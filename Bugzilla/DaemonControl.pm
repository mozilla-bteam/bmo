package Bugzilla::DaemonControl;
use 5.10.1;
use strict;
use warnings;

use Cwd qw(realpath);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir catfile);
use Future;
use Future::Utils qw(repeat try_repeat);
use IO::Async::Loop;
use IO::Async::Process;
use IO::Async::Signal;
use IO::Async::Protocol::LineStream;
use LWP::Simple qw(get);
use POSIX qw(setsid WEXITSTATUS);

use base qw(Exporter);

our @EXPORT_OK = qw(
    run_httpd run_gollum run_gollum_and_httpd
    catch_signal on_finish on_exception
    assert_httpd assert_gollum assert_database
);

our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
    start => [grep /^run_/, @EXPORT_OK],
    utils => [qw(catch_signal on_exception on_finish)],
);


use constant DOCKER_SUPPORT_DIR => realpath(catdir(dirname(__FILE__), '..', 'docker_support'));

use constant HTTPD_BIN     => '/usr/sbin/httpd';
use constant HTTPD_CONFIG  => catfile( DOCKER_SUPPORT_DIR, 'httpd.conf' );
use constant GOLLUM_BIN    => '/usr/local/bin/gollum';
use constant GOLLUM_CONFIG => catfile( DOCKER_SUPPORT_DIR, 'gollum.conf' );

sub catch_signal {
    my ($name, $rc)   = @_;
    my $loop     = IO::Async::Loop->new;
    my $signal_f = $loop->new_future;
    my $signal   = IO::Async::Signal->new(
        name       => $name,
        on_receipt => sub {
            $signal_f->done($rc);
        }
    );
    $signal_f->on_cancel(
        sub {
            my $l = IO::Async::Loop->new;
            $l->remove($signal);
        },
    );

    $loop->add($signal);

    return $signal_f;
}

sub run_gollum {
    my $loop   = IO::Async::Loop->new;
    my $exit_f = $loop->new_future;
    my $gollum = IO::Async::Process->new(
        command   => [
            GOLLUM_BIN,
            '-n' => 1,
            '-p' => '/tmp/gollum.pid',
            '-lc' => 'never',
            '-ll' => 0,
             '-c' => GOLLUM_CONFIG
        ],
        on_finish => on_finish($exit_f),
        on_exception => on_exception( "gollum", $exit_f ),
    );
    $loop->add($gollum);
    $exit_f->on_cancel( sub { $gollum->kill('TERM') } );

    return $exit_f;
}

sub run_httpd {
    my (@args) = @_;
    my $loop = IO::Async::Loop->new;

    my $exit_f = $loop->new_future;
    my $httpd  = IO::Async::Process->new(
        code => sub {
            # we have to setsid() to make a new process group
            # or else apache will kill its parent.
            setsid();
            exec HTTPD_BIN, '-DFOREGROUND', '-f' => HTTPD_CONFIG, @args;
        },
        on_finish    => on_finish($exit_f),
        on_exception => on_exception( 'httpd', $exit_f ),
    );
    $exit_f->on_cancel( sub { $httpd->kill('TERM') } );
    $loop->add($httpd);

    return $exit_f;
}

sub run_gollum_and_httpd {
    my @httpd_args = @_;

    # If we're behind a proxy and the urlbase says https, we must be using https.
    # * basically means "I trust the load balancer" anyway.
    my $lc = Bugzilla::Install::Localconfig::read_localconfig();
    if ( ($lc->{inbound_proxies} // '') eq '*' && $lc->{urlbase} =~ /^https/) {
        push @httpd_args, '-DHTTPS';
    }
    push @httpd_args, '-DGOLLUM';
    my $gollum_exit_f = run_gollum();
    my $signal_f      = catch_signal("TERM", 0);
    return assert_gollum()->then(
        sub {
            warn "start httpd";
            my $httpd_exit_f = run_httpd(@httpd_args);
            Future->wait_any($gollum_exit_f, $httpd_exit_f, $signal_f);
        }
    );
}

# our gollum listens 5880 tcp/udp, and 5881 tcp.
# 5881 sends an ACK message back to faciliate this "is running" check
# which hopefully ensures it is running before starting apache.
sub assert_gollum {
    my $loop = IO::Async::Loop->new;
    my $repeat = repeat {
        my $gollum_status_f = $loop->new_future;
        my $stream = IO::Async::Protocol::LineStream->new(
            on_read_line => sub {
                my ($self, $line) = @_;
                warn "check\n";
                $gollum_status_f->done( $line =~ /^gollum OK/ );
            }
        );
        $loop->add($stream);
        my $socket_f = $stream->connect(
            socktype  => 'stream',
            host    => '127.0.0.1',
            service => 5881,
        );
        return $socket_f->then(
            sub {
                $stream->write(__PACKAGE__ . "\n")->then(
                    sub {
                        Future->wait_any(
                            $gollum_status_f,
                            delay_future_value(after => 1, value => 0)
                        );
                    }
                );
            }
        )->else(sub {
            delay_future_value(after => 1, value => 0);
        });
    } until => sub { shift->get };
    my $timeout = $loop->timeout_future(after => 20);
    return Future->wait_any($repeat, $timeout);
}

sub delay_future_value {
    my (%param) = @_;
    my $loop = IO::Async::Loop->new;
    my $value = delete $param{value};
    return $loop->delay_future(%param)->then(sub { $loop->new_future->done($value) });
}

sub assert_httpd {
    my $loop = IO::Async::Loop->new;
    my $port  = $ENV{PORT} // 8000;
    my $repeat = repeat {
        $loop->delay_future(after => 0.25)->then(
            sub {
                Future->wrap(get("http://localhost:$port/__lbheartbeat__") // '');
            },
        );
    } until => sub {
        my $f = shift;
        ( $f->get =~ /^httpd OK/ );
    };
    my $timeout = $loop->timeout_future(after => 20);
    return Future->wait_any($repeat, $timeout);
}

sub assert_database {
    my $loop = IO::Async::Loop->new;
    my $lc   = Bugzilla::Install::Localconfig::read_localconfig();

    for my $var (qw(db_name db_host db_user db_pass)) {
        return $loop->new_future->die("$var is not set!") unless $lc->{$var};
    }

    my $dsn    = "dbi:mysql:database=$lc->{db_name};host=$lc->{db_host}";
    my $repeat = repeat {
        $loop->delay_future( after => 0.25 )->then(
            sub {
                my $dbh = DBI->connect(
                    $dsn,
                    $lc->{db_user},
                    $lc->{db_pass},
                    { RaiseError => 0, PrintError => 0 },
                );
                Future->wrap($dbh);
            }
        );
    }
    until => sub { defined shift->get };
    my $timeout = $loop->timeout_future( after => 20 );
    my $any_f = Future->needs_any( $repeat, $timeout );
    return $any_f->transform(
        done => sub { return },
        fail => sub { "unable to connect to $dsn as $lc->{db_user}" },
    );
}

sub on_finish {
    my ($f) = @_;
    return sub {
        my ($self, $exitcode) = @_;
        $f->done(WEXITSTATUS($exitcode));
    };
}

sub on_exception {
    my ( $name, $f ) = @_;
    return sub {
        my ( $self, $exception, $errno, $exitcode ) = @_;

        if ( length $exception ) {
            $f->fail( "$name died with the exception $exception " . "(errno was $errno)\n" );
        }
        elsif ( ( my $status = WEXITSTATUS($exitcode) ) == 255 ) {
            $f->fail("$name failed to exec() - $errno\n");
        }
        else {
            $f->fail("$name exited with exit status $status\n");
        }
    };
}

1;
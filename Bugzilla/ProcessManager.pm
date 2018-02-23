package Bugzilla::ProcessManager;
use 5.10.1;
use strict;
use warnings;

use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir catfile);
use Cwd qw(realpath);
use IO::Async::Loop;
use IO::Async::Process;
use IO::Async::Signal;
use POSIX qw(setsid WEXITSTATUS);

use constant DOCKER_SUPPORT_DIR => realpath(catdir(dirname(__FILE__), '..', 'docker_support'));

use constant HTTPD_BIN    => '/usr/sbin/httpd';
use constant HTTPD_CONFIG => catfile(DOCKER_SUPPORT_DIR, 'httpd.conf');

use constant GOLLUM_BIN    => '/usr/local/bin/gollum';
use constant GOLLUM_CONFIG => catfile( DOCKER_SUPPORT_DIR, 'gollum.conf' );

sub catch_signal {
    my ($class, $name)  = @_;
    my $loop     = IO::Async::Loop->new;
    my $signal_f = $loop->new_future;
    my $signal = IO::Async::Signal->new(
        name       => $name,
        on_receipt => sub {
            $signal_f->done( "signal", $name );
        }
    );
    $signal_f->on_cancel(
        sub {
            my $l = IO::Async::Loop->new;
            $l->remove($signal);
        },
    )

    $loop->add($signal);

    return $signal_f;
}

sub start_gollum {
    my ($class) = @_;
    my $loop = IO::Async::Loop->new;
    my $exit_f = $loop->new_future;
    my $gollum = IO::Async::Process->new(
        command      => [ GOLLUM_BIN, '-c', GOLLUM_CONFIG ],
        on_finish    => on_finish($exit_f),
        on_exception => on_exception( "gollum", $exit_f ),
    );
    $loop->add($gollum);
    $exit_f->on_cancel(sub { $gollum->kill('TERM') });

    my $run_f = $loop->new_future;
    my $count = 60;
    my $timer = IO::Async::Timer::Periodic->new(
        interval => 1,
        on_tick => sub {
            my ($self) = @_;
            if ($gollum->is_running || $exit_f->is_ready) {
                $run_f->done($exit_f);
                $self->stop;
            }
            elsif ($count-- <= 0) {
                $run_f->fail("gollum never started");
                $self->stop;
            }
        },
    );
    $timer->start;
    $loop->add($timer);


    return $run_f;
}

sub start_httpd {
    my ($class, @args) = @_;
    my $loop = IO::Async::Loop->new;

    my $exit_f = $loop->new_future;
    my $httpd = IO::Async::Process->new(
        code => sub {
            # we have to setsid() to make a new process group
            # or else apache will kill its parent.
            setsid();
            exec HTTPD_BIN,
                '-DFOREGROUND',
                '-f' => HTTPD_CONFIG,
                @args;
        },
        on_finish => on_finish('httpd', $exit_f),
        on_exception => on_exception('httpd', $exit_f),
    );
    $loop->add($httpd);
    $exit_f->on_cancel(sub { $httpd->kill('TERM') });

    return $exit_f;
}

sub on_finish {
    my ($name, $f) = @_;
    return sub {
        my ($self, $exitcode) = @_;
        $f->done($name, WEXITSTATUS($exitcode));
    };
}

sub on_exception {
    my ($name, $f) = @_;
    return sub {
        my ( $self, $exception, $errno, $exitcode ) = @_;

        if ( length $exception ) {
            $f->fail("$name died with the exception $exception " . "(errno was $errno)\n");
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

#!/usr/bin/env perl
use 5.10.1;
use strict;
use warnings;
use autodie qw(:all);
use lib qw(. lib local/lib/perl5);

use Try::Tiny;
use MIME::QuotedPrint qw(decode_qp);
use Carp;
use Test::More 1.302;

use constant DRIVER => $ENV{TEST_LOCAL} ? 'Test::Selenium::Chrome' : 'Test::Selenium::Remote::Driver';

BEGIN {
    plan skip_all => 'these tests only run in CI' unless $ENV{CI} && $ENV{CIRCLE_JOB} eq 'test_bmo'
};

use ok DRIVER;

my $ADMIN_USER = $ENV{BZ_TEST_ADMIN} // 'admin@example.test';
my $ADMIN_PASS = $ENV{BZ_TEST_ADMIN_PASS} // 'Te6Oovohch';

my @require_env = qw(
    BZ_BASE_URL
    BZ_TEST_NEWBIE
    BZ_TEST_NEWBIE_PASS
);

if (DRIVER =~ /Remote/) {
    push @require_env, qw( TWD_HOST TWD_PORT );
}
my @missing_env = grep { ! exists $ENV{$_} } @require_env;
BAIL_OUT("Missing env: @missing_env") if @missing_env;

try {
    my $sel = DRIVER->new(base_url => $ENV{BZ_BASE_URL});
    $sel->set_implicit_wait_timeout(6000);

    login_ok($sel, $ADMIN_USER, $ADMIN_PASS);
    test_securemail(
        $sel,
        sub { set_securemail($sel, PUBKEY()) },
        sub {
            my $msg = shift;
            my $expected_msg = INTRO_MSG();
            is(length($msg), length($expected_msg), 'check message length');
            is($msg, $expected_msg, 'check message content');
        },
    );

    logout_ok($sel);
    system('perl checksetup.pl --no-template --make-admin=' . $ENV{BZ_TEST_NEWBIE} . ' >&2 ');
    login_ok($sel, $ENV{BZ_TEST_NEWBIE}, $ENV{BZ_TEST_NEWBIE_PASS});

    test_securemail(
        $sel,
        sub { make_secure_bug($sel) },
        sub {
            my $msg = shift;
            like($msg, qr/Subject:\s+\[Bug \d+\]\s+New:\s+Some Bug/, "check subject");
            like($msg, qr/Group:\s+core-security/, "check that it is in core-security");
            like($msg, qr/I like pie/, "check that pie is appreciated");
        },
    );
} catch {
    fail("got exception $_");
};

done_testing();

sub make_secure_bug {
    my ($sel) = @_;
    $sel->get_ok("/enter_bug.cgi?format=__default__&product=Firefox");
    $sel->title_is("Enter Bug: Firefox");
    click_and_type($sel, "short_desc", "Some Bug");
    click_and_type($sel, "comment", "I like pie");

    my $group = $sel->find_element(qq{//*[\@id="bugzilla-body"]//*[\@for="group_core-security"]}, 'xpath');
    $group->click();
    my $advanced = $sel->find_element(q{//*[@id="expert_fields_controller"]}, 'xpath');
    $advanced->click();
    click_and_type($sel, "assigned_to", $ADMIN_USER);
    submit($sel, '//input[@value="Submit Bug"]');
    $sel->title_like(qr/Some Bug/, "submitted some bug");
    sleep 10;

}

sub test_securemail {
    my ($sel, $code, $test) = @_;
    truncate '/app/data/mailer.testfile', 0;
    $code->();
    local $_ = undef;
    open my $in, '<', '/app/data/mailer.testfile';
    open my $out, '>', '/tmp/gpg-message.gpg';
    my $found_pgp = 0;
    my @junk;
    while ($_ = <$in>) {
        if (m{-----BEGIN PGP MESSAGE-----} .. m{-----END PGP MESSAGE-----}) {
            $found_pgp = 1;
            $out->print(decode_qp($_));
        }
        else {
            push @junk, $_;
        }
    }
    $in->close;
    $out->close;
    if ($found_pgp) {
        system 'gpg --decrypt < /tmp/gpg-message.gpg 2>/dev/null > /tmp/gpg-message.txt';
        ok(-f '/tmp/gpg-message.txt', 'message file exists');
        my $msg = slurp('/tmp/gpg-message.txt');
        $test->($msg);
    }
    else {
        diag @junk;
        fail("Did not see PGP block");
    }
}

sub login {
    my ($sel, $login, $password) = @_;

    $sel->get_ok('/login');
    $sel->title_is('Log in to Bugzilla');
    click_and_type($sel, 'Bugzilla_login', $login);
    click_and_type($sel, 'Bugzilla_password', $password);
    submit($sel, '//*[@id="bugzilla-body"]//input[@name="GoAheadAndLogIn"]');
}

sub login_ok {
    my ($sel, $login, $pass) = @_;
    login($sel, $login, $pass);
    $sel->title_is('Bugzilla Main Page');
}

sub logout_ok {
    my ($sel) = @_;
    $sel->get_ok('/index.cgi?logout=1');
    $sel->title_is('Logged Out');
}


sub submit {
    my ($sel, $xpath) = @_;
    $sel->find_element($xpath, 'xpath')->submit();
}

sub click_and_type {
    my ($sel, $name, $text) = @_;
    confess "no text" unless $text;

    try {
        my $el = $sel->find_element(qq{//*[\@id="bugzilla-body"]//*[\@name="$name"]}, 'xpath');
        $el->click();
        $el->clear();
        $el->send_keys($text);
        pass("found $name and typed $text");
    } catch {
        fail("failed to find $name");
    };
}

sub click_link {
    my ($sel, $text) = @_;
    my $el = $sel->find_element($text, 'link_text');
    $el->click();
}

sub set_securemail {
    my ($sel, $pub_key) = @_;
    $sel->get_ok('/userprefs.cgi?tab=securemail');
    $sel->title_is('User Preferences');
    click_and_type($sel, 'public_key', $pub_key);
    submit($sel, '//input[@value="Submit Changes"]');
}

sub INTRO_MSG {
    my $s = <<"EOF";
Congratulations! If you can read this, then your SecureMail encryption\r
key uploaded to Bugzilla is working properly.\r
\r
To update your SecureMail preferences at any time, please go to:\r
$ENV{BZ_BASE_URL}/userprefs.cgi?tab=securemail\r
\r
Sincerely,\r
Your Friendly Bugzilla Administrator
EOF
    chomp $s;
    return $s;
}

sub PUBKEY { slurp('/app/t/bmo/admin-public-key') }

sub slurp {
    my ($file) = @_;
    local $/ = undef;
    open my $fh, '<', $file;
    my $s = <$fh>;
    close $fh;
    return $s;
}


# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.
package Bugzilla::JobQueue::Forker;

use 5.10.1;
use Moo;

use Bugzilla::JobQueue;
use Module::Runtime qw(require_module);
use IO::Async::Process;
use IO::Async::Loop;

sub run {
    my ($self) = @_;
    my $loop = IO::Async::Loop->new;

    my $jq = Bugzilla->job_queue();
    foreach my $module (values %{ Bugzilla::JobQueue->job_map() }) {
        require_module($module);
        $jq->can_do($module);
    }

    foreach (1..10) {
         $self->_spawn();
    }

    $loop->run;
}

sub _spawn {
    my ($self) = @_;

    my $loop = IO::Async::Loop->new;
    my $future = $loop->new_future;
    my $worker = IO::Async::Process->new(
        code => sub {
            my $jq = Bugzilla->job_queue;
            $jq->work_until_done;
            exit 0;
        },
        on_finish => sub {
            my ($self, $exitcode) = @_;
            if ($exitcode == 0) {
                $future->done(1);
            }
            else {
                $future->die("bad exit code: $exitcode");
            }
        },
        on_exception => sub {
            my ($self, $exception, $errno, $exitcode) = @_;
            $future->fail($exception);
        },
    );

    $loop->add($worker);

    $future->on_ready(
        sub {
            my ($f) = @_;
            if ($f->is_done) {
                $self->_spawn();
            }
            elsif ($f->is_failed) {
                my ($error, @details) = $f->failure;
                warn "error: $error\n";
            }
            elsif ($f->is_cancelled) {
                warn "canceled _spawn()\n";
            }
        }
    );

    return ($worker, $future);
}


1;
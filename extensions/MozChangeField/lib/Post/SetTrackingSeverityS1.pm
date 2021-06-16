# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::MozChangeField::Post::SetTrackingSeverityS1;

use 5.10.1;
use Moo;
use Mojo::JSON qw(decode_json);
use Mojo::Util qw(dumper);

use Bugzilla::Logging;
use Bugzilla::Extension::TrackingFlags::Flag::Bug;

use constant PD_ENDPOINT => 'https://product-details.mozilla.org/1.0/';

sub evaluate_create {
  my ($self, $args) = @_;
  my $bug       = $args->{bug};
  my $timestamp = $args->{timestamp};

  if ($bug->bug_severity eq 'S1') {
    my $cache    = Bugzilla->request_cache->{tracking_flags_create_params};
    my $versions = _fetch_product_version_file();
    my $nightly  = 'cf_tracking_firefox' . $versions->{nightly};
    my $beta     = 'cf_tracking_firefox' . $versions->{beta};

    my $tracking_flags
      = Bugzilla::Extension::TrackingFlags::Flag->match({
      bug_id => $bug->id, is_active => 1,
      });

    foreach my $flag (@{$tracking_flags}) {

      # Only interested in nightly and beta flags
      my $flag_name = $flag->name;
      next if $flag_name ne $nightly && $flag_name ne $beta;

      # Only interested in flags not set to +
      my $flag_value = $cache->{$flag_name} || $flag->bug_flag->value;
      next if $flag_value eq '?'            || $flag_value eq '+';

      if ($flag_value eq '-') {
        $flag->bug_flag->remove_from_db();
        delete $cache->{$flag_name};
      }

      Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
        tracking_flag_id => $flag->flag_id, bug_id => $bug->id, value => '?',
      });

      # Update the name/value pair in the bug object
      $bug->{$flag_name} = '?';
    }
  }
}

sub evaluate_change {
  my ($self, $args) = @_;
  my ($bug, $old_bug, $timestamp, $changes)
    = @$args{qw(bug old_bug timestamp changes)};

  if ( $changes
    && exists $changes->{bug_severity}
    && $changes->{bug_severity}->[1] eq 'S1')
  {
    my $versions = _fetch_product_version_file();
    my $nightly  = 'cf_tracking_firefox' . $versions->{nightly};
    my $beta     = 'cf_tracking_firefox' . $versions->{beta};

    my $tracking_flags
      = Bugzilla::Extension::TrackingFlags::Flag->match({
      bug_id => $bug->id, is_active => 1,
      });

    my $product_id   = $bug->product_id;
    my $component_id = $bug->component_id;
    my $is_visible   = sub {
      $_->product_id == $product_id
        && (!$_->component_id || $_->component_id == $component_id);
    };

    foreach my $flag (@$tracking_flags) {
      my $flag_name = $flag->name;

      # Only interested in nightly and beta flags
      next if $flag_name ne $nightly && $flag_name ne $beta;

      my $new_value = $bug->$flag_name;
      my $old_value = $old_bug->$flag_name;

      # Only interested in flags not set to + or ? or changed to + or ?
      next if $new_value eq $old_value && ($old_value eq '+' || $old_value eq '?');
      next if $new_value ne $old_value && $new_value eq '?';

      # Do not change if the user cannot set the flag to ?
      next if !$flag->can_set_value('?');

      if ($old_value eq '---') {
        Bugzilla::Extension::TrackingFlags::Flag::Bug->create({
          tracking_flag_id => $flag->flag_id, bug_id => $bug->id, value => '?',
        });
      }
      else {
        $flag->bug_flag->set_value('?');
        $flag->bug_flag->update($timestamp);
      }

      $changes->{$flag_name} = [$old_value, '?'];

      # Update the name/value pair in the bug object
      $old_bug->{$flag_name} = '?';
      $bug->{$flag_name} = '?';
    }
  }
}

sub _fetch_product_version_file {
  my $key      = "firefox_versions";
  my $versions = Bugzilla->request_cache->{$key}
    || Bugzilla->memcached->get_data({key => $key});

  unless ($versions) {
    my $ua = Mojo::UserAgent->new;
    if (my $proxy_url = Bugzilla->params->{'proxy_url'}) {
      $ua->proxy->http($proxy_url);
    }

    my $response = $ua->get(PD_ENDPOINT . $key . '.json')->result;
    $versions = Bugzilla->request_cache->{$key}
      = $response->is_success ? decode_json($response->body) : {};
    Bugzilla->memcached->set_data({
      key   => $key,
      value => $versions,

      # Cache for 30 minutes if the data is available, otherwise retry in 5 min
      expires_in => $response->is_success ? 1800 : 300,
    });
  }

  my ($nightly) = split /\./, $versions->{FIREFOX_NIGHTLY};
  my ($beta)    = split /\./, $versions->{LATEST_FIREFOX_RELEASED_DEVEL_VERSION};
  return {nightly => $nightly, beta => $beta};
}

1;

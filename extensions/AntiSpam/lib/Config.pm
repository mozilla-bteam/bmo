# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AntiSpam::Config;

use 5.10.1;
use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Group;

our $sortkey = 511;

sub get_param_list {
  my ($class) = @_;

  my @param_list = (
    {
      name    => 'antispam_spammer_exclude_group',
      type    => 's',
      choices => \&get_all_group_names,
      default => 'canconfirm',
      checker => \&check_group
    },
    {
      name    => 'antispam_spammer_comment_count',
      type    => 't',
      default => '3',
      checker => \&check_numeric
    },
    {
      name    => 'antispam_spammer_disable_text',
      type    => 'l',
      default => "This account has been automatically disabled as a result of "
        . "a high number of spam comments.<br>\n<br>\n"
        . "Please contact the address at the end of this message if "
        . "you believe this to be an error."
    },
    {
      name    => 'antispam_abusive_comment_count',
      type    => 't',
      default => '5',
      checker => \&check_numeric
    },
    {
      name    => 'antispam_abusive_disable_text',
      type    => 'l',
      default => "This account has been automatically disabled as a result of "
        . "a high number of comments tagged as abusive.<br>\n<br>\n"
        . "All interactions on Bugzilla should follow our "
        . "<a href=\"https://bugzilla.mozilla.org/page.cgi?id=etiquette.html\">"
        . "etiquette guidelines</a>.<br>\n<br>\n"
        . "Please contact the address at the end of this message if you "
        . "believe this to be an error, or if you would like your account "
        . "reactivated in order to interact within our etiquette "
        . "guidelines."
    },
    {
      name    => 'antispam_multi_user_limit_age',
      type    => 't',
      default => '2',
      checker => \&check_numeric,
    },
    {
      name    => 'antispam_multi_user_limit_count',
      type    => 't',
      default => '5',
      checker => \&check_numeric,
    },
  );

  return @param_list;
}

1;

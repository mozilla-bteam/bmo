#!/usr/bin/env perl
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

use 5.10.1;
use strict;
use warnings;

use lib qw(. lib local/lib/perl5);

use Bugzilla;
use Bugzilla::Util qw(html_quote);

my $cgi = Bugzilla->cgi;

print $cgi->header(-type => 'text/html', -charset => 'utf-8');

print <<'HTML';
<!DOCTYPE html>
<html>
<head>
<title>Request Headers</title>
<style>
  body { font-family: monospace; padding: 20px; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; vertical-align: top; white-space: nowrap;}
  th { background: #eee; font-weight: bold; }
  tr:nth-child(even) { background: #f9f9f9; }
</style>
</head>
<body>
<h1>Request Headers</h1>
<table>
<thead><tr><th>Header</th><th>Value</th></tr></thead>
<tbody>
HTML

for my $key (sort $cgi->http()) {
  my $value = $cgi->http($key) // '';
  (my $name = $key) =~ s/^HTTP_//;
  $name = join('-', map { ucfirst(lc($_)) } split(/_/, $name));
  $name = html_quote($name);
  $value = html_quote($value);
  print "<tr><td>$name</td><td>$value</td></tr>\n";
}

print <<'HTML';
</tbody>
</table>
</body>
</html>
HTML

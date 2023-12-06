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

use Test::More;

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Net::Google;
use Bugzilla::Net::S3;

Bugzilla->usage_mode(USAGE_MODE_TEST);
Bugzilla->error_mode(ERROR_MODE_DIE);

# Create S3 instance using s3ninja
# The client ID and secret will always be the same each run
my $storage = Bugzilla::Net::S3->new(
  client_id  => 'AKIAIOSFODNN7EXAMPLE',
  secret_key => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  bucket     => 'attachments',
  host       => 's3',
);

# Is this S3 instance?
ok($storage->data_type eq 's3', 'Data type is S3');

# Test adding of data to the bucket
ok(
  $storage->add_key('somekey', 'somedata'),
  'Add data to attachments bucket successfully'
);

# Check if the key exists
ok($storage->head_key('somekey'),
  'The key exists in the storage attachments bucket');

# Test retrieving the data
my $result = $storage->get_key('somekey');
ok($result eq 'somedata',
  'Retrieved data from attachments bucket successfully');

# Test deleting the data
ok($storage->delete_key('somekey'),
  'Deleted data in the attachments bucket successfully');

# Make sure the data is deleted
ok(!$storage->head_key('somekey'),
  'The key no longer exists in the attachments bucket');

# Create Google instance using fake-gcs-server
$storage = Bugzilla::Net::Google->new(
  bucket          => 'attachments',
  host            => 'gcs',
  service_account => 'test',
);

# Is this Google instance?
ok($storage->data_type eq 'google', 'Data type is Google');

# Test adding of data to the bucket
ok(
  $storage->add_key('somekey', 'somedata'),
  'Add data to attachments bucket successfully'
);

# Check if the key exists
ok($storage->head_key('somekey'),
  'The key exists in the storage attachments bucket');

# Test retrieving the data
$result = $storage->get_key('somekey');
ok($result eq 'somedata',
  'Retrieved data from attachments bucket successfully');

# Test deleting the data
ok($storage->delete_key('somekey'),
  'Deleted data in the attachments bucket successfully');

# Make sure the data is deleted
ok(!$storage->head_key('somekey'),
  'The key no longer exists in the attachments bucket');

done_testing;


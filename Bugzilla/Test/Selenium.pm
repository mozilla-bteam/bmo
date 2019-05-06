# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Test::Selenium;

use 5.10.1;
use Bugzilla::Logging;
use Bugzilla::Util qw(trim);
use Moo;
use Test2::V0;
use Test::Selenium::Remote::Driver;
use Try::Tiny;

has 'driver_class' => (is => 'ro', default => 'Test::Selenium::Remote::Driver');
has 'driver_args' => (is => 'ro', required => 1,);
has 'driver'      => (
  is      => 'lazy',
  handles => [qw(
      add_cookie
      alert_text_like
      get_all_cookies
      get_ok
      get_title
      go_back_ok
      title_is
      title_like
      )],
);

sub click_ok {
  my ($self, $locator, $arg1, $desc) = @_;
  $arg1 ||= 'undefined';
  $desc ||= "Click ok: $locator";
  DEBUG("click_ok: $locator, $arg1, $desc");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    DEBUG("click_ok new locator: $locator");
  }
  $self->driver->click_element_ok($locator, 'xpath', $arg1, $desc);
}

sub open_ok {
  my ($self, $arg1, $arg2, $name) = @_;
  $arg2 ||= 'undefined';
  DEBUG("open_ok: $arg1, $arg2, $name");
  $self->get_ok($arg1, $name);
}

sub type_ok {
  my ($self, $locator, $text, $desc) = @_;
  $desc ||= '';
  DEBUG("type_ok: $locator, $text, $desc");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
    if (!$element) {
      ok(0, $desc);
      return;
    }
  }
  $element->clear();    # Some fields have a default value
  $self->driver->type_element_ok($locator, 'xpath', $text, $desc);
}

sub wait_for_page_to_load_ok {
  my ($self, $timeout) = @_;
  DEBUG("wait_for_page_to_load_ok: $timeout");
  ok($self->driver->set_timeout('page load', $timeout),
    "Wait for page to load: $timeout");
}

sub wait_for_page_to_load {
  my ($self, $timeout) = @_;
  DEBUG("wait_for_page_to_load: $timeout");
  $self->driver->set_timeout('page load', $timeout);
}

sub is_text_present {
  my ($self, $text) = @_;
  DEBUG("is_text_present: $text");
  return 0 unless $text;
  my $body = $self->driver->get_body();
  if ($text =~ /^regexp:(.*)$/) {
    return $body =~ /$1/ ? 1 : 0;
  }
  my $index = index $body, $text;
  return ($index >= 0) ? 1 : 0;
}

sub is_text_present_ok {
  my ($self, $text) = @_;
  DEBUG("is_text_present_ok: $text");
  ok($self->is_text_present($text), "Text is present: $text");
}

sub find_element {
  my ($self, $locator, $method) = @_;
  $method ||= 'xpath';
  DEBUG("find_element: $locator $method");
  try {
    return $self->driver->find_element($locator, $method);
  }
  catch {
    return undef;
  };
}

sub is_element_present {
  my ($self, $locator) = @_;
  DEBUG("is_element_present: $locator");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  return $element;
}

sub is_element_present_ok {
  my ($self, $locator) = @_;
  DEBUG("is_element_present_ok: $locator");
  ok($self->is_element_present($locator), "Element is present: $locator");
}

sub is_enabled {
  my ($self, $locator) = @_;
  DEBUG("is_enabled: $locator");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  return $element && $element->is_enabled ? 1 : 0;
}

sub is_selected {
  my ($self, $locator) = @_;
  DEBUG("is_selected: $locator");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  return $element && $element->is_selected ? 1 : 0;
}

sub get_body_text {
  my ($self) = @_;
  DEBUG('get_body_text');
  return $self->driver->get_body();
}

sub get_value {
  my ($self, $locator) = @_;
  DEBUG("get_value: $locator");
  $locator = $self->_fix_locator($locator, 'name');
  my $element = $self->find_element($locator);
  if ($element) {
    return $element->get_value();
  }
  return '';
}

sub get_text {
  my ($self, $locator) = @_;
  DEBUG("get_text: $locator");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if ($element) {
    return $element->get_text();
  }
  return '';
}

sub selected_label_is {
  my ($self, $id, $label) = @_;
  DEBUG("selected_label_is: $id, $label");
  my $locator = qq{//select[\@id="$id"]};
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  my @options;
  try {
    @options = $self->driver->find_elements($locator . '/option');
  };
  foreach my $option (@options) {
    my $text = trim($option->get_text());
    if ($text eq $label
        && $option->get_property('selected'))
    {
      ok(1, "Selected label is: $label");
      return;
    }
  }
  ok(0, "Selected label is: $label");
}

sub get_selected_labels {
  my ($self, $locator) = @_;
  DEBUG("get_selected_labels: $locator");
  $locator = $self->_fix_locator($locator);
  my @elements;
  try {
    @elements = $self->driver->find_elements($locator . '/option');
  };
  if (@elements) {
    my @selected;
    foreach my $element (@elements) {
      next if !$element->is_selected();
      push @selected, $element->get_text();
    }
    return @selected;
  }
  return undef;
}

sub get_select_options {
  my ($self, $locator) = @_;
  DEBUG("get_select_options: $locator");
  $locator = $self->_fix_locator($locator);
  my @elements;
  try {
    @elements = $self->driver->find_elements($locator . '/option');
  };
  if (@elements) {
    my @options;
    foreach my $element (@elements) {
      push @options, $element->get_text();
    }
    return @options;
  }
  return undef;
}

sub remove_all_selections {
  my ($self, $id) = @_;
  DEBUG("remove_all_selections: $id");
  $self->driver->execute_script('document.getElementById(arguments[0]).selectedIndex = -1;', $id);
  return 1;
}

sub remove_all_selections_ok {
  my ($self, $id) = @_;
  DEBUG("remove_all_selections_ok: $id");
  ok($self->remove_all_selections($id), "Remove all selections ok: $id");
}

sub is_checked {
  my ($self, $locator) = @_;
  DEBUG("is_checked: $locator");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  if ($element) {
    return $element->is_selected() ? 1 : 0;
  }
  return 0;
}

sub is_checked_ok {
  my ($self, $locator) = @_;
  DEBUG("is_checked_ok: $locator");
  ok($self->is_checked($locator), "Is checked: $locator");
}

sub select_ok {
  my ($self, $locator, $label) = @_;
  DEBUG("select_ok: $locator, $label");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  my @options;
  try {
    @options = $self->driver->find_elements($locator . '/option');
  };
  my ($is_label, $is_value);
  if ($label =~ /^label=(.*)$/) {
    $label = $1;
    $is_label = 1;
  }
  elsif ($label =~ /^value=(.*)$/) {
    $label = $1;
    $is_value = 1;
  }
  foreach my $option (@options) {
    my $value;
    if ($is_label) {
      $value = $option->get_text();
    }
    elsif ($is_value) {
      $value = $option->get_value();
    }
    else {
      $value = $option->get_text();
    }
    $value = trim($value);
    if ($value eq $label) {
      if ($option->get_property('selected')) {
        ok(1, "Set selected: $label");
      }
      else {
        ok($option->click(), "Set selected: $label");
      }
      return;
    }
  }
  ok(0, "Set selected: $label");
}

sub check_ok {
  my ($self, $locator) = @_;
  DEBUG("check_ok: $locator");
  ok($self->_toggle_check($locator, 1), "Check OK: $locator");
}

sub uncheck_ok {
  my ($self, $locator) = @_;
  DEBUG("uncheck_ok: $locator");
  ok($self->_toggle_check($locator, 0), "Uncheck OK: $locator");
}

sub get_location {
  my ($self) = @_;
  DEBUG('get_location');
  return $self->driver->get_current_url();
}

sub value_is {
  my ($self, $locator, $value) = @_;
  DEBUG("value_is: $locator $value");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  # checkboxes
  if ($value eq 'on') {
    ok($element->is_selected(), 'Value is on');
  }
  elsif ($value eq 'off') {
    ok(!$element->is_selected(), 'Value is off');
  }
  else {
    # other
    ok($element->get_value() eq $value, "Value is: $value");
  }
}

sub get_attribute {
  my ($self, $locator) = @_;
  DEBUG("get_attribute: $locator");
  my $attr;
  ($locator, $attr) = ($locator =~ /(.*)@([^@]+)$/);
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if ($element) {
    return $element->get_attribute($attr);
  }
  return undef;
}

sub submit {
  my ($self, $locator) = @_;
  DEBUG("submit: $locator");
  $locator = $self->_fix_locator($locator);
  $self->find_element($locator)->submit();
}

sub is_editable {
  my ($self, $locator) = @_;
  DEBUG("is_editable: $locator");
  $locator = $self->_fix_locator($locator);
  my $element = $self->find_element($locator);
  if ($element) {
    DEBUG("is_editable found element");
    return $element->is_enabled() ? 1 : 0;
  }
  return 0;
}

sub is_editable_ok {
  my ($self, $locator) = @_;
  DEBUG("is_editable_ok: $locator");
  ok($self->is_editable($locator), "Is editable: $locator");
}

sub attach_file {
  my ($self, $locator, $filename) = @_;
  $self->type_ok('att-textarea', _read_file($filename), 'Add attachment data');
}

# Private Helpers

sub _build_driver {
  my ($self) = @_;
  $self->driver_class->new(%{$self->driver_args});
}

sub _fix_locator {
  my ($self, $locator, $type) = @_;
  $type ||= 'id';
  DEBUG("_fix_locator old: $locator type: $type");
  if ($locator =~ /^link=(.*)$/) {
    $locator = qq{//a[normalize-space(text())="$1"]};
  }
  if ($locator =~ /^name=(.*)$/) {
    $locator = qq{//input[\@name="$1"]};
  }
  if ($locator !~ /^\/\//) {
    $locator = qq{//*[\@$type="$locator"]};
  }
  DEBUG("_fix_locator new: $locator");
  return $locator;
}

sub _toggle_check {
  my ($self, $locator, $check) = @_;
  $locator = $self->_fix_locator($locator, 'id');
  my $element = $self->find_element($locator);
  if (!$element) {
    $locator =~ s/\@id/\@name/;
    $element = $self->find_element($locator);
  }
  if ($element) {
    if (($check && !$element->is_selected) || (!$check && $element->is_selected)) {
      $element->toggle();
    }
    return 1;
  }
  return 0;
}

sub _read_file {
  my ($filename) = @_;
  my $fh = IO::File->new($filename, 'r');
  $fh || die "Could not open file $filename: $!";
  my $content;
  { local $/; $content = <$fh> }
  $fh->close() || die "Could not close file $filename: $!";
  return $content;
}

1;

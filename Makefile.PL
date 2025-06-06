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

use File::Basename;
use File::Spec;

BEGIN {
  require lib;
  my $dir = File::Spec->rel2abs(dirname(__FILE__));
  lib->import(
    $dir,
    File::Spec->catdir($dir, 'lib'),
    File::Spec->catdir($dir, qw(local lib perl5))
  );
}

use ExtUtils::MakeMaker 7.22;
use File::Basename;
use File::Spec;
use English qw(-no_match_vars $OSNAME);

BEGIN {
  if ($ENV{BZ_SILENT_MAKEFILE}) {
    open STDOUT, '>>', File::Spec->devnull
      or die "redirecting STDOUT to /dev/null failed: $!";
    open STDERR, '>>', File::Spec->devnull
      or die "redirecting STDERR to /dev/null failed: $!";
  }
}

# PREREQ_PM
my %requires = (
  'Algorithm::BloomFilter'              => '0.02',
  'CGI'                                 => '4.31',
  'CGI::Compile'                        => 0,
  'CGI::Emulate::PSGI'                  => 0,
  'CPAN::Meta::Prereqs'                 => '2.132830',
  'CPAN::Meta::Requirements'            => '2.121',
  'Class::XSAccessor'                   => '1.18',
  'Crypt::OpenSSL::Bignum'              => 0,
  'Crypt::OpenSSL::RSA'                 => 0,
  'DBI'                                 => '1.614',
  'DBIx::Connector'                     => 0,
  'DBIx::Class'                         => 0,
  'DBIx::Class::Helpers'                => '== 2.034002',
  'Date::Format'                        => '2.23',
  'Date::Parse'                         => '2.31',
  'DateTime'                            => '0.75',
  'DateTime::TimeZone'                  => '2.11',
  'Devel::NYTProf'                      => '6.04',
  'Digest::SHA'                         => '5.47',
  'EV'                                  => '4.0',
  'Email::MIME'                         => '1.904',
  'Email::MIME::ContentType'            => 0,
  'Email::Sender'                       => 0,
  'FFI::Platypus'                       => 0,
  'Future'                              => '0.34',
  'Graph'                               => 0,
  'HTML::Escape'                        => '1.10',
  'IO::Async'                           => '0.71',
  'IPC::System::Simple'                 => 0,
  'JSON::MaybeXS'                       => '1.003008',
  'JSON::Validator'                     => '3.05',
  'JSON::XS'                            => '2.01',
  'LWP::Protocol::https'                => '6.07',
  'LWP::UserAgent'                      => '6.44',
  'LWP::UserAgent::Determined'          => 0,
  'List::MoreUtils'                     => '0.418',
  'Log::Dispatch'                       => '2.67',
  'Log::Log4perl'                       => '1.49',
  'Math::Random::ISAAC'                 => '1.0.1',
  'Module::Metadata'                    => '1.000033',
  'Module::Runtime'                     => '0.014',
  'Mojo::JWT'                           => '0.07',
  'MojoX::Log::Log4perl'                => '0.04',
  'Mojolicious'                         => '9.0',
  'Mojolicious::Plugin::OAuth2'         => '1.58',
  'Mojolicious::Plugin::OAuth2::Server' => '0.44',
  'Moo'                                 => '2.002004',
  'MooX::StrictConstructor'             => '0.008',
  'Mozilla::CA'                         => '20160104',
  'Net::DNS'                            => '0',
  'Package::Stash'                      => '0.37',
  'Parse::CPAN::Meta'                   => '1.44',
  'PerlX::Maybe'                        => 0,
  'Role::Tiny'                          => '2.000003',
  'Scope::Guard'                        => '0.21',
  'Sereal'                              => '4.004',
  'Set::Object'                         => 0,
  'Sub::Identify'                       => 0,
  'Sub::Quote'                          => '2.005000',
  'Template'                            => '2.24',
  'Text::CSV_XS'                        => '1.26',
  'Throwable'                           => '0.200013',
  'Type::Tiny'                          => '1.004004',
  'URI'                                 => '1.55',
  'URI::Escape::XS'                     => '0.14',
  'version'                             => '0.87',
);

my %build_requires = ('ExtUtils::MakeMaker' => '7.22',);
my %recommends = (Safe => '2.30',);

# Windows requires some additional modules.
if ($OSNAME eq 'MSWin32') {
  $requires{'Win32'}                            = '0.35';
  $requires{'Win32::API'}                       = '0.55';
  $requires{'DateTime::TimeZone::Local::Win32'} = '1.64';
}

if ($OSNAME eq 'linux' && -f '/etc/debian_version') {
  my @extra = qw(
    Test::Pod::Coverage
    Pod::Coverage::TrustPod
    Test::CPAN::Meta
    Test::Pod
  );
  $requires{$_} = 0 for @extra;
}

my %optional_features = (
  better_xff => {
    description => 'Improved behavior of MOJO_REVERSE_PROXY',
    prereqs =>
      {runtime => {requires => {'Mojolicious::Plugin::ForwardedFor' => 0}}}
  },
  alien_cmark => {
    description => 'Support GitHub-flavored markdown',
    prereqs     => {runtime => {requires => {'Alien::libcmark_gfm' => '3'},},},
  },
  argon2 => {
    description => 'Support hashing passwords with Argon2',
    prereqs     => {runtime => {requires => {'Crypt::Argon2' => '0.004',},},},
  },
  smtp_auth => {
    description => 'SMTP Authentication',
    prereqs     => {
      runtime => {requires => {'Authen::SASL' => 0, 'Net::SMTP::TLS' => 0}}},
  },
  detect_charset => {
    description => 'Automatic charset detection for text attachments',
    prereqs =>
      {runtime => {requires => {'Encode::Detect' => 0, Encode => '2.21'}}},
  },
  chart_clicker => {
    description => 'Support nice-looking charts',
    prereqs     => {runtime => {requires => {'Chart::Clicker' => 0}},},
  },
  new_charts => {
    description => 'New Charts',
    prereqs =>
      {runtime => {requires => {'Chart::Lines' => 'v2.4.10', GD => '1.20'}}}
  },
  html_desc => {
    description => 'More HTML in Product/Group Descriptions',
    prereqs     => {
      runtime => {requires => {'HTML::Parser' => '3.67', 'HTML::Scrubber' => 0}}
    }
  },
  markdown => {
    description => 'Markdown syntax support for comments',
    prereqs     => {
      runtime =>
        {requires => {'Text::MultiMarkdown' => '1.000034', 'Unicode::GCString' => 0}}
    }
  },
  pg => {
    description => 'Postgres database support',
    prereqs     => {runtime => {requires => {'DBD::Pg' => 'v2.19.3'}}},
  },
  memcached => {
    description => 'Memcached Support',
    prereqs => {runtime => {requires => {'Cache::Memcached::Fast' => '0.17'}}}
  },
  updates => {
    description => 'Automatic Update Notifications',
    prereqs     => {runtime => {requires => {'XML::Twig' => 0}}}
  },
  auth_radius => {
    description => 'RADIUS Authentication',
    prereqs     => {runtime => {requires => {'Authen::Radius' => 0}}}
  },
  documentation => {
    description => 'Documentation',
    prereqs     => {
      runtime =>
        {requires => {'File::Which' => 0, 'File::Copy::Recursive' => 0,}}
    },
  },
  xmlrpc => {
    description => 'XML-RPC Interface',
    prereqs     => {
      runtime => {
        requires => {
          'XMLRPC::Lite' => '0.712',
          'SOAP::Lite'   => '0.712',
          'Test::Taint'  => '1.06'
        }
      }
    }
  },
  auth_ldap => {
    description => 'LDAP Authentication',
    prereqs     => {runtime => {requires => {'Net::LDAP' => 0}}},
  },
  old_charts => {
    description => 'Old Charts',
    prereqs =>
      {runtime => {requires => {GD => '1.20', 'Chart::Lines' => 'v2.4.10'}},},
  },
  moving => {
    description => 'Move Bugs Between Installations',
    prereqs =>
      {runtime => {requires => {'MIME::Parser' => '5.406', 'XML::Twig' => 0}}},
  },
  oracle => {
    description => 'Oracle database support',
    prereqs     => {runtime => {requires => {'DBD::Oracle' => '1.19'}}}
  },
  s3 => {
    description => 'Amazon S3 Attachment Storage',
    prereqs     => {
      runtime => {
        requires => {
          'Class::Accessor::Fast' => 0,
          'XML::Simple'           => 0,
          'URI::Escape'           => 0,
        }
      }
    }
  },
  typesniffer => {
    description => 'Sniff MIME type of attachments',
    prereqs     => {
      runtime =>
        {requires => {'IO::Scalar' => 0, 'File::MimeInfo::Magic' => 0,},},
    },
  },
  sqlite => {
    description => 'SQLite database support',
    prereqs     => {runtime => {requires => {'DBD::SQLite' => '1.29', 'DateTime::Format::SQLite' => '0.11'}}},
  },
  mysql => {
    description => 'MySQL database support',
    prereqs     => {runtime => {requires => {'DBD::mysql' => '== 4.051', 'DateTime::Format::MySQL' => '0.06'}}}
  },
  jsonrpc => {
    description => 'JSON-RPC Interface',
    prereqs     => {
      runtime =>
        {requires => {'JSON::RPC' => '== 1.01', 'Test::Taint' => '1.06'}}
    }
  },
  graphical_reports => {
    description => 'Graphical Reports',
    prereqs     => {
      runtime => {
        requires => {
          'GD::Text'                    => 0,
          'Template::Plugin::GD::Image' => 0,
          'GD::Graph'                   => 0,
          GD                            => '1.20',
        }
      }
    }
  },
  mfa => {
    description => 'Multi-Factor Authentication',
    prereqs     => {
      runtime => {
        requires =>
          {'Auth::GoogleAuth' => '1.01', 'GD::Barcode' => '== 1.15',},
      }
    },
  },
  inbound_email => {
    description => 'Inbound Email',
    prereqs     => {
      runtime => {
        requires =>
          {'Email::MIME::Attachment::Stripper' => 0, 'Email::Reply' => 0,}
      }
    },
  },
  patch_viewer => {
    description => 'Patch Viewer',
    prereqs     => {runtime => {requires => {PatchReader => '0.9.6'}}}
  },
  rest => {
    description => 'REST Interface',
    prereqs     => {
      runtime =>
        {requires => {'Test::Taint' => '1.06', 'JSON::RPC' => '==1.01',}}
    }
  },
  linux_pid => {
    description => 'Linux::PID',
    prereqs     => {runtime => {requires => {'Linux::Pid' => 0},},},
  },
  linux_smaps => {
    description => 'Linux::Smaps::Tiny for limiting memory usage',
    prereqs     => {
      runtime =>
        {requires => {'Linux::Smaps::Tiny' => '0', 'BSD::Resource' => 0}}
    },
  },
  linux_pdeath => {
    description => 'Linux::Pdeathsig for a good parent/child relationships',
    prereqs     => {runtime => {requires => {'Linux::Pdeathsig' => 0},},},
  },
  jobqueue => {
    description => 'Mail Queueing',
    prereqs     => {
      runtime => {requires => {TheSchwartz => '1.10', 'Daemon::Generic' => 0}}
    }
  },
  sentry => {
    description => 'Sentry Support',
    prereqs     => {
      runtime => {requires => {'Log::Log4perl::Appender::Raven' => '0.006'},},
    },
  },
  datadog => {
    description => 'Data Dog support',
    prereqs => {runtime => {requires => {'DataDog::DogStatsd' => '0.05'},},},
  },
);

for my $file (glob 'extensions/*/Config.pm') {
  my $dir  = dirname($file);
  my $name = basename($dir);

  next if -f File::Spec->catfile($dir, 'disabled');
  require $file;
  my $class = "Bugzilla::Extension::$name";
  if ($class->can('REQUIRED_MODULES')) {
    foreach my $required_module (@{$class->REQUIRED_MODULES()}) {
      $requires{$required_module->{module}} = $required_module->{version};
    }
  }

  if ($class->can('OPTIONAL_MODULES')) {
    my $default_feature = 'extension_' . lc($name) . '_optional';
    foreach my $mod (@{$class->OPTIONAL_MODULES}) {
      my @features = $mod->{feature} ? @{$mod->{feature}} : ($default_feature);
      foreach my $feature (@features) {
        $optional_features{$feature}{prereqs}{runtime}{requires}{$mod->{module}}
          = $mod->{version} // 0;
      }
    }
  }
}

my %test_requires = (
  %{ $optional_features{sqlite}{prereqs}{runtime}{requires} },
  'Capture::Tiny'                   => 0,
  'DBD::SQLite'                     => '1.29',
  'Perl::Critic::Freenode'          => 0,
  'Perl::Critic::Policy::Documentation::RequirePodLinksIncludeText' => 0,
  'Perl::Tidy'                      => '20180220',
  'Pod::Coverage'                   => 0,
  'Selenium::Remote::Driver'        => 1.31,
  'Test::More'                      => 0,
  'Test::Perl::Critic::Progressive' => 0,
  'Test::Selenium::Firefox'         => 0,
  'Test::WWW::Selenium'             => 0,
  'Test2::V0'                       => 0,
);

# BMO Customization
my @bmo_features = grep { is_bmo_feature($_) } keys %optional_features;

$optional_features{bmo} = {
  description => 'features that BMO needs',
  prereqs     => {
    runtime => {
      requires => {
        map { %{$optional_features{$_}{prereqs}{runtime}{requires}} }
          @bmo_features
      },
    },
  },
};

WriteMakefile(
  NAME             => 'Bugzilla',
  AUTHOR           => q{Bugzilla Developers <developers@bugzilla.org>},
  VERSION_FROM     => 'Bugzilla.pm',
  ABSTRACT         => 'Bugzilla Bug Tracking System',
  LICENSE          => 'Mozilla_2_0',
  MIN_PERL_VERSION => '5.34.0',
  CONFIGURE_REQUIRES =>
    {'ExtUtils::MakeMaker' => $build_requires{'ExtUtils::MakeMaker'}},
  PREREQ_PM      => {%requires},
  BUILD_REQUIRES => {%build_requires},
  TEST_REQUIRES  => {%test_requires},
  META_MERGE     => {
    'meta-spec' => {
      url     => 'http://search.cpan.org/perldoc?CPAN::Meta::Spec',
      version => '2'
    },
    dynamic_config => 1,
    prereqs        => {
      build   => {requires => {%build_requires}},
      runtime => {requires => {%requires}, recommends => {%recommends}},
      test    => {requires => {%test_requires}},
    },
    optional_features => \%optional_features,
  },
);

sub MY::postamble {
  return <<"MAKE";
GEN_CPANFILE_ARGS = -D bmo
cpanfile: MYMETA.json
\t\$(PERLRUN) gen-cpanfile.pl \$(GEN_CPANFILE_ARGS)

META.json: Makefile.PL
\tmake distmeta 2>&1 /dev/null; mv */META.json .

META.yml: Makefile.PL
\tmake distmeta 2>&1 /dev/null; mv */META.yml .
MAKE
}

sub is_bmo_feature {
  local $_ = shift;
  return $OSNAME eq 'linux' if /^linux/;
  return !m{
        ^
        (?: pg
          | oracle
          | sqlite
          | auth_ldap
          | auth_radius
          | updates)
        $
    }mxs;
}

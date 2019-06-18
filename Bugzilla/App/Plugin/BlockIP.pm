package Bugzilla::App::Plugin::BlockIP;
use 5.10.1;
use Mojo::Base 'Mojolicious::Plugin';

use Bugzilla::Logging;
use Bugzilla::Memcached;
use Bugzilla::Types qw(JSONBool);
use Mojo::Path;
use Mojo::URL;
use Try::Tiny;
use Type::Library -base, -declare => qw( ResponseType);
use Type::Utils -all;
use Types::Standard -all;

declare ResponseType,
  as Dict [
  object      => Str,
  type        => Str,
  reputation  => Int,
  reviewed    => JSONBool,
  lastupdated => Str,
  decayafter  => Optional [Str],
  slurpy Any,
  ];

use constant BLOCK_TIMEOUT => 60 * 60;

my $MEMCACHED             = Bugzilla::Memcached->new()->{memcached};
my $BLOCKED_INTERNAL_HTML = "";
my $BLOCKED_EXTERNAL_HTML = "";

sub register {
  my ($self, $app, $conf) = @_;

  $app->hook(before_routes => \&_before_routes);
  $app->helper(block_ip   => \&_block_ip);
  $app->helper(unblock_ip => \&_unblock_ip);
  $app->helper(check_ip   => \&_check_ip);

  $app->hook(
    before_server_start => sub {
      my $template = Bugzilla::Template->create();
      $template->process('global/ip-blocked.html.tmpl',
        {block_timeout => BLOCK_TIMEOUT, block_type => 'internal'},
        \$BLOCKED_INTERNAL_HTML);
      $template->process('global/ip-blocked.html.tmpl', {block_type => 'external'},
        \$BLOCKED_EXTERNAL_HTML);
      undef $template;
      utf8::encode($BLOCKED_INTERNAL_HTML);
      utf8::encode($BLOCKED_EXTERNAL_HTML);

      my $iprepd_url = Bugzilla->localconfig->iprepd_url;
      my $iprepd_key = Bugzilla->localconfig->iprepd_key;
      WARN("iprepd_url is not set") unless $iprepd_url;
      WARN("iprepd_key is not set") unless $iprepd_key;
    }
  );
}

sub _block_ip {
  my ($class, $ip) = @_;
  $MEMCACHED->set("block_ip:$ip" => 1, BLOCK_TIMEOUT) if $MEMCACHED;
}

sub _unblock_ip {
  my ($class, $ip) = @_;
  $MEMCACHED->delete("block_ip:$ip") if $MEMCACHED;
}

sub _check_ip {
  my ($c, $ip) = @_;

  state $iprepd_url = Bugzilla->localconfig->iprepd_url;
  state $iprepd_key = Bugzilla->localconfig->iprepd_key;

  if ($MEMCACHED && $MEMCACHED->get("block_ip:$ip")) {
    return 'block_internal';
  }

  if ($iprepd_url && $iprepd_key) {
    my $params = Bugzilla->params;
    my $path   = Mojo::Path->new('/type/ip/')->merge($ip);
    my $url    = Mojo::URL->new($iprepd_url)->path($path);

    return '' unless $params->{iprepd_active};

    my $filter = Bugzilla::Bloomfilter->lookup("rate_limit_whitelist");
    if ($filter->test($ip)) {
      INFO("$ip is in the rate limit whitelist, ignoring iprepd.");
      return '';
    }

    # API may not be slower than 200ms
    $c->ua->connect_timeout(0.100);
    $c->ua->inactivity_timeout(0.100);
    $c->ua->request_timeout(0.200);
    my $tx   = $c->ua->get($url => {Authorization => "APIKey $iprepd_key"});
    my $code = $tx->result->code;
    if ($code == 200) {
      my $response = $tx->result->json;
      my $error    = ResponseType->validate($response);
      if ($error) {
        die "JSON Response from $iprepd_url does not meet expectations: $error";
      }
      if ($response->{reputation} < $params->{iprepd_min_reputation}) {
        return 'block_external';
      }
    }
    elsif ($code == 404) {
      INFO("No reputation for $ip");
    }
    else {
      my $message = $tx->result->message;
      die "Unexpected HTTP response $code, message: $message";
    }
  }

  return '';
}

sub _before_routes {
  my ($c) = @_;
  return if $c->stash->{'mojo.static'};

  state $better_xff = Bugzilla->has_feature('better_xff');
  my $ip = $better_xff ? $c->forwarded_for : $c->tx->remote_address;
  try {
    my $blocked = $c->check_ip($ip);

    if ($blocked eq 'block_internal') {
      $c->block_ip($ip);
      $c->res->code(429);
      $c->res->message('Too Many Requests');
      $c->write($BLOCKED_INTERNAL_HTML);
      $c->finish;
    }
    elsif ($blocked eq 'block_external') {
      $c->res->code(403);
      $c->res->message('Forbidden');
      $c->write($BLOCKED_EXTERNAL_HTML);
      $c->finish;
    }
  }
  catch {
    ERROR($_);
  };
}

1;

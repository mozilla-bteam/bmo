#!/usr/bin/env perl
BEGIN { $ENV{MOJO_LISTEN} = 'http://*:8025' }
use Mojolicious::Lite;
use Mojo::JSON qw(true false);

my %database = (
  '1.2.3.4' => 10,
);

get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};

get '/type/ip/*ip' => sub {
  my $c  = shift;
  my $ip = $c->param('ip');
  if (exists $database{$ip}) {
    $c->render(
      json => {
        object      => $ip,
        type        => 'ip',
        reputation  => $database{$ip},
        reviewed    => false,
        lastupdated => '2018-04-23T18=>25=>43.511Z',
      }
    );
  }
  else {
    $c->reply->not_found;
  }
};

app->start;
__DATA__

@@ index.html.ep
% layout 'default';
% title 'Welcome';
<h1>Welcome to the Mojolicious real-time web framework!</h1>

@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>

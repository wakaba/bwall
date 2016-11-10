use strict;
use warnings;
use Path::Tiny;
use lib glob path (__FILE__)->parent->parent->child ('t_deps/modules/*/lib');
use Test::X1;
use Test::More;
use Sarze;
use Promised::Flow;
use Web::URL;
use Web::Transport::ConnectionClient;

{
  use Socket;
  my $EphemeralStart = 1024;
  my $EphemeralEnd = 5000;

  sub is_listenable_port ($) {
    my $port = $_[0];
    return 0 unless $port;
    
    my $proto = getprotobyname('tcp');
    socket(my $server, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";
    setsockopt($server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) || die "setsockopt: $!";
    bind($server, sockaddr_in($port, INADDR_ANY)) || return 0;
    listen($server, SOMAXCONN) || return 0;
    close($server);
    return 1;
  } # is_listenable_port

  my $using = {};
  sub find_listenable_port () {
    for (1..10000) {
      my $port = int rand($EphemeralEnd - $EphemeralStart);
      next if $using->{$port}++;
      return $port if is_listenable_port $port;
    }
    die "Listenable port not found";
  } # find_listenable_port
}

my $Port = find_listenable_port;
my $ServerURL = Web::URL->parse_string ("http://localhost:$Port");

test {
  my $c = shift;
  my $client = Web::Transport::ConnectionClient->new_from_url ($ServerURL);
  promised_cleanup {
    done $c;
    undef $c;
  } $client->request (path => [])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 404;
    } $c;
  });
} n => 1;

test {
  my $c = shift;
  my $client = Web::Transport::ConnectionClient->new_from_url ($ServerURL);
  promised_cleanup {
    done $c;
    undef $c;
  } $client->request (path => ['robots.txt'])->then (sub {
    my $res = $_[0];
    test {
      is $res->status, 200;
      is $res->body_bytes, qq{User-agent: *\nDisallow: /};
    } $c;
  });
} n => 2;

local $ENV{DATABASE_URL} = q<https://dummy.test>;
my $sarze;
Sarze->start (
  hostports => [['127.0.0.1', $Port]],
  psgi_file_name => path (__FILE__)->parent->parent->child ('bin/server.psgi'),
)->then (sub {
  $sarze = $_[0];
});
run_tests;
$sarze->stop->to_cv->recv;

=head1 LICENSE

Copyright 2016 Wakaba <wakaba@suikawiki.org>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Affero General Public License for more details.

You does not have received a copy of the GNU Affero General Public
License along with this program, see <https://www.gnu.org/licenses/>.

=cut

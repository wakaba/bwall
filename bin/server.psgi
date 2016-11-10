# -*- Perl -*-
use strict;
use warnings;
use Wanage::HTTP;
use Warabe::App;
use Web::URL;
use Web::Transport::ConnectionClient;
use JSON::PS;

my $DatabaseURL = Web::URL->parse_string ($ENV{DATABASE_URL} // die "Bad |DATABASE_URL|")
    // die "Bad |DATABASE_URL|";

return sub {
  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);
  return $app->execute_by_promise (sub {
    my $path = $app->path_segments;

    ## GET /wall/{group}
    if (@$path == 2 and $path->[0] eq 'wall' and
        $path->[1] =~ /\A[A-Za-z0-9_.-]{1,20}\z/) {
      my $client = Web::Transport::ConnectionClient->new_from_url ($DatabaseURL);
      return $client->request (
        path => [$path->[1], '_search'],
        basic_auth => [$DatabaseURL->username, $DatabaseURL->password],
        headers => {'Content-Type' => 'application/json'},
        body => (perl2json_bytes {query => {match_all => {}}}),
      )->then (sub {
        my $res = $_[0];
        die $res unless $res->status == 200;
        my $json = json_bytes2perl $res->body_bytes;
        $app->http->set_response_header ('content-type', 'application/json');
        $app->http->send_response_body_as_ref
            (\perl2json_bytes ({map { $_->{_source}->{name} => $_->{_source} } @{$json->{hits}->{hits}}}));
        $app->http->close_response_body;
      });
    }

    ## POST /ping/{group}/{name}
    ##   pass={boolean}
    ##   fail={boolean}
    ##   status={string}
    if (@$path == 3 and $path->[0] eq 'ping' and
        $path->[1] =~ /\A[A-Za-z0-9_.-]{1,20}\z/ and
        $path->[2] =~ /\A[A-Za-z0-9_.-]{1,20}\z/) {
      $app->requires_request_method ({POST => 1});
      $app->requires_same_origin
          if defined $app->http->get_request_header ('Origin');

      my $p = $app->bare_param ('pass');
      my $f = $app->bare_param ('fail');
      my $failed = $f;
      $failed = 1 if defined $p and not $p;

      my $status = $app->text_param ('status') // '';
      $status = substr $status, 0, 20;

      my $data = {
        group => $path->[1],
        name => $path->[2],
        failed => !!$failed,
        status => $status,
        timestamp => time,
      };

      my $client = Web::Transport::ConnectionClient->new_from_url ($DatabaseURL);
      return $client->request (
        method => 'PUT',
        path => [$data->{group}, $data->{name}],
        basic_auth => [$DatabaseURL->username, $DatabaseURL->password],
        headers => {'Content-Type' => 'application/json'},
        body => (perl2json_bytes $data),
      )->then (sub {
        die $_[0] unless $_[0]->is_success;
        return $app->send_error (200, reason_phrase => 'Pong');
      })->then (sub {
        return $client->close;
      });
    }

    if (@$path == 1 and $path->[0] eq 'robots.txt') {
      return $app->send_plain_text ("User-agent: *\nDisallow: /");
    }

    return $app->send_error (404);
  });
};

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

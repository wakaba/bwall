# -*- Perl -*-
use strict;
use warnings;
use Wanage::HTTP;
use Warabe::App;
use Digest::SHA qw(sha1_hex);
use Web::Encoding;
use Web::URL;
use Web::Transport::ConnectionClient;
use JSON::PS;

my $DatabaseURL = Web::URL->parse_string ($ENV{DATABASE_URL} // die "Bad |DATABASE_URL|")
    // die "Bad |DATABASE_URL|";

sub e ($) {
  my $s = $_[0];
  $s =~ s/&/&amp;/g;
  $s =~ s/</&lt;/g;
  $s =~ s/>/&gt;/g;
  $s =~ s/"/&quot;/g;
  return $s;
} # e

return sub {
  my $http = Wanage::HTTP->new_from_psgi_env ($_[0]);
  my $app = Warabe::App->new_from_http ($http);
  return $app->execute_by_promise (sub {
    my $path = $app->path_segments;

    $http->set_response_header
        ('Strict-Transport-Security' => 'max-age=2592000; includeSubDomains; preload');

    ## GET /wall/{group}
    ## GET /wall/{group}/html
    if ((@$path == 2 and $path->[0] eq 'wall') or
        (@$path == 3 and $path->[0] eq 'wall' and $path->[2] eq 'html')) {
      my $egroup = sha1_hex encode_web_utf8 $path->[1];
      my $is_html = @$path == 3;
      my $client = Web::Transport::ConnectionClient->new_from_url ($DatabaseURL);
      return $client->request (
        path => [$egroup, '_search'],
        basic_auth => [$DatabaseURL->username, $DatabaseURL->password],
        headers => {'Content-Type' => 'application/json'},
        body => (perl2json_bytes {query => {match_all => {}}}),
      )->then (sub {
        my $res = $_[0];
        die $res unless $res->status == 200;
        my $json = json_bytes2perl $res->body_bytes;
        my $data = {map { $_->{_source}->{name} => $_->{_source} } @{$json->{hits}->{hits}}};
        if ($is_html) {
          $app->http->set_response_header ('content-type', 'text/html;charset=utf-8');
          $app->http->send_response_body_as_text
              (sprintf q{<!DOCTYPE HTML><title>%s</title><style>.PASS{background:green;color:white}.FAIL{background:red;color:white}</style><h1>%s</h1><table><tbody>%s</table>},
                   e $path->[1],
                   e $path->[1],
                   join '', map {
                     my @t = gmtime $_->{timestamp};
                     sprintf q{<tr><th>%s<td class="%s"><time>%04d-%02d-%02dT%02d:%02d:%02dZ</time><td class="%s">%s<td>%s},
                         e $_->{name},
                         $_->{timestamp} + 7*24*60*60 < time ? 'FAIL' : '',
                         $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0],
                         $_->{failed} ? 'FAIL' : 'PASS',
                         $_->{failed} ? 'FAIL' : 'PASS',
                         e $_->{status};
                   } sort { $b->{timestamp} <=> $a->{timestamp} } values %$data);
          $app->http->close_response_body;
        } else {
          $app->http->set_response_header ('content-type', 'application/json');
          $app->http->send_response_body_as_ref (\perl2json_bytes ($data));
          $app->http->close_response_body;
        }
      });
    }

    ## POST /ping/{group}/{name}
    ##   pass={boolean}
    ##   fail={boolean}
    ##   status={string}
    if (@$path == 3 and $path->[0] eq 'ping') {
      $app->requires_request_method ({POST => 1});
      $app->requires_same_origin
          if defined $app->http->get_request_header ('Origin');

      my $p = $app->bare_param ('pass');
      my $f = $app->bare_param ('fail');
      my $failed = $f;
      $failed = 1 if defined $p and not $p;

      my $status = $app->text_param ('status') // '';
      $status = substr $status, 0, 20;

      my $egroup = sha1_hex encode_web_utf8 $path->[1];
      my $ename = sha1_hex encode_web_utf8 $path->[2];
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
        path => [$egroup, $ename],
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

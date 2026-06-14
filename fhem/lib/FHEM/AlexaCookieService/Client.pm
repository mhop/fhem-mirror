# $Id$
#
# Maintainer: sidey
# Description: HTTP request helper for the external Alexa cookie service.
# More information: https://github.com/fhem/alexa-cookie-service

package FHEM::AlexaCookieService::Client;

use strict;
use warnings;

use JSON::PP qw(decode_json);
use URI::Escape qw(uri_escape_utf8);

sub new {
  my ($class, %args) = @_;

  my $base_url = $args{base_url} || 'http://alexa-cookie-service:58080';
  $base_url =~ s{/+\z}{};

  return bless {
    base_url => $base_url,
    token    => $args{token} || q{},
    timeout  => $args{timeout} || 30,
  }, $class;
}

sub status_request {
  my ($self, %args) = @_;
  return $self->_request('GET', '/api/status', undef, %args);
}

sub login_url_request {
  my ($self, %args) = @_;
  return $self->_request('GET', '/api/cookie/login/url', undef, %args);
}

sub login_start_request {
  my ($self, %args) = @_;
  return $self->_request('POST', '/api/cookie/login/start', undef, %args);
}

sub refresh_request {
  my ($self, %args) = @_;
  return $self->_request('POST', '/api/cookie/refresh', _query(save => $args{save}), %args);
}

sub cookie_request {
  my ($self, %args) = @_;
  return $self->_request('GET', '/api/cookie', _query(save => $args{save}), %args);
}

sub cookie_text_request {
  my ($self, %args) = @_;
  return $self->_request('GET', '/api/cookie/text', undef, %args);
}

sub decode_json_response {
  my ($self, $error, $data) = @_;

  return ($error, undef) if $error;
  return (q[empty response], undef) if !defined $data || $data eq q{};

  my $decoded = eval { decode_json($data) };
  return ($@ || q[invalid JSON response], undef) if $@;

  return (undef, $decoded);
}

sub _request {
  my ($self, $method, $path, $query, %args) = @_;

  my $url = $self->{base_url} . $path . ($query || q{});
  my $header = $self->{token} ? 'x-auth-token: ' . $self->{token} : undef;

  my %request = (
    url      => $url,
    method   => $method,
    timeout  => $args{timeout} || $self->{timeout},
    callback => $args{callback},
  );

  $request{header} = $header if defined $header;
  $request{data} = $args{data} if exists $args{data};

  return \%request;
}

sub _query {
  my (%params) = @_;

  my @pairs;
  for my $key (sort keys %params) {
    next if !defined $params{$key} || $params{$key} eq q{};
    push @pairs, uri_escape_utf8($key) . q{=} . uri_escape_utf8($params{$key});
  }

  return @pairs ? q{?} . join q{&}, @pairs : q{};
}

1;

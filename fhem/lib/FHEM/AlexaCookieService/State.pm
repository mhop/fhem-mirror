# $Id$
#
# Maintainer: sidey
# Description: Secret-free state normalization for Alexa cookie service data.
# More information: https://github.com/fhem/alexa-cookie-service

package FHEM::AlexaCookieService::State;

use strict;
use warnings;

sub normalize_status {
  my ($status) = @_;

  return {} if ref $status ne 'HASH';

  return {
    ok              => $status->{ok} ? 1 : 0,
    updatedAt       => $status->{updatedAt},
    ageHours        => $status->{ageHours},
    hasCookie       => $status->{hasCookie} ? 1 : 0,
    hasCsrf         => $status->{hasCsrf} ? 1 : 0,
    hasRefreshToken => $status->{hasRefreshToken} ? 1 : 0,
    amazonPage      => $status->{amazonPage},
  };
}

sub normalize_cookie_export {
  my ($cookie) = @_;

  return {} if ref $cookie ne 'HASH';

  return {
    hasCookie       => ($cookie->{localCookie} || $cookie->{cookie}) ? 1 : 0,
    hasCsrf         => $cookie->{csrf} ? 1 : 0,
    hasRefreshToken => $cookie->{refreshToken} ? 1 : 0,
    hasMacDms       => $cookie->{macDms} ? 1 : 0,
    serviceUpdatedAt => $cookie->{serviceUpdatedAt},
  };
}

sub has_usable_cookie {
  my ($state) = @_;

  return 0 if ref $state ne 'HASH';
  return $state->{hasCookie} && $state->{hasCsrf} && $state->{hasRefreshToken} ? 1 : 0;
}

sub readings_from_status {
  my ($status) = @_;
  my $normalized = normalize_status($status);

  return {
    service_ok          => $normalized->{ok} ? '1' : '0',
    service_updated_at  => $normalized->{updatedAt} || q{},
    service_age_hours   => defined $normalized->{ageHours} ? $normalized->{ageHours} : q{},
    cookie_available    => $normalized->{hasCookie} ? '1' : '0',
    csrf_available      => $normalized->{hasCsrf} ? '1' : '0',
    refresh_available   => $normalized->{hasRefreshToken} ? '1' : '0',
    amazon_page         => $normalized->{amazonPage} || q{},
  };
}

1;

# $Id$
#
# Maintainer: sidey
# Description: echodevice import glue for Alexa cookie service exports.
# More information: https://github.com/fhem/alexa-cookie-service

package FHEM::AlexaCookieService::EchodeviceImport;

use strict;
use warnings;

sub export_name_for_hash {
  my ($hash) = @_;

  return if ref $hash ne 'HASH';
  return if !defined $hash->{NR} || $hash->{NR} eq q{};

  return $hash->{NR} . 'result.json';
}

sub validate_target {
  my ($hash) = @_;

  return q[missing echodevice hash] if ref $hash ne 'HASH';
  return q[missing device name] if !$hash->{NAME};
  return q[device is not an echodevice] if ($hash->{TYPE} || q{}) ne 'echodevice';
  return q[missing internal FHEM NR] if !defined $hash->{NR} || $hash->{NR} eq q{};

  return;
}

sub trigger_import {
  my ($hash, %args) = @_;

  my $error = validate_target($hash);
  return $error if $error;

  my $login_type = $args{login_type} || 'NPM Login Refresh external';

  {
    no warnings 'once';
    local $main::NPMLoginTyp = $login_type;

    no strict 'refs'; ## no critic (ProhibitNoStrict)
    return q[echodevice_NPMWaitForCookie is not available]
      if !defined &{'main::echodevice_NPMWaitForCookie'};
    &{'main::echodevice_NPMWaitForCookie'}($hash);
  }

  return;
}

1;

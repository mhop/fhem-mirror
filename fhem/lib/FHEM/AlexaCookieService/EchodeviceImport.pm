# $Id$
#
# Maintainer: sidey
# Description: echodevice import glue for Alexa cookie service exports.
# More information: https://github.com/fhem/alexa-cookie-service

package FHEM::AlexaCookieService::EchodeviceImport;

use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP qw(decode_json encode_json);

sub export_name_for_hash {
  my ($hash) = @_;

  return if ref $hash ne 'HASH';
  return if !defined $hash->{NR} || $hash->{NR} !~ /\A\d+\z/;

  return $hash->{NR} . 'result.json';
}

sub export_name_for_device {
  my ($name) = @_;

  return if !$name;

  no warnings 'once';
  return export_name_for_hash($main::defs{$name});
}

sub validate_target {
  my ($hash) = @_;

  return q[missing echodevice hash] if ref $hash ne 'HASH';
  return q[missing device name] if !$hash->{NAME};
  return q[device is not an echodevice] if ($hash->{TYPE} || q{}) ne 'echodevice';
  return q[missing internal FHEM NR] if !defined $hash->{NR} || $hash->{NR} !~ /\A\d+\z/;

  return;
}

sub export_path_for_hash {
  my ($hash, %args) = @_;

  my $export_name = export_name_for_hash($hash);
  return if !defined $export_name;

  my $export_dir = $args{export_dir} || $args{base_dir} || $args{dir};
  return if !defined $export_dir || $export_dir eq q{};

  return File::Spec->catfile($export_dir, $export_name);
}

sub write_cookie_export {
  my ($hash, $payload, %args) = @_;

  my $error = validate_target($hash);
  return $error if $error;

  my $path = export_path_for_hash($hash, %args);
  return q[missing export dir] if !defined $path;

  my $cookie = _normalize_export_payload($payload);
  return q[invalid cookie export payload] if ref $cookie ne 'HASH';

  my $dir = dirname($path);
  if (!-d $dir) {
    make_path($dir) or return qq[failed to create export dir $dir];
  }

  my $tmp_path = $path . qq{.tmp.$$};
  open my $fh, '>', $tmp_path or return qq[failed to open $tmp_path: $!];
  binmode $fh, ':raw';

  my $json = encode_json($cookie);
  if (!print {$fh} $json) {
    my $err = $!;
    close $fh;
    unlink $tmp_path;
    return qq[failed to write $tmp_path: $err];
  }

  if (!close $fh) {
    my $err = $!;
    unlink $tmp_path;
    return qq[failed to close $tmp_path: $err];
  }

  if (!rename $tmp_path, $path) {
    my $err = $!;
    unlink $tmp_path;
    return qq[failed to rename $tmp_path to $path: $err];
  }

  return;
}

sub write_cookie_export_for_device {
  my ($name, $payload, %args) = @_;

  return q[missing echodevice name] if !$name;

  no warnings 'once';
  return write_cookie_export($main::defs{$name}, $payload, %args);
}

sub write_cookie_export_and_trigger_import {
  my ($hash, $payload, %args) = @_;

  my $error = write_cookie_export($hash, $payload, %args);
  return $error if $error;

  return trigger_import($hash, %args);
}

sub write_cookie_export_and_trigger_import_for_device {
  my ($name, $payload, %args) = @_;

  return q[missing echodevice name] if !$name;

  no warnings 'once';
  return write_cookie_export_and_trigger_import($main::defs{$name}, $payload, %args);
}

sub httpmod_write_cookie_export_and_trigger_import {
  my ($httpmod_hash, $buffer) = @_;

  return if ref $httpmod_hash ne q{HASH} || !defined $buffer;

  my $payload = _normalize_httpmod_export_payload($buffer);
  return if ref $payload ne q{HASH};

  my $httpmod_name = $httpmod_hash->{NAME} || q{};
  my $echodevice = main::AttrVal($httpmod_name, q{echodevice}, q{});
  if (!$echodevice) {
    main::Log3($httpmod_name, 3, qq[$httpmod_name: missing echodevice attribute]);
    return q{missing echodevice attribute};
  }

  my $error = write_cookie_export_and_trigger_import_for_device(
    $echodevice,
    $payload,
    export_dir => q{/opt/fhem/cache/alexa-cookie},
  );

  main::Log3(
    $httpmod_name,
    $error ? 3 : 4,
    $error
      ? qq[$httpmod_name: cookie export/import failed: $error]
      : qq[$httpmod_name: cookie export written and imported],
  );

  return $error;
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

sub trigger_import_for_device {
  my ($name, %args) = @_;

  return q[missing echodevice name] if !$name;

  no warnings 'once';
  return trigger_import($main::defs{$name}, %args);
}

sub _normalize_export_payload {
  my ($payload) = @_;

  return $payload if ref $payload eq 'HASH';

  if (!ref $payload && defined $payload && $payload ne q{}) {
    my $decoded = eval { decode_json($payload) };
    return $decoded if !$@ && ref $decoded eq 'HASH';
  }

  return;
}

sub _normalize_httpmod_export_payload {
  my ($buffer) = @_;

  my $body = $buffer;
  $body =~ s{\A.*?\r?\n\r?\n}{}s;

  my $payload = _normalize_export_payload($body);
  return if ref $payload ne q{HASH};

  return if !exists $payload->{localCookie};
  return if !exists $payload->{refreshToken};
  return if !exists $payload->{formerRegistrationData};

  return $payload;
}

1;

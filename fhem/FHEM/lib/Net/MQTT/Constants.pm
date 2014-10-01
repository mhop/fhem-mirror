use strict;
use warnings;
package Net::MQTT::Constants;
$Net::MQTT::Constants::VERSION = '1.142010';
# ABSTRACT: Module to export constants for MQTT protocol


use Carp qw/croak/;

my %constants =
  (
   MQTT_CONNECT     => 0x1,
   MQTT_CONNACK     => 0x2,
   MQTT_PUBLISH     => 0x3,
   MQTT_PUBACK      => 0x4,
   MQTT_PUBREC      => 0x5,
   MQTT_PUBREL      => 0x6,
   MQTT_PUBCOMP     => 0x7,
   MQTT_SUBSCRIBE   => 0x8,
   MQTT_SUBACK      => 0x9,
   MQTT_UNSUBSCRIBE => 0xa,
   MQTT_UNSUBACK    => 0xb,
   MQTT_PINGREQ     => 0xc,
   MQTT_PINGRESP    => 0xd,
   MQTT_DISCONNECT  => 0xe,

   MQTT_QOS_AT_MOST_ONCE  => 0x0,
   MQTT_QOS_AT_LEAST_ONCE => 0x1,
   MQTT_QOS_EXACTLY_ONCE  => 0x2,

   MQTT_CONNECT_ACCEPTED                              => 0,
   MQTT_CONNECT_REFUSED_UNACCEPTABLE_PROTOCOL_VERSION => 1,
   MQTT_CONNECT_REFUSED_IDENTIFIER_REJECTED           => 2,
   MQTT_CONNECT_REFUSED_SERVER_UNAVAILABLE            => 3,
   MQTT_CONNECT_REFUSED_BAD_USER_NAME_OR_PASSWORD     => 4,
   MQTT_CONNECT_REFUSED_NOT_AUTHORIZED                => 5,
  );

sub import {
  no strict qw/refs/; ## no critic
  my $pkg = caller(0);
  foreach (keys %constants) {
    my $v = $constants{$_};
    *{$pkg.'::'.$_} = sub () { $v };
  }
  foreach (qw/decode_byte encode_byte
              decode_short encode_short
              decode_string encode_string
              decode_remaining_length encode_remaining_length
              qos_string
              message_type_string
              dump_string
              connect_return_code_string
             /) {
    *{$pkg.'::'.$_} = \&{$_};
  }
}


sub decode_remaining_length {
  my ($data, $offset) = @_;
  my $multiplier = 1;
  my $v = 0;
  my $d;
  do {
    $d = decode_byte($data, $offset);
    $v += ($d&0x7f) * $multiplier;
    $multiplier *= 128;
  } while ($d&0x80);
  $v
}


sub encode_remaining_length {
  my $v = shift;
  my $o;
  my $d;
  do {
    $d = $v % 128;
    $v = int($v/128);
    if ($v) {
      $d |= 0x80;
    }
    $o .= encode_byte($d);
  } while ($d&0x80);
  $o;
}


sub decode_byte {
  my ($data, $offset) = @_;
  croak 'decode_byte: insufficient data' unless (length $data >= $$offset+1);
  my $res = unpack 'C', substr $data, $$offset, 1;
  $$offset++;
  $res
}


sub encode_byte {
  pack 'C', $_[0];
}


sub decode_short {
  my ($data, $offset) = @_;
  croak 'decode_short: insufficient data' unless (length $data >= $$offset+2);
  my $res = unpack 'n', substr $data, $$offset, 2;
  $$offset += 2;
  $res;
}


sub encode_short {
  pack 'n', $_[0];
}


sub decode_string {
  my ($data, $offset) = @_;
  my $len = decode_short($data, $offset);
  croak 'decode_string: insufficient data'
    unless (length $data >= $$offset+$len);
  my $res = substr $data, $$offset, $len;
  $$offset += $len;
  $res;
}


sub encode_string {
  pack "n/a*", $_[0];
}


sub qos_string {
  [qw/at-most-once at-least-once exactly-once reserved/]->[$_[0]]
}


sub message_type_string {
  [qw/Reserved0 Connect ConnAck Publish PubAck PubRec PubRel PubComp
      Subscribe SubAck Unsubscribe UnsubAck PingReq PingResp Disconnect
      Reserved15/]->[$_[0]];
}


sub dump_string {
  my $data = shift || '';
  my $prefix = shift || '';
  $prefix .= '  ';
  my @lines;
  while (length $data) {
    my $d = substr $data, 0, 16, '';
    my $line = unpack 'H*', $d;
    $line =~ s/([A-F0-9]{2})/$1 /ig;
    $d =~ s/[^ -~]/./g;
    $line = sprintf "%-48s %s", $line, $d;
    push @lines, $line
  }
  scalar @lines ? "\n".$prefix.(join "\n".$prefix, @lines) : ''
}



sub connect_return_code_string {
  [
   'Connection Accepted',
   'Connection Refused: unacceptable protocol version',
   'Connection Refused: identifier rejected',
   'Connection Refused: server unavailable',
   'Connection Refused: bad user name or password',
   'Connection Refused: not authorized',
  ]->[$_[0]] || 'Reserved'
}

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Constants - Module to export constants for MQTT protocol

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  use Net::MQTT::Constants;

=head1 DESCRIPTION

Module to export constants for MQTT protocol.

=head1 C<FUNCTIONS>

=head2 C<decode_remaining_length( $data, \$offset )>

Calculates the C<remaining length> from the bytes in C<$data> starting
at the offset read from the scalar reference.  The offset reference is
subsequently incremented by the number of bytes processed.

=head2 C<encode_remaining_length( $length )>

Calculates the C<remaining length> bytes from the length, C<$length>,
and returns the packed bytes as a string.

=head2 C<decode_byte( $data, \$offset )>

Returns a byte by unpacking it from C<$data> starting at the offset
read from the scalar reference.  The offset reference is subsequently
incremented by the number of bytes processed.

=head2 C<encode_byte( $byte )>

Returns a packed byte.

=head2 C<decode_short( $data, \$offset )>

Returns a short (two bytes) by unpacking it from C<$data> starting at
the offset read from the scalar reference.  The offset reference is
subsequently incremented by the number of bytes processed.

=head2 C<encode_short( $short )>

Returns a packed short (two bytes).

=head2 C<decode_string( $data, \$offset )>

Returns a string (short length followed by length bytes) by unpacking
it from C<$data> starting at the offset read from the scalar
reference.  The offset reference is subsequently incremented by the
number of bytes processed.

=head2 C<encode_string( $string )>

Returns a packed string (length as a short and then the bytes of the
string).

=head2 C<qos_string( $qos_value )>

Returns a string describing the given QoS value.

=head2 C<message_type_string( $message_type_value )>

Returns a string describing the given C<message_type> value.

=head2 C<dump_string( $data )>

Returns a string representation of arbitrary data - as a string if it
contains only printable characters or as a hex dump otherwise.

=head2 C<connect_return_code_string( $return_code_value )>

Returns a string describing the given C<connect_return_code> value.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

use strict;
use warnings;
package Net::MQTT::Message;
$Net::MQTT::Message::VERSION = '1.142010';
# ABSTRACT: Perl module to represent MQTT messages


use Net::MQTT::Constants qw/:all/;
use Module::Pluggable search_path => __PACKAGE__, require => 1;

our %types;
foreach (plugins()) {
  my $m = $_.'::message_type';
  next unless (defined &{$m}); # avoid super classes
  my $t = $_->message_type;
  if (exists $types{$t}) {
    die 'Duplicate message_type number ', $t, ":\n",
      '  ', $_, " and\n",
        '  ', $types{$t}, "\n";
  }
  $types{$t} = $_;
}


sub new {
  my ($pkg, %p) = @_;
  my $type_pkg =
    exists $types{$p{message_type}} ? $types{$p{message_type}} : $pkg;
  bless { %p }, $type_pkg;
}


sub new_from_bytes {
  my ($pkg, $bytes, $splice) = @_;
  my %p;
  return if (length $bytes < 2);
  my $offset = 0;
  my $b = decode_byte($bytes, \$offset);
  $p{message_type} = ($b&0xf0) >> 4;
  $p{dup} = ($b&0x8)>>3;
  $p{qos} = ($b&0x6)>>1;
  $p{retain} = ($b&0x1);
  my $length;
  eval {
    $length = decode_remaining_length($bytes, \$offset);
  };
  return if ($@);
  if (length $bytes < $offset+$length) {
    return
  }
  substr $_[1], 0, $offset+$length, '' if ($splice);
  $p{remaining} = substr $bytes, $offset, $length;
  my $self = $pkg->new(%p);
  $self->_parse_remaining();
  $self;
}

sub _parse_remaining {
}


sub message_type { shift->{message_type} }


sub dup { shift->{dup} || 0 }


sub qos {
  my $self = shift;
  defined $self->{qos} ? $self->{qos} : $self->_default_qos
}

sub _default_qos {
  MQTT_QOS_AT_MOST_ONCE
}


sub retain { shift->{retain} || 0 }


sub remaining { shift->{remaining} || '' }

sub _remaining_string {
  my ($self, $prefix) = @_;
  dump_string($self->remaining, $prefix);
}

sub _remaining_bytes { shift->remaining }


sub string {
  my ($self, $prefix) = @_;
  $prefix = '' unless (defined $prefix);
  my @attr;
  push @attr, qos_string($self->qos);
  foreach (qw/dup retain/) {
    my $bool = $self->$_;
    push @attr, $_ if ($bool);
  }
  my $r = $self->_remaining_string($prefix);
  $prefix.message_type_string($self->message_type).
    '/'.(join ',', @attr).($r ? ' '.$r : '')
}


sub bytes {
  my ($self) = shift;
  my $o = '';
  my $b =
    ($self->message_type << 4) | ($self->dup << 3) |
      ($self->qos << 1) | $self->retain;
  $o .= encode_byte($b);
  my $remaining = $self->_remaining_bytes;
  $o .= encode_remaining_length(length $remaining);
  $o .= $remaining;
  $o;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message - Perl module to represent MQTT messages

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  use Net::MQTT::Constants;
  use Net::MQTT::Message;
  use IO::Socket::INET;
  my $socket = IO::Socket::INET->new(PeerAddr => '127.0.0.1:1883');
  my $mqtt = Net::MQTT::Message->new(message_type => MQTT_CONNECT);
  print $socket $mqtt->bytes;

  my $tcp_payload = pack 'H*', '300d000774657374696e6774657374';
  $mqtt = Net::MQTT::Message->new_from_bytes($tcp_payload);
  print 'Received: ', $mqtt->string, "\n";

=head1 DESCRIPTION

This module encapsulates a single MQTT message.  It uses subclasses to
represent specific message types.

=head1 METHODS

=head2 C<new( %parameters )>

Constructs an L<Net::MQTT::Message> object based on the given
parameters.  The common parameter keys are:

=over

=item C<message_type>

The message type field of the MQTT message.  This should be an integer
between 0 and 15 inclusive.  The module L<Net::MQTT::Constants>
provides constants that can be used for this value.  This parameter
is required.

=item C<dup>

The duplicate flag field of the MQTT message.  This should be either 1
or 0.  The default is 0.

=item C<qos>

The QoS field of the MQTT message.  This should be an integer between
0 and 3 inclusive.  The default is as specified in the spec or 0 ("at
most once") otherwise.  The module L<Net::MQTT::Constants> provides
constants that can be used for this value.

=item C<retain>

The retain flag field of the MQTT message.  This should be either 1
or 0.  The default is 0.

=back

The remaining keys are dependent on the specific message type.  The
documentation for the subclasses for each message type list methods
with the same name as the required keys.

=head2 C<new_from_bytes( $packed_bytes, [ $splice ] )>

Attempts to constructs an L<Net::MQTT::Message> object based on
the given packed byte string.  If there are insufficient bytes, then
undef is returned.  If the splice parameter is provided and true, then
the processed bytes are removed from the scalar referenced by the
$packed_bytes parameter.

=head2 C<message_type()>

Returns the message type field of the MQTT message.  The module
L<Net::MQTT::Constants> provides a function, C<message_type_string>,
that can be used to convert this value to a human readable string.

=head2 C<dup()>

The duplicate flag field of the MQTT message.

=head2 C<qos()>

The QoS field of the MQTT message.  The module
L<Net::MQTT::Constants> provides a function, C<qos_string>, that
can be used to convert this value to a human readable string.

=head2 C<retain()>

The retain field of the MQTT message.

=head2 C<remaining()>

This contains a packed string of bytes with any of the payload of the
MQTT message that was not parsed by these modules.  This should not
be required for packets that strictly follow the standard.

=head2 C<string([ $prefix ])>

Returns a summary of the message as a string suitable for logging.
If provided, each line will be prefixed by the optional prefix.

=head2 C<bytes()>

Returns the bytes of the message suitable for writing to a socket.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

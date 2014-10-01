use strict;
use warnings;
package Net::MQTT::Message::SubAck;
$Net::MQTT::Message::SubAck::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT SubAck message


use base 'Net::MQTT::Message';
use Net::MQTT::Constants qw/:all/;

sub message_type {
  9
}


sub message_id { shift->{message_id} }


sub qos_levels { shift->{qos_levels} }

sub _remaining_string {
  my ($self, $prefix) = @_;
  $self->message_id.'/'.
    (join ',', map { qos_string($_) } @{$self->qos_levels}).
    ' '.$self->SUPER::_remaining_string($prefix)
}

sub _parse_remaining {
  my $self = shift;
  my $offset = 0;
  $self->{message_id} = decode_short($self->{remaining}, \$offset);
  while ($offset < length $self->{remaining}) {
    push @{$self->{qos_levels}}, decode_byte($self->{remaining}, \$offset)&0x3;
  }
  substr $self->{remaining}, 0, $offset, '';
}

sub _remaining_bytes {
  my $self = shift;
  my $o = encode_short($self->message_id);
  foreach my $qos (@{$self->qos_levels}) {
    $o .= encode_byte($qos);
  }
  $o
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::SubAck - Perl module to represent an MQTT SubAck message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Subscription Acknowledgement
message.  It is a specific subclass used by L<Net::MQTT::Message>
and should not need to be instantiated directly.

=head1 METHODS

=head2 C<message_id()>

Returns the message id field of the MQTT Subscription Acknowledgement
message.

=head2 C<qos_levels()>

Returns the list of granted QoS fields of the MQTT Subscription
Acknowledgement message.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

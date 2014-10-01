use strict;
use warnings;
package Net::MQTT::Message::ConnAck;
$Net::MQTT::Message::ConnAck::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT ConnAck message


use base 'Net::MQTT::Message';
use Net::MQTT::Constants qw/:all/;

sub message_type {
  2
}


sub connack_reserved { shift->{connack_reserved} || 0 }


sub return_code { shift->{return_code} || MQTT_CONNECT_ACCEPTED }

sub _remaining_string {
  my ($self, $prefix) = @_;
  connect_return_code_string($self->return_code).
    ' '.$self->SUPER::_remaining_string($prefix)
}

sub _parse_remaining {
  my $self = shift;
  my $offset = 0;
  $self->{connack_reserved} = decode_byte($self->{remaining}, \$offset);
  $self->{return_code} = decode_byte($self->{remaining}, \$offset);
  substr $self->{remaining}, 0, $offset, '';
}

sub _remaining_bytes {
  my $self = shift;
  my $o = encode_byte($self->connack_reserved);
  $o .= encode_byte($self->return_code);
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::ConnAck - Perl module to represent an MQTT ConnAck message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Connection Acknowledgement
message.  It is a specific subclass used by L<Net::MQTT::Message>
and should not need to be instantiated directly.

=head1 METHODS

=head2 C<connack_reserved()>

Returns the reserved field of the MQTT Connection Acknowledgement
message.

=head2 C<return_code()>

Returns the return code field of the MQTT Connection Acknowledgement
message.  The module L<Net::MQTT::Constants> provides a function,
C<connect_return_code_string>, that can be used to convert this value
to a human readable string.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

use strict;
use warnings;
package Net::MQTT::Message::JustMessageId;
$Net::MQTT::Message::JustMessageId::VERSION = '1.142010';
# ABSTRACT: Perl module for an MQTT message w/message id only payload


use base 'Net::MQTT::Message';
use Net::MQTT::Constants qw/:all/;


sub message_id { shift->{message_id} }

sub _remaining_string {
  my ($self, $prefix) = @_;
  $self->message_id.' '.$self->SUPER::_remaining_string($prefix)
}

sub _parse_remaining {
  my $self = shift;
  my $offset = 0;
  $self->{message_id} = decode_short($self->{remaining}, \$offset);
  substr $self->{remaining}, 0, $offset, '';
}

sub _remaining_bytes {
  my $self = shift;
  encode_short($self->message_id)
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::JustMessageId - Perl module for an MQTT message w/message id only payload

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # abstract class not instantiated directly

=head1 DESCRIPTION

This module encapsulates a single MQTT message that has only a message id
in its payload.  This is an abstract class used to implement a number
of other MQTT messages such as PubAck, PubComp, etc.

=head1 METHODS

=head2 C<message_id()>

Returns the message id field of the MQTT message.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

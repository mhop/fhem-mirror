use strict;
use warnings;
package Net::MQTT::Message::Publish;
$Net::MQTT::Message::Publish::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT Publish message


use base 'Net::MQTT::Message';
use Net::MQTT::Constants qw/:all/;

sub message_type {
  3
}


sub topic { shift->{topic} }


sub message_id { shift->{message_id} }


sub message { shift->{message} }

sub _message_string { shift->{message} }

sub _remaining_string {
  my $self = shift;
  $self->topic.
    ($self->qos ? '/'.$self->message_id : '').
      ' '.dump_string($self->_message_string)
}

sub _parse_remaining {
  my $self = shift;
  my $offset = 0;
  $self->{topic} = decode_string($self->{remaining}, \$offset);
  $self->{message_id} = decode_short($self->{remaining}, \$offset)
    if ($self->qos);
  $self->{message} = substr $self->{remaining}, $offset;
  $self->{remaining} = '';
}

sub _remaining_bytes {
  my $self = shift;
  my $o = encode_string($self->topic);
  if ($self->qos) {
    $o .= encode_short($self->message_id);
  }
  $o .= $self->message;
  $o;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::Publish - Perl module to represent an MQTT Publish message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Publish message.  It
is a specific subclass used by L<Net::MQTT::Message> and should
not need to be instantiated directly.

=head1 METHODS

=head2 C<topic()>

Returns the topic field of the MQTT Publish message.

=head2 C<message_id()>

Returns the message id field of the MQTT Publish message.

=head2 C<message()>

Returns the message field of the MQTT Publish message.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

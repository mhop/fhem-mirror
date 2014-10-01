use strict;
use warnings;
package Net::MQTT::Message::Subscribe;
$Net::MQTT::Message::Subscribe::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT Subscribe message


use base 'Net::MQTT::Message';
use Net::MQTT::Constants qw/:all/;

sub message_type {
  8
}

sub _default_qos {
  MQTT_QOS_AT_LEAST_ONCE
}


sub message_id { shift->{message_id} }


sub topics { shift->{topics} }

sub _topics_string {
  join  ',', map { $_->[0].'/'.qos_string($_->[1]) } @{shift->{topics}}
}

sub _remaining_string {
  my ($self, $prefix) = @_;
  $self->message_id.' '.$self->_topics_string.' '.
    $self->SUPER::_remaining_string($prefix)
}

sub _parse_remaining {
  my $self = shift;
  my $offset = 0;
  $self->{message_id} = decode_short($self->{remaining}, \$offset);
  while ($offset < length $self->{remaining}) {
    push @{$self->{topics}}, [ decode_string($self->{remaining}, \$offset),
                               decode_byte($self->{remaining}, \$offset) ];
  }
  substr $self->{remaining}, 0, $offset, '';
}

sub _remaining_bytes {
  my $self = shift;
  my $o = encode_short($self->message_id);
  foreach my $r (@{$self->topics}) {
    my ($name, $qos) = @$r;
    $o .= encode_string($name);
    $o .= encode_byte($qos);
  }
  $o
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::Subscribe - Perl module to represent an MQTT Subscribe message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Subscribe message.  It is a
specific subclass used by L<Net::MQTT::Message> and should not
need to be instantiated directly.

=head1 METHODS

=head2 C<message_id()>

Returns the message id field of the MQTT Subscribe message.

=head2 C<topics()>

Returns the list of topics of the MQTT Subscribe message.  Each
element of the list is a 2-ple containing the topic and its associated
requested QoS level.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

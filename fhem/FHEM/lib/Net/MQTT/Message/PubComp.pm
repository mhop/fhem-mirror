use strict;
use warnings;
package Net::MQTT::Message::PubComp;
$Net::MQTT::Message::PubComp::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT PubComp message


use base 'Net::MQTT::Message::JustMessageId';
use Net::MQTT::Constants qw/:all/;

sub message_type {
  7
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::PubComp - Perl module to represent an MQTT PubComp message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Publish Complete message.  It
is a specific subclass used by L<Net::MQTT::Message> and should
not need to be instantiated directly.

=head1 METHODS

=head2 C<message_id()>

Returns the message id field of the MQTT Publish Complete message.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

use strict;
use warnings;
package Net::MQTT::Message::PingResp;
$Net::MQTT::Message::PingResp::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT PingResp message


use base 'Net::MQTT::Message';

sub message_type {
  13
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::PingResp - Perl module to represent an MQTT PingResp message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Ping Response message.  It is a
specific subclass used by L<Net::MQTT::Message> and should not
need to be instantiated directly.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

use strict;
use warnings;
package Net::MQTT::Message::Connect;
$Net::MQTT::Message::Connect::VERSION = '1.142010';
# ABSTRACT: Perl module to represent an MQTT Connect message


use base 'Net::MQTT::Message';
use Net::MQTT::Constants qw/:all/;

sub message_type {
  1
}


sub protocol_name { shift->{protocol_name} || 'MQIsdp' }


sub protocol_version { shift->{protocol_version} || 3 }


sub user_name_flag {
  my $self = shift;
  $self->{user_name_flag} || defined $self->{user_name};
}


sub password_flag {
  my $self = shift;
  $self->{password_flag} || defined $self->{password};
}


sub will_retain { shift->{will_retain} || 0 }


sub will_qos { shift->{will_qos} || 0 }


sub will_flag {
  my $self = shift;
  $self->{will_flag} || defined $self->{will_topic}
}


sub clean_session {
  my $self = shift;
  defined $self->{clean_session} ? $self->{clean_session} : 1
}


sub connect_reserved_flag { shift->{connect_reserved_flag} || 0 }


sub keep_alive_timer { shift->{keep_alive_timer} || 60 }


sub client_id { shift->{client_id} || 'Net::MQTT::Message['.$$.']' }


sub will_topic { shift->{will_topic} }


sub will_message { shift->{will_message} }


sub user_name { shift->{user_name} }


sub password { shift->{password} }

sub _remaining_string {
  my ($self, $prefix) = @_;
  $self->protocol_name.'/'.$self->protocol_version.'/'.$self->client_id.
    ($self->user_name_flag ? ' user='.$self->user_name : '').
    ($self->password_flag ? ' pass='.$self->password : '').
    ($self->will_flag
     ? ' will='.$self->will_topic.',"'.$self->will_message.'",'.
       $self->will_retain.','.qos_string($self->will_qos) : '').
    ' '.$self->SUPER::_remaining_string($prefix)
}

sub _parse_remaining {
  my $self = shift;
  my $offset = 0;
  $self->{protocol_name} = decode_string($self->{remaining}, \$offset);
  $self->{protocol_version} = decode_byte($self->{remaining}, \$offset);
  my $b = decode_byte($self->{remaining}, \$offset);
  $self->{user_name_flag} = ($b&0x80) >> 7;
  $self->{password_flag} = ($b&0x40) >> 6;
  $self->{will_retain} = ($b&0x20) >> 5;
  $self->{will_qos} = ($b&0x18) >> 3;
  $self->{will_flag} = ($b&0x4) >> 2;
  $self->{clean_session} = ($b&0x2) >> 1;
  $self->{connect_reserved_flag} = $b&0x1;
  $self->{keep_alive_timer} = decode_short($self->{remaining}, \$offset);
  $self->{client_id} = decode_string($self->{remaining}, \$offset);
  if ($self->will_flag) {
    $self->{will_topic} = decode_string($self->{remaining}, \$offset);
    $self->{will_message} = decode_string($self->{remaining}, \$offset);
  }
  if ($self->user_name_flag) {
    $self->{user_name} = decode_string($self->{remaining}, \$offset);
  }
  if ($self->password_flag) {
    $self->{password} = decode_string($self->{remaining}, \$offset);
  }
  substr $self->{remaining}, 0, $offset, '';
}

sub _remaining_bytes {
  my $self = shift;
  my $o = encode_string($self->protocol_name);
  $o .= encode_byte($self->protocol_version);
  $o .= encode_byte(
                    ($self->user_name_flag << 7) |
                    ($self->password_flag << 6) |
                    ($self->will_retain << 5) | ($self->will_qos << 3) |
                    ($self->will_flag << 2) |
                    ($self->clean_session << 1) |
                    $self->connect_reserved_flag);
  $o .= encode_short($self->keep_alive_timer);
  $o .= encode_string($self->client_id);
  $o .= encode_string($self->will_topic) if ($self->will_flag);
  $o .= encode_string($self->will_message) if ($self->will_flag);
  $o .= encode_string($self->user_name) if ($self->user_name_flag);
  $o .= encode_string($self->password) if ($self->password_flag);
  $o;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Net::MQTT::Message::Connect - Perl module to represent an MQTT Connect message

=head1 VERSION

version 1.142010

=head1 SYNOPSIS

  # instantiated by Net::MQTT::Message

=head1 DESCRIPTION

This module encapsulates a single MQTT Connection Request message.  It
is a specific subclass used by L<Net::MQTT::Message> and should
not need to be instantiated directly.

=head1 METHODS

=head2 C<protocol_name()>

Returns the protocol name field of the MQTT Connect message.  The
default is 'C<MQIsdp>'.

=head2 C<protocol_version()>

Returns the protocol version field of the MQTT Connect message.  The
default is 3.

=head2 C<user_name_flag()>

Returns the user name flag field of the MQTT Connect message.  The
default is true if and only if a user name is defined.

=head2 C<password_flag()>

Returns the password flag field of the MQTT Connect message.  The
default is true if and only if a password is defined.

=head2 C<will_retain()>

Returns the will retain field of the MQTT Connect message.  The
default is 0.

=head2 C<will_qos()>

Returns the will QoS field of the MQTT Connect message.  The default
is 0.

=head2 C<will_flag()>

Returns the will flag field of the MQTT Connect message.  The
default is true if and only if a will topic is defined.

=head2 C<clean_session()>

Returns the clean session flag field of the MQTT Connect message.  The
default is 1.

=head2 C<connect_reserved_flag()>

Returns the reserved flag field of the MQTT Connect message.  The
default is 0.

=head2 C<keep_alive_timer()>

Returns the keep alive timer field of the MQTT Connect message.  The
units are seconds.  The default is 60.

=head2 C<client_id()>

Returns the client identifier field of the MQTT Connect message.  The
default is 'C<Net::MQTT::Message[$$]>' where 'C<$$>' is the
current process id.

=head2 C<will_topic()>

Returns the will topic field of the MQTT Connect message.  The default
is undefined.

=head2 C<will_message()>

Returns the will message field of the MQTT Connect message.  The
default is undefined.

=head2 C<user_name()>

Returns the user name field of the MQTT Connect message.  The default
is undefined.

=head2 C<password()>

Returns the password field of the MQTT Connect message.  The default
is undefined.

=head1 AUTHOR

Mark Hindess <soft-cpan@temporalanomaly.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Mark Hindess.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

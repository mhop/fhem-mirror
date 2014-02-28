package Device::Firmata::Protocol;

=head1 NAME

Device::Firmata::Protocol - details of the actual firmata protocol

=cut

use strict;
use warnings;
use vars qw/ $MIDI_DATA_SIZES /;

use constant {
  MIDI_COMMAND                => 0x80,
  MIDI_PARSE_NORMAL           => 0,
  MIDI_PARSE_SYSEX            => 1,
  MIDI_START_SYSEX            => 0xf0,
  MIDI_END_SYSEX              => 0xf7,
};

use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::Base
  ISA                         => 'Device::Firmata::Base',
  FIRMATA_ATTRIBS             => {
  buffer                      => [],
  parse_status                => MIDI_PARSE_NORMAL,
  protocol_version            => 'V_2_04', # We are starting with the highest protocol
  };

$MIDI_DATA_SIZES = {
  0x80                        => 2,
  0x90                        => 2,
  0xA0                        => 2,
  0xB0                        => 2,
  0xC0                        => 1,
  0xD0                        => 1,
  0xE0                        => 2,
  0xF0                        => 0,    # note that this requires special handling

  # Special for version queries
  0xF4                        => 2,
  0xF9                        => 2,
  0x71                        => 0,
  0xFF                        => 0,
};

our $ONE_WIRE_COMMANDS = {
  SEARCH_REQUEST              => 0x40,
  CONFIG_REQUEST              => 0x41,
  SEARCH_REPLY                => 0x42,
  READ_REPLY                  => 0x43,
  SEARCH_ALARMS_REQUEST       => 0x44,
  SEARCH_ALARMS_REPLY         => 0x45,
  RESET_REQUEST_BIT           => 0x01,
  SKIP_REQUEST_BIT            => 0x02,
  SELECT_REQUEST_BIT          => 0x04,
  READ_REQUEST_BIT            => 0x08,
  DELAY_REQUEST_BIT           => 0x10,
  WRITE_REQUEST_BIT           => 0x20,
};

our $SCHEDULER_COMMANDS = {
  CREATE_FIRMATA_TASK         => 0,
  DELETE_FIRMATA_TASK         => 1,
  ADD_TO_FIRMATA_TASK         => 2,
  DELAY_FIRMATA_TASK          => 3,
  SCHEDULE_FIRMATA_TASK       => 4,
  QUERY_ALL_FIRMATA_TASKS     => 5,
  QUERY_FIRMATA_TASK          => 6,
  RESET_FIRMATA_TASKS         => 7,
  ERROR_TASK_REPLY            => 8,
  QUERY_ALL_TASKS_REPLY       => 9,
  QUERY_TASK_REPLY            => 10,
};

our $STEPPER_COMMANDS = {
  STEPPER_CONFIG              => 0,
  STEPPER_STEP                => 1,
};

our $ENCODER_COMMANDS = {
  ENCODER_ATTACH              => 0,
  ENCODER_REPORT_POSITION     => 1,
  ENCODER_REPORT_POSITIONS    => 2,
  ENCODER_RESET_POSITION      => 3,
  ENCODER_REPORT_AUTO         => 4,
  ENCODER_DETACH              => 5,
};

our $MODENAMES = {
  0                           => 'INPUT',
  1                           => 'OUTPUT',
  2                           => 'ANALOG',
  3                           => 'PWM',
  4                           => 'SERVO',
  5                           => 'SHIFT',
  6                           => 'I2C',
  7                           => 'ONEWIRE',
  8                           => 'STEPPER',
  9                           => 'ENCODER',
};

=head1 DESCRIPTION

Because we're dealing with a permutation of the
MIDI protocol, certain commands are one byte,
others 2 or even 3. We do this part to figure out
how many bytes we're actually looking at

One of the first things to know is that while
MIDI is packet based, the bytes have specialized
construction (where the top-most bit has been
reserved to differentiate if it's a command or a
data bit)

So any byte being transferred in a MIDI stream
will look like the following

 BIT# | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
 DATA | X | ? | ? | ? | ? | ? | ? | ? |

If X is a "1" this byte is considered a command byte
If X is a "0" this byte is considered a data bte

We figure out how many bytes a packet is by looking at the
command byte and of that byte, only the high nibble.
This nibble tells us the requisite information via a lookup
table...

See: http://www.midi.org/techspecs/midimessages.php
And
http://www.ccarh.org/courses/253/handout/midiprotocol/
For more information

Basically, however:

command
nibble  bytes
8       2
9       2
A       2
B       2
C       1
D       1
E       2
F       0 or variable

=cut

=head2 message_data_receive

Receive a string of data. Normally, only one byte
is passed due to the code, but you can also pass as
many bytes in a string as you'd like.

=cut

sub message_data_receive {

  # --------------------------------------------------
  my ( $self, $data ) = @_;

  defined $data and length $data or return;

  my $protocol_version  = $self->{protocol_version};
  my $protocol_commands = $COMMANDS->{$protocol_version};
  my $protocol_lookup   = $COMMAND_LOOKUP->{$protocol_version};

  # Add the new data to the buffer
  my $buffer = $self->{buffer} ||= [];
  push @$buffer, unpack "C*", $data;

  my @packets;

  # Loop until we're finished parsing all available packets
  while (@$buffer) {
    # Not in SYSEX mode, we can proceed normally
    if (    $self->{parse_status} == MIDI_PARSE_NORMAL and $buffer->[0] == MIDI_START_SYSEX ) {
      my $command = shift @$buffer;
      push @packets, {
          command     => $command,
          command_str => $protocol_lookup->{$command} || 'START_SYSEX',
        };
      $self->{parse_status} = MIDI_PARSE_SYSEX;
      next;
    }
    # If in sysex mode, we will check for the end of the sysex message here
    elsif ( $self->{parse_status} == MIDI_PARSE_SYSEX and $buffer->[0] == MIDI_END_SYSEX ) {
      $self->{parse_status} = MIDI_PARSE_NORMAL;
      my $command = shift @$buffer;
      push @packets, {
          command     => $command,
          command_str => $protocol_lookup->{$command} || 'END_SYSEX',
        };
    }

# Regardless of the SYSEX mode we are in, we will allow commands to interrupt the flowthrough
    elsif ( $buffer->[0] & MIDI_COMMAND ) {
      my $command = $buffer->[0] & 0xf0;
      my $bytes = ( $MIDI_DATA_SIZES->{$command} || $MIDI_DATA_SIZES->{ $buffer->[0] } ) + 1;
      last if ( @$buffer < $bytes );
      my @data = splice @$buffer, 0, $bytes;
      $command = shift @data;
      push @packets,
        {
          command     => $command,
          command_str => $protocol_lookup->{$command}
            || $protocol_lookup->{ $command & 0xf0 }
            || 'UNKNOWN',
            data => \@data
        };
    }

# We have a data byte, if we're in SYSEX mode, we'll just add that to the data stream
# packet
    elsif ( $self->{parse_status} == MIDI_PARSE_SYSEX ) {
      my $data = shift @$buffer;
      if ( @packets and $packets[-1]{command_str} eq 'DATA_SYSEX' ) {
        push @{ $packets[-1]{data} }, $data;
      }
      else {
        push @packets,
          {
            command     => 0x0,
            command_str => 'DATA_SYSEX',
            data        => [$data]
          };
      }

    }

    # No idea what to do with this one, eject it and skip to the next
    else {
      shift @$buffer;
      last if ( not @$buffer );
    }
  }

  return if not @packets;
  return \@packets;
}

=head2 sysex_parse

Takes the sysex data buffer and parses it into
something useful

=cut

sub sysex_parse {

  # --------------------------------------------------
  my ( $self, $sysex_data ) = @_;

  my $protocol_version  = $self->{protocol_version};
  my $protocol_commands = $COMMANDS->{$protocol_version};
  my $protocol_lookup   = $COMMAND_LOOKUP->{$protocol_version};

  my $command = shift @$sysex_data;
  if ( defined $command ) {
    my $command_str = $protocol_lookup->{$command};

    if ($command_str) {
      my $return_data;

      COMMAND_HANDLER: {

        $command == $protocol_commands->{STRING_DATA} and do {
          $return_data = $self->handle_string_data($sysex_data);
          last;
        };

        $command == $protocol_commands->{REPORT_FIRMWARE} and do {
          $return_data = $self->handle_report_firmware($sysex_data);
          last;
        };

        $command == $protocol_commands->{CAPABILITY_RESPONSE} and do {
          $return_data = $self->handle_capability_response($sysex_data);
          last;
        };

        $command == $protocol_commands->{ANALOG_MAPPING_RESPONSE} and do {
          $return_data =
            $self->handle_analog_mapping_response($sysex_data);
          last;
        };

        $command == $protocol_commands->{PIN_STATE_RESPONSE} and do {
          $return_data = $self->handle_pin_state_response($sysex_data);
          last;
        };

        $command == $protocol_commands->{I2C_REPLY} and do {
          $return_data = $self->handle_i2c_reply($sysex_data);
          last;
        };

        $command == $protocol_commands->{ONEWIRE_DATA} and do {
          $return_data = $self->handle_onewire_reply($sysex_data);
          last;
        };

        $command == $protocol_commands->{SCHEDULER_DATA} and do {
          $return_data = $self->handle_scheduler_response($sysex_data);
          last;
        };
        
        $command == $protocol_commands->{STEPPER_DATA} and do {
          #TODO implement and call handle_stepper_response
          last;
        };
        
        $command == $protocol_commands->{ENCODER_DATA} and do {
          $return_data = $self->handle_encoder_response($sysex_data);
          last;
        };

        $command == $protocol_commands->{RESERVED_COMMAND} and do {
          $return_data = $sysex_data;
          last;
        };
      }

      return {
        command     => $command,
        command_str => $command_str,
        data        => $return_data
      };
    } else {
      return {
        command     => $command,
        data        => $sysex_data
      }
    }
  }
  return undef;
}

=head2 message_prepare

Using the midi protocol, create a binary packet
that can be transmitted to the serial output

=cut

sub message_prepare {

  # --------------------------------------------------
  my ( $self, $command_name, $channel, @data ) = @_;

  my $protocol_version  = $self->{protocol_version};
  my $protocol_commands = $COMMANDS->{$protocol_version};
  my $command           = $protocol_commands->{$command_name} or return;

  my $bytes = 1 +
    ( $MIDI_DATA_SIZES->{ $command & 0xf0 } || $MIDI_DATA_SIZES->{$command} );
  my $packet = pack "C" x $bytes, $command | $channel, @data;
  return $packet;
}

=head2 packet_sysex_command

create a binary packet containing a sysex-command

=cut

sub packet_sysex_command {

  my ( $self, $command_name, @data ) = @_;

  my $protocol_version  = $self->{protocol_version};
  my $protocol_commands = $COMMANDS->{$protocol_version};
  my $command           = $protocol_commands->{$command_name} or return;

#    my $bytes = 3+($MIDI_DATA_SIZES->{$command & 0xf0}||$MIDI_DATA_SIZES->{$command});
  my $bytes = @data + 3;
  my $packet = pack "C" x $bytes, $protocol_commands->{START_SYSEX},
    $command,
    @data,
    $protocol_commands->{END_SYSEX};
  return $packet;
}

=head2 packet_query_version

Craft a firmware version query packet to be sent

=cut

sub packet_query_version {
  my $self = shift;
  return $self->message_prepare( REPORT_VERSION => 0 );

}

sub handle_query_version_response {

}

sub handle_string_data {
  my ( $self, $sysex_data ) = @_;
  return { string => double_7bit_to_string($sysex_data) };
}

=head2 packet_query_firmware

Craft a firmware variant query packet to be sent

=cut

sub packet_query_firmware {
  my $self = shift;
  return $self->packet_sysex_command(REPORT_FIRMWARE);
}

sub handle_report_firmware {
  my ( $self, $sysex_data ) = @_;
  return {
      major_version => shift @$sysex_data,
      minor_version => shift @$sysex_data,
      firmware      => double_7bit_to_string($sysex_data)
    };
}

sub packet_query_capability {
  my $self = shift;
  return $self->packet_sysex_command(CAPABILITY_QUERY);
}

#/* capabilities response
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  capabilities response (0x6C)
# * 2  1st mode supported of pin 0
# * 3  1st mode's resolution of pin 0
# * 4  2nd mode supported of pin 0
# * 5  2nd mode's resolution of pin 0
# ...   additional modes/resolutions, followed by a single 127 to mark the
#       end of the first pin's modes.  Each pin follows with its mode and
#       127, until all pins implemented.
# * N  END_SYSEX (0xF7)
# */

sub handle_capability_response {
  my ( $self, $sysex_data ) = @_;
  my %capabilities;
  my $byte = shift @$sysex_data;
  my $i=0;
  while ( defined $byte ) {
    my %pinmodes;
    while ( defined $byte && $byte != 127 ) {
      $pinmodes{$byte} = {
        mode_str   => $MODENAMES->{$byte},
        resolution => shift @$sysex_data    # /secondbyte
      };
      $byte = shift @$sysex_data;
    }
    $capabilities{$i}=\%pinmodes;
    $i++;
    $byte = shift @$sysex_data;
  }
  return { capabilities => \%capabilities };
}

sub packet_query_analog_mapping {
  my $self = shift;
  return $self->packet_sysex_command(ANALOG_MAPPING_QUERY);
}

#/* analog mapping response
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  analog mapping response (0x6A)
# * 2  analog channel corresponding to pin 0, or 127 if pin 0 does not support analog
# * 3  analog channel corresponding to pin 1, or 127 if pin 1 does not support analog
# * 4  analog channel corresponding to pin 2, or 127 if pin 2 does not support analog
# ...   etc, one byte for each pin
# * N  END_SYSEX (0xF7)
# */

sub handle_analog_mapping_response {
  my ( $self, $sysex_data ) = @_;
  my %pins;
  my $pin_mapping = shift @$sysex_data;
  my $i=0;

  while ( defined $pin_mapping ) {
    $pins{$pin_mapping}=$i if ($pin_mapping!=127);
    $pin_mapping = shift @$sysex_data;
    $i++;
  }
  return { mappings => \%pins };
}

#/* pin state query
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  pin state query (0x6D)
# * 2  pin (0 to 127)
# * 3  END_SYSEX (0xF7) (MIDI End of SysEx - EOX)
# */

sub packet_query_pin_state {
  my ( $self, $pin ) = @_;
  return $self->packet_sysex_command( PIN_STATE_QUERY, $pin );
}

#/* pin state response
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  pin state response (0x6E)
# * 2  pin (0 to 127)
# * 3  pin mode (the currently configured mode)
# * 4  pin state, bits 0-6
# * 5  (optional) pin state, bits 7-13
# * 6  (optional) pin state, bits 14-20
# ...  additional optional bytes, as many as needed
# * N  END_SYSEX (0xF7)
# */

sub handle_pin_state_response {
  my ( $self, $sysex_data ) = @_;
  my $pin    = shift @$sysex_data;
  my $mode   = shift @$sysex_data;
  my $state  = shift @$sysex_data & 0x7f;
  my $nibble = shift @$sysex_data;
  for ( my $i = 1 ; defined $nibble ; $nibble = shift @$sysex_data ) {
    $state += ( $nibble & 0x7f ) << ( 7 * $i );
  }

  return {
    pin       => $pin,
    mode      => $mode,
    moden_str => $MODENAMES->{$mode},
    state     => $state
  };

}

sub packet_sampling_interval {
  my ( $self, $interval ) = @_;
  return $self->packet_sysex_command( SAMPLING_INTERVAL,
    $interval & 0x7f,
    $interval >> 7
  );
}

#/* I2C read/write request
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  I2C_REQUEST (0x76)
# * 2  slave address (LSB)
# * 3  slave address (MSB) + read/write and address mode bits
#      {7: always 0} + {6: reserved} + {5: address mode, 1 means 10-bit mode} +
#      {4-3: read/write, 00 => write, 01 => read once, 10 => read continuously, 11 => stop reading} +
#      {2-0: slave address MSB in 10-bit mode, not used in 7-bit mode}
# * 4  data 0 (LSB)
# * 5  data 0 (MSB)
# * 6  data 1 (LSB)
# * 7  data 1 (MSB)
# * ...
# * n  END_SYSEX (0xF7)
# */

sub packet_i2c_request {
  my ( $self, $address, $command, @i2cdata ) = @_;
  if (($address & 0x380) > 0) {
    $command |= (0x20 | (($address >> 7) & 0x7));
  }

  if (scalar @i2cdata) {
    my @data;
    push_array_as_two_7bit(\@i2cdata,\@data);
    return $self->packet_sysex_command( I2C_REQUEST,
      $address & 0x7f,
      $command,
      @data,
    );
  } else {
    return $self->packet_sysex_command( I2C_REQUEST,
      $address & 0x7f,
      $command,
    );
  }
}

#/* I2C reply
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  I2C_REPLY (0x77)
# * 2  slave address (LSB)
# * 3  slave address (MSB)
# * 4  register (LSB)
# * 5  register (MSB)
# * 6  data 0 LSB
# * 7  data 0 MSB
# * ...
# * n  END_SYSEX (0xF7)
# */

sub handle_i2c_reply {
  my ( $self, $sysex_data ) = @_;
  my $address = shift14bit($sysex_data);
  my $register = shift14bit($sysex_data);
  my @data = double_7bit_to_array($sysex_data);
  return {
    address       => $address,
    register      => $register,
    data          => \@data,
  };
}

#/* I2C config
# * -------------------------------
# * 0  START_SYSEX (0xF0) (MIDI System Exclusive)
# * 1  I2C_CONFIG (0x78)
# * 2  Delay in microseconds (LSB)
# * 3  Delay in microseconds (MSB)
# * ... user defined for special cases, etc
# * n  END_SYSEX (0xF7)
# */

sub packet_i2c_config {
  my ( $self, $delay, @data ) = @_;
  return $self->packet_sysex_command( I2C_CONFIG,
    $delay & 0x7f,
    $delay >> 7, @data
  );
}

#/* servo config
# * --------------------
# * 0  START_SYSEX (0xF0)
# * 1  SERVO_CONFIG (0x70)
# * 2  pin number (0-127)
# * 3  minPulse LSB (0-6)
# * 4  minPulse MSB (7-13)
# * 5  maxPulse LSB (0-6)
# * 6  maxPulse MSB (7-13)
# * 7  END_SYSEX (0xF7)
# */

sub packet_servo_config_request {
  my ( $self, $pin, $data ) = @_;
  my $min_pulse = $data->{min_pulse};
  my $max_pulse = $data->{max_pulse};

  return $self->packet_sysex_command( SERVO_CONFIG,
    $pin & 0x7f,
    $min_pulse & 0x7f,
    $min_pulse >> 7,
    $max_pulse & 0x7f,
    $max_pulse >> 7
  );
}

#This is just the standard SET_PIN_MODE message:

#/* set digital pin mode
# * --------------------
# * 1  set digital pin mode (0xF4) (MIDI Undefined)
# * 2  pin number (0-127)
# * 3  state (INPUT/OUTPUT/ANALOG/PWM/SERVO, 0/1/2/3/4)
# */

#Then the normal ANALOG_MESSAGE data format is used to send data.

#/* write to servo, servo write is performed if the pins mode is SERVO
# * ------------------------------
# * 0  ANALOG_MESSAGE (0xE0-0xEF)
# * 1  value lsb
# * 2  value msb
# */

sub packet_onewire_search_request {
  my ( $self, $pin ) = @_;
  return $self->packet_sysex_command( ONEWIRE_DATA,$ONE_WIRE_COMMANDS->{SEARCH_REQUEST},$pin);
};

sub packet_onewire_search_alarms_request {
  my ( $self, $pin ) = @_;
  return $self->packet_sysex_command( ONEWIRE_DATA,$ONE_WIRE_COMMANDS->{SEARCH_ALARMS_REQUEST},$pin);
};

sub packet_onewire_config_request {
  my ( $self, $pin, $power ) = @_;
  return $self->packet_sysex_command( ONEWIRE_DATA, $ONE_WIRE_COMMANDS->{CONFIG_REQUEST},$pin,
    ( defined $power ) ? $power : 1
  );
};

#$args = {
# reset => undef | 1,
# skip => undef | 1,
# select => undef | device,
# read => undef | short int,
# delay => undef | long int,
# write => undef | bytes[],
#}

sub packet_onewire_request {
  my ( $self, $pin, $args ) = @_;
  my $subcommand = 0;
  my @data;
  if (defined $args->{reset}) {
    $subcommand |= $ONE_WIRE_COMMANDS->{RESET_REQUEST_BIT};
  }
  if (defined $args->{skip}) {
    $subcommand |= $ONE_WIRE_COMMANDS->{SKIP_REQUEST_BIT};
  }
  if (defined $args->{select}) {
    $subcommand |= $ONE_WIRE_COMMANDS->{SELECT_REQUEST_BIT};
    push_onewire_device_to_byte_array($args->{select},\@data);
  }
  if (defined $args->{read}) {
    $subcommand |= $ONE_WIRE_COMMANDS->{READ_REQUEST_BIT};
    push @data,$args->{read} & 0xFF;
    push @data,($args->{read}>>8) & 0xFF;
    if ($self->{protocol_version} ne 'V_2_04') {
      my $id = (defined $args->{id}) ? $args->{id} : 0;
      push @data,$id &0xFF;
      push @data,($id>>8) & 0xFF;
    }
  }
  if (defined $args->{delay}) {
    $subcommand |= $ONE_WIRE_COMMANDS->{DELAY_REQUEST_BIT};
    push @data,$args->{delay} & 0xFF;
    push @data,($args->{delay}>>8) & 0xFF;
    push @data,($args->{delay}>>16) & 0xFF;
    push @data,($args->{delay}>>24) & 0xFF;
  }
  if (defined $args->{write}) {
    $subcommand |= $ONE_WIRE_COMMANDS->{WRITE_REQUEST_BIT};
    my $writeBytes=$args->{write};
    push @data,@$writeBytes;
  }
  return $self->packet_sysex_command( ONEWIRE_DATA, $subcommand, $pin, pack_as_7bit(@data));
};

sub handle_onewire_reply {
  my ( $self, $sysex_data ) = @_;
  my $command = shift @$sysex_data;
  my $pin     = shift @$sysex_data;

  if ( defined $command ) {
    COMMAND_HANDLER: {
      $command == $ONE_WIRE_COMMANDS->{READ_REPLY} and do {    #PIN,COMMAND,ADDRESS,DATA
        my @data = unpack_from_7bit(@$sysex_data);
        if ($self->{protocol_version} eq 'V_2_04') {
          my $device = shift_onewire_device_from_byte_array(\@data);
          return {
            pin     => $pin,
            command => 'READ_REPLY',
            device  => $device,
            data    => \@data
          };
        } else {
          my $id = shift @data;
          $id += (shift @data)<<8;
          return {
            pin     => $pin,
            command => 'READ_REPLY',
            id      => $id,
            data    => \@data
          };
        };
      };

      ($command == $ONE_WIRE_COMMANDS->{SEARCH_REPLY} or $command == $ONE_WIRE_COMMANDS->{SEARCH_ALARMS_REPLY}) and do {    #PIN,COMMAND,ADDRESS...
        my @devices;
        my @data = unpack_from_7bit(@$sysex_data);
        my $device = shift_onewire_device_from_byte_array(\@data);
        while ( defined $device ) {
          push @devices, $device;
          $device = shift_onewire_device_from_byte_array(\@data);
        }
        return {
          pin     => $pin,
          command => $command == $ONE_WIRE_COMMANDS->{SEARCH_REPLY} ? 'SEARCH_REPLY' : 'SEARCH_ALARMS_REPLY',
          devices => \@devices,
        };
      };
    }
  }
}

sub packet_create_task {
  my ($self,$id,$len) = @_;
  my $packet = $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{CREATE_FIRMATA_TASK}, $id, $len & 0x7F, $len>>7);
  return $packet;
}

sub packet_delete_task {
  my ($self,$id) = @_;
  return $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{DELETE_FIRMATA_TASK}, $id);
}

sub packet_add_to_task {
  my ($self,$id,@data) = @_;
  my $packet = $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{ADD_TO_FIRMATA_TASK}, $id, pack_as_7bit(@data));
  return $packet;
}

sub packet_delay_task {
  my ($self,$time_ms) = @_;
  my $packet = $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{DELAY_FIRMATA_TASK}, pack_as_7bit($time_ms & 0xFF, ($time_ms & 0xFF00)>>8, ($time_ms & 0xFF0000)>>16,($time_ms & 0xFF000000)>>24));
  return $packet;
}

sub packet_schedule_task {
  my ($self,$id,$time_ms) = @_;
  my $packet = $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{SCHEDULE_FIRMATA_TASK}, $id, pack_as_7bit($time_ms & 0xFF, ($time_ms & 0xFF00)>>8, ($time_ms & 0xFF0000)>>16,($time_ms & 0xFF000000)>>24));
  return $packet;
}

sub packet_query_all_tasks {
  my $self = shift;
  return $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{QUERY_ALL_FIRMATA_TASKS});
}

sub packet_query_task {
  my ($self,$id) = @_;
  return $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{QUERY_FIRMATA_TASK},$id);
}

sub packet_reset_scheduler {
  my $self = shift;
  return $self->packet_sysex_command('SCHEDULER_DATA', $SCHEDULER_COMMANDS->{RESET_FIRMATA_TASKS});
}

sub handle_scheduler_response {
  my ( $self, $sysex_data ) = @_;
  my $command = shift @$sysex_data;

  if ( defined $command ) {
    COMMAND_HANDLER: {
      $command == $SCHEDULER_COMMANDS->{QUERY_ALL_TASKS_REPLY} and do {
        return {
          command => 'QUERY_ALL_TASKS_REPLY',
          ids => $sysex_data,
        }
      };

      ($command == $SCHEDULER_COMMANDS->{QUERY_TASK_REPLY} or $command == $SCHEDULER_COMMANDS->{ERROR_TASK_REPLY}) and do {
        my $error = ($command == $SCHEDULER_COMMANDS->{ERROR_TASK_REPLY});
        if (scalar @$sysex_data == 1) {
          return {
            command => ($error ? 'ERROR_TASK_REPLY' : 'QUERY_TASK_REPLY'),
            id => shift @$sysex_data,
          }
        }
        if (scalar @$sysex_data >= 11) {
          my $id = shift @$sysex_data;
          my @data = unpack_from_7bit(@$sysex_data);
          return {
            command => ($error ? 'ERROR_TASK_REPLY' : 'QUERY_TASK_REPLY'),
            id => $id,
            time_ms => shift @data | (shift @data)<<8 | (shift @data)<<16 | (shift @data)<<24,
            len => shift @data  | (shift @data)<<8,
            position => shift @data  | (shift @data)<<8,
            messages => \@data,
          }
        }
      };
    }
  }
}

#TODO packet_stepper_config
sub packet_stepper_config {
  my ( $self ) = @_;
  my $packet = $self->packet_sysex_command('STEPPER_DATA', $STEPPER_COMMANDS->{STEPPER_CONFIG});
}

#TODO packet_stepper_step
sub packet_stepper_step {
  my ( $self ) = @_;
  my $packet = $self->packet_sysex_command('STEPPER_DATA', $STEPPER_COMMANDS->{STEPPER_STEP});
}

sub packet_encoder_attach {
  my ( $self,$encoderNum, $pinA, $pinB ) = @_;
  my $packet = $self->packet_sysex_command('ENCODER_DATA', $ENCODER_COMMANDS->{ENCODER_ATTACH}, $encoderNum, $pinA, $pinB);
  return $packet;
}

sub packet_encoder_report_position {
  my ( $self,$encoderNum ) = @_;
  my $packet = $self->packet_sysex_command('ENCODER_DATA', $ENCODER_COMMANDS->{ENCODER_REPORT_POSITION}, $encoderNum);
  return $packet;
}

sub packet_encoder_report_positions {
  my ( $self ) = @_;
  my $packet = $self->packet_sysex_command('ENCODER_DATA', $ENCODER_COMMANDS->{ENCODER_REPORT_POSITIONS});
  return $packet;
}

sub packet_encoder_reset_position {
  my ( $self,$encoderNum ) = @_;
  my $packet = $self->packet_sysex_command('ENCODER_DATA', $ENCODER_COMMANDS->{ENCODER_RESET_POSITION}, $encoderNum);
  return $packet;
}

sub packet_encoder_report_auto {
  my ( $self,$arg ) = @_; #TODO clarify encoder_report_auto $arg
  my $packet = $self->packet_sysex_command('ENCODER_DATA', $ENCODER_COMMANDS->{ENCODER_REPORT_AUTO}, $arg);
  return $packet;
}

sub packet_encoder_detach {
  my ( $self,$encoderNum ) = @_;
  my $packet = $self->packet_sysex_command('ENCODER_DATA', $ENCODER_COMMANDS->{ENCODER_DETACH}, $encoderNum);
  return $packet;
}

sub handle_encoder_response {
  my ( $self, $sysex_data ) = @_;
  
  my @retval = ();
  
  while (@$sysex_data) {
    
    my $command = shift @$sysex_data;
    my $direction = ($command & 0x40) >> 6;
    my $encoderNum = $command & 0x3f;
    my $value = shift14bit($sysex_data) + (shift14bit($sysex_data) << 14);
    
    push @retval,{
      encoderNum => $encoderNum,
      value => $direction ? -1 * $value : $value,
    };
  };
  
  return \@retval;
}


sub shift14bit {
  my $data = shift;
  my $lsb  = shift @$data;
  my $msb  = shift @$data;
  return
      defined $lsb
    ? defined $msb
      ? ( $msb << 7 ) + ( $lsb & 0x7f )
      : $lsb
    : undef;
}

sub double_7bit_to_string {
  my ( $data, $numbytes ) = @_;
  my $ret;
  if ( defined $numbytes ) {
    for ( my $i = 0 ; $i < $numbytes ; $i++ ) {
      my $value = shift14bit($data);
      $ret .= chr($value);
    }
  }
  else {
    while (@$data) {
      my $value = shift14bit($data);
      $ret .= chr($value);
    }
  }
  return $ret;
}

sub double_7bit_to_array {
  my ( $data, $numbytes ) = @_;
  my @ret;
  if ( defined $numbytes ) {
    for ( my $i = 0 ; $i < $numbytes ; $i++ ) {
      push @ret, shift14bit($data);
    }
  }
  else {
    while (@$data) {
      my $value = shift14bit($data);
      push @ret, $value;
    }
  }
  return @ret;
}

sub shift_onewire_device_from_byte_array {
  my $buffer = shift;
  my $family = shift @$buffer;
  if ( defined $family ) {
    my @address;
    for (my $i=0;$i<6;$i++) { push @address,shift @$buffer; }
    my $crc = shift @$buffer;
    return {
      family   => $family,
      identity => \@address,
      crc      => $crc
    };
  }
  else {
    return undef;
  }
}

sub push_value_as_two_7bit {
  my ( $value, $buffer ) = @_;
  push @$buffer, $value & 0x7f;    #LSB
  push @$buffer, ( $value >> 7 ) & 0x7f;    #MSB
}

sub push_onewire_device_to_byte_array {
  my ( $device, $buffer ) = @_;
  push @$buffer, $device->{family};
  for ( my $i = 0 ; $i < 6 ; $i++ ) { push @$buffer, $device->{identity}[$i]; }
  push @$buffer, $device->{crc};
}

sub push_array_as_two_7bit {
  my ( $data, $buffer ) = @_;
  my $byte = shift @$data;
  while ( defined $byte ) {
    push_value_as_two_7bit( $byte, $buffer );
    $byte = shift @$data;
  }
}

sub pack_as_7bit {
  my @data = @_;
  my @outdata;
  my $numBytes    = @data;
  my $messageSize = ( $numBytes << 3 ) / 7;
  for ( my $i = 0 ; $i < $messageSize ; $i++ ) {
    my $j     = $i * 7;
    my $pos   = $j >> 3;
    my $shift = $j & 7;
    my $out   = $data[$pos] >> $shift & 0x7F;
    printf "%b, %b, %d\n",$data[$pos],$out,$shift if ($out >> 7 > 0);
    $out |= ( $data[ $pos + 1 ] << ( 8 - $shift ) ) & 0x7F if ( $shift > 1 && $pos < $numBytes-1 );
    push( @outdata, $out );
  }
  return @outdata;
}

sub unpack_from_7bit {
  my @data = @_;
  my @outdata;
  my $numBytes = @data;
  my $outBytes = ( $numBytes * 7 ) >> 3;
  for ( my $i = 0 ; $i < $outBytes ; $i++ ) {
    my $j     = $i << 3;
    my $pos   = $j / 7;
    my $shift = $j % 7;
    push( @outdata,
      ( $data[$pos] >> $shift ) |
        ( ( $data[ $pos + 1 ] << ( 7 - $shift ) ) & 0xFF ) );
  }
  return @outdata;
}

1;

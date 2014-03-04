package Device::Firmata::Constants;

=head1 NAME

Device::Firmata::Constants - constants used in the Device::Firmata system

=cut

use strict;
use Exporter;
use vars qw/
  @ISA @EXPORT_OK %EXPORT_TAGS
  $BASE
  $COMMANDS $COMMAND_NAMES
  $COMMAND_LOOKUP
  /;
@ISA = 'Exporter';

# Basic commands and constants
use constant (
  $BASE = {
    PIN_INPUT   => 0,
    PIN_OUTPUT  => 1,
    PIN_ANALOG  => 2,
    PIN_PWM     => 3,
    PIN_SERVO   => 4,
    PIN_SHIFT   => 5,
    PIN_I2C     => 6,
    PIN_ONEWIRE => 7,
    PIN_STEPPER => 8,
    PIN_ENCODER => 9,
    PIN_LOW  => 0,
    PIN_HIGH => 1,
  }
);

# We need to apply all the available protocols
use constant (
  $COMMANDS = {

    V_2_01 => {

      MAX_DATA_BYTES           => 32,   # max number of data bytes in non-Sysex messages

      # message command bytes (128-255/0x80-0xFF)
      DIGITAL_MESSAGE          => 0x90, # send data for a digital pin
      ANALOG_MESSAGE           => 0xE0, # send data for an analog pin (or PWM)
      REPORT_ANALOG            => 0xC0, # enable analog input by pin #
      REPORT_DIGITAL           => 0xD0, # enable digital input by port pair
      SET_PIN_MODE             => 0xF4, # set a pin to INPUT/OUTPUT/PWM/etc
      REPORT_VERSION           => 0xF9, # report protocol version
      SYSTEM_RESET             => 0xFF, # reset from MIDI
      START_SYSEX              => 0xF0, # start a MIDI Sysex message
      END_SYSEX                => 0xF7, # end a MIDI Sysex message

      # extended command set using sysex (0-127/0x00-0x7F)
      SERVO_CONFIG             => 0x70, # set max angle, minPulse, maxPulse, freq
      STRING_DATA              => 0x71, # a string message with 14-bits per char
      SHIFT_DATA               => 0x75, # a bitstream to/from a shift register
      I2C_REQUEST              => 0x76, # send an I2C read/write request
      I2C_REPLY                => 0x77, # a reply to an I2C read request
      I2C_CONFIG               => 0x78, # config I2C settings such as delay times and power pins
      REPORT_FIRMWARE          => 0x79, # report name and version of the firmware
      SAMPLING_INTERVAL        => 0x7A, # set the poll rate of the main loop
      SYSEX_NON_REALTIME       => 0x7E, # MIDI Reserved for non-realtime messages
      SYSEX_REALTIME           => 0x7F, # MIDI Reserved for realtime messages

      # these are DEPRECATED to make the naming more consistent
      FIRMATA_STRING           => 0x71, # same as STRING_DATA
      SYSEX_I2C_REQUEST        => 0x76, # same as I2C_REQUEST
      SYSEX_I2C_REPLY          => 0x77, # same as I2C_REPLY
      SYSEX_SAMPLING_INTERVAL  => 0x7A, # same as SAMPLING_INTERVAL

      # pin modes
      INPUT                    => 0x00, # digital pin in digitalOut mode
      OUTPUT                   => 0x01, # digital pin in digitalInput mode
      ANALOG                   => 0x02, # analog pin in analogInput mode
      PWM                      => 0x03, # digital pin in PWM output mode
      SERVO                    => 0x04, # digital pin in Servo output mode
      SHIFT                    => 0x05, # shiftIn/shiftOut mode
      I2C                      => 0x06, # pin included in I2C setup

      # Deprecated entries
      deprecated => [
        qw( FIRMATA_STRING SYSEX_I2C_REQUEST SYSEX_I2C_REPLY SYSEX_SAMPLING_INTERVAL )
      ],
    }, # /Constants for Version 2.1

    V_2_02 => {

      MAX_DATA_BYTES           => 32,   # max number of data bytes in non-Sysex messages

      # message command bytes (128-255/0x80-0xFF)
      DIGITAL_MESSAGE          => 0x90, # send data for a digital pin
      ANALOG_MESSAGE           => 0xE0, # send data for an analog pin (or PWM)
      REPORT_ANALOG            => 0xC0, # enable analog input by pin #
      REPORT_DIGITAL           => 0xD0, # enable digital input by port pair
      SET_PIN_MODE             => 0xF4, # set a pin to INPUT/OUTPUT/PWM/etc
      REPORT_VERSION           => 0xF9, # report protocol version
      SYSTEM_RESET             => 0xFF, # reset from MIDI
      START_SYSEX              => 0xF0, # start a MIDI Sysex message
      END_SYSEX                => 0xF7, # end a MIDI Sysex message

      # extended command set using sysex (0-127/0x00-0x7F)
      RESERVED_COMMAND         => 0x00, # 2nd SysEx data byte is a chip-specific command (AVR, PIC, TI, etc).
      ANALOG_MAPPING_QUERY     => 0x69, # ask for mapping of analog to pin numbers
      ANALOG_MAPPING_RESPONSE  => 0x6A, # reply with mapping info
      CAPABILITY_QUERY         => 0x6B, # ask for supported modes and resolution of all pins
      CAPABILITY_RESPONSE      => 0x6C, # reply with supported modes and resolution
      PIN_STATE_QUERY          => 0x6D, # ask for a pin's current mode and value
      PIN_STATE_RESPONSE       => 0x6E, # reply with a pin's current mode and value
      EXTENDED_ANALOG          => 0x6F, # analog write (PWM, Servo, etc) to any pin
      SERVO_CONFIG             => 0x70, # set max angle, minPulse, maxPulse, freq
      STRING_DATA              => 0x71, # a string message with 14-bits per char
      SHIFT_DATA               => 0x75, # shiftOut config/data message (34 bits)
      I2C_REQUEST              => 0x76, # send an I2C read/write request
      I2C_REPLY                => 0x77, # a reply to an I2C read request
      I2C_CONFIG               => 0x78, # config I2C settings such as delay times and power pins
      REPORT_FIRMWARE          => 0x79, # report name and version of the firmware
      SAMPLING_INTERVAL        => 0x7A, # set the poll rate of the main loop
      SYSEX_NON_REALTIME       => 0x7E, # MIDI Reserved for non-realtime messages
      SYSEX_REALTIME           => 0x7F, # MIDI Reserved for realtime messages

      # pin modes
      INPUT                    => 0x00, # digital pin in digitalOut mode
      OUTPUT                   => 0x01, # digital pin in digitalInput mode
      ANALOG                   => 0x02, # analog pin in analogInput mode
      PWM                      => 0x03, # digital pin in PWM output mode
      SERVO                    => 0x04, # digital pin in Servo output mode
      SHIFT                    => 0x05, # shiftIn/shiftOut mode
      I2C                      => 0x06, # pin included in I2C setup

      # Deprecated entries
      deprecated => [
        qw( FIRMATA_STRING SYSEX_I2C_REQUEST SYSEX_I2C_REPLY SYSEX_SAMPLING_INTERVAL )
      ],

    },    # /Constants for Version 2.2

    V_2_03 => { 

      MAX_DATA_BYTES           =>  32, # max number of data bytes in non-Sysex messages

      # message command bytes (128-255/0x80-0xFF)
      DIGITAL_MESSAGE          => 0x90, # send data for a digital pin
      ANALOG_MESSAGE           => 0xE0, # send data for an analog pin (or PWM)
      REPORT_ANALOG            => 0xC0, # enable analog input by pin #
      REPORT_DIGITAL           => 0xD0, # enable digital input by port pair
      SET_PIN_MODE             => 0xF4, # set a pin to INPUT/OUTPUT/PWM/etc
      REPORT_VERSION           => 0xF9, # report protocol version
      SYSTEM_RESET             => 0xFF, # reset from MIDI
      START_SYSEX              => 0xF0, # start a MIDI Sysex message
      END_SYSEX                => 0xF7, # end a MIDI Sysex message

      # extended command set using sysex (0-127/0x00-0x7F)
      RESERVED_COMMAND         => 0x00, # 2nd SysEx data byte is a chip-specific command (AVR, PIC, TI, etc).
      ANALOG_MAPPING_QUERY     => 0x69, # ask for mapping of analog to pin numbers
      ANALOG_MAPPING_RESPONSE  => 0x6A, # reply with mapping info
      CAPABILITY_QUERY         => 0x6B, # ask for supported modes and resolution of all pins
      CAPABILITY_RESPONSE      => 0x6C, # reply with supported modes and resolution
      PIN_STATE_QUERY          => 0x6D, # ask for a pin's current mode and value
      PIN_STATE_RESPONSE       => 0x6E, # reply with a pin's current mode and value
      EXTENDED_ANALOG          => 0x6F, # analog write (PWM, Servo, etc) to any pin
      SERVO_CONFIG             => 0x70, # set max angle, minPulse, maxPulse, freq
      STRING_DATA              => 0x71, # a string message with 14-bits per char
      SHIFT_DATA               => 0x75, # shiftOut config/data message (34 bits)
      I2C_REQUEST              => 0x76, # send an I2C read/write request
      I2C_REPLY                => 0x77, # a reply to an I2C read request
      I2C_CONFIG               => 0x78, # config I2C settings such as delay times and power pins
      REPORT_FIRMWARE          => 0x79, # report name and version of the firmware
      SAMPLING_INTERVAL        => 0x7A, # set the poll rate of the main loop
      SYSEX_NON_REALTIME       => 0x7E, # MIDI Reserved for non-realtime messages
      SYSEX_REALTIME           => 0x7F, # MIDI Reserved for realtime messages

      # pin modes
      INPUT                    => 0x00, # digital pin in digitalOut mode
      OUTPUT                   => 0x01, # digital pin in digitalInput mode
      ANALOG                   => 0x02, # analog pin in analogInput mode
      PWM                      => 0x03, # digital pin in PWM output mode
      SERVO                    => 0x04, # digital pin in Servo output mode
      SHIFT                    => 0x05, # shiftIn/shiftOut mode
      I2C                      => 0x06, # pin included in I2C setup

      # Deprecated entries
      deprecated => [
        qw( FIRMATA_STRING SYSEX_I2C_REQUEST SYSEX_I2C_REPLY SYSEX_SAMPLING_INTERVAL )
      ],

    },    # /Constants for Version 2.3 (same as V_2_02)

    V_2_04 => {

      MAX_DATA_BYTES           => 64,   # max number of data bytes in non-Sysex messages

      # message command bytes (128-255/0x80-0xFF)
      DIGITAL_MESSAGE          => 0x90, # send data for a digital pin
      ANALOG_MESSAGE           => 0xE0, # send data for an analog pin (or PWM)
      REPORT_ANALOG            => 0xC0, # enable analog input by pin #
      REPORT_DIGITAL           => 0xD0, # enable digital input by port pair
      SET_PIN_MODE             => 0xF4, # set a pin to INPUT/OUTPUT/PWM/etc
      REPORT_VERSION           => 0xF9, # report protocol version
      SYSTEM_RESET             => 0xFF, # reset from MIDI
      START_SYSEX              => 0xF0, # start a MIDI Sysex message
      END_SYSEX                => 0xF7, # end a MIDI Sysex message

      # extended command set using sysex (0-127/0x00-0x7F)
      RESERVED_COMMAND         => 0x00, # 2nd SysEx data byte is a chip-specific command (AVR, PIC, TI, etc).
      ANALOG_MAPPING_QUERY     => 0x69, # ask for mapping of analog to pin numbers
      ANALOG_MAPPING_RESPONSE  => 0x6A, # reply with mapping info
      CAPABILITY_QUERY         => 0x6B, # ask for supported modes and resolution of all pins
      CAPABILITY_RESPONSE      => 0x6C, # reply with supported modes and resolution
      PIN_STATE_QUERY          => 0x6D, # ask for a pin's current mode and value
      PIN_STATE_RESPONSE       => 0x6E, # reply with a pin's current mode and value
      EXTENDED_ANALOG          => 0x6F, # analog write (PWM, Servo, etc) to any pin
      SERVO_CONFIG             => 0x70, # set max angle, minPulse, maxPulse, freq
      STRING_DATA              => 0x71, # a string message with 14-bits per char
      STEPPER_DATA             => 0x72, # control a stepper motor
      ONEWIRE_DATA             => 0x73, # OneWire read/write/reset/select/skip/search request + read/search reply
      SHIFT_DATA               => 0x75, # shiftOut config/data message (34 bits)
      I2C_REQUEST              => 0x76, # send an I2C read/write request
      I2C_REPLY                => 0x77, # a reply to an I2C read request
      I2C_CONFIG               => 0x78, # config I2C settings such as delay times and power pins
      REPORT_FIRMWARE          => 0x79, # report name and version of the firmware
      SAMPLING_INTERVAL        => 0x7A, # set the poll rate of the main loop
      SCHEDULER_DATA           => 0x7B, # createtask/deletetask/addtotask/schedule/querytasks/querytask request and querytasks/querytask reply
      SYSEX_NON_REALTIME       => 0x7E, # MIDI Reserved for non-realtime messages
      SYSEX_REALTIME           => 0x7F, # MIDI Reserved for realtime messages

      # pin modes
      INPUT                    => 0x00, # digital pin in digitalOut mode
      OUTPUT                   => 0x01, # digital pin in digitalInput mode
      ANALOG                   => 0x02, # analog pin in analogInput mode
      PWM                      => 0x03, # digital pin in PWM output mode
      SERVO                    => 0x04, # digital pin in Servo output mode
      SHIFT                    => 0x05, # shiftIn/shiftOut mode
      I2C                      => 0x06, # pin included in I2C setup
      ONEWIRE                  => 0x07, # pin configured for 1-Wire commuication
      STEPPER                  => 0x08, # pin configured for stepper motor

      # Deprecated entries
      deprecated => [
        qw( FIRMATA_STRING SYSEX_I2C_REQUEST SYSEX_I2C_REPLY SYSEX_SAMPLING_INTERVAL )
      ],
    },    # /Constants for Version 2.4

    V_2_05 => {

      MAX_DATA_BYTES           => 64, # max number of data bytes in non-Sysex messages

      # message command bytes (128-255/0x80-0xFF)
      DIGITAL_MESSAGE          => 0x90, # send data for a digital pin
      ANALOG_MESSAGE           => 0xE0, # send data for an analog pin (or PWM)
      REPORT_ANALOG            => 0xC0, # enable analog input by pin #
      REPORT_DIGITAL           => 0xD0, # enable digital input by port pair
      SET_PIN_MODE             => 0xF4, # set a pin to INPUT/OUTPUT/PWM/etc
      REPORT_VERSION           => 0xF9, # report protocol version
      SYSTEM_RESET             => 0xFF, # reset from MIDI
      START_SYSEX              => 0xF0, # start a MIDI Sysex message
      END_SYSEX                => 0xF7, # end a MIDI Sysex message

      # extended command set using sysex (0-127/0x00-0x7F)
      RESERVED_COMMAND         => 0x00, # 2nd SysEx data byte is a chip-specific command (AVR, PIC, TI, etc).
      ANALOG_MAPPING_QUERY     => 0x69, # ask for mapping of analog to pin numbers
      ANALOG_MAPPING_RESPONSE  => 0x6A, # reply with mapping info
      CAPABILITY_QUERY         => 0x6B, # ask for supported modes and resolution of all pins
      CAPABILITY_RESPONSE      => 0x6C, # reply with supported modes and resolution
      PIN_STATE_QUERY          => 0x6D, # ask for a pin's current mode and value
      PIN_STATE_RESPONSE       => 0x6E, # reply with a pin's current mode and value
      EXTENDED_ANALOG          => 0x6F, # analog write (PWM, Servo, etc) to any pin
      SERVO_CONFIG             => 0x70, # set max angle, minPulse, maxPulse, freq
      STRING_DATA              => 0x71, # a string message with 14-bits per char
      STEPPER_DATA             => 0x72, # control a stepper motor
      ONEWIRE_DATA             => 0x73, # OneWire read/write/reset/select/skip/search request + read/search reply
      SHIFT_DATA               => 0x75, # shiftOut config/data message (34 bits)
      I2C_REQUEST              => 0x76, # send an I2C read/write request
      I2C_REPLY                => 0x77, # a reply to an I2C read request
      I2C_CONFIG               => 0x78, # config I2C settings such as delay times and power pins
      REPORT_FIRMWARE          => 0x79, # report name and version of the firmware
      SAMPLING_INTERVAL        => 0x7A, # set the poll rate of the main loop
      SCHEDULER_DATA           => 0x7B, # createtask/deletetask/addtotask/schedule/querytasks/querytask request and querytasks/querytask reply
      SYSEX_NON_REALTIME       => 0x7E, # MIDI Reserved for non-realtime messages
      SYSEX_REALTIME           => 0x7F, # MIDI Reserved for realtime messages

      # pin modes
      INPUT                    => 0x00, # digital pin in digitalOut mode
      OUTPUT                   => 0x01, # digital pin in digitalInput mode
      ANALOG                   => 0x02, # analog pin in analogInput mode
      PWM                      => 0x03, # digital pin in PWM output mode
      SERVO                    => 0x04, # digital pin in Servo output mode
      SHIFT                    => 0x05, # shiftIn/shiftOut mode
      I2C                      => 0x06, # pin included in I2C setup
      ONEWIRE                  => 0x07, # pin configured for 1-Wire commuication
      STEPPER                  => 0x08, # pin configured for stepper motor
      # Deprecated entries
      deprecated => [
        qw( FIRMATA_STRING SYSEX_I2C_REQUEST SYSEX_I2C_REPLY SYSEX_SAMPLING_INTERVAL )
      ],

    },    # /Constants for Version 2.5

    V_2_06 => {

      MAX_DATA_BYTES           => 64, # max number of data bytes in non-Sysex messages

      # message command bytes (128-255/0x80-0xFF)
      DIGITAL_MESSAGE          => 0x90, # send data for a digital pin
      ANALOG_MESSAGE           => 0xE0, # send data for an analog pin (or PWM)
      REPORT_ANALOG            => 0xC0, # enable analog input by pin #
      REPORT_DIGITAL           => 0xD0, # enable digital input by port pair
      SET_PIN_MODE             => 0xF4, # set a pin to INPUT/OUTPUT/PWM/etc
      REPORT_VERSION           => 0xF9, # report protocol version
      SYSTEM_RESET             => 0xFF, # reset from MIDI
      START_SYSEX              => 0xF0, # start a MIDI Sysex message
      END_SYSEX                => 0xF7, # end a MIDI Sysex message

      # extended command set using sysex (0-127/0x00-0x7F)
      RESERVED_COMMAND         => 0x00, # 2nd SysEx data byte is a chip-specific command (AVR, PIC, TI, etc).
      ENCODER_DATA             => 0x61, # receive rotary-encoders current positions
      ANALOG_MAPPING_QUERY     => 0x69, # ask for mapping of analog to pin numbers
      ANALOG_MAPPING_RESPONSE  => 0x6A, # reply with mapping info
      CAPABILITY_QUERY         => 0x6B, # ask for supported modes and resolution of all pins
      CAPABILITY_RESPONSE      => 0x6C, # reply with supported modes and resolution
      PIN_STATE_QUERY          => 0x6D, # ask for a pin's current mode and value
      PIN_STATE_RESPONSE       => 0x6E, # reply with a pin's current mode and value
      EXTENDED_ANALOG          => 0x6F, # analog write (PWM, Servo, etc) to any pin
      SERVO_CONFIG             => 0x70, # set max angle, minPulse, maxPulse, freq
      STRING_DATA              => 0x71, # a string message with 14-bits per char
      STEPPER_DATA             => 0x72, # control a stepper motor
      ONEWIRE_DATA             => 0x73, # OneWire read/write/reset/select/skip/search request + read/search reply
      SHIFT_DATA               => 0x75, # shiftOut config/data message (34 bits)
      I2C_REQUEST              => 0x76, # send an I2C read/write request
      I2C_REPLY                => 0x77, # a reply to an I2C read request
      I2C_CONFIG               => 0x78, # config I2C settings such as delay times and power pins
      REPORT_FIRMWARE          => 0x79, # report name and version of the firmware
      SAMPLING_INTERVAL        => 0x7A, # set the poll rate of the main loop
      SCHEDULER_DATA           => 0x7B, # createtask/deletetask/addtotask/schedule/querytasks/querytask request and querytasks/querytask reply
      SYSEX_NON_REALTIME       => 0x7E, # MIDI Reserved for non-realtime messages
      SYSEX_REALTIME           => 0x7F, # MIDI Reserved for realtime messages

      # pin modes
      INPUT                    => 0x00, # digital pin in digitalOut mode
      OUTPUT                   => 0x01, # digital pin in digitalInput mode
      ANALOG                   => 0x02, # analog pin in analogInput mode
      PWM                      => 0x03, # digital pin in PWM output mode
      SERVO                    => 0x04, # digital pin in Servo output mode
      SHIFT                    => 0x05, # shiftIn/shiftOut mode
      I2C                      => 0x06, # pin included in I2C setup
      ONEWIRE                  => 0x07, # pin configured for 1-Wire commuication
      STEPPER                  => 0x08, # pin configured for stepper motor
      ENCODER                  => 0x09, # pin configured for rotary-encoders
      

      # Deprecated entries
      deprecated => [
        qw( FIRMATA_STRING SYSEX_I2C_REQUEST SYSEX_I2C_REPLY SYSEX_SAMPLING_INTERVAL )
      ],

    },    # /Constants for Version 2.6
  }
);

# Handle the reverse lookups of the protocol
$COMMAND_LOOKUP = {};
while ( my ( $protocol_version, $protocol_commands ) = each %$COMMANDS ) {
  my $protocol_lookup = $COMMAND_LOOKUP->{$protocol_version} = {};
  my $deprecated = $protocol_lookup->{deprecated} || [];
  my $deprecated_lookup = { map { ( $_ => 1 ) } @$deprecated };
  while ( my ( $protocol_command, $command_value ) = each %$protocol_commands ) {
    next if $protocol_command eq 'deprecated';
    next if $deprecated_lookup->{$protocol_command};
    $protocol_lookup->{$command_value} = $protocol_command;
  }
}

# Now we consolidate all the string keynames into a single master list.
use constant ( $COMMAND_NAMES = { map { map { ( $_ => $_ ) } keys %$_ } values %$COMMANDS } );
use constant { COMMAND_NAMES => [ $COMMAND_NAMES = [ keys %$COMMAND_NAMES ] ] };

@EXPORT_OK = (
    @$COMMAND_NAMES, keys %$BASE,
    keys %$COMMANDS,
    qw( $COMMANDS $COMMAND_NAMES $COMMAND_LOOKUP ),
  );

%EXPORT_TAGS = ( all => \@EXPORT_OK );

1;     

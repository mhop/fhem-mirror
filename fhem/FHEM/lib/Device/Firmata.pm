package Device::Firmata;

use strict;
use warnings;

use Device::Firmata::Constants;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

=head1 NAME

Device::Firmata - Perl interface to Firmata for the arduino platform.

=head1 VERSION

Version 0.50

=cut

our $VERSION = '0.51';
our $DEBUG = 0;


=head1 SYNOPSIS

use strict;
use warnings;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
$|++;
use Time::HiRes 'sleep';

my $led_pin = 13;

my $device = Device::Firmata->open('/dev/ttyUSB0') or die "Could not connect to Firmata Server";
$device->pin_mode($led_pin=>PIN_OUTPUT);
my $iteration = 0;
while (1) {
    my $strobe_state = $iteration++%2;
    $device->digital_write($led_pin=>$strobe_state);
    sleep 0.5;
}

=head1 SUBROUTINES/METHODS

=head2 open

establish serial connection with an Arduino micro-controller.  Single argument is the name of the device file mapped to the arduino.  Typically '/dev/ttyUSB0' or 'COM9'

=cut

sub open {
# --------------------------------------------------
# Establish a connection to Arduino via the serial port
#
    my ( $self, $serial_port, $opts ) = @_;

# We're going to try and create the device connection first...
    my $package = "Device::Firmata::Platform";
    eval "require $package";
    my $device = $package->open($serial_port,$opts) or die "Could not connect to Firmata Server";

# Figure out what platform we're running on
    $device->probe;

    return $device;
}


1;

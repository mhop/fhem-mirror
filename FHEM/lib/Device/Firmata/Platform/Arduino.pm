package Device::Firmata::Platform::Arduino;

=head1 NAME

Device::Firmata::Platform::Arduino - subclass for the arduino itself

=head1 DESCRIPTION

No customization requried at this time so this is just a specification of the 
Device::Firmata::Platform class

=cut

use strict;
use Device::Firmata::Platform;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Platform';

1;

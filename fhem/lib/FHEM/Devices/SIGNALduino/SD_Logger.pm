# $Id$
# The file is part of the SIGNALduino project.
# Logging helper functions for Packages in FHEM::Devices::SD.

package FHEM::Devices::SIGNALduino::SD_Logger;

use strict;
use warnings;


sub Log {
    my ($hash, $level, $message) = @_;
    
    if (ref($hash) eq 'HASH' && defined($hash->{logMethod})) {
        $hash->{logMethod}->($hash->{NAME}, $level, $message);
    }
    # Fallback: main::Log3 
    elsif (ref($hash) eq 'HASH' && defined($hash->{NAME})) {
        main::Log3($hash->{NAME}, $level, $message);
    }
    # Fallback if $hash is a device name
    elsif (defined($hash)) {
        main::Log3($hash, $level, $message);
    }
    # generic fallback
    else {
        main::Log3 (undef, $level, $message);
    }
}

1;

=pod

=head1 NAME

FHEM::Devices::SIGNALduino::SD_Logger - Logging helper for SIGNALduino

=head1 SYNOPSIS

    use FHEM::Devices::SIGNALduino::SD_Logger;
    FHEM::Devices::SIGNALduino::SD_Logger::Log($hash, $level, $message);

=head1 DESCRIPTION

Provides a centralized logging function for SIGNALduino modules.

=head1 FUNCTIONS

=head2 Log($hash, $level, $message)

Logs a message with a specific log level.
It supports a custom C<logMethod> in C<$hash>, falls back to C<main::Log3> using the device name,
or uses C<undef> for generic logging if no device is specified.

=cut

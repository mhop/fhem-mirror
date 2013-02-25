# $Id$
##############################################################################
#
#     71_DENON_AVR.pm
#     An FHEM Perl module for controlling Denon AV-Receivers
#     via network connection. 
#
#     Copyright by Boris Pruessmann
#     e-mail: boris@pruessmann.org
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;

use Time::HiRes qw(usleep);

###################################
sub
DENON_AVR_Initialize($)
{
	my ($hash) = @_;
		
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	
# Provider
    $hash->{ReadFn}  = "DENON_AVR_Read";
    $hash->{WriteFn} = "DENON_AVR_Write";
 
# Device	
    $hash->{DefFn}      = "DENON_AVR_Define";
    $hash->{UndefFn}    = "DENON_AVR_Undefine";
    $hash->{ShutdownFn} = "DENON_AVR_Shutdown";
}

#####################################
sub
DENON_AVR_DoInit($)
{
    my $hash = shift;
    my $name = $hash->{NAME};
  
    Log 5, "DENON_AVR_DoInit: Called for $name";

    DENON_AVR_SimpleWrite("PW?"); 
    DENON_AVR_SimpleWrite("MU?");
    DENON_AVR_SimpleWrite("MV?");

    $hash->{STATE} = "Initialized";
}

###################################
sub
DENON_AVR_Read($)
{
    my ($hash) = @_;

    Log 5, "DENON_AVR_Read: Called";

    local $/ = "\r";

    my $msg = readline($hash->{TCPDev}); if ($hash->{TCPDev});
    chomp($msg);

    DENON_AVR_Parse($hash, $msg); if ($msg);
}

#####################################
sub
DENON_AVR_Write($$$)
{
    my ($hash, $fn, $msg) = @_;

    Log 5, "DENON_AVR_Write: Called";
}

###################################
sub
DENON_AVR_SimpleWrite(@)
{
	my ($hash, $msg) = @_;
    my $name = $hash->{NAME};
	
	my $name = $hash->{NAME};
    my $ll5 = GetLogLevel($name,5);
    Log $ll5, "DENON_AVR_SimpleWrite: $msg";
	
	syswrite($hash->{TCPDev}, $msg."\r") if ($hash->{TCPDev});
	
	# Let's wait 100ms - not sure if still needed
	usleep(100 * 1000);
	
	# Some linux installations are broken with 0.001, T01 returns no answer
    select(undef, undef, undef, 0.01);
}

###################################
sub
DENON_AVR_Parse(@)
{
    my ($hash, $msg) = @_;

    Log 5, "DENON_AVR_Parse: Called";

    readingsBeginUpdate($hash);

    if (msg =~ /PW(.+)/)
    {
	    $power = $1;
        if($power eq "Standby")
        {
            $power = "Off";
        }

        readingsBulkUpdate($hash, "power", lc($power));
		$hash->{STATE} = lc($power);
    }
	else
	{
	    Log 5, "DENON_AVR_Parse: Unknown message <$msg>";	
	}
  
    readingsEndUpdate($hash, 1);
}

###################################
sub
DENON_AVR_Define($$)
{
    my ($hash, $def) = @_;
    Log 5, "DENON_AVR_Define(".$def.") called.";

    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};

    if (@a != 3)
    {
        my $msg = "wrong syntax: define <name> DENON_AVR <ip-or-hostname>";
        Log 2, $msg;

        return $msg;
    }

    DevIo_CloseDev($hash);

    my $name = $a[0];
    my $host = $a[2];

    $hash->{DeviceName} = $host.":23";
	my $ret = DevIo_OpenDev($hash, 0, "DENON_AVR_DoInit");
    return $ret;
}

#############################
sub
DENON_AVR_Undefine($$)
{
	my($hash, $name) = @_;
	
    Log 5, "DENON_AVR_Undefine: Called for $name";	

	DevIo_CloseDev($hash); 
    return undef;
}

#####################################
sub
DENON_AVR_Shutdown($)
{
    my ($hash) = @_;

    Log 5, "DENON_AVR_Shutdown: Called";
}

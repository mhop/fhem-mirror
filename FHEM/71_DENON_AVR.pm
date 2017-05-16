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
my %commands = 
(
	"power:on" => "PWON",
	"power:off" => "PWSTANDBY",
	"mute:on" => "MUON",
	"mute:off" => "MUOFF"
);

###################################
sub
DENON_AVR_Initialize($)
{
	my ($hash) = @_;

    Log 5, "DENON_AVR_Initialize: Entering";
		
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
	
# Provider
    $hash->{ReadFn}  = "DENON_AVR_Read";
    $hash->{WriteFn} = "DENON_AVR_Write";
 
# Device	
    $hash->{DefFn}      = "DENON_AVR_Define";
    $hash->{UndefFn}    = "DENON_AVR_Undefine";
    $hash->{GetFn}      = "DENON_AVR_Get";
    $hash->{SetFn}      = "DENON_AVR_Set";
    $hash->{ShutdownFn} = "DENON_AVR_Shutdown";

    $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,1,2,3,4,5  ".$readingFnAttributes;
}

#####################################
sub
DENON_AVR_DoInit($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};
  
    Log 5, "DENON_AVR_DoInit: Called for $name";

    DENON_AVR_SimpleWrite($hash, "PW?"); 
    DENON_AVR_SimpleWrite($hash, "MU?");
    DENON_AVR_SimpleWrite($hash, "MV?");
    DENON_AVR_SimpleWrite($hash, "SI?");

    $hash->{STATE} = "Initialized";
    $hash->{helper}{INTERVAL} = 60 * 5;

    return undef;
}

###################################
sub
DENON_AVR_Read($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log 5, "DENON_AVR_Read: Called for $name";

    my $buf = DevIo_SimpleRead($hash);
    return "" if (!defined($buf));

    my $culdata = $hash->{PARTIAL};
    Log 5, "DENON_AVR_Read: $culdata/$buf"; 
    $culdata .= $buf;

    while($culdata =~ m/\r/) 
    {
	    my $rmsg;
	    ($rmsg, $culdata) = split("\r", $culdata, 2);
	    $rmsg =~ s/\r//;
	
	    DENON_AVR_Parse($hash, $rmsg) if($rmsg);
    }

    $hash->{PARTIAL} = $culdata;
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
	
    my $ll5 = GetLogLevel($name, 5);
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

    if ($msg =~ /PW(.+)/)
    {
	    my $power = $1;
        if($power eq "STANDBY")
        {
            $power = "Off";
        }

        readingsBulkUpdate($hash, "power", lc($power));
		$hash->{STATE} = lc($power);
    }
    elsif ($msg =~ /MU(.+)/)
    {
        readingsBulkUpdate($hash, "mute", lc($1));
    }
    elsif ($msg =~ /MVMAX (.+)/)
    {
        Log 5, "DENON_AVR_Parse: Ignoring maximum volume of <$1>";	
    }
    elsif ($msg =~ /MV(.+)/)
    {
	    my $volume = $1;
	    if (length($volume) == 2)
        {
            $volume = $volume."0";
        }

        readingsBulkUpdate($hash, "volume_level", lc($volume / 10));
    }
    elsif ($msg =~/SI(.+)/)
    {
	    my $input = $1;
	    readingsBulkUpdate($hash, "input", $input);
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
	
    InternalTimer(gettimeofday() + 5,"DENON_AVR_UpdateConfig", $hash, 0);
	
    return $ret;
}

#############################
sub
DENON_AVR_Undefine($$)
{
	my($hash, $name) = @_;
	
    Log 5, "DENON_AVR_Undefine: Called for $name";	

    RemoveInternalTimer($hash);
	DevIo_CloseDev($hash); 
	
    return undef;
}

#####################################
sub
DENON_AVR_Get($@)
{
    my ($hash, @a) = @_;
    my $what;

    return "argument is missing" if (int(@a) != 2);
    $what = $a[1];

    if ($what =~ /^(power|volume_level|mute)$/)
    {
        if(defined($hash->{READINGS}{$what}))
        {
		    return $hash->{READINGS}{$what}{VAL};
		}
		else
		{
		    return "no such reading: $what";
		}
    }
    else
    {
        return "Unknown argument $what, choose one of param power input volume_level mute get";
    }
}

###################################
sub
DENON_AVR_Set($@)
{
    my ($hash, @a) = @_;

    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on off toggle volume:slider,0,1,98 mute:on,off rawCommand statusRequest";

	if ($what =~ /^(on|off)$/)
    {
		my $command = $commands{"power:".$what};
	    DENON_AVR_SimpleWrite($hash, $command);
	}
	elsif ($what eq "toggle")
	{
		if ($hash->{STATE} eq "off")
	    {
			my $command = $commands{"power:on"};
		    DENON_AVR_SimpleWrite($hash, $command);
		}
		else
		{
			my $command = $commands{"power:off"};
		    DENON_AVR_SimpleWrite($hash, $command);			
		}
	}
    elsif ($what eq "mute")
    {
	    my $mute = $a[2];
	    if (defined($mute))
	    {
		    $mute = lc($mute);
		    if ($hash->{STATE} eq "off")
		    {
			    return "mute can only used when device is powered on";
			}
			else
			{
				my $command = $commands{$what.":".$mute};
			    DENON_AVR_SimpleWrite($hash, $command);
			}
	    }	
    }
    elsif ($what eq "volume")
    {
	    my $volume = $a[2];
	    if (defined($volume))
	    {
		    $volume = $volume * 10;
			if($hash->{STATE} eq "off")
		    {
			    return "volume can only used when device is powered on";
			}
			else
			{
				if ($volume % 10 == 0)
				{
					DENON_AVR_SimpleWrite($hash, "MV".($volume / 10));
				}
				else
				{
					DENON_AVR_SimpleWrite($hash, "MV".$volume);
				}
			}
	    }	
    }
    elsif ($what eq "rawCommand")
    {
        my $cmd = $a[2];
        DENON_AVR_SimpleWrite($hash, $cmd); 
    }
    elsif ($what eq "statusRequest")
    {
	    # Status is always up to date
	    return undef;
    }
    else
    {
        return $usage;
    }
}

#####################################
sub
DENON_AVR_Shutdown($)
{
    my ($hash) = @_;

    Log 5, "DENON_AVR_Shutdown: Called";
}

#####################################
sub 
DENON_AVR_UpdateConfig($)
{
    # this routine is called 5 sec after the last define of a restart
    # this gives FHEM sufficient time to fill in attributes
    # it will also be called after each manual definition
    # Purpose is to parse attributes and read config
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $webCmd  = AttrVal($name, "webCmd", "");
    if (!$webCmd)
    {
	    $attr{$name}{webCmd} = "toggle:on:off:statusRequest";
	}
	
	InternalTimer(gettimeofday() + $hash->{helper}{INTERVAL}, "DENON_AVR_KeepAlive", $hash, 0);
}

#####################################
sub 
DENON_AVR_KeepAlive($)
{
    my ($hash) = @_;

    DENON_AVR_SimpleWrite($hash, "PW?"); 

	InternalTimer(gettimeofday() + $hash->{helper}{INTERVAL}, "DENON_AVR_KeepAlive", $hash, 0);
}

1;

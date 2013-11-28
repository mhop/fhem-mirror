# $Id$
##############################################################################
#
#     71_YAMAHA_AVR.pm
#     An FHEM Perl module for controlling Yamaha AV-Receivers
#     via network connection. As the interface is standardized
#     within all Yamaha AV-Receivers, this module should work
#     with any receiver which has an ethernet or wlan connection.
#
#     Currently supported are:  power (on|off)
#                               input (hdmi1|hdmi2|...)
#                               volume (-50 ... 10)
#                               mute (on|off)
#
#     Of course there are more possibilities than these 4 commands.
#     But in my oppinion these are the most relevant usecases within fhem.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
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
use Time::HiRes qw(gettimeofday sleep);
use HttpUtils;

sub YAMAHA_AVR_Get($@);
sub YAMAHA_AVR_Define($$);
sub YAMAHA_AVR_GetStatus($;$);
sub YAMAHA_AVR_Undefine($$);




###################################
sub
YAMAHA_AVR_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "YAMAHA_AVR_Get";
  $hash->{SetFn}     = "YAMAHA_AVR_Set";
  $hash->{DefFn}     = "YAMAHA_AVR_Define";
  $hash->{UndefFn}   = "YAMAHA_AVR_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,1,2,3,4,5 volume-smooth-change:0,1 volume-smooth-time:0,1,2,3,4,5 volume-smooth-steps:1,2,3,4,5,6,7,8,9,10 event-on-update-reading event-on-change-reading";
}

###################################
sub
YAMAHA_AVR_GetStatus($;$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $power;
    
    $local = 0 unless(defined($local));

    return "" if(!defined($hash->{helper}{ADDRESS}) or !defined($hash->{helper}{INTERVAL}));

    my $device = $hash->{helper}{ADDRESS};

    if(not defined($hash->{ACTIVE_ZONE}) or not defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
	YAMAHA_AVR_getModel($hash, $device);
    }

    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
	YAMAHA_AVR_getInputs($hash, $device);
    }
    
    my $zone = YAMAHA_AVR_getZoneName($hash, $hash->{ACTIVE_ZONE});
    
    if(not defined($zone))
    {
	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "YAMAHA_AVR_GetStatus", $hash, 1) unless($local == 1);
	return "No Zone available";
    }
    
    my $return = YAMAHA_AVR_SendCommand($hash, $device,"<YAMAHA_AV cmd=\"GET\"><$zone><Basic_Status>GetParam</Basic_Status></$zone></YAMAHA_AV>");
    
    Log GetLogLevel($name, 4), "YANMAHA_AVR: GetStatus-Request returned:\n$return" if(defined($return));
    
    if(not defined($return) or $return eq "")
    {
	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "YAMAHA_AVR_GetStatus", $hash, 1) unless($local == 1);
	return;
    }
    
    readingsBeginUpdate($hash);
    
    if($return =~ /<Power>(.+)<\/Power>/)
    {
       $power = $1;
       readingsBulkUpdate($hash, "power", lc($power));
       if($power eq "Standby")
       {
	    $power = "Off";
       }
       
       $hash->{STATE} = lc($power);
       
    }
    
    if($return =~ /<Volume><Lvl><Val>(.+)<\/Val><Exp>(.+)<\/Exp><Unit>.+<\/Unit><\/Lvl><Mute>(.+)<\/Mute>.*<\/Volume>/)
    {
	readingsBulkUpdate($hash, "volume_level", ($1 / 10 ** $2));
	readingsBulkUpdate($hash, "mute", lc($3));
    }
    
    if($return =~ /<Volume>.*?<Output>(.+?)<\/Output>.*?<\/Volume>/)
    {
	readingsBulkUpdate($hash, "output", lc($1));
    }
    else
    {
       delete($hash->{READINGS}{output}) if(defined($hash->{READINGS}{output}));
    
    }
    
    if($return =~ /<Input_Sel>(.+)<\/Input_Sel>/)
    {
	readingsBulkUpdate($hash, "input", YAMAHA_AVR_InputParam2Fhem(lc($1), 0));
    }
    
    if($return =~ /<Input>.*?<Title>\s*?(\S+?)\s*?<\/Title>.*<\/Input>/)
    {
	readingsBulkUpdate($hash, "input_name", $1);
    }
    
    readingsEndUpdate($hash, 1);
    
    InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "YAMAHA_AVR_GetStatus", $hash, 1) unless($local == 1);
    
    Log GetLogLevel($name,4), "YAMAHA_AVR $name: $hash->{STATE}";
    
    return $hash->{STATE};
}

###################################
sub
YAMAHA_AVR_Get($@)
{
    my ($hash, @a) = @_;
    my $what;

    return "argument is missing" if(int(@a) != 2);
    
    $what = $a[1];
    
    if($what =~ /^(power|input|volume_level|mute)$/)
    {
        YAMAHA_AVR_GetStatus($hash, 1);

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
YAMAHA_AVR_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    my $result = "";
    my $command;
    my $zone = YAMAHA_AVR_getZoneName($hash, $hash->{ACTIVE_ZONE});
    
    my $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_InputParam2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
    my $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_InputParam2Fhem(lc($hash->{helper}{INPUTS}), 1) : "" ;
   
    return "No Argument given" if(!defined($a[1]));     
 
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on off volume:slider,-80,1,16 input:".$inputs_comma." mute:on,off statusRequest";

    readingsBeginUpdate($hash);

    if($what eq "on")
    {
	$result = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Power>On</Power></Power_Control></$zone></YAMAHA_AV>");

	if($result =~ /RC="0"/ and $result =~ /<Power><\/Power>/)
	{
	    # As the receiver startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
	    readingsBulkUpdate($hash, "power", "on");
	    $hash->{STATE} = "on";
	    return undef;
	}
	else
	{
	    return "Could not set power to on";
	}

    }
    elsif($what eq "off")
    {
	$result = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"PUT\"><$zone><Power_Control><Power>Standby</Power></Power_Control></$zone></YAMAHA_AV>");
	
	if(not $result =~ /RC="0"/)
	{
		# if the returncode isn't 0, than the command was not successful
		return "Could not set power to off";
	}

    }
    elsif($what eq "input")
    {
	if(defined($a[2]))
	{
	    if($hash->{STATE} eq "on")
	    {
		$inputs_piped =~ s/,/|/g;
	    if(not $inputs_piped eq "")
	    {
		if($a[2] =~ /^($inputs_piped)$/)
		{
		    $command = YAMAHA_AVR_getCommandParam($hash, $a[2]);
		    if(defined($command) and length($command) > 0)
		    {
			$result = YAMAHA_AVR_SendCommand($hash, $address,"<YAMAHA_AV cmd=\"PUT\"><$zone><Input><Input_Sel>".$command."</Input_Sel></Input></$zone></YAMAHA_AV>");
		    }
		    else
		    {
			return "invalid input: ".$a[2];
		    }

		    if(not $result =~ /RC="0"/)
		    {
			# if the returncode isn't 0, than the command was not successful
			return "Could not set input to ".$a[2].".";
		    }
		}
		else
		{
		    return $usage;
		}
	      }
	      else
	      {
	        return "No inputs are avaible. Please try an statusUpdate.";
	      }
	     
	    }
	    else
	    {
		return "input can only be used when device is powered on";
	    }
	}
	else
	{
	    return $inputs_piped eq "" ? "No inputs are available. Please try an statusUpdate." : "No input parameter was given";
	}

    }
    elsif($what eq "mute")
    {
	if(defined($a[2]))
	{
	    if($hash->{STATE} eq "on")
	    {
		if( $a[2] eq "on")
		{
		    $result = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"PUT\"><$zone><Volume><Mute>On</Mute></Volume></$zone></YAMAHA_AV>");
		}
		elsif($a[2] eq "off")
		{
		    $result = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"PUT\"><$zone><Volume><Mute>Off</Mute></Volume></$zone></YAMAHA_AV>"); 
		}
		else
		{
		    return $usage;
		}
		
		if(not $result =~ /RC="0"/)
		{
			# if the returncode isn't 0, than the command was not successful
			return "Could not set mute to ".$a[2].".";
		}    
	    }
	    else
	    {
		return "mute can only used when device is powered on";
	    }
	}
    }
    elsif($what eq "volume")
    {
	if(defined($a[2]) && $a[2] >= -80 && $a[2] < 16)
	{
	    if($hash->{STATE} eq "on")
	    {
		if(AttrVal($name, "volume-smooth-change", "0") eq "1")
		{
		    my $diff = int(($a[2] - $hash->{READINGS}{volume_level}{VAL}) / AttrVal($hash->{NAME}, "volume-smooth-steps", 5) / 0.5) * 0.5;
		    my $steps = AttrVal($name, "volume-smooth-steps", 5);
		    my $current_volume = $hash->{READINGS}{volume_level}{VAL};
		    my $time = AttrVal($name, "volume-smooth-time", 0);
		    my $sleep = $time / $steps;

		    if($diff > 0)
		    {
		        Log GetLogLevel($name, 4), "YAMAHA_AVR: use smooth volume change (with $steps steps of +$diff volume change each ".sprintf("%.3f", $sleep)." seconds)";
		    }
		    else
		    {
			Log GetLogLevel($name, 4), "YAMAHA_AVR: use smooth volume change (with $steps steps of $diff volume change each ".sprintf("%.3f", $sleep)." seconds)";
		    }
	
		    # Only if a volume reading exists and smoohing is really needed (step difference is not zero)
		    if(defined($hash->{READINGS}{volume_level}{VAL}) and $diff != 0)
		    {
			for(my $step = 1; $step <= $steps; $step++)
			{
			    Log GetLogLevel($name, 4), "YAMAHA_AVR: set volume to ".($current_volume + ($diff * $step))." dB";
			
			    YAMAHA_AVR_SendCommand($hash, $address,"<YAMAHA_AV cmd=\"PUT\"><$zone><Volume><Lvl><Val>".(($current_volume + ($diff * $step))*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></$zone></YAMAHA_AV>");
			
			    sleep $sleep unless ($time == 0);
			}
		    }
		}
		
		# Set the desired volume
		Log GetLogLevel($name, 4), "YAMAHA_AVR: set volume to ".$a[2]." dB";
		$result = YAMAHA_AVR_SendCommand($hash, $address,"<YAMAHA_AV cmd=\"PUT\"><$zone><Volume><Lvl><Val>".($a[2]*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></$zone></YAMAHA_AV>");
		if(not $result =~ /RC="0"/)
		{
			# if the returncode isn't 0, than the command was not successful
			return "Could not set volume to ".$a[2].".";
		}    
	    
	    }
	    else
	    {
		return "volume can only be used when device is powered on";
	    }
	}
    }
    elsif($what eq "statusRequest")
    {
	# Will be executed on the end of this function anyway, so no need to call it specificly
    }
    else
    {
	return $usage;
    }
    readingsEndUpdate($hash, 1);
    
    # Call the GetStatus() Function to retrieve the new values after setting something (with local flag, so the internal timer is not getting interupted)
    YAMAHA_AVR_GetStatus($hash, 1);
    
    return undef;
    
}


#############################
sub
YAMAHA_AVR_Define($$)
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(! @a >= 4)
    {
	my $msg = "wrong syntax: define <name> YAMAHA_AVR <ip-or-hostname> [<zone>] [<statusinterval>]";
	Log 2, $msg;
	return $msg;
    }


    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;
    
    
    
    if(defined($a[3]))
    {
        $hash->{helper}{SELECTED_ZONE} = $a[3];
    }
    else
    {
	$hash->{helper}{SELECTED_ZONE} = "mainzone";
    }
    
    
    if(defined($a[4]) and $a[4] > 0)
    {
	$hash->{helper}{INTERVAL}=$a[4];
    }
    else
    {
	$hash->{helper}{INTERVAL}=30;
    }
    
    
    # In case of a redefine, check the zone parameter if the specified zone exist, otherwise use the main zone
    if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
    {
	if(defined(YAMAHA_AVR_getZoneName($hash, lc $hash->{helper}{SELECTED_ZONE})))
	{
    
	    $hash->{ACTIVE_ZONE} = lc $hash->{helper}{SELECTED_ZONE};
	    YAMAHA_AVR_getInputs($hash, $address);
	    
	}
	else
	{
	    Log GetLogLevel($name, 2), "YAMAHA_AVR: selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available on device ".$hash->{NAME}.". Using Main Zone instead";
	    $hash->{ACTIVE_ZONE} = "mainzone";
	    YAMAHA_AVR_getInputs($hash, $address);
	}
    }
    
    # set the volume-smooth-change attribute only if it is not defined, so no user values will be overwritten
    $attr{$name}{"volume-smooth-change"} = "1" unless(defined($attr{$name}{"volume-smooth-change"}));
    
    InternalTimer(gettimeofday()+2, "YAMAHA_AVR_GetStatus", $hash, 0);
  
  return undef;
}

#############################
sub
YAMAHA_AVR_SendCommand($$$)
{
   my($hash, $address, $command) = @_;
   my $name = $hash->{NAME};
   my $response;
   
     
   Log GetLogLevel($name, 5), "YAMAHA_AVR: execute on $name: $command";
    
   # In case any URL changes must be made, this part is separated in this function".
   $response = GetFileFromURL("http://".$address."/YamahaRemoteControl/ctrl", 10, "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$command);
   Log GetLogLevel($name, 3), "YAMAHA_AVR: could not execute command on device $name" unless (defined($response));
    
   return $response;

}

#############################
sub
YAMAHA_AVR_Undefine($$)
{
  my($hash, $name) = @_;
  
  # Stop the internal GetStatus-Loop and exist
  RemoveInternalTimer($hash);
  return undef;
}


#############################
# Converts all Inputs to FHEM usable command lists
sub YAMAHA_AVR_InputParam2Fhem($$)
{
    my ($inputs, $replace_pipes) = @_;

   
    $inputs =~ s/\s+//g;
    $inputs =~ s/,//g;
    $inputs =~ s/\(/_/g;
    $inputs =~ s/\)//g;
    $inputs =~ s/\|/,/g if($replace_pipes == 1);

    return $inputs;
}

#############################
# Converts all Zones to FHEM usable command lists
sub YAMAHA_AVR_Zone2Fhem($$)
{
    my ($zones, $replace_pipes) = @_;

   
    $zones =~ s/\s+//g;
    $zones =~ s/_//g;
    $zones =~ s/\|/,/g if($replace_pipes == 1);

    return lc $zones;

}

#############################
# Returns the Yamaha Zone Name for the FHEM like zone attribute
sub YAMAHA_AVR_getZoneName($$)
{
   my ($hash, $zone) = @_;
   my $item;
   
   return undef if(not defined($hash->{helper}{ZONES}));
   
   my @commands = split("\\|", $hash->{helper}{ZONES});

    foreach $item (@commands)
    {
	if(YAMAHA_AVR_Zone2Fhem($item, 0) eq $zone)
	{
	    return $item;
	}
    
    }
    
    return undef;
    
}

#############################
# Returns the Yamaha Parameter Name for the FHEM like input channel
sub YAMAHA_AVR_getCommandParam($$)
{
   my ($hash, $command) = @_;
   my $item;
   my @commands = split("\\|", $hash->{helper}{INPUTS});

    foreach $item (@commands)
    {
	if(lc(YAMAHA_AVR_InputParam2Fhem($item, 0)) eq $command)
	{
	    return $item;
	}
    
    }
    
    return undef;
    
}


sub YAMAHA_AVR_getModel($$)
{
    my ($hash, $address) = @_;
    my $name = $hash->{NAME};
    my $response;
    my $desc_url;
    
    $response = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"GET\"><System><Unit_Desc>GetParam</Unit_Desc></System></YAMAHA_AV>");

    Log GetLogLevel($name, 3), "YAMAHA_AVR: could not get unit description url from device $name" unless (defined($response));
    
    
    if(defined($response) and $response =~ /<URL>(.+?)<\/URL>/)
    { 
       $desc_url = $1;
    }
    else
    {
       $desc_url = "/YamahaRemoteControl/desc.xml";
    }
    
    $response = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>");
    
    Log GetLogLevel($name, 3), "YAMAHA_AVR: could not get system configuration from device $name" unless (defined($response));
    
    if(defined($response) and $response =~ /<Model_Name>(.+?)<\/Model_Name>.*<System_ID>(.+?)<\/System_ID>.*<Version>(.+?)<\/Version>/)
    {
        $hash->{MODEL} = $1;
        $hash->{SYSTEM_ID} = $2;
        $hash->{FIRMWARE} = $3;
    }
    else
    {
	return undef;
    }
    
    $response = GetFileFromURL("http://".$address.$desc_url);
    
    Log GetLogLevel($name, 3), "YAMAHA_AVR: could not get unit description from device $name" unless (defined($response));
    
    return undef unless(defined($response));

    while($response =~ /<Menu Func="Subunit" Title_1="(.+?)" YNC_Tag="(.+?)">/gc)
    {
        if(defined($hash->{helper}{ZONES}) and length($hash->{helper}{ZONES}) > 0)
        {
            $hash->{helper}{ZONES} .= "|";
        }

        $hash->{helper}{ZONES} .= $2;

    }
    
    # uncommented line for zone detection testing
    #
    # $hash->{helper}{ZONES} .= "|Zone_2";
    
    $hash->{ZONES_AVAILABLE} = YAMAHA_AVR_Zone2Fhem($hash->{helper}{ZONES}, 1);
    
    
    if(defined(YAMAHA_AVR_getZoneName($hash, lc $hash->{helper}{SELECTED_ZONE})))
    {
    
	Log GetLogLevel($name, 4), "YAMAHA_AVR: using zone ".YAMAHA_AVR_getZoneName($hash, lc $hash->{helper}{SELECTED_ZONE});
	$hash->{ACTIVE_ZONE} = lc $hash->{helper}{SELECTED_ZONE};
    
    }
    else
    {
	Log GetLogLevel($name, 2), "YAMAHA_AVR: selected zone >>".$hash->{helper}{SELECTED_ZONE}."<< is not available on device $name. Using Main Zone instead";
	$hash->{ACTIVE_ZONE} = "mainzone";
    }
    return 0;
}

sub YAMAHA_AVR_getInputs($$)
{

    my ($hash, $address) = @_;  
    my $name = $hash->{NAME};
    my $zone = YAMAHA_AVR_getZoneName($hash, $hash->{ACTIVE_ZONE});
    
    return undef if (not defined($zone) or $zone eq "");
    
    my $response = YAMAHA_AVR_SendCommand($hash, $address, "<YAMAHA_AV cmd=\"GET\"><$zone><Input><Input_Sel_Item>GetParam</Input_Sel_Item></Input></$zone></YAMAHA_AV>");
    
    
    Log GetLogLevel($name, 3), "YAMAHA_AVR: could not get the available inputs from device $name" unless (defined($response));
    
    return undef unless (defined($response));

    
    delete($hash->{helper}{INPUTS}) if(defined($hash->{helper}{INPUTS}));

    
    
	while($response =~ /<Param>(.+?)<\/Param>/gc)
	{
	    if(defined($hash->{helper}{INPUTS}) and length($hash->{helper}{INPUTS}) > 0)
	    {
	      $hash->{helper}{INPUTS} .= "|";
	    }
	  
	      $hash->{helper}{INPUTS} .= $1;
	    
	}
	
	$hash->{helper}{INPUTS} = join("|", sort split("\\|", $hash->{helper}{INPUTS}));
	
    

}



1;

=pod
=begin html

<a name="YAMAHA_AVR"></a>
<h3>YAMAHA_AVR</h3>
<ul>

  <a name="YAMAHA_AVRdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; YAMAHA_AVR &lt;ip-address&gt; [&lt;zone&gt;] [&lt;status_interval&gt;]</code>
    <br><br>

    This module controls AV receiver from Yamaha via network connection. You are able
    to power your AV reveiver on and off, query it's power state,
    select the input (HDMI, AV, AirPlay, internet radio, Tuner, ...), select the volume
    or mute/unmute the volume.<br><br>
    Defining a YAMAHA_AVR device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30
    seconds), which periodically reads the status of the AV receiver (power state, selected
    input, volume and mute status) and triggers notify/filelog commands.<br><br>

    Example:
    <PRE>
       define AV_Receiver YAMAHA_AVR 192.168.0.10
       
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60   # With custom interval of 60 seconds
    </PRE>
  </ul>
  <b>Zone Selection</b><br>
  <ul>
    If your receiver supports zone selection (e.g. RX-V671, RX-V673,... and the AVANTAGE series) 
    you can select the zone which should be controlled. The RX-V3xx and RX-V4xx series for example 
    just have a "Main Zone" (which is the whole receiver itself). In general you have the following
    possibilities for the parameter &lt;zone&gt; (depending on your receiver model).<br><br>
    <ul>
    <li><b>mainzone</b> - this is the main zone (standard)</li>
    <li><b>zone2</b> - The second zone (Zone 2)</li>
    <li><b>zone3</b> - The third zone (Zone 3)</li>
    <li><b>zone4</b> - The fourth zone (Zone 4)</li>
    </ul>
    <br>
    Depending on your receiver model you have not all inputs available on these different zones.
    The module just offers the real available inputs.
    <br><br>
    Example:
    
     <PRE>
        define AV_Receiver YAMAHA_AVR 192.168.0.10           # If no zone is specified, the "Main Zone" will be used.
        attr AV_Receiver YAMAHA_AVR room Livingroom
        
        # Define the second zone
        define AV_Receiver_Zone2 YAMAHA_AVR 192.168.0.10 zone2
        attr AV_Receiver_Zone2 room Bedroom
     </PRE>
     For each Zone you will need an own YAMAHA_AVR device, which can be assigned to a different room.
     Each zone can be controlled separatly from all other available zones.
     <br><br>
  </ul>
  
  <a name="YAMAHA_AVRset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined; the available inputs are depending on the used receiver.
    The module only offers the real available inputs. The following input commands are just an example and can differ.

<pre>on
off
input hdmi1
input hdmi2
input hdmi3
input hdmi4
input av1
input av2
input av3
input av3
input av4
input av5
input av6
input usb
input airplay
input tuner
input v-aux
input audio
input server
volume -80..16	(volume between -80 and +16 dB)
mute on
mute off</pre>
  </ul>

  <a name="YAMAHA_AVRget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br><br>
    Currently, the following commands are defined and return the current state of the receiver.
<pre>power
input 
mute 
volume_level</pre>
  </ul>
  <a name="YAMAHA_AVRattr"></a>
  <b>Attributes</b>
  <ul>
  
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li><br>
    <li><a name="volume-smooth-change">volume-smooth-change</a></li>
	Optional attribute to activate a smooth volume change.
	<br><br>
	Possible values: 0 => off , 1 => on<br><br>
    <li><a name="volume-smooth-steps">volume-smooth-steps</a></li>
	Optional attribute to define the number of volume changes between the
        current and the desired volume. Default value is 5 steps<br><br>
    <li><a name="volume-smooth-time">volume-smooth-time</a></li>
       Optional attribute to define the time window for the volume smoothing in seconds.
       For example the value 2 means the smooth process in general should take 2 seconds.
       The value 0 means "as fast as possible". Default value is 0.
  </ul>
<br>
  <b>Implementator's note</b>
  <ul>
    The module is only usable if you activate "Network Standby" on your receiver.<br><br>
    Technically there are many more commands and readings possible, but I think
    these are the main usecases within FHEM.
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a name="YAMAHA_AVR"></a>
<h3>YAMAHA_AVR</h3>
<ul>

  <a name="YAMAHA_AVRdefine"></a>
  <b>Definition</b>
  <ul>
    <code>define &lt;name&gt; YAMAHA_AVR &lt;IP-Addresse&gt; [&lt;Zone&gt;] [&lt;Status_Interval&gt;]</code>
    <br><br>

    Dieses Modul steuert AV-Receiver des Herstellers Yamaha &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit den Receiver an-/auszuschalten, den Eingangskanal zu w&auml;hlen,
    die Lautst&auml;rke zu &auml;ndern, den Receiver "Stumm" zu schalten, sowie den aktuellen Status abzufragen.
    <br><br>
    Bei der Definition eines YAMAHA_AVR-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter &lt;Status_Interval&gt;; falls nicht gesetzt ist der Standardwert 30 Sekunden)
    den Status des Receivers abfragt und entsprechende Notify-/FileLog-Ger&auml;te triggert..<br><br>

    Beispiel:
    <PRE>
       define AV_Receiver YAMAHA_AVR 192.168.0.10
       
       define AV_Receiver YAMAHA_AVR 192.168.0.10 mainzone 60   # Mit modifiziertem Status Interval (60 Sekunden)
    </PRE>
  </ul>
  <b>Zonenauswahl</b><br>
  <ul>
    Wenn der zu steuernde Receiver mehrere Zonen besitzt (z.B. RX-V671, RX-V673,... sowie die AVANTAGE Modellreihe) 
    kann die zu steuernde Zone explizit angegeben werden. Die Modellreihen RX-V3xx und RX-V4xx als Beispiel
    haben nur eine Zone (Main Zone). Je nach Receiver-Modell stehen folgende Zonen zur Verf&uuml;gung, welche mit
    dem optionalen Parameter &lt;Zone&gt; angegeben werden k&ouml;nnen.<br><br>
    <ul>
    <li><b>mainzone</b> - Das ist die Hauptzone (Standard)</li>
    <li><b>zone2</b> - Die zweite Zone (Zone 2)</li>
    <li><b>zone3</b> - Die dritte Zone (Zone 3)</li>
    <li><b>zone4</b> - Die vierte Zone (Zone 4)</li>
    </ul>
    <br>
    Je nach Receiver-Modell stehen in den verschiedenen Zonen nicht immer alle Eing&auml;nge zur Verf&uuml;gung. 
    Dieses Modul bietet nur die tats&auml;chlich verf&uuml;gbaren Eing&auml;nge an.
    <br><br>
    Beispiel:
    
     <PRE>
        define AV_Receiver YAMAHA_AVR 192.168.0.10           # Wenn keine Zone angegeben ist, wird 
        attr AV_Receiver YAMAHA_AVR room Wohnzimmer          # standardm&auml;&szlig;ig "mainzone" verwendet
        
        # Definition der zweiten Zone
        define AV_Receiver_Zone2 YAMAHA_AVR 192.168.0.10 zone2
        attr AV_Receiver_Zone2 room Schlafzimmer
     </PRE>
     F&uuml;r jede Zone muss eine eigene YAMAHA_AVR Definition erzeugt werden, welche dann unterschiedlichen R&auml;umen zugeordnet werden kann.
     Jede Zone kann unabh&auml;ngig von allen anderen Zonen (inkl. der Main Zone) gesteuert werden.
     <br><br>
  </ul>
  
  <a name="YAMAHA_AVRset"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <br><br>
    Aktuell werden folgende Kommandos unterst&uuml;tzt. Die verf&uuml;gbaren Eing&auml;nge k&ouml;nnen je nach Receiver-Modell variieren.
    Die folgenden Eing&auml;nge stehen beispielhaft an einem RX-V473 Receiver zur Verf&uuml;gung.
    Aktuell stehen folgende Kommandos zur Verf&uuml;gung.

<pre>on
off
input hdmi1
input hdmi2
input hdmi3
input hdmi4
input av1
input av2
input av3
input av3
input av4
input av5
input av6
input usb
input airplay
input tuner
input v-aux
input audio
input server
volume -80..16	(Lautst&auml;rke zwischen -80 und +16 dB)
mute on
mute off</pre>
  </ul>

  <a name="YAMAHA_AVRget"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Parameter&gt;</code>
    <br><br>
    Aktuell stehen folgende Parameter zur Verf&uuml;gung welche den aktuellen Status des Receivers zur&uuml;ck geben.<br><br>
     <ul>
     <li><code>power</code> - Betriebszustand des Receiveres/Zone (on oder off)</li>
     <li><code>input</code> - Gew&auml;hlter Eingang</li>
     <li><code>mute</code> - Lautlos an oder aus (on oder off)</li>
     <li><code>volume_level</code> - Lautst&auml;rkepegel in dB</li>
     </ul>
  </ul>
  <br>
  <a name="YAMAHA_AVRattr"></a>
  <b>Attribute</b>
  <ul>
  
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li><br>
    <li><a name="volume-smooth-change">volume-smooth-change</a></li>
	Optionales Attribut, welches einen weichen Lautst&auml;rke&uuml;bergang aktiviert..
	<br><br>
	M&ouml;gliche Werte: 0 => deaktiviert , 1 => aktiviert<br><br>
    <li><a name="volume-smooth-steps">volume-smooth-steps</a></li>
	Optionales Attribut, welches angibt, wieviele Schritte zur weichen Lautst&auml;rkeanpassung
	 durchgef&uuml;hrt werden sollen. Standartwert ist 5 Anpassungschritte<br><br>
    <li><a name="volume-smooth-time">volume-smooth-time</a></li>
	Optionales Attrribut welches das Zeitfenster in Sekunden f&uuml;r die Anpassung angibt.
       Als Beispiel bedeutet der Wert 2 dass innerhalb von 2 Sekunden die Lautst&auml;rkeanpassung durchgef&uuml;hrt werden soll.
       Der Wert 0 bedeutet, dass die Anpassung so schnell wie m&ouml;glich geschehen soll. Der Standardwert ist 0.
  </ul>
<br>
  <b>Hinweise des Autors</b>
  <ul>
    Dieses Modul ist nur nutzbar, wenn die Option "Network Standby" am Receiver aktiviert ist.<br><br>
    Technisch gesehen sind viel mehr Kommandos und R&uuml;ckgabewerte m&ouml;glich, aber dies sind meiner
    Meinung nach die wichtigsten innerhalb von FHEM.
  </ul>
  <br>
</ul>
=end html_DE

=cut

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

require "$attr{global}{modpath}/FHEM/HttpUtils.pm";

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

  $hash->{AttrList}  = "loglevel:0,1,2,3,4,5 volume-smooth-change:0,1 volume-smooth-time:0,1,2,3,4,5 volume-smooth-steps:1,2,3,4,5,6,7,8,9,10 event-on-update-reading event-on-change-reading";
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



    if(not defined($hash->{MODEL}))
    {
	YAMAHA_AVR_getModel($hash, $device);
    }

    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
	YAMAHA_AVR_getInputs($hash, $device);
    }
    
    
    
    my $return = YAMAHA_AVR_SendCommand($device,"<YAMAHA_AV cmd=\"GET\"><Main_Zone><Basic_Status>GetParam</Basic_Status></Main_Zone></YAMAHA_AV>");

    Log GetLogLevel($name, 4), "YANMAHA_AVR: GetStatus-Request returned:\n$return";
    
    if($return eq "")
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
    
    
    if($return =~ /<Volume><Lvl><Val>(.+)<\/Val><Exp>(.+)<\/Exp><Unit>.+<\/Unit><\/Lvl><Mute>(.+)<\/Mute><\/Volume>/)
    {
	readingsBulkUpdate($hash, "volume_level", ($1 / 10 ** $2));
	readingsBulkUpdate($hash, "mute", lc($3));
    }
    
    
    if($return =~ /<Input_Sel>(.+)<\/Input_Sel>/)
    {
	readingsBulkUpdate($hash, "input", YAMAHA_AVR_InputParam2Fhem(lc($1), 0));
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
    
    
    my $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_InputParam2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
    my $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_AVR_InputParam2Fhem(lc($hash->{helper}{INPUTS}), 1) : "" ;
   
    return "No Argument given" if(!defined($a[1]));     
 
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on off volume:slider,-80,1,16 input:".$inputs_comma." mute:on,off statusRequest";

    readingsBeginUpdate($hash);

    if($what eq "on")
    {
	$result = YAMAHA_AVR_SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>On</Power></Power_Control></Main_Zone></YAMAHA_AV>");

	if($result =~ /RC="0"/ and $result =~ /<Power><\/Power>/)
	{
	    # As the receiver startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
	    readingsBulkUpdate($hash, "power", "on");
	    $hash->{STATE} = "on";
	    return undef;
	}   

    }
    elsif($what eq "off")
    {
	YAMAHA_AVR_SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>Standby</Power></Power_Control></Main_Zone></YAMAHA_AV>");
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
			$result = YAMAHA_AVR_SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Input><Input_Sel>".$command."</Input_Sel></Input></Main_Zone></YAMAHA_AV>");
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
		    YAMAHA_AVR_SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Mute>On</Mute></Volume></Main_Zone></YAMAHA_AV>");
		}
		elsif($a[2] eq "off")
		{
		    YAMAHA_AVR_SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Mute>Off</Mute></Volume></Main_Zone></YAMAHA_AV>"); 
		}
		else
		{
		    return $usage;
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
		        Log GetLogLevel($name, 4), "YAMAHA_AV: use smooth volume change (with $steps steps of +$diff volume change each ".sprintf("%.3f", $sleep)." seconds)";
		    }
		    else
		    {
			Log GetLogLevel($name, 4), "YAMAHA_AV: use smooth volume change (with $steps steps of $diff volume change each ".sprintf("%.3f", $sleep)." seconds)";
		    }
	
		    # Only if smoohing is really needed (step difference is not zero)
		    if($diff != 0)
		    {
			for(my $step = 1; $step <= $steps; $step++)
			{
			    Log GetLogLevel($name, 4), "YAMAHA_AV: set volume to ".($current_volume + ($diff * $step))." dB";
			
			    YAMAHA_AVR_SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Lvl><Val>".(($current_volume + ($diff * $step))*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></Main_Zone></YAMAHA_AV>");
			
			    sleep $sleep unless ($time == 0);
			}
		    }
		}
		
		Log GetLogLevel($name, 4), "YAMAHA_AV set volume to ".$a[2]." dB";
		YAMAHA_AVR_SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Lvl><Val>".($a[2]*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></Main_Zone></YAMAHA_AV>");
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
    
    if(! @a >= 3)
    {
	my $msg = "wrong syntax: define <name> YAMAHA_AVR <ip-or-hostname> [<statusinterval>]";
	Log 2, $msg;
	return $msg;
    }


    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;
    
    
    if(defined($a[3]) and $a[3] > 0)
    {
	$hash->{helper}{INTERVAL}=$a[3];
    }
    else
    {
	$hash->{helper}{INTERVAL}=30;
    }
    $attr{$name}{"volume-smooth-change"} = "1";
    
    InternalTimer(gettimeofday()+2, "YAMAHA_AVR_GetStatus", $hash, 0);
  
  return undef;
}

#############################
sub
YAMAHA_AVR_SendCommand($$)
{
   my($address, $command) = @_;
   
   # In case any URL changes must be made, this part is separated in this function".
   return GetFileFromURL("http://".$address."/YamahaRemoteControl/ctrl", 10, "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$command);
}

#############################
sub
YAMAHA_AVR_Undefine($$)
{
  my($hash, $name) = @_;
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
    $inputs =~ s/\(.+?\)//g;
    $inputs =~ s/\|/,/g if($replace_pipes == 1);

    return $inputs;
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
    my $response = GetFileFromURL("http://".$address."/YamahaRemoteControl/desc.xml");
    return undef unless(defined($response));
    if($response =~ /<Unit_Description\s+Version="(.+?)"\s+Unit_Name="(.+?)">/)
    {
	$hash->{FIRMWARE} = $1;
        $hash->{MODEL} = $2;
    }
}

sub YAMAHA_AVR_getInputs($$)
{

    my ($hash, $address) = @_;  
    my $response = YAMAHA_AVR_SendCommand($address, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Input><Input_Sel_Item>GetParam</Input_Sel_Item></Input></Main_Zone></YAMAHA_AV>");
    return undef unless (defined($response));
    $response =~ s/></>\n</g;
    my @inputs = split("\n", $response);
    
    foreach (sort @inputs)
    {
	if($_ =~ /<Param>(.+?)<\/Param>/)
	{
	    if(defined($hash->{helper}{INPUTS}) and length($hash->{helper}{INPUTS}) > 0)
	    {
	      $hash->{helper}{INPUTS} .= "|";
	    }
	  
	      $hash->{helper}{INPUTS} .= $1;
	    
	}
    }

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
    <code>define &lt;name&gt; YAMAHA_AVR &lt;ip-address&gt; [&lt;status_interval&gt;]</code>
    <br><br>

    This module controls AV receiver from Yamaha via network connection. You are able
    to power your AV reveiver on and off, query it's power state,
    select the input (HDMI, AV, AirPlay, internet radio, Tuner, ...), select the volume
    or mute/unmute the volume.<br><br>
    Defining a YAMAHA_AVR device will schedule an internal task (interval can be set
    with optional parameter &lt;status_interval&gt; in seconds, if not set, the value is 30 seconds), which periodically reads
    the status of the AV receiver (power state, selected input, volume and mute status)
    and triggers notify/filelog commands.<br><br>

    Example:
    <ul>
      <code>define AV_Receiver YAMAHA_AVR 192.168.0.10</code><br>
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
</ul>

=end html
=cut

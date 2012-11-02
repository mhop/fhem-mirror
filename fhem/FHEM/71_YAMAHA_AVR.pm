#
#  Module: YAMAHA_AVR
#
# An FHEM Perl module for controlling Yamaha AV-Receivers
# via network connection. As the interface is standardized
# within all Yamaha AV-Receivers, this module should work
# with any receiver which has an ethernet or wlan connection.
# 
# Currently supported are:  power (on|off)
#                           input (hdmi1|hdmi2|...)
#                           volume (-50 ... 10)
#                           mute (on|off)
#
# Of course there are more possibilities than these 4 commands.
# But in my oppinion these are the most relevant usecases within FHEM.
#
# $Id$
#
###################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday sleep);


sub YAMAHA_AVR_Get($@);
sub YAMAHA_AVR_Define($$);
sub YAMAHA_AVR_GetStatus($);
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
YAMAHA_AVR_GetStatus($$)
{
    my ($hash, $local) = @_;
    my $name = $hash->{NAME};
    my $power;
    $local = 0 if(!defined($local));
    
    return "" if(!defined($hash->{ADDRESS}) or !defined($hash->{INTERVAL}));
    
    my $device = $hash->{ADDRESS};
    my $return = SendCommand($device,"<YAMAHA_AV cmd=\"GET\"><Main_Zone><Basic_Status>GetParam</Basic_Status></Main_Zone></YAMAHA_AV>");


    return "Can't submit command. please see fhem logfile for further information" if(not defined($return) or length($return) == 0);
    
    readingsBeginUpdate($hash);
    
    if($return =~ /<Power>(.+)<\/Power>/)
    {
       $power = $1;
       readingsUpdate($hash, "power", lc($power));
       if($power eq "Standby")
       {
	    $power = "Off";
       }
       
       $hash->{STATE} = lc($power);
       
    }
    if($return =~ /<Volume><Lvl><Val>(.+)<\/Val><Exp>(.+)<\/Exp><Unit>.+<\/Unit><\/Lvl><Mute>(.+)<\/Mute><\/Volume>/)
    {
	readingsUpdate($hash, "volume_level", ($1 / 10 ** $2));
	readingsUpdate($hash, "mute", lc($3));
    }
    
    if($return =~ /<Input_Sel>(.+)<\/Input_Sel>/)
    {
	readingsUpdate($hash, "input", lc($1));
    }
    
    readingsEndUpdate($hash, 1);
    
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "YAMAHA_AVR_GetStatus", $hash, 1) unless $local == 0;
    
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
    
    
    if($what =~ /^(power|input|volume|mute)$/)
    {
        YAMAHA_AVR_GetStatus($hash, 1);
        if(defined($hash->{READINGS}{$what}))
        {
    	    return $a[0]." ".$what." => ".$hash->{READINGS}{$what}{VAL};
	}
	else
	{
	    return "no such reading: $what";
	}
    }
    else
    {
	return "Unknown argument $what, choose one of param power input volume mute get";
    }
}


###################################
sub
YAMAHA_AVR_Set($@)
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{ADDRESS};
    my $result = "";
    my $inputs_piped = $hash->{INPUTS};
    
    return "No Argument given" if(!defined($a[1]));
    
    my $what = $a[1];
    my $usage = "Unknown argument $what, choose one of on off volume:slider,-80,1,16 input:".$hash->{INPUTS}." mute:on,off statusRequest";

    readingsBeginUpdate($hash);
    if($what eq "on")
    {
	$result = SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>On</Power></Power_Control></Main_Zone></YAMAHA_AV>");
	if($result =~ /RC="0"/ and $result =~ /<Power><\/Power>/)
	{
	    # As the receiver startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
	    readingsUpdate($hash, "power", "on");
	    $hash->{STATE} = "on";
	    return undef;
	}   
    }
    elsif($what eq "off")
    {
	SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Power_Control><Power>Standby</Power></Power_Control></Main_Zone></YAMAHA_AV>");
    }
    elsif($what eq "input")
    {
	if(defined($a[2]))
	{
	    if($hash->{STATE} eq "on")
	    {
	        $inputs_piped =~ s/,/|/g;
	        
		if($a[2] =~ /^($inputs_piped)$/)
		{
		    if($a[2] eq "netradio")
		    {
			$result = SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Input><Input_Sel>NET RADIO</Input_Sel></Input></Main_Zone></YAMAHA_AV>");
		    }
		    elsif($a[2] eq "airplay")
		    {
			$result = SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Input><Input_Sel>AirPlay</Input_Sel></Input></Main_Zone></YAMAHA_AV>");
		    }
		    else
		    {
			$result = SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Input><Input_Sel>".uc($a[2])."</Input_Sel></Input></Main_Zone></YAMAHA_AV>");
		    }

		    if(not $result =~ /RC="0"/)
		    {
			# if the returncode isn't 0, than the command was not successful
			return "Could not set input to ".$a[2].". Please use only available inputs on your specific receiver";
		    }
		}
		else
		{
		    return $usage;
		}
	    }
	    else
	    {
		return "input can only be used when device is powered on";
	    }
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
		    SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Mute>On</Mute></Volume></Main_Zone></YAMAHA_AV>");
		}
		elsif($a[2] eq "off")
		{
		    SendCommand($address, "<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Mute>Off</Mute></Volume></Main_Zone></YAMAHA_AV>"); 
		
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
			
			    SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Lvl><Val>".(($current_volume + ($diff * $step))*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></Main_Zone></YAMAHA_AV>");
			
				sleep $sleep unless ($time == 0);
			}
		    }
		    
		    # After complete smoothing, set the real wanted volume
		    Log GetLogLevel($name, 4), "YAMAHA_AV set volume to ".$a[2]." dB";
		    SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Lvl><Val>".($a[2]*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></Main_Zone></YAMAHA_AV>");
		}
		else
		{
		    SendCommand($address,"<YAMAHA_AV cmd=\"PUT\"><Main_Zone><Volume><Lvl><Val>".($a[2]*10)."</Val><Exp>1</Exp><Unit>dB</Unit></Lvl></Volume></Main_Zone></YAMAHA_AV>");
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
    my @inputs;
    
    if(! @a >= 3)
    {
	my $msg = "wrong syntax: define <name> YAMAHA_AVR <ip-or-hostname> [<statusinterval>]";
	Log 2, $msg;
	return $msg;
    }


    my $address = $a[2];
  
    my $response = GetFileFromURL("http://".$address."/YamahaRemoteControl/desc.xml");
    if($response =~ /<Unit_Description.* Unit_Name="(.+?)">/)
    {
        $hash->{MODEL} = $1;
    }

    $hash->{ADDRESS} = $address;
  
    $response = SendCommand($address, "<YAMAHA_AV cmd=\"GET\"><Main_Zone><Input><Input_Sel_Item>GetParam</Input_Sel_Item></Input></Main_Zone></YAMAHA_AV>");
    $response =~ s/></>\n</g;
    @inputs = split("\n", $response);
    
    foreach (sort @inputs)
    {
	if($_ =~ /<Param>(.+?)<\/Param>/ and not $1 =~ /iPod/)
	{
	    if(defined($hash->{INPUTS}) and length($hash->{INPUTS}) > 0)
	    {
	      $hash->{INPUTS} .= ",";
	    }
	    if($1 eq "NET RADIO")
	    {
		$hash->{INPUTS} .= "netradio";
	    }
	    else
	    {
		$hash->{INPUTS} .= lc($1);
	    }
	}
    }
    
    
    if(defined($a[3]) and $a[3] > 0)
    {
	$hash->{INTERVAL}=$a[3];
    }
    else
    {
	$hash->{INTERVAL}=30;
    }
    $attr{$name}{"volume-smooth-change"} = "1";
    
    InternalTimer(gettimeofday()+2, "YAMAHA_AVR_GetStatus", $hash, 0);
  
  return undef;
}

#############################
sub
SendCommand($$)
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

1;

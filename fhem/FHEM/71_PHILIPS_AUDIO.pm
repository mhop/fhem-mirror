##############################################################################
#
#     $Id$
#
#     71_PHILIPS_AUDIO.pm
#
#     An FHEM Perl module for controlling Philips Audio Equipment connected to local network
#     such as MCi, Streamium and Fidelio devices.
#     The module provides basic functionality accessible through the port 8889 of the device:
#     (http://<device_ip>:8889/index).
#
#     Copyright by Radoslaw Watroba
#     (e-mail: ra666ack@googlemail.com)
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
use Time::Piece;
use POSIX qw{strftime};
use HttpUtils;

###################################
sub PHILIPS_AUDIO_Initialize
{
  my ($hash) = @_;

  $hash->{DefFn}     = "PHILIPS_AUDIO_Define";
  $hash->{GetFn}     = "PHILIPS_AUDIO_Get";
  $hash->{SetFn}     = "PHILIPS_AUDIO_Set";
  $hash->{AttrFn}    = "PHILIPS_AUDIO_Attr";
  $hash->{UndefFn}   = "PHILIPS_AUDIO_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 disable:0,1 request-timeout:1,2,3,4,5 ".$readingFnAttributes;
  
  return;
}

###################################
sub PHILIPS_AUDIO_GetStatus
{
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $power;

  $local = 0 unless(defined($local));

  return "" if((!defined($hash->{IP_ADDRESS})) or (!defined($hash->{helper}{OFF_INTERVAL})) or (!defined($hash->{helper}{ON_INTERVAL})));

  my $device = $hash->{IP_ADDRESS};
  
  PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "","nowplay", "noArg");
  PHILIPS_AUDIO_ResetTimer($hash) unless($local == 1);
  
  return;
}

###################################
sub PHILIPS_AUDIO_Get
{
  my ($hash, @a) = @_;
  my $what;
  my $return;
  
  my $name = $hash->{NAME};
  
  my $address = $hash->{IP_ADDRESS};
  $hash->{IP_ADDRESS} = $address;
  
  return "argument is missing" if(int(@a) != 2);
  
  if(not defined($hash->{MODEL}))
  {
    return "Please provide the model information as argument.";    
  }  
  
  $what = $a[1];
  
  if(exists($hash->{READINGS}{$what}))
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
    $return = "unknown argument $what, choose one of";
    
    foreach my $reading (keys %{$hash->{READINGS}})
    {
      $return .= " $reading:noArg";
    }
  
    return $return;
  }
}

###################################
sub PHILIPS_AUDIO_Set
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $port = $hash->{PORT};
  
  if(not defined($hash->{MODEL}))
  {
    return "Please provide the model information as argument.";
  }
  
  return "No Argument given" if(!defined($a[1]));     
  
  my $what = $a[1];
  
  my $usage;
  
  $usage = "Unknown argument $what, choose one of ".
           "volumeStraight:slider,0,1,64 ".
           "volume:slider,0,1,100 ".
           #"volumeUp:noArg ".
           #"volumeDown:noArg ".
           "standbyButton:noArg ".
           "unmute:noArg ".
           "next:noArg ".
           "previous:noArg ".
           "play_pause:noArg ".
           "stop:noArg ".
           "shuffle:on,off ".
           "aux:noArg ".
           #"input:aux,internetRadio,mediaLibrary,onlineServices ".
           "inetRadioPreset:1,2,3,4,5,6,7,8,9,10 ".
           "statusRequest:noArg ".
           #"addToFavourites:noArg ".
           #"removeFromFavourites:noArg ".
           "repeat:single,all,off ".
           #"home:noArg ".
           "mute:noArg ";         
    
  Log3 $name, 5, "PHILIPS_AUDIO ($name) - set ".join(" ", @a);
    
  if($what eq "standbyButton")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$STANDBY", "",$what, "noArg");
  }
  elsif($what eq "aux")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/aux", "",$what, $a[2]);
  }
  elsif($what eq "home")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/index", "",$what, $a[2]);
  }
  elsif($what  eq "mediaLibrary")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/nav\$02\$01\$001\$0", "",$what, $a[2]);
  }
  elsif($what  eq "internetRadio")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "",$what, $a[2]);
  }
  elsif($what  eq "onlineServices")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/nav\$09\$01\$001\$0", "",$what, $a[2]);
  }  
  elsif($what eq "shuffle")
  {
    if($a[2]  eq "on")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$SHUFFLE_ON", "",$what, $a[2]);
    }
    elsif($a[2]  eq "off")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$SHUFFLE_OFF", "",$what, $a[2]);
    }
    else
    {
      return $usage;
    }
  }
  elsif($what eq "repeat")
  {
    if($a[2]  eq "single")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$REPEAT_SINGLE", "",$what, $a[2]);
    }
    elsif($a[2]  eq "all")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$REPEAT_ALL", "",$what, $a[2]);
    }
    elsif($a[2]  eq "off")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$REPEAT_OFF", "",$what, $a[2]);
    }
    else
    {
      return $usage;
    }
  }
  elsif($what eq "statusRequest")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "","nowplay", "noArg");
  }
  elsif($what eq "addToFavourites")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$ADD2FAV", "",$what, "noArg");
  }
  elsif($what eq "removeFromFavourites")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$REMFAV", "",$what, "noArg");
  }
  elsif($what eq "mute")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$MUTE", "",$what, "noArg");
  }
  elsif($what eq "unmute")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$UNMUTE", "",$what, "noArg");
  }
  elsif($what eq "next")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$NEXT", "",$what, "noArg");
  }
  elsif($what eq "previous")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$PREV", "",$what, "noArg");
  }
  elsif($what eq "play_pause")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$PLAY_PAUSE", "",$what, "noArg");
  }
  elsif($what eq "stop")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$STOP", "",$what, "noArg");
  }
  elsif($what eq "inetRadioPreset")
  {
    # Hierarchichal navigation through the contents mandatory
    $hash->{helper}{cmdStep} = 1;
    $hash->{helper}{inetRadioPreset} = $a[2];
    PHILIPS_AUDIO_SendCommand($hash, "/index", "", $what, $a[2]);    
  }
  elsif($what eq "volumeStraight")
  {
    if($a[2] >= 0 and $a[2] <= 64)
    {
      $hash->{helper}{targetVolume} = $a[2];
      PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$VAL\$".$a[2], "",$what, $a[2]);
    }
    else
    {
      return "volumeStraight must be in the range 0...64.";
    }
  }
  elsif($what eq "volume")
  {
    if($a[2] >= 0 and $a[2] <= 100)
    {
      $hash->{helper}{targetVolume} = PHILIPS_AUDIO_volume_rel2abs($hash, $a[2]);
      PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$VAL\$".$a[2], "",$what, $a[2]);
    }
    else
    {
      return "volumeStraight must be in the range 0...100.";
    }
  }
  elsif($what eq "nowplay")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "",$what, "noArg");
  }  
  else  
  {
    return $usage;
  }  
  return;
}

#############################
sub PHILIPS_AUDIO_Define
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(! @a >= 4)
    {
      my $msg = "Wrong syntax: define <name> PHILIPS_AUDIO <model> <ip-or-hostname> [<ON-statusinterval>] [<OFF-statusinterval>] ";
      Log3 $name, 2, $msg;
      return $msg;
    }
    
    if(defined($a[2]))
    {
      $hash->{MODEL} = $a[2];
    }
    
    $hash->{IP_ADDRESS} = $a[3];
    $hash->{PORT}    = 8889;
    
    # if an update interval was given which is greater than zero, use it.
    if(defined($a[4]) and $a[4] > 0)
    {
      $hash->{helper}{OFF_INTERVAL} = $a[4];
      # Minimum interval 3 sec
      if($hash->{helper}{OFF_INTERVAL} < 3)
      {
        $hash->{helper}{OFF_INTERVAL} = 3;
      }
    }
    else
    {
      $hash->{helper}{OFF_INTERVAL} = 30;
    }
      
    if(defined($a[5]) and $a[5] > 0)
    {
      $hash->{helper}{ON_INTERVAL} = $a[5];
      # Minimum interval 3 sec
      if($hash->{helper}{ON_INTERVAL} < 3)
      {
        $hash->{helper}{ON_INTERVAL} = 3;
      }
    }
    else
    {
      $hash->{helper}{ON_INTERVAL} = $hash->{helper}{OFF_INTERVAL};
    }
    
    unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
    {
      $hash->{helper}{AVAILABLE} = 1;
      readingsSingleUpdate($hash, "presence", "present", 1);
    }
    
    # start the status update timer
    $hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));
    PHILIPS_AUDIO_ResetTimer($hash,0);
  
    return;
}


##########################
sub PHILIPS_AUDIO_Attr
{
  my @a = @_;
  my $hash = $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "disable")
  {
    if($a[3] eq "0")
    {
      $hash->{helper}{DISABLED} = 0;
      PHILIPS_AUDIO_GetStatus($hash, 1);
    }
    elsif($a[3] eq "1")
    {
      $hash->{helper}{DISABLED} = 1;
    }
  }
  elsif($a[0] eq "del" && $a[2] eq "disable")
  {
    $hash->{helper}{DISABLED} = 0;
    PHILIPS_AUDIO_GetStatus($hash, 1);
  }

  # Start/Stop Timer according to new disabled-Value
  PHILIPS_AUDIO_ResetTimer($hash);

  return;
}

#############################
sub PHILIPS_AUDIO_Undefine
{
  my($hash, $name) = @_;

  # Stop the internal GetStatus-Loop and exit
  RemoveInternalTimer($hash);
  return;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

#############################
# sends a command to the receiver via HTTP
sub PHILIPS_AUDIO_SendCommand
{
  my ($hash,$url,$data,$cmd,$arg) = @_;
  my $name    = $hash->{NAME};
  my $address = $hash->{IP_ADDRESS};
  my $port    = $hash->{PORT};

  Log3 $name, 5, "PHILIPS_AUDIO ($name) - execute nonblocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";
    
  HttpUtils_NonblockingGet
  ({
    url        => "http://".$address.":".$port."".$url,
    timeout    => AttrVal($name, "request-timeout", 30),
    noshutdown => 1,
    data       => $data,
    loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
    hash       => $hash,
    cmd        => $cmd,
    arg        => $arg,
    callback   => \&PHILIPS_AUDIO_ParseResponse                        
  });  
  return;  
}

#############################
# parses the receiver response
sub PHILIPS_AUDIO_ParseResponse
{
    my ($param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $cmd = $param->{cmd};
    my $arg = $param->{arg};
    
    if(exists($param->{code}))
    {
      Log3 $name, 5, "PHILIPS_AUDIO ($name) - received HTTP code ".$param->{code}." for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
    }
    
     #Log3 $name, 5, "Error = $err";
     #Log3 $name, 5, "Data = $data";
    
    if($err ne "")
    {
      Log3 $name, 5, "PHILIPS_AUDIO ($name) - could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $err";

      if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} == 1))
      {
        Log3 $name, 3, "PHILIPS_AUDIO ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
        readingsSingleUpdate($hash, "presence", "absent", 1);
        readingsSingleUpdate($hash, "state", "absent", 1);
        $hash->{STATE} = "absent";
      }  

      $hash->{helper}{AVAILABLE} = 0;
    }
    elsif($data ne "")
    {
      Log3 $name, 5, "PHILIPS_AUDIO ($name) - got response for \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $data";

      if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
      {
        Log3 $name, 3, "PHILIPS_AUDIO ($name) - device $name reappeared";
        readingsSingleUpdate($hash, "presence", "present", 1);        
      }     
      
      $hash->{helper}{AVAILABLE} = 1;
           
      readingsBeginUpdate($hash);
      
      readingsBulkUpdate($hash, "power", "on");
      readingsBulkUpdate($hash, "state","on");
      $hash->{STATE} = "on";
      
      if($cmd eq "standbyButton")
      {
        if($data =~ /SUCCESS/)
        {
          #readingsBulkUpdate($hash, "power", "on");
          #readingsBulkUpdate($hash, "state","on");          
        }        
      }      
      elsif($cmd eq "mute")
      {
        if($data =~ /SUCCESS/)
        {
          readingsBulkUpdate($hash, "mute", "on");
        }
      }
      elsif($cmd eq "unmute")
      {
        if($data =~ /SUCCESS/)
        {
          readingsBulkUpdate($hash, "mute", "off");
        }
      }
      elsif($cmd eq "removeFromFavourites")
      {
        # evtl. for future use
      }
      elsif($cmd eq "addToFavourites")
      {
        # evtl. for future use
      }
      elsif($cmd eq "inetRadioPreset")
      {        
        # This command must be processed hierarchicaly through the navigation path
        if($hash->{helper}{cmdStep} == 1)
        {
          $hash->{helper}{cmdStep} = 2;
          # Internet radio
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "", "inetRadioPreset", $hash->{helper}{inetRadioPreset});
        }
        elsif($hash->{helper}{cmdStep} == 2)
        {
          $hash->{helper}{cmdStep} = 3;
          # Presets
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$02\$001\$0", "","inetRadioPreset", $hash->{helper}{inetRadioPreset});
        }
        elsif($hash->{helper}{cmdStep} == 3)
        {
          $hash->{helper}{cmdStep} = 4;
          # Preset select
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$03\$".sprintf("%03d", $hash->{helper}{inetRadioPreset})."\$1", "","inetRadioPreset", $hash->{helper}{inetRadioPreset});
        }               
      }
      elsif($cmd eq "play_pause")
      {
        if($data =~ /SUCCESS/)
        {
          #readingsBulkUpdate($hash, "play_pause", "on");
          #readingsBulkUpdate($hash, "stop", "off");
        }
      }
      elsif($cmd eq "stop")
      {
        if($data =~ /STOP/)
        {
          readingsBulkUpdate($hash, "playing", "no");          
        }
      }      
      elsif($cmd eq "volume" or $cmd eq "volumeStraight")
      {        
        if($data =~ /SUCCESS/)
        {
          readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
          my $targetVolume = $hash->{helper}{targetVolume};
          readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $targetVolume));          
        }
      }      
      elsif($cmd eq "nowplay")
      {        
        if($data =~ /'title':'\\'(.+)\\''/)
        {
          readingsBulkUpdate($hash, "title", PHILIPS_AUDIO_STREAMIUMNP2txt($1));
        }
        else
        {
          readingsBulkUpdate($hash, "title", "");
        }
        
        if($data =~ /'title':'(.+)'/)
        {
          readingsBulkUpdate($hash, "title", PHILIPS_AUDIO_STREAMIUMNP2txt($1));
        }
        else
        {
          readingsBulkUpdate($hash, "title", "");
        }
        
        if($data =~ /'subTitle':'(.+)'/)
        {
          readingsBulkUpdate($hash, "subtitle", $1);
        }
        else
        {
          readingsBulkUpdate($hash, "subtitle", "");
        }
        
        if($data =~ /'albumArt':'(.+)'/)
        {
          readingsBulkUpdate($hash, "albumArt", $1);
        }
        else
        {
          readingsBulkUpdate($hash, "albumArt", "");
        }
        
        if($data =~ /'volume':(.+),/)
        {
          readingsBulkUpdate($hash, "volumeStraight", $1);
          readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $1));          
        }
        else
        {
          readingsBulkUpdate($hash, "volumeStraight", "0");
          readingsBulkUpdate($hash, "volume", "0");  
        }
        
        if($data =~ /'elapsetime':(.+),/)
        {
          readingsBulkUpdate($hash, "elapseTime", strftime("\%H:\%M:\%S", gmtime($1)));
        }
        else
        {
          readingsBulkUpdate($hash, "elapseTime", "");
        }
        if($data =~ /'totaltime':(.+),/)
        {
          # Playing radio delivers that total time
          if($1 eq "65535")
          {
            readingsBulkUpdate($hash, "totalTime", "infinite");
          }
          else
          {
            readingsBulkUpdate($hash, "totalTime", strftime("\%H:\%M:\%S", gmtime($1)));
          }          
        }
        else
        {
          readingsBulkUpdate($hash, "totalTime", "");
        }
        
        if($data =~ /'muteStatus':(.+),/)
        {
          if($1 == 1)
          {
            readingsBulkUpdate($hash, "mute", "on");
          }
          else
          {
            readingsBulkUpdate($hash, "mute", "off");
          }
        }
        
        # typo in the (buggy) Streamium firmware...
        if($data =~ /'playStaus':(.+),/)
        {
          if($1 == 1)
          {
            readingsBulkUpdate($hash, "playing", "yes");
          }        
          else
          {
            readingsBulkUpdate($hash, "playing", "no");
          }
        }
        else
        {
          readingsBulkUpdate($hash, "playing", "no");
        }
      }
      
      # Eventual future UPNP implementation. Requests IO::Socket::Multicast non-standard module.      
      elsif ($cmd eq "getModel")
      {
        if($data =~ /<friendlyName>(.+)<\/friendlyName>/)
        {
          $hash->{FRIENDLY_NAME} = $1;
        }        
        if($data =~ /<UDN>(.+)<\/UDN>/)
        {
          $hash->{UNIQUE_DEVICE_NAME} = uc($1);
        }
        
        my $modelName   = "";
        my $modelNumber = "";
        
        if($data =~ /<modelName>(.+)<\/modelName>/)
        {
          $modelName = $1;
        }       
        if($data =~ /<modelNumber>(.+)<\/modelNumber>/)
        {
          $modelNumber = $1;
        }
        # Combine both strings
        if(($modelName ne "") and ($modelNumber ne ""))
        {
          $hash->{MODEL} = $modelName . $modelNumber;
        }
        
        if($data =~ /<serialNumber>(.+)<\/serialNumber>/)
        {
          $hash->{SERIAL_NUMBER} = uc($1);
        }
        if($data =~ /<modelDescription>(.+)<\/modelDescription>/)
        {
          $hash->{MODEL_DESCRIPTION} = $1;
        }        
        # Replace \n, \r, \t from the string for XML parsing
        
        # replace \n by ""
        $data =~ s/\n//g;
        
        # replace \t by ""
        $data =~ s/\t//g;
        
        # replace \r by ""
        $data =~ s/\r//g;
        
        if($data =~ /<iconList>(.+?)<\/iconList>/)
        {
          my $address = $hash->{IP_ADDRESS};
          my $i = 1;
          
          while ($data =~ /<url>(.+?)<\/url>/g)
          {
            $hash->{"NP_ICON_$i"} = "http://".$address.":".$arg."/".$1;            
            $i++;
          }
        }
      }
      
      readingsEndUpdate($hash, 1);
    }
    return;
}

#############################
# converts straight volume in percentage volume (volumestraightmin .. volumestraightmax => 0 .. 100%)
sub PHILIPS_AUDIO_volume_rel2abs
{
  my ($hash, $percentage) = @_;
  
  return int(($percentage * 64 / 100 ));
}

#############################
# converts relative volume to "straight" volume (0 .. 100% => volumestraightmin .. volumestraightmax)
sub PHILIPS_AUDIO_volume_abs2rel
{
  my ($hash, $absolute) = @_;
  
  return int(int($absolute * 100) / int(64));    
}

#############################
# Restarts the internal status request timer according to the given interval or current receiver state
sub PHILIPS_AUDIO_ResetTimer
{
  my ($hash, $interval) = @_;

  RemoveInternalTimer($hash);

  if($hash->{helper}{DISABLED} == 0)
  {
    if(defined($interval))
    {
      InternalTimer(gettimeofday()+$interval, "PHILIPS_AUDIO_GetStatus", $hash, 0);
    }
    elsif((exists($hash->{READINGS}{presence}{VAL}) and $hash->{READINGS}{presence}{VAL} eq "present") and (exists($hash->{READINGS}{power}{VAL}) and $hash->{READINGS}{power}{VAL} eq "on"))
    {
      InternalTimer(gettimeofday() + $hash->{helper}{ON_INTERVAL}, "PHILIPS_AUDIO_GetStatus", $hash, 0);
    }
    else
    {
      InternalTimer(gettimeofday() + $hash->{helper}{OFF_INTERVAL}, "PHILIPS_AUDIO_GetStatus", $hash, 0);
    }
  }  
  return;
}

#############################
# convert all HTML entities into UTF-8 equivalent
sub PHILIPS_AUDIO_STREAMIUMNP2txt
{
  my ($string) = @_;

  $string =~ s/\\'//g;
  return $string;
}

1;

=pod
=begin html

<a name="PHILIPS_AUDIO"></a>
<h3>PHILIPS_AUDIO</h3>
<ul>
  <a name="PHILIPS_AUDIOdefine"></a>
  <b>Define</b>
  <br><br>
  <ul>
    <code>
      define &lt;name&gt; PHILIPS_AUDIO &lt;device model&gt; &lt;ip-address&gt; [&lt;status_interval&gt;]<br><br>
      define &lt;name&gt; PHILIPS_AUDIO &lt;device model&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>
    This module controls a Philips Audio Player e.g. MCi, Streamium or Fidelio and (potentially) any other device including a navigation server.<br>
    To check, open the following URL in the browser: http://[ip # of your device]:8889/index
    <br><br>
    Currently implemented features:
    <br><br>
    <ul>
      <li>Power on/off</li>
      <li>Internet Radio Preset Selection</li>
      <li>Input selection</li>
      <li>Volume +/-</li>
      <li>Mute on/off</li>
      <li>...</li>
    </ul>
    <br>
    Defining a PHILIPS_AUDIO device will schedule an internal task (interval can be set
    with optional parameters &lt;off_status_interval&gt; and &lt;on_status_interval&gt; in seconds.<br>
    &lt;off_status_interval&gt; is a parameter used in case the device is powered off or not available.<br>
    &lt;on_status_interval&gt; is a parameter used in case the device is powered on.<br>
    If both parameters are unset, a default value 30 (seconds) for both is used.<br>
    If &lt;off_status_interval&gt; is set only the same value is used for both parameters.<br>
    Due to a relatively low-performance of the devices the minimum interval is set to 3 seconds.
    <br>
    The internal task periodically reads the status of the Network Player (power state, volume and mute status etc.) and triggers notify/filelog commands.
    <br><br>    
    Example:<br><br>
    <ul><br>
      Add the following code into the <b>fhem.cfg</b> configuration file and restart fhem:<br><br>
      <code>
      define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15<br>
      attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset<br><br>
      # With custom status interval of 60 seconds<br>
      define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60</b><br>
      attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset<br><br>
      # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
      define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60 10</b><br>
      attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset<br><br>
      </code>
    </ul>   
  </ul>
  <br><br>
  <a name="PHILIPS_AUDIOset"></a>
  <b>Set</b>
  <ul>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code><br><br>
    Currently, the following commands are defined.<br>    
    <i>Note: Commands and parameters are case sensitive.</i><br>
      <ul><br><br>
      <u>Available commands:</u><br><br>
      <li><b>aux</b>&nbsp;&nbsp;-&nbsp;&nbsp; Switches to the AUX input (MP3 Link or similar).</li>
      <li><b>inetRadioPreset</b> [1..10] &nbsp;&nbsp;-&nbsp;&nbsp; Selects an internet radio preset (be patient...).</li>
      <li><b>mute</b>&nbsp;&nbsp;-&nbsp;&nbsp; Mutes the device.</li>
      <li><b>unmute</b>&nbsp;&nbsp;-&nbsp;&nbsp; Unmutes the device.</li>
      <li><b>next</b> &nbsp;&nbsp;-&nbsp;&nbsp; Selects the next song, preset etc.</li>
      <li><b>play_pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; Toggles PLAY/PAUSE.</li>
      <li><b>previous</b> &nbsp;&nbsp;-&nbsp;&nbsp; Selects the previous song, preset etc.</li>
      <li><b>repeat [single|all|off]</b> &nbsp;&nbsp;-&nbsp;&nbsp; Sets the repeat mode.</li>
      <li><b>shuffle [on|off]</b> &nbsp;&nbsp;-&nbsp;&nbsp; Sets the shuffle mode.</li>
      <li><b>standbyButton</b> &nbsp;&nbsp;-&nbsp;&nbsp; Toggles between standby and power on.</li>
      <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; Updates the readings.</li>
      <li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; Stops the player.</li>
      <li><b>volume</b> &nbsp;&nbsp;-&nbsp;&nbsp; Sets the relative volume 0...100%.</li>
      <li><b>volumeStraight</b> &nbsp;&nbsp;-&nbsp;&nbsp; Sets the absolute volume 0...64.</li>     
    </ul><br><br>

    A typical example is powering the device remotely and tuning the favourite radio station:<br><br>
    Add the following code into the <b>fhem.cfg</b> configuration file:<br><br><br>
    <ul>
      <code>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 30 5<br>
        attr PHAUDIO_player webCmd volume:mute:inetRadioPreset
      </code>
    </ul><br><br>
    Add the following code into the <b>99_MyUtils.pm</b> file:<br><br>
    <ul>
      <code>
        sub startMyFavouriteRadioStation()<br>
        {<br>
          &nbsp;&nbsp;fhem "set PHAUDIO_player inetRadioPreset 1";<br>
          &nbsp;&nbsp;sleep 1;<br>
          &nbsp;&nbsp;fhem "set PHAUDIO_player volume 30";<br>
        }
      </code>
    </ul>
    <br><br>
    It's a good idea to insert a 'sleep' instruction between each fhem commands due to internal processing time of the player. Be patient when executing the commands...<br><br>

    Now the function can be called by typing the following line in the FHEM command line or by the notify-definitions:<br><br>
    <ul>
      <code>
        {startMyFavouriteRadioStation()}<br><br>
      </code>
    </ul>
  </ul>
  <a name="PHILIPS_AUDIOget"></a>
  <b>Get</b>
  <ul>
    <code>
      get &lt;name&gt; &lt;reading&gt;
    </code>
    <br><br>
    Currently, the 'get' command returns reading values only. For a specific list of possible values, see section <b>"Generated Readings"</b>.<br><br>
  </ul>
  <a name="PHILIPS_AUDIOattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <ul>  
      <li><b><a href="#do_not_notify">do_not_notify</a></b></li>
      <li><b><a href="#readingFnAttributes">readingFnAttributes</a></b></li>
      <li><b><a name="request-timeout">request-timeout</a></b></li>
      <br>Optional attribute change the response timeout in seconds for all queries to the receiver.
      <br>Possible values: 1...5 seconds. Default value is 4 seconds.<br><br>
      <li><b><a name="disable">disable</a></b></li>
      <br>Optional attribute to disable the internal cyclic status update of the receiver. Manual status updates via statusRequest command is still possible.
      <br>Possible values: 0 &rarr; perform cyclic status update, 1 &rarr; don't perform cyclic status updates.<br><br><br>
    </ul>
  </ul>
  <b>Readings</b><br><br>
  <ul>
    <ul>
      <li><b>albumArt</b> - Link to current album art or radio station.</li>
      <li><b>elapseTime</b> - Elapse time of the played audio.</li>
      <li><b>mute</b> - Reports the mute status (on|off).</li>
      <li><b>playing</b> - Reports the current playier status (yes|no).</li>
      <li><b>power</b> - Reports the current power status (on|absent).</li>
      <li><b>presence</b> - Reports the current presence (present|absent).</li>
      <li><b>state</b> - Reports the current state status (on|absent).</li>
      <li><b>subtitle</b> - Reports the current subtitle of played audio.</li>
      <li><b>title</b> - Reports the current title of played audio.</li>
      <li><b>totalTime</b> - Reports the total time of the played audio.</li>
      <li><b>volume</b> - Reports current relative volume (0..100).</li>
      <li><b>volumeStraight</b> - Reports current absolute volume (0..64).</li>      
    </ul>
  </ul><br>
  <b>Implementer's note</b><br><br>
    <ul>
    Trivial: In order to use that module the network player must be connected to the Ethernet.<br>
    There's no possibility to read back the current power on/standby status from the device. This fuctionality is missing in the server application.<br>
    </ul><br>
</ul>
=end html
=begin html_DE

<a name="PHILIPS_AUDIO"></a>
<h3>PHILIPS_AUDIO</h3>
<ul>
  <a name="PHILIPS_AUDIOdefine"></a>
  <b>Define</b><br><br>
  <ul>
    <code>
      define &lt;name&gt; PHILIPS_AUDIO &lt;device model&gt; &lt;ip-address&gt; [&lt;status_interval&gt;]<br><br>
      define &lt;name&gt; PHILIPS_AUDIO &lt;device model&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>
    Mit Hilfe dieses Moduls lassen sich Philips Audio Netzwerk Player wie z.B. MCi, Streamium oder Fidelio via Ethernet steuern.<br>
    Theoretisch sollten alle Ger&auml;te, die &uuml;ber einer implementierten HTTP Server am Port 8889 haben (http://[ip Nummer des Ger&auml;tes]:8889/index), bedient werden k&ouml;nnen.<br>
    <br>
    
    Die aktuelle Implementierung erm&ouml;glicht u.a. den folgenden Funktionsumfang:<br><br>
    <ul>
      <li>Power on/off</li>
      <li>Internet Radio Preset Auswahl</li>
      <li>Input Auswahl</li>
      <li>Volume +/-</li>
      <li>Mute on/off</li>
      <li>...</li>
    </ul>
    <br>
    Eine PHILIPS_AUDIO Definition initiiert einen internen Task, der von FHEM zyklisch abgearbeitet wird.<br>
    Das Intervall (in Sekunden) kann f&uuml;r die Zust&auml;nde &lt;on_status_interval&gt; und &lt;off_status_interval&gt; optional gesetzt werden.<br>
    &lt;off_status_interval&gt; steht f&uuml;r das Intervall, wenn das Ger&auml;t ausgeschaltet/abwesend ist.<br>
    &lt;on_status_interval&gt; steht f&uuml;r das Intervall, wenn das Ger&auml;t eingeschaltet/verf&uuml;gbar ist.<br>
    Wenn keine Parameter angegeben wurden, wird ein Default-Wert von 30 Sekunden f&uuml;r beide gesetzt.<br>
    Wenn nur &lt;off_status_interval&gt; gesetzt wird, gilt dieser Wert f&uuml;r beide Zust&auml;nde (eingeschaltet/ausgeschaltet).<br>
    Der Task liest zyklisch grundlegende Parameter vom Player und triggert notify/filelog Befehle.<br>
    Aufgrund der recht schwachen Rechenleistung der Player wurde das minimale Intervall auf 3 Sekunden beschr&auml;nkt.<br><br>    
    Beispiel:<br><br>
    <ul><br>
      Definition in der <b>fhem.cfg</b> Konfigurationsdatei:<br><br>
      <code>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15<br>
        attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset<br><br>
        # 60 Sekunden Intervall<br>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60</b><br>
        attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset<br><br>
        # 60 Sekunden Intervall f&uuml;r "off" und 10 Sekunden f&uuml;r "on"<br>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60 10</b><br>
        attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset
      </code>
    </ul>   
  </ul><br><br>
  <a name="PHILIPS_AUDIOset"></a>
  <b>Set</b>
  <ul>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code>
    <br><br>
    Aktuell sind folgende Befehle implementiert:<br>
    <i>Bemerkung: Bitte bei den Befehlen und Parametern die Gro&szlig;- und Kleinschreibung beachten.</i><br>
    <ul><br><br>
      <li><b>aux</b>&nbsp;&nbsp;-&nbsp;&nbsp; Schaltet auf den AUX Eingang um (MP3 Link oder &auml;hnlich.).</li>
      <li><b>inetRadioPreset</b> [1..10] &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt die Internetradio Voreinstellung (Gedult...).</li>
      <li><b>mute</b>&nbsp;&nbsp;-&nbsp;&nbsp; Stummschaltung des Players.</li>
      <li><b>unmute</b>&nbsp;&nbsp;-&nbsp;&nbsp; Deaktivierung der Stummschaltung.</li>
      <li><b>next</b> &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt den n&auml;chten Titel, Voreinstellung etc.</li>
      <li><b>play_pause</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet um zwischen PLAY um PAUSE.</li>
      <li><b>previous</b> &nbsp;&nbsp;-&nbsp;&nbsp; W&auml;hlt den vorherigen Titel, Voreinstellung etc.</li>
      <li><b>repeat [single|all|off]</b> &nbsp;&nbsp;-&nbsp;&nbsp; Bestimmt den Wiederholungsmodus.</li>
      <li><b>shuffle [on|off]</b> &nbsp;&nbsp;-&nbsp;&nbsp; Bestimmt den Zufallswiedergabemodus.</li>
      <li><b>standbyButton</b> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet um zwischen Standby und Power on.</li>
      <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; Readings Update.</li>
      <li><b>stop</b> &nbsp;&nbsp;-&nbsp;&nbsp; Stoppt den Player.</li>
      <li><b>volume</b> &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die relative Lautst&auml;rke 0...100%.</li>
      <li><b>volumeStraight</b> &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die absolute Lautst&auml;rke  0...64.</li>
    </ul><br><br>
      Ein typisches Beispiel ist das Einschalten des Ger&auml;tes und das Umschalten auf den Lieblingsradiosender:<br><br>
      Beispieldefinition in der <b>fhem.cfg</b> Konfigurationsdatei:<br><br><br>
      <ul>
        <code>
          define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 30 5<br>
          attr PHAUDIO_player webCmd input:volume:mute:inetRadioPreset
        </code>
      </ul><br><br>
      Folgender Code kann anschlie&szlig;end in die Datei <b>99_MyUtils.pm</b> eingebunden werden:<br><br>
      <ul>
        <code>
          sub startMyFavouriteRadioStation()<br>
          {<br>
            &nbsp;&nbsp;fhem "set PHAUDIO_player inetRadioPreset 1";<br>
            &nbsp;&nbsp;sleep 1;<br>
            &nbsp;&nbsp;fhem "set PHAUDIO_player volume 30";<br>}
        </code>
      </ul><br><br>
      <i>Bemerkung: Aufgrund der relativ langsamen Befehlsverarbeitung im  Player im Vergleich zur asynchronen Ethernet-Kommunikation, kann es vorkommen, dass veraltete Statusinformationen zur&uuml;ckgesendet werden.<br>
      Aus diesem Grund wird empfohlen, w&auml;hrend der Automatisierung zwischen den 'set' und 'get' Befehlen ein Delay einzubauen.</i><br><br>
      Die Funktion kann jetzt in der FHEM Befehlszeile eingegeben oder in die Notify-Definitionen eingebunden werden.<br><br>
      <ul>
        <code>
          {startMyFavouriteRadioStation()}<br><br>
        </code>
      </ul>
    </ul>
    <a name="PHILIPS_AUDIOget"></a>
    <b>Get</b>
    <code>
      get &lt;name&gt; &lt;reading&gt;
    </code><br><br>
    Aktuell liefert der Befehl 'get' ausschlie&szlig;lich Reading-Werte (s. Abschnitt <b>"Readings"</b>).<br><br>
  </ul>
  <a name="PHILIPS_AUDIOattr"></a>
  <ul>
    <b>Attribute</b><br><br>
    <ul>
      <ul>  
        <li><b><a href="#do_not_notify">do_not_notify</a></b></li>
        <li><b><a href="#readingFnAttributes">readingFnAttributes</a></b></li><br>
        <li><b><a name="request-timeout">request-timeout</a></b></li><br>
        Optionales Attribut, um das HTTP response timeout zu beeinflu&szlig;en.<br>
        M&ouml;gliche Werte: 1...5 Sekunden. Default Wert ist 4 Sekunden.<br><br>
        <li><b><a name="disable">disable</a></b></li><br>
        Optionales Attribut zum Deaktivieren des internen zyklischen Timers zum Aktualisieren des NP-Status. Manuelles Update ist nach wie vor m&ouml;glich.<br>
        M&ouml;gliche Werte: 0 &rarr; Zyklisches Update aktiv., 1 &rarr; Zyklisches Update inaktiv.<br><br><br>
      </ul>
    </ul>
    <b>Readings</b><br><br>
    <ul>
      <ul>
        <li><b>albumArt</b> - Link zum aktuellen Album art oder Radiostation.</li>
        <li><b>elapseTime</b> - Aktuelle Zeit des abgespielten Audiost&uuml;ckes.</li>
        <li><b>mute</b> - Abfrage des Stummschaltungstatus (on|off).</li>
        <li><b>playing</b> - Abfrage des aktuelle Playierstatus (yes|no).</li>
        <li><b>power</b> - Abfrage des aktuellen Ger&auml;tezustands (on|absent).</li>
        <li><b>presence</b> - Abfrage der Ger&auml;teanwesenheit (present|absent).</li>
        <li><b>state</b> - Abfrage des aktuellen 'state'-Status (on|absent).</li>
        <li><b>subtitle</b> - Untertiltel des abgespielten Audiost&uuml;ckes.</li>
        <li><b>title</b> - Titel des abgespielten Audiost&uuml;ckes.</li>
        <li><b>totalTime</b> Gesamtspieldauer des Audiost&uuml;ckes.</li>
        <li><b>volume</b> - Aktuelle relative Lautst&auml;rke (0..100).</li>
        <li><b>volumeStraight</b> - Aktuelle absolute Lautst&auml;rke (0..64).</li>  
      </ul>
    </ul><br>
  <b>Bemerkung des Entwicklers</b><br><br>
  <ul>
    Trivial: Um das Ger&auml;t fernbedienen zu k&ouml;nnen, muss es an das Ethernet-Netzwerk angeschlossen und erreichbar sein.<br>
    Es gibt keine M&ouml;glichkeit, den Zustand Power-on/Standby des Ger&auml;tes abzufragen. Diese Limitierung liegt auf Seiten des Ger&auml;tes.<br>
  </ul><br>
</ul>
=end html_DE
=cut
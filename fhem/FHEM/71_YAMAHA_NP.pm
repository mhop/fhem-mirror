# $Id$     
###############################################################################
#
# 71_YAMAHA_NP.pm
#
# Fhem Perl module for controlling the Yamaha PianoCraft(TM) HiFi
# Network Audiosystem MCR-N560(D) over Ethernet.
# The system is also marketed as CRX-N560(D).
#
# The module might also work with other devices such as
# NP-S2000, CD-N500, CD-N301, R-N500, R-N301 or any other device
# implementing the Yamaha Network Player Controller(TM) protocol:
#
# i*S:
# https://itunes.apple.com/us/app/network-player-controller-us/id467502483?mt=8
#
# Andr*id:
# https://play.google.com/store/apps/details?id=com.yamaha.npcontroller
#
# Since the used communication protocol is undisclosed the module bases on
# entirely reverse engineered implementation.
# Some features may be unavailable.
# (Online check for new firmware was excluded intentionally.)
#
# Many thanks go to martinp876 for his contribution to the source code
# and improved usability of the module. 
#
# Copyright by ra666ack (ra666ack a t  9 m a 1 l  d 0 t  c 0 m)
#
# This file is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU general Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU general Public License for more details.
#
# You should have received a copy of the GNU general Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday sleep);
use Time::Piece;
use POSIX qw{strftime};
use HttpUtils;
use List::Util qw(first);

sub YAMAHA_NP_Initialize
{
  my ($hash) = @_;

  $hash->{DefFn}     = "YAMAHA_NP_Define";
  $hash->{GetFn}     = "YAMAHA_NP_Get";
  $hash->{SetFn}     = "YAMAHA_NP_Set";
  $hash->{AttrFn}    = "YAMAHA_NP_Attr";
  $hash->{UndefFn}   = "YAMAHA_NP_Undefine";
  $hash->{NotifyFn}  = "YAMAHA_NP_Notify";
  
  # Generate pulldown menu for the Timer Volume
  # according to device specific range
  my $name = $hash->{NAME};
  my $volumeStraightMin = ReadingsVal($name,".volumeStraightMin",0);
  my $volumeStraightMax = ReadingsVal($name,".volumeStraightMax",60);
  my $timerVolume = "timerVolume:";
  my $i;
  
  for($i = $volumeStraightMin; $i < $volumeStraightMax; $i++)
  {
    $timerVolume .= "$i,";  
  }
  $timerVolume .= "$i";

  $hash->{AttrList}  = "do_not_notify:0,1"
                      ." disable:0,1"
                      ." requestTimeout:1,2,3,4,5"
                      ." model"
                      ." autoUpdatePlayerReadings:1,0"
                      ." autoUpdateTunerReadings:1,0"
                      ." autoUpdatePlayerlistReadings:1,0"
                      ." searchAttempts"
                      ." directPlaySleepNetradio:3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30"
                      ." directPlaySleepServer:2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30"
                      ." smoothVolumeChange:1,0"

                      ." .favoriteList" # Hidden attribute for favorites storage
                      ." .DABList" # Hidden attribute for DAB list storage
                      
                      ." maxPlayerListItems"
                      ." $timerVolume"
                      ." timerRepeat:once,every"
                      ." timerHour:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23"
                      ." timerMinute:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59"
                      ." ".$readingFnAttributes;
}

sub YAMAHA_NP_Define
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  if(! @a >= 3)
  {
    my $msg = "Wrong syntax: define <name> YAMAHA_NP <ip-or-hostname> [<OFF-statusinterval>] [<ON-statusinterval>] ";
    Log3 $name, 2, $msg;
    return $msg;
  }

  my $address = $a[2];

  $hash->{helper}{ADDRESS} = $address;

  # if an update interval was given >0, use it.
  if(defined($a[3]) and $a[3] > 0)
  {
    $hash->{helper}{OFF_INTERVAL} = $a[3];
  }
  else
  {
    $hash->{helper}{OFF_INTERVAL} = 30;
  }
    
  if(defined($a[4]) and $a[4] > 0)
  {
    $hash->{helper}{ON_INTERVAL} = $a[4];
  }
  else
  {
    $hash->{helper}{ON_INTERVAL} = $hash->{helper}{OFF_INTERVAL};
  }

  YAMAHA_NP_getInputs($hash);

  unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
  {
    $hash->{helper}{AVAILABLE} = 1;
  }

  # Timeout for directPlay
  $attr{$name}{"searchAttempts"} = 15;

  $attr{$name}{".favoriteList"} = ""
                             ."aux1:aux1;"
                             ."aux2:aux2;"
                             ."airplay:airplay;"
                             ."cd:cd;"
                             ."digital1:digital1;"
                             ."digital2:digital2;"
                             ."netradio:netradio;"
                             ."server:server;"
                             ."spotify:spotify;"
                             ."DAB:DAB;"
                             ."FM:FM;"
                             ."usb:usb;"
                             ;
  YAMAHA_NP_favoriteList($name);

  # start the status update timer
  $hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));
  YAMAHA_NP_ResetTimer($hash,0);
}

sub YAMAHA_NP_Undefine
{
  my($hash, $name) = @_;

  # Stop the internal GetStatus-Loop and exit
  RemoveInternalTimer($hash);
}

sub YAMAHA_NP_Attr
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};

  if($attrName eq "disable")
  {
    if ($cmd eq "set")
    {
      $hash->{helper}{DISABLED} = $attrVal;
      if ($attrVal eq "0")
      {
        YAMAHA_NP_GetStatus($hash, 1);
      }
    }
    else
    {
      $hash->{helper}{DISABLED} = 0;
      YAMAHA_NP_GetStatus($hash, 1);
    }
  }
  elsif($attrName eq "timerVolume")
  {
    my $volumeStraightMin = ReadingsVal($name,".volumeStraightMin",0);
    my $volumeStraightMax = ReadingsVal($name,".volumeStraightMax",60);
    
    if ($cmd eq "set" && (($attrVal < $volumeStraightMin) || ($attrVal > $volumeStraightMax)))
    {
      return "$attrName must be between $volumeStraightMin and $volumeStraightMax";
    }
  }
  elsif($attrName eq "timerRepeat")
  {
    if ($cmd eq "set" && $attrVal !~ /^(once|every)$/)
    {
      return "Use 'once' or 'every'";
    }
  }
  elsif($attrName eq "timerHour")
  {
    if ($cmd eq "set" && (($attrVal < 0) || ($attrVal > 23)))
    {
      return "$attrName must be between 0 and 23";
    }
  }
  elsif($attrName eq "timerMin")
  {
    if ($cmd eq "set" && (($attrVal < 0) || ($attrVal > 59)))
    {
      return "$attrName must be between 0 and 59";
    }
  }
  elsif($attrName eq "searchAttempts")
  {
    if ($cmd eq "set" && (($attrVal < 15) || ($attrVal > 100)))
    {
      return "$attrName must be between 15 and 100";
    }
  }
  elsif(($attrName eq ".favoriteList") && defined($attrVal))
  {
    if ($cmd eq "set")
    {
      $attr{$name}{$attrName} = $attrVal; #need to set first!
    }
    YAMAHA_NP_favoriteList($name);
  }
  elsif(($attrName eq ".DABList") && defined($attrVal))
  {
    if ($cmd eq "set")
    {
      foreach (split(";", $attrVal))
      {
        my ($id, $sender) = split(":", $_, 2);
        next if (!defined $sender);
        next if ($id !~ m/.DAB_ID/);
        $hash->{READINGS}{$id}{VAL} = $sender;
        $hash->{READINGS}{$id}{TIME} = "-";
      }
    }
  }
  elsif(($attrName eq "directPlaySleepNetradio") && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 3) || ($attrVal > 30)))
    {
      return "$attrName must be between 3 and 30";
    }
  }
  elsif(($attrName eq "directPlaySleepServer") && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 2) || ($attrVal > 30)))
    {
      return "$attrName must be between 2 and 30";
    }
  }
  elsif(($attrName eq "maxPlayerListItems") && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 8) || ($attrVal > 999)))
    {
      return "$attrName must be between 8 and 999";
    }
  }
  elsif($attrName eq "autoUpdatePlayerlistReadings" && defined($attrName))
  {
	if($cmd eq "set" && (($attrVal < 0) || ($attrVal > 1)))
	{
	   return "$attrName must be 0 or 1"; 
	}
	else
	{
	  if($attrVal eq "0")
	  {
	    foreach (grep /playerListLvl.*$/,keys %{$hash->{READINGS}})
	    {
		  #delete level information
		  delete $hash->{READINGS}{$_};
	    }
	    # delete playerlist items
	    delete $hash->{READINGS}{$_} foreach (grep /listItem_...$/,keys %{$hash->{READINGS}});
	    delete $hash->{READINGS}{playerListMenuStatus};
	  }
	}
  }

  # Start/Stop Timer according to new disabled-Value
  YAMAHA_NP_ResetTimer($hash);
}

sub YAMAHA_NP_Notify
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  return "" if ($dev->{NAME} ne "global");

  my $events = deviceEvents($dev, AttrVal($name, "addStateEvent", 0));
  
  return undef if(!$events); # Some previous notify deleted the array.
  
  # Save DAB list on save or shutdown 
  if (grep /(SAVE|SHUTDOWN)/, @{$events})
  {
    $attr{$name}{".DABList"} = "";

    foreach (grep /^(.DAB_ID)/, keys %{$hash->{READINGS}})
    {
      $attr{$name}{".DABList"} .= ";".$_.":".$hash->{READINGS}{$_}{VAL};
    }
  }
  return undef;
}

sub YAMAHA_NP_GetStatus
{
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $power;

  # Local means a timer reset by the module itself
  $local = 0 unless(defined($local));

  return "" if((!defined($hash->{helper}{ADDRESS})) or (!defined($hash->{helper}{OFF_INTERVAL})) or (!defined($hash->{helper}{ON_INTERVAL})));

  my $device = $hash->{helper}{ADDRESS};

  # Get model and firmware information
  if(not defined($hash->{MODEL}))
  {
    YAMAHA_NP_getModel($hash);
    # Get network related information from the NP
    YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Network,Info:GetParam", "statusRequest", "networkInfo" , 0);
    YAMAHA_NP_SendCmd($hash, "GET:System,Config:GetParam"           , "statusRequest", "systemConfig", 0);
  }
  elsif((not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0))
  {
    # Get available inputs if not defined
    YAMAHA_NP_getInputs($hash);
  }
  else
  {
    if(not defined($hash->{READINGS}{timerVolume}))
    {
      # Timer readings available?
      YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Timer,Mode:GetParam" , "statusRequest", "getTimer"   , 0);
      YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Timer,Param:GetParam", "statusRequest", "timerStatus", 0);  
    }
    
    if(not defined($hash->{READINGS}{standbyMode}))
    {
      # Standby mode readings available?
      YAMAHA_NP_SendCmd($hash, "GET:System,Power_Control,Saving:GetParam", "statusRequest", "standbyMode", 0); 
    }
    
    # Basic status request
    YAMAHA_NP_SendCmd($hash, "GET:System,Basic_Status:GetParam", "statusRequest", "basicStatus", 0);
  }

  # Reset Timer for the next loop.
  YAMAHA_NP_ResetTimer($hash) unless($local == 1);  
}

sub YAMAHA_NP_favoriteList
{
  # Process favorites list
  # Format of favorite list:
  # .favoriteList = name:input:lvl1,lvl2,lvl3;name:input:lvl1,lvl2,lvl3; ...

  my ($name) = @_;
  my $hash = $defs{$name};
 
  # Put favorites attribute .favoriteList separated by ';' to an array
  my @favEntry = split(";",$attr{$name}{".favoriteList"});

  # Delete existing favorites
  delete $hash->{helper}{fav};

  # Parse favorites
  foreach my $entry (@favEntry)
  {
    next if (!$entry);
    # NAME:INPUT:[STREAM,...] (stream may be empty)
    my ($entryName, $entryInput, $entryStream) = split(":", $entry);
    next if (!$entryName || !$entryInput);
    $hash->{helper}{fav}{$entryName}{input}  = $entryInput;
    $hash->{helper}{fav}{$entryName}{stream} = $entryStream ? $entryStream : "";
  }
}

sub YAMAHA_NP_statTimeOut
{
  # timeout occured during operation. Some problems. Clear. 
  my ($para) = @_;
  my ($cmd, $name) = split(":", $para, 2);
  my $hash = $defs{$name};

  #Log 1,"General                      YAMAHA_NP_statTimeOut";
  $hash->{helper}{statReq}{$_} = 0 foreach (keys% {$hash->{helper}{statReq}});
}

sub YAMAHA_NP_directRestartTimer
{
  my ($name,$wait,$a,$inputTarget,$stream) = @_;
  my $hash = $defs{$name};

  RemoveInternalTimer("directPlay:".$name);
  InternalTimer(gettimeofday() + $wait, "YAMAHA_NP_directSet", "directPlay:".$name, 0);
  
  $hash->{helper}{directPlayQueue}{state}  = "selectInput";
  $hash->{helper}{directPlayQueue}{sleep}  = $wait;
  $hash->{helper}{directPlayQueue}{a}      = $a;
  $hash->{helper}{directPlayQueue}{input}  = $inputTarget;
  $hash->{helper}{directPlayQueue}{stream} = $stream;
}
                  
sub YAMAHA_NP_directSet
{
  my ($para) = @_;
  my ($cmd, $name) = split(":", $para, 2);
  my $hash = $defs{$name};

  #Log 1,"directSet, directPlay ". $hash->{helper}{directPlayQueue}{input}.":".$hash->{helper}{directPlayQueue}{stream};
  $hash->{helper}{directPlayQueue}{stream} = "noStream" if(not($hash->{helper}{directPlayQueue}{stream}));
  
  # Due to asyncronous timers possible race condition. Supress if already playing.
  if(ReadingsVal($name,"playerPlaybackInfo", "stop") ne "play")
  {
    YAMAHA_NP_Set($hash,"","directPlay",$hash->{helper}{directPlayQueue}{input}.":".$hash->{helper}{directPlayQueue}{stream});
  }  
}

sub YAMAHA_NP_Get
{
  my ($hash, @a) = @_;

  return "Argument missing." if(int(@a) < 2);

  my $what = $a[1];
  my $return; 
  
  if   ($what eq "reading"){
    if(exists($hash->{READINGS}{$a[2]}))
    {
      if(defined($hash->{READINGS}{$a[2]}))
      {
        return $hash->{READINGS}{$a[2]}{VAL};
      }
      else
      {
        return "No such reading: $what";
      }
    }
  }
  elsif($what eq "deviceInfo")
  {
    my $deviceInfo = join("\n", map {sprintf("%-15s: %-15s", $_, $hash->{helper}{dInfo}{$_})} sort keys %{$hash->{helper}{dInfo}});
	return "Device info:\n\n$deviceInfo";
  }
  elsif($what eq "favoriteList"  )
  {
    return "No favorites defined" if(!$hash->{helper}{fav});
    my $favoriteList = "Favorite list:\n\n"
                 ."name           :input      -> stream\n";
    foreach my $fav (sort keys%{$hash->{helper}{fav}})
    {
      $favoriteList .= sprintf("%-15s:%-10s -> %s\n",$fav
                                                ,$hash->{helper}{fav}{$fav}{input}
                                                ,$hash->{helper}{fav}{$fav}{stream});
    }
    return $favoriteList;
  }
  else
  {
    $return = "Unknown argument $what, choose one of"   
             ." deviceInfo:noArg"
             ." favoriteList:noArg"
             ." reading:".(join(",",(sort keys %{$hash->{READINGS}})));           
    return $return;
  }

}

sub YAMAHA_NP_Set
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    
    # Get model info in case not defined
    if(not defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
      YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Network,Info:GetParam", "statusRequest", "networkInfo" , 0);
      YAMAHA_NP_getModel($hash);
      YAMAHA_NP_SendCmd($hash, "GET:System,Config:GetParam"           , "statusRequest", "systemConfig", 0);
    }
    
    # Setting default values. Update from device during existing communication.
    my $volumeStraightMin = ReadingsVal($name,".volumeStraightMin",0);
    my $volumeStraightMax = ReadingsVal($name,".volumeStraightMax",60);
    
    if((!ReadingsVal($name,".volumeStraightMax","")) || (!ReadingsVal($name,".volumeStraightMin","")))
    {
      YAMAHA_NP_SendCmd($hash, "GET:System,Config:GetParam"           , "statusRequest", "systemConfig", 0);
    }

    # Get available inputs in case of an empty list
    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
      YAMAHA_NP_getInputs($hash);
    }
       
    my $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_NP_Param2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
    my $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_NP_Param2Fhem(lc($hash->{helper}{INPUTS}), 1) : "" ;
    
    return "No Argument given" if(!defined($a[1]));     
    
    my $what = $a[1];
    my $usage = "";
    
    # DAB available? Suffix D stands for DAB. "CRX-N560D"
    
    my $input = ReadingsVal($name,"input","");

    if (defined($hash->{MODEL}))
    {
      my $model = $hash->{MODEL};     
      my $favLst = join(",",sort keys%{$hash->{helper}{fav}});
      
      # Minimum set commands for simplified power-on
      $usage = "Unknown argument $what, choose one of"
              ." on:noArg"
              ." off:noArg" 
              ." favoritePlay:".$favLst
              ." directPlay";

      # Context-sensitive command availability        
      if (ReadingsVal($name,"power","") !~ m/(off|absent)/)
      {
        $usage .=" input:".$inputs_comma
      
                ." volumeStraight:slider,".$volumeStraightMin.",1,".$volumeStraightMax
                ." volume:slider,0,1,100"
                ." volumeUp:noArg"
                ." volumeDown:noArg"
                ." mute:on,off"
                
                ." statusRequest:basicStatus,mediaRendererDesc,playerStatus,standbyMode,systemConfig,timerStatus,tunerStatus"
                
                ." CDTray:noArg"
                ." clockUpdate:noArg"
                ." standbyMode:eco,normal"
                ." sleep:off,30min,60min,90min,120min"
                ." timerSet:noArg"
                ." timer:on,off"
                ." dimmer:1,2,3"
                ." favoriteDefine"
                ." favoriteDelete:".$favLst
                
                ." ";
        
        # Add additional set commands in case of netradio|usb|server|cd|DAB|FM
        if($input =~ m/^(netradio|usb|server|cd|DAB|FM)/)
        {
          # Process 'playerListLvl' and 'listItem_' readings and provide them for 'selStream' command
          # playerListLvl -> Player Menu Directory Level
          # listItem_     -> Item. May be container (directory) or item (file/audio stream)
          
          my @playerList;
          
          # Scan all readings and reformat the contents of
          # playerListLvlX -> lvlX_NAME and listItem_XXX -> XXX_NAME into an array
          # Limit to 25 chars
          foreach my $readings (keys %{$hash->{READINGS}})
          {
            push @playerList, "lvl$1"."_".substr($hash->{READINGS}{$readings}{VAL} ,0, 25) if($readings =~ m/^playerListLvl(.*)/);
            push @playerList, $2."_"     .substr($hash->{READINGS}{$readings}{VAL} ,0, 25) if($readings =~ m/(listItem_)(...)$/);
          }

          # Sort playerList first numeric items XXX_NAME -> lvlX_XXX -> ...
          # Replace not allowed characters
          @playerList = sort map{s/[ :;,'.]/_/g;$_;} grep/._..*$/,@playerList;

          # Sort CD tracks as 'Track_XX'
          if($input eq "cd")
          {
            push @playerList,(sort map { "Track_".sprintf("%02d",$_) } (1 .. ReadingsVal($name,"playerTotalTracks",0)));
          }
          
          # Add next, prev as set command
          push @playerList,("next","prev");
          
          # Add tuneUp/tuneDown in case of tuner input
          if($input =~ m/^(DAB|FM)/)
          {
            push @playerList, ("tuneUp","tuneDown");
          }
          
          # Add selectStream as set command. In addition '---' as dummy for web interface.
          # Otherwise the first item cannot be executed
          
          $usage .="selectStream:".join(",",("---",(sort @playerList)));
          
          # Add direct FM frequency input in case of FM tuner band
          if(ReadingsVal($name,"tunerBand","") eq "FM")
          {
            $usage .= " tunerFMFrequency"
          }
          
          $usage .= " player:play,stop,pause,next,prev";

          if ($input =~ m/^(usb|server|cd)/)
          {
            $usage .= " playMode:shuffleAll,shuffleOff,repeatOff,repeatOne,repeatAll";
          }
        }
        
        # In case of DAB capable NP replace tuner by DAB and FM for direct command
        # Otherwise limit to tuner -> FM
        if  ($model eq "CRX-N560D")
        {
          $usage =~ s/,tuner/,DAB,FM/; # direct select tuner band
        }
        else
        {
          $usage =~ s/,tuner/,FM/;     # direct select tuner band
        }
      }

      $usage .=  " ";

      #Log 1, "$usage";

      Log3 $name, 5, "Model: $model.";
    }    
    
    Log3 $name, 5, "YAMAHA_NP ($name) - set ".join(" ", @a);
    
    #Simplified commands
    if($what eq "?"){ return $usage}
    
    if($what eq "favoritePlay")
    {
      if(!defined $a[2] || !defined $hash->{helper}{fav}{$a[2]})
      {
        return "Entry $a[2] unknown, check favoriteList."; 
      }
      
      $what = "directPlay";
      $a[2] = $hash->{helper}{fav}{$a[2]}{input}.":".$hash->{helper}{fav}{$a[2]}{stream};
      
    }
    elsif($what eq "favoriteDefine")
    {
      return "Specify favorite" if(!$a[2]);
      
      # Favorites are defined as NAME:INPUT:[STREAM_LVL1,STREAM_LVL2,...]
      my ($favName, $favInput, $favSelect) = split(":", $a[2]);
      
      if(!$favInput)
      {
        return "No input defined. Use <name>:<input>:[stream]. Provide minimum name and input.";
      }
      elsif($favInput eq "current")
      {
        my $input = ReadingsVal($name, "input", "");
        my $stream = "$favName:$input:";

        if ($input eq "DAB")
        {
          $stream .= ReadingsVal($name, "tunerStation", "");
        }
        elsif ($input eq "FM")
        {
          $stream .= ReadingsVal($name, "tunerFrequency", "");
          $stream =~ s/ MHZ//;
        }
        #elsif ($input =~ m/^(usb)$/)
        #{
        #  
        #}
        else
        {
          foreach (sort grep /playerListLvl/, keys %{$hash->{READINGS}})
          {
            $stream .= $hash->{READINGS}{$_}{VAL}."," if ($_ ne "playerListLvl1");# level 1 is not necessary
          }
          $stream .= ReadingsVal($name, "playerPlayArtist", "");
        }
       
        $stream =~ s/ /./g; #replace spaces
        
        $attr{$name}{".favoriteList"} .= ";" .$stream; # Append to the .favoriteList attribute
        YAMAHA_NP_favoriteList($name);
        return;
      }
      else
      {
        $attr{$name}{".favoriteList"} .= ";$a[2]"; # Append to the .favoriteList attribute
        YAMAHA_NP_favoriteList($name);
        return;
      }
    }
    elsif($what eq "favoriteDelete")
    {
      if (   defined $a[2] 
          && defined $hash->{helper}{fav}
          && defined $hash->{helper}{fav}{$a[2]})
      {
        delete $hash->{helper}{fav}{$a[2]};
      }
      
      # Reset favorites attribute
      $attr{$name}{".favoriteList"} = "";

      foreach my $favorite (keys %{$hash->{helper}{fav}})
      {
        next if (!$favorite);
        $attr{$name}{".favoriteList"} .= $favorite.":".$hash->{helper}{fav}{$favorite}{input}.":".$hash->{helper}{fav}{$favorite}{stream}.";";
      }
      return;
    }
    
    if($what eq "directPlay")
    {
      # Format INPUT:STREAM_LVL1,STREAM_LVL2,...

      delete $hash->{helper}{directPlayQueue};
      
      return "Please enter stream -> INPUT:STREAM_LVL1,STREAM_LVL2,..." if(!$a[2]);

      if (!defined $hash->{helper}{directPlayQueueTry})
      {
        $hash->{helper}{directPlayQueueTry} = 1 ; # 1st try
        readingsSingleUpdate($hash, "directPlay", "started", 1);
      }
      else
      {
        # Increment and limit number to searchAttempts
        $hash->{helper}{directPlayQueueTry}++;
        
        if ($hash->{helper}{directPlayQueueTry} > AttrVal($name,"searchAttempts", 15))
        {
          # Timeout
          YAMAHA_NP_directPlayFinish($hash, "abort-timeout");
          return;
        }
      }
      
      # INPUT:STREAM_LVL1,STREAM_LVL2,...
      my ($inputTarget, $stream) = split(":",$a[2],2); 
      
      $inputTarget = lc($inputTarget);
      
      # Set default stream name in case none provided
      $stream = "noStream" if(not $stream);
      
      # Check if device unpowered
      if (ReadingsVal($name, "state", 0) ne "on")
      {
        $what = "on";
        $hash->{helper}{directPlayQueue}{sleep}  = 2;
        $hash->{helper}{directPlayQueue}{state}  = "directPlay";
        $hash->{helper}{directPlayQueue}{a}      = $a[2];
        $hash->{helper}{directPlayQueue}{input}  = $inputTarget;
        $hash->{helper}{directPlayQueue}{stream} = $stream;
      }
      else
      {
        
        my $input = ReadingsVal($name, "input", "");
        
        #Log 1, "InputTarget: $inputTarget";
        #Log 1, "Input: $input";
        
        if ($inputTarget eq $input)
        {
          # Force Playerlist status update.
          YAMAHA_NP_SendCmd($hash, "GET:Player,List_Info:GetParam", "statusRequest", "playerListGetList", 0);
          
          if($inputTarget =~ m/(aux|digital|spotify|airplay)/)
          {
            # These inputs don't have streams. Finish.
            YAMAHA_NP_directPlayFinish($hash);
            return;
          }
          elsif($inputTarget =~ m/(DAB|FM|cd)/)                  
          {
            # Single level selection Stream CD:Track_01 etc.
            $stream = 1 if (!defined $stream);
            
            if($inputTarget eq "cd")
            {
              # Remove header
              $stream =~ s/^Track_//;
              
              # Get track # and total tracks information
              my ($totalTracks, $currentTrack) =
                 (ReadingsVal($name,"playerTotalTracks", 0),
                  ReadingsVal($name,"playerPlayTrackNb", 0)
                 );
              
              if (  ($stream !~ m/\d+/)         # non numeric
                  ||($stream < 1)               # too small
                  ||($stream > $totalTracks )   # too big
                  )
              {
                YAMAHA_NP_directPlayFinish($hash, "abort-not found");
                return ;
              }
              elsif ($currentTrack == $stream)
              {
                # match: we are done
                YAMAHA_NP_directPlayFinish($hash);
                return ;
              }
              $a[2] = "Track_".$stream; # select stream
            }
            else
            {
              # DAB or FM
              if ( (ReadingsVal($name,"tunerPreset"   ,"")
                   .ReadingsVal($name,"tunerFrequency","")) =~ m/$stream/)
              {
                # Match. No further action. Finish.
                YAMAHA_NP_directPlayFinish($hash);
                return;
              }

              if($inputTarget eq "FM")
              {
                $what = "tunerFMFrequency";
                $a[2] = $stream;
              }
              else
              {
                # $inputTarget eq "DAB"
                my $found = 0;
                
                foreach my $listItemReading (sort grep /^(listItem_)/,keys %{$hash->{READINGS}})
                {
                  my $listItemReadingValue = $hash->{READINGS}{$listItemReading}{VAL};
                  
                  if($listItemReadingValue =~ m/$stream/)
                  {
                    $a[2] = substr($listItemReading, 9, 3);
                    $found = 1;
                    last;
                  }
                } 
                if($found == 0)
                { 
                  YAMAHA_NP_directPlayFinish($hash,"abort-not found");
                  return ;
                }
              }
            }
            
            $what = "selectStream" if ($what eq "directPlay");
            $hash->{helper}{directPlayQueue}{sleep} = 1;
          }
          # Server, Netradio
          elsif(ReadingsVal($name, "playerListMenuStatus", "-") ne "Ready")
          {
            # Depending on input and server/network speed the duration is unknown
            # Customization of polling intervall for Server (LAN) and Netradio (vTuner)
            
            my $sleep = 3; # default
            
            if (lc($inputTarget) eq "server")
            {
              $sleep = AttrVal($name,"directPlaySleepServer", 2);
            }
            elsif(lc($inputTarget) eq "netradio")
            {
              $sleep = AttrVal($name,"directPlaySleepNetradio", 3);
            }
            # take another chance: data was not complete
            YAMAHA_NP_directRestartTimer($name, $sleep, $a[2], $inputTarget, $stream);
            return;
          }
		  
          # Streams with multilevel selection e.g. server, netradio
		  	  
          else	
          { 
            
            my $level = 1;
            my @desiredList = split(",", $stream);
            my $desiredListLast = scalar (@desiredList);


desiredListNloop:

            foreach my $desiredListN(@desiredList)
            {
              $level++;
              my $currentLevel = ReadingsVal($name,"playerListLvl$level", undef);
              
              if (!defined $currentLevel)
              {
                if ($level > $desiredListLast)
                {
                  #last level - might be an item, not a container
                  #playerPlaySong i_04 FelizNavidad.mp3
        
                  my $currentStream = $inputTarget eq "netradio"
                                   ? ReadingsVal($name, "playerPlayArtist", "")
                                   : ReadingsVal($name, "playerPlaySong"  , "");
                  
                  if ($currentStream =~ m/$desiredListN/)
                  {
                    YAMAHA_NP_directPlayFinish($hash);# we are done!!
                    return ; 
                  }
                  
                  # Depending on input and server/network speed the duration is unknown
                  # Customization of polling intervall for Server (LAN) and Netradio (vTuner)
                  
                  my $sleep = 2; # default        
                  
                  if (lc($inputTarget) eq "server")
                  {
                    $sleep = AttrVal($name,"directPlaySleepServer", 2);
                  }
                  elsif(lc($inputTarget) eq "netradio")
                  {
                    $sleep = AttrVal($name,"directPlaySleepNetradio", 3);
                  }
                  
                  $hash->{helper}{directPlayQueue}{sleep} = $sleep;                  
                }
                
                my $found = 0;

                foreach (grep /listItem_...$/,keys %{$hash->{READINGS}})
                {
                  if ($hash->{READINGS}{$_}{VAL} =~ m/$desiredListN/)
                  {
                    $a[2] = substr($_, 9);
                    $found = 1; $level = 0; # force next step
                    last desiredListNloop;
                  }
                }

                if($desiredListN =~ m/^[0-9]{3}$/ && defined $hash->{READINGS}{"listItem_".$desiredListN})
                {
                  # go by number
                  my $desiredSong = ReadingsVal($name,"listItem_".$desiredListN, undef);
                  my $playerSong = ReadingsVal($name,"playerPlaySong",undef);
                  
                  if (!defined $desiredSong)
                  {# no list item - problem. abort
                    YAMAHA_NP_directPlayFinish($hash, "abort-not found");    
                    return;                    
                  }
                  elsif (!defined $playerSong)
                  {
                    # Depending on input and server/network speed the duration is unknown
                    # Customization of polling intervall for Server (LAN) and Netradio (vTuner)
                    
                    my $sleep = 2; # default        
                    
                    if (lc($inputTarget) eq "server")
                    {
                      $sleep = AttrVal($name,"directPlaySleepServer", 2);
                    }
                    elsif(lc($inputTarget) eq "netradio")
                    {
                      $sleep = AttrVal($name,"directPlaySleepNetradio", 3);
                    }
                    
                    # not yet playing?
                    YAMAHA_NP_directRestartTimer($name, $sleep, $a[2], $inputTarget, $stream); # take another chance: data was not complete
                    return;
                  }
                  elsif ($desiredSong =~ m/$playerSong/)
                  {
                    YAMAHA_NP_directPlayFinish($hash);    
                    return;                    
                  }

                  $a[2] = $desiredListN;
                  $level  = 0;
                  last desiredListNloop;
                }
                elsif ($hash->{helper}{playlist}{state} ne "complete")
                {
                  my $sleep = 2; # default        
                    
                  if (lc($inputTarget) eq "server")
                  {
                    $sleep = AttrVal($name, "directPlaySleepServer", 2);
                  }
                  elsif(lc($inputTarget) eq "netradio")
                  {
                    $sleep = AttrVal($name, "directPlaySleepNetradio", 3);
                  }                  
                  YAMAHA_NP_directRestartTimer($name, $sleep, $a[2], $inputTarget, $stream);# take another chance: data was not complete
                }
                else
                {
                  YAMAHA_NP_directPlayFinish($hash, "abort-not found");                 
                } #no chance
                return;
              }
              elsif ($currentLevel !~ m/$desiredListN/)
              { 
                # current level does not match   
                $a[2] = "lvl".($level - 1)."_";
                $level = 0; # force next step
                last;
              }
              next;
            }
            if ($level > $desiredListLast)
            {
              #$level is one less then desiredListLast!
              YAMAHA_NP_directPlayFinish($hash, "abort-not found");
              return;
            }
            $what = "selectStream";
          }
          $hash->{helper}{directPlayQueue}{state}  = "selectInput";
          $hash->{helper}{directPlayQueue}{sleep}  = 3; # default
          
          # Depending on input and server/network speed the duration is unknown
          # Customization of polling intervall for Server (LAN) and Netradio (vTuner)
                  
          if (lc($inputTarget) eq "server")
          {
            $hash->{helper}{directPlayQueue}{sleep} = AttrVal($name, "directPlaySleepServer", 2);
          }
          elsif(lc($inputTarget) eq "netradio")
          {
            $hash->{helper}{directPlayQueue}{sleep} = AttrVal($name, "directPlaySleepNetradio", 3);
          }
          
          $hash->{helper}{directPlayQueue}{a}      = $a[2];
          $hash->{helper}{directPlayQueue}{input}  = $inputTarget;
          $hash->{helper}{directPlayQueue}{stream} = $stream;
        }
        else
        {
          if ($inputTarget !~ m/(aux|digital|spotify|airplay)/)
          {
            # stream set necessary?
            delete $hash->{helper}{directPlayQueue};
            $hash->{helper}{directPlayQueue}{state}  = "selectInput";
            
            $hash->{helper}{directPlayQueue}{sleep}  = 3; # default
            # Depending on input and server/network speed the duration is unknown
            # Customization of polling intervall for Server (LAN) and Netradio (vTuner)
                    
            if (lc($inputTarget) eq "server")
            {
              $hash->{helper}{directPlayQueue}{sleep} = AttrVal($name, "directPlaySleepServer", 2);
            }
            elsif(lc($inputTarget) eq "netradio")
            {
              $hash->{helper}{directPlayQueue}{sleep} = AttrVal($name, "directPlaySleepNetradio", 3);
            }
            
            $hash->{helper}{directPlayQueue}{a}      = $a[2];
            $hash->{helper}{directPlayQueue}{input}  = $inputTarget;
            $hash->{helper}{directPlayQueue}{stream} = $stream;
          }
          $what = "input";
          $a[2] = $inputTarget;
          YAMAHA_NP_directRestartTimer($name, 2, $a[2], $inputTarget, $stream);
        }
      }
    }
    else
    { 
      # Remove directPlay helper 
      delete $hash->{helper}{directPlayQueue};
      delete $hash->{helper}{directPlayQueueTry};
      RemoveInternalTimer("statTimeOut:".$hash->{NAME});
    }

     #Log 1,"General process $what ++++$a[2] --------->$hash->{helper}{directPlayQueue}{a}";
      
    if($what eq "selectStream")
    {
      readingsSingleUpdate($hash, "selectStream", "select", 1);            
      my $input = ReadingsVal($name,"input","");
      
      if($input eq "---")
      {
        # dummy entry for web interface
        return;
      }
      elsif($input =~ m/^(cd|netradio|server|usb)/)
      {
        # player stream supported
        if   ($a[2] =~ m/(next|prev)/)
        {
          $what = "player";
        }
        elsif($a[2] =~ m/^Track_(.*)/)
        {
          # cd counts tracks 
          YAMAHA_NP_SendCmd($hash,"PUT:Player,Play_Control,Track_Number:$1", $what, $a[2], 0); # cd only
          readingsSingleUpdate($hash, "audioSource", ReadingsVal($name, "input", "") . " (reading status...)", 1);   
        }
        elsif($a[2] =~ m/^lvl(.*?)_/)
        {
          my ($targetLevel, $currentLevel) = ($1, split(":",$hash->{helper}{playlist}{mnCur}));
          
          return "Level must bei between $currentLevel and 1" if($targetLevel < 1 || $targetLevel > $currentLevel);
          
          return if ($targetLevel eq $currentLevel); # nothing to do
          
          $hash->{helper}{playlist}{desiredDirectoryLevel} = $targetLevel;
          
          YAMAHA_NP_SendCmd($hash, "PUT:Player,List_Control,Cursor:Return", "playerListCursorReturn", $targetLevel,0);          
        }
        elsif($a[2] eq "---")
        {
          # Do nothing. Dummy entry for the web interface.
          return;
        }
        else
        {
          $a[2] = substr($a[2],0,3);
          return "Argument must be numeric and >= 1. Entered is $a[2]" if($a[2] !~ /^\d{1,3}$/ || $a[2] < 1);
          my $selection = (($a[2]-1)%8)+1;
          
          $hash->{helper}{playlist}{selection} = $selection;# remember: more to do. 
          YAMAHA_NP_SendCmd($hash, "PUT:Player,List_Control,Jump_Line:".$a[2], $what, "jump_$a[2]_$selection", 0);
          readingsSingleUpdate($hash, "audioSource", ReadingsVal($name, "input", "") . " (reading status...)", 1); 
        }
      }
      elsif($input eq "DAB" || $input eq "FM")
      {
        if ($a[2] =~ m/(tuneUp|tuneDown|next|prev)/)
        {
          $what = "tuner";
        }
        else
        {
          $what = "tunerPreset".ReadingsVal($name,"tunerBand","");# DAB or FM
          $a[2] = substr($a[2], 0, 3);
          return "Argument must be numeric and >= 1. Entered is $a[2]" if($a[2] !~ /^\d{1,3}$/ || $a[2] < 1);
        }
      }
      elsif($input =~ m/^(digital|aux|airplay|spotify)/)
      {
        # Direct input ... no further stream required
      }
    }

    # Processing of SET commands.
    
    if($what =~ m/^(on|off)/)
    {
      # Device Power ON/OFF
      my $arg;
      
      if($what eq "on")
      {
        $what = "on";
        $arg = "On";        
      }
      elsif($what eq "off")
      {
        $what = "off";
        $arg = "Standby";
      }
      else
      {
        return "Invalid argument $a[2] - Select on or off";
      }
      YAMAHA_NP_SendCmd($hash, "PUT:System,Power_Control,Power:$arg", $what, $arg, 0);
    }
    elsif($what eq "input")
    {
      if(defined($a[2]))
      {
        if(not $inputs_piped eq "")
        {
          if(  $a[2] =~ /^($inputs_piped)$/)
          {
            my $command = YAMAHA_NP_getParamName($hash, $a[2], $hash->{helper}{INPUTS});
            
            if(defined($command) and length($command) > 0)
            {
              YAMAHA_NP_SendCmd($hash, "PUT:System,Input,Input_Sel:$command", $what, $a[2], 0);
            }
            else
            {
              return "Invalid input: ".$a[2];
            } 
          }
          elsif($a[2] =~ m/^(FM|DAB)$/)
          {
            my $command = YAMAHA_NP_getParamName($hash, "tuner", $hash->{helper}{INPUTS});               
            YAMAHA_NP_SendCmd($hash, "PUT:System,Input,Input_Sel:$command", $what, $a[2], 0);
          }
          else
          {
            return $usage;
          }
        }
        else
        {
          return "No inputs available. Please try statusRequest.";
        }
      }
      else
      {
        return $inputs_piped eq "" ? "No inputs available. Please try statusRequest." : "No input parameter given.";
      }
    }
    elsif($what eq "mute")
    {
      # MUTE
      return "Power on the device first." if($hash->{READINGS}{power}{VAL} ne "on");
      
  	  if(defined($a[2]))
      {
        if($a[2] =~ /^(on|off)$/)
  		  {
          YAMAHA_NP_SendCmd($hash, "PUT:System,Volume,Mute:".ucfirst($a[2]), $what, ucfirst($a[2]), 0);
        }          
        else
        {
            return $usage;
        }   
      }        
    }
    elsif($what eq "dimmer")
    {
      # DISPLAY DIMMER
      if($a[2] >= 1 and $a[2] <= 3)
      {
        YAMAHA_NP_SendCmd($hash, "PUT:System,Misc,Display,FL_Dimmer:$a[2]", $what, $a[2], 0);
      }
      else{
        return "Dimmer value must be 1 .. 3";
      }
    }
	#
	# VolumeStraight is device specific e.g. 0...60, Volume 0...100, VolumeUp/Down one step
	#
    elsif($what =~ /^(volumeStraight|volume|volumeUp|volumeDown)$/)
    {
      return "Power on the device first." if($hash->{READINGS}{power}{VAL} ne "on");

      my $target_volume;
      my $minVolume = ReadingsVal($name,".volumeStraightMin",0);
      my $maxVolume = ReadingsVal($name,".volumeStraightMax",60);      

      if   ($what eq "volumeDown")
      {
          $target_volume = $hash->{READINGS}{volumeStraight}{VAL} - 1;
      }
      elsif($what eq "volumeUp")
      {
          $target_volume = $hash->{READINGS}{volumeStraight}{VAL} + 1;		  
      }
      else
      {
        if   ($what eq "volume")
        {
          if($a[2] >= 0 and $a[2] <= 100)
          {
            $target_volume = YAMAHA_NP_volume_rel2abs($hash, $a[2]);
          }
          else
          {
            return "Volume must be in the range 1...100."; 
          }
        }
        elsif($what eq "volumeStraight")
        {
          if($a[2] >= $minVolume and $a[2] <= $maxVolume)
          {
            $target_volume = $a[2];          
          }
          else
          {
            return "Volume must be in the range $minVolume...$maxVolume.";
          }
        }
        $hash->{helper}{targetVolume} = $target_volume;# final destination
        
        if(AttrVal($name, "smoothVolumeChange", "1") eq "1" )
        {
          if   ($target_volume <  $hash->{READINGS}{volumeStraight}{VAL})
          {
            $target_volume = $hash->{READINGS}{volumeStraight}{VAL} - 1;  
          }
          elsif($target_volume >  $hash->{READINGS}{volumeStraight}{VAL})
          {
            $target_volume = $hash->{READINGS}{volumeStraight}{VAL} + 1;  
          }
          elsif($target_volume eq $hash->{READINGS}{volumeStraight}{VAL})
          {
            $target_volume = $hash->{READINGS}{volumeStraight}{VAL};  
          }
        }
      }
      $hash->{helper}{volumeChangeDir} = ($hash->{helper}{targetVolume} < $target_volume)? "DOWN" 
                                       :(($hash->{helper}{targetVolume} > $target_volume)? "UP"
                                       :                                                   "EQUAL");
      YAMAHA_NP_SendCmd($hash, "PUT:System,Volume,Lvl:$target_volume", "volume", $target_volume, 0); 
      
      Log3 $name, 4, "YAMAHA_NP ($name) - new target volume: $hash->{helper}{targetVolume}";
    }
    elsif($what eq "sleep")
    {
      if($a[2] eq "off")
      {
        YAMAHA_NP_SendCmd($hash, "PUT:System,Power_Control,Sleep:Off", $what, $a[2], 0);
      }
      elsif($a[2] =~ /^(30min|60min|90min|120min)$/)
      {
        if($a[2] =~ /(.+)min/)
        {
		      YAMAHA_NP_SendCmd($hash, "PUT:System,Power_Control,Sleep:$1 min", $what, $a[2], 0);
		    }
	    }      
      else
      {
        return $usage;
      } 
    }
    elsif($what eq "tuner")
    {
      # TUNER
      if   ($a[2] eq "next")
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Preset,Preset_Sel:Next", $what, $a[2], 0);
      }
      elsif($a[2] eq "prev")
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Preset,Preset_Sel:Prev", $what, $a[2], 0);
      }
      elsif($a[2] eq "tuneUp")
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Service:Next"          , $what, $a[2], 0);
      }
      elsif($a[2] eq "tuneDown")
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Service:Prev"          , $what, $a[2], 0);
      }
      elsif($a[2] eq "bandDAB")
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Band:DAB"              , $what, $a[2], 0);
      }
      elsif($a[2] eq "bandFM")
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Band:FM"               , $what, $a[2], 0);
      }  
      else
      {
        return $usage;
      }
    }
    elsif($what eq "player")
    {
      # Player
      if(   $a[2] =~ /^(play|pause|stop|next|prev|prevCD)$/)
      {
        my $postCmd = ($input eq "cd" && $a[2] eq "prev") ? "prevCD" : $a[2]; # need prev twice for CD
        YAMAHA_NP_SendCmd($hash,"PUT:Player,Play_Control,Playback:".ucfirst($a[2]), $what, $postCmd, 0);
      }      
      else
      {
		    return $usage;
      }
    }
    elsif($what eq "playMode")
    {
      # Playermode
      my $sh = ReadingsVal($name,"playerShuffle",""); # on/off
      my $rp = ReadingsVal($name,"playerRepeat" ,""); # off/one/all     
        
      # Shuffle toggles between ON/OFF      
      if    (  (($sh eq "off") && $a[2] eq "shuffleAll"  )
             ||(($sh eq "on")  && $a[2] eq "shuffleOff"))
      {
        YAMAHA_NP_SendCmd($hash,"PUT:Player,Play_Control,Play_Mode,Shuffle:Toggle", $what, $a[2], 0);
      }

      # Repeat Mode toggles between OFF/ONE/ALL      
      elsif(    (($rp eq "off") && ($a[2] eq "repeatOne" || $a[2] eq "repeatAll"))
             || (($rp eq "one") && ($a[2] eq "repeatOff" || $a[2] eq "repeatAll"))
             || (($rp eq "all") && ($a[2] eq "repeatOff" || $a[2] eq "repeatOne"))
           )
      {
        $hash->{helper}{playerRepeatModeTarget} = $a[2];
        YAMAHA_NP_SendCmd($hash,"PUT:Player,Play_Control,Play_Mode,Repeat:Toggle", $what, $a[2], 0);
      }           
      else
      {        
        return $usage;
      }
    }
    elsif($what eq "playerListSelectLine")
    {
      # PlayerListSelectLine
      if($a[2] ne "")
      {
        $a[2] = substr($a[2],0,2);
        if($a[2] =~ /^\d\d+$/ and $a[2] >= 1)
        {
          $a[2] = int($a[2]);
          YAMAHA_NP_SendCmd($hash,"PUT:Player,List_Control,Direct_Sel:Line_$a[2]", $what, $a[2], 0);
        }
        else
        {
          return "Argument must be numeric and >= 1.";
        }
      }
      else
      {
        return "No argument given.";
      }
    }
    elsif($what eq "standbyMode")
    {
      # Standby Mode
      if(($a[2] eq "eco") or ($a[2] eq "normal"))
      {
        YAMAHA_NP_SendCmd($hash, "PUT:System,Power_Control,Saving:".ucfirst($a[2]), $what, $a[2], 0);
      }      
      else{
        return $usage;
      }
    }
    elsif($what eq "CDTray")
    {
      # Toggle CD Tray
      YAMAHA_NP_SendCmd($hash, "PUT:System,Misc,Tray:Open/Close", $what, "Open/Close", 0);
    }
    elsif($what eq "clockUpdate")
    {  # Clock Update
      my $clockUpdateCurrentTime = Time::Piece->new();
      YAMAHA_NP_SendCmd($hash, "PUT:System,Misc,Clock,Param:".($clockUpdateCurrentTime->strftime('%Y:%m:%d:%H:%M:%S')), $what, ($clockUpdateCurrentTime->strftime('%Y:%m:%d:%H:%M:%S')), 0);
    }
    elsif($what eq "statusRequest")
    { 
      # Status Request
      if(   $a[2] eq "systemConfig")
      {
        YAMAHA_NP_SendCmd($hash, "GET:System,Config:GetParam"              , $what, $a[2], 0);
      }
      elsif($a[2] eq "playerStatus")
      {
        YAMAHA_NP_SendCmd($hash, "GET:Player,Play_Info:GetParam"           , $what, $a[2], 0);
      }
      elsif($a[2] eq "tunerStatus")
      {
        YAMAHA_NP_SendCmd($hash, "GET:Tuner,Play_Info:GetParam"            , $what, $a[2], 0);
      }
      elsif($a[2] eq "basicStatus")
      {
        YAMAHA_NP_SendCmd($hash, "GET:System,Basic_Status:GetParam"        , $what, $a[2], 0);
      }
      elsif($a[2] eq "timerStatus")
      {
        YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Timer,Mode:GetParam"     , $what, "getTimer", 0);
        YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Timer,Param:GetParam"    , $what, $a[2], 0);
      }
      elsif($a[2] eq "networkInfo")
      {
        YAMAHA_NP_SendCmd($hash, "GET:System,Misc,Network,Info:GetParam"   , $what, $a[2], 0);
      }
      elsif($a[2] eq "standbyMode")
      {
        YAMAHA_NP_SendCmd($hash, "GET:System,Power_Control,Saving:GetParam", $what, $a[2], 0);
      }
      elsif($a[2] eq "mediaRendererDesc")
      {
        YAMAHA_NP_getMediaRendererDesc($hash);
      }
      else
      {
        return $usage;
      }
    }
    elsif($what eq "timer")
    {
      # Timer
      if($a[2] eq "on")
      {
        # Check if standbyMode == 'Normal'
        if($hash->{READINGS}{standbyMode}{VAL} eq "normal")
        {
          YAMAHA_NP_SendCmd($hash, "PUT:System,Misc,Timer,Mode:".ucfirst($a[2]), $what, $a[2], 0);        
        }
        else
        {
          return "Set 'standbyMode normal' first.";
        }
      }
      elsif($a[2] eq "off")
      {
        YAMAHA_NP_SendCmd($hash, "PUT:System,Misc,Timer,Mode:".ucfirst($a[2]), $what, $a[2], 0);
      }
      else
      {
          return $usage;
      }
    }
    elsif($what eq "timerVolume")
    {
      # TimerVolume
      # if lower than minimum VOLUMESTRAIGHTMIN or higher than max VOLUMESTRAIGHTMAX set target volume to the corresponding limits
      if($a[2] >=  $hash->{helper}{VOLUMESTRAIGHTMIN} and $a[2] <= $hash->{helper}{VOLUMESTRAIGHTMAX})
      {
        $hash->{helper}{timerVolume} = $a[2];
      }
      else
      {
        return "Please use straight device volume range :".$hash->{helper}{VOLUMESTRAIGHTMIN}."...".$hash->{helper}{VOLUMESTRAIGHTMAX}.".";
      }
    }
    elsif($what eq "timerSet")
    {
      # TimerSet
      my ($timerHour, $timerMinute, $timerRepeat, $timerVolume) = 
                             ( AttrVal($name,"timerHour"  ,undef)
                              ,AttrVal($name,"timerMinute",undef)
                              ,AttrVal($name,"timerRepeat",undef)
                              ,AttrVal($name,"timerVolume",undef)
                             );
      if(    defined($timerHour) 
         and defined($timerMinute) 
         and defined($timerRepeat) 
         and defined($timerVolume))
      {
         # Configure Timer according to provided parameters
        YAMAHA_NP_SendCmd($hash, "PUT:System,Misc,Timer,Param:"
                                ."<Start_Time>".sprintf("%02d", $timerHour).":".sprintf("%02d", $timerMinute)."</Start_Time>"
                                ."<Volume>$timerVolume</Volume>"
                                ."<Repeat>$timerRepeat</Repeat>", $what, $a[2], 0);
      }
      else
      {
        return "Please, define attributes timerHour, timerMinute, timerRepeat and timerVolume first.";
      }
    }
    elsif($what =~ m/^tunerPreset(DAB|FM)/)
    {
      # Tuner Preset DAB/FM
      if($a[2] >= 1 and $a[2] <= 30)
      {
        # DAB only for$hash->{MODEL} eq "CRX-N560D"
        $hash->{helper}{tuner}{station}   = "";# need to delete here to prevent station naming
        $hash->{helper}{tuner}{stationID} = "";
        YAMAHA_NP_SendCmd($hash,"PUT:Tuner,Play_Control,Preset,$1,Preset_Sel:".$a[2], "tunerPreset", $a[2], 0);
      }
      else
      {
        return $usage;
      }
    }
    elsif($what eq "tunerFMFrequency")
    {
      # Tuner FM Frequency
      if(length($a[2]) <= 6 and length($a[2]) >= 5)
      {  # Check the string length (x)xx.xx
        if ( $a[2] =~ /^[0-9,.E]+$/ )
        {              # Check if value is numeric
          if(substr($a[2], -3, 1) eq '.')
          {          # Check for decimal point
             if( $a[2] >= 87.50 and $a[2] <= 108.00)
             {   # Check if within the value range
              my $lastDigit = substr($a[2], -1, 1);
               if(($lastDigit eq "0") or ($lastDigit eq "5"))
               {
                 my $frequency = $a[2];
                 $frequency =~ s/\.//; 			# Remove decimal point
                 YAMAHA_NP_SendCmd($hash, "PUT:Tuner,Play_Control,Tuning,FM,Freq:$frequency", $what, $a[2], 0);
               }
               else
               {
                 return "Last digit must be '0' or '5'";
               }
             }
             else
             {
               return "Frequency value must be in the range 87.50 ... 108.00 of the format (x)xx.xx";	
             }			
          }
          else
          {
        	  return "Missing decimal point. Accepted format (x)xx.xx";            
          }
        }
        else
        {
          return "Frequency value must be numeric in the range 87.50 ... 108.00 of the format (x)xx.xx";
        }
      }
      else
      {
        return "Frequency length must be 5 or 6 characters e.g. 89.50 or 108.00";
      }
    }
    elsif($what eq "selectStream")
    {
      #dummy
    }
    else
    {
      return $usage;
    }
}

sub YAMAHA_NP_SendCmd
{
  # Pre-process the HTTP request.
  my ($hash,$di,$cmd,$arg,$blocking) = @_;
  my ($c,$x,$d) = split(":",$di, 3);
  my @xa = split(",",$x);
  
  my $data = "<YAMAHA_AV cmd=\"$c\"><".join("><",@xa).">$d</".join("></",reverse @xa)."></YAMAHA_AV>";
  
  if ($cmd eq "statusRequest")
  {
    # avoid multiple status request
    return if ($hash->{helper}{statReq}{$arg}); # we are already waiting for an answer
    $hash->{helper}{statReq}{$arg} = 1;
    RemoveInternalTimer("statTimeOut:".$hash->{NAME});
    InternalTimer(gettimeofday() + 1, "YAMAHA_NP_statTimeOut", "statTimeOut:".$hash->{NAME}, 0);
  }
  YAMAHA_NP_SendCommand($hash,$data,$cmd,$arg,$blocking);
}

sub YAMAHA_NP_SendCommand
{
  # sends a command to the NP via HTTP
  my ($hash,$data,$cmd,$arg,$blocking) = @_;
  my $name = $hash->{NAME};
  my $address = $hash->{helper}{ADDRESS};
  
  #Log 1,"2 >>>>  :    #$cmd # $arg";
  
  if(defined($blocking) && $blocking == 1)
  {
    # use non-blocking http communication if not specified
    Log3 $name, 5, "YAMAHA_NP ($name) - execute blocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";

    my $param ={
                 url        => "http://".$address."/YamahaRemoteControl/ctrl",
                 timeout    => AttrVal($name, "requestTimeout", 4),
                 noshutdown => 1,
                 data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data,
                 loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                 hash       => $hash,
                 cmd        => $cmd,
                 arg        => $arg
               };
                           
    my ($err, $data) = HttpUtils_BlockingGet($param);

    YAMAHA_NP_ParseResponse($param, $err, $data);
  }
  else
  {
    Log3 $name, 5, "YAMAHA_NP ($name) - execute nonblocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";
    HttpUtils_NonblockingGet({
                               url        => "http://".$address."/YamahaRemoteControl/ctrl",
                               timeout    => AttrVal($name, "requestTimeout", 4),
                               noshutdown => 1,
                               data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data,
                               loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                               hash       => $hash,
                               cmd        => $cmd,
                               arg        => $arg,
                               callback   => \&YAMAHA_NP_ParseResponse
                             }); 
  }
}

sub YAMAHA_NP_ParseResponse
{
    # parses HTTP response
    my ($param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $cmd  = $param->{cmd};
    my $arg  = $param->{arg};
    #d1-input
    #d2-source
    #d3-song
    
    if(exists($param->{code}))
    {
      Log3 $name, 5, "YAMAHA_NP ($name) - received HTTP code ".$param->{code}." for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
    }

    if($err  ne "")
    {
      Log3 $name, 5, "YAMAHA_NP ($name) - could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $err";
      if((not exists($hash->{helper}{AVAILABLE})) or ($hash->{helper}{AVAILABLE} == 1)){
        Log3 $name, 3, "YAMAHA_NP ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
        readingsSingleUpdate($hash, "power", "absent", 1);
        readingsSingleUpdate($hash, "state", "absent", 1);
      }  
      $hash->{helper}{AVAILABLE} = 0;
    }
    elsif($data ne "")
    {
      Log3 $name, 5, "YAMAHA_NP ($name) - got response for \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $data";
      if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
      {
        Log3 $name, 3, "YAMAHA_NP ($name) - device $name reappeared";
        readingsSingleUpdate($hash, "power", "present", 1);            
      }
      
      $hash->{helper}{AVAILABLE} = 1;
      
      if (($cmd ne "statusRequest") and ($arg ne "systemConfig"))
      { # RC="0" is not delivered by that status Request
        if(not $data =~ /RC="0"/){
          # if the returncode != 0 -> HTTP command unsuccessful
          Log3 $name, 3, "YAMAHA_NP ($name) - Could not execute \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
        }
      }
      
      # Start readings update 
      readingsBeginUpdate($hash);

      if($cmd eq "statusRequest")
      {
        $hash->{helper}{statReq}{$arg} = 0;
        if   ($arg eq "systemConfig")
        {
          if($data =~ /<Model_Name>(.+?)<\/Model_Name>.*<System_ID>(.+?)<\/System_ID>.*<Version>(.+?)<\/Version>.*<Volume><Min>(.+?)<\/Min>.*<Max>(.+?)<\/Max>.*<Step>(.+?)<\/Step><\/Volume>/)
          {
            
            $hash->{MODEL}                      = $1;
            $hash->{helper}{dInfo}{MODEL}       = $1;
            $hash->{FIRMWARE}                   = $3;
            $hash->{helper}{dInfo}{FIRMWARE}    = $3;
            $hash->{helper}{dInfo}{SYSTEM_ID}   = $2;
            readingsBulkUpdate($hash, ".volumeStraightMin" , int($4));
            readingsBulkUpdate($hash, ".volumeStraightMax" , int($5));
            readingsBulkUpdate($hash, ".volumeStraightStep", int($6));
            # Used by 'fheminfo' command for statistics
            $attr{$name}{"model"} = $hash->{MODEL};
          }          
        }
        elsif($arg eq "getInputs")
        {
          my @ip;
          while($data =~ /<Feature_Existence>(.+?)<\/Feature_Existence>/gc)
          {
            push @ip,split(",",$1);
          } 
          $hash->{helper}{INPUTS} = join("|", sort @ip);  
        }
        elsif($arg eq "basicStatus")
        {
          if($data =~ /<Power>(.+?)<\/Power>/)
          {
            my $power = ($1 eq "Standby") ? "off":$1;
            $hash->{helper}{power} = lc($power);
            readingsBulkUpdate($hash, "power", $hash->{helper}{power});
            readingsBulkUpdate($hash, "state", $hash->{helper}{power});
            readingsBulkUpdate($hash, "audioSource", $hash->{helper}{power});
          }
          
          # current volume and mute status
          if($data =~ /<Volume><Lvl>(.+?)<\/Lvl><Mute>(.+?)<\/Mute><\/Volume>/)
          {
            readingsBulkUpdate($hash, "mute", lc($2));
            if($1 eq "0")
            {
              readingsBulkUpdate($hash, "mute", "on");
              # Bug in the NP firmware. Even if volume = 0. Mute remains off.
            }
			
			# Surpress Readings update during smooth volume change
            $hash->{helper}{volumeChangeProcessing} = "0" if(not defined($hash->{helper}{volumeChangeProcessing}));
			if ($hash->{helper}{volumeChangeProcessing} eq "0")
			{
			  readingsBulkUpdate($hash, "volumeStraight", ($1));
              readingsBulkUpdate($hash, "volume", YAMAHA_NP_volume_abs2rel($hash, $1));
			}
			
            if($hash->{helper}{power} eq "on" && (ReadingsVal($name, "volumeStraight", "") eq "0" || ReadingsVal($name, "mute", "") eq "on"))
            {
              if(ReadingsVal($name, "input", "") =~ m/(server|netradio|cd|usb)/)
              {
                my $playerInfo = ReadingsVal($name, "playerPlaybackInfo", "");
                if ($playerInfo eq "")
                {
                  $playerInfo = ("reading status...");
                }                
                readingsBulkUpdate($hash, "audioSource", ReadingsVal($name, "input", "") . " ($playerInfo, muted)");   
              }
              else
              {
                readingsBulkUpdate($hash, "audioSource", ReadingsVal($name, "input", "") . " (muted)");  
              }                 
            }
            elsif($hash->{helper}{power} eq "on")
            {
              if(ReadingsVal($name, "input", "") =~ m/(server|netradio|cd|usb)/)
              {
                my $playerInfo = ReadingsVal($name, "playerPlaybackInfo", "");
                if ($playerInfo eq "")
                {
                  $playerInfo = ("reading status...");
                }
                readingsBulkUpdate($hash, "audioSource", ReadingsVal($name, "input", "") . " ($playerInfo)");   
              }
              else
              {
                readingsBulkUpdate($hash, "audioSource", ReadingsVal($name, "input", ""));  
              }             
            }                          
          }
          
          if($data =~ /<Input_Sel>(.+?)<\/Input_Sel>/)
          {
            # current input same as the corresponding set command name
            my $input = lc($1);
            my $tb = ReadingsVal($name, "tunerBand", "tuner");
            $input = ($input eq "tuner") ? $tb : YAMAHA_NP_Param2Fhem($input, 0);
            
            if($input ne ReadingsVal($name,"input",""))
            {
              #input changed: clean readings and settings
              readingsBulkUpdate($hash, "input", $input);
              readingsBulkUpdate($hash, "audioSource", $input . " (reading status...)");  
              blankReadings4InChange($hash);              
            }
            if($input =~ m/(FM|DAB|tuner)/)
            {
              if(AttrVal($name, "autoUpdateTunerReadings","1") eq "1")
              {
                YAMAHA_NP_SendCmd($hash, "GET:Tuner,Play_Info:GetParam", "statusRequest", "tunerStatus", 0);
              }
            }
            else
            {
              delete $hash->{READINGS}{tunerBand};
              if(AttrVal($name, "autoUpdatePlayerReadings", "1") eq "1" )
              {
                # Inputs don't use any player readings. Blank them.
                if($input !~ m/^(aux|digital)/)
                {
                  YAMAHA_NP_SendCmd($hash, "GET:Player,Play_Info:GetParam", "statusRequest", "playerStatus", 0);        
                }
              }
            }
          }
          
          #Log 1, "Sleep: $data";

          if($data =~ /<Sleep>(.+?)<\/Sleep>/)
          {
            # Buggy NP firmware.
            # SLEEP does not reset in case of manual switch off...
            
            #my $sl = YAMAHA_NP_Param2Fhem($1, 0);
            my $sl = lc($1);
            $hash->{helper}{sleep} = $sl;
            readingsBulkUpdate($hash, "sleep", $sl);
          }
        }
        elsif($arg eq "playerStatus")
        {
          my $input = ReadingsVal($name,"input","");
          my $song = ($data =~ /<Song>(.+)<\/Song>/) ? YAMAHA_NP_html2txt($1) : "";

          $song = ReadingsVal($name,"listItem_$1","-") if ($song =~ /^Track(.*)/);
          readingsBulkUpdate($hash, "playerPlaySong"    , $song);
          readingsBulkUpdate($hash, "playerPlaybackInfo", ($data !~ /<Playback_Info>(.+)<\/Playback_Info>/)? ""    : lc($1));          
          
          if ($data =~ /<Play_Time>(.+)<\/Play_Time>/)
          {
            if(int($1) < 3600) # 00:00
            {
              readingsBulkUpdate($hash, "playerPlayTime", strftime("\%M:\%S", gmtime($1)));
            }
            else               # 00:00:00
            {
              readingsBulkUpdate($hash, "playerPlayTime", strftime("\%H:\%M:\%S", gmtime($1)));
            }
          }
          else
          {
            readingsBulkUpdate($hash, "playerPlayTime", "");
          }
          
          readingsBulkUpdate($hash, "playerPlayArtist"  , ($data !~ /<Artist>(.+)<\/Artist>/)              ? ""    : YAMAHA_NP_html2txt($1));
          readingsBulkUpdate($hash, "playerPlayAlbum"   , ($data !~ /<Album>(.+)<\/Album>/)                ? ""    : YAMAHA_NP_html2txt($1));
          readingsBulkUpdate($hash, "playerDeviceType"  , ($data !~ /<Device_Type>(.+)<\/Device_Type>/)    ? ""    : lc($1));
          readingsBulkUpdate($hash, "playerIpodMode"    , ($data !~ /<iPod_Mode>(.+)<\/iPod_Mode>/)        ? ""    : lc($1));
          readingsBulkUpdate($hash, "playerRepeat"      , ($data !~ /<Repeat>(.+)<\/Repeat>/)              ? ""    : lc($1));
          
          # Repeat toggles between OFF/ONE/ALL
          # Depending on the chosen command value the HTTP request command request has to be executed twice.
          # Check if different repeate mode is desired --> $hash->{helper}{playerRepeatModeTarget}
          if(defined($hash->{helper}{playerRepeatModeTarget})) # RepeatMode change requested previously
          {
            if(ReadingsVal($name, "playerRepeat", "") ne lc(substr($hash->{helper}{playerRepeatModeTarget}, -3))) # repeatOff,repeatOne,repeatAll 
            {
               YAMAHA_NP_SendCmd($hash,"PUT:Player,Play_Control,Play_Mode,Repeat:Toggle", "playMode", $hash->{helper}{playerRepeatModeTarget}, 0);
            }
            else
            {
               # The right mode selected. Delete helper.
               delete $hash->{helper}{playerRepeatModeTarget};
            }
          }
          
          readingsBulkUpdate($hash, "playerShuffle"     , ($data !~ /<Shuffle>(.+)<\/Shuffle>/)            ? ""    : lc($1));

          if($data =~ /<Album_ART><URL>(.+)<\/URL><ID>(.+)<\/ID><Format>(.+)<\/Format><\/Album_ART>/)
          {
            readingsBulkUpdate($hash, "playerAlbumArtURL"   , "http://".$hash->{helper}{ADDRESS}.YAMAHA_NP_html2txt($1));
            readingsBulkUpdate($hash, "playerAlbumArtID"    , YAMAHA_NP_html2txt($2));
            readingsBulkUpdate($hash, "playerAlbumArtFormat", YAMAHA_NP_html2txt($3));
          }
          else
          {
            readingsBulkUpdate($hash, "playerAlbumArtURL"   , "");
            readingsBulkUpdate($hash, "playerAlbumArtID"    , "");
            readingsBulkUpdate($hash, "playerAlbumArtFormat", "");  
          }
          if($input !~ m/^(cd|aux|digital|airplay|spotify)/)
		  {
		    # Don't update readings if not desired
			if(AttrVal($name, "autoUpdatePlayerlistReadings", "1") eq "1")
			{
			  YAMAHA_NP_SendCmd($hash, "GET:Player,List_Info:GetParam", "statusRequest", "playerListGetList", 0);
			  delete $hash->{helper}{playlist}{ready};	
			}
			else
			{
			  foreach (grep /playerListLvl.*$/,keys %{$hash->{READINGS}})
			  {
			    #delete level information
			    delete $hash->{READINGS}{$_};
			  }
			  # delete playerlist items
			  delete $hash->{READINGS}{$_} foreach (grep /listItem_...$/,keys %{$hash->{READINGS}});
			  delete $hash->{READINGS}{playerListMenuStatus};
			}
		  }
          elsif($input eq "cd")
          {
            my $tr = ($data =~ /<Track_Number>(.+)<\/Track_Number>/) ? sprintf("%02d",lc($1)) : "";
            readingsBulkUpdate($hash, "playerPlayTrackNb" , $tr);
            readingsBulkUpdate($hash, "playerTotalTracks" , ($data !~ /<Total_Tracks>(.+)<\/Total_Tracks>/)  ? ""          : lc($1));
          }
        }
        elsif($arg eq "tunerStatus")
        {
          if ($hash->{READINGS}{input}{VAL} =~ m/(FM|DAB|tuner)/)
          {
            # don't update if  tuner not selected
            if($data =~ /<Band>(.+)<\/Band>/)
            {
              $hash->{helper}{tuner}{band} = $1;
              readingsBulkUpdate($hash, "tunerBand", $hash->{helper}{tuner}{band});
            }
            
            if   ($hash->{helper}{tuner}{band} eq "FM")
            {
              my $id         = "-";
              my $frequency  = "-";
              my $tunerInfo1 = "-";
              
              if($data =~ /<FM><Preset><Preset_Sel>(.+)<\/Preset_Sel><\/Preset><Tuning><Freq>(.+)<\/Freq>(.*)<\/FM/)
              {
                $id = $1;
              }

              if($data =~ /<Program_Service>(.*)<\/Program_Service>/)
              {
                readingsBulkUpdate($hash, "tunerInfo1"   , ($1 ? YAMAHA_NP_html2txt($1) : "-"));
                $tunerInfo1 = $1;
              }              
              if($data =~ /<Radio_Text_A>(.*)<\/Radio_Text_A>/)
              {
                readingsBulkUpdate($hash, "tunerInfo2_A" , ($1 ? YAMAHA_NP_html2txt($1) : "-"));
              }
              if($data =~ /<Radio_Text_B>(.*)<\/Radio_Text_B>/)
              {
                readingsBulkUpdate($hash, "tunerInfo2_B" , ($1 ? YAMAHA_NP_html2txt($1) : "-"));
              } 
              if($data =~ /<Tuning><Freq>(.*)<\/Freq><\/Tuning>/)
              {
                if(ReadingsVal($name, "power","") eq "off")
				{
					# Bug in the firmware. Last tuned frequency is send also in Standby mode.
					$frequency = "-";
				}
				else
				{
			      $frequency = $1 ? $1 : "";
                  $frequency =~ s/(\d{2})$/.$1/; # Insert '.' to frequency
				}
                readingsBulkUpdate($hash, "tunerFrequency", $frequency." MHz");
              }
              # No presets stored
              if ($id eq "No Preset")
              {
                readingsBulkUpdate($hash, "tunerPreset"  , "-");
              }
              else
              {

                # NP sends <Preset_Sel>[Number]</Preset_Sel>
                # In case the station has been changed manually the number remains.
                # resulting in mismatch between preset and actual frequency.
                # NP Firmware bug?

                my $j = sprintf("%02d", $id);
                my $storedPreset = ReadingsVal($name,"listItem_0$j","");
                
                if ("FM $frequency MHz" eq $storedPreset)
                {
                    readingsBulkUpdate($hash, "tunerPreset"  , "$j $storedPreset $tunerInfo1");
                }
                else
                {
                  readingsBulkUpdate($hash, "tunerPreset"  , "-");
                }                
              }

              YAMAHA_NP_SendCmd($hash, "GET:Tuner,Play_Control,Preset,FM,Preset_Sel_Item:GetParam", "statusRequest", "tunerPreset", 0);
            }
            elsif($hash->{helper}{tuner}{band} eq "DAB")
            {
              my ($fq,$br,$qu,$am,$ch,$es,$dp,$sId) = ("-","-","-","-","-","-","DAB+","");
              
			  if($data =~ /<Signal_Info><Freq>(.+)<\/Freq>/)
              {
                $fq = $1;
                $fq =~ s/(\d{3})$/.$1/; # Insert '.' to frequency
              }
			                
              $br = $1                     if($data =~ /<Bit_Rate>(.+)<\/Bit_Rate>/);
              $qu = $1                     if($data =~ /<Quality>(.+)<\/Quality>/);
              $am = $1                     if($data =~ /<Audio_Mode>(.+)<\/Audio_Mode>/);
              $ch = $1                     if($data =~ /<Ch_Label>(.*)<\/Ch_Label>/);
			  $ch = "-"                    if($ch eq "");
              $es = YAMAHA_NP_html2txt($1) if($data =~ /<Ensemble_Label>(.*)<\/Ensemble_Label>/);
			  $es = "-"                    if($es eq "");
              $dp = "DAB"                  if($data =~ /<DAB_PLUS>Negate<\/DAB_PLUS>/);
			  
			  if($fq eq "-")
			  {
				$am = "-";
				$dp = "-";
				$qu = "-";
			  }
              
              # remember station name
              my $stName = "-";
              my $dls    = "-";
              my $ID     = "-";

              if($data =~ /<DLS>(.*)<\/DLS>/)
              {
                readingsBulkUpdate($hash, "tunerInfo1"  , ($1 ? YAMAHA_NP_html2txt($1) : "-"));
              }
              if($data =~ /<Service_Label>(.*)<\/Service_Label>/)
              {
                $stName = $1 ? YAMAHA_NP_html2txt($1) : "-";
                readingsBulkUpdate($hash, "tunerStation", $stName);
              }
              if($data =~ /<ID>(.+)<\/ID>/)
              {
                # we remember the channel names in hidden readings
                if ($stName)
                {
                  #if DLS not set the ID/Name correlation will likely not match. Just a workaround
                  $ID = YAMAHA_NP_html2txt($1);
                  # workaround: we need to see the station/ID combi twice before we assign it. 
                  if (   $hash->{helper}{tuner}{station} 
                      && $hash->{helper}{tuner}{station}   eq $stName
                      && $hash->{helper}{tuner}{stationID} eq $ID)
                  {
                    $hash->{READINGS}{".DAB_ID$ID"}{VAL}  = $stName;
                    $hash->{READINGS}{".DAB_ID$ID"}{TIME} = "-";
                  }
                  else
                  {
                    $hash->{helper}{tuner}{station}   = $stName;
                    $hash->{helper}{tuner}{stationID} = $ID;
                  }
                }
              }

              if($data =~ /<DAB><Preset><Preset_Sel>(.*)<\/Preset_Sel><\/Preset>(.*)<\/DAB>/)
              {
                my $presetSel = $1;

                #Log 1,"sID $2";

                if ($presetSel eq "No Preset")
                {
                  readingsBulkUpdate($hash, "tunerPreset"  , "-");
                }
                else
                {
                  # NP sends <Preset_Sel>[Number]</Preset_Sel>
                  # In case the station has been chosen manually the number remains.
                  # resulting in mismatch between preset and actual frequency.
                  # NP Firmware bug?

                  my $j = sprintf("%02d", $presetSel);
                  my $storedPreset = ReadingsVal($name,"listItem_0$j","");

                  #Log 1, "StorePreset: $storedPreset, ID: $ID";
                  
                  if ($storedPreset eq "ID $ID $stName")
                  {
                      readingsBulkUpdate($hash, "tunerPreset"  , "$j DAB $fq MHz $stName");
                  }
                  else
                  {
                    readingsBulkUpdate($hash, "tunerPreset"  , "-");
                  } 
                }                
              }
              readingsBulkUpdate($hash, "tunerDABSignal", "$fq MHz, $qu %, $br kbit/s, $am");
              readingsBulkUpdate($hash, "tunerDABStation", "$dp, Channel: $ch, Ensemble: $es" );
                            
              YAMAHA_NP_SendCmd($hash, "GET:Tuner,Play_Control,Preset,DAB,Preset_Sel_Item:GetParam", "statusRequest", "tunerPreset", 0); 
            }
          }          
        }
        elsif($arg eq "timerStatus")
        {
          if($data =~ /<Volume><Lvl>(.+)<\/Lvl><\/Volume>/){readingsBulkUpdate($hash, "timerVolume"   , $1);}
          if($data =~ /<Start_Time>(.+)<\/Start_Time>/)    {readingsBulkUpdate($hash, "timerStartTime", $1);}
          if($data =~ /<Repeat>(.+)<\/Repeat>/)            {readingsBulkUpdate($hash, "timerRepeat"   , lc($1));}
        }
        elsif($arg eq "getTimer")
        {
          if($data =~ /<Mode>(.+)<\/Mode>/){readingsBulkUpdate($hash, "timer", lc($1));}                                                  
        }
        elsif($arg eq "networkInfo")
        {
          if($data =~ /<IP_Address>(.+)<\/IP_Address>/)          {$hash->{helper}{dInfo}{IP_ADDRESS}      = $1;}
          if($data =~ /<Subnet_Mask>(.+)<\/Subnet_Mask>/)        {$hash->{helper}{dInfo}{SUBNET_MASK}     = $1;}
          if($data =~ /<Default_Gateway>(.+)<\/Default_Gateway>/){$hash->{helper}{dInfo}{DEFAULT_GATEWAY} = $1;}
          if($data =~ /<DNS_Server_1>(.+)<\/DNS_Server_1>/)      {$hash->{helper}{dInfo}{DNS_SERVER_1}    = $1;}
          if($data =~ /<DNS_Server_2>(.+)<\/DNS_Server_2>/)      {$hash->{helper}{dInfo}{DNS_SERVER_2}    = $1;}
          if($data =~ /<MAC_Address>(.+)<\/MAC_Address>/)        {$hash->{helper}{dInfo}{MAC_ADDRESS} = $1;
                                                                  # Add ':' after every two chars -> AA:BB:CC:DD:EE:FF
                                                                  $hash->{helper}{dInfo}{MAC_ADDRESS} =~ s/\w{2}\B/$&:/g;
          }            
        }
        elsif($arg eq "tunerPreset")
        {
          # May be also an empty string <Item_#></Item_#>
          if   (ReadingsVal($name,"tunerBand","") eq "FM")
          {
            # Max 30 presets
            for (my $i = 1; $i < 31; $i++)
            {
              my $s = $1 if ($data =~ /<Item_$i>(.+?)<\/Item_$i>/);            
              $s =~ s/.*?: // if ($s);                   
              if($s){readingsBulkUpdate($hash,sprintf("listItem_%03d", $i), $s);}
              else  {delete $hash->{READINGS}{sprintf("listItem_%03d", $i)};}               
            } 
          }
          else
          {
            #Band eq "DAB"
            # May be also an empty string <Item_#></Item_#>
            for (my $i = 1; $i < 31; $i++)
            {
              my $s = $1 if ($data =~ /<Item_$i>(.+?)<\/Item_$i>/);            
              if ($s)
              {
                $s =~ s/.*?: //; 
                my $ID = $s;
                $ID =~ s/^ID //;
                $s .= " ".$hash->{READINGS}{".DAB_ID$ID"}{VAL} if ($hash->{READINGS}{".DAB_ID$ID"});           
                readingsBulkUpdate($hash,sprintf("listItem_%03d", $i), $s);
              }
              else
              {
                delete $hash->{READINGS}{sprintf("listItem_%03d", $i)};
              }
            }
          }
        }
        elsif($arg eq "standbyMode")
        {
          if($data =~ /<Saving>(.+)<\/Saving>/){readingsBulkUpdate($hash, "standbyMode", lc($1));}
        }
        elsif($arg eq "mediaRendererDesc")
        {
          if($data =~ /<friendlyName>(.+)<\/friendlyName>/)
          {
            $hash->{FRIENDLY_NAME} = $1;
            $hash->{helper}{dInfo}{FRIENDLY_NAME} = $1;
          }          
          if($data =~ /<UDN>(.+)<\/UDN>/)
          {
            my @uuid = split(/:/, $1);
            $hash->{helper}{dInfo}{UUID} = uc($uuid[1]);            
          }
          
          $data =~ s/[\n\t\r]//g;# replace \n\t\r by ""
          
          if($data =~ /<iconList>(.+?)<\/iconList>/)
          {
            my $address = $hash->{helper}{ADDRESS};
            my $i = 1;
            
            while ($data =~ /<url>(.+?)<\/url>/g)
            {
              # MAy have several urls according to the UPNP/DLNA standard
              $hash->{helper}{dInfo}{"NP_ICON_$i"} = "http://".$address.":8080".$1;            
              $i++;
            }
          }
        }
        elsif($arg eq "playerListGetList") 	
        {
        if($data =~ /<Menu_Status>(.*)<\/Menu_Status>/)
        {
        $hash->{helper}{playlist}{ready} = $1;
        readingsBulkUpdate($hash, "playerListMenuStatus", $hash->{helper}{playlist}{ready});
        }
        
        my $lay = ($data =~ /<Menu_Layer>(.*)<\/Menu_Layer>/) ? $1 : "-";
        my $nam = ($data =~ /<Menu_Name>(.*)<\/Menu_Name>/)   ? $1 : "-";
        my ($lnMax,$lnCur,$lnPg) = (1,1,1);# maxline, currentline, currentpage
        
        if($data =~ /<Cursor_Position><Current_Line>(.*)<\/Current_Line><Max_Line>(.*)<\/Max_Line><\/Cursor_Position>/)
        {
        ($lnMax,$lnCur,$lnPg) = ($2,$1,int(($1-1)/8));
        }

        $lnMax = AttrVal($name, "maxPlayerListItems", 999) if ($lnMax >= AttrVal($name, "maxPlayerListItems", 999)); # Limit to given attribute value
        
        if (!$hash->{helper}{playlist}{mnCur} || $hash->{helper}{playlist}{mnCur} ne "$lay:$nam")
        {
        # did we change our context? Clean up
        $hash->{helper}{playlist}{mnCur} = "$lay:$nam"; 
        foreach (grep /playerListLvl.*$/,keys %{$hash->{READINGS}})
        {
          #delete level information
          delete $hash->{READINGS}{$_} if (substr($_,13)>$lay);
        }
        readingsBulkUpdate($hash, "playerListLvl$lay", "$nam");
        
        delete $hash->{READINGS}{$_} foreach (grep /listItem_...$/,keys %{$hash->{READINGS}});#delete playlist

        for (my $pln = 1;$pln <= $lnMax;$pln++)
        {
          #prefill entries as unknown
          $pln = sprintf("%03d",$pln);
          next if ($pln > 999);
          $hash->{READINGS}{"listItem_$pln"}{VAL} = "unknown";
          $hash->{READINGS}{"listItem_$pln"}{TIME}= "-";
        }
        my $lnNext = (($lnPg + 1) % (int(($lnMax-1)/8)+1))*8 + 1;
        $hash->{helper}{playlist}{state} = ($lnNext == 1) ? "complete" : "incomplete"; 
        YAMAHA_NP_SendCmd($hash, "PUT:Player,List_Control,Jump_Line:1","statusRequest", "playerListJumpLine", 0);
        }
        else
        {
        if ($hash->{helper}{playlist}{state} eq "incomplete")
        {
          my $lnNext = (($lnPg + 1) % (int(($lnMax-1)/8)+1))*8 + 1;
          $hash->{helper}{playlist}{state} = "complete" if($lnNext == 1); 
          YAMAHA_NP_SendCmd($hash, "PUT:Player,List_Control,Jump_Line:$lnNext","statusRequest", "playerListJumpLine", 0);
        }
        }
        if($data =~ /<Current_List>(.*)<\/Current_List>/)
        {
        # write list entries
        # <Line_X><Txt>****</Txt><Attribute>Container|Item|Unselectable</Attribute></Line_X>
        my ($i,$ip) = (1,1);
        my %pla =( Container => "c_",Item => "i_");   #PlayListAttr - convert to prefix
        while($data =~ /<Line_$i><Txt>(.*?)<\/Txt><Attribute>(.*?)<\/Attribute><\/Line_$i>/gc)
        {
          last if($ip >= AttrVal($name, "maxPlayerListItems", 999)); # Limit to giver attribute value
          $ip = sprintf("%03d",($lnPg * 8) + $i);
          if($1){readingsBulkUpdate($hash, "listItem_$ip", $pla{$2}.YAMAHA_NP_html2txt($1));}
          $i++;
        }    
        } 
        $hash->{helper}{playlist}{lnCur} = $lnCur; 
        if (ReadingsVal($name,"playerListMenuStatus","") eq "Ready")
        {
          # see whether more action is required
          if ($hash->{helper}{playlist}{selection})
          {
            YAMAHA_NP_SendCmd($hash, "PUT:Player,List_Control,Direct_Sel:Line_$hash->{helper}{playlist}{selection}", "selectStream", $hash->{helper}{playlist}{selection}, 0);
            delete $hash->{helper}{playlist}{selection};
          }
          elsif ($hash->{helper}{playlist}{desiredDirectoryLevel})
          {
            # want to change directory level
            my ($currentLevel) = split(":",$hash->{helper}{playlist}{mnCur});# currentLevel, 
            if ($hash->{helper}{playlist}{desiredDirectoryLevel} < $currentLevel)
            {
            YAMAHA_NP_SendCmd($hash, "PUT:Player,List_Control,Cursor:Return", "playerListCursorReturn", $hash->{helper}{playlist}{desiredDirectoryLevel},0);
            }
            else
            {
              delete $hash->{helper}{playlist}{desiredDirectoryLevel};
            }
          }		  
        }			
      }
      elsif($arg eq "playerListJumpLine")
      {
        YAMAHA_NP_SendCmd($hash, "GET:Player,List_Info:GetParam"      ,"statusRequest", "playerListGetList" , 0);
      }
      }
      elsif($cmd eq "on")
      {
        if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
        {
          $hash->{helper}{power} = "on";
          readingsBulkUpdate($hash, "power", "on");
          readingsBulkUpdate($hash, "state","on");
          readingsBulkUpdate($hash, "audioSource","- (reading status...)");
          
          readingsEndUpdate($hash, 1);
          
          YAMAHA_NP_ResetTimer($hash);
          
          # Used for direct play if device unpowered
          $cmd = $hash->{helper}{directPlayQueue}{state} if($hash->{helper}{directPlayQueue});
          return if(!defined $hash->{helper}{directPlayQueue});
        }
      }
      elsif($cmd eq "off")
      {
        if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
        {
          $hash->{helper}{power} = "on";
          readingsBulkUpdate($hash, "power", "off");
          readingsBulkUpdate($hash, "state","off");
          readingsBulkUpdate($hash, "audioSource","off");
          readingsEndUpdate($hash, 1);		  
		      blankReadings4InChange($hash); 
          YAMAHA_NP_ResetTimer($hash);
          return;
        }
      }
      elsif($cmd eq "mute")
      {
        if($data =~ /RC="0"/){readingsBulkUpdate($hash, "mute", $arg);}
      }
      elsif($cmd eq "standbyMode")
      {
        if($data =~ /RC="0"/)
        {
          readingsBulkUpdate($hash, "standbyMode", lc($arg));
        }
      }
      elsif($cmd =~ m/^volume/)
      {        
        if($data =~ /RC="0"/)
        {
		  if(AttrVal($name, "smoothVolumeChange", "1") eq "1" )
          {            
            my $volumeStraight = $hash->{READINGS}{volumeStraight}{VAL};

            if($hash->{helper}{targetVolume} eq $volumeStraight)
            {
              $hash->{helper}{volumeChangeDir} = "EQUAL";			   
            }
            
            if($hash->{helper}{volumeChangeDir} eq "EQUAL")
            {
              $hash->{helper}{volumeChangeProcessing} = "0";
              readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
              readingsBulkUpdate($hash, "volume", YAMAHA_NP_volume_abs2rel($hash, $hash->{helper}{targetVolume}));
            }			
            elsif($hash->{helper}{volumeChangeDir} =~ m/(UP|DOWN)/)
            {
              $hash->{helper}{volumeChangeProcessing} = "1";
			  if($hash->{helper}{volumeChangeDir} eq "UP")
			  {
				$volumeStraight += 1;				
			  }
			  elsif($hash->{helper}{volumeChangeDir} eq "DOWN")
			  {
			    $volumeStraight -= 1;			
        }
        readingsBulkUpdate($hash, "volumeStraight", $volumeStraight);
        readingsBulkUpdate($hash, "volume", YAMAHA_NP_volume_abs2rel($hash, $volumeStraight));
			  YAMAHA_NP_SendCmd($hash, "PUT:System,Volume,Lvl:$volumeStraight", "volume", $volumeStraight, 0);
			}
          }
          else
          {
            readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
            readingsBulkUpdate($hash, "volume", YAMAHA_NP_volume_abs2rel($hash, $hash->{helper}{targetVolume}));
            $hash->{helper}{volumeChangeDir} = "EQUAL";
            $hash->{helper}{volumeChangeProcessing} = "0";
          }
        }
      }
      elsif($cmd eq "input")
      {
        if ($arg =~ m/(FM|DAB)/)
        {
          # we have to select the correct band
          YAMAHA_NP_SendCmd($hash, "PUT:Tuner,Play_Control,Band:$arg", "tuner", $arg, 0);
          YAMAHA_NP_GetStatus($hash, 1);
        }
      }
      elsif($cmd eq "player")
      {
        if ($arg eq "prevCD" && ReadingsVal($name,"playerPlaybackInfo","") eq "play")
        {# we have to select the correct band
          YAMAHA_NP_SendCmd($hash,"PUT:Player,Play_Control,Playback:prev", "player", "prevCDDone", 0);
          YAMAHA_NP_GetStatus($hash, 1);

        }
      }
     
      # Reset internal timer for direct play.
      
      #Log 1,"General <<    : $cmd # $arg ".ReadingsVal($name,"playerListMenuStatus","-");
      
      if ($cmd ne "statusRequest")
      {
        if ($hash->{helper}{directPlayQueue})
        {
          RemoveInternalTimer("directPlay:".$name);
          my $slp = $hash->{helper}{directPlayQueue}{sleep} ? $hash->{helper}{directPlayQueue}{sleep} : 0.5;          
          InternalTimer(gettimeofday() + $slp, "YAMAHA_NP_directSet", "directPlay:".$name, 0);
        }
        YAMAHA_NP_GetStatus($hash, 1) ;# got to update if parameter changed
      }
      elsif
      (
           ($hash->{helper}{playlist}{ready} && $hash->{helper}{playlist}{ready} ne "Ready")
        && ($arg ne "playerListJumpLine")
      )                                              
      {
        # fast poll
        my $slp = $hash->{helper}{directPlayQueue}{sleep} ? $hash->{helper}{directPlayQueue}{sleep} : 0.5;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + $slp, "YAMAHA_NP_GetStatus", $hash, 0);
      }
      readingsEndUpdate($hash, 1);      
    }
}

sub blankReadings4InChange
{           
  # Blanks input relarted readings
  my ($hash) = @_;
  delete $hash->{READINGS}{$_} foreach(grep /^(player|tuner)/,keys %{$hash->{READINGS}});
  delete $hash->{helper}{playlist}{ready};
  blankLineItem($hash);
}

sub blankLineItem
{ 
  # Blanks list item entries
  my ($hash) = @_;
  delete $hash->{READINGS}{$_} foreach(grep /^listItem_/,keys %{$hash->{READINGS}});
}

sub YAMAHA_NP_directPlayFinish
{
  my ($hash, $status) = @_;
  delete $hash->{helper}{directPlayQueueTry};
  delete $hash->{helper}{directPlayQueue};
  RemoveInternalTimer("statTimeOut:".$hash->{NAME});
  readingsSingleUpdate($hash, "directPlay", ($status ? $status : "completed"), 1);
}

sub YAMAHA_NP_Param2Fhem
{
  # Converts all Values to FHEM usable command lists
  my ($param, $replace_pipes) = @_;
  
  $param =~ s/\s+//g;
  $param =~ s/[,_\)]//g;
  $param =~ s/\(/_/g;
  $param =~ s/\|/,/g if($replace_pipes == 1);

  return lc $param;
}

sub YAMAHA_NP_getParamName
{
  # Returns the Yamaha Parameter Name for the FHEM like equivalent
  my ($hash, $name, $list) = @_;
  
  return if(not defined($list));

  foreach my $item (split("\\|", $list)){
    return $item if(YAMAHA_NP_Param2Fhem($item, 0) eq $name);
  }    
}

sub YAMAHA_NP_getModel
{
  # queries the NP model, system-id and version
  my ($hash) = @_;

  YAMAHA_NP_SendCmd($hash, "GET:System,Config:GetParam", "statusRequest","systemConfig", 0);
  YAMAHA_NP_getMediaRendererDesc($hash);
  return;
}

sub YAMAHA_NP_getMediaRendererDesc
{
  # queries the addition model descriptions
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 5, "YAMAHA_NP ($name) - execute nonblocking \"MediaRendererDesc\"";
      
  HttpUtils_NonblockingGet({
                            url        => "http://".$hash->{helper}{ADDRESS}.":8080/MediaRenderer/desc.xml",
                            timeout    => AttrVal($name, "requestTimeout", 4),
                            noshutdown => 1,
                            data       => "",
                            loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                            hash       => $hash,
                            cmd        => "statusRequest",
                            arg        => "mediaRendererDesc",
                            callback   => \&YAMAHA_NP_ParseResponse                        
                          });
  return;
}

sub YAMAHA_NP_volume_rel2abs
{ 
  # converts straight volume in percentage volume (volumestraightmin .. volumestraightmax => 0 .. 100%)
  my ($hash, $percentage) = @_;
  
  return int($percentage * ReadingsVal($hash->{NAME},".volumeStraightMax",60) / 100 );
}

sub YAMAHA_NP_volume_abs2rel
{ 
  # converts relative volume in straight volume (0 .. 100% => volumestraightmin .. volumestraightmax)
  my ($hash, $absolute) = @_;	
  return int($absolute * 100 / ReadingsVal($hash->{NAME},".volumeStraightMax",100000)); #high default will return 0 if not set. 
}

sub YAMAHA_NP_getInputs
{
  # queries available inputs
  my ($hash) = @_;  
  my $name = $hash->{NAME};
  my $address = $hash->{helper}{ADDRESS};

  YAMAHA_NP_SendCmd($hash, "GET:System,Config:GetParam", "statusRequest","getInputs", 0);
  return;
}

sub YAMAHA_NP_ResetTimer
{
  # Restarts the internal status request timer according to the given interval or current NP state
  my ($hash, $interval) = @_;

  RemoveInternalTimer($hash);

  if($hash->{helper}{DISABLED} == 0){
    my $dly = 0;
    
    if(defined($interval)){
      $dly = $interval;
    }
    elsif(ReadingsVal($hash->{NAME},"power"   ,"") eq "on"){
      $dly = $hash->{helper}{ON_INTERVAL};
    }
    else{
      $dly = $hash->{helper}{OFF_INTERVAL};
    }
    InternalTimer(gettimeofday() + $dly, "YAMAHA_NP_GetStatus", $hash, 0) if ($dly);
  }  
}

sub YAMAHA_NP_html2txt
{
  # convert HTML entities into UTF-8 equivalent
  my ($string) = @_;

  $string =~ s/\\'//g;
  $string =~ s/(&amp;amp;quot;|&amp;quot;|&quot;)/\"/g;
  $string =~ s/(&amp;amp;|&amp;)/&/g;
  $string =~ s/&nbsp;/ /g;
  $string =~ s/&apos;/'/g;
  $string =~ s/(\xe4|&auml;)/ä;/g;
  $string =~ s/(\xc4|&Auml;)/Ä;/g;
  $string =~ s/(\xf6|&ouml;)/ö;/g;
  $string =~ s/(\xd6|&Ouml;)/Ö;/g;
  $string =~ s/(\xfc|&uuml;)/ü;/g;
  $string =~ s/(\xdc|&Uuml;)/Ü;/g;
  $string =~ s/(\xdf|&szlig;)/ß/g;

  $string =~ s/<.+?>//g;
  $string =~ s/(^\s+|\s+$)//g;

  return $string;
}

1;

=pod
=item device
=item summary    controls a Yamaha Network Player in a local network
=item summary_DE steuert einen Yamaha Netzwerkplayer im lokalen Netzwerk
=begin html

<a name="YAMAHA_NP"></a>
<h3>YAMAHA_NP</h3>
<ul>
  <a name="YAMAHA_NPdefine"></a>
  <b>Define</b>
  <br><br>
  <ul>
	<code>
	  define &lt;name&gt; YAMAHA_NP &lt;ip&ndash;address&gt; [&lt;status_interval&gt;]
	</code>
	<br><br>Alternatively with different two off/on interval definitions (default is 30 seconds).<br><br>
	<code>
	  define &lt;name&gt; YAMAHA_NP &lt;ip&ndash;address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
	</code>
	<br><br>This FHEM module controls a Yamaha Network Player (such as MCR&ndash;N560, MCR&ndash;N560D, CRX&ndash;N560, CRX&ndash;N560D, CD&ndash;N500 or NP&ndash;S2000) connected to local network.
	<br>Devices implementing the communication protocol of the Yamaha Network Player App for i*S and Andr*id might also work.
	<br><br>
	Example:<br>
	<ul><br>
	  <code>
		define NP_Player YAMAHA_NP 192.168.0.15<br>
		attr NP_player webCmd input:selectStream:volume<br><br>
		# With custom status interval of 60 seconds<br>
		define NP_Player YAMAHA_NP 192.168.0.15 <b>60</b><br>
		attr NP_player webCmd input:selectStream:volume<br><br>
		# With custom "off"&ndash;interval of 60 seconds and "on"&ndash;interval of 10 seconds<br>
		define NP_Player YAMAHA_NP 192.168.0.15 <b>60 10</b><br>
		attr NP_player webCmd input:selectStream:volume
	  </code>
	</ul>
  </ul>
  <br>
  <a name="YAMAHA_NPset"></a>
  <b>Set</b>
  <ul><br>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code>
	<br>
    <br>
    <i>Note: Commands and parameters are case&ndash;sensitive. The module provides available inputs depending on the connected device. Commands are context&ndash;sensitive depending on the current input or action.</i><br>
      <ul>
	  <br>
      <u>Available commands:</u><br><br>
      <li><b>CDTray</b> &ndash; open/close the CD tray.</li>
      <li><b>clockUpdate</b> &ndash; updates the system clock with current time. The local time information is taken from the FHEM server.</li>
      <li><b>dimmer</b> < 1..3 > &ndash; Sets the display brightness.</li>
      <li><b>directPlay</b> < input:Stream Level 1,Stream Level 2,... > &ndash; allows direct stream selection e.g. CD:1, DAB:1, netradio:Bookmarks,SWR3 (case&ndash;sensitive)</li>
      <li><b>favoriteDefine</b> < name:input[,Stream Level 1,Stream Level 2,...] > &ndash; defines and stores a favorite stream e.g. CoolSong:CD,1 (predefined favorites are the available inputs)</li>
      <li><b>favoriteDelete</b> < name > &ndash; deletes a favorite stream</li>
      <li><b>favoritePlay</b> < name > &ndash; plays a favorite stream</li>
      <li><b>input</b> [&lt;parameter&gt;] &ndash; selects the input channel. The inputs are read dynamically from the device. Available inputs can be set (e.g. cd, tuner, aux1, aux2, ...).</li>
      <li><b>mute</b> [on|off] &ndash; activates/deactivates muting</li>
      <li><b>off</b> &ndash; shuts down the device </li>
      <li><b>on</b> &ndash; powers on the device</li>
      <li><b>player [&lt;parameter&gt;] </b> &ndash; sets player related commands</li>
      <ul>
        <li><b>play</b> &ndash; play</li>
        <li><b>stop</b> &ndash; stop</li>
        <li><b>pause</b> &ndash; pause</li>
        <li><b>next</b> &ndash; next item</li>
        <li><b>prev</b> &ndash; previous item</li>
      </ul>
      <li><b>playMode [&lt;parameter&gt;] </b> &ndash; sets player mode shuffle or repeat</li>
      <ul>
        <li><b>shuffleAll</b> &ndash; Set shuffle mode</li>
        <li><b>shuffleOff</b> &ndash; Remove shuffle mode</li>
        <li><b>repeatOff</b> &ndash; Set repeat mode Off</li>        
        <li><b>repeatOne</b> &ndash; Set repeat mode One</li>
        <li><b>repeatAll</b> &ndash; Set repeat mode All</li>
      </ul>
      <li><b>selectStream</b> &ndash; direct context&ndash;sensitive stream selection depending on the input and available streams. Available streams are read out from device automatically. Depending on the number, this may take some time... (Limited to 999 list entries.) (see also 'maxPlayerLineItems' attribute</li>
	  <li><b>sleep</b> [off|30min|60min|90min|120min] &ndash; activates the internal sleep timer</li>
      <li><b>standbyMode</b> [eco|normal] &ndash; set the standby mode</li>
      <li><b>statusRequest [&lt;parameter&gt;] </b> &ndash; requests the current status of the device</li>
      <ul>
        <li><b>basicStatus</b> &ndash; requests the basic status such as volume input etc.</li>
        <li><b>playerStatus</b> &ndash; requests the player status such as play status, song info, artist info etc.</li>
        <li><b>standbyMode</b> &ndash; requests the standby mode information</li>
        <li><b>systemConfig</b> &ndash; requests the system configuration</li>
        <li><b>tunerStatus</b> &ndash; requests the tuner status such as FM frequency, preset number, DAB information etc.</li>
        <li><b>timerStatus</b> &ndash; requests device's internal wake&ndash;up timer status</li>
        <li><b>networkInfo</b> &ndash; requests device's network related information such as IP, Gateway, MAC address etc.</li>
      </ul>
      <li><b>timerSet</b> &ndash; configures the timer according to timerHour, timerMinute, timerRepeat, timerVolume attributes that must be set before. This command does not switch on the timer. &rarr; 'timer on'.)</li>
      <li><b>timer</b> [on|off] &ndash; sets device's internal wake&ndash;up timer. <i><br>(Note: The timer will be activated according to the last stored timer parameters in the device. In order to modify please use the 'timerSet' command.)</i></li>
      <li><b>tunerFMFrequency</b> [87.50 ... 108.00] &ndash; Sets the FM frequency. The value must be 87.50 ... 108.00 including the decimal point ('.') with two following decimals. Otherwise the value will be ignored. Available if input was set to FM.</li>
      <li><b>volume</b> [0...100] &ndash; set the volume level in &#037;</li>
      <li><b>volumeStraight</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; set the volume as used and displayed in the device. &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; are read and set from the device automatically.</li>
      <li><b>volumeUp</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; increases the volume by one device's absolute step. &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; are read and set from the device automatically.</li>
      <li><b>volumeDown</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; increases the volume by one device's absolute step. &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; are read and set from the device automatically.</li>
	</ul>
  </ul>
    <br>
  <a name="YAMAHA_NPget"></a>
  <b>Get</b>
  <ul>
    <code>
      get &lt;name&gt; &lt;reading&gt;
    </code>
    <br><br>
    The 'get' command returns reading values. Readings are context&ndash;sensitive depending on the current input or action taken.<br><br>
  </ul>
  <a name="YAMAHA_NPattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <ul>  
      <li><b>.DABList</b> &ndash; (internal) attribute used for DAB preset storage.</li>
      <li><b>.favoriteList</b> &ndash; (internal) attribute used for favorites storage.</li>      
      <li><b>autoUpdatePlayerReadings</b> &ndash; optional attribute for auto refresh of player related readings (default is 1).</li>
      <li><b>autoUpdatePlayerlistReadings</b> &ndash; optional attribute for auto scanning of the playerlist content (default is 1). (Due to the playerlist information transfer concept this function might slow down the reaction time of the Yamaha App when used at the same time.)</li>
	  <li><b>autoUpdateTunerReadings</b> &ndash; optional attribute for auto refresh of tuner related readings (default is 1).</li>
	  <li><b>directPlaySleepNetradio</b> &ndash; optional attribute to define a sleep time between two netradio requests to the vTuner server while using the directPlay command. Increase in case of slow internet connection (default is 5 seconds).</li>
	  <li><b>directPlaySleepServer</b> &ndash; optional attribute to define a sleep time between two multimedia server requests while using the directPlay command. Increase in case of slow server connection (default is 2 seconds).</li>
      <li><b>disable</b> &ndash; optional attribute to disable the internal cyclic status update of the NP. Manual status updates via statusRequest command is still possible. Possible values: 0 &rarr; perform cyclic status update, 1 &rarr; don't perform cyclic status updates (default is 1).</li>
	  <li><b>do_not_notify</b></li>
      <li><b>maxPlayerListItems</b> &ndash; optional attribute to limit the max number of player list items (default is 999).</li>
	  <li><b>readingFnAttributes</b></li><br>
      <li><b>requestTimeout</b> &ndash; optional attribute change the response timeout in seconds for all queries to the receiver. Possible values: 1...5 seconds (default value is 4).</li>
	  <li><b>searchAttempts</b> &ndash; optional attribute used by the directPlay command defining the max. number of finding the provided directory content tries before giving up. Possible values: 15...100 (default is 15).</li>
	  <li><b>smoothVolumeChange</b> &ndash; optional attribute for smooth volume change (significantly more Ethernet traffic is generated during volume change if set to 1) (default is 1).</li>
      <li><b>timerHour</b> [0...23] &ndash; sets hour of device's internal wake&ndash;up timer</li>
      <li><b>timerMinute</b> [0...59] &ndash; sets minutes of device's internal wake&ndash;up timer</li>
      <li><b>timerRepeat</b> [once|every] &ndash; sets repetition mode of device's internal wake&ndash;up timer</li>
      <li><b>timerVolume</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; sets volume of device's internal wake&ndash;up timer.</li>
      <br>
    </ul>
  </ul>
  <b>Readings</b><br>
  <ul>
    <ul>
      <br><u>General readings:</u><br><br>
      <li><b>deviceInfo</b> &ndash; Reports device specific grouped information such as uuid, ip address, etc.</li>
      <li><b>favoriteList</b> &ndash; Reports stored favorites</li>
      <li><b>reading [reading]</b> &ndash; Reports readings values</li>
      <ul><br>
        <li>.volumeStraightMax &ndash; device specific maximum volume</li>
        <li>.volumeStraightMin &ndash; device specific minimum volume</li>
        <li>.volumeStraightStep &ndash; device specific volume in&#47;decrement step</li>
        <li>audioSource &ndash; consolidated audio stream information with currently selected input, player status (if used) and volume muting information (off|reading status...|input [(play|stop|pause[, muted])]])</li>
		<li>directPlay &ndash; status of directPlay command</li>
        <li>input &ndash; currently selected input</li>
        <li>mute &ndash; mute status on/off</li>
        <li>power &ndash; current device status on/off</li>
        <li>presence &ndash; presence status of the device (present|absent)</li>
        <li>selectStream &ndash; status of the selectStream command</li>
        <li>sleep &ndash; sleep timer value (off|30 min|60 min|90 min|120 min)</li>
        <li>standbyMode &ndash; status of the standby mode (normal|eco)</li>
        <li>state &ndash; current state information (on|off)</li>
        <li>volume &ndash; relative volume (0...100)</li>
        <li>volumeStraight &ndash; device specific absolute volume [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;]</li>
      </ul>      
      <br><u>Player related readings:</u><br><br>
      <li><b>playerAlbumArtFormat</b> &ndash; Reports the album art format (if available) of the currently played audio</li>
      <li><b>playerAlbumArtID</b> &ndash; Reports the album art ID (if available) of the currently played audio</li>
      <li><b>playerAlbumArtURL</b> &ndash; Reports the album art url (if available) of the currently played audio. The URL points to the network player</li>
      <li><b>playerDeviceType</b> &ndash; Reports the device type (ipod|msc)</li>
      <li><b>playerIpodMode</b> &ndash; Reports the Ipod Mode (normal|off)</li>
      <li><b>playerAlbum</b> &ndash; Reports the album (if available) of the currently played audio</li>
      <li><b>playerArtist</b> &ndash; Reports the artist (if available) of the currently played audio</li>
      <li><b>playerSong</b> &ndash; Reports the song name (if available) of the currently played audio</li>
      <li><b>playerPlayTime</b> &ndash; Reports the play time of the currently played audio (HH:MM:SS)</li>
      <li><b>playerTrackNb</b> &ndash; Reports the track number of the currently played audio</li>
      <li><b>playerPlaybackInfo</b> &ndash; Reports current player state (play|stop|pause)</li>
      <li><b>playerRepeat</b> &ndash; Reports the Repeat Mode (one|all|off)</li>
      <li><b>playerShuffle</b> &ndash; Reports the Shuffle Mode (on|off)</li>
      <li><b>playerTotalTracks</b> &ndash; Reports the total number of tracks for playing</li>
      
      <br><u>Player list (menu) related readings:</u><br><br>
      <li>listItem_XXX &ndash; Reports the content of the device's current directory. Prefix 'c_' indicates a container (directory), prefix 'i_' an item (audio file/stream). Number of lines can be limited by the attribute 'maxPlayerLineItems' (default is 999).</li>
	  <li>lvlX_ &ndash; Reports the hierarchical directory tree level.</li>
      <br><u>Tuner related readings:</u><br><br>
      <li>listItem_XXX &ndash; Reports the stored presets.</li>
      <li>tunerBand &ndash; Reports the tuner band (DAB|FM)</li>
      <br>
      <li>DAB</li>
      <ul><li>tunerDABStation &ndash; (DAB|DAB+), Channel: (value), Ensemble: (name)</li></ul>  
      <ul><li>tunerDABSignal &ndash; (Frequency), (Signal quality), (Bitrate), (Mono|Stereo)</li></ul>
      <ul><li>tunerInfo1 &ndash; DAB program service</li></ul>
      <ul><li>tunerPreset &ndash; (Preset number DAB Frequency Station) or '&ndash;' if not stored as preset</li></ul>
      <ul><li>tunerStation &ndash; DAB Station Name</li></ul>
      <br>
      <li>FM</li>
      <ul><li>tunerFrequency &ndash; FM frequency</li></ul>
      <ul><li>tunerInfo1 &ndash; FM station name</li></ul>
      <ul><li>tunerInfo2_A &ndash; Additional RDS information A</li></ul>
      <ul><li>tunerInfo2_A &ndash; Additional RDS information B</li></ul>
      <ul><li>tunerPreset &ndash; (Preset number FM Frequency Station) or '&ndash;' if not stored as preset</li></ul>

      <br><u>Timer related readings:</u><br><br>
      <li>timer &ndash; current timer status (on|off)</li>
      <li>timerRepeat &ndash; timer repeat mode (once|every)</li>
      <li>timerStartTime &ndash; timer start time HH:MM</li>
      <li>timerVolume &ndash; timer volume [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;]</li>
    </ul>
  </ul>
</ul>

=end html

=begin html_DE

<a name="YAMAHA_NP"></a>
<h3>YAMAHA_NP</h3>
<ul>
  <a name="YAMAHA_NPdefine"></a>
  <b>Define</b>
  <br><br>
  <ul>
	<code>
	  define &lt;name&gt; YAMAHA_NP &lt;ip&ndash;address&gt; [&lt;status_interval&gt;]
	</code>
	<br><br>Alternatitv mit unterschiedlichen off/on Intervalldefinitionen (Default 30 Sek).<br><br>
	<code>
	  define &lt;name&gt; YAMAHA_NP &lt;ip&ndash;address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
	</code>
	<br><br>Dieses FHEM&ndash;Modul steuert einen Yamaha Network Player (z.B. MCR&ndash;N560, MCR&ndash;N560D, CRX&ndash;N560, CRX&ndash;N560D, CD&ndash;N500 or NP&ndash;S2000) im lokalen Netzwerk.
	<br>Ger&auml;te, die das Kommunikationsprotokoll der Yamaha Network Player App f&uuml;r i*S und Andr*id implementieren, sollten ebenfalls unterst&uuml;tzen werden k&ouml;nnen.
	<br><br>
	Beispiel:<br>
	<ul><br>
	  <code>
		define NP_Player YAMAHA_NP 192.168.0.15<br>
		attr NP_player webCmd input:selectStream:volume<br><br>
		# Mit einem Statusintervall von 60 Sek.<br>
		define NP_Player YAMAHA_NP 192.168.0.15 <b>60</b><br>
		attr NP_player webCmd input:selectStream:volume<br><br>
		# Mit unterschiedlichen Statusintervallen f&uuml;r off/on, 60/10 Sekunden<br>
		define NP_Player YAMAHA_NP 192.168.0.15 <b>60 10</b><br>
		attr NP_player webCmd input:selectStream:volume
	  </code>
	</ul>
  </ul>
  <br>
  <a name="YAMAHA_NPset"></a>
  <b>Set</b>
  <ul><br>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code>
	<br>
    <br>
    <i>Bemerkung: Bei den Befehlen und Parametern ist die Groß&ndash;/Kleinschreibung zu bachten. Das Modul zeigt ausschließlich verf&uuml;gbare Eing&auml;nge, die vom jeweiligen Ger&auml;t unterst&uuml;tzt werden. Dar&uuml;ber hinaus sind die Befehle kontextsensitiv, abh&auml;ngig von dem jeweils gew&auml;hlten Eingang bzw. Betriebsmodus.</i><br>
      <ul>
	  <br>
      <u>Verf&uuml;gbare Befehle:</u><br><br>
      <li><b>CDTray</b> &ndash; &Ouml;ffnen und Schlie&szlig;en des CD&ndash;Fachs.</li>
      <li><b>clockUpdate</b> &ndash; Aktualisierung der Systemzeit des Network Players. Die Zeitinformation wird von dem FHEM Server bezogen, auf dem das Modul ausgef&uuml;hrt wird.</li>
      <li><b>dimmer</b> [1..3] &ndash; Einstellung der Anzeigehelligkeit</li>
      <li><b>directPlay</b> < input:Stream Level 1,Stream Level 2,... > &ndash; erm&ouml;glicht direktes Abspielen eines Audiostreams/einer Audiodatei z.B. CD:1, DAB:1, netradio:Bookmarks,SWR3 </li>
      <li><b>favoriteDefine</b> < name:input[,Stream Level 1,Stream Level 2,...] > &ndash; Speichert einen Favoriten e.g. CoolSong:CD,1 (vordefinierte Favoriten sind die verf&uuml;gbaren Eing&auml;nge)</li>
      <li><b>favoriteDelete</b> < name > &ndash; L&ouml;scht einen Favoriten</li>
      <li><b>favoritePlay</b> < name > &ndash; Spielt einen Favoriten ab</li>
	  <li><b>input</b> [&lt;parameter&gt;] &ndash; Auswahl des Eingangs des Network Players. (Nicht verf&uuml;gbar beim ausgeschaltetem Ger&auml;t)</li>
      <li><b>mute</b> [on|off] &ndash; Aktiviert/Deaktiviert die Stummschaltung</li>
      <li><b>off</b> &ndash; Network Player ausschalten</li>
      <li><b>on</b> &ndash; Network Player einschalten</li>
      <li><b>player [&lt;parameter&gt;] </b> &ndash; Setzt Player relevante Befehle.</li>
      <ul>
        <li><b>play</b> &ndash; play</li>
        <li><b>stop</b> &ndash; stop</li>
        <li><b>pause</b> &ndash; pause</li>
        <li><b>next</b> &ndash; n&auml;chstes Audiost&uuml;ck</li>
        <li><b>prev</b> &ndash; vorheriges Audiost&uuml;ck</li>
      </ul>
       <li><b>playMode [&lt;parameter&gt;] </b> &ndash; Setzt Player relevante Befehle</li>
      <ul>
        <li><b>shuffleAll</b> &ndash; setzt shuffle</li>
        <li><b>shuffleOff</b> &ndash; setzt no Shuffle mode</li>
        <li><b>repeatOff</b> &ndash; repeat off</li>
        <li><b>repeatOne</b> &ndash; repeat one</li>
        <li><b>repeatAll</b> &ndash; repeat all</li>                
      </ul>
	  <li><b>selectStream</b> &ndash; Direkte kontextsensitive Streamauswahl. Ver&uuml;gbare Men&uuml;eintr&auml;ge werden automatisch generiert. Bedingt durch das KOnzept des Yamaha&ndash;Protokolls kann dies etwas Zeit in Anspruch nehmen. (Defaultm&auml;ssig auf 999 Listeneint&auml;ge limitiert. s.a. maxPlayerLineItems Attribut.)</li>
	  <li><b>sleep</b> [off|30min|60min|90min|120min] &ndash; Aktiviert/Deaktiviert den internen Sleep&ndash;Timer</li>
      <li><b>standbyMode</b> [eco|normal] &ndash; Umschaltung des Standby Modus.</li>
      <li><b>statusRequest [&lt;parameter&gt;] </b> &ndash; Abfrage des aktuellen Status des Network Players.</li>
      <ul>
        <li><b>basicStatus</b> &ndash; Abfrage der Elementarparameter (z.B. Lautst&auml;rke, Eingang, etc.)</li>
        <li><b>playerStatus</b> &ndash; Abfrage des Player&ndash;Status.</li>
        <li><b>standbyMode</b> &ndash; Abfrage des standby Modus.</li>
        <li><b>systemConfig</b> &ndash; Abfrage der Systemkonfiguration.</li>
        <li><b>tunerStatus</b> &ndash; Abfrage des Tuner&ndash;Status (z.B. FM Frequenz, Preset&ndash;Nummer, DAB Information etc.)</li>
        <li><b>timerStatus</b> &ndash; Abfrage des internen Wake&ndash;up timers.</li>
        <li><b>networkInfo</b> &ndash; Abfrage von Netzwerk&ndash;relevanten Informationen (z.B: IP&ndash;Adresse, Gateway&ndash;Adresse, MAC&ndash;address etc.)</li>
      </ul>
      <li><b>timerSet</b> &ndash; konfiguriert den Timer nach den Vorgaben: timerHour, timerMinute, timerRepeat, timerVolume (s. entprechende Attribute). (ALLE Attribute m&uuml;ssen zuvor gesetzt sein. Dieser Befehl schaltet den Timer nicht ein &rarr; 'timer on'.)</li>
      <li><b>timer</b> [on|off] &ndash; Schaltet ein/aus den internen Wake&ndash;up Timer. <i>(Bemerkung: Der Timer wird basierend auf den im Ger&auml;t gespeicherten Parametern aktiviert. Um diese zu &auml;ndern, bitte den 'timerSet' Befehl benutzen.)</i></li>
      <li><b>tunerFMFrequency</b> [87.50 ... 108.00] &ndash; Setzt die FM Frequenz. Der Wert muss zwischen 87.50 ... 108.00 liegen und muss den Digitalpunkt beinhalten ('.') mit zwei Nachkommastellen.</li>
      <li><b>volume</b> [0...100] &ndash; Setzt den relativen Lautst&auml;rkepegel in &#037;</li>
      <li><b>volumeStraight</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; Setzt die absolute Lautst&auml;rke wie vom Ger&auml;t benutzt und angezeigt. Die Parameter &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; werden automatisch ermittelt.</li>
      <li><b>volumeUp</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; Erh&ouml;ht die Lautst&auml;rke um einen absoluten Schritt. Die Parameter &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; werden automatisch ermittelt.</li>
      <li><b>volumeDown</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &ndash; Reduziert die Lautst&auml;rke um einen absoluten Schritt. Die Parameter &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; werden automatisch ermittelt.</li>
	</ul>
  </ul>
    <br>
  <a name="YAMAHA_NPget"></a>
  <b>Get</b>
  <ul>
    <code>
      get &lt;name&gt; &lt;reading&gt;
    </code>
    <br><br>
    Der 'get' Befehl liest Readingwerte zur&uuml;ck. Die Readings sind kontextsensitiv und h&auml;ngen von dem/der jeweils gew&auml;hlten Eingang bzw. Aktion ab.<br><br>
  </ul>
  <a name="YAMAHA_NPattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <ul>  
      <li><b>.DABList</b> &ndash; (internes) Attribut zum Speichern von DAB Presets</li>
      <li><b>.favoriteList</b> &ndash; (internes) Attribut zum Speichern von Favoriten</li>      
      <li><b>autoUpdatePlayerReadings</b> &ndash; optionales Attribut zum automtischen aktualisieren der Player&ndash;Readings (Default 1)</li>
      <li><b>autoUpdatePlayerlistReadings</b> &ndash; optionales Attribut zum automatischen Scannen der Playerlist (Men&uuml;) (Default 1). (Aufgrund des Kommunikationskonzeptes bei der &Uuml;bertragung der Playerlistinformation kann diese Funktion zu l&auml;ngeren Reaktionszeiten bei der Yamaha App f&uuml;hren, wenn gleichzeitig auf den Netzwerkplayer zugegriffen wird.)</li>
	  <li><b>autoUpdateTunerReadings</b> &ndash; optionales Attribut zum automtischen aktualisieren der Tuner&ndash;Readings (Default 1)</li>
      <li><b>directPlaySleepNetradio</b> &ndash; optionales Attribut zum Definieren der Sleep-Zeit zwischen zwei netradio Anfragen zum vTuner Server, wenn der Befehl directPlay benutzt wird. Kann bei langsamen Interneverbindungen n&uuml;tzlich sein. (Default 5 Sek.).</li>
	  <li><b>directPlaySleepServer</b> &ndash; optionales Attribut zum Definieren der Sleep-Zeit zwischen zwei Multimediaserver-Anfragen, wenn der Befehl directPlay benutzt wird. Kann bei langsamen Verbindungen n&uuml;tzlich sein. (Default 2 Sek.).</li>
	  <li><b>disable</b> &ndash; optionales Attribut zum Deaktivieren des internen zyklischen Timers zum Aktualisieren des NP&ndash;Status. Manuelles Update ist nach wie vor m&ouml;glich. M&ouml;gliche Werte: 0 &rarr; Zyklisches Update aktiv., 1 &rarr; Zyklisches Update inaktiv (Default 1).</li>
	  <li><b>do_not_notify</b></li>
	  <li><b>maxPlayerListItems</b> &ndash; optionales Attribut zum Limitieren der maximalen Anzahl von Men&uuml;eintr&auml;gen (Default 999).</li>
	  <li><b>readingFnAttributes</b></li>
	  <li><b>requestTimeout</b> &ndash; optionales Attribut zum setzen des HTTP response Timeouts (Default 4)</li>
	  <li><b>searchAttempts</b> &ndash; optionales Attribut zur Definition von max. Anzahl der Suchversuche des angegebenen Direktoryinhalts bei der Benutzng des directPlay Befehls. M&ouml;gliche Werte: 15...100 (Default 15 Sek.).</li>
	  <li><b>smoothVolumeChange</b> &ndash; optionales Attribut zur sanften Lautst&auml;rke&auml;nderung (Erzeugt deutlich mehr Ethernetkommunikation w&auml;hrend der Lautst&auml;rke&auml;nderung). (Default 1)</li>
      <li><b>timerHour</b> [0...23] &ndash; Setzt die Stunde des internen Wake&ndash;up Timers</li>
      <li><b>timerMinute</b> [0...59] &ndash; Setzt die Minute des internen Wake&ndash;up Timers</li>
      <li><b>timerRepeat</b> [once|every] &ndash; Setzt den Wiederholungsmodus des internen Wake&ndash;up Timers</li>
      <br>
    </ul>
  </ul>
  <b>Readings</b><br>
  <ul>
    <ul>
      <br><u>Generelle Readings:</u><br><br>      
	  <li><b>deviceInfo</b> &ndash; Devicespezifische, konsolidierte Informationen wie z.B. uuid, IP&ndash;Adresse, usw.</li>
      <li><b>favoriteList</b> &ndash; Listet gespeicherte Favoriten auf</li>
      <li><b>reading [reading]</b> &ndash; Gibt Readingwerte zur&uuml;ck</li>
      <ul><br>
        <li>.volumeStraightMax &ndash; Devicespezifische maximale Lautst&aumlrke</li>
        <li>.volumeStraightMin &ndash;  Devicespezifische minimale Lautst&aumlrke</li>
        <li>.volumeStraightStep &ndash;  Devicespezifischer minimales Lautst&aumlrkenin&ndash;&#47;dekrement</li>
        <li>audioSource &ndash; Konsolidierte Audiostreaminformation mit aktuell gew&auml;hltem Eingang, Playerstatus (wenn aktiv) und Mute Information. (off|reading status...|input [(play|stop|pause[, muted])]])</li>
		<li>directPlay &ndash; Status des directPlay Befehls</li>
        <li>input &ndash; Aktuell gew&aumlhlter Eingang</li>
        <li>mute &ndash; Mute status</li>
        <li>power &ndash; Aktueller Devicestatus (on|off)</li>
        <li>presence &ndash; Ger&aumlteverf&uuml;gbarkeit im Netzwerk (present|absent)</li>
        <li>selectStream &ndash; Status des selectStream Befehls</li>
        <li>sleep &ndash; Sleeptimer Wert (off|30 min|60 min|90 min|120 min)</li>
        <li>standbyMode &ndash; Standby Mode Status (normal|eco)</li>
        <li>state &ndash; Aktueller Ger&auml;tezusand (on|off)</li>
        <li>volume &ndash; Relative Lautst&aumlrke [0 ... 100]</li>
        <li>volumeStraight &ndash; Devicespezifische absolute Lautst&aumlrke [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;]</li>
      </ul>      
      <br><u>Playerspezifische Readings:</u><br><br>
      <li><b>playerPlaybackInfo</b> &ndash; Abfrage des aktuellen Player Status (play|stop|pause)</li>
		<li><b>playerAlbum</b> &ndash; Abfrage des Albumnamens (falls verf&uuml;gbar) der aktuellen Wiedergabe</li>
		<li><b>playerAlbumArtURL</b> &ndash; Abfrage der Album URL (falls verf&uuml;gbar) der aktuellen Wiedergabe</li>
		<li><b>playerAlbumArtID</b> &ndash; Abfrage der AlbumArtID (falls verf&uuml;gbar) der aktuellen Wiedergabe</li>
		<li><b>playerAlbumArtFormat</b> &ndash; Abfrage des AlbumArt Formats (falls verf&uuml;gbar) der aktuellen Wiedergabe</li>
		<li><b>playerArtist</b> &ndash; Abfrage des K&uuml;nstler (Artist) (falls verf&uuml;gbar) der aktuellen Wiedergabe</li>
		<li><b>playerDeviceType</b> &ndash; Abfrage des Device Typs (ipod|msc)</li>
		<li><b>playerIpodMode</b> &ndash; Abfrage des iP*d/iPh*ne Modus (normal|off)</li>
		<li><b>playerPlayTime</b> &ndash; Abfrage der aktuellen Spielzeit (HH:MM:SS)</li>
		<li><b>playerRepeat</b> &ndash; Abfrage des Wiederholungsmodus (one|all)</li>
		<li><b>playerShuffle</b> &ndash; Abfrage des Zufallswiedergabemodus (on|off)</li>
		<li><b>playerSong</b> &ndash; Abfrage des Tracknamens (falls verf&uuml;gbar) der aktuellen Wiedergabe</li>
		<li><b>playerTotalTracks</b> &ndash; Abfrage der Gesamtzahl der zu wiedergebenden Tracks</li>
		<li><b>playerTrackNb</b> &ndash; Abfrage der Audiotracknummer</li>
      <br><u>Playerlistspezifische (Men&uuml;) Readings:</u><br><br>
      <li>listItem_XXX &ndash; Inhalt der Men&uuml;eintr&auml;ge. Prefix 'c_' steht f&uuml;r Container (Directory), Prefix 'i_' f&uuml;r Item (Audiofile/Stream). Die Anzahl kann mit dem Attribut 'maxPlayerLineItems' limitiert werden (Default 999).</li>
	  <li>lvlX_ &ndash; Zeigt den hierarchischen Directorylevel im Directory Tree an</li>
      <br><u>Tunerspezifische Readings:</u><br><br>
      <li>listItem_XXX &ndash; Gespeicherter Preset</li>
      <li>tunerBand &ndash; Tuner Band (DAB|FM)</li>
      <br>
      <li>DAB</li>
      <ul><li>tunerDABStation &ndash; (DAB|DAB+), Channel: (value), Ensemble: (name)</li></ul>  
      <ul><li>tunerDABSignal &ndash; (Frequenz), (Signalqualit&auml;), (Bitrate), (Mono|Stereo)</li></ul>
      <ul><li>tunerInfo1 &ndash; DAB program service</li></ul>
      <ul><li>tunerPreset &ndash; (Preset number DAB Frequenz Sender) oder '&ndash;' wenn aktueller Sender nicht als Preset gespeichert wurde</li></ul>
      <ul><li>tunerStation &ndash; DAB Sendername</li></ul>
      <br>
      <li>FM</li>
      <ul><li>tunerFrequency &ndash; FM Frequenz</li></ul>
      <ul><li>tunerInfo1 &ndash; FM Sendername</li></ul>
      <ul><li>tunerInfo2_A &ndash; Zus&auml;tzliche RDS Information A</li></ul>
      <ul><li>tunerInfo2_A &ndash; Zus&auml;tzliche RDS Information B</li></ul>
      <ul><li>tunerPreset &ndash; (Presetnummer FM Frequenz Sender) oder '&ndash;' wenn aktueller Sender nicht als Preset gespeichert wurde</li></ul>

      <br><u>Timerspezifische Readings:</u><br><br>
      <li>timer &ndash; Aktueller Timerstatus (on|off)</li>
      <li>timerRepeat &ndash; Timer repeat mode (once|every)</li>
      <li>timerStartTime &ndash; Timer Startzeit HH:MM</li>
      <li>timerVolume &ndash; Timerlautst&auml;rke [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;]</li>
    </ul>
  </ul>
</ul>

=end html_DE

=cut

##############################################################################
#
#     $Id$
#
#     71_YAMAHA_NP.pm
#
#     An FHEM Perl module for controlling the Yamaha CD-Receiver CRX-N560(D)
#     (aka MCR-N560D) via Ethernet connection.
#     The module should also work with devices controlled by the
#     Yamaha Network Player App for *OS and Andr*id
#     (e.g. NP-S2000, CD-N500, CD-N301, R-N500, R-N301).
#
#     Copyright by Radoslaw Watroba
#     (e-mail: ra666ack@googlemail.com)
#
#     Inspired by the 71_YAMAHA_AVR module by Markus Bloch
#     (e-mail: Notausstieg0309@googlemail.com)
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
sub YAMAHA_NP_Initialize
{
  my ($hash) = @_;

  $hash->{DefFn}     = "YAMAHA_NP_Define";
  $hash->{GetFn}     = "YAMAHA_NP_Get";
  $hash->{SetFn}     = "YAMAHA_NP_Set";
  $hash->{AttrFn}    = "YAMAHA_NP_Attr";
  $hash->{UndefFn}   = "YAMAHA_NP_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 disable:0,1 request-timeout:1,2,3,4,5 ".$readingFnAttributes;
  
  return;
}

###################################
sub YAMAHA_NP_GetStatus
{
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $power;

  $local = 0 unless(defined($local));

  return "" if((!defined($hash->{helper}{ADDRESS})) or (!defined($hash->{helper}{OFF_INTERVAL})) or (!defined($hash->{helper}{ON_INTERVAL})));

  my $device = $hash->{helper}{ADDRESS};

  # Get model and firmware information
  if(not defined($hash->{MODEL}))
  {
    YAMAHA_NP_getModel($hash);
    # Get network related information from the NP
    YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Info>GetParam</Info></Network></Misc></System></YAMAHA_AV>", "statusRequest", "networkInfo");
    YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Info>GetParam</Info></Network></Misc></System></YAMAHA_AV>", "statusRequest", "systemConfig");
    YAMAHA_NP_ResetTimer($hash) unless($local == 1);    
    return;
  }
  
  # Get available inputs if not defined
  if((not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0))
  {
    YAMAHA_NP_getInputs($hash);
    YAMAHA_NP_ResetTimer($hash) unless($local == 1);    
    return;
  }
  
  YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Basic_Status>GetParam</Basic_Status></System></YAMAHA_AV>", "statusRequest", "basicStatus");  
  YAMAHA_NP_ResetTimer($hash) unless($local == 1);
  return;
}

###################################
sub YAMAHA_NP_Get
{
  my ($hash, @a) = @_;
  my $what;
  my $return;

  return "argument is missing" if(int(@a) != 2);
  
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
sub YAMAHA_NP_Set
{
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    my $address = $hash->{helper}{ADDRESS};
    
    # Get model info in case not defined
    if(not defined($hash->{MODEL}) or not defined($hash->{FIRMWARE}))
    {
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Info>GetParam</Info></Network></Misc></System></YAMAHA_AV>", "statusRequest", "networkInfo");
      YAMAHA_NP_getModel($hash);
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Info>GetParam</Info></Network></Misc></System></YAMAHA_AV>", "statusRequest", "systemConfig");
    }
    
    if(not defined($hash->{helper}{VOLUMESTRAIGHTMIN}) and not defined($hash->{helper}{VOLUMESTRAIGHTMAX}))
    {
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Info>GetParam</Info></Network></Misc></System></YAMAHA_AV>", "statusRequest", "basicStatus");
    }

    # get all available inputs if nothing is available
    if(not defined($hash->{helper}{INPUTS}) or length($hash->{helper}{INPUTS}) == 0)
    {
      YAMAHA_NP_getInputs($hash);
    }
       
    my $inputs_piped = defined($hash->{helper}{INPUTS}) ? YAMAHA_NP_Param2Fhem(lc($hash->{helper}{INPUTS}), 0) : "" ;
    my $inputs_comma = defined($hash->{helper}{INPUTS}) ? YAMAHA_NP_Param2Fhem(lc($hash->{helper}{INPUTS}), 1) : "" ;
    
    # Setting default values. Update from device during existing communication.
    my $volumeStraightMin = defined($hash->{helper}{VOLUMESTRAIGHTMIN}) ? $hash->{helper}{VOLUMESTRAIGHTMIN} : "0";
    my $volumeStraightMax = defined($hash->{helper}{VOLUMESTRAIGHTMAX}) ? $hash->{helper}{VOLUMESTRAIGHTMAX} : "60";
    
    return "No Argument given" if(!defined($a[1]));     
    
    my $what = $a[1];
    
    my $usage = "";
    
    # DAB available? Suffix D stands for DAB.
    if (defined($hash->{MODEL}))
    {
      my $model = $hash->{MODEL};
      
      if ($model eq "CRX-N560D")
      {
        $usage = "Unknown argument $what, choose one of ".
                 "on:noArg ".
                 "off:noArg ".
                 "timerRepeat:once,every ".
                 "sleep:off,30min,60min,90min,120min ".
                 "volumeStraight:slider,".$volumeStraightMin.",1,".$volumeStraightMax." ".
                 "volume:slider,0,1,100 ".
                 "volumeUp:noArg ".
                 "volumeDown:noArg ".
                 "timerVolume:slider,".$volumeStraightMin.",1,".$volumeStraightMax." ".
                 "mute:on,off ".
                 (exists($hash->{helper}{INPUTS})?"input:".$inputs_comma." ":"").
                 "statusRequest:basicStatus,mediaRendererDesc,playerStatus,systemConfig,timerStatus,tunerPresetDAB,tunerPresetFM,tunerStatus ".
                 "standbyMode:eco,normal ".
                 "cdTray:noArg ".
                 "timer:on,off ".
                 "tuner:bandDAB,bandFM,presetUp,presetDown,tuneDown,tuneUp ".
                 "player:play,stop,pause,next,prev,shuffleToggle,repeatToggle ".
                 "clockUpdate:noArg ".
                 "tunerPresetDAB:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30 ".
                 "tunerPresetFM:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30 ".
                 "timerHour:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23 ".
                 "timerMinute:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59 ";
      }
      else
      {
        $usage = "Unknown argument $what, choose one of ".
                 "on:noArg ".
                 "off:noArg ".
                 "timerRepeat:once,every ".
                 "sleep:off,30min,60min,90min,120min ".
                 "volumeStraight:slider,".$volumeStraightMin.",1,".$volumeStraightMax." ".
                 "volume:slider,0,1,100 ".
                 "volumeUp:noArg ".
                 "volumeDown:noArg ".
                 "timerVolume:slider,".$volumeStraightMin.",1,".$volumeStraightMax." ".
                 "mute:on,off ".
                 (exists($hash->{helper}{INPUTS})?"input:".$inputs_comma." ":"").
                 "statusRequest:basicStatus,mediaRendererDesc,networkInfo,playerStatus,systemConfig,timerStatus,tunerPresetFM,tunerStatus ".
                 "standbyMode:eco,normal ".
                 "cdTray:noArg ".
                 "timer:on,off ".
                 "tuner:bandFM,presetUp,presetDown,tuneDown,tuneUp ".
                 "player:play,stop,pause,next,prev,shuffleToggle,repeatToggle ".
                 "clockUpdate:noArg ".
                 "tunerPresetFM:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30 ".
                 "timerHour:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23 ".
                 "timerMinute:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59 ";
      }
      Log3 $name, 5, "Model: $model.";
    }    
    
    Log3 $name, 5, "YAMAHA_NP ($name) - set ".join(" ", @a);
    
    if($what eq "on")
    {
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Power>On</Power></Power_Control></System></YAMAHA_AV>" ,$what, undef);
    }
    elsif($what eq "off")
    {
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Power>Standby</Power></Power_Control></System></YAMAHA_AV>", $what, undef);
    }
    elsif($what eq "input")
    {
      if(defined($a[2]))
      {
        if($hash->{READINGS}{power}{VAL} eq "on")
        {
          if(not $inputs_piped eq "")
          {
            if($a[2] =~ /^($inputs_piped)$/)
            {
              my $command = YAMAHA_NP_getParamName($hash, $a[2], $hash->{helper}{INPUTS});
              
              if(defined($command) and length($command) > 0)
              {
                YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Input><Input_Sel>".$command."</Input_Sel></Input></System></YAMAHA_AV>", $what, $a[2]);
              }
              else
              {
                  return "invalid input: ".$a[2];
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
        if($hash->{READINGS}{power}{VAL} eq "on")
        {
          if($a[2] eq "on")
          {
            YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Volume><Mute>On</Mute></Volume></System></YAMAHA_AV>", $what, "on");
          }
          elsif($a[2] eq "off")
          {
            YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Volume><Mute>Off</Mute></Volume></System></YAMAHA_AV>", $what, "off"); 
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
    elsif($what =~ /^(volumeStraight|volume|volumeUp|volumeDown)$/)
    {
      my $target_volume;
      
      if(($what eq "volume") and ($a[2] >= 0) and ($a[2] <= 100))
      {
          $target_volume = YAMAHA_NP_volume_rel2abs($hash, $a[2]);
      }
      elsif($what eq "volumeDown")
      {
          $target_volume = $hash->{READINGS}{volumeStraight}{VAL} - 1;
      }
      elsif($what eq "volumeUp")
      {
          $target_volume = $hash->{READINGS}{volumeStraight}{VAL} + 1;
      }
      else
      {
        # volumeStraight
        $target_volume = $a[2];
      }
            
      # if lower than minimum VOLUMESTRAIGHTMIN or higher than max VOLUMESTRAIGHTMAX set target volume to the corresponding limts
      $target_volume = $hash->{helper}{VOLUMESTRAIGHTMIN} if(defined($target_volume) and $target_volume < $hash->{helper}{VOLUMESTRAIGHTMIN});
      $target_volume = $hash->{helper}{VOLUMESTRAIGHTMAX} if(defined($target_volume) and $target_volume > $hash->{helper}{VOLUMESTRAIGHTMAX});
      
      Log3 $name, 4, "YAMAHA_NP ($name) - new target volume: $target_volume";
      
      if(defined($target_volume) )
      {
        if($hash->{READINGS}{power}{VAL} eq "on")
        {
          $hash->{helper}{targetVolume} = $target_volume;
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Volume><Lvl>".($target_volume)."</Lvl></Volume><\/System></YAMAHA_AV>", "volume", undef);
        }
        else
        {
            return "Volume can only be changed when device is powered on";
        }
      }
    }    
    elsif($what eq "sleep")
    {
      if($a[2] eq "off")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Sleep>Off</Sleep></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "30min")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Sleep>30 min</Sleep></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "60min")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Sleep>60 min</Sleep></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "90min")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Sleep>90 min</Sleep></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "120min")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Sleep>120 min</Sleep></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      else
      {
          return $usage;
      } 
    }
    elsif($what eq "tuner")
    {
        if($a[2] eq "presetUp")
        {
          YAMAHA_NP_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><Preset_Sel>Next</Preset_Sel></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "presetDown")
        {
          YAMAHA_NP_SendCommand($hash,"<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><Preset_Sel>Prev</Preset_Sel></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "tuneUp")
        {
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Service>Next</Service></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "tuneDown")
        {
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Service>Prev</Service></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "bandDAB")
        {
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Band>DAB</Band></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }
        elsif($a[2] eq "bandFM")
        {
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Band>FM</Band></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
        }  
        else
        {
          return $usage;
        }
    }
    elsif($what eq "player")
    {
      if($a[2] eq "play")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Playback>Play</Playback></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "pause")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Playback>Pause</Playback></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "stop")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Playback>Stop</Playback></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "next")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Playback>Next</Playback></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "prev")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Playback>Prev</Playback></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "shuffle")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Play_Mode><Shuffle>Toggle</Shuffle></Play_Mode></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "repeat")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Player><Play_Control><Play_Mode><Repeat>Toggle</Repeat></Play_Mode></Play_Control></Player></YAMAHA_AV>", $what, $a[2]);
      }
      else
      {
          return $usage;
      }
    }        
    elsif($what eq "standbyMode")
    {
      if($a[2] eq "eco")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Saving>Eco</Saving></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "normal")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Power_Control><Saving>Normal</Saving></Power_Control></System></YAMAHA_AV>", $what, $a[2]);
      }
      else
      {
          return $usage;
      }
    }
    elsif($what eq "cdTray")
    {
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Misc><Tray>Open/Close</Tray></Misc></System></YAMAHA_AV>", $what, undef);
    }
    elsif($what eq "clockUpdate")
    {  
      my $clockUpdateCurrentTime = Time::Piece->new();
      YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Misc><Clock><Param>".($clockUpdateCurrentTime->strftime('%Y:%m:%d:%H:%M:%S'))."</Param></Clock></Misc></System></YAMAHA_AV>", $what, undef);
    }
    elsif($what eq "statusRequest")
    {
      if($a[2] eq "systemConfig")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "playerStatus")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Player><Play_Info>GetParam<\/Play_Info><\/Player><\/YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "tunerStatus")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Tuner><Play_Info>GetParam<\/Play_Info><\/Tuner><\/YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "basicStatus")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Basic_Status>GetParam</Basic_Status></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "timerStatus")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Timer><Mode>GetParam</Mode></Timer></Misc></System></YAMAHA_AV>", $what, "getTimer");
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Timer><Param>GetParam</Param></Timer></Misc></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "networkInfo")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Misc><Network><Info>GetParam</Info></Network></Misc></System></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "tunerPresetFM")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Tuner><Play_Control><Preset><FM><Preset_Sel_Item>GetParam</Preset_Sel_Item></FM></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
      }
      elsif($a[2] eq "tunerPresetDAB")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><Tuner><Play_Control><Preset><DAB><Preset_Sel_Item>GetParam</Preset_Sel_Item></DAB></Preset></Play_Control></Tuner></YAMAHA_AV>", $what, $a[2]);
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
      if($a[2] eq "on")
      {
        if(defined($hash->{helper}{timerHour}) and defined($hash->{helper}{timerMinute}) and defined($hash->{helper}{timerRepeat}) and defined($hash->{helper}{timerVolume}))
        {
            # Configure Timer according to provided parameters
            YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Misc><Timer><Param><Start_Time>".sprintf("%02d", $hash->{helper}{timerHour}).":".sprintf("%02d", $hash->{helper}{timerMinute})."</Start_Time><Volume>".$hash->{helper}{timerVolume}."</Volume><Repeat>".$hash->{helper}{timerRepeat}."</Repeat></Param></Timer></Misc></System></YAMAHA_AV>", $what, $a[2]);
            # Switch on timer
            YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Misc><Timer><Mode>".ucfirst($a[2])."</Mode></Timer></Misc></System></YAMAHA_AV>", $what, $a[2]);
        }
        else
        {
          return "Please, define timerHour, timerMinute, timerRepeat and timerVolume first."
        }
      }
      elsif($a[2] eq "off")
      {
        YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><System><Misc><Timer><Mode>".ucfirst($a[2])."</Mode></Timer></Misc></System></YAMAHA_AV>", $what, $a[2]);
      }
      else
      {
          return $usage;
      }
    }
    elsif($what eq "timerHour")
    {
      if((int($a[2]) >= 0) and (int($a[2]) <= 23))
      {
        $hash->{helper}{timerHour} = $a[2];
      }
      else
      {
        return $usage;
      }
    }
    elsif($what eq "timerMinute")
    {
      if((int($a[2]) >= 0) and (int($a[2]) <= 59))
      {
        $hash->{helper}{timerMinute} = $a[2];
      }
      else
      {
        return $usage;
      }
    }
    elsif($what eq "timerRepeat")
    {
        if($a[2] eq "once" or $a[2] eq "every")
        {
          $hash->{helper}{timerRepeat} = ucfirst($a[2]);
        }
        else
        {
          return $usage;
        }
    }
    elsif($what eq "timerVolume")
    {
        # if lower than minimum VOLUMESTRAIGHTMIN or higher than max VOLUMESTRAIGHTMAX set target volume to the corresponding limts
        if($a[2] >=  $hash->{helper}{VOLUMESTRAIGHTMIN} and $a[2] <= $hash->{helper}{VOLUMESTRAIGHTMAX})
        {
          $hash->{helper}{timerVolume} = $a[2];
        }
        else
        {
          return "Please use straight device volume range :".$hash->{helper}{VOLUMESTRAIGHTMIN}."...".$hash->{helper}{VOLUMESTRAIGHTMAX}.".";
        }
    }
    elsif($what eq "tunerPresetDAB")
    {
        if($a[2] >= 1 and $a[2] <= 30 and $hash->{MODEL} eq "CRX-N560D")
        {
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><DAB><Preset_Sel>".$a[2]."<\/Preset_Sel><\/DAB><\/Preset><\/Play_Control><\/Tuner></YAMAHA_AV>", "tunerPresetDAB", $a[2]);
        }
        else
        {
          return $usage;
        }
    }
    elsif($what eq "tunerPresetFM")
    {
        if($a[2] >= 1 and $a[2] <= 30)
        {
          YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"PUT\"><Tuner><Play_Control><Preset><FM><Preset_Sel>".$a[2]."<\/Preset_Sel><\/FM><\/Preset><\/Play_Control><\/Tuner></YAMAHA_AV>", "tunerPresetFM", $a[2]);
        }
        else
        {
          return $usage;
        }
    }
    else
    {
        return $usage;
    }
    
    return;
}

#############################
sub YAMAHA_NP_Define
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    if(! @a >= 3)
    {
      my $msg = "Wrong syntax: define <name> YAMAHA_NP <ip-or-hostname> [<ON-statusinterval>] [<OFF-statusinterval>] ";
      Log3 $name, 2, $msg;
      return $msg;
    }

    my $address = $a[2];
  
    $hash->{helper}{ADDRESS} = $address;

    # if an update interval was given which is greater than zero, use it.
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
    
    # set the volume-smooth-change attribute only if it is not defined, so no user values will be overwritten
    #
    # own attribute values will be overwritten anyway when all attr-commands are executed from fhem.cfg
    
    unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0))
    {
      $hash->{helper}{AVAILABLE} = 1;
      readingsSingleUpdate($hash, "presence", "present", 1);
    }
    

    # start the status update timer
    $hash->{helper}{DISABLED} = 0 unless(exists($hash->{helper}{DISABLED}));
    YAMAHA_NP_ResetTimer($hash,0);
  
    return;
}


##########################
sub YAMAHA_NP_Attr
{
  my @a = @_;
  my $hash = $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "disable")
  {
    if($a[3] eq "0")
    {
      $hash->{helper}{DISABLED} = 0;
      YAMAHA_NP_GetStatus($hash, 1);
    }
    elsif($a[3] eq "1")
    {
      $hash->{helper}{DISABLED} = 1;
    }
  }
  elsif($a[0] eq "del" && $a[2] eq "disable")
  {
    $hash->{helper}{DISABLED} = 0;
    YAMAHA_NP_GetStatus($hash, 1);
  }

  # Start/Stop Timer according to new disabled-Value
  YAMAHA_NP_ResetTimer($hash);

  return;
}

#############################
sub YAMAHA_NP_Undefine
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
sub YAMAHA_NP_SendCommand
{
  my ($hash, $data,$cmd,$arg,$blocking) = @_;
  my $name = $hash->{NAME};
  my $address = $hash->{helper}{ADDRESS};

  # "Blocking" delivers most reliable results for updating the READINGS.
  # However, should the NP suddenly disappear FHEM would be blocked until a timeout.
  # Trade-off between sending command and getting status...

  # Always use non-blocking http communication
  if(not defined($blocking) and $cmd ne "statusRequest" and $hash->{helper}{AVAILABLE} == 1)
  {
    #1 for testing
    $blocking = 0;
  }
  else
  {
    #0 for testing
    $blocking = 0;
  }
    
  # In case any URL changes must be made, this part is separated in this function".

  if($blocking == 1)
  {
    Log3 $name, 5, "YAMAHA_NP ($name) - execute blocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";
    
    my $param =
    {
      url        => "http://".$address."/YamahaRemoteControl/ctrl",
      timeout    => AttrVal($name, "request-timeout", 4),
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
      
    HttpUtils_NonblockingGet
    ({
      url        => "http://".$address."/YamahaRemoteControl/ctrl",
      timeout    => AttrVal($name, "request-timeout", 4),
      noshutdown => 1,
      data       => "<?xml version=\"1.0\" encoding=\"utf-8\"?>".$data,
      loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
      hash       => $hash,
      cmd        => $cmd,
      arg        => $arg,
      callback   => \&YAMAHA_NP_ParseResponse
                          
    }); 
  }
  
  return;  
}

#############################
# parses the receiver response
sub YAMAHA_NP_ParseResponse
{
    my ( $param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $cmd = $param->{cmd};
    my $arg = $param->{arg};
    
    if(exists($param->{code}))
    {
      Log3 $name, 5, "YAMAHA_NP ($name) - received HTTP code ".$param->{code}." for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
    }
    
    if($err ne "")
    {
      Log3 $name, 5, "YAMAHA_NP ($name) - could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $err";

      if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} == 1))
      {
        Log3 $name, 3, "YAMAHA_NP ($name) - could not execute command on device $name. Please turn on your device in case of deactivated network standby or check for correct hostaddress.";
        readingsSingleUpdate($hash, "presence", "absent", 1);
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
        readingsSingleUpdate($hash, "presence", "present", 1);            
      }
      
      $hash->{helper}{AVAILABLE} = 1;
      
      if ($cmd ne "statusRequest" and $arg ne "systemConfig") # RC="0" is not delivered by that status Request
      {
        if(not $data =~ /RC="0"/)
        {
          # if the returncode isn't 0, than the command was not successful
          Log3 $name, 3, "YAMAHA_NP ($name) - Could not execute \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
        }
      }
      
      readingsBeginUpdate($hash);
      
      if($cmd eq "statusRequest")
      {
          if($arg eq "systemConfig")
          {
            if($data =~ /<Model_Name>(.+?)<\/Model_Name>.*<System_ID>(.+?)<\/System_ID>.*<Version>(.+?)<\/Version>.*<Volume><Min>(.+?)<\/Min>.*<Max>(.+?)<\/Max>.*<Step>(.+?)<\/Step><\/Volume>/)
            {
              delete($hash->{MODEL}) if(defined($hash->{MODEL}));
              delete($hash->{helper}{VOLUMESTRAIGHTMIN}) if(defined($hash->{helper}{VOLUMESTRAIGHTMIN}));
              delete($hash->{helper}{VOLUMESTRAIGHTMAX}) if(defined($hash->{helper}{VOLUMESTRAIGHTMAX}));
              delete($hash->{helper}{VOLUMESTRAIGHTSTEP}) if(defined($hash->{helper}{VOLUMESTRAIGHTSTEP}));
              
              $hash->{MODEL}                      = $1;
              $hash->{SYSTEM_ID}                  = $2;
              $hash->{FIRMWARE}                   = $3;
              $hash->{helper}{VOLUMESTRAIGHTMIN}  = $4;
              $hash->{helper}{VOLUMESTRAIGHTMAX}  = $5;
              $hash->{helper}{VOLUMESTRAIGHTSTEP} = $6;
            }
            
            #$attr{$name}{"model"} = $hash->{MODEL};
          }
          elsif($arg eq "getInputs")
          {
            delete($hash->{helper}{INPUTS}) if(defined($hash->{helper}{INPUTS}));
            
            while($data =~ /<Feature_Existence>(.+?)<\/Feature_Existence>/gc)
            {
              if(defined($hash->{helper}{INPUTS}) and length($hash->{helper}{INPUTS}) > 0)
              {
                $hash->{helper}{INPUTS} .= ",";
              }      
              $hash->{helper}{INPUTS} .= $1;
            }    
            $hash->{helper}{INPUTS} = join("|", sort split("\\,", $hash->{helper}{INPUTS}));  
          }
          elsif($arg eq "basicStatus")
          {
            if($data =~ /<Power>(.+?)<\/Power>/)
            {
              my $power = $1;
              
              if($power eq "Standby")
              {	
                  $power = "off";
              }
              readingsBulkUpdate($hash, "power", lc($power));
              readingsBulkUpdate($hash, "state", lc($power));
            }
            
            # current volume and mute status
            if($data =~ /<Volume><Lvl>(.+?)<\/Lvl><Mute>(.+?)<\/Mute><\/Volume>/)
            {
              readingsBulkUpdate($hash, "volumeStraight", ($1));
              readingsBulkUpdate($hash, "volume", YAMAHA_NP_volume_abs2rel($hash, $1));
              readingsBulkUpdate($hash, "mute", lc($2));                
            }
            # current input same as the corresponding set command name
            if($data =~ /<Input_Sel>(.+?)<\/Input_Sel>/)
            {
              readingsBulkUpdate($hash, "input", YAMAHA_NP_Param2Fhem(lc($1), 0));
            }
            
            if($data =~ /<Sleep>(.+?)<\/Sleep>/)
            {
              readingsBulkUpdate($hash, "sleep", YAMAHA_NP_Param2Fhem($1, 0));
            }
          }
          elsif($arg eq "playerStatus")
          {
            if($data =~ /<Playback_Info>(.+)<\/Playback_Info>/)
            {
              readingsBulkUpdate($hash, "playerPlaybackInfo", lc($1));
            }                
            if($data =~ /<Device_Type>(.+)<\/Device_Type>/)
            {
              readingsBulkUpdate($hash, "playerDeviceType", lc($1));
            }
            if($data =~ /<iPod_Mode>(.+)<\/iPod_Mode>/)
            {
              readingsBulkUpdate($hash, "playerIpodMode", lc($1));
            }
            if($data =~ /<Repeat>(.+)<\/Repeat>/)
            {
              readingsBulkUpdate($hash, "playerRepeat", lc($1));
            }
            if($data =~ /<Shuffle>(.+)<\/Shuffle>/)
            {
              readingsBulkUpdate($hash, "playerShuffle", lc($1));
            }
            if($data =~ /<Play_Time>(.+)<\/Play_Time>/)
            {
              readingsBulkUpdate($hash, "playerPlayTime", strftime("\%H:\%M:\%S", gmtime($1)));                  
            }
            if($data =~ /<Track_Number>(.+)<\/Track_Number>/)
            {
              readingsBulkUpdate($hash, "playerTrackNumber", lc($1));
            }
            if($data =~ /<Total_Tracks>(.+)<\/Total_Tracks>/)
            {
              readingsBulkUpdate($hash, "playerTotalTracks", lc($1));
            }
            if($data =~ /<Artist>(.+)<\/Artist>/)
            {
              readingsBulkUpdate($hash, "playerArtist", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Album>(.+)<\/Album>/)
            {
              readingsBulkUpdate($hash, "playerAlbum", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Song>(.+)<\/Song>/)
            {
              readingsBulkUpdate($hash, "playerSong", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Album_ART><URL>(.+)<\/URL><ID>(.+)<\/ID><Format>(.+)<\/Format><\/Album_ART>/)
            {
              my $address = $hash->{helper}{ADDRESS};
              
              readingsBulkUpdate($hash, "playerAlbumArtURL", "http://".$address."".YAMAHA_NP_html2txt($1));
              readingsBulkUpdate($hash, "playerAlbumArtID", YAMAHA_NP_html2txt($2));
              readingsBulkUpdate($hash, "playerAlbumArtFormat", YAMAHA_NP_html2txt($3));
            }            
          }
          elsif($arg eq "tunerStatus")
          {
            if($data =~ /<Band>(.+)<\/Band>/)
            {
              readingsBulkUpdate($hash, "tunerBand", ($1));
            }
            if($data =~ /<FM><Preset><Preset_Sel>(.+)<\/Preset_Sel><\/Preset>(.*)<\/FM/)
            {
              readingsBulkUpdate($hash, "tunerPresetFM", ($1));
            }
            if($data =~ /<Tuning><Freq>(.+)<\/Freq><\/Tuning>/)
            {
              my $frequency = $1;
              $frequency =~ s/(\d{2})$/.$1/; # Insert '.' to frequency
              readingsBulkUpdate($hash, "tunerFrequencyFM", $frequency." MHz");
            }
            if($data =~ /<Program_Service>(.+)<\/Program_Service>/)
            {
              readingsBulkUpdate($hash, "tunerProgramServiceFM", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Radio_Text_A>(.+)<\/Radio_Text_A>/)
            {
              readingsBulkUpdate($hash, "tunerRadioTextAFM", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Radio_Text_B>(.+)<\/Radio_Text_B>/)
            {
              readingsBulkUpdate($hash, "tunerRadioTextBFM", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<DAB><Preset><Preset_Sel>(.+)<\/Preset_Sel><\/Preset>(.*)<\/DAB>/)
            {
              readingsBulkUpdate($hash, "tunerPresetDAB", ($1));
            }
            if($data =~ /<Service_Label>(.+)<\/Service_Label>/)
            {
              readingsBulkUpdate($hash, "tunerServiceLabelDAB", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Ch_Label>(.+)<\/Ch_Label>/)
            {
              readingsBulkUpdate($hash, "tunerChannelLabelDAB", ($1));
            }
            if($data =~ /<DLS>(.+)<\/DLS>/)
            {
              readingsBulkUpdate($hash, "tunerDLSDAB", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Ensemble_Label>(.+)<\/Ensemble_Label>/)
            {
              readingsBulkUpdate($hash, "tunerEnsembleLabelDAB", YAMAHA_NP_html2txt($1));
            }
            if($data =~ /<Bit_Rate>(.+)<\/Bit_Rate>/)
            {
              readingsBulkUpdate($hash, "tunerBitRateDAB", $1." kbit\/s");
            }
            if($data =~ /<Audio_Mode>(.+)<\/Audio_Mode>/)
            {
              readingsBulkUpdate($hash, "tunerAudioModeDAB", $1);
            }
            if($data =~ /<DAB_PLUS>(.+)<\/DAB_PLUS>/)
            {
              if($1 eq "Negate")
              {
                readingsBulkUpdate($hash, "tunerModeDAB", "DAB");
              }
              elsif($1 eq "Assert")
              {
                readingsBulkUpdate($hash, "tunerModeDAB", "DAB+");
              }
            }
            if($data =~ /<Signal_Info><Freq>(.+)<\/Freq>/)
            {
              my $frequency = $1;
              $frequency =~ s/(\d{3})$/.$1/; # Insert '.' to frequency
              readingsBulkUpdate($hash, "tunerFrequencyDAB", $frequency." MHz");
            }
          }
          elsif($arg eq "timerStatus")
          {
            if($data =~ /<Volume><Lvl>(.+)<\/Lvl><\/Volume>/)
            {
              readingsBulkUpdate($hash, "timerVolume", $1);
            }
            if($data =~ /<Start_Time>(.+)<\/Start_Time>/)
            {
              readingsBulkUpdate($hash, "timerStartTime", $1);
            }
            if($data =~ /<Repeat>(.+)<\/Repeat>/)
            {
              readingsBulkUpdate($hash, "timerRepeat", lc($1));
            }
          }
          elsif($arg eq "getTimer")
          {
            if($data =~ /<Mode>(.+)<\/Mode>/)
            {
              readingsBulkUpdate($hash, "timer", lc($1));
            }                                                  
        }
        elsif($arg eq "networkInfo")
        {
          if($data =~ /<IP_Address>(.+)<\/IP_Address>/)
          {
            $hash->{IP_ADDRESS} = $1;
          }
          if($data =~ /<Subnet_Mask>(.+)<\/Subnet_Mask>/)
          {
            $hash->{SUBNET_MASK} = $1;
          }
          if($data =~ /<Default_Gateway>(.+)<\/Default_Gateway>/)
          {
            $hash->{DEFAULT_GATEWAY} = $1;
          }
          if($data =~ /<DNS_Server_1>(.+)<\/DNS_Server_1>/)
          {
            $hash->{DNS_SERVER_1} = $1;
          }
          if($data =~ /<DNS_Server_2>(.+)<\/DNS_Server_2>/)
          {
            $hash->{DNS_SERVER_2} = $1;
          }
          if($data =~ /<MAC_Address>(.+)<\/MAC_Address>/)
          {
            $hash->{MAC_ADDRESS} = $1;
            # Add ':' after every two chars
            $hash->{MAC_ADDRESS} =~ s/\w{2}\B/$&:/g;
          }            
        }
        elsif($arg eq "tunerPresetFM")
        {
          {
            # May be also an empty string <Item_#></Item_#>
            for (my $i = 1; $i < 31; $i++)
            {
              if ($data =~ /<Item_$i><\/Item_$i>/)
              {
                readingsBulkUpdate($hash, sprintf("tunerPresetFMItem_%02d", $i), "No Preset");
              }
              elsif($data =~ /<Item_$i>(.+?)<\/Item_$i>/)
              {
                readingsBulkUpdate($hash, sprintf("tunerPresetFMItem_%02d", $i), $1);
              }                        
            }          
          }           
        }
        elsif($arg eq "tunerPresetDAB")
        {
          # May be also an empty string <Item_#></Item_#>
          for (my $i = 1; $i < 31; $i++)
          {
            if ($data =~ /<Item_$i><\/Item_$i>/)
            {
              readingsBulkUpdate($hash, sprintf("tunerPresetDABItem_%02d", $i), "No Preset");
            }
            elsif($data =~ /<Item_$i>(.+?)<\/Item_$i>/)
            {
              readingsBulkUpdate($hash, sprintf("tunerPresetDABItem_%02d", $i), $1);
            }                        
          }          
        }
        elsif ($arg eq "mediaRendererDesc")
        {
          if($data =~ /<friendlyName>(.+)<\/friendlyName>/)
          {
            $hash->{FRIENDLY_NAME} = $1;
          }
          
          if($data =~ /<UDN>(.+)<\/UDN>/)
          {
            $hash->{UNIQUE_DEVICE_NAME} = $1;
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
            my $address = $hash->{helper}{ADDRESS};
            my $i = 1;
            
            while ($data =~ /<url>(.+?)<\/url>/g)
            {
              $hash->{"NP_ICON_$i"} = "http://".$address.":8080".$1;            
              $i++;
            }
          }
        }
      }
      elsif($cmd eq "on")
      {
        if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
        {
          # As the NP startup takes about 5 seconds, the status will be already set, if the return code of the command is 0.
          readingsBulkUpdate($hash, "power", "on");
          readingsBulkUpdate($hash, "state","on");
          
          readingsEndUpdate($hash, 1);
          
          YAMAHA_NP_ResetTimer($hash, 5);
          
          return;
        }
      }
      elsif($cmd eq "off")
      {
        if($data =~ /RC="0"/ and $data =~ /<Power><\/Power>/)
        {
          readingsBulkUpdate($hash, "power", "off");
          readingsBulkUpdate($hash, "state","off");
          
          readingsEndUpdate($hash, 1);
          
          YAMAHA_NP_ResetTimer($hash, 3);
          
          return;
        }
      }
      elsif($cmd eq "mute")
      {
        if($data =~ /RC="0"/)
        {
          readingsBulkUpdate($hash, "mute", $arg);
        }
      }
      elsif($cmd eq "volume" or $cmd eq "volumeStraight" or $cmd eq "volumeUp" or $cmd eq "volumeDown")
      {        
        if($data =~ /RC="0"/)
        {
          readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
          readingsBulkUpdate($hash, "volume", YAMAHA_NP_volume_abs2rel($hash, $hash->{helper}{targetVolume}));
          # New "volume"value: The CRX-N560D cannot provide the current volume in time after a volume change.
          # Therefore updated locally.          
          # Volume will be updated during the next timer loop.
        }
      }
      
      readingsEndUpdate($hash, 1);
      
      YAMAHA_NP_ResetTimer($hash, 0) if($cmd ne "statusRequest" and $cmd ne "on" and $cmd ne "volume");
    }
    return;
}

#############################
# Converts all Values to FHEM usable command lists
sub YAMAHA_NP_Param2Fhem
{
  my ($param, $replace_pipes) = @_;
  
  $param =~ s/\s+//g;
  $param =~ s/,//g;
  $param =~ s/_//g;
  $param =~ s/\(/_/g;
  $param =~ s/\)//g;
  $param =~ s/\|/,/g if($replace_pipes == 1);

  return lc $param;
}

#############################
# Returns the Yamaha Parameter Name for the FHEM like equivalent
sub YAMAHA_NP_getParamName
{
  my ($hash, $name, $list) = @_;
  
  return if(not defined($list));

  my @commands = split("\\|",  $list);

  foreach my $item (@commands)
  {
    if(YAMAHA_NP_Param2Fhem($item, 0) eq $name)
    {
      return $item;
    }
  }    
  return;
}

#############################
# queries the NP model, system-id and version
sub YAMAHA_NP_getModel
{
  my ($hash) = @_;

  YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>", "statusRequest","systemConfig");
  YAMAHA_NP_getMediaRendererDesc($hash);
  return;
}	

#############################
# queries the addition model descriptions
sub YAMAHA_NP_getMediaRendererDesc
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $address = $hash->{helper}{ADDRESS};
  
  Log3 $name, 5, "YAMAHA_NP ($name) - execute nonblocking \"MediaRendererDesc\"";
      
  HttpUtils_NonblockingGet
  ({
    url        => "http://".$address.":8080/MediaRenderer/desc.xml",
    timeout    => AttrVal($name, "request-timeout", 4),
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

#############################
# converts straight volume in percentage volume (volumestraightmin .. volumestraightmax => 0 .. 100%)
sub YAMAHA_NP_volume_rel2abs
{
  my ($hash, $percentage) = @_;
  
  return int(($percentage * $hash->{helper}{VOLUMESTRAIGHTMAX} / 100 ));
}

#############################
# converts percentage volume in decibel volume (0 .. 100% => volumestraightmin .. volumestraightmax)
sub YAMAHA_NP_volume_abs2rel
{
  my ($hash, $absolute) = @_;	
  
  # Prevent division by 0
  if (defined($hash->{helper}{VOLUMESTRAIGHTMAX}) and $hash->{helper}{VOLUMESTRAIGHTMAX} ne "0")
  {
    return int($absolute * 100 / int($hash->{helper}{VOLUMESTRAIGHTMAX}));
  }
  else
  {
    return int(0)
  }  
}

#############################
# queries all available inputs
sub YAMAHA_NP_getInputs
{
  my ($hash) = @_;  
  my $name = $hash->{NAME};
  my $address = $hash->{helper}{ADDRESS};

  # query all inputs
  YAMAHA_NP_SendCommand($hash, "<YAMAHA_AV cmd=\"GET\"><System><Config>GetParam</Config></System></YAMAHA_AV>", "statusRequest","getInputs");
  return;
}

#############################
# Restarts the internal status request timer according to the given interval or current receiver state
sub YAMAHA_NP_ResetTimer
{
  my ($hash, $interval) = @_;

  RemoveInternalTimer($hash);

  if($hash->{helper}{DISABLED} == 0)
  {
    if(defined($interval))
    {
      InternalTimer(gettimeofday()+$interval, "YAMAHA_NP_GetStatus", $hash, 0);
    }
    elsif((exists($hash->{READINGS}{presence}{VAL}) and $hash->{READINGS}{presence}{VAL} eq "present") and (exists($hash->{READINGS}{power}{VAL}) and $hash->{READINGS}{power}{VAL} eq "on"))
    {
      InternalTimer(gettimeofday() + $hash->{helper}{ON_INTERVAL}, "YAMAHA_NP_GetStatus", $hash, 0);
    }
    else
    {
      InternalTimer(gettimeofday() + $hash->{helper}{OFF_INTERVAL}, "YAMAHA_NP_GetStatus", $hash, 0);
    }
  }  
  return;
}

#############################
# convert all HTML entities into UTF-8 equivalent
sub YAMAHA_NP_html2txt
{
  my ($string) = @_;

  $string =~ s/&quot;/\"/g;
  $string =~ s/&amp;/&/g;
  $string =~ s/&amp;/&/g;
  $string =~ s/&nbsp;/ /g;
  $string =~ s/&apos;/'/g;
  $string =~ s/(\xe4|&auml;)/ä/g;
  $string =~ s/(\xc4|&Auml;)/Ä/g;
  $string =~ s/(\xf6|&ouml;)/ö/g;
  $string =~ s/(\xd6|&Ouml;)/Ö/g;
  $string =~ s/(\xfc|&uuml;)/ü/g;
  $string =~ s/(\xdc|&Uuml;)/Ü/g;
  $string =~ s/(\xdf|&szlig;)/ß/g;

  $string =~ s/<.+?>//g;
  $string =~ s/(^\s+|\s+$)//g;

  return $string;
}

1;

=pod
=begin html

<a name="YAMAHA_NP"></a>
<h3>YAMAHA_NP</h3>
<ul>
  <a name="YAMAHA_NPdefine"></a>
  <b>Define</b>
  <br><br>
  <ul>
    <code>
      define &lt;name&gt; YAMAHA_NP &lt;ip-address&gt; [&lt;status_interval&gt;]<br><br>
      define &lt;name&gt; YAMAHA_NP &lt;ip-address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>
    This module controls a Yamaha Network Player (such as CRX-N560, CRX-N560D, CD-N500 or NP-S2000) via Ethernet.
    Theoretically, any device understanding the communication protocol of the Yamaha Network Player App should work. 
    <br><br>
    Currently implemented features:
    <br><br>
    <ul>
      <li>Power on/off</li>
      <li>Timer on/off</li>
      <li>Input selection</li>
      <li>Timer on/off</li>
      <li>Volume +/-</li>
      <li>Mute on/off</li>
      <li>System Clock Update</li>
      <li>Tuner: tune +/-, preset +/-, Station information (FM/DAB)</li>
      <li>Stand-by mode: eco/normal</li>
      <li>Player (play, stop, next, prev, shuffle, repeat)</li>
      <li>...</li>
    </ul>
    <br>
    Defining a YAMAHA_NP device will schedule an internal task (interval can be set
    with optional parameters &lt;off_status_interval&gt; and &lt;on_status_interval&gt; in seconds.<br>
    &lt;off_status_interval&gt; is a parameter used in case the device is powered off or not available.<br>
    &lt;on_status_interval&gt; is a parameter used in case the device is powered on.<br>
    If both parameters are unset, a default value 30 (seconds) for both is used.<br>
    If &lt;off_status_interval&gt; is set only the same value is used for both parameters.
    <br>
    The internal task periodically reads the status of the Network Player (power state, selected
    input, volume and mute status etc.) and triggers notify/filelog commands.
    <br><br>    
    Example:<br><br>
    <ul><br>
      Add the following code into the <b>fhem.cfg</b> configuration file and restart fhem:<br><br>
      <code>
      define NP_Player YAMAHA_NP 192.168.0.15<br>
      attr NP_player webCmd input:volume:mute:volumeDown:volumeUp<br><br>
      # With custom status interval of 60 seconds<br>
      define NP_Player YAMAHA_NP 192.168.0.15 <b>60</b><br>
      attr NP_player webCmd input:volume:mute:volumeDown:volumeUp<br><br>
      # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
      define NP_Player YAMAHA_NP 192.168.0.15 <b>60 10</b><br>
      attr NP_player webCmd input:volume:mute:volumeDown:volumeUp
      </code>
    </ul>   
  </ul>
  <br><br>
  <a name="YAMAHA_NPset"></a>
  <b>Set</b>
  <ul>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code><br><br>
    Currently, the following commands are defined.<br>
    The available inputs are depending on the used network player.
    The module offers only available inputs.<br><br>
    <i>Note: Commands and parameters are case sensitive.</i><br>
      <ul><br><br>
      <u>Available commands:</u><br><br>
      <li><b>cdTray</b>&nbsp;&nbsp;-&nbsp;&nbsp; open/close the CD tray.</li>
      <li><b>clockUpdate</b>&nbsp;&nbsp;-&nbsp;&nbsp; updates the system clock with current time. The time information is taken from the FHEM server.</li>
      <li><b>input</b> [&lt;parameter&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; selects the input channel. The inputs are read dynamically from the device. Available inputs can be set (e.g. cd, tuner, aux1, aux2, ...).</li>
      <li><b>mute</b> [on|off] &nbsp;&nbsp;-&nbsp;&nbsp; activates/deactivates muting</li>
      <li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; shuts down the device </li>
      <li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device</li>
      <li><b>player [&lt;parameter&gt;] </b> &nbsp;&nbsp;-&nbsp;&nbsp; sets player related commands.</li>
      <ul>
        <li><b>play</b>&nbsp;&nbsp;-&nbsp;&nbsp; play.</li>
        <li><b>stop</b>&nbsp;&nbsp;-&nbsp;&nbsp; stop.</li>
        <li><b>pause</b>&nbsp;&nbsp;-&nbsp;&nbsp; pause.</li>
        <li><b>next</b>&nbsp;&nbsp;-&nbsp;&nbsp; next item.</li>
        <li><b>prev</b>&nbsp;&nbsp;-&nbsp;&nbsp; previous item.</li>
        <li><b>shuffleToggle</b>&nbsp;&nbsp;-&nbsp;&nbsp; Toggles the shuffle mode.</li>
        <li><b>repeatToggle</b>&nbsp;&nbsp;-&nbsp;&nbsp; Toggles the repeat modes.</li>
      </ul>
      <li><b>sleep</b> [off|30min|60min|90min|120min] &nbsp;&nbsp;-&nbsp;&nbsp; activates the internal sleep timer</li>
      <li><b>standbyMode</b> [eco|normal] &nbsp;&nbsp;-&nbsp;&nbsp; set the standby mode.</li>
      <li><b>statusRequest [&lt;parameter&gt;] </b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
      <ul>
        <b><li>systemConfig</b>&nbsp;&nbsp;-&nbsp;&nbsp; requests the system configuration</li>
        <li><b>basicStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; requests the basic status such as volume input etc.</li>
        <li><b>playerStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; requests the player status such as play status, song info, artist info etc.</li>
        <li><b>tunerStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; requests the tuner status such as FM frequency, preset number, DAB information etc.</li>
        <li><b>timerStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; requests device's internal wake-up timer status</li>
        <li><b>networkInfo</b>&nbsp;&nbsp;-&nbsp;&nbsp; requests device's network related information such as IP, Gateway, MAC address etc.</li>
      </ul>
      <li><b>timerHour</b> [0...23] &nbsp;&nbsp;-&nbsp;&nbsp; sets hour of device's internal wake-up timer</li>
      <li><b>timerMinute</b> [0...59] &nbsp;&nbsp;-&nbsp;&nbsp; sets minutes of device's internal wake-up timer</li>
      <li><b>timerRepeat</b> [once|every] &nbsp;&nbsp;-&nbsp;&nbsp; sets repetition mode of device's internal wake-up timer</li>
      <li><b>timerVolume</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; sets volume of device's internal wake-up timer</li>
      <li><b>timer</b> [on|off] &nbsp;&nbsp;-&nbsp;&nbsp; sets device's internal wake-up timer. <i>(Note: before timer activation timerHour, timerMinute, timerRepeat and timerVolume must be set.)</i></li>
      <li><b>tuner [&lt;parameter&gt;] </b> &nbsp;&nbsp;-&nbsp;&nbsp; sets tuner related commands.</li>
      <ul>
        <li><b>bandDAB</b>&nbsp;&nbsp;-&nbsp;&nbsp; sets the tuner band to DAB (if available).</li>
        <li><b>bandFM</b>&nbsp;&nbsp;-&nbsp;&nbsp; sets the tuner band to FM.</li>
        <li><b>tuneUp</b>&nbsp;&nbsp;-&nbsp;&nbsp; tuner tune up.</li>
        <li><b>tuneDown</b>&nbsp;&nbsp;-&nbsp;&nbsp; tuner tune down.</li>
        <li><b>presetUp</b>&nbsp;&nbsp;-&nbsp;&nbsp; tuner preset up.</li>
        <li><b>presetDown</b>&nbsp;&nbsp;-&nbsp;&nbsp; tuner preset down.</li>
      </ul>
      <li><b>tunerPresetDAB</b> [1...30] &nbsp;&nbsp;-&nbsp;&nbsp; Sets the DAB preset.</li>
      <li><b>tunerPresetFM</b> [1...30] &nbsp;&nbsp;-&nbsp;&nbsp; Sets the FM preset.</li>
      <li><b>volume</b> [0...100] &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in &#037;</li>
      <li><b>volumeStraight</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; set the volume as used and displayed in the device. &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; are read and set from the device automatically.</li>
      <li><b>volumeUp</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume by one device's absolute step. &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; are read and set from the device automatically.</li>
      <li><b>volumeDown</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume by one device's absolute step. &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; are read and set from the device automatically.</li>
    </ul><br><br>

    A typical example is powering the device remotely and tuning the favourite radio station:<br><br>
    Add the following code into the <b>fhem.cfg</b> configuration file:<br><br><br>
    <ul>
      <code>
        define NP_player YAMAHA_NP 192.168.0.15 30 5<br>
        attr NP_player webCmd input:volume:mute:volumeDown:volumeUp
      </code>
    </ul><br><br>
    Add the following code into the <b>99_MyUtils.pm</b> file:<br><br>
    <ul>
      <code>
        sub startMyFavouriteRadioStation()<br>
        {<br>
          &nbsp;&nbsp;fhem "set NP_player on";<br>
          &nbsp;&nbsp;sleep 1;<br>
          &nbsp;&nbsp;fhem "set NP_player input tuner";<br>
          &nbsp;&nbsp;sleep 1;<br>
          &nbsp;&nbsp;fhem "set NP_player tunerPresetDAB 1";<br>
          &nbsp;&nbsp;sleep 1;<br>
          &nbsp;&nbsp;fhem "set NP_player volume 30";<br>
        }
      </code>
    </ul>
    <br><br>
    It's a good idea to insert a 'sleep' instruction between each fhem commands due to internal processing time of the network player. During that time the following commands might be ignored...<br><br>

    Now the function can be called by typing the following line in the FHEM command line or by the notify-definitions:<br><br>
    <ul>
      <code>
        {startMyFavouriteRadioStation()}<br><br>
      </code>
    </ul>
  </ul>
  <a name="YAMAHA_NPget"></a>
  <b>Get</b>
  <ul>
    <code>
      get &lt;name&gt; &lt;reading&gt;
    </code>
    <br><br>
    Currently, the 'get' command returns reading values only. For a specific list of possible values, see section <b>"Generated Readings"</b>.<br><br>
  </ul>
  <a name="YAMAHA_NPattr"></a>
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
  <b>Readings</b><br>
  <ul>
    <ul>
      <br><br><u>Basic readings:</u><br><br>
      <li><b>input</b> - The selected input source according to the FHEM input commands</li>
      <li><b>mute</b> - Reports the mute status of the receiver (on|off)</li>
      <li><b>power</b> - Reports the power status of the receiver (on|off)</li>
      <li><b>presence</b> - Reports the presence status of the receiver or zone (absent|present). <i>Note: In case of "absent", the device cannot be controlled by FHEM. Check standbyMode.</i></li>
      <li><b>volume</b> - Reports the current volume level of the receiver in &#037; (0...100&#037;)</li>
      <li><b>volumeStraight</b> - Reports the current volume level of the receiver as used and displayed in the device (values device specific)</li>
      <li><b>sleep</b> - Reports the current sleep timer status (30min|60min|90min|120min|off).</li>
      <li><b>state</b> - Reports the current power state and an absence of the device (on|off|absent)</li>
      <br><br><u>Player related readings:</u><br><br>
      <li><b>playerPlaybackInfo</b> - Reports current player state (play|stop|pause).</li>
      <li><b>playerDeviceType</b> - Reports the device type (ipod|msc).</li>
      <li><b>playerIpodMode</b> - Reports the Ipod Mode (normal|off)</li>
      <li><b>playerRepeat</b> - Reports the Repeat Mode (one|off)</li>
      <li><b>playerShuffle</b> - Reports the Shuffle Mode (on|off)</li>
      <li><b>playerPlayTime</b> - Reports the play time of the currently played audio (HH:MM:SS).</li>
      <li><b>playerTrackNumber</b> - Reports the track number of the currently played audio.</li>
      <li><b>playerTotalTracks</b> - Reports the total number of tracks for playing.</li>
      <li><b>playerArtist</b> - Reports the artist (if available) of the currently played audio.</li>
      <li><b>playerAlbum</b> - Reports the album (if available) of the currently played audio.</li>
      <li><b>playerSong</b> - Reports the song name (if available) of the currently played audio.</li>
      <li><b>playerAlbumArtURL</b> - Reports the album art url (if available) of the currently played audio. The URL points to the network player.</li>
      <li><b>playerAlbumArtID</b> - Reports the album art ID (if available) of the currently played audio.</li>
      <li><b>playerAlbumArtFormat</b> - Reports the album art format (if available) of the currently played audio.</li>
      <br><br><u>Tuner related readings:</u><br><br>
      <li><b>tunerAudioModeDAB</b> - Reports current audio mode (Mono|Stereo).</li>
      <li><b>tunerBand</b> - Reports the currently selected tuner band (FM|DAB). DAB if available.</li>
      <li><b>tunerBitRateDAB</b> - Reports current DAB stream bit rate (kbit/s).</li>
      <li><b>tunerPresetFM</b> - Reports the currently selected FM preset. If stored as such (1...30).</li>
      <li><b>tunerFrequencyDAB</b> - Reports the currently tuned DAB frequency. (xxx.xxx MHz)</li>
      <li><b>tunerFrequencyFM</b> - Reports the currently tuned FM frequency. (xxx.xx MHz)</li>
      <li><b>tunerModeDAB</b> - Reports current DAB audio mode (Mono|Stereo).</li>
      <li><b>tunerProgramServiceFM</b> - Reports the FM service name.</li>
      <li><b>tunerRadioTextAFM</b> - Reports the Radio Text A of the selected FM service.</li>
      <li><b>tunerRadioTextBFM</b> - Reports the Radio Text B of the selected FM service.</li>
      <li><b>tunerPresetDAB</b> - Reports the currently selected DAB preset. If stored as such (1...30).</li>
      <li><b>tunerServiceLabelDAB</b> - Reports the service label of the selected DAB service.</li>
      <li><b>tunerChannelLabelDAB</b> - Reports the channel label of the selected DAB service.</li>
      <li><b>tunerDLSDAB</b> - Reports the dynamic label segment of the selected DAB service.</li>
      <li><b>tunerEnsembleLabelDAB</b> - Reports the ensemble label of the selected DAB service.</li>
      <br><br><u>Timer related readings:</u><br><br>
      <li><b>timer</b> - Reports the time mode (on|off).</li>
      <li><b>timerRepeat</b> - Reports the timer repeat mode (once|every).</li>
      <li><b>timerStartTime</b> - Reports the timer start time (HH:MM).</li>
      <li><b>timerVolumeLevel</b> - Reports the timer volume level.</li>  
    </ul>
  </ul><br>
  <b>Implementer's note</b><br><br>
    <ul>
    Trivial: In order to use that module the network player must be connected to the Ethernet.<br>
    The device must be in standbyMode "Normal" in order to power on.<br>
    However, even if the standbyMode is set to "Eco" the device can be powered off. In that case it has to be switched on manually.<br>
    </ul><br>
</ul>
=end html
=begin html_DE

<a name="YAMAHA_NP"></a>
<h3>YAMAHA_NP</h3>
<ul>
  <a name="YAMAHA_NPdefine"></a>
  <b>Define</b><br><br>
  <ul>
    <code>
      define &lt;name&gt; YAMAHA_NP &lt;ip-address&gt; [&lt;status_interval&gt;]<br><br>
      define &lt;name&gt; YAMAHA_NP &lt;ip-address&gt; [&lt;off_status_interval&gt;] [&lt;on_status_interval&gt;]
    </code>
    <br><br>
    Mit Hilfe dieses Moduls lassen sich Yamaha Network Player (z.B. CRX-N560, CRX-N560D, CD-N500 or NP-S2000) via Ethernet steuern.<br>
    Theoretisch sollten alle Ger&auml;te, die mit der Yamaha Network Player App kompatibel sind, bedient werden k&ouml;nnen.<br><br>
    Die aktuelle Implementierung erm&ouml;glicht u.a. den folgenden Funktionsumfang:<br><br>
    <ul>
      <li>Power on/off</li>
      <li>Timer on/off</li>
      <li>Input selection</li>
      <li>Timer on/off</li>
      <li>Volume +/-</li>
      <li>Mute on/off</li>
      <li>System Clock Update</li>
      <li>Tuner: tune +/-, preset +/-, Senderinformation (FM/DAB)</li>
      <li>Stand-by mode: eco/normal</li>
      <li>Player (play, stop, next, prev, shuffle, repeat)</li>
      <li>...</li>
    </ul>
    <br>
    Eine YAMAHA_NP Definition initiiert einen internen Task, der von FHEM zyklisch abgearbeitet wird.<br>
    Das Intervall (in Sekunden) kann f&uuml;r die Zust&auml;nde &lt;on_status_interval&gt; und &lt;off_status_interval&gt; optional gesetzt werden.<br>
    &lt;off_status_interval&gt; steht f&uuml;r das Intervall, wenn das Ger&auml;t ausgeschaltet/abwesend ist.<br>
    &lt;on_status_interval&gt; steht f&uuml;r das Intervall, wenn das Ger&auml;t eingeschaltet/verf&uuml;gbar ist.<br>
    Wenn keine Parametere angegeben wurden, wird ein Default-Wert von 30 Sekunden für beide gesetzt.<br>
    Wenn nur &lt;off_status_interval&gt; gesetzt wird, gilt dieser Wert f&uuml;r beide Zust&auml;nde (eingeschaltet/ausgeschaltet).<br>
    Der Task liest zyklisch grundlegende Parameter vom Network Player wie z.B. (Power-Status , gew&auml;hlter Eingang, Lautst&auml;rke etc.) und triggert notify/filelog Befehle.<br><br>    
    Beispiel:<br><br>
    <ul><br>
      Definition in der <b>fhem.cfg</b> Konfigurationsdatei:<br><br>
      <code>
        define NP_Player YAMAHA_NP 192.168.0.15<br>
        attr NP_player webCmd input:volume:mute:volumeDown:volumeUp<br><br>
        # 60 Sekunden Intervall<br>
        define NP_Player YAMAHA_NP 192.168.0.15 <b>60</b><br>
        attr NP_player webCmd input:volume:mute:volumeDown:volumeUp<br><br>
        # 60 Sekunden Intervall f&uuml;r "off" und 10 Sekunden f&uuml;r "on"<br>
        define NP_Player YAMAHA_NP 192.168.0.15 <b>60 10</b><br>
        attr NP_player webCmd input:volume:mute:volumeDown:volumeUp
      </code>
    </ul>   
  </ul><br><br>
  <a name="YAMAHA_NPset"></a>
  <b>Set</b>
  <ul>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code>
    <br><br>
    Aktuell sind folgende Befehle implementiert:<br>
    Die verf&uuml;gbaren Eing&auml;nge des Network Players werden vom diesem gelesen und dynamisch in FHEM angepasst.<br><br>
    <i>Bemerkung: Bitte bei den Befehlen und Parametern die Gro&szlig;- und Kleinschreibung beachten.</i><br><br>
    <ul><br><br>
      <u>Verf&uuml;gbare Befehle:</u><br><br>
      <li><b>cdTray</b>&nbsp;&nbsp;-&nbsp;&nbsp; &Ouml;ffnen und Schlie&szlig;en des CD-Fachs.</li>
      <li><b>clockUpdate</b>&nbsp;&nbsp;-&nbsp;&nbsp; Aktualisierung der Systemzeit des Network Players. Die Zeitinformation wird von dem FHEM Server bezogen, auf dem das Modul ausgef&uuml;hrt wird.</li>
      <li><b>input</b> [&lt;parameter&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; Auswahl des Eingangs des NP. Der aktive Eingang wird vom Ger&auml;t gelesen und in FHEM dynamisch dargestellt (z.B. cd, tuner, aux1, aux2, ...).</li>
      <li><b>mute</b> [on|off] &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert/Deaktiviert die Stummschaltung.</li>
      <li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; Network Player ausschalten.</li>
      <li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; Network Player einschalten.</li>
      <li><b>player [&lt;parameter&gt;] </b> &nbsp;&nbsp;-&nbsp;&nbsp; Setzt Player relevante Befehle.</li>
      <ul>
        <li><b>play</b>&nbsp;&nbsp;-&nbsp;&nbsp; play.</li>
        <li><b>stop</b>&nbsp;&nbsp;-&nbsp;&nbsp; stop.</li>
        <li><b>pause</b>&nbsp;&nbsp;-&nbsp;&nbsp; pause.</li>
        <li><b>next</b>&nbsp;&nbsp;-&nbsp;&nbsp; n&auml;chstes Audiost&uuml;ck.</li>
        <li><b>prev</b>&nbsp;&nbsp;-&nbsp;&nbsp; vorheriges Audiost&uuml;ck.</li>
        <li><b>shuffleToggle</b>&nbsp;&nbsp;-&nbsp;&nbsp; Umschaltung des Zufallswiedergabe.</li>
        <li><b>repeatToggle</b>&nbsp;&nbsp;-&nbsp;&nbsp; Umschaltung des Wiederholungsmodes.</li>
      </ul>
      <li><b>sleep</b> [off|30min|60min|90min|120min] &nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert/Deaktiviert den internen Sleep-Timer</li>
      <li><b>standbyMode</b> [eco|normal] &nbsp;&nbsp;-&nbsp;&nbsp; Umschaltung des Standby Modus.</li>
      <li><b>statusRequest [&lt;parameter&gt;] </b> &nbsp;&nbsp;-&nbsp;&nbsp; Abfrage des aktuellen Status des Network Players.</li>
      <ul>
        <b><li>systemConfig</b>&nbsp;&nbsp;-&nbsp;&nbsp; Abfrage der Systemkonfiguration.</li>
        <li><b>basicStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; Abfrage der Elementarparameter (z.B. Lautst&auml;rke, Eingang, etc.)</li>
        <li><b>playerStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; Abfrage des Player-Status.</li>
        <li><b>tunerStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; Abfrage des Tuner-Status (z.B. FM Frequenz, Preset-Nummer, DAB Information etc.)</li>
        <li><b>timerStatus</b>&nbsp;&nbsp;-&nbsp;&nbsp; Abfrage des internen Wake-up timers.</li>
        <li><b>networkInfo</b>&nbsp;&nbsp;-&nbsp;&nbsp; Abfrage von Netzwerk-relevanten Informationen (z.B: IP-Adresse, Gateway-Adresse, MAC-address etc.)</li>
      </ul>
      <li><b>timerHour</b> [0...23] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Stunde des internen Wake-up Timers</li>
      <li><b>timerMinute</b> [0...59] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Minute des internen Wake-up Timers</li>
      <li><b>timerRepeat</b> [once|every] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt den Wiederholungsmodus des internen Wake-up Timers</li>
      <li><b>timerVolume</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die Lautst&auml;rke des internen Wake-up Timers</li>
      <li><b>timer</b> [on|off] &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet ein/aus den internen Wake-up Timer. <i>(Bemerkung: Bevor der Wake-Up Timer gesetzt werden kann, m&uuml;ssen timerHour, timerMinute, timerRepeat and timerVolume zuvor gesetzt werden.)</i></li>
      <li><b>tuner [&lt;parameter&gt;] </b> &nbsp;&nbsp;-&nbsp;&nbsp; Tuner-relevante Befehle.</li>
      <ul>
        <li><b>bandDAB</b>&nbsp;&nbsp;-&nbsp;&nbsp; Setzt das Tuner-Band auf DAB (falls verf&uuml;gbar).</li>
        <li><b>bandFM</b>&nbsp;&nbsp;-&nbsp;&nbsp; Setzt das Tuner-Band auf FM.</li>
        <li><b>tuneUp</b>&nbsp;&nbsp;-&nbsp;&nbsp; Tuner Frequenz +.</li>
        <li><b>tuneDown</b>&nbsp;&nbsp;-&nbsp;&nbsp; Tuner Frquenz -.</li>
        <li><b>presetUp</b>&nbsp;&nbsp;-&nbsp;&nbsp; Tuner Voreinstellung hoch.</li>
        <li><b>presetDown</b>&nbsp;&nbsp;-&nbsp;&nbsp; Tuner Voreinstellung runter.</li>
      </ul>
      <li><b>tunerPresetDAB</b> [1...30] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die DAB Voreinstellung.</li>
      <li><b>tunerPresetFM</b> [1...30] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die FM Voreinstellung.</li>
      <li><b>volume</b> [0...100] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt den Lautst&auml;rkepegel in &#037;</li>
      <li><b>volumeStraight</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; Setzt die absolute Lautst&auml;rke wie vom Ger&auml;t benutzt und angezeigt. Die Parameter &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; werden automatisch ermittelt.</li>
      <li><b>volumeUp</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; Erh&ouml;ht die Lautst&auml;rke um einen absoluten Schritt. Die Parameter &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; werden automatisch ermittelt.</li>
      <li><b>volumeDown</b> [&lt;VOL_MIN&gt;...&lt;VOL_MAX&gt;] &nbsp;&nbsp;-&nbsp;&nbsp; Reduziert die Lautst&auml;rke um einen absoluten Schritt. Die Parameter &lt;VOL_MIN&gt; and &lt;VOL_MAX&gt; werden automatisch ermittelt.</li>
      </ul><br><br>
      Ein typisches Beispiel ist das Einschalten des Ger&auml;tes und das Umschalten auf den Lieblingsradiosender:<br><br>
      Beispieldefinition in der <b>fhem.cfg</b> Konfigurationsdatei:<br><br><br>
      <ul>
        <code>
          define NP_player YAMAHA_NP 192.168.0.15 30 5<br>
          attr NP_player webCmd input:volume:mute:volumeDown:volumeUp
        </code>
      </ul><br><br>
      Folgender Code kann anschlie&szlig;end in die Datei <b>99_MyUtils.pm</b> eingebunden werden:<br><br>
      <ul>
        <code>
          sub startMyFavouriteRadioStation()<br>
          {<br>
            &nbsp;&nbsp;fhem "set NP_player on";<br>
            &nbsp;&nbsp;sleep 1;<br>
            &nbsp;&nbsp;fhem "set NP_player input tuner";<br>
            &nbsp;&nbsp;sleep 1;<br>
            &nbsp;&nbsp;fhem "set NP_player tunerPresetDAB 1";<br>
            &nbsp;&nbsp;sleep 1;<br>
            &nbsp;&nbsp;fhem "set NP_player volume 30";<br>
          }
        </code>
      </ul><br><br>
      <i>Bemerkung: Aufgrund der relativ langsamen Befehlsverarbeitung im Network Player im Vergleich zur asynchronen Ethernet-Kommunikation, kann es vorkommen, dass veraltete Statusinformationen zur&uuml;ckgesendet werden.<br>
      Aus diesem Grund wird empfohlen, w&auml;hrend der Automatisierung zwischen den 'set' und 'get' Befehlen ein Delay einzubauen. Speziell beim Hochfahren des Network Players sollte dies beachtet werden.</i><br><br>
      Die Funktion kann jetzt in der FHEM Befehlszeile eingegeben oder in die Notify-Definitionen eingebunden werden.<br><br>
      <ul>
        <code>
          {startMyFavouriteRadioStation()}<br><br>
        </code>
      </ul>
    </ul>
    <a name="YAMAHA_NPget"></a>
    <b>Get</b>
    <code>
      get &lt;name&gt; &lt;reading&gt;
    </code><br><br>
    Aktuell liefert der Befehl 'get' ausschlie&szlig;lich Reading-Werte (s. Abschnitt <b>"Readings"</b>).<br><br>
  </ul>
  <a name="YAMAHA_NPattr"></a>
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
    <b>Readings</b><br>
    <ul>
      <ul>
        <br><br><u>Elementar-Readings:</u><br><br>
        <li><b>input</b> - Aktivierter Eingang.</li>
        <li><b>mute</b> - Abfrage des Mute Status (on|off)</li>
        <li><b>power</b> - Abfrage des Power-Status (on|off)</li>
        <li><b>presence</b> - Abfrage der Ger&auml;teanwesenheit im Netzwerk (absent|present). <i>Bemerkung: Falls abwesend ("absent"), l&auml;sst sich das Ger&auml;t nicht fernbedienen.</i></li>
        <li><b>volume</b> - Abfrage der aktuell eingestellten Lautst&auml;rke in &#037; (0...100&#037;)</li>
        <li><b>volumeStraight</b> - Abfrage der aktuellen absoluten Ger&auml;telautst&auml;rke im Ger&auml;t (ger&auml;tespezifisch)</li>
        <li><b>sleep</b> - Abfrage des Sleep-Timer Status (30min|60min|90min|120min|off).</li>
        <li><b>state</b> - Abfrage des aktuellen Power Zustands und Anwesenheit (on|off|absent).</li>
        <br><br><u>Player Readings:</u><br><br>
        <li><b>playerPlaybackInfo</b> - Abfrage des aktuellen Player Status (play|stop|pause).</li>
        <li><b>playerDeviceType</b> - Abfrage des Device Typs (ipod|msc).</li>
        <li><b>playerIpodMode</b> - Abfrage des *Pod/*Pad/*Phone Modus (normal|off)</li>
        <li><b>playerRepeat</b> - Abfrage des Wiederholungsmodus (one|all)</li>
        <li><b>playerShuffle</b> - Abfrage des Zufallswiedergabemodus (on|off)</li>
        <li><b>playerPlayTime</b> - Abfrage der aktuellen Spielzeit (HH:MM:SS).</li>
        <li><b>playerTrackNumber</b> - Abfrage der Audiotracknummer.</li>
        <li><b>playerTotalTracks</b> - Abfrage der Gesamtzahl der zu wiedergebenden Tracks.</li>
        <li><b>playerArtist</b> - Abfrage des K&uuml;nstler (Artist) (falls verf&uuml;gbar) der aktuellen Wiedergabe.</li>
        <li><b>playerAlbum</b> - Abfrage des Albumnamens (falls verf&uuml;gbar) der aktuellen Wiedergabe.</li>
        <li><b>playerSong</b> - Abfrage des Tracknamens (falls verf&uuml;gbar) der aktuellen Wiedergabe.</li>
        <li><b>playerAlbumArtURL</b> - Abfrage der Album URL (falls verf&uuml;gbar) der aktuellen Wiedergabe.</li>
        <li><b>playerAlbumArtID</b> - Abfrage der AlbumArtID (falls verf&uuml;gbar) der aktuellen Wiedergabe.</li>
        <li><b>playerAlbumArtFormat</b> - Abfrage des AlbumArt Formats (falls verf&uuml;gbar) der aktuellen Wiedergabe.</li>
        <br><br><u>Tuner Readings:</u><br><br>
        <li><b>tunerAudioModeDAB</b> - Abfrage des aktuellen DAB Audio-Modus (Mono|Stereo)..</li>
        <li><b>tunerBand</b> - Abfrage des aktuellen Radio-Bandes (FM|DAB). DAB falls verf&uuml;gbar.</li>
        <li><b>tunerBitRate</b> - Abfrage der aktuellen DAB Stream Bitrate (kbit/s).</li>
        <li><b>tunerModeDAB</b> - Abfrage des aktuellen DAB Modus (DAB|DAB+).</li>
        <li><b>tunerFrequencyDAB</b> - Abfrage der aktuellen DAB Frequenz. (xxx.xxx MHz)</li>
        <li><b>tunerPresetFM</b> - Abfrage der aktuellen FM Voreinstellung. Falls gespeichtert (1...30).</li>
        <li><b>tunerFrequencyFM</b> - Abfrage der aktuellen FM Frequenz. (xxx.xx MHz)</li>
        <li><b>tunerProgramServiceFM</b> - Abfrage des FM Sendernamen.</li>
        <li><b>tunerRadioTextAFM</b> - Abfrage des Radio Text A des FM Senders.</li>
        <li><b>tunerRadioTextBFM</b> - Abfrage des Radio Text B des FM Senders.</li>
        <li><b>tunerPresetDAB</b> - Abfrage der aktuellen DAB Voreinstellung. Falls gespeichtert (1...30).</li>
        <li><b>tunerServiceLabelDAB</b> - Abfrage des DAB Sendernamen.</li>
        <li><b>tunerChannelLabelDAB</b> - Abfrage des Channel Labels des gew&auml;hlten DAB Senders.</li>
        <li><b>tunerDLSDAB</b> - Abfrage des 'Dynamic Label Segment' des gew&auml;hlten DAB Senders.</li>
        <li><b>tunerEnsembleLabelDAB</b> - Abfrage des 'Ensemble Label' des gew&auml;hlten DAB Senders.</li>
        <br><br><u>Timer Readings:</u><br><br>
        <li><b>timer</b> - Abfrage des Time Modus (Wecker) (on|off).</li>
        <li><b>timerRepeat</b> - Abfrage des Timer Wiederholungs Modus (once|every).</li>
        <li><b>timerStartTime</b> - Abfrage der Timer Startzeit (HH:MM).</li>
        <li><b>timerVolumeLevel</b> - Abfrage der Timer-Lautst&auml;rke.</li>  
      </ul>
    </ul><br>
  <b>Bemerkung des Entwicklers</b><br><br>
  <ul>
    Trivial: Um das Ger&auml;t fernbedienen zu k&ouml;nnen, muss es an das Ethernet-Netzwerk angeschlossen und erreichbar sein.<br>
    Das Ger&auml;t muss sich im standbyMode "Normal" befinden, um es fergesteuert einzuschalten.<br>
    Das Abschalten funktioniert auch standbyMode "Normal" Modus.<br>
  </ul><br>
</ul>
=end html_DE
=cut

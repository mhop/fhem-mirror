# $Id$
##############################################################################
#
# 71_PHILIPS_AUDIO.pm
#
# An FHEM Perl module for controlling Philips Audio Equipment connected to
# local network such as MCi, Streamium and Fidelio devices.
# The module provides basic functionality accessible through the port 8889
# of the device: (http://<device_ip>:8889/index)
# e.g. AW9000, NP3500, NP3700, NP3900 
#
# Copyright by ra666ack
# (e-mail: ra666ack at g**glemail d*t c*m)
#
# This file is part of fhem.
#
# Fhem is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# Fhem is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday sleep);
use Time::Piece;
use POSIX qw{strftime};
use HttpUtils;

sub PHILIPS_AUDIO_Initialize
{
  my ($hash) = @_;

  $hash->{DefFn}     = "PHILIPS_AUDIO_Define";
  $hash->{GetFn}     = "PHILIPS_AUDIO_Get";
  $hash->{SetFn}     = "PHILIPS_AUDIO_Set";
  $hash->{AttrFn}    = "PHILIPS_AUDIO_Attr";
  $hash->{UndefFn}   = "PHILIPS_AUDIO_Undefine";

  $hash->{AttrList}  = "do_not_notify:0,1 ".
                       "disable:0,1 ".
                       "autoGetPresets:0,1 ".
                       "autoGetFavorites:0,1 ".
                       "httpBufferTimeout ".
                       "maxListItems ".
                       "model ".
                       "playerBrowsingTimeout ".
                       "requestTimeout ".
                       "$readingFnAttributes";
  return;
}

sub PHILIPS_AUDIO_GetStatus
{
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $power;

  $local = 0 unless(defined($local));

  return if((!defined($hash->{IP_ADDRESS})) or (!defined($hash->{helper}{OFF_INTERVAL})) or (!defined($hash->{helper}{ON_INTERVAL})));
  my $device = $hash->{IP_ADDRESS};
  
  # First run
  $hash->{helper}{networkRequest} = "idle"  if (not defined($hash->{helper}{networkRequest}));
  
  # Try to get additional info from the device.
  # Only if device already implemented.
  # Otherwise possible timeout due to wrong ports and device description links  
  if(not defined($hash->{helper}{dInfo}{UUID}))
  {
    if (grep {$_ eq $hash->{MODEL}} @{$hash->{helper}{DevDescImplementedModels}})
    {
      PHILIPS_AUDIO_getMediaRendererDesc($hash);
    }
  }
  
  if (not defined($hash->{helper}{playerState}))
  {
    # First run. Go to index.
    $hash->{helper}{playerState}   = "home";
    readingsSingleUpdate($hash, "playerState", "home", 1);
    PHILIPS_AUDIO_SendCommand($hash, "/index", "","home", "noArg");    
    PHILIPS_AUDIO_ResetTimer($hash); # getStatus
    return;
  }
  
  if($hash->{helper}{playerState} eq "home")  
  {
    # Check if device playing. Might by activated by the remote control or app.
    # If not, the device returns 'NOTHING';    
    PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "","nowplay", "noArg");
    
    # Heartbeat
    #PHILIPS_AUDIO_SendCommand($hash, "/HOMESTATUS", "","homestatus", "noArg");
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "input", "-");
    readingsBulkUpdate($hash, "playerState", "home");
    readingsBulkUpdate($hash, "playerPlaying", "no");
    readingsEndUpdate($hash, 1);
  }
  elsif($hash->{helper}{playerState} eq "browsing")
  {
    # Do nothing and check for inactivity duration
    
    $hash->{helper}{playerBrowsingTimeout} = 0 if(not defined ($hash->{helper}{playerBrowsingTimeout}));
    
    $hash->{helper}{playerBrowsingTimeout} += $hash->{helper}{ON_INTERVAL};
    
    # reset browsing state after 3 minutes inactivity in order to update the readings automatically again
    if($hash->{helper}{playerBrowsingTimeout} >= int(AttrVal($name, "playerBrowsingTimeout", 180))) 
    {
      $hash->{helper}{playerState} = "home";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "input", "-");
      readingsBulkUpdate($hash, "playerState", "home");
      readingsBulkUpdate($hash, "playerPlaying", "no");
      readingsEndUpdate($hash, 1);
      $hash->{helper}{playerBrowsingTimeout} = 0;
    }
  }
  elsif($hash->{helper}{playerState} eq "playing")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/ELAPSE", "","elapse", "noArg");    
  }
  
  # Check for Presets availability
  if
  (
    (not defined($hash->{READINGS}{"totalPresets"}))      and
    (ReadingsVal($name, "presence", "no")  eq "present")  and
    (AttrVal($name, "autoGetPresets", "0") eq "1")
  )
  {
	readingsSingleUpdate($hash, "Reading_presets" , "May take some time...", 1);
    # Hierarchichal navigation through the contents mandatory
    $hash->{helper}{cmdStep} = 1;    
    PHILIPS_AUDIO_SendCommand($hash, "/index", "", "getPresets", "noArg") if((ReadingsVal($name, "playerListStatus", "ready") eq "ready") and (ReadingsVal($name, "readingPresets", "no") eq "no"));    
    PHILIPS_AUDIO_ResetTimer($hash, 10); # Scan takes approx 8 sec.
    return;
  }
  
  # Check for Favorites availability
  if
  (
    (not defined($hash->{READINGS}{"totalFavorites"}))    and
    (ReadingsVal($name, "presence", "no")  eq "present")  and
    (AttrVal($name, "autoGetFavorites", "0") eq "1")
  )
  {
    readingsSingleUpdate($hash, "Reading_favorites" , "May take some time...", 1);
    # Hierarchichal navigation through the contents mandatory
    $hash->{helper}{cmdStep} = 1;    
    PHILIPS_AUDIO_SendCommand($hash, "/index", "", "getFavorites", "noArg") if((ReadingsVal($name, "playerListStatus", "ready") eq "ready") and (ReadingsVal($name, "readingFavorites", "no") eq "no"));    
    PHILIPS_AUDIO_ResetTimer($hash, 10); # Scan takes approx 8 sec.
    return;
  }
  
  PHILIPS_AUDIO_ResetTimer($hash) if(not ($local == 1)); # getStatus
  return;
}

sub PHILIPS_AUDIO_Get
{
  my ($hash, @a) = @_;
  my $what = $a[1];
  my $return;
  
  my $name = $hash->{NAME};
  
  my $address = $hash->{IP_ADDRESS};
  $hash->{IP_ADDRESS} = $address;
  
  return "Argument missing." if(int(@a) < 2);
  
  if($what eq "reading")
  {
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
    return "Device info:\n\n".
           join("\n", map {sprintf("%-17s: %-17s", $_, $hash->{helper}{dInfo}{$_})} sort keys %{$hash->{helper}{dInfo}});
  }
  else
  {
    $return = "Unknown argument $what, choose one of"
             ." deviceInfo:noArg"
             ." reading:".(join(",",(sort keys %{$hash->{READINGS}})));
     
    return $return;
  }
}

sub PHILIPS_AUDIO_Set
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  my $port = $hash->{PORT};
  my $address = $hash->{IP_ADDRESS};
  
  if(not defined($hash->{MODEL}))
  {
    return "Please provide the model information as argument.";
  }
  
  return "No Argument given" if(!defined($a[1])); 

  my $what = $a[1];
  my $usage = "";
  
  my $model = $hash->{MODEL};
  
  $hash->{helper}{dInfo}{MODEL}       = $model;
  $hash->{helper}{dInfo}{NAME}        = $name;
  $hash->{helper}{dInfo}{PORT}        = $port;
  $hash->{helper}{dInfo}{IP_ADDRESS}  = $address;

  $usage = "Unknown argument $what, choose one of".
           " volumeStraight:slider,0,1,64 ".
           " volume:slider,0,1,100 ".
           " volumeUp:noArg ".
           " volumeDown:noArg ".
           " standbyButton:noArg ".
           " player:next,prev,play-pause,stop ".
           " shuffle:on,off ".
           " input:---,".
           
           ((uc($model) eq "AW9000") ? "analogAux," : "").       # Input implemented in AW9000 only
           ((uc($model) eq "AW9000") ? "digital1Coaxial," : ""). # Input implemented in AW9000 only
           ((uc($model) eq "AW9000") ? "digital2Optical," : ""). # Input implemented in AW9000 only
           
           # Input not implemented in the AW9000. Only as DLNA renderer
           ((uc($model) ne "AW9000") ? "mediaLibrary," : ""). 
           
           "internetRadio,onlineServices,mp3Link ". # Available in all devices
           #" statusRequest:noArg".
           " getPresets:noArg".
           " getFavorites:noArg". 
           " getMediaRendererDesc:noArg".
           " favoriteAdd:noArg".
           " favoriteRemove:noArg".
           " repeat:single,all,off".
           #" home:noArg".
           " mute:on,off ";   

  my @favoriteList;
  my @favoriteNumber;
  foreach my $readings (keys % {$hash->{READINGS}})
  {
    push @favoriteList,$1."_".substr($hash->{READINGS}{$readings}{VAL}, 0, 25) if($readings =~ m/^.inetRadioFavorite_(..)/);
    push @favoriteNumber, $1 if($readings =~ m/^.inetRadioFavorite_(..)/);
  }
 
  (s/\*/\[asterisk\]/g) for @favoriteList; # '*' not shown correctly
  (s/#/\[hash\]/g)      for @favoriteList; # '#' not shown correctly
  (s/[\\]//g)           for @favoriteList;
  (s/[ :;,']/_/g)       for @favoriteList; # Replace not allowed characters
       
  my @presetList;
  my @presetNumber;
  foreach my $readings (keys % {$hash->{READINGS}})
  {
    push @presetList, $1."_".substr($hash->{READINGS}{$readings}{VAL}, 0, 25) if($readings =~ m/^.inetRadioPreset_(..)/);
    push @presetNumber, $1 if($readings =~ m/^.inetRadioPreset_(..)/);
  }
 
  (s/\*/\[asterisk\]/g) for @presetList; # '*' not shown correctly
  (s/#/\[hash\]/g)      for @presetList; # '#' not shown correctly
  (s/[\\]//g)           for @presetList; # Replace \   
  (s/[ :;,']/_/g)       for @presetList; # Replace not allowed characters           
       
  $usage .= "selectFavorite:"        .join(",",("---",(sort @favoriteList))) . " ";
  $usage .= "selectPreset:"          .join(",",("---",(sort @presetList)))   . " ";           
  $usage .= "selectPresetByNumber:"  .join(",",("---",(sort @presetNumber)))   . " ";
  $usage .= "selectFavoriteByNumber:".join(",",("---",(sort @favoriteNumber)))   . " ";
  # Direct stream selection if any
               
  my @selectStream;
 
  for(my $lvl = 1; $lvl < int(ReadingsVal($name, ".listDepthLevel", "1") - 1); $lvl++)
  {
    my $listLevelName = ReadingsVal($name, ".lvl_".$lvl."_name", "");
    push @selectStream, "lvl_".$lvl."_".$listLevelName;
  }
 
  foreach my $readings (keys % {$hash->{READINGS}})
  {
    push @selectStream,$1."_".substr($hash->{READINGS}{$readings}{VAL}, 0, 25) if($readings =~ m/^listItem_(...)/);                 
  }
             
  @selectStream = sort map{s/\*/\[asterisk\]/g;$_;} grep/._..*$/, @selectStream; # Replace *
  @selectStream = sort map{s/#/\[hash\]/g;$_;}      grep/._..*$/, @selectStream; # Replace #
  @selectStream = sort map{s/[\\]//g;$_;}           grep/._..*$/, @selectStream; # Replace not allowed characters
  @selectStream = sort map{s/[ :;,']/_/g;$_;}       grep/._..*$/, @selectStream; # Replace not allowed characters
             
  $usage .= "selectStream:".join(",",("---",(sort @selectStream))) . " ";
    
  Log3 $name, 5, "PHILIPS_AUDIO ($name) - set ".join(" ", @a);
  
  # External Command. Not from buffer timer.
  $hash->{helper}{fromSendCommandBuffer} = 0;
  
  if($what =~ /input|selectStream|selectPreset|selectFavorite/)
  {
    # GetStatus while manual operation causes the device to stuck. Supress.
    # Change device state to "browsing" in order to suppress automatic update
    $hash->{helper}{playerState}   = "browsing";
    $hash->{helper}{manualOperation} = 1;
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "playerState", "browsing");
    readingsBulkUpdate($hash, ".manualOperation", "yes", 1);
    readingsEndUpdate($hash, 1);
    # Reset browsing timeout
    $hash->{helper}{playerBrowsingTimeout} = 0;
  } 

  if($what eq "standbyButton")
  {
    readingsSingleUpdate($hash, "input", "-", 1);
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$STANDBY", "",$what, "noArg");
  }
  elsif($what eq "getMediaRendererDesc")
  {
    PHILIPS_AUDIO_getMediaRendererDesc($hash);
  }  
  elsif($what eq "input")
  {
    if ($a[2] =~ /analogAux|mp3Link|digital1Coaxial|digital2Optical/)
    {
      # Delete List related readings
      delete $hash->{READINGS}{$_} foreach (grep /list/, keys %{$hash->{READINGS}});
      # Delete player related readings
      delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});      
    }
    
    if($a[2] eq "analogAux")
    {
      readingsSingleUpdate($hash, "input", "Aux-in (analog)", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/aux", "",$what, $a[2]);
    }
    elsif($a[2] eq "mp3Link")
    {
      
      $hash->{helper}{playerState}   = "home";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "input", "MP3-Link");      
      readingsBulkUpdate($hash, "playerState", "home");
      readingsEndUpdate($hash, 1);
      
      if(uc($model) eq "AW9000")
      {
        PHILIPS_AUDIO_SendCommand($hash, "/mp3link", "", $what, $a[2]);      
      }
      else
      {
        PHILIPS_AUDIO_SendCommand($hash, "/aux", "", $what, $a[2]);
      }
    }
    elsif($a[2] eq "digital1Coaxial")
    {
      $hash->{helper}{playerState} = "home";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "input", "Digital-in 1 (coaxial)");      
      readingsBulkUpdate($hash, "playerState", "home");
      readingsEndUpdate($hash, 1);
      
	  PHILIPS_AUDIO_SendCommand($hash, "/digin_coaxial", "",$what, $a[2]);
      
    }
    elsif($a[2] eq "digital2Optical")
    {
      $hash->{helper}{playerState} = "home";
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "input", "Digital-in 2 (optical)");      
      readingsBulkUpdate($hash, "playerState", "home");
      readingsEndUpdate($hash, 1);
      
      PHILIPS_AUDIO_SendCommand($hash, "/digin_optical", "",$what, $a[2]);      
    }
    elsif($a[2]  eq "mediaLibrary")
    {
      readingsSingleUpdate($hash, "playerListStatus", "busy", 1);
      #readingsSingleUpdate($hash, "input", "Media Library", 1);
	  PHILIPS_AUDIO_SendCommand($hash, "/nav\$02\$01\$001\$0", "", $what, $a[2]);      
    }
    elsif($a[2]  eq "internetRadio")
    {
      readingsSingleUpdate($hash, "playerListStatus", "busy", 1);
      #readingsSingleUpdate($hash, "input", "Internet Radio", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "",$what, $a[2]);      
    }
    elsif($a[2]  eq "onlineServices")
    {
      readingsSingleUpdate($hash, "playerListStatus", "busy", 1);
      #readingsSingleUpdate($hash, "input", "Online Services", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/nav\$09\$01\$001\$0", "", $what, $a[2]);      
    }        
    else
    {
      return $usage;
    }   
  }  
  elsif($what eq "home")
  {
    readingsSingleUpdate($hash, "playerListStatus", "busy", 1);
    $hash->{header}{httpHeaderRefer} = "Upgrade-Insecure-Requests: 1\r\n";
    PHILIPS_AUDIO_SendCommand($hash, "/index", "",$what, "noArg");
  }  
  elsif($what eq "shuffle")
  {
    if($a[2]  eq "on")
    {
      readingsSingleUpdate($hash, "playerShuffle", "on", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$SHUFFLE_ON", "",$what, $a[2]);
    }
    elsif($a[2]  eq "off")
    {
      readingsSingleUpdate($hash, "playerShuffle", "off", 1);
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
      readingsSingleUpdate($hash, "playerRepeat", "single", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$REPEAT_SINGLE", "",$what, $a[2]);
    }
    elsif($a[2]  eq "all")
    {
      readingsSingleUpdate($hash, "playerRepeat", "all", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/MODE\$REPEAT_ALL", "",$what, $a[2]);
    }
    elsif($a[2]  eq "off")
    {
      readingsSingleUpdate($hash, "playerRepeat", "off", 1);
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
  elsif($what eq "favoriteAdd")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$ADD2FAV", "",$what, "noArg");
  }
  elsif($what eq "favoriteRemove")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$REMFAV", "",$what, "noArg");
  }
  elsif($what eq "mute")
  {
    if($a[2] eq "on")
    {
      readingsSingleUpdate($hash, "mute", "on", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$MUTE", "",$what, "noArg");
    }
    elsif($a[2] eq "off")
    {
      readingsSingleUpdate($hash, "mute", "off", 1);
      PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$UNMUTE", "",$what, "noArg");
    }
    else
    {
      return $usage;
    }    
  }  
  elsif($what eq "player")
  {
    if($a[2] eq "next")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$NEXT", "",$what, "noArg");
    }
    elsif($a[2] eq "prev")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$PREV", "",$what, "noArg");
    }
    elsif($a[2] eq "play-pause")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$PLAY_PAUSE", "",$what, "noArg");
    }
    elsif($a[2] eq "stop")
    {
      PHILIPS_AUDIO_SendCommand($hash, "/CTRL\$STOP", "",$what, "noArg");
    }
    else
    {
      return $usage;
    }
  }
  elsif($what =~ m/^(selectPreset|selectPresetByNumber)/)
  {
    if($a[2] ne "---")
    {
      # Hierarchichal navigation through the contents mandatory
      $hash->{helper}{cmdStep} = 1;
	  
	  my $presetNumber = substr($a[2], 0, 2); # Get 2 first digits      
	      
	  if($a[2] =~ m/empty/ or ReadingsVal($name, ".inetRadioPreset_$presetNumber","") eq "empty")
	  {
		# Do nothing
	  }
      else
      {
        $presetNumber =~ s/^0+//g;     # Remove leading '0'
        $hash->{helper}{inetRadioPreset} = $presetNumber;
        readingsSingleUpdate($hash, "input", "Internet Radio", 1);      
        PHILIPS_AUDIO_SendCommand($hash, "/index", "", $what, $a[2]);    
      }	      
    }      
  }  
  elsif($what =~ m/^(selectFavorite|selectFavoriteByNumber)/)
  {
    if($a[2] ne "---")
    {
      # Hierarchichal navigation through the contents mandatory
      $hash->{helper}{cmdStep} = 1;
	  
	  my $favoriteNumber = substr($a[2], 0, 2);  # Get 2 first digits
	  
	  if($a[2] =~ m/empty/ or ReadingsVal($name, ".inetRadioFavorite_$favoriteNumber","") eq "empty")
	  {
		# Do nothing
	  }
      else
      {
        $favoriteNumber =~ s/^0+//g;               # Remove leading '0'
        $hash->{helper}{inetRadioFavorite} = $favoriteNumber;
        #readingsSingleUpdate($hash, "input", "Internet Radio", 1);      
        PHILIPS_AUDIO_SendCommand($hash, "/index", "", $what, $a[2]);
      }    
    }
  }  
  elsif($what eq "volumeStraight")
  {
    if(($a[2] < 0) || ($a[2] > 64))
    {
      return "volumeStraight must be in the range 0...64.";
    }  
    else
    {
      $hash->{helper}{targetVolume} = int($a[2]);
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
      readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $hash->{helper}{targetVolume}));
      readingsEndUpdate($hash, 1);      
      PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$VAL\$".$a[2], "",$what, $a[2]);      
    }
  }
  elsif($what eq "volumeUp")
  {
    my $targetVolume = int(int(ReadingsVal($name, "volumeStraight", "0")) + 1);
    
    if($targetVolume > 64)
    {
      $targetVolume = 64;
    }
    
    $hash->{helper}{targetVolume} = $targetVolume;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
    readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $hash->{helper}{targetVolume}));
    readingsEndUpdate($hash, 1);
    
    PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$VAL\$" . $hash->{helper}{targetVolume}, "",$what, $hash->{helper}{targetVolume});
  }
  elsif($what eq "volumeDown")
  {
    my $targetVolume = int(int(ReadingsVal($name, "volumeStraight", "0")) - 1);
    
    if($targetVolume < 0)
    {
      $targetVolume = 0;
    }
    
    $hash->{helper}{targetVolume} = $targetVolume;
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
    readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $hash->{helper}{targetVolume}));
    readingsEndUpdate($hash, 1);
    
    PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$VAL\$" . $hash->{helper}{targetVolume}, "",$what, $hash->{helper}{targetVolume});
  }
  elsif($what eq "volume")
  {
    if(($a[2] < 0) || ($a[2] > 100))
    {
      return "volumeStraight must be in the range 0...100.";
    }
    else
    {
      $hash->{helper}{targetVolume} = PHILIPS_AUDIO_volume_rel2abs($hash, $a[2]);
      
      readingsBeginUpdate($hash);
      readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});
      readingsBulkUpdate($hash, "volume", $a[2]);
      readingsEndUpdate($hash, 1);
      
      PHILIPS_AUDIO_SendCommand($hash, "/VOLUME\$VAL\$".$hash->{helper}{targetVolume}, "",$what, $hash->{helper}{targetVolume});
    }
  }
  elsif($what eq "nowplay")
  {
    PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "",$what, "noArg");
  }
  elsif($what eq "homestatus")
  {
    $hash->{helper}{httpHeaderRefer} = "http://$hash->{IP_ADDRESS}:$hash->{PORT}/index\r\n";
    PHILIPS_AUDIO_SendCommand($hash, "/HOMESTATUS", "",$what, "noArg");
  }
  elsif($what eq "getPresets")
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "playerListStatus", "busy");
    readingsBulkUpdate($hash, "readingPresets", "yes");
    readingsEndUpdate($hash, 1);
    
    # Delete old redings
    delete $hash->{READINGS}{$_} foreach (grep /.inetRadioPreset_..$/, keys %{$hash->{READINGS}});    
	
    # Hierarchichal navigation through the contents mandatory
    $hash->{helper}{cmdStep} = 1;
    PHILIPS_AUDIO_SendCommand($hash, "/index", "", $what, "noArg");    
  }
  elsif($what eq "getFavorites")
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, "playerListStatus", "busy");
    readingsBulkUpdate($hash, "readingFavorites", "yes");
    readingsEndUpdate($hash, 1);
    
    # Delete old redings
    delete $hash->{READINGS}{$_} foreach (grep /.inetRadioFavorite_..$/, keys %{$hash->{READINGS}});
		
	# Hierarchichal navigation through the contents mandatory
    $hash->{helper}{cmdStep} = 1;
    PHILIPS_AUDIO_SendCommand($hash, "/index", "", $what, "noArg");
  }
  elsif($what eq "selectStream")
  {
    
    # The player list selection has been designed for a GUI/touchscreen
    # Virtually scrolling down to last item and choosing the first one
    # arises an error. Needs to navigate back to the corresponding page
    # consisting of 8 items per page
    
    readingsSingleUpdate($hash, "playerListStatus", "busy", 1);
    
    if($a[2]  =~ /lvl_(.+?)/)
    {
      my $desiredLevel = $1;
      my $currentUrl   = $hash->{helper}{currentNavUrl};
      my $newUrl       = "";
      my $currentLevel = "";
      my $newLevel     = "";
      
      if($currentUrl =~ /\/nav\$(.*)\$(.*)\$(.*)\$(.*)/) # e.g. /nav$02$XX$001$0
      {
        $currentLevel = int($2);
        $newLevel     = sprintf("%02d", $currentLevel - ($currentLevel - $desiredLevel) + 1);
        $newUrl       = "/nav\$$1\$$newLevel\$$3\$0";
      }
      
      PHILIPS_AUDIO_SendCommand($hash, $newUrl, "", $what, $a[2]);      
    }
    elsif($a[2] ne "---")
    {
      my $targetNr   = substr($a[2], 0, 3);
      my $currentUrl = $hash->{helper}{currentNavUrl};
            
      # Remark TODO...
      
      if($a[2] =~ /(\d{3})_(.+?)_(.*)/)
      {
        my $currentListLevel = ReadingsVal($name, ".listDepthLevel", "");
        readingsSingleUpdate($hash, ".lvl_".$currentListLevel."_name", "$2_$3", 1);
        
        if(int(ReadingsVal($name, "playerListTotalCount", "8")) > 8)
        {
          if($currentUrl =~ /\/nav\$(.*)\$(.*)\$(.*)\$(.*)/)
          {
            # Virtually scroll back to the first line
            
            my $scrollUrl = "\/nav\$$1\$$2\$001\$$4";
                                
            PHILIPS_AUDIO_SendCommand($hash, $scrollUrl, "", "selectStream", "scroll");
            
            # int(($targetNr / 8) + 0.5) -> Round up
            for(my $i = 1; $i < (int(($targetNr / 8) + 0.5) + 1); $i += 8) # Max 8 items in the actual list
            {
              my $scrollUrl = "\/nav\$$1\$$2\$".sprintf("%003s", ($i + 8))."\$$4";
              
              PHILIPS_AUDIO_SendCommand($hash, $scrollUrl, "", "selectStream", "scroll");
            }
          }
        }      
      }
      PHILIPS_AUDIO_SendCommand($hash, ReadingsVal($name, ".listItemTarget_$targetNr", ""), "", $what, $a[2]);
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

  PHILIPS_AUDIO_ResetTimer($hash); # Reset timer for the next loop
  
  return;
}

sub PHILIPS_AUDIO_Define
{
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    my $name = $hash->{NAME};
    
    # Implemented devices for reading Device Description
    @{$hash->{helper}{DevDescImplementedModels}} = qw( AW9000 NP3500 NP3700 NP3900 );
    
    $hash->{helper}{sendCommandBuffer} = [];
    
    delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
    
    if(! @a >= 4)
    {
      my $msg = "Wrong syntax: define <name> PHILIPS_AUDIO <model> <ip-or-hostname> [<ON-statusinterval>] [<OFF-statusinterval>] ";
      Log3 $name, 2, $msg;
      return $msg;
    }
    
    if(defined($a[2]))
    {
      $hash->{MODEL} = uc($a[2]);
      
      # Used by 'fheminfo' command for statistics
      $attr{$name}{"model"} = $hash->{MODEL};
    }
    
    $hash->{IP_ADDRESS} = $a[3];
    $hash->{PORT}       = 8889;
    
    # if an update interval >= 5 use it.
    if(defined($a[4]) and $a[4] > 0)
    {
      $hash->{helper}{OFF_INTERVAL} = $a[4];
      # Minimum interval 5 sec
      if($hash->{helper}{OFF_INTERVAL} < 5)
      {
        $hash->{helper}{OFF_INTERVAL} = 5;
      }
    }
    else
    {
      $hash->{helper}{OFF_INTERVAL} = 30;
    }
      
    if(defined($a[5]) and $a[5] > 0)
    {
      $hash->{helper}{ON_INTERVAL} = $a[5];
      # Minimum interval 5 sec
      if($hash->{helper}{ON_INTERVAL} < 5)
      {
        $hash->{helper}{ON_INTERVAL} = 5;
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
    
    PHILIPS_AUDIO_ResetTimer($hash, 0);
  
    return;
}

sub PHILIPS_AUDIO_Attr
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
        PHILIPS_AUDIO_GetStatus($hash, 1);
      }
    }
    else
    {
      $hash->{helper}{DISABLED} = 0;
      PHILIPS_AUDIO_GetStatus($hash, 1);
    }
  }
  elsif($attrName eq "maxListItems" && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 8) || ($attrVal > 999)))
    {
      return "$attrName must be between 8 and 999";
    }
  }
  elsif($attrName eq "httpBufferTimeout" && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 10) || ($attrVal > 15)))
    {
      return "$attrName must be between 10 and 15";
    }
  }
  elsif($attrName eq "requestTimeout" && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 10) || ($attrVal > 15)))
    {
      return "$attrName must be between 10 and 15";
    }
  }
  elsif($attrName eq "autoGetPresets" && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 0) || ($attrVal > 1)))
    {
      return "$attrName must be between 0 or 1";
    }
  }
  elsif($attrName eq "autoGetFavorites" && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 0) || ($attrVal > 1)))
    {
      return "$attrName must be between 0 or 1";
    }
  }
  elsif($attrName eq "playerBrowsingTimeout" && defined($attrVal))
  {
    if ($cmd eq "set" && (($attrVal < 60) || ($attrVal > 600)))
    {
      return "$attrName must be between 60 or 600";
    }
  }
  
  # Start/Stop Timer according to new disabled-Value
  PHILIPS_AUDIO_ResetTimer($hash);

  return;
}

sub PHILIPS_AUDIO_Undefine
{
  my($hash, $name) = @_;

  # Stop the internal GetStatus-Loop and exit
  RemoveInternalTimer($hash, "PHILIPS_AUDIO_GetStatus");
  return;
}

sub PHILIPS_AUDIO_SendCommandBuffer
{
  # Function called by an internal timer in case device busy
  my ($hash) = @_;
  
  my $firstCommand = "";
  my ($url, $data, $cmd, $arg) = ("", "", "", "");
  
  
  # Get first command from buffer
  if
  (
    @{$hash->{helper}{sendCommandBuffer}}
  )
  {
    $firstCommand = shift(@{$hash->{helper}{sendCommandBuffer}});
    
    $url  = $firstCommand->{url};
    $data = $firstCommand->{data};
    $cmd  = $firstCommand->{cmd};
    $arg  = $firstCommand->{arg};
  }
  
  # Only send in case buffer not empty
  if(($url ne "") and ($cmd ne "") and ($arg ne "")) # $data may be empty
  {
    
    $hash->{helper}{comeFromSendBuffer} = 1;
    
    PHILIPS_AUDIO_SendCommand(
                              $hash,
                              $url,
                              $data,
                              $cmd,
                              $arg
                             );
                             
    
    # Check if buffer empty
    if
    (
      (@{$hash->{helper}{sendCommandBuffer}})
    )
    {
      # Come back
      # -> try again after 1 sec delay and process buffer.
      RemoveInternalTimer($hash, "PHILIPS_AUDIO_SendCommandBuffer");    
      InternalTimer(gettimeofday() + 1, "PHILIPS_AUDIO_SendCommandBuffer", $hash);
    }                         
    
  }
  else
  {
    # Do nothing.
    # Reset flag in case buffer empty
    $hash->{helper}{comeFromSendBuffer} = 0;
    PHILIPS_AUDIO_ResetTimer($hash);
  }
  
  return;
}

sub PHILIPS_AUDIO_SendCommand
{
  my ($hash, $url, $data, $cmd, $arg) = @_;
  my $name    = $hash->{NAME};
  my $address = $hash->{IP_ADDRESS};
  my $port    = $hash->{PORT};
  
  $hash->{helper}{networkRequest}     = "idle" if(not defined($hash->{helper}{networkRequest}));   # First run
  $hash->{helper}{comeFromSendBuffer} = 0    if(not defined($hash->{helper}{comeFromSendBuffer})); # First run
  
  # buffer command and wait a second in case device busy 
  if ($hash->{helper}{networkRequest} eq "busy")
  {
    
    my $httpBufferData = 
       {
          url  => $url,
          data => $data,
          cmd  => $cmd,
          arg  => $arg                          
       };
       
    # Append to buffer only if not coming from itself    
    # Or put to first position for resending
    
    #        add  remove  start  end
    # push    X                   X
    # pop           X             X
    # unshift X            X
    # shift         X      X
    
    if($hash->{helper}{comeFromSendBuffer} == 0)
    {
      push    @{$hash->{helper}{sendCommandBuffer}}, $httpBufferData;
    }
    else
    {
      unshift @{$hash->{helper}{sendCommandBuffer}}, $httpBufferData; 
    }
    
    if($hash->{helper}{timeoutCounter} >= AttrVal($name, "httpBufferTimeout", 10))
    {
     # X seconds timeout. Something went wrong. Clear buffer. Release "busy"
     
     # Delete all remaining commands
     splice(@{$hash->{helper}{sendCommandBuffer}});
     
     $hash->{helper}{timeoutCounter}            = 0;
     $hash->{helper}{networkRequest}            = "idle";
     $hash->{helper}{comeFromSendBuffer}        = 0;
     
     readingsBeginUpdate($hash);
     readingsBulkUpdate ($hash, "networkRequest", "idle");
     readingsBulkUpdate ($hash, "networkError", "buffer timed out");
     readingsEndUpdate  ($hash, 1);
     
     Log3 $name, 3, "PHILIPS_AUDIO ($name) - HTTP buffer timeout. Please, check your network connection, ip-address etc. Device switched off?";
     
     PHILIPS_AUDIO_ResetTimer($hash);
     
     return;
    }
    
    # -> try again after 1 sec delay and process buffer.
    RemoveInternalTimer($hash, "PHILIPS_AUDIO_SendCommandBuffer");    
    InternalTimer(gettimeofday() + 1, "PHILIPS_AUDIO_SendCommandBuffer", $hash);
    
    return;
  }
  else
  {
    if($url =~ /\/nav(.*)/)
    {
      $hash->{helper}{currentNavUrl} = $url;
    }
    else
    {
      $hash->{helper}{currentUrl} = $url;
    }
    
    if(ReadingsVal($name, "presence", "absent") ne "absent")
    {
      $hash->{helper}{networkRequest} = "busy";
      readingsSingleUpdate($hash, "networkRequest", "busy", 1);
    }
    
    PHILIPS_AUDIO_ResetTimer($hash); # getStatus
  }
  
  $hash->{helper}{timeoutCounter}  = 0;
  
  Log3 $name, 5, "PHILIPS_AUDIO ($name) - Executing nonblocking \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\" on $name: $data";
  
  # Reset flag if successfully sent
  $hash->{helper}{comeFromSendBuffer} = 0;
  
  HttpUtils_NonblockingGet
  ({
    url         => "http://".$address.":".$port."".$url,
    timeout     => AttrVal($name, "requestTimeout", 10),
    noshutdown  => 1,
    data        => $data,
    loglevel    => ($hash->{helper}{AVAILABLE} ? undef : 5),
    hash        => $hash,
    cmd         => $cmd,
    arg         => $arg,
    method      => "GET",
    httpversion => "1.1",
    keepalive   => 1, # Philips app always uses keep-alive 
    header      => $hash->{helper}{httpHeaderRefer},
    callback    => \&PHILIPS_AUDIO_ParseResponse                        
  });
  
  return;  
}

sub PHILIPS_AUDIO_ParseResponse
{
    my ($param, $err, $data ) = @_;    
    
    my $hash = $param->{hash};
    my $name = $hash ->{NAME};
    my $cmd  = $param->{cmd};
    my $arg  = $param->{arg};
    
    if(exists($param->{code}))
    {
      Log3 $name, 5, "PHILIPS_AUDIO ($name) - received HTTP code ".$param->{code}." for command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\"";
    }
    
    if($err ne "")
    {
      readingsBeginUpdate($hash);
      
      Log3 $name, 5, "PHILIPS_AUDIO ($name) - Could not execute command \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $err";
      
      # Release the busy flag
      $hash->{helper}{networkRequest} = "idle";
      readingsBulkUpdate($hash, "networkRequest", "idle");
      
      if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} == 1))
      {
        Log3 $name, 3, "PHILIPS_AUDIO ($name) - Could not execute HTTP request. Please, check your network connection, ip-address etc. Device switched off? ($err)";
        readingsBulkUpdate($hash, "networkError", "$err");
        readingsBulkUpdate($hash, "presence", "absent");
        readingsBulkUpdate($hash, "state", "absent");
        $hash->{STATE} = "absent";
      }
      
      $hash->{helper}{AVAILABLE}          = 0;
      $hash->{helper}{timeoutCounter}     = 0;      
      $hash->{helper}{comeFromSendBuffer} = 0;      
      
      # Close HTTP connection
      HttpUtils_Close($param);
      
      # Force "home" state
      $hash->{helper}{playerState}   = "home";
      readingsBulkUpdate($hash, "playerState", "home");
      readingsBulkUpdate($hash, "playerListStatus", "ready");
      
      readingsEndUpdate($hash, 1);
      
      # Device firware "somehow buggy".
      # Try to reanimate the device after timeout.
      # Go to /index
      PHILIPS_AUDIO_SendCommand($hash, "/index", "","home", "noArg");
      
      PHILIPS_AUDIO_ResetTimer($hash);
      return;
    }
    elsif($data ne "")
    {
      
      Log3 $name, 5, "PHILIPS_AUDIO ($name) - got response for \"$cmd".(defined($arg) ? " ".(split("\\|", $arg))[0] : "")."\": $data";
      
      delete $hash->{READINGS}{networkError};
      
      readingsBeginUpdate($hash);
      
      if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0)
      {
        Log3 $name, 3, "PHILIPS_AUDIO ($name) - device $name reappeared";
        readingsBulkUpdate($hash, "presence", "present");        
      }
      
      $hash->{helper}{AVAILABLE} = 1;
      
      readingsBulkUpdate($hash, "power", "on");
      readingsBulkUpdate($hash, "state","on");
      
      $hash->{STATE} = "on";
      
      readingsEndUpdate($hash, 1);
      
      if($cmd eq "standbyButton")
      {
        if($data =~ /SUCCESS/)
        {
          #readingsBulkUpdate($hash, "power", "on");
          #readingsBulkUpdate($hash, "state","on");          
        }
        
      }
      elsif($cmd eq "home")
      {
        if($data =~ /'devicename'/) # Device responded correctly
        {
          $hash->{helper}{playerState} = "home";
          
          readingsBeginUpdate($hash);          
          readingsBulkUpdate ($hash, "playerState", "home");
          readingsBulkUpdate ($hash, "playerListStatus", "ready");
          readingsEndUpdate  ($hash, 1);
        }
      }
      elsif($cmd eq "mute")
      {
        if($data =~ /SUCCESS/)
        {
          readingsSingleUpdate($hash, "mute", "on", 1);
        }
      }
      elsif($cmd eq "unmute")
      {
        if($data =~ /SUCCESS/)
        {
          readingsSingleUpdate($hash, "mute", "off", 1);
        }
      }
      elsif($cmd eq "favoriteRemove")
      {
        # replace \n by ""
        $data =~ s/\n//g;
                
        if($data =~ /{'command':'MESSAGE','value':'(.+)'}/)
        {
          # Do nothing
        }
      }
      elsif($cmd eq "favoriteAdd")
      {
        # replace \n by ""
        $data =~ s/\n//g;
        
        if($data =~ /{'command':'MESSAGE','value':'(.+)'}/)
        {
          # Do nothing
        }
      }
      elsif($cmd =~ m/^(selectPreset|inetRadioPreset)/)
      {        
        # This command must be processed hierarchicaly through the navigation path
        if($hash->{helper}{cmdStep} == 1)
        {
          $hash->{helper}{cmdStep} = 2;
          
          # External Command. Not from buffer timer.
          $hash->{helper}{fromSendCommandBuffer} = 0;
          # Internet radio
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "", "selectPreset", $hash->{helper}{inetRadioPreset});
        }
        elsif($hash->{helper}{cmdStep} == 2)
        {
          $hash->{helper}{cmdStep} = 3;
          
          # External Command. Not from buffer timer.
          $hash->{helper}{fromSendCommandBuffer} = 0;
          # Presets
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$02\$001\$0", "","selectPreset", $hash->{helper}{inetRadioPreset});
        }
        elsif($hash->{helper}{cmdStep} == 3)
        {
          $hash->{helper}{cmdStep} = 4;
          
          # External Command. Not from buffer timer.
          $hash->{helper}{fromSendCommandBuffer} = 0;
          
          # Preset select
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$03\$".sprintf("%03d", $hash->{helper}{inetRadioPreset})."\$1", "","selectPreset", $hash->{helper}{inetRadioPreset});
          
          $hash->{helper}{playerState} = "playing";
          readingsSingleUpdate($hash, "playerState", "playing", 1);          
        }
               
      }      
      elsif($cmd =~ m/^(selectFavorite|inetRadioFavorite)/)
      {
        # This command must be processed hierarchicaly through the navigation path
        if($hash->{helper}{cmdStep} == 1)
        {
          $hash->{helper}{cmdStep} = 2;
          # Internet radio favorite# External Command. Not from buffer timer.
          $hash->{helper}{fromSendCommandBuffer} = 0;
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "", "selectFavorite", $hash->{helper}{inetRadioFavorite});
        }
        elsif($hash->{helper}{cmdStep} == 2)
        {
          $hash->{helper}{cmdStep} = 3;
          
          # External Command. Not from buffer timer.
          $hash->{helper}{fromSendCommandBuffer} = 0;
          
          # Favorite Presets
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$02\$002\$0", "","selectFavorite", $hash->{helper}{inetRadioFavorite});
        }
        elsif($hash->{helper}{cmdStep} == 3)
        {
          $hash->{helper}{cmdStep} = 4;
          
          # External Command. Not from buffer timer.
          $hash->{helper}{fromSendCommandBuffer} = 0;
          
          # Favorite Preset select
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$03\$".sprintf("%03d", $hash->{helper}{inetRadioFavorite})."\$1", "","selectFavorite", $hash->{helper}{inetRadioFavorite});
          
          $hash->{helper}{playerState} = "playing";
          readingsSingleUpdate($hash, "playerState", "playing", 1);       
        }
      }
      elsif($cmd eq "play_pause")
      {
        if($data =~ /SUCCESS/)
        {
          if(ReadingsVal($name, "playerPlaying", "") eq "no")
          {
            readingsSingleUpdate($hash, "playerPlaying", "yes", 1);
          }
          else
          {
            delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
            
            readingsBeginUpdate($hash);            
            readingsBulkUpdate($hash, "playerPlaying", "no");
            readingsBulkUpdate($hash, "input", "-");
            readingsEndUpdate($hash, 1);
          }          
        }        
      }
      elsif($cmd eq "stop")
      {
        if($data =~ /STOP/)
        {
          delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
          
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "playerPlaying", "no");
          readingsBulkUpdate($hash, "input", "-");
          readingsEndUpdate($hash, 1);
        }
      }      
      elsif($cmd =~ m/^(volumeStraight|volumeUp|volumeDown)/)
      {        
        if($data =~ /SUCCESS/)
        {
          my $targetVolume = $hash->{helper}{targetVolume};
          
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "volumeStraight", $hash->{helper}{targetVolume});          
          readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $targetVolume));
          readingsEndUpdate($hash, 1);          
        }
      }
      elsif($cmd eq "elapse")
      {
        if($data =~ /'command':'(.+)',/)
        {
          if($1 eq "NOWPLAY")
          {
            # New player status information available
            readingsSingleUpdate($hash, "playerPlaying", "yes", 1);
            PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "","nowplay", "noArg");
          }
          elsif($1 eq "ELAPSE")
          {
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, "playerPlaying", "yes");
            
            if($data =~ /'value':(.+),/)
            {
              # Sometimes the device does not refresh the ELAPSE -> NOWPLAY request
              # Showing the current stream position.
              # Check for a new song.
              
              $hash->{helper}{elapseValueOld} = "0" if(not defined($hash->{helper}{elapseValueOld}));
              
              if (int($1) < int($hash->{helper}{elapseValueOld})) # New song
              {
                PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "","nowplay", "noArg");                
              }
              
              $hash->{helper}{elapseValueOld} = $1;
              
              if(int($1) < 3600)
              {
                readingsBulkUpdate($hash, "playerPlayTime", strftime("%M:\%S", gmtime($1)));
              }
              else
              {
                readingsBulkUpdate($hash, "playerPlayTime", strftime("\%H:\%M:\%S", gmtime($1)));
              }
            }
            if($data =~ /'mute':(.+),/)
            {
              if(int($1) == 1)
              {
                readingsBulkUpdate($hash, "mute", "on");
              }
              else
              {
                readingsBulkUpdate($hash, "mute", "off");
              }
            }
            if($data =~ /'shuffle':(.+),/)
            {
              if(int($1) == 1)
              {
                readingsBulkUpdate($hash, "playerShuffle", "on");
              }
              else
              {
                readingsBulkUpdate($hash, "playerShuffle", "off");
              }
            }
            if($data =~ /'repeat':(.+),/)
            {
              if(int($1) == 0)
              {
                readingsBulkUpdate($hash, "playerRepeat", "off");
              }
              elsif(int($1) == 1)
              {
                readingsBulkUpdate($hash, "playerRepeat", "single");
              }
              elsif(int($1) == 2)
              {
                readingsBulkUpdate($hash, "playerRepeat", "all");
              }          
            }
            if($data =~ /'rating':(.+),/)
            {
              readingsBulkUpdate($hash, "playerStreamRating", $1);
            }
            if($data =~ /'favstatus':(.+)}/)
            {
              if(int($1) == 1)
              {
                readingsBulkUpdate($hash, "playerStreamFavorite", "yes");
              }
              else
              {
                readingsBulkUpdate($hash, "playerStreamFavorite", "no");
              }
            }        
            if($data =~ /'volume':(.+),/)
            {
              readingsBulkUpdate($hash, "volumeStraight", $1);
              readingsBulkUpdate($hash, "volume", PHILIPS_AUDIO_volume_abs2rel($hash, $1));          
            }
            
            readingsEndUpdate($hash, 1);  
            
            if($data =~ /'play':(.+),/)
            {
              if(int($1) == 1)
              {
                $hash->{helper}{playerState}   = "playing";
                readingsBeginUpdate($hash);
                readingsBulkUpdate ($hash, "playerPlaying", "yes");
                readingsBulkUpdate ($hash, "playerState", "playing");
                readingsEndUpdate  ($hash, 1);
              }        
              else
              {
                delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
                
                readingsBeginUpdate($hash);
                readingsBulkUpdate ($hash, "playerPlaying", "no");
                readingsBulkUpdate ($hash, "playerState", "home");
                readingsEndUpdate  ($hash, 1);
              }
            }
          }
        }
      }           
      elsif($cmd eq "nowplay")
      {        
        if($data =~ /'command':'(.+)',/)
        {
          if($1 eq "NOTHING")
          {
            delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
            
            $hash->{helper}{playerState} = "home";
            
            readingsBeginUpdate($hash);
            readingsBulkUpdate ($hash, "playerPlaying", "no");
            readingsBulkUpdate ($hash, "playerState", "home");
            readingsEndUpdate  ($hash, 1);
          }
        }
        elsif($data =~ /window.location = \"\/index\"/)
        {
          delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
          
          $hash->{helper}{playerState} = "home";
          
          readingsBeginUpdate($hash);
          readingsBulkUpdate ($hash, "playerPlaying", "no");
          readingsBulkUpdate ($hash, "playerState", "home");
          readingsEndUpdate  ($hash, 1);          
        }
        else
        {
          $hash->{helper}{playerState} = "playing";
          
          readingsBeginUpdate($hash);
          readingsBulkUpdate ($hash, "playerPlaying", "yes");
          readingsBulkUpdate ($hash, "playerState", "playing");
          readingsEndUpdate  ($hash, 1);          
        }
        
        if($data =~ /'devicename':'(.*?)'/)
        {
          if(not defined ($hash->{FRIENDLY_NAME}))
          {
            $hash->{FRIENDLY_NAME} = $1;
            $hash->{helper}{dInfo}{FRIENDLY_NAME} = $1;
          }          
        }
        
        readingsBeginUpdate($hash);
        
        if ($data =~ /'defaultAlbumArt':'res\/Internet_radio.jpg'/)
        {
          readingsBulkUpdate($hash, "input", "Internet Radio");          
        }
        
        if($data =~ /'defaultAlbumArt':'res\/Media_library.jpg'/)
        {
          readingsBulkUpdate($hash, "input", "Media Library"); 
        }
        
        if($data =~ /'defaultAlbumArt':'res\/Home_AUX_nowplaying.jpg'/)
        {
          if($hash->{MODEL} eq "AW9000")
          {
            if($data =~ />Aux-in</)
            {
              readingsBulkUpdate($hash, "input", "Aux-in (analog)");
            }
            elsif($data =~ />Digital-in 1(.+)</)
            {
              readingsBulkUpdate($hash, "input", "Digital-in 1 (coaxial)");  
            }
            elsif($data =~ />Digital-in 2(.+)</)
            {
              readingsBulkUpdate($hash, "input", "Digital-in 2 (optical)");  
            }
            elsif($data =~ />MP3-Link</)
            {
              readingsBulkUpdate($hash, "input", "MP3-Link");  
            }             
          }
          else
          {
            readingsBulkUpdate($hash, "input", "MP3-Link");
          }          
        }
        
        if($data =~ /'defaultAlbumArt':'res\/spot_Nowplaying_AA.png'/)
        {
          readingsBulkUpdate($hash, "input", "Spotify");  
        }
        
        if($data =~ /'defaultAlbumArt':'res\/Home_OnlineServices.png'/)
        {
          readingsBulkUpdate($hash, "input", "Online Services"); 
        }        
        
        readingsEndUpdate($hash, 1);
        
        if($data =~ /'title':'\\'(.+)\\''/)
        {
          if((ReadingsVal($name, "input", "") eq "Media Library") or (ReadingsVal($name, "input", "") eq "Spotify"))
          {
            readingsSingleUpdate($hash, "playerTitle", PHILIPS_AUDIO_html2txt($1), 1);
            delete $hash->{READINGS}{playerRadioStationInfo};
          }
          elsif(ReadingsVal($name, "input", "") eq "Internet Radio")
          {
           readingsSingleUpdate($hash, "playerRadioStationInfo", PHILIPS_AUDIO_html2txt($1), 1);
           delete $hash->{READINGS}{playerTitle};           
          }
        }
        elsif($data =~ /'title':'(.+)'/)
        {
          if((ReadingsVal($name, "input", "") eq "Media Library") or (ReadingsVal($name, "input", "") eq "Spotify"))
          {
            readingsSingleUpdate($hash, "playerTitle", PHILIPS_AUDIO_html2txt($1), 1);
            delete $hash->{READINGS}{playerRadioStationInfo};
          }
          elsif(ReadingsVal($name, "input", "") eq "Internet Radio")
          {
           readingsSingleUpdate($hash, "playerRadioStationInfo", PHILIPS_AUDIO_html2txt($1), 1);
           delete $hash->{READINGS}{playerTitle};           
          }
        }
        else
        {
          delete $hash->{READINGS}{playerTitle};
          delete $hash->{READINGS}{playerRadioStationInfo};
        }
        
        if($data =~ /'subTitle':'(.+)'/)
        {
          if((ReadingsVal($name, "input", "") eq "Media Library") or (ReadingsVal($name, "input", "") eq "Spotify"))
          {
            readingsSingleUpdate($hash, "playerAlbum", PHILIPS_AUDIO_html2txt($1), 1);
            delete $hash->{READINGS}{playerRadioStation};
          }
          else
          {
            readingsSingleUpdate($hash, "playerRadioStation", PHILIPS_AUDIO_html2txt($1), 1);
            delete $hash->{READINGS}{playerAlbum};
          }          
        }
        else
        {
          delete $hash->{READINGS}{playerRadioStation};
          delete $hash->{READINGS}{playerAlbum};
        }
        
        if($data =~ /'albumArt':'(.+)'/)
        {
          readingsSingleUpdate($hash, "playerAlbumArt", $1, 1);
        }
        else
        {
          delete $hash->{READINGS}{playerAlbumArt};
        }
        
        readingsBeginUpdate($hash);
        
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
        
        readingsEndUpdate($hash, 1);
        
        if($data =~ /'elapsetime':(.+),/)
        {
          if(int($1) < 3600)
          {
            readingsSingleUpdate($hash, "playerPlayTime", strftime("%M:\%S", gmtime($1)), 1);
          }
          else
          {
            readingsSingleUpdate($hash, "playerPlayTime", strftime("\%H:\%M:\%S", gmtime($1)), 1);
          }
        }
        else
        {
          delete $hash->{READINGS}{playerPlayTime};
        }
        
        if($data =~ /'totaltime':(.+),/)
        {
          # Playing radio delivers that total time
          if($1 eq "65535")
          {
            delete $hash->{READINGS}{playerTotalPlayTime};            
          }
          elsif(int($1) < 3600)
          {
            readingsSingleUpdate($hash, "playerTotalPlayTime", strftime("%M:\%S", gmtime($1)), 1);
          }
          else
          {
            readingsSingleUpdate($hash, "playerTotalPlayTime", strftime("\%H:\%M:\%S", gmtime($1)), 1);
          }          
        }
        else
        {
          delete $hash->{READINGS}{playerTotalPlayTime};
        }
        
        if($data =~ /'muteStatus':(.+),/)
        {
          if($1 == 1)
          {
            readingsSingleUpdate($hash, "mute", "on", 1);
          }
          else
          {
            readingsSingleUpdate($hash, "mute", "off", 1);
          }
        }
        
        # typo in the (buggy) Streamium firmware...
        if($data =~ /'playStaus':(.+),/)
        {
          if($1 == 1)
          {
            readingsSingleUpdate($hash, "playerPlaying", "yes", 1);
          }        
          else
          {
            delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
            readingsSingleUpdate($hash, "playerPlaying", "no", 1);            
          }
        }
        else
        {
          delete $hash->{READINGS}{$_} foreach (grep /player/, keys %{$hash->{READINGS}});
          readingsSingleUpdate($hash, "playerPlaying", "no", 1);
        }
      }
      elsif($cmd eq "homestatus")
      {
        # Homestatus answers with
        # {'command':'NOTHING',\n'value':0}
        
        # Do nothing ?
      }
      elsif ($cmd eq "getMediaRendererDesc")
      {
        if($data =~ /<manufacturer>(.+)<\/manufacturer>/)
        {
          $hash->{helper}{dInfo}{MANUFACTURER} = $1;
        }
        
        if($data =~ /<manufacturerURL>(.+)<\/manufacturerURL>/)
        {
          $hash->{helper}{dInfo}{MANUFACTURER_URL} = $1;
        }
        
        if($data =~ /<manufacturerURL>(.+)<\/manufacturerURL>/)
        {
          $hash->{helper}{dInfo}{MANUFACTURER_URL} = $1;
        }
        
        if($data =~ /<presentationURL>(.+)<\/presentationURL>/)
        {
          $hash->{helper}{dInfo}{PRESENTATION_URL} = $1;
        }
        
        if($data =~ /<deviceType>(.+)<\/deviceType>/)
        {
          $hash->{helper}{dInfo}{UPNP_DEVICE_TYPE} = $1;
        }
        
        if($data =~ /<friendlyName>(.+)<\/friendlyName>/)
        {
          $hash->{helper}{dInfo}{FRIENDLY_NAME} = $1;
        }        
        if($data =~ /<UDN>(.+)<\/UDN>/)
        {
          my $uuid = uc($1);
          $uuid =~ s/UUID://g;
          $hash->{helper}{dInfo}{UUID} = $uuid;
        }
        
        if($data =~ /<UPC>(.+)<\/UPC>/)
        {
          $hash->{helper}{dInfo}{UPC} = $1;
        }       
        
        if($data =~ /<modelName>(.+)<\/modelName>/)
        {
          $hash->{helper}{dInfo}{MODEL_NAME} = $1;
        }       
        if($data =~ /<modelNumber>(.+)<\/modelNumber>/)
        {
          $hash->{helper}{dInfo}{MODEL_NUMBER} = $1;
        }
        
        if($data =~ /<serialNumber>(.+)<\/serialNumber>/)
        {
          $hash->{helper}{dInfo}{SERIAL_NUMBER} = uc($1);
        }
        if($data =~ /<modelDescription>(.+)<\/modelDescription>/)
        {
          $hash->{helper}{dInfo}{MODEL_DESCRIPTION} = $1;
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
          my $port    = "";
          
          if (uc($hash->{MODEL}) eq "NP3700")
          {
            $port = 7123;
          }
          elsif
          (
            (uc($hash->{MODEL}) eq "NP3500") or
            (uc($hash->{MODEL}) eq "NP3900") or
            (uc($hash->{MODEL}) eq "AW9000")
          )
          {
            $port = 49153;
          }
          
          my $i = 1;
          
          while ($data =~ /<url>(.+?)<\/url>/g)
          {
            # May have several urls according to the UPNP/DLNA standard
            $hash->{helper}{dInfo}{"DEVICE_ICON_$i"} = "http://$address:$port/$1";            
            $i++;
          }          
        }      
      }
      elsif ($cmd eq "getPresets")
      {        
        $hash->{helper}{TOTALINETRADIOPRESETS} = 0 if(not defined($hash->{helper}{TOTALINETRADIOPRESETS})); 
        
        # This command must be processed hierarchicaly through the navigation path
        if($hash->{helper}{cmdStep} == 1)
        {
          $hash->{helper}{cmdStep} = 2;
          # Internet radio
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "","getPresets", "noArg");
        }
        elsif($hash->{helper}{cmdStep} == 2)
        {
          $hash->{helper}{cmdStep} = 3;
          # Presets
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$02\$001\$0", "","getPresets", "noArg");
        }
        elsif($hash->{helper}{cmdStep} == 3)
        {
          my $listedItems;       # Visible Items in the display. Max 8
          my $nextreqURL;
          my $i;
          my $presetID = 0;
          my $presetName;

          # Parse first 8 Presets
          if($data =~ /<title>Error<\/title>/)
          {
            # In case on presets defined the player returns an Error
            # Do nothing
            $hash->{helper}{TOTALINETRADIOPRESETS} = 0;
            readingsSingleUpdate($hash, "totalPresets", "0", 1);
            delete $hash->{READINGS}{Reading_presets};
          }
          else
          {
            if ($data =~ /'nextrequrl':'(.+?)',/)
            {
              $nextreqURL = $1;
              #Log3 $name, 5, "NextreqURL: $nextreqURL";
            }

            if ($data =~ /'totalListCount':(.+),/)
            {
              $hash->{helper}{TOTALINETRADIOPRESETS} = $1;
              readingsSingleUpdate($hash, "totalPresets", $1, 1);
              #Log3 $name, 5, "ListedItems: $listedItems";
            }
            
            $data =~ s/\R//g;        # Remove new lines			
            
            readingsBeginUpdate($hash);
            
            while ($data =~ /{'title':'(.+?)',/g)
            {            
              
              $presetName = $1;

              if($data =~ /'id':(.+?),/g)
              {
                $presetID = $1;
              }
              if ($presetID ne "" and $presetName ne "")
              {
                readingsBulkUpdate($hash, sprintf(".inetRadioPreset_%02d", $presetID), $presetName);
              }                                                                      
            }
            readingsEndUpdate($hash, 1);

            if($presetID < ($hash->{helper}{TOTALINETRADIOPRESETS})) # Maximum listed items = 8. Get the next items by sending the nextreqURL
            {
              # External Command. Not from buffer timer.
              $hash->{helper}{fromSendCommandBuffer} = 0;
              PHILIPS_AUDIO_SendCommand($hash, $nextreqURL, "","getPresets", "noArg"); 
            }
            else
            {
              readingsSingleUpdate($hash, "playerListStatus", "ready", 1);
              delete $hash->{READINGS}{Reading_presets};
              delete $hash->{READINGS}{readingPresets};
              $hash->{helper}{cmdStep} = 4;
              # Finished
            }
          }
        }
      }      
      elsif ($cmd eq "getFavorites")
      { 
        $hash->{helper}{TOTALINETRADIOFAVORITES} = 0 if(not defined($hash->{helper}{TOTALINETRADIOFAVORITES}));
                
        # This command must be processed hierarchicaly through the navigation path
        if($hash->{helper}{cmdStep} == 1)
        {
          $hash->{helper}{cmdStep} = 2;
          # Internet radio
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$01\$001\$0", "","getFavorites", "noArg");
        }
        elsif($hash->{helper}{cmdStep} == 2)
        {
          $hash->{helper}{cmdStep} = 3;
          # Favorites
          PHILIPS_AUDIO_SendCommand($hash, "/nav\$03\$02\$002\$0", "","getFavorites", "noArg");
        }
        elsif($hash->{helper}{cmdStep} == 3)
        {
          if($data =~ /<title>Error<\/title>/)
          {
            # In case on presets defined the player returns an Error
            # Do nothing
            $hash->{helper}{TOTALINETRADIOFAVORITES} = 0;
            readingsSingleUpdate($hash, "totalFavorites", "0", 1);
            delete $hash->{READINGS}{Reading_favorites};
          }
          else
          {
            my $listedItems;       # Visible Items in the display. Max 8
            my $nextreqURL;
            my $i;
            my $favoriteID = 0;
            my $favoriteName;

            # Parse first 8 Presets

            if ($data =~ /'nextrequrl':'(.+?)',/)
            {
              $nextreqURL = $1;
              #Log3 $name, 5, "NextreqURL: $nextreqURL";
            }

            if ($data =~ /'totalListCount':(.+),/)
            {
              $hash->{helper}{TOTALINETRADIOFAVORITES} = $1;
              readingsSingleUpdate($hash, "totalFavorites", $1, 1);
            }
            
            $data =~ s/\R//g;        # Remove new lines
            
            readingsBeginUpdate($hash);
            
            while($data =~ /{'title':'(.+?)',/g)
            {            
              $favoriteName = $1;
                
              if($data =~ /'id':(.+?),/g)
              {
                $favoriteID = $1;
              }
              if ($favoriteID ne "" and $favoriteName ne "")
              {
                readingsBulkUpdate($hash, sprintf(".inetRadioFavorite_%02d", $favoriteID), $favoriteName);
              }
            }
            
            readingsEndUpdate($hash, 1);

            #Log3 $name, 5, "FavoriteIDNachLoop: $favoriteID"; 

            if($favoriteID < ($hash->{helper}{TOTALINETRADIOFAVORITES})) # Maximum listed items = 8. Get the next items by sending the nextreqURL
            {
              # External Command. Not from buffer timer.
              $hash->{helper}{fromSendCommandBuffer} = 0;
              
              PHILIPS_AUDIO_SendCommand($hash, $nextreqURL, "","getFavorites", "noArg"); 
            }
            else
            {
              readingsSingleUpdate($hash, "playerListStatus", "ready", 1);
              delete $hash->{READINGS}{Reading_favorites};
              delete $hash->{READINGS}{readingFavorites};
              $hash->{helper}{cmdStep} = 4;
              # Finished
            }
          }  
        }     
      }      
      elsif($cmd =~ /input|selectStream/)
      {
        $data =~ s/\R//g;        # Remove new lines for regex
        
        if($arg eq "---")
        {
          # Do nothing
        }        
        elsif($arg =~ /internetRadio|onlineServices|mediaLibrary|(\d{3})_(.+?)_|lvl_(.+?)/) # 000_[c|i]_******
        {
          # don't update menu content if playable item was chosen
          if (defined $1)
          {
            if ($2 eq "i")
            {
              $hash->{helper}{networkRequest} = "idle";
              $hash->{helper}{playerState}   = "playing";
              # Stream selected. Manual operation finished.
              $hash->{helper}{manualOperation} = 0;
              
              readingsBeginUpdate($hash);
              readingsBulkUpdate ($hash, "networkRequest", "idle");  
              readingsBulkUpdate ($hash, "playerListStatus", "ready");
              readingsBulkUpdate ($hash, "playerState", "playing");
              readingsBulkUpdate ($hash, ".manualOperation", "no");
              readingsEndUpdate  ($hash, 1);
              
              PHILIPS_AUDIO_SendCommand($hash, "/nowplay", "","nowplay", "noArg");
              
              # Stream selected trigger getStatus
              PHILIPS_AUDIO_ResetTimer($hash); # getStatus              
              return;
            }
          }
          
          if ($data =~ /{'command':'NOTHING','value':0}|<title>Error<\/title>/)
          {
            my $errorMessage = "Player responded with unspecified error";
            
            if($data =~ /alert\(\'(.*?)\'\);|\'command\':\'(.*?)\'/)
            {
              $errorMessage = $1;
            }
            # Delete old readings			
            delete $hash->{READINGS}{$_} foreach (grep /listItem_...$/, keys %{$hash->{READINGS}});
            delete $hash->{READINGS}{$_} foreach (grep /.listItemTarget_...$/, keys %{$hash->{READINGS}});
            
            $hash->{helper}{networkRequest} = "idle";
            $hash->{helper}{manualOperation} = 0;
            
            readingsBeginUpdate($hash);            
            readingsBulkUpdate ($hash, "networkRequest", "idle");            
            readingsBulkUpdate ($hash, "listItem_001", "$errorMessage");
            readingsBulkUpdate ($hash, ".listItemTarget_001", "$hash->{helper}{currentNavUrl}");
            readingsBulkUpdate ($hash, "playerListStatus", "ready");
            readingsBulkUpdate ($hash, ".manualOperation", "no");            
            readingsEndUpdate  ($hash, 1);
            
            return "Player response: $errorMessage.";
          }
          
          my $listDepthLevel = 0;
          my $playerListTotalCount = 0;
          my $listId = 0;
          my $listItems = "";
          
          readingsBeginUpdate($hash);
          
          if($data =~ /var listdetails = \{(.*)\};/)
          {
            my $listdetails_temp = $1;
            my $listdetails = $listdetails_temp;
            
            if($listdetails =~ /'totalitems':(.*?),/)
            {
              readingsBulkUpdate($hash, ".listTotalItems", "$1");
            }
            
            $listdetails = $listdetails_temp;
            
            if($listdetails =~ /'totalListCount':(.*?),/)
            {
              $playerListTotalCount = $1;              
              $hash->{helper}{playerListTotalCount} = $1;
              readingsBulkUpdate($hash, "playerListTotalCount", "$1");
            }
            
            $listdetails = $listdetails_temp;
            
            if($listdetails =~ /'depthlevel':(.*?),/)
            {
              $listDepthLevel = $1;
              readingsBulkUpdate($hash, ".listDepthLevel", "$1");
            }				
          }
          
          if($data =~ /var listItem = \{(.*)\};/)
          {
            my $listItems_temp = $1;
            $listItems = $listItems_temp;
            
            if($listItems =~ /'nextrequrl':'(.*?)'/)
            {
              $hash->{helper}{nextUrl} = $1;
              readingsBulkUpdate($hash, ".listNextUrl", "$1");
            }
            
            $listItems = $listItems_temp;
            
            if($listItems =~ /'prevUrl':'(.*?)',/)
            {
              if($1 ne "")
              {
              $hash->{helper}{prevUrl} = $1;
              readingsBulkUpdate($hash, ".listPrevUrl", "$1");
              }
              else
              {
              $hash->{helper}{prevUrl} = "-";
              readingsBulkUpdate($hash, ".listPrevUrl", "-");
              }
            }			
            
            readingsEndUpdate($hash, 1);
            
            $listItems = $listItems_temp;
            
            if($listItems =~ /'items': \[(.*)\]/)
            {
              
              # Delete old readings			
              delete $hash->{READINGS}{$_} foreach (grep /listItem_...$/, keys %{$hash->{READINGS}});
              delete $hash->{READINGS}{$_} foreach (grep /.listItemTarget_...$/, keys %{$hash->{READINGS}});
              
              # Predefine all listItem readings with "reading..."
              
              readingsBeginUpdate($hash);
              
              for(my $i = 1; ($i < int($hash->{helper}{playerListTotalCount}) + 1) and ($i < AttrVal($name, "maxListItems", 100) + 1); $i++)
              {
                readingsBulkUpdate($hash, "listItem_".sprintf("%03s", $i), "reading...");
              }
              
              my $items = $1;
             
              while ($items =~ /\{(.*?)\}/g)
              {
                my $item = $1;
                my $title = "";
                
                if($item =~ /'title':'(.*?)',/)
                {
                  $title = PHILIPS_AUDIO_html2txt($1);				 
                }
                
                if($item =~ /'id':(.*?),/)
                {
                  $listId = $1;				  
                }
                
                my $itemTarget = "";
                if($item =~ /'target':'(.*?)'/)
                {
                  $itemTarget = $1;
                  readingsBulkUpdate($hash, ".listItemTarget_".sprintf("%03s", int($listId)), $1);
                }				
                if(substr($itemTarget, -1) eq "1")
                {
                  $title = "i_" . $title; # item
                }
                else
                {
                  $title = "c_" . $title; # container
                }				
                readingsBulkUpdate($hash, "listItem_".sprintf("%03s", int($listId)), $title);
              }
              
              readingsEndUpdate($hash, 1);
              
            }
          }
          if($listId < $hash->{helper}{playerListTotalCount})
          {
            # External Command. Not from buffer timer.
            $hash->{helper}{fromSendCommandBuffer} = 0;
            PHILIPS_AUDIO_SendCommand($hash, "$hash->{helper}{nextUrl}", "", "selectStream", "list");
          }
          else
          {
            $hash->{helper}{networkRequest} = "idle";
            
            readingsBeginUpdate($hash);
            readingsBulkUpdate ($hash, "networkRequest", "idle"); 
            readingsBulkUpdate ($hash, "playerListStatus", "ready");
            readingsEndUpdate  ($hash, 1);            
            
          }
        }        
        elsif($arg =~ /list/)
        {
          if ($data =~ /{'command':'NOTHING','value':0}|<title>Error<\/title>/)
          {
            $hash->{helper}{networkRequest} = "idle";
            readingsSingleUpdate($hash, "networkRequest", "idle", 1);
            Log3 $name, 3, "PHILIPS_AUDIO ($name) - Player response: Media Library change not successful.";
            return "Player response: Media Library change not successful.";
          }
          
          $hash->{helper}{networkRequest} = "busy";
          
          readingsBeginUpdate($hash);
          readingsBulkUpdate($hash, "networkRequest", "busy");
          
          $data =~ s/\R//g;        # Remove new lines for regex
          
          my $listDepthLevel = 0;
          my $playerListTotalCount = 0;
          my $listId = 0;
          my $listItems = "";
                
          $listItems = $data;
            
          if($listItems =~ /'nextrequrl':'(.*?)'/)
          {
            $hash->{helper}{nextUrl} = $1;
            readingsBulkUpdate($hash, ".listNextUrl", "$1");
          }
          
          $listItems = $data;
          
          if($listItems =~ /'prevUrl':'(.*?)',/)
          {
            if($1 ne "")
            {
            $hash->{helper}{prevUrl} = $1;
            readingsBulkUpdate($hash, ".listPrevUrl", "$1");
            }
            else
            {
            $hash->{helper}{prevUrl} = "-";
            readingsBulkUpdate($hash, ".listPrevUrl", "-");
            }
          }			
          
          $listItems = $data;
          
          if($listItems =~ /'items': \[(.*)\]/)
          {
            my $items = $1;
                        
            while ($items =~ /\{(.*?)\}/g)
            {
              my $item_temp = $1;
              my $item = $item_temp;
              
              my $title = "";
              if($item =~ /'title':'(.*?)',/)
              {
                $title = PHILIPS_AUDIO_html2txt($1);				 
              }
              $item = $item_temp;
              if($item =~ /'id':(.*?),/)
              {
                $listId = $1;                
              }
              
              $item = $item_temp;
              my $itemTarget = "";
              if($item =~ /'target':'(.*?)'/)
              {
                $itemTarget = $1;
                readingsBulkUpdate($hash, ".listItemTarget_".sprintf("%03s", int($listId)), $1);
              }	
              
              if(substr($itemTarget, -1) eq "1")
              {
                $title = "i_" . $title; # item
              }
              else
              {
                $title = "c_" . $title; # container
              }				
              readingsBulkUpdate($hash, "listItem_".sprintf("%03s", int($listId)), $title);
              
              last if($listId eq AttrVal($name, "maxListItems", 100));
            }
          }
          
          if(($listId < $hash->{helper}{playerListTotalCount}) && ($listId < AttrVal($name, "maxListItems", 100)))
          {
            # External Command. Not from buffer timer.
            $hash->{helper}{fromSendCommandBuffer} = 0;
            
            PHILIPS_AUDIO_SendCommand($hash, "$hash->{helper}{nextUrl}", "", "selectStream", "list");
          }
          else
          {
            $hash->{helper}{networkRequest} = "idle";
            readingsBulkUpdate($hash, "networkRequest", "idle");
            readingsBulkUpdate($hash, "playerListStatus", "ready");            
          }
          
          readingsEndUpdate($hash, 1);
        }       
               
      }      
      
      $hash->{helper}{networkRequest} = "idle";
      readingsSingleUpdate($hash, "networkRequest", "idle", 1);
    }    
    return;
}

#############################
# converts straight volume in percentage volume (volumestraightmin .. volumestraightmax => 0 .. 100%)
sub PHILIPS_AUDIO_volume_rel2abs
{
  my ($hash, $percentage) = @_;
  
  return int($percentage * 64 / 100);
}

#############################
# converts relative volume to "straight" volume (0 .. 100% => volumestraightmin .. volumestraightmax)
sub PHILIPS_AUDIO_volume_abs2rel
{
  my ($hash, $absolute) = @_;
  
  return int($absolute * 100 /  64);    
}

#############################
# Restarts the internal status request timer according to the given interval or current receiver state
sub PHILIPS_AUDIO_ResetTimer
{
  my ($hash, $interval) = @_;

  RemoveInternalTimer($hash, "PHILIPS_AUDIO_GetStatus");

  if($hash->{helper}{DISABLED} == 0)
  {
    if(defined($interval))
    {
      InternalTimer(gettimeofday() + $interval, "PHILIPS_AUDIO_GetStatus", $hash);
    }
    elsif((exists($hash->{READINGS}{presence}{VAL}) and $hash->{READINGS}{presence}{VAL} eq "present") and (exists($hash->{READINGS}{power}{VAL}) and $hash->{READINGS}{power}{VAL} eq "on"))
    {
      InternalTimer(gettimeofday() + $hash->{helper}{ON_INTERVAL}, "PHILIPS_AUDIO_GetStatus", $hash);
    }
    else
    {
      InternalTimer(gettimeofday() + $hash->{helper}{OFF_INTERVAL}, "PHILIPS_AUDIO_GetStatus", $hash);
    }
  }  
  return;
}

#############################
# convert all HTML entities into UTF-8 equivalent

sub PHILIPS_AUDIO_html2txt
{
  my ($string) = @_;

  $string =~ s/(&amp;amp;quot;|&amp;quot;|&quot;|\\")/\"/g;
  $string =~ s/(&amp;amp;|&amp;)/&/g;  
  $string =~ s/&nbsp;/ /g;
  $string =~ s/(&apos;|\\'|\')/'/g;
  $string =~ s/(\xe4|&auml;)/ä/g;
  $string =~ s/(\xc4|&Auml;)/Ä/g;
  $string =~ s/(\xf6|&ouml;)/ö/g;
  $string =~ s/(\xd6|&Ouml;)/Ö/g;
  $string =~ s/(\xfc|&uuml;)/ü/g;
  $string =~ s/(\xdc|&Uuml;)/Ü/g;
  $string =~ s/(\xdf|&szlig;)/ß/g;

  return $string;
}

sub PHILIPS_AUDIO_getMediaRendererDesc
{
  # queries the addition model descriptions
  my ($hash) = @_;
  
  my $name = $hash->{NAME};
  
  Log3 $name, 5, "PHILIPS_AUDIO ($name) - execute nonblocking \"MediaRendererDesc\"";
  
  my $url = "";
  my $port = "";
  
  if(uc($hash->{MODEL}) eq "NP3700")
  {
    $url = "http://$hash->{IP_ADDRESS}:7123/DeviceDescription.xml";
  }
  elsif
  (
    (uc($hash->{MODEL}) eq "NP3500") or
    (uc($hash->{MODEL}) eq "NP3900") or
    (uc($hash->{MODEL}) eq "AW9000")
  )
  {
    $url = "http://$hash->{IP_ADDRESS}:49153/nmrDescription.xml";
  }
  else
  {
    return "Unknown Device.";
  }
  
  HttpUtils_NonblockingGet({
                            url        => $url,
                            timeout    => AttrVal($name, "requestTimeout", 10),
                            noshutdown => 1,
                            data       => "",
                            loglevel   => ($hash->{helper}{AVAILABLE} ? undef : 5),
                            hash       => $hash,
                            cmd        => "getMediaRendererDesc",
                            arg        => "noArg",
                            callback   => \&PHILIPS_AUDIO_ParseResponse                        
                          });
  return;
}

1;

=pod
=item device
=item summary    controls a Philips Streamium Network Player in a local network
=item summary_DE steuert einen Philips Streamium Netzwerkplayer im lokalen Netzwerk
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
    This module controls a Philips Audio Player e.g. MCi, Streamium or Fidelio and potentially any other device controlled by the "myRemote" app.<br>
    You might also check, opening the following URL in the browser: http://[ip number of your device]:8889/index
    <br><br>
    (Tested on: AW9000, NP3500, NP3700 and NP3900)  
    <br><br>
    Example:<br><br>
    <ul>
      <code>
      define player PHILIPS_AUDIO NP3900 192.168.0.15<br><br>
      # With custom status interval of 60 seconds<br>
      define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60</b><br><br>
      # With custom "off"-interval of 60 seconds and "on"-interval of 10 seconds<br>
      define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60 10</b><br>
      </code>
      <br>
      <i>Note: Due to slow command processing by the player itself the minimum interval is <b>limited to 5 seconds</b>. More frequent polling might cause device freezes.</i>
    </ul>   
  </ul>
  <br>  
  <a name="PHILIPS_AUDIOset"></a>
  <b>Set</b>
  <ul>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code><br><br>
    <i>Note: Commands and parameters are case sensitive.</i><br>
      <ul><br>
      <li><b>favoriteAdd</b> &ndash; Adds currently played Internet Radio stream to favorites</li>
      <li><b>favoriteRemove</b> &ndash; Removes currently played Internet Radio stream from favorites</li>
      <li><b>getFavorites</b> &ndash; Reads stored favorites from the device (may take some time...)</li>
      <li><b>getMediaRendererDesc</b> &ndash; Reads device specific information (stored in the deviceInfo reading)</li>
      <li><b>getPresets</b> &ndash; Reads stored presets from the device (may take some time...)</li>
      <li><b>input</b> &ndash; Selects the following input</li>
      <ul>
      <li><b>analogAux</b> &ndash; Selects the analog AUX input (AW9000 only)</li>
      <li><b>digital1Coaxial</b> &ndash; Selects the digital coaxial input (AW9000 only)</li>
      <li><b>digital2Optical</b> &ndash; Selects the digital optical input (AW9000 only)</li>      
      <li><b>internetRadio</b> &ndash; Selects the Internet Radio input</li>
      <li><b>mediaLibrary</b> &ndash; Selects the Media Library input (UPnP/DLNA server) (not available on AW9000)</li>
      <li><b>mp3Link</b> &ndash; Selects the analog MP3 Link input (not available on AW9000)</li>
      <li><b>onlineServices</b> &ndash; Selects the Online Services input</li>
      </ul>
      <li><b>mute [ on | off ]</b> &ndash; Mutes/unmutes the device</li>
      <li><b>player</b> &ndash; Player related commands</li>
      <ul>
      <li><b>next</b> &ndash; Selects next audio stream</li>
      <li><b>prev</b> &ndash; Selects previous audio stream</li>
      <li><b>play-pause</b> &ndash; Plays/pauses the current audio stream</li>
      <li><b>stop</b> &ndash; Stops the current audio stream</li>
      </ul>
      <li><b>repeat [ single | all | off]</b> &ndash; Selects the repeate mode</li>
      <li><b>selectFavorite [ name ]</b> &ndash; Selects a favorite. Empty if no favorites found. (see also getFavorites)</li>
      <li><b>selectFavoriteByNumber [ number ]</b> &ndash; Selects a favorite by its number. Empty if no favorites found. (see also getFavorites)</li>
      <li><b>selectPreset [ name ]</b> &ndash; Selects a preset. Empty if no presets found. (see also getPresets)</li>
      <li><b>selectPresetByNumber [ number ]</b> &ndash; Selects a preset by its number. Empty if no presets found. (see also getPresets)</li>
      <li><b>selectStream [ name ]</b> &ndash; Context-sensitive. Selects a stream depending on the current input and player list content. A 'c'-prefix represents a 'container' (directory). An 'i'-prefix represents an 'item' (audio stream).</li>
      <li><b>shuffle [ on | off ]</b> &ndash; Sets the shuffle mode</li>
      <li><b>standbyButton</b> &ndash; Emulates the standby button. Toggles between standby and power on</li>
      <li><b>volume</b> &ndash; Sets the relative volume 0...100%</li>
      <li><b>volumeDown</b> &ndash; Sets the device specific volume by one decrement</li>
      <li><b>volumeStraight</b> &ndash; Sets the device specific absolute volume 0...64</li>
      <li><b>volumeUp</b> &ndash; Sets the device specific volume by one increment</li>      
    </ul>
  </ul>
  <br>
  <a name="PHILIPS_AUDIOget"></a>
  <b>Get</b>
  <ul>
    <code>
      get &lt;name&gt; &lt;reading&gt &lt;reading name&gt;
    </code>
    <ul>
      <br>
      <li><b>deviceInfo</b> &ndash; Returns device specific information</li>
      <li><b>reading</b></li>
      <ul>
        <li><b>input</b> &ndash; Returns current input or '-' if not playing</li>
        <li><b>listItem_xxx</b> &ndash; Returns player list item (limited to 999 entries)</li>
        <li><b>networkError</b> &ndash; Shows an occured current network error</li>
        <li><b>networkRequest</b> &ndash; Shows current network activity (idle/busy)</li>
        <li><b>power</b> &ndash; Returns power status (on/off)</li>
        <li><b>playerAlbum</b> &ndash; Returns the album name of played stream</li>
        <li><b>playerAlbumArt</b> &ndash; Returns the album art of played audio stream</li>
        <li><b>playerListStatus</b> &ndash; Returns current player list status (busy/ready)</li>
        <li><b>playerListTotalCount</b> &ndash; Returns number of player list entries</li>
        <li><b>playerPlayTime</b> &ndash; Returns audio stream duration</li>
        <li><b>playerPlaying</b> &ndash; Returns current player playing state (yes/no)</li>
        <li><b>playerRadioStation</b> &ndash; Returns the name of played radio station</li>
        <li><b>playerRadioStationInfo</b> &ndash; Returns additional info of the played radio station</li>
        <li><b>playerRepeat</b> &ndash; Returns current repeat mode (off/single/all)</li>
        <li><b>playerShuffle</b> &ndash; Returns current shuffle mode (on/off)</li>
        <li><b>playerState</b> &ndash; Returns current player state (home/browsing/playing)</li>
        <li><b>playerStreamFavorite</b> &ndash; Shows if audio stream is a favorite (yes/no)</li>
        <li><b>playerStreamRating</b> &ndash; Shows rating of the audio stream</li>
        <li><b>playerTitle</b> &ndash; Returns audio stream's title</li>
        <li><b>playerTotalTime</b> &ndash; Shows audio stream's total time</li>
        <li><b>presence</b> &ndash; Returns peresence status (present/absent)</li>
        <li><b>state</b> &ndash; Returns current state (on/off)</li>
        <li><b>totalFavorites</b> &ndash; Returns total number of stored favorites (see getFavorites)</li>
        <li><b>totalPresets</b> &ndash; Returns total number of stored presets (see getPresets)</li>
        <li><b>volume</b> &ndash; Returns current relative volume (0...100%)</li>
        <li><b>volumeStraight</b> &ndash; Returns current device absolute volume (0...64)</li>    
      </ul>
    </ul>
    <br>
  </ul>
  <a name="PHILIPS_AUDIOattr"></a>  
  <b>Attributes</b><br><br>
  <ul>
    <ul>  
      <li><b>autoGetFavorites</b> &ndash; Automatically read favorites from device if none available (default off)</li>
      <li><b>autoGetPresets</b> &ndash; Automatically read presets from device if none available (default off)</li>
      <li><b>do_not_notify</b></li>
      <li><b>httpBufferTimeout</b> &ndash; Optional attribute defing the internal http buffer timeount (default 10)</li>
      <li><b>maxListItems</b> &ndash; Defines max. number of player list items (default 100)</li>
      <li><b>playerBrowsingTimeout</b> &ndash; Defines the inactivity timeout for browsing. After that timeout the player returns to the state 'home' in which the readings are updated automaically again. (default 180 seconds)</li>
      <li><b>readingFnAttributes</b></li>
      <li><b>requestTimeout</b> &ndash; Optional attribute defining the http response timeout (default 4 seconds)</li>      
    </ul>
  </ul>
  <br>
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
    Mit Hilfe dieses Moduls lassen sich Philips Audio Netzwerk Player wie z.B. MCi, Streamium oder Fidelio im lokalen Netzwerk steuern.<br>
    Ger&auml;te, die &uuml;ber die myRemote App oder einen internen HTTP Server am Port 8889 sollten theoretisch ebenfalls bedient werden k&ouml;nnen.<br>
    (http://[ip Nummer des Ger&auml;tes]:8889/index)<br>
    <br>
    (Getestet mit: AW9000, NP3500, NP3700 und NP3900)
    <br><br>
    Beispiel:<br>
    <ul><br>
      <code>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15
        <br>
        <br>
        # 60 Sekunden Intervall<br>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60</b>
        <br>
        <br>
        # 60 Sekunden Intervall f&uuml;r "off" und 10 Sekunden f&uuml;r "on"<br>
        define PHAUDIO_player PHILIPS_AUDIO NP3900 192.168.0.15 <b>60 10</b>
        </code>        
        <br><br>
      <i>Bemerkung: Aufgrund der relativ langsamen Verarbeitung von Befehlen durch den Player selbst wurde das minimale Intervall <b>auf 5 Sekunden limitiert</b>. Dadurch sollten potentielle Ger&auml;tefreezes reduziert werden.</i>
    </ul>   
  </ul><br>  
  <a name="PHILIPS_AUDIOset"></a>
  <b>Set</b>
  <ul>
    <code>
      set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]
    </code>
    <br><br>
    <i>Bemerkung: Befehle und Parameter sind case-sensitive</i><br>
    <ul><br>
      <li><b>favoriteAdd</b> &ndash; F&uuml;gt den aktuellen Audiostream zu Favoriten hinzu</li>
      <li><b>favoriteRemove</b> &ndash; L&ouml;scht den aktuellen Audiostream aus den Favoriten</li>
      <li><b>getFavorites</b> &ndash; Liest aus die gespeicherten Favoriten aus dem Ger&auml;t (kann einige Zeit dauern...)</li>
      <li><b>getMediaRendererDesc</b> &ndash; Liest aus Ger&auml;tspezifische Informationen aus (siehe auch deviceInfo reading)</li>
      <li><b>getPresets</b> &ndash; Liest aus die gespeicherten Presets aus dem Ger&auml;t (kann einige Zeit dauern...)</li>
      <li><b>input</b> &ndash; Schaltet auf den folgenden Eingang</li>
      <ul>
      <li><b>analogAux</b> &ndash; AUX input (nur AW9000)</li>
      <li><b>digital1Coaxial</b> &ndash; digital coaxial input (nur AW9000)</li>
      <li><b>digital2Optical</b> &ndash; digital optical input (nur AW9000)</li>      
      <li><b>internetRadio</b> &ndash; Internet Radio</li>
      <li><b>mediaLibrary</b> &ndash; Media Library (UPnP/DLNA server) (nicht verf&uuml;gbar beim AW9000)</li>
      <li><b>mp3Link</b> &ndash; Analoger MP3 Link (nicht verf&uuml;gbar beim AW9000)</li>
      <li><b>onlineServices</b> &ndash; Online Services</li>
      </ul>
      <li><b>mute [ on | off ]</b> &ndash; Stummschaltung (an/aus)</li>
      <li><b>player</b> &ndash; Player-Befehle</li>
      <ul>
      <li><b>next</b> &ndash; N&auml;chstee Audiostream</li>
      <li><b>prev</b> &ndash; Letzter Audiostream</li>
      <li><b>play-pause</b> &ndash; Play/pause des aktuellen Audiostreams</li>
      <li><b>stop</b> &ndash; Stoppt das Abspielen des aktuellen Audiostreams</li>
      </ul>
      <li><b>repeat [ single | all | off]</b> &ndash; Stellt den repeat mode ein</li>
      <li><b>selectFavorite [ name ]</b> &ndash; W&auml;hlt einen Favoriten. Leer falls keine Favoriten vorhanden (s. getFavorites)</li>
      <li><b>selectFavoriteByNumber [ number ]</b> &ndash; W&auml;hlt einen Favoriten anhand seiner Speichernummer. Leer falls keine Favoriten vorhanden (s. getFavorites)</li>
      <li><b>selectPreset [ name ]</b> &ndash; W&auml;hlt einen Preset. Leer falls keine Presets vorhanden (s. getPresets)</li>
      <li><b>selectPresetByNumber [ number ]</b> &ndash; W&auml;hlt einen Preset anhand seiner Speichernummer. Leer falls keine Presets vorhanden (see also getPresets)</li>
      <li><b>selectStream [ name ]</b> &ndash; Context-sensitive. W&auml;hlt einen Audiostream. H&auml;ngt vom aktuellen Inhalt der Playerlist ab. Ein 'c'-Pr&auml;fix repr&auml;sentiert einen 'Container' (Directory). ein 'i'-Pr&auml;fix repr&auml;sentiert ein 'Item' (audio stream).</li>
      <li><b>shuffle [ on | off ]</b> &ndash; W&auml;hlt den gew&uuml;nschten Shuffle Modus</li>
      <li><b>standbyButton</b> &ndash; Emuliert den standby-Knopf. Toggelt zwischen standby und power on</li>
      <li><b>volume</b> &ndash; Setzt die relative Lautst&auml;rke 0...100%</li>
      <li><b>volumeDown</b> &ndash; Setzt die Lautst&auml;rke um ein Dekrement herunter</li>
      <li><b>volumeStraight</b> &ndash; Setzt die devicespezifische Lautst&auml;rke 0...64</li>
      <li><b>volumeUp</b> &ndash; Setzt die Lautst&auml;rke um ein Inkrement herauf</li>      
    </ul>
  </ul>
  <br>
  <a name="PHILIPS_AUDIOget"></a>
  <b>Get</b>        
  <ul>
    <code>
      get &lt;name&gt; &lt;reading&gt &lt;reading name&gt;
    </code>
    <ul>
      <br>
      <li><b>deviceInfo</b> &ndash; Liefert devicespezifische Information</li>
      <li><b>reading</b></li>
      <ul>
        <li><b>input</b> &ndash; Liefert den aktuellen Eingang oder '-' falls kein Audiostream aktiv</li>
        <li><b>listItem_xxx</b> &ndash; Liefert Eintr&auml;ge der Playerliste (limitiert auf 999 Eintr&auml;ge)</li>
        <li><b>networkError</b> &ndash; Liefert einen potentiellen Netzwerkfehler</li>
        <li><b>networkRequest</b> &ndash; Liefert die aktuelle Netzwerkaktivit&auml;t (idle/busy)</li>
        <li><b>power</b> &ndash; Liefert den Power-Status (on/off)</li>
        <li><b>playerAlbum</b> &ndash; Liefert den Albumnamen des aktiven Audiostreams</li>
        <li><b>playerAlbumArt</b> &ndash; Liefert die Albumart des aktiven Audiostreams</li>
        <li><b>playerListStatus</b> &ndash; Liefert den aktuellen Zusatand der Playlist (busy/ready)</li>
        <li><b>playerListTotalCount</b> &ndash; Liefert die Anzahl der Playlisteintr&auml;ge</li>
        <li><b>playerPlayTime</b> &ndash; Liefert die aktuell Audiostreamspieldauer</li>
        <li><b>playerPlaying</b> &ndash; Zeigt an, ob Audiostream abgespielt wird (yes/no)</li>
        <li><b>playerRadioStation</b> &ndash; Liefert den Stationsnamen des Radiosenders</li>
        <li><b>playerRadioStationInfo</b> &ndash; Liefert zus&auml;tzliche Informationen des Radiosenders</li>
        <li><b>playerRepeat</b> &ndash; Zeigt den Reapeat Mode an (off/single/all)</li>
        <li><b>playerShuffle</b> &ndash; Zeigt den aktuellen Shuffle mode an (on/off)</li>
        <li><b>playerState</b> &ndash; Zeigt den Playerzustand an (home/browsing/playing)</li>
        <li><b>playerStreamFavorite</b> &ndash; Zeigt an, ob aktueller Audiostream ein Favorit ist (yes/no)</li>
        <li><b>playerStreamRating</b> &ndash; Zeigt das rating des Audiostreams</li>
        <li><b>playerTitle</b> &ndash; Zeigt den Titel des Audiostreams an</li>
        <li><b>playerTotalTime</b> &ndash; Zeigt die Audiostreamdauer an</li>
        <li><b>presence</b> &ndash; Liefert den presence status (present/absent)</li>
        <li><b>state</b> &ndash; Lifert den aktuellen Ger&auml;testatus (on/off)</li>
        <li><b>totalFavorites</b> &ndash; Liefert die Anzahl gepseicherter Favoriten (s. getFavorites)</li>
        <li><b>totalPresets</b> &ndash; Liefert die Anzahl gepseicherter Presets (see getPresets)</li>
        <li><b>volume</b> &ndash; Liefert die relative Lutst&auml;rke (0...100%)</li>
        <li><b>volumeStraight</b> &ndash; Liefert die devicespezifische Lautst&auml;rke (0...64)</li>    
      </ul>
    </ul>
    <br>
  </ul>
  <a name="PHILIPS_AUDIOattr"></a>
    <b>Attribute</b><br><br>
    <ul>
      <ul>  
      <li><b>autoGetFavorites</b> &ndash; Automatisches Auslesen der Favoriten beim Modulstart falls keine vorhanden (default off)</li>
      <li><b>autoGetPresets</b> &ndash; Automatisches Auslesen der Presets beim Modulstart falls keine vorhanden (default off)</li>
      <li><b>do_not_notify</b></li>
      <li><b>httpBufferTimeout</b> &ndash; Optionalles Attribut f&uuml;r den internen http buffer timeount (default 10 Sekunden)</li>
      <li><b>maxListItems</b> &ndash; Definiert die max. Anzahl der anzuzeigenden Playerlisteintr&auml;ge (default 100)</li>
      <li><b>playerBrowsingTimeout</b> &ndash; Definiert den Inaktivit&auml;ts-Timeout beim Browsen der Playerlist. Nach diesem Timeout f&auml;llt das Modul in den "home"-State zur&uuml;ck. Die Playerreadings werden wieder aktualisiert (default 180 Sekunden)</li>
      <li><b>readingFnAttributes</b></li>
      <li><b>requestTimeout</b> &ndash; Optionalles Attribut f&uuml;r http responses (default 4 Sekunden)</li>      
      </ul>
    </ul>    
</ul>

=end html_DE

=cut

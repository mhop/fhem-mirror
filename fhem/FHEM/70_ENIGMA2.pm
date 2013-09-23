# $Id$
##############################################################################
#
#     70_ENIGMA2.pm
#     An FHEM Perl module for controlling ENIGMA2 based TV receivers
#     via network connection.
#
#     Copyright by Julian Pawlowski
#     e-mail: julian.pawlowski at gmail.com
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
#
# Version: 1.0
#
# Version History:
# - 1.00 - 2013-09-23
# -- First release
#
##############################################################################

package main;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use XML::Simple;
use IO::Socket;

sub ENIGMA2_Define($$);
sub ENIGMA2_GetStatus($;$);
sub ENIGMA2_Undefine($$);




###################################
sub ENIGMA2_Initialize($) {
  my ($hash) = @_;

  $hash->{GetFn}     = "ENIGMA2_Get";
  $hash->{SetFn}     = "ENIGMA2_Set";
  $hash->{DefFn}     = "ENIGMA2_Define";
  $hash->{UndefFn}   = "ENIGMA2_Undefine";

  $hash->{AttrList}  = "".
                      $readingFnAttributes;
}

#####################################
sub ENIGMA2_GetStatus($;$) {
  my ($hash, $local) = @_;
  my $name = $hash->{NAME};
  my $interval = $hash->{INTERVAL};
  my $state='';
  my $boxinfo;
  my $serviceinfo;
  my $eventinfo;
  my $signalinfo;
  my $vol;
  my $changecount = 0;
  
  $local = 0 unless(defined($local));

  InternalTimer(gettimeofday()+$interval, "ENIGMA2_GetStatus", $hash, 0) unless($local == 1);

  # Read powerstate
  #
  my $powerstate = ENIGMA2_SendCommand($hash, "powerstate", "");

  if (defined($powerstate) && ref($powerstate) eq "HASH") {
    if ($powerstate->{e2instandby} eq "true") {
      $state = "off";
    } else {
      $state = "on";
      # Read Boxinfo
      $boxinfo = ENIGMA2_SendCommand($hash, "about", "");
      $serviceinfo = ENIGMA2_SendCommand($hash, "subservices", "");
      $signalinfo = ENIGMA2_SendCommand($hash, "signal", "");
      $vol = ENIGMA2_SendCommand($hash, "vol", "");
      if (ref($serviceinfo) eq "HASH" && defined($serviceinfo->{e2service})) {
        $eventinfo = ENIGMA2_SendCommand($hash, "epgservicenow", "sRef=".urlEncode($serviceinfo->{e2service}{e2servicereference}));
      }
    }
  } elsif ($hash->{helper}{AVAILABLE} == 1) {
    $state = "undefined";
  } else {
    $state = "absent";
  }

  readingsBeginUpdate($hash);

  # Set reading for power
  #
  my $readingPower = "off";
  if ($state eq "on") {
    $readingPower = "on";
  }
  if (!defined($hash->{READINGS}{power}{VAL}) || $hash->{READINGS}{power}{VAL} ne $readingPower) {
    readingsBulkUpdate($hash, "power", $readingPower, 1);
  }

  # Set reading for state
  #
  if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{state}{VAL} ne $state) {
    readingsBulkUpdate($hash, "state", $state, 1);
  }

  # Set reading for Boxinfos
  #
  if (ref($boxinfo) eq "HASH") {
    my $reading;
    my $e2reading;

    # General
    foreach ( "enigmaversion",
              "imageversion",
              "webifversion",
              "fpversion",
              "lanmac",
              "model",
              "servicenamespace",
              "serviceaspect",
              "serviceprovider",
              "servicevideosize",
              "videowidth",
              "videoheight",
              "apid",
              "vpid",
              "pcrpid",
              "servicevideosize",
              "pmtpid",
              "txtpid",
              "tsid",
              "onid",
              "sid"
            ) {
      $reading = $_;
      $e2reading = "e2".$_;

      if (defined($boxinfo->{e2about}{$e2reading})) {
        if ($boxinfo->{e2about}{$e2reading} eq "False" || $boxinfo->{e2about}{$e2reading} eq "True") {
          if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne lc($boxinfo->{e2about}{$e2reading})) {
    			  readingsBulkUpdate($hash, $reading, lc($boxinfo->{e2about}{$e2reading}), 1);
          }
        } else {
          if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne $boxinfo->{e2about}{$e2reading}) {
    			  readingsBulkUpdate($hash, $reading, $boxinfo->{e2about}{$e2reading}, 1);
          }
        }
      } else {
        if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne "-") {
  			  readingsBulkUpdate($hash, $reading, "-", 1);
        }
      }
    }

    # servicename + channel
    $reading = "servicename";
    $e2reading = "e2".$reading;
    if (defined($boxinfo->{e2about}{$e2reading})) {
      if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne $boxinfo->{e2about}{$e2reading}) {
			  readingsBulkUpdate($hash, $reading, $boxinfo->{e2about}{$e2reading}, 1);
			  readingsBulkUpdate($hash, "channel", $boxinfo->{e2about}{$e2reading}, 1);
      }
    } else {
      if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne "-") {
			  readingsBulkUpdate($hash, $reading, "-", 1);
			  readingsBulkUpdate($hash, "channel", "-", 1);
      }
    }

    # HDD
    # multiple
    if (defined($boxinfo->{e2about}{e2hddinfo}) && ref($boxinfo->{e2about}{e2hddinfo}) eq "ARRAY") {
      my $i=0;
      my $arr_size=@{ $boxinfo->{e2about}{e2hddinfo} };

      while ($i < $arr_size) {
        my $counter = $i + 1;
        my $readingname = "hdd".$counter."_model";
        if (!defined($hash->{READINGS}{$readingname}{VAL}) || $hash->{READINGS}{$readingname}{VAL} ne $boxinfo->{e2about}{e2hddinfo}[$i]{model}) {
          readingsBulkUpdate($hash, $readingname, $boxinfo->{e2about}{e2hddinfo}[$i]{model}, 1);
        }

        $readingname = "hdd".$counter."_capacity";
        my @value = split(/ /, $boxinfo->{e2about}{e2hddinfo}[$i]{capacity});
        if (!defined($hash->{READINGS}{$readingname}{VAL}) || $hash->{READINGS}{$readingname}{VAL} ne $value[0]) {
          readingsBulkUpdate($hash, $readingname, $value[0], 1);
        }

        $readingname = "hdd".$counter."_free";
        @value = split(/ /, $boxinfo->{e2about}{e2hddinfo}[$i]{free});
        if (!defined($hash->{READINGS}{$readingname}{VAL}) || $hash->{READINGS}{$readingname}{VAL} ne $value[0]) {
          readingsBulkUpdate($hash, $readingname, $value[0], 1);
        }

        $i++;
      }
    # single
    } elsif(defined($boxinfo->{e2about}{e2hddinfo}) && ref($boxinfo->{e2about}{e2hddinfo}) eq "HASH") {
      my $readingname = "hdd1_model";
      if (!defined($hash->{READINGS}{$readingname}{VAL}) || $hash->{READINGS}{$readingname}{VAL} ne $boxinfo->{e2about}{e2hddinfo}{model}) {
        readingsBulkUpdate($hash, $readingname, $boxinfo->{e2about}{e2hddinfo}{model}, 1);
      }

      $readingname = "hdd1_capacity";
      my @value = split(/ /, $boxinfo->{e2about}{e2hddinfo}{capacity});
      if (!defined($hash->{READINGS}{$readingname}{VAL}) || $hash->{READINGS}{$readingname}{VAL} ne $value[0]) {
        readingsBulkUpdate($hash, $readingname, $value[0], 1);
      }

      $readingname = "hdd1_free";
      @value = split(/ /, $boxinfo->{e2about}{e2hddinfo}{free});
      if (!defined($hash->{READINGS}{$readingname}{VAL}) || $hash->{READINGS}{$readingname}{VAL} ne $value[0]) {
        readingsBulkUpdate($hash, $readingname, $value[0], 1);
      }
    }

    # Tuner
    if (defined($boxinfo->{e2about}{e2tunerinfo}{e2nim})) {
      my %tuner= %{ $boxinfo->{e2about}{e2tunerinfo}{e2nim} };
      # single
      if ( defined($tuner{type}) ) {
        my $tunerRef = \%tuner;
        my $tuner_name=lc($$tunerRef{name});
        $tuner_name =~ s/\s/_/g;	

        if (!defined($hash->{READINGS}{$tuner_name}{VAL}) || $hash->{READINGS}{$tuner_name}{VAL} ne $$tunerRef{type}) {
          readingsBulkUpdate($hash, $tuner_name, $$tunerRef{type}, 1);
        }

      # multiple	
      } else {
        for (keys %tuner) {
          my $tuner_name=lc($_);
          $tuner_name =~ s/\s/_/g;
          my $tuner_type=$tuner{$_}{type};

          if (!defined($hash->{READINGS}{$tuner_name}{VAL}) || $hash->{READINGS}{$tuner_name}{VAL} ne $tuner_type) {
            readingsBulkUpdate($hash, $tuner_name, $tuner_type, 1);
          }
        }
      }
    }

    # Volume
    if (ref($vol) eq "HASH" && defined($vol->{e2current})) {
      if (!defined($hash->{READINGS}{volume}{VAL}) || $hash->{READINGS}{volume}{VAL} ne $vol->{e2current}) {
        readingsBulkUpdate($hash, "volume", $vol->{e2current}, 1);
      }
    }
    if (ref($vol) eq "HASH" && defined($vol->{e2ismuted})) {
      my $muteState = "on";
      if (lc($vol->{e2ismuted}) eq "false") {
        $muteState = "off";
      }
      if (!defined($hash->{READINGS}{mute}{VAL}) || $hash->{READINGS}{mute}{VAL} ne $muteState) {
        readingsBulkUpdate($hash, "mute", $muteState, 1);
      }
    }

    # servicereference + input + currentMedia
    if (ref($serviceinfo) eq "HASH" && defined($serviceinfo->{e2service})) {
      if (!defined($hash->{READINGS}{servicereference}{VAL}) || $hash->{READINGS}{servicereference}{VAL} ne $serviceinfo->{e2service}{e2servicereference}) {
        readingsBulkUpdate($hash, "servicereference", $serviceinfo->{e2service}{e2servicereference}, 1);
        readingsBulkUpdate($hash, "currentMedia", $serviceinfo->{e2service}{e2servicereference}, 1);

        my @servicetype = split(/:/, $serviceinfo->{e2service}{e2servicereference});
        if ($servicetype[2] eq "2") {
          readingsBulkUpdate($hash, "input", "radio", 1);
        } else {
          readingsBulkUpdate($hash, "input", "tv", 1);
        }
      }
    }

    # Event
    if (ref($eventinfo) eq "HASH" && defined($eventinfo->{e2event})) {
      foreach ( "eventstart",
                "eventduration",
                "eventdescription",
              ) {
        $reading = $_;
        $e2reading = "e2".$_;

        if (defined($eventinfo->{e2event}{$e2reading})) {
          if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne $eventinfo->{e2event}{$e2reading}) {
    			  readingsBulkUpdate($hash, $reading, $eventinfo->{e2event}{$e2reading}, 1);
          }
        } else {
          if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne "-") {
    			  readingsBulkUpdate($hash, $reading, "-", 1);
          }
        }
      }

      # eventtitle + currentTitle
      $reading = "eventtitle";
      $e2reading = "e2".$reading;
      if (defined($eventinfo->{e2event}{$e2reading}) && $eventinfo->{e2event}{$e2reading} ne "N/A") {
        if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne $eventinfo->{e2event}{$e2reading}) {
  			  readingsBulkUpdate($hash, $reading, $eventinfo->{e2event}{$e2reading}, 1);
  			  readingsBulkUpdate($hash, "currentTitle", $eventinfo->{e2event}{$e2reading}, 1);
        }
      } else {
        if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne $boxinfo->{e2about}{e2servicename}) {
  			  readingsBulkUpdate($hash, $reading, $boxinfo->{e2about}{e2servicename}, 1);
  			  readingsBulkUpdate($hash, "currentTitle", $boxinfo->{e2about}{e2servicename}, 1);
        }
      }

      # eventstart_hr
      $reading = "eventstart_hr";
      $e2reading = "e2eventstart";
      if (defined($eventinfo->{e2event}{$e2reading}) && $eventinfo->{e2event}{$e2reading} ne "0") {
        my $timestring = FmtDateTime($eventinfo->{e2event}{$e2reading});
        if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne $timestring) {
  			  readingsBulkUpdate($hash, $reading, $timestring, 1);
        }
      } else {
        if (!defined($hash->{READINGS}{$reading}{VAL}) || $hash->{READINGS}{$reading}{VAL} ne "-") {
  			  readingsBulkUpdate($hash, $reading, "-", 1);
        }
      }
    }

    # Signal
    if (ref($signalinfo) eq "HASH" && defined($signalinfo->{e2snrdb})) {
      foreach ( "snrdb",
                "snr",
                "ber",
                "acg",
              ) {
        $reading = $_;
        $e2reading = "e2".$_;

        if (defined($signalinfo->{$e2reading})) {
          my @value = split(/ /, $signalinfo->{$e2reading});
          if (defined($value[1]) || $reading eq "ber") {
      			readingsBulkUpdate($hash, $reading, $value[0], 1);
          } else {
      			readingsBulkUpdate($hash, $reading, "0", 1);
          }
        } else {
  			  readingsBulkUpdate($hash, $reading, "0", 1);
        }
      }
    }

  } else {

    # Set ENIGMA2 online-only readings to "-" in case box is in offline or in standby mode
    foreach ( 'servicename',
              'servicenamespace',
              'serviceaspect',
              'serviceprovider',
              'servicereference',
              'videowidth',
              'videoheight',
              'servicevideosize',
              'apid',
              'vpid',
              'pcrpid',
              'pmtpid',
              'txtpid',
              'tsid',
              'onid',
              'sid',
              'mute',
              'volume',
              'channel',
              'currentTitle',
              'input',
              'eventcurrenttime',
              'eventcurrenttime_hr',
              'eventdescription',
              'eventduration',
              'eventstart',
              'eventstart_hr',
              'eventtitle',
              'currentMedia',
            ) {
      if (!defined($hash->{READINGS}{$_}{VAL}) || $hash->{READINGS}{$_}{VAL} ne "-") {
        readingsBulkUpdate($hash, $_, "-", 1);
      }
    }

    # Set ENIGMA2 online-only readings to "-" in case box is in offline or in standby mode
    foreach ( 'acg',
              'ber',
              'snr',
              'snrdb',
            ) {
      if (!defined($hash->{READINGS}{$_}{VAL}) || $hash->{READINGS}{$_}{VAL} ne "0") {
        readingsBulkUpdate($hash, $_, "0", 1);
      }
    }

  }

  readingsEndUpdate($hash, 1);

  Log3 $name, 4, "ENIGMA2 $name: ".$hash->{STATE};
  
  return $hash->{STATE};
}

###################################
sub ENIGMA2_Get($@) {
  my ($hash, @a) = @_;
  my $what;

  return "argument is missing" if(int(@a) < 2);
    
  $what = $a[1];

  if($what =~ /^(power|input|volume|mute|channel|currentMedia|currentTitle|serviceprovider|servicevideosize)$/) {
    ENIGMA2_GetStatus($hash, 1);

    if(defined($hash->{READINGS}{$what})) {
			return $hash->{READINGS}{$what}{VAL};
    } else {
			return "no such reading: $what";
		}

  # streamUrl
  } elsif($what eq "streamUrl") {
    if (defined($a[2]) && $a[2] eq "mobile") {
      return "http://".$hash->{helper}{ADDRESS}.":".$hash->{helper}{PORT}."/web/stream.m3u?ref=".urlEncode($hash->{READINGS}{servicereference}{VAL})."&device=phone";
    } else {
      return "http://".$hash->{helper}{ADDRESS}.":".$hash->{helper}{PORT}."/web/stream.m3u?ref=".urlEncode($hash->{READINGS}{servicereference}{VAL})."&device=etc";
    }
  } else {
		return "Unknown argument $what, choose one of power:noArg input:noArg volume:noArg mute:noArg channel:noArg currentMedia:noArf currentTitle:noArg serviceprovider:noArg servicevideosize:noArg streamUrl:,mobile ";
  }
}

###################################
sub ENIGMA2_Set($@) {
  my ($hash, @a) = @_;
  my $name=$hash->{NAME};
  
  return "No Argument given" if(!defined($a[1]));

  my $usage = "Unknown argument ".$a[1].", choose one of statusRequest:noArg toogle:noArg on:noArg off:noArg reboot:noArg restartGui:noArg shutdown:noArg volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg mute:on,off msg remoteControl:UP,DOWN,LEFT,RIGHT,OK,MENU,EPG,ESC,EXIT,RECORD,RED,GREEN,YELLOW,BLUE,AUDIO channel:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30 channelUp:noArg channelDown:noArg input:tv,radio play:noArg pause:noArg stop:noArg showText ";
  my $cmd='';
  my $result;

  # statusRequest
  if($a[1] eq "statusRequest") {
		# Will be executed anyway on the end of the function			
  # toogle
  } elsif($a[1] eq "toogle") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      if($hash->{READINGS}{state}{VAL} eq "off") {
        $cmd = "newstate=4";
    		readingsBeginUpdate($hash);
        if (!defined($hash->{READINGS}{power}{VAL}) || $hash->{READINGS}{power}{VAL} ne "on") {
    		  readingsBulkUpdate($hash, "power", "on");
        }
        if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{state}{VAL} ne "on") {
    		  readingsBulkUpdate($hash, "state", "on");
        }
    		readingsEndUpdate($hash, 1);
      } else {
        $cmd = "newstate=5";
    		readingsBeginUpdate($hash);
        if (!defined($hash->{READINGS}{power}{VAL}) || $hash->{READINGS}{power}{VAL} ne "off") {
    		  readingsBulkUpdate($hash, "power", "off");
        }
        if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{state}{VAL} ne "off") {
    		  readingsBulkUpdate($hash, "state", "off");
        }
    		readingsEndUpdate($hash, 1);
      }
      $result = ENIGMA2_SendCommand($hash, "powerstate", $cmd);
    } else {
      return "Device needs to be reachable to toogle powerstate.";
    }

  # shutdown
  } elsif($a[1] eq "shutdown") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      $cmd = "newstate=1";
      $result = ENIGMA2_SendCommand($hash, "powerstate", $cmd);
  		readingsBeginUpdate($hash);
      if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{power}{VAL} ne "off") {
  		  readingsBulkUpdate($hash, "power", "off");
      }
      if (!defined($hash->{READINGS}{presence}{VAL}) || $hash->{READINGS}{presence}{VAL} ne "absent") {
        $hash->{helper}{AVAILABLE} = 0;
  		  readingsBulkUpdate($hash, "presence", "absent");
      }
      if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{state}{VAL} ne "absent") {
  		  readingsBulkUpdate($hash, "state", "absent");
      }
  		readingsEndUpdate($hash, 1);
    } else {
      return "Device needs to be ON to set to standby mode.";
    }

  # reboot
  } elsif($a[1] eq "reboot") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      $cmd = "newstate=2";
      $result = ENIGMA2_SendCommand($hash, "powerstate", $cmd);
    } else {
      return "Device needs to be reachable to be rebooted.";
    }

  # restartGui
  } elsif($a[1] eq "restartGui") {
    if($hash->{READINGS}{state}{VAL} eq "on") {
      $cmd = "newstate=3";
      $result = ENIGMA2_SendCommand($hash, "powerstate", $cmd);
    } else {
      return "Device needs to be ON to restart the GUI.";
    }

  # on
  } elsif($a[1] eq "on") {
    if ($hash->{READINGS}{state}{VAL} eq "absent") {
      if (defined($hash->{READINGS}{lanmac}{VAL}) && $hash->{READINGS}{lanmac}{VAL} ne "-") {
        $result = ENIGMA2_wake($hash);
      } else {
        return "Device MAC address unknown. Please turn on the device manually once.";
      }
    } else {
      $cmd = "newstate=4";
      $result = ENIGMA2_SendCommand($hash, "powerstate", $cmd);
  		readingsBeginUpdate($hash);
      if (!defined($hash->{READINGS}{power}{VAL}) || $hash->{READINGS}{power}{VAL} ne "on") {
  		  readingsBulkUpdate($hash, "power", "on");
      }
      if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{state}{VAL} ne "on") {
  		  readingsBulkUpdate($hash, "state", "on");
      }
  		readingsEndUpdate($hash, 1);
      ENIGMA2_GetStatus($hash, 1);
    }

  # off
  } elsif($a[1] eq "off") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      $cmd = "newstate=5";
      $result = ENIGMA2_SendCommand($hash, "powerstate", $cmd);
  		readingsBeginUpdate($hash);
      if (!defined($hash->{READINGS}{power}{VAL}) || $hash->{READINGS}{power}{VAL} ne "off") {
  		  readingsBulkUpdate($hash, "power", "off");
      }
      if (!defined($hash->{READINGS}{state}{VAL}) || $hash->{READINGS}{state}{VAL} ne "off") {
  		  readingsBulkUpdate($hash, "state", "off");
      }
  		readingsEndUpdate($hash, 1);
    } else {
      return "Device needs to be reachable to be set to standby mode.";
    }

  # volume
  } elsif($a[1] eq "volume") {
    return "No argument given" if(!defined($a[2]));

    if($hash->{READINGS}{state}{VAL} eq "on") {
      my $_ = $a[2];
      if ( m/^\d+$/ && $_ >= 0 && $_ <= 100 ) {
        $cmd = "set=set".$a[2];
        if (!defined($hash->{READINGS}{volume}{VAL}) || $hash->{READINGS}{volume}{VAL} ne $a[2]) {
    		  readingsSingleUpdate($hash, "volume", $a[2], 1);
        }
      } else {
        return "Argument does not seem to be a valid integer between 0 and 100";
      }
      $result = ENIGMA2_SendCommand($hash, "vol", $cmd);
    } else {
      return "Device needs to be ON to adjust volume.";
    }

  # volumeUp/volumeDown
  } elsif($a[1] =~ /^(volumeUp|volumeDown)$/) {
    if($hash->{READINGS}{state}{VAL} eq "on") {
      if($a[2] eq "volumeUp") {
        $cmd = "set=up";
      } else {
        $cmd = "set=down";
      }
      $result = ENIGMA2_SendCommand($hash, "vol", $cmd);
    } else {
      return "Device needs to be ON to adjust volume.";
    }

  # mute
  } elsif($a[1] eq "mute") {
    return "No argument given, choose one of on off toogle" if(!defined($a[2]));
    if($hash->{READINGS}{state}{VAL} eq "on") {
      if($a[2] eq "off") {
        if ($hash->{READINGS}{mute}{VAL} ne "off") {
          $cmd = "set=mute";
      		readingsSingleUpdate($hash, "mute", $a[2], 1);
        }
      } elsif($a[2] eq "on") {
        if ($hash->{READINGS}{mute}{VAL} ne "on") {
          $cmd = "set=mute";
      		readingsSingleUpdate($hash, "mute", $a[2], 1);
        }
      } elsif($a[2] eq "toogle") {
        $cmd = "set=mute";
        if ($hash->{READINGS}{mute}{VAL} eq "off") {
    		  readingsSingleUpdate($hash, "mute", "on", 1);
        } else {
    		  readingsSingleUpdate($hash, "mute", "off", 1);
        }
      } else {
        return "Unknown argument ".$a[2];
      }
      $result = ENIGMA2_SendCommand($hash, "vol", $cmd);
    } else {
      return "Device needs to be ON to mute/unmute audio.";
    }

  # msg
  } elsif($a[1] eq "msg") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      return "No 1st argument given, choose one of yesno info message attention " if(!defined($a[2]));
      return "No 2nd argument given, choose one of timeout " if(!defined($a[3]));
      return "No 3nd argument given, choose one of messagetext " if(!defined($a[4]));
      $_ = $a[3];
      return "Argument ".$_." is not a valid integer between 5 and 49680" if ( !m/^\d+$/ || $_ < 5 || $_ > 49680 );
      my $i=4;
      my $text=$a[$i];
      $i++;
      if (defined($a[$i])) {
        my $arr_size=@a;
        while ($i < $arr_size) {
          $text = $text ." ". $a[$i];
          $i++;
        }
      }
      if($a[2] eq "yesno") {
        $cmd = "type=0&timeout=".$a[3]."&text=".urlEncode($text);
      } elsif($a[2] eq "info") {
        $cmd = "type=1&timeout=".$a[3]."&text=".urlEncode($text);
      } elsif($a[2] eq "message") {
        $cmd = "type=2&timeout=".$a[3]."&text=".urlEncode($text);
      } elsif($a[2] eq "attention") {
        $cmd = "type=3&timeout=".$a[3]."&text=".urlEncode($text);
      } else {
        return "Unknown argument ".$a[2].", choose one of yesno info message attention ";
      }
      $result = ENIGMA2_SendCommand($hash, "message", $cmd);
    } else {
      return "Device needs to be reachable to send a message to screen.";
    }

  # remoteControl
  } elsif($a[1] eq "remoteControl") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      if(!defined($a[2])) {
        my $commandKeys = "";
        for (sort keys %{ ENIGMA2_GetRemotecontrolCommand("GetRemotecontrolCommands") } ) {
          $commandKeys = $commandKeys . " " . $_;
        }
        return "No argument given, choose one of".$commandKeys;
      }
      my $request = ENIGMA2_GetRemotecontrolCommand($a[2]);
      if ($request ne "") {
        $cmd = "command=".ENIGMA2_GetRemotecontrolCommand($a[2]);
      } else {
        my $commandKeys = "";
        for (sort keys %{ ENIGMA2_GetRemotecontrolCommand("GetRemotecontrolCommands") } ) {
          $commandKeys = $commandKeys . " " . $_;
        }
        return "Unknown argument ".$a[2].", choose one of".$commandKeys;
      }
      $result = ENIGMA2_SendCommand($hash, "remotecontrol", $cmd);
    } else {
      return "Device needs to be reachable to be controlled remotely.";
    }

  # channel
  } elsif($a[1] eq "channel") {
    return "No argument given, choose one of channelNumber servicereference " if(!defined($a[2]));
    if($hash->{READINGS}{state}{VAL} eq "on") {
      my $_ = $a[2];
      if ( m/^(\d+):(.*):$/ ) {
        $result = ENIGMA2_SendCommand($hash, "zap", "sRef=".$_);
      } elsif ( m/^\d+$/ && $_ > 0 && $_ < 10000 ) {
        for (split(//, $a[2])) {
          $cmd = "command=".ENIGMA2_GetRemotecontrolCommand($_);
          $result = ENIGMA2_SendCommand($hash, "remotecontrol", $cmd);
        }
        $result = ENIGMA2_SendCommand($hash, "remotecontrol", "command=".ENIGMA2_GetRemotecontrolCommand("OK"));
      } else {
        return "Argument ".$_." is not a valid integer between 0 and 9999 or servicereference is invalid";
      }
    } else {
      return "Device needs to be ON to switch to a specific channel.";
    }

  # channelUp/channelDown
  } elsif($a[1] =~ /^(channelUp|channelDown)$/) {
    if($hash->{READINGS}{state}{VAL} eq "on") {
      if($a[1] eq "channelUp") {
        $cmd = "command=".ENIGMA2_GetRemotecontrolCommand("RIGHT");
      } else {
        $cmd = "command=".ENIGMA2_GetRemotecontrolCommand("LEFT");
      }
      $result = ENIGMA2_SendCommand($hash, "remotecontrol", $cmd);
    } else {
      return "Device needs to be ON to switch channel.";
    }

  # input
  } elsif($a[1] eq "input") {
    if($hash->{READINGS}{state}{VAL} eq "on") {
      if($a[2] eq "tv" || $a[2] eq "TV") {
        $cmd = "command=".ENIGMA2_GetRemotecontrolCommand("TV");
    		readingsSingleUpdate($hash, "input", "tv", 1);
      } elsif($a[2] eq "radio" || $a[2] eq "RADIO") {
        $cmd = "command=".ENIGMA2_GetRemotecontrolCommand("RADIO");
    		readingsSingleUpdate($hash, "input", "radio", 1);
      } else {
        return "Argument ".$a[2]." is not a valid, please choose one from tv radio ";
      }
      $result = ENIGMA2_SendCommand($hash, "remotecontrol", $cmd);
    } else {
      return "Device needs to be ON to switch input.";
    }

  # play / pause
  } elsif($a[1] =~ /^(play|pause)$/) {
    if($hash->{READINGS}{state}{VAL} eq "on") {
      $cmd = "command=".ENIGMA2_GetRemotecontrolCommand("PLAYPAUSE");
      $result = ENIGMA2_SendCommand($hash, "remotecontrol", $cmd);
    } else {
      return "Device needs to be ON to play or pause video.";
    }

  # stop
  } elsif($a[1] eq "stop") {
    if($hash->{READINGS}{state}{VAL} eq "on") {
      $cmd = "command=".ENIGMA2_GetRemotecontrolCommand("STOP");
      $result = ENIGMA2_SendCommand($hash, "remotecontrol", $cmd);
    } else {
      return "Device needs to be ON to stop video.";
    }

  # showText
  } elsif($a[1] eq "showText") {
    if($hash->{READINGS}{state}{VAL} ne "absent") {
      return "No argument given, choose one of messagetext " if(!defined($a[2]));
      my $i=2;
      my $text=$a[$i];
      $i++;
      if (defined($a[$i])) {
        my $arr_size=@a;
        while ($i < $arr_size) {
          $text = $text ." ". $a[$i];
          $i++;
        }
      }
      $cmd = "type=1&timeout=8&text=".urlEncode($text);
      $result = ENIGMA2_SendCommand($hash, "message", $cmd);
    } else {
      return "Device needs to be reachable to send a message to screen.";
    }

  # return usage hint
  } else {
    return $usage;
  }

  # Call the GetStatus() Function to retrieve the new values after setting something (with local flag, so the internal timer is not getting interupted)
  if($a[1] ne "shutdown" && $a[1] ne "on" && $a[1] ne "restartGui" && $a[1] ne "reboot") {
    ENIGMA2_GetStatus($hash, 1);
  }

  return undef;
}

###################################
sub ENIGMA2_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name=$hash->{NAME};

  if (int(@a) < 3) {
    my $msg = "Wrong syntax: define <name> ENIGMA2 <ip-or-hostname> [<port>] [<poll-interval>] [<http-user] [<http-password>]";
    Log3 $name, 4, $msg;
    return $msg;
  }

  my $address = $a[2];
  $hash->{helper}{ADDRESS} = $address;

  # use port 80 if not defined
  my $port = $a[3]||80;
  $hash->{helper}{PORT} = $port;

  # use interval of 75sec if not defined
  my $interval=$a[4]||75;
  $hash->{INTERVAL}=$interval;

  # set http user if defined
  my $http_user=$a[5];
  $hash->{helper}{USER}=$http_user if $http_user;

  # set http password if defined
  my $http_passwd=$a[6];
  $hash->{helper}{PASSWORD}=$http_passwd if $http_passwd;

  unless(exists($hash->{helper}{AVAILABLE}) and ($hash->{helper}{AVAILABLE} == 0)) {
  	$hash->{helper}{AVAILABLE} = 1;
  	readingsSingleUpdate($hash, "presence", "present", 1);
  }

  # start the status update timer
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+2, "ENIGMA2_GetStatus", $hash, 0);
 
  return undef;
}

#############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################



###################################
sub ENIGMA2_SendCommand($$;$) {
	my ($hash, $service, $cmd) = @_;
  my $name=$hash->{NAME};
  my $address = $hash->{helper}{ADDRESS};
  my $port = $hash->{helper}{PORT};
  $cmd = "" if(!defined($cmd));

  my $http_user = $hash->{helper}{USER} if(defined($hash->{helper}{USER}));
  my $http_passwd = $hash->{helper}{PASSWORD} if(defined($hash->{helper}{PASSWORD}));
  my $URL;
  my $response;
  my $return;
  
  Log3 $name, 5, "ENIGMA2: execute on $name: $service -> $cmd";

  if (defined($http_user) && defined($http_passwd)) {
    $URL="http://".$http_user.":".$http_passwd."@".$address.":".$port."/web/".$service."?".$cmd."&";
  } elsif (defined($http_user)) {
    $URL="http://".$http_user."@".$address.":".$port."/web/".$service."?".$cmd."&";
  } else {
    $URL="http://".$address.":".$port."/web/".$service."?".$cmd."&";
  }

  $response = CustomGetFileFromURL(0, $URL, 4, $cmd, 0, 5);

  Log3 $name, 5, "ENIGMA2: got response for $name: $service" if(defined($response));

  unless (defined($response)) {
	  if((not exists($hash->{helper}{AVAILABLE})) or (exists($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 1)) {
		  Log3 $name, 3, "ENIGMA2: device $name is unavailable";
		  readingsSingleUpdate($hash, "presence", "absent", 1);
	  }
  } else {
	  if (defined($hash->{helper}{AVAILABLE}) and $hash->{helper}{AVAILABLE} eq 0) {
		  Log3 $name, 3, "ENIGMA2: device $name is available";
		  readingsSingleUpdate($hash, "presence", "present", 1);
    }

    if ($response ne "") {
      my $parser = XML::Simple->new(
        NormaliseSpace => 2,
        KeepRoot       => 0,
        ForceArray     => 0,
        SuppressEmpty  => 1
      );
      $return = $parser->XMLin($response);
    }

    $hash->{helper}{AVAILABLE} = (defined($response) ? 1 : 0);

    if(ref($return) eq "HASH") {
      return $return;
    } else {
      return $response;
    }
  }

  $hash->{helper}{AVAILABLE} = (defined($response) ? 1 : 0);

  return undef;
}

###################################
sub ENIGMA2_Undefine($$) {
  my ($hash, $arg) = @_;
  
  # Stop the internal GetStatus-Loop and exit
  RemoveInternalTimer($hash);
  return undef;
}

###################################
sub ENIGMA2_wake ($) {
  my ($hash) = @_;
  my $name=$hash->{NAME};
  my $mac_addr = $hash->{READINGS}{lanmac}{VAL};
  my $address;
  my $port;

  if ($mac_addr ne "-") {
    if (! defined $address) { $address = '255.255.255.255' }
    if (! defined $port || $port !~ /^\d+$/ ) { $port = 9 }

    my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
    die "Can't create WOL socket" if(!$sock);
  
    my $ip_addr = inet_aton($address);
    my $sock_addr = sockaddr_in($port, $ip_addr);
    $mac_addr =~ s/://g;
    my $packet = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
  
  
    Log3 $name, 4, "ENIGMA2: Waking up $name by sending Wake-On-Lan magic package to ".$mac_addr;
    send($sock, $packet, 0, $sock_addr) or die "send : $!";
    close ($sock);
  } else {
    Log3 $name, 3, "ENIGMA2: MAC address for $name unknown. Please turn on manually once.";
  }

  return 1;
}

###################################
sub ENIGMA2_GetRemotecontrolCommand($) {
  my ($command) = @_;
  my $commands = {
    'RESERVED' => 0,
    'ESC' => 1,
    '1' => 2,
    '2' => 3,
    '3' => 4,
    '4' => 5,
    '5' => 6,
    '6' => 7,
    '7' => 8,
    '8' => 9,
    '9' => 10,
    '0' => 11,
    'MINUS' => 12,
    'EQUAL' => 13,
    'BACKSPACE' => 14,
    'TAB' => 15,
    'Q' => 16,
    'W' => 17,
    'E' => 18,
    'R' => 19,
    'T' => 20,
    'Y' => 21,
    'U' => 22,
    'I' => 23,
    'O' => 24,
    'P' => 25,
    'LEFTBRACE' => 26,
    'RIGHTBRACE' => 27,
    'ENTER' => 28,
    'LEFTCTRL' => 29,
    'A' => 30,
    'S' => 31,
    'D' => 32,
    'F' => 33,
    'G' => 34,
    'H' => 35,
    'J' => 36,
    'K' => 37,
    'L' => 38,
    'SEMICOLON' => 39,
    'APOSTROPHE' => 40,
    'GRAVE' => 41,
    'LEFTSHIFT' => 42,
    'BACKSLASH' => 43,
    'Z' => 44,
    'X' => 45,
    'C' => 46,
    'V' => 47,
    'B' => 48,
    'N' => 49,
    'M' => 50,
    'COMMA' => 51,
    'DOT' => 52,
    'SLASH' => 53,
    'RIGHTSHIFT' => 54,
    'KPASTERISK' => 55,
    'LEFTALT' => 56,
    'SPACE' => 57,
    'CAPSLOCK' => 58,
    'F1' => 59,
    'F2' => 60,
    'F3' => 61,
    'F4' => 62,
    'F5' => 63,
    'F6' => 64,
    'F7' => 65,
    'F8' => 66,
    'F9' => 67,
    'F10' => 68,
    'NUMLOCK' => 69,
    'SCROLLLOCK' => 70,
    'KP7' => 71,
    'KP8' => 72,
    'KP9' => 73,
    'KPMINUS' => 74,
    'KP4' => 75,
    'KP5' => 76,
    'KP6' => 77,
    'KPPLUS' => 78,
    'KP1' => 79,
    'KP2' => 80,
    'KP3' => 81,
    'KP0' => 82,
    'KPDOT' => 83,
    '103RD' => 84,
    'F13' => 85,
    '102ND' => 86,
    'F11' => 87,
    'F12' => 88,
    'F14' => 89,
    'F15' => 90,
    'F16' => 91,
    'F17' => 92,
    'F18' => 93,
    'F19' => 94,
    'F20' => 95,
    'KPENTER' => 96,
    'RIGHTCTRL' => 97,
    'KPSLASH' => 98,
    'SYSRQ' => 99,
    'RIGHTALT' => 100,
    'LINEFEED' => 101,
    'HOME' => 102,
    'UP' => 103,
    'PAGEUP' => 104,
    'LEFT' => 105,
    'RIGHT' => 106,
    'END' => 107,
    'DOWN' => 108,
    'PAGEDOWN' => 109,
    'INSERT' => 110,
    'DELETE' => 111,
    'MACRO' => 112,
    'MUTE' => 113,
    'VOLUMEDOWN' => 114,
    'VOLUMEUP' => 115,
    'POWER' => 116,
    'KPEQUAL' => 117,
    'KPPLUSMINUS' => 118,
    'PAUSE' => 119,
    'F21' => 120,
    'F22' => 121,
    'F23' => 122,
    'F24' => 123,
    'KPCOMMA' => 124,
    'LEFTMETA' => 125,
    'RIGHTMETA' => 126,
    'COMPOSE' => 127,
    'STOP' => 128,
    'AGAIN' => 129,
    'PROPS' => 130,
    'UNDO' => 131,
    'FRONT' => 132,
    'COPY' => 133,
    'OPEN' => 134,
    'PASTE' => 135,
    'FIND' => 136,
    'CUT' => 137,
    'HELP' => 138,
    'MENU' => 139,
    'CALC' => 140,
    'SETUP' => 141,
    'SLEEP' => 142,
    'WAKEUP' => 143,
    'FILE' => 144,
    'SENDFILE' => 145,
    'DELETEFILE' => 146,
    'XFER' => 147,
    'PROG1' => 148,
    'PROG2' => 149,
    'WWW' => 150,
    'MSDOS' => 151,
    'COFFEE' => 152,
    'DIRECTION' => 153,
    'CYCLEWINDOWS' => 154,
    'MAIL' => 155,
    'BOOKMARKS' => 156,
    'COMPUTER' => 157,
    'BACK' => 158,
    'FORWARD' => 159,
    'CLOSECD' => 160,
    'EJECTCD' => 161,
    'EJECTCLOSECD' => 162,
    'NEXTSONG' => 163,
    'PLAYPAUSE' => 164,
    'PREVIOUSSONG' => 165,
    'STOPCD' => 166,
    'RECORD' => 167,
    'REWIND' => 168,
    'PHONE' => 169,
    'ISO' => 170,
    'CONFIG' => 171,
    'HOMEPAGE' => 172,
    'REFRESH' => 173,
    'EXIT' => 174,
    'MOVE' => 175,
    'EDIT' => 176,
    'SCROLLUP' => 177,
    'SCROLLDOWN' => 178,
    'KPLEFTPAREN' => 179,
    'KPRIGHTPAREN' => 180,
    'INTL1' => 181,
    'INTL2' => 182,
    'INTL3' => 183,
    'INTL4' => 184,
    'INTL5' => 185,
    'INTL6' => 186,
    'INTL7' => 187,
    'INTL8' => 188,
    'INTL9' => 189,
    'LANG1' => 190,
    'LANG2' => 191,
    'LANG3' => 192,
    'LANG4' => 193,
    'LANG5' => 194,
    'LANG6' => 195,
    'LANG7' => 196,
    'LANG8' => 197,
    'LANG9' => 198,
    'PLAYCD' => 200,
    'PAUSECD' => 201,
    'PROG3' => 202,
    'PROG4' => 203,
    'SUSPEND' => 205,
    'CLOSE' => 206,
    'PLAY' => 207,
    'FASTFORWARD' => 208,
    'BASSBOOST' => 209,
    'PRINT' => 210,
    'HP' => 211,
    'CAMERA' => 212,
    'SOUND' => 213,
    'QUESTION' => 214,
    'EMAIL' => 215,
    'CHAT' => 216,
    'SEARCH' => 217,
    'CONNECT' => 218,
    'FINANCE' => 219,
    'SPORT' => 220,
    'SHOP' => 221,
    'ALTERASE' => 222,
    'CANCEL' => 223,
    'BRIGHTNESSDOWN' => 224,
    'BRIGHTNESSUP' => 225,
    'MEDIA' => 226,
    'UNKNOWN' => 240,
    'OK' => 352,
    'SELECT' => 353,
    'GOTO' => 354,
    'CLEAR' => 355,
    'POWER2' => 356,
    'OPTION' => 357,
    'INFO' => 358,
    'TIME' => 359,
    'VENDOR' => 360,
    'ARCHIVE' => 361,
    'PROGRAM' => 362,
    'CHANNEL' => 363,
    'FAVORITES' => 364,
    'EPG' => 365,
    'PVR' => 366,
    'MHP' => 367,
    'LANGUAGE' => 368,
    'TITLE' => 369,
    'SUBTITLE' => 370,
    'ANGLE' => 371,
    'ZOOM' => 372,
    'MODE' => 373,
    'KEYBOARD' => 374,
    'SCREEN' => 375,
    'PC' => 376,
    'TV' => 377,
    'TV2' => 378,
    'VCR' => 379,
    'VCR2' => 380,
    'SAT' => 381,
    'SAT2' => 382,
    'CD' => 383,
    'TAPE' => 384,
    'RADIO' => 385,
    'TUNER' => 386,
    'PLAYER' => 387,
    'TEXT' => 388,
    'DVD' => 389,
    'AUX' => 390,
    'MP3' => 391,
    'AUDIO' => 392,
    'VIDEO' => 393,
    'DIRECTORY' => 394,
    'LIST' => 395,
    'MEMO' => 396,
    'CALENDAR' => 397,
    'RED' => 398,
    'GREEN' => 399,
    'YELLOW' => 400,
    'BLUE' => 401,
    'CHANNELUP' => 402,
    'CHANNELDOWN' => 403,
    'FIRST' => 404,
    'LAST' => 405,
    'AB' => 406,
    'NEXT' => 407,
    'RESTART' => 408,
    'SLOW' => 409,
    'SHUFFLE' => 410,
    'BREAK' => 411,
    'PREVIOUS' => 412,
    'DIGITS' => 413,
    'TEEN' => 414,
    'TWEN' => 415,
    'DEL_EOL' => 448,
    'DEL_EOS' => 449,
    'INS_LINE' => 450,
    'DEL_LINE' => 451,
    'ASCII' => 510,
    'MAX' => 511,
    'BTN_0' => 256,
    'BTN_1' => 257
  };

  if (defined($commands->{$command})) {
    return $commands->{$command};
  } elsif ($command eq "GetRemotecontrolCommands") {
    return $commands;
  } else {
    return "";
  }
}

1;

=pod
=begin html

<a name="ENIGMA2"></a>
<h3>ENIGMA2</h3>
<ul>

  <a name="ENIGMA2define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ENIGMA2 &lt;ip-address-or-hostname&gt; [&lt;port&gt;] [&lt;poll-interval&gt;]
   [&lt;http-user&gt;] [&lt;http-password&gt;]</code>
    <br><br>

    This module controls ENIGMA2 based devices like Dreambox or VUplus via network connection.<br><br>
    Defining an ENIGMA2 device will schedule an internal task (interval can be set
    with optional parameter &lt;poll-interval&gt; in seconds, if not set, the value is 75
    seconds), which periodically reads the status of the device and triggers notify/filelog commands.<br><br>

    Example:<br>
    <ul><code>
       define SATReceiver ENIGMA2 192.168.0.10
       <br><br>
       define SATReceiver ENIGMA2 192.168.0.10 8080 &nbsp;&nbsp;&nbsp; # With custom port
       <br><br>
       define SATReceiver ENIGMA2 192.168.0.10 80 60 &nbsp;&nbsp;&nbsp; # With custom interval of 60 seconds
       <br><br>
       define SATReceiver ENIGMA2 192.168.0.10 80 60 root secret &nbsp;&nbsp;&nbsp; # With HTTP user credentials
    </code></ul>
   
  </ul>
  
  <a name="ENIGMA2set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    Currently, the following commands are defined.<br>
    <ul>
    <li><b>on</b> &nbsp;&nbsp;-&nbsp;&nbsp; powers on the device and send a WoL magic package if needed</li>
    <li><b>off</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in standby mode</li>
    <li><b>toogle</b> &nbsp;&nbsp;-&nbsp;&nbsp; switch between on and off</li>
    <li><b>shutdown</b> &nbsp;&nbsp;-&nbsp;&nbsp; turns the device in deepstandby mode</li>
    <li><b>reboot</b> &nbsp;&nbsp;-&nbsp;&nbsp;reboots the device</li>
    <li><b>restartGui</b> &nbsp;&nbsp;-&nbsp;&nbsp;restarts the GUI / ENIGMA2 process</li>
    <li><b>channel</b> 0...999,sRef &nbsp;&nbsp;-&nbsp;&nbsp; zap to specific channel or service reference</li>
    <li><b>channelUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to next channel</li>
    <li><b>channelDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; zap to previous channel</li>
    <li><b>volume</b> 0...100 &nbsp;&nbsp;-&nbsp;&nbsp; set the volume level in percentage</li>
    <li><b>volumeUp</b> &nbsp;&nbsp;-&nbsp;&nbsp; increases the volume level</li>
    <li><b>volumeDown</b> &nbsp;&nbsp;-&nbsp;&nbsp; decreases the volume level</li>
    <li><b>mute</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; controls volume mute</li>
    <li><b>play</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; starts/resumes playback</li>
    <li><b>pause</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; pauses current playback or enables timeshift</li>
    <li><b>stop</b> on,off &nbsp;&nbsp;-&nbsp;&nbsp; stops current playback</li>
    <li><b>input</b> 1...9999,servicereference &nbsp;&nbsp;-&nbsp;&nbsp; zap to a specific channel; can be a real channel number from bouquet or service reference ID</li>
    <li><b>statusRequest</b> &nbsp;&nbsp;-&nbsp;&nbsp; requests the current status of the device</li>
    <li><b>remoteControl</b> up,down,... &nbsp;&nbsp;-&nbsp;&nbsp; sends remote control commands; see remoteControl help</li>
    <li><b>showText</b> text &nbsp;&nbsp;-&nbsp;&nbsp; sends info message to screen to be displayed for 8 seconds</li>
    <li><b>msg</b> yesno,info... &nbsp;&nbsp;-&nbsp;&nbsp; allows more complex messages as showText, see commands as listed below</li>
    </ul>
  </ul><br><br>

<u>Messaging</u><br><br>
<ul>
    showText has predefined settings. If you would like to send more individual messages
    to your TV screen, the function msg can be used.
    For this application the following commands are available:<br><br>

    <u>Type Selection:</u><br>
    <ul><code>
    msg yesno<br>
    msg info<br>
    msg message<br>
    msg attention<br>
    </code></ul><br><br>

    The following parameter are essentially needed after type specification:
    <ul><code>
    msg &lt;TYPE&gt; &lt;TIMEOUT&gt; &lt;YOUR MESSAGETEXT&gt;<br>
    </code></ul><br><br>
</ul>

  <a name="ENIGMA2get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;what&gt;</code>
    <br><br>
    Currently, the following commands are defined:<br><br>

    <ul><code>power<br>
    input<br>
    volume<br>
    mute<br>
    channel<br>
    currentMedia<br>
    currentTitle<br>
    serviceprovider<br>
    servicevideosize<br>
    streamUrl<br>
  </code></ul>
</ul>

  <br>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>acg</b> - Shows Automatic Gain Control value in percent; reflects overall signal quality strength</li>
  <li><b>apid</b> - Shows the audio process ID for current channel</li>
  <li><b>ber</b> - Shows Bit Error Rate for current channel</li>
  <li><b>channel</b> - Shows the service name of current channel or media file name; part of FHEM-4-AV-Devices compatibility</li>
  <li><b>currentTitle</b> - Shows the title of the running event; part of FHEM-4-AV-Devices compatibility</li>
  <li><b>currentMedia</b> - The service reference ID of current channel; part of FHEM-4-AV-Devices compatibility</li>
  <li><b>enigmaversion</b> - Shows the installed version of ENIGMA2</li>
  <li><b>eventdescription</b> - Shows the description of running event</li>
  <li><b>evenduration</b> - Shows the total duration time of running event in seconds</li>
  <li><b>eventid</b> - Shows the ID of running event</li>
  <li><b>eventstart</b> - Shows the starting time of running event as UNIX timestamp</li>
  <li><b>eventstart_hr</b> - Shows the starting time of running event in human readable format</li>
  <li><b>eventtitle</b> - Shows the title of the running event</li>
  <li><b>fpversion</b> - Shows the firmware version for the front processor</li>
  <li><b>hddX_capacity</b> - Shows the total capacity of the installed hard drive in GB</li>
  <li><b>hddX_free</b> - Shows the free capacity of the installed hard drive in GB</li>
  <li><b>hddX_model</b> - Shows hardware details for the installed hard drive</li>
  <li><b>imageversion</b> - Shows the version for the installed software image</li>
  <li><b>input</b> - Shows currently used input; part of FHEM-4-AV-Devices compatibility</li>
  <li><b>lanmac</b> - Shows the device MAC address</li>
  <li><b>model</b> - Shows details about the device hardware</li>
  <li><b>mute</b> - Reports the mute status of the device (can be "on" or "off")</li>
  <li><b>onid</b> - The ON ID</li>
  <li><b>pcrpid</b> - The PCR process ID</li>
  <li><b>pmtpid</b> - The PMT process ID</li>
  <li><b>power</b> - Reports the power status of the device (can be "on" or "off")</li>
  <li><b>presence</b> - Reports the presence status of the receiver (can be "absent" or "present"). In case of an absent device, control is basically limited to turn it on again. This will only work if the device supports Wake-On-LAN packages, otherwise command "on" will have no effect.</li>
  <li><b>serviceaspect</b> - Aspect ratio for current channel</li>
  <li><b>servicename</b> - Name for current channel</li>
  <li><b>servicenamespace</b> - Namespace for current channel</li>
  <li><b>serviceprovider</b> - Service provider of current channel</li>
  <li><b>servicereference</b> - The service reference ID of current channel</li>
  <li><b>servicevideosize</b> - Video resolution for current channel</li>
  <li><b>sid</b> - The S-ID</li>
  <li><b>snr</b> - Shows Signal to Noise for current channel in percent</li>
  <li><b>snrdb</b> - Shows Signal to Noise in dB</li>
  <li><b>state</b> - Reports current power state and an absence of the device (can be "on", "off" or "absent")</li>
  <li><b>tsid</b> - The TS ID</li>
  <li><b>tuner_X</b> - Details about the used tuner hardware</li>
  <li><b>txtpid</b> - The TXT process ID</li>
  <li><b>videoheight</b> - Height of the video resolution for current channel</li>
  <li><b>videowidth</b> - Width of the video resolution for current channel</li>
  <li><b>volume</b> - Reports current volume level of the receiver in percentage values (between 0 and 100 %)</li>
  <li><b>vpid</b> - The Video process ID</li>
  <li><b>webifversion</b> - Type and version of the used web interface</li>
  </ul>
</ul>

=end html
=cut

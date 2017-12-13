#
#
# 94_PWM.pm
# written by Andreas Goebel 2012-07-25
# e-mail: ag at goebel-it dot de
#
# 21.09.15 GA update, use Log3
# 07.10.15 GA initial version published
# 13.10.15 GA add event-on-change-reading
# 13.10.15 GA add several readings
# 15.10.15 GA add reading for avg pulses
# 19.10.15 GA add overall heating switch
# 22.10.15 GA add new definition for overall heating switch. Decision now based on threshold for pulseMax
# 30.11.15 GA add new definition for overall heating switch. based on pulseMax or roomsOn
# 30.11.15 GA add new followUpTime can now delay switching of OverallHeatingSwitch from "on" to "off"
# 26.01.16 GA fix don't call AssignIoPort
# 26.01.16 GA fix IODev from PWMR object is now a reference to PWM object
# 29.06.16 GA add attribute valveProtectIdlePeriod
# 16.08.16 GA add event-min-interval
# 23.09.16 GA fix set default for maxPulse to 1 (from 0.85)
# 28.09.16 GA add "get timers" to collect a maximum of all timers from the rooms attached
# 11.10.16 GA add new delayTimeOn can now suspend switching of OverallHeadtingSwitch from "off" to "on"
# 16.11.16 GA add new attribute overallHeatingSwitchRef for threshold based configuration
# 17.11.16 GA add internals for configuration parameters: p_interval, p_cycletime, p_minOnOffTime, 
#                 p_maxPulse, p_roomsMinOnOffThreshold and p_overallHeatingSwitch
# 01.08.17 GA add attribute disable to stop calculations of PWM
# 01.08.17 GA fix OverallHeatingSwitch (without threshold) now independent from ValveProtection
# 17.08.17 GA add attribute overallHeatingSwitchThresholdTemp define a threshold temperature to prevent switch to "on"
# 30.11.17 GA add helper for last pulses of rooms
# 30.11.17 GA fix clear roomsToStayOn and roomsToStayOnList if not used
# 05.12.17 GA add extend helper for last pulses by $roomsWaitOffset{$wkey}
# 13.12.17 GA fix consider $roomsWaitOffset{$wkey} in oldpulse set for each room

##############################################
# $Id$


# module for PWM (Pulse Width Modulation) calculation
#  this module uses PWMR (R like room) to
#  - get information (ReadRoom)
#  - set actors (SetRoom)
#
# standard heating devices support 0 to 100% heating they can be driven by the PID module
# heating devices only supporing "on" of "off" can be driven by PWM
# in PWM 50% is realised by defining a timeframe (cycletime) 
# and switch the defive "on" for 50% of this time
# basis for calculation of this pulse is a factor multiplied with the difference 
# between desired-temp and act-temp
#
# default for cycletime is 15 minutes (900 sec)
# since the devices act very slow 
# there is a parameter minonofftime to prevent "senseless" switches
# PWM recalculates the needed pulse every 60 seconds and 
# then decides if the devices will be switched 
# "on->off", "off->on" or stays in the current state
#



package main;

use strict;
use warnings;

sub PWM_Get($@);
sub PWM_Set($@);
sub PWM_Define($$);
sub PWM_Calculate($);
sub PWM_Undef($$);
sub PWM_CalcRoom(@);

my %roomsWaitOffset = ();

###################################
sub
PWM_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "PWM_Get";
  $hash->{SetFn}     = "PWM_Set";
  $hash->{DefFn}     = "PWM_Define";
  $hash->{UndefFn}   = "PWM_Undef";
  $hash->{AttrFn}    = "PWM_Attr";

  $hash->{AttrList}  = "disable:1,0 event-on-change-reading event-min-interval valveProtectIdlePeriod overallHeatingSwitchRef:pulseMax,pulseSum,pulseAvg,pulseAvg2,pulseAvg3,avgPulseRoomsOn".
		       " overallHeatingSwitchThresholdTemp";
  #$hash->{GetList}   = "status timers";

}

###################################
sub
PWM_Calculate($)
{
  my ($hash) = @_;

  my $name = $hash->{NAME};
  my %RoomsToSwitchOn       = ();
  my %RoomsToSwitchOff      = ();
  my %RoomsToStayOn         = ();
  my %RoomsToStayOff        = ();
  my %RoomsValveProtect     = ();
  my %RoomsPulses           = ();
  my $roomsActive           = 0;
  my $newpulseMax           = 0;
  my $newpulseSum           = 0;
  my $newpulseAvg           = 0;
  my $newpulseAvg2          = 0;
  my $newpulseAvg3          = 0;
  my $wkey                  = "";

  if($hash->{INTERVAL} > 0) {
    InternalTimer(gettimeofday() + $hash->{INTERVAL}, "PWM_Calculate", $hash, 0);
  }

  if (defined($attr{$name}{disable}) and $attr{$name}{disable} == 1) {
    Log3 ($hash, 3, "PWM_Calculate $name");
    $hash->{STATE} = "disabled";
    readingsSingleUpdate ($hash,  "lastrun", "disabled", 0);
    return;
  }

  Log3 ($hash, 3, "PWM_Calculate $name");

  $hash->{helper}{pulses} = ();

  readingsBeginUpdate ($hash);

  #$hash->{STATE} = "lastrun: ".TimeNow();
  #$hash->{STATE} = "calculating";
  readingsBulkUpdate ($hash,  "lastrun", "calculating");
  $hash->{STATE} = "lastrun: ".$hash->{READINGS}{lastrun}{TIME};

  # loop over all devices
  #  fetch all PWMR devices
  #  which are not disabled
  #  and are linked to me (via IODev)

  foreach my $d (sort keys %defs) {
    if ( (defined ($defs{$d}{TYPE})) && $defs{$d}{TYPE} eq "PWMR" ) {      # all PWMR objects
       if (!defined ($attr{$d}{disable}) or $attr{$d}{disable} == 0) {     # not disabled
         if ($hash->{NAME} eq $defs{$d}{IODev}->{NAME}) {                          # referencing to this fb

          Log3 ($hash, 4, "PWM_Calculate calc $name, room $d");

          ########################
          # calculate room
          # $newstate is "" if state is unchanged
          # $newstate is "on" or "off" if state changes
          # $newstate may be "on_vp" or "off_vp" if valve protection is active
	  my ($newstate, $newpulse, $cycletime, $oldstate) = PWM_CalcRoom($hash, $defs{$d});

          my $onoff = $newpulse * $cycletime;
          if ($newstate =~ "off.*") {
            $onoff = (1 - $newpulse) * $cycletime
          }

          if ($newstate eq "on_vp") {
	    $RoomsValveProtect{$d} = "on";
          } elsif ($newstate eq "off_vp") {
	    $RoomsValveProtect{$d} = "off";
          }
	  
          $wkey = $name."_".$d;
          if (defined ($roomsWaitOffset{$wkey})) {
            $hash->{helper}{pulses}{$d} = $newpulse." / ".$roomsWaitOffset{$wkey}; 
            $newpulse += $roomsWaitOffset{$wkey};
            
          } else {
            $roomsWaitOffset{$wkey} = 0;
            $hash->{helper}{pulses}{$d} = $newpulse." / ".$roomsWaitOffset{$wkey}; 
          }

	  $defs{$d}->{READINGS}{oldpulse}{TIME} = TimeNow();
	  $defs{$d}->{READINGS}{oldpulse}{VAL}  = $newpulse;

          $roomsActive++;
          $RoomsPulses{$d} = $newpulse;
          $newpulseSum += $newpulse;
          $newpulseMax = max($newpulseMax, $newpulse);

          # $newstate ne "" -> state changed "on" -> "off" or "off" -> "on"
          if ((int($hash->{MINONOFFTIME}) > 0) &&
              (($newstate eq "on") or ($newstate eq "off")) && 
              ($onoff < int($hash->{MINONOFFTIME})) 
             ) {

            #######################
            # actor devices take 3 minutes for an open/close cycle
            #  this is handled by MINONOFFTIME

            Log3 ($hash, 3, "PWM_Calculate $d: F0 stay unchanged $oldstate: ".
              "($onoff < $hash->{MINONOFFTIME} sec)");
                
            if ($oldstate eq "off") {
              $RoomsToStayOff{$d} = $newpulse;
            } else {
              $RoomsToStayOn{$d}  = $newpulse;
            }
 
          } else {
          
            # state changed and it is worth to move the device

            if ($newstate eq "on") {
              $RoomsToSwitchOn{$d}   = $newpulse;

            } elsif ($newstate eq "off") {
              $RoomsToSwitchOff{$d}  = $newpulse;

            } elsif ($newstate eq "") {

              if ($oldstate eq "on") {
                $RoomsToStayOn{$d}   = $newpulse;
              } else {
                $RoomsToStayOff{$d}  = $newpulse;
              }
            } 

          }
        }
      }
    }
  }


  # synchronize the heating on the "off" edge of the pulse
  # try to minimize the situation where all rooms are "on" at the same time
  #
  # algorithm:
  # -> if more than 2 rooms are switched off at the same time,
  # -> simply keep some on (but this will last only for one calculation cycle)
  #
  # assumption: 100% "on" time is not allowed (max newpulse = 85%)
  # -> in the morning all rooms will be switched on at the same time
  # -> and then off at the same time 


  # normally we switch off only one room at the same time
  # normally we switch on  only one room at the same time
  my $switchOn  = $hash->{MaxSwitchOnPerCycle};    # default 1
  my $switchOff = $hash->{MaxSwitchOffPerCycle};   # default 1

  # rooms may stay on due to logic below ...
  #
  # switch off only (one) the room with lowest need for heating

  # sort rooms with ascending "newpulse"
  foreach my $room (sort { $RoomsToSwitchOff{$a} <=> $RoomsToSwitchOff{$b} } keys %RoomsToSwitchOff) {

    # only the first room in the list will be switched off
    # all others will stay on
    # first room has the lowest need for heating ... it will be switched off

    $switchOff--;

    if ($switchOff >= 0) {
      Log3 ($hash, 3, "PWM_Calculate $room: F99 switch off ".
        "(pulse=$RoomsToSwitchOff{$room})");
      next;
    } 

    Log3 ($hash, 3, "PWM_Calculate $room: F99 keep room on ".
      "(pulse=$RoomsToSwitchOff{$room})");

    $RoomsToStayOn{$room} = 1;
    if (defined($RoomsToSwitchOff{$room})) {
      delete ($RoomsToSwitchOff{$room});
    }
  }

  # try to minimize the situation where all rooms are "on" at the same time
  # switch "on" only one room at the same time
  
  # sort rooms with decending "newpulse"
  foreach my $room (sort { $RoomsToSwitchOn{$b} <=> $RoomsToSwitchOn{$a} } keys %RoomsToSwitchOn) {

    # only the first room in the list will be switched on
    # all others will stay off
    # first room has the highest need for heating ... it will be switched on

    $switchOn--;

    if ($switchOn >= 0) {
      Log3 ($hash, 3, "PWM_Calculate $room: F98 switch on ".
        "(pulse=$RoomsToSwitchOn{$room})");
      next;
    }

    Log3 ($hash, 3, "PWM_Calculate $room: F98 keep room off ".
      "(pulse=$RoomsToSwitchOn{$room})");

    my $wkey = $name."_".$room;
    $roomsWaitOffset{$wkey} += 0.0001;

    $RoomsToStayOff{$room} = 1;
    if (defined($RoomsToSwitchOn{$room})) {
      delete ($RoomsToSwitchOn{$room});
    }

  }


  # in addition to the above max. of 85% of the active rooms may be on at the same time
  # 11 * 0.8 = 8.8 ... 8 is ok ... 9, 10, 11 is not (laraEG!)

  my $roomsOn = (scalar keys %RoomsToStayOn) - (scalar keys %RoomsToSwitchOff);

  # treat less than 8 active rooms as 8 (more can get active)
  # 16.01.2015
  #my $maxRoomsOn = $roomsActive * 0.7;

  # 23.09.2015
  #my $maxRoomsOn = $roomsActive * 0.6;  # 11 rooms -> max 6 active
  #$maxRoomsOn = (8 * 0.7)  if ($roomsActive < 8);

  my $maxRoomsOn = $roomsActive - $hash->{NoRoomsToStayOff};

  #
  # looks complicated but this will work if more than one room would be switched on
  #
  # prevent rooms to be switched on if maxRoomsOn is reached
  #
  while (
         (($roomsOn + (scalar keys %RoomsToSwitchOn)) > $maxRoomsOn) && 
         ((scalar keys %RoomsToSwitchOn) > 0)
        ) {

    # sort rooms with ascending "newpulse"
    foreach my $room (sort { $RoomsToSwitchOn{$a} <=> $RoomsToSwitchOn{$b} } keys %RoomsToSwitchOn) {

      Log3 ($hash, 3, "PWM_Calculate $room: F97 keep room off ".
        "(pulse=$RoomsToSwitchOn{$room}) (max=$maxRoomsOn)");


      my $wkey = $name."_".$room;
      $roomsWaitOffset{$wkey} += 0.001;
 
      $RoomsToStayOff{$room} = 1;
      if (defined($RoomsToSwitchOn{$room})) {
        delete ($RoomsToSwitchOn{$room});
      }

      last; # continue in while loop 
    }
  }

  # in addition to the above try to prevent that too many rooms are off 
  # use $roomsActive and $newpulseSum to differentiate if heating is required
  # 11 * 0.27 = 2.97 ... 3 rooms is ok ... 0,1 or 2 is not

  # 23.09.2015
  #my $minRoomsOn = $roomsActive * 0.29;

  # if overall required heating is below 0.42 ... possibly drive Vaillant into "Sperrzeit"
  # 15.01.2015: adjust this from 0.42 to 0.25 (=25% Pulse needed)
  # 23.09.2015
  #if ($roomsActive == 0 or $newpulseSum/$roomsActive < 0.42) {
  #  $minRoomsOn = 0;
  #} 

  my $minRoomsOn = $hash->{NoRoomsToStayOn};
  my $minRoomsOnList = "";

  if ($minRoomsOn > 0) {

    my $roomsCounted  = 0;
    my $pulseSum      = 0;

    foreach my $room (sort { $RoomsPulses{$b} <=> $RoomsPulses{$a} } keys %RoomsPulses) {

      last if ($roomsCounted == $minRoomsOn);
      Log3 ($hash, 3, "PWM_Calculate: loop $roomsCounted $room $RoomsPulses{$room}");

      $minRoomsOnList .= "$room,";
      $pulseSum += $RoomsPulses{$room};
      $roomsCounted++;
    }
    $minRoomsOnList =~ s/,$//;

    if ($roomsActive == 0 or $hash->{NoRoomsToStayOnThreshold} == 0 or $pulseSum/$roomsCounted < $hash->{NoRoomsToStayOnThreshold}) {
      $minRoomsOn = 0;
      $minRoomsOnList = "";
    } 
 
    #Log3 ($hash, 3, "PWM_Calculate: newpulseSum $newpulseSum avg ".$newpulseSum/$roomsActive." minRoomsOn(".$minRoomsOn.")") if ($roomsActive > 0);
    Log3 ($hash, 3, "PWM_Calculate: pulseSum $pulseSum avg ".$pulseSum/$roomsCounted." minRoomsOn(".$minRoomsOn.")") if ($roomsActive > 0);

  }


  #
  # looks complicated but this will work if more than one room would stay on
  #
  while (
         (((scalar keys %RoomsToStayOn) + (scalar keys %RoomsToSwitchOn)) < $minRoomsOn) && 
         ((scalar keys %RoomsToSwitchOff) > 0)
        ) {

    # sort rooms with decending "newpulse"
    foreach my $room (sort { $RoomsToSwitchOff{$b} <=> $RoomsToSwitchOff{$a} } keys %RoomsToSwitchOff) {

      my $ron = 1 + (scalar keys %RoomsToStayOn) + (scalar keys %RoomsToSwitchOn);

      Log3 ($hash, 3, "PWM_Calculate $room: F96 keep room on ".
        "(pulse=$RoomsToSwitchOff{$room}) (min=$minRoomsOn) (roomsOn=$ron)");

      my $wkey = $name."_".$room;
      $roomsWaitOffset{$wkey} -= 0.001;
 
      $RoomsToStayOn{$room} = 1;
      if (defined($RoomsToSwitchOff{$room})) {
        delete ($RoomsToSwitchOff{$room});
      }

      last; # continue in while loop
    }
  }

  #
  # now process the calculated actions
  #

  my $cntRoomsOn = 0;
  my $cntRoomsOnVP = 0;
  my $cntRoomsOff = 0;
  my $pulseRoomsOn = 0;
  my $pulseRoomsOff = 0;

  foreach my $roomStay (sort keys %RoomsToStayOff) {

	PWMR_SetRoom ($defs{$roomStay}, ""); 

        $cntRoomsOff++;
        $pulseRoomsOff += $RoomsPulses{$roomStay};

  }

  foreach my $roomStay (sort keys %RoomsToStayOn) {

	PWMR_SetRoom ($defs{$roomStay}, ""); 

        $cntRoomsOn++;
        $pulseRoomsOn += $RoomsPulses{$roomStay};

  }
  
  foreach my $roomOff (sort keys %RoomsToSwitchOff) {

	PWMR_SetRoom ($defs{$roomOff}, "off"); 

        $cntRoomsOff++;
        $pulseRoomsOff += $RoomsPulses{$roomOff};
  } 

  foreach my $roomOn (sort keys %RoomsToSwitchOn) {

        my $wkey = $name."-".$roomOn;
        $roomsWaitOffset{$wkey} = 0;
	PWMR_SetRoom ($defs{$roomOn}, "on"); 

        $cntRoomsOn++;
        $pulseRoomsOn += $RoomsPulses{$roomOn};

  }

  foreach my $roomVP (sort keys %RoomsValveProtect) {

        my $wkey = $name."-".$roomVP;
        $roomsWaitOffset{$wkey} = 0;

        if ( $RoomsValveProtect{$roomVP} eq "on") {

	  PWMR_SetRoom ($defs{$roomVP}, "on"); 
          $cntRoomsOn++;
          $cntRoomsOnVP++;
          $pulseRoomsOn += $RoomsPulses{$roomVP};

	} else {

	  PWMR_SetRoom ($defs{$roomVP}, "off"); 
          $cntRoomsOff++;
          $pulseRoomsOff += $RoomsPulses{$roomVP};
        }

  }

  my $cntAvg = 0;

  # sort rooms with decending "newpulse"
  foreach my $room (sort { $RoomsPulses{$b} <=> $RoomsPulses{$a} } keys %RoomsPulses) {

    $newpulseAvg  += $RoomsPulses{$room};
    $newpulseAvg2 += $RoomsPulses{$room} if ($cntAvg < 2);
    $newpulseAvg3 += $RoomsPulses{$room} if ($cntAvg < 3);

    $cntAvg++;
  }

  $newpulseAvg  = sprintf ("%.02f", $newpulseAvg  / $cntAvg)             if ($cntAvg > 0);
  $newpulseAvg2 = sprintf ("%.02f", $newpulseAvg2 / minNum (2, $cntAvg)) if ($cntAvg > 0);
  $newpulseAvg3 = sprintf ("%.02f", $newpulseAvg3 / minNum (3, $cntAvg)) if ($cntAvg > 0);

  
  readingsBulkUpdate ($hash,  "roomsActive",   $roomsActive);
  readingsBulkUpdate ($hash,  "roomsOn",       $cntRoomsOn);
  readingsBulkUpdate ($hash,  "roomsOff",      $cntRoomsOff);
  readingsBulkUpdate ($hash,  "avgPulseRoomsOn",  ($cntRoomsOn > 0 ? sprintf ("%.2f", $pulseRoomsOn / $cntRoomsOn) : 0));
  readingsBulkUpdate ($hash,  "avgPulseRoomsOff", ($cntRoomsOff > 0 ? sprintf ("%.2f", $pulseRoomsOff /$cntRoomsOff) : 0));
  readingsBulkUpdate ($hash,  "pulseMax",      $newpulseMax);
  readingsBulkUpdate ($hash,  "pulseSum",      $newpulseSum);
  readingsBulkUpdate ($hash,  "pulseAvg",      $newpulseAvg);
  readingsBulkUpdate ($hash,  "pulseAvg2",     $newpulseAvg2);
  readingsBulkUpdate ($hash,  "pulseAvg3",     $newpulseAvg3);

  if ( $hash->{NoRoomsToStayOn} > 0) {
    readingsBulkUpdate ($hash,  "roomsToStayOn", $minRoomsOn);
    readingsBulkUpdate ($hash,  "roomsToStayOnList", $minRoomsOnList);
  } else {
    readingsBulkUpdate ($hash,  "roomsToStayOn", 0);
    readingsBulkUpdate ($hash,  "roomsToStayOnList", "");
  }
	

  if ( defined ($hash->{OverallHeatingSwitch}) ) {
    if ( $hash->{OverallHeatingSwitch} ne "") {

      my $newstateOHS = "on";
      if ( $hash->{OverallHeatingSwitch_threshold} > 0) {

        # threshold based
	my $refValue = $newpulseMax;

	if (defined($attr{$name}{overallHeatingSwitchRef})) {

          my $ref = $attr{$name}{overallHeatingSwitchRef};

          $refValue = $newpulseMax   if ($ref eq "pulseMax");
          $refValue = $newpulseSum   if ($ref eq "pulseSum");
          $refValue = $newpulseAvg   if ($ref eq "pulseAvg");
          $refValue = $newpulseAvg2  if ($ref eq "pulseAvg2");
          $refValue = $newpulseAvg3  if ($ref eq "pulseAvg3");
        }

        $newstateOHS = ($refValue > $hash->{OverallHeatingSwitch_threshold}) ? "on" : "off";

      } else {

        # room based
        $newstateOHS = (($cntRoomsOn - $cntRoomsOnVP) > 0) ? "on" : "off";

      }

      # OverallHeatingSwitchThresholdTemp may prevent switch ot on and sets OverallHeatingSwitch to e-off
      my $newstateOHS_eoff = 0;
      if ($newstateOHS eq "on" and defined ($hash->{OverallHeatingSwitchTT_tsensor})) {

        my $sensor  = $hash->{OverallHeatingSwitchTT_tsensor};
        my $reading = $hash->{OverallHeatingSwitchTT_reading};

        if (defined ($defs{$sensor}) and defined ($defs{$sensor}->{READINGS}{$reading})) {

          my $t_regexp = $hash->{OverallHeatingSwitchTT_t_regexp};
          my $maxTemp  = $hash->{OverallHeatingSwitchTT_maxTemp};

          my $temp = $defs{$sensor}->{READINGS}{$reading}{VAL};
          $temp =~ /$t_regexp/;
          if (defined ($1))
          {
            $temp = $1;
            if ($temp >= $maxTemp)
            {
              $newstateOHS_eoff = 1;
              $newstateOHS      = "off";
              Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitch forced to off since ThresholdTemp reached maxTemp ($temp >= $maxTemp)");
              readingsBulkUpdate ($hash,  "OverallHeatingSwitchTT_Off", 1);
            }
            else
            {
              if ($hash->{READINGS}{OverallHeatingSwitchTT_Off}{VAL} == 1) {
                readingsBulkUpdate ($hash,  "OverallHeatingSwitchTT_Off", 0);
              }
            }

          }
          else
          {
            Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitchThresholdTemp t_regexp does not match temperature");
          }
        }
        else
        {
          Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitchThresholdTemp refers to invalid device or reading");
        }
      }

      my $actor       = $hash->{OverallHeatingSwitch};
      my $actstateOHS = ($defs{$actor}{STATE} =~ $hash->{OverallHeatingSwitch_regexp_on}) ? "on" : "off";

      if ($hash->{OverallHeatingSwitch_followUpTime} > 0) {

        if ($newstateOHS_eoff == 1) 
        {
            readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitUntilOff", "");
        }
        else
        {
          if ($actstateOHS eq "on" and $newstateOHS eq "off") {

            if ($hash->{READINGS}{OverallHeatingSwitchWaitUntilOff}{VAL} eq "") {
              $newstateOHS = "on";
              Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitch wait for followUpTime before switching off (init timestamp)");
              readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitUntilOff", FmtDateTime(time() + $hash->{OverallHeatingSwitch_followUpTime}));

            } elsif ($hash->{READINGS}{OverallHeatingSwitchWaitUntilOff}{VAL} ge TimeNow()) {
              $newstateOHS = "on";
              Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitch wait for followUpTime before switching off");
            } else {
              readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitUntilOff", "");
            }

          } else {
            readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitUntilOff", "");
          }
        }
      }
      if ($hash->{OverallHeatingSwitch_delayTimeOn} > 0) {

        if ($actstateOHS eq "off" and $newstateOHS eq "on") {

          if ($hash->{READINGS}{OverallHeatingSwitchWaitBeforeOn}{VAL} eq "") {
            $newstateOHS = "off";
            Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitch wait for delayTimeOn before switching on (init timestamp)");
            readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitBeforeOn", FmtDateTime(time() + $hash->{OverallHeatingSwitch_delayTimeOn}));

          } elsif ($hash->{READINGS}{OverallHeatingSwitchWaitBeforeOn}{VAL} ge TimeNow()) {
            $newstateOHS = "off";
            Log3 ($name, 2, "PWM_Calculate: $name: OverallHeatingSwitch wait for delayTimeOn before switching on");
          } else {
            readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitBeforeOn", "");
          }

        } else {
          readingsBulkUpdate ($hash,  "OverallHeatingSwitchWaitBeforeOn", "");
        }
      }

      if ($newstateOHS ne $actstateOHS or $hash->{READINGS}{OverallHeatingSwitch}{VAL} ne $actstateOHS) {

        my $ret = fhem sprintf ("set %s %s", $hash->{OverallHeatingSwitch}, $newstateOHS);
        if (!defined($ret)) {    # sucessfull
          Log3 ($name, 4, "PWMR_SetRoom: $name: set $actor $newstateOHS");
  
          readingsBulkUpdate ($hash,  "OverallHeatingSwitch", $newstateOHS);

 
#          push @{$room->{CHANGED}}, "actor $newstateOHS";
#          DoTrigger($name, undef);
  
	} else {
          Log3 ($name, 4, "PWMR_SetRoom $name: set $actor $newstateOHS failed ($ret)");
        }
      }
    }
  }

 
  readingsEndUpdate($hash, 1);

#  if(!$hash->{LOCAL}) {
#    DoTrigger($name, undef) if($init_done);
#  }

}

###################################
sub 
PWM_CalcRoom(@)
{
  my ($hash, $room) = @_;
  my $name = $hash->{NAME};

  Log3 ($hash, 4, "PWM_CalcRoom: $name ($room->{NAME})");

  my $cycletime = $hash->{CYCLETIME};

  my ($temperaturV, $actorV, $factor, $oldpulse, $newpulse, $prevswitchtime, $windowV) =
     PWMR_ReadRoom($room, $cycletime, $hash->{MaxPulse});

  my $nextswitchtime; 
  if ($actorV eq "on") {
     $nextswitchtime = int($oldpulse * $cycletime) + $prevswitchtime;
  } else {
     $nextswitchtime = int((1-$oldpulse) * $cycletime) + $prevswitchtime;
  }

  #Log3 ($hash, 4, "PWM_CalcRoom $room->{NAME}: $cycletime ($prevswitchtime/$nextswitchtime)=".($nextswitchtime-$prevswitchtime));

  if ($actorV eq "on")                   # current state is "on"
  {
    # ----------------
    # check if valve protection is active, keep this state for 5 minutes

    if (defined ($room->{helper}{valveProtectLastSwitch}))  {
      if ( $room->{helper}{valveProtectLastSwitch} + 300 > time()) {
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F13 valveProtect continue");
         return ("", $newpulse, $cycletime, $actorV);
      } else {
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F14 valveProtect off");
         delete ($room->{helper}{valveProtectLastSwitch});
         return ("off_vp", $newpulse, $cycletime, $actorV);
      }

    }
      
    # ----------------
    # decide if to change to "off"

    if ($newpulse == 1) {
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F10 stay on");
         return ("", $newpulse, $cycletime, $actorV);
    }

    if ($newpulse < $oldpulse) {          # on: was 80% now it is 30%

       if ( time() >= $nextswitchtime )   # F3
       { 
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F3 new off");
         return ("off", $newpulse, $cycletime, $actorV);
         
         
           # state changed and it is worth to move the device
       }
       else #( time() < $nextswitchtime ) # F1
       {
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F1 stay on");
         return ("", $newpulse, $cycletime, $actorV);
       } 

    } else { #($newpulse >= $oldpulse)    # unchanged, or was 30% now 40%

					  # maybe we switch off 
 					  # - because several cycles were not calculated
					  # - or on time is simply over
                                          # - newpulse 0 is also handled here

      if ( time() >= $nextswitchtime) {   # F4
        Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F4 new off");
        return ("off", $newpulse, $cycletime, $actorV);
      } else {
        Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F9 stay on");
        return ("", $newpulse, $cycletime, $actorV);
      }

    }

  }
  elsif ($actorV eq "off")               # current state is "off"
  {
    # ----------------
    # check if valve protection is activated (attribute valveProtectIdlePeriod is set)

    if (defined ($attr{$name}{"valveProtectIdlePeriod"})) {
      # period is defined in days (*86400)
      if ($room->{READINGS}{lastswitch}{VAL} + ($attr{$name}{"valveProtectIdlePeriod"} * 86400)  < time()) {

      $room->{helper}{valveProtectLastSwitch} = time();
      Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F12 valve protect");
      return ("on_vp", $newpulse, $cycletime, $actorV); 
      }
    }

    # ----------------
    # decide if to change to "on"

    if ($oldpulse == 0 && $newpulse > 0) { # was 0% now heating is required 
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F7 new on");
         return ("on", $newpulse, $cycletime, $actorV); 
    }
    if ($newpulse == 0) {
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F11 stay off (0)");
         return ("", $newpulse, $cycletime, $actorV); 
    }

    if ($newpulse > $oldpulse) {         # was 30% now it is 80%
                                          # F5
       if ( time() < $nextswitchtime ) 
       {
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F5 stay off");
         return ("", $newpulse, $cycletime, $actorV); 

       } 
       else # time >= $nextswitchtime
       { 
                                          # F6
         Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F6 new on");
         return ("on", $newpulse, $cycletime, $actorV);
       }

    } else {                              # unchanged, was 80% now 30%
                                          # F2
      if ( time() >= $nextswitchtime ) {
        Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F2 new on");
        return ("on", $newpulse, $cycletime, $actorV);
      } else {
        Log3 ($hash, 3, "PWM_CalcRoom $room->{NAME}: F8 stay off");
        return ("", $newpulse, $cycletime, $actorV);
      }


    }

  }
  else # $actorV not "on" of "off"
  {
    Log3 ($hash, 3, "PWM_CalcRoom -> $name -> $room->{NAME}: invalid actor state ($actorV) try to switch off"); 
    return ("off", 0, $cycletime, $actorV);
    
  }
 
  return ("", $newpulse, $cycletime, $actorV);
  
}

###################################
sub
PWM_Get($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  return "argument is missing" if(int(@a) != 2);

  my $msg;

  if ($a[1] eq "status") {
    return $hash->{STATE};

  } elsif ($a[1] eq "timers") {
Log3 ($hash, 1, "in get timers");

    my $cnt = 0;
    my %tmpTimersFrom = ();
    my %tmpTimersTo   = ();

    foreach my $d (sort keys %defs) {
      if ( (defined ($defs{$d}{TYPE})) && $defs{$d}{TYPE} eq "PWMR" ) {      # all PWMR objects
        if (!defined ($attr{$d}{disable}) or $attr{$d}{disable} == 0) {     # not disabled
          if ($name eq $defs{$d}{IODev}->{NAME}) {                          # referencing to this fb
            my $room = $defs{$d};
Log3 ($hash, 1, "PWM_Get $name collect $room->{NAME}");

            foreach my $reading ("timer1_Mo", "timer2_Di", "timer3_Mi", "timer4_Do", "timer5_Fr", "timer6_Sa", "timer7_So") {
              if (defined ($room->{READINGS}{$reading}) and $room->{READINGS}{$reading} ne "") {

                $cnt++;

Log3 ($hash, 1, "PWM_Get $name collect $room->{NAME} $reading");
                my (@timers) = split / /, $room->{READINGS}{$reading}{VAL}; 
                
                my ($mintime, $minTempId, $minTemp ) = split /,/, $timers[0];
                my ($maxtime, $maxTempId, $maxTemp ) = split /,/, $timers[$#timers];

                my ($minfrom, $minto) = split /-/, $mintime;
                my ($maxfrom, $maxto) = split /-/, $maxtime;

		$tmpTimersFrom{$reading} = $minfrom unless defined($tmpTimersFrom{$reading});
                $tmpTimersTo{$reading}   = $maxto   unless defined($tmpTimersTo{$reading});

		$tmpTimersFrom{$reading} = $minfrom if ($tmpTimersFrom{$reading} > $minfrom);
                $tmpTimersTo{$reading}   = $maxto   if ($tmpTimersTo{$reading}   < $maxto);

              }
            }
          }
        }
      }
    }
    if ($cnt == 0) {
      foreach my $reading ("timer1_Mo", "timer2_Di", "timer3_Mi", "timer4_Do", "timer5_Fr", "timer6_Sa", "timer7_So") {
        delete ($hash->{READINGS}{$reading});
      }
    } else {
      readingsBeginUpdate ($hash);
      foreach my $reading ("timer1_Mo", "timer2_Di", "timer3_Mi", "timer4_Do", "timer5_Fr", "timer6_Sa", "timer7_So") {
        readingsBulkUpdate ($hash,  "$reading", $tmpTimersFrom{$reading}."-".$tmpTimersTo{$reading});
      }
      readingsEndUpdate($hash, 1);
      }

    #return "$reading from $minfrom to $maxto";
    return "";
  
  } else {
    return "Unknown argument $a[1], choose one of status timers";
  }
  
  #return $hash->{READINGS}{STATE}{VAL};
  #return $hash->{STATE};
}

#############################
sub
PWM_Set($@)
{
  my ($hash, @a) = @_;

  my $u = "Unknown argument $a[1], choose one of recalc interval cycletime";


  if ( $a[1] =~ /^interval$|^cycletime$/ ) {
    return $u if(int(@a) != 3);
 
    my $hw      = uc($a[1]);
    $hash->{$hw}= $a[2];

  } elsif ( $a[1] =~ /^recalc$/ ) {

    #$hash->{LOCAL} = 1;
    RemoveInternalTimer($hash);
    my $v = PWM_Calculate($hash);
    #delete $hash->{LOCAL};

  } else {
  
      return $u;
  }

  return undef;
}


#############################
sub
PWM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = $hash->{NAME};

  return "syntax: define <name> PWM [<interval>] [<cycletime>] [<minonofftime>] [<maxPulse>] [<maxSwitchOnPerCycle>,<maxSwitchOffPerCycle>] [<roomStayOn>,<roomStayOff>,<stayOnThreshold>]".
    " [<overallHeatingSwitch>[,<pulseThreshold>[,<followUpTime>[,<h_regexp_on>[,<delayTimeOn>]]]]"
    if(int(@a) < 2 || int(@a) > 9);

  my $interval     = ((int(@a) > 2) ? $a[2] : 60);
  my $cycletime    = ((int(@a) > 3) ? $a[3] : 900);
  my $minonofftime = ((int(@a) > 4) ? $a[4] : 120);
  my $maxPulse     = ((int(@a) > 5) ? minNum ($a[5], 1.00) : 1.00);

  $hash->{INTERVAL}             = $interval;
  $hash->{CYCLETIME}            = $cycletime;
  $hash->{MINONOFFTIME}         = $minonofftime;
  $hash->{MaxPulse}             = $maxPulse;

  $hash->{STATE}                = "defined";
  $hash->{p_interval}           = $interval;
  $hash->{p_cycletime}          = $cycletime;
  $hash->{p_minOnOfftime}       = $minonofftime;
  $hash->{p_maxPulse}           = $maxPulse;


  ##########
  # [<maxSwitchOnPerCycle>,<maxSwitchOffPerCycle>]

  if (int(@a) > 6) {
    my ($maxOn, $maxOff) = split (",", $a[6]);
    $maxOff = $maxOn unless (defined($maxOff));
 
    $hash->{MaxSwitchOnPerCycle}  = $maxOn;
    $hash->{MaxSwitchOffPerCycle} = $maxOff;

  } else {

    if ($maxPulse == 1) {
      $hash->{MaxSwitchOnPerCycle}  = 99;
      $hash->{MaxSwitchOffPerCycle} = 99;
    } else {
      $hash->{MaxSwitchOnPerCycle}  = 1;
      $hash->{MaxSwitchOffPerCycle} = 1;
    }

  }

  ##########
  # [<roomStayOn>,<roomStayOff>,<stayOnThreshold>]
 
  if (int(@a) > 7) {
    my ($stayOn, $stayOff, $onThreshold) = split (",", $a[7]);

    $stayOff     = 1   unless (defined($stayOff));      # one room stays off
    $onThreshold = 0.3 unless (defined($onThreshold));  # $stayOn is used only if average pluse is >= 0.3
 
    $hash->{NoRoomsToStayOn}             = $stayOn; 	    # eg. 4 rooms stay switched on (unless average pulse is less then threshold)
    $hash->{NoRoomsToStayOff}            = $stayOff;       # 1 room stays off to limit energy used (maxPulse should be < 1 if this is used)
    $hash->{NoRoomsToStayOnThreshold}    = $onThreshold;   # $stayOn is used only if average pluse is >= threshold
    $hash->{p_roomsMinOnOffThreshold}    = $a[7];

  } else {

    $hash->{NoRoomsToStayOn}             = 0;		# switch off all rooms is allowd
    $hash->{NoRoomsToStayOff}            = 0;		# switch on all rooms if allowed
    $hash->{NoRoomsToStayOnThreshold}    = 0;		# pulse threshold to use "NoRoomsToStayOn"
    $hash->{p_minOnOffThreshold}         = "";

  }

  ##########
  # [<overallHeatingSwitch>]

  if (int(@a) > 8) {
    my ($hactor, $h_threshold, $h_followUpTime, $h_regexp_on, $h_delayTimeOn) = split (",", $a[8], 5);
    $h_followUpTime  = 0    unless ($h_followUpTime);
    $h_threshold     = 0    unless ($h_threshold);
    $h_regexp_on     = "on" unless ($h_regexp_on);
    $h_delayTimeOn   = 0    unless ($h_delayTimeOn);

    if (!$defs{$hactor} && $hactor ne "dummy")
    {
      my $msg = "$name: Unknown actor device $hactor specified";
      Log3 ($hash, 3, "PWM_Define $msg");
      return $msg;
    }

    $hash->{OverallHeatingSwitch}               = $hactor;
    $hash->{OverallHeatingSwitch_threshold}     = $h_threshold;
    $hash->{OverallHeatingSwitch_regexp_on}     = $h_regexp_on;
    $hash->{OverallHeatingSwitch_roomBased}     = ($h_threshold > 0) ? "off" : "on";
    $hash->{OverallHeatingSwitch_followUpTime}  = $h_followUpTime;
    $hash->{OverallHeatingSwitch_delayTimeOn}   = $h_delayTimeOn;
    $hash->{p_overallHeatingSwitch}             = $a[8];
    readingsSingleUpdate ($hash,  "OverallHeatingSwitchWaitUntilOff", "", 0);
    readingsSingleUpdate ($hash,  "OverallHeatingSwitchWaitBeforeOn", "", 0);
    readingsSingleUpdate ($hash,  "OverallHeatingSwitch", "", 0);

    delete ($hash->{READINGS}{OverallHeatingSwitchWaitUntil}) if defined ($hash->{READINGS}{OverallHeatingSwitchWaitUntil});
    delete ($hash->{READINGS}{OverallHeatingSwitchWaitBefore}) if defined ($hash->{READINGS}{OverallHeatingSwitchWaitBefore});
  } else {
    $hash->{OverallHeatingSwitch}               = "";
    $hash->{OverallHeatingSwitch_threshold}     = "";
    $hash->{OverallHeatingSwitch_regexp_on}     = "";
    $hash->{OverallHeatingSwitch_roomBased}     = "";
    $hash->{OverallHeatingSwitch_followUpTime}  = "";
    $hash->{OverallHeatingSwitch_delayTimeOn}   = "";
    $hash->{p_overallHeatingSwitch}             = "";
    readingsSingleUpdate ($hash,  "OverallHeatingSwitchWaitUntilOff", "", 0);
    readingsSingleUpdate ($hash,  "OverallHeatingSwitchWaitBeforeOn", "", 0);
    readingsSingleUpdate ($hash,  "OverallHeatingSwitch", "", 0);

    delete ($hash->{READINGS}{OverallHeatingSwitchWaitUntil}) if defined ($hash->{READINGS}{OverallHeatingSwitchWaitUntil});
    delete ($hash->{READINGS}{OverallHeatingSwitchWaitBefore}) if defined ($hash->{READINGS}{OverallHeatingSwitchWaitBefore});
  }

  #AssignIoPort($hash);

  if($hash->{INTERVAL} > 0) {
    InternalTimer(gettimeofday() + 10, "PWM_Calculate", $hash, 0);
  }

  Log3 ($hash, 3, "PWM Define $name");

  return undef;
}

###################################
sub PWM_Undef($$)
{
  my ($hash, $args) = @_;

  my $name = $hash->{NAME};
  Log3 ($hash, 3, "PWM Undef $name");

  if ( $hash->{INTERVAL} )
  {
    RemoveInternalTimer($hash);
  }

  return undef;

}

sub
PWM_Attr(@)
{
  my @a = @_;
  my ($action, $name, $attrname, $attrval) = @a;

  my $hash = $defs{$name};

  $attrval = "" unless defined ($attrval);

  if ($action eq "del")
  {
    if ($attrname eq "overallHeatingSwitchThresholdTemp")
    {
      delete ($hash->{OverallHeatingSwitchTT_tsensor}       ) if defined ($hash->{OverallHeatingSwitchTT_tsensor});
      delete ($hash->{OverallHeatingSwitchTT_reading}       ) if defined ($hash->{OverallHeatingSwitchTT_reading});
      delete ($hash->{OverallHeatingSwitchTT_t_regexp}      ) if defined ($hash->{OverallHeatingSwitchTT_t_regexp});
      delete ($hash->{OverallHeatingSwitchTT_maxTemp}       ) if defined ($hash->{OverallHeatingSwitchTT_maxTemp});
      delete ($hash->{READINGS}{OverallHeatingSwitchTT_Off} ) if defined ($hash->{READINGS}{OverallHeatingSwitchTT_Off});
    }

    if (defined $attr{$name}{$attrname}) {
      delete ($attr{$name}{$attrname});
    }

    return undef;
  }
  elsif ($action eq "set")
  {
    if (defined $attr{$name}{$attrname}) 
    {
    }
    if ($attrname eq "overallHeatingSwitchThresholdTemp")
    {
      my ($obj, $temp) = split (",", $attrval, 2);
      $temp = 50 unless (defined($temp));

      unless ($temp =~ /^(\d[\d\.]+)$/)
      {
          return "$name: invalid temperature for attribute $attrname ($attrval)";
      }

      if (defined ($obj)) 
      {
        my ($sensor, $reading, $t_regexp) = split (":", $obj, 3);
        $reading = "temperature" unless defined ($reading);
        $t_regexp = '(\d[\d\.]+)', unless defined ($t_regexp);

        if (defined($sensor)) # may be not defined yet
        {
          $hash->{OverallHeatingSwitchTT_tsensor}  = $sensor;
          $hash->{OverallHeatingSwitchTT_reading}  = $reading;
          $hash->{OverallHeatingSwitchTT_t_regexp} = $t_regexp;
          $hash->{OverallHeatingSwitchTT_maxTemp}  = $temp;
          

        } else {
          Log3 ($hash, 2, "invalid temperature reading in attribute overallHeatingSwitchThresholdTemp");
          return "$name: invalid value for attribute $attrname ($attrval)";
        }
      } else {
        Log3 ($hash, 2, "invalid value for attribute overallHeatingSwitchThresholdTemp");
        return "$name: invalid value for attribute $attrname ($attrval)";
      }

    }
  }

  Log3 (undef, 2, "called PWM_Attr($a[0],$a[1],$a[2],<$a[3]>)");
 
  return undef;
}

###################################
1;

=pod
=item device
=item summary Device for room temperature control using PWM. See also 93_PWM.pm 
=begin html

<a name="PWM"></a>
<h3>PWM</h3>
<ul>

  <table>
  <tr><td>
  The PMW module implements temperature regulation for heating systems only capeable of switching on/off.<br><br>
  PWM is based on Pulse Width Modulation which means valve position 70% is implemented in switching the device on for 70% and off for 30% in a given timeframe.<br>
  PWM defines a calculation unit and depents on objects based on PWMR which define the rooms to be heated.<br>
  <br>
  </td></tr>
  </table>

  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PWM [&lt;interval&gt;] [&lt;cycletime&gt;] [&lt;minonofftime&gt;] [&lt;maxPulse&gt;] [&lt;maxSwitchOnPerCycle&gt;,&lt;maxSwitchOffPerCycle&gt;] [&lt;roomStayOn&gt;,&lt;roomStayOff&gt;,&lt;stayOnThreshold&gt;] [&lt;overallHeatingSwitch&gt;[,&lt;pulseThreshold&gt;[,&lt;followUpTime&gt;[,&lt;h_regexp_on&gt;[,&lt;delayTimeOn&gt;]]]]]<br></code>
    <br>
    eg. define fb PWM 60 900 120 1 99,99 0,0,0 pumpactor<br>
    <br>
    Define a calculation object with the following parameters:<br>
    <ul>
    <li>interval<br>
      Calculate the pulses every <i>interval</i> seconds. Default is 60 seconds.<br>
    </li>

    <li>cycletime<br>
      Timeframe to which the pulses refere to. Default is 900 seconds (=15 Minutes). "valve position" of 100% calculates to "on" for this period.<br>
    </li>

    <li>minonofftime<br>
      Default is 120 seconds.
      Floor heating systems are driven by thermomechanic elements which react very slow. on/off status changes for lower periods are ignored.<br>
    </li>

    <li>maxPulse<br>
      Default is 1, which means that a device can be switched on for the full <i>cylcetime</i> period.<br>
      For energy saving reasons it may be wanted to prevent situations were all rooms are switched on (high energy usage) and afterwards off.<br>
      In this case <i>maxPulse</i> is set to 0.85 (=12:45 minutes) which forces a room with a pulse of 1 (=100%) to be switched off after 12:45 minutes to give another 
      room the chance to be switched on.
      <br>
    </li>

    <li>maxSwitchOnPerCycle,maxSwitchoffPerCycle<br>
      Defaults are 99 for both values. This means that 99 PWMR object can be switched on or off at the same time.<br>
      To prevent energy usage peaks followend by "no energy consumption" situations set both values to "1".<br>
      This means after the room the the least energy required is switched off the next will be switched off.<br>
      Rooms are switched on or off one after the other (in <interval> cycles) and not all at one time.<br>
      Waiting times are honored by a addon to the pulse.<br>
      <br>
    </li>

    <li>roomStayOn,roomStayOff,stayOnThreshold<br>
      Defauts: <br>
      <i>roomStayOn</i> = 0 ... all rooms can be switched off at the same time.<br>
      <i>roomStayOff</i> = 0 ... all rooms can be switched on at the same time.<br>
      <i>stayOnThreshold</i> = 0 ... no impact.<br>
      For energy saving reasons the following may be set: "4,1,0.25". This means:<br>
      The room with the least pulse will be kept off (<i>roomsStayOff</i>=1)<br>
      If the average pulse for the (<i>roomsStayOn</i>=4) rooms with the most heating required is greater than (<i>stayOnThreshold</i>=0.25) then <i>maxRoomStayOn</i> will be kept in state "on", even if the time for the current pulse is reached.
      If the threshold is not reached (not so much heating required) then all rooms can be switched off at the same time.<br>
      <br>
    </li>

    <li>&lt;overallHeatingSwitch&gt[,&lt;pulseThreshold&gt[,&lt;followUpTime&gt;[,&lt;regexp_on&gt;[,&lt;delayTimeOn&gt;]]]]<br>
      Universal switch to controll eg. pumps or the heater itself. It will be set to "off" if no heating is required and otherwise "on".<br>
      <i>pulseThreshold</i> defines a threshold which is applied to reading <i>pulseMax</i>, <i>pulseSum</i>, <i>pulseAvg</i>, <i>pulseAvg2</i> or <i>pulseAvg3</i> of the PWM object to decide if heating is required. If (calculated pulse > threshold) then actor is set to "on", otherwise "off".<br>
      If <i>pulseThreshold</i> is set to 0 (or is not defined) then the decision is based on <i>roomsOn</i>. If (roomsOn > 0) then actor is set to "on", otherwise "off".<br>
      <i>followUpTime</i> defines a number of seconds which is used to delay the status change from "on" to "off". This can be used to prevent a toggling switch.<br>
      <i>regexp_on</i> defines a regular expression to be applied to the state of the actor. Default is "on". If state matches the regular expression it is handled as "on", otherwise "off".<br>
      <i>delayTimeOn</i> defines a number of seconds which is used to delay the status change from "off" to "on". This can be used to give the valves time to open before switching..<br>
      The pulse used for comparision is defined by attribute <i>overallHeatingSwitchRef</i>. Default is <i>maxPulse</i>.<br>
      <br>
    </li>

    </ul>

    <br>
    Example:<br>
    <br>
    <code>define fh PWM</code>
    <br>which is equal to<br>
    <code>define fh PWM 60 900 120 1 99,99 0,0,0</code>
    <br>Energy saving definition might be<br>
    <code>define fh PWM 60 900 120 0.85 1,1 4,1,0.25</code>
    <br><br>
       

  </ul>
  <br>

  <b>Set </b>
  <ul>
    <li>cycletime<br>
        Temporary change of parameter <i>cycletime</i>.
        </li><br>

    <li>interval<br>
        Temporary change of parameter <i>interval</i>.
        </li><br>

    <li>recalc<br>
        Cause recalculation that normally appeary every <i>interval</i> seconds.
        </li><br>

  </ul>

  <b>Get</b>
  <ul>
    <li>status<br>
        Retrieve content of variable <i>STATE</i>.
        </li><br>
    <li>timers<br>
        Retrieve values from the readings "timer?_??" from the attached rooms..<br>
        The readings define start and end times for different room temperatures.<br>
        This funktion will retrieve the first start and the last end time. <i>STATE</i>.
        </li><br>

  </ul>
  <br>

  <b>Attributes</b>
  <ul>
    <li>disable<br>
        Set to 1 will disable all calculations and STATE will be set to "disabled".<br>
        </li><br>
    <li>valveProtectIdlePeriod<br>
        Protect Valve by switching on actor for 300 seconds.<br>
        After <i>valveProtectIdlePeriod</i> number of days without switching the valve the actor is set to "on" for 300 seconds.
        overallHeatingSwitch is not affected.
        </li><br>
    <li>overallHeatingSwitchRef<br>
        Defines which reading is used for threshold comparision for <i>OverallHeatingSwitch</i> calculation. Possible values are:<br>
        <i>pulseMax</i>,
        <i>pulseSum</i>,
        <i>pulseAvg</i>,
        <i>pulseAvg2</i>,
        <i>pulseAvg3</i>,
	<i>avgPulseRoomsOn</i><br>
        pulseAvg is an average pulse of all rooms which should be switched to "on".<br>
        pulseAvg2 and pulseAvg3 refer to the 2 or 3 romms with highest pulses.
        </li><br>
    <li>overallHeatingSwitchThresholdTemp<br>
        Defines a reading for a temperature and a maximum value that prevents the overallHeatingSwitch from switching to "on".<br>
        Value has the following format: tsensor[:reading[:t_regexp]],maxValue.<br>
        <i>tsensor</i> defines the temperature sensor for the actual temperature.<br>
        <i>reading</i> defines the reading of the temperature sensor. Default is "temperature"<br>
        <i>t_regexp</i> defines a regular expression to be applied to the reading. Default is '(\d[\d\.]+)'.<br>
        if <i>maxValue</i> is reached as a temperature from tsensor then overallHeatingSwitch will not be switch to "on".<br>
        Example: tsensor,44 or tsensor:temperature,44 or tsensor:temperature:(\d+).*,44<br>
        The reading OverallHeatingSwitchTT_Off will be set to 1 if temperature from tsensor prevents <i>overallHeatingSwitch</i> from switching to "on".<br>
        Please be aware that temperatures raising to high will seriously harm your heating system and this parameter should not be used as the only protection feature.<br>
        Using this parameter is on your own risk. Please test your settings very carefully.<br>
    </li>

  </ul>
  <br>
</ul>

=end html
=cut

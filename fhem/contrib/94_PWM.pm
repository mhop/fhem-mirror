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

##############################################
# $Id: 


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

  $hash->{AttrList}  = "event-on-change-reading";

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
  my %RoomsPulses           = ();
  my $roomsActive           = 0;
  my $newpulseSum           = 0;
  my $newpulseMax           = 0;
  my $wkey                  = "";

  if($hash->{INTERVAL} > 0) {
    InternalTimer(gettimeofday() + $hash->{INTERVAL}, "PWM_Calculate", $hash, 0);
  }

  Log3 ($hash, 3, "PWM_Calculate $name");

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
         if ($hash->{NAME} eq $defs{$d}{IODev}) {                          # referencing to this fb

          Log3 ($hash, 4, "PWM_Calculate calc $name, room $d");

          ########################
          # calculate room
          # $newstate is "" if state is unchanged
          # $newstate is "on" or "off" if state changes
	  my ($newstate, $newpulse, $cycletime, $oldstate) = PWM_CalcRoom($hash, $defs{$d});

	  $defs{$d}->{READINGS}{oldpulse}{TIME} = TimeNow();
	  $defs{$d}->{READINGS}{oldpulse}{VAL}  = $newpulse;
	  
          my $onoff = $newpulse * $cycletime;
          if ($newstate eq "off") {
            $onoff = (1 - $newpulse) * $cycletime
          }

          $wkey = $name."_".$d;
          if (defined ($roomsWaitOffset{$wkey})) {
            $newpulse += $roomsWaitOffset{$wkey};
            
          } else {
            $roomsWaitOffset{$wkey} = 0;
          }

          $roomsActive++;
          $RoomsPulses{$d} = $newpulse;
          $newpulseSum += $newpulse;
          $newpulseMax = max($newpulseMax, $newpulse);

          # $newstate ne "" -> state changed "on" -> "off" or "off" -> "on"
          if ((int($hash->{MINONOFFTIME}) > 0) &&
              ($newstate ne "") && 
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

    #if ($roomsActive == 0 or $hash->{NoRoomsToStayOnThreshold} == 0 or $newpulseSum/$roomsActive < $hash->{NoRoomsToStayOnThreshold}) {

    if ($roomsActive == 0 or $hash->{NoRoomsToStayOnThreshold} == 0 or $pulseSum/$roomsCounted < $hash->{NoRoomsToStayOnThreshold}) {
      $minRoomsOn = 0;
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
  

  readingsBulkUpdate ($hash,  "roomsActive",   $roomsActive);
  readingsBulkUpdate ($hash,  "roomsOn",       $cntRoomsOn);
  readingsBulkUpdate ($hash,  "roomsOff",      $cntRoomsOff);
  readingsBulkUpdate ($hash,  "avgPulseRoomsOn",  ($cntRoomsOn > 0 ? sprintf ("%.2f", $pulseRoomsOn / $cntRoomsOn) : 0));
  readingsBulkUpdate ($hash,  "avgPulseRoomsOff", ($cntRoomsOff > 0 ? sprintf ("%.2f", $pulseRoomsOff /$cntRoomsOff) : 0));
  readingsBulkUpdate ($hash,  "pulseMax",      $newpulseMax);
  readingsBulkUpdate ($hash,  "pulseSum",      $newpulseSum);

  if ( $hash->{NoRoomsToStayOn} > 0) {
    readingsBulkUpdate ($hash,  "roomsToStayOn", $minRoomsOn);
    readingsBulkUpdate ($hash,  "roomsToStayOnList", $minRoomsOnList);
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

  return "argument is missing" if(int(@a) != 2);

  my $msg;

  if($a[1] ne "status") {
    return "Unknown argument $a[1], choose one of status";
  }
  
  #return $hash->{READINGS}{STATE}{VAL};
  return $hash->{STATE};
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

  return "syntax: define <name> PWM [<interval>] [<cycletime>] [<minonofftime>] [<maxPulse>] [<maxSwitchOnPerCycle>,<maxSwitchOffPerCycle>] [<roomStayOn>,<roomStayOff>,<stayOnThreshold>]"
    if(int(@a) < 2 || int(@a) > 8);

  my $interval     = ((int(@a) > 2) ? $a[2] : 60);
  my $cycletime    = ((int(@a) > 3) ? $a[3] : 900);
  my $minonofftime = ((int(@a) > 4) ? $a[4] : 120);
  my $maxPulse     = ((int(@a) > 5) ? min ($a[5], 1.00) : 0.85);

  $hash->{INTERVAL}             = $interval;
  $hash->{CYCLETIME}            = $cycletime;
  $hash->{MINONOFFTIME}         = $minonofftime;
  $hash->{MaxPulse}             = $maxPulse;

  $hash->{STATE}                = "defined";


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

  } else {

    $hash->{NoRoomsToStayOn}             = 0;		# switch off all rooms is allowd
    $hash->{NoRoomsToStayOff}            = 0;		# switch on all rooms if allowed
    $hash->{NoRoomsToStayOnThreshold}    = 0;		# pulse threshold to use "NoRoomsToStayOn"

  }

  AssignIoPort($hash);

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

1;

=pod
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
    <code>define &lt;name&gt; PWM [&lt;interval&gt;] [&lt;cycletime&gt;] [&lt;minonofftime&gt;] [&lt;maxPulse&gt;] [&lt;maxSwitchOnPerCycle&gt;,&lt;maxSwitchOffPerCycle&gt;] [&lt;roomStayOn&gt;,&lt;roomStayOff&gt;,&lt;stayOnThreshold&gt;]<br></code>
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
      If the average pulse for the (<i>roomsStayOn</i>=4) rooms with the most heating required is greater than (<i>stayOnThreshold</i>=0.25) then <i>maxRoomStayOn</i> will be kept in state "on", even it the time for the current pulse is reached.
      If the threshold is not reached (not so much heating required) then all rooms can be switched off at the same time.<br>
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

  </ul>
  <br>

  <b>Attributes</b>
  <ul>
  </ul>
  <br>
</ul>

=end html
=cut

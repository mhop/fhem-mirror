#
#
# 94_PWMR.pm
# written by Andreas Goebel 2012-07-25
# e-mail: ag at goebel-it dot de
#
##############################################
# $Id: 
# 29.07.15 GA change set <name> manualTempDuration <minutes>
# 21.09.15 GA update, use Log3 and readingsSingleUpdate
# 07.10.15 GA initial version published
# 07.10.15 GA fix calculation of PWMPulse, default for c_autoCalcTemp
# 13.10.15 GA add event-on-change-reading
# 14.10.15 GA fix round energyusedp 
# 15.10.15 GA add a_regexp_on, a regular expression for the on state of the actor
# 05.11.15 GA fix new reading desired-temp-until which substitutes modification date of desired-temp in the future
#                 events for desired-temp adjusted (no update of timestamp if temperature stays the same)
# 10.11.15 GA fix event for actor change added again, desired-temp notifications adjusted for midnight change


# module for PWM (Pulse Width Modulation) calculation
# this module defines a room for calculation 
# it is used by a PWM object 
# reference to the PWM object is via IODev
# PWMR object defines:
#  IODev: reference to PWM
#  factor (also used in PID calculation): 
#     temperatur difference * factor * cycletime (from PWM) defines on/off periods (pulse)
#  sensor delivering the temperature (temperature is read from reading using a regexp)
#  actor to switch on/off the heating devices (may be a structure if more than on actor..)
#  comma separated list of window contacts followd by ":" and a regular expression 
#     default for the regular expression is "Open"
#     if the regular expression matches on of the contacts 
#     then readRoom will return c_tempFrostProtect as desired-temp
#     instead of the current calculated desired-temp
#     this should cause the calculation routine for the room to switch off heating
#
# calculation of "desired-temp" is done in a loop (5-minutes default)
#  - if c_frostProtect is "1" -> set to c_tempFrostProtect
#  - if c_autoCalcTemp is "1" -> use c_tempN, c_tempD, c_tempC, c_tempE and c_tempRule[1-5]
#  - c_* variables are syntax checked and derived from attr which have a readable syntax
# 
#  - c_tempRule[1-5] are processed in order 5..1 (5 is highes priority)
#    rules define: 
#    <interval of valid days (0..6 = So..Sa)
#    <time>,[N|D|C] [<time>,[N|D|C|E]] 
#      ... time is interpreted as Hour[:Min]       
#      ... N,D,C,E reference timeN (Night), timeD (Day), timeC (Cosy), timeE(Energysave)
# 
#    attr names are: tempDay, tempCosy, tempNight, tempEnergy ...
#
# subroutines PWMR_ReedRoom and PWMR_SetRoom are called from PWM object


package main;

use strict;
use warnings;

my %dayno = (
   "mo"  => 1,
   "di"  => 2,
   "di"  => 3,
   "do"  => 4,
   "fr"  => 5,
   "sa"  => 6,
   "so"  => 0
);

sub PWMR_Get($@);
sub PWMR_Set($@);
sub PWMR_Define($$);
sub PWMR_CalcDesiredTemp($);
sub PWMR_SetRoom(@);
sub PWMR_ReadRoom(@);
sub PWMR_Attr(@);
sub PWMR_Boost(@);

###################################
sub
PWMR_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "PWMR_Get";
  $hash->{SetFn}     = "PWMR_Set";
  $hash->{DefFn}     = "PWMR_Define";
  $hash->{UndefFn}   = "PWMR_Undef";
  $hash->{AttrFn}    = "PWMR_Attr";

  $hash->{AttrList}  = "disable:1,0 loglevel:0,1,2,3,4,5 event-on-change-reading ".
			"frostProtect:0,1 ".
			"autoCalcTemp:0,1 ".
                        "tempFrostProtect ".
			"tempDay ".
			"tempNight ".
			"tempCosy ".
			"tempEnergy ".
			"tempRule1 ".
			"tempRule2 ".
			"tempRule3 ".
			"tempRule4 ".
			"tempRule5 ".
 			"";

}

###################################
sub
PWMR_CalcDesiredTemp($)
{
  my ($hash) = @_;

  if($hash->{INTERVAL} > 0) {
    if ($hash->{INTERVAL} == 300) {
      # align interval to hh:00:ss, hh:05:ss, ... hh:55:ss
      
      my $n = gettimeofday();
      my ($hour, $min, $sec) = split (":", FmtTime($n));

      # 15:12:05 -> 15:16:05  
      my $offset = ((((int($min/ 5)) +1 ) * 5 ) - $min) * 60;
      #Log3 ($hash, 4, "offset $min -> ".int($min / 5)." $offset ".($offset / 60));

      InternalTimer($n + $offset, "PWMR_CalcDesiredTemp", $hash, 0);

    } else {
      InternalTimer(gettimeofday()+$hash->{INTERVAL}, "PWMR_CalcDesiredTemp", $hash, 0);
      #Log3 ($hash, 4, "interval not 300");
    }
  }

  my $name = $hash->{NAME};

  if (defined($hash->{READINGS}{"desired-temp-until"})) {
    if ($hash->{READINGS}{"desired-temp-until"}{VAL} ne "no" ) {

      if ($hash->{READINGS}{"desired-temp-until"}{VAL} gt TimeNow()) {

        Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: desired-temp was manualy set until ".
          $hash->{READINGS}{"desired-temp"}{TIME});
        $hash->{STATE}     = "ManualSetUntil";
        return undef;
      }
      else
      {
        readingsSingleUpdate ($hash,  "desired-temp-until", "no", 1);
        Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: calc desired-temp");
      }
    }
  }

  #if ($hash->{READINGS}{"desired-temp"}{TIME} gt TimeNow()) {
  #  Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: desired-temp was manualy set until ".
  #      $hash->{READINGS}{"desired-temp"}{TIME});
  #
  #  $hash->{STATE}     = "ManualSetUntil";
  #  return undef;
  #} else {
  #  Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: calc desired-temp");
  #}

  ####################
  # frost protection

  if ($hash->{c_frostProtect} > 0) {
    if ($hash->{READINGS}{"desired-temp"}{VAL} ne $hash->{c_tempFrostProtect}  
        or substr(TimeNow(),1,8) ne substr($hash->{READINGS}{"desired-temp"}{TIME},1,8)) {
      readingsSingleUpdate ($hash,  "desired-temp", $hash->{c_tempFrostProtect}, 1);
    } else {
      readingsSingleUpdate ($hash,  "desired-temp", $hash->{c_tempFrostProtect}, 0);
    }

    #$hash->{READINGS}{"desired-tem"}{TIME} = TimeNow();
    #$hash->{READINGS}{"desired-temp"}{VAL} = $hash->{c_tempFrostProtect};

    #push @{$hash->{CHANGED}}, "desired-temp $hash->{c_tempFrostProtect}";
    #DoTrigger($name, undef);
 
    $hash->{STATE}     = "FrostProtect";
    return undef;
  }

  ####################
  # rule based calculation

  if ($hash->{c_autoCalcTemp} > 0) {

    $hash->{STATE}     = "Calculating";

    my @time = localtime();
    my $wday = $time[6];
    my $cmptime = sprintf ("%02d%02d", $time[2], $time[1]);
    Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: wday $wday cmptime $cmptime");

    foreach my $rule ($hash->{c_tempRule5}, 
                      $hash->{c_tempRule4}, 
                      $hash->{c_tempRule3}, 
                      $hash->{c_tempRule2}, 
                      $hash->{c_tempRule1} ) {
      if ($rule ne "") {		# valid rule is 1-5 0600,D 1800,C 2200,N

        Log3 ($hash, 5, "PWMR_CalcDesiredTemp $name: $rule");

        my @points = split (" ", $rule);

        my ($dayfrom, $dayto) = split ("-", $points[0]);
        #Log3 ($hash, 5, "PWMR_CalcDesiredTemp $name: dayfrom $dayfrom dayto $dayto");

        my $rulematch = 0;
        if ($dayfrom <= $dayto ) {                    # rule 1-5 or 4-4
          $rulematch = ($wday >= $dayfrom && $wday <= $dayto);
        } else {                                      # rule  5-2
          $rulematch = ($wday >= $dayfrom || $wday <= $dayto);
        }

        if ($rulematch) {

          for (my $i=int(@points)-1; $i>0; $i--) {
            Log3 ($hash, 5, "PWMR_CalcDesiredTemp $name: i:$i $points[$i]");

            my ($ruletime, $tempV) = split (",", $points[$i]);

            if ($cmptime >= $ruletime) {

              my $temperature = $hash->{"c_tempN"};
              $temperature = $hash->{"c_tempD"} if ($tempV eq "D");
              $temperature = $hash->{"c_tempC"} if ($tempV eq "C");
              $temperature = $hash->{"c_tempE"} if ($tempV eq "E");

              Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: match i:$i $points[$i] ($tempV/$temperature)");
               
              if ($hash->{READINGS}{"desired-temp"}{VAL} ne $temperature 
                  or substr(TimeNow(),1,8) ne substr($hash->{READINGS}{"desired-temp"}{TIME},1,8)) {
                readingsSingleUpdate ($hash,  "desired-temp", $temperature, 1);
              } else {
                readingsSingleUpdate ($hash,  "desired-temp", $temperature, 0);
              }

              #$hash->{READINGS}{"desired-temp"}{TIME} = TimeNow();
              #$hash->{READINGS}{"desired-temp"}{VAL} = $temperature;

              #push @{$hash->{CHANGED}}, "desired-temp $temperature";
              #DoTrigger($name, undef);
              return undef;
            } 

          }
          # no interval matched .. guess I am before the first one
          # so I choose the temperature from yesterday :-)
          # this should be the tempN
          my $newTemp = $hash->{"c_tempN"};

          my $act_dtemp = $hash->{READINGS}{"desired-temp"}{VAL};
          Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: use last value ($act_dtemp)");

          if ($act_dtemp ne $newTemp
            or substr(TimeNow(),1,8) ne substr($hash->{READINGS}{"desired-temp"}{TIME},1,8)) {
            readingsSingleUpdate ($hash,  "desired-temp", $newTemp, 1);
          #} else {
          #  readingsSingleUpdate ($hash,  "desired-temp", $newTemp, 0);
          }

          #$hash->{READINGS}{"desired-temp"}{TIME} = TimeNow();
          #$hash->{READINGS}{"desired-temp"}{VAL} = $newTemp;

          #push @{$hash->{CHANGED}}, "desired-temp $newTemp";
          #DoTrigger($name, undef);
          return undef;
        }
      }
    }

  } else {
    $hash->{STATE}     = "Manual";
  }

  #DoTrigger($name, undef);
  return undef;

}

###################################
sub
PWMR_Get($@)
{
  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  my $msg;

  if($a[1] ne "status") {
    return "unknown get value, valid is status";
  }
  $hash->{LOCAL} = 1;
  RemoveInternalTimer($hash);
  my $v = PWMR_CalcDesiredTemp($hash);
  delete $hash->{LOCAL};

  return "$a[0] $a[1] => recalculatd";
}

#############################
sub
PWMR_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};

  my @list = map { ($_.".0", $_+0.5) } (6..29);
  my $valList = join (",", @list);
  $valList .= ",30.0";
  #my $u = "Unknown argument $a[1], choose one of factor actor:off,on desired-temp:knob,min:6,max:26,step:0.5,linecap:round interval manualTempDuration:slider,60,60,600";
  #my $u = "Unknown argument $a[1], choose one of factor actor:off,on desired-temp:uzsuDropDown:$valList interval manualTempDuration:slider,60,60,600";
  my $u = "Unknown argument $a[1], choose one of factor actor:off,on desired-temp:$valList interval manualTempDuration:slider,60,60,600";

  $valList = "slider,6,0.5,30,0.5";

  return $u if ($a[1] eq "?");

  return $u if(int(@a) < 3);

  my $cmd = $a[1];

  ##############
  # manualTempDuration

  if ( $cmd eq "manualTempDuration" ) {
    readingsSingleUpdate ($hash,  "manualTempDuration", $a[2], 1);

    #$hash->{READINGS}{"manualTempDuration"}{VAL} = $a[2];
    #$hash->{READINGS}{"manualTempDuration"}{TIME} = TimeNow();
    return undef;
  } 

  ##############
  # desired-temp

  if ( $cmd eq "desired-temp" ) {
    my $val = $a[2];
    if ( $val < 6 || $val > 30 ) {
      return "Unknown argument for $cmd, choose <6..30>";
    }
    
    my $duration = defined($hash->{READINGS}{"manualTempDuration"}{VAL}) ? $hash->{READINGS}{"manualTempDuration"}{VAL} * 60 : 60 * 60;

    if (defined($a[3])) {
      $duration = int($a[3]) * 60;
    }
    
    # manual set desired-temp will be set for 1 hour (default)
    # afterwards it will be overwritten by auto calc
 
    my $now =  time();

    readingsBeginUpdate ($hash);
    readingsBulkUpdate ($hash,  "desired-temp", $a[2]);
    if ($hash->{c_autoCalcTemp} == 0) {
      $hash->{STATE}     = "Manual";
    } else {
      $hash->{STATE}     = "ManualSetUntil";
      readingsBulkUpdate ($hash,  "desired-temp-until", FmtDateTime($now + $duration));
    }
    readingsEndUpdate($hash, 1);
 
    #readingsSingleUpdate ($hash,  "desired-temp", $a[2], 1);

    #$hash->{READINGS}{$cmd}{TIME} = FmtDateTime($now + $duration);
    #$hash->{READINGS}{$cmd}{VAL} = $val;


    #push @{$hash->{CHANGED}}, "$cmd: $val";
    #DoTrigger($hash, undef);
    return undef
  } 

  ##############
  # actor 

  if ( $cmd eq "actor" ) {
    my $val = $a[2];
    if ( $val eq "on" || $val eq "off" ) {
      PWMR_SetRoom($hash, $val);
      return undef;
    } else {
      return "Unknow argument for $cmd, choose on|off";
    }
  }

  ##############
  # others

  if ($cmd =~ /^interval$|^factor$/) {
	my $var = uc($a[1]);
	$hash->{$var} = $a[2];
  } else {
      return $u;
  }

  return undef;
}


#############################
sub
PWMR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $name = $hash->{NAME};

  return "syntax: define <name> PWMR <IODev> <factor[,offset]> <tsensor[:reading:t_regexp]> <actor>[:<a_regexp_on>] [<window>[,<window>]:<w_regexp>]"
    if(int(@a) < 6 || int(@a) > 8);

  my $iodev   = $a[2];
  my $factor  = ((int(@a) > 2) ? $a[3] : 0.2);
  my $tsensor = ((int(@a) > 3) ? $a[4] : "");
  my $actor   = ((int(@a) > 4) ? $a[5] : "");
  my $window  = ((int(@a) > 6) ? $a[6] : "");

  my ($f, $o) = split (",", $factor, 2);
  $o = 0.11 unless (defined ($o));       # if cycletime is 900 then this increases the on-time by 1:39 (=99 seconds)
 
  $hash->{TEMPSENSOR}         = $tsensor;
  $hash->{ACTOR}              = $actor;
  $hash->{WINDOW}             = $window;
  $hash->{FACTOR}             = $f;		# pulse is calculated using the below formular
  $hash->{FOFFSET}            = $o;             # ( $deltaTemp * $factor) ** 2) + $factoroffset
  
  #$hash->{helper}{cycletime}  = 0;

  if ( !$defs{$iodev} ) {
    return "unknown device $iodev";
  }

  if ( $defs{$iodev}->{TYPE} ne "PWM" ) {
    return "wrong type of $iodev (not PWM)";
  }

  $hash->{IODev} = $iodev;
  
  ##########
  # calculage factoroffset 
  # 01.10.2015
  #my $minonoff     = $defs{$iodev}->{MINONOFFTIME};
  #my $cycle        = $defs{$iodev}->{CYCLETIME};
  #my $factorOffset = ($minonoff / $cycle) - 0.02;
  #$factorOffset = sprintf ("%.2f", $factorOffset);
  #$hash->{factoroffset} = $factorOffset;

  ##########
  # check window

  $hash->{windows} = "";

  my ($allwindows, $w_regexp) = split (":", $window, 2);

  if ( !defined($w_regexp) ) 
  {  
    # this regexp defines the result of ReadRoom
    # if any window is open return 1

    $w_regexp = '.*Open.*'
  }
  $hash->{w_regexp}    = $w_regexp;

  if ( defined ($allwindows) ) { 
    my (@windows) = split (",", $allwindows);
    foreach my $onewindow (@windows) {
  
      if (!$defs{$onewindow} && $onewindow ne "dummy") {
        my $msg = "$name: Unknown window device $onewindow specified";
        Log3 ($hash, 3, "PWMR_Define $msg");
        return $msg;
      }

      if (length($hash->{windows}) > 0 ) {
        $hash->{windows} .= ",$onewindow"
      } else {
        $hash->{windows} = "$onewindow"
      }
    }
  }

  

  ##########
  # check sensor
  # dummy is allowed and will be ignored

  my ($sensor, $reading, $t_regexp) = split (":", $tsensor, 3);
  if (!$defs{$sensor} && $sensor ne "dummy")
  {
    my $msg = "$name: Unknown sensor device $sensor specified";
    Log3 ($hash, 3, "PWMR_Define $msg");
    return $msg;
  }

  $sensor            =~ s/dummy//;
  $hash->{t_sensor}    = $sensor;
  $reading = "temperature" unless (defined($reading));
  $hash->{t_reading}   = $reading;
  if ( !defined($t_regexp) ) 
  {  
    $t_regexp = '([\\d\\.]*)'
  }
  $hash->{t_regexp}    = $t_regexp;

  ##########
  # check actor

  my ($tactor, $a_regexp_on) = split (":", $actor, 2);

  $a_regexp_on = "on" unless defined ($a_regexp_on);

  $tactor              =~ s/dummy//;
  $hash->{actor}       = $tactor;
  $hash->{a_regexp_on} = $a_regexp_on;
  $hash->{actorState}  = "unknown";

  $hash->{STATE}       = "Initialized";

  # values for calculation of desired-temp

  $hash->{c_frostProtect}     = 0;
  $hash->{c_autoCalcTemp}     = 1;
  $hash->{c_tempFrostProtect} = 6;
  $hash->{c_tempN}            = 16;
  $hash->{c_tempD}            = 20;
  $hash->{c_tempC}            = 22;
  $hash->{c_tempE}            = 19;
  $hash->{c_tempRule1}        = "1-5 0600,D 2200,N";
  $hash->{c_tempRule2}        = "6-0 0800,D 2200,N";
  $hash->{c_tempRule3}        = "";
  $hash->{c_tempRule4}        = "";
  $hash->{c_tempRule5}        = "";

  $hash->{INTERVAL}           = 300;

  AssignIoPort($hash);

  if($hash->{INTERVAL}) {
    InternalTimer(gettimeofday()+10, "PWMR_CalcDesiredTemp", $hash, 0);
  }
  return undef;
}

#############################
sub PWMR_Undef($$)
{
  my ($hash, $args) = @_;

  my $name = $hash->{NAME};
  Log3 ($hash, 3, "PWMR Undef $name");

  if ( $hash->{INTERVAL} )
  {
    RemoveInternalTimer($hash);
  }

  return undef;

}


#############################
sub 
PWMR_SetRoom(@)
{
  my ($room, $newState) = @_;

  my $name = $room->{NAME};

  Log3 ($room, 4, "PWMR_SetRoom $name <$newState>");

  my $energyused = "";
  if (defined($room->{READINGS}{energyused}{VAL})) {                                        
    $energyused = substr ( $room->{READINGS}{energyused}{VAL}, -29);
  }

  # newState may be "", "on", "off"
  if ($newState eq "") {
    $energyused = $energyused.substr ( $energyused ,-1);
  } else {
    $energyused = $energyused.($newState eq "on" ? "1" : "0");
  }

  readingsBeginUpdate ($room);
  readingsBulkUpdate ($room,  "energyused", $energyused);
  readingsBulkUpdate ($room,  "energyusedp", sprintf ("%.2f", ($energyused =~ tr/1//) /30));
  readingsEndUpdate($room, 0);
  
  if ($newState eq "") {
    return;
  }

  if ($room->{actor})
  {
    my $ret = fhem sprintf ("set %s %s", $room->{actor}, $newState);
    if (!defined($ret)) {    # sucessfull
      Log3 ($room, 2, "PWMR_SetRoom $room->{NAME}: set $room->{actor} $newState");
       
      $room->{actorState}                 = $newState;
      readingsSingleUpdate ($room,  "lastswitch", time(), 1);

      push @{$room->{CHANGED}}, "actor $newState";
      DoTrigger($name, undef);

      Log3 ($room, 2, "PWMR_SetRoom $name: set $room->{actor} $newState failed ($ret)");
    }

  }
}


###################################
sub 
PWMR_ReadRoom(@)
{
  my ($room, $cycletime, $MaxPulse) = @_; # room, cylcetime for PMW Calculation (15Min), Max Time to stay on (0.00 .. 1.00)

  my $name = $room->{NAME};
  my $temperaturT;
  my $desiredTemp;
  my $prevswitchtimeT;

  #$room->{helper}{cycletime} = $cycletime;

  my ($temperaturV, $actorV, $factor, $oldpulse, $newpulse, $prevswitchtime, $windowV) = 
    (99, "off", 0, 0, 0, 0, 0);

  #Log3 ($room, 4, "PWMR_ReadRoom $name <$room->{t_sensor}> <$room->{actor}>");

  if ($room->{t_sensor})
  {
    my $sensor   =  $room->{t_sensor};
    my $reading  =  $room->{t_reading};
    my $t_regexp =  $room->{t_regexp};

    $temperaturV =  $defs{$sensor}->{READINGS}{$reading}{VAL};
    $temperaturT =  $defs{$sensor}->{READINGS}{$reading}{TIME};

    $temperaturV =~ s/$t_regexp/$1/;
  }

  if ($room->{actor})
  {
    # HERE
    #$actorV    =  (($defs{$room->{actor}}->{STATE} eq "on") : "on" ? "off");
    #$actorV    =  $defs{$room->{actor}}->{STATE};
    
    # until 26.01.2013 -> may be undef which forces room to be switched off first
    #$actorV    =  $room->{actorState};
    
    # starting from 26.01.2013 -> try to read act status .. (may also be invalid if struct)
    if ($defs{$room->{actor}}->{TYPE} eq "RBRelais") {
      $actorV =  $defs{$room->{actor}}->{STATE};
    } elsif (defined($defs{$room->{actor}}->{STATE})) {
      $actorV =  $defs{$room->{actor}}->{STATE};
    } else {
      $actorV = $room->{actorState};
    } 

    #my $actorVOrg = $actorV;
    
    my $a_regexp_on = $room->{a_regexp_on};
    if ($actorV =~ /^$a_regexp_on$/) {
      $actorV = "on";
    } else {
      $actorV = "off";
    }
    #Log3 ($room, 2, "$name actorV $actorV org($actorVOrg) regexp($a_regexp_on)");
  }

  if (!$room->{READINGS}{"desired-temp"}{TIME})
  {
    readingsSingleUpdate ($room,  "desired-temp", 6.0, 0);
  }

  if (!$room->{READINGS}{oldpulse}{TIME})
  {
    readingsSingleUpdate ($room,  "oldpulse", 0.0, 0);
  }

  if (!$room->{READINGS}{lastswitch}{TIME})
  {
    readingsSingleUpdate ($room,  "lastswitch", time(), 0);
  }

  $factor          = $room->{FACTOR};
  $oldpulse        = $room->{READINGS}{oldpulse}{VAL};
  $prevswitchtime  = $room->{READINGS}{lastswitch}{VAL};
  $prevswitchtimeT = $room->{READINGS}{lastswitch}{TIME};

  $windowV        = 0;
  if ($room->{windows} && $room->{windows} ne "" && $room->{w_regexp} ne "")
  {
    foreach my $window (split (",", $room->{windows})) {
      Log3 ($room, 4, "PWMR_ReadRoom $name: check window $window");
      if (defined($room->{w_regexp}) && $room->{w_regexp} ne "") {
        if (defined($defs{$window}) && $defs{$window}{STATE} ) {
        
          Log3 ($room, 5, "PWMR_ReadRoom $name: $window ($defs{$window}{STATE}/$room->{w_regexp})");
          if ( $defs{$window}{STATE} =~ /$room->{w_regexp}/ ) {
            $windowV = 1;
            Log3 ($room, 3, "PWMR_ReadRoom $name: $window state: set to 1");
          
          }
        }
      }
    }
  }

  if ($windowV > 0) {
    $desiredTemp    = $room->{c_tempFrostProtect};
  } else {
    $desiredTemp    = $room->{READINGS}{"desired-temp"}{VAL};
  }

  my $deltaTemp    = max (0, $desiredTemp - $temperaturV);
  
  my $factoroffset = $room->{FOFFSET};
  
  my $PWMPulse    = min ($MaxPulse,  (( $deltaTemp * $factor) ** 2) + $factoroffset);

  $newpulse       = $PWMPulse;
  #$newpulse       = min ($MaxPulse, $newpulse); # default 85% max ontime
  $newpulse       = sprintf ("%.2f", $newpulse);

  my $PWMOnTime =  sprintf ("%02s:%02s", int ($PWMPulse * $cycletime / 60), ($PWMPulse * $cycletime) % 60);

  readingsBeginUpdate ($room);
  readingsBulkUpdate ($room,  "PWMOnTime", $PWMOnTime);
  readingsBulkUpdate ($room,  "PWMPulse", $newpulse);
  readingsEndUpdate($room, 1);

  
  Log3 ($room, 4, "PWMR_ReadRoom $name: desT($desiredTemp), actT($temperaturV von($temperaturT)), state($actorV)");
  Log3 ($room, 4, "PWMR_ReadRoom $name: newpulse($newpulse/$PWMOnTime), oldpulse($oldpulse), lastSW($prevswitchtime = $prevswitchtimeT), window($windowV)");

  return ($temperaturV, $actorV, $factor, $oldpulse, $newpulse, $prevswitchtime, $windowV);

}
  

sub 
PWMR_normTime ($)
{
  my ($time) = @_;

  my $hour = 0;
  my $minute = 0;

  #Log 4, "normTime $time";

  $time =~ /^([0-9]+):*([0-9]*)$/;

  if (defined ($2) && ($2 ne "")) {  # set $minute to 0 if time was only 6 
    $minute = $2;
  }
    
  if (defined ($1)) {  # error if no hour given
    $hour = $1
  } else {
    return undef;
  }

  #Log 4, "<$hour> <$minute>";

  if ($hour < 0 || $hour > 23) {
    return undef;
  }
  if ($minute < 0 || $minute > 59) {
    return undef;
  }

  #Log 4, "uhrzeit $hour $minute";
  return sprintf ("%02d%02d", $hour, $minute);

}

sub 
PWMR_CheckTempRule(@)
{
  my ($hash, $var, $vals) = @_;

  my $name = $hash->{NAME};
  my $valid  = "";

  my $usage = "usage: [Mo|Di|..|So[-Mo|-Di|..|-So] <zeit>,D|C|E|N [<zeit>,D|C|E|N] ]\n".
  		"e.g. Mo-Fr 6:00,D 22,N\n".
 		"or   So 10,D 23,N";
  
  Log3 ($hash, 4, "PWMR_CheckTempRule: $hash->{NAME} $var <$vals>");

  my @points = split (" ", $vals);
  my $day = $points[0];

  unless ( $day =~ /-/ ) {                   # normalise Mo to  Mo-Mo
    $day = "$day-$day";
  }

  # analyse Mo-Di

  my ($from, $to) = split ("-", $day);
  $from = lc ($from);
  $to   = lc ($to);
  if (defined ($dayno{$from}) && defined ($dayno{$to})) {
    $valid .= "$dayno{$from}-$dayno{$to} ";
  } else {
    return $usage;
  }

  Log3 ($hash, 4, "PWMR_CheckTempRule: $name day valid: $valid");

  shift @points;

  foreach my $point (@points) {
    #Log3 ($hash, 4, "loop: $point");
    my ($from, $temp) = split(",", $point);
    $temp = uc($temp);
    unless ($temp eq "D" || $temp eq "N" || $temp eq "C" || $temp eq "E") {   # valid temp
      return $usage;
    }
 
    #Log3 ($hash, 4, "loop: fromto: $fromto");
 
    return $usage unless ( $from = PWMR_normTime($from) );

    Log3 ($hash, 4, "PWMR_CheckTempRule: $name time valid: $from,$temp");

    $valid .= "$from,$temp ";


  } 

  Log3 ($hash, 4, "PWMR_CheckTempRule: $name $var <$valid>");

  $hash->{$var} = $valid;

  return undef
} 

sub 
PWMR_CheckTemp(@)
{
  my ($hash, $var, $vals) = @_;

  my $error = "valid values are 0 ... 30";
  
  my $name = $hash->{NAME};
  Log3 ($hash, 4, "PWMR_CheckTemp: $name $var <$vals>");

  if ($vals !~ /^[0-9]+\.{0,1}[0-9]*$/ ) {
    return "$error";
  } else {
  }

  if ($vals < 0 || $vals > 30) {
    return "$error";
  }

 $hash->{$var} = $vals;
 return undef;

}

sub 
PWMR_Attr(@)
{
  my @a = @_;

  my $name = $a[1];
  my $hash = $defs{$name};
  my $attr = $a[2];
  my $val  = $a[3];
  
  if ($a[0] eq "del") {
  
    if ($attr eq "tempRule1") {
      $hash->{c_tempRule1} = "";
    } elsif ($attr eq "tempRule2") {
      $hash->{c_tempRule2} = "";
    } elsif ($attr eq "tempRule3") {
      $hash->{c_tempRule3} = "";
    } elsif ($attr eq "tempRule4") {
      $hash->{c_tempRule4} = "";
    } elsif ($attr eq "tempRule5") {
      $hash->{c_tempRule5} = "";
    } elsif ($attr eq "frostProtect") {
      $hash->{c_frostProtect} = 0;
    } elsif ($attr eq "autoCalcTemp") {
      $hash->{c_autoCalcTemp} = 1;
      $hash->{STATE}     = "Calculating";
    }
  
  }

  if (!defined($val)) {
    Log3 ($hash, 4, "PWMR_Attr: $name, delete $attr ($val)");
    return undef;
  } else {
    Log3 ($hash, 4, "PWMR_Attr: $name, $attr, $val");
  }

  if ($attr eq "frostProtect") {                            # frostProtect  0/1
    if ($val eq 0 or $val eq 1) {
      $hash->{c_frostProtect} = $val;
    } elsif ($val eq "") {
      $hash->{c_frostProtect} = 0;
    } else {
      return "valid values are 0 or 1";
    }

  } elsif ($attr eq "autoCalcTemp") {                       # autoCalcTemp 0/1
    if ($val eq 0) {
      $hash->{c_autoCalcTemp} = 0;
      $hash->{STATE}     = "Manual";
    } elsif ( $val eq 1) {
      $hash->{c_autoCalcTemp} = 1;
      $hash->{STATE}     = "Calculating";
    } elsif ($val eq "") {
      $hash->{c_autoCalcTemp} = 1;
      $hash->{STATE}     = "Calculating";
    } else {
      return "valid values are 0 or 1";
    }

  } elsif ($attr eq "tempDay") {                           # tempDay
    return PWMR_CheckTemp($hash, "c_tempD", $val);

  } elsif ($attr eq "tempNight") {                         # tempNight
    return PWMR_CheckTemp($hash, "c_tempN", $val);

  } elsif ($attr eq "tempCosy") {                          # tempCosy
    return PWMR_CheckTemp($hash, "c_tempC", $val);

  } elsif ($attr eq "tempEnergy") {                        # tempEnergy
    return PWMR_CheckTemp($hash, "c_tempE", $val);

  } elsif ($attr eq "tempRule1") {                         # tempRule1
    return PWMR_CheckTempRule($hash, "c_tempRule1", $val);

  } elsif ($attr eq "tempRule2") {                         # tempRule2
    return PWMR_CheckTempRule($hash, "c_tempRule2", $val);

  } elsif ($attr eq "tempRule3") {                         # tempRule3
    return PWMR_CheckTempRule($hash, "c_tempRule3", $val);

  } elsif ($attr eq "tempRule4") {                         # tempRule4
    return PWMR_CheckTempRule($hash, "c_tempRule4", $val);

  } elsif ($attr eq "tempRule5") {                         # tempRule5
    return PWMR_CheckTempRule($hash, "c_tempRule5", $val);

  }

  return undef;

}

sub 
PWMR_Boost(@)
{
  my ($me, $outsideSensor, $outsideMax, $deltaTemp, $desiredOffset, $boostDuration) = @_;
  
  return undef unless defined ($defs{$me}->{NAME});
  
  my $room = $defs{$me};
  my $name = $room->{NAME};
  
  my $outsideTemp = 99;
  if (defined($defs{$outsideSensor}->{READINGS}{temperature}{VAL})) {
    $outsideTemp = $defs{$outsideSensor}->{READINGS}{temperature}{VAL};
  }
  
  if ($room->{t_sensor})
  {
    my $sensor   =  $room->{t_sensor};
    my $reading  =  $room->{t_reading};
    my $t_regexp   =  $room->{t_regexp};

    my $temperaturV =  $defs{$sensor}->{READINGS}{$reading}{VAL};
    $temperaturV =~ s/$t_regexp/$1/;
    
    my $desiredTemp    = $room->{READINGS}{"desired-temp"}{VAL};
    
    # boost necessary?
    if (($outsideTemp < $outsideMax)
     && ($temperaturV <= $desiredTemp - $deltaTemp)) {
     
      Log3 ($room, 3, "PWMR_Boost: $name ".
        "($outsideTemp, $outsideMax, $deltaTemp, $desiredOffset, $boostDuration) ".
        "temp($temperaturV) desired-temp($desiredTemp) -> boost");
        
      my $now =  time();

      readingsBeginUpdate ($room);
      readingsBulkUpdate ($room,  "desired-temp", $desiredTemp + $desiredOffset);
      readingsBulkUpdate ($room,  "desired-temp-until", FmtDateTime($now + $boostDuration * 60));
      readingsEndUpdate($room, 1);

      #$room->{READINGS}{"desired-temp"}{TIME} = FmtDateTime($now + $boostDuration * 60);
      #$room->{READINGS}{"desired-temp"}{VAL} = $desiredTemp + $desiredOffset;

      #my $t = $room->{READINGS}{"desired-temp"}{VAL};
      #push @{$room->{CHANGED}}, "desired-temp $t";
      #DoTrigger($name, undef);

      Log3 ($room, 4, "PWMR_Boost: $name ".
        "set desiredtemp ".$room->{READINGS}{"desired-temp"}{TIME}." ".
        $room->{READINGS}{"desired-temp"}{VAL});
        
    } else {
      Log3 ($room, 3, "PWMR_Boost: $name ".
        "($outsideTemp, $outsideMax, $deltaTemp, $desiredOffset, $boostDuration) ".
        "temp($temperaturV) desired-temp($desiredTemp) -> do nothing");
    }
  
    
  } else {
    Log3 ($room, 3, "PWMR_Boost: $name warning: no sensor.");
  }
  
  
  return undef;
}

1;

=pod
=begin html

<a name="PWMR"></a>
<h3>PWMR</h3>
<ul>

  <table>
  <tr><td>
  The PMWR module defines rooms to be used for calculation within module PWM.<br><br>
  PWM is based on Pulse Width Modulation which means valve position 70% is implemented in switching the device on for 70% and off for 30% in a given timeframe.<br>
  PWM defines a calculation unit and depents on objects based on PWMR which define the rooms to be heated.<br>
  PWMR objects calculate a desired temperature for a room based on several rules, define windows, a temperature sensor and an actor to be used to switch on/off heating.
  <br>
  </td></tr>
  </table>

  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PWMR &lt;IODev&gt; &lt;factor[,offset]&gt; &lt;tsensor[:reading:t_regexp]&gt; &lt;actor&gt;[:&lt;a_regexp_on&gt;] [&lt;window&gt;[,&lt;window&gt;:w_regexp]<br></code>

    <br>
    Define a calculation object with the following parameters:<br>
    <ul>
    <li>IODev<br>
      Reference to an object of TYPE PWM. This object will switch on/off heating.<br>
    </li>

    <li>factor[,offset]<br>
      Pulse for PWM will be calculated as ((delta-temp * factor) ** 2) + offset.<br>
      <i>offset</i> defaults to 0.11<br>
      <i>factor</i> can be used to weight rooms.<br>
    </li>

    <li>tsensor[:reading:t_regexp]<br>
      <i>tsensor</i> defines the temperature sensor for the actual room temperature.<br>
      <i>reading</i> defines the reading of the temperature sensor. Default is "temperature"<br>
      <i>t_regexp</i> defines a regular expression to be applied to the reading. Default is '([\\d\\.]*)'.<br>
    </li>

    <li>actor[:&lt;a_regexp_on&gt;]<br>
      The actor will be set to "on" of "off" to turn on/off heating.<br>
      <i>a_regexp_on</i> defines a regular expression to be applied to the state of the actor. Default is 'on". If state matches the regular expression it is handled as "on", otherwise "off"<br>
    </li>

    <li>window[,window]:w_regexp<br>
      <i>window</i> defines several window devices that can prevent heating to be turned on. 
      If STATE matches the regular expression then the desired-temp will be decreased to frost-protect temperature.<br>
      <i>w_regexp</i> defines a regular expression to be applied to the reading. Default is '.*Open.*'.<br>
    </li>

    </ul>

    <br>
    Example:<br>
    <br>
    <code>define roomKitchen PWMR fh 1,0 tempKitchen relaisKitchen</code><br>
    <code>define roomKitchen PWMR fh 1,0 tempKitchen relaisKitchen windowKitchen1,windowKitchen2</code><br>
    <code>define roomKitchen PWMR fh 1,0 tempKitchen relaisKitchen windowKitchen1,windowKitchen2:.*Open.*</code><br>
    <br>
       

  </ul>
  <br>

  <b>Set </b>
  <ul>
    <li>factor<br>
        Temporary change of parameter <i>factor</i>.
        </li><br>

    <li>actor<br>
        Set the actor state for this room to <i>on</i> or <i>off</i>. This is only a temporary change that will be overwritten by PWM object.
        </li><br>

    <li>desired-temp<br>
        If <i>desired-temp</i> is automatically calculated (attribute <i>autoCalcTemp</i> not set or 1) then the desired temperature is set for a defined time.<br>
        Default for this period is 60 minutes, but it can be changed by attribute <i>autoCalcTemp</i>.<br>
        If <i>desired-temp</i> is not automatically calculated (attribute <i>autoCalcTemp</i> is 0) then this will set the actual target temperature.<br>
        </li><br>

    <li>manualTempDuration<br>
        Define the period how long <i>desired-temp</i> manually set will be valid. Default is 60 Minutes.<br>
        </li><br>

    <li>interval<br>
        Temporary change <i>INTERVAL</i> which defines how often <i>desired-temp</i> is calculated in autoCalcMode. Default is 300 seconds (5:00 Minutes).
        </li><br>

  </ul>

  <br>

  <b>Attributes</b>
  <ul>
    <li>frostProtect<br>
        Switch on (1) of off (0) frostProtectMode. <i>desired-temp</i> will be set to <i>tempFrostProtect</i> in autoCalcMode.
        </li><br>

    <li>autoCalcTemp<br>
        Switch on (1) of off (0) autoCalcMode. <i>desired-temp</i> will be set based on the below temperatures and rules in autoCalcMode.
        </li><br>

    <li>tempDay<br>
        Define day temperature. This will be referenced as "D" in the rules.
        </li><br>

    <li>tempNight<br>
        Define night temperature. This will be referenced as "N" in the rules.
        </li><br>

    <li>tempCosy<br>
        Define cosy temperature. This will be referenced as "C" in the rules.
        </li><br>

    <li>tempEnergy<br>
        Define energy saving temperature. This will be referenced as "E" in the rules.
        </li><br>

    <li>tempFrostProtect<br>
        Define temperature for frostProtectMode. See also <i>frostProtect</i>.
        </li><br>

    <li>tempRule1 ... tempRule5<br>
        Rule to calculate the <i>desired-temp</i> in autoCalcMode.<br>
        Format is: &lt;weekday&gt;[-&lt;weekday] &lt;time&gt;,&lt;temperatureSelector&gt;<br>
        weekday is one of Mo,Di,Mi,Do,Fr,Sa,So<br>
        time is in format hh:mm, e.g. 7:00 or 07:00<br>
        temperatureSelector is one of D,N,C,E<br>
        <br>
        Predefined are:<br>
        tempRule1: Mo-Fr 6:00,D 22:00,N<br>
        tempRule2: Sa-So 8:00,D 22:00,N<br>
        This results in tempDay 6:00-22:00 from Monday to Friday and tempNight outside this time window.<br>
        </li><br>

  </ul>
  <br>
</ul>

=end html
=cut

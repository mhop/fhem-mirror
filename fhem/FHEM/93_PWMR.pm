#
#
# 93_PWMR.pm
# written by Andreas Goebel 2012-07-25
# e-mail: ag at goebel-it dot de
#
##############################################
# $Id$ 
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
# 17.11.15 GA add ReadRoom will now set a reading named temperature containing the last temperature used for calculation
# 18.11.15 GA add adjusted energyusedp to be in percent. Now it can be used in Tablet-UI as valve-position
# 19.11.15 GA fix move actorState to readings
# 22.11.15 GA fix rules on wednesday are now possible (thanks to Skusi)
# 22.11.15 GA fix error handling in SetRoom (thanks to cobra112)
# 30.11.15 GA fix set reading of desired-temp-used to frost_protect if window is opened
# 30.11.15 GA add call PWMR_Attr in PWMR_Define if already some attributes are defined
# 26.01.16 GA fix don't call AssignIoPort
# 26.01.16 GA fix assign IODev as reference to that hash (otherwise xmllist will crash fhem)
# 26.01.16 GA add implementation of PID regulation
# 27.01.16 GA add attribute desiredTempFrom to take desiredTemp from another object
# 04.02.16 GA add DLookBackCnt, buffer holding previouse temperatures used for PID D-Part calculation
# 08.02.16 GA add ILookBackCnt, buffer holding previouse temperatures used for PID I-Part calculation
# 08.02.16 GA add valueFormat attribute
# 29.06.16 GA add "set frostProtect on|off"
# 16.08.16 GA add event-min-interval
# 23.09.16 GA fix changes on commandref based on suggestions from user "sledge"
# 28.09.16 GA add readings for tempRules (single reading for Mo to So)
# 04.10.16 GA fix adjust readings for tempRules if temperature changes
# 11.10.16 GA fix delete log entries for PWMR_NormalizeRules
# 17.10.16 GA fix attribute tempFrostProtect is now evaluated
# 16.11.16 GA add display time until in state if "ManualSetUntil"
# 16.11.16 GA fix format desired-temp with one digit after the decimal point
# 17.11.16 GA add internals for configuration parameters: p_factor, p_tsensor, p_actor, p_window, p_pid
# 11.12.16 GA add alternative PID calculation, selectable by usePID=2, implementation from user Albatros_
# 14.12.16 GA fix adjust rounding of PVal and newpulsePID
# 14.12.16 GA fix supply DBuffer with delta temps for usePID=2 calculation
# 14.12.16 GA add implement get previousTemps
# 01.08.17 GA add documentation for attribute disable
# 27.12.17 GA add handle "off" as c_tempFrostProtect and "on" as c_tempC in getDesiredTempFrom (valid form Homematic)
# 31.01.18 GA add support for stateFormat
# 08.02.18 GA fix PID_I_previousTemps was shortened to c_PID_DLookBackCnt instead of c_PID_ILookBackCnt in define


# module for PWM (Pulse Width Modulation) calculation
# this module defines a room for calculation 
# it is used by a PWM object 
# reference to the PWM object is via IODev
# PWMR object defines:
#  IODev: reference to PWM
#  factor (also used in Pulse calculation): 
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
   "mi"  => 3,
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
sub PWMR_valueFormat(@);

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

  $hash->{AttrList}  = "disable:1,0 loglevel:0,1,2,3,4,5 ".
			"frostProtect:0,1 ".
			"autoCalcTemp:0,1 ".
			"desiredTempFrom ".
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
			"valueFormat:textField-long ".
 			" ".$readingFnAttributes;

}

sub
PWMR_getDesiredTempFrom(@)
{
      my ($hash, $dt, $d_reading, $d_regexpTemp) = @_; 
      my $newTemp;

      my $d_readingVal  = defined($dt->{READINGS}{$d_reading}{VAL}) ? $dt->{READINGS}{$d_reading}{VAL} : "undef"; 

      my $val           = $d_readingVal;
      $val              =~ /$d_regexpTemp/;
 
      if (defined($1)) { 
        $newTemp  = $1;
        Log3 ($hash, 4, "PWMR_getDesiredTempFrom $hash->{NAME}: from $dt->{NAME} reading($d_reading) VAL($d_readingVal) regexp($d_regexpTemp) regexpVal($val)");

      } else { # regexp does not match

        if ($val =~ /^on$/) {
          $newTemp = $hash->{c_tempC};
          Log3 ($hash, 4, "PWMR_getDesiredTempFrom $hash->{NAME}: from $dt->{NAME} reading($d_reading) VAL($d_readingVal) regexp($d_regexpTemp) regexpVal($val) set to 30");

        } elsif ( $val =~ /^off$/ ) {

          $newTemp = $hash->{c_tempFrostProtect};
          Log3 ($hash, 4, "PWMR_getDesiredTempFrom $hash->{NAME}: from $dt->{NAME} reading($d_reading) VAL($d_readingVal) regexp($d_regexpTemp) regexpVal($val) set to frostProtect");
        } else {

          $newTemp = $hash->{c_tempFrostProtect};
          Log3 ($hash, 4, "PWMR_getDesiredTempFrom $hash->{NAME}: from $dt->{NAME} reading($d_reading) VAL($d_readingVal) regexp($d_regexpTemp) regexpVal($val) set to frostProtect");
        }

      }

      Log3 ($hash, 4, "PWMR_getDesiredTempFrom $hash->{NAME}: from $dt->{NAME} reading($d_reading) VAL($d_readingVal) regexp($d_regexpTemp) regexpVal($val)");

      return ($newTemp);

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
        return undef;
      }
      else
      {
        readingsSingleUpdate ($hash,  "desired-temp-until", "no", 1);
        Log3 ($hash, 4, "PWMR_CalcDesiredTemp $name: calc desired-temp");
      }
    }
  }

  ####################
  # frost protection

  if ($hash->{c_frostProtect} > 0) {

    if ($hash->{READINGS}{"desired-temp"}{VAL} != $hash->{c_tempFrostProtect}
        or substr(TimeNow(),1,8) ne substr($hash->{READINGS}{"desired-temp"}{TIME},1,8)) {
      readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%.01f", $hash->{c_tempFrostProtect}), 1);
    } else {
      readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%.01f", $hash->{c_tempFrostProtect}), 0);
    }

    #$hash->{READINGS}{"desired-tem"}{TIME} = TimeNow();
    #$hash->{READINGS}{"desired-temp"}{VAL} = $hash->{c_tempFrostProtect};

    #push @{$hash->{CHANGED}}, "desired-temp $hash->{c_tempFrostProtect}";
    #DoTrigger($name, undef);
 
    #$hash->{STATE}     = "FrostProtect";
    readingsSingleUpdate ($hash,  "state", "FrostProtect", 1);
    return undef;
  }

  ####################
  # rule based calculation

  if ($hash->{c_autoCalcTemp} > 0 ) {
    if ($hash->{c_desiredTempFrom} eq "") {

      #$hash->{STATE}     = "Calculating";
      readingsSingleUpdate ($hash,  "state", "Calculating", 1);
  
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
                 
                if ($hash->{READINGS}{"desired-temp"}{VAL} != $temperature 
                    or substr(TimeNow(),1,8) ne substr($hash->{READINGS}{"desired-temp"}{TIME},1,8)) {
                  readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%.01f", $temperature), 1);
                } else {
                  readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%.01f", $temperature), 0);
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
              readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%.01f", $newTemp), 1);
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
    } else { # $hash->{c_desiredTempFrom} is set
      #$hash->{STATE}     = "From $hash->{d_name}";
      readingsSingleUpdate ($hash,  "state", "From $hash->{d_name}", 1);

      my $newTemp = PWMR_getDesiredTempFrom ($hash, $defs{$hash->{d_name}}, $hash->{d_reading}, $hash->{d_regexpTemp});

      if ($hash->{READINGS}{"desired-temp"}{VAL} != $newTemp 
         or substr(TimeNow(),1,8) ne substr($hash->{READINGS}{"desired-temp"}{TIME},1,8)) {
           readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%.01f", $newTemp), 1);
      } else {
         readingsSingleUpdate ($hash,  "desired-temp", sprintf ("%0.1f", $newTemp), 0);
      }
  
    }
  } else {
    #$hash->{STATE}     = "Manual";
    readingsSingleUpdate ($hash,  "state", "Manual", 1);
  }

  #DoTrigger($name, undef);
  return undef;

}

###################################
sub
PWMR_Get($@)
{
  my ($hash, @a) = @_;

  my $u = "Unknown argument $a[1], choose one of previousTemps";
  return $u if ($a[1] eq "?");

  return "argument is missing" if(int(@a) != 2);

  if ($a[1] eq "previousTemps") {
    my $msg = "";
    $msg .= "IBuffer: ".join (" ", @{$hash->{helper}{PID_I_previousTemps}})."\n" if (defined ($hash->{helper}{PID_I_previousTemps}));
    $msg .= "DBuffer: ".join (" ", @{$hash->{helper}{PID_D_previousTemps}})."\n" if (defined ($hash->{helper}{PID_D_previousTemps}));

    return $msg
  }


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

  my $desiredTempString = "";
  if (defined($hash->{READINGS}{"desired-temp"}{VAL}) 
    and ($hash->{READINGS}{"desired-temp"}{VAL} < 6 or $hash->{READINGS}{"desired-temp"}{VAL} > 30)) {
    $desiredTempString = $hash->{READINGS}{"desired-temp"}{VAL}.",";
  }


  my @list = map { ($_.".0", $_+0.5) } (6..29);
  my $valList = join (",", @list);
  $valList .= ",30.0";
  #my $u = "Unknown argument $a[1], choose one of factor actor:off,on desired-temp:knob,min:6,max:26,step:0.5,linecap:round interval manualTempDuration:slider,60,60,600";
  #my $u = "Unknown argument $a[1], choose one of factor actor:off,on desired-temp:uzsuDropDown:$valList interval manualTempDuration:slider,60,60,600";
  my $u = "Unknown argument $a[1], choose one of factor actor:off,on desired-temp:$desiredTempString$valList interval manualTempDuration:slider,60,60,600 frostProtect:off,on";

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
    if ( $val < 0 || $val > 30 ) {
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
    readingsBulkUpdate ($hash,  "desired-temp", sprintf ("%.01f", $a[2]));
    if ($hash->{c_autoCalcTemp} == 0) {
      #$hash->{STATE}     = "Manual";
      readingsBulkUpdate ($hash,  "state", "Manual");
    } else {
      #$hash->{STATE}     = "ManualSetUntil ".FmtTime($now + $duration);
      readingsBulkUpdate ($hash,  "state", "ManualSetUntil ".FmtTime($now + $duration));
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
  # frostProtect 

  if ( $cmd eq "frostProtect" ) {
    my $val = $a[2];
    if ( $val eq "on" ) {
     $hash->{c_frostProtect} = 1;
      $attr{$name}{frostProtect} = 1;
      return undef;
    } elsif ( $val eq "off" ) {
      $hash->{c_frostProtect} = 0;
      $attr{$name}{frostProtect} = 0;
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

  return "syntax: define <name> PWMR <IODev> <factor[,offset]> <tsensor[:reading[:t_regexp]]> <actor>[:<a_regexp_on>] [<window|dummy>[,<window>][:<w_regexp>]] ".
         "[<usePID=0>]|".
         "[<usePID=1>:<PFactor>:<IFactor>[,<ILookBackCnt>]:<DFactor>[,<DLookBackCnt>]]|".
         "[<usePID=2>:<PFactor>:<IFactor>:<DFactor>[,<DLookBackCnt>]]"
    if(int(@a) < 6 || int(@a) > 9);

  my $iodevname = $a[2];
  my $factor  = ((int(@a) > 2) ? $a[3] : 0.8);
  my $tsensor = ((int(@a) > 3) ? $a[4] : "");
  my $actor   = ((int(@a) > 4) ? $a[5] : "");
  my $window  = ((int(@a) > 6) ? $a[6] : "");
  my $pid     = ((int(@a) > 7) ? $a[7] : "");

  $hash->{TEMPSENSOR}         = $tsensor;
  $hash->{ACTOR}              = $actor;
  $hash->{WINDOW}             = ($window eq "dummy" ? "" : $window);

  # definitions used in the past moved to c_factor and c_foffset
  delete ($hash->{FACTOR})                  if (defined (($hash->{FACTOR})));
  delete ($hash->{FOFFSET})                 if (defined (($hash->{FOFFSET})));

  $hash->{c_desiredTempFrom}  = "";

  $hash->{p_factor}           = $factor;
  $hash->{p_tsensor}          = $tsensor;
  $hash->{p_actor}            = $actor;
  $hash->{p_window}           = $window;
  $hash->{p_pid}              = $pid;
  
  #$hash->{helper}{cycletime}  = 0;

  if ( !$iodevname ) {
    return "unknown device $iodevname";
  }

  if ( $defs{$iodevname}->{TYPE} ne "PWM" ) {
    return "wrong type of $iodevname (not PWM)";
  }

  #$hash->{IODev} = $iodev;
  $hash->{IODev} = $defs{$iodevname};
  
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
  # check pid definition

  my ($usePID, $PFactor, $IFactorTmp, $DFactorTmp) = split (":", $pid);

  $IFactorTmp = "" unless (defined ($IFactorTmp));
  $DFactorTmp = "" unless (defined ($DFactorTmp));

  my ($IFactor, $ILookBackCnt) = split (",", $IFactorTmp);
  my ($DFactor, $DLookBackCnt) = split (",", $DFactorTmp);

  $hash->{c_PID_useit}        = !defined($usePID)  ?       0 : $usePID;

  if ($hash->{c_PID_useit} eq 0) {

    # simple p-factor calculation will be done

    delete ($hash->{READINGS}{PID_PVal})          if (defined($hash->{READINGS}{PID_PVal}));
    delete ($hash->{READINGS}{PID_IVal})          if (defined($hash->{READINGS}{PID_IVal}));
    delete ($hash->{READINGS}{PID_DVal})          if (defined($hash->{READINGS}{PID_DVal}));
    delete ($hash->{READINGS}{PID_PWMPulse})      if (defined($hash->{READINGS}{PID_PWMPulse}));
    delete ($hash->{READINGS}{PID_PWMOnTime})     if (defined($hash->{READINGS}{PID_PWMOnTime}));
 
    delete ($hash->{helper}{PID_I_previousTemps}) if (defined (($hash->{helper}{PID_I_previousTemps})));
    delete ($hash->{helper}{PID_D_previousTemps}) if (defined (($hash->{helper}{PID_D_previousTemps})));

    delete ($hash->{h_PID_I_previousTemps})       if (defined (($hash->{h_PID_I_previousTemps})));
    delete ($hash->{h_PID_D_previousTemps})       if (defined (($hash->{h_PID_D_previousTemps})));

    delete ($hash->{c_PID_PFactor})               if (defined (($hash->{c_PID_PFactor})));
    delete ($hash->{c_PID_IFactor})               if (defined (($hash->{c_PID_IFactor})));
    delete ($hash->{c_PID_DFactor})               if (defined (($hash->{c_PID_DFactor})));

    delete ($hash->{c_PID_ILookBackCnt})          if (defined (($hash->{c_PID_ILookBackCnt})));
    delete ($hash->{c_PID_DLookBackCnt})          if (defined (($hash->{c_PID_DLookBackCnt})));

    delete ($hash->{h_deltaTemp})                 if (defined($hash->{h_deltaTemp}));
    delete ($hash->{h_deltaTemp_D})               if (defined($hash->{h_deltaTemp_D}));

    my ($f, $o) = split (",", $factor);
    $f = 1    unless (defined ($f));
    $o = 0.11 unless (defined ($o));       # if cycletime is 900 then this increases the on-time by 1:39 (=99 seconds)
 

    $hash->{c_factor}             = $f;		# pulse is calculated using the below formular
    $hash->{c_foffset}            = $o;           # ( $deltaTemp * $c_factor) ** 2) + $c_foffset

  } elsif ($hash->{c_PID_useit} eq 1) {

    delete ($hash->{READINGS}{PWMPulse})      if (defined($hash->{READINGS}{PWMPulse}));
    delete ($hash->{READINGS}{PWMOnTime})     if (defined($hash->{READINGS}{PWMOnTime}));

    delete ($hash->{h_PID_I_previousTemps})   if (defined (($hash->{h_PID_I_previousTemps})));
    delete ($hash->{h_PID_D_previousTemps})   if (defined (($hash->{h_PID_D_previousTemps})));

    delete ($hash->{c_factor})                  if (defined (($hash->{c_factor})));
    delete ($hash->{c_foffset})                 if (defined (($hash->{c_foffset})));

    $hash->{c_PID_PFactor}      = !defined($PFactor) ?      0.8 : $PFactor;
    $hash->{c_PID_IFactor}      = !defined($IFactor) ?      0.3 : $IFactor;
    $hash->{c_PID_DFactor}      = !defined($DFactor) ?      0.5 : $DFactor;

    $hash->{c_PID_ILookBackCnt} = !defined($ILookBackCnt) ?   5 : $ILookBackCnt;
    $hash->{c_PID_DLookBackCnt} = !defined($DLookBackCnt) ?  10 : $DLookBackCnt;

    $hash->{h_deltaTemp}      = 0 unless defined ($hash->{h_deltaTemp});
    $hash->{h_deltaTemp_D}    = 0 unless defined ($hash->{h_deltaTemp_D});

    ### I-Factor

    # initialize if not yet done 
    $hash->{helper}{PID_I_previousTemps} = [] unless defined (($hash->{helper}{PID_I_previousTemps}));

    # shorter reference to array
    my $IBuffer = $hash->{helper}{PID_I_previousTemps};
    my $Icnt = ( @{$IBuffer} ); # or scalar @{$IBuffer}

    # reference
    #Log3 ($hash, 3, "org reference IBuffer is $hash->{helper}{PID_I_previousTemps} short is $IBuffer, cnt is ". scalar @{$IBuffer}." (starting from 0)");
    Log3 ($hash, 4, "content of IBuffer is @{$IBuffer}");

    # cut Buffer if it is too large
    while (scalar @{$IBuffer} > $hash->{c_PID_ILookBackCnt}) {
      my $v = shift @{$IBuffer};
    }

    ### D-Factor

    # initialize if not yet done 
    $hash->{helper}{PID_D_previousTemps} = [] unless defined (($hash->{helper}{PID_D_previousTemps}));

    # shorter reference to array
    my $DBuffer = $hash->{helper}{PID_D_previousTemps};
    my $Dcnt = ( @{$DBuffer} ); # or scalar @{$DBuffer}

    # reference
    #Log3 ($hash, 3, "org reference DBuffer is $hash->{helper}{PID_D_previousTemps} short is $DBuffer, cnt is ". scalar @{$DBuffer}." (starting from 0)");
    Log3 ($hash, 4, "content of DBuffer is @{$DBuffer}");

    # cut Buffer if it is too large
    while (scalar @{$DBuffer} > $hash->{c_PID_DLookBackCnt}) {
      my $v = shift @{$DBuffer};
    }

  } else {

    # usePID >= 2

    delete ($hash->{READINGS}{PWMPulse})      if (defined($hash->{READINGS}{PWMPulse}));
    delete ($hash->{READINGS}{PWMOnTime})     if (defined($hash->{READINGS}{PWMOnTime}));

    delete ($hash->{h_PID_I_previousTemps})   if (defined (($hash->{h_PID_I_previousTemps})));
    delete ($hash->{h_PID_D_previousTemps})   if (defined (($hash->{h_PID_D_previousTemps})));

    delete ($hash->{c_factor})                  if (defined (($hash->{c_factor})));
    delete ($hash->{c_foffset})                 if (defined (($hash->{c_foffset})));

    $hash->{c_PID_PFactor}      = !defined($PFactor) ?       0.8  : $PFactor;
    $hash->{c_PID_IFactor}      = !defined($IFactor) ?       0.01 : $IFactor;
    $hash->{c_PID_DFactor}      = !defined($DFactor) ?       0    : $DFactor;

    $hash->{c_PID_DLookBackCnt} = !defined($DLookBackCnt) ?  10   : $DLookBackCnt;

    delete ($hash->{helper}{PID_I_previousTemps}) if (defined (($hash->{helper}{PID_I_previousTemps})));
    #delete ($hash->{helper}{PID_D_previousTemps}) if (defined (($hash->{helper}{PID_D_previousTemps})));

    delete ($hash->{c_PID_ILookBackCnt})          if (defined ($hash->{c_PID_ILookBackCnt}));
    #delete ($hash->{c_PID_DLookBackCnt})          if (defined ($hash->{c_PID_DLookBackCnt}));

    #delete ($hash->{h_deltaTemp})                 if (defined ($hash->{h_deltaTemp}));
    #delete ($hash->{h_deltaTemp_D})               if (defined ($hash->{h_deltaTemp_D}));

    ### D-Factor

    # initialize if not yet done 
    $hash->{helper}{PID_D_previousTemps} = [] unless defined (($hash->{helper}{PID_D_previousTemps}));

    # shorter reference to array
    my $DBuffer = $hash->{helper}{PID_D_previousTemps};
    my $Dcnt = ( @{$DBuffer} ); # or scalar @{$DBuffer}

    # reference
    #Log3 ($hash, 3, "org reference DBuffer is $hash->{helper}{PID_D_previousTemps} short is $DBuffer, cnt is ". scalar @{$DBuffer}." (starting from 0)");
    Log3 ($hash, 4, "content of DBuffer is @{$DBuffer}");

    # cut Buffer if it is too large
    while (scalar @{$DBuffer} > $hash->{c_PID_DLookBackCnt}) {
      my $v = shift @{$DBuffer};
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
    $t_regexp = '([\\d\\.]+)'
  }
  $hash->{t_regexp}    = $t_regexp;

  ##########
  # check actor

  my ($tactor, $a_regexp_on) = split (":", $actor, 2);

  $a_regexp_on = "on" unless defined ($a_regexp_on);

  $tactor              =~ s/dummy//;

  if (!$defs{$tactor} && $tactor ne "dummy")
  {
    my $msg = "$name: Unknown actor device $tactor specified";
    Log3 ($hash, 3, "PWMR_Define $msg");
    return $msg;
  }

  $hash->{actor}       = $tactor;
  $hash->{a_regexp_on} = $a_regexp_on;
  #$hash->{actorState}  = "unknown";

  readingsSingleUpdate ($hash,  "actorState", "unknown", 0);

  #$hash->{STATE}       = "Initialized";
  readingsSingleUpdate ($hash,  "state", "Initialized", 1);

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

  #AssignIoPort($hash);

  # if attributes already defined then recall set for them
  foreach my $oneattr (sort keys %{$attr{$name}})
  {
    PWMR_Attr ("set", $name, $oneattr, $attr{$name}{$oneattr});
  }

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
  readingsBulkUpdate ($room,  "energyusedp", sprintf ("%.1f", ($energyused =~ tr/1//) /30*100));
  
  if ($newState eq "") {
    readingsEndUpdate($room, 1);
    return;
  }

  if ($room->{actor})
  {
    my $ret = fhem sprintf ("set %s %s", $room->{actor}, $newState);
    if (!defined($ret)) {    # sucessfull
      Log3 ($room, 2, "PWMR_SetRoom $room->{NAME}: set $room->{actor} $newState");
       
      #$room->{actorState}                 = $newState;

      readingsBulkUpdate ($room,  "actorState", $newState);
      readingsBulkUpdate ($room,  "lastswitch", time());
      readingsEndUpdate($room, 1);

      push @{$room->{CHANGED}}, "actor $newState";
      DoTrigger($name, undef);

    } else {
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

  my ($temperaturV, $actorV, $factor, $oldpulse, $newpulse, $newpulsePID, $prevswitchtime, $windowV) = 
    (99, "off", 0, 0, 0, 0, 0, 0);

  #Log3 ($room, 4, "PWMR_ReadRoom $name <$room->{t_sensor}> <$room->{actor}>");

  if ($room->{t_sensor})
  {
    my $sensor   =  $room->{t_sensor};
    my $reading  =  $room->{t_reading};
    my $t_regexp =  $room->{t_regexp};

    $temperaturV =  $defs{$sensor}->{READINGS}{$reading}{VAL};
    $temperaturT =  $defs{$sensor}->{READINGS}{$reading}{TIME};

    $temperaturV =~ s/$t_regexp/$1/;

    $temperaturV = PWMR_valueFormat ($room, "temperature", $temperaturV);
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
      #$actorV = $room->{actorState};
      $actorV = $room->{READINGS}{actorState};
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

  readingsBeginUpdate ($room);
  
  if ($room->{c_PID_useit} eq 0) {

    # simple P-Factor calculation

    my $deltaTemp    = maxNum (0, $desiredTemp - $temperaturV);
  
    $factor          = $room->{c_factor};
    my $factoroffset = $room->{c_foffset};
  
    $newpulse        = minNum ($MaxPulse,  (( $deltaTemp * $factor) ** 2) + $factoroffset); # default 85% max ontime
    $newpulse        = sprintf ("%.2f", $newpulse);

  
    my $PWMPulse     = $newpulse * 100;
    my $PWMOnTime    =  sprintf ("%02s:%02s", int ($newpulse * $cycletime / 60), ($newpulse * $cycletime) % 60);

    my $iodev = $room->{IODev};
    if ($newpulse * $iodev->{CYCLETIME} < $iodev->{MINONOFFTIME}) {
      $PWMPulse = 0;
      $PWMOnTime = "00:00";
    }

    readingsBulkUpdate ($room,  "desired-temp-used", $desiredTemp);
    readingsBulkUpdate ($room,  "PWMOnTime", $PWMOnTime);
    readingsBulkUpdate ($room,  "PWMPulse", $PWMPulse);
    readingsBulkUpdate ($room,  "temperature", $temperaturV);

    Log3 ($room, 4, "PWMR_ReadRoom $name: desT($desiredTemp), actT($temperaturV von($temperaturT)), state($actorV)");
    Log3 ($room, 4, "PWMR_ReadRoom $name: newpulse($newpulse/$PWMOnTime), oldpulse($oldpulse), lastSW($prevswitchtime = $prevswitchtimeT), window($windowV)");

  } elsif ($room->{c_PID_useit} eq 1) {

    ### PID calculation

    my $DBuffer = $room->{helper}{PID_D_previousTemps};
    push @{$DBuffer}, $temperaturV;

    my $IBuffer = $room->{helper}{PID_I_previousTemps};
    push @{$IBuffer}, $temperaturV;

    # cut I-Buffer if it is too large
    while (scalar @{$IBuffer} > $room->{c_PID_ILookBackCnt}) {
      my $v = shift @{$IBuffer};
      #Log3 ($room, 3, "shift $v from IBuffer");
    }
    #Log3 ($room, 3, "IBuffer contains ".scalar @{$IBuffer}." elements");

    # cut D-Buffer if it is too large
    while (scalar @{$DBuffer} > $room->{c_PID_DLookBackCnt}) {
      my $v = shift @{$DBuffer};
      #Log3 ($room, 3, "shift $v from DBuffer");
    }
    #Log3 ($room, 3, "DBuffer contains ".scalar @{$DBuffer}." elements");

    # helper for previousTemps
    #$room->{h_PID_I_previousTemps} = join (" ", @{$IBuffer});
    #$room->{h_PID_D_previousTemps} = join (" ", @{$DBuffer});


    my $deltaTempPID = $desiredTemp - $temperaturV;
    $room->{h_deltaTemp}   = sprintf ("%.1f", -1 * $deltaTempPID);
    $room->{h_deltaTemp_D} = sprintf ("%.1f", -1 * ($desiredTemp - $DBuffer->[0]));

    my $ISum = 0;
    foreach my $t (@{$IBuffer}) {
      $ISum += ($desiredTemp - $t);
    }
    $ISum = $ISum;

  
    my $PVal = $room->{c_PID_PFactor} * maxNum (0, $deltaTempPID);
    my $IVal = $room->{c_PID_IFactor} * $ISum;
    my $DVal = $room->{c_PID_DFactor} * ($room->{h_deltaTemp_D} - $room->{h_deltaTemp});

    $PVal    = minNum (1, sprintf ("%.2f", $PVal));
    $IVal    = minNum (1, sprintf ("%.2f", $IVal));
    $DVal    = minNum (1, sprintf ("%.2f", $DVal));

    $IVal    = maxNum (-1, $IVal);

    my $newpulsePID  = ($PVal + $IVal + $DVal);
    $newpulsePID     = minNum ($MaxPulse, sprintf ("%.2f", $newpulsePID));
    $newpulsePID     = maxNum (0,         sprintf ("%.2f", $newpulsePID));

    my $PWMPulsePID  = $newpulsePID * 100;
    my $PWMOnTimePID =  sprintf ("%02s:%02s", int ($newpulsePID * $cycletime / 60), ($newpulsePID * $cycletime) % 60);


    my $iodev = $room->{IODev};
    if ($PWMPulsePID * $iodev->{CYCLETIME} < $iodev->{MINONOFFTIME}) {
      $PWMPulsePID = 0;
      $PWMOnTimePID = "00:00";
    }

    readingsBulkUpdate ($room,  "desired-temp-used", $desiredTemp);
    readingsBulkUpdate ($room,  "temperature", $temperaturV);

    #readingsBulkUpdate ($room,  "PWMOnTime", $PWMOnTimePID);
    #readingsBulkUpdate ($room,  "PWMPulse", $PWMPulsePID);

    readingsBulkUpdate ($room,  "PID_PVal", $PVal);
    readingsBulkUpdate ($room,  "PID_IVal", $IVal);
    readingsBulkUpdate ($room,  "PID_DVal", $DVal);
    readingsBulkUpdate ($room,  "PID_PWMPulse", $PWMPulsePID);
    readingsBulkUpdate ($room,  "PID_PWMOnTime", $PWMOnTimePID);

    Log3 ($room, 4, "PWMR_ReadRoom $name: desT($desiredTemp), actT($temperaturV von($temperaturT)), state($actorV)");
    Log3 ($room, 4, "PWMR_ReadRoom $name: newpulse($newpulsePID/$PWMOnTimePID), oldpulse($oldpulse), lastSW($prevswitchtime = $prevswitchtimeT), window($windowV)");

    $newpulse = $newpulsePID;

  } elsif($room->{c_PID_useit} >= 2) {

    my $DBuffer = $room->{helper}{PID_D_previousTemps};
    push @{$DBuffer}, $temperaturV;

    # cut D-Buffer if it is too large
    while (scalar @{$DBuffer} > $room->{c_PID_DLookBackCnt}) {
      my $v = shift @{$DBuffer};
      #Log3 ($room, 3, "shift $v from DBuffer");
    }
    #Log3 ($room, 3, "DBuffer contains ".scalar @{$DBuffer}." elements");

    my $deltaTempPID = $desiredTemp - $temperaturV;
    $room->{h_deltaTemp}   = sprintf ("%.1f", -1 * $deltaTempPID);
    $room->{h_deltaTemp_D} = sprintf ("%.1f", -1 * ($desiredTemp - $DBuffer->[0]));

    #calculate IValue
    my $ISum = $room->{READINGS}{"PID_IVal"}{VAL};
    $ISum = $ISum + ($deltaTempPID * $room->{c_PID_IFactor});
 
    my $PVal = $room->{c_PID_PFactor} * $deltaTempPID;
    my $IVal = $ISum;
    my $DVal = $room->{c_PID_DFactor} * ($room->{h_deltaTemp_D} - $room->{h_deltaTemp});

    $PVal    = sprintf ("%.4f", $PVal);
    $IVal    = minNum (1, sprintf ("%.4f", $IVal));
    $DVal    = minNum (1, sprintf ("%.4f", $DVal));

    $IVal    = maxNum (0, $IVal);


    my $newpulsePID  = ($PVal + $IVal + $DVal);
    $newpulsePID     = minNum ($MaxPulse, sprintf ("%.2f", $newpulsePID));
    $newpulsePID     = maxNum (0,         sprintf ("%.2f", $newpulsePID));

    my $PWMPulsePID  = $newpulsePID * 100;
    my $PWMOnTimePID =  sprintf ("%02s:%02s", int ($newpulsePID * $cycletime / 60), ($newpulsePID * $cycletime) % 60);

    my $iodev = $room->{IODev};
    if ($PWMPulsePID * $iodev->{CYCLETIME} < $iodev->{MINONOFFTIME}) {
      $PWMPulsePID = 0;
      $PWMOnTimePID = "00:00";
    }

    readingsBulkUpdate ($room,  "desired-temp-used", $desiredTemp);
    readingsBulkUpdate ($room,  "temperature", $temperaturV);

    #readingsBulkUpdate ($room,  "PWMOnTime", $PWMOnTimePID);
    #readingsBulkUpdate ($room,  "PWMPulse", $PWMPulsePID);

    readingsBulkUpdate ($room,  "PID_PVal", $PVal);
    readingsBulkUpdate ($room,  "PID_IVal", $IVal);
    readingsBulkUpdate ($room,  "PID_DVal", $DVal);
    readingsBulkUpdate ($room,  "PID_PWMPulse", $PWMPulsePID);
    readingsBulkUpdate ($room,  "PID_PWMOnTime", $PWMOnTimePID);

    Log3 ($room, 4, "PWMR_ReadRoom $name: desT($desiredTemp), actT($temperaturV von($temperaturT)), state($actorV)");
    Log3 ($room, 4, "PWMR_ReadRoom $name: newpulse($newpulsePID/$PWMOnTimePID), oldpulse($oldpulse), lastSW($prevswitchtime = $prevswitchtimeT), window($windowV)");

    $newpulse = $newpulsePID;
  }

  readingsEndUpdate($room, 1);
  

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
PWMR_NormalizeRules(@)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $rule;
  my @week = ();

  #Log3 ($hash, 2, "PWMR_NormalizeRules");

  if ($hash->{c_autoCalcTemp} == 0 or $hash->{c_desiredTempFrom} ne "")
  {
    #Log3 ($hash, 2, "PWMR_NormalizeRules delete readings timer._..");
    delete ($hash->{READINGS}{timer1_Mo}) if (defined ($hash->{READINGS}{timer1_Mo}));
    delete ($hash->{READINGS}{timer2_Di}) if (defined ($hash->{READINGS}{timer2_Di}));
    delete ($hash->{READINGS}{timer3_Mi}) if (defined ($hash->{READINGS}{timer3_Mi}));
    delete ($hash->{READINGS}{timer4_Do}) if (defined ($hash->{READINGS}{timer4_Do}));
    delete ($hash->{READINGS}{timer5_Fr}) if (defined ($hash->{READINGS}{timer5_Fr}));
    delete ($hash->{READINGS}{timer6_Sa}) if (defined ($hash->{READINGS}{timer6_Sa}));
    delete ($hash->{READINGS}{timer7_So}) if (defined ($hash->{READINGS}{timer7_So}));

    return;
  }

  foreach my $var ("c_tempRule1", "c_tempRule2", "c_tempRule3", "c_tempRule4", "c_tempRule5")
  {
    $rule = $hash->{$var};
    if ($rule ne "") {              # valid rule is 1-5 0600,D 1800,C 2200,N
    Log3 ($hash, 5, "PWMR_NormalizeRules from $var: $rule");
 
      my ($day, @points) = split (" ", $rule);
      my ($dayFromNo, $dayToNo) = split ("-", $day);

      $dayFromNo = 7 if ($dayFromNo == 0);
      $dayToNo   = 7 if ($dayToNo   == 0);

      my $lastTime   = "";
      my $lastTempId = ""; 
      my $lastTemp   = ""; 
      my $ruleLong   = "";

      foreach my $step (@points) {
   
        $step =~ /^(..)(..),(.)$/;
  
        my ($actTime, $actTempId) = ($1.":".$2, $3);
   
        if ($lastTime ne "") {
          $ruleLong .= sprintf ("%s-%s,%s,%s ", $lastTime, $actTime, $lastTempId, $lastTemp);
        }
        $lastTime   = $actTime;
        $lastTempId = $actTempId;

        if ($actTempId eq "D") {
          $lastTemp   = $hash->{c_tempD};
        } elsif ($actTempId eq "E") {
          $lastTemp   = $hash->{c_tempE};
        } elsif ($actTempId eq "C") {
          $lastTemp   = $hash->{c_tempC};
        } else {
          $lastTemp   = $hash->{c_tempN};
        }

      }

      if (uc($lastTempId) ne "N") {
        $ruleLong .=  sprintf "%s-%s,%s,%s ", $lastTime, "23:59", $lastTempId, $lastTemp;
      }
      Log3 ($hash, 5, "PWMR_NormalizeRules to   $var: $dayFromNo-$dayToNo $ruleLong");

      for (my $i=1; $i<=7; $i++)
      {
        # only first rule matches

        if ($dayFromNo <= $dayToNo) {
          # rule 1 .. 5
          if ($i >= $dayFromNo and $i <= $dayToNo) {
            $week[$i] = $ruleLong if (!defined($week[$i]));
          }
        } else {
          # rule 7 .. 1
          if ($i >= $dayFromNo or $i <= $dayToNo) {
            $week[$i] = $ruleLong if (!defined($week[$i]));
          }
        }
      }
    }

  }

  # update Readings

  readingsBeginUpdate ($hash);
  readingsBulkUpdate ($hash,  "timer1_Mo", (defined($week[1]) ? $week[1] : ""));
  readingsBulkUpdate ($hash,  "timer2_Di", (defined($week[2]) ? $week[2] : ""));
  readingsBulkUpdate ($hash,  "timer3_Mi", (defined($week[3]) ? $week[3] : ""));
  readingsBulkUpdate ($hash,  "timer4_Do", (defined($week[4]) ? $week[4] : ""));
  readingsBulkUpdate ($hash,  "timer5_Fr", (defined($week[5]) ? $week[5] : ""));
  readingsBulkUpdate ($hash,  "timer6_Sa", (defined($week[6]) ? $week[6] : ""));
  readingsBulkUpdate ($hash,  "timer7_So", (defined($week[7]) ? $week[7] : ""));
  readingsEndUpdate($hash, 0);
}

sub 
PWMR_CheckTempRule(@)
{
  my ($hash, $attrname, $var, $vals) = @_;

  my $name = $hash->{NAME};
  my $valid  = "";

  my $usage = "usage: [Mo|Di|..|So[-Mo|-Di|..|-So] <zeit>,D|C|E|N [<zeit>,D|C|E|N] ]\n".
  		"e.g. Mo-Fr 6:00,D 22,N\n".
 		"or   So 10,D 23,N";
  
  Log3 ($hash, 4, "PWMR_CheckTempRule: $hash->{NAME} $var <$vals>");

  my ($day, @points) = split (" ", $vals);

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
 
  PWMR_NormalizeRules($hash);

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

  PWMR_NormalizeRules($hash);

  return undef;

}

sub 
PWMR_Attr(@)
{
  #my @a = @_;
  my ($action, $name, $attrname, $attrval) = @_;

  #my $name = $a[1];
  #my $attr = $a[2];
  #my $val  = defined ($a[3]) ? $a[3] : "";
  #my $val  = $a[3];

  my $hash = $defs{$name};
  $attrval = "" unless defined ($attrval);

  #Log3 ($hash, 2, "Attr cmd: $action, Attr $attrname value <$attrval> attr <$attr{$name}{$attrname}>");
  
  if ($action eq "del") {

    Log3 ($hash, 4, "PWMR_Attr: $name, delete $attrname");
  
    if ($attrname eq "tempRule1") {
      $hash->{c_tempRule1} = "";
      PWMR_NormalizeRules($hash);
    } elsif ($attrname eq "tempRule2") {
      $hash->{c_tempRule2} = "";
      PWMR_NormalizeRules($hash);
    } elsif ($attrname eq "tempRule3") {
      $hash->{c_tempRule3} = "";
      PWMR_NormalizeRules($hash);
    } elsif ($attrname eq "tempRule4") {
      $hash->{c_tempRule4} = "";
      PWMR_NormalizeRules($hash);
    } elsif ($attrname eq "tempRule5") {
      $hash->{c_tempRule5} = "";
      PWMR_NormalizeRules($hash);
    } elsif ($attrname eq "frostProtect") {
      $hash->{c_frostProtect} = 0;
    } elsif ($attrname eq "tempFrostProtect") {
      $hash->{c_tempFrostProtect} = 6;
    } elsif ($attrname eq "desiredTempFrom") {
      $hash->{c_desiredTempFrom} = "";
      delete($hash->{d_name});
      delete($hash->{d_reading});
      delete($hash->{d_regexpTemp});
      PWMR_NormalizeRules($hash);
    } elsif ($attrname eq "autoCalcTemp") {
      $hash->{c_autoCalcTemp} = 1;
      #$hash->{STATE}     = "Calculating";
      readingsSingleUpdate ($hash,  "state", "Calculating", 1);
      PWMR_NormalizeRules($hash);
    } 

    if ($attrname eq "valueFormat" and defined ($hash->{helper}{$attrname})) {
      delete ($hash->{helper}{$attrname});
    }

    PWMR_NormalizeRules($hash);
    return undef;
  
  }

  Log3 ($hash, 4, "PWMR_Attr: $name, $attrname, $attrval");

  if ($attrname eq "frostProtect") {                            # frostProtect  0/1
    if ($attrval eq 0 or $attrval eq 1) {
      $hash->{c_frostProtect} = $attrval;
    } elsif ($attrval eq "") {
      $hash->{c_frostProtect} = 0;
    } else {
      return "valid values are 0 or 1";
    }

  } elsif ($attrname eq "autoCalcTemp") {                       # autoCalcTemp 0/1
    if ($attrval eq 0) {
      $hash->{c_autoCalcTemp} = 0;
      #$hash->{STATE}     = "Manual";
      readingsSingleUpdate ($hash,  "state", "Manual", 1);
    } elsif ( $attrval eq 1) {
      $hash->{c_autoCalcTemp} = 1;
      #$hash->{STATE}     = "Calculating";
      readingsSingleUpdate ($hash,  "state", "Calculating", 1);
    } elsif ($attrval eq "") {
      $hash->{c_autoCalcTemp} = 1;
      #$hash->{STATE}     = "Calculating";
      readingsSingleUpdate ($hash,  "state", "Calculating", 1);
    } else {
      return "valid values are 0 or 1";
    }
    PWMR_NormalizeRules($hash);

  } elsif ($attrname eq "desiredTempFrom") {                   # desiredTempFrom
    $hash->{c_desiredTempFrom} = $attrval;

    my ( $d_name, $d_reading, $d_regexpTemp) = split (":", $attrval, 3);

    # set defaults

    $hash->{d_name}                = (defined($d_name)               ? $d_name                : "");
    $hash->{d_reading}             = (defined($d_reading)            ? $d_reading             : "desired-temp");
    $hash->{d_regexpTemp}          = (defined($d_regexpTemp)         ? $d_regexpTemp          : '(\d[\d\\.]+)');

    # check if device exist 
    unless (defined($defs{$hash->{d_name}})) {
      return "error: $hash->{d_name} does not exist.";
    }
    PWMR_NormalizeRules($hash);

  } elsif ($attrname eq "tempDay") {                           # tempDay
    return PWMR_CheckTemp($hash, "c_tempD", $attrval);

  } elsif ($attrname eq "tempNight") {                         # tempNight
    return PWMR_CheckTemp($hash, "c_tempN", $attrval);

  } elsif ($attrname eq "tempCosy") {                          # tempCosy
    return PWMR_CheckTemp($hash, "c_tempC", $attrval);

  } elsif ($attrname eq "tempEnergy") {                        # tempEnergy
    return PWMR_CheckTemp($hash, "c_tempE", $attrval);

  } elsif ($attrname eq "tempFrostProtect") {                  # tempFrostProtect
    return PWMR_CheckTemp($hash, "c_tempFrostProtect", $attrval);

  } elsif ($attrname eq "tempRule1") {                         # tempRule1
    return PWMR_CheckTempRule($hash, $attrname, "c_tempRule1", $attrval);

  } elsif ($attrname eq "tempRule2") {                         # tempRule2
    return PWMR_CheckTempRule($hash, $attrname, "c_tempRule2", $attrval);

  } elsif ($attrname eq "tempRule3") {                         # tempRule3
    return PWMR_CheckTempRule($hash, $attrname, "c_tempRule3", $attrval);

  } elsif ($attrname eq "tempRule4") {                         # tempRule4
    return PWMR_CheckTempRule($hash, $attrname, "c_tempRule4", $attrval);

  } elsif ($attrname eq "tempRule5") {                         # tempRule5
    return PWMR_CheckTempRule($hash, $attrname, "c_tempRule5", $attrval);

  }

  if ($attrname eq "valueFormat") {
    my $attrValTmp = $attrval;
    if( $attrValTmp =~ m/^{.*}$/s && $attrValTmp =~ m/=>/ && $attrValTmp !~ m/\$/ ) {
      my $av = eval $attrValTmp;
      if( $@ ) {
        Log3 ($hash->{NAME}, 3, $hash->{NAME} ." $attrname: ". $@);
      } else {
        $attrValTmp = $av if( ref($av) eq "HASH" );
      }
      $hash->{helper}{$attrname} = $attrValTmp;

      foreach my $key (keys %{$hash->{helper}{$attrname}}) {
        Log3 ($hash->{NAME}, 3, $hash->{NAME} ." $key ".$hash->{helper}{$attrname}{$key});
      }

      #return "$attrname set to $attrValTmp";

    } else {
      # if valueFormat is not verified sucessfully ... the helper is deleted (=not used)
      delete $hash->{helper}{$attrname};
    }
    return undef;
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
      readingsBulkUpdate ($room,  "desired-temp", sprintf ("%.01f", $desiredTemp + $desiredOffset));
      readingsBulkUpdate ($room,  "desired-temp-until", FmtDateTime($now + $boostDuration * 60));
      readingsEndUpdate($room, 1);

      #$room->{READINGS}{"desired-temp"}{TIME} = FmtDateTime($now + $boostDuration * 60);
      #$room->{READINGS}{"desired-temp"}{VAL} = $desiredTemp + $desiredOffset;

      #my $t = $room->{READINGS}{"desired-temp"}{VAL};
      #push @{$room->{CHANGED}}, "desired-temp $t";
      #DoTrigger($name, undef);

      Log3 ($room, 4, "PWMR_Boost: $name ".
        "set desired-temp ".$room->{READINGS}{"desired-temp"}{TIME}." for ".
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

sub 
PWMR_valueFormat(@)
{
  my ($hash, $reading, $value) = @_;

  return $value unless (defined ($reading));
 
  if (ref($hash->{helper}{valueFormat}) eq 'HASH')
  {
     
    if (exists($hash->{helper}{valueFormat}->{$reading})) {

      my $vf = $hash->{helper}{valueFormat}->{$reading};
      return sprintf ("$vf", $value);
    }
  }

  return $value;

}

1;

=pod
=item device
=item summary Device for room temperature control using PWM. See also 94_PWM.pm 
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
    <code>define &lt;name&gt; PWMR &lt;IODev&gt; &lt;factor[,offset]&gt; &lt;tsensor[:reading:[t_regexp]]&gt; &lt;actor&gt;[:&lt;a_regexp_on&gt;] [&lt;window|dummy&gt;[,&lt;window&gt;[:&lt;w_regexp&gt;]] [ &lt;usePID=0&gt; | &lt;usePID=1&gt;:&lt;PFactor&gt;:&lt;IFactor&gt;[,&lt;ILookBackCnt&gt;]:&lt;DFactor&gt;[,&lt;DLookBackCnt&gt;] | &lt;usePID=2&gt;:&lt;PFactor&gt;:&lt;IFactor&gt;:&lt;DFactor&gt[,&lt;DLookBackCnt&gt;] ] <br></code>

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

    <li>tsensor[:reading[:t_regexp]]<br>
      <i>tsensor</i> defines the temperature sensor for the actual room temperature.<br>
      <i>reading</i> defines the reading of the temperature sensor. Default is "temperature"<br>
      <i>t_regexp</i> defines a regular expression to be applied to the reading. Default is '(\d[\d\.]+)'.<br>
    </li>

    <li>actor[:&lt;a_regexp_on&gt;]<br>
      The actor will be set to "on" of "off" to turn on/off heating.<br>
      <i>a_regexp_on</i> defines a regular expression to be applied to the state of the actor. Default is 'on". If state matches the regular expression it is handled as "on", otherwise "off"<br>
    </li>

    <li>&lt;window|dummy&gt;[,&lt;window&gt;[:&lt;w_regexp&gt;]<br>
      <i>window</i> defines several window devices that can prevent heating to be turned on.<br>
      If STATE matches the regular expression then the desired-temp will be decreased to frost-protect temperature.<br>
      'dummy' can be used as a neutral value for window and will be ignored when processing the configuration.<br>
      <i>w_regexp</i> defines a regular expression to be applied to the reading. Default is '.*Open.*'.<br>
    </li>

    <li>
     <code>&lt;usePID=0&gt;</code><br>
      <i>usePID 0</i>: calculate Pulse based on parameters factor and offset.<br>
      Internals c_factor and c_foffset will reflect the values used for calculatio. Defaults are 1 and 0.11 (if not specified)<br>
      Readings PWMOnTime and PWMPulse will reflect the actual calculated Pulse.<br>
    </li>
    <li>
     <code>&lt;usePID=1&gt;:&lt;PFactor&gt;:&lt;IFactor&gt;[,&lt;ILookBackCnt&gt;]:&lt;DFactor&gt;[,&lt;DLookBackCnt&gt;]</code><br>
      <i>PFactor</i>: Konstant for P. Default is 0.8.<br>
      <i>IFactor</i>: Konstant for I. Default is 0.3<br>
      <i>DFactor</i>: Konstant for D. Default is 0.5<br> 
      <i>ILookBackCnt</i>: Buffer size to store previous temperatures. For I calculation all values will be used. Default is 5.<br> 
      <i>DLookBackCnt</i>: Buffer size to store previous temperatures. For D calculation actual and oldest temperature will be used. Default is 10.<br> 
      Internals c_PID_PFactor, c_PID_IFactor, c_PID_ILookBackCnt, c_PID_DFactor, c_PID_DLookBackCnt and c_PID_useit will reflect the above configuration values.<br>
      Readings PID_DVal, PID_IVal, PID_PVal, PID_PWMOnTime and PID_PWMPulse will reflect the actual calculated PID values and Pulse.<br>
    </li>
    <li>
     <code>&lt;usePID=2&gt;:&lt;PFactor&gt;:&lt;IFactor&gt;:&lt;DFactor&gt;[,&lt;DLookBackCnt&gt;]</code><br>
      <i>PFactor</i>: Konstant for P. Default is 0.8.<br>
      <i>IFactor</i>: Konstant for I. Default is 0.01<br>
      <i>DFactor</i>: Konstant for D. Default is 0<br> 
      <i>DLookBackCnt</i>: Buffer size to store previous temperatures. For D calculation actual and oldest temperature will be used. Default is 10.<br> 
      Internals c_PID_PFactor, c_PID_IFactor, c_PID_DFactor, c_PID_DLookBackCnt and c_PID_useit will reflect the above configuration values.<br>
      Readings PID_DVal, PID_IVal, PID_PVal, PID_PWMOnTime and PID_PWMPulse will reflect the actual calculated PID values and Pulse.<br>
    </li>

    </ul>

    <br>
    Example:<br>
    <br>
    <code>define roomKitchen PWMR fh 1,0.11 tempKitchen relaisKitchen</code><br>
    <code>define roomKitchen PWMR fh 1,0.11 tempKitchen relaisKitchen windowKitchen1,windowKitchen2</code><br>
    <code>define roomKitchen PWMR fh 1,0.11 tempKitchen relaisKitchen windowKitchen1,windowKitchen2:.*Open.*</code><br>
    <code>define roomKitchen PWMR fh 1,0.11 tempKitchen relaisKitchen windowKitchen1,windowKitchen2</code><br>
    <code>define roomKitchen PWMR fh 1,0.11 tempKitchen relaisKitchen dummy 0</code><br>
    <code>define roomKitchen PWMR fh 0 tempKitchen relaisKitchen dummy 1:0.8:0.3:0.5</code><br>
    <code>define roomKitchen PWMR fh 0 tempKitchen relaisKitchen dummy 1:0.8:0.3,5:0.5,10</code><br>
    <code>define roomKitchen PWMR fh 0 tempKitchen relaisKitchen dummy 2:0.8:0.01:00</code><br>
    <code>define roomKitchen PWMR fh 0 tempKitchen relaisKitchen dummy 2:0.8:0.01:0.1,10</code><br>
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

    <li>frostProtect<br>
        Sets attribute frostProtect to 1 (on) or 0 (off).
        </li><br>


  </ul>

  <b>Get </b>
  <ul>
    <li>previousTemps<br>
        Get conent of buffers defined by <i>ILookBackCnt</i> and <i>DLookBackCnt</i>.
        </li><br>
  </ul>

  <b>Attributes</b>
  <ul>
    <li>disable<br>
        PWMR objects with attribute disable set to <i>1</i> will be excluded in the calculation loop of the PWM object.
        </li><br>

    <li>frostProtect<br>
        Switch on (1) of off (0) frostProtectMode. <i>desired-temp</i> will be set to <i>tempFrostProtect</i> in autoCalcMode.
        </li><br>

    <li>autoCalcTemp<br>
        Switch on (1) of off (0) autoCalcMode. <i>desired-temp</i> will be set based on the below temperatures and rules in autoCalcMode.<br>
        Default is on.
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

    <li>desiredTempFrom<br>
        This can be used as an alternative instead of the calculation of desired-temp based on the tempRules - which will happen when autoCalcTemp is set to '1'.<br>
	(Either by removing the attribute autoCalcTemp or explicitly setting it to '1'.).<br>
        If set correctly the desired-temp will be read from a reading of another device.<br>
        Format is &lt;device&gt;[:&lt;reading&gt;[:&lt;regexp&gt;]]<br>
        <i>device</i> defines the reference to the other object.<br>
        <i>reading</i> defines the reading that contains the value for desired-temp. Default is 'desired-temp'.<br>
        <i>regexp</i> defines a regular expression to extract the value used for 'desired-temp'. Default is '(\d[\d\.]+)'. 
        If <i>regexp</i> does not match (e.g. reading is 'off') then tempFrostProtect is used.<br> 
        Internals c_desiredTempFrom reflects the actual setting and d_name, d_reading und d_regexpTemp the values used.<br>
        If this attribute is used then state will change from "Calculating" to "From &lt;device&gt;".<br>
        Calculation of desired-temp is (like when using tempRules) based on the interval specified for this device (default is 300 seconds).<br>
        Special values "on" and "off" of Homematic devices are handled as c_tempC (set by attribute tempCosy) and c_tempFrostProtect (set by attribute tempFrostProtect).



        </li><br>

    <li>valueFormat<br>
        Defines a map to format values within PWMR.<br>
        The following reading can be formated using syntax of sprinf: temperature
	<br>
        Example: { "temperature" => "%0.2f" }
        </li><br>

  </ul>
  <br>
</ul>

=end html
=cut

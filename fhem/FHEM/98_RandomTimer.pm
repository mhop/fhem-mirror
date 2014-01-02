# $Id$
##############################################################################
#
#     98_RandomTimer_Initialize.pm
#     written by Dietmar Ortmann
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
#     define t1 RandomTimer  *23:01:10 Zirkulation 23:02:10  100; attr   t1 verbose 5;
#     define t2 RandomTimer  *23:01:20 Zirkulation 23:03:20  100; attr   t2 verbose 5;
#     define t3 RandomTimer  *23:01:30 Zirkulation 23:04:30  100; attr   t3 verbose 5;
#     define t4 RandomTimer  *23:01:40 Zirkulation 23:02:40  100; attr   t4 verbose 5;
#
##############################################################################
# 10.09.2013 Svenson : disable direct if attribute changed, add state disabled;
#                      randomtimer run every day if attribut runonce 0 (default is 1)
#
##############################################################################
package main;

use strict;
use warnings;
use IO::Socket;
use Time::HiRes qw(gettimeofday);

sub RandomTimer_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "RandomTimer_Define";
  $hash->{UndefFn}   = "RandomTimer_Undef";
  $hash->{AttrFn}   =  "RandomTimer_Attr";
  $hash->{AttrList}  = "onCmd offCmd switchmode disable:0,1 disableCond runonce:0,1 ".
                       $readingFnAttributes;
}
#
#
#
sub RandomTimer_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  delete $modules{RandomTimer}{defptr}{$hash->{NAME}};
  return undef;
}
#
#
#
sub RandomTimer_Define($$)
{
  my ($hash, $def) = @_;

  RemoveInternalTimer($hash);
  my ($name, $type, $timespec_start, $device, $timespec_stop, $timeToSwitch) =
    split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> RandomTimer <timespec_start> <device> <timespec_stop> <timeToSwitch>"
    if(!defined $timeToSwitch);

  return "Wrong timespec_start <$timespec_start>, use \"[+][*]<time or func>\""
     if($timespec_start !~ m/^(\+)?(\*)?(.*)$/i);
  my ($rel, $rep, $tspec) = ($1, $2, $3);
  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($tspec);
  return $err if($err);

  $rel = "" if(!defined($rel));
  $rep = "" if(!defined($rep));

  return "Wrong timespec_stop <$timespec_stop>, use \"[+][*]<time or func>\""
     if($timespec_stop !~ m/^(\+)?(\*)?(.*)$/i);
  my ($srel, $srep, $stspec) = ($1, $2, $3);
  my ($e, $h, $m, $s, $f) = GetTimeSpec($stspec);
  return $e if($e);

  return "invalid timeToSwitch <$timeToSwitch>, use 9999"
     if(!($timeToSwitch =~  m/^[0-9]{2,4}$/i));

   get_switchmode($hash);

  $hash->{NAME}           = $name;
  $hash->{DEVICE}         = $device;
  $hash->{TIMESPEC_START} = $timespec_start;
  $hash->{TIMESPEC_STOP}  = $timespec_stop;
  $hash->{TIMETOSWITCH}   = $timeToSwitch;
  $hash->{REP}            = $rep;
  $hash->{REL}            = $rel;
  $hash->{S_REP}          = $srep;
  $hash->{S_REL}          = $srel;
  $hash->{COMMAND}        = "off";

  delete $hash->{STARTTIME};
  delete $hash->{ABSCHALTZEIT};

  $modules{RandomTimer}{defptr}{$hash->{NAME}} = $hash;
  RandomTimer_ExecRepeater($hash);
  return undef;

}
#
#
#
sub RandomTimer_ExecRepeater($)
{
  my ($hash) = @_;
  my $timespec_start = $hash->{TIMESPEC_START};

  return "Wrong timespec_start <$timespec_start>, use \"[+][*]<time or func>\""
     if($timespec_start !~ m/^(\+)?(\*)?(.*)$/i);
  my ($rel, $rep, $tspec) = ($1, $2, $3);

  my ($err, $thour, $tmin, $tsec, $fn);
  if (!defined $hash->{STARTTIME}) {
     ($err, $thour, $tmin, $tsec, $fn) = GetTimeSpec($tspec);
     return $err if($err);
     $hash->{STARTTIME} = sprintf ("%2d:%02d:%02d", $thour, $tmin, $tsec);
  } else {
    ($thour, $tmin, $tsec) = split(/:/, $hash->{STARTTIME});
  }

  my $now = time();
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($now);

  my $stopTime = abschaltUhrZeitErmitteln($hash);
  my ($shour, $smin, $ssec) = split(/:/, $stopTime);

  my $timeToStart = $now + 3600*($thour-$hour) + 60*($tmin-$min) + ($tsec-$sec);
  my $timeToStop  = $now + 3600*($shour-$hour) + 60*($smin-$min) + ($ssec-$sec);
  $timeToStop    += 24*3600 if ($timeToStart>=$timeToStop);
  $hash->{STATE}  = strftime("%H:%M:%S",localtime($timeToStart));

  my $timeToExec;
  my $function = "RandomTimer_ExecRepeater";
  if ($now > $timeToStop) {

    my $midnight  =  $now + 24*3600 -(3600*$hour + 60*$min + $sec);
    $timeToExec   = max ($timeToStop, $midnight) + 5*60;
    delete $hash->{STARTTIME};

  } else {
    if ($now < $timeToStart) {
        $timeToExec = $timeToStart;
    } else {
        $timeToExec = $now + 1;
        $function = "RandomTimer_Exec";
    }
  }

  Log3 $hash, 4, "[".$hash->{NAME}. "]"." Next timer ".strftime("%d.%m.%Y  %H:%M:%S",localtime($timeToExec));

  delete $hash->{ABSCHALTZEIT};
  RemoveInternalTimer($hash);
  InternalTimer      ($timeToExec, $function, $hash, 0);

}
#
#
#
sub RandomTimer_Exec($)
{
  my ($hash) = @_;

  my $now1 = time();
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime($now1);

  my $now = sprintf ("%04d:%03d:%02d:%02d:%02d",$year+1900,$yday,$hour,$min,$sec);

  if (RandomTimer_disable($hash)) {
     if (defined $hash->{ABSCHALTZEIT}) {
        $hash->{COMMAND} = "off";
        $hash->{STATE}   = "off";
        fhem ("set $hash->{DEVICE} $hash->{COMMAND}");
        Log3 $hash, 3, "[".$hash->{NAME}. "]" . " $hash->{DEVICE} disabled - going down ...";
        delete $hash->{ABSCHALTZEIT};
     } else {
       Log3 $hash, 4, "[".$hash->{NAME}. "]" . " $hash->{DEVICE} timer disabled - no start";
     }
     if ($hash->{REP} gt "") {
        my $midnight = $now1 + 24*3600 - (3600*$hour + 60*$min + $sec);
        Log3 $hash, 4, "[".$hash->{NAME}. "]"." Next Timer ".strftime("%d.%m.%Y  %H:%M:%S",localtime($midnight));
        InternalTimer($midnight,      "RandomTimer_ExecRepeater_verzoegert",     $hash, 0);
     } else {
        $hash->{COMMAND} = "off";
        $hash->{STATE}   = "disabled";
     }
     return;
  }

  if (!defined $hash->{ABSCHALTZEIT}) {
     $hash->{ABSCHALTZEIT} = abschaltZeitErmitteln($hash);
     if ($now ge $hash->{ABSCHALTZEIT})  {
        $hash->{COMMAND} = "off";
        $hash->{STATE}   = "off";
        delete $hash->{STARTTIME};
        delete $hash->{ABSCHALTZEIT};
        if ($hash->{REP} gt "") {
           RandomTimer_ExecRepeater($hash);
        }
        return;
     }
  }

  if ($now ge $hash->{ABSCHALTZEIT})  {
    Log3 $hash, 3, "[".$hash->{NAME}."]"." $hash->{DEVICE} going down ...";
    $hash->{COMMAND} = "off";
    $hash->{STATE}   = "off";
    fhem ("set $hash->{DEVICE} $hash->{COMMAND}");
    delete $hash->{ABSCHALTZEIT};

    if ($hash->{REP} gt "") {
       RandomTimer_ExecRepeater($hash);
    } else {
      if ( AttrVal($hash->{NAME}, "runonce", 1) == 1 )
         { fhem ("delete $hash->{NAME}") ;}
      else
         { RandomTimer_ExecRepeater($hash);}
    }
  } else {
    toggleDevice($hash);
    my $secsToNextAbschaltTest = getSecsToNextAbschaltTest($hash);
    InternalTimer(gettimeofday()+$secsToNextAbschaltTest,      "RandomTimer_Exec",     $hash, 0);
  }
}
#
#
#
sub RandomTimer_Attr($$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
 
  if( $attrName eq "disable" ) {
     my $hash = $defs{$name};
     if( $cmd eq "set" && $attrVal ne "0" ) {
       $attr{$name}{$attrName} = 1;
       $hash->{STATE}   = "disabled";
       RemoveInternalTimer($hash);
     } else {
        $attr{$name}{$attrName} = 0;
        $hash->{STATE}   = "off";
        RandomTimer_ExecRepeater($hash);
     }
  } 
}
#
#
#
sub RandomTimer_ExecRepeater_verzoegert($)
{
    my ($hash) = @_;

    if ($hash->{REP} gt "") {
       RandomTimer_ExecRepeater($hash);
    }
}
#
#
#
sub getSecsToNextAbschaltTest($)
{
    my ($hash) = @_;
    my $intervall = $hash->{TIMETOSWITCH};

    my $proz = 10;
    my $delta    = $intervall * $proz/100;
    my $nextSecs = $intervall - $delta/2 + int(rand($delta));

    return $nextSecs;
}
#
#
#
sub abschaltZeitErmitteln ($) {
   my ($hash) = @_;
   my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);

   my $uebertragDay  = 0;
   my $uebertragYear = 0;

   my $stoptime  = abschaltUhrZeitErmitteln($hash);
   my $starttime = $hash->{STARTTIME};

   if ($stoptime lt $starttime) {
	     $uebertragDay = 1;
	     if ($mday = 31 && $yday>=365) {
	        $uebertragYear = 1;
		  }
	 }
   return (sprintf ("%04d:%03d:%5s",$year+1900+$uebertragYear,$yday+$uebertragDay,$stoptime));

}
#
#
#
sub abschaltUhrZeitErmitteln ($)
{
   my ($hash) = @_;
   my($sec,$min,$hour)=localtime(time);

   my $timespec_stop  = $hash->{TIMESPEC_STOP};

  Log3 ($hash, 3, "Wrong timespec_stop <$timespec_stop>, use \"[+][*]<time or func>\"" )
     if($timespec_stop !~ m/^(\+)?(\*)?(.*)$/i);
  my ($srel, $srep, $stspec) = ($1, $2, $3);
  my ($err, $h, $m, $s, $fn) = GetTimeSpec($stspec);
  Log3 ($hash, 3, $err) if($err);
  $h -=24  if ($h >= 24);

  if ($hash->{S_REL}) {
     my ($thour, $tmin, $tsec) = split(/:/, $hash->{STARTTIME});
     my $timeToStart = time() + 3600*($thour-$hour) + 60*($tmin-$min) + ($tsec-$sec);
     my $timeToStop = $timeToStart + 3600*$h + 60*$m + $s;
     ($s,$m,$h)=localtime($timeToStop);
  }

  my $timeToStop_st =  sprintf ("%02d:%02d:%2d", $h,$m,$s );
  return ($timeToStop_st);
}
#
#
#
sub toggleDevice ($)
{
    my ($hash) = @_;
    get_switchmode($hash);

    my $sigma = ($hash->{COMMAND} eq "on") ? $hash->{SIGMAON} : $hash->{SIGMAOFF};

    my $zufall = int(rand(1000));
    Log3 $hash, 4,  "[".$hash->{NAME}."]"." Zustand:$hash->{COMMAND} sigma:$sigma random:$zufall";

    if ($zufall <= $sigma ) {
       $hash->{COMMAND}  = ($hash->{COMMAND} eq "on") ? "off" : "on";

       my $command = "set @ $hash->{COMMAND}";
       if ($hash->{COMMAND} eq "on") {
          $command = AttrVal($hash->{NAME}, "onCmd", $command);
       } else {
          $command = AttrVal($hash->{NAME}, "offCmd", $command);
       }
       $command =~ s/@/$hash->{DEVICE}/g;
       $command = SemicolonEscape($command);
       Log3 $hash, 4, "[".$hash->{NAME}. "]"." command: $command";

       my $ret  = AnalyzeCommandChain(undef, $command);
       Log3 ($hash, 3, $ret)                  if($ret);
    }
    $hash->{STATE} = $hash->{COMMAND};
}
#
#
#
sub get_switchmode ($) {

   my ($hash) = @_;
   my $mod = "[".$hash->{NAME} ."] ";

   my $attr       = "switchmode";
   my $default    = "800/200";
   my $switchmode = AttrVal($hash->{NAME}, $attr, $default);

   if(!($switchmode =~  m/^([0-9]{3,3})\/([0-9]{3,3})$/i)) {
      Log3 undef, 3, $mod . "invalid switchMode <$switchmode>, use 999/999";
      $attr{$hash->{NAME}}{$attr} = $default;
   } else {
      my ($sigmaoff, $sigmaon) = ($1, $2);
      $hash->{SWITCHMODE}   = $switchmode;
      $hash->{SIGMAON}      = $sigmaon;
      $hash->{SIGMAOFF}     = $sigmaoff;

   }
}
sub RandomTimer_disable($) {

   my ($hash) = @_;

   my $disable     = AttrVal($hash->{NAME}, "disable",     0 );
   my $disableCond = AttrVal($hash->{NAME}, "disableCond", "");
   $disable = $disable || eval ($disableCond);
   return $disable;
}

1;


=pod
=begin html

<a name="RandomTimer"></a>
<h1>RandomTimer</h1>
   <h2>Define</h2>
       <ul>
          <code><font size="+2">define &lt;name&gt; RandomTimer  &lt;timespec_start&gt; &lt;device&gt; &lt;timespec_stop&gt; [&lt;timeToSwitch&gt;]</font></code><br>
         <br>
         Defines a device, that imitates the random switch functionality of a timer clock, like a <b>FS20 ZSU</b>.
         The idea to create it, came from the problem, that is was always a little bit tricky to install a timer clock before
         holiday: finding the manual, testing it the days before and three different timer clocks with three different manuals - a horror.<br>
         By using it in conjunction with a dummy and a <a href="#disableCond">disableCond</a>, i'm able to switch the always defined timer on every weekend easily from all over the word.
         <br><br>
         <h3>Deskrition</h3>
          a RandomTimer device starts at timespec_start switching device. Every (timeToSwitch
          seconds +-10%) it trys to switch device on/off. The switching period stops when the
          next time to switch is greater than timespec_stop.
         <br><br>
       </ul>
       <h3>Parameter</h3>
           <ul>
              <b>timespec_start</b>
              <br>
                The parameter <b>timespec_start</b> defines the start time of the timer with format: HH:MM:SS.
                It can be a Perlfunction as known from the timespec <a href="#at">at</a> &nbsp;.
                <br><br>
              <b>device</b>
              <br>
                       The parameter <b>device</b> defines the fhem device that should be switched.
                <br><br>
              <b>timespec_stop</b>
              <br>
                       The parameter <b>timespec_stop</b> defines the stop time of the timer with format: HH:MM:SS.
                It can be a Perlfunction as known from the timespec <a href="#at">at</a> &nbsp;.
                <br><br>
              <b>timeToSwitch</b>
              <br>
                       The parameter <b>timeToSwitch</b> defines the time in seconds between two on/off switches.
                <br><br>
           </ul>
       <h3>Examples</h3>
           <ul>
             <li>
               <code>define ZufallsTimerTisch      RandomTimer  *{sunset_abs()} StehlampeTisch  +03:00:00             500</code><br>
               defines a timer that starts at sunset an ends 3 hous later. The timer trys to switch every 500 seconds(+-10%).
             </li><br><br>
             <li>
               <code>define ZufallsTimerTisch      RandomTimer  *{sunset_abs()} StehlampeTisch  *{sunset_abs(3*3600)} 480</code><br>
               defines a timer that starts at sunset and stops after sunset + 3 hours. The timer trys to switch every 480 seconds(+-10%).
             </li><br><br>
             <li>
               <code>define ZufallsTimerTisch      RandomTimer  *{sunset_abs()} StehlampeTisch  22:30:00 300</code><br>
               defines a timer that starts at sunset an ends at 22:30. The timer trys to switch every 300 seconds(+-10%).
             </li><br><br>
          </ul>

  <!-- -------------------------------------------------------------------------- -->
  <!-- Set     ------------------------------------------------------------------ -->
  <!-- -------------------------------------------------------------------------- -->
  <a name="RandomTimerSet"></a>
  <h3>Set</h3>
  <ul>
    N/A
  </ul>
  <!-- -------------------------------------------------------------------------- -->
  <!-- Get     ------------------------------------------------------------------ -->
  <!-- -------------------------------------------------------------------------- -->
  <a name="RandomTimerGet"></a>
  <h3>Get</h3>
  <ul>
    N/A
  </ul>
  <!-- -------------------------------------------------------------------------- -->
  <!-- Attributes --------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
  <a name="RandomTimerAttributes"></a>
  <h3>Attributes</h3>
  <ul>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="disableCond">disableCond</a><br>
        The default behavior of a RandomTimer is, that it works.
        To set the Randomtimer out of work, you can specify in the disableCond attibute a condition in perlcode that must evaluate to true.
        The Condition must be put into round brackets. The best way is to define
        a function in 99_utils.
        <br>
        <b>Examples</b>
        <pre>
        attr   ZufallsTimerZ         disableCond  (!isVerreist())
        attr   ZufallsTimerZ         disableCond  (Value("presenceDummy" eq "notPresent"))
        </pre>
    </li>
    <li><a name="onOffCmd">onCmd, offCmd</a><br>
        Setting the on-/offCmd changes the command sent to the device. Standard is: "set &lt;device&gt; on".
        The device can be specified by a @.
        <br>
        <b>Examples</b>
        <pre>
        attr   Timer                  oncmd   {fhem("set @ on-for-timer 14")}
        attr   Timer                  offCmd  {fhem("set @ off 16")}
        attr   Timer                  oncmd  set @ on-for-timer 12
        attr   Timer                  offCmd set @ off 12
        </pre>
    </li>
    <li><a name="switchmode">switchmode</a><br>
        Setting the switchmode you can influence the behavior of switching on/off.
        The parameter has the Format 999/999 and the default ist 800/200. The values are in "per mill".
        The first  parameter sets the value of the probability that the device will be switched on  when the device is off.
        The second parameter sets the value of the probability that the device will be switched off when the device is off.
        <b>Examples</b>
        <pre>
        attr   ZufallsTimerZ         switchmode  400/400
        </pre>
    </li>
  </ul>

=end html
=cut

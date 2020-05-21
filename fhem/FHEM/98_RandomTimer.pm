##########################################################################
# $Id$
#
# copyright ###################################################################
#
# 98_RandomTimer.pm
#
# written by Dietmar Ortmann
# Maintained by Beta-User since 11-2019
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# FHEM is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FHEM.  If not, see <http://www.gnu.org/licenses/>.

# packages ####################################################################
package FHEM::RandomTimer;    ## no critic 'Package declaration'

use strict;
use warnings;
use utf8;
use Time::HiRes qw(gettimeofday);
use Time::Local qw(timelocal_nocheck);
use List::Util qw(max);
use GPUtils qw(GP_Import GP_Export);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          defs
          modules
          attr
          featurelevel
          readingFnAttributes
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          AttrVal
          ReadingsVal
          Value
          IsDisabled
          Log3
          InternalTimer
          RemoveInternalTimer
          CommandDeleteAttr
          AnalyzeCommandChain
          AnalyzePerlCommand
          perlSyntaxCheck
          SemicolonEscape
          FmtDateTime
          strftime
          GetTimeSpec
          stacktrace )
    );
}

sub main::RandomTimer_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
    my $hash = shift // return;

    $hash->{DefFn}    = \&Define;
    $hash->{UndefFn}  = \&Undef;
    $hash->{SetFn}    = \&Set;
    $hash->{AttrFn}   = \&Attr;
    $hash->{AttrList} = "onCmd offCmd switchmode disable:0,1 disableCond disableCondCmd:none,offCmd,onCmd offState "
      . "runonce:0,1 keepDeviceAlive:0,1 forceStoptimeSameDay:0,1 disabledForIntervals "
      . $readingFnAttributes;
    return;
}

# regular Functions ##################################################################
sub Define {
    my $hash = shift;
    my $def = shift // return;

    RemoveInternalTimer($hash);
    my ( $name, $type, $timespec_start, $device, $timespec_stop, $timeToSwitch,
        $variation )
      = split m{\s+}xms, $def;

    return "wrong syntax: define <name> RandomTimer <timespec_start> <device> <timespec_stop> <timeToSwitch> [<variations>]"
      if ( !defined $timeToSwitch );

    my ( $rel, $rep, $tspec );
    if ( $timespec_start =~ m{^(\+)?(\*)?(.*)$}ixms ) {
        $rel   = $1;
        $rep   = $2;
        $tspec = $3;
    }
    else { 
        return qq{ "Wrong timespec_start <$timespec_start>, use "[+][*]<time or func>" };
    }

    my ( $err, $hr, $min, $sec, $fn ) = GetTimeSpec($tspec);
    return $err if ($err);

    $rel = $rel // "";
    $rep = $rep // "";

    my ( $srel, $srep, $stspec );
    if ( $timespec_stop =~ m{^(\+)?(\*)?(.*)$}ixms ) {
        $srel   = $1;
        $srep   = $2;
        $stspec = $3;
    }
    else {
        return
          qq{"Wrong timespec_stop <$timespec_stop>, use "[+][*]<time or func>"};
    }

    my ( $e, $h, $m, $s, $f ) = GetTimeSpec($stspec);
    return $e if ($e);

    return "invalid timeToSwitch <$timeToSwitch>, use 9999"
      if ( !( $timeToSwitch =~ m{^[0-9]{2,4}$}ixms ) );
    my ( $varDuration, $varStart );
    $varDuration = 0;
    $varStart    = 0;
    if ( defined $variation ) {
        $variation =~ m{^([\d]+)}xms   ? $varDuration = $1 : undef;
        $variation =~ m{[:]([\d]+)}xms ? $varStart    = $1 : undef;
    }
    setSwitchmode( $hash, "800/200" )
      if ( !defined $hash->{helper}{SWITCHMODE} );

    $hash->{NAME}                   = $name;
    $hash->{DEVICE}                 = $device;
    $hash->{helper}{TIMESPEC_START} = $timespec_start;
    $hash->{helper}{TIMESPEC_STOP}  = $timespec_stop;
    $hash->{helper}{TIMETOSWITCH}   = $timeToSwitch;
    $hash->{helper}{REP}            = $rep;
    $hash->{helper}{REL}            = $rel;
    $hash->{helper}{VAR_DURATION}   = $varDuration;
    $hash->{helper}{VAR_START}      = $varStart;
    $hash->{helper}{S_REL}          = $srel;
    $hash->{helper}{S_REL}          = $srel;

    $hash->{COMMAND} = Value( $hash->{DEVICE} ) if ( $featurelevel < 6.1 );
    if ( $featurelevel > 6.0 ) {
        $hash->{COMMAND} = ReadingsVal( $hash->{DEVICE}, "state", undef );
        $hash->{helper}{offRegex}   = "off";
        $hash->{helper}{offReading} = "state";
    }

    readingsSingleUpdate( $hash, "TimeToSwitch", $hash->{helper}{TIMETOSWITCH},
        1 );

    RmInternalTimer( "SetTimer", $hash );
    MkInternalTimer( "SetTimer", time(), \&SetTimer, $hash, 0 );

    return;
}

sub Undef {

    my ( $hash, $arg ) = @_;

    RmInternalTimer( "SetTimer", $hash );
    RmInternalTimer( "Exec",     $hash );
    delete $modules{RandomTimer}{defptr}{ $hash->{NAME} };
    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;

    my $hash = $defs{$name};

    if ( $attrName eq 'switchmode' ) {
        setSwitchmode( $hash, $attrVal );
    }

    if ( $attrName =~ m{\A disable(Cond)? \z}xms ) {

        # Immediately execute next switch check
        RmInternalTimer( "Exec", $hash );
        MkInternalTimer( "Exec", time() + 1, \&Exec, $hash, 0 );
    }

    if ( $attrName eq 'offState' ) {
        my ( $offRegex, $offReading ) = split ' ', $attrVal, 2;
        $hash->{helper}{offRegex} = $offRegex;
        $hash->{helper}{offReading} = $offReading // 'state';
    }
    
    if ( $attrName eq 'disableCond' ) {
        if( $cmd eq "set" ) {
            my $err = perlSyntaxCheck($attrVal);
            return $err if ( $err );
        }
    }
  
    return;
}

sub Set {
    my ( $hash, @a ) = @_;

    return "no set value specified" if ( int(@a) < 2 );
    return "Unknown argument $a[1], choose one of execNow:noArg active:noArg inactive:noArg"
      if ( $a[1] eq "?" );

    my $name = shift @a;
    my $v = join( " ", @a );

    if ( $v eq "execNow" ) {
        Log3( $hash, 3, "[$name] set $name $v" );
        if ( AttrVal( $name, "disable", 0 ) ) {
            Log3( $hash, 3, "[$name] is disabled, set execNow not possible" );
        }
        else {
            RmInternalTimer( "Exec", $hash );
            MkInternalTimer( "Exec", time() + 1, \&Exec, $hash, 0 );
        }
        return;
    }
    if ( $v eq "active" || $v eq "inactive" ) {
        Log3( $hash, 3, "[$name] set $name $v" );
        if ( $v eq "active" && AttrVal( $name, "disable", 0 ) ) {
            CommandDeleteAttr( undef, "$name disable" );
        }
        my $statevalue = $v eq "active" ? "activated" : $v;
        readingsSingleUpdate( $hash, "state", $statevalue, 1 );
        RmInternalTimer( "Exec", $hash );
        MkInternalTimer( "Exec", time() + 1, \&Exec, $hash, 0 );
        return;
    }
    return;
}

# module Fn ###################################################################
sub addDays {
    my $now = shift;
    my $days = shift // return;

    my @jetzt_arr = localtime($now);
    $jetzt_arr[3] += $days;
    my $next = timelocal_nocheck(@jetzt_arr);

    return $next;

}

sub device_switch {
    my $hash = shift // return;

    my $command = "set @ $hash->{COMMAND}";
    if ( $hash->{COMMAND} eq "on" ) {
        $command = AttrVal( $hash->{NAME}, "onCmd", $command );
    }
    else {
        $command = AttrVal( $hash->{NAME}, "offCmd", $command );
    }
    $command =~ s/@/$hash->{DEVICE}/gxms;
    $command = SemicolonEscape($command);
    readingsSingleUpdate( $hash, 'LastCommand', $command, 1 );
    Log3( $hash, 4, "[" . $hash->{NAME} . "]" . " command: $command" );

    my $ret = AnalyzeCommandChain( undef, $command );
    Log3( $hash, 3, "[$hash->{NAME}] ERROR: " . $ret . " SENDING " . $command )
      if ($ret);

    return;
}

sub device_toggle {
    my $hash = shift // return;
    my $name = $hash->{NAME};

    #my $attrOffState = AttrVal($name,"offState",undef);
    my $status = Value( $hash->{DEVICE} );

    if ( defined $hash->{helper}{offRegex} ) {
        $status =
          ReadingsVal( $hash->{DEVICE}, $hash->{helper}{offReading}, "off" );
        my $attrOffState = $hash->{helper}{offRegex};
        $status = $status =~ m{^$attrOffState$}xms ? "off" : lc($status);
        $status = $status =~ m{off}xms             ? "off" : "on";
    }
    if ( $status ne "on" && $status ne "off" ) {
        if ( $hash->{helper}{offRegex} ) {
            Log3( $hash, 3, "[$name] result of function ReadingsVal($hash->{DEVICE},\"<offReading>\",undef) must be 'on' or 'off' or set attribute offState accordingly" );
        }
        else {
            Log3 ( $hash, 3, "[$name] result of function Value($hash->{DEVICE}) must be 'on' or 'off'" );
        }
    }

    my $sigma =
      ( $status eq "on" )
      ? $hash->{helper}{SIGMAWHENON}
      : $hash->{helper}{SIGMAWHENOFF};

    my $zufall = int( rand(1000) );
    Log3( $hash, 4, "[$name] IstZustand:$status sigmaWhen-$status:$sigma random:$zufall<$sigma=>"
      . ( ( $zufall < $sigma ) ? "true" : "false" ) );

    if ( $zufall < $sigma ) {
        $hash->{COMMAND} = ( $status eq "on" ) ? "off" : "on";
        device_switch($hash);
    }
    return;
}

sub disableDown {
    my $hash = shift // return;
    my $disableCondCmd = AttrVal( $hash->{NAME}, "disableCondCmd", 0 );

    if ( $disableCondCmd ne "none" ) {
        Log3( $hash, 4,
            "["
          . $hash->{NAME} . "]"
          . " setting requested disableCondCmd on $hash->{DEVICE}: " );
        $hash->{COMMAND} =
          AttrVal( $hash->{NAME}, "disableCondCmd", 0 ) eq "onCmd"
          ? "on"
          : "off";
        device_switch($hash);
    }
    else {
        Log3( $hash, 4,
            "["
          . $hash->{NAME} . "]"
          . " no action requested on $hash->{DEVICE}: " );
    }
    return;
}

sub down {
    my $hash = shift // return;
    Log3( $hash, 4,
        "["
      . $hash->{NAME} . "]"
      . " setting requested keepDeviceAlive on $hash->{DEVICE}: " );
    $hash->{COMMAND} =
      AttrVal( $hash->{NAME}, "keepDeviceAlive", 0 ) ? "on" : "off";
    device_switch($hash);
    return;
}

sub Exec {
    my $myHash = shift // return;

    my $hash = GetHashIndirekt( $myHash, ( caller(0) )[3] );
    return if ( !defined($hash) );

    my $now = time();

    # Wenn aktiv aber disabled, dann timer abschalten, Meldung ausgeben.
    my $active          = isAktive($hash);
    my $disabled        = isDisabled($hash);
    my $stopTimeReached = stopTimeReached($hash);

    if ($active) {

        # wenn temporär ausgeschaltet
        if ($disabled) {
            Log3( $hash, 3,
                "["
              . $hash->{NAME} . "]"
              . " disabled before stop-time , ending RandomTimer on $hash->{DEVICE}: "
              . strftime( "%H:%M:%S(%d)",
                localtime( $hash->{helper}{startTime} ) )
              . " - "
              . strftime( "%H:%M:%S(%d)",
                localtime( $hash->{helper}{stopTime} ) ) );
            disableDown($hash);
            setActive( $hash, 0 );
            setState($hash);
        }

# Wenn aktiv und Abschaltzeit erreicht, dann Gerät ausschalten, Meldung ausgeben und Timer schließen
        if ($stopTimeReached) {
            Log3( $hash, 3,
                "["
              . $hash->{NAME} . "]"
              . " stop-time reached, ending RandomTimer on $hash->{DEVICE}: "
              . strftime( "%H:%M:%S(%d)",
                localtime( $hash->{helper}{startTime} ) )
              . " - "
              . strftime( "%H:%M:%S(%d)",
                localtime( $hash->{helper}{stopTime} ) ) );
            down($hash);
            setActive( $hash, 0 );
            if ( AttrVal( $hash->{NAME}, "runonce", -1 ) eq "1" ) {
                Log3( $hash, 3, "[" . $hash->{NAME} . "]" . "runonceMode" );
                fhem("delete $hash->{NAME}");
            }
            setState($hash);
            return;
        }
    }
    else {    # !active
        if ($disabled) {
            Log3( $hash, 4,
                "["
              . $hash->{NAME}
              . "] RandomTimer on $hash->{DEVICE} timer disabled - no switch" );
            setState($hash);
            setActive( $hash, 0 );
        }
        if ($stopTimeReached) {
            Log3( $hash, 4,
                "["
              . $hash->{NAME} . "]"
              . " definition RandomTimer on $hash->{DEVICE}: "
              . strftime( "%H:%M:%S(%d)",
                localtime( $hash->{helper}{startTime} ) )
              . " - "
              . strftime( "%H:%M:%S(%d)",
                localtime( $hash->{helper}{stopTime} ) ) );
            setState($hash);
            setActive( $hash, 0 );
            return;
        }
        if ( !$disabled ) {
            if (   $now > $hash->{helper}{startTime}
                && $now < $hash->{helper}{stopTime} )
            {
                Log3( $hash, 3,
                    "["
                  . $hash->{NAME} . "]"
                  . " starting RandomTimer on $hash->{DEVICE}: "
                  . strftime( "%H:%M:%S(%d)",
                    localtime( $hash->{helper}{startTime} ) )
                  . " - "
                  . strftime( "%H:%M:%S(%d)",
                    localtime( $hash->{helper}{stopTime} ) ) );
                setActive( $hash, 1 );
            }
        }
    }

    setState($hash);
    if ( $now > $hash->{helper}{startTime} && $now < $hash->{helper}{stopTime} )
    {
        device_toggle($hash) if ( !$disabled );
    }

    my $nextSwitch = time() + getSecsToNextAbschaltTest($hash);
    RmInternalTimer( "Exec", $hash );
    $hash->{helper}{NEXT_CHECK} =
      strftime( "%d.%m.%Y  %H:%M:%S", localtime($nextSwitch) );
    MkInternalTimer( "Exec", $nextSwitch, \&Exec, $hash, 0 );
    return;
}

sub getSecsToNextAbschaltTest {
    my $hash        = shift // return;
    my $intervall   = $hash->{helper}{TIMETOSWITCH};
    my $varDuration = $hash->{helper}{VAR_DURATION};
    my $nextSecs    = $intervall + int( rand($varDuration) );
    unless ($varDuration) {
        my $proz  = 10;
        my $delta = $intervall * $proz / 100;
        $nextSecs = $intervall - $delta / 2 + int( rand($delta) );
    }
    return $nextSecs;
}

sub isAktive {
    my $hash = shift // return;
    return defined( $hash->{helper}{active} ) ? $hash->{helper}{active} : 0;
}

sub isDisabled {
    my $hash = shift // return;

    my $disable =
      IsDisabled( $hash->{NAME} );    #AttrVal($hash->{NAME}, "disable", 0 );
    return $disable if ($disable);

    my $disableCond = AttrVal( $hash->{NAME}, "disableCond", "nf" );
    return 0 if ( $disableCond eq "nf" );

    return AnalyzePerlCommand( $hash, $disableCond );
}

sub schaltZeitenErmitteln {
    my $hash = shift;
    my $now = shift // return;

    startZeitErmitteln( $hash, $now );
    stopZeitErmitteln( $hash, $now );

    readingsBeginUpdate($hash);

#  readingsBulkUpdate ($hash,  "Startzeit", FmtDateTime($hash->{helper}{startTime}));
#  readingsBulkUpdate ($hash,  "Stoppzeit", FmtDateTime($hash->{helper}{stopTime}));
    readingsBulkUpdate( $hash, "StartTime",
        FmtDateTime( $hash->{helper}{startTime} ) );
    readingsBulkUpdate( $hash, "StopTime",
        FmtDateTime( $hash->{helper}{stopTime} ) );
    readingsEndUpdate( $hash, defined( $hash->{LOCAL} ? 0 : 1 ) );
    return;
}

sub setActive {
    my $hash = shift;
    my $value = shift // return;
    $hash->{helper}{active} = $value;
    my $trigger = ( isDisabled($hash) ) ? 0 : 1;
    readingsSingleUpdate( $hash, "active", $value, $trigger );
    return;
}

sub setState {
    my $hash = shift // return;

    if ( isDisabled($hash) ) {
        if ( ReadingsVal( $hash->{NAME}, "state", "" ) ne "inactive" ) {
            my $dotrigger =
              ReadingsVal( $hash->{NAME}, "state", "none" ) ne "disabled"
              ? 1
              : 0;
            readingsSingleUpdate( $hash, "state", "disabled", $dotrigger );
        }
    }
    else {
        my $state = $hash->{helper}{active} ? "on" : "off";
        readingsSingleUpdate( $hash, "state", $state, 1 );
    }
    return;
}

sub setSwitchmode {

    my $hash    = shift;
    my $attrVal = shift // return;
    my $mod     = "[" . $hash->{NAME} . "] ";

    if ( !( $attrVal =~ m/^([0-9]{1,3})\/([0-9]{1,3})$/ixms ) ) {
        Log3( undef, 3, $mod . "invalid switchMode <$attrVal>, use 999/999");
    }
    else {
        my ( $sigmaWhenOff, $sigmaWhenOn ) = ( $1, $2 );
        $hash->{helper}{SWITCHMODE}        = $attrVal;
        $hash->{helper}{SIGMAWHENON}       = $sigmaWhenOn;
        $hash->{helper}{SIGMAWHENOFF}      = $sigmaWhenOff;
        $attr{ $hash->{NAME} }{switchmode} = $attrVal;
    }
    return;
}

sub SetTimer {
    my $myHash = shift // return;
    my $hash = GetHashIndirekt( $myHash, ( caller(0) )[3] );
    return if ( !defined($hash) );

    my $now = time();
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime($now);

    setActive( $hash, 0 );
    schaltZeitenErmitteln( $hash, $now );
    setState($hash);

    Log3( $hash, 4,
        "["
      . $hash->{NAME} . "]"
      . " timings RandomTimer on $hash->{DEVICE}: "
      . strftime( "%H:%M:%S(%d)", localtime( $hash->{helper}{startTime} ) )
      . " - "
      . strftime( "%H:%M:%S(%d)", localtime( $hash->{helper}{stopTime} ) ) );

    my $secToMidnight = 24 * 3600 - ( 3600 * $hour + 60 * $min + $sec );

    my $setExecTime = max( $now, $hash->{helper}{startTime} );
    RmInternalTimer( "Exec", $hash );
    MkInternalTimer( "Exec", $setExecTime, \&Exec, $hash, 0 );

    if ( $hash->{helper}{REP} gt "" ) {
        my $setTimerTime =
          max( $now + $secToMidnight + 15, $hash->{helper}{stopTime} ) +
          $hash->{helper}{TIMETOSWITCH} + 15;
        RmInternalTimer( "SetTimer", $hash );
        MkInternalTimer( "SetTimer", $setTimerTime, \&SetTimer, $hash, 0 );
    }
    return;
}

sub startZeitErmitteln {
    my $hash = shift;
    my $now = shift // return;

    my $timespec_start = $hash->{helper}{TIMESPEC_START};

    my ( $rel, $rep, $tspec );
    if ( $timespec_start =~ m{^(\+)?(\*)?(.*)$}ixms ) {
        $rel   = $1;
        $rep   = $2;
        $tspec = $3;
    }
    else {
        return
"Wrong timespec_start <$timespec_start>, use \"[+][*]<time or func>\"";
    }

    my ( $err, $hour, $min, $sec, $fn ) = GetTimeSpec($tspec);
    return $err if ($err);

    my $startTime;
    if ($rel) {
        $startTime = $now + 3600 * $hour + 60 * $min + $sec;
    }
    else {
        $startTime = zeitBerechnen( $now, $hour, $min, $sec );
    }
    my $varStart = $hash->{helper}{VAR_START};
    $startTime += int( rand($varStart) );

    $hash->{helper}{startTime} = $startTime;
    $hash->{helper}{STARTTIME} =
      strftime( "%d.%m.%Y  %H:%M:%S", localtime($startTime) );
    return;
}

sub stopTimeReached {
    my $hash = shift // return;
    return ( time() > $hash->{helper}{stopTime} );
}

sub stopZeitErmitteln {
    my $hash = shift;
    my $now = shift // return;

    my $timespec_stop = $hash->{helper}{TIMESPEC_STOP};

    my ( $rel, $rep, $tspec );
    if ( $timespec_stop =~ m{^(\+)?(\*)?(.*)$}ixms ) {
        $rel   = $1;
        $rep   = $2;
        $tspec = $3;
    }
    else {
        return
          "Wrong timespec_stop <$timespec_stop>, use \"[+][*]<time or func>\"";
    }

    my ( $err, $hour, $min, $sec, $fn ) = GetTimeSpec($tspec);
    return $err if ($err);

    my $stopTime;
    if ($rel) {
        $stopTime =
          $hash->{helper}{startTime} + 3600 * $hour + 60 * $min + $sec;
    }
    else {
        $stopTime = zeitBerechnen( $now, $hour, $min, $sec );
    }

    if ( !AttrVal( $hash->{NAME}, "forceStoptimeSameDay", 0 ) ) {
        if ( $hash->{helper}{startTime} > $stopTime ) {
            $stopTime = addDays( $stopTime, 1 );
        }
    }
    $hash->{helper}{stopTime} = $stopTime;
    $hash->{helper}{STOPTIME} =
      strftime( "%d.%m.%Y  %H:%M:%S", localtime($stopTime) );
    return;
}

sub zeitBerechnen {
    my ( $now, $hour, $min, $sec ) = @_;

    my @jetzt_arr = localtime($now);

    #Stunden               Minuten               Sekunden
    $jetzt_arr[2] = $hour;
    $jetzt_arr[1] = $min;
    $jetzt_arr[0] = $sec;
    my $next = timelocal_nocheck(@jetzt_arr);
    return $next;
}

sub MkInternalTimer {
    my ( $modifier, $tim, $callback, $hash, $waitIfInitNotDone ) = @_;

    my $timerName = "$hash->{NAME}_$modifier";
    my $mHash     = {
        HASH     => $hash,
        NAME     => "$hash->{NAME}_$modifier",
        MODIFIER => $modifier
    };
    if ( defined( $hash->{TIMER}{$timerName} ) ) {
        Log3( $hash, 1, "[$hash->{NAME}] possible overwriting of timer $timerName - please delete first" );
        stacktrace();
    }
    else {
        $hash->{TIMER}{$timerName} = $mHash;
    }

    Log3( $hash, 5,
      "[$hash->{NAME}] setting  Timer: $timerName " . FmtDateTime($tim) );
    InternalTimer( $tim, $callback, $mHash, $waitIfInitNotDone );
    return $mHash;
}
################################################################################
sub RmInternalTimer {
    my $modifier = shift;
    my $hash = shift // return;

    my $timerName = "$hash->{NAME}_$modifier";
    my $myHash    = $hash->{TIMER}{$timerName};
    if ( defined($myHash) ) {
        delete $hash->{TIMER}{$timerName};
        Log3( $hash, 5, "[$hash->{NAME}] removing Timer: $timerName" );
        RemoveInternalTimer($myHash);
    }
    return;
}

sub GetHashIndirekt {
    my $myHash = shift;
    my $function = shift // return;

    if ( !defined( $myHash->{HASH} ) ) {
        Log3( $myHash, 3, "[$function] myHash not valid" );
        return;
    }
    return $myHash->{HASH};
}

1;

__END__

# commandref ##################################################################
=pod
=encoding utf8
=item helper
=item summary    imitates the random switch functionality of a timer clock (FS20 ZSU)
=item summary_DE bildet die Zufallsfunktion einer Zeitschaltuhr nach

=begin html

<a name="RandomTimer"></a>
<h3>RandomTimer</h3>
<div>
  <ul>
    <a name="RandomTimerdefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; RandomTimer  &lt;timespec_start&gt; &lt;device&gt; &lt;timespec_stop&gt; &lt;timeToSwitch&gt;
      </code>
      <br>
      Defines a device, that imitates the random switch functionality of a timer clock, like a <b>FS20 ZSU</b>. The idea to create it, came from the problem, that is was always a little bit tricky to install a timer clock before holiday: finding the manual, testing it the days before and three different timer clocks with three different manuals - a horror.<br>
      By using it in conjunction with a dummy and a disableCond, I'm able to switch the always defined timer on every weekend easily from all over the world.<br>
      <br>
    </ul>
      <b>Description</b>
      <ul>
        a RandomTimer device starts at timespec_start switching device. Every (timeToSwitch seconds +-10%) it trys to switch device on/off. The switching period stops when the next time to switch is greater than timespec_stop.
      </ul>
      <br>
      <b>Parameter</b>
      <ul>
        <li>
          <code>timespec_start</code><br>
          The parameter <b>timespec_start</b> defines the start time of the timer with format: HH:MM:SS. It can be a Perlfunction as known from the <a href="#at">at</a> timespec.
        </li><br>
        <li>
          <code>device</code><br>
          The parameter <b>device</b> defines the fhem device that should be switched.
        </li><br>
        <li>
          <code>timespec_stop</code><br>
          The parameter <b>timespec_stop</b> defines the stop time of the timer with format: HH:MM:SS. It can be a Perlfunction as known from the timespec <a href="#at">at</a>.
        </li><br>
        <li>
          <code>timeToSwitch</code><br>
          The parameter <b>timeToSwitch</b> defines the time in seconds between two on/off switches.<br>
          Note: timeToSwitch will randomly vary by +-10% by default.
        </li><br>
        <li>
          <code>variations</code><br>
          The optional parameters <b>variations</b> will modify <i>timeToSwitch</i> and/or <i>timespec_start</i>, syntax is [VAR_DURATION][:VAR_START].<br>
          <ul>
            <li>VAR_DURATION will turn <i>timeToSwitch</i> to a minimum value with some random seconds between zero and VAR_DURATION will be added.</li>
            <li>VAR_START will modify <i>timespec_start</i> by adding some random seconds between zero and VAR_START.</li>
            <b>Examples:</b><br>
            Add something between 0 and 10 minutes to <i>timeToSwitch</i>:<br>
            <code>defmod Zufall1 RandomTimer *06:00 MYSENSOR_98 22:00:00 3600 600</code><br>
            Randomize day's first check by half an hour:<br>
            <code>defmod Zufall1 RandomTimer *06:00 MYSENSOR_98 22:00:00 3600 :1800</code><br>
            Do both:<br>
            <code>defmod Zufall1 RandomTimer *06:00 MYSENSOR_98 22:00:00 3600 600:1800</code><br>
          </ul>
        </li>
      </ul>
      <br>
      <b>Examples</b>
      <ul>
        <li>
          <code>
            define ZufallsTimerTisch RandomTimer *{sunset_abs()} StehlampeTisch +03:00:00 500
          </code><br>
          defines a timer that starts at sunset an ends 3 hous later. The timer trys to switch every 500 seconds(+-10%).
        </li><br>
        <li>
          <code>
            define ZufallsTimerTisch RandomTimer *{sunset_abs()} StehlampeTisch *{sunset_abs(3*3600)} 480
          </code><br>
          defines a timer that starts at sunset and stops after sunset + 3 hours. The timer trys to switch every 480 seconds(+-10%).
        </li><br>
        <li>
          <code>
            define ZufallsTimerTisch RandomTimer *{sunset_abs()} StehlampeTisch 22:30:00 300
          </code><br>
          defines a timer that starts at sunset an ends at 22:30. The timer trys to switch every 300 seconds(+-10%).
        </li>
      </ul><br>
   </ul>
   <ul>
     <a name="RandomTimerset"></a>
     <b>Set</b><br>
     <ul>
       <code>set &lt;name&gt; execNow</code>
     <br>
     This will force the RandomTimer device to immediately execute the next switch instead of waiting untill timeToSwitch has passed. Use this in case you want immediate reaction on changes of reading values factored in disableCond. As RandomTimer itself will not be notified about any event at all, you'll need an additional event handler like notify that listens to relevant events and issues the "execNow" command towards your RandomTimer device(s). <br>
     NOTE: If the RandomTimer is disabled by attribute, this will not have any effect (different to <code>set &lt;name&gt; active</code>.)
     </ul><br>
     <ul>
       <code>set &lt;name&gt; active</code>
     <br>
     Same effect than execNow, but will also delete a disable attribute if set.
     </ul><br>
     <ul>
       <code>set &lt;name&gt; inactive</code>
     <br>
     Temporarily disable the RandomTimer w/o setting disable attribute. When set the next switch will be immediately executed.
     </ul><br>
    </ul>
   <ul>  
    <a name="RandomTimerAttributes"></a>
    <b>Attributes</b>
    <ul>
      <li>
        <code>disableCond</code><br>
        The default behavior of a RandomTimer is, that it works. To set the Randomtimer out of work, you can specify in the disableCond attibute a condition in perlcode that must evaluate to true. The Condition must be put into round brackets. The best way is to define a function in 99_utils.<br>
        <br>
        <b>Examples</b>
        <ul>
          <li><code>
            attr ZufallsTimerZ disableCond (!isVerreist())
          </code></li>
          <li><code>
            attr ZufallsTimerZ disableCond (ReadingsVal("presenceDummy","state","absent") eq "present")
          </code></li>
        </ul>
      </li>
      <br>
      <li>
        <code>forceStoptimeSameDay</code><br>
        When <b>timespec_start</b> is later then <b>timespec_stop</b>, it forces the <b>timespec_stop</b> to end on the current day instead of the next day. See <a href="https://forum.fhem.de/index.php/topic,72988.0.html" title="Random Timer in Verbindung mit Twilight, EIN-Schaltzeit nach AUS-Schaltzeit">forum post</a> for use case.<br>
      </li>
      <br>
      <li>
        <code>keepDeviceAlive</code><br>
        The default behavior of a RandomTimer is, that it shuts down the device after stoptime is reached. The <b>keepDeviceAlive</b> attribute changes the behavior. If set, the device status is not changed when the stoptime is reached.<br>
        <br>
        <b>Example</b>
        <ul>
          <li><code>attr ZufallsTimerZ keepDeviceAlive</code></li>
        </ul>
      </li>
      <br>
      <li>
        <code>disableCondCmd</code><br>
        In case the disable condition becomes true while a RandomTimer is already <b>running</b>, by default the same action is executed as when stoptime is reached (see keepDeviceAlive attribute). Setting the <b>disableCondCmd</b> attribute changes this as follows: "none" will lead to no action, "offCmd" means "use off command", "onCmd" will lead to execution of the "on command". Delete the attribute to get back to default behaviour.<br>
    <br>
        <b>Examples</b>
        <ul>
          <li><code>attr ZufallsTimerZ disableCondCmd offCmd</code></li>
        </ul>
      </li><br><br>
      <li>
        <code>disabledForIntervals</code><br>
        See <a href="#disabledForIntervals">commandref for at - disabledForIntervals</a>
      </li><br>
      <li>
        <code>onCmd, offCmd</code><br>
        Setting the on-/offCmd changes the command sent to the device. Standard is: "set &lt;device&gt; on". The device can be specified by a @.<br>
        <br>
        <b>Examples</b>
        <ul>
          <li><code>
            attr Timer oncmd  {fhem("set @ on-for-timer 14")}
          </code></li>
          <br>NOTE: using on-for-timer commands might lead to irritating results!
          <li><code>
            attr Timer offCmd {fhem("set @ off 16")}
          </code></li>
          <li><code>
            attr Timer oncmd  set @ pct 65
          </code></li>
          <li><code>
            attr Timer offCmd set @ off 12
          </code></li>
        </ul>
        The decision to switch on or off depends on the state of the device. For $featurelevel 6.0 and earlier, or if no offState attribute is set, this is evaluated by the funktion Value(&lt;device&gt;). Value() must evaluate one of the values "on" or "off". The behavior of devices that do not evaluate one of those values can be corrected by defining a stateFormat:<br>
        <code>
           attr stateFormat EDIPlug_01 {(ReadingsVal("EDIPlug_01","state","nF") =~ m/(ON|on)/i)  ? "on" : "off" }
        </code><br>
        if a devices Value() funktion does not evalute to on or off(like WLAN-Steckdose von Edimax) you get the message:<br>
        <code>
           [EDIPlug] result of function Value(EDIPlug_01) must be 'on' or 'off'
        </code>
        NOTE: From $featurelevel 6.1 on or if attribute offState is set, the funktion ReadingsVal(&lt;device&gt;,"state",undef) will be used instead of Value(). If "state" of the device exactly matches the regex provided in the attribute "offState" or lowercase of "state" contains a part matching to "off", device will be considered to be "off" (or "on" in all other cases respectively).
      </li>
      <li>
        <code>offState</code><br>
        Setting this attribute, evaluation of on of will use ReadingsVal(&lt;device&gt;,"state",undef) instead of Value(). The attribute value will be used as regex, so e.g. also "dim00" beside "off" may be considered as indication the device is "off". You may use an optional second parameter (space separated) to check a different reading, e.g. for a HUEDevice-group "0 any_on" might be usefull.
      <br>NOTE: This will be default behaviour starting with featurelevel 6.1.
      </li>
      <br>
      <li>
        <a href="#readingFnAttributes">
          <u><code>readingFnAttributes</code></u>
        </a>
      </li>
      <br>
      <li>
        <code>runonce</code><br>
        Deletes the RandomTimer device after <b>timespec_stop</b> is reached.
        <br>
      </li>
      <br>
      <li>
        <code>switchmode</code><br>
        Setting the switchmode you can influence the behavior of switching on/off. The parameter has the Format 999/999 and the default ist 800/200. The values are in "per mill". The first parameter sets the value of the probability that the device will be switched on when the device is off. The second parameter sets the value of the probability that the device will be switched off when the device is on.<br>
        <br>
        <b>Example</b>
        <ul>
          <li><code>attr ZufallsTimerZ switchmode 400/400</code></li>
        </ul>
      </li>
    </ul>
  </ul>
</div>

=end html

=for :application/json;q=META.json 98_RandomTimer.pm
{
   "abstract" : "imitates the random switch functionality of a timer clock (FS20 ZSU)",
   "x_lang" : {
      "de" : {
         "abstract" : "bildet die Zufallsfunktion einer Zeitschaltuhr nach"
      }
   },
   "keywords" : [
   ],
   "prereqs" : {
      "runtime" : {
         "requires" : {
            "Time::HiRes" : "0",
            "Time::Local" : "0",
            "strict" : "0",
            "warnings" : "0"
         }
      }
   }
}
=end :application/json;q=META.json

=cut

# $Id$
##############################################################################
#
#     RESIDENTStk.pm
#     Additional functions for 10_RESIDENTS.pm, 20_ROOMMATE.pm, 20_GUEST.pm
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
# Version: 1.0.1
#
# Version History:
# - 1.0.0 - 2015-03-11
# -- First release
#
##############################################################################

#####################################
# PRE-DEFINITION: wakeuptimer
#------------------------------------
#

#
# Enslave DUMMY device to be used for alarm clock
#
sub RESIDENTStk_wakeupSet($$) {
    my ( $NAME, $notifyValue ) = @_;
    my $VALUE;

    # filter non-registered notifies
    my @notify = split / /, $notifyValue;
    if ( lc( $notify[0] ) !~ /off|nextrun|stop|reset|auto|([0-9]{2}:[0-9]{2})/ )
    {
        Log3 $NAME, 5,
            "RESIDENTStk $NAME: received unspecified notify '"
          . $notify[0]
          . "' - nothing to do";
        return;
    }
    elsif ( lc( $notify[0] ) eq "nextrun" ) {
        return if ( !defined( $notify[1] ) );
        $VALUE = $notify[1];
    }
    else {
        $VALUE = $notify[0];
    }

    my $wakeupMacro         = AttrVal( $NAME, "wakeupMacro",         0 );
    my $wakeupDefaultTime   = AttrVal( $NAME, "wakeupDefaultTime",   0 );
    my $wakeupAtdevice      = AttrVal( $NAME, "wakeupAtdevice",      0 );
    my $wakeupUserdevice    = AttrVal( $NAME, "wakeupUserdevice",    0 );
    my $wakeupDays          = AttrVal( $NAME, "wakeupDays",          0 );
    my $wakeupResetdays     = AttrVal( $NAME, "wakeupResetdays",     0 );
    my $wakeupOffset        = AttrVal( $NAME, "wakeupOffset",        0 );
    my $wakeupResetSwitcher = AttrVal( $NAME, "wakeupResetSwitcher", 0 );
    my $wakeupUserdevice    = AttrVal( $NAME, "wakeupUserdevice",    0 );
    my $room                = AttrVal( $NAME, "room",                0 );
    my $userattr            = AttrVal( $NAME, "userattr",            0 );
    my $lastRun = ReadingsVal( $NAME, "lastRun", "07:00" );
    my $nextRun = ReadingsVal( $NAME, "nextRun", "07:00" );
    my $running = ReadingsVal( $NAME, "running", 0 );
    my $macroName = "Macro_" . $NAME;
    my $atName    = "at_" . $NAME;

    # check for required userattr attribute
    my $userattributes =
"wakeupOffset:slider,0,1,120 wakeupDefaultTime:OFF,00:00,00:15,00:30,00:45,01:00,01:15,01:30,01:45,02:00,02:15,02:30,02:45,03:00,03:15,03:30,03:45,04:00,04:15,04:30,04:45,05:00,05:15,05:30,05:45,06:00,06:15,06:30,06:45,07:00,07:15,07:30,07:45,08:00,08:15,08:30,08:45,09:00,09:15,09:30,09:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45 wakeupMacro wakeupUserdevice wakeupAtdevice wakeupResetSwitcher wakeupResetdays:multiple-strict,0,1,2,3,4,5,6 wakeupDays:multiple-strict,0,1,2,3,4,5,6";
    if ( !$userattr || $userattr ne $userattributes ) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: adjusting dummy device for required attribute userattr";
        fhem "attr $NAME userattr $userattributes";
    }

    # check for required userdevice attribute
    if ( !$wakeupUserdevice ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - set attribute wakeupUserdevice before running wakeup function!";
    }
    elsif ( !defined( $defs{$wakeupUserdevice} ) ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - user device $wakeupUserdevice does not exist!";
    }
    elsif ($defs{$wakeupUserdevice}{TYPE} ne "RESIDENTS"
        && $defs{$wakeupUserdevice}{TYPE} ne "ROOMMATE"
        && $defs{$wakeupUserdevice}{TYPE} ne "GUEST" )
    {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - defined user device '$wakeupUserdevice' is not a RESIDENTS, ROOMMATE or GUEST device!";
    }

    # check for required wakeupMacro attribute
    if ( !$wakeupMacro ) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: adjusting dummy device for required attribute wakeupMacro";
        fhem "attr $NAME wakeupMacro $macroName";
        $wakeupMacro = $macroName;
    }
    if ( !defined( $defs{$wakeupMacro} ) ) {
        my $wakeUpMacroTemplate = "{\
#\
# This is an example wake-up program running within a period of 30 minutes:\
# - drive shutters upwards slowly\
# - light up a HUE bulb from 2000K to 6500K\
# - have some voice notifications via SONOS\
# - have some wake-up chill music via SONOS during program run\
#\
# Available wake-up variables:\
# 1. \$EVTPART0 -> start or stop\
# 2. \$EVTPART1 -> target wake-up time\
# 2. \$EVTPART2 -> wake-up begin offset time\
#\
\
#------------------------------------------------------------------------------------\
# DELETE TEMP. AT-COMMANDS POTENTIALLY CREATED EARLIER BY THIS SCRIPT\
# Executed for start to cleanup in case this wake-up automation is re-started.\
# Executed for stop to cleanup in case the user ends this automation earlier.\
#\
for (my \$i=1;; \$i <= 10;; \$i++) {\
	if (defined(\$defs{\"atTmp_\".\$i.\"_\".\$NAME})) {\
    	fhem \"delete atTmp_\".\$i.\"_\".\$NAME;;\
	}\
}\
\
#------------------------------------------------------------------------------------\
# BEGIN WAKE-UP PROGRAM\
# Run first automation commands and create temp. at-devices for lagging actions.\
#\
if (\$EVTPART0 eq \"start\") {\
	Log3 \$NAME, 3, \"\$NAME: Wake-up program started for \".\$EVTPART1;;\
\
	fhem \"set BR_FloorLamp pct 1 : ct 2000 : transitiontime 0;; set BR_FloorLamp pct 90 : ct 5600 : transitiontime 1770\";;\
\
	fhem \"define atTmp_1_\$NAME at +00:10:00 set BR_Shutter pct 20\";;\
	fhem \"define atTmp_2_\$NAME at +00:20:00 set BR_Shutter pct 40\";;\
	fhem \"define atTmp_4_\$NAME at +00:30:00 set Sonos_Bedroom Speak 33 de |Hint| Es ist \".\$EVTPART1.\" Uhr, Zeit zum aufstehen!;;;; set BR_FloorLamp pct 100 60;;;; sleep 10;;;; set BR_Shutter pct 60;;;; set Sonos_Bedroom volume 10 10\";;\
\
	# Working days only (Mon-Fri except bank holidays): do enforced wake-up actions\
	if (!\$we) {\
		Log (4, \"\$NAME: planning enforced wake-up\");;\
		fhem \"define atTmp_3_\$NAME at +00:25:00 set Sonos_Bedroom volume 2;;;; set Sonos_Bedroom Shuffle 1;;;; set Sonos_Bedroom StartFavourite Morning%%20Sounds;;;; sleep 4;;;; set Sonos_Bedroom volume 8 290\";;\
	}\
}\
\
#------------------------------------------------------------------------------------\
# END WAKE-UP PROGRAM (OPTIONAL)\
# Put some post wake-up tasks here like reminders after the actual wake-up period.\
#\
if (\$EVTPART0 eq \"stop\") {\
	Log3 \$NAME, 3, \"\$NAME: Wake-up program ended for \".\$EVTPART1;;\
\
	# Working days only (Mon-Fri except bank holidays): after only a small additional nap,\
	# get you out of bed :-)\
	# An additional notify for user state 'awoken' may take further actions\
	# and change to state 'home' afterwards.\
	if (!\$we) {\
		fhem \"define atTmp_5_\$NAME at +00:05:00 set rr_Julian:FILTER=STATE=asleep awoken\";;\
\
	# At weekend and bank holidays: be jentle and just set user state to 'home' after some\
	# additional long nap time\
	} else {\
		fhem \"define atTmp_5_\$NAME at +01:30:00 set rr_Julian:FILTER=STATE=asleep home\";;\
    }\
}\
\
}\
";

        Log3 $NAME, 3,
          "RESIDENTStk $NAME: new notify macro device $wakeupMacro created";
        fhem "define $wakeupMacro notify $wakeupMacro $wakeUpMacroTemplate";
        fhem
          "attr $wakeupMacro comment Macro auto-created by RESIDENTS Toolkit";
        if ($room) { fhem "attr $wakeupMacro room $room" }
    }
    elsif ( $defs{$wakeupMacro}{TYPE} ne "notify" ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - defined macro device '$wakeupMacro' is not a notify device!";
    }

    # check for required wakeupAtdevice attribute
    if ( !$wakeupAtdevice ) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: adjusting dummy device for required attribute wakeupAtdevice";
        fhem "attr $NAME wakeupAtdevice $atName";
        $wakeupAtdevice = $atName;
    }
    if ( !defined( $defs{$wakeupAtdevice} ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: new at-device $wakeupAtdevice created";
        fhem
"define $wakeupAtdevice at *{RESIDENTStk_wakeupGetBegin(\"$NAME\")} { RESIDENTStk_wakeupRun(\"$NAME\") }";
        fhem "attr $wakeupAtdevice comment Auto-created by RESIDENTS Toolkit";
        if ($room) { fhem "attr $wakeupAtdevice room $room" }
    }
    elsif ( $defs{$wakeupAtdevice}{TYPE} ne "at" ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - defined at-device '$wakeupAtdevice' is not an at-device!";
    }

    # stop
    #
    if ( $VALUE eq "stop" && $running ) {
        Log3 $NAME, 4, "RESIDENTStk $NAME: stopping wake-up program";
        fhem "setreading $NAME running 0";
        fhem "set $NAME nextRun $nextRun";

        # trigger macro again so it may clean up it's stuff.
        # use $EVTPART1 to check
        if ( !$wakeupMacro ) {
            Log3 $NAME, 2, "RESIDENTStk $NAME: missing attribute wakeupMacro";
        }
        elsif ( !defined( $defs{$wakeupMacro} ) ) {
            Log3 $NAME, 2,
"RESIDENTStk $NAME: notify macro $wakeupMacro not found - no wakeup actions defined!";
        }
        elsif ( $defs{$wakeupMacro}{TYPE} ne "notify" ) {
            Log3 $NAME, 2,
              "RESIDENTStk $NAME: device $wakeupMacro is not of type notify";
        }
        else {
            if ( defined( $notify[1] ) ) {
                Log3 $NAME, 4,
"RESIDENTStk $NAME: trigger $wakeupMacro (running=0,forced-stop=0)";
                fhem "trigger $wakeupMacro stop $lastRun $wakeupOffset";
            }
            else {
                Log3 $NAME, 4,
"RESIDENTStk $NAME: trigger $wakeupMacro (running=0,forced-stop=1)";
                fhem "trigger $wakeupMacro forced-stop $lastRun $wakeupOffset";
            }
            fhem "setreading $wakeupUserdevice:FILTER=wakeup=1 wakeup 0";

            my $wakeupStopAtdevice = $wakeupAtdevice . "_stop";
            if ( defined( $defs{$wakeupStopAtdevice} ) ) {
                fhem "delete $wakeupStopAtdevice";
            }
        }
        return;
    }

    # auto or reset
    #
    elsif ( $VALUE eq "auto" || $VALUE eq "reset" ) {
        my $resetTime = ReadingsVal( $NAME, "lastRun", 0 );
        if ($wakeupDefaultTime) {
            $resetTime = $wakeupDefaultTime;
        }

        if ( $resetTime
            && !( $VALUE eq "auto" && lc($resetTime) eq "off" ) )
        {
            fhem "set $NAME:FILTER=state!=$resetTime nextRun $resetTime";
        }
        elsif ( $VALUE eq "reset" ) {
            Log3 $NAME, 4,
"RESIDENTStk $NAME: no default value specified in attribute wakeupDefaultTime, just keeping setting OFF";
            fhem "set $NAME:FILTER=state!=OFF nextRun OFF";
        }

        return;
    }

    # set new wakeup value
    elsif (( lc($VALUE) eq "off" || $VALUE =~ /^([0-9]{2}:[0-9]{2})$/ )
        && defined( $defs{$wakeupAtdevice} )
        && $defs{$wakeupAtdevice}{TYPE} eq "at" )
    {
        Log3 $NAME, 4, "RESIDENTStk $NAME: New wake-up time: $VALUE";

        readingsBeginUpdate( $defs{$NAME} );
        readingsBulkUpdate( $defs{$NAME}, "state", $VALUE )
          if ( ReadingsVal( $NAME, "state", 0 ) ne $VALUE );
        readingsBulkUpdate( $defs{$NAME}, "nextRun", $VALUE )
          if ( ReadingsVal( $NAME, "nextRun", 0 ) ne $VALUE );
        readingsEndUpdate( $defs{$NAME}, 1 );

        fhem
"set $wakeupAtdevice modifyTimeSpec {RESIDENTStk_wakeupGetBegin(\"$NAME\")}";

        if ( !$running ) {
            fhem "setreading $wakeupUserdevice:FILTER=wakeup!=0 wakeup 0";
        }
    }

    return undef;
}

#
# Get current wakeup begin
#
sub RESIDENTStk_wakeupGetBegin($) {
    my ($NAME) = @_;
		my $defaultBeginTime = "05:00";
    my $wakeupDefaultTime = AttrVal( $NAME, "wakeupDefaultTime", $defaultBeginTime );
    my $nextRun = ReadingsVal( $NAME, "nextRun", $wakeupDefaultTime );
    my $wakeupTime = (
        lc($nextRun) ne "off"
        ? $nextRun
        : ( lc($wakeupDefaultTime) ne "off" ? $wakeupDefaultTime : $defaultBeginTime ) );
    my $wakeupOffset = AttrVal( $NAME, "wakeupOffset", 0 );
    my $return;

    # Recalculate new wake-up value
    if ( $wakeupTime =~ /^([0-9]{2}:[0-9]{2})$/ ) {
        my @time = split /:/, $wakeupTime;

        my $seconds = $time[0] * 3600 + $time[1] * 60 - $wakeupOffset * 60;
        if ( $seconds < 0 ) { $seconds = 86400 + $seconds }

        $return = RESIDENTStk_sec2time($seconds);
    }

    return $return;
}

#
# Use DUMMY device to run wakup event
#
sub RESIDENTStk_wakeupRun($) {
    my ($NAME) = @_;

    my $wakeupMacro         = AttrVal( $NAME, "wakeupMacro",         0 );
    my $wakeupDefaultTime   = AttrVal( $NAME, "wakeupDefaultTime",   0 );
    my $wakeupAtdevice      = AttrVal( $NAME, "wakeupAtdevice",      0 );
    my $wakeupUserdevice    = AttrVal( $NAME, "wakeupUserdevice",    0 );
    my $wakeupDays          = AttrVal( $NAME, "wakeupDays",          0 );
    my $wakeupResetdays     = AttrVal( $NAME, "wakeupResetdays",     0 );
    my $wakeupOffset        = AttrVal( $NAME, "wakeupOffset",        0 );
    my $wakeupResetSwitcher = AttrVal( $NAME, "wakeupResetSwitcher", 0 );
    my $lastRun = ReadingsVal( $NAME, "lastRun", "07:00" );
    my $nextRun = ReadingsVal( $NAME, "nextRun", "07:00" );
    my $running = ReadingsVal( $NAME, "running", 0 );
    my $wakeupUserdeviceWakeup = ReadingsVal( $wakeupUserdevice, "wakeup", 0 );
    my $room = AttrVal( $NAME, "room", 0 );
    my $running = 0;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);

    my @days = ($wday);
    if ($wakeupDays) {
        @days = split /,/, $wakeupDays;
    }

    my @rdays = ($wday);
    if ($wakeupResetdays) {
        @rdays = split /,/, $wakeupResetdays;
    }

    if ( !defined( $defs{$NAME} ) ) {
        return "$NAME: Non existing device";
    }
    elsif ( lc($nextRun) eq "off" ) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: alarm set to OFF - not triggering wake-up program";
    }
    elsif ( !$wakeupUserdevice ) {
        return "$NAME: missing attribute wakeupUserdevice";
    }
    elsif ( !defined( $defs{$wakeupUserdevice} ) ) {
        return "$NAME: Non existing wakeupUserdevice $wakeupUserdevice";
    }
    elsif ($defs{$wakeupUserdevice}{TYPE} ne "ROOMMATE"
        && $defs{$wakeupUserdevice}{TYPE} ne "GUEST" )
    {
        return
          "$NAME: device $wakeupUserdevice is not of type ROOMMATE or GUEST";
    }
    elsif ( $defs{$wakeupUserdevice}{TYPE} eq "GUEST"
        && ReadingsVal( $wakeupUserdevice, "state", "" ) eq "none" )
    {
        fhem "set $NAME nextRun OFF";
        return;
    }
    elsif ($wday ~~ @days
        && ReadingsVal( $wakeupUserdevice, "state", "" ) ne "absent"
        && ReadingsVal( $wakeupUserdevice, "state", "" ) ne "gone"
        && ReadingsVal( $wakeupUserdevice, "state", "" ) ne "gotosleep"
        && ReadingsVal( $wakeupUserdevice, "state", "" ) ne "awoken" )
    {
        if ( !$wakeupMacro ) {
            return "$NAME: missing attribute wakeupMacro";
        }
        elsif ( !defined( $defs{$wakeupMacro} ) ) {
            return
"$NAME: notify macro $wakeupMacro not found - no wakeup actions defined!";
        }
        elsif ( $defs{$wakeupMacro}{TYPE} ne "notify" ) {
            return "$NAME: device $wakeupMacro is not of type notify";
        }
        elsif ($wakeupUserdeviceWakeup) {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: Another wake-up program is already being executed, won't trigger $wakeupMacro";
        }
        else {
            Log3 $NAME, 4,
              "RESIDENTStk $NAME: trigger $wakeupMacro (running=1)";
            fhem "trigger $wakeupMacro start $nextRun $wakeupOffset";
            fhem "setreading $wakeupUserdevice wakeup 1";
            fhem "setreading $NAME lastRun $nextRun";

            if ( $wakeupOffset > 0 ) {
                my $wakeupStopAtdevice = $wakeupAtdevice . "_stop";

                if ( defined( $defs{$wakeupStopAtdevice} ) ) {
                    fhem "delete $wakeupStopAtdevice";
                }

                Log3 $NAME, 4,
"RESIDENTStk $NAME: created at-device $wakeupStopAtdevice to stop wake-up program in $wakeupOffset minutes";
                fhem "define $wakeupStopAtdevice at +"
                  . RESIDENTStk_sec2time( $wakeupOffset * 60 + 1 )
                  . " set $NAME:FILTER=running=1 stop triggerpost";
                fhem
"attr $wakeupStopAtdevice comment Auto-created by RESIDENTS Toolkit";
            }

            $running = 1;
        }
    }

    my $doReset = 1;
    if (   $wakeupResetSwitcher
        && defined( $defs{$wakeupResetSwitcher} )
        && $defs{$wakeupResetSwitcher}{TYPE} eq "dummy"
        && ReadingsVal( $wakeupResetSwitcher, "state", 0 ) eq "off" )
    {
        $doReset = 0;
    }

    if ( $wakeupDefaultTime && $wday ~~ @rdays && $doReset ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: Resetting based on wakeupDefaultTime";
        fhem
"set $NAME:FILTER=state!=$wakeupDefaultTime nextRun $wakeupDefaultTime";
    }

    if ( $running && $wakeupOffset > 0 ) {
        readingsBeginUpdate( $defs{$NAME} );
        readingsBulkUpdate( $defs{$NAME}, "running", "1" )
          if ( ReadingsVal( $NAME, "running", 0 ) ne "1" );
        readingsBulkUpdate( $defs{$NAME}, "state", "running" )
          if ( ReadingsVal( $NAME, "state", 0 ) ne "running" );
        readingsEndUpdate( $defs{$NAME}, 1 );
    }

    return undef;
}

#####################################
# FHEM CODE INJECTION
#------------------------------------
#

#
# AttFn for enslaved dummy devices
#
sub RESIDENTStk_AttrFnDummy(@) {
    my ( $cmd, $name, $aName, $aVal ) = @_;

    # set attribute
    if ( $cmd eq "set" ) {

        # wakeupResetSwitcher
        if ( $aName eq "wakeupResetSwitcher" ) {
            if ( !defined( $defs{$aVal} ) ) {
                my $alias = AttrVal( $name, "alias", 0 );
                my $group = AttrVal( $name, "group", 0 );
                my $room  = AttrVal( $name, "room",  0 );

                fhem "define $aVal dummy";
                fhem "attr $aVal comment Auto-created by RESIDENTS Toolkit";
                if ($alias) {
                    fhem "attr $aVal alias $alias Reset";
                }
                else {
                    fhem "attr $aVal alias Wake-up Timer Reset";
                }
                fhem
"attr $aVal devStateIcon auto:time_automatic:off off:time_manual_mode:auto";
                if ($group) { fhem "attr $aVal group $group" }
                fhem "attr $aVal icon refresh";
                if ($room) { fhem "attr $aVal room $room" }
                fhem "attr $aVal setList state:auto,off";
                fhem "attr $aVal webCmd state";
                fhem "set $aVal auto";

                Log3 $name, 3,
                  "RESIDENTStk $name: new slave dummy device $aVal created";
            }
            elsif ( $defs{$aVal}{TYPE} ne "dummy" ) {
                Log3 $name, 3,
"RESIDENTStk $name: Defined device name in attr $aName is not a dummy device";
                return "Existing device $aVal is not a dummy!";
            }
        }

    }

    return undef;
}

#####################################
# GENERAL FUNCTIONS USED IN RESIDENTS, ROOMMATE, GUEST
#------------------------------------
#

sub RESIDENTStk_TimeDiff ($$;$) {
    my ( $datetimeNow, $datetimeOld, $format ) = @_;

    my $timestampNow = RESIDENTStk_Datetime2Timestamp($datetimeNow);
    my $timestampOld = RESIDENTStk_Datetime2Timestamp($datetimeOld);
    my $timeDiff     = $timestampNow - $timestampOld;

    # return seconds
    return int( $timeDiff + 0.5 )
      if ( defined($format) && $format eq "sec" );

    # return minutes
    return int( $timeDiff / 60 + 0.5 )
      if ( defined($format) && $format eq "min" );

    # return human readable format
    return RESIDENTStk_sec2time( int( $timeDiff + 0.5 ) );
}

sub RESIDENTStk_Datetime2Timestamp($) {
    my ($datetime) = @_;

    my ( $date, $time, $y, $m, $d, $hour, $min, $sec, $timestamp );

    ( $date, $time ) = split( ' ', $datetime );
    ( $y,    $m,   $d )   = split( '-', $date );
    ( $hour, $min, $sec ) = split( ':', $time );
    $m -= 01;
    $timestamp = timelocal( $sec, $min, $hour, $d, $m, $y );

    return $timestamp;
}

sub RESIDENTStk_sec2time($) {
    my ($sec) = @_;

    # return human readable format
    my $hours = ( abs($sec) < 3600 ? 0 : int( abs($sec) / 3600 ) );
    $sec -= ( $hours == 0 ? 0 : ( $hours * 3600 ) );
    my $minutes = ( abs($sec) < 60 ? 0 : int( abs($sec) / 60 ) );
    my $seconds = abs($sec) % 60;

    $hours   = "0" . $hours   if ( $hours < 10 );
    $minutes = "0" . $minutes if ( $minutes < 10 );
    $seconds = "0" . $seconds if ( $seconds < 10 );

    return "$hours:$minutes:$seconds";
}

sub RESIDENTStk_InternalTimer($$$$$) {
    my ( $modifier, $tim, $callback, $hash, $waitIfInitNotDone ) = @_;

    my $mHash;
    if ( $modifier eq "" ) {
        $mHash = $hash;
    }
    else {
        my $timerName = $hash->{NAME} . "_" . $modifier;
        if ( exists( $hash->{TIMER}{$timerName} ) ) {
            $mHash = $hash->{TIMER}{$timerName};
        }
        else {
            $mHash = {
                HASH     => $hash,
                NAME     => $hash->{NAME} . "_" . $modifier,
                MODIFIER => $modifier
            };
            $hash->{TIMER}{$timerName} = $mHash;
        }
    }
    InternalTimer( $tim, $callback, $mHash, $waitIfInitNotDone );
}

sub RESIDENTStk_RemoveInternalTimer($$) {
    my ( $modifier, $hash ) = @_;

    my $timerName = $hash->{NAME} . "_" . $modifier;
    if ( $modifier eq "" ) {
        RemoveInternalTimer($hash);
    }
    else {
        my $mHash = $hash->{TIMER}{$timerName};
        if ( defined($mHash) ) {
            delete $hash->{TIMER}{$timerName};
            RemoveInternalTimer($mHash);
        }
    }
}

1;

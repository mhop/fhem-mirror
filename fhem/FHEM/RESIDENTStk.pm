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
# Version: 1.0.2
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
    if (
        lc( $notify[0] ) !~
        /^(off|nextrun|trigger|start|stop|end|reset|auto|([0-9]{2}:[0-9]{2}))$/
      )
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

    my $wakeupMacro         = AttrVal( $NAME,    "wakeupMacro",         0 );
    my $wakeupDefaultTime   = AttrVal( $NAME,    "wakeupDefaultTime",   0 );
    my $wakeupAtdevice      = AttrVal( $NAME,    "wakeupAtdevice",      0 );
    my $wakeupUserdevice    = AttrVal( $NAME,    "wakeupUserdevice",    0 );
    my $wakeupDays          = AttrVal( $NAME,    "wakeupDays",          "" );
    my $wakeupHolidays      = AttrVal( $NAME,    "wakeupHolidays",      0 );
    my $wakeupResetdays     = AttrVal( $NAME,    "wakeupResetdays",     "" );
    my $wakeupOffset        = AttrVal( $NAME,    "wakeupOffset",        0 );
    my $wakeupEnforced      = AttrVal( $NAME,    "wakeupEnforced",      0 );
    my $wakeupResetSwitcher = AttrVal( $NAME,    "wakeupResetSwitcher", 0 );
    my $holidayDevice       = AttrVal( "global", "holiday2we",          0 );
    my $room                = AttrVal( $NAME,    "room",                0 );
    my $userattr            = AttrVal( $NAME,    "userattr",            0 );
    my $lastRun = ReadingsVal( $NAME, "lastRun", "07:00" );
    my $nextRun = ReadingsVal( $NAME, "nextRun", "07:00" );
    my $running = ReadingsVal( $NAME, "running", 0 );
    my $wakeupUserdeviceState = ReadingsVal( $wakeupUserdevice, "state", 0 );
    my $atName                = "at_" . $NAME;
    my $wdNameGotosleep       = "wd_" . $wakeupUserdevice . "_gotosleep";
    my $wdNameAsleep          = "wd_" . $wakeupUserdevice . "_asleep";
    my $wdNameAwoken          = "wd_" . $wakeupUserdevice . "_awoken";
    my $macroName             = "Macro_" . $NAME;
    my $macroNameGotosleep    = "Macro_" . $wakeupUserdevice . "_gotosleep";
    my $macroNameAsleep       = "Macro_" . $wakeupUserdevice . "_asleep";
    my $macroNameAwoken       = "Macro_" . $wakeupUserdevice . "_awoken";

    # check for required userattr attribute
    my $userattributes =
"wakeupOffset:slider,0,1,120 wakeupDefaultTime:OFF,00:00,00:15,00:30,00:45,01:00,01:15,01:30,01:45,02:00,02:15,02:30,02:45,03:00,03:15,03:30,03:45,04:00,04:15,04:30,04:45,05:00,05:15,05:30,05:45,06:00,06:15,06:30,06:45,07:00,07:15,07:30,07:45,08:00,08:15,08:30,08:45,09:00,09:15,09:30,09:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45 wakeupMacro wakeupUserdevice wakeupAtdevice wakeupResetSwitcher wakeupResetdays:multiple-strict,0,1,2,3,4,5,6 wakeupDays:multiple-strict,0,1,2,3,4,5,6 wakeupHolidays:andHoliday,orHoliday,andNoHoliday,orNoHoliday wakeupEnforced:0,1,2 wakeupWaitPeriod:slider,0,1,360";
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
##=============================================================================\
## This is an example wake-up program running within a period of 30 minutes:\
## - drive shutters upwards slowly\
## - light up a HUE bulb from 2000K to 5600K\
## - have some voice notifications via SONOS\
## - have some wake-up chill music via SONOS during program run\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##\
## Available wake-up variables:\
## 1. \$EVTPART0 -> start or stop\
## 2. \$EVTPART1 -> target wake-up time\
## 3. \$EVTPART2 -> wake-up begin time considering wakeupOffset attribute\
## 4. \$EVTPART3 -> enforced wakeup yes=1,no=0 from wakeupEnforced attribute\
## 5. \$EVTPART4 -> device name of the user which called this macro\
## 6. \$EVTPART5 -> current state of user\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## DELETE TEMP. AT-COMMANDS POTENTIALLY CREATED EARLIER BY THIS SCRIPT\
## Executed for start to cleanup in case this wake-up automation is re-started.\
## Executed for stop to cleanup in case the user ends this automation earlier.\
##\
for (my \$i=1;; \$i <= 10;; \$i++) {\
	if (defined(\$defs{\"atTmp_\".\$i.\"_\".\$NAME})) {\
    	fhem \"delete atTmp_\".\$i.\"_\".\$NAME;;\
	}\
}\
\
##-----------------------------------------------------------------------------\
## BEGIN WAKE-UP PROGRAM\
## Run first automation commands and create temp. at-devices for lagging actions.\
##\
if (\$EVTPART0 eq \"start\") {\
	Log3 \$NAME, 3, \"\$NAME: Wake-up program started for \$EVTPART4 with target time \$EVTPART1. Current state: \$EVTPART5\";;\
\
#	fhem \"set BR_FloorLamp:FILTER=onoff=0 pct 1 : ct 2000 : transitiontime 0;; set BR_FloorLamp:FILTER=pct=1 pct 90 : ct 5600 : transitiontime 17700\";;\
\	
#	fhem \"define atTmp_1_\$NAME at +00:10:00 set BR_Shutter:FILTER=pct<20 pct 20\";;\
#	fhem \"define atTmp_2_\$NAME at +00:20:00 set BR_Shutter:FILTER=pct<40 pct 40\";;\
#	fhem \"define atTmp_4_\$NAME at +00:30:00 set Sonos_Bedroom Speak 33 de |Hint| Es ist \".\$EVTPART1.\" Uhr, Zeit zum aufstehen!;;;; set BR_FloorLamp:FILTER=pct<100 pct 100 60;;;; sleep 10;;;; set BR_Shutter:FILTER=pct<60 pct 60;;;; set Sonos_Bedroom:FILTER=Volume<10 Volume 10 10\";;\
\
	# if wake-up should be enforced\
	if (\$EVTPART3) {\
		Log (4, \"\$NAME: planning enforced wake-up\");;\
#		fhem \"define atTmp_3_\$NAME at +00:25:00 set Sonos_Bedroom:FILTER=Volume>4 Volume 4;;;; sleep 0.5;;;; set Sonos_Bedroom:FILTER=Shuffle=0 Shuffle 1;;;; sleep 0.5;;;; set Sonos_Bedroom StartFavourite Morning%20Sounds\";;\
#		fhem \"define atTmp_4_\$NAME at +00:26:00 set Sonos_Bedroom:FILTER=Volume<5 Volume 5\";;\
#		fhem \"define atTmp_5_\$NAME at +00:27:00 set Sonos_Bedroom:FILTER=Volume<6 Volume 6\";;\
#		fhem \"define atTmp_6_\$NAME at +00:28:00 set Sonos_Bedroom:FILTER=Volume<7 Volume 7\";;\
#		fhem \"define atTmp_7_\$NAME at +00:29:00 set Sonos_Bedroom:FILTER=Volume<8 Volume 8\";;\
	}\
}\
\
##-----------------------------------------------------------------------------\
## END WAKE-UP PROGRAM (OPTIONAL)\
## Put some post wake-up tasks here like reminders after the actual wake-up period.\
##\
## Note: Will only be run when program ends normally after minutes specified in wakeupOffset.\
##       If stop was user-forced by sending explicit set-command 'stop', this is not executed\
##       assuming the user does not want any further automation activities.\
##\
if (\$EVTPART0 eq \"stop\") {\
	Log3 \$NAME, 3, \"\$NAME: Wake-up program ended for \$EVTPART4 with target time \$EVTPART1. Current state: \$EVTPART5\";;\
\
	# if wake-up should be enforced, auto-change user state from 'asleep' to 'awoken'\
	# after a small additional nap to kick you out of bed if user did not confirm to be awake :-)\
	# An additional notify for user state 'awoken' may take further actions\
	# and change to state 'home' afterwards.\
	if (\$EVTPART3) {\
		fhem \"define atTmp_9_\$NAME at +00:05:00 set \$EVTPART4:FILTER=STATE=asleep awoken\";;\
\
	# Without enforced wake-up, be jentle and just set user state to 'home' after some\
	# additional long nap time\
	} else {\
		fhem \"define atTmp_9_\$NAME at +01:30:00 set \$EVTPART4:FILTER=STATE=asleep home\";;\
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
        fhem "attr $wakeupMacro room $room"
          if ($room);
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
"define $wakeupAtdevice at *{RESIDENTStk_wakeupGetBegin(\"$NAME\",\"$wakeupAtdevice\")} set $NAME trigger";
        fhem
"attr $wakeupAtdevice comment Auto-created by RESIDENTS Toolkit: trigger wake-up timer at specific time";
        fhem "attr $wakeupAtdevice room $room"
          if ($room);

        ########
        # (re)create other notify and watchdog templates
        # for ROOMMATE or GUEST devices

        # macro: gotosleep
        if ( $defs{$wakeupUserdevice}{TYPE} ne "RESIDENTS"
            && !defined( $defs{$macroNameGotosleep} ) )
        {
            my $templateGotosleep = "{\
##=============================================================================\
## This is an example macro when gettin' ready for bed.\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## LIGHT SCENE\
##\
\
## Dim up floor light\
#fhem \"set FL_Light:FILTER=pct=0 pct 20\";;\
\
## Dim down bright ceilling light in bedroom\
#fhem \"set BR_Light:FILTER=pct!=0 pct 0 5\";;\
\
## Dim up HUE floor lamp with very low color temperature\
#fhem \"set BR_FloorLamp ct 2000 : pct 80 : transitiontime 30\";;\
\
\
##-----------------------------------------------------------------------------\
## ENVIRONMENT SCENE\
##\
\
## Turn down shutter to 28%\
#fhem \"set BR_Shutter:FILTER=pct>28 pct 28\";;\
\
\
##-----------------------------------------------------------------------------\
## PLAY CHILLOUT MUSIC\
## via SONOS at Bedroom and Bathroom\
##\
\
## Stop playback bedroom's Sonos device might be involved in\
#fhem \"set Sonos_Bedroom:transportState=PLAYING stop;;\";;\
\
## Make Bedroom's and Bathroom's Sonos devices a single device\
## and do not touch other Sonos devices (this is why we use RemoveMember!)\
#fhem \"sleep 0.5;; set Sonos_Bedroom RemoveMember Sonos_Bedroom\";;\
#fhem \"sleep 1.0;; set Sonos_Bathroom RemoveMember Sonos_Bathroom\";;\
\
## Group Bedroom's and Bathroom's Sonos devices with Bedroom as master\
#fhem \"sleep 2.0;; set Sonos_Bedroom AddMember Sonos_Bathroom;; set Sonos_Bedroom:FILTER=Shuffle!=1 Shuffle 1;; set Sonos_Bedroom,Sonos_Bathroom:FILTER=Volume!=12 Volume 12\";;\
\
## Start music from playlist\
#fhem \"sleep 3.0;; set Sonos_Bedroom StartFavourite Evening%%20Chill\";;\
\
}";

            Log3 $NAME, 3,
"RESIDENTStk $NAME: new notify macro device $macroNameGotosleep created";
            fhem
"define $macroNameGotosleep notify $macroNameGotosleep $templateGotosleep";
            fhem
"attr $macroNameGotosleep comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when gettin' ready for bed";
            fhem "attr $macroNameGotosleep room $room"
              if ($room);
        }

        # wd: gotosleep
        if ( !defined( $defs{$wdNameGotosleep} ) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: new watchdog device $wdNameGotosleep created";
            fhem
"define $wdNameGotosleep watchdog $wakeupUserdevice:gotosleep 00:00:04 $wakeupUserdevice:(home|absent|gone|none|asleep|awoken) trigger $macroNameGotosleep;; setstate $wdNameGotosleep defined";
            fhem
"attr $wdNameGotosleep comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state gotosleep";
            fhem "attr $wdNameGotosleep room $room"
              if ($room);
        }

        # macro: asleep
        if ( $defs{$wakeupUserdevice}{TYPE} ne "RESIDENTS"
            && !defined( $defs{$macroNameAsleep} ) )
        {
            my $templateAsleep = "{\
##=============================================================================\
## This is an example macro when jumpin' into bed and start to sleep.\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## LIGHT SCENE\
##\
\
## In 15 seconds, turn off all lights in Bedroom using a structure\
#fhem \"sleep 15;; set g_BR_Lights [FILTER=state!=off] off\";;\
\
\
##-----------------------------------------------------------------------------\
## ENVIRONMENT SCENE\
##\
\
## In 12 seconds, close shutter if window is closed\
#if (ReadingsVal(\"BR_Window\",\"state\",0) eq \"closed\") {\
#	fhem \"sleep 12;; set BR_Shutter:FILTER=pct>0 close\";;\
\
## In 12 seconds, if window is not closed just make sure shutter is at least\
## at 28% to allow some ventilation\
#} else {\
#	fhem \"sleep 12;; set BR_Shutter:FILTER=pct>28 pct 28\";;\
#}\
\
\
##-----------------------------------------------------------------------------\
## PLAY WAKE-UP ANNOUNCEMENT\
## via SONOS at Bedroom and stop playback elsewhere\
##\
\
#my \$nextWakeup = ReadingsVal(\"rr_Bewohner\",\"nextWakeup\",0);;
#my \$text = \"|Hint| Bewohner, es ist kein Wecker gestellt. Du könntest verschlafen! Trotzdem eine gute Nacht.\";;
#if (\$nextWakeup ne \"OFF\") {
#	\$text = \"|Hint| Bewohner, dein Wecker ist auf \$nextWakeup Uhr gestellt. Gute Nacht und schlaf gut.\";;
#}
#fhem \"set Sonos_Bedroom RemoveMember Sonos_Bedroom;; sleep 0.5;; set Sonos_Bedroom Speak 28 de \$text\";;\
\
}";

            Log3 $NAME, 3,
"RESIDENTStk $NAME: new notify macro device $macroNameAsleep created";
            fhem
              "define $macroNameAsleep notify $macroNameAsleep $templateAsleep";
            fhem
"attr $macroNameAsleep comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when jumpin' into bed and start to sleep";
            fhem "attr $macroNameAsleep room $room"
              if ($room);
        }

        # wd: asleep
        if ( !defined( $defs{$wdNameAsleep} ) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: new watchdog device $wdNameAsleep created";
            fhem
"define $wdNameAsleep watchdog $wakeupUserdevice:asleep 00:00:04 $wakeupUserdevice:(home|absent|gone|none|gotosleep|awoken) trigger $macroNameAsleep;; setstate $wdNameAsleep defined";
            fhem
"attr $wdNameAsleep comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state asleep";
            fhem "attr $wdNameAsleep room $room"
              if ($room);
        }

        # macro: awoken
        if ( $defs{$wakeupUserdevice}{TYPE} ne "RESIDENTS"
            && !defined( $defs{$macroNameAwoken} ) )
        {
            my $templateAwoken = "{\
##=============================================================================\
## This is an example macro after confirming to be awake.\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## LIGHT SCENE\
##\
\
## Dim up HUE floor lamp to maximum with cold color temperature\
#fhem \"set BR_FloorLamp:FILTER=pct<100 pct 100 : ct 6500 : transitiontime 30\";;\
\
\
##-----------------------------------------------------------------------------\
## ENVIRONMENT SCENE\
##\
\
## In 22 seconds, turn up shutter at least until 60%\
#fhem \"sleep 22;; set BR_Shutter:FILTER=pct<60 60\";;\
\
\
##-----------------------------------------------------------------------------\
## RAMP-UP ALL MORNING STUFF\
##\
\
## Play morning announcement via SONOS at Bedroom\
#fhem \"set Sonos_Bedroom Stop;; set Sonos_Bedroom Speak 40 de |Hint| Guten Morgen, Bewohner.\";;\
\
## In 10 seconds, start webradio playback in Bedroom\
#fhem \"sleep 10;; set Sonos_Bedroom StartRadio /Charivari/;; sleep 2;; set Sonos_Bedroom Volume 15\";;\
\
## Make webradio stream available at Bathroom and\
## Kitchen 5 seonds after it started\
#fhem \"set Sonos_Bathroom,Sonos_Kitchen Volume 15;; sleep 15;; set Sonos_Bedroom AddMember Sonos_Bathroom;; set Sonos_Bedroom AddMember Sonos_Kitchen\";;\
\
}";

            Log3 $NAME, 3,
"RESIDENTStk $NAME: new notify macro device $macroNameAwoken created";
            fhem
              "define $macroNameAwoken notify $macroNameAwoken $templateAwoken";
            fhem
"attr $macroNameAwoken comment Auto-created by RESIDENTS Toolkit: FHEM commands to run after confirming to be awake";
            fhem "attr $macroNameAwoken room $room"
              if ($room);
        }

        # wd: awoken
        if ( !defined( $defs{$wdNameAwoken} ) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: new watchdog device $wdNameAwoken created";
            fhem
"define $wdNameAwoken watchdog $wakeupUserdevice:awoken 00:00:04 $wakeupUserdevice:(home|absent|gone|none|gotosleep|asleep) trigger $macroNameAwoken;; setstate $wdNameAwoken defined";
            fhem
"attr $wdNameAwoken comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state awoken";
            fhem "attr $wdNameAwoken room $room"
              if ($room);
        }

        ########
        # (re)create other notify and watchdog templates
        # for RESIDENT devices
        #

        my $RESIDENTGROUPS = "";
        if ( $defs{$wakeupUserdevice}{TYPE} eq "RESIDENTS" ) {
            $RESIDENTGROUPS = $wakeupUserdevice;
        }
        elsif (
            defined(
                $RESIDENTGROUPS = $defs{$wakeupUserdevice}{RESIDENTGROUPS}
            )
          )
        {
            $RESIDENTGROUPS = $defs{$wakeupUserdevice}{RESIDENTGROUPS};
        }

        for my $deviceName ( split /,/, $RESIDENTGROUPS ) {
            my $macroRNameGotosleep = "Macro_" . $deviceName . "_gotosleep";
            my $macroRNameAsleep    = "Macro_" . $deviceName . "_asleep";
            my $macroRNameAwoken    = "Macro_" . $deviceName . "_awoken";
            my $wdRNameGotosleep    = "wd_" . $deviceName . "_gotosleep";
            my $wdRNameAsleep       = "wd_" . $deviceName . "_asleep";
            my $wdRNameAwoken       = "wd_" . $deviceName . "_awoken";

            # macro: gotosleep
            if ( !defined( $defs{$macroRNameGotosleep} ) ) {
                my $templateGotosleep = "{\
##=============================================================================\
## This is an example macro when all residents are gettin' ready for bed.\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## HOUSE MODE\
## Enforce evening mode if we are still in day mode\
##\
\
#fhem \"set HouseMode:FILTER=state=day evening\";;\
\
\
##-----------------------------------------------------------------------------\
## LIGHT SCENE\
##\
\
## In 10 seconds, turn off lights in unused rooms using structures\
#fhem \"sleep 10;; set g_LR_Lights,g_KT_Lights [FILTER=state!=off] off\";;\
\
\
##-----------------------------------------------------------------------------\
## ENVIRONMENT SCENE\
##\
\
## Turn off all media devices in the Living Room\
#fhem \"set g_HSE_Media [FILTER=state!=off] off\";;\
\
}";

                Log3 $NAME, 3,
"RESIDENTStk $NAME: new notify macro device $macroRNameGotosleep created";
                fhem
"define $macroRNameGotosleep notify $macroRNameGotosleep $templateGotosleep";
                fhem
"attr $macroRNameGotosleep comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when all residents are gettin' ready for bed";
                fhem "attr $macroRNameGotosleep room $room"
                  if ($room);
            }

            # wd: gotosleep
            if ( !defined( $defs{$wdRNameGotosleep} ) ) {
                Log3 $NAME, 3,
"RESIDENTStk $NAME: new watchdog device $wdRNameGotosleep created";
                fhem
"define $wdRNameGotosleep watchdog $deviceName:gotosleep 00:00:03 $deviceName:(home|absent|gone|none|asleep|awoken) trigger $macroRNameGotosleep;; setstate $wdRNameGotosleep defined";
                fhem
"attr $wdRNameGotosleep comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state gotosleep";
                fhem "attr $wdRNameGotosleep room $room"
                  if ($room);
            }

            # macro: asleep
            if ( !defined( $defs{$macroRNameAsleep} ) ) {
                my $templateAsleep = "{\
##=============================================================================\
## This is an example macro when all residents are in their beds.\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## HOUSE MODE\
## Enforce night mode if we are still in evening mode\
##\
\
#fhem \"set HouseMode:FILTER=state=evening night\";;\
\
\
##-----------------------------------------------------------------------------\
## LIGHT SCENE\
##\
\
## In 20 seconds, turn off all lights in the house using structures\
#fhem \"sleep 20;; set g_HSE_Lights [FILTER=state!=off] off\";;\
\
\
##-----------------------------------------------------------------------------\
## ENVIRONMENT SCENE\
##\
\
## Stop playback at SONOS devices in shared rooms, e.g. Bathroom\
#fhem \"set Sonos_Bathroom:FILTER=transportState=PLAYING Stop\";;\
\
}";

                Log3 $NAME, 3,
"RESIDENTStk $NAME: new notify macro device $macroRNameAsleep created";
                fhem
"define $macroRNameAsleep notify $macroRNameAsleep $templateAsleep";
                fhem
"attr $macroRNameAsleep comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when all residents are in their beds";
                fhem "attr $macroRNameAsleep room $room"
                  if ($room);
            }

            # wd: asleep
            if ( !defined( $defs{$wdRNameAsleep} ) ) {
                Log3 $NAME, 3,
"RESIDENTStk $NAME: new watchdog device $wdNameAsleep created";
                fhem
"define $wdRNameAsleep watchdog $deviceName:asleep 00:00:03 $deviceName:(home|absent|gone|none|gotosleep|awoken) trigger $macroRNameAsleep;; setstate $wdRNameAsleep defined";
                fhem
"attr $wdRNameAsleep comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state asleep";
                fhem "attr $wdRNameAsleep room $room"
                  if ($room);
            }

            # macro: awoken
            if ( !defined( $defs{$macroRNameAwoken} ) ) {
                my $templateAwoken = "{\
##=============================================================================\
## This is an example macro when the first resident has confirmed to be awake\
##\
## Actual FHEM commands are commented out by default as they would need\
## to be adapted to your configuration.\
##=============================================================================\
\
##-----------------------------------------------------------------------------\
## HOUSE MODE\
## Enforce morning mode if we are still in night mode\
##\
\
#fhem \"set HouseMode:FILTER=state=night morning\";;\
\
\
##-----------------------------------------------------------------------------\
## LIGHT SCENE\
##\
\
## Turn on lights in the Kitchen already but set a timer to turn it off again\
#fhem \"set KT_CounterLight on-for-timer 6300\";;\
\
\
##-----------------------------------------------------------------------------\
## PREPARATIONS\
##\
\
## In 90 minutes, switch House Mode to 'day' and\
## play voice announcement via SONOS\
#if (!defined($defs{\"atTmp_HouseMode_day\"})) {\
#	fhem \"define atTmp_HouseMode_day at +01:30:00 {if (ReadingsVal(\\\"HouseMode\\\", \\\"state\\\", 0) ne \\\"day\\\") {fhem \\\"set Sonos_Kitchen Speak 40 de |Notification| Tagesmodus wird etabliert.;;;; sleep 10;;;; set HouseMode day\\\"}}\";;\
#}\
\
}";

                Log3 $NAME, 3,
"RESIDENTStk $NAME: new notify macro device $macroRNameAwoken created";
                fhem
"define $macroRNameAwoken notify $macroRNameAwoken $templateAwoken";
                fhem
"attr $macroRNameAwoken comment Auto-created by RESIDENTS Toolkit: FHEM commands to run after first resident confirmed to be awake";
                fhem "attr $macroRNameAwoken room $room"
                  if ($room);
            }

            # wd: awoken
            if ( !defined( $defs{$wdRNameAwoken} ) ) {
                Log3 $NAME, 3,
"RESIDENTStk $NAME: new watchdog device $wdNameAwoken created";
                fhem
"define $wdRNameAwoken watchdog $deviceName:awoken 00:00:04 $deviceName:(home|absent|gone|none|gotosleep|asleep) trigger $macroRNameAwoken;; setstate $wdRNameAwoken defined";
                fhem
"attr $wdRNameAwoken comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state awoken";
                fhem "attr $wdRNameAwoken room $room"
                  if ($room);
            }

        }

    }
    elsif ( $defs{$wakeupAtdevice}{TYPE} ne "at" ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - defined at-device '$wakeupAtdevice' is not an at-device!";
    }

    # verify holiday2we attribute
    if ($wakeupHolidays) {
        if ( !$holidayDevice ) {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: ERROR - wakeupHolidays set in this alarm clock but global attribute holiday2we not set!";
            return
"ERROR: wakeupHolidays set in this alarm clock but global attribute holiday2we not set!";
        }
        elsif ( !defined( $defs{$holidayDevice} ) ) {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: ERROR - global attribute holiday2we has reference to non-existing device $holidayDevice";
            return
"ERROR: global attribute holiday2we has reference to non-existing device $holidayDevice";
        }
        elsif ( $defs{$holidayDevice}{TYPE} ne "holiday" ) {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: ERROR - global attribute holiday2we seems to have invalid device reference - $holidayDevice is not of type 'holiday'";
            return
"ERROR: global attribute holiday2we seems to have invalid device reference - $holidayDevice is not of type 'holiday'";
        }
    }

    # start
    #
    if ( $VALUE eq "start" ) {
        RESIDENTStk_wakeupRun( $NAME, 1 );
    }

    # trigger
    #
    elsif ( $VALUE eq "trigger" ) {
        RESIDENTStk_wakeupRun($NAME);
    }

    # stop | end
    #
    elsif ( ( $VALUE eq "stop" || $VALUE eq "end" ) && $running ) {
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

            # conditional enforced wake-up:
            # only if actual wake-up time is not wakeupDefaultTime
            if (   $wakeupEnforced == 2
                && $wakeupDefaultTime
                && $wakeupDefaultTime ne $lastRun )
            {
                $wakeupEnforced = 1;
            }
            elsif ( $wakeupEnforced == 2 ) {
                $wakeupEnforced = 0;
            }

            if ( defined( $notify[1] ) || $VALUE eq "end" ) {
                Log3 $NAME, 4,
"RESIDENTStk $NAME: trigger $wakeupMacro stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";
                fhem
"trigger $wakeupMacro stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";
            }
            else {
                Log3 $NAME, 4,
"RESIDENTStk $NAME: trigger $wakeupMacro forced-stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";
                fhem
"trigger $wakeupMacro forced-stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";

                fhem "set $wakeupUserdevice:FILTER=state=asleep awoken";
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
        # Update wakeuptimer device
        #
        readingsBeginUpdate( $defs{$NAME} );
        if ( ReadingsVal( $NAME, "nextRun", 0 ) ne $VALUE ) {
            Log3 $NAME, 4, "RESIDENTStk $NAME: New wake-up time: $VALUE";
            readingsBulkUpdate( $defs{$NAME}, "nextRun", $VALUE );

            # Update at-device
            fhem
"set $wakeupAtdevice modifyTimeSpec {RESIDENTStk_wakeupGetBegin(\"$NAME\",\"$wakeupAtdevice\")}";
        }
        if ( ReadingsVal( $NAME, "state", 0 ) ne $VALUE && !$running ) {
            readingsBulkUpdate( $defs{$NAME}, "state", $VALUE );
        }
        elsif ( ReadingsVal( $NAME, "state", 0 ) ne "running" && $running ) {
            readingsBulkUpdate( $defs{$NAME}, "state", "running" );
        }
        readingsEndUpdate( $defs{$NAME}, 1 );

        # Update user device
        #
        readingsBeginUpdate( $defs{$wakeupUserdevice} );
        my ( $nextWakeupDev, $nextWakeup ) =
          RESIDENTStk_wakeupGetNext($wakeupUserdevice);
        if ( !$nextWakeupDev || !$nextWakeup ) {
            $nextWakeupDev = "none";
            $nextWakeup    = "OFF";
        }
        readingsBulkUpdate( $defs{$wakeupUserdevice},
            "nextWakeupDev", $nextWakeupDev )
          if ( ReadingsVal( $defs{$wakeupUserdevice}, "nextWakeupDev", 0 ) ne
            $nextWakeupDev );
        readingsBulkUpdate( $defs{$wakeupUserdevice},
            "nextWakeup", $nextWakeup )
          if ( ReadingsVal( $defs{$wakeupUserdevice}, "nextWakeup", 0 ) ne
            $nextWakeup );
        readingsEndUpdate( $defs{$wakeupUserdevice}, 1 );

    }

    return undef;
}

#
# Get current wakeup begin
#
sub RESIDENTStk_wakeupGetBegin($;$) {
    my ( $NAME, $wakeupAtdevice ) = @_;
    my $nextRun = ReadingsVal( $NAME, "nextRun", 0 );
    my $wakeupDefaultTime = AttrVal( $NAME, "wakeupDefaultTime", 0 );
    my $wakeupOffset      = AttrVal( $NAME, "wakeupOffset",      0 );
    my $wakeupTime;

    if ($atDeviceName) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: RESIDENTStk_wakeupGetBegin() run by at-device $atDeviceName";
    }

    # just give any valuable return to at-device
    # if wakeuptimer device does not exit anymore
    # and run self-destruction to clean up
    if ( !defined( $defs{$NAME} ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: this wake-up timer device does not exist anymore";
        my $atName = "at_" . $NAME;

        if (   $wakeupAtdevice
            && defined( $defs{$wakeupAtdevice} )
            && $defs{$wakeupAtdevice}{TYPE} eq "at" )
        {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: Cleaning up at-device $wakeupAtdevice (self-destruction)";
            fhem "sleep 1; delete $wakeupAtdevice";
        }
        elsif ( defined( $defs{$atName} )
            && $defs{$atName}{TYPE} eq "at" )
        {
            Log3 $NAME, 3, "RESIDENTStk $NAME: Cleaning up at-device $atName";
            fhem "sleep 1; delete $atName";
        }
        else {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: Could not automatically clean up at-device, please perform manual cleanup.";
        }

        return "05:00";
    }

    # use nextRun value if not OFF
    if ( $nextRun && lc($nextRun) ne "off" ) {
        $wakeupTime = $nextRun;
        Log3 $NAME, 4, "RESIDENTStk $NAME: wakeupGetBegin source: nextRun";
    }

    # use wakeupDefaultTime if present and not OFF
    elsif ( $wakeupDefaultTime && lc($wakeupDefaultTime) ne "off" ) {
        $wakeupTime = $wakeupDefaultTime;
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: wakeupGetBegin source: wakeupDefaultTime";
    }

    # Use a default value to ensure auto-reset at least once a day
    else {
        $wakeupTime = "05:00";
        Log3 $NAME, 4, "RESIDENTStk $NAME: wakeupGetBegin source: defaultValue";
    }

    # Recalculate new wake-up value
    my $seconds = RESIDENTStk_time2sec($wakeupTime) - $wakeupOffset * 60;
    if ( $seconds < 0 ) { $seconds = 86400 + $seconds }

    Log3 $NAME, 4,
"RESIDENTStk $NAME: wakeupGetBegin result: $wakeupTime = $seconds s - $wakeupOffset m = "
      . RESIDENTStk_sec2time($seconds);

    return RESIDENTStk_sec2time($seconds);
}

#
# Use DUMMY device to run wakup event
#
sub RESIDENTStk_wakeupRun($;$) {
    my ( $NAME, $forceRun ) = @_;

    my $wakeupMacro         = AttrVal( $NAME,    "wakeupMacro",         0 );
    my $wakeupDefaultTime   = AttrVal( $NAME,    "wakeupDefaultTime",   0 );
    my $wakeupAtdevice      = AttrVal( $NAME,    "wakeupAtdevice",      0 );
    my $wakeupUserdevice    = AttrVal( $NAME,    "wakeupUserdevice",    0 );
    my $wakeupDays          = AttrVal( $NAME,    "wakeupDays",          "" );
    my $wakeupHolidays      = AttrVal( $NAME,    "wakeupHolidays",      0 );
    my $wakeupResetdays     = AttrVal( $NAME,    "wakeupResetdays",     "" );
    my $wakeupOffset        = AttrVal( $NAME,    "wakeupOffset",        0 );
    my $wakeupEnforced      = AttrVal( $NAME,    "wakeupEnforced",      0 );
    my $wakeupResetSwitcher = AttrVal( $NAME,    "wakeupResetSwitcher", 0 );
    my $wakeupWaitPeriod    = AttrVal( $NAME,    "wakeupWaitPeriod",    360 );
    my $holidayDevice       = AttrVal( "global", "holiday2we",          0 );
    my $lastRun = ReadingsVal( $NAME, "lastRun", "06:00" );
    my $lastRunTimestamp =
      ReadingsTimestamp( $NAME, "lastRun", "1970-01-01 00:00:00" );
    my $nextRun = ReadingsVal( $NAME, "nextRun", "06:00" );
    my $nextRunTimestamp =
      ReadingsTimestamp( $NAME, "nextRun", "1970-01-01 00:00:00" );
    my $wakeupUserdeviceState  = ReadingsVal( $wakeupUserdevice, "state",  0 );
    my $wakeupUserdeviceWakeup = ReadingsVal( $wakeupUserdevice, "wakeup", 0 );
    my $room         = AttrVal( $NAME, "room", 0 );
    my $running      = 0;
    my $preventRun   = 0;
    my $holidayToday = "";

    if (   $wakeupHolidays
        && $holidayDevice
        && defined( $defs{$holidayDevice} )
        && $defs{$holidayDevice}{TYPE} eq "holiday" )
    {
        my $hdayTod = ReadingsVal( $holidayDevice, "state", "" );

        if   ( $hdayTod ne "none" && $hdayTod ne "" ) { $holidayToday = 1 }
        else                                          { $holidayToday = 0 }
    }
    else {
        $wakeupHolidays = 0;
    }

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime( time + $wakeupOffset * 60 );
    $mon += 01;

    $hour = "0" . $hour if ( $hour < 10 );
    $min  = "0" . $min  if ( $min < 10 );

    my $nowRun = $hour . ":" . $min;
    my $nowRunSec =
      RESIDENTStk_Datetime2Timestamp( $year . "-"
          . $mon . "-"
          . $mday . " "
          . $hour . ":"
          . $min . ":"
          . $sec );

    if ( $nextRun ne $nowRun ) {
        $lastRun = $nowRun;
        Log3 $NAME, 4, "RESIDENTStk $NAME: lastRun != nextRun = $lastRun";
    }
    else {
        $lastRun = $nextRun;
        Log3 $NAME, 4, "RESIDENTStk $NAME: lastRun = nextRun = $lastRun";
    }

    # do not run if wakeupWaitPeriod expiration was not reached yet
    my $expLastRun =
      RESIDENTStk_Datetime2Timestamp($lastRunTimestamp) - 1 +
      $wakeupOffset * 60 +
      $wakeupWaitPeriod * 60;
    my $expNextRun = RESIDENTStk_Datetime2Timestamp($nextRunTimestamp) - 1 +
      $wakeupWaitPeriod * 60;
    if (   $expLastRun > $nowRunSec
        && $expNextRun < time() )
    {
        $preventRun = 1;
    }
    else {
        Log3 $NAME, 5,
"RESIDENTStk $NAME: wakeupWaitPeriod threshold reached (expLastRun=$expLastRun nowRunSec=$nowRunSec expNextRun=$expNextRun localtime="
          . time() . ")";
    }

    my @days = ($wday);
    if ( $wakeupDays ne "" ) {
        @days = split /,/, $wakeupDays;
    }

    my @rdays = ($wday);
    if ( $wakeupResetdays ne "" ) {
        @rdays = split /,/, $wakeupResetdays;
    }

    if ( !defined( $defs{$NAME} ) ) {
        return "$NAME: Non existing device";
    }
    elsif ( lc($nextRun) eq "off" && !$forceRun ) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: alarm set to OFF - not triggering wake-up program";
    }
    elsif ( !$wakeupUserdevice ) {
        return "$NAME: missing attribute wakeupUserdevice";
    }
    elsif ( !defined( $defs{$wakeupUserdevice} ) ) {
        return "$NAME: Non existing wakeupUserdevice $wakeupUserdevice";
    }
    elsif ($defs{$wakeupUserdevice}{TYPE} ne "RESIDENTS"
        && $defs{$wakeupUserdevice}{TYPE} ne "ROOMMATE"
        && $defs{$wakeupUserdevice}{TYPE} ne "GUEST" )
    {
        return
"$NAME: device $wakeupUserdevice is not of type RESIDENTS, ROOMMATE or GUEST";
    }
    elsif ($defs{$wakeupUserdevice}{TYPE} eq "GUEST"
        && $wakeupUserdeviceState eq "none" )
    {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: GUEST device $wakeupUserdevice has status value 'none' so let's disable this alarm timer";
        fhem "set $NAME nextRun OFF";
        return;
    }
    elsif ( !$wakeupHolidays && !( $wday ~~ @days ) && !$forceRun ) {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: weekday restriction in use - not triggering wake-up program this time";
    }
    elsif (
           $wakeupHolidays
        && !$forceRun
        && (   $wakeupHolidays eq "orHoliday"
            || $wakeupHolidays eq "orNoHoliday" )
        && (
            !( $wday ~~ @days )
            && (   ( $wakeupHolidays eq "orHoliday" && !$holidayToday )
                || ( $wakeupHolidays eq "orNoHoliday" && $holidayToday ) )
        )
      )
    {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: neither weekday nor holiday restriction matched - not triggering wake-up program this time";
    }
    elsif (
           $wakeupHolidays
        && !$forceRun
        && (   $wakeupHolidays eq "andHoliday"
            || $wakeupHolidays eq "andNoHoliday" )
        && (
            !( $wday ~~ @days )
            || (   ( $wakeupHolidays eq "andHoliday" && !$holidayToday )
                || ( $wakeupHolidays eq "andNoHoliday" && $holidayToday ) )
        )
      )
    {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: weekday restriction in conjunction with $wakeupHolidays in use - not triggering wake-up program this time";
    }
    elsif ($wakeupUserdeviceState eq "absent"
        || $wakeupUserdeviceState eq "gone"
        || $wakeupUserdeviceState eq "gotosleep"
        || $wakeupUserdeviceState eq "awoken" )
    {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: we should not start any wake-up program for resident device $wakeupUserdevice being in state '"
          . $wakeupUserdeviceState
          . "' - not triggering wake-up program this time";
    }

    #  general conditions to trigger program fulfilled
    else {
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
"RESIDENTStk $NAME: Another wake-up program is already being executed for device $wakeupUserdevice, won't trigger $wakeupMacro";
        }
        elsif ( $preventRun && !$forceRun ) {
            Log3 $NAME, 4,
"RESIDENTStk $NAME: won't trigger wake-up program due to non-expired wakeupWaitPeriod threshold since lastRun (expLastRun=$expLastRun nowRunSec=$nowRunSec expNextRun=$expNextRun localtime="
              . time() . ")";
        }
        else {
            # conditional enforced wake-up:
            # only if actual wake-up time is not wakeupDefaultTime
            if (   $wakeupEnforced == 2
                && $wakeupDefaultTime
                && $wakeupDefaultTime ne $lastRun )
            {
                $wakeupEnforced = 1;
            }
            elsif ( $wakeupEnforced == 2 ) {
                $wakeupEnforced = 0;
            }

            Log3 $NAME, 4,
              "RESIDENTStk $NAME: trigger $wakeupMacro (running=1)";
            fhem
"trigger $wakeupMacro start $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";

            # Update user device with last wakeup details
            #
            readingsBeginUpdate( $defs{$wakeupUserdevice} );
            readingsBulkUpdate( $defs{$wakeupUserdevice},
                "lastWakeup", $lastRun );
            readingsBulkUpdate( $defs{$wakeupUserdevice},
                "lastWakeupDev", $NAME );
            readingsBulkUpdate( $defs{$wakeupUserdevice}, "wakeup", "1" );
            readingsEndUpdate( $defs{$wakeupUserdevice}, 1 );

            fhem "setreading $wakeupUserdevice wakeup 0"
              if ( !$wakeupOffset );

            fhem "setreading $NAME lastRun $lastRun";

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
"attr $wakeupStopAtdevice comment Auto-created by RESIDENTS Toolkit: temp. at-device to stop wake-up program of timer $NAME when wake-up time is reached";

                $running = 1;
            }

        }
    }

    # Update user device with next wakeup details
    #
    readingsBeginUpdate( $defs{$wakeupUserdevice} );
    my ( $nextWakeupDev, $nextWakeup ) =
      RESIDENTStk_wakeupGetNext($wakeupUserdevice);
    if ( !$nextWakeupDev || !$nextWakeup ) {
        $nextWakeupDev = "none";
        $nextWakeup    = "OFF";
    }
    readingsBulkUpdate( $defs{$wakeupUserdevice},
        "nextWakeupDev", $nextWakeupDev )
      if ( ReadingsVal( $defs{$wakeupUserdevice}, "nextWakeupDev", 0 ) ne
        $nextWakeupDev );
    readingsBulkUpdate( $defs{$wakeupUserdevice}, "nextWakeup", $nextWakeup )
      if ( ReadingsVal( $defs{$wakeupUserdevice}, "nextWakeup", 0 ) ne
        $nextWakeup );
    readingsEndUpdate( $defs{$wakeupUserdevice}, 1 );

    if ( $running && $wakeupOffset > 0 ) {
        readingsBeginUpdate( $defs{$NAME} );
        readingsBulkUpdate( $defs{$NAME}, "running", "1" )
          if ( ReadingsVal( $NAME, "running", 0 ) ne "1" );
        readingsBulkUpdate( $defs{$NAME}, "state", "running" )
          if ( ReadingsVal( $NAME, "state", 0 ) ne "running" );
        readingsEndUpdate( $defs{$NAME}, 1 );
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
    elsif ( !$running ) {
        fhem "setreading $NAME:FILTER=state!=$nextRun state $nextRun";
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
    if ( $init_done && $cmd eq "set" ) {

        # wakeupResetSwitcher
        if ( $aName eq "wakeupResetSwitcher" ) {
            if ( !defined( $defs{$aVal} ) ) {
                my $alias = AttrVal( $name, "alias", 0 );
                my $group = AttrVal( $name, "group", 0 );
                my $room  = AttrVal( $name, "room",  0 );

                fhem "define $aVal dummy";
                fhem
"attr $aVal comment Auto-created by RESIDENTS Toolkit: easy between on/off for auto time reset of wake-up timer $NAME";
                if ($alias) {
                    fhem "attr $aVal alias $alias Reset";
                }
                else {
                    fhem "attr $aVal alias Wake-up Timer Reset";
                }
                fhem
"attr $aVal devStateIcon auto:time_automatic:off off:time_manual_mode:auto";
                fhem "attr $aVal group $group"
                  if ($group);
                fhem "attr $aVal icon refresh";
                fhem "attr $aVal room $room"
                  if ($room);
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
# GENERAL USER AUTOMATION FUNCTIONS
#------------------------------------
#

sub RESIDENTStk_wakeupGetNext($) {
    my ($name) = @_;
    my $wakeupDeviceAttrName = "";

    $wakeupDeviceAttrName = "rgr_wakeupDevice"
      if ( defined( $attr{$name}{"rgr_wakeupDevice"} ) );
    $wakeupDeviceAttrName = "rr_wakeupDevice"
      if ( defined( $attr{$name}{"rr_wakeupDevice"} ) );
    $wakeupDeviceAttrName = "rg_wakeupDevice"
      if ( defined( $attr{$name}{"rg_wakeupDevice"} ) );

    my $wakeupDeviceList = AttrVal( $name, $wakeupDeviceAttrName, 0 );

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);

    $hour = "0" . $hours if ( $hour < 10 );
    $min  = "0" . $min   if ( $min < 10 );

    my $wdayTomorrow = $wday + 1;
    $wdayTomorrow = 0 if ( $wdayTomorrow == 7 );
    my $secNow              = RESIDENTStk_time2sec( $hour . ":" . $min ) + $sec;
    my $definitiveNextToday = 0;
    my $definitiveNextTomorrow    = 0;
    my $definitiveNextTodayDev    = 0;
    my $definitiveNextTomorrowDev = 0;

    my $holidayDevice = AttrVal( "global", "holiday2we", 0 );
    my $hdayTod = ReadingsVal( $holidayDevice, "state",    "" );
    my $hdayTom = ReadingsVal( $holidayDevice, "tomorrow", "" );

    # check for each registered wake-up device
    for my $wakeupDevice ( split /,/, $wakeupDeviceList ) {
        next if !$wakeupDevice;

        if ( !defined( $defs{$wakeupDevice} ) ) {
            Log3 $name, 4,
"RESIDENTStk $name: 00 - ignoring reference to non-existing wakeupDevice $wakeupDevice";

            my $wakeupDeviceListNew = $wakeupDeviceList;
            $wakeupDeviceListNew =~ s/,$wakeupDevice,/,/g;
            $wakeupDeviceListNew =~ s/$wakeupDevice,//g;
            $wakeupDeviceListNew =~ s/,$wakeupDevice//g;

            if ( $wakeupDeviceListNew ne $wakeupDeviceList ) {
                Log3 $name, 3,
"RESIDENTStk $name: reference to non-existing wakeupDevice '$wakeupDevice' was removed";
                fhem "attr $name $wakeupDeviceAttrName $wakeupDeviceListNew";
            }

            next;
        }

        Log3 $name, 4,
"RESIDENTStk $name: 00 - checking for next wake-up candidate $wakeupDevice";

        my $nextRun = ReadingsVal( $wakeupDevice, "nextRun", 0 );
        my $wakeupAtdevice = AttrVal( $wakeupDevice, "wakeupAtdevice", 0 );
        my $wakeupOffset   = AttrVal( $wakeupDevice, "wakeupOffset",   0 );
        my $wakeupAtNTM    = (
            defined( $defs{$wakeupAtdevice} )
              && defined( $defs{$wakeupAtdevice}{NTM} )
            ? substr( $defs{$wakeupAtdevice}{NTM}, 0, -3 )
            : 0
        );
        my $wakeupDays     = AttrVal( $wakeupDevice, "wakeupDays",     "" );
        my $wakeupHolidays = AttrVal( $wakeupDevice, "wakeupHolidays", 0 );
        my $holidayToday   = 0;
        my $holidayTomorrow = 0;

        # get holiday status for today and tomorrow
        if (   $wakeupHolidays
            && $holidayDevice
            && defined( $defs{$holidayDevice} )
            && $defs{$holidayDevice}{TYPE} eq "holiday" )
        {
            if ( $hdayTod ne "none" && $hdayTod ne "" ) { $holidayToday    = 1 }
            if ( $hdayTom ne "none" && $hdayTom ne "" ) { $holidayTomorrow = 1 }

            Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 01 - Holidays to be considered - today=$holidayToday tomorrow=$holidayTomorrow";
        }
        else {
            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: 01 - Not considering any holidays";
        }

        # set day scope for today
        my @days = ($wday);
        if ( $wakeupDays ne "" ) {
            @days = split /,/, $wakeupDays;
        }

        # set day scope for tomorrow
        my @daysTomorrow = ($wdayTomorrow);
        if ( $wakeupDays ne "" ) {
            @daysTomorrow = split /,/, $wakeupDays;
        }

        if ( lc($nextRun) ne "off" && $nextRun =~ /^([0-9]{2}:[0-9]{2})$/ ) {

            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: 02 - possible candidate found";

            my $nextRunSec;

            # Use direct information from at-device if possible
            if ( $wakeupAtNTM && $wakeupAtNTM =~ /^([0-9]{2}:[0-9]{2})$/ ) {
                $nextRunSec =
                  RESIDENTStk_time2sec($wakeupAtNTM) + $wakeupOffset * 60;
                Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 03 - considering at-device value wakeupAtNTM=$wakeupAtNTM wakeupOffset=$wakeupOffset";
            }
            else {
                $nextRunSec = RESIDENTStk_time2sec($nextRun);
                Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 03 - considering dummy-device value nextRun=$nextRun wakeupOffset=$wakeupOffset (wakeupAtNTM=$wakeupAtNTM)";
            }

            # still running today
            if ( $nextRunSec > $secNow ) {
                Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 04 - this is a candidate for today";

                # if today is in scope
                if ( $wday ~~ @days ) {

                    # if we need to consider holidays in addition
                    if (
                        $wakeupHolidays && ( $wakeupHolidays eq "andHoliday"
                            && !$holidayToday )
                        || (   $wakeupHolidays eq "andNoHoliday"
                            && $holidayToday )
                      )
                    {
                        Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 05 - no run today due to holiday based on combined weekday and holiday decision";
                        next;
                    }

                    # easy if there is no holiday dependency
                    elsif ( !$definitiveNextToday
                        || $nextRunSec < $definitiveNextToday )
                    {
                        Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 05 - until now, will be NEXT WAKE-UP RUN today based on weekday decision";
                        $definitiveNextToday    = $nextRunSec;
                        $definitiveNextTodayDev = $wakeupDevice;
                    }

                }
                else {
                    Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 05 - won't be running today anymore based on weekday decision";
                }

                # if we need to consider holidays in parallel to weekdays
                if (
                    $wakeupHolidays
                    && (
                        ( $wakeupHolidays eq "orHoliday" && $holidayToday )
                        || ( $wakeupHolidays eq "orNoHoliday"
                            && !$holidayToday )
                    )
                  )
                {

                    if (  !$definitiveNextToday
                        || $nextRunSec < $definitiveNextToday )
                    {
                        Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 06 - until now, will be NEXT WAKE-UP RUN today based on holiday decision";
                        $definitiveNextToday    = $nextRunSec;
                        $definitiveNextTodayDev = $wakeupDevice;
                    }

                }
                elsif ($wakeupHolidays) {
                    Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 06 - won't be running today based on holiday decision (wakeupHolidays=$wakeupHolidays)";
                }

            }

            # running tomorrow
            else {
                Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 04 - this is a candidate for tomorrow";

                # if tomorrow is in scope
                if ( $wdayTomorrow ~~ @daysTomorrow ) {

                    # if we need to consider holidays in addition
                    if (
                        $wakeupHolidays && ( $wakeupHolidays eq "andHoliday"
                            && !$holidayTomorrow )
                        || (   $wakeupHolidays eq "andNoHoliday"
                            && $holidayTomorrow )
                      )
                    {
                        Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 05 - no run tomorrow due to holiday based on combined weekday and holiday decision (wakeupHolidays=$wakeupHolidays)";
                        next;
                    }

                    # easy if there is no holiday dependency
                    elsif ( !$definitiveNextTomorrow
                        || $nextRunSec < $definitiveNextTomorrow )
                    {
                        Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 05 - until now, will be NEXT WAKE-UP RUN tomorrow based on weekday decision";
                        $definitiveNextTomorrow    = $nextRunSec;
                        $definitiveNextTomorrowDev = $wakeupDevice;
                    }

                }
                else {
                    Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 05 - won't be running tomorrow based on weekday decision";

                }

                # if we need to consider holidays in parallel to weekdays
                if (
                    $wakeupHolidays
                    && (
                        ( $wakeupHolidays eq "orHoliday" && $holidayTomorrow )
                        || ( $wakeupHolidays eq "orNoHoliday"
                            && !$holidayTomorrow )
                    )
                  )
                {

                    if (  !$definitiveNextTomorrow
                        || $nextRunSec < $definitiveNextTomorrow )
                    {
                        Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 06 - until now, will be NEXT WAKE-UP RUN tomorrow based on holiday decision (wakeupHolidays=$wakeupHolidays)";
                        $definitiveNextTomorrow    = $nextRunSec;
                        $definitiveNextTomorrowDev = $wakeupDevice;
                    }

                }
                elsif ($wakeupHolidays) {
                    Log3 $name, 4,
"RESIDENTStk $wakeupDevice: 06 - won't be running tomorrow based on holiday decision (wakeupHolidays=$wakeupHolidays)";
                }

            }

        }
        else {
            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: 02 - set to OFF so no candidate";
        }
    }

    if ( $definitiveNextTodayDev && $definitiveNextToday ) {
        Log3 $name, 4,
            "RESIDENTStk $name: 07 - next wake-up result: today at "
          . RESIDENTStk_sec2time($definitiveNextToday)
          . ", wakeupDevice="
          . $definitiveNextTodayDev;

        return ( $definitiveNextTodayDev,
            substr( RESIDENTStk_sec2time($definitiveNextToday), 0, -3 ) );
    }
    elsif ( $definitiveNextTomorrowDev && $definitiveNextTomorrow ) {
        Log3 $name, 4,
            "RESIDENTStk $name: 07 - next wake-up result: tomorrow at "
          . RESIDENTStk_sec2time($definitiveNextTomorrow)
          . ", wakeupDevice="
          . $definitiveNextTomorrowDev;

        return ( $definitiveNextTomorrowDev,
            substr( RESIDENTStk_sec2time($definitiveNextTomorrow), 0, -3 ) );
    }

    return ( 0, 0 );
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

sub RESIDENTStk_time2sec($) {
    my ($timeString) = @_;
    my @time = split /:/, $timeString;

    return $time[0] * 3600 + $time[1] * 60;
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

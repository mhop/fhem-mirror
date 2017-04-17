###############################################################################
# $Id$
# package main;
# use strict;
# use warnings;
# use Data::Dumper;
sub RESIDENTStk_Initialize() { }

#####################################
# PRE-DEFINITION: wakeuptimer
#------------------------------------
#

#
# Enslave DUMMY device to be used for alarm clock
#
sub RESIDENTStk_wakeupSet($$) {
    my ( $NAME, $n ) = @_;
    my ( $a,    $h ) = parseParams($n);
    my $cmd = shift @$a;
    my $VALUE = join( " ", @$a );

    $cmd =~ s/^state:\s*(.*)$/$1/;
    return if ( $cmd =~ /^[A-Za-z]+:/ );

    # filter non-registered notifies
    if ( $cmd !~
m/^((?:next[rR]un)?\s*(off|OFF|([\+\-])?(([0-9]{2}):([0-9]{2})|([1-9]+[0-9]*)))?|trigger|start|stop|end|reset|auto|wakeupResetdays|wakeupDays|wakeupHolidays|wakeupEnforced|wakeupDefaultTime|wakeupOffset)$/i
      )
    {
        Log3 $NAME, 6,
          "RESIDENTStk $NAME: "
          . "received unspecified notify '$cmd' - nothing to do";
        return;
    }

    my $wakeupMacro = AttrVal( $NAME, "wakeupMacro", 0 );
    my $wakeupDefaultTime =
      ReadingsVal( $NAME, "wakeupDefaultTime",
        AttrVal( $NAME, "wakeupDefaultTime", 0 ) );
    my $wakeupAtdevice   = AttrVal( $NAME, "wakeupAtdevice",   0 );
    my $wakeupUserdevice = AttrVal( $NAME, "wakeupUserdevice", 0 );
    my $wakeupDays =
      ReadingsVal( $NAME, "wakeupDays", AttrVal( $NAME, "wakeupDays", "" ) );
    my $wakeupHolidays =
      ReadingsVal( $NAME, "wakeupHolidays",
        AttrVal( $NAME, "wakeupHolidays", "" ) );
    my $wakeupResetdays =
      ReadingsVal( $NAME, "wakeupResetdays",
        AttrVal( $NAME, "wakeupResetdays", "" ) );
    my $wakeupOffset =
      ReadingsVal( $NAME, "wakeupOffset", AttrVal( $NAME, "wakeupOffset", 0 ) );
    my $wakeupEnforced =
      ReadingsVal( $NAME, "wakeupEnforced",
        AttrVal( $NAME, "wakeupEnforced", 0 ) );
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

    my $wakeupUserdeviceRealname = "Bewohner";

    if ( IsDevice( $wakeupUserdevice, "ROOMMATE" ) ) {
        $wakeupUserdeviceRealname = AttrVal(
            AttrVal( $NAME, "wakeupUserdevice", "" ),
            AttrVal(
                AttrVal( $NAME, "wakeupUserdevice", "" ), "rr_realname",
                "group"
            ),
            $wakeupUserdeviceRealname
        );
    }
    elsif ( IsDevice( $wakeupUserdevice, "GUEST" ) ) {
        $wakeupUserdeviceRealname = AttrVal(
            AttrVal( $NAME, "wakeupUserdevice", "" ),
            AttrVal(
                AttrVal( $NAME, "wakeupUserdevice", "" ), "rg_realname",
                "alias"
            ),
            $wakeupUserdeviceRealname
        );
    }

    RESIDENTStk_findDummySlaves($wakeupUserdevice);

    # check for required userattr attribute
    my $userattributes =
"wakeupOffset:slider,0,1,120 wakeupDefaultTime:OFF,00:00,00:15,00:30,00:45,01:00,01:15,01:30,01:45,02:00,02:15,02:30,02:45,03:00,03:15,03:30,03:45,04:00,04:15,04:30,04:45,05:00,05:15,05:30,05:45,06:00,06:15,06:30,06:45,07:00,07:15,07:30,07:45,08:00,08:15,08:30,08:45,09:00,09:15,09:30,09:45,10:00,10:15,10:30,10:45,11:00,11:15,11:30,11:45,12:00,12:15,12:30,12:45,13:00,13:15,13:30,13:45,14:00,14:15,14:30,14:45,15:00,15:15,15:30,15:45,16:00,16:15,16:30,16:45,17:00,17:15,17:30,17:45,18:00,18:15,18:30,18:45,19:00,19:15,19:30,19:45,20:00,20:15,20:30,20:45,21:00,21:15,21:30,21:45,22:00,22:15,22:30,22:45,23:00,23:15,23:30,23:45 wakeupMacro wakeupUserdevice wakeupAtdevice wakeupResetSwitcher wakeupResetdays:multiple-strict,0,1,2,3,4,5,6 wakeupDays:multiple-strict,0,1,2,3,4,5,6 wakeupHolidays:andHoliday,orHoliday,andNoHoliday,orNoHoliday wakeupEnforced:0,1,2,3 wakeupWaitPeriod:slider,0,1,360";
    if ( !$userattr || $userattr ne $userattributes ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "adjusting dummy device for required attribute userattr";
        fhem "attr $NAME userattr $userattributes";
    }

    # check for required userdevice attribute
    if ( !$wakeupUserdevice ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "WARNING - set attribute wakeupUserdevice before running wakeup function!";
    }
    elsif ( !IsDevice($wakeupUserdevice) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "WARNING - user device $wakeupUserdevice does not exist!";
    }
    elsif ( !IsDevice( $wakeupUserdevice, "RESIDENTS|ROOMMATE|GUEST" ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "WARNING - defined user device '$wakeupUserdevice' is not a RESIDENTS, ROOMMATE or GUEST device!";
    }

    # check for required wakeupMacro attribute
    if ( !$wakeupMacro ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "adjusting dummy device for required attribute wakeupMacro";
        fhem "attr $NAME wakeupMacro $macroName";
        $wakeupMacro = $macroName;
    }
    if ( !IsDevice($wakeupMacro) ) {
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
fhem \"delete atTmp_.*_\".\$NAME.\":FILTER=TYPE=at\";;\
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
#	fhem \"define atTmp_4_\$NAME at +00:30:00 msg audio \\\@Sonos_Bedroom |Hint| Es ist \".\$EVTPART1.\" Uhr, Zeit zum aufstehen!;;;; set BR_FloorLamp:FILTER=pct<100 pct 100 60;;;; sleep 10;;;; set BR_Shutter:FILTER=pct<60 pct 60;;;; set Sonos_Bedroom:FILTER=Volume<10 Volume 10 10\";;\
\
	# if wake-up should be enforced\
	if (\$EVTPART3) {\
		Log3 \$NAME, 3, \"\$NAME: planning enforced wake-up\";;\
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
		fhem \"define atTmp_9_\$NAME at +00:05:00 set \$EVTPART4:FILTER=state=asleep awoken\";;\
\
	# Without enforced wake-up, be jentle and just set user state to 'home' after some\
	# additional long nap time\
	} else {\
		fhem \"define atTmp_9_\$NAME at +01:30:00 set \$EVTPART4:FILTER=state=asleep home\";;\
    }\
}\
\
}\
";

        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "new notify macro device $wakeupMacro created";
        fhem "define $wakeupMacro notify $wakeupMacro $wakeUpMacroTemplate";
        fhem
          "attr $wakeupMacro comment Macro auto-created by RESIDENTS Toolkit";
        fhem "attr $wakeupMacro room $room"
          if ($room);
    }
    elsif ( !IsDevice( $wakeupMacro, "notify" ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "WARNING - defined macro device '$wakeupMacro' is not a notify device!";
    }

    # check for required wakeupAtdevice attribute
    if ( !$wakeupAtdevice ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "adjusting dummy device for required attribute wakeupAtdevice";
        fhem "attr $NAME wakeupAtdevice $atName";
        $wakeupAtdevice = $atName;
    }
    if ( !IsDevice($wakeupAtdevice) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: " . "new at-device $wakeupAtdevice created";
        fhem "define $wakeupAtdevice "
          . "at *{RESIDENTStk_wakeupGetBegin(\"$NAME\",\"$wakeupAtdevice\")} set $NAME trigger";
        fhem "attr $wakeupAtdevice "
          . "comment Auto-created by RESIDENTS Toolkit: trigger wake-up timer at specific time";
        fhem "attr $wakeupAtdevice computeAfterInit 1";
        fhem "attr $wakeupAtdevice room $room"
          if ($room);

        ########
        # (re)create other notify and watchdog templates
        # for ROOMMATE or GUEST devices

        # macro: gotosleep
        if (   !IsDevice( $wakeupUserdevice, "RESIDENTS" )
            && !IsDevice($macroNameGotosleep) )
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
#fhem \"sleep 2.0;; set Sonos_Bedroom AddMember Sonos_Bathroom;; set Sonos_Bedroom:FILTER=Shuffle!=1 Shuffle 1;; set Sonos_Bedroom:FILTER=Volume!=12,Sonos_Bathroom:FILTER=Volume!=12 Volume 12\";;\
\
## Start music from playlist\
#fhem \"sleep 3.0;; set Sonos_Bedroom StartFavourite Evening%%20Chill\";;\
\
return;;\
}";

            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "new notify macro device $macroNameGotosleep created";
            fhem "define $macroNameGotosleep "
              . "notify $macroNameGotosleep $templateGotosleep";
            fhem "attr $macroNameGotosleep "
              . "comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when gettin' ready for bed";
            fhem "attr $macroNameGotosleep room $room"
              if ($room);
        }

        # wd: gotosleep
        if ( !IsDevice($wdNameGotosleep) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "new watchdog device $wdNameGotosleep created";
            fhem "define $wdNameGotosleep "
              . "watchdog $wakeupUserdevice:(gotosleep|bettfertig) 00:00:04 $wakeupUserdevice:(home|anwesend|zuhause|absent|abwesend|gone|verreist|asleep|schlaeft|schläft|awoken|aufgestanden) trigger $macroNameGotosleep";
            fhem "attr $wdNameGotosleep autoRestart 1";
            fhem "attr $wdNameGotosleep "
              . "comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state gotosleep";
            fhem "attr $wdNameGotosleep room $room"
              if ($room);
        }

        # macro: asleep
        if (   !IsDevice( $wakeupUserdevice, "RESIDENTS" )
            && !IsDevice($macroNameAsleep) )
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
#my \$nextWakeup = ReadingsVal(\"$wakeupUserdevice\",\"nextWakeup\",\"none\");;
#my \$text = \"|Hint| $wakeupUserdeviceRealname, es ist kein Wecker gestellt. Du könntest verschlafen! Trotzdem eine gute Nacht.\";;
#if (\$nextWakeup ne \"OFF\") {
#	\$text = \"|Hint| $wakeupUserdeviceRealname, dein Wecker ist auf \$nextWakeup Uhr gestellt. Gute Nacht und schlaf gut.\";;
#}
#if (\$nextWakeup ne \"none\") {
#	fhem \"set Sonos_Bedroom RemoveMember Sonos_Bedroom;; sleep 0.5;; msg audio \\\@Sonos_Bedroom \$text\";;\
#}
\
return;;\
}";

            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "new notify macro device $macroNameAsleep created";
            fhem
              "define $macroNameAsleep notify $macroNameAsleep $templateAsleep";
            fhem "attr $macroNameAsleep "
              . "comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when jumpin' into bed and start to sleep";
            fhem "attr $macroNameAsleep room $room"
              if ($room);
        }

        # wd: asleep
        if ( !IsDevice($wdNameAsleep) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "new watchdog device $wdNameAsleep created";
            fhem "define $wdNameAsleep "
              . "watchdog $wakeupUserdevice:(asleep|schlaeft|schläft) 00:00:04 $wakeupUserdevice:(home|anwesend|zuhause|absent|abwesend|gone|verreist|gotosleep|bettfertig|awoken|aufgestanden) trigger $macroNameAsleep";
            fhem "attr $wdNameAsleep autoRestart 1";
            fhem "attr $wdNameAsleep "
              . "comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state asleep";
            fhem "attr $wdNameAsleep room $room"
              if ($room);
        }

        # macro: awoken
        if (   !IsDevice( $wakeupUserdevice, "RESIDENTS" )
            && !IsDevice($macroNameAwoken) )
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
#fhem \"set Sonos_Bedroom Stop;; msg audio \\\@Sonos_Bedroom |Hint| Guten Morgen, $wakeupUserdeviceRealname.\";;\
\
## In 10 seconds, start webradio playback in Bedroom\
#fhem \"sleep 10;; set Sonos_Bedroom StartRadio /Charivari/;; sleep 2;; set Sonos_Bedroom Volume 15\";;\
\
## Make webradio stream available at Bathroom and\
## Kitchen 5 seonds after it started\
#fhem \"set Sonos_Bathroom,Sonos_Kitchen Volume 15;; sleep 15;; set Sonos_Bedroom AddMember Sonos_Bathroom;; set Sonos_Bedroom AddMember Sonos_Kitchen\";;\
\
## change user state to home after 60 seconds\
fhem \"sleep 60;; set $wakeupUserdevice:FILTER=state!=home home\";;\
\
return;;\
}";

            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "new notify macro device $macroNameAwoken created";
            fhem
              "define $macroNameAwoken notify $macroNameAwoken $templateAwoken";
            fhem "attr $macroNameAwoken "
              . "comment Auto-created by RESIDENTS Toolkit: FHEM commands to run after confirming to be awake";
            fhem "attr $macroNameAwoken room $room"
              if ($room);
        }

        # wd: awoken
        if ( !IsDevice($wdNameAwoken) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "new watchdog device $wdNameAwoken created";
            fhem "define $wdNameAwoken "
              . "watchdog $wakeupUserdevice:(awoken|aufgestanden) 00:00:04 $wakeupUserdevice:(home|anwesend|zuhause|absent|abwesend|gone|verreist|gotosleep|bettfertig|asleep|schlaeft|schläft) trigger $macroNameAwoken";
            fhem "attr $wdNameAwoken autoRestart 1";
            fhem "attr $wdNameAwoken "
              . "comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state awoken";
            fhem "attr $wdNameAwoken room $room"
              if ($room);
        }

        ########
        # (re)create other notify and watchdog templates
        # for RESIDENT devices
        #

        my $RESIDENTGROUPS = "";
        if ( IsDevice( $wakeupUserdevice, "RESIDENTS" ) ) {
            $RESIDENTGROUPS = $wakeupUserdevice;
        }
        elsif ( IsDevice($wakeupUserdevice)
            && defined( $defs{$wakeupUserdevice}{RESIDENTGROUPS} ) )
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
            if ( !IsDevice($macroRNameGotosleep) ) {
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
return;;\
}";

                Log3 $NAME, 3,
                  "RESIDENTStk $NAME: "
                  . "new notify macro device $macroRNameGotosleep created";
                fhem
"define $macroRNameGotosleep notify $macroRNameGotosleep $templateGotosleep";
                fhem
"attr $macroRNameGotosleep comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when all residents are gettin' ready for bed";
                fhem "attr $macroRNameGotosleep room $room"
                  if ($room);
            }

            # wd: gotosleep
            if ( !IsDevice($wdRNameGotosleep) ) {
                Log3 $NAME, 3,
                  "RESIDENTStk $NAME: "
                  . "new watchdog device $wdRNameGotosleep created";
                fhem "define $wdRNameGotosleep "
                  . "watchdog $deviceName:(gotosleep|bettfertig) 00:00:03 $deviceName:(home|anwesend|zuhause|absent|abwesend|gone|verreist|asleep|schlaeft|schläft|awoken|aufgestanden) trigger $macroRNameGotosleep";
                fhem "attr $wdRNameGotosleep autoRestart 1";
                fhem "attr $wdRNameGotosleep "
                  . "comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state gotosleep";
                fhem "attr $wdRNameGotosleep room $room"
                  if ($room);
            }

            # macro: asleep
            if ( !IsDevice($macroRNameAsleep) ) {
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
return;;\
}";

                Log3 $NAME, 3,
                  "RESIDENTStk $NAME: "
                  . "new notify macro device $macroRNameAsleep created";
                fhem "define $macroRNameAsleep "
                  . "notify $macroRNameAsleep $templateAsleep";
                fhem "attr $macroRNameAsleep "
                  . "comment Auto-created by RESIDENTS Toolkit: FHEM commands to run when all residents are in their beds";
                fhem "attr $macroRNameAsleep room $room"
                  if ($room);
            }

            # wd: asleep
            if ( !IsDevice($wdRNameAsleep) ) {
                Log3 $NAME, 3,
                  "RESIDENTStk $NAME: "
                  . "new watchdog device $wdNameAsleep created";
                fhem "define $wdRNameAsleep "
                  . "watchdog $deviceName:(asleep|schlaeft|schläft) 00:00:03 $deviceName:(home|anwesend|zuhause|absent|abwesend|gone|verreist|gotosleep|bettfertig|awoken|aufgestanden) trigger $macroRNameAsleep";
                fhem "attr $wdRNameAsleep autoRestart 1";
                fhem "attr $wdRNameAsleep "
                  . "comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state asleep";
                fhem "attr $wdRNameAsleep room $room"
                  if ($room);
            }

            # macro: awoken
            if ( !IsDevice($macroRNameAwoken) ) {
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
#	fhem \"define atTmp_HouseMode_day at +01:30:00 {if (ReadingsVal(\\\"HouseMode\\\", \\\"state\\\", 0) ne \\\"day\\\") {fhem \\\"msg audio \\\@Sonos_Kitchen Tagesmodus wird etabliert.;;;; sleep 10;;;; set HouseMode day\\\"}}\";;\
#}\
\
return;;\
}";

                Log3 $NAME, 3,
                  "RESIDENTStk $NAME: "
                  . "new notify macro device $macroRNameAwoken created";
                fhem "define $macroRNameAwoken "
                  . "notify $macroRNameAwoken $templateAwoken";
                fhem "attr $macroRNameAwoken "
                  . "comment Auto-created by RESIDENTS Toolkit: FHEM commands to run after first resident confirmed to be awake";
                fhem "attr $macroRNameAwoken room $room"
                  if ($room);
            }

            # wd: awoken
            if ( !IsDevice($wdRNameAwoken) ) {
                Log3 $NAME, 3,
                  "RESIDENTStk $NAME: "
                  . "new watchdog device $wdNameAwoken created";
                fhem "define $wdRNameAwoken "
                  . "watchdog $deviceName:(awoken|aufgestanden) 00:00:04 $deviceName:(home|anwesend|zuhause|absent|abwesend|gone|verreist|gotosleep|bettfertig|asleep|schlaeft|schläft) trigger $macroRNameAwoken";
                fhem "attr $wdRNameAwoken autoRestart 1";
                fhem "attr $wdRNameAwoken "
                  . "comment Auto-created by RESIDENTS Toolkit: trigger macro after going to state awoken";
                fhem "attr $wdRNameAwoken room $room"
                  if ($room);
            }

        }

    }
    elsif ( !IsDevice( $wakeupAtdevice, "at" ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "WARNING - defined at-device '$wakeupAtdevice' is not an at-device!";
    }
    elsif ( AttrVal( $wakeupAtdevice, "computeAfterInit", 0 ) ne "1" ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "Correcting '$wakeupAtdevice' attribute computeAfterInit required for correct recalculation after reboot";
        fhem "attr $wakeupAtdevice computeAfterInit 1";
    }

    # verify holiday2we attribute
    if ( $wakeupHolidays ne "" ) {
        if ( !$holidayDevice ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "ERROR - wakeupHolidays set in this alarm clock but global attribute holiday2we not set!";
            return "ERROR: "
              . "wakeupHolidays set in this alarm clock but global attribute holiday2we not set!";
        }
        elsif ( !IsDevice($holidayDevice) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "ERROR - global attribute holiday2we has reference to non-existing device $holidayDevice";
            return "ERROR: "
              . "global attribute holiday2we has reference to non-existing device $holidayDevice";
        }
        elsif ( !IsDevice( $holidayDevice, "holiday" ) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "ERROR - global attribute holiday2we seems to have invalid device reference - $holidayDevice is not of type 'holiday'";
            return "ERROR: "
              . "global attribute holiday2we seems to have invalid device reference - $holidayDevice is not of type 'holiday'";
        }
    }

    # start
    #
    if ( $cmd eq "start" ) {
        RESIDENTStk_wakeupRun( $NAME, 1 );
    }

    # trigger
    #
    elsif ( $cmd eq "trigger" ) {
        RESIDENTStk_wakeupRun($NAME);
    }

    # stop | end
    #
    elsif ( $cmd eq "stop" || $cmd eq "end" ) {
        if ($running) {
            Log3 $NAME, 4, "RESIDENTStk $NAME: " . "stopping wake-up program";
            readingsSingleUpdate( $defs{$NAME}, "running", "0", 1 );
        }

        fhem "set $NAME nextRun $nextRun";
        return unless ($running);

        # trigger macro again so it may clean up it's stuff.
        # use $EVTPART1 to check
        if ( !$wakeupMacro ) {
            Log3 $NAME, 2,
              "RESIDENTStk $NAME: " . "missing attribute wakeupMacro";
        }
        elsif ( !IsDevice($wakeupMacro) ) {
            Log3 $NAME, 2,
              "RESIDENTStk $NAME: "
              . "notify macro $wakeupMacro not found - no wakeup actions defined!";
        }
        elsif ( !IsDevice( $wakeupMacro, "notify" ) ) {
            Log3 $NAME, 2,
              "RESIDENTStk $NAME: "
              . "device $wakeupMacro is not of type notify";
        }
        else {

            # conditional enforced wake-up:
            # only if actual wake-up time is
            # earlier than wakeupDefaultTime
            if (   $wakeupEnforced == 3
                && $wakeupDefaultTime
                && RESIDENTStk_time2sec($wakeupDefaultTime) >
                RESIDENTStk_time2sec($lastRun) )
            {
                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "Enforcing wake-up because wake-up time is earlier than normal (wakeupDefaultTime=$wakeupDefaultTime > lastRun=$lastRun)";
                $wakeupEnforced = 1;
            }

            # conditional enforced wake-up:
            # only if actual wake-up time is not wakeupDefaultTime
            elsif ($wakeupEnforced == 2
                && $wakeupDefaultTime
                && $wakeupDefaultTime ne $lastRun )
            {
                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "Enforcing wake-up because wake-up is different from normal (wakeupDefaultTime=$wakeupDefaultTime =! lastRun=$lastRun)";
                $wakeupEnforced = 1;
            }
            elsif ( $wakeupEnforced > 1 ) {
                $wakeupEnforced = 0;
            }

            if ( $VALUE ne "" || $cmd eq "end" ) {
                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "trigger $wakeupMacro stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";
                fhem "trigger $wakeupMacro "
                  . "stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";
            }
            else {
                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "trigger $wakeupMacro forced-stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";
                fhem "trigger $wakeupMacro "
                  . "forced-stop $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";

                fhem "set $wakeupUserdevice:FILTER=state=asleep awoken";
            }

            my $wakeupStopAtdevice = $wakeupAtdevice . "_stop";
            fhem "delete $wakeupStopAtdevice"
              if ( IsDevice($wakeupStopAtdevice) );
        }

        readingsSingleUpdate( $defs{$wakeupUserdevice}, "wakeup", "0", 1 );
        return;
    }

    # auto or reset
    #
    elsif ( $cmd eq "auto" || $cmd eq "reset" ) {
        my $resetTime = ReadingsVal( $NAME, "lastRun", 0 );
        if ($wakeupDefaultTime) {
            $resetTime = $wakeupDefaultTime;
        }

        if ( $resetTime
            && !( $cmd eq "auto" && lc($resetTime) eq "off" ) )
        {
            fhem "set $NAME:FILTER=state!=$resetTime nextRun $resetTime";
        }
        elsif ( $cmd eq "reset" ) {
            Log3 $NAME, 4,
              "RESIDENTStk $NAME: "
              . "no default value specified in attribute wakeupDefaultTime, just keeping setting OFF";
            fhem "set $NAME:FILTER=state!=OFF nextRun OFF";
        }

        return;
    }

    # wakeup attributes
    #
    elsif ( $cmd =~
m/^(wakeupResetdays|wakeupDays|wakeupHolidays|wakeupEnforced|wakeupDefaultTime|wakeupOffset)$/
      )
    {
        Log3 $NAME, 4, "RESIDENTStk $NAME: " . "setting $1 to '$VALUE'";

        readingsBeginUpdate( $defs{$NAME} );
        readingsBulkUpdate( $defs{$NAME}, $1, $VALUE );
        readingsEndUpdate( $defs{$NAME}, 1 );

        fhem "set $NAME nextRun $nextRun";

        return;
    }

    # set new wakeup value
    elsif ( IsDevice( $wakeupAtdevice, "at" )
        && $cmd =~
m/^(?:nextRun)?\s*(OFF|([\+\-])?(([0-9]{2}):([0-9]{2})|([1-9]+[0-9]*)))?$/i
      )
    {
        $VALUE = $1 if ( $1 && $1 ne "" );

        $VALUE =
          RESIDENTStk_TimeSum( ReadingsVal( $NAME, "nextRun", 0 ), $VALUE )
          if ($2);

        # Update wakeuptimer device
        #
        readingsBeginUpdate( $defs{$NAME} );
        if ( ReadingsVal( $NAME, "nextRun", 0 ) ne $VALUE ) {
            Log3 $NAME, 4, "RESIDENTStk $NAME: " . "New wake-up time: $VALUE";
            readingsBulkUpdate( $defs{$NAME}, "nextRun", $VALUE );

            # Update at-device
            fhem "set $wakeupAtdevice "
              . "modifyTimeSpec {RESIDENTStk_wakeupGetBegin(\"$NAME\",\"$wakeupAtdevice\")}";
        }
        if ( ReadingsVal( $NAME, "state", 0 ) ne $VALUE
            && !$running )
        {
            readingsBulkUpdate( $defs{$NAME}, "state", $VALUE );
        }
        elsif ( ReadingsVal( $NAME, "state", 0 ) ne "running"
            && $running )
        {
            readingsBulkUpdate( $defs{$NAME}, "state", "running" );
        }
        readingsEndUpdate( $defs{$NAME}, 1 );

        # Update user device
        #
        readingsBeginUpdate( $defs{$wakeupUserdevice} );
        my ( $nextWakeupDev, $nextWakeup ) =
          RESIDENTStk_wakeupGetNext($wakeupUserdevice);
        if ( !$nextWakeupDev || !$nextWakeup ) {
            $nextWakeupDev = "";
            $nextWakeup    = "OFF";
        }
        readingsBulkUpdateIfChanged( $defs{$wakeupUserdevice},
            "nextWakeupDev", $nextWakeupDev );
        readingsBulkUpdateIfChanged( $defs{$wakeupUserdevice},
            "nextWakeup", $nextWakeup );
        readingsEndUpdate( $defs{$wakeupUserdevice}, 1 );
    }

    return undef;
}

#
# Get current wakeup begin
#
sub RESIDENTStk_wakeupGetBegin($;$) {
    my ( $NAME, $wakeupAtdevice ) = @_;

    unless ( IsDevice($NAME) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "Run function RESIDENTStk_wakeupGetBegin() for non-existing device!";
        return "$NAME: Non-existing device";
    }

    my $nextRun = ReadingsVal( $NAME, "nextRun", 0 );
    my $wakeupDefaultTime =
      ReadingsVal( $NAME, "wakeupDefaultTime",
        AttrVal( $NAME, "wakeupDefaultTime", 0 ) );
    my $wakeupOffset =
      ReadingsVal( $NAME, "wakeupOffset", AttrVal( $NAME, "wakeupOffset", 0 ) );
    my $wakeupInitTime = (
          $wakeupDefaultTime && lc($wakeupDefaultTime) ne "off"
        ? $wakeupDefaultTime
        : "05:00"
    );
    my $wakeupTime;

    if ($wakeupAtdevice) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "Wakeuptime recalculation triggered by at-device $wakeupAtdevice";
    }

    # just give any valuable return to at-device
    # if wakeuptimer device does not exit anymore
    # and run self-destruction to clean up
    if ( !IsDevice($NAME) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "this wake-up timer device does not exist anymore";
        my $atName = "at_" . $NAME;

        if ( IsDevice( $wakeupAtdevice, "at" ) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "Cleaning up at-device $wakeupAtdevice (self-destruction)";
            fhem "sleep 1; delete $wakeupAtdevice";
        }
        elsif ( IsDevice( $atName, "at" ) ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: " . "Cleaning up at-device $atName";
            fhem "sleep 1; delete $atName";
        }
        else {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "Could not automatically clean up at-device, please perform manual cleanup.";
        }

        return $wakeupInitTime;
    }

    # use nextRun value if not OFF
    if ( $nextRun && lc($nextRun) ne "off" ) {
        $wakeupTime = $nextRun;
        Log3 $NAME, 4, "RESIDENTStk $NAME: " . "wakeupGetBegin source: nextRun";
    }

    # use wakeupDefaultTime if present and not OFF
    elsif ( $wakeupDefaultTime
        && lc($wakeupDefaultTime) ne "off" )
    {
        $wakeupTime = $wakeupDefaultTime;
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: " . "wakeupGetBegin source: wakeupDefaultTime";
    }

    # Use a default value to ensure auto-reset at least once a day
    else {
        $wakeupTime = $wakeupInitTime;
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: " . "wakeupGetBegin source: defaultValue";
    }

    # Recalculate new wake-up value
    my $seconds = RESIDENTStk_time2sec($wakeupTime) - $wakeupOffset * 60;
    if ( $seconds < 0 ) { $seconds = 86400 + $seconds }

    Log3 $NAME, 4,
        "RESIDENTStk $NAME: "
      . "wakeupGetBegin result: $wakeupTime = $seconds s - $wakeupOffset m = "
      . RESIDENTStk_sec2time($seconds);

    return RESIDENTStk_sec2time($seconds);
}

#
# Use DUMMY device to run wakup event
#
sub RESIDENTStk_wakeupRun($;$) {
    my ( $NAME, $forceRun ) = @_;

    unless ( IsDevice($NAME) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: "
          . "Run function RESIDENTStk_wakeupRun() for non-existing device!";
        return "$NAME: Non-existing device";
    }

    my $wakeupMacro = AttrVal( $NAME, "wakeupMacro", 0 );
    my $wakeupDefaultTime =
      ReadingsVal( $NAME, "wakeupDefaultTime",
        AttrVal( $NAME, "wakeupDefaultTime", 0 ) );
    my $wakeupAtdevice   = AttrVal( $NAME, "wakeupAtdevice",   0 );
    my $wakeupUserdevice = AttrVal( $NAME, "wakeupUserdevice", 0 );
    my $wakeupDays =
      ReadingsVal( $NAME, "wakeupDays", AttrVal( $NAME, "wakeupDays", "" ) );
    my $wakeupHolidays =
      ReadingsVal( $NAME, "wakeupHolidays",
        AttrVal( $NAME, "wakeupHolidays", "" ) );
    my $wakeupResetdays =
      ReadingsVal( $NAME, "wakeupResetdays",
        AttrVal( $NAME, "wakeupResetdays", "" ) );
    my $wakeupOffset =
      ReadingsVal( $NAME, "wakeupOffset", AttrVal( $NAME, "wakeupOffset", 0 ) );
    my $wakeupEnforced =
      ReadingsVal( $NAME, "wakeupEnforced",
        AttrVal( $NAME, "wakeupEnforced", 0 ) );
    my $wakeupResetSwitcher = AttrVal( $NAME,    "wakeupResetSwitcher", 0 );
    my $wakeupWaitPeriod    = AttrVal( $NAME,    "wakeupWaitPeriod",    360 );
    my $holidayDevice       = AttrVal( "global", "holiday2we",          0 );
    my $lastRun = ReadingsVal( $NAME, "lastRun", "06:00" );
    my $nextRun = ReadingsVal( $NAME, "nextRun", "06:00" );
    my $wakeupUserdeviceState  = ReadingsVal( $wakeupUserdevice, "state",  0 );
    my $wakeupUserdeviceWakeup = ReadingsVal( $wakeupUserdevice, "wakeup", 0 );
    my $room         = AttrVal( $NAME, "room", 0 );
    my $running      = 0;
    my $preventRun   = 0;
    my $holidayToday = 0;

    if ( $wakeupHolidays ne ""
        && IsDevice( $holidayDevice, "holiday" ) )
    {
        $holidayToday = 1
          unless ( ReadingsVal( $holidayDevice, "state", "none" ) eq "none" );
    }
    else {
        $wakeupHolidays = "";
    }

    my ( $sec, $min, $hour, $mday, $mon, $year, $today, $yday, $isdst ) =
      localtime( time() + $wakeupOffset * 60 );

    $year += 1900;
    $mon++;
    $mon  = "0" . $mon  if ( $mon < 10 );
    $mday = "0" . $mday if ( $mday < 10 );
    $hour = "0" . $hour if ( $hour < 10 );
    $min  = "0" . $min  if ( $min < 10 );
    $sec  = "0" . $sec  if ( $sec < 10 );

    my $nowRun = $hour . ":" . $min;
    my $nowRunSec =
      time_str2num( $year . "-"
          . $mon . "-"
          . $mday . " "
          . $hour . ":"
          . $min . ":"
          . $sec );

    if ( $nextRun ne $nowRun ) {
        $lastRun = $nowRun;
        Log3 $NAME, 4, "RESIDENTStk $NAME: " . "lastRun != nextRun = $lastRun";
    }
    else {
        $lastRun = $nextRun;
        Log3 $NAME, 4, "RESIDENTStk $NAME: " . "lastRun = nextRun = $lastRun";
    }

    my @days = ($today);
    @days = split /,/, $wakeupDays
      if ( $wakeupDays ne "" );
    my %days = map { $_ => 1 } @days;

    my @rdays = ($today);
    @rdays = split /,/, $wakeupResetdays
      if ( $wakeupResetdays ne "" );
    my %rdays = map { $_ => 1 } @rdays;

    if ( IsDisabled($wakeupDevice) ) {
        Log3 $name, 4,
          "RESIDENTStk $NAME: "
          . "wakeupDevice disabled - not triggering wake-up program";
    }
    elsif ( !$wakeupUserdevice ) {
        return "$NAME: missing attribute wakeupUserdevice";
    }
    elsif ( !IsDevice($wakeupUserdevice) ) {
        return "$NAME: Non existing wakeupUserdevice $wakeupUserdevice";
    }
    elsif ( !IsDevice( $wakeupUserdevice, "RESIDENTS|ROOMMATE|GUEST" ) ) {
        return "$NAME: "
          . "wakeupUserdevice $wakeupUserdevice is not of type RESIDENTS, ROOMMATE or GUEST";
    }
    elsif ( IsDevice( $wakeupUserdevice, "GUEST" )
        && $wakeupUserdeviceState eq "none" )
    {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "GUEST device $wakeupUserdevice has status value 'none' so let's disable this wake-up timer";
        fhem "set $NAME nextRun OFF";
        return;
    }
    elsif ( IsDisabled($wakeupUserdevice) ) {
        Log3 $name, 4,
          "RESIDENTStk $NAME: "
          . "wakeupUserdevice disabled - not triggering wake-up program";
    }
    elsif ( lc($nextRun) eq "off" && !$forceRun ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "wakeup timer set to OFF - not triggering wake-up program";
    }
    elsif (
           !$forceRun
        && !$days{$today}
        && (   $wakeupHolidays eq ""
            || $wakeupHolidays eq "andHoliday"
            || $wakeupHolidays eq "andNoHoliday" )
      )
    {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "weekday restriction in use - not triggering wake-up program this time";
    }
    elsif (
        !$forceRun
        && (
            ( $wakeupHolidays eq "andHoliday" && !$holidayToday )
            || (   $wakeupHolidays eq "andNoHoliday"
                && $holidayToday )
            || ( $wakeupHolidays eq "orHoliday" && !$holidayToday )
            || (   $wakeupHolidays eq "orNoHoliday"
                && $holidayToday )
        )
      )
    {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: "
          . "holiday restriction $wakeupHolidays in use - not triggering wake-up program this time";
    }
    elsif ($wakeupUserdeviceState eq "absent"
        || $wakeupUserdeviceState eq "gone"
        || $wakeupUserdeviceState eq "gotosleep"
        || $wakeupUserdeviceState eq "awoken" )
    {
        Log3 $NAME, 4,
            "RESIDENTStk $NAME: "
          . "we should not start any wake-up program for resident device $wakeupUserdevice being in state '"
          . $wakeupUserdeviceState
          . "' - not triggering wake-up program this time";
    }

    #  general conditions to trigger program fulfilled
    else {

        my $expLastWakeup = time_str2num(
            ReadingsTimestamp(
                $wakeupUserdevice, "lastWakeup", "1970-01-01 00:00:00"
            )
          ) - 1 +
          $wakeupOffset * 60 +
          $wakeupWaitPeriod * 60;

        my $expLastAwake = time_str2num(
            ReadingsTimestamp(
                $wakeupUserdevice, "lastAwake", "1970-01-01 00:00:00"
            )
          ) - 1 +
          $wakeupWaitPeriod * 60;

        if ( !$wakeupMacro ) {
            return "$NAME: missing attribute wakeupMacro";
        }
        elsif ( !IsDevice($wakeupMacro) ) {
            return "$NAME: "
              . "notify macro $wakeupMacro not found - no wakeup actions defined!";
        }
        elsif ( !IsDevice( $wakeupMacro, "notify" ) ) {
            return "$NAME: device $wakeupMacro is not of type notify";
        }
        elsif ($wakeupUserdeviceWakeup) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "Another wake-up program is already being executed for device $wakeupUserdevice, won't trigger $wakeupMacro";
        }
        elsif ( $expLastWakeup > $nowRunSec && !$forceRun ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "won't trigger wake-up program due to non-expired wakeupWaitPeriod threshold since lastWakeup (expLastWakeup=$expLastWakeup > nowRunSec=$nowRunSec)";
        }
        elsif ( $expLastAwake > $nowRunSec && !$forceRun ) {
            Log3 $NAME, 3,
              "RESIDENTStk $NAME: "
              . "won't trigger wake-up program due to non-expired wakeupWaitPeriod threshold since lastAwake (expLastAwake=$expLastAwake > nowRunSec=$nowRunSec)";
        }
        else {

            # conditional enforced wake-up:
            # only if actual wake-up time is
            # earlier than wakeupDefaultTime
            if (   $wakeupEnforced == 3
                && $wakeupDefaultTime
                && RESIDENTStk_time2sec($wakeupDefaultTime) >
                RESIDENTStk_time2sec($lastRun) )
            {
                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "Enforcing wake-up because wake-up time is earlier than normal (wakeupDefaultTime=$wakeupDefaultTime > lastRun=$lastRun)";
                $wakeupEnforced = 1;
            }

            # conditional enforced wake-up:
            # only if actual wake-up time is not wakeupDefaultTime
            elsif ($wakeupEnforced == 2
                && $wakeupDefaultTime
                && $wakeupDefaultTime ne $lastRun )
            {
                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "Enforcing wake-up because wake-up is different from normal (wakeupDefaultTime=$wakeupDefaultTime =! lastRun=$lastRun)";
                $wakeupEnforced = 1;
            }
            elsif ( $wakeupEnforced > 1 ) {
                $wakeupEnforced = 0;
            }

            Log3 $NAME, 4,
              "RESIDENTStk $NAME: " . "trigger $wakeupMacro (running=1)";
            fhem "trigger $wakeupMacro "
              . "start $lastRun $wakeupOffset $wakeupEnforced $wakeupUserdevice $wakeupUserdeviceState";

            # Update user device with last wakeup details
            #
            readingsBeginUpdate( $defs{$wakeupUserdevice} );
            readingsBulkUpdate( $defs{$wakeupUserdevice},
                "lastWakeup", $lastRun );
            readingsBulkUpdate( $defs{$wakeupUserdevice},
                "lastWakeupDev", $NAME );
            readingsBulkUpdate( $defs{$wakeupUserdevice}, "wakeup", "1" );
            readingsEndUpdate( $defs{$wakeupUserdevice}, 1 );

            readingsSingleUpdate( $defs{$wakeupUserdevice}, "wakeup", "0", 1 )
              unless ($wakeupOffset);

            readingsSingleUpdate( $defs{$NAME}, "lastRun", $lastRun, 1 );

            if ($wakeupOffset) {
                my $wakeupStopAtdevice = $wakeupAtdevice . "_stop";
                fhem "delete $wakeupStopAtdevice"
                  if ( IsDevice($wakeupStopAtdevice) );

                Log3 $NAME, 4,
                  "RESIDENTStk $NAME: "
                  . "created at-device $wakeupStopAtdevice to stop wake-up program in $wakeupOffset minutes";
                fhem "define $wakeupStopAtdevice at +"
                  . RESIDENTStk_sec2time( $wakeupOffset * 60 + 1 )
                  . " set $NAME:FILTER=running=1 stop triggerpost";
                fhem "attr $wakeupStopAtdevice "
                  . "comment Auto-created by RESIDENTS Toolkit: temp. at-device to stop wake-up program of timer $NAME when wake-up time is reached";

                $running = 1;
            }
        }
    }

    if ( $running && $wakeupOffset ) {
        readingsBeginUpdate( $defs{$NAME} );
        readingsBulkUpdate( $defs{$NAME}, "running", "1" );
        readingsBulkUpdate( $defs{$NAME}, "state",   "running" );
        readingsEndUpdate( $defs{$NAME}, 1 );
    }

    # Update user device with next wakeup details
    #
    readingsBeginUpdate( $defs{$wakeupUserdevice} );
    my ( $nextWakeupDev, $nextWakeup ) =
      RESIDENTStk_wakeupGetNext( $wakeupUserdevice, $NAME );
    if ( !$nextWakeupDev || !$nextWakeup ) {
        $nextWakeupDev = "";
        $nextWakeup    = "OFF";
    }
    readingsBulkUpdateIfChanged( $defs{$wakeupUserdevice},
        "nextWakeupDev", $nextWakeupDev );
    readingsBulkUpdateIfChanged( $defs{$wakeupUserdevice},
        "nextWakeup", $nextWakeup );
    readingsEndUpdate( $defs{$wakeupUserdevice}, 1 );

    my $doReset = 1;
    if (   IsDevice( $wakeupResetSwitcher, "dummy" )
        && ReadingsVal( $wakeupResetSwitcher, "state", 0 ) eq "off" )
    {
        $doReset = 0;
    }

    if ( $wakeupDefaultTime && $rdays{$today} && $doReset ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: " . "Resetting based on wakeupDefaultTime";
        fhem "set $NAME:FILTER=state!=$wakeupDefaultTime "
          . "nextRun $wakeupDefaultTime";
    }
    elsif ( !$running ) {
        readingsBeginUpdate( $defs{$NAME} );
        readingsBulkUpdateIfChanged( $defs{$NAME}, "state", $nextRun );
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

    # wakeupResetSwitcher
    if ( $aName eq "wakeupResetSwitcher" ) {
        if ( $init_done && $cmd eq "set" ) {
            if ( !IsDevice($aVal) ) {
                my $alias = AttrVal( $name, "alias", 0 );
                my $group = AttrVal( $name, "group", 0 );
                my $room  = AttrVal( $name, "room",  0 );

                fhem "define $aVal dummy";
                fhem "attr $aVal "
                  . "comment Auto-created by RESIDENTS Toolkit: easy switch between on/off for auto time reset of wake-up timer $NAME";
                if ($alias) {
                    fhem "attr $aVal alias $alias Reset";
                }
                else {
                    fhem "attr $aVal alias Wake-up Timer Reset";
                }
                fhem "attr $aVal "
                  . "devStateIcon auto:time_automatic:off off:time_manual_mode:auto";
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
        }

        my $wakeupUserdevice = AttrVal( $name, "wakeupUserdevice", undef );
        if ( IsDevice( $wakeupUserdevice, "ROOMMATE|GUEST" ) ) {
            RESIDENTStk_findDummySlaves($wakeupUserdevice);
        }
    }

    return undef;
}

#####################################
# GENERAL USER AUTOMATION FUNCTIONS
#------------------------------------
#

sub RESIDENTStk_wakeupGetNext($;$) {
    my ( $name, $wakeupDeviceRunning ) = @_;
    my $wakeupDeviceAttrName = "";

    $wakeupDeviceAttrName = "rgr_wakeupDevice"
      if ( defined( $attr{$name}{"rgr_wakeupDevice"} ) );
    $wakeupDeviceAttrName = "rr_wakeupDevice"
      if ( defined( $attr{$name}{"rr_wakeupDevice"} ) );
    $wakeupDeviceAttrName = "rg_wakeupDevice"
      if ( defined( $attr{$name}{"rg_wakeupDevice"} ) );

    my $wakeupDeviceList = AttrVal( $name, $wakeupDeviceAttrName, 0 );

    my ( $sec, $min, $hour, $mday, $mon, $year, $today, $yday, $isdst ) =
      localtime(time);

    $hour = "0" . $hours if ( $hour < 10 );
    $min  = "0" . $min   if ( $min < 10 );

    my $tomorrow = $today + 1;
    $tomorrow = 0 if ( $tomorrow == 7 );
    my $secNow = RESIDENTStk_time2sec( $hour . ":" . $min ) + $sec;
    my $definitiveNextToday;
    my $definitiveNextTomorrow;
    my $definitiveNextTodayDev;
    my $definitiveNextTomorrowDev;

    my $holidayDevice = AttrVal( "global", "holiday2we", 0 );

    # check for each registered wake-up device
    for my $wakeupDevice ( split /,/, $wakeupDeviceList ) {
        if ( !IsDevice($wakeupDevice) ) {
            Log3 $name, 4,
              "RESIDENTStk $name: "
              . "00 - ignoring reference to non-existing wakeupDevice $wakeupDevice";

            my $wakeupDeviceListNew = $wakeupDeviceList;
            $wakeupDeviceListNew =~ s/,$wakeupDevice,/,/g;
            $wakeupDeviceListNew =~ s/$wakeupDevice,//g;
            $wakeupDeviceListNew =~ s/,$wakeupDevice//g;

            if ( $wakeupDeviceListNew ne $wakeupDeviceList ) {
                Log3 $name, 3,
                  "RESIDENTStk $name: "
                  . "reference to non-existing wakeupDevice '$wakeupDevice' was removed";
                fhem "attr $name $wakeupDeviceAttrName $wakeupDeviceListNew";
            }

            next;
        }

        my $wakeupAtdevice = AttrVal( $wakeupDevice, "wakeupAtdevice", undef );
        my $wakeupOffset =
          ReadingsVal( $wakeupDevice, "wakeupOffset",
            AttrVal( $wakeupDevice, "wakeupOffset", 0 ) );
        my $wakeupAtNTM = (
            IsDevice($wakeupAtdevice)
              && defined( $defs{$wakeupAtdevice}{NTM} )
            ? substr( $defs{$wakeupAtdevice}{NTM}, 0, -3 )
            : undef
        );
        my $wakeupDays =
          ReadingsVal( $wakeupDevice, "wakeupDays",
            AttrVal( $wakeupDevice, "wakeupDays", "" ) );
        my $wakeupHolidays =
          ReadingsVal( $wakeupDevice, "wakeupHolidays",
            AttrVal( $wakeupDevice, "wakeupHolidays", "" ) );
        my $holidayToday    = 0;
        my $holidayTomorrow = 0;
        my $nextRunSrc;
        my $nextRun   = ReadingsVal( $wakeupDevice, "nextRun", undef );
        my $ltoday    = $today;
        my $ltomorrow = $tomorrow;

        if (   IsDisabled($wakeupDevice)
            || !$nextRun
            || lc($nextRun) eq "off"
            || $nextRun !~ /^([0-9]{2}:[0-9]{2})$/ )
        {
            Log3 $name, 4,
              "RESIDENTStk $name: "
              . "00 - ignoring disabled wakeupDevice $wakeupDevice";
            next;
        }

        Log3 $name, 4,
          "RESIDENTStk $name: "
          . "00 - checking for next wake-up candidate $wakeupDevice";

        # get holiday status for today and tomorrow
        if ( $wakeupHolidays eq "" ) {
            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: 01 - Not considering any holidays";
        }
        elsif ( IsDevice( $holidayDevice, "holiday" ) ) {
            $holidayToday = 1
              unless (
                ReadingsVal( $holidayDevice, "state", "none" ) eq "none" );
            $holidayTomorrow = 1
              unless (
                ReadingsVal( $holidayDevice, "tomorrow", "none" ) eq "none" );

            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: "
              . "01 - Holidays to be considered ($wakeupHolidays) - holidayToday=$holidayToday holidayTomorrow=$holidayTomorrow";
        }

        # set day scope for today
        my @days = ($ltoday);
        @days = split /,/, $wakeupDays
          if ( $wakeupDays ne "" );
        my %days = map { $_ => 1 } @days;

        # set day scope for tomorrow
        my @daysTomorrow = ($ltomorrow);
        @daysTomorrow = split /,/, $wakeupDays
          if ( $wakeupDays ne "" );
        my %daysTomorrow = map { $_ => 1 } @daysTomorrow;

        Log3 $name, 4,
          "RESIDENTStk $wakeupDevice: "
          . "02 - possible candidate found - weekdayToday=$ltoday weekdayTomorrow=$ltomorrow";

        my $nextRunSec;
        my $nextRunSecTarget;

        # Use direct information from at-device if possible
        if (   $wakeupAtNTM
            && $wakeupAtNTM =~ /^([0-9]{2}:[0-9]{2})$/ )
        {
            $nextRunSrc       = "at";
            $nextRunSec       = RESIDENTStk_time2sec($wakeupAtNTM);
            $nextRunSecTarget = $nextRunSec + $wakeupOffset * 60;

            if ( $wakeupOffset && $nextRunSecTarget >= 86400 ) {
                $nextRunSecTarget -= 86400;

                $ltoday++;
                $ltoday = $ltoday - 7
                  if ( $ltoday > 6 );

                $ltomorrow++;
                $ltomorrow = $ltomorrow - 7
                  if ( $ltomorrow > 6 );
            }

            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: "
              . "03 - considering at-device value wakeupAtNTM=$wakeupAtNTM wakeupOffset=$wakeupOffset nextRunSec=$nextRunSec nextRunSecTarget=$nextRunSecTarget";
        }
        else {
            $nextRunSrc       = "dummy";
            $nextRunSecTarget = RESIDENTStk_time2sec($nextRun);
            $nextRunSec       = $nextRunSecTarget - $wakeupOffset * 60;

            if ( $wakeupOffset && $nextRunSec < 0 ) {
                $nextRunSec += 86400;

                $ltoday--;
                $ltoday = $ltoday + 7
                  if ( $ltoday < 0 );

                $ltomorrow--;
                $ltomorrow = $ltomorrow + 7
                  if ( $ltomorrow < 0 );
            }

            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: "
              . "03 - considering dummy-device value nextRun=$nextRun wakeupOffset=$wakeupOffset nextRunSec=$nextRunSec nextRunSecTarget=$nextRunSecTarget (wakeupAtNTM=$wakeupAtNTM)";
        }

        # still running today
        if ( $nextRunSec > $secNow ) {
            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: "
              . "04 - this is a candidate for today - weekdayToday=$ltoday";

            # if today is in scope
            if ( $days{$ltoday} ) {

                # if we need to consider holidays in addition
                if (
                    ( $wakeupHolidays eq "andHoliday" && !$holidayToday )
                    || (   $wakeupHolidays eq "andNoHoliday"
                        && $holidayToday )
                  )
                {
                    Log3 $name, 4,
                      "RESIDENTStk $wakeupDevice: "
                      . "05 - no run today due to holiday based on combined weekday and holiday decision";
                    next;
                }

                # easy if there is no holiday dependency
                elsif ( !$definitiveNextToday
                    || $nextRunSec < $definitiveNextToday )
                {
                    Log3 $name, 4,
                      "RESIDENTStk $wakeupDevice: "
                      . "05 - until now, will be NEXT WAKE-UP RUN today based on weekday decision";
                    $definitiveNextToday    = $nextRunSec;
                    $definitiveNextTodayDev = $wakeupDevice;
                }
            }

            elsif ($wakeupHolidays eq ""
                || $wakeupHolidays eq "andHoliday"
                || $wakeupHolidays eq "andNoHoliday" )
            {
                Log3 $name, 4,
                  "RESIDENTStk $wakeupDevice: "
                  . "05 - won't be running today anymore based on weekday decision";
                next;
            }

            # if we need to consider holidays in parallel to weekdays
            elsif (( $wakeupHolidays eq "orHoliday" && !$holidayToday )
                || ( $wakeupHolidays eq "orNoHoliday" && $holidayToday ) )
            {
                Log3 $name, 4,
                  "RESIDENTStk $wakeupDevice: "
                  . "06 - won't be running today based on holiday decision";
                next;
            }

            # easy if there is no holiday dependency
            elsif ( !$definitiveNextToday
                || $nextRunSec < $definitiveNextToday )
            {
                Log3 $name, 4,
                  "RESIDENTStk $wakeupDevice: "
                  . "06 - until now, will be NEXT WAKE-UP RUN today based on holiday decision";
                $definitiveNextToday    = $nextRunSec;
                $definitiveNextTodayDev = $wakeupDevice;
            }
        }

        # running later
        else {
            Log3 $name, 4,
              "RESIDENTStk $wakeupDevice: "
              . "04 - this is a candidate for tomorrow or later - weekdayTomorrow=$ltomorrow";

            # if tomorrow is in scope
            if ( $daysTomorrow{$ltomorrow} ) {

                # if we need to consider holidays in addition
                if (
                    ( $wakeupHolidays eq "andHoliday" && !$holidayTomorrow )
                    || (   $wakeupHolidays eq "andNoHoliday"
                        && $holidayTomorrow )
                  )
                {
                    Log3 $name, 4,
                      "RESIDENTStk $wakeupDevice: "
                      . "05 - no run tomorrow due to holiday based on combined weekday and holiday decision";
                    next;
                }

                # easy if there is no holiday dependency
                elsif ( !$definitiveNextTomorrow
                    || $nextRunSec < $definitiveNextTomorrow )
                {
                    Log3 $name, 4,
                      "RESIDENTStk $wakeupDevice: "
                      . "05 - until now, will be NEXT WAKE-UP RUN tomorrow based on weekday decision";
                    $definitiveNextTomorrow    = $nextRunSec;
                    $definitiveNextTomorrowDev = $wakeupDevice;
                }
            }

            elsif ($wakeupHolidays eq ""
                || $wakeupHolidays eq "andHoliday"
                || $wakeupHolidays eq "andNoHoliday" )
            {
                Log3 $name, 4,
                  "RESIDENTStk $wakeupDevice: "
                  . "05 - won't be running tomorrow based on weekday decision";
                next;
            }

            # if we need to consider holidays in parallel to weekdays
            elsif (
                ( $wakeupHolidays eq "orHoliday" && !$holidayTomorrow )
                || (   $wakeupHolidays eq "orNoHoliday"
                    && $holidayTomorrow )
              )
            {
                Log3 $name, 4,
                  "RESIDENTStk $wakeupDevice: "
                  . "06 - won't be running tomorrow based on holiday decision";
                next;
            }

            # easy if there is no holiday dependency
            elsif ( !$definitiveNextTomorrow
                || $nextRunSec < $definitiveNextTomorrow )
            {
                Log3 $name, 4,
                  "RESIDENTStk $wakeupDevice: "
                  . "06 - until now, will be NEXT WAKE-UP RUN tomorrow based on holiday decision";
                $definitiveNextTomorrow    = $nextRunSec;
                $definitiveNextTomorrowDev = $wakeupDevice;
            }
        }

        if ($wakeupOffset) {

            # add Offset
            $definitiveNextToday += $wakeupOffset * 60
              if ( defined($definitiveNextToday) );
            $definitiveNextTomorrow += $wakeupOffset * 60
              if ( defined($definitiveNextTomorrow) );

            if ( $definitiveNextToday >= 86400 ) {
                $definitiveNextToday -= 86400;
            }
            elsif ( $definitiveNextToday < 0 ) {
                $definitiveNextToday += 86400;
            }

            if ( $definitiveNextTomorrow >= 86400 ) {
                $definitiveNextTomorrow -= 86400;
            }
            elsif ( $definitiveNextTomorrow < 0 ) {
                $definitiveNextTomorrow += 86400;
            }
        }
    }

    if (   defined($definitiveNextTodayDev)
        && defined($definitiveNextToday) )
    {
        Log3 $name, 4,
            "RESIDENTStk $name: 07 - next wake-up result: today at "
          . RESIDENTStk_sec2time($definitiveNextToday)
          . ", wakeupDevice="
          . $definitiveNextTodayDev;

        return ( $definitiveNextTodayDev,
            substr( RESIDENTStk_sec2time($definitiveNextToday), 0, -3 ) );
    }
    elsif (defined($definitiveNextTomorrowDev)
        && defined($definitiveNextTomorrow) )
    {
        Log3 $name, 4,
            "RESIDENTStk $name: 07 - next wake-up result: tomorrow at "
          . RESIDENTStk_sec2time($definitiveNextTomorrow)
          . ", wakeupDevice="
          . $definitiveNextTomorrowDev;

        return ( $definitiveNextTomorrowDev,
            substr( RESIDENTStk_sec2time($definitiveNextTomorrow), 0, -3 ) );
    }

    return ( undef, undef );
}

#####################################
# GENERAL FUNCTIONS USED IN RESIDENTS, ROOMMATE, GUEST
#------------------------------------
#

#
# Make a summary of two time designations
#
sub RESIDENTStk_TimeSum($$) {
    my ( $val1, $val2 ) = @_;
    my ( $timestamp1, $timestamp2, $math );

    if ( $val1 !~ /^([0-9]{2}):([0-9]{2})$/ ) {
        return $val1;
    }
    else {
        $timestamp1 = RESIDENTStk_time2sec($val1);
    }

    if ( $val2 =~ /^([\+\-])([0-9]{2}):([0-9]{2})$/ ) {
        $math       = $1;
        $timestamp2 = RESIDENTStk_time2sec("$2:$3");
    }
    elsif ( $val2 =~ /^([\+\-])([0-9]*)$/ ) {
        $math       = $1;
        $timestamp2 = $2 * 60;
    }
    else {
        return $val1;
    }

    if ( $math eq "-" ) {
        return
          substr( RESIDENTStk_sec2time( $timestamp1 - $timestamp2 ), 0, -3 );
    }
    else {
        return
          substr( RESIDENTStk_sec2time( $timestamp1 + $timestamp2 ), 0, -3 );
    }

}

sub RESIDENTStk_TimeDiff ($$;$) {
    my ( $datetimeNow, $datetimeOld, $format ) = @_;

    if ( $datetimeNow eq "" || $datetimeOld eq "" ) {
        Log3 $name, 5,
          "RESIDENTStk $name: "
          . "empty data: datetimeNow='$datetimeNow' datetimeOld='$datetimeOld'";
        $datetimeNow = "1970-01-01 00:00:00";
        $datetimeOld = "1970-01-01 00:00:00";
    }

    my $timestampNow = time_str2num($datetimeNow);
    my $timestampOld = time_str2num($datetimeOld);
    my $timeDiff     = $timestampNow - $timestampOld;

    # return seconds
    return round( $timeDiff, 0 )
      if ( defined($format) && $format eq "sec" );

    # return minutes
    return round( $timeDiff / 60, 0 )
      if ( defined($format) && $format eq "min" );

    # return human readable format
    return RESIDENTStk_sec2time( round( $timeDiff, 0 ) );
}

sub RESIDENTStk_sec2time($) {
    my ($sec) = @_;

    # return human readable format
    my $hours =
      ( abs($sec) < 3600 ? 0 : int( abs($sec) / 3600 ) );
    $sec -= ( $hours == 0 ? 0 : ( $hours * 3600 ) );
    my $minutes = ( abs($sec) < 60 ? 0 : int( abs($sec) / 60 ) );
    my $seconds = abs($sec) % 60;

    $hours   = "0" . $hours   if ( $hours < 10 );
    $minutes = "0" . $minutes if ( $minutes < 10 );
    $seconds = "0" . $seconds if ( $seconds < 10 );

    return "$hours:$minutes:$seconds";
}

sub RESIDENTStk_time2sec($) {
    my ($s) = @_;
    my @t = split /:/, $s;
    $t[2] = 0 unless ( $t[2] );

    return $t[0] * 3600 + $t[1] * 60 + $t[2];
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

sub RESIDENTStk_RG_StartInternalTimers($$) {
    my ($hash) = @_;

    RESIDENTStk_RG_AutoGone($hash);
    RESIDENTStk_RG_DurationTimer($hash);
}

sub RESIDENTStk_RG_StopInternalTimers($) {
    my ($hash) = @_;

    delete $hash->{AUTOGONE}      if ( $hash->{AUTOGONE} );
    delete $hash->{DURATIONTIMER} if ( $hash->{DURATIONTIMER} );

    RESIDENTStk_RemoveInternalTimer( "AutoGone",      $hash );
    RESIDENTStk_RemoveInternalTimer( "DurationTimer", $hash );
}

sub RESIDENTStk_findResidentSlaves($;$) {
    my ( $hash, $rgr_wakeupDevice ) = @_;
    return
      unless ( ref($hash) eq "HASH" && defined( $hash->{NAME} ) );

    $hash->{NOTIFYDEV} = "";

    delete $hash->{ROOMMATES};
    foreach ( devspec2array("TYPE=ROOMMATE") ) {
        next
          unless (
            defined( $defs{$_}{RESIDENTGROUPS} )
            && grep { $hash->{NAME} eq $_ }
            split( /,/, $defs{$_}{RESIDENTGROUPS} )
          );
        $hash->{ROOMMATES} .= "," if ( $hash->{ROOMMATES} );
        $hash->{ROOMMATES} .= $_;
    }

    delete $hash->{GUESTS};
    foreach ( devspec2array("TYPE=GUEST") ) {
        next
          unless (
            defined( $defs{$_}{RESIDENTGROUPS} )
            && grep { $hash->{NAME} eq $_ }
            split( /,/, $defs{$_}{RESIDENTGROUPS} )
          );
        $hash->{GUESTS} .= "," if ( $hash->{GUESTS} );
        $hash->{GUESTS} .= $_;
    }

    $hash->{NOTIFYDEV} = $hash->{ROOMMATES} if ( $hash->{ROOMMATES} );
    $hash->{NOTIFYDEV} .= "," if ( $hash->{NOTIFYDEV} ne "" );
    $hash->{NOTIFYDEV} .= $hash->{GUESTS} if ( $hash->{GUESTS} );

    RESIDENTStk_findDummySlaves( $hash->{NAME} );
}

sub RESIDENTStk_findDummySlaves($;$$) {
    my ( $name, $wakeupDevice, $presenceDevices ) = @_;
    my $hash   = $defs{$name};
    my $TYPE   = GetType($name);
    my $prefix = RESIDENTStk_GetPrefixFromType($name);

    $wakeupDevice = AttrVal( $name, $prefix . "wakeupDevice", undef )
      unless ( !$init_done || $wakeupDevice );
    $presenceDevices = AttrVal( $name, $prefix . "presenceDevices", undef )
      unless ( !$init_done || $presenceDevices );

    $hash->{NOTIFYDEV} = "global" unless ( $prefix eq "rgr_" );

    if ($wakeupDevice) {
        $hash->{NOTIFYDEV} .= "," if ( $hash->{NOTIFYDEV} ne "" );
        $hash->{NOTIFYDEV} .= $wakeupDevice;

        my @wakeupdevs =
          split( ',', $wakeupDevice );

        foreach (@wakeupdevs) {
            my $rsw;
            next unless ( IsDevice($_) );

            $rsw = AttrVal( $_, "wakeupResetSwitcher", "" ) if ($init_done);

            if ( $rsw =~ /^[a-zA-Z\d._]+$/ ) {
                $hash->{NOTIFYDEV} .= "," if ( $hash->{NOTIFYDEV} ne "" );
                $hash->{NOTIFYDEV} .= $rsw;
            }
        }
    }

    if ($presenceDevices) {
        $hash->{NOTIFYDEV} .= "," if ( $hash->{NOTIFYDEV} ne "" );
        $hash->{NOTIFYDEV} .= $presenceDevices;
    }
}

sub RESIDENTStk_GetPrefixFromType($) {
    my ($name) = @_;
    return "rgr_" if ( GetType($name) eq "RESIDENTS" );
    return "rr_"  if ( GetType($name) eq "ROOMMATE" );
    return "rg_"  if ( GetType($name) eq "GUEST" );
    return "";
}

sub RESIDENTStk_RG_Attr(@) {
    my ( $cmd, $name, $attribute, $value ) = @_;
    my $hash   = $defs{$name};
    my $prefix = RESIDENTStk_GetPrefixFromType($name);

    if (   $attribute eq $prefix . "wakeupDevice"
        || $attribute eq $prefix . "presenceDevices" )
    {
        return "Value for $attribute has invalid format"
          unless ( $cmd eq "del"
            || $value =~ /^([a-zA-Z\d._]+,?)([a-zA-Z\d._]+,?)*$/ );

        $value = "" if ( $cmd eq "del" );

        my $wakeupDevice =
            $attribute eq $prefix . "wakeupDevice"
          ? $value
          : AttrVal( $name, $prefix . "wakeupDevice", undef );
        my $presenceDevices =
            $attribute eq $prefix . "presenceDevices"
          ? $value
          : AttrVal( $name, $prefix . "presenceDevices", undef );

        RESIDENTStk_findDummySlaves( $name, $wakeupDevice, $presenceDevices );
    }

    elsif ( !$init_done ) {
        return undef;
    }

    elsif ( $attribute eq "disable" ) {
        if ( $value and $value == 1 ) {
            $hash->{STATE} = "disabled";
            RESIDENTStk_RG_StopInternalTimers($hash);
        }
        elsif ( $cmd eq "del" or !$value ) {
            evalStateFormat($hash);
            RESIDENTStk_RG_StartInternalTimers( $hash, 1 );
        }
    }

    elsif ( $attribute eq $prefix . "autoGoneAfter" ) {
        if ($value) {
            RESIDENTStk_RG_AutoGone($hash);
        }
        elsif ( !$value ) {
            delete $hash->{AUTOGONE} if ( $hash->{AUTOGONE} );
            RESIDENTStk_RemoveInternalTimer( "AutoGone", $hash );
        }
    }

    elsif ( $attribute eq $prefix . "noDuration" ) {
        if ($value) {
            delete $hash->{DURATIONTIMER} if ( $hash->{DURATIONTIMER} );
            RESIDENTStk_RemoveInternalTimer( "DurationTimer", $hash );
        }
        elsif ( !$value ) {
            RESIDENTStk_RG_DurationTimer($hash);
        }
    }

    elsif ( $attribute eq $prefix . "lang" ) {
        my $lang =
          $cmd eq "set" ? uc($value) : AttrVal( "global", "language", "EN" );

        # for initial define, ensure fallback to EN
        $lang = "EN"
          if ( $cmd eq "init" && $lang !~ /^EN|DE$/i );

        if ( $lang eq "DE" ) {
            $attr{$name}{devStateIcon} =
'.*zuhause:user_available:absent .*anwesend:user_available:absent .*abwesend:user_away:home .*verreist:user_ext_away:home .*bettfertig:scene_toilet:asleep .*schlaeft:scene_sleeping:awoken .*schläft:scene_sleeping:awoken .*aufgestanden:scene_sleeping_alternat:home .*:user_unknown:home';
            $attr{$name}{eventMap} =
"home:zuhause absent:abwesend gone:verreist gotosleep:bettfertig asleep:schläft awoken:aufgestanden";
            $attr{$name}{widgetOverride} =
"state:zuhause,bettfertig,schläft,aufgestanden,abwesend,verreist";
        }
        elsif ( $lang eq "EN" ) {
            $attr{$name}{devStateIcon} =
'.*home:user_available:absent .*absent:user_away:home .*gone:user_ext_away:home .*gotosleep:scene_toilet:asleep .*asleep:scene_sleeping:awoken .*awoken:scene_sleeping_alternat:home .*:user_unknown:home';
            delete $attr{$name}{eventMap}
              if ( defined( $attr{$name}{eventMap} ) );
            delete $attr{$name}{widgetOverride}
              if ( defined( $attr{$name}{widgetOverride} ) );
        }
        else {
            return "Unsupported language $lang";
        }

        evalStateFormat($hash);
    }

    return undef;
}

sub RESIDENTStk_RG_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name    = $hash->{NAME};
    my $TYPE    = GetType($name);
    my $prefix  = RESIDENTStk_GetPrefixFromType($name);
    my $devName = $dev->{NAME};
    return "" if ( IsDisabled($name) or IsDisabled($devName) );

    if ( $devName eq "global" ) {
        my $events = deviceEvents( $dev, 0 );
        return ""
          unless ( $events && grep( m/^INITIALIZED|REREADCFG$/, @{$events} ) );
        RESIDENTStk_findDummySlaves($name);
        return "";
    }

    delete $dev->{CHANGEDWITHSTATE};
    my $events = deviceEvents( $dev, 1 );
    return "" unless ($events);

    # process wakeup devices
    my @registeredWakeupdevs =
      split( ',', AttrVal( $name, $prefix . "wakeupDevice", "" ) );
    if (@registeredWakeupdevs) {

        # if this is a notification of a registered wakeup device
        if ( grep { m/^$devName$/ } @registeredWakeupdevs ) {

            foreach my $event ( @{$events} ) {
                next unless ( defined($event) );
                RESIDENTStk_wakeupSet( $devName, $event );
            }

            return "";
        }

        # process sub-child notifies: *_wakeupDevice
        foreach my $wakeupDev (@registeredWakeupdevs) {

            # if this is a notification of a registered sub dummy device
            # of one of our wakeup devices
            if (   AttrVal( $wakeupDev, "wakeupResetSwitcher", "" ) eq $devName
                && IsDevice( $devName, "dummy" ) )
            {
                foreach my $event ( @{$events} ) {
                    next unless ( defined($event) );
                    RESIDENTStk_wakeupSet( $wakeupDev, $event )
                      unless ( $event =~ /^(?:state:\s*)?off$/i );
                }

                return "";
            }
        }

        return "";
    }

    # process PRESENCE
    my @presenceDevices =
      split( ',', AttrVal( $name, $prefix . "presenceDevices", "" ) );
    if ( @presenceDevices
        && grep { /^[\s\t ]*$devName(:[A-Za-z\d_\.\-\/]*)?[\s\t ]*$/ }
        @presenceDevices )
    {

        my $counter = {
            absent  => 0,
            present => 0,
        };

        for (@presenceDevices) {
            my $r = "presence";
            my $d = $_;
            if ( $d =~
                m/^[\s\t ]*([A-Za-z\d_\.\-\/]+):([A-Za-z\d_\.\-\/]+)?[\s\t ]*$/
              )
            {
                $d = $1;
                $r = $2;
            }

            my $presenceState =
              ReadingsVal( $d, $r, ReadingsVal( $d, "state", "" ) );
            next
              unless ( $presenceState =~
m/^(0|false|absent|disappeared|unavailable|unreachable|disconnected)|(1|true|present|appeared|available|reachable|connected|)$/i
              );

            $counter->{absent}++  if ($1);
            $counter->{present}++ if ($2);
        }

        if ( $counter->{absent} && !$counter->{present} ) {
            Log3 $name, 4,
              "$TYPE $name: " . "Syncing status with $devName = absent";
            fhem "set $name:FILTER=presence=present absent";
        }
        elsif ( $counter->{present} ) {
            Log3 $name, 4,
              "$TYPE $name: " . "Syncing status with $devName = present";
            fhem "set $name:FILTER=presence=absent home";
        }

        return "";
    }

    return "";
}

sub RESIDENTStk_RG_AutoGone($;$) {
    my ( $mHash, @a ) = @_;
    my $hash          = ( $mHash->{HASH} ) ? $mHash->{HASH} : $mHash;
    my $name          = $hash->{NAME};
    my $TYPE          = GetType($name);
    my $prefix        = RESIDENTStk_GetPrefixFromType($name);
    my $autoGoneAfter = AttrVal( $hash->{NAME}, $prefix . "autoGoneAfter", 36 );
    delete $hash->{AUTOGONE} if ( $hash->{AUTOGONE} );

    RESIDENTStk_RemoveInternalTimer( "AutoGone", $hash );

    return if ( IsDisabled($name) || !$autoGoneAfter );

    if ( ReadingsVal( $name, "state", "home" ) eq "absent" ) {
        my ( $date, $time, $y, $m, $d, $hour, $min, $sec, $timestamp,
            $timeDiff );
        my $timestampNow = gettimeofday();

        ( $date, $time ) = split( ' ', $hash->{READINGS}{state}{TIME} );
        ( $y,    $m,   $d )   = split( '-', $date );
        ( $hour, $min, $sec ) = split( ':', $time );
        $m -= 01;
        $timestamp = timelocal( $sec, $min, $hour, $d, $m, $y );
        $timeDiff = $timestampNow - $timestamp;

        if ( $timeDiff >= $autoGoneAfter * 3600 ) {
            Log3 $name, 3,
              "$TYPE $name: AutoGone timer changed state to 'gone'";
            &{ $TYPE . "_Set" }( $hash, $name, "silentSet", "state", "gone" );
        }
        else {
            my $runtime = $timestamp + $autoGoneAfter * 3600;
            $hash->{AUTOGONE} = $runtime;
            Log3 $name, 4, "$TYPE $name: AutoGone timer scheduled: $runtime";
            RESIDENTStk_InternalTimer( "AutoGone", $runtime,
                "RESIDENTStk_RG_AutoGone", $hash, 1 );
        }
    }

    return undef;
}

sub RESIDENTStk_RG_DurationTimer($;$) {
    my ( $mHash, @a ) = @_;
    my $hash         = ( $mHash->{HASH} ) ? $mHash->{HASH} : $mHash;
    my $name         = $hash->{NAME};
    my $TYPE         = GetType($name);
    my $prefix       = RESIDENTStk_GetPrefixFromType($name);
    my $silent       = ( defined( $a[0] ) && $a[0] eq "1" ) ? 1 : 0;
    my $timestampNow = gettimeofday();
    my $diff;
    my $durPresence = "0";
    my $durAbsence  = "0";
    my $durSleep    = "0";
    my $noDuration  = AttrVal( $name, $prefix . "noDuration", 0 );
    delete $hash->{DURATIONTIMER} if ( $hash->{DURATIONTIMER} );

    RESIDENTStk_RemoveInternalTimer( "DurationTimer", $hash );

    return if ( IsDisabled($name) || $noDuration );

    # presence timer
    if (   ReadingsVal( $name, "presence", "absent" ) eq "present"
        && ReadingsVal( $name, "lastArrival", "-" ) ne "-" )
    {
        $durPresence =
          $timestampNow -
          time_str2num( ReadingsVal( $name, "lastArrival", "" ) );
    }

    # absence timer
    if (   ReadingsVal( $name, "presence", "present" ) eq "absent"
        && ReadingsVal( $name, "lastDeparture", "-" ) ne "-" )
    {
        $durAbsence =
          $timestampNow -
          time_str2num( ReadingsVal( $name, "lastDeparture", "" ) );
    }

    # sleep timer
    if (   ReadingsVal( $name, "state", "home" ) eq "asleep"
        && ReadingsVal( $name, "lastSleep", "-" ) ne "-" )
    {
        $durSleep =
          $timestampNow - time_str2num( ReadingsVal( $name, "lastSleep", "" ) );
    }

    my $durPresence_hr =
      ( $durPresence > 0 )
      ? RESIDENTStk_sec2time($durPresence)
      : "00:00:00";
    my $durPresence_cr =
      ( $durPresence > 60 ) ? int( $durPresence / 60 + 0.5 ) : 0;
    my $durAbsence_hr =
      ( $durAbsence > 0 ) ? RESIDENTStk_sec2time($durAbsence) : "00:00:00";
    my $durAbsence_cr =
      ( $durAbsence > 60 ) ? int( $durAbsence / 60 + 0.5 ) : 0;
    my $durSleep_hr =
      ( $durSleep > 0 ) ? RESIDENTStk_sec2time($durSleep) : "00:00:00";
    my $durSleep_cr = ( $durSleep > 60 ) ? int( $durSleep / 60 + 0.5 ) : 0;

    readingsBeginUpdate($hash) if ( !$silent );
    readingsBulkUpdateIfChanged( $hash, "durTimerPresence_cr",
        $durPresence_cr );
    readingsBulkUpdateIfChanged( $hash, "durTimerPresence",   $durPresence_hr );
    readingsBulkUpdateIfChanged( $hash, "durTimerAbsence_cr", $durAbsence_cr );
    readingsBulkUpdateIfChanged( $hash, "durTimerAbsence",    $durAbsence_hr );
    readingsBulkUpdateIfChanged( $hash, "durTimerSleep_cr",   $durSleep_cr );
    readingsBulkUpdateIfChanged( $hash, "durTimerSleep",      $durSleep_hr );
    readingsEndUpdate( $hash, 1 ) if ( !$silent );

    $hash->{DURATIONTIMER} = $timestampNow + 60;

    RESIDENTStk_InternalTimer(
        "DurationTimer",
        $hash->{DURATIONTIMER},
        "RESIDENTStk_RG_DurationTimer",
        $hash, 1
    );

    return undef;
}

1;

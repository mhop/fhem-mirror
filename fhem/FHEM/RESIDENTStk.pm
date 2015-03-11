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
# Version: 1.0.0
#
# Version History:
# - 1.0.0 - 2015-03-11
# -- First release
#
##############################################################################

#####################################
# Enslave DUMMY device to be used for alarm clock
#
sub RESIDENTStk_wakeupSet($;$) {
    my ( $NAME, $VALUE ) = @_;
    my $userattr          = AttrVal( $NAME, "userattr",          0 );
    my $autosave          = AttrVal( $NAME, "wakeupAutosave",    0 );
    my $wakeupDefaultTime = AttrVal( $NAME, "wakeupDefaultTime", 0 );
    my $wakeupMacro       = AttrVal( $NAME, "wakeupMacro",       0 );
    my $wakeupAtdevice    = AttrVal( $NAME, "wakeupAtdevice",    0 );
    my $wakeupOffset      = AttrVal( $NAME, "wakeupOffset",      "0" );
    my $room              = AttrVal( $NAME, "room",              0 );
    my $macroName         = "Macro_" . $NAME;
    my $atName            = "at_" . $NAME;

    if ( !$VALUE ) {
        if ($wakeupDefaultTime) {
            Log3 $NAME, 4,
              "RESIDENTStk $NAME: Resetting based on wakeupDefaultTime";
            fhem
              "set $NAME:FILTER=state!=$wakeupDefaultTime $wakeupDefaultTime";
        }
        return;
    }

    # check for required userattr attribute
    my $userattributes =
"wakeupOffset:slider,0,1,120 wakeupDefaultTime:time wakeupMacro wakeupUserdevice wakeupAtdevice wakeupResetSwitcher wakeupResetdays:multiple-strict,0,1,2,3,4,5,6 wakeupDays:multiple-strict,0,1,2,3,4,5,6 wakeupAutosave:1,0";
    if ( !$userattr || $userattr ne $userattributes ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: adjusting dummy device for required attribute userattr";
        fhem "attr $NAME userattr $userattributes";
    }

    # check for required userdevice attribute
    if ( !AttrVal( $NAME, "wakeupUserdevice", 0 ) ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: WARNING - set attribute wakeupUserdevice before running wakeup function";
    }

    # check for required wakeupMacro attribute
    if ( !$wakeupMacro ) {
        Log3 $NAME, 3,
"RESIDENTStk $NAME: adjusting dummy device for required attribute wakeupMacro";
        fhem "attr $NAME wakeupMacro $macroName";
        $wakeupMacro = $macroName;
    }

    # check for existing macro notify device
    if ( !defined( $defs{$wakeupMacro} ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: new notify macro device $wakeupMacro created";
        fhem "define $wakeupMacro notify $wakeupMacro {}";
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
        Log3 $NAME, 3,
"RESIDENTStk $NAME: adjusting dummy device for required attribute wakeupAtdevice";
        fhem "attr $NAME wakeupAtdevice $atName";
        $wakeupAtdevice = $atName;
    }

    # check for existing at device
    if ( !defined( $defs{$wakeupAtdevice} ) ) {
        Log3 $NAME, 3,
          "RESIDENTStk $NAME: new at device $wakeupAtdevice created";
        fhem
"define $wakeupAtdevice at *08:00 { RESIDENTStk_wakeupRun(\"$NAME\") }";
        fhem "attr $wakeupAtdevice comment Auto-created by RESIDENTS Toolkit";
        if ($room) { fhem "attr $wakeupAtdevice room $room" }
    }

# Reset at device if wake-up timer was disabled and wakeupDefaultTime is present
    if ( $VALUE eq "OFF" ) {
        Log3 $NAME, 4, "RESIDENTStk $NAME: Wake-up timer disabled";
        if ($wakeupDefaultTime) {
            $VALUE = $wakeupDefaultTime;
            Log3 $NAME, 4,
"RESIDENTStk $NAME: Wake-up timer disabled and triggered at device reset";
        }
        else {
            Log3 $NAME, 4, "RESIDENTStk $NAME: Wake-up timer disabled";
        }
    }

    # Recalculate new wake-up value
    if ( $VALUE ne "OFF" ) {
        my @time     = split /:/, $VALUE;
        my $time_sec = $time[0] * 3600 + $time[1] * 60;
        my $begin    = $time_sec - $wakeupOffset * 60;
        my $hour     = int( $begin / 3600 );
        my $leftover = $begin % 3600;
        my $min      = int( $leftover / 60 );
        if ( $time_sec < 1800 && $wakeupOffset > 0 ) { $hour = 23 }

        if ( $defs{$wakeupAtdevice}{TYPE} ne "at" ) {
            Log3 $NAME, 3,
"RESIDENTStk $NAME: ERROR - defined device '$wakeupAtdevice' is not an at device!";
        }
        else {
            fhem "modify $wakeupAtdevice *"
              . sprintf( "%02d:%02d", $hour, $min );

            Log3 $NAME, 4,
              "RESIDENTStk $NAME($wakeupAtdevice): Wake-up begin scheduled for "
              . sprintf( "%02d:%02d", $hour, $min );
        }
    }

    # autosave
    if ($autosave) { fhem "save" }

    return undef;
}

#####################################
# Use DUMMY device to run wakup event
#
sub RESIDENTStk_wakeupRun($) {
    my ($NAME) = @_;

    my $wakeupMacro         = AttrVal( $NAME, "wakeupMacro",         0 );
    my $wakeupDefaultTime   = AttrVal( $NAME, "wakeupDefaultTime",   0 );
    my $wakeupUserdevice    = AttrVal( $NAME, "wakeupUserdevice",    0 );
    my $wakeupDays          = AttrVal( $NAME, "wakeupDays",          0 );
    my $wakeupResetdays     = AttrVal( $NAME, "wakeupResetdays",     0 );
    my $wakeupResetSwitcher = AttrVal( $NAME, "wakeupResetSwitcher", 0 );

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
        Log3 $NAME, 3, "RESIDENTStk $NAME: Non existing device";
        return "$NAME: Non existing device";
    }
    elsif ( ReadingsVal( $NAME, "state", "OFF" ) eq "OFF" ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: alarm set to OFF - not running any action";
    }
    elsif ( !$wakeupUserdevice ) {
        Log3 $NAME, 4, "RESIDENTStk $NAME: missing attribute wakeupUserdevice";
        return "$NAME: missing attribute wakeupUserdevice";
    }
    elsif ( !defined( $defs{$wakeupUserdevice} ) ) {
        Log3 $NAME, 4,
          "RESIDENTStk $NAME: Non existing wakeupUserdevice $wakeupUserdevice";
        return "$NAME: Non existing wakeupUserdevice $wakeupUserdevice";
    }
    elsif ($defs{$wakeupUserdevice}{TYPE} ne "ROOMMATE"
        && $defs{$wakeupUserdevice}{TYPE} ne "GUEST" )
    {
        Log3 $NAME, 4,
"RESIDENTStk $NAME: device $wakeupUserdevice is not of type ROOMMATE or GUEST";
        return
          "$NAME: device $wakeupUserdevice is not of type ROOMMATE or GUEST";
    }
    elsif ( $defs{$wakeupUserdevice}{TYPE} eq "GUEST"
        && ReadingsVal( $wakeupUserdevice, "state", "" ) eq "none" )
    {
        fhem "set $NAME OFF";
        return;
    }
    elsif ($wday ~~ @days
        && ReadingsVal( $wakeupUserdevice, "state", "" ) ne "absent"
        && ReadingsVal( $wakeupUserdevice, "state", "" ) ne "gone" )
    {
        if ( !$wakeupMacro ) {
            Log3 $NAME, 2, "RESIDENTStk $NAME: missing attribute wakeupMacro";
            return "$NAME: missing attribute wakeupMacro";
        }
        elsif ( !defined( $defs{$wakeupMacro} ) ) {
            Log3 $NAME, 2,
"RESIDENTStk $NAME: notify macro $wakeupMacro not found - no wakeup actions defined!";
            return
"$NAME: notify macro $wakeupMacro not found - no wakeup actions defined!";
        }
        elsif ( $defs{$wakeupMacro}{TYPE} ne "notify" ) {
            Log3 $NAME, 2,
              "RESIDENTStk $NAME: device $wakeupMacro is not of type notify";
            return "$NAME: device $wakeupMacro is not of type notify";
        }
        else {
            Log3 $NAME, 4, "RESIDENTStk $NAME: trigger $wakeupMacro";
            fhem "trigger $wakeupMacro";
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
        fhem "set $NAME:FILTER=state!=$wakeupDefaultTime $wakeupDefaultTime";
    }

    return undef;
}

#####################################
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

		# del attribute
    elsif ( $cmd eq "del" ) {

        # wakeupResetSwitcher
        if ( $aName eq "wakeupResetSwitcher" ) {
            if ( defined( $defs{$aVal} ) && $defs{$aVal}{TYPE} eq "dummy" ) {
                fhem "delete $aVal";

                Log3 $name, 3,
                  "RESIDENTStk $name: slave dummy device $aVal deleted";
            }
        }

    }

    return undef;
}

1;

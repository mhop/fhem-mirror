###############################################################################
# $Id$
package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Encode;
use Data::Dumper;
use FHEM::Meta;

# initialize ##################################################################
sub THINKINGCLEANER_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "THINKINGCLEANER_Initialize: Entering";

    my $webhookFWinstance =
      join( ",", devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') );

    $hash->{DefFn}       = "THINKINGCLEANER_Define";
    $hash->{UndefFn}     = "THINKINGCLEANER_Undefine";
    $hash->{SetFn}       = "THINKINGCLEANER_Set";
    $hash->{AttrFn}      = "THINKINGCLEANER_Attr";
    $hash->{parseParams} = 1;

    $hash->{AttrList} =
"disable:0,1 disabledForIntervals timeout:1,2,3,4,5 pollInterval:30,45,60,75,90 pollMultiplierWebhook pollMultiplierCleaning model webhookHttpHostname webhookPort webhookFWinstance:$webhookFWinstance restart:noArg "
      . $readingFnAttributes;

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        model   => 'modelid',    # fallback to attribute
        modelid => {
            'Roomba_700_Series' => {
                rname_E => 'energy',
                rname_P => 'consumption',
                map     => {
                    presence => {
                        absent => 0,
                    },
                    deviceStatus => {
                        base         => 0.1,
                        plug         => 0.1,
                        base_recon   => 33,
                        plug_recon   => 33,
                        base_full    => 33,
                        plug_full    => 33,
                        base_trickle => 5,
                        plug_trickle => 5,
                        base_wait    => 0.1,
                        plug_wait    => 0.1,
                        '*'          => 0,
                    },
                },
            },
        },
    };

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

# regular Fn ##################################################################
sub THINKINGCLEANER_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name  = $hash->{NAME};
    my $infix = "THINKINGCLEANER";

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_Define()";

    eval {
        require JSON;
        import JSON qw( decode_json );
    };
    return "Please install Perl JSON to use module THINKINGCLEANER"
      if ($@);

    if ( int(@$a) < 2 ) {
        my $msg =
          "Wrong syntax: define <name> THINKINGCLEANER <ip-or-hostname>";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "THINKINGCLEANER";

    # Initialize the device
    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    my $address = @$a[2];
    $hash->{DeviceName} = $address;

    # set reverse pointer
    $modules{THINKINGCLEANER}{defptr}{$name} = \$hash;

    # set default settings on first define
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        $attr{$name}{cmdIcon} =
'on-max:text_max on-spot:refresh on-delayed:time_timer dock:measure_battery_50 locate:rc_SEARCH';
        $attr{$name}{devStateIcon} =
'on-delayed:rc_STOP@green:off on-max:rc_BLUE@green:off on-spot:rc_GREEN@red:off on.*:rc_GREEN@green:off dock:rc_GREEN@orange:off off:rc_STOP:on standby|remote:rc_YELLOW:on locate:rc_YELLOW .*:rc_RED';
        $attr{$name}{icon}   = 'scene_cleaning';
        $attr{$name}{webCmd} = 'on-max:on-spot:on-delayed:dock:locate';
    }

    if ( THINKINGCLEANER_addExtension( $name, "THINKINGCLEANER_CGI", $infix ) )
    {
        $hash->{fhem}{infix} = $infix;
    }

    $hash->{WEBHOOK_REGISTER} = "unregistered";

    # start the status update timer
    THINKINGCLEANER_GetStatus( $hash, 2 );

    return undef;
}

sub THINKINGCLEANER_Undefine($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    if ( defined( $hash->{fhem}{infix} ) ) {
        THINKINGCLEANER_removeExtension( $hash->{fhem}{infix} );
    }

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    # release reverse pointer
    delete $modules{THINKINGCLEANER}{defptr}{$name};

    return undef;
}

sub THINKINGCLEANER_Set($$$);

sub THINKINGCLEANER_Set($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name         = $hash->{NAME};
    my $state        = ReadingsVal( $name, "state", "absent" );
    my $deviceStatus = ReadingsVal( $name, "deviceStatus", "off" );
    my $presence     = ReadingsVal( $name, "presence", "absent" );
    my $power        = ReadingsVal( $name, "power", "off" );

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_Set()";

    return "Argument is missing" if ( int(@$a) < 1 );

    my $usage =
        "Unknown argument "
      . @$a[1]
      . ", choose one of statusRequest:noArg toggle:noArg on:noArg on-spot:noArg on-max:noArg off:noArg power:off,on dock:noArg undock:noArg locate:noArg on-delayed:noArg cleaningDelay  remoteControl:forward,backward,left,left-spin,right,right-spin,stop,drive scheduleAdd name damageProtection:off,on reboot:noArg autoUpdate:on,off vacuumDrive:off,on restartAC:on,off alwaysMAX:on,off autoDock:on,off keepAwakeOnDock:on,off songSubmit songReset:noArg dockAt stopAt";

    my $cmd = '';
    my $result;

    # find existing schedules and offer set commands
    my $sd0 = ReadingsVal( $name, "schedule0", "" );
    my $sd1 = ReadingsVal( $name, "schedule1", "" );
    my $sd2 = ReadingsVal( $name, "schedule2", "" );
    my $sd3 = ReadingsVal( $name, "schedule3", "" );
    my $sd4 = ReadingsVal( $name, "schedule4", "" );
    my $sd5 = ReadingsVal( $name, "schedule5", "" );
    my $sd6 = ReadingsVal( $name, "schedule6", "" );

    my $schedules = "";
    my $si        = "0";
    foreach ( $sd0, $sd1, $sd2, $sd3, $sd4, $sd5, $sd6 ) {
        if ( $_ ne "" ) {
            $schedules .= "," if ( $schedules ne "" );

            $_ =~ s/(\d+)_(\d{2}:\d{2}:\d{2})_(([A-Za-z]+),?)/$si\_$1_$2_$3/g;
            $schedules .= $_;
        }
        $si++;
    }
    $usage .= " scheduleDel:$schedules scheduleMod:$schedules"
      if ( $schedules ne "" );

    # statusRequest
    if ( lc( @$a[1] ) eq "statusrequest" ) {
        Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];
        THINKINGCLEANER_GetStatus($hash);
    }

    # scheduleAdd
    elsif ( lc( @$a[1] ) eq "scheduleadd" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3,
                "THINKINGCLEANER set $name "
              . @$a[1] . " "
              . @$a[2] . " "
              . @$a[3] . " "
              . @$a[4];

            return
              "Missing arguments. Usage: scheduleAdd <day> <time> <command>"
              if ( !defined( @$a[2] )
                || !defined( @$a[3] )
                || !defined( @$a[4] ) );

            return
"Invalid value for day, needs to be between 0(=sunday) and 6(=saturday)"
              if ( @$a[2] !~ /^[0-6]$/ );

            return "Invalid value for time, needs to be of format 00:00:00"
              if ( @$a[3] !~ /^([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$/ );

            return
              "Invalid value for command, choose one of clean max dock stop"
              if ( @$a[4] !~ /^(clean|max|dock|stop)$/ );

            my $time = THINKINGCLEANER_time2sec( @$a[3] );
            my $command;
            $command = "0"
              if ( @$a[4] eq "clean" );
            $command = "1"
              if ( @$a[4] eq "max" );
            $command = "2"
              if ( @$a[4] eq "dock" );
            $command = "3"
              if ( @$a[4] eq "stop" );

            my $wday = @$a[2] - 1;
            $wday = "6" if ( $wday < 0 );

            $cmd = "$command&day=$wday&time=$time";

            $result =
              THINKINGCLEANER_SendCommand( $hash, "add_schedule.json", $cmd );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # scheduleMod
    elsif ( lc( @$a[1] ) eq "schedulemod" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3,
                "THINKINGCLEANER set $name "
              . @$a[1] . " "
              . @$a[2] . " "
              . @$a[3] . " "
              . @$a[4] . " "
              . @$a[5];

            return
"Missing arguments. Usage: scheduleMod <day> <index> <time> <command>"
              if ( !defined( @$a[2] )
                || !defined( @$a[3] )
                || !defined( @$a[4] ) );

            return
"Invalid value for day, needs to be between 0(=sunday) and 6(=saturday)"
              if ( @$a[2] !~ /^[0-6]/ );

            if ( @$a[2] =~ s/_(\d+)_\d{2}:\d{2}:\d{2}_.*//
                && !defined( @$a[5] ) )
            {
                @$a[4] = @$a[3];
                @$a[5] = @$a[4];
                @$a[3] = $1;
            }

            return "Invalid value for index, needs to be integer value"
              if ( @$a[3] !~ /^\d+$/ );

            return "Invalid value for time, needs to be of format 00:00:00"
              if ( @$a[4] !~ /^([0-1][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]$/ );

            return
              "Invalid value for command, choose one of clean max dock stop"
              if ( @$a[5] !~ /^(clean|max|dock|stop)$/ );

            my $time = THINKINGCLEANER_time2sec( @$a[4] );
            my $command;
            $command = "0"
              if ( @$a[5] eq "clean" );
            $command = "1"
              if ( @$a[5] eq "max" );
            $command = "2"
              if ( @$a[5] eq "dock" );
            $command = "3"
              if ( @$a[5] eq "stop" );

            my $wday = @$a[2] - 1;
            $wday = "6" if ( $wday < 0 );

            $cmd = "$command&day=$wday&index=" . @$a[3] . "&time=$time";

            $result =
              THINKINGCLEANER_SendCommand( $hash, "change_schedule.json",
                $cmd );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # scheduleDel
    elsif ( lc( @$a[1] ) eq "scheduledel" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3,
                "THINKINGCLEANER set $name "
              . @$a[1] . " "
              . @$a[2] . " "
              . @$a[3];

            return "Missing arguments. Usage: scheduleDel <day> <index>"
              if ( !defined( @$a[2] ) );

            return
"Invalid value for day, needs to be between 0(=sunday) and 6(=saturday)"
              if ( @$a[2] !~ /^[0-6]/ );

            @$a[3] = $1
              if ( @$a[2] =~ s/_(\d+)_\d{2}:\d{2}:\d{2}_.*//
                && !defined( @$a[3] ) );

            return "Invalid value for index, needs to be integer value"
              if ( @$a[3] !~ /^\d+$/ );

            my $wday = @$a[2] - 1;
            $wday = "6" if ( $wday < 0 );

            $cmd = "&day=$wday&index=" . @$a[3];

            $result =
              THINKINGCLEANER_SendCommand( $hash, "remove_schedule.json",
                $cmd );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # remoteControl
    elsif ( lc( @$a[1] ) eq "remotecontrol" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3,
                "THINKINGCLEANER set $name "
              . @$a[1] . " "
              . @$a[2] . " "
              . @$a[3];

            return
"No argument given, choose one of forward left right left-spin right-spin stop drive"
              if ( !defined( @$a[2] ) );

            if ( $power eq "off" ) {
                $result =
                  THINKINGCLEANER_SendCommand( $hash, "command.json",
                    "forward", "power" );
                return
                    fhem "sleep 2;set $name "
                  . @$a[1] . " "
                  . @$a[2] . " "
                  . @$a[3];
            }

            if ( @$a[2] eq "forward" ) {
                $cmd = @$a[2];
            }
            elsif ( @$a[2] eq "backward" ) {
                $cmd = "drive_only&speed=-200&degrees=180";
            }
            elsif ( @$a[2] =~ /^(left|right|stop)$/ ) {
                $cmd = "drive" . @$a[2];
            }
            elsif ( @$a[2] =~ /^(left|right|stop|left-spin|right-spin)$/ ) {
                $cmd = @$a[2];
                $cmd =~ s/(\w+)-spin/spin$1/;
            }
            elsif ( @$a[2] = "drive" ) {
                return
"Missing arguments. Usage: remoteControl drive <speed> <degrees>"
                  if ( !defined( @$a[3] ) || !defined( @$a[4] ) );

                return "Invalid value for speed"
                  if ( @$a[3] !~ /^-?\d+/
                    || @$a[3] < -500
                    || @$a[3] > 500 );

                return "Invalid value for degree"
                  if ( @$a[4] !~ /^-?\d+/ || @$a[4] < 0 || @$a[4] > 360 );

                $cmd = "drive_only&speed=" . @$a[3] . "&degrees=" . @$a[4];
            }
            else {
                return "Unknown driving command";
            }

            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "remoteControl" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # cleaningDelay
    elsif ( lc( @$a[1] ) eq "cleaningdelay" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value: minutes"
              if ( !defined( @$a[2] ) );

            return
"Invalid value for minutes: needs to be between 30 and 240 minutes"
              if ( @$a[2] !~ /^\d+/ || @$a[2] < 30 || @$a[2] > 240 );

            $cmd = "CleanDelay&minutes=" . @$a[2];
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "cleaningDelay" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # dockAt
    elsif ( lc( @$a[1] ) eq "dockat" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value: percent"
              if ( !defined( @$a[2] ) );

            return
              "Invalid value for minutes: needs to be between 10 and 50 percent"
              if ( @$a[2] !~ /^\d+/ || @$a[2] < 10 || @$a[2] > 50 );

            $cmd = "DockAt" . @$a[2];
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "dockAt" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # stopAt
    elsif ( lc( @$a[1] ) eq "stopat" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value: percent"
              if ( !defined( @$a[2] ) );

            return
              "Invalid value for minutes: needs to be between 6 and 50 percent"
              if ( @$a[2] !~ /^\d+/ || @$a[2] < 6 || @$a[2] > 50 );

            $cmd = "StopAt" . @$a[2];
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "stopAt" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # autoUpdate
    elsif ( lc( @$a[1] ) eq "autoupdate" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value"
              if ( !defined( @$a[2] ) );

            $cmd = "UpdateOFF";
            $cmd = "UpdateON" if ( @$a[2] eq "on" );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "autoUpdate" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # songSubmit
    elsif ( lc( @$a[1] ) eq "songsubmit" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value"
              if ( !defined( @$a[2] ) );

            $cmd = @$a[2];
            $result =
              THINKINGCLEANER_SendCommand( $hash, "newsong.json", $cmd );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # songReset
    elsif ( lc( @$a[1] ) eq "songreset" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            $cmd = "resetSongCommand";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # restartAC
    elsif ( lc( @$a[1] ) eq "restartac" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value"
              if ( !defined( @$a[2] ) );

            $cmd = "MAXOFF";
            $cmd = "MAXON" if ( @$a[2] eq "on" );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "restartAC" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # alwaysMAX
    elsif ( lc( @$a[1] ) eq "alwaysmax" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value"
              if ( !defined( @$a[2] ) );

            $cmd = "MAXOFF";
            $cmd = "MAXON" if ( @$a[2] eq "on" );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "alwaysMAX" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # autoDock
    elsif ( lc( @$a[1] ) eq "autodock" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value"
              if ( !defined( @$a[2] ) );

            $cmd = "AutoDockOFF";
            $cmd = "AutoDockON" if ( @$a[2] eq "on" );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "autoDock" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # keepAwakeOnDock
    elsif ( lc( @$a[1] ) eq "keepawakeondock" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value"
              if ( !defined( @$a[2] ) );

            $cmd = "keepAwakeOnDockOFF";
            $cmd = "keepAwakeOnDockON" if ( @$a[2] eq "on" );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "keepAwakeOnDock" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # name
    elsif ( lc( @$a[1] ) eq "name" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

            return "Missing value: name"
              if ( !defined( @$a[2] ) );

            return "Wrong format for name"
              if ( @$a[2] !~ /^\w+$/ );

            $cmd = "rename_device&name=" . @$a[2];
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "name" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # reboot
    elsif ( lc( @$a[1] ) eq "reboot" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            $cmd = "crash";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd );
        }
        else {
            return "Device needs to be reachable to be rebooted.";
        }
    }

    # locate
    elsif ( lc( @$a[1] ) eq "locate" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            $cmd = "find_me";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "locate" );
        }
        else {
            return "Device needs to be reachable to be located.";
        }
    }

    # dock
    elsif ( lc( @$a[1] ) eq "dock" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            $cmd = "dock";
            $result = THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd )
              if ( $deviceStatus !~ /^(base.*|plug.*)$/ );
        }
        else {
            return "Device needs to be reachable to be docked.";
        }
    }

    # undock
    elsif ( lc( @$a[1] ) eq "undock" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            $cmd = "leavehomebase";
            $result = THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd )
              if ( $deviceStatus =~ /^(base.*)$/ );
        }
        else {
            return "Device needs to be reachable to be undocked.";
        }
    }

    # damageProtection
    elsif ( lc( @$a[1] ) eq "damageprotection" ) {
        Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

        return "No argument given, choose one of on off"
          if ( !defined( @$a[2] ) );

        if ( $state ne "absent" ) {
            $cmd = "DriveNormal";
            $cmd = "DriveAlways" if ( lc( @$a[2] eq "off" ) );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "damageProtection" );
        }
        else {
            return "Device needs to be reachable to set " . @$a[1];
        }
    }

    # vacuumDrive
    elsif ( lc( @$a[1] ) eq "vacuumdrive" ) {
        Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

        return "No argument given, choose one of on off"
          if ( !defined( @$a[2] ) );

        if ( $state ne "absent" ) {
            $cmd = "VacuumDriveON";
            $cmd = "VacuumDriveOFF" if ( lc( @$a[2] eq "off" ) );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "vacuumDrive" );
        }
        else {
            return "Device needs to be reachable to set vacuumDrive.";
        }
    }

    # power
    elsif ( lc( @$a[1] ) eq "power" ) {
        Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1] . " " . @$a[2];

        return "No argument given, choose one of on off"
          if ( !defined( @$a[2] ) );

        if ( $state ne "absent" ) {
            $cmd = "poweroff";
            $cmd = "forward" if ( lc( @$a[2] eq "on" ) );
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "power" )
              if ( ( $cmd eq "forward" && $state ne "on" && $power ne "on" )
                || $cmd eq "poweroff" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # on-delayed
    elsif ( lc( @$a[1] ) eq "on-delayed" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            $cmd = "delayedclean";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "on-delayed" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # on-spot
    elsif ( lc( @$a[1] ) eq "on-spot" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            if ( $power eq "off" ) {
                $result =
                  THINKINGCLEANER_SendCommand( $hash, "command.json",
                    "forward", "power" );
                return fhem "sleep 2;set $name " . @$a[1];
            }

            $cmd = "spot";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "on-spot" );
        }
        else {
            return "Device needs to be reachable to be controlled.";
        }
    }

    # on-max
    elsif ( lc( @$a[1] ) eq "on-max" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            if ( $power eq "off" ) {
                $result =
                  THINKINGCLEANER_SendCommand( $hash, "command.json",
                    "forward", "power" );
                return fhem "sleep 2;set $name " . @$a[1];
            }

            $cmd = "max";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                "on-max" );
        }
        else {
            return "Device needs to be reachable to be turned on.";
        }
    }

    # on
    elsif ( lc( @$a[1] ) eq "on" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];

            if ( $power eq "off" ) {
                $result =
                  THINKINGCLEANER_SendCommand( $hash, "command.json",
                    "forward", "power" );
                return fhem "sleep 2;set $name " . @$a[1];
            }

            $cmd = "clean";
            $result =
              THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd, "on" )
              if ( $state ne "on" );
        }
        else {
            return "Device needs to be reachable to be turned on.";
        }
    }

    # off
    elsif ( lc( @$a[1] ) eq "off" ) {
        if ( $state ne "absent" ) {
            Log3 $name, 3, "THINKINGCLEANER set $name " . @$a[1];
            $cmd = "clean";

            if ( $state ne "on-delayed" && $state =~ /^(dock|on.*)$/ ) {
                $result =
                  THINKINGCLEANER_SendCommand( $hash, "command.json", $cmd,
                    "off" );
            }
        }
        else {
            return "Device needs to be reachable to be set to standby mode.";
        }
    }

    # toggle
    elsif ( lc( @$a[1] ) eq "toggle" ) {
        if ( $state ne "on" ) {
            return THINKINGCLEANER_Set( $hash, $name, "on" );
        }
        else {
            return THINKINGCLEANER_Set( $hash, $name, "off" );
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return undef;
}

sub THINKINGCLEANER_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_Attr()";

    return
"Invalid value for attribute $attrName: can only by FQDN or IPv4 or IPv6 address"
      if ( $attrVal
        && $attrName eq "webhookHttpHostname"
        && $attrVal !~ /^([A-Za-z_.0-9]+\.[A-Za-z_.0-9]+)|[0-9:]+$/ );

    return
"Invalid value for attribute $attrName: needs to be different from the defined name/address of your Roomba, we need to know how Rooma can connect back to FHEM here!"
      if ( $attrVal
        && $attrName eq "webhookHttpHostname"
        && $attrVal eq $hash->{DeviceName} );

    return
"Invalid value for attribute $attrName: FHEMWEB instance $attrVal not existing"
      if (
           $attrVal
        && $attrName eq "webhookFWinstance"
        && ( !defined( $defs{$attrVal} )
            || $defs{$attrVal}{TYPE} ne "FHEMWEB" )
      );

    return
      "Invalid value for attribute $attrName: needs to be an integer value"
      if ( $attrVal && $attrName eq "webhookPort" && $attrVal !~ /^\d+$/ );

    return
"Invalid value for attribute $attrName: minimum value is 1 second, maximum 5 seconds"
      if ( $attrVal
        && $attrName eq "timeout"
        && ( $attrVal < 1 || $attrVal > 5 ) );

    return "Invalid value for attribute $attrName: minimum value is 16 seconds"
      if ( $attrVal && $attrName eq "pollInterval" && $attrVal < 16 );

    return
"Invalid value for attribute $attrName: minimum factor is 1.25, maximum is 4"
      if ( $attrVal
        && $attrName eq "pollMultiplierWebhook"
        && ( $attrVal < 1.25 || $attrVal > 4 ) );

    return
"Invalid value for attribute $attrName: minimum factor is 0.2, maximum is 30"
      if ( $attrVal
        && $attrName eq "pollMultiplierCleaning"
        && ( $attrVal < 0.2 || $attrVal > 30 ) );

    # webhook*
    if ( $attrName =~ /^webhook.*/ ) {
        my $webhookHttpHostname = (
              $attrName eq "webhookHttpHostname"
            ? $attrVal
            : AttrVal( $name, "webhookHttpHostname", "" )
        );
        my $webhookFWinstance = (
              $attrName eq "webhookFWinstance"
            ? $attrVal
            : AttrVal( $name, "webhookFWinstance", "" )
        );
        $hash->{WEBHOOK_URI} = "/"
          . AttrVal( $webhookFWinstance, "webname", "fhem" )
          . "/THINKINGCLEANER";
        $hash->{WEBHOOK_PORT} = (
              $attrName eq "webhookPort"
            ? $attrVal
            : AttrVal(
                $name, "webhookPort",
                InternalVal( $webhookFWinstance, "PORT", "" )
            )
        );

        $hash->{WEBHOOK_URL}     = "";
        $hash->{WEBHOOK_COUNTER} = "0";
        if ( $webhookHttpHostname ne "" && $hash->{WEBHOOK_PORT} ne "" ) {
            $hash->{WEBHOOK_URL} =
                "http://"
              . $webhookHttpHostname . ":"
              . $hash->{WEBHOOK_PORT}
              . $hash->{WEBHOOK_URI};

            my $cmd =
                "&h_url=$webhookHttpHostname&h_path="
              . $hash->{WEBHOOK_URI}
              . "&h_port="
              . $hash->{WEBHOOK_PORT};

            THINKINGCLEANER_SendCommand( $hash, "register_webhook.json", $cmd );
            $hash->{WEBHOOK_REGISTER} = "sent";
        }
        else {
            $hash->{WEBHOOK_REGISTER} = "incomplete_attributes";
        }

    }

    return undef;
}

# module Fn ####################################################################
sub THINKINGCLEANER_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";

    return 0
      if ( defined( $data{FWEXT}{$url} )
        && $data{FWEXT}{$url}{deviceName} ne $name );

    Log3 $name, 2,
"THINKINGCLEANER $name: Registering THINKINGCLEANER for webhook URI $url ...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;

    return 1;
}

sub THINKINGCLEANER_removeExtension($) {
    my ($link) = @_;

    my $url  = "?/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2,
"THINKINGCLEANER $name: Unregistering THINKINGCLEANER for webhook URI $url...";
    delete $data{FWEXT}{$url};
}

sub THINKINGCLEANER_CGI() {
    my ($request) = @_;

    # data received
    if ( defined( $FW_httpheader{UUID} ) ) {
        if ( defined( $modules{THINKINGCLEANER}{defptr} ) ) {
            while ( my ( $key, $value ) =
                each %{ $modules{THINKINGCLEANER}{defptr} } )
            {

                my $uuid = ReadingsVal( $key, "uuid", undef );
                next if ( !$uuid || $uuid ne $FW_httpheader{UUID} );

                $defs{$key}{WEBHOOK_COUNTER}++;
                $defs{$key}{WEBHOOK_LAST} = TimeNow();

                Log3 $key, 4,
"THINKINGCLEANER $key: Received webhook for matching UUID at device $key";

                my $delay = undef;

# we need some delay as to the Robo seems to send webhooks but it's status does
# not really reflect the change we'd expect to get here already so give 'em some
# more time to think about it...
                $delay = "2"
                  if ( defined( $defs{$key}{LAST_COMMAND} )
                    && time() - time_str2num( $defs{$key}{LAST_COMMAND} ) < 3 );

                THINKINGCLEANER_GetStatus( $defs{$key}, $delay );
                last;
            }
        }

        return ( undef, undef );
    }

    # no data received
    else {
        Log3 undef, 5, "THINKINGCLEANER: received malformed request\n$request";
    }

    return ( "text/plain; charset=utf-8", "Call failure: " . $request );
}

sub THINKINGCLEANER_GetStatus($;$) {
    my ( $hash, $delay ) = @_;
    my $name = $hash->{NAME};
    $hash->{INTERVAL_MULTIPLIER} = (
        ReadingsVal( $name, "state", "off" ) ne "off"
          && ReadingsVal( $name, "state", "absent" ) ne "absent"
          && ReadingsVal( $name, "state", "standby" ) ne "standby"
        ? AttrVal( $name, "pollMultiplierCleaning", "0.5" )
        : (
            $hash->{WEBHOOK_REGISTER} eq "success"
            ? AttrVal( $name, "pollMultiplierWebhook", "2" )
            : "1"
        )
    );

    $hash->{INTERVAL} =
      AttrVal( $name, "pollInterval", "45" ) * $hash->{INTERVAL_MULTIPLIER};
    my $interval = (
          $delay
        ? $delay
        : $hash->{INTERVAL}
    );

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_GetStatus()";

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval,
        "THINKINGCLEANER_GetStatus", $hash, 0 );

    return
      if ( $delay || AttrVal( $name, "disable", 0 ) == 1 );

    THINKINGCLEANER_SendCommand( $hash, "full_status.json" );

    return;
}

sub THINKINGCLEANER_SendCommand($$;$$) {
    my ( $hash, $service, $cmd, $type ) = @_;
    my $name            = $hash->{NAME};
    my $address         = $hash->{DeviceName};
    my $http_method     = "GET";
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $timeout;
    $cmd = ( defined($cmd) && $cmd ne "" ) ? "command=$cmd" : "";

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_SendCommand()";

    my $http_proto  = "http";
    my $http_user   = "";
    my $http_passwd = "";
    my $URL;
    my $response;
    my $return;

    $http_method = "POST"
      if ( $service eq "register_webhook.json" || $service eq "newsong.json" );

    if ( !defined($cmd) || $cmd eq "" ) {
        Log3 $name, 4, "THINKINGCLEANER $name: REQ $service";
    }
    else {
        $cmd = "?" . $cmd . "&"
          if ( $http_method eq "GET" || $http_method eq "" );
        Log3 $name, 4, "THINKINGCLEANER $name: REQ $service/" . urlDecode($cmd);
    }

    $URL = $http_proto . "://" . $address . "/" . $service;
    $URL .= $cmd if ( $http_method eq "GET" || $http_method eq "" );

    if ( AttrVal( $name, "timeout", "3" ) =~ /^\d+$/ ) {
        $timeout = AttrVal( $name, "timeout", "3" );
    }
    else {
        Log3 $name, 3,
          "THINKINGCLEANER $name: wrong format in attribute 'timeout'";
        $timeout = 3;
    }

    # send request via HTTP-GET method
    if ( $http_method eq "GET" || $http_method eq "" || $cmd eq "" ) {
        Log3 $name, 5,
            "THINKINGCLEANER $name: GET "
          . urlDecode($URL)
          . " (noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url         => $URL,
                timeout     => $timeout,
                noshutdown  => $http_noshutdown,
                data        => undef,
                hash        => $hash,
                service     => $service,
                cmd         => $cmd,
                type        => $type,
                callback    => \&THINKINGCLEANER_ReceiveCommand,
                httpversion => "1.1",
                loglevel    => AttrVal( $name, "httpLoglevel", 4 ),
                header      => {
                    Agent            => 'FHEM-THINKINGCLEANER/1.0.0',
                    'User-Agent'     => 'FHEM-THINKINGCLEANER/1.0.0',
                    Accept           => 'application/json;charset=UTF-8',
                    'Accept-Charset' => 'UTF-8',
                },
            }
        );

    }

    # send request via HTTP-POST method
    elsif ( $http_method eq "POST" ) {
        Log3 $name, 5,
            "THINKINGCLEANER $name: GET "
          . $URL
          . " (POST DATA: "
          . urlDecode($cmd)
          . ", noshutdown="
          . $http_noshutdown . ")";

        HttpUtils_NonblockingGet(
            {
                url         => $URL,
                timeout     => $timeout,
                noshutdown  => $http_noshutdown,
                data        => $cmd,
                hash        => $hash,
                service     => $service,
                cmd         => $cmd,
                type        => $type,
                callback    => \&THINKINGCLEANER_ReceiveCommand,
                httpversion => "1.1",
                loglevel    => AttrVal( $name, "httpLoglevel", 4 ),
                header      => {
                    Agent            => 'FHEM-THINKINGCLEANER/1.0.0',
                    'User-Agent'     => 'FHEM-THINKINGCLEANER/1.0.0',
                    'Content-Type'   => 'application/json',
                    Accept           => 'application/json;charset=UTF-8',
                    'Accept-Charset' => 'UTF-8',
                },
            }
        );
    }

    # other HTTP methods are not supported
    else {
        Log3 $name, 1,
            "THINKINGCLEANER $name: ERROR: HTTP method "
          . $http_method
          . " is not supported.";
    }

    if ( $service eq "command.json" ) {
        $hash->{LAST_COMMAND} = TimeNow();
        THINKINGCLEANER_GetStatus( $hash, 6 );
    }

    return;
}

sub THINKINGCLEANER_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash     = $param->{hash};
    my $name     = $hash->{NAME};
    my $service  = $param->{service};
    my $cmd      = $param->{cmd};
    my $state    = ReadingsVal( $name, "state", "off" );
    my $power    = ReadingsVal( $name, "power", "off" );
    my $presence = ReadingsVal( $name, "presence", "absent" );
    my $type     = ( $param->{type} ) ? $param->{type} : "";
    my $return;

    Log3 $name, 5,
      "THINKINGCLEANER $name: called function THINKINGCLEANER_ReceiveCommand()";

    readingsBeginUpdate($hash);

    # device not reachable
    if ($err) {

        # powerstate
        $state = "absent";
        $power = "off";

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "THINKINGCLEANER $name: RCV TIMEOUT $service";
        }
        else {
            Log3 $name, 4,
              "THINKINGCLEANER $name: RCV TIMEOUT $service/" . urlDecode($cmd);
        }

        $presence = "absent";
        readingsBulkUpdate( $hash, "presence", $presence )
          if ( ReadingsVal( $name, "presence", "" ) ne $presence );
    }

    # data received
    elsif ($data) {
        $presence = "present";
        readingsBulkUpdate( $hash, "presence", $presence )
          if ( ReadingsVal( $name, "presence", "" ) ne $presence );

        if ( !defined($cmd) || $cmd eq "" ) {
            Log3 $name, 4, "THINKINGCLEANER $name: RCV $service";
        }
        else {
            Log3 $name, 4,
              "THINKINGCLEANER $name: RCV $service/" . urlDecode($cmd);
        }

        if ( $data ne "" ) {
            if ( $data =~ /^{/ || $data =~ /^\[/ ) {
                if ( !defined($cmd) || ref($cmd) eq "HASH" || $cmd eq "" ) {
                    Log3 $name, 5,
                      "THINKINGCLEANER $name: RES $service\n" . $data;
                }
                else {
                    Log3 $name, 5,
                        "THINKINGCLEANER $name: RES $service/"
                      . urlDecode($cmd) . "\n"
                      . $data;
                }

                eval '$return = decode_json( Encode::encode_utf8($data) ); 1';
                if ($@) {

                    if ( !defined($cmd) || $cmd eq "" ) {
                        Log3 $name, 5,
"THINKINGCLEANER $name: RES ERROR $service - unable to parse malformed JSON: $@\n"
                          . $data;
                    }
                    else {
                        Log3 $name, 5,
                            "THINKINGCLEANER $name: RES ERROR $service/"
                          . urlDecode($cmd)
                          . " - unable to parse malformed JSON: $@\n"
                          . $data;

                    }

                    return undef;
                }

            }

            else {
                if ( !defined($cmd) || $cmd eq "" ) {
                    Log3 $name, 5,
"THINKINGCLEANER $name: RES ERROR $service - not in JSON format\n"
                      . $data;
                }
                else {
                    Log3 $name, 5,
                        "THINKINGCLEANER $name: RES ERROR $service/"
                      . urlDecode($cmd)
                      . " - not in JSON format\n"
                      . $data;
                }

                return undef;
            }
        }

        $return = Encode::encode_utf8($data)
          if ( $return && ref($return) ne "HASH" );

        #######################
        # process return data
        #

        # full_status
        if ( $service eq "full_status.json" ) {
            if ( defined($return)
                && ref($return) eq "HASH" )
            {
                $state = "off";

                if ( $return->{result} ne "success" ) {
                    $state = "error";
                }
                else {
                    foreach my $r ( keys %{$return} ) {
                        next if ( ref( $return->{$r} ) ne "HASH" );

                        my $rPrefix = $r;
                        $rPrefix = ""        if ( $r eq "firmware" );
                        $rPrefix = "battery" if ( $r eq "power_status" );
                        $rPrefix = ""        if ( $r eq "tc_status" );
                        $rPrefix = "button"  if ( $r eq "buttons" );
                        $rPrefix = "sensor"  if ( $r eq "sensors" );

                        foreach my $r2 ( keys %{ $return->{$r} } ) {
                            next unless ( $r2 && $r2 ne "" );

                            # INTERNALS or dynamic values
                            if ( $r2 eq "cleaning" ) {

                               # let state be on if cleaning is clearly going on
                                $state = "on"
                                  if ( $return->{$r}{$r2} eq "1"
                                    && $state !~ /dock|on-.*/ );
                                next;
                            }
                            elsif ( $r2 eq "modelnr" ) {
                                $hash->{modelid} =
                                  "Roomba_" . $return->{$r}{$r2} . "_Series";
                                $attr{$name}{model} =
                                  "Roomba_" . $return->{$r}{$r2} . "_Series";
                                next;
                            }
                            elsif ( $r2 eq "time_h_m" ) {
                                $hash->{SYSTEMTIME} = $return->{$r}{$r2};
                                next;
                            }
                            elsif ( lc($r2) eq "selected_timezone" ) {
                                $hash->{TIMEZONE} = $return->{$r}{$r2};
                                next;
                            }
                            elsif ( $r2 eq "boot_version" ) {
                                $hash->{SWVERSION_BOOTLOADER} =
                                  $return->{$r}{$r2};
                                next;
                            }
                            elsif ( $r2 eq "cleaning_distance_miles" ) {
                                next;
                            }
                            elsif ( $r2 eq "wifi_version" ) {
                                $hash->{SWVERSION_WIFI} =
                                  $return->{$r}{$r2};
                                next;
                            }
                            elsif ( $r2 eq "version" ) {
                                $hash->{SWVERSION} = $return->{$r}{$r2};
                                next;
                            }
                            elsif ( $r2 eq "schedule_serial_number" ) {
                                my $serial = (
                                      $hash->{SCHEDULE_SERIAL}
                                    ? $hash->{SCHEDULE_SERIAL}
                                    : "0"
                                );
                                $hash->{SCHEDULE_SERIAL} =
                                  $return->{$r}{$r2};
                                THINKINGCLEANER_SendCommand( $hash,
                                    "schedule.json" )
                                  if ( $serial ne $return->{$r}{$r2} );
                                next;
                            }

                            # READINGS
                            my $v = $return->{$r}{$r2};
                            my $readingName;

                            if ( $r2 eq "cleaner_state" ) {
                                $readingName = "deviceStatus";
                                $v =~ s/^st_//;

                                # change state based on cleaner_state
                                if ( $v =~ /^clean_(.*)$/ ) {
                                    $state = "on-$1";
                                }
                                elsif ($state ne "on"
                                    && $v eq "delayed" )
                                {
                                    $state = "on-delayed";
                                }
                                elsif ($state ne "on"
                                    && $v =~
                                    /^(off|clean|stopped|cleanstop|wait)$/ )
                                {
                                    $state = "standby";
                                }
                                elsif (
                                    $v =~ /^dock|locate$/
                                    || (   $state ne "on"
                                        && $v !~ /^(base.*|plug.*)$/ )
                                  )
                                {
                                    $state = $v;
                                }

                                my $cvals;
                                $cvals->{cleaningDistance} =
                                  ReadingsVal( $name, "cleaningDistance", "0" );
                                $cvals->{cleaningDistanceLast} =
                                  ReadingsVal( $name, "cleaningDistanceLast",
                                    "0" );
                                $cvals->{cleaningDistanceStart} = ReadingsVal(
                                    $name,
                                    "cleaningDistanceStart",
                                    $return->{"tc_status"}{"cleaning_distance"}
                                );
                                $cvals->{cleaningDistanceTotal} =
                                  $return->{"tc_status"}{"cleaning_distance"};

                                # left at base station / begin stats
                                if ( $v !~ /^(base.*|plug.*)$/
                                    && ReadingsVal( $name, $readingName, "" )
                                    =~ /^(base.*|plug.*)$/ )
                                {
                                    $cvals->{cleaningDistanceStart} =
                                      $cvals->{cleaningDistanceTotal};
                                }

                                # arrived at base station / end stats
                                elsif ( $v =~ /^(base.*|plug.*)$/
                                    && ReadingsVal( $name, $readingName, "" )
                                    !~ /^(base.*|plug.*)$/ )
                                {
                                    if ( $cvals->{cleaningDistanceStart} > 0 ) {
                                        $cvals->{cleaningDistanceLast} =
                                          $cvals->{cleaningDistanceTotal} -
                                          $cvals->{cleaningDistanceStart};

                                        $cvals->{cleaningDistanceStart} =
                                          $cvals->{cleaningDistanceTotal};
                                    }

                                    $cvals->{cleaningDistance} = "0";
                                }

                                while ( my ( $key, $value ) = each %{$cvals} ) {
                                    readingsBulkUpdate( $hash, $key, $value )
                                      if ( ReadingsVal( $name, $key, "" ) ne
                                        $value );
                                }
                            }
                            elsif ($r2 eq "cleaning_time"
                                && $v eq "0"
                                && ReadingsVal( $name, "cleaningTime", "0" ) ne
                                "0" )
                            {
                                readingsBulkUpdate( $hash, "cleaningTimeLast",
                                    ReadingsVal( $name, "cleaningTime", "0" ) );
                            }
                            elsif ($r2 eq "auto_update"
                                || $r2 eq "vacuum_drive"
                                || $r2 eq "restart_AC"
                                || $r2 eq "always_MAX"
                                || $r2 eq "auto_dock"
                                || $r2 eq "keepAwakeOnDock"
                                || $r2 eq "webview_advanced" )
                            {
                                $readingName = $r2;
                                $v           = "off";
                                $v = "on" if ( $return->{$r}{$r2} eq "1" );
                            }
                            elsif ( $r2 eq "bin_status" ) {
                                $readingName = $r2;
                                $v           = "ok";
                                $v = "full" if ( $return->{$r}{$r2} eq "1" );
                            }
                            elsif ( $r2 eq "tc-roomba-conn" ) {
                                $readingName = "roombaConnection";
                                $power       = "off";
                                $power       = "on"
                                  if ( $v ne "0" );
                            }
                            elsif ( $r2 eq "clean_delay" ) {
                                $readingName = "cleaningDelay";
                            }
                            elsif ( $r2 eq "DHCP" ) {
                                $readingName = "networkDHCP";
                            }
                            elsif ( $r2 eq "cleaning_distance" ) {
                                $readingName = "cleaningDistanceTotal";

                                my $cleaningDistance =
                                  $v -
                                  ReadingsVal( $name, "cleaningDistanceStart",
                                    "0" );

                                readingsBulkUpdate( $hash, "cleaningDistance",
                                    $cleaningDistance )
                                  if (
                                    ReadingsVal(
                                        $name, "cleaningDistance", ""
                                    ) ne $cleaningDistance
                                  );
                            }
                            elsif ( $r2 eq "battery_charge" ) {
                                $readingName = "batteryLevel";
                            }
                            elsif ( $rPrefix ne "" && $r2 !~ /^battery/ ) {
                                $readingName = $rPrefix . ucfirst($r2);
                            }
                            else {
                                $readingName = $r2;
                            }

                            if ($readingName && $readingName ne "") {
                                $readingName =~ s/_(state|button|current)$//;
                                $readingName =~ s/[-_](\w)/\U$1/g;

                                readingsBulkUpdateIfChanged( $hash,
                                    $readingName, $v );
                            }
                            else {
                                Log3 $name, 4,
                                  "THINKINGCLEANER $name: "
                                  . "ERROR: variable readingName is not initialized - r=$r r2=$r2 v=$v".Dumper($return);
                            }
                        }
                    }
                }
            }
            elsif ( $state ne "undefined" ) {
                Log3 $name, 2,
                  "THINKINGCLEANER $name: ERROR: Undefined state of device";

                $state = "undefined";
            }
        }

        # command
        elsif ( $service eq "command.json" ) {
            if ( $return->{result} eq "success" ) {

                # power
                if ( $type eq "power" ) {

                    # off
                    if ( $cmd =~ /=poweroff&/ ) {
                        $state = "standby"
                          if ( ReadingsVal( $name, "deviceState", "" ) !~
                            /^(dock.*|plug.*)$/ );
                        $power = "off";

                        readingsBulkUpdate( $hash, "deviceStatus", "off" )
                          if (
                            ReadingsVal( $name, "deviceStatus", "" ) ne "off" );

                        readingsBulkUpdate( $hash, "roombaConnection", "0" )
                          if (
                            ReadingsVal( $name, "roombaConnection", "" ) ne
                            "0" );
                    }

                    # on
                    else {
                        $power = "on";
                        $state = "standby";

                        readingsBulkUpdate( $hash, "deviceStatus", "wait" )
                          if ( ReadingsVal( $name, "deviceStatus", "" ) ne
                            "wait" );
                    }

                    THINKINGCLEANER_GetStatus( $hash, 6 );
                }

                # off
                elsif ( $type eq "off" ) {
                    $state = "standby";

                    readingsBulkUpdate( $hash, "deviceStatus", "clean" )
                      if (
                        ReadingsVal( $name, "deviceStatus", "" ) ne "clean" );

                    THINKINGCLEANER_GetStatus( $hash, 10 );
                }

                # on
                elsif ( $type eq "on" ) {
                    $power = "on";
                    $state = "on";

                    readingsBulkUpdate( $hash, "deviceStatus", "clean" )
                      if (
                        ReadingsVal( $name, "deviceStatus", "" ) ne "clean" );

                    THINKINGCLEANER_GetStatus( $hash, 6 );
                }

                # on-spot
                elsif ( $type eq "on-spot" ) {
                    $power = "on";
                    $state = "on-spot";

                    readingsBulkUpdate( $hash, "deviceStatus", "clean_spot" )
                      if ( ReadingsVal( $name, "deviceStatus", "" ) ne
                        "clean_spot" );

                    THINKINGCLEANER_GetStatus( $hash, 6 );
                }

                # on-max
                elsif ( $type eq "on-max" ) {
                    $power = "on";
                    $state = "on-max";

                    readingsBulkUpdate( $hash, "deviceStatus", "clean_max" )
                      if ( ReadingsVal( $name, "deviceStatus", "" ) ne
                        "clean_max" );

                    THINKINGCLEANER_GetStatus( $hash, 6 );
                }

                # dock
                elsif ( $type eq "dock" ) {
                    $power = "on";
                    $state = "dock";

                    readingsBulkUpdate( $hash, "deviceStatus", "dock" )
                      if ( ReadingsVal( $name, "deviceStatus", "" ) ne "dock" );

                    THINKINGCLEANER_GetStatus( $hash, 6 );
                }

                # remoteControl
                elsif ( $type eq "remoteControl" ) {
                    $power = "on";
                    $state = "remote";

                    readingsBulkUpdate( $hash, "deviceStatus", "remote" )
                      if (
                        ReadingsVal( $name, "deviceStatus", "" ) ne "remote" );
                }

                # vacuumDrive
                elsif ( $type eq "vacuumDrive" ) {
                    my $v = "off";
                    $v = "on" if ( $cmd =~ /=VacuumDriveON&/ );

                    readingsBulkUpdate( $hash, "vacuumDrive", $v )
                      if ( ReadingsVal( $name, "vacuumDrive", "" ) ne $v );
                }

                # cleaningDelay
                elsif ( $type eq "cleaningDelay" ) {
                    my $v = $cmd;
                    $v =~ s/.*minutes=(\d+).*/$1/;

                    readingsBulkUpdate( $hash, "cleaningDelay", $v )
                      if ( ReadingsVal( $name, "cleaningDelay", "" ) ne $v );
                }

                # locate
                elsif ( $type eq "locate" ) {
                    $power = "on";
                    $state = "locate";

                    readingsBulkUpdate( $hash, "deviceStatus", "locate" )
                      if (
                        ReadingsVal( $name, "deviceStatus", "" ) ne "locate" );

                    THINKINGCLEANER_GetStatus( $hash, 10 );
                }

            }
        }

        # schedule
        elsif ( $service eq "schedule.json" ) {
            if ( $return->{result} eq "success" ) {
                $hash->{SCHEDULE_SERIAL} = $return->{serial_number};

                foreach my $r ( keys %{$return} ) {
                    next if ( ref( $return->{$r} ) ne "HASH" );

                    foreach my $wday ( keys %{ $return->{$r} } ) {
                        my $wdayStnd = $wday + 1;
                        $wdayStnd = "0" if ( $wdayStnd > 6 );
                        my $readingName = "schedule$wdayStnd";
                        my $v           = "";

                        foreach my $ti ( @{ $return->{$r}{$wday} } ) {
                            my $command;
                            $command = "clean"
                              if ( $ti->{command} eq "0" );
                            $command = "max"
                              if ( $ti->{command} eq "1" );
                            $command = "doch"
                              if ( $ti->{command} eq "2" );
                            $command = "stop"
                              if ( $ti->{command} eq "3" );

                            $v .= "," if ( $v ne "" );
                            $v .=
                                $ti->{index} . "_"
                              . THINKINGCLEANER_sec2time( $ti->{time} )
                              . "_"
                              . $command;
                        }

                        readingsBulkUpdate( $hash, $readingName, $v )
                          if ( ReadingsVal( $name, $readingName, "-" ) ne $v );
                    }
                }
            }
        }

        # add_schedule, change_schedule, remove_schedule
        elsif ( $service =~ /^(add|change|remove)_schedule.json$/ ) {
            if ( $return->{result} eq "success" ) {
                $hash->{SCHEDULE_SERIAL}++;
                THINKINGCLEANER_SendCommand( $hash, "schedule.json" );
            }
        }

        # register_webhook
        elsif ( $service eq "register_webhook.json" ) {
            $hash->{WEBHOOK_REGISTER} = $return->{result};
        }

        else {
            Log3 $name, 2,
              "THINKINGCLEANER $name: ERROR: Response could not be interpreted";
        }
    }

    # Set reading for power
    #
    readingsBulkUpdate( $hash, "power", $power )
      if ( ReadingsVal( $name, "power", "" ) ne $power );

    # Set reading for state
    #
    readingsBulkUpdate( $hash, "state", $state )
      if ( ReadingsVal( $name, "state", "" ) ne $state );

    readingsEndUpdate( $hash, 1 );

    undef $return;
    return;
}

sub THINKINGCLEANER_time2sec($) {
    my ($timeString) = @_;
    my @time = split /:/, $timeString;

    return $time[0] * 3600 + $time[1] * 60;
}

sub THINKINGCLEANER_sec2time($) {
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

1;

=pod
=item device
=item summary control for Roomba cleaning robots using ThinkingCleaner add-on
=item summary_DE Steuerung von Roomba Staubsauger Robotern mit ThinkingCleaner add-on
=begin html

<a name="THINKINGCLEANER" id="THINKINGCLEANER"></a>
<h3>THINKINGCLEANER</h3>
<ul>
  This module provides support for <a href="http://www.thinkingcleaner.com/">ThinkingCleaner</a> hardware add-on module for Roomba cleaning robots.
  <br><br>
  <a name="THINKINGCLEANERdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; THINKINGCLEANER &lt;IP-ADRESS or HOSTNAME&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Robby THINKINGCLEANER 192.168.0.35</code><br>
    </ul>
    <br>
  </ul>
  <br><br>
  <a name="THINKINGCLEANERset"></a>
  <b>Set</b>
  <ul>
    <li>cleaningDelay - sets cleaning delay in minutes when using on-delayed cleaning</li>
    <li>damageProtection - turns damage protection on or off while sending remotrControl commands (on/off)</li>
    <li>dock - Send Roomba back to it's docking station</li>
    <li>locate - Play sound to help finding Roomba</li>
    <li>off - Stop/pause cleaning</li>
    <li>on - Start cleaning</li>
    <li>on-delayed - Delayed start for cleaning according to cleaningDelay</li>
    <li>on-max - Start cleaning with max setting</li>
    <li>on-spot - Start spot cleaning</li>
    <li>power - Turn Roomba on or off (on/off)</li>
    <li>remoteControl - Send remote control commands</li>
    <li>scheduleAdd - Add new cleaning schedule</li>
    <li>scheduleDel - Delete existing cleaning schedule</li>
    <li>scheduleMod - Modify existing cleaning schedule</li>
    <li>statusRequest - Update device readings</li>
    <li>toggle - Toogle between on and off</li>
    <li>undock - Let Roomba leave it's docking station</li>
    <li>vacuumDrive - Enable or disable vaccuming during remoteControl commands (on/off)</li>
  </ul>
  <br><br>
  <a name="THINKINGCLEANERattr"></a>
  <b>Attributes</b>
  <ul>
    <li>pollInterval - Set regular polling interval in minutes (defaults to 45s)</li>
    <li>pollMultiplierCleaning - Change interval multiplier used during cleaning (defaults to 0.5)</li>
    <li>pollMultiplierWebhook - Change interval multiplier used during standby and webhook being enabled (defaults to 2)</li>
    <li>webhookFWinstance - Set FHEMWEB instance for incoming webhook events used by Roomba (mandatory for webhook)</li>
    <li>webhookHttpHostname - Set HTTP Hostname or IP address for incoming webhook events used by Roomba (mandatory for webhook)</li>
    <li>webhookPort - Use different port instead of what defined FHEMWEB instance uses (optional)</li>
  </ul>
  <br><br>
</ul>

=end html

=begin html_DE

<a name="THINKINGCLEANER" id="THINKINGCLEANER"></a>
<h3>THINKINGCLEANER</h3>
<ul>
  Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
</ul>
<ul>
  <a href='http://fhem.de/commandref.html#THINKINGCLEANER'>THINKINGCLEANER</a>
</ul>

=end html_DE

=cut

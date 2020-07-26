###############################################################################
#
# Developed with Kate
#
#  (c) 2017-2020 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  Special thanks goes to:
#       -  Charlie71: add special patch
#       -  Holger S: patch to support Mijia LYWSD03MMC devices
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

#$cmd = "qx(gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F";
#$cmd = "qx(gatttool -i $hci -b $mac --char-read -a 0x35";   # Sensor Daten
#$cmd = "qx(gatttool -i $hci -b $mac --char-read -a 0x38";   # Firmware und Batterie
#  e8 00 00 58 0f 00 00 34 f1 02 02 3c 00 fb 34 9b

package FHEM::XiaomiBTLESens;

my $missingModul = q{};

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

use GPUtils qw(GP_Import GP_Export);

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
};

if ($@) {
    $@ = undef;

    # try to use JSON wrapper
    #   for chance of better performance
    eval {

        # JSON preference order
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

        require JSON;
        import JSON qw( decode_json encode_json );
        1;
    };

    if ($@) {
        $@ = undef;

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        };

        if ($@) {
            $@ = undef;

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            };

            if ($@) {
                $@ = undef;

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                };

                if ($@) {
                    $@ = undef;

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                }
            }
        }
    }
}

eval "use Blocking;1" or $missingModul .= "Blocking ";

#use Data::Dumper;          only for Debugging

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          CommandAttr
          AttrVal
          ReadingsVal
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          DoTrigger
          BlockingKill
          BlockingCall
          FmtDateTime
          readingFnAttributes
          makeDeviceName)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      stateRequestTimer
      )
);

my %XiaomiModels = (
    flowerSens => {
        'rdata'       => '0x35',
        'wdata'       => '0x33',
        'wdataValue'  => 'A01F',
        'wdatalisten' => 0,
        'battery'     => '0x38',
        'firmware'    => '0x38'
    },
    thermoHygroSens => {
        'wdata'       => '0x10',
        'wdataValue'  => '0100',
        'wdatalisten' => 1,
        'battery'     => '0x18',
        'firmware'    => '0x24',
        'devicename'  => '0x3'
    },
    clearGrassSens => {
        'rdata'       => '0x1e',
        'wdata'       => '0x10',
        'wdataValue'  => '0100',
        'wdatalisten' => 2,
        'battery'     => '0x3b',
        'firmware'    => '0x2a',
        'devicename'  => '0x3'
    },
    mijiaLYWSD03MMC => {
        'wdata'       => '0x38',
        'wdataValue'  => '0100',
        'wdatalisten' => 3,
        'battery'     => '0x1b',
        'firmware'    => '0x12',
        'devicename'  => '0x3'
    },
);

my %CallBatteryAge = (
    '8h'  => 28800,
    '16h' => 57600,
    '24h' => 86400,
    '32h' => 115200,
    '40h' => 144000,
    '48h' => 172800
);

sub Initialize {
    my $hash = shift;

    $hash->{SetFn}    = \&Set;
    $hash->{GetFn}    = \&Get;
    $hash->{DefFn}    = \&Define;
    $hash->{NotifyFn} = \&Notify;
    $hash->{UndefFn}  = \&Undef;
    $hash->{AttrFn}   = \&Attr;
    $hash->{AttrList} =
        'interval '
      . 'disable:1 '
      . 'disabledForIntervals '
      . 'hciDevice:hci0,hci1,hci2 '
      . 'batteryFirmwareAge:8h,16h,24h,32h,40h,48h '
      . 'minFertility '
      . 'maxFertility '
      . 'minTemp '
      . 'maxTemp '
      . 'minMoisture '
      . 'maxMoisture '
      . 'minLux '
      . 'maxLux '
      . 'sshHost '
      . 'psCommand '
      . 'model:flowerSens,thermoHygroSens,clearGrassSens,mijiaLYWSD03MMC '
      . 'blockingCallLoglevel:2,3,4,5 '
      . $readingFnAttributes;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define {
    my $hash    = shift;
    my $arg_ref = shift;

    return $@ if ( !FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'too few parameters: define <name> XiaomiBTLESens <BTMAC>'
      if ( scalar( @{$arg_ref} ) != 3 );
    return
"Cannot define XiaomiBTLESens device. Perl modul ${missingModul}is missing."
      if ($missingModul);

    my $name = $arg_ref->[0];
    my $mac  = $arg_ref->[2];

    $hash->{BTMAC}                       = $mac;
    $hash->{VERSION}                     = version->parse($VERSION)->normal;
    $hash->{INTERVAL}                    = 300;
    $hash->{helper}{CallSensDataCounter} = 0;
    $hash->{helper}{CallBattery}         = 0;
    $hash->{NOTIFYDEV}                   = 'global,' . $name;
    $hash->{loglevel}                    = 4;

    readingsSingleUpdate( $hash, 'state', 'initialized', 0 );
    CommandAttr( undef, $name . ' room XiaomiBTLESens' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    Log3( $name, 3,
        "XiaomiBTLESens ($name) - defined with BTMAC $hash->{BTMAC}" );

    $modules{XiaomiBTLESens}{defptr}{ $hash->{BTMAC} } = $hash;

    return;
}

sub Undef {
    my $hash = shift;
    my $arg  = shift;

    my $mac  = $hash->{BTMAC};
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{RUNNING_PID} )
      if ( defined( $hash->{helper}{RUNNING_PID} ) );

    delete( $modules{XiaomiBTLESens}{defptr}{$mac} );
    Log3( $name, 3, "Sub XiaomiBTLESens_Undef ($name) - delete device $name" );

    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' && $attrVal == 1 ) {
            RemoveInternalTimer($hash);

            readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            Log3( $name, 3, "XiaomiBTLESens ($name) - disabled" );
        }

        elsif ( $cmd eq 'del' ) {
            Log3( $name, 3, "XiaomiBTLESens ($name) - enabled" );
        }
    }

    elsif ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            return
'check disabledForIntervals Syntax HH:MM-HH:MM or HH:MM-HH:MM HH:MM-HH:MM ...'
              if ( $attrVal !~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3( $name, 3, "XiaomiBTLESens ($name) - disabledForIntervals" );
            stateRequest($hash);
        }

        elsif ( $cmd eq 'del' ) {
            Log3( $name, 3, "XiaomiBTLESens ($name) - enabled" );
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
        }
    }

    elsif ( $attrName eq 'interval' ) {
        RemoveInternalTimer($hash);

        if ( $cmd eq 'set' ) {
            if ( $attrVal < 120 ) {
                Log3( $name, 3,
"XiaomiBTLESens ($name) - interval too small, please use something >= 120 (sec), default is 300 (sec)"
                );
                return
'interval too small, please use something >= 120 (sec), default is 300 (sec)';
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3( $name, 3,
                    "XiaomiBTLESens ($name) - set interval to $attrVal" );
            }
        }

        elsif ( $cmd eq 'del' ) {
            $hash->{INTERVAL} = 300;
            Log3( $name, 3,
                "XiaomiBTLESens ($name) - set interval to default" );
        }
    }

    elsif ( $attrName eq 'blockingCallLoglevel' ) {
        if ( $cmd eq 'set' ) {
            $hash->{loglevel} = $attrVal;
            Log3( $name, 3,
                "XiaomiBTLESens ($name) - set blockingCallLoglevel to $attrVal"
            );
        }

        elsif ( $cmd eq 'del' ) {
            $hash->{loglevel} = 4;
            Log3( $name, 3,
                "XiaomiBTLESens ($name) - set blockingCallLoglevel to default"
            );
        }
    }

    return;
}

sub Notify {
    my $hash = shift;
    my $dev  = shift;

    my $name = $hash->{NAME};
    return stateRequestTimer($hash) if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    stateRequestTimer($hash)
      if (
        (
            (
                (
                    grep /^DEFINED.$name$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.disable$/,
                    @{$events}
                    or grep /^ATTR.$name.disable.0$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.interval$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.model$/,
                    @{$events}
                    or grep /^ATTR.$name.model.+/,
                    @{$events}
                    or grep /^ATTR.$name.interval.[0-9]+/,
                    @{$events}
                )
                && $devname eq 'global'
            )
            or grep /^resetBatteryTimestamp$/,
            @{$events}
        )
        && $init_done
        || (
            (
                grep /^INITIALIZED$/,
                @{$events}
                or grep /^REREADCFG$/,
                @{$events}
                or grep /^MODIFIED.$name$/,
                @{$events}
            )
            && $devname eq 'global'
        )
      );

    CreateParamGatttool( $hash, 'read',
        $XiaomiModels{ AttrVal( $name, 'model', '' ) }{devicename} )
      if (
        (
               AttrVal( $name, 'model', 'thermoHygroSens' ) eq 'thermoHygroSens'
            || AttrVal( $name, 'model', 'mijiaLYWSD03MMC' ) eq 'mijiaLYWSD03MMC'
        )
        && $devname eq $name
        && grep /^$name.firmware.+/,
        @{$events}
      );

    return;
}

sub stateRequest {
    my $hash = shift;

    my $name = $hash->{NAME};
    my %readings;

    if ( AttrVal( $name, 'model', 'none' ) eq 'none' ) {
        readingsSingleUpdate( $hash, 'state', 'set attribute model first', 1 );

    }
    elsif ( !IsDisabled($name) ) {
        if ( ReadingsVal( $name, 'firmware', 'none' ) ne 'none' ) {

            return CreateParamGatttool( $hash, 'read',
                $XiaomiModels{ AttrVal( $name, 'model', '' ) }{battery} )
              if (
                CallBattery_IsUpdateTimeAgeToOld(
                    $hash,
                    $CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge',
                            '24h' ) }
                )
              );

            if ( $hash->{helper}{CallSensDataCounter} < 1
                && AttrVal( $name, 'model', '' ) ne 'clearGrassSens' )
            {
                CreateParamGatttool(
                    $hash,
                    'write',
                    $XiaomiModels{ AttrVal( $name, 'model', '' ) }{wdata},
                    $XiaomiModels{ AttrVal( $name, 'model', '' ) }{wdataValue}
                );
                $hash->{helper}{CallSensDataCounter} =
                  $hash->{helper}{CallSensDataCounter} + 1;

            }
            elsif ( $hash->{helper}{CallSensDataCounter} < 1
                && AttrVal( $name, 'model', '' ) eq 'clearGrassSens' )
            {
                CreateParamGatttool( $hash, 'read',
                    $XiaomiModels{ AttrVal( $name, 'model', '' ) }{rdata},
                );
                $hash->{helper}{CallSensDataCounter} =
                  $hash->{helper}{CallSensDataCounter} + 1;
            }
            else {
                $readings{'lastGattError'} = 'charWrite faild';
                WriteReadings( $hash, \%readings );
                $hash->{helper}{CallSensDataCounter} = 0;
                return;
            }
        }
        else {

            CreateParamGatttool( $hash, 'read',
                $XiaomiModels{ AttrVal( $name, 'model', '' ) }{firmware} );
        }

    }
    else {
        readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
    }

    return;
}

sub stateRequestTimer {
    my $hash = shift;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    stateRequest($hash);

    InternalTimer( gettimeofday() + $hash->{INTERVAL} + int( rand(300) ),
        'XiaomiBTLESens_stateRequestTimer', $hash );

    Log3( $name, 4,
        "XiaomiBTLESens ($name) - stateRequestTimer: Call Request Timer" );

    return;
}

sub Set($$@) {
    my $hash    = shift;
    my $arg_ref = shift;
    my $name    = shift @$arg_ref;
    my $cmd     = shift @$arg_ref
      // return qq{"set $name" needs at least one argument};

    my $mod;
    my $handle;
    my $value = 'write';

    if ( $cmd eq 'devicename' ) {
        return 'usage: devicename <name>' if ( scalar( @{$arg_ref} ) < 1 );

        $mod    = 'write';
        $handle = $XiaomiModels{ AttrVal( $name, 'model', '' ) }{devicename};
        $value  = CreateDevicenameHEX( makeDeviceName( $arg_ref->[0] ) );

    }
    elsif ( $cmd eq 'resetBatteryTimestamp' ) {
        return 'usage: resetBatteryTimestamp' if ( scalar( @{$arg_ref} ) != 0 );

        $hash->{helper}{updateTimeCallBattery} = 0;
        return;

    }
    else {
        my $list = q{};
        $list .= 'resetBatteryTimestamp:noArg'
          if ( AttrVal( $name, 'model', 'none' ) ne 'none' );
        $list .= ' devicename'
          if (
            (
                AttrVal( $name, 'model', 'thermoHygroSens' ) eq
                'thermoHygroSens'
                || AttrVal( $name, 'model', 'mijiaLYWSD03MMC' ) eq
                'mijiaLYWSD03MMC'
            )
            && AttrVal( $name, 'model', 'none' ) ne 'none'
          );

        return "Unknown argument $cmd, choose one of $list";
    }

    CreateParamGatttool( $hash, $mod, $handle, $value );

    return;
}

sub Get {
    my $hash    = shift;
    my $arg_ref = shift;
    my $name    = shift @$arg_ref;
    my $cmd     = shift @$arg_ref
      // return qq{"set $name" needs at least one argument};

    my $mod = 'read';
    my $handle;

    if ( $cmd eq 'sensorData' ) {
        return 'usage: sensorData' if ( scalar( @{$arg_ref} ) != 0 );

        stateRequest($hash);

    }
    elsif ( $cmd eq 'firmware' ) {
        return 'usage: firmware' if ( scalar( @{$arg_ref} ) != 0 );

        $mod = 'read';
        $handle = $XiaomiModels{ AttrVal( $name, 'model', '' ) }{firmware};

    }
    elsif ( $cmd eq 'devicename' ) {
        return "usage: devicename" if ( scalar( @{$arg_ref} ) != 0 );

        $mod = 'read';
        $handle = $XiaomiModels{ AttrVal( $name, 'model', '' ) }{devicename};

    }
    else {
        my $list = q{};
        $list .= 'sensorData:noArg firmware:noArg'
          if ( AttrVal( $name, 'model', 'none' ) ne 'none' );
        $list .= ' devicename:noArg'
          if (
            (
                AttrVal( $name, 'model', 'thermoHygroSens' ) eq
                'thermoHygroSens'
                || AttrVal( $name, 'model', 'mijiaLYWSD03MMC' ) eq
                'mijiaLYWSD03MMC'
            )
            && AttrVal( $name, 'model', 'none' ) ne 'none'
          );
        return "Unknown argument $cmd, choose one of $list";
    }

    CreateParamGatttool( $hash, $mod, $handle ) if ( $cmd ne 'sensorData' );

    return;
}

sub CreateParamGatttool {
    my ( $hash, $mod, $handle, $value ) = @_;

    my $name = $hash->{NAME};
    my $mac  = $hash->{BTMAC};

    Log3( $name, 4,
        "XiaomiBTLESens ($name) - Run CreateParamGatttool with mod: $mod" );

    if ( $mod eq 'read' ) {
        $hash->{helper}{RUNNING_PID} = BlockingCall(
            'FHEM::XiaomiBTLESens::ExecGatttool_Run',
            $name . '|' . $mac . '|' . $mod . '|' . $handle,
            'FHEM::XiaomiBTLESens::ExecGatttool_Done',
            90,
            'FHEM::XiaomiBTLESens::ExecGatttool_Aborted',
            $hash
        ) if ( !exists( $hash->{helper}{RUNNING_PID} ) );

        readingsSingleUpdate( $hash, 'state', 'read sensor data', 1 );

        Log3( $name, 5,
"XiaomiBTLESens ($name) - Read XiaomiBTLESens_ExecGatttool_Run $name|$mac|$mod|$handle"
        );

    }
    elsif ( $mod eq 'write' ) {
        $hash->{helper}{RUNNING_PID} = BlockingCall(
            'FHEM::XiaomiBTLESens::ExecGatttool_Run',
            $name . '|'
              . $mac . '|'
              . $mod . '|'
              . $handle . '|'
              . $value . '|'
              . $XiaomiModels{ AttrVal( $name, 'model', '' ) }{wdatalisten},
            'FHEM::XiaomiBTLESens::ExecGatttool_Done',
            90,
            'FHEM::XiaomiBTLESens::ExecGatttool_Aborted',
            $hash
        ) if ( !exists( $hash->{helper}{RUNNING_PID} ) );

        readingsSingleUpdate( $hash, 'state', 'write sensor data', 1 );

        Log3( $name, 5,
"XiaomiBTLESens ($name) - Write XiaomiBTLESens_ExecGatttool_Run $name|$mac|$mod|$handle|$value"
        );
    }

    return;
}

sub Gatttool_executeCommand {
    my $command = join q{ }, @_;
    return ( $_ = qx{$command 2>&1}, $? >> 8 );
}

sub ExecGatttool_Run {
    my $string = shift;

    my ( $name, $mac, $gattCmd, $handle, $value, $listen ) =
      split '\|', $string;
    my $sshHost = AttrVal( $name, 'sshHost', 'none' );
    my $gatttool;
    my $json_notification;

    $gatttool = qx(which gatttool) if ( $sshHost eq 'none' );
    $gatttool = qx(ssh $sshHost 'which gatttool') if ( $sshHost ne 'none' );
    chomp $gatttool;

    if ( defined($gatttool) && ($gatttool) ) {

        my $cmd;
        my $loop;
        my @gtResult;
        my $wait    = 1;
        my $sshHost = AttrVal( $name, 'sshHost', 'none' );
        my $hci     = AttrVal( $name, 'hciDevice', 'hci0' );

        $cmd .= "ssh $sshHost '"         if ( $sshHost ne 'none' );
        $cmd .= "timeout 10 "            if ($listen);
        $cmd .= "gatttool -i $hci -b $mac ";
        $cmd .= "--char-read -a $handle" if ( $gattCmd eq 'read' );
        $cmd .= "--char-write-req -a $handle -n $value"
          if ( $gattCmd eq 'write' );
        $cmd .= " --listen" if ($listen);

        #        $cmd .= " 2>&1 /dev/null";
        $cmd .= " 2>&1";
        $cmd .= "'" if ( $sshHost ne 'none' );

        $cmd =
"ssh $sshHost 'gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F && gatttool -i $hci -b $mac --char-read -a 0x35 2>&1 '"
          if ( $sshHost ne 'none'
            && $gattCmd eq 'write'
            && AttrVal( $name, 'model', 'none' ) eq 'flowerSens' );

        while ($wait) {

            my $grepGatttool;
            my $gatttoolCmdlineStaticEscaped =
              BTLE_CmdlinePreventGrepFalsePositive("gatttool -i $hci -b $mac");
            my $psCommand = AttrVal( $name, 'psCommand', 'ps ax' );
            Log3( $name, 5,
"XiaomiBTLESens ($name) - ExecGatttool_Run: Execute Command $psCommand | grep -E $gatttoolCmdlineStaticEscaped"
            );

#            $grepGatttool = qx(ps ax| grep -E \'$gatttoolCmdlineStaticEscaped\')
            $grepGatttool =
              qx($psCommand | grep -E \'$gatttoolCmdlineStaticEscaped\')
              if ( $sshHost eq 'none' );

#            $grepGatttool =  qx(ssh $sshHost 'ps ax| grep -E "$gatttoolCmdlineStaticEscaped"')
            $grepGatttool =
qx(ssh $sshHost '$psCommand | grep -E "$gatttoolCmdlineStaticEscaped"')
              if ( $sshHost ne 'none' );

            if ( not $grepGatttool =~ /^\s*$/ ) {
                Log3( $name, 3,
"XiaomiBTLESens ($name) - ExecGatttool_Run: another gatttool process is running. waiting..."
                );
                sleep(1);
            }
            else {
                $wait = 0;
            }
        }

        $loop = 0;
        my $returnString;
        my $returnCode = 1;
        do {

            Log3( $name, 5,
"XiaomiBTLESens ($name) - ExecGatttool_Run: call gatttool with command: $cmd and loop $loop"
            );

            ( $returnString, $returnCode ) = Gatttool_executeCommand($cmd);
            @gtResult = split /:\s/, $returnString;

            Log3( $name, 5,
"XiaomiBTLESens ($name) - ExecGatttool_Run: gatttool loop result "
                  . join q{,}, @gtResult );

            $returnCode = 2
              if ( !defined( $gtResult[0] ) );

            $loop++;
        } while ( $loop < 5 && ( $returnCode != 0 && $returnCode != 124 ) );
        Log3( $name, 3,
"XiaomiBTLESens ($name) - ExecGatttool_Run: errorcode: \"$returnCode\", ErrorString: \"$returnString\""
        ) if ( $returnCode != 0 && $returnCode != 124 );

        Log3( $name, 4,
            "XiaomiBTLESens ($name) - ExecGatttool_Run: gatttool result "
              . join q{,}, @gtResult );

        $handle = '0x35'
          if ( $sshHost ne 'none'
            && $gattCmd eq 'write'
            && AttrVal( $name, 'model', 'none' ) eq 'flowerSens' );
        $gattCmd = 'read'
          if ( $sshHost ne 'none'
            && $gattCmd eq 'write'
            && AttrVal( $name, 'model', 'none' ) eq 'flowerSens' );

        $gtResult[1] = 'no data response'
          if ( !defined( $gtResult[1] ) );

        if ( $gtResult[1] ne 'no data response' && $listen ) {
            ( $gtResult[1] ) = split '\n', $gtResult[1];
            $gtResult[1] =~ s/\\n//g;
        }

        $json_notification = encodeJSON( $gtResult[1] );

        if ( $gtResult[1] =~ /^([0-9a-f]{2}(\s?))*$/ ) {
            return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
        }
        elsif ( $returnCode == 0 && $gattCmd eq 'write' ) {
            if ( $sshHost ne 'none' ) {
                ExecGatttool_Run( $name . "|" . $mac . "|read|0x35" );
            }
            else {
                return "$name|$mac|ok|$gattCmd|$handle|$json_notification";
            }
        }
        else {
            return "$name|$mac|error|$gattCmd|$handle|$json_notification";
        }
    }
    else {
        $json_notification = encodeJSON(
'no gatttool binary found. Please check if bluez-package is properly installed'
        );
        return "$name|$mac|error|$gattCmd|$handle|$json_notification";
    }

    return;
}

sub ExecGatttool_Done {
    my $string = shift;

    my ( $name, $mac, $respstate, $gattCmd, $handle, $json_notification ) =
      split /\|/, $string;

    my $hash = $defs{$name};

    delete( $hash->{helper}{RUNNING_PID} );

    Log3( $name, 5,
"XiaomiBTLESens ($name) - ExecGatttool_Done: Helper is disabled. Stop processing"
    ) if ( $hash->{helper}{DISABLED} );
    return if ( $hash->{helper}{DISABLED} );

    Log3( $name, 5,
"XiaomiBTLESens ($name) - ExecGatttool_Done: gatttool return string: $string"
    );

    my $decode_json = eval { decode_json($json_notification) };
    if ($@) {
        Log3( $name, 4,
"XiaomiBTLESens ($name) - ExecGatttool_Done: JSON error while request: $@"
        );
    }

    if (   $respstate eq 'ok'
        && $gattCmd eq 'write'
        && AttrVal( $name, 'model', 'none' ) eq 'flowerSens' )
    {
        CreateParamGatttool( $hash, 'read',
            $XiaomiModels{ AttrVal( $name, 'model', '' ) }{rdata} );

    }
    elsif ( $respstate eq 'ok' ) {
        ProcessingNotification( $hash, $gattCmd, $handle,
            $decode_json->{gtResult} );

    }
    else {
        ProcessingErrors( $hash, $decode_json->{gtResult} );
    }

    return;
}

sub ExecGatttool_Aborted {
    my $hash = shift;

    my $name = $hash->{NAME};
    my %readings;

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, 'state', 'unreachable', 1 );

    $readings{'lastGattError'} =
      'The BlockingCall Process terminated unexpectedly. Timedout';
    WriteReadings( $hash, \%readings );

    Log3( $name, 4,
"XiaomiBTLESens ($name) - ExecGatttool_Aborted: The BlockingCall Process terminated unexpectedly. Timedout"
    );

    return;
}

sub ProcessingNotification {
    my ( $hash, $gattCmd, $handle, $notification ) = @_;

    my $name = $hash->{NAME};
    my $readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - ProcessingNotification" );

    if ( AttrVal( $name, 'model', 'none' ) eq 'flowerSens' ) {
        if ( $handle eq '0x38' ) {
            ### Flower Sens - Read Firmware and Battery Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x38"
            );

            $readings = FlowerSensHandle0x38( $hash, $notification );

        }
        elsif ( $handle eq '0x35' ) {
            ### Flower Sens - Read Sensor Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x35"
            );

            $readings = FlowerSensHandle0x35( $hash, $notification );
        }

    }
    elsif ( AttrVal( $name, 'model', 'none' ) eq 'thermoHygroSens' ) {
        if ( $handle eq '0x18' ) {
            ### Thermo/Hygro Sens - Read Battery Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x18"
            );

            $readings = ThermoHygroSensHandle0x18( $hash, $notification );
        }
        elsif ( $handle eq '0x10' ) {
            ### Thermo/Hygro Sens - Read Sensor Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x10"
            );

            $readings = ThermoHygroSensHandle0x10( $hash, $notification );
        }
        elsif ( $handle eq '0x24' ) {
            ### Thermo/Hygro Sens - Read Firmware Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x24"
            );

            $readings = ThermoHygroSensHandle0x24( $hash, $notification );
        }
        elsif ( $handle eq '0x3' ) {
            ### Thermo/Hygro Sens - Read and Write Devicename
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x3" );

            return CreateParamGatttool( $hash, 'read',
                $XiaomiModels{ AttrVal( $name, 'model', '' ) }{devicename} )
              if ( $gattCmd ne 'read' );
            $readings = ThermoHygroSensHandle0x3( $hash, $notification );
        }
    }
    elsif ( AttrVal( $name, 'model', 'none' ) eq 'mijiaLYWSD03MMC' ) {
        if ( $handle eq '0x1b' ) {
            ### mijiaLYWSD03MMC - Read Battery Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x1b"
            );

            $readings = mijiaLYWSD03MMC_Handle0x1b( $hash, $notification );
        }
        elsif ( $handle eq '0x38' ) {
            ### mijiaLYWSD03MMC - Read Sensor Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x38"
            );

            $readings = mijiaLYWSD03MMC_Handle0x38( $hash, $notification );
        }
        elsif ( $handle eq '0x12' ) {
            ### mijiaLYWSD03MMC - Read Firmware Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x12"
            );

            $readings = mijiaLYWSD03MMC_Handle0x12( $hash, $notification );
        }
        elsif ( $handle eq '0x3' ) {
            ### mijiaLYWSD03MMC - Read and Write Devicename
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x3" );

            return CreateParamGatttool( $hash, 'read',
                $XiaomiModels{ AttrVal( $name, 'model', '' ) }{devicename} )
              unless ( $gattCmd eq 'read' );
            $readings = mijiaLYWSD03MMC_Handle0x3( $hash, $notification );
        }
    }
    elsif ( AttrVal( $name, 'model', 'none' ) eq 'clearGrassSens' ) {
        if ( $handle eq '0x3b' ) {
            ### Clear Grass Sens - Read Battery Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x3b"
            );

            $readings = ClearGrassSensHandle0x3b( $hash, $notification );
        }
        elsif ( $handle eq '0x1e' ) {
            ### Clear Grass Sens - Read Sensor Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x1e"
            );

            $readings = ClearGrassSensHandle0x1e( $hash, $notification );
        }
        elsif ( $handle eq '0x2a' ) {
            ### Clear Grass Sens - Read Firmware Data
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x2a"
            );

            $readings = ClearGrassSensHandle0x2a( $hash, $notification );
        }
        elsif ( $handle eq '0x3' ) {
            ### Clear Grass Sens - Read and Write Devicename
            Log3( $name, 4,
                "XiaomiBTLESens ($name) - ProcessingNotification: handle 0x3" );

            return CreateParamGatttool( $hash, 'read',
                $XiaomiModels{ AttrVal( $name, 'model', '' ) }{devicename} )
              if ( $gattCmd ne 'read' );
            $readings = ClearGrassSensHandle0x3( $hash, $notification );
        }
    }

    return WriteReadings( $hash, $readings );
}

sub FlowerSensHandle0x38 {
    ### FlowerSens - Read Firmware and Battery Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - FlowerSens Handle0x38" );

    my @dataBatFw = split /\s/, $notification;

    ### neue Vereinheitlichung für Batteriereadings Forum #800017
    $readings{'batteryPercent'} = hex( "0x" . $dataBatFw[0] );
    $readings{'batteryState'} =
      ( hex( "0x" . $dataBatFw[0] ) > 15 ? "ok" : "low" );

    $readings{'firmware'} =
        ( $dataBatFw[2] - 30 ) . "."
      . ( $dataBatFw[4] - 30 ) . "."
      . ( $dataBatFw[6] - 30 );

    $hash->{helper}{CallBattery} = 1;
    CallBattery_Timestamp($hash);

    return \%readings;
}

sub FlowerSensHandle0x35 {
    ### Flower Sens - Read Sensor Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - FlowerSens Handle0x35" );

    my @dataSensor = split /\s/, $notification;

    return stateRequest($hash)
      if ( $dataSensor[0] eq "aa"
        && $dataSensor[1] eq "bb"
        && $dataSensor[2] eq "cc"
        && $dataSensor[3] eq "dd"
        && $dataSensor[4] eq "ee"
        && $dataSensor[5] eq "ff" );

    if ( $dataSensor[1] eq "ff" ) {
        $readings{'temperature'} =
          ( hex( "0x" . $dataSensor[1] . $dataSensor[0] ) - hex("0xffff") ) /
          10;
    }
    else {
        $readings{'temperature'} =
          hex( "0x" . $dataSensor[1] . $dataSensor[0] ) / 10;
    }

    $readings{'lux'}       = hex( "0x" . $dataSensor[4] . $dataSensor[3] );
    $readings{'moisture'}  = hex( "0x" . $dataSensor[7] );
    $readings{'fertility'} = hex( "0x" . $dataSensor[9] . $dataSensor[8] );

    Log3( $name, 4,
            "XiaomiBTLESens ($name) - FlowerSens Handle0x35 - lux: "
          . $readings{lux}
          . ", moisture: "
          . $readings{moisture}
          . ", fertility: "
          . $readings{fertility} );

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub ThermoHygroSensHandle0x18 {
    ### Thermo/Hygro Sens - Battery Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x18" );

    chomp($notification);
    $notification =~ s/\s+//g;

    ### neue Vereinheitlichung für Batteriereadings Forum #800017
    $readings{'batteryPercent'} = hex( "0x" . $notification );
    $readings{'batteryState'} =
      ( hex( "0x" . $notification ) > 15 ? 'ok' : 'low' );

    $hash->{helper}{CallBattery} = 1;
    CallBattery_Timestamp($hash);

    return \%readings;
}

sub ThermoHygroSensHandle0x10 {
    ### Thermo/Hygro Sens - Read Sensor Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x10" );

    return stateRequest($hash)
      if ( $notification !~ /^([0-9a-f]{2}(\s?))*$/ );

    my @numberOfHex = split /\s/, $notification;

    $notification =~ s/\s+//g;

    $readings{'temperature'} = pack( 'H*', substr( $notification, 4, 8 ) );
    $readings{'humidity'} = pack(
        'H*',
        substr(
            $notification,
            (
                (
                    scalar(@numberOfHex) == 14 || ( scalar(@numberOfHex) == 13
                        && $readings{'temperature'} > 9 )
                ) ? 18 : 16
            ),
            8
        )
    );

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub ThermoHygroSensHandle0x24 {
    ### Thermo/Hygro Sens - Read Firmware Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x24" );

    $notification =~ s/\s+//g;

    $readings{'firmware'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub ThermoHygroSensHandle0x3 {
    ### Thermo/Hygro Sens - Read and Write Devicename
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Thermo/Hygro Sens Handle0x3" );

    $notification =~ s/\s+//g;

    $readings{'devicename'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub mijiaLYWSD03MMC_Handle0x1b($$) {
    ### mijiaLYWSD03MMC - Battery Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - mijiaLYWSD03MMC Handle0x1b" );

    chomp($notification);
    $notification =~ s/\s+//g;

    ### neue Vereinheitlichung für Batteriereadings Forum #800017
    $readings{'batteryPercent'} = $notification; ###hex( "0x" . $notification );
    $readings{'batteryState'} =
      ( hex( "0x" . $notification ) > 15 ? "ok" : "low" );

    $hash->{helper}{CallBattery} = 1;
    CallBattery_Timestamp($hash);
    return \%readings;
}

sub mijiaLYWSD03MMC_Handle0x38($$) {
    ### mijiaLYWSD03MMC - Read Sensor Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - mijiaLYWSD03MMC Handle0x38" );

    return stateRequest($hash)
      unless ( $notification =~ /^([0-9a-f]{2}(\s?))*$/ );

    my @splitVal = split /\s/, $notification;

    $notification =~ s/\s+//g;

    $readings{'temperature'} = hex( "0x" . $splitVal[1] . $splitVal[0] ) / 100;
    $readings{'humidity'}    = hex( "0x" . $splitVal[2] );

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub mijiaLYWSD03MMC_Handle0x12($$) {
    ### mijiaLYWSD03MMC - Read Firmware Data
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - mijiaLYWSD03MMC Handle0x12" );

    $notification =~ s/\s+//g;

    $readings{'firmware'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub mijiaLYWSD03MMC_Handle0x3($$) {
    ### mijiaLYWSD03MMC - Read and Write Devicename
    my ( $hash, $notification ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - mijiaLYWSD03MMC Handle0x3" );

    $notification =~ s/\s+//g;

    $readings{'devicename'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;
    return \%readings;
}

sub ClearGrassSensHandle0x3b {
    ### Clear Grass Sens - Battery Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Clear Grass Sens Handle0x3b" );

    chomp($notification);
    $notification =~ s/\s+//g;

    ### neue Vereinheitlichung für Batteriereadings Forum #800017
    $readings{'batteryPercent'} = hex( substr( $notification, 14, 2 ) );
    $readings{'batteryState'} =
      ( hex( substr( $notification, 14, 2 ) ) > 15 ? 'ok' : 'low' );

    $hash->{helper}{CallBattery} = 1;
    CallBattery_Timestamp($hash);

    return \%readings;
}

sub ClearGrassSensHandle0x1e {
    ### Clear Grass Sens - Read Sensor Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Clear Grass Sens Handle0x1e" );

    return stateRequest($hash)
      if ( $notification !~ /^([0-9a-f]{2}(\s?))*$/ );

    my @numberOfHex = split /\s/, $notification;

    $notification =~ s/\s+//g;

    $readings{'temperature'} = hex( substr( $notification, 4, 2 ) ) / 10;
    $readings{'humidity'} =
      hex( substr( $notification, 11, 1 ) . substr( $notification, 8, 2 ) ) /
      10;

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub ClearGrassSensHandle0x2a {
    ### Clear Grass Sens - Read Firmware Data
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Clear Grass Sens Handle0x2a" );

    $notification =~ s/\s+//g;

    $readings{'firmware'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub ClearGrassSensHandle0x3 {
    ### Clear Grass Sens - Read and Write Devicename
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - Clear Grass Sens Handle0x3" );

    $notification =~ s/\s+//g;

    $readings{'devicename'} = pack( 'H*', $notification );

    $hash->{helper}{CallBattery} = 0;

    return \%readings;
}

sub WriteReadings {
    my $hash     = shift;
    my $readings = shift;

    my $name = $hash->{NAME};

    readingsBeginUpdate($hash);
    while ( my ( $r, $v ) = each %{$readings} ) {
        readingsBulkUpdate( $hash, $r, $v );
    }

    readingsBulkUpdateIfChanged( $hash, "state",
        ( $readings->{'lastGattError'} ? 'error' : 'active' ) )
      if ( AttrVal( $name, 'model', 'none' ) eq 'flowerSens' );
    readingsBulkUpdateIfChanged(
        $hash, "state",
        (
            $readings->{'lastGattError'}
            ? 'error'
            : 'T: '
              . ReadingsVal( $name, 'temperature', 0 ) . ' H: '
              . ReadingsVal( $name, 'humidity',    0 )
        )
      )
      if ( AttrVal( $name, 'model', 'none' ) eq 'thermoHygroSens'
        || AttrVal( $name, 'model', 'none' ) eq 'mijiaLYWSD03MMC'
        || AttrVal( $name, 'model', 'none' ) eq 'clearGrassSens' );

    readingsEndUpdate( $hash, 1 );

    if ( AttrVal( $name, 'model', 'none' ) eq 'flowerSens' ) {
        if ( defined( $readings->{temperature} ) ) {
            DoTrigger(
                $name,
                'minFertility '
                  . (
                    $readings->{fertility} < AttrVal( $name, 'minFertility', 0 )
                    ? 'low'
                    : 'ok'
                  )
            ) if ( AttrVal( $name, 'minFertility', 'none' ) ne 'none' );
            DoTrigger(
                $name,
                'maxFertility '
                  . (
                    $readings->{fertility} > AttrVal( $name, 'maxFertility', 0 )
                    ? 'high'
                    : 'ok'
                  )
            ) if ( AttrVal( $name, 'maxFertility', 'none' ) ne 'none' );

            DoTrigger(
                $name,
                'minMoisture '
                  . (
                    $readings->{moisture} < AttrVal( $name, 'minMoisture', 0 )
                    ? 'low'
                    : 'ok'
                  )
            ) if ( AttrVal( $name, 'minMoisture', 'none' ) ne 'none' );
            DoTrigger(
                $name,
                'maxMoisture '
                  . (
                    $readings->{moisture} > AttrVal( $name, 'maxMoisture', 0 )
                    ? 'high'
                    : 'ok'
                  )
            ) if ( AttrVal( $name, 'maxMoisture', 'none' ) ne 'none' );

            DoTrigger(
                $name,
                'minLux '
                  . (
                    $readings->{lux} < AttrVal( $name, 'minLux', 0 )
                    ? 'low'
                    : 'ok'
                  )
            ) if ( AttrVal( $name, 'minLux', 'none' ) ne 'none' );
            DoTrigger(
                $name,
                'maxLux '
                  . (
                    $readings->{lux} > AttrVal( $name, 'maxLux', 0 )
                    ? 'high'
                    : 'ok'
                  )
            ) if ( AttrVal( $name, 'maxLux', 'none' ) ne 'none' );
        }
    }

    if ( defined( $readings->{temperature} ) ) {
        DoTrigger(
            $name,
            'minTemp '
              . (
                $readings->{temperature} < AttrVal( $name, 'minTemp', 0 )
                ? 'low'
                : 'ok'
              )
        ) if ( AttrVal( $name, 'minTemp', 'none' ) ne 'none' );
        DoTrigger(
            $name,
            'maxTemp '
              . (
                $readings->{temperature} > AttrVal( $name, 'maxTemp', 0 )
                ? 'high'
                : 'ok'
              )
        ) if ( AttrVal( $name, 'maxTemp', 'none' ) ne 'none' );
    }

    Log3( $name, 4,
        "XiaomiBTLESens ($name) - WriteReadings: Readings were written" );

    $hash->{helper}{CallSensDataCounter} = 0;
    stateRequest($hash) if ( $hash->{helper}{CallBattery} == 1 );

    return;
}

sub ProcessingErrors {
    my $hash         = shift;
    my $notification = shift;

    my $name = $hash->{NAME};
    my %readings;

    Log3( $name, 4, "XiaomiBTLESens ($name) - ProcessingErrors" );
    $readings{'lastGattError'} = $notification;

    return WriteReadings( $hash, \%readings );
}

#### my little Helper
sub encodeJSON {
    my $gtResult = shift;

    chomp($gtResult);

    my %response = ( 'gtResult' => $gtResult );

    return encode_json( \%response );
}

## Routinen damit Firmware und Batterie nur alle X male statt immer aufgerufen wird
sub CallBattery_Timestamp {
    my $hash = shift;

    # get timestamp
    $hash->{helper}{updateTimeCallBattery} =
      gettimeofday();    # in seconds since the epoch
    $hash->{helper}{updateTimestampCallBattery} = FmtDateTime( gettimeofday() );
}

sub CallBattery_UpdateTimeAge {
    my $hash = shift;

    $hash->{helper}{updateTimeCallBattery} = 0
      if ( not defined( $hash->{helper}{updateTimeCallBattery} ) );
    my $UpdateTimeAge = gettimeofday() - $hash->{helper}{updateTimeCallBattery};

    return $UpdateTimeAge;
}

sub CallBattery_IsUpdateTimeAgeToOld {
    my $hash   = shift;
    my $maxAge = shift;

    return ( CallBattery_UpdateTimeAge($hash) > $maxAge ? 1 : 0 );
}

sub CreateDevicenameHEX {
    my $devicename = shift;

    my $devicenameHex = unpack( "H*", $devicename );

    return $devicenameHex;
}

sub BTLE_CmdlinePreventGrepFalsePositive {

# https://stackoverflow.com/questions/9375711/more-elegant-ps-aux-grep-v-grep
# Given abysmal (since external-command-based) performance in the first place, we'd better
# avoid an *additional* grep process plus pipe...
    my $cmdline = shift;

    $cmdline =~ s/(.)(.*)/[$1]$2/;

    return $cmdline;
}

1;

=pod
=item device
=item summary       Modul to retrieves data from a Xiaomi BTLE Sensors
=item summary_DE    Modul um Daten vom Xiaomi BTLE Sensoren aus zu lesen

=begin html

<a name="XiaomiBTLESens"></a>
<h3>Xiaomi BTLE Sensor</h3>
<ul>
  <u><b>XiaomiBTLESens - Retrieves data from a Xiaomi BTLE Sensor</b></u>
  <br>
  With this module it is possible to read the data from a sensor and to set it as reading.</br>
  Gatttool and hcitool is required to use this modul. (apt-get install bluez)
  <br><br>
  <a name="XiaomiBTLESensdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; XiaomiBTLESens &lt;BT-MAC&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Weihnachtskaktus XiaomiBTLESens C4:7C:8D:62:42:6F</code><br>
    </ul>
    <br>
    This statement creates a XiaomiBTLESens with the name Weihnachtskaktus and the Bluetooth Mac C4:7C:8D:62:42:6F.<br>
    After the device has been created and the model attribut is set, the current data of the Xiaomi BTLE Sensor is automatically read from the device.
  </ul>
  <br><br>
  <a name="XiaomiBTLESensreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status of the flower sensor or error message if any errors.</li>
    <li>batteryState - current battery state dependent on batteryLevel.</li>
    <li>batteryPercent - current battery level in percent.</li>
    <li>fertility - Values for the fertilizer content</li>
    <li>firmware - current device firmware</li>
    <li>lux - current light intensity</li>
    <li>moisture - current moisture content</li>
    <li>temperature - current temperature</li>
  </ul>
  <br><br>
  <a name="XiaomiBTLESensset"></a>
  <b>Set</b>
  <ul>
    <li>devicename - set a devicename</li>
    <li>resetBatteryTimestamp - when the battery was changed</li>
    <br>
  </ul>
  <br><br>
  <a name="XiaomiBTLESensget"></a>
  <b>Get</b>
  <ul>
    <li>sensorData - retrieves the current data of the Xiaomi sensor</li>
    <li>devicename - fetch devicename</li>
    <li>firmware - fetch firmware</li>
    <br>
  </ul>
  <br><br>
  <a name="XiaomiBTLESensattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the device</li>
    <li>disabledForIntervals - disable device for interval time (13:00-18:30 or 13:00-18:30 22:00-23:00)</li>
    <li>interval - interval in seconds for statusRequest</li>
    <li>minFertility - min fertility value for low warn event</li>
    <li>hciDevice - select bluetooth dongle device</li>
    <li>model - set model type</li>
    <li>maxFertility - max fertility value for High warn event</li>
    <li>minMoisture - min moisture value for low warn event</li>
    <li>maxMoisture - max moisture value for High warn event</li>
    <li>minTemp - min temperature value for low warn event</li>
    <li>maxTemp - max temperature value for high warn event</li>
    <li>minlux - min lux value for low warn event</li>
    <li>maxlux - max lux value for high warn event
    <br>
    Event Example for min/max Value's: 2017-03-16 11:08:05 XiaomiBTLESens Dracaena minMoisture low<br>
    Event Example for min/max Value's: 2017-03-16 11:08:06 XiaomiBTLESens Dracaena maxTemp high</li>
    <li>sshHost - FQD-Name or IP of ssh remote system / you must configure your ssh system for certificate authentication. For better handling you can config ssh Client with .ssh/config file</li>
    <li>batteryFirmwareAge - how old can the reading befor fetch new data</li>
    <li>blockingCallLoglevel - Blocking.pm Loglevel for BlockingCall Logoutput</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="XiaomiBTLESens"></a>
<h3>Xiaomi BTLE Sensor</h3>
<ul>
  <u><b>XiaomiBTLESens - liest Daten von einem Xiaomi BTLE Sensor</b></u>
  <br />
  Dieser Modul liest Daten von einem Sensor und legt sie in den Readings ab.<br />
  Auf dem (Linux) FHEM-Server werden gatttool und hcitool vorausgesetzt. (sudo apt install bluez)
  <br /><br />
  <a name="XiaomiBTLESensdefine"></a>
  <b>Define</b>
  <ul><br />
    <code>define &lt;name&gt; XiaomiBTLESens &lt;BT-MAC&gt;</code>
    <br /><br />
    Beispiel:
    <ul><br />
      <code>define Weihnachtskaktus XiaomiBTLESens C4:7C:8D:62:42:6F</code><br />
    </ul>
    <br />
    Der Befehl legt ein Device vom Typ XiaomiBTLESens mit dem Namen Weihnachtskaktus und der Bluetooth MAC C4:7C:8D:62:42:6F an.<br />
    Nach dem Anlegen des Device und setzen des korrekten model Attributes werden umgehend und automatisch die aktuellen Daten vom betroffenen Xiaomi BTLE Sensor gelesen.
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status des BTLE Sensor oder eine Fehlermeldung falls Fehler beim letzten Kontakt auftraten.</li>
    <li>batteryState - aktueller Batterie-Status in Abhängigkeit vom Wert batteryLevel.</li>
    <li>batteryPercent - aktueller Ladestand der Batterie in Prozent.</li>
    <li>fertility - Wert des Fruchtbarkeitssensors (Bodenleitf&auml;higkeit)</li>
    <li>firmware - aktuelle Firmware-Version des BTLE Sensor</li>
    <li>lastGattError - Fehlermeldungen vom gatttool</li>
    <li>lux - aktuelle Lichtintensit&auml;t</li>
    <li>moisture - aktueller Feuchtigkeitswert</li>
    <li>temperature - aktuelle Temperatur</li>
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensset"></a>
  <b>Set</b>
  <ul>
    <li>resetBatteryTimestamp - wenn die Batterie gewechselt wurde</li>
    <li>devicename - setzt einen Devicenamen</li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensGet"></a>
  <b>Get</b>
  <ul>
    <li>sensorData - aktive Abfrage der Sensors Werte</li>
    <li>devicename - liest den Devicenamen aus</li>
    <li>firmware - liest die Firmeware aus</li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiBTLESensattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Device</li>
    <li>interval - Interval in Sekunden zwischen zwei Abfragen</li>
    <li>disabledForIntervals - deaktiviert das Gerät für den angegebenen Zeitinterval (13:00-18:30 or 13:00-18:30 22:00-23:00)</li>
    <li>minFertility - min Fruchtbarkeits-Grenzwert f&uuml;r ein Ereignis minFertility low </li>
    <li>hciDevice - Auswahl bei mehreren Bluetooth Dongeln</li>
    <li>model - setzt das Model</li>
    <li>maxFertility - max Fruchtbarkeits-Grenzwert f&uuml;r ein Ereignis maxFertility high </li>
    <li>minMoisture - min Feuchtigkeits-Grenzwert f&uuml;r ein Ereignis minMoisture low </li> 
    <li>maxMoisture - max Feuchtigkeits-Grenzwert f&uuml;r ein Ereignis maxMoisture high </li>
    <li>minTemp - min Temperatur-Grenzwert f&uuml;r ein Ereignis minTemp low </li>
    <li>maxTemp - max Temperatur-Grenzwert f&uuml;r ein Ereignis maxTemp high </li>
    <li>minlux - min Helligkeits-Grenzwert f&uuml;r ein Ereignis minlux low </li>
    <li>maxlux - max Helligkeits-Grenzwert f&uuml;r ein Ereignis maxlux high
    <br /><br />Beispiele f&uuml;r min/max-Ereignisse:<br />
    2017-03-16 11:08:05 XiaomiBTLESens Dracaena minMoisture low<br />
    2017-03-16 11:08:06 XiaomiBTLESens Dracaena maxTemp high<br /><br /></li>
    <li>sshHost - FQDN oder IP-Adresse eines entfernten SSH-Systems. Das SSH-System ist auf eine Zertifikat basierte Authentifizierung zu konfigurieren. Am elegantesten geschieht das mit einer  .ssh/config Datei auf dem SSH-Client.</li>
    <li>batteryFirmwareAge - wie alt soll der Timestamp des Readings sein bevor eine Aktuallisierung statt findet</li>
    <li>blockingCallLoglevel - Blocking.pm Loglevel für BlockingCall Logausgaben</li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 74_XiaomiBTLESens.pm
{
  "abstract": "Modul to retrieves data from a Xiaomi BTLE Sensors",
  "x_lang": {
    "de": {
      "abstract": "Modul um Daten vom Xiaomi BTLE Sensoren aus zu lesen"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Flower",
    "BTLE",
    "Xiaomi",
    "Sensor",
    "Bluetooth LE"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v3.0.0",
  "author": [
    "Marko Oldenburg <leongaultier@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 1,
        "Blocking": 1,
        "JSON": 1
      },
      "recommends": {
        "JSON": 0
      },
      "suggests": {
        "Cpanel::JSON::XS": 0,
        "JSON::XS": 0
      }
    }
  }
}
=end :application/json;q=META.json

=cut

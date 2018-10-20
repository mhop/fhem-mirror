#############################################################
#
#  Copyright notice
#
#  (c) 2016
#  Copyright:           Juergen Kellerer (juergen at k123 dot eu)
#  FHEM Maintenance:    Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
# $Id$
#
#############################################################
#
# SmaterCoffee.pm by Juergen Kellerer, 2016
#
# FHEM module to communicate with a Smarter Coffee machine
#
# Credits:
# Thanks to creators and contributors of:
# - https://github.com/nanab/smartercoffee
# - https://github.com/petermajor/SmartThingsSmarterCoffee
# - https://github.com/Tristan79/iBrew
# .. and to all the volonteers crafting the FHEM project.
#
# Version: 1.0.0
#
#############################################################
# v1.0.0 - 2018-10-19
#  - change modul code to package module routine
#  - change code FHEM conform
#  - add multiple Attribut to control IoDev modul output
# v0.9.1 - 2017-04-25
#  - fixed "stop" detection interferring with "extra" strength.
#  - added new state "grinding".
# v0.9 - 2017-04-24
#  - added "strength-extra-start-on-device-strength" which allows
#    brewing with "extra" strength using device buttons.
#  - added "INITIATED_BREWING" internals to see if FHEM started it.
#  - fixed timing problem when forcing "grinder" in extra mode.
#  - fixed "stop" using device button doesn't reset extra mode.
#  - fixed incorrect placement of start and end anchors in event
#    regex leading to a too broad event handling for INITIALIZED
#    events.
#  - fixed "hotplate off" didn't reset state to "ready".
#
# v0.8 - 2017-03-18
#  - added "controls.txt" to support automatic updates in FHEM.
#  - changed default value of 'strength extra' to 140% to match
#    6 gramms coffee per cup by default.
#  - improved dev-state icon and documentation.
#  - fixed possible fallthrough to brew in pre-brew phase.
#  - fixed a problem that strength extra could be started without
#    also enabling grinder.
#  - fixed 'strength extra' not being restored when restarting.
#
# v0.7 - 2016-08-28
#  - added 'reset' defaults to factory settings command.
#  - added 'get_defaults'.
#  - added 'strength-extra-pre-brew-*'.
#
# v0.6 - 2016-08-20
#  - final updates & cleanup, preparation for initial checking.
#
# v0.5 - 2016-08-19
#  - added strength "extra"
#  - added descale detection and descale command
#  - improvements in connection handling
#
# v0.4 - 2016-08-17
#  - added "set defaults" command
#  - support reading device type and firmware version
#  - changed status detection from simple mapping to bitmasks
#  - handling carafe required dealing with "ready" state
#
# v0.3 - 2016-08-06
#  - added custom state icon (embedded SVG)
#
# v0.2 - 2016-07-30
#  - support auto discovery via UPD broadcast
#  - start brewing with custom / default settings
#  - stop brewing while running
#
# v0.1 - 2016-07-29
#  - define Smarter Coffee based on fixed IP or hostname
#  - set cups, strength, grinder and toggle hotplate
#  - start brewing
#  - view detailed status
#
#############################################################

package main;

use strict;
use warnings;

my $version = "1.0.0";

sub SmarterCoffee_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}    = 'SmarterCoffee::Define';
    $hash->{UndefFn}  = 'SmarterCoffee::Undefine';
    $hash->{GetFn}    = 'SmarterCoffee::Get';
    $hash->{SetFn}    = 'SmarterCoffee::Set';
    $hash->{ReadFn}   = 'SmarterCoffee::Read';
    $hash->{ReadyFn}  = 'SmarterCoffee::OpenIfRequiredAndWritePending';
    $hash->{NotifyFn} = 'SmarterCoffee::Notify';
    $hash->{AttrFn}   = 'SmarterCoffee::Attr';

    $hash->{AttrList} = ""
      . "default-hotplate-on-for-minutes "
      . "ignore-max-cups "
      . "set-on-brews-coffee "
      . "strength-coffee-weights "
      . "strength-extra-percent "
      . "strength-extra-pre-brew-cups "
      . "strength-extra-pre-brew-delay-seconds "
      . "strength-extra-start-on-device-strength:off,weak,medium,strong "
      . "devioLoglevel:0,1,2,3,4,5 "
      . $readingFnAttributes;

    foreach my $d ( sort keys %{ $modules{SmarterCoffee}{defptr} } ) {
        my $hash = $modules{SmarterCoffee}{defptr}{$d};
        $hash->{VERSION} = $version;
    }
}

package SmarterCoffee;

use strict;
use warnings;
use POSIX;

use GPUtils qw(:all)
  ;    # wird für den Import der FHEM Funktionen aus der fhem.pl benötigt

use Data::Dumper;
use Socket;
use IO::Select;

use DevIo;

#use HttpUtils;

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          CommandAttr
          defs
          modules
          Log3
          AttrVal
          ReadingsVal
          ReadingsNum
          Value
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          DoTrigger)
    );
}

my $port                        = 2081;
my $discoveryInterval           = 60 * 15;
my $strengthExtraDefaultPercent = 1.4;
my $strengthDefaultWeights      = "3.5 3.9 4.3";
my %hotplate                    = ( default => 15, min => 5, max => 40 );

my %messageMaps = (
    status_bitmasks => [

        # BIT 1 = ???
        # BIT 2 = hotplate
        # BIT 3 = idle/heating
        # BIT 4 = brewing/descaling
        # BIT 5 = grinding
        # BIT 6 = ready/done
        # BIT 7 = grinder
        # BIT 8 = carafe
        [
            '00000000' => {
                grinder  => "disabled",
                carafe   => "missing",
                hotplate => "off",
                state    => "maintenance"
            }
        ],
        [ '01000000' => { hotplate => "on" } ],
        [ '00000100' => { state    => "ready" } ],
        [ '00100000' => { state    => "ready" } ]
        ,    # Set when hotplate is off after being in "heating" state.
        [ '01000100' => { state   => "done" } ],
        [ '00001000' => { state   => "grinding" } ],
        [ '01010000' => { state   => "brewing" } ],
        [ '01100000' => { state   => "heating" } ],
        [ '00000010' => { grinder => "enabled" } ],
        [ '00000001' => { carafe  => "present" } ],
    ],

    water => {

        # HEX key, only lower 4 bits are used.
        '00' => { water => "none", water_level => 0 },
        '01' => { water => "low",  water_level => 25 },
        '02' => { water => "half", water_level => 50 },
        '03' => { water => "full", water_level => 100 },
    },

    strength => {

        # HEX key, only lower 4 bits are used.
        '00' => { strength => "weak",   strength_level => 1 },
        '01' => { strength => "medium", strength_level => 2 },
        '02' => { strength => "strong", strength_level => 3 },
    },

    cups => {

        # HEX key, only lower 4 bits are used.
        '01' => 1,
        '02' => 2,
        '03' => 3,
        '04' => 4,
        '05' => 5,
        '06' => 6,
        '07' => 7,
        '08' => 8,
        '09' => 9,
        '0a' => 10,
        '0b' => 11,
        '0c' => 12
    },

    grinder => {
        '00' => "disabled",
        '01' => "enabled"
    }
);

my %commands = (
    reset                   => "107e",
    brew                    => "377e",
    brew_with_settings      => "33########7e",
    adjust_defaults         => "38########7e",
    get_defaults            => "487e",
    stop                    => "347e",
    strength                => "35##7e",
    cups                    => "36##7e",
    grinder                 => "3c7e",
    hotplate_on_for_minutes => "3e##7e",
    hotplate_off            => "4a7e",
    carafe_required_status  => "4c7e",
    cups_single_mode_status => "4f7e",
    info                    => "647e",
    history                 => "467e"
);

my @getCommands = (
    "info",                    "carafe_required_status",
    "cups_single_mode_status", "get_defaults"
);    #, "history"

my %responseCodes = (
    '00' => { message => 'Ok',                      success => 'yes' },
    '01' => { message => 'Ok, brewing in progress', success => 'yes' },

    '04' => { message => 'Ok, stopped', success => 'yes' },

    '05' => { message => 'No carafe, brewing not possible', success => 'no' },
    '06' => { message => 'No water, brewing not possible',  success => 'no' },

    '69' => { message => 'Invalid command', success => 'no' },
);

sub ParseMessage {
    my ( $hash, $message ) = @_;

    $message = ( $hash->{PARTIAL} // "" ) if ( not defined($message) );

    if ( $message =~ /^(32|03|47|49|4d|50|65)[0-9a-f]+7e.*/ ) {

        Log3 $hash->{NAME}, 5,
            "Connection :: Received from "
          . ( $hash->{DeviceName} // "unknown" )
          . ": $message";

        # Handle multiple messages in one frame:
        my @messages = split( "7e", $message );
        if ( int(@messages) > 1 ) {
            my $failed;
            for (@messages) {
                $failed = 1 if ( not ParseMessage( $hash, $_ . "7e" ) );
            }
            return not $failed;
        }

        # Handle single message:
        $hash->{".last_response"} = $message
          if $message =~ /^(03|49|4d|50|65).+7e.*/;

        # Parse response of a command.
        if ( $message =~ /^03([0-9a-f]{2})7e.*/ ) {
            if ( my $response = ( $responseCodes{$1} // 0 ) ) {
                UpdateReadings(
                    $hash,
                    sub($) {
                        my ($updateReading) = @_;
                        while ( my ( $key, $value ) = each %{$response} ) {
                            $updateReading->( "last_command_$key", $value );
                        }
                        $updateReading->(
                            "last_command", $hash->{".last_set_command"}
                        );
                    },
                    1
                );
            }
            else {
                Log3 $hash->{NAME}, 3,
                  "Connection :: Unknown command response '$message'.";
            }
        }

        # Parse history message.
        if ( $message =~ /^47([0-9a-f]{2})(.+)7e.*/ ) {
            my @history = split( "7d", $2 );

            Log3 $hash->{NAME}, 5, Dumper(@history);    #TODO
        }

        # Parse default settings message.
        if ( $message =~ /^49([0-9a-f]+)7e.*/ ) {
            my %values = (
                cups     => '0' . substr( $1, 1, 1 ),
                strength => substr( $1, 2, 2 ),
                grinder  => '0' . substr( $1, 5, 1 ),
                hotplate => substr( $1, 6, 2 ),
            );

            ParseStatusValues( $hash, \%values );
            DoTrigger( $hash->{NAME}, "get_defaults" );
            Set( $hash, @{ [ $hash->{NAME}, "defaults" ] } );
        }

        # Parse carafe detection status message.
        if ( $message =~ /^4d([0-9a-f]{2})7e.*/ ) {
            UpdateReading( $hash, "carafe_required",
                ( $1 eq "01" ? "no" : "yes" ) );
        }

        # Parse single cup mode status message.
        if ( $message =~ /^50([0-9a-f]{2})7e.*/ ) {
            UpdateReading( $hash, "cups_single_mode",
                ( $1 eq "00" ? "no" : "yes" ) );
        }

        # Parse info & discovery message.
        if ( $message =~ /^65([0-9a-f]{2})([0-9a-f]{2})7e.*/ ) {
            $hash->{FIRMWARE} = ord( pack( "H2", $2 ) );
            return 0 if ( $1 ne "02" );
        }

        # Parse status message.
        if (    $message =~ /^(32[0-9a-f]+7e).*/
            and $message ne $hash->{".raw_last_status"} )
        {
            $hash->{".last_status"} = $hash->{".raw_last_status"} = $message =
              $1;

            my %values = (
                status   => substr( $message, 2, 2 ),
                water    => '0' . substr( $message, 5, 1 ),
                strength => substr( $message, 8, 2 ),
                cups     => '0' . substr( $message, 11, 1 ),
            );

            ParseStatusValues( $hash, \%values );
        }

        $hash->{CONNECTION} = ""
          . "STATUS: "
          . ( $hash->{".last_status"} // "n/a" )
          . " | COMMAND: "
          . ( $hash->{".last_command"} // "n/a" ) . " => "
          . ( $hash->{".last_response"} // "n/a" );

        return 1;
    }

    return 0;
}

sub DumpToExpression($) {
    my $d = Dumper( $_[0] );
    $d =~ s/\s+/ /g;
    $d =~ s/[^\}]*(\{.+\})[^\}]*/$1/;
    return $d;
}

sub ParseStatusValues {
    my ( $hash, $values ) = @_;

    while ( my ( $mappingKey, $rawValue ) = each %{$values} ) {
        if ( $mappingKey eq "status" ) {
            my %status = ();
            my $unpackedStatusBits =
              sprintf( '%08b', ord( pack( "H2", $rawValue ) ) );
            $hash->{".last_status"} .= " ($unpackedStatusBits)";

            for ( @{ $messageMaps{"status_bitmasks"} } ) {
                my ( $unpackedBitmask, $statusInfo ) = @{$_};

                my $bitmask = ord( pack( "B8", $unpackedBitmask ) );
                if ( ( $bitmask & ord( pack( "B8", $unpackedStatusBits ) ) ) ==
                    $bitmask )
                {
                    while ( my ( $k, $v ) = each( %{$statusInfo} ) ) {
                        $status{$k} = $v;
                    }

                    Log3 $hash->{NAME}, 5,
"Connection :: Matched all bits of $unpackedBitmask in $unpackedStatusBits. Setting: "
                      . DumpToExpression($statusInfo);
                }
            }
            $values->{$mappingKey} = {%status};
        }
        else {
            if ( defined( $messageMaps{$mappingKey}{$rawValue} ) ) {
                $values->{$mappingKey} = $messageMaps{$mappingKey}{$rawValue};
            }
            elsif ( $mappingKey eq "hotplate" ) {
                $values->{$mappingKey} =
                  { "hotplate_on_for_minutes" => hex($rawValue) };
            }
            else {
                Log3 $hash->{NAME}, 3,
"Connection :: Unknown value '$rawValue' for $mappingKey message part.";
                $values->{$mappingKey} = {};
            }
        }
    }

    Log3 $hash->{NAME}, 5, "Connection :: Parsed message: " . Dumper($values);

    UpdateReadings(
        $hash,
        sub($) {
            my ($updateReading) = @_;
            my $state = 0;

            while ( my ( $n, $readings ) = each %{$values} ) {
                $readings = { $n => $readings } if ( ref($readings) ne "HASH" );

                while ( my ( $name, $value ) = each %{$readings} ) {
                    if ( $name eq "state" ) {
                        $state = $value;
                    }
                    else {
                        $updateReading->( $name, $value );
                    }
                }
            }

            # Adding calculated readings
            if (
                defined( $values->{"water"} )
                and (
                    my $maxCups = int(
                        ( $values->{"water"}{"water_level"} // 0 ) / 100 * 12
                    )
                )
              )
            {
                $maxCups = 3
                  if ( $maxCups > 3
                    and ReadingsVal( $hash->{NAME}, "cups_single_mode", "" ) eq
                    "yes" );
                $updateReading->( "cups_max", $maxCups );
            }

            # Overriding "ready" state if carafe or water is missing.
            if ( $state eq "ready" ) {
                my $cupsOk = (
                    AttrVal( $hash->{NAME}, "ignore-max-cups", 1 )
                      or ( ReadingsNum( $hash->{NAME}, "cups_max", 0 ) >=
                        ReadingsNum( $hash->{NAME}, "cups", 0 ) )
                );

                my $carafeOk = (
                    ReadingsVal( $hash->{NAME}, "carafe_required", "yes" ) ne
                      "yes"
                      or
                      ( ( $values->{"status"}{"carafe"} // "" ) eq "present" )
                );

                my $waterOk =
                  ( ( $values->{"water"}{"water_level"} // 0 ) > 0 );

                $state = "maintenance"
                  if ( not $carafeOk or not $waterOk or not $cupsOk );
            }

            # Setting status at last when all other readings are updated.
            $updateReading->( "state", $state ) if $state;
        }
    );
}

sub Connect($) {
    my ($hash) = @_;

    my $isNewConnection =
      ReadingsVal( $hash->{NAME}, 'state', 'none' ) eq "initializing";

    readingsSingleUpdate( $hash, 'state', 'disconnected', 0 );
    delete $hash->{INVALID_DEVICE} if defined( $hash->{INVALID_DEVICE} );

    if ( $hash->{AUTO_DETECT} ) {
        RunDiscoveryProcess( $hash, 1 );
    }

    if ( defined( $hash->{DeviceName} ) ) {
        if ( not( $hash->{DeviceName} =~ m/^(.+):([0-9]+)$/ ) ) {
            $hash->{DeviceName} .= ":$port";
        }

        main::main::DevIo_CloseDev($hash) if main::DevIo_IsOpen($hash);
        delete $hash->{DevIoJustClosed}   if ( $hash->{DevIoJustClosed} );

        return OpenIfRequiredAndWritePending( $hash, $isNewConnection );
    }
    return 0;
}

sub OpenIfRequiredAndWritePending($;$) {
    my ( $hash, $initial ) = @_;
    return main::DevIo_OpenDev( $hash, ( $initial ? 0 : 1 ),
        "SmarterCoffee::WritePending" );
}

sub HandleInitialConnectState($) {
    my ($hash) = @_;

    return if ( $hash->{".initial-connection-state"} );

    if (
        main::DevIo_IsOpen($hash)
        and (  ReadingsVal( $hash->{NAME}, 'state', 'none' ) eq "disconnected"
            or ReadingsVal( $hash->{NAME}, 'state', 'none' ) eq "opened" )
      )
    {
        $hash->{".initial-connection-state"} = 1;

        readingsSingleUpdate( $hash, 'state', 'connected', 0 );
        Get( $hash, @{ [ $hash->{NAME}, "info" ] } )
          if ( not $hash->{AUTO_DETECT} );
        Get( $hash, @{ [ $hash->{NAME}, "carafe_required_status" ] } );
        Get( $hash, @{ [ $hash->{NAME}, "cups_single_mode_status" ] } );

        delete $hash->{".initial-connection-state"};
    }
}

sub WritePending {
    my ( $hash, $mustSucceed ) = @_;

    if ( main::DevIo_IsOpen($hash) ) {
        my $pending = ( $hash->{PENDING_COMMAND} // 0 );

        # Handling initial call on a fresh connection
        HandleInitialConnectState($hash);

        # Processing pending commands
        if ( ( $hash->{INVALID_DEVICE} // "0" ) eq "1" ) {
            readingsSingleUpdate( $hash, 'state', 'invalid', 0 );
        }
        else {
            if ($pending) {
                delete $hash->{PENDING_COMMAND}
                  if defined( $hash->{PENDING_COMMAND} );

                Log3 $hash->{NAME}, 4,
                    "Connection :: Sending to "
                  . $hash->{DeviceName}
                  . ": $pending";
                main::DevIo_SimpleWrite( $hash, $pending, 1 );
                $hash->{".raw_last_status"} = "";

                my $result = main::DevIo_SimpleReadWithTimeout( $hash, 5 );
                if ($result) {
                    $result = Read( $hash, $result );
                }
                else {
                    main::DevIo_Disconnected($hash);
                }

                $hash->{INVALID_DEVICE} = "1"
                  if ( $mustSucceed and not $result );
                $hash->{PENDING_COMMAND} = $pending if ( not $result );
            }
        }
    }

    return undef;
}

sub Read($;$) {
    my ( $hash, $buffer ) = @_;

  # Handle case that fhem reconnected a broken connection and state is "opened".
    HandleInitialConnectState($hash) if ( not defined($buffer) );

    # Abort read if we already detected that the device is invalid.
    return 0 if ( $hash->{INVALID_DEVICE} // 0 );

# Reset partial data buffer if it exceeds length of 512 (256 bytes) or when $buffer was specified explicitly.
    $hash->{PARTIAL} = ""
      if ( not defined( $hash->{PARTIAL} )
        or defined($buffer)
        or length( $hash->{PARTIAL} // "" ) >= 512 );

    # Reading available bytes from the socket (if not specified from external).
    $buffer = main::DevIo_SimpleRead($hash) if ( not defined($buffer) );
    return 0 if ( not defined($buffer) );

    # Appending message bytes as hex string.
    $hash->{PARTIAL} .= unpack( 'H*', $buffer );

    # Parsing the message and populate readings.
    if ( $hash->{PARTIAL} ne "" ) {
        if ( ParseMessage($hash) ) {
            delete $hash->{PARTIAL};
        }
        else {
            Log3 $hash->{NAME}, 2,
              "Connection :: Failed parsing buffer content: "
              . $hash->{PARTIAL};
            return 0;
        }
    }

    return 1;
}

sub Define($$) {
    my ( $hash, $def ) = @_;
    my @param = split( '[ \t]+', $def );
    my $name = $hash->{NAME};

    # set default settings on first define
    if ($init_done) {
        CommandAttr( undef, $name . ' alias Coffee Machine' )
          if ( AttrVal( $name, 'alias', 'none' ) eq 'none' );
        CommandAttr( undef, $name . ' webCmd strength:cups:start:hotplate:off' )
          if ( AttrVal( $name, 'webCmd', 'none' ) eq 'none' );
        CommandAttr( undef,
            $name . ' strength-extra-percent ' . $strengthExtraDefaultPercent )
          if ( AttrVal( $name, 'strength-extra-percent', 'none' ) eq 'none' );
        CommandAttr( undef,
            $name . ' default-hotplate-on-for-minutes 15 5=20 8=30 10=35' )
          if ( AttrVal( $name, 'default-hotplate-on-for-minutes', 'none' ) eq
            'none' );
        CommandAttr( undef, $name . ' event-on-change-reading .*' )
          if ( AttrVal( $name, 'event-on-change-reading', 'none' ) eq 'none' );
        CommandAttr( undef, $name . ' event-on-update-reading last_command.*' )
          if ( AttrVal( $name, 'event-on-update-reading', 'none' ) eq 'none' );
        CommandAttr( undef, $name . ' devioLoglevel 4' )
          if ( AttrVal( $name, 'devioLoglevel', 'none' ) eq 'none' );
    }

    CommandAttr( undef,
        $name . 'devStateIcon { SmarterCoffee::GetDevStateIcon($name) }' )
      if ( AttrVal( $name, 'devStateIcon', 'none' ) eq 'none'
        or AttrVal( $name, 'devStateIcon', 'none' ) eq
        '{ SmarterCoffee_GetDevStateIcon($name) }' );

    $hash->{VERSION} = $version;
    if ( int(@param) < 3 ) {
        $hash->{AUTO_DETECT} = 1;
    }
    else {
        delete $hash->{AUTO_DETECT};
        $hash->{DeviceName} = $param[2];
    }

    $hash->{NOTIFYDEV} = "global,$name";
    readingsSingleUpdate( $hash, 'state', 'initializing', 0 );

    $hash->{".last_command"} = $hash->{".last_response"} =
      $hash->{".last_status"} = $hash->{".raw_last_status"} = "";

    Connect($hash);

    $modules{SmarterCoffee}{defptr}{CoolTux} = $hash;

    Log3 $hash->{NAME}, 4,
      "Instance :: Defined module 'SmarterCoffee': " . Dumper($hash);
}

sub Undefine($$) {
    my ( $hash, $arg ) = @_;

    RemoveInternalTimer($hash);
    main::DevIo_CloseDev($hash);

    Log3 $hash->{NAME}, 4,
      "Instance :: Closed module 'SmarterCoffee': " . Dumper($hash);

    delete( $modules{SmarterCoffee}{defptr}{CoolTux} );

    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "devioLoglevel" ) {
        if ( $cmd eq "set" ) {
            $hash->{devioLoglevel} = $attrVal;
            Log3 $name, 3,
              "SmarterCoffee ($name) - set devioLoglevel to $attrVal";

        }
        elsif ( $cmd eq "del" ) {
            delete $hash->{devioLoglevel};
            Log3 $name, 3,
              "SmarterCoffee ($name) - delete Internal devioLoglevel";
        }
    }

    return undef;
}

sub Get {
    my ( $hash, @param ) = @_;

    if ( grep { $_ eq ( $param[1] // "" ) } @getCommands ) {
        return Set( $hash, @param ) // "Ok :: " . $hash->{".last_response"};
    }
    else {
        return
            "Unknown argument $param[1], choose one of "
          . join( ":noArg ", @getCommands )
          . ":noArg";
    }
}

sub Set {
    my ( $hash, @param ) = @_;

    my $desiredCups =
      defined( $hash->{".extra_strength.original_desired_cups"} )
      ? $hash->{".extra_strength.original_desired_cups"}
      : ReadingsVal( $hash->{NAME}, "cups", 1 );

    my $optionToMessage = sub($$;$) {
        my ( $option, $optionValue, $value ) = @_;

        # Remembering "cups" when a message part is looked-up.
        $desiredCups = int($optionValue)
          if ( $option eq "cups" and $optionValue =~ /^[0-9]+$/ );

        # Special treatment for hotplate, syntax: "set hotplate (on|off) [5-40]"
        if ( $option =~ /^hotplate.*/ ) {

# Select default time from "[minutes] [cups=minutes]", e.g.: "15 5=20 10=35" means: 15 default, 20 from 5 cups and 35 from 10 cups.
            my ( $defaultOnForMinutes, $overrides ) = parseParams(
                AttrVal(
                    $hash->{NAME}, "default-hotplate-on-for-minutes",
                    $hotplate{default}
                )
            );
            $defaultOnForMinutes = $defaultOnForMinutes->[0]
              if ( defined($defaultOnForMinutes)
                and int($defaultOnForMinutes) > 0 );
            for my $key ( sort { $a <=> $b } ( keys %{$overrides} ) ) {
                $defaultOnForMinutes = $overrides->{$key}
                  if ( int($desiredCups) >= int($key) );
            }

            $value = $optionValue if ( not defined($value) );
            $value =
              $value =~ /^[0-9]+$/ ? int($value) : int($defaultOnForMinutes);
            $value = $hotplate{max} if ( $value > $hotplate{max} );
            $value = $hotplate{min} if ( $value < $hotplate{min} );

            UpdateReading( $hash, "hotplate_on_for_minutes",
                ( $option eq "hotplate_off" ? 0 : $value ) );

            return unpack( 'H*', pack( 'C', $value ) );

        }
        elsif ( defined( $messageMaps{$option} ) and defined($optionValue) ) {

# Ordinary values are looked up in the message maps (looking up the HEX code that backs a setting).
            for my $key ( keys %{ $messageMaps{$option} } ) {
                my $v = $messageMaps{$option}{$key};
                if (
                    (
                        ref($v) eq "HASH"
                        ? grep( /^$optionValue$/, values %{$v} )
                        : $v eq $optionValue
                    )
                  )
                {
                    return $key;
                }
            }
        }

        return undef;
    };

    # Command & params pre-processing
    my ( $instanceName, $option, $messagePart ) =
      ( shift @param, shift @param, undef );

    # Support "set <name> off"
    $option = "stop" if ( $option =~ /^off$/i );

    # Support "set <name> on" and "set <name> start"
    if (
        (
            $option =~ /^on$/i
            and AttrVal( $hash->{NAME}, "set-on-brews-coffee", "0" ) =~
            /^(yes|true|1)$/i
        )
        or $option =~ /^start$/i
      )
    {
        $option = "brew";
    }

   # Support "set 6-cups" as alias to "set brew 6" (for better readable webCmds)
    if ( $option =~ /^([0-9]+)-cups(|[\-_,:;][a-z]+)$/i ) {
        unshift( @param, substr( $2, 1 ) )
          if ($2);    # supporting "set 3-cups,strong"
        unshift( @param, $1 );
        $option = "brew";
    }

    if ( $option eq "brew" or $option eq "defaults" ) {

        # Handle extra strong coffee
        if ( ( $param[1] // ReadingsVal( $hash->{NAME}, "strength", "" ) ) =~
            /^extra.*/ )
        {
          # Enable grinder in extra mode if required and option is not defaults.
            my $grinderEnabled =
              ( ( $param[3] // ReadingsVal( $hash->{NAME}, "grinder", "" ) ) eq
                  "enabled" );
            if (    $option ne "defaults"
                and not $grinderEnabled
                and ( $param[3] // "" ) ne "disabled" )
            {
                Set( $hash, @{ [ $hash->{NAME}, "grinder", "enabled" ] } );
                $grinderEnabled = 1;
                $param[3] = "enabled" if defined( $param[3] );
            }

            if ( $option ne "defaults" and $grinderEnabled ) {
                if (
                    TranslateParamsForExtraStrength( $hash, \@param, "grind" ) )
                {
                    my ( $cups, $error ) = (
                        $hash->{".extra_strength.desired_cups"},
                        $hash->{".extra_strength.error_rate"}
                    );
                    Log3 $hash->{NAME}, 3,
                        "Extra Strength :: Grinding ["
                      . join( " ", @param )
                      . "] to get $cups cups (error rate: $error%).";
                }
                else {
                    return "strength 'extra' failed. check water level.";
                }
            }
            else {
                Log3 $hash->{NAME}, 3,
"Extra Strength :: Downgrading strength extra to 'strong' for set $option.";
                $param[1] = "strong";
            }
        }

        # Handle normal brew or set defaults
        if ( not defined( $param[0] ) or $param[0] ne "current" ) {

            # Get message parts
            my %input = (
                "cups"     => $param[0],
                "strength" => $param[1],
                "hotplate" => $param[2],
                "grinder"  => $param[3]
            );
            my %readingsValues = (%input);
            my $inputsDefined  = 0;

            for my $key ( keys %input ) {

                # Translating input to message part.
                $input{$key} = $optionToMessage->( $key, $input{$key} )
                  if defined( $input{$key} );

# Taking message part from readings if input didn't specifiy it (using "on" for "hotplate" as the reading would be missleading.
                if ( not defined( $input{$key} ) ) {
                    $readingsValues{$key} = (
                        $key eq "hotplate"
                        ? (
                            ReadingsVal(
                                $hash->{NAME}, "cups_single_mode", ""
                            ) eq "yes" ? 0 : "on"
                          )
                        : ReadingsVal( $hash->{NAME}, $key, "" )
                    );

                    $input{$key} =
                      $optionToMessage->( $key, $readingsValues{$key} );
                }

                # Count if message part was retrieved
                $inputsDefined++ if defined( $input{$key} );
            }

            if ( $inputsDefined == 4 ) {
                if ( $option eq "defaults" ) {
                    $option = "adjust_defaults";
                    $messagePart =
                        $input{strength}
                      . $input{cups}
                      . $input{grinder}
                      . $input{hotplate};
                }
                else {
                    $option = "brew_with_settings";
                    $messagePart =
                        $input{cups}
                      . $input{strength}
                      . $input{hotplate}
                      . $input{grinder};

                    UpdateReadings(
                        $hash,
                        sub($) {
                            my ($updateReading) = @_;
                            for my $key ( keys %readingsValues ) {
                                $updateReading->( $key, $readingsValues{$key} );
                            }
                        }
                    );
                }
            }
        }

 # Aborting if option "defaults" was not properly prepared to "adjust_defaults".
        return undef if $option eq "defaults";

    }
    elsif ( $option =~ /^hotplate.*/ ) {
        if ( not defined( $param[0] ) ) {
            $param[0] =
              ( $option ne "hotplate_on_for_minutes"
                  and ReadingsVal( $hash->{NAME}, "hotplate", "" ) ne "off" )
              ? "off"
              : "on";
        }
        $option =
          $param[0] =~ /^(0|no|disable|off).*$/i
          ? "hotplate_off"
          : "hotplate_on_for_minutes";
        $messagePart = $optionToMessage->( $option, $param[0], $param[1] );

    }
    else {
        if ( defined( $param[0] ) ) {

            # Resetting "extra" strength mode when strength is updated.
            delete $hash->{".extra_strength.enabled"}
              if (  $option eq "strength"
                and $param[0] ne "extra"
                and $hash->{".extra_strength.enabled"} );

# Eager updating strength, cups and grinder reading to avoid that widget updates are slower than starting a "brew".
            UpdateReading( $hash, $option, $param[0] )
              if ( $option =~ /^(strength|cups|grinder)$/ );

            # Aborting device update when strength is "extra".
            return undef if ( $option eq "strength" and $param[0] eq "extra" );

# Aborting device update if grinder is not changed (every command sent to the coffee machine flips the grinder setting).
            return undef
              if (  $option eq "grinder"
                and $param[0] eq ReadingsVal( $hash->{NAME}, "grinder", "" ) );
        }

        # Resetting internal states before executing "stop".
        if ( $option eq "stop" and ( $param[0] // "" ) ne "no-reset" ) {
            ResetState($hash);
        }

        $messagePart = $optionToMessage->( $option, $param[0] );
    }

    # Command execution
    if ( defined( $commands{$option} ) ) {
        my $message = $commands{$option};

        # Replacing placeholders with value.
        $message =~ s/#+/$messagePart/
          if ( defined($messagePart) and $messagePart =~ /^[a-f0-9]{2,}$/ );

        if ( $message =~ /.*#.*/ ) {
            return "Option $option: Unsupported params: " . join( " ", @param );
        }
        else {
            $hash->{".last_set_command"} =
              $option . ( int(@param) ? " " . join( " ", @param ) : "" );
            $hash->{"PENDING_COMMAND"} = $hash->{".last_command"} = $message;
            Log3 $hash->{NAME}, 4, "Connection :: Sending message: $message ["
              . $hash->{".last_set_command"} . "]";

            WritePending( $hash, ( $option eq "info" ) );
        }
        return undef;

    }
    elsif ( $option eq "disconnect" or $option eq "reconnect" ) {

        # This option is primarily to test if reconnect works.
        main::DevIo_Disconnected($hash);
        Connect($hash) if ( $option eq "reconnect" );
        return undef;

    }
    elsif ( $option ne "?" and $option ne "help" ) {
        return "Unknown option: $option with params: " . join( " ", @param );
    }

    my @strength = split( ",", "weak,medium,strong,extra" );
    pop(@strength) if ( not IsExtraStrengthModeAvailable($hash) );

    return
        "Unknown argument $option, choose one of" . " brew"
      . " defaults"
      . " reset:noArg"
      . " stop:noArg"
      . " strength:"
      . join( ",", @strength )
      . " cups:slider,1,1,12"
      . " grinder:enabled,disabled"
      . " hotplate"
      . " hotplate_on_for_minutes:slider,5,5,40";
}

sub ResetState($) {
    my ($hash) = @_;

    ResetBrewState($hash);
    ResetExtraStrengthMode($hash);
}

sub Notify($$) {
    my ( $hash, $eventHash ) = @_;
    my $name       = $hash->{NAME};
    my $senderName = $eventHash->{NAME};

# Return without any further action if the module is disabled or the event is not from this module or global.
    return ""
      if ( IsDisabled($name)
        or ( $senderName ne $name and $senderName ne "global" ) );

    if ( my $events = deviceEvents( $eventHash, 1 ) ) {
        if ( $senderName eq "global" ) {
            ReadConfiguration($hash)
              if ( grep( m/^(INITIALIZED|REREADCFG)$/, @{$events} ) );
        }
        else {
            for ( @{$events} ) {
                if ($_) {
                    ProcessBrewStateEvents( $hash, $_ );
                    ProcessEventForExtraStrength( $hash, $_ );
                    LogCommands( $hash, $_ );
                }
            }
        }
    }
}

sub ReadConfiguration($) {
    my ($hash) = @_;

    # Restoring extra strength
    $hash->{".extra_strength.enabled"} = 1
      if ( ReadingsVal( $hash->{NAME}, "strength", "" ) =~ /^extra.*/ );
}

sub LogCommands($$) {
    my ( $hash, $event ) = @_;

    if ( $event =~ /^last_command_success:\s*(yes|no)\s*$/i
        and ( my $command = ReadingsVal( $hash->{NAME}, "last_command", 0 ) ) )
    {
        my $message = ReadingsVal( $hash->{NAME}, "last_command_message", "" );
        if ( $1 eq "yes" ) {
            Log3 $hash->{NAME}, 4,
              "Command :: Success [$command]; Message: $message";
        }
        else {
            Log3 $hash->{NAME}, 3,
              "Command :: Failed [$command]; Cause: $message";
        }
    }
}

sub ProcessBrewStateEvents($$) {
    my ( $hash, $event ) = @_;

# Setting "INITIATED_BREWING" when brewing was initiated by a command (and not by using the machine's buttons)
    if ( $event =~ /^last_command_success:\s*yes\s*$/i
        and ReadingsVal( $hash->{NAME}, "last_command", 0 ) =~ /^brew.*/ )
    {
        $hash->{"INITIATED_BREWING"} = 1;
        $hash->{".brew-state"}       = "brewing";

    }
    elsif ( $event =~ /^state:\s*(brewing|grinding)/ ) {
        $hash->{".brew-state"} = $1;

    }
    elsif ( $event =~ /^state:\s*done/ ) {
        ResetBrewState($hash);

    }
    elsif ( $event =~ /^state:\s*(.+)$/
        and ( $hash->{".brew-state"} // "" ) =~ /^(brewing|grinding)$/ )
    {
        Log3 $hash->{NAME}, 3,
"Found state change from 'brewing' to '$1'. This looks like an abort, resetting all states to initial.";
        ResetState($hash);
    }
}

sub ResetBrewState($) {
    my ($hash) = @_;
    delete $hash->{".brew-state"} if defined( $hash->{".brew-state"} );
    delete $hash->{"INITIATED_BREWING"}
      if defined( $hash->{"INITIATED_BREWING"} );
}

sub ProcessEventForExtraStrength($$) {
    my ( $hash, $event ) = @_;

    if ( $event =~ /^strength:\s*extra\s*$/ ) {

        # Listen to "set strength extra" and enable it if available.
        if ( not( EnableExtraStrengthMode($hash) ) ) {
            Log3 $hash->{NAME}, 3,
              "Extra-Strength :: Downgrading strength 'extra' to 'strong'";
            fhem(   "sleep 0.1 fix-strength ; set "
                  . $hash->{NAME}
                  . " strength strong" );
        }

    }
    elsif ( $event =~ /^state:\s*brewing/ and not $hash->{"INITIATED_BREWING"} )
    {
# Monitor event that brewing was started on the device without grinder and upgrade to 'extra' if configured in attributes.
        if (
            ReadingsVal( $hash->{NAME}, "grinder", "-" ) eq "disabled"
            and ( my $cups = int( ReadingsVal( $hash->{NAME}, "cups", 0 ) ) ) >
            0
            and ( my $strength = ReadingsVal( $hash->{NAME}, "strength", "" ) )
            eq AttrVal(
                $hash->{NAME}, "strength-extra-start-on-device-strength",
                "off"
            )
            and EnableExtraStrengthMode($hash)
          )
        {

            Log3 $hash->{NAME}, 3,
"Extra-Strength :: Upgrading brewing $cups cups started with disabled grinder and strength '$strength' to strength 'extra'.";
            Set( $hash, @{ [ $hash->{NAME}, "stop" ] } );
            Set( $hash, @{ [ $hash->{NAME}, "brew", $cups, "extra" ] } );
        }

    }
    elsif (
        (
               $hash->{".extra_strength.enabled"}
            or $hash->{".extra_strength.phase-2"}
        )
      )
    {
# Listen to "set strength ?" while in extra mode and revert it to extra shortly.
        if ( $event =~ /^strength:\s*([^\s]+)\s*$/ ) {
            fhem(   "sleep 0.1 fix-strength ; set "
                  . $hash->{NAME}
                  . " strength extra" );

        }
        elsif ( $event =~ /^state:\s*done/ ) {

            # Finishing first round (grinding & first brew are done here)
            if (
                (
                    my $delay =
                    int( $hash->{".extra_strength.pre_brew_phase_delay"} // 0 )
                ) > 0
              )
            {
                InternalTimer(
                    gettimeofday() + $delay,
                    "SmarterCoffee::ExtraStrengthHandleBrewing",
                    $hash, 0
                );
            }
            else {
                if (
                    int(
                        $hash->{".extra_strength.original_desired_cups"} // 0
                    ) > 0
                  )
                {
                    Set(
                        $hash,
                        @{
                            [
                                $hash->{NAME}, "cups",
                                $hash->{".extra_strength.original_desired_cups"}
                            ]
                        }
                    );
                }
                ResetExtraStrengthMode($hash);
            }

        }
        elsif ( $event =~ /^state:\s*brewing/
            and not $hash->{".extra_strength.phase-2"} )
        {
       # Entering phase-2: Brewing after initial grinding at different settings.
            $hash->{".extra_strength.phase-2"} =
              ExtraStrengthHandleBrewing($hash);
        }
    }
}

sub ExtraStrengthHandleBrewing($) {
    my ($hash) = @_;
    my @params = (
        ReadingsVal( $hash->{NAME}, "cups",     "-" ),
        ReadingsVal( $hash->{NAME}, "strength", "-" ),
        ReadingsVal(
            $hash->{NAME},
            "hotplate_on_for_minutes",
            (
                ReadingsVal( $hash->{NAME}, "cups_single_mode", "" ) eq "yes"
                ? 0
                : "on"
            )
        ),
        "disabled"
    );

    if ( TranslateParamsForExtraStrength( $hash, \@params, "brew" ) ) {

# Resetting brew state to ensure it doesn't interfere with stop command that runs with "no-reset" option.
        ResetBrewState($hash);

# Stopping brewing after initial grinding (skip stop if we are in phase-2 and came here due to pre-brew delay)
        Set( $hash, @{ [ $hash->{NAME}, "stop", "no-reset" ] } )
          if not $hash->{".extra_strength.phase-2"};

        unshift( @params, "brew" );
        unshift( @params, $hash->{NAME} );

        my $phase =
          int( $hash->{".extra_strength.pre_brew_phase_delay"} // 0 ) > 0
          ? "2 (pre brew)"
          : "2";
        Log3 $hash->{NAME}, 4,
          "Extra-Strength :: Phase $phase [set " . join( " ", @params ) . "]";

        Set( $hash, @params );
        return 1;
    }

    return 0;
}

sub IsExtraStrengthModeAvailable($;$) {
    my ( $hash, $slient ) = @_;

    my $extraPercent = AttrVal( $hash->{NAME}, "strength-extra-percent",
        $strengthExtraDefaultPercent );
    my $preBrew =
      int( AttrVal( $hash->{NAME}, "strength-extra-pre-brew-cups", 1 ) ) *
      int(
        AttrVal( $hash->{NAME}, "strength-extra-pre-brew-delay-seconds", 0 ) );

    if (    $extraPercent > 0
        and ( $extraPercent != 1 or $preBrew > 0 )
        and $extraPercent < 2.5 )
    {
        return 1;
    }
    else {
        Log3 $hash->{NAME}, ( ( $slient // 1 ) ? 5 : 3 ),
"Extra-Strength :: Strength 'extra' is disabled as [strength-extra-percent = $extraPercent] is out of range (0 < x < 2.5)";
        return 0;
    }
}

sub EnableExtraStrengthMode($) {
    my ($hash) = @_;

    return 1 if ( $hash->{".extra_strength.enabled"} );

    if ( IsExtraStrengthModeAvailable( $hash, 0 ) ) {
        Log3 $hash->{NAME}, 4,
          "Extra-Strength :: Entering extra strength mode.";
        $hash->{".extra_strength.enabled"} = 1;
        return 1;
    }
    else {
        return 0;
    }
}

sub ResetExtraStrengthMode($;$) {
    my ( $hash, $partial ) = @_;

    Log3 $hash->{NAME}, 4,
      (     "Extra-Strength :: Resetting state to initial (partial: "
          . ( $partial // 0 )
          . ")." );
    foreach my $key ( keys %{$hash} ) {
        my $resetableKey = ( $key =~ /^\.extra_strength\..+$/
              and $key ne ".extra_strength.enabled" );

        if ( ( $partial // 0 ) and $resetableKey ) {
            $resetableKey = (
                not $key =~
/.+\.(original_desired_cups|desired_cups|pre_brew_phase_delay|phase-2).+$/
            );
        }

        if ($resetableKey) {
            Log3 $hash->{NAME}, 5, "Extra-Strength :: Resetting $key";
            delete $hash->{$key};
        }
    }
}

sub TranslateParamsForExtraStrength($$$) {
    my ( $hash, $params, $phase ) = @_;

    return 0 if ( not( EnableExtraStrengthMode($hash) ) );

    if ( $phase eq "grind" ) {
        my $extraPercent = AttrVal( $hash->{NAME}, "strength-extra-percent",
            $strengthExtraDefaultPercent );

        my @strengths = ( "weak", "medium", "strong" );
        my @weights = split(
            /\s+/,
            AttrVal(
                $hash->{NAME}, "strength-coffee-weights",
                $strengthDefaultWeights
            )
        );
        while ( int(@weights) < 3 ) {
            push( @weights,
                ( int(@weights) ? $weights[ int(@weights) - 1 ] : 4.3 ) );
        }

        Log3 $hash->{NAME}, 4,
            "Extra-Strength :: Reference weights: "
          . join( " ", @weights ) . " ("
          . join( " ", @strengths ) . ")";

        my $desiredCups = $params->[0]
          // ReadingsVal( $hash->{NAME}, "cups", 0 );
        my $maxCups = ReadingsVal( $hash->{NAME}, "cups_max", $desiredCups );
        $desiredCups = $maxCups if ( $desiredCups > $maxCups );

        my %grind = (
            "cups"     => undef,
            "desired"  => $desiredCups,
            "strength" => undef,
            "delta"    => undef,
            "error"    => undef
        );

        while ( $desiredCups > 0 and not defined( $grind{cups} ) ) {
            my $targetWeight = $desiredCups * $weights[2] * $extraPercent;

            for ( my $i = 0 ; $i < int(@weights) ; $i++ ) {
                if ( ( $weights[$i] // -1 ) > 0 and $targetWeight > 0 ) {
                    my $cups = int( $targetWeight / $weights[$i] ) +
                      ( $extraPercent > 1 ? 1 : 0 );
                    my $weight = $cups * $weights[$i];
                    my $delta =
                      ( $targetWeight > $weight
                        ? ( $targetWeight - $weight )
                        : ( $weight - $targetWeight ) );
                    my $error = int(
                        ( 1 - ( ( $targetWeight - $delta ) / $targetWeight ) )
                        * 100 );

                    Log3 $hash->{NAME}, 4,
                        "Extra-Strength :: GC: $cups ("
                      . $strengths[$i]
                      . "), DC: $desiredCups, D: $delta (e:$error%), W: $weight, T: $targetWeight";

                    if (
                        $cups <= $maxCups
                        and ( not defined( $grind{delta} )
                            or $grind{delta} > $delta )
                      )
                    {
                        $grind{desired}  = $desiredCups;
                        $grind{cups}     = $cups;
                        $grind{delta}    = $delta;
                        $grind{strength} = $strengths[$i];
                        $grind{error}    = $error;
                    }
                }
            }

            $desiredCups--;
        }

        if ( defined( $grind{cups} ) ) {
            $hash->{".extra_strength.original_desired_cups"} = $grind{desired};
            $hash->{".extra_strength.desired_cups"}          = $grind{desired};
            $hash->{".extra_strength.error_rate"}            = $grind{error};
            $params->[0]                                     = $grind{cups};
            $params->[1]                                     = $grind{strength};

            return 1;
        }
        else {
            Log3 $hash->{NAME}, 2,
"Extra-Strength :: Failed calculating extra strength (not enough water?). Ordinary coffee strength will be applied.";
        }

    }
    elsif ( $phase eq "brew"
        and defined( $hash->{".extra_strength.desired_cups"} ) )
    {
        my ( $preBrewCups, $preBrewDelay ) = (
            int( AttrVal( $hash->{NAME}, "strength-extra-pre-brew-cups", 1 ) ),
            int(
                AttrVal(
                    $hash->{NAME}, "strength-extra-pre-brew-delay-seconds",
                    0
                )
            )
        );

        if (    $preBrewCups > 0
            and $preBrewDelay > 0
            and $preBrewCups < $hash->{".extra_strength.desired_cups"}
            and not $hash->{".extra_strength.pre_brew_phase_delay"} )
        {

            $hash->{".extra_strength.pre_brew_phase_delay"} = $preBrewDelay;
            $hash->{".extra_strength.desired_cups"} -= $preBrewCups;
            $params->[0] = $preBrewCups;
        }
        else {
            $params->[0] = $hash->{".extra_strength.desired_cups"};
            ResetExtraStrengthMode( $hash, 1 );
        }

        return 1;
    }

    return 0;
}

sub UpdateReading($$$) {
    my ( $hash, $name, $value ) = @_;
    UpdateReadings( $hash, sub($) { ( $_[0] )->( $name, $value ) } );
}

sub UpdateReadings($$;$) {
    my ( $hash, $callback, $forceUpdate ) = @_;

    $forceUpdate = (
        ( $forceUpdate // 0 )
          or
          defined( AttrVal( $hash->{NAME}, "event-on-update-reading", undef ) )
          or
          defined( AttrVal( $hash->{NAME}, "event-on-change-reading", undef ) )
    );

    my $updated = 0;
    my $updater = sub {
        my ( $name, $value ) = @_;
        return if not( defined($name) and defined($value) );

        my $changed =
          ReadingsVal( $hash->{NAME}, $name, "##undefined" ) ne $value;
        if ( $changed or $forceUpdate ) {
            readingsBulkUpdate( $hash, $name, $value );
            $updated = 1 if ($changed);
        }

        $updated = 1
          if ( $name eq "state"
            and ReadingsVal( $name, 'state', 'none' ) ne $value );
    };

    readingsBeginUpdate($hash);
    $callback->($updater);
    readingsEndUpdate( $hash, ( $updated or $forceUpdate ) );
}

sub RunDiscoveryProcess($;$) {
    my ( $hash, $skipConnect ) = @_;

    if ( Discover($hash) and not $skipConnect ) {
        Connect($hash);
    }

    InternalTimer(
        gettimeofday() + $discoveryInterval,
        "SmarterCoffee::RunDiscoveryProcess",
        $hash, 0
    );
}

sub InetSocketAddressString($) {
    my ( $sport, $inetAddress ) = sockaddr_in( $_[0] );
    return inet_ntoa($inetAddress) . ":$sport";
}

sub Discover($) {
    my ($hash) = @_;

    my $existingDeviceName = ( $hash->{DeviceName} // "" );
    my $broadcastAddress = sockaddr_in( $port, INADDR_BROADCAST );

    Log3 $hash->{NAME}, 4,
        "Discovery :: Broadcasting discovery request to "
      . InetSocketAddressString($broadcastAddress)
      . " (already discovered: $existingDeviceName)";

    socket( my $socket, AF_INET, SOCK_DGRAM, getprotobyname('udp') );
    setsockopt( $socket, SOL_SOCKET, SO_BROADCAST, 1 );
    send( $socket, 'd~', 0, $broadcastAddress );
    my $wait = IO::Select->new($socket);

    while ( $wait->can_read(10) ) {
        my $deviceAddress = recv( $socket, my $message, 128, 0 );
        my $inetSocketAddress = InetSocketAddressString($deviceAddress);

        $message = unpack( 'H*', $message );

        Log3 $hash->{NAME}, 4,
          "Discovery :: Received message $message from $inetSocketAddress";

        if ( $message =~ /^65.*7e.*/ and ParseMessage( $hash, $message ) ) {
            my ( $sport, $inetAddress ) = sockaddr_in($deviceAddress);

            if ( my ($hostname) = gethostbyaddr( $inetAddress, AF_INET ) ) {
                $hash->{DeviceName} = $hostname . ":$sport";
            }
            else {
                $hash->{DeviceName} = $inetSocketAddress;
            }

            if ( $existingDeviceName ne $hash->{DeviceName} ) {
                Log3 $hash->{NAME}, 3,
"Discovery :: Discovered smarter coffee machine (message=$message): "
                  . $hash->{DeviceName};
            }

            last;
        }
    }

    close $socket;

    if ( !defined( $hash->{DeviceName} ) ) {
        my $recommendation =
          "Recommendation: Specify <IP address or hostname> in fhem config at: "
          . "'define "
          . $hash->{NAME}
          . " SmarterCoffee <IP address or hostname>' or check network / coffee machine.";
        Log3 $hash->{NAME}, 2,
"Discovery :: Failed discovering smarter coffee machine. $recommendation";
        return 0;
    }
    else {
        return $existingDeviceName ne $hash->{DeviceName};
    }
}

## -------------------------------------------------------------------------------------------------------------------
## The following section deals with displaying dev state (it is completely optional with regards to the functionality)

my $SmarterCoffee_StatusIconSVG = <<XML;
<svg class="icon" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewbox="0,0,340,300">
    <g id="Layer1" name="water-level-25" opacity="1">
        <path id="shapePath1" d="M10.7664,202.592 L39.25,202.592 L39.25,251.046 L10.7664,251.046 L10.7664,202.592 Z"
              style="stroke:#000000;stroke-opacity:1;stroke-width:0;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill-rule:evenodd;fill:#000000;fill-opacity:0.501961;"/>
    </g>
    <g id="Layer2" name="water-level-50" opacity="1">
        <path id="shapePath2" d="M10.7664,148.916 L39.25,148.916 L39.25,251.046 L10.7664,251.046 L10.7664,148.916 Z"
              style="stroke:#000000;stroke-opacity:1;stroke-width:0;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill-rule:evenodd;fill:#000000;fill-opacity:0.501961;"/>
    </g>
    <g id="Layer3" name="water-level-100" opacity="1">
        <path id="shapePath3" d="M10.7664,72.7703 L39.25,72.7703 L39.25,251.046 L10.7664,251.046 L10.7664,72.7703 Z"
              style="stroke:#000000;stroke-opacity:1;stroke-width:0;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill-rule:evenodd;fill:#000000;fill-opacity:0.501961;"/>
    </g>
    <g id="Layer4" name="coffee-level" opacity="1">
        <path id="shapePath4"
              d="M105.839,186.865 C110.989,185.046 119.097,178.364 126.436,179.589 C135.267,181.064 134.469,186.36 143.482,186.592 C151.348,186.796 156.278,181.403 164.079,180.563 C173.196,179.579 180.365,188.579 189.536,189.158 C196.588,189.602 208.142,183.427 215.216,183.427 C224.061,183.427 226.257,189.158 235.103,189.158 C241.477,189.158 248.419,184.86 252.858,183.427 "
              style="stroke:#000000;stroke-opacity:0.776471;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath5" d="M119.439,200.823 L121.792,200.823 C127.621,198.887 129.259,210.763 130.009,202.074 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath6" d="M164.019,197.487 C166.354,198.01 171.011,196.425 171.832,198.321 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath7" d="M221.007,204.159 C223.591,204.456 227.478,203.571 229.28,204.576 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath8" d="M210.437,222.922 L221.467,222.922 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath9" d="M230.659,241.269 C226.311,241.752 216.061,240.957 216.411,238.35 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath10" d="M120.358,235.432 C123.681,235.753 128.403,234.804 130.928,235.849 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath11" d="M158.963,226.548 L170.913,226.548 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath12" d="M192.513,232.513 Z"
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath13" d="M200.326,196.236 C202.87,195.729 207.125,195.933 208.139,196.236 "
              style="stroke:#000000;stroke-opacity:0.509804;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
    </g>
    <g id="Layer5" name="machine" opacity="1">
        <path id="shapePath14"
              d="M10.7795,288.06 L309.337,288.06 L309.337,287.83 L63.516,287.83 L63.516,38.3877 L277.337,38.3877 L291.337,10.509 L10.7795,10.509 "
              style="stroke:#000000;stroke-opacity:1;stroke-width:13.5;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath15"
              d="M10.1377,84.2715 C10.1377,75.9847 16.8555,69.2668 25.1423,69.2668 L25.7807,69.2668 C34.0675,69.2668 40.7853,75.9847 40.7853,84.2715 L40.1469,239.658 C40.1469,247.944 33.4291,254.663 25.1423,254.663 L24.504,254.663 C16.2172,254.663 9.4994,247.944 9.4994,239.658 L10.1377,84.2715 Z"
              style="stroke:#000000;stroke-opacity:1;stroke-width:8;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
    </g>
    <g id="Layer6" name="carafe" opacity="1">
        <path id="shapePath16"
              d="M82.5,70.5 L281.5,70.5 L332.5,230.122 L305.207,230.122 L270.5,122.968 L253.5,122.967 L253.5,252.5 L106.5,252.5 L106.5,122.968 L82.5,70.5 Z"
              style="stroke:#000000;stroke-opacity:1;stroke-width:11;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
    </g>
    <g id="Layer7" name="heating" opacity="1">
        <path id="shapePath17" d="M154.14,171.887 C116.542,221.403 178.086,221.403 144.759,270.919 "
              style="stroke:#000000;stroke-opacity:0.823529;stroke-width:20.5;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath18" d="M188.668,171.887 C151.071,221.403 212.613,221.403 179.286,270.919 "
              style="stroke:#000000;stroke-opacity:0.823529;stroke-width:20.5;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath19" d="M221.858,171.887 C184.261,221.403 245.803,221.403 212.476,270.919 "
              style="stroke:#000000;stroke-opacity:0.823529;stroke-width:20.5;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
    </g>
    <g id="Layer8" name="brewing" opacity="1">
        <path id="shapePath20" d="M183.349,41.4504 L183.349,135.501 "
              style="stroke:#000000;stroke-opacity:1;stroke-width:16;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;stroke-dasharray:48,32;fill:none;"/>
    </g>
    <g id="Layer9" name="ready" opacity="1">
        <path id="shapePath21" d="M310.567,47.2444 L210.027,187.123 L166,146 "
              style="stroke:#000000;stroke-opacity:1;stroke-width:23;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
    </g>
    <g id="Layer10" name="no-water" opacity="0">
        <path id="shapePath22"
              d="M122.5,155 C122.5,113.855 155.855,80.5 197,80.5 C238.145,80.5 271.5,113.855 271.5,155 C271.5,196.145 238.145,229.5 197,229.5 C155.855,229.5 122.5,196.145 122.5,155 Z"
              style="stroke:#000000;stroke-opacity:0.47451;stroke-width:20;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath23" d="M147.412,195.101 C147.412,195.101 247.103,114.482 247.103,114.482 "
              style="stroke:#000000;stroke-opacity:0.47451;stroke-width:20;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
        <path id="shapePath24"
              d="M196.525,98.5 L201.136,118.997 C204.122,137.531 227.896,146 227.896,172.094 C227.896,221.827 165.155,221.227 165.155,172.094 C165.155,145.791 187.942,137.596 192.007,118.997 L196.525,98.5 Z"
              style="stroke:#000000;stroke-opacity:1;stroke-width:15;stroke-linejoin:miter;stroke-miterlimit:2;stroke-linecap:round;fill:none;"/>
    </g>
</svg>
XML

sub GetDevStateIcon {
    my ( $name, $colors ) = @_;

    my ( $state, $icon ) = ( Value($name), $SmarterCoffee_StatusIconSVG );

    my $noWater = ( ReadingsVal( $name, "water", "none" ) eq "none"
          and $state eq "maintenance" );
    my $waterLevel = ReadingsVal( $name, "water_level", "0" );

    $state = "brewing" if ( $state eq "grinding" );

    $icon =~ s/(name="ready" opacity)="1"/$1="0"/g   if $state ne "ready";
    $icon =~ s/(name="brewing" opacity)="1"/$1="0"/g if $state ne "brewing";
    $icon =~ s/(name="coffee-level" opacity)="1"/$1="0"/g
      if ( $state ne "brewing" and $state ne "done" );
    $icon =~ s/(name="(carafe|coffee-level)" opacity)="1"/$1="0"/g
      if ( ReadingsVal( $name, "carafe", "present" ) ne "present" or $noWater );
    $icon =~ s/(name="heating" opacity)="1"/$1="0"/g
      if ReadingsVal( $name, "hotplate", "off" ) ne "on";

    $icon =~ s/(name="water-level.*" opacity)="1"/$1="0"/g;
    $icon =~ s/(name="water-level-$waterLevel" opacity)="0"/$1="1"/;
    $icon =~ s/(name="no-water" opacity)="0"/$1="1"/ if $noWater;

    # Adjusting the icon color
    my @stateColors = split( /\s+/, ( $colors // "" ) );
    for ( my $i = 0 ; $i < int(@stateColors) ; $i++ ) {
        $stateColors[$i] = undef if ( $stateColors[$i] =~ /^[^#a-z0].*/i );
    }

    my %cm = (
        "default" => ( $stateColors[0] // "#7b7b7b" ),
        "ready"   => ( $stateColors[1] // "green" ),
        "brewing" => ( $stateColors[2] // "chocolate" ),
        "done"    => ( $stateColors[3] // "#336699" ),
    );

    if ( my $stateColor = ( $cm{$state} ? $cm{$state} : $cm{default} ) ) {
        $icon =~ s/(stroke|fill):#000000/$1:$stateColor/g;
    }

    # Removing any CR/LF to avoid wrapping in <pre> tags
    $icon =~ s/[\r\n]//g;

    return $icon;
}

## -------------------------------------------------------------------------------------------------------------------
## Documentation follows

1;

=pod
=item device
=item summary Controls a Wi-Fi Smarter Coffee machine via network connection
=begin html

<a name="SmarterCoffee"></a>
<h3>SmarterCoffee</h3>
<ul>
    Integrates the equally called Wi-Fi coffee machine (<code>http://smarter.am/</code>) with FHEM.
    <br><br>
    <i>Prerequisite</i>:<br>
    Make sure the machine can be controlled by the smarter mobile app when both are connected to the same network as fhem.<br>
    If in doubt check the official documentation or official support forum to get help with integrating the coffee machine into your network.
</ul>
<br>

<a name="SmarterCoffeedefine"></a>
<b>Define</b>
<ul>
    <code>define &lt;name&gt; SmarterCoffee (&lt;hostname&gt;)</code>
    <br><br>
    Hostname is optional, if omitted the name is auto-detected via UDP broadcast.
    <br><br>
    Examples:<ul>
    <li><code>define coffee-machine SmarterCoffee</code><br>
        Connects with the first coffee machine that answers the UDP broadcast.</li><br>
    <li><code>define coffee-machine SmarterCoffee smarter-coffee.fritz.box</code><br>
        Connects with the coffee machine at address 'smarter-coffee.fritz.box'.</li><br>
    <li><code>define coffee-machine SmarterCoffee 192.168.2.56:2081</code><br>
        Connects with the coffee machine at '192.168.2.56' using port 2081 (= default)</li>
    </ul>
</ul>
<br>

<a name="SmarterCoffeereadings"></a>
<b>Readings</b><br>
<ul>
    <li>
        <code>state</code><br>
        Device state, can be one of:<ul>
            <li><code>disconnected</code>: No connection to coffee machine.</li>
            <li><code>opened / connected</code>: Intermediate states after connection has been established but before the machine's state is known.</li>
            <li><code>invalid</code>: The connected device is not a coffee machine.</li>
            <li><code>ready</code>: Ready to start brewing.</li>
            <li><code>grinding</code>: Grinding coffee.</li>
            <li><code>brewing</code>: Brewing coffee.</li>
            <li><code>done</code>: Done brewing.</li>
            <li><code>heating</code>: Keeping coffee warm or reheating.</li>
            <li><code>maintenance</code>: Maintenance is needed to get ready for brewing (e.g. water or carafe is missing).</li>
        </ul>
    </li><br>
    <li>
        <code>hotplate_on_for_minutes</code><br>
        Shows the number of minutes that the hotplate will be on when it was turned on via "<code>set &lt;name&gt; hotplate</code>"
        or "<code>set &lt;name&gt; brew</code>".</li><br>
    <li>
        <code>carafe</code><br>
        One of "<code>present</code>" or "<code>missing</code>" as the carafe is detected as being present or not.<br>
        (<code>state</code> <code>ready</code> turns to <code>maintenance</code> when carafe is missing and <code>carafe_required</code> is <code>yes</code>)</li><br>
    <li>
        <code>carafe_required</code><br>
        Is "<code>yes</code>" or "<code>no</code>" as the carafe is required to start brewing or not.<br>
        This option can be configured via the smarter mobile app. Read disclaimer before turning off carafe detection.</li><br>
    <li>
        <code>cups_max</code><br>
        The estimated maximum brewable cups when taking current water level into account.</li><br>
    <li>
        <code>cups_single_mode</code><br>
        Is "<code>yes</code>" or "<code>no</code>" as the single cup mode is active or not.<br>
        This option can be configured via the smarter mobile app.
        When enabled "<code>set &lt;name&gt; brew</code>" will not enable the hotplate and "<code>cups_max</code>" is limited to <code>3</code>.
        In single cup mode, cups [1,2,3] is used for one [small,medium,large] cup.</li><br>
    <li>
        <code>water</code> and <code>water_level</code><br>
        Is [<code>none, low, half, full</code>] and [<code>0, 25, 50, 100</code>] indicating the amount of water that remains in the tank.<br>
        (<code>state</code> <code>ready</code> turns to <code>maintenance</code> when <code>water_level</code> is "<code>0</code>")</li><br>
    <li>
        <code>last_command.*</code><br>
        Is updated with the last executed <code>set</code> or <code>get</code> command string, including device response and success information.</li><br>
    <li>
        Further readings match <code>set</code> commands and reflect the corresponding machine state. See <i>Set</i> section below.</li><br>
</ul>

<a name="SmarterCoffeeget"></a>
<b>Get</b><br>
<ul>
    <li>
        <code>get &lt;name&gt; info</code><br>
        Retrieves firmware &amp; device type information and updates internals.</li><br>
    <li>
        <code>get &lt;name&gt; carafe_required_status</code><br>
        Retrieves whether carafe is required for brewing and updates reading "carafe_required".</li><br>
    <li>
        <code>get &lt;name&gt; cups_single_mode_status</code><br>
        Retrieves whether single cup mode is active and updates reading "cups_single_mode".</li><br>
    <li>
        <code>get &lt;name&gt; get_defaults</code><br>
        Retrieves and applies previously set machine defaults. Triggers the event "defaults" after retrieval but before applying them.</li><br>
</ul>

<a name="SmarterCoffeeset"></a>
<b>Set</b><br>
<ul>
    <li>
        <code>set &lt;name&gt; brew</code><br>
        Start brewing with settings displayed in readings and "<code>default-hotplate-on-for-minutes</code>" for hotplate.</li>
    <li>
        <code>set &lt;name&gt; brew current</code><br>
        Start brewing with current machine settings.</li>
    <li>
        <code>set &lt;name&gt; brew [1 - 12] ([weak, medium, strong, extra]) ([5-40]) ([enabled, disabled])</code><br>
        Start brewing the specified amount of cups at optionally specified strength, hotplate and grinder with non-specified settings used from readings
        and "<code>default-hotplate-on-for-minutes</code>" for hotplate.
        <p></p>
        E.g. "<code>set &lt;name&gt; brew 5 medium</code>" brews 5 cups of medium coffee reusing current hotplate and grinder settings.</li><br>
    <li>
        <code>set &lt;name&gt; defaults ([1 - 12]) ([weak, medium, strong]) ([5-40]) ([enabled, disabled])</code><br>
        Sets the machine defaults to the current settings optionally overridden by specified amount of cups, strength, hotplate and grinder.
        Non-specified settings are used from readings and "<code>default-hotplate-on-for-minutes</code>" for hotplate.<br>
        Note: Machine defaults are applied by the coffee machine after every brew and when stopping or turning off.
        Readings are updated accordingly when defaults are applied.
        <p></p>
        E.g. "<code>set &lt;name&gt; defaults 5 medium</code>" sets defaults to 5 cups of medium coffee and reuses current hotplate and grinder settings
        as future defaults.</li><br>
    <li>
        <code>set &lt;name&gt; stop</code><br>
        Stop brewing and disable hotplate if on.</li><br>
    <li>
        <code>set &lt;name&gt; strength [weak, medium, strong, extra]</code><br>
        Toggles the strength via the amount of coffee beans to use per cup when grinding.
        <p></p>
        The strength "<code>extra</code>" is special in that it is not natively supported by the machine itself.
        To brew coffee with "extra" strength a custom sequence similar to the following is started:<br>
        <code>set &lt;name&gt; brew &lt;cups + 1&gt; strong on enabled ;; sleep &lt;cups * 1.5&gt; ;; set &lt;name&gt; stop ;; set &lt;name&gt; brew &lt;cups&gt; on disabled</code>.<br>
        See also attributes "<code>strength-extra-percent</code>" and "<code>strength-coffee-weights</code>" which control the calculation
        of actual strength and cup counts.</li><br>
    <li>
        <code>set &lt;name&gt; grinder [enabled, disabled]</code><br>
        Toggles whether grinder is used when brewing coffee.
        Ground coffee has to be added manually to the filter and strength settings are ignored when grinder is disabled.</li><br>
    <li>
        <code>set &lt;name&gt; cups [1 - 12]</code><br>
        Toggles the amount of cups (~100ml) to brew.</li><br>
    <li>
        <code>set &lt;name&gt; [1 - 12]-cups</code><br>
        Is an alias to "<code>set &lt;name&gt; brew [1 - 12]</code>".
        This adds support for web commands like "8-cups" and "3-cups,strong".</li><br>
    <li>
        <code>set &lt;name&gt; hotplate &lt;command&gt;</code><br>
        Toggles the hotplate that keeps the coffee warm after brewing.
        <br><br>
        &lt;command&gt; is one of:<ul>
            <li><code>on</code><br>On for "<code>default-hotplate-on-for-minutes</code>" minutes (defaults to 15 minutes)</li>
            <li><code>on [5 - 40]</code><br>On for the specified amount of minutes</li>
            <li><code>off</code></li>
        </ul>
    </li><br>
    <li>
        <code>set &lt;name&gt; hotplate_on_for_minutes [5 - 40]</code><br>
        Is an alias to "<code>set &lt;name&gt; hotplate on [5 - 40]</code>".</li><br>
    <li>
        <code>set &lt;name&gt; reconnect</code><br>
        Disconnects, optionally runs discovery (if hostname or address was omitted in the device definition) and reconnects.</li><br>
    <li>
        <code>set &lt;name&gt; reset</code><br>
        Resets machine to factory default, excluding WLAN settings.</li><br>
</ul>

<a name="SmarterCoffeeattr"></a>
<b>Attributes</b><br>
<ul>
    <li>
        <code>attr &lt;name&gt; devStateIcon { SmarterCoffee::GetDevStateIcon($name) }</code>
        <br><br>
        The function <code>SmarterCoffee::GetDevStateIcon($name[, "...colors..."])</code> renders a custom dev state icon that displays
        the machine states (ready, brewing, done) and shows information on carafe, hotplate and water level.
        <br><br>
        The icon is monochrome using a default color that may change to highlight states: ready, brewing, done.
        Built-in colors can be adjusted with the second parameter of <code>SmarterCoffee::GetDevStateIcon</code>.<br>
        E.g. using "<code>attr &lt;name&gt; devStateIcon { SmarterCoffee::GetDevStateIcon($name, '#7b7b7b green chocolate #336699' }</code>"
        sets colors for default, ready, brewing and done.
        <br><br>
        Colors are specified as HTML color values delimited by whitespace using a fixed order of "default ready brewing done".
        Use '-' or '0' to substitute a color with the built-in or the default color within the color sequence. E.g. a color sequence of 'blue - 0 0' uses
        blue for all states except "ready" which uses the built-in color green.</li><br>
    <li>
        <code>attr &lt;name&gt; default-hotplate-on-for-minutes 15</code><br>
        Defines how long the hotplate is heating coffee when turning it on without specifying a time or when brewing coffee without
        specifying a valid time value for hotplate.<br>
        Values of 15, 5 or 40 minutes are used as this attribute is not specified, invalid or greater than 40 (5 <= x <= 40, with x defaulting to 15).
        <br><br>
        In addition to a fixed value, the hotplate can also be turned on relative to the number of cups that are brewed.
        E.g. setting a value of "<code>15 5=20 10=35</code>" means: 15 from 1 to 4 cups, 20 from 5 cups and 35 from 10 cups.</li><br>
    <li>
        <code>attr &lt;name&gt; ignore-max-cups [1, 0]</code><br>
        Toggles whether the reading "<code>cups_max</code>" influences the state "<code>ready</code>".
        By default "<code>attr &lt;name&gt; ignore-max-cups 1</code>" is assumed which means that the state "<code>ready</code>" is not
        related to "<code>cups_max</code>" if this attribute is not set. Set this attribute to "0" if the state should turn to "<code>maintenance</code>"
        when the selected cup count is larger than "<code>cups_max</code>".</li><br>
    <li>
        <code>attr &lt;name&gt; set-on-brews-coffee [0, 1]</code><br>
        Toggles whether the command "<code>set &lt;name&gt; on</code>" is an alias to "<code>set &lt;name&gt; brew</code>".
        By default this is disabled to avoid accidental coffee brewing.</li><br>
    <li>
        <code>attr &lt;name&gt; strength-extra-percent 1.4</code><br>
        Specifies the percentage of coffee to use relative to strength "<code>strong</code>" when brewing coffee with <code>extra</code> strength.
        A value of "<code>1.4</code>" brews coffee that is 140% the strength of "<code>strong</code>" respectively "<code>0.6</code>" brews coffee that
        is 60% the strength. Setting <code>strength-extra-percent</code> to <code>0</code> disables support for extra strength.
        <br><br>
        Note: Brewing coffee with <code>extra</code> strength uses strengths and cup counts natively supported by the machine and the configured percentage
        is likely not matched exactly.
        Best results are achieved with 4 - 8 cups and a full water tank as it allows to use most variations to get close to the target.</li><br>
    <li>
        <code>attr &lt;name&gt; strength-extra-pre-brew-delay-seconds 0</code><br>
        Specifies a delay in seconds when brewing coffee with extra strength which is used to split the brewing operation in a pre-brew
        and the normal brew phase. The pre-brew phase brews a small amount of cups (usually 1) and pauses for a couple of seconds
        before continuing with the rest of the cups.
        This mode can help to overcome limitations with grounds being too coarse to provide good taste at standard brewing speed.
        Specifying 0 disables "pre-brew".
        </li><br>
    <li>
        <code>attr &lt;name&gt; strength-extra-pre-brew-cups 1</code><br>
        Specifies the number of cups that are brewed first before delaying brewing in extra mode. Specifying 0 disables "pre-brew".
        </li><br>
    <li>
        <code>attr &lt;name&gt; strength-extra-start-on-device-strength [off, weak, medium, strong]</code><br>
        Specifies a strength level that maps to strength 'extra' when starting brewing without grinder using the buttons at the coffee machine.
        By default this option is set to "<code>off</code>" which means that strength 'extra' can only be used when starting brewing via FHEM.
        <br>
        E.g. a value of "<code>weak</code>" allows to brew coffee with extra strength by pressing the start button at the coffee machine
        with strength set to "weak" and grinder set to "disabled" (= "Filter" in the display).
        <br><br>
        Note: Brewing started from FHEM is never affected by this setting.
        </li><br>
    <li>
        <code>attr &lt;name&gt; strength-coffee-weights 3.5 3.9 4.3</code><br>
        Is the amount of coffee that the grinder produces per cup depending on the selected strength. This setting does not control the amount it only
        tells the module what the grinder will produce. Changing the default values is therefore only required if the coffee machine produces
        different results on the actually used beans.<br>
        The amounts are specified in grams per strength <code>[weak, medium, strong]</code> using whitespace as delimiter.
        <br><br>
        The purpose of this metric is to calculate the actual <code>strength</code> and <code>cups</code> to use when grinding coffee with
        <code>extra</code> strength. E.g. for 140% extra strength, 4 cups require <tt style="white-space: nowrap">(4 * 4.3 * 1.4) = 24.08</tt>
        gramms of coffee. In this example the closest match is grinding 7 cups with weak strength which produces <code>(7 * 3.5) = 24.5</code> gramms.
        The actual brewing is then performed with 4 cups as originally requested.
        <br><br>
        The algorithm tries to find the closest matching cup counts and strength value towards the target amount of coffee required for
        <code>extra</code> strength. It is technically not possible to control the amount of coffee directly, therefore the grams specified for the
        different strengths are used select between natively supported strengths <code>weak, medium, strong</code> that match the desired target the closest.
        Water level is also taken into account as cup count is truncated by the coffee machine when grinding, depending on the amount of available water.
        Decisions may vary depending on cups and available water, keep water level at maximum to get best results.
        <br><br>
        Note: SCAE (Speciality Coffee Association of Europe) recommends ~6 gramms of coffee per cup. To come close, 140% is the default value for
        <code>extra</code> strength assuming that the default values for <code>strength-coffee-weights</code> apply to the used coffee beans.
        As the density of coffee beans differs these defaults may be inappropriate. To get better results with a certain kind of beans it may make
        sense to measure the actual produced weights and adjust the values (<code>strength-coffee-weights</code> and <code>strength-extra-percent</code>)
        accordingly.
        </li><br>
</ul>

=end html

=cut

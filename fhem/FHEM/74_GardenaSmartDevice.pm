###############################################################################
#
# Developed with VSCodium and richterger perl plugin.
#
#  (c) 2017-2022 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Michael (mbrak)       Thanks for Commandref
#       - Christian (zife)      Thanks for Commandref
#       - Matthias (Kenneth)    Thanks for Wiki entry
#       - BioS                  Thanks for predefined start points Code
#       - fettgu                Thanks for Debugging Irrigation Control data flow
#       - Sebastian (BOFH)      Thanks for new Auth Code after API Change
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
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#
###### Wichtige Notizen
#
#   apt-get install libio-socket-ssl-perl
#   http://www.dxsdata.com/de/2016/07/php-class-for-gardena-smart-system-api/
#
##
##

## unserer packagename
package FHEM::GardenaSmartDevice;
use GPUtils qw(GP_Import GP_Export);

use strict;
use warnings;
use POSIX;
use FHEM::Meta;
use Time::Local;
use Time::Piece;
use Time::Seconds;

use SetExtensions;

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
} or do {

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
    } or do {

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        } or do {

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            } or do {

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                } or do {

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                };
            };
        };
    };
};

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
          Log3
          CommandAttr
          AttrVal
          ReadingsVal
          readingFnAttributes
          AssignIoPort
          modules
          IOWrite
          defs
          makeDeviceName
          SetExtensions)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
    )
);

sub Initialize {
    my $hash = shift;

    $hash->{Match} = '^{"id":".*';

    $hash->{SetFn}   = \&Set;
    $hash->{DefFn}   = \&Define;
    $hash->{UndefFn} = \&Undef;
    $hash->{ParseFn} = \&Parse;

    $hash->{AttrFn} = \&Attr;
    $hash->{AttrList} =
        "readingValueLanguage:de,en "
      . "model:watering_computer,sensor,sensor2,mower,ic24,power,electronic_pressure_pump "
      . "extendedState:0,1 "
      . "IODev "
      . $readingFnAttributes;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define {
    my $hash = shift // return;
    my $aArg = shift // return;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return
      "too few parameters: define <NAME> GardenaSmartDevice <device_Id> <model>"
      if ( scalar( @{$aArg} ) < 3 );

    my $name     = $aArg->[0];
    my $deviceId = $aArg->[2];
    my $category = $aArg->[3];

    $hash->{DEVICEID}                = $deviceId;
    $hash->{VERSION}                 = version->parse($VERSION)->normal;
    $hash->{helper}{STARTINGPOINTID} = '';
    $hash->{helper}{schedules_paused_until_id} = '';
    $hash->{helper}{eco_mode_id}               = '';
    $hash->{helper}{button_config_time_id}     = '';
    $hash->{helper}{winter_mode_id}            = '';

    # Electroni Pressure Pump
    $hash->{helper}{operating_mode_id}    = '';
    $hash->{helper}{leakage_detection_id} = '';
    $hash->{helper}{turn_on_pressure_id}  = '';

    $hash->{helper}{_id} = '';

    # IrrigationControl valve control max 6
    $hash->{helper}{schedules_paused_until_1_id} = '';
    $hash->{helper}{schedules_paused_until_2_id} = '';
    $hash->{helper}{schedules_paused_until_3_id} = '';
    $hash->{helper}{schedules_paused_until_4_id} = '';
    $hash->{helper}{schedules_paused_until_5_id} = '';
    $hash->{helper}{schedules_paused_until_6_id} = '';

    CommandAttr( undef,
        "$name IODev $modules{GardenaSmartBridge}{defptr}{BRIDGE}->{NAME}" )
      if ( AttrVal( $name, 'IODev', 'none' ) eq 'none' );

    my $iodev = AttrVal( $name, 'IODev', 'none' );

    AssignIoPort( $hash, $iodev ) if ( !$hash->{IODev} );

    if ( defined( $hash->{IODev}->{NAME} ) ) {
        Log3 $name, 3, "GardenaSmartDevice ($name) - I/O device is "
          . $hash->{IODev}->{NAME};
    }
    else {
        Log3 $name, 1, "GardenaSmartDevice ($name) - no I/O device";
    }

    $iodev = $hash->{IODev}->{NAME};

    my $d = $modules{GardenaSmartDevice}{defptr}{$deviceId};

    return
"GardenaSmartDevice device $name on GardenaSmartBridge $iodev already defined."
      if ( defined($d)
        && $d->{IODev} == $hash->{IODev}
        && $d->{NAME} ne $name );

    CommandAttr( undef, $name . ' room GardenaSmart' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    CommandAttr( undef, $name . ' model ' . $category )
      if ( AttrVal( $name, 'model', 'none' ) eq 'none' );

    Log3 $name, 3,
"GardenaSmartDevice ($name) - defined GardenaSmartDevice with DEVICEID: $deviceId";
    readingsSingleUpdate( $hash, 'state', 'initialized', 1 );

    $modules{GardenaSmartDevice}{defptr}{$deviceId} = $hash;

    return;
}

sub Undef {
    my $hash = shift;
    my $arg  = shift;

    my $name     = $hash->{NAME};
    my $deviceId = $hash->{DEVICEID};

    delete $modules{GardenaSmartDevice}{defptr}{$deviceId};

    return;
}

sub Attr {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    return;
}

sub Set {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg;
    my $cmd  = shift @$aArg
      // return qq{"set $name" needs at least one argument};

    my $payload;
    my $abilities;
    my $service_id;
    my $mainboard_version =
      ReadingsVal( $name, 'mower_type-mainboard_version', 0.0 );

    my (
        $Sekunden, $Minuten,   $Stunden,   $Monatstag, $Monat,
        $Jahr,     $Wochentag, $Jahrestag, $Sommerzeit
    ) = localtime(time);

    my $timezone_offset = $Sommerzeit ? 0 : ( Time::Piece->new )->tzoffset;

    #set default abilitie ... overwrite in cmd to change
    $abilities = 'mower'
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'mower' );
    $abilities = 'watering'
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'ic24'
        || AttrVal( $name, 'model', 'unknown' ) eq 'watering_computer' );
    $abilities = 'power'
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'power' );
    $abilities = 'watering'
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'electronic_pressure_pump' );

    ### mower
    # service_id (eco, parkuntilfurhternotice, startpoints)
    if ( lc $cmd eq 'parkuntilfurthernotice' ) {
        $payload = '"name":"park_until_further_notice"';
        if ( $mainboard_version > 10.30 ) {
            $payload =
' "settings":{"name":"schedules_paused_until","value":"2038-01-18T00:00:00.000Z","device":"'
              . $hash->{DEVICEID} . '"}';
            $abilities  = 'mower_settings';
            $service_id = $hash->{helper}{schedules_paused_until_id};
        }
    }
    elsif ( lc $cmd eq 'parkuntilnexttimer' ) {
        $payload = '"name":"park_until_next_timer"';
        if ( $mainboard_version > 10.30 ) {
            $payload   = '"properties":{"name":"mower_timer","value":0}';
            $abilities = 'mower_timer';
        }
    }
    elsif ( lc $cmd eq 'startresumeschedule' ) {
        $payload = '"name":"start_resume_schedule"';
        if ( $mainboard_version > 10.30 ) {
            $payload =
' "settings":{"name":"schedules_paused_until","value":"","device":"'
              . $hash->{DEVICEID} . '"}';
            $abilities  = 'mower_settings';
            $service_id = $hash->{helper}{schedules_paused_until_id};
        }
    }
    elsif ( lc $cmd eq 'startoverridetimer' ) {
        $payload = '"name":"start_override_timer","parameters":{"duration":'
          . $aArg->[0] * 60 . '}';
        if ( $mainboard_version > 10.30 ) {
            $payload = '"properties":{"name":"mower_timer","value":'
              . $aArg->[0] * 60 . '}';
            $abilities = 'mower_timer';
        }

    }
    elsif ( lc $cmd eq 'startpoint' ) {
        my $err;
        ( $err, $payload, $abilities ) =
          SetPredefinedStartPoints( $hash, $aArg );
        $service_id = $hash->{helper}{STARTINGPOINTID};
        return $err if ( defined($err) );
    }
    elsif ( lc $cmd eq 'eco' ) {
        $payload =
            '"settings": {"name": "eco_mode", "value": '
          . $aArg->[0]
          . ', "device": "'
          . $hash->{DEVICEID} . '"}';
        $abilities  = 'mower_settings' if ( $mainboard_version > 10.30 );
        $service_id = $hash->{helper}{eco_mode_id};

#$abilities['service_id'] = $hash->{helper}{SCHEDULESID}  if ( $mainboard_version > 10.30 );
    }
    ### electronic_pressure_pump
    # elsif ( lc $cmd eq 'pumptimer' ) {
    #     $payload =
    #       '"name":"pump_manual_watering_timer","parameters":{"duration":'
    #       . $aArg->[0] . '}';
    # }
    ### watering_computer & electronic pump
    elsif ( lc $cmd eq 'manualoverride' ) {
        $payload =
            '"properties":{"name":"watering_timer_1'
          . '","value":{"state":"manual","duration":'
          . $aArg->[0] * 60
          . ',"valve_id":1}}';
    }
    elsif ( lc $cmd eq 'manualbuttontime' ) {
        $service_id = $hash->{helper}{button_config_time_id};
        $payload =
            '"properties":{"name":"button_config_time",'
          . '"value":'
          . $aArg->[0] * 60
          . ',"timestamp":"2021-05-26T19:06:23.680Z"'
          . ',"at_bound":null,"unit":"seconds","ability":"'
          . $service_id . '"}';
        $abilities = 'watering_button_config';
    }
    elsif ( $cmd =~ m{\AcancelOverride}xms ) {

        my $valve_id = 1;

        if ( $cmd =~ m{\AcancelOverrideValve(\d)\z}xms ) {
            $valve_id = $1;
        }

        $payload =
            '"properties":{"name":"watering_timer_'
          . $valve_id
          . '","value":{"state":"idle","duration":'
          . 0
          . ',"valve_id":'
          . $valve_id . '}}';
    }
    elsif ( $cmd =~ /.*Schedule$/ ) {
        my $duration = (
            (
                defined( $aArg->[0] )
                ? (
                    (
                        ( Time::Piece->new ) +
                          ( ONE_HOUR * $aArg->[0] ) -
                          $timezone_offset
                    )->datetime
                  )
                  . '.000Z'
                : '2038-01-18T00:00:00.000Z'
            )
        );

        $abilities  = 'wateringcomputer_settings';
        $service_id = $hash->{helper}->{'schedules_paused_until_id'};
        $payload =
            '"settings":{"name":"schedules_paused_until"'
          . ', "value":"'
          . ( $cmd eq 'resumeSchedule' ? '' : $duration )
          . '","device":"'
          . $hash->{DEVICEID} . '"}';
    }
    elsif ( lc $cmd eq 'on' || lc $cmd eq 'off' || lc $cmd eq 'on-for-timer' ) {
        my $val = (
            scalar( !@$aArg == 0 ) && ref($aArg) eq 'ARRAY'
            ? $aArg->[0] * 60
            : lc $cmd
        );

        $payload =
          '"properties":{"name":"power_timer", "value":"' . $val . '"}';
    }
    ### Watering ic24
    elsif ( $cmd =~ m{\AmanualDurationValve\d\z}xms ) {
        my $valve_id;

        if ( $cmd =~ m{\AmanualDurationValve(\d)\z}xms ) {
            $valve_id = $1;
        }

        $payload =
            '"properties":{"name":"watering_timer_'
          . $valve_id
          . '","value":{"state":"manual","duration":'
          . $aArg->[0] * 60
          . ',"valve_id":'
          . $valve_id . '}}';
    }
    elsif ( $cmd eq 'closeAllValves' ) {
        $payload = '"name":"close_all_valves","parameters":{}';
    }
    elsif ( $cmd =~ /.*ScheduleValve$/ ) {
        my $valve_id = $aArg->[0];
        my $duration = (
            (
                defined( $aArg->[1] )
                ? (
                    (
                        ( Time::Piece->new ) +
                          ( ONE_HOUR * $aArg->[1] ) -
                          $timezone_offset
                    )->datetime
                  )
                  . '.000Z'
                : '2038-01-18T00:00:00.000Z'
            )
        );

        $abilities = 'irrigation_settings';
        $service_id =
          $hash->{helper}->{ 'schedules_paused_until_' . $valve_id . '_id' };
        $payload =
            '"settings":{"name":"schedules_paused_until_'
          . $valve_id
          . '", "value":"'
          . ( $cmd eq 'resumeScheduleValve' ? '' : $duration )
          . '","device":"'
          . $hash->{DEVICEID} . '"}';
    }
    ### Watering_pressure_pump
    elsif ( lc $cmd eq 'operating_mode' ) {
        my $op_mode = $aArg->[0];
        $payload =
            '"settings":{"name":"operating_mode",'
          . '"value":"'
          . $op_mode . '",'
          . '"device":"'
          . $hash->{DEVICEID} . '"}';
        $abilities  = 'watering_pressure_pump_settings';
        $service_id = $hash->{helper}->{'operating_mode_id'};
    }
    elsif ( lc $cmd eq 'leakage_detection' ) {
        my $leakdetection_mode = $aArg->[0];
        $payload =
            '"settings":{"name":"leakage_detection",'
          . '"value":"'
          . $leakdetection_mode . '",'
          . '"device":"'
          . $hash->{DEVICEID} . '"}';
        $abilities  = 'watering_pressure_pump_settings';
        $service_id = $hash->{helper}->{'leakage_detection_id'};
    }
    elsif ( lc $cmd eq 'turn_on_pressure' ) {
        my $turnonpressure = $aArg->[0];
        $payload =
            '"settings":{"name":"turn_on_pressure",'
          . '"value":"'
          . $turnonpressure . '",'
          . '"device":"'
          . $hash->{DEVICEID} . '"}';
        $abilities  = 'watering_pressure_pump_settings';
        $service_id = $hash->{helper}->{'turn_on_pressure_id'};
    }
    elsif ( lc $cmd eq 'resetvalveerrors' ) {
        $payload   = '"name":"reset_valve_errors",' . ' "parameters": {}';
        $abilities = 'error';
    }

    ### Sensors
    elsif ( lc $cmd eq 'refresh' ) {

        my $sensname = $aArg->[0];
        if ( lc $sensname eq 'temperature' ) {
            if ( ReadingsVal( $name, 'device_info-category', 'sensor' ) eq
                'sensor' )
            {
                $payload   = '"name":"measure_ambient_temperature"';
                $abilities = 'ambient_temperature';
            }
            else {
                $payload   = '"name":"measure_soil_temperature"';
                $abilities = 'soil_temperature';
            }
        }
        elsif ( lc $sensname eq 'light' ) {
            $payload   = '"name":"measure_light"';
            $abilities = 'light';

        }
        elsif ( lc $sensname eq 'humidity' ) {
            $payload   = '"name":"measure_soil_humidity"';
            $abilities = 'humidity';
        }
    }
    ## winter sleep
    elsif ( lc $cmd eq 'winter_mode' ) {
        $payload =
            '"settings":{"name":"winter_mode","value":"'
          . $aArg->[0]
          . '","device":"'
          . $hash->{DEVICEID} . '"}';
        $abilities  = 'winter_settings';
        $service_id = $hash->{helper}->{'winter_mode_id'};
    }

    else {

        my $list = '';

        $list .=
'parkUntilFurtherNotice:noArg parkUntilNextTimer:noArg startResumeSchedule:noArg startOverrideTimer:slider,0,1,240 startpoint'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'mower' );

        $list .=
'manualOverride:slider,1,1,59 cancelOverride:noArg resumeSchedule:noArg stopSchedule manualButtonTime:slider,0,2,100 resetValveErrors:noArg'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'watering_computer' );

        $list .=
'manualOverride:slider,1,1,90 cancelOverride:noArg operating_mode:automatic,scheduled leakage_detection:watering,washing_machine,domestic_water_supply,off turn_on_pressure:slider,2,0.2,3.0,1 resetValveErrors:noArg'
          if ( AttrVal( $name, 'model', 'unknown' ) eq
            'electronic_pressure_pump' );

        $list .=
'closeAllValves:noArg resetValveErrors:noArg stopScheduleValve:select,'
          . ReadingsVal( $name, 'ic24-valves_connected', '1' )
          . ' resumeScheduleValve:select,'
          . ReadingsVal( $name, 'ic24-valves_connected', '1' )
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'ic24' );

        foreach my $valve (
            split( ',', ReadingsVal( $name, 'ic24-valves_connected', '1' ) ) )
        {
            $list .= ' manualDurationValve' . $valve . ':slider,1,1,90 '
              if ( AttrVal( $name, 'model', 'unknown' ) eq 'ic24' );
        }

        foreach my $valve (
            split( ',', ReadingsVal( $name, 'ic24-valves_connected', '1' ) ) )
        {
            $list .= ' cancelOverrideValve' . $valve . ':noArg '
              if ( AttrVal( $name, 'model', 'unknown' ) eq 'ic24' );
        }

        $list .= 'refresh:temperature,humidity'
          if ( AttrVal( $name, 'model', 'unknown' ) =~ /sensor.?/ );

        # add light for old sensors
        $list .= ',light'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'sensor'
            && ReadingsVal( $name, 'device_info-category', 'unknown' ) eq
            'sensor' );

        $list .= 'on:noArg off:noArg on-for-timer:slider,0,1,720'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'power' );

        # all devices has abilitie to fall a sleep
        $list .= ' winter_mode:awake,hibernate';
        return SetExtensions( $hash, $list, $name, $cmd, @$aArg );

        # return "Unknown argument $cmd, choose one of $list";
    }

    $hash->{helper}{deviceAction} = $payload;
    readingsSingleUpdate( $hash, "state", "send command to gardena cloud", 1 );

    IOWrite( $hash, $payload, $hash->{DEVICEID}, $abilities, $service_id );
    Log3 $name, 4,
"GardenaSmartBridge ($name) - IOWrite: $payload $hash->{DEVICEID} $abilities IODevHash=$hash->{IODev}";

    return;
}

sub Parse {
    my $io_hash = shift;
    my $json    = shift;

    my $name = $io_hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3 $name, 3,
          "GardenaSmartDevice ($name) - JSON error while request: $@";
    }

    Log3 $name, 4, "GardenaSmartDevice ($name) - ParseFn was called";
    Log3 $name, 4, "GardenaSmartDevice ($name) - JSON: $json";

    if ( defined( $decode_json->{id} ) ) {

        my $deviceId = $decode_json->{id};

        if ( my $hash = $modules{GardenaSmartDevice}{defptr}{$deviceId} ) {
            my $name = $hash->{NAME};

            WriteReadings( $hash, $decode_json );
            Log3 $name, 4,
              "GardenaSmartDevice ($name) - find logical device: $hash->{NAME}";

            return $hash->{NAME};

        }
        else {

            Log3 $name, 3,
                "GardenaSmartDevice ($name) - autocreate new device "
              . makeDeviceName( $decode_json->{name} )
              . " with deviceId $decode_json->{id}, model $decode_json->{category}";
            return
                "UNDEFINED "
              . makeDeviceName( $decode_json->{name} )
              . " GardenaSmartDevice $decode_json->{id} $decode_json->{category}";
        }
    }

    return;
}

sub WriteReadings {
    my $hash        = shift;
    my $decode_json = shift;

    my $name             = $hash->{NAME};
    my $abilities        = scalar( @{ $decode_json->{abilities} } );
    my $settings         = scalar( @{ $decode_json->{settings} } );
    my $scheduled_events = scalar( @{ $decode_json->{scheduled_events} } );

    readingsBeginUpdate($hash);

    do {

        if (
            ref( $decode_json->{abilities}[$abilities]{properties} ) eq "ARRAY"
            && scalar( @{ $decode_json->{abilities}[$abilities]{properties} } )
            > 0 )
        {
            for my $propertie (
                @{ $decode_json->{abilities}[$abilities]{properties} } )
            {
                if (
                    exists( $decode_json->{abilities}[$abilities]{name} )
                    && ( $decode_json->{abilities}[$abilities]{name} eq
                        'watering' )
                  )
                {

                    if ( $propertie->{name} eq 'button_config_time' ) {
                        if ( $hash->{helper}{ $propertie->{name} . '_id' } ne
                            $decode_json->{abilities}[$abilities]{id} )
                        {
                            $hash->{helper}{ $propertie->{name} . '_id' } =
                              $decode_json->{abilities}[$abilities]{id};
                        }
                        readingsBulkUpdateIfChanged(
                            $hash,
                            'manualButtonTime',
                            (
                                RigReadingsValue(
                                    $hash, $propertie->{value} / 60
                                )
                            )
                        );
                        next;
                    }
                }

                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name},
                    ( defined( $propertie->{value} ) eq '' )
                    ? RigReadingsValue( $hash, 'n/a' )
                    : ""
                      . RigReadingsValue( $hash,
                        $propertie->{value} )  # cast all data to string with ""
                  )
                  if ( exists( $propertie->{value} )
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'radio-quality'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'battery-level'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'internal_temperature-temperature'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'ambient_temperature-temperature'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'soil_temperature-temperature'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'humidity-humidity'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'light-light'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'ic24-valves_connected'
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} ne 'ic24-valves_master_config'
                    && ref( $propertie->{value} ) ne "HASH" );

                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name},
                    ""
                      . RigReadingsValue( $hash,
                        $propertie->{value} )  # cast all data to string with ""
                  )
                  if (
                    defined( $propertie->{value} )
                    && (  $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq 'radio-quality'
                        || $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq 'battery-level'
                        || $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq
                        'internal_temperature-temperature'
                        || $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq
                        'ambient_temperature-temperature'
                        || $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq 'soil_temperature-temperature'
                        || $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq 'humidity-humidity'
                        || $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq 'light-light' )
                  );

                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name}
                      . '_timestamp',
                    ""
                      . Time::Piece->strptime(
                        RigReadingsValue( $hash, $propertie->{timestamp} ),
                        "%Y-%m-%d %H:%M:%S" )->strftime('%s')

                  )
                  if (
                    defined( $propertie->{value} )
                    && (  $decode_json->{abilities}[$abilities]{name} . '-'
                        . $propertie->{name} eq 'mower_timer-mower_timer' )
                  );

                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name},
                    join( ',', @{ $propertie->{value} } )
                  )
                  if ( defined( $propertie->{value} )
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} eq 'ic24-valves_connected' );

                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name},
                    join( ',', @{ $propertie->{value} } )
                  )
                  if ( defined( $propertie->{value} )
                    && $decode_json->{abilities}[$abilities]{name} . '-'
                    . $propertie->{name} eq 'ic24-valves_master_config' );

                if ( ref( $propertie->{value} ) eq "HASH" ) {
                    my $sub_state = 0;
                    my $sub_value = 0;
                    while ( my ( $r, $v ) = each %{ $propertie->{value} } ) {
                        if ( ref($v) ne "HASH" ) {
                            readingsBulkUpdateIfChanged(
                                $hash,
                                $decode_json->{abilities}[$abilities]{name}
                                  . '-'
                                  . $propertie->{name} . '_'
                                  . $r,
                                RigReadingsValue( $hash, $v )
                            );
                        }
                        else {
                            while ( my ( $i_r, $i_v ) = each %{$v} ) {
                                readingsBulkUpdateIfChanged(
                                    $hash,
                                    $decode_json->{abilities}[$abilities]{name}
                                      . '-'
                                      . $propertie->{name} . '_'
                                      . $r . '_'
                                      . $i_r,
                                    RigReadingsValue( $hash, $i_v )
                                );
                            }
                        }
                    }
                }

                # ic24 and other watering devices calc irrigation left in sec
                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name}
                      . '_irrigation_left',
                    ( $propertie->{value}{duration} > 0 )
                    ? (
                        Time::Piece::localtime->strptime(
                            RigReadingsValue( $hash, $propertie->{timestamp} ),
                            "%Y-%m-%d %H:%M:%S"
                          ) +
                          ( $propertie->{value}{duration} + 3 ) -
                          Time::Piece::localtime->new
                      )
                    : 0
                  )
                  if ( defined( $propertie->{value} )
                    && $decode_json->{abilities}[$abilities]{name} eq
                    'watering' );
            }
        }

        $abilities--;
    } while ( $abilities >= 0 );

    if (
        exists( $decode_json->{scheduled_events} )

        #  && scalar ($decode_json->{scheduled_events} ) > 0
        && ref( $decode_json->{scheduled_events} ) eq 'ARRAY'
        && AttrVal( $name, 'model', 'unknown' ) !~ /sensor.?/
      )
    {
        readingsBulkUpdateIfChanged(
            $hash,
            'scheduling-schedules_events_count',
            scalar( @{ $decode_json->{scheduled_events} } )
        );
        my $valve_id = 1;
        my $event_id = 0;    # ic24 [1..6] | wc, pump [1]

        ##
        # validiere schedules
        my @soll    = ();
        my @ist     = ();
        my @tmp_ist = ();
        for my $cloud_schedules ( @{ $decode_json->{scheduled_events} } ) {
            while ( my ( $r, $v ) = each %{$cloud_schedules} ) {
                push @soll, $v if $r eq 'id';    # cloud hat  SOLL
            }
        }

        foreach my $dev_schedules ( sort keys %{ $hash->{READINGS} } ) {
            my $dev_reading = ReadingsVal( $name, $dev_schedules, "error" );
            push @ist, $dev_reading
              if $dev_schedules =~ /schedule.*\d_id/;    # push reading _id
            push @ist, $1
              if $dev_schedules =~
              /schedule.*_(\d)_id/;    # push readigs d from x_id

            Log3 $name, 5,
              "[DEBUG] $name - Schedule - Key ist : $dev_schedules ";
            Log3 $name, 5, "[DEBUG] $name - Schedule - ID FOUND $dev_reading"
              if $dev_schedules =~ /schedule.*_\d_id/;    # cloud hat  SOLL
        }

   #Log3 $name, 5, "[DEBUG] Cloud:".Dumper(@soll) . "- Internal:". Dumper(@ist);

        ## delete only if cloud != (ist/2)
        if (
            (
                   scalar(@soll) != scalar( @ist / 2 )
                && scalar(@soll) > 0
                && scalar(@ist) > 0
            )
            || ( scalar(@ist) eq 2 && scalar(@soll) eq 1 )
          )
        {
            @tmp_ist = @ist;
            while ( my $element = shift(@soll) ) {
                my $schedule_step_int = 0;

                foreach my $sist (@tmp_ist) {
                    my $step = scalar(@tmp_ist) > 1 ? 2 : 1;
                    if ( $element eq $sist ) {
                        splice( @ist, $schedule_step_int, $step )
                          ;    # more than 2 items del them, otherwise 1
                    }
                    $schedule_step_int += $step;
                }
            }
        }

        #Log3 $name, 5, "[DEBUG] $name - Schedule - Rest  ". Dumper(@ist);
        # delete only if count soll != count ist. cos the will be overwritten
        if (   scalar(@ist) > 0
            && scalar(@soll) != scalar( @ist / 2 ) )
        {
            while ( my $old_schedule_id = shift(@ist) ) {
                if ( length($old_schedule_id) == 1 ) {
                    foreach ( keys %{ $hash->{READINGS} } ) {
                        delete $hash->{READINGS}->{$_}
                          if ( $_ =~
                            /scheduling-schedules_event_$old_schedule_id.*/ );
                    }
                }    # fi
                Log3 $name, 5,
"[DEBUG] - $name : deletereading scheduling-schedules_event_$old_schedule_id.*"
                  if length($old_schedule_id) == 1;
            }
        }
        #### /validiere schedules

        for my $event_schedules ( @{ $decode_json->{scheduled_events} } ) {
            $valve_id = $event_schedules->{valve_id}
              if ( exists( $event_schedules->{valve_id} ) );    #ic24
            $event_id++;                                        # event id

            while ( my ( $r, $v ) = each %{$event_schedules} ) {
                readingsBulkUpdateIfChanged(
                    $hash, 'scheduling-schedules_event_' . $event_id

#. ( ReadingsVal($name,'error-valve_error_1_valve_id','') ne '' ? "_valve_$valve_id" : '')
                      . '_'
                      . $r,
                    $v
                ) if ( ref($v) ne 'HASH' );
                readingsBulkUpdateIfChanged(
                    $hash, 'scheduling-schedules_event_' . $event_id

#. ( ReadingsVal($name,'error-valve_error_1_valve_id','') ne '' ? "_valve_$valve_id" : '')
                      . '_'
                      . $v->{type},
                    join( ',', @{ $v->{weekdays} } )
                ) if ( ref($v) eq 'HASH' );
            }
        }

    }
    ;    # fi scheduled_events

    my $winter_mode = 'awake';

    do {
#Log3 $name, 1, "Settings pro Device : ".$decode_json->{settings}[$settings]{name};
#Log3 $name, 1, " - KEIN ARRAY" if ( ref( $decode_json->{settings}[$settings]{value} ) ne "ARRAY");
#Log3 $name, 1, " - IST ARRAY" if ( ref( $decode_json->{settings}[$settings]{value} ) eq "ARRAY");

        if (
            exists( $decode_json->{settings}[$settings]{name} )
            && ( $decode_json->{settings}[$settings]{name} =~
                   /schedules_paused_until_?\d?$/
                || $decode_json->{settings}[$settings]{name} eq 'eco_mode'
                || $decode_json->{settings}[$settings]{name} eq 'winter_mode'
                || $decode_json->{settings}[$settings]{name} eq 'operating_mode'
                || $decode_json->{settings}[$settings]{name} eq
                'leakage_detection'
                || $decode_json->{settings}[$settings]{name} eq
                'turn_on_pressure' )
          )
        {
            if ( $hash->{helper}
                { $decode_json->{settings}[$settings]{name} . '_id' } ne
                $decode_json->{settings}[$settings]{id} )
            {
                $hash->{helper}
                  { $decode_json->{settings}[$settings]{name} . '_id' } =
                  $decode_json->{settings}[$settings]{id};
            }

            # check watering controler single schedules pause until
            if ( $decode_json->{settings}[$settings]{name} eq
                'schedules_paused_until' )
            {
                readingsBulkUpdateIfChanged(
                    $hash,
                    'scheduling-schedules_paused_until',
                    $decode_json->{settings}[$settings]{value}
                );
            }
            #####
            #ic24 schedules pause until
            if ( $decode_json->{settings}[$settings]{name} =~
                /schedules_paused_until_?(\d)?$/ )
            {
 #my $ventil = substr($decode_json->{settings}[$settings]{name}, -1); # => 1 - 6
 # check if empty, clear scheduling-scheduled_watering_next_start_x
                readingsBulkUpdateIfChanged(
                    $hash,
                    'scheduling-' . $decode_json->{settings}[$settings]{name},
                    $decode_json->{settings}[$settings]{value}
                );

# CommandAttr( undef, $name . " scheduling-scheduled_watering_next_start_")  if ($decode_json->{settings}[$settings]{value} eq '' )
            }

            #TODO: Readings und Setter ?!
            # save electronid pressure pump settings as readings
            if (   $decode_json->{settings}[$settings]{name} eq 'operating_mode'
                || $decode_json->{settings}[$settings]{name} eq
                'leakage_detection'
                || $decode_json->{settings}[$settings]{name} eq
                'turn_on_pressure' )
            {
                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{settings}[$settings]{name},
                    $decode_json->{settings}[$settings]{value}
                );

            }

            # save winter mode as reading
            if ( $decode_json->{settings}[$settings]{name} eq 'winter_mode' ) {
                readingsBulkUpdateIfChanged( $hash, 'winter_mode',
                    $decode_json->{settings}[$settings]{value} );

                $winter_mode = $decode_json->{settings}[$settings]{value};
            }
        }

        if (   defined( $decode_json->{settings}[$settings]{name} )
            && $decode_json->{settings}[$settings]{name} eq 'valve_names'
            && ref( $decode_json->{settings}[$settings]{value} ) eq "ARRAY" )
        {    # or HASH ?
            my @valves = @{ $decode_json->{settings}[$settings]{value} };
            foreach my $valve (@valves) {

      #Log3 $name, 4,  "GardenaSmartDevice ($name) valve_name $valve->{'name'}";
                readingsBulkUpdateIfChanged( $hash,
                    'valve-valve_name_' . $valve->{"id"},
                    $valve->{"name"} );
            }
        }

        if ( ref( $decode_json->{settings}[$settings]{value} ) eq "ARRAY"
            && $decode_json->{settings}[$settings]{name} eq 'starting_points' )
        {
            #save the startingpointid needed to update the startingpoints
            if ( $hash->{helper}{STARTINGPOINTID} ne
                $decode_json->{settings}[$settings]{id} )
            {
                $hash->{helper}{STARTINGPOINTID} =
                  $decode_json->{settings}[$settings]{id};
            }

            $hash->{helper}{STARTINGPOINTS} =
              '{ "name": "starting_points", "value": '
              . encode_json( $decode_json->{settings}[$settings]{value} ) . '}';
            my $startpoint_cnt = 0;

            for my $startingpoint (
                @{ $decode_json->{settings}[$settings]{value} } )
            {
                $startpoint_cnt++;
                readingsBulkUpdateIfChanged(
                    $hash,
                    'startpoint-' . $startpoint_cnt . '-enabled',
                    $startingpoint->{enabled}
                );
            }
        }

        $settings--;
    } while ( $settings >= 0 );

    if ( $winter_mode ne 'hibernate' ) {
        setState($hash);
    }
    else {
        readingsBulkUpdate( $hash, 'state',
            RigReadingsValue( $hash, 'hibernate' ) );
    }

    readingsEndUpdate( $hash, 1 );

    Log3 $name, 4, "GardenaSmartDevice ($name) - readings was written";

    return;
}

sub setState {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $online_state =
      ReadingsVal( $name, 'device_info-connection_status', 'unknown' );

    #online state mower
    readingsBulkUpdate( $hash, 'state',
        $online_state eq 'online'
        ? ReadingsVal( $name, 'mower-status', 'readingsValError' )
        : 'offline' )
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'mower' );

    # ic24 / wc / electronic pump

    if (   AttrVal( $name, 'model', 'unknown' ) eq 'ic24'
        || AttrVal( $name, 'model', 'unknown' ) eq 'watering_computer'
        || AttrVal( $name, 'model', 'unknown' ) eq 'electronic_pressure_pump' )
    {
        my @opened_valves;
        my $state_string      = '';
        my $nearst_irrigation = '2999-12-12 12:00';
        my $has_schedule      = 0;
        my $longest_duration  = 0;
        my $processed_item    = '';
        my $error_type        = 'ok';
        my @valves_connected =
          AttrVal( $name, 'model', 'unknown' ) eq 'ic24'
          ? split( ',', ReadingsVal( $name, 'ic24-valves_connected', '' ) )
          : '1';

        $has_schedule = 1
          if ( ReadingsVal( $name, 'scheduling-schedules_events_count', '' ) ne
            '' );
        for (@valves_connected) {    # valves 1 or 1..6
            ## add to opened ventils, if watering active
            push @opened_valves,
              $_
              if (
                (
                    (
                        ReadingsVal( $name,
                            "watering-watering_timer_" . $_ . "_duration", 0 )
                        =~ m{\A[1-9]([0-9]+)?\z}xms
                    ) ? $_ : 0
                ) > 0
              );
            ## set error type (pumpe required)
            $error_type =
              ReadingsVal( $name, 'error-valve_error_' . $_ . '_type', 'error' )
              if (
                ReadingsVal( $name, 'error-valve_error_' . $_ . '_type',
                    'error' ) ne 'ok'
              );
            ## find longest irrigation duration
            $longest_duration =
              ReadingsVal( $name,
                "watering-watering_timer_" . $_ . "_irrigation_left", 0 )
              if (
                (
                    ReadingsVal( $name,
                        "watering-watering_timer_" . $_ . "_duration", 0 ) =~
                    m{\A[1-9]([0-9]+)?\z}xms
                    && ReadingsVal( $name,
                        "watering-watering_timer_" . $_ . "_duration", 0 ) > 0
                    && ReadingsVal( $name,
                        "watering-watering_timer_" . $_ . "_duration", 0 ) >
                    $longest_duration
                )
              );

            # y-m-d h:m
            $processed_item =
              AttrVal( $name, 'model', 'unknown' ) eq 'ic24'
              ? RigReadingsValue(
                $hash,
                ReadingsVal(
                    $name, 'scheduling-schedules_paused_until_' . $_, ''
                )
              )
              : RigReadingsValue( $hash,
                ReadingsVal( $name, 'scheduling-schedules_paused_until', '' ) );

            Log3 $name, 5, "[DEBUG] - process: $processed_item";
            Log3 $name, 5,
              "[DEBUG] - next_start: "
              . ReadingsVal( $name, 'scheduling-scheduled_watering_next_start',
                '' );    # n/a  RigReadingsValue( $hash, 'n/a')
             # $nearst_irrigation = RigReadingsValue($hash, ReadingsVal($name, 'scheduling-schedules_paused_until_'.$_, ''))
            if (
                ReadingsVal( $name, 'scheduling-scheduled_watering_next_start',
                    '' ) eq RigReadingsValue( $hash, 'n/a' )
              )
            { # non next start, schedules paused permanently or next schedule > 1 year; get nearst paused_until
                Log3 $name, 5, "[DEBUG] - next_start: empty ";
                Log3 $name, 5,
                  "[DEBUG] - empty pro item "
                  . Time::Piece->strptime( $processed_item,
                    "%Y-%m-%d %H:%M:%S" );
                Log3 $name, 5,
                  "[DEBUG] - empty nearst "
                  . Time::Piece->strptime( $nearst_irrigation,
                    "%Y-%m-%d %H:%M:%S" );
                $nearst_irrigation = $processed_item
                  if (
                    Time::Piece->strptime( $processed_item,
                        "%Y-%m-%d %H:%M:%S" ) <
                    Time::Piece->strptime( $nearst_irrigation,
                        "%Y-%m-%d %H:%M:%S" )
                    && $has_schedule
                    && Time::Piece->strptime( $processed_item,
                        "%Y-%m-%d %H:%M:%S" ) > Time::Piece->new
                  );
            }
            else {
                $nearst_irrigation = ReadingsVal( $name,
                    'scheduling-scheduled_watering_next_start', '' );
            }
            Log3 $name, 5, "[DEBUG] - choosed nearst: $nearst_irrigation";

        }    # for
             # override state 4 extendedstates
        if ( AttrVal( $name, "extendedState", 0 ) == 1 ) {
            if ( scalar(@opened_valves) > 0 ) {
                ## valve 1 will be ir.. 23 minutes remaining
                for (@valves_connected) {
                    $state_string .= sprintf(
                        RigReadingsValue( $hash, 'valve' ) . ' '
                          . $_ . ' '
                          . (
                            RigReadingsValue( $hash,
                                'watering. %.f minutes left' )
                              . '</br>'
                          ),
                        (
                            ReadingsVal( $name,
                                'watering-watering_timer_' . $_ . '_duration',
                                0 ) / 60
                        )
                    );
                }    # /for
            }
            else {
                $state_string .= RigReadingsValue( $hash, 'closed' );
            }
            $state_string .=
              ($has_schedule)
              ? sprintf(
                RigReadingsValue( $hash, 'next watering: %s' ),
                RigReadingsValue(
                    $hash,
                    ReadingsVal(
                        $name, 'scheduling-scheduled_watering_next_start', ''
                    )
                )
              )
              : sprintf(
                RigReadingsValue( $hash, 'paused until %s' ),
                $nearst_irrigation
              );

            #TODO: Write state format for ventil 1-@valces_connected  -> map ?
            CommandAttr(
                undef, $name . ' stateFormat 
              {

              }
            '
            ) if ( AttrVal( $name, 'stateFormat', 'none' ) eq 'none' );
        }
        else {
            Log3 $name, 5,
                "[DEBUG] - Offene Ventile :"
              . scalar(@opened_valves)
              . " laengste bewaesserung: $longest_duration . hat Zeitplan: $has_schedule Naechster Zeitplan: $nearst_irrigation";
            $state_string = scalar(@opened_valves) > 0

              # offen
              ? sprintf(
                ( RigReadingsValue( $hash, 'watering. %.f minutes left' ) ),
                $longest_duration / 60
              )

              # zu
              : (    $has_schedule
                  && $nearst_irrigation ne '2999-12-12 12:00' )

# zeitplan aktiv
# ? ( $nearst_irrigation eq '2038-01-18 00:00')   sprintf( RigReadingsValue($hash, 'paused until %s') , $nearst_irrigation)
              ? (    $nearst_irrigation eq RigReadingsValue( $hash, 'n/a' )
                  || $nearst_irrigation =~ '2038-01-18.*' )

              # dauerhaft pausiert
                  ? sprintf(
                      (
                          RigReadingsValue( $hash, 'closed' ) . '. '
                            . RigReadingsValue(
                              $hash, 'schedule permanently paused'
                            )
                      )
                  )

                  # naechster zeutplan
                  : (
                      ReadingsVal( $name,
                          'scheduling-scheduled_watering_next_start', '' ) eq
                        RigReadingsValue( $hash, 'n/a' )
                  ) ? sprintf(
                      RigReadingsValue( $hash, 'paused until %s' ),
                      $nearst_irrigation
                  )
                : sprintf(
                      (
                              RigReadingsValue( $hash, 'closed' ) . '. '
                            . RigReadingsValue( $hash, 'next watering: %s' )
                      ),
                      $nearst_irrigation
                )

                  # zeitplan pausiert
              : RigReadingsValue( $hash, 'closed' );

            # state offline | override
            $state_string = 'offline' if ( $online_state eq 'offline' );
            $state_string =
              ( $error_type ne 'ok' ) ? $error_type : $state_string;

        }
        readingsBulkUpdate( $hash, 'state',
            RigReadingsValue( $hash, $state_string ) );
    }

    # Sensor / Sensor 2
    if ( AttrVal( $name, 'model', 'unknown' ) =~ /sensor.?/ ) {
        my $state_string =
          ( ReadingsVal( $name, 'device_info-category', 'unknown' ) eq
              'sensor' )
          ? 'T: '
          . ReadingsVal( $name, 'ambient_temperature-temperature',
            'readingsValError' )
          . '°C, '
          : 'T: '
          . ReadingsVal( $name, 'soil_temperature-temperature',
            'readingsValError' )
          . '°C, ';
        $state_string .= 'H: '
          . ReadingsVal( $name, 'humidity-humidity', 'readingsValError' ) . '%';
        $state_string .= ', L: '
          . ReadingsVal( $name, 'light-light', 'readingsValError' ) . 'lux'
          if ( ReadingsVal( $name, 'device_info-category', 'unknown' ) eq
            'sensor' );

        #online state sensor I II
        readingsBulkUpdate( $hash, 'state',
            $online_state eq 'online'
            ? RigReadingsValue( $hash, $state_string )
            : RigReadingsValue( $hash, 'offline' ) );
    }

    readingsBulkUpdate( $hash, 'state',
        ReadingsVal( $name, 'power-power_timer', 'no info from power-timer' ) )
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'power' );

    return;
}

##################################
##################################
#### my little helpers ###########

sub ReadingLangGerman {
    my $hash         = shift;
    my $readingValue = shift;

    my $name           = $hash->{NAME};
    my %langGermanMapp = (
        'ok_cutting'           => 'mähen',
        'paused'               => 'pausiert',
        'ok_searching'         => 'suche Ladestation',
        'ok_charging'          => 'lädt',
        'ok_leaving'           => 'unterwegs zum Startpunkt',
        'wait_updating'        => 'wird aktualisiert ...',
        'wait_power_up'        => 'wird eingeschaltet ...',
        'parked_timer'         => 'geparkt nach Zeitplan',
        'parked_park_selected' => 'geparkt',
        'off_disabled'         => 'der Mäher ist ausgeschaltet',
        'off_hatch_open'       =>
          'deaktiviert. Abdeckung ist offen oder PIN-Code erforderlich',
        'unknown'           => 'unbekannter Status',
        'error'             => 'Fehler',
        'error_at_power_up' => 'Neustart ...',
        'off_hatch_closed'  => 'Deaktiviert. Manueller Start erforderlich',
        'ok_cutting_timer_overridden'    => 'manuelles mähen',
        'parked_autotimer'               => 'geparkt durch SensorControl',
        'parked_daily_limit_reached'     => 'abgeschlossen',
        'no_message'                     => 'kein Fehler',
        'outside_working_area'           => 'außerhalb des Arbeitsbereichs',
        'no_loop_signal'                 => 'kein Schleifensignal',
        'wrong_loop_signal'              => 'falsches Schleifensignal',
        'loop_sensor_problem_front'      => 'Problem Schleifensensor, vorne',
        'loop_sensor_problem_rear'       => 'Problem Schleifensensor, hinten',
        'trapped'                        => 'eingeschlossen',
        'upside_down'                    => 'steht auf dem Kopf',
        'low_battery'                    => 'niedriger Batteriestand',
        'empty_battery'                  => 'Batterie leer',
        'no_drive'                       => 'fährt nicht',
        'lifted'                         => 'angehoben',
        'stuck_in_charging_station'      => 'eingeklemmt in Ladestation',
        'charging_station_blocked'       => 'Ladestation blockiert',
        'collision_sensor_problem_rear'  => 'Problem Stoßsensor hinten',
        'collision_sensor_problem_front' => 'Problem Stoßsensor vorne',
        'wheel_motor_blocked_right'      => 'Radmotor rechts blockiert',
        'wheel_motor_blocked_left'       => 'Radmotor links blockiert',
        'wheel_drive_problem_right'      => 'Problem Antrieb, rechts',
        'wheel_drive_problem_left'       => 'Problem Antrieb, links',
        'cutting_system_blocked'         => 'Schneidsystem blockiert',
        'invalid_sub_device_combination' => 'fehlerhafte Verbindung',
        'settings_restored'              => 'Standardeinstellungen',
        'electronic_problem'             => 'elektronisches Problem',
        'charging_system_problem'        => 'Problem Ladesystem',
        'tilt_sensor_problem'            => 'Kippsensor Problem',
        'wheel_motor_overloaded_right'   => 'rechter Radmotor überlastet',
        'wheel_motor_overloaded_left'    => 'linker Radmotor überlastet',
        'charging_current_too_high'      => 'Ladestrom zu hoch',
        'temporary_problem'              => 'vorübergehendes Problem',
        'guide_1_not_found'              => 'SK 1 nicht gefunden',
        'guide_2_not_found'              => 'SK 2 nicht gefunden',
        'guide_3_not_found'              => 'SK 3 nicht gefunden',
        'difficult_finding_home'         => 'Problem die Ladestation zu finden',
        'guide_calibration_accomplished' =>
          'Kalibrierung des Suchkabels beendet',
        'guide_calibration_failed' =>
          'Kalibrierung des Suchkabels fehlgeschlagen',
        'temporary_battery_problem' => 'kurzzeitiges Batterieproblem',
        'battery_problem'           => 'Batterieproblem',
        'alarm_mower_switched_off'  => 'Alarm! Mäher ausgeschalten',
        'alarm_mower_stopped'       => 'Alarm! Mäher gestoppt',
        'alarm_mower_lifted'        => 'Alarm! Mäher angehoben',
        'alarm_mower_tilted'        => 'Alarm! Mäher gekippt',
        'connection_changed'        => 'Verbindung geändert',
        'connection_not_changed'    => 'Verbindung nicht geändert',
        'com_board_not_available'   => 'COM Board nicht verfügbar',
        'slipped'                   => 'rutscht',
        'out_of_operation'          => 'ausser Betrieb',
        'replace_now'    => 'kritischer Batteriestand, wechseln Sie jetzt',
        'low'            => 'niedrig',
        'ok'             => 'ok',
        'no_source'      => 'ok',
        'mower_charging' => 'Mäher wurde geladen',
        'completed_cutting_autotimer' => 'Sensor Control erreicht',
        'week_timer'                  => 'Wochentimer erreicht',
        'countdown_timer'             => 'Stoppuhr Timer',
        'undefined'                   => 'unklar',
        'unknown'                     => 'unklar',
        'status_device_unreachable'   => 'Gerät ist nicht in Reichweite',
        'status_device_alive'         => 'Gerät ist in Reichweite',
        'bad'                         => 'schlecht',
        'poor'                        => 'schwach',
        'good'                        => 'gut',
        'undefined'                   => 'unklar',
        'idle'                        => 'nichts zu tun',
        'firmware_cancel'             => 'Firmwareupload unterbrochen',
        'firmware_upload'             => 'Firmwareupload',
        'unsupported'                 => 'nicht unterstützt',
        'up_to_date'                  => 'auf dem neusten Stand',
        'mower'                       => 'Mäher',
        'watering_computer'           => 'Bewässerungscomputer',
        'no_frost'                    => 'kein Frost',
        'open'                        => 'offen',
        'closed'                      => 'geschlossen',
        'included'                    => 'inbegriffen',
        'active'                      => 'aktiv',
        'inactive'                    => 'nicht aktiv',
        'hibernate'                   => 'Winterschlaf',
        'awake'                       => 'Aufgewacht',
        'schedule permanently paused' => 'Zeitplan dauerhaft pausiert',
        'paused until %s'             => 'pausiert bis %s',
        'watering. %.f minutes left'  =>
          'Wird bewässert. %.f Minuten verbleibend.',
        'next watering: %s'        => 'Nächste Bewässerung: %s',
        'n/a'                      => 'nicht verfügbar',
        'pump_not_filled'          => 'Pumpe nicht gefüllt',
        'clean_fine_filter'        => 'Filter reinigen',
        'concurrent_limit_reached' =>
          'Grenze gleichzeitig geöffneter Ventile erreicht',
        'low_battery_prevents_starting' =>
          'Niedrieger Batteriestand verhindert Bewässerung',
    );

    if (
        defined( $langGermanMapp{$readingValue} )
        && (   AttrVal( 'global', 'language', 'none' ) eq 'DE'
            || AttrVal( $name, 'readingValueLanguage', 'none' ) eq 'de' )
        && AttrVal( $name, 'readingValueLanguage', 'none' ) ne 'en'
      )
    {
        return $langGermanMapp{$readingValue};
    }
    else {
        return $readingValue;
    }

    return;
}

sub RigReadingsValue {
    my $hash         = shift;
    my $readingValue = shift;

    my $rigReadingValue;

    if ( $readingValue =~ /^(\d+)-(\d\d)-(\d\d)T(\d\d)/ ) {
        $rigReadingValue = Zulu2LocalString($readingValue);
    }
    else {
        $rigReadingValue = ReadingLangGerman( $hash, $readingValue );
    }

    return $rigReadingValue;
}

sub Zulu2LocalString {
    my $t = shift;

    my ( $datehour, $datemin, $rest ) = split( /:/, $t, 3 );

    my ( $year, $month, $day, $hour, $min ) =
      $datehour =~ /(\d+)-(\d\d)-(\d\d)T(\d\d)/;
    my $epoch = timegm( 0, 0, $hour, $day, $month - 1, $year );

    my ( $lyear, $lmonth, $lday, $lhour, $isdst ) =
      ( localtime($epoch) )[ 5, 4, 3, 2, -1 ];

    $lyear += 1900;    # year is 1900 based
    $lmonth++;         # month number is zero based

    if ( defined($rest) ) {
        return (
            sprintf(
                "%04d-%02d-%02d %02d:%02d:%s",
                $lyear, $lmonth,  $lday,
                $lhour, $datemin, substr( $rest, 0, 2 )
            )
        );
    }
    elsif ( $lyear < 2000 ) {
        return 'temporarily unavailable';
    }
    else {
        return (
            sprintf(
                "%04d-%02d-%02d %02d:%02d",
                $lyear, $lmonth, $lday, $lhour, substr( $datemin, 0, 2 )
            )
        );
    }

    return;
}

sub SetPredefinedStartPoints {
    my $hash = shift;
    my $aArg = shift;

    my ( $startpoint_state, $startpoint_num, @morestartpoints ) = @{$aArg};

    my $name = $hash->{NAME};
    my $payload;
    my $abilities;

    if ( defined($startpoint_state) && defined($startpoint_num) ) {
        if ( defined( $hash->{helper}{STARTINGPOINTS} )
            && $hash->{helper}{STARTINGPOINTS} ne '' )
        {
# add needed parameters to saved settings config and change the value in request
            my $decode_json_settings =
              eval { decode_json( $hash->{helper}{STARTINGPOINTS} ) };
            if ($@) {
                Log3 $name, 3,
"GardenaSmartBridge ($name) - JSON error while setting startpoint: $@";
            }

            $decode_json_settings->{device} = $hash->{DEVICEID};
            my $setval = $startpoint_state eq 'disable' ? \0 : \1;
            $decode_json_settings->{value}[ $startpoint_num - 1 ]{enabled} =
              $setval;

            #set more startpoints
            if (
                defined scalar(@morestartpoints)
                && (   scalar(@morestartpoints) == 2
                    || scalar(@morestartpoints) == 4 )
              )
            {
                if ( scalar(@morestartpoints) == 2 ) {
                    $setval = $morestartpoints[0] eq 'disable' ? \0 : \1;
                    $decode_json_settings->{value}[ $morestartpoints[1] - 1 ]
                      {enabled} = $setval;

                }
                elsif ( scalar(@morestartpoints) == 4 ) {
                    $setval = $morestartpoints[0] eq 'disable' ? \0 : \1;
                    $decode_json_settings->{value}[ $morestartpoints[1] - 1 ]
                      {enabled} = $setval;
                    $setval = $morestartpoints[2] eq 'disable' ? \0 : \1;
                    $decode_json_settings->{value}[ $morestartpoints[3] - 1 ]
                      {enabled} = $setval;
                }
            }

            $payload   = '"settings": ' . encode_json($decode_json_settings);
            $abilities = 'mower_settings';

            #$abilities['service_id'] = $hash->{helper}{STARTINGPOINTID};
        }
        else {
            return
              "startingpoints not loaded yet, please wait a couple of minutes",
              undef, undef;
        }
    }
    else {
        return
            "startpoint usage: set "
          . $hash->{NAME}
          . " startpoint disable 1 [enable 2] [disable 3]", undef, undef;
    }

    return undef, $payload, $abilities;
}

1;

=pod

=item device
=item summary    Modul to control GardenaSmart Devices
=item summary_DE Modul zur Steuerung von GardenaSmartger&auml;ten
=begin html

<a id="GardenaSmartDevice"></a>
<h3>GardenaSmartDevice</h3>
<ul> 
    In combination with Fhem device <b>GardenaSmartBridge</b> this Fhem module enables communication between GardenaCloud and
    fhem.
    <br><br>
    Once the bridge device is created, the connected Gardena devices will be recognized and created in Fhem
    automatically.<br>
    From now on these devices can be controlled via Fhem. Changes in the Gardena App are synchronized with state and
    readings of the devices.
    <br><br>
    So far, known devices are mower, smart water control, irrigation control, smart sensors, power plug and pressure
    pump. Schedules can be disabled/enabled via fhem, defining or deleting them must be done via Gardena App or its web interface.<br>
</ul>
<br>
<div>
  <a id="GardenaSmartDevice-set"></a>
  <li><a id="GardenaSmartDevice-set-parkUntilFurtherNotice">parkUntilFurtherNotice</a> - park mower and disable schedule</li>
  <li><a id="GardenaSmartDevice-set-parkUntilNextTimer">parkUntilNextTimer</a> - park mower until next schedule</li>
  <li><a id="GardenaSmartDevice-set-startOverrideTimer">startOverrideTimer</a> n - manual mowing for n minutes (e.g. 60 = 1h, 1440 = 24h, 4320 = 72h)</li>
  <li><a id="GardenaSmartDevice-set-startResumeSchedule">startResumeSchedule</a> - enable schedule</li>
  <li><a id="GardenaSmartDevice-set-startpoint">startpoint</a> enable|disable 1|2|3 - nable or disable pre-defined starting points
    <ul>
      <li>set NAME startpoint enable 1</li>
      <li>set NAME startpoint disable 3 enable 1</li>
    </ul>
  </li>
  <!-- WC, PUMPE, SENSOR(2) -->
  <li><a id="GardenaSmartDevice-set-cancelOverride">cancelOverride</a> - stop (manual) watering</li>
  <li><a id="GardenaSmartDevice-set-manualButtonTime">manualButtonTime</a> n - set watering time for manual button (0 disables button)</li>
  <li><a id="GardenaSmartDevice-set-manualOverride">manualOverride</a> n - manual watering for n minutes</li>
  <li><a id="GardenaSmartDevice-set-resetValveErrors">resetValveErrors</a> - reset valve errormessage</li>
  <li><a id="GardenaSmartDevice-set-resumeSchedule">resumeSchedule</a> - enable schedule</li>
  <li><a id="GardenaSmartDevice-set-stopSchedule">stopSchedule</a> n - disable schedule for n hours (Default: 2038-01-18T00:00:00.000Z, Gardena App reads it as
            "permanently")</li>
   
  <li><a id="GardenaSmartDevice-set-operating_mode">operating_mode</a> - Managing operation mode. Timed operation is used in combination with schedules or "manualOverride". Automatic operation leaves pump active and activates irrigation depending on start-up pressure.   automatic|scheduled </li>
  <li><a id="GardenaSmartDevice-set-leakage_detection">leakage_detection</a> - Manages leakage detection.</br> Pump will be deactivated if it detects irregular loss of water. watering|washing_machine|domestic_water_supply|off</li>
  <li><a id="GardenaSmartDevice-set-turn_on_pressure">turn_on_pressure</a> - Start-up pressure 2.0 - 3.0 Manages start-up pressure in scheduled and automatic mode. If pressure falls below this setting, pump will start. If pressure stays above this setting and there isn't any water flow, pump will activate standby.</li>
       
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve1">cancelOverrideValve1</a> - stop (manual) watering for valve 1</li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve2">cancelOverrideValve2</a> - stop (manual) watering for valve 2</li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve3">cancelOverrideValve3</a> - stop (manual) watering for valve 3</li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve4">cancelOverrideValve4</a> - stop (manual) watering for valve 4</li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve5">cancelOverrideValve5</a> - stop (manual) watering for valve 5</li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve6">cancelOverrideValve6</a> - stop (manual) watering for valve 6</li>
  <li><a id="GardenaSmartDevice-set-closeAllValves">closeAllValves</a> - close all valves</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve1">manualDurationValve1</a> n - open valve 1 for n minutes</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve2">manualDurationValve2</a> n - open valve 2 for n minutes</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve3">manualDurationValve3</a> n - open valve 3 for n minutes</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve4">manualDurationValve4</a> n - open valve 4 for n minutes</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve5">manualDurationValve5</a> n - open valve 5 for n minutes</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve6">manualDurationValve6</a> n - open valve 6 for n minutes</li> 
  <li><a id="GardenaSmartDevice-set-resumeScheduleValve">resumeScheduleValve</a> n - (re)start irrigation schedule for valve n</li>
  <li><a id="GardenaSmartDevice-set-stopScheduleValve">stopScheduleValve</a> n m - stop irrigation schedule for valve n  (Default: 2038-01-18T00:00:00.000Z, Gardena
            App reads it as "permanently")</li>
  <!-- ALL -->
  <li><a id="GardenaSmartDevice-set-winter_mode">winter_mode</a> awake|hibernate -  enable or disable winter mode</li>
  <!-- SENSOR -->
  <li><a id="GardenaSmartDevice-set-refresh">refresh</a> temperature|humidity|light*
  <br>
    refresh sensor reading for temperature, humidity or daylight
    <br>*only Sensor type 1
  </li>

  

</div>
    <a id="GardenaSmartDevice-readings"></a>
<ul>
    <b>Readings (model = mower)</b>
    <br><br>
    Readings are based on Sileno, other models might have different/additional readings depending on their functions (tbd.)
    <br><br>
    <ul>
        <li>battery-charging - Indicator if battery is charged (0/1)</li>
        <li>battery-level - load percentage of battery</li>
        <li>battery-rechargeable_battery_status - healthyness of the battery (out_of_operation/replace_now/low/ok), not all models</li>
        <li>device_info-category - category of device (mower/watering_computer)</li>
        <li>device_info-connection_status - connection status (online/offline/unknown)</li>
        <li>device_info-last_time_online - timestamp of last radio contact</li>
        <li>device_info-manufacturer - manufacturer</li>
        <li>device_info-product - product type</li>
        <li>device_info-serial_number - serial number</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - firmware version</li>
        <li>firmware-firmware_command - firmware command (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - firmware status </li>
        <li>firmware-firmware_upload_progress - progress indicator of firmware update</li>
        <li>firmware-inclusion_status - inclusion status</li>
        <li>internal_temperature-temperature - internal device temperature, not all models</li>
        <li>mower-error - actual error message
            <ul>
                <li>no_message</li>
                <li>outside_working_area</li>
                <li>no_loop_signal</li>
                <li>wrong_loop_signal</li>
                <li>loop_sensor_problem_front</li>
                <li>loop_sensor_problem_rear</li>
                <li>trapped</li>
                <li>upside_down</li>
                <li>low_battery</li>
                <li>empty_battery</li>
                <li>no_drive</li>
                <li>lifted</li>
                <li>stuck_in_charging_station</li>
                <li>charging_station_blocked</li>
                <li>collision_sensor_problem_rear</li>
                <li>collision_sensor_problem_front</li>
                <li>wheel_motor_blocked_right</li>
                <li>wheel_motor_blocked_left</li>
                <li>wheel_drive_problem_right</li>
                <li>wheel_drive_problem_left</li>
                <li>cutting_system_blocked</li>
                <li>invalid_sub_device_combination</li>
                <li>settings_restored</li>
                <li>electronic_problem</li>
                <li>charging_system_problem</li>
                <li>tilt_sensor_problem</li>
                <li>wheel_motor_overloaded_right</li>
                <li>wheel_motor_overloaded_left</li>
                <li>charging_current_too_high</li>
                <li>temporary_problem</li>
                <li>guide_1_not_found</li>
                <li>guide_2_not_found</li>
                <li>guide_3_not_found</li>
                <li>difficult_finding_home</li>
                <li>guide_calibration_accomplished</li>
                <li>guide_calibration_failed</li>
                <li>temporary_battery_problem</li>
                <li>battery_problem</li>
                <li>alarm_mower_switched_off</li>
                <li>alarm_mower_stopped</li>
                <li>alarm_mower_lifted</li>
                <li>alarm_mower_tilted</li>
                <li>connection_changed</li>
                <li>connection_not_changed</li>
                <li>com_board_not_available</li>
                <li>slipped</li>
            </ul>
        </li>
        <li>mower-last_error_code - code of last error</li>
        <li>mower-source_for_next_start - source for the next start
            <ul>
                <li>no_source</li>
                <li>mower_charging</li>
                <li>completed_cutting_autotimer</li>
                <li>week_timer</li>
                <li>countdown_timer</li>
                <li>undefined</li>
            </ul>
        </li>
        <li>mower-status - mower status (see state reading)</li>
        <li>mower-timestamp_last_error_code - timestamp of last error</li>
        <li>mower-timestamp_next_start - timestamp of next scheduled start</li>
        <li>mower_stats-charging_cycles - number of charging cycles</li>
        <li>mower_stats-collisions - number of collisions</li>
        <li>mower_stats-cutting_time - cutting time in hours</li>
        <li>mower_stats-running_time - running time in hours (including cutting time)</li>
        <li>mower_timer-mower_timer - (tbd.)</li>
        <li>mower_timer-mower_timer_timestamp - (tbd.)</li>
        <li>mower_type-base_software_up_to_date - latest software (0/1)</li>
        <li>mower_type-device_type - device type </li>
        <li>mower_type-device_variant - device variant</li>
        <li>mower_type-mainboard_version - mainboard version</li>
        <li>mower_type-mmi_version - mmi version</li>
        <li>mower_type-serial_number - serial number</li>
        <li>radio-quality - percentage of the radio quality</li>
        <li>radio-state - radio state (bad/poor/good/undefined)</li>
        <li>scheduling-schedules_event_n_end_at - ending time of schedule 1</li>
        <li>scheduling-schedules_event_n_id - ID of schedule 1</li>
        <li>scheduling-schedules_event_n_start_at - starting time of schedule 1</li> 
        <li>scheduling-schedules_event_n_weekly - weekdays of schedule 1(comma-separated)</li>
        <li>...more readings for additional schedules (if defined)</li>
        <li>scheduling-schedules_events_count - number of pre-defined schedules</li>
	<li>startpoint-1-enabled - starpoint 1 enabled (0/1)</li>
        <li>...more readings for additional startpoints</li>
        <li>state - state of the mower
            <ul>
                <li>paused</li>
                <li>ok_cutting</li>
                <li>ok_searching</li>
                <li>ok_charging</li>
                <li>ok_leaving</li>
                <li>wait_updating</li>
                <li>wait_power_up</li>
                <li>parked_timer</li>
                <li>parked_park_selected</li>
                <li>off_disabled</li>
                <li>off_hatch_open</li>
                <li>unknown</li>
                <li>error</li>
                <li>error_at_power_up</li>
                <li>off_hatch_closed</li>
                <li>ok_cutting_timer_overridden</li>
                <li>parked_autotimer</li>
                <li>parked_daily_limit_reached</li>
                <li>hibernate - winter mode</li>
            </ul>
        </li>
        <li>winter_mode - status of winter mode (awake/hibernate)</li>    
    </ul>
    <br><br>
    <b>Readings (model = watering_computer)</b>
    <ul>
        <li>ambient_temperature-temperature - ambient temperature in Celsius</li>
        <li>battery-disposable_battery_status - healthyness of the battery (ok/low/replace_now/out_of_operation/no_battery/unknown)</li>
	<li>battery-level - energy level of battery in percent</li>
        <li>device_info-category - category of device (mower/watering_computer/sensor/etc.)</li>
        <li>device_info-connection_status - connection status (online/offline/unknown)</li>
        <li>device_info-last_time_online - timestamp of last radio contact</li>
        <li>device_info-manufacturer - manufacturer</li>
        <li>device_info-product - product type</li>
        <li>device_info-serial_number - serial number</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - firmware version</li>
        <li>error-error - error message (tbd.)</li>
        <li>error-valve_error_1_severity - (tbd.)</li>
        <li>error-valve_error_1_type - (tbd.)</li>
        <li>error-valve_error_1_valve_id - id of valve with error</li>
        <li>firmware-firmware_available_version - new available firmware (only if available)</li>
        <li>firmware-firmware_command - firmware command (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - firmware status </li>
        <li>firmware-firmware_upload_progress - progress indicator of firmware update</li>
        <li>firmware-inclusion_status - inclusion status</li>        
        <li>manualButtonTime - watering time for manual button on device in minutes</li>
        <li>radio-quality - percentage of the radio quality</li>
        <li>radio-state - radio state (bad/poor/good/undefined)</li>   
        <li>scheduling-scheduled_watering_end - next schedule ending time</li>
        <li>scheduling-scheduled_watering_next_start - next schedule starting time</li>
        <li>scheduling-schedules_event_n_valve_1_end_at - ending time of schedule 1</li>
        <li>scheduling-schedules_event_n_valve_1_id - ID of schedule 1</li>
        <li>scheduling-schedules_event_n_valve_1_start_at - starting time of schedule 1</li>
        <li>scheduling-schedules_event_n_valve_1_weekly - weekdays of schedule 1</li>
        <li>scheduling-schedules_events_count - number of pre-defined schedules</li>
        <li>scheduling-schedules_paused_until - date/time until schedule is paused (2038-01-18T00:00:00.000Z is defined as permanently by Gardena cloud) </li>
        <li>state - state of device
           <ul>
               <li>closed - valve closed, no schedules available</li>
               <li>closed. schedule permanently paused - valve closed, schedule disabled</li>
               <li>closed. next watering: YYYY-MM-DD HH:MM - valve closed, next scheduled start at YYYY-MM-DDTHH:MM:00.000Z</li>
               <li>watering. n minutes left. - watering, n minutes remaining (depending on manual button time or on pre-defined schedule)</li>
               <li>offline - device is disabled/not connected</li>
               <li>hibernate - winter mode)</li>
           </ul>
        </li>
	<li>watering-watering_timer_1_duration - duration of current watering in seconds</li>
        <li>watering-watering_timer_1_irrigation_left - remaining watering time in minutes</li>
        <li>watering-watering_timer_1_state - state of schedule</li>
        <li>watering-watering_timer_1_valve_id - valve id of schedule</li>
        <li>winter_mode - status of winter mode (awake/hibernate)</li>        
    </ul>
    <br><br>
    <b>Readings (model = ic24)</b>
    <ul>
        <li>device_info-category - category of device (mower/watering_computer/sensor/etc.)</li>
        <li>device_info-connection_status - connection status (online/offline/unknown)</li>
        <li>device_info-last_time_online - timestamp of last radio contact</li>
        <li>device_info-manufacturer - manufacturer</li>
        <li>device_info-product - product type</li>
        <li>device_info-serial_number - serial number</li>
        <li>device_info-sgtin - tbd.</li>
        <li>device_info-version - firmware version</li>
        <li>error-error - error message (tbd.)</li>
        <li>error-valve_error_0_severity - (tbd.)</li>
        <li>error-valve_error_0_type - (tbd.)</li>
        <li>error-valve_error_0_valve_id - id of valve with error</li>
        <li>...more error readings</li>
        <li>firmware-firmware_available_version - new available firmware (only if available)</li>
        <li>firmware-firmware_command - firmware command (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - firmware status </li>
        <li>firmware-firmware_upload_progress - progress indicator of firmware update</li>
        <li>firmware-inclusion_status - inclusion status</li>        
        <li>ic24-valves_connected - connected valves (comma separated)</li>
        <li>ic24-valves_master_config - master valve (only if defined in Gardena app)</li>
        <li>radio-quality - percentage of the radio quality</li>
        <li>radio-state - radio state (bad/poor/good/undefined)</li>   
        <li>scheduling-scheduled_watering_end - next schedule ending time</li>
        <li>scheduling-scheduled_watering_end_1 - next schedule ending time for valve 1</li>
        <li>...more readings for valves 2-6</li>
        <li>scheduling-scheduled_watering_next_start - next schedule starting time</li>
        <li>scheduling-scheduled_watering_next_start_1 - next schedule starting time for valve 1</li>
        <li>...more readings for valves 2-6</li>
        <li>scheduling-schedules_event_n_valve_1_end_at - ending time of schedule 1</li>
        <li>scheduling-schedules_event_n_valve_1_id - ID of schedule 1</li>
        <li>scheduling-schedules_event_n_valve_1_start_at - starting time of schedule 1</li>
        <li>scheduling-schedules_event_n_valve_1_weekly - weekdays of schedule 1</li>
        <li>scheduling-schedules_events_count - number of pre-defined schedules</li>
        <li>...more readings for further schedules/valves</li>
        <li>scheduling-schedules_paused_until_1 - date/time until schedule is paused (2038-01-18T00:00:00.000Z is defined as permanently by Gardena cloud) </li>
        <li>...more readings for valves 2-6</li>
        <li>state - state of device
           <ul>
               <li>closed - valve closed, no schedules available</li>
               <li>closed. schedule permanently paused - valve closed, all schedules disabled/paused</li>
               <li>closed. next watering: YYYY-MM-DD HH:MM - valve closed, next scheduled start at YYYY-MM-DDTHH:MM:00.000Z</li>
               <li>watering. n minutes left. - watering, n minutes remaining. If more than one schedule is active, the longer remaining time is shown.</li>
               <li>offline - device is disabled/not connected</li>
           </ul>
        </li>
        <li>valve-valve_name_1 - individual name for valve 1</li>
        <li>...more readings for valves 2-6 (if installed)</li>
	<li>watering-watering_timer_1_duration - duration of current watering in seconds</li>
        <li>watering-watering_timer_1_irrigation_left - remaining watering time in minutes</li>
        <li>watering-watering_timer_1_state - state of schedule</li>
        <li>watering-watering_timer_1_valve_id - valve id of schedule</li>
        <li>...more readings for further valves/schedules</li>
        <li>winter_mode - status of winter mode (awake/hibernate)</li>
    </ul>   
    <br><br>
    <b>Readings (model = sensor)</b>
    <ul>
	<li>ambient_temperature-frost_warning - frost warning</li>
        <li>ambient_temperature-temperature - ambient temperature in Celsius</li>
        <li>battery-disposable_battery_status - healthyness of the battery (ok/low/replace_now/out_of_operation/no_battery/unknown)</li>
	<li>battery-level - energy level of battery in percent</li>
        <li>device_info-category - category of device (mower/watering_computer/sensor/etc.)</li>
        <li>device_info-connection_status - connection status (online/offline/unknown)</li>
        <li>device_info-last_time_online - timestamp of last radio contact</li>
        <li>device_info-manufacturer - manufacturer</li>
        <li>device_info-product - product type</li>
        <li>device_info-serial_number - serial number</li>
        <li>device_info-sgtin - tbd.</li>
        <li>device_info-version - firmware version</li>
        <li>firmware-firmware_available_version - new available firmware (only if available)</li>
        <li>firmware-firmware_command - firmware command (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - firmware status </li>
        <li>firmware-firmware_upload_progress - progress indicator of firmware update</li>
        <li>firmware-inclusion_status - inclusion status</li>
	<li>humidity-humidity - humidity in percent</li>
        <li>light-light - brightness in lux</li>
        <li>radio-quality - percentage of the radio quality</li>
        <li>radio-state - radio state (bad/poor/good/undefined)</li>
        <li>soil_temperature-temperature - soil temperature in Celsius</li>
        <li>state - state of sensor (temperature (T:), humidity (H:), brightness/light (L:)|offline|hibernate)</li>
        <li>winter_mode - status of winter mode (awake/hibernate)</li>
    </ul>
    <br><br>
    <b>Readings (model = sensor2)</b>
    <br><br>
    "sensor2" does not measure brightness or ambient temperature, and it has another reading for frost warning. Other than that, it seems to be more or less identical to "sensor".
    <br><br>
    <ul>
        <li>battery-disposable_battery_status - healthyness of the battery (ok/low/replace_now/out_of_operation/no_battery/unknown)</li>
	<li>battery-level - energy level of battery in percent</li>
        <li>device_info-category - category of device (mower/watering_computer/sensor/etc.)</li>
        <li>device_info-connection_status - connection status (online/offline/unknown)</li>
        <li>device_info-last_time_online - timestamp of last radio contact</li>
        <li>device_info-manufacturer - manufacturer</li>
        <li>device_info-product - product type</li>
        <li>device_info-serial_number - serial number</li>
        <li>device_info-sgtin - tbd.</li>
        <li>device_info-version - firmware version</li>
        <li>firmware-firmware_available_version - new available firmware (only if available)</li>
        <li>firmware-firmware_command - firmware command (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - firmware status </li>
        <li>firmware-firmware_upload_progress - progress indicator of firmware update</li>
        <li>firmware-inclusion_status - inclusion status</li>
	<li>humidity-humidity - humidity in percent</li>
        <li>radio-quality - percentage of the radio quality</li>
        <li>radio-state - radio state (bad/poor/good/undefined)</li>
        <li>soil_model-model_definition - tbd.</li>
        <li>soil_model-model_status - tbd.</li>
        <li>soil_temperature-frost-warning - frost warning</li>
        <li>soil_temperature-temperature - soil temperature in Celsius</li>
        <li>state - state of sensor (temperature (T:), humidity (H:)|offline|hibernate)</li>
        <li>winter_mode - status of winter mode (awake/hibernate)</li>
    </ul>
    <br><br>
    <b>Readings (model = power)</b>
    <ul>
        <li>(tbd.)</li>
    </ul>
    <br><br>
    <b>Readings (model = electronic_pressure_pump)</b>
    <ul>
        <li>(tbd.)</li>
    </ul>
    <br><br><br>
    <a id="GardenaSmartDevice-attr"></a>
    <b>Attribute (all models)</b>
    <ul>
        <li>IODev - Name of GardenaSmartBridge device</li>
        <li>model watering_computer|sensor|sensor2|mower|ic24|power|electronic_pressure_pump - model of
            GardenaSmartDevice</li>
        <li>readingValueLanguage en|de - Reading language enlish or german (default: english, if global language is not
            set to german)</li>
    </ul>
    <br><br><br>
    <a id="GardenaSmartDevice-set"></a>
    <b>set (model = mower)</b>
    <ul>
        <li>parkUntilFurtherNotice - park mower and disable schedule</li>
        <li>parkUntilNextTimer - park mower until next schedule</li>
        <li>startOverrideTimer n - manual mowing for n minutes (e.g. 60 = 1h, 1440 = 24h, 4320 = 72h)</li>
        <li>startResumeSchedule - enable schedule</li>
        <li>startPoint enable|disable 1|2|3 - enable or disable pre-defined starting points</li>
        <ul>
            <li>set NAME startpoint enable 1</li>
            <li>set NAME startpoint disable 3 enable 1</li>
        </ul>
        <li>winter_mode hibernate|awake - enable or disable winter mode</li>
    </ul>
    <br><br>
    <b>set (model = watering_computer)</b>
    <ul>
        <li>cancelOverride - stop (manual) watering</li>
        <li>manualButtonTime n - set watering time for manual button (0 disables button)</li>
        <li>manualOverride n - manual watering for n minutes</li>
        <li>resetValveErrors - reset valve errormessage</li>
        <li>resumeSchedule - enable schedule</li>
        <li>stopSchedule n - disable schedule for n hours (Default: 2038-01-18T00:00:00.000Z, Gardena App reads it as
            "permanently")</li>
        <li>winter_mode hibernate|awake - enable or disable winter mode</li>
    </ul>
    <br><br>
    <b>set (model = ic24)</b>
    <ul>
        <li>cancelOverrideValve1 - stop (manual) watering for valve 1 </li>
        <li>cancelOverrideValve2 - stop (manual) watering for valve 2 </li>
        <li>cancelOverrideValve3 - stop (manual) watering for valve 3 </li>
        <li>cancelOverrideValve4 - stop (manual) watering for valve 4 </li>
        <li>cancelOverrideValve5 - stop (manual) watering for valve 5 </li>
        <li>cancelOverrideValve6 - stop (manual) watering for valve 6 </li>
        <li>closeAllValves - close all valves</li>
        <li>manualDurationValve1 n - open valve 1 for n minutes</li>
        <li>manualDurationValve2 n - open valve 2 for n minutes</li>
        <li>manualDurationValve3 n - open valve 3 for n minutes</li>
        <li>manualDurationValve4 n - open valve 4 for n minutes</li>
        <li>manualDurationValve5 n - open valve 5 for n minutes</li>
        <li>manualDurationValve6 n - open valve 6 for n minutes</li>
        <li>resetValveErrors - reset valve errormessage</li>
        <li>resumeScheduleValve n - (re)start irrigation schedule for valve n</li>
        <li>stopScheduleValve n m - stop irrigation schedule for valve n  (Default: 2038-01-18T00:00:00.000Z, Gardena
            App reads it as "permanently")</li>
        <li>winter_mode hibernate|awake - enable or disable winter mode</li>
    </ul>
    <br><br>
    <b>set (model = sensor)</b>
    <ul>
        <li>refresh temperature|humidity|light - refresh sensor reading for temperature, humidity or daylight</li>
        <li>winter_mode hibernate|awake - enable or disable winter mode</li>
    </ul>
    <br><br>
    <b>set (model = sensor2)</b>
    <ul>
        <li>refresh temperature|humidity - refresh sensor reading for temperature or humidity</li>
        <li>winter_mode hibernate|awake - enable or disable winter mode</li>
    </ul>
    <br><br>
    <b>set (model = power)</b>
    <ul>
        <li>(tbd.)</li>
    </ul>
    <br><br>
    <b>set (model = electronic_pressure_pump)</b>
    <ul>
        <li>(tbd.)</li>
    </ul>
</ul>

=end html

=begin html_DE


<a id="GardenaSmartDevice"></a>
<h3>GardenaSmartDevice</h3>
<ul>
    Zusammen mit dem Device GardenaSmartBridge stellt dieses Fhem-Modul die Kommunikation zwischen der GardenaCloud und
    Fhem her.
    <br><br>
    Wenn das GardenaSmartBridge Device erzeugt wurde, werden verbundene Ger&auml;te automatisch erkannt und in Fhem angelegt.
    <br>
    Von nun an k&ouml;nnen die eingebundenen Ger&auml;te gesteuert werden. &auml;nderungen in der App werden mit den Readings und dem
    Status synchronisiert.
    <br><br>
    Bekannte Gardena-Ger&auml;te umfassen Rasenm&auml;her, Smart Water Control, Irrigation Control, Smart Sensoren,
    Steckdosen-Adapter und Pumpe. Zeitpl&auml;ne k&ouml;nnen &uuml;ber fhem pausiert/aktiviert werden, das Anlegen oder L&ouml;schen erfolgt
    derzeit nur &uuml;ber die App oder deren Web-Frontend.
</ul>
<div>
  <a id="GardenaSmartDevice-set"></a>
  <li><a id="GardenaSmartDevice-set-parkUntilFurtherNotice">parkUntilFurtherNotice</a> - Parken des M&auml;hers und Aussetzen des Zeitplans</li>
  <li><a id="GardenaSmartDevice-set-parkUntilNextTimer">parkUntilNextTimer</a> - Parken bis zum n&auml;chsten Start nach Zeitplan</li>
  <li><a id="GardenaSmartDevice-set-startOverrideTimer">startOverrideTimer</a> n - Manuelles M&auml;hen f&uuml;r n Minuten (z.B. 60 = 1h, 1440 = 24h, 4320 = 72h)</li>
  <li><a id="GardenaSmartDevice-set-startResumeSchedule">startResumeSchedule</a> - Zeitplan wieder aktivieren</li>
  <li><a id="GardenaSmartDevice-set-startpoint">startpoint</a> enable|disable 1|2|3 - Aktiviert oder deaktiviert einen vordefinierten Startbereich
    <ul>
      <li>set NAME startpoint enable 1</li>
      <li>set NAME startpoint disable 3 enable 1</li>
    </ul>
  </li>
  <!-- WC, PUMPE, SENSOR(2) -->
  <li><a id="GardenaSmartDevice-set-cancelOverride">cancelOverride</a> - (Manuelle) Bew&auml;sserung stoppen</li>
  <li><a id="GardenaSmartDevice-set-manualButtonTime">manualButtonTime</a> n - Bew&auml;sserungsdauer f&uuml;r manuellen Knopf auf n Minuten setzen (0 schaltet den Knopf aus)</li>
  <li><a id="GardenaSmartDevice-set-manualOverride">manualOverride</a> n - Manuelle Bew&auml;sserung f&uuml;r n Minuten</li>
  <li><a id="GardenaSmartDevice-set-resetValveErrors">resetValveErrors</a> - Ventilfehler zur&uuml;cksetzen</li>
  <li><a id="GardenaSmartDevice-set-resumeSchedule">resumeSchedule</a> - Zeitplan wieder aktivieren</li>
  <li><a id="GardenaSmartDevice-set-stopSchedule">stopSchedule</a> n - Zeitplan anhalten f&uuml;r n Stunden (Default: 2038-01-18T00:00:00.000Z, durch Gardena-App als "dauerhaft" interpretiert)</li>
   
  <li><a id="GardenaSmartDevice-set-operating_mode">operating_mode</a> -Steuert den Operation Mode. Zeitgesteuert wird in Kombination mit dem Wochenzeitplan oder mit "manualOverride" genutzt, automatisch bedeutet, dass die Pumpe immer aktiv ist und die Bewässerung abhängig vom Wert "Einschaltdruck" startet. automatic|scheduled </li>
  <li><a id="GardenaSmartDevice-set-leakage_detection">leakage_detection</a> - Steuert die Lekage-Erkennung.</br> Hierdurch wird eine Pumpenabschaltung erreicht, sollte die Pumpe unkontrollierten Wasserverlust feststellen.  watering|washing_machine|domestic_water_supply|off</li>
  <li><a id="GardenaSmartDevice-set-turn_on_pressure">turn_on_pressure</a> - Einschaltdruck 2.0 - 3.0 Steuert den Einschaltdruck in Scheduled und Automatic Mode. Fällt der Druck bei der Bewässerung unter diese wert, startet die Pumpe, ist der Wert dauerhaft über diesem Wert und es finden kein Durchfluss statt, geht die Pumpe in Standby</li>
      
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve1">cancelOverrideValve1</a> - (Manuelle) Bew&auml;sserung an Ventil 1 stoppen </li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve2">cancelOverrideValve2</a> - (Manuelle) Bew&auml;sserung an Ventil 2 stoppen </li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve3">cancelOverrideValve3</a> - (Manuelle) Bew&auml;sserung an Ventil 3 stoppen </li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve4">cancelOverrideValve4</a> - (Manuelle) Bew&auml;sserung an Ventil 4 stoppen </li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve5">cancelOverrideValve5</a> - (Manuelle) Bew&auml;sserung an Ventil 5 stoppen </li>
  <li><a id="GardenaSmartDevice-set-cancelOverrideValve6">cancelOverrideValve6</a> - (Manuelle) Bew&auml;sserung an Ventil 6 stoppen </li>
  <li><a id="GardenaSmartDevice-set-closeAllValves">closeAllValves</a> - Alle Ventile schliessen</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve1">manualDurationValve1</a> n - Ventil 1 f&uuml;r n Minuten &ouml;ffnen</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve2">manualDurationValve2</a> n - Ventil 2 f&uuml;r n Minuten &ouml;ffnen</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve3">manualDurationValve3</a> n - Ventil 3 f&uuml;r n Minuten &ouml;ffnen</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve4">manualDurationValve4</a> n - Ventil 4 f&uuml;r n Minuten &ouml;ffnen</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve5">manualDurationValve5</a> n - Ventil 5 f&uuml;r n Minuten &ouml;ffnen</li>
  <li><a id="GardenaSmartDevice-set-manualDurationValve6">manualDurationValve6</a> n - Ventil 6 f&uuml;r n Minuten &ouml;ffnen</li> 
  <li><a id="GardenaSmartDevice-set-resumeScheduleValve">resumeScheduleValve</a> n - Zeitplan f&uuml;r Ventil n wieder aktivieren</li>
  <li><a id="GardenaSmartDevice-set-stopScheduleValve">stopScheduleValve</a> n m - Zeitplan f&uuml;r Ventil n anhalten f&uuml;r m Stunden (Default: 2038-01-18T00:00:00.000Z durch Gardena-App als "dauerhaft" interpretiert)</li>
  <!-- ALL -->
  <li><a id="GardenaSmartDevice-set-winter_mode">winter_mode</a> awake|hibernate - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
  <!-- SENSOR -->
  <li><a id="GardenaSmartDevice-set-refresh">refresh</a> temperature|humidity|light*
  <br>
    Wert f&uuml;r Temperatur, Feuchtigkeit oder Helligkeit aktualisieren
    <br>*nur bei Sensor type 1 verf&uuml;gbar
  </li>

  

</div>
<br>
<a id="GardenaSmartDevice-readings"></a>
<ul>
    <b>Readings (model = mower/M&auml;her)</b>
    <br><br>
    Readings basieren auf dem Modell Sileno, andere Modelle haben abweichende/zus&auml;tzliche Readings abh&auml;ngig von ihren Funktionen (tbd.)
    <br><br>
    <ul>
        <li>battery-charging - Ladeindikator (0/1)</li>
        <li>battery-level - Ladezustand der Batterie in Prozent</li>
        <li>battery-rechargeable_battery_status - Zustand der Batterie (Ausser Betrieb/Kritischer Batteriestand,
            wechseln Sie jetzt/Niedrig/oK), nicht bei allen Modellen</li>
        <li>device_info-connection_status - Verbindungs-Status (online/offline/unknown)</li>
        <li>device_info-category - Eigenschaft des Ger&auml;tes (M&auml;her/Bew&auml;sserungscomputer/Bodensensor)</li>
        <li>device_info-last_time_online - Zeitpunkt der letzten Funk&uuml;bertragung</li>
        <li>device_info-manufacturer - Hersteller</li>
        <li>device_info-product - Produkttyp</li>
        <li>device_info-serial_number - Seriennummer</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - Firmware Version</li>
        <li>firmware-firmware_command - Firmware Kommando (Nichts zu tun/Firmwareupload
            unterbrochen/Firmwareupload/nicht unterst&uuml;tzt)</li>
        <li>firmware-firmware_status - Firmware Status </li>
        <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
        <li>firmware-inclusion_status - Einbindungsstatus</li>
        <li>internal_temperature-temperature - Interne Ger&auml;te Temperatur, nicht bei allen Modellen</li>
        <li>mower-error - Aktuelle Fehler Meldung
            <ul>
                <li>Kein Fehler</li>
                <li>Ausserhalb des Arbeitsbereichs</li>
                <li>Kein Schleifensignal</li>
                <li>Falsches Schleifensignal</li>
                <li>Problem Schleifensensor, vorne</li>
                <li>Problem Schleifensensor, hinten</li>
                <li>Eingeschlossen</li>
                <li>Steht auf dem Kopf</li>
                <li>Niedriger Batteriestand</li>
                <li>Batterie ist leer</li>
                <li>Kein Antrieb</li>
                <li>Angehoben</li>
                <li>Eingeklemmt in Ladestation</li>
                <li>Ladestation blockiert</li>
                <li>Problem Stosssensor hinten</li>
                <li>Problem Stosssensor vorne</li>
                <li>Radmotor rechts blockiert</li>
                <li>Radmotor links blockiert</li>
                <li>Problem Antrieb, rechts</li>
                <li>Problem Antrieb, links</li>
                <li>Schneidsystem blockiert</li>
                <li>Fehlerhafte Verbindung</li>
                <li>Standardeinstellungen</li>
                <li>Elektronisches Problem</li>
                <li>Problem Ladesystem</li>
                <li>Kippsensorproblem</li>
                <li>Rechter Radmotor &uuml;berlastet</li>
                <li>Linker Radmotor &uuml;berlastet</li>
                <li>Ladestrom zu hoch</li>
                <li>Vor&uuml;bergehendes Problem</li>
                <li>SK 1 nicht gefunden</li>
                <li>SK 2 nicht gefunden</li>
                <li>SK 3 nicht gefunden</li>
                <li>Problem die Ladestation zu finden</li>
                <li>Kalibration des Suchkabels beendet</li>
                <li>Kalibration des Suchkabels fehlgeschlagen</li>
                <li>Kurzzeitiges Batterieproblem</li>
                <li>Batterieproblem</li>
                <li>Alarm! M&auml;her ausgeschalten</li>
                <li>Alarm! M&auml;her gestoppt</li>
                <li>Alarm! M&auml;her angehoben</li>
                <li>Alarm! M&auml;her gekippt</li>
                <li>Verbindung ge&auml;ndert</li>
                <li>Verbindung nicht ge&auml;ndert</li>
                <li>COM board nicht verf&uuml;gbar</li>
                <li>Rutscht</li>
            </ul>
        </li>
        <li>mower-override_end_time - Zeitpunkt wann der manuelle Betrieb beendet ist</li>
        <li>mower-source_for_next_start - Grund f&uuml;r den n&auml;chsten Start
            <ul>
                <li>Kein Grund</li>
                <li>M&auml;her wurde geladen</li>
                <li>SensorControl erreicht</li>
                <li>Wochentimer erreicht</li>
                <li>Stoppuhr Timer</li>
                <li>Undefiniert</li>
            </ul>
        </li>
        <li>mower-status - M&auml;her Status (siehe state)</li>
        <li>mower-timestamp_last_error_code - Zeitpunkt des letzten Fehlers</li>
        <li>mower-timestamp_next_start - Zeitpunkt des n&auml;chsten geplanten Starts</li>
        <li>mower_stats-charging_cycles - Anzahl Ladezyklen</li>
        <li>mower_stats-collisions - Anzahl Zusammenst&ouml;sse</li>
        <li>mower_stats-cutting_time - Schnittzeit in Stunden</li>
        <li>mower_stats-running_time - Laufzeit in Stunden (inkl. Schnittzeit)</li>
        <li>mower_timer-mower_timer - (tbd.)</li>
        <li>mower_timer-mower_timer_timestamp - (tbd.)</li>
        <li>mower_type-base_software_up_to_date - Software aktuell (0/1)</li>
        <li>mower_type-device_type - Ger&auml;tetyp </li>
        <li>mower_type-device_variant - Ger&auml;tevariante</li>
        <li>mower_type-mainboard_version - Mainboard-Version</li>
        <li>mower_type-mmi_version - MMI-Version</li>
        <li>mower_type-serial_number - Seriennummer</li> 
        <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
        <li>radio-state - Verbindungsqualit&auml;t (schlecht/schwach/gut/Undefiniert)</li>
        <li>scheduling-schedules_event_n_end_at - Endzeit des Zeitplans 1</li>
        <li>scheduling-schedules_event_n_id - ID des Zeitplans 1</li>
        <li>scheduling-schedules_event_n_start_at - Startzeit des Zeitplans 1</li> 
        <li>scheduling-schedules_event_n_weekly - Wochentage des Zeitplans 1 (kommagetrennt)</li>
        <li>...weitere Readings f&uuml;r zus&auml;tzliche Zeitpl&auml;ne (falls angelegt)</li>
        <li>scheduling-schedules_events_count - Anzahl angelegter Zeitpl&auml;ne</li>
	    <li>startpoint-1-enabled - starpoint 1 enabled (0/1)</li>
        <li>...weitere Readings f&uuml;r zus&auml;tzliche Startpunkte (falls angelegt)</li>
        <li>state - Status des M&auml;hers
            <ul>
                <li>Pausiert</li>
                <li>M&auml;hen</li>
                <li>Suche Ladestation</li>
                <li>L&auml;dt</li>
                <li>M&auml;hen</li>
                <li>Wird aktualisiert ...</li>
                <li>Wird eingeschaltet ...</li>
                <li>Geparkt nach Zeitplan</li>
                <li>Geparkt</li>
                <li>Der M&auml;her ist ausgeschaltet</li>
                <li>Deaktiviert. Abdeckung ist offen oder PIN-Code erforderlich</li>
                <li>Unbekannter Status</li>
                <li>Fehler</li>
                <li>Neustart ...</li>
                <li>Deaktiviert. Manueller Start erforderlich</li>
                <li>Manuelles M&auml;hen</li>
                <li>Geparkt durch SensorControl</li>
                <li>Abgeschlossen</li>
                <li>Winterschlaf - Ger&auml;t ist im Winterschlaf</li>
            </ul>
        </li>
        <li>winter_mode - Status Winterschlaf (awake/hibernate)</li> 
    </ul>
    <br><br>
    <b>Readings (model = watering_computer/Bew&auml;sserungscomputer)</b>
    <ul>
        <li>ambient_temperature-temperature - Umgebungstemperatur in Celsius</li>
        <li>battery-disposable_battery_status - Batteriezustand</li>
	    <li>battery-level - Ladezustand der Batterie in Prozent</li>
        <li>device_info-category - Art des Ger&auml;ts</li>
        <li>device_info-connection_status - Verbindungsstatus (online/offline/unknown)</li>
        <li>device_info-last_time_online - Zeitpunkt der letzten Funk&uuml;bertragung</li>
        <li>device_info-manufacturer - Hersteller</li>
        <li>device_info-product - Produkttyp</li>
        <li>device_info-serial_number - Seriennummer</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - Firmware Version</li>
        <li>error-error - Fehlermeldung (tbd.)</li>
        <li>error-valve_error_1_severity - (tbd.)</li>
        <li>error-valve_error_1_type - (tbd.)</li>
        <li>error-valve_error_1_valve_id - ID des fehlerhaften Ventils</li>
        <li>firmware-firmware_available_version - Neue Firmware (nur wenn verf&uuml;gbar)</li>
        <li>firmware-firmware_command - Firmware-Kommando (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - Firmware Status </li>
        <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
        <li>firmware-inclusion_status - Einbindungsstatus</li>        
        <li>manualButtonTime - Bew&auml;sserungszeit f&uuml;r den Ger&auml;te-Knopf in Minuten</li>
        <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
        <li>radio-state - Verbindungsqualit&auml;t (schlecht/schwach/gut/Undefiniert)</li>   
        <li>scheduling-scheduled_watering_end - Endzeit des n&auml;chsten Zeitplans</li>
        <li>scheduling-scheduled_watering_next_start - Startzeit des n&auml;chsten Zeitplans</li>
        <li>scheduling-schedules_event_n_valve_1_end_at - Endzeit von Zeitplan 1</li>
        <li>scheduling-schedules_event_n_valve_1_id - ID von Zeitplan 1</li>
        <li>scheduling-schedules_event_n_valve_1_start_at - Startzeit von Zeitplan 1</li>
        <li>scheduling-schedules_event_n_valve_1_weekly - Wochentage von Zeitplan 1</li>
        <li>scheduling-schedules_events_count - Anzahl angelegter Zeitpl&auml;ne</li>
        <li>scheduling-schedules_paused_until - Datum/Uhrzeit, bis wann Zeitplan pausiert ist (2038-01-18T00:00:00.000Z wird von Gardena-Cloud als dauerhaft angesehen) </li>
        <li>state - Status des Ger&auml;ts
           <ul>
               <li>geschossen - Ventil geschlossen, keine Zeitpl&auml;ne definiert</li>
               <li>geschlossen. Zeitplan dauerhaft pausiert - Ventil geschlossen, Zeitplan dauerhaft pausiert</li>
               <li>geschlossen. N&auml;chste Bew&auml;sserung: YYYY-MM-DD HH:MM - Ventil geschlossen, n&auml;chster Zeitplan-Start YYYY-MM-DDTHH:MM:00.000Z</li>
               <li>will be irrigated n minutes remaining. - watering, n minutes remaining (depending on manual button time or on pre-defined schedule)</li>
               <li>offline - Ger&auml;t ist ausgeschaltet/hat keine Verbindung</li>
               <li>Winterschlaf - Ger&auml;t ist im Winterschlaf</li>
           </ul>
        </li>
	    <li>watering-watering_timer_1_duration - Gesamt-Dauer der aktuellen Bew&auml;sserung in Sekunden</li>
        <li>watering-watering_timer_1_irrigation_left - Verbleibende Bew&auml;sserungszeit in Minuten</li>
        <li>watering-watering_timer_1_state - Status des Zeitplans</li>
        <li>watering-watering_timer_1_valve_id - Ventil-ID des Zeitplans</li>
        <li>winter_mode - Status Winterschlaf (awake/hibernate)</li>        
    </ul>
    <br><br>
    <b>Readings (model = ic24)</b>
      <ul>
        <li>device_info-category - Art des Ger&auml;ts</li>
        <li>device_info-connection_status - Verbindungsstatus (online/offline/unknown)</li>
        <li>device_info-last_time_online - Zeitpunkt der letzten Funk&uuml;bertragung</li>
        <li>device_info-manufacturer - Hersteller</li>
        <li>device_info-product - Produkttyp</li>
        <li>device_info-serial_number - Seriennummer</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - Firmware Version</li>
        <li>error-error - Fehlermeldung (tbd.)</li>
        <li>error-valve_error_0_severity - (tbd.)</li>
        <li>error-valve_error_0_type - (tbd.)</li>
        <li>error-valve_error_0_valve_id - ID des fehlerhaften Ventils</li>
        <li>...ggf. weitere Error-Readings</li>
        <li>firmware-firmware_available_version - Neue Firmware (nur wenn verf&uuml;gbar)</li>
        <li>firmware-firmware_command - Firmware-Kommando (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - Firmware Status </li>
        <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
        <li>firmware-inclusion_status - Einbindungsstatus</li>        
        <li>ic24-valves_connected - Verbundene Ventile (ID, kommagetrennt)</li>
        <li>ic24-valves_master_config - Masterventil (nur, wenn in Gardena-App definiert)</li>
        <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
        <li>radio-state - Verbindungsqualit&auml;t (schlecht/schwach/gut/Undefiniert)</li>   
        <li>scheduling-scheduled_watering_end - Endzeit des n&auml;chsten Zeitplans</li>
        <li>scheduling-scheduled_watering_end_1 - Endzeit des n&auml;chsten Zeitplans f&uuml;r Ventil 1</li>
        <li>...weitere Readings f&uuml;r Ventile 2-6</li>
        <li>scheduling-scheduled_watering_next_start - Startzeit des n&auml;chsten Zeitplans</li>
        <li>scheduling-scheduled_watering_next_start_1 - Startzeit des n&auml;chsten Zeitplans f&uuml;r Ventil 1</li>
        <li>...weitere Readings f&uuml;r Ventile 2-6</li>
        <li>scheduling-schedules_event_n_end_at - Endzeit des ersten definierten Zeitplans f&uuml;r Ventil n</li>
        <li>scheduling-schedules_event_n_id - ID des ersten definierten Zeitplans f&uuml;r Ventil n</li>
        <li>scheduling-schedules_event_n_start_at - Startzeit des ersten definierten Zeitplans f&uuml;r Ventil n</li>
        <li>scheduling-schedules_event_n_weekly - Wochentage des ersten definierten Zeitplans f&uuml;r Ventil n</li>
        <li>scheduling-schedules_events_count - Anzahl angelegter Zeitpl&auml;ne</li>
        <li>...weitere Readings f&uuml;r zus&auml;tzliche Zeitpl&auml;ne/Ventile</li>
        <li>scheduling-schedules_paused_until_1 - Datum/Uhrzeit, bis wann Zeitplan pausiert ist (2038-01-18T00:00:00.000Z wird von Gardena-Cloud als dauerhaft angesehen) </li>
        <li>...weitere Readings f&uuml;r Ventile 2-6</li>
        <li>state - Status des Ger&auml;ts
           <ul>
               <li>geschossen - Ventil geschlossen, keine Zeitpl&auml;ne definiert</li>
               <li>geschlossen. Zeitplan dauerhaft pausiert - Ventil geschlossen, Zeitplan dauerhaft pausiert</li>
               <li>geschlossen. N&auml;chste Bew&auml;sserung: YYYY-MM-DD HH:MM - Ventil geschlossen, n&auml;chster Zeitplan-Start YYYY-MM-DDTHH:MM:00.000Z</li>
               <li>wird bew&auml;ssert. n Minuten verbleibend - Bew&auml;sserung aktiv, n Minuten verbleibend (wenn 2 Ventile ge&ouml;ffnet sind, wird die l&auml;ngere Dauer angezeigt)</li>
               <li>offline - Ger&auml;t ist ausgeschaltet/hat keine Verbindung</li>
               <li>Winterschlaf - Ger&auml;t ist im Winterschlaf</li>
           </ul>
        </li>
        <li>valve-valve_name_1 - Eigener Name f&uuml;r Ventil 1</li>
        <li>...weitere Readings f&uuml;r Ventile 2-6 (if installed)</li>
	      <li>watering-watering_timer_1_duration - Gesamt-Dauer der aktuellen Bew&auml;sserung in Sekunden</li>
        <li>watering-watering_timer_1_irrigation_left - Verbleibende Dauer der aktuellen Bew&auml;sserung in Minuten</li>
        <li>watering-watering_timer_1_state - Status des Timers</li>
        <li>watering-watering_timer_1_valve_id - Ventil-ID des Timers</li>
        <li>...weitere Readings f&uuml;r weitere Ventile/Zeitpl&auml;ne</li>
        <li>winter_mode - Status Winterschlaf (awake/hibernate)</li>
    </ul>
    <br><br>
    <b>Readings (model = sensor)</b>
    <ul>
	    <li>ambient_temperature-frost_warning - Frostwarnung</li>
        <li>ambient_temperature-temperature - Umgebungstemperatur in Celsius</li>
        <li>battery-disposable_battery_status - Batteriezustand</li>
	    <li>battery-level - Ladezustand der Batterie in Prozent</li>
        <li>device_info-category - Art des Ger&auml;ts</li>
        <li>device_info-connection_status - Verbindungsstatus (online/offline/unknown)</li>
        <li>device_info-last_time_online - Zeitpunkt der letzten Funk&uuml;bertragung</li>
        <li>device_info-manufacturer - Hersteller</li>
        <li>device_info-product - Produkttyp</li>
        <li>device_info-serial_number - Seriennummer</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - Firmware Version</li>
        <li>firmware-firmware_available_version - Neue Firmware (nur wenn verf&uuml;gbar)</li>
        <li>firmware-firmware_command - Firmware-Kommando (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - Firmware Status </li>
        <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
        <li>firmware-inclusion_status - Einbindungsstatus</li>
	    <li>humidity-humidity - Feuchtigkeit in Prozent</li>
        <li>light-light - Helligkeit in Lux</li>
        <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
        <li>radio-state - Verbindungsqualit&auml;t (schlecht/schwach/gut/Undefiniert)</li>
        <li>soil_temperature-temperature - Erd-Temperatur in Celsius</li>
        <li>state - Status (Temperatur (T:), Feuchtigkeit (H:), Helligkeit (L:)|offline|Winterschlaf)</li>
        <li>winter_mode - Status Winterschlaf (awake/hibernate)</li>
    </ul>
    <br><br>
    <b>Readings (model = sensor2)</b>
    <br><br>
    "sensor2" hat keine Helligkeitsmessung oder Umgebungstemperatur, und es legt die Frost-Warnung in einem anderen Reading ab. Ansonsten ist er mehr oder weniger identisch zum "sensor".
    <br><br>
    <ul>
        <li>battery-disposable_battery_status - Batteriezustand</li>
        <li>battery-level - Ladezustand der Batterie in Prozent</li>
        <li>device_info-category - Art des Ger&auml;ts</li>
        <li>device_info-connection_status - Verbindungsstatus (online/offline/unknown)</li>
        <li>device_info-last_time_online - Zeitpunkt der letzten Funk&uuml;bertragung</li>
        <li>device_info-manufacturer - Hersteller</li>
        <li>device_info-product - Produkttyp</li>
        <li>device_info-serial_number - Seriennummer</li>
        <li>device_info-sgtin - (tbd.)</li>
        <li>device_info-version - Firmware Version</li>
        <li>firmware-firmware_available_version - Neue Firmware (nur wenn verf&uuml;gbar)</li>
        <li>firmware-firmware_command - Firmware-Kommando (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - Firmware Status </li>
        <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
        <li>firmware-inclusion_status - Einbindungsstatus</li>
	    <li>humidity-humidity - Feuchtigkeit in Prozent</li>
        <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
        <li>radio-state - Verbindungsqualit&auml;t (schlecht/schwach/gut/Undefiniert)</li>
        <li>soil_model-model_definition - (tbd.)</li>
        <li>soil_model-model_status - (tbd.)</li>
        <li>soil_temperature-frost-warning - Frostwarnung</li>
        <li>soil_temperature-temperature - Erd-Temperatur in Celsius</li>
        <li>state - Status (Temperatur (T:), Feuchtigkeit (H:), Helligkeit (L:)|offline|Winterschlaf)</li>
        <li>winter_mode - Status Winterschlaf (awake/hibernate)</li>
    </ul>
    <br><br>
    <b>Readings (model = power)</b>
    <ul>
      <li>(tbd.)</li>
    </ul>
    <br><br>
    <b>Readings (model = electronic_pressure_pump)</b>
    <ul>
      <li>error-error - Fehlermeldung (tbd.)</li>
      <li>error-valve_error_1_severity - (tbd.)</li>
      <li>error-valve_error_1_type - (tbd.)</li>
      <li>error-valve_error_1_valve_id - ID des fehlerhaften Ventils</li>
      <li>firmware-firmware_available_version - Neue Firmware (nur wenn verf&uuml;gbar)</li>
      <li>firmware-firmware_command - Firmware-Kommando (idle/firmware_cancel/firmware_upload/unsupported)</li>
      <li>firmware-firmware_status - Firmware Status </li>
      <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
      <li>firmware-inclusion_status - Einbindungsstatus</li>    
      <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
      <li>radio-state - Verbindungsqualit&auml;t (schlecht/schwach/gut/Undefiniert)</li>  

      <li>scheduling-schedules_event_n__end_at - Endzeit des ersten definierten Zeitplans f&uuml;r Ventil n</li>
      <li>scheduling-schedules_event_n_id - ID des ersten definierten Zeitplans f&uuml;r Ventil n</li>
      <li>scheduling-schedules_event_n_start_at - Startzeit des ersten definierten Zeitplans f&uuml;r Ventil n</li>
      <li>scheduling-schedules_event_n_weekly - Wochentage des ersten definierten Zeitplans f&uuml;r Ventil n</li>
      <li>scheduling-schedules_events_count - Anzahl angelegter Zeitpl&auml;ne</li>
      <li>...weitere Readings f&uuml;r zus&auml;tzliche Zeitpl&auml;ne/Ventile</li>
      <li>scheduling-schedules_paused_until_1 - Datum/Uhrzeit, bis wann Zeitplan pausiert ist (2038-01-18T00:00:00.000Z wird von Gardena-Cloud als dauerhaft angesehen) </li>
        
      <li>state - Status des Ger&auml;ts
         <ul>
             <li>geschossen - Ventil geschlossen, keine Zeitpl&auml;ne definiert</li>
             <li>geschlossen. Zeitplan dauerhaft pausiert - Ventil geschlossen, Zeitplan dauerhaft pausiert</li>
             <li>geschlossen. N&auml;chste Bew&auml;sserung: YYYY-MM-DD HH:MM - Ventil geschlossen, n&auml;chster Zeitplan-Start YYYY-MM-DDTHH:MM:00.000Z</li>
             <li>wird bew&auml;ssert. n Minuten verbleibend - Bew&auml;sserung aktiv, n Minuten verbleibend (wenn 2 Ventile ge&ouml;ffnet sind, wird die l&auml;ngere Dauer angezeigt)</li>
             <li>offline - Ger&auml;t ist ausgeschaltet/hat keine Verbindung</li>
             <li>Winterschlaf - Ger&auml;t ist im Winterschlaf</li>
         </ul>
      </li>
      
      <li>watering-watering_timer_1_duration - Gesamt-Dauer der aktuellen Bew&auml;sserung in Sekunden</li>
      <li>watering-watering_timer_1_irrigation_left - Verbleibende Dauer der aktuellen Bew&auml;sserung in Minuten</li>
      <li>watering-watering_timer_1_state - Status des Timers</li>
      <li>watering-watering_timer_1_valve_id - Ventil-ID des Timers</li>
      <li>winter_mode - Status Winterschlaf (awake/hibernate)</li>
      <li><strong>Flussmengen und Lekage-Erkennung</strong></li>
      <li>flow-dripping_alert sixty</li>
      <li>flow-flow_rate - FLussrate (600)</li>
      <li>flow-flow_since_last_reset 13</li>
      <li>flow-flow_total 20</li>
      <li>leakage_detection - Status der Lekage-Konfiguration</li>
      
      <li><strong>Status des Ger&auml;tes Temperataur und Druck-Einstellungen</strong></li>
      <li>outlet_pressure-outlet_pressure - </li>
      <li>outlet_pressure-outlet_pressure_max 5.8</li>
      <li>outlet_temperature-frost_warning - Frostwarnung</li>
      <li>outlet_temperature-temperature - Außentemperatur</li>
      <li>outlet_temperature-temperature_max - tbd. 100</li>
      <li>outlet_temperature-temperature_min - tbd. 0</li>
      
      <li><strong>Pumpen-Konfiguration</strong></li>
      <li>operating_mode - Modus der Pumpe</li>
      
      <li><strong>Pumpenstatus aktuell</strong></li>
      <li>pump-mode - Modus der Pumpe</li>
      <li>pump-operating_mode – Pumpenmodus automatic|scheduled</li>
      <li>pump-pump_on_off - Pumpenzustand on|off</li>
      <li>pump-pump_state - tbd</li>
      <li>pump-turn_on_pressure - Einschaltdruck 2.0 - 3.0</li>

    </ul>
    <br><br><br>
</ul> 
    <b>Attribute (alle Modelle)</b>
    <ul>
      <li>IODev - Name des GardenaSmartBridge Devices</li>
      <li>model watering_computer|sensor|sensor2|mower|ic24|power|electronic_pressure_pump - Modell des GardenaSmartDevice</li>
      <li>readingValueLanguage en|de - Sprache der Readings englisch oder deutsch (default: englisch, es sei denn, Deutsch ist als globale Sprache gesetzt)</li>
    </ul>
    <br><br><br> 
    <b>set (model = mower)</b>
    <ul>
        <li>parkUntilFurtherNotice - Parken des M&auml;hers und Aussetzen des Zeitplans</li>
        <li>parkUntilNextTimer - Parken bis zum n&auml;chsten Start nach Zeitplan</li>
        <li>startOverrideTimer n - Manuelles M&auml;hen f&uuml;r n Minuten (z.B. 60 = 1h, 1440 = 24h, 4320 = 72h)</li>
        <li>startResumeSchedule - Zeitplan wieder aktivieren</li>
        <li>startPoint enable|disable 1|2|3 - Aktiviert oder deaktiviert einen vordefinierten Startbereich</li>
      <ul>
        <li>set NAME startpoint enable 1</li>
        <li>set NAME startpoint disable 3 enable 1</li>
      </ul>
      <li>winter_mode hibernate|awake - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
    </ul>
    <br><br>
    <b>set (model = watering_computer)</b> 
    <ul>
        <li>cancelOverride - (Manuelle) Bew&auml;sserung stoppen</li>
        <li>manualButtonTime n - Bew&auml;sserungsdauer f&uuml;r manuellen Knopf auf n Minuten setzen (0 schaltet den Knopf aus)</li>
        <li>manualOverride n - Manuelle Bew&auml;sserung f&uuml;r n Minuten</li>
        <li>resetValveErrors - Ventilfehler zur&uuml;cksetzen</li>
        <li>resumeSchedule - Zeitplan wieder aktivieren</li>
        <li>stopSchedule n - Zeitplan anhalten f&uuml;r n Stunden (Default: 2038-01-18T00:00:00.000Z, durch Gardena-App als "dauerhaft" interpretiert)</li>
        <li>winter_mode hibernate|awake - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
    </ul>
    <br><br>
    <b>set (model = ic24)</b> 
    <ul>
        <li>cancelOverrideValve1 - (Manuelle) Bew&auml;sserung an Ventil 1 stoppen </li>
        <li>cancelOverrideValve2 - (Manuelle) Bew&auml;sserung an Ventil 2 stoppen </li>
        <li>cancelOverrideValve3 - (Manuelle) Bew&auml;sserung an Ventil 3 stoppen </li>
        <li>cancelOverrideValve4 - (Manuelle) Bew&auml;sserung an Ventil 4 stoppen </li>
        <li>cancelOverrideValve5 - (Manuelle) Bew&auml;sserung an Ventil 5 stoppen </li>
        <li>cancelOverrideValve6 - (Manuelle) Bew&auml;sserung an Ventil 6 stoppen </li>
        <li>closeAllValves - Alle Ventile schliessen</li>
        <li>manualDurationValve1 n - Ventil 1 f&uuml;r n Minuten &ouml;ffnen</li>
        <li>manualDurationValve2 n - Ventil 2 f&uuml;r n Minuten &ouml;ffnen</li>
        <li>manualDurationValve3 n - Ventil 3 f&uuml;r n Minuten &ouml;ffnen</li>
        <li>manualDurationValve4 n - Ventil 4 f&uuml;r n Minuten &ouml;ffnen</li>
        <li>manualDurationValve5 n - Ventil 5 f&uuml;r n Minuten &ouml;ffnen</li>
        <li>manualDurationValve6 n - Ventil 6 f&uuml;r n Minuten &ouml;ffnen</li>
        <li>resetValveErrors - Ventilfehler zur&uuml;cksetzen</li>
        <li>resumeScheduleValve n - Zeitplan f&uuml;r Ventil n wieder aktivieren</li>
        <li>stopScheduleValve n m - Zeitplan f&uuml;r Ventil n anhalten f&uuml;r m Stunden (Default: 2038-01-18T00:00:00.000Z durch Gardena-App als "dauerhaft" interpretiert)</li>
        <li>winter_mode hibernate|awake - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
    </ul>
    <br><br>
    <b>set (model = sensor)</b>
    <ul>
        <li>refresh temperature|humidity|light - Sensorwert f&uuml;r Temperatur, Feuchtigkeit oder Helligkeit aktualisieren</li>
        <li>winter_mode hibernate|awake - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
    </ul>
    <br><br>
    <b>set (model = sensor2)</b>
    <ul>
        <li>refresh temperature|humidity - Sensorwert f&uuml;r Temperatur oder Feuchtigkeit aktualisieren</li>
        <li>winter_mode hibernate|awake - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
    </ul>
    <br><br>
    <b>set (model = power)</b>
    <ul>
        <li>(tbd.)</li>
    </ul>
    <br><br>
    <b>set (model = electronic_pressure_pump)</b>
    <ul>
        <li>manualOverride n - Bew&auml;sserungdauer in Minuten</li>
        <li>cancelOverride - (Manuelle) Bew&auml;sserung stoppen</li>
        <li>operating_mode - Steuert den Operation Mode. Zeitgesteuert wird in Kombination mit dem Wochenzeitplan oder mit "manualOverride" genutzt, automatisch bedeutet, dass die Pumpe immer aktiv ist und die Bewässerung abhängig vom Wert "Einschaltdruck" startet. automatic|scheduled </li>
        <li>leakage_detection - Steuert die Lekage-Erkennung.</br> Hierdurch wird eine Pumpenabschaltung erreicht, sollte die Pumpe unkontrollierten Wasserverlust feststellen.  watering|washing_machine|domestic_water_supply|off</li>
        <li>turn_on_pressure - Einschaltdruck 2.0 - 3.0 Steuert den Einschaltdruck in Scheduled und Automatic Mode. Fällt der Druck bei der Bewässerung unter diese wert, startet die Pumpe, ist der Wert dauerhaft über diesem Wert und es finden kein Durchfluss statt, geht die Pumpe in Standby</li>
        <li>resetValveErrors - Ventilfehler zur&uuml;cksetzen</li>
        <li>winter_mode hibernate|awake - Winterschlaf aktivieren oder Ger&auml;t aufwecken</li>
    </ul>


=end html_DE


=for :application/json;q=META.json 74_GardenaSmartDevice.pm
{
  "abstract": "Modul to control GardenaSmart Devices",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Steuerung von Gardena Smart Ger&aumlten"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Garden",
    "Gardena",
    "Smart"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.6.1",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
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
        "Meta": 0,
        "JSON": 0,
        "Time::Local": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut

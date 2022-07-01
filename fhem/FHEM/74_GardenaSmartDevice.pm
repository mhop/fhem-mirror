###############################################################################
#
# Developed with VSCodium and richterger perl plugin.
#
#  (c) 2017-2022 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Michael (mbrak)       Thanks for Commandref
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
          makeDeviceName)
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
    $hash->{helper}{operating_mode_id}         = '';
    $hash->{helper}{leakage_detection_id}      = '';
    $hash->{helper}{turn_on_pressure_id}       = '';


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
    
    my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat,
        $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);

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
    elsif ( lc $cmd eq 'operating_mode') {
      my $op_mode = $aArg->[0];
      $payload = '"settings":{"name":"operating_mode",'
                 .'"value":"'.$op_mode.'",'
                 .'"device":"'
                 . $hash->{DEVICEID}.'"}';
      $abilities = 'watering_pressure_pump_settings';
      $service_id = $hash->{helper}->{ 'operating_mode_id' };
    }
    elsif ( lc $cmd eq 'leakage_detection') {
      my $leakdetection_mode = $aArg->[0];
      $payload = '"settings":{"name":"leakage_detection",'
                 .'"value":"'.$leakdetection_mode.'",'
                 .'"device":"'
                 . $hash->{DEVICEID}.'"}';
      $abilities = 'watering_pressure_pump_settings';
      $service_id = $hash->{helper}->{ 'leakage_detection_id' };
    }
    elsif ( lc $cmd eq 'turn_on_pressure') {
      my $turnonpressure = $aArg->[0];
      $payload = '"settings":{"name":"turn_on_pressure",'
                 .'"value":"'.$turnonpressure.'",'
                 .'"device":"'
                 . $hash->{DEVICEID}.'"}';
      $abilities = 'watering_pressure_pump_settings';
      $service_id = $hash->{helper}->{ 'turn_on_pressure_id' };
    }
    elsif ( lc $cmd eq 'resetvalveerrors') {
      $payload = '"name":"reset_valve_errors",'
                 .' "parameters": {}';
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
'manualOverride:slider,1,1,59 cancelOverride:noArg resumeSchedule:noArg stopSchedule manualButtonTime:slider,0,2,100'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'watering_computer' );

        $list .=
'closeAllValves:noArg stopScheduleValve:selectnumbers,1,1,6,0,lin resumeScheduleValve:selectnumbers,1,1,6,0,lin manualDurationValve1:slider,1,1,90 manualDurationValve2:slider,1,1,90 manualDurationValve3:slider,1,1,90 manualDurationValve4:slider,1,1,90 manualDurationValve5:slider,1,1,90 manualDurationValve6:slider,1,1,90 cancelOverrideValve1:noArg cancelOverrideValve2:noArg cancelOverrideValve3:noArg cancelOverrideValve4:noArg cancelOverrideValve5:noArg cancelOverrideValve6:noArg'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'ic24' );

        $list .= 'manualOverride:slider,1,1,90 cancelOverride:noArg operating_mode:automatic,scheduled leakage_detection:watering,washing_machine,domestic_water_supply,off turn_on_pressure:slider,2,0.2,3.0,1 resetValveErrors:noArg'
          if ( AttrVal( $name, 'model', 'unknown' ) eq 'electronic_pressure_pump' );

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
        return "Unknown argument $cmd, choose one of $list";
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

    my $name      = $hash->{NAME};
    my $abilities = scalar( @{ $decode_json->{abilities} } );
    my $settings  = scalar( @{ $decode_json->{settings} } );

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
                    RigReadingsValue( $hash, $propertie->{value} )
                  )
                  if ( defined( $propertie->{value} )
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
                    && ref( $propertie->{value} ) ne "HASH" );

                readingsBulkUpdateIfChanged(
                    $hash,
                    $decode_json->{abilities}[$abilities]{name} . '-'
                      . $propertie->{name},
                    RigReadingsValue( $hash, $propertie->{value} )
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
                    Time::Piece->strptime(
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
                    while ( my ( $r, $v ) = each %{ $propertie->{value} } ) {
                      if ( ref( $v ) ne "HASH" ) {
                            readingsBulkUpdate(
                              $hash,
                              $decode_json->{abilities}[$abilities]{name} . '-'
                                . $propertie->{name} . '_'
                                . $r,
                                RigReadingsValue( $hash, $v )
                            );
                        } else {
                          while ( my ( $i_r, $i_v ) = each %{ $v } ) {
                            readingsBulkUpdate(
                              $hash,
                              $decode_json->{abilities}[$abilities]{name} . '-'
                              . $propertie->{name} . '_'
                              . $r . '_' . $i_r,
                              RigReadingsValue( $hash, $i_v )
                            );
                          }
                        }
                    }
                }
            }
        }

        $abilities--;
    } while ( $abilities >= 0 );

    my $winter_mode;

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
                || $decode_json->{settings}[$settings]{name} eq 'leakage_detection' 
                || $decode_json->{settings}[$settings]{name} eq 'turn_on_pressure' )
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
            if ( $decode_json->{settings}[$settings]{name} eq 'schedules_paused_until' ) {
              readingsBulkUpdateIfChanged( $hash, 'scheduling-schedules_paused_until',
                    $decode_json->{settings}[$settings]{value} );
            }

            # save electronid pressure pump settings as readings
            if ( $decode_json->{settings}[$settings]{name} eq 'operating_mode' 
                || $decode_json->{settings}[$settings]{name} eq 'leakage_detection' 
                || $decode_json->{settings}[$settings]{name} eq 'turn_on_pressure' ) {
                readingsBulkUpdateIfChanged( $hash, $decode_json->{settings}[$settings]{name},
                    $decode_json->{settings}[$settings]{value} );

            }
            # save winter mode as reading

            if ( $decode_json->{settings}[$settings]{name} eq 'winter_mode' ) {
                readingsBulkUpdateIfChanged( $hash, 'winter_mode',
                    $decode_json->{settings}[$settings]{value} );

                $winter_mode = $decode_json->{settings}[$settings]{value};
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

    #online state water control
    # zeitplan   -> dauert pausiert wenn 2038-01-18T00:00:00.000Z

    # watering-watering_timer_1_state idle | scheduled | manual
    # watering-watering_timer_1_duration  0    in sec
    # scheduling-scheduled_watering_next_start  XXX 
    # scheduling-scheduled_watering_end   | end  < NOW && duration = 0 => abbruch manuell
    # scheduling-schedules_paused_until

   
    # 1. Ventil geschlossen, Zeitplan pausiert.
    #   App zeigt: nichts (wenn vorher ein Zeitplan abgebrochen wurde, steht da "Unterbrochen   xx:yy - zz:aa")
    # 2. Ventil geschlossen, Zeitplan aktiv.
    #   App zeigt: "Nächste Bewässerung heute um xx:yy Uhr" (wenn vorher ein Zeitplan abgebrochen wurde, steht da vorher auch "Unterbrochen   xx:yy - zz:aa")
    # 3. Ventil manuell geoeffnet, späterer Zeitplan aktiv.
    #   Wird bewässert   xx Minuten verbleibend" und "Nächste Bewässerung   heute um xx:yy Uhr"
    # 4. Ventil manuell geoeffnet, Zeitpläne deaktiviert.
    #   App zeigt: "Wird bewässert   xx Minuten verbleibend"
    if ( AttrVal( $name, 'model', 'unknown' ) eq 'watering_computer' ){
         my $state_string = ReadingsVal( $name, 'watering-watering_timer_1_duration', 0 ) =~
              m{\A[1-9]([0-9]+)?\z}xms
            # offen
            ? 
              ( ReadingsVal($name, 'scheduling-schedules_paused_until', '' ) eq '' )
              # leer ( zeitplan aktiv ... ) 
              ? sprintf( (RigReadingsValue($hash, 'will be irrigated %.f minutes remaining.').' '.RigReadingsValue($hash, 'next watering: %s')), (ReadingsVal( $name, 'watering-watering_timer_1_duration', 0 )/60), RigReadingsValue($hash, ReadingsVal($name, 'scheduling-scheduled_watering_next_start', '')) ) 
              # zeitplan pausiert
              : 
                ( ReadingsVal($name, 'scheduling-schedules_paused_until', '') eq '2038-01-18T00:00:00.000Z')
                # pause bis  dauerhaft
                ? sprintf( (RigReadingsValue($hash, 'will be irrigated %.f minutes remaining.').' '.RigReadingsValue($hash , 'schedule permanently paused')), (ReadingsVal( $name, 'watering-watering_timer_1_duration', 0 )/60) )
                # naechter termin
                : sprintf( RigReadingsValue($hash , 'paused until %s'), RigReadingsValue($hash, ReadingsVal($name, 'scheduling-schedules_paused_until', '')) )
            # zu
            :
              ( ReadingsVal($name, 'scheduling-schedules_paused_until', '' ) eq '' )
              # zeitplan aktiv
              ? sprintf( (RigReadingsValue($hash, 'closed') .'. '.RigReadingsValue($hash, 'next watering: %s')),  RigReadingsValue($hash, ReadingsVal($name, 'scheduling-scheduled_watering_next_start', '') ) )
              # zeitplan pausiert
              : RigReadingsValue($hash, 'closed')
            ;
      # state offline | override
      $state_string = 'offline' if ($online_state eq 'offline');
 
      readingsBulkUpdate(
        $hash, 'state',  RigReadingsValue( $hash, $state_string ) );
    }

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

# if ( $online_state eq 'offline') {
#   readingsBulkUpdate( $hash, 'humidity-humidity', '-1' );
#   readingsBulkUpdate( $hash, 'ambient_temperature-temperature', '-1' ) if (ReadingsVal($name, 'device_info-category', 'unknown') eq 'sensor');
#   readingsBulkUpdate( $hash, 'light-light', '-1' ) if (ReadingsVal($name, 'device_info-category', 'unknown') eq 'sensor');
# }
        #online state sensor I II
        readingsBulkUpdate( $hash, 'state',
            $online_state eq 'online' ? RigReadingsValue( $hash, $state_string) : RigReadingsValue( $hash, 'offline') );
    }

    readingsBulkUpdate(
        $hash, 'state',
        'scheduled watering next start: '
          . (
            ReadingsVal(
                $name, 'scheduling-scheduled_watering_next_start',
                'no timer'
            )
          )
    ) if ( AttrVal( $name, 'model', 'unknown' ) eq 'ic24' );

    readingsBulkUpdate( $hash, 'state',
        ReadingsVal( $name, 'power-power_timer', 'no info from power-timer' ) )
      if ( AttrVal( $name, 'model', 'unknown' ) eq 'power' );

    #electronic water pump
    if ( AttrVal( $name, 'model', 'unknown' ) eq 'electronic_pressure_pump' ) {  #        | ok | pump_not_filled (Pumpe nicht gefüllt)
         my $state_string = ReadingsVal( $name, 'watering-watering_timer_1_duration', 0 ) =~
              m{\A[1-9]([0-9]+)?\z}xms
            # offen
            ? 
              ( ReadingsVal($name, 'scheduling-schedules_paused_until', '' ) eq '' )
              # leer ( zeitplan aktiv ... ) 
              ? sprintf( (RigReadingsValue($hash, 'will be irrigated %.f minutes remaining.').' '.RigReadingsValue($hash, 'next watering: %s')), (ReadingsVal( $name, 'watering-watering_timer_1_duration', 0 )/60), RigReadingsValue($hash, ReadingsVal($name, 'scheduling-scheduled_watering_next_start', '')) ) 
              # zeitplan pausiert
              : 
                ( ReadingsVal($name, 'scheduling-schedules_paused_until', '') eq '2038-01-18T00:00:00.000Z')
                # pause bis  dauerhaft
                ? sprintf( (RigReadingsValue($hash, 'will be irrigated %.f minutes remaining.').' '.RigReadingsValue($hash , 'schedule permanently paused')), (ReadingsVal( $name, 'watering-watering_timer_1_duration', 0 )/60) )
                # naechter termin
                : sprintf( RigReadingsValue($hash , 'paused until %s'), RigReadingsValue($hash, ReadingsVal($name, 'scheduling-schedules_paused_until', '')) )
            # zu
            :
              ( ReadingsVal($name, 'scheduling-schedules_paused_until', '' ) eq '' )
              # zeitplan aktiv
              ? sprintf( (RigReadingsValue($hash, 'closed') .'. '.RigReadingsValue($hash, 'next watering: %s')),  RigReadingsValue($hash, ReadingsVal($name, 'scheduling-scheduled_watering_next_start', '') ) )
              # zeitplan pausiert
              : RigReadingsValue($hash, 'closed')
            ;
      # state offline | override
      $state_string = 'offline' if ($online_state eq 'offline');
      # check valv error, override state 
      my $error_type = ReadingsVal( $name, 'error-valve_error_1_type', 'ok' );
      $state_string = ( $error_type ne 'ok' ) ? $error_type : $state_string;
  
      readingsBulkUpdate(
        $hash, 'state',  RigReadingsValue( $hash, $state_string ) );
    }
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
        'ok_cutting'                     => 'mähen',
        'paused'                         => 'pausiert',
        'ok_searching'                   => 'suche Ladestation',
        'ok_charging'                    => 'lädt',
        'ok_leaving'                     => 'unterwegs zum Startpunkt',
        'wait_updating'                  => 'wird aktualisiert ...',
        'wait_power_up'                  => 'wird eingeschaltet ...',
        'parked_timer'                   => 'geparkt nach Zeitplan',
        'parked_park_selected'           => 'geparkt',
        'off_disabled'                   => 'der Mäher ist ausgeschaltet',
        'off_hatch_open'                 => 'deaktiviert. Abdeckung ist offen oder PIN-Code erforderlich',
        'unknown'                        => 'unbekannter Status',
        'error'                          => 'Fehler',
        'error_at_power_up'              => 'Neustart ...',
        'off_hatch_closed'               => 'Deaktiviert. Manueller Start erforderlich',
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
        'guide_calibration_accomplished' => 'Kalibrierung des Suchkabels beendet',
        'guide_calibration_failed'       => 'Kalibrierung des Suchkabels fehlgeschlagen',
        'temporary_battery_problem'      => 'kurzzeitiges Batterieproblem',
        'battery_problem'                => 'Batterieproblem',
        'alarm_mower_switched_off'       => 'Alarm! Mäher ausgeschalten',
        'alarm_mower_stopped'            => 'Alarm! Mäher gestoppt',
        'alarm_mower_lifted'             => 'Alarm! Mäher angehoben',
        'alarm_mower_tilted'             => 'Alarm! Mäher gekippt',
        'connection_changed'             => 'Verbindung geändert',
        'connection_not_changed'         => 'Verbindung nicht geändert',
        'com_board_not_available'        => 'COM Board nicht verfügbar',
        'slipped'                        => 'rutscht',
        'out_of_operation'               => 'ausser Betrieb',
        'replace_now'                    => 'kritischer Batteriestand, wechseln Sie jetzt',
        'low'                            => 'niedrig',
        'ok'                             => 'ok',
        'no_source'                      => 'ok',
        'mower_charging'                 => 'Mäher wurde geladen',
        'completed_cutting_autotimer'    => 'Sensor Control erreicht',
        'week_timer'                     => 'Wochentimer erreicht',
        'countdown_timer'                => 'Stoppuhr Timer',
        'undefined'                      => 'unklar',
        'unknown'                        => 'unklar',
        'status_device_unreachable'      => 'Gerät ist nicht in Reichweite',
        'status_device_alive'            => 'Gerät ist in Reichweite',
        'bad'                            => 'schlecht',
        'poor'                           => 'schwach',
        'good'                           => 'gut',
        'undefined'                      => 'unklar',
        'idle'                           => 'nichts zu tun',
        'firmware_cancel'                => 'Firmwareupload unterbrochen',
        'firmware_upload'                => 'Firmwareupload',
        'unsupported'                    => 'nicht unterstützt',
        'up_to_date'                     => 'auf dem neusten Stand',
        'mower'                          => 'Mäher',
        'watering_computer'              => 'Bewässerungscomputer',
        'no_frost'                       => 'kein Frost',
        'open'                           => 'offen',
        'closed'                         => 'geschlossen',
        'included'                       => 'inbegriffen',
        'active'                         => 'aktiv',
        'inactive'                       => 'nicht aktiv',
        'hibernate'                      => 'Winterschlaf',
        'awake'                          => 'Aufgewacht',
        'schedule permanently paused'    => 'Zeitplan dauerhaft pausiert',
        'paused until %s'                => 'pausiert bis %s',        
        'will be irrigated %.f minutes remaining.'=> 'Wird bewässert. %.f Minuten verbleibend.',
        'next watering: %s'              => 'Nächste Bewässerung: %s',
        'pump_not_filled'                => 'Pumpe nicht gefüllt',
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
=item summary_DE Modul zur Steuerung von GardenaSmartger&aumlten

=begin html

<a name="GardenaSmartDevice"></a>
<h3>GardenaSmartDevice</h3>
<ul>
    In combination with GardenaSmartBridge this FHEM Module controls the GardenaSmart Device using the GardenaCloud
    <br><br>
    Once the Bridge device is created, the connected devices are automatically recognized and created in FHEM. <br>
    From now on the devices can be controlled and changes in the GardenaAPP are synchronized with the state and readings of the devices.
    <a name="GardenaSmartDevicereadings"></a>
    <br><br><br>
    <b>Readings</b>
    <ul>
        <li>battery-charging - Indicator if the Battery is charged (0/1) or with newer Firmware (false/true)</li>
        <li>battery-level - load percentage of the Battery</li>
        <li>battery-rechargeable_battery_status - healthyness of the battery (out_of_operation/replace_now/low/ok)</li>
        <li>device_info-category - category of device (mower/watering_computer)</li>
        <li>device_info-last_time_online - timestamp of last radio contact</li>
        <li>device_info-manufacturer - manufacturer</li>
        <li>device_info-product - product type</li>
        <li>device_info-serial_number - serial number</li>
        <li>device_info-sgtin - </li>
        <li>device_info-version - firmware version</li>
        <li>firmware-firmware_command - firmware command (idle/firmware_cancel/firmware_upload/unsupported)</li>
        <li>firmware-firmware_status - firmware status </li>
        <li>firmware-firmware_update_start - indicator when a firmwareupload is started</li>
        <li>firmware-firmware_upload_progress - progress indicator of firmware update</li>
        <li>firmware-inclusion_status - inclusion status</li>
        <li>internal_temperature-temperature - internal device temperature</li>
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
        <li>mower-manual_operation - (0/1) or with newer Firmware (false/true)</li>
        <li>mower-override_end_time - manual override end time</li>
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
        <li>mower-status - mower state (see state)</li>
        <li>mower-timestamp_next_start - timestamp of next scheduled start</li>
        <li>radio-connection_status - state of connection</li>
        <li>radio-quality - percentage of the radio quality</li>
        <li>radio-state - radio state (bad/poor/good/undefined)</li>
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
        </ul>
        </li>
    </ul>
    <br><br>
    <a name="GardenaSmartDeviceattributes"></a>
    <b>Attributes</b>
    <ul>
        <li>readingValueLanguage - Change the Language of Readings (de,en/if not set the default is english and the global language is not set at german) </li>
        <li>model - </li>
    </ul>
    <br><br>
    <a name="GardenaSmartDeviceset"></a>
    <b>set</b>
    <ul>
      <li>winter_mode - awake | hibernate</li>
    </ul>
    <ul>
        <h3>mower</h3>
        <li>parkUntilFurtherNotice</li>
        <li>parkUntilNextTimer</li>
        <li>startOverrideTimer - (in minutes, 60 = 1h, 1440 = 24h, 4320 = 72h)</li>
        <li>startResumeSchedule</li>
        <li>startpoint enable|disable 1|2|3 - enables or disables one or more predefined start points</li>
        <ul>
            <li>set NAME startpoint enable 1</li>
            <li>set NAME startpoint disable 3 enable 1</li>
        </ul>
        <h3>irrigation control</h3>
        <li>resumeScheduleValve - start schedule irrigation on valve n</li>
        <li>stopScheduleValve - stop schedule irrigation on valve n  (Default: 2038-01-18T00:00:00.000Z) | optional params hours (now + hours)</li>
        <li>closeAllValves - close all valves</li>
        <h3>water control</h3>
        <li>manualButtonTime - set manual time for button press (in minutes) 0 disable button</li>
        <li>stopSchedule - stop schedule for now + n hours (Default: 2038-01-18T00:00:00.000Z)</li>
        <li>resumeSchedule - resume schedule</li>
    </ul>
</ul>

=end html
=begin html_DE

<a name="GardenaSmartDevice"></a>
<h3>GardenaSmartDevice</h3>
<ul>
    Zusammen mit dem Device GardenaSmartDevice stellt dieses FHEM Modul die Kommunikation zwischen der GardenaCloud und Fhem her.
    <br><br>
    Wenn das GardenaSmartBridge Device erzeugt wurde, werden verbundene Ger&auml;te automatisch erkannt und in Fhem angelegt.<br> 
    Von nun an k&ouml;nnen die eingebundenen Ger&auml;te gesteuert werden. &Auml;nderungen in der APP werden mit den Readings und dem Status syncronisiert.
    <a name="GardenaSmartDevicereadings"></a>
    </ul>
    <br>
    <ul>
    <b>Readings</b>
    <ul>
        <li>battery-charging - Ladeindikator (0/1) oder mit neuerer Firmware (false/true)</li>
        <li>battery-level - Ladezustand der Batterie in Prozent</li>
        <li>battery-rechargeable_battery_status - Zustand der Batterie (Ausser Betrieb/Kritischer Batteriestand, wechseln Sie jetzt/Niedrig/oK)</li>
        <li>device_info-category - Eigenschaft des Ger&auml;tes (M&auml;her/Bew&auml;sserungscomputer/Bodensensor)</li>
        <li>device_info-last_time_online - Zeitpunkt der letzten Funk&uuml;bertragung</li>
        <li>device_info-manufacturer - Hersteller</li>
        <li>device_info-product - Produkttyp</li>
        <li>device_info-serial_number - Seriennummer</li>
        <li>device_info-sgtin - </li>
        <li>device_info-version - Firmware Version</li>
        <li>firmware-firmware_command - Firmware Kommando (Nichts zu tun/Firmwareupload unterbrochen/Firmwareupload/nicht unterst&uuml;tzt)</li>
        <li>firmware-firmware_status - Firmware Status </li>
        <li>firmware-firmware_update_start - Firmwareupdate (0/1) oder mit neuerer Firmware (false/true)</li>
        <li>firmware-firmware_upload_progress - Firmwareupdatestatus in Prozent</li>
        <li>firmware-inclusion_status - Einbindungsstatus</li>
        <li>internal_temperature-temperature - Interne Ger&auml;te Temperatur</li>
        <li>mower-error - Aktuelle Fehler Meldung
        <ul>
            <li>Kein Fehler</li>
            <li>Au&szlig;erhalb des Arbeitsbereichs</li>
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
            <li>Problem Sto&szlig;sensor hinten</li>
            <li>Problem Sto&szlig;sensor vorne</li>
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
            <li>Verbindung geändert</li>
            <li>Verbindung nicht ge&auml;ndert</li>
            <li>COM board nicht verf&uuml;gbar</li>
            <li>Rutscht</li>
        </ul>
        </li>
        <li>mower-manual_operation - Manueller Betrieb (0/1) oder mit neuerer Firmware (false/true)</li>
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
        <li>mower-timestamp_next_start - Zeitpunkt des n&auml;chsten geplanten Starts</li>
        <li>radio-connection_status - Status der Funkverbindung</li>
        <li>radio-quality - Indikator f&uuml;r die Funkverbindung in Prozent</li>
        <li>radio-state - radio state (schlecht/schwach/gut/Undefiniert)</li>
        <li>state - Staus des M&auml;hers
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
        </ul>
        </li>
    </ul>
    <br><br>
    <a name="GardenaSmartDeviceattributes"></a>
    <b>Attribute</b>
    <ul>
        <li>readingValueLanguage - &Auml;nderung der Sprache der Readings (de,en/wenn nichts gesetzt ist, dann Englisch es sei denn deutsch ist als globale Sprache gesetzt) </li>
        <li>model - </li>
    </ul>
    <a name="GardenaSmartDeviceset"></a>
    <b>set</b>
    <ul>
      <li>winter_mode - aufw&auml;cken (awake)| winterschlaf (hibernate)</li>
    </ul>
    <ul>
        <h3>m&auml;her</h3>
        <li>parkUntilFurtherNotice - Parken des M&auml;hers unter Umgehung des Zeitplans</li>
        <li>parkUntilNextTimer - Parken bis zum n&auml;chsten Zeitplan</li>
        <li>startOverrideTimer - Manuelles m&auml;hen (in Minuten, 60 = 1h, 1440 = 24h, 4320 = 72h)</li>
        <li>startResumeSchedule - Weiterf&uuml;hrung des Zeitplans</li>
        <li>startpoint enable|disable 1|2|3 - Aktiviert oder deaktiviert einen vordefinierten Startbereich</li>
        <ul>
            <li>set NAME startpoint enable 1</li>
            <li>set NAME startpoint disable 3 enable 1</li>
        </ul>
        <h3>irrigation control</h3>
        <li>resumeScheduleValve - Startet Bew&aauml;sserung am Ventil n nach Zeitplan</li>
        <li>stopScheduleValve - Setzt Bew&aauml;sserung am Ventil n aus (Default: 2038-01-18T00:00:00.000Z) | Optionaler Parameter Stunden (Jetzt + Stunden)</li>
        <li>closeAllValves - Stopt Bew&aauml;sserung an allen Ventilen </li> 
        <h3>water control</h3>
        <li>manualButtonTime - setzt die Dauer f&uuml;r den manuellen Knopf (in Minuten) 0 Schaltet den Knopf aus</li>
        <li>stopSchedule - Halte Zeitplan an für x Stunden - (Default: 2038-01-18T00:00:00.000Z)</li>
        <li>resumeSchedule - Weiterf&uuml;hrung des Zeitplans</li>
    </ul>
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
  "version": "v2.5.2",
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

##############################################
# $Id$
# Written by Markus Feist, 2017
package main;

use strict;
use warnings;
use constant MA_RAIN_FACTOR => 0.258;

sub MOBILEALERTS_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}   = "MOBILEALERTS_Define";
    $hash->{UndefFn} = "MOBILEALERTS_Undef";
    $hash->{SetFn}   = "MOBILEALERTS_Set";
    $hash->{AttrFn}  = "MOBILEALERTS_Attr";
    $hash->{ParseFn} = "MOBILEALERTS_Parse";
    $hash->{Match}   = "^.*";
    $hash->{AttrList} =
        "actCycle "
      . "lastMsg:0,1 "
      . "expert:0,1,4 "
      . "stateFormat "
      . "ignore:0,1 "
      . $readingFnAttributes;
    $hash->{AutoCreate} = {
        "MA_.*" => {
            ATTR => "event-on-change-reading:.* timestamp-on-change-reading:.*",
            FILTER => "%NAME"
        }
    };
    InternalTimer( gettimeofday() + 60, "MOBILEALERTS_ActionDetector", $hash );
    Log3 "MOBILEALERTS", 5, "MOBILEALERTS_Initialize finished.";
}

sub MOBILEALERTS_Define($$) {
    my ( $hash, $def ) = @_;
    my (
        $name,      $type,        $deviceID,   $corrTempIn,
        $corrHumIn, $corrTempOut, $corrHumOut, $corrTemp2,
        $corrHum2,  $corrTemp3,   $corrHum3
    ) = split( "[ \t]+", $def );
    Log3 $name, 3, "$name MOBILEALERTS: DeviceID $deviceID";
    $corrTempIn  = 0 if ( !defined($corrTempIn) );
    $corrHumIn   = 0 if ( !defined($corrHumIn) );
    $corrTempOut = 0 if ( !defined($corrTempOut) );
    $corrHumOut  = 0 if ( !defined($corrHumOut) );
    $corrTemp2   = 0 if ( !defined($corrTemp2) );
    $corrHum2    = 0 if ( !defined($corrHum2) );
    $corrTemp3   = 0 if ( !defined($corrTemp3) );
    $corrHum3    = 0 if ( !defined($corrHum3) );
    $corrTempIn =~ s/,/./g;
    $corrHumIn =~ s/,/./g;
    $corrTempOut =~ s/,/./g;
    $corrHumOut =~ s/,/./g;
    $corrTemp2 =~ s/,/./g;
    $corrHum2 =~ s/,/./g;
    $corrTemp3 =~ s/,/./g;
    $corrHum3 =~ s/,/./g;
    return
"Usage: define <name> MOBILEALERTS <id-12 stellig hex > <opt. corrTempIn> <opt. corrHumIn> <opt. corrTempOut/1> <opt. corrHumOut/1> <opt. corrTemp2> <opt. corrHum2> <opt. corrTemp3> <opt. corrHum3>"
      if ( ( $deviceID !~ m/^[0-9a-f]{12}$/ )
        || ( $corrTempIn !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrHumIn !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrTempOut !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrHumOut !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrTemp2 !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrHum2 !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrTemp3 !~ m/^-?[0-9]*\.?[0-9]*$/ )
        || ( $corrHum3 !~ m/^-?[0-9]*\.?[0-9]*$/ ) );

    $modules{MOBILEALERTS}{defptr}{$deviceID} = $hash;
    $hash->{DeviceID} = $deviceID;
    delete $hash->{corrTemperature};
    $hash->{corrTemperature} = $corrTempIn + 0 if ( $corrTempIn != 0 );
    $hash->{".corrTemperature"} = $corrTempIn + 0;
    delete $hash->{corrHumidty};
    $hash->{corrHumidity} = $corrHumIn + 0 if ( $corrHumIn != 0 );
    $hash->{".corrHumidity"} = $corrHumIn + 0;
    delete $hash->{corrTemperatureOut};
    $hash->{corrTemperatureOut} = $corrTempOut + 0 if ( $corrTempOut != 0 );
    $hash->{".corrTemperatureOut"} = $corrTempOut + 0;
    delete $hash->{corrHumidtyOut};
    $hash->{corrHumidityOut} = $corrHumOut + 0 if ( $corrHumOut != 0 );
    $hash->{".corrHumidityOut"} = $corrHumOut + 0;
    delete $hash->{corrTemperature2};
    $hash->{corrTemperature2} = $corrTemp2 + 0 if ( $corrTemp2 != 0 );
    $hash->{".corrTemperature2"} = $corrTemp2 + 0;
    delete $hash->{corrHumidty2};
    $hash->{corrHumidity2} = $corrHum2 + 0 if ( $corrHum2 != 0 );
    $hash->{".corrHumidity2"} = $corrHum2 + 0;
    delete $hash->{corrTemperature3};
    $hash->{corrTemperature3} = $corrTemp3 + 0 if ( $corrTemp3 != 0 );
    $hash->{".corrTemperature3"} = $corrTemp3 + 0;
    delete $hash->{corrHumidty3};
    $hash->{corrHumidity3} = $corrHum3 + 0 if ( $corrHum3 != 0 );
    $hash->{".corrHumidity3"} = $corrHum3 + 0;

    if (   ( exists $modules{MOBILEALERTS}{AutoCreateMessages} )
        && ( exists $modules{MOBILEALERTS}{AutoCreateMessages}{$deviceID} ) )
    {
        MOBILEALERTS_Parse(
            $modules{MOBILEALERTS}{AutoCreateMessages}{$deviceID}[0],
            $modules{MOBILEALERTS}{AutoCreateMessages}{$deviceID}[1]
        );
        delete $modules{MOBILEALERTS}{AutoCreateMessages}{$deviceID};
    }
    if ( substr( $deviceID, 0, 2 ) eq "08" ) {
        Log3 $name, 5, "$name MOBILEALERTS: is rainSensor, start Timer";
        InternalTimer( gettimeofday() + 60,
            "MOBILEALERTS_CheckRainSensorTimed", $hash );
    }
    return undef;
}

sub MOBILEALERTS_Undef($$) {
    my ( $hash, $name ) = @_;
    delete $modules{MOBILEALERTS}{defptr}{ $hash->{DeviceID} };
    RemoveInternalTimer( $hash, "MOBILEALERTS_CheckRainSensorTimed" );
    return undef;
}

sub MOBILEALERTS_Attr($$$$) {
    my ( $cmd, $name, $attrName, $attrValue ) = @_;

    if ( $cmd eq "set" ) {
        if ( $attrName eq "lastMsg" ) {
            if ( $attrValue !~ /^[01]$/ ) {
                Log3 $name, 3,
"$name MOBILELAERTS: Invalid parameter attr $name $attrName $attrValue";
                return "Invalid value $attrValue allowed 0,1";
            }
        }
        elsif ( $attrName eq "expert" ) {
            if ( $attrValue !~ /^[014]$/ ) {
                Log3 $name, 3,
"$name MOBILELAERTS: Invalid parameter attr $name $attrName $attrValue";
                return "Invalid value $attrValue allowed 0,1,4";
            }
        }
        elsif ( $attrName eq "actCycle" ) {
            unless ( $attrValue eq "off" ) {
                ( $_[3], my $sec ) = MOBILEALERTS_time2sec($attrValue);
                if ( $sec > 0 ) {
                    my $hash = $modules{MOBILEALERTS};
                    if ($init_done) {
                        RemoveInternalTimer($hash);
                        InternalTimer( gettimeofday() + 60,
                            "MOBILEALERTS_ActionDetector", $hash );
                    }
                }
            }
        }
    }
    return undef;
}

sub MOBILEALERTS_Notify($$) {
    my ( $hash, $dev ) = @_;
    my $name    = $hash->{NAME};
    my $devName = $dev->{NAME};
}

sub MOBILEALERTS_Set ($$@) {
    my ( $hash, $name, $cmd, @args ) = @_;
    return "\"set $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "clear" ) {
        if ( $args[0] eq "readings" ) {
            for ( keys %{ $hash->{READINGS} } ) {
                readingsDelete( $hash, $_ ) if ( $_ ne 'state' );
            }
            return undef;
        }
        elsif ( $args[0] eq "counters" ) {
            my $test = ReadingsVal( $hash->{NAME}, "mmRain", undef );
            readingsSingleUpdate( $hash, "mmRain", 0, 1 ) if ( defined $test );
            return undef;
        }
        else {
            return
"Unknown value $args[0] for $cmd, choose one of readings,counters";
        }
    }
    else {
        return "Unknown argument $cmd, choose one of clear:readings,counters";
    }
}

sub MOBILEALERTS_Parse ($$) {
    my ( $io_hash, $message ) = @_;
    my ( $packageHeader, $timeStamp, $packageLength, $deviceID ) =
      unpack( "H2NCH12", $message );
    my $name = $io_hash->{NAME};

    Log3 $name, 5, "$name MOBILELAERTS: Search for Device ID: $deviceID";
    if ( my $hash = $modules{MOBILEALERTS}{defptr}{$deviceID} ) {
        my $verbose = GetVerbose( $hash->{NAME} );
        Log3 $name, 5, "$name MOBILELAERTS: Found Device: " . $hash->{NAME};
        Log3 $hash->{NAME}, 5,
          "$hash->{NAME} MOBILELAERTS: Message: " . unpack( "H*", $message )
          if ( $verbose >= 5 );

        # Nachricht für $hash verarbeiten
        $timeStamp = FmtDateTime($timeStamp);
        readingsBeginUpdate($hash);
        $hash->{".updateTimestamp"} = $timeStamp;
        $hash->{".expertMode"} = AttrVal( $hash->{NAME}, "expert", 0 );
        my $sub =
            "MOBILEALERTS_Parse_"
          . substr( $deviceID, 0, 2 ) . "_"
          . $packageHeader;
        if ( defined &$sub ) {

            #no strict "refs";
            &{ \&$sub }( $hash, substr $message, 12, $packageLength - 12 );

            #use strict "refs";
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastMsg",
                unpack( "H*", $message ) )
              if ( AttrVal( $hash->{NAME}, "lastMsg", 0 ) == 1 );
        }
        else {
            Log3 $name, 2,
                "$name MOBILELAERTS: For id "
              . substr( $deviceID, 0, 2 )
              . " and packageHeader $packageHeader is no decoding defined.";
            MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
                    "Unknown - "
                  . substr( $deviceID, 0, 2 ) . " "
                  . $packageHeader );
            $sub = "MOBILEALERTS_Parse_" . $packageHeader;
            if ( defined &$sub ) {

                #no strict "refs";
                &{ \&$sub }( $hash, substr $message, 12, $packageLength - 12 );

                #use strict "refs";
            }
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastMsg",
                unpack( "H*", $message ) );
        }
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastRcv", $timeStamp );

        my $actCycle = AttrVal( $hash->{NAME}, "actCycle", undef );
        if ($actCycle) {
            ( undef, my $sec ) = MOBILEALERTS_time2sec($actCycle);
            if ( $sec > 0 ) {
                MOBILEALERTS_readingsBulkUpdate( $hash, 0, "actStatus",
                    "alive" );
            }
        }
        readingsEndUpdate( $hash, 1 );

        # Rückgabe des Gerätenamens, für welches die Nachricht bestimmt ist.
        return $hash->{NAME};
    }
    $modules{MOBILEALERTS}{AutoCreateMessages}{$deviceID} =
      [ $io_hash, $message ];
    my $res = "UNDEFINED MA_" . $deviceID . " MOBILEALERTS $deviceID";
    Log3 $name, 5, "$name MOBILELAERTS: Parse return: " . $res;
    return $res;
}

sub MOBILEALERTS_Parse_02_ce ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10100/MA10101" );
    MOBILEALERTS_Parse_ce( $hash, $message );
}

sub MOBILEALERTS_Parse_ce ($$) {
    my ( $hash, $message ) = @_;
    my ( $txCounter, $temperature, $prevTemperature ) =
      unpack( "nnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperature =
      MOBILEALERTS_decodeTemperature($temperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature", $temperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString",
        MOBILEALERTS_temperatureToString($temperature) );
    $prevTemperature = MOBILEALERTS_decodeTemperature($prevTemperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature",
        $prevTemperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state", "T: " . $temperature );
}

sub MOBILEALERTS_Parse_0f_d2 ($$) {
    my ( $hash, $message ) = @_;
    my ( $txCounter, $temperatureIn, $temperatureOut, $prevTemperatureIn,
        $prevTemperatureOut )
      = unpack( "nnnnn", $message );

    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10450" );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperatureIn =
      MOBILEALERTS_decodeTemperature($temperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureIn",
        $temperatureIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureInString",
        MOBILEALERTS_temperatureToString($temperatureIn) );
    $temperatureOut = MOBILEALERTS_decodeTemperature($temperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureOut",
        $temperatureOut );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureOutString",
        MOBILEALERTS_temperatureToString($temperatureOut) );
    $prevTemperatureIn = MOBILEALERTS_decodeTemperature($prevTemperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureIn",
        $prevTemperatureIn );
    $prevTemperatureOut = MOBILEALERTS_decodeTemperature($prevTemperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureOut",
        $prevTemperatureOut );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
        "In T: " . $temperatureIn . " Out T: " . $temperatureOut );
}

sub MOBILEALERTS_Parse_03_d2 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10200" );
    MOBILEALERTS_Parse_d2( $hash, $message );
}

sub MOBILEALERTS_Parse_d2 ($$) {
    my ( $hash, $message ) = @_;
    my ( $txCounter, $temperature, $humidity, $prevTemperature, $prevHumidity )
      = unpack( "nnnnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperature =
      MOBILEALERTS_decodeTemperature($temperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature", $temperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString",
        MOBILEALERTS_temperatureToString($temperature) );
    $humidity =
      MOBILEALERTS_decodeHumidity($humidity) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity", $humidity );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString",
        MOBILEALERTS_humidityToString($humidity) );
    $prevTemperature = MOBILEALERTS_decodeTemperature($prevTemperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature",
        $prevTemperature );
    $prevHumidity =
      MOBILEALERTS_decodeHumidity($prevHumidity) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity", $prevHumidity );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
        "T: " . $temperature . " H: " . $humidity );
}

sub MOBILEALERTS_Parse_04_d4 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10350" );
    MOBILEALERTS_Parse_d4( $hash, $message );
}

sub MOBILEALERTS_Parse_d4 ($$) {
    my ( $hash, $message ) = @_;
    my ( $txCounter, $temperature, $humidity, $wetness,
        $prevTemperature, $prevHumidity, $prevWetness )
      = unpack( "nnnCnnC", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperature =
      MOBILEALERTS_decodeTemperature($temperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature", $temperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString",
        MOBILEALERTS_temperatureToString($temperature) );
    $humidity =
      MOBILEALERTS_decodeHumidity($humidity) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity", $humidity );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString",
        MOBILEALERTS_humidityToString($humidity) );
    $wetness = MOBILEALERTS_decodeWetness($wetness);
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "wetness", $wetness );
    $prevTemperature = MOBILEALERTS_decodeTemperature($prevTemperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature",
        $prevTemperature );
    $prevHumidity =
      MOBILEALERTS_decodeHumidity($prevHumidity) + $hash->{".corrHumidity"};
    $prevWetness = MOBILEALERTS_decodeWetness($prevWetness);
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevWetness",  $prevWetness );
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity", $prevHumidity );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
        "T: " . $temperature . " H: " . $humidity . " " . $wetness );
}

sub MOBILEALERTS_Parse_05_da ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "WL2000" );
    my ( $txCounter, $temperatureOut, $temperatureIn, $humidityIn, $co2,
        $prevTemperatureOut, $prevTemperatureIn, $prevHumidityIn )
      = unpack( "nnnnnnnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperatureIn =
      MOBILEALERTS_decodeTemperature($temperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureIn",
        $temperatureIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureStringIn",
        MOBILEALERTS_temperatureToString($temperatureIn) );
    $temperatureOut = MOBILEALERTS_decodeTemperature($temperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureOut",
        $temperatureOut );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureStringOut",
        MOBILEALERTS_temperatureToString($temperatureOut) );
    $humidityIn =
      MOBILEALERTS_decodeHumidity($humidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity", $humidityIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString",
        MOBILEALERTS_humidityToString($humidityIn) );
    $co2 = MOBILEALERTS_decodeCO2($co2);
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "co2", $co2 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "co2String",
        MOBILEALERTS_cO2ToString($co2) );
    $prevTemperatureIn = MOBILEALERTS_decodeTemperature($prevTemperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureIn",
        $prevTemperatureIn );
    $prevTemperatureOut = MOBILEALERTS_decodeTemperature($prevTemperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureOut",
        $prevTemperatureOut );
    $prevHumidityIn =
      MOBILEALERTS_decodeHumidity($prevHumidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidityIn",
        $prevHumidityIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
            "In T: "
          . $temperatureIn . " H: "
          . $humidityIn
          . " Out T: "
          . $temperatureOut
          . " CO2: "
          . $co2 );
}

sub MOBILEALERTS_Parse_07_da ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10410" );
    MOBILEALERTS_Parse_da( $hash, $message );
}

sub MOBILEALERTS_Parse_da ($$) {
    my ( $hash, $message ) = @_;
    my (
        $txCounter,      $temperatureIn,      $humidityIn,
        $temperatureOut, $humidityOut,        $prevTemperatureIn,
        $prevHumidityIn, $prevTemperatureOut, $prevHumidityOut
    ) = unpack( "nnnnnnnnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperatureIn =
      MOBILEALERTS_decodeTemperature($temperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureIn",
        $temperatureIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureInString",
        MOBILEALERTS_temperatureToString($temperatureIn) );
    $humidityIn =
      MOBILEALERTS_decodeHumidity($humidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityIn", $humidityIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityInString",
        MOBILEALERTS_humidityToString($humidityIn) );
    $temperatureOut = MOBILEALERTS_decodeTemperature($temperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureOut",
        $temperatureOut );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureOutString",
        MOBILEALERTS_temperatureToString($temperatureOut) );
    $humidityOut =
      MOBILEALERTS_decodeHumidity($humidityOut) + $hash->{".corrHumidityOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityOut", $humidityOut );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityOutString",
        MOBILEALERTS_humidityToString($humidityOut) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
            "In T: "
          . $temperatureIn . " H: "
          . $humidityIn
          . " Out T: "
          . $temperatureOut . " H: "
          . $humidityOut );
}

sub MOBILEALERTS_Parse_08_e1 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10650" );
    MOBILEALERTS_Parse_e1( $hash, $message );
}

sub MOBILEALERTS_Parse_e1 ($$) {
    my ( $hash, $message ) = @_;
    my @eventTime;
    ( my ( $txCounter, $temperature, $eventCounter ), @eventTime[ 0 .. 8 ] ) =
      unpack( "nnnnnnnnnnnn", $message );
    my $lastEventCounter = ReadingsVal( $hash->{NAME}, "eventCounter", undef );
    my $mmRain = 0;

    if ( !defined($lastEventCounter) ) {

        # First Data
        $mmRain = $eventCounter * MA_RAIN_FACTOR;
    }
    elsif ( $lastEventCounter > $eventCounter ) {

        # Overflow EventCounter or fresh Batterie
        $mmRain = $eventCounter * MA_RAIN_FACTOR;
    }
    elsif ( $lastEventCounter < $eventCounter ) {
        $mmRain = ( $eventCounter - $lastEventCounter ) * MA_RAIN_FACTOR;
    }
    else {
        $mmRain = 0;
    }
    MOBILEALERTS_CheckRainSensor( $hash, $mmRain );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperature =
      MOBILEALERTS_decodeTemperature($temperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature", $temperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString",
        MOBILEALERTS_temperatureToString($temperature) );

    for ( my $z = 0 ; $z < 9 ; $z++ ) {
        my $eventTimeString =
          MOBILEALERTS_convertEventTimeString( $eventTime[$z], 14 );
        $eventTime[$z] = MOBILEALERTS_convertEventTime( $eventTime[$z], 14 );
        if ( $z == 0 ) {
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastEvent",
                $eventTime[$z] );
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastEventString",
                $eventTimeString );
        }
        else {
            MOBILEALERTS_readingsBulkUpdate( $hash, 4, "lastEvent" . $z,
                $eventTime[$z] );
            MOBILEALERTS_readingsBulkUpdate( $hash, 4,
                "lastEvent" . $z . "String",
                $eventTimeString );
        }
    }
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "eventCounter", $eventCounter );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
        "T: " . $temperature . " C: " . $eventCounter );
}

sub MOBILEALERTS_Parse_0b_e2 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10660" );
    MOBILEALERTS_Parse_e2( $hash, $message );
}

sub MOBILEALERTS_Parse_e2 ($$) {
    my ( $hash, $message ) = @_;
    my @dirTable = (
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
    );
    my ( $txCounter, $data0, $data1, $data2, $data3 ) =
      unpack( "NCCCC", "\0" . $message );

    my $dir          = $data0 >> 4;
    my $overFlowBits = $data0 & 3;
    my $windSpeed    = ( ( ( $overFlowBits & 2 ) >> 1 ) << 8 ) + $data1 * 0.1;
    my $gustSpeed    = ( ( ( $overFlowBits & 1 ) >> 1 ) << 8 ) + $data2 * 0.1;
    my $lastTransmit = $data3 * 2;

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "direction", $dirTable[$dir] );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "directionInt", $dir );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "windSpeed",    $windSpeed );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "gustSpeed",    $gustSpeed );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
        "D: " . $dirTable[$dir] . " W: " . $windSpeed . " G: " . $gustSpeed );
}

sub MOBILEALERTS_Parse_0e_d8 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "TFA30.3312.02" );
    MOBILEALERTS_Parse_d8( $hash, $message );
}

sub MOBILEALERTS_Parse_d8 ($$) {
    my ( $hash, $message ) = @_;
    my (
        $txCounter,    $temperature,      $humidity, $prevTemperature,
        $prevHumidity, $prevTemperature2, $prevHumidity2
    ) = unpack( "nnnxnnxnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperature =
      MOBILEALERTS_decodeTemperature($temperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature", $temperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString",
        MOBILEALERTS_temperatureToString($temperature) );
    $humidity =
      MOBILEALERTS_decodeHumidityDecimal($humidity) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity", $humidity );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString",
        MOBILEALERTS_humidityToString($humidity) );
    $prevTemperature = MOBILEALERTS_decodeTemperature($prevTemperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature",
        $prevTemperature );
    $prevHumidity =
      MOBILEALERTS_decodeHumidityDecimal($prevHumidity) +
      $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity", $prevHumidity );
    $prevTemperature2 = MOBILEALERTS_decodeTemperature($prevTemperature2) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature2",
        $prevTemperature2 );
    $prevHumidity2 = MOBILEALERTS_decodeHumidityDecimal($prevHumidity2) +
      $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity2",
        $prevHumidity2 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
        "T: " . $temperature . " H: " . $humidity );
}

sub MOBILEALERTS_Parse_10_d3 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10800" );
    MOBILEALERTS_Parse_d3( $hash, $message );
}

sub MOBILEALERTS_Parse_d3 ($$) {
    my ( $hash, $message ) = @_;
    my @data;
    ( my ($txCounter), @data[ 0 .. 3 ] ) = unpack( "nnnnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    for ( my $z = 0 ; $z < 4 ; $z++ ) {
        my $eventTimeString =
          MOBILEALERTS_convertEventTimeString( $data[$z], 13 );
        my $eventTime = MOBILEALERTS_convertEventTime( $data[$z], 13 );
        $data[$z] = MOBILEALERTS_convertOpenState( $data[$z] );

        if ( $z == 0 ) {
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state", $data[$z] );
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastEvent",
                $eventTime );
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "lastEventString",
                $eventTimeString );
        }
        else {
            MOBILEALERTS_readingsBulkUpdate( $hash, 4, "state" . $z,
                $data[$z] );
            MOBILEALERTS_readingsBulkUpdate( $hash, 4, "lastEvent" . $z,
                $eventTime );
            MOBILEALERTS_readingsBulkUpdate( $hash, 4,
                "lastEvent" . $z . "String",
                $eventTimeString );
        }
    }
}

sub MOBILEALERTS_Parse_12_d9 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10230" );
    MOBILEALERTS_Parse_d9( $hash, $message );
}

sub MOBILEALERTS_Parse_d9 ($$) {
    my ( $hash, $message ) = @_;
    my (
        $txCounter,   $humidity3h,  $humidity24h, $humidity7d,
        $humidity30d, $temperature, $humidity
    ) = unpack( "nCCCCnC", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperature =
      MOBILEALERTS_decodeTemperature($temperature) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature", $temperature );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString",
        MOBILEALERTS_temperatureToString($temperature) );
    $humidity =
      MOBILEALERTS_decodeHumidity($humidity) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity", $humidity );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString",
        MOBILEALERTS_humidityToString($humidity) );
    $humidity3h =
      MOBILEALERTS_decodeHumidity($humidity3h) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity3h", $humidity3h );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity3hString",
        MOBILEALERTS_humidityToString($humidity3h) );
    $humidity24h =
      MOBILEALERTS_decodeHumidity($humidity24h) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity24h", $humidity3h );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity24hString",
        MOBILEALERTS_humidityToString($humidity24h) );
    $humidity7d =
      MOBILEALERTS_decodeHumidity($humidity7d) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity7d", $humidity7d );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity7dString",
        MOBILEALERTS_humidityToString($humidity7d) );
    $humidity30d =
      MOBILEALERTS_decodeHumidity($humidity30d) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity30d", $humidity30d );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity30dString",
        MOBILEALERTS_humidityToString($humidity30d) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
            "T: "
          . $temperature . " H: "
          . $humidity . " "
          . $humidity3h . "/"
          . $humidity24h . "/"
          . $humidity7d . "/"
          . $humidity30d );
}

sub MOBILEALERTS_Parse_06_d6 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10300/MA10700" );
    MOBILEALERTS_Parse_d6( $hash, $message );
}

sub MOBILEALERTS_Parse_09_d6 ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "MA10320PRO" );
    MOBILEALERTS_Parse_d6( $hash, $message );
}

sub MOBILEALERTS_Parse_d6 ($$) {
    my ( $hash, $message ) = @_;
    my ( $txCounter, $temperatureIn, $temperatureOut, $humidityIn,
        $prevTemperatureIn, $prevTemperatureOut, $prevHumidityIn )
      = unpack( "nnnnnnn", $message );

    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );
    $temperatureIn =
      MOBILEALERTS_decodeTemperature($temperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureIn",
        $temperatureIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureStringIn",
        MOBILEALERTS_temperatureToString($temperatureIn) );
    $temperatureOut = MOBILEALERTS_decodeTemperature($temperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureOut",
        $temperatureOut );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureStringOut",
        MOBILEALERTS_temperatureToString($temperatureOut) );
    $humidityIn =
      MOBILEALERTS_decodeHumidity($humidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity", $humidityIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString",
        MOBILEALERTS_humidityToString($humidityIn) );
    $prevTemperatureIn = MOBILEALERTS_decodeTemperature($prevTemperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureIn",
        $prevTemperatureIn );
    $prevTemperatureOut = MOBILEALERTS_decodeTemperature($prevTemperatureOut) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureOut",
        $prevTemperatureOut );
    $prevHumidityIn =
      MOBILEALERTS_decodeHumidity($prevHumidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidityIn",
        $prevHumidityIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
            "In T: "
          . $temperatureIn . " H: "
          . $humidityIn
          . " Out T: "
          . $temperatureOut );
}

sub MOBILEALERTS_Parse_11_ea ($$) {
    my ( $hash, $message ) = @_;
    MOBILEALERTS_readingsBulkUpdateIfChanged( $hash, 0, "deviceType",
        "TFA30.3060.01.IT" );
    MOBILEALERTS_Parse_ea( $hash, $message );
}

sub MOBILEALERTS_Parse_ea ($$) {
    my ( $hash, $message ) = @_;
    my (
        $txCounter,         $temperature1,     $humidity1,
        $temperature2,      $humidity2,        $temperature3,
        $humidity3,         $temperatureIn,    $humidityIn,
        $prevTemperature1,  $prevHumidity1,    $prevTemperature2,
        $prevHumidity2,     $prevTemperature3, $prevHumidity3,
        $prevTemperatureIn, $prevHumidityIn
    ) = unpack( "nnnnnnnnnnnnnnnnn", $message );

    # txCounter
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "txCounter",
        MOBILEALERTS_decodeTxCounter($txCounter) );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "triggered",
        MOBILEALERTS_triggeredTxCounter($txCounter) );

    # Sensor 1
    $temperature1 = MOBILEALERTS_decodeTemperature($temperature1) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature1", $temperature1 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString1",
        MOBILEALERTS_temperatureToString($temperature1) );

    $humidity1 =
      MOBILEALERTS_decodeHumidity($humidity1) + $hash->{".corrHumidityOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity1", $humidity1 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString1",
        MOBILEALERTS_humidityToString($humidity1) );

    # Sensor 2
    $temperature2 = MOBILEALERTS_decodeTemperature($temperature2) +
      $hash->{".corrTemperature2"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature2", $temperature2 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString2",
        MOBILEALERTS_temperatureToString($temperature2) );

    $humidity2 =
      MOBILEALERTS_decodeHumidity($humidity2) + $hash->{".corrHumidity2"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity2", $humidity2 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString2",
        MOBILEALERTS_humidityToString($humidity2) );

    # Sensor 3
    $temperature3 = MOBILEALERTS_decodeTemperature($temperature3) +
      $hash->{".corrTemperature3"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperature3", $temperature3 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureString3",
        MOBILEALERTS_temperatureToString($temperature3) );

    $humidity3 =
      MOBILEALERTS_decodeHumidity($humidity3) + $hash->{".corrHumidity3"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidity3", $humidity3 );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityString3",
        MOBILEALERTS_humidityToString($humidity3) );

    # Sensor In
    $temperatureIn = MOBILEALERTS_decodeTemperature($temperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureIn",
        $temperatureIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "temperatureStringIn",
        MOBILEALERTS_temperatureToString($temperatureIn) );

    $humidityIn =
      MOBILEALERTS_decodeHumidity($humidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityIn", $humidityIn );
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "humidityStringIn",
        MOBILEALERTS_humidityToString($humidityIn) );

    # Sensor1 prev
    $prevTemperature1 = MOBILEALERTS_decodeTemperature($prevTemperature1) +
      $hash->{".corrTemperatureOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature1",
        $prevTemperature1 );
    $prevHumidity1 =
      MOBILEALERTS_decodeHumidity($prevHumidity1) + $hash->{".corrHumidityOut"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity1",
        $prevHumidity1 );

    # Sensor2 prev
    $prevTemperature2 = MOBILEALERTS_decodeTemperature($prevTemperature2) +
      $hash->{".corrTemperature2"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature2",
        $prevTemperature2 );
    $prevHumidity2 =
      MOBILEALERTS_decodeHumidity($prevHumidity2) + $hash->{".corrHumidity2"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity2",
        $prevHumidity2 );

    # Sensor3 prev
    $prevTemperature3 = MOBILEALERTS_decodeTemperature($prevTemperature3) +
      $hash->{".corrTemperature3"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperature3",
        $prevTemperature3 );
    $prevHumidity3 =
      MOBILEALERTS_decodeHumidity($prevHumidity3) + $hash->{".corrHumidity3"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidity3",
        $prevHumidity3 );

    # Sensor In prev
    $prevTemperatureIn = MOBILEALERTS_decodeTemperature($prevTemperatureIn) +
      $hash->{".corrTemperature"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevTemperatureIn",
        $prevTemperatureIn );
    $prevHumidityIn =
      MOBILEALERTS_decodeHumidity($prevHumidityIn) + $hash->{".corrHumidity"};
    MOBILEALERTS_readingsBulkUpdate( $hash, 1, "prevHumidityIn",
        $prevHumidityIn );

    # state
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "state",
            "In T: "
          . $temperatureIn . " H: "
          . $humidityIn
          . " 1 T: "
          . $temperature1 . " H: "
          . $humidity1
          . " 2 T: "
          . $temperature2 . " H: "
          . $humidity2
          . " 3 T: "
          . $temperature3 . " H: "
          . $humidity3 );
}

sub MOBILEALERTS_decodeTxCounter($) {
    my ($txCounter) = @_;
    return $txCounter & 0x3FFF;
}

sub MOBILEALERTS_triggeredTxCounter($) {
    my ($txCounter) = @_;
    if ( ( $txCounter & 0x4000 ) == 0x4000 ) {
        return 1;
    }
    return 0;
}

sub MOBILEALERTS_decodeTemperature($) {
    my ($temperature) = @_;

    #Overflow
    return 9999 if ( ( $temperature & 0x2000 ) == 0x2000 );

    #Illegal value
    return -9999 if ( ( $temperature & 0x1000 ) == 0x1000 );

    #Negativ Values
    return ( 0x800 - ( $temperature & 0x7ff ) ) * -0.1
      if ( ( $temperature & 0x400 ) == 0x400 );

    #Positiv Values
    return ( $temperature & 0x7ff ) * 0.1;
}

sub MOBILEALERTS_temperatureToString($) {
    my ($temperature) = @_;
    return "---" if ( $temperature < -1000 );
    return "OLF" if ( $temperature > 1000 );
    return $temperature . "°C";
}

sub MOBILEALERTS_decodeHumidity($) {
    my ($humidity) = @_;
    return 9999 if ( ( $humidity & 0x80 ) == 0x80 );
    return $humidity & 0x7F;
}

sub MOBILEALERTS_decodeHumidityDecimal($) {
    my ($humidity) = @_;
    return ( $humidity & 0x3FF ) * 0.1;
}

sub MOBILEALERTS_humidityToString($) {
    my ($humidity) = @_;
    return "---" if ( $humidity > 1000 );
    return $humidity . "%";
}

sub MOBILEALERTS_decodeCO2($) {
    my ($co2) = @_;
    return 9999 if ( ( $co2 & 0x80 ) == 0x80 );
    return ( $co2 & 0x7F ) * 50;
}

sub MOBILEALERTS_cO2ToString($) {
    my ($co2) = @_;
    return "---" if ( $co2 == 9999 );
    return $co2 . " ppm";
}

sub MOBILEALERTS_decodeWetness($) {
    my ($wetness) = @_;

    return "dry" if ( $wetness & 0x01 );
    return "wet";
}

sub MOBILEALERTS_convertOpenState($) {
    my ($value) = @_;
    return "open" if ( $value & 0x8000 );
    return "closed";
}

sub MOBILEALERTS_convertEventTime($$) {
    my ( $value, $timeScaleBitOffset ) = @_;
    my $timeScaleFactor = ( $value >> $timeScaleBitOffset ) & 3;
    $value = $value & ( ( 1 << $timeScaleBitOffset ) - 1 );
    if ( $timeScaleFactor == 0 ) {    # days
        return $value * 60 * 60 * 24;
    }
    elsif ( $timeScaleFactor == 1 ) {    # hours
        return $value * 60 * 60;
    }
    elsif ( $timeScaleFactor == 2 ) {    # minutes
        return $value * 60;
    }
    elsif ( $timeScaleFactor == 3 ) {    # seconds
        return $value;
    }
}

sub MOBILEALERTS_convertEventTimeString($$) {
    my ( $value, $timeScaleBitOffset ) = @_;
    my $timeScaleFactor = ( $value >> $timeScaleBitOffset ) & 3;
    $value = $value & ( ( 1 << $timeScaleBitOffset ) - 1 );
    if ( $timeScaleFactor == 0 ) {       # days
        return $value . " d";
    }
    elsif ( $timeScaleFactor == 1 ) {    # hours
        return $value . " h";
    }
    elsif ( $timeScaleFactor == 2 ) {    # minutes
        return $value . " m";
    }
    elsif ( $timeScaleFactor == 3 ) {    # seconds
        return $value . " s";
    }
}

sub MOBILEALERTS_readingsBulkUpdate($$$$@) {
    my ( $hash, $expert, $reading, $value, $changed ) = @_;
    if ( $expert > $hash->{".expertMode"} ) {
        readingsDelete( $hash, $reading );
        return undef;
    }
    my $i = $#{ $hash->{CHANGED} };
    my $res = readingsBulkUpdate( $hash, $reading, $value, $changed );
    $hash->{CHANGETIME}->[ $#{ $hash->{CHANGED} } ] =
      $hash->{".updateTimestamp"}
      if ( $#{ $hash->{CHANGED} } != $i );  # only add ts if there is a event to
    return $res;
}

sub MOBILEALERTS_readingsBulkUpdateIfChanged($$$$@) {
    my ( $hash, $expert, $reading, $value, $changed ) = @_;
    if ( $expert > $hash->{".expertMode"} ) {
        readingsDelete( $hash, $reading );
        return undef;
    }
    my $i = $#{ $hash->{CHANGED} };
    my $res = readingsBulkUpdateIfChanged( $hash, $reading, $value, $changed );
    $hash->{CHANGETIME}->[ $#{ $hash->{CHANGED} } ] =
      $hash->{".updateTimestamp"}
      if ( $#{ $hash->{CHANGED} } != $i );  # only add ts if there is a event to
    return $res;
}

sub MOBILEALERTS_time2sec($) {
    my ($timeout) = @_;
    return ( "off", 0 ) unless ($timeout);
    return ( "off", 0 ) if ( $timeout eq "off" );

    my ( $h, $m ) = split( ":", $timeout );
    no warnings 'numeric';
    $h = int($h);
    $m = int($m);
    use warnings 'numeric';
    return (
        ( sprintf( "%03s:%02d", $h, $m ) ),
        ( ( int($h) * 60 + int($m) ) * 60 )
    );
}

sub MOBILEALERTS_CheckRainSensorTimed($) {
    my ($hash) = @_;
    $hash->{".expertMode"} = AttrVal( $hash->{NAME}, "expert", 0 );
    readingsBeginUpdate($hash);
    MOBILEALERTS_CheckRainSensor( $hash, 0 );
    readingsEndUpdate( $hash, 1 );
    InternalTimer(
        time_str2num(
            substr( FmtDateTime( gettimeofday() + 3600 ), 0, 13 ) . ":00:00"
        ),
        "MOBILEALERTS_CheckRainSensorTimed",
        $hash
    );
}

sub MOBILEALERTS_CheckRainSensor($$) {
    my ( $hash, $mmRain ) = @_;

    #Event
    push @{ $hash->{CHANGED} }, "rain" if ( $mmRain > 0 );

    #lastHour
    my $actTime = $hash->{".updateTimestamp"};
    my $actH = ReadingsTimestamp( $hash->{NAME}, "mmRainActHour", $actTime );
    if ( substr( $actTime, 0, 13 ) eq substr( $actH, 0, 13 ) ) {
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainActHour",
            $mmRain + ReadingsVal( $hash->{NAME}, "mmRainActHour", "0" ) )
          if ( $mmRain > 0 );
    }
    else {
        if (
            (
                time_str2num( substr( $actTime, 0, 13 ) . ":00:00" ) -
                time_str2num( substr( $actH,    0, 13 ) . ":00:00" )
            ) > 3600
          )
        {
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainLastHour", 0 );
        }
        else {
            $hash->{".updateTimestamp"} = $actH;
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainLastHour",
                ReadingsVal( $hash->{NAME}, "mmRainActHour", "0" ) );
            $hash->{".updateTimestamp"} = $actTime;
        }
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainActHour", 0 );
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainActHour", $mmRain )
          if ( $mmRain > 0 );
    }

    #Yesterday
    my $actD = ReadingsTimestamp( $hash->{NAME}, "mmRainActDay", $actTime );
    if ( substr( $actTime, 0, 10 ) eq substr( $actD, 0, 10 ) ) {
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainActDay",
            $mmRain + ReadingsVal( $hash->{NAME}, "mmRainActDay", "0" ) )
          if ( $mmRain > 0 );
    }
    else {
        if (
            (
                time_str2num( substr( $actTime, 0, 13 ) . " 00:00:00" ) -
                time_str2num( substr( $actD,    0, 13 ) . " 00:00:00" )
            ) > 86400
          )
        {
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainYesterday", 0 );
        }
        else {
            $hash->{".updateTimestamp"} =
              ReadingsTimestamp( $hash->{NAME}, "mmRainActDay", $actD );
            MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainYesterday",
                ReadingsVal( $hash->{NAME}, "mmRainActDay", "0" ) );
            $hash->{".updateTimestamp"} = $actTime;
        }
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainActDay", 0 );
        MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRainActDay", $mmRain )
          if ( $mmRain > 0 );
    }
    MOBILEALERTS_readingsBulkUpdate( $hash, 0, "mmRain",
        $mmRain + ReadingsVal( $hash->{NAME}, "mmRain", "0" ) )
      if ( $mmRain > 0 );
}

sub MOBILEALERTS_ActionDetector($) {
    my ($hash) = @_;
    my $name = "ActionDetector";
    unless ($init_done) {
        Log3 $name, 5,
          "$name MOBILELAERTS: ActionDetector run - fhem not intialized";
        InternalTimer( gettimeofday() + 60,
            "MOBILEALERTS_ActionDetector", $hash );
        return;
    }
    Log3 $name, 5, "$name MOBILELAERTS: ActionDetector run";
    my $now       = gettimeofday();
    my $nextTimer = $now + 60 * 60;    # Check at least Hourly
    for my $chash ( values %{ $modules{MOBILEALERTS}{defptr} } ) {
        Log3 $name, 5, "$name MOBILELAERTS: ActionDetector " . $chash->{NAME};
        my $actCycle = AttrVal( $chash->{NAME}, "actCycle", undef );
        ( undef, my $sec ) = MOBILEALERTS_time2sec($actCycle);
        if ( $sec == 0 ) {
            readingsBeginUpdate($chash);
            readingsBulkUpdateIfChanged( $chash, "actStatus", "switchedOff" );
            readingsEndUpdate( $chash, 1 );
            next;
        }
        my $lastRcv = ReadingsTimestamp( $chash->{NAME}, "lastRcv", undef );
        my $deadTime = undef;
        readingsBeginUpdate($chash);
        if ( defined($lastRcv) ) {
            Log3 $name, 5,
                "$name MOBILELAERTS: ActionDetector "
              . $chash->{NAME}
              . " lastRcv "
              . $lastRcv;
            $lastRcv  = time_str2num($lastRcv);
            $deadTime = $lastRcv + $sec;
            if ( $deadTime < $now ) {
                readingsBulkUpdateIfChanged( $chash, "actStatus", "dead" );
                $deadTime = $now + $sec;
            }
            else {
                readingsBulkUpdate( $chash, "actStatus", "alive" );
            }
        }
        else {
            readingsBulkUpdateIfChanged( $chash, "actStatus", "unknown" );
            $deadTime = $now + $sec;
        }
        readingsEndUpdate( $chash, 1 );
        if ( ( defined($deadTime) ) && ( $deadTime < $nextTimer ) ) {
            $nextTimer = $deadTime;
            Log3 $name, 5,
                "$name MOBILELAERTS: ActionDetector "
              . $chash->{NAME}
              . " nextTime Set to "
              . FmtDateTime($nextTimer);
        }
    }
    Log3 $name, 5,
      "$name MOBILELAERTS: MOBILEALERTS_ActionDetector nextRun "
      . FmtDateTime($nextTimer);
    InternalTimer( $nextTimer, "MOBILEALERTS_ActionDetector", $hash );
}

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;

=pod
=item device
=item summary    virtual device for MOBILEALERTSGW
=item summary_DE virtuelles device für MOBILEALERTSGW
=begin html

<a name="MOBILEALERTS"></a>
<h3>MOBILEALERTS</h3>
<ul>
  The MOBILEALERTS is a fhem module for the german MobileAlerts devices and TFA WEATHERHUB devices.
  <br><br>
  The fhem module represents a MobileAlerts device. The connection is provided by the <a href="#MOBILEALERTSGW">MOBILELAERTSGW</a> module.
  Currently supported: MA10100, MA10101, MA10200, MA10230, MA10300, MA10650, MA10320PRO, MA10350, MA10410, MA10450, MA10660, MA10700, TFA 30.3312.02, MA10800, WL2000, TFA30.3060.01.IT<br>
  Supported but untested: ./.<br>
  <br>

  <a name="MOBILEALERTSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MOBILEALERTS &lt;deviceID&gt; &lt;corrTempIn&gt; &lt;corrHumIn&gt; &lt;corrTempOut&gt; &lt;corrHumOut&gt; &lt;corrTemp2&gt; &lt;corrHum2&gt; &lt;corrTemp3&gt; &lt;corrHum3&gt;</code><br>
    <br>
    deviceID is the sensorcode on the sensor.
    <br>
    corrTempIn optional: correction temperature
    <br>
    corrHumIn optional: correction humidity
    <br>
    corrTempOut optional: correction temperature out / sensor 1
    <br>
    corrHumOut optional: correction humidity out / sensor 1
    <br>
    corrTemp3 optional: correction temperature sensor 2
    <br>
    corrHum3 optional: correction humidity sensor 2
   <br>
    corrTemp4 optional: correction temperature sensor 3
    <br>
    corrHum4 optional: correction humidity sensor 3
  </ul>
  <br>

  <a name="MOBILEALERTSreadings"></a>
  <b>Readings</b>
  <ul>
    <li>lastMsg<br>The last message received (always for unknown devices, for known devices only if attr lastMsg is set).</li>
    <li>deviceType<br>The devicetype.</li>
    <li>lastRcv<br>Timestamp of last message.</li>
    <li>actStatus<br>Shows 'unknown', 'alive', 'dead', 'switchedOff' depending on attribut actCycle</li>
    <li>txCounter<br>Counter of last message.</li>
    <li>triggered<br>1=last message was triggered by a event.</li>
    <li>tempertature, prevTemperature, temperatureIn, temperatureOut, prevTemperatureIn, prevTemperatureOut<br>Temperature (depending on device and attribut expert).</li>
    <li>tempertatureString, prevTemperatureString, temperatureInString, temperatureOutString, prevTemperatureInString, prevTemperatureOutString<br>Temperature as string (depending on device and attribut expert).</li>
    <li>state<br>State of device (short actual reading)</li>
    <li>humidity, prevHumidity, humidityIn, humidityOut, prevHumidityIn, prevHumidityOut<br>Humidity (depending on device and attribut expert).</li>
    <li>humidityString, prevHumidityString, humidityInString, humidityOutString, prevHumidityInString, prevHumidityOutString<br>Humidity as string (depending on device and attribut expert).</li>
    <li>wetness<br>Shows if sensor detects water.</li>
    <li>lastEvent, lastEvent&lt;X&gt; ,lastEventString, lastEvent&lt;X&gt;String<br>Time when last event (rain) happend (MA10650 only).</li>
    <li>mmRain, mmRainActHour, mmRainLastHour, mmRainActDay, mmRainYesterday<br>Rain since reset of counter, current hour, last hour, current day, yesterday.</li>
    <li>direction, directionInt<br>Direction of wind.</li>
    <li>windSpeed, gustSpeed<br>Windspeed.</li>
  </ul>
  <br>  

  <a name="MOBILEALERTSset"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; clear &lt;readings|counters&gt;</code><br>
    Clears the readings (all) or counters (like mmRain). </li>
  </ul>
  <br>

  <a name="MOBILEALERTSget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>
  <br>

  <a name="MOBILEALERTSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>  
    <li>lastMsg<br>
      If value 1 is set, the last received message will be logged as reading even if device is known.
    </li>
    <li>actCycle &lt;[hhh:mm]|off&gt;<br>
      This value triggers a 'alive' and 'not alive' detection. [hhh:mm] is the maximum silent time for the device.
      The reading actStatus will show the states: 'unknown', 'alive', 'dead'.
    </li>
    <li>expert<br>
      Defines how many readings are show (0=only current, 1=previous, 4=all).
    </li>        
  </ul>
</ul>

=end html
=begin html_DE

<a name="MOBILEALERTS"></a>
<h3>MOBILEALERTS</h3>
<ul>
  MOBILEALERTS ist ein FHEM-Modul f&uuml; die deutschen MobileAlerts Ger&auml; und TFA WEATHERHUB.
  <br><br>
  Dieses FHEM Modul stellt jeweils ein MobileAlerts Ger&auml;t dar. Die Verbindung wird durch das 
  <a href="#MOBILEALERTSGW">MOBILELAERTSGW</a> Modul bereitgestellt.<br>
  Aktuell werden unterst&uuml;zt: MA10100, MA10101, MA10200, MA10230, MA10300, MA10650, MA10320PRO, MA10350, MA10410, MA10450, MA10660, MA10700, TFA 30.3312.02, MA10800, WL2000, TFA30.3060.01.IT<br>
  Unterst&uuml;zt aber ungetestet: ./.<br>
  <br>

  <a name="MOBILEALERTSdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; MOBILEALERTS &lt;deviceID&gt; &lt;corrTempIn&gt; &lt;corrHumIn&gt; &lt;corrTempOut&gt; &lt;corrHumOut&gt; &lt;corrTemp2&gt; &lt;corrHum2&gt; &lt;corrTemp3&gt; &lt;corrHum3&gt;</code><br>
    <br>
    deviceID ist der Sensorcode auf dem Sensor.
    <br>
    corrTempIn optional: Korrekturwert f&uuml;r Temperatur (bzw. Temperatur in)
    <br>
    corrHumIn optional: Korrekturwert f&uuml;r die Luftfeuchte
    <br>
    corrTempOut optional: Korrekturwert f&uuml;r Temperatur Out / Sensor 1
    <br>
    corrHumOut optional: Korrekturwert f&uuml;r die Luftfeuchte Out / Sensor 1
    <br>
    corrTemp2 optional: Korrekturwert f&uuml;r Temperatur Sensor 2
    <br>
    corrHum2 optional: Korrekturwert f&uuml;r die Luftfeuchte Sensor 2
    <br>
    corrTemp3 optional: Korrekturwert f&uuml;r Temperatur Sensor 3
    <br>
    corrHum3 optional: Korrekturwert f&uuml;r die Luftfeuchte Sensor 3
  </ul>
  <br>

  <a name="MOBILEALERTSreadings"></a>
  <b>Readings</b>
  <ul>
    <li>lastMsg<br>Die letzte empfangene Nachricht (immer f&uuml;r unbekannte Ger&auml;te, f&uuml;r bekannte nur wenn das Attribut lastMsg gesetzt ist).</li>
    <li>deviceType<br>Der Ger&auml;tetyü.</li>
    <li>lastRcv<br>Timestamp der letzten Nachricht.</li>
    <li>actStatus<br>Zeigt 'unknown', 'alive', 'dead', 'switchedOff' abh&auml;ngig vom Attribut actCycle</li>
    <li>txCounter<br>Counter des letzten Nachricht (wird 0 nach Batteriewechsel).</li>
    <li>triggered<br>1=letzte Nachricht wurde von einem Ereignis ausgel&ouml;st.</li>
    <li>tempertature, prevTemperature, temperatureIn, temperatureOut, prevTemperatureIn, prevTemperatureOut<br>Temperatur (abh&auml;nging vom Ger&auml;t und dem Attribut expert).</li>
    <li>tempertatureString, prevTemperatureString, temperatureInString, temperatureOutString, prevTemperatureInString, prevTemperatureOutString<br>Temperatur als Zeichkette.</li>
    <li>state<br>State of device (short actual reading)</li>
    <li>humidity, prevHumidity, humidityIn, humidityOut, prevHumidityIn, prevHumidityOut<br>Luftfeuchte (abh&auml;nging vom Ger&auml;t und dem Attribut expert).</li>
    <li>humidityString, prevHumidityString, humidityInString, humidityOutString, prevHumidityInString, prevHumidityOutString<br>Luftfeuchte als Zeichenkette</li>
    <li>wetness<br>Zeigt ob der Sensors Wasser entdeckt.</li>
    <li>lastEvent, lastEvent&lt;X&gt; ,lastEventString, lastEvent&lt;X&gt;String<br>Zeitpunkt wann das letzte Event (Regen) stattgefunden hat (nur MA10650).</li>
    <li>mmRain, mmRainActHour, mmRainLastHour, mmRainActDay, mmRainYesterday<br>Regen seit dem letzten Reset des Counters, in der aktuellen Stunde, seit der letzten Stunden, am aktuellen Tagn, gestern.</li>
    <li>direction, directionInt<br>Richtung des Winds.</li>
    <li>windSpeed, gustSpeed<br>Windgeschwindigkeit.</li>
  </ul>
  <br>    

  <a name="MOBILEALERTSset"></a>
  <b>Set</b>
  <ul>
    <li><code>set &lt;name&gt; clear &lt;readings|counters&gt;</code><br>
    L&ouml;scht die Readings (alle) oder Counter (wie mmRain). </li>
  </ul>
  <br>

  <a name="MOBILEALERTSget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>
  <br>

  <a name="MOBILEALERTSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>  
    <li>lastMsg<br>
      Wenn dieser Wert auf 1 gesetzt ist, wird die letzte erhaltene Nachricht als Reading gelogt auch wenn das Ger&auml bekannt ist.
    </li>
    <li>actCycle &lt;[hhh:mm]|off&gt;<br>
      Dieses Attribut erm&ouml;licht eine 'nicht erreichbarkeit' Erkennung.
      [hhh:mm] ist die maximale Zeit, innerhalb der keine Nachrichten empfrangen wird.
      Das Reading actStatus zeigt den Status 'unknown', 'alive', 'dead' an.
    </li>
    <li>expert<br>
      Gibt an wie detailiert die Readings angezeigt werden (0=nur aktuelle, 1=mit vorhergehenden, 4=alle).
    </li>    
  </ul>
</ul>

=end html_DE
=cut

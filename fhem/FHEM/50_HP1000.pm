###############################################################################
# $Id$
package main;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::smartmatch';
use Data::Dumper;
use Time::Local;
use Encode qw(encode_utf8 decode_utf8);
use List::Util qw(sum);

use HttpUtils;
use Unit;


# module hashes ###############################################################
my %HP1000_pwsMapping = (

    # PWS           => 'FHEM',

    # name translation for general readings
    light           => 'luminosity',
    solarradiation  => 'solarradiation',
    windcomp        => 'wind_compasspoint',
    windcomp_avg2m  => 'wind_compasspoint_avg2m',
    windcomp_avg10m => 'wind_compasspoint_avg10m',
    winddir         => 'wind_direction',
    winddir_avg2m   => 'wind_direction_avg2m',
    windgustdir     => 'wind_gust_direction',
    windgustdir_10m => 'wind_gust_direction_avg10m',

    # name translation for Metric standard
    dewpoint         => 'dewpoint',
    indewpoint       => 'indoorDewpoint',
    humidity         => 'humidity',
    outhumiabs       => 'humidityAbs',
    relbaro          => 'pressure',
    absbaro          => 'pressureAbs',
    indoorhumidity   => 'indoorHumidity',
    inhumiabs        => 'indoorHumidityAbs',
    rainrate         => 'rain',
    dailyrain        => 'rain_day',
    weeklyrain       => 'rain_week',
    monthlyrain      => 'rain_month',
    yearlyrain       => 'rain_year',
    outtemp          => 'temperature',
    intemp           => 'indoorTemperature',
    windchill        => 'wind_chill',
    windgust         => 'wind_gust',
    windgust_10m     => 'wind_gust_max10m',
    windgustmps      => 'wind_gust_mps',
    windgustmps_10m  => 'wind_gust_mps_max10m',
    windspeed        => 'wind_speed',
    windspeed_avg2m  => 'wind_speed_avg2m',
    windspeedmps     => 'wind_speed_mps',
    windspdmps_avg2m => 'wind_speed_mps_avg2m',

    # other formats
    barommm          => 'pressure_mm',
    absbarommm       => 'pressureAbs_mm',
    windgustbft      => 'wind_gust_bft',
    windgustbft_10m  => 'wind_gust_bft_max10m',
    windgustkn       => 'wind_gust_kn',
    windgustkn_10m   => 'wind_gust_kn_max10m',
    windspeedbft     => 'wind_speed_bft',
    windspdbft_avg2m => 'wind_speed_bft_avg2m',
    windspeedkn      => 'wind_speed_kn',
    windspdkn_avg2m  => 'wind_speed_kn_avg2m',

    # name translation for Angloamerican standard
    dewptf             => 'dewpoint_f',
    indoordewptf       => 'indoorDewpoint_f',
    outhumi            => 'humidity',
    outhumiabsf        => 'humidityAbs_f',
    baromin            => 'pressure_in',
    absbaromin         => 'pressureAbs_in',
    inhumi             => 'indoorHumidity',
    indoorhumidityabsf => 'indoorHumidityAbs',
    rainin             => 'rain_in',
    dailyrainin        => 'rain_day_in',
    weeklyrainin       => 'rain_week_in',
    monthlyrainin      => 'rain_month_in',
    yearlyrainin       => 'rain_year_in',
    tempf              => 'temperature_f',
    indoortempf        => 'indoorTemperature_f',
    windchillf         => 'wind_chill_f',
    windgustfts        => 'wind_gust_fts',
    windgustfts_10m    => 'wind_gust_fts_max10m',
    windgustmph        => 'wind_gust_mph',
    windgustmph_10m    => 'wind_gust_mph_max10m',
    windspeedfts       => 'wind_speed_fts',
    windspdfts_avg2m   => 'wind_speed_fts_avg2m',
    windspeedmph       => 'wind_speed_mph',
    windspdmph_avg2m   => 'wind_speed_mph_avg2m',
);

my %HP1000_wuParams = (
    action           => 1,
    baromin          => 1,
    clouds           => 1,
    dailyrainin      => 1,
    dateutc          => 1,
    dewptf           => 1,
    humidity         => 1,
    ID               => 1,
    indoorhumidity   => 1,
    indoortempf      => 1,
    lowbatt          => 1,
    monthlyrainin    => 1,
    PASSWORD         => 1,
    rainin           => 1,
    realtime         => 1,
    rtfreq           => 1,
    softwaretype     => 1,
    solarradiation   => 1,
    tempf            => 1,
    UV               => 1,
    weather          => 1,
    weeklyrainin     => 1,
    windchillf       => 1,
    winddir          => 1,
    winddir_avg2m    => 1,
    windgustdir      => 1,
    windgustdir_10m  => 1,
    windgustmph      => 1,
    windgustmph_10m  => 1,
    windspdmph_avg2m => 1,
    windspeedmph     => 1,
    yearlyrainin     => 1,
);

# initialize ##################################################################
sub HP1000_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "HP1000_Initialize: Entering";

    if ( !$modules{dewpoint}{LOADED}
        && -f "$attr{global}{modpath}/FHEM/98_dewpoint.pm" )
    {
        my $ret = CommandReload( undef, "98_dewpoint" );
        Log3 undef, 1, $ret if ($ret);
    }

    my $webhookFWinstance =
      join( ",", devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') );

    $hash->{GetFn}         = "HP1000_Get";
    $hash->{DefFn}         = "HP1000_Define";
    $hash->{UndefFn}       = "HP1000_Undefine";
    $hash->{DbLog_splitFn} = "Unit_DbLog_split";
    $hash->{parseParams}   = 1;

    $hash->{AttrList} =
"disable:1,0 disabledForIntervals do_not_notify:1,0 wu_push:1,0 wu_indoorValues:1,0 wu_id wu_password wu_realtime:1,0 wu_dataValues extSrvPush_Url stateReadingsLang:en,de,at,ch,nl,fr,pl webhookFWinstances:sortable-strict,$webhookFWinstance stateReadings stateReadingsFormat:0,1 "
      . $readingFnAttributes;

    my @wu;
    foreach ( keys %HP1000_wuParams ) {
        next unless ( $HP1000_pwsMapping{$_} );
        push @wu, $HP1000_pwsMapping{$_};
    }

    $hash->{AttrList} .= " wu_pushValues:multiple," . join( ",", sort @wu );

    # Unit.pm support
    $hash->{readingsDesc} = {
        'Activity'              => { rtype => 'oknok', },
        'UV'                    => { rtype => 'uvi', },
        'UVR'                   => { rtype => 'uwpscm', },
        'UVcondition'           => { rtype => 'condition_uvi', },
        'UVcondition_rgb'       => { rtype => 'rgbhex', },
        'battery'               => { rtype => 'oknok', },
        'condition'             => { rtype => 'condition_weather', },
        'daylight'              => { rtype => 'yesno', },
        'dewpoint'              => { rtype => 'c', formula_symbol => 'Td', },
        'dewpoint_f'            => { rtype => 'f', formula_symbol => 'Td', },
        'extsrv_state'          => { rtype => 'oknok', },
        'humidity'              => { rtype => 'pct', formula_symbol => 'H', },
        'humidityAbs'           => { rtype => 'c', formula_symbol => 'Tabs', },
        'humidityAbs_f'         => { rtype => 'f', formula_symbol => 'Tabs', },
        'humidityCondition'     => { rtype => 'condition_hum', },
        'humidityCondition_rgb' => { rtype => 'rgbhex', },
        'indoorDewpoint'        => { rtype => 'c', formula_symbol => 'Tdi', },
        'indoorDewpoint_f'      => { rtype => 'f', formula_symbol => 'Tdi', },
        'indoorHumidity'        => { rtype => 'pct', formula_symbol => 'Hi', },
        'indoorHumidityAbs'     => { rtype => 'c', formula_symbol => 'Tabsi', },
        'indoorHumidityAbs_f'   => { rtype => 'f', formula_symbol => 'Tabsi', },
        'indoorHumidityCondition'     => { rtype => 'condition_hum', },
        'indoorHumidityCondition_rgb' => { rtype => 'rgbhex', },
        'indoorTemperature' => { rtype => 'c', formula_symbol => 'Ti', },
        'indoorTemperature_f' => { rtype => 'f', formula_symbol => 'Ti', },

        #'indoorTemperatureCondition'     => {},
        'indoorTemperatureCondition_rgb' => { rtype => 'rgbhex', },
        'israining'                      => { rtype => 'yesno', },
        'luminosity'                     => { rtype => 'lx', },
        'pressure'                       => { rtype => 'hpamb', },
        'pressureAbs'                    => { rtype => 'hpamb', },
        'pressureAbs_in'                 => { rtype => 'inhg', },
        'pressureAbs_mm'                 => { rtype => 'mmhg', },
        'pressure_in'                    => { rtype => 'inhg', },
        'pressure_mm'                    => { rtype => 'mmhg', },
        'rain'                           => { rtype => 'mm', },
        'rain_day'                       => { rtype => 'mm', },
        'rain_day_in'                    => { rtype => 'in', },
        'rain_in'                        => { rtype => 'in', },
        'rain_month'                     => { rtype => 'mm', },
        'rain_month_in'                  => { rtype => 'in', },
        'rain_week'                      => { rtype => 'mm', },
        'rain_week_in'                   => { rtype => 'in', },
        'rain_year'                      => { rtype => 'mm', },
        'rain_year_in'                   => { rtype => 'in', },
        'solarradiation'                 => { rtype => 'wpsm', },
        'temperature'                    => { rtype => 'c', },
        'temperature_f'                  => { rtype => 'f', },

        #'temperatureCondition'           => {},
        'temperatureCondition_rgb' => { rtype => 'rgbhex', },

        #'windCondition'                  => {},
        'windCondition_rgb' => { rtype => 'rgbhex', },

        #'windWarning'                    => {},
        'wind_compasspoint'        => { rtype => 'compasspoint', },
        'wind_compasspoint_avg2m'  => { rtype => 'compasspoint', },
        'wind_compasspoint_avg10m' => { rtype => 'compasspoint', },
        'wind_chill'               => { rtype => 'c', formula_symbol => 'Wc', },
        'wind_chill_f'             => { rtype => 'f', formula_symbol => 'Wc', },
        'wind_direction' =>
          { rtype => 'compasspoint', formula_symbol => 'Wdir', },
        'wind_direction_avg2m' =>
          { rtype => 'compasspoint', formula_symbol => 'Wdir', },
        'wind_gust'     => { rtype => 'kmph', formula_symbol => 'Wg', },
        'wind_gust_bft' => { rtype => 'bft',  formula_symbol => 'Wg', },
        'wind_gust_direction_avg10m' =>
          { rtype => 'compasspoint', formula_symbol => 'Wdir', },
        'wind_gust_fts'        => { rtype => 'fts',  formula_symbol => 'Wg', },
        'wind_gust_kn'         => { rtype => 'kn',   formula_symbol => 'Wg', },
        'wind_gust_mph'        => { rtype => 'mph',  formula_symbol => 'Wg', },
        'wind_gust_mph_max10m' => { rtype => 'mph',  formula_symbol => 'Wg', },
        'wind_gust_mps'        => { rtype => 'mps',  formula_symbol => 'Wg', },
        'wind_gust_max10m'     => { rtype => 'kmph', formula_symbol => 'Wg', },
        'wind_speed'           => { rtype => 'kmph', formula_symbol => 'W', },
        'wind_speed_avg2m'     => { rtype => 'kmph', formula_symbol => 'W', },
        'wind_speed_bft'       => { rtype => 'bft',  formula_symbol => 'W', },
        'wind_speed_bft_avg2m' => { rtype => 'bft',  formula_symbol => 'W', },
        'wind_speed_kn'        => { rtype => 'kn',   formula_symbol => 'W', },
        'wind_speed_kn_avg2m'  => { rtype => 'kn',   formula_symbol => 'W', },
        'wind_speed_mph'       => { rtype => 'mph',  formula_symbol => 'W', },
        'wind_speed_mph_avg2m' => { rtype => 'mph',  formula_symbol => 'W', },
        'wind_speed_mps'       => { rtype => 'mps',  formula_symbol => 'W', },
        'wind_speed_mps_avg2m' => { rtype => 'mps',  formula_symbol => 'W', },
        'wu_state' => { rtype => 'oknok', },
    };

    # 98_powerMap.pm support
    $hash->{powerMap} = {
        rname_E => 'energy',
        rname_P => 'consumption',
        map     => {
            Activity => {
                'dead'  => 0,
                'alive' => 5,
            },
            state => {
                '*' => 'Activity',
            },
        },
    };
}

# regular Fn ##################################################################
sub HP1000_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    return "Usage: define <name> HP1000 [<ID> <PASSWORD>]"
      if ( int(@$a) < 2 );

    $hash->{ID}       = @$a[2] if ( defined( @$a[2] ) );
    $hash->{PASSWORD} = @$a[3] if ( defined( @$a[3] ) );

    return
        "Device already defined: "
      . $modules{HP1000}{defptr}{NAME}
      . " (there can only be one instance as per restriction of the weather station itself)"
      if ( defined( $modules{HP1000}{defptr} ) && !defined( $hash->{OLDDEF} ) );

    # check FHEMWEB instance
    if ( $init_done && !defined( $hash->{OLDDEF} ) ) {
        my $FWports;
        foreach ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
            $hash->{FW} = $_
              if ( AttrVal( $_, "webname", "fhem" ) eq "weatherstation" );
            push( @{$FWports}, $defs{$_}->{PORT} )
              if ( defined( $defs{$_}->{PORT} ) );
        }

        if ( !defined( $hash->{FW} ) ) {
            $hash->{FW} = "WEBweatherstation";
            my $port = 8084;
            until ( !grep ( /^$port$/, @{$FWports} ) ) {
                $port++;
            }

            if ( !defined( $defs{ $hash->{FW} } ) ) {

                Log3 $name, 3,
                    "HP1000 $name: Creating new FHEMWEB instance "
                  . $hash->{FW}
                  . " with webname 'weatherstation'";

                fhem "define " . $hash->{FW} . " FHEMWEB $port global";
                fhem "attr " . $hash->{FW} . " closeConn 1";
                fhem "attr " . $hash->{FW} . " webname weatherstation";
            }
        }

        $hash->{FW_PORT} = $defs{ $hash->{FW} }{PORT};

        fhem 'attr ' . $name . ' stateReadings temperature humidity';
        fhem 'attr ' . $name . ' stateReadingsFormat 1';
    }

    if ( HP1000_addExtension( $name, "HP1000_CGI", "updateweatherstation" ) ) {
        $hash->{fhem}{infix} = "updateweatherstation";
    }
    else {
        return "Error registering FHEMWEB infix";
    }

    # create global unique device definition
    $modules{HP1000}{defptr} = $hash;

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + 120, "HP1000_SetAliveState", $hash, 0 );

    return undef;
}

sub HP1000_Undefine($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "HP1000 $name: called function HP1000_Undefine()";

    HP1000_removeExtension( $hash->{fhem}{infix} );

    # release global unique device definition
    delete $modules{HP1000}{defptr};

    RemoveInternalTimer($hash);

    return undef;
}

sub HP1000_Get($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};
    my $wu_id = AttrVal( $name, "wu_id", "" );

    Log3 $name, 5, "HP1000 $name: called function HP1000_Get()";

    return "Argument is missing" if ( int(@$a) < 1 );

    my $usage = "Unknown argument " . @$a[1] . ", choose one of";
    $usage .= " createWUforecast" if ( $wu_id ne "" );

    my $cmd = '';
    my $result;

    # createWUforecast
    if ( lc( @$a[1] ) eq "createwuforecast" ) {
        return "Attribute wu_id "
          . "does not contain a PWS ID to create a Wunderground device"
          if ( $wu_id eq "" );

        my @wudev = devspec2array("TYPE=Wunderground:FILTER=PWS_ID=$wu_id");

        if ( !@wudev ) {
            return "Missing WU API key" if ( !defined( @$a[2] ) );
            Log3 $name, 3, "HP1000 get $name " . @$a[1] . " " . @$a[2];

            $result =
              fhem "define $name" . "_WU Wunderground " . @$a[2] . " $wu_id";
            $result = $name . "_WU created"
              if ( !defined($result) );
        }
        else {
            $result = "Found existing WU device for this PWS ID: $wudev[0]";
        }
    }

    # return usage hint
    else {
        return $usage;
    }

    return $result;
}

# module Fn ####################################################################
sub HP1000_CGI() {

    my ($request) = @_;

    my $hash;
    my $name = "";
    my $link;
    my $URI;
    my $result = "Initialized";
    my $webArgs;
    my $servertype;

    #TODO: should better be blocked in FHEMWEB already
    return ( "text/plain; charset=utf-8", "Booting up" )
      unless ($init_done);

    # data received
    if ( $request =~ /^\/updateweatherstation\.(\w{3})\?(.+=.+)/ ) {
        $servertype = lc($1);
        $URI        = $2;

        # get device name
        $name = $data{FWEXT}{"/updateweatherstation"}{deviceName}
          if ( defined( $data{FWEXT}{"/updateweatherstation"} ) );

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "No HP1000 device for webhook /updateweatherstation" )
          unless ( IsDevice( $name, 'HP1000' ) );

        # incorrect FHEMWEB instance used
        my @webhookFWinstances = split( ",",
            AttrVal( $name, "webhookFWinstances", "weatherstation" ) );

        return ( "text/plain; charset=utf-8",
            "incorrect FHEMWEB instance to receive data" )
          unless ( $FW_wname ~~ @webhookFWinstances );

        # extract values from URI
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = Encode::encode_utf8($v)
              if ( $v ne "" );
        }

        if (   !defined( $webArgs->{softwaretype} )
            || !defined( $webArgs->{dateutc} )
            || !defined( $webArgs->{action} ) )
        {
            Log3 $name, 5,
              "HP1000: received insufficient data:\n" . Dumper($webArgs);

            return ( "text/plain; charset=utf-8", "Insufficient data" );
        }

        if ( $webArgs->{action} ne "updateraw" ) {
            Log3 $name, 5,
              "HP1000: action $webArgs->{action} is not implemented:\n"
              . Dumper($webArgs);

            return ( "text/plain; charset=utf-8",
                "Action $webArgs->{action} was not implemented" );
        }

        if (
               defined( $hash->{ID} )
            && defined( $hash->{PASSWORD} )
            && (   $hash->{ID} ne $webArgs->{ID}
                || $hash->{PASSWORD} ne $webArgs->{PASSWORD} )
          )
        {
            Log3 $name, 4,
              "HP1000: received data containing wrong credentials:\n"
              . Dumper($webArgs);

            return ( "text/plain; charset=utf-8", "Wrong credentials" );
        }
    }

    # no data received
    else {
        return ( "text/plain; charset=utf-8", "Missing data" );
    }

    $hash = $defs{$name};
    my $uptime = time() - $fhem_started;

    delete $hash->{FORECASTDEV} if ( $hash->{FORECASTDEV} );
    my @wudev = devspec2array(
        "TYPE=Wunderground:FILTER=PWS_ID=" . AttrVal( $name, "wu_id", "-" ) );
    $hash->{FORECASTDEV} = $wudev[0]
      if ( defined( $wudev[0] ) );

    HP1000_SetAliveState( $hash, 1 );

    $hash->{IP}          = $defs{$FW_cname}{PEER};
    $hash->{SERVER_TYPE} = $servertype;
    $hash->{SWVERSION}   = $webArgs->{softwaretype};
    $hash->{INTERVAL}    = (
        $hash->{SYSTEMTIME_UTC}
        ? time_str2num( $webArgs->{dateutc} ) -
          time_str2num( $hash->{SYSTEMTIME_UTC} )
        : 0
    );
    $hash->{SYSTEMTIME_UTC} = $webArgs->{dateutc};
    $hash->{FW}             = "";
    $hash->{FW_PORT}        = "";
    $hash->{UPLOAD_TYPE}    = "default";
    $hash->{UPLOAD_TYPE}    = "customize"
      if ( defined( $webArgs->{solarradiation} ) );

    foreach ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
        if ( AttrVal( $_, "webname", "fhem" ) eq "weatherstation" ) {
            $hash->{FW}      = $_;
            $hash->{FW_PORT} = $defs{$_}{PORT};
            last;
        }
    }

    Log3 $name, 5,
      "HP1000: received data (uptime=$uptime):\n" . Dumper($webArgs);

    # rename wind speed values as those are in m/sec and
    # we want km/h to be our metric default
    if ( defined( $webArgs->{windspeed} ) ) {
        $webArgs->{windspeedmps} = $webArgs->{windspeed};
        delete $webArgs->{windspeed};
    }
    if ( defined( $webArgs->{windgust} ) ) {
        $webArgs->{windgustmps} = $webArgs->{windgust};
        delete $webArgs->{windgust};
    }

    # Special handling for humidity values
    $webArgs->{inhumi} = $webArgs->{indoorhumidity}
      if ( defined( $webArgs->{indoorhumidity} )
        && !defined( $webArgs->{inhumi} ) );

    $webArgs->{indoorhumidity} = $webArgs->{inhumi}
      if ( defined( $webArgs->{inhumi} )
        && !defined( $webArgs->{indoorhumidity} ) );

    $webArgs->{outhumi} = $webArgs->{humidity}
      if ( defined( $webArgs->{humidity} )
        && !defined( $webArgs->{outhumi} ) );

    $webArgs->{humidity} = $webArgs->{outhumi}
      if ( defined( $webArgs->{outhumi} )
        && !defined( $webArgs->{humidity} ) );

    my %HP1000_pwsMappingEquivalent = (

        # Metric       => 'Angloamerican',

        dewpoint       => 'dewptf',
        indewpoint     => 'indoordewptf',
        humidity       => 'outhumi',
        outhumiabs     => 'outhumiabsf',
        relbaro        => 'baromin',
        absbaro        => 'absbaromin',
        indoorhumidity => 'inhumi',
        inhumiabs      => 'indoorhumidityabsf',
        rainrate       => 'rainin',
        dailyrain      => 'dailyrainin',
        weeklyrain     => 'weeklyrainin',
        monthlyrain    => 'monthlyrainin',
        yearlyrain     => 'yearlyrainin',
        outtemp        => 'tempf',
        intemp         => 'indoortempf',
        windchill      => 'windchillf',
        windgustmps    => 'windgustmph',
        windspeedmps   => 'windspeedmph',
    );

    my %HP1000_pwsMappingEquivalent_rev =
      %{ { reverse %HP1000_pwsMappingEquivalent } };

    # calculate readings for Metric standard from Angloamerican standard
    #

    # calculate Celsius based values based on Fahrenheit
    foreach ( 'dewptf', 'tempf', 'indoortempf', 'windchillf' ) {
        my $k = $HP1000_pwsMappingEquivalent_rev{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        $webArgs->{$k} = UConv::f2c( $webArgs->{$_} );
        Log3 $name, 5,
          "HP1000: "
          . "Adding calculated value for $k=$webArgs->{$k} from $_=$webArgs->{$_}";
    }

    # calculate hPa based values based on inHg
    foreach ( 'baromin', 'absbaromin' ) {
        my $k = $HP1000_pwsMappingEquivalent_rev{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        $webArgs->{$k} = UConv::inhg2hpa( $webArgs->{$_} );
        Log3 $name, 5,
          "HP1000: "
          . "Adding calculated value for $k=$webArgs->{$k} from $_=$webArgs->{$_}";
    }

    # calculate milimeter based values based on inch
    foreach (
        'rainin',        'dailyrainin', 'weeklyrainin',
        'monthlyrainin', 'yearlyrainin'
      )
    {
        my $k = $HP1000_pwsMappingEquivalent_rev{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        $webArgs->{$k} = UConv::in2mm( $webArgs->{$_} );
        Log3 $name, 5,
          "HP1000: "
          . "Adding calculated value for $k=$webArgs->{$k} from $_=$webArgs->{$_}";
    }

    # calculate kph based values based on mph
    foreach ( 'windgustmph', 'windspeedmph' ) {
        my $k = $HP1000_pwsMappingEquivalent_rev{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        $webArgs->{$k} = UConv::mph2mps( $webArgs->{$_} );
        Log3 $name, 5,
          "HP1000: "
          . "Adding calculated value for $k=$webArgs->{$k} from $_=$webArgs->{$_}";
    }

    # windgust in km/h (convert from windgustmps)
    if ( defined( $webArgs->{windgustmps} )
        && !defined( $webArgs->{windgust} ) )
    {
        $webArgs->{windgust} =
          UConv::mps2kph( $webArgs->{windgustmps} );
        Log3 $name, 5,
          "HP1000: "
          . "Adding calculated value for windgust=$webArgs->{windgust} from windgustmps=$webArgs->{windgustmps}";
    }

    # windspeed in km/h (convert from windspeedmps)
    if ( defined( $webArgs->{windspeedmps} )
        && !defined( $webArgs->{windspeed} ) )
    {
        Log3 $name, 5,
          "HP1000: Adding calculated value for windspeed from windspeedmps";
        $webArgs->{windspeed} =
          UConv::mps2kph( $webArgs->{windspeedmps} );
    }

    # windgust in km/h (convert from windgustmph)
    if ( defined( $webArgs->{windgustmph} )
        && !defined( $webArgs->{windgust} ) )
    {
        Log3 $name, 5,
          "HP1000: Adding calculated value for windgust from windgustmph";
        $webArgs->{windgust} =
          UConv::mph2kph( $webArgs->{windgustmph} );
    }

    # windspeed in km/h (convert from windspeedmph)
    if ( defined( $webArgs->{windspeedmph} )
        && !defined( $webArgs->{windspeed} ) )
    {
        Log3 $name, 5,
          "HP1000: Adding calculated value for windspeed from windspeedmph";
        $webArgs->{windspeed} =
          UConv::mps2kph( $webArgs->{windspeedmph} );
    }

    # calculate readings for Angloamerican standard from Metric standard
    #

    # calculate Fahrenheit based values based on Celsius
    foreach ( 'dewpoint', 'outtemp', 'intemp', 'windchill' ) {
        my $k = $HP1000_pwsMappingEquivalent{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        Log3 $name, 5, "HP1000: Adding calculated value for $k from $_";
        $webArgs->{$k} = UConv::c2f( $webArgs->{$_} );
    }

    # calculate inHg based values based on hPa
    foreach ( 'relbaro', 'absbaro' ) {
        my $k = $HP1000_pwsMappingEquivalent{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        Log3 $name, 5, "HP1000: Adding calculated value for $k from $_";
        $webArgs->{$k} = UConv::hpa2inhg( $webArgs->{$_}, 2 );
    }

    # calculate inch based values based on milimeter
    foreach ( 'rainrate', 'dailyrain', 'weeklyrain', 'monthlyrain',
        'yearlyrain' )
    {
        my $k = $HP1000_pwsMappingEquivalent{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        Log3 $name, 5, "HP1000: Adding calculated value for $k from $_";
        $webArgs->{$k} = UConv::mm2in( $webArgs->{$_}, 2 );
    }

    # calculate kph based values based on mph
    foreach ( 'windgustmps', 'windspeedmps' ) {
        my $k = $HP1000_pwsMappingEquivalent{$_};
        next unless ( $webArgs->{$_} && $k && !defined( $webArgs->{$k} ) );

        Log3 $name, 5, "HP1000: Adding calculated value for $k from $_";
        $webArgs->{$k} = UConv::mps2mph( $webArgs->{$_} );
    }

    # windgustmph in mph (convert from windgustmps)
    if ( defined( $webArgs->{windgustmps} )
        && !defined( $webArgs->{windgustmph} ) )
    {
        Log3 $name, 5,
          "HP1000: Adding calculated value for windgustmph from windgustmps";
        $webArgs->{windgustmph} =
          UConv::mps2mph( $webArgs->{windgustmps} );
    }

    # windspeedmph in mph (convert from windspeedmps)
    if ( defined( $webArgs->{windspeedmps} )
        && !defined( $webArgs->{windspeedmph} ) )
    {
        Log3 $name, 5,
          "HP1000: Adding calculated value for windspeedmph from windspeedmps";
        $webArgs->{windspeedmph} =
          UConv::mps2mph( $webArgs->{windspeedmps} );
    }

    # write general readings
    #
    readingsBeginUpdate($hash);

    while ( ( my $p, my $v ) = each %$webArgs ) {

        # ignore those values
        next
          if ( $p eq "action"
            || $p eq "dateutc"
            || $p eq "lowbatt"
            || $p eq "realtime"
            || $p eq "rtfreq"
            || $p eq "softwaretype"
            || $p eq "humidity"
            || $p eq "indoorhumidity"
            || $p eq "UV"
            || $p eq "UVR"
            || $p eq "ID"
            || $p eq "PASSWORD" );

        $p = $HP1000_pwsMapping{$p} ? $HP1000_pwsMapping{$p} : "_" . $p;

        readingsBulkUpdate( $hash, $p, $v );
    }

    # calculate additional readings
    #

    # battery
    my $battery = "ok";
    if ( defined( $webArgs->{lowbatt} ) ) {
        $battery = "low" if ( $webArgs->{lowbatt} );
        readingsBulkUpdateIfChanged( $hash, "battery", $battery );
    }

    # israining
    my $israining = 0;
    $israining = 1
      if ( defined( $webArgs->{rainrate} ) && $webArgs->{rainrate} > 0 );
    readingsBulkUpdateIfChanged( $hash, "israining", $israining );

    # solarradiation in W/m2 (convert from lux)
    if ( defined( $webArgs->{light} )
        && !defined( $webArgs->{solarradiation} ) )
    {
        $webArgs->{solarradiation} =
          UConv::lux2wpsm( $webArgs->{light}, 2 );
        readingsBulkUpdate( $hash, "solarradiation",
            $webArgs->{solarradiation} );
    }

    # luminosity in lux (convert from W/m2)
    if ( defined( $webArgs->{solarradiation} )
        && !defined( $webArgs->{light} ) )
    {
        $webArgs->{light} =
          UConv::wpsm2lux( $webArgs->{solarradiation} );
        readingsBulkUpdate( $hash, "luminosity", $webArgs->{light} );
    }

    # daylight
    my $daylight = 0;
    $daylight = 1
      if ( defined( $webArgs->{light} ) && $webArgs->{light} > 50 );
    readingsBulkUpdateIfChanged( $hash, "daylight", $daylight );

    # condition
    if ( defined( $webArgs->{light} ) ) {
        my $temp =
          ( defined( $webArgs->{outtemp} ) ? $webArgs->{outtemp} : "10" );
        my $hum = ( $webArgs->{outhumi} ? $webArgs->{outhumi} : "50" );

        readingsBulkUpdateIfChanged(
            $hash,
            "condition",
            UConv::values2weathercondition(
                $temp, $hum, $webArgs->{light}, $daylight, $israining
            )
        );
    }

    # temperatureCondition
    if ( defined( $webArgs->{windchill} ) ) {
        my $avg =
          HP1000_GetAvg( $hash, "windchill", 600, $webArgs->{windchill} );

        if ( $hash->{INTERVAL} > 0 ) {
            my ( $cond, $rgb ) = UConv::c2condition($avg);
            readingsBulkUpdateIfChanged( $hash, "temperatureCondition", $cond );
            readingsBulkUpdateIfChanged( $hash, "temperatureCondition_rgb",
                $rgb );
        }
    }

    # indoorTemperatureCondition
    if ( defined( $webArgs->{intemp} ) ) {
        my ( $v, $rgb ) = UConv::c2condition( $webArgs->{intemp}, 1 );
        readingsBulkUpdateIfChanged( $hash, "indoorTemperatureCondition", $v );
        readingsBulkUpdateIfChanged( $hash, "indoorTemperatureCondition_rgb",
            $rgb );
    }

    # humidityCondition
    if ( defined( $webArgs->{outhumi} ) ) {
        my ( $v, $rgb ) = UConv::humidity2condition( $webArgs->{outhumi} );
        readingsBulkUpdateIfChanged( $hash, "humidityCondition",     $v );
        readingsBulkUpdateIfChanged( $hash, "humidityCondition_rgb", $rgb );
    }

    # indoorHumidityCondition
    if ( defined( $webArgs->{inhumi} ) ) {
        my ( $v, $rgb ) = UConv::humidity2condition( $webArgs->{inhumi}, 1 );
        readingsBulkUpdateIfChanged( $hash, "indoorHumidityCondition", $v );
        readingsBulkUpdateIfChanged( $hash, "indoorHumidityCondition_rgb",
            $rgb );
    }

    if ( defined( $webArgs->{UV} ) ) {

        # UV is already in UV-index format when upload-type
        # is set to 'customize'. Wunderground format is 'customize'.
        if ( $hash->{UPLOAD_TYPE} eq "customize" ) {
            $webArgs->{UVR} = UConv::uvi2uwpscm( $webArgs->{UV} )
              unless ( defined( $webArgs->{UVR} ) );
        }
        else {
            $webArgs->{UVR} = $webArgs->{UV};
            $webArgs->{UV}  = UConv::uwpscm2uvi( $webArgs->{UVR} );
        }

        readingsBulkUpdate( $hash, "UV",  $webArgs->{UV} );
        readingsBulkUpdate( $hash, "UVR", $webArgs->{UVR} );

        # UVcondition
        my ( $v, $rgb ) = UConv::uvi2condition( $webArgs->{UV} );
        readingsBulkUpdateIfChanged( $hash, "UVcondition",     $v );
        readingsBulkUpdateIfChanged( $hash, "UVcondition_rgb", $rgb );
    }

    # pressure_mm in mmHg (convert from hpa)
    if ( defined( $webArgs->{relbaro} ) ) {
        $webArgs->{barommm} = UConv::hpa2mmhg( $webArgs->{relbaro} );
        readingsBulkUpdate( $hash, "pressure_mm", $webArgs->{barommm} );
    }

    # pressureAbs_mm in mmHg (convert from hpa)
    if ( defined( $webArgs->{absbaro} ) ) {
        $webArgs->{absbarommm} =
          UConv::hpa2mmhg( $webArgs->{absbaro} );
        readingsBulkUpdate( $hash, "pressureAbs_mm", $webArgs->{absbarommm} );
    }

    # indoorDewpoint in Celsius
    if (   defined( $webArgs->{intemp} )
        && defined( $webArgs->{inhumi} )
        && exists &dewpoint_dewpoint )
    {
        my $h = (
            $webArgs->{inhumi} > 110
            ? 110
            : ( $webArgs->{inhumi} <= 0 ? 0.01 : $webArgs->{inhumi} )
        );

        $webArgs->{indewpoint} =
          round( dewpoint_dewpoint( $webArgs->{intemp}, $h ), 1 );
        readingsBulkUpdate( $hash, "indoorDewpoint", $webArgs->{indewpoint} );
    }

    # indoorDewpoint in Fahrenheit
    if (   defined( $webArgs->{indoortempf} )
        && defined( $webArgs->{indoorhumidity} )
        && exists &dewpoint_dewpoint )
    {
        my $h = (
            $webArgs->{indoorhumidity} > 110 ? 110
            : (
                  $webArgs->{indoorhumidity} <= 0 ? 0.01
                : $webArgs->{indoorhumidity}
            )
        );

        $webArgs->{indoordewptf} =
          round( dewpoint_dewpoint( $webArgs->{indoortempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "indoorDewpoint_f",
            $webArgs->{indoordewptf} );
    }

    # humidityAbs
    if (   defined( $webArgs->{outtemp} )
        && defined( $webArgs->{outhumi} )
        && looks_like_number( $webArgs->{outtemp} )
        && looks_like_number( $webArgs->{outhumi} )
        && exists &dewpoint_absFeuchte )
    {
        my $h = (
            $webArgs->{outhumi} > 110
            ? 110
            : ( $webArgs->{outhumi} <= 0 ? 0.01 : $webArgs->{outhumi} )
        );
        $webArgs->{outhumiabs} =
          round( dewpoint_absFeuchte( $webArgs->{outtemp}, $h ), 1 );
        readingsBulkUpdate( $hash, "humidityAbs", $webArgs->{outhumiabs} );
    }

    # humidityAbs_f
    if (   defined( $webArgs->{tempf} )
        && defined( $webArgs->{outhumi} )
        && looks_like_number( $webArgs->{tempf} )
        && looks_like_number( $webArgs->{outhumi} )
        && exists &dewpoint_absFeuchte )
    {
        my $h = (
            $webArgs->{outhumi} > 110
            ? 110
            : ( $webArgs->{outhumi} <= 0 ? 0.01 : $webArgs->{outhumi} )
        );
        $webArgs->{outhumiabsf} =
          round( dewpoint_absFeuchte( $webArgs->{tempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "humidityAbs_f", $webArgs->{outhumiabsf} );
    }

    # indoorHumidityAbs
    if (   defined( $webArgs->{intemp} )
        && defined( $webArgs->{inhumi} )
        && looks_like_number( $webArgs->{intemp} )
        && looks_like_number( $webArgs->{inhumi} )
        && exists &dewpoint_absFeuchte )
    {
        my $h = (
            $webArgs->{inhumi} > 110
            ? 110
            : ( $webArgs->{inhumi} <= 0 ? 0.01 : $webArgs->{inhumi} )
        );
        $webArgs->{inhumiabs} =
          round( dewpoint_absFeuchte( $webArgs->{intemp}, $h ), 1 );
        readingsBulkUpdate( $hash, "indoorHumidityAbs", $webArgs->{inhumiabs} );
    }

    # indoorHumidityAbs_f
    if (   defined( $webArgs->{indoortempf} )
        && defined( $webArgs->{indoorhumidity} )
        && looks_like_number( $webArgs->{indoortempf} )
        && looks_like_number( $webArgs->{indoorhumidity} )
        && exists &dewpoint_absFeuchte )
    {
        my $h = (
            $webArgs->{indoorhumidity} > 110 ? 110
            : (
                  $webArgs->{indoorhumidity} <= 0 ? 0.01
                : $webArgs->{indoorhumidity}
            )
        );
        $webArgs->{indoorhumidityabsf} =
          round( dewpoint_absFeuchte( $webArgs->{indoortempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "indoorHumidityAbs_f",
            $webArgs->{indoorhumidityabsf} );
    }

    # wind_compasspoint
    if ( defined( $webArgs->{winddir} ) ) {
        $webArgs->{windcomp} =
          UConv::direction2compasspoint( $webArgs->{winddir} );
        readingsBulkUpdate( $hash, "wind_compasspoint", $webArgs->{windcomp} );
    }

    # wind_speed_bft in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windspeed} ) ) {
        $webArgs->{windspeedbft} =
          UConv::kph2bft( $webArgs->{windspeed} );
        readingsBulkUpdate( $hash, "wind_speed_bft", $webArgs->{windspeedbft} );
    }

    # wind_speed_kn in kn (convert from km/h)
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v = UConv::kph2kn( $webArgs->{windspeed} );
        $webArgs->{windspeedkn} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "wind_speed_kn", $webArgs->{windspeedkn} );
    }

    # wind_speed_fts in ft/s (convert from mph)
    if ( defined( $webArgs->{windspeedmph} ) ) {
        my $v = UConv::mph2fts( $webArgs->{windspeedmph} );
        $webArgs->{windspeedfts} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "wind_speed_fts", $webArgs->{windspeedfts} );
    }

    # wind_gust_bft in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windgust} ) ) {
        $webArgs->{windgustbft} =
          UConv::kph2bft( $webArgs->{windgust} );
        readingsBulkUpdate( $hash, "wind_gust_bft", $webArgs->{windgustbft} );
    }

    # wind_gust_kn in m/s (convert from km/h)
    if ( defined( $webArgs->{windgust} ) ) {
        my $v = UConv::kph2kn( $webArgs->{windgust} );
        $webArgs->{windgustkn} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "wind_gust_kn", $webArgs->{windgustkn} );
    }

    # wind_gust_fts ft/s (convert from mph)
    if ( defined( $webArgs->{windgustmph} ) ) {
        my $v = UConv::mph2fts( $webArgs->{windgustmph} );
        $webArgs->{windgustfts} = ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "wind_gust_fts", $webArgs->{windgustfts} );
    }

    # averages/wind_direction_avg10m
    # averages/wind_direction_avg2m
    if ( defined( $webArgs->{winddir} ) ) {
        my $v =
          round( HP1000_GetAvg( $hash, "winddir", 600, $webArgs->{winddir} ),
            0 );

        if ( $hash->{INTERVAL} > 0 && $uptime >= 600 ) {
            $webArgs->{windgustdir_10m} = $v;
            readingsBulkUpdateIfChanged( $hash,
                "wind_gust_direction_avg10m", $webArgs->{windgustdir_10m} );
        }

        if ( $hash->{INTERVAL} > 0 && $uptime >= 120 ) {
            my $v2 = round( HP1000_GetAvg( $hash, "winddir", 120 ), 0 );
            $webArgs->{winddir_avg2m} = $v2;
            readingsBulkUpdateIfChanged( $hash, "wind_direction_avg2m",
                $webArgs->{winddir_avg2m} );
        }
    }

    # averages/wind_compasspoint_avg10m
    if ( defined( $webArgs->{windgustdir_10m} ) ) {
        $webArgs->{windcomp_avg10m} =
          UConv::direction2compasspoint( $webArgs->{windgustdir_10m} );
        readingsBulkUpdateIfChanged( $hash, "wind_compasspoint_avg10m",
            $webArgs->{windcomp_avg10m} );
    }

    # averages/wind_compasspoint_avg2m
    if ( defined( $webArgs->{winddir_avg2m} ) ) {
        $webArgs->{windcomp_avg2m} =
          UConv::direction2compasspoint( $webArgs->{winddir_avg2m} );
        readingsBulkUpdateIfChanged( $hash, "wind_compasspoint_avg2m",
            $webArgs->{windcomp_avg2m} );
    }

    # averages/wind_speed_avg2m in km/h
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v = HP1000_GetAvg( $hash, "windspeed", 120, $webArgs->{windspeed} );

        if ( $hash->{INTERVAL} > 0 && $uptime >= 120 ) {
            $webArgs->{windspeed_avg2m} = $v;
            readingsBulkUpdateIfChanged( $hash, "wind_speed_avg2m",
                $webArgs->{windspeed_avg2m} );
        }
    }

    # averages/wind_speed_mph_avg2m in mph
    if ( defined( $webArgs->{windspeedmph} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspeedmph", 120, $webArgs->{windspeedmph} );

        if ( $hash->{INTERVAL} > 0 && $uptime >= 120 ) {
            $webArgs->{windspdmph_avg2m} = $v;
            readingsBulkUpdateIfChanged( $hash, "wind_speed_mph_avg2m",
                $webArgs->{windspdmph_avg2m} );
        }
    }

    # averages/wind_speed_bft_avg2m in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        $webArgs->{windspdbft_avg2m} =
          UConv::kph2bft( $webArgs->{windspeed_avg2m} );
        readingsBulkUpdateIfChanged( $hash, "wind_speed_bft_avg2m",
            $webArgs->{windspdbft_avg2m} );
    }

    # averages/wind_speed_kn_avg2m in Kn (convert from km/h)
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        $webArgs->{windspdkn_avg2m} =
          UConv::kph2kn( $webArgs->{windspeed_avg2m} );
        readingsBulkUpdateIfChanged( $hash, "wind_speed_kn_avg2m",
            $webArgs->{windspdkn_avg2m} );
    }

    # averages/wind_speed_mps_avg2m in m/s
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        my $v = UConv::kph2mps( $webArgs->{windspeed_avg2m} );
        $webArgs->{windspdmps_avg2m} =
          ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdateIfChanged( $hash, "wind_speed_mps_avg2m",
            $webArgs->{windspdmps_avg2m} );
    }

    # maximum/wind_gust_max10m
    if ( defined( $webArgs->{windgust} ) ) {
        my $v = HP1000_GetMax( $hash, "windgust", 600, $webArgs->{windgust} );

        if ( $hash->{INTERVAL} > 0 && $uptime >= 600 ) {
            $webArgs->{windgust_10m} = $v;
            readingsBulkUpdateIfChanged( $hash, "wind_gust_max10m",
                $webArgs->{windgust_10m} );

            my ( $val, $rgb, $cond, $warn ) =
              UConv::kph2bft( $webArgs->{windgust_10m} );
            readingsBulkUpdateIfChanged( $hash, "windCondition",     $cond );
            readingsBulkUpdateIfChanged( $hash, "windCondition_rgb", $rgb );
            readingsBulkUpdateIfChanged( $hash, "windWarning",       $warn );
        }
    }

    # maximum/wind_gust_mph_max10m
    if ( defined( $webArgs->{windgustmph} ) ) {
        my $v =
          HP1000_GetMax( $hash, "windgustmph", 600, $webArgs->{windgustmph} );

        if ( $hash->{INTERVAL} > 0 && $uptime >= 600 ) {
            $webArgs->{windgustmph_10m} = $v;
            readingsBulkUpdateIfChanged( $hash, "wind_gust_mph_max10m",
                $webArgs->{windgustmph_10m} );
        }
    }

    # from WU API - can we somehow calculate these as well?
    # weather - [text] -- metar style (+RA)
    # clouds - [text] -- SKC, FEW, SCT, BKN, OVC
    # soiltempf - [F soil temperature]
    # soilmoisture - [%]
    # leafwetness  - [%]
    # visibility - [nm visibility]
    # condition_forecast (based on pressure trend)
    # dayNight
    # soilTemperature
    # brightness in % ??

    # state
    my $stateReadings       = AttrVal( $name, "stateReadings",       "" );
    my $stateReadingsLang   = AttrVal( $name, "stateReadingsLang",   "en" );
    my $stateReadingsFormat = AttrVal( $name, "stateReadingsFormat", "0" );

    # $result =
    #   makeSTATE( $name, $stateReadings,
    #     $stateReadingsLang, $stateReadingsFormat );

    $result = makeSTATE( $name, $stateReadings, $stateReadingsFormat );

    readingsBulkUpdate( $hash, "state", $result );
    readingsEndUpdate( $hash, 1 );

    HP1000_PushWU( $hash, $webArgs )
      if AttrVal( $name, "wu_push", 0 ) eq "1";

    HP1000_PushSrv( $hash, $webArgs )
      if AttrVal( $name, "extSrvPush_Url", undef );

    return ( "text/plain; charset=utf-8", "success" );
}

sub HP1000_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 2, "Registering HP1000 $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

sub HP1000_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2, "Unregistering HP1000 $name for URL $url...";
    delete $data{FWEXT}{$url};
}

sub HP1000_SetAliveState($;$) {
    my ( $hash, $alive ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "HP1000 $name: called function HP1000_SetAliveState()";
    RemoveInternalTimer($hash);

    my $activity = "dead";
    $activity = "alive" if ($alive);

    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "Activity", $activity );
    readingsEndUpdate( $hash, 1 );

    InternalTimer( gettimeofday() + 120, "HP1000_SetAliveState", $hash, 0 );

    return;
}

sub HP1000_PushSrv($$) {
    my ( $hash, $webArgs ) = @_;
    my $name            = $hash->{NAME};
    my $timeout         = AttrVal( $name, "timeout", 7 );
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $srv_url         = AttrVal( $name, "extSrvPush_Url", "" );
    my $cmd             = "";

    Log3 $name, 5, "HP1000 $name: called function HP1000_PushSrv()";

    $srv_url =~ s/\$SERVER_TYPE/$hash->{SERVER_TYPE}/g
      if ( $hash->{SERVER_TYPE} );

    if ( $srv_url !~
m/(https?):\/\/([\w\.]+):?(\d+)?([a-zA-Z0-9\~\!\@\#\$\%\^\&\*\(\)_\-\=\+\\\/\?\.\:\;\'\,]*)?/
      )
    {
        return;
    }
    elsif ( $4 !~ /\?/ ) {
        $cmd = "?";
    }
    else {
        $cmd = "&";
    }

    $webArgs->{PASSWORD} = "";

    while ( my ( $key, $value ) = each %{$webArgs} ) {
        if ( $key eq "softwaretype" || $key eq "dateutc" ) {
            $value = urlEncode($value);
        }
        $cmd .= "$key=" . $value . "&";
    }

    Log3 $name, 4,
      "HP1000 $name: pushing data to external Server: $srv_url$cmd";

    HttpUtils_NonblockingGet(
        {
            url         => $srv_url . $cmd,
            timeout     => $timeout,
            noshutdown  => $http_noshutdown,
            data        => undef,
            hash        => $hash,
            callback    => \&HP1000_ReturnSrv,
            httpversion => "1.1",
            loglevel    => AttrVal( $name, "httpLoglevel", 5 ),
            header      => {
                Agent        => 'FHEM-HP1000/1.0.0',
                'User-Agent' => 'FHEM-HP1000/1.0.0',
            },
            sslargs => {
                SSL_verify_mode => 'SSL_VERIFY_NONE',
            },
        }
    );

    return;
}

sub HP1000_PushWU($$) {

    #
    # See: http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol
    #

    my ( $hash, $webArgs ) = @_;
    my $name            = $hash->{NAME};
    my $timeout         = AttrVal( $name, "timeout", 7 );
    my $http_noshutdown = AttrVal( $name, "http-noshutdown", "1" );
    my $wu_user         = AttrVal( $name, "wu_id", "" );
    my $wu_pass         = AttrVal( $name, "wu_password", "" );
    my $wu_realtime     = AttrVal( $name, "wu_realtime", undef );
    my $wu_indoorValues = AttrVal( $name, "wu_indoorValues", 1 );
    my $wu_dataValues   = AttrVal( $name, "wu_dataValues", undef );
    my $wu_pushValues   = AttrVal( $name, "wu_pushValues", undef );
    my @whitelist =
      ( 'action', 'dateutc', 'ID', 'PASSWORD', 'rtfreq', 'softwaretype' );

    Log3 $name, 5, "HP1000 $name: called function HP1000_PushWU()";

    if ( $wu_user eq "" && $wu_pass eq "" ) {
        Log3 $name, 4,
          "HP1000 $name: "
          . "missing attributes for Weather Underground transfer: wu_user and wu_password";

        my $return = "error: missing attributes wu_user and wu_password";

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "wu_state", $return );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    if ( defined($wu_realtime) && $wu_realtime eq "0" ) {
        Log3 $name, 5, "HP1000 $name: Explicitly turning off realtime";
        delete $webArgs->{realtime};
        delete $webArgs->{rtfreq};
    }
    elsif ($wu_realtime) {
        Log3 $name, 5, "HP1000 $name: Explicitly turning on realtime";
        $webArgs->{realtime} = 1;
    }

    if ( $wu_dataValues || $wu_pushValues ) {
        my %HP1000_pwsMapping_rev = %{ { reverse %HP1000_pwsMapping } };

        if ($wu_dataValues) {
            my %dummy;
            $wu_dataValues =~ s/\$name/$name/g;
            my ( $err, @a ) = ReplaceSetMagic( \%dummy, 0, ($wu_dataValues) );
            if ($err) {
                Log3 $name, 3,
                  "HP1000 $name: error parsing wu_dataValues: $err";
            }
            else {
                my ( undef, $h ) = parseParams( \@a );
                foreach ( keys %$h ) {
                    next unless $_ ne "";
                    my $n = $_;
                    if ( $HP1000_pwsMapping_rev{$_} ) {
                        $n = $HP1000_pwsMapping_rev{$_};
                        Log3 $name, 4,
                          "HP1000 $name: Remapping reading name from $_ to $n";
                    }

                    Log3 $name, 4,
                      "HP1000 $name: Adding new value for WU: $n=$h->{$_}"
                      unless ( defined( $webArgs->{$n} ) );
                    Log3 $name, 4,
"HP1000 $name: Replacing existing value for WU: $n=$h->{$_}"
                      if ( defined( $webArgs->{$n} ) );

                    $webArgs->{$n} = $h->{$_};
                }
            }
        }

        if ($wu_pushValues) {
            foreach ( split( /,/, $wu_pushValues ) ) {
                if ( $HP1000_pwsMapping_rev{$_} ) {
                    my $v = $HP1000_pwsMapping_rev{$_};
                    $v = "humidity"       if ( $v eq "outhumi" );
                    $v = "indoorhumidity" if ( $v eq "inhumi" );
                    push @whitelist, $v;
                }
                else {
                    push @whitelist, $_;
                }
            }
        }
    }

    $webArgs->{rtfreq} = 5
      if ( defined( $webArgs->{realtime} )
        && !defined( $webArgs->{rtfreq} ) );

    my $wu_url = (
        defined( $webArgs->{realtime} )
          && $webArgs->{realtime} eq "1"
        ? "https://rtupdate.wunderground.com/weatherstation/updateweatherstation.php?"
        : "https://weatherstation.wunderground.com/weatherstation/updateweatherstation.php?"
    );

    $webArgs->{ID}       = $wu_user;
    $webArgs->{PASSWORD} = $wu_pass;

    my $cmd;

    while ( my ( $key, $value ) = each %{$webArgs} ) {
        $value = urlEncode($value)
          if ( $key =~ /^(softwaretype|dateutc)$/i );

        if (   ( $wu_indoorValues || $key =~ m/^in/i )
            && ( !$wu_pushValues || grep ( $_ eq $key, @whitelist ) ) )
        {
            Log3 $name, 4, "HP1000 $name: pushing data to WU: $key=$value";
            $cmd .= "$key=" . $value . "&";
        }
    }

    HttpUtils_NonblockingGet(
        {
            url         => $wu_url . $cmd,
            timeout     => $timeout,
            noshutdown  => $http_noshutdown,
            data        => undef,
            hash        => $hash,
            callback    => \&HP1000_ReturnWU,
            httpversion => "1.1",
            loglevel    => AttrVal( $name, "httpLoglevel", 5 ),
            header      => {
                Agent        => 'FHEM-HP1000/1.0.0',
                'User-Agent' => 'FHEM-HP1000/1.0.0',
            },
        }
    );

    return;
}

sub HP1000_ReturnSrv($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    # device not reachable
    if ($err) {
        my $return = "error: connection timeout";
        Log3 $name, 4, "HP1000 $name: EXTSRV HTTP " . $return;

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "extsrv_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    # data received
    elsif ($data) {
        my $logprio = 5;
        my $return  = "ok";

        if ( $param->{code} ne "200" ) {
            $logprio = 4;
            $return  = "error " . $param->{code} . ": $data";
        }
        Log3 $name, $logprio,
          "HP1000 $name: EXTSRV HTTP return: " . $param->{code} . " - $data";

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "extsrv_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    return;
}

sub HP1000_ReturnWU($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    # device not reachable
    if ($err) {
        my $return = "error: connection timeout";
        Log3 $name, 4, "HP1000 $name: WU HTTP " . $return;

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "wu_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    # data received
    elsif ($data) {
        my $logprio = 5;
        my $return  = "ok";

        if ( $data !~ m/^success.*/i ) {
            $logprio = 4;
            $return  = "error";
            $return .= " " . $param->{code} if ( $param->{code} ne "200" );
            $return .= ": $data";
        }
        Log3 $name, $logprio,
          "HP1000 $name: WU HTTP return: " . $param->{code} . " - $data";

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged( $hash, "wu_state", $return );
        readingsEndUpdate( $hash, 1 );
    }

    return;
}

sub HP1000_GetAvg($$;$$) {
    my ( $hash, $t, $s, $v ) = @_;
    return HP1000_HistoryDb( $hash, $t, $s, $v, 1 );
}

sub HP1000_GetMax($$;$$) {
    my ( $hash, $t, $s, $v ) = @_;
    return HP1000_HistoryDb( $hash, $t, $s, $v, 2 );
}

sub HP1000_HistoryDb($$;$$$) {
    my ( $hash, $t, $s, $v, $type ) = @_;
    my $name = $hash->{NAME};

    return $v if ( $type && $type == 1 && $hash->{INTERVAL} < 1 );
    return "0" if ( $hash->{INTERVAL} < 1 );

    my $historySize = $s ? round( $s / $hash->{INTERVAL}, 0 ) : undef;
    $historySize = "1" if ( defined($historySize) && $historySize < 1 );

    if ( defined($v) && looks_like_number($v) ) {
        my $v2 = unshift @{ $hash->{helper}{history}{$t} }, $v
          unless ( !$type && $v <= 0 );
        my $v3 = splice @{ $hash->{helper}{history}{$t} }, $historySize
          if ($historySize);

        Log3 $name, 5, "HP1000 $name: Added $v to history for $t:"
          . Dumper( @{ $hash->{helper}{history}{$t} } );
    }

    my $asize = scalar @{ $hash->{helper}{history}{$t} };
    return $v unless ($asize);

    $historySize = $asize if ( !$historySize || $asize < $historySize );
    $historySize--;

    my @a =
      $historySize
      ? @{ $hash->{helper}{history}{$t} }[ 0 .. $historySize ]
      : @{ $hash->{helper}{history}{$t} }[0];

    if ( $type == 1 ) {
        return round( sum(@a) / @a, 1 );
    }
    elsif ( $type == 2 ) {
        return maxNum( 0, @a );
    }

    return undef;
}

1;

=pod
=item device
=item summary support for Wifi-based weather stations using PWS protocol from Wunderground
=item summary_DE unterst&uuml;tzt WLAN-basierte Wetterstationen mit Wunderground PWS Protokoll
=begin html

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <ul>

    <div>
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div>
      <ul>
        <code>define &lt;WeatherStation&gt; HP1000 [&lt;ID&gt; &lt;PASSWORD&gt;]</code><br>
        <br>
          Provides webhook receiver for Wifi-based weather station which support <a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">PWS protocol</a> from Weather Underground (e.g. HP1000, WH2600, WH2601, WH2621, WH2900, WH2950 of <a href="http://www.foshk.com/Wifi_Weather_Station/">Fine Offset Electronics</a> - sometimes also known as <a href="http://www.ambientweather.com/peorhowest.html">Ambient Weather</a> WS-1001-WIFI or similar). In Germany, these devices are commonly distributed by <a href="http://www.froggit.de/">froggit</a> or by <a href="http://www.conrad.de/">Conrad</a> under it's brand name Renkforce.<br>
          There needs to be a dedicated FHEMWEB instance with attribute webname set to "weatherstation".<br>
          No other name will work as it's hardcoded in the weather station device itself!<br>
          If necessary, this module will create a matching FHEMWEB instance named WEBweatherstation during initial definition.<br>
          <br>
          As the URI has a fixed coding as well there can only be one single instance of this module FHEM installation.<br>
        <br>
        Example:<br>
        <div>
          <code># unprotected instance where ID and PASSWORD will be ignored<br>
          define WeatherStation HP1000<br>
          <br>
          # protected instance: Weather Station needs to be configured<br>
          # to send this ID and PASSWORD for data to be accepted<br>
          define WeatherStation HP1000 MyHouse SecretPassword</code>
        </div><br>
          IMPORTANT: In your hardware device, make sure you use a DNS name as most revisions cannot handle IP addresses correctly.<br>
          You might want to check to install a firmware update from <a href="http://www.foshk.com/support/">here</a>.
      </ul>
      </div><br>
    </div>
    <br>

    <a name="HP1000Attr" id="HP10000Attr"></a> <b>Attributes</b>
    <div>
    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <br>

      <a name="webhookFWinstances"></a><li><b>webhookFWinstances</b></li>
        Explicitly specify allowed FHEMWEB instaces for data input (defaults to weatherstation)

      <a name="wu_id"></a><li><b>wu_id</b></li>
        Weather Underground (Wunderground) station ID

      <a name="wu_password"></a><li><b>wu_password</b></li>
        Weather Underground (Wunderground) password

      <a name="wu_dataValues"></a><li><b>wu_dataValues</b></li>
        Add or replace values before pushing data to Weather Underground.<br>
        Format is key=value while value may be of <a href="#set">set magic format</a>

      <a name="wu_indoorValues"></a><li><b>wu_indoorValues</b></li>
        Include indoor values for Weather Underground (defaults to 1=yes)

      <a name="wu_push"></a><li><b>wu_push</b></li>
        Enable or disable to push data forward to Weather Underground (defaults to 0=no)

      <a name="wu_pushValues"></a><li><b>wu_pushValues</b></li>
        Restrict values to be transferred to Weather Underground,
        otherwise all values will be transferred.

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Send the data to the WU realtime server instead of using the standard server (defaults to 1=yes)
    </ul>
    </div>

    </ul>
=end html

=begin html_DE

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <ul>

    <div>
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div>
      <ul>
        <code>define &lt;WeatherStation&gt; HP1000 [&lt;ID&gt; &lt;PASSWORD&gt;]</code><br>
        <br>
          Stellt einen Webhook f&uuml;r WLAN-basierte Wetterstationen bereit, die das <a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">PWS</a> Protokoll von Weather Underground verwenden (z.B. HP1000, WH2600, WH2601, WH2621, WH2900, WH2950 Wetterstation von <a href="http://www.foshk.com/Wifi_Weather_Station/">Fine Offset Electronics</a> - manchmal auch bekannt als <a href="http://www.ambientweather.com/peorhowest.html">Ambient Weather</a> WS-1001-WIFI oder &auml;hnliches). In Deutschland werden die Ger&auml;te zumeist von <a href="http://www.froggit.de/">froggit</a> oder von <a href="http://www.conrad.de/">Conrad</a> unter dem Markennamen Renkforce vertrieben.<br>
          Es muss noch eine dedizierte FHEMWEB Instanz angelegt werden, wo das Attribut webname auf "weatherstation" gesetzt wurde.<br>
          Kein anderer Name funktioniert, da dieser fest in der Wetterstation hinterlegt ist!<br>
          Sofern notwendig, erstellt dieses Modul eine passende FHEMWEB Instanz namens WEBweatherstation w&auml;hrend der initialen Definition.<br>
          <br>
          Da die URI ebenfalls fest kodiert ist, kann mit einer einzelnen FHEM Installation maximal eine Instanz dieses Moduls gleichzeitig verwendet werden.<br>
        <br>
        Beispiel:<br>
        <div>
          <code># ungesch&uuml;tzte Instanz bei der ID und PASSWORD ignoriert werden<br>
          define WeatherStation HP1000<br>
          <br>
          # gesch&uuml;tzte Instanz: Die Wetterstation muss so konfiguriert sein, dass sie<br>
          # diese ID und PASSWORD sendet, damit Daten akzeptiert werden<br>
          define WeatherStation HP1000 MyHouse SecretPassword</code>
        </div><br>
          WICHTIG: Im Ger&auml;t selbst muss sichergestellt sein, dass ein DNS Name statt einer IP Adresse verwendet wird, da einige Revisionen damit nicht umgehen k&ouml;nnen.<br>
          Ggf. sollte man <a href="http://www.foshk.com/support/">hier</a> einmal nach einer neueren Firmware schauen.
      </ul>
      </div><br>
    </div>

    <a name="HP1000Attr" id="HP10000Attr"></a> <b>Attributes</b>
    <div>
    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <br>

      <a name="webhookFWinstances"></a><li><b>webhookFWinstances</b></li>
        Explizite Angabe der FHEMWEB Instanzen, &auml;ber die Dateneingaben erlaubt sind (Standard ist weatherstation)

      <a name="wu_id"></a><li><b>wu_id</b></li>
        Weather Underground (Wunderground) Stations ID

      <a name="wu_password"></a><li><b>wu_password</b></li>
        Weather Underground (Wunderground) Passwort

      <a name="wu_dataValues"></a><li><b>wu_dataValues</b></li>
        Ersetzt Werte oder f&uuml;gt neue Werte hinzu, bevor diese zu Weather Underground &uuml;bertragen werden.<br>
        Das Format entspricht key=value wobei value im <a href="#set">Format set magic sein</a> kann.

      <a name="wu_indoorValues"></a><li><b>wu_indoorValues</b></li>
        Gibt an, ob die Innenraumwerte mit zu Weather Underground &uuml;bertragen werden sollen (Standard ist 1=an)

      <a name="wu_push"></a><li><b>wu_push</b></li>
        Pushen der Daten zu Weather Underground aktivieren oder deaktivieren (Standard ist 0=aus)

      <a name="wu_pushValues"></a><li><b>wu_pushValues</b></li>
        Schr&auml;nkt die Werte ein, die an Weather Underground &uuml;bertragen werden.
        Andernfalls werden alle Werte &uuml;bertragen.

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Sendet die Daten an den WU Echtzeitserver statt an den Standard Server (Standard ist 1=an)
    </ul>
    </div>

    </ul>
=end html_DE

=cut

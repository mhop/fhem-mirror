# $Id$
##############################################################################
#
#     50_HP1000.pm
#     An FHEM Perl module to receive data from HP1000 weather stations.
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
##############################################################################

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use utf8;
use Encode qw(encode_utf8 decode_utf8);
use Unit;
use Time::Local;
use List::Util qw(sum);
use Scalar::Util qw(looks_like_number);
use Data::Dumper;

#########################
sub HP1000_addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = "/$link";
    Log3 $name, 2, "Registering HP1000 $name for URL $url...";
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;
}

#########################
sub HP1000_removeExtension($) {
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    Log3 $name, 2, "Unregistering HP1000 $name for URL $url...";
    delete $data{FWEXT}{$url};
}

###################################
sub HP1000_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "HP1000_Initialize: Entering";

    if ( !$modules{dewpoint}{LOADED}
        && -f "$attr{global}{modpath}/FHEM/98_dewpoint.pm" )
    {
        my $ret = CommandReload( undef, "98_dewpoint" );
        Log3 undef, 1, $ret if ($ret);
    }

    $hash->{GetFn}         = "HP1000_Get";
    $hash->{DefFn}         = "HP1000_Define";
    $hash->{UndefFn}       = "HP1000_Undefine";
    $hash->{DbLog_splitFn} = "Unit_DbLog_split";
    $hash->{parseParams}   = 1;

    $hash->{AttrList} =
"wu_push:1,0 wu_indoorValues:1,0 wu_id wu_password wu_realtime:1,0 wu_dataValues extSrvPush_Url stateReadingsLang:en,de,at,ch,nl,fr,pl stateReadings stateReadingsFormat:0,1 "
      . $readingFnAttributes;

    # Unit.pm support
    $hash->{readingsDesc} = {
        'Activity'            => { rtype => 'oknok', },
        'UV'                  => { rtype => 'uvi', },
        'UVR'                 => { rtype => 'uwpscm', },
        'UVcondition'         => { rtype => 'condition_uvi', },
        'UVcondition_rgb'     => { rtype => 'rgbhex', },
        'condition'           => { rtype => 'condition_weather', },
        'daylight'            => { rtype => 'yesno', },
        'dewpoint'            => { rtype => 'c', formula_symbol => 'Td', },
        'dewpoint_f'          => { rtype => 'f', formula_symbol => 'Td', },
        'extsrv_state'        => { rtype => 'oknok', },
        'humidity'            => { rtype => 'pct', formula_symbol => 'H', },
        'humidityAbs'         => { rtype => 'c', formula_symbol => 'Tabs', },
        'humidityAbs_f'       => { rtype => 'f', formula_symbol => 'Tabs', },
        'humidityCondition'   => { rtype => 'condition_hum', },
        'indoorDewpoint'      => { rtype => 'c', formula_symbol => 'Tdi', },
        'indoorDewpoint_f'    => { rtype => 'f', formula_symbol => 'Tdi', },
        'indoorHumidity'      => { rtype => 'pct', formula_symbol => 'Hi', },
        'indoorHumidityAbs'   => { rtype => 'c', formula_symbol => 'Tabsi', },
        'indoorHumidityAbs_f' => { rtype => 'f', formula_symbol => 'Tabsi', },
        'indoorHumidityCondition' => { rtype => 'condition_hum', },
        'indoorTemperature'       => { rtype => 'c', formula_symbol => 'Ti', },
        'indoorTemperature_f'     => { rtype => 'f', formula_symbol => 'Ti', },
        'israining'               => { rtype => 'yesno', },
        'luminosity'              => { rtype => 'lx', },
        'pressure'                => { rtype => 'hpamb', },
        'pressureAbs'             => { rtype => 'hpamb', },
        'pressureAbs_in'          => { rtype => 'inhg', },
        'pressureAbs_mm'          => { rtype => 'mmhg', },
        'pressure_in'             => { rtype => 'inhg', },
        'pressure_mm'             => { rtype => 'mmhg', },
        'rain'                    => { rtype => 'mm', },
        'rain_day'                => { rtype => 'mm', },
        'rain_day_in'             => { rtype => 'in', },
        'rain_in'                 => { rtype => 'in', },
        'rain_month'              => { rtype => 'mm', },
        'rain_month_in'           => { rtype => 'in', },
        'rain_week'               => { rtype => 'mm', },
        'rain_week_in'            => { rtype => 'in', },
        'rain_year'               => { rtype => 'mm', },
        'rain_year_in'            => { rtype => 'in', },
        'solarradiation'          => { rtype => 'wpsm', },
        'temperature'             => { rtype => 'c', },
        'temperature_f'           => { rtype => 'f', },
        'wind_compasspoint'       => { rtype => 'compasspoint', },
        'wind_compasspoint_avg2m' => { rtype => 'compasspoint', },
        'wind_chill'              => { rtype => 'c', formula_symbol => 'Wc', },
        'wind_chill_f'            => { rtype => 'f', formula_symbol => 'Wc', },
        'wind_direction' =>
          { rtype => 'compasspoint', formula_symbol => 'Wdir', },
        'wind_direction_avg2m' =>
          { rtype => 'compasspoint', formula_symbol => 'Wdir', },
        'wind_gust'            => { rtype => 'kmph', formula_symbol => 'Wg', },
        'wind_gust_bft'        => { rtype => 'bft',  formula_symbol => 'Wg', },
        'wind_gust_fts'        => { rtype => 'fts',  formula_symbol => 'Wg', },
        'wind_gust_kn'         => { rtype => 'kn',   formula_symbol => 'Wg', },
        'wind_gust_mph'        => { rtype => 'mph',  formula_symbol => 'Wg', },
        'wind_gust_mph_sum10m' => { rtype => 'mph',  formula_symbol => 'Wg', },
        'wind_gust_mps'        => { rtype => 'mps',  formula_symbol => 'Wg', },
        'wind_gust_sum10m'     => { rtype => 'kmph', formula_symbol => 'Wg', },
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

###################################
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
        return
"Attribute wu_id does not contain a PWS ID to create a Wunderground device"
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

###################################
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

###################################
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

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

#####################################
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

###################################
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
    return ( "text/plain; charset=utf-8", "booting up" )
      unless ($init_done);

    # incorrect FHEMWEB instance used
    if ( AttrVal( $FW_wname, "webname", "fhem" ) ne "weatherstation" ) {
        return ( "text/plain; charset=utf-8",
            "incorrect FHEMWEB instance to receive data" );
    }

    # data received
    elsif ( $request =~ /^\/updateweatherstation\.(\w{3})\?(.+=.+)/ ) {
        $servertype = lc($1);
        $URI        = $2;

        # get device name
        $name = $data{FWEXT}{"/updateweatherstation"}{deviceName}
          if ( defined( $data{FWEXT}{"/updateweatherstation"} ) );

        # return error if no such device
        return ( "text/plain; charset=utf-8",
            "No HP1000 device for webhook /updateweatherstation" )
          unless ($name);

        # extract values from URI
        foreach my $pv ( split( "&", $URI ) ) {
            next if ( $pv eq "" );
            $pv =~ s/\+/ /g;
            $pv =~ s/%([\dA-F][\dA-F])/chr(hex($1))/ige;
            my ( $p, $v ) = split( "=", $pv, 2 );

            $webArgs->{$p} = $v ne "" ? Encode::encode_utf8($v) : $v;
        }

        if (   !defined( $webArgs->{softwaretype} )
            || !defined( $webArgs->{dateutc} )
            || !defined( $webArgs->{ID} )
            || !defined( $webArgs->{PASSWORD} )
            || !defined( $webArgs->{action} ) )
        {
            Log3 $name, 5,
              "HP1000: received insufficient data:\n" . Dumper($webArgs);

            return ( "text/plain; charset=utf-8", "Insufficient data" );
        }
    }

    # no data received
    else {
        return ( "text/plain; charset=utf-8", "Missing data" );
    }

    $hash = $defs{$name};

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

    foreach ( devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') ) {
        if ( AttrVal( $_, "webname", "fhem" ) eq "weatherstation" ) {
            $hash->{FW}      = $_;
            $hash->{FW_PORT} = $defs{$_}{PORT};
            last;
        }
    }

    if (
           defined( $hash->{ID} )
        && defined( $hash->{PASSWORD} )
        && (   $hash->{ID} ne $webArgs->{ID}
            || $hash->{PASSWORD} ne $webArgs->{PASSWORD} )
      )
    {
        Log3 $name, 4, "HP1000: received data containing wrong credentials:\n"
          . Dumper($webArgs);
        return ( "text/plain; charset=utf-8", "Wrong credentials" );
    }

    Log3 $name, 5, "HP1000: received data:\n" . Dumper($webArgs);

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

    # calculate readings for Metric standard from Angloamerican standard
    #

    # humidity (special case here!)
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

    # dewpoint in Celsius (convert from dewptf)
    if (   defined( $webArgs->{dewptf} )
        && $webArgs->{dewptf} ne ""
        && !defined( $webArgs->{dewpoint} ) )
    {
        $webArgs->{dewpoint} =
          UConv::f2c( $webArgs->{dewptf} );
    }

    # relbaro in hPa (convert from baromin)
    if (   defined( $webArgs->{baromin} )
        && $webArgs->{baromin} ne ""
        && !defined( $webArgs->{relbaro} ) )
    {
        $webArgs->{relbaro} = UConv::inhg2hpa( $webArgs->{baromin} );
    }

    # absbaro in hPa (convert from absbaromin)
    if (   defined( $webArgs->{absbaromin} )
        && $webArgs->{absbaromin} ne ""
        && !defined( $webArgs->{absbaro} ) )
    {
        $webArgs->{absbaro} =
          UConv::inhg2hpa( $webArgs->{absbaromin} );
    }

    # rainrate in mm/h (convert from rainin)
    if (   defined( $webArgs->{rainin} )
        && $webArgs->{rainin} ne ""
        && !defined( $webArgs->{rainrate} ) )
    {
        $webArgs->{rainrate} = UConv::in2mm( $webArgs->{rainin} );
    }

    # dailyrain in mm (convert from dailyrainin)
    if (   defined( $webArgs->{dailyrainin} )
        && $webArgs->{dailyrainin} ne ""
        && !defined( $webArgs->{dailyrain} ) )
    {
        $webArgs->{dailyrain} =
          UConv::in2mm( $webArgs->{dailyrainin} );
    }

    # weeklyrain in mm (convert from weeklyrainin)
    if (   defined( $webArgs->{weeklyrainin} )
        && $webArgs->{weeklyrainin} ne ""
        && !defined( $webArgs->{weeklyrain} ) )
    {
        $webArgs->{weeklyrain} =
          UConv::in2mm( $webArgs->{weeklyrainin} );
    }

    # monthlyrain in mm (convert from monthlyrainin)
    if (   defined( $webArgs->{monthlyrainin} )
        && $webArgs->{monthlyrainin} ne ""
        && !defined( $webArgs->{monthlyrain} ) )
    {
        $webArgs->{monthlyrain} =
          UConv::in2mm( $webArgs->{monthlyrainin} );
    }

    # yearlyrain in mm (convert from yearlyrainin)
    if (   defined( $webArgs->{yearlyrainin} )
        && $webArgs->{yearlyrainin} ne ""
        && !defined( $webArgs->{yearlyrain} ) )
    {
        $webArgs->{yearlyrain} =
          UConv::in2mm( $webArgs->{yearlyrainin} );
    }

    # outtemp in Celsius (convert from tempf)
    if (   defined( $webArgs->{tempf} )
        && $webArgs->{tempf} ne ""
        && !defined( $webArgs->{outtemp} ) )
    {
        $webArgs->{outtemp} =
          UConv::f2c( $webArgs->{tempf} );
    }

    # intemp in Celsius (convert from indoortempf)
    if (   defined( $webArgs->{indoortempf} )
        && $webArgs->{indoortempf} ne ""
        && !defined( $webArgs->{intemp} ) )
    {
        $webArgs->{intemp} =
          UConv::f2c( $webArgs->{indoortempf} );
    }

    # windchill in Celsius (convert from windchillf)
    if (   defined( $webArgs->{windchillf} )
        && $webArgs->{windchillf} ne ""
        && !defined( $webArgs->{windchill} ) )
    {
        $webArgs->{windchill} =
          UConv::f2c( $webArgs->{windchillf} );
    }

    # windgust in km/h (convert from windgustmph)
    if (   defined( $webArgs->{windgustmph} )
        && $webArgs->{windgustmph} ne ""
        && !defined( $webArgs->{windgust} ) )
    {
        $webArgs->{windgust} =
          UConv::mph2kph( $webArgs->{windgustmph} );
    }

    # windspeed in km/h (convert from windspeedmph)
    if (   defined( $webArgs->{windspeedmph} )
        && $webArgs->{windspeedmph} ne ""
        && !defined( $webArgs->{windspeed} ) )
    {
        $webArgs->{windspeed} =
          UConv::mph2kph( $webArgs->{windspeedmph} );
    }

    # windspeed in km/h (convert from windspdmph)
    if (   defined( $webArgs->{windspdmph} )
        && $webArgs->{windspdmph} ne ""
        && !defined( $webArgs->{windspeed} ) )
    {
        $webArgs->{windspeed} =
          UConv::mph2kph( $webArgs->{windspdmph} );
    }

    # calculate readings for Angloamerican standard from Metric standard
    #

    # humidity (special case here!)
    $webArgs->{indoorhumidity} = $webArgs->{inhumi}
      if ( defined( $webArgs->{inhumi} )
        && !defined( $webArgs->{indoorhumidity} ) );

    # dewptf in Fahrenheit (convert from dewpoint)
    if (   defined( $webArgs->{dewpoint} )
        && $webArgs->{dewpoint} ne ""
        && !defined( $webArgs->{dewptf} ) )
    {
        $webArgs->{dewptf} =
          UConv::c2f( $webArgs->{dewpoint} );
    }

    # baromin in inch (convert from relbaro)
    if (   defined( $webArgs->{relbaro} )
        && $webArgs->{relbaro} ne ""
        && !defined( $webArgs->{baromin} ) )
    {
        $webArgs->{baromin} = UConv::hpa2inhg( $webArgs->{relbaro} );
    }

    # absbaromin in inch (convert from absbaro)
    if (   defined( $webArgs->{absbaro} )
        && $webArgs->{absbaro} ne ""
        && !defined( $webArgs->{absbaromin} ) )
    {
        $webArgs->{absbaromin} =
          UConv::hpa2inhg( $webArgs->{absbaro} );
    }

    # rainin in in/h (convert from rainrate)
    if (   defined( $webArgs->{rainrate} )
        && $webArgs->{rainrate} ne ""
        && !defined( $webArgs->{rainin} ) )
    {
        $webArgs->{rainin} = UConv::mm2in( $webArgs->{rainrate} );
    }

    # dailyrainin in inch (convert from dailyrain)
    if (   defined( $webArgs->{dailyrain} )
        && $webArgs->{dailyrain} ne ""
        && !defined( $webArgs->{dailyrainin} ) )
    {
        $webArgs->{dailyrainin} =
          UConv::mm2in( $webArgs->{dailyrain} );
    }

    # weeklyrainin in inch (convert from weeklyrain)
    if (   defined( $webArgs->{weeklyrain} )
        && $webArgs->{weeklyrain} ne ""
        && !defined( $webArgs->{weeklyrainin} ) )
    {
        $webArgs->{weeklyrainin} =
          UConv::mm2in( $webArgs->{weeklyrain} );
    }

    # monthlyrainin in inch (convert from monthlyrain)
    if (   defined( $webArgs->{monthlyrain} )
        && $webArgs->{monthlyrain} ne ""
        && !defined( $webArgs->{monthlyrainin} ) )
    {
        $webArgs->{monthlyrainin} =
          UConv::mm2in( $webArgs->{monthlyrain} );
    }

    # yearlyrainin in inch (convert from yearlyrain)
    if (   defined( $webArgs->{yearlyrain} )
        && $webArgs->{yearlyrain} ne ""
        && !defined( $webArgs->{yearlyrainin} ) )
    {
        $webArgs->{yearlyrainin} =
          UConv::mm2in( $webArgs->{yearlyrain} );
    }

    #  tempf in Fahrenheit (convert from outtemp)
    if (   defined( $webArgs->{outtemp} )
        && $webArgs->{outtemp} ne ""
        && !defined( $webArgs->{tempf} ) )
    {
        $webArgs->{tempf} =
          UConv::c2f( $webArgs->{outtemp} );
    }

    # indoortempf in Fahrenheit (convert from intemp)
    if (   defined( $webArgs->{intemp} )
        && $webArgs->{intemp} ne ""
        && !defined( $webArgs->{indoortempf} ) )
    {
        $webArgs->{indoortempf} =
          UConv::c2f( $webArgs->{intemp} );
    }

    # windchillf in Fahrenheit (convert from windchill)
    if (   defined( $webArgs->{windchill} )
        && $webArgs->{windchill} ne ""
        && !defined( $webArgs->{windchillf} ) )
    {
        $webArgs->{windchillf} =
          UConv::c2f( $webArgs->{windchill} );
    }

    # windgustmps in m/s (convert from windgust)
    if (   defined( $webArgs->{windgust} )
        && $webArgs->{windgust} ne ""
        && !defined( $webArgs->{windgustmps} ) )
    {
        $webArgs->{windgustmps} =
          UConv::kph2mps( $webArgs->{windgust} );
    }

    # windgust in km/h (convert from windgustmps,
    # not exactly from angloamerican...)
    if (   defined( $webArgs->{windgustmps} )
        && $webArgs->{windgustmps} ne ""
        && !defined( $webArgs->{windgust} ) )
    {
        $webArgs->{windgust} =
          UConv::mps2kph( $webArgs->{windgustmps} );
    }

    # windgustmph in mph (convert from windgust)
    if (   defined( $webArgs->{windgust} )
        && $webArgs->{windgust} ne ""
        && !defined( $webArgs->{windgustmph} ) )
    {
        $webArgs->{windgustmph} =
          UConv::kph2mph( $webArgs->{windgust} );
    }

    # windspeedmps in m/s (convert from windspeed,
    # not exactly from angloamerican...)
    if (   defined( $webArgs->{windspeed} )
        && $webArgs->{windspeed} ne ""
        && !defined( $webArgs->{windspeedmps} ) )
    {
        $webArgs->{windspeedmps} =
          UConv::kph2mps( $webArgs->{windspeed} );
    }

    # windspeed in km/h (convert from windspeedmps)
    if (   defined( $webArgs->{windspeedmps} )
        && $webArgs->{windspeedmps} ne ""
        && !defined( $webArgs->{windspeed} ) )
    {
        $webArgs->{windspeed} =
          UConv::mps2kph( $webArgs->{windspeedmps} );
    }

    # windspdmph in mph (convert from windspeed)
    if (   defined( $webArgs->{windspeed} )
        && $webArgs->{windspeed} ne ""
        && !defined( $webArgs->{windspeedmph} ) )
    {
        $webArgs->{windspeedmph} =
          UConv::kph2mph( $webArgs->{windspeed} );
    }

    # windspdmph in mph (convert from windspeed)
    if (   defined( $webArgs->{windspeed} )
        && $webArgs->{windspeed} ne ""
        && !defined( $webArgs->{windspdmph} ) )
    {
        $webArgs->{windspdmph} =
          UConv::kph2mph( $webArgs->{windspeed} );
    }

    # write general readings
    #
    readingsBeginUpdate($hash);

    while ( ( my $p, my $v ) = each %$webArgs ) {

        # delete empty values
        if ( $v eq "" ) {
            delete $webArgs->{$p};
            next;
        }

        # ignore those values
        next
          if ( $p eq "dateutc"
            || $p eq "action"
            || $p eq "softwaretype"
            || $p eq "realtime"
            || $p eq "rtfreq"
            || $p eq "humidity"
            || $p eq "indoorhumidity"
            || $p eq "ID"
            || $p eq "PASSWORD" );

        $p = "_" . $p;

        # name translation for general readings
        $p = "humidity"       if ( $p eq "_outhumi" );
        $p = "indoorHumidity" if ( $p eq "_inhumi" );
        $p = "luminosity"     if ( $p eq "_light" );
        $p = "solarradiation" if ( $p eq "_solarradiation" );
        $p = "wind_direction" if ( $p eq "_winddir" );
        $p = "UV" if ( $p eq "_UV" && $hash->{SERVER_TYPE} eq "php" );
        $p = "UVR" if ( $p eq "_UV" && $hash->{SERVER_TYPE} ne "php" );

        # name translation for Metric standard
        $p = "dewpoint"          if ( $p eq "_dewpoint" );
        $p = "pressure"          if ( $p eq "_relbaro" );
        $p = "pressureAbs"       if ( $p eq "_absbaro" );
        $p = "rain"              if ( $p eq "_rainrate" );
        $p = "rain_day"          if ( $p eq "_dailyrain" );
        $p = "rain_week"         if ( $p eq "_weeklyrain" );
        $p = "rain_month"        if ( $p eq "_monthlyrain" );
        $p = "rain_year"         if ( $p eq "_yearlyrain" );
        $p = "temperature"       if ( $p eq "_outtemp" );
        $p = "indoorTemperature" if ( $p eq "_intemp" );
        $p = "wind_chill"        if ( $p eq "_windchill" );
        $p = "wind_gust"         if ( $p eq "_windgust" );
        $p = "wind_gust_mps"     if ( $p eq "_windgustmps" );
        $p = "wind_speed"        if ( $p eq "_windspeed" );
        $p = "wind_speed_mps"    if ( $p eq "_windspeedmps" );

        # name translation for Angloamerican standard
        $p = "dewpoint_f"          if ( $p eq "_dewptf" );
        $p = "pressure_in"         if ( $p eq "_baromin" );
        $p = "pressureAbs_in"      if ( $p eq "_absbaromin" );
        $p = "rain_in"             if ( $p eq "_rainin" );
        $p = "rain_day_in"         if ( $p eq "_dailyrainin" );
        $p = "rain_week_in"        if ( $p eq "_weeklyrainin" );
        $p = "rain_month_in"       if ( $p eq "_monthlyrainin" );
        $p = "rain_year_in"        if ( $p eq "_yearlyrainin" );
        $p = "temperature_f"       if ( $p eq "_tempf" );
        $p = "indoorTemperature_f" if ( $p eq "_indoortempf" );
        $p = "wind_chill_f"        if ( $p eq "_windchillf" );
        $p = "wind_gust_mph"       if ( $p eq "_windgustmph" );
        $p = "wind_speed_mph"      if ( $p eq "_windspeedmph" );
        $p = "wind_speed_mph"      if ( $p eq "_windspdmph" );

        readingsBulkUpdate( $hash, $p, $v );
    }

    # calculate additional readings
    #

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
          UConv::lux2wpsm( $webArgs->{light} );
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

    # humidityCondition
    if ( defined( $webArgs->{outhumi} ) ) {
        readingsBulkUpdateIfChanged( $hash, "humidityCondition",
            UConv::humidity2condition( $webArgs->{outhumi} ) );
    }

    # indoorHumidityCondition
    if ( defined( $webArgs->{inhumi} ) ) {
        readingsBulkUpdateIfChanged( $hash, "indoorHumidityCondition",
            UConv::humidity2condition( $webArgs->{inhumi} ) );
    }

    if ( defined( $webArgs->{UV} ) ) {

        # php reports UV as index
        # UVR (convert from UVI)
        if ( $hash->{SERVER_TYPE} eq 'php' ) {
            $webArgs->{UVI} = $webArgs->{UV};
            $webArgs->{UVR} = UConv::uvi2uwpscm( $webArgs->{UVI} );
            readingsBulkUpdate( $hash, "UVR", $webArgs->{UVR} );
        }

        # jsp reports UV as radiation
        # UV (convert from uW/cm2)
        else {
            $webArgs->{UVR} = $webArgs->{UV};
            $webArgs->{UVI} = UConv::uwpscm2uvi( $webArgs->{UVR} );
            readingsBulkUpdate( $hash, "UV", $webArgs->{UVI} );
        }
    }

    # UVcondition
    if ( defined( $webArgs->{UVI} ) ) {
        my ( $v, $rgb ) = UConv::uvi2condition( $webArgs->{UVI} );
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

        $webArgs->{indoordewpointf} =
          round( dewpoint_dewpoint( $webArgs->{indoortempf}, $h ), 1 );
        readingsBulkUpdate( $hash, "indoorDewpoint_f",
            $webArgs->{indoordewpointf} );
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
        $webArgs->{windcompasspoint} =
          UConv::direction2compasspoint( $webArgs->{winddir} );
        readingsBulkUpdate( $hash, "wind_compasspoint",
            $webArgs->{windcompasspoint} );
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

    # averages/wind_direction_avg2m
    if ( defined( $webArgs->{winddir} ) ) {
        my $v = sprintf( '%0.0f',
            HP1000_GetAvg( $hash, "winddir", 2 * 60, $webArgs->{winddir} ) );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "wind_direction_avg2m", $v );
            $webArgs->{winddir_avg2m} = $v;
        }
    }

    # averages/wind_compasspoint_avg2m
    if ( defined( $webArgs->{winddir_avg2m} ) ) {
        $webArgs->{windcompasspoint_avg2m} =
          UConv::direction2compasspoint( $webArgs->{winddir_avg2m} );
        readingsBulkUpdate( $hash, "wind_compasspoint_avg2m",
            $webArgs->{windcompasspoint_avg2m} );
    }

    # averages/wind_speed_avg2m in km/h
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspeed", 2 * 60, $webArgs->{windspeed} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "wind_speed_avg2m", $v );
            $webArgs->{windspeed_avg2m} = $v;
        }
    }

    # averages/wind_speed_mph_avg2m in mph
    if ( defined( $webArgs->{windspeedmph} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspeedmph", 2 * 60,
            $webArgs->{windspeedmph} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "wind_speed_mph_avg2m", $v );
            $webArgs->{windspdmph_avg2m}   = $v;
            $webArgs->{windspeedmph_avg2m} = $v;
        }
    }

    # averages/wind_speed_bft_avg2m in Beaufort (convert from km/h)
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        $webArgs->{windspeedbft_avg2m} =
          UConv::kph2bft( $webArgs->{windspeed_avg2m} );
        readingsBulkUpdate( $hash, "wind_speed_bft_avg2m",
            $webArgs->{windspeedbft_avg2m} );
    }

    # averages/wind_speed_kn_avg2m in Kn (convert from km/h)
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        $webArgs->{windspeedkn_avg2m} =
          UConv::kph2kn( $webArgs->{windspeed_avg2m} );
        readingsBulkUpdate( $hash, "wind_speed_kn_avg2m",
            $webArgs->{windspeedkn_avg2m} );
    }

    # averages/wind_speed_mps_avg2m in m/s
    if ( defined( $webArgs->{windspeed_avg2m} ) ) {
        my $v = UConv::kph2mps( $webArgs->{windspeed_avg2m} );
        $webArgs->{windspeedmps_avg2m} =
          ( $v > 0.5 ? round( $v, 1 ) : "0.0" );
        readingsBulkUpdate( $hash, "wind_speed_mps_avg2m",
            $webArgs->{windspeedmps_avg2m} );
    }

    # averages/wind_gust_sum10m
    if ( defined( $webArgs->{windgust} ) ) {
        my $v =
          HP1000_GetSum( $hash, "windgust", 10 * 60, $webArgs->{windgust} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "wind_gust_sum10m", $v );
            $webArgs->{windgust_10m} = $v;
        }
    }

    # averages/wind_gust_mph_sum10m
    if ( defined( $webArgs->{windgustmph} ) ) {
        my $v =
          HP1000_GetSum( $hash, "windgustmph", 10 * 60,
            $webArgs->{windgustmph} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "wind_gust_mph_sum10m", $v );
            $webArgs->{windgustmph_10m} = $v;
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

###################################
sub HP1000_GetAvg($$$$) {
    my ( $hash, $t, $s, $v, $avg ) = @_;
    return HP1000_GetSum( $hash, $t, $s, $v, 1 );
}

sub HP1000_GetSum($$$$;$) {
    my ( $hash, $t, $s, $v, $avg ) = @_;
    my $name = $hash->{NAME};

    return $v if ( $avg && $hash->{INTERVAL} < 1 );
    return "0" if ( $hash->{INTERVAL} < 1 );

    my $max = sprintf( "%.0f", $s / $hash->{INTERVAL} );
    $max = "1" if ( $max < 1 );
    my $return;

    my $v2 = unshift @{ $hash->{helper}{history}{$t} }, $v;
    my $v3 = splice @{ $hash->{helper}{history}{$t} }, $max;

    Log3 $name, 5, "HP1000 $name: Updated history for $t:"
      . Dumper( $hash->{helper}{history}{$t} );

    if ($avg) {
        $return = sprintf( "%.1f",
            sum( @{ $hash->{helper}{history}{$t} } ) /
              @{ $hash->{helper}{history}{$t} } );

        Log3 $name, 5, "HP1000 $name: Average for $t: $return";
    }
    else {
        $return = sprintf( "%.1f", sum( @{ $hash->{helper}{history}{$t} } ) );
        Log3 $name, 5, "HP1000 $name: Sum for $t: $return";
    }

    return $return;
}

###################################
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
                SSL_verify_mode => 0,
            },
        }
    );

    return;
}

###################################
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
    my $wu_indoorValues = AttrVal( $name, "wu_indoorValues", 1 );
    my $wu_dataValues   = AttrVal( $name, "wu_dataValues", undef );

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

    if ( AttrVal( $name, "wu_realtime", "1" ) eq "0" ) {
        Log3 $name, 5, "HP1000 $name: Explicitly turning off realtime";
        delete $webArgs->{realtime};
        delete $webArgs->{rtfreq};
    }
    elsif ( AttrVal( $name, "wu_realtime", "0" ) eq "1" ) {
        Log3 $name, 5, "HP1000 $name: Explicitly turning on realtime";
        $webArgs->{realtime} = 1;
    }

    if ($wu_dataValues) {
        my %dummy;
        my ( $err, @a ) = ReplaceSetMagic( \%dummy, 0, ($wu_dataValues) );
        if ($err) {
            Log3 $name, 3, "HP1000 $name: error parsing wu_dataValues: $err";
        }
        else {
            my ( undef, $h ) = parseParams( \@a );
            foreach ( keys %$h ) {
                next unless $_ ne "";
                Log3 $name, 4,
                  "HP1000 $name: Adding new value for WU: $_=$h->{$_}"
                  unless ( defined( $webArgs->{$_} ) );
                Log3 $name, 4,
                  "HP1000 $name: Replacing existing value for WU: $_=$h->{$_}"
                  if ( defined( $webArgs->{$_} ) );
                $webArgs->{$_} = $h->{$_};
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
        if ( $key eq "softwaretype" || $key eq "dateutc" ) {
            $value = urlEncode($value);
        }

        elsif ( $key eq "UVI" ) {
            $key   = "UV";
            $value = $value;
        }

        elsif ( $key eq "UV" ) {
            next;
        }

        if (  !$wu_indoorValues
            && $key =~
m/^(indoorhumidity|indoortempf|indoordewpointf|inhumi|intemp|indewpoint)/i
          )
        {
            Log3 $name, 4, "HP1000 $name: excluding indoor value $key=$value";
            next;
        }

        $cmd .= "$key=" . $value . "&";
    }

    Log3 $name, 4, "HP1000 $name: pushing data to WU: " . $cmd;

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

###################################
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

###################################
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
          Provides webhook receiver for Wifi-based weather station which support PWS protocol from Weather Underground (e.g. HP1000, WH2600, WH2601, WH3000 of Fine Offset Electronics - sometimes also known as Ambient Weather WS-1001-WIFI or similar). In Germany, these devices are commonly distributed by <a href="http://www.froggit.de/"froggit</a>.<br>
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
      </ul>
      </div><br>
    </div>
    <br>

    <a name="HP1000Attr" id="HP10000Attr"></a> <b>Attributes</b>
    <div>
    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <br>

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
          Stellt einen Webhook f&uuml;r WLAN-basierte Wetterstationen bereit, die das PWS Protokoll von Weather Underground verwenden (z.B. HP1000, WH2600, WH2601, WH3000 Wetterstation von Fine Offset Electronics - manchmal auch bekannt als Ambient Weather WS-1001-WIFI oder &auml;hnliches). In Deutschland werden die Ger&auml;te zumeist von <a href="http://www.froggit.de/"froggit</a> vertrieben.<br>
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
      </ul>
      </div><br>
    </div>

    <a name="HP1000Attr" id="HP10000Attr"></a> <b>Attributes</b>
    <div>
    <ul>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
      <br>

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

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Sendet die Daten an den WU Echtzeitserver statt an den Standard Server (Standard ist 1=an)
    </ul>
    </div>

    </ul>
=end html_DE

=cut

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
use Time::Local;
use Data::Dumper;
use List::Util qw(sum);
use FHEM::98_dewpoint;
use FHEM::59_Twilight;

sub HP1000_Define($$);
sub HP1000_Undefine($$);

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

    $hash->{DefFn}   = "HP1000_Define";
    $hash->{UndefFn} = "HP1000_Undefine";
    $hash->{AttrList} =
      "wu_push:1,0 wu_id wu_password wu_realtime:1,0 " . $readingFnAttributes;
}

###################################
sub HP1000_Define($$) {

    my ( $hash, $def ) = @_;

    my @a = split( "[ \t]+", $def, 5 );

    return "Usage: define <name> HP1000 [<ID> <PASSWORD>]"
      if ( int(@a) < 2 );
    my $name = $a[0];
    $hash->{ID}       = $a[2] if ( defined( $a[2] ) );
    $hash->{PASSWORD} = $a[3] if ( defined( $a[3] ) );

    return "Device already defined: " . $modules{HP1000}{defptr}{NAME}
      if ( defined( $modules{HP1000}{defptr} ) );

    $hash->{fhem}{infix} = "updateweatherstation";

    # create global unique device definition
    $modules{HP1000}{defptr} = $hash;

    HP1000_addExtension( $name, "HP1000_CGI", "updateweatherstation" );

    return undef;
}

###################################
sub HP1000_Undefine($$) {

    my ( $hash, $name ) = @_;

    HP1000_removeExtension( $hash->{fhem}{infix} );

    # release global unique device definition
    delete $modules{HP1000}{defptr};

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub HP1000_CGI() {

    my ($request) = @_;

    my $hash;
    my $name = "";
    my $link;
    my $URI;
    my $result = "";
    my $webArgs;

    # data received
    if ( $request =~ /^\/updateweatherstation\.(\w{3})\?(.+=.+)/ ) {
        $hash->{SERVER_TYPE} = lc($1);
        $URI = $2;

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

            $webArgs->{$p} = $v;
        }

        return ( "text/plain; charset=utf-8", "Insufficient data" )
          if ( !defined( $webArgs->{softwaretype} )
            || !defined( $webArgs->{dateutc} )
            || !defined( $webArgs->{ID} )
            || !defined( $webArgs->{PASSWORD} )
            || !defined( $webArgs->{action} ) );
    }

    # no data received
    else {
        return ( "text/plain; charset=utf-8", "Missing data" );
    }

    $hash = $defs{$name};

    $hash->{SWVERSION} = $webArgs->{softwaretype};
    $hash->{INTERVAL}  = (
        $hash->{SYSTEMTIME_UTC}
        ? time_str2num( $webArgs->{dateutc} ) -
          time_str2num( $hash->{SYSTEMTIME_UTC} )
        : 0
    );
    $hash->{SYSTEMTIME_UTC} = $webArgs->{dateutc};

    if (
           defined( $hash->{ID} )
        && defined( $hash->{PASSWORD} )
        && (   $hash->{ID} ne $webArgs->{ID}
            || $hash->{PASSWORD} ne $webArgs->{PASSWORD} )
      )
    {
        Log3 $name, 4, "HP1000: received data containing wrong credentials:";
        return ( "text/plain; charset=utf-8", "Wrong credentials" );
    }
    else {
        Log3 $name, 5, "HP1000: received data:\n" . Dumper($webArgs);

        delete $webArgs->{ID};
        delete $webArgs->{PASSWORD};
    }

    readingsBeginUpdate($hash);

    # write general readings
    while ( ( my $p, my $v ) = each %$webArgs ) {

        # ignore those values
        next
          if ( $v eq ""
            || $p eq "dateutc"
            || $p eq "action"
            || $p eq "softwaretype"
            || $p eq "realtime"
            || $p eq "rtfreq" );

        # name translation
        $p = "humidityIndoor"    if ( $p eq "inhumi" );
        $p = "temperatureIndoor" if ( $p eq "intemp" );
        $p = "humidity"          if ( $p eq "outhumi" );
        $p = "temperature"       if ( $p eq "outtemp" );
        $p = "luminosity"        if ( $p eq "light" );
        $p = "pressure"          if ( $p eq "relbaro" );
        $p = "pressureAbs"       if ( $p eq "absbaro" );
        $p = "rain"              if ( $p eq "rainrate" );
        $p = "rainDay"           if ( $p eq "dailyrain" );
        $p = "rainWeek"          if ( $p eq "weeklyrain" );
        $p = "rainMonth"         if ( $p eq "monthlyrain" );
        $p = "rainYear"          if ( $p eq "yearlyrain" );
        $p = "uv"                if ( $p eq "UV" );
        $p = "windChill"         if ( $p eq "windchill" );
        $p = "windDir"           if ( $p eq "winddir" );
        $p = "windGust"          if ( $p eq "windgust" );
        $p = "windSpeed"         if ( $p eq "windspeed" );

        readingsBulkUpdate( $hash, $p, $v );
    }

    # calculated readings
    #

    # dewpointIndoor
    if ( defined( $webArgs->{intemp} ) && defined( $webArgs->{inhumi} ) ) {
        my $h = (
            $webArgs->{inhumi} > 110
            ? 110
            : ( $webArgs->{inhumi} <= 0 ? 0.01 : $webArgs->{inhumi} )
        );
        my $v = sprintf( '%0.1f', dewpoint_dewpoint( $webArgs->{intemp}, $h ) );
        readingsBulkUpdate( $hash, "dewpointIndoor", $v );
    }

    # humidityAbs
    if ( defined( $webArgs->{outtemp} ) && defined( $webArgs->{outhumi} ) ) {
        my $h = (
            $webArgs->{outhumi} > 110
            ? 110
            : ( $webArgs->{outhumi} <= 0 ? 0.01 : $webArgs->{outhumi} )
        );
        my $v = int( dewpoint_absFeuchte( $webArgs->{outtemp}, $h ) + 0.5 );
        readingsBulkUpdate( $hash, "humidityAbs", $v );
    }

    # humidityIndoorAbs
    if ( defined( $webArgs->{intemp} ) && defined( $webArgs->{inhumi} ) ) {
        my $h = (
            $webArgs->{inhumi} > 110
            ? 110
            : ( $webArgs->{inhumi} <= 0 ? 0.01 : $webArgs->{inhumi} )
        );
        my $v = int( dewpoint_absFeuchte( $webArgs->{intemp}, $h ) + 0.5 );
        readingsBulkUpdate( $hash, "humidityIndoorAbs", $v );
    }

    # windCompasspoint
    if ( defined( $webArgs->{winddir} ) ) {
        my $v = Twilight_CompassPoint( $webArgs->{winddir} );
        readingsBulkUpdate( $hash, "windCompasspoint", $v );
        $webArgs->{windCompasspoint} = $v;
    }

    # windSpeedForce in Beaufort
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v = HP1000_windForce( $webArgs->{windspeed} );
        readingsBulkUpdate( $hash, "windSpeedForce", $v );
        $webArgs->{windSpeedForce} = $v;
    }

    # windGustForce in Beaufort
    if ( defined( $webArgs->{windgust} ) ) {
        my $v = HP1000_windForce( $webArgs->{windgust} );
        readingsBulkUpdate( $hash, "windGustForce", $v );
        $webArgs->{windGustForce} = $v;
    }

    # windSpeedMps in m/s
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v = HP1000_windKmh2Mps( $webArgs->{windspeed} );
        $v = ( $v > 0.5 ? sprintf( '%0.1f', $v ) : "0.0" );
        readingsBulkUpdate( $hash, "windSpeedMps", $v );
        $webArgs->{windSpeedMps} = $v;
    }

    # windGustMps in m/s
    if ( defined( $webArgs->{windgust} ) ) {
        my $v = HP1000_windKmh2Mps( $webArgs->{windgust} );
        $v = ( $v > 0.5 ? sprintf( '%0.1f', $v ) : "0.0" );
        readingsBulkUpdate( $hash, "windGustMps", $v );
        $webArgs->{windgust} = $v;
    }

    # averages/windSpeed_avg2m
    if ( defined( $webArgs->{windspeed} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspeed", 2 * 60, $webArgs->{windspeed} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windSpeed_avg2m", $v );
            $webArgs->{windspd_avg2m} = $v;
        }
    }
    elsif ( defined( $webArgs->{windspeedmph} ) ) {
        my $v =
          HP1000_GetAvg( $hash, "windspeedmph", 2 * 60,
            $webArgs->{windspeedmph} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windSpeed_avg2m", $v );
            $webArgs->{windspdmph_avg2m} = $v;
        }
    }

    # averages/windSpeedForce_avg2m in Beaufort
    if ( defined( $webArgs->{windspd_avg2m} ) ) {
        my $v = HP1000_windForce( $webArgs->{windspd_avg2m} );
        readingsBulkUpdate( $hash, "windSpeedForce_avg2m", $v );
        $webArgs->{windSpeedForce_avg2m} = $v;
    }

    # averages/windSpeedMps_avg2m in m/s
    if ( defined( $webArgs->{windspd_avg2m} ) ) {
        my $v = HP1000_windKmh2Mps( $webArgs->{windspd_avg2m} );
        $v = ( $v > 0.5 ? sprintf( '%0.1f', $v ) : "0.0" );
        readingsBulkUpdate( $hash, "windSpeedMps_avg2m", $v );
        $webArgs->{windspdmps_avg2m} = $v;
    }

    # averages/windDir_avg2m
    if ( defined( $webArgs->{winddir} ) ) {
        my $v = HP1000_GetAvg( $hash, "winddir", 2 * 60, $webArgs->{winddir} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windDir_avg2m", $v );
            $webArgs->{winddir_avg2m} = $v;
        }
    }

    # averages/windCompasspoint_avg2m
    if ( defined( $webArgs->{winddir_avg2m} ) ) {
        my $v = Twilight_CompassPoint( $webArgs->{winddir_avg2m} );
        readingsBulkUpdate( $hash, "windCompasspoint_avg2m", $v );
        $webArgs->{windCompasspoint_avg2m} = $v;
    }

    # averages/windGust_sum10m
    if ( defined( $webArgs->{windgust} ) ) {
        my $v =
          HP1000_GetSum( $hash, "windgust", 10 * 60, $webArgs->{windgust} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windGust_sum10m", $v );
            $webArgs->{windgust_10m} = $v;
        }
    }
    elsif ( defined( $webArgs->{windgustmph} ) ) {
        my $v =
          HP1000_GetSum( $hash, "windgustmph", 10 * 60,
            $webArgs->{windgustmph} );

        if ( $hash->{INTERVAL} > 0 ) {
            readingsBulkUpdate( $hash, "windGust_sum10m", $v );
            $webArgs->{windgustmph_10m} = $v;
        }
    }

    # from WU API:
    # weather - [text] -- metar style (+RA)
    # clouds - [text] -- SKC, FEW, SCT, BKN, OVC
    # soiltempf - [F soil temperature]
    # soilmoisture - [%]
    # leafwetness  - [%]
    # visibility - [nm visibility]

    # condition_forecast (based on pressure trendency)

    # day/night

    # isRaining
    # solarRadiation
    # soilTemperature
    # brightness in % ??

    # uv_index, uv_risk
    if ( defined( $webArgs->{UV} ) ) {
        my $wavelength = $webArgs->{UV};
    }

    $result = "T: " . $webArgs->{outtemp}
      if ( defined( $webArgs->{outtemp} ) );
    $result .= " H: " . $webArgs->{outhumi}
      if ( defined( $webArgs->{outhumi} ) );
    $result .= " Ti: " . $webArgs->{intemp}
      if ( defined( $webArgs->{intemp} ) );
    $result .= " Hi: " . $webArgs->{inhumi}
      if ( defined( $webArgs->{inhumi} ) );
    $result .= " W: " . $webArgs->{windspeed}
      if ( defined( $webArgs->{windspeed} ) );
    $result .= " W: " . $webArgs->{windspeedmph}
      if ( defined( $webArgs->{windspeedmph} ) );
    $result .= " WC: " . $webArgs->{windchill}
      if ( defined( $webArgs->{windchill} ) );
    $result .= " WG: " . $webArgs->{windgust}
      if ( defined( $webArgs->{windgust} ) );
    $result .= " WG: " . $webArgs->{windgustmph}
      if ( defined( $webArgs->{windgustmph} ) );
    $result .= " R: " . $webArgs->{rainrate}
      if ( defined( $webArgs->{rainrate} ) );
    $result .= " RD: " . $webArgs->{dailyrain}
      if ( defined( $webArgs->{dailyrain} ) );
    $result .= " RW: " . $webArgs->{weeklyrain}
      if ( defined( $webArgs->{weeklyrain} ) );
    $result .= " RM: " . $webArgs->{monthlyrain}
      if ( defined( $webArgs->{monthlyrain} ) );
    $result .= " RY: " . $webArgs->{yearlyrain}
      if ( defined( $webArgs->{yearlyrain} ) );
    $result .= " WD: " . $webArgs->{winddir}
      if ( defined( $webArgs->{winddir} ) );
    $result .= " D: " . $webArgs->{dewpoint}
      if ( defined( $webArgs->{dewpoint} ) );
    $result .= " P: " . $webArgs->{relbaro}
      if ( defined( $webArgs->{relbaro} ) );
    $result .= " UV: " . $webArgs->{UV}
      if ( defined( $webArgs->{UV} ) );
    $result .= " L: " . $webArgs->{light}
      if ( defined( $webArgs->{light} ) );

    readingsBulkUpdate( $hash, "state", $result );
    readingsEndUpdate( $hash, 1 );

    HP1000_PushWU( $hash, $webArgs )
      if AttrVal( $name, "wu_push", 0 ) eq "1";

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

    my $max = int( $s / $hash->{INTERVAL} );
    my $return;

    my $v2 = unshift @{ $hash->{helper}{history}{$t} }, "$v";
    my $v3 = splice @{ $hash->{helper}{history}{$t} }, "$max";

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

    Log3 $name, 5, "HP1000 $name: called function HP1000_PushWU()";

    if ( $wu_user eq "" && $wu_pass eq "" ) {
        Log3 $name, 4,
"HP1000 $name: missing attributes for Weather Underground transfer: wu_user and wu_password";

        my $return = "error: missing attributes wu_user and wu_password";

        readingsSingleUpdate( $hash, "wu_state", $return, 1 )
          if ( ReadingsVal( $name, "wu_state", "" ) ne $return );
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

    $webArgs->{rtfreq} = 5
      if ( defined( $webArgs->{realtime} ) && !defined( $webArgs->{rtfreq} ) );

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

        elsif ( $key eq "windspeed" ) {
            $key   = "windspeedmph";
            $value = $value / 1.609344;    # convert from kph to mph
        }

        elsif ( $key eq "windspd_avg2m" ) {
            $key   = "windspdmph_avg2m";
            $value = $value / 1.609344;    # convert from kph to mph
        }

        elsif ( $key eq "windgust" ) {
            $key   = "windgustmph";
            $value = $value / 1.609344;    # convert from kph to mph
        }

        elsif ( $key eq "windgust_10m" ) {
            $key   = "windgustmph_10m";
            $value = $value / 1.609344;    # convert from kph to mph
        }

        elsif ( $key eq "inhumi" ) {
            $key = "indoorhumidity";
        }

        elsif ( $key eq "intemp" ) {
            $key   = "indoortempf";
            $value = $value * 9 / 5 + 32;   # convert from Celsius to Fahrenheit
        }

        elsif ( $key eq "intempf" ) {
            $key = "indoortempf";
        }

        elsif ( $key eq "outhumi" ) {
            $key = "humidity";
        }

        elsif ( $key eq "outtemp" ) {
            $key   = "tempf";
            $value = $value * 9 / 5 + 32;   # convert from Celsius to Fahrenheit
        }

        elsif ( $key eq "outtempf" ) {
            $key = "tempf";
        }

        elsif ( $key eq "rain" ) {
            $key   = "rainin";
            $value = $value / 25.4;         # convert from mm to inch
        }

        elsif ( $key eq "dailyrain" ) {
            $key   = "dailyrainin";
            $value = $value / 25.4;         # convert from mm to inch
        }

        elsif ( $key eq "dewpoint" ) {
            $key   = "dewptf";
            $value = $value * 9 / 5 + 32;   # convert from Celsius to Fahrenheit
        }

        elsif ( $key eq "relbaro" ) {
            $key   = "baromin";
            $value = $value * 100 *
              0.000295299830714;    # convert from hPa to Inches of Mercury
        }

        elsif ( $key eq "light" ) {
            $key   = "solarradiation";
            $value = $value * 0.01;      # convert from uW/cm2 to W/m2
        }

        $cmd .= "$key=" . $value . "&";
    }

    Log3 $name, 4, "HP1000 $name: pushing data to WU: " . $cmd;

    HttpUtils_NonblockingGet(
        {
            url        => $wu_url . $cmd,
            timeout    => $timeout,
            noshutdown => $http_noshutdown,
            data       => undef,
            hash       => $hash,
            callback   => \&HP1000_ReturnWU,
        }
    );

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

        readingsSingleUpdate( $hash, "wu_state", $return, 1 )
          if ( ReadingsVal( $name, "wu_state", "" ) ne $return );
    }

    # data received
    elsif ($data) {
        my $logprio = 5;
        my $return  = "ok";

        if ( $data !~ m/^success.*/ ) {
            $logprio = 4;
            $return  = "error";
            $return .= " " . $param->{code} if ( $param->{code} ne "200" );
            $return .= ": $data";
        }
        Log3 $name, $logprio,
          "HP1000 $name: WU HTTP return: " . $param->{code} . " - $data";

        readingsSingleUpdate( $hash, "wu_state", $return, 1 )
          if ( ReadingsVal( $name, "wu_state", "" ) ne $return );
    }

    return;
}

###################################
sub HP1000_windForce($) {
    my ($data) = @_;
    my $v = "0";

    if ( $data >= 118 ) {
        $v = "12";
    }
    elsif ( $data >= 103 ) {
        $v = "11";
    }
    elsif ( $data >= 89 ) {
        $v = "10";
    }
    elsif ( $data >= 75 ) {
        $v = "9";
    }
    elsif ( $data >= 62 ) {
        $v = "8";
    }
    elsif ( $data >= 50 ) {
        $v = "7";
    }
    elsif ( $data >= 39 ) {
        $v = "6";
    }
    elsif ( $data >= 29 ) {
        $v = "5";
    }
    elsif ( $data >= 20 ) {
        $v = "4";
    }
    elsif ( $data >= 12 ) {
        $v = "3";
    }
    elsif ( $data >= 6 ) {
        $v = "2";
    }
    elsif ( $data >= 1 ) {
        $v = "1";
    }

    return $v;
}

###################################
sub HP1000_windKmh2Mps($) {
    my ($data) = @_;

    # convert km/h to m/s
    return $data / 3.6;
}

1;

=pod
=item device
=item summary support for Wifi-based weather stations HP1000 and WH2600
=item summary_DE Unterst&uuml;tzung f&uuml;r die WLAN-basierte HP1000 oder WH2600 Wetterstationen
=begin html

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <div>
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div>
        <code>define &lt;WeatherStation&gt; HP1000 [&lt;ID&gt; &lt;PASSWORD&gt;]</code><br>
        <br>
          Provides webhook receiver for Wifi-based weather station HP1000 and WH2600 of Fine Offset Electronics (e.g. also known as Ambient Weather WS-1001-WIFI).<br>
          There needs to be a dedicated FHEMWEB instance with attribute webname set to "weatherstation".<br>
          No other name will work as it's hardcoded in the HP1000/WH2600 device itself!<br>
          <br>
          As the URI has a fixed coding as well there can only be one single HP1000/WH2600 station per FHEM installation.<br>
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
          IMPORTANT: In your HP1000/WH2600 hardware device, make sure you use a DNS name as most revisions cannot handle IP addresses correctly.<br>
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

      <a name="wu_push"></a><li><b>wu_push</b></li>
        Enable or disable to push data forward to Weather Underground (defaults to 0=no)

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Send the data to the WU realtime server instead of using the standard server (defaults to 1=yes)
    </ul>
    </div>

=end html

=begin html_DE

    <p>
      <a name="HP1000" id="HP1000"></a>
    </p>
    <h3>
      HP1000
    </h3>
    <div>
      <a name="HP1000define" id="HP10000define"></a> <b>Define</b>
      <div>
        <code>define &lt;WeatherStation&gt; HP1000 [&lt;ID&gt; &lt;PASSWORD&gt;]</code><br>
        <br>
          Stellt einen Webhook f&uuml;r die WLAN-basierte HP1000 oder WH2600 Wetterstation von Fine Offset Electronics bereit (z.B. auch bekannt als Ambient Weather WS-1001-WIFI).<br>
          Es muss noch eine dedizierte FHEMWEB Instanz angelegt werden, wo das Attribut webname auf "weatherstation" gesetzt wurde.<br>
          Kein anderer Name funktioniert, da dieser hard im HP1000/WH2600 Ger&auml;t hinterlegt ist!<br>
          <br>
          Da die URI ebenfalls fest kodiert ist, kann mit einer einzelnen FHEM Installation maximal eine HP1000/WH2600 Station gleichzeitig verwendet werden.<br>
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
          WICHTIG: Im HP1000/WH2600 Ger&auml;t selbst muss sichergestellt sein, dass ein DNS Name statt einer IP Adresse verwendet wird, da einige Revisionen damit nicht umgehen k&ouml;nnen.<br>
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

      <a name="wu_push"></a><li><b>wu_push</b></li>
        Pushen der Daten zu Weather Underground aktivieren oder deaktivieren (Standard ist 0=aus)

      <a name="wu_realtime"></a><li><b>wu_realtime</b></li>
        Sendet die Daten an den WU Echtzeitserver statt an den Standard Server (Standard ist 1=an)
    </ul>
    </div>

=end html_DE

=cut

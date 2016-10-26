# $Id$
##############################################################################
#
#     59_Wunderground.pm
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

# http://api.wunderground.com/weather/api

package main;

use strict;
use warnings;
use vars qw(%data);
use HttpUtils;
use Encode;
use UConv;
use Data::Dumper;

sub Wunderground_Hash2Readings($$;$);

###################################
sub Wunderground_Initialize($) {
    my ($hash) = @_;

    Log3 $hash, 5, "Wunderground_Initialize: Entering";

    my $webhookFWinstance =
      join( ",", devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') );

    $hash->{SetFn}         = "Wunderground_Set";
    $hash->{DefFn}         = "Wunderground_Define";
    $hash->{AttrFn}        = "Wunderground_Attr";
    $hash->{UndefFn}       = "Wunderground_Undefine";
    $hash->{DbLog_splitFn} = "Wunderground_DbLog_split";
    $hash->{parseParams}   = 1;

    $hash->{AttrList} =
"disable:0,1 timeout:1,2,3,4,5 pollInterval:300,450,600,750,900 wu_lang:en,de,at,ch,nl,fr,pl "
      . $readingFnAttributes;

    return;
}

#####################################
sub Wunderground_GetStatus($;$) {
    my ( $hash, $delay ) = @_;
    my $name = $hash->{NAME};
    $hash->{INTERVAL} = AttrVal( $name, "pollInterval", "300" );
    my $lang = AttrVal( $name, "wu_lang", "en" );
    my $interval = (
          $delay
        ? $delay
        : $hash->{INTERVAL}
    );

    Log3 $name, 5,
      "Wunderground $name: called function Wunderground_GetStatus()";

    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday() + $interval,
        "Wunderground_GetStatus", $hash, 0 );

    return
      if ( $delay || AttrVal( $name, "disable", 0 ) == 1 );

    if ( $lang eq "de" ) {
        $hash->{LANG} = "DL";
    }
    elsif ( $lang eq "at" ) {
        $hash->{LANG} = "OS";
    }
    elsif ( $lang eq "ch" ) {
        $hash->{LANG} = "SW";
    }
    else {
        $hash->{LANG} = uc($lang);
    }

    Wunderground_SendCommand( $hash,
        "astronomy/conditions/forecast/lang:" . $hash->{LANG} );

    return;
}

###################################
sub Wunderground_Set($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 5, "Wunderground $name: called function Wunderground_Set()";

    return "Argument is missing" if ( int(@$a) < 1 );

    my $usage = "Unknown argument " . @$a[1] . ", choose one of update:noArg";

    my $cmd = '';
    my $result;

    # update
    if ( lc( @$a[1] ) eq "update" ) {
        Log3 $name, 3, "Wunderground set $name " . @$a[1];
        Wunderground_GetStatus($hash);
    }

    # return usage hint
    else {
        return $usage;
    }

    return $result;
}

###################################
sub Wunderground_Define($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name  = $hash->{NAME};
    my $infix = "Wunderground";

    Log3 $name, 5, "Wunderground $name: called function Wunderground_Define()";

    eval {
        require JSON;
        import JSON qw( decode_json );
    };
    return "Please install Perl JSON to use module Wunderground"
      if ($@);

    if ( int(@$a) < 2 ) {
        my $msg = "Wrong syntax: define <name> Wunderground <api-key> <pws-id>";
        Log3 $name, 4, $msg;
        return $msg;
    }

    $hash->{TYPE} = "Wunderground";

    $hash->{API_KEY} = @$a[2];
    $hash->{PWS_ID}  = @$a[3];

    # start the status update timer
    Wunderground_GetStatus( $hash, 2 );

    return;
}

###################################
sub Wunderground_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    Log3 $name, 5, "Wunderground $name: called function Wunderground_Attr()";

    return
"Invalid value for attribute $attrName: minimum value is 1 second, maximum 5 seconds"
      if ( $attrVal
        && $attrName eq "timeout"
        && ( $attrVal < 1 || $attrVal > 5 ) );

    return
      "Invalid value for attribute $attrName: minimum value is 300 seconds"
      if ( $attrVal && $attrName eq "pollInterval" && $attrVal < 300 );

    return undef;
}

############################################################################################################
#
#   Begin of helper functions
#
############################################################################################################

###################################
sub Wunderground_SendCommand($$) {
    my ( $hash, $features ) = @_;
    my $name   = $hash->{NAME};
    my $apikey = $hash->{API_KEY};
    my $pws    = $hash->{PWS_ID};
    my $URL =
      "https://api.wunderground.com/api/%APIKEY%/%FEATURES%/q/PWS:%PWSID%.json";

    Log3 $name, 5,
      "Wunderground $name: called function Wunderground_SendCommand()";

    $URL =~ s/%APIKEY%/$apikey/;
    $URL =~ s/%FEATURES%/$features/;
    $URL =~ s/%PWSID%/$pws/;

    Log3 $name, 5, "Wunderground $name: GET " . urlDecode($URL);

    HttpUtils_NonblockingGet(
        {
            url     => $URL,
            timeout => AttrVal( $name, "timeout", "3" ),
            hash    => $hash,
            method  => "GET",
            header =>
"agent: FHEM-Wunderground/1.0.0\r\nUser-Agent: FHEM-Wunderground/1.0.0\r\nAccept: application/json",
            httpversion => "1.1",
            callback    => \&Wunderground_ReceiveCommand,
        }
    );

    return;
}

###################################
sub Wunderground_ReceiveCommand($$$) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $lastQueryResult =
      ReadingsVal( $name, "lastQueryResult", "Initialized" );
    my $return;

    Log3 $name, 5,
      "Wunderground $name: called function Wunderground_ReceiveCommand()";

    readingsBeginUpdate($hash);

    # service not reachable
    if ($err) {
        Log3 $name, 4, "Wunderground $name: RCV TIMEOUT: $err";

        $lastQueryResult = "unavailable";
    }

    # data received
    elsif ($data) {
        Log3 $name, 4, "Wunderground $name: RCV";

        if ( $data ne "" ) {

            # fix malformed JSON ...
            $data =~ s/^[\s\r\n0-9a-zA-Z]*//;
            $data =~ s/[\s\r\n0-9a-zA-Z]*$//;
            $data =~ s/[\r\n]+[0-9a-zA-Z]+[\r\n]+//g;

            eval '$return = decode_json( Encode::encode_utf8($data) ); 1';
            if ($@) {

                Log3 $name, 5,
"Wunderground $name: RES ERROR - unable to parse malformed JSON: $@\n"
                  . $data;

                return undef;
            }
            else {
                Log3 $name, 5, "Wunderground $name: RES";
            }
        }

        $lastQueryResult = "ok";

        #######################
        # process return data
        #
        if ( $return && ref($return) eq "HASH" ) {
            Wunderground_Hash2Readings( $hash, $return );
        }
    }

    readingsBulkUpdateIfChanged( $hash, "lastQueryResult", $lastQueryResult );
    readingsEndUpdate( $hash, 1 );

    return;
}

###################################
sub Wunderground_Hash2Readings($$;$) {
    my ( $hash, $h, $r ) = @_;
    my $name = $hash->{NAME};
    my $loop = 0;
    $loop = 1 if ( defined($r) );

    if ( ref($h) eq "HASH" ) {
        foreach my $k ( keys %{$h} ) {
            next
              if ( $k eq "response"
                || $k eq "image"
                || $k eq "station_id"
                || $k =~ /^.*_string$/ );

            my $reading;
            my $cr = $k;

            # hash level1 renaming
            $cr = "" if ( $cr eq "current_observation" );

            # custom reading
            $cr = "condition"      if ( $cr eq "weather" );
            $cr = "dewpoint"       if ( $cr eq "dewpoint_c" );
            $cr = "humidity"       if ( $cr eq "relative_humidity" );
            $cr = "pressure"       if ( $cr eq "pressure_mb" );
            $cr = "rain"           if ( $cr eq "precip_1hr_metric" );
            $cr = "rain_day"       if ( $cr eq "precip_today_metric" );
            $cr = "rain_in"        if ( $cr eq "precip_1hr_in" );
            $cr = "rain_day_in"    if ( $cr eq "precip_today_in" );
            $cr = "wind_direction" if ( $cr eq "wind_degrees" );
            $cr = "wind_gust"      if ( $cr eq "wind_gust_kph" );
            $cr = "wind_gust_mph"  if ( $cr eq "wind_gust_mph" );
            $cr = "wind_speed"     if ( $cr eq "wind_kph" );
            $cr = "wind_speed_mph" if ( $cr eq "wind_mph" );
            $cr = "wind_chill"     if ( $cr eq "windchill_c" );
            $cr = "wind_chill_f"   if ( $cr eq "windchill_f" );
            $cr = "visibility"     if ( $cr eq "visibility_km" );

            next
              if ( $cr =~ /^sun_phase(.*)$/
                || $cr eq "date"
                || $cr eq "wind_dir" );
            next if ( $r && $r =~ /^display_location.*$/ );

            # observation_*
            if ( $cr =~ /^observation_.*$/ ) {
                $hash->{LAST_OBSERVATION} = $h->{observation_epoch};
                next;
            }

            # local_*
            elsif ( $cr =~ /^local_.*$/ ) {
                $hash->{LAST} = $h->{local_epoch};
                next;
            }

            # moon_phase
            elsif ( $cr =~ /^moon_phase(.*)$/ ) {
                my $sunrise = $h->{moon_phase}{sunrise}{hour} . ":"
                  . $h->{moon_phase}{sunrise}{minute};
                my $sunset = $h->{moon_phase}{sunset}{hour} . ":"
                  . $h->{moon_phase}{sunset}{minute};
                my $moonrise = $h->{moon_phase}{moonrise}{hour} . ":"
                  . $h->{moon_phase}{moonrise}{minute};
                my $moonset = $h->{moon_phase}{moonset}{hour} . ":"
                  . $h->{moon_phase}{moonset}{minute};

                $sunrise =~ s/^(\d):(\d\d)$/0$1:$2/;
                $sunrise =~ s/^(\d\d):(\d)$/$1:0$2/;
                $sunset =~ s/^(\d):(\d\d)$/0$1:$2/;
                $sunset =~ s/^(\d\d):(\d)$/$1:0$2/;
                $moonrise =~ s/^(\d):(\d\d)$/0$1:$2/;
                $moonrise =~ s/^(\d\d):(\d)$/$1:0$2/;
                $moonset =~ s/^(\d):(\d\d)$/0$1:$2/;
                $moonset =~ s/^(\d\d):(\d)$/$1:0$2/;

                readingsBulkUpdate( $hash, "sunrise",  $sunrise );
                readingsBulkUpdate( $hash, "sunset",   $sunset );
                readingsBulkUpdate( $hash, "moonrise", $moonrise );
                readingsBulkUpdate( $hash, "moonset",  $moonset );

                readingsBulkUpdate( $hash, "moon_age",
                    $h->{moon_phase}{ageOfMoon} );
                readingsBulkUpdate( $hash, "moon_pct",
                    $h->{moon_phase}{percentIlluminated} );
                readingsBulkUpdate( $hash, "moon_phase",
                    $h->{moon_phase}{phaseofMoon} );
            }

            # simpleforecast
            elsif ($r
                && $r =~ /^forecast\/simpleforecast\/forecastday(\d+)$/ )
            {
                my $period = $h->{period} - 1;
                $reading = "fc" . $period . "_";

                readingsBulkUpdate( $hash, $reading . "condition",
                    $h->{conditions} );
                readingsBulkUpdate(
                    $hash,
                    $reading . "high_c",
                    $h->{high}{celsius}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "high_f",
                    $h->{high}{fahrenheit}
                );
                readingsBulkUpdate( $hash, $reading . "humidity",
                    $h->{avehumidity} );
                readingsBulkUpdate( $hash, $reading . "humidity_min",
                    $h->{minhumidity} );
                readingsBulkUpdate( $hash, $reading . "humidity_max",
                    $h->{maxhumidity} );
                readingsBulkUpdate( $hash, $reading . "icon", $h->{icon} );
                readingsBulkUpdate( $hash, $reading . "icon_url",
                    $h->{icon_url} );
                readingsBulkUpdate(
                    $hash,
                    $reading . "low_c",
                    $h->{low}{celsius}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "low_f",
                    $h->{low}{fahrenheit}
                );
                readingsBulkUpdate( $hash, $reading . "pop", $h->{pop} );
                readingsBulkUpdate(
                    $hash,
                    $reading . "rain_day",
                    $h->{qpf_allday}{mm}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "rain_day_in",
                    $h->{qpf_allday}{in}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "rain_night",
                    $h->{qpf_night}{mm}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "rain_night_in",
                    $h->{qpf_night}{in}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "snow_day",
                    $h->{snow_allday}{cm}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "snow_day_in",
                    $h->{snow_allday}{in}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "snow_night",
                    $h->{snow_night}{cm}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "snow_night_in",
                    $h->{snow_night}{in}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "wind_direction",
                    $h->{avewind}{degrees}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "wind_direction_max",
                    $h->{maxwind}{degrees}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "wind_speed",
                    $h->{avewind}{kph}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "wind_speed_mph",
                    $h->{avewind}{mph}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "wind_speed_max",
                    $h->{maxwind}{kph}
                );
                readingsBulkUpdate(
                    $hash,
                    $reading . "wind_speed_max_mph",
                    $h->{maxwind}{mph}
                );
            }

            # txt_forecast
            elsif ($r
                && $r =~ /^forecast\/txt_forecast\/forecastday(\d+)$/ )
            {
                my $period = $h->{period};
                my $night =
                  (      $period eq "1"
                      || $period eq "3"
                      || $period eq "5"
                      || $period eq "7" ? "_night" : "" );

                if ( $period < 2 ) {
                    $period = "0";
                }
                elsif ( $period < 4 ) {
                    $period = "1";
                }
                elsif ( $period < 6 ) {
                    $period = "2";
                }
                elsif ( $period < 8 ) {
                    $period = "3";
                }

                $reading = "fc" . $period . "_";

                readingsBulkUpdate( $hash, $reading . "icon$night",
                    $h->{icon} );
                readingsBulkUpdate( $hash, $reading . "icon_url$night",
                    $h->{icon_url} );
                readingsBulkUpdate( $hash, $reading . "pop$night", $h->{pop} );
                readingsBulkUpdate( $hash, $reading . "text$night",
                    $h->{fcttext_metric} );
                readingsBulkUpdate( $hash, $reading . "text_f$night",
                    $h->{fcttext} );
                readingsBulkUpdate( $hash, $reading . "title$night",
                    $h->{title} );
            }

            elsif ( ref( $h->{$k} ) eq "HASH" || ref( $h->{$k} ) eq "ARRAY" ) {
                $reading .= $r . "/" if ( $r && $r ne "" );
                $reading .= $cr;

                Wunderground_Hash2Readings( $hash, $h->{$k}, $reading );
            }

            else {
                $reading .= $r . "_." if ( $r && $r ne "" );
                $reading .= $cr;
                my $value = $h->{$k};
                $value = "" if ( !defined($value) || $value eq "NA" );

                $value = "0"
                  if ( $reading =~ /^wind(Gust|Speed).*$/
                    && $value eq "-9999" );

                $value =~ s/^(\d+)%$/$1/;

                readingsBulkUpdate( $hash, $reading, $value );
            }
        }
    }
    elsif ( ref($h) eq "ARRAY" ) {
        my $i = 0;

        foreach ( @{$h} ) {
            if ( ref($_) eq "HASH" || ref($_) eq "ARRAY" ) {
                Wunderground_Hash2Readings( $hash, $_, $r . $i );
            }
            else {
                readingsBulkUpdate( $hash, $r . $i, $_ );
            }

            $i++;
        }
    }
}

###################################
sub Wunderground_Undefine($$$) {
    my ( $hash, $a, $h ) = @_;
    my $name = $hash->{NAME};

    if ( defined( $hash->{fhem}{infix} ) ) {
        Wunderground_removeExtension( $hash->{fhem}{infix} );
    }

    Log3 $name, 5,
      "Wunderground $name: called function Wunderground_Undefine()";

    # Stop the internal GetStatus-Loop and exit
    RemoveInternalTimer($hash);

    # release reverse pointer
    delete $modules{Wunderground}{defptr}{$name};

    return;
}

###################################
sub Wunderground_DbLog_split($$) {
    my ( $event, $device ) = @_;
    my ( $reading, $value, $unit ) = "";
    my $hash = $defs{$device};

    if ( $event =~
/^(wind_compasspoint.*|.*_sum10m|.*_avg2m|uvCondition):\s([\w\.,]+)\s*(.*)/
      )
    {
        return undef;
    }
    elsif ( $event =~ /^(dewpoint|temp_c|wind_chill):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "°C";
    }
    elsif ( $event =~ /^(dewpoint_f|temp_f|wind_chill_f):\s([\w\.,]+)\s*(.*)/ )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "°F";
    }
    elsif ( $event =~ /^(.*humidity.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "%";
    }
    elsif ( $event =~ /^(solarradiation):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "W/m2";
    }
    elsif ( $event =~ /^(pressure_trend):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "";
        $value   = "0" if ( $2 eq "=" );
        $value   = "1" if ( $2 eq "+" );
        $value   = "2" if ( $2 eq "-" );
        return undef if ( $value eq "" );
        $unit = "";
    }
    elsif ( $event =~ /^(pressure|pressureAbs):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "hPa";
    }
    elsif ( $event =~ /^(pressure_in|pressureAbs_in):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "inHg";
    }
    elsif ( $event =~ /^(pressure_mm|pressureAbs_mm):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "mmHg";
    }
    elsif ( $event =~ /^(rain):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "mm/h";
    }
    elsif ( $event =~ /^(rain_in):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "in/h";
    }
    elsif ( $event =~ /^(rain|.*rain_day|.*rain_night):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "mm";
    }
    elsif ( $event =~
        /^(rain_in|.*rain_day_in|.*rain_night_in):\s([\w\.,]+)\s*(.*)/ )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "in";
    }
    elsif ( $event =~ /^(UV):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "UVI";
    }
    elsif ( $event =~ /^(.*wind_direction.*):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "°";
    }
    elsif ( $event =~
        /^(.*wind_gust|.*wind_speed|.*wind_speed_max):\s([\w\.,]+)\s*(.*)/ )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "km/h";
    }
    elsif ( $event =~
/^(.*wind_gust_mph|.*wind_speed_mph|.*wind_speed_max_mph):\s([\w\.,]+)\s*(.*)/
      )
    {
        $reading = $1;
        $value   = $2;
        $unit    = "mph";
    }
    elsif ( $event =~ /^(wind_gust_bft|wind_speed_bft):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "Bft";
    }
    elsif ( $event =~ /^(wind_gust_mps|wind_speed_mps):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "m/s";
    }
    elsif ( $event =~ /^(wind_gust_fts|wind_speed_fts):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "ft/s";
    }
    elsif ( $event =~ /^(wind_gust_kn|wind_speed_kn):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = "kn";
    }
    elsif ( $event =~ /^(.*condition):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "";
        $value   = "0" if ( $2 eq "clear" );
        $value   = "1" if ( $2 eq "sunny" );
        $value   = "2" if ( $2 eq "cloudy" );
        $value   = "3" if ( $2 eq "rain" );
        return undef if ( $value eq "" );
        $unit = "";
    }
    elsif ( $event =~ /^(humidity_condition):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = "";
        $value   = "0" if ( $2 eq "dry" );
        $value   = "1" if ( $2 eq "low" );
        $value   = "2" if ( $2 eq "optimal" );
        $value   = "3" if ( $2 eq "wet" );
        $value   = "4" if ( $2 eq "rain" );
        return undef if ( $value eq "" );
        $unit = "";
    }
    elsif ( $event =~ /(.+):\s([\w\.,]+)\s*(.*)/ ) {
        $reading = $1;
        $value   = $2;
        $unit    = $3;
    }

    Log3 $device, 5,
"Wunderground $device: Splitting event $event > reading=$reading value=$value unit=$unit";

    return ( $reading, $value, $unit );
}

1;

=pod
=item device
=item summary Get weather data and forecast from Weather Underground
=item summary_DE Ruft Wetterdaten und Vorhersage von Weather Underground ab
=begin html

<a name="Wunderground" id="Wunderground"></a>
<h3>Wunderground</h3>
<ul>
  This module gets weather data and forecast from <a href="http://www.wunderground.com/">Weather Underground</a> weather service.
  <br><br>
  <a name="Wundergrounddefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; Wunderground &lt;api-key&gt; &lt;pws-id&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define WUweather Wunderground d123ab11bb2c3456 IBAYERNM70</code><br>
    </ul>
    <br>
  </ul>
  <br><br>
  <a name="Wundergroundset"></a>
  <b>Set</b>
  <ul>
    <li>update - refresh data</li>
  </ul>
  <br><br>
  <a name="Wundergroundattr"></a>
  <b>Attributes</b>
  <ul>
    <li>pollInterval - Set regular polling interval in seconds (defaults to 300s)</li>
    <li>wu_lang - Set data language (default=en)</li>
  </ul>
  <br><br>
</ul>

=end html

=begin html_DE

<a name="Wunderground" id="Wunderground"></a>
<h3>Wunderground</h3>
<ul>
  Eine deutsche Version der Dokumentation ist derzeit nicht vorhanden. Die englische Version ist hier zu finden:
</ul>
<ul>
  <a href='http://fhem.de/commandref.html#Wunderground'>Wunderground</a>
</ul>

=end html_DE

=cut

# $Id$
################################################################################
#    59_WUup.pm
#
#    Copyright: mahowi
#    e-mail: mahowi@gmx.net
#
#    Based on 55_weco.pm by betateilchen
#
#    This file is part of fhem.
#
#    Fhem is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 2 of the License, or
#    (at your option) any later version.
#
#    Fhem is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################

package FHEM::WUup;    ## no critic ( RequireFilenameMatchesPackage )

use strict;
use warnings;
use 5.010;
use Time::HiRes qw(gettimeofday);
use POSIX qw(strftime);
use UConv;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw( attr
            AttrVal
            CommandDeleteReading
            defs
            HttpUtils_NonblockingGet
            init_done
            InternalTimer
            IsDisabled
            Log3
            readingFnAttributes
            readingsBeginUpdate
            readingsBulkUpdate
            readingsEndUpdate
            readingsSingleUpdate
            ReadingsVal
            RemoveInternalTimer )
    );
}

#-- Export to main context with different name
GP_Export(qw( Initialize ));

################################################################################
#
# Main routines
#
################################################################################

sub Initialize {
    my ($hash) = @_;

    $hash->{DefFn}   = \&Define;
    $hash->{UndefFn} = \&Undef;
    $hash->{SetFn}   = \&Set;
    $hash->{AttrFn}  = \&Attr;
    $hash->{AttrList} =
          'disable:1,0 '
        . 'disabledForIntervals '
        . 'interval '
        . 'unit_windspeed:km/h,m/s '
        . 'unit_solarradiation:W/m²,lux '
        . 'round '
        . 'wubaromin wudailyrainin wudewptf wuhumidity wurainin '
        . 'wusoilmoisture wusoiltempf wusolarradiation wutempf wuUV '
        . 'wuwinddir wuwinddir_avg2m wuwindgustdir wuwindgustdir_10m '
        . 'wuwindgustmph wuwindgustmph_10m wuwindspdmph_avg2m wuwindspeedmph '
        . 'wuAqPM2.5 wuAqPM10 '
        . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define {
    my $hash = shift;
    my $def  = shift;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    
    ## no critic ( ProhibitComplexVersion )
    use version 0.77; our $VERSION = version->new( FHEM::Meta::Get( $hash, 'version' ) )->normal;
    ## use critic

    my @param = split( "[ \t][ \t]*", $def );

    return q{syntax: define <name> WUup <stationID> <password>}
        if ( int(@param) != 4 );

    my $name = $hash->{NAME};

    $hash->{VERSION}  = $VERSION;
    $hash->{INTERVAL} = 300;

    $hash->{helper}{stationid}    = $param[2];
    $hash->{helper}{password}     = $param[3];
    $hash->{helper}{softwaretype} = 'FHEM';
    $hash->{helper}{url} =
        'https://weatherstation.wunderground.com/weatherstation/updateweatherstation.php';
    $hash->{helper}{url_rf} =
        'https://rtupdate.wunderground.com/weatherstation/updateweatherstation.php';

    readingsSingleUpdate( $hash, 'state', 'defined', 1 );

    RemoveInternalTimer($hash);

    $init_done
        ? &stateRequestTimer($hash)
        : InternalTimer( gettimeofday(), \&stateRequestTimer, $hash, 0 );

    Log3( $name, 3, qq{WUup ($name): defined} );

    return;
}

sub Undef {
    my $hash = shift;
    RemoveInternalTimer($hash);
    return;
}

sub Set {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return qq{set $name needs at least one argument};

    return &stateRequestTimer($hash) if ( $cmd eq 'update' );
    return qq{Unknown argument $cmd, choose one of update:noArg};
}

sub Attr {
    my $cmd      = shift;
    my $name     = shift;
    my $attrName = shift;
    my $attrVal  = shift;
    my $hash     = $defs{$name};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' and $attrVal == 1 ) {
            readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            Log3( $name, 3, qq{WUup ($name) - disabled} );
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3( $name, 3, qq{WUup ($name) - enabled} );
        }
    }

    if ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            readingsSingleUpdate( $hash, 'state', 'unknown', 1 );
            Log3( $name, 3, qq{WUup ($name) - disabledForIntervals} );
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3( $name, 3, qq{WUup ($name) - enabled} );
        }
    }

    if ( $attrName eq 'interval' ) {
        if ( $cmd eq 'set' ) {
            if ( $attrVal < 3 ) {
                Log3( $name, 1,
                    qq{WUup ($name) - interval too small, please use something >= 3 (sec), default is 300 (sec).}
                );
                return
                    qq{interval too small, please use something >= 3 (sec), default is 300 (sec)};
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3( $name, 4, qq{WUup ($name) - set interval to $attrVal} );
            }
        }
        elsif ( $cmd eq 'del' ) {
            $hash->{INTERVAL} = 300;
            Log3( $name, 4, qq{WUup ($name) - set interval to default} );
        }
    }

    return;
}

sub stateRequestTimer {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( !IsDisabled($name) ) {
        readingsSingleUpdate( $hash, 'state', 'active', 1 )
            if (
            (      ReadingsVal( $name, 'state', 0 ) eq 'defined'
                or ReadingsVal( $name, 'state', 0 ) eq 'disabled'
                or ReadingsVal( $name, 'state', 0 ) eq 'Unknown'
            )
            );

        sendtowu($hash);

    }
    else {
        readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
    }

    InternalTimer( gettimeofday() + $hash->{INTERVAL},
        \&stateRequestTimer, $hash, 1 );

    Log3( $name, 5,
        qq{Sub stateRequestTimer ($name) - Request Timer is called} );

    return;
}

sub sendtowu {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my $ver    = $hash->{VERSION};
    my $url    = $hash->{INTERVAL} < 300
               ? $hash->{helper}{url_rf}
               : $hash->{helper}{url};
    $url       .= "?ID=$hash->{helper}{stationid}";
    $url       .= "&PASSWORD=$hash->{helper}{password}";
    
    my $datestring = strftime "%F+%T", gmtime;
    $datestring    =~ s{:}{%3A}gxms;

    $url .= "&dateutc=$datestring";

    my ( $data, $d, $r, $o );
    my $a                   = $attr{$name};
    my $unit_windspeed      = AttrVal( $name, 'unit_windspeed', 'km/h' );
    my $unit_solarradiation = AttrVal( $name, 'unit_solarradiation', 'lux' );
    my $rnd                 = AttrVal( $name, 'round', 4 );
    
    while ( my ( $key, $value ) = each(%$a) ) {
        next if substr( $key, 0, 2 ) ne 'wu';
        $key = substr( $key, 2, length($key) - 2 );
        ( $d, $r, $o ) = split( ":", $value );
        
        if ( defined($r) ) {
            $o //= 0;
            $value = ReadingsVal( $d, $r, 0 ) + $o;
        }

        my $mph_metric =
            $key =~ m{\w+mph [^\n]*}xms && $unit_windspeed eq 'm/s';
        my $lux_radiation =
            $key eq 'solarradiation'    && $unit_solarradiation eq 'lux';

        $value = $key =~ m{\w+f \z}xms       ? UConv::c2f( $value, $rnd )
               : $key =~ m{\w+mph [^\n]*}xms ? UConv::kph2mph( $value, $rnd )
               : $key eq 'baromin'           ? UConv::hpa2inhg( $value, $rnd )
               : $key =~ m{rainin \z}xms     ? UConv::mm2in( $value, $rnd )
               : $mph_metric                 ? UConv::kph2mph( ( UConv::mps2kph( $value, $rnd ) ), $rnd )
               : $lux_radiation              ? UConv::lux2wpsm( $value, $rnd )
               : $value;

        $data .= "&$key=$value";
    }

    readingsBeginUpdate($hash);
    
    if ( defined($data) ) {
        readingsBulkUpdate( $hash, 'data', $data );
        Log3( $name, 4, qq{WUup ($name) - data sent: $data} );
        $url .= $data;
        $url .= "&softwaretype=$hash->{helper}{softwaretype}";
        $url .= '&action=updateraw';
        
        if ( $hash->{INTERVAL} < 300 ) {
            $url .= "&realtime=1&rtfreq=$hash->{INTERVAL}";
        }
        
        my $param = {
            url      => $url,
            timeout  => 6,
            hash     => $hash,
            method   => 'GET',
            header   => "agent: FHEM-WUup/$ver\r\nUser-Agent: FHEM-WUup/$ver",
            callback => \&receive
        };

        Log3( $name, 5, qq{WUup ($name) - full URL: $url} );
        HttpUtils_NonblockingGet($param);
    }
    else {
        CommandDeleteReading( undef, "$name data" );
        CommandDeleteReading( undef, "$name response" );
        Log3( $name, 3, qq{WUup ($name) - no data} );
        readingsBulkUpdate( $hash, 'state', 'defined' );
    }
    readingsEndUpdate( $hash, 1 );

    return;
}

sub receive {
    my $param = shift;
    my $err   = shift;
    my $data  = shift;
    my $hash  = $param->{hash};
    my $name  = $hash->{NAME};

    if ( $err ne q{} ) {
        Log3( $name, 3,
            qq{WUup ($name) - error while requesting $param->{url} - $err} );
        readingsSingleUpdate( $hash, 'state',    'ERROR', undef );
        readingsSingleUpdate( $hash, 'response', $err,    undef );
    }
    elsif ( $data ne q{} ) {
        Log3( $name, 4, qq{WUup ($name) - server response: $data} );
        readingsSingleUpdate( $hash, 'state',    'active', undef );
        readingsSingleUpdate( $hash, 'response', $data,    undef );
    }
    return;
}

1;

################################################################################
#
# Documentation
#
################################################################################

=pod

=encoding utf8

=item helper
=item summary sends weather data to Weather Underground
=item summary_DE sendet Wetterdaten zu Weather Underground

=begin html

<a name="WUup" id="WUup"></a>
<h3>WUup</h3>
<ul>

    <a name="WUupdefine" id="WUupdefine"></a>
    <b>Define</b>
    <ul>

        <br/>
        <code>define &lt;name&gt; WUup &lt;stationId&gt; &lt;password&gt;</code>
        <br/><br/>
        This module provides connection to 
        <a href="https://www.wunderground.com">www.wunderground.com</a></br>
        to send data from your own weather station.<br/>

    </ul>
    <br/><br/>

    <a name="WUupset" id="WUupset"></a>
    <b>Set-Commands</b><br/>
    <ul>
        <li><b>update</b> - send data to Weather Underground</li>
    </ul>
    <br/><br/>

    <a name="WUupget" id="WUupget"></a>
    <b>Get-Commands</b><br/>
    <ul>
        <br/>
        - not implemented -<br/>
    </ul>
    <br/><br/>

    <a name="WUupattr" id="WUupattr"></a>
    <b>Attributes</b><br/><br/>
    <ul>
        <li><b><a href="#readingFnAttributes">readingFnAttributes</a></b></li>
        <li><b>interval</b> - Interval (seconds) to send data to 
            www.wunderground.com. 
            Will be adjusted to 300 (which is the default) if set to a value lower than 3.<br />
            If lower than 300, RapidFire mode will be used.</li>
        <li><b>disable</b> - disables the module</li>
        <li><b><a href="#disabledForIntervals">disabledForIntervals</a></b></li>
        <li><b>unit_windspeed</b> - change the units of your windspeed readings (m/s or km/h)</li>
        <li><b>unit_solarradiation</b> - change the units of your solarradiation readings (lux or W/m²)</li>
        <li><b>round</b> - round values to this number of decimals for calculation (default 4)</li>
        <li><b>wu....</b> - Attribute name corresponding to 
<a href="https://feedback.weather.com/customer/en/portal/articles/2924682-pws-upload-protocol?b_id=17298">parameter name from api.</a> 
            Each of these attributes contains information about weather data to be sent 
            in format <code>sensorName:readingName</code><br/>
            Example: <code>attr WUup wutempf outside:temperature</code> will 
            define the attribute wutempf and <br/>
            reading "temperature" from device "outside" will be sent to 
            network as parameter "tempf" (which indicates current temperature)
            <br/>
            Units get converted to angloamerican system automatically 
            (°C -> °F; km/h(m/s) -> mph; mm -> in; hPa -> inHg)<br/><br/>
        <u>The following information is supported:</u>
        <ul>
            <li>winddir - instantaneous wind direction (0-360) [°]</li>
            <li>windspeedmph - instantaneous wind speed ·[mph]</li>
            <li>windgustmph - current wind gust, using software specific time period [mph]</li>
            <li>windgustdir - current wind direction, using software specific time period [°]</li>
            <li>windspdmph_avg2m  - 2 minute average wind speed [mph]</li>
            <li>winddir_avg2m - 2 minute average wind direction [°]</li>
            <li>windgustmph_10m - past 10 minutes wind gust [mph]</li>
            <li>windgustdir_10m - past 10 minutes wind gust direction [°]</li>
            <li>humidity - outdoor humidity (0-100) [%]</li>
            <li>dewptf- outdoor dewpoint [°F]</li>
            <li>tempf - outdoor temperature [°F]</li>
            <li>rainin - rain over the past hour -- the accumulated rainfall in the past 60 min [in]</li>
            <li>dailyrainin - rain so far today in local time [in]</li>
            <li>baromin - barometric pressure [inHg]</li>
            <li>soiltempf - soil temperature [°F]</li>
            <li>soilmoisture - soil moisture [%]</li>
            <li>solarradiation - solar radiation[W/m²]</li>
            <li>UV - [index]</li>
            <li>AqPM2.5 - PM2.5 mass [µg/m³]</li>
            <li>AqPM10 - PM10 mass [µg/m³]</li>
        </ul>
        </li>
    </ul>
    <br/><br/>

    <b>Readings/Events:</b>
    <br/><br/>
    <ul>
        <li><b>data</b> - data string transmitted to www.wunderground.com</li>
        <li><b>response</b> - response string received from server</li>
    </ul>
    <br/><br/>

    <b>Notes</b><br/><br/>
    <ul>
        <li>Find complete api description 
<a href="https://feedback.weather.com/customer/en/portal/articles/2924682-pws-upload-protocol?b_id=17298">here</a></li>
        <li>Have fun!</li><br/>
    </ul>

</ul>

=end html

=begin html_DE

<a name="WUup" id="WUup"></a>
<h3>WUup</h3>
<ul>

    <a name="WUupdefine" id="WUupdefine"></a>
    <b>Define</b>
    <ul>

        <br/>
        <code>define &lt;name&gt; WUup &lt;stationId&gt; &lt;password&gt;</code>
        <br/><br/>
        Dieses Modul stellt eine Verbindung zu <a href="https://www.wunderground.com">www.wunderground.com</a></br>
        her, um Daten einer eigenen Wetterstation zu versenden..<br/>

    </ul>
    <br/><br/>

    <a name="WUupset" id="WUupset"></a>
    <b>Set-Befehle</b><br/>
    <ul>
        <li><b>update</b> - sende Daten an Weather Underground</li>
    </ul>
    <br/><br/>

    <a name="WUupget" id="WUupget"></a>
    <b>Get-Befehle</b><br/>
    <ul>
        <br/>
        - keine -<br/>
    </ul>
    <br/><br/>

    <a name="WUupattr" id="WUupattr"></a>
    <b>Attribute</b><br/><br/>
    <ul>
        <li><b><a href="#readingFnAttributes">readingFnAttributes</a></b></li>
        <li><b>interval</b> - Sendeinterval in Sekunden. Wird auf 300 (Default-Wert)
        eingestellt, wenn der Wert kleiner als 3 ist.<br />
        Wenn der Wert kleiner als 300 ist, wird der RapidFire Modus verwendet.</li>
        <li><b>disable</b> - deaktiviert das Modul</li>
        <li><b><a href="#disabledForIntervals">disabledForIntervals</a></b></li>
        <li><b>unit_windspeed</b> - gibt die Einheit der Readings für die
        Windgeschwindigkeiten an (m/s oder km/h)</li>
        <li><b>unit_solarradiation</b> - gibt die Einheit der Readings für die
        Sonneneinstrahlung an (lux oder W/m²)</li>
        <li><b>round</b> - Anzahl der Nachkommastellen zur Berechnung (Standard 4)</li>
        <li><b>wu....</b> - Attributname entsprechend dem 
<a href="https://feedback.weather.com/customer/en/portal/articles/2924682-pws-upload-protocol?b_id=17298">Parameternamen aus der API.</a><br />
        Jedes dieser Attribute enthält Informationen über zu sendende Wetterdaten
        im Format <code>sensorName:readingName</code>.<br/>
        Beispiel: <code>attr WUup wutempf outside:temperature</code> definiert
        das Attribut wutempf und sendet das Reading "temperature" vom Gerät "outside" als Parameter "tempf" 
        (welches die aktuelle Temperatur angibt).
        <br />
        Einheiten werden automatisch ins anglo-amerikanische System umgerechnet. 
        (°C -> °;F; km/h(m/s) -> mph; mm -> in; hPa -> inHg)<br/><br/>
        <u>Unterstützte Angaben</u>
        <ul>
            <li>winddir - momentane Windrichtung (0-360) [°]</li>
            <li>windspeedmph - momentane Windgeschwindigkeit [mph]</li>
            <li>windgustmph - aktuelle Böe, mit Software-spezifischem Zeitraum [mph]</li>
            <li>windgustdir - aktuelle Böenrichtung, mit Software-spezifischer Zeitraum [°]</li>
            <li>windspdmph_avg2m - durchschnittliche Windgeschwindigkeit innerhalb 2 Minuten [mph]</li>
            <li>winddir_avg2m - durchschnittliche Windrichtung innerhalb 2 Minuten [°]</li>
            <li>windgustmph_10m - Böen der vergangenen 10 Minuten [mph]</li>
            <li>windgustdir_10m - Richtung der Böen der letzten 10 Minuten [°]</li>
            <li>humidity - Luftfeuchtigkeit im Freien (0-100) [%]</li>
            <li>dewptf- Taupunkt im Freien [°F]</li>
            <li>tempf - Außentemperatur [°F]</li>
            <li>rainin - Regen in der vergangenen Stunde [in]</li>
            <li>dailyrainin - Regenmenge bisher heute [in]</li>
            <li>baromin - barometrischer Druck [inHg]</li>
            <li>soiltempf - Bodentemperatur [°F]</li>
            <li>soilmoisture - Bodenfeuchtigkeit [%]</li>
            <li>solarradiation - Sonneneinstrahlung [W/m²]</li>
            <li>UV - [Index]</li>
            <li>AqPM2.5 - Feinstaub PM2,5 [µg/m³]</li>
            <li>AqPM10 - Feinstaub PM10 [µg/m³]</li>
        </ul>
        </li>
    </ul>
    <br/><br/>

    <b>Readings/Events:</b>
    <br/><br/>
    <ul>
        <li><b>data</b> - Daten, die zu www.wunderground.com gesendet werden</li>
        <li><b>response</b> - Antwort, die vom Server empfangen wird</li>
    </ul>
    <br/><br/>

    <b>Notizen</b><br/><br/>
    <ul>
        <li>Die komplette API-Beschreibung findet sich 
<a href="https://feedback.weather.com/customer/en/portal/articles/2924682-pws-upload-protocol?b_id=17298">hier</a></li>
        <li>Viel Spaß!</li><br/>
    </ul>

</ul>

=end html_DE

=for :application/json;q=META.json 59_WUup.pm
{
  "abstract": "sends weather data to Weather Underground",
  "description": "This module provides connection to Weather Underground to send data from your own weather station.",
  "x_lang": {
    "de": {
      "abstract": "sendet Wetterdaten zu Weather Underground",
      "description": "Dieses Modul stellt eine Verbindung zu Weather Underground her, um Daten einer eigenen Wetterstation zu versenden"
    }
  },
  "license": [
    "gpl_2"
  ],
  "version": "v0.10.1",
  "release_status": "stable",
  "author": [
    "Manfred Winter <mahowi@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "mahowi"
  ],
  "x_fhem_maintainer_github": [
    "mahowi"
  ],
  "keywords": [
    "fhem-mod",
    "wunderground",
    "pws",
    "weather"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 0,
        "FHEM::Meta": 0,
        "UConv": 0,
        "POSIX": 0,
        "Time::HiRes": 0,
        "perl": 5.010
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "x_wiki" : {
      "title" : "Wetter und Wettervorhersagen - Eigene Wetterdaten hochladen",
      "web" : "https://wiki.fhem.de/wiki/Wetter_und_Wettervorhersagen#Eigene_Wetterdaten_hochladen"
     },
    "repository": {
      "type": "git",
      "url": "https://github.com/fhem/WUup.git",
      "web": "https://github.com/mahowi/WUup/blob/master/FHEM/59_WUup.pm",
      "x_branch": "master",
      "x_filepath": "FHEM/",
      "x_raw": "https://raw.githubusercontent.com/mahowi/WUup/master/FHEM/59_WUup.pm"
     }
  },
  "x_support_status": "supported"
}
=end :application/json;q=META.json

=cut

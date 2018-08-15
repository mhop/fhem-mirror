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

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use HttpUtils;
use UConv;

my $version = "0.9.9";

# Declare functions
sub WUup_Initialize($);
sub WUup_Define($$$);
sub WUup_Undef($$);
sub WUup_Set($@);
sub WUup_Attr(@);
sub WUup_stateRequestTimer($);
sub WUup_send($);
sub WUup_receive($);

################################################################################
#
# Main routines
#
################################################################################

sub WUup_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}   = "WUup_Define";
    $hash->{UndefFn} = "WUup_Undef";
    $hash->{SetFn}   = "WUup_Set";
    $hash->{AttrFn}  = "WUup_Attr";
    $hash->{AttrList} =
        "disable:1 "
      . "disabledForIntervals "
      . "interval "
      . "unit_windspeed:km/h,m/s "
      . "unit_solarradiation:W/m²,lux "
      . "round "
      . "wubaromin wudailyrainin wudewptf wuhumidity wurainin wusoilmoisture "
      . "wusoiltempf wusolarradiation wutempf wuUV wuwinddir wuwinddir_avg2m "
      . "wuwindgustdir wuwindgustdir_10m wuwindgustmph wuwindgustmph_10m "
      . "wuwindspdmph_avg2m wuwindspeedmph wuAqPM2.5 wuAqPM10 "
      . $readingFnAttributes;
    $hash->{VERSION} = $version;
}

sub WUup_Define($$$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return "syntax: define <name> WUup <stationID> <password>"
      if ( int(@a) != 4 );

    my $name = $hash->{NAME};

    $hash->{VERSION}  = $version;
    $hash->{INTERVAL} = 300;

    $hash->{helper}{stationid}    = $a[2];
    $hash->{helper}{password}     = $a[3];
    $hash->{helper}{softwaretype} = 'FHEM';
    $hash->{helper}{url} =
"https://weatherstation.wunderground.com/weatherstation/updateweatherstation.php";
    $hash->{helper}{url_rf} =
"https://rtupdate.wunderground.com/weatherstation/updateweatherstation.php";

    readingsSingleUpdate( $hash, "state", "defined", 1 );

    $attr{$name}{room} = "Weather" if ( !defined( $attr{$name}{room} ) );
    $attr{$name}{unit_windspeed} = "km/h"
      if ( !defined( $attr{$name}{unit_windspeed} ) );
    $attr{$name}{unit_solarradiation} = "lux"
      if ( !defined( $attr{$name}{unit_solarradiation} ) );
    $attr{$name}{round} = 4 if ( !defined( $attr{$name}{round} ) );

    RemoveInternalTimer($hash);

    if ($init_done) {
        WUup_stateRequestTimer($hash);
    }
    else {
        InternalTimer( gettimeofday(), "WUup_stateRequestTimer", $hash, 0 );
    }

    Log3 $name, 3, "WUup ($name): defined";

    return undef;
}

sub WUup_Undef($$) {
    my ( $hash, $arg ) = @_;
    RemoveInternalTimer($hash);
    return undef;
}

sub WUup_Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    return "\"set $name\" needs at least one argument" unless ( defined($cmd) );

    if ( $cmd eq "update" ) {
        WUup_stateRequestTimer($hash);
    }
    else {
        return "Unknown argument $cmd, choose one of update:noArg";
    }
}

sub WUup_Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "WUup ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate( $hash, "state", "active", 1 );
            Log3 $name, 3, "WUup ($name) - enabled";
        }
    }

    if ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            readingsSingleUpdate( $hash, "state", "unknown", 1 );
            Log3 $name, 3, "WUup ($name) - disabledForIntervals";
        }

        elsif ( $cmd eq "del" ) {
            readingsSingleUpdate( $hash, "state", "active", 1 );
            Log3 $name, 3, "WUup ($name) - enabled";
        }
    }

    if ( $attrName eq "interval" ) {
        if ( $cmd eq "set" ) {
            if ( $attrVal < 3 ) {
                Log3 $name, 1,
"WUup ($name) - interval too small, please use something >= 3 (sec), default is 300 (sec).";
                return
"interval too small, please use something >= 3 (sec), default is 300 (sec)";
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 4, "WUup ($name) - set interval to $attrVal";
            }
        }

        elsif ( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 4, "WUup ($name) - set interval to default";
        }
    }

    return undef;
}

sub WUup_stateRequestTimer($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if ( !IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "active", 1 )
          if (
            (
                   ReadingsVal( $name, "state", 0 ) eq "defined"
                or ReadingsVal( $name, "state", 0 ) eq "disabled"
                or ReadingsVal( $name, "state", 0 ) eq "Unknown"
            )
          );

        WUup_send($hash);

    }
    else {
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }

    InternalTimer( gettimeofday() + $hash->{INTERVAL},
        "WUup_stateRequestTimer", $hash, 1 );

    Log3 $name, 5,
      "Sub WUup_stateRequestTimer ($name) - Request Timer is called";
}

sub WUup_send($) {
    my ($hash)  = @_;
    my $name    = $hash->{NAME};
    my $version = $hash->{VERSION};
    my $url     = "";
    if ( $hash->{INTERVAL} < 300 ) {
        $url = $hash->{helper}{url_rf};
    }
    else {
        $url = $hash->{helper}{url};
    }
    $url .= "?ID=" . $hash->{helper}{stationid};
    $url .= "&PASSWORD=" . $hash->{helper}{password};
    my $datestring = strftime "%F+%T", gmtime;
    $datestring =~ s/:/%3A/g;
    $url .= "&dateutc=" . $datestring;

    $attr{$name}{unit_windspeed} = "km/h"
      if ( !defined( $attr{$name}{unit_windspeed} ) );

    $attr{$name}{unit_solarradiation} = "lux"
      if ( !defined( $attr{$name}{unit_solarradiation} ) );

    $attr{$name}{round} = 4 if ( !defined( $attr{$name}{round} ) );

    my ( $data, $d, $r, $o );
    my $a   = $attr{$name};
    my $rnd = $attr{$name}{round};
    while ( my ( $key, $value ) = each(%$a) ) {
        next if substr( $key, 0, 2 ) ne 'wu';
        $key = substr( $key, 2, length($key) - 2 );
        ( $d, $r, $o ) = split( ":", $value );
        if ( defined($r) ) {
            $o = ( defined($o) ) ? $o : 0;
            $value = ReadingsVal( $d, $r, 0 ) + $o;
        }
        if ( $key =~ /\w+f$/ ) {
            $value = UConv::c2f( $value, $rnd );
        }
        elsif ( $key =~ /\w+mph.*/ ) {

            if ( $attr{$name}{unit_windspeed} eq "m/s" ) {
                Log3 $name, 5, "WUup ($name) - windspeed unit is m/s";
                $value =
                  UConv::kph2mph( ( UConv::mps2kph( $value, $rnd ) ), $rnd );
            }
            else {
                Log3 $name, 5, "WUup ($name) - windspeed unit is km/h";
                $value = UConv::kph2mph( $value, $rnd );
            }
        }
        elsif ( $key eq "baromin" ) {
            $value = UConv::hpa2inhg( $value, $rnd );
        }
        elsif ( $key =~ /.*rainin$/ ) {
            $value = UConv::mm2in( $value, $rnd );
        }
        elsif ( $key eq "solarradiation" ) {

            if ( $attr{$name}{unit_solarradiation} eq "lux" ) {
                Log3 $name, 5, "WUup ($name) - solarradiation unit is lux";
                $value = ( $value / 126.7 );
            }
            else {
                Log3 $name, 5, "WUup ($name) - solarradiation unit is W/m²";
            }
        }
        $data .= "&$key=$value";
    }

    readingsBeginUpdate($hash);
    if ( defined($data) ) {
        readingsBulkUpdate( $hash, "data", $data );
        Log3 $name, 4, "WUup ($name) - data sent: $data";
        $url .= $data;
        $url .= "&softwaretype=" . $hash->{helper}{softwaretype};
        $url .= "&action=updateraw";
        if ( $hash->{INTERVAL} < 300 ) {
            $url .= "&realtime=1&rtfreq=" . $hash->{INTERVAL};
        }
        my $param = {
            url     => $url,
            timeout => 6,
            hash    => $hash,
            method  => "GET",
            header =>
              "agent: FHEM-WUup/$version\r\nUser-Agent: FHEM-WUup/$version",
            callback => \&WUup_receive
        };

        Log3 $name, 5, "WUup ($name) - full URL: $url";
        HttpUtils_NonblockingGet($param);

        #        my $response = GetFileFromURL($url);
        #        readingsBulkUpdate( $hash, "response", $response );
        #        Log3 $name, 4, "WUup ($name) - server response: $response";
    }
    else {
        CommandDeleteReading( undef, "$name data" );
        CommandDeleteReading( undef, "$name response" );
        Log3 $name, 3, "WUup ($name) - no data";
        readingsBulkUpdate( $hash, "state", "defined" );

    }
    readingsEndUpdate( $hash, 1 );

    return;
}

sub WUup_receive($) {
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( $err ne "" ) {
        Log3 $name, 3,
          "WUup ($name) - error while requesting " . $param->{url} . " - $err";
        readingsSingleUpdate( $hash, "state",    "ERROR", undef );
        readingsSingleUpdate( $hash, "response", $err,    undef );
    }
    elsif ( $data ne "" ) {
        Log3 $name, 4, "WUup ($name) - server response: $data";
        readingsSingleUpdate( $hash, "state",    "active", undef );
        readingsSingleUpdate( $hash, "response", $data,    undef );
    }
}

1;

################################################################################
#
# Documentation
#
################################################################################
#
# Changelog:
#
# 2017-01-23 initial release
# 2017-02-10 added german docu
# 2017-02-22 fixed bug when module cannot get reenabled after disabling
#            added disabledForIntervals
#            changed attribute WUInterval to interval
#            default interval 300
# 2017-02-23 added attribute unit_windspeed
#            converted units rounded to 4 decimal places
# 2017-03-16 implemented non-blocking mode
# 2017-08-16 integrated RapidFire mode (thanks to Scooty66)
# 2017-10-10 added windspdmph_avg2m, winddir_avg2m, windgustmph_10m,
#            windgustdir_10m (thanks to Aeroschmelz for reminding me)
#            timeout raised to 6s, fixed state error (thanks to mumpitzstuff)
# 2017-10-16 fixed attributes
# 2017-10-19 added set-command "update"
# 2018-03-19 solarradiation calculated from lux to W/m² (thanks to dieter114)
# 2018-04-10 added attribute round
# 2018-04-13 added AqPM2.5 and AqPM10
# 2018-08-15 added attribute unit_solarradiation
#
################################################################################

=pod
=item helper
=item summary sends weather data to Weather Underground
=item summary_DE sendet Wetterdaten zu Weather Underground
=begin html

<a name="WUup"></a>
<h3>WUup</h3>
<ul>

    <a name="WUupdefine"></a>
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

    <a name="WUupset"></a>
    <b>Set-Commands</b><br/>
    <ul>
        <li><b>update</b> - send data to Weather Underground</li>
    </ul>
    <br/><br/>

    <a name="WUupget"></a>
    <b>Get-Commands</b><br/>
    <ul>
        <br/>
        - not implemented -<br/>
    </ul>
    <br/><br/>

    <a name="WUupattr"></a>
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
        <li><b>unit_solarradiation</b> - change the units of your solarradiation readings (lux or W/m&sup2;)</li>
        <li><b>round</b> - round values to this number of decimals for calculation (default 4)</li>
        <li><b>wu....</b> - Attribute name corresponding to 
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">parameter name from api.</a> 
            Each of these attributes contains information about weather data to be sent 
            in format <code>sensorName:readingName</code><br/>
            Example: <code>attr WUup wutempf outside:temperature</code> will 
            define the attribute wutempf and <br/>
            reading "temperature" from device "outside" will be sent to 
            network as parameter "tempf" (which indicates current temperature)
            <br/>
            Units get converted to angloamerican system automatically 
            (&deg;C -> &deg;F; km/h(m/s) -> mph; mm -> in; hPa -> inHg)<br/><br/>
        <u>The following information is supported:</u>
        <ul>
            <li>winddir - instantaneous wind direction (0-360) [&deg;]</li>
            <li>windspeedmph - instantaneous wind speed ·[mph]</li>
            <li>windgustmph - current wind gust, using software specific time period [mph]</li>
            <li>windgustdir - current wind direction, using software specific time period [&deg;]</li>
            <li>windspdmph_avg2m  - 2 minute average wind speed [mph]</li>
            <li>winddir_avg2m - 2 minute average wind direction [&deg;]</li>
            <li>windgustmph_10m - past 10 minutes wind gust [mph]</li>
            <li>windgustdir_10m - past 10 minutes wind gust direction [&deg;]</li>
            <li>humidity - outdoor humidity (0-100) [&#37;]</li>
            <li>dewptf- outdoor dewpoint [F]</li>
            <li>tempf - outdoor temperature [F]</li>
            <li>rainin - rain over the past hour -- the accumulated rainfall in the past 60 min [in]</li>
            <li>dailyrainin - rain so far today in local time [in]</li>
            <li>baromin - barometric pressure [inHg]</li>
            <li>soiltempf - soil temperature [F]</li>
            <li>soilmoisture - soil moisture [&#37;]</li>
            <li>solarradiation - solar radiation[W/m&sup2;]</li>
            <li>UV - [index]</li>
            <li>AqPM2.5 - PM2.5 mass [&micro;g/m&sup3;]</li>
            <li>AqPM10 - PM10 mass [&micro;g/m&sup3;]</li>
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
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">here</a></li>
        <li>Have fun!</li><br/>
    </ul>

</ul>

=end html
=begin html_DE

<a name="WUup"></a>
<h3>WUup</h3>
<ul>

    <a name="WUupdefine"></a>
    <b>Define</b>
    <ul>

        <br/>
        <code>define &lt;name&gt; WUup &lt;stationId&gt; &lt;password&gt;</code>
        <br/><br/>
        Dieses Modul stellt eine Verbindung zu <a href="https://www.wunderground.com">www.wunderground.com</a></br>
        her, um Daten einer eigenen Wetterstation zu versenden..<br/>

    </ul>
    <br/><br/>

    <a name="WUupset"></a>
    <b>Set-Befehle</b><br/>
    <ul>
        <li><b>update</b> - sende Daten an Weather Underground</li>
    </ul>
    <br/><br/>

    <a name="WUupget"></a>
    <b>Get-Befehle</b><br/>
    <ul>
        <br/>
        - keine -<br/>
    </ul>
    <br/><br/>

    <a name="WUupattr"></a>
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
        Sonneneinstrahlung an (lux oder W/m&sup2;)</li>
        <li><b>round</b> - Anzahl der Nachkommastellen zur Berechnung (Standard 4)</li>
        <li><b>wu....</b> - Attributname entsprechend dem 
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">Parameternamen aus der API.</a><br />
        Jedes dieser Attribute enth&auml;lt Informationen &uuml;ber zu sendende Wetterdaten
        im Format <code>sensorName:readingName</code>.<br/>
        Beispiel: <code>attr WUup wutempf outside:temperature</code> definiert
        das Attribut wutempf und sendet das Reading "temperature" vom Ger&auml;t "outside" als Parameter "tempf" 
        (welches die aktuelle Temperatur angibt).
        <br />
        Einheiten werden automatisch ins anglo-amerikanische System umgerechnet. 
        (&deg;C -> &deg;F; km/h(m/s) -> mph; mm -> in; hPa -> inHg)<br/><br/>
        <u>Unterst&uuml;tzte Angaben</u>
        <ul>
            <li>winddir - momentane Windrichtung (0-360) [&deg;]</li>
            <li>windspeedmph - momentane Windgeschwindigkeit [mph]</li>
            <li>windgustmph - aktuelle B&ouml;e, mit Software-spezifischem Zeitraum [mph]</li>
            <li>windgustdir - aktuelle B&ouml;enrichtung, mit Software-spezifischer Zeitraum [&deg;]</li>
            <li>windspdmph_avg2m - durchschnittliche Windgeschwindigkeit innerhalb 2 Minuten [mph]</li>
            <li>winddir_avg2m - durchschnittliche Windrichtung innerhalb 2 Minuten [&deg;]</li>
            <li>windgustmph_10m - B&ouml;en der vergangenen 10 Minuten [mph]</li>
            <li>windgustdir_10m - Richtung der B&ouml;en der letzten 10 Minuten [&deg;]</li>
            <li>humidity - Luftfeuchtigkeit im Freien (0-100) [&#37;]</li>
            <li>dewptf- Taupunkt im Freien [F]</li>
            <li>tempf - Au&szlig;entemperatur [F]</li>
            <li>rainin - Regen in der vergangenen Stunde [in]</li>
            <li>dailyrainin - Regenmenge bisher heute [in]</li>
            <li>baromin - barometrischer Druck [inHg]</li>
            <li>soiltempf - Bodentemperatur [F]</li>
            <li>soilmoisture - Bodenfeuchtigkeit [&#37;]</li>
            <li>solarradiation - Sonneneinstrahlung [W/m&sup2;]</li>
            <li>UV - [Index]</li>
            <li>AqPM2.5 - Feinstaub PM2,5 [&micro;g/m&sup3;]</li>
            <li>AqPM10 - Feinstaub PM10 [&micro;g/m&sup3;]</li>
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
<a href="http://wiki.wunderground.com/index.php/PWS_-_Upload_Protocol">hier</a></li>
        <li>Viel Spa&szlig;!</li><br/>
    </ul>

</ul>

=end html_DE
=cut

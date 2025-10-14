# $Id$
##############################################################################
#
#     59_Weather.pm
#     (c) 2009-2025 Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#       Contributors:
#         - Marko Oldenburg (CoolTux)
#         - Lippie
#         - stefanru (wundergroundAPI)
#
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

package FHEM::Weather;

use strict;
use warnings;

require FHEM::Core::Weather;

use FHEM::Meta;

sub ::Weather_Initialize { goto &Initialize }

sub Initialize {
    my $hash = shift;

    $hash->{DefFn}   = \&FHEM::Core::Weather::Define;
    $hash->{UndefFn} = \&FHEM::Core::Weather::Undef;
    $hash->{GetFn}   = \&FHEM::Core::Weather::Get;
    $hash->{SetFn}   = \&FHEM::Core::Weather::Set;
    $hash->{AttrFn}  = \&FHEM::Core::Weather::Attr;
    $hash->{AttrList} =
        'disable:0,1 '
      . 'forecast:multiple-strict,hourly,daily '
      . 'forecastLimit '
      . 'alerts:0,1 '
      . $::readingFnAttributes;
    $hash->{NotifyFn}    = \&FHEM::Core::Weather::Notify;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;

__END__


=pod
=item device
=item summary provides current weather condition and forecast
=item summary_DE stellt Wetterbericht und -vorhersage bereit
=begin html

<a id="Weather"></a>
<h3>Weather</h3>
<ul>
  Note: you need the JSON perl module. Use <code>apt-get install
  libjson-perl</code> on Debian and derivatives.<p></p>

  The Weather module works with various weather APIs:
  <ul>
    <li>OpenWeatherMap (<a href="https://openweathermap.org/">web site)</a></li>
    <li>Wunderground (<a href="https://www.wunderground.com/member/api-keys">web site)</a></li>
  </ul>
  <br>
  Such a virtual Weather device periodically gathers current and forecast
  weather conditions from the chosen weather API.<br><br>

  <a id="Weather-define"></a>
  <h4>Define</h4><br><br>
    <ul>
      <code>define &lt;name&gt; Weather [API=&lt;API&gt;[,&lt;apioptions&gt;]] [apikey=&lt;apikey&gt;]
       [location=&lt;location&gt;] [interval=&lt;interval&gt;] [lang=&lt;lang&gt;]</code><br><br>


       The parameters have the following meanings:<br>

       <table>
       <tr><td><code>API</code></td><td>name of the weather API, e.g. <code>OpenWeatherMapAPI</code></td></tr>
       <tr><td><code>apioptions</code></td><td>indivual options for the chosen API</td></tr>
       <tr><td><code>apikey</code></td><td>key for the chosen API</td></tr>
       <tr><td><code>location</code></td><td>location for the weather forecast;
         e.g. coordinates, a town name or an ID, depending on the chosen API</td></tr>
       <tr><td><code>interval</code></td><td>duration in seconds between updates</td></tr>
       <tr><td><code>lang</code></td><td>language of the forecast: <code>de</code>,
         <code>en</code>, <code>pl</code>, <code>fr</code>, <code>it</code> or <code>nl</code></td></tr>
       </table>
       <p></p>

    A very simple definition is:<br><br>
    <code>define &lt;name&gt; Weather apikey=&lt;OpenWeatherMapAPISecretKey&gt;</code><br><br>
    This uses the Dark Sky API with an individual key that you need to
    retrieve from the Dark Sky web site.<p></p>

    Examples:
    <pre>
      define Forecast Weather apikey=987498ghjgf864
      define MyWeather Weather API=OpenWeatherMapAPI,cachemaxage:600 apikey=09878945fdskv876 location=52.4545,13.4545 interval=3600 lang=de
      define <name> Weather API=wundergroundAPI,stationId:IHAUIDELB111 apikey=ed64ccc80f004556a4e3456567800b6324a
    </pre>


    API-specific documentation follows.<p></p>

        <h4>OpenWeatherMap</h4><p></p>

        <table>
        <tr><td>API</td><td><code>OpenWeatherMapAPI</code></td></tr>
        <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code><br>duration
          in seconds to retrieve the forecast from the cache instead from the API</td>
          <td><code>version:&lt;version&gt;</code> API version which should be used.
          2.5 by default, 3.0 is still possible but only with an additional subscription</td>
          <td><code>endpoint:onecall</code> only to test whether the API key which not
          officially for onecall is not supported yet onecall via API version 2.5. IMPORTANT!!!
          apioption version must not be set to 3.0</td></tr>
        <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code><br>
          geographic coordinates in degrees of the location for which the
          weather is forecast; if missing, the values of the attributes
          of the <code>global</code> device are taken, if these exist.</td></tr>
        </table>
        <p></p>
        
        <h4>Wunderground</h4><p></p>

        <table>
        <tr><td>API</td><td><code>wundergroundAPI</code></td></tr>
        <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code><br>duration
          in seconds to retrieve the forecast from the cache instead from the API<br><code>stationId:ID-Num</code>
      <br>Station ID of the station to be read.</td></tr>
        <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code><br>
          geographic coordinates in degrees of the location for which the
          weather is forecast; if missing, the values of the attributes
          of the <code>global</code> device are taken, if these exist.</td></tr>
        </table>
        <p></p>

    The module provides four additional functions <code>WeatherAsHtml</code>,
    <code>WeatherAsHtmlV</code>, <code>WeatherAsHtmlH</code> and
    <code>WeatherAsHtmlD</code>. The former two functions are identical:
    they return the HTML code for a vertically arranged weather forecast.
    The third function returns the HTML code for a horizontally arranged
    weather forecast. The latter function dynamically picks the orientation
    depending on wether a smallscreen style is set (vertical layout) or not
    (horizontal layout). Each version accepts an additional paramter
    to limit the numer of icons to display.<br><br>
    Example:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WeatherAsHtmlH("MyWeather","h",10) }
    </pre>


  </ul>
  <br>

  <a id="Weather-set"></a>
  <h4>Set</h4>
  <ul>
    <a id="Weather-set-update"></a>
    <li>
      <i>set &lt;name&gt; update</i><br><br>

      Forces the retrieval of the weather data. The next automatic retrieval is scheduled to occur
      <code>interval</code> seconds later.
    </li>
    <a id="Weather-set-newLocation"></a>
    <li>
      <i>set &lt;name&gt; newLocation latitude,longitude</i><br><br>
      
      set a new temporary location.
      the value pair Latitude Longitude is separated by a comma.
      if no value is entered (empty value), the location detected by definition is automatically taken.<br><br>
    </li>
  </ul>
  <br>

  <a id="Weather-get"></a>
  <h4>Get</h4>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>

    Valid readings and their meaning (? can be one of 1, 2, 3, 4, 5 and stands
    for today, tomorrow, etc.):<br>
    <table>
    <a id="Weather-get-.license"></a>
    <tr><td>.license</td><td>license of the API provider, if available</td></tr>
    <a id="Weather-get-city"></a>
    <tr><td>city</td><td>name of town returned for location</td></tr>
    <a id="Weather-get-code"></a>
    <tr><td>code</td><td>current condition code</td></tr>
    <a id="Weather-get-condition"></a>
    <tr><td>condition</td><td>current condition</td></tr>
    <a id="Weather-get-current_date_time"></a>
    <tr><td>current_date_time</td><td>last update of forecast on server</td></tr>
     <a id="Weather-get-fc?_code"></a>
    <tr><td>fc?_code</td><td>forecast condition code</td></tr>
    <a id="Weather-get-fc?_condition"></a>
    <tr><td>fc?_condition</td><td>forecast condition</td></tr>
    <a id="Weather-get-fc?_day_of_week"></a>
    <tr><td>fc?_day_of_week</td><td>day of week for day +?</td></tr>
    <a id="Weather-get-fc?_high_c"></a>
    <tr><td>fc?_high_c</td><td>forecasted daily high in degrees centigrade</td></tr>
    <a id="Weather-get-fc?_icon"></a>
    <tr><td>fc?_icon</td><td>forecast icon</td></tr>
    <a id="Weather-get-fc?_low_c"></a>
    <tr><td>fc?_low_c</td><td>forecasted daily low in degrees centigrade</td></tr>
    <a id="Weather-get-humidity"></a>
    <tr><td>humidity</td><td>current humidity in %</td></tr>
    <a id="Weather-get-icon"></a>
    <tr><td>icon</td><td>relative path for current icon</td></tr>
    <a id="Weather-get-pressure"></a>
    <tr><td>pressure</td><td>air pressure in hPa</td></tr>
    <a id="Weather-get-pressure_trend"></a>
    <tr><td>pressure_trend</td><td>air pressure trend (0= steady, 1= rising, 2= falling)</td></tr>
    <a id="Weather-get-pressure_trend_txt"></a>
    <tr><td>pressure_trend_txt</td><td>textual representation of air pressure trend</td></tr>
    <a id="Weather-get-pressure_trend_sym"></a>
    <tr><td>pressure_trend_sym</td><td>symbolic representation of air pressure trend</td></tr>
    <a id="Weather-get-temperature"></a>
    <tr><td>temperature</td><td>current temperature in degrees centigrade</td></tr>
    <a id="Weather-get-temp_c"></a>
    <tr><td>temp_c</td><td>current temperature in degrees centigrade</td></tr>
    <a id="Weather-get-temp_f"></a>
    <tr><td>temp_f</td><td>current temperature in degrees Fahrenheit</td></tr>
    <a id="Weather-get-visibility"></a>
    <tr><td>visibility</td><td>visibility in km</td></tr>
    <a id="Weather-get-wind"></a>
    <tr><td>wind</td><td>wind speed in km/h</td></tr>
    <a id="Weather-get-wind_chill"></a>
    <tr><td>wind_chill</td><td>wind chill in degrees centigrade</td></tr>
    <a id="Weather-get-wind_condition"></a>
    <tr><td>wind_condition</td><td>wind direction and speed</td></tr>
    <a id="Weather-get-wind_direction"></a>
    <tr><td>wind_direction</td><td>direction wind comes from in degrees (0 = north wind)</td></tr>
    <a id="Weather-get-wind_speed"></a>
    <tr><td>wind_speed</td><td>same as wind</td></tr>
    </table>
    <br>
    The weekday of the forecast will be in the language of your FHEM system. Enter {$ENV{LANG}} into the FHEM command line to verify. If nothing is displayed or you see an unexpected language setting, add export LANG=de_DE.UTF-8 or something similar to your FHEM start script, restart FHEM and check again. If you get a locale warning when starting FHEM the required language pack might be missing. It can be installed depending on your OS and your preferences (e.g. dpkg-reconfigure locales, apt-get install language-pack-de or something similar).
    <br>
    Depending on the chosen API, other readings can be shown as well.
    The meaning of these readings can be determined from the API provider's
    documentation.

  </ul>
  <br>

  <a id="Weather-attr"></a>
  <h4>Attributes</h4>
  <ul>
    <a id="Weather-attr-disable"></a>
    <li><i>disable</i> - disables the retrieval of weather data - the timer runs according to schedule,
    though no data is requested from the API.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="Weather-attr-forecast"></a>
    <li><i>forecast</i> - hourly/daily, display of forecast data.</li>
    <a id="Weather-attr-forecastLimit"></a>
    <li><i>forecastLimit</i> - Number of forecast data records which should be written as a reading.</li>
    <a id="Weather-attr-alerts"></a>
    <li><i>alerts</i> - 0/1 should alert messages be written similar to Unwetterwarnung</li>
  </ul>
  <br>
</ul>


=end html
=begin html_DE

<a id="Weather"></a>
<h3>Weather</h3>
<ul>
    Hinweis: es wird das Perl-Modul JSON ben&ouml;tigt. Mit <code>apt-get install
    libjson-perl</code> kann es unter Debian und Derivaten installiert
    werden.<p></p>

    Das Weather-Modul arbeitet mit verschiedenen Wetter-APIs zusammen:
    <ul>
      <li>DarkSky (<a href="https://darksky.net">Webseite</a>, Standard)</li>
      <li>OpenWeatherMap (<a href="https://openweathermap.org/">Webseite)</a></li>
      <li>Wunderground (<a href="https://www.wunderground.com/member/api-keys">Webseite)</a></li>
    </ul>
    <br>
    Eine solche virtuelle Wetterstation sammelt periodisch aktuelle Wetterdaten
    und Wettervorhersagen aus dem verwendeten API.<br><br>

  <a id="Weather-define"></a>
  <h4>Define</h4><br><br>
  <ul>
    <code>define &lt;name&gt; Weather [API=&lt;API&gt;[,&lt;apioptions&gt;]] [apikey=&lt;apikey&gt;]
     [location=&lt;location&gt;] [interval=&lt;interval&gt;] [lang=&lt;lang&gt;]</code><br><br>

    Die Parameter haben die folgende Bedeutung:<br>

    <table>
    <tr><td><code>API</code></td><td>Name des Wetter-APIs, z.B. <code>OpenWeatherMapAPI</code></td></tr>
    <tr><td><code>apioptions</code></td><td>Individuelle Optionen f&uuml;r das gew&auml;hlte API</td></tr>
    <tr><td><code>apikey</code></td><td>Schl&uuml;ssel f&uuml;r das gew&auml;hlte API</td></tr>
    <tr><td><code>location</code></td><td>Ort, f&uuml;r den das Wetter vorhergesagt wird.
      Abh&auml;ngig vom API z.B. die Koordinaten, ein Ortsname oder eine ID.</td></tr>
    <tr><td><code>interval</code></td><td>Dauer in Sekunden zwischen den einzelnen
      Aktualisierungen der Wetterdaten</td></tr>
    <tr><td><code>lang</code></td><td>Sprache der Wettervorhersage: <code>de</code>,
      <code>en</code>, <code>pl</code>, <code>fr</code>, <code>it</code> oder <code>nl</code></td></tr>
    </table>
    <p></p>


    Eine ganz einfache Definition ist:<br><br>
    <code>define &lt;name&gt; Weather apikey=&lt;OpenWeatherMapAPISecretKey&gt;</code><br><br>

    Bei dieser Definition wird die API von Dark Sky verwendet mit einem
    individuellen Schl&uuml;ssel, den man sich auf der Webseite von Dark Sky
     beschaffen muss.<p></p>

    Beispiele:
    <pre>
      define Forecast Weather apikey=987498ghjgf864
      define MyWeather Weather API=OpenWeatherMapAPI,cachemaxage:600 apikey=09878945fdskv876 location=52.4545,13.4545 interval=3600 lang=de
      define <name> Weather API=wundergroundAPI,stationId:IHAUIDELB111 apikey=ed64ccc80f004556a4e3456567800b6324a
    </pre>

    Es folgt die API-spezifische Dokumentation.<p></p>

    <h4>OpenWeatherMap</h4><p></p>

    <table>
    <tr><td>API</td><td><code>OpenWeatherMapAPI</code></td></tr>
    <tr>
      <td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code> Zeitdauer in
      Sekunden, innerhalb derer die Wettervorhersage nicht neu abgerufen
      sondern aus dem Cache zur&uuml;ck geliefert wird.</td>
      <td><code>version:&lt;version&gt;</code> API Version welche verwendet werden soll.
      Per Default 2.5, m&ouml;glich ist noch 3.0 aber nur mit Zusatzsubscription</td>
      <td><code>endpoint:onecall</code> nur zum testen ob der API Key welcher nicht
      offiziell für onecall ist nicht doch onecall über die API Version 2.5 unterst&uuml;tzt. WICHTIG!!!
      apioption version darf nicht auf 3.0 gesetzt werden</td>
    </tr>
    <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code> Geographische Breite
      und L&auml;nge des Ortes in Grad, f&uuml;r den das Wetter vorhergesagt wird.
      Bei fehlender Angabe werden die Werte aus den gleichnamigen Attributen
      des <code>global</code>-Device genommen, sofern vorhanden.</td></tr>
    </table>
    <p></p>
    
    <h4>Wunderground</h4><p></p>

    <table>
    <tr><td>API</td><td><code>wundergroundAPI</code></td></tr>
    <tr><td>apioptions</td><td><code>cachemaxage:&lt;cachemaxage&gt;</code> Zeitdauer in
      Sekunden, innerhalb derer die Wettervorhersage nicht neu abgerufen
      sondern aus dem Cache zur&uuml;ck geliefert wird.<br><code>stationId:ID-Num</code>
      <br>die ID der Station von welcher die Daten gelesen werden sollen.</td></tr>
    <tr><td>location</td><td><code>&lt;latitude,longitude&gt;</code> Geographische Breite
      und L&auml;nge des Ortes in Grad, f&uuml;r den das Wetter vorhergesagt wird.
      Bei fehlender Angabe werden die Werte aus den gleichnamigen Attributen
      des <code>global</code>-Device genommen, sofern vorhanden.</td></tr>
    </table>
    <p></p>

    Das Modul unterst&uuml;tzt zus&auml;tzlich vier verschiedene Funktionen
    <code>WeatherAsHtml</code>, <code>WeatherAsHtmlV</code>,
    <code>WeatherAsHtmlH</code> und <code>WeatherAsHtmlD</code>.
    Die ersten beiden Funktionen sind identisch: sie erzeugen
    den HTML-Kode f&uuml;r eine vertikale Darstellung des Wetterberichtes.
    Die dritte Funktion liefert den HTML-Code f&uuml;r eine horizontale
    Darstellung des Wetterberichtes. Die letztgenannte Funktion w&auml;hlt
    automatisch eine Ausrichtung, die abh&auml;ngig davon ist, ob ein
    Smallcreen Style ausgew&auml;hlt ist (vertikale Darstellung) oder
    nicht (horizontale Darstellung). Alle vier Funktionen akzeptieren
    einen zus&auml;tzlichen optionalen Paramter um die Anzahl der
    darzustellenden Icons anzugeben.<br>
    Zus&auml;tzlich erlauben die Funktionen 2 und 3 noch einen dritten Parameter (d oder h) welcher die Forecast-Art (h-Hourly oder d-Daily) mit an gibt.<br>
    Wird der dritte Parameter verwendet muss auch der zweite Parameter f&uuml;r die Anzahl der darzustellenden Icons gesetzt werden.<br><br>
    Beispiel:
    <pre>
      define MyWeatherWeblink weblink htmlCode { WeatherAsHtmlH("MyWeather","h",10) }
    </pre>

  </ul>
  <br>

  <a id="Weather-set"></a>
    <h4>Set</h4>
  <ul>
    <a id="Weather-set-update"></a>
    <li><i>set &lt;name&gt; update</i><br><br>
        Erzwingt eine Abfrage der Wetterdaten. Die darauffolgende Abfrage
        wird gem&auml;&szlig; dem eingestellten
        Intervall <code>interval</code> Sekunden sp&auml;ter durchgef&uuml;hrt.
    </li>
    <a id="Weather-set-newLocation"></a>
    <li>
      <i>set &lt;name&gt; newLocation latitude,longitude</i><br><br>
      Gibt die M&ouml;glichkeit eine neue tempor&auml;re Location zu setzen.
      Das Wertepaar Latitude Longitude wird durch ein Komma getrennt &uuml;bergeben.
      Wird kein Wert mitgegebn (leere &Uuml;bergabe) wird automatisch die per Definition erkannte Location genommen<br><br>
    </li>
  </ul>
  <br>
  <a id="Weather-get"></a>
  <h4>Get</h4>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt;</code><br><br>

    G&uuml;ltige ausgelesene Daten (readings) und ihre Bedeutung (das ? kann einen der Werte 1, 2, 3 , 4 oder 5 annehmen und steht f&uuml;r heute, morgen, &uuml;bermorgen etc.):<br><br>
    <table>
    <a id="Weather-get-.license"></a>
    <tr><td>.license</td><td>Lizenz des jeweiligen API-Anbieters, sofern vorhanden</td></tr>
    <a id="Weather-get-city"></a>
    <tr><td>city</td><td>Name der Stadt, der f&uuml;r die location &uuml;bermittelt wird</td></tr>
    <a id="Weather-get-code"></a>
    <tr><td>code</td><td>Code f&uuml;r die aktuellen Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-condition"></a>
    <tr><td>condition</td><td>aktuelle Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-current_date_time"></a>
    <tr><td>current_date_time</td><td>Zeitstempel der letzten Aktualisierung der Wetterdaten vom Server</td></tr>
    <a id="Weather-get-fc?_code"></a>
    <tr><td>fc?_code</td><td>Code f&uuml;r die vorhergesagten Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-fc?_condition"></a>
    <tr><td>fc?_condition</td><td>vorhergesagte Wetterverh&auml;ltnisse</td></tr>
    <a id="Weather-get-fc?_day_of_week"></a>
    <tr><td>fc?_day_of_week</td><td>Wochentag des Tages, der durch ? dargestellt wird</td></tr>
    <a id="Weather-get-fc?_high_c"></a>
    <tr><td>fc?_high_c</td><td>vorhergesagte maximale Tagestemperatur in Grad Celsius</td></tr>
    <a id="Weather-get-fc?_icon"></a>
    <tr><td>fc?_icon</td><td>Icon f&uuml;r Vorhersage</td></tr>
    <a id="Weather-get-fc?_low_c"></a>
    <tr><td>fc?_low_c</td><td>vorhergesagte niedrigste Tagestemperatur in Grad Celsius</td></tr>
    <a id="Weather-get-humidity"></a>
    <tr><td>humidity</td><td>gegenw&auml;rtige Luftfeuchtgkeit in %</td></tr>
    <a id="Weather-get-icon"></a>
    <tr><td>icon</td><td>relativer Pfad f&uuml;r das aktuelle Icon</td></tr>
    <a id="Weather-get-pressure"></a>
    <tr><td>pressure</td><td>Luftdruck in hPa</td></tr>
    <a id="Weather-get-temperature"></a>
    <tr><td>temperature</td><td>gegenw&auml;rtige Temperatur in Grad Celsius</td></tr>
    <a id="Weather-get-temp_c"></a>
    <tr><td>temp_c</td><td>gegenw&auml;rtige Temperatur in Grad Celsius</td></tr>
    <a id="Weather-get-temp_f"></a>
    <tr><td>temp_f</td><td>gegenw&auml;rtige Temperatur in Grad Celsius</td></tr>
    <a id="Weather-get-visibility"></a>
    <tr><td>visibility</td><td>Sichtweite in km</td></tr>
    <a id="Weather-get-wind"></a>
    <tr><td>wind</td><td>Windgeschwindigkeit in km/h</td></tr>
    <a id="Weather-get-wind_condition"></a>
    <tr><td>wind_condition</td><td>Windrichtung und -geschwindigkeit</td></tr>
    <a id="Weather-get-wind_direction"></a>
    <tr><td>wind_direction</td><td>Gradangabe der Windrichtung (0 = Nordwind)</td></tr>
    <a id="Weather-get-wind_speed"></a>
    <tr><td>wind_speed</td><td>Windgeschwindigkeit in km/h (mit wind identisch)</td></tr>
    <a id="Weather-get-validity"></a>
    <tr><td>validity</td><td>stale, wenn der Ver&ouml;ffentlichungszeitpunkt auf dem entfernten Server vor dem Zeitpunkt der aktuellen Daten (readings) liegt</td></tr>
    </table>
    <br>
    Der Wochentag der Prognose wird in der Sprache Ihres FHEM-Systems angezeigt. Geben Sie zur Überprüfung {$ ENV {LANG}} in die Befehlszeile von FHEM ein. Wenn nichts angezeigt wird oder eine unerwartete Spracheinstellung angezeigt wird, fügen Sie export LANG = de_DE.UTF-8 oder etwas Ähnliches zu Ihrem FHEM-Startskript hinzu. Starten Sie FHEM erneut und überprüfen Sie es erneut. Wenn Sie beim Starten von FHEM eine Ländereinstellung erhalten, fehlt möglicherweise das erforderliche Sprachpaket. Sie kann abhängig von Ihrem Betriebssystem und Ihren Präferenzen installiert werden (z. B. Gebietsschemas dpkg-reconfigure, apt-get install language-pack-de oder ähnliches).
    <br>
    Je nach verwendeter API ist es durchaus m&ouml;glich, dass weitere
    readings geschrieben werden. Die Bedeutung dieser readings kann man
    der API-Beschreibung des Anbieters entnehmen.
  </ul>
  <br>

  <a id="Weather-attr"></a>
  <h4>Attribute</h4>
  <ul>
    <a id="Weather-attr-disable"></a>
    <li><i>disable</i> - stellt die Abfrage der Wetterdaten ab - der Timer l&auml;ft
    gem&auml;&szlig Plan doch es werden keine Daten vom
    API angefordert.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <a id="Weather-attr-forecast"></a>
    <li><i>forecast</i> - hourly/daily, Anzeige von forecast Daten.</li>
    <a id="Weather-attr-forecastLimit"></a>
    <li><i>forecastLimit</i> - Anzahl der Forecast-Datens&auml;tze welche als Reading geschrieben werden sollen.</li>
    <a id="Weather-attr-alerts"></a>
    <li><i>alerts</i> - 0/1 Sollen Alert Meldungen &auml;nlich Unwetterwarnung geschrieben werden.</li>

  </ul>
  <br>
</ul>

=end html_DE

=for :application/json;q=META.json 59_Weather.pm
{
  "abstract": "Modul to provides current weather condition and forecast",
  "x_lang": {
    "de": {
      "abstract": ""
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Weather",
    "OpenWeatherMap",
    "Underground"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.3.0",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "CoolTuxNet"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Date::Parse": 0
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

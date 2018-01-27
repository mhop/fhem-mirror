# $Id$
##############################################################################
#
#     98_Heating_Control.pm
#     written by Dietmar Ortmann
#     Maintained by igami since 02-2018
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
use POSIX;
########################################################################
sub Heating_Control_Initialize($)
{
  my ($hash) = @_;

  if(!$modules{WeekdayTimer}{LOADED} && -f "$attr{global}{modpath}/FHEM/98_WeekdayTimer.pm") {
    my $ret = CommandReload(undef, "98_WeekdayTimer");
    Log3 undef, 1, $ret if($ret);
  }

# Consumer
  $hash->{SetFn}   = "Heating_Control_Set";
  $hash->{AttrFn}  = "Heating_Control_Attr";
  $hash->{DefFn}   = "Heating_Control_Define";
  $hash->{UndefFn} = "Heating_Control_Undef";
  $hash->{GetFn}   = "Heating_Control_Get";
  $hash->{UpdFn}   = "Heating_Control_Update";
  $hash->{AttrList}= "disable:0,1 delayedExecutionCond windowSensor switchInThePast:0,1 commandTemplate ".
     $readingFnAttributes;
}
################################################################################
sub Heating_Control_Set($@) {
  my ($hash, @a) = @_;

  return "no set value specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of enable disable " if($a[1] eq "?");

  my $name = shift @a;
  my $v = join(" ", @a);

  Log3 $hash, 3, "[$name] set $name $v";

  if      ($v eq "enable") {
     fhem("attr $name disable 0");
  } elsif ($v eq "disable") {
     fhem("attr $name disable 1");
  }
  return undef;
}
########################################################################
sub Heating_Control_Get($@) {
   return WeekdayTimer_Get($@);
}
########################################################################
sub Heating_Control_Define($$){
  my ($hash, $def) = @_;

  my $ret = WeekdayTimer_Define($hash, $def);
  return $ret;
}
########################################################################
sub Heating_Control_Undef($$){
  my ($hash, $arg) = @_;
  return WeekdayTimer_Undef($hash, $arg);
}
########################################################################
sub Heating_Control_Update($){
  my ($hash) = @_;
  return WeekdayTimer_Update($hash);
}
################################################################################
sub Heating_Control_SetTimerOfDay($) {
  my ($hash) = @_;
  return WeekdayTimer_SetTimerOfDay($hash);
}
########################################################################
sub Heating_Control_Attr($$$$) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  WeekdayTimer_Attr($cmd, $name, $attrName, $attrVal);
  return undef;
}
########################################################################
sub Heating_Control_SetTimer($) {
  my ($hash) = @_;
  WeekdayTimer_DeleteTimer($hash);
  WeekdayTimer_SetTimer($hash);
}
########################################################################
sub Heating_Control_SetTemp($) {
  my ($name) = @_;

  my $hash = $modules{Heating_Control}{defptr}{$name};
  if(defined $hash) {
     Heating_Control_SetTimer($hash);
  }
}
########################################################################
sub Heating_Control_SetAllTemps() {  # {Heating_Control_SetAllTemps()}

  my @hcNamen = sort keys %{$modules{Heating_Control}{defptr}};
  foreach my $hcName ( @hcNamen ) {
     Heating_Control_SetTemp($hcName);
  }
  Log3 undef,  3, "Heating_Control_SetAllTemps() done on: ".join(" ",@hcNamen );
}

1;

=pod
=item device
=item summary    sends heating commands to heating at defined times
=item summary_DE sendet Temperaturwerte zu festgelegen Zeiten an eine Heizung
=begin html

<a name="Heating_Control"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>Heating Control</h3>
<ul>
  <br>
  <a name="Heating_Controldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Heating_Control &lt;device&gt; [&lt;language&gt;] [<u>weekdays</u>] &lt;profile&gt; [&lt;command&gt;|&lt;condition&gt;]</code>
    <br><br>

    to set a weekly profile for &lt;device&gt;, eg. a heating sink.<br>
    You can define different switchingtimes for every day.<br>

    The new temperature is sent to the &lt;device&gt; automatically with <br><br>

    <code>set &lt;device&gt; (desired-temp|desiredTemperature) &lt;temp&gt;</code><br><br>

    Because of the fhem-type of structures, a structures of heating sinks is sent "desired-temp":
    Use an explicit command if you have structures of MAX heating thermostats.<br>
    If you have defined a &lt;condition&gt; and this condition is false if the switchingtime has reached, no command will executed.<br>
    A other case is to define an own perl command with &lt;command&gt;.
    <p>
    The following parameter are defined:
    <ul><b>device</b><br>
      The device to switch at the given time.
    </ul>
    <p>
    <ul><b>language</b><br>
      Specifies the language used for definition and profiles.
      de,en,fr are possible. The parameter is optional.
    </ul>
    <p>
    <ul><b>weekdays</b><br>
      Specifies the days for all timer in the <b>Heating_Control</b>.
      The parameter is optional. For details see the weekdays part in profile.
    </ul>
    <p>
    <ul><b>profile</b><br>
      Define the weekly profile. All timings are separated by space. A switchingtime is defined
      by the following example: <br><br>

      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;</b></ul><br>

      <u>weekdays:</u> optional, if not set every day of the week is used.<br>
        Otherwise you can define a day with its number or its shortname.<br>
        <ul>
        <li>0,su  sunday</li>
        <li>1,mo  monday</li>
        <li>2,tu  tuesday</li>
        <li>3,we  wednesday</li>
        <li>4 ...</li>
        <li>7,$we  weekend  ($we)</li>
        <li>8,!$we weekday  (!$we)</li>
        </ul><br>
         It is possible to define $we or !$we in daylist to easily allow weekend an holiday. $we !$we are coded as 7 8, when using a numeric daylist.<br><br>
      <u>time:</u>define the time to switch, format: HH:MM:[SS](HH in 24 hour format) or a Perlfunction like {sunrise_abs()}. Within the {} you can use the variable $date(epoch) to get the exact switchingtimes of the week. Example: {sunrise_abs_dat($date)}<br><br>
      <u>parameter:</u>the temperature to be set, using a float with mask 99.9 or a sybolic value like <b>eco</b> or <b>comfort</b> - whatever your thermostat understands.
      The symbolic value can be added an additional parameter:  dayTemp:16 night-temp:15. See examples <br><br>
    </ul>
    <p>
    <ul><b>command</b><br>
      If no condition is set, all the rest is interpreted as a command. Perl-code is setting up
      by the well-known Block with {}.<br>
      Note: if a command is defined only this command is executed. In case of executing
      a "set desired-temp" command, you must define the hole commandpart explicitly by yourself.<br>
  <!----------------------------------------------------------------------------- -->
  <!----------------------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
      The following parameter are replaced:<br>
        <ol>
          <li>$NAME  => the device to switch</li>
          <li>$EVENT => the new temperature</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      if a condition is defined you must declare this with () and a valid perl-code.<br>
      The returnvalue must be boolean.<br>
      The parameter $NAME and $EVENT will be interpreted.
    </ul>
    <p>
    <b>Examples:</b>
    <ul>
        <code>define HCB Heating_Control Bad_Heizung 12345|05:20|21 12345|05:25|comfort 17:20|21 17:25|eco</code><br>
        Mo-Fr are setting the temperature at 05:20 to 21&deg;C, and at 05:25 to <b>comfort</b>.
        Every day will be set the temperature at 17:20 to 21&deg;C and 17:25 to <b>eco</b>.<p>

        <code>define HCW Heating_Control WZ_Heizung 07:00|16 Mo,Tu,Th-Fr|16:00|18.5 20:00|12
          {fhem("set dummy on"); fhem("set $NAME desired-temp $EVENT");}</code><br>
        At the given times and weekdays only(!) the command will be executed.<p>

        <code>define HCW Heating_Control WZ_Heizung Sa-Su,We|08:00|21 (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        The temperature is only set if the dummy variable WeAreThere is "yes".<p>

        <code>define HCW Heating_Control WZ_Heizung en Su-Fr|{sunrise_abs()}|21 Mo-Fr|{sunset_abs()}|16</code><br>
        The device is switched at sunrise/sunset. Language: english.<p>

        <code>define HCW Heating_Control WZ_Heizung en Mo-Fr|{myFunction}|night-temp:18 Mo-Fr|{myFunction()}|dayTemp:16</code><br>
        The is switched at time myFunction(). It is sent the Command "night-temp 18" and "dayTemp 16".<p>

        If you want to have set all Heating_Controls their current value (after a temperature lowering phase holidays)
        you can call the function <b>Heating_Control_SetTemp("HC-device")</b> or <b>Heating_Control_SetAllTemps()</b>.<br>
        This call can be automatically coupled to a dummy by a notify:<br>
        <code>define HeizStatus2 notify Heating:. * {Heating_Control_SetAllTemps()}</code>
        <br><p>
        Some definitions without comment:
        <code><pre>
        define hc    Heating_Control  HeizungKueche de        7|23:35|25        34|23:30|22 23:30|16 23:15|22     8|23:45|16
        define hc    Heating_Control  HeizungKueche de        fr,$we|23:35|25   34|23:30|22 23:30|16 23:15|22    12|23:45|16
        define hc    Heating_Control  HeizungKueche de        20:35|25          34|14:30|22 21:30|16 21:15|22    12|23:00|16

        define hw    Heating_Control  HeizungKueche de        mo-so, $we|{sunrise_abs_dat($date)}|18      mo-so, $we|{sunset_abs_dat($date)}|22
        define ht    Heating_Control  HeizungKueche de        mo-so,!$we|{sunrise_abs_dat($date)}|18      mo-so,!$we|{sunset_abs_dat($date)}|22

        define hh    Heating_Control  HeizungKueche de        {sunrise_abs_dat($date)}|19           {sunset_abs_dat($date)}|21
        define hx    Heating_Control  HeizungKueche de        22:35|25  23:00|16
        </code></pre>

        the list of days can be set globaly for the whole  Heating_Control:<p>

        <code><pre>
        define HeizungWohnen_an_wt    Heating_Control HeizungWohnen de  !$we     09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   $we     09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   78      09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   57      09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de  fr,$we   09:00|19  (heizungAnAus("Ein"))
        </code></pre>

      An example to be able to temporarily boost the temperature for one hour:
      <code><pre>
      define hc Heating_Control HeatingBath de !$we|05:00|{HC_WithBoost(23,"HeatingBath")} $we|07:00|{HC_WithBoost(23,"HeatingBath")} 23:00|{HC_WithBoost(20,"HeatingBath")}
      </code></pre>
      and using a "HeatingBath_Boost" dummy variable:
      <code><pre>
      define HeatingBath_Boost dummy
      attr HeatingBath_Boost setList state:0,23,24,25
      attr HeatingBath_Boost webCmd state
      define di_ResetBoostBath DOIF ([HeatingBath_Boost] > 0)
         ({Heating_Control_SetAllTemps()}, defmod di_ResetBoostBath_Reset at +01:00:00 set HeatingBath_Boost 0)
        DOELSE
         ({Heating_Control_SetAllTemps()})
      attr di_ResetBoostBath do always
      </code></pre>
      and the perl subroutine in 99_myUtils.pm (or the like)
      <code><pre>
      sub HC_BathWithBoost {
        my $numParams = @_;
        my ($degree, $boostPrefix) = @_;
        if ($numParams > 1)
         {
         my $boost = ReadingsVal($boostPrefix . "_Boost", "state", "0");
         return $boost if ($boost =~ m/^\d+$/) && ($boost > 0); # boost?
         }
        return $degree; # otherwise return given temperature
      }
      </code></pre>
      Now you can set "HeatingBath_Boost" in the web interface for a one-hour boost of 3 degrees in the bath.
      (you can trigger that using the PRESENCE function using your girlfriend's device... grin).

      Easy to extend this with a vacation timer using another dummy variable, here <code>VacationTemp</code>.<br>
      Then you can use the command
      <code>defmod defVacationEnd at 2016-12-30T00:00:00 set VacationTemp off, {Heating_Control_SetAllTemps()}</code>
      to stop the vacation temperature before you return in january 2017 and let the appartment heat up again.
      <code><pre>
      sub HC_BathWithBoost($) {
        my $vacation = ReadingsVal("VacationTemp", "state", "unfortunately not on vacation");
        return $vacation if $vacation =~ /^(\d+|eco)$/; # set vacation temperature if given

        my $numParams = @_;
        my ($degree, $boostPrefix) = @_;
        if ($numParams > 1)
         {
         my $boost = ReadingsVal($boostPrefix . "_Boost", "state", "0");
         return $boost if ($boost =~ m/^\d+$/) && ($boost > 0); # boost?
         }
      }
      </code></pre>
      Pray that the device does not restart during your vacation, as the <code>define defVacationEnd ... at </code> is volatile and will be lost at restart!

    </ul>
  </ul>

  <a name="Heating_Controlset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="Heating_Controlget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="Heating_ControlLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li>delayedExecutionCond <br>
    defines a delay Function. When returning true, the switching of the device is delayed until the function retruns a false value. The behavior is just like a windowsensor.

    <br><br>
    <b>Example:</b>
    <pre>
    attr hc delayedExecutionCond isDelayed("%HEATING_CONTROL","%WEEKDAYTIMER","%TIME","%NAME","%EVENT")
    </pre>
    the parameters %HEATING_CONTROL(timer name) %TIME %NAME(device name) %EVENT are replaced at runtime by the correct value.

    <br><br>
    <b>Example of a function:</b>
    <pre>
    sub isDelayed($$$$$) {
       my($hc, $wdt, $tim, $nam, $event ) = @_;

       my $theSunIsStillshining = ...

       return ($tim eq "16:30" && $theSunIsStillshining) ;
    }
    </pre>
    </li>
    <li>switchInThePast<br>
    defines that the depending device will be switched in the past in definition and startup phase when the device is not recognized as a heating.
    Heatings are always switched in the past.
    </li>

    <li><a href="#disable">disable</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
    <li>windowSensor<br>Defines a list of window sensors. When one of its window state readings is <b>open</b> the aktual switch is delayed.</li>  </ul><br>
</ul>

=end html
=begin html_DE

<a name="Heating_Control"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>Heating Control</h3>
<ul>
  <br>
  <a name="Heating_Controldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Heating_Control &lt;device&gt; [&lt;language&gt;] &lt;wochentage;] &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
    <br><br>

    Bildet ein Wochenprofil f&uumlr ein &lt;device&gt;, zb. Heizk&oumlrper, ab.<br>
    Es k&oumlnnen f&uumlr jeden Tag unterschiedliche Schaltzeiten angegeben werden.<br>
    Ist das &lt;device&gt; ein Heizk&oumlrperthermostat (zb. FHT8b, MAX) so wird bei FHT8b/MAX die
    zu setzende Temperatur im &lt;profile&gt; automatisch mittels <br><br>
    <code>set &lt;device&gt; (desired-temp|desiredTemperature) &lt;temp&gt;</code> <br><br> gesendet.
    Struktuen von Heizk&oumlrperthermostaten bekommen aufgrund des fhem-Typs auch desired-temp gesendet:
    Nutze bitte explizite Kommandos wenn Strukturen von MAX Heizthermostaten gesteuert werden sollen.<br><br>
    Ist eine &lt;condition&gt; angegeben und ist zum Schaltpunkt der Ausdruck unwahr,
    so wird dieser Schaltpunkt nicht ausgef&uumlhrt.<br>
    Alternativ zur Automatik kann stattdessen eigener Perl-Code im &lt;command&gt; ausgef&uumlhrt werden.
    <p>
    Folgende Parameter sind im Define definiert:
    <ul><b>device</b><br>
      Name des zu schaltenden Device.
    </ul>
    <p>
    <ul><b>language</b><br>
      Spezifiziert die Sprache f&uumlr die Definition und die Anzeige der Profile in der Weboberfl&aumlche.
      Zurzeit sind de,en,fr definiert. Der Parameter ist optional.
    </ul>
    <p>
    <ul><b><u>wochentage</u></b><br>
      Spezifiziert die Tage f&uumlr alle Timer eines <b>Heating_Control</b>.
      Der Parameter ist optional. Bitte f&uumlr Details zur Definition siehe wochentage im part profile.
    </ul>
    <p>

    <ul><b>profile</b><br>
      Angabe des Wochenprofils. Die einzelnen Schaltzeiten sind durch Leerzeichen getrennt
      Die Angabe der Schaltzeiten ist nach folgendem Muster definiert:<br>
      <ul><b>[&lt;Wochentage&gt;|]&lt;Uhrzeit&gt;|&lt;Parameter&gt;</b></ul><br>

      <u>Wochentage:</u> optionale Angabe, falls nicht gesetzt wird der Schaltpunkt jeden Tag ausgef&uumlhrt.
        F&uumlr die Tage an denen dieser Schaltpunkt aktiv sein soll, ist jeder Tag mit seiner
        Tagesnummer (Mo=1, ..., So=0) oder Name des Tages (Mo, Di, ..., So) einzusetzen.<br><br>
        <ul>
        <li>0,so  Sonntag</li>
        <li>1,mo  Montag</li>
        <li>2,di  Dienstag</li>
        <li>3,mi  Mittwoch</li>
        <li>4 ...</li>
        <li>7,$we  Wochenende  ($we)</li>
        <li>8,!$we Wochentag  (!$we)</li>
        </ul><br>
         Es ist m&oumlglich $we or !$we in der Tagesliste zu definieren.
         So ist es auf einfache Art m&oumlglich die Schaltzeitpunkte f&uumlr das Wochenende oder Wochetage zu definieren.
         $we und!$we werden als 7 bzw. 8 spezifiziert, wenn die numerische Variante der Tagesliste gew&aumlhlt wird.<br><br>
      <u>Uhrzeit:</u>Angabe der Uhrzeit zu der geschaltet werden soll, Format: HH:MM:[SS](HH im 24 Stunden Format) oder eine Perlfunction wie {sunrise_abs()}.
      In {} kannst du die Variable $date(epoch) nutzen, um die Schaltzeiten der Woche zu berechnen. Beispiel: {sunrise_abs_dat($date)}<br><br>

      <u>Parameter:</u>Angabe der zu setzenden Temperatur als Zahl mit Format 99.9 oder als symbolische Konstante <b>eco</b>
      or <b>comfort</b> - was immer das Heizk&oumlrperthermostat versteht.
      Symbolischen Werten kann ein zus&aumltzlicher Parameter angeh&aumlngt werden: dayTemp:16 night-temp:15. Unten folgen Beispiele<br><br>
    </ul>
    <p>
    <ul><b>command</b><br>
      Falls keine Condition in () angegeben wurde, so wird alles weitere als Command
      interpretiert. Perl-Code ist in {} zu setzen. <br>
      Wichtig: Falls ein Command definiert ist, so wird zu den definierten Schaltzeiten
      nur(!) das Command ausgef&uumlhrt. Falls ein desired-temp Befehl abgesetzt werde soll,
      so muss dies explizit angegeben werden.<br>
      Folgende Parameter werden ersetzt:<br>
        <ol>
          <li>$NAME  => das zu schaltende Device</li>
          <li>$EVENT => die zu setzende Temperatur</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      Bei Angabe einer Condition ist diese in () zu setzen und mit validem Perl-Code zu versehen.<br>
      Der R&uumlckgabedatentyp der condition muss boolean sein.<br>
      Die Parameter $NAME und $EVENT werden interpretiert.
    </ul>
    <p>
    <b>Beispiele:</b>
    <ul>
        <code>define HCW Heating_Control Bad_Heizung 12345|05:20|21 12345|05:25|comfort 17:20|21 17:25|eco</code><br>
        Mo-Fr wird die Temperatur um 05:20Uhr auf 21&deg;C, und um 05:25Uhr auf <b>comfort</b> gesetzt.
        Jeden Tag wird die Temperatur um 17:20Uhr auf 21&deg;C und 17:25Uhr auf <b>eco</b> gesetzt.<p>

        <code>define HCW Heating_Control WZ_Heizung 07:00|16 Mo,Di,Mi|16:00|18.5 20:00|12
          {fhem("set dummy on"); fhem("set $NAME desired-temp $EVENT");}</code><br>
        Zu den definierten Schaltzeiten wird nur(!) der in {} angegebene Perl-Code ausgef&uumlhrt.<p>

        <code>define HCW Heating_Control WZ_Heizung Sa-So,Mi|08:00|21 (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        Die zu setzende Temperatur wird nur gesetzt, falls die Dummy Variable WeAreThere = "yes" ist.<p>

        <code>define HCW Heating_Control WZ_Heizung en Su-Fr|{sunrise_abs()}|21 Mo-Fr|{sunset_abs()}|16</code><br>
        Das Ger&aumlt wird bei Sonnenaufgang und Sonnenuntergang geschaltet. Sprache: Englisch.<p>

        <code>define HCW Heating_Control WZ_Heizung en Mo-Fr|{myFunction}|night-temp:18 Mo-Fr|{myFunction()}|dayTemp:16</code><br>
        Das Ger&aumlt wird bei myFunction() geschaltet. Es wird das Kommando "night-temp 18" bzw. "dayTemp 16" gesendet.<p>

        Wenn du beispielsweise nach einer Temperaturabsenkungsphase erreichen willst, dass  alle Heating_Controls ihren aktuellen Wert
        einstellen sollen, kannst du die Funktion <b>Heating_Control_SetTemp("HC-device")</b> or <b>Heating_Control_SetAllTemps()</b> aufrufen.<p>
        Dieser Aufruf kann per notify automatisch an ein dummy gekoppelt werden:<br>
        <code>define HeizStatus2            notify Heizung:.*                          {Heating_Control_SetAllTemps()}</code>
        <br><p>
        Einige Definitionen ohne weitere Erkl&aumlrung:
        <code><pre>
        define hc    Heating_Control  HeizungKueche de        7|23:35|25        34|23:30|22 23:30|16 23:15|22     8|23:45|16
        define hc    Heating_Control  HeizungKueche de        fr,$we|23:35|25   34|23:30|22 23:30|16 23:15|22    12|23:45|16
        define hc    Heating_Control  HeizungKueche de        20:35|25          34|14:30|22 21:30|16 21:15|22    12|23:00|16

        define hw    Heating_Control  HeizungKueche de        mo-so, $we|{sunrise_abs_dat($date)}|18      mo-so, $we|{sunset_abs_dat($date)}|22
        define ht    Heating_Control  HeizungKueche de        mo-so,!$we|{sunrise_abs_dat($date)}|18      mo-so,!$we|{sunset_abs_dat($date)}|22

        define hh    Heating_Control  HeizungKueche de        {sunrise_abs_dat($date)}|19           {sunset_abs_dat($date)}|21
        define hx    Heating_Control  HeizungKueche de        22:35|25  23:00|16
        </code></pre>
        Die Tagesliste kann global f&uumlr das ganze Heating_Control angegeben werden:<p>
        <code><pre>
        define HeizungWohnen_an_wt    Heating_Control HeizungWohnen de  !$we     09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   $we     09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   78      09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de   57      09:00|19  (heizungAnAus("Ein"))
        define HeizungWohnen_an_we    Heating_Control HeizungWohnen de  fr,$we   09:00|19  (heizungAnAus("Ein"))
        </code></pre>

       es ist möglich den Parameter als Perlcode zu spezifizieren:<p>
        <code><pre>
        ...   7|23:35|{getParameter(13,"this")}   7|23:36|{getParameter(14,"that")}
        </code></pre>
        ein detailiertes Beispiel ist in Heating_Control(EN) beschrieben<p>

    </ul>
  </ul>

  <a name="Heating_Controlset"></a>
  <b>Set</b>

    <code><b><font size="+1">set &lt;name&gt; &lt;value&gt;</font></b></code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    <b>enable</b>                # enables  the Heating_Control
    <b>disable</b>               # disables the Heating_Control
    </pre>

    <b><font size="+1">Examples</font></b>:
    <ul>
      <code>set hc disable</code><br>
      <code>set hc enable</code><br>
    </ul>
  </ul>

  <a name="Heating_Controlget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="Heating_ControlLogattr"></a>
  <b>Attributes</b>
  <ul>
    <li>delayedExecutionCond <br>
    definiert eine Veroegerungsfunktion. Wenn die Funktion wahr liefert, wird die Schaltung des Geraets solage verzoegert, bis die Funktion wieder falsch liefert. Das Verhalten entspricht einem Fensterkontakt.

    <br><br>
    <b>Beispiel:</b>
    <pre>
    attr wd delayedExecutionCond isDelayed("$HEATING_CONTROL","$WEEKDAYTIMER","$TIME","$NAME","$EVENT")
    </pre>
    Die Parameter $HEATING_CONTROL(timer Name) $TIME $NAME(device Name) $EVENT werden zur Laufzeit durch die echten Werte ersetzt.

    <br><br>
    <b>Beispielfunktion:</b>
    <pre>
    sub isDelayed($$$$$) {
       my($hc, $wdt, $tim, $nam, $event ) = @_;

       my $theSunIsStillshining = ...

       return ($tim eq "16:30" && $theSunIsStillshining) ;
    }
    </pre>
    </li>
    <li>switchInThePast<br>
    Definiert, dass ein abh&aumlngiges Ger&aumlt in der Start- oder Definitionsphase mit einem Wert aus der Vergangheit geschaltet wird auch wenn das Ger&aumlt nicht als Heizung erkannt wurde.
    Heizungen werden immer mit einem Wert aus der Vergangenheit geschaltet.
    </li>


    <li><a href="#disable">disable</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
    <li>windowSensor<br>Definiert eine Liste mit Fensterkontakten. Wenn das Reading window state eines Fensterkontakts <b>open</b> ist, wird der aktuelle Schaltvorgang verz&oumlgert.</li>
  </ul><br>

=end html_DE
=cut

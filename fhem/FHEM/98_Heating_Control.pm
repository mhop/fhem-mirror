# $Id$
##############################################################################
#
#     98_Heating_Control.pm
#     written by Dietmar Ortmann
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
  $hash->{AttrList}= "disable:0,1 delayedExecutionCond windowSensor switchInThePast:0,1 ".
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
     Log3 undef, 3, "Heating_Control_SetTimer() for $hash->{NAME} done!";
  }   
}
########################################################################
sub Heating_Control_SetAllTemps() {  # {Heating_Control_SetAllTemps()}
  foreach my $hcName ( sort keys %{$modules{Heating_Control}{defptr}} ) {
     Heating_Control_SetTemp($hcName);
  }
  Log3 undef,  3, "Heating_Control_SetAllTemps() done!";
}

1;

=pod
=begin html

<a name="Heating_Control"></a>
<meta content="text/html; charset=ISO-8859-1" http-equiv="content-type">
<h3>Heating Control</h3>
<ul>
  <br>
  <a name="Heating_Controldefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; Heating_Control &lt;device&gt; [&lt;language&gt;] &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
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
    <ul><b>profile</b><br>
      Define the weekly profile. All timings are separated by space. One switchingtime are defined
      by the following example: <br>
      <ul><b>[&lt;weekdays&gt;|]&lt;time&gt;|&lt;parameter&gt;</b></ul><br>
      <u>weekdays:</u> optional, if not set every day is using.<br>
        Otherwise you can define one day as number or as shortname.<br>
      <u>time:</u>define the time to switch, format: HH:MM:[SS](HH in 24 hour format) or a Perlfunction like {sunrise_abs()}. Within the {} you can use the variable $date(epoch) to get the exact switchingtimes of the week. Example: {sunrise_abs_dat($date)}<br>
      <u>parameter:</u>the temperature to be set, using a float with mask 99.9 or a sybolic value like <b>eco</b> or <b>comfort</b> - whatever your thermostat understands.
      The symbolic value can be added an additional parameter:  dayTemp:16 night-temp:15. See examples <br>
    </ul>
    <p>
    <ul><b>command</b><br>
      If no condition is set, all others is interpreted as command. Perl-code is setting up
      by well-known Block with {}.<br>
      Note: if a command is defined only this command are executed. In case of executing
      a "set desired-temp" command, you must define it explicitly.<br>
  <!-- -------------------------------------------------------------------------- -->
  <!----------------------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
      <li>in the command section you can access the event:
      <ul>
        <li>The variable $EVENT will contain the complete event, e.g.
          <code>measured-temp: 21.7 (Celsius)</code></li>
        <li>$EVTPART0,$EVTPART1,$EVTPART2,etc contain the space separated event
          parts (e.g. <code>$EVTPART0="measured-temp:", $EVTPART1="21.7",
          $EVTPART2="(Celsius)"</code>. This data is available as a local
          variable in perl, as environment variable for shell scripts, and will
          be textually replaced for FHEM commands.</li>
        <li>$NAME contains the device to send the event, e.g.
          <code>myFht</code></li>
       </ul></li>

      <li>Note: the following is deprecated and will be removed in a future
        release. The described replacement is attempted if none of the above
        variables ($NAME/$EVENT/etc) found in the command.
      <ul>
        <li>The character <code>%</code> will be replaced with the received
        event, e.g. with <code>on</code> or <code>off</code> or
        <code>measured-temp: 21.7 (Celsius)</code><br> It is advisable to put
        the <code>%</code> into double quotes, else the shell may get a syntax
        error.</li>

        <li>The character <code>@</code> will be replaced with the device
        name.</li>

        <li>To use % or @ in the text itself, use the double mode (%% or
        @@).</li>

        <li>Instead of <code>%</code> and <code>@</code>, the parameters
        <code>%EVENT</code> (same as <code>%</code>), <code>%NAME</code> (same
        as <code>@</code>) and <code>%TYPE</code> (contains the device type,
        e.g.  <code>FHT</code>) can be used. The space separated event "parts"
        are available as %EVTPART0, %EVTPART1, etc.  A single <code>%</code>
        looses its special meaning if any of these parameters appears in the
        definition.</li>
      </ul></li>
  <!-- -------------------------------------------------------------------------- -->
  <!----------------------------------------------------------------------------- -->
  <!-- -------------------------------------------------------------------------- -->
      The following parameter are replaced:<br>
        <ol>
          <li>@ => the device to switch</li>
          <li>% => the new temperature</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      if a condition is defined you must declare this with () and a valid perl-code.<br>
      The returnvalue must be boolean.<br>
      The parameter @ and % will be interpreted.
    </ul>
    <p>
    <b>Example:</b>
    <ul>
        <code>define HCB Heating_Control Bad_Heizung 12345|05:20|21 12345|05:25|comfort 17:20|21 17:25|eco</code><br>
        Mo-Fr are setting the temperature at 05:20 to 21&deg;C, and at 05:25 to <b>comfort</b>.
        Every day will be set the temperature at 17:20 to 21&deg;C and 17:25 to <b>eco</b>.<p>

        <code>define HCW Heating_Control WZ_Heizung 07:00|16 Mo,Tu,Th-Fr|16:00|18.5 20:00|12
          {fhem("set dummy on"); fhem("set @ desired-temp %");}</code><br>
        At the given times and weekdays only(!) the command will be executed.<p>

        <code>define HCW Heating_Control WZ_Heizung Sa-Su,We|08:00|21 (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        The temperature is only set if the dummy variable WeAreThere is "yes".<p>

        <code>define HCW Heating_Control WZ_Heizung en Su-Fr|{sunrise_abs()}|21 Mo-Fr|{sunset_abs()}|16</code><br>
        The device is switched at sunrise/sunset. Language: english.

        <code>define HCW Heating_Control WZ_Heizung en Mo-Fr|{myFunction}|night-temp:18 Mo-Fr|{myFunction()}|dayTemp:16</code><br>
        The is switched at time myFunction(). It is sent the Command "night-temp 18" and "dayTemp 16".

        If you want to have set all Heating_Controls their current value (after a temperature lowering phase holidays)
        you can call the function <b> Heating_Control_SetAllTemps ()</b>.
        This call can be automatically coupled to a dummy by notify:
        <code>define HeizStatus2 notify Heating:. * {Heating_Control_SetAllTemps ()}</code>

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
    <code>define &lt;name&gt; Heating_Control &lt;device&gt; [&lt;language&gt;] &lt;profile&gt; &lt;command&gt;|&lt;condition&gt;</code>
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
    <ul><b>profile</b><br>
      Angabe des Wochenprofils. Die einzelnen Schaltzeiten sind durch Leerzeichen getrennt
      Die Angabe der Schaltzeiten ist nach folgendem Muster definiert:<br>
      <ul><b>[&lt;Wochentage&gt;|]&lt;Uhrzeit&gt;|&lt;Parameter&gt;</b></ul><br>
      <u>Wochentage:</u> optionale Angabe, falls nicht gesetzt wird der Schaltpunkt jeden Tag ausgef&uumlhrt.
        F&uumlr die Tage an denen dieser Schaltpunkt aktiv sein soll, ist jeder Tag mit seiner
        Tagesnummer (Mo=1, ..., So=7) oder Name des Tages (Mo, Di, ..., So) einzusetzen.<br>
      <u>Uhrzeit:</u>Angabe der Uhrzeit zu der geschaltet werden soll, Format: HH:MM:[SS](HH im 24 Stunden Format) oder eine Perlfunction wie {sunrise_abs()}. In {} kannst du die Variable $date(epoch) nutzen, um die Schlatzeiten der Woche zu berechnen. Beispiel: {sunrise_abs_dat($date)}<br>
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
          <li>@ => das zu schaltende Device</li>
          <li>% => die zu setzende Temperatur</li>
        </ol>
    </ul>
    <p>
    <ul><b>condition</b><br>
      Bei Angabe einer Condition ist diese in () zu setzen und mit validem Perl-Code zu versehen.<br>
      Der R&uumlckgabedatentyp der condition muss boolean sein.<br>
      Die Parameter @ und  % werden interpretiert.
    </ul>
    <p>
    <b>Beispiel:</b>
    <ul>
        <code>define HCW Heating_Control Bad_Heizung 12345|05:20|21 12345|05:25|comfort 17:20|21 17:25|eco</code><br>
        Mo-Fr wird die Temperatur um 05:20Uhr auf 21&deg;C, und um 05:25Uhr auf <b>comfort</b> gesetzt.
        Jeden Tag wird die Temperatur um 17:20Uhr auf 21&deg;C und 17:25Uhr auf <b>eco</b> gesetzt.<p>

        <code>define HCW Heating_Control WZ_Heizung 07:00|16 Mo,Di,Mi|16:00|18.5 20:00|12
          {fhem("set dummy on"); fhem("set @ desired-temp %");}</code><br>
        Zu den definierten Schaltzeiten wird nur(!) der in {} angegebene Perl-Code ausgef&uumlhrt.<p>

        <code>define HCW Heating_Control WZ_Heizung Sa-So,Mi|08:00|21 (ReadingsVal("WeAreThere", "state", "no") eq "yes")</code><br>
        Die zu setzende Temperatur wird nur gesetzt, falls die Dummy Variable WeAreThere = "yes" ist.<p>

        <code>define HCW Heating_Control WZ_Heizung en Su-Fr|{sunrise_abs()}|21 Mo-Fr|{sunset_abs()}|16</code><br>
        Das Ger&aumlt wird bei Sonnenaufgang und Sonnenuntergang geschaltet. Sprache: Englisch.

        <code>define HCW Heating_Control WZ_Heizung en Mo-Fr|{myFunction}|night-temp:18 Mo-Fr|{myFunction()}|dayTemp:16</code><br>
        Das Ger&aumlt wird bei myFunction() geschaltet. Es wird das Kommando "night-temp 18" bzw. "dayTemp 16" gesendet.

        Wenn du beispielsweise nach einer Temperaturabsenkungsphase erreichen willst, dass  alle Heating_Controls ihren aktuellen Wert
        einstellen sollen, kannst du die Funktion <b>Heating_Control_SetAllTemps()</b> aufrufen.
        Dieser Aufruf kann per notify automatisch an ein dummy gekoppelt werden:
        <code>define HeizStatus2            notify Heizung:.*                          {Heating_Control_SetAllTemps()}</code>

        <p>
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
    attr wd delayedExecutionCond isDelayed("%HEATING_CONTROL","%WEEKDAYTIMER","%TIME","%NAME","%EVENT")  
    </pre>
    Die Parameter %HEATING_CONTROL(timer Name) %TIME %NAME(device Name) %EVENT werden zur Laufzeit durch die echten Werte ersetzt.
    
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
    
    <li><a href="#disable">disable</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#stateFormat">stateFormat</a></li>
    <li>windowSensor<br>Definiert eine Liste mit Fensterkontakten. Wenn das Reading window state eines Fensterkontakts <b>open</b> ist, wird der aktuelle Schaltvorgang verz&oumlgert.</li>
  </ul><br>

=end html_DE
=cut


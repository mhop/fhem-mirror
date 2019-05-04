###############################################################################
# $Id$
package main;
use strict;
use warnings;
use Data::Dumper;
use Time::Local;

require RESIDENTStk;
our ( @RESIDENTStk_attr, %RESIDENTStk_subTypes );

# initialize ##################################################################
sub GUEST_Initialize($) {
    my ($hash) = @_;

    $hash->{InitDevFn} = "RESIDENTStk_InitializeDev";
    $hash->{DefFn}     = "RESIDENTStk_Define";
    $hash->{UndefFn}   = "RESIDENTStk_Undefine";
    $hash->{SetFn}     = "RESIDENTStk_Set";
    $hash->{AttrFn}    = "RESIDENTStk_Attr";
    $hash->{NotifyFn}  = "RESIDENTStk_Notify";

    $hash->{AttrPrefix} = "rg_";

    $hash->{AttrList} =
        "disable:1,0 disabledForIntervals do_not_notify:1,0 "
      . "rg_states:multiple-strict,home,gotosleep,asleep,awoken,absent,none "
      . "subType:"
      . join( ',', @{ $RESIDENTStk_subTypes{GUEST} } ) . " "
      . $readingFnAttributes;

    foreach (@RESIDENTStk_attr) {
        $hash->{AttrList} .= " " . $hash->{AttrPrefix} . $_;
    }

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;

=pod
=item helper
=item summary special virtual device to represent a guest of your home
=item summary_DE spezielles virtuelles Device, welches einen Gast zu Hause repr&auml;sentiert
=begin html

    <a name="GUEST" id="GUEST"></a>
    <h3>GUEST</h3>
    <ul>
      <a name="GUESTdefine" id="GUESTdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;rg_GuestName&gt; GUEST [&lt;device name(s) of resident group(s)&gt;]</code><br>
        <br>
        Provides a special virtual device to represent a guest of your home.<br>
        Based on the current state and other readings, you may trigger other actions within FHEM.<br>
        <br>
        Used by superior module <a href="#RESIDENTS">RESIDENTS</a> but may also be used stand-alone.<br>
        <br />
        Use comma separated list of resident device names for multi-membership (see example below).<br />
        <br>
        Example:<br>
        <ul>
          <code># Standalone<br>
          define rg_Guest GUEST<br>
          <br>
          # Typical group member<br>
          define rg_Guest GUEST rgr_Residents # to be member of resident group rgr_Residents<br>
          <br>
          # Member of multiple groups<br>
          define rg_Guest GUEST rgr_Residents,rgr_Guests # to be member of resident group rgr_Residents and rgr_Guests</code>
        </ul>
      </ul><br>
      <br>
      <a name="GUESTset" id="GUESTset"></a> <b>Set</b>
      <ul>
        <code>set &lt;rg_GuestName&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Currently, the following commands are defined.<br>
        <ul>
          <li>
            <b>location</b> &nbsp;&nbsp;-&nbsp;&nbsp; sets reading 'location'; see attribute rg_locations to adjust list shown in FHEMWEB
          </li>
          <li>
            <b>mood</b> &nbsp;&nbsp;-&nbsp;&nbsp; sets reading 'mood'; see attribute rg_moods to adjust list shown in FHEMWEB
          </li>
          <li>
            <b>state</b> &nbsp;&nbsp;home,gotosleep,asleep,awoken,absent,none&nbsp;&nbsp; switch between states; see attribute rg_states to adjust list shown in FHEMWEB
          </li>
          <li>
            <b>create</b>
             <li><i>locationMap</i>&nbsp;&nbsp; add a pre-configured weblink device using showing a Google Map if readings locationLat+locationLong are present.</li>
             <li><i>wakeuptimer</i>&nbsp;&nbsp; add several pre-configurations provided by RESIDENTS Toolkit. See separate section in <a href="#RESIDENTS">RESIDENTS module commandref</a> for details.</li>
          </li>
        </ul>
        <ul>
            <u>Note:</u> If you would like to restrict access to admin set-commands (-> create) you may set your FHEMWEB instance's attribute allowedCommands like 'set,set-user'.
            The string 'set-user' will ensure only non-admin set-commands can be executed when accessing FHEM using this FHEMWEB instance.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Possible states and their meaning</u><br>
        <br>
        <ul>
          This module differs between 6 states:<br>
          <br>
          <ul>
            <li>
              <b>home</b> - individual is present at home and awake
            </li>
            <li>
              <b>gotosleep</b> - individual is on it's way to bed
            </li>
            <li>
              <b>asleep</b> - individual is currently sleeping
            </li>
            <li>
              <b>awoken</b> - individual just woke up from sleep
            </li>
            <li>
              <b>absent</b> - individual is not present at home but will be back shortly
            </li>
            <li>
              <b>none</b> - guest device is disabled
            </li>
          </ul>
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Presence correlation to location</u><br>
        <br>
        <ul>
          Under specific circumstances, changing state will automatically change reading 'location' as well.<br>
          <br>
          Whenever presence state changes from 'absent' to 'present', the location is set to 'home'. If attribute rg_locationHome was defined, first location from it will be used as home location.<br>
          <br>
          Whenever presence state changes from 'present' to 'absent', the location is set to 'underway'. If attribute rg_locationUnderway was defined, first location from it will be used as underway location.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Auto Gone</u><br>
        <br>
        <ul>
          Whenever an individual is set to 'absent', a trigger is started to automatically change state to 'gone' after a specific timeframe.<br>
          Default value is 16 hours.<br>
          <br>
          This behaviour can be customized by attribute rg_autoGoneAfter.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Synchronizing presence with other GUEST, PET or ROOMMATE devices</u><br>
        <br>
        <ul>
          If you always leave or arrive at your house together with other roommates, guests or pets, you may enable a synchronization of your presence state for certain individuals.<br>
          By setting attribute rg_passPresenceTo, those individuals will follow your presence state changes to 'home', 'absent' or 'gone' as you do them with your own device.<br>
          <br>
          Please note that individuals with current state 'gone' or 'none' (in case of guests) will not be touched.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Synchronizing state with other GUEST, PET or ROOMMATE devices</u><br>
        <br>
        <ul>
          To sync each and every status change that is _not_ related to leaving or arriving at your house, you may set attribute rg_passStateTo.<br>
          <br>
          Please note that individuals with current state 'gone' or 'none' (in case of guests) will not be touched.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Location correlation to state</u><br>
        <br>
        <ul>
          Under specific circumstances, changing location will have an effect on the actual state as well.<br>
          <br>
          Whenever location is set to 'home', the state is set to 'home' if prior presence state was 'absent'. If attribute rg_locationHome was defined, all of those locations will trigger state change to 'home' as well.<br>
          <br>
          Whenever location is set to 'underway', the state is set to 'absent' if prior presence state was 'present'. If attribute rg_locationUnderway was defined, all of those locations will trigger state change to 'absent' as well. Those locations won't appear in reading 'lastLocation'.<br>
          <br>
          Whenever location is set to 'wayhome', the reading 'wayhome' is set to '1' if current presence state is 'absent'. If attribute rg_locationWayhome was defined, LEAVING one of those locations will set reading 'wayhome' to '1' as well. So you actually have implicit and explicit options to trigger wayhome.<br>
          Arriving at home will reset the value of 'wayhome' to '0'.<br>
          <br>
          If you are using the <a href="#GEOFANCY">GEOFANCY</a> module, you can easily have your location updated with GEOFANCY events by defining a simple NOTIFY-trigger like this:<br>
          <br>
          <code>define n_rg_Guest.location notify geofancy:currLoc_Guest.* set rg_Guest:FILTER=location!=$EVTPART1 location $EVTPART1</code><br>
          <br>
          By defining geofencing zones called 'home' and 'wayhome' in the iOS app, you automatically get all the features of automatic state changes described above.
        </ul>
      </ul><br>
      <br>
      <a name="GUESTattr" id="GUESTattr"></a> <b>Attributes</b><br>
      <ul>
        <ul>
          <li>
            <b>rg_autoGoneAfter</b> - hours after which state should be auto-set to 'gone' when current state is 'absent'; defaults to 16 hours
          </li>
          <li>
            <b>rg_geofenceUUIDs</b> - comma separated list of device UUIDs updating their location via <a href="#GEOFANCY">GEOFANCY</a>. Avoids necessity for additional notify/DOIF/watchdog devices and can make GEOFANCY attribute <i>devAlias</i> obsolete. (using more than one UUID/device might not be a good idea as location my leap)
          </li>
          <li>
            <b>rg_lang</b> - overwrite global language setting; helps to set device attributes to translate FHEMWEB display text
          </li>
          <li>
            <b>rg_locationHome</b> - locations matching these will be treated as being at home; first entry reflects default value to be used with state correlation; separate entries by space; defaults to 'home'
          </li>
          <li>
            <b>rg_locationUnderway</b> - locations matching these will be treated as being underway; first entry reflects default value to be used with state correlation; separate entries by comma or space; defaults to "underway"
          </li>
          <li>
            <b>rg_locationWayhome</b> - leaving a location matching these will set reading wayhome to 1; separate entries by space; defaults to "wayhome"
          </li>
          <li>
            <b>rg_locations</b> - list of locations to be shown in FHEMWEB; separate entries by comma only and do NOT use spaces
          </li>
          <li>
            <b>rg_moodDefault</b> - the mood that should be set after arriving at home or changing state from awoken to home
          </li>
          <li>
            <b>rg_moodSleepy</b> - the mood that should be set if state was changed to gotosleep or awoken
          </li>
          <li>
            <b>rg_moods</b> - list of moods to be shown in FHEMWEB; separate entries by comma only and do NOT use spaces
          </li>
          <li>
            <b>rg_noDuration</b> - may be used to disable continuous, non-event driven duration timer calculation (see readings durTimer*)
          </li>
          <li>
            <b>rg_passStateTo</b> - synchronize home state with other GUEST, PET or ROOMMATE devices; separte devices by space
          </li>
          <li>
            <b>rg_passPresenceTo</b> - synchronize presence state with other GUEST, PET or ROOMMATE devices; separte devices by space
          </li>
          <li>
            <b>rg_presenceDevices</b> - take over presence state from any other FHEM device. Separate more than one device with comma meaning ALL of them need to be either present or absent to trigger update of this GUEST device. You may optionally add a reading name separated by :, otherwise reading name presence and state will be considered.
          </li>
          <li>
            <b>rg_realname</b> - whenever GUEST wants to use the realname it uses the value of attribute alias or group; defaults to group
          </li>
          <li>
            <b>rg_showAllStates</b> - states 'asleep' and 'awoken' are hidden by default to allow simple gotosleep process via devStateIcon; defaults to 0
          </li>
          <li>
            <b>rg_states</b> - list of states to be shown in FHEMWEB; separate entries by comma only and do NOT use spaces; unsupported states will lead to errors though
          </li>
          <li>
            <b>rg_wakeupDevice</b> - reference to enslaved DUMMY devices used as a wake-up timer (part of RESIDENTS Toolkit's wakeuptimer)
          </li>
          <li>
            <b>subType</b> - specifies a specific class of a guest for the device. This will be considered for home alone status calculation. Defaults to "generic"
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generated Readings/Events:</b><br>
      <ul>
        <ul>
          <li>
            <b>durTimerAbsence</b> - timer to show the duration of absence from home in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>durTimerAbsence_cr</b> - timer to show the duration of absence from home in computer readable format (minutes)
          </li>
          <li>
            <b>durTimerPresence</b> - timer to show the duration of presence at home in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>durTimerPresence_cr</b> - timer to show the duration of presence at home in computer readable format (minutes)
          </li>
          <li>
            <b>durTimerSleep</b> - timer to show the duration of sleep in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>durTimerSleep_cr</b> - timer to show the duration of sleep in computer readable format (minutes)
          </li>
          <li>
            <b>lastArrival</b> - timestamp of last arrival at home
          </li>
          <li>
            <b>lastAwake</b> - timestamp of last sleep cycle end
          </li>
          <li>
            <b>lastDeparture</b> - timestamp of last departure from home
          </li>
          <li>
            <b>lastDurAbsence</b> - duration of last absence from home in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>lastDurAbsence_cr</b> - duration of last absence from home in computer readable format (minutes)
          </li>
          <li>
            <b>lastDurPresence</b> - duration of last presence at home in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>lastDurPresence_cr</b> - duration of last presence at home in computer readable format (minutes)
          </li>
          <li>
            <b>lastDurSleep</b> - duration of last sleep in human readable format (hours:minutes:seconds)
          </li>
          <li>
            <b>lastDurSleep_cr</b> - duration of last sleep in computer readable format (minutes)
          </li>
          <li>
            <b>lastLocation</b> - the prior location
          </li>
          <li>
            <b>lastMood</b> - the prior mood
          </li>
          <li>
            <b>lastSleep</b> - timestamp of last sleep cycle begin
          </li>
          <li>
            <b>lastState</b> - the prior state
          </li>
          <li>
            <b>lastWakeup</b> - time of last wake-up timer run
          </li>
          <li>
            <b>lastWakeupDev</b> - device name of last wake-up timer
          </li>
          <li>
            <b>location</b> - the current location
          </li>
          <li>
            <b>mood</b> - the current mood
          </li>
          <li>
            <b>nextWakeup</b> - time of next wake-up program run
          </li>
          <li>
            <b>nextWakeupDev</b> - device name for next wake-up program run
          </li>
          <li>
            <b>presence</b> - reflects the home presence state, depending on value of reading 'state' (can be 'present' or 'absent')
          </li>
          <li>
            <b>state</b> - reflects the current state
          </li>
          <li>
            <b>wakeup</b> - becomes '1' while a wake-up program of this resident is being executed
          </li>
          <li>
            <b>wayhome</b> - depending on current location, it can become '1' if individual is on his/her way back home
          </li>
          <br>
          <br>
          The following readings will be set to '-' if state was changed to 'none':<br>
          lastArrival, lastDurAbsence, lastLocation, lastMood, location, mood
        </ul>
      </ul>
    </ul>

=end html

=begin html_DE

    <a name="GUEST" id="GUEST"></a>
    <h3>GUEST</h3>
    <ul>
      <a name="GUESTdefine" id="GUESTdefine"></a> <b>Define</b>
      <ul>
        <code>define &lt;rg_FirstName&gt; GUEST [&lt;Device Name(n) der Bewohnergruppe(n)&gt;]</code><br>
        <br>
        Stellt ein spezielles virtuelles Device bereit, welches einen Gast zu Hause repr&auml;sentiert.<br>
        Basierend auf dem aktuellen Status und anderen Readings k&ouml;nnen andere Aktionen innerhalb von FHEM angestoßen werden.<br>
        <br>
        Wird vom &uuml;bergeordneten Modul <a href="#RESIDENTS">RESIDENTS</a> verwendet, kann aber auch einzeln benutzt werden.<br>
        <br />
        Bei Mitgliedschaft mehrerer Bewohnergruppen werden diese durch Komma getrennt angegeben (siehe Beispiel unten).<br />
        <br>
        Beispiele:<br>
        <ul>
          <code># Einzeln<br>
          define rg_Guest GUEST<br>
          <br>
          # Typisches Gruppenmitglied<br>
          define rg_Guest GUEST rgr_Residents # um Mitglied der Gruppe rgr_Residents zu sein<br>
          <br>
          # Mitglied in mehreren Gruppen<br>
          define rg_Guest GUEST rgr_Residents,rgr_Guests # um Mitglied der Gruppen rgr_Residents und rgr_Guests zu sein</code>
        </ul>
      </ul><br>
      <br>
      <a name="GUESTset" id="GUESTset"></a> <b>Set</b>
      <ul>
        <code>set &lt;rg_FirstName&gt; &lt;command&gt; [&lt;parameter&gt;]</code><br>
        <br>
        Momentan sind die folgenden Kommandos definiert.<br>
        <ul>
          <li>
            <b>location</b> &nbsp;&nbsp;-&nbsp;&nbsp; setzt das Reading 'location'; siehe auch Attribut rg_locations, um die in FHEMWEB angezeigte Liste anzupassen
          </li>
          <li>
            <b>mood</b> &nbsp;&nbsp;-&nbsp;&nbsp; setzt das Reading 'mood'; siehe auch Attribut rg_moods, um die in FHEMWEB angezeigte Liste anzupassen
          </li>
          <li>
            <b>state</b> &nbsp;&nbsp;home,gotosleep,asleep,awoken,absent,gone&nbsp;&nbsp; wechselt den Status; siehe auch Attribut rg_states, um die in FHEMWEB angezeigte Liste anzupassen
          </li>
          <li>
            <b>create</b>
             <li><i>locationMap</i>&nbsp;&nbsp; f&uuml;gt ein vorkonfiguriertes weblink Device hinzu, welches eine Google Map anzeigt, sofern die Readings locationLat+locationLong vorhanden sind.</li>
             <li><i>wakeuptimer</i>&nbsp;&nbsp; f&uuml;gt diverse Vorkonfigurationen auf Basis von RESIDENTS Toolkit hinzu. Siehe separate Sektion in der <a href="#RESIDENTS">RESIDENTS Modul Kommandoreferenz</a>.</li>
          </li>
        </ul>
        <ul>
            <u>Hinweis:</u> Sofern der Zugriff auf administrative set-Kommandos (-> create) eingeschr&auml;nkt werden soll, kann in einer FHEMWEB Instanz das Attribut allowedCommands &auml;hnlich wie 'set,set-user' erweitert werden.
            Die Zeichenfolge 'set-user' stellt dabei sicher, dass beim Zugriff auf FHEM &uuml;ber diese FHEMWEB Instanz nur nicht-administrative set-Kommandos ausgef&uuml;hrt werden k&ouml;nnen.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>M&ouml;gliche Status und ihre Bedeutung</u><br>
        <br>
        <ul>
          Dieses Modul unterscheidet 6 verschiedene Status:<br>
          <br>
          <ul>
            <li>
              <b>home</b> - Mitbewohner ist zu Hause und wach
            </li>
            <li>
              <b>gotosleep</b> - Mitbewohner ist auf dem Weg ins Bett
            </li>
            <li>
              <b>asleep</b> - Mitbewohner schl&auml;ft
            </li>
            <li>
              <b>awoken</b> - Mitbewohner ist gerade aufgewacht
            </li>
            <li>
              <b>absent</b> - Mitbewohner ist momentan nicht zu Hause, wird aber bald zur&uuml;ck sein
            </li>
            <li>
              <b>none</b> - Gast Device ist deaktiviert
            </li>
          </ul>
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Zusammenhang zwischen Anwesenheit/Presence und Aufenthaltsort/Location</u><br>
        <br>
        <ul>
          Unter bestimmten Umst&auml;nden f&uuml;hrt der Wechsel des Status auch zu einer Änderung des Readings 'location'.<br>
          <br>
          Wannimmer die Anwesenheit (bzw. das Reading 'presence') von 'absent' auf 'present' wechselt, wird 'location' auf 'home' gesetzt. Sofern das Attribut rg_locationHome gesetzt ist, wird die erste Lokation daraus anstelle von 'home' verwendet.<br>
          <br>
          Wannimmer die Anwesenheit (bzw. das Reading 'presence') von 'present' auf 'absent' wechselt, wird 'location' auf 'underway' gesetzt. Sofern das Attribut rg_locationUnderway gesetzt ist, wird die erste Lokation daraus anstelle von 'underway' verwendet.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Auto-Status 'gone'</u><br>
        <br>
        <ul>
          Immer wenn ein Mitbewohner auf 'absent' gesetzt wird, wird ein Z&auml;hler gestartet, der nach einer bestimmten Zeit den Status automatisch auf 'gone' setzt.<br>
          Der Standard ist nach 16 Stunden.<br>
          <br>
          Dieses Verhalten kann &uuml;ber das Attribut rg_autoGoneAfter angepasst werden.
        </ul>
      </ul><br>
      <br>
      <ul>
        <u>Anwesenheit mit anderen GUEST, PET oder ROOMMATE Devices synchronisieren</u><br />
        <br />
        <ul>
          Wenn Sie immer zusammen mit anderen Mitbewohnern oder G&auml;sten das Haus verlassen oder erreichen, k&ouml;nnen Sie ihren Status ganz einfach auf andere Mitbewohner &uuml;bertragen.<br />
          Durch das Setzen des Attributs rr_PassPresenceTo folgen die dort aufgef&uuml;hrten Mitbewohner ihren eigenen Status&auml;nderungen nach 'home', 'absent' oder 'gone'.<br />
          <br />
          Bitte beachten, dass Mitbewohner mit dem aktuellen Status 'gone' oder 'none' (im Falle von G&auml;sten) nicht beachtet werden.
        </ul>
      </ul><br />
      <br />
      <ul>
        <u>Status zu Hause mit anderen GUEST, PET oder ROOMMATE Devices synchronisieren</u><br />
        <br />
        <ul>
          Um jeden Statuswechsel zu synchronisieren, welcher _nicht_ dem erreichen oder verlassen des Hauses entspricht, kann das Attribut rr_passStateTo gesetzt werden.<br />
          <br />
          Bitte beachten, dass Mitbewohner mit dem aktuellen Status 'gone' oder 'none' (im Falle von G&auml;sten) nicht beachtet werden.
        </ul>
      </ul><br />
      <br />
      <ul>
        <u>Zusammenhang zwischen Aufenthaltsort/Location und Anwesenheit/Presence</u><br>
        <br>
        <ul>
          Unter bestimmten Umst&auml;nden hat der Wechsel des Readings 'location' auch einen Einfluss auf den tats&auml;chlichen Status.<br>
          <br>
          Immer wenn eine Lokation mit dem Namen 'home' gesetzt wird, wird auch der Status auf 'home' gesetzt, sofern die Anwesenheit bis dahin noch auf 'absent' stand. Sofern das Attribut rg_locationHome gesetzt wurde, so l&ouml;sen alle dort angegebenen Lokationen einen Statuswechsel nach 'home' aus.<br>
          <br>
          Immer wenn eine Lokation mit dem Namen 'underway' gesetzt wird, wird auch der Status auf 'absent' gesetzt, sofern die Anwesenheit bis dahin noch auf 'present' stand. Sofern das Attribut rg_locationUnderway gesetzt wurde, so l&ouml;sen alle dort angegebenen Lokationen einen Statuswechsel nach 'underway' aus. Diese Lokationen werden auch nicht in das Reading 'lastLocation' &uuml;bertragen.<br>
          <br>
          Immer wenn eine Lokation mit dem Namen 'wayhome' gesetzt wird, wird das Reading 'wayhome' auf '1' gesetzt, sofern die Anwesenheit zu diesem Zeitpunkt 'absent' ist. Sofern das Attribut rg_locationWayhome gesetzt wurde, so f&uuml;hrt das VERLASSEN einer dort aufgef&uuml;hrten Lokation ebenfalls dazu, dass das Reading 'wayhome' auf '1' gesetzt wird. Es gibt also 2 M&ouml;glichkeiten den Nach-Hause-Weg-Indikator zu beeinflussen (implizit und explizit).<br>
          Die Ankunft zu Hause setzt den Wert von 'wayhome' zur&uuml;ck auf '0'.<br>
          <br>
          Wenn Sie auch das <a href="#GEOFANCY">GEOFANCY</a> Modul verwenden, k&ouml;nnen Sie das Reading 'location' ganz einfach &uuml;ber GEOFANCY Ereignisse aktualisieren lassen. Definieren Sie dazu einen NOTIFY-Trigger wie diesen:<br>
          <br>
          <code>define n_rg_Manfred.location notify geofancy:currLoc_Manfred.* set rg_Manfred:FILTER=location!=$EVTPART1 location $EVTPART1</code><br>
          <br>
          Durch das Anlegen von Geofencing-Zonen mit den Namen 'home' und 'wayhome' in der iOS App werden zuk&uuml;nftig automatisch alle Status&auml;nderungen wie oben beschrieben durchgef&uuml;hrt.
        </ul>
      </ul><br>
      <br>
      <a name="GUESTattr" id="GUESTattr"></a> <b>Attribute</b><br>
      <ul>
        <ul>
          <li>
            <b>rg_autoGoneAfter</b> - Anzahl der Stunden, nach denen sich der Status automatisch auf 'gone' &auml;ndert, wenn der aktuellen Status 'absent' ist; Standard ist 36 Stunden
          </li>
          <li>
            <b>rg_geofenceUUIDs</b> - Mit Komma getrennte Liste von Ger&auml;te UUIDs, die ihren Standort &uuml;ber <a href="#GEOFANCY">GEOFANCY</a> aktualisieren. Vermeidet zus&auml;tzliche notify/DOIF/watchdog Ger&auml;te und kann als Ersatz f&uuml;r das GEOFANCY attribute <i>devAlias</i> dienen. (hier ehr als eine UUID/Device zu hinterlegen ist eher keine gute Idee da die Lokation dann wom&ouml;glich anf&auml;ngt zu springen)
          </li>
          <li>
            <b>rg_lang</b> - &uuml;berschreibt globale Spracheinstellung; hilft beim setzen von Device Attributen, um FHEMWEB Anzeigetext zu &uuml;bersetzen
          </li>
          <li>
            <b>rg_locationHome</b> - hiermit &uuml;bereinstimmende Lokationen werden als zu Hause gewertet; der erste Eintrag wird f&uuml;r das Zusammenspiel bei Status&auml;nderungen benutzt; mehrere Eintr&auml;ge durch Leerzeichen trennen; Standard ist 'home'
          </li>
          <li>
            <b>rg_locationUnderway</b> - hiermit &uuml;bereinstimmende Lokationen werden als unterwegs gewertet; der erste Eintrag wird f&uuml;r das Zusammenspiel bei Status&auml;nderungen benutzt; mehrere Eintr&auml;ge durch Leerzeichen trennen; Standard ist 'underway'
          </li>
          <li>
            <b>rg_locationWayhome</b> - das Verlassen einer Lokation, die hier aufgef&uuml;hrt ist, l&auml;sst das Reading 'wayhome' auf '1' setzen; mehrere Eintr&auml;ge durch Leerzeichen trennen; Standard ist "wayhome"
          </li>
          <li>
            <b>rg_locations</b> - Liste der in FHEMWEB anzuzeigenden Lokationsauswahlliste in FHEMWEB; mehrere Eintr&auml;ge nur durch Komma trennen und KEINE Leerzeichen verwenden
          </li>
          <li>
            <b>rg_moodDefault</b> - die Stimmung, die nach Ankunft zu Hause oder nach dem Statuswechsel von 'awoken' auf 'home' gesetzt werden soll
          </li>
          <li>
            <b>rg_moodSleepy</b> - die Stimmung, die nach Statuswechsel zu 'gotosleep' oder 'awoken' gesetzt werden soll
          </li>
          <li>
            <b>rg_moods</b> - Liste von Stimmungen, wie sie in FHEMWEB angezeigt werden sollen; mehrere Eintr&auml;ge nur durch Komma trennen und KEINE Leerzeichen verwenden
          </li>
          <li>
            <b>rg_noDuration</b> - deaktiviert die kontinuierliche, nicht Event-basierte Berechnung der Zeitspannen (siehe Readings durTimer*)
          </li>
          <li>
            <b>rg_passStateTo</b> - synchronisiere den Status zu Hause mit anderen GUEST, PET oder ROOMMATE Devices; mehrere Devices durch Leerzeichen trennen
          </li>
          <li>
            <b>rg_passPresenceTo</b> - synchronisiere die Anwesenheit mit anderen GUEST, PET oder ROOMMATE Devices; mehrere Devices durch Leerzeichen trennen
          </li>
          <li>
            <b>rg_presenceDevices</b> - &uuml;bernehmen des presence Status von einem anderen FHEM Device. Bei mehreren Devices diese mit Komma trennen, um ein Update des GUEST Devices auszul&ouml;sen, sobald ALLE Devices entweder absent oder present sind. Optional kann auch durch : abgetrennt ein Reading Name angegeben werden, ansonsten werden die Readings presence und state ber&uuml;cksichtigt.
          </li>
          <li>
            <b>rg_realname</b> - wo immer GUEST den richtigen Namen verwenden m&ouml;chte nutzt es den Wert des Attributs alias oder group; Standard ist group
          </li>
          <li>
            <b>rg_showAllStates</b> - die Status 'asleep' und 'awoken' sind normalerweise nicht immer sichtbar, um einen einfachen Zubettgeh-Prozess &uuml;ber das devStateIcon Attribut zu erm&ouml;glichen; Standard ist 0
          </li>
          <li>
            <b>rg_states</b> - Liste aller in FHEMWEB angezeigter Status; Eintrage nur mit Komma trennen und KEINE Leerzeichen benutzen; nicht unterst&uuml;tzte Status f&uuml;hren zu Fehlern
          </li>
          <li>
            <b>rg_wakeupDevice</b> - Referenz zu versklavten DUMMY Ger&auml;ten, welche als Wecker benutzt werden (Teil von RESIDENTS Toolkit's wakeuptimer)
          </li>
          <li>
            <b>subType</b> - Gibt einen bestimmten Typ eines Gasts f&uuml;r das Device an. Dies wird bei der Berechnung des Home Alone Status ber&uuml;cksichtigt. Standard ist "generic"
          </li>
        </ul>
      </ul><br>
      <br>
      <br>
      <b>Generierte Readings/Events:</b><br>
      <ul>
        <ul>
          <li>
            <b>durTimerAbsence</b> - Timer, der die Dauer der Abwesenheit in normal lesbarem Format anzeigt (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>durTimerAbsence_cr</b> - Timer, der die Dauer der Abwesenheit in Computer lesbarem Format anzeigt (Minuten)
          </li>
          <li>
            <b>durTimerPresence</b> - Timer, der die Dauer der Anwesenheit in normal lesbarem Format anzeigt (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>durTimerPresence_cr</b> - Timer, der die Dauer der Anwesenheit in Computer lesbarem Format anzeigt (Minuten)
          </li>
          <li>
            <b>durTimerSleep</b> - Timer, der die Schlafdauer in normal lesbarem Format anzeigt (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>durTimerSleep_cr</b> - Timer, der die Schlafdauer in Computer lesbarem Format anzeigt (Minuten)
          </li>
          <li>
            <b>lastArrival</b> - Zeitstempel der letzten Ankunft zu Hause
          </li>
          <li>
            <b>lastAwake</b> - Zeitstempel des Endes des letzten Schlafzyklus
          </li>
          <li>
            <b>lastDeparture</b> - Zeitstempel des letzten Verlassens des Zuhauses
          </li>
          <li>
            <b>lastDurAbsence</b> - Dauer der letzten Abwesenheit in normal lesbarem Format (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>lastDurAbsence_cr</b> - Dauer der letzten Abwesenheit in Computer lesbarem Format (Minuten)
          </li>
          <li>
            <b>lastDurPresence</b> - Dauer der letzten Anwesenheit in normal lesbarem Format (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>lastDurPresence_cr</b> - Dauer der letzten Anwesenheit in Computer lesbarem Format (Minuten)
          </li>
          <li>
            <b>lastDurSleep</b> - Dauer des letzten Schlafzyklus in normal lesbarem Format (Stunden:Minuten:Sekunden)
          </li>
          <li>
            <b>lastDurSleep_cr</b> - Dauer des letzten Schlafzyklus in Computer lesbarem Format (Minuten)
          </li>
          <li>
            <b>lastLocation</b> - der vorherige Aufenthaltsort
          </li>
          <li>
            <b>lastMood</b> - die vorherige Stimmung
          </li>
          <li>
            <b>lastSleep</b> - Zeitstempel des Beginns des letzten Schlafzyklus
          </li>
          <li>
            <b>lastState</b> - der vorherige Status
          </li>
          <li>
            <b>lastWakeup</b> - Zeit der letzten Wake-up Timer Ausf&uuml;hring
          </li>
          <li>
            <b>lastWakeupDev</b> - Device Name des zuletzt verwendeten Wake-up Timers
          </li>
          <li>
            <b>location</b> - der aktuelle Aufenthaltsort
          </li>
          <li>
            <b>mood</b> - die aktuelle Stimmung
          </li>
          <li>
            <b>nextWakeup</b> - Zeit der n&auml;chsten Wake-up Timer Ausf&uuml;hrung
          </li>
          <li>
            <b>nextWakeupDev</b> - Device Name des als n&auml;chstes ausgef&auml;hrten Wake-up Timer
          </li>
          <li>
            <b>presence</b> - gibt den zu Hause Status in Abh&auml;ngigkeit des Readings 'state' wieder (kann 'present' oder 'absent' sein)
          </li>
          <li>
            <b>state</b> - gibt den aktuellen Status wieder
          </li>
          <li>
            <b>wakeup</b> - hat den Wert '1' w&auml;hrend ein Weckprogramm dieses Bewohners ausgef&uuml;hrt wird
          </li>
          <li>
            <b>wayhome</b> - abh&auml;ngig vom aktullen Aufenthaltsort, kann der Wert '1' werden, wenn die Person auf dem weg zur&uuml;ck nach Hause ist
          </li>
          <br>
          <br>
          Die folgenden Readings werden auf '-' gesetzt, sobald der Status auf 'none' steht:<br>
          lastArrival, lastDurAbsence, lastLocation, lastMood, location, mood
        </ul>
      </ul>
    </ul>

=end html_DE

=for :application/json;q=META.json 20_GUEST.pm
{
  "author": [
    "Julian Pawlowski <julian.pawlowski@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "loredo"
  ],
  "x_fhem_maintainer_github": [
    "jpawlowski"
  ],
  "keywords": [
    "Attendence",
    "Workers",
    "Presence",
    "RESIDENTS"
  ]
}
=end :application/json;q=META.json

=cut

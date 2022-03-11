###############################################################################
#
# Developed with VSCodium and richterger perl plugin.
#
#  (c) 2017-2022 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Vitolinker / Commandref
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################
package FHEM::LGTV_WebOS;

use strict;
use warnings;

require FHEM::Devices::LGTV::LGTVWebOS;

use FHEM::Meta;

use GPUtils qw(GP_Import);

#-- Run before package compilation
BEGIN {
    #-- Export to main context with different name
    GP_Import(qw( readingFnAttributes));
}

sub ::LGTV_WebOS_Initialize { goto &Initialize }

sub Initialize {
    my $hash = shift;

    # Provider
    $hash->{ReadFn}  = \&FHEM::Devices::LGTV::LGTVWebOS::Read;
    $hash->{WriteFn} = \&FHEM::Devices::LGTV::LGTVWebOS::Write;

    # Consumer
    $hash->{SetFn}   = \&FHEM::Devices::LGTV::LGTVWebOS::Set;
    $hash->{DefFn}   = \&FHEM::Devices::LGTV::LGTVWebOS::Define;
    $hash->{UndefFn} = \&FHEM::Devices::LGTV::LGTVWebOS::Undef;
    $hash->{AttrFn}  = \&FHEM::Devices::LGTV::LGTVWebOS::Attr;
    $hash->{AttrList} =
        "disable:1 "
      . "channelGuide:1 "
      . "pingPresence:1 "
      . "wakeOnLanMAC "
      . "wakeOnLanBroadcast "
      . "wakeupCmd "
      . "keepAliveCheckTime "
      . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;

__END__

=pod
=item device
=item summary       Controls LG SmartTVs run with WebOS Operating System
=item summary_DE    Steuert LG SmartTVs mit WebOS Betriebssystem

=begin html

<a name="LGTV_WebOS"></a>
<h3>LGTV_WebOS</h3>

<ul>
    This module controls SmartTVs from LG based on WebOS as operation system via network. It offers to swtich the TV channel, start and switch applications, send remote control commands, as well as to query the actual status.<p><br /><br />
    
    <strong>Definition </strong><code>define &lt;name&gt; LGTV_WebOS &lt;IP-Address&gt;</code>
    </p>
    <ul>
        <ul>
            When an LGTV_WebOS-Module is defined, an internal routine is triggered which queries the TV's status every 15s and triggers respective Notify / FileLog Event definitions.
        </ul>
    </ul>
    </p>
    <ul>
        <ul>
            Example:
        </ul>
        <ul>
            <code>define TV LGTV_WebOS 192.168.0.10 <br /></code><br /><br /></p>
        </ul>
    </ul>
        <p><code><strong>Set-Commands </strong><code>set &lt;Name&gt; &lt;Command&gt; [&lt;Parameter&gt;]</code></code></p>
    <ul>
        <ul>
            The following commands are supported in the actual version:
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li><strong>connect&nbsp;</strong> -&nbsp; Connects to the TV at the defined address. When triggered the first time, a pairing is conducted</li>
                <li><strong>pairing&nbsp;</strong> -&nbsp;&nbsp; Sends a pairing request to the TV which needs to be confirmed by the user with remote control</li>
                <li><strong>screenMsg</strong> &lt;Text&gt;&nbsp;&nbsp;-&nbsp;&nbsp; Displays a message for 3-5s on the TV in the top right corner of the screen</li>
                <li><strong>mute</strong> on, off&nbsp; -&nbsp; Turns volume to mute. Depending on the audio connection, this needs to be set on the AV Receiver (see volume) </li>
                <li><strong>volume </strong>0-100, Slider -&nbsp;&nbsp; Sets the volume. Depending on the audio connection, this needs to be set on the AV Receiver (see mute)</li>
                <li><strong>volumeUp</strong>&nbsp; -&nbsp;&nbsp; Increases the volume by 1</li>
                <li><strong>volumeDown</strong>&nbsp; -&nbsp;&nbsp; Decreases the volume by 1</li>
                <li><strong>channelUp</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Switches the channel to the next one</li>
                <li><strong>channelDown</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Switches the channel to the previous one</li>
                <li><strong>getServiceList&nbsp;</strong> -&nbsp; Queries the running services on WebOS (in beta phase)</li>
                <li><strong>on</strong> - Turns the TV on, depending on type of device. Only working when LAN or Wifi connection remains active during off state.</li>
                <li><strong>off</strong> - Turns the TV off, when an active connection is established</li>
                <li><strong>launchApp</strong> &lt;Application&gt;&nbsp;&nbsp;-&nbsp;&nbsp; Activates an application out of the following list (Maxdome, AmazonVideo, YouTube, Netflix, TV, GooglePlay, Browser, Chili, TVCast, Smartshare, Scheduler, Miracast, TV)&nbsp; <br />Note: TV is an application in LG's terms and not an input connection</li>
                <li><strong>3D</strong> on,off&nbsp; -&nbsp; 3D Mode is turned on and off. Depending on type of TV there might be different modes (e.g. Side-by-Side, Top-Bottom)</li>
                <li><strong>stop</strong>&nbsp; -&nbsp;&nbsp; Stop command (depending on application)</li>
                <li><strong>play&nbsp; </strong>-&nbsp;&nbsp; Play command (depending on application)</li>
                <li><strong>pause&nbsp; </strong>-&nbsp;&nbsp; Pause command (depending on application)</li>
                <li><strong>rewind&nbsp; </strong>-&nbsp;&nbsp; Rewind command (depending on application)</li>
                <li><strong>fastForward&nbsp; </strong>-&nbsp;&nbsp; Fast Forward command (depending on application)</li>
                <li><strong>clearInputList&nbsp;</strong> -&nbsp;&nbsp; Clears list of Inputs</li>
                <li><strong>input&nbsp;</strong> - Selects the input connection (depending on the actual TV type and connected devices) <br />e.g.: extInput_AV-1, extInput_HDMI-1, extInput_HDMI-2, extInput_HDMI-3)</li>
            </ul>
        </ul>
    </ul><br /><br /></p>
        <p><strong>Get-Command</strong> <code>get &lt;Name&gt; &lt;Readingname&gt;</code><br /></p>
    <ul>
        <ul>
            Currently, GET reads back the values of the current readings. Please see below for a list of Readings / Generated Events.
        </ul>
    </ul>
    <p><br /><strong>Attributes</strong></p>
    <ul>
        <ul>
            <li>disable</li>
            Optional attribute to deactivate the recurring status updates. Manual trigger of update is alsways possible.</br>
            Valid Values: 0 =&gt; recurring status updates, 1 =&gt; no recurring status updates.</p>
        </ul>
    </ul>
    <ul>
        <ul>
            <li>channelGuide</li>
            Optional attribute to deactivate the recurring TV Guide update. Depending on TV and FHEM host, this causes significant network traffic and / or CPU load</br>
            Valid Values: 0 =&gt; no recurring TV Guide updates, 1 =&gt; recurring TV Guide updates.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>pingPresence</li>
            current state of ping presence from TV. create a reading presence with values absent or present.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>keepAliveCheckTime</li>
            value in seconds - keepAliveCheck is check read data input from tcp socket and prevented FHEM freeze.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>wakeOnLanMAC</li>
            Network MAC Address of the LG TV Networkdevice.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>wakeOnLanBroadcast</li>
            Broadcast Address of the Network - wakeOnLanBroadcast &lt;network&gt;.255
        </ul>
    </ul>
    <ul>
        <ul>
            <li>wakeupCmd</li>
            Set a command to be executed when turning on an absent device. Can be an FHEM command or Perl command in {}.
        </ul>
    </ul> 
</ul>

=end html

=begin html_DE

<a name="LGTV_WebOS"></a>
<h3>LGTV_WebOS</h3>
<ul>
    <ul>
        Dieses Modul steuert SmartTV's des Herstellers LG mit dem Betriebssystem WebOS &uuml;ber die Netzwerkschnittstelle. Es bietet die M&ouml;glichkeit den aktuellen TV Kanal zu steuern, sowie Apps zu starten, Fernbedienungsbefehle zu senden, sowie den aktuellen Status abzufragen.
    </ul>
    <p><br /><br /><strong>Definition </strong><code>define &lt;name&gt; LGTV_WebOS &lt;IP-Addresse&gt;</code> <br /><br /></p>
    <ul>
        <ul>
            <ul>Bei der Definition eines LGTV_WebOS-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig alle 15s den Status des TV abfragt und entsprechende Notify-/FileLog-Definitionen triggert.</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>Beispiel: <code>define TV LGTV_WebOS 192.168.0.10 <br /></code><br /><br /></ul>
        </ul>
    </ul>
    <strong>Set-Kommandos </strong><code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <ul>
        <ul>
            <ul>Aktuell werden folgende Kommandos unterst&uuml;tzt.</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <ul>
                    <li><strong>connect&nbsp;</strong> -&nbsp; Verbindet sich zum Fernseher unter der IP wie definiert, f&uuml;hrt beim ersten mal automatisch ein pairing durch</li>
                    <li><strong>pairing&nbsp;</strong> -&nbsp;&nbsp; Berechtigungsanfrage an den Fernseher, hier muss die Anfrage mit der Fernbedienung best&auml;tigt werden</li>
                    <li><strong>screenMsg</strong> &lt;Text&gt;&nbsp;&nbsp;-&nbsp;&nbsp; zeigt f&uuml;r ca 3-5s eine Nachricht auf dem Fernseher oben rechts an</li>
                    <li><strong>mute</strong> on, off&nbsp; -&nbsp; Schaltet den Fernseher Stumm, je nach Anschluss des Audiosignals, muss dieses am Verst&auml;rker (AV Receiver) geschehen (siehe Volume)</li>
                    <li><strong>volume </strong>0-100, Schieberegler&nbsp; -&nbsp;&nbsp; Setzt die Lautst&auml;rke des Fernsehers, je nach Anschluss des Audiosignals, muss dieses am Verst&auml;rker (AV Receiver) geschehen (siehe mute)</li>
                    <li><strong>volumeUp</strong>&nbsp; -&nbsp;&nbsp; Erh&ouml;ht die Lautst&auml;rke um den Wert 1</li>
                    <li><strong>volumeDown</strong>&nbsp; -&nbsp;&nbsp; Verringert die Lautst&auml;rke um den Wert 1</li>
                    <li><strong>channelUp</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet auf den n&auml;chsten Kanal um</li>
                    <li><strong>channelDown</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet auf den vorherigen Kanal um</li>
                    <li><strong>getServiceList&nbsp;</strong> -&nbsp; Fragrt die Laufenden Dienste des Fernsehers an (derzeit noch in Beta-Phase)</li>
                    <li><strong>on</strong>&nbsp; -&nbsp;&nbsp; Schaltet den Fernseher ein, wenn WLAN oder LAN ebenfalls im Aus-Zustand aktiv ist (siehe Bedienungsanleitung da Typabh&auml;ngig)</li>
                    <li><strong>off</strong> - Schaltet den Fernseher aus, wenn eine Connection aktiv ist</li>
                    <li><strong>launchApp</strong> &lt;Anwendung&gt;&nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert eine Anwendung aus der Liste (Maxdome, AmazonVideo, YouTube, Netflix, TV, GooglePlay, Browser, Chili, TVCast, Smartshare, Scheduler, Miracast, TV)&nbsp; <br />Achtung: TV ist hier eine Anwendung, und kein Ger&auml;teeingang</li>
                    <li><strong>3D</strong> on,off&nbsp; -&nbsp; 3D Modus kann hier ein- und ausgeschaltet werden, je nach Fernseher k&ouml;nnen mehrere 3D Modi unterst&uuml;tzt werden (z.B. Side-by-Side, Top-Bottom)</li>
                    <li><strong>stop</strong>&nbsp; -&nbsp;&nbsp; Stop-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>play&nbsp; </strong>-&nbsp;&nbsp; Play-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>pause&nbsp; </strong>-&nbsp;&nbsp; Pause-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>rewind&nbsp; </strong>-&nbsp;&nbsp; Zur&uuml;ckspulen-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>fastForward&nbsp; </strong>-&nbsp;&nbsp; Schneller-Vorlauf-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>clearInputList&nbsp;</strong> -&nbsp;&nbsp; L&ouml;scht die Liste der Ger&auml;teeing&auml;nge</li>
                    <li><strong>input&nbsp;</strong> - W&auml;hlt den Ger&auml;teeingang aus (Abh&auml;ngig von Typ und angeschossenen Ger&auml;ten) <br />Beispiele: extInput_AV-1, extInput_HDMI-1, extInput_HDMI-2, extInput_HDMI-3)</li>
                </ul>
            </ul>
        </ul>
    </ul>
    <p><strong>Get-Kommandos</strong> <code>get &lt;Name&gt; &lt;Readingname&gt;</code><br /><br /></p>
    <ul>
        <ul>
            <ul>Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".</ul>
        </ul>
    </ul>
    <p><br /><br /><strong>Attribute</strong></p>
    <ul>
        <ul>
            <ul>
                <li>disable</li>
                Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>M&ouml;gliche Werte: 0 =&gt; zyklische Status-Updates, 1 =&gt; keine zyklischen Status-Updates.</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>channelGuide</li>
                Optionales Attribut zur Deaktivierung der zyklischen Updates des TV-Guides, dieses beansprucht je nach Hardware einigen Netzwerkverkehr und Prozessorlast
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>M&ouml;gliche Werte: 0 =&gt; keine zyklischen TV-Guide-Updates, 1 =&gt; zyklische TV-Guide-Updates</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>wakeOnLanMAC</li>
                MAC Addresse der Netzwerkkarte vom LG TV
            </ul>
        </ul>        
    </ul>    
    <ul>
        <ul>
            <ul>
                <li>wakeOnLanBroadcast</li>
                Broadcast Netzwerkadresse - wakeOnLanBroadcast &lt;netzwerk&gt;.255
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>pingPresence</li>
                M&ouml;gliche Werte: 0 =&gt; presence via ping deaktivert, 1 =&gt; presence via ping aktiviert
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>keepAliveCheckTime</li>
                Wert in Sekunden - keepAliveCheckTime
 kontrolliert in einer bestimmten Zeit ob noch Daten über die TCP Schnittstelle kommen und verhindert somit FHEM Freezes
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>wakeupCmd</li>
                Befehl zum Einschalten des LG TV. M&ouml;glich ist ein FHEM Befehl oder Perl in {}.
            </ul>
        </ul>        
    </ul>
    <p><br /><br /><strong>Generierte Readings/Events:</strong></p>
    <ul>
        <ul>
            <li><strong>3D</strong> - Status des 3D-Wiedergabemodus ("on" =&gt; 3D Wiedergabemodus aktiv, "off" =&gt; 3D Wiedergabemodus nicht aktiv)</li>
            <li><strong>3DMode</strong> - Anzeigemodus (2d, 2dto3d, side_side_half, line_interleave_half, column_interleave, check_board)</li>
            <li><strong>channel</strong> - Die Nummer des aktuellen TV-Kanals</li>
            <li><strong>channelName</strong> - Der Name des aktuellen TV-Kanals</li>
            <li><strong>channelMedia</strong> - Senderinformation</li>
            <li><strong>channelCurrentEndTime </strong>- Ende der laufenden Sendung (Beta)</li>
            <li><strong>channelCurrentStartTime </strong>- Start der laufenden Sendung (Beta)</li>
            <li><strong>channelCurrentTitle</strong> - Der Name der laufenden Sendung (Beta)</li>
            <li><strong>channelNextEndTime </strong>- Ende der n&auml;chsten Sendung (Beta)</li>
            <li><strong>channelNextStartTime </strong>- Start der n&auml;chsten Sendung (Beta)</li>
            <li><strong>channelNextTitle</strong> - Der Name der n&auml;chsten Sendung (Beta)</li>
            <li><strong>extInput_&lt;Ger&auml;teeingang</strong>&gt; - Status der Eingangsquelle (connect_true, connect_false)</li>
            <li><strong>input</strong> - Derzeit aktiver Ger&auml;teeingang</li>
            <li><strong>lastResponse </strong>- Status der letzten Anfrage (ok, error &lt;Fehlertext&gt;)</li>
            <li><strong>launchApp</strong> &lt;Anwendung&gt; - Gegenw&auml;rtige aktive Anwendung</li>
            <li><strong>lgKey</strong> - Der Client-Key, der f&uuml;r die Verbindung verwendet wird</li>
            <li><strong>mute</strong> on,off - Der aktuelle Stumm-Status ("on" =&gt; Stumm, "off" =&gt; Laut)</li>
            <li><strong>pairing</strong> paired, unpaired - Der Status des Pairing</li>
            <li><strong>presence </strong>absent, present - Der aktuelle Power-Status ("present" =&gt; eingeschaltet, "absent" =&gt; ausgeschaltet)</li>
            <li><strong>state</strong> on, off - Status des Fernsehers (&auml;hnlich presence)</li>
            <li><strong>volume</strong> - Der aktuelle Lautst&auml;rkepegel -1, 0-100 (-1 invalider Wert)</li>
        </ul>
    </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 82_LGTV_WebOS.pm
{
  "abstract": "Module for Controls LG SmartTVs run with WebOS Operating System",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Steuerung von LG SmartTVs mit WebOS Betriebssystem"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Multimedia",
    "TV",
    "LG"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v3.6.1",
  "author": [
    "Marko Oldenburg <fhemdevelopment@cooltux.net>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 1,
        "JSON": 1,
        "Date::Parse": 0
      },
      "recommends": {
        "JSON": 0
      },
      "suggests": {
        "Cpanel::JSON::XS": 0,
        "JSON::XS": 0
      }
    }
  }
}
=end :application/json;q=META.json

=cut

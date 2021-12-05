###############################################################################
#
# Developed with Kate
#
#  (c) 2016-2021 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
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

#################################
######### Wichtige Hinweise und Links #################

## Beispiel für Logausgabe
# https://forum.fhem.de/index.php/topic,55756.msg508412.html#msg508412

##
#

################################
package FHEM::NUKIBridge;

use strict;
use warnings;

use FHEM::Meta;
require FHEM::Devices::Nuki::Bridge;

sub ::NUKIBridge_Initialize { goto &Initialize }

sub Initialize {
    my ($hash) = @_;

    # Provider
    $hash->{WriteFn}   = \&FHEM::Devices::Nuki::Bridge::Write;
    $hash->{Clients}   = ':NUKIDevice:';
    $hash->{MatchList} = { '1:NUKIDevice' => '^{.*}$' };

    my $webhookFWinstance =
      join( ",", ::devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') );

    # Consumer
    $hash->{SetFn}    = \&FHEM::Devices::Nuki::Bridge::Set;
    $hash->{GetFn}    = \&FHEM::Devices::Nuki::Bridge::Get;
    $hash->{DefFn}    = \&FHEM::Devices::Nuki::Bridge::Define;
    $hash->{UndefFn}  = \&FHEM::Devices::Nuki::Bridge::Undef;
    $hash->{NotifyFn} = \&FHEM::Devices::Nuki::Bridge::Notify;
    $hash->{AttrFn}   = \&FHEM::Devices::Nuki::Bridge::Attr;
    $hash->{AttrList} =
        'disable:1 ' . 'port '
      . 'webhookFWinstance:'
      . $webhookFWinstance . ' '
      . 'webhookHttpHostname '
      . $::readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;

=pod
=item device
=item summary    Modul to control the Nuki Smartlock's over the Nuki Bridge.
=item summary_DE Modul zur Steuerung des Nuki Smartlock über die Nuki Bridge.

=begin html

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - controls the Nuki Smartlock over the Nuki Bridge</b></u>
  <br>
  The Nuki Bridge module connects FHEM to the Nuki Bridge and then reads all the smartlocks available on the bridge. Furthermore, the detected Smartlocks are automatically created as independent devices.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    This statement creates a NUKIBridge device with the name NBridge1 and the IP 192.168.0.23 as well as the token F34HK6.<br>
    After the bridge device is created, all available Smartlocks are automatically placed in FHEM.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>bridgeAPI - API Version of bridge</li>
    <li>bridgeType - Hardware bridge / Software bridge</li>
    <li>currentTime - Current timestamp</li>
    <li>firmwareVersion - Version of the bridge firmware</li>
    <li>hardwareId - Hardware ID</li>
    <li>lastError - Last connected error</li>
    <li>serverConnected - Flag indicating whether or not the bridge is connected to the Nuki server</li>
    <li>serverId - Server ID</li>
    <li>uptime - Uptime of the bridge in seconds</li>
    <li>wifiFirmwareVersion- Version of the WiFi modules firmware</li>
    <br>
    The preceding number is continuous, starts with 0 und returns the properties of <b>one</b> Smartlock.
   </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>getDeviceList - Prompts to re-read all devices from the bridge and if not already present in FHEM, create the automatically.</li>
    <li>callbackRemove -  Removes a previously added callback</li>
    <li>clearLog - Clears the log of the Bridge (only hardwarebridge)</li>
    <li>factoryReset - Performs a factory reset (only hardwarebridge)</li>
    <li>fwUpdate -  Immediately checks for a new firmware update and installs it (only hardwarebridge)</li>
    <li>info -  Returns all Smart Locks in range and some device information of the bridge itself</li>
    <li>reboot - reboots the bridge (only hardwarebridge)</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeget"></a>
  <b>Get</b>
  <ul>
    <li>callbackList - List of register url callbacks.</li>
    <li>logFile - Retrieves the log of the Bridge</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki Bridge</li>
    <li>webhookFWinstance - Webinstanz of the Callback</li>
    <li>webhookHttpHostname - IP or FQDN of the FHEM Server Callback</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - Steuert das Nuki Smartlock über die Nuki Bridge</b></u>
  <br>
  Das Nuki Bridge Modul verbindet FHEM mit der Nuki Bridge und liest dann alle auf der Bridge verf&uuml;gbaren Smartlocks ein. Desweiteren werden automatisch die erkannten Smartlocks als eigenst&auml;ndige Devices an gelegt.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIBridge Device mit Namen NBridge1 und der IP 192.168.0.23 sowie dem Token F34HK6.<br>
    Nach dem anlegen des Bridge Devices werden alle zur verf&uuml;gung stehende Smartlock automatisch in FHEM an gelegt.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>bridgeAPI - API Version der Bridge</li>
    <li>bridgeType - Hardware oder Software/App Bridge</li>
    <li>currentTime - aktuelle Zeit auf der Bridge zum zeitpunkt des Info holens</li>
    <li>firmwareVersion - aktuell auf der Bridge verwendete Firmwareversion</li>
    <li>hardwareId - ID der Hardware Bridge</li>
    <li>lastError - gibt die letzte HTTP Errormeldung wieder</li>
    <li>serverConnected - true/false gibt an ob die Hardwarebridge Verbindung zur Nuki-Cloude hat.</li>
    <li>serverId - gibt die ID des Cloudeservers wieder</li>
    <li>uptime - Uptime der Bridge in Sekunden</li>
    <li>wifiFirmwareVersion- Firmwareversion des Wifi Modules der Bridge</li>
    <br>
    Die vorangestellte Zahl ist forlaufend und gibt beginnend bei 0 die Eigenschaften <b>Eines</b> Smartlocks wieder.
  </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>getDeviceList - Veranlasst ein erneutes Einlesen aller Devices von der Bridge und falls noch nicht in FHEM vorhanden das automatische anlegen.</li>
    <li>callbackRemove - L&ouml;schen der Callback Instanz auf der Bridge.</li>
    <li>clearLog - l&ouml;scht das Logfile auf der Bridge</li>
    <li>fwUpdate - schaut nach einer neueren Firmware und installiert diese sofern vorhanden</li>
    <li>info - holt aktuellen Informationen &uuml;ber die Bridge</li>
    <li>reboot - veranl&auml;sst ein reboot der Bridge</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeget"></a>
  <b>Get</b>
  <ul>
    <li>callbackList - Gibt die Liste der eingetragenen Callback URL's wieder.</li>
    <li>logFile - Zeigt das Logfile der Bridge an</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert die Nuki Bridge</li>
    <li>webhookFWinstance - zu verwendene Webinstanz für den Callbackaufruf</li>
    <li>webhookHttpHostname - IP oder FQDN vom FHEM Server für den Callbackaufruf</li>
    <br>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 73_NUKIBridge.pm
{
  "abstract": "Modul to control the Nuki Smartlock's over the Nuki Bridge",
  "x_lang": {
    "de": {
      "abstract": "Modul to control the Nuki Smartlock's over the Nuki Bridge"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Smartlock",
    "Nuki",
    "Control"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.0.0",
  "x_apiversion": "1.12.3",
  "author": [
    "Marko Oldenburg <leongaultier@gmail.com>"
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

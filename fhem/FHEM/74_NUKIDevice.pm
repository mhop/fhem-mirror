###############################################################################
#
# Developed with VSCodium and richterger perl plugin
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
package FHEM::NUKIDevice;

use strict;
use warnings;

use FHEM::Meta;
require FHEM::Devices::Nuki::Device;

use GPUtils qw(GP_Import);

BEGIN {

    # Import from main context
    GP_Import(qw( readingFnAttributes ));
}

main::LoadModule('NUKIBridge');

sub ::NUKIDevice_Initialize { goto &Initialize }

sub Initialize {
    my ($hash) = @_;

    $hash->{Match} = '^{.*}$';

    $hash->{SetFn}    = \&FHEM::Devices::Nuki::Device::Set;
    $hash->{DefFn}    = \&FHEM::Devices::Nuki::Device::Define;
    $hash->{UndefFn}  = \&FHEM::Devices::Nuki::Device::Undef;
    $hash->{NotifyFn} = \&FHEM::Devices::Nuki::Device::Notify;
    $hash->{AttrFn}   = \&FHEM::Devices::Nuki::Device::Attr;
    $hash->{ParseFn}  = \&FHEM::Devices::Nuki::Device::Parse;

    $hash->{AttrList} =
        'IODev '
      . 'model:smartlock,opener,smartdoor,smartlock3 '
      . 'disable:1 '
      . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;

=pod
=item device
=item summary    Modul to control the Nuki Smartlock's
=item summary_DE Modul zur Steuerung des Nuki Smartlocks.

=begin html

<a name="NUKIDevice"></a>
<h3>NUKIDevice</h3>
<ul>
  <u><b>NUKIDevice - Controls the Nuki Smartlock</b></u>
  <br>
  The Nuki module connects FHEM over the Nuki Bridge with a Nuki Smartlock or Nuki Opener. After that, it´s possible to control your Nuki devices<br>
  Normally the Nuki devices are automatically created by the bridge module.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt; &lt;Device-Type&gt;</code>
    <br><br>
    Device-Type is 0/4 for the Smartlock and 2 for the Opener.
    <br><br>
    Example:
    <ul><br>
      <code>define Frontdoor NUKIDevice 1 NBridge1 0</code><br>
    </ul>
    <br>
    This statement creates a NUKIDevice with the name Frontdoor, the NukiId 1 and the IODev device NBridge1.<br>
    After the device has been created, the current state of the Smartlock is automatically read from the bridge.
  </ul>
  <br><br>
  <a name="NUKIDevicereadings"></a>
  <b>Readings</b>
  <br>Smartlock
    <ul>
        <li>batteryCharging - is the battery charging true/false.</li>
        <li>batteryPercent - current battry state in percent.</li>
        <li>batteryState - battery state ok/low</li>
        <li>deviceType - type name of nuki device smartlock/smartlock3/opener</li>
        <li>firmwareVersion - version of device firmware</li>
        <li>name - name of the device</li>
        <li>nukiid - id of the nuki device</li>
        <li>paired - paired information false/true</li>
        <li>rssi - value of rssi</li>
        <li>state - Status of the Smartlock or error message if any error.</li>
        <li>stateName - Status of the Smartlock or error message if any error.</li>
        <li>succes - true, false   Returns the status of the last closing command. Ok or not Ok.</li>
    </ul>
    <br>Opener
    <ul>
        <li>batteryState - battery state ok/low</li>
        <li>deviceType - type name of nuki device smartlock/smartlock3/opener</li>
        <li>firmwareVersion - version of device firmware</li>
        <li>mode - Operation mode (door mode/continuous mode)</li>
        <li>name - name of the device</li>
        <li>nukiid - id of the nuki device</li>
        <li>paired - paired information false/true</li>
        <li>ringactionState - state of ring (0/1)</li>
        <li>ringactionTimestamp - timestamp of ring</li>
        <li>rssi - value of rssi</li>
        <li>state - Status of the Smartlock or error message if any error.</li>
        <li>stateName - Status of the Smartlock or error message if any error.</li>
        <li>succes - true, false   Returns the status of the last closing command. Ok or not Ok.</li>
    </ul>
    <br><br>
    <a name="NUKIDeviceset"></a>
    <b>Set</b>
    <br>Smartlock
    <ul>
        <li>statusRequest - retrieves the current state of the smartlock from the bridge.</li>
        <li>lock - lock</li>
        <li>unlock - unlock</li>
        <li>unlatch - unlock / open Door</li>
        <li>unpair -  Removes the pairing with a given Smart Lock</li>
        <li>locknGo - lock when gone</li>
        <li>locknGoWithUnlatch - lock after the door has been opened</li>
    </ul>
    <br>Opener
    <ul>
        <li>statusRequest - retrieves the current state of the smartlock from the bridge.</li>
        <li>activateRto - activate ring to open mode / ringing the bell activates the electric strike actuation </li>
        <li>deactivateRto - deactivate ring to open mode</li>
        <li>electricStrikeActuation - electric strike actuation</li>
        <li>activateContinuousMode -  activate Nuki Opener Mode with Ring to Open continuously</li>
        <li>deactivateContinuousMode - deactivate Ring to Open continuously</li>
    </ul>
    <br><br>
    <a name="NUKIDeviceattribut"></a>
    <b>Attributes</b>
    <ul>
        <li>disable - disables the Nuki device</li>
        <br>
    </ul>
</ul>

=end html
=begin html_DE

<a name="NUKIDevice"></a>
<h3>NUKIDevice</h3>
<ul>
  <u><b>NUKIDevice - Zur Steuerung von Nuki Ger&auml;te</b></u>
  <br>
  Das Nuki Modul verbindet FHEM &uuml;ber die Nuki Bridge mit einem Nuki Smartlock oder Opener. Nach der Einrichtung k&ouml;nnen diese Ger&auml;te gesteuert werden.<br>
  Die Nuki Ger&auml;te werden automatisch nach dem erstellen der Nuki Bridge in FHEM eingerichtet.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt; &lt;Device-Type&gt;</code>
    <br><br>
    Der Device-Type kann 0/4 f&uuml;r ein Smartlock sein oder 2 f&uuml;r den Opener.
    <br><br>
    Example:
    <ul><br>
      <code>define Frontdoor NUKIDevice 1 NBridge1 0</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIDevice mit Namen Haust&uuml;r, der NukiId 1 sowie dem IODev Device NBridge1.<br>
    Nach dem anlegen des Devices wird automatisch der aktuelle Zustand des Smartlocks aus der Bridge gelesen.
  </ul>
  <br><br>
  <a name="NUKIDevicereadings"></a>
  <b>Readings</b>
  <br>Smartlock
    <ul>
        <li>batteryCharging - wird die Batterie geladen true/false.</li>
        <li>batteryPercent - aktueller Ladestand der Batterie.</li>
        <li>batteryState - Staus der Batterie ok/low</li>
        <li>deviceType - der Typenname des Nuki Ger&auml;tes smartlock/smartlock3/opener</li>
        <li>firmwareVersion - Version der Ger&auml;te Firmware</li>
        <li>name - Name des Nuki Ger&auml;tes</li>
        <li>nukiid - die Ger&auml;te Id</li>
        <li>paired - paired Informationen false/true</li>
        <li>rssi - Wert f&uuml;r die empfangene Signalst&auml;rke</li>
        <li>state - Status des Smartlock bzw . Fehlermeldung von Fehler vorhanden.</li>
        <li>succes - true, false. Gibt den Status des letzen Befehls zur&uuml;ck.</li>
    </ul>
  <br>Opener
    <ul>
        <li>batteryCharging - wird die Batterie geladen true/false.</li>
        <li>batteryPercent - aktueller Ladestand der Batterie.</li>
        <li>batteryState - Staus der Batterie ok/low</li>
        <li>deviceType - der Typenname des Nuki Ger&auml;tes smartlock/smartlock3/opener</li>
        <li>firmwareVersion - Version der Ger&auml;te Firmware</li>
        <li>name - Name des Nuki Ger&auml;tes</li>
        <li>nukiid - die Ger&auml;te Id</li>
        <li>paired - paired Informationen false/true</li>
        <li>ringactionState - Status der Klingel. Wurde eben geklingelt (0/1)</li>
        <li>ringactionTimestamp - Zeitstempel des klingelns</li>
        <li>rssi - Wert f &uuml;r die empfangene Signalst &auml;rke</li>
        <li>state - Status des Opener bzw . Fehlermeldung von Fehler vorhanden.</li>
        <li>succes - true, false. Gibt den Status des letzen Befehls zur&uuml;ck.</li>
    </ul>
    <br><br>
    <a name="NUKIDeviceset"></a>
    <b>Set</b>
    <br>Smartlock
    <ul>
        <li>statusRequest - ruft den aktuellen Status des Smartlocks von der Bridge ab.</li>
        <li>lock - verschlie&szlig;en</li>
        <li>unlock - aufschlie&szlig;en</li>
        <li>unlatch - entriegeln/Falle &ouml;ffnen.</li>
        <li>unpair -  entfernt das pairing mit dem Smart Lock</li>
        <li>locknGo - verschlie&szlig;en wenn gegangen</li>
        <li>locknGoWithUnlatch - verschlie&szlig;en nach dem die Falle ge&ouml;ffnet wurde.</li>
    </ul>
    <br>Opener
    <ul>
        <li>statusRequest - ruft den aktuellen Status des Opener von der Bridge ab.</li>
        <li>activateRto - aktiviert den ring to open Modus / ein klingeln aktiviert den T&uuml;r&ouml;ffner</li>
        <li>deactivateRto - deaktiviert den ring to open Modus</li>
        <li>electricStrikeActuation - aktiviert den T&uuml;r&ouml;ffner</li>
        <li>activateContinuousMode -  aktiviert dauerhaft &ouml;ffnen der T&uuml;r durch klingeln Modus</li>
        <li>deactivateContinuousMode - deaktiviert diesen Modus</li>
    </ul>
    <br><br>
    <a name="NUKIDeviceattribut"></a>
    <b>Attributes</b>
    <ul>
        <li>disable - disables the Nuki device</li>
        <br>
    </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 74_NUKIDevice.pm
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
  "version": "v2.0.2",
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
        "perl": 5.024, 
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

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
package FHEM::NUKIDevice;

use strict;
use warnings;

use FHEM::Meta;
require FHEM::Devices::Nuki::Device;

main::LoadModule('NUKIBridge');

sub ::NUKIDevice_Initialize { goto &Initialize }

sub Initialize($) {
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
      . $::readingFnAttributes;

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
  The Nuki module connects FHEM over the Nuki Bridge with a Nuki Smartlock or Nuki Opener. After that, it´s possible to lock and unlock the Smartlock.<br>
  Normally the Nuki devices are automatically created by the bridge module.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt; &lt;Device-Type&gt;</code>
    <br><br>
    Device-Type is 0 for the Smartlock and 2 for the Opener.
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
  <ul>
    <li>state - Status of the Smartlock or error message if any error.</li>
    <li>lockState - current lock status uncalibrated, locked, unlocked, unlocked (lock ‘n’ go), unlatched, locking, unlocking, unlatching, motor blocked, undefined.</li>
    <li>name - name of the device</li>
    <li>paired - paired information false/true</li>
    <li>rssi - value of rssi</li>
    <li>succes - true, false   Returns the status of the last closing command. Ok or not Ok.</li>
    <li>batteryCritical - Is the battery in a critical state? True, false</li>
    <li>batteryState - battery status, ok / low</li>
  </ul>
  <br><br>
  <a name="NUKIDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - retrieves the current state of the smartlock from the bridge.</li>
    <li>lock - lock</li>
    <li>unlock - unlock</li>
    <li>unlatch - unlock / open Door</li>
    <li>unpair -  Removes the pairing with a given Smart Lock</li>
    <li>locknGo - lock when gone</li>
    <li>locknGoWithUnlatch - lock after the door has been opened</li>
    <br>
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
  <u><b>NUKIDevice - Steuert das Nuki Smartlock</b></u>
  <br>
  Das Nuki Modul verbindet FHEM über die Nuki Bridge  mit einem Nuki Smartlock oder Nuki Opener. Es ist dann m&ouml;glich das Schloss zu ver- und entriegeln.<br>
  In der Regel werden die Nuki Devices automatisch durch das Bridgemodul angelegt.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt; &lt;Device-Type&gt;</code>
    <br><br>
    Device-Type ist 0 f&uuml;r das Smartlock und 2 f&üuml;r den Opener.
    <br><br>
    Beispiel:
    <ul><br>
      <code>define Haust&uuml;r NUKIDevice 1 NBridge1 0</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIDevice mit Namen Haust&uuml;r, der NukiId 1 sowie dem IODev Device NBridge1.<br>
    Nach dem anlegen des Devices wird automatisch der aktuelle Zustand des Smartlocks aus der Bridge gelesen.
  </ul>
  <br><br>
  <a name="NUKIDevicereadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status des Smartlock bzw. Fehlermeldung von Fehler vorhanden.</li>
    <li>lockState - aktueller Schlie&szlig;status uncalibrated, locked, unlocked, unlocked (lock ‘n’ go), unlatched, locking, unlocking, unlatching, motor blocked, undefined.</li>
    <li>name - Name des Smart Locks</li>
    <li>paired - pairing Status des Smart Locks</li>
    <li>rssi - rssi Wert des Smart Locks</li>
    <li>succes - true, false Gibt des Status des letzten Schlie&szlig;befehles wieder. Geklappt oder nicht geklappt.</li>
    <li>batteryCritical - Ist die Batterie in einem kritischen Zustand? true, false</li>
    <li>batteryState - Status der Batterie, ok/low</li>
  </ul>
  <br><br>
  <a name="NUKIDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - ruft den aktuellen Status des Smartlocks von der Bridge ab.</li>
    <li>lock - verschlie&szlig;en</li>
    <li>unlock - aufschlie&szlig;en</li>
    <li>unlatch - entriegeln/Falle &ouml;ffnen.</li>
    <li>unpair -  entfernt das pairing mit dem Smart Lock</li>
    <li>locknGo - verschlie&szlig;en wenn gegangen</li>
    <li>locknGoWithUnlatch - verschlie&szlig;en nach dem die Falle ge&ouml;ffnet wurde.</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIDeviceattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Nuki Device</li>
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
  "version": "v2.0.0",
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

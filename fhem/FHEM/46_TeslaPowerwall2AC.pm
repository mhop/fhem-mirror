###############################################################################
#
# Developed with Kate
#
#  (c) 2017-2021 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
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
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#######
#######
#  URLs zum Abrufen diverser Daten
# https://<ip-Powerwall>/api/system_status/soe
# https://<ip-Powerwall>/api/meters/aggregates
# https://<ip-Powerwall>/api/site_info
# https://<ip-Powerwall>/api/sitemaster
# https://<ip-Powerwall>/api/powerwalls
# https://<ip-Powerwall>/api/networks
# https://<ip-Powerwall>/api/system/networks
# https://<ip-Powerwall>/api/operation
#
##
##

package FHEM::TeslaPowerwall2AC;

use strict;
use warnings;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);

require FHEM::Tesla::Powerwall;

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          readingFnAttributes
          )
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      )
);

sub Initialize {

    my $hash            = shift;

    $hash->{GetFn}          = 'FHEM::Tesla::Powerwall::Get';
    $hash->{SetFn}          = 'FHEM::Tesla::Powerwall::Set';
    $hash->{DefFn}          = 'FHEM::Tesla::Powerwall::Define';
    $hash->{UndefFn}        = 'FHEM::Tesla::Powerwall::Undef';
    $hash->{NotifyFn}       = 'FHEM::Tesla::Powerwall::Notify';
    $hash->{RenameFn}       = 'FHEM::Tesla::Powerwall::Rename';

    $hash->{AttrFn}         = 'FHEM::Tesla::Powerwall::Attr';
    $hash->{AttrList}       =
                      'interval '
                    . 'disable:1 '
                    . 'devel:1 '
                    . 'emailaddr '
                    . $readingFnAttributes;

    $hash->{parseParams}    = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

1;


=pod

=item device
=item summary       Modul to retrieves data from a Tesla Powerwall 2AC
=item summary_DE 

=begin html

<a name="TeslaPowerwall2AC"></a>
<h3>Tesla Powerwall 2 AC</h3>
<ul>
    <u><b>TeslaPowerwall2AC - Retrieves data from a Tesla Powerwall 2AC System</b></u>
    <br>
    With this module it is possible to read the data from a Tesla Powerwall 2AC and to set it as reading.
    <br><br>
    <a name="TeslaPowerwall2ACdefine"></a>
    <b>Define</b>
    <ul><br>
        <code>define &lt;name&gt; TeslaPowerwall2AC &lt;HOST&gt;</code>
    <br><br>
    Example:
    <ul><br>
        <code>define myPowerWall TeslaPowerwall2AC 192.168.1.34</code><br>
    </ul>
    <br>
    This statement creates a Device with the name myPowerWall and the Host IP 192.168.1.34.<br>
    After the device has been created, the current data of Powerwall is automatically read from the device.
    </ul>
    <br><br>
    <a name="TeslaPowerwall2ACreadings"></a>
    <b>Readings</b>
    <ul>
        <li>actionQueue     - information about the entries in the action queue</li>
        <li>aggregates-*    - readings of the /api/meters/aggregates response</li>
        <li>batteryLevel    - battery level in percent</li>
        <li>batteryPower    - battery capacity in kWh</li>
        <li>powerwalls-*    - readings of the /api/powerwalls response</li>
        <li>registration-*  - readings of the /api/customer/registration response</li>
        <li>siteinfo-*      - readings of the /api/site_info response</li>
        <li>sitemaster-*    - readings of the /api/sitemaster response</li>
        <li>state           - information about internel modul processes</li>
        <li>status-*        - readings of the /api/status response</li>
        <li>statussoe-*     - readings of the /api/system_status/soe response</li>
        <li>setPassword     - write password encrypted to password file</li>
        <li>removePassword  - remove password from password file</li>
    </ul>
    <a name="TeslaPowerwall2ACget"></a>
    <b>get</b>
    <ul>
        <li>aggregates      - fetch data from url path /api/meters/aggregates</li>
        <li>powerwalls      - fetch data from url path /api/powerwalls</li>
        <li>registration    - fetch data from url path /api/customer/registration</li>
        <li>siteinfo        - fetch data from url path /api/site_info</li>
        <li>sitemaster      - fetch data from url path /api/sitemaster</li>
        <li>status          - fetch data from url path /api/status</li>
        <li>statussoe       - fetch data from url path /api/system_status/soe</li>
    </ul>
    <br><br>
    <a name="TeslaPowerwall2ACset"></a>
    <b>set</b>
    <ul>
        <li>removePassword  - remove password from password file</li>
        <li>setPassword     - save password in passswordfile ATTANTION!!! text must begin with pass= (Example: pass=meinpassword)</li>
    </ul>
    <br><br>
    <a name="TeslaPowerwall2ACattribute"></a>
    <b>Attribute</b>
    <ul>
        <li>interval - interval in seconds for automatically fetch data (default 300)</li>
        <li>emailaddr - emailadress to get cookie token</li>
    </ul>
</ul>

=end html
=begin html_DE

<a name="TeslaPowerwall2AC"></a>
<h3>Tesla Powerwall 2 AC</h3>

=end html_DE

=for :application/json;q=META.json 46_TeslaPowerwall2AC.pm
{
  "abstract": "Modul to retrieves data from a Tesla Powerwall 2AC",
  "x_lang": {
    "de": {
      "abstract": ""
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Power",
    "Tesla",
    "AC",
    "Powerwall",
    "Control"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v1.2.0",
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

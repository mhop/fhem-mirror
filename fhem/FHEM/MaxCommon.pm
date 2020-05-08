##############################################
# $Id$
# 
#  (c) 2012 Copyright: Matthias Gehre, M.Gehre@gmx.de
#  (c) 2019 Copyright: Wzut
#
#  All rights reserved
#
#  FHEM Forum : http://forum.fhem.de/
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
################################################################

package MaxCommon;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(%device_types %msgId2Cmd %msgCmd2Id $defaultWeekProfile validTemperature);

%device_types = (
  0 => "Cube",
  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton",
  6 => "virtualShutterContact",
  7 => "virtualThermostat",
  8 => "PlugAdapter"
);

%msgId2Cmd = (
                 "00" => "PairPing",
                 "01" => "PairPong",
                 "02" => "Ack",
                 "03" => "TimeInformation",

                 "10" => "ConfigWeekProfile",
                 "11" => "ConfigTemperatures", #like eco/comfort etc
                 "12" => "ConfigValve",

                 "20" => "AddLinkPartner",
                 "21" => "RemoveLinkPartner",
                 "22" => "SetGroupId",
                 "23" => "RemoveGroupId",

                 "30" => "ShutterContactState",

                 "40" => "SetTemperature", # to thermostat
                 "42" => "WallThermostatControl", # by WallMountedThermostat
                 # Sending this without payload to thermostat sets desiredTempeerature to the comfort/eco temperature
                 # We don't use it, we just do SetTemperature
                 "43" => "SetComfortTemperature",
                 "44" => "SetEcoTemperature",

                 "50" => "PushButtonState",

                 "60" => "ThermostatState", # by HeatingThermostat

                 "70" => "WallThermostatState",

                 "82" => "SetDisplayActualTemperature",

                 "F1" => "WakeUp",
                 "F0" => "Reset",
               );

%msgCmd2Id = reverse %msgId2Cmd;

my $defaultWeekProfile = "444855084520452045204520452045204520452045204520452044485508452045204520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc5514452045204520452045204520452045204520";


sub validTemperature { return $_[0] eq "on" || $_[0] eq "off" || ($_[0] =~ /^\d+(\.[05])?$/ && $_[0] >= 4.5 && $_[0] <= 30.5); }

# Identify for numeric values and maps "on" and "off" to their temperatures
#sub MAX_ParseTemperature
#{
  #return $_[0] eq "on" ? 30.5 : ($_[0] eq "off" ? 4.5 :$_[0]);
#}

1;

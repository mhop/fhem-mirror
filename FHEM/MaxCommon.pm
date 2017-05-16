package MaxCommon;

require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw(%device_types %msgId2Cmd %msgCmd2Id $defaultWeekProfile);

%device_types = (
  0 => "Cube",
  1 => "HeatingThermostat",
  2 => "HeatingThermostatPlus",
  3 => "WallMountedThermostat",
  4 => "ShutterContact",
  5 => "PushButton"
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

                 "40" => "SetTemperature", #to thermostat
                 "42" => "WallThermostatControl", #by WallMountedThermostat
                 #Sending this without payload to thermostat sets desiredTempeerature to the comfort/eco temperature
                 #We don't use it, we just do SetTemperature
                 "43" => "SetComfortTemperature",
                 "44" => "SetEcoTemperature",

                 "50" => "PushButtonState",

                 "60" => "ThermostatState", #by HeatingThermostat

                 "70" => "WallThermostatState",

                 "82" => "SetDisplayActualTemperature",

                 "F1" => "WakeUp",
                 "F0" => "Reset",
               );
%msgCmd2Id = reverse %msgId2Cmd;

$defaultWeekProfile = "444855084520452045204520452045204520452045204520452044485508452045204520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc55144520452045204520452045204520452045204448546c44cc5514452045204520452045204520452045204520";

1;

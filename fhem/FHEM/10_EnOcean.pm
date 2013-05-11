##############################################
# $Id$

package main;

use strict;
use warnings;
use SetExtensions;

sub EnOcean_Define($$);
sub EnOcean_Initialize($);
sub EnOcean_Parse($$);
sub EnOcean_Set($@);
sub EnOcean_MD15Cmd($$$);

my %EnO_rorgname = ("F6" => "switch",     # org 05, RPS
                    "D5" =>" contact",    # org 06, 1BS
                    "A5" => "sensor",     # org 07, 4BS
                   );
my @EnO_ptm200btn = ("AI", "A0", "BI", "B0", "CI", "C0", "DI", "D0");
my %EnO_ptm200btn;

# Gateway Commands
my @EnO_gwCmd = ("switching", "dimming", "setpointShift", "setpointBasic", "controlVar", "fanStage", "blindCmd");
my %EnO_gwCmd = (
  "switching"     => 1,
  "dimming"       => 2,
  "setpointShift" => 3,
  "setpointBasic" => 4,
  "controlVar"    => 5,
  "fanStage"      => 6,
  "blindCmd"      => 7,
);

# Some Manufacturers (e.g. Jaeger Direkt) also sell EnOcean products without an
# entry in the table below. This table is only needed for 4BS category devices.
my %EnO_manuf = (
  "001" => "Peha",
  "002" => "Thermokon",
  "003" => "Servodan",
  "004" => "EchoFlex Solutions",
  "005" => "Omnio AG",
  "006" => "Hardmeier electronics",
  "007" => "Regulvar Inc",
  "008" => "Ad Hoc Electronics",
  "009" => "Distech Controls",
  "00A" => "Kieback + Peter",
  "00B" => "EnOcean GmbH",
  "00C" => "Probare",
  "00D" => "Eltako",
  "00E" => "Leviton",
  "00F" => "Honeywell",
  "010" => "Spartan Peripheral Devices",
  "011" => "Siemens",
  "012" => "T-Mac",
  "013" => "Reliable Controls Corporation",
  "014" => "Elsner Elektronik GmbH",
  "015" => "Diehl Controls",
  "016" => "BSC Computer",
  "017" => "S+S Regeltechnik GmbH",
  "018" => "Masco Corporation",
  "019" => "Intesis Software SL",
  "01A" => "Res.",
  "01B" => "Lutuo Technology",
  "01C" => "CAN2GO",
  "7FF" => "Multi user Manufacturer ID",
);

my %EnO_subType = (
  "A5.02.01" => "tempSensor.01",
  "A5.02.02" => "tempSensor.02",
  "A5.02.03" => "tempSensor.03",
  "A5.02.04" => "tempSensor.04",
  "A5.02.05" => "tempSensor.05",
  "A5.02.06" => "tempSensor.06",
  "A5.02.07" => "tempSensor.07",
  "A5.02.08" => "tempSensor.08",
  "A5.02.09" => "tempSensor.09",
  "A5.02.0A" => "tempSensor.0A",
  "A5.02.0B" => "tempSensor.0B",
  "A5.02.10" => "tempSensor.10",
  "A5.02.11" => "tempSensor.11",
  "A5.02.12" => "tempSensor.12",
  "A5.02.13" => "tempSensor.13",
  "A5.02.14" => "tempSensor.14",
  "A5.02.15" => "tempSensor.15",
  "A5.02.16" => "tempSensor.16",
  "A5.02.17" => "tempSensor.17",
  "A5.02.18" => "tempSensor.18",
  "A5.02.19" => "tempSensor.19",
  "A5.02.1A" => "tempSensor.1A",
  "A5.02.1B" => "tempSensor.1B",
  "A5.02.20" => "tempSensor.20",
  "A5.02.30" => "tempSensor.30",
  "A5.04.01" => "roomSensorControl.01",
  "A5.04.02" => "tempHumiSensor.02",
  "A5.06.01" => "lightSensor.01",
  "A5.06.02" => "lightSensor.02",
  "A5.06.03" => "lightSensor.03",
  "A5.07.01" => "occupSensor.01",
  "A5.07.02" => "occupSensor.02",
  "A5.07.03" => "occupSensor.03",
  "A5.08.01" => "lightTempOccupSensor.01",
  "A5.08.02" => "lightTempOccupSensor.02",
  "A5.08.03" => "lightTempOccupSensor.03",
  "A5.09.01" => "COSensor.01",
  "A5.09.04" => "tempHumiCO2Sensor.01",
  "A5.09.05" => "vocSensor.01",
  "A5.09.06" => "radonSensor.01",
  "A5.09.07" => "particlesSensor.01",
  "A5.10.01" => "roomSensorControl.05",
  "A5.10.02" => "roomSensorControl.05",
  "A5.10.03" => "roomSensorControl.05",
  "A5.10.04" => "roomSensorControl.05",
  "A5.10.05" => "roomSensorControl.05",
  "A5.10.06" => "roomSensorControl.05",
  "A5.10.07" => "roomSensorControl.05",
  "A5.10.08" => "roomSensorControl.05",
  "A5.10.09" => "roomSensorControl.05",
  "A5.10.0A" => "roomSensorControl.05",
  "A5.10.0B" => "roomSensorControl.05",
  "A5.10.0C" => "roomSensorControl.05",
  "A5.10.0D" => "roomSensorControl.05",
  "A5.10.10" => "roomSensorControl.01",
  "A5.10.11" => "roomSensorControl.01",
  "A5.10.12" => "roomSensorControl.01",
  "A5.10.13" => "roomSensorControl.01",
  "A5.10.14" => "roomSensorControl.01",
  "A5.10.15" => "roomSensorControl.02",
  "A5.10.16" => "roomSensorControl.02",
  "A5.10.17" => "roomSensorControl.02",
  "A5.10.18" => "roomSensorControl.18",
  "A5.10.19" => "roomSensorControl.19",
  "A5.10.1A" => "roomSensorControl.1A",
  "A5.10.1B" => "roomSensorControl.1B",
  "A5.10.1C" => "roomSensorControl.1C",
  "A5.10.1D" => "roomSensorControl.1D",
  "A5.10.1E" => "roomSensorControl.1B",
  "A5.10.1F" => "roomSensorControl.1F",
  "A5.11.01" => "lightCtrlState.01",
  "A5.11.02" => "tempCtrlState.01",
  "A5.11.03" => "shutterCtrlState.01",
  "A5.11.04" => "lightCtrlState.02",
  "A5.12.00" => "autoMeterReading.00",
  "A5.12.01" => "autoMeterReading.01",
  "A5.12.02" => "autoMeterReading.02",
  "A5.12.03" => "autoMeterReading.03",
  "A5.13.01" => "environmentApp",
  "A5.13.02" => "environmentApp",
  "A5.13.03" => "environmentApp",
  "A5.13.04" => "environmentApp",
  "A5.13.05" => "environmentApp",
  "A5.13.06" => "environmentApp",
  "A5.13.10" => "environmentApp",
  "A5.14.01" => "multiFuncSensor",
  "A5.14.02" => "multiFuncSensor",
  "A5.14.03" => "multiFuncSensor",
  "A5.14.04" => "multiFuncSensor",
  "A5.14.05" => "multiFuncSensor",
  "A5.14.06" => "multiFuncSensor",
  "A5.20.01" => "MD15",
  "A5.30.01" => "digitalInput.01",
  "A5.30.02" => "digitalInput.02",
  "A5.38.08" => "gateway",
  "A5.3F.7F" => "manufProfile",
  1          => "switch",
  2          => "contact",
  3          => "sensor",
  4          => "windowHandle",
  5          => "eltakoDimmer",
  6          => "eltakoShutter",
  7          => "FAH",
  8          => "FBH",
  9          => "FTF",
 10          => "SR04",
 11          => "FRW",
 12          => "keycard",
 13          => "raw",
);

my @EnO_models = qw (
  other
  FAH60 FAH63 FIH63
  FABH63 FBH55 FBH63 FIBH63
  FSB14 FSB61 FSB70
  FSG70
  FSM12 FSM61
  FT55
  FTF55
  FTS12
  PM101
  SR04 SR04P SR04T SR04PT SR04PMS SR04PS SR04PST
);

# Initialize
sub
EnOcean_Initialize($)
{
  my ($hash) = @_;
  my %subTypeList;
  my %subTypeSetList;  

  $hash->{Match}     = "^EnOcean:";
  $hash->{DefFn}     = "EnOcean_Define";
  $hash->{UndefFn}   = "EnOcean_Undef";
  $hash->{ParseFn}   = "EnOcean_Parse";
  $hash->{SetFn}     = "EnOcean_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 ".
                       "actualTemp dimTime dimValueOn ".
                       "model:".join(",", @EnO_models)." ".
                       "gwCmd:".join(",", sort @EnO_gwCmd)." ".
                       "manufID:".join(",", keys %EnO_manuf)." ". 
                       "rampTime ".
                       "repeatingAllowed:yes,no ".
                       "shutTime subDef subDef0 subDefI ".
                       "subType:".join(",", sort grep { !$subTypeList{$_}++ } values %EnO_subType)." ".
                       "subTypeSet:".join(",", sort grep { !$subTypeSetList{$_}++ } values %EnO_subType)." ".
                       "switchMode:switch,pushbutton ".
                       "switchType:direction,universal,central ".
                       $readingFnAttributes;

  for(my $i=0; $i<@EnO_ptm200btn;$i++) {
    $EnO_ptm200btn{$EnO_ptm200btn[$i]} = "$i:30";
  }
  $EnO_ptm200btn{released} = "0:20";
  return undef;
}

# Define
sub
EnOcean_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};
  return "wrong syntax: define <name> EnOcean 8-digit-hex-code"
    if(int(@a)!=3 || $a[2] !~ m/^[A-F0-9]{8}$/i);

  $modules{EnOcean}{defptr}{uc($a[2])} = $hash;
  AssignIoPort($hash);
  # Help FHEMWEB split up devices
  $attr{$name}{subType} = $1 if($name =~ m/EnO_(.*)_$a[2]/);
  return undef;
}

# Set
sub
EnOcean_Set($@)
{
  my ($hash, @a) = @_;
  return "no set value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $data;
  my $header;
  my $ll2 = GetLogLevel($name, 2);
  my $manufID = AttrVal($name, "manufID", "");
  my $model = AttrVal($name, "model", "");
  my $repeatingAllowed = AttrVal($name, "repeatingAllowed", "yes");
  my $sendCmd = "yes";
  my $status = "00";
  my $st = AttrVal($name, "subType", "");
  my $stSet = AttrVal($name, "subTypeSet", undef);
  if (defined $stSet) {$st = $stSet;}
  my $subDef = AttrVal($name, "subDef", "$hash->{DEF}");
  my $switchMode = AttrVal($name, "switchMode", "switch");
  my $tn = TimeNow();
  my $updateState = 1;

  shift @a;

  for(my $i = 0; $i < @a; $i++) {
    my $cmd = $a[$i];

    if($st eq "MD15") {
    # Battery Powered Actuator (EEP A5-20-01)
    # [Kieback&Peter MD15-FTL-xx]
    # See also http://www.oscat.de/community/index.php/topic,985.30.html
    # Maintenance commands (runInit, liftSet, valveOpen, valveClosed)
      my %sets = (
        "desired-temp"   => "\\d+(\\.\\d)?",
        "actuator"       => "\\d+",
        "unattended"     => "",
        "initialize"     => "",
        "runInit"        => "",
        "liftSet"        => "",
        "valveOpen"      => "",
        "valveClosed"    => "",
      );
      my $re = $sets{$a[0]};
      return "Unknown argument $cmd, choose one of ".join(" ", sort keys %sets)
        if(!defined($re));
      return "Need a parameter" if ($re && @a < 2);
      return "Argument $a[1] is incorrect (expect $re)"
        if ($re && $a[1] !~ m/^$re$/);

      $hash->{CMD} = $cmd;
      $hash->{READINGS}{CMD}{TIME} = $tn;
      $hash->{READINGS}{CMD}{VAL} = $cmd;

      my $arg = "true";
      if($re) {
        $arg = $a[1];
        shift(@a);
      }

      $hash->{READINGS}{$cmd}{TIME} = $tn;
      $hash->{READINGS}{$cmd}{VAL} = $arg;

    } elsif($st eq "eltakoDimmer") {
      # Dimmer
      my $sendDimCmd=0;
      my $dimTime=AttrVal($name, "dimTime", 1);
      my $onoff=1;
      my $dimVal=$hash->{READINGS}{dimValue}{VAL};

      if($cmd eq "teach") {
        $data = "A502000000";
        $header = "000A0001";
        Log $ll2, "EnOcean: set $name $cmd";

      } elsif($cmd eq "dim") {
        return "Usage: $cmd percent [dimspeed 1-100]" if(@a<2 or $a[1]>100);
        # for eltako relative (0-100) (but not compliant to EEP because DB0.2
        # is 0)
        $dimVal=$a[1];
	readingsSingleUpdate($hash, "dimValueStored", $dimVal, 1);
        shift(@a);
        if(defined($a[1])) {
          $dimTime = sprintf("%X",(($a[1]*2.55)-255)*-1);
          shift(@a);
        }
        $sendDimCmd=1;

      } elsif($cmd eq "dimup") {
        return "Usage: $cmd percent [dimspeed 1-100]" if(@a<2 or $a[1]>100);
        $dimVal+=$a[1];
	readingsSingleUpdate($hash,"dimValueStored",$dimVal,1);
        shift(@a);
        if(defined($a[1])) {
          $dimTime=sprintf("%X",(($a[1]*2.55)-255)*-1);
          shift(@a);
        }
        $sendDimCmd=1;

      } elsif($cmd eq "dimdown") {
        return "Usage: $cmd percent [dimspeed 1-100]" if(@a<2 or $a[1]>100);
        $dimVal-=$a[1];
	readingsSingleUpdate($hash,"dimValueStored",$dimVal,1);
        shift(@a);
        if(defined($a[1])) {
          $dimTime=sprintf("%X",(($a[1]*2.55)-255)*-1);
          shift(@a);
        }
        $sendDimCmd=1;

      } elsif($cmd eq "on" || $cmd eq "B0") {
        $dimTime=1;
        $sendDimCmd=1;
        my $dimValueOn = AttrVal($name, "dimValueOn", 100);
        if ($dimValueOn eq "stored") {
          $dimVal = ReadingsVal($name, "dimValueStored", 100);
          if ($dimVal < 1) {
            $dimVal = 100;
            readingsSingleUpdate($hash, "dimValueStored", $dimVal, 1);
          }
        } elsif ($dimValueOn eq "last") {
          $dimVal = ReadingsVal($name, "dimValueLast", 100);
          if ($dimVal < 1) {
            $dimVal = 100;
          }
        } else {
          $dimVal = $dimValueOn;
          if($dimValueOn > 100) { $dimVal = 100; }
          if($dimValueOn < 1)   { $dimVal = 1; }
        }

      } elsif($cmd eq "off" || $cmd eq "BI") {
        $dimTime=1;
        $onoff=0;
        $sendDimCmd=1;
        $dimVal=0;

      } else {
        my $list = "dim:slider,0,1,100 dimup:slider,0,1,100 ".
                   "dimdown:slider,0,1,100 on off teach";
        return SetExtensions($hash, $list, $name, @a);
      }

      if($sendDimCmd) {
        $a[0]="on";
          if($dimVal > 100) { $dimVal=100; }
          if($dimVal <= 0) { $dimVal=0; $onoff=0; $a[0]="off"; }
        $updateState = 0;
        $data = sprintf "A502%02X%02X%02X", $dimVal, $dimTime, $onoff|0x08;
        $header = "000A0001";
        Log $ll2, "EnOcean: set $name $cmd";
      }

    } elsif($st eq "eltakoShutter") {
      # Shutter
      my $shutTime = AttrVal($name, "shutTime", 0);
      my $shutCmd = 0x00;
      if($cmd eq "teach") {
        $data = "A5FFF80D80";
        $header = "000A0001";
        Log $ll2, "EnOcean: set $name $cmd";

      } elsif($cmd eq "stop") {
        $shutCmd = 0x00;

      } elsif($cmd eq "up" || $cmd eq "B0") {
        my $position = 100;
        if($a[1]) {
          $shutTime = $shutTime/100*$a[1];
          $position = $hash->{READINGS}{position}{VAL}+$a[1];
            if($position > 100) { $position = 100; };
        }
        $hash->{READINGS}{position}{TIME} = $tn;
        $hash->{READINGS}{position}{VAL} = $position;
        $shutCmd = 0x01;

      } elsif($cmd eq "down" || $cmd eq "BI") {
        my $position = 0;
        if($a[1]) {
          $shutTime = $shutTime/100*$a[1];
          $position = $hash->{READINGS}{position}{VAL}-$a[1];
            if($position <= 0) { $position = 0; };
        }
        $hash->{READINGS}{position}{TIME} = $tn;
        $hash->{READINGS}{position}{VAL} = $position;
        $shutCmd = 0x02;
      } else {
        return "Unknown argument " . $cmd . ", choose one of up down stop teach"
      }
      shift(@a);
      if($shutCmd || ($cmd eq "stop")) {
        $updateState = 0;
        $data = sprintf "A5%02X%02X%02X%02X", 0x00, $shutTime, $shutCmd, 0x08;
        $header = "000A0001";
        Log $ll2, "EnOcean: set $name $cmd";
      }

    } elsif ($st eq "gateway") {
      # Gateway (EEP A5-38-08)
      # select Command from attribute gwCmd or command line
      my $gwCmd = AttrVal($name, "gwCmd", undef);
      if ($gwCmd && $EnO_gwCmd{$gwCmd}) {
        # PHC Command from attribute gwCmd
        if ($EnO_gwCmd{$cmd}) {
          # shift $cmd
          $cmd = $a[1];
          shift(@a);
        }
      } elsif ($EnO_gwCmd{$cmd}) {
        # PHC Command from command line
        $gwCmd = $cmd;
        $cmd = $a[1];
        shift(@a);
      } else {
        return "Unknown Gateway Command " . $cmd . ", choose one of " . join(" ", sort keys %EnO_gwCmd);
      }
      my $gwCmdID;
      my $setCmd = 0;
      ## $status = "00";
      my $time = 0;
      if ($gwCmd eq "switching") {
        # Switching
        $gwCmdID = 1;
        if($cmd eq "teach") {
          $data = sprintf "A5%02X000000", $gwCmdID;
        } elsif ($cmd eq "on" || $cmd eq "B0") {
          $setCmd = 9;
          if ($a[1]) {
            return "Usage: $cmd [lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            $setCmd = $setCmd | 4 if ($a[1] eq "lock");
            shift(@a);
          }
          $updateState = 0;
          $data = sprintf "A5%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } elsif ($cmd eq "off" || $cmd eq "BI") {
          $setCmd = 8;
          if ($a[1]) {
            return "Usage: $cmd [lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            $setCmd = $setCmd | 4 if ($a[1] eq "lock");
            shift(@a);
          }
          $updateState = 0;
          $data = sprintf "A5%02X%04X%02X", $gwCmdID, $time, $setCmd;
        } else {
          my $cmdList = "B0 BI off on teach";
          return SetExtensions ($hash, $cmdList, $name, @a);
          $updateState = 0;
          $data = sprintf "A5%02X%04X%02X", $gwCmdID, $time, $setCmd;
        }

      } elsif ($gwCmd eq "dimming") {
        # Dimming
        $gwCmdID = 2;
        my $dimVal = $hash->{READINGS}{dimValue}{VAL};
        my $rampTime = AttrVal($name, "rampTime", 1);
        my $sendDimCmd = 0;
        $setCmd = 9;
        if ($cmd eq "teach") {
          $setCmd = 0;
          $data = sprintf "A5%02X000000", $gwCmdID;
        } elsif ($cmd eq "dim") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] < 0 || $a[1] > 100 || $a[1] !~ m/^[+-]?\d+$/);
          # for eltako relative (0-100) (but not compliant to EEP because DB0.2 is 0)
          # >> if manufID needed: set DB2.0
          $dimVal = $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^[+-]?\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "dimup") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] < 0 || $a[1] > 100 || $a[1] !~ m/^[+-]?\d+$/);
          $dimVal += $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^[+-]?\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "dimdown") {
          return "Usage: $cmd dim/% [rampTime/s lock|unlock]"
            if(@a < 2 || $a[1] < 0 || $a[1] > 100 || $a[1] !~ m/^[+-]?\d+$/);
          $dimVal -= $a[1];
	  if ($dimVal > 0) {
	    readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
	  }
          shift(@a);
          if (defined($a[1])) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if ($a[1] !~ m/^[+-]?\d+$/);
            $rampTime = $a[1];
            shift(@a);
          }
          $sendDimCmd = 1;

        } elsif ($cmd eq "on" || $cmd eq "B0") {
          $rampTime = 1;
          my $dimValueOn = AttrVal($name, "dimValueOn", 100);
          if ($dimValueOn eq "stored") {
            $dimVal = ReadingsVal($name, "dimValueStored", 100);
            if ($dimVal < 1) {
              $dimVal = 100;
              readingsSingleUpdate ($hash, "dimValueStored", $dimVal, 1);
            }
          } elsif ($dimValueOn eq "last") {
            $dimVal = ReadingsVal ($name, "dimValueLast", 100);
            if ($dimVal < 1) { $dimVal = 100; }
          } else {
            if ($dimValueOn !~ m/^[+-]?\d+$/) {
              $dimVal = 100;
            } elsif ($dimValueOn > 100) {
              $dimVal = 100;
            } elsif ($dimValueOn < 1) {
              $dimVal = 1;
            } else {
              $dimVal = $dimValueOn;
            }
          }
          $sendDimCmd = 1

        } elsif ($cmd eq "off" || $cmd eq "BI") {
          $dimVal = 0;
          $rampTime = 1;
          $setCmd = 8;
          $sendDimCmd = 1;

        } else {
          my $cmdList = "dim:slider,0,1,100 B0 BI on off teach";
          return SetExtensions ($hash, $cmdList, $name, @a);
        }
        if($sendDimCmd) {
          if (defined $a[1]) {
            return "Usage: $cmd dim/% [rampTime/s lock|unlock]" if (($a[1] ne "lock") && ($a[1] ne "unlock"));
            if ($manufID eq "OOD") {
              # Eltako devices: block dimming value
              if ($a[1] eq "lock") { $setCmd = $setCmd | 4; }
            } else {
              # Dimming value relative
              $setCmd = $setCmd | 4;
            }
            shift(@a);
          } else {
            if ($manufID ne "OOD") { $setCmd = $setCmd | 4; }
          }
          if ($dimVal > 100) { $dimVal = 100; }
          if ($dimVal <= 0) { $dimVal = 0; $setCmd = 8; }
          if ($rampTime > 255) { $rampTime = 255; }
          if ($rampTime < 0) { $rampTime = 0; }
          $updateState = 0;
          $data = sprintf "A5%02X%02X%02X%02X", $gwCmdID, $dimVal, $rampTime, $setCmd;
        }

      } elsif ($gwCmd eq "setpointShift") {
        $gwCmdID = 3;
        if ($cmd eq "teach") {
          $data = sprintf "A5%02X000000", $gwCmdID;
        } elsif ($cmd eq "shift") {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= -12.7) && ($a[1] <= 12.8)) {
            $updateState = 0;
            $data = sprintf "A5%02X00%02X08", $gwCmdID, ($a[1] + 12.7) * 10;
            shift(@a);
          } else {
            return "Usage: $a[1] is not numeric or out of range";
          }
        } else {
          return "Unknown argument $cmd, choose one of teach shift";        
        }

      } elsif ($gwCmd eq "setpointBasic") {
        $gwCmdID = 4;
        if($cmd eq "teach") {
          $data = sprintf "A5%02X000000", $gwCmdID;
        } elsif ($cmd eq "basic") {
          if (($a[1] =~ m/^[+-]?\d+(\.\d+)?$/) && ($a[1] >= 0) && ($a[1] <= 51.2)) {
            $updateState = 0;
            $data = sprintf "A5%02X00%02X08", $gwCmdID, $a[1] * 5;
            shift(@a);
          } else {
            return "Usage: $cmd parameter is not numeric or out of range.";
          }
        } else {
          return "Unknown argument $cmd, choose one of teach basic";        
        }

      } elsif ($gwCmd eq "controlVar") {
        $gwCmdID = 5;
        my $controlVar = ReadingsVal($name, "controlVar", 0);
        if($cmd eq "teach") {
          $data = printf "A5%02X000000", $gwCmdID;
        } elsif ($cmd eq "presence") {
          if ($a[1] eq "standby") {
            $setCmd = 0x0A;
          } elsif ($a[1] eq "absent") {
            $setCmd = 9;
          } elsif ($a[1] eq "present") {
            $setCmd = 8;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "A5%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "energyHoldOff") {
          if ($a[1] eq "normal") {
            $setCmd = 8;
          } elsif ($a[1] eq "holdoff") {
            $setCmd = 0x0C;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "A5%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "controllerMode") {
          if ($a[1] eq "auto") {
            $setCmd = 8;
          } elsif ($a[1] eq "heating") {
            $setCmd = 0x28;
          } elsif ($a[1] eq "cooling") {
            $setCmd = 0x48;
          } elsif ($a[1] eq "off" || $a[1] eq "BI") {
            $setCmd = 0x68;
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $data = sprintf "A5%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } elsif ($cmd eq "controllerState") {
          if ($a[1] eq "auto") {
            $setCmd = 8;
          } elsif ($a[1] eq "override") {
            $setCmd = 0x18;
            if (defined $a[2] && ($a[2] =~ m/^[+-]?\d+$/) && ($a[2] >= 0) && ($a[2] <= 100) ) {
              $controlVar = $a[2] * 255;
              shift(@a);
            } else {
              return "Usage: Control Variable Override is not numeric or out of range.";
            }
          } else {
            return "Usage: $cmd parameter unknown.";
          }
          shift(@a);
          $updateState = 0;
          $data = sprintf "A5%02X00%02X%02X", $gwCmdID, $controlVar, $setCmd;
        } else {
          return "Unknown argument, choose one of teach presence energyHoldOff controllerMode controllerState";
        }

      } elsif ($gwCmd eq "fanStage") {
        $gwCmdID = 6;
        if($cmd eq "teach") {
          $data = sprintf "A5%02X000000", $gwCmdID;
        } elsif ($cmd eq "stage") {
          if ($a[1] eq "auto") {
            $updateState = 0;
            $data = sprintf "A5%02X00%02X08", $gwCmdID, 255;
          } elsif ($a[1] && $a[1] =~ m/^[0-3]$/) {
            $updateState = 0;
            $data = sprintf "A5%02X00%02X08", $gwCmdID, $a[1];
          } else {
            return "Usage: $cmd parameter is not numeric or out of range"
          }
          shift(@a);          
        } else {
          return "Unknown argument, choose one of teach stage";
        }

      } elsif ($gwCmd eq "blindCmd") {
        $gwCmdID = 7;
        my %blindFunc = (
          "status"         => 0,
          "stop"           => 1,
          "opens"          => 2,
          "closes"         => 3,
          "position"       => 4,
          "up"             => 5,
          "down"           => 6,
          "runtimeSet"     => 7,
          "angleSet"       => 8,
          "positionMinMax" => 9,
          "angleMinMax"    => 10,
          "positionLogic"  => 11,
          "teach"          => 255,
        );
        my $blindFuncID;
        if (defined $blindFunc {$cmd}) {
          $blindFuncID = $blindFunc {$cmd};
        } else {
          return "Unknown Gateway Blind Central Function " . $cmd . ", choose one of ". join(" ", sort keys %blindFunc);
        }
        my $blindParam1 = 0;
        my $blindParam2 = 0;
        $setCmd = $blindFuncID << 4 | 8;

        if($blindFuncID == 255) {
          # teach
          $setCmd = 0;
        } elsif ($blindFuncID == 0) {
          # status
          $updateState = 0;
        } elsif ($blindFuncID == 1) {
          # stop
          $updateState = 0;
        } elsif ($blindFuncID == 2) {
          # opens
          $updateState = 0;
        } elsif ($blindFuncID == 3) {
          # closes
          $updateState = 0;
        } elsif ($blindFuncID == 4) {
          # position
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= -180 && $a[2] <= 180) {
              $blindParam2 = abs($a[2]) / 2;
              if ($a[2] < 0) {$blindParam2 |= 0x80;}
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 5 || $blindFuncID == 6) {
          # up / down
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[2] >= 0 && $a[2] <= 25.5) {
              $blindParam2 = $a[2] * 10;
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 7) {
          # runtimeSet
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 255) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= 0 && $a[2] <= 255) {
              $blindParam2 = $a[2];
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          ##
          readingsSingleUpdate($hash, "runTimeUp", $blindParam1, 1);
          readingsSingleUpdate($hash, "runTimeDown", $blindParam2, 1);
          $updateState = 0;
        } elsif ($blindFuncID == 8) {
          # angleSet
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+(\.\d+)?$/ && $a[1] >= 0 && $a[1] <= 25.5) {
            $blindParam1 = $a[1] * 10;
            ##
            readingsSingleUpdate($hash, "angleTime", (sprintf "%0.1f", $a[1]), 1);
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          $updateState = 0;
        } elsif ($blindFuncID == 9) {
          # positionMinMax
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
            $blindParam1 = $a[1];
            if (defined $a[2] && $a[2] =~ m/^[+-]?\d+$/ && $a[2] >= 0 && $a[2] <= 100) {
              $blindParam2 = $a[2];
              shift(@a);
            } else {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            shift(@a);
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          if ($blindParam1 > $blindParam2) {($blindParam1, $blindParam2) = ($blindParam2, $blindParam1);}
          ##
          readingsSingleUpdate($hash, "positionMin", $blindParam1, 1);
          readingsSingleUpdate($hash, "positionMax", $blindParam2, 1);
          $updateState = 0;
        } elsif ($blindFuncID == 10) {
          # angleMinMax
          if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= -180 && $a[1] <= 180) {
            if (!defined $a[2] || $a[2] !~ m/^[+-]?\d+$/ || $a[2] < -180 || $a[2] > 180) {
              return "Usage: $cmd variable is not numeric or out of range.";
            }
            if ($a[1] > $a[2]) {($a[1], $a[2]) = ($a[2], $a[1]);}
            $blindParam1 = abs($a[1]) / 2;
            if ($a[1] < 0) {$blindParam1 |= 0x80;}
            $blindParam2 = abs($a[2]) / 2;
            if ($a[2] < 0) {$blindParam2 |= 0x80;}
          } else {
            return "Usage: $cmd variable is not numeric or out of range.";
          }
          ##
          readingsSingleUpdate($hash, "angleMin", $a[1], 1);
          readingsSingleUpdate($hash, "angleMax", $a[2], 1);
          splice (@a, 0, 2);
          $updateState = 0;
        } elsif ($blindFuncID == 11) {
          # positionLogic
          if ($a[1] eq "normal") {
            $blindParam1 = 0;
          } elsif ($a[1] eq "inverse") {
            $blindParam1 = 1;
          } else {
            return "Usage: $cmd variable is unknown.";
          }
          shift(@a);
          $updateState = 0;
        } else {
        }
        $data = sprintf "A5%02X%02X%02X%02X", $gwCmdID, $blindParam1, $blindParam2, $setCmd;

      } else {
        return "Unknown Gateway Command " . $cmd . ", choose one of ". join(" ", sort keys %EnO_gwCmd);
      }
      # write gateway command
      $header = "000A0001";
      Log $ll2, "EnOcean: set $name $cmd";

    } elsif ($st eq "manufProfile") {
      if ($manufID eq "00D") {
        # Eltako Shutter
        my $position = ReadingsVal($name, "position", undef);
        my $shutTime = AttrVal($name, "shutTime", 255);
        my $shutCmd = 0;
        $shutTime = 255 if ($shutTime !~ m/^[+-]?\d+$/);
        $shutTime = 255 if ($shutTime > 255);
        $shutTime = 1 if ($shutTime < 1);
        if ($cmd eq "teach") {
          $data = "A5FFF80D80";
          $header = "000A0001";
          Log $ll2, "EnOcean: set $name $cmd";
        } elsif ($cmd eq "stop") {
          $shutCmd = 0;
        } elsif ($cmd eq "up" || $cmd eq "B0") {
          if(defined $a[1]) {
            if ($a[1] =~ m/^[+-]?\d+$/ && $a[1] > 0 && $a[1] <= 100) {
              $shutTime = $shutTime / 100 * $a[1];
              $position -= $a[1];
              if($position <= 0) { $position = 0; }
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          } else {
            $position = 0;
          }
      	  readingsSingleUpdate($hash,"position",$position,1);
          $shutCmd = 1;
        } elsif ($cmd eq "down" || $cmd eq "BI") {
          if(defined $a[1]) {
            if ($a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] < 100) {
              $shutTime = $shutTime / 100 * $a[1];
              $position += $a[1];
              if($position > 100) { $position = 100; }
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          } else {
            $position = 100;
          }
          readingsSingleUpdate($hash,"position",$position,1);
          $shutCmd = 2;
        } elsif ($cmd eq "position") {
          if (!defined $position) {
            return "Position unknown, please first open the blinds completely."
          } else {
            if (defined $a[1] && $a[1] =~ m/^[+-]?\d+$/ && $a[1] >= 0 && $a[1] <= 100) {
              if ($position < $a[1]) {
                # down
                $shutTime = $shutTime / 100 * ($a[1] - $position);
                $shutCmd = 2;
              } elsif ($position > $a[1]) {
                # up
                $shutTime = $shutTime / 100 * ($position - $a[1]);
                $shutCmd = 1;
              } else {
                # position ok
                $shutCmd = 0;
              }
              readingsSingleUpdate($hash,"position",$a[1],1);
              shift(@a);
            } else {
              return "Usage: $a[1] is not numeric or out of range";
            }
          }
        } else {
          return "Unknown argument " . $cmd . ", choose one of up stop down position teach"
        }
        if($shutCmd || $cmd eq "stop") {
          $updateState = 0;
          $data = sprintf "A5%02X%02X%02X%02X", 0, $shutTime, $shutCmd, 8;
          $header = "000A0001";
          Log $ll2, "EnOcean: set $name $cmd";
        }
      } else {
        return "Manufacturer Specific Application unknown. Set correct attr manufID.";
      }

    } elsif ($st eq "contact") {
      # 1BS Telegram
      # Single Input Contact (EEP D5-00-01)
      my $setCmd;
      if ($cmd eq "teach") {
        $setCmd = 0;
      } elsif ($cmd eq "closed") {
        $setCmd = 9;
      } elsif ($cmd eq "open") {
        $setCmd = 8;
      } else {
        return "Unknown argument $cmd, choose one of open closed teach";
      }
      $data = sprintf "D5%02X", $setCmd;
      $header = "00070001";
      Log $ll2, "EnOcean: set $name $cmd";

    } elsif ($st eq "raw") {
      # sent raw data
      # to do: optional data
      if ($cmd eq "4BS"){
        # 4BS Telegram
        if ($a[1] && $a[1] =~ /^[\dA-F]{8}$/) {
          $data = sprintf "A5%s", $a[1];
          $header = "000A0001";
        } else {
          return "Wrong parameter, choose 4BS <data 4 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "1BS") {
        # 1BS Telegram
        if ($a[1] && $a[1] =~ /^[\dA-F]{2}$/) {
          $data = sprintf "D5%s", $a[1];
          $header = "00070001";
        } else {
          return "Wrong parameter, choose 1BS <data 1 Byte hex> [status 1 Byte hex]";
        }
      } elsif ($cmd eq "RPS") {
        # RPS Telegram
        if ($a[1] && $a[1] =~ /^[\dA-F]{2}$/) {
          $data = sprintf "F6%s", $a[1];
          $header = "00070001";
        } else {
          return "Wrong parameter, choose RPS <data 1 Byte hex> [status 1 Byte hex]";
        }
      } else {
        return "Unknown argument $cmd, choose one of RPS 1BS 4BS";
      }
      if ($a[2]) {
        if ($a[2] !~ /^[\dA-F]{2}$/) {
          return "Wrong status parameter, choose $cmd $a[1] [status 1 Byte hex]";
        }
       $status = $a[2];
       shift(@a);     
      }
      $updateState = 0;
      readingsSingleUpdate($hash, "RORG", $cmd, 1);
      readingsSingleUpdate($hash, "dataSent", $a[1], 1);
      readingsSingleUpdate($hash, "statusSent", $status, 1);
      Log $ll2, "EnOcean: set $name $cmd $a[1] $status";
      shift(@a);     
      
    } else {
    # Rocker Switch, simulate a PTM200 switch module
      # separate first and second action
      my ($c1,$c2) = split(",", $cmd, 2);
      # check values
      if(!defined($EnO_ptm200btn{$c1}) || ($c2 && !defined($EnO_ptm200btn{$c2}))) {
        my $list = join(" ", sort keys %EnO_ptm200btn);
        return SetExtensions($hash, $list, $name, @a);
      }
      my $channelA = ReadingsVal($name, "channelA", undef);
      my $channelB = ReadingsVal($name, "channelB", undef);
      my $channelC = ReadingsVal($name, "channelC", undef);
      my $channelD = ReadingsVal($name, "channelD", undef);
      my $subDef0 = AttrVal($name, "subDef0", "$hash->{DEF}");
      my $subDefI = AttrVal($name, "subDefI", "$hash->{DEF}");
      my $switchType = AttrVal($name, "switchType", "direction");
      # first action
      if ($switchType eq "central") {
        if ($c1 =~ m/.0/ || $c1 eq "released") {
          $subDef = $subDef0;
        } else {
          $subDef = $subDefI;
        }
      }
      if ($switchType eq "universal") {
        if ($c1 =~ m/A0|AI/ && (!$channelA || ($c1 ne $channelA))) {
          $c1 = "A0";
        } elsif ($c1 =~ m/B0|BI/ && (!$channelB || $c1 ne $channelB)) {
          $c1 = "B0";
        } elsif ($c1 =~ m/C0|CI/ && (!$channelC || ($c1 ne $channelC))) {
          $c1 = "C0";
        } elsif ($c1 =~ m/D0|DI/ && (!$channelD || ($c1 ne $channelD))) {
          $c1 = "D0";
        } elsif ($c1 eq "released") {

        } else {
          $sendCmd = "no";
        }
      }
      # second action
      if ($c2 && $switchType eq "universal") {
        if ($c2 =~ m/A0|AI/ && (!$channelA || ($c2 ne $channelA))) {
          $c2 = "A0";
        } elsif ($c2 =~ m/B0|BI/ && (!$channelB || $c2 ne $channelB)) {
          $c2 = "B0";
        } elsif ($c2 =~ m/C0|CI/ && (!$channelC || ($c2 ne $channelC))) {
          $c2 = "C0";
        } elsif ($c2 =~ m/D0|DI/ && (!$channelD || ($c2 ne $channelD))) {
          $c2 = "D0";
        } else {
          $c2 = undef;
        }
        if ($c2 && $sendCmd eq "no") {
          # only second action has changed, send as first action
          $c1 = $c2;
          $c2 = undef;
          $sendCmd = "yes";
        }
      }
      # convert and send first and second command
      my $switchCmd;
      ($switchCmd, $status) = split(":", $EnO_ptm200btn{$c1}, 2);
      $switchCmd <<= 5;
      $switchCmd |= 0x10 if($c1 ne "released"); # set the pressed flag
      if($c2 && $switchType ne "central") {
        my ($d2, undef) = split(":", $EnO_ptm200btn{$c2}, 2);
        $switchCmd |= ($d2<<1) | 0x01;
      }
      if ($sendCmd ne "no") {
        $data = sprintf "F6%02X", $switchCmd;
        $header = "00070001";
        Log $ll2, "EnOcean: set $name $cmd";
      }
    }
    if($st ne "MD15") {
      if ($repeatingAllowed eq "no") {
        $status = substr ($status, 0, 1) . "F";
      }
      $data = sprintf "%s%s%s", $data, $subDef, $status;
      IOWrite ($hash, $header, $data);
      if ($switchMode eq "pushbutton") {
        $data = "F600";
        $status = "20";
        $data = sprintf "%s%s%s", $data, $subDef, $status;
	Log $ll2, "EnOcean: set $name released";
        IOWrite ($hash, $header, $data);
      }
    }
    select(undef, undef, undef, 0.2);   # Tested by joerg. He prefers 0.3 :)
  }
  # set reading state if acknowledge is not expected
  $subDef = AttrVal($name, "subDef", undef);
  if($updateState == 1 || !defined $subDef) {
    readingsSingleUpdate($hash, "state", join(" ", @a), 1);
    return undef;
  }
}

# Parse
sub
EnOcean_Parse($$)
{
  my ($iohash, $msg) = @_;
  my (undef,$rorg,$data,$id,$status,$odata) = split(":", $msg);

  my $rorgname = $EnO_rorgname{$rorg};
  if(!$rorgname) {
    Log 2, "Unknown EnOcean RORG ($rorg) received from $id";
    return "";
  }

  my $hash = $modules{EnOcean}{defptr}{$id};
  if(!$hash) {
    Log 3, "EnOcean Unknown device with ID $id, please define it";
    return "UNDEFINED EnO_${rorgname}_$id EnOcean $id";
  }

  my $name = $hash->{NAME};
  my $dl = length($data);
  my $db_3 = hex substr($data,0,2);
  my $db_2 = hex substr($data,2,2) if($dl > 2);
  my $db_1 = hex substr($data,4,2) if($dl > 4);
  my $db_0 = hex substr($data,6,2) if($dl > 6);
  my @event;
  my $ll4 = GetLogLevel($name, 4);
  my $model = AttrVal($name, "model", "");
  my $manufID = AttrVal($name, "manufID", "");
  my $st = AttrVal($name, "subType", "");
  
  Log $ll4, "$name: ORG:$rorg DATA:$data ID:$id STATUS:$status";

  if($rorg eq "F6") {
    # RPS Telegram (PTM200)
    # Rocker Switch (EEP F6-02-01 ... F6-03-02)
    # Position Switch, Home and Office Application (EEP F6-04-01)
    # Mechanical Handle (EEP F6-10-00)
    my $event = "state";
    my $nu =  ((hex($status)&0x10)>>4);
    # unused flags (AFAIK)
    #push @event, "1:T21:".((hex($status)&0x20)>>5);
    #push @event, "1:NU:$nu";

    if($nu) {
      # Theoretically there can be a released event with some of the A0,BI
      # pins set, but with the plastic cover on this wont happen.
      $msg  = $EnO_ptm200btn[($db_3&0xe0)>>5];
      $msg .= ",".$EnO_ptm200btn[($db_3&0x0e)>>1] if($db_3 & 1);
      $msg .= " released" if(!($db_3 & 0x10));

    } else {
      if($db_3 == 112) {
        # Key Card, not tested
        $msg = "keycard inserted";

      } elsif($db_3 & 0xC0) {
        # Only a Mechanical Handle is setting these bits when nu=0
        $msg = "closed"           if($db_3 == 0xF0);
        $msg = "open"             if($db_3 == 0xE0);
        $msg = "tilted"           if($db_3 == 0xD0);
        $msg = "open from tilted" if($db_3 == 0xC0);

      } else {
        if($st eq "keycard") {
          $msg = "keycard removed";
        }
        else {
          $msg = (($db_3&0x10) ? "pressed" : "released");
        }
      }
    }
    if ($st eq "FRW") {
      # smoke detector Eltako FRW, untested
      if ($msg =~ m/A0$/) {
        push @event, "3:battery:low";
      } elsif ($msg =~ m/AI$/) {
        push @event, "3:alarm:smoke-alarm";
        $msg = "smoke-alarm";
      } elsif ($msg =~ m/released$/) {
        push @event, "3:alarm:off";
        push @event, "3:battery:ok";
        $msg = "off";
      }
    } else {
      if ($msg =~ m/A0$/) {
        push @event, "3:channelA:A0";
      } elsif ($msg =~ m/AI$/) {
        push @event, "3:channelA:AI";
      } elsif ($msg =~ m/B0$/) {
        push @event, "3:channelB:B0";
      } elsif ($msg =~ m/BI$/) {
        push @event, "3:channelB:BI";
      } elsif ($msg =~ m/C0$/) {
        push @event, "3:channelC:C0";
      } elsif ($msg =~ m/CI$/) {
        push @event, "3:channelC:CI";
      } elsif ($msg =~ m/D0$/) {
        push @event, "3:channelD:D0";
      } elsif ($msg =~ m/DI$/) {
        push @event, "3:channelD:DI";
      }
    # released events are disturbing when using a remote, since it overwrites
    # the "real" state immediately. In the case of an Eltako FSB14, FSB61
    # the state should remain released. (by Thomas)
    $event = "buttons" if ($msg =~ m/released$/ &&
                           $model ne "FT55" && $model ne "FSB14" &&
                           $model ne "FSB61" && $model ne "FSB70" &&
                           $model ne "FSM12" && $model ne "FSM61" &&
                           $model ne "FTS12");
    }
    push @event, "3:$event:$msg";

  } elsif($rorg eq "D5") {
  # 1BS Telegram
  # Single Input Contact (EEP D5-00-01)
  # [Eltako FTK, STM-250]
    push @event, "3:state:" . ($db_3 & 1 ? "closed" : "open");
    push @event, "3:learnBtn:on" if (!($db_3 & 0x8));

  } elsif($rorg eq "A5") {
  # 4BS Telegram
    if(($db_0 & 0x08) == 0) {
    # teach-in telegram
      if($db_0 & 0x80) {
        # teach-in telegram with EEP and Manufacturer ID
        my $fn = sprintf "%02x", ($db_3 >> 2);
        my $tp = sprintf "%02X", ((($db_3 & 3) << 5) | ($db_2 >> 3));
        my $mf = sprintf "%03X", ((($db_2 & 7) << 8) | $db_1);
        # manufID to account for vendor-specific features
        $attr{$name}{manufID} = $mf;
        $mf = $EnO_manuf{$mf} if($EnO_manuf{$mf});
        my $m = "teach-in:EEP A5-$fn-$tp Manufacturer: $mf";
        Log 1, $m;
        push @event, "3:$m";
        my $st = "A5.$fn.$tp";
        $st = $EnO_subType{$st} if($EnO_subType{$st});
        $attr{$name}{subType} = $st;

        if("$fn.$tp" eq "20.01" && $iohash->{pair}) {      # MD15
          select(undef, undef, undef, 0.1);                # max 10 Seconds
          EnOcean_A5Cmd($hash, "800800F0", "00000000");
          select(undef, undef, undef, 0.5);
          EnOcean_MD15Cmd($hash, $name, 128); # 128 == 20 degree C
        }
        # subType, manufID storing corrected
        CommandSave(undef, undef);
      } else {
        push @event, "3:teach-in:No EEP profile identifier and no Manufacturer ID";
      }

    } elsif($st eq "MD15") {
      # Battery Powered Actuator (EEP A5-20-01)
      # [Kieback&Peter MD15-FTL-xx]
      push @event, "3:state:$db_3";
      push @event, "3:currentValue:$db_3";
      push @event, "3:serviceOn:"    . (($db_2 & 0x80) ? "yes" : "no");
      push @event, "3:energyInput:"  . (($db_2 & 0x40) ? "enabled":"disabled");
      push @event, "3:energyStorage:". (($db_2 & 0x20) ? "charged":"empty");
      push @event, "3:battery:"      . (($db_2 & 0x10) ? "ok" : "low");
      push @event, "3:cover:"        . (($db_2 & 0x08) ? "open" : "closed");
      push @event, "3:tempSensor:"   . (($db_2 & 0x04) ? "failed" : "ok");
      push @event, "3:window:"       . (($db_2 & 0x02) ? "open" : "closed");
      push @event, "3:actuatorStatus:".(($db_2 & 0x01) ? "obstructed" : "ok");
      push @event, "3:measured-temp:". sprintf "%0.1f", ($db_1*40/255);
      push @event, "3:selfCtl:"      . (($db_0 & 0x04) ? "on" : "off");
      EnOcean_MD15Cmd($hash, $name, $db_1);

    } elsif($model eq "PM101") {
      # Light and Presence Sensor [Omnio Ratio eagle-PM101]
      # The sensor also sends switching commands (RORG F6) with the senderID-1
      # code by aicgazi
      # $db_2 is the illuminance where max value 0xFF stands for 1000 lx
      my $lux = sprintf "%3d", $db_2;
      $lux = sprintf "%04.2f", ( $lux * 1000 / 255 ) ;
      push @event, "3:brightness:$lux";
      push @event, "3:channel1:" . ($db_0 & 0x01 ? "off" : "on");
      push @event, "3:channel2:" . ($db_0 & 0x02 ? "off" : "on");
      push @event, "3:motion:" . ($db_0 & 0x02 ? "off" : "on");
      push @event, "3:state:" . ($db_0 & 0x02 ? "off" : "on");

    } elsif($st eq "FAH" || $model =~ /^(FAH60|FAH63|FIH63)$/) {
      # Light Sensor
      # [Eltako FAH60, FAH63, FIH63] (EEP A5-06-01 plus Data_byte3)
      # $db_3 is the illuminance where min 0x00 = 0 lx, max 0xFF = 100 lx
      # $db_2 must be 0x00
      if($db_2 eq 0x00) {
        my $luxlow = sprintf "%3d", $db_3;
        $luxlow = sprintf "%d", ( $luxlow * 100 / 255 ) ;
        push @event, "3:brightness:$luxlow";
        push @event, "3:state:$luxlow";
      } else {
        # $db_2 is the illuminance where min 0x00 = 300 lx, max 0xFF = 30000 lx
        my $lux = sprintf "%3d", $db_2;
        $lux = sprintf "%d", (( $lux * 116.48) + 300 ) ;
        push @event, "3:brightness:$lux";
        push @event, "3:state:$lux";
      }

    } elsif($st eq "FBH" || $model =~ /^(FABH63|FBH55|FBH63|FIBH63)$/) {
      # Light and Occupancy Sensor (no Temperature)
      # [Eltako FABH63, FBH55, FBH63, FIBH63] (EEP similar A5-08-01)
      # $db_0 motion detection where 0x0D = motion and 0x0F = no motion
      # (DB0_Bit1 = 1 or 0)
      if($db_0 eq 0x0D) {
        push @event, "3:motion:yes";
        push @event, "3:state:yes";
      }
      if($db_0 eq 0x0F) {
        push @event, "3:motion:no";
        push @event, "3:state:no";
      }
      # $db_2 is the illuminance where min 0x00 = 0 lx, max 0xFF = 2048 lx
      my $lux = sprintf "%3d", $db_2;
      $lux = sprintf "%d", ( $lux * 2048 / 255 ) ;
      push @event, "3:brightness:$lux";
      # $db_3 is voltage in EEP A5-08-01 but not used by Eltako !?
      # push @event, "3:voltage:$db_3";

    } elsif($st eq "FTF" || $model eq "FTF55") {
      # Temperature Sensor (EEP A5-02-05)
      # [Eltako FTF55, Thermokon SR04]
      # $db_1 is the temperature where 0x00 = 40°C and 0xFF = 0°C
      my $temp = sprintf "%3d", $db_1;
      $temp = sprintf "%0.1f", ( 40 - $temp * 40 / 255 ) ;
      push @event, "3:state:$temp";
      push @event, "3:temperature:$temp";

    } elsif($model =~ m/^SR04/ || $st eq "SR04") {
      # Room Sensor and Control Unit
      # [Thermokon SR04 *]
      my ($fspeed, $temp, $present, $solltemp);
      $fspeed = 3;
      $fspeed = 2      if($db_3 >= 145);
      $fspeed = 1      if($db_3 >= 165);
      $fspeed = 0      if($db_3 >= 190);
      $fspeed = "Auto" if($db_3 >= 210);
      $temp   = sprintf("%0.1f", 40-$db_1/6.375);      # 40..0
      $present= $db_0&0x1 ? "no" : "yes";
      $solltemp= sprintf("%0.1f", $db_2/6.375);
      push @event, "3:state:temperature $temp";
      push @event, "3:set_point: $solltemp";
      push @event, "3:setpoint:$db_2";
      push @event, "3:fan:$fspeed";
      push @event, "3:present:$present" if($present eq "yes");
      push @event, "3:learnBtn:on" if(!($db_0&0x8));
      push @event, "3:T:$temp SP: $db_3 F: $fspeed P: $present";

    } elsif ($st =~ m/^tempSensor/) {
      # Temperature Sensor with with different ranges (EEP A5-02-01 ... A5-02-1B)
      # $db_1 is the temperature where 0x00 = max °C ... 0xFF = min °C
      my $temp;
      $temp = sprintf "%0.1f", -40 - $db_1 / 6.375 if ($st eq "tempSensor.01");
      $temp = sprintf "%0.1f", -30 - $db_1 / 6.375 if ($st eq "tempSensor.02");
      $temp = sprintf "%0.1f", -20 - $db_1 / 6.375 if ($st eq "tempSensor.03");
      $temp = sprintf "%0.1f", -10 - $db_1 / 6.375 if ($st eq "tempSensor.04");
      $temp = sprintf "%0.1f",   0 - $db_1 / 6.375 if ($st eq "tempSensor.05");
      $temp = sprintf "%0.1f",  10 - $db_1 / 6.375 if ($st eq "tempSensor.06");
      $temp = sprintf "%0.1f",  20 - $db_1 / 6.375 if ($st eq "tempSensor.07");
      $temp = sprintf "%0.1f",  30 - $db_1 / 6.375 if ($st eq "tempSensor.08");
      $temp = sprintf "%0.1f",  40 - $db_1 / 6.375 if ($st eq "tempSensor.09");
      $temp = sprintf "%0.1f",  50 - $db_1 / 6.375 if ($st eq "tempSensor.0A");
      $temp = sprintf "%0.1f",  60 - $db_1 / 6.375 if ($st eq "tempSensor.0B");
      $temp = sprintf "%0.1f", -60 - $db_1 / 3.1875 if ($st eq "tempSensor.10");
      $temp = sprintf "%0.1f", -50 - $db_1 / 3.1875 if ($st eq "tempSensor.11");
      $temp = sprintf "%0.1f", -40 - $db_1 / 3.1875 if ($st eq "tempSensor.12");
      $temp = sprintf "%0.1f", -30 - $db_1 / 3.1875 if ($st eq "tempSensor.13");
      $temp = sprintf "%0.1f", -20 - $db_1 / 3.1875 if ($st eq "tempSensor.14");
      $temp = sprintf "%0.1f", -10 - $db_1 / 3.1875 if ($st eq "tempSensor.15");
      $temp = sprintf "%0.1f",   0 - $db_1 / 3.1875 if ($st eq "tempSensor.16");
      $temp = sprintf "%0.1f",  10 - $db_1 / 3.1875 if ($st eq "tempSensor.17");
      $temp = sprintf "%0.1f",  20 - $db_1 / 3.1875 if ($st eq "tempSensor.18");
      $temp = sprintf "%0.1f",  30 - $db_1 / 3.1875 if ($st eq "tempSensor.19");
      $temp = sprintf "%0.1f",  40 - $db_1 / 3.1875 if ($st eq "tempSensor.1A");
      $temp = sprintf "%0.1f",  50 - $db_1 / 3.1875 if ($st eq "tempSensor.1B");
      $temp = sprintf "%0.2f",  -10 - (($db_2 << 8) | $db_1) / 19.98 if ($st eq "tempSensor.20");
      $temp = sprintf "%0.1f",  -40 - (($db_2 << 8) | $db_1) / 6.3 if ($st eq "tempSensor.30");
      push @event, "3:temperature:$temp";
      push @event, "3:state:$temp";

    } elsif($st eq "COSensor.01") {
      # Gas Sensor, CO Sensor (EEP A5-09-01)
      # [untested]
      # $db_3 is the CO concentration where 0x00 = 0 ppm ... 0xFF = 255 ppm
      # $db_1 is the temperature where 0x00 = 0 °C ... 0xFF = 255 °C
      # $db_0 bit D1 temperature sensor available 0 = no, 1 = yes
      my $coChannel1 = $db_3;
      push @event, "3:CO:$coChannel1";
      if ($db_0 & 2) {
        my $temp = $db_1;
        push @event, "3:temperature:$temp";
      }
      push @event, "3:state:$coChannel1";

    } elsif($st eq "COSensor.02") {
      # Gas Sensor, CO Sensor (EEP A5-09-02)
      # [untested]
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db_2 is the CO concentration where 0x00 = 0 ppm ... 0xFF = 1020 ppm
      # $db_1 is the temperature where 0x00 = 0 °C ... 0xFF = 51 °C
      # $db_0_bit_1 temperature sensor available 0 = no, 1 = yes
      my $coChannel1 = $db_2 << 2;
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      push @event, "3:CO:$coChannel1";
      if ($db_0 & 2) {
        my $temp = sprintf "%0.1f", $db_1 * 0.2;
        push @event, "3:temperature:$temp";
      }
      push @event, "3:voltage:$voltage";
      push @event, "3:state:$coChannel1";

    } elsif($st eq "tempHumiCO2Sensor.01") {
      # Gas Sensor, CO2 Sensor (EEP A5-09-04)
      # [Thermokon SR04 CO2 *, untested]
      # $db_3 is the humidity where 0x00 = 0 %rH ... 0xC8 = 100 %rH
      # $db_2 is the CO2 concentration where 0x00 = 0 ppm ... 0xFF = 2500 ppm
      # $db_1 is the temperature where 0x00 = 0°C ... 0xFF = +51 °C
      # $db_0 bit D2 humidity sensor available 0 = no, 1 = yes
      # $db_0 bit D1 temperature sensor available 0 = no, 1 = yes
      my $humi = "unknown";
      my $temp = "unknown";
      my $airQuality;
      if ($db_0 & 4) {
        $humi = $db_3 >> 1;
      push @event, "3:humidity:$humi";
      }
      my $co2 = sprintf "%d", $db_2 * 10;
      push @event, "3:CO2:$co2";
      if ($db_0 & 2) {
        $temp = sprintf "%0.1f", $db_1 * 51 / 255 ;
        push @event, "3:temperature:$temp";
      }
      if ($co2 <= 400) {
        $airQuality = "high";
      } elsif ($co2 <= 600) {
        $airQuality = "mean";
      }  elsif ($co2 <= 1000) {
        $airQuality = "moderate";
      } else {
        $airQuality = "low";
      }
      push @event, "3:airQuality:$airQuality";
      push @event, "3:state:CO2 $co2 AQ: $airQuality T: $temp H: $humi";

    } elsif ($st eq "radonSensor.01") {
      # Gas Sensor, Radon Sensor (EEP A5-09-06)
      # [untested]
      # $db_3_bit_7 ... $db_2_bit_6 is the radon activity where 0 = 0 Bq/m3 ... 1023 = 1023 Bq/m3
      my $rn = $db_3 << 2 | $db_2 >> 6;
      push @event, "3:Rn:$rn";
      push @event, "3:state:$rn";

    } elsif ($st eq "vocSensor.01") {
      # Gas Sensor, VOC Sensor (EEP A5-09-05)
      # [untested]
      # $db_3_bit_7 ... $db_2_bit_0 is the VOC concentration where 0 = 0 ppb ... 65535 = 65535 ppb
      # $db_1 is the VOC identification
      # $db_0_bit_1 ... $db_0_bit_0 is the scale multiplier
      my $vocSCM = $db_0 & 3;
      if ($vocSCM == 3) {
        $vocSCM = 10;
      } elsif ($vocSCM == 2) {
        $vocSCM = 1;
      } elsif ($vocSCM == 1) {
        $vocSCM = 0.1;
      } else {
        $vocSCM = 0.01;
      }
      my $vocConc = sprintf "%f", ($db_3 << 8 | $db_2) * $vocSCM;
      my %vocID = (
        0 => "VOCT",
        1 => "Formaldehyde",
        2 => "Benzene",
        3 => "Styrene",
        4 => "Toluene",
        5 => "Tetrachloroethylene",
        6 => "Xylene",
        7 => "n-Hexane",
        8 => "n-Octane",
        9 => "Cyclopentane",
        10 => "Methanol",
        11 => "Ethanol",
        12 => "1-Pentanol",
        13 => "Acetone",
        14 => "Ethylene Oxide",
        15 => "Acetaldehyde ue",
        16 => "Acetic Acid",
        17 => "Propionice Acid",
        18 => "Valeric Acid",
        19 => "Butyric Acid",
        20 => "Ammoniac",
        22 => "Hydrogen Sulfide",
        23 => "Dimethylsulfide",
        24 => "2-Butanol",
        25 => "2-Methylpropanol",
        26 => "Diethyl Ether",
        255 => "Ozone",
      );
      if ($vocID{$db_1}) {
        push @event, "3:vocName:$vocID{$db_1}";
      } else {
        push @event, "3:vocName:unknown";
      }
      push @event, "3:concentration:$vocConc";
      push @event, "3:state:$vocConc";

    } elsif ($st eq "particlesSensor.01") {
      # Gas Sensor, Particles Sensor (EEP A5-09-07)
      # [untested]
      # $db_3_bit_7 ... $db_2_bit_7 is the particle concentration < 10 µm
      # where 0 = 0 µg/m3 ... 511 = 511 µg/m3
      # $db_2_bit_6 ... $db_1_bit_6 is the particle concentration < 2.5 µm
      # where 0 = 0 µg/m3 ... 511 = 511 µg/m3
      # $db_1_bit_5 ... $db_0_bit_5 is the particle concentration < 1 µm
      # where 0 = 0 µg/m3 ... 511 = 511 µg/m3
      # $db_0_bit_2 = 1 = Sensor PM10 active
      # $db_0_bit_1 = 1 = Sensor PM2_5 active
      # $db_0_bit_0 = 1 = Sensor PM1 active
      my $pm_10 = "inactive";
      my $pm_2_5 = "inactive";
      my $pm_1 = "inactive";
      if ($db_0 & 4) {$pm_10 = $db_3 << 1 | $db_2 >> 7;}
      if ($db_0 & 2) {$pm_2_5 = ($db_2 & 0x7F) << 1 | $db_1 >> 7;}
      if ($db_0 & 1) {$pm_1 = ($db_1 & 0x3F) << 3 | $db_0 >> 5;}
      push @event, "3:particles_10:$pm_10";
      push @event, "3:particles_2_5:$pm_2_5";
      push @event, "3:particles_1:$pm_1";
      push @event, "3:state:PM10: $pm_10 PM2_5: $pm_2_5 PM1: $pm_1";

    } elsif ($st eq "roomSensorControl.05") {
      # Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)
      # [Eltako FTF55D, FTF55H, Thermokon SR04 *, Thanos SR *, untested]
      # $db_3 is the fan speed or night reduction for Eltako
      # $db_2 is the setpoint where 0x00 = min ... 0xFF = max or
      # reference temperature for Eltako whre 0x00 = 0°C ... 0xFF = 40°C
      # $db_1 is the temperature where 0x00 = +40°C ... 0xFF = 0°C
      # $db_0 bit D0 is the occupy button, pushbutton or slide switch
      my $temp = sprintf "%0.1f", 40 - $db_1 / 6.375;
      if ($manufID eq "00D") {
        my $nightReduction = 0;
        $nightReduction = 1 if ($db_3 == 0x06);
        $nightReduction = 2 if ($db_3 == 0x0c);
        $nightReduction = 3 if ($db_3 == 0x13);
        $nightReduction = 4 if ($db_3 == 0x19);
        $nightReduction = 5 if ($db_3 == 0x1f);
        my $setpointTemp = sprintf "%0.1f", $db_2 / 6.375;
        push @event, "3:state:T: $temp SPT: $setpointTemp NR: $nightReduction";
        push @event, "3:nightReduction:$nightReduction";
        push @event, "3:setpointTemp:$setpointTemp";
      } else {
        my $fspeed = 3;
        $fspeed = 2      if ($db_3 >= 145);
        $fspeed = 1      if ($db_3 >= 165);
        $fspeed = 0      if ($db_3 >= 190);
        $fspeed = "auto" if ($db_3 >= 210);
        my $switch = $db_0 & 1;
        push @event, "3:state:T: $temp SP: $db_2 F: $fspeed SW: $switch";
        push @event, "3:fan:$fspeed";
        push @event, "3:switch:$switch";
        push @event, "3:setpoint:$db_2";
      }
      push @event, "3:temperature:$temp";

    } elsif($st eq "roomSensorControl.01") {
      # Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)
      # [Thermokon SR04 * rH, Thanus SR *, untested]
      # $db_3 is the setpoint where 0x00 = min ... 0xFF = max
      # $db_2 is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db_1 is the temperature where 0x00 = 0°C ... 0xFA = +40°C
      # $db_0 bit D0 is the occupy button, pushbutton or slide switch
      my $temp = sprintf "%0.1f", $db_1 * 40 / 250;
      my $humi = sprintf "%d", $db_2 / 2.5;
      my $switch = $db_0 & 1;
      push @event, "3:state:T: $temp H: $humi SP: $db_2 SW: $switch";
      push @event, "3:humidity:$humi";
      push @event, "3:switch:$switch";
      push @event, "3:setpoint:$db_2";
      push @event, "3:temperature:$temp";

    } elsif($st eq "roomSensorControl.02") {
      # Room Sensor and Control Unit (A5-10-15 ... A5-10-17)
      # [untested]
      # $db_2 bit D7 ... D2 is the setpoint where 0 = min ... 63 = max
      # $db_2 bit D1 ... $db_1 bit D0 is the temperature where 0 = -10°C ... 1023 = +41.2°C
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $temp = sprintf "%0.2f", -10 + ((($db_2 & 3) << 8) | $db_1) / 19.98;
      my $setpoint = ($db_2 & 0xFC) >> 2;
      my $presence = $db_0 & 1 ? "absent" : "present";
      push @event, "3:state:T: $temp SP: $setpoint P: $presence";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";

    } elsif($st eq "roomSensorControl.18") {
      # Room Sensor and Control Unit (A5-10-18)
      # [untested]
      # $db_3 is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db_2 is the setpoint where 250 = 0 °C ... 0 = 40 °C
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux = $db_3 << 2;
      if ($db_3 == 251) {$lux = "over range";}
      my $setpoint = sprintf "%0.1f", 40 - $db_2 * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250;
      my $fanSpeed;
      if ((($db_0 & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db_0 & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db_0 & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db_0 & 2) {
        $presence = "disabled";
      } else {
        $presence = $db_0 & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed SP: $setpoint P: $presence";

    } elsif($st eq "roomSensorControl.19") {
      # Room Sensor and Control Unit (A5-10-19)
      # [untested]
      # $db_3 is the humidity where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db_2 is the setpoint where 250 = 0 °C ... 0 = 40 °C
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_1 is Occupany Button where 0 = pressed, 1 = released
      # $db_0_bit_0 is Occupany enable where 0 = enabled, 1 = disabled
      my $humi = $db_3 / 2.5;
      my $setpoint = sprintf "%0.1f", 40 - $db_2 * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250;
      my $fanSpeed;
      if ((($db_0 & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db_0 & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db_0 & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db_0 & 1) {
        $presence = "disabled";
      } else {
        $presence = $db_0 & 2 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:humidity:$humi";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi F: $fanSpeed SP: $setpoint P: $presence";

    } elsif($st eq "roomSensorControl.1A") {
      # Room Sensor and Control Unit (A5-10-1A)
      # [untested]
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_2 is the setpoint where 250 = 0 °C ... 0 = 40 °C
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      my $setpoint = sprintf "%0.1f", 40 - $db_2 * 40 / 250;
      my $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250;
      my $fanSpeed;
      if ((($db_0 & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db_0 & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db_0 & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db_0 & 2) {
        $presence = "disabled";
      } else {
        $presence = $db_0 & 1 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:T: $temp F: $fanSpeed SP: $setpoint P: $presence U: $voltage";

    } elsif($st eq "roomSensorControl.1B") {
      # Room Sensor and Control Unit (A5-10-1B)
      # [untested]
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_2 is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      my $lux = $db_2 << 2;
      if ($db_2 == 251) {$lux = "over range";}
      my $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250;
      my $fanSpeed;
      if ((($db_0 & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db_0 & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db_0 & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db_0 & 2) {
        $presence = "disabled";
      } else {
        $presence = $db_0 & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:temperature:$temp";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed P: $presence U: $voltage";

    } elsif($st eq "roomSensorControl.1C") {
      # Room Sensor and Control Unit (A5-10-1C)
      # [untested]
      # $db_3 is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db_2 is the illuminance setpoint where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux = $db_3 << 2;
      if ($db_3 == 251) {$lux = "over range";}
      my $setpoint = $db_2 << 2;
      my $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250;
      my $fanSpeed;
      if ((($db_0 & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db_0 & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db_0 & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db_0 & 2) {
        $presence = "disabled";
      } else {
        $presence = $db_0 & 1 ? "absent" : "present";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp B: $lux F: $fanSpeed SP: $setpoint P: $presence";

    } elsif($st eq "roomSensorControl.1D") {
      # Room Sensor and Control Unit (A5-10-1D)
      # [untested]
      # $db_3 is the humidity where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db_2 is the humidity setpoint where min 0x00 = 0 %rH, max 0xFA = 10 %rH
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $humi = $db_3 / 2.5;
      my $setpoint = $db_2 / 2.5;
      my $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250;
      my $fanSpeed;
      if ((($db_0 & 0x70) >> 4) == 0) {
        $fanSpeed = "auto";
      } elsif ((($db_0 & 0x70) >> 4) == 7) {
        $fanSpeed = "off";
      } else {
        $fanSpeed = (($db_0 & 0x70) >> 4) - 1;
      }
      my $presence;
      if ($db_0 & 2) {
        $presence = "disabled";
      } else {
        $presence = $db_0 & 1 ? "absent" : "present";
      }
      push @event, "3:fan:$fanSpeed";
      push @event, "3:humidity:$humi";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp H: $humi F: $fanSpeed SP: $setpoint P: $presence";

    } elsif($st eq "roomSensorControl.1F") {
      # Room Sensor and Control Unit (A5-10-1F)
      # [untested]
      # $db_3 is the fan speed
      # $db_2 is the setpoint where 0 = 0 ... 255 = 255
      # $db_1 is the temperature where 250 = 0 °C ... 0 = 40 °C
      # $db_0_bit_6 ... $db_0_bit_4 is the fan speed
      # $db_0_bit_6 ... $db_0_bit_4 are flags
      # $db_0_bit_1 is Occupany enable where 0 = enabled, 1 = disabled
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $fanSpeed = "unknown";
      if ($db_0 & 0x10) {
        $fanSpeed = 3;
        $fanSpeed = 2      if ($db_3 >= 145);
        $fanSpeed = 1      if ($db_3 >= 165);
        $fanSpeed = 0      if ($db_3 >= 190);
        $fanSpeed = "auto" if ($db_3 >= 210);
      }
      my $setpoint = "unknown";
      $setpoint = $db_2 if ($db_0 & 0x20);
      my $temp = "unknown";
      $temp = sprintf "%0.1f", 40 - $db_1 * 40 / 250 if ($db_0 & 0x40);
      my $presence = "unknown";
      $presence = "absent" if (!($db_0 & 2));
      $presence = "present" if (!($db_0 & 1));
      push @event, "3:fan:$fanSpeed";
      push @event, "3:presence:$presence";
      push @event, "3:setpoint:$setpoint";
      push @event, "3:temperature:$temp";
      push @event, "3:state:T: $temp F: $fanSpeed SP: $setpoint P: $presence";

    } elsif($st eq "tempHumiSensor.02") {
      # Temperatur and Humidity Sensor(EEP A5-04-02)
      # [Eltako FAFT60, FIFT63AP]
      # $db_3 is the voltage where 0x59 = 2.5V ... 0x9B = 4V, only at Eltako
      # $db_2 is the humidity where 0x00 = 0%rH ... 0xFA = 100%rH
      # $db_1 is the temperature where 0x00 = -20°C ... 0xFA = +60°C
      my $humi = sprintf "%d", $db_2 / 2.5;
      my $temp = sprintf "%0.1f", -20 + $db_1 * 80 / 250;
      my $battery = "unknown";
      if ($manufID eq "00D") {
        # Eltako sensor
        my $voltage = sprintf "%0.1f", $db_3 * 6.58 / 255;
        my $energyStorage = "unknown";
        if ($db_3 <= 0x58) {
          $energyStorage = "empty";
          $battery = "low";
        }
        elsif ($db_3 <= 0xDC) {
          $energyStorage = "charged";
          $battery = "ok";
        }
        else {
          $energyStorage = "full";
          $battery = "ok";
        }
        push @event, "3:battery:$battery";
        push @event, "3:energyStorage:$energyStorage";
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:state:T: $temp H: $humi B: $battery";
      push @event, "3:humidity:$humi";
      push @event, "3:temperature:$temp";

    } elsif ($st eq "lightSensor.01") {
      # Light Sensor (EEP A5-06-01)
      # [Eltako FAH60, FAH63, FIH63, Thermokon SR65 LI, untested]
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db_3 is the low illuminance for Eltako devices where
      # min 0x00 = 0 lx, max 0xFF = 100 lx, if $db_2 = 0
      # $db_2 is the illuminance (ILL2) where min 0x00 = 300 lx, max 0xFF = 30000 lx
      # $db_1 is the illuminance (ILL1) where min 0x00 = 600 lx, max 0xFF = 60000 lx
      # $db_0_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      my $voltage = "unknown";
      if ($manufID eq "00D") {
        if($db_2 == 0) {
          $lux = sprintf "%d", $db_3 * 100 / 255;
        } else {
          $lux = sprintf "%d", $db_2 * 116.48 + 300;
        }
      } else {
        $voltage = sprintf "0.1f", $db_3 * 0.02;
        if($db_0 & 1) {
          $lux = sprintf "%d", $db_2 * 116.48 + 300;
        } else {
          $lux = sprintf "%d", $db_1 * 232.94 + 600;
        }
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.02") {
      # Light Sensor (EEP A5-06-02)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db_2 is the illuminance (ILL2) where min 0x00 = 0 lx, max 0xFF = 510 lx
      # $db_1 is the illuminance (ILL1) where min 0x00 = 0 lx, max 0xFF = 1020 lx
      # $db_0_bit_0 is Range select where 0 = ILL1, 1 = ILL2
      my $lux;
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      if($db_0 & 1) {
        $lux = $db_2 << 1;
      } else {
        $lux = $db_1 << 2;
      }
      push @event, "3:voltage:$voltage";
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "lightSensor.03") {
      # Light Sensor (EEP A5-06-03)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_2_bit_7 ... $db_1_bit_6 is the illuminance where min 0x000 = 0 lx, max 0x3E8 = 1000 lx
      my $lux = $db_2 << 2 | $db_1 >> 6;
      if ($lux == 1001) {$lux = "over range";}
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      push @event, "3:voltage:$voltage";
      push @event, "3:brightness:$lux";
      push @event, "3:state:$lux";

    } elsif ($st eq "occupSensor.01") {
      # Occupancy Sensor (EEP A5-07-01)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_1 is PIR Status (motion) where 0 ... 127 = off, 128 ... 255 = on
      my $motion = "off";
      if ($db_1 >= 128) {$motion = "on";}
      if ($db_0 & 1) {push @event, "3:voltage:" . sprintf "0.1f", $db_3 * 0.02;}
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      push @event, "3:motion:$motion";
      push @event, "3:state:$motion";

    } elsif ($st eq "occupSensor.02") {
      # Occupancy Sensor (EEP A5-07-02)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_0_bit_7 is PIR Status (motion) where 0 = off, 1 = on
      my $motion = $db_0 >> 7 ? "on" : "off";
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      push @event, "3:motion:$motion";
      push @event, "3:voltage:" . sprintf "0.1f", $db_3 * 0.02;
      push @event, "3:state:$motion";

    } elsif ($st eq "occupSensor.03") {
      # Occupancy Sensor (EEP A5-07-03)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_2_bit_7 ... $db_1_bit_6 is the illuminance where min 0x000 = 0 lx, max 0x3E8 = 1000 lx
      # $db_0_bit_7 is PIR Status (motion) where 0 = off, 1 = on
      my $motion = $db_0 >> 7 ? "on" : "off";
      my $lux = $db_2 << 2 | $db_1 >> 6;
      if ($lux == 1001) {$lux = "over range";}
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      push @event, "3:brightness:$lux";
      push @event, "3:motion:$motion";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:M: $motion E: $lux U: $voltage";

    } elsif ($st =~ m/^lightTempOccupSensor/) {
      # Light, Temperatur and Occupancy Sensor (EEP A5-08-01 ... A5-08-03)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFF = 5.1 V
      # $db_2 is the illuminance where min 0x00 = 0 lx, max 0xFF = 510 lx, 1020 lx, (2048 lx)
      # $db_1 is the temperature whrere 0x00 = 0 °C ... 0xFF = 51 °C or -30 °C ... 50°C
      # $db_0_bit_1 is PIR Status (motion) where 0 = on, 1 = off
      # $db_0_bit_0 is Occupany Button where 0 = pressed, 1 = released
      my $lux;
      my $temp;
      my $voltage = sprintf "%0.1f", $db_3 * 0.02;
      my $motion = $db_0 & 2 ? "off" : "on";
      my $presence = $db_0 & 1 ? "absent" : "present";

      if ($st eq "lightTempOccupSensor.01") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-01)
        # [Eltako FABH63, FBH55, FBH63, FIBH63]
        if ($manufID eq "00D") {
          $lux = sprintf "%d", $db_2 * 2048 / 255;
          push @event, "3:state:M: $motion E: $lux";
        } else {
          $lux = $db_2 << 1;
          $temp = sprintf "%0.1f", $db_1 * 0.2;
          push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
          push @event, "3:presence:$presence";
          push @event, "3:temperature:$temp";
          push @event, "3:voltage:$voltage";
        }
      } elsif ($st eq "lightTempOccupSensor.02") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-02)
        $lux = $db_2 << 2;
        $temp = sprintf "%0.1f", $db_1 * 0.2;
        push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
        push @event, "3:presence:$presence";
        push @event, "3:temperature:$temp";
        push @event, "3:voltage:$voltage";
      } elsif ($st eq "lightTempOccupSensor.03") {
        # Light, Temperatur and Occupancy Sensor (EEP A5-08-03)
        $lux = $db_2 * 6;
        $temp = sprintf "%0.1f", -30 + $db_1 * 80 / 255;
        push @event, "3:state:M: $motion E: $lux P: $presence T: $temp U: $voltage";
        push @event, "3:presence:$presence";
        push @event, "3:temperature:$temp";
        push @event, "3:voltage:$voltage";
      }
      push @event, "3:brightness:$lux";
      push @event, "3:motion:$motion";

    } elsif ($st eq "lightCtrlState.01") {
      # Lighting Controller State (EEP A5-11-01)
      # $db_3 is the illumination where 0x00 = 0 lx ... 0xFF = 510 lx
      # $db_2 is the illumination Setpoint where 0x00 = 0 ... 0xFF = 255
      # $db_1 is the Dimming Output Level where 0x00 = 0 ... 0xFF = 255
      # $db_0_bit_7 is the Repeater state where 0 = disabled, 1 = enabled
      # $db_0_bit_6 is the Power Relay Timer state where 0 = disabled, 1 = enabled
      # $db_0_bit_5 is the Daylight Harvesting state where 0 = disabled, 1 = enabled
      # $db_0_bit_4 is the Dimming mode where 0 = switching, 1 = dimming
      # $db_0_bit_2 is the Magnet Contact state where 0 = open, 1 = closed
      # $db_0_bit_1 is the Occupancy (prensence) state where 0 = absent, 1 = present
      # $db_0_bit_0 is the Power Relay state where 0 = off, 1 = on
      push @event, "3:brightness:" . ($db_3 << 1);
      push @event, "3:illum:$db_2";
      push @event, "3:dimValue:$db_1";
      push @event, "3:powerRelayTimer:" . ($db_0 & 0x80 ? "enabled" : "disabled");
      push @event, "3:repeater:" . ($db_0 & 0x40 ? "enabled" : "disabled");
      push @event, "3:daylightHarvesting:" . ($db_0 & 0x20 ? "enabled" : "disabled");
      push @event, "3:mode:" . ($db_0 & 0x10 ? "dimming" : "switching");
      push @event, "3:contact:" . ($db_0 & 4 ? "closed" : "open");
      push @event, "3:presence:" . ($db_0 & 2 ? "present" : "absent");
      push @event, "3:powerSwitch:" . ($db_0 & 1 ? "on" : "off");
      push @event, "3:state:" . ($db_0 & 1 ? "on" : "off");

    } elsif ($st eq "tempCtrlState.01") {
      # Temperature Controller Output (EEP A5-11-02)
      # $db_3 is the Control Variable where 0x00 = 0 % ... 0xFF = 100 %
      # $db_2 is the Fan Stage
      # $db_1 is the Actual Setpoint where 0x00 = 0 °C ... 0xFF = 51.2 °C
      # $db_0_bit_7 is the Alarm state where 0 = no, 1 = yes
      # $db_0_bit_6 ... $db_0_bit_5 is the Controller Mode
      # $db_0_bit_4 is the Controller State where 0 = auto, 1 = override
      # $db_0_bit_2 is the Energy hold-off where 0 = normal, 1 = hold-off
      # $db_0_bit_1 ... $db_0_bit_0is the Occupancy (prensence) state where 0 = present
      # 1 = absent, 3 = standby, 4 = frost
      push @event, "3:controlVar:" . sprintf "%d", $db_3 * 100 / 255;
      if (($db_2 & 3) == 0) {
        push @event, "3:fan:0";
      } elsif (($db_2 & 3) == 1){
        push @event, "3:fan:1";
      } elsif (($db_2 & 3) == 2){
        push @event, "3:fan:2";
      } elsif (($db_2 & 3) == 3){
        push @event, "3:fan:3";
      } elsif ($db_2 == 255){
        push @event, "3:fan:unknown";
      }
      push @event, "3:fanMode:" . ($db_2 & 0x10 ? "auto" : "manual");
      my $setpointTemp = sprintf "%0.1f", $db_1 * 0.2;
      push @event, "3:setpointTemp:$setpointTemp";
      push @event, "3:alarm:" . ($db_0 & 1 ? "on" : "off");
      my $controllerMode = ($db_0 & 0x60) >> 5;
      if ($controllerMode == 0) {
        push @event, "3:controllerMode:auto";
      } elsif ($controllerMode == 1) {
        push @event, "3:controllerMode:heating";
      } elsif ($controllerMode == 2) {
        push @event, "3:controllerMode:cooling";
      } elsif ($controllerMode == 3) {
        push @event, "3:controllerMode:off";
      }
      push @event, "3:controllerState:" . ($db_0 & 0x10 ? "override" : "auto");
      push @event, "3:energyHoldOff:" . ($db_0 & 4 ? "holdoff" : "normal");
      if (($db_0 & 3) == 0) {
        push @event, "3:presence:present";
      } elsif (($db_0 & 3) == 1){
        push @event, "3:presence:absent";
      } elsif (($db_0 & 3) == 2){
        push @event, "3:presence:standby";
      } elsif (($db_0 & 3) == 3){
        push @event, "3:presence:frost";
      }
      push @event, "3:state:$setpointTemp";

    } elsif ($st eq "shutterCtrlState.01") {
      # Blind Status (EEP A5-11-03)
      # $db_3 is the Shutter Position where 0 = 0 % ... 100 = 100 %
      # $db_2_bit_7 is the Angle sign where 0 = positive, 1 = negative
      # $db_2_bit_6 ... $db_2_bit_0 where 0 = 0° ... 90 = 180°
      # $db_1_bit_7 is the Positon Value Flag where 0 = no available, 1 = available
      # $db_1_bit_6 is the Angle Value Flag where 0 = no available, 1 = available
      # $db_1_bit_5 ... $db_1_bit_4 is the Error State (alarm)
      # $db_1_bit_3 ... $db_1_bit_2 is the End-position State
      # $db_1_bit_1 ... $db_1_bit_0 is the Shutter State
      # $db_0_bit_7 is the Service Mode where 0 = no, 1 = yes
      # $db_0_bit_6 is the Position Mode where 0 = normal, 1 = inverse
      push @event, "3:positon:" . $db_3;
      my $angle = ($db_2 & 0x7F) << 1;
      if ($db_2 & 80) {$angle *= -1;}
      push @event, "3:angle:" . $angle;
      my $alarm = ($db_1 & 0x30) >> 4;
      if ($alarm == 0) {
        push @event, "3:alarm:off";
      } elsif ($alarm == 1){
        push @event, "3:alarm:no endpoints defined";
      } elsif ($alarm == 2){
        push @event, "3:alarm:on";
      } elsif ($alarm == 3){
        push @event, "3:alarm:not used";
      }
      my $endPosition = ($db_1 & 0x0C) >> 2;
      if ($endPosition == 0) {
        push @event, "3:endPosition:not available";
        push @event, "3:state:not available";
      } elsif ($endPosition == 1) {
        push @event, "3:endPosition:not reached";
        push @event, "3:state:not reached";
      } elsif ($endPosition == 2) {
        push @event, "3:endPosition:open";
        push @event, "3:state:open";
      } elsif ($endPosition == 3){
        push @event, "3:endPosition:closed";
        push @event, "3:state:closed";
      }
      my $shutterState = $db_1 & 3;
      if (($db_1 & 3) == 0) {
        push @event, "3:shutterState:not available";
      } elsif (($db_1 & 3) == 1) {
        push @event, "3:shutterState:stopped";
      } elsif (($db_1 & 3) == 2){
        push @event, "3:shutterState:opens";
      } elsif (($db_1 & 3) == 3){
        push @event, "3:shutterState:closes";
      }
      push @event, "3:serviceOn:" . ($db_2 & 0x80 ? "yes" : "no");
      push @event, "3:positionMode:" . ($db_2 & 0x40 ? "inverse" : "normal");

    } elsif ($st eq "lightCtrlState.02") {
      # Extended Lighting Status (EEP A5-11-04)
      # $db_3 the contents of the variable depends on the parameter mode
      # $db_2 the contents of the variable depends on the parameter mode
      # $db_1 the contents of the variable depends on the parameter mode
      # $db_0_bit_7 is the Service Mode where 0 = no, 1 = yes
      # $db_0_bit_6 is the operating hours flag where 0 = not available, 1 = available
      # $db_0_bit_5 ... $db_0_bit_4 is the Error State (alarm)
      # $db_0_bit_2 ... $db_0_bit_1 is the parameter mode
      # $db_0_bit_0 is the lighting status where 0 = off, 1 = on
      push @event, "3:serviceOn:" . ($db_1 & 0x80 ? "yes" : "no");
      my $alarm = ($db_0 & 0x30) >> 4;
      if ($alarm == 0) {
        push @event, "3:alarm:off";
      } elsif ($alarm == 1){
        push @event, "3:alarm:lamp failure";
      } elsif ($alarm == 2){
        push @event, "3:alarm:internal failure";
      } elsif ($alarm == 3){
        push @event, "3:alarm:external periphery failure";
      }
      my $mode = ($db_0 & 6) >> 1;
      if ($mode == 0) {
        # dimmer value and lamp operating hours
        push @event, "3:dimValue:$db_3";
        if ($db_0 & 40) {
          push @event, "3:lampOpHours:" . ($db_2 << 8 | $db_1);
        } else {
          push @event, "3:lampOpHours:unknown";
        }
      } elsif ($mode == 1){
        # RGB value
        push @event, "3:RGB:$db_3 $db_2 $db_1";
      } elsif ($mode == 2){
        # energy metering value
        my @measureUnit = ("mW", "W", "kW", "MW", "Wh", "kWh", "MWh", "GWh",
                           "mA", "1/10 A", "mV", "1/10 V");
        push @event, "3:measuredValue:" . ($db_3 << 8 | $db_2);
        if (defined $measureUnit[$db_1]) {
          push @event, "3:measureUnit:" . $measureUnit[$db_1];
        } else {
          push @event, "3:measureUnit:unknown";
        }
      } elsif ($mode == 3){
        # not used
      }
      push @event, "3:powerSwitch:" . ($db_0 & 1 ? "on" : "off");
      push @event, "3:state:" . ($db_0 & 1 ? "on" : "off");

    } elsif ($st =~ m/^autoMeterReading/) {
      # Automated meter reading (AMR) (EEP A5-12-00 ... A5-12-03)
      # $db_3 (MSB) + $db_2 + $db_1 (LSB) is the Meter reading
      # $db_0_bit_7 ... $db_0_bit_4 is the Measurement channel
      # $db_0_bit_2 is the Data type where 0 = cumulative value, 1 = current value
      # $db_0_bit_1 ... $db_0_bit_0 is the Divisor where 0 = x/1, 1 = x/10,
      # 2 = x/100, 3 = x/1000
      # my $meterReading = hex sprintf "%02x%02x%02x", $db_3, $db_2, $db_1;
      my $dataType = ($db_0 & 4) >> 2;
      my $divisor = $db_0 & 3;
      if ($divisor == 3) {
        $divisor = 1000;
      } elsif ($divisor == 2) {
        $divisor = 100;
      } elsif ($divisor == 1) {
        $divisor = 10;
      } else {
        $divisor = 1;
      }
      my $meterReading = sprintf "%0.1f", ($db_3 << 16 | $db_2 << 8 | $db_1) / $divisor;
      my $channel = $db_0 >> 4;

      if ($st eq "autoMeterReading.00") {
        # Automated meter reading (AMR), Counter (EEP A5-12-01)
        # [Thermokon SR-MI-HS, untested]
        if ($dataType == 1) {
          # current value
          push @event, "3:currentValue:$meterReading";
          push @event, "3:state:$meterReading";
        } else {
          # cumulative counter
          push @event, "3:counter$channel:$meterReading";
        }
      } elsif ($st eq "autoMeterReading.01") {
        # Automated meter reading (AMR), Electricity (EEP A5-12-01)
        # [Eltako FSS12, FWZ12, DSZ14DRS, DSZ14WDRS]
        # $db_0_bit_7 ... $db_0_bit_4 is the Tariff info
        # $db_0_bit_2 is the Data type where 0 = cumulative value kWh,
        # 1 = current value W
        if ($dataType == 1) {
          # momentary power
          push @event, "3:power:$meterReading";
          push @event, "3:state:$meterReading";
        } elsif ($db_0 == 0x8F && $manufID eq "00D") {
          # Eltako, read meter serial number
          my $serialNumber;
          if ($db_0 == 0) {
            # first 2 digits of the serial number
            $serialNumber = printf "S-%01x%01x", $db_3 >> 4, $db_3 & 0x0F;
          } else {
            # last 4 digits of the serial number
            $serialNumber = substr (ReadingsVal($name, "serialNumber", "S---"), 0, 4);
            $serialNumber = printf "%4c%01x%01x%01x%01x", $serialNumber,
                            $db_2 >> 4, $db_2 & 0x0F, $db_3 >> 4, $db_3 & 0x0F;
          }
          push @event, "3:serialNumber:$serialNumber";
        } else {
          # power consumption
          push @event, "3:energy$channel:$meterReading";
          push @event, "3:currentTariff:$channel";
        }
      } elsif ($st eq "autoMeterReading.02" | $st eq "autoMeterReading.03") {
        # Automated meter reading (AMR), Gas, Water (EEP A5-12-02, A5-12-03)
        if ($dataType == 1) {
          # current value
          push @event, "3:flowrate:$meterReading";
          push @event, "3:state:$meterReading";
        } else {
          # cumulative counter
          push @event, "3:consumption$channel:$meterReading";
          push @event, "3:currentTariff:$channel";
        }
      }

    } elsif ($st eq "environmentApp") {
      # Environmental Applications (EEP A5-13-01 ... EEP A5-13-06, EEP A5-13-10)
      # [Eltako FWS61, untested]
      # $db_0_bit_7 ... $db_0_bit_4 is the Identifier
      my $identifier = $db_0 >> 4;
      if ($identifier == 1) {
        # Weather Station (EEP A5-13-01)
        # $db_3 is the dawn sensor where 0x00 = 0 lx ... 0xFF = 999 lx
        # $db_2 is the temperature where 0x00 = -40 °C ... 0xFF = 80 °C
        # $db_1 is the wind speed where 0x00 = 0 m/s ... 0xFF = 70 m/s
        # $db_0_bit_2 is day / night where 0 = day, 1 = night
        # $db_0_bit_1 is rain indication where 0 = no (no rain), 1 = yes (rain)
        my $dawn = sprintf "%d", $db_3 * 999 / 255;
        my $temp = sprintf "%0.1f", -40 + $db_2 * 120 / 255;
        my $windSpeed = sprintf "%0.1f", $db_1 * 70 / 255;
        my $dayNight = $db_0 & 2 ? "night" : "day";
        my $isRaining = $db_0 & 1 ? "yes" : "no";
        push @event, "3:brightness:$dawn";
        push @event, "3:dayNight:$dayNight";
        push @event, "3:isRaining:$isRaining";
        push @event, "3:temperature:$temp";
        push @event, "3:windSpeed:$windSpeed";
        push @event, "3:state:T: $temp B: $dawn W: $windSpeed IR: $isRaining";
      } elsif ($identifier == 2) {
        # Sun Intensity (EEP A5-13-02)
        # $db_3 is the sun exposure west where 0x00 = 1 lx ... 0xFF = 150 klx
        # $db_2 is the sun exposure south where 0x00 = 1 lx ... 0xFF = 150 klx
        # $db_1 is the sun exposure east where 0x00 = 1 lx ... 0xFF = 150 klx
        # $db_0_bit_2 is hemisphere where 0 = north, 1 = south
        push @event, "3:hemisphere:" . ($db_0 & 4 ? "south" : "north");
        push @event, "3:sunWest:" . sprintf "%d", 1 + $db_3 * 149999 / 255;
        push @event, "3:sunSouth:" . sprintf "%d", 1 + $db_2 * 149999 / 255;
        push @event, "3:sunEast:" . sprintf "%d", 1 + $db_1 * 149999 / 255;
      } elsif ($identifier == 7) {
        # Sun Position and Radiation (EEP A5-13-10)
        # $db_3_bit_7 ... $db_3_bit_1 is Sun Elevation where 0 = 0 ° ... 90 = 90 °
        # $db_3_bit_0 is day / night where 0 = day, 1 = night
        # $db_2 is Sun Azimuth where 0 = -90 ° ... 180 = 90 °
        # $db_1 and $db_0_bit_2 ... $db_0_bit_0 is Solar Radiation where
        # 0 = 0 W/m2 ... 2000 = 2000 W/m2
        my $sunElev = $db_3 >> 1;
        my $sunAzim = $db_2 - 90;
        my $solarRad = $db_1 << 3 | $db_0 & 7;
        push @event, "3:dayNight:" . ($db_3 & 1 ? "night" : "day");
        push @event, "3:solarRadiation:$solarRad";
        push @event, "3:sunAzimuth:$sunAzim";
        push @event, "3:sunElevation:$sunElev";
        push @event, "3:state:SRA: $solarRad SNA: $sunAzim SNE: $sunElev";
      } else {
        # EEP A5-13-03 ... EEP A5-13-06 not implemented
      }

    } elsif ($st eq "multiFuncSensor") {
      # Multi-Func Sensor (EEP A5-14-01 ... A5-14-06)
      # $db_3 is the voltage where 0x00 = 0 V ... 0xFA = 5.0 V
      # $db_3 > 0xFA is error code
      # $db_2 is the illuminance where min 0x00 = 0 lx, max 0xFA = 1000 lx
      # $db_0_bit_1 is Vibration where 0 = off, 1 = on
      # $db_0_bit_0 is Contact where 0 = closed, 1 = open
      my $lux = $db_2 << 2;
      if ($db_2 == 251) {$lux = "over range";}
      my $voltage = sprintf "0.1f", $db_3 * 0.02;
      if ($db_3 > 250) {push @event, "3:errorCode:$db_3";}
      my $vibration = $db_0 & 2 ? "on" : "off";
      my $contact = $db_0 & 1 ? "open" : "closed";
      push @event, "3:brightness:$lux";
      push @event, "3:contact:$contact";
      push @event, "3:vibration:$vibration";
      push @event, "3:voltage:$voltage";
      push @event, "3:state:C: $contact V: $vibration E: $lux U: $voltage";

    } elsif ($st =~ m/^digitalInput/) {
      # Digital Input (EEP A5-30-01, A5-30-02)
      my $contact;
      if ($st eq "digtalInput.01") {
        # Single Input Contact, Batterie Monitor (EEP A5-30-01)
        # [Thermokon SR65 DI, untested]
        # $db_2 is the supply voltage, if >= 121 = battery ok
        # $db_1 is the input state, if <= 195 = contact closed
        my $battery = $db_2 >= 121 ? "ok" : "low";
        $contact = $db_1 <= 195 ? "closed" : "open";
        push @event, "3:battery:$battery";
      } else {
        # Single Input Contact (EEP A5-30-01)
        # $db_0_bit_0 is the input state where 0 = closed, 1 = open
        $contact = $db_0 & 1 ? "open" : "closed";
      }
      push @event, "3:contact:$contact";
      push @event, "3:state:$contact";

    } elsif ($st eq "gateway") {
      # Gateway (EEP A5-38-08)
      # $db_3 is the command ID ($gwCmdID)
      # Eltako devices not send teach-in telegrams
      if(($db_0 & 8) == 0) {
        # teach-in, identify and store command type in attr gwCmd
        my $gwCmd = AttrVal($name, "gwCmd", undef);
        if (!$gwCmd) {
          $gwCmd = $EnO_gwCmd[$db_3 - 1];
          $attr{$name}{gwCmd} = $gwCmd;
        }
      }
      if ($db_3 == 1) {
        # Switching
        # Eltako devices not send A5 telegrams
        push @event, "3:executeTime:" . sprintf "%0.1f", (($db_2 << 8) | $db_1) / 10;
        push @event, "3:lock:" . ($db_0 & 4 ? "lock" : "unlock");
        push @event, "3:executeType" . ($db_0 & 2 ? "delay" : "duration");
        push @event, "3:state:" . ($db_0 & 1 ? "on" : "off");
      } elsif ($db_3 == 2) {
        # Dimming
        # $db_0_bit_2 is store final value, not used, because
        # dimming value is always stored
        push @event, "3:rampTime:$db_1";
        push @event, "3:state:" . ($db_0 & 0x01 ? "on" : "off");
        if ($db_0 & 4) {
          # Relative Dimming Range
          push @event, "3:dimValue:" . sprintf "%d", $db_2 * 100 / 255;
        } else {
          push @event, "3:dimValue:$db_2";
        }
        push @event, "3:dimValueLast:$db_2" if ($db_2 > 0);
      } elsif ($db_3 == 3) {
        # Setpoint shift
        # $db1 is setpoint shift where 0 = -12.7 K ... 255 = 12.8 K
        my $setpointShift = sprintf "%0.1f", -12.7 + $db_1 / 10;
        push @event, "3:setpointShift:$setpointShift";
        push @event, "3:state:$setpointShift";
      } elsif ($db_3 == 4) {
        # Basic Setpoint
        # $db1 is setpoint where 0 = 0 °C ... 255 = 51.2 °C
        my $setpoint = sprintf "%0.1f", $db_1 / 5;
        push @event, "3:setpoint:$setpoint";
        push @event, "3:state:$setpoint";
      } elsif ($db_3 == 5) {
        # Control variable
        # $db1 is control variable override where 0 = 0 % ... 255 = 100 %
        push @event, "3:controlVar:" . sprintf "%d", $db_1 * 100 / 255;
        my $controllerMode = ($db_0 & 0x60) >> 5;
        if ($controllerMode == 0) {
          push @event, "3:controllerMode:auto";
          push @event, "3:state:auto";
        } elsif ($controllerMode == 1) {
          push @event, "3:controllerMode:heating";
          push @event, "3:state:heating";
        } elsif ($controllerMode == 2){
          push @event, "3:controllerMode:cooling";
          push @event, "3:state:cooling";
        } elsif ($controllerMode == 3){
          push @event, "3:controllerMode:off";
          push @event, "3:state:off";
        }
        push @event, "3:controllerState:" . ($db_0 & 0x10 ? "override" : "auto");
        push @event, "3:energyHoldOff:" . ($db_0 & 4 ? "holdoff" : "normal");
        my $occupancy = $db_0 & 3;
        if ($occupancy == 0) {
          push @event, "3:presence:present";
        } elsif ($occupancy == 1){
          push @event, "3:presence:absent";
        } elsif ($occupancy == 2){
          push @event, "3:presence:standby";
        }
      } elsif ($db_3 == 6) {
        # Fan stage
        if ($db_1 == 0) {
          push @event, "3:fan:0";
          push @event, "3:state:0";
        } elsif ($db_1 == 1) {
          push @event, "3:fan:1";
          push @event, "3:state:1";
        } elsif ($db_1 == 2) {
          push @event, "3:fan:2";
          push @event, "3:state:2";
        } elsif ($db_1 == 3) {
          push @event, "3:fan:3";
          push @event, "3:state:3";
        } elsif ($db_1 == 255) {
          push @event, "3:fan:auto";
          push @event, "3:state:auto";
        }
      } else {
          push @event, "3:state:Gateway Command ID $db_3 unknown.";
      }

    } elsif ($st eq "manufProfile") {
      # Manufacturer Specific Applications (EEP A5-3F-7F)
      if ($manufID eq "002") {
        # [Thermokon SR65 3AI, untested]
        # $db_3 is the input 3 where 0x00 = 0 V ... 0xFF = 10 V
        # $db_2 is the input 2 where 0x00 = 0 V ... 0xFF = 10 V
        # $db_1 is the input 1 where 0x00 = 0 V ... 0xFF = 10 V
        my $input3 = sprintf "%0.2f", $db_3 * 10 / 255;
        my $input2 = sprintf "%0.2f", $db_2 * 10 / 255;
        my $input1 = sprintf "%0.2f", $db_1 * 10 / 255;
        push @event, "3:input1:$input1";
        push @event, "3:input2:$input2";
        push @event, "3:input3:$input3";
        push @event, "3:state:I1: $input1 I2: $input2 I3: $input3";
      } else {
        # Unknown Application
        push @event, "3:state:Manufacturer Specific Application unknown";
      }

    } elsif ($st eq "eltakoDimmer") {
      # Dimmer
      # todo: create a more general solution for the central-command responses
      if($db_3 eq 0x02) { # dim
        push @event, "3:state:" . ($db_0 & 0x01 ? "on" : "off");
        push @event, "3:dimValue:" . $db_2;
        if ($db_2 > 0) {
          push @event, "3:dimValueLast:" . $db_2;
        }
      }

    } elsif ($st eq "raw") {
      # raw
      push @event, "3:state:RORG: $rorg DATA: $data STATUS: $status ODATA: $odata";    
    
    } else {
    # unknown devices
      push @event, "3:state:$db_3";
      push @event, "3:sensor1:$db_3";
      push @event, "3:sensor2:$db_2";
      push @event, "3:sensor3:$db_1";
      push @event, "3:D3:".(($db_0&0x8)?1:0);
      push @event, "3:D2:".(($db_0&0x4)?1:0);
      push @event, "3:D1:".(($db_0&0x2)?1:0);
      push @event, "3:D0:".(($db_0&0x1)?1:0);
    }
  }

  readingsBeginUpdate($hash);
  for(my $i = 0; $i < int(@event); $i++) {
    # Flag & 1: reading, Flag & 2: changed. Currently ignored.
    my ($flag, $vn, $vv) = split(":", $event[$i], 3);
    readingsBulkUpdate($hash, $vn, $vv);
  }
  readingsEndUpdate($hash, 1);

  return $name;
}

# MD15Cmd
sub
EnOcean_MD15Cmd($$$)
{
  my ($hash, $name, $db_1) = @_;
  my $cmd = ReadingsVal($name, "CMD", undef);
  if($cmd) {
    my $msg; # Unattended
    my $arg1 = ReadingsVal($name, $cmd, 0); # Command-Argument
    if($cmd eq "actuator") {
#      $msg = sprintf("%02X000000", $arg1);
      $msg = sprintf("%02X7F0008", $arg1);
    } elsif($cmd eq "desired-temp") {
#      $msg = sprintf "%02X%02X0400", $arg1*255/40, AttrVal($name, "actualTemp", ($db_1*40/255)) * 255/40;
#      $msg = sprintf "%02X%02X0408", $arg1*255/40, AttrVal($name, "actualTemp", (255 - $db_1)*40/255) *255/40;
#      $msg = sprintf "%02X7F0408", $arg1*255/40;
       $msg = sprintf "%02X%02X0408", $arg1*255/40, AttrVal($name, "actualTemp", 127);
    } elsif($cmd eq "initialize") {
#      $msg = sprintf("00006400");
      $msg = "00006408";
    # Maintenance commands
    } elsif($cmd eq "runInit") {
      $msg = "00008108";
    } elsif($cmd eq "liftSet") {
      $msg = "00004108";
    } elsif($cmd eq "valveOpen") {
      $msg = "00002108";
    } elsif($cmd eq "valveClosed") {
      $msg = "00001108";
    }
    if($msg) {
      select(undef, undef, undef, 0.2);
      EnOcean_A5Cmd($hash, $msg, "00000000");
      if($cmd eq "initialize") {
        delete($defs{$name}{READINGS}{CMD});
        delete($defs{$name}{READINGS}{$cmd});
      }
    }
  }
}

# A5Cmd
sub
EnOcean_A5Cmd($$$)
{
  my ($hash, $msg, $org) = @_;
  IOWrite($hash, "000A0701", # varLen=0A optLen=07 msgType=01=radio,
          sprintf("A5%s%s0001%sFF00",$msg,$org,$hash->{DEF}));
          # type=A5 msg:4 senderId:4 status=00 subTelNum=01 destId:4 dBm=FF Security=00
}

# Undef
sub
EnOcean_Undef($$)
{
  my ($hash, $arg) = @_;
  delete $modules{EnOcean}{defptr}{uc($hash->{DEF})};
  return undef;
}

1;

=pod
=begin html

<a name="EnOcean"></a>
<h3>EnOcean</h3>
<ul>
  EnOcean devices are sold by numerous hardware vendors (e.g. Eltako, Peha, etc),
  using the RF Protocol provided by the EnOcean Alliance. Depending on the
  function of the device an specific device profile is used, called EnOcean
  Equipment Profile (EEP). Basically three profiles will be differed, e. g.
  switches, contacts, sensors. Some manufacturers use additional proprietary
  extensions. Further technical information can be found at the
  <a href="http://www.enocean-alliance.org/de/enocean_standard/">EnOcean Alliance</a>,
  see in particular the
  <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>
  <br><br>
  Fhem recognizes a number of devices automatically. In order to teach-in, for
  some devices the sending of confirmation telegrams has to be turned on.
  Some equipment types and/or device models must be manually specified.
  Do so using the <a href="#EnOceanattr">attributes</a>
  <a href="#subType">subType</a> and <a href="#model">model</a>, see chapter
  <a href="#EnOceanset">Set</a> and
  <a href="#EnOceanevents">Generated events</a>. With the help of additional
  <a href="#EnOceanattr">attributes</a>, the behavior of the devices can be
  changed separately.
  <br><br>
  The teach-in procedure depends on the type of the devices. Switches (EEP RORG
  F6) and contacts (EEP RORG D5) are recognized when receiving the first message.
  Contacts can also send a teach-in telegram. Fhem not need this telegram.
  Sensors (EEP RORG A5) has to send a teach-in telegram. The profile-less
  A5 teach-in procedure transfers no EEP profile identifier and no manufacturer
  ID. In this case Fhem does not recognize the device automatically. The proper
  device type must be set manually, use the <a href="#EnOceanattr">attributes</a>
  <a href="#subType">subType</a>, <a href="#manufID">manufID</a> and/or
  <a href="#model">model</a>. If the EEP profile identifier and the manufacturer
  ID are sent the device is clearly identifiable. FHEM automatically assigns
  these devices to the correct profile. Some A5 devices must be paired
  bidirectional, see <a href="#pairForSec">Bidirectional A5 Teach-In</a>.<br><br>
  Fhem supports many of most common EnOcean profiles and manufacturer-specific
  devices. Additional profiles and devices can be added if required.
  <br><br>
  In order to enable communication with EnOcean remote stations a
  <a href="#TCM">TCM</a> module is necessary.
  <br><br>

  <a name="EnOceandefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EnOcean &lt;def&gt;</code>
    <br><br>

    Define an EnOcean device, connected via a <a href="#TCM">TCM</a> modul. The
    &lt;def&gt; is the SenderID/DestinationID of the device (8 digit hex number).
    The <a href="#autocreate">autocreate</a> module may help you.<br>

    Example:
    <ul>
      <code>define switch1 EnOcean ffc54500</code><br>
    </ul><br>
    In order to control devices, you cannot reuse the SenderIDs/
    DestinationID of other devices (like remotes), instead you have to create
    your own, which must be in the allowed SenderID range of the underlying Fhem
    IO device. For this first query the <a href="#TCM">TCM</a> with the
    <code>get &lt;tcm&gt; idbase</code> command for the BaseID. You can use
    up to 127 IDs starting with the BaseID + 1 shown there. The BaseID is
    used for A5 devices with a bidectional teach-in only. If you are using an Fhem
    SenderID outside of the allowed range, you will see an ERR_ID_RANGE
    message in the Fhem log.<br>
    In order to control bidirectional F6 devices (switches, actors) with
    additional SenderIDs you can use the attributes <a href="#subDef">subDef</a>,
    <a href="#subDef0">subDef0</a> and <a href="#subDefI">subDefI</a>.<br>
    Fhem communicates unicast with the BaseID, if the A5 devices are teached-in with the
    <a href="#pairForSec"> Bidirectional A5 Teach-In</a> procedure. In this case
    Fhem send telegrams with its SenderID (BaseID) and the DestinationID of the
    device.<br><br>
  </ul>

  <a name="EnOceanset"></a>
  <b>Set</b>
  <ul>
    <li><a name="pairForSec">Bidirectional A5 Teach-In</a>
    <ul>
    <code>set &lt;name&gt; pairForSec &lt;t/s&gt;</code>
    <br><br>
    Set the EnOcean Transceiver module (TCM Modul) in the bidirectional pairing
    mode. A device, which is then also put in this state is to paired with
    Fhem bidirectional. Bidirectional pearing is only used for some EEP A5-xx-xx,
    e. g. EEP A5-20-01 (Battery Powered Actuator).
    <br>
    <code>name</code> is the name of the TCM Module . <code>t/s</code> is the
    time for the teach-in period.
    <br><br>
    Example:
    <ul><code>set TCM_0 pairForSec 600</code>
    <br><br>
    </ul>
    </ul>
    </li>

    <li>Switch, Pushbutton Switch, Bidirectional Actor (EEP F6-02-01 ... F6-03-02)<br>
    [Default subType]
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of A0, AI, B0, BI, C0, CI, D0, DI,
    combinations of these and released.  First and second action can be sent
    simultaneously. Separate first and second action with a comma.<br>
    In fact we are trying to emulate a PT200 type remote.<br>
    If you define an <a href="#eventMap">eventMap</a> attribute with on/off,
    then you will be able to easily set the device from the <a
    href="#FHEMWEB">WEB</a> frontend.<br>
    <a href="#setExtensions">set extensions</a> are supported, if the corresponding
    <a href="#eventMap">eventMap</a> specifies the <code>on</code> and <code>off</code>
    mappings.<br>
    With the help of additional <a href="#EnOceanattr">attributes</a>, the
    behavior of the devices can be adapt.
    <br><br>
    Example:
    <ul><code>
      set switch1 BI<br>
      set switch1 B0,CI<br>
      attr eventMap BI:on B0:off<br>
      set switch1 on<br>
    </code></ul><br>
    </ul>
    </li>

    <li>Staircase off-delay timer (EEP F6-02-01 ... F6-02-02)<br>
        [Eltako FTN14, tested with Eltako FTN14 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>released<br>
        start timer</li>
    </ul><br>
    Set attr eventMap to B0:on BI:off, attr subType to switch, attr
    webCmd to on:released and if needed attr switchMode to pushbutton manually.<br>
    Use the sensor type "Schalter" for Eltako devices. The Staircase
    off-delay timer is switched on when pressing "on" and the time will be started
    when pressing "released". "released" immediately after "on" is sent if
    the attr switchMode is set to "pushbutton".
    </li>
    <br><br>

    <li>Single Input Contact, Door/Window Contact<br>
        1BS Telegram (EEP D5-00-01)<br>
        [tested with Eltako FSR14]
    <ul>
        <li>closed<br>
          issue closed command</li>
         <li>open<br>
          issue open command</li>
        <li>teach<br>
          initiate teach-in mode</li>
    </ul></li>
        The attr subType must be contact. The attribute must be set manually.
    <br><br>

    <li>Battery Powered Actuator (EEP A5-20-01)<br>
        [Kieback&Peter MD15-FTL-xx]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>actuator setpoint/%<br>
          Set the actuator to the specifed setpoint (0-100)</li>
      <li>desired-temp &lt;value&gt;<br>
          Use the builtin PI regulator, and set the desired temperature to the
          specified degree. The actual value will be taken from the temperature
          reported by the MD15 or from the attribute actualTemp if it is set.</li>
      <li>runInit<br>
          Maintenance Mode (service on): Run init sequence.</li>
      <li>liftSet<br>
          Maintenance Mode (service on): Lift set</li>
      <li>valveOpen<br>
          Maintenance Mode (service on): Valve open</li>
      <li>valveClosed<br>
          Maintenance Mode (service on): Valve closed</li>
      <li>unattended<br>
          Do not regulate the actuator.</li>
    </ul><br>
    The attr subType must be MD15. This is done if the device was
    created by autocreate. To control the device, it must be bidirectional paired,
    see <a href="#pairForSec">Bidirectional A5 Teach-In</a>.<br>
    The command is not sent until the device wakes up and sends a mesage, usually
    every 10 minutes.
    </li>
    <br><br>

    <li><a name="Gateway">Gateway</a> (EEP A5-38-08)<br>
        The Gateway profile include 7 different commands (Switching, Dimming,
        Setpoint Shift, Basic Setpoint, Control variable, Fan stage, Blind Central Command).
        The commands can be selected by the attribute gwCmd or command line. The attribute
        entry has priority.<br>
    <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>&lt;gwCmd&gt; &lt;cmd&gt; [subCmd]<br>
          initiate Gateway commands by command line</li>
        <li>&lt;cmd&gt; [subCmd]<br>
          initiate Gateway commands if attribute gwCmd is set.</li>
    </ul><br>
       The attr subType must be gateway. Attribute gwCmd can also be set to
       switching|dimming|setpointShift|setpointBasic|controlVar|fanStage|blindCmd.<br>
       This is done if the device was created by autocreate.<br>
       For Eltako devices attributes must be set manually.
    </li>
    <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Switching<br>
         [Eltako FLC61, FSR14]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>on [lock|unlock]<br>
          issue switch on command</li>
        <li>off [lock|unlock]<br>
          issue switch off command</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be switching. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Dimming<br>
         [Eltako FUD12, FUD14, FUD61, FUD70, FSG14, ...]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>on [lock|unlock]<br>
          issue switch on command</li>
        <li>off [lock|unlock]<br>
          issue switch off command</li>
        <li>dim dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>dimup dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li>dimdown dim/% [rampTime/s [lock|unlock]]<br>
          issue dim command</li>
        <li><a href="#setExtensions">set extensions</a> are supported.</li>
     </ul><br>
        rampTime Range: t = 1 s ... 255 s or 0 if no time specified,
        for Eltako: t = 1 = fast dimming ... 255 = slow dimming or 0 = dimming speed on the dimmer used)<br>
        The attr subType must be gateway and gwCmd must be dimming. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. Use the sensor type "PC/FVS" for Eltako devices.
     </li>
     <br><br>

    <li>Gateway (EEP A5-38-08)<br>
        Dimming of fluorescent lamps<br>
        [Eltako FSG70, tested with Eltako FSG70 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>off<br>
        issue switch off command</li>
      <li><a href="#setExtensions">set extensions</a> are supported.</li>
    </ul><br>
    The attr subType must be gateway and gwCmd must be dimming. Set attr eventMap to B0:on BI:off,
    attr subTypeSet to switch and attr switchMode to pushbutton manually.<br>
    Use the sensor type "Richtungstaster" for Eltako devices.
    </li>
    <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Setpoint shift<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>shift 1/K <br>
          issue Setpoint shift</li>
     </ul><br>
        Setpoint Range: T = -12.7 K ... 12.8 K<br>
        The attr subType must be gateway and gwCmd must be setpointShift.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Basic Setpoint<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>basic t/&#176C<br>
          issue Basic Setpoint</li>
     </ul><br>
        Setpoint Range: t = 0 &#176C ... 51.2 &#176C<br>
        The attr subType must be gateway and gwCmd must be setpointBasic.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Control variable<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>presence present|absent|standby<br>
          issue Room occupancy</li>
        <li>energyHoldOff normal|holdoff<br>
          issue Energy hold off</li>
        <li>controllerMode auto|heating|cooling|off<br>
          issue Controller mode</li>
        <li>controllerState auto|override <0 ... 100> <br>
          issue Control variable override</li>
     </ul><br>
        Override Range: cvov = 0 % ... 100 %<br>
        The attr subType must be gateway and gwCmd must be controlVar.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Fan stage<br>
         [untested]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>stage 0 ... 3|auto<br>
          issue Fan Stage override</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be fanStage.
        This is done if the device was created by autocreate.<br>
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         <a name="Blind Command Central">Blind Command Central</a><br>
         [untested, experimental status]<br>
     <ul>
      <code>set &lt;name&gt; &lt;value&gt;</code>
      <br><br>
      where <code>value</code> is
        <li>teach<br>
          initiate teach-in mode</li>
        <li>status<br>
          Status request</li>
        <li>opens<br>
          issue blinds opens command</li>
        <li>up tu/s ta/s<br>
          issue roll up command</li>
        <li>closes<br>
          issue blinds closes command</li>
        <li>down td/s ta/s<br>
          issue roll down command</li>
        <li>position position/% &alpha;/&#176<br>
          drive blinds to postion with angle value</li>
        <li>stop<br>
          issue blinds stops command</li>
        <li>runtimeSet tu/s td/s<br>
          set runtime parameter</li>
        <li>angleSet ta/s<br>
          set angle configuration</li>
        <li>positionMinMax positionMin/% positionMin/%<br>
          set Min, Max values for position</li>
        <li>angleMinMax &alpha;s/&#176 &alpha;o/&#176<br>
          set slat angle for Shut und Open position</li>
        <li>positionLogic normal|inverse<br>
          set position logic</li>
     </ul><br>
        Runtime Range: tu|td = 0 s ... 255 s<br>
        Select a runtime up and a runtime down that is at least as long as the
        shading element or roller shutter needs to move from its end position to
        the other position.<br>
        Position Range: position = 0 % ... 100 %<br>
        Angle Time Range: ta = 0 s ... 25.5 s<br>
        Runtime value for the sunblind reversion time. Select the time to revolve
        the sunblind from one slat engle end psosition to the other end position.<br>
        Slat Angle: &alpha;|&alpha;s|&alpha;o = -180 &#176 ... 180 &#176<br>
        Position Logic, normal: Blinds fully opens corresponds to Position = 0 %<br>
        Position Logic, inverse: Blinds fully opens corresponds to Position = 100 %<br>
        The attr subType must be gateway and gwCmd must be blindCmd. The profile
        is linked with controller profile, see <a href="#Blind Status">Blind Status</a>.<br>
     </li>
     <br><br>

    <li><a name="Manufacturer Specific Applications">Manufacturer Specific Applications</a> (EEP A5-3F-7F)<br>
        Shutter<br>
        [Eltako FSB12, FSB14, FSB61, FSB70, tested with Eltako devices only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
        initiate teach-in mode</li>
      <li>up [position/%]<br>
        issue roll up command</li>
      <li>down [position/%]<br>
        issue roll down command</li>
      <li>position position/%<br>
        set shutter to position</li>
      <li>stop<br>
        issue stop command</li>
    </ul><br>
    Set attr subType to manufProfile, manufID to 00D and attr model to
    FSB14|FSB61|FSB70 manually.<br>
    Use the sensor type "Szenentaster/PC" for Eltako devices.
    </li>
    <br><br>

    <li><a name="RAW Command">RAW Command</a><br>
        <br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>RPS|1BS|4BS data [status]<br>
        sent data telegram</li>
    </ul><br>
    With the help of this command data messages in hexadecimal format can be sent.
    Telegram types (RORG) RPS, 1BS and 4BS are supported. For further information,
    see <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>. 
    <br>
    Set attr subType to raw manually.
    </li>
    <br><br>

    <li>Dimmer<br>
        [Eltako FUD12, FUD14, FUD61, FUD70, tested with Eltako devices only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
        initiate teach-in mode</li>
      <li>on<br>
        issue switch on command</li>
      <li>off<br>
        issue switch off command</li>
      <li>dim dim/% [dim time 1-100/%]<br>
        issue dim command</li>
      <li>dimup dim/% [dim time 1-100/%]<br>
        issue dim command</li>
      <li>dimdown dim/% [dim time 1-100/%]<br>
        issue dim command</li>
      <li><a href="#setExtensions">set extensions</a> are supported.</li>
    </ul><br>
    Old profile, use <a href="#Gateway">Gateway</a> alternative.<br>
    Set attr subType to eltakoDimmer manually.<br>
    Use the sensor type "PC/FVS" for Eltako devices.
    </li>
    <br><br>

    <li>Dimmer for fluorescent lamps<br>
        [Eltako FSG70, tested with Eltako FSG70 only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>on<br>
        issue switch on command</li>
      <li>off<br>
        issue switch off command</li>
      <li><a href="#setExtensions">set extensions</a> are supported.</li>
    </ul><br>
    Old profile, use <a href="#Gateway">Gateway</a> alternative.<br>
    Set attr subType to eltakoDimmer, attr subTypeSet to switch, attr eventMap
    to B0:on BI:off and attr switchMode to pushbutton manually.<br>
    Use the sensor type "Richtungstaster" for Eltako devices.
    </li>
    <br><br>

    <li>Shutter (EEP F6-02-01 ... F6-02-02 and A5-3F-7F)<br>
        [Eltako FSB12, FSB14, FSB61, FSB70, tested with Eltako devices only]<br>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is
      <li>teach<br>
        initiate teach-in mode</li>
      <li>up [position/%]<br>
        issue roll up command</li>
      <li>down [position/%]<br>
        issue roll down command</li>
      <li>stop<br>
        issue stop command</li>
    </ul><br>
    Old profile, use <a href="#Manufacturer Specific Applications">Manufacturer Specific Applications</a>
    alternative.<br>
    Set attr subType to eltakoShutter and attr model to
    FSB14|FSB61|FSB70 manually.<br>
    Use the sensor type "Szenentaster/PC" for Eltako devices.
    </li>
  </ul>
  <br>

  <a name="EnOceanget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="EnOceanattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="actualTemp">actualTemp</a> t/&#176C<br>
      The value of the actual temperature, used when controlling MD15 devices.
      Should by filled via a notify from a distinct temperature sensor. If
      absent, the reported temperature from the MD15 is used.
      </li>
    <li><a href="#devStateIcon">devStateIcon</a></li>
    <li><a name="dimTime">dimTime</a> relative, [dimTime] = 1 is default.<br>
      No ramping or for Eltako dimming speed set on the dimmer if [dimTime] = 0.<br>
      Ramping time which fast to low dimming if [dimTime] = 1 ... 100.<br>
      dimTime is supported for dimmer.
      </li>
    <li><a name="dimValueOn">dimValueOn</a> dim/%|last|stored,
      [dimValueOn] = 100 is default.<br>
      Dim value for the command "on".<br>
      The dimmer switched on with the value 1 % ... 100 % if [dimValueOn] =
      1 ... 100.<br>
      The dimmer switched to the last dim value received from the
      bidirectional dimmer if [dimValueOn] = last.<br>
      The dimmer switched to the last Fhem dim value if [dimValueOn] =
      stored.<br>
      dimValueOn is supported for dimmer.
      </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a name="gwCmd">gwCmd</a> switching|dimming|setpointShift|setpointBasic|controlVar|fanStage|blindCmd<br>
      Gateway Command Type, see <a href="#Gateway">Gateway</a> profile
      </li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a></li>
    <li><a name="rampTime">rampTime</a> t/s or relative, [rampTime] = 1 is default.<br>
      No ramping or for Eltako dimming speed set on the dimmer if [rampTime] = 0.<br>
      Ramping time 1 s to 255 s or relative fast to low dimming speed if [rampTime] = 1 ... 255.<br>
      rampTime is supported for gateway, command dimming.
      </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    <li><a name="repeatingAllowed">repeatingAllowed</a> yes|no,
      [repeatingAllowed] = yes is default.<br>
      EnOcean Repeater in the transmission range of Fhem may forward data messages
      of the device, if the attribute is set to yes.
    </li>
    <li><a href="#showtime">showtime</a></li>
    <li><a name="shutTime">shutTime</a> t/s, [shutTime] = 1 ... 255, 255 is default.<br>
      Use the attr shutTime to set the time delay to the position "Halt" in
      seconds. Select a delay time that is at least as long as the shading element
      or roller shutter needs to move from its end position to the other position.<br>
      shutTime is supported for shutter.
      </li>
    <li><a name="subDef">subDef</a> &lt;EnOcean SenderID&gt;,
      [subDef] = [def] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) to control a bidirectional switch or actor.<br>
      In order to control bidirectional devices, you cannot reuse the ID of this
      devices, instead you have to create your own, which must be in the
      allowed ID-Range of the underlying IO device. For this first query the
      <a href="#TCM">TCM</a> with the "<code>get &lt;tcm&gt; idbase</code>" command. You can use
      up to 128 IDs starting with the base shown there.<br>
      subDef is supported for switches, staircase off-delay timer, dimmer and
      shutter.
      </li>
    <li><a name="subDef0">subDef0</a> &lt;EnOcean SenderID&gt;,
      [subDef0] = [def] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = A0|B0|C0|D0|released<br>
      Used with switch type "central". Set attr switchType to central.<br>
      Use the sensor type "zentral aus/ein" for Eltako devices.<br>
      subDef0 is supported for switches.<br>
      Second action is not sent.
      </li>
    <li><a name="subDefI">subDefI</a> &lt;EnOcean SenderID&gt;,
      [subDefI] = [def] is default.<br>
      SenderID (<a href="#TCM">TCM</a> BaseID + offset) for [value] = AI|BI|CI|DI<br>
      Used with switch type "central". Set attr switchType to central.<br>
      Use the sensor type "zentral aus/ein" for Eltako devices.<br>
      subDefI is supported for switches.<br>
      Second action is not sent.
      </li>
    <li><a href="#subType">subType</a></li>
    <li><a name="subTypeSet">subTypeSet</a> &lt;type of device&gt;, [subTypeSet] = [subType] is default.<br>
      Type of device (EEP Profile) used for sending commands. Set the Attribute manually.
      The profile has to fit their basic profile. More information can be found in the basic profiles.
    </li>
    <li><a name="switchMode">switchMode</a> switch|pushbutton,
      [SwitchMode] = switch is default.<br>
      The set command "released" immediately after &lt;value&gt; is sent if the
      attribute is set to "pushbutton".
    </li>
    <li><a name="switchType">switchType</a> direction|universal|central,
      [SwitchType] = direction is default.<br>
      EnOcean Devices support different types of sensors, e. g. direction
      switch, universal switch or pushbutton, central on/off.<br>
      For Eltako devices these are the sensor types "Richtungstaster",
      "Universalschalter" or "Universaltaster", "Zentral aus/ein".<br>
      With the sensor type <code>direction</code> switch on/off commands are
      accepted, e. g. B0, BI, released. Fhem can control an device with this
      sensor type unique. This is the default function and should be
      preferred.<br>
      Some devices only support the sensor type <code>universal switch
      </code> or <code>pushbutton</code>. With a Fhem command, for example,
      B0 or BI is switched between two states. In this case Fhem cannot
      control this device unique. But if the Attribute <code>switchType
      </code> is set to <code>universal</code> Fhem synchronized with
      a bidirectional device and normal on/off commands can be used.
      If the bidirectional device response with the channel B
      confirmation telegrams also B0 and BI commands are to be sent,
      e g. channel A with A0 and AI. Also note that confirmation telegrams
      needs to be sent.<br>
      Partly for the sensor type <code>central</code> two different SenderID
      are required. In this case set the Attribute <code>switchType</code> to
      <code>central</code> and define the Attributes
      <a href="#subDef0">subDef0</a> and <a href="#subDefI">subDefI</a>.
      </li>
    <li><a href="#webCmd">webCmd</a></li>
  </ul>
  <br>

  <a name="EnOceanevents"></a>
  <b>Generated events</b>
  <ul>
     <li>Switch / Bidirectional Actor (EEP F6-02-01 ... F6-03-02)<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>C0</li>
         <li>CI</li>
         <li>D0</li>
         <li>DI</li>
         <li>&lt;BtnX,BtnY&gt; First and second action where BtnX and BtnY is
             one of the above, e.g. A0,BI or D0,CI</li>
         <li>buttons: released</li>
         <li>buttons: &lt;BtnX&gt; released</li>
     </ul><br>
         Switches (remote controls) or actors with more than one
         (pair) keys may have multiple channels e. g. B0/BI, A0/AI with one
         SenderID or with separate addresses.
     </li>
     <br><br>

     <li>Pushbutton Switch, Pushbutton Input Module (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FT55, FSM12, FSM61, FTS12]<br>
     <ul>
         <li>A0</li>
         <li>AI</li>
         <li>B0</li>
         <li>BI</li>
         <li>released</li>
         <li>state: A0|AI|B0|BI|released</li>
     </ul><br>
         The status of the device may become "released", this
         is not the case for a normal switch.<br>
         Set attr model to FT55|FSM12|FSM61|FTS12 manually.
     </li>
     <br><br>

     <li>Smoke Detector (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FRW, untested]<br>
     <ul>
         <li>smoke-alarm</li>
         <li>off</li>
         <li>alarm: smoke-alarm|off</li>
         <li>battery: low|ok</li>
         <li>state: smoke-alarm|off</li>
     </ul><br>
        Set attr subType to FRW manually.
     </li>
     <br><br>

     <li>Key Card Activated Switch (EEP F6-04-01)<br>
         [Eltako FKC, FKF, FZS, untested]<br>
     <ul>
         <li>keycard inserted</li>
         <li>keycard removed</li>
         <li>state: keycard inserted|keycard removed</li>
     </ul><br>
         Set attr subType to keycard manually.
     </li>
     <br><br>

     <li>Window Handle (EEP F6-10-00)<br>
         [HOPPE SecuSignal]<br>
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>tilted</li>
         <li>open from tilted</li>
         <li>state: closed|open|tilted|open from tilted</li>
     </ul><br>
        The device should be created by autocreate.
     </li>
     <br><br>

     <li>Single Input Contact, Door/Window Contact<br>
         1BS Telegram (EEP D5-00-01)<br>
         [Eltako FTK, Peha D 450 FU, STM-250, BSC ?]
     <ul>
         <li>closed</li>
         <li>open</li>
         <li>learnBtn: on</li>
         <li>state: open|closed</li>
     </ul></li>
        The device should be created by autocreate.
     <br><br>

     <li>Temperature Sensors with with different ranges (EEP A5-02-01 ... A5-02-30)<br>
         [Thermokon SR65, untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = &lt;t min&gt; &#176C ... &lt;t max&gt; &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be tempSensor.01 ... tempSensor.30. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperatur and Humidity Sensor (EEP A5-04-02)<br>
         [Eltako FAFT60, FIFT63AP]<br>
     <ul>
       <li>T: t/&#176C H: rH/% B: unknown|low|ok</li>
       <li>battery: unknown|low|ok</li>
       <li>energyStorage: unknown|empty|charged|full</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -20 &#176C ... 60 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 6.6 V)
       <li>state: T: t/&#176C H: rH/% B: unknown|low|ok</li>
     </ul><br>
        The attr subType must be tempHumiSensor.02 and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-01)<br>
         [Eltako FAH60, FAH63, FIH63, Thermokon SR65 LI]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 300 lx ... 30 klx, 600 lx ... 60 klx
       , Sensor Range for Eltako: E = 0 lx ... 100 lx, 300 lx ... 30 klx)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: E/lx</li>
     </ul><br>
        Eltako devices only support Brightness.<br>
        The attr subType must be lightSensor.01 and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-02)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: 0 lx ... 1020 lx</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.1 V)</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light Sensor (EEP A5-06-03)<br>
         [untested]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>state: E/lx</li>
     </ul><br>
        The attr subType must be lightSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

      <li>Occupancy Sensor (EEP A5-07-01, A5-07-02)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>errorCode: 251 ... 255</li>
       <li>motion: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be occupSensor.<01|02>. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

      <li>Occupancy Sensor (EEP A5-07-03)<br>
         [untested]<br>
     <ul>
       <li>M: on|off E: E/lx U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>motion: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: M: on|off E: E/lx U: U/V</li>
     </ul><br>
        The attr subType must be occupSensor.03. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Light, Temperatur and Occupancy Sensor (EEP A5-08-01 ... A5-08-03)<br>
         [Eltako FABH63, FBH55, FBH63, FIBH63, Thermokon SR-MDS, PEHA 482 FU-BM DE]<br>
     <ul>
       <li>M: on|off E: E/lx P: absent|present T: t/&#176C U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 510, 1020, 1530 or 2048 lx)</li>
       <li>motion: on|off</li>
       <li>presence: absent|present</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51 &#176C or -30 &#176C ... 50 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: M: on|off E: E/lx P: absent|present T: t/&#176C U: U/V</li>
     </ul><br>
        Eltako and PEHA devices only support Brightness and Motion.<br>
        The attr subType must be lightTempOccupSensor.<01|02|03> and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO Sensor (EEP A5-09-01)<br>
         [untested]<br>
     <ul>
       <li>CO: c/ppm (Sensor Range: c = 0 ppm ... 255 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 255 &#176C)</li>
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be COSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO Sensor (EEP A5-09-02)<br>
         [untested]<br>
     <ul>
       <li>CO: c/ppm (Sensor Range: c = 0 ppm ... 1020 ppm)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51.0 &#176C)</li>
       <li>voltage: U/V</li> (Sensor Range: U = 0 V ... 5.1 V)
       <li>state: c/ppm</li>
     </ul><br>
        The attr subType must be COSensor.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, CO2 Sensor (EEP A5-09-04)<br>
         [Thermokon SR04 CO2 *, untested]<br>
     <ul>
       <li>airQuality: high|mean|moderate|low (Air Quality Classes DIN EN 13779)</li>
       <li>CO2: c/ppm (Sensor Range: c = 0 ppm ... 2550 ppm)</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 51 &#176C)</li>
       <li>state: CO2: c/ppm AQ: high|mean|moderate|low T: t/&#176C  H: rH/%</li>
     </ul><br>
        The attr subType must be tempHumiCO2Sensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Volatile organic compounds (VOC) Sensor (EEP A5-09-05)<br>
         [untested]<br>
     <ul>
       <li>concentration: c/ppb (Sensor Range: c = 0 ppb ...  655350 ppb)</li>
       <li>vocName: Name of last measured VOC</li>
       <li>state: c/ppb</li>
     </ul><br>
        The attr subType must be vocSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Radon Sensor (EEP A5-09-06)<br>
         [untested]<br>
     <ul>
       <li>Rn: A m3/Bq (Sensor Range: A = 0 Bq/m3 ... 1023 Bq/m3)</li>
       <li>state: A m3/Bq</li>
     </ul><br>
        The attr subType must be radonSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gas Sensor, Particles Sensor (EEP A5-09-07)<br>
         [untested]<br>
         Three channels with particle sizes of up to 10 &mu;m, 2.5 &mu;m and 1 &mu;m are supported<br>.
     <ul>
       <li>particles_10: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>particles_2_5: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>particles_1: p m3/&mu;g | inactive (Sensor Range: p = 0 &mu;g/m3 ... 511 &mu;g/m3)</li>
       <li>state: PM10: p m3/&mu;g PM2_5: p m3/&mu;g PM1: p m3/&mu;g</li>
     </ul><br>
        The attr subType must be particlesSensor.01. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

    <li>Room Sensor and Control Unit (EEP A5-10-01 ... A5-10-0D)<br>
         [Eltako FTF55, FTR55*, Thermokon SR04 *, Thanos SR *]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|auto SW: 0|1</li>
       <li>fan: 0|1|2|3|auto</li>
       <li>switch: 0|1</li>
       <li>setpoint: 0 ... 255</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|auto SW: 0|1</li><br>
       Alternatively for Eltako devices
       <li>T: t/&#176C SPT: t/&#176C NR: t/&#176C</li>
       <li>nightReduction: t/&#176C</li>
       <li>setpointTemp: t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C SPT: t/&#176C NR: t/&#176C</li><br>
     </ul><br>
        The attr subType must be roomSensorControl.05 and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-04-01, A5-10-10 ... A5-10-14)<br>
         [Thermokon SR04 * rH, Thanos SR *, untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% SP: 0 ... 255 SW: 0|1</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>switch: 0|1</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpoint: 0 ... 255</li>
       <li>state: T: t/&#176C H: rH/% SP: 0 ... 255 SW: 0|1</li>
     </ul><br>
         The attr subType must be roomSensorControl.01. This is
         done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-15 ... A5-10-17)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 63 P: absent|present</li>
       <li>presence: absent|present</li>
       <li>temperature: t/&#176C (Sensor Range: t = -10 &#176C ... 41.2 &#176C)</li>
       <li>setpoint: 0 ... 63</li>
       <li>state: T: t/&#176C SP: 0 ... 63 P: absent|present</li>
     </ul><br>
        The attr subType must be roomSensorControl.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-18)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.18. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-19)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.19. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1A)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled U: U/V</li>
       <li>errorCode: 251 ... 255</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: T: t/&#176C F: 0|1|2|3|4|5|auto|off SP: t/&#176C P: absent|present|disabled U: U/V</li>
     </ul><br>
        The attr subType must be roomSensorControl.1A. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1B, A5-10-1D)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off P: absent|present|disabled U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>errorCode: 251 ... 255</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off P: absent|present|disabled U: U/V</li>
     </ul><br>
        The attr subType must be roomSensorControl.1B. This is done if the device was
        created by autocreate.
     </li>
     <br><br>
     <li>Room Sensor and Control Unit (EEP A5-10-1C)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: E/lx P: absent|present|disabled</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C B: E/lx F: 0|1|2|3|4|5|auto|off SP: E/lx P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1C. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1D)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: rH/% P: absent|present|disabled</li>
       <li>humidity: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>fan: 0|1|2|3|4|5|auto|off</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: rH/% (Sensor Range: rH = 0 % ... 100 %)</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C H: rH/% F: 0|1|2|3|4|5|auto|off SP: rH/% P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1D. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-10-1F)<br>
         [untested]<br>
     <ul>
       <li>T: t/&#176C F: 0|1|2|3|auto SP: 0 ... 255 P: absent|present|disabled</li>
       <li>fan: 0|1|2|3|auto</li>
       <li>presence: absent|present|disabled</li>
       <li>setpoint: 0 ... 255</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: T: t/&#176C F: 0|1|2|3|auto SP: 0 ... 255 P: absent|present|disabled</li>
     </ul><br>
        The attr subType must be roomSensorControl.1F. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Lighting Controller State (EEP A5-11-01)<br>
         [untested]<br>
     <ul>
       <li>on|off</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 510 lx)</li>
       <li>contact: open|closed</li>
       <li>daylightHarvesting: enabled|disabled</li>
       <li>dimValue: 0 ... 255</li>
       <li>presence: absent|present</li>
       <li>illum: 0 ... 255</li>
       <li>mode: switching|dimming</li>
       <li>powerRelayTimer: enabled|disabled</li>
       <li>powerSwitch: on|off</li>
       <li>repeater: enabled|disabled</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be lightCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Temperature Controller Output (EEP A5-11-02)<br>
         [untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>alarm: on|off</li>
       <li>controlVar: cvar (Sensor Range: cvar = 0 % ... 100 %)</li>
       <li>controllerMode: auto|heating|cooling|off</li>
       <li>controllerState: auto|override</li>
       <li>energyHoldOff: normal|holdoff</li>
       <li>fan: 0 ... 3|auto</li>
       <li>presence: present|absent|standby|frost</li>
       <li>setpointTemp: t/&#176C (Sensor Range: t = 0 &#176C ... 51.2 &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be tempCtrlState.01 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li><a name="Blind Status">Blind Status</a> (EEP A5-11-03)<br>
         [untested, experimental status]<br>
     <ul>
       <li>open|closed|not reached|not available</li>
       <li>alarm: on|off|no endpoints defined|not used</li>
       <li>angle: &alpha;/&#176 (Sensor Range: &alpha; = -360 &#176 ... 360 &#176)</li>
       <li>endPosition: open|closed|not reached|not available</li>
       <li>position: pos/% (Sensor Range: pos = 0 % ... 100 %)</li>
       <li>serviceOn: yes|no</li>
       <li>shutterState: opens|closes|stopped|not available</li>
       <li>positionMode: normal|inverse</li>
       <li>state: open|closed|not reached|not available</li>
     </ul><br>
        The attr subType must be shutterCtrlState.01 This is done if the device was
        created by autocreate.<br>
        The profile is linked with <a href="#Blind Command Central">Blind Command Central</a>.
        The profile <a href="#Blind Command Central">Blind Command Central</a>
        controls the devices centrally. For that the attributes subDef, subTypeSet
        and gwCmd have to be set manually.
     </li>
     <br><br>

     <li>Extended Lighting Status (EEP A5-11-04)<br>
         [untested, experimental status]<br>
     <ul>
       <li>on|off</li>
       <li>alarm: off|lamp failure|internal failure|external periphery failure</li>
       <li>dimValue: 0 ... 255</li>
       <li>measuredValue: &lt;formula symbol&gt;/&lt;unit&gt; (Sensor range: &lt;formula symbol&gt; = 0 ... 65535 &lt;unit&gt;</li>
       <li>measureUnit: mW|W|kW|MW|Wh|kWh|MWh|GWh|mA|1/10 A|mV|1/10 V</li>
       <li>lampOpHours: t/h |unknown (Sensor range: t = 0 h ... 65535 h)</li>
       <li>powerSwitch: on|off</li>
       <li>RGB: R G B (RGB color component values: 0 ... 255)</li>
       <li>serviceOn: yes|no</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be lightCtrlState.02 This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Counter (EEP A5-12-00)<br>
         [Thermokon SR-MI-HS, untested]<br>
     <ul>
       <li>1/s</li>
       <li>currentValue: 1/s</li>
       <li>counter<0 ... 15>: 0 ... 16777215</li>
       <li>channel: 0 ... 15</li>
      <li>state: 1/s</li>
     </ul><br>
        The attr subType must be autoMeterReading.00. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Electricity (EEP A5-12-01)<br>
         [Eltako FSS12, DSZ14DRS, DSZ14WDRS, Thermokon SR-MI-HS, untested]<br>
         [Eltako FWZ12-16A tested]<br>
     <ul>
       <li>P/W</li>
       <li>power: P/W</li>
       <li>energy<0 ... 15>: E/kWh</li>
       <li>currentTariff: 0 ... 15</li>
       <li>serialNumber: S-&lt;nnnnnn&gt;</li>
      <li>state: P/W</li>
     </ul><br>
        The attr subType must be autoMeterReading.01 and attr
        manufID must be 00D for Eltako Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Automated meter reading (AMR), Gas, Water (EEP A5-12-02, A5-12-03)<br>
         [untested]<br>
     <ul>
       <li>Vs/l</li>
       <li>flowrate: Vs/l</li>
       <li>consumption<0 ... 15>: V/m3</li>
       <li>currentTariff: 0 ... 15</li>
      <li>state: Vs/l</li>
     </ul><br>
        The attr subType must be autoMeterReading.02|autoMeterReading.02.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Weather Station (EEP A5-13-01)<br>
         Sun Intensity (EEP A5-13-02)<br>
         [Eltako FWS61, untested]<br>
     <ul>
       <li>T: t/&#176C B: E/lx W: Vs/m IR: yes|no</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 999 lx)</li>
       <li>dayNight: day|night</li>
       <li>hemisphere: north|south</li>
       <li>isRaining: yes|no</li>
       <li>sunEast: E/lx (Sensor Range: E = 1 lx ... 150 klx)</li>
       <li>sunSouth: E/lx (Sensor Range: E = 1 lx ... 150 klx)</li>
       <li>sunWest: E/lx (Sensor Range: E = 1 lx ... 150 klx)</li>
       <li>temperature: t/&#176C (Sensor Range: t = -40 &#176C ... 80 &#176C)</li>
       <li>windSpeed: Vs/m (Sensor Range: V = 0 m/s ... 70 m/s)</li>
       <li>state:T: t/&#176C B: E/lx W: Vs/m IR: yes|no</li>
     </ul><br>
        Brightness is the strength of the dawn light. SunEast,
        sunSouth and sunWest are the solar radiation from the respective
        compass direction. IsRaining is the rain indicator.<br>
        The attr subType must be environmentApp and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by
        autocreate.<br>
        The Eltako Weather Station FWS61 supports not the day/night indicator
        (dayNight).<br>
        EEP A5-13-03 ... EEP A5-13-06 are not implemented.
     </li>
     <br><br>

     <li>Environmental Applications<br>
         EEP A5-13-03 ... EEP A5-13-06 are not implemented.
     </li>
     <br><br>

     <li>Environmental Applications<br>
         Sun Position and Radiation (EEP A5-13-10)<br>
         [untested]<br>
     <ul>
       <li>SRA: E m2/W SNA: &alpha;/&deg; SNE: &beta;/&deg;</li>
       <li>dayNight: day|night</li>
       <li>solarRadiation: E m2/W (Sensor Range: E = 0 W/m2 ... 2000 W/m2)</li>
       <li>sunAzimuth: &alpha;/&deg; (Sensor Range: &alpha; = -90 &deg; ... 90 &deg;)</li>
       <li>sunElevation: &beta;/&deg; (Sensor Range: &beta; = 0 &deg; ... 90 &deg;)</li>
       <li>state:SRA: E m2/W SNA: &alpha;/&deg; SNE: &beta;/&deg;</li>
     </ul><br>
        The attr subType must be environmentApp. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

      <li>Multi-Func Sensor (EEP A5-14-01 ... A5-14-06)<br>
         [untested]<br>
     <ul>
       <li>C: open|closed V: on|off E: E/lx U: U/V</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx, over range)</li>
       <li>contact: open|closed</li>
       <li>errorCode: 251 ... 255</li>
       <li>vibration: on|off</li>
       <li>voltage: U/V (Sensor Range: U = 0 V ... 5.0 V)</li>
       <li>state: C: open|closed V: on|off E: E/lx U: U/V</li>
     </ul><br>
        The attr subType must be multiFuncSensor. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Battery Powered Actuator (EEP A5-20-01)<br>
         [Kieback&Peter MD15-FTL-xx]<br>
     <ul>
       <li>Actuator/%</li>
       <li>actuator: ok|obstructed</li>
       <li>battery: ok|low</li>
       <li>currentValue: Actuator/%</li>
       <li>cover: open|closed</li>
       <li>energyInput: enabled|disabled</li>
       <li>energyStorage: charged|empty</li>
       <li>selfCtl: on|off</li>
       <li>serviceOn: yes|no</li>
       <li>temperature: t/&#176C</li>
       <li>tempSensor: failed|ok</li>
       <li>window: open|closed</li>
       <li>state: Actuator/%</li>
     </ul><br>
        The attr subType must be MD15. This is done if the device was created by
        autocreate.
     </li>
     <br><br>

     <li>Digital Input (EEP A5-30-01, A5-30-02)<br>
         [Thermokon SR65 DI, untested]<br>
     <ul>
       <li>open|closed</li>
       <li>battery: ok|low (only EEP A5-30-01)</li>
       <li>contact: open|closed</li>
      <li>state: open|closed</li>
     </ul><br>
        The attr subType must be digitalInput.01 or digitalInput.02. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Switching<br>
         [Eltako FLC61, FSR14]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>executeTime: t/s (Sensor Range: t = 0.1 s ... 6553.5 s or 0 if no time specified)</li>
       <li>executeType: duration|delay</li>
       <li>lock: lock|unlock</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be gateway and gwCmd must be switching. This is done if the device was
        created by autocreate.<br>
        For Eltako devices attributes must be set manually. Eltako devices only send on/off.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Dimming<br>
         [Eltako FUD14, FUD61, FUD70, FSG14, ...]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>dimValue: dim/% (Sensor Range: dim = 0 % ... 100 %)</li>
       <li>dimValueLast: dim/%<br>
           Last value received from the bidirectional dimmer.</li>
       <li>dimValueStored: dim/%<br>
           Last value saved by <code>set &lt;name&gt; dim &lt;value&gt;</code>.</li>
       <li>rampTime: t/s (Sensor Range: t = 1 s ... 255 s or 0 if no time specified,
           for Eltako: t = 1 = fast dimming ... 255 = slow dimming or 0 = dimming speed on the dimmer used)</li>
       <li>state: on|off</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be dimming and attr manufID must be 00D
        for Eltako Devices. This is done if the device was created by autocreate.<br>
        For Eltako devices attributes must be set manually. Eltako devices only send on/off and dimValue.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Setpoint shift<br>
         [untested]<br>
     <ul>
       <li>1/K</li>
       <li>setpointShift: 1/K (Sensor Range: T = -12.7 K ... 12.8 K)</li>
       <li>state: 1/K</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be setpointShift.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Basic Setpoint<br>
         [untested]<br>
     <ul>
       <li>t/&#176C</li>
       <li>setpoint: t/&#176C (Sensor Range: t = 0 &#176C ... 51.2 &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be setpointBasic.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Control variable<br>
         [untested]<br>
     <ul>
       <li>auto|heating|cooling|off</li>
       <li>controlVar: cvov (Sensor Range: cvov = 0 % ... 100 %)</li>
       <li>controllerMode: auto|heating|cooling|off</li>
       <li>controllerState: auto|override</li>
       <li>energyHoldOff: normal|holdoff</li>
       <li>presence: present|absent|standby</li>
       <li>state: auto|heating|cooling|off</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be controlVar.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Gateway (EEP A5-38-08)<br>
         Fan stage<br>
         [untested]<br>
     <ul>
       <li>0 ... 3|auto</li>
       <li>state: 0 ... 3|auto</li>
     </ul><br>
        The attr subType must be gateway, gwCmd must be fanStage.
        This is done if the device was created by autocreate.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Wireless Analog Input Module<br>
         [Thermokon SR65 3AI, untested]<br>
     <ul>
       <li>I1: U/V I2: U/V I3: U/V</li>
       <li>input1: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>input2: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>input3: U/V (Sensor Range: U = 0 V ... 10 V)</li>
       <li>state: I1: U/V I2: U/V I3: U/V</li>
     </ul><br>
        The attr subType must be manufProfile and attr manufID must be 002
        for Thermokon Devices. This is done if the device was
        created by autocreate.
     </li>
     <br><br>

     <li>Manufacturer Specific Applications (EEP A5-3F-7F)<br><br>
         Shutter (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FSB12, FSB14, FSB61, FSB70]<br>
     <ul>
        <li>B0<br>
            The status of the device will become "B0" after the TOP endpoint is
            reached, or it has finished an "up" or "position 0" command.</li>
        <li>BI<br>
            The status of the device will become "BI" if the BOTTOM endpoint is
            reached</li>
        <li>released<br>
            The status of the device become "released" between one of the endpoints.</li>
        <li>state: BO|BI|released</li>
     </ul><br>
        Set attr subType to manufProfile, attr manufID to 00D and attr model to
        FSB14|FSB61|FSB70 manually.
     </li>
     <br><br>

    <li><a name="RAW Command">RAW Command</a><br>
        <br>
    <ul>
       <li>RORG: RPS|1BS|4BS</li>
       <li>dataSent: data (Range: 0x00 ... 0xFF or 0x00000000 ... 0xFFFFFFFF)</li>
       <li>statusSent: status (Range: 0x00 ... 0xFF)</li>
       <li>state: RORG: rorg DATA: data STATUS: status ODATA: odata</li>
    </ul><br>
    With the help of this command data messages in hexadecimal format can be received.
    The telegram type (RORG) 4BS can be received. For further information,
    see <a href="http://www.enocean-alliance.org/eep/">EnOcean Equipment Profiles (EEP)</a>. 
    <br>
    Set attr subType to raw manually.
    </li>
    <br><br>

     <li>Dimmer<br>
         [Eltako FUD14, FUD61, FUD70, FSG14, FSG70, ...]<br>
     <ul>
        <li>on</li>
        <li>off</li>
        <li>dimValue: Dim/% (Sensor Range: Dim = 0 % ... 100 %)</li>
        <li>dimValueLast: Dim/%<br>
            Last value received from the bidirectional dimmer.</li>
        <li>dimValueStored: Dim/%<br>
            Last value saved by <code>set &lt;name&gt; dim &lt;value&gt;</code>.</li>
        <li>state: on|off</li>
     </ul><br>
        Old profile, use <a href="#Gateway">Gateway</a> alternative.<br>
        Set attr subType to eltakoDimmer manually.
     </li>
     <br><br>

     <li>Shutter (EEP F6-02-01 ... F6-02-02)<br>
         [Eltako FSB14, FSB61, FSB70]<br>
     <ul>
        <li>B0<br>
            The status of the device will become "B0" after the TOP endpoint is
            reached, or it has finished an "up %" command.</li>
        <li>BI<br>
            The status of the device will become "BI" if the BOTTOM endpoint is
            reached</li>
        <li>released<br>
            The status of the device become "released" between one of the endpoints.</li>
        <li>state: BO|BI|released</li>
     </ul><br>
        Old profile, use <a href="#Manufacturer Specific Applications">Manufacturer Specific Applications</a>
        alternative.<br>
        Set attr subType to eltakoShutter and attr model to FSB14|FSB61|FSB70 manually.
     </li>
     <br><br>

     <li>Temperature Sensor (EEP A5-02-05)<br>
         [Eltako FTF55]<br>
     <ul>
       <li>t/&#176C</li>
       <li>temperature: t/&#176C (Sensor Range: t = 0 &#176C ... 40 &#176C)</li>
       <li>state: t/&#176C</li>
     </ul><br>
        Old profile, use subType roomSensorControl.05 alternative.<br>
        Set attr subType to FTF or attr model to FTF55 manually.
     </li>
     <br><br>

     <li>Room Sensor and Control Unit (EEP A5-02-05, A5-10-03, A5-10-0C, A5-10-05,
         A5-10-06, A5-10-04, A5-10-01)<br>
         [Thermokon SR04 *]<br>
     <ul>
       <li>T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|Auto P: yes|no</li>
       <li>fan: 0|1|2|3|Auto</li>
       <li>learnBtn: on</li>
       <li>present: yes</li>
       <li>temperature: t/&#176C</li>
       <li>set_point: 0 ... 255</li>
       <li>state: T: t/&#176C SP: 0 ... 255 F: 0|1|2|3|Auto P: yes|no</li>
     </ul><br>
        Old profile, use subType roomSensorControl.05 alternative.<br>
        Set attr model to SR04|SR04P|SR04T|SR04PT|SR04PMS|SR04PS|SR04PST or
        attr subType to SR04.
     </li>
     <br><br>

     <li>Light Sensor (EEP similar A5-06-01)<br>
         [Eltako FAH60, FAH63, FIH63]<br>
     <ul>
       <li>E/lx</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 100 lx, 300 lx ... 30 klx)</li>
       <li>state: E/lx</li>
     </ul><br>
        Old profile, use subType lightSensor.01 alternative.<br>
        Set attr subType to FAH or attr model to FAH60|FAH63|FIH63
        manually.
     </li>
     <br><br>

     <li>Light and Occupancy Sensor (EEP similar A5-08-01)<br>
         [Eltako FABH63, FBH55, FBH63, FIBH63]<br>
     <ul>
       <li>yes</li>
       <li>no</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 2048 lx)</li>
       <li>motion: yes|no</li>
       <li>state: yes|no</li>
     </ul><br>
         Old profile, use subType lightTempOccupSensor.01 alternative.<br>
         Set attr subType to FBH or attr model to FABH63|FBH55|FBH63|FIBH63
         manually.
     </li>
     <br><br>

     <li>Light and Presence Sensor<br>
         [Omnio Ratio eagle-PM101]<br>
     <ul>
       <li>on</li>
       <li>off</li>
       <li>brightness: E/lx (Sensor Range: E = 0 lx ... 1000 lx)</li>
       <li>channel1: on|off</li> (Motion message in depending on the brightness threshold)
       <li>channel2: on|off</li> (Motion message)
       <li>motion: on|off</li> (Channel 2)
       <li>state: on|off</li> (Channel 2)
     </ul><br>
         The sensor also sends switching commands (RORG F6) with
         the senderID-1.<br>
         Set attr model to PM101 manually. Automatic teach-in is not possible,
         since no EEP and manufacturer ID are sent.
     </li>
  </ul>
</ul>

=end html
=cut

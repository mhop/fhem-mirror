##########################################################################
# This file is part of the smarthomatic module for FHEM.
#
# Copyright (c) 2014 Stefan Baumann, Uwe Freese
#
# You can find smarthomatic at www.smarthomatic.org.
# You can find FHEM at www.fhem.de.
#
# This file is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This file is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with smarthomatic. If not, see <http://www.gnu.org/licenses/>.
###########################################################################
# $Id: 37_SHCdev.pm xxxx 2014-xx-xx xx:xx:xx rr2000 $

package main;

use strict;
use feature qw(switch);
use warnings;
use SetExtensions;

use SHC_parser;

my $parser = new SHC_parser();

my %dev_state_icons = (
  "PowerSwitch" => "on:on:toggle off:off:toggle set.*:light_question:off",
  "Dimmer"      => "on:on off:off set.*:light_question:off",
  "EnvSensor"   => undef
);

my %web_cmds = (
  "PowerSwitch" => "on:off:toggle:statusRequest",
  "Dimmer"      => "on:off:statusRequest",
  "EnvSensor"   => undef
);

# Array format: [ reading1, str_format1, reading2, str_format2 ... ]
# "on" reading translates 0 -> "off"
#                         1 -> "on"
my %dev_state_format = (
  "PowerSwitch" => ["on", ""],
  "Dimmer"      => ["on", "", "brightness", "B: "],
  "EnvSensor" => [    # Results in "T: 23.4 H: 27.3 Baro: 978.34 B: 45"
    "temperature",         "T: ",
    "humidity",            "H: ",
    "barometric_pressure", "Baro: ",
    "brightness",          "B: ",
    "distance",            "D: "
  ]
);

# Supported set commands
# use "" if no set commands are available for device type
# use "cmd_name:cmd_additional_info"
#     cmd_additional_info: Description available at http://www.fhemwiki.de/wiki/DevelopmentModuleIntro#X_Set
my %sets = (
  "PowerSwitch" => "on:noArg off:noArg toggle:noArg statusRequest:noArg " .
                   # Used from SetExtensions.pm
                   "blink on-for-timer on-till off-for-timer off-till intervals",
  "Dimmer"      => "on:noArg off:noArg toggle:noArg statusRequest:noArg pct:slider,0,1,100 ani " .
                   # Used from SetExtensions.pm
                   "blink on-for-timer on-till off-for-timer off-till intervals",
  "EnvSensor"   => "",
  "Custom"      => "PowerSwitch.SwitchState " .
                   "PowerSwitch.SwitchStateExt " .
                   "Dimmer.Brightness " .
                   "Dimmer.Animation"
);

# Supported get commands
# use syntax from set commands
my %gets = (
  "PowerSwitch" => "",
  "Dimmer"      => "",
  "EnvSensor"   => "input:all,1,2,3,4,5,6,7,8 ",
  "Custom"      => ""
);

# Hashtable for automatic device type assignment
# Format:
# "MessageGroupName:MessageName" => "Auto Device Type"
my %auto_devtype = (
  "Weather.Temperature"                   => "EnvSensor",
  "Weather.HumidityTemperature"           => "EnvSensor",
  "Weather.BarometricPressureTemperature" => "EnvSensor",
  "Environment.Brightness"                => "EnvSensor",
  "Environment.Distance"                  => "EnvSensor",
  "GPIO.DigitalPin"                       => "EnvSensor",
  "PowerSwitch.SwitchState"               => "PowerSwitch",
  "Dimmer.Brightness"                     => "Dimmer"
);

sub SHCdev_Parse($$);

#####################################
sub SHCdev_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}    = "^Packet Data: SenderID=[1-9]|0[1-9]|[1-9][0-9]|[0-9][0-9][0-9]|[0-3][0-9][0-9][0-9]|40[0-8][0-9]|409[0-6]";
  $hash->{SetFn}    = "SHCdev_Set";
  $hash->{GetFn}    = "SHCdev_Get";
  $hash->{DefFn}    = "SHCdev_Define";
  $hash->{UndefFn}  = "SHCdev_Undef";
  $hash->{ParseFn}  = "SHCdev_Parse";
  $hash->{AttrList} = "IODev" 
                       ." readonly:1"
                       ." forceOn:1"
                       ." $readingFnAttributes"
                       ." devtype:EnvSensor,Dimmer,PowerSwitch";
}

#####################################
sub SHCdev_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if (@a < 3 || @a > 4) {
    my $msg = "wrong syntax: define <name> SHCdev <SenderID> [<AesKey>] ";
    Log3 undef, 2, $msg;
    return $msg;
  }

  # Correct SenderID for SHC devices is from 1 - 4096 (leading zeros allowed)
  $a[2] =~ m/^([1-9]|0[1-9]|[1-9][0-9]|[0-9][0-9][0-9]|[0-3][0-9][0-9][0-9]|40[0-8][0-9]|409[0-6])$/i;
  return "$a[2] is not a valid SHCdev SenderID" if (!defined($1));

  my $aeskey;

  if (@a == 3) {
    $aeskey = 0;
  } else {
    return "$a[3] is not a valid SHCdev AesKey" if ($a[3] lt 0 || $a[3] gt 15);
    $aeskey = $a[3];
  }

  my $name = $a[0];
  my $addr = $a[2];

  return "SHCdev device $addr already used for $modules{SHCdev}{defptr}{$addr}->{NAME}." if ($modules{SHCdev}{defptr}{$addr}
    && $modules{SHCdev}{defptr}{$addr}->{NAME} ne $name);

  $hash->{addr}   = $addr;
  $hash->{aeskey} = $aeskey;

  $modules{SHCdev}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if (defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  return undef;
}

#####################################
sub SHCdev_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete($modules{SHCdev}{defptr}{$addr});

  return undef;
}

#####################################
sub SHCdev_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  if (!$parser->parse($msg)) {
    Log3 $hash, 4, "SHC_TEMP: parser error: $msg";
    return "";
  }

  my $msgtypename  = $parser->getMessageTypeName();
  my $msggroupname = $parser->getMessageGroupName();
  my $msgname      = $parser->getMessageName();
  my $raddr        = $parser->getSenderID();
  my $rhash        = $modules{SHCdev}{defptr}{$raddr};
  my $rname        = $rhash ? $rhash->{NAME} : $raddr;

  if (!$modules{SHCdev}{defptr}{$raddr}) {
    Log3 $name, 3, "SHC_TEMP: Unknown device $rname, please define it";
    return "UNDEFINED SHCdev_$rname SHCdev $raddr";
  }

  if (($msgtypename ne "Status") && ($msgtypename ne "AckStatus")) {
    Log3 $name, 3, "$rname: Ignoring MessageType $msgtypename";
    return "";
  }

  Log3 $name, 4, "$rname: Msg: $msg";
  Log3 $name, 4, "$rname: MsgType: $msgtypename, MsgGroupName: $msggroupname, MsgName: $msgname";

  my @list;
  push(@list, $rname);
  $rhash->{SHCdev_lastRcv} = TimeNow();
  $rhash->{SHCdev_msgtype} = "$msggroupname : $msgname : $msgtypename";

  my $readonly = AttrVal($rname, "readonly", "0");

  readingsBeginUpdate($rhash);

  given ($msggroupname) {
    when ('Generic') {
      given ($msgname) {
        when ('BatteryStatus') {
          readingsBulkUpdate($rhash, "battery", $parser->getField("Percentage"));
        }
        when ('Version') {
          my $major = $parser->getField("Major");
          my $minor = $parser->getField("Minor");
          my $patch = $parser->getField("Patch");
          my $vhash = $parser->getField("Hash");

          readingsBulkUpdate($rhash, "version", "$major.$minor.$patch-$vhash");
        }
      }
    }
    when ('GPIO') {
      given ($msgname) {
        when ('DigitalPin') {
          my $pins = "";
          for (my $i = 0 ; $i < 8 ; $i++) {
            my $pinx = $parser->getField("On", $i);
            my $channel = $i + 1;
            readingsBulkUpdate($rhash, "pin" . $channel, $pinx);
            $pins .= $pinx;
          }
          readingsBulkUpdate($rhash, "pins", $pins);
        }
      }
    }
    when ('Weather') {
      given ($msgname) {
        when ('Temperature') {
          my $tmp = $parser->getField("Temperature") / 100;    # parser returns centigrade

          readingsBulkUpdate($rhash, "temperature", $tmp);
        }
        when ('HumidityTemperature') {
          my $hum = $parser->getField("Humidity") / 10;        # parser returns 1/10 percent
          my $tmp = $parser->getField("Temperature") / 100;    # parser returns centigrade

          readingsBulkUpdate($rhash, "humidity",    $hum);
          readingsBulkUpdate($rhash, "temperature", $tmp);
        }
        when ('BarometricPressureTemperature') {
          my $bar = $parser->getField("BarometricPressure") / 100;    # parser returns pascal, use hPa
          my $tmp = $parser->getField("Temperature") / 100;           # parser returns centigrade

          readingsBulkUpdate($rhash, "barometric_pressure", $bar);
          readingsBulkUpdate($rhash, "temperature",         $tmp);
        }
      }
    }
    when ('Environment') {
      given ($msgname) {
        when ('Brightness') {
          my $brt = $parser->getField("Brightness");
          readingsBulkUpdate($rhash, "brightness", $brt);
        }
        when ('Distance') {
          my $brt = $parser->getField("Distance");
          readingsBulkUpdate($rhash, "distance", $brt);
        }
      }
    }
    when ('PowerSwitch') {
      given ($msgname) {
        when ('SwitchState') {
          my $on      = $parser->getField("On");
          my $timeout = $parser->getField("TimeoutSec");

          readingsBulkUpdate($rhash, "on",      $on);
          readingsBulkUpdate($rhash, "timeout", $timeout);
        }
      }
    }
    when ('Dimmer') {
      given ($msgname) {
        when ('Brightness') {
          my $brightness = $parser->getField("Brightness");
          my $on = $brightness == 0 ? 0 : 1;

          readingsBulkUpdate($rhash, "on",         $on);
          readingsBulkUpdate($rhash, "brightness", $brightness);
        }
      }
    }
  }

  # Autoassign device type
  my $devtype = AttrVal( $rname, "devtype", undef );
  if (!defined($devtype) && (defined($auto_devtype{"$msggroupname.$msgname"}))) {
    $attr{$rname}{devtype} = $auto_devtype{"$msggroupname.$msgname"};
    Log3 $name, 3, "$rname: Autoassign device type = " . $attr{$rname}{devtype};
  }

  # If the devtype is defined add, if not already done, the according webCmds and devStateIcons
  my $devtype2 = AttrVal( $rname, "devtype", undef );
  if (defined($devtype2)) {
    if (!defined($attr{$rname}{devStateIcon}) && defined($dev_state_icons{$devtype2})) {
      $attr{$rname}{devStateIcon} = $dev_state_icons{$devtype2};
    }
    if (!defined($attr{$rname}{webCmd}) && defined($web_cmds{$devtype2})) {
      $attr{$rname}{webCmd} = $web_cmds{$devtype2};
    }
  }

  # Assemble state string according to %dev_state_format
  my $devtype3 = AttrVal( $rname, "devtype", undef );
  if (defined($devtype3) && defined($dev_state_format{$devtype3})) {
    my $state_format_arr = $dev_state_format{$devtype3};

    # Iterate over state_format array, if readings are available append it to the state string
    my $state_str = "";
    for (my $i = 0 ; $i < @$state_format_arr ; $i = $i + 2) {
      if ( defined($rhash->{READINGS}{$state_format_arr->[$i]})
        && defined($rhash->{READINGS}{$state_format_arr->[$i]}{VAL}))
      {
        my $val = $rhash->{READINGS}{$state_format_arr->[$i]}{VAL};

        if ($state_str ne "") {
          $state_str .= " ";
        }

        # "on" reading requires a special treatment because 0 translates to off, 1 translates to on
        if ($state_format_arr->[$i] eq "on") {
          $state_str .= $val == 0 ? "off" : "on";
        } else {
          $state_str .= $state_format_arr->[$i + 1] . $val;
        }
      }
    }
    readingsBulkUpdate($rhash, "state", $state_str);
  }

  readingsEndUpdate($rhash, 1);    # Do triggers to update log file

  return @list;
}

#####################################
sub SHCdev_Set($@)
{
  my ($hash, $name, @aa) = @_;
  my $cnt = @aa;

  my $cmd  = $aa[0];
  my $arg  = $aa[1];
  my $arg2 = $aa[2];
  my $arg3 = $aa[3];
  my $arg4 = $aa[4];

  return "\"set $name\" needs at least one parameter" if ($cnt < 1);

  # Return list of device-specific set-commands.
  # This list is used to provide the set commands in the web interface
  my $devtype = AttrVal( $name, "devtype", undef );
  if ($cmd eq "?") {
    if (!defined($devtype)) {
      return;
    } else {
      return $sets{$devtype};
    }
  }

  if (!defined($devtype)) {
    return "devtype not yet specifed. Currently supported device types are " . join(", ", sort keys %sets);
  }

  if (!defined($sets{$devtype})) {
    return "No set commands for " . $devtype . "device type supported ";
  }

  # TODO:
  # Currently the commands for every device type are defined in %sets but not used to verify the commands. Instead
  # the SetExtension.pm modulesis used for this purpose.
  # For more sophisticated device types this has to be revisited

  my $readonly = AttrVal($name, "readonly", "0");

  given ($devtype) {
    when ('PowerSwitch') {

      # Timeout functionality for SHCdev is not implemented, because FHEMs internal notification system
      # is able to do this as well. Even more it supports intervals, off-for-timer, off-till ...

      if ($cmd eq 'toggle') {
        $cmd = ReadingsVal($name, "state", "on") eq "off" ? "on" : "off";
      }

      if (!$readonly && $cmd eq 'off') {
        readingsSingleUpdate($hash, "state", "set-$cmd", 1);
        $parser->initPacket("PowerSwitch", "SwitchState", "SetGet");
        $parser->setField("PowerSwitch", "SwitchState", "TimeoutSec", 0);
        $parser->setField("PowerSwitch", "SwitchState", "On",         0);
        SHCdev_Send($hash);
      } elsif (!$readonly && $cmd eq 'on') {
        readingsSingleUpdate($hash, "state", "set-$cmd", 1);
        $parser->initPacket("PowerSwitch", "SwitchState", "SetGet");
        $parser->setField("PowerSwitch", "SwitchState", "TimeoutSec", 0);
        $parser->setField("PowerSwitch", "SwitchState", "On",         1);
        SHCdev_Send($hash);
      } elsif ($cmd eq 'statusRequest') {
        $parser->initPacket("PowerSwitch", "SwitchState", "Get");
        SHCdev_Send($hash);
      } else {
        return SetExtensions($hash, "", $name, @aa);
      }
    }
    when ('Dimmer') {

      # Timeout functionality for SHCdev is not implemented, because FHEMs internal notification system
      # is able to do this as well. Even more it supports intervals, off-for-timer, off-till ...

      if ($cmd eq 'toggle') {
        $cmd = ReadingsVal($name, "state", "on") eq "off" ? "on" : "off";
      }

      if (!$readonly && $cmd eq 'off') {
        readingsSingleUpdate($hash, "state", "set-$cmd", 1);
        $parser->initPacket("Dimmer", "Brightness", "SetGet");
        $parser->setField("Dimmer", "Brightness", "Brightness", 0);
        SHCdev_Send($hash);
      } elsif (!$readonly && $cmd eq 'on') {
        readingsSingleUpdate($hash, "state", "set-$cmd", 1);
        $parser->initPacket("Dimmer", "Brightness", "SetGet");
        $parser->setField("Dimmer", "Brightness", "Brightness", 100);
        SHCdev_Send($hash);
      } elsif (!$readonly && $cmd eq 'pct') {
        my $brightness = $arg;

        # DEBUG
        # Log3 $name, 3, "$name: Args: $arg, $arg2, $arg3, $brightness";

        readingsSingleUpdate($hash, "state", "set-pct:$brightness", 1);
        $parser->initPacket("Dimmer", "Brightness", "SetGet");
        $parser->setField("Dimmer", "Brightness", "Brightness", $brightness);
        SHCdev_Send($hash);
      } elsif (!$readonly && $cmd eq 'ani') {

        #TODO Verify argument values
        my $brightness = $arg;

        # DEBUG
        # Log3 $name, 3, "$name: ani args: $arg, $arg2, $arg3, $arg4, $brightness";

        readingsSingleUpdate($hash, "state", "set-ani", 1);
        $parser->initPacket("Dimmer", "Animation", "SetGet");
        $parser->setField("Dimmer", "Animation", "AnimationMode",   $arg);
        $parser->setField("Dimmer", "Animation", "TimeoutSec",      $arg2);
        $parser->setField("Dimmer", "Animation", "StartBrightness", $arg3);
        $parser->setField("Dimmer", "Animation", "EndBrightness",   $arg4);
        SHCdev_Send($hash);
      } elsif ($cmd eq 'statusRequest') {
        $parser->initPacket("Dimmer", "Brightness", "Get");
        SHCdev_Send($hash);
      } else {
        return SetExtensions($hash, "", $name, @aa);
      }
    }
  }

  return undef;
}

#####################################
sub SHCdev_Get($@)
{
  my ($hash, $name, @aa) = @_;
  my $cnt = @aa;

  my $cmd = $aa[0];
  my $arg = $aa[1];

  return "\"get $name\" needs at least one parameter" if ($cnt < 1);

  my $devtype = AttrVal( $name, "devtype", undef );
  if (!defined($devtype)) {
    return "\"devtype\" not yet specifed. Currently supported device types are " . join(", ", sort keys %sets);
  }

  if (!defined($gets{$devtype})) {
    return "No get commands for " . $devtype . " device type supported ";
  }

  given ($devtype) {
    when ('EnvSensor') {
      if ($cmd eq 'input') {
        if ($arg =~ /[1-8]/) {
          my $channel = "pin" . $arg;
          if ( defined($hash->{READINGS}{$channel})
            && defined($hash->{READINGS}{$channel}{VAL}))
          {
            return "$name.$channel => " . $hash->{READINGS}{$channel}{VAL};
          }
          return "Error: \"input " . $channel . "\" readings not yet available or not supported by device";
        }
        elsif ($arg eq "all")
        {
          if ( defined($hash->{READINGS}{pins})
            && defined($hash->{READINGS}{pins}{VAL}))
          {
            return "$name.pins => " . $hash->{READINGS}{pins}{VAL};
          }
          return "Error: \"input all\" readings not yet available or not supported by device";
        }
      }

      # This return is required to provide the get commands in the web interface
      return "Unknown argument $cmd, choose one of " . $gets{$devtype};
    }
  }
  return undef;
}

#####################################
sub SHCdev_Send($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{SHCdev_lastSend} = TimeNow();

  my $msg = $parser->getSendString($hash->{addr}, $hash->{aeskey});

  Log3 $name, 3, "$name: Sending $msg";

  IOWrite($hash, $msg);
}

1;

=pod
=begin html

<a name="SHCdev"></a>
<h3>SHCdev</h3>
<ul>
  SHC is the device module that supports several device types available 
  at <a href="http://http://www.smarthomatic.org">www.smarthomatic.org</a>.<br><br>

  These device are connected to the FHEM server through the SHC base station (<a href="#SHC">SHC</a>).<br><br>
  Currently supported are:<br>
  <ul>
    <li>EnvSensor</li>
    <li>PowerSwitch</li>
    <li>Dimmer</li>
  </ul><br>

  <a name="SHCdev_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SHCdev &lt;SenderID&gt; [&lt;AesKey&gt;]</code><br>
    <br>
    &lt;SenderID&gt;<br>
    is a number ranging from 0 .. 4095 to identify the SHCdev device.<br><br>

    &lt;AesKey&gt;<br>
    is a optional number ranging from 0 .. 15 to select an encryption key.
    It is required for the basestation to communicate with remote devides
    The default value is 0.<br><br>

    Note: devices are autocreated on reception of the first message.<br>
  </ul>
  <br>

  <a name="SHCdev_Set"></a>
  <b>Set</b>
  <ul>
    <li>on<br>
        Supported by Dimmer and PowerSwitch.
    </li><br>
    <li>off<br>
        Supported by Dimmer, PowerSwitch.
    </li><br>
    <li>pct &lt;0..100&gt;<br>
        Sets the brightness in percent. Supported by Dimmer.
    </li><br>
    <li>ani &lt;AnimationMode&gt; &lt;TimeoutSec&gt; &lt;StartBrightness&gt; &lt;EndBrightness&gt;<br>
        Description and details available at <a href="http://www.smarthomatic.org/basics/message_catalog.html#Dimmer_Animation">www.smarthomatic.org</a>
        Supported by Dimmer.
    </li><br>
    <li>statusRequest<br>
        Supported by Dimmer and PowerSwitch.
    </li><br>
    <li><a href="#setExtensions"> set extensions</a><br>
        Supported by Dimmer and PowerSwitch.</li>
  </ul><br>

  <a name="SHCdev_Get"></a>
  <b>Get</b>
  <ul>
    <li>input &lt;pin&gt;<br>
        Returns the state of the specified pin for pin = 1..8 or the state of all pins for pin = all.
        Supported by EnvSensor.
    </li><br>
  </ul><br>

  <a name="SHCdev_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>devtype<br>
      The device type determines the command set, default web commands and the
      default devStateicon. Currently supported are: EnvSensor, Dimmer, PowerSwitch.<br><br>

      Note: If the device is not set manually, it will be determined automatically
      on reception of a device type specific message. For example: If a
      temperature message is received, the device type will be set to EnvSensor.
    </li><br>
    <li>readonly<br>
        if set to a value != 0 all switching commands (on, off, toggle, ...) will be disabled.
    </li><br>
    <li>forceOn<br>
        try to switch on the device whenever an off status is received.
    </li><br>
  </ul><br>
</ul>

=end html
=cut

##############################################
#
# fhem bridge to MySensors (see http://mysensors.org)
#
# Copyright (C) 2014 Norbert Truchsess
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
##############################################

use strict;
use warnings;

my %gets = (
  "version"   => "",
);

sub MYSENSORS_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MYSENSORS::DEVICE::Define";
  $hash->{UndefFn}  = "MYSENSORS::DEVICE::UnDefine";
  $hash->{SetFn}    = "MYSENSORS::DEVICE::Set";
  $hash->{AttrFn}   = "MYSENSORS::DEVICE::Attr";
  
  $hash->{AttrList} =
    "config:M,I ".
    "setCommands ".
    "setReading_.+_\\d+ ".
    "mapReadingType_.+ ".
    "requestAck:1 ". 
    "IODev ".
    $main::readingFnAttributes;

  main::LoadModule("MYSENSORS");
}

package MYSENSORS::DEVICE;

use strict;
use warnings;
use GPUtils qw(:all);

use Device::MySensors::Constants qw(:all);
use Device::MySensors::Message qw(:all);

BEGIN {
  MYSENSORS->import(qw(:all));

  GP_Import(qw(
    AttrVal
    readingsSingleUpdate
    CommandDeleteReading
    AssignIoPort
    Log3
  ))
};

my %static_mappings = (
  V_TEMP        => { type => "temperature" },
  V_HUM         => { type => "humidity" },
  V_PRESSURE    => { type => "pressure" },
  V_LIGHT_LEVEL => { type => "brightness" },
  V_LIGHT       => { type => "switch", val => { 0 => 'off', 1 => 'on' }},
);

sub Define($$) {
  my ( $hash, $def ) = @_;
  my ($name, $type, $radioId) = split("[ \t]+", $def);
  return "requires 1 parameters" unless (defined $radioId and $radioId ne "");
  $hash->{radioId} = $radioId;
  $hash->{sets} = {
    'time' => "",
    clear  => "",
    reboot => "",
  };
  $hash->{ack} = 0;
  $hash->{typeMappings} = {map {variableTypeToIdx($_) => $static_mappings{$_}} keys %static_mappings};
  $hash->{readingMappings} = {};
  AssignIoPort($hash);
};

sub UnDefine($) {
  my ($hash) = @_;
  
  return undef;
}

sub Set($@) {
  my ($hash,$name,$command,@values) = @_;
  return "Need at least one parameters" unless defined $command;
  return "Unknown argument $command, choose one of " . join(" ", map {$hash->{sets}->{$_} ne "" ? "$_:$hash->{sets}->{$_}" : $_} sort keys %{$hash->{sets}})
    if(!defined($hash->{sets}->{$command}));
  COMMAND_HANDLER: {
    $command eq "clear" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_CHILDREN, payload => "C");
      last;
    };
    $command eq "time" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_TIME, payload => time);
      last;
    };
    $command eq "reboot" and do {
      sendClientMessage($hash, childId => 255, cmd => C_INTERNAL, subType => I_REBOOT);
      last;
    };
    $command =~ /^(.+_\d+)$/ and do {
      my $value = @values ? join " ",@values : "";
      my ($type,$childId,$mappedValue) = readingToType($hash,$1,$value);
      sendClientMessage($hash, childId => $childId, cmd => C_SET, subType => $type, payload => $mappedValue);
      readingsSingleUpdate($hash,$command,$value,1) unless ($hash->{ack} or $hash->{IODev}->{ack});
      last;
    };
    (defined ($hash->{setcommands}->{$command})) and do {
      my $setcommand = $hash->{setcommands}->{$command};
      my ($type,$childId,$mappedValue) = readingToType($hash,$setcommand->{var},$setcommand->{val});
      sendClientMessage($hash,
        childId => $childId,
        cmd => C_SET,
        subType => $type,
        payload => $mappedValue,
      );
      readingsSingleUpdate($hash,$setcommand->{var},$setcommand->{val},1) unless ($hash->{ack} or $hash->{IODev}->{ack});
      last;
    };
    return "$command not defined by attr setCommands";
  }
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute eq "config" and do {
      if ($main::init_done) {
        sendClientMessage($hash, cmd => C_INTERNAL, subType => I_CONFIG, payload => $command eq 'set' ? $value : "M");
      }
      last;
    };
    $attribute eq "setCommands" and do {
      if ($command eq "set") {
        foreach my $setCmd (split ("[, \t]+",$value)) {
          $setCmd =~ /^(.+):(.+_\d+):(.+)$/;
          $hash->{sets}->{$1}="";
          $hash->{setcommands}->{$1} = {
            var => $2,
            val => $3,
          };
        }
      } else {
        foreach my $set (keys %{$hash->{setcommands}}) {
          delete $hash->{sets}->{$set};
        }
        $hash->{setcommands} = {};
      }
      last;
    };
    $attribute =~ /^setReading_(.+_\d+)$/ and do {
      if ($command eq "set") {
        $hash->{sets}->{$1}=join(",",split ("[, \t]+",$value));
      } else {
        CommandDeleteReading(undef,"$hash->{NAME} $1");
        delete $hash->{sets}->{$1};
      }
      last;
    };
    $attribute =~ /^mapReadingType_(.+)/ and do {
      my $type = variableTypeToIdx("V_$1");
      if ($command eq "set") {
        my @values = split ("[, \t]",$value);
        $hash->{typeMappings}->{$type}={
          type => shift @values,
          val => {map {$_ =~ /^(.+):(.+)$/; $1 => $2} @values},
        }
      } else {
        if ($static_mappings{"V_$1"}) {
          $hash->{typeMappings}->{$type}=$static_mappings{"V_$1"};
        } else {
          delete $hash->{typeMappings}->{$type};
        }
        CommandDeleteReading(undef,"$hash->{NAME} $1"); #TODO do propper remap of existing readings
      }
      last;
    };
    $attribute eq "requestAck" and do {
      if ($command eq "set") {
        $hash->{ack} = 1;
      } else {
        $hash->{ack} = 0;
      }
      last;
    };
  }
}

sub onGatewayStarted($) {
  my ($hash) = @_;
}

sub onPresentationMessage($$) {
  my ($hash,$msg) = @_;
}

sub onSetMessage($$) {
  my ($hash,$msg) = @_;
  if (defined $msg->{payload}) {
    my ($reading,$value) = mapReading($hash,$msg->{subType},$msg->{childId},$msg->{payload});
    readingsSingleUpdate($hash,$reading,$value,1);
  } else {
    Log3 ($hash->{NAME},5,"MYSENSORS_DEVICE $hash->{NAME}: ignoring C_SET-message without payload");
  }
}

sub onRequestMessage($$) {
  my ($hash,$msg) = @_;
  variableTypeToStr($msg->{subType}) =~ /^V_(.+)$/;
  sendClientMessage($hash,
    childId => $msg->{childId},
    cmd => C_SET,
    subType => $msg->{subType},
    payload => ReadingsVal($hash->{NAME},"$1\_$msg->{childId}","")
  );
}

sub onInternalMessage($$) {
  my ($hash,$msg) = @_;
  my $name = $hash->{NAME};
  my $type = $msg->{subType};
  my $typeStr = internalMessageTypeToStr($type);
  INTERNALMESSAGE: {
    $type == I_BATTERY_LEVEL and do {
      readingsSingleUpdate($hash,"batterylevel",$msg->{payload},1);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: batterylevel $msg->{payload}");
      last;
    };
    $type == I_TIME and do {
      sendClientMessage($hash,cmd => C_INTERNAL, subType => I_TIME, payload => time);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: update of time requested");
      last;
    };
    $type == I_VERSION and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_ID_REQUEST and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_ID_RESPONSE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_INCLUSION_MODE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_CONFIG and do {
      sendClientMessage($hash,cmd => C_INTERNAL, subType => I_CONFIG, payload => AttrVal($name,"config","M"));
      Log3 ($name,4,"MYSENSORS_DEVICE $name: respond to config-request");
      last;
    };
    $type == I_PING and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_PING_ACK and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_LOG_MESSAGE and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_CHILDREN and do {
      readingsSingleUpdate($hash,"state","routingtable cleared",1);
      Log3 ($name,4,"MYSENSORS_DEVICE $name: routingtable cleared");
      last;
    };
    $type == I_SKETCH_NAME and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_SKETCH_VERSION and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
    $type == I_REBOOT and do {
      $hash->{$typeStr} = $msg->{payload};
      last;
    };
  }
}

sub sendClientMessage($%) {
  my ($hash,%msg) = @_;
  $msg{radioId} = $hash->{radioId};
  $msg{ack} = 1 if $hash->{ack};
  sendMessage($hash->{IODev},%msg);
}

sub mapReading($$) {
  my($hash, $type, $childId, $value) = @_;

  if(defined (my $mapping = $hash->{typeMappings}->{$type})) {
    return ("$mapping->{type}_$childId",defined $mapping->{val}->{$value} ? $mapping->{val}->{$value} : $value);
  } else {
    return (variableTypeToStr($type)."_$childId",$value);
  }
}

sub readingToType($$$) {
  my ($hash,$reading,$value) = @_;
  $reading =~ /^(.+)_(\d+)$/;
  if (my @types = grep {$hash->{typeMappings}->{$_}->{type} eq $1} keys %{$hash->{typeMappings}}) {
    my $type = shift @types;
    my $valueMappings = $hash->{typeMappings}->{$type}->{val};
    if (my @mappedValues = grep {$valueMappings->{$_} eq $value} keys %$valueMappings) {
      return ($type,$2,shift @mappedValues);
    }
    return ($type,$2,$value);
  }
  return (variableTypeToIdx("V_$1"),$2,$value);
}

1;

=pod
=begin html

<a name="MYSENSORS_DEVICE"></a>
<h3>MYSENSORS_DEVICE</h3>
<ul>
  <p>represents a mysensors sensor attached to a mysensor-node</p>
  <p>requires a <a href="#MYSENSOR">MYSENSOR</a>-device as IODev</p>
  <a name="MYSENSORS_DEVICEdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MYSENSORS_DEVICE &lt;Sensor-type&gt; &lt;node-id&gt;</code><br/>
      Specifies the MYSENSOR_DEVICE device.</p>
  </ul>
  <a name="MYSENSORS_DEVICEset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; clear</code><br/>
         clears routing-table of a repeater-node</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; time</code><br/>
         sets time for nodes (that support it)</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; reboot</code><br/>
         reboots a node (requires a bootloader that supports it).<br/>
         Attention: Nodes that run the standard arduino-bootloader will enter a bootloop!<br/>
         Dis- and reconnect the nodes power to restart in this case.</p>
    </li>
  </ul>
  <a name="MYSENSORS_DEVICEattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; config [&lt;M|I&gt;]</code><br/>
         configures metric (M) or inch (I). Defaults to 'M'</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; setCommands [&lt;command:reading:value&gt;]*</code><br/>
         configures one or more commands that can be executed by set.<br/>
         e.g.: <code>attr &lt;name&gt; setCommands on:switch_1:on off:switch_1:off</code></p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; setReading_&lt;reading&gt; [&lt;value&gt;]*</code><br/>
         configures a reading that can be modified by set-command<br/>
         e.g.: <code>attr &lt;name&gt; setReading_switch_1 on,off</code></p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; mapReadingType_&lt;reading&gt; &lt;new reading name&gt; [&lt;value&gt;:&lt;mappedvalue&gt;]*</code><br/>
         configures reading user names that should be used instead of technical names<br/>
         E.g.: <code>attr xxx mapReadingType_LIGHT switch 0:on 1:off</code></p>
    </li>
    <li>
      <p><code>att &lt;name&gt; requestAck</code><br/>
         request acknowledge from nodes.<br/>
         if set the Readings of nodes are updated not before requested acknowledge is received<br/>
         if not set the Readings of nodes are updated immediatly (not awaiting the acknowledge).<br/>
         May also be configured on the gateway for all nodes at once</p>
    </li>
  </ul>
</ul>

=end html
=cut

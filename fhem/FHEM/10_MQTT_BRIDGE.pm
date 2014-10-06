##############################################
#
# fhem bridge to mqtt (see http://mqtt.org)
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

my %sets = (
);

my %gets = (
  "version"   => "",
  "readings"  => ""
);

sub MQTT_BRIDGE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MQTT::Client_Define";
  $hash->{UndefFn}  = "MQTT::Client_Undefine";
  $hash->{GetFn}    = "MQTT::BRIDGE::Get";
  $hash->{NotifyFn} = "MQTT::BRIDGE::Notify";
  $hash->{AttrFn}   = "MQTT::BRIDGE::Attr";
  
  $hash->{AttrList} =
    "IODev ".
    "qos:".join(",",keys %MQTT::qos)." ".
    "publish-topic-base ".
    "publishState ".
    "publishReading_.* ".
    "subscribeSet ".
    "subscribeSet_.* ".
    $main::readingFnAttributes;

    main::LoadModule("MQTT");
}

package MQTT::BRIDGE;

use strict;
use warnings;
use GPUtils qw(:all);

use Net::MQTT::Constants;

BEGIN {
  MQTT->import(qw(:all));

  GP_Import(qw(
    AttrVal
    CommandAttr
    readingsSingleUpdate
    Log3
    DoSet
  ))
};

sub Get($$@) {
  my ($hash, $name, $command) = @_;
  return "Need at least one parameters" unless (defined $command);
  return "Unknown argument $command, choose one of " . join(" ", sort keys %gets)
    unless (defined($gets{$command}));

  COMMAND_HANDLER: {
    # populate dynamically from keys %{$defs{$sdev}{READINGS}}
    $command eq "readings" and do {
      my $base = AttrVal($name,"publish-topic-base","/$hash->{DEF}/");
      foreach my $reading (keys %{$main::defs{$hash->{DEF}}{READINGS}}) {
        unless (defined AttrVal($name,"publishReading_$reading",undef)) {
          CommandAttr($hash,"$name publishReading_$reading $base$reading");
        }
      };
      last;
    };
  };
}

sub Notify() {
  my ($hash,$dev) = @_;

  Log3($hash->{NAME},5,"Notify for $dev->{NAME}");
  foreach my $event (@{$dev->{CHANGED}}) {
    $event =~ /^([^:]+)(: )?(.*)$/;
    Log3($hash->{NAME},5,"$event, '".((defined $1) ? $1 : "-undef-")."', '".((defined $3) ? $3 : "-undef-")."'");
    if (defined $3 and $3 ne "") {
      if (defined $hash->{publishReadings}->{$1}) {
        send_publish($hash->{IODev}, topic => $hash->{publishReadings}->{$1}, message => $3, qos => $hash->{qos});
        readingsSingleUpdate($hash,"transmission-state","publish sent",1);
      }
    } else {
      if (defined $hash->{publishState}) {
        send_publish($hash->{IODev}, topic => $hash->{publishState}, message => $1, qos => $hash->{qos});
        readingsSingleUpdate($hash,"transmission-state","publish sent",1);
      }
    }
  }
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute =~ /^subscribeSet(_?)(.*)/ and do {
      if ($command eq "set") {
        $hash->{subscribeSets}->{$value} = $2;
        push @{$hash->{subscribe}},$value unless grep {$_ eq $value} @{$hash->{subscribe}};
        if ($main::init_done) {
          if (my $mqtt = $hash->{IODev}) {;
            my $msgid = send_subscribe($mqtt,
              topics => [[$value => $hash->{qos} || MQTT_QOS_AT_MOST_ONCE]],
            );
            $hash->{message_ids}->{$msgid}++;
            readingsSingleUpdate($hash,"transmission-state","subscribe sent",1)
          }
        }
      } else {
        foreach my $topic (keys %{$hash->{subscribeSets}}) {
          if ($hash->{subscribeSets}->{topic} eq $2) {
            delete $hash->{subscribeSets}->{$topic};
            $hash->{subscribe} = [grep { $_ != $topic } @{$hash->{subscribe}}];
            if ($main::init_done) {
              if (my $mqtt = $hash->{IODev}) {;
                my $msgid = send_unsubscribe($mqtt,
                  topics => [$topic],
                );
                $hash->{message_ids}->{$msgid}++;
              }
            }
            last;
          }
        }
      }
      last;
    };
    $attribute eq "publishState" and do {
      if ($command eq "set") {
        $hash->{publishState} = $value;
      } else {
        delete $hash->{publishState};
      }
      last;
    };
    $attribute =~ /^publishReading_(.+)$/ and do {
      if ($command eq "set") {
        $hash->{publishReadings}->{$1} = $value;
      } else {
        delete $hash->{publishReadings}->{$1};
      }
      last;
    };
    client_attr($hash,$command,$name,$attribute,$value);
  }
}

sub onmessage($$$) {
  my ($hash,$topic,$message) = @_;
  if (defined (my $command = $hash->{subscribeSets}->{$topic})) {
    my @args = split ("[ \t]+",$message);
    if ($command eq "") {
      Log3($hash->{NAME},5,"calling DoSet($hash->{DEF}".(@args ? ",".join(",",@args) : ""));
      DoSet($hash->{DEF},@args);
    } else {
      Log3($hash->{NAME},5,"calling DoSet($hash->{DEF},$command".(@args ? ",".join(",",@args) : ""));
      DoSet($hash->{DEF},$command,@args);
    }
  }
}
1;

=pod
=begin html

<a name="MQTT_BRIDGE"></a>
<h3>MQTT_BRIDGE</h3>
<ul>
  acts as a bridge in between an fhem-device and <a href="http://mqtt.org">mqtt</a>-topics.
  <br><br>
  requires a <a href="#MQTT">MQTT</a>-device as IODev<br><br>
  
  Note: this module is based on module <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a>.
  <br><br>
  
  <a name="MQTT_BRIDGEdefine"></a>
  <b>Define</b><br>
  <ul><br>
    <code>define &lt;name&gt; MQTT_BRIDGE &lt;fhem-device-name&gt;</code> <br>
    Specifies the MQTT device.<br>
    &lt;fhem-device-name&gt; is the fhem-device this MQTT_BRIDGE is linked to.<br>
    <br>
    <a name="MQTT_BRIDGEget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>get &lt;name&gt; readings</code><br>
        retrieves all existing readings from fhem-device and configures (default-)topics for them.<br>
        attribute 'publish-topic-base' is prepended if set.
      </li><br>
    </ul>
    <br><br>

    <a name="MQTT_BRIDGEattr"></a>
    <b>Attributes</b><br>
    <ul>
      <li>
        <code>attr &lt;name&gt; subscribeSet &lt;topic&gt;</code><br>
        configures a topic that will issue a 'set &lt;message&gt; whenever a message is received<br>
      </li>
      <li>
        <code>attr &lt;name&gt; subscribeSet_&lt;reading&gt; &lt;topic&gt;</code><br>
        configures a topic that will issue a 'set &lt;reading&gt; &lt;message&gt; whenever a message is received<br>
      </li>
      <li>
        <code>attr &lt;name&gt; publishState &lt;topic&gt;</code><br>
        configures a topic such that a message is sent to topic whenever the device state changes.<br>
      </li>
      <li>
        <code>attr &lt;name&gt; publishReading_&lt;reading&gt; &lt;topic&gt;</code><br>
        configures a topic such that a message is sent to topic whenever the device readings value changes.<br>
      </li>
      <li>
        <code>attr &lt;name&gt; publish-topic-base &lt;topic&gt;</code><br>
        this is used as base path when issueing 'get &lt;device&gt; readings' to construct topics to publish to based on the devices existing readings<br>
      </li>
    </ul>
  </ul>
</ul>
<br>

=end html
=cut

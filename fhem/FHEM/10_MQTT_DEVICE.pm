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
use GPUtils qw(:all);

use Net::MQTT::Constants;
use Net::MQTT::Message;

my %sets = (
);

my %gets = (
  "version"   => "",
);

my %qos = map {qos_string($_) => $_} (MQTT_QOS_AT_MOST_ONCE,MQTT_QOS_AT_LEAST_ONCE,MQTT_QOS_EXACTLY_ONCE);

sub MQTT_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MQTT_client_define";
  $hash->{UndefFn}  = "MQTT_client_undefine";
  $hash->{SetFn}    = "MQTT_DEVICE_Set";
  $hash->{AttrFn}   = "MQTT_DEVICE_Attr";
  
  $hash->{AttrList} =
    "IODev ".
    "qos:".join(",",keys %qos)." ".
    "publishSet ".
    "publishSet_.* ".
    "subscribeReading_.* ".
    $main::readingFnAttributes;
}

sub MQTT_DEVICE_Set($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", map {$sets{$_} eq "" ? $_ : "$_:$sets{$_}"} sort keys %sets)
    if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];
  if (defined $value) {
    MQTT_send_publish($hash->{IODev}, topic => $hash->{publishSets}->{$command}->{topic}, message => $value, qos => $hash->{qos});
    readingsSingleUpdate($hash,$command,$value,1);
  } else {
    MQTT_send_publish($hash->{IODev}, topic => $hash->{publishSets}->{""}->{topic}, message => $command, qos => $hash->{qos});
    readingsSingleUpdate($hash,"state",$command,1);
  }
  return undef;
}

sub MQTT_DEVICE_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute =~ /^subscribeReading_(.+)/ and do {
      if ($command eq "set") {
        $hash->{subscribeReadings}->{$value} = $1;
        push @{$hash->{subscribe}},$value unless grep {$_ eq $value} @{$hash->{subscribe}};
        if ($main::init_done) {
          if (my $mqtt = $hash->{IODev}) {;
            my $msgid = MQTT_send_subscribe($mqtt,
              topics => [[$value => $hash->{qos} || MQTT_QOS_AT_MOST_ONCE]],
            );
            $hash->{message_ids}->{$msgid}++;
            readingsSingleUpdate($hash,"transmission-state","subscribe sent",1)
          }
        }
      } else {
        foreach my $topic (keys %{$hash->{subscribeReadings}}) {
          if ($hash->{subscribeReadings}->{$topic} eq $1) {
            $hash->{subscribe} = [grep { $_ != $topic } @{$hash->{subscribe}}];
            delete $hash->{subscribeReadings}->{$topic};
            if ($main::init_done) {
              if (my $mqtt = $hash->{IODev}) {;
                my $msgid = MQTT_send_unsubscribe($mqtt,
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
    $attribute =~ /^publishSet(_?)(.*)/ and do {
      if ($command eq "set") {
        my @values = split ("[ \t]+",$value);
        my $topic = pop @values;
        $hash->{publishSets}->{$2} = {
          'values' => \@values,
          topic    => $topic,
        };
        if ($2 eq "") {
          foreach my $set (@values) {
            $sets{$set}="";
          }
        } else {
          $sets{$2}=join(",",@values);
        }
      } else {
        if ($2 eq "") {
          foreach my $set (@{$hash->{publishSets}->{$2}->{'values'}}) {
            delete $sets{$set};
          }
        } else {
          delete $sets{$2};
        }
        delete $hash->{publishSets}->{$2};
      }
      last;
    };
    $attribute eq "qos" and do {
      if ($command eq "set") {
        $hash->{qos} = $qos{$value};
      } else {
        $hash->{qos} = MQTT_QOS_AT_MOST_ONCE;
      }
      last;
    };
    $attribute eq "IODev" and do {
      if ($command eq "set") {
      } else {
      }
      last;
    };
  }
}

sub MQTT_DEVICE_onmessage($$$) {
  my ($hash,$topic,$message) = @_;
  if (defined (my $reading = $hash->{subscribeReadings}->{$topic})) {
    main::Log3($hash->{NAME},5,"calling readingsSingleUpdate($hash->{NAME},$reading,$message,1");
    main::readingsSingleUpdate($hash,$reading,$message,1);
  }
}

1;

=pod
=begin html

<a name="MQTT_DEVICE"></a>
<h3>MQTT</h3>
<ul>
  acts as a fhem-device that is mapped to <a href="http://mqtt.org">mqtt</a>-topics.
  <br><br>
  requires a <a href="#MQTT">MQTT</a>-device as IODev<br><br>
  
  Note: this module is based on module <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod>Net::MQTT</a>.
  <br><br>
  
  <a name="MQTT_DEVICEdefine"></a>
  <b>Define</b><br>
  <ul><br>
    <code>define &lt;name&gt; MQTT_DEVICE</code> <br>
    Specifies the MQTT device.<br>
    <br>
    <a name="MQTT_DEVICEset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>set &lt;name&gt; &lt;command&gt;/code><br>
        sets reading 'state' and publishes the command to topic configured via attr publishSet
      </li><br>
      <li>
        <code>set &lt;name&gt; &lth;reading&gt; &lt;value&gt;/code><br>
        sets reading &lth;reading&gt; and publishes the command to topic configured via attr publishSet_&lth;reading&gt;
      </li><br>
    </ul>
    <br><br>

    <a name="MQTT_DEVICEattr"></a>
    <b>Attributes</b><br>
    <ul>
      <li>
        <code>attr &lt;name&gt; publishSet [&lt;commands&gt] &lt;topic&gt;/code><br>
        configures set commands that may be used to both set reading 'state' and publish to configured topic<br>
      </li>
      <li>
        <code>attr &lt;name&gt; publishSet_&lt;reading&gt; [&lt;values&gt] &lt;topic&gt;/code><br>
        configures reading that may be used to both set 'reading' (to optionally configured values) and publish to configured topic<br>
      </li>
    </ul>
  </ul>
</ul>
<br>

=end html
=cut

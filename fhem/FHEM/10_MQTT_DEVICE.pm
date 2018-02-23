##############################################
#
# fhem bridge to mqtt (see http://mqtt.org)
#
# Copyright (C) 2017 Stephan Eisler
# Copyright (C) 2014 - 2016 Norbert Truchsess
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

sub MQTT_DEVICE_Initialize($) {

  my $hash = shift @_;

  # Consumer
  $hash->{DefFn}    = "MQTT::DEVICE::Define";
  $hash->{UndefFn}  = "MQTT::Client_Undefine";
  $hash->{SetFn}    = "MQTT::DEVICE::Set";
  $hash->{AttrFn}   = "MQTT::DEVICE::Attr";
  
  #$hash->{OnMessageFn} = "MQTT::DEVICE::onmessage";
  
  $hash->{AttrList} =
    "IODev ".
    #"qos:".join(",",keys %MQTT::qos)." ".
    "qos ".
    "retain ".
    "publishSet ".
    "publishSet_.* ".
    "subscribeReading_.* ".
    "autoSubscribeReadings ".
    "useSetExtensions:1,0 ".
    $main::readingFnAttributes;
    
    main::LoadModule("MQTT");
}

package MQTT::DEVICE;

use strict;
use warnings;
use GPUtils qw(:all);

use Net::MQTT::Constants;
use SetExtensions qw/ :all /;

BEGIN {
  MQTT->import(qw(:all));

  GP_Import(qw(
    CommandDeleteReading
    CommandAttr
    readingsSingleUpdate
    Log3
    SetExtensions
    SetExtensionsCancel
    fhem
    defs
    AttrVal
    ReadingsVal
  ))
};

sub Define() {
  my ( $hash, $def ) = @_;
  $hash->{sets} = {};
  return MQTT::Client_Define($hash,$def);
};

sub Set($$$@) {
  my ($hash,$name,$command,@values) = @_;
  return "Need at least one parameters" unless defined $command;
  my $msgid;
  my $mark=0;

  if (AttrVal($name,"useSetExtensions",undef)) {
    if ($command =~ m/^(blink|intervals|(off-|on-)(for-timer|till(-overnight)?))(.+)?|toggle$/) {
      Log3($hash->{NAME},5,"calling SetExtensions(...) for $command");
      return SetExtensions($hash, join(" ", map {$hash->{sets}->{$_} eq "" ? $_ : "$_:".$hash->{sets}->{$_}} sort keys %{$hash->{sets}}), $name, $command, @values);
    }
  }

  if($command ne '?') {
    if(defined($hash->{publishSets}->{$command})) {
      my $value = join " ",@values;
      my $retain = $hash->{".retain"}->{$command};
      $retain = $hash->{".retain"}->{'*'} unless defined($retain);
      my $qos = $hash->{".qos"}->{$command};
      $qos = $hash->{".qos"}->{'*'} unless defined($qos);
      #Log3($hash->{NAME},1,">>>>>>>>>>>>>>>>>> RETAIN: ".$retain); $retain=0; ### TEST
      $msgid = send_publish($hash->{IODev}, topic => $hash->{publishSets}->{$command}->{topic}, message => $value, qos => $qos, retain => $retain);
      readingsSingleUpdate($hash,$command,$value,1);
      $mark=1;
    } elsif(defined($hash->{publishSets}->{""})) {
      my $value = join (" ", ($command, @values));
      my $retain = $hash->{".retain"}->{""};
      $retain = $hash->{".retain"}->{'*'} unless defined($retain);
      my $qos = $hash->{".qos"}->{""};
      $qos = $hash->{".qos"}->{'*'} unless defined($qos);
      #Log3($hash->{NAME},1,">>>>>>>>>>>>>>>>>> RETAIN: ".$retain); $retain=0; ### TEST
      $msgid = send_publish($hash->{IODev}, topic => $hash->{publishSets}->{""}->{topic}, message => $value, qos => $qos, retain => $retain);
      readingsSingleUpdate($hash,"state",$command,1);
      $mark=1;
    }
  }
  if(!$mark) {
    if(AttrVal($name,"useSetExtensions",undef)) {
      return SetExtensions($hash, join(" ", map {$hash->{sets}->{$_} eq "" ? $_ : "$_:".$hash->{sets}->{$_}} sort keys %{$hash->{sets}}), $name, $command, @values);
    } else {
      return "Unknown argument $command, choose one of " . join(" ", map {$hash->{sets}->{$_} eq "" ? $_ : "$_:".$hash->{sets}->{$_}} sort keys %{$hash->{sets}})
    }
  }
  SetExtensionsCancel($hash);
  $hash->{message_ids}->{$msgid}++ if defined $msgid;
  readingsSingleUpdate($hash,"transmission-state","outgoing publish sent",1);
  return undef;
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute =~ /^subscribeReading_(.+)/ and do {
      if ($command eq "set") {
        my ($mqos, $mretain,$mtopic, $mvalue, $mcmd)=MQTT::parsePublishCmdStr($value);
        if(!defined($mtopic)) {return "topic may not be empty";}
        unless (defined $hash->{subscribeReadings}->{$mtopic}->{name} and $hash->{subscribeReadings}->{$mtopic}->{name} eq $1) {
          unless (defined $hash->{subscribeReadings}->{$mtopic}->{name}) {
            client_subscribe_topic($hash,$mtopic,$mqos,$mretain);
          }
          $hash->{subscribeReadings}->{$mtopic}->{name} = $1;
          $hash->{subscribeReadings}->{$mtopic}->{cmd} = $mcmd;
        }
      } else {
        foreach my $topic (keys %{$hash->{subscribeReadings}}) {
          if ($hash->{subscribeReadings}->{$topic}->{name} eq $1) {
            client_unsubscribe_topic($hash,$topic);
            delete $hash->{subscribeReadings}->{$topic};
            CommandDeleteReading(undef,"$hash->{NAME} $1");
            last;
          }
        }
      }
      last;
    };
    $attribute eq "autoSubscribeReadings" and do {
      if ($command eq "set") {
        unless (defined $hash->{'.autoSubscribeTopic'} and $hash->{'.autoSubscribeTopic'} eq $value) {
          if (defined $hash->{'.autoSubscribeTopic'}) {
            client_unsubscribe_topic($hash,$hash->{'.autoSubscribeTopic'});
          }
          $hash->{'.autoSubscribeTopic'} = $value;
          $hash->{'.autoSubscribeExpr'} = topic_to_regexp($value);
          client_subscribe_topic($hash,$value);
        }
      } else {
        if (defined $hash->{'.autoSubscribeTopic'}) {
          client_unsubscribe_topic($hash,$hash->{'.autoSubscribeTopic'});
          delete $hash->{'.autoSubscribeTopic'};
          delete $hash->{'.autoSubscribeExpr'};
        }
      }
      last;
    };
    $attribute =~ /^publishSet(_?)(.*)/ and do {
      if ($command eq "set") {
        my ( $aa, $bb ) = parseParams($value);
        my @values = @{$aa};
        my $topic = pop @values;
        $hash->{publishSets}->{$2} = {
          'values' => \@values,
          topic    => $topic,
        };
        if ($2 eq "") {
          if(@values) {
            foreach my $set (@values) {
              $hash->{sets}->{$set}="";
              my($setname,@restvalues) = split(":",$set);
              if(@restvalues) {
                $hash->{publishSets}->{$setname} = {
                  'values' => \@restvalues,
                  topic    => $topic,
                };
              }
            }
          } else {
            $hash->{sets}->{""}="";
          }
        } else {
          $hash->{sets}->{$2}=join(",",@values);
        }
      } else {
        if ($2 eq "") {
          foreach my $set (@{$hash->{publishSets}->{$2}->{'values'}}) {
            delete $hash->{sets}->{$set};
          }
        } else {
          CommandDeleteReading(undef,"$hash->{NAME} $2");
          delete $hash->{sets}->{$2};
        }
        delete $hash->{publishSets}->{$2};
      }
      last;
    };
    return client_attr($hash,$command,$name,$attribute,$value);
  }
}

sub onmessage($$$) {
  my ($hash,$topic,$message) = @_;
  if (defined (my $reading = $hash->{subscribeReadings}->{$topic}->{name})) {
    my $do=1;
    if(defined (my $cmd = $hash->{subscribeReadings}->{$topic}->{cmd})) {
      Log3($hash->{NAME},5,"evaluating cmd: $cmd");
      my $name = $hash->{NAME};
      $do=eval($cmd);
      Log3($hash->{NAME},1,"ERROR evaluating $cmd: $@") if($@);
      $do=1 if (!defined($do));
    }
    if($do) {
      Log3($hash->{NAME},5,"calling readingsSingleUpdate($hash->{NAME},$reading,$message,1)");
      readingsSingleUpdate($hash,$reading,$message,1);
    }
  } elsif ($topic =~ $hash->{'.autoSubscribeExpr'}) {
    Log3($hash->{NAME},5,"calling readingsSingleUpdate($hash->{NAME},$1,$message,1)");
    CommandAttr(undef,"$hash->{NAME} subscribeReading_$1 $topic");
    readingsSingleUpdate($hash,$1,$message,1);
  }
}

1;

=pod
=item [device]
=item summary MQTT_DEVICE acts as a fhem-device that is mapped to mqtt-topics
=begin html

<a name="MQTT_DEVICE"></a>
<h3>MQTT_DEVICE</h3>
<ul>
  <p>acts as a fhem-device that is mapped to <a href="http://mqtt.org/">mqtt</a>-topics.</p>
  <p>requires a <a href="#MQTT">MQTT</a>-device as IODev<br/>
     Note: this module is based on <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a> which needs to be installed from CPAN first.</p>
  <a name="MQTT_DEVICEdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MQTT_DEVICE</code><br/>
       Specifies the MQTT device.</p>
  </ul>
  <a name="MQTT_DEVICEset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; &lt;command&gt;</code><br/>
         sets reading 'state' and publishes the command to topic configured via attr publishSet</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code><br/>
         sets reading &lt;reading&gt; and publishes the command to topic configured via attr publishSet_&lt;reading&gt;</p>
    </li>
    <li>
      <p>The <a href="#setExtensions">set extensions</a> are supported with useSetExtensions attribute.<br/>
      Set eventMap if your publishSet commands are not on/off.</p>
      <p>example for true/false:<br/>
      <code>attr mqttest eventMap { dev=>{ 'true'=>'on', 'false'=>'off' }, usr=>{ '^on$'=>'true', '^off$'=>'false' }, fw=>{ '^on$'=>'on', '^off$'=>'off' } }</code></p>
    </li>
  </ul>
  <a name="MQTT_DEVICEattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p><code>attr &lt;name&gt; publishSet [[&lt;reading&gt;:]&lt;commands_or_options&gt;] &lt;topic&gt;</code><br/>
         configures set commands and UI-options e.g. 'slider' that may be used to both set given reading ('state' if not defined) and publish to configured topic</p>
      <p>example:<br/>
      <code>attr mqttest publishSet on off switch:on,off level:slider,0,1,100 /topic/123</code>
      </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; publishSet_&lt;reading&gt; [&lt;values&gt;]* &lt;topic&gt;</code><br/>
         configures reading that may be used to both set 'reading' (to optionally configured values) and publish to configured topic</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; autoSubscribeReadings &lt;topic&gt;</code><br/>
         specify a mqtt-topic pattern with wildcard (e.c. 'myhouse/kitchen/+') and MQTT_DEVICE automagically creates readings based on the wildcard-match<br/>
         e.g a message received with topic 'myhouse/kitchen/temperature' would create and update a reading 'temperature'</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; subscribeReading_&lt;reading&gt; [{Perl-expression}] [qos:?] [retain:?] &lt;topic&gt;</code><br/>
         mapps a reading to a specific topic. The reading is updated whenever a message to the configured topic arrives.<br/>
         QOS and ratain can be optionally defined for this topic. <br/>
         Furthermore, a Perl statement can be provided which is executed when the message is received. The following variables are available for the expression: $hash, $name, $topic, $message. Return value decides whether reading is set (true (e.g., 1) or undef) or discarded (false (e.g., 0)).
         </p>
      <p>Example:<br/>
         <code>attr mqttest subscribeReading_cmd {fhem("set something off")} /topic/cmd</code>
       </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; retain &lt;flags&gt; ...</code><br/>
         Specifies the retain flag for all or specific readings. Possible values are 0, 1</p>
      <p>Examples:<br/>
         <code>attr mqttest retain 0</code><br/>
         defines retain 0 for all readings/topics (due to downward compatibility)<br>
         <code> retain *:0 1 test:1</code><br/>
         defines retain 0 for all readings/topics except the reading 'test'. Retain for 'test' is 1<br>
       </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; qos &lt;flags&gt; ...</code><br/>
         Specifies the QOS flag for all or specific readings. Possible values are 0, 1 or 2. Constants may be also used: at-most-once = 0, at-least-once = 1, exactly-once = 2</p>
      <p>Examples:<br/>
         <code>attr mqttest qos 0</code><br/>
         defines QOS 0 for all readings/topics (due to downward compatibility)<br>
         <code> retain *:0 1 test:1</code><br/>
         defines QOS 0 for all readings/topics except the reading 'test'. Retain for 'test' is 1<br>
       </p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; useSetExtensions &lt;flags&gt;</code><br/>
         If set to 1, then the <a href="#setExtensions">set extensions</a> are supported.</p>
    </li>
  </ul>
</ul>

=end html
=cut

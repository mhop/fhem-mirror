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

my %sets = (
  "connect" => "",
  "disconnect" => "",
);

my %gets = (
  "version"   => ""
);

my @clients = qw(
  MQTT_DEVICE
  MQTT_BRIDGE
);

sub MQTT_Initialize($) {

  my $hash = shift @_;

  require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

  # Provider
  $hash->{Clients} = join (':',@clients);
  $hash->{ReadyFn} = "MQTT::Ready";
  $hash->{ReadFn}  = "MQTT::Read";

  # Consumer
  $hash->{DefFn}    = "MQTT::Define";
  $hash->{UndefFn}  = "MQTT::Undef";
  $hash->{SetFn}    = "MQTT::Set";
  $hash->{NotifyFn} = "MQTT::Notify";

  $hash->{AttrList} = "keep-alive";
}

package MQTT;

use Exporter ('import');
@EXPORT = ();
@EXPORT_OK = qw(send_publish send_subscribe send_unsubscribe client_attr client_subscribe_topic client_unsubscribe_topic topic_to_regexp);
%EXPORT_TAGS = (all => [@EXPORT_OK]);

use strict;
use warnings;

use GPUtils qw(:all);

use Net::MQTT::Constants;
use Net::MQTT::Message;

our %qos = map {qos_string($_) => $_} (MQTT_QOS_AT_MOST_ONCE,MQTT_QOS_AT_LEAST_ONCE,MQTT_QOS_EXACTLY_ONCE);

BEGIN {GP_Import(qw(
  gettimeofday
  readingsSingleUpdate
  DevIo_OpenDev
  DevIo_SimpleWrite
  DevIo_SimpleRead
  DevIo_CloseDev
  RemoveInternalTimer
  InternalTimer
  AttrVal
  Log3
  AssignIoPort
  ))};

sub Define($$) {
  my ( $hash, $def ) = @_;

  $hash->{NOTIFYDEV} = "global";
  $hash->{msgid} = 1;
  $hash->{timeout} = 60;
  $hash->{messages} = {};

  if ($main::init_done) {
    return Start($hash);
  } else {
    return undef;
  }
}

sub Undef($) {
  Stop(shift);
}

sub Set($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];

  COMMAND_HANDLER: {
    $command eq "connect" and do {
      Start($hash);
      last;
    };
    $command eq "disconnect" and do {
      Stop($hash);
      last;
    };
  };
}

sub Notify($$) {
  my ($hash,$dev) = @_;
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    Start($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

sub Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;

  my $hash = $main::defs{$name};
  ATTRIBUTE_HANDLER: {
    $attribute eq "keep-alive" and do {
      if ($command eq "set") {
        $hash->{timeout} = $value;
      } else {
        $hash->{timeout} = 60;
      }
      if ($main::init_done) {
        $hash->{ping_received}=1;      
        Timer($hash);
      };
      last;
    };
  };
}

sub Start($) {
  my $hash = shift;
  my ($dev) = split("[ \t]+", $hash->{DEF});
  $hash->{DeviceName} = $dev;
  DevIo_CloseDev($hash);
  return DevIo_OpenDev($hash, 0, "MQTT::Init");
}

sub Stop($) {
  my $hash = shift;
  send_disconnect($hash);
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);
  readingsSingleUpdate($hash,"connection","disconnected",1);
}

sub Ready($) {
  my $hash = shift;
  return DevIo_OpenDev($hash, 1, "MQTT::Init") if($hash->{STATE} eq "disconnected");
}

sub Init($) {
  my $hash = shift;
  send_connect($hash);
  readingsSingleUpdate($hash,"connection","connecting",1);
  $hash->{ping_received}=1;
  Timer($hash);
  return undef;
}

sub Timer($) {
  my $hash = shift;
  RemoveInternalTimer($hash);
  readingsSingleUpdate($hash,"connection","timed-out",1) unless $hash->{ping_received};
  $hash->{ping_received} = 0;
  InternalTimer(gettimeofday()+$hash->{timeout}, "MQTT::Timer", $hash, 0);
  send_ping($hash);
}

sub Read {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf = DevIo_SimpleRead($hash);
  return undef unless $buf;
  $hash->{buf} .= $buf;
  while (my $mqtt = Net::MQTT::Message->new_from_bytes($hash->{buf},1)) {
    
    my $message_type = $mqtt->message_type();
  
    Log3($name,5,"MQTT $name message received: ".$mqtt->string());
  
    MESSAGE_TYPE: {
      $message_type == MQTT_CONNACK and do {
        readingsSingleUpdate($hash,"connection","connected",1);
        GP_ForallClients($hash,\&client_start);
        foreach my $message_id (keys %{$hash->{messages}}) {
          my $msg = $hash->{messages}->{$message_id}->{message};
          $msg->{dup} = 1;
          DevIo_SimpleWrite($hash,$msg->bytes,undef);
        }
        last;
      };
  
      $message_type == MQTT_PUBLISH and do {
        my $topic = $mqtt->topic();
        GP_ForallClients($hash,sub {
          my $client = shift;
          Log3($client->{NAME},5,"publish received for $topic, ".$mqtt->message());
          if (grep { $topic =~ $_ } @{$client->{subscribeExpr}}) {
            readingsSingleUpdate($client,"transmission-state","incoming publish received",1);
            if ($client->{TYPE} eq "MQTT_DEVICE") {
              MQTT::DEVICE::onmessage($client,$topic,$mqtt->message());
            } else {
              MQTT::BRIDGE::onmessage($client,$topic,$mqtt->message());
            }
          };
        },undef);
        if (my $qos = $mqtt->qos() > MQTT_QOS_AT_MOST_ONCE) {
          my $message_id = $mqtt->message_id();
          if ($qos == MQTT_QOS_AT_LEAST_ONCE) {
            send_message($hash, message_type => MQTT_PUBACK, message_id => $message_id);
          } else {
            send_message($hash, message_type => MQTT_PUBREC, message_id => $message_id);
          }
        }
        last;
      };
  
      $message_type == MQTT_PUBACK and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","outgoing publish acknowledged",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        delete $hash->{messages}->{$message_id}; #QoS Level 1: at_least_once handling
        last;
      };
  
      $message_type == MQTT_PUBREC and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","outgoing publish received",1);
          };
        },undef);
        send_message($hash, message_type => MQTT_PUBREL, message_id => $message_id); #QoS Level 2: exactly_once handling
        last;
      };
  
      $message_type == MQTT_PUBREL and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","incoming publish released",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        send_message($hash, message_type => MQTT_PUBCOMP, message_id => $message_id); #QoS Level 2: exactly_once handling
        delete $hash->{messages}->{$message_id};
        last;
      };
  
      $message_type == MQTT_PUBCOMP and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","outgoing publish completed",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        delete $hash->{messages}->{$message_id}; #QoS Level 2: exactly_once handling
        last;
      };
  
      $message_type == MQTT_SUBACK and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","subscription acknowledged",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        delete $hash->{messages}->{$message_id}; #QoS Level 1: at_least_once handling
        last;
      };
  
      $message_type == MQTT_UNSUBACK and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","unsubscription acknowledged",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        delete $hash->{messages}->{$message_id}; #QoS Level 1: at_least_once handling
        last;
      };
  
      $message_type == MQTT_PINGRESP and do {
        $hash->{ping_received} = 1;
        readingsSingleUpdate($hash,"connection","active",1);
        last;
      };
  
      Log3($hash->{NAME},4,"MQTT::Read '$hash->{NAME}' unexpected message type '".message_type_string($message_type)."'");
    }
  }
  return undef;
};

sub send_connect($) {
  my $hash = shift;
  return send_message($hash, message_type => MQTT_CONNECT, keep_alive_timer => $hash->{timeout});
};

sub send_publish($@) {
  my ($hash,%msg) = @_;
  if ($msg{qos} == MQTT_QOS_AT_MOST_ONCE) {
    send_message(shift, message_type => MQTT_PUBLISH, %msg);
    return undef;
  } else {
    my $msgid = $hash->{msgid}++;
    send_message(shift, message_type => MQTT_PUBLISH, message_id => $msgid, %msg);
    return $msgid;
  }
};

sub send_subscribe($@) {
  my $hash = shift;
  my $msgid = $hash->{msgid}++;
  send_message($hash, message_type => MQTT_SUBSCRIBE, message_id => $msgid, qos => MQTT_QOS_AT_LEAST_ONCE, @_);
  return $msgid;
};

sub send_unsubscribe($@) {
  my $hash = shift;
  my $msgid = $hash->{msgid}++;
  send_message($hash, message_type => MQTT_UNSUBSCRIBE, message_id => $msgid, qos => MQTT_QOS_AT_LEAST_ONCE, @_);
  return $msgid;
};

sub send_ping($) {
  return send_message(shift, message_type => MQTT_PINGREQ);
};

sub send_disconnect($) {
  return send_message(shift, message_type => MQTT_DISCONNECT);
};

sub send_message($$$@) {
  my ($hash,%msg) = @_;
  my $name = $hash->{NAME};
  my $message = Net::MQTT::Message->new(%msg);
  Log3($name,5,"MQTT $name message sent: ".$message->string());
  if (defined $msg{message_id}) {
    $hash->{messages}->{$msg{message_id}} = {
      message => $message,
      timeout => gettimeofday()+$hash->{timeout},
    };
  }
  DevIo_SimpleWrite($hash,$message->bytes,undef);
};

sub topic_to_regexp($) {
  my $t = shift;
  $t =~ s|#$|.\*|;
  $t =~ s|\/\.\*$|.\*|;
  $t =~ s|\/|\\\/|g;
  $t =~ s|(\+)([^+]*$)|(+)$2|;
  $t =~ s|\+|[^\/]+|g;
  return "^$t\$";
}

sub client_subscribe_topic($$) {
  my ($client,$topic) = @_;
  push @{$client->{subscribe}},$topic unless grep {$_ eq $topic} @{$client->{subscribe}};
  my $expr = topic_to_regexp($topic);
  push @{$client->{subscribeExpr}},$expr unless grep {$_ eq $expr} @{$client->{subscribeExpr}};
  if ($main::init_done) {
    if (my $mqtt = $client->{IODev}) {;
      my $msgid = send_subscribe($mqtt,
        topics => [[$topic => $client->{qos} || MQTT_QOS_AT_MOST_ONCE]],
      );
      $client->{message_ids}->{$msgid}++;
      readingsSingleUpdate($client,"transmission-state","subscribe sent",1)
    }
  }
};

sub client_unsubscribe_topic($$) {
  my ($client,$topic) = @_;
  $client->{subscribe} = [grep { $_ ne $topic } @{$client->{subscribe}}];
  my $expr = topic_to_regexp($topic);
  $client->{subscribeExpr} = [grep { $_ ne $expr} @{$client->{subscribeExpr}}];
  if ($main::init_done) {
    if (my $mqtt = $client->{IODev}) {;
      my $msgid = send_unsubscribe($mqtt,
        topics => [$topic],
      );
      $client->{message_ids}->{$msgid}++;
      readingsSingleUpdate($client,"transmission-state","unsubscribe sent",1)
    }
  }
};

sub Client_Define($$) {
  my ( $client, $def ) = @_;

  $client->{NOTIFYDEV} = $client->{DEF} if $client->{DEF};
  $client->{qos} = MQTT_QOS_AT_MOST_ONCE;
  $client->{retain} = 0;
  $client->{subscribe} = [];
  $client->{subscribeExpr} = [];
  
  if ($main::init_done) {
    return client_start($client);
  } else {
    return undef;
  }
};

sub Client_Undefine($) {
  client_stop(shift);
};

sub client_attr($$$$$) {
  my ($client,$command,$name,$attribute,$value) = @_;

  ATTRIBUTE_HANDLER: {
    $attribute eq "qos" and do {
      if ($command eq "set") {
        $client->{qos} = $MQTT::qos{$value};
      } else {
        $client->{qos} = MQTT_QOS_AT_MOST_ONCE;
      }
      last;
    };
    $attribute eq "retain" and do {
      if ($command eq "set") {
        $client->{retain} = $value; 
      } else {
        $client->{retain} = 0;
      }
      last;
    };
    $attribute eq "IODev" and do {
      if ($main::init_done) {
        if ($command eq "set") {
          client_stop($client);
          $main::attr{$name}{IODev} = $value;
          client_start($client);
        } else {
          client_stop($client);
        }
      }
      last;
    };
  }
};

sub client_start($) {
  my $client = shift;
  AssignIoPort($client);
  my $name = $client->{NAME};
  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{stateFormat} = "transmission-state";
  }
  if (@{$client->{subscribe}}) {
    my $msgid = send_subscribe($client->{IODev},
      topics => [map { [$_ => $client->{qos} || MQTT_QOS_AT_MOST_ONCE] } @{$client->{subscribe}}],
    );
    $client->{message_ids}->{$msgid}++;
    readingsSingleUpdate($client,"transmission-state","subscribe sent",1);
  }
};

sub client_stop($) {
  my $client = shift;
  if (@{$client->{subscribe}}) {
    my $msgid = send_unsubscribe($client->{IODev},
      topics => [@{$client->{subscribe}}],
    );
    $client->{message_ids}->{$msgid}++;
    readingsSingleUpdate($client,"transmission-state","unsubscribe sent",1);
  }
};

1;

=pod
=begin html

<a name="MQTT"></a>
<h3>MQTT</h3>
<ul>
  <p>connects fhem to <a href="http://mqtt.org">mqtt</a>.</p>
  <p>A single MQTT device can serve multiple <a href="#MQTT_DEVICE">MQTT_DEVICE</a> and <a href="#MQTT_BRIDGE">MQTT_BRIDGE</a> clients.<br/>
     Each <a href="#MQTT_DEVICE">MQTT_DEVICE</a> acts as a bridge in between an fhem-device and mqtt.<br/>
     Note: this module is based on module <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a>.</p>
  <a name="MQTTdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MQTT &lt;ip:port&gt;</code></p>
    <p>Specifies the MQTT device.</p>
  </ul>
  <a name="MQTTset"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <p><code>set &lt;name&gt; connect</code><br/>
         (re-)connects the MQTT-device to the mqtt-broker</p>
    </li>
    <li>
      <p><code>set &lt;name&gt; disconnect</code><br/>
         disconnects the MQTT-device from the mqtt-broker</p>
    </li>
  </ul>
  <a name="MQTTattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p>keep-alive<br/>
         sets the keep-alive time (in seconds).</p>
    </li>
  </ul>
</ul>

=end html
=cut

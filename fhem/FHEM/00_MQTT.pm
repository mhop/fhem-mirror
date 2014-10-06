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
@EXPORT_OK = qw(send_publish send_subscribe send_unsubscribe client_attr);
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
  InternalTimer(gettimeofday()+AttrVal($hash-> {NAME},"keep-alive",60), "MQTT::Timer", $hash, 0);
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
        last;
      };
  
      $message_type == MQTT_PUBLISH and do {
        my $topic = $mqtt->topic();
        GP_ForallClients($hash,sub {
          my $client = shift;
          Log3($client->{NAME},5,"publish received for $topic, ".$mqtt->message());
          if (grep { $_ eq $topic } @{$client->{subscribe}}) {
            readingsSingleUpdate($client,"transmission-state","publish received",1);
            if ($client->{TYPE} eq "MQTT_DEVICE") {
              MQTT::DEVICE::onmessage($client,$topic,$mqtt->message());
            } else {
              MQTT::BRIDGE::onmessage($client,$topic,$mqtt->message());
            }
          };
        },undef);
        last;
      };
  
      $message_type == MQTT_PUBACK and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","pubacknowledge received",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        last;
      };
  
      $message_type == MQTT_PUBREC and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","pubreceive received",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        last;
      };
  
      $message_type == MQTT_PUBREL and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","pubrelease received",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
        last;
      };
  
      $message_type == MQTT_PUBCOMP and do {
        my $message_id = $mqtt->message_id();
        GP_ForallClients($hash,sub {
          my $client = shift;
          if ($client->{message_ids}->{$message_id}) {
            readingsSingleUpdate($client,"transmission-state","pubcomplete received",1);
            delete $client->{message_ids}->{$message_id};
          };
        },undef);
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
  return send_message($hash, message_type => MQTT_CONNECT, keep_alive_timer => AttrVal($hash->{NAME},"keep-alive",60));
};

sub send_publish($@) {
  return send_message(shift, message_type => MQTT_PUBLISH, @_);
};

sub send_subscribe($@) {
  my $hash = shift;
  return send_message($hash, message_type => MQTT_SUBSCRIBE, @_);
};

sub send_unsubscribe($@) {
  return send_message(shift, message_type => MQTT_UNSUBSCRIBE, @_);
};

sub send_ping($) {
  return send_message(shift, message_type => MQTT_PINGREQ);
};

sub send_disconnect($) {
  return send_message(shift, message_type => MQTT_DISCONNECT);
};

sub send_message($$$@) {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $msgid = $hash->{msgid}++;
  my $msg = Net::MQTT::Message->new(message_id => $msgid,@_);
  Log3($name,5,"MQTT $name message sent: ".$msg->string());
  DevIo_SimpleWrite($hash,$msg->bytes,undef);
  return $msgid;
};

sub Client_Define($$) {
  my ( $client, $def ) = @_;

  $client->{NOTIFYDEV} = $client->{DEF} if $client->{DEF};
  $client->{qos} = MQTT_QOS_AT_MOST_ONCE;
  $client->{subscribe} = [];
  
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
  connects fhem to <a href="http://mqtt.org">mqtt</a>
  <br><br>
  A single MQTT device can serve multiple <a href="#MQTT_DEVICE">MQTT_DEVICE</a> clients.<br><br>
   
  Each <a href="#MQTT_DEVICE">MQTT_DEVICE</a> acts as a bridge in between an fhem-device and mqtt.
  
  Note: this module is based on module <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a>.
  <br><br>
  
  <a name="MQTTdefine"></a>
  <b>Define</b><br>
  <ul><br>
    <code>define &lt;name&gt; MQTT &lt;ip:port&gt;</code> <br>
    Specifies the MQTT device.<br>
    <br>
    <br>
    <a name="MQTTset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>set &lt;name&gt; connect</code><br>
        (re-)connects the MQTT-device to the mqtt-broker
      </li><br>
      <li>
        <code>set &lt;name&gt; disconnect</code><br>
        disconnects the MQTT-device from the mqtt-broker
      </li>
    </ul>
    <br><br>
    <a name="MQTTattr"></a>
    <b>Attributes</b><br>
    <ul>
      <li>keep-alive<br>
      sets the keep-alive time (in seconds).
      </li>
    </ul>
  </ul>
</ul>
<br>

=end html
=cut

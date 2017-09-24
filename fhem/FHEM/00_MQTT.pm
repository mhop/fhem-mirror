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

my %sets = (
  "connect" => "",
  "disconnect" => "",
  "publish" => "",
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
  $hash->{DefFn}      = "MQTT::Define";
  $hash->{UndefFn}    = "MQTT::Undef";
  $hash->{DeleteFn}   = "MQTT::Delete";
  $hash->{ShutdownFn} = "MQTT::Shutdown";
  $hash->{SetFn}      = "MQTT::Set";
  $hash->{NotifyFn}   = "MQTT::Notify";
  $hash->{AttrFn}     = "MQTT::Attr";

  $hash->{AttrList} = "keep-alive "."last-will "."on-connect on-disconnect on-timeout ".$main::readingFnAttributes;
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
  ReadingsVal
  Log3
  AssignIoPort
  getKeyValue
  setKeyValue
  CallFn
  defs
  modules
  looks_like_number
  fhem
  ))};

sub Define($$) {
  my ( $hash, $def ) = @_;

  $hash->{NOTIFYDEV} = "global";
  $hash->{msgid} = 1;
  $hash->{timeout} = 60;
  $hash->{messages} = {};

  my ($host,$username,$password) = split("[ \t]+", $hash->{DEF});
  $hash->{DeviceName} = $host;
  
  my $name = $hash->{NAME};
  my $user = getKeyValue($name."_user");
  my $pass = getKeyValue($name."_pass");

  setKeyValue($name."_user",$username) unless(defined($user));
  setKeyValue($name."_pass",$password) unless(defined($pass));

  $hash->{DEF} = $host;
  
  #readingsSingleUpdate($hash,"connection","disconnected",0);

  if ($main::init_done) {
    return Start($hash);
  } else {
    return undef;
  }
}

sub Undef($) {
  my $hash = shift;
  Stop($hash);
  return undef;
}

sub Delete($$) {
  my ($hash, $name) = @_;
  setKeyValue($name."_user",undef);
  setKeyValue($name."_pass",undef);
  return undef;
}

sub Shutdown($) {
  my $hash = shift;
  Stop($hash);
  my $name = $hash->{NAME};
  Log3($name,1,"Shutdown executed");
  return undef;
}

sub onConnect($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $cmdstr = AttrVal($name,"on-connect",undef);
  return process_event($hash,$cmdstr);
}

sub onDisconnect($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $cmdstr = AttrVal($name,"on-disconnect",undef);
  return process_event($hash,$cmdstr);
}

sub onTimeout($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  my $cmdstr = AttrVal($name,"on-timeout",undef);
  if($cmdstr) {
    return eval($cmdstr);
  }
}

sub process_event($$) {
  my $hash = shift;
  my $str = shift;
  my ($qos, $retain,$topic, $message, $cmd) = parsePublishCmdStr($str);
  
  my $do=1;
  if($cmd) {
    my $name = $hash->{NAME};
    $do=eval($cmd);
    $do=1 if (!defined($do));
    #no strict "refs";
    #my $ret = &{$hash->{WBCallback}}($hash);
    #use strict "refs";
  }
  
  if($do && defined($topic)) {
    $qos = MQTT_QOS_AT_MOST_ONCE unless defined($qos);
    send_publish($hash, topic => $topic, message => $message, qos => $qos, retain => $retain);
  }
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
    $command eq "publish" and do {
      shift(@a);
      shift(@a);
      #if(scalar(@a)<2) {return "not enough parameters. usage: publish [qos [retain]] topic value";}
      #my $qos=0;
      #my $retain=0;
      #if(looks_like_number ($a[0])) {
      #   $qos = int($a[0]);
      #   $qos = 0 if $qos>1;
      #   shift(@a);
      #   if(looks_like_number ($a[0])) {
      #     $retain = int($a[0]);
      #     $retain = 0 if $retain>2;
      #     shift(@a);
      #   }
      #}
      #if(scalar(@a)<2) {return "missing parameters. usage: publish [qos [retain]] topic value";}
      #my $topic = shift(@a);
      #my $value = join (" ", @a);
      
      my ($qos, $retain,$topic, $value) = parsePublishCmd(@a);
      return "missing parameters. usage: publish [qos:?] [retain:?] topic value1 [value2]..." if(!$topic);
      return "wrong parameter. topic may nob be '#' or '+'" if ($topic eq '#' or $topic eq '+');
      $qos = MQTT_QOS_AT_MOST_ONCE unless defined($qos);
      my $msgid = send_publish($hash, topic => $topic, message => $value, qos => $qos, retain => $retain);
      last;
    }
  };
}

sub parsePublishCmdStr($) {
  my ($str) = @_;

  if(defined($str) && $str=~m/\s*(?:({.*})\s+)?(.*)/) {
    my $exp = $1;
    my $rest = $2;
    if ($rest){
      my @lwa = split("[ \t]+",$rest);
      unshift (@lwa,$exp) if($exp);
      return parsePublishCmd(@lwa);
    }    
  }
  return undef;
}

sub parsePublishCmd(@) {
  my @a = @_;
  # [qos:?] [retain:?] topic value
  
  return undef if(!@a);
  return undef if(scalar(@a)<1);
  
  my $qos = 0;
  my $retain = 0;
  my $topic = undef;
  my $value = "\0";
  my $expression = undef;
  
  while (scalar(@a)>0) {
    my $av = shift(@a);
    if($av =~ /\{.*\}/) {
      $expression = $av;
      next;
    }
    my ($pn,$pv) = split(":",$av);
    if(defined($pv)) {
      if($pn eq "qos") {
        if($pv >=0 && $pv <=2) {
          $qos = $pv;
        }
      } elsif($pn eq "retain") {
        if($pv >=0 && $pv <=1) {
          $retain = $pv;
        }
      } else {
        # ignore
        next;
      }
    } else {
      $topic = $av;
      last;
    }
  }
  
  if(scalar(@a)>0) {
    $value = join(" ", @a);
  }
  
  return undef unless $topic || $expression;  
  return ($qos, $retain,$topic, $value, $expression);
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
    $attribute eq "last-will" and do {
      if($hash->{STATE} ne "disconnected") {
        Stop($hash);
        InternalTimer(gettimeofday()+1, "MQTT::Start", $hash, 0);
      }
      last;
    };
  };
}

#sub Reconnect($){
#  my $hash = shift;
#  Stop($hash);
#  Start($hash);
#}

sub Start($) {
  my $hash = shift;
  my $firsttime = $hash->{".cinitmark"};
  
  if(defined($firsttime)) {
    my $cstate=ReadingsVal($hash->{NAME},"connection","");
    if($cstate ne "disconnected" && $cstate ne "timed-out") {
      return undef;
    }
  } else {
    $hash->{".cinitmark"} = 1;
  }
   
  DevIo_CloseDev($hash);
  return DevIo_OpenDev($hash, 0, "MQTT::Init");
}

sub Stop($) {
  my $hash = shift;
  
  my $cstate=ReadingsVal($hash->{NAME},"connection","");
  if($cstate eq "disconnected" || $cstate eq "timed-out") {
    return undef;
  }
  
  send_disconnect($hash);
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);
  readingsSingleUpdate($hash,"connection","disconnected",1);
}

sub Ready($) {
  my $hash = shift;
  return DevIo_OpenDev($hash, 1, "MQTT::Init") if($hash->{STATE} eq "disconnected");
}

sub Rename() {
  my ($new,$old) = @_;
  setKeyValue($new."_user",getKeyValue($old."_user"));
  setKeyValue($new."_pass",getKeyValue($old."_pass"));
	
  setKeyValue($old."_user",undef);
  setKeyValue($old."_pass",undef);
  return undef;
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
  unless ($hash->{ping_received}) {
    onTimeout($hash);
    readingsSingleUpdate($hash,"connection","timed-out",1) ;#unless $hash->{ping_received};
  }
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
        onConnect($hash);
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
            my $fn = $modules{$defs{$client->{NAME}}{TYPE}}{OnMessageFn};
            if($fn) {
              CallFn($client->{NAME},"OnMessageFn",($client,$topic,$mqtt->message()))
            } elsif ($client->{TYPE} eq "MQTT_DEVICE") {
              MQTT::DEVICE::onmessage($client,$topic,$mqtt->message());
            } elsif ($client->{TYPE} eq "MQTT_BRIDGE") {
              MQTT::BRIDGE::onmessage($client,$topic,$mqtt->message());
            } else {
              Log3($client->{NAME},1,"unexpected client or no OnMessageFn defined: ".$client->{TYPE});
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
  my $name = $hash->{NAME};
  my $user = getKeyValue($name."_user");
  my $pass = getKeyValue($name."_pass");
  
  my $lw = AttrVal($name,"last-will",undef);
  my ($willqos, $willretain,$willtopic, $willmessage) = parsePublishCmdStr($lw);
  
  return send_message($hash, message_type => MQTT_CONNECT, keep_alive_timer => $hash->{timeout}, user_name => $user, password => $pass, will_topic => $willtopic,  will_message => $willmessage, will_retain => $willretain, will_qos => $willqos);
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
  my $hash = shift;
  onDisconnect($hash);
  return send_message($hash, message_type => MQTT_DISCONNECT);
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

sub client_subscribe_topic($$;$$) {
  my ($client,$topic,$qos,$retain) = @_;
  push @{$client->{subscribe}},$topic unless grep {$_ eq $topic} @{$client->{subscribe}};
  my $expr = topic_to_regexp($topic);
  push @{$client->{subscribeExpr}},$expr unless grep {$_ eq $expr} @{$client->{subscribeExpr}};
  if ($main::init_done) {
    if (my $mqtt = $client->{IODev}) {;
      $qos = $client->{".qos"}->{"*"} unless defined $qos; # MQTT_QOS_AT_MOST_ONCE
      $retain = 0 unless defined $retain; # not supported yet
      my $msgid = send_subscribe($mqtt,
        topics => [[$topic => $qos || MQTT_QOS_AT_MOST_ONCE]],
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
  #$client->{qos} = MQTT_QOS_AT_MOST_ONCE; ### ALT
  $client->{".qos"}->{'*'} = 0; 
  $client->{".retain"}->{'*'} = "0";
  $client->{subscribe} = [];
  $client->{subscribeExpr} = [];
  AssignIoPort($client);

  if ($main::init_done) {
    return client_start($client);
  } else {
    return undef;
  }
};

sub Client_Undefine($) {
  client_stop(shift);
  return undef;
};
#use Data::Dumper;
sub client_attr($$$$$) {
  my ($client,$command,$name,$attribute,$value) = @_;

  ATTRIBUTE_HANDLER: {
    $attribute eq "qos" and do {
      #if ($command eq "set") {
      #  $client->{qos} = $MQTT::qos{$value}; ### ALT
      #} else {
      #  $client->{qos} = MQTT_QOS_AT_MOST_ONCE; ### ALT
      #}
      
      delete($client->{".qos"});
      
      if ($command ne "set") {
        delete($client->{".qos"});
        $client->{".qos"}->{"*"} = "0";
      } else {
      
        my @values = ();
        if(!defined($value) || $value=~/^[ \t]*$/) {
           return "QOS value may not be empty. Format: [<reading>|*:]0|1|2";
        }
        @values = split("[ \t]+",$value);
    
        foreach my $set (@values) {
          my($rname,$rvalue) = split(":",$set);
          if(!defined($rvalue)) {
            $rvalue=$rname;
            $rname="";
            $rname="*" if (scalar(@values)==1); # backward compatibility: single value without a reading name should be applied to all
          }
          #if ($command eq "set") {
            # Map constants
            #$rvalue = MQTT_QOS_AT_MOST_ONCE if($rvalue eq qos_string(MQTT_QOS_AT_MOST_ONCE));
            #$rvalue = MQTT_QOS_AT_LEAST_ONCE if($rvalue eq qos_string(MQTT_QOS_AT_LEAST_ONCE));
            #$rvalue = MQTT_QOS_EXACTLY_ONCE if($rvalue eq qos_string(MQTT_QOS_EXACTLY_ONCE));
            $rvalue=$MQTT::qos{$rvalue} if(defined($MQTT::qos{$rvalue}));
            if($rvalue ne "0" && $rvalue ne "1" && $rvalue ne "2") {
              return "unexpected QOS value $rvalue. use 0, 1 or 2. Constants may be also used (".MQTT_QOS_AT_MOST_ONCE."=".qos_string(MQTT_QOS_AT_MOST_ONCE).", ".MQTT_QOS_AT_LEAST_ONCE."=".qos_string(MQTT_QOS_AT_LEAST_ONCE).", ".MQTT_QOS_EXACTLY_ONCE."=".qos_string(MQTT_QOS_EXACTLY_ONCE)."). Format: [<reading>|*:]0|1|2";
            }
            #$rvalue="1" unless ($rvalue eq "0");
            $client->{".qos"}->{$rname} = $rvalue;
          #} else {
          #  delete($client->{".qos"}->{$rname});
          #  $client->{".qos"}->{"*"} = "0" if($rname eq "*");
          #}
        }
      }
      
      my $showqos = "";
      if(defined($client->{".qos"})) {
        foreach my $rname (sort keys %{$client->{".qos"}}) {
          my $rvalue = $client->{".qos"}->{$rname};
          $rname="[state]" if ($rname eq "");
          $showqos.=$rname.':'.$rvalue.' ';
        }
      }
      $client->{"qos"} = $showqos;
      last;
    };
    $attribute eq "retain" and do {
      delete($client->{".retain"});
      
      if ($command ne "set") {
        delete($client->{".retain"});
        $client->{".retain"}->{"*"} = "0";
      } else {
        my @values = ();

        if(!defined($value) || $value=~/^[ \t]*$/) {
           return "retain value may not be empty. Format: [<reading>|*:]0|1";
        }
        @values = split("[ \t]+",$value);
        
        foreach my $set (@values) {
          my($rname,$rvalue) = split(":",$set);
          if(!defined($rvalue)) {
            $rvalue=$rname;
            $rname="";
            $rname="*" if (scalar(@values)==1); # backward compatibility: single value without a reading name should be applied to all
          }
            if($rvalue ne "0" && $rvalue ne "1") {
              return "unexpected retain value. use 0 or 1. Format: [<reading>|*:]0|1";
            }
            $client->{".retain"}->{$rname} = $rvalue;
        }
      }
      
      my $showretain = "";
      if(defined($client->{".retain"})) {
        foreach my $rname (sort keys %{$client->{".retain"}}) {
          my $rvalue = $client->{".retain"}->{$rname};
          $rname="[state]" if ($rname eq "");
          $showretain.=$rname.':'.$rvalue.' ';
        }
      }
      $client->{"retain"} = $showretain;
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
  my $name = $client->{NAME};
  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{stateFormat} = "transmission-state";
  }
  if (@{$client->{subscribe}}) {
    my $msgid = send_subscribe($client->{IODev},
      topics => [map { [$_ => $client->{".qos"}->{$_} || MQTT_QOS_AT_MOST_ONCE] } @{$client->{subscribe}}],
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
=item [device]
=item summary connects fhem to MQTT
=begin html

<a name="MQTT"></a>
<h3>MQTT</h3>
<ul>
  <p>connects fhem to <a href="http://mqtt.org">mqtt</a>.</p>
  <p>A single MQTT device can serve multiple <a href="#MQTT_DEVICE">MQTT_DEVICE</a> and <a href="#MQTT_BRIDGE">MQTT_BRIDGE</a> clients.<br/>
     Each <a href="#MQTT_DEVICE">MQTT_DEVICE</a> acts as a bridge in between an fhem-device and mqtt.<br/>
     Note: this module is based on <a href="https://metacpan.org/pod/distribution/Net-MQTT/lib/Net/MQTT.pod">Net::MQTT</a> which needs to be installed from CPAN first.</p>
  <a name="MQTTdefine"></a>
  <p><b>Define</b></p>
  <ul>
    <p><code>define &lt;name&gt; MQTT &lt;ip:port&gt; [&lt;username&gt;] [&lt;password&gt;]</code></p>
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
    <li>
      <p><code>set &lt;name&gt; publish [qos:?] [retain:?] &lt;topic&gt; &lt;message&gt;</code><br/>
         sends message to the specified topic</p>
    </li>
  </ul>
  <a name="MQTTattr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <p>keep-alive<br/>
         sets the keep-alive time (in seconds).</p>
    </li>
    <li>
      <p><code>attr &lt;name&gt; last-will [qos:?] [retain:?] &lt;topic&gt; &lt;message&gt;</code><br/>
         Support for MQTT feature "last will" 
         </p>
      <p>example:<br/>
      <code>attr mqtt last-will /fhem/status crashed</code>
      </p>
    </li>
    <li>
      <p>on-connect, on-disconnect<br/>
      <code>attr &lt;name&gt; on-connect {Perl-expression} &lt;topic&gt; &lt;message&gt;</code><br/>
         Publish the specified message to a topic at connect / disconnect (counterpart to lastwill) and / or evaluation of Perl expression<br/>
         If a Perl expression is provided, the message is sent only if expression returns true (for example, 1) or undef.<br/>
         The following variables are passed to the expression at evaluation: $hash, $name, $qos, $retain, $topic, $message.
         </p>
      <p>examples:<br/>
      <code>attr mqtt on-connect /topic/status connected</code><br/>
      <code>attr mqtt on-connect {Log3("abc",1,"on-connect")} /fhem/status connected</code>
      </p>
    </li>
    <li>
      <p>on-timeout<br/>
      <code>attr &lt;name&gt; on-timeout {Perl-expression}</code>    
         evaluate the given Perl expression on timeout<br/>
         </p>
    </li>
  </ul>
</ul>

=end html
=cut

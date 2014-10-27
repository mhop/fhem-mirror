
# $Id$

package main;

use strict;
use warnings;

use Data::Dumper;

use JSON;
use MIME::Base64;
use IO::Socket::INET;
use Encode qw(encode_utf8);
#use XML::Simple qw(:strict);

use HttpUtils;

my $harmony_isFritzBox = undef;
sub
harmony_isFritzBox()
{
  $harmony_isFritzBox = int( qx( [ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0 ) )  if( !defined($harmony_isFritzBox) );

  return $harmony_isFritzBox;
}

sub
harmony_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "harmony_Read";

  $hash->{DefFn}    = "harmony_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "harmony_Notify";
  $hash->{UndefFn}  = "harmony_Undefine";
  $hash->{SetFn}    = "harmony_Set";
  $hash->{GetFn}    = "harmony_Get";
  $hash->{AttrFn}   = "harmony_Attr";
  $hash->{AttrList} = "disable:1 nossl:1 $readingFnAttributes"
}

#####################################

sub
harmony_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> harmony [username password] ip"  if(@a < 3 || @a > 5);
  return "Usage: define <name> harmony [username password] ip"  if(@a == 4 && $a[2] ne "DEVICE" );

  delete( $hash->{helper}{username} );
  delete( $hash->{helper}{password} );

  my $name = $a[0];

  if( @a == 3 ) {
    my $ip = $a[2];

    $hash->{ip} = $ip;

  } elsif( @a == 4 ) {
    my $id = $a[3];

    return "$name: device '$id' already defined" if( defined($modules{$hash->{TYPE}}{defptr}{$id}) );

    $hash->{id} = $id;
    $modules{$hash->{TYPE}}{defptr}{$id} = $hash;

  } elsif( @a == 5 ) {
    my $username = $a[2];
    my $password = $a[3];
    my $ip = $a[4];

    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    $hash->{ip} = $ip;

  }

  $hash->{NAME} = $name;

  $hash->{STATE} = "Initialized";
  $hash->{ConnectionState} = "Initialized";

  #$attr{$name}{nossl} = 1 if( !$init_done && harmony_isFritzBox() );

  if( $init_done ) {
    harmony_connect($hash) if( !defined($hash->{id}) );
  }

  return undef;
}

sub
harmony_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  harmony_connect($hash) if( !defined($hash->{id}) );
}

sub
harmony_Undefine($$)
{
  my ($hash, $arg) = @_;

  if( defined($hash->{id}) ) {
    delete( $modules{$hash->{TYPE}}{defptr}{$hash->{id}} );
    return undef;
  }


  RemoveInternalTimer($hash);

  harmony_disconnect($hash);

  return undef;
}

sub
harmony_idOfActivity($$;$)
{
  my ($hash, $label, $default) = @_;

  foreach my $activity (@{$hash->{config}->{activity}}) {
    return $activity->{id} if( $activity->{label} =~ m/^$label$/ );
  }

  return $default;
}
sub
harmony_labelOfActivity($$;$)
{
  my ($hash, $id, $default) = @_;

  foreach my $activity (@{$hash->{config}->{activity}}) {
    return $activity->{label} if( $activity->{id} == $id );
  }

  return $default;
}
sub
harmony_activityOfId($$)
{
  my ($hash, $id) = @_;

  foreach my $activity (@{$hash->{config}->{activity}}) {
    return $activity if( $activity->{id} == $id );
  }

  return undef;
}

sub
harmony_idOfDevice($$;$)
{
  my ($hash, $label, $default) = @_;

  foreach my $device (@{$hash->{config}->{device}}) {
    return $device->{id} if( $device->{label} =~ m/^$label$/ );
  }

  return $default;
}
sub
harmony_labelOfDevice($$;$)
{
  my ($hash, $id, $default) = @_;

  foreach my $device (@{$hash->{config}->{device}}) {
    return $device->{label} if( $device->{id} == $id );
  }

  return $default;
}
sub
harmony_deviceOfId($$)
{
  my ($hash, $id) = @_;

  foreach my $device (@{$hash->{config}->{device}}) {
    return $device if( $device->{id} == $id );
  }

  return undef;
}

sub
harmony_actionOfCommand($$)
{
  my ($device, $command) = @_;
  return undef if( ref($device) ne "HASH" );

  $command = lc($command);

  foreach my $group (@{$device->{controlGroup}}) {
    foreach my $function (@{$group->{function}}) {
      if( lc($function->{name}) eq $command ) {
        return decode_json($function->{action}) if( harmony_isFritzBox() );

        return JSON->new->utf8(0)->decode($function->{action});

      }
    }
  }

  return undef;
}


sub
harmony_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;
  my ($param, $param2) = @params;
  #$cmd = lc( $cmd );

  my $list = "";
  if( defined($hash->{id}) ) {
    if( !$hash->{hub} ) {
      $hash->{hub} = harmony_hubOfDevice($param);

      return "no hub found for device $name ($param)" if( !$hash->{hub} );
    }


    if( $cmd eq "command" ) {
      $param2 = $param;
      $param = $hash->{id};

      $hash = $defs{$hash->{hub}};

    } elsif( $cmd eq "hidDevice" || $cmd eq "text" || $cmd eq "cursor" || $cmd eq "special" || $cmd eq "hid" ) {
      my $id = $hash->{id};

      $hash = $defs{$hash->{hub}};

      my $device = harmony_deviceOfId( $hash, $id );
      return "unknown device" if( !$device );

      return "no keyboard associated with device $device->{label}" if( !$device->{IsKeyboardAssociated} );

      if( !$hash->{hidDevice} || $hash->{hidDevice} ne $id ) {
        $hash->{hidDevice} = $id;
        harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='harmony.engine?sethiddevice' token=''>deviceId=$id</oa>");
        sleep( 3 );
      }

      return if( $cmd eq "hidDevice" );

    } else {
      $list = "command hidDevice:noArg text cursor:up,down,left,right,pageUp,pageDown,home,end special:previousTrack,nextTrack,stop,playPause,volumeUp,volumeDown,mute";
      return "Unknown argument $cmd, choose one of $list" if( defined($hash->{id}) );

    }
  }

  if( $cmd eq 'off' ) {
    $cmd = "activity";
    $param = "PowerOff";
  }

  if( $cmd eq 'activity' ) {
    $param = harmony_idOfActivity($hash, $param) if( $param && $param !~ m/^([\d-])+$/ );
    return "unknown activity" if( !$param );

    harmony_sendEngineGet($hash, "startactivity", "activityId=$param:timestamp=0");

    return undef;
  } elsif( $cmd eq "command" ) {
    my $action;

    if( !$param2 ) {
      return "unknown activity" if( !$hash->{currentActivityID} );
      return "unknown command" if( !$param );

      my $activity = harmony_activityOfId($hash, $hash->{currentActivityID});
      return "unknown activity" if( !$activity );

      $action = harmony_actionOfCommand( $activity, $param );
      return "unknown command $param" if( !$action );

    } else {
      $param = harmony_idOfDevice($hash, $param) if( $param && $param !~ m/^([\d-])+$/ );
      return "unknown device" if( !$param );
      return "unknown command" if( !$param2 );

      my $device = harmony_deviceOfId( $hash, $param );
      return "unknown device" if( !$device );

      $action = harmony_actionOfCommand( $device, $param2 );
      return "unknown command $param2" if( !$action );
    }

    Log3 $name, 4, "$name: sending $action->{command} for ". harmony_labelOfDevice($hash, $action->{deviceId} );

    my $payload = "status=press:action={'command'::'$action->{command}','type'::'$action->{type}','deviceId'::'$action->{deviceId}'}:timestamp=0";
    harmony_sendEngineRender($hash, "holdAction", $payload);
    select(undef, undef, undef, (0.1));
    $payload = "status=release:action={'command'::'$action->{command}','type'::'$action->{type}','deviceId'::'$action->{deviceId}'}:timestamp=100";
    harmony_sendEngineRender($hash, "holdAction", $payload);

    return undef;
  } elsif( $cmd eq "getCurrentActivity" ) {
    harmony_sendEngineGet($hash, "getCurrentActivity", "");

    return undef;

  } elsif( $cmd eq "getConfig" ) {
    harmony_sendEngineGet($hash, "config", "");

    return undef;

  } elsif( $cmd eq "hidDevice" ) {
    my $id = $param;

    if( !$id && $hash->{currentActivityID} ) {
      my $activity = harmony_activityOfId($hash, $hash->{currentActivityID});
      return "unknown activity" if( !$activity );

      return "no KeyboardTextEntryActivityRole in current activity $activity->{label}" if( !$activity->{KeyboardTextEntryActivityRole} );

      $id = $activity->{KeyboardTextEntryActivityRole};

    } else {
      $id = harmony_idOfDevice($hash, $id) if( $id && $id !~ m/^([\d-])+$/ );
      return "unknown device $param" if( $param && !$id );

      my $device = harmony_deviceOfId( $hash, $id );
      return "unknown device" if( !$device );

      return "no keyboard associated with device $device->{label}" if( !$device->{IsKeyboardAssociated} );

    }

    $hash->{hidDevice} = $id;
    harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='harmony.engine?sethiddevice' token=''>deviceId=$id</oa>");
    return undef;

  } elsif( $cmd eq "hid" || $cmd eq "text" || $cmd eq "cursor" || $cmd eq "special" ) {
    return "nothing to send" if( !$param );

    return "unknown activity" if( !$hash->{currentActivityID} );
    return "unknown command" if( !$param );

    if( !$hash->{hidDevice} ) {
      my $activity = harmony_activityOfId($hash, $hash->{currentActivityID});
      return "unknown activity" if( !$activity );

      return "no KeyboardTextEntryActivityRole in current activity $activity->{label}" if( !$activity->{KeyboardTextEntryActivityRole} );
    }

    if( $cmd eq "text" ) {
      $hash->{hid} = "" if( !$hash->{hid} );
      $hash->{hid} .= join(' ', @params);

      $param = undef;
    } elsif( $cmd eq "cursor" ) {
      $param = lc( $param ) if( $param );

      $param = "0700004A" if( $param eq "home" );
      $param = "0700004B" if( $param eq "pageup" );
      $param = "0700004D" if( $param eq "end" );
      $param = "0700004E" if( $param eq "pagedown" );
      $param = "0700004F" if( $param eq "right" );
      $param = "07000050" if( $param eq "left" );
      $param = "07000051" if( $param eq "down" );
      $param = "07000052" if( $param eq "up" );

      return "unknown cursor direction $param" if( $param !~ m/^07/ );

    } elsif( $cmd eq "special" ) {
      $param = lc( $param ) if( $param );

      $param = "01000081" if( $param eq "systempower" );
      $param = "01000082" if( $param eq "systemsleep" );
      $param = "01000083" if( $param eq "systemwake" );
      $param = "0C0000B5" if( $param eq "nexttrack" );
      $param = "0C0000B6" if( $param eq "previoustrack" );
      $param = "0C0000B7" if( $param eq "stop" );
      $param = "0C0000CD" if( $param eq "playpause" );
      $param = "0C0000E9" if( $param eq "volumeup" );
      $param = "0C0000EA" if( $param eq "volumedown" );
      $param = "0C0000E2" if( $param eq "mute" );

      return "unknown special key $param" if( $param !~ m/^0(1|C)/ );
    }

    harmony_sendHID($hash, $param);

    return undef;

  } elsif( $cmd eq "reconnect" ) {
    harmony_connect($hash);

    return undef;

  } elsif( $cmd eq "autocreate" ) {
    return harmony_autocreate($hash,$param);

    return undef;

  } elsif( $cmd eq "sleeptimer" ) {
    my $interval = $param?$param*60:60*60;
    $interval = -1 if( $interval < 0 );

    harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='harmony.engine?setsleeptimer' token=''>interval=$interval</oa>", "setsleeptimer");

    return undef;

  } elsif( $cmd eq "sync" ) {
    harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='setup.sync' token=''/>");

    return undef;
  }

  if( $hash->{config} ) {
    return undef if( !defined($hash->{config}) );

    my $activities;
    foreach my $activity (sort { ($a->{activityOrder}||0) <=> ($b->{activityOrder}||0) } @{$hash->{config}->{activity}}) {
      next if( $activity->{label} eq "PowerOff" );
      $activities .= "," if( $activities );
      $activities .= $activity->{label};
     }
    if( $activities ) {
      $activities =~ s/ /./g;

      $list .= " activity:$activities,PowerOff";
    }

    my $hidDevices;
    my $autocreateDevices;
    foreach my $device (sort { $a->{id} <=> $b->{id} } @{$hash->{config}->{device}}) {
      if( $device->{IsKeyboardAssociated} ) {
        $hidDevices .= "," if( $hidDevices );
        $hidDevices .= harmony_labelOfDevice($hash, $device->{id} );
      }

      if( !defined($modules{$hash->{TYPE}}{defptr}{$device->{id}}) ) {
        $autocreateDevices .= "," if( $autocreateDevices );
        $autocreateDevices .= harmony_labelOfDevice($hash, $device->{id} );
      }
    }

    if( $hidDevices ) {
      $hidDevices =~ s/ /./g;

      $list .= " hidDevice:,$hidDevices";
    }

    if( $autocreateDevices ) {
      $autocreateDevices =~ s/ /./g;

      $list .= " autocreate:$autocreateDevices,";
    }

  }

  $list .= " command getConfig:noArg getCurrentActivity:noArg off:noArg reconnect:noArg sleeptimer sync:noArg text cursor:up,down,left,right,pageUp,pageDown,home,end special:previousTrack,nextTrack,stop,playPause,volumeUp,volumeDown,mute";

  return "Unknown argument $cmd, choose one of $list";
}

sub
harmony_getLoginToken($)
{
  my ($hash) = @_;

  return if( defined($hash->{helper}{UserAuthToken}) );

  if( !$hash->{helper}{username} ) {
    $hash->{helper}{UserAuthToken} = "";
    return;

  }

  my $https = "https";
  $https = "http" if( AttrVal($hash->{NAME}, "nossl", 0) );

  my $json = encode_json( { email => $hash->{helper}{username}, password => $hash->{helper}{password} } );

  my($err,$data) = HttpUtils_BlockingGet({
    url => "$https://svcs.myharmony.com/CompositeSecurityServices/Security.svc/json/GetUserAuthToken",
    timeout => 10,
    #noshutdown => 1,
    #httpversion => "1.1",
    header => "Content-Type: application/json;charset=utf-8",
    data => $json,
  });

  harmony_dispatch( {hash=>$hash,type=>'token'},$err,$data );
}

sub
harmony_attr2hash($)
{
  my ($attr) = @_;

  my @args = split(' ', $attr);

  my %params = ();
  while (@args) {
    my $arg = shift(@args);

    my ($name,$value) = split("=", $arg,2);

    while( $value && $value =~ m/^'/ && $value !~ m/'$/ ) {
      my $next = shift(@args);
      last if( !defined($next) );
      $value .= " ". $next;
    }

    $params{$name} = substr( $value, 1, -1 );
  }

  return \%params;
}

sub
harmony_CDATA2hash($)
{
  my ($cdata) = @_;

  my @args = split(':', $cdata);

  my %params = ();
  while (@args) {
    my $arg = shift(@args);
    my ($name,$value) = split("=", $arg,2);

    #fix for updates=table: 0x...
    if( $args[0] && $args[0] !~ m/=/ ) {
      my $next = shift(@args);
      last if( !defined($next) );
      $value .= ":". $next;
    }

    ##fix for http://...
    #if( $args[0] && $args[0] =~ m/^\/\// ) {
    #  my $next = shift(@args);
    #  last if( !defined($next) );
    #  $value .= ":". $next;
    #}

    #fix for json {...<key>:<value>...}
    while( $value && $value =~ m/^{/ && $value !~ m/}$/ ) {
      my $next = shift(@args);
      last if( !defined($next) );
      $value .= ":". $next;
    }

    $params{$name} = $value;
  }

  return \%params;
}

use constant  { CTRL   => 0x01,
                SHIFT  => 0x02,
                ALT    => 0x04,
                GUI    => 0x08,
                RIGHT_CTRL  => 0x10,
                RIGHT_SHIFT => 0x20,
                RIGHT_ALT   => 0x40,
                RIGHT_GUI   => 0x80,
              };

my %keys = ( '1' => '0702001E',
             '2' => '0702001F',
             '3' => '07020020',
             '4' => '07020021',
             '5' => '07020022',
             '6' => '07020023',
             '7' => '07020024',
             '8' => '07020025',
             '9' => '07020026',
             '0' => '07020027',

            '\\n'=> '07000028',
            '\\e'=> '07000029',
            '\\t'=> '0700002B',
             ' ' => '0700002C',

             '!' => '0702001E',
             '"' => '0702001F',
             '§' => '07020020',
             '$' => '07020021',
             '%' => '07020022',
             '&' => '07020023',
             '/' => '07020024',
             '(' => '07020025',
             ')' => '07020026',
             '=' => '07020027',

             'ß' => '0700002D',
             '´' => '0700002E',
             'ü' => '0700002F',
             '+' => '07000030',
             '#' => '07000031',
             'ö' => '07000033',
             'ä' => '07000034',
             '<' => '07000035',
             ',' => '07000036',
             '.' => '07000037',
             '-' => '07000038',

             '?' => '0702002D',
             '`' => '0702002E',
             'Ü' => '0702002F',
             '*' => '07020030',
             "'" => '07020031',
             'Ö' => '07020033',
             'Ä' => '07020034',
             '>' => '07020035',
             ';' => '07020036',
             ':' => '07020037',
             '_' => '07020038',

           'F1'  => '0700003A',
           'F2'  => '0700003B',
           'F3'  => '0700003C',
           'F4'  => '0700003D',
           'F5'  => '0700003E',
           'F6'  => '0700003F',
           'F7'  => '07000040',
           'F8'  => '07000041',
           'F9'  => '07000042',
           'F10' => '07000043',
           'F11' => '07000044',
           'F12' => '07000045',

           'KP/' => '07000054',
           'KP*' => '07000055',
           'KP-' => '07000056',
           'KP+' => '07000057',
         'KP\\n' => '07000058',
           'KP1' => '07000059',
           'KP2' => '0700005A',
           'KP3' => '0700005C',
           'KP4' => '0700005C',
           'KP5' => '0700005D',
           'KP6' => '0700005E',
           'KP7' => '0700005F',
           'KP8' => '07000060',
           'KP9' => '07000061',
           'KP0' => '07000062',
         );


sub
harmony_char2hid($)
{
  my ($char) = @_;
Log 1, $char;

  my $ret;
  if( $char ge '1' && $char le '9' ) {
    $ret = sprintf( "070000%02X", 0x1E + ord($char) - ord('1') );
  } elsif( $char ge 'a' && $char le 'z' ) {
    $ret = sprintf( "070000%02X", 0x04 + ord($char) - ord('a') );
  } elsif( $char ge 'A' && $char le 'Z' ) {
    $ret = sprintf( "070200%02X", 0x04 + ord($char) - ord('A') );
  } elsif( defined( $keys{$char} ) ) {
    $ret = $keys{$char};
  }

  return $ret;
}

sub
harmony_updateActivity($$;$)
{
  my ($hash,$id,$modifier) = @_;
  $modifier = "" if( !$modifier );

  if( $hash->{currentActivityID} && $hash->{currentActivityID}  ne $id ) {
    my $id = $hash->{currentActivityID};
    $hash->{previousActivityID} = $id;

    my $previous = harmony_labelOfActivity($hash,$id,$id);
    readingsSingleUpdate( $hash, "previousActivity", $previous, 0 );
  }

  if( !$modifier && defined($modules{$hash->{TYPE}}{defptr}) ) {
    if( my $activity = harmony_activityOfId($hash, $id)) {
      foreach my $id (keys %{$activity->{fixit}}) {
        if( my $hash = $modules{$hash->{TYPE}}{defptr}{$id} ) {
          my $state = $activity->{fixit}->{$id}->{Power};
          $state = "Manual" if( !$state );
          readingsSingleUpdate( $hash, "power", lc($state), 1 );
        }
      }
    }
  }

  $hash->{currentActivityID} = $id;

  my $activity = harmony_labelOfActivity($hash,$id,$id);
  readingsSingleUpdate( $hash, "currentActivity", "$modifier$activity", 1 );

  delete $hash->{hidDevice} if( $id == -1 );
}

sub
harmony_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 1024*1024);

  if(!defined($ret) || $ret <= 0) {
    harmony_disconnect( $hash );

    InternalTimer(gettimeofday()+2, "harmony_connect", $hash, 0);
    return;
  }

  my $data = $hash->{helper}{PARTIAL};
  $data .= $buf;

  #FIXME: should use real xmpp/xml parser
  my @lines = split( "\n", $data );
  foreach my $line (@lines) {
    if( $line =~ m/^<(\w*)\s*([^>]*)?\/>(.*)?/ ) {
      Log3 $name, 5, "$name: tag: $1, attr: $2";

      $data = $3;

      if( $line eq "<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>" ) {
        $hash->{STATE} = "LoggedIn";
        $hash->{ConnectionState} = "LoggedIn";
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='connect.discoveryinfo?get'>format=json</oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='vnd.logitech.harmony/vnd.logitech.harmony.system?systeminfo' token=''></oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='vnd.logitech.connect/vnd.logitech.deviceinfo?get' token=''></oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='vnd.logitech.setup/vnd.logitech.account?getProvisionInfo' token=''></oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='vnd.logitech.connect/vnd.logitech.statedigest?get' token=''>format=json</oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='nd.logtech.setup/vnd.logitech.firmware?check' token=''>format=json</oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='proxy.resource?get' token=''>hetag= :uri=dynamite:://HomeAutomationService/Config/:encode=true</oa>");
        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='harmony.automation?getstate' token=''></oa>");

        #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='vnd.logitech.connect/vnd.logitech.pair'>name=1vm7ATw/tN6HXGpQcCs/A5MkuvI#iOS6.0.1#iPhone</oa>");
        harmony_sendEngineGet($hash, "config", "");

        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+50, "harmony_ping", $hash, 0);
      }

      $line = $3;
    }

    if( $line =~ m/^<(\w*)([^>]*)>(.*)<\/\1>(.*)?/ ) {
      Log3 $name, 5, "$name: tag: $1, attr: $2";
      #Log3 $name, 5, "  data: $3";

      $data = $4;

      my $tag = $1;
      my $attr = $2;
      my $content = $3;

      #if( $content =~ m/^<(\w*)([^>]*)>(.*)<\/\1>(.*)?/ ) {
      #  Log3 $name, 1, "$name: tag: $1, attr: $2";
      #  Log3 $name, 1, Dumper harmony_attr2hash($2);
      #}

      if( $content =~ m/<!\[CDATA\[(.*)\]\]>/ ) {
        my $cdata = $1;

        my $json;
        my $decoded;
        if( $cdata =~ m/^{.*}$/ ) {
          if( harmony_isFritzBox() ) {
            $json = decode_json($cdata);
          } else {
            $json = JSON->new->utf8(0)->decode($cdata);
          }
          $decoded = $json;

        } else {
          $decoded = harmony_CDATA2hash($cdata);

        }

        if( ($tag eq "iq" &&  $content =~ m/statedigest\?get'/)
            || ($tag eq "message" && $content =~ m/type="connect.stateDigest\?notify"/) ) {
          Log3 $name, 4, "$name: notify: $cdata";

          if( $decoded ) {
            if( defined($decoded->{syncStatus}) ) {
              harmony_sendEngineGet($hash, "config", "") if( $hash->{syncStatus} && !$decoded->{syncStatus} );

              $hash->{syncStatus} = $decoded->{syncStatus};
            }

            $hash->{activityStatus} = $decoded->{activityStatus} if( defined($decoded->{activityStatus}) );

            $hash->{hubSwVersion} = $decoded->{hubSwVersion} if( defined($decoded->{hubSwVersion}) );
            $hash->{hubUpdate} = $decoded->{hubUpdate} if( defined($decoded->{hubUpdate}) );

            my $modifier = "";
            $modifier = "starting " if( $hash->{activityStatus} == 1 );
            $modifier = "stopping " if( $hash->{activityStatus} == 3 );

            harmony_updateActivity($hash, $decoded->{activityId}, $modifier) if( defined($decoded->{activityId}) );

            if( defined($decoded->{sleepTimerId}) ) {
              if( $decoded->{sleepTimerId} == -1 ) {
                delete $hash->{sleeptimer};
              } else {
                harmony_sendEngineGet($hash, "gettimerinterval", "timerId=$decoded->{sleepTimerId}");
              }
            }
          }
        } elsif( $tag eq "message" ) {
          if( $content =~ m/type="harmony.engine\?startActivityFinished"/ ) {
            my $id = 0;
            my $error = 0;

            if( $cdata =~ m/activityId=([\d\-]*).*errorCode=(\d*).*errorString=(\w)*/ ) {
              $id = $1;
              $error = $2;
            }

            harmony_updateActivity($hash, $id);

          } else {
            Log3 $name, 2, "$name: unknown message: $content";

          }

        } elsif( $tag eq "iq" ) {
          if( $content =~ m/errorcode='(\d*)'.*errorstring='(.*)'/ && $1 != 100 && $1 != 200 ) {
            Log3 $name, 2, "$name: error ($1): $2";

          } elsif( $content =~ m/vnd.logitech.pair/ ) {
#Log 3, Dumper $decoded;

            if( !$hash->{identity} && $decoded->{identity} ) {
              $hash->{identity} = $decoded->{identity};
              harmony_connect($hash);

            } else {
              harmony_sendEngineGet($hash, "config", "");

            }

          } elsif( $content =~ m/\?startactivity/ ) {
            if( $cdata =~ m/done=(\d*):total=(\d*):deviceId=(\d*)/ ) {
              my $done = $1;
              my $total = $2;
              my $id = $3;

              my $label = harmony_labelOfDevice($hash,$id,$id);

              if( $done == $total ) {
                Log3 $name, 4, "$name: done starting/stopping device: $label";
              } elsif( $done == 1  ) {
                Log3 $name, 4, "$name: starting/stopping device: $label";
              } else {
                Log3 $name, 4, "$name: starting/stopping device ($done/$total): $label";
              }

            } else {
              Log3 $name, 3, "$name: unknown startactivity message: $content";
            }

          } elsif( $content =~ m/discoveryinfo\?get/ && $decoded ) {
            Log3 $name, 4, "$name: ". Dumper $decoded;

            $hash->{discoveryinfo} = $decoded;

            $hash->{current_fw_version} = $decoded->{current_fw_version} if( defined($decoded->{current_fw_version}) );

            harmony_sendEngineGet($hash, "config", "");

          } elsif( $content =~ m/engine\?gettimerinterval/ && $decoded ) {
            $hash->{sleeptimer} = FmtDateTime( gettimeofday() + $decoded->{interval} );

          } elsif( $content =~ m/\?config/ && $decoded ) {
            $hash->{config} = $decoded;
            Log3 $name, 3, "$name: new config ";
            #Log3 $name, 5, "$name: ". Dumper $json;

            #my $station = $hash->{config}->{content}->{contentImageHost};
            #$station =~ s/{stationId}/4faa0c3b7232c50c26001b86/;
            #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='proxy.resource?get' token=''>hetag= :uri=content:://1.0/user;$station:encode=true</oa>");

            #foreach my $device (sort { $a->{id} <=> $b->{id} } @{$hash->{config}->{device}}) {
            #  my $content = $hash->{config}->{content}->{contentDeviceHost};
            #  $content =~ s/{deviceProfileUri}/$device->{deviceProfileUri}/;
            #  harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='proxy.resource?get' token=''>hetag= :uri=content:://1.0/user;$content:encode=true</oa>");
            #  last;
            #}

            #harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='proxy.resource?get' token=''>hetag= :uri=content:://1.0/user;$hash->{config}->{content}->{householdUserProfileUri}:encode=true</oa>");

            harmony_sendIq($hash, "<oa xmlns='connect.logitech.com' mime='vnd.logitech.connect/vnd.logitech.statedigest?get' token=''>format=json</oa>");
            #harmony_sendEngineGet($hash, "getCurrentActivity", "");

          } elsif( $cdata =~ m/result=(.*)/ ) {
            my $result = $1;
            Log3 $name, 4, "$name: got result $1";

            if( $content =~ m/getCurrentActivity/ ) {
              harmony_updateActivity($hash, $result);

            } else {
              Log3 $name, 3, "$name: unknown result: $content";

            }

          } elsif( $content =~ m/mime='hid.report'/ ) {
            harmony_sendHID($hash) if( $hash->{hid} );

          } else {
            Log3 $name, 3, "$name: unknown iq: $content";
Log 3, Dumper $decoded;

Log 3, Dumper decode_json($decoded->{resource}) if( !$json && $decoded->{resource} && $decoded->{resource} =~ m/^{.*}$/ );

          }

        } else {
          Log3 $name, 3, "$name: unhandled tag: $line";

        }

      } elsif( $content =~ m/mime='hid.report'/ ) {
        harmony_sendHID($hash) if( $hash->{hid} );

      } elsif( $line =~ m/<iq id='ping-(\d+)' type='result'><\/iq>/ ) {
        Log3 $name, 5, "$name: got ping response $1";

      } elsif( $line ) {
        Log3 $name, 4, "$name: unknown (no cdata): $line";

      }
    } elsif( $line =~ m/^<\?xml.*id='([\w-]*).*error.*>/ ) {
      Log3 $name, 2, "$name: error: $1" if( $1 );
      Log3 $name, 4, "$name: $line";

      harmony_disconnect($hash);

    } elsif( $line =~ m/^<\?xml.*PLAIN.*>/ ) {

      my $identity = $hash->{identity}?$hash->{identity}:"guest";
      my $auth = encode_base64("\0$identity\0$identity",'');
      harmony_send($hash, "<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='PLAIN'>$auth</auth>");

      $data = "";

    } elsif( $line =~ m/^<.*>$/ ) {
      Log3 $name, 4, "$name: unknown: $line";

    } elsif( $line ) {
      Log3 $name, 5, "$name: $line";

    }
  }

  $hash->{helper}{PARTIAL} = $data;
#Log 3, "length: ". length($hash->{helper}{PARTIAL});
}

sub
harmony_disconnect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);
  $hash->{STATE} = "Disconnected";
  $hash->{ConnectionState} = "Disconnected";

  return if( !$hash->{CD} );
  Log3 $name, 2, "$name: disconnect";

  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});

  $hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
}

sub
harmony_connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( AttrVal($hash->{NAME}, "disable", 0) );

  harmony_disconnect($hash);

  Log3 $name, 4, "$name: connect";

  harmony_getLoginToken($hash);

  if( defined($hash->{helper}{UserAuthToken}) ) {
    my $timeout = $hash->{TIMEOUT} ? $hash->{TIMEOUT} : 3;
    my $conn = IO::Socket::INET->new(PeerAddr => "$hash->{ip}:5222", Timeout => $timeout);

    if( $conn ) {
      Log3 $name, 3, "$name: connected";
      $hash->{STATE} = "Connected";
      $hash->{ConnectionState} = "Connected";
      $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );

      $hash->{FD}    = $conn->fileno();
      $hash->{CD}    = $conn;         # sysread / close won't work on fileno
      $hash->{CONNECTS}++;
      $selectlist{$name} = $hash;

      $hash->{helper}{PARTIAL} = "";

      harmony_send($hash, "<stream:stream to='connect.logitech.com' xmlns:stream='http://etherx.jabber.org/streams' xmlns='jabber:client' xml:lang='en' version='1.0'>");

    } else {
      harmony_disconnect( $hash );

      InternalTimer(gettimeofday()+2, "harmony_connect", $hash, 0);
    }
  }
}

sub
harmony_send($$)
{
  my ($hash, $data) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: send: $data";

  syswrite $hash->{CD}, $data;
}
my $id = 0;
sub
harmony_sendIq($$;$)
{
  my ($hash, $xml, $type) = @_;
  $type = 'get' if ( !$type );

  ++$id;

  my $iq = "<iq type='$type' id='$id'>$xml</iq>";

  harmony_send($hash,$iq);
}
sub
harmony_sendEngineGet($$$)
{
  my ($hash, $endpoint, $payload) = @_;

  my $xml = "<oa xmlns='connect.logitech.com' mime='vnd.logitech.harmony/vnd.logitech.harmony.engine?$endpoint'>$payload</oa>";

  harmony_sendIq($hash,$xml);
}
sub
harmony_sendHID($;$)
{
  my ($hash, $code) = @_;

  if( !$code ) {
    return if( !$hash->{hid} );

    my $char = substr($hash->{hid}, 0, 1);
    $hash->{hid} = substr($hash->{hid}, 1);

    if( $char eq '\\' || ord($char) == 0xC3 ) {
      $char .= substr($hash->{hid}, 0, 1);
      $hash->{hid} = substr($hash->{hid}, 1);
    }

    $code = harmony_char2hid( $char );
  }

  my $xml = "<oa xmlns='connect.logitech.com' mime='hid.report' token=''>{'code':'$code'}</oa>";

  harmony_sendIq($hash,$xml);
}
sub
harmony_sendEngineRender($$$)
{
  my ($hash, $endpoint, $payload) = @_;

  my $xml = "<oa xmlns='connect.logitech.com' mime='vnd.logitech.harmony/vnd.logitech.harmony.engine?$endpoint' token=''>$payload</oa>";

  harmony_sendIq($hash,$xml, "render");
}

sub
harmony_ping($)
{
  my( $hash ) = @_;

  return if( $hash->{ConnectionState} eq "Disconnected" );

  ++$id;
  harmony_send($hash, "<iq type='get' id='ping-$id'><ping xmlns='urn:xmpp:ping'/></iq>");

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+50, "harmony_ping", $hash, 0);
}


sub
harmony_dispatch($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
  } elsif( $data ) {
    Log3 $name, 4, "$name: $data";

    if( $data !~ m/^{.*}$/ ) {
      Log3 $name, 2, "$name: invalid json detected: $data";
      return undef;
    }

    my $json;
    if( harmony_isFritzBox() ) {
      $json = decode_json($data);
    } else {
      $json = JSON->new->utf8(0)->decode($data);
    }

    if( $json->{error} ) {
      #$hash->{lastError} = $json->{error}{message};
    }

    if( $param->{type} eq 'token' ) {
      harmony_parseToken($hash,$json);

    }
  }
}

sub
harmony_autocreate($;$)
{
  my($hash, $param) = @_;
  my $name = $hash->{NAME};

  return if( !defined($hash->{config}) );

  my $id = $param;
  $id = harmony_idOfDevice($hash, $id) if( $id && $id !~ m/^([\d-])+$/ );
  return "unknown device $param" if( $param && !$id );

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
  }

  my $autocreated = 0;
  foreach my $device (@{$hash->{config}->{device}}) {
    next if( $id && $device->{id} != $id );

    if( defined($modules{$hash->{TYPE}}{defptr}{$device->{id}}) ) {
      Log3 $name, 4, "$name: device '$device->{id}' already defined";
      next;
    }

    my $devname = "harmony_". $device->{id};
    my $define = "$devname harmony DEVICE $device->{id}";

    Log3 $name, 3, "$name: create new device '$devname' for device '$device->{id}'";
    my $cmdret = CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$device->{id}': $cmdret";

    } else {
      $cmdret = CommandAttr(undef,"$devname alias $device->{label}") if( defined($device->{label}) );
      $cmdret = CommandAttr(undef,"$devname event-on-change-reading .*");
      $cmdret = CommandAttr(undef,"$devname room $hash->{TYPE}");
      $cmdret = CommandAttr(undef,"$devname stateFormat power");
      #$cmdret = CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub
harmony_parseToken($$)
{
  my($hash, $json) = @_;

  RemoveInternalTimer($hash);

  my $had_token = $hash->{helper}{UserAuthToken};

  #$hash->{helper}{AccountId} = $json->{GetUserAuthTokenResult}->{AccountId};
  $hash->{helper}{UserAuthToken} = $json->{GetUserAuthTokenResult}->{UserAuthToken};

  if( $json->{GetUserAuthTokenResult} ) {
    $hash->{STATE} = "GotToken";
    $hash->{ConnectionState} = "GotToken";

  } else {
    $hash->{STATE} = "Error" if( !$hash->{helper}{UserAuthToken} );
    $hash->{ConnectionState} = "Error" if( !$hash->{helper}{UserAuthToken} );

    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+60, "harmony_connect", $hash, 0);

  }
}

sub
harmony_data2string($)
{
  my ($data) = @_;

   return "" if( !defined($data) );

   return $data if( !ref($data) );
   return $data if( ref($data) eq "JSON::XS::Boolean" );
   return "[". join(',', @{$data}) ."]" if(ref($data) eq "ARRAY");

   return Dumper $data;
}
sub
harmony_GetPower($$)
{
  my ($hash, $activity) = @_;

  my $power = "";
  return $power if( !defined($activity->{fixit}) );

  foreach my $id (keys %{$activity->{fixit}}) {
    my $label = harmony_labelOfDevice($hash, $id);
    my $state = $activity->{fixit}->{$id}->{Power};
    $state = "Manual" if( !$state );

    $power .= "\n\t\t\t$label: $state";
  }

  return $power;
}
sub
harmony_hubOfDevice($)
{
  my ($id) = @_;

  foreach my $d (sort keys %defs) {
    next if( !defined($defs{$d}) );
    next if( $defs{$d}->{TYPE} ne "harmony" );
    next if( $defs{$d}->{id} );
    next if( !harmony_deviceOfId($defs{$d}, $id) );
    Log3 undef, 3, "harmony: found IODev $d for device $id" ;
    return $d;
  }
}
sub
harmony_Get($$@)
{
  my ($hash, $name, $cmd, $param) = @_;
  #$cmd = lc( $cmd );

  my $list = "";

  if( defined($hash->{id}) ) {
    if( !$hash->{hub} ) {
      $hash->{hub} = harmony_hubOfDevice($hash->{id});

      return "no IODev found for device $name ($hash->{id})" if( !$hash->{hub} );
    }

    if( $cmd eq "commands" || $cmd eq "deviceCommands" ) {
      $cmd = "deviceCommands";
      $param = $hash->{id};

      $hash = $defs{$hash->{hub}};

    } else {
      $list = "commands:noArg";
      return "Unknown argument $cmd, choose one of $list" if( defined($hash->{id}) );

    }

  }


  my $ret;
  if( $cmd eq "activities" ) {
    return "no activities found" if( !defined($hash->{config}) || !defined($hash->{config}->{activity}) );

    my $ret = "";
    foreach my $activity (sort { ($a->{activityOrder}||0) <=> ($b->{activityOrder}||0) } @{$hash->{config}->{activity}}) {
      next if( $activity->{label} eq "PowerOff" );
      $ret .= "\n" if( $ret );
      $ret .= sprintf( "%s\t%-24s", $activity->{id}, $activity->{label});
      $ret .= "\t". harmony_data2string($activity->{$param}) if( $param && defined($activity->{$param}) );

      if( $param eq "power" ) {
        my $power = harmony_GetPower($hash, $activity);
        $ret .= $power if( $power );
      }
    }
    #$ret = sprintf("%s\t\t%-24s\n", "ID", "LABEL"). $ret if( $ret );
    $ret .= "\n-1\t\tPowerOff";
    if( $param eq "power" ) {
      if( my $activity = harmony_activityOfId($hash, -1) ) {
        my $power = harmony_GetPower($hash, $activity);
        $ret .= $power if( $power );
      }
    }

    return $ret;

  } elsif( $cmd eq "devices" ) {
    return "no devices found" if( !defined($hash->{config}) || !defined($hash->{config}->{device}) );

    my $ret = "";
    foreach my $device (sort { $a->{id} <=> $b->{id} } @{$hash->{config}->{device}}) {
      $ret .= "\n" if( $ret );
      $ret .= sprintf( "%s\t%-20s\t%-20s\t%-15s\t%-15s", $device->{id}, $device->{label}, $device->{type}, $device->{manufacturer}, $device->{model});
      $ret .= "\t". harmony_data2string($device->{$param}) if( $param && defined($device->{$param}) );
    }
    #$ret = sprintf("%s\t\t%-20s\t%-20s\t%-15s\t%-15s\n", "ID", "LABEL", "TYPE", "MANUFACTURER", "MODEL"). $ret if( $ret );
    return $ret;

  } elsif( $cmd eq "commands" ) {
    return "no commands found" if( !defined($hash->{config}) || !defined($hash->{config}->{activity}) );

    my $id = $param;
    $id = harmony_idOfActivity($hash, $id) if( $id && $id !~ m/^([\d-])+$/ );
    return "unknown activity $param" if( $param && !$id );

    my $ret = "";

    foreach my $activity (sort { ($a->{activityOrder}||0) <=> ($b->{activityOrder}||0) } @{$hash->{config}->{activity}}) {
      next if( $activity->{id} == -1 );
      next if( $id && $activity->{id} != $id );
      $ret .= "$activity->{label}\n";
      #$ret .= "$device->{label}\t$device->{manufacturer}\t$device->{model}\n";
      foreach my $group (@{$activity->{controlGroup}}) {
        $ret .= "\t$group->{name}\n";
        foreach my $function (@{$group->{function}}) {
          my $action;
          if( harmony_isFritzBox() ) {
            $action = decode_json($function->{action});
          } else {
            $action = JSON->new->utf8(0)->decode($function->{action});
          }

          $ret .= sprintf( "\t\t%-20s\t%s (%s)\n", $function->{name}, $function->{label}, harmony_labelOfDevice($hash, $action->{deviceId}, $action->{deviceId}) );
        }
      }
    }

    return $ret;

  } elsif( $cmd eq "deviceCommands" ) {
    return "no commands found" if( !defined($hash->{config}) || !defined($hash->{config}->{device}) );

    my $id = $param;
    $id = harmony_idOfDevice($hash, $id) if( $id && $id !~ m/^([\d-])+$/ );
    return "unknown device $param" if( $param && !$id );

    my $ret = "";

    foreach my $device (sort { $a->{id} <=> $b->{id} } @{$hash->{config}->{device}}) {
      next if( $id && $device->{id} != $id );
      $ret .= "$device->{label}\t$device->{manufacturer}\t$device->{model}\n";
      foreach my $group (@{$device->{controlGroup}}) {
        $ret .= "\t$group->{name}\n";
        foreach my $function (@{$group->{function}}) {
          $ret .= sprintf( "\t\t%-20s\t%s\n", $function->{name}, $function->{label} );
        }
      }
    }

    return "no commands found" if( !$ret );
    return $ret;

  } elsif( $cmd eq "activityDetail"
           || $cmd eq "deviceDetail" ) {
    return undef if( !defined($hash->{config}) );

    $param = harmony_idOfActivity($hash, $param) if( $param && $param !~ m/^([\d-])+$/ && $cmd eq "activityDetail" );
    $param = harmony_idOfDevice($hash, $param) if( $param && $param !~ m/^([\d-])+$/ && $cmd eq "deviceDetail" );

    my $var;
    $var = $hash->{config}->{activity} if( $cmd eq "activityDetail"  );
    $var = $hash->{config}->{device}   if( $cmd eq "deviceDetail"  );
    if( $param ) {
      foreach my $v (@{$var}) {
        if( $v->{id} eq $param ) {
          $var = $v;
          last;
        }
      }
    }

    return Dumper $var;

  } elsif( $cmd eq "configDetail" ) {

    return undef if( !defined($hash->{config}) );

    return Dumper $hash->{config};

  } elsif( $cmd eq "currentActivity" ) {
      return "unknown activity" if( !$hash->{currentActivityID} );

      my $activity = harmony_activityOfId($hash, $hash->{currentActivityID});
      return "unknown activity" if( !$activity );

      return $activity->{label};
  }

  $list .= "activities:noArg devices:noArg";

  if( $hash->{config} ) {
    return undef if( !defined($hash->{config}) );

    my $activities;
    foreach my $activity (sort { ($a->{activityOrder}||0) <=> ($b->{activityOrder}||0) } @{$hash->{config}->{activity}}) {
      next if( $activity->{label} eq "PowerOff" );
      $activities .= "," if( $activities );
      $activities .= $activity->{label};
     }
    if( $activities ) {
      $activities =~ s/ /./g;

      $list .= " commands:,$activities";
    }

    my $devices;
    foreach my $device (sort { $a->{id} <=> $b->{id} } @{$hash->{config}->{device}}) {
      $devices .= "," if( $devices );
      $devices .= $device->{label};
    }
    if( $devices ) {
      $devices =~ s/ /./g;

      $list .= " deviceCommands:,$devices";
    }
  }

  $list .= " currentActivity:noArg";

  return "Unknown argument $cmd, choose one of $list";
}

sub
harmony_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
      $attrVal = 1;
      harmony_disconnect($hash);

    } else {
      $attr{$name}{$attrName} = 0;
      harmony_connect($hash);

    }
  }

  if( $cmd eq "set" ) {
    if( !defined($orig) || $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=begin html

<a name="harmony"></a>
<h3>harmony</h3>
<ul>
  Defines a device to integrate a Logitech Harmony Hub based remote control into fhem.<br><br>

  It is possible to: start and stop activities, send ir commands to devices, send keyboard input by bluetooth and
  smart keyboard usb dongles.<br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
    <li>currently username and password are not used and should be omitted.</li>
    <li>activity and device names can be given as id or name. names can be given as a regex and spaces in names musst be replaced by a single '.' (dot).</li>
  </ul><br>

  <a name="harmony_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; harmony [&lt;username&gt; &lt;password&gt;] &lt;ip&gt;</code><br>
    <br>

    Defines a harmony device.<br><br>

    Examples:
    <ul>
      <code>define hub harmony 10.0.1.4</code><br>
    </ul>
  </ul><br>

  <a name="harmony_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>currentActivity<br>
      the name of the currently selected activity.</li>
    <li>previousActivity<br>
      the name of the previous selected activity. does not trigger an event.</li>
  </ul><br>

  <a name="harmony_Internals"></a>
  <b>Internals</b>
  <ul>
    <li>currentActivityID<br>
      the id of the currently selected activity.</li>
    <li>previousActivityID<br>
      the id of the previous selected activity.</li>
    <li>sleeptimer<br>
      timeout for sleeptimer if any is set.</li>
  </ul><br>


  <a name="harmony_Set"></a>
  <b>Set</b>
  <ul>
    <li>activity &lt;id&gt|&ltname&gt;<br>
      switch to this activity</li>
    <li>command [&lt;id&gt|&ltname&gt;] &lt;command&gt;<br>
      send the given ir command for the current activity or for the given device.</li>
    <li>getConfig<br>
      request the configuration from the hub</li>
    <li>getCurrentActivity<br>
      request the current activity from the hub</li>
    <li>off<br>
      switch current activity off</li>
    <li>reconnect<br>
      close connection to the hub and reconnect</li>
    <li>sleeptimer [&lt;timeout&gt;]<br>
      &lt;timeout&gt; -> timeout in minutes<br>
      -1 -> timer off<br>
      default -> 60 minutes</li>
    <li>sync<br>
      syncs the hub to the myHarmony config</li>
    <li>hidDevice [&lt;id&gt|&ltname&gt;]<br>
      sets the target device for keyboard commands, if no device is given -> set the target to the
      default device for the current activity.</li>
    <li>text &lt;text&gt;<br>
      sends &lt;text&gt; by bluetooth/smart keaboard dongle. a-z ,A-Z ,0-9, \n, \e, \t and space are currently possible</li>
    <li>cursor &lt;direction&gt;<br>
      moves the cursor by bluetooth/smart keaboard dongle. &lt;direction&gt; can be one of: up, down, left, right, pageUp, pageDown, home, end.</li>
    <li>special &lt;key&gt;<br>
      sends special key by bluetooth/smart keaboard dongle. &lt;key&gt; can be one of: previousTrack, nextTrack, stop, playPause, volumeUp, volumeDown, mute.</li>
    <li>autocreate [&lt;id&gt|&ltname&gt;]<br>
      creates a fhem device for a single/all device(s) in the harmony hub. if activities are startet the state
      of these devices will be updatet with the power state defined in these activites.</li>
  </ul>
  The command, hidDevice, text, cursor and special commmands are also available for the autocreated devices. The &lt;id&gt|&ltname&gt; paramter hast to be omitted.<br><br>

  <a name="harmony_Get"></a>
  <b>Get</b>
  <ul>
    <li>activites [&lt;param&gt;]<br>
      lists all activities<br>
      parm = power -> list power state for each device</li>
    <li>devices [&lt;param&gt;]<br>
      lists all devices</li>
    <li>commands [&lt;id&gt;|&ltname&gt;]<br>
      lists the commands for the specified activity or for all activities</li>
    <li>deviceCommands [&lt;id&gt;|&ltname&gt;]<br>
      lists the commands for the specified device or for all devices</li>
    <li>activityDetail [&lt;id&gt;|&ltname&gt;]</li>
    <li>deviceDetail [&lt;id&gt;|&ltname&gt;]</li>
    <li>configDetail</li>
    <li>currentActivity<br>
      returns the current activity name</li>
  </ul>
  The commands commmand is also available for the autocreated devices. The &lt;id&gt|&ltname&gt; paramter hast to be omitted.<br><br>


  <a name="harmony_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>disable<br>
      1 -> disconnect from the hub</li>
  </ul>
</ul>

=end html
=cut

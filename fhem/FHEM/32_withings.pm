
# $Id$

package main;

use strict;
use warnings;

use Encode qw(encode_utf8);
use JSON;
use LWP::Simple;
use HTTP::Request;
use HTTP::Cookies;

use Digest::MD5 qw(md5 md5_hex md5_base64);

use POSIX qw( strftime );

my %device_types = (  0 => "User related",
                      1 => "Body scale",
                      4 => "Blood pressure monitor",
                     16 => "Withings Pulse", );

my %device_models = (  1 => { 1 => "Smart scale", 4 => "Body analyzer", }, );

my %measure_types = (  1 => { name => "Weight (kg)", reading => "weight", },
                       4 => { name => "Height (meter)", reading => "height", },
                       5 => { name => "Fat Free Mass (kg)", reading => "fatFreeMass", },
                       6 => { name => "Fat Ratio (%)", reading => "fatRatio", },
                       8 => { name => "Fat Mass Weight (kg)", reading => "fatMassWeight", },
                       9 => { name => "Diastolic Blood Pressure (mmHg)", reading => "diastolicBloodPressure", },
                      10 => { name => "Systolic Blood Pressure (mmHg)", reading => "systolicBloodPressure", },
                      11 => { name => "Heart Pulse (bpm)", reading => "heartPulse", },
                      12 => { name => "Temperature (&deg;C)", reading => "temperature", },
                      35 => { name => "CO2 (ppm)", reading => "co2", }, );

sub
withings_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "withings_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "withings_Notify";
  $hash->{UndefFn}  = "withings_Undefine";
  #$hash->{SetFn}    = "withings_Set";
  $hash->{GetFn}    = "withings_Get";
  $hash->{AttrFn}   = "withings_Attr";
  $hash->{AttrList} = "IODev ".
                      "debug:1 ".
                      "disable:1 ".
                      "interval ".
                      "logfile ".
                      "nossl:1 ";
  $hash->{AttrList} .= $readingFnAttributes;
}

#####################################

sub
withings_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $subtype;
  my $name = $a[0];
  if( @a == 3 ) {
    $subtype = "DEVICE";

    my $device = $a[2];

    $hash->{Device} = $device;

    $hash->{INTERVAL} = 3600;

    my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

  } elsif( @a == 4 && $a[2] =~ m/\d+/ && $a[3] =~ m/[\da-f]+/  ) {
    $subtype = "USER";

    my $user = $a[2];
    my $key = $a[3];

    $hash->{User} = $user;
    $hash->{Key} = $key;

    $hash->{INTERVAL} = 3600;

    my $d = $modules{$hash->{TYPE}}{defptr}{"U$user"};
    return "device $user already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"U$user"} = $hash;

  } elsif( @a == 4  || ($a[2] eq "ACCOUNT" && @a == 5 ) ) {
    $subtype = "ACCOUNT";

    my $login = $a[@a-2];
    my $password = $a[@a-1];

    $hash->{Clients} = ":withings:";

    $hash->{Login} = $login;
    $hash->{Password} = $password;
  } else {
    return "Usage: define <name> withings device\
       define <name> withings userid publickey\
       define <name> withings [ACCOUNT] login password"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized";

  if( $init_done ) {
    withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
    withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  }

  return undef;
}

sub
withings_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  withings_initUser($hash) if( $hash->{SUBTYPE} eq "USER" );
  withings_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  withings_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
}

sub
withings_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete( $modules{$hash->{TYPE}}{defptr}{"U$hash->{User}"} ) if( $hash->{SUBTYPE} eq "USER" );
  delete( $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );

  return undef;
}

sub
withings_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";
  return "Unknown argument $cmd, choose one of $list";
}

sub
withings_getToken($)
{
  my ($hash) = @_;

  my $URL = 'http://auth.withings.com/index/service/once?action=get';
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  my $json = JSON->new->utf8(0)->decode($response->content);
  my $once = $json->{body}{once};

  $hash->{Token} = $once;

  my $hashstring = $hash->{Login}.':'.md5_hex($hash->{Password}).':'.$once;

  $hash->{Hash} = md5_hex($hashstring);
}

sub
withings_getSessionKey($)
{
  my ($hash) = @_;

  return if( $hash->{SessionTimestamp} && gettimeofday() - $hash->{SessionTimestamp} < 300 );

  withings_getToken($hash);

  my $URL='http://auth.withings.com/en/';
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $response = $agent->post($URL, [email => $hash->{Login}, password => $hash->{Password}, rememberme => 'on', hash => $hash->{Hash}, once => $hash->{Token}, passClear => $hash->{Password}]);

  my $authcookies=$response->header('Set-Cookie');
  $authcookies =~ /session_key=([\s\S]+?);/;

  $hash->{SessionKey} = $1;
  $hash->{SessionTimestamp} = (gettimeofday())[0];

  $hash->{STATE} = "Connected" if( $hash->{SessionKey} );
  $hash->{STATE} = "Error" if( !$hash->{SessionKey} );

  if( !$hash->{AccountID} || length($hash->{AccountID} < 2 ) ) {
    my $URL = 'http://healthmate.withings.com/index/service/account?applitype=20&action=get&sessionid='.$hash->{SessionKey};
    my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
    my $header = HTTP::Request->new(GET => $URL);
    my $request = HTTP::Request->new('GET', $URL, $header);
    my $response = $agent->request($request);

    my $json = JSON->new->utf8(0)->decode($response->content);
    foreach my $account (@{$json->{body}{account}}) {
        next if( !defined($account->{id}) );
        $hash->{AccountID} = $account->{id} if($account->{email} eq $hash->{Login});
    }
  }
}
sub
withings_connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  withings_getSessionKey( $hash );

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
  }

  my $autocreated = 0;

  my $users = withings_getUsers($hash);
  foreach my $user (@{$users}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"U$user->{id}"}) ) {
      Log3 $name, 4, "$name: user '$user->{id}' already defined";
      next;
    }

    my $id = $user->{id};
    my $devname = "withings_U". $id;
    my $define= "$devname withings $id $user->{publickey}";

    Log3 $name, 3, "$name: create new device '$devname' for user '$id'";

    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$user->{shortname});
      $cmdret= CommandAttr(undef,"$devname room withings");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  my $devices = withings_getDevices($hash);
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{deviceid}"}) ) {
      Log3 $name, 4, "$name: device '$device->{deviceid}' already defined";
      next;
    }

    my $detail = withings_getDeviceDetail( $hash, $device->{deviceid} );

    my $id = $detail->{id};
    my $devname = "withings_D". $id;
    my $define= "$devname withings $id";

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$device_types{$detail->{type}}) if( defined($device_types{$detail->{type}}) );
      $cmdret= CommandAttr(undef,"$devname room withings");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );
}
sub
withings_initDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $device = withings_getDeviceDetail( $hash, $hash->{Device} );

  $hash->{DeviceType} = "UNKNOWN";

  $hash->{sn} = $device->{sn};
  $hash->{fw} = $device->{fw};
  $hash->{DeviceType} = $device->{type};
  $hash->{DeviceType} = $device_types{$device->{type}} if( defined($device_types{$device->{type}}) );
  $hash->{Model} = $device->{model};
  $hash->{Model} = $device_models{$device->{type}}->{$device->{model}}
                   if( defined($device_models{$device->{type}}) && defined($device_models{$device->{type}}->{$device->{model}}) );

  if( !defined( $attr{$name}{stateFormat} ) ) {
    $attr{$name}{stateFormat} = "batteryLevel %"; 

    $attr{$name}{stateFormat} = "co2 ppm" if( $device->{type} == 1 && $device->{model} == 4 ); 
  }

  withings_poll($hash);
}

sub
withings_initUser($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $user = withings_getUserDetail( $hash, $hash->{User} );

  $hash->{shortName} = $user->{shortname};
  $hash->{gender} = ($user->{gender}==0)?"male":"female";
  $hash->{userName} = $user->{firstname} ." ". $user->{lastname};
  $hash->{birthdate} = strftime("%Y-%m-%d", localtime($user->{birthdate}));

  $attr{$name}{stateFormat} = "weight kg" if( !defined( $attr{$name}{stateFormat} ) );

  withings_poll($hash);
}

sub
withings_getUsers($)
{
  my ($hash) = @_;

  withings_getSessionKey($hash);

  my $URL = 'http://healthmate.withings.com/index/service/account?action=getuserslist&sessionid='.$hash->{SessionKey};
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  my $json = JSON->new->utf8(0)->decode($response->content);

  my @users = ();
  foreach my $user (@{$json->{body}{users}}) {
    next if( !defined($user->{id}) );

    push( @users, $user );
  }

  return \@users;
}
sub
withings_getDevices($)
{
  my ($hash) = @_;

  withings_getSessionKey($hash);

  my $URL = 'http://healthmate.withings.com/index/service/association?action=getbyaccountid&sessionid='.$hash->{SessionKey}.'&accountid='.$hash->{AccountID};
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  my $json = JSON->new->utf8(0)->decode($response->content);

  my @devices = ();
  foreach my $association (@{$json->{body}{associations}}) {
    next if( !defined($association->{deviceid}) );

    push( @devices, $association );
  }

  return \@devices;
}
sub
withings_getDeviceDetail($$)
{
  my ($hash,$id) = @_;

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  withings_getSessionKey( $hash );

  my $URL = 'http://healthmate.withings.com/index/service/device?action=getproperties&sessionid='.$hash->{SessionKey}.'&deviceid='.$id;
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  my $json = JSON->new->utf8(0)->decode($response->content);

  return $json->{body};
}
sub
withings_getDeviceReadings($$)
{
  my ($hash,$id) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  withings_getSessionKey( $hash );

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );

  my $URL = 'http://healthmate.withings.com/index/service/v2/measure?action=getmeashf&meastype=12%2C35&sessionid='.$hash->{SessionKey}.'&deviceid='.$id;
  $URL .= "&lastupdate=$lastupdate" if( $lastupdate );
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  my $json = JSON->new->utf8(0)->decode($response->content);

  if(open(FH, "</tmp/getmeashf.txt")) {
    my $content;
    while (my $line = <FH>) {
      chomp $line;
      next if($line =~ m/^#.*$/);
      $content .= $line;
    }
    close(FH);

    $json = JSON->new->utf8(0)->decode($content);
  }

  return $json;
}
sub
withings_getUserDetail($$)
{
  my ($hash,$id) = @_;

  return undef if( $hash->{SUBTYPE} ne "USER" );

  my $URL = "http://wbsapi.withings.net/user?action=getbyuserid&userid=$hash->{User}&publickey=$hash->{Key}";
  my $agent = LWP::UserAgent->new(env_proxy => 1,keep_alive => 1, timeout => 30);
  my $header = HTTP::Request->new(GET => $URL);
  my $request = HTTP::Request->new('GET', $URL, $header);
  my $response = $agent->request($request);

  my $json = JSON->new->utf8(0)->decode($response->content);

  return $json->{body}{users}[0];
}

sub
withings_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);

  if( $hash->{SUBTYPE} eq "DEVICE" ) {
    withings_pollDevice($hash);
  } elsif( $hash->{SUBTYPE} eq "USER" ) {
    withings_pollUser($hash);
  }

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "withings_poll", $hash, 1);
}

sub
withings_pollDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $json = withings_getDeviceReadings( $hash, $hash->{Device} );
  if( $json ) {
    $hash->{status} = $json->{status};
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @readings = ();
    if( $hash->{status} == 0 ) {
      foreach my $series ( @{$json->{body}{series}}) {
        my $reading = $measure_types{$series->{type}}->{reading};
        if( !defined($reading) ) {
          Log3 $name, 3, "$name: unknown measure type: $series->{type}";
          next;
        }

        foreach my $measure (@{$series->{data}}) {
          next if( $measure->{date} < $lastupdate );

          my $value = $measure->{value};

          push(@readings, [$measure->{date}, $reading, $value]);
        }
      }

      if( @readings ) {
        readingsBeginUpdate($hash);
        my $i = 0;
        foreach my $reading (sort { $a->[0] <=> $b->[0] } @readings) {
          $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
          $hash->{CHANGETIME}[$i++] = FmtDateTime($reading->[0]);
          readingsBulkUpdate( $hash, $reading->[1], $reading->[2], 1 );
        }

        my ($seconds) = gettimeofday();
        $hash->{LAST_POLL} = FmtDateTime( $seconds );

        readingsBulkUpdate( $hash, ".lastupdate", $seconds, 0 );

        readingsEndUpdate($hash,1);

        delete $hash->{CHANGETIME};
      }
    }
  }


  readingsBeginUpdate($hash);

  my $detail = withings_getDeviceDetail( $hash, $hash->{Device} );
  if( defined($detail->{batterylvl}) ) {
    readingsBulkUpdate( $hash, "batteryLevel", $detail->{batterylvl}, 1 );
    readingsBulkUpdate( $hash, "battery", ($detail->{batterylvl}>20?"ok":"low"), 1 );
  }
  readingsBulkUpdate( $hash, "lastWeighinDate", FmtDateTime($detail->{lastweighindate}), 1 ) if( defined($detail->{lastweighindate}) );

  readingsEndUpdate($hash,1);
}

sub
withings_pollUser($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );

  my $url = "http://wbsapi.withings.net/measure?action=getmeas";
  $url .= "&userid=$hash->{User}&publickey=$hash->{Key}";
  $url .= "&lastupdate=$lastupdate" if( $lastupdate );
  my $ret = get($url);
  my $json = JSON->new->utf8(0)->decode($ret);

  $hash->{status} = $json->{status};
  if( $hash->{status} == 0 ) {
    my $i = 0;
    readingsBeginUpdate($hash);
    foreach my $measuregrp ( sort { $a->{date} <=> $b->{date} } @{$json->{body}{measuregrps}}) {
      foreach my $measure (@{$measuregrp->{measures}}) {
        my $reading = $measure_types{$measure->{type}}->{reading};
        if( !defined($reading) ) {
          Log3 $name, 3, "$name: unknown measure type: $measure->{type}";
          next;
        }

        my $value = $measure->{value} * 10 ** $measure->{unit};

        $hash->{".updateTimestamp"} = FmtDateTime($measuregrp->{date});
        $hash->{CHANGETIME}[$i++] = FmtDateTime($measuregrp->{date});
        readingsBulkUpdate( $hash, $reading, $value, 1 );
      }
    }

   my ($seconds) = gettimeofday();
   $hash->{LAST_POLL} = FmtDateTime( $seconds );

   readingsBulkUpdate( $hash, ".lastupdate", $seconds, 0 );

   readingsEndUpdate($hash,1);

   delete $hash->{CHANGETIME};
  }
}

sub
withings_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list;
  if( $hash->{SUBTYPE} eq "USER" ) {
    $list = "update:noArg updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      $cmd = "update";
      CommandDeleteReading( undef, "$name .*" );
    }

    if( $cmd eq "update" ) {
      withings_poll($hash);
      return undef;
    }
  } elsif( $hash->{SUBTYPE} eq "DEVICE" ) {
    $list = "update:noArg updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      $cmd = "update";
      CommandDeleteReading( undef, "$name .*" );
    }

    if( $cmd eq "update" ) {
      withings_poll($hash);
      return undef;
    }
  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "users:noArg devices:noArg";

    if( $cmd eq "users" ) {
      my $users = withings_getUsers($hash);
      my $ret;
      foreach my $user (@{$users}) {
        $ret .= "$user->{id}\t\[$user->{shortname}\]\t$user->{publickey}\t$user->{firstname} $user->{lastname}\n";
      }

      $ret = "id\tshort\tpublickey\t\tname\n" . $ret if( $ret );;
      $ret = "no users found" if( !$ret );
      return $ret;
    } elsif( $cmd eq "devices" ) {
      my $devices = withings_getDevices($hash);
      my $ret;
      foreach my $device (@{$devices}) {
       my $detail = withings_getDeviceDetail($hash,$device->{deviceid});
        $ret .= "$detail->{id}\t$device_types{$detail->{type}}\t$detail->{batterylvl}\t$detail->{sn}\n";
      }

      $ret = "id\ttype\t\tbattery\tSN\n" . $ret if( $ret );;
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
withings_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 3600 if($attrName eq "interval" && $attrVal < 3600 && $attrVal != 0);

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    $hash->{INTERVAL} = 3600 if( !$attrVal );
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
      withings_poll($hash);
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}


1;

=pod
=begin html

<a name="withings"></a>
<h3>withings</h3>
<ul>
  xxx<br><br>

  Notes:
  <ul>
    <li>JSON, LWP::Simple and Digest::MD5 have to be installed on the FHEM host.</li>
  </ul><br>

  <a name="withings_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; withings &lt;device&gt;</code><br>
    <code>define &lt;name&gt; withings &lt;userid&gt; &lt;publickey&gt;</code><br>
    <code>define &lt;name&gt; withings [ACCOUNT] &lt;login&gt; &lt;password&gt;</code><br>
    <br>

    Defines a withings device.<br><br>
    If a withing device of the account type is created all fhem devices for users and devices are automaticaly created.
    <br>

    Examples:
    <ul>
      <code>define withings withings abc@test.com myPassword</code><br>
      <code>define withings withings 642123 2a42f132b9312311</code><br>
    </ul>
  </ul><br>

  <a name="withings_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>weight</li>
    <li>height</li>
    <li>fatFreeMass</li>
    <li>fatRatio</li>
    <li>fatMass</li>
    <li>diastolicBloodPressure</li>
    <li>systolicBloodPressure</li>
    <li>heartPulse</li>
    <br>
    <li>co2</li>
    <li>battery</li>
    <li>batteryLevel</li>
  </ul><br>

  <a name="withings_Get"></a>
  <b>Get</b>
  <ul>
    <li>update<br>
      trigger an update</li>
  </ul><br>

  <a name="withings_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds used to check for new values.</li>
    <li>disable<br>
      1 -> stop polling</li>
  </ul>
</ul>

=end html
=cut

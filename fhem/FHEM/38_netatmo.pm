
# $Id$

package main;

use strict;
use warnings;

use Encode qw(encode_utf8);
use JSON;

use HttpUtils;

sub
netatmo_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "netatmo_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "netatmo_Notify";
  $hash->{UndefFn}  = "netatmo_Undefine";
  #$hash->{SetFn}    = "netatmo_Set";
  $hash->{GetFn}    = "netatmo_Get";
  $hash->{AttrFn}   = "netatmo_Attr";
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
netatmo_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  my $subtype;
  my $name = $a[0];
  if( @a == 3 ) {
    $subtype = "DEVICE";

    my $device = $a[2];

    $hash->{Device} = $device;

    $hash->{INTERVAL} = 60*5;

    my $d = $modules{$hash->{TYPE}}{defptr}{"D$device"};
    return "device $device already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"D$device"} = $hash;

  } elsif( ($a[2] eq "MODULE" && @a == 5 ) ) {
    $subtype = "MODULE";

    my $device = $a[@a-2];
    my $module = $a[@a-1];

    $hash->{Device} = $device;
    $hash->{Module} = $module;

    $hash->{INTERVAL} = 60*5;

    my $d = $modules{$hash->{TYPE}}{defptr}{"M$module"};
    return "module $module already defined as $d->{NAME}" if( defined($d) && $d->{NAME} ne $name );

    $modules{$hash->{TYPE}}{defptr}{"M$module"} = $hash;

  } elsif( @a == 6  || ($a[2] eq "ACCOUNT" && @a == 7 ) ) {
    $subtype = "ACCOUNT";

    my $username = $a[@a-4];
    my $password = $a[@a-3];
    my $client_id = $a[@a-2];
    my $client_secret = $a[@a-1];

    $hash->{Clients} = ":netatmo:";

    $hash->{username} = $username;
    $hash->{password} = $password;
    $hash->{client_id} = $client_id;
    $hash->{client_secret} = $client_secret;
  } else {
    return "Usage: define <name> netatmo device\
       define <name> netatmo userid publickey\
       define <name> netatmo [ACCOUNT] username password"  if(@a < 3 || @a > 5);
  }

  $hash->{NAME} = $name;
  $hash->{SUBTYPE} = $subtype;

  $hash->{STATE} = "Initialized";

  if( $init_done ) {
    netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
    netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
  }

  return undef;
}

sub
netatmo_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  netatmo_connect($hash) if( $hash->{SUBTYPE} eq "ACCOUNT" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "DEVICE" );
  netatmo_initDevice($hash) if( $hash->{SUBTYPE} eq "MODULE" );
}

sub
netatmo_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete( $modules{$hash->{TYPE}}{defptr}{"D$hash->{Device}"} ) if( $hash->{SUBTYPE} eq "DEVICE" );
  delete( $modules{$hash->{TYPE}}{defptr}{"M$hash->{Module}"} ) if( $hash->{SUBTYPE} eq "MODULE" );

  return undef;
}

sub
netatmo_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";
  return "Unknown argument $cmd, choose one of $list";
}

sub
netatmo_getToken($)
{
  my ($hash) = @_;

  my($err,$data) = HttpUtils_BlockingGet({
    url => 'https://api.netatmo.net/oauth2/token',
    timeout => 10,
    noshutdown => 1,
    data => {grant_type => 'password', client_id => $hash->{client_id},  client_secret=> $hash->{client_secret}, username => $hash->{username}, password => $hash->{password}},
  });

  netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
}

sub
netatmo_refreshToken($;$)
{
  my ($hash,$nonblocking) = @_;

  if( !$hash->{access_token} ) {
    netatmo_getToken($hash);
    return undef;
  } elsif( !$nonblocking && defined($hash->{expires_at}) ) {
    my ($seconds) = gettimeofday();
    return undef if( $seconds < $hash->{expires_at} - 300 );
  }

  if( $nonblocking ) {
    HttpUtils_NonblockingGet({
      url => 'https://api.netatmo.net/oauth2/token',
      timeout => 10,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{client_id},  client_secret=> $hash->{client_secret}, refresh_token => $hash->{refresh_token}},
        hash => $hash,
        type => 'token',
        callback => \&netatmo_dispatch,
    });
  } else {
    my($err,$data) = HttpUtils_BlockingGet({
      url => 'https://api.netatmo.net/oauth2/token',
      timeout => 10,
      noshutdown => 1,
      data => {grant_type => 'refresh_token', client_id => $hash->{client_id},  client_secret=> $hash->{client_secret}, refresh_token => $hash->{refresh_token}},
    });

    netatmo_dispatch( {hash=>$hash,type=>'token'},$err,$data );
  }
}
sub
netatmo_refreshTokenTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "$name: refreshing token";

  netatmo_refreshToken($hash, 1);
}

sub
netatmo_connect($)
{
  my ($hash) = @_;

  netatmo_getToken($hash);
}
sub
netatmo_initDevice($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  my $device;
  if( $hash->{Module} ) {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Module} );
  } else {
    $device = netatmo_getDeviceDetail( $hash, $hash->{Device} );
  }

  $hash->{stationName} = $device->{station_name} if( $device->{station_name} );

  $hash->{model} = $device->{type};
  $hash->{firmware} = $device->{firmware};
  if( $device->{place} ) {
    $hash->{country} = $device->{place}{country};
    $hash->{bssid} = $device->{place}{bssid};
    $hash->{altitude} = $device->{place}{altitude};
    $hash->{location} = $device->{place}{location}[0] .",". $device->{place}{location}[1];
  }

  my $state_format;
  if( $device->{data_type} ) {
    delete($hash->{dataTypes});
    delete($hash->{helper}{dataTypes});

    my @reading_names = ();
    foreach my $type (@{$device->{data_type}}) {
      $hash->{dataTypes} = "" if ( !defined($hash->{dataTypes}) );
      $hash->{dataTypes} .= "," if ( $hash->{dataTypes} );
      $hash->{dataTypes} .= $type;

      push @reading_names, lc($type);

      if( $type eq "Temperature" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "T: temperature";
      } elsif( $type eq "Humidity" ) {
        $state_format .= " " if( $state_format );
        $state_format .= "H: humidity";
      }
    }

    $hash->{helper}{readingNames} = \@reading_names;
  }
  $attr{$name}{stateFormat} = $state_format if( !defined( $attr{$name}{stateFormat} ) );

  netatmo_poll($hash);
}

sub
netatmo_getDevices($;$)
{
  my ($hash,$blocking) = @_;

  netatmo_refreshToken($hash);

  if( $blocking ) {
    my($err,$data) = HttpUtils_BlockingGet({
      url => 'http://api.netatmo.net/api/devicelist',
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, scope => 'read_station' },
    });

    netatmo_dispatch( {hash=>$hash,type=>'devicelist'},$err,$data );

    return $hash->{helper}{devices};
  } else {
    HttpUtils_NonblockingGet({
      url => 'http://api.netatmo.net/api/devicelist',
      noshutdown => 1,
      data => { access_token => $hash->{access_token}, scope => 'read_station', },
      hash => $hash,
      type => 'devicelist',
      callback => \&netatmo_dispatch,
    });
  }
}
sub
netatmo_getDeviceDetail($$)
{
  my ($hash,$id) = @_;

  $hash = $hash->{IODev} if( defined($hash->{IODev}) );

  netatmo_getDevices($hash,1) if( !$hash->{helper}{devices} );

  foreach my $device (@{$hash->{helper}{devices}}) {
    return $device if( $device->{_id} eq $id );
  }

  return undef;
}
sub
netatmo_requestDeviceReadings($@)
{
  my ($hash,$id,$module) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{IODev}) );

  my $iohash = $hash->{IODev};
  my $type = $hash->{dataTypes};

  netatmo_refreshToken( $iohash );

  my %data = (access_token => $iohash->{access_token}, scope => 'read_station', device_id => $id, scale => "max", type => $type);
  $data{"module_id"} = $module if( $module );

  my $lastupdate = ReadingsVal( $name, ".lastupdate", undef );
  $data{"date_begin"} = $lastupdate if( defined($lastupdate) );

  HttpUtils_NonblockingGet({
    url => 'http://api.netatmo.net/api/getmeasure',
    timeout => 10,
    noshutdown => 1,
    data => \%data,
    hash => $hash,
    type => 'getmeasure',
    callback => \&netatmo_dispatch,
  });
}

sub
netatmo_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  RemoveInternalTimer($hash);

  if( $hash->{SUBTYPE} eq "DEVICE" ) {
    netatmo_pollDevice($hash);
  } elsif( $hash->{SUBTYPE} eq "MODULE" ) {
    netatmo_pollDevice($hash);
  }

  if( defined($hash->{helper}{update_count}) && $hash->{helper}{update_count} > 1024 ) {
    InternalTimer(gettimeofday()+2, "netatmo_poll", $hash, 0);
  } else {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "netatmo_poll", $hash, 0);
  }
}

sub
netatmo_dispatch($$$)
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

    my $json = JSON->new->utf8(0)->decode($data);

    if( $json->{error} ) {
      #$hash->{lastError} = $json->{error}{message};
    }

    if( $param->{type} eq 'token' ) {
      netatmo_parseToken($hash,$json);
    } elsif( $param->{type} eq 'devicelist' ) {
      netatmo_parseDeviceList($hash,$json);
    } elsif( $param->{type} eq 'getmeasure' ) {
      netatmo_parseReadings($hash,$json);
    }
  }
}

sub
netatmo_autocreate($)
{
  my($hash) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{helper}{devices} ) {
    netatmo_getDevices($hash);
    return undef;
  }

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
  }

  my $autocreated = 0;

  my $devices = $hash->{helper}{devices};
  foreach my $device (@{$devices}) {
    if( defined($modules{$hash->{TYPE}}{defptr}{"D$device->{_id}"}) ) {
      Log3 $name, 4, "$name: device '$device->{_id}' already defined";
      next;
    }
    if( defined($modules{$hash->{TYPE}}{defptr}{"M$device->{_id}"}) ) {
      Log3 $name, 4, "$name: module '$device->{_id}' already defined";
      next;
    }

    my $id = $device->{_id};
    my $devname = "netatmo_D". $id;
    my $define= "$devname netatmo $id";
    if( $device->{main_device} ) {
      $devname = "netatmo_M". $id;
      $define= "$devname netatmo MODULE $device->{main_device} $id";
    }

    Log3 $name, 3, "$name: create new device '$devname' for device '$id'";
    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$device->{module_name}) if( defined($device->{module_name}) );
      $cmdret= CommandAttr(undef,"$devname room netatmo");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );
}

sub
netatmo_parseToken($$)
{
  my($hash, $json) = @_;

  RemoveInternalTimer($hash);

  my $had_token = $hash->{access_token};

  $hash->{access_token} = $json->{access_token};
  $hash->{refresh_token} = $json->{refresh_token};

  if( $hash->{access_token} ) {
    $hash->{STATE} = "Connected";

    ($hash->{expires_at}) = gettimeofday();
    $hash->{expires_at} += $json->{expires_in};

    netatmo_getDevices($hash) if( !$had_token );

    InternalTimer(gettimeofday()+$json->{expires_in}*3/4, "netatmo_refreshTokenTimer", $hash, 0);
  } else {
    $hash->{STATE} = "Error" if( !$hash->{access_token} );
    InternalTimer(gettimeofday()+60, "netatmo_refreshTokenTimer", $hash, 0);
  }
}
sub
netatmo_parseDeviceList($$)
{
  my($hash, $json) = @_;

  my $do_autocreate = 1;
  $do_autocreate = 0 if( !defined($hash->{helper}{devices}) ); #autocreate

  my @devices = ();
  foreach my $device (@{$json->{body}{devices}}) {
    push( @devices, $device );
  }
  foreach my $module (@{$json->{body}{modules}}) {
    push( @devices, $module );
  }

  $hash->{helper}{devices} = \@devices;

  netatmo_autocreate($hash) if( $do_autocreate );
}

sub
netatmo_parseReadings($$)
{
  my($hash, $json) = @_;
  my $name = $hash->{NAME};

  if( $json ) {
    $hash->{status} = $json->{status};
    $hash->{status} = $json->{error}{message} if( $json->{error} );
    my $lastupdate = ReadingsVal( $name, ".lastupdate", 0 );
    my @readings = ();
    if( $hash->{status} eq "ok" ) {
      foreach my $values ( @{$json->{body}}) {
        my $time = $values->{beg_time};
        my $step_time = $values->{step_time};

        my $i = -1;
        foreach my $value (@{$values->{value}}) {
          foreach my $reading (@{$value}) {
            $i++;
            next if( !defined($reading) );

            my $name = $hash->{helper}{readingNames}[$i];

            push(@readings, [$time, $name, $reading]);
          }

          $time += $step_time if( $step_time );
        }
      }

      my $latest = 0;
      if( @readings ) {
        readingsBeginUpdate($hash);
        my $i = 0;
        foreach my $reading (sort { $a->[0] <=> $b->[0] } @readings) {
          $hash->{".updateTimestamp"} = FmtDateTime($reading->[0]);
          $hash->{CHANGETIME}[$i++] = FmtDateTime($reading->[0]);
          readingsBulkUpdate( $hash, $reading->[1], $reading->[2], 1 );
          $latest = $reading->[0] if( $reading->[0] > $latest );
        }
        #$hash->{helper}{update_count} = int(@readings);

        my ($seconds) = gettimeofday();
        $hash->{LAST_POLL} = FmtDateTime( $seconds );

        #$seconds = $latest + 1 if( $latest );
        readingsBulkUpdate( $hash, ".lastupdate", $seconds, 0 );

        readingsEndUpdate($hash,1);

        delete $hash->{CHANGETIME};
      }
    }
  }
}

sub
netatmo_pollDevice($)
{
  my ($hash) = @_;

  my $json;
  if( $hash->{Module} ) {
    $json = netatmo_requestDeviceReadings( $hash, $hash->{Device}, $hash->{Module} );
  } else {
    $json = netatmo_requestDeviceReadings( $hash, $hash->{Device} );
  }
}

sub
netatmo_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list;
  if( $hash->{SUBTYPE} eq "DEVICE"
      || $hash->{SUBTYPE} eq "MODULE" ) {
    $list = "update:noArg updateAll:noArg";

    if( $cmd eq "updateAll" ) {
      $cmd = "update";
      CommandDeleteReading( undef, "$name .*" );
    }

    if( $cmd eq "update" ) {
      netatmo_poll($hash);
      return undef;
    }
  } elsif( $hash->{SUBTYPE} eq "ACCOUNT" ) {
    $list = "devices:noArg";

    if( $cmd eq "devices" ) {
      my $devices = netatmo_getDevices($hash,1);
      my $ret;
      foreach my $device (@{$devices}) {
        $ret .= "$device->{_id}\t$device->{module_name}\t$device->{hw_version}\t$device->{firmware}\n";
      }

      $ret = "id\t\t\tname\t\thw\tfw\n" . $ret if( $ret );
      $ret = "no devices found" if( !$ret );
      return $ret;
    }
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
netatmo_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60*5 if($attrName eq "interval" && $attrVal < 60*5 && $attrVal != 0);

  if( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    $hash->{INTERVAL} = 60*5 if( !$attrVal );
  } elsif( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    RemoveInternalTimer($hash);
    if( $cmd eq "set" && $attrVal ne "0" ) {
    } else {
      $attr{$name}{$attrName} = 0;
      netatmo_poll($hash);
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

<a name="netatmo"></a>
<h3>netatmo</h3>
<ul>
  xxx<br><br>

  Notes:
  <ul>
    <li>JSON has to be installed on the FHEM host.</li>
  </ul><br>

  <a name="netatmo_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; netatmo &lt;device&gt;</code><br>
    <code>define &lt;name&gt; netatmo [ACCOUNT] &lt;username&gt; &lt;password&gt; &lt;client_id&gt; &lt;client_secret&gt;</code><br>
    <br>

    Defines a netatmo device.<br><br>
    If a netatmo device of the account type is created all fhem devices for the netatmo devices are automaticaly created.
    <br>

    Examples:
    <ul>
      <code>define netatmo netatmo ACCOUNT abc@test.com myPassword 2134123412399119d4123134 AkqcOIHqrasfdaLKcYgZasd987123asd</code><br>
      <code>define netatmo netatmo 2f:13:2b:93:12:31</code><br>
      <code>define netatmo netatmo MODULE  2f:13:2b:93:12:31 f1:32:b9:31:23:11</code><br>
    </ul>
  </ul><br>

  <a name="netatmo_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>co2</li>
    <li>battery</li>
    <li>batteryLevel</li>
  </ul><br>

  <a name="netatmo_Get"></a>
  <b>Get</b>
  <ul>
    <li>update<br>
      trigger an update</li>
  </ul><br>

  <a name="netatmo_Attr"></a>
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

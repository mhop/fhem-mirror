
# $Id$

# "Hue Personal Wireless Lighting" is a trademark owned by Koninklijke Philips Electronics N.V.,
# see www.meethue.com for more information.
# I am in no way affiliated with the Philips organization.

package main;

use strict;
use warnings;
use POSIX;
use JSON;
use Data::Dumper;

use HttpUtils;

my $HUEBridge_isFritzBox = undef;
sub
HUEBridge_isFritzBox()
{
  $HUEBridge_isFritzBox = int( qx( [ -f /usr/bin/ctlmgr_ctl ] && echo 1 || echo 0 ) )  if( !defined( $HUEBridge_isFritzBox) );

  return $HUEBridge_isFritzBox;
}

sub HUEBridge_Initialize($)
{
  my ($hash) = @_;

  # Provider
  $hash->{ReadFn}  = "HUEBridge_Read";
  $hash->{WriteFn}  = "HUEBridge_Read";
  $hash->{Clients} = ":HUEDevice:";

  #Consumer
  $hash->{DefFn}    = "HUEBridge_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "HUEBridge_Notify";
  $hash->{SetFn}    = "HUEBridge_Set";
  $hash->{GetFn}    = "HUEBridge_Get";
  $hash->{UndefFn}  = "HUEBridge_Undefine";
  $hash->{AttrList}= "key disable:1 httpUtils:1,0 pollDevices:1";
}

sub
HUEBridge_Read($@)
{
  my ($hash,$chash,$name,$id,$obj)= @_;

  if( $id =~ m/^G(\d.*)/ ) {
    return HUEBridge_Call($hash, $chash, 'groups/' . $1, $obj);
  }
  return HUEBridge_Call($hash, $chash, 'lights/' . $id, $obj);
}

sub
HUEBridge_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> HUEBridge [<host>] [interval]"  if(@args < 2);

  my ($name, $type, $host, $interval) = @args;

  if( !defined($host) ) {
    my $ret = HUEBridge_HTTP_Request(0,"http://www.meethue.com/api/nupnp","GET",undef,undef,undef);

    if( defined($ret) && $ret ne '' )
      {
        my $obj = from_json($ret);

        if( defined($obj->[0])
            && defined($obj->[0]->{'internalipaddress'}) ) {
          }
        $host = $obj->[0]->{'internalipaddress'};
      }

    if( !defined($host) ) {
      return 'error detecting bridge.';
    }

    $hash->{DEF} = $host;
  }

  $interval= 300 unless defined($interval);
  if( $interval < 10 ) { $interval = 10; }

  $hash->{STATE} = 'Initialized';

  $hash->{Host} = $host;
  $hash->{INTERVAL} = $interval;

  $attr{$name}{"key"} = join "",map { unpack "H*", chr(rand(256)) } 1..16 unless defined( AttrVal($name, "key", undef) );

  $hash->{helper}{last_config_timestamp} = 0;

  if( !defined($hash->{helper}{count}) ) {
    $modules{$hash->{TYPE}}{helper}{count} = 0 if( !defined($modules{$hash->{TYPE}}{helper}{count}) );
    $hash->{helper}{count} =  $modules{$hash->{TYPE}}{helper}{count}++;
  }

  if( $init_done ) {
    HUEBridge_OpenDev( $hash ) if( !AttrVal($name, "disable", 0) );
  }

  return undef;
}
sub
HUEBridge_Notify($$)
{
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  return undef if( AttrVal($name, "disable", 0) );

  HUEBridge_OpenDev($hash);

  return undef;
}

sub HUEBridge_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

sub HUEBridge_OpenDev($)
{
  my ($hash) = @_;

  my $result = HUEBridge_Call($hash, undef, 'config', undef);
  if( !defined($result) ) {
    return undef;
  }

  if( !defined($result->{'linkbutton'}) )
    {
      HUEBridge_Pair($hash);
      return;
    }

  $hash->{mac} = $result->{'mac'};

  $hash->{STATE} = 'Connected';
  HUEBridge_GetUpdate($hash);

  HUEBridge_Autocreate($hash);

  return undef;
}
sub HUEBridge_Pair($)
{
  my ($hash) = @_;

  $hash->{STATE} = 'Pairing';

  my $result = HUEBridge_Register($hash);
  if( $result->{'error'} )
    {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+5, "HUEBridge_Pair", $hash, 0);

      return undef;
    }

  $hash->{STATE} = 'Paired';

  HUEBridge_OpenDev($hash);

  return undef;
}


sub
HUEBridge_Set($@)
{
  my ($hash, $name, $cmd, $arg, @params) = @_;

  # usage check
  if($cmd eq 'statusRequest') {
    $hash->{LOCAL} = 1;
    #RemoveInternalTimer($hash);
    HUEBridge_GetUpdate($hash);
    delete $hash->{LOCAL};
    return undef;

  } elsif($cmd eq 'swupdate') {
    my $obj = {
      'swupdate' => { 'updatestate' => 3, },
    };
    my $result = HUEBridge_Call($hash, undef, 'config', $obj);

    if( !defined($result) || $result->{'error'} ) {
      return $result->{'error'}->{'description'};
    }

    $hash->{updatestate} = 3;
    $hash->{STATE} = "updating";
    return "starting update";

  } elsif($cmd eq 'autocreate') {
    return HUEBridge_Autocreate($hash,1);

  } elsif($cmd eq 'creategroup') {

    my @lights = ();
    for my $param (@params) {
      $param = $defs{$param}{ID} if( defined $defs{$param} && $defs{$param}{TYPE} eq 'HUEDevice' );
      push( @lights, $param );
    }

    my $obj = { 'name' => $arg,
                'lights' => \@lights,
    };

    my $result = HUEBridge_Call($hash, undef, 'groups', $obj, 'POST');

    if( $result->{success} ) {
      HUEBridge_Autocreate($hash);

      my $code = $name ."-G". $result->{success}{id};
      return "created $modules{HUEDevice}{defptr}{$code}->{NAME}" if( defined($modules{HUEDevice}{defptr}{$code}) );
    }

    return $result->{error}{description} if( $result->{error} );
    return undef;

  } elsif($cmd eq 'deletegroup') {
    if( defined $defs{$arg} && $defs{$arg}{TYPE} eq 'HUEDevice' ) {
      $defs{$arg}{ID} =~ m/G(.*)/;
      $arg = $1;
    }

    my $code = $name ."-G". $arg;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      CommandDelete( undef, "$modules{HUEDevice}{defptr}{$code}{NAME}" );
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    my $result = HUEBridge_Call($hash, undef, "groups/$arg", undef, 'DELETE');
    return $result->{error}{description} if( $result->{error} );

    return undef;

  } else {
    my $list = "creategroup deletegroup autocreate:noArg statusRequest:noArg";
    $list .= " swupdate:noArg" if( defined($hash->{updatestate}) && $hash->{updatestate} == 2 );
    return "Unknown argument $cmd, choose one of $list";
  }
}

sub
HUEBridge_Get($@)
{
  my ($hash, $name, $cmd) = @_;

  return "$name: get needs at least one parameter" if( !defined($cmd) );

  # usage check
  if($cmd eq 'devices') {
    my $result =  HUEBridge_Call($hash, undef, 'lights', undef);
    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %$result ) {
      my $code = $name ."-". $key;
      my $fhem_name ="";
      $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
      $ret .= sprintf( "%2i: %-25s %-15s %s\n", $key, $result->{$key}{name}, $fhem_name, $result->{$key}{type} );
    }
    $ret = sprintf( "%2s  %-25s %-15s %s\n", "ID", "NAME", "FHEM", "TYPE" ) .$ret if( $ret );
    return $ret;

  } elsif($cmd eq 'groups') {
    my $result =  HUEBridge_Call($hash, undef, 'groups', undef);
    $result->{0} = { name => 'Lightset 0', type => 'LightGroup', lights => ["ALL"] };
    my $ret = "";
    foreach my $key ( sort {$a<=>$b} keys %$result ) {
      my $code = $name ."-G". $key;
      my $fhem_name ="";
      $fhem_name = $modules{HUEDevice}{defptr}{$code}->{NAME} if( defined($modules{HUEDevice}{defptr}{$code}) );
      $ret .= sprintf( "%2i: %-15s %-15s %-15s %s\n", $key, $result->{$key}{name}, $fhem_name, $result->{$key}{type},  join( ",", @{$result->{$key}{lights}} ) );
    }
    $ret = sprintf( "%2s  %-15s %-15s %-15s %s\n", "ID", "NAME", "FHEM", "TYPE", "LIGHTS" ) .$ret if( $ret );
    return $ret;

  } else {
    return "Unknown argument $cmd, choose one of devices:noArg groups:noArg";
  }
}

sub
HUEBridge_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEBridge_GetUpdate", $hash, 0);
  }

  my $type;
  my $result;
  if( AttrVal($name,"pollDevices",0) ) {
    my ($now) = gettimeofday();
    if( $hash->{LOCAL} || $now - $hash->{helper}{last_config_timestamp} > 300 ) {
      $result = HUEBridge_Call($hash, $hash, undef, undef);
      $hash->{helper}{last_config_timestamp} = $now;
    } else {
      $type = 'lights';
      $result = HUEBridge_Call($hash, $hash, 'lights', undef);
    }
  } else {
    $type = 'config';
    $result = HUEBridge_Call($hash, $hash, 'config', undef);
  }

  return undef if( !defined($result) );

  HUEBridge_dispatch( {hash=>$hash,chash=>$hash,type=>$type}, undef, undef, $result );

  #HUEBridge_Parse($hash, $result);

  return undef;
}

sub
HUEBridge_Parse($$)
{
  my($hash,$result) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 4, "parse status message for $name";
  #Log3 $name, 5, Dumper $result;

  #Log 3, Dumper $result;
  $result = $result->{config} if( defined($result->{config}) );

  $hash->{name} = $result->{name};
  $hash->{swversion} = $result->{swversion};

  if( defined( $result->{swupdate} ) ) {
    my $txt = $result->{swupdate}->{text};
    readingsSingleUpdate($hash, "swupdate", $txt, 1) if( $txt && $txt ne ReadingsVal($name,"swupdate","") );
    if( defined($hash->{updatestate}) ){
      $hash->{STATE} = "update done" if( $result->{swupdate}->{updatestate} == 0 &&  $hash->{updatestate} >= 2 );
      $hash->{STATE} = "update failed" if( $result->{swupdate}->{updatestate} == 2 &&  $hash->{updatestate} == 3 );
    }

    $hash->{updatestate} = $result->{swupdate}->{updatestate};
  } elsif ( defined(  $hash->{swupdate} ) ) {
    delete( $hash->{updatestate} );
  }
}

sub
HUEBridge_Autocreate($;$)
{
  my ($hash,$force)= @_;
  my $name = $hash->{NAME};

  if( !$force ) {
    foreach my $d (keys %defs) {
      next if($defs{$d}{TYPE} ne "autocreate");
      return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
    }
  }

  my $autocreated = 0;
  my $result =  HUEBridge_Call($hash,undef, 'lights', undef);
  foreach my $key ( keys %$result ) {
    my $id= $key;

    my $code = $name ."-". $id;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
      next;
    }

    my $devname = "HUEDevice" . $id;
    $devname = $name ."_". $devname if( $hash->{helper}{count} );
    my $define= "$devname HUEDevice $id IODev=$name";

    Log3 $name, 4, "$name: create new device '$devname' for address '$id'";

    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$result->{$id}{name});
      $cmdret= CommandAttr(undef,"$devname room HUEDevice");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  $result =  HUEBridge_Call($hash,undef, 'groups', undef);
  $result->{0} = { name => "Lightset 0", };
  foreach my $key ( keys %$result ) {
    my $id= $key;

    my $code = $name ."-G". $id;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
      next;
    }

    my $devname= "HUEGroup" . $id;
    $devname = $name ."_". $devname if( $hash->{helper}{count} );
    my $define= "$devname HUEDevice group $id IODev=$name";

    Log3 $name, 4, "$name: create new group '$devname' for address '$id'";

    my $cmdret= CommandDefine(undef,$define);
    if($cmdret) {
      Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
    } else {
      $cmdret= CommandAttr(undef,"$devname alias ".$result->{$id}{name});
      $cmdret= CommandAttr(undef,"$devname room HUEDevice");
      $cmdret= CommandAttr(undef,"$devname IODev $name");

      $autocreated++;
    }
  }

  CommandSave(undef,undef) if( $autocreated && AttrVal( "autocreate", "autosave", 1 ) );

  return "created $autocreated devices";
}

sub HUEBridge_ProcessResponse($$)
{
  my ($hash,$obj) = @_;
  my $name = $hash->{NAME};

  #Log3 $name, 3, ref($obj);
  #Log3 $name, 3, "Receiving: " . Dumper $obj;

  if( ref($obj) eq 'ARRAY' )
    {
      if( defined($obj->[0]->{error}))
        {
          my $error = $obj->[0]->{error}->{'description'};

          $hash->{STATE} = $error;

          Log3 $name, 3, $error;
        }

      return ($obj->[0]);
    }
  elsif( ref($obj) eq 'HASH' )
    {
      return $obj;
    }

  return undef;
}

sub HUEBridge_Register($)
{
  my ($hash) = @_;

  my $obj = {
    'username'  => AttrVal($hash->{NAME}, "key", ""),
    'devicetype' => 'fhem',
  };

  return HUEBridge_Call($hash, undef, undef, $obj);
}

#Executes a JSON RPC
sub
HUEBridge_Call($$$$;$)
{
  my ($hash,$chash,$path,$obj,$method) = @_;
  my $name = $hash->{NAME};

  #Log3 $hash->{NAME}, 5, "Sending: " . Dumper $obj;

  my $json = undef;
  $json = encode_json($obj) if $obj;

  if( !defined($attr{$name}{httpUtils}) ) {
    return HUEBridge_HTTP_Call($hash,$path,$json,$method);
  } else {
    return HUEBridge_HTTP_Call2($hash,$chash,$path,$json,$method);
  }
}

#JSON RPC over HTTP
sub
HUEBridge_HTTP_Call($$$;$)
{
  my ($hash,$path,$obj,$method) = @_;
  my $name = $hash->{NAME};

  return undef if($attr{$name} && $attr{$name}{disable});
  #return { state => {reachable => 0 } } if($attr{$name} && $attr{$name}{disable});

  my $uri = "http://" . $hash->{Host} . "/api";
  if( defined($obj) ) {
    $method = 'PUT' if( !$method );

    if( $hash->{STATE} eq 'Pairing' ) {
      $method = 'POST';
    } else {
      $uri .= "/" . AttrVal($name, "key", "");
    }
  } else {
    $uri .= "/" . AttrVal($name, "key", "");
  }
  $method = 'GET' if( !$method );
  if( defined $path) {
    $uri .= "/" . $path;
  }
  #Log3 $name, 3, "Url: " . $uri;
  Log3 $name, 4, "using HUEBridge_HTTP_Request: $method ". ($path?$path:'');
  my $ret = HUEBridge_HTTP_Request(0,$uri,$method,undef,$obj,undef);
  #Log3 $name, 3, Dumper $ret;
  if( !defined($ret) ) {
    return undef;
  } elsif($ret eq '') {
    return undef;
  } elsif($ret =~ /^error:(\d){3}$/) {
    return "HTTP Error Code " . $1;
  }

  if( !$ret ) {
    Log3 $name, 2, "$name: empty answer received for $uri";
    return undef;
  } elsif( $ret !~ m/^[\[{].*[\]}]$/ ) {
    Log3 $name, 2, "$name: invalid json detected for $uri: $ret";
    return undef;
  }

#  try {
#    from_json($ret);
#  } catch {
#    return undef;
#  }

  return HUEBridge_ProcessResponse($hash,decode_json($ret)) if( HUEBridge_isFritzBox() );

  return HUEBridge_ProcessResponse($hash,from_json($ret));
}

sub
HUEBridge_HTTP_Call2($$$$;$)
{
  my ($hash,$chash,$path,$obj,$method) = @_;
  my $name = $hash->{NAME};

  return undef if($attr{$name} && $attr{$name}{disable});
  #return { state => {reachable => 0 } } if($attr{$name} && $attr{$name}{disable});

  my $url = "http://" . $hash->{Host} . "/api";
  my $blocking = $attr{$name}{httpUtils} < 1;
  $blocking = 1 if( !defined($chash) );
  if( defined($obj) ) {
    $method = 'PUT' if( !$method );

    if( $hash->{STATE} eq 'Pairing' ) {
      $method = 'POST';
      $blocking = 1;
    } else {
      $url .= "/" . AttrVal($name, "key", "");
    }
  } else {
    $url .= "/" . AttrVal($name, "key", "");
  }
  $method = 'GET' if( !$method );

  if( defined $path) {
    $url .= "/" . $path;
  }
  #Log3 $name, 3, "Url: " . $url;

#Log 2, $path;
  if( $blocking ) {
    Log3 $name, 4, "using HttpUtils_BlockingGet: $method ". ($path?$path:'');

    my($err,$data) = HttpUtils_BlockingGet({
      url => $url,
      timeout => 4,
      method => $method,
      noshutdown => 1,
      header => "Content-Type: application/json",
      data => $obj,
    });

    return HUEBridge_ProcessResponse($hash,from_json($data));

    HUEBridge_dispatch( {hash=>$hash,chash=>$chash,type=>$path},$err,$data );
  } else {
    Log3 $name, 4, "using HttpUtils_NonblockingGet: $method ". ($path?$path:'');

    my($err,$data) = HttpUtils_NonblockingGet({
      url => $url,
      timeout => 10,
      method => $method,
      noshutdown => 1,
      header => "Content-Type: application/json",
      data => $obj,
      hash => $hash,
      chash => $chash,
      type => $path,
      callback => \&HUEBridge_dispatch,
    });

    return undef;
  }
}

sub
HUEBridge_dispatch($$$;$)
{
  my ($param, $err, $data,$json) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};

  #Log3 $name, 5, "HUEBridge_dispatch";

  if( $err ) {
    Log3 $name, 2, "$name: http request failed: $err";
  } elsif( $data || $json ) {
    if( !$data && !$json ) {
      Log3 $name, 2, "$name: empty answer received";
      return undef;
    } elsif( $data && $data !~ m/^[\[{].*[\]}]$/ ) {
      Log3 $name, 2, "$name: invalid json detected: $data";
      return undef;
    }

    $json = from_json($data) if( !$json );
    my $type = $param->{type};

    if( ref($json) eq 'ARRAY' )
      {
        if( defined($json->[0]->{error}))
          {
            my $error = $json->[0]->{error}->{'description'};

            $hash->{STATE} = $error;

            Log3 $name, 3, $error;
          }

        #return ($json->[0]);
      }

    if( $hash == $param->{chash} ) {
      if( !defined($type) ) {
        HUEBridge_Parse($hash,$json->{config});

        if( defined($json->{groups}) ) {
          my $groups = $json->{groups};
          foreach my $id ( keys %{$groups} ) {
            my $code = $name ."-G". $id;
            my $chash = $modules{HUEDevice}{defptr}{$code};

            if( defined($chash) ) {
              HUEDevice_Parse($chash,$groups->{$id});
            } else {
              Log3 $name, 2, "$name: message for unknow group received: $code";
            }
          }
        }

        $type = 'lights';
        $json = $json->{lights};

      }

      if( $type eq 'lights' ) {
        my $lights = $json;
        foreach my $id ( keys %{$lights} ) {
          my $code = $name ."-". $id;
          my $chash = $modules{HUEDevice}{defptr}{$code};

          if( defined($chash) ) {
            HUEDevice_Parse($chash,$lights->{$id});
          } else {
            Log3 $name, 2, "$name: message for unknow device received: $code";
          }
        }

      } elsif( $type =~ m/^config$/ ) {
        HUEBridge_Parse($hash,$json);

      } else {
        Log3 $name, 2, "$name: message for unknow type received: $type";
        Log3 $name, 4, Dumper $json;

      }

    } elsif( $type =~ m/^lights\/(\d*)$/ ) {
      HUEDevice_Parse($param->{chash},$json);

    } elsif( $type =~ m/^groups\/(\d*)$/ ) {
      HUEDevice_Parse($param->{chash},$json);

    } elsif( $type =~ m/^lights\/(\d*)\/state$/ ) {
      my $chash = $param->{chash};
      if( $chash->{helper}->{update_timeout} ) {
        RemoveInternalTimer($chash);
        InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
      } else {
        RemoveInternalTimer($chash);
        HUEDevice_GetUpdate( $chash );
      }

    } elsif( $type =~ m/^groups\/(\d*)\/action$/ ) {
      my $chash = $param->{chash};
      if( $chash->{helper}->{update_timeout} ) {
        RemoveInternalTimer($chash);
        InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
      } else {
        RemoveInternalTimer($chash);
        HUEDevice_GetUpdate( $chash );
      }

    } else {
      Log3 $name, 2, "$name: message for unknow type received: $type";
      Log3 $name, 4, Dumper $json;

    }
  }
}

#adapted version of the CustomGetFileFromURL subroutine from HttpUtils.pm
sub
HUEBridge_HTTP_Request($$$@)
{
  my ($quiet, $url, $method, $timeout, $data, $noshutdown) = @_;
  $timeout = 4.0 if(!defined($timeout));

  my $displayurl= $quiet ? "<hidden>" : $url;
  if($url !~ /^(http|https):\/\/([^:\/]+)(:\d+)?(\/.*)$/) {
    Log3 undef, 1, "HUEBridge_HTTP_Request $displayurl: malformed or unsupported URL";
    return undef;
  }

  my ($protocol,$host,$port,$path)= ($1,$2,$3,$4);

  if(defined($port)) {
    $port =~ s/^://;
  } else {
    $port = ($protocol eq "https" ? 443: 80);
  }
  $path= '/' unless defined($path);


  my $conn;
  if($protocol eq "https") {
    eval "use IO::Socket::SSL";
    if($@) {
      Log3 undef, 1, $@;
    } else {
      $conn = IO::Socket::SSL->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
    }
  } else {
    $conn = IO::Socket::INET->new(PeerAddr=>"$host:$port", Timeout=>$timeout);
  }
  if(!$conn) {
    Log3 undef, 1, "HUEBridge_HTTP_Request $displayurl: Can't connect to $protocol://$host:$port";
    undef $conn;
    return undef;
  }

  $host =~ s/:.*//;
  #my $hdr = ($data ? "POST" : "GET")." $path HTTP/1.0\r\nHost: $host\r\n";
  my $hdr = $method." $path HTTP/1.0\r\nHost: $host\r\n";
  if(defined($data)) {
    $hdr .= "Content-Length: ".length($data)."\r\n";
    $hdr .= "Content-Type: application/json";
  }
  $hdr .= "\r\n\r\n";
  syswrite $conn, $hdr;
  syswrite $conn, $data if(defined($data));
  shutdown $conn, 1 if(!$noshutdown);

  my ($buf, $ret) = ("", "");
  $conn->timeout($timeout);
  for(;;) {
    my ($rout, $rin) = ('', '');
    vec($rin, $conn->fileno(), 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, $timeout);
    if($nfound <= 0) {
      Log3 undef, 1, "HUEBridge_HTTP_Request $displayurl: Select timeout/error: $!";
      undef $conn;
      return undef;
    }

    my $len = sysread($conn,$buf,65536);
    last if(!defined($len) || $len <= 0);
    $ret .= $buf;
  }

  $ret=~ s/(.*?)\r\n\r\n//s; # Not greedy: switch off the header.
  my @header= split("\r\n", $1);
  my $hostpath= $quiet ? "<hidden>" : $host . $path;
  Log3 undef, 5, "HUEBridge_HTTP_Request $displayurl: Got data, length: ".length($ret);
  if(!length($ret)) {
    Log3 undef, 4, "HUEBridge_HTTP_Request $displayurl: Zero length data, header follows...";
    for (@header) {
        Log3 undef, 4, "HUEBridge_HTTP_Request $displayurl: $_";
    }
  }
  undef $conn;
  if($header[0] =~ /^[^ ]+ ([\d]{3})/ && $1 != 200) {
    return "error:" . $1;
  }
  return $ret;
}

1;

=pod
=begin html

<a name="HUEBridge"></a>
<h3>HUEBridge</h3>
<ul>
  Module to access the bridge of the phillips hue lighting system.<br><br>

  The actual hue bulbs, living colors or living whites devices are defined as <a href="#HUEDevice">HUEDevice</a> devices.

  <br><br>
  All newly found devices and groups are autocreated at startup and added to the room HUEDevice.

  <br><br>
  Notes:
  <ul>
    <li>This module needs <code>JSON</code>.<br>
        Please install with '<code>cpan install JSON</code>' or your method of choice.</li>
    <li>autocreate only works for the first bridge. devices on other bridges have to be manualy defined.</li>
  </ul>


  <br><br>
  <a name="HUEBridge_Define_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HUEBridge [&lt;host&gt;] [&lt;interval&gt;]</code><br>
    <br>

    Defines a HUEBridge device with address &lt;host&gt;.<br><br>

    If [&lt;host&gt;] is not given the module will try to autodetect the bridge with the hue portal services.<br><br>

    The bridge status will be updated every &lt;interval&gt; seconds. The default and minimum is 60.<br><br>

    After a new bridge is created the pair button on the bridge has to be pressed.<br><br>

    Examples:
    <ul>
      <code>define bridge HUEBridge 10.0.1.1</code><br>
    </ul>
  </ul><br>

  <a name="HUEBridge_Get"></a>
  <b>Set</b>
  <ul>
    <li>devices<br>
    list the devices known to the bridge.</li>
    <li>groups<br>
    list the groups known to the bridge.</li>
  </ul><br>

  <a name="HUEBridge_Set"></a>
  <b>Set</b>
  <ul>
    <li>autocreate<br>
    Create fhem devices for all bridge devices.</li>
    <li>creategroup &lt;name&gt; &lt;light-1&gt[ &lt;light-2&gt;..&lt;lignt-n&gt;]<br>
    Create a group out of &lt;light-1&gt-&lt;light-n&gt in the bridge.
    The lights can be given as fhem device names or bridge device numbers.</li>
    <li>deletegroup &lt;name&gt;|&lt;id&gt;<br>
    Deletes the given group in the bridge and deletes the associated fhem device.</li>
    <li>statusRequest<br>
    Update bridge status.</li>
    <li>swupdate<br>
    Update bridge firmware. This command is only available if a new firmware is available (indicated by updatestate with a value of 2. The version and release date is shown in the reading swupdate.<br>
    A notify of the form <code>define HUEUpdate notify bridge:swupdate.* {...}</code> can be used to be informed about available firmware updates.<br></li>
  </ul><br>
</ul><br>

=end html
=cut

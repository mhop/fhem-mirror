
# $Id$

# "Hue Personal Wireless Lighting" is a trademark owned by Koninklijke Philips Electronics N.V.,
# see www.meethue.com for more information.
# I am in no way affiliated with the Philips organization.

package main;

use strict;
use warnings;
use POSIX;
use JSON;
#use Try::Tiny;
use Data::Dumper;
use MIME::Base64;

sub HUEBridge_Initialize($)
{
  my ($hash) = @_;

  # Provider
  $hash->{ReadFn}  = "HUEBridge_Read";
  $hash->{WriteFn}  = "HUEBridge_Read";
  $hash->{Clients} = ":HUEDevice:";

  #Consumer
  $hash->{DefFn}    = "HUEBridge_Define";
  $hash->{NotifyFn} = "HUEBridge_Notify";
  $hash->{SetFn}    = "HUEBridge_Set";
  $hash->{GetFn}    = "HUEBridge_Get";
  $hash->{UndefFn}  = "HUEBridge_Undefine";
  $hash->{AttrList}= "key";
}

sub
HUEBridge_Read($@)
{
  my ($hash,$name,$id,$obj)= @_;

  if( $id =~ m/^G(\d.*)/ ) {
    return HUEBridge_Call($hash, 'groups/' . $1, $obj);
  }
  return HUEBridge_Call($hash, 'lights/' . $id, $obj);
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
        my $obj = decode_json($ret);

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
  if( $interval < 60 ) { $interval = 60; }

  $hash->{STATE} = 'Initialized';

  $hash->{Host} = $host;
  $hash->{INTERVAL} = $interval;

  $attr{$name}{"key"} = join "",map { unpack "H*", chr(rand(256)) } 1..16 unless defined( AttrVal($name, "key", undef) );

  if( !defined($hash->{helper}{count}) ) {
    $modules{$hash->{TYPE}}{helper}{count} = 0 if( !defined($modules{$hash->{TYPE}}{helper}{count}) );
    $hash->{helper}{count} =  $modules{$hash->{TYPE}}{helper}{count}++;
  }

  if( $init_done ) {
    delete $modules{$hash->{TYPE}}{NotifyFn};
    HUEBridge_OpenDev( $hash );
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

  return if($attr{$name} && $attr{$name}{disable});

  delete $modules{$type}{NotifyFn};
  delete $hash->{NTFY_ORDER} if($hash->{NTFY_ORDER});

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "$type");
    HUEBridge_OpenDev($defs{$d});
  }

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

  my $result = HUEBridge_Call($hash, 'config', undef);
  if( !defined($result) ) {
    return undef;
  }

  if( !defined($result->{'mac'}) )
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
  my ($hash, $name, $cmd) = @_;

  # usage check
  if($cmd eq 'statusRequest') {
    RemoveInternalTimer($hash);
    HUEBridge_GetUpdate($hash);
    return undef;
  } elsif($cmd eq 'swupdate') {
    my $obj = {
      'swupdate' => { 'updatestate' => 3, },
    };
    my $result = HUEBridge_Call($hash, 'config', $obj);

    if( !defined($result) || $result->{'error'} ) {
      return $result->{'error'}->{'description'};
    }

    $hash->{updatestate} = 3;
    $hash->{STATE} = "updating";
    return "starting update";
  } elsif($cmd eq 'autocreate') {
    HUEBridge_Autocreate($hash);
    return undef;
  } else {
    my $list = "statusRequest:noArg";
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
    my $result =  HUEBridge_Call($hash, 'lights', undef);
    my $ret = "";
    foreach my $key ( sort keys %$result ) {
      $ret .= $key .": ". $result->{$key}{name} ."\n";
    }
    return $ret;
  } elsif($cmd eq 'groups') {
    my $result =  HUEBridge_Call($hash, 'groups', undef);
    $result->{0} = { name => "Lightset 0", };
    my $ret = "";
    foreach my $key ( sort keys %$result ) {
      $ret .= $key .": ". $result->{$key}{name} ."\n";
    }
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
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "HUEBridge_GetUpdate", $hash, 1);
  }

  my $result = HUEBridge_Call($hash, 'config', undef);
  #my $result = HUEBridge_Call($hash, undef, undef);
  #Log 3, Dumper $result;
  #$result = $result->{config};
  $hash->{name} = $result->{name};
  $hash->{swversion} = $result->{swversion};

  if( defined( $result->{swupdate} ) ) {
    my $txt = $result->{swupdate}->{text};
    readingsSingleUpdate($hash, "swupdate", $txt, defined($hash->{LOCAL} ? 0 : 1)) if( $txt && $txt ne ReadingsVal($name,"swupdate","") );
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
HUEBridge_Autocreate($)
{
  my ($hash)= @_;
  my $name = $hash->{NAME};

  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "autocreate");
    return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
  }

  my $result =  HUEBridge_Call($hash, 'lights', undef);
  foreach my $key ( keys %$result ) {
    my $id= $key;

    my $code = $name ."-". $id;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      Log3 $name, 4, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
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
    }
  }

  $result =  HUEBridge_Call($hash, 'groups', undef);
  $result->{0} = { name => "Lightset 0", };
  foreach my $key ( keys %$result ) {
    my $id= $key;

    my $code = $name ."-G". $id;
    if( defined($modules{HUEDevice}{defptr}{$code}) ) {
      Log3 $name, 4, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";
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
    }
  }

  return undef;
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

  return HUEBridge_Call($hash, undef, $obj);
}

#Executes a JSON RPC
sub
HUEBridge_Call($$$)
{
  my ($hash,$path,$obj) = @_;

  #Log3 $name, 3, "Sending: " . Dumper $obj;

  my $json = undef;
  $json = encode_json($obj) if $obj;

  return HUEBridge_HTTP_Call($hash,$path,$json);
}

#JSON RPC over HTTP
sub HUEBridge_HTTP_Call($$$)
{
  my ($hash,$path,$obj) = @_;
  my $name = $hash->{NAME};

  my $uri = "http://" . $hash->{Host} . "/api";
  my $method = 'GET';
  if( defined($obj) ) {
      $method = 'PUT';

      if( $hash->{STATE} eq 'Pairing' ) {
          $method = 'POST';
      } else {
        $uri .= "/" . AttrVal($name, "key", "");
      }
    } else {
      $uri .= "/" . AttrVal($name, "key", "");
    }
  if( defined $path) {
    $uri .= "/" . $path;
  }
  #Log3 $name, 3, "Url: " . $uri;
  my $ret = HUEBridge_HTTP_Request(0,$uri,$method,undef,$obj,undef);
  #Log3 $name, 3, Dumper $ret;
  if( !defined($ret) ) {
    return undef;
  } elsif($ret eq '') {
    return undef;
  } elsif($ret =~ /^error:(\d){3}$/) {
    return "HTTP Error Code " . $1;
  }

#  try {
#    decode_json($ret);
#  } catch {
#    return undef;
#  }

  return HUEBridge_ProcessResponse($hash,decode_json($ret));
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
    <li>statusRequest<br>
    Update bridge status.</li>
    <li>swupdate<br>
    Update bridge firmware. This command is only available if a new firmware is available (indicated by updatestate with a value of 2. The version and release date is shown in the reading swupdate.<br>
    A notify of the form <code>define HUEUpdate notify bridge:swupdate.* {...}</code> can be used to be informed about available firmware updates.<br></li>
  </ul><br>
</ul><br>

=end html
=cut

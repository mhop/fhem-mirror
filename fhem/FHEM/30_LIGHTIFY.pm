
# $Id$

package main;

use strict;
use warnings;

use Color;

use IO::Socket::INET;
use IO::File;
use IO::Handle;
use Data::Dumper;

use constant { getDevices  => '13',
               setDim => '31',
               setOnOff => '32',
               setCT => '33',
               setRGB => '36',
             };

sub
LIGHTIFY_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "LIGHTIFY_Read";
  $hash->{WriteFn}  = "LIGHTIFY_Write";
  $hash->{Clients}  = ":HUEDevice:";

  $hash->{DefFn}    = "LIGHTIFY_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "LIGHTIFY_Notify";
  $hash->{UndefFn}  = "LIGHTIFY_Undefine";
  $hash->{SetFn}    = "LIGHTIFY_Set";
  #$hash->{GetFn}    = "LIGHTIFY_Get";
  $hash->{AttrFn}   = "LIGHTIFY_Attr";
  $hash->{AttrList} = "disable:1";
}

#####################################

sub
LIGHTIFY_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> LIGHTIFY host"  if(@a < 3);

  my $name = $a[0];

  my $host = $a[2];

  $hash->{NAME} = $name;
  $hash->{Host} = $host;

  if( $init_done ) {
    LIGHTIFY_Disconnect($hash);
    LIGHTIFY_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  $attr{$name}{pollDevices} = 1;

  return undef;
}

sub
LIGHTIFY_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  LIGHTIFY_Connect($hash);

  return undef;
}

sub
LIGHTIFY_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  $hash->{MSG_NR} = 0;

  my @send_queue = ();
  $hash->{SEND_QUEUE} = \@send_queue;
  $hash->{UNCONFIRMED} = 0;

  my $socket = IO::Socket::INET->new( PeerAddr => $hash->{Host},
                                      PeerPort => 4000, #AttrVal($name, "port", 4000)
                                    );

  if($socket) {
    $hash->{STATE} = "Connected";
    $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );

    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;
    Log3 $name, 3, "$name: connected to $hash->{Host}";

    LIGHTIFY_sendRaw( $hash, getDevices ." 00 00 00 00 01" );

  } else {
    Log3 $name, 3, "$name: failed to connect to $hash->{Host}";

    LIGHTIFY_Disconnect($hash);
    InternalTimer(gettimeofday()+10, "LIGHTIFY_Connect", $hash, 0);

  }
}
sub
LIGHTIFY_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);

  return if( !$hash->{CD} );

  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});
  $hash->{STATE} = "Disconnected";
  Log3 $name, 3, "$name: Disconnected";
  $hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
}

sub
LIGHTIFY_Undefine($$)
{
  my ($hash, $arg) = @_;

  LIGHTIFY_Disconnect($hash);

  return undef;
}
sub
LIGHTIFY_sendRaw($$)
{
  my ($hash, $hex) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );
  return "not connected" if( !$hash->{CD} );

  if( $hash->{UNCONFIRMED} ) {
    Log3 $name, 4, "$name: enque:". $hex;
    push  @{$hash->{SEND_QUEUE}}, $hex;
    return undef;
  }

  substr($hex,2*1,2+1,sprintf( '%02x', $hash->{MSG_NR} ) );
  $hash->{MSG_NR}++;
  $hash->{MSG_NR} &= 0xFF;

  $hex =~ s/ //g;
  my $length = length($hex)/2+1;
  $hex = sprintf( '%02x%02x', $length & 0xff, $length >> 8 ) .'00'. $hex;

  Log3 $name, 4, "$name: sending:". $hex;

  #return undef if( AttrVal($name, "disable", 0 ) == 1 );
  #return "not connected" if( !$hash->{CD} );
  syswrite($hash->{CD}, pack('H*', $hex));

  $hash->{UNCONFIRMED}++;

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+1, "LIGHTIFY_sendNext", $hash, 0);

  return undef;
}
sub
LIGHTIFY_Write($@)
{
  my ($hash,$chash,$name,$id,$obj)= @_;
#Log 3, Dumper $obj;

  return undef if( !$chash );

  if( $obj ) {
    if( defined($obj->{on}) ) {
      my $onoff = "00";
      $onoff = "01" if( $obj->{on} );

      LIGHTIFY_sendRaw( $hash, setOnOff ." 00 00 00 00 $chash->{ID} $onoff" );
    }

    if( defined($obj->{ct}) ) {
      my $ct = int(1000000 / $obj->{ct});
      $ct = sprintf( '%02x%02x', $ct & 0xff, $ct >> 8 );

      my $transitiontime = 2;
      $transitiontime = $obj->{transitiontime} if( defined($obj->{transitiontime}) );
      $transitiontime = sprintf( '%02x%02x', $transitiontime & 0xff, $transitiontime >> 8 );

      LIGHTIFY_sendRaw( $hash, setCT ." 00 00 00 00 $chash->{ID} $ct $transitiontime" );
    } elsif( defined($obj->{hue}) || defined($obj->{sat}) ) {
      my $hue = ReadingsVal($chash->{NAME}, 'hue', 65535 );
      my $sat = ReadingsVal($chash->{NAME}, 'sat', 254 );
      my $bri = ReadingsVal($chash->{NAME}, 'bri', 254 );
      $hue = $obj->{hue} if( defined($obj->{hue}) );
      $sat = $obj->{sat} if( defined($obj->{sat}) );
      $bri = $obj->{bri} if( defined($obj->{bri}) );

      my $h = $hue / 65535.0;
      my $s = $sat / 254.0;
      my $v = $bri / 254.0;
      my ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);
      $r *= 255;
      $g *= 255;
      $b *= 255;
      my $rgb = sprintf( "%02x%02x%02x", $r+0.5, $g+0.5, $b+0.5 );

      my $transitiontime = 2;
      $transitiontime = $obj->{transitiontime} if( defined($obj->{transitiontime}) );
      $transitiontime = sprintf( '%02x%02x', $transitiontime & 0xff, $transitiontime >> 8 );

      LIGHTIFY_sendRaw( $hash, setRGB ." 00 00 00 00 $chash->{ID} $rgb ff $transitiontime" );
    } elsif( defined($obj->{bri}) ) {
      my $bri = $obj->{bri};
      $bri /= 2.54;
      $bri = sprintf( "%02x", $bri );

      my $transitiontime = 2;
      $transitiontime = $obj->{transitiontime} if( defined($obj->{transitiontime}) );
      $transitiontime = sprintf( '%02x%02x', $transitiontime & 0xff, $transitiontime >> 8 );

      LIGHTIFY_sendRaw( $hash, setDim ." 00 00 00 00 $chash->{ID} $bri $transitiontime" );
    }
  }

  LIGHTIFY_sendRaw( $hash, getDevices ." 00 00 00 00 01" );

  return undef;
}

sub
LIGHTIFY_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  my $list = "";

  $list .= "raw " if( $hash->{CD} );
  $list .= "reconnect:noArg ";
  $list .= "statusRequest:noArg " if( $hash->{CD} );

  if( $cmd eq 'raw' ) {
    return LIGHTIFY_sendRaw( $hash, join( '', @args ) );

    return undef;

  } elsif( $cmd eq 'received' ) {
    my $hex = join( '', @args );
    $hex =~ s/ //g;
    LIGHTIFY_Parse($hash, $hex);

    return undef;

  } elsif( $cmd eq 'reconnect' ) {
    LIGHTIFY_Disconnect($hash);
    LIGHTIFY_Connect($hash);

    return undef;

  } elsif( $cmd eq 'statusRequest' ) {
    return LIGHTIFY_sendRaw( $hash, getDevices ." 00 00 00 00 01" );

    return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
LIGHTIFY_poll($)
{
  my ($hash) = @_;

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "LIGHTIFY_poll", $hash, 0);
}


sub
LIGHTIFY_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
LIGHTIFY_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60 if($attrName eq "interval" && $attrVal < 60 && $attrVal != 0);

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      LIGHTIFY_Disconnect($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      LIGHTIFY_Disconnect($hash);
      LIGHTIFY_Connect($hash);
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

sub
LIGHTIFY_sendNext($)
{
  my ($hash) = @_;

  $hash->{UNCONFIRMED}-- if( $hash->{UNCONFIRMED} > 0 );

  if( $hash->{SEND_QUEUE} ) {
    my $hex = shift @{$hash->{SEND_QUEUE}};
    LIGHTIFY_sendRaw( $hash, $hex ) if( $hex );
  }
}
sub
LIGHTIFY_Parse($$)
{
  my ($hash,$hex) = @_;
  my $name = $hash->{NAME};

  $hex = uc($hex);

  my $length = hex(substr($hex,2*1,2*1).substr($hex,2*0,2*1));
  my $response = substr($hex,2*3,2*1);
  my $cnt = substr($hex,2*4,2*1);
  if( $response eq getDevices ) {
    my $nr_lights = hex(substr($hex,2*9,2*1));

    my $autocreated = 0;
    for( my $i = 0; $i < $nr_lights; ++$i ) {
      my $short = substr($hex,$i*42*2+2*11,2*2);
      my $id = substr($hex,$i*42*2+2*13,2*8);
      my $type = substr($hex,$i*42*2+2*21,2*1);
      my $onoff = hex(substr($hex,$i*42*2+2*29,2*1));
      my $dim = hex(substr($hex,$i*42*2+2*30,2*1));
      my $ct = hex(substr($hex,$i*42*2+2*32,2*1).substr($hex,$i*42*2+2*31,2*1));
      my $r = (substr($hex,$i*42*2+2*33,2*1));
      my $g = (substr($hex,$i*42*2+2*34,2*1));
      my $b = (substr($hex,$i*42*2+2*35,2*1));
      my $alias = pack('H*', substr($hex,$i*42*2+2*37,2*16));
Log 3, "$alias: $id:$short, type?: $type, onoff: $onoff, dim: $dim, ct: $ct, rgb: $r$g$b";


      #my $code = $id;
      my $code = $name ."-". $id;
      if( defined($modules{HUEDevice}{defptr}{$code}) ) {
        Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";

      } else {
        my $devname = "HUEDevice" . $id;
        #my $define= "$devname HUEDevice $id";
        my $define= "$devname HUEDevice $id IODev=$name";
        Log3 $name, 4, "$name: create new device '$devname' for address '$id'";
        my $cmdret= CommandDefine(undef,$define);
        if($cmdret) {
          Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
        } else {
          $cmdret= CommandAttr(undef,"$devname alias ".$alias);
          $cmdret= CommandAttr(undef,"$devname room LIGHTIFY");
          $cmdret= CommandAttr(undef,"$devname IODev $name");
          $cmdret= CommandAttr(undef,"$devname subType extcolordimmer");

          $autocreated++;
        }
      }

      if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
        my( $r, $g, $b ) = (hex($r)/255.0, hex($g)/255.0, hex($b)/255.0);
        my( $h, $s, $v ) = Color::rgb2hsv($r,$g,$b);

        my $json = { state => { reachable => ($short eq 'FFFF') ? 0 : 1,

                                on => $onoff,

                                colormode => 'hs',
                                hue => int( $h * 65535 ),
                                sat => int( $s * 254 ),
                                bri => int( $v * 254 ),

                                ct => int(1000000/$ct),

                                bri => int($dim/100*254),
                   } };


        HUEDevice_Parse( $chash, $json );
      }

    }

    return "created $autocreated devices";
  } elsif( $response eq setOnOff ) {
    my $id = substr($hex,2*11,2*8);
    my $onoff = hex(substr($hex,2*19,2*1));

  }

  LIGHTIFY_sendNext( $hash );
}

sub
LIGHTIFY_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 1024);

  if( !defined($ret) || !$ret ) {
    Log3 $name, 4, "$name: disconnected";
    LIGHTIFY_Disconnect($hash);
    InternalTimer(gettimeofday()+10, "LIGHTIFY_Connect", $hash, 0);
    return;
  }

  my $hex = unpack('H*', $buf);
  Log3 $name, 4, "$name: received: $hex";

  LIGHTIFY_Parse($hash, $hex);
}

1;

=pod
=begin html

<a name="LIGHTIFY"></a>
<h3>LIGHTIFY</h3>
<ul>
  Module to integrate a OSRAM LIGHTIFY gateway into FHEM;.<br><br>

  The actual LIGHTIFY lights are defined as <a href="#HUEDevice">HUEDevice</a> devices.

  <br><br>
  All newly found devices and groups are autocreated at startup and added to the room LIGHTIFY.

  <br><br>
  Notes:
  <ul>
    <li>Autocreate only works for the first gateway. Devices on other gateways have to be manualy defined.</li>
  </ul>


  <br><br>
  <a name="LIGTHIFY_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LIGHTIFY &lt;host&gt;</code><br>
    <br>

    Defines a LIGHTIFY gateway device with address &lt;host&gt;.<br><br>

    Examples:
    <ul>
      <code>define gateway LIGHTIFY 10.0.1.1</code><br>
    </ul>
  </ul><br>

  <a name="LIGHTIFY_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="LIGHTIFY_Set"></a>
  <b>Set</b>
  <ul>
    <li>reconnect<br>
      Closes and reopens the connection to the gateway.</li>

    <li>statusRequest<br>
      Update light status.</li>
  </ul><br>
</ul><br>

=end html
=cut


# $Id$

package main;

use strict;
use warnings;

use Color;

use JSON;

use IO::Socket::INET;
use IO::File;
use IO::Handle;
use Data::Dumper;

use constant {      getDevices => '13',       #  19
                     getGroups => '1E',       #  30
                    addToGroup => '20',       #  32
               removeFromGroup => '21',       #  33
                  getGroupInfo => '26',       #  38
                  setGroupName => '27',       #  39
                       setName => '28',       #  40
                        setDim => '31',       #  49
                      setOnOff => '32',       #  50
                         setCT => '33',       #  51
                        setRGB => '36',       #  54
                   setPhysical => '38',
                     goToScene => '52',       #  82
                     getStatus => '68',       # 104
                     setSoftOn => 'DB',       # -37
                    setSoftOff => 'DC',       # -36

                       switch => 0x1,
                     ctdimmer => 0x2,
                       dimmer => 0x4,
                  colordimmer => 0x8,
               extcolordimmer => 0x10,
               motiondetector => 0x20,
                    pushbuton => 0x41,
             };

sub
LIGHTIFY_Initialize($)
{
  my ($hash) = @_;

  $hash->{ReadFn}   = "LIGHTIFY_Read";
  $hash->{WriteFn}  = "LIGHTIFY_Write";
  $hash->{Clients}  = ":HUEDevice:";

  $hash->{DefFn}    = "LIGHTIFY_Define";
  $hash->{RenameFn} = "LIGHTIFY_Rename";
  $hash->{NotifyFn} = "LIGHTIFY_Notify";
  $hash->{UndefFn}  = "LIGHTIFY_Undefine";
  $hash->{SetFn}    = "LIGHTIFY_Set";
  #$hash->{GetFn}    = "LIGHTIFY_Get";
  $hash->{AttrFn}   = "LIGHTIFY_Attr";
  $hash->{AttrList} = "disable:1,0 disabledForIntervals pollDevices:1";
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

  $hash->{INTERVAL} = 60;

  $hash->{NOTIFYDEV} = "global";

  if( $init_done ) {
    LIGHTIFY_Disconnect($hash);
    LIGHTIFY_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    readingsSingleUpdate($hash, 'state', 'initialized', 1 );
  }

  $attr{$name}{pollDevices} = 1;

  return undef;
}
sub
LIGHTIFY_Rename($$$)
{
  my ($new,$old) = @_;
 
  foreach my $chash ( values %{$modules{HUEDevice}{defptr}} ) {
    next if( !$chash->{IODev} );
    next if( $chash->{IODev}{NAME} ne $new );
 
    HUEDevice_IODevChanged($chash, $old, $new);
  }
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

  return undef if( IsDisabled($name) > 0 );

  $hash->{MSG_NR} = 0;

  my @send_queue = ();
  $hash->{SEND_QUEUE} = \@send_queue;
  $hash->{UNCONFIRMED} = 0;
  $hash->{PARTIAL} = "";

  my $socket = IO::Socket::INET->new( PeerAddr => $hash->{Host},
                                      PeerPort => 4000, #AttrVal($name, "port", 4000),
                                      Timeout => 4,
                                    );

  if($socket) {
    readingsSingleUpdate($hash, 'state', 'connected', 1 );
    $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );

    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;
    Log3 $name, 3, "$name: connected to $hash->{Host}";

    LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );
    LIGHTIFY_sendRaw( $hash, '00', getGroups ." 00 00 00 00 00" );

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
  readingsSingleUpdate($hash, 'state', 'disconnected', 1 );
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
LIGHTIFY_sendRaw($$$;$)
{
  my ($hash, $flag, $hex, $force) = @_;
  my $name = $hash->{NAME};

  return undef if( IsDisabled($name) > 0 );
  return "not connected" if( !$hash->{CD} );

  if( !$force && $hash->{UNCONFIRMED} ) {
    for(my $i = int(@{$hash->{SEND_QUEUE}}); $i >= 0; --$i) {
      my $a = $hash->{SEND_QUEUE}[$i];
      next if( !$a );
      if( $flag eq $a->[0] && $hex eq $a->[1] ) {
        Log3 $name, 4, "$name: discard: $flag, $hex";

        if( 1 ) {
          splice @{$hash->{SEND_QUEUE}}, $i, 1;
        } else {
          return undef;
        }
      }
    }

    Log3 $name, 4, "$name: enque: $flag, $hex";
    push  @{$hash->{SEND_QUEUE}}, [$flag, $hex, $hash->{CL}];
    return undef;
  }

  substr($hex,2*1,2+1,sprintf( '%02X', $hash->{MSG_NR} ) );
  $hash->{MSG_NR}++;
  $hash->{MSG_NR} &= 0xFF;

  $hex =~ s/ //g;
  my $length = length($hex)/2+1;
  $hex = sprintf( '%02X%02X', $length & 0xff, $length >> 8 ) . $flag . $hex;

  Log3 $name, 4, "$name: sending: ". $hex;

  #return undef if( IsDisabled($name) > 0 );
  #return "not connected" if( !$hash->{CD} );
  syswrite($hash->{CD}, pack('H*', $hex));

  $hash->{helper}{CL} = $hash->{CL};

  $hash->{UNCONFIRMED}++ if( !$force );

  RemoveInternalTimer($hash, "LIGHTIFY_sendNext");
  InternalTimer(gettimeofday()+1, "LIGHTIFY_sendNext", $hash, 0);

  return undef;
}
sub
LIGHTIFY_Write($@)
{
  my ($hash,$chash,$name,$id,$obj)= @_;
#Log 3, Dumper $obj;

  return undef if( !$chash );

  my $flag = '00';
  my $light = $chash->{ID};
  if( $chash->{helper}->{devtype} && $chash->{helper}->{devtype} eq 'G' ) {

    my $group = $chash->{ID};
    $group =~ s/^.//;
    $group = sprintf( "%02X", $group );

    if( $group eq '00' ) {
      $light = 'FF FF FF FF FF FF FF FF';

    } else {
      $flag = '02';
      $light = "$group 00 00 00 00 00 00 00";

      if( $obj ) {
        if( defined($obj->{name}) ) {
          my $name;
          for( my $i = 0; $i < 15; ++$i ) {
            $name .= sprintf( "%02X ", ord(substr($obj->{name},$i,1)) );
          }
          $name .= '00';
          LIGHTIFY_sendRaw( $hash, $flag, setGroupName ." 00 00 00 00 $group 00 $name" );

          CommandAttr(undef,"$chash->{NAME} alias $obj->{name}");
          CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

          #LIGHTIFY_sendRaw( $hash, '00', getGroups ." 00 00 00 00 00" );
          return undef;
        }
      }

    }

    $chash->{helper}{on} = -1;
  }

  if( $obj ) {
    if( defined($obj->{name}) ) {
      my $name;
      for( my $i = 0; $i < 15; ++$i ) {
        $name .= sprintf( "%02X ", ord(substr($obj->{name},$i,1)) );
      }
      $name .= '00';
      LIGHTIFY_sendRaw( $hash, $flag, setName ." 00 00 00 00 $light $name" );

      CommandAttr(undef,"$chash->{NAME} alias $obj->{name}");
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );

      #LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );
      return undef;
    }
  }

  my $force = ($chash->{helper}->{update_timeout} && $chash->{helper}->{update_timeout} == -1);

  my $transitiontime = 2;
  my $json = { state => { xreachable => 1, } };

  if( $obj ) {
    if( defined($obj->{on}) ) {
      my $onoff = "00";
      $onoff = "01" if( $obj->{on} );

      LIGHTIFY_sendRaw( $hash, $flag, setOnOff ." 00 00 00 00 $light $onoff", $force ) if( 1 || $obj->{on} != $chash->{helper}{on} );

      $json->{state}{on} = $obj->{on} ? JSON::true : JSON::false;
    }

    if( defined($obj->{ct}) ) {
      my $ct = int(1000000 / $obj->{ct});
      $ct = sprintf( '%02X%02X', $ct & 0xff, $ct >> 8 );

      $transitiontime = $obj->{transitiontime} if( defined($obj->{transitiontime}) );
      my $t = sprintf( '%02X%02X', $transitiontime & 0xff, $transitiontime >> 8 );

      LIGHTIFY_sendRaw( $hash, $flag, setCT ." 00 00 00 00 $light $ct $t", $force );

      $json->{state}{colormode} = 'ct';
      $json->{state}{ct} = $obj->{ct};

    } elsif( defined($obj->{hue}) || defined($obj->{sat}) ) {
      my $hue = ReadingsVal($chash->{NAME}, 'hue', 65535 );
      my $sat = ReadingsVal($chash->{NAME}, 'sat', 254 );
      my $bri = ReadingsVal($chash->{NAME}, 'bri', 254 );
      $hue = $obj->{hue} if( defined($obj->{hue}) );
      $sat = $obj->{sat} if( defined($obj->{sat}) );
      $bri = $obj->{bri} if( defined($obj->{bri}) );

      $json->{state}{colormode} = 'hs';
      $json->{state}{bri} = $obj->{bri};
      $json->{state}{hue} = $obj->{hue};
      $json->{state}{sat} = $obj->{sat};

      my $h = $hue / 65535.0;
      my $s = $sat / 254.0;
      my $v = $bri / 254.0;
      my ($r,$g,$b) = Color::hsv2rgb($h,$s,$v);
      $r *= 255;
      $g *= 255;
      $b *= 255;
      my $rgb = sprintf( "%02X%02X%02X", $r+0.5, $g+0.5, $b+0.5 );

      $transitiontime = $obj->{transitiontime} if( defined($obj->{transitiontime}) );
      my $t = sprintf( '%02X%02X', $transitiontime & 0xff, $transitiontime >> 8 );

      LIGHTIFY_sendRaw( $hash, $flag, setRGB ." 00 00 00 00 $light $rgb 00 $t", $force );
    }

    if( defined($obj->{bri})
        && !defined($obj->{hue}) && !defined($obj->{sat}) ) {
      my $bri = $obj->{bri};
      $bri /= 2.54;
      $bri = sprintf( "%02X", $bri );

      $transitiontime = $obj->{transitiontime} if( defined($obj->{transitiontime}) );
      my $t = sprintf( '%02X%02X', $transitiontime & 0xff, $transitiontime >> 8 );

      LIGHTIFY_sendRaw( $hash, $flag, setDim ." 00 00 00 00 $light $bri $t", $force );

      $json->{state}{bri} = $obj->{bri};
    }

  }

  my $fake = (0 && $chash->{helper}->{update_timeout} && $chash->{helper}->{update_timeout} != 0);
  if( $obj && $fake ) {
    HUEDevice_Parse( $chash, $json );

    $chash->{helper}->{update_timeout} = AttrVal($name, "delayedUpdate", 0);;
    #$chash->{helper}->{update_timeout} = 1 if( !$chash->{helper}->{update_timeout} );

    RemoveInternalTimer($chash);
    InternalTimer(gettimeofday()+$chash->{helper}->{update_timeout}, "HUEDevice_GetUpdate", $chash, 0);

  } else {
    if( $flag eq '00' && $light ne 'FF FF FF FF FF FF FF FF' ) {
      LIGHTIFY_sendRaw( $hash, '00', getStatus ." 00 00 00 00 $light" );

      $chash->{helper}{transitiontime} = int($transitiontime/10) if( $obj );
      #RemoveInternalTimer($chash);
      #InternalTimer(gettimeofday()+5, "HUEDevice_GetUpdate", $chash, 0);

    } else {
      LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );

    }

  }

  my %ret = ();
  return \%ret;
}

sub
LIGHTIFY_Set($$@)
{
  my ($hash, $name, $cmd, @args) = @_;

  $hash->{".triggerUsed"} = 1;

  my $list = "";

  $list .= "on off  " if( $hash->{CD} );
  $list .= "raw " if( $hash->{CD} );
  $list .= "reconnect:noArg ";
  $list .= "goToScene " if( $hash->{CD} );
  $list .= "setRGBW " if( $hash->{CD} );
  $list .= "setSoftOn setSoftOff " if( $hash->{CD} );
  $list .= "statusRequest:noArg " if( $hash->{CD} );

  if( $cmd eq 'on' ) {
    LIGHTIFY_sendRaw( $hash, '00', setOnOff ." 00 00 00 00 FF FF FF FF FF FF FF FF 01", 1 );
    LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );
    return undef;

  } elsif( $cmd eq 'off' ) {
    LIGHTIFY_sendRaw( $hash, '00', setOnOff ." 00 00 00 00 FF FF FF FF FF FF FF FF 00", 1 );
    LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );
    return undef;

  } elsif( $cmd eq 'raw' ) {
    return LIGHTIFY_sendRaw( '00', $hash, join( '', @args ) );

    return undef;

  } elsif( $cmd eq 'received' ) {
    my $hex = join( '', @args );
    $hex =~ s/ //g;
    LIGHTIFY_Parse($hash, $hex);

    return undef;

  } elsif( $cmd eq 'reconnect' ) {
    delete $hash->{CL};
    LIGHTIFY_Disconnect($hash);
    LIGHTIFY_Connect($hash);

    return undef;

  } elsif( $cmd eq 'statusRequest' ) {
    return LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );

  } elsif( $cmd eq 'getGroups' ) {
    return LIGHTIFY_sendRaw( $hash, '00', getGroups ." 00 00 00 00 00" );

  } elsif( $cmd eq 'getGroupInfo' ) {
    return "usage: getGroupInfo <groupId>" if( !$args[0] );
    return "usage: <groupId> musst be numeric" if( $args[0] !~ /^\d*$/ );
    return "usage: <groupId> musst be in the range [0-255]" if( $args[0] < 0 || $args[0] > 255 );

    my $group = $args[0];
    $group = 1 if( !$group || $group < 1 );
    $group = sprintf( "%02i", $group );

    return LIGHTIFY_sendRaw( $hash, '00', getGroupInfo ." 00 00 00 00 $group 00" );

  } elsif( $cmd eq 'addToGroup' ) {
    return "usage: addToGroup <groupId> <addr> <name>" if( !$args[2] );
    return "usage: <groupId> musst be numeric" if( $args[0] !~ /^\d*$/ );
    return "usage: <groupId> musst be in the range [0-255]" if( $args[0] < 0 || $args[0] > 255 );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[1] !~ /^[A-F0-9]{16}$/i );

    my $group = $args[0];
    $group = 1 if( !$group || $group < 1 );
    $group = sprintf( "%02i", $group );

    my $new = join( ' ', @args[2..@args-1]);

    my $name;
    for( my $i = 0; $i < 15; ++$i ) {
      $name .= sprintf( "%02X ", ord(substr($new,$i,1)) );
    }
    my $length = sprintf( "%02X ", length($name) );

    LIGHTIFY_sendRaw( $hash, '02', addToGroup ." 00 00 00 00 $group 00 $args[1] $length $name" );
    LIGHTIFY_sendRaw( $hash, '00', getGroups ." 00 00 00 00 00" );

    return undef;

  } elsif( $cmd eq 'removeFromGroup' ) {
    return "usage: removeFromGroup <groupId> <addr>" if( !$args[1] );
    return "usage: <groupId> musst be numeric" if( $args[0] !~ /^\d*$/ );
    return "usage: <groupId> musst be in the range [0-255]" if( $args[0] < 0 || $args[0] > 255 );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[1] !~ /^[A-F0-9]{16}$/i );

    my $group = $args[0];
    $group = 1 if( !$group || $group < 1 );
    $group = sprintf( "%02i", $group );

    return LIGHTIFY_sendRaw( $hash, '02', removeFromGroup ." 00 00 00 00 $group 00 $args[1]" );

  } elsif( $cmd eq 'getStatus' ) {
    return "usage: getStatus <addr>" if( !$args[0] );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[0] !~ /^[A-F0-9]{16}$/i );

    return LIGHTIFY_sendRaw( $hash, '00', getStatus ." 00 00 00 00 $args[0]" );

  } elsif( $cmd eq 'goToScene' ) {
    return "usage: goToScene <sceneId>" if( !$args[0] );
    return "usage: <sceneId> musst be numeric" if( $args[0] !~ /^\d*$/ );

    my $scene = $args[0];
    $scene = 1 if( !$scene || $scene < 1 );
    $scene = sprintf( "%02i", $scene );

    LIGHTIFY_sendRaw( $hash, '00', goToScene ." 00 00 00 00 $scene" );

    return LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );

  } elsif( $cmd eq 'saveScene' ) {
    return "usage: saveScene <sceneId>" if( !$args[0] );
    return "usage: <sceneId> musst be numeric" if( $args[0] !~ /^\d*$/ );

    my $scene = $args[0];
    $scene = 1 if( !$scene || $scene < 1 );
    $scene = sprintf( "%02i", $scene );

    return LIGHTIFY_sendRaw( $hash, '02', goToScene ." 00 00 00 00 $scene" );

    return LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );

  } elsif( $cmd eq 'setSoftOn' ) {
    return "usage: setSoftOn <addr> <transitiontime>" if( !defined($args[1]) );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[0] !~ /^[A-F0-9]{16}$/i );
    return "usage: <transitiontime> musst be numeric" if( $args[1] !~ /^\d*$/ );
    return "usage: <transitiontime> musst be in the range [0-255]" if( $args[1] < 0 || $args[1] > 255 );
    my $transitiontime = sprintf( '%02X', $args[1] & 0xff );

    return LIGHTIFY_sendRaw( $hash, '00', setSoftOn ." 00 00 00 00 $args[0] $transitiontime" );

  } elsif( $cmd eq 'setSoftOff' ) {
    return "usage: setSoftOff <addr> <transitiontime>" if( !defined($args[1]) );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[0] !~ /^[A-F0-9]{16}$/i );
    return "usage: <transitiontime> musst be numeric" if( $args[1] !~ /^\d*$/ );
    return "usage: <transitiontime> musst be in the range [0-255]" if( $args[1] < 0 || $args[1] > 255 );
    my $transitiontime = sprintf( '%02X', $args[1] & 0xff );

    return LIGHTIFY_sendRaw( $hash, '00', setSoftOff ." 00 00 00 00 $args[0] $transitiontime" );

  } elsif( $cmd eq 'setPhysical' ) {
    return "usage: setPhysical <addr>" if( !defined($args[0]) );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[0] !~ /^[A-F0-9]{16}$/i );

    return LIGHTIFY_sendRaw( $hash, '00', setPhysical ." 00 00 00 00 $args[0] 00" );

  } elsif( $cmd eq 'setRGBW' ) {
    return "usage: setRGBW <addr> <RRGGBBWW>" if( !defined($args[1]) );
    return "usage: <addr> musst be a 16 hex digit device address" if( $args[0] !~ /^[A-F0-9]{16}$/i );
    return "usage: <RRGGBBWW> musst be a 8 hex digits rgbw color" if( $args[1] !~ /^[A-F0-9]{8}$/i );

    return LIGHTIFY_sendRaw( $hash, '00', setRGB ." 00 00 00 00 $args[0] $args[1] 0200" );

  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
LIGHTIFY_poll($)
{
  my ($hash) = @_;

  RemoveInternalTimer($hash, "LIGHTIFY_poll");
  LIGHTIFY_sendRaw( $hash, '00', getDevices ." 00 00 00 00 01" );
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
    if( $cmd eq 'set' && $attrVal ne "0" ) {
      LIGHTIFY_Disconnect($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      LIGHTIFY_Disconnect($hash);
      LIGHTIFY_Connect($hash);
    }
  }

  if( $cmd eq 'set' ) {
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
    my $a = shift @{$hash->{SEND_QUEUE}};
    if( $a ) {
      $hash->{CL} = $a->[2];
      LIGHTIFY_sendRaw( $hash, $a->[0], $a->[1] ) if( $a );
      delete $hash->{CL};
    }
  }
}
sub
LIGHTIFY_toJson($$$$$$$$$$)
{
  my ($hash,$chash,$id,$reachable,$onoff,$dim,$ct,$r,$g,$b) = @_;

  my $json = { state => { } };

  if( $chash ) {
    $json->{uniqueid} = $id if( defined($id) );
    $json->{state}{on} = $onoff if( defined($onoff) );
    $json->{state}{reachable} = $reachable? 1 : 0 if( defined($reachable) );

    if( !$chash->{helper}{type} ) {
      Log3 $hash->{NAME}, 2, "$chash->{NAME}: unknown light type";
    } elsif( $chash->{helper}{type} == motiondetector ) {
      $json->{type} = 'MotionDetector';
    } elsif( $chash->{helper}{type} == extcolordimmer ) {
      $json->{type} = 'Extended color light';
    } elsif( $chash->{helper}{type} == colordimmer ) {
      $json->{type} = 'Color light';
    } elsif( $chash->{helper}{type} == ctdimmer ) {
      $json->{type} = 'Color temperature tight';
    } elsif( $chash->{helper}{type} == dimmer ) {
      $json->{type} = 'Dimmable';
    } else {
      $json->{type} = 'On/Off';
    }

    my $has_ct = ($chash->{helper}{type} & 0x02) ? 1: 0;
    my $has_rgb = ($chash->{helper}{type} & 0x08) ? 1 : 0;
    my $is_sensor = ($chash->{helper}{type} >= 0x20) ? 1 : 0;
    if( $is_sensor ) {
      $json->{state}->{lastupdated} = TimeNow();
      if( $chash->{helper}{type} == motiondetector ) {
        if( $r eq '01' ) {
          $json->{config}->{on} = 1;
          $json->{state}->{presence} = $g eq '01'?1:0;
        } else {
          $json->{config}->{on} = 0;
        }
      }

    } elsif( $has_rgb ) {
      if( $has_ct && "$r$g$b" eq '111' ) {
        $json->{state}->{colormode} = 'ct';

      } elsif( defined($r) ) {
        my( $r, $g, $b ) = (hex($r)/255.0, hex($g)/255.0, hex($b)/255.0);
        my( $h, $s, $v ) = Color::rgb2hsv($r,$g,$b);

        $json->{state}{colormode} = 'hs';
        $json->{state}{hue} = int( $h * 65535 ),
        $json->{state}{sat} = int( $s * 254 ),
        $json->{state}{bri} = int( $v * 254 ),
      }

    } elsif( $has_ct && $ct ) {
      $json->{state}->{colormode} = 'ct';

    } else {
    }

    $json->{state}{ct} = int(1000000/$ct) if( $ct );

    $json->{state}{bri} = int($dim/100*254) if( defined($dim) );

  }

  return $json;
}
sub
LIGHTIFY_Parse($$)
{
  my ($hash,$hex) = @_;
  my $name = $hash->{NAME};

  $hex = uc($hex);
  Log3 $name, 4, "$name: parsing: $hex";

  my $length = hex(substr($hex,2*1,2*1).substr($hex,2*0,2*1));
  my $flag = substr($hex,2*2,2*1);
  my $cmd = substr($hex,2*3,2*1);
  my $cnt = substr($hex,2*4,2*1);
  my $err = substr($hex,2*8,2*1);

  if( $err ne '00' ) {
    readingsSingleUpdate($hash, 'lastError', "for cmd: $cmd: err: $err", 0 );

    Log3 $name, 3, "$name: got error: $err ";

    return undef;
  }

  if( $cmd eq getDevices ) {
    my $nr_lights = hex(substr($hex,2*10,2*1).substr($hex,2*9,2*1));

    return undef if( !$nr_lights );

    my $offset = ($length+2-11) / $nr_lights;
    Log3 $name, 2, "$name: warning: offset for cmd $cmd is $offset instead of 50" if( $offset != 50 );

    my $autocreated = 0;
    for( my $i = 0; $i < $nr_lights; ++$i ) {
      my $short = substr($hex,$i*$offset*2+2*11,2*2);
      my $id = substr($hex,$i*$offset*2+2*13,2*8);
      my $type = substr($hex,$i*$offset*2+2*21,2*1);
      my $firmware = substr($hex,$i*$offset*2+2*22,2*4);
      my $reachable = hex(substr($hex,$i*$offset*2+2*26,2*1));
      my $groups = (substr($hex,$i*$offset*2+2*28,2*1).substr($hex,$i*$offset*2+2*27,2*1));
      my $onoff = hex(substr($hex,$i*$offset*2+2*29,2*1));
      my $dim = hex(substr($hex,$i*$offset*2+2*30,2*1));
      my $ct = hex(substr($hex,$i*$offset*2+2*32,2*1).substr($hex,$i*$offset*2+2*31,2*1));
      my $r = substr($hex,$i*$offset*2+2*33,2*1);
      my $g = substr($hex,$i*$offset*2+2*34,2*1);
      my $b = substr($hex,$i*$offset*2+2*35,2*1);
      my $w = substr($hex,$i*$offset*2+2*36,2*1);
      my $alias = pack('H*', substr($hex,$i*$offset*2+2*37,2*15));
      $alias =~ s/\x00//g;

      #my $count1 = substr($hex,$i*$offset*2+2*53,2*4); #reportMissingCount
      #my $count2 = substr($hex,$i*$offset*2+2*57,2*4); #pollingCount
      #Log 1, "count1: $count1, count2, $count2";

      my $has_ct = (hex($type) & 0x02) ? 1: 0;
      my $has_rgb = (hex($type) & 0x08) ? 1 : 0;
      my $is_sensor = (hex($type) >= 0x20) ? 1 : 0;
      #$has_ct = 1 if( $type eq '00' );
      Log3 $name, 4, "$alias: $id:$short, type: $type (ct:$has_ct, rgb:$has_rgb, sensor:$is_sensor), firmware: $firmware, reachable: $reachable, groups: $groups, onoff: $onoff, dim: $dim, ct: $ct, rgb: $r$g$b, w: $w";

      #my $code = $id;
      my $code = $name ."-". $id;
      $code = $name ."-S". $id if( $is_sensor );
      if( defined($modules{HUEDevice}{defptr}{$code}) ) {
        Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";

      } else {
        my $devname = "LIGHTIFY" . $id;
        #my $define= "$devname HUEDevice $id";
        my $define= "$devname HUEDevice $id IODev=$name";
        $define= "$devname HUEDevice sensor $id IODev=$name" if( $is_sensor );
        Log3 $name, 4, "$name: create new device '$devname' for address '$id'";
        my $cmdret= CommandDefine(undef,$define);
        if($cmdret) {
          Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";
        } else {
          $cmdret = CommandAttr(undef,"$devname alias ".$alias);
          $cmdret = CommandAttr(undef,"$devname room LIGHTIFY");
          $cmdret = CommandAttr(undef,"$devname IODev $name");

          $autocreated++;
        }
      }

      if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
        $chash->{helper}{type} = hex($type);
        $chash->{helper}{type} = extcolordimmer if( !$chash->{helper}{type} );

        my $json = LIGHTIFY_toJson($hash, $chash, $id, $reachable, $onoff, $dim, $ct, $r, $g, $b);
        my $changed = HUEDevice_Parse( $chash, $json );
        if( $changed || $chash->{helper}{transitiontime} ) {
          RemoveInternalTimer($chash);
          InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
          $chash->{helper}{transitiontime} -= 1 if( $chash->{helper}{transitiontime} );
        }
      }
    }
    if( $autocreated ) {
      Log3 $name, 2, "$name: autocreated $autocreated devices";
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    RemoveInternalTimer($hash, "LIGHTIFY_poll");
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "LIGHTIFY_poll", $hash, 0);

  } elsif( $cmd eq getGroups ) {
    my $nr_groups = hex(substr($hex,2*10,2*1).substr($hex,2*9,2*1));
#Log 1, unpack 'v', pack 'H*', substr($hex,2*9,2*2);
    return undef if( !$nr_groups );

    my $offset = ($length+2-11) / $nr_groups;
    Log3 $name, 2, "$name: warning: offset for cmd $cmd is $offset instead of 18" if( $offset != 18 );

    my @groups;
    my $autocreated = 0;
    for( my $i = 0; $i <= $nr_groups; ++$i ) {
      my $id;
      my $alias;

      if( $i == 0 ) {
        $id = 0;
        $alias = 'Gruppe alles';
      } else {
        $id = hex(substr($hex,($i-1)*$offset*2+2*12,2*1).substr($hex,($i-1)*$offset*2+2*11,2*1));
        $alias = pack('H*', substr($hex,($i-1)*$offset*2+2*13,2*15));
        $alias =~ s/\x00//g;

        my $group = sprintf( "%02X", $id );
        $hash->{CL} = $hash->{helper}{CL};
        LIGHTIFY_sendRaw( $hash, '00', getGroupInfo ." 00 00 00 00 $group 00" );
        delete $hash->{CL};
      }
      push @groups, "$id: $alias";

      #my $code = $id;
      my $code = $name ."-G". $id;
      if( defined($modules{HUEDevice}{defptr}{$code}) ) {
        Log3 $name, 5, "$name: id '$id' already defined as '$modules{HUEDevice}{defptr}{$code}->{NAME}'";

      } else {
        my $devname = "LIGHTIFYGroup" . $id;
        my $define= "$devname HUEDevice group $id IODev=$name";
        Log3 $name, 4, "$name: create new device '$devname' for group nr. '$id'";
        my $cmdret= CommandDefine(undef,$define);
        if($cmdret) {
          Log3 $name, 1, "$name: Autocreate: An error occurred while creating device for id '$id': $cmdret";

        } else {
          $cmdret = CommandAttr(undef,"$devname alias ".$alias);
          $cmdret = CommandAttr(undef,"$devname room LIGHTIFY");
          $cmdret = CommandAttr(undef,"$devname IODev $name");

          $cmdret = CommandAttr(undef,"$devname subType switch") if( $id == 0 );

          $autocreated++;
        }
      }
    }
    Log3 $name, 4, "groups: " .join( ', ', @groups );

    if( $autocreated ) {
      Log3 $name, 2, "$name: autocreated $autocreated groups";
      CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    asyncOutput( $hash->{helper}{CL}, "got groups: ". join( ', ', @groups ) ) if( $hash->{helper}{CL} );

  } elsif( $cmd eq getGroupInfo ) {
    my $nr = hex(substr($hex,2*10,2*1).substr($hex,2*9,2*1));
    my $alias = pack('H*', substr($hex,2*11,2*15));
    my $nr_lights = hex(substr($hex,2*27,2*1));
    return undef if( !$nr_lights );

    $alias =~ s/\x00//g;

    my $offset = ($length+2-28) / $nr_lights; # should be 8
    Log3 $name, 2, "$name: warning: offset for cmd $cmd is $offset instead of 8" if( $offset != 8 );

    my @lights;
    for( my $i = 0; $i < $nr_lights; ++$i ) {
      my $light = substr($hex,$i*$offset*2+2*28,2*8);
      push @lights, $light;
    }
    Log3 $name, 4, "group $nr: alias: $alias, lights: " .join( ',', @lights );

    my $code = $name ."-G". $nr;
    if( my $chash = $modules{HUEDevice}{defptr}{$code} ) {
      $chash->{lights} = join( ',', @lights );
    }

    asyncOutput( $hash->{helper}{CL}, "group info: $nr: $alias, lights: ". join( ', ', @lights ) ) if( $hash->{helper}{CL} );

  } elsif( $cmd eq setOnOff ) {
    my $id = substr($hex,2*11,2*8);
    my $onoff = hex(substr($hex,2*19,2*1));

  } elsif( $cmd eq getStatus ) {
      my $id = substr($hex,2*11,2*8);

      my $json;

      my $code = $name ."-". $id;
      my $chash = $modules{HUEDevice}{defptr}{$code};
      if( !$chash ) {
        $code = $name ."-S". $id;
        $chash = $modules{HUEDevice}{defptr}{$code};
      }

      if( $length < 30 ) {
        $json = { state => { } };

        if( substr($hex,2*19,2*1) eq 'FF' ) {
          Log3 $name, 4, "$id, not reachable";

          $json = { state => { reachable => 0 } };
        }

      } else {

        my $reachable = hex(substr($hex,2*20,2*1));

        my $onoff = hex(substr($hex,2*21,2*1));
        my $dim = hex(substr($hex,2*22,2*1));
        my $ct = hex(substr($hex,2*24,2*1).substr($hex,2*23,2*1));
        my $r = substr($hex,2*25,2*1);
        my $g = substr($hex,2*26,2*1);
        my $b = substr($hex,2*27,2*1);
        my $w = substr($hex,2*28,2*1);

        Log3 $name, 4, "$id, reachable: $reachable, onoff: $onoff, dim: $dim, ct: $ct, rgb: $r$g$b, w: $w";

        $json = LIGHTIFY_toJson($hash, $chash, $id, $reachable, $onoff, $dim, $ct, $r, $g, $b);

      }
    my $changed = HUEDevice_Parse( $chash, $json ) if( $chash );
    if( $changed || $chash->{helper}{transitiontime} ) {
      RemoveInternalTimer($chash);
      InternalTimer(gettimeofday()+1, "HUEDevice_GetUpdate", $chash, 0);
      $chash->{helper}{transitiontime} -= 1 if( $chash->{helper}{transitiontime} );
    }

  } else {
    Log3 $name, 4, "$name: unhandled message $hex ";

  }
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
  Log3 $name, 5, "$name: received: $hex";

  $hash->{PARTIAL} .= $hex;
  my $length = hex(substr($hash->{PARTIAL},2*1,2*1).substr($hash->{PARTIAL},2*0,2*1));

  while( $hash->{PARTIAL} && $length+2 <= length($hash->{PARTIAL})/2  ) {
    $hex = substr($hash->{PARTIAL},0,$length*2+2*2);
    $hash->{PARTIAL} = substr($hash->{PARTIAL},$length*2+2*2);
    $length = hex(substr($hash->{PARTIAL},2*1,2*1).substr($hash->{PARTIAL},2*0,2*1)) if( $hash->{PARTIAL} );

    LIGHTIFY_Parse($hash, $hex);
  }

  readingsSingleUpdate($hash, 'state', $hash->{READINGS}{state}{VAL}, 0);

  LIGHTIFY_sendNext( $hash ) if( !$hash->{PARTIAL} );
  #RemoveInternalTimer($hash);
  #InternalTimer(gettimeofday()+2, "LIGHTIFY_sendNext", $hash, 0);
}

1;

=pod
=item tag protocol:zigbee
=item summary    module for the osram lightify gateway
=item summary_DE Modul f&uuml;r das Osram LIGHTFY Gateway
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
      <code>define gateway LIGHTIFY 10.0.1.100</code><br>
    </ul>
  </ul><br>

  <a name="LIGHTIFY_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="LIGHTIFY_Set"></a>
  <b>Set</b>
  <ul>
    <li>on</li>
    <li>off</li>

    <li>goToScene &lt;sceneId&gt;</li>

    <li>setSoftOn &lt;addr&gt; &lt;transitiontime&gt;</li>
    <li>setSoftOff &lt;addr&gt; &lt;transitiontime&gt;</li>

    <li>reconnect<br>
      Closes and reopens the connection to the gateway.</li>

    <li>statusRequest<br>
      Update light status.</li>
  </ul><br>

  <a name="LIGHTIFY_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
  </ul><br>

</ul><br>

=end html
=cut

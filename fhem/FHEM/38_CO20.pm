
# $Id$

# basic idea from http://code.google.com/p/airsensor-linux-usb

package main;

use strict;
use warnings;

use Device::USB;

sub
CO20_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "CO20_Define";
  $hash->{NOTIFYDEV} = "global";
  $hash->{NotifyFn} = "CO20_Notify";
  $hash->{UndefFn}  = "CO20_Undefine";
  #$hash->{SetFn}    = "CO20_Set";
  $hash->{GetFn}    = "CO20_Get";
  $hash->{AttrFn}   = "CO20_Attr";
  $hash->{AttrList} = "disable:1 ".
                      "interval ".
                      $readingFnAttributes;
}

#####################################

sub
CO20_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> CO20 [bus:device]"  if(@a < 2);

  delete $hash->{ID};

  my $name = $a[0];

  $hash->{tag} = undef;
  $hash->{ID} = $a[2] if( defined($a[2]));

  $hash->{NAME} = $name;

  if( $init_done ) {
    CO20_Disconnect($hash);
    CO20_Connect($hash);
  } elsif( $hash->{STATE} ne "???" ) {
    $hash->{STATE} = "Initialized";
  }

  return undef;
}

sub
CO20_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  CO20_Connect($hash);
}

my $VENDOR = 0x03eb;
my $PRODUCT = 0x2013;

sub
CO20_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return undef if( AttrVal($name, "disable", 0 ) == 1 );

  $hash->{USB} = Device::USB->new() if( !$hash->{USB} );

  if( $hash->{ID} =~ m/(\d.*):(\d.*)/ ) {
    my $dirname = $1;
    my $filename = $2;
    delete $hash->{DEV};
    foreach my $bus ($hash->{USB}->list_busses()) {
      next if( $bus->{dirname} != $dirname );

      foreach my $device (@{$bus->{devices}}) {
        next if( $device->idVendor() != $VENDOR );
        next if( $device->idProduct() != $PRODUCT );
        next if( $device->{filename} != $filename );
        $hash->{DEV} = $device;
        last;
      }
      last if( $hash->{DEV} );
    }

  } else {
    $hash->{DEV} = $hash->{USB}->find_device( $VENDOR, $PRODUCT );
  }

  if( $hash->{DEV} ) {
    $hash->{STATE} = "found";
    Log3 $name, 3, "$name: CO20 device found";

    $hash->{DEV}->open();

    $hash->{manufacturer} = $hash->{DEV}->manufacturer();
    $hash->{product} = $hash->{DEV}->product();

    if( $hash->{manufacturer} && $hash->{product} ) {
       $hash->{DEV}->detach_kernel_driver_np(0) if( $hash->{DEV}->get_driver_np(0) );
       my $ret = $hash->{DEV}->claim_interface( 0 );
       if( $ret == -16 ) {
         $hash->{STATE} = "waiting";
         Log3 $name, 3, "$name: waiting for CO20 device";
         return;
       } elsif( $ret != 0 ) {
         Log3 $name, 3, "$name: failed to claim CO20 device";
         CO20_Disconnect($hash);
       }

      $hash->{STATE} = "opened";
      Log3 $name, 3, "$name: CO20 device opened";

      my $interval = AttrVal($name, "interval", 0);
      $interval = 60*5 if( !$interval );
      $hash->{INTERVAL} = $interval;

      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+10, "CO20_poll", $hash, 0);

      my $buf;
      $hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, 1000);

    } else {
      Log3 $name, 3, "$name: failed to open CO20 device";
      CO20_Disconnect($hash);
    }
  } else {
    Log3 $name, 3, "$name: filed to find CO20 device";
  }
}

sub
CO20_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);

  return if( !$hash->{USB} );
  if( $hash->{manufacturer} && $hash->{product} ) {
    $hash->{DEV}->release_interface(0);
  }

  delete( $hash->{USB} );
  delete( $hash->{DEV} );
  delete( $hash->{manufacturer} );
  delete( $hash->{product} );

  $hash->{STATE} = "disconnected";
  Log3 $name, 3, "$name: disconnected";
}

sub
CO20_Undefine($$)
{
  my ($hash, $arg) = @_;

  CO20_Disconnect($hash);

  return undef;
}

sub
CO20_Set($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "";
  return "Unknown argument $cmd, choose one of $list";
}

sub
CO20_poll($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "CO20_poll", $hash, 0);
  }

  if( $hash->{manufacturer} && $hash->{product} ) {
    my $buf = "\x40\x68\x2a\x54\x52\x0a\x40\x40\x40\x40\x40\x40\x40\x40\x40\x40";
    my $ret = $hash->{DEV}->interrupt_write(0x00000002, $buf, 0x0000010, 1000);

    $ret = $hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, 1000);
    if( $ret == 16 ) {
      my $voc = ord(substr($buf,3,1))*256 + ord(substr($buf,2,1));
      readingsSingleUpdate($hash, "voc", $voc, 1 );
      $hash->{DEV}->interrupt_read(0x00000081, $buf, 0x0000010, 1000);
    } else {
      Log3 $name, 3, "$name: read failed";
      CO20_Disconnect($hash);
      CO20_Connect($hash);
    }

    $hash->{LAST_POLL} = FmtDateTime( gettimeofday() );
  } else {
    CO20_Disconnect($hash);
    CO20_Connect($hash);
  }
}


sub
CO20_Get($$@)
{
  my ($hash, $name, $cmd) = @_;

  my $list = "update:noArg";

  if( $cmd eq "update" ) {
      $hash->{LOCAL} = 1;
      CO20_poll($hash);
      delete $hash->{LOCAL};
      return undef;
  }

  return "Unknown argument $cmd, choose one of $list";
}

sub
CO20_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  my $orig = $attrVal;
  $attrVal = int($attrVal) if($attrName eq "interval");
  $attrVal = 60 if($attrName eq "interval" && $attrVal < 60 && $attrVal != 0);

  if( $attrName eq "disable" ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      CO20_Disconnect($hash);
    } else {
      $attr{$name}{$attrName} = 0;
      CO20_Disconnect($hash);
      CO20_Connect($hash);
    }
  } elsif( $attrName eq "interval" ) {
    my $hash = $defs{$name};
    $hash->{INTERVAL} = $attrVal;
    CO20_poll($hash) if( $init_done );
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

<a name="CO20"></a>
<h3>CO20</h3>
<ul>
  Module for measuring air quality with usb sticks based on the AppliedSensor iAQ-Engine sensor.
  Products currently know to work are the VOLTCRAFT CO-20 and the Sentinel Haus Institut RaumluftW&auml;chter.
  Probably works with all devices recognized as iAQ Stick (0x03eb:0x2013).<br><br>

  Notes:
  <ul>
    <li>Device::USB hast to be installed on the FHEM host.<br>
        It can be installed with '<code>cpan install Device::USB</code>'<br>
        or on debian with '<code>sudo apt-get install libdevice-usb-perl'</code>'</li>
    <li>FHEM has to have permissions to open the device. To configure this with udev
        rules see here: <a href="https://code.google.com/p/usb-sensors-linux/wiki/Install_AirSensor_Linux">Install_AirSensor_Linux
usb-sensors-linux</a></li>
  </ul><br>

  <a name="CO20_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CO20 [bus:device]</code><br>
    <br>

    Defines a CO20 device. bus:device hast to be used if more than one sensor is connected to the same host.<br><br>

    Examples:
    <ul>
      <code>define CO20 CO20</code><br>
    </ul>
  </ul><br>

  <a name="CO20_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>voc</br>
      CO2 equivalents in the range of 450-2000ppm.</li>
  </ul><br>

  <a name="CO20_Get"></a>
  <b>Get</b>
  <ul>
    <li>update<br>
      trigger an update</li>
  </ul><br>

  <a name="CO20_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>interval<br>
      the interval in seconds used to read updates. the minimum and default ist 60.</li>
    <li>disable<br>
      1 -> disconnect and stop polling</li>
  </ul>
</ul>

=end html
=cut

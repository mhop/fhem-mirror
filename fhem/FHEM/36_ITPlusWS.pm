
# $Id$
#
# TODO: Add the rest of the readings
#       Autocreate
#       Replace battery
#       ignore
#       doAverage

package main;

use strict;
use warnings;
use SetExtensions;

sub ITPlusWS_Parse($$);

#####################################
sub ITPlusWS_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}         = "^OK\\sWS\\s";
  $hash->{DefFn}         = "ITPlusWS_Define";
  $hash->{UndefFn}       = "ITPlusWS_Undef";
  $hash->{FingerprintFn} = "ITPlusWS_Fingerprint";
  $hash->{ParseFn}       = "ITPlusWS_Parse";
  $hash->{AttrList}      = "IODev"
                         ." ignore:1"
                         ." doAverage:1"
                         ." $readingFnAttributes";
}

#####################################
sub ITPlusWS_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3 ) {
    my $msg = "wrong syntax: define <name> ITPlusWS <addr>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{2})$/i;
  return "$a[2] is not a valid ITPlusWS address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  return "ITPlusWS device $addr already used for $modules{ITPlusWS}{defptr}{$addr}->{NAME}." if( $modules{ITPlusWS}{defptr}{$addr} && $modules{ITPlusWS}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{ITPlusWS}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }
    
  return undef;
}

#####################################
sub ITPlusWS_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{ITPlusWS}{defptr}{$addr} );

  return undef;
}


#####################################
sub ITPlusWS_Get($@) {
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

#####################################
sub ITPlusWS_Fingerprint($$) {
  my ($name, $msg) = @_;

  return ( "", $msg );
}

# Format
#         0   1   2   3   4   5   6   7   8   9   10 
#   ------------------------------------------------------
#   OK WS 60  1   4   193 52  2   88  4   101 15  20      ID=60  21.7°C  52%rH  600mm  Dir.: 112.5°  Wind:15m/s  Gust:20m/s 
#   OK WS ID  XXX TTT TTT HHH RRR RRR DDD DDD SSS GGG FFF
#   |  |  |   |   |   |   |   |   |   |   |   |   |   |-- Flags *
#   |  |  |   |   |   |   |   |   |   |   |   |   |------ WindGust (0 ... 50 m/s)                        255 = none
#   |  |  |   |   |   |   |   |   |   |   |   |---------- WindSpeed (0 ... 50 m/s)                       255 = none
#   |  |  |   |   |   |   |   |   |   |   |-------------- WindDirection * 10 LSB (0.0 ... 365.0 Degrees) 255/255 = none
#   |  |  |   |   |   |   |   |   |   |------------------ WindDirection * 10 MSB
#   |  |  |   |   |   |   |   |   |---------------------- Rain LSB (0 ... 9999 mm)                       255/255 = none
#   |  |  |   |   |   |   |   |-------------------------- Rain MSB
#   |  |  |   |   |   |   |------------------------------ Humidity (1 ... 99 %rH)                        255 = none
#   |  |  |   |   |   |---------------------------------- Temp * 10 + 1000 LSB (-40 ... +60 °C)          255/255 = none
#   |  |  |   |   |-------------------------------------- Temp * 10 + 1000 MSB
#   |  |  |   |------------------------------------------ Sensor type (1=TX22)
#   |  |  |---------------------------------------------- Sensor ID (1 ... 63)
#   |  |------------------------------------------------- fix "WS"
#   |---------------------------------------------------- fix "OK"
#
#   * Flags: 777 666 555 444 333 222 111 000        
#                                     |   |
#                                     |   |-- New battery
#                                     |------ ERROR

sub ITPlusWS_Parse($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  my( @bytes, $addr, $typeNumber, $typeName);
  if( $msg =~ m/^OK WS/ ) {
    @bytes = split( ' ', substr($msg, 5) );

    $addr = sprintf( "%01X", $bytes[0] );
    $typeNumber = $bytes[1];
    $typeName = $typeNumber == 1 ? "TX22" : "unknown";
  } 
  else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return undef;
  }

  my $raddr = $addr;
  my $rhash = $modules{ITPlusWS}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;
  
  if( !$modules{ITPlusWS}{defptr}{$raddr} ) {    
    Log3 $name, 3, "ITPlusWS Unknown device $rname, please define it";

    my $iohash = $rhash->{IODev};

    return undef;
  }

  my @list;
  push(@list, $rname);

  $rhash->{ITPlusWS_lastRcv} = TimeNow();

  readingsBeginUpdate($rhash);
    
  readingsBulkUpdate($rhash, "message", $msg);
  readingsBulkUpdate($rhash, "sensorType", "$typeNumber=$typeName");
  
  my $temperature = ($bytes[2]*256 + $bytes[3] - 1000)/10;
  readingsBulkUpdate($rhash, "temperature", $temperature);



  
  my $state = "ID: $bytes[0]";
  readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );

  readingsEndUpdate($rhash,1);

  return @list;
}

#####################################
sub ITPlusWS_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="ITPlusWS"></a>
<h3>ITPlusWS</h3>

<ul>
  <tr><td>
  <u><b>!!! This module is under development and will be finished soon</b></u><br><br>
  
  FHEM module for WS 1600<br><br>
  
  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br>
  The JeeNode sketch required for this module can be found in .../contrib/36_LaCrosse-LaCrosseITPlusReader.zip. It must be at least version 10.1i<br>
  For more information see: http://forum.fhem.de/index.php/topic,14786.0.html<br><br>
  
  <a name="ITPlusWS_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ITPlusWS &lt;addr&gt;</code> <br>
    addr is a 2 digit hex number to identify the device.
    <br><br>
  </ul>
  
  <a name="ITPlusWS_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>Tremperature</li>
    <li>Humidity</li>
    <li>Wind speed, gust and direction</li>
    <li>Rain</li>
  </ul><br>

  <a name="ITPlusWS_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>None</li>
  </ul><br>
</ul>

=end html
=cut

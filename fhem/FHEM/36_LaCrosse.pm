
# $Id$
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

sub LaCrosse_Parse($$);

sub
LaCrosse_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^\\S+\\s+9 ";
  #$hash->{SetFn}     = "LaCrosse_Set";
  #$hash->{GetFn}     = "LaCrosse_Get";
  $hash->{DefFn}     = "LaCrosse_Define";
  $hash->{UndefFn}   = "LaCrosse_Undef";
  $hash->{FingerprintFn}   = "LaCrosse_Fingerprint";
  $hash->{ParseFn}   = "LaCrosse_Parse";
  #$hash->{AttrFn}    = "LaCrosse_Attr";
  $hash->{AttrList}  = "IODev"
                       ." ignore:1"
                       ." filterThreshold"
                       ." $readingFnAttributes";
}

sub
LaCrosse_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3 ) {
    my $msg = "wrong syntax: define <name> LaCrosse <addr>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{2})$/i;
  return "$a[2] is not a valid LaCrosse address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  #return "$addr is not a 1 byte hex value" if( $addr !~ /^[\da-f]{2}$/i );
  #return "$addr is not an allowed address" if( $addr eq "00" );

  return "LaCrosse device $addr already used for $modules{LaCrosse}{defptr}{$addr}->{NAME}." if( $modules{LaCrosse}{defptr}{$addr}
                                                                                             && $modules{LaCrosse}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{LaCrosse}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  return undef;
}

#####################################
sub
LaCrosse_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{LaCrosse}{defptr}{$addr} );

  return undef;
}


#####################################
sub
LaCrosse_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
LaCrosse_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}

sub
LaCrosse_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  my( @bytes, $addr, $battery_new, $type, $channel, $temperature, $battery_low, $humidity );
  if( $msg =~ m/^OK/ ) {
    @bytes = split( ' ', substr($msg, 5) );

    $addr = sprintf( "%02X", $bytes[0] );
    $battery_new = ($bytes[1] & 0x80) >> 7;
    $type = ($bytes[1] & 0x70) >> 4;
    $channel = $bytes[1] & 0x0F;
    $temperature = ($bytes[2]*256 + $bytes[3] - 1000)/10;
    $battery_low = ($bytes[4] & 0x80) >> 7;
    $humidity = $bytes[4] & 0x7f;
  } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return undef;
  }

  my $raddr = $addr;
  my $rhash = $modules{LaCrosse}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;

  if( !$modules{LaCrosse}{defptr}{$raddr} ) {
    Log3 $name, 3, "LaCrosse Unknown device $rname, please define it";

    my $iohash = $rhash->{IODev};
    return undef if( !$iohash->{LaCrossePair} );

    return "UNDEFINED LaCrosse_$rname LaCrosse $raddr" if( $battery_new || $iohash->{LaCrossePair} == 2 );
    return undef;
  }

  $rhash->{battery_new} = $battery_new;

  my @list;
  push(@list, $rname);

  $rhash->{LaCrosse_lastRcv} = TimeNow();

  if( $type == 0x00 ) {
    $channel = "" if( $channel == 1 );

    if( defined($rhash->{"previousT$channel"})
        && abs($rhash->{"previousH$channel"} - $humidity) <= AttrVal( $rname, "filterThreshold", 10 )
        && abs($rhash->{"previousT$channel"} - $temperature) <= AttrVal( $rname, "filterThreshold", 10 ) ) {
      readingsBeginUpdate($rhash);
      readingsBulkUpdate($rhash, "temperature$channel", $temperature);
      readingsBulkUpdate($rhash, "humidity$channel", $humidity) if( $humidity && $humidity != 99 );
      if( !$channel ) {
        my $state = "T: $temperature";
        $state .= " H: $humidity" if( $humidity && $humidity != 99 );
        readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );
      }
      readingsBulkUpdate($rhash, "battery$channel", $battery_low?"low":"ok");
      readingsEndUpdate($rhash,1);
    }

    $rhash->{"previousH$channel"} = $humidity;
    $rhash->{"previousT$channel"} = $temperature;
  }

  return @list;
}

sub
LaCrosse_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="LaCrosse"></a>
<h3>LaCrosse</h3>
<ul>

  <tr><td>
  FHEM module for LaCrosse Temperature and Humidity sensors.<br><br>

  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  The JeeNode sketch required for this module can be found in .../contrib/36_LaCrosse-pcaSerial.zip.<br><br>

  <a name="LaCrosseDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LaCrosse &lt;addr&gt;</code> <br>
    <br>
    addr is a 2 digit hex number to identify the LaCrosse device.<br><br>
    Note: devices are autocreated only if LaCrossePairForSec is active for the <a href="#JeeLink">JeeLink</a> IODevice device.<br>
  </ul>
  <br>

  <a name="LaCrosse_Set"></a>
  <b>Set</b>
  <ul>
  </ul><br>

  <a name="LaCrosse_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="LaCrosse_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>battery[]<br>
      ok or low</li>
    <li>temperature[]<br>
      Notice: see the filterThreshold attribute.</li>
    <li>humidity</li>
  </ul><br>

  <a name="LaCrosse_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>filterThreshold<br>
      if the difference between the current and previous temperature is greater than filterThreshold degrees
      the readings for this channel are not updated. the default is 10.</li>
    <li>ignore<br>
    1 -> ignore this device.</li>
  </ul><br>
</ul>

=end html
=cut

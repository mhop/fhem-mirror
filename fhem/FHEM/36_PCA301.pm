
# $Id$
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

sub PCA301_Parse($$);
sub PCA301_Send($$@);

sub
PCA301_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^\\S+\\s+24";
  $hash->{SetFn}     = "PCA301_Set";
  #$hash->{GetFn}     = "PCA301_Get";
  $hash->{DefFn}     = "PCA301_Define";
  $hash->{UndefFn}   = "PCA301_Undef";
  $hash->{FingerprintFn}   = "PCA301_Fingerprint";
  $hash->{ParseFn}   = "PCA301_Parse";
  $hash->{AttrFn}    = "PCA301_Attr";
  $hash->{AttrList}  = "IODev".
                       " $readingFnAttributes";
}

sub
PCA301_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 4 ) {
    my $msg = "wrong syntax: define <name> PCA301 <addr> <channel>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/^([\da-f]{6})$/i;
  return "$a[2] is not a valid PCA301 address" if( !defined($1) );

  $a[3] =~ m/^([\da-f]{2})$/i;
  return "$a[3] is not a valid PCA301 channel" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];
  my $channel = $a[3];

  #return "$addr is not a 1 byte hex value" if( $addr !~ /^[\da-f]{2}$/i );
  #return "$addr is not an allowed address" if( $addr eq "00" );

  return "PCA301 device $addr already used for $modules{PCA301}{defptr}{$addr}->{NAME}." if( $modules{PCA301}{defptr}{$addr}
                                                                                             && $modules{PCA301}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;
  $hash->{channel} = $channel;

  $modules{PCA301}{defptr}{$addr} = $hash;

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  $attr{$name}{devStateIcon} = 'on:on:toggle off:off:toggle .*:light_question:off' if( !defined( $attr{$name}{devStateIcon} ) );
  $attr{$name}{webCmd} = 'on:off:toggle:statusRequest' if( !defined( $attr{$name}{webCmd} ) );
  CommandAttr( undef, "$name userReadings consumptionTotal:consumption monotonic {ReadingsVal(\$name,'consumption',0)}" ) if( !defined( $attr{$name}{userReadings} ) );

  #PCA301_Send($hash, $addr, "00" );

  return undef;
}

#####################################
sub
PCA301_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{PCA301}{defptr}{$addr} );

  return undef;
}

#####################################
sub
PCA301_Set($@)
{
  my ($hash, $name, @aa) = @_;

  my $cnt = @aa;

  return "\"set $name\" needs at least one parameter" if($cnt < 1);

  my $cmd = $aa[0];
  my $arg = $aa[1];
  my $arg2 = $aa[2];
  my $arg3 = $aa[3];

  my $list = "identify:noArg off:noArg on:noArg toggle:noArg reset:noArg statusRequest:noArg";

  if( $cmd eq 'toggle' ) {
    $cmd = ReadingsVal($name,"state","on") eq "off" ? "on" :"off";
  }

  if( $cmd eq 'off' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    PCA301_Send( $hash, 0x05, 0x00 );
  } elsif( $cmd eq 'on' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    PCA301_Send( $hash, 0x05, 0x01 );
  } elsif( $cmd eq 'statusRequest' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    PCA301_Send( $hash, 0x04, 0x00 );
  } elsif( $cmd eq 'reset' ) {
    readingsSingleUpdate($hash, "state", "set-$cmd", 1);
    PCA301_Send( $hash, 0x04, 0x01 );
  } elsif( $cmd eq 'identify' ) {
    PCA301_Send( $hash, 0x06, 0x00 );
  } else {
    return SetExtensions($hash, $list, $name, @aa);
  }

  return undef;
}

#####################################
sub
PCA301_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
PCA301_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}


sub
PCA301_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  #return undef if( $msg !~ m/^[\dA-F]{12,}$/ );

  if( $msg =~ m/^L/ ) {
    my @parts = split( ' ', substr($msg, 5), 4 );
    $msg = "OK 24 $parts[3]";
  }

  my( @bytes, $channel,$cmd,$addr,$data,$power,$consumption );
  if( $msg =~ m/^OK/ ) {
    @bytes = split( ' ', substr($msg, 6) );

    $channel = sprintf( "%02X", $bytes[0] );
    $cmd = $bytes[1];
    $addr = sprintf( "%02X%02X%02X", $bytes[2], $bytes[3], $bytes[4] );
    $data = $bytes[5];
    return "" if( $cmd == 0x04 && $bytes[6] == 170 && $bytes[7] == 170 && $bytes[8] == 170 && $bytes[9] == 170 ); # ignore commands from display unit
    return "" if( $cmd == 0x05 && ( $bytes[6] != 170 || $bytes[7] != 170 || $bytes[8] != 170 || $bytes[9] != 170 ) ); # ignore commands not from the plug
  } elsif ( $msg =~ m/^TX/ ) {
    # ignore TX
    return "";
  } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return undef;
  }

  my $raddr = $addr;
  my $rhash = $modules{PCA301}{defptr}{$raddr};
  my $rname = $rhash?$rhash->{NAME}:$raddr;

   if( !$modules{PCA301}{defptr}{$raddr} ) {
     Log3 $name, 3, "PCA301 Unknown device $rname, please define it";

     return "UNDEFINED PCA301_$rname PCA301 $raddr $channel";
   }

  #CommandAttr( undef, "$rname userReadings consumptionTotal:consumption monotonic {ReadingsVal($rname,'consumption',0)}" ) if( !defined( $attr{$rname}{userReadings} ) );

  my @list;
  push(@list, $rname);

  $rhash->{PCA301_lastRcv} = TimeNow();

  if( $cmd eq 0x04 ) {
    my $state = $data==0x00?"off":"on";
    my $power = ($bytes[6]*256 + $bytes[7]) / 10.0;
    my $consumption = ($bytes[8]*256 + $bytes[9]) / 100.0;
    readingsBeginUpdate($rhash);
    readingsBulkUpdate($rhash, "power", $power) if( $data != 0x00 || ReadingsVal($rname,"power","") != $power );
    readingsBulkUpdate($rhash, "consumption", $consumption) if( ReadingsVal($rname,"consumption","") != $consumption );
    readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );
    readingsEndUpdate($rhash,1);
  } elsif( $cmd eq 0x05 ) {
    my $state = $data==00?"off":"on";

    readingsSingleUpdate($rhash, "state", $state, 1)
  }

  return @list;
}
sub
PCA301_Send($$@)
{
  my ($hash, $cmd, $data) = @_;

  $hash->{PCA301_lastSend} = TimeNow();

  my $msg = sprintf( "%i,%i,%i,%i,%i,%i,255,255,255,255s", hex($hash->{channel}),
                                                           $cmd,
                                                           hex(substr($hash->{addr},0,2)), hex(substr($hash->{addr},2,2)), hex(substr($hash->{addr},4,2)),
                                                           $data );

  IOWrite( $hash, $msg );
}

sub
PCA301_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="PCA301"></a>
<h3>PCA301</h3>
<ul>

  <tr><td>
  The PCA301 is a RF controlled AC mains plug with integrated power meter functionality from ELV.<br><br>

  It can be integrated in to FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  The JeeNode sketch required for this module can be found in .../contrib/36_PCA301-pcaSerial.zip.<br><br>

  <a name="PCA301Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PCA301 &lt;addr&gt; &lt;channel&gt;</code> <br>
    <br>
    addr is a 6 digit hex number to identify the PCA301 device.
    channel is a 2 digit hex number to identify the PCA301 device.<br><br>
    Note: devices are autocreated on reception of the first message.<br>
  </ul>
  <br>

  <a name="PCA301_Set"></a>
  <b>Set</b>
  <ul>
    <li>on</li>
    <li>off</li>
    <li>identify<br>
      Blink the status led for ~5 seconds.</li>
    <li>reset<br>
      Reset consumption counters</li>
    <li>statusRequest<br>
      Request device status update.</li>
    <li><a href="#setExtensions"> set extensions</a> are supported.</li>
  </ul><br>

  <a name="PCA301_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="PCA301_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>power</li>
    <li>consumption</li>
    <li>consumptionTotal<br>
      will be created as a default user reading to have a continous consumption value that is not influenced
      by the regualar reset or overflow of the normal consumption reading</li>
  </ul><br>

  <a name="PCA301_Attr"></a>
  <b>Attributes</b>
  <ul>
  </ul><br>
</ul>

=end html
=cut

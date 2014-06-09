
# $Id$
#
# TODO:

package main;

use strict;
use warnings;
use SetExtensions;

sub EMT7110_Parse($$);

sub
EMT7110_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^OK\\sEMT7110\\s";
  $hash->{SetFn}     = "EMT7110_Set";
  #$hash->{GetFn}     = "EMT7110_Get";
  $hash->{DefFn}     = "EMT7110_Define";
  $hash->{UndefFn}   = "EMT7110_Undef";
  $hash->{FingerprintFn}   = "EMT7110_Fingerprint";
  $hash->{ParseFn}   = "EMT7110_Parse";
  $hash->{AttrFn}    = "EMT7110_Attr";
  $hash->{AttrList}  = "IODev".
                       " accumulatedPowerOffset".
                       " pricePerKWH".
                       " $readingFnAttributes";
}

sub
EMT7110_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3 ) {
    my $msg = "wrong syntax: define <name> EMT7110 <addr>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  $a[2] =~ m/(\d|[abcdef]|[ABCDEF]){4}/i;
  return "$a[2] is not a valid EMT7110 address" if( !defined($1) );

  my $name = $a[0];
  my $addr = $a[2];

  
  return "EMT7110 device $addr already used for $modules{EMT7110}{defptr}{$addr}->{NAME}." if( $modules{EMT7110}{defptr}{$addr}
                                                                                             && $modules{EMT7110}{defptr}{$addr}->{NAME} ne $name );

  $hash->{addr} = $addr;

  $modules{EMT7110}{defptr}{$addr} = $hash;

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
EMT7110_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  my $addr = $hash->{addr};

  delete( $modules{EMT7110}{defptr}{$addr} );

  return undef;
}

#####################################
sub
EMT7110_Get($@)
{
  my ($hash, $name, $cmd, @args) = @_;

  return "\"get $name\" needs at least one parameter" if(@_ < 3);

  my $list = "";

  return "Unknown argument $cmd, choose one of $list";
}

sub
EMT7110_Fingerprint($$)
{
  my ($name, $msg) = @_;

  return ( "", $msg );
}

#  // Format
#  // 
#  // OK  EMT7110  84 81  8  237 0  13  0  2   1  6  1  -> ID 5451   228,5V   13mA   2W   2,62kWh
#  // OK  EMT7110  84 81  8  247 1  12  0  56  1  13 1  -> ID 5451   229,5V  268mA  56W   2,69kWh  
#  // OK  EMT7110  ID ID  VV VV  AA AA  WW WW  KW KW Flags
#  //     |        |  |   |  |   |  |   |  |   |  |  `--- Bit0: Connected Bit1: Pairing  
#  //     |        |  |   |  |   |  |   |  |   |   `--- AccumulatedPower * 100 LSB
#  //     |        |  |   |  |   |  |   |  |    `------ AccumulatedPower * 100 MSB
#  //     |        |  |   |  |   |  |   |   `--- Power (W) LSB
#  //     |        |  |   |  |   |  |    `------ Power (W) MSB
#  //     |        |  |   |  |   |   `--- Current (mA) LSB
#  //     |        |  |   |  |    `------ Current (mA) MSB
#  //     |        |  |   |  `--- Voltage (V) * 10 LSB
#  //     |        |  |    `----- Voltage (V) * 10 MSB
#  //     |        |    `--- ID
#  //     |         `------- ID
#  //      `--- fix "EMT7110"
sub
EMT7110_Parse($$)
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
 
  my( @bytes, $addr,$voltage,$current,$power,$accumulatedPower,$accumulatedPowerMeasured,$connected,$pairing );
  if( $msg =~ m/^OK EMT7110/ ) {
    @bytes = split( ' ', substr($msg, 11) );

    $addr = sprintf( "%02X%02X", $bytes[0], $bytes[1] );
    $voltage = ($bytes[2]*256 + $bytes[3] ) / 10.0;
    $current = $bytes[4]*256 + $bytes[5];
    $power = $bytes[6]*256 + $bytes[7];
    $accumulatedPowerMeasured = ($bytes[8]*256 + $bytes[9]) / 100.0;
    $connected = ($bytes[10] & 0x01);
    $pairing = ($bytes[10] & 0x02) >> 1;
    
    } else {
    DoTrigger($name, "UNKNOWNCODE $msg");
    Log3 $name, 3, "$name: Unknown code $msg, help me!";
    return undef;
  }

  if($pairing > 0) {
    return undef;
  }
  else {
    my $raddr = $addr;
    my $rhash = $modules{EMT7110}{defptr}{$raddr};
    my $rname = $rhash?$rhash->{NAME}:$raddr;

    my $accumulatedPowerOffset = AttrVal( $rname, "accumulatedPowerOffset", 0);
    $accumulatedPower = $accumulatedPowerMeasured - $accumulatedPowerOffset;
    
    my $costs = $accumulatedPower * AttrVal( $rname, "pricePerKWH", 0);
    
     if( !$modules{EMT7110}{defptr}{$raddr} ) {
       Log3 $name, 3, "EMT7110 Unknown device $rname, please define it";
    
       return "UNDEFINED EMT7110_$rname EMT7110 $raddr";
     }
    
    my @list;
    push(@list, $rname);

    $rhash->{lastReceiveTime} = TimeNow();

    readingsBeginUpdate($rhash);
    readingsBulkUpdate($rhash, "voltage", $voltage);
    readingsBulkUpdate($rhash, "current", $current);
    readingsBulkUpdate($rhash, "power", $power);
    readingsBulkUpdate($rhash, "accumulatedPowerMeasured", $accumulatedPowerMeasured);
    readingsBulkUpdate($rhash, "accumulatedPower", $accumulatedPower);
    readingsBulkUpdate($rhash, "costs", $costs);
    
   
    my $state = "V: $voltage";
    $state .= "  C: $current";
    $state .= " P: $power";
    $state .= " A: $accumulatedPower";
   
    readingsBulkUpdate($rhash, "state", $state) if( Value($rname) ne $state );
    readingsEndUpdate($rhash,1);
  
    return @list;
  }
  
}

#####################################
sub
EMT7110_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);


  my $list = "resetAccumulatedPower";
  return $list if( $cmd eq '?' || $cmd eq '');


  if($cmd eq "resetAccumulatedPower") {
    CommandAttr(undef, "$name accumulatedPowerOffset " . $hash->{READINGS}{accumulatedPowerMeasured}{VAL});
  } 
  else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

sub
EMT7110_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  return undef;
}

1;

=pod
=begin html

<a name="EMT7110"></a>
<h3>EMT7110</h3>
<ul>

  <tr><td>
  The EMT7110 is a plug with integrated power meter functionality.<br><br>

  It can be integrated into FHEM via a <a href="#JeeLink">JeeLink</a> as the IODevice.<br><br>

  <a name="EMT7110_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EMT7110 &lt;addr&gt;</code> <br>
    addr is a 1 digit hex number to identify the EMT7110 device.<br>
  </ul>
  <br>

  <a name="EMT7110_Set"></a>
  <b>Set</b>
  <ul>
  <li>
    resetAccumulatedPower<br>
    Sets the accumulatedPowerOffset attribute to the current value of accumulatedPowerMeasured.
    Don't forget to call save to write the new value to fhem.cfg
  </li>
  </ul><br>

  <a name="EMT7110_Get"></a>
  <b>Get</b>
  <ul>
  </ul><br>

  <a name="EMT7110_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>accumulatedPowerMeasured<br>
      The accumulated power sent by the EMT7110. The EMT7110 accumulates the power even if it was removed and reconnected to the power outlet.
      The only was to reset it is to remove and reinsert the batteries in the EMT7110.       
    </li><br>
    
    <li>accumulatedPower<br>
      Is accumulatedPowerMeasured minus the value of the accumulatedPowerOffset attribute value
      This reading is used for the A: part of state       
    </li><br>
    
    <li>costs<br>
      Is accumulatedPower * pricePerKWH attribute value
    </li><br>
    
    <li>current<br>
      The measured current in mA
    </li><br>
    
    <li>power<br>
      The measured power in Watt 
    </li><br>
    
    <li>voltage<br>
      The measured voltage in Volt
    </li><br>
  </ul>

  <a name="EMT7110_Attr"></a>
  <b>Attributes</b>
  <ul>
  <li>accumulatedPowerOffset<br>
    See accumulatedPower reading
  </li><br>
  
  <li>pricePerKWH<br>
   See costs reading
  </li><br>
  
  </ul><br>
</ul>

=end html
=cut

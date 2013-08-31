#
#
# 09_BS.pm
# written by Dr. Boris Neubert 2009-06-20
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;

#############################
sub
BS_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^81..(04|0c)..0101a001a5cf";
  $hash->{DefFn}     = "BS_Define";
  $hash->{UndefFn}   = "BS_Undef";
  $hash->{ParseFn}   = "BS_Parse";
  $hash->{AttrList}  = "do_not_notify:1,0 showtime:0,1 ".
                       "ignore:1,0 model:BS " . $readingFnAttributes;

}

#############################
sub
BS_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u= "wrong syntax: define <name> BS <sensor> [[RExt] luxOffset]";
  return $u if((int(@a)< 3) || (int(@a)>5));

  my $name	= $a[0];
  my $sensor	= $a[2];
  if($sensor !~ /[123456789]/) {
  	return "erroneous sensor specification $sensor, use one of 1..9";
  }
  $sensor= "0$sensor";

  my $RExt	= 50000; # default is 50kOhm
  $RExt= $a[3] if(int(@a)>=4);
  my $luxOffset= 0;  # default is no offset
  $luxOffset= $a[4] if(int(@a)>=5);
  $hash->{SENSOR}= "$sensor";
  $hash->{RExt}= $RExt;
  $hash->{luxOffset}= $luxOffset;

  my $dev= "a5cf $sensor";
  $hash->{DEF}= $dev;

  $modules{BS}{defptr}{$dev} = $hash;
  AssignIoPort($hash);
}

#############################
sub
BS_Undef($$)
{
  my ($hash, $name) = @_;
  
  delete($modules{BS}{defptr}{$hash->{DEF}});
  return undef;
}

#############################
sub
BS_Parse($$)
{
  my ($hash, $msg) = @_;	# hash points to the FHZ, not to the BS


  # Msg format:
  # 01 23 45 67 8901 2345 6789 01 23 45 67
  # 81 0c 04 .. 0101 a001 a5cf xx 00 zz zz

  my $sensor= substr($msg, 20, 2);
  my $dev= "a5cf $sensor";

  my $def= $modules{BS}{defptr}{$dev};
  if(!defined($def)) {
    $sensor =~ s/^0//; 
    Log3 $hash, 3, "BS Unknown device $sensor, please define it";
    return "UNDEFINED BS_$sensor BS $sensor";
  }

  my $name= $def->{NAME};
  return "" if(IsIgnored($name));

  my $t= TimeNow();

  my $flags= hex(substr($msg, 24, 1)) & 0xdc;
  my $value= hex(substr($msg, 25, 3)) & 0x3ff;

  my $RExt= $def->{RExt};
  my $luxOffset= $def->{luxOffset};
  my $brightness= $value/10.24; # Vout in percent of reference voltage 1.1V

  # brightness in lux= 100lux*(VOut/RExt/1.8muA)^2;
  my $VOut= $value*1.1/1024.0;
  my $temp= $VOut/$RExt/1.8E-6;
  my $lux= 100.0*$temp*$temp;
  $lux+= $luxOffset; # add lux offset

  my $state= sprintf("brightness: %.2f  lux: %.0f  flags: %d",
  	$brightness, $lux, $flags);

  readingsBeginUpdate($def);
  readingsBulkUpdate($def, "state", $state);
  #Debug "BS $name: $state";
  readingsBulkUpdate($def, "brightness", $brightness);
  readingsBulkUpdate($def, "lux", $lux);
  readingsBulkUpdate($def, "flags", $flags);
  readingsEndUpdate($def, 1);

  return $name;

}

#############################

1;

=pod
=begin html

<a name="BS"></a>
<h3>BS</h3>
<ul>
  The module BS allows to collect data from a brightness sensor through a
  <a href="#FHZ">FHZ</a> device. For details on the brightness sensor see
  <a href="http://www.busware.de/tiki-index.php?page=CPM-BS">busware wiki</a>.
  You can have at most nine different brightness sensors in range of your
  FHZ.<br>
  <br>

  The state contains the brightness in % (reading <code>brightness</code>) and
  the brightness in lux (reading <code>lux</code>). The <code>flags</code>
  reading is always zero. The meaning of these readings is explained in more
  detail on the above mentioned wiki page.<br>
  <br>

  <a name="BSDefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; BS &lt;sensor#&gt; [&lt;RExt&gt;]</code>
    <br><br>

    <code>&lt;sensor#&gt;</code> is the number of sensor in the brightness
    sensor address system that runs from 1 to 9.<br>
    <br>
    <code>&lt;RExt&gt;</code> is the value of the resistor on your brightness
    sensor in &Omega; (Ohm). The brightness reading in % is proportional to the resistance, the
    lux reading is proportional to the resistance squared. The value is
    optional. The default resistance is RExt= 50.000&Omega;.<br>
    <br>

    Example:<br>
    <ul>
      <code>define bs1 BS 1 40000</code><br>
    </ul>
  </ul>
  <br>

  <a name="BSset"></a>
  <b>Set </b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="BSget"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="BSattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a> (bs)</li>
    <li><a href="#ignore">ignore</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>


=end html
=cut

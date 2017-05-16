#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################
sub
FRM_I2C_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_I2C_Init";
  $hash->{UndefFn}   = "FRM_I2C_Undef";
  $hash->{AttrFn}    = "FRM_I2C_Attr";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_I2C_Init($)
{
	my ($hash,$args) = @_;
 	my $u = "wrong syntax: define <name> FRM_I2C address register numbytes";

	return $u if(int(@$args) < 5);
  
	$hash->{"i2c-address"} = @$args[2];
	$hash->{"i2c-register"} = @$args[3];
	$hash->{"i2c-bytestoread"} = @$args[4];

	return "no IODev set" unless defined $hash->{IODev};
	return "no FirmataDevice assigned to ".$hash->{IODev}->{NAME} unless defined $hash->{IODev}->{FirmataDevice};  	
	
	eval {
		$hash->{IODev}->{FirmataDevice}->i2c_read(@$args[2],@$args[3],@$args[4]);
	};
	return "error calling i2c_read: ".$@ if ($@);
	return undef;
}

sub FRM_I2C_Attr(@) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $main::defs{$name};
	if ($command eq "set") {
		$main::attr{$name}{$attribute}=$value;
	}
}

sub
FRM_I2C_Undef($$)
{
  my ($hash, $name) = @_;
}

1;

=pod
=begin html

<a name="FRM_I2C"></a>
<h3>FRM_I2C</h3>
<ul>
  represents an integrated curcuit connected to the i2c-pins of an <a href="http://www.arduino.cc">Arduino</a>
  running <a href="http://www.firmata.org">Firmata</a><br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br>
  this FRM-device has to be configures for i2c by setting attr 'i2c-config' on the FRM-device<br>
  it reads out the ic-internal storage in intervals of 'sampling-interval' as set on the FRM-device<br><br> 
  
  <a name="FRM_I2Cdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_I2C &lt;i2c-address&gt; &lt;register&gt; &lt;bytes-to-read&gt;</code> <br>
  Specifies the FRM_I2C device.<br>
  <li>i2c-address is the (device-specific) address of the ic on the i2c-bus</li>
  <li>register is the (device-internal) address to start reading bytes from.</li>
  <li>bytes-to-read is the number of bytes read from the ic</li>
  </ul>
  
  <br>
  <a name="FRM_I2Cset"></a>
  <b>Set</b><br>
  <ul>
  N/A<br>
  </ul>
  <a name="FRM_I2Cget"></a>
  <b>Get</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="FRM_I2Cattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut

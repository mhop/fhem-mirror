#############################################
package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata::Constants  qw/ :all /;

#####################################
sub
FRM_I2C_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_I2C_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_I2C_Attr";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_I2C_Init($)
{
	my ($hash,$args) = @_;
 	my $u = "wrong syntax: define <name> FRM_I2C address register numbytes";

	return $u if(int(@$args) < 3);
  
	$hash->{"i2c-address"} = @$args[0];
	$hash->{"i2c-register"} = @$args[1];
	$hash->{"i2c-bytestoread"} = @$args[2];

  eval {
    FRM_Client_FirmataDevice($hash)->i2c_read(@$args[0],@$args[1],@$args[2]);
  };
	return "error calling i2c_read: ".$@ if ($@);
	if (! (defined AttrVal($hash->{NAME},"event-min-interval",undef))) {
		$main::attr{$hash->{NAME}}{"event-min-interval"} = 5;
	}
	return undef;
}

sub
FRM_I2C_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  if ($command eq "set") {
    ARGUMENT_HANDLER: {
      $attribute eq "IODev" and do {
      	my $hash = $main::defs{$name};
      	if (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value) {
        	$hash->{IODev} = $defs{$value};
      		FRM_Init_Client($hash) if (defined ($hash->{IODev}));
      	}
        last;
      };
   	  $main::attr{$name}{$attribute}=$value;
    }
  }
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

#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################
sub
FRM_PWM_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_PWM_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_PWM_Init";
  $hash->{UndefFn}   = "FRM_PWM_Undef";
  $hash->{AttrFn}    = "FIR_Attr";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_PWM_Init($$)
{
	my ($hash,$args) = @_;
	FRM_Init_Pin_Client($hash,$args);
	if (defined $hash->{IODev}) {
		my $firmata = $hash->{IODev}->{FirmataDevice};
		if (defined $firmata and defined $hash->{PIN}) {
			$firmata->pin_mode($hash->{PIN},PIN_PWM);
			main::readingsSingleUpdate($hash,"state","initialized",1);
		}
	}
}

sub
FRM_PWM_Set($@)
{
  my ($hash, @a) = @_;
  my $value = $a[1];
  my $iodev = $hash->{IODev};
  if (defined $iodev and defined $iodev->{FirmataDevice} and defined $iodev->{FD}) {
  	$iodev->{FirmataDevice}->analog_write($hash->{PIN},$value);
	main::readingsSingleUpdate($hash,"state",$a[1], 1);
  } else {
  	return $hash->{NAME}." no IODev assigned" if (!defined $iodev);
  	return $hash->{NAME}.", ".$iodev->{NAME}." is not connected";
  }
  return undef;
}

sub
FRM_PWM_Undef($$)
{
  my ($hash, $name) = @_;
}

1;

=pod
=begin html

<a name="FRM_PWM"></a>
<h3>FRM_PWM</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured for analog output.<br>
  The value set will be output by the specified pin as a pulse-width-modulated signal.<br> 
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_PWMdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_PWM &lt;pin&gt;</code> <br>
  Specifies the FRM_PWM device.
  </ul>
  
  <br>
  <a name="FRM_PWMset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; &lt;value&gt;</code><br><br>
  </ul>
  <a name="FRM_PWMget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_PWMattr"></a>
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

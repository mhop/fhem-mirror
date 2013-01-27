#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################
sub
FRM_IN_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "FRM_IN_Get";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_IN_Init";
  $hash->{UndefFn}   = "FRM_IN_Undef";
  $hash->{AttrFn}    = "FRM_Attr";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_IN_Init($$)
{
	my ($hash,$args) = @_;
	FRM_Init_Pin_Client($hash,$args);
	if (defined $hash->{IODev}) {
		my $firmata = $hash->{IODev}->{FirmataDevice};
		if (defined $firmata and defined $hash->{PIN}) {
			$firmata->pin_mode($hash->{PIN},PIN_INPUT);
			$firmata->observe_digital($hash->{PIN},\&FRM_IN_observer,$hash);
			main::readingsSingleUpdate($hash,"state","initialized",1);
			return undef;
		}
	}
	return 1;
}

sub
FRM_IN_observer
{
	my ($pin,$old,$new,$hash) = @_;
	main::Log(6,"onDigitalMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--"));
	main::readingsSingleUpdate($hash,"state",$new == PIN_HIGH ? "on" : "off", 1);
}

sub
FRM_IN_Get($)
{
  my ($hash) = @_;
  my $iodev = $hash->{IODev};
  if (defined $iodev and defined $iodev->{FirmataDevice} and defined $iodev->{FD}) {
  	my $ret = $iodev->{FirmataDevice}->digital_read($hash->{PIN});
  	return $ret == PIN_HIGH ? "on" : "off";
  } else {
  	return $hash->{NAME}." no IODev assigned" if (!defined $iodev);
  	return $hash->{NAME}.", ".$iodev->{NAME}." is not connected";
  }
}

sub
FRM_IN_Undef($$)
{
  my ($hash, $name) = @_;
}

1;

=pod
=begin html

<a name="FRM_IN"></a>
<h3>FRM_IN</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured for digital input.<br>
  The current state of the arduino-pin is stored in reading 'state'. Values are 'on' and 'off'.<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_INdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_IN &lt;pin&gt;</code> <br>
  Specifies the FRM_IN device.
  </ul>
  
  <br>
  <a name="FRM_INset"></a>
  <b>Set</b><br>
  <ul>
  N/A<br>
  </ul>
  <a name="FRM_INget"></a>
  <b>Get</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="FRM_INattr"></a>
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

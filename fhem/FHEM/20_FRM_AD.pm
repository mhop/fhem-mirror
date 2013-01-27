#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################
sub
FRM_AD_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "FRM_AD_Get";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_AD_Init";
  $hash->{UndefFn}   = "FRM_AD_Undef";
  $hash->{AttrFn}    = "FRM_Attr";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_AD_Init($$)
{
	my ($hash,$args) = @_;
	FRM_Init_Pin_Client($hash,$args);
	if (defined $hash->{IODev}) {
		my $firmata = $hash->{IODev}->{FirmataDevice};
		if (defined $firmata and defined $hash->{PIN}) {
			$firmata->pin_mode($hash->{PIN},PIN_ANALOG);
			$firmata->observe_analog($hash->{PIN},\&FRM_AD_observer,$hash);
			main::readingsSingleUpdate($hash,"state","initialized",1);
			return undef;
		}
	}
	return 1;
}

sub
FRM_AD_observer
{
	my ($pin,$old,$new,$hash) = @_;
	main::Log(6,"onAnalogMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--"));
	main::readingsSingleUpdate($hash,"state",$new, 1);
}

sub
FRM_AD_Get($)
{
  my ($hash) = @_;
  my $iodev = $hash->{IODev};
  if (defined $iodev and defined $iodev->{FirmataDevice} and defined $iodev->{FD}) {
  	my $ret = $iodev->{FirmataDevice}->analog_read($hash->{PIN});
  	return $ret;
  } else {
  	return $hash->{NAME}." no IODev assigned" if (!defined $iodev);
  	return $hash->{NAME}.", ".$iodev->{NAME}." is not connected";
  }
}

sub
FRM_AD_Undef($$)
{
  my ($hash, $name) = @_;
}

1;

=pod
=begin html

<a name="FRM_AD"></a>
<h3>FRM_AD</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured for analog input.<br>
  The value read is stored in reading 'state'. Range is from 0 to 1.<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_ADdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_AD &lt;pin&gt;</code> <br>
  Specifies the FRM_AD device.
  </ul>
  
  <br>
  <a name="FRM_ADset"></a>
  <b>Set</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="FRM_ADget"></a>
  <b>Get</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="FRM_ADattr"></a>
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

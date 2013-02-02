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
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_AD_Init($$)
{
	my ($hash,$args) = @_;
	if (FRM_Init_Pin_Client($hash,$args,PIN_ANALOG)) {
		my $firmata = $hash->{IODev}->{FirmataDevice};
		$firmata->observe_analog($hash->{PIN},\&FRM_AD_observer,$hash);
		$main::defs{$hash->{NAME}}{resolution}=$firmata->{metadata}{analog_resolutions}{$hash->{PIN}} if (defined $firmata->{metadata}{analog_resolutions});
		main::readingsSingleUpdate($hash,"state","Initialized",1);
		return undef;
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
  my ($hash,@a) = @_;
  my $iodev = $hash->{IODev};
  my $name = shift @a;
  return $name." no IODev assigned" if (!defined $iodev);
  return $name.", ".$iodev->{NAME}." is not connected" if (!(defined $iodev->{FirmataDevice} and defined $iodev->{FD}));
  my $cmd = shift @a;
  my $ret;
  ARGUMENT_HANDLER: {
    $cmd eq "reading" and do {
  	  $ret = $iodev->{FirmataDevice}->analog_read($hash->{PIN});
  	  last;
    };
    $ret = "unknown command ".$cmd;
  }
  return $ret;
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
  The value read is stored in reading 'state'. Range is from 0 to 1023 (10 Bit)<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_ADdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_AD &lt;pin&gt;</code> <br>
  Defines the FRM_AD device. &lt;pin&gt; is the arduino-pin to use.
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
  <li>reading<br>
  returns the voltage-level read on the arduino-pin. Values range from 0 to 1023.<br></li>
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

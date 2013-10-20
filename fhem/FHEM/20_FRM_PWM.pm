#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "value" => "",
);

sub
FRM_PWM_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_PWM_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_PWM_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{StateFn}   = "FRM_PWM_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_PWM_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_PWM);
	return $ret if (defined $ret);
	my $firmata = $hash->{IODev}->{FirmataDevice};
	my $name = $hash->{NAME};
	$main::defs{$name}{resolution}=$firmata->{metadata}{pwm_resolutions}{$hash->{PIN}} if (defined $firmata->{metadata}{pwm_resolutions});
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "value";
	}
	my $value = ReadingsVal($name,"value",undef);
	if (defined $value and AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
		FRM_PWM_Set($hash,$name,$value);
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_PWM_Set($@)
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];
  my $iodev = $hash->{IODev};
  eval {
    FRM_Client_FirmataDevice($hash)->analog_write($hash->{PIN},$value);
    main::readingsSingleUpdate($hash,"value",$value, 1);
  };
  return $@;
}

sub FRM_PWM_State($$$$)
{
	my ($hash, $tim, $sname, $sval) = @_;
	
STATEHANDLER: {
		$sname eq "value" and do {
			if (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") { 
				FRM_PWM_Set($hash,$hash->{NAME},$sval);
			}
			last;
		}
	}
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
  Defines the FRM_PWM device. &lt;pin&gt> is the arduino-pin to use.
  </ul>
  
  <br>
  <a name="FRM_PWMset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; value &lt;value&gt;</code><br>
  sets the pulse-width of the signal that is output on the configured arduino pin<br>
  Range is from 0 to 255 (see <a href="http://arduino.cc/en/Reference/AnalogWrite">analogWrite()</a> for details)
  </ul>
  <a name="FRM_PWMget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_PWMattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>restoreOnStartup &lt;on|off&gt;</li>
      <li>restoreOnReconnect &lt;on|off&gt;</li>
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

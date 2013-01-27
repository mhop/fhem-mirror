#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################
sub
FRM_OUT_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_OUT_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_OUT_Init";
  $hash->{UndefFn}   = "FRM_OUT_Undef";
  $hash->{AttrFn}    = "FRM_Attr";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_OUT_Init($$)
{
	my ($hash,$args) = @_;
	FRM_Init_Pin_Client($hash,$args);
	if (defined $hash->{IODev}) {
		my $firmata = $hash->{IODev}->{FirmataDevice};
		if (defined $firmata and defined $hash->{PIN}) {
			$firmata->pin_mode($hash->{PIN},PIN_OUTPUT);
			main::readingsSingleUpdate($hash,"state","initialized",1);
		}
	}
}

sub
FRM_OUT_Set($@)
{
  my ($hash, @a) = @_;
  my $value;
  if ($a[1] eq "on") {
  	$value=PIN_HIGH;
  } elsif ($a[1] eq "off") {
  	  $value=PIN_LOW;
  } else {
  	  return "illegal value '".$a[1]."', allowed are 'on' and 'off'";
  }
  my $iodev = $hash->{IODev};
  if (defined $iodev and defined $iodev->{FirmataDevice} and defined $iodev->{FD}) {
  	$iodev->{FirmataDevice}->digital_write($hash->{PIN},$value);
	main::readingsSingleUpdate($hash,"state",$a[1], 1);
  } else {
  	return $hash->{NAME}." no IODev assigned" if (!defined $iodev);
  	return $hash->{NAME}.", ".$iodev->{NAME}." is not connected";
  }
  return undef;
}

sub
FRM_OUT_Undef($$)
{
  my ($hash, $name) = @_;
}

1;

=pod
=begin html

<a name="FRM_OUT"></a>
<h3>FRM_OUT</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured for digital input.<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_OUTdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_OUT &lt;pin&gt;</code> <br>
  Specifies the FRM_OUT device.
  </ul>
  
  <br>
  <a name="FRM_OUTset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; on|off</code><br><br>
  </ul>
  <a name="FRM_OUTget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_OUTattr"></a>
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

#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;
use SetExtensions;

#####################################
sub
FRM_OUT_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_OUT_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_OUT_Init";
  $hash->{UndefFn}   = "FRM_OUT_Undef";
  
  $hash->{AttrList}  = "IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_OUT_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_OUTPUT);
	return $ret if (defined $ret);
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_OUT_Set($@)
{
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  shift @a;
  my $cmd = $a[0];
  my $value;
  if ($cmd eq "on") {
  	$value=PIN_HIGH;
  } elsif ($cmd eq "off") {
  	  $value=PIN_LOW;
  } else {
  	my $list = "on off";
    return SetExtensions($hash, $list, $name, @a);
  }
  my $iodev = $hash->{IODev};
  if (defined $iodev and defined $iodev->{FirmataDevice} and defined $iodev->{FD}) {
  	$iodev->{FirmataDevice}->digital_write($hash->{PIN},$value);
	main::readingsSingleUpdate($hash,"state",$cmd, 1);
  } else {
  	return $name." no IODev assigned" if (!defined $iodev);
  	return $name.", ".$iodev->{NAME}." is not connected";
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
  Defines the FRM_OUT device. &lt;pin&gt> is the arduino-pin to use.
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

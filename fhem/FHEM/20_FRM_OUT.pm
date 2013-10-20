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
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{StateFn}   = "FRM_OUT_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_OUT_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_OUTPUT);
	return $ret if (defined $ret);
	my $name = $hash->{NAME};
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "value";
	}
	my $value = ReadingsVal($name,"value",undef);
	if (defined $value and AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
		FRM_OUT_Set($hash,$name,$value);
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_OUT_Set($$$)
{
  my ($hash, $name, $cmd, @a) = @_;
  my $value;
  if ($cmd eq "on") {
  	$value=PIN_HIGH;
  } elsif ($cmd eq "off") {
  	  $value=PIN_LOW;
  } else {
  	my $list = "on off";
    return SetExtensions($hash, $list, $name, $cmd, @a);
  }
  eval {
    FRM_Client_FirmataDevice($hash)->digital_write($hash->{PIN},$value);
    main::readingsSingleUpdate($hash,"value",$cmd, 1);
  };
  return $@;
}

sub FRM_OUT_State($$$$)
{
	my ($hash, $tim, $sname, $sval) = @_;
	
STATEHANDLER: {
		$sname eq "value" and do {
			if (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") { 
				FRM_OUT_Set($hash,$hash->{NAME},$sval);
			}
			last;
		}
	}
}

1;

=pod
=begin html

<a name="FRM_OUT"></a>
<h3>FRM_OUT</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured for digital output.<br>
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

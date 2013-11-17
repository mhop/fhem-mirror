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

my %gets = (
  "reading" => "",
  "state"   => "",
  "alarm-upper-threshold"   => "off",
  "alarm-lower-threshold"   => "off",
);

sub
FRM_AD_Initialize($)
{
  my ($hash) = @_;

  $hash->{AttrFn}    = "FRM_AD_Attr";
  $hash->{GetFn}     = "FRM_AD_Get";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_AD_Init";
  
  $hash->{AttrList}  = "IODev upper-threshold lower-threshold $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_AD_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_ANALOG);
	return $ret if (defined $ret);
	my $firmata = $hash->{IODev}->{FirmataDevice};
	my $name = $hash->{NAME};
	$firmata->observe_analog($hash->{PIN},\&FRM_AD_observer,$hash);
	$main::defs{$name}{resolution}=$firmata->{metadata}{analog_resolutions}{$hash->{PIN}} if (defined $firmata->{metadata}{analog_resolutions});
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "reading";
	}
	if (! (defined AttrVal($name,"event-min-interval",undef))) {
		$main::attr{$name}{"event-min-interval"} = 5;
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_AD_observer
{
	my ($pin,$old,$new,$hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name,6,"onAnalogMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--");
	main::readingsBeginUpdate($hash);
	main::readingsBulkUpdate($hash,"reading",$new,1);
	my $upperthresholdalarm = ReadingsVal($name,"alarm-upper-threshold","off");
    if ( $new < AttrVal($name,"upper-threshold",1024) ) {
      if ( $upperthresholdalarm eq "on" ) {
    	main::readingsBulkUpdate($hash,"alarm-upper-threshold","off",1);
      }
      my $lowerthresholdalarm = ReadingsVal($name,"alarm-lower-threshold","off"); 
      if ( $new > AttrVal($name,"lower-threshold",-1) ) {
        if ( $lowerthresholdalarm eq "on" ) {
          main::readingsBulkUpdate($hash,"alarm-lower-threshold","off",1);
        }
      } else {
      	if ( $lowerthresholdalarm eq "off" ) {
          main::readingsBulkUpdate($hash,"alarm-lower-threshold","on",1);
      	}
      }
    } else {
      if ( $upperthresholdalarm eq "off" ) {
    	main::readingsBulkUpdate($hash,"alarm-upper-threshold","on",1);
      }
	};
	main::readingsEndUpdate($hash,1);
}

sub
FRM_AD_Get($)
{
  my ($hash,@a) = @_;
  my $name = shift @a;
  my $cmd = shift @a;
  my $ret;
  ARGUMENT_HANDLER: {
    $cmd eq "reading" and do {
      eval {
        return FRM_Client_FirmataDevice($hash)->analog_read($hash->{PIN});
      };
      return $@;
    };
    ( $cmd eq "alarm-upper-threshold" or $cmd eq "alarm-lower-threshold" or $cmd eq "state" ) and do {
      return main::ReadingsVal($name,"count",$gets{$cmd});
    };
  }
  return undef;
}

sub
FRM_AD_Attr($$$$) {
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
    }
  }
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
    returns the voltage-level read on the arduino-pin. Values range from 0 to 1023.</li>
    <li>alarm-upper-threshold<br>
    returns the current state of 'alarm-upper-threshold'. Values are 'on' and 'off' (Defaults to 'off')<br>
    'alarm-upper-threshold' turns 'on' whenever the 'reading' is higher than the attribute 'upper-threshold'<br>
    it turns 'off' again as soon 'reading' falls below 'alarm-upper-threshold'</li>
    <li>alarm-lower-threshold<br>
    returns the current state of 'alarm-lower-threshold'. Values are 'on' and 'off' (Defaults to 'off')<br>
    'alarm-lower-threshold' turns 'on' whenever the 'reading' is lower than the attribute 'lower-threshold'<br>
    it turns 'off' again as soon 'reading rises above 'alarm-lower-threshold'</li>
    <li>state<br>
    returns the 'state' reading</li>
  </ul><br>
  <a name="FRM_ADattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>upper-threshold<br>
      sets the 'upper-threshold'. Whenever the 'reading' exceeds this value 'alarm-upper-threshold' is set to 'on'<br>
      As soon 'reading' falls below the 'upper-threshold' 'alarm-upper-threshold' turns 'off' again<br>
      Defaults to 1024.</li>
      <li>lower-threshold<br>
      sets the 'lower-threshold'. Whenever the 'reading' falls below this value 'alarm-lower-threshold' is set to 'on'<br>
      As soon 'reading' rises above the 'lower-threshold' 'alarm-lower-threshold' turns 'off' again<br>
      Defaults to -1.</li>
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

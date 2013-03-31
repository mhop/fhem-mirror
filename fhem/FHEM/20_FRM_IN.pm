#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "alarm" => "",
);

my %gets = (
  "reading" => "",
  "state"   => "",
  "count"   => 0,
  "alarm"   => "off"
);

sub
FRM_IN_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_IN_Set";
  $hash->{GetFn}     = "FRM_IN_Get";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_IN_Init";
  $hash->{UndefFn}   = "FRM_IN_Undef";
  
  $hash->{AttrList}  = "IODev count-mode count-threshold loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
}

sub
FRM_IN_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_INPUT);
	return $ret if (defined $ret);
	my $firmata = $hash->{IODev}->{FirmataDevice};
	$firmata->observe_digital($hash->{PIN},\&FRM_IN_observer,$hash);
	if (! (defined AttrVal($hash->{NAME},"stateFormat",undef))) {
		$main::attr{$hash->{NAME}}{"stateFormat"} = "reading";
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_IN_observer
{
	my ($pin,$old,$new,$hash) = @_;
	main::Log(6,"onDigitalMessage for pin ".$pin.", old: ".(defined $old ? $old : "--").", new: ".(defined $new ? $new : "--"));
	my $name = $hash->{NAME};
	my $mode = AttrVal($name,"count-mode","rising");
	my $count = ReadingsVal($name,"count",0);
	main::readingsBeginUpdate($hash);
	if ( ($old != $new) 
	  and (($mode eq "rising" and $old == PIN_LOW) 
	    or ($mode eq "falling" and $old == PIN_HIGH)
	    or ($mode eq "both"))) {
	  $count++;
	  my $threshold = AttrVal($name,"count-threshold",0);
      if ( $count >= $threshold ) {
      	main::readingsBulkUpdate($hash,"alarm","on",1);
      	$count=0;
      }
	  main::readingsBulkUpdate($hash,"count",$count,1); 
	};
	main::readingsBulkUpdate($hash,"reading",$new == PIN_HIGH ? "on" : "off", 1);
	main::readingsEndUpdate($hash,1);
}

sub
FRM_IN_Set
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];
  COMMAND_HANDLER: {
    $command eq "alarm" and do {
      return undef if (!($value eq "off" or $value eq "on"));
      main::readingsSingleUpdate($hash,"alarm",$value,1);
      last;
    }
  }
}

sub
FRM_IN_Get($)
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "reading" and do {
      my $iodev = $hash->{IODev};
      return $name." no IODev assigned" if (!defined $iodev);
      return $name.", ".$iodev->{NAME}." is not connected" if (!(defined $iodev->{FirmataDevice} and defined $iodev->{FD}));
  	  return $iodev->{FirmataDevice}->digital_read($hash->{PIN}) == PIN_HIGH ? "on" : "off";
    };
    ( $cmd eq "count" or $cmd eq "alarm" or $cmd eq "state" ) and do {
      return main::ReadingsVal($name,"count",$gets{$cmd});
    };
  }
  return undef;
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
  Defines the FRM_IN device. &lt;pin&gt> is the arduino-pin to use.
  </ul>
  
  <br>
  <a name="FRM_INset"></a>
  <b>Set</b><br>
  <ul>
    <li>alarm on|off<br>
    set the alarm to on or off. Used to clear the alarm.<br>
    The alarm is set to 'on' whenever the count reaches the threshold and doesn't clear itself.</li>
  </ul>
  <a name="FRM_INget"></a>
  <b>Get</b>
  <ul>
    <li>reading<br>
    returns the logical state of the arduino-pin. Values are 'on' and 'off'.<br></li>
    <li>count<br>
    returns the current count. Contains the number of toggles of the arduino-pin.<br>
    Depending on the attribute 'count-mode' every rising or falling edge (or both) is counted.</li>
    <li>alarm<br>
    returns the current state of 'alarm'. Values are 'on' and 'off' (Defaults to 'off')<br>
    'alarm' doesn't clear itself, has to be set to 'off' eplicitly./li>
    <li>state<br>
    returns the 'state' reading</li>
  </ul><br>
  <a name="FRM_INattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>count-mode rising|falling|both<br>
      Determines whether 'rising' (transitions from 'off' to 'on') of falling (transitions from 'on' to 'off')<br>
      edges (or 'both') are counted. Defaults to 'rising'</li>
      <li>count-threshold &lt;number&gt;<br>
      sets the theshold-value for the counter. Whenever 'count' reaches the 'count-threshold' 'alarm' is<br>
      set to 'on' and count is reset to 0. Use 'set alarm off' to clear the alarm.</li>
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

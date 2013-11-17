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

my %sets = (
  "angle" => "",
);

sub
FRM_SERVO_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_SERVO_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_SERVO_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_SERVO_Attr";
  
  $hash->{AttrList}  = "min-pulse max-pulse IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_SERVO_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_SERVO);
	return $ret if (defined $ret);
	my $firmata = $hash->{IODev}->{FirmataDevice};
	$main::defs{$hash->{NAME}}{resolution}=$firmata->{metadata}{servo_resolutions}{$hash->{PIN}} if (defined $firmata->{metadata}{servo_resolutions});
	FRM_SERVO_apply_attribute($hash,"max-pulse"); #sets min-pulse as well
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_SERVO_Attr($$$$) {
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
   	  $main::attr{$name}{$attribute}=$value;
   	  if ( $attribute eq "min-pulse" || $attribute eq "max-pulse" ) {
   	    FRM_SERVO_apply_attribute($main::defs{$name},$attribute);
   	  }
    }
  }
}

sub FRM_SERVO_apply_attribute {
	my ($hash,$attribute) = @_;
	return unless (defined $hash->{IODev} and defined $hash->{IODev}->{FirmataDevice});
	my $firmata = $hash->{IODev}->{FirmataDevice};
	my $name = $hash->{NAME};
	if ( $attribute eq "min-pulse" || $attribute eq "max-pulse" ) {
		# defaults are taken from: http://arduino.cc/en/Reference/ServoAttach
		$firmata->servo_config($hash->{PIN},{min_pulse => main::AttrVal($name,"min-pulse",544), max_pulse => main::AttrVal($name,"max-pulse",2400)});
	}
}

sub
FRM_SERVO_Set($@)
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];
  eval {
    FRM_Client_FirmataDevice($hash)->servo_write($hash->{PIN},$value);
    main::readingsSingleUpdate($hash,"state",$value, 1);
  };
  return $@;
}

1;

=pod
=begin html

<a name="FRM_SERVO"></a>
<h3>FRM_SERVO</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured to drive a pwm-controlled servo-motor.<br>
  The value set will be drive the shaft of the servo to the specified angle. see <a href="http://arduino.cc/en/Reference/ServoWrite">Servo.write</a> for values and range<br> 
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_SERVOdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_SERVO &lt;pin&gt;</code> <br>
  Defines the FRM_SERVO device. &lt;pin&gt> is the arduino-pin to use.
  </ul>
  
  <br>
  <a name="FRM_SERVOset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; angle &lt;value&gt;</code><br>sets the angle of the servo-motors shaft to the value specified (in degrees).<br>
  </ul>
  <a name="FRM_SERVOget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_SERVOattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li>min-pulse<br>
      sets the minimum puls-width to use. Defaults to 544. For most servos this translates into a rotation of 180° counterclockwise.</li>
      <li>max-pulse<br>
      sets the maximum puls-width to use. Defaults to 2400. For most servos this translates into a rotation of 180° clockwise</li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut

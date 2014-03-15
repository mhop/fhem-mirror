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
  "reset"    => "noArg",
  "position" => "",
  "step"     => "",
);

my %gets = (
  "position" => "noArg",
);

sub
FRM_STEPPER_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_STEPPER_Set";
  $hash->{GetFn}     = "FRM_STEPPER_Get";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_STEPPER_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_STEPPER_Attr";
  $hash->{StateFn}   = "FRM_STEPPER_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off speed acceleration deceleration IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_STEPPER_Init($$)
{
	my ($hash,$args) = @_;

	my $u = "wrong syntax: define <name> FRM_STEPPER [DRIVER|TWO_WIRE|FOUR_WIRE] directionPin stepPin [motorPin3 motorPin4] stepsPerRev [id]";
	return $u unless defined $args;
	
	my $driver = shift @$args;
	
	return $u unless ( $driver eq 'DRIVER' or $driver eq 'TWO_WIRE' or $driver eq 'FOUR_WIRE' );
	return $u if (($driver eq 'DRIVER' or $driver eq 'TWO_WIRE') and (scalar(@$args) < 3 or scalar(@$args) > 4));
	return $u if (($driver eq 'FOUR_WIRE') and (scalar(@$args) < 5 or scalar(@$args) > 6));
	
	$hash->{DRIVER} = $driver;
	
	$hash->{PIN1} = shift @$args;
	$hash->{PIN2} = shift @$args;
	
	if ($driver eq 'FOUR_WIRE') {
		$hash->{PIN3} = shift @$args;
		$hash->{PIN4} = shift @$args;
	}
	
	$hash->{STEPSPERREV} = shift @$args;
	$hash->{STEPPERNUM} = shift @$args;
	
	eval {
		FRM_Client_AssignIOPort($hash);
		my $firmata = FRM_Client_FirmataDevice($hash);
		$firmata->stepper_config(
			$hash->{STEPPERNUM},
			$driver,
			$hash->{STEPSPERREV},
			$hash->{PIN1},
			$hash->{PIN2},
			$hash->{PIN3},
			$hash->{PIN4});
		$firmata->observe_stepper(0, \&FRM_STEPPER_observer, $hash );
	};
	if ($@) {
		$@ =~ /^(.*)( at.*FHEM.*)$/;
		$hash->{STATE} = "error initializing: ".$1;
		return "error initializing '".$hash->{NAME}."': ".$1;
	}
	$hash->{POSITION} = 0;
	$hash->{DIRECTION} = 0;
	$hash->{STEPS} = 0;
	if (! (defined AttrVal($hash->{NAME},"stateFormat",undef))) {
		$main::attr{$hash->{NAME}}{"stateFormat"} = "position";
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_STEPPER_observer
{
	my ( $stepper, $hash ) = @_;
	my $name = $hash->{NAME};
	Log3 $name,5,"onStepperMessage for pins ".$hash->{PIN1}.",".$hash->{PIN2}.(defined ($hash->{PIN3}) ? ",".$hash->{PIN3} : ",-").(defined ($hash->{PIN4}) ? ",".$hash->{PIN4} : ",-")." stepper: ".$stepper;
	my $position = $hash->{DIRECTION} ? $hash->{POSITION} - $hash->{STEPS} : $hash->{POSITION} + $hash->{STEPS};
	$hash->{POSITION} = $position;
	$hash->{DIRECTION} = 0;
	$hash->{STEPS} = 0;
	main::readingsSingleUpdate($hash,"position",$position,1);
}

sub
FRM_STEPPER_Set
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  shift @a;
  my $name = $hash->{NAME};
  my $command = shift @a;
  if(!defined($sets{$command})) {
  	my @commands = ();
    foreach my $key (sort keys %sets) {
      push @commands, $sets{$key} ? $key.":".join(",",$sets{$key}) : $key;
    }
    return "Unknown argument $command, choose one of " . join(" ", @commands);
  }
  COMMAND_HANDLER: {
    $command eq "reset" and do {
      $hash->{POSITION} = 0;
      main::readingsSingleUpdate($hash,"position",0,1);
      last;
    };
    $command eq "position" and do {
      my $position = $hash->{POSITION};
      my $value = shift @a;
      my $direction = $value < $position ? 1 : 0;
      my $steps = $direction ? $position - $value : $value - $position;
      my $speed = shift @a;
      $speed = AttrVal($name,"speed",30) unless (defined $speed);
      my $accel = shift @a;
      $accel = AttrVal($name,"acceleration",undef) unless (defined $accel);
      my $decel = shift @a;
      $decel = AttrVal($name,"deceleration",undef) unless (defined $decel);
      $hash->{DIRECTION} = $direction;
      $hash->{STEPS} = $steps;
      eval {
      # $stepperNum, $direction, $numSteps, $stepSpeed, $accel, $decel
        FRM_Client_FirmataDevice($hash)->stepper_step($hash->{STEPPERNUM},$direction,$steps,$speed,$accel,$decel);
      };
      last;
    };
    $command eq "step" and do {
      my $value = shift @a;
      my $direction = $value < 0 ? 1 : 0;
      my $steps = abs $value;
      my $speed = shift @a;
      $speed = AttrVal($name,"speed",100) unless (defined $speed);
      my $accel = shift @a;
      $accel = AttrVal($name,"acceleration",undef) unless (defined $accel);
      my $decel = shift @a;
      $decel = AttrVal($name,"deceleration",undef) unless (defined $decel);
      $hash->{DIRECTION} = $direction;
      $hash->{STEPS} = $steps;
      eval {
      # $stepperNum, $direction, $numSteps, $stepSpeed, $accel, $decel
        FRM_Client_FirmataDevice($hash)->stepper_step($hash->{STEPPERNUM},$direction,$steps,$speed,$accel,$decel);
      };
      last;
    };
  }
}

sub
FRM_STEPPER_Get
{
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  shift @a;
  my $name = $hash->{NAME};
  my $command = shift @a;
  return "Unknown argument $command, choose one of " . join(" ", sort keys %gets) unless defined($gets{$command});
}


sub FRM_STEPPER_State($$$$)
{
	my ($hash, $tim, $sname, $sval) = @_;
	
STATEHANDLER: {
		$sname eq "value" and do {
			if (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") { 
				FRM_STEPPER_Set($hash,$hash->{NAME},$sval);
			}
			last;
		}
	}
}

sub
FRM_STEPPER_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            FRM_Client_AssignIOPort($hash,$value);
            FRM_Init_Client($hash) if (defined ($hash->{IODev}));
          }
          last;
        };
      }
    }
  };
  if ($@) {
    $@ =~ /^(.*)( at.*FHEM.*)$/;
    $hash->{STATE} = "error setting $attribute to $value: ".$1;
    return "cannot $command attribute $attribute to $value for $name: ".$1;
  }
}

1;

=pod
=begin html

<a name="FRM_STEPPER"></a>
<h3>FRM_STEPPER</h3>
<ul>
  represents a stepper-motor attached to digital-i/o pins of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a><br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_STEPPERdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_STEPPER [DRIVER|TWO_WIRE|FOUR_WIRE] &lt;directionPin&gt &lt;stepPin&gt [motorPin3 motorPin4] stepsPerRev [stepper-id]</code><br>
  Defines the FRM_STEPPER device.
  <li>[DRIVER|TWO_WIRE|FOUR_WIRE] defines the control-sequence being used to drive the motor.
    <ul>
      <li>DRIVER: motor is attached via a smart circuit that is controlled via two lines: 1 line defines the direction to turn, the other triggers one step per impluse.</li>
      <li>FOUR_WIRE: motor is attached via four wires each driving one coil individually.</li>
      <li>TWO_WIRE: motor is attached via two wires. This mode makes use of the fact that at any time two of the four motor
coils are the inverse of the other two so by using an inverting circuit to drive the motor the number of control connections can be reduced from 4 to 2.</li>
    </ul>
  </li>
  <li>
    <ul>
      <li>The sequence of control signals for 4 control wires is as follows:<br>
<br>
<code>
Step C0 C1 C2 C3<br>
   1  1  0  1  0<br>
   2  0  1  1  0<br>
   3  0  1  0  1<br>
   4  1  0  0  1<br>
</code>
      </li>
      <li>The sequence of controls signals for 2 control wires is as follows:<br>
(columns C1 and C2 from above):<br>
<br>
<code>
Step C0 C1<br>
   1  0  1<br>
   2  1  1<br>
   3  1  0<br>
   4  0  0<br>
</code>
      </li>
    </ul>
  </li>
  <li>
  If your stepper-motor does not move or does move but only in a single direction you will have to rearrage the pin-numbers to match the control sequence.<br>
  that can be archived either by rearranging the physical connections, or by mapping the connection to the pin-definitions in FRM_STEPPERS define:<br>
  e.g. the widely used cheap 28byj-48 you can get for few EUR on eBay including a simple ULN2003 driver interface may be defined by<br>
  <code>define stepper FRM_STEPPER FOUR_WIRE 7 5 6 8 64 0</code><br>
  when being connected to the arduio with:<br>
  <code>motor pin1 <-> arduino pin5<br>
  motor pin2 <-> arduino pin6<br>
  motor pin3 <-> arduino pin7<br>
  motor pin4 <-> arduino pin8<br>
  motor pin5 <-> ground</code><br>
  </li>
  </ul>
  
  <br>
  <a name="FRM_STEPPERset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; reset</code>
  <li>resets the reading 'position' to 0 without moving the motor</li>
  <br>
  <code>set &lt;name&gt; position &lt;position&gt; [speed] [acceleration] [deceleration]</code>
  <li>moves the motor to the absolute position specified. positive or negative integer<br>
  speed (10 * revolutions per minute, optional), defaults to 30, higher numbers are faster) At 2048 steps per revolution (28byj-48) a speed of 30 results in 3 rev/min<br>
  acceleration and deceleration are optional.<br>
  </li>
  <br>
  <code>set &lt;name&gt; step &lt;stepstomove&gt; [speed] [accel] [decel]</code>
  <li>moves the motor the number of steps specified. positive or negative integer<br>
  speed, accelleration and deceleration are optional.<br>
  </li>
  </ul>
  <a name="FRM_STEPPERget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_STEPPERattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>restoreOnStartup &lt;on|off&gt;</li>
      <li>restoreOnReconnect &lt;on|off&gt;</li>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li>>speed (same meaning as in 'set position')</li>
      <li>acceleration (same meaning as in 'set position')</li>
      <li>deceleration (same meaning as in 'set position')</li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut

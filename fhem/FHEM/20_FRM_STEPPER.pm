########################################################################################
# $Id$
########################################################################################

=encoding UTF-8

=head1 NAME

FHEM module for two/four Firmata stepper motor output pins

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013 ntruchess
Copyright (C) 2020 jensb

All rights reserved

This script is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this script; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

A copy of the GNU General Public License, Version 2 can also be found at

http://www.gnu.org/licenses/old-licenses/gpl-2.0.

This copyright notice MUST APPEAR in all copies of the script!

=cut

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

#####################################

# (min) number of arguments
my %sets = (
  "reset:noArg" => 0,
  "position"    => 1,
  "step"        => 1,
);

my %gets = (
  "position" => "",
);

sub FRM_STEPPER_Initialize
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_STEPPER_Set";
  $hash->{GetFn}     = "FRM_STEPPER_Get";
  $hash->{DefFn}     = "FRM_STEPPER_Define";
  $hash->{InitFn}    = "FRM_STEPPER_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_STEPPER_Attr";
  $hash->{StateFn}   = "FRM_STEPPER_State";

  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off speed acceleration deceleration IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub FRM_STEPPER_Define
{
  my ($hash, $def) = @_;

  # verify define arguments
  my $usage = "usage: define <name> FRM_STEPPER [DRIVER|TWO_WIRE|FOUR_WIRE] directionPin stepPin [motorPin3 motorPin4] stepsPerRev [id]";

  my @a = split("[ \t][ \t]*", $def);
  my $args = [@a[2..scalar(@a)-1]];
  return $usage unless defined $args;

  my $driver = shift @$args;
  return $usage unless ( $driver eq 'DRIVER' or $driver eq 'TWO_WIRE' or $driver eq 'FOUR_WIRE' );
  return $usage if (($driver eq 'DRIVER' or $driver eq 'TWO_WIRE') and (scalar(@$args) < 3 or scalar(@$args) > 4));
  return $usage if (($driver eq 'FOUR_WIRE') and (scalar(@$args) < 5 or scalar(@$args) > 6));

  $hash->{DRIVER} = $driver;

  $hash->{PIN1} = shift @$args;
  $hash->{PIN2} = shift @$args;

  if ($driver eq 'FOUR_WIRE') {
    $hash->{PIN3} = shift @$args;
    $hash->{PIN4} = shift @$args;
  }

  $hash->{STEPSPERREV} = shift @$args;
  $hash->{STEPPERNUM} = shift @$args;

  my $ret = FRM_Client_Define($hash, $def);
  if ($ret) {
    return $ret;
  }
  return undef;
}

sub FRM_STEPPER_Init
{
  my ($hash,$args) = @_;
  my $name = $hash->{NAME};

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  eval {
    FRM_Client_AssignIOPort($hash);
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->stepper_config(
      $hash->{STEPPERNUM},
      $hash->{DRIVER},
      $hash->{STEPSPERREV},
      $hash->{PIN1},
      $hash->{PIN2},
      $hash->{PIN3},
      $hash->{PIN4});
    $firmata->observe_stepper(0, \&FRM_STEPPER_observer, $hash );
  };
  if ($@) {
    my $ret = FRM_Catch($@);
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }

  $hash->{POSITION} = 0;
  $hash->{DIRECTION} = 0;
  $hash->{STEPS} = 0;
  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{"stateFormat"} = "position";
  }

  main::readingsSingleUpdate($hash,"state","Initialized",1);

  return undef;
}

sub FRM_STEPPER_observer
{
  my ( $stepper, $hash ) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: observer pins: ".$hash->{PIN1}.",".$hash->{PIN2}.(defined ($hash->{PIN3}) ? ",".$hash->{PIN3} : ",-").(defined ($hash->{PIN4}) ? ",".$hash->{PIN4} : ",-")." stepper: ".$stepper;
  my $position = $hash->{DIRECTION} ? $hash->{POSITION} - $hash->{STEPS} : $hash->{POSITION} + $hash->{STEPS};
  $hash->{POSITION} = $position;
  $hash->{DIRECTION} = 0;
  $hash->{STEPS} = 0;
  main::readingsSingleUpdate($hash,"position",$position,1);
}

sub FRM_STEPPER_Set
{
  my ($hash, $name, $cmd, @a) = @_;

  return "set command missing" if(!defined($cmd));
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return "unknown set command '$cmd', choose one of " . join(" ", sort keys %sets) if ($cmd eq '?' || @match == 0);
  return "$cmd requires (at least) $sets{$match[0]} argument(s)" unless (@a >= $sets{$match[0]});

  my $value = shift @a;
  SETHANDLER: {
    $cmd eq "reset" and do {
      $hash->{POSITION} = 0;
      main::readingsSingleUpdate($hash,"position",0,1);
      last;
    };
    $cmd eq "position" and do {
      if (defined($main::defs{$name}{IODev_ERROR})) {
        return 'Perl module Device::Firmata not properly installed';
      }
      my $position = $hash->{POSITION};
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
        FRM_Client_FirmataDevice($hash)->stepper_step($hash->{STEPPERNUM},$direction,$steps,$speed,$accel,$decel);
      };
      if ($@) {
        my $ret = FRM_Catch($@);
        $hash->{STATE} = "set $cmd error: " . $ret;
        return $hash->{STATE};
      }
      last;
    };
    $cmd eq "step" and do {
      if (defined($main::defs{$name}{IODev_ERROR})) {
        return 'Perl module Device::Firmata not properly installed';
      }
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
        FRM_Client_FirmataDevice($hash)->stepper_step($hash->{STEPPERNUM},$direction,$steps,$speed,$accel,$decel);
      };
      if ($@) {
        my $ret = FRM_Catch($@);
        $hash->{STATE} = "set $cmd error: " . $ret;
        return $hash->{STATE};
      }
      last;
    };
  }

  return undef;
}

sub FRM_STEPPER_Get
{
  my ($hash, $name, $cmd, @a) = @_;

  return "get command missing" if(!defined($cmd));
  return "unknown get command '$cmd', choose one of " . join(":noArg ", sort keys %gets) . ":noArg" if(!defined($gets{$cmd}));

  GETHANDLER: {
    $cmd eq 'position' and do {
      return $hash->{POSITION};
    };
  }

  return undef;
}


sub FRM_STEPPER_State
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

sub FRM_STEPPER_Attr
{
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
    my $ret = FRM_Catch($@);
    $hash->{STATE} = "$command $attribute error: " . $ret;
    return $hash->{STATE};
  }
}

1;

=pod

=head1 CHANGES

  05.09.2020 jensb
    o check for IODev install error in Init and Set
    o prototypes removed
    o get position implemented
    o set argument verifier improved
    o module help updated
    o moved define argument verification and decoding from Init to Define

  22.10.2020 jensb
    o annotaded module help of attributes for FHEMWEB

=cut


=pod

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary Firmata: rotary encoder input

=item summary_DE Firmata: Drehgeber Eingang

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="FRM_STEPPER"></a>
<h3>FRM_STEPPER</h3>
<ul>
  represents a stepper-motor attached to digital-i/o pins of an <a href="http://www.arduino.cc">Arduino</a>
  running <a href="http://www.firmata.org">Firmata</a><br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br>

  <a name="FRM_STEPPERdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FRM_STEPPER [DRIVER|TWO_WIRE|FOUR_WIRE] &lt;directionPin&gt &lt;stepPin&gt [motorPin3 motorPin4] stepsPerRev [stepper-id]</code><br>
    Defines the FRM_STEPPER device.
    <li>[DRIVER|TWO_WIRE|FOUR_WIRE] defines the control-sequence being used to drive the motor.
      <ul>
        <li>DRIVER: motor is attached via a smart circuit that is controlled via two lines: 1 line defines the
        direction to turn, the other triggers one step per impluse.
        </li>
        <li>FOUR_WIRE: motor is attached via four wires each driving one coil individually.</li>
        <li>TWO_WIRE: motor is attached via two wires. This mode makes use of the fact that at any time two of
        the four motor coils are the inverse of the other two so by using an inverting circuit to drive the motor
        the number of control connections can be reduced from 4 to 2.
        </li>
      </ul>
    </li>
    <li>
      <ul>
        <li>The sequence of control signals for 4 control wires is as follows:<br><br>

          <code>
          Step C0 C1 C2 C3<br>
             1  1  0  1  0<br>
             2  0  1  1  0<br>
             3  0  1  0  1<br>
             4  1  0  0  1<br>
          </code>
        </li>
        <li>The sequence of controls signals for 2 control wires is as follows:<br>
        (columns C1 and C2 from above):<br><br>

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
    If your stepper-motor does not move or does move but only in a single direction you will have to rearrage
    the pin-numbers to match the control sequence. That can be archived either by rearranging the physical
    connections, or by mapping the connection to the pin-definitions in FRM_STEPPERS define:<br>
    e.g. the widely used cheap 28byj-48 you can get for few EUR on eBay including a simple ULN2003 driver
    interface may be defined by<br>
    <code>define stepper FRM_STEPPER FOUR_WIRE 7 5 6 8 64 0</code><br>
    when being connected to the arduio with:<br><br>

      <code>
      motor pin1 <-> arduino pin5<br>
      motor pin2 <-> arduino pin6<br>
      motor pin3 <-> arduino pin7<br>
      motor pin4 <-> arduino pin8<br>
      motor pin5 <-> ground
      </code>
    </li><br>
  </ul><br>

  <a name="FRM_STEPPERset"></a>
  <b>Set</b><br>
  <ul>
    <code>set &lt;name&gt; reset</code>
    <li>resets the reading 'position' to 0 without moving the motor</li><br>

    <code>set &lt;name&gt; position &lt;position&gt; [speed] [acceleration] [deceleration]</code>
    <li>moves the motor to the absolute position specified. positive or negative integer<br>
    speed (10 * revolutions per minute, optional), defaults to 30, higher numbers are faster.
    At 2048 steps per revolution (28byj-48) a speed of 30 results in 3 rev/min<br>
    acceleration and deceleration are optional.<br>
    </li><br>

    <code>set &lt;name&gt; step &lt;stepstomove&gt; [speed] [accel] [decel]</code>
    <li>moves the motor the number of steps specified. positive or negative integer<br>
    speed, accelleration and deceleration are optional.<br>
    </li>
  </ul><br>

  <a name="FRM_STEPPERget"></a>
  <b>Get</b><br>
  <ul>
    <code>get &lt;position&gt;</code>
    <li>returns the current position value</li>
  </ul><br>

  <a name="FRM_STEPPERattr"></a>
  <b>Attributes</b><br>
  <ul>
    <a name="restoreOnStartup"/>
    <li>restoreOnStartup &lt;on|off&gt;</li>

    <a name="restoreOnReconnect"/>
    <li>restoreOnReconnect &lt;on|off&gt;</li>

    <a name="IODev"/>
    <li><a href="#IODev">IODev</a><br>
    Specify which <a href="#FRM">FRM</a> to use. Only required if there is more than one FRM-device defined.
    </li>

    <a name="speed"/>
    <li>>speed (same meaning as in 'set position')</li>

    <a name="acceleration"/>
    <li>acceleration (same meaning as in 'set position')</li>

    <a name="deceleration"/>
    <li>deceleration (same meaning as in 'set position')</li>

    <li><a href="#attributes">global attributes</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul><br>

=end html

=begin html_DE

<a name="FRM_STEPPER"></a>
<h3>FRM_STEPPER</h3>
<ul>
  Die Modulbeschreibung von FRM_STEPPER gibt es nur auf <a href="commandref.html#FRM_STEPPER">Englisch</a>. <br>
</ul><br>

=end html_DE

=cut

########################################################################################
# $Id$
########################################################################################

=encoding UTF-8

=head1 NAME

FHEM module for one Firmata PMW controlled servo output

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

# number of arguments
my %sets = (
  "angle" => 1,
);

sub FRM_SERVO_Initialize
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

sub FRM_SERVO_Init
{
  my ($hash,$args) = @_;
  my $name = $hash->{NAME};

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  my $ret = FRM_Init_Pin_Client($hash,$args,Device::Firmata::Constants->PIN_SERVO);
  if (defined($ret)) {
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }

  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $hash->{resolution}=$firmata->{metadata}{servo_resolutions}{$hash->{PIN}} if (defined $firmata->{metadata}{servo_resolutions});
    FRM_SERVO_apply_attribute($hash,"max-pulse"); #sets min-pulse as well
  };
  if ($@) {
    $ret = FRM_Catch($@);
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }

  main::readingsSingleUpdate($hash,"state","Initialized",1);

  return undef;
}

sub FRM_SERVO_Attr
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
        ($attribute eq "min-pulse" || $attribute eq "max-pulse") and do {
          if ($main::init_done) {
            if (defined($main::defs{$name}{IODev_ERROR})) {
              die 'Perl module Device::Firmata not properly installed';
            }
            $main::attr{$name}{$attribute}=$value;
            FRM_SERVO_apply_attribute($hash,$attribute);
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

sub FRM_SERVO_apply_attribute
{
  my ($hash,$attribute) = @_;
  if ( $attribute eq "min-pulse" || $attribute eq "max-pulse" ) {
    my $name = $hash->{NAME};
    # defaults are taken from: http://arduino.cc/en/Reference/ServoAttach
    FRM_Client_FirmataDevice($hash)->servo_config($hash->{PIN},{min_pulse => main::AttrVal($name,"min-pulse",544), max_pulse => main::AttrVal($name,"max-pulse",2400)});
  }
}

sub FRM_SERVO_Set
{
  my ($hash, $name, $cmd, @a) = @_;

  return "set command missing" if(!defined($cmd));
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return "unknown set command '$cmd', choose one of " . join(" ", sort keys %sets) if ($cmd eq '?' || @match == 0);
  return "$cmd requires $sets{$match[0]} argument" unless (@a == $sets{$match[0]});

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  my $value = shift @a;
  eval {
    FRM_Client_FirmataDevice($hash)->servo_write($hash->{PIN},$value);
    main::readingsSingleUpdate($hash,"state",$value, 1);
  };
  if ($@) {
    my $ret = FRM_Catch($@);
    $hash->{STATE} = "set $cmd error: " . $ret;
    return $hash->{STATE};
  }

  return undef;
}

1;

=pod

=head1 CHANGES

  05.09.2020 jensb
    o check for IODev install error in Init and Set
    o prototypes removed
    o set argument verifier improved

  19.10.2020 jensb
    o annotaded module help of attributes for FHEMWEB

=cut


=pod

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary Firmata: PWM controlled servo output

=item summary_DE Firmata: PWM gesteuerter Servo Ausgang

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="FRM_SERVO"/>
<h3>FRM_SERVO</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured to drive a pwm-controlled servo-motor.<br>
  The value set will be drive the shaft of the servo to the specified angle. see <a href="http://arduino.cc/en/Reference/ServoWrite">Servo.write</a> for values and range<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br>

  <a name="FRM_SERVOdefine"/>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_SERVO &lt;pin&gt;</code> <br>
  Defines the FRM_SERVO device. &lt;pin&gt> is the arduino-pin to use.
  </ul>

  <br>
  <a name="FRM_SERVOset"/>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; angle &lt;value&gt;</code><br>sets the angle of the servo-motors shaft to the value specified (in degrees).<br>
  </ul>

  <a name="FRM_SERVOget"/>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>

  <a name="FRM_SERVOattr"/>
  <b>Attributes</b><br>
  <ul>
    <a name="IODev"/>
    <li><a href="#IODev">IODev</a><br>
    Specify which <a href="#FRM">FRM</a> to use. Only required if there is more than one FRM-device defined.
    </li>

    <a name="min-pulse"/>
    <li>min-pulse<br>
    sets the minimum puls-width to use. Defaults to 544. For most servos this translates into a rotation of 180° counterclockwise.
    </li>

    <a name="max-pulse"/>
    <li>max-pulse<br>
    sets the maximum puls-width to use. Defaults to 2400. For most servos this translates into a rotation of 180° clockwise.
    </li>

    <li><a href="#attributes">global attributes</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul><br>

=end html

=begin html_DE

<a name="FRM_SERVO"/>
<h3>FRM_SERVO</h3>
<ul>
  Die Modulbeschreibung von FRM_SERVO gibt es nur auf <a href="commandref.html#FRM_SERVO">Englisch</a>. <br>
</ul><br>

=end html_DE

=cut

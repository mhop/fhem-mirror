########################################################################################
# $Id$
########################################################################################

=encoding UTF-8

=head1 NAME

FHEM module for two Firmata rotary encoder input pins

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
  "reset:noArg" => 0,
  "offset"      => 1,
);

my %gets = (
  "position" => "",
  "offset"   => "",
  "value"    => "",
);

sub FRM_ROTENC_Initialize
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_ROTENC_Set";
  $hash->{GetFn}     = "FRM_ROTENC_Get";
  $hash->{AttrFn}    = "FRM_ROTENC_Attr";
  $hash->{DefFn}     = "FRM_ROTENC_Define";
  $hash->{InitFn}    = "FRM_ROTENC_Init";
  $hash->{UndefFn}   = "FRM_ROTENC_Undef";
  $hash->{StateFn}   = "FRM_ROTENC_State";

  $hash->{AttrList}  = "IODev $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub FRM_ROTENC_Define
{
  my ($hash, $def) = @_;

  # verify define arguments
  my $usage = "usage: define <name> FRM_ROTENC pinA pinB [id]";

  my @a = split("[ \t]+", $def);
  return $usage if (scalar(@a) < 4);
  my $args = [@a[2..scalar(@a)-1]];

  $hash->{PINA} = @$args[0];
  $hash->{PINB} = @$args[1];

  $hash->{ENCODERNUM} = defined @$args[2] ? @$args[2] : 0;

  my $ret = FRM_Client_Define($hash, $def);
  if ($ret) {
    return $ret;
  }
  return undef;
}

sub FRM_ROTENC_Init
{
  my ($hash,$args) = @_;
  my $name = $hash->{NAME};

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  eval {
    FRM_Client_AssignIOPort($hash);
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->encoder_attach($hash->{ENCODERNUM}, $hash->{PINA}, $hash->{PINB});
    $firmata->observe_encoder($hash->{ENCODERNUM}, \&FRM_ROTENC_observer, $hash );
  };
  if ($@) {
    my $ret = FRM_Catch($@);
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }

  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{"stateFormat"} = "position";
  }

  $hash->{offset} = ReadingsVal($name,"position",0);

  main::readingsSingleUpdate($hash,"state","Initialized",1);

  return undef;
}

sub FRM_ROTENC_observer
{
  my ($encoder, $value, $hash) = @_;
  my $name = $hash->{NAME};
  Log3 ($name, 5, "$name: observer pins: ".$hash->{PINA}.", ".$hash->{PINB}." encoder: ".$encoder." position: ".$value."\n");
  main::readingsBeginUpdate($hash);
  main::readingsBulkUpdate($hash,"position",$value+$hash->{offset}, 1);
  main::readingsBulkUpdate($hash,"value",$value, 1);
  main::readingsEndUpdate($hash,1);
}

sub FRM_ROTENC_Set
{
  my ($hash, $name, $cmd, @a) = @_;

  return "set command missing" if(!defined($cmd));
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return "unknown set command '$cmd', choose one of " . join(" ", sort keys %sets) if ($cmd eq '?' || @match == 0);
  return "$cmd requires $sets{$match[0]} argument(s)" unless (@a == $sets{$match[0]});

  my $value = shift @a;
  SETHANDLER: {
    $cmd eq "reset" and do {
      if (defined($main::defs{$name}{IODev_ERROR})) {
        return 'Perl module Device::Firmata not properly installed';
      }
      eval {
        FRM_Client_FirmataDevice($hash)->encoder_reset_position($hash->{ENCODERNUM});
      };
      main::readingsBeginUpdate($hash);
      main::readingsBulkUpdate($hash,"position",$hash->{offset},1);
      main::readingsBulkUpdate($hash,"value",0,1);
      main::readingsEndUpdate($hash,1);
      last;
    };
    $cmd eq "offset" and do {
      $hash->{offset} = $value;
      readingsSingleUpdate($hash,"position",ReadingsVal($name,"value",0)+$value,1);
      last;
    };
  }
}

sub FRM_ROTENC_Get
{
  my ($hash, $name, $cmd, @a) = @_;

  return "get command missing" if(!defined($cmd));
  return "unknown get command '$cmd', choose one of " . join(":noArg ", sort keys %gets) . ":noArg" if(!defined($gets{$cmd}));

  GETHANDLER: {
    $cmd eq "position" and do {
      return ReadingsVal($name,"position","0");
    };
    $cmd eq "offset" and do {
      return $hash->{offset};
    };
    $cmd eq "value" and do {
      return ReadingsVal($name,"value","0");
    };
  }
  return undef;
}

sub FRM_ROTENC_Attr
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

sub FRM_ROTENC_Undef
{
  my ($hash, $name) = @_;

  my $pinA = $hash->{PINA};
  my $pinB = $hash->{PINB};
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->encoder_detach($hash->{ENCODERNUM});
  };

  $hash->{PIN} = $hash->{PINA};
  FRM_Client_Undef($hash, $name);
  $hash->{PIN} = $hash->{PINB};
  FRM_Client_Undef($hash, $name);

  return undef;
}

sub FRM_ROTENC_State
{
  my ($hash, $tim, $sname, $sval) = @_;
  if ($sname eq "position") {
    $hash->{offset} = $sval;
  }
  return undef;
}

1;

=pod

=head1 CHANGES

  05.09.2020 jensb
    o check for IODev install error in Init, Set and Undef
    o prototypes removed
    o set argument verifier improved
    o moved define argument verification and decoding from Init to Define

  19.10.2020 jensb
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

<a name="FRM_ROTENC"/>
<h3>FRM_ROTENC</h3>
<ul>
  represents a rotary-encoder attached to two pins of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a><br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br>

  <a name="FRM_ROTENCdefine"/>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_ROTENC &lt;pinA&gt; &lt;pinB&gt; [id]</code> <br>
  Defines the FRM_ROTENC device. &lt;pinA&gt> and &lt;pinA&gt> are the arduino-pins to use.<br>
  [id] is the instance-id of the encoder. Must be a unique number per FRM-device (rages from 0-4 depending on Firmata being used, optional if a single encoder is attached to the arduino).<br>
  </ul>

  <br>
  <a name="FRM_ROTENCset"/>
  <b>Set</b><br>
  <ul>
    <li>reset<br>
    resets to value of 'position' to 0<br></li>
    <li>offset &lt;value&gt;<br>
    set offset value of 'position'<br></li>
  </ul><br>

  <a name="FRM_ROTENCget"/>
  <b>Get</b>
  <ul>
    <li>position<br>
    returns the position of the rotary-encoder attached to pinA and pinB of the arduino<br>
    the 'position' is the sum of 'value' and 'offset'<br></li>
    <li>offset<br>
    returns the offset value<br>
    on shutdown of fhem the latest position-value is saved as new offset.<br></li>
    <li>value<br>
    returns the raw position value as it's reported by the rotary-encoder attached to pinA and pinB of the arduino<br>
    this value is reset to 0 whenever Arduino restarts or Firmata is reinitialized<br></li>
  </ul><br>

  <a name="FRM_ROTENCattr"/>
  <b>Attributes</b><br>
  <ul>
    <a name="IODev"/>
    <li><a href="#IODev">IODev</a><br>
    Specify which <a href="#FRM">FRM</a> to use. Only required if there is more than one FRM-device defined.
    </li>

    <li><a href="#attributes">global attributes</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul><br>

=end html

=begin html_DE

<a name="FRM_ROTENC"/>
<h3>FRM_ROTENC</h3>
<ul>
  Die Modulbeschreibung von FRM_ROTENC gibt es nur auf <a href="commandref.html#FRM_ROTENC">Englisch</a>. <br>
</ul><br>

=end html_DE

=cut

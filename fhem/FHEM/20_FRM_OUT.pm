########################################################################################
# $Id$
########################################################################################

=encoding UTF-8

=head1 NAME

FHEM module for one Firmata digial output pin

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013 ntruchess
Copyright (C) 2016 jensb

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

#add FHEM/lib to @INC if it's not already included. Should rather be in fhem.pl than here though...
BEGIN {
  if (!grep(/FHEM\/lib$/,@INC)) {
    foreach my $inc (grep(/FHEM$/,@INC)) {
      push @INC,$inc."/lib";
    };
  };
};

use SetExtensions;

#####################################

# number of arguments
my %sets = (
  "on:noArg"  => 0,
  "off:noArg" => 0,
);

sub FRM_OUT_Initialize
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_OUT_Set";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_OUT_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_OUT_Attr";
  $hash->{StateFn}   = "FRM_OUT_State";

  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off activeLow:yes,no IODev valueMode:send,receive,bidirectional $main::readingFnAttributes";

  main::LoadModule("FRM");
}

sub FRM_OUT_Init
{
  my ($hash,$args) = @_;
  my $name = $hash->{NAME};

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  my $ret = FRM_Init_Pin_Client($hash, $args, Device::Firmata::Constants->PIN_OUTPUT);
  if (defined($ret)) {
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }

  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    my $pin = $hash->{PIN};
    $firmata->observe_digital($pin,\&FRM_OUT_observer,$hash);
  };
  if ($@) {
    $ret = FRM_Catch($@);
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }

  if (!(defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{"stateFormat"} = "value";
  }

  my $value = ReadingsVal($name,"value",undef);
  if (!defined($value)) {
    readingsSingleUpdate($hash,"value","off",0);
  }

  if (AttrVal($name, "restoreOnReconnect", "on") eq "on") {
    FRM_OUT_Set($hash,$name,$value);
  }

  main::readingsSingleUpdate($hash,"state","Initialized",1);

  return undef;
}

sub FRM_OUT_observer
{
  my ($pin,$old,$new,$hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: observer pin: ".$pin.", old: ".(defined $old? $old : "--").", new: ".(defined $new? $new : "--");
  if (AttrVal($hash->{NAME}, "activeLow", "no") eq "yes") {
    $old = $old == Device::Firmata::Constants->PIN_LOW ? Device::Firmata::Constants->PIN_HIGH : Device::Firmata::Constants->PIN_LOW if (defined $old);
    $new = $new == Device::Firmata::Constants->PIN_LOW ? Device::Firmata::Constants->PIN_HIGH : Device::Firmata::Constants->PIN_LOW;
  }
  my $changed = !defined($old) || ($old != $new);
  if ($changed && (AttrVal($hash->{NAME}, "valueMode", "send") ne "send")) {
    main::readingsSingleUpdate($hash, "value", $new == Device::Firmata::Constants->PIN_HIGH? "on" : "off", 1);
  }
}

sub FRM_OUT_Set
{
  my ($hash, $name, $cmd, @a) = @_;

  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return SetExtensions($hash, join(" ", keys %sets), $name, $cmd, @a) unless @match == 1;
  return "$cmd requires $sets{$match[0]} arguments" unless (@a == $sets{$match[0]});

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  my $value = Device::Firmata::Constants->PIN_LOW;
  my $invert = AttrVal($hash->{NAME}, "activeLow", "no");
  SETHANDLER: {
    $cmd eq "on" and do {
      $value = $invert eq "yes" ? Device::Firmata::Constants->PIN_LOW : Device::Firmata::Constants->PIN_HIGH;
      last;
    };
    $cmd eq "off" and do {
      $value = $invert eq "yes" ? Device::Firmata::Constants->PIN_HIGH : Device::Firmata::Constants->PIN_LOW;
      last;
    };
  };

  eval {
    FRM_Client_FirmataDevice($hash)->digital_write($hash->{PIN},$value);
    if (AttrVal($hash->{NAME}, "valueMode", "send") ne "receive") {
      main::readingsSingleUpdate($hash,"value",$cmd, 1);
    }
  };
  if ($@) {
    my $ret = FRM_Catch($@);
    $hash->{STATE} = "set $cmd error: " . $ret;
    return $hash->{STATE};
  }

  return undef;
}

sub FRM_OUT_State
{
  my ($hash, $tim, $sname, $sval) = @_;

  STATEHANDLER: {
    $sname eq "value" and do {
      if (AttrVal($hash->{NAME},"restoreOnStartup", "on") eq "on") {
        FRM_OUT_Set($hash,$hash->{NAME},$sval);
      }
      last;
    }
  }
}

sub FRM_OUT_Attr
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

        $attribute eq "activeLow" and do {
          my $oldval = AttrVal($hash->{NAME},"activeLow", "no");
          if ($oldval ne $value) {
            # toggle output with attribute change
            $main::attr{$hash->{NAME}}{activeLow} = $value;
            if ($main::init_done) {
              my $value = ReadingsVal($name,"value",undef);
              FRM_OUT_Set($hash,$hash->{NAME},$value);
            }
          };
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

  2016 jensb
    o new sub FRM_OUT_observer, modified sub FRM_OUT_Init
      to receive output state from Firmata device
    o support attribute "activeLow"

  01.01.2018 jensb
    o create reading "value" in FRM_OUT_Init if missing

  02.01.2018 jensb
    o new attribute "valueMode" to control how "value" reading is updated

  14.01.2018 jensb
    o fix "uninitialised" when calling FRM_OUT_Set without command

  23.08.2020 jensb
    o check for IODev install error in Init
    o prototypes removed
    o set argument metadata added
    o set argument verifier improved

  22.10.2020 jensb
    o annotaded module help of attributes for FHEMWEB

=cut


=pod

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary Firmata: digital output

=item summary_DE Firmata: digitaler Ausang

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="FRM_OUT"/>
<h3>FRM_OUT</h3>
<ul>
  This module represents a pin of a <a href="http://www.firmata.org">Firmata device</a>
  that should be configured as a digital output.<br><br>

  Requires a defined <a href="#FRM">FRM</a> device to work. The pin must be listed in
  the internal reading "<a href="#FRMinternals">output_pins</a>"<br>
  of the FRM device (after connecting to the Firmata device) to be used as digital output.<br><br>

  <a name="FRM_OUTdefine"/>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; FRM_OUT &lt;pin&gt;</code> <br>
    Defines the FRM_OUT device. &lt;pin&gt> is the arduino-pin to use.
  </ul><br>

  <a name="FRM_OUTset"/>
  <b>Set</b><br>
  <ul>
    <code>set &lt;name&gt; on|off</code><br><br>
  </ul>
  <ul>
    <a href="#setExtensions">set extensions</a> are supported<br>
  </ul><br>

  <a name="FRM_OUTget"/>
  <b>Get</b><br>
  <ul>
    N/A
  </ul><br>

  <a name="FRM_OUTattr"/>
  <b>Attributes</b><br>
  <ul>
    <a name="restoreOnStartup"/>
    <li>restoreOnStartup &lt;on|off&gt;, default: on<br>
    Set output value in Firmata device on FHEM startup (if device is already connected) and
    whenever the <em>setstate</em> command is used.
    </li>

    <a name="restoreOnReconnect"/>
    <li>restoreOnReconnect &lt;on|off&gt;, default: on<br>
    Set output value in Firmata device after IODev is initialized.
    </li>

    <a name="activeLow"/>
    <li>activeLow &lt;yes|no&gt;, default: no</li>

    <a name="IODev"/>
    <li><a href="#IODev">IODev</a><br>
    Specify which <a href="#FRM">FRM</a> to use. Only required if there is more than one FRM-device defined.
    </li>

    <a name="valueMode"/>
    <li>valueMode &lt;send|receive|bidirectional&gt;, default: send<br>
    Define how the reading <em>value</em> is updated:<br>
      <ul>
        <li>send - after sending</li>
        <li>receive - after receiving</li>
        <li>bidirectional - after sending and receiving</li>
      </ul>
    </li>

    <li><a href="#attributes">global attributes</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul><br>

  <a name="FRM_OUTnotes"/>
  <b>Notes</b><br>
  <ul>
    <li>attribute <i>stateFormat</i><br>
    In most cases it is a good idea to assign "value" to the attribute <i>stateFormat</i>. This will show the state
    of the pin in the web interface.
    </li>
    <li>attribute <i>valueMode</i><br>
    For modes "receive" and "bidirectional" to work the default Firmata application code must
    be modified in function "<code>setPinModeCallback</code>":<br>
    add "<code> || mode == OUTPUT</code>" to the if condition for "<code>portConfigInputs[pin / 8] |= (1 << (pin & 7));</code>" to enable<br>
    reporting the output state (as if the pin were an input). This is of interest if you have custom code in your Firmata device that my change to pin state.<br>
    the state of an output or you want a feedback from the Firmata device after the output state was changed.
    </li>
  </ul>
</ul><br>

=end html

=begin html_DE

<a name="FRM_OUT"/>
<h3>FRM_OUT</h3>
<ul>
  Die Modulbeschreibung von FRM_OUT gibt es nur auf <a href="commandref.html#FRM_OUT">Englisch</a>. <br>
</ul><br>

=end html_DE

=cut

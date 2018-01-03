########################################################################################
#
# $Id$
#
# FHEM module for one Firmata digial output pin
#
########################################################################################
#
#  LICENSE AND COPYRIGHT
#
#  Copyright (C) 2013 ntruchess
#  Copyright (C) 2016 jensb
#
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
########################################################################################

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
  $hash->{AttrFn}    = "FRM_OUT_Attr";
  $hash->{StateFn}   = "FRM_OUT_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off activeLow:yes,no IODev valueMode:send,receive,bidirectional $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_OUT_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_OUTPUT);
	return $ret if (defined $ret);
	eval {
      my $firmata = FRM_Client_FirmataDevice($hash);
      my $pin = $hash->{PIN};
      $firmata->observe_digital($pin,\&FRM_OUT_observer,$hash);
	};  
	my $name = $hash->{NAME};
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "value";
	}
	my $value = ReadingsVal($name,"value",undef);
	if (!defined($value)) {
		readingsSingleUpdate($hash,"value","off",0);
	}  
	if (AttrVal($hash->{NAME},"restoreOnReconnect", "on") eq "on") {
		FRM_OUT_Set($hash,$name,$value);
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_OUT_observer($$$$)
{
  my ($pin,$old,$new,$hash) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "onDigitalMessage for pin ".$pin.", old: ".(defined $old? $old : "--").", new: ".(defined $new? $new : "--");
  if (AttrVal($hash->{NAME}, "activeLow", "no") eq "yes") {
    $old = $old == PIN_LOW ? PIN_HIGH : PIN_LOW if (defined $old);
    $new = $new == PIN_LOW ? PIN_HIGH : PIN_LOW;
  }
  my $changed = !defined($old) || ($old != $new);
  if ($changed && (AttrVal($hash->{NAME}, "valueMode", "send") ne "send")) {
    main::readingsSingleUpdate($hash, "value", $new == PIN_HIGH? "on" : "off", 1);
  }
}

sub
FRM_OUT_Set($$$)
{
  my ($hash, $name, $cmd, @a) = @_;
  my $value;
  my $invert = AttrVal($hash->{NAME},"activeLow", "no");
  if ($cmd eq "on") {
  	$value = $invert eq "yes" ? PIN_LOW : PIN_HIGH;
  } elsif ($cmd eq "off") {
  	$value = $invert eq "yes" ? PIN_HIGH : PIN_LOW;
  } else {
  	my $list = "on off";
    return SetExtensions($hash, $list, $name, $cmd, @a);
  }
  eval {
    FRM_Client_FirmataDevice($hash)->digital_write($hash->{PIN},$value);
    if (AttrVal($hash->{NAME}, "valueMode", "send") ne "receive") {
      main::readingsSingleUpdate($hash,"value",$cmd, 1);
    }
  };
  return $@;
}

sub FRM_OUT_State($$$$)
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

sub
FRM_OUT_Attr($$$$) {
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
    $@ =~ /^(.*)( at.*FHEM.*)$/;
    $hash->{STATE} = "error setting $attribute to $value: ".$1;
    return "cannot $command attribute $attribute to $value for $name: ".$1;
  }
}

1;

=pod

  CHANGES

  2016 jensb
    o new sub FRM_OUT_observer, modified sub FRM_OUT_Init
      to receive output state from Firmata device
    o support attribute "activeLow"
  01.01.2018 jensb
    o create reading "value" in FRM_OUT_Init if missing
  02.01.2018 jensb
    o new attribute "valueMode" to control how "value" reading is updated

=cut

=pod
=item device
=item summary Firmata: digital output
=item summary_DE Firmata: digitaler Ausang
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
  <ul>
  <a href="#setExtensions">set extensions</a> are supported<br>
  </ul>
  <a name="FRM_OUTget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_OUTattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>restoreOnStartup &lt;on|off&gt;, default: on<br>
      Set output value in Firmata device on FHEM startup (if device is already connected) and
      whenever the <em>setstate</em> command is used.
      </li>
      <li>restoreOnReconnect &lt;on|off&gt;, default: on<br>
      Set output value in Firmata device after IODev is initialized.
      </li>
      <li>activeLow &lt;yes|no&gt;, default: no</li>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#FRM">FRM</a> to use. (Optional, only required if there is more
      than one FRM-device defined.)
      </li>
      <li>valueMode &lt;send|receive|bidirectional&gt;, default: send<br>
      Define how the reading <em>value</em> is updated:<br>
      <ul>
        <li>send - after sending</li>
        <li>receive - after receiving</li>
        <li>bidirectional - after sending and receiving</li>
      </ul>
      If you have custom code in your Firmata device that can change the state of an output
      you can enable receive or bidirectional mode. For this to work the default Firmata application code must 
      also be modified in function <em>setPinModeCallback</em>: add <ins>|| mode == OUTPUT</ins> 
      to the if condition for <em>portConfigInputs[pin / 8] |= (1 << (pin & 7));</em> to enable 
      reporting the output state as if the pin is an input.
      </li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut

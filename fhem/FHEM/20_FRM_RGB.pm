########################################################################################
# $Id$
########################################################################################

=encoding UTF-8

=head1 NAME

FHEM module for one Firmata PWM output pin for controlling RGB LEDs

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

use vars qw{%attr %defs $readingFnAttributes};
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

use Color qw/ :all /;
use SetExtensions qw/ :all /;

#####################################

my %gets = (
  "rgb"          => "",
  "RGB"          => "",
  "pct"          => "",
);

# number of arguments
my %sets = (
  "on:noArg"            => 0,
  "off:noArg"           => 0,
  "toggle:noArg"        => 0,
  "rgb:colorpicker,RGB" => 1,
  "pct:slider,0,1,100"  => 1,
  "dimUp:noArg"         => 0,
  "dimDown:noArg"       => 0,
);

sub FRM_RGB_Initialize
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_RGB_Set";
  $hash->{GetFn}     = "FRM_RGB_Get";
  $hash->{DefFn}     = "FRM_RGB_Define";
  $hash->{InitFn}    = "FRM_RGB_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_RGB_Attr";
  $hash->{StateFn}   = "FRM_RGB_State";

  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev loglevel:0,1,2,3,4,5 $readingFnAttributes";

  LoadModule("FRM");
  FHEM_colorpickerInit();
}

sub FRM_RGB_Define
{
  my ($hash, $def) = @_;
  $attr{$hash->{NAME}}{webCmd} = "rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:toggle:on:off";
  return FRM_Client_Define($hash,$def);
}

sub FRM_RGB_Init
{
  my ($hash,$args) = @_;
  my $name = $hash->{NAME};

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  my $ret = FRM_Init_Pin_Client($hash, $args, Device::Firmata::Constants->PIN_PWM);
  if (defined($ret)) {
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }
  my @pins = ();
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $hash->{PIN} = "";
    foreach my $pin (@{$args}) {
      $firmata->pin_mode($pin, Device::Firmata::Constants->PIN_PWM);
      push @pins,{
        pin     => $pin,
        "shift" => defined $firmata->{metadata}{pwm_resolutions} ? $firmata->{metadata}{pwm_resolutions}{$pin}-8 : 0,
      };
      $hash->{PIN} .= $hash->{PIN} eq "" ? $pin : " $pin";
    }
    $hash->{PINS} = \@pins;
  };
  if ($@) {
    $ret = FRM_Catch($@);
    readingsSingleUpdate($hash, 'state', "error initializing: $ret", 1);
    return $ret;
  }
  if (!(defined AttrVal($name,"stateFormat",undef))) {
    $attr{$name}{"stateFormat"} = "rgb";
  }
  my $value = ReadingsVal($name,"rgb",undef);
  if (defined $value and AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
    FRM_RGB_Set($hash,$name,"rgb",$value);
  }
  $hash->{toggle} = "off";
  $hash->{".dim"} = {
    bri => 50,
    channels => [(255) x @{$hash->{PINS}}],
  };
  readingsSingleUpdate($hash,"state","Initialized",1);
  return undef;
}

sub FRM_RGB_Set
{
  my ($hash, $name, $cmd, @a) = @_;

  return "set command missing" if(!defined($cmd));
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  return SetExtensions($hash, join(" ", keys %sets), $name, $cmd, @a) unless @match == 1;
  return "$cmd requires $sets{$match[0]} argument(s)" unless (@a == $sets{$match[0]});

  if (defined($main::defs{$name}{IODev_ERROR})) {
    return 'Perl module Device::Firmata not properly installed';
  }

  my $value = shift @a;
  eval {
    SETHANDLER: {
      $cmd eq "on" and do {
        FRM_RGB_SetChannels($hash,(0xFF) x scalar(@{$hash->{PINS}}));
        $hash->{toggle} = "on";
        last;
      };
      $cmd eq "off" and do {
        FRM_RGB_SetChannels($hash,(0x00) x scalar(@{$hash->{PINS}}));
        $hash->{toggle} = "off";
        last;
      };
      $cmd eq "toggle" and do {
        my $toggle = $hash->{toggle};
        TOGGLEHANDLER: {
          $toggle eq "off" and do {
            $hash->{toggle} = "up";
            FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{".dim"}));
            last;
          };
          $toggle eq "up" and do {
            FRM_RGB_SetChannels($hash,(0xFF) x @{$hash->{PINS}});
            $hash->{toggle} = "on";
            last;
          };
          $toggle eq "on" and do {
            $hash->{toggle} = "down";
            FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{".dim"}));
            last;
          };
          $toggle eq "down" and do {
            FRM_RGB_SetChannels($hash,(0x0) x @{$hash->{PINS}});
            $hash->{toggle} = "off";
            last;
          };
        };
        last;
      };
      $cmd eq "rgb" and do {
        my $numPins = scalar(@{$hash->{PINS}});
        my $nybles = $numPins << 1;
        die "$value is not the right format" unless( $value =~ /^[\da-f]{$nybles}$/i );
        my @channels = RgbToChannels($value,$numPins);
        FRM_RGB_SetChannels($hash,@channels);
        RGBHANDLER: {
          $value =~ /^0{$nybles}$/ and do {
            $hash->{toggle} = "off";
            last;
          };
          $value =~ /^f{$nybles}$/i and do {
            $hash->{toggle} = "on";
            last;
          };
          $hash->{toggle} = "up";
        };
        $hash->{".dim"} = ChannelsToBrightness(@channels);
        last;
      };
      $cmd eq "pct" and do {
        $hash->{".dim"}->{bri} = $value;
        FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{".dim"}));
        last;
      };
      $cmd eq "dimUp" and do {
        $hash->{".dim"}->{bri} = $hash->{".dim"}->{bri} > 90 ? 100 : $hash->{".dim"}->{bri}+10;
        FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{".dim"}));
        last;
      };
      $cmd eq "dimDown" and do {
        $hash->{".dim"}->{bri} = $hash->{".dim"}->{bri} < 10 ? 0 : $hash->{".dim"}->{bri}-10;
        FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{".dim"}));
        last;
      };
    }
  };
  if ($@) {
    my $ret = FRM_Catch($@);
    $hash->{STATE} = "set $cmd error: " . $ret;
    return $hash->{STATE};
  }

	return undef;
}

sub FRM_RGB_Get
{
  my ($hash, $name, $cmd, @a) = @_;

  return "get command missing" if(!defined($cmd));
  return "unknown get command '$cmd', choose one of " . join(":noArg ", sort keys %gets) . ":noArg" if(!defined($gets{$cmd}));

  GETHANDLER: {
    $cmd eq 'rgb' and do {
      return ReadingsVal($name,"rgb",undef);
    };
    $cmd eq 'RGB' and do {
      return ChannelsToRgb(@{$hash->{".dim"}->{channels}});
    };
    $cmd eq 'pct' and do {
      return $hash->{".dim"}->{bri};
    };
  }
}

sub FRM_RGB_SetChannels
{
  my ($hash,@channels) = @_;

  my $firmata = FRM_Client_FirmataDevice($hash);
  my @pins = @{$hash->{PINS}};
  my @values = @channels;

  while(@values) {
    my $pin = shift @pins;
    my $value = shift @values;
    if ($pin->{"shift"} < 0) {
      $value >>= -$pin->{"shift"};
    } else {
      $value <<= $pin->{"shift"};
    }
    $firmata->analog_write($pin->{pin},$value);
  };
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"rgb",ChannelsToRgb(@channels),1);
  readingsBulkUpdate($hash,"pct",(ChannelsToBrightness(@channels))->{bri},1);
  readingsEndUpdate($hash, 1);
}

sub FRM_RGB_State
{
  my ($hash, $tim, $sname, $sval) = @_;
  if ($sname eq "rgb") {
    FRM_RGB_Set($hash,$hash->{NAME},$sname,$sval);
  }
}

sub FRM_RGB_Attr
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

  30.08.2020 jensb
    o check for IODev install error in Init and Set
    o prototypes removed
    o set argument metadata added
    o get/set argument verifier improved

  19.10.2020 jensb
    o annotaded module help of attributes for FHEMWEB

=cut


=pod

=head1 FHEM COMMANDREF METADATA

=over

=item device

=item summary Firmata: PWM output for RGB-LED

=item summary_DE Firmata: PWM Ausgang für RGB-LED

=back

=head1 INSTALLATION AND CONFIGURATION

=begin html

<a name="FRM_RGB"/>
<h3>FRM_RGB</h3>
<ul>
  allows to drive LED-controllers and other multichannel-devices that use PWM as input by an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  <br>
  The value set will be output by the specified pins as pulse-width-modulated signals.<br>
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br>

  <a name="FRM_RGBdefine"/>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_RGB &lt;pin&gt; &lt;pin&gt; &lt;pin&gt; [pin...]</code> <br>
  Defines the FRM_RGB device. &lt;pin&gt> are the arduino-pin to use.<br>
  For rgb-controlled devices first pin drives red, second pin green and third pin blue.
  </ul>

  <br>
  <a name="FRM_RGBset"/>
  <b>Set</b><br>
  <ul>
    <code>set &lt;name&gt; on</code><br>
    sets the pulse-width of all configured pins to 100%</ul><br>
  <ul>
    <code>set &lt;name&gt; off</code><br>
    sets the pulse-width of all configured pins to 0%</ul><br>
  <ul>
    <a href="#setExtensions">set extensions</a> are supported</ul><br>
  <ul>
    <code>set &lt;name&gt; toggle</code><br>
    toggles in between the last dimmed value, 0% and 100%. If no dimmed value was set before defaults to pulsewidth 50% on all channels</ul><br>
  <ul>
    <code>set &lt;name&gt; rgb &lt;value&gt;</code><br>
    sets the pulse-width of all channels at once. Also sets the value toggle can switch to<br>
    Value is encoded as hex-string, 2-digigs per channel (e.g. FFFFFF for reguler rgb)</ul><br>
  <ul>
    <code>set &lt;name&gt; pct &lt;value&gt;</code><br>
    dims all channels at once while leving the ratio in between the channels unaltered.<br>
    Range is 0-100 ('pct' stands for 'percent')</ul><br>
  <ul>
    <code>set &lt;name&gt; dimUp</code><br>
    dims up by 10%</ul><br>
  <ul>
    <code>set &lt;name&gt; dimDown</code><br>
    dims down by 10%
  </ul><br>

  <a name="FRM_RGBget"/>
  <b>Get</b><br>
  <ul>
    <code>get &lt;name&gt; rgb</code><br>
    returns the values set for all channels. Format is hex, 2 nybbles per channel.
  </ul><br>
  <ul>
    <code>get &lt;name&gt; RGB</code><br>
    returns the values set for all channels in normalized format. Format is hex, 2 nybbles per channel.
    Values are scaled such that the channel with the highest value is set to FF. The real values are calculated
    by multipying each byte with the value of 'pct'.
  </ul><br>
  <ul>
    <code>get &lt;name&gt; pct</code><br>
    returns the value of the channel with the highest value scaled to the range of 0-100 (percent).
  </ul><br>

  <a name="FRM_RGBattr"/>
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

    <li><a href="#attributes">global attributes</a></li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul><br>

=end html

=begin html_DE

<a name="FRM_RGB"/>
<h3>FRM_RGB</h3>
<ul>
  Die Modulbeschreibung von FRM_RGB gibt es nur auf <a href="commandref.html#FRM_RGB">Englisch</a>. <br>
</ul> <br>

=end html_DE

=cut

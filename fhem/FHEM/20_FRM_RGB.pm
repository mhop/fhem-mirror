#############################################
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

use Device::Firmata::Constants  qw/ :all /;
use Color qw/ :all /;
use SetExtensions qw/ :all /;

#####################################

my %gets = (
  "rgb"           => 0,
  "RGB"           => 0,
  "pct"           => 0,
  "devStateIcon"  => 0,
);

my %sets = (
  "on"                  => 0,
  "off"                 => 0,
  "toggle"              => 0,
  "rgb:colorpicker,RGB" => 1,
  "pct:slider,0,1,100"  => 1,
  "fadeTo"              => 2,
  "dimUp"               => 0,
  "dimDown"             => 0,
);

sub
FRM_RGB_Initialize($)
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

sub
FRM_RGB_Define($$)
{
  my ($hash, $def) = @_;
  $attr{$hash->{NAME}}{webCmd} = "rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:toggle:on:off";
  return FRM_Client_Define($hash,$def);
}

sub
FRM_RGB_Init($$)
{
  my ($hash,$args) = @_;
  my $name = $hash->{NAME};
  my $ret = FRM_Init_Pin_Client($hash,$args,PIN_PWM);
  return $ret if (defined $ret);
  my @pins = ();
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $hash->{PIN} = "";
    foreach my $pin (@{$args}) {
      $firmata->pin_mode($pin,PIN_PWM);
      push @pins,{
        pin     => $pin,
        "shift" => defined $firmata->{metadata}{pwm_resolutions} ? $firmata->{metadata}{pwm_resolutions}{$pin}-8 : 0,
      };
      $hash->{PIN} .= $hash->{PIN} eq "" ? $pin : " $pin";
    }
    $hash->{PINS} = \@pins;
    if (! (defined AttrVal($name,"stateFormat",undef))) {
      $attr{$name}{"stateFormat"} = "value";
    }
    my $value = ReadingsVal($name,"rgb",undef);
    if (defined $value and AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
      FRM_RGB_Set($hash,$name,"rgb",$value);
    }
  };
  return $@ if $@;
  $hash->{toggle} = "off";
  $hash->{dim} = {
    bri => 50,
    channels => [(255) x @{$hash->{PINS}}],    
  };
  readingsSingleUpdate($hash,"state","Initialized",1);
  return undef;  
}

sub
FRM_RGB_Set($@)
{
  my ($hash, $name, $cmd, @a) = @_;
  
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  #-- check argument
  return SetExtensions($hash, join(" ", keys %sets), $name, $cmd, @a) unless @match == 1;
  return "$cmd expects $sets{$match[0]} parameters" unless (@a eq $sets{$match[0]});

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
          FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{dim}));
          last;    
        };
        $toggle eq "up" and do {
          FRM_RGB_SetChannels($hash,(0xFF) x @{$hash->{PINS}});
          $hash->{toggle} = "on";
          last;
        };
        $toggle eq "on" and do {
          $hash->{toggle} = "down";
          FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{dim}));
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
      my $arg = $a[0];
      my $numPins = scalar(@{$hash->{PINS}});
      my $nybles = $numPins << 1;
      my @channels = RgbToChannels($arg,$numPins);
      FRM_RGB_SetChannels($hash,@channels);
      RGBHANDLER: {
        $arg =~ /^0{$nybles}$/ and do {
          $hash->{toggle} = "off";
          last;
        };
        $arg =~ /^f{$nybles}$/i and do {
          $hash->{toggle} = "on";
          last;
        };
        $hash->{toggle} = "up";
      };
      $hash->{dim} = ChannelsToBrightness(@channels);
      last;
    };
    $cmd eq "pct" and do {
      $hash->{dim}->{bri} = $a[0];
      FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{dim}));
      last;
    };
    $cmd eq "dimUp" and do {
      $hash->{dim}->{bri} = $hash->{dim}->{bri} > 90 ? 100 : $hash->{dim}->{bri}+10;
      FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{dim})); 
      last; 
    };
    $cmd eq "dimDown" and do {
      $hash->{dim}->{bri} = $hash->{dim}->{bri} < 10 ? 0 : $hash->{dim}->{bri}-10;
      FRM_RGB_SetChannels($hash,BrightnessToChannels($hash->{dim}));
      last;
    };
  }
  return undef;
}

sub
FRM_RGB_Get($@)
{
  my ($hash, $name, $cmd, @a) = @_;
  
  return "FRM_RGB: Get with unknown argument $cmd, choose one of ".join(" ", sort keys %gets)
    unless defined($gets{$cmd});
    
  GETHANDLER: {
    $cmd eq 'rgb' and do {
      return ReadingsVal($name,"rgb",undef);
    };
    $cmd eq 'RGB' and do {
      return ChannelsToRgb(@{$hash->{dim}->{channels}});
    };
    $cmd eq 'pct' and do {
      return $hash->{dim}->{bri};
      return undef;
    };
  }
}

sub
FRM_RGB_SetChannels($$)
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
  readingsSingleUpdate($hash,"rgb",ChannelsToRgb(@channels),1);
}

sub FRM_RGB_State($$$$)
{
	my ($hash, $tim, $sname, $sval) = @_;
	
STATEHANDLER: {
		$sname eq "value" and do {
			if (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") { 
				FRM_RGB_Set($hash,$hash->{NAME},$sval);
			}
			last;
		}
	}
}

sub
FRM_RGB_Attr($$$$) {
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
    }
  }
}

1;

=pod
=begin html

<a name="FRM_PWM"></a>
<h3>FRM_PWM</h3>
<ul>
  represents a pin of an <a href="http://www.arduino.cc">Arduino</a> running <a href="http://www.firmata.org">Firmata</a>
  configured for analog output.<br>
  The value set will be output by the specified pin as a pulse-width-modulated signal.<br> 
  Requires a defined <a href="#FRM">FRM</a>-device to work.<br><br> 
  
  <a name="FRM_PWMdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_PWM &lt;pin&gt;</code> <br>
  Defines the FRM_PWM device. &lt;pin&gt> is the arduino-pin to use.
  </ul>
  
  <br>
  <a name="FRM_PWMset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; value &lt;value&gt;</code><br>
  sets the pulse-width of the signal that is output on the configured arduino pin<br>
  Range is from 0 to 255 (see <a href="http://arduino.cc/en/Reference/AnalogWrite">analogWrite()</a> for details)
  </ul>
  <a name="FRM_PWMget"></a>
  <b>Get</b><br>
  <ul>
  N/A
  </ul><br>
  <a name="FRM_PWMattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>restoreOnStartup &lt;on|off&gt;</li>
      <li>restoreOnReconnect &lt;on|off&gt;</li>
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

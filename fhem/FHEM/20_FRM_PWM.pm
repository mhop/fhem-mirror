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
use SetExtensions qw/ :all /;

#####################################

my %gets = (
  "dim"           => 0,
  "value"         => 0,
  "devStateIcon"  => 0,
);

my %sets = (
  "on"                  => 0,
  "off"                 => 0,
  "toggle"              => 0,
  "value"               => 1,
  "dim:slider,0,1,100"  => 1,
  "fadeTo"              => 2,
  "dimUp"               => 0,
  "dimDown"             => 0,
);

sub
FRM_PWM_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}     = "FRM_PWM_Set";
  $hash->{GetFn}     = "FRM_PWM_Get";
  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_PWM_Init";
  $hash->{UndefFn}   = "FRM_Client_Undef";
  $hash->{AttrFn}    = "FRM_PWM_Attr";
  $hash->{StateFn}   = "FRM_PWM_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
  main::LoadModule("FRM");
}

sub
FRM_PWM_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_PWM);
	return $ret if (defined $ret);
	my $firmata = $hash->{IODev}->{FirmataDevice};
	my $name = $hash->{NAME};
	my $resolution = $firmata->{metadata}{pwm_resolutions}{$hash->{PIN}} if (defined $firmata->{metadata}{pwm_resolutions});
	$hash->{".max"} = defined $resolution ? (1<<$resolution)-1 : 255;
	$hash->{".dim"} = 0;
	$hash->{".toggle"} = "off"; 
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "value";
	}
	my $value = ReadingsVal($name,"value",undef);
	if (defined $value and AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
		FRM_PWM_Set($hash,$name,$value);
	}
	main::readingsSingleUpdate($hash,"state","Initialized",1);
	return undef;
}

sub
FRM_PWM_Set($@)
{
  my ($hash, $name, $cmd, @a) = @_;
  
  my @match = grep( $_ =~ /^$cmd($|:)/, keys %sets );
  #-- check argument
  return SetExtensions($hash, join(" ", keys %sets), $name, $cmd, @a) unless @match == 1;
  return "$cmd expects $sets{$match[0]} parameters" unless (@a eq $sets{$match[0]});

  eval {
    SETHANDLER: {
      my $value = $a[0] if @a; 
      $cmd eq "on" and do {
        FRM_PWM_writeOut($hash,$hash->{".max"});
        $hash->{".toggle"} = "on";
        last;
      };
      $cmd eq "off" and do {
        FRM_PWM_writeOut($hash,0);
        $hash->{".toggle"} = "off";
        last;
      };
      $cmd eq "toggle" and do {
        my $toggle = $hash->{".toggle"};
        TOGGLEHANDLER: {
          $toggle eq "off" and do {
            FRM_PWM_writeOut($hash,$hash->{".dim"});
            $hash->{".toggle"} = "up";
            last;    
          };
          $toggle eq "up" and do {
            FRM_PWM_writeOut($hash,$hash->{".max"});
            $hash->{".toggle"} = "on";
            last;
          };
          $toggle eq "on" and do {
            FRM_PWM_writeOut($hash,$hash->{".dim"});
            $hash->{".toggle"} = "down";
            last;    
          };
          $toggle eq "down" and do {
            FRM_PWM_writeOut($hash,0);
            $hash->{".toggle"} = "off";
            last;
          };
        };
        last;
      };
      $cmd eq "value" and do {
        my $max = $hash->{".max"};
        die "maximum value of $max exceeded: $value" if ($value > $max);
        FRM_PWM_writeOut($hash,$value);
        TOGGLEHANDLER: {
          $value == $max and do {
            $hash->{".toggle"} = "on";
            last;
          };
          $value == 0 and do {
            $hash->{".toggle"} = "off";
            last;
          };
          $hash->{".toggle"} = "up" unless $hash->{".toggle"} eq "down";
          $hash->{".dim"} = $value;
        };
        last;
      };
      $cmd eq "dim" and do {
        die "maximum value of 100 exceeded: $value" if ($value > 100);
        my $dim = int($hash->{".max"}*$value/100);
        FRM_PWM_writeOut($hash,$dim);
        TOGGLEHANDLER: {
          $value == 100 and do {
            $hash->{".toggle"} = "on";
            last;
          };
          $value == 0 and do {
            $hash->{".toggle"} = "off";
            last;
          };
          $hash->{".toggle"} = "up" unless $hash->{".toggle"} eq "down";
          $hash->{".dim"} = $dim;
        };
        last;
      };
      $cmd eq "fadeTo" and do {
        die "fadeTo not implemented yet";
      };
      $cmd eq "dimUp" and do {
        my $dim = $hash->{".dim"};
        my $max = $hash->{".max"};
        if ($dim > $max * 0.9) {
          $dim = $max;
          $hash->{".toggle"} = "on";
        } else {
          $dim = $dim + $max / 10;
          $hash->{".toggle"} = "up" unless $hash->{".toggle"} eq "down";
        }
        FRM_PWM_writeOut($hash,$dim);
        $hash->{".dim"} = $dim;
        last;
      };
      $cmd eq "dimDown" and do {
        my $step = $hash->{".max"} / 10;
        my $dim = $hash->{".dim"};
        if ($dim < $step) {
          $dim = 0;
          $hash->{".toggle"} = "off";
        } else {
          $dim = $dim - $step;
          $hash->{".toggle"} = "down" unless $hash->{".toggle"} eq "up";
        }
        FRM_PWM_writeOut($hash,$dim);
        $hash->{".dim"} = $dim;
        last;
      };
    }
  };
	if ($@) {
  	$@ =~ /^(.*)( at.*FHEM.*)$/;
  	$hash->{STATE} = "error setting '$cmd': ".(defined $1 ? $1 : $@);
		return "error setting '$hash->{NAME} $cmd': ".(defined $1 ? $1 : $@);
	}
	return undef;
}

sub
FRM_PWM_writeOut($$)
{
  my ($hash,$value) = @_;
  FRM_Client_FirmataDevice($hash)->analog_write($hash->{PIN},$value);
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"value",$value, 1);
  readingsBulkUpdate($hash,"dim",int($value*100/$hash->{".max"}), 1);
  readingsEndUpdate($hash, 1);
}

sub
FRM_PWM_Get($@)
{
  my ($hash, $name, $cmd, @a) = @_;
  
  return "FRM_PWM: Get with unknown argument $cmd, choose one of ".join(" ", sort keys %gets)
    unless defined($gets{$cmd});
    
  GETHANDLER: {
    $cmd eq 'dim' and do {
      return ReadingsVal($name,"dim",undef);
    };
    $cmd eq 'value' and do {
      return ReadingsVal($name,"value",undef);
    };
    $cmd eq 'devStateIcon' and do {
      return return "not implemented yet";
    };
  }
}

sub
FRM_PWM_State($$$$)
{
  my ($hash, $tim, $sname, $sval) = @_;
  if ($sname eq "value") {
    FRM_PWM_Set($hash,$hash->{NAME},$sname,$sval);
  }
}

sub
FRM_PWM_Attr($$$$)
{
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
  <code>set &lt;name&gt; on</code><br>
  sets the pulse-width to 100%<br>
  </ul>
  <ul>
  <code>set &lt;name&gt; off</code><br>
  sets the pulse-width to 0%<br>
  </ul>
  <ul>
  <a href="#setExtensions">set extensions</a> are supported<br>
  </ul>
  <ul>
  <code>set &lt;name&gt; toggle</code><br>
  toggles the pulse-width in between to the last value set by 'value' or 'dim' and 0 respectivly 100%<br>
  </ul>
  <ul>
  <code>set &lt;name&gt; value &lt;value&gt;</code><br>
  sets the pulse-width to the value specified<br>
  Range is from 0 to 255 (for 8-bit resolution) (see <a href="http://arduino.cc/en/Reference/AnalogWrite">analogWrite()</a> for details)<br>
  </ul>
  <ul>
  <code>set &lt;name&gt; dim &lt;value&gt;</code><br>
  sets the pulse-width to the value specified in percent<br>
  Range is from 0 to 100<br>
  </ul>
  <ul>
  <code>set &lt;name&gt; dimUp</code><br>
  increases the pulse-width by 10%<br>
  </ul>
  <ul>
  <code>set &lt;name&gt; dimDown</code><br>
  decreases the pulse-width by 10%<br>
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

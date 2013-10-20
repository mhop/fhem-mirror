#############################################
package main;

use strict;
use warnings;
use Device::Firmata;
use Device::Firmata::Constants  qw/ :all /;

#####################################

my %sets = (
  "text" => "",
  "home" => "",
  "clear" => "",
  "display" => "on,off",
  "cursor" => "",
  "scroll" => "left,right",
);

my %gets = (
);

sub
FRM_LCD_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "FRM_Client_Define";
  $hash->{InitFn}    = "FRM_LCD_Init";
  $hash->{SetFn}     = "FRM_LCD_Set";
  $hash->{AttrFn}    = "FRM_LCD_Attr";
  $hash->{StateFn}   = "FRM_LCD_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev model backLight:on,off blink:on,off autoClear:on,off autoBreak:on,off loglevel:0,1,2,3,4,5 $main::readingFnAttributes";
  #  autoScroll:on,off direction:leftToRight,rightToLeft do not work reliably
}

sub
FRM_LCD_Init($)
{
	my ($hash,$args) = @_;
 	my $u = "wrong syntax: define <name> FRM_LCD <type> <size-x> <size-y> [<address>]";

	return $u if(int(@$args) < 3);
  
	$hash->{type} = shift @$args;
	$hash->{sizex} = shift @$args;
	$hash->{sizey} = shift @$args;
	$hash->{address} = shift @$args if (@$args); 

	return "no IODev set" unless defined $hash->{IODev};
	return "no FirmataDevice assigned to ".$hash->{IODev}->{NAME} unless defined $hash->{IODev}->{FirmataDevice};  	

	my $name = $hash->{NAME};
	if (($hash->{type} eq "i2c") and defined $hash->{address}) {
		require LiquidCrystal_I2C;
		my $lcd = LiquidCrystal_I2C->new($hash->{address},$hash->{sizex},$hash->{sizey});
		$lcd->attach($hash->{IODev}->{FirmataDevice});
		$lcd->init();
		$hash->{lcd} = $lcd;
		FRM_LCD_Apply_Attribute($name,"backLight");
#		FRM_LCD_Apply_Attribute($name,"autoscroll");
#		FRM_LCD_Apply_Attribute($name,"direction");
		FRM_LCD_Apply_Attribute($name,"blink");
	}
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "text";
	}
	my $value = ReadingsVal($name,"text",undef);
	if (defined $value and AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
		FRM_LCD_Set($hash,$name,"text",$value);
	}
	
	
	return undef;
}

sub FRM_LCD_Attr(@) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $main::defs{$name};
	if ($command eq "set") {
		$main::attr{$name}{$attribute}=$value;
		FRM_LCD_Apply_Attribute($name,$attribute);
	}
}

sub FRM_LCD_Apply_Attribute {
	my ($name,$attribute) = @_;
	my $lcd = $main::defs{$name}{lcd};
	if (defined $lcd) {
		ATTRIBUTE_HANDLER: {
			$attribute eq "backLight" and do {
				if (AttrVal($name,"backLight","on") eq "on") {
					$lcd->backlight();  
				} else {
					$lcd->noBacklight();
				}
				last;
			};
			$attribute eq "autoScroll" and do {
				if (AttrVal($name,"autoScroll","on") eq "on") {
					$lcd->autoscroll();  
				} else {
					$lcd->noAutoscroll();
				}
				last;
			};
			$attribute eq "direction" and do {
				if (AttrVal($name,"direction","leftToRight") eq "leftToRight") {
					$lcd->leftToRight();  
				} else {
					$lcd->rightToLeft();
				}
				last;
			};
			$attribute eq "blink" and do {
				if (AttrVal($name,"blink","off") eq "on") {
					$lcd->blink();  
				} else {
					$lcd->noBlink();
				}
				last;
			};
		}
	}
}

sub FRM_LCD_Set(@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  my $command = $a[1];
  my $value = $a[2];
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$command}));
  my $lcd = $hash->{lcd};
  return unless defined $lcd;
  COMMAND_HANDLER: {
    $command eq "text" and do {
    	if (AttrVal($hash->{NAME},"autoClear","on") eq "on") {
    		$lcd->clear();
    	}
    	if (AttrVal($hash->{NAME},"autoBreak","on") eq "on") {
    		my $sizex = $hash->{sizex};
    		my $sizey = $hash->{sizey};
    		my $start = 0;
    		my $len = length $value;
    		for (my $line = 0;$line<$sizey;$line++) {
    			$lcd->setCursor(0,$line);
    			if ($start<$len) {
    				$lcd->print(substr $value, $start, $sizex);
    			} else {
    				last;
    			}
    			$start+=$sizex;
    		}
    	} else {
    		$lcd->print($value);
    	}
    	main::readingsSingleUpdate($hash,"text",$value,1);
    	last;
    };
    $command eq "home" and do {
    	$lcd->home();
    	last;
    };
    $command eq "clear" and do {
    	$lcd->clear();
    	main::readingsSingleUpdate($hash,"text","",1);
    	last;
    };
    $command eq "display" and do {
    	if ($value ne "off") {
			$lcd->display();    		
    	} else {
    		$lcd->noDisplay();
    	}
    	last;
    };
    $command eq "cursor" and do {
    	my ($x,$y) = split ",",$value;
    	$lcd->setCursor($x,$y);
    	last;
    };
    $command eq "scroll" and do {
    	if ($value eq "left") {
			$lcd->scrollDisplayLeft();    		
    	} else {
    		$lcd->scrollDisplayRight();
    	}
    	last;
    };
  }
}

sub FRM_LCD_State($$$$)
{
	my ($hash, $tim, $sname, $sval) = @_;
	
STATEHANDLER: {
		$sname eq "text" and do {
			if (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") { 
				FRM_LCD_Set($hash,$hash->{NAME},$sname,$sval);
			}
			last;
		}
	}
}

1;

=pod
=begin html

<a name="FRM_LCD"></a>
<h3>FRM_LCD</h3>
<ul>
  drives LiquidCrystal Displays (LCD) that are connected to Firmata (via I2C).
  Supported are Displays that use a PCF8574T as I2C Bridge (as found on eBay when searching for
  'LCD' and 'I2C'). Tested is the 1602 type (16 characters, 2 Lines), the 2004 type (and other cheap chinise-made
  I2C-LCDs for Arduino) ship with the same library, so they should work as well.
  See <a name="LiquidCrystal tutorial">http://arduino.cc/en/Tutorial/LiquidCrystal</a> for details about
  how to hook up the LCD to the arduino.

  Requires a defined <a href="#FRM">FRM</a>-device to work.<br>
  this FRM-device has to be configures for i2c by setting attr 'i2c-config' on the FRM-device<br>
    
  <a name="FRM_LCDdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM_LCD i2c &lt;size-x&gt; &lt;size-y&gt; &lt;i2c-address&gt;</code> <br>
  Specifies the FRM_LCD device.<br>
  <li>size-x is the number of characters per line</li>
  <li>size-y is the numbers of rows.</li>
  <li>i2c-address is the (device-specific) address of the ic on the i2c-bus</li>
  </ul>
  
  <br>
  <a name="FRM_LCDset"></a>
  <b>Set</b><br>
  <ul>
  <code>set &lt;name&gt; text &lt;text to be displayed&gt;</code><br>
  </ul>
  <a name="FRM_I2Cget"></a>
  <b>Get</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="FRM_LCDattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>backLight &lt;on|off&gt;</li>
      <li>autoClear &lt;on|off&gt;</li>
      <li>autoBreak &lt;on|off&gt;</li>
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

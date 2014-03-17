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
  "text" => "",
  "home" => "noArg",
  "clear" => "noArg",
  "display" => "on,off",
  "cursor" => "",
  "scroll" => "left,right",
  "backlight" => "on,off",
  "reset" => "noArg",
  "writeXY" => ""
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
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev model"
  ." backLight:on,off blink:on,off autoClear:on,off autoBreak:on,off $main::readingFnAttributes";
  #  autoScroll:on,off direction:leftToRight,rightToLeft do not work reliably
  main::LoadModule("FRM");
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

	my $name = $hash->{NAME};
	if (($hash->{type} eq "i2c") and defined $hash->{address}) {
		eval {
			FRM_Client_AssignIOPort($hash);
			my $firmata = FRM_Client_FirmataDevice($hash);
			require LiquidCrystal_I2C;
			my $lcd = LiquidCrystal_I2C->new($hash->{address},$hash->{sizex},$hash->{sizey});
			$lcd->attach($firmata);
			$lcd->init();
			$hash->{lcd} = $lcd;
			FRM_LCD_Apply_Attribute($name,"backLight");
#			FRM_LCD_Apply_Attribute($name,"autoscroll");
#			FRM_LCD_Apply_Attribute($name,"direction");
			FRM_LCD_Apply_Attribute($name,"blink");
		};
		return FRM_Catch($@) if $@;
	}
	if (! (defined AttrVal($name,"stateFormat",undef))) {
		$main::attr{$name}{"stateFormat"} = "text";
	}
	if (AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
		foreach my $reading (("display","scroll","backlight","text","writeXY")) {
			if (defined (my $value = ReadingsVal($name,$reading,undef))) {
				FRM_LCD_Set($hash,$name,$reading,split " ", $value);
			}
		}
	}
	return undef;
}

sub
FRM_LCD_Attr($$$$) {
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
      $main::attr{$name}{$attribute}=$value;
      FRM_LCD_Apply_Attribute($name,$attribute);
      }
    }
  };
  my $ret = FRM_Catch($@) if $@;
  if ($ret) {
    $hash->{STATE} = "error setting $attribute to $value: ".$ret;
    return "cannot $command attribute $attribute to $value for $name: ".$ret;
  }
}

sub FRM_LCD_Apply_Attribute {
	my ($name,$attribute) = @_;
	my $lcd = $main::defs{$name}{lcd};
	if ($main::init_done and defined $lcd) {
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
  if(!defined($sets{$command})) {
  	my @commands = ();
    foreach my $key (sort keys %sets) {
      push @commands, $sets{$key} ? $key.":".join(",",$sets{$key}) : $key;
    }
    return "Unknown argument $a[1], choose one of " . join(" ", @commands);
  }
  my $lcd = $hash->{lcd};
  return unless defined $lcd;
  eval {
    COMMAND_HANDLER: {
      $command eq "text" and do {
        shift @a;
        shift @a;
        $value = join(" ", @a);
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
      $command eq "reset" and do {
        $lcd->init();
#        $hash->{lcd} = $lcd;
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
        main::readingsSingleUpdate($hash,"display",$value,1);
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
        main::readingsSingleUpdate($hash,"scroll",$value,1);
        last;
      };
      $command eq "backlight" and do {
        if ($value eq "on") {
          $lcd->backlight();
        } else {
          $lcd->noBacklight();
        }
        main::readingsSingleUpdate($hash,"backlight",$value,1);
        last;
      };
      $command eq "writeXY" and do { 
        my ($x,$y,$l,$al) = split(",",$value);
        $lcd->setCursor($x,$y);
        shift @a; shift @a; shift @a;
        my $t = join(" ", @a);
        my %umlaute = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss" ," - " => " " ,"©"=>"@");
        my $umlautkeys = join ("|", keys(%umlaute));
        $t =~ s/($umlautkeys)/$umlaute{$1}/g;
        my $sl = length $t;
        if ($sl > $l) {
          $t = substr($t,0,$l);
        }
        if ($sl < $l) {
          my $dif = "";
          for (my $i=$sl; $i<$l; $i++) {
            $dif .= " ";
          }
          $t = ($al eq "l") ? $t.$dif : $dif.$t;
        }
        $lcd->print($t);
        main::readingsSingleUpdate($hash,"writeXY",$value." ".$t,1);
        readingsSingleUpdate($hash,"state",$t,1);
        last; #"X=$x|Y=$y|L=$l|Text=$t";
      };
    }
  };
  return FRM_Catch($@) if $@;
  return undef;
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
      <li><code>set &lt;name&gt; text &lt;text to be displayed&gt;</code><br></li>
      <li><code>set &lt;name&gt; home</code><br></li>
      <li><code>set &lt;name&gt; clear</code><br></li>
      <li><code>set &lt;name&gt; display on|off</code><br></li>
      <li><code>set &lt;name&gt; cursor &lt;...&gt;</code><br></li>
      <li><code>set &lt;name&gt; scroll left|right</code><br></li>
      <li><code>set &lt;name&gt; backlight on|off</code><br></li>
      <li><code>set &lt;name&gt; reset</code><br></li>
      <li><code>set &lt;name&gt; writeXY x-pos,y-pos,len[,l] &lt;text to be displayed&gt;</code><br></li>
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

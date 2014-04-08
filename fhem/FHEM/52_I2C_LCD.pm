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

my %mapping = (
  'P0' => 'RS',
  'P1' => 'RW',
  'P2' => 'E',
  'P3' => 'LED',
  'P4' => 'D4',
  'P5' => 'D5',
  'P6' => 'D6',
  'P7' => 'D7',
);

my @LEDPINS = sort values %mapping;

sub
I2C_LCD_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "I2C_LCD_Define";
  $hash->{InitFn}    = "I2C_LCD_Init";
  $hash->{SetFn}     = "I2C_LCD_Set";
  $hash->{AttrFn}    = "I2C_LCD_Attr";
  $hash->{StateFn}   = "I2C_LCD_State";
  
  $hash->{AttrList}  = "restoreOnReconnect:on,off restoreOnStartup:on,off IODev model pinMapping"
  ." backLight:on,off blink:on,off autoClear:on,off autoBreak:on,off $main::readingFnAttributes";
  #  autoScroll:on,off direction:leftToRight,rightToLeft do not work reliably
}

sub
I2C_LCD_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE}="defined";

  my @keyvalue = ();
  while (my ($key, $value) = each %mapping) {
    push @keyvalue,"$key=$value";
  };
  $main::attr{$a[0]}{"pinMapping"} = join (',',sort @keyvalue);
  $hash->{mapping} = \%mapping;
  
  if ($main::init_done) {
    eval {
      I2C_LCD_Init($hash,[@a[2..scalar(@a)-1]]);
    };
    return I2C_LCD_Catch($@) if $@;
  }

  return undef;
}

sub
I2C_LCD_Init($$)
{
  my ($hash,$args) = @_;
  my $u = "wrong syntax: define <name> I2C_LCD <size-x> <size-y> [<address>]";

  return $u if(int(@$args) < 2);
  
  $hash->{sizex} = shift @$args;
  $hash->{sizey} = shift @$args;
  if (defined (my $address = shift @$args)) {
    $hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
  }

  my $name = $hash->{NAME};
  if (defined $hash->{I2C_Address}) {
    eval {
      main::AssignIoPort($hash,AttrVal($hash->{NAME},"IODev",undef));
      require LiquidCrystal;
      my $lcd = LiquidCrystal->new($hash->{sizex},$hash->{sizey});
      $lcd->setMapping($hash->{mapping});
      $lcd->attach(I2C_LCD_IO->new($hash));
      $lcd->init();
      $hash->{lcd} = $lcd;
      I2C_LCD_Apply_Attribute($name,"backLight");
#      I2C_LCD_Apply_Attribute($name,"autoscroll");
#      I2C_LCD_Apply_Attribute($name,"direction");
      I2C_LCD_Apply_Attribute($name,"blink");
    };
    return I2C_LCD_Catch($@) if $@;
  }
  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{"stateFormat"} = "text";
  }
  if (AttrVal($hash->{NAME},"restoreOnReconnect","on") eq "on") {
    foreach my $reading (("display","scroll","backlight","text","writeXY")) {
      if (defined (my $value = ReadingsVal($name,$reading,undef))) {
        I2C_LCD_Set($hash,$name,$reading,split " ", $value);
      }
    }
  }
  return undef;
}

sub
I2C_LCD_Attr($$$$) {
  my ($command,$name,$attribute,$value) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ($command eq "set") {
      ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $value)) {
            main::AssignIoPort($hash,$value);
            my @def = split (' ',$hash->{DEF});
            I2C_LCD_Init($hash,\@def) if (defined ($hash->{IODev}));
          }
          last;
        };
        $attribute eq "pinMapping" and do {
          my %newMapping = ();
          foreach my $keyvalue (split (/,/,$value)) {
            my ($key,$value) = split (/=/,$keyvalue);
            #Log3 ($name,5,"pinMapping, token: $key=$value, current mapping: $mapping{$key}");
            die "unknown token $key in attribute pinMapping, valid tokens are ".join (',',keys %mapping) unless (defined $mapping{$key});
            die "undefined or invalid value for token $key in attribute pinMapping, valid LED-Pins are ".join (',',@LEDPINS) unless $value and grep (/$value/,@LEDPINS);
            $newMapping{$key} = $value; 
          }
          $hash->{mapping} = \%newMapping;
          I2C_LCD_Init($hash,split (' ',$hash->{DEF})) if ($main::init_done);
          last;
        };
        $main::attr{$name}{$attribute}=$value;
        I2C_LCD_Apply_Attribute($name,$attribute);
      }
    }
  };
  my $ret = I2C_LCD_Catch($@) if $@;
  if ($ret) {
    $hash->{STATE} = "error setting $attribute to $value: ".$ret;
    return "cannot $command attribute $attribute to $value for $name: ".$ret;
  }
}

sub I2C_LCD_Apply_Attribute {
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

sub I2C_LCD_Set(@) {
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
  return I2C_LCD_Catch($@) if $@;
  return undef;
}

sub I2C_LCD_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_LCD_State($$$$)
{
	my ($hash, $tim, $sname, $sval) = @_;
	
STATEHANDLER: {
		$sname eq "text" and do {
			if (AttrVal($hash->{NAME},"restoreOnStartup","on") eq "on") { 
				I2C_LCD_Set($hash,$hash->{NAME},$sname,$sval);
			}
			last;
		}
	}
}

package I2C_LCD_IO;

sub new {
	my ($class,$hash) = @_;
	return bless {
		hash => $hash,
	}, $class;
}

sub write {
	my ( $self, @data ) = @_;
	my $hash = $self->{hash};
	if (defined (my $iodev = $hash->{IODev})) {
		main::CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			i2caddress => $hash->{I2C_Address},
			direction  => "i2cwrite",
			data       => join (' ',@data)
		});
	} else {
		die "no IODev assigned to '$hash->{NAME}'";
	}
}

1;

=pod
=begin html

<a name="I2C_LCD"></a>
<h3>I2C_LCD</h3>
<ul>
  drives LiquidCrystal Displays (LCD) that are connected to Firmata (via I2C).
  Supported are Displays that use a PCF8574T as I2C Bridge (as found on eBay when searching for
  'LCD' and 'I2C'). Tested is the 1602 type (16 characters, 2 Lines), the 2004 type (and other cheap chinise-made
  I2C-LCDs for Arduino) ship with the same library, so they should work as well.
  See <a name="LiquidCrystal tutorial">http://arduino.cc/en/Tutorial/LiquidCrystal</a> for details about
  how to hook up the LCD to the arduino.

  Requires a defined <a href="#I2C">I2C</a>-device to work.<br>
  this I2C-device has to be configures for i2c by setting attr 'i2c-config' on the I2C-device<br>
    
  <a name="I2C_LCDdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; I2C_LCD &lt;size-x&gt; &lt;size-y&gt; &lt;i2c-address&gt;</code> <br>
  Specifies the I2C_LCD device.<br>
  <li>size-x is the number of characters per line</li>
  <li>size-y is the numbers of rows.</li>
  <li>i2c-address is the (device-specific) address of the ic on the i2c-bus</li>
  </ul>
  
  <br>
  <a name="I2C_LCDset"></a>
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
  
  <a name="I2C_I2Cget"></a>
  <b>Get</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="I2C_LCDattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>backLight &lt;on|off&gt;</li>
      <li>autoClear &lt;on|off&gt;</li>
      <li>autoBreak &lt;on|off&gt;</li>
      <li>restoreOnStartup &lt;on|off&gt;</li>
      <li>restoreOnReconnect &lt;on|off&gt;</li>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#I2C">I2C</a> to use. (Optional, only required if there is more
      than one I2C-device defined.)
      </li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut

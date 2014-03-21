# www.DFRobot.com
# last updated on 21/12/2011
# Tim Starling Fix the reset bug (Thanks Tim)
# wiki doc http://www.dfrobot.com/wiki/index.php?title=I2C/TWI_LCD1602_Module_(SKU:_DFR0063)
# Support Forum: http://www.dfrobot.com/forum/
# Compatible with the Arduino IDE 1.0
# Library version:1.1

# When the display powers up, it is configured as follows:
#
# 1. Display clear
# 2. Function set:
#    DL = 1; 8-bit interface data
#    N = 0; 1-line display
#    F = 0; 5x8 dot character font
# 3. Display on/off control:
#    D = 0; Display off
#    C = 0; Cursor off
#    B = 0; Blinking off
# 4. Entry mode set:
#    I/D = 1; Increment by 1
#    S = 0; No shift
#
# Note, however, that resetting the Arduino doesn't reset the LCD, so we
# can't assume that its in that state when a sketch starts (and the
# LiquidCrystal constructor is called).

package LiquidCrystal_I2C;

use warnings;
use strict;

#Basic commands and constants
use constant LCD_CLEARDISPLAY   => 0x01;
use constant LCD_RETURNHOME     => 0x02;
use constant LCD_ENTRYMODESET   => 0x04;
use constant LCD_DISPLAYCONTROL => 0x08;
use constant LCD_CURSORSHIFT    => 0x10;
use constant LCD_FUNCTIONSET    => 0x20;
use constant LCD_SETCGRAMADDR   => 0x40;
use constant LCD_SETDDRAMADDR   => 0x80;

# flags for display entry mode
use constant LCD_ENTRYRIGHT          => 0x00;
use constant LCD_ENTRYLEFT           => 0x02;
use constant LCD_ENTRYSHIFTINCREMENT => 0x01;
use constant LCD_ENTRYSHIFTDECREMENT => 0x00;

# flags for display on/off control
use constant LCD_DISPLAYON  => 0x04;
use constant LCD_DISPLAYOFF => 0x00;
use constant LCD_CURSORON   => 0x02;
use constant LCD_CURSOROFF  => 0x00;
use constant LCD_BLINKON    => 0x01;
use constant LCD_BLINKOFF   => 0x00;

# flags for display/cursor shift
use constant LCD_DISPLAYMOVE => 0x08;
use constant LCD_CURSORMOVE  => 0x00;
use constant LCD_MOVERIGHT   => 0x04;
use constant LCD_MOVELEFT    => 0x00;

# flags for function set
use constant LCD_8BITMODE => 0x10;
use constant LCD_4BITMODE => 0x00;
use constant LCD_2LINE    => 0x08;
use constant LCD_1LINE    => 0x00;
use constant LCD_5x10DOTS => 0x04;
use constant LCD_5x8DOTS  => 0x00;

# flags for backlight control
use constant LCD_BACKLIGHT   => 0x08;
use constant LCD_NOBACKLIGHT => 0x00;

use constant En => 0b00000100;    # Enable bit
use constant Rw => 0b00000010;    # Read / Write bit
use constant Rs => 0b00000001;    # Register select bit

sub print($$) {
	my ($self,$c) = @_;
	my @buf = unpack "c*",$c;
	foreach my $s (@buf) {
		$self->write($s);		
	}
};

sub write($$) {
	my ( $self, $value ) = @_;
	$self->send( $value, Rs );
	return 0;
}

sub new($$$$) {
	my ( $class, $lcd_Addr, $lcd_cols, $lcd_rows ) = @_;
	return bless {
		Addr         => $lcd_Addr,
		cols         => $lcd_cols,
		rows         => $lcd_rows,
		backlightval => LCD_NOBACKLIGHT,
	}, $class;
}

sub init($) {
	my $self = shift;
	$self->init_priv();
}

sub attach($$) {
	my ($self,$dev) = @_;
	$self->{I2CDevice} = $dev;
}

sub init_priv($) {
	my $self = shift;

	$self->{displayfunction} =
	  LCD_4BITMODE | LCD_1LINE |
	  LCD_5x8DOTS;
	$self->begin( $self->{cols}, $self->{rows} );
}

sub begin($$$$) {
	my ( $self, $cols, $lines, $dotsize ) = @_;
	if ( $lines > 1 ) {
		$self->{displayfunction} |= LCD_2LINE;
	}
	$self->{numlines} = $lines;

	# for some 1 line displays you can select a 10 pixel high font
	if ( (defined $dotsize) && ($dotsize != 0) && ( $lines == 1 ) ) {
		$self->{displayfunction} |= LCD_5x10DOTS;
	}

  # SEE PAGE 45/46 FOR INITIALIZATION SPECIFICATION!
  # according to datasheet, we need at least 40ms after power rises above 2.7V
  # before sending commands. Arduino can turn on way befer 4.5V so we'll wait 50
	select( undef, undef, undef, 0.050 );

	# Now we pull both RS and R/W low to begin commands
	$self->expanderWrite( $self->{backlightval} )
	  ;    # reset expanderand turn backlight off (Bit 8 =1)
	select( undef, undef, undef, 1 );

	#put the LCD into 4 bit mode
	# this is according to the hitachi HD44780 datasheet
	# figure 24, pg 46

	# we start in 8bit mode, try to set 4 bit mode
	$self->write4bits( 0x03 << 4 );
	select( undef, undef, undef, 0.0045 );    # wait min 4.1ms

	# second try
	$self->write4bits( 0x03 << 4 );
	select( undef, undef, undef, 0.0045 );    # wait min 4.1ms

	# third go!
	$self->write4bits( 0x03 << 4 );
	select( undef, undef, undef, 0.00015 );

	# finally, set to 4-bit interface
	$self->write4bits( 0x02 << 4 );

	# set # lines, font size, etc.
	$self->command(
		LCD_FUNCTIONSET | $self->{displayfunction} );

	# turn the display on with no cursor or blinking default
	$self->{displaycontrol} =
	  LCD_DISPLAYON | LCD_CURSOROFF |
	  LCD_BLINKOFF;
	$self->display();

	# clear it off
	$self->clear();

	# Initialize to default text direction (for roman languages)
	$self->{displaymode} =
	  LCD_ENTRYLEFT |
	  LCD_ENTRYSHIFTDECREMENT;

	# set the entry mode
	$self->command(
		LCD_ENTRYMODESET | $self->{displaymode} );

	$self->home();

}

#********** high level commands, for the user!

sub clear($) {
	my $self = shift;
	$self->command(LCD_CLEARDISPLAY)
	  ;    # clear display, set cursor position to zero
	select( undef, undef, undef, 0.002 );    # this command takes a long time!
}

sub home($) {
	my $self = shift;
	$self->command(LCD_RETURNHOME)
	  ;                                      # set cursor position to zero
	select( undef, undef, undef, 0.002 );    # this command takes a long time!
}

sub setCursor($$$) {
	my ( $self, $col, $row ) = @_;
	my @row_offsets = ( 0x00, 0x40, 0x14, 0x54 );
	if ( $row > $self->{numlines} ) {
		$row = $self->{numlines} - 1;        # we count rows starting w/0
	}
	$self->command(
		LCD_SETDDRAMADDR | ( $col + $row_offsets[$row] ) );
}

# Turn the display on/off (quickly)
sub noDisplay($) {
	my $self = shift;
	$self->{displaycontrol} &=
	  ~LCD_DISPLAYON;    #TODO validate '~'
	$self->command(
		LCD_DISPLAYCONTROL | $self->{displaycontrol} );
}

sub display($) {
	my $self = shift;
	$self->{displaycontrol} |= LCD_DISPLAYON;
	$self->command(
		LCD_DISPLAYCONTROL | $self->{displaycontrol} );
}

# Turns the underline cursor on/off
sub noCursor($) {
	my $self = shift;
	$self->{displaycontrol} &=
	  ~LCD_CURSORON;    #TODO validate '~'
	$self->command(
		LCD_DISPLAYCONTROL | $self->{displaycontrol} );
}

sub cursor($) {
	my $self = shift;
	$self->{displaycontrol} |= LCD_CURSORON;
	$self->command(
		LCD_DISPLAYCONTROL | $self->{displaycontrol} );
}

# Turn on and off the blinking cursor
sub noBlink($) {
	my $self = shift;
	$self->{displaycontrol} &=
	  ~LCD_BLINKON;    #TODO validate '~'
	$self->command(
		LCD_DISPLAYCONTROL | $self->{displaycontrol} );
}

sub blink($) {
	my $self = shift;
	$self->{displaycontrol} |= LCD_BLINKON;
	$self->command(
		LCD_DISPLAYCONTROL | $self->{displaycontrol} );
}

# These commands scroll the display without changing the RAM
sub scrollDisplayLeft($) {
	my $self = shift;
	$self->command( LCD_CURSORSHIFT |
		  LCD_DISPLAYMOVE |
		  LCD_MOVELEFT );
}

sub scrollDisplayRight($) {
	my $self = shift;
	$self->command( LCD_CURSORSHIFT |
		  LCD_DISPLAYMOVE |
		  LCD_MOVERIGHT );
}

# This is for text that flows Left to Right
sub leftToRight($) {
	my $self = shift;
	$self->{displaymode} |= LCD_ENTRYLEFT;
	$self->command(
		LCD_ENTRYMODESET | $self->{displaymode} );
}

# This is for text that flows Right to Left
sub rightToLeft($) {
	my $self = shift;
	$self->{displaymode} &=
	  ~LCD_ENTRYLEFT;    #TODO validate '~'
	$self->command(
		LCD_ENTRYMODESET | $self->{displaymode} );
}

# This will 'right justify' text from the cursor
sub autoscroll($) {
	my $self = shift;
	$self->{displaymode} |= LCD_ENTRYSHIFTINCREMENT;
	$self->command(
		LCD_ENTRYMODESET | $self->{displaymode} );
}

# This will 'left justify' text from the cursor
sub noAutoscroll($) {
	my $self = shift;
	$self->{displaymode} &=
	  ~LCD_ENTRYSHIFTINCREMENT;    #TODO validate '~'
	$self->command(
		LCD_ENTRYMODESET | $self->{displaymode} );
}

# Allows us to fill the first 8 CGRAM locations
# with custom characters
sub createChar($$$) {
	my ( $self, $location, $charmap ) = @_;
	$location &= 0x7;    # we only have 8 locations 0-7
	$self->command( LCD_SETCGRAMADDR | ( $location << 3 ) );
	for ( my $i = 0 ; $i < 8 ; $i++ ) {
		$self->write( @$charmap[$i] );
	}
}

# Turn the (optional) backlight off/on
sub noBacklight($) {
	my $self = shift;
	$self->{backlightval} = LCD_NOBACKLIGHT;
	$self->expanderWrite(0);
}

sub backlight($) {
	my $self = shift;
	$self->{backlightval} = LCD_BACKLIGHT;
	$self->expanderWrite(0);
}

#*********** mid level commands, for sending data/cmds

sub command($$) {
	my ( $self, $value ) = @_;
	$self->send( $value, 0 );
}

#************ low level data pushing commands **********

# write either command or data
sub send($$$) {
	my ( $self, $value, $mode ) = @_;
	my $highnib = $value & 0xf0;
	my $lownib  = ( $value << 4 ) & 0xf0;
	$self->write4bits( ($highnib) | $mode );
	$self->write4bits( ($lownib) | $mode );
}

sub write4bits($$) {
	my ( $self, $value ) = @_;
	$self->expanderWrite($value);
	$self->pulseEnable($value);
}

sub expanderWrite($$) {
	my ( $self, $data ) = @_;

	$self->{I2CDevice}->i2c_write($self->{Addr},($data) | $self->{backlightval});
}

sub pulseEnable($$) {
	my ( $self, $data ) = @_;
	$self->expanderWrite( $data | En );    # En high
	select( undef, undef, undef, 0.000001 );    # enable pulse must be >450ns
	$self->expanderWrite( $data & ~En )
	  ;                                         # En low TODO: validate '~'
	select( undef, undef, undef, 0.000050 );    # commands need > 37us to settle
}

# Alias functions

sub cursor_on($) {
	my $self = shift;
	$self->cursor();
}

sub cursor_off($) {
	my $self = shift;
	$self->noCursor();
}

sub blink_on($) {
	my $self = shift;
	$self->blink();
}

sub blink_off($) {
	my $self = shift;
	$self->noBlink();
}

sub load_custom_character($$$) {
	my ( $self, $char_num, $rows ) = @_;
	$self->createChar( $char_num, $rows );
}

sub setBacklight($$) {
	my ( $self, $new_val ) = @_;
	if ($new_val) {
		$self->backlight();    # turn backlight on
	}
	else {
		$self->noBacklight();    # turn backlight off
	}
}

# unsupported API functions
sub off($)         { }
sub on($)          { }
sub setDelay ($$$) { }

sub status($) {
	return 0;
}

sub keypad ($) {
	return 0;
}

sub init_bargraph($$) {
	return 0;
}

sub draw_horizontal_graph($$$$$) { }
sub draw_vertical_graph($$$$$)   { }
sub setContrast($$)              { }

1;

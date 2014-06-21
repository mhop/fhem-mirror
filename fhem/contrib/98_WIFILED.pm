# ############################################################################
#
#  FHEM Modue for WLAN based LED Driver
#
# ############################################################################
#
#  This is absolutley open source. Please feel free to use just as you
#  like. Please note, that no warranty is given and no liability 
#  granted
#
# ############################################################################
#
#  we have the following readings
#  state            on|off
#
# ############################################################################
#
#  we have the following attributes
#  timeout          the timeout in seconds for the TCP connection
#
# ############################################################################
#  we have the following internals (all UPPERCASE)
#  RED              last red value 
#  GREEN            last green value
#  BLUE             last blue value
#  IP               the IP of the device
#  RGB              for the RGB Values of color-picker
#  MODE             the last number of the built in modes
#
# ############################################################################
#  TODO: the speed of the animation: 0xBB, ??, ??, 0x44
# ############################################################################

package main;
use strict;
use warnings;

use IO::Socket;
# include this for the self-calling timer we use later on
use Time::HiRes qw(gettimeofday);

# for the color picker module
use Color;

use SetExtensions;

# ----------------------------------------------------------------------------
#  Initialisation routine called upon start-up of FHEM
# ----------------------------------------------------------------------------
sub WIFILED_Initialize( $ ) {
  my ($hash) = @_;

  # the commands we provide to FHEM
  # installs the respecitive call-backs for FHEM. The call back in quotes 
  # must be realised as a sub later on in the file
  $hash->{DefFn}      = "WIFILED_Define";
  $hash->{SetFn}      = "WIFILED_Set";
  $hash->{GetFn}      = "WIFILED_Get";

  # the attributes we have. Space separated list of attribute values in 
  # the form name:default1,default2
  $hash->{AttrList}  = "timeout loglevel:0,1,2,3,4,5,6 " . $readingFnAttributes;

  # initialize the color picker
  FHEM_colorpickerInit();

}


# ----------------------------------------------------------------------------
#  Definition of a module instance
#  called when defining an element via fhem.cfg
# ----------------------------------------------------------------------------
sub WIFILED_Define( $$ ) {
    my ( $hash, $def ) = @_;
    
    my $name = $hash->{NAME};
    
    my @a = split("[ \t][ \t]*", $def);
    
    # do we have the right number of arguments?
    if( @a != 3 ) {
	Log( $attr{$name}{loglevel}, "WIFILED_Define: falsche Anzahl an Argumenten" );
	return( "wrong syntax: define <name> WIFILED <serverip> " );
    }
    
    # preset the internals
    $hash->{IP} = $a[ 2 ];

    $hash->{RED}   = 255;
    $hash->{GREEN} = 255;
    $hash->{BLUE}  = 255;
    $hash->{MODE}   = 0;

    if( !defined( $attr{$name}{timeout} ) ) {
	$attr{$name}{timeout} = 2;
    }

    if( !defined( $attr{$name}{loglevel} ) ) {
	$attr{$name}{loglevel} = 4;
    }

    # Preset our readings if undefined
    my $tn = TimeNow();

    if( !defined( $hash->{READINGS}{state}{VAL} ) ) {
	$hash->{READINGS}{state}{VAL} = "?"; 
	$hash->{READINGS}{state}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{rgb}{VAL} ) ) {
	$hash->{READINGS}{rgb}{VAL} = "FFFFFF"; 
	$hash->{READINGS}{rgb}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{RGB}{VAL} ) ) {
	$hash->{READINGS}{RGB}{VAL} = "FFFFFF"; 
	$hash->{READINGS}{RGB}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{dim}{VAL} ) ) {
	$hash->{READINGS}{dim}{VAL} = 100; 
	$hash->{READINGS}{dim}{TIME} = $tn; 
    }

    return( undef );
}


# ----------------------------------------------------------------------------
#  Set of a module
#  called upon set <name> cmd, arg1, arg2, ....
# ----------------------------------------------------------------------------
sub WIFILED_Set( $@ ) {
  my ( $hash, $name, $cmd, @arg ) = @_;

  # check if we have received a command
  if( !defined( $cmd ) ) { 
      return( "$name: set needs at least one parameter" );
  }

  my $cmdList = "" . 
	  "on off next:noArg prev:noArg mode " . 
	  "color brightness:slider,0,1,100 dim:slider,0,1,100 " . 
	  "rgb:colorpicker,RGB ";
	  
  # now parse the commands
  if( $cmd eq "?" ) {
      # this one should give us a drop down list
      return SetExtensions( $hash, $cmdList, $name, $cmd, @arg );
  } elsif( $cmd eq "on" ) {
      WIFILED_Write( $hash, "\x{CC}\x{23}\x{33}" );
      # and update the state
      readingsSingleUpdate( $hash, 
			    "state", 
			    "on", 
			    1 );
      Log( GetLogLevel( $name, 4 ), "$name switched on" );
  } elsif( $cmd eq "off" ) {
      WIFILED_Write( $hash, "\x{CC}\x{24}\x{33}" );
      # and update the state
      readingsSingleUpdate( $hash, 
			    "state", 
			    "off", 
			    1 );
      Log( GetLogLevel( $name, 4 ), "$name switched off" );
  } elsif( $cmd eq "run" ) {
      WIFILED_Write( $hash, "\x{CC}\x{21}\x{33}" );
  } elsif( $cmd eq "stop" ) {
      WIFILED_Write( $hash, "\x{CC}\x{22}\x{33}" );
  } elsif( $cmd eq "next" ) {
      my $offset = 38;
      my $mode = $offset + $hash->{MODE};
      if( $mode > ( $offset + 20 ) ) {
	  $mode = $offset;
      }
      $hash->{MODE} = $mode;
      WIFILED_Write( $hash, "\x{BB}" . chr( $mode ) . "\x{19}\x{44}" );
  } elsif( $cmd eq "prev" ) {
      my $offset = 38;
      my $mode = $offset + $hash->{MODE};
      if( $mode < $offset ) {
	  $mode = $offset + 20;
      }
      $hash->{MODE} = $mode;
      WIFILED_Write( $hash, "\x{BB}" . chr( $mode ) . "\x{19}\x{44}" );
  } elsif( $cmd eq "mode" ) {
      my $offset = 38;
      if( ( $arg[ 0 ] < 0 ) || ( $arg[ 0 ] > 19 ) ) {
	  my $msg = "WIFILED_Set: wrong mode number given";
	  Log( $attr{$name}{loglevel}, $msg );
	  return( $msg );
      }	  
      $hash->{MODE} = $arg[ 0 ] + $offset;
      WIFILED_Write( $hash, "\x{BB}" . chr( $hash->{MODE} ) . "\x{19}\x{44}" );
  } elsif( $cmd eq "color" ) {
      if( @arg != 3 ) {
	  my $msg = "WIFILED_Set: wrong number of arguments for set color";
	  Log( $attr{$name}{loglevel}, $msg );
	  return( $msg );
      } else {
	  $hash->{RED}   = $arg[ 0 ];
	  $hash->{GREEN} = $arg[ 1 ];
	  $hash->{BLUE}  = $arg[ 2 ];
	  WIFILED_Write( $hash, "\x{56}" . 
			 chr( $arg[ 0 ] ) . 
			 chr( $arg[ 1 ] ) . 
			 chr( $arg[ 2 ] ) . 
			 "\x{AA}" );
	  WIFILED_UpdateRGB( $hash );
	  Log( GetLogLevel( $name, 4 ), "$name set to " . 
	       "$hash->{RED} $hash->{GREEN} $hash->{BLUE}" );

      }
  } elsif( $cmd eq "rgb" ) {
      if( @arg != 1 ) {
	  my $msg = "WIFILED_Set: wrong number of arguments for set rgb";
	  Log( $attr{$name}{loglevel}, $msg );
	  return( $msg );
      } else {
	  $arg[ 0 ] = uc( $arg[ 0 ] );
	  my @colors = ( $arg[ 0 ] =~ m/..?/g );

	  if( @colors != 3 ) {
	      my $msg = "WIFILED_Set: malformed RBG given.";
	      Log( $attr{$name}{loglevel}, $msg );
	      return( $msg );
	  } else {
	      $hash->{RED}   = hex( $colors[ 0 ] );
	      $hash->{GREEN} = hex( $colors[ 1 ] );
	      $hash->{BLUE}  = hex( $colors[ 2 ] );
	      WIFILED_Write( $hash, "\x{56}" . 
			     chr( $hash->{RED} ) . 
			     chr( $hash->{GREEN} ) . 
			     chr( $hash->{BLUE} ) . 
			     "\x{AA}" );
	      WIFILED_UpdateRGB( $hash );
	      Log( GetLogLevel( $name, 4 ), "$name set to " . 
		   "$hash->{RED} $hash->{GREEN} $hash->{BLUE}" );
	  }
      }
  } elsif( ( $cmd eq "brightness" ) || ( $cmd eq "dim" ) ) {
      if( @arg != 1 ) {
	  my $msg = "WIFILED_Set: wrong number of arguments for set brightness";
	  Log( $attr{$name}{loglevel}, $msg );
	  return( $msg );
      } else {
	  # brightness is in percent (0..100)
	  my $bright = $arg[ 0 ];
	  my $red    = $hash->{RED};
	  my $green  = $hash->{GREEN};
	  my $blue   = $hash->{BLUE};

	  if( ( $bright > 100 ) || ( $bright < 0 ) ) {
	      $bright = 50;
	  }

	  # we need to determine what is 100%
	  my $upscale = 0;

	  # what is the smallest upscale factor?
	  if( $red > $green ) {
	      if( $red > $blue ) {
		  $upscale = 255 / $red;
	      } else {
		  $upscale = 255 / $blue;
	      }
	  } else {
	      if( $green > $blue ) {
		  $upscale = 255 / $green;
	      } else {
		  $upscale = 255 / $blue;
	      }
	  }
	  
	  $red   = int( ( ( $red * $upscale ) * $bright ) / 100 );
	  $blue  = int( ( ( $blue * $upscale ) * $bright ) / 100 );
	  $green = int( ( ( $green * $upscale ) * $bright ) / 100 );
	  WIFILED_Write( $hash, "\x{56}" . chr( $red ) . chr( $green ) . 
			 chr( $blue ) . "\x{AA}\n" );
	  $hash->{RED}   = $red;
	  $hash->{GREEN} = $green;
	  $hash->{BLUE}  = $blue;
	  WIFILED_UpdateRGB( $hash );
	  readingsSingleUpdate( $hash, "dim", $bright, 1 );
      }
  } else {
#      my $msg = "WIFILED_Set: unsupported command given $cmd @arg";
#      Log( $attr{$name}{loglevel}, $msg );
#      return( $msg );
      return SetExtensions ($hash, $cmdList, $name, $cmd, @arg);
  }

  return( undef );
}

# ----------------------------------------------------------------------------
#  Get of a module
#  called upon get <name> arg1
# ----------------------------------------------------------------------------
sub WIFILED_Get( $@ ) {
  my ($hash, @a) = @_;

  my $name = $a[ 0 ];

  if( int( @a ) != 2 ) {
      my $msg = "WIFILED_Get: wrong number of arguments";
      Log( $attr{$name}{loglevel}, $msg );
      return( $msg );
  }

  if( ( $a[ 1 ] eq "rgb" ) || ( $a[ 1 ] eq "RGB" ) ) {
      return( ReadingsVal( "$name", "rgb", "F0F0F0" ) );
  } elsif( ( $a[ 1 ] eq "dim" ) || ( $a[ 1 ] eq "DIM" ) ) {
      return( ReadingsVal( "$name", "dim", "50" ) );
  } else {
      my $msg = "WIFILED_Get: unkown argument";
      Log( $attr{$name}{loglevel}, $msg );
      return( $msg );
  } 
      
}


# ----------------------------------------------------------------------------
#  write something to the WIFI LED
# ----------------------------------------------------------------------------
sub WIFILED_Write( $$ ) {
    my ( $hash, $out ) = @_;
    my $name = $hash->{NAME};

    my $s = new IO::Socket::INET( PeerAddr => $hash->{IP},
				  PeerPort => 5577,
				  Proto => 'tcp',
				  Timeout => int( $attr{$name}{timeout} ) );

    if( defined $s ) {
	my $res = "";
	
	$s->autoflush( 1 );
	
	print $s $out;
	
	close( $s );
    }
}


# ----------------------------------------------------------------------------
#  Update the RGB Readings for the color picker
# ----------------------------------------------------------------------------
sub WIFILED_UpdateRGB( $ ) {
    my ( $hash, @rest )  = @_;
    my $name = $hash->{NAME};

    my $buf = sprintf( "%02X%02X%02X", 
		       $hash->{RED}, 
		       $hash->{GREEN}, 
		       $hash->{BLUE} );

    readingsSingleUpdate( $hash, 
			  "RGB", 
			  $buf, 
			  1 );

    readingsSingleUpdate( $hash, 
			  "rgb", 
			  $buf, 
			  1 );
    CommandTrigger( "", "$hash->{NAME} RGB: $buf" );

    return;
}



# DO NOT WRITE BEYOND THIS LINE
1;

=pod
=begin html

<a name="WIFILED"></a>
<h3>WIFILED</h3>
<ul>
    Define a WIFI LED Controler.
  <br><br>

  <a name="WIFILEDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; WIFILED &lt;ip&gt;</code>
    <br><br>

    Example:
    define myled WIFILED 192.168.38.17
    <ul>
    </ul>
  </ul>
  <br>

  <a name="WIFILEDset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set any value.
  </ul>
  <br>

  <a name="WIFILEDget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="WIFILEDattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="setList">setList</a><br>
        Space separated list of commands, which will be returned upon "set name ?",
        so the FHEMWEB frontend can construct a dropdown and offer on/off
        switches. Example: attr WIFILEDName setList on off
        </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>

</ul>

=end html
=cut

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
#  dim              0-100
#  hsv              the rgb in hsv-spectrum
#  mode             1-21
#  rgb              color in rgb
#  speed            0-255
#
# ############################################################################
#
#  we have the following attributes
#  timeout          the timeout in seconds for the TCP connection
#  updateInterval	the interval for automatic Statusupdate
#
# ############################################################################
#  we have the following internals (all UPPERCASE)
#  RED (helper)     last red value 
#  GREEN (helper)   last green value
#  BLUE (helper)    last blue value
#  IP               the IP of the device
#
# ############################################################################
#  TODO:
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

#global Variable
my $offset = 36;

sub LW12_UpdateRGB($);
sub LW12_updateStatus($);

# ----------------------------------------------------------------------------
#  Initialisation routine called upon start-up of FHEM
# ----------------------------------------------------------------------------
sub LW12_Initialize( $ ) {
  my ($hash) = @_;

  # the commands we provide to FHEM
  # installs the respecitive call-backs for FHEM. The call back in quotes 
  # must be realised as a sub later on in the file
  $hash->{DefFn}      = "LW12_Define";
  $hash->{UndefFn}    = "LW12_Undefine";
  $hash->{SetFn}      = "LW12_Set";
  $hash->{GetFn}      = "LW12_Get";

  # the attributes we have. Space separated list of attribute values in 
  # the form name:default1,default2
  $hash->{AttrList}  = "timeout updateInterval verbose:0,1,2,3,4,5 " . $readingFnAttributes;

  # initialize the color picker
  FHEM_colorpickerInit();

}


# ----------------------------------------------------------------------------
#  Definition of a module instance
#  called when defining an element via fhem.cfg
# ----------------------------------------------------------------------------
sub LW12_Define( $$ ) {
    my ( $hash, $def ) = @_;
    
    my $name = $hash->{NAME};
    
    my @a = split("[ \t][ \t]*", $def);
    
    # do we have the right number of arguments?
    if( @a != 3 ) {
	Log3 $name, 3, "LW12_Define: falsche Anzahl an Argumenten";
	return( "wrong syntax: define <name> LW12 <serverip> " );
    }
    
    # preset the internals
    $hash->{IP} = $a[ 2 ];

    $hash->{".dim"}   = {
        bri => 100,
        channels => [(255) x 3],
    };

 	$attr{$name}{timeout} = 2;
 	$attr{$name}{updateInterval} = 60;
 	$attr{$name}{verbose} = 3;

	LW12_updateStatus($hash);

	return undef;
}

# ----------------------------------------------------------------------------
#  Undefinition of a module instance
#  called when undefining an element via fhem.cfg
# ----------------------------------------------------------------------------
sub LW12_Undefine($$)
{
  my ($hash,$arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

# ----------------------------------------------------------------------------
#  Set of a module
#  called upon set <name> cmd, arg1, arg2, ....
# ----------------------------------------------------------------------------
sub LW12_Set( $@ ) {
  my ( $hash, $name, $cmd, @arg ) = @_;

  # check if we have received a command
  if( !defined( $cmd ) ) { 
      return( "$name: set needs at least one parameter" );
  }
 
#  if(!$hash->{LOCAL}) {
#      RemoveInternalTimer($hash);
#  }
 
  my $cmdList = "" . 
	  "on off next:noArg prev:noArg animation mode speed run:noArg stop:noArg " . 
	  "color dim:slider,0,1,100 " . 
	  "rgb:colorpicker,rgb hsv";
	  
  # now parse the commands
  if( $cmd eq "?" ) {
      # this one should give us a drop down list
      return SetExtensions( $hash, $cmdList, $name, $cmd, @arg );
  } elsif( $cmd eq "on" ) {
      LW12_Write( $hash, "\x{CC}\x{23}\x{33}" );
      readingsSingleUpdate( $hash, "state", "on", 1 );
      Log3 $name, 4, "$name switched on" ;
  } elsif( $cmd eq "off" ) {
      LW12_Write( $hash, "\x{CC}\x{24}\x{33}" );
      readingsSingleUpdate( $hash, "state", "off", 1 );
      Log3 $name, 4, "$name switched off";
  } elsif( $cmd eq "run" ) {
      LW12_Write( $hash, "\x{CC}\x{21}\x{33}" );
  } elsif( $cmd eq "stop" ) {
      LW12_Write( $hash, "\x{CC}\x{22}\x{33}" );
  } elsif( $cmd eq "next" ) {
      my $mode = $hash->{READINGS}{mode}{VAL};
      if( $mode == 20 ) { $mode = 1; }
	  else { $mode = $mode + 1; }     
      LW12_Write( $hash, "\x{BB}" . chr( $mode + $offset ) . "\x{AA}\x{44}" );
	  readingsSingleUpdate( $hash, "mode", $mode, 1 );
  } elsif( $cmd eq "prev" ) {
      my $mode = $hash->{READINGS}{mode}{VAL};
      if( $mode == 1 ) { $mode = 20; }
	  else { $mode = $mode - 1; } 
      LW12_Write( $hash, "\x{BB}" . chr( $mode + $offset ) . "\x{AA}\x{44}" );
	  readingsSingleUpdate( $hash, "mode", $mode, 1 );
  } elsif( $cmd eq "mode" ){
      if( @arg > 2 || @arg < 1 ) {
		  my $msg = "LW12_Set: wrong number of arguments for set mode";
		  Log3 $name, 3, $msg ;
		  return( $msg );
      } else {
		  if( ( $arg[ 0 ] < 1 ) || ( $arg[ 0 ] > 21 ) ) {
			  my $msg = "LW12_Set: wrong mode number given";
			  Log3 $name, 3, $msg ;
			  return( $msg );
		  }	  
		  readingsSingleUpdate( $hash, "mode", $arg[ 0 ], 1 );
		  
		  if( @arg == 2 ) {
			  if( ( $arg[ 1 ] < 0 ) || ( $arg[ 1 ] > 255 ) ) {
				  my $msg = "LW12_Set: wrong speed value given";
				  Log3 $name, 3, $msg ;
				  return( $msg );
			  }	  		  
		  
			  LW12_Write( $hash, "\x{BB}" . chr( $arg[ 0 ] + $offset ) . chr ( 255 - $arg[ 1 ] ) . "\x{44}" );
			  readingsSingleUpdate( $hash, "mode", $arg[ 0 ], 1 );
			  readingsSingleUpdate( $hash, "speed", $arg[ 1 ], 1 );
		  } else { 
		      LW12_Write( $hash, "\x{BB}" . chr( $arg[ 0 ] + $offset ) . chr ( 255 - $hash->{READINGS}{speed}{VAL} ) . "\x{44}" );
			  readingsSingleUpdate( $hash, "mode", $arg[ 0 ], 1 );
		  }		  
      }
  } elsif( $cmd eq "speed" ){
      if( @arg != 1 ) {
		  my $msg = "LW12_Set: wrong number of arguments for set speed";
		  Log3 $name, 3, $msg ;
		  return( $msg );
      } else {		  
		  if( ( $arg[ 1 ] < 0 ) || ( $arg[ 1 ] > 255 ) ) {
			  my $msg = "LW12_Set: wrong speed value given";
			  Log3 $name, 3, $msg ;
			  return( $msg );
		  }	  		  
		  LW12_Write( $hash, "\x{BB}" . chr( $hash->{READINGS}{mode}{VAL} + $offset ) . chr ( 255 - $arg[ 0 ] ) . "\x{44}" );
		  readingsSingleUpdate( $hash, "speed", $arg[ 0 ], 1 );
      }	  
  } elsif( $cmd eq "animation" ){
      if( @arg < 3 ) {
		  my $msg = "LW12_Set: wrong number of arguments for set animation";
		  Log3 $name, 3, $msg ;
		  return( $msg );
      } else {		  
		  if( ( $arg[ (@arg - 1) ] < 0 ) || ( $arg[ (@arg - 1) ] > 2 ) ) {
			  my $msg = "LW12_Set: wrong mode value given";
			  Log3 $name, 3, $msg ;
			  return( $msg );
		  }	 
		  if( ( $arg[ (@arg - 2) ] < 0 ) || ( $arg[ (@arg - 2) ] > 255 ) ) {
			  my $msg = "LW12_Set: wrong speed value given";
			  Log3 $name, 3, $msg ;
			  return( $msg );
		  }	 	
      
	      my $it = 0;
		  my @red;
		  my @green;
		  my @blue;
		  my $colorstring = "";
		  for ( $it = 0; $it < 16; $it++){
			  $red  [ $it ] = hex( 0x01 );
			  $green[ $it ] = hex( 0x02 );
			  $blue [ $it ] = hex( 0x03 );
		  }
		  for( $it = 0; $it < @arg - 2; $it++){
		      $arg[ $it ] = uc( $arg[ $it ] );
		      my @colors = ( $arg[ $it ] =~ m/..?/g );

			  if( @colors != 3 ) {
				  my $msg = "LW12_Set: malformed RBG [ $it ] given: $colors[ 0 ] $colors[ 1 ] $colors[ 2 ]";
				  Log3 $name, 3,  $msg ;
				  return( $msg );
			  } else {
				  $red  [ $it ] = hex( $colors[ 0 ] );
				  $green[ $it ] = hex( $colors[ 1 ] );
				  $blue [ $it ] = hex( $colors[ 2 ] );
			  }
		  }
		  for( $it = 0; $it < 16; $it++){
		   $colorstring = $colorstring . chr( $red[ $it ] ) . chr( $green[ $it ] ) . chr( $blue[ $it ] );
		  }
		  
		  my $mode = 0;
		  if($arg[ (@arg - 1) ] == 0){ $mode = hex("3A");
		  }elsif($arg[ (@arg - 1) ] == 1){ $mode = hex("3B");
		  }elsif($arg[ (@arg - 1) ] == 2){ $mode = hex("3C");}
		  
		  
		  Log3 $name, 4, "Sending string: 99 " . sprintf ("%*v2.2X\n", ' ', $colorstring) . " " . ( 255 - $arg[ (@arg - 2) ] ) . " " . sprintf ("%*v2.2X\n", ' ', $mode ) . " FF" . " 66";
		  LW12_Write( $hash, "\x{99}" . $colorstring . chr ( 255 - $arg[ (@arg - 2) ] ) . chr ( $mode ) . "\x{FF}" . "\x{66}" );
      }		  
  } elsif( $cmd eq "color" ) {
      if( @arg != 3 ) {
		  my $msg = "LW12_Set: wrong number of arguments for set color";
		  Log3 $name, 3, $msg ;
		  return( $msg );
		  } else {
          @{$hash->{".bri"}->{channels}} = @arg;
		  LW12_Write( $hash, "\x{56}" . 
				 chr( $arg[ 0 ] ) . 
				 chr( $arg[ 1 ] ) . 
				 chr( $arg[ 2 ] ) . 
				 "\x{AA}" );
          Log3 $name, 4, "$name set to @{$hash->{'.bri'}->{channels}}";
	  }
  } elsif( $cmd eq "hsv" ) {
      if( ( @arg != 3 ) || ( $arg[ 0 ] > 360 ) || ( $arg[ 1 ] > 100 )|| ( $arg[ 2 ] > 100 ) ) {
		  if( @arg != 3 ){
			  my $msg = "LW12_Set: wrong number of arguments for set hsv";
			  Log3 $name, 3, $msg ;
			  return( $msg );
		  }else {
			  my $msg = "LW12_Set: wrong values for set hsv. use h:[0-360]; s:[0-100]; v:[0-100]";
			  Log3 $name, 3, $msg ;
			  return( $msg );
		  }
	  } else {
		  my @rgb = Color::hsv2rgb(( $arg[ 0 ]/360 ), ( $arg[ 1 ]/100 ), ( $arg[ 2 ] / 100 ));
		  foreach (@rgb){
		      $_ = $_ * 255;
		  }
		  @{$hash->{".bri"}->{channels}} = @rgb;
		  
		  LW12_Write( $hash, "\x{56}" . 
				 chr( @{$hash->{".bri"}->{channels}}[0] ) .
				 chr( @{$hash->{".bri"}->{channels}}[1] ) .
				 chr( @{$hash->{".bri"}->{channels}}[2] ) .
				 "\x{AA}" );
          Log3 $name, 4, "$name set to @{$hash->{'.bri'}->{channels}}";
	  }
  } elsif( $cmd eq "rgb" ) {
      if( @arg != 1 ) {
		  my $msg = "LW12_Set: wrong number of arguments for set rgb";
		  Log3 $name, 3, $msg ;
		  return( $msg );
      } else {
		  $arg[ 0 ] = uc( $arg[ 0 ] );
		  my @channels = ( $arg[ 0 ] =~ m/..?/g );
		  foreach (@channels){
		      $_ = hex( $_ );
		  }

          if( @channels != 3 ) {
			  my $msg = "LW12_Set: malformed RBG given.";
			  Log3 $name, 3,  $msg ;
			  return( $msg );
		  } else {
              @{$hash->{".bri"}->{channels}} = @channels;

			  LW12_Write( $hash, "\x{56}" . 
					 chr( @{$hash->{".bri"}->{channels}}[0] ) .
					 chr( @{$hash->{".bri"}->{channels}}[1] ) .
					 chr( @{$hash->{".bri"}->{channels}}[2] ) .
					 "\x{AA}" );
			  Log3 $name, 4, "$name set to @{$hash->{'.bri'}->{channels}}";
		  }
      }
  } elsif( $cmd eq "dim" ) {
      if( @arg != 1 ) {
		  my $msg = "LW12_Set: wrong number of arguments for set brightness";
		  Log3 $name, 3, $msg ;
		  return( $msg );
      } else {
	
        $hash->{".dim"}->{bri} = $arg[0];
        @{$hash->{".bri"}->{channels}} = Color::BrightnessToChannels($hash->{".dim"});
		  LW12_Write( $hash, "\x{56}" .
   		 chr( @{$hash->{".bri"}->{channels}}[0] ) .
   		 chr( @{$hash->{".bri"}->{channels}}[1] ) .
   		 chr( @{$hash->{".bri"}->{channels}}[2] ) .
   		 "\x{AA}" );
       Log3 $name, 4, "$name set to @{$hash->{'.bri'}->{channels}}";
    }
  } else {
      return SetExtensions ($hash, $cmdList, $name, $cmd, @arg);
  }
  LW12_UpdateRGB( $hash );
#  if(!$hash->{LOCAL}) {
#	  if ( ($attr{$name}{updateInterval}) != 0){
#		 InternalTimer(gettimeofday()+ $attr{$name}{updateInterval} , "LW12_updateStatus", $hash, 0);
#     }
#  }
  return( undef );
}

# ----------------------------------------------------------------------------
#  Get of a module
#  called upon get <name> arg1
# ----------------------------------------------------------------------------
sub LW12_Get( $@ ) {
  my ( $hash, $name, $cmd, @arg ) = @_;
  my $cmdList = "updateStatus:noArg"; 
  
  # check if we have received a command
  if( !defined( $cmd ) ) { 
      return( "$name: set needs at least one parameter" );
  }

  if( $cmd eq "updateStatus" ) {
      LW12_updateStatus( $hash );
      Log3 $name, 4, "$name updateStatus requested" ;    
  } else {
      return "Unknown argument $cmd, choose one of $cmdList";
  }  
}


# ----------------------------------------------------------------------------
#  write something to the WIFI LED
# ----------------------------------------------------------------------------
sub LW12_Write( $$ ) {
    my ( $hash, $out ) = @_;
    my $name = $hash->{NAME};
	
    my $s = new IO::Socket::INET( PeerAddr => $hash->{IP},
				  PeerPort => 5577,
				  Proto => 'tcp',
				  Timeout => int( $attr{$name}{timeout} ) );

    if( defined $s ) {
		my $res = "";

		$s->autoflush( 1 );
		$s->send($out);	
		
		if ($out eq "\x{EF}\x{01}\x{77}"){
			$s->recv($res,11);
			my $res = unpack "H*", $res;
			return $res;
		}
		$s->close();
    }
	else {
		Log3 $name, 3, "Can't connect to socket!";
	}
}


# ----------------------------------------------------------------------------
#  Update the RGB Readings for the color picker
# ----------------------------------------------------------------------------
sub LW12_UpdateRGB( $ ) {
    my ( $hash, @rest )  = @_;
    my $name = $hash->{NAME};
	my @channels = @{$hash->{".bri"}->{channels}};
	
    my @hsv = Color::rgb2hsv( $channels[0] / 255.0, $channels[1] / 255.0, $channels[2] / 255.0 ); 
    my $hsv_reading = "". sprintf('%d', $hsv[ 0 ] * 360 ) . " " . sprintf('%d', $hsv[ 1 ] * 100 ) . " " . sprintf('%d', $hsv[ 2 ] * 100 );
	
    $hash->{".dim"} = Color::ChannelsToBrightness(@channels);	
		   
	readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "rgb", Color::ChannelsToRgb(@channels) );
        readingsBulkUpdate( $hash, "hsv", $hsv_reading );	
        readingsBulkUpdate( $hash, "dim", $hash->{".dim"}->{bri} );
    readingsEndUpdate( $hash,1 );		   
			   
    return;
}

# ----------------------------------------------------------------------------
#  Request and update the Readings from the LW12
# ----------------------------------------------------------------------------
sub LW12_updateStatus( $ ) {
    my ( $hash, @rest )  = @_;
    my $name = $hash->{NAME};
	
	if(!$hash->{LOCAL}) {
	   RemoveInternalTimer($hash);
	   if ( ($attr{$name}{updateInterval}) != 0){
		InternalTimer(gettimeofday()+ $attr{$name}{updateInterval} , "LW12_updateStatus", $hash, 0);
	   }
	}	
	
	my $res = LW12_Write( $hash, "\x{EF}\x{01}\x{77}" );	
	$res = uc($res);
	my @colors = ( $res =~ m/..?/g );

    readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "mode", hex( $colors[ 3 ] ) - $offset );	
        readingsBulkUpdate( $hash, "speed", 255 - hex(  $colors[ 5 ] ) );
		if($colors[2] eq "23"){
			readingsBulkUpdate( $hash, "state", "on");
		}else{ 
			readingsBulkUpdate( $hash, "state", "off",);
		}		
    readingsEndUpdate( $hash,1 );
	  
	@{$hash->{".bri"}->{channels}}[0] = hex( $colors[ 6 ] );
	@{$hash->{".bri"}->{channels}}[1] = hex( $colors[ 7 ] );
	@{$hash->{".bri"}->{channels}}[2] = hex( $colors[ 8 ] );
	  
	LW12_UpdateRGB( $hash );
}



# DO NOT WRITE BEYOND THIS LINE
1;

=pod
=begin html




=end html
=cut

=pod
=begin html

<a name="LW12"></a>
<h3>LW12</h3>
<ul>
    Define a WIFI LED Controler.
  <br><br>

  <a name="LW12define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LW12 &lt;ip&gt;</code>
    <br><br>

    Example:
    define myled LW12 192.168.38.17
    <ul>
    </ul>
  </ul>
  <br>

  <a name="LW12_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>dim<br>
    the brightness of the device. The value can be betwen 1 and 100</li>
    <li>RGB/rgb<br>
    the current color in format rrggbb</li>
    <li>speed<br>
    the current animation speed</li>
    <li>speed<br>
    the current state (on|off)</li>
  </ul><br>

  
  
  <a name="LW12_Set"></a>
    <b>Set</b>
    <ul>
      <li>on </li>
      <li>off </li>
      <li>toggle </li>
      <li>color &lt;red&gt; &lt;green&gt; &lt;blue&gt;<br>
        set color to the given decimal-number per channel. range is 0-255</li>
      <li>dim &lt;value&gt;<br>
        set brighness to &lt;value&gt;; range is 0-100.</li>
      <li>mode &lt;mode&gt; [&lt;speed&gt;]  <br>
        set controller animation mode to &lt;mode&gt; with &lt;speed&gt;; mode-range is 0-19 speed-range is 0-255</li>
	  <li>animation &lt;rrggbb&gt; &lt;rrggbb&gt; &larr; up to 16 colors &lt;speed&gt; &lt;mode&gt; <br>
        set controller animation with the given colors and the given speed. <br>
		mode: <br>
		      0 = fade<br>
		      1 = jump<br>
              2 = strobe<br>			  
		mode-range is 0-2, speed-range is 0-255 <br></li>	
      <li>next<br>
        set next controller animation mode </li>
      <li>prev<br>
        set previous controller animation mode </li>
      <li>run<br>
        run controller animation </li>
      <li>stop<br>
        stop controller animation </li>
      <li>rgb &lt;rrggbb&gt;</li>
      <li><a href="#setExtensions"> set extensions</a> are supported.</li>
      <br>
    </ul><br>

  <a name="LW12get"></a>
  <b>Get</b>
    <ul>
      <li>updateStatus<br>
        Requests a status-update from the RGB-Controller. The next update is in &lt;updateInterval&gt seconds.</li>
      <br>
    </ul><br>


  <a name="LW12attr"></a>
  <b>Attributes</b>
    <ul>
      <li>updateInterval<br>
        The Interval of the Statusupdates in seconds. If &lt;updateInterval&gt = 0, the automatic updates are not active. Default is 60.</li>
      <li>Timeout<br>
        The Timeout of the connection to the RGB-controller in seconds. Default is 2.</li>
      <br>
    </ul><br>

=end html
=cut


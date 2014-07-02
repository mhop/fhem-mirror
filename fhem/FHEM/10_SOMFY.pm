######################################################
# $Id$
#
# SOMFY RTS / Simu Hz protocol module for FHEM
# (c) Thomas Dankert <post@thomyd.de>
#
# This will only work if you flashed your CUL with
# the newest culfw (support for "Y" command).
#
# Published under GNU GPL License, v2
######################################################

package main;

use strict;
use warnings;

my %codes = (
	"10" => "go-my",    # goto "my" position
	"11" => "stop", 	# stop the current movement
	"20" => "off",      # go "up"
	"40" => "on",       # go "down"
	"80" => "prog",     # enter programming mode
	"100" => "on-for-timer",
	"101" => "off-for-timer",
);

my %somfy_c2b;

my $somfy_defsymbolwidth = 1240;    # Default Somfy frame symbol width
my $somfy_defrepetition = 6;	# Default Somfy frame repeat counter

my %models = ( somfyblinds => 'blinds', ); # supported models (blinds only, as of now)

#############################
sub SOMFY_Initialize($) {
	my ($hash) = @_;

	# map commands from web interface to codes used in Somfy RTS
	foreach my $k ( keys %codes ) {
		$somfy_c2b{ $codes{$k} } = $k;
	}

	#                         YsKKC0RRRRAAAAAA
	#  $hash->{Match}     = "^YsA..0..........\$";
	$hash->{SetFn}   = "SOMFY_Set";
	$hash->{StateFn} = "SOMFY_SetState";
	$hash->{DefFn}   = "SOMFY_Define";
	$hash->{UndefFn} = "SOMFY_Undef";

	#  $hash->{ParseFn}   = "SOMFY_Parse";
	$hash->{AttrList} = "IODev"
	  . " symbol-length"
	  . " enc-key"
	  . " rolling-code"
	  . " repetition"
	  . " switch_rfmode:1,0"
	  . " do_not_notify:1,0"
	  . " ignore:0,1"
	  . " dummy:1,0"
	  . " model:somfyblinds"
	  . " loglevel:0,1,2,3,4,5,6";

}

#############################
sub SOMFY_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my $u = "wrong syntax: define <name> SOMFY address "
	  . "[encryption-key] [rolling-code]";

	# fail early and display syntax help
	if ( int(@a) < 3 ) {
		return $u;
	}

	# check address format (6 hex digits)
	if ( ( $a[2] !~ m/^[a-fA-F0-9]{6}$/i ) ) {
		return "Define $a[0]: wrong address format: specify a 6 digit hex value "
	}

	my $address = $a[2];
	$hash->{ADDRESS} = uc($address);

	# check optional arguments for device definition
	if ( int(@a) > 3 ) {

		# check encryption key (2 hex digits, first must be "A")
		if ( ( $a[3] !~ m/^[aA][a-fA-F0-9]{1}$/i ) ) {
			return "Define $a[0]: wrong encryption key format:"
			  . "specify a 2 digits hex value (first nibble = A) "
		}

		# store it as attribute, so it is saved in the statefile
		$attr{ $a[0] }{"enc-key"} = lc( $a[3] );

		if ( int(@a) == 5 ) {
			# check rolling code (4 hex digits)
			if ( ( $a[4] !~ m/^[a-fA-F0-9]{4}$/i ) ) {
				return "Define $a[0]: wrong rolling code format:"
			 	 . "specify a 4 digits hex value "
			}

			# store it
			$attr{ $a[0] }{"rolling-code"} = lc( $a[4] );
		}
	}
	else {
		# no values for encryption and rolling code provided, use initial defaults
		$attr{ $a[0] }{"enc-key"}      = "A0";
		$attr{ $a[0] }{"rolling-code"} = "0000";
	}

	# group devices by their address
	my $code  = uc($address);
	my $ncode = 1;
	my $name  = $a[0];

	$hash->{CODE}{ $ncode++ } = $code;
	$modules{SOMFY}{defptr}{$code}{$name} = $hash;

	AssignIoPort($hash);
}

#############################
sub SOMFY_Undef($$) {
	my ( $hash, $name ) = @_;

	foreach my $c ( keys %{ $hash->{CODE} } ) {
		$c = $hash->{CODE}{$c};

		# As after a rename the $name my be different from the $defptr{$c}{$n}
		# we look for the hash.
		foreach my $dname ( keys %{ $modules{SOMFY}{defptr}{$c} } ) {
			if ( $modules{SOMFY}{defptr}{$c}{$dname} == $hash ) {
				delete( $modules{SOMFY}{defptr}{$c}{$dname} );
			}
		}
	}
	return undef;
}

#####################################
sub SOMFY_SetState($$$$) {
	my ( $hash, $tim, $vt, $val ) = @_;

	if ( $val =~ m/^(.*) \d+$/ ) {
		$val = $1;
	}

	if ( !defined( $somfy_c2b{$val} ) ) {
		return "Undefined value $val";
	}

	return undef;
}

#####################################
sub SOMFY_Extension_Fn($)
{
  my (undef, $name, $cmd) = split(" ", shift, 3);
  return if(!defined($defs{$name}));

  if($cmd eq "on-for-timer") {
    DoSet($name, "stop"); # send the stop-command

  } elsif($cmd eq "off-for-timer") {
    DoSet($name, "stop");

  }
}

#############################
sub SOMFY_Do_For_Timer($@)
{
  	my ($hash, $name, $cmd, $param) = @_;

  	my $cmd1 = ($cmd =~ m/on.*/ ? "on" : "off");

	RemoveInternalTimer("SOMFY $name $cmd");
	return "$cmd requires a number as argument" if($param !~ m/^\d*\.?\d*$/);

	if($param) {
	  # send the on/off command first
	  DoSet($name, $cmd1);
	  # schedule the stop command for later
	  InternalTimer(gettimeofday()+$param,"SOMFY_Extension_Fn","SOMFY $name $cmd",0);
	}

	return
}

###################################
sub SOMFY_Set($@) {
	my ( $hash, $name, @args ) = @_;

	my $ret = undef;
	my $numberOfArgs  = int(@args);
	my $message;

	if ( $numberOfArgs < 1 ) {
		return "no set value specified" ;
	}

  return SOMFY_Do_For_Timer($hash, $name, @args) if($args[0] =~ m/[on|off]-for-timer$/);
  return "Bad time spec" if($numberOfArgs == 2 && $args[1] !~ m/^\d*\.?\d+$/);

    my $command = $somfy_c2b{ $args[0] };
	if ( !defined($command) ) {

		return "Unknown argument $args[0], choose one of "
		  . join( " ", sort keys %somfy_c2b );
	}

	my $io = $hash->{IODev};

	## Do we need to change RFMode to SlowRF?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"switch_rfmode"} ) )
	{
		if ( $attr{ $name }{"switch_rfmode"} eq "1" )
		{    # do we need to change RFMode of IODev
			my $ret =
			  CallFn( $io->{NAME}, "AttrFn", "set",
				( $io->{NAME}, "rfmode", "SlowRF" ) );
		}
	}

	## Do we need to change symbol length?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"symbol-length"} ) )
	{
		$message = "Yt" . $attr{ $name }{"symbol-length"};
		CUL_SimpleWrite( $io, $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set symbol-length: $message for $io->{NAME}";
	}


	## Do we need to change frame repetition?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"repetition"} ) )
	{
		$message = "Yr" . $attr{ $name }{"repetition"};
		CUL_SimpleWrite( $io, $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set repetition: $message for $io->{NAME}";
	}

	my $value = $name ." ". join(" ", @args);

	# message looks like this
	# Ys_key_ctrl_cks_rollcode_a0_a1_a2
	# Ys ad 20 0ae3 a2 98 42

	$message = "Ys"
	  . uc( $attr{ $name }{"enc-key"} )
	  . $command
	  . uc( $attr{ $name }{"rolling-code"} )
	  . uc( $hash->{ADDRESS} );

	## Log that we are going to switch Somfy
	Log GetLogLevel( $name, 2 ), "SOMFY set $value: $message";
	( undef, $value ) = split( " ", $value, 2 );    # Not interested in the name...

	## Send Message to IODev and wait for correct answer
	my $msg = CallFn( $io->{NAME}, "GetFn", $io, ( " ", "raw", $message ) );

	my $enckey = uc($attr{$name}{"enc-key"});
	if ( $msg =~ m/raw => Ys$enckey.*/ ) {
		Log 4, "Answer from $io->{NAME}: $msg";
	}
	else {
		Log 2, "SOMFY IODev device didn't answer Ys command correctly: $msg";
	}

	# increment encryption key and rolling code
	my $enc_key_increment      = hex( $attr{ $name }{"enc-key"} );
	my $rolling_code_increment = hex( $attr{ $name }{"rolling-code"} );

	$attr{ $name }{"enc-key"} =
	  sprintf( "%02X", ( ++$enc_key_increment & hex("0xAF") ) );
	$attr{ $name }{"rolling-code"} =
	  sprintf( "%04X", ( ++$rolling_code_increment ) );

	## Do we need to change symbol length back?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"symbol-length"} ) )
	{
		$message = "Yt" . $somfy_defsymbolwidth;
		CUL_SimpleWrite( $io, $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set symbol-length back: $message for $io->{NAME}";
	}

	## Do we need to change repetition back?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"repetition"} ) )
	{
		$message = "Yr" . $somfy_defrepetition;
		CUL_SimpleWrite( $io, $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set repetition back: $message for $io->{NAME}";
	}

	## Do we need to change RFMode back to HomeMatic??
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"switch_rfmode"} ) )
	{
		if ( $attr{ $name }{"switch_rfmode"} eq "1" )
		{    # do we need to change RFMode of IODev?
			my $ret =
			  CallFn( $io->{NAME}, "AttrFn", "set",
				( $io->{NAME}, "rfmode", "HomeMatic" ) );
		}
	}

	##########################
	# Look for all devices with the same address, and set state, timestamp
	my $code = "$hash->{ADDRESS}";
	my $tn   = TimeNow();
	foreach my $n ( keys %{ $modules{SOMFY}{defptr}{$code} } ) {

		my $lh = $modules{SOMFY}{defptr}{$code}{$n};
		$lh->{CHANGED}[0]            = $value;
		$lh->{STATE}                 = $value;
		$lh->{READINGS}{state}{TIME} = $tn;
		$lh->{READINGS}{state}{VAL}  = $value;
	}
	return $ret;
}

#############################
sub SOMFY_Parse($$) {

	# not implemented yet, since we only support SENDING of somfy commands
}

#############################
1;


=pod
=begin html

<a name="SOMFY"></a>
<h3>SOMFY - Somfy RTS / Simu Hz protocol</h3>
<ul>
  The Somfy RTS (identical to Simu Hz) protocol is used by a wide range of devices,
  which are either senders or receivers/actuators.
  As we right now are only able to SEND Somfy commands, but CAN'T receive them, this module currently only
  supports devices like blinds, dimmers, etc. through a <a href="#CUL">CUL</a> device, so this must be defined first.

  <br><br>

  <a name="SOMFYdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SOMFY &lt;address&gt; [&lt;encryption-key&gt;] [&lt;rolling-code&gt;] </code>
    <br><br>

   The address is a 6-digit hex code, that uniquely identifies a single remote control channel.
   It is used to pair the remote to the blind or dimmer it should control.
   <br>
   Pairing is done by setting the blind in programming mode, either by disconnecting/reconnecting the power,
   or by pressing the program button on an already associated remote.
   <br>
   Once the blind is in programming mode, send the "prog" command from within FHEM to complete the pairing.
   The blind will move up and down shortly to indicate completion.
   <br>
   You are now able to control this blind from FHEM, the receiver thinks it is just another remote control.

   <ul>
   <li><code>&lt;address&gt;</code> is a 6 digit hex number that uniquely identifies FHEM as a new remote control channel.
   <br>You should use a different one for each device definition, and group them using a structure.
   </li>
   <li>The optional <code>&lt;encryption-key&gt;</code> is a 2 digit hex number (first letter should always be A)
   that can be set to clone an existing remote control channel.</li>
   <li>The optional <code>&lt;rolling-code&gt;</code> is a 4 digit hex number that can be set
   to clone an existing remote control channel.<br>
   If you set one of them, you need to pick the same address as an existing remote.
   Be aware that the receiver might not accept commands from the remote any longer,<br>
   if you used FHEM to clone an existing remote.
   <br>
   This is because the code is original remote's codes are out of sync.</li>
   </ul>
   <br>

    Examples:
    <ul>
      <code>define rollo_1 SOMFY 000001</code><br>
      <code>define rollo_2 SOMFY 000002</code><br>
      <code>define rollo_3_original SOMFY 42ABCD A5 0A1C</code><br>
    </ul>
  </ul>
  <br>

  <a name="SOMFYset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    go-my
    stop
    prog  # Special, see note
    on-for-timer
    off-for-timer
</pre>
    Examples:
    <ul>
      <code>set rollo_1 on</code><br>
      <code>set rollo_1,rollo_2,rollo_3 on</code><br>
      <code>set rollo_1-rollo_3 on</code><br>
      <code>set rollo_1 off</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>prog is a special command used to pair the receiver to FHEM:
      Set the receiver in programming mode (eg. by pressing the program-button on the original remote)
      and send the "prog" command from FHEM to finish pairing.<br>
      The blind will move up and down shortly to indicate success.
      </li>
      <li>on-for-timer and off-for-timer send a stop command after the specified time,
      instead of reversing the blind.<br>
      This can be used to go to a specific position by measuring the time it takes to close the blind completely.
      </li>
    </ul>
  </ul>
  <br>

  <b>Get</b> <ul>N/A</ul><br>

  <a name="SOMFYattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. An example for the physical device is a CUL.<br>
        Note: The IODev has to be set, otherwise no commands will be sent!<br>
        If you have both a CUL868 and CUL433, use the CUL433 as IODev for increased range.
		</li><br>

    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values, each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or comma(,)
        then split not by space but by this character, enabling to embed spaces.
        Examples:<ul><code>
        attr store eventMap on:open off:closed<br>
        attr store eventMap /on-for-timer 10:open/off:closed/<br>
        set store open
        </code></ul>
        </li><br>

    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <a name="attrdummy"></a>
    <li>dummy<br>
    Set the device attribute dummy to define devices which should not
    output any radio signals. Associated notifys will be executed if
    the signal is received. Used e.g. to react to a code from a sender, but
    it will not emit radio signal if triggered in the web frontend.
    </li><br>

    <li><a href="#loglevel">loglevel</a></li><br>

    <li><a href="#showtime">showtime</a></li><br>

    <a name="model"></a>
    <li>model<br>
        The model attribute denotes the model type of the device.
        The attributes will (currently) not be used by the fhem.pl directly.
        It can be used by e.g. external programs or web interfaces to
        distinguish classes of devices and send the appropriate commands
        (e.g. "on" or "off" to a switch, "dim..%" to dimmers etc.).<br>
        The spelling of the model names are as quoted on the printed
        documentation which comes which each device. This name is used
        without blanks in all lower-case letters. Valid characters should be
        <code>a-z 0-9</code> and <code>-</code> (dash),
        other characters should be ommited.<br>
        Here is a list of "official" devices:<br>
          <b>Receiver/Actor</b>: somfyblinds<br>
    </li><br>


    <a name="ignore"></a>
    <li>ignore<br>
        Ignore this device, e.g. if it belongs to your neighbour. The device
        won't trigger any FileLogs/notifys, issued commands will silently
        ignored (no RF signal will be sent out, just like for the <a
        href="#attrdummy">dummy</a> attribute). The device won't appear in the
        list command (only if it is explicitely asked for it), nor will it
        appear in commands which use some wildcard/attribute as name specifiers
        (see <a href="#devspec">devspec</a>). You still get them with the
        "ignored=1" special devspec.
        </li><br>

  </ul>
  <br>

  <a name="SOMFYevents"></a>
  <b>Generated events:</b>
  <ul>
     From a Somfy device you can receive one of the following events.
     <li>on</li>
     <li>off</li>
     <li>stop</li>
     <li>go-my<br></li>
      Which event is sent is device dependent and can sometimes be configured on
     the device.
  </ul>
</ul>



=end html
=cut

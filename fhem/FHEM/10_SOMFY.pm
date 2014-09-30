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
#
# History:
#	1.0		thomyd			initial implementation
#
#	1.1		Elektrolurch	state changed to open,close,pos <x>
# 							for using "set device pos <value> the attributes
#							drive-down-time-to-100, drive-down-time-to-close,
#							drive-up-time-to-100 and drive-up-time-to-open must be set
# 							Hardware section seperated to SOMFY_SetCommand
#
#	1.2		Elektrolurch	state is now set after reaching the position of the blind
#							preparation for receiving signals of Somfy remotes signals,
#							associated with the blind
#
#	1.3		thomyd			Basic implementation of "parse" function, requires updated CULFW
#							Removed open/close as the same functionality can be achieved with an eventMap.

######################################################

package main;

use strict;
use warnings;

my %codes = (
	"10" => "go-my",    # goto "my" position
	"11" => "stop", 	# stop the current movement
	"20" => "off",      # go "up"
	"40" => "on",       # go "down"
	"80" => "prog",     # finish pairing
	"100" => "on-for-timer",
	"101" => "off-for-timer",
	"XX" => "z_custom",	# custom control code
);

my %sets = (
	"off" => "",
	"on" => "",
	"stop" => "",
	"go-my" => "",
	"prog" => "",
	"on-for-timer" => "textField",
	"off-for-timer" => "textField",
	"z_custom" => "textField",
	"pos" => "0,10,20,30,40,50,60,70,80,90,100"
);

my %somfy_c2b;

my $somfy_defsymbolwidth = 1240;    # Default Somfy frame symbol width
my $somfy_defrepetition = 6;	# Default Somfy frame repeat counter

my %models = ( somfyblinds => 'blinds', ); # supported models (blinds only, as of now)

#############################
sub myUtilsSOMFY_Initialize($) {
	$modules{SOMFY}{LOADED} = 1;
	my $hash = $modules{SOMFY};

	SOMFY_Initialize($hash);
} # end sub myUtilsSomfy_initialize

#############################
sub SOMFY_Initialize($) {
	my ($hash) = @_;

	# map commands from web interface to codes used in Somfy RTS
	foreach my $k ( keys %codes ) {
		$somfy_c2b{ $codes{$k} } = $k;
	}

	#                       YsKKC0RRRRAAAAAA
	#  $hash->{Match}	= "^YsA..0..........\$";
	$hash->{SetFn}		= "SOMFY_Set";
	#$hash->{StateFn} 	= "SOMFY_SetState";
	$hash->{DefFn}   	= "SOMFY_Define";
	$hash->{UndefFn}	= "SOMFY_Undef";
	$hash->{ParseFn}  	= "SOMFY_Parse";
	$hash->{AttrFn}  	= "SOMFY_Attr";

	$hash->{AttrList} = " drive-down-time-to-100"
	  . " drive-down-time-to-close"
	  . " drive-up-time-to-100"
	  . " drive-up-time-to-open "
	  . " IODev"
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
sub SOMFY_StartTime($) {
	my ($d) = @_;

	my ($s, $ms) = gettimeofday();

	my $t = $s + ($ms / 1000000); # 10 msec
	my $t1 = 0;
	$t1 = $d->{'starttime'} if(exists($d->{'starttime'} ));
	$d->{'starttime'}  = $t;
	my $dt = sprintf("%.2f", $t - $t1);

	return $dt;
} # end sub SOMFY_StartTime

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

	# group devices by their address
	my $name  = $a[0];
	my $address = $a[2];

	$hash->{ADDRESS} = uc($address);

	my $tn = TimeNow();

	# check optional arguments for device definition
	if ( int(@a) > 3 ) {

		# check encryption key (2 hex digits, first must be "A")
		if ( ( $a[3] !~ m/^[aA][a-fA-F0-9]{1}$/i ) ) {
			return "Define $a[0]: wrong encryption key format:"
			  . "specify a 2 digits hex value (first nibble = A) "
		}

		# store it as reading, so it is saved in the statefile
		# only store it, if the reading does not exist yet
		my $old_enc_key = uc(ReadingsVal($name, "enc_key", "invalid"));
		if($old_enc_key eq "invalid") {
			setReadingsVal($hash, "enc_key", uc($a[3]), $tn);
		}

		if ( int(@a) == 5 ) {
			# check rolling code (4 hex digits)
			if ( ( $a[4] !~ m/^[a-fA-F0-9]{4}$/i ) ) {
				return "Define $a[0]: wrong rolling code format:"
			 	 . "specify a 4 digits hex value "
			}

			# store it, if old reading does not exist yet
			my $old_rolling_code = uc(ReadingsVal($name, "rolling_code", "invalid"));
			if($old_rolling_code eq "invalid") {
				setReadingsVal($hash, "rolling_code", uc($a[4]), $tn);
			}
		}
	}

	my $code  = uc($address);
	my $ncode = 1;
	$hash->{CODE}{ $ncode++ } = $code;
	$modules{SOMFY}{defptr}{$code}{$name} = $hash;
	$hash->{move} = 'stop';
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
sub SOMFY_SendCommand($@)
{
	my ($hash, @args) = @_;
	my $ret = undef;
	my $cmd = $args[0];
	my $message;
	my $name = $hash->{NAME};
	my $numberOfArgs  = int(@args);


  # custom control needs 2 digit hex code
  return "Bad custom control code, use 2 digit hex codes only" if($args[0] eq "z_custom"
  	&& ($numberOfArgs == 1
  		|| ($numberOfArgs == 2 && $args[1] !~ m/^[a-fA-F0-9]{2}$/)));

    my $command = $somfy_c2b{ $cmd };
	# eigentlich überflüssig, da oben schon auf Existenz geprüft wird -> %sets
	if ( !defined($command) ) {

		return "Unknown argument $cmd, choose one of "
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
		$message = "t" . $attr{ $name }{"symbol-length"};
		IOWrite( $hash, "Y", $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set symbol-length: $message for $io->{NAME}";
	}


	## Do we need to change frame repetition?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"repetition"} ) )
	{
		$message = "r" . $attr{ $name }{"repetition"};
		IOWrite( $hash, "Y", $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set repetition: $message for $io->{NAME}";
	}

	my $value = $name ." ". join(" ", @args);

	# convert old attribute values to READINGs
	my $timestamp = TimeNow();
	if(defined($attr{$name}{"enc-key"} && defined($attr{$name}{"rolling-code"}))) {
		setReadingsVal($hash, "enc_key", $attr{$name}{"enc-key"}, $timestamp);
		setReadingsVal($hash, "rolling_code", $attr{$name}{"rolling-code"}, $timestamp);

		# delete old attribute
		delete($attr{$name}{"enc-key"});
		delete($attr{$name}{"rolling-code"});
	}

	# message looks like this
	# Ys_key_ctrl_cks_rollcode_a0_a1_a2
	# Ys ad 20 0ae3 a2 98 42

	my $enckey = uc(ReadingsVal($name, "enc_key", "A0"));
	my $rollingcode = uc(ReadingsVal($name, "rolling_code", "0000"));

	if($command eq "XX") {
		# use user-supplied custom command
		$command = $args[1];
	}

	$message = "s"
	  . $enckey
	  . $command
	  . $rollingcode
	  . uc( $hash->{ADDRESS} );

	## Log that we are going to switch Somfy
	Log GetLogLevel( $name, 2 ), "SOMFY set $value: $message";
	( undef, $value ) = split( " ", $value, 2 );    # Not interested in the name...

	## Send Message to IODev using IOWrite
	IOWrite( $hash, "Y", $message );

	# increment encryption key and rolling code
	my $enc_key_increment      = hex( $enckey );
	my $rolling_code_increment = hex( $rollingcode );

	my $new_enc_key = sprintf( "%02X", ( ++$enc_key_increment & hex("0xAF") ) );
	my $new_rolling_code = sprintf( "%04X", ( ++$rolling_code_increment ) );

	# update the readings, but do not generate an event
	setReadingsVal($hash, "enc_key", $new_enc_key, $timestamp);
	setReadingsVal($hash, "rolling_code", $new_rolling_code, $timestamp);

	## Do we need to change symbol length back?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"symbol-length"} ) )
	{
		$message = "t" . $somfy_defsymbolwidth;
		IOWrite( $hash, "Y", $message );
		Log GetLogLevel( $name, 4 ),
		  "SOMFY set symbol-length back: $message for $io->{NAME}";
	}

	## Do we need to change repetition back?
	if (   defined( $attr{ $name } )
		&& defined( $attr{ $name }{"repetition"} ) )
	{
		$message = "r" . $somfy_defrepetition;
		IOWrite( $hash, "Y", $message );
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
	# Look for all devices with the same address, and set state, enc-key, rolling-code and timestamp
	my $code = "$hash->{ADDRESS}";
	my $tn   = TimeNow();
	foreach my $n ( keys %{ $modules{SOMFY}{defptr}{$code} } ) {

		my $lh = $modules{SOMFY}{defptr}{$code}{$n};
		$lh->{READINGS}{enc_key}{TIME} 		= $tn;
		$lh->{READINGS}{enc_key}{VAL}       = $new_enc_key;
		$lh->{READINGS}{rolling_code}{TIME} = $tn;
		$lh->{READINGS}{rolling_code}{VAL}  = $new_rolling_code;
	}
	return $ret;
} # end sub SOMFY_SendCommand

###################################
sub SOMFY_CalcNewPos($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $dt = SOMFY_StartTime($hash);
	my $move = $hash->{move};
	my $oldpos = $hash->{oldpos};
	my $newpos = ($move eq 'up')?0:100; # it works anyway
	my $timestamp = TimeNow();


	# Attributes for calulation
	my $t1down100 = AttrVal($name,'drive-down-time-to-100',undef);
	my $t1downclose = AttrVal($name,'drive-down-time-to-close',undef);
	my $t1upopen = AttrVal($name,'drive-up-time-to-open',undef);
	my $t1up100 =  AttrVal($name,'drive-up-time-to-100',undef);

	if(defined($t1down100) && defined($t1downclose) && defined($t1up100) && defined($t1upopen)) {
		# attributes are set
		if($move eq 'down') {
			$newpos = $oldpos + (100 * $dt / $t1down100);

		} elsif($move eq 'up') {
			if($oldpos > 100) {
				$dt = $dt - $t1up100;
				$newpos = $oldpos - (100 * $dt / ($t1upopen - $t1up100));
				$newpos = 100 if($newpos > 100), # driven only short between close and pos 100!

			} else {
				$newpos = $oldpos - (100 * $dt / ($t1upopen - $t1up100));

			}
			$newpos = 0 if($newpos < 0);

		} else {
			Log3($name,1,"SOMFY_CalcNewPos: $name move wrong $move");
		} # error
	} else {
		# no attributes set
		Log3($name,1,"SOMFY_CalcNewPos $name drive-down-time... attributes not set");
	}

	# update state
	my $value;
	if($newpos == 0) {
		$value = 'off';

	} elsif($newpos > 100) {
		$value = 'on';

	} else {
		$value = 'pos '.SOMFY_Runden($newpos); # for using icons in state
	}

	$hash->{CHANGED}[0]            = $value;
	$hash->{STATE}                 = $value;
	$hash->{READINGS}{state}{TIME} = $timestamp;
	$hash->{READINGS}{state}{VAL}  = $value;
	setReadingsVal($hash,'position',$newpos,$timestamp);

	# finish move
	$hash->{move} = 'stop';
	return undef;
} # end sub SOMFY_CalcNewPos

###################################
sub SOMFY_SendStop($) {
	my ($hash) = @_;
	SOMFY_SendCommand($hash,'stop');
	SOMFY_CalcNewPos($hash);
} # end sub SOMFY_SendStop

###################################
sub SOMFY_Runden($) {
	my ($v) = @_;
	return sprintf("%d", ($v + 5) /10) * 10;
} # end sub SOMFY_Runden

###################################
sub SOMFY_Set($@) {
	my ( $hash, $name, @args ) = @_;
	my $numberOfArgs  = int(@args);

	if ( $numberOfArgs < 1 ) {
		return "no set value specified" ;
	}

	my $cmd = lc($args[0]);
	my $drivetime = 0; # on/off-for-timer and pos <value> -> move by time
	my $updatetime = 0; # move to endpos or go-my / stop -> assume stop = pos 100

	my $oldpos = ReadingsVal($name,'position',0);
	$hash->{oldpos} = $oldpos; # store it for later recalculation
	my $newpos = $args[1];

	return "Bad time spec" if($cmd =~m/(on|off)-for-timer/ && $numberOfArgs == 2 && $args[1] !~ m/^\d*\.?\d+$/);

	if(($cmd =~m/off/) || ($cmd eq 'pos' &&  $args[1] == 0)) {
		$cmd = 'off';
		$hash->{move} = 'up';
		$newpos = 0;
		$updatetime = (AttrVal($name,'drive-up-time-open',25) - AttrVal($name,'drive-up-time-100',0)) * $oldpos / 100;

	} elsif ($cmd =~m/on/) {
		$cmd = 'on';
		$hash->{move} = 'down';

		my $t1 = AttrVal($name,'drive-down-time-to-100',100);
		my $t2 = AttrVal($name,'drive-down-time-to-close',100);
		$newpos = sprintf("%d",100 * $t2/$t1);
		$updatetime = $t1* (1 - ($oldpos / 100)) + ($t2 - $t1);

	} elsif($cmd eq 'pos') {
		return "bad pos specification"  if(!defined($newpos));
		return "SOMFY_set: oldpos eq newpos ($newpos" if($newpos == $oldpos);
		return  "SOMFY_set: $newpos must be > 0 and < 100" if($newpos < 0 || $newpos > 100);

		my $t1down = AttrVal($name,'drive-down-time-to-100',undef);
		my $t1upopen = AttrVal($name,'drive-up-time-to-open',undef);
		my $t1up100 =  AttrVal($name,'drive-up-time-to-100',undef);
		return "Please set attr drive-down-time-to-100, drive-down-time-to-close, "
		. "drive-up-time-to-100 and drive-up-time-to-open before using the pos <value> extension" if(!defined($t1down) || !defined($t1upopen) || !defined($t1up100));

		if($newpos > $oldpos) { # down
			$cmd = 'on';
			$hash->{move} = 'down';
			$drivetime = ($t1down * ($newpos -  $oldpos) / 100);

		} else { # up
			$cmd = 'off';
			$hash->{move} = 'up';
			my $t1 = $t1upopen - $t1up100;
			$drivetime = ($t1 * ($oldpos -  $newpos) / 100);
		}
		Log3($name,3,"somfy_set: cmd $cmd newpos $newpos drivetime $drivetime");

	} elsif($cmd =~m/stop|go_my/) { # assuming stop = pos 100
		$newpos = 100;
		$hash->{move} = 'stop';
		$hash->{READINGS}{position}{VAL} = 100;
		Log3($name,1,"SOMFY_set: Warning: go-my/stop will mess up correct positioning! Please use pos <value> instead.");

	} elsif($cmd eq 'on-for-timer') {
		$cmd = 'on';
		$hash->{move} = 'down';
		$drivetime = $args[1];
		my $tclose = AttrVal($name,'drive-down-time-to-close',25);
		my $tmax = ($oldpos / 100) * $tclose;

		if(($tmax + $drivetime) > $tclose) { # limit ?
			$drivetime = 0;
			$updatetime = $tmax;
		}
	} elsif($cmd eq 'off-for-timer') {
		$cmd = 'off';
		$hash->{move} = 'up';
		$drivetime = $args[1];
		my $topen = AttrVal($name,'drive-up-time-to-open',25);
		my $t100 = AttrVal($name,'drive-up-time-to-100',0);
		my $tpos =  $topen * ($topen / ($topen - $t100)) - ($oldpos / 100);

		if(($tpos + $drivetime) > $topen) { # limit ?
			$drivetime  = 0;
			$updatetime = $tpos;
		}
	} elsif(!exists($sets{$cmd})) {
		my @cList;
		foreach my $k (sort keys %sets) {
			my $opts = undef;
			$opts = $sets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		} # end foreach

		return "Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error and ? handling

	$args[0] = $cmd;

	if($drivetime > 0) {
		# timer fuer stop starten
		RemoveInternalTimer($hash);
		Log3($name,3,"SOMFY_set: $name -> stopping in $drivetime sec");
		InternalTimer(gettimeofday()+$drivetime,"SOMFY_SendStop",$hash,0);

	} elsif($updatetime > 0) {
		# timer fuer Update state starten
		RemoveInternalTimer($hash);
		Log3($name,3,"SOMFY_set: $name -> state update in $updatetime sec");
		InternalTimer(gettimeofday()+$updatetime,"SOMFY_CalcNewPos",$hash,0);

	} else {
		Log3($name,1,"SOMFY_set: Error - drivetime and updatetime = 0");
	}

	SOMFY_SendCommand($hash,@args);
	SOMFY_StartTime($hash);

	return undef;
} # end sub SOMFY_setFN
###############################


#############################
sub SOMFY_Parse($$) {
	my ($hash, $msg) = @_;

	# Msg format:
	# Ys AB 2C 004B 010010
	# address needs bytes 1 and 3 swapped

	if (substr($msg, 0, 2) eq "Yr" || substr($msg, 0, 2) eq "Yt") {
		# changed time or repetition, just return the name
		return $hash->{NAME};
	}

    # get address
    my $address = uc(substr($msg, 14, 2).substr($msg, 12, 2).substr($msg, 10, 2));

    # get command and set new state
	my $cmd = sprintf("%X", hex(substr($msg, 4, 2)) & 0xF0);
	if ($cmd eq "10") {
	 $cmd = "11"; # use "stop" instead of "go-my"
    }

	my $newstate = $codes{ $cmd };

	my $def = $modules{SOMFY}{defptr}{$address};

	if($def) {
		my @list;
		foreach my $name (keys %{ $def }) {
      		my $lh = $def->{$name};
     	 	$name = $lh->{NAME};        # It may be renamed

      		return "" if(IsIgnored($name));   # Little strange.

      		# update the state and log it
     		readingsSingleUpdate($lh, "state", $newstate, 1);

			Log3 $name, 4, "SOMFY $name $newstate";

			push(@list, $name);
		}
		# return list of affected devices
		return @list;

	} else {
		Log3 $hash, 3, "SOMFY Unknown device $address, please define it";
		return "UNDEFINED SOMFY_$address SOMFY $address";
	}
}
##############################
sub SOMFY_Attr(@) {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};

	return "\"SOMFY Attr: \" $name does not exist" if (!defined($hash));

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	if ($cmd eq "set") {
		if ($aName =~/drive-(down|up)-time-to.*/) {
			# check name and value
			return "SOMFY_attr: value must be >0 and <= 100" if($aVal <= 0 || $aVal > 100);
		}

		if ($aName eq 'drive-down-time-to-100') {
			$attr{$name}{'drive-down-time-to-100'} = $aVal;
			$attr{$name}{'drive-down-time-to-close'} = $aVal if(!defined($attr{$name}{'drive-down-time-to-close'}) || ($attr{$name}{'drive-down-time-to-close'} < $aVal));

		} elsif($aName eq 'drive-down-time-to-close') {
			$attr{$name}{'drive-down-time-to-close'} = $aVal;
			$attr{$name}{'drive-down-time-to-100'} = $aVal if(!defined($attr{$name}{'drive-down-time-to-100'}) || ($attr{$name}{'drive-down-time-to-100'} > $aVal));

		} elsif($aName eq 'drive-up-time-to-100') {
			$attr{$name}{'drive-up-time-to-100'} = $aVal;

		} elsif($aName eq 'drive-up-time-to-open') {
			$attr{$name}{'drive-up-time-to-open'} = $aVal;
			$attr{$name}{'drive-up-time-to-100'} = 0 if(!defined($attr{$name}{'drive-up-time-to-100'}) || ($attr{$name}{'drive-up-time-to-100'} > $aVal));
		}
	}

	return undef;
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
  Right now only SENDING of Somfy commands is implemented in the CULFW, so this module currently only
  supports devices like blinds, dimmers, etc. through a <a href="#CUL">CUL</a> device (which must be defined first).

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
    pos value (0..100) # see note
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
      <code>set rollo_1 pos 50</code><br>
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
      <li>pos value<br>
	  The position must be between 0 and 100 and the appropriate
	  attributes drive-down-time-to-100, drive-down-time-to-close,
	  drive-up-time-to-100 and drive-up-time-to-open must be set.<br>
	  pos 100 means the blind covers the window (but is not completely shut), 0 means it is completely open.
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

    <a name="drive-down-time-to-100"></a>
    <li>drive-down-time-to-100<br>
        The time the blind needs to drive down from "open" (pos 0) to pos 100.<br>
		In this position, the lower edge touches the window frame, but it is not completely shut.<br>
		For a mid-size window this time is about 12 to 15 seconds.
        </li><br>

    <a name="drive-down-time-to-close"></a>
    <li>drive-down-time-to-close<br>
        The time the blind needs to drive down from "open" (pos 0) to "close", the end position of the blind.<br>
		This is about 3 to 5 seonds more than the "drive-down-time-to-100" value.
        </li><br>

    <a name="drive-up-time-to-100"></a>
    <li>drive-up-time-to-100<br>
        The time the blind needs to drive up from "close" (endposition) to "pos 100".<br>
		This usually takes about 3 to 5 seconds.
        </li><br>

    <a name="drive-up-time-to-open"></a>
    <li>drive-up-time-to-open<br>
        The time the blind needs drive up from "close" (endposition) to "open" (upper endposition).<br>
		This value is usually a bit higher than "drive-down-time-to-close", due to the blind's weight.
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

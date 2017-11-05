######################################################
# $Id$
#
# Dooya module for FHEM
# Thanks for templates/coding from Somfy and SIGNALduino team
#
# Needs SIGNALduino.
# Published under GNU GPL License, v2
# History:
# 0.10	2016-02-16	Jarnsen		initial template
# 0.20	2016-03-06	darkmission	first functions, renamed from 10_ to 99_
# 0.21	2016-03-06	darkmission	Bug default channel corrected, changed attribute repetition to SignalRepeats
# 0.22  2016-03-10	darkmission	code cleaned, renamed from 99_ to 98_
# 0.23  2016-03-11	Jarnsen		AttrList cleaned and change priority
# 1.00	2016-03-12	darkmission	autocreate, parse communication from SIGNALduino for correct position when using remote from doooya 
# 1.10  2016-03-13	Ralf9		changed SendCommand with sendMsg
# 1.11  2016-03-17	Ralf9   	ID + Channel = DeviceCode
# 1.12  2016-04-26      Jarnsen     im Dooya parse cmd geändert
# 1.13	2017-08-26	darkmission	Update state when called by remote, little code cleaning (setlist and go-my deleted), some more debug messages

#TODOS:
# - Groups, diff by channels
# 
######################################################


package main;

use strict;
use warnings;

#use List::Util qw(first max maxstr min minstr reduce shuffle sum);

my %codes = (
	"01010101" => "stop", 	  # stop the current movement
	"00010001" => "off",      # go "up"
	"00110011" => "on",       # go "down"
	"11001100" => "prog",     # finish pairing
);

my %sets = (
	"off" => "noArg",
	"on" => "noArg",
	"down"=> "noArg",
	"stop" => "noArg",
	"prog" => "noArg",
#	"on-for-timer" => "textField",
#	"off-for-timer" => "textField",
#	"pos" => "0,10,20,30,40,50,60,70,80,90,100"    # Todo: Warum nicht als Slider?
	"pos" => "slider,0,10,100"
);

my %sendCommands = (
	"off" => "off",
	"open" => "off",
	"on" => "on",
	"close" => "on",
	"prog" => "prog",
	"stop" => "stop"
);

my %dooya_c2b;                                           # Todo: Als internal speichern
my $dooya_updateFreq = 3;	# Interval for State update  # Todo: Als internal speichern

# supported models (blinds  and shutters)
my %models = ( 
	dooyablinds => 'blinds', 
	dooyashutter => 'shutter' 
); 
	

##################################################
# new globals for new set
#

my $dooya_posAccuracy = 2;            # Todo: Als internal speichern
my $dooya_maxRuntime = 50;            # Todo: Als internal speichern

my %positions = (
	"moving" => "50", 
	"open" => "0",
	"off" => "0",
	"down" => "150", 
	"closed" => "200",
	"on" => "200"
);

my %translations = (
	"0" => "open", 
	"10" => "10", 
	"20" => "20", 
	"30" => "30", 
	"40" => "40", 
	"50" => "50", 
	"60" => "60", 
	"70" => "70", 
	"80" => "80", 
	"90" => "90", 
	"100" => "100", 
	"150" => "down", 
	"200" => "closed"
);

######################################################
# Forward declarations
#
sub Dooya_CalcCurrentPos($$$$);

######################################################
sub myUtilsDooya_Initialize($) {
	$modules{Dooya}{LOADED} = 1;
	my $hash = $modules{Dooya};

	Dooya_Initialize($hash);
} # end sub myUtilsDooya_initialize

######################################################
sub Dooya_Initialize($) {
	my ($hash) = @_;

	# map commands from web interface to codes used in Dooya
	foreach my $k ( keys %codes ) {
		$dooya_c2b{ $codes{$k} } = $k;
	}

	$hash->{SetFn}		= "Dooya_Set";
	#$hash->{StateFn} 	= "Dooya_SetState";
	$hash->{DefFn}   	= "Dooya_Define";
	$hash->{UndefFn}	= "Dooya_Undef";
	$hash->{ParseFn}  	= "Dooya_Parse";
	$hash->{AttrFn}  	= "Dooya_Attr";
	$hash->{Match}     	= "^P16#[A-Fa-f0-9]+";
	$hash->{AttrList} = " IODev"
	  . " SignalRepeats:5,10,15,20"
	  . " channel:0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
	  . " drive-down-time-to-100"
	  . " drive-down-time-to-close"
	  . " drive-up-time-to-100"
	  . " drive-up-time-to-open"
	  . " additionalPosReading"
	  . " $readingFnAttributes"
#	  . " setList"
	  . " ignore:0,1"
	  . " dummy:1,0"
#	  . " model:dooyablinds,dooyashutter"
	  . " loglevel:0,1,2,3,4,5,6";
	
	$hash->{AutoCreate} =
      { "Dooya.*" => { ATTR => "event-min-interval:.*:300 event-on-change-reading:.*", 
                       FILTER => "%NAME",
                       autocreateThreshold => "2:10" } };
}

######################################################
sub Dooya_StartTime($) {
	my ($d) = @_;

	my ($s, $ms) = gettimeofday();

	my $t = $s + ($ms / 1000000); # 10 msec
	my $t1 = 0;
	$t1 = $d->{'starttime'} if(exists($d->{'starttime'} ));
	$d->{'starttime'}  = $t;
	my $dt = sprintf("%.2f", $t - $t1);

	return $dt;
} # end sub Dooya_StartTime

######################################################
sub Dooya_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my $u = "wrong syntax: define <name> Dooya id ";

	# fail early and display syntax help
	if ( int(@a) < 3 ) {
		return $u;
	}

	my ($id, $channel) = split('_', $a[2]);
	Log3 $hash,4 ,"Dooya_Define: id = $id channel = $channel";
	
	# check id format (28 binaer digits)
	if ( ( $id !~ m/^[0-1]{28}$/i ) ) {
		return "Define $a[0]: wrong address format: specify a 28 binaer id value "
	}

	# group devices by their id
	my $name  = $a[0];

	$hash->{ID} = uc($id);
	$hash->{CHANNEL} = $channel;

	my $tn = TimeNow();

	my $code  = uc($a[2]);
	my $ncode = 1;
	$hash->{CODE}{ $ncode++ } = $code;
	$modules{Dooya}{defptr}{$code}{$name} = $hash;
	$hash->{move} = 'stop';
	AssignIoPort($hash);
}

######################################################
sub Dooya_Undef($$) {
	my ( $hash, $name ) = @_;

	foreach my $c ( keys %{ $hash->{CODE} } ) {
		$c = $hash->{CODE}{$c};

		# As after a rename the $name my be different from the $defptr{$c}{$n}
		# we look for the hash.
		foreach my $dname ( keys %{ $modules{Dooya}{defptr}{$c} } ) {
			if ( $modules{Dooya}{defptr}{$c}{$dname} == $hash ) {
				delete( $modules{Dooya}{defptr}{$c}{$dname} );
			}
		}
	}
	return undef;
}

######################################################
sub Dooya_SendCommand($@){

	my ($hash, @args) = @_;
	my $ret = undef;
	my $cmd = $args[0];
	my $message;
	my $chan;
	my $channel;
	my $SignalRepeats;
	my $name = $hash->{NAME};
	my $bin;
	my $numberOfArgs  = int(@args);

	Log3($name,4,"Dooya_sendCommand: $name -> cmd :$cmd: ");
 
	my $command = $dooya_c2b{ $cmd };
	
	# eigentlich ueberfluessig, da oben schon auf Existenz geprueft wird -> %sets
	if ( !defined($command) ) {
		return "Unknown argument $cmd, choose one of "
		  . join( " ", sort keys %dooya_c2b );
	}
	
	my $io = $hash->{IODev};

	$SignalRepeats = AttrVal($name,'SignalRepeats', '10');
	Log3 $io,4, "Dooya set SignalRepeats: $SignalRepeats for $io->{NAME}";
	
	$chan = AttrVal($name,'channel', undef);
	if (!defined($chan)) {
		$chan = $hash->{CHANNEL};
	}
	$channel = sprintf("%04b",$chan);
	Log3 $io,4, "Dooya set channel: $chan ($channel) for $io->{NAME}";
	
	my $value = $name ." ". join(" ", @args);

	$bin = 	uc($hash->{ID}) . $channel . $command;
	#print ("data = $bin \n");
	
	Log3 $io, 4, "Dooya set value = $value";

	## Send Message to IODev using IOWrite
	$message = 'P16#' . $bin . '#R' . $SignalRepeats;
	Log3 $io, 4, "Dooya_sendCommand: $name -> message :$message: ";
	IOWrite($hash, 'sendMsg', $message);

	return $ret;
} # end sub Dooya_SendCommand

######################################################
sub Dooya_Runden($) {                                  
	my ($v) = @_;
	if ( ( $v > 105 ) && ( $v < 195 ) ) {
		$v = 150;
	} else {
		$v = int(($v + 5) /10) * 10;
	}
	
	return sprintf("%d", $v );
} # end sub Dooya_Runden

######################################################
sub Dooya_Translate($) {
	my ($v) = @_;

	if(exists($translations{$v})) {
		$v = $translations{$v}
	}

	return $v
} # end sub Dooya_Runden

######################################################
sub Dooya_Parse($$) {

	my ($hash, $msg) = @_;
	my (undef ,$rawData) = split("#",$msg);

    my $hlen = length($rawData);
    my $blen = $hlen * 4;
    my $bitData = unpack("B$blen", pack("H$hlen", $rawData)); 

    Log3 $hash, 4, "Dooya_Parse: rawData = $rawData length: $hlen";
    Log3 $hash, 4, "Dooya_Parse: converted to bits: $bitData";

    # get id, channel, cmd
   my $id = substr($bitData, 0, 28);
   my $BitChannel = substr($bitData, 28, 4); #noch nicht benoetigt
   my $channel = oct("0b" . $BitChannel);
   my $cmd = substr($bitData, 32, 4);
   my $newstate = $codes{ $cmd . $cmd};            # set new state
   my $deviceCode = $id . '_' . $channel;

    Log3 $hash, 4, "Dooya_Parse: device ID: $id";
    Log3 $hash, 4, "Dooya_Parse: Channel: $channel";
    Log3 $hash, 4, "Dooya_Parse: Cmd: $cmd  Newstate: $newstate";
    Log3 $hash, 4, "Dooya_Parse: deviceCode: $deviceCode";

	my $def = $modules{Dooya}{defptr}{$deviceCode};

	if($def) {
		my @list;
		foreach my $name (keys %{ $def }) {
      		my $lh = $def->{$name};
     		$name = $lh->{NAME};        # It may be renamed

      		return "" if(IsIgnored($name));   # Little strange.

      		# update the state and log it
					### NEEDS to be deactivated due to the state being maintained by the timer
					# readingsSingleUpdate($lh, "state", $newstate, 1);
					readingsSingleUpdate($lh, "parsestate", $newstate, 1);
					
					Log3 $name, 4, "Dooya_Parse n:$name ns:$newstate lhn:$lh->{NAME} lht:$lh->{TYPE}";				
					Dooya_Set( $lh, $name, 'virtual', $newstate );
			push(@list, $name);
		}
		# return list of affected devices
		return @list;

	} else {
		Log3 $hash, 3, "Dooya Unknown device $deviceCode, please define it";
		return "UNDEFINED Dooya_$deviceCode Dooya $deviceCode";
	}
}

######################################################
sub Dooya_Attr(@) {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};

	return "\"Dooya Attr: \" $name does not exist" if (!defined($hash));

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	if ($cmd eq "set") {
		if($aName eq 'drive-up-time-to-100') {
			return "Dooya_attr: value must be >=0 and <= 100" if($aVal < 0 || $aVal > 100);
		} elsif ($aName =~/drive-(down|up)-time-to.*/) {
			# check name and value
			return "Dooya_attr: value must be >0 and <= 100" if($aVal <= 0 || $aVal > 100);
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

##################################################
### New set (state) method (using internalset)
###
### Reimplemented calculations for position readings and state
### Allowed sets to be done without sending actually commands to the blinds
### 	syntax set <name> [ <virtual|send> ] <normal set parameter>
### position and state are also updated on stop or other commands based on remaining time
### position is handled between 0 and 100 blinds down but not completely closed and 200 completely closed
### 	if timings for 100 and close are equal no position above 100 is used (then 100 == closed)
### position is rounded to a value of 5 and state is rounded to a value of 10
#
### General assumption times are rather on the upper limit to reach desired state


# Readings
## state contains rounded (to 10) position and/or textField
## position contains rounded position (limited detail)

# STATE
## might contain position or textual form of the state (same as STATE reading)


######################################################
# call with hash, name, [virtual/send], set-args   (send is default if ommitted)
sub Dooya_Set($@) {
	my ( $hash, $name, @args ) = @_;
	Log3 $name, 4, "Dooya_Set: Called";
	
	if ( lc($args[0]) =~m/(virtual|send)/ ) {
		Log3 $name, 4, "Dooya_InternalSet call $args[0] ";
		Dooya_InternalSet( $hash, $name, @args );

	} else {
		Log3 $name, 4, "Dooya_InternalSet call send $hash->{NAME} $hash->{TYPE} $name";
		Dooya_InternalSet( $hash, $name, 'send', @args );
	}
}

######################################################
# call with hash, name, virtual/send, set-args
sub Dooya_InternalSet($@) {
	my ( $hash, $name, $mode, @args ) = @_;
	
	### Check Args
	return "Dooya_InternalSet: mode must be virtual or send: $mode " if ( $mode !~m/(virtual|send)/ );

	my $numberOfArgs  = int(@args);
	return "Dooya_set: No set value specified" if ( $numberOfArgs < 1 );

	my $cmd = lc($args[0]);

	# just a number provided, assume "pos" command
	if ($cmd =~ m/\d{1,3}/) {
		pop @args;
		push @args, "pos";
		push @args, $cmd;

		$cmd = "pos";
		$numberOfArgs = int(@args);
	}

	if(!exists($sets{$cmd})) {
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

		return "Dooya_set: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling

	my $arg1 = "";
	if ( $numberOfArgs >= 2 ) {
		$arg1 = $args[1];
	}
	
	return "Dooya_set: Bad time spec" if($cmd =~m/(on|off)-for-timer/ && $numberOfArgs == 2 && $arg1 !~ m/^\d*\.?\d+$/);

	# read timing variables
  my ($t1down100, $t1downclose, $t1upopen, $t1up100) = Dooya_getTimingValues($hash);
	Log3($name,5,"Dooya_set: $name -> timings ->  td1:$t1down100: tdc :$t1downclose:  tuo :$t1upopen:  tu1 :$t1up100: ");

	my $model =  AttrVal($name,'model',$models{dooyablinds});
	
	if($cmd eq 'pos') {
		return "Dooya_set: No pos specification"  if(!defined($arg1));
		return "Dooya_set: $arg1 must be > 0 and < 100 for pos" if($arg1 < 0 || $arg1 > 100);
		return "Dooya_set: Please set attr drive-down-time-to-100, drive-down-time-to-close, etc"
				if(!defined($t1downclose) || !defined($t1down100) || !defined($t1upopen) || !defined($t1up100));
	}

		### initialize locals
	my $drivetime = 0; # timings until halt command to be sent for on/off-for-timer and pos <value> -> move by time
	my $updatetime = 0; # timing until update of pos to be done for any unlimited move move to endpos stop
	my $move = $cmd;
	my $newState;
	my $updateState;
	
	# get current infos
	my $state = $hash->{STATE};
	my $pos = ReadingsVal($name,'exact',undef);
	if ( !defined($pos) ) {
		$pos = ReadingsVal($name,'position',undef);
	}

	# translate state info to numbers - closed = 200 , open = 0    (correct missing values)
	if ( !defined($pos) ) {
		if(exists($positions{$state})) {
			$pos = $positions{$state};
		} else {
			$pos = $state;
		}
		$pos = sprintf( "%d", $pos );
	}

	Log3($name,4,"Dooya_set: $name -> entering with mode :$mode: cmd :$cmd:  arg1 :$arg1:  pos :$pos: ");

	# check timer running - stop timer if running and update detail pos
	# recognize timer running if internal updateState is still set
	if ( defined( $hash->{updateState} )) {
		# timer is running so timer needs to be stopped and pos needs update
		RemoveInternalTimer($hash);
		
		$pos = Dooya_CalcCurrentPos( $hash, $hash->{move}, $pos, Dooya_UpdateStartTime($hash) );
		delete $hash->{starttime};
		delete $hash->{updateState};
		delete $hash->{runningtime};
		delete $hash->{runningcmd};
	}

	################ No error returns after this point to avoid stopped timer causing confusion...

	# calc posRounded
	my $posRounded = Dooya_RoundInternal( $pos );

	### handle commands
	if(!defined($t1downclose) || !defined($t1down100) || !defined($t1upopen) || !defined($t1up100)) {
		#if timings not set

		if($cmd eq 'on') {
			$newState = 'closed';
#			$newState = 'moving';
#			$updatetime = $dooya_maxRuntime;
#			$updateState = 'closed';
		} elsif($cmd eq 'off') {
			$newState = 'open';
#			$newState = 'moving';
#			$updatetime = $dooya_maxRuntime;
#			$updateState = 'open';

		} elsif($cmd eq 'on-for-timer') {
			# elsif cmd == on-for-timer - time x
			$move = 'on';
			$newState = 'moving';
			$drivetime = $arg1;
			if ( $drivetime == 0 ) {
				$move = 'stop';
			} else {
				$updateState = 'moving';
			}

		} elsif($cmd eq 'off-for-timer') {
			# elsif cmd == off-for-timer - time x
			$move = 'off';
			$newState = 'moving';
			$drivetime = $arg1;
			if ( $drivetime == 0 ) {
				$move = 'stop'; 
			} else {
				$updateState = 'moving';
			}

		} elsif($cmd =~m/stop/) {
			$move = 'stop';
			$newState = $state

		} else {
			$newState = $state;
		}

	###else (here timing is set)
	} else {
		# default is roundedPos as new StatePos
		$newState = $posRounded;

		if($cmd eq 'on') {
			if ( $posRounded == 200 ) {
				# 	if pos == 200 - no state pos change / no timer
			} elsif ( $posRounded >= 100 ) {
				# 	elsif pos >= 100 - set timer for 100-to-closed  --> update timer(newState 200)
				my $remTime = ( $t1downclose - $t1down100 ) * ( (200-$pos) / 100 );
				$updatetime = $remTime;

				$updateState = 200;
			} elsif ( $posRounded < 100 ) {
				#		elseif pos < 100 - set timer for remaining time to 100+time-to-close  --> update timer( newState 200)
				my $remTime = $t1down100 * ( (100 - $pos) / 100 );
				$updatetime = ( $t1downclose - $t1down100 ) + $remTime;
				$updateState = 200;
			} else {
				#		else - unknown pos - assume pos 0 set timer for full time --> update timer( newState 200)
				$newState = 0;
				$updatetime = $t1downclose;
				$updateState = 200;
			}

		} elsif($cmd eq 'off') {
			if ( $posRounded == 0 ) {
				# 	if pos == 0 - no state pos change / no timer
			} elsif ( $posRounded <= 100 ) {
				# 	elsif pos <= 100 - set timer for remaining time to 0 --> update timer( newState 0 )
				my $remTime = ( $t1upopen - $t1up100 ) * ( $pos / 100 );
				$updatetime = $remTime;
				$updateState = 0;
			} elsif ( $posRounded > 100 ) {
				#		elseif ( pos > 100 ) - set timer for remaining time to 100+time-to-open --> update timer( newState 0 )
				my $remTime = $t1up100 * ( ($pos - 100 ) / 100 );
				$updatetime = ( $t1upopen - $t1up100 ) + $remTime;
				$updateState = 0;
			} else {
				#		else - unknown pos assume pos 200 set time for full time --> update timer( newState 0 )
				$newState = 200;
				$updatetime = $t1upopen;
				$updateState = 0;
			}

		} elsif($cmd eq 'pos') {
			if ( $pos < $arg1 ) {
				# 	if pos < x - set halt timer for remaining time to x / cmd close --> halt timer`( newState x )
				$move = 'on';
				my $remTime = $t1down100 * ( ( $arg1 - $pos ) / 100 );
				$drivetime = $remTime;
				$updateState = $arg1;
			} elsif ( (  $pos >= $arg1 ) && ( $posRounded <= 100 ) ) {
				# 	elsif pos <= 100 & pos > x - set halt timer for remaining time to x / cmd open --> halt timer ( newState x )
				$move = 'off';
				my $remTime = ( $t1upopen - $t1up100 ) * ( ( $pos - $arg1) / 100 );
				$drivetime = $remTime;
				if ( $drivetime == 0 ) {
					# $move = 'stop';    # avoid sending stop to move to my-pos
          $move = 'none'; 
				} else {
					$updateState = $arg1;
				}
			} elsif ( $pos > 100 ) {
				#		else if pos > 100 - set timer for remaining time to 100+time for 100-x / cmd open --> halt timer ( newState x )
				$move = 'off';
				my $remTime = ( $t1upopen - $t1up100 ) * ( ( 100 - $arg1) / 100 );
				my $posTime = $t1up100 * ( ( $pos - 100) / 100 );
				$drivetime = $remTime + $posTime;
				$updateState = $arg1;
			} else {
				#		else - send error (might be changed to first open completely then drive to pos x) / assume open
				$newState = 0;
				$move = 'on';
				my $remTime = $t1down100 * ( ( $arg1 - 0 ) / 100 );
				$drivetime = $remTime;
				$updateState = $arg1;
			###				return "Dooya_set: Pos not currently known please open or close first";
			}

		} elsif($cmd =~m/stop/) {
			#		update pos according to current detail pos
			$move = 'stop';
			
		} elsif($cmd eq 'off-for-timer') {
			#		calcPos at new time y / cmd close --> halt timer ( newState y )
			$move = 'off';
			$drivetime = $arg1;
			if ( $drivetime == 0 ) {
				$move = 'stop';   
			} else {
				$updateState = 	Dooya_CalcCurrentPos( $hash, $move, $pos, $arg1 );
			}

		} elsif($cmd eq 'on-for-timer') {
			#		calcPos at new time y / cmd open --> halt timer ( newState y )
			$move = 'on';
			$drivetime = $arg1;
			if ( $drivetime == 0 ) {
				$move = 'stop';
			} else {
				$updateState = Dooya_CalcCurrentPos( $hash, $move, $pos, $arg1 );
			}

		}			

		## special case close is at 100 ("markisen")
		if( ( $t1downclose == $t1down100) && ( $t1up100 == 0 ) ) {
			if ( defined( $updateState )) {
				$updateState = min( 100, $updateState );
			}
			$newState = min( 100, $posRounded );
		}
	}

	### update hash / readings
	Log3($name,3,"Dooya_set: handled command $cmd --> move :$move:  newState :$newState: ");
	if ( defined($updateState)) {
		Log3($name,5,"Dooya_set: handled for drive/udpate:  updateState :$updateState:  drivet :$drivetime: updatet :$updatetime: ");
	} else {
		Log3($name,5,"Dooya_set: handled for drive/udpate:  updateState ::  drivet :$drivetime: updatet :$updatetime: ");
	}
			
	# bulk update should do trigger if virtual mode
	Dooya_UpdateState( $hash, $newState, $move, $updateState, ( $mode eq 'virtual' ) );
	
	### send command
	if ( $mode ne 'virtual' ) {
		if(exists($sendCommands{$move})) {
			$args[0] = $sendCommands{$move};
			Dooya_SendCommand($hash,@args);
		} elsif ( $move eq 'none' ) {
      # do nothing if commmand / move is set to none
		} else {
			Log3($name,1,"Dooya_set: Error - unknown move for sendCommands: $move");
		}
	}	

	### start timer
	if ( $mode eq 'virtual' ) {
		# in virtual mode define drivetime as updatetime only, so no commands will be send
		if ( $updatetime == 0 ) {
			$updatetime = $drivetime;
		}
		$drivetime = 0;
	}
	
	### update time stamp
	Dooya_UpdateStartTime($hash);
	$hash->{runningtime} = 0;
	if($drivetime > 0) {
		$hash->{runningcmd} = 'stop';
		$hash->{runningtime} = $drivetime;
	} elsif($updatetime > 0) {
		$hash->{runningtime} = $updatetime;
	}

	if($hash->{runningtime} > 0) {
		# timer fuer stop starten
		if ( defined( $hash->{runningcmd} )) {
			Log3($name,4,"Dooya_set: $name -> stopping in $hash->{runningtime} sec");
		} else {
			Log3($name,4,"Dooya_set: $name -> update state in $hash->{runningtime} sec");
		}
		my $utime = $hash->{runningtime} ;
		if($utime > $dooya_updateFreq) {
			$utime = $dooya_updateFreq;
		}
		InternalTimer(gettimeofday()+$utime,"Dooya_TimedUpdate",$hash,0);
	} else {
		delete $hash->{runningtime};
		delete $hash->{starttime};
	}

	return undef;
} # end sub Dooya_setFN
######################################################

######################################################
###
### Helper for set routine
###
######################################################

######################################################
sub Dooya_RoundInternal($) {   # Todo: kann das nicht die Round Funktion von FHEM?
	my ($v) = @_;
	return sprintf("%d", ($v + ($dooya_posAccuracy/2)) / $dooya_posAccuracy) * $dooya_posAccuracy;
} # end sub Dooya_RoundInternal

######################################################
sub Dooya_UpdateStartTime($) {
	my ($d) = @_;

	my ($s, $ms) = gettimeofday();

	my $t = $s + ($ms / 1000000); # 10 msec
	my $t1 = 0;
	$t1 = $d->{starttime} if(exists($d->{starttime} ));
	$d->{starttime}  = $t;
	my $dt = sprintf("%.2f", $t - $t1);
	
	return $dt;
} # end sub Dooya_UpdateStartTime

######################################################
sub Dooya_TimedUpdate($) {
	my ($hash) = @_;

	Log3($hash->{NAME},4,"Dooya_TimedUpdate");
	
	# get current infos
	my $pos = ReadingsVal($hash->{NAME},'exact',undef);
	Log3($hash->{NAME},5,"Dooya_TimedUpdate : pos so far : $pos");
	
	my $dt = Dooya_UpdateStartTime($hash);
  my $nowt = gettimeofday();
 
	$pos = Dooya_CalcCurrentPos( $hash, $hash->{move}, $pos, $dt );
#	my $posRounded = Dooya_RoundInternal( $pos );
	
	Log3($hash->{NAME},5,"Dooya_TimedUpdate : delta time : $dt   new rounde pos (rounded): $pos ");
	
	$hash->{runningtime} = $hash->{runningtime} - $dt;
	if ( $hash->{runningtime} <= 0.1) {
		if ( defined( $hash->{runningcmd} ) ) {
			Dooya_SendCommand($hash, $hash->{runningcmd});
		}
		# trigger update from timer
		Dooya_UpdateState( $hash, $hash->{updateState}, 'stop', undef, 1 );
		delete $hash->{starttime};
		delete $hash->{runningtime};
		delete $hash->{runningcmd};
	} else {
		my $utime = $hash->{runningtime} ;
		if($utime > $dooya_updateFreq) {
			$utime = $dooya_updateFreq;
		}
		Dooya_UpdateState( $hash, $pos, $hash->{move}, $hash->{updateState}, 1 );
		if ( defined( $hash->{runningcmd} )) {
			Log3($hash->{NAME},4,"Dooya_TimedUpdate: $hash->{NAME} -> stopping in $hash->{runningtime} sec");
		} else {
			Log3($hash->{NAME},4,"Dooya_TimedUpdate: $hash->{NAME} -> update state in $hash->{runningtime} sec");
		}
    my $nstt = max($nowt+$utime-0.01, gettimeofday()+.1 );
    Log3($hash->{NAME},5,"Dooya_TimedUpdate: $hash->{NAME} -> next time to stop: $nstt");
		InternalTimer($nstt,"Dooya_TimedUpdate",$hash,0);
	}
	
	Log3($hash->{NAME},5,"Dooya_TimedUpdate DONE");
} # end sub Dooya_TimedUpdate

######################################################
#	Dooya_UpdateState( $hash, $newState, $move, $updateState );
sub Dooya_UpdateState($$$$$) {
	my ($hash, $newState, $move, $updateState, $doTrigger) = @_;

  my $addtlPosReading = AttrVal($hash->{NAME},'additionalPosReading',undef);
  if ( defined($addtlPosReading )) {
    $addtlPosReading = undef if ( ( $addtlPosReading eq "" ) or ( $addtlPosReading eq "state" ) or ( $addtlPosReading eq "position" ) or ( $addtlPosReading eq "exact" ) );
  }

	readingsBeginUpdate($hash);

	if(exists($positions{$newState})) {
		readingsBulkUpdate($hash,"state",$newState);
		$hash->{STATE} = $newState;

		readingsBulkUpdate($hash,"position",$positions{$newState});
		$hash->{position} = $positions{$newState};
   
    readingsBulkUpdate($hash,$addtlPosReading,$positions{$newState}) if ( defined($addtlPosReading) );

  } else {
		my $rounded = Dooya_Runden( $newState );
		my $stateTrans = Dooya_Translate( $rounded );
		readingsBulkUpdate($hash,"state",$stateTrans);
		$hash->{STATE} = $stateTrans;

		readingsBulkUpdate($hash,"position",$rounded);
		$hash->{position} = $rounded;

    readingsBulkUpdate($hash,$addtlPosReading,$rounded) if ( defined($addtlPosReading) );
     

  }

		readingsBulkUpdate($hash,"exact",$newState);
	$hash->{exact} = $newState;

	if ( defined( $updateState ) ) {
		$hash->{updateState} = $updateState;
	} else {
		delete $hash->{updateState};
	}
	$hash->{move} = $move;
	
	readingsEndUpdate($hash,$doTrigger);
} # end sub Dooya_UpdateState

######################################################
# Return timingvalues from attr and after correction
sub Dooya_getTimingValues($) {
	my ($hash) = @_;

	my $name = $hash->{NAME};

	my $t1down100 = AttrVal($name,'drive-down-time-to-100',undef);
	my $t1downclose = AttrVal($name,'drive-down-time-to-close',undef);
	my $t1upopen = AttrVal($name,'drive-up-time-to-open',undef);
	my $t1up100 =  AttrVal($name,'drive-up-time-to-100',undef);

  return (undef, undef, undef, undef) if(!defined($t1downclose) || !defined($t1down100) || !defined($t1upopen) || !defined($t1up100));

  if ( ( $t1downclose < 0 ) || ( $t1down100 < 0 ) || ( $t1upopen < 0 ) || ( $t1up100 < 0 ) ) {
    Log3($name,1,"Dooya_getTimingValues: $name time values need to be positive values");
    return (undef, undef, undef, undef);
  }

  if ( $t1downclose < $t1down100 ) {
    Log3($name,1,"Dooya_getTimingValues: $name close time needs to be higher or equal than time to pos100");
    return (undef, undef, undef, undef);
  } elsif ( $t1downclose == $t1down100 ) {
    $t1up100 = 0;
  }

  if ( $t1upopen <= $t1up100 ) {
    Log3($name,1,"Dooya_getTimingValues: $name open time needs to be higher or equal than time to pos100");
    return (undef, undef, undef, undef);
  }

  if ( $t1upopen < 1 ) {
    Log3($name,1,"Dooya_getTimingValues: $name time to open needs to be at least 1 second");
    return (undef, undef, undef, undef);
  }

  if ( $t1downclose < 1 ) {
    Log3($name,1,"Dooya_getTimingValues: $name time to close needs to be at least 1 second");
    return (undef, undef, undef, undef);
  }

  return ($t1down100, $t1downclose, $t1upopen, $t1up100);
}

######################################################
# call with hash, translated state
sub Dooya_CalcCurrentPos($$$$) {
	my ($hash, $move, $pos, $dt) = @_;
	my $name = $hash->{NAME};
	my $newPos = $pos;
	
	# Attributes for calculation
  my ($t1down100, $t1downclose, $t1upopen, $t1up100) = Dooya_getTimingValues($hash);

	if(defined($t1down100) && defined($t1downclose) && defined($t1up100) && defined($t1upopen)) {
		if( ( $t1downclose == $t1down100) && ( $t1up100 == 0 ) ) {
			$pos = min( 100, $pos );
			if($move eq 'on') {
				$newPos = min( 100, $pos );
				if ( $pos < 100 ) {
					# calc remaining time to 100%
					my $remTime = ( 100 - $pos ) * $t1down100 / 100;
					if ( $remTime > $dt ) {
						$newPos = $pos + ( $dt * 100 / $t1down100 );
					}
				}

			} elsif($move eq 'off') {
				$newPos = max( 0, $pos );
				if ( $pos > 0 ) {
					$newPos = $dt * 100 / ( $t1upopen );
					$newPos = max( 0, ($pos - $newPos) );
				}
			} else {
				Log3($name,1,"Dooya_CalcCurrentPos: $name move wrong $move");
			}			
		} else {
			if($move eq 'on') {
				if ( $pos >= 100 ) {
					$newPos = $dt * 100 / ( $t1downclose - $t1down100 );
					$newPos = min( 200, $pos + $newPos );
				} else {
					# calc remaining time to 100%
					my $remTime = ( 100 - $pos ) * $t1down100 / 100;
					if ( $remTime > $dt ) {
						$newPos = $pos + ( $dt * 100 / $t1down100 );
					} else {
						$dt = $dt - $remTime;
						$newPos = 100 + ( $dt * 100 / ( $t1downclose - $t1down100 ) );
					}
				}

			} elsif($move eq 'off') {

				if ( $pos <= 100 ) {
					$newPos = $dt * 100 / ( $t1upopen - $t1up100 );
					$newPos = max( 0, $pos - $newPos );
				} else {
					# calc remaining time to 100%
					my $remTime = ( $pos - 100 ) * $t1up100 / 100;
					if ( $remTime > $dt ) {
						$newPos = $pos - ( $dt * 100 / $t1up100 );
					} else {
						$dt = $dt - $remTime;
						$newPos = 100 - ( $dt * 100 / ( $t1upopen - $t1up100 ) );
					}
				}
			} else {
				Log3($name,1,"Dooya_CalcCurrentPos: $name move wrong $move");
			}			
		}
	} else {
		### no timings set so just assume it is always moving
		$newPos = $positions{'moving'};
	}
	
	return $newPos;
}

######################################################
######################################################
######################################################

1;


=pod
=item summary    Supports rf shutters from dooya
=item summary_DE Unterst&uumltzt dooya Funkrolladen
=begin html

<a name="Dooya"></a>
<h3>Dooya protocol</h3>
<ul>
  The Dooya protocol is used by a wide range of devices,
  which are either senders or receivers/actuators.
  The RECIVING and SENDING of Dooya commands is implemented in the SIGNALduino, so this module currently supports 
  devices like blinds and shutters. The Dooya protocol is used from a lot of different shutter companies in Germanyr. Examples are Rohrmotor24 or Nobily.
  <br><br>  


  <pre>
  <code>4: sduino/msg READ: MU;P0=4717;P1=-1577;P2=284;P3=-786;P4=649;P5=-423;D=01232345[......]445232;CP=2;</code> 
  <code>4: sduino: Fingerprint for MU Protocol id 16 -> Dooya shutter matches, trying to demodulate</code>  
  <code>4: sduino: decoded matched MU Protocol id 16 dmsg u16#370658E133 length 40</code>  
  <code>4: SIGNALduino_unknown Protocol: 16</code> 
  <code>4: SIGNALduino_unknown converted to bits: 0011011100000110010110001110000100110011</code>  
  <code>4: SIGNALduino_unknown / shutter Dooya 0011011100000110010110001110000100110011 received</code>  
  <code>4: 00110111000001100101100 1110 0001 0011 0011</code>  
  <code>4: SIGNALduino_unknown found shutter from Dooya. id=3606104, remotetype=14,  channel=1, direction=down, all_shutters=false</code>  
  </pre>

  
   <br> a <a href="#SIGNALduino">SIGNALduino</a> device (must be defined first)  <br>
 <br>
 <br>

   
  <a name="Dooyadefine"></a>
   <br>
  <b>Define</b>
   <br>
  <ul>
    <code>define &lt;name&gt; Dooya &lt;id&gt;_&lt;channel&gt; </code>
  <br>
 <br>
   The id is a 28-digit binar code, that uniquely identifies a single remote control.
   <br>
   Pairing is done by setting the shutter in programming mode, either by disconnecting/reconnecting the power,
   and by pressing the program button on an already associated remote.
   <br>
   Once the shutter is in programming mode, send the "prog" command from within FHEM to complete the pairing.
   The shutter will peep shortly to indicate completion.
   <br>
   You are now able to control this blind from FHEM, the receiver thinks it is just another remote control or the real exist remote. 
   For the shutter it´s the same.

   <ul>
   <li><code>&lt;id&gt;</code> is a 28 digit binar number that uniquely identifies FHEM as a new remote control.
   <br>You can use a different one for each device definition, and group them using a structure. You can use the same ID for a couple of shutters
   and you can give every one an other channel. (0 to 15, 0 ist the MASTER and conrols all other channels.)
   If you set one of them, you need to pick the same address as an existing remote. You can create the Device with autocreate with a real remote or manuel without remote control.</li>
   </ul>
   <br>

    Examples:
    <ul>
	  <code>define Rollo_Master Dooya 0011011100000110010110001110_0</code><br> Rollo_Master channel 0 controls all shutters (channel 1 - 15) with the same ID, in this case Rollo_1 and Rollo_2 <br>
	  <br>
      <code>define Rollo_1 Dooya 0011011100000110010110001110_1</code><br> Rollo_1 channel 1<br>
      <code>define Rollo_2 Dooya 0011011100000110010110101110_2</code><br> Rollo_2 channel 2<br>
    </ul>
  </ul>
  <br>

  <a name="Dooyaset"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;time&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    stop
    pos value (0..100) # see note
    prog  # Special, see note
    </pre>
    Examples:
    <ul>
      <code>set rollo_1 on</code><br>
      <code>set rollo_1 on,sleep 1,rollo_2 on,sleep 1,rollo_3 on</code><br>
      <code>set rollo_1 off</code><br>
      <code>set rollo_1 pos 50</code><br>
    </ul>
    <br>
    Notes:
    <ul>
      <li>prog is a special command used to pair the receiver to FHEM:
      Set the receiver in programming mode and send the "prog" command from FHEM to finish pairing.<br>
      The shutter will peep shortly to indicate success.
      </li>
      <li>pos value<br>
		
			The position is variying between 0 completely open and 100 for covering the full window.
			The position must be between 0 and 100 and the appropriate
			attributes drive-down-time-to-100, drive-down-time-to-close,
			drive-up-time-to-100 and drive-up-time-to-open must be set.<br>
	  </li>
	</ul>

		The position reading distinuishes between multiple cases
    <ul>
      <li>Without timing values set only generic values are used for status and position: <pre>open, closed, moving</pre> are used
      </li>
	  <li>With timing values set but drive-down-time-to-close equal to drive-down-time-to-100 and drive-up-time-to-100 equal 0 
			the device is considered to only vary between 0 and 100 (100 being completely closed)
      </li>
	  <li>With full timing values set the device is considerd a window shutter (Rolladen) with a difference between 
			covering the full window (position 100) and being completely closed (position 200)
      </li>
	</ul>

  </ul>
  <br>

  <b>Get</b> 
  <ul>N/A</ul><br>

  <a name="Dooyaattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        Set the IO or physical device which should be used for sending signals
        for this "logical" device. It must be the SIGNALduino.<br>
        Note: The IODev has to be set, otherwise no commands will be sent!<br>
    </li><br>

  <a name="channel"></a>
    <li>channel<br>
        Set the channel of the remote. You can use 0 (MASTER) to 15.<br>
        Note: The MASTER conrols all remotes with the same ID!!!<br>
    </li><br>
        
          <a name="SignalRepeats"></a>
    <li>SignalRepeats<br>
        Set the repeats for sending signal. You can use 5, 10, 15 and 20.
    </li><br>
        
    <a name="additionalPosReading"></a>
    <li>additionalPosReading<br>
        Position of the shutter will be stored in the reading <code>pos</code> as numeric value. 
        Additionally this attribute might specify a name for an additional reading to be updated with the same value than the pos.
	</li><br>




    <a name="eventMap"></a>
    <li>eventMap<br>
        Replace event names and set arguments. The value of this attribute
        consists of a list of space separated values, each value is a colon
        separated pair. The first part specifies the "old" value, the second
        the new/desired value. If the first character is slash(/) or comma(,)
        then split not by space but by this character, enabling to embed spaces.
        Examples:
        <ul><code>
        attr store eventMap on:open off:closed<br>
        attr store eventMap /on-for-timer 10:open/off:closed/<br>
        set store open
        </code>
        </ul>
    </li>
    <br>

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

  <a name="Dooyaevents"></a>
  <b>Generated events:</b>
  <ul>
     From a Dooya device you can receive one of the following events.
     <li>on</li>
     <li>off</li>
     <li>stop</li>
      Which event is sent is device dependent and can sometimes be configured on
     the device.
  </ul>
</ul>



=end html
=cut

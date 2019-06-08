# $Id$
#
# Siro module for FHEM
# Thanks for templates/coding from SIGNALduino team and Jarnsen_darkmission_ralf9
#
# Needs SIGNALduino.
# Published under GNU GPL License, v2
# History:
# 30.05.19 Version 1.0 innitial comit
################################################################################################################
# Todo's:
# -
# -
###############################################################################################################

package main;

use strict;
use warnings;
my $version = "1.1";


sub Siro_Initialize($) {
    my ($hash) = @_;

    $hash->{SetFn}      = "FHEM::Siro::Set";
    $hash->{NotifyFn}   = "FHEM::Siro::Notify";
    $hash->{ShutdownFn} = "FHEM::Siro::Shutdown";
	$hash->{FW_deviceOverview} = 1;
	$hash->{FW_detailFn} = "FHEM::Siro::fhemwebFn";
    $hash->{DefFn}    = "FHEM::Siro::Define";
    $hash->{UndefFn}  = "FHEM::Siro::Undef";
    $hash->{DeleteFn} = "FHEM::Siro::Delete";
    $hash->{ParseFn}  = "FHEM::Siro::Parse";
    $hash->{AttrFn}   = "FHEM::Siro::Attr";
    $hash->{Match}    = "^P72#[A-Fa-f0-9]+";
	$hash->{AsyncOutput} = "FHEM::Siro::AsyncOutput";
    $hash->{AttrList} =
        " IODev"
      . " disable:0,1"
      . " SIRO_signalRepeats:1,2,3,4,5,6,7,8,9"
	  . " SIRO_inversPosition:0,1"
	  . " SIRO_Battery_low"
	  . " SIRO_downLimit:slider,0,1,100"
      . " SIRO_signalLongStopRepeats:10,15,20,40,45,50"
      . " $readingFnAttributes"
	  . " SIRO_send_channel:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
	  
	  
	  
	  . " SIRO_send_id"
      . " SIRO_time_to_open"
      . " SIRO_time_to_close"
	  . " SIRO_debug:0,1"
	  . " SIRO_remote_correction:0,0.25,0.5,0.75,1,1.25,1.5,1.75,2,2.5,2.75,3"
	  #oldversion entfernen mit kommender version 
      # . " SIRO_channel:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15" 
      . " SignalRepeats:1,2,3,4,5,6,7,8,9"
      . " SignalLongStopRepeats:10,15,20,40,45,50"
      . " channel_send_mode_1:1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
      . " $readingFnAttributes"
      . " setList"
      . " ignore:0,1"
      . " dummy:1,0"
      . " time_to_open"
      . " time_to_close"
      . " time_down_to_favorite" . " hash"
      . " operation_mode:0,1"
      . " debug_mode:0,1"
      . " down_limit_mode_1:slider,0,1,100"
      . " down_auto_stop:slider,0,1,100"
      . " invers_position:0,1"
      . " prog_fav_sequence";
	  
	  
	  


    $hash->{AutoCreate} = {
        "Siro.*" => {
            ATTR   => "event-min-interval:.*:300 event-on-change-reading:.*",
            FILTER => "%NAME",
            autocreateThreshold => "2:10"
        }
    };

    $hash->{NOTIFYDEV} = "global";
	
	$hash->{helper}{progmode} = "off";   #exexcmd    on
	#$hash->{helper}{exexcmd} = "on"; 
	
	
    FHEM::Siro::LoadHelper($hash) if ($init_done);
}


#################################################################


#### arbeiten mit packages
package FHEM::Siro;

use strict;
use warnings;

use GPUtils qw(GP_Import)
  ;    # wird fuer den Import der FHEM Funktionen aus der fhem.pl ben?tigt


## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(readingsSingleUpdate
		  readingsBeginUpdate
		  readingsEndUpdate
		  readingsBulkUpdate
          defs
          modules
          Log3
          AttrVal
          ReadingsVal
          IsDisabled
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          AssignIoPort
          IOWrite
          ReadingsNum
          CommandAttr
		  attr
		  fhem
		  init_done
		  )

    );
}


my %codes = (
    "55" => "stop",    # Stop the current movement or move to custom position
    "11" => "off",     # Move "up"
    "33" => "on",      # Move "down"
    "CC" => "prog",    # Programming-Mode (Remote-control-key: P2)
);

my %sets = (
    "open"      => "noArg",
    "close"     => "noArg",
    "up"      => "noArg",
    "down"     => "noArg",
    "off"       => "noArg",
    "stop"      => "noArg",
    "on"        => "noArg",
    "fav"       => "noArg",
	"prog"      => "noArg",
	"sequenz"      => "noArg",
    "prog_mode_on"      => "noArg",
    "prog_mode_off" => "noArg",
	"reset_motor_term" => "noArg",
    "pct" => "slider,0,1,100",    # Wird nur bei vorhandenen time_to attributen gesetzt
	"position" => "slider,0,1,100",    # Wird nur bei vorhandenen time_to attributen gesetzt
    "state"                   => "noArg",
    "set_favorite"            => "noArg",
	"del_favorite"            => "only_modul,only_shutter,shutter_and_modul",
    "down_for_timer"          => "textField",
    "up_for_timer"            => "textField"

);

my %sendCommands = (
	"pct"         => "level",
	"level"         => "level",
	"position"         => "level",
    "stop"         => "stop",
	"off"          => "off",
    "on"           => "on",
    "open"         => "off",
    "close"        => "on",
	"up"         => "off",
    "down"        => "on",
    "fav"          => "fav",
    "prog"         => "prog",
	"reset_motor_term"  => "reset_motor_term",
    "up_for_timer" => "upfortimer",
	"down_for_timer" => "downfortimer"
	
);

my %siro_c2b;
# Map commands from web interface to codes used in Siro
foreach my $k ( keys %codes ) {
    $siro_c2b{ $codes{$k} } = $k;
}

######################
sub Attr(@) {
	my ( $cmd, $name, $aName, $aVal ) = @_;
    my $hash = $defs{$name};
    return "\"Siro Attr: \" $name does not exist" if ( !defined($hash) );

	if ( $cmd eq "set" and $init_done == 1) 
	{
	
	
		if ( $aName eq "SIRO_inversPosition" ) 
		{
		my $oldinvers = AttrVal($name,'SIRO_inversPosition','undef');
		Log3( $name,5 , "Siro_attr_oldinvers: $oldinvers ");
		Log3( $name,5 , "Siro_attr_newinvers: $aVal ");
		if ( $aVal ne $oldinvers) 
				{
				my $aktstate = ReadingsVal( $name, 'state', 'undef' );
				$aktstate = 100 - $aktstate;
				readingsSingleUpdate( $hash, "state", $aktstate , 1 );
				readingsSingleUpdate( $hash, "pct", $aktstate , 1 );
				}
	}
	
	Log3( $name,5 , "Siro_attr: $cmd, $name, $aName, $aVal ");
	
	}
	
	Log3( $name,5 , "Siro_attr init done : $init_done");
return;
}
#################################################################
sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    my $u = "Wrong syntax: define <name> Siro id ";
    my $askedchannel;    # Angefragter kanal

    # Fail early and display syntax help
    if ( int(@a) < 3 ) {
        return $u;
    }

    if ( $a[2] =~ m/^[A-Fa-f0-9]{8}$/i ) {
        $hash->{ID} = uc( substr( $a[2], 0, 7 ) );
        $hash->{CHANNEL_RECEIVE} = sprintf( "%d", hex( substr( $a[2], 7, 1 ) ) );
        $askedchannel = sprintf( "%d", hex( substr( $a[2], 7, 1 ) ) );
    }
    else {
        return
"Define $a[0]: wrong address format: specify a 8 char hex value (id=7 chars, channel=1 char) . Example A23B7C51. The last hexchar identifies the channel. -> ID=A23B7C5, Channel=1. ";
    }

    $hash->{Version} = $version;
    my $name = $a[0];
    my $code  = uc( $a[2] );
    my $ncode = 1;

    my $devpointer = $hash->{ID} . $hash->{CHANNEL_RECEIVE};
    $hash->{CODE}{ $ncode++ } = $code;
	$hash->{MODEL} = "LE-serie";
    $modules{Siro}{defptr}{$devpointer} = $hash;
	AssignIoPort($hash);
	
   # CommandAttr( undef,$name . ' devStateIcon {if (ReadingsVal( $name, \'state\', \'undef\' ) =~ m/[a-z]/ ) { return \'programming:edit_settings notAvaible:hue_room_garage runningUp.*:fts_shutter_up runningDown.*:fts_shutter_down\'}else{return \'[0-9]{1,3}:fts_shutter_1w_\'.(int($state/10)*10)}}' )
    #  if ( AttrVal($name,'devStateIcon','none') eq 'none' );

	 	
  
	   CommandAttr( undef,$name . ' devStateIcon {return FHEM::Siro::Siro_icon($name)}' )
      if ( AttrVal($name,'devStateIcon','none') eq 'none' );
	  
	  
    CommandAttr(undef,$name . ' webCmd stop:open:close:fav:pct')
      if ( AttrVal($name,'webCmd','none') eq 'none' );
	
	
    Log3( $name, 5, "Siro_define: angelegtes Device - code -> $code name -> $name hash -> $hash "
    );
}

#################################################################
sub Undef($$) {

    my ( $hash, $name ) = @_;
    delete( $modules{Siro}{defptr}{$hash} );
    return undef;
}

#################################################################
sub Shutdown($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    return;
}

#################################################################
sub LoadHelper($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    return;
}

#################################################################

sub Notify($$) {

    return;
}
#################################################################

sub Delete($$) {
    my ( $hash, $name ) = @_;
    return undef;
}

#################################################################
sub SendCommand($@) {
    my ( $hash, @args ) = @_;
    my $ret = undef;
    my $cmd = $args[0];    # Command as text (on, off, stop, prog)
    my $message;           # IO-Message (full)
    my $chan;              # Channel
    my $binChannel;        # Binary channel
    my $SignalRepeats;     #
    my $name = $hash->{NAME};
    my $binHash;
    my $bin;               # Full binary IO-Message
    my $binCommand;
    my $numberOfArgs = int(@args);
    my $command      = $siro_c2b{$cmd};
    my $io           = $hash->{IODev};    # IO-Device (SIGNALduino)

	#if ( $hash->{helper}{exexcmd} eq "off") # send kommand blockiert / keine ausf?hrung
	if ( defined($hash->{helper}{exexcmd}) and $hash->{helper}{exexcmd} eq "off") # send kommand blockiert / keine ausf?hrung
	{
	Log3( $name, 5,"Siro_sendCommand: ausf?hrung durch helper blockiert ");
	return;
	
	}
	
	 #if ( $hash->{helper}{ignorecmd} eq "on") # send kommand blockiert / keine ausf?hrung
	 if ( defined($hash->{helper}{ignorecmd}) and $hash->{helper}{ignorecmd} eq "on") # send kommand blockiert / keine ausf?hrung
	 {
	 Log3( $name, 5,"Siro_sendCommand: ausführung einmalig blockiert ");
	
	 delete( $hash->{helper}{ignorecmd} );
	 return;
	
	 }

	#Log3( $name, 5,"Siro_sendCommand: args1 - $args[1]");

   if ( defined($args[1]) and $args[1] eq "longstop" || defined $hash->{helper}{progmode} and $hash->{helper}{progmode} eq "on")
		{
			$SignalRepeats = AttrVal( $name, 'SIRO_signalLongStopRepeats', '15' );
		}
    else
		{
			 $SignalRepeats = AttrVal( $name, 'SIRO_signalRepeats', '10' );
		}
		
    $chan = AttrVal( $name, 'SIRO_send_channel', undef );
    if ( !defined($chan) ) 
		{
            $chan = $hash->{CHANNEL_RECEIVE};
        }

    $binChannel = sprintf( "%04b", $chan );

    my $value = $name . " " . join( " ", @args );

	
	my $sendid = AttrVal( $name, 'SIRO_send_id', 'undef' );
	if ( $sendid eq 'undef')
	{
    $binHash = sprintf( "%028b", hex( $hash->{ID} ) );
	}
	else{
	 $binHash = sprintf( "%028b", hex( $sendid ) );
	}
	
	
	
	
    Log3 $io, 5, "Siro_sendCommand: BinHash: = $binHash";

    $binCommand = sprintf( "%08b", hex($command) );
    Log3 $io, 5, "Siro_sendCommand: BinCommand: = $binCommand";

    $bin = $binHash . $binChannel . $binCommand;    # Binary code to send
    Log3 $io, 5, "Siro_sendCommand: Siro set value = $value";

    $message = 'P72#' . $bin . '#R' . $SignalRepeats;

	IOWrite( $hash, 'sendMsg', $message ) if AttrVal( $name, 'SIRO_debug', "0" ) ne "1";
   
    Log3( $name, 5,"Siro_sendCommand: name-$name command-$cmd  channel-$chan bincmd-$binCommand bin-$bin id-$sendid message-$message");
    Log3( $name, 3, "Siro_sendCommand: not sent upround debugmode 1") if AttrVal( $name, 'SIRO_debug', "0" ) eq "1";
    return $ret;
}

#################################################################
sub Parse($$) {
   
    my @args;
    my ( $hash, $msg ) = @_;
    my $doubelmsgtime = 2;  # zeit in sek in der doppelte nachrichten blockiert werden
    my $favcheck = $doubelmsgtime +1;# zeit in der ein zweiter stop kommen muss/darf für fav
    my $testid  = substr( $msg, 4,  8 );
    my $testcmd = substr( $msg, 12, 2 );
    my $timediff;

    my $name = $hash->{NAME};
    return "" if ( IsDisabled($name) );
	
	
	 Log3( $name, 5,"Siro_parse: Incomming msg time -> ".time);
	
	
	
	# if ($hash->{helper}{progmode} eq "on")
	# {
	# Log3( $name, 4, "Siro Parse deactivated cause of programmingmode");
	# return;
	# }
	
	
	# my $lock = 1;
	# if  ($lock eq "1")
	# {
	# Log3( $name, 4, "Siro Parse blocking activated");
	
	# $hash->{helper}{savedcmds}{cmd1} = 'pct';
	# $hash->{helper}{savedcmds}{cmd2} = 10;
	# InternalTimer( (time+2), "FHEM::Siro::Restartset", "$name" );
	# }
	

	

    if ( my $lh = $modules{Siro}{defptr}{$testid} ) {
        my $name = $lh->{NAME};
        Log3 $hash, 5,"Siro_Parse: Incomming msg from IODevice $testid - $name device is defined";
		
		
       # if ( defined($name)&& $testcmd ne "54")# prüfe auf doppele msg falls gerät vorhanden und cmd nicht stop
        if ( defined($name)&& $testcmd ne "54")# pr?fe auf doppele msg falls ger?t vorhanden und cmd nicht stop

		{
            Log3 $lh, 5,"Siro_Parse: Incomming msg $msg from IODevice name/DEF $testid - Hash -> $lh";

            my $testparsetime  = gettimeofday();
            my $lastparse      = $lh->{helper}{lastparse};
            my @lastparsearray = split( / /, $lastparse );
            if ( !defined( $lastparsearray[1] ) ) { $lastparsearray[1] = 0 }
            if ( !defined( $lastparsearray[0] ) ) { $lastparsearray[0] = "" }
            $timediff = $testparsetime - $lastparsearray[1];
            my $abort = "false";

            Log3 $lh, 5, "Siro_Parse: test doublemsg ";
            Log3 $lh, 5, "Siro_Parse: lastparsearray[0] -> $lastparsearray[0] ";
            Log3 $lh, 5, "Siro_Parse: lastparsearray[1] -> $lastparsearray[1] ";
            Log3 $lh, 5, "Siro_Parse: testparsetime -> $testparsetime ";
            Log3 $lh, 5, "Siro_Parse: timediff -> $timediff ";

            if ( $msg eq $lastparsearray[0] ) {

                if ( $timediff < $doubelmsgtime ) {

                    $abort = "true";
                }
            }
            $lh->{helper}{lastparse} = "$msg $testparsetime";
            if ( $abort eq "true" ) {
                Log3 $lh, 4, "Siro_Parse: aborted , doublemsg ";
                return $name;
            }

            Log3 $lh, 4, "Siro_Parse: not aborted , no doublemsg ";
        }

        my ( undef, $rawData ) = split( "#", $msg );
        my $hlen    = length($rawData);
        my $blen    = $hlen * 4;
        my $bitData = unpack( "B$blen", pack( "H$hlen", $rawData ) );

        Log3 $hash, 5, "Siro_Parse: msg = $rawData length: $msg";
        Log3 $hash, 5, "Siro_Parse: rawData = $rawData length: $hlen";
        Log3 $hash, 5, "Siro_Parse: converted to bits: $bitData";

        my $id = substr( $rawData, 0, 7 );    # The first 7 hexcodes are the ID
        my $BitChannel = substr( $bitData, 28, 4 );    # Not needed atm
        my $channel = sprintf( "%d", hex( substr( $rawData, 7, 1 ) ) );# The last hexcode-char defines the channel
        my $channelhex = substr( $rawData, 7, 1 );    # tmp
        my $cmd = sprintf( "%d", hex( substr( $rawData, 8, 1 ) ) );
        my $newstate   = $codes{ $cmd . $cmd };       # Set new state
        my $deviceCode = $id. $channelhex;#Tmp change channel -> channelhex. The device-code is a combination of id and channel

      
        Log3 $hash, 5, "Siro_Parse: device ID: $id";
        Log3 $hash, 5, "Siro_Parse: Channel: $channel";
        Log3 $hash, 5, "Siro_Parse: Cmd: $cmd  Newstate: $newstate";
        Log3 $hash, 5, "Siro_Parse: deviceCode: $deviceCode";

        #if ( defined($name)&& $testcmd eq "54" )#prüfe auf doppele msg falls gerät vorhanden und cmd stop
        if ( defined($name)&& $testcmd eq "54" )#pr?fe auf doppele msg falls ger?t vorhanden und cmd stop
		{
            # Log3 $lh, 5, "Siro_Parse: prüfung auf douplestop ";
            my $testparsetime      = gettimeofday();
            my $lastparsestop      = 0;
			$lastparsestop = $lh->{helper}{lastparse_stop} if defined $lh->{helper}{lastparse_stop};
            my $parseaborted       = $lh->{helper}{parse_aborted};
            my @lastparsestoparray = split( / /, $lastparsestop );
            my $timediff           = $testparsetime - $lastparsestoparray[1];
            my $abort              = "false";
            $parseaborted = 0 if ( !defined($parseaborted) );

            Log3 $lh, 5, "Siro_Parse: test doublestop ";
            Log3 $lh, 5,
              "Siro_Parse: lastparsearray[0] -> $lastparsestoparray[0] ";
            Log3 $lh, 5,
              "Siro_Parse: lastparsearray[1] -> $lastparsestoparray[1] ";
            Log3 $lh, 5, "Siro_Parse: testparsetime -> $testparsetime ";
            Log3 $lh, 5, "Siro_Parse: timediff -> $timediff ";
            Log3 $lh, 5, "Siro_Parse: parseaborted -> $parseaborted ";

            if ( $newstate eq $lastparsestoparray[0] ) {

                if ( $timediff < 3 ) {
                    $abort = "true";
                    $parseaborted++;
                }

            }
            if ( $abort eq "true" && $parseaborted < 8 ) {
                $lh->{helper}{parse_aborted} = $parseaborted;
                Log3 $lh, 5, "Siro_Parse: aborted , doublestop ";
                return $name;
            }

            $lh->{helper}{lastparse_stop} = "$newstate $testparsetime";

            if ( $parseaborted >= 7 ) {
                $parseaborted                 = 0;
                $lh->{helper}{parse_aborted}  = $parseaborted;
                $testparsetime                = gettimeofday();
                $lh->{helper}{lastparse_stop} = "$newstate $testparsetime";
                if ( $newstate eq "stop" ) {
                    Log3 $lh, 3,
                      "Siro_Parse: double_msg signal_favoritenanfahrt erkannt ";
                    $newstate = "fav";
                    $args[0] = "fav";
                }
            }
        }

		Log3( $name, 5, "Siro Parse Befehl:  $newstate");
		
		
	if ($lh->{helper}{progmode} eq "on")
	{
	Log3( $name, 4, "Siro Parse deactivated cause off programmingmode");
	return;
	}
	
	
	#my $lock = 1;
	#if  ($lock eq "1")
	#{
	#Log3( $name, 4, "Siro Parse blocking activated");
	
	#$lh->{helper}{savedcmds}{cmd1} = 'pct';
	#$lh->{helper}{savedcmds}{cmd2} = 10;
	#InternalTimer( (time+3), "FHEM::Siro::Restartset", "$name" );
	
	#Log3( $name, 4, "Siro Parse blocking cmd: set $name pct 10");
	#fhem("set $name pct 10");
	
	
	#}
		
		
		
		
		
		
		
        if ( defined($name) ) {#device vorhanden
            my $parseaborted = 0;
            $lh->{helper}{parse_aborted} = $parseaborted;
            Log3 $lh, 5, "Siro_Parse:  $name $newstate";
			my $defchannnel =  $lh->{CHANNEL_RECEIVE};
			my $atrrchannel = AttrVal( $name, 'SIRO_send_channel', $defchannnel );
			
			Log3 $lh, 5, "Siro_Parse: defchannnel - $defchannnel ";
			Log3 $lh, 5, "Siro_Parse: atrrchannel - $atrrchannel ";
			
			if ($defchannnel eq $atrrchannel)
			{
			$lh->{helper}{remotecmd} = "on"; #verhindert das senden von signalen nur wenn nicht auf anderem kanal gesendet wird
			}
			
			Log3 $lh, 5, "Siro_Parse: hash->{helper}{remotecmd} - ".$lh->{helper}{remotecmd};
			Log3( $name, 3, "Siro-Parse ($name) : Signal FB emfangen -  $newstate");	
            Set( $lh, $name, $newstate );
			
			
			#$lh->{helper}{savedcmds}{cmd1} = 'pct';
			#$lh->{helper}{savedcmds}{cmd2} = 10;
			#InternalTimer( (time), "FHEM::Siro::Restartset", "$name" );
			
			
            return $name;
        }
    }
	
	
	
    else 
	{ # device nicht vorhanden 
        my ( undef, $rawData ) = split( "#", $msg );
        my $hlen    = length($rawData);
        my $blen    = $hlen * 4;
        my $bitData = unpack( "B$blen", pack( "H$hlen", $rawData ) );

        Log3 $hash, 5, "Siro_Parse: msg = $rawData length: $msg";
        Log3 $hash, 5, "Siro_Parse: rawData = $rawData length: $hlen";
        Log3 $hash, 5, "Siro_Parse: converted to bits: $bitData";

        my $id = substr( $rawData, 0, 7 );    # The first 7 hexcodes are the ID
        my $BitChannel = substr( $bitData, 28, 4 );    # Not needed atm
        my $channel = sprintf( "%d", hex( substr( $rawData, 7, 1 ) ) );    # The last hexcode-char defines the channel
        my $channelhex = substr( $rawData, 7, 1 );    # tmp
        my $cmd = sprintf( "%d", hex( substr( $rawData, 8, 1 ) ) );
        my $newstate   = $codes{ $cmd . $cmd };       # Set new state
        my $deviceCode = $id. $channelhex; # Tmp change channel -> channelhex. The device-code is a combination of id and channel

        Log3 $hash, 5, "Siro_Parse: device ID: $id";
        Log3 $hash, 5, "Siro_Parse: Channel: $channel";
        Log3 $hash, 5, "Siro_Parse: Cmd: $cmd  Newstate: $newstate";
        Log3 $hash, 5, "Siro_Parse: deviceCode: $deviceCode";

        Log3 $hash, 2, "Siro unknown device $deviceCode, please define it";
        return "UNDEFINED Siro_$deviceCode Siro $deviceCode";
    }
}

#############################################################

# Call with hash, name, virtual/send, set-args
sub Set($@) {
    my $testtimestart = gettimeofday();
    my $debug;
    my ( $hash, $name, @args ) = @_;
	my $cmd           = $args[0]; # eingehendes set
	my $zielposition  = $args[1]; # eingehendes set position
	Log3( $name, 5, "Siro-Set: eingehendes Kommando $cmd") if $cmd ne "?";
	### check for old version 
	if (ReadingsVal( $name, 'last_reset_os', 'undef' ) ne 'undef' && $cmd ne "?")
	{
	Log3( $name,0 , "Das Siromodul wurde geaendert und die einstellungen sind nicht mehr Kompatibel. Bitte das Sirodevice \"$name\" kontrollieren .");
	}
	##################
	
	my $actiontime = time; # zeit dieses Aufrufes
	my $lastactiontime = ReadingsVal( $name, 'ActionTime', $actiontime ); # Zeit des letzten Aufrufes
	my $betweentime = $actiontime-$lastactiontime; # Zeit zwischen aktuellem und letztem Aufruf
	my $downtime = AttrVal( $name, 'SIRO_time_to_close','undef' ); # fahrdauer runter
	my $uptime = AttrVal( $name, 'SIRO_time_to_open','undef' ); # fahrdauer hoch
	my $correction = AttrVal( $name, 'SIRO_remote_correction',0 ); # zeitkorrektur fernbedienung
	my $down1time ="undef"; # fahrzeit 1 prozent
	my $up1time ="undef"; # fahrzeit 1 prozent
	my $drivingtime; # fahrzeit bei positionsanfahrt
	my $aktendaction = ReadingsVal( $name, 'aktEndAction', '0' ); #endzeit laufende avtion
	my $akttimeaction = ReadingsVal( $name, 'aktTimeAction', '0' ); #dauer einer laufenden aktion
	my $aktrunningaction = ReadingsVal( $name, 'aktRunningAction', '' ); #typ einer laufenden aktion
	my $position = ReadingsVal( $name, 'pct', '' ); #position pct bis zum ende einer aktion
	my $state = ReadingsVal( $name, 'state', 'undef' ); #aktuelle aktion ( runningDown/runningUp )
	my $drivedpercents; # beinhaltet gefahrene prozent bei aktionswechsel
	my $newposition ; # beinhaltet neue positin bei aktionswechsel
	my $favposition = ReadingsVal( $name, 'Favorite-Position', 'nA' ); #gespeicherte Favoritenposition
	my $invers = 1; #invertiert position
	my $oldcmdfrom = ReadingsVal( $name, 'ActionTrigger', 'fhem' );# ActionTrigger der letzten aktion
	if ($downtime ne "undef" && $uptime ne "undef")
			{
			$down1time = $downtime/100;
			$up1time = $uptime/100;
			}
	
    return "" if ( IsDisabled($name) );
	
	$hash->{helper}{progmode} = "off" if !defined $hash->{helper}{progmode};
	
	
	
	# versionschange
	#changeconfig
	
	if ( $cmd eq 'changeconfig'){
		versionchange( $name );
		return;
		}	
	
	# pruefe auf unbekannte sets
	
	 if ( $cmd =~ m/^exec.*/ )# empfangene sequenz aus programmiermode 
	 {
	 $args[1] = $cmd;
	 $cmd = "sequenz";
	 }
	
	 if ( !exists( $sets{$cmd} ) ) {
        my @cList;
        my $atts = AttrVal( $name, 'setList', "" );
        my %setlist = split( "[: ][ ]*", $atts );
        foreach my $k ( sort keys %sets ) {
            my $opts = undef;
            $opts = $sets{$k};
            $opts = $setlist{$k} if ( exists( $setlist{$k} ) );
            if ( defined($opts) ) {
                push( @cList, $k . ':' . $opts );
            }
            else {
                push( @cList, $k );
            }
        }    # end foreach
        return "Unknown argument $cmd, choose one of " . join( " ", @cList );
    }

####################################
# programmiermodus
####################################
	
	#if ( $hash->{helper}{progmode} eq "on" && $cmd eq "sequenz") # sequenz ausführen 
	if ( defined $hash->{helper}{progmode} and $hash->{helper}{progmode} eq "on" && $cmd eq "sequenz") # sequenz ausf?hren 
 
	{
	Log3( $name, 5, "Siro-Programmiermodus: Sequenz gefunden :$args[1]");
	my @seq = split(/,/, $args[1]);
	
	shift @seq;
	my $exectime = time;
	foreach my $seqpart (@seq) 
			{
			#$actiontime
			$exectime = $exectime+2;
			my $execcmd = $seqpart;
			Log3( $name, 5, "Siro-Programmiermodus: Sequenz - $exectime - $execcmd");
			InternalTimer( $exectime, "FHEM::Siro::Prog", $name." ".$execcmd );	
			}
	return;
	}
	
	if ($cmd eq "prog_mode_on" && $hash->{helper}{progmode} ne "on")
	

	{
	readingsSingleUpdate( $hash, "state",  'programming', 1 ); 
	$hash->{helper}{progmode} = "on";
	}
	
	if ($cmd eq "prog_mode_off"  && $hash->{helper}{progmode} eq "on")
	{
		readingsSingleUpdate( $hash, "state",  $position, 1 ); 
		#delete( $hash->{helper}{progmode} );
		$hash->{helper}{progmode} = "off";
	}
	
	if ($hash->{helper}{progmode} eq "on")
	{
		SendCommand( $hash, $sendCommands{$cmd} );
		delete( $hash->{Signalduino_RAWMSG} );
		delete( $hash->{Signalduino_MSGCNT} );
		delete( $hash->{Signalduino_RSSI} );
		delete( $hash->{Signalduino_TIME} );
		Log3( $name, 5, "Siro-Programmiermodus: Parse deaktiviert");
		return;
	}
	
####################################

	if ($state eq "programming") # keine Befehlsausf?hrung w?hrend einer programmierung
	{
	Log3( $name, 1, "Siro-Programmiermodus: Befehl nicht moeglich , Device ist im Programmiermodus");
	return;
	}
	
	# setze actiontime und lastactiontime
	# umbauen zu bulk update
	RemoveInternalTimer($name); #alle vorhandenen timer l?schen
	#delete( $hash->{helper}{exexcmd} ); # on/off off blockiert befehlsausf?hrung / l?schen vor jedem durchgang
	$hash->{helper}{exexcmd}="on";  #reset ignore send comand states
	$hash->{helper}{ignorecmd} = "off" ; #reset ignore send comand states
	#setze helper neu wenn signal von fb kommt
	#if ($hash->{helper}{remotecmd} eq "on")
	
	my $aktcmdfrom ="fhem";
	if ( defined($hash->{helper}{remotecmd}) and $hash->{helper}{remotecmd} eq "on")
	{
	$hash->{helper}{exexcmd} = "off" ;
	$aktcmdfrom = "remote";
	}
	delete( $hash->{helper}{remotecmd} );
	
	readingsBeginUpdate($hash);
	readingsBulkUpdate( $hash, "ActionTime", $actiontime, 0 );
	readingsBulkUpdate( $hash, "ActionTrigger", $aktcmdfrom, 1 );
	readingsBulkUpdate( $hash, "LastActionTime", $lastactiontime, 0 );
	readingsBulkUpdate( $hash, "BetweentActionTime", $betweentime, 0 );
	readingsEndUpdate($hash, 1);
	
	
	# befehl aus %sendCommands ermitteln
    my $comand = $sendCommands{$cmd}; # auzuf?hrender befehl
	Log3( $name, 5, "Siro-Set: ermittelter Befehl: $comand " ); 

	###############################
	# limit testen , falls limit wird on zu level limit
	my $downlimit = AttrVal( $name, 'SIRO_downLimit','undef' ) ;
	if ($downlimit ne "undef"  && ($comand eq 'on' || $comand eq 'level') && $hash->{helper}{exexcmd} ne "off")
	# nur wenn befehl nicht von fb kommt
		{
			if (!defined $zielposition){$zielposition = 100}
			if ( $position < $downlimit )
			{
				$comand = 'level';
				$zielposition = $downlimit;
			}
			my $sendchan = AttrVal( $name, 'SIRO_send_channel', 'undef' );
			if ( $sendchan ne $hash->{CHANNEL_RECEIVE} && $position >= $downlimit )
			{
				return;
			}
		}
##################
	if ($downlimit ne "undef"  && ($comand eq 'on' || $comand eq 'level') && $hash->{helper}{exexcmd} eq "off")
	# nur wenn befehl  von fb kommt
		{
		if ( $position < $downlimit )
			{
			#delete( $hash->{helper}{exexcmd} );
			$hash->{helper}{exexcmd}="on";
			$hash->{helper}{ignorecmd} ="on";
			$comand = 'level';
			$zielposition = $downlimit;
			}
		}
############################
	# set reset_motor_term   reset_motor_term
	if ($comand eq "reset_motor_term")
		{
		readingsSingleUpdate( $hash, "motor-term", "0", 1 ) ;
		readingsSingleUpdate( $hash, "batteryState", "unknown", 1 ) ;
		readingsSingleUpdate( $hash, "motor-term-reset",  time, 1 ); 
		return;
		}
		
	# pruefe auf laufende aktion nur bei definierten laufzeiten
	# wenn vorhanden neuberechnung aller readings 
	if ($aktendaction > time && ($downtime ne "undef" || $uptime ne "undef"))
		{
		Log3( $name, 5, "Siro-Set: laufende aktion gefunden - abbruch");
		Log3( $name, 5, "Siro-Set: laufende aktion -");
		
		#aktTimeAction  - dauer der laufenden aktion - in variable $akttimeaction
		#aktEndAction geplantes aktionsende - in variabel $aktendaction
		#$actiontime aktuelle zeit
		#$aktrunningaction - typ der laufenden aktion
		#$position -position bei actionsbeginn
		
		my $pastaction = $akttimeaction - ($aktendaction  - $actiontime);
		Log3( $name, 5, "Siro-Set: unterbrochene Aktion $state lief $pastaction ");
		##################korrektur zeitdifferenz fb/fhem
		if ($oldcmdfrom eq "remote" and  $aktcmdfrom eq "fhem")
		{
		$pastaction = $pastaction + $correction ;
		Log3( $name, 5, "Siro-Set: unterbrochene Aktion wurde von $oldcmdfrom gestartet und von $aktcmdfrom unterbrochen, starte Korrektur ");
		Log3( $name, 5, "Siro-Set: unterbrochene Aktion $state lief $pastaction mit Korrektur");
		Log3( $name, 5, "Siro-Set: Korrektur um $correction sekunden");
		}
		
		if ($oldcmdfrom eq "fhem" and  $aktcmdfrom eq "remote")
		{
		$pastaction = $pastaction - $correction ;
		Log3( $name, 5, "Siro-Set: unterbrochene Aktion wurde von $oldcmdfrom gestartet und von $aktcmdfrom unterbrochen, starte Korrektur ");
		Log3( $name, 5, "Siro-Set: unterbrochene Aktion $state lief $pastaction mit Korrektur");
		Log3( $name, 5, "Siro-Set: Korrektur um $correction sekunden");
		}
		################
		
		
		
		Log3( $name, 5, "Siro-Set: Aktionsbeginn bei $position ");

		if ($state eq "runningDown" || $state eq "runningDownfortimer")
			{
			 $drivedpercents = $pastaction/$down1time;
			 $drivedpercents = ( int( $drivedpercents * 10 ) / 10 );
			 Log3( $name, 5, "Siro-Set: Positionsveraenderung um $drivedpercents Prozent nach unten ");
			 
			 
			 if (AttrVal( $name, 'SIRO_inversPosition',0 ) eq "1")
			 {
			 $newposition = int ($position-$drivedpercents);
			 }
			 else{
			 $newposition = int ($position+$drivedpercents);
			 }
			}
		
		if ($state eq "runningUp" || $state eq "runningUpfortimer")
			{
			 $drivedpercents = $pastaction/$up1time;
			 $drivedpercents = ( int( $drivedpercents * 10 ) / 10 );
			 Log3( $name, 5, "Siro-Set: Positionsveraenderung um $drivedpercents Prozent nach oben ");
			 
			  if (AttrVal( $name, 'SIRO_inversPosition',0 ) eq "1")
			 {
			 $newposition = int ($position+$drivedpercents);
			 }
			 else{
			 $newposition = int ($position-$drivedpercents);
			 }
			}
		
		Log3( $name, 5, "Siro-Set: neue Position - $newposition ");

		my $operationtime = ReadingsNum( $name, 'motor-term', 0 );
		my $newoperationtime = $operationtime + $pastaction;
	
		readingsBeginUpdate($hash);
		readingsBulkUpdate( $hash, "state", $newposition ) ;
		readingsBulkUpdate( $hash, "pct", $newposition ) ;
		readingsBulkUpdate( $hash, "position", $newposition) ;
		readingsBulkUpdate( $hash, "aktRunningAction", "noAction" ) ;
		readingsBulkUpdate( $hash, "aktEndAction", 0 ) ;
		readingsBulkUpdate( $hash, "aktTimeAction", 0 ) ;
		readingsBulkUpdate( $hash, "aktActionFinish", 0 ) ;
		readingsBulkUpdate( $hash, "motor-term", $newoperationtime, 1 ) ;
		readingsEndUpdate($hash, 1);
		
			if ($comand ne "stop") #wenn anders kommando als stop befehl zwischenspeichern und per internal timer neu aufrufen , vorher fahrt stoppen per befehl. Stopbefehl l?uft durch wegen notbetrieb ohne timer attribute, gespeicherter befehl wir abgelegt in reading ($cmd) helper/cmd1 und ($zielposition) helper/cmd2. bei aufruf set wird auf vorhandensein gepr?ft.
			{
			SendCommand( $hash, 'stop' );
			Log3( $name, 5, "Siro-Set: Twischenspeichern von Cmd ($cmd) und Position ($zielposition)");
			$hash->{helper}{savedcmds}{cmd1} = $cmd;
			$hash->{helper}{savedcmds}{cmd2} = $zielposition if defined $zielposition;
			InternalTimer( time, "FHEM::Siro::Restartset", "$name" );
			return;
			}
		}

		Log3( $name, 5, "Siro-Set: cmd nach change : $comand");
###############		
#pct 100 und pct 0 auf on oder off mappen
		if ($comand eq "level" and $zielposition eq "100")
		{
		$comand = "on" if AttrVal( $name, 'SIRO_inversPosition',0 ) eq "0";
		$comand = "off" if AttrVal( $name, 'SIRO_inversPosition',0 ) eq "1";
		
		Log3( $name, 4, "Siro-Set: mapping level 100 - on");
		}
		
		
		
		
		if ($comand eq "level" and $zielposition eq "0")
		{
		$comand = "off" if AttrVal( $name, 'SIRO_inversPosition',0 ) eq "0";
		$comand = "on" if AttrVal( $name, 'SIRO_inversPosition',0 ) eq "1";
		
		Log3( $name, 4, "Siro-Set: mapping level 0 - off");
		}

#################
# mappe invers position		
		# verschoben in routine on/off
		
############## on off for timer
# up/down for timer mappen auf on/off und timer für stop setzen
    if ( $comand eq 'upfortimer' ) 
	{
        Log3( $name, 5, "Siro-Set: up_for_timer  $args[1]" );
        $hash->{helper}{savedcmds}{cmd1} = 'stop';
        InternalTimer( time + $args[1], "FHEM::Siro::Restartset", "$name" );
    }

############## on off for timer

# up/down for timer mappen auf on/off und timer für stop setzen
    if ( $comand eq 'downfortimer' ) 
	{
        Log3( $name, 5, "Siro_Set: down_for_timer  $args[1]" );
        $hash->{helper}{savedcmds}{cmd1} = 'stop';
        InternalTimer( time + $args[1], "FHEM::Siro::Restartset", "$name" );
    }
#################
	if ($comand eq "fav") # favoritenanfahrt
		{
		if ($favposition eq "nA")
			{
			Log3( $name, 1, "Siro-Set: Favoritenanfahrt nicht m?glich , Reading nicht gesetzt");
			return;
			}
		Log3( $name, 3, "Siro-Set ($name) : set Favorit");	
        SendCommand( $hash, 'stop' , 'longstop' );
		# befehl ?ndern auf position favorite
		# weiterer programmdurchlauf 
		# per defintition keine weiteren send kommandos helper exexcmd on/off (off)
		$hash->{helper}{exexcmd} = 'off'; # schaltet das senden folgender befehls ab / nur anpassung der readings
		$comand = "level";
		$zielposition = $favposition;
		}
####################################
# favoritenposition speichern
    if ( $cmd eq "set_favorite" ) {
     
	 # lockdevive einrichten !  
	 readingsSingleUpdate( $hash, "state",  'programming', 1 );  

        my $sequence ;
		my $blocking;
		if ($favposition eq "nA")
			{
			$sequence =  '1:prog,3:stop,3:stop' ;
			$blocking = 8;
			}
		else
			{
			$sequence =  '1:prog,3:stop,3:stop,3:prog,3:stop,3:stop' ;
			$blocking =17;
			}
		
        my @sequenzraw =split (/,/,$sequence);
		my $exectime = $actiontime;
		foreach my $seqpart (@sequenzraw) 
			{
			Log3( $name, 5, "Siro-Set: Favorit seqpart - $seqpart");
			my @seqpartraw =split (/\:/,$seqpart);
			#$actiontime
			$exectime = $exectime+$seqpartraw[0];
			my $execcmd = $seqpartraw[1];
			Log3( $name, 5, "Siro-Set: Favorit $exectime - $execcmd");
			InternalTimer( $exectime, "FHEM::Siro::Prog", $name." ".$execcmd );	
			InternalTimer( ($actiontime+$blocking), "FHEM::Siro::Delock", $name );
			}
	readingsSingleUpdate( $hash, "Favorite-Position",  $position, 1 );	
    return;
    }
	
###################################################
# favoritenposition speichern
    if ( $cmd eq "del_favorite" )
		{
		   if ($args[1] eq "only_shutter" || $args[1] eq "shutter_and_modul")
			{
				readingsSingleUpdate( $hash, "state",  'programming', 1 ); 
				my $sequence ;
				$sequence =  '0:prog,2:stop,2:stop' ;
				my @sequenzraw =split (/,/,$sequence);
				my $exectime = $actiontime;
				foreach my $seqpart (@sequenzraw) 
					{
					Log3( $name, 5, "Siro-Set: Delfavorit seqpart - $seqpart");
					my @seqpartraw =split (/\:/,$seqpart);
					#$actiontime
					$exectime = $exectime+$seqpartraw[0];
					my $execcmd = $seqpartraw[1];
					Log3( $name, 5, "Siro-Set: Delfavorit  $exectime - $execcmd");
					InternalTimer( $exectime, "FHEM::Siro::Prog", $name." ".$execcmd );
					InternalTimer( $exectime+10, "FHEM::Siro::Delock", $name );
					}
			}
		if ($args[1] eq "only_modul" || $args[1] eq "shutter_and_modul")
			{
			readingsSingleUpdate( $hash, "Favorite-Position",  'nA', 1 );	
			}
        return;
    }
	
	
	##################################################
	##################################
	
	# set on ( device faeht runter )
	if ($comand eq "on" || $comand eq "downfortimer" )
		{
		Log3( $name, 3, "Siro-Set ($name) : set Down");	
		if ($downtime eq "undef" || $uptime eq "undef") # bei ungesetzten fahrzeiten
			{
			
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate( $hash, "state", "100" ) ;
			readingsBulkUpdate( $hash, "pct", "100" ) ;
			readingsBulkUpdate( $hash, "motor-term", "Function is not available without set runtime attribute, please define") ;
			readingsBulkUpdate( $hash, "LastAction", $comand );
			readingsEndUpdate( $hash, 1);
			SendCommand( $hash, 'on' );
			
			#return;
			
			}
			if ($state eq "undef" || $state eq "notAvaible") { $state = 0; }
			my $waytodrive = 100 - $state;
			
			if (AttrVal( $name, 'SIRO_inversPosition',0 ) eq "1"){$waytodrive = $state;}
			
			my $timetodrive = $waytodrive * $down1time;
			my $endaction = time + $timetodrive;
			Log3( $name, 5, "Siro-Set: on downtime - waytodrive $waytodrive");
			Log3( $name, 5, "Siro-Set: on downtime - state  $state");
			Log3( $name, 5, "Siro-Set: on downtime - down1time  $down1time");
			SendCommand( $hash, 'on' );
			#SendCommand( $hash, 'stop' );
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate( $hash, "aktRunningAction", $comand ) ;
			readingsBulkUpdate( $hash, "aktEndAction", $endaction ) ;
			readingsBulkUpdate( $hash, "aktTimeAction", $timetodrive ) ;
			readingsBulkUpdate( $hash, "aktActionFinish", "100" ) ;
			readingsBulkUpdate( $hash, "LastAction", $comand );
			readingsEndUpdate( $hash, 1);
			
			if ($comand eq "on")
			{
			readingsSingleUpdate( $hash, "state", "runningDown" , 1 ) ;
			
			# internen timer setzen runningtime - dann states setzen
			Log3( $name, 5, "Siro-Set: setze Timer -$comand");
			InternalTimer( $endaction, "FHEM::Siro::Finish", "$name" );
			
			}
			else{
			readingsSingleUpdate( $hash, "state", "runningDownfortimer" , 1 ) ;
			}
			#befehl ausfuhren
		}
		
##########################################
	# set off ( device faeht hoch )
	if ($comand eq "off" || $comand eq "upfortimer" )
		{
		Log3( $name, 3, "Siro-Set ($name) : set Up");	
		if ($downtime eq "undef" || $uptime eq "undef") # bei ungesetzten fahrzeiten
			{
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate( $hash, "state", "0" ) ;
			readingsBulkUpdate( $hash, "pct", "0" ) ;
			readingsBulkUpdate( $hash, "motor-term", "Function is not available without set runtime attribute, please define") ;
			readingsBulkUpdate( $hash, "LastAction", $comand );
			readingsEndUpdate( $hash, 1);
			SendCommand( $hash, 'off' );
			
			#return;
			}
			# 
			if ($state eq "undef" || $state eq "notAvaible") { $state = 100; }
			
			
			my $waytodrive = 0 + $state;
			if (AttrVal( $name, 'SIRO_inversPosition',0 ) eq "1"){$waytodrive = 0 + (100- $state);}
			
			my $timetodrive = $waytodrive * $up1time;
			
			
			my $endaction = time + $timetodrive;
			
			
			Log3( $name, 5, "Siro-Set: off downtime - waytodrive $waytodrive");
			Log3( $name, 5, "Siro-Set: off downtime - state  $state");
			Log3( $name, 5, "Siro-Set: off downtime - up1time  $up1time");
			SendCommand( $hash, 'off' );
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate( $hash, "aktRunningAction", $comand ) ;
			readingsBulkUpdate( $hash, "aktEndAction", $endaction ) ;
			readingsBulkUpdate( $hash, "aktTimeAction", $timetodrive ) ;
			readingsBulkUpdate( $hash, "aktActionFinish", "0" ) ;
			readingsBulkUpdate( $hash, "LastAction", $comand );
			readingsEndUpdate( $hash, 1);
			
			
			if ($comand eq "off")
				{
				readingsSingleUpdate( $hash, "state", "runningUp" , 1 ) ;
				
				# internen timer setzen runningtime - dann states setzen
			Log3( $name, 5, "Siro-Set: setze timer -$comand");
		    InternalTimer( $endaction, "FHEM::Siro::Finish", "$name" );
				}
			else
				{
				readingsSingleUpdate( $hash, "state", "runningUpfortimer" , 1 ) ;
				}

			#befehl ausfuhren
		}
		
#################################################	
	# set level ( positionsanfahrt )
	if ($comand eq "level")
		{
	
		if ( AttrVal($name,'SIRO_inversPosition','0') eq '1' )
			{
			$zielposition = 100 - $zielposition;
			$state = 100 - $state;
			}

		Log3( $name, 3, "Siro-Set ($name) : set Position $zielposition ");	
			
		if ($downtime eq "undef" || $uptime eq "undef") # bei ungesetzten fahrzeiten
			{
			Log3( $name, 1, "ERROR Siro - Set: Function is not available without set runtime attribute, please define");
			readingsSingleUpdate( $hash, "LastAction", $comand, 1 );
			readingsSingleUpdate( $hash, "motor-term", "Function is not available without set runtime attribute, please define", 1 ) ;
			return "Function PCT is not available without set runtime attribute, please define ";
			}
		my $timetodrive; #enth?tlt fahrzeit
		my $cmdpos ="undef"; # enth?lt fahrbefehl f?r gew?nschte richtung
		my $cmdactiontime ; # enth?lt fahrtdauer f?r gew?nschte position
		my $directionmsg; #enth?lt actionstesxt
		# geforderte farhtrichtung ermitteln
		if ($state < $zielposition) # fahrt runter ben?tigt
			{
			$cmdpos = "on";
			# fahrdauer ermitteln
			$timetodrive = ($zielposition - $state) * $down1time;
			$directionmsg ="runningDown";
			}
			
		if ($state > $zielposition) # fahrt hoch ben?tigt
			{
			$cmdpos = "off";
			# fahrdauer ermitteln
			$timetodrive = ($state - $zielposition) * $up1time;
			$directionmsg ="runningUp";
			} 

	my $endaction = time + $timetodrive;
	SendCommand( $hash, $cmdpos );

	readingsBeginUpdate($hash);
	readingsBulkUpdate( $hash, "aktRunningAction", 'position' ) ;
	readingsBulkUpdate( $hash, "aktEndAction", $endaction ) ;
	readingsBulkUpdate( $hash, "aktTimeAction", $timetodrive ) ;
	readingsBulkUpdate( $hash, "aktActionFinish", $zielposition ) ;
	readingsBulkUpdate( $hash, "state", $directionmsg  ) ;
	readingsEndUpdate( $hash, 1);
			
	# internen timer setzen runningtime - dann states setzen
	Log3( $name, 5, "Siro-Set: setze timer -$comand");
	InternalTimer( $endaction, "FHEM::Siro::Finish", "$name" );	
	
	Log3( $name, 5, "Siro-Set: found direction - $cmdpos");
	Log3( $name, 5, "Siro-Set: found finish - $zielposition");	
	Log3( $name, 5, "Siro-Set: found position now - $state");	
		
	}
		
######################################################
	# set stop 
	if ($comand eq "stop" && ReadingsVal( $name, 'LastAction', 'undef' ) ne $comand )
		{
		Log3( $name, 3, "Siro-Set ($name) : set Stop ");	
		if ($downtime eq "undef" || $uptime eq "undef") # bei ungesetzten fahrzeiten
			{
			SendCommand( $hash, 'stop' );
			readingsBeginUpdate($hash);
			readingsBulkUpdate( $hash, "state", "notAvaible" ) ;
			readingsBulkUpdate( $hash, "LastAction", $comand );
			readingsBulkUpdate( $hash, "motor-term", "Function is not available without set runtime attribute, please define", 1 ) ;
			readingsEndUpdate( $hash, 1);
			return;
			}
			else # bei gesetzten fahrzeiten
			{
			SendCommand( $hash, 'stop' );
			}
		
		}
############################################
   # batteriecheck
   if ( AttrVal( $name, 'SIRO_Battery_low','undef' ) ne "undef")
	   {
	   readingsSingleUpdate( $hash, "batteryState", "ok" , 1 ) if (AttrVal( $name, 'SIRO_Battery_low','' ) > ReadingsNum( $name, 'motor-term', 0 ));
	   readingsSingleUpdate( $hash, "batteryState", "low" , 1 ) if (AttrVal( $name, 'SIRO_Battery_low','' ) < ReadingsNum( $name, 'motor-term', 0 ));
	   }
   else
	   {
	   readingsSingleUpdate( $hash, "batteryState", "unknown" , 1 );
	   }
  return;
}

#######################
sub Delock($) { 
# entsperrt device nach programmierung des shutters
    my ($input) = @_;
    my ( $name, $arg ) = split(/ /, $input );
    my $hash = $defs{$name};
	my $position = ReadingsVal( $name, 'pct', '' ); #position pct bis zum ende einer aktion
	readingsSingleUpdate( $hash, "state", $position , 1 );
	}

#######################
sub Prog($) { 
#wird im programmiermode von internaltimer aufgerufen
    my ($input) = @_;
    my ( $name, $arg ) = split(/ /, $input );
    my $hash = $defs{$name};
	Log3( $name, 5, "Siro-Prog: $arg ");
	SendCommand( $hash, $arg );
	return;
	}
	
#######################
sub Finish($) { 
# wird bei errechnetem aktionsende aufgerufen
    my ($input) = @_;
    my ( $name, $arg ) = split( / /, $input );
    my $hash = $defs{$name};
    return "" if ( IsDisabled($name) );
	
	my $invers = 1;
	my $action = ReadingsVal( $name, 'aktRunningAction', '' );
	my $state = ReadingsVal( $name, 'aktActionFinish', 'notAvaible' );
	my $operationtime = ReadingsNum( $name, 'motor-term', 0 );
	my $newoperationtime = $operationtime + ReadingsNum ($name, 'aktTimeAction', 0 );
	
	Log3( $name, 5, "Siro-Finish: action - $action");
	
	SendCommand( $hash, 'stop' ) if ( $action ne "on" && $action ne "off" ) ;
	
	if ( AttrVal($name,'SIRO_inversPosition','0') eq '1' )
		{
		$state = 100 - $state;
		}
	readingsBeginUpdate($hash);
	readingsBulkUpdate( $hash, "state", $state  ) ;
	readingsBulkUpdate( $hash, "pct", $state  ) ;
	readingsBulkUpdate( $hash, "position", $state  ) ;
	readingsBulkUpdate( $hash, "aktRunningAction", "noAction" ) ;
	readingsBulkUpdate( $hash, "aktEndAction", 0 ) ;
	readingsBulkUpdate( $hash, "aktTimeAction", 0 ) ;
	readingsBulkUpdate( $hash, "aktActionFinish", 0 ) ;
	readingsBulkUpdate( $hash, "motor-term", $newoperationtime, 1 ) ;
	readingsEndUpdate( $hash, 1);
	return;
	}

#####################
sub Restartset($) {
    my ($input) = @_;
    my ( $name, $arg ) = split( / /, $input );
    my $hash = $defs{$name};
    return "" if ( IsDisabled($name) );
	Log3( $name, 5, "Siro-Restartset : aufgerufen");
	my $cmd = $hash->{helper}{savedcmds}{cmd1};
	my $pos = $hash->{helper}{savedcmds}{cmd2};
	delete( $hash->{helper}{savedcmds} );
	Log3( $name, 5, "Siro-Restartset : cmds $name, $cmd , $pos");
    Set($hash, $name, $cmd , $pos);
	return;
}
#####################
sub versionchange($) {
    my ($input) = @_;
    my ( $name, $arg ) = split( / /, $input );
    my $hash = $defs{$name};
    return "" if ( IsDisabled($name) );
	Log3( $name, 0, "Siro - versionchange : aufruf");
	my $attr;

	$attr = AttrVal($name,'time_to_close','undef');
	CommandAttr(undef,$name . ' SIRO_time_to_close ' . $attr) if ( AttrVal($name,'time_to_close','undef') ne 'undef' );
	fhem("deleteattr $name time_to_close");
	
	$attr = AttrVal($name,'time_to_open','undef');
	CommandAttr(undef,$name . ' SIRO_time_to_open ' . $attr) if ( AttrVal($name,'time_to_open','undef') ne 'undef' );
	fhem("deleteattr $name time_to_open");
	
	$attr = AttrVal($name,'SignalLongStopRepeats','undef');
	CommandAttr(undef,$name . ' SIRO_signalLongStopRepeats ' . $attr) if ( AttrVal($name,'SignalLongStopRepeats','undef') ne 'undef' );
	fhem("deleteattr $name SignalLongStopRepeats");
	
	$attr = AttrVal($name,'SignalRepeats','undef');
	CommandAttr(undef,$name . ' SIRO_signalRepeats ' . $attr) if ( AttrVal($name,'SignalRepeats','undef') ne 'undef' );
	fhem("deleteattr $name SignalRepeats");
	
	$attr = AttrVal($name,'invers_position','undef');
	CommandAttr(undef,$name . ' SIRO_inversPosition ' . $attr) if ( AttrVal($name,'invers_position','undef') ne 'undef' );
	fhem("deleteattr $name invers_position");

	CommandAttr( undef,$name . ' devStateIcon {if (ReadingsVal( $name, \'state\', \'undef\' ) =~ m/[a-z]/ ) { return \'programming:edit_settings notAvaible:hue_room_garage runningUp.*:fts_shutter_up runningDown.*:fts_shutter_down\'}else{return \'[0-9]{1,3}:fts_shutter_1w_\'.(int($state/10)*10)}}' );
    CommandAttr(undef,$name . ' webCmd stop:open:close:fav:pct');

	$attr = AttrVal($name,'operation_mode','undef');
	if ($attr eq "1"){
	my $modch = AttrVal($name,'channel_send_mode_1','undef');
	CommandAttr(undef,$name . ' SIRO_send_channel ' . $modch)
	}
	
	fhem("deleteattr $name operation_mode");
	fhem("deleteattr $name channel_send_mode_1");
	fhem("deleteattr $name down_limit_mode_1");
	fhem("deleteattr $name operation_mode");
	fhem("deleteattr $name invers_position");
	fhem("deleteattr $name down_auto_stop");
	fhem("deleteattr $name prog_fav_sequence");
	fhem("deleteattr $name time_down_to_favorite");
	fhem("deleteattr $name time_down_to_favorite");
	my $seconds = ReadingsVal( $name, 'operating_seconds', '0' );
	fhem("deletereading $name .*");
	readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "state", "0" );
	readingsBulkUpdate( $hash, "pct", "0" ) ;
	readingsBulkUpdate( $hash, "position", "0" ) ;
	readingsBulkUpdate( $hash, "motor-term", $seconds ) ;
    readingsEndUpdate( $hash, 1 );
	SendCommand( $hash, 'off' );
	return;
}
##################
sub fhemwebFn($$$$) {
my ( $FW_wname, $d, $room, $pageHash ) =@_;    # pageHash is set for summaryFn.
    my $hash     = $defs{$d};
    my $name     = $hash->{NAME};
    return "" if ( IsDisabled($name) );
	my $progmode =$hash->{helper}{progmode};
	Log3( $name, 5, "Siro-progmode: reached progmode $progmode");
	if (!defined $progmode){$progmode='off';}
	my $msg;

############## versionsänderung
# kann irgendwann entfernt werden
	
	if (AttrVal( $name, 'SIRO_debug', "0" ) eq "1")
	
	{
	$msg.= "<table class='block wide' id='SiroWebTR'>
			<tr class='even'>
			<td><center>&nbsp;<br>Das Device ist im Debugmodus, es werden keine Befehle gesendet";
	$msg.= "<br>&nbsp;<br></td></tr></table>";
	
	}
#######################	
	
	if (ReadingsVal( $name, 'last_reset_os', 'undef' ) ne 'undef')
		{
		$msg.= "<table class='block wide' id='SiroWebTR'>
			<tr class='even'>
			<td><center>&nbsp;<br>ACHTUNG !<br>&nbsp;<br>Das Siromudul wurde komplett erneuert.<br>Die vorhandenen Attribute und Readings sind inkompatibel und das Device derzeit nur bedingt funktionsfaehig:<br>&nbsp;<br>Durch druecken des untenstehenden Buttons ist eine automatisch Neukonfiguration moeglich, dabei werden vorhandene Daten beruecksichtigt. Nach betaetigen des Buttons macht das Rollo eine Initialisierungsfahrt nach oben.<br>&nbsp;<br>Danach ist eine Funktion mit der alten Siroversion nicht mehr moeglich.<br>Fuer den Fall, das doch die alte Version wieder eingesetzt werden sollte ist die jetzt vorhandene Rawdefinition <u>vor einer Umstellung zu sichern</u>.<br>Wichtig: Bei einer automatischen Umstellung werden entgegen den Massgaben vorhandene Userattribute geaendert ! ";
		$msg.= "<br>&nbsp;<br>";
		$msg.= "<input type=\"button\" id=\"\" value=\"KONFIGURATION AUTOMATISCH ANPASSEN\" onClick=\"javascript:prog('changeconfig');\">";
		$msg.= "&nbsp;";
		$msg.= "<br>&nbsp;
			</td></tr></table>
			";
		}
######################

	if ( $progmode eq "on")
		{
		$msg= "<table class='block wide' id='SiroWebTR'>
			<tr class='even'>
			<td><center>&nbsp;<br>Programmiermodus aktiv, es werden nur folgende Befehle unterstuetzt:<br>&nbsp;<br>";
		$msg.= "Das Anlernen ene Rollos erfolgt unter der ID: ";
		
	my $sendid = AttrVal( $name, 'SIRO_send_id', 'undef' );
	if ( $sendid eq 'undef')
	{
		$msg.= $hash->{ID} ;
	}
	else
	{
		$msg.=  $sendid ;	
	}		
	$msg.= " und dem Kanal:  ";
	my $sendchan = AttrVal( $name, 'SIRO_send_channel', 'undef' );
	if ( $sendchan eq 'undef')
	{
		$msg.= $hash->{CHANNEL_RECEIVE} ;
	}
	else
	{
		$msg.=  $sendchan ;	
	}	
	
		$msg.= "<br>&nbsp;<br> ";	
		
		$msg.= "<input  style=\"height: 80px; width: 150px;\" type=\"button\" id=\"siro_prog_proc\" value=\"P2\" onClick=\"javascript:prog('prog');\">";
		$msg.= "&nbsp;";
			
		$msg.= "<input  style=\"height: 80px; width: 150px;\" type=\"button\" id=\"siro_prog_up\" value=\"UP\" onClick=\"javascript:prog('off');\">";
		$msg.= "&nbsp;";
			
		$msg.= "<input  style=\"height: 80px; width: 150px;\" type=\"button\" id=\"siro_prog_up\" value=\"DOWN\" onClick=\"javascript:prog('on');\">";
		$msg.= "&nbsp;";
			
		$msg.= "<input  style=\"height: 80px; width: 150px;\" type=\"button\" id=\"siro_prog_down\" value=\"STOP\" onClick=\"javascript:prog('stop');\">";
		$msg.= "&nbsp;";
			
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "&nbsp;";
		$msg.= "<input  style=\"height: 80px; width: 150px;\" type=\"button\" id=\"siro_prog_end\" value=\"END THIS MODE\" onClick=\"javascript:prog('prog_mode_off');\">";
		$msg.= "&nbsp;<br>&nbsp;";
			
		$msg.= "<br>- Motor anlernen: P2,P2,DOWN je nach Wicklung des Rollos";
		$msg.= "&nbsp;<input type=\"button\" id=\"siro_prog_stop\" value=\"execute\" onClick=\"javascript:prog('exec,prog,prog,on');\">";
			
		$msg.= "<br>- Motor anlernen: P2,P2,UP je nach Wicklung des Rollos";
		$msg.= "&nbsp;<input type=\"button\" id=\"siro_prog_stop\" value=\"execute\" onClick=\"javascript:prog('exec,prog,prog,off');\">";
			
		$msg.= "<br>- Einstellmodus aktivieren: P2, UP, P2";
		$msg.= "&nbsp;<input type=\"button\" id=\"siro_prog_stop\" value=\"execute\" onClick=\"javascript:prog('exec,prog,off,prog');\">";
			
		$msg.= "<br>- Endlagen loeschen: P2, DOWN, P2";
		$msg.= "&nbsp;<input type=\"button\" id=\"siro_prog_stop\" value=\"execute\" onClick=\"javascript:prog('exec,prog,on,prog');\">";
			
		$msg.= "<br>- Pairing loeschen: P2, STOP, P2";
		$msg.= "&nbsp;<input type=\"button\" id=\"siro_prog_stop\" value=\"execute\" onClick=\"javascript:prog('exec,prog,stop,prog');\">";
			
		$msg.= "<br>&nbsp;</td></tr></table>";
	}	
		
	$msg.= "<script type=\"text/javascript\">{";	
	$msg.= "function prog(msg){
		var  def = \"" . $name . "\"+\" \"+msg;
		if (msg == 'prog_mode_off')
		{
		location = location.pathname+\"?detail=" . $name . "&cmd=set \"+addcsrf(def);
		}
		else if ( msg == 'changeconfig')
		{
		location = location.pathname+\"?detail=" . $name . "&cmd=set \"+addcsrf(def);
		}
		else{
		var clickurl = location.pathname+\"?cmd=set \"+addcsrf(def);
		\$.post(clickurl, {});
		}
	}
	";
	
	$msg.= "}</script>";	
	return $msg;
}

################	
sub Siro_icon($) 
	{
	my ($name) = @_;
	my $hash = $defs{$name};
	my $state = ReadingsVal( $name, 'state', 'undef' );
	
	
	if ($state =~ m/[a-z].*/){$state=0;}
	
	
	my $invers = AttrVal( $name, 'SIRO_inversPosition',0 ); 
	my $ret ="programming:edit_settings notAvaible:hue_room_garage runningUp.*:fts_shutter_up runningDown.*:fts_shutter_down ".$state.":fts_shutter_1w_".(int($state/10)*10);
	$ret ="programming:edit_settings notAvaible:hue_room_garage runningUp.*:fts_shutter_up runningDown.*:fts_shutter_down ".$state.":fts_shutter_1w_".(100 - (int($state/10)*10)) if $invers eq "1";
	return $ret;
	}

################


1;

=pod

=item summary    Supports rf shutters from Siro
=item summary_DE Unterst&uumltzt Siro Rollo-Funkmotoren


=begin html

<a name="Siro"></a>
<h3>Siro protocol</h3>
<ul>
   
   <br> A <a href="#SIGNALduino">SIGNALduino</a> device (must be defined first).<br>
   
   <br>
        Since the protocols of Siro and Dooya are very similar, it is currently difficult to operate these systems simultaneously via one "IODev". Sending commands works without any problems, but distinguishing between the remote control signals is hardly possible in SIGNALduino. For the operation of the Siro-Module it is therefore recommended to exclude the Dooya protocol (16) in the SIGNALduino, via the whitelist. In order to detect the remote control signals correctly, it is also necessary to deactivate the "manchesterMC" protocol (disableMessagetype manchesterMC) in the SIGNALduino. If machester-coded commands are required, it is recommended to use a second SIGNALduino.<br>
 <br>
 <br>

   
  <a name="Sirodefine"></a>
   <br>
  <b>Define</b>
   <br>
  <ul>
    <code>define&lt; name&gt; Siro &lt;id&gt;&lt;channel&gt; </code>
  <br>
 <br>
   The ID is a 7-digit hex code, which is uniquely and firmly assigned to a Siro remote control. Channel is the single-digit channel assignment of the remote control and is also hexadecimal. This results in the possible channels 0 - 15 (hexadecimal 0-F). 
A unique ID must be specified, the channel (channel) must also be specified. 
An autocreate (if enabled) automatically creates the device with the ID of the remote control and the channel.

    <br><br>

    Examples:<br><br>
    <ul>
	<code>define Siro1 Siro AB00FC1</code><br>       Creates a Siro-device called Siro1 with the ID: AB00FC and Channel: 1<br>
    </ul>
  </ul>
  <br>

  <a name="Siroset"></a>
  <b>Set </b><br>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;position&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    stop
    pos (0...100) 
    prog  
    fav
    </pre>
    
    Examples:<br><br>
    <ul>
      <code>set Siro1 on</code><br>
      <code>set Siro1 off</code><br>
      <code>set Siro1 position 50</code><br>
      <code>set Siro1 fav</code><br>
      <code>set Siro1 stop</code><br>
	    <code>set Siro1 set_favorite</code><br>
    </ul>
    <br>
     <ul>
set Siro1 on                           moves the roller blind up completely (0%)<br>
set Siro1 off                           moves the roller blind down completely (100%)<br>
set Siro1 stop                        stops the current movement of the roller blind<br>
set Siro1 pct 45              moves the roller blind to the specified position (45%)<br>
set Siro1 45                           moves the roller blind to the specified position (45%)<br>
set Siro1 fav                          moves the blind to the hardware-programmed favourite middle position<br>
set Siro1 set_favorite               programs the current roll position as hardware middle position. The attribute time_down_to_favorite is recalculated and set. <br>
set Siro1 progmode_on               enable the programming mode <br>


</ul>
    <br>
    Notes:<br><br>
    <ul>
      <li>If the module is in programming mode, the module detects successive stop commands because they are absolutely necessary for programming. In this mode, the readings and state are not updated. The mode is automatically terminated after 3 minutes. The remaining time in programming mode is displayed in the reading "pro_mode". The remaining time in programming mode is displayed in the reading "pro_mode". The programming of the roller blind must be completed during this time, otherwise the module will no longer accept successive stop commands. The display of the position, the state, is a calculated position only, since there is no return channel to status message. Due to a possible missing remote control command, timing problem etc. it may happen that this display shows wrong values sometimes. When moving into an end position without stopping the movement (set Siro1[on/off]), the status display and real position are synchronized each time the position is reached. This is due to the hardware and unfortunately not technically possible.
      </li>
     	</ul>
  </ul>
  <br>

  <b>Get</b> 
  <ul>N/A</ul><br>

  <a name="Siroattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <a name="IODev"></a>
    <li>IODev<br>
        The IODev must contain the physical device for sending and receiving the signals. Currently a SIGNALduino or SIGNALesp is supported.
        Without the specification of the "Transmit and receive module" "IODev", a function is not possible. 
    </li><br>

  <a name="SIRO_send_channel"></a>
    <li>channel (since V1.09 no longer available)<br>
        contains the channel used by the module for sending. 
        This is already set when the device is created.

    </li><br>
	
	 <a name="SIRO_send_ID"></a>
    <li>contains the ID used by the module for sending. 
        This is already set when the device is created.

    </li><br>
	

    <a name="SIRO_time_to_close"></a>
    <li>time_to_close<br>
        contains the movement time in seconds required by the blind from 0% position to 100% position. This time must be measured and entered manually. 
        Without this attribute, the module is not fully functional.</li><br>

       <a name="SIRO_time_to_open"></a>
    <li>time_to_open<br>
        contains the movement time in seconds required by the blind from 100% position to 0% position. This time must be measured and entered manually.
        Without this attribute, the module is not fully functional.</li><br>

		<a name="debug_mode [0:1]"></a>
    <li>debug_mode [0:1]<br>
        In mode 1 Commands are NOT physically sent.</li><br>
		
			<a name="Info"></a>
    <li>Info<br>
        The attributes webcmd and devStateIcon are set once when the device is created and are adapted to the respective mode of the device during operation. The adaptation of these contents only takes place until they have been changed by the user. After that, there is no longer any automatic adjustment.</li><br>

  </ul>
</ul>

=end html

=begin html_DE

<a name="Siro"></a>
<h3>Siro protocol</h3>
<ul>
   
   <br> Ein <a href="#SIGNALduino">SIGNALduino</a>-Geraet (dieses sollte als erstes angelegt sein).<br>
   
   <br>
        Da sich die Protokolle von Siro und Dooya sehr &auml;hneln, ist ein gleichzeitiger Betrieb dieser Systeme ueber ein "IODev" derzeit schwierig. Das Senden von Befehlen funktioniert ohne Probleme, aber das Unterscheiden der Fernbedienungssignale ist in Signalduino kaum m&ouml;glich. Zum Betrieb der Siromoduls wird daher empfohlen, das Dooyaprotokoll im SIGNALduino (16) &uuml;ber die Whitelist auszuschliessen. Zur fehlerfreien Erkennung der Fernbedienungssignale ist es weiterhin erforderlich im SIGMALduino das Protokoll "manchesterMC" zu deaktivieren (disableMessagetype manchesterMC). Wird der Empfang von machestercodierten Befehlen benoetigt, wird der Betrieb eines zweiten Signalduinos empfohlen.<br>
 <br>
 <br>

   
  <a name="Sirodefine"></a>
   <br>
  <b>Define</b>
   <br>
  <ul>
    <code>define &lt;name&gt; Siro &lt;id&gt; &lt;channel&gt;</code>
  <br>
 <br>
   Bei der <code>&lt;ID&gt;</code> handelt es sich um einen 7-stelligen Hexcode, der einer Siro Fernbedienung eindeutig und fest zugewiesen ist. <code>&lt;Channel&gt;</code> ist die einstellige Kanalzuweisung der Fernbedienung und ist ebenfalls hexadezimal. Somit ergeben sich die m&ouml;glichen Kan&auml;le 0 - 15 (hexadezimal 0-F).
Eine eindeutige ID muss angegeben werden, der Kanal (Channel) muss ebenfalls angegeben werden. <br>
Ein Autocreate (falls aktiviert), legt das Device mit der ID der Fernbedienung und dem Kanal automatisch an.

    <br><br>

    Beispiele:<br><br>
    <ul>
	<code>define Siro1 Siro AB00FC1</code><br>       erstellt ein Siro-Geraet Siro1 mit der ID: AB00FC und dem Kanal: 1<br>
    </ul>
  </ul>
  <br>

  <a name="Siroset"></a>
  <b>Set </b><br>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;position&gt]</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <pre>
    on
    off
    up
    down
    stop
    pct (0..100)
    prog_mode_on
    prog_mode_off
    fav
    set_favorite
    del_favorite
    </pre>
    
    Beispiele:<br><br>
    <ul>
      <code>set Siro1 on</code><br>
      <code>set Siro1 off</code><br>
      <code>set Siro1 pct 50</code><br>
      <code>set Siro1 fav</code><br>
      <code>set Siro1 stop</code><br>
      <code>set Siro1 set_favorite</code><br>
      <code>set Siro1 down_for_timer 5</code><br>
      <code>set Siro1 up_for_timer 5</code><br>
      <code>set Siro1 set_favorite</code><br>
    </ul>
    <br>
     <ul>
set Siro1 on                           f&auml;hrt das Rollo komplett hoch (0%)<br>
set Siro1 off                           f&auml;hrt das Rollo komplett herunter (100%)<br>
set Siro1 stop                        stoppt die aktuelle Fahrt des Rollos<br>
set Siro1 pct 45              f&auml;hrt das Rollo zur angegebenen Position (45%)<br>
set Siro1 45                           f&auml;hrt das Rollo zur angegebenen Position (45%)<br>
set Siro1 fav                          f&auml;hrt das Rollo in die hardwarem&auml;ssig programmierte Mittelposition<br>
set Siro1 down_for_timer 5                          f&auml;hrt das Rollo 5 Sekunden nach unten<br>
set Siro1 down_for_timer 5                         f&auml;hrt das Rollo 5 Sekunden nach oben<br>
set Siro1 progmode_on                       Das Modul wird in den Programmiermodus versetzt<br>
set Siro1 set_favorite               programmiert den aktuellen Rollostand als Hardwaremittelposition, das ATTR time_down_to_favorite wird neu berechnet und gesetzt. <br>
</ul>
    <br>
    Hinweise:<br><br>
    <ul>
      <li>Befindet sich das Modul im Programmiermodus, werden aufeinanderfolgende Stoppbefehle vom Modul erkannt, da diese zur Programmierung zwingend erforderlich sind. In diesem Modus werden die Readings und das State nicht aktualisiert. Der Modus wird nach 3 Minuten automatisch beendet. Die verbleibende Zeit im Programmiermodus wird im Reading "pro_mode" dargestellt. Die Programmierung des Rollos muss in dieser Zeit abgeschlossen sein, da das Modul andernfalls keine aufeinanderfolgenden Stoppbefehle mehr akzeptiert.
Die Anzeige der Position, des States, ist eine ausschliesslich rechnerisch ermittelte Position, da es keinen R&uumlckkanal zu Statusmeldung gibt. Aufgrund eines ggf. verpassten Fernbedienungsbefehls, Timingproblems etc. kann es vorkommen, dass diese Anzeige ggf. mal falsche Werte anzeigt. Bei einer Fahrt in eine Endposition, ohne die Fahrt zu stoppen (set Siro1 [on/off]), werden Statusanzeige und echte Position bei Erreichen der Position jedes Mal synchronisiert. Diese ist der Hardware geschuldet und technisch leider nicht anders l&ouml;sbar.
      </li>
     	</ul>
  </ul>
  <br>

  <b>Get</b> 
  <ul>N/A</ul><br>

  <a name="Siroattr"></a>
  <b>Attributes</b><br><br>
  <ul>
        <a name="IODev"></a>
    <li>IODev<br>
        Das IODev muss das physische Ger&auml;t zum Senden und Empfangen der Signale enthalten. Derzeit wird ein SIGNALduino bzw. SIGNALesp unterst?tzt.
        Ohne der Angabe des "Sende- und Empfangsmodul" "IODev" ist keine Funktion moeglich.</li><br>

    <a name="SIRO_time_to_close"></a>
    <li>time_to_close<br>
        beinhaltet die Fahrtzeit in Sekunden, die das Rollo von der 0% Position bis zur 100% Position ben&ouml;tigt. Diese Zeit muss manuell gemessen werden und eingetragen werden.
        Ohne dieses Attribut ist das Modul nur eingeschr&auml;nkt funktionsf&auml;hig.</li><br>

       <a name="time_to_open"></a>
    <li>SIRO_time_to_open<br>
        beinhaltet die Fahrtzeit in Sekunden, die das Rollo von der 100% Position bis zur 0% Position ben&ouml;tigt. Diese Zeit muss manuell gemessen werden und eingetragen werden.
        Ohne dieses Attribut ist das Modul nur eingeschr&auml;nkt funktionsf&auml;hig.</li><br>

    <a name="debug_mode [0:1]"></a>
    <li>debug_mode [0:1] <br>
         unterdrueckt das Weiterleiten von Befehlen an den Signalduino</li><br>
		 
	 <a name="SIRO_signalRepeats"></a>
    <li>SIRO_signalRepeats <br>
         Anzahl der Signalwiederholungen von gesendeten Befehlen </li><br>
		 
	 <a name="SIRO_signalLongstopRepeats"></a>
    <li>SIRO_signalLongstopRepeats <br>
         Anzahl der Signalwiederholungen des Favoritenbefehls </li><br>
		 
	<a name="SIRO_inversPosition"></a>
    <li>SIRO_signalLongstopRepeats <br>
         invertiert die Positionsangaben </li><br>	 
		 
	<a name="SIRO_inversPosition"></a>
    <li>SIRO_signalLongstopRepeats <br>
         invertiert die Positionsangaben </li><br>

	<a name="SIRO_sendChannel"></a>
    <li>SIRO_sendChannel <br>
         Kanal, der zum senden genutzt wird. Wird dieses Attribut gesetz, so empfaengt das Device nachwievor den urspruenglich gesetzten Kanal, sendet aber auf dem hier angegebenen Kanal </li><br>		 
	
	<a name="SIRO_sendID"></a>
    <li>SIRO_sendID <br>
         ID, die zum senden genutzt wird. Wird dieses Attribut gesetz, so empfaengt das Device nachwievor ie urspruenglich gesetzte ID, sendet aber auf der hier angegebenen ID </li><br>		 
		 	
	<a name="SIRO_battery_low"></a>
    <li>SIRO_battery_low <br>
         Motorlaufzeit in sekunden. Bei erreichen der Zeit wird das Reading Batterystate auf low gesetzt</li><br>		 
		 

    <a name="Info"></a>
    <li>Info<br>
        Die Attribute webcmd und devStateIcon werden beim Anlegen des Devices einmalig gesetzt und im auch im Betrieb an den jeweiligen Mode des Devices angepasst. Die Anpassung dieser Inhalte geschieht nur solange, bis diese durch den Nutzer ge&auml;ndert wurden. Danach erfolgt keine automatische Anpassung mehr.</li><br>

  </ul>
</ul>

=end html_DE



=cut
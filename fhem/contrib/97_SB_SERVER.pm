# ############################################################################
#
#  FHEM Modue for Squeezebox Servers
#
# ############################################################################
#
#  used to interact with Squeezebox server
#
# ############################################################################
#
#  This is absolutley open source. Please feel free to use just as you
#  like. Please note, that no warranty is given and no liability 
#  granted.
#
# ############################################################################
#
#  we have the following readings
#  power            on|off
#  version          the version of the SB Server
#  serversecure     is the CLI port protected with a passowrd?
#
# ############################################################################
#
#  we have the following attributes
#  alivetimer       time frequency to set alive signals
#  maxfavorites     maximum number of favorites we handle at FHEM
#
# ############################################################################
#  we have the following internals (all UPPERCASE)
#  IP               the IP of the server
#  CLIPORT          the port for the CLI interface of the server
#
# ############################################################################

package main;
use strict;
use warnings;

use IO::Socket;
use URI::Escape;
# inlcude for using the perl ping command
use Net::Ping;


# this will hold the hash of hashes for all instances of SB_SERVER
my %favorites;
my $favsetstring = "favorites: ";

# this is the buffer for commands, we queue up when server is power=off
my %SB_SERVER_CmdStack;

# include this for the self-calling timer we use later on
use Time::HiRes qw(gettimeofday);

use constant { true => 1, false => 0 };
use constant { TRUE => 1, FALSE => 0 };

# ----------------------------------------------------------------------------
#  Initialisation routine called upon start-up of FHEM
# ----------------------------------------------------------------------------
sub SB_SERVER_Initialize( $ ) {
    my ($hash) = @_;

    require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
    $hash->{ReadFn}  = "SB_SERVER_Read";
    $hash->{WriteFn} = "SB_SERVER_Write";
    $hash->{ReadyFn} = "SB_SERVER_Ready";
    $hash->{Clients} = ":SB_PLAYER:";
    my %matchList= (
	"1:SB_PLAYER"   => "^SB_PLAYER:",
	);
    $hash->{MatchList} = \%matchList;

# Normal devices
    $hash->{DefFn}   = "SB_SERVER_Define";
    $hash->{UndefFn} = "SB_SERVER_Undef";
    $hash->{ShutdownFn} = "SB_SERVER_Shutdown";
    $hash->{GetFn}   = "SB_SERVER_Get";
    $hash->{SetFn}   = "SB_SERVER_Set";
    $hash->{AttrFn}  = "SB_SERVER_Attr";

    $hash->{AttrList} = "alivetimer maxfavorites ";
    $hash->{AttrList} .= "doalivecheck:true,false ";
    $hash->{AttrList} .= "maxcmdstack ";
    $hash->{AttrList} .= $readingFnAttributes;

}

# ----------------------------------------------------------------------------
#  called when defining a module
# ----------------------------------------------------------------------------
sub SB_SERVER_Define( $$ ) {
    my ($hash, $def ) = @_;
    
    #my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_Define: called" );

    # first of all close existing connections
    DevIo_CloseDev( $hash );
    
    my @a = split("[ \t][ \t]*", $def);
    
    # do we have the right number of arguments?
    if( ( @a < 3 ) || ( @a > 7 ) ) {
	Log3( $hash, 3, "SB_SERVER_Define: falsche Anzahl an Argumenten" );
	return( "wrong syntax: define <name> SB_SERVER <serverip[:cliport]>" .
		"[USER:username] [PASSWord:password] " . 
		"[RCC:RCC_Name] [WOL:WOLName]" );
    }

    # remove the name and our type
    my $name = shift( @a );
    shift( @a );

    # assign safe default values
    $hash->{IP} = "127.0.0.1";
    $hash->{CLIPORT}  = 9090;
    $hash->{WOLNAME} = "none";
    $hash->{RCCNAME} = "none";
    $hash->{USERNAME} = "?";
    $hash->{PASSWORD} = "?";
    # parse the user spec
    foreach( @a ) {
	if( $_ =~ /^(RCC:)(.*)/ ) {
	    $hash->{RCCNAME} = $2;
	    next;
	} elsif( $_ =~ /^(WOL:)(.*)/ ) {
	    $hash->{WOLNAME} = $2;
	    next;
	} elsif( $_ =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d{3,5})/ ) {
	    $hash->{IP} = $1;
	    $hash->{CLIPORT}  = $2;
	    next;
	} elsif( $_ =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) {
	    $hash->{IP} = $1;
	    $hash->{CLIPORT}  = 9090;
	    next;
	} elsif( $_ =~ /^(USER:)(.*)/ ) {
	    $hash->{USERNAME} = $2;
	} elsif( $_ =~ /^(PASSWORD:)(.*)/ ) {
	    $hash->{PASSWORD} = $2;
	} else {
	    next;
	}
    }

    $hash->{LASTANSWER} = "none";

    # preset our attributes
    if( !defined( $attr{$name}{alivetimer} ) ) {
	$attr{$name}{alivetimer} = 120;
    }

    if( !defined( $attr{$name}{doalivecheck} ) ) {
	$attr{$name}{doalivecheck} = "true";
    }

    if( !defined( $attr{$name}{maxfavorites} ) ) {
	$attr{$name}{maxfavorites} = 30;
    }

    if( !defined( $attr{$name}{maxcmdstack} ) ) {
	$attr{$name}{maxcmdstack} = 200;
    }

    # Preset our readings if undefined
    my $tn = TimeNow();

    # server on / off
    if( !defined( $hash->{READINGS}{power}{VAL} ) ) {
	$hash->{READINGS}{power}{VAL} = "?";
	$hash->{READINGS}{power}{TIME} = $tn; 
    }

    # the server version
    if( !defined( $hash->{READINGS}{serverversion}{VAL} ) ) {
	$hash->{READINGS}{serverversion}{VAL} = "?";
	$hash->{READINGS}{serverversion}{TIME} = $tn; 
    }

    # is the CLI port secured with password?
    if( !defined( $hash->{READINGS}{serversecure}{VAL} ) ) {
	$hash->{READINGS}{serversecure}{VAL} = "?";
	$hash->{READINGS}{serversecure}{TIME} = $tn; 
    }

    # the status of our server alive check mechanism
    if( !defined( $hash->{READINGS}{alivecheck}{VAL} ) ) {
	$hash->{READINGS}{alivecheck}{VAL} = "?";
	$hash->{READINGS}{alivecheck}{TIME} = $tn; 
    }


    # the maximum number of favorites on the server
    if( !defined( $hash->{READINGS}{favoritestotal}{VAL} ) ) {
	$hash->{READINGS}{favoritestotal}{VAL} = 0;
	$hash->{READINGS}{favoritestotal}{TIME} = $tn; 
    }

    # is a scan in progress
    if( !defined( $hash->{READINGS}{scanning}{VAL} ) ) {
	$hash->{READINGS}{scanning}{VAL} = "?";
	$hash->{READINGS}{scanning}{TIME} = $tn; 
    }

    # the scan in progress
    if( !defined( $hash->{READINGS}{scandb}{VAL} ) ) {
	$hash->{READINGS}{scandb}{VAL} = "?";
	$hash->{READINGS}{scandb}{TIME} = $tn; 
    }

    # the scan already completed
    if( !defined( $hash->{READINGS}{scanprogressdone}{VAL} ) ) {
	$hash->{READINGS}{scanprogressdone}{VAL} = "?";
	$hash->{READINGS}{scanprogressdone}{TIME} = $tn; 
    }

    # the scan already completed
    if( !defined( $hash->{READINGS}{scanprogresstotal}{VAL} ) ) {
	$hash->{READINGS}{scanprogresstotal}{VAL} = "?";
	$hash->{READINGS}{scanprogresstotal}{TIME} = $tn; 
    }

    # did the last scan fail
    if( !defined( $hash->{READINGS}{scanlastfailed}{VAL} ) ) {
	$hash->{READINGS}{scanlastfailed}{VAL} = "?";
	$hash->{READINGS}{scanlastfailed}{TIME} = $tn; 
    }

    # number of players connected to us
    if( !defined( $hash->{READINGS}{players}{VAL} ) ) {
	$hash->{READINGS}{players}{VAL} = "?";
	$hash->{READINGS}{players}{TIME} = $tn; 
    }

    # number of players connected to mysqueezebox
    if( !defined( $hash->{READINGS}{players_mysb}{VAL} ) ) {
	$hash->{READINGS}{players_mysb}{VAL} = "?";
	$hash->{READINGS}{players_mysb}{TIME} = $tn; 
    }

    # number of players connected to other servers in our network
    if( !defined( $hash->{READINGS}{players_other}{VAL} ) ) {
	$hash->{READINGS}{players_other}{VAL} = "?";
	$hash->{READINGS}{players_other}{TIME} = $tn; 
    }

    # number of albums in the database
    if( !defined( $hash->{READINGS}{db_albums}{VAL} ) ) {
	$hash->{READINGS}{db_albums}{VAL} = "?";
	$hash->{READINGS}{db_albums}{TIME} = $tn; 
    }

    # number of artists in the database
    if( !defined( $hash->{READINGS}{db_artists}{VAL} ) ) {
	$hash->{READINGS}{db_artists}{VAL} = "?";
	$hash->{READINGS}{db_artists}{TIME} = $tn; 
    }

    # number of songs in the database
    if( !defined( $hash->{READINGS}{db_songs}{VAL} ) ) {
	$hash->{READINGS}{db_songs}{VAL} = "?";
	$hash->{READINGS}{db_songs}{TIME} = $tn; 
    }

    # number of genres in the database
    if( !defined( $hash->{READINGS}{db_genres}{VAL} ) ) {
	$hash->{READINGS}{db_genres}{VAL} = "?";
	$hash->{READINGS}{db_genres}{TIME} = $tn; 
    }

    # initialize the command stack
    $SB_SERVER_CmdStack{$name}{first_n} = 0;
    $SB_SERVER_CmdStack{$name}{last_n} = 0;
    $SB_SERVER_CmdStack{$name}{cnt} = 0;

    # assign our IO Device
    $hash->{DeviceName} = "$hash->{IP}:$hash->{CLIPORT}";
    
    # open the IO device
    my $ret = DevIo_OpenDev($hash, 0, "SB_SERVER_DoInit" );

    # do and update of the status
    InternalTimer( gettimeofday() + 10, 
		   "SB_SERVER_DoInit", 
		   $hash, 
		   0 );

    Log3( $hash, 4, "SB_SERVER_Define: leaving" );

    return $ret;
}


# ----------------------------------------------------------------------------
#  called when deleting a module
# ----------------------------------------------------------------------------
sub SB_SERVER_Undef( $$ ) {
    my ($hash, $arg) = @_;
    my $name = $hash->{NAME};
    
    Log3( $hash, 4, "SB_SERVER_Undef: called" );
    
    # no idea what this is for. Copied from 10_TCM.pm
    # presumably to notify the clients, that the server is gone
    foreach my $d (sort keys %defs) {
	if( ( defined( $defs{$d} ) ) && 
	    ( defined( $defs{$d}{IODev} ) ) &&
	    ( $defs{$d}{IODev} == $hash ) ) {
	    delete $defs{$d}{IODev};
	}
    }
    
    # terminate the CLI session
    DevIo_SimpleWrite( $hash, "listen 0\n", 0 );
    DevIo_SimpleWrite( $hash, "exit\n", 0 );

    # close the device
    DevIo_CloseDev( $hash ); 
    
    # remove all timers we created
    RemoveInternalTimer( $hash );
    
    return( undef );
}

# ----------------------------------------------------------------------------
#  Shutdown function - called before fhem shuts down
# ----------------------------------------------------------------------------
sub SB_SERVER_Shutdown( $$ ) {
    my ($hash, $dev) = @_;
    
    Log3( $hash, 4, "SB_SERVER_Shutdown: called" );

    # terminate the CLI session
    DevIo_SimpleWrite( $hash, "listen 0\n", 0 );
    DevIo_SimpleWrite( $hash, "exit\n", 0 );

    # close the device
    DevIo_CloseDev( $hash ); 

    # remove all timers we created
    RemoveInternalTimer( $hash );

    return( undef );
}


# ----------------------------------------------------------------------------
#  ReadyFn - called when?
# ----------------------------------------------------------------------------
sub SB_SERVER_Ready( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_Ready: called" );

    # we need to re-open the device
    if( $hash->{STATE} eq "disconnected" ) {
	if( ( ReadingsVal( $name, "power", "on" ) eq "on" ) ||
	    ( ReadingsVal( $name, "power", "on" ) eq "?" ) ) {
	    # obviously the first we realize the Server is off
	    # clean up first
	    RemoveInternalTimer( $hash );
	    readingsSingleUpdate( $hash, "power", "off", 1 );

	    # and signal to our clients
	    SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
	}

	if( $hash->{TCPDev} ) {
	    SB_SERVER_DoInit( $hash );
	}
    }

    return( DevIo_OpenDev( $hash, 1, "SB_SERVER_DoInit" ) );
}


# ----------------------------------------------------------------------------
#  Get functions 
# ----------------------------------------------------------------------------
sub SB_SERVER_Get( $@ ) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};
    
    Log3( $hash, 4, "SB_SERVER_Get: called" );

    if( @a != 2 ) {
	return( "\"get $name\" needs one parameter" );
    }

    return( "?" );
}


# ----------------------------------------------------------------------------
#  Attr functions 
# ----------------------------------------------------------------------------
sub SB_SERVER_Attr( @ ) {
    my $cmd = shift( @_ );
    my $name = shift( @_ );
    my @args = @_;

    Log( 1, "SB_SERVER_Attr: called with @args" );

    if( $cmd eq "set" ) {
	if( $args[ 0 ] eq "alivetimer" ) {

	}
    }
    
    # do an update of the status
#    InternalTimer( gettimeofday() + AttrVal( $name, "alivetimer", 120 ),
#		   "SB_SERVER_Alive", 
#		   $hash, 
#		   0 );
}


# ----------------------------------------------------------------------------
#  Set function
# ----------------------------------------------------------------------------
sub SB_SERVER_Set( $@ ) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};

    if( @a < 2 ) {
	return( "at least one parameter is needed" ) ;
    }

    $name = shift( @a );
    my $cmd = shift( @a );

    if( $cmd eq "?" ) {
	# this one should give us a drop down list
	my $res = "Unknown argument ?, choose one of " . 
	    "on renew:noArg abort:noArg cliraw statusRequest:noArg ";
	$res .= "rescan:full,playlists ";

	return( $res );

    } elsif( $cmd eq "on" ) {
	if( ReadingsVal( $name, "power", "off" ) eq "off" ) {
	    # the server is off, try to reactivate it
	    if( $hash->{WOLNAME} ne "none" ) {
		fhem( "set $hash->{WOLNAME} on" );
	    }
	    if( $hash->{RCCNAME} ne "none" ) {
		fhem( "set $hash->{RCCNAME} on" );
	    }

	} elsif( $cmd eq "renew" ) {
	    Log3( $hash, 5, "SB_SERVER_Set: renew" );
	    DevIo_SimpleWrite( $hash, "listen 1\n", 0 );

	} elsif( $cmd eq "abort" ) {
	    DevIo_SimpleWrite( $hash, "listen 0\n", 0 );

	} elsif( $cmd eq "statusRequest" ) {
	    DevIo_SimpleWrite( $hash, "serverstatus 0 200\n", 0 );

	} elsif( $cmd eq "cliraw" ) {
	    # write raw messages to the CLI interface per player
	    my $v = join( " ", @a );
	    $v .= "\n";	
	    Log3( $hash, 5, "SB_SERVER_Set: cliraw: $v " ); 
	    IOWrite( $hash, $v );

	} elsif( $cmd eq "rescan" ) {
	    IOWrite( $hash, $cmd . " " . $a[ 0 ] . "\n" );

	} else {
	    ;
	}

	return( undef );
    }
}

# ----------------------------------------------------------------------------
# Read
# called from the global loop, when the select for hash->{FD} reports data
# ----------------------------------------------------------------------------
sub SB_SERVER_Read( $ ) {
    my ($hash) = @_;

    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );
    Log3( $hash, 5, "New Squeezebox Server Read cycle starts here" );
    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );
    Log3( $hash, 5, "SB_SERVER_Read: called" );

    my $buf = DevIo_SimpleRead( $hash );

    if( !defined( $buf ) ) {
	return( "" );
    }

    my $name = $hash->{NAME};

    # if we have data, the server is on again
    if( ReadingsVal( $name, "power", "off" ) ne "on" ) {
	readingsSingleUpdate( $hash, "power", "on", 1 );
	if( defined( $SB_SERVER_CmdStack{$name}{cnt} ) ) {
	    my $maxmsg = $SB_SERVER_CmdStack{$name}{cnt};
	    my $out;
	    for( my $n = 0; $n <= $maxmsg; $n++ ) {
		$out = SB_SERVER_CMDStackPop( $hash );
		if( $out ne "empty" ) {
		    DevIo_SimpleWrite( $hash, $out , 0 );
		}	    
	    }
	}


	Log3( $hash, 5, "SB_SERVER_Read($name): please implelement the " .
	      "sending of the CMDStack." );
    }

    # if there are remains from the last time, append them now
    $buf = $hash->{PARTIAL} . $buf;

    $buf = uri_unescape( $buf );
    Log3( $hash, 6, "SB_SERVER_Read: the buf: $buf" );


    # if we have received multiline commands, they are split by \n
    my @cmds = split( "\n", $buf );

    # check for last element in string
    my $lastchr = substr( $buf, -1, 1 );
    if( $lastchr ne "\n" ) {
	#ups, the return doesn't seem to be complete
	$hash->{PARTIAL} = $cmds[ $#cmds ];
	# and remove the last element
	pop( @cmds );
	Log3( $hash, 5, "SB_SERVER_Read: uncomplete command received" );
    } else {
	Log3( $hash, 5, "SB_SERVER_Read: complete command received" );
	$hash->{PARTIAL} = "";
    }

    # and dispatch the rest
    foreach( @cmds ) {
	# double check complete line
	my $lastchar = substr( $_, -1);
	SB_SERVER_DispatchCommandLine( $hash, $_  );
    }

    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );
    Log3( $hash, 5, "Squeezebox Server Read cycle ends here" );
    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );

    return( undef );
}


# ----------------------------------------------------------------------------
# called by the clients to send data
# ----------------------------------------------------------------------------
sub SB_SERVER_Write( $$$ ) {
    my ( $hash, $fn, $msg ) = @_;
    my $name = $hash->{NAME};

    if( !defined( $fn ) ) {
	return( undef );
    }

    Log3( $hash, 4, "SB_SERVER_Write($name): called with FN:$fn" );

    if( defined( $msg ) ) {
	Log3( $hash, 4, "SB_SERVER_Write: MSG:$msg" );
    }

    if( ReadingsVal( $name, "serversecure", "0" ) eq "1" ) {
	if( ( $hash->{USERNAME} ne "?" ) && ( $hash->{PASSWORD} ne "?" ) ) {
	    # we need to send username and passord first
	} else {
	    my $retmsg = "SB_SERVER_Write: Server needs username and " . 
		"password but you did not specify those. No sending";	
	    Log3( $hash, 1, $retmsg );
	    return( $retmsg );
	}
    }

    if( ReadingsVal( $name, "power", "on" ) eq "on" ) {
	DevIo_SimpleWrite( $hash, "$fn", 0 );
    } else {
	# we are off, so save the command for later
	# if maxcmdstack is 0, the function is turned off
	if( AttrVal( $name, "maxcmdstack", 100 ) > 0 ) {
	    SB_SERVER_CMDStackPush( $hash, $fn );
	}
    }

}


# ----------------------------------------------------------------------------
#  Initialisation of the CLI connection
# ----------------------------------------------------------------------------
sub SB_SERVER_DoInit( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_DoInit: called" );

    if( !$hash->{TCPDev} ) {
	Log3( $hash, 5, "SB_SERVER_DoInit: no TCPDev available?" );
    }

    if( $hash->{STATE} eq "disconnected" ) {
	# server is off after FHEM start, broadcast to clients
	SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
	return( "" );
    }

    # subscribe us
    DevIo_SimpleWrite( $hash, "listen 1\n", 0 );

    # and get some info on the server
    DevIo_SimpleWrite( $hash, "pref authorize ?\n", 0 );
    DevIo_SimpleWrite( $hash, "version ?\n", 0 );
    DevIo_SimpleWrite( $hash, "serverstatus 0 200\n", 0 );
    DevIo_SimpleWrite( $hash, "favorites items 0 " . 
		       AttrVal( $name, "maxfavorites", 100 ) . "\n", 0 );

    # start the alive checking mechanism
    readingsSingleUpdate( $hash, "alivecheck", "?", 0 );
    InternalTimer( gettimeofday() + AttrVal( $name, "alivetimer", 120 ),
		   "SB_SERVER_Alive", 
		   $hash, 
		   0 );

    return( undef );
}


# ----------------------------------------------------------------------------
#  Dispatch every single line of commands
# ----------------------------------------------------------------------------
sub SB_SERVER_DispatchCommandLine( $$ ) {
    my ( $hash, $buf ) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_DispatchCommandLine($name): Line:$buf..." );

    # try to extract the first answer to the SPACE
    my $indx = index( $buf, " " );
    my $id1  = substr( $buf, 0, $indx );

    # is the first return value a player ID? 
    # Player ID is MAC adress, hence : included
    my @id = split( ":", $id1 );

    if( @id > 1 ) {
	# we have received a return for a dedicated player

	# create the fhem specific unique id
	my $playerid = join( "", @id );
	Log3( $hash, 5, "SB_SERVER_DispatchCommandLine: fhem-id: $playerid" );
	
	# create the commands
	my $cmds = substr( $buf, $indx + 1 );
	Log3( $hash, 5, "SB_SERVER__DispatchCommandLine: commands: $cmds" );
	Dispatch( $hash, "SB_PLAYER:$playerid:$cmds", undef );

    } else {
	# that is a server specific command
	SB_SERVER_ParseCmds( $hash, $buf );
    }

    return( undef );
}


# ----------------------------------------------------------------------------
#  parse the server answers that are not intended for players
# ----------------------------------------------------------------------------
sub SB_SERVER_ParseCmds( $$ ) {
    my ( $hash, $instr ) = @_;

    my $name = $hash->{NAME};

    my @args = split( " ", $instr );

    $hash->{LASTANSWER} = "@args";

    my $cmd = shift( @args );

    if( $cmd eq "version" ) {
	readingsSingleUpdate( $hash, "serverversion", $args[ 1 ], 0 );

	if( ReadingsVal( $name, "power", "off" ) eq "off" ) {
	    # that also means the server returned from being away
	    readingsSingleUpdate( $hash, "power", "on", 1 );
	    # signal our players
	    SB_SERVER_Broadcast( $hash, "SERVER", "ON" );
	}

    } elsif( $cmd eq "pref" ) {
	if( $args[ 0 ] eq "authorize" ) {
	    readingsSingleUpdate( $hash, "serversecure", $args[ 1 ], 0 );
	}

    } elsif( $cmd eq "fhemalivecheck" ) {
	readingsSingleUpdate( $hash, "alivecheck", "received", 0 );
	Log3( $hash, 4, "SB_SERVER_ParseCmds($name): alivecheck received" );

    } elsif( $cmd eq "favorites" ) {
	if( $args[ 0 ] eq "changed" ) {
	    Log3( $hash, 4, "SB_SERVER_ParseCmds($name): favorites changed" );
	    # we need to trigger the favorites update here
	    DevIo_SimpleWrite( $hash, "favorites items 0 " . 
			       AttrVal( $name, "maxfavorites", 100 ) . 
			       "\n", 0 );
	} elsif( $args[ 0 ] eq "items" ) {
	    Log3( $hash, 4, "SB_SERVER_ParseCmds($name): favorites items" );
	    # the response to our query of the favorites
	    SB_SERVER_FavoritesParse( $hash, join( " ", @args ) );	    
	} else {
	}

    } elsif( $cmd eq "serverstatus" ) {
	Log3( $hash, 4, "SB_SERVER_ParseCmds($name): server status" );
	SB_SERVER_ParseServerStatus( $hash, \@args );

    } else {
	# unkown
    }
}


# ----------------------------------------------------------------------------
#  Alivecheck of the server
# ----------------------------------------------------------------------------
sub SB_SERVER_Alive( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_Alive($name): called" );

    if( AttrVal( $name, "doalivecheck", "false" ) eq "false" ) {
	Log3( $hash, 5, "SB_SERVER_Alive($name): alivechecking is off" );
	return;
    }

    # let's ping the server to figure out if he is reachable
    # needed for servers that go in hibernate mode
    my $p = Net::Ping->new( 'tcp' );
    if( $p->ping( $hash->{IP}, 2 ) ) {
	# host is reachable so go on normally
	if( ReadingsVal( $name, "power", "on" ) eq "off" ) {
	    Log3( $hash, 5, "SB_SERVER_Alive($name): ping succesful. " . 
		  "SB-Server is back again." );
	    # first time we realized server is away
	    DevIo_OpenDev( $hash, 1, "SB_SERVER_DoInit" );
	    readingsSingleUpdate( $hash, "power", "on", 1 );
	    readingsSingleUpdate( $hash, "alivecheck", "?", 0 );
	    # signal that to our clients
	    SB_SERVER_Broadcast( $hash, "SERVER",  "ON" );
	}

	if( ReadingsVal( $name, "alivecheck", "received" ) eq "waiting" ) {
	    # ups, we did not receive any answer in the last minutes
	    # SB Server potentially dead or shut-down
	    Log3( $hash, 5, "SB_SERVER_Alive($name): overrun SB-Server dead." );

	    readingsSingleUpdate( $hash, "power", "off", 1 );
	    readingsSingleUpdate( $hash, "alivecheck", "?", 0 );

	    # signal that to our clients
	    SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );

	    # close the device
	    DevIo_CloseDev( $hash ); 

	    # remove all timers we created
	    RemoveInternalTimer( $hash );
	} else {
	    # just send something to the SB-Server. It will echo it
	    # if we receive the echo, the server is still alive
	    DevIo_SimpleWrite( $hash, "fhemalivecheck\n", 0 );
	    
	    readingsSingleUpdate( $hash, "alivecheck", "waiting", 0 );
	}

    } else {
	# the server is away and therefore presumably in hibernate / suspend
	Log3( $hash, 5, "SB_SERVER_Alive($name): ping timeout. " . 
	      "SB-Server in hibernate / suspend?." );

	if( ReadingsVal( $name, "power", "off" ) eq "on" ) {
	    # first time we realized server is away
	    readingsSingleUpdate( $hash, "power", "off", 1 );
	    readingsSingleUpdate( $hash, "alivecheck", "?", 0 );

	    # signal that to our clients
	    SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );

	    # close the device
	    DevIo_CloseDev( $hash ); 
	    # remove all timers we created
	    RemoveInternalTimer( $hash );
	}

    }
	
    # close our ping mechanism again
    $p->close( );

    # do an update of the status
    InternalTimer( gettimeofday() + AttrVal( $name, "alivetimer", 120 ),
		   "SB_SERVER_Alive", 
		   $hash, 
		   0 );
}


# ----------------------------------------------------------------------------
#  Broadcast a message to all clients
# ----------------------------------------------------------------------------
sub SB_SERVER_Broadcast( $$@ ) {
    my( $hash, $cmd, $msg, $bin ) = @_;
    my $name = $hash->{NAME};
    my $iodevhash;

    Log3( $hash, 4, "SB_SERVER_Broadcast: called" );

    if( !defined( $bin ) ) {
	$bin = 0;
    }

    foreach my $mydev ( keys %defs ) {
	# the hash to the IODev as defined at the client
	if( defined( $defs{$mydev}{IODev} ) ) {
	    $iodevhash = $defs{$mydev}{IODev};
	} else {
	    $iodevhash = undef;
	}

	if( defined( $iodevhash ) ) {
	    if( ( defined( $defs{$mydev}{TYPE} ) ) && 
		( defined( $iodevhash->{NAME} ) ) ){

		if( ( $defs{$mydev}{TYPE} eq "SB_PLAYER" ) &&
		    ( $iodevhash->{NAME} eq $name ) ) {
		    # we found a valid entry
		    my $clienthash = $defs{$mydev};
		    my $namebuf = $clienthash->{NAME};
		    
		    SB_PLAYER_RecBroadcast( $clienthash, $cmd, $msg, $bin );
		}
	    }
	} 
    }
    
    return;
}


# ----------------------------------------------------------------------------
#  Handle the return for a serverstatus query
# ----------------------------------------------------------------------------
sub SB_SERVER_ParseServerStatus( $$ ) {
    my( $hash, $dataptr ) = @_;
    
    my $name = $hash->{NAME};
    
    # typically the start index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
	shift( @{$dataptr} );
    } else {
	Log3( $hash, 5, "SB_SERVER_ParseServerStatus($name): entry is " .
	      "not the start number" );
	return;
    }

    # typically the max index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
	shift( @{$dataptr} );
    } else {
	Log3( $hash, 5, "SB_SERVER_ParseServerStatus($name): entry is " .
	      "not the end number" );
	return;
    }

    my $datastr = join( " ", @{$dataptr} );
    # replace funny stuff
    $datastr =~ s/info total albums/infototalalbums/g;
    $datastr =~ s/info total artists/infototalartists/g;
    $datastr =~ s/info total songs/infototalsongs/g;
    $datastr =~ s/info total genres/infototalgenres/g;
    $datastr =~ s/sn player count/snplayercount/g;
    $datastr =~ s/other player count/otherplayercount/g;
    $datastr =~ s/player count/playercount/g;

    Log3( $hash, 5, "SB_SERVER_ParseServerStatus($name): data to parse: " .
	  $datastr );

    my @data1 = split( " ", $datastr );

    # the rest of the array should now have the data, we're interested in
    readingsBeginUpdate( $hash );

    # set default values for stuff not always send
    readingsBulkUpdate( $hash, "scanning", "no" );
    readingsBulkUpdate( $hash, "scandb", "?" );
    readingsBulkUpdate( $hash, "scanprogressdone", "0" );
    readingsBulkUpdate( $hash, "scanprogresstotal", "0" );
    readingsBulkUpdate( $hash, "scanlastfailed", "none" );

    my $addplayers = true;
    my %players;
    my $currentplayerid = "none";

    # needed for scanning the MAC Adress
    my $d = "[0-9A-Fa-f]";
    my $dd = "$d$d";

    # needed for scanning the IP adress
    my $e = "[0-9]";
    my $ee = "$e$e";

    foreach( @data1 ) {
	if( $_ =~ /^(lastscan:)([0-9]*)/ ) {
	    # we found the lastscan entry
	    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = 
		localtime( $2 );
	    $year = $year + 1900;
	    readingsBulkUpdate( $hash, "scan_last", "$mday-$mon-$year " . 
				"$hour:$min:$sec" );
	    next;
	} elsif( $_ =~ /^(scanning:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "scanning", $2 );
	    next;
	} elsif( $_ =~ /^(version:)([0-9\.]*)/ ) {
	    readingsBulkUpdate( $hash, "serverversion", $2 );
	    next;
	} elsif( $_ =~ /^(playercount:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "players", $2 );
	    next;
	} elsif( $_ =~ /^(snplayercount:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "players_mysb", $2 );
	    $currentplayerid = "none";
	    $addplayers = false;
	    next;
	} elsif( $_ =~ /^(otherplayercount:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "players_other", $2 );
	    $currentplayerid = "none";
	    $addplayers = false;
	    next;
	} elsif( $_ =~ /^(infototalalbums:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "db_albums", $2 );
	    next;
	} elsif( $_ =~ /^(infototalartists:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "db_artists", $2 );
	    next;
	} elsif( $_ =~ /^(infototalsongs:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "db_songs", $2 );
	    next;
	} elsif( $_ =~ /^(infototalgenres:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "db_genres", $2 );
	    next;
	} elsif( $_ =~ /^(playerid:)($dd[:|-]$dd[:|-]$dd[:|-]$dd[:|-]$dd[:|-]$dd)/ ) {
	    my $id = join( "", split( ":", $2 ) );
	    if( $addplayers = true ) {
		$players{$id}{ID} = $id;
		$players{$id}{MAC} = $2;
		$currentplayerid = $id;
	    }
	    next;
	} elsif( $_ =~ /^(name:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{name} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(displaytype:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{displaytype} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(model:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{model} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(power:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{power} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(canpoweroff:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{canpoweroff} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(connected:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{connected} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(isplayer:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{isplayer} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(ip:)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{3,5})/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{IP} = $2;
	    }
	    next;
	} elsif( $_ =~ /^(seq_no:)(.*)/ ) {
	    # just to take care of the keyword
	    next;
	} else {
	    # no keyword found, so let us assume it is part of the player name
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{name} .= $_;
	    }

	}
    }

    readingsEndUpdate( $hash, 1 );

    foreach my $player ( keys %players ) {
	if( defined( $players{$player}{isplayer} ) ) {
	    if( $players{$player}{isplayer} eq "0" ) {
		Log3( $hash, 1, "not a player" );
		next;
	    }
	}

	# if the player is not yet known, it will be created
	if( defined( $players{$player}{ID} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:NONE", undef );
	} else {
	    Log3( $hash, 1, "not defined" );
	    next;
	}

	if( defined( $players{$player}{name} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "name $players{$player}{name}", undef );
	}

	if( defined( $players{$player}{IP} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "player ip $players{$player}{IP}", undef );
	}

	if( defined( $players{$player}{model} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "player model $players{$player}{model}", undef );
	}

	if( defined( $players{$player}{canpoweroff} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "player canpoweroff $players{$player}{canpoweroff}", 
		      undef );
	}

	if( defined( $players{$player}{power} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "power $players{$player}{power}", undef );
	}

	if( defined( $players{$player}{connected} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "connected $players{$player}{connected}", undef );
	}

	if( defined( $players{$player}{displaytype} ) ) {
	    Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" . 
		      "displaytype $players{$player}{displaytype}", undef );
	}
    }

    return;
}


# ----------------------------------------------------------------------------
#  Parse the return values of the favorites items
# ----------------------------------------------------------------------------
sub SB_SERVER_FavoritesParse( $$ ) {
    my ( $hash, $str ) = @_;
    
    my $name = $hash->{NAME};

    # flush the existing list
    foreach my $titi ( keys %{$favorites{$name}} ) {
	delete( $favorites{$name}{$titi} );
    }

    # split up the string we got
    my @data = split( " ", $str );

    # eliminate the first entries of the response
    # some more comment
    # typically 'items'
    if( $data[ 0 ] =~ /^(items)*/ ) {
	my $notneeded = shift( @data );
    } 
    
    # typically the start index being a number
    if( $data[ 0 ] =~ /^([0-9])*/ ) {
	my $notneeded = shift( @data );
    }

    # typically the start index being a number
    my $maxwanted = 100;
    if( $data[ 0 ] =~ /^([0-9])*/ ) {
	$maxwanted = int( shift( @data ) );
    }

    # find the maximum number of favorites. That is typically at the 
    # end of the server response. So check there first
    my $totals = 0;
    my $lastdata = $data[ $#data ];
    if( $lastdata =~ /^(count:)([0-9]*)/ ) {
	$totals = $2;
	# remove the last element from the array
	pop( @data );
    } else {
	my $i = 0;
	my $delneeded = false;
	foreach( @data ) {
	    if( $_ =~ /^(count:)([0-9]*)/ ) {
		$totals = $2;
		$delneeded = true;
		last;
	    } else {
		$i++;
	    }
	    
	    # delete the element from the list
	    if( $delneeded == true ) {
		splice( @data, $i, 1 );
	    }
	}
    }
    readingsSingleUpdate( $hash, "favoritestotal", $totals, 0 );


    my $favname = "";
    if( $data[ 0 ] =~ /^(title:)(.*)/ ) {
	$favname = $2;
	shift( @data );
    }
    readingsSingleUpdate( $hash, "favoritesname", $favname, 0 );

    # check if we got all the favoites with our response
    if( $totals > $maxwanted ) {
	# we asked for too less data, there are more favorites defined
    }

    # treat the rest of the string
    my $namestarted = false;
    my $firstone = true;

    my $namebuf = "";
    my $idbuf = "";
    my $hasitemsbuf = false;
    my $isaudiobuf = "";

    foreach ( @data ) {
	if( $_ =~ /^(id:|ID:)([A-Za-z0-9\.]*)/ ) {
	    # we found an ID, that is typically the start of a new session
	    # so save the old session first
	    if( $firstone == false ) {
		if( $hasitemsbuf == false ) {
		    # derive our hash entry
		    my $entryuid = SB_SERVER_FavoritesName2UID( $namebuf );
		    $favorites{$name}{$entryuid} = {
			ID => $idbuf,
			Name => $namebuf, };
		    $namebuf = "";
		    $isaudiobuf = "";
		    $hasitemsbuf = false;
		} else {
		    # that is a folder we found, but we don't handle that
		}	   
	    }

	    $firstone = false;
	    $idbuf = $2;

	    # if there has been a name found before, end it now
	    if( $namestarted == true ) {
		$namestarted = false;
	    }

	} elsif( $_ =~ /^(isaudio:)([0|1]?)/ ) {
	    $isaudiobuf = $2;
	    if( $namestarted == true ) {
		$namestarted = false;
	    }

	} elsif( $_ =~ /^(hasitems:)([0|1]?)/ ) {
	    if( int( $2 ) == 0 ) { 
		$hasitemsbuf = false;
	    } else {
		$hasitemsbuf = true;
	    }

	    if( $namestarted == true ) {
		$namestarted = false;
	    }

	} elsif( $_ =~ /^(type:)([a|u|d|i|o]*)/ ) {
	    if( $namestarted == true ) {
		$namestarted = false;
	    }

	} elsif( $_ =~ /^(name:)([0-9a-zA-Z]*)/ ) {
	    $namebuf = $2;
	    $namestarted = true;

	} else {
	    # no regexp matched, so it must be part of the name
	    if( $namestarted == true ) {
		$namebuf .= " " . $_;
	    }
	}
    }

    # capture the last element also
    if( ( $namebuf ne "" ) && ( $idbuf ne "" ) ) {
	if( $hasitemsbuf == false ) {
	    my $entryuid = join( "", split( " ", $namebuf ) );
	    $favorites{$name}{$entryuid} = {
		ID => $idbuf,
		Name => $namebuf, };
	} else {
	    # that is a folder we found, but we don't handle that
	}
    }

    # make all client create e new favorites list
    SB_SERVER_Broadcast( $hash, "FAVORITES",  
			 "FLUSH dont care", undef );

    # find all the names and broadcast to our clients
    $favsetstring = "favorites:";
    foreach my $titi ( keys %{$favorites{$name}} ) {
	Log3( $hash, 5, "SB_SERVER_ParseFavorites($name): " . 
	      "ID:" .  $favorites{$name}{$titi}{ID} . 
	      " Name:" . $favorites{$name}{$titi}{Name} . "$titi" );
	$favsetstring .= "$titi,";
	SB_SERVER_Broadcast( $hash, "FAVORITES",  
			     "ADD $name $favorites{$name}{$titi}{ID} " . 
			     "$titi", undef );
    }
    #chop( $favsetstring );
    #$favsetstring .= " ";
}


# ----------------------------------------------------------------------------
#  generate a UID for the hash entry from the name
# ----------------------------------------------------------------------------
sub SB_SERVER_FavoritesName2UID( $ ) {
    my $namestr = shift( @_ );

    # eliminate spaces
    $namestr = join( "", split( " ", $namestr ) );

    # this defines the regexp. Please add new stuff with the seperator |
    my $tobereplaced = '[Ä|ä|Ö|öÜ|ü|\[|\]|\{|\}|\(|\)|\\\\|' . 
	'\/|\'|\.|\"|\^|°|\$|\||%|@]|Ã¼|&';

    $namestr =~ s/$tobereplaced//g;

    return( $namestr );
}

# ----------------------------------------------------------------------------
#  push a command to the buffer
# ----------------------------------------------------------------------------
sub SB_SERVER_CMDStackPush( $$ ) {
    my ( $hash, $cmd ) = @_;

    my $name = $hash->{NAME};

    my $n = $SB_SERVER_CmdStack{$name}{last_n};

    if( $n > AttrVal( $name, "maxcmdstack", 200 ) ) {
	Log3( $hash, 5, "SB_SERVER_CMDStackPush($name): limit reached" );
	return;
    }

    $SB_SERVER_CmdStack{$name}{$n} = $cmd;

    $n = $n + 1;

    $SB_SERVER_CmdStack{$name}{last_n} = $n;

    # update overall number of entries
    $SB_SERVER_CmdStack{$name}{cnt} = $SB_SERVER_CmdStack{$name}{last_n} - 
	$SB_SERVER_CmdStack{$name}{first_n} + 1;
}

# ----------------------------------------------------------------------------
#  pop a command from the buffer
# ----------------------------------------------------------------------------
sub SB_SERVER_CMDStackPop( $ ) {
    my ( $hash ) = @_;
    
    my $name = $hash->{NAME};
    
    my $n = $SB_SERVER_CmdStack{$name}{first_n};
    
    my $res = "";
    # return the first element of the list
    if( defined( $SB_SERVER_CmdStack{$name}{$n} ) ) {
	$res = $SB_SERVER_CmdStack{$name}{$n};
    } else {
	$res = "empty";
    }

    # and now remove the first element
    
    delete( $SB_SERVER_CmdStack{$name}{$n} );
    
    $n = $n + 1;
    
    if ( $n <= $SB_SERVER_CmdStack{$name}{first_n} ) {
	$SB_SERVER_CmdStack{$name}{first_n} = $n;
	# update overall number of entries
	$SB_SERVER_CmdStack{$name}{cnt} = $SB_SERVER_CmdStack{$name}{last_n} - 
	    $SB_SERVER_CmdStack{$name}{first_n} + 1;
    } else {
	# end of list reached
	$SB_SERVER_CmdStack{$name}{last_n} = 0;
	$SB_SERVER_CmdStack{$name}{first_n} = 0;
	$SB_SERVER_CmdStack{$name}{cnt} = 0;
    }
    
    return( $res );
}


1;

=pod
    =begin html
    
    
    =end html
    =cut

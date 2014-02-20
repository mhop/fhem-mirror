# ############################################################################
#
#  FHEM Module for Squeezebox Players
#
# ############################################################################
#
#  used to interact with Squeezebox Player
#
# ############################################################################
# $Id$
# ############################################################################
#
#  This is absolutley open source. Please feel free to use just as you
#  like. Please note, that no warranty is given and no liability granted
#
# ############################################################################
#
#  we have the following readings
#  state            on / off / ?
#
# ############################################################################
#
#  we have the following attributes
#  timer            the time frequency how often we check
#  volumeStep       the volume delta when sending the up or down command
#  timeout          the timeout in seconds for the TCP connection
#
# ############################################################################
#  we have the following internals (all UPPERCASE)
#  PLAYERIP         the IP adress of the player in the network
#  PLAYERID         the unique identifier of the player. Mostly the MAC
#  SERVER           based on the IP and the port as given
#  IP               the IP of the server
#  PORT             the Port of the Server
#  CLIPORT          the port for the CLI interface of the server
#  PLAYERNAME       the name of the Player
#  CONNECTION       the connection status to the server
#  CANPOWEROFF      is the player supporting power off commands
#  MODEL            the model of the player
#  DISPLAYTYPE      what sort of display is there, if any
#
# ############################################################################

package main;
use strict;
use warnings;

use IO::Socket;
use URI::Escape;


# include this for the self-calling timer we use later on
use Time::HiRes qw(gettimeofday);

# the list of favorites
my %SB_PLAYER_Favs;


# ----------------------------------------------------------------------------
#  Initialisation routine called upon start-up of FHEM
# ----------------------------------------------------------------------------
sub SB_PLAYER_Initialize( $ ) {
    my ($hash) = @_;

    # the commands we provide to FHEM
    # installs the respecitive call-backs for FHEM. The call back in quotes 
    # must be realised as a sub later on in the file
    $hash->{DefFn}      = "SB_PLAYER_Define";
    $hash->{UndefFn}    = "SB_PLAYER_Undef";
    $hash->{ShutdownFn} = "SB_PLAYER_Shutdown";
    $hash->{SetFn}      = "SB_PLAYER_Set";
    $hash->{GetFn}      = "SB_PLAYER_Get";

    # for the two step approach
    $hash->{Match}     = "^SB_PLAYER:";
    $hash->{ParseFn}   = "SB_PLAYER_Parse";
    
    # the attributes we have. Space separated list of attribute values in 
    # the form name:default1,default2
    $hash->{AttrList}  = "volumeStep ttslanguage:de,en,fr ";
    $hash->{AttrList}  .= "ttslink ";
    $hash->{AttrList}  .= "donotnotify:true,false ";
    $hash->{AttrList}  .= "idismac:true,false ";
    $hash->{AttrList}  .= "serverautoon:true,false ";
    $hash->{AttrList}  .= "fadeinsecs ";
    $hash->{AttrList}  .= $readingFnAttributes;
}


# ----------------------------------------------------------------------------
#  Definition of a module instance
#  called when defining an element via fhem.cfg
# ----------------------------------------------------------------------------
sub SB_PLAYER_Define( $$ ) {
    my ( $hash, $def ) = @_;
    
    my $name = $hash->{NAME};
    
    my @a = split("[ \t][ \t]*", $def);
    
    # do we have the right number of arguments?
    if( @a != 3 ) {
	Log3( $hash, 1, "SB_PLAYER_Define: falsche Anzahl an Argumenten" );
	return( "wrong syntax: define <name> SB_PLAYER <playerid>" );
    }
    
    # needed for manual creation of the Player; autocreate checks in ParseFn
    if( SB_PLAYER_IsValidMAC( $a[ 2 ] ) == 1 ) {
	# the MAC adress is valid
	$hash->{PLAYERMAC} = $a[ 2 ];
    } else {
	my $msg = "SB_PLAYER_Define: playerid ist keine MAC Adresse " . 
	    "im Format xx:xx:xx:xx:xx:xx oder xx-xx-xx-xx-xx-xx";
	Log3( $hash, 1, $msg );
	return( $msg );
    }

    Log3( $hash, 5, "SB_PLAYER_Define successfully called" );

    # remove the : from the ID
    my @idbuf = split( ":", $hash->{PLAYERMAC} );
    my $uniqueid = join( "", @idbuf );

    # our unique id
    $hash->{FHEMUID} = $uniqueid;
    # do the alarms fade in
    $hash->{ALARMSFADEIN} = "?";
    # the number of alarms of the player
    $hash->{ALARMSCOUNT} = 2;

    # for the two step approach
    $modules{SB_PLAYER}{defptr}{$uniqueid} = $hash;
    AssignIoPort( $hash );

    # preset the internals
    # can the player power off
    $hash->{CANPOWEROFF} = "?";
    # graphical or textual display
    $hash->{DISPLAYTYPE} = "?";
    # which model do we see?
    $hash->{MODEL} = "?";
    # what's the ip adress of the player
    $hash->{PLAYERIP} = "?";
    # the name of the player as assigned by the server
    $hash->{PLAYERNAME} = "?";
    # the last alarm we did set
    $hash->{LASTALARM} = 1;
    # the reference to the favorites list
    $hash->{FAVREF} = " ";
    # the command for selecting a favorite
    $hash->{FAVSET} = "favorites";
    # the entry in the global hash table
    $hash->{FAVSTR} = "not,yet,defined ";
    # last received answer from the server
    $hash->{LASTANSWER} = "none";


    # preset the attributes
    if( !defined( $attr{$name}{volumeStep} ) ) {
	$attr{$name}{volumeStep} = 10;
    }

    if( !defined( $attr{$name}{fadeinsecs} ) ) {
	$attr{$name}{fadeinsecs} = 10;
    }

    if( !defined( $attr{$name}{donotnotify} ) ) {
	$attr{$name}{donotnotify} = "true";
    }

    if( !defined( $attr{$name}{ttslanguage} ) ) {
	$attr{$name}{ttslanguage} = "de";
    }

    if( !defined( $attr{$name}{idismac} ) ) {
	$attr{$name}{idismac} = "true";
    }

    if( !defined( $attr{$name}{ttslink} ) ) {
	$attr{$name}{ttslink} = "http://translate.google.com/translate_tts?";
    }

    if( !defined( $attr{$name}{serverautoon} ) ) {
	$attr{$name}{serverautoon} = "true";
    }

    # Preset our readings if undefined
    my $tn = TimeNow();

    # according to development guidelines of FHEM AV Module
    if( !defined( $hash->{READINGS}{presence}{VAL} ) ) {
	$hash->{READINGS}{presence}{VAL} = "?";
	$hash->{READINGS}{presence}{TIME} = $tn; 
    }

    # according to development guidelines of FHEM AV Module
    if( !defined( $hash->{READINGS}{power}{VAL} ) ) {
	$hash->{READINGS}{power}{VAL} = "?";
	$hash->{READINGS}{power}{TIME} = $tn; 
    }

    # the last unkown command
    if( !defined( $hash->{READINGS}{lastunkowncmd}{VAL} ) ) {
	$hash->{READINGS}{lastunkowncmd}{VAL} = "none";
	$hash->{READINGS}{lastunkowncmd}{TIME} = $tn; 
    }

    # the last unkown IR command
    if( !defined( $hash->{READINGS}{lastir}{VAL} ) ) {
	$hash->{READINGS}{lastir}{VAL} = "?";
	$hash->{READINGS}{lastir}{TIME} = $tn; 
    }

    # the id of the alarm we create
    if( !defined( $hash->{READINGS}{alarmid1}{VAL} ) ) {
	$hash->{READINGS}{alarmid1}{VAL} = "none";
	$hash->{READINGS}{alarmid1}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{alarmid2}{VAL} ) ) {
	$hash->{READINGS}{alarmid2}{VAL} = "none";
	$hash->{READINGS}{alarmid2}{TIME} = $tn; 
    }

    # values according to standard
    if( !defined( $hash->{READINGS}{playStatus}{VAL} ) ) {
	$hash->{READINGS}{playStatus}{VAL} = "?";
	$hash->{READINGS}{playStatus}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{currentArtist}{VAL} ) ) {
	$hash->{READINGS}{currentArtist}{VAL} = "?";
	$hash->{READINGS}{currentArtist}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{currentAlbum}{VAL} ) ) {
	$hash->{READINGS}{currentAlbum}{VAL} = "?";
	$hash->{READINGS}{currentAlbum}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{currentTitle}{VAL} ) ) {
	$hash->{READINGS}{currentTitle}{VAL} = "?";
	$hash->{READINGS}{currentTitle}{TIME} = $tn; 
    }

    # for the FHEM AV Development Guidelinses
    # we use this to store the currently playing ID to later on return to
    if( !defined( $hash->{READINGS}{currentMedia}{VAL} ) ) {
	$hash->{READINGS}{currentMedia}{VAL} = "?";
	$hash->{READINGS}{currentMedia}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{currentPlaylistName}{VAL} ) ) {
	$hash->{READINGS}{currentPlaylistName}{VAL} = "?";
	$hash->{READINGS}{currentPlaylistName}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{currentPlaylisturl}{VAL} ) ) {
	$hash->{READINGS}{currentPlaylistUrl}{VAL} = "?";
	$hash->{READINGS}{currentPlaylistUrl}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{volume}{VAL} ) ) {
	$hash->{READINGS}{volume}{VAL} = 0;
	$hash->{READINGS}{volume}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{volumeStraight}{VAL} ) ) {
	$hash->{READINGS}{volumeStraight}{VAL} = "?";
	$hash->{READINGS}{volumeStraight}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{connected}{VAL} ) ) {
	$hash->{READINGS}{connected}{VAL} = "?"; 
	$hash->{READINGS}{connected}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{signalstrength}{VAL} ) ) {
	$hash->{READINGS}{signalstrength}{VAL} = "?";
	$hash->{READINGS}{currentTitle}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{shuffle}{VAL} ) ) {
	$hash->{READINGS}{shuffle}{VAL} = "?";
	$hash->{READINGS}{currentTitle}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{repeat}{VAL} ) ) {
	$hash->{READINGS}{repeat}{VAL} = "?";
	$hash->{READINGS}{currentTitle}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{state}{VAL} ) ) {
	$hash->{READINGS}{state}{VAL} = "?"; 
	$hash->{READINGS}{state}{TIME} = $tn; 
    }

    # check our 

    # do and update of the status
    InternalTimer( gettimeofday() + 10, 
		   "SB_PLAYER_GetStatus", 
		   $hash, 
		   0 );

    return( undef );
}


# ----------------------------------------------------------------------------
#  called from the global dispatch if new data is available
# ----------------------------------------------------------------------------
sub SB_PLAYER_Parse( $$ ) {
    my ( $iohash, $msg ) = @_;

    # we expect the data to be in the following format
    # xxxxxxxxxxxx cmd1 cmd2 cmd3 ...
    # where xxxxxxxxxxxx is derived from xx:xx:xx:xx:xx:xx
    # that needs to be done by the server
    
    Log3( $iohash, 5, "SB_PLAYER_Parse: called with $msg" ); 

    # storing the last in an array is necessery, for tagged responses
    my ( $modtype, $id, @data ) = split(":", $msg, 3 );
    
    Log3( $iohash, 5, "SB_PLAYER_Parse: type:$modtype, ID:$id CMD:@data" ); 

    if( $modtype ne "SB_PLAYER" ) {
	# funny stuff happens at the disptach function
	Log3( $iohash, 5, "SB_PLAYER_Parse: wrong type given." );
    }

    # let's see what we got. Split the data at the space
    # necessery, for tagged responses
    my @args = split( " ", join( " ", @data ) );
    my $cmd = shift( @args );


    my $hash = $modules{SB_PLAYER}{defptr}{$id};
    if( !$hash ) {
	Log3( undef, 3, "SB_PLAYER Unknown device with ID $id, " . 
	      "please define it");

	# do the autocreate; derive the unique id (MAC adress)
	my @playermac = ( $id =~ m/.{2}/g );
	my $idbuf = join( ":", @playermac );

	Log3( undef, 3, "SB_PLAYER Dervived the following MAC $idbuf " );

	if( SB_PLAYER_IsValidMAC( $idbuf ) == 1 ) {
	    # the MAC Adress is valid
	    Log3( undef, 3, "SB_PLAYER_Parse: the unkown ID $id is a valid " . 
		  "MAC Adress" );
	    # this line supports autocreate
	    return( "UNDEFINED SB_PLAYER_$id SB_PLAYER $idbuf" );
	} else {
	    # the MAC adress is not valid
	    Log3( undef, 3, "SB_PLAYER_Parse: the unkown ID $id is NOT " . 
		  "a valid MAC Adress" );
	    return( undef );
	}
    }
    
    # so the data is for us
    my $name = $hash->{NAME};

    Log3( $hash, 5, "SB_PLAYER_Parse: $name CMD:$cmd ARGS:@args..." ); 

    # what ever we have received, signal it
    $hash->{LASTANSWER} = "$cmd @args";

    # signal the update to FHEM
    readingsBeginUpdate( $hash );

    if( $cmd eq "mixer" ) {
	if( $args[ 0 ] eq "volume" ) {
	    # update the volume 
            if ($args[ 1 ] eq "?") {
                 # it is a request
            } elsif( scalar( $args[ 1 ] ) > 0 ) {
		readingsSingleUpdate( $hash, "volume", 
				      scalar( $args[ 1 ] ), 0 );
	    } else {
		readingsSingleUpdate( $hash, "volume", 
				      "muted", 0 );
	    }
	    readingsSingleUpdate( $hash, "volumeStraight", 
				  scalar( $args[ 1 ] ), 0 );
	}

    } elsif( $cmd eq "play" ) {
	readingsSingleUpdate( $hash, "playStatus", "playing", 1 );

    } elsif( $cmd eq "stop" ) {
	readingsSingleUpdate( $hash, "playStatus", "stopped", 1 );

    } elsif( $cmd eq "pause" ) {
        if( $args[ 0 ] eq "0" ) {
            readingsSingleUpdate( $hash, "playStatus", "playing", 1 );
        } else {
            readingsSingleUpdate( $hash, "playStatus", "paused", 1 );
        } 

    } elsif( $cmd eq "mode" ) {
	#Log3( $hash, 1, "Playmode: $args[ 0 ]" );
	# alittle more complex to fulfill FHEM Development guidelines
	if( $args[ 0 ] eq "play" ) {
	    readingsSingleUpdate( $hash, "playStatus", "playing", 1 );
	} elsif( $args[ 0 ] eq "stop" ) {
	    readingsSingleUpdate( $hash, "playStatus", "stopped", 1 );
	} elsif( $args[ 0 ] eq "pause" ) {
	    readingsSingleUpdate( $hash, "playStatus", "paused", 1 );
	} else {
	    readingsSingleUpdate( $hash, "playStatus", $args[ 0 ], 1 );
	}

    } elsif( $cmd eq "newmetadata" ) {
	# the song has changed, but we are easy and just ask the player
	# sending the requests causes endless loop
	#IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
	#IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
	#IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );

    } elsif( $cmd eq "playlist" ) {
	if( $args[ 0 ] eq "newsong" ) {
	    # the song has changed, but we are easy and just ask the player
	    IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
	    IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
	    IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );

	    # the id is in the last return. ID not reported for radio stations
	    # so this will go wrong for e.g. Bayern 3 
	    if( $args[ $#args ] =~ /(^[0-9]{1,3})/g ) {
		readingsBulkUpdate( $hash, "currentMedia", $1 );
	    }
	} elsif( $args[ 0 ] eq "cant_open" ) {
	    #TODO: needs to be handled
	} elsif( $args[ 0 ] eq "open" ) {
	    $args[ 2 ] =~ /^(file:)(.*)/g;
	    if( defined( $2 ) ) {
		readingsBulkUpdate( $hash, "currentMedia", $2 );
	    }
	} elsif( $args[ 0 ] eq "repeat" ) {
	    if( $args[ 1 ] eq "0" ) {
		readingsBulkUpdate( $hash, "repeat", "off" );
	    } elsif( $args[ 1 ] eq "1") {
		readingsBulkUpdate( $hash, "repeat", "one" );
	    } elsif( $args[ 1 ] eq "2") {
		readingsBulkUpdate( $hash, "repeat", "all" );
	    } else {
		readingsBulkUpdate( $hash, "repeat", "?" );
	    }
	} elsif( $args[ 0 ] eq "shuffle" ) {
	    if( $args[ 1 ] eq "0" ) {
		readingsBulkUpdate( $hash, "shuffle", "off" );
	    } elsif( $args[ 1 ] eq "1") {
		readingsBulkUpdate( $hash, "shuffle", "song" );
	    } elsif( $args[ 1 ] eq "2") {
		readingsBulkUpdate( $hash, "shuffle", "album" );
	    } else {
		readingsBulkUpdate( $hash, "shuffle", "?" );
	    }
	} elsif( $args[ 0 ] eq "name" ) {
	    shift( @args );
	    readingsBulkUpdate( $hash, "currentPlaylistName", 
				join( " ", @args ) );
	} elsif( $args[ 0 ] eq "url" ) {
	    shift( @args );
	    readingsBulkUpdate( $hash, "currentPlaylistUrl", 
				join( " ", @args ) );

	} else {
	}
	# chekc if this caused going to play, as not send automatically
	IOWrite( $hash, "$hash->{PLAYERMAC} mode ?\n" );

    } elsif( $cmd eq "playlistcontrol" ) {
	#playlistcontrol cmd:load artist_id:22 count:4

    } elsif( $cmd eq "connected" ) {
	readingsBulkUpdate( $hash, "connected", $args[ 0 ] );
	readingsBulkUpdate( $hash, "presence", "present" );

    } elsif( $cmd eq "name" ) {
	$hash->{PLAYERNAME} = join( " ", @args );

    } elsif( $cmd eq "title" ) {
	readingsBulkUpdate( $hash, "currentTitle", join( " ", @args ) );

    } elsif( $cmd eq "artist" ) {
	readingsBulkUpdate( $hash, "currentArtist", join( " ", @args ) );

    } elsif( $cmd eq "album" ) {
	readingsBulkUpdate( $hash, "currentAlbum", join( " ", @args ) );

    } elsif( $cmd eq "player" ) {
	if( $args[ 0 ] eq "model" ) {
	    $hash->{MODEL} = $args[ 1 ];
	} elsif( $args[ 0 ] eq "canpoweroff" ) {
	    $hash->{CANPOWEROFF} = $args[ 1 ];
	} elsif( $args[ 0 ] eq "ip" ) {
	    $hash->{PLAYERIP} = "$args[ 1 ]";
	    if( defined( $args[ 2 ] ) ) {
		$hash->{PLAYERIP} .= ":$args[ 2 ]";
	    }
	    
	} else {
	}

    } elsif( $cmd eq "power" ) {
	if (!(@args)) {
	    # power toggle : should only happen when called with SB CLI
            if (ReadingsVal($hash->{NAME}, "state", "off") eq "on") {
                readingsSingleUpdate( $hash, "presence", "absent", 0 );
                readingsSingleUpdate( $hash, "state", "off", 1 );
                readingsSingleUpdate( $hash, "power", "off", 1 );
            } else {
                readingsSingleUpdate( $hash, "state", "on", 1 );
                readingsSingleUpdate( $hash, "power", "on", 1 );
            }
	} elsif( $args[ 0 ] eq "1" ) {
	    readingsSingleUpdate( $hash, "state", "on", 1 );
	    readingsSingleUpdate( $hash, "power", "on", 1 );
	} elsif( $args[ 0 ] eq "0" ) {
	    readingsSingleUpdate( $hash, "presence", "absent", 0 );
	    readingsSingleUpdate( $hash, "state", "off", 1 );
	    readingsSingleUpdate( $hash, "power", "off", 1 );
	} else {
	    # should be "?" normally
	}

    } elsif( $cmd eq "displaytype" ) {
	$hash->{DISPLAYTYPE} = $args[ 0 ];

    } elsif( $cmd eq "signalstrength" ) {
	if( $args[ 0 ] eq "0" ) {
	    readingsBulkUpdate( $hash, "signalstrength", "wired" );
	} else {
	    readingsBulkUpdate( $hash, "signalstrength", "$args[ 0 ]" );
	}
	
    } elsif( $cmd eq "alarm" ) {
	if( $args[ 0 ] eq "sound" ) {
	    # fired when an alarm goes off
	} elsif( $args[ 0 ] eq "end" ) {
	    # fired when an alarm ends
	} elsif( $args[ 0 ] eq "snooze" ) {
	    # fired when an alarm is snoozed by the user
	} elsif( $args[ 0 ] eq "snooze_end" ) {
	    # fired when an alarm comes back from snooze
	} elsif( $args[ 0 ] eq "add" ) {
	    # fired when an alarm has been added. 
	    # this setup goes wrong, when an alarm is defined manually
	    # the last entry in the array shall contain th id
	    my $idstr = $args[ $#args ];
	    if( $idstr =~ /^(id:)([0-9a-zA-Z\.]+)/g ) {
		readingsBulkUpdate( $hash, "alarmid$hash->{LASTALARM}", $2 );
	    } else {
	    }
	} else {
	}


    } elsif( $cmd eq "alarms" ) {
	SB_PLAYER_ParseAlarms( $hash, @args );

    } elsif( $cmd eq "showbriefly" ) {
	# to be ignored, we get two hashes

    } elsif( $cmd eq "unkownir" ) {
	readingsSingleUpdate( $hash, "lastir", $args[ 0 ], 1 );

    } elsif( $cmd eq "status" ) {
	# TODO
	Log3( $hash, 5, "SB_PLAYER_Parse($name): please implement the " . 
	      "parser for the status answer" );
    } elsif( $cmd eq "client" ) {
        # filter "client disconnect" and "client reconnect" messages 
    } elsif( $cmd eq "prefset" ) {
	if( $args[ 0 ] eq "server" ) {
	    if( $args[ 1 ] eq "currentSong" ) {
		readingsBulkUpdate( $hash, "currentMedia", $args[ 2 ] );
	    }
	} else {
	    readingsSingleUpdate( $hash, "lastunkowncmd", 
				  $cmd . " " . join( " ", @args ), 1 );
	}


    } elsif( $cmd eq "NONE" ) {
	# we shall never end up here, as cmd=NONE is used by the server for 
	# autocreate

    } else {
	# unkown command, we push it to the last command thingy
	readingsSingleUpdate( $hash, "lastunkowncmd", 
			      $cmd . " " . join( " ", @args ), 1 );
    }
    
    # and signal the end of the readings update
    
    if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
	readingsEndUpdate( $hash, 0 );
    } else {
	readingsEndUpdate( $hash, 1 );
    }
    
    Log3( $hash, 5, "SB_PLAYER_Parse: $name: leaving" );

    return( $name );
}

# ----------------------------------------------------------------------------
#  Undefinition of an SB_PLAYER
#  called when undefining (delete) and element
# ----------------------------------------------------------------------------
sub SB_PLAYER_Undef( $$$ ) {
    my ($hash, $arg) = @_;
    
    Log3( $hash, 5, "SB_PLAYER_Undef: called" );
    
    RemoveInternalTimer( $hash );

    # to be reviewed if that works. 
    # check for uc()
    # what is $hash->{DEF}?
    delete $modules{SB_PLAYER}{defptr}{uc($hash->{DEF})};

    return( undef );
}

# ----------------------------------------------------------------------------
#  Shutdown function - called before fhem shuts down
# ----------------------------------------------------------------------------
sub SB_PLAYER_Shutdown( $$ ) {
    my ($hash, $dev) = @_;
    
    RemoveInternalTimer( $hash );

    Log3( $hash, 5, "SB_PLAYER_Shutdown: called" );

    return( undef );
}


# ----------------------------------------------------------------------------
#  Get of a module
#  called upon get <name> cmd, arg1, arg2, ....
# ----------------------------------------------------------------------------
sub SB_PLAYER_Get( $@ ) {
    my ($hash, @a) = @_;
    
    #my $name = $hash->{NAME};

    Log3( $hash, 1, "SB_PLAYER_Get: called with @a" );

    my $name = shift( @a );
    my $cmd  = shift( @a ); 

    # if( int( @a ) != 2 ) {
    # 	my $msg = "SB_PLAYER_Get: $name: wrong number of arguments";
    # 	Log3( $hash, 5, $msg );
    # 	return( $msg );
    # }

    if( $cmd eq "volume" ) {
	return( scalar( ReadingsVal( "$name", "volumeStraight", 25 ) ) );
    } else {
	my $msg = "SB_PLAYER_Get: $name: unkown argument";
	Log3( $hash, 5, $msg );
	return( $msg );
    } 

    return( undef );
}

# ----------------------------------------------------------------------------
#  Set of a module
#  called upon set <name> cmd, arg1, arg2, ....
# ----------------------------------------------------------------------------
sub SB_PLAYER_Set( $@ ) {
    my ( $hash, $name, $cmd, @arg ) = @_;

    #my $name = $hash->{NAME};

    Log3( $hash, 5, "SB_PLAYER_Set: called with $cmd" );

    # check if we have received a command
    if( !defined( $cmd ) ) { 
	my $msg = "$name: set needs at least one parameter";
	Log3( $hash, 3, $msg );
	return( $msg );
    }

    # now parse the commands
    if( $cmd eq "?" ) {
	# this one should give us a drop down list
	my $res = "Unknown argument ?, choose one of " . 
	    "on off stop:noArg play:noArg pause:noArg " . 
	    "volume:slider,0,1,100 " . 
	    "volumeUp:noArg volumeDown:noArg " . 
	    "mute:noArg repeat:off,one,all show statusRequest:noArg " . 
	    "shuffle:on,off next:noArg prev:noArg playlist sleep " . 
	    "alarm1 alarm2 allalarms:enable,disable cliraw talk ";
	# add the favorites
	$res .= $hash->{FAVSET} . ":" . $hash->{FAVSTR} . " ";

	return( $res );
    }

    # as we have some other command, we need to turn on the server
    #if( AttrVal( $name, "serverautoon", "true" ) eq "true" ) {
#	SB_PLAYER_ServerTurnOn( $hash );
#    }


    if( ( $cmd eq "Stop" ) || ( $cmd eq "STOP" ) || ( $cmd eq "stop" ) ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );

    } elsif( ( $cmd eq "Play" ) || ( $cmd eq "PLAY" ) || ( $cmd eq "play" ) ) {
	my $secbuf = AttrVal( $name, "fadeinsecs", 10 );
	IOWrite( $hash, "$hash->{PLAYERMAC} play $secbuf\n" );

    } elsif( ( $cmd eq "Pause" ) || ( $cmd eq "PAUSE" ) || ( $cmd eq "pause" ) ) {
	my $secbuf = AttrVal( $name, "fadeinsecs", 10 );
	if( @arg == 1 ) {
	    if( $arg[ 0 ] eq "1" ) {
		# pause the player
		IOWrite( $hash, "$hash->{PLAYERMAC} pause 1 $secbuf\n" );
	    } else {
		# unpause the player
		IOWrite( $hash, "$hash->{PLAYERMAC} pause 0 $secbuf\n" );
	    }
	} else {
	    IOWrite( $hash, "$hash->{PLAYERMAC} pause $secbuf\n" );
	}

    } elsif( ( $cmd eq "next" ) || ( $cmd eq "NEXT" ) || ( $cmd eq "Next" ) || 
	     ( $cmd eq "channelUp" ) || ( $cmd eq "CHANNELUP" ) ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} playlist jump %2B1\n" );

    } elsif( ( $cmd eq "prev" ) || ( $cmd eq "PREV" ) || ( $cmd eq "Prev" ) || 
	     ( $cmd eq "channelDown" ) || ( $cmd eq "CHANNELDOWN" ) ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} playlist jump %2D1\n" );

    } elsif( ( $cmd eq "volume" ) || ( $cmd eq "VOLUME" ) || 
	     ( $cmd eq "Volume" ) ||( $cmd eq "volumeStraight" ) ) {
	if( @arg != 1 ) {
	    my $msg = "SB_PLAYER_Set: no arguments for Vol given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}
	# set the volume to the desired level. Needs to be 0..100
	# no error checking here, as the server does this
	IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $arg[ 0 ]\n" );

    } elsif( $cmd eq $hash->{FAVSET} ) {
	if( defined( $SB_PLAYER_Favs{$name}{$arg[0]}{ID} ) ) {
	    my $fid = $SB_PLAYER_Favs{$name}{$arg[0]}{ID};
	    IOWrite( $hash, "$hash->{PLAYERMAC} favorites playlist " . 
		     "play item_id:$fid\n" );
	}


    } elsif( ( $cmd eq "volumeUp" ) || ( $cmd eq "VOLUMEUP" ) || 
	     ( $cmd eq "VolumeUp" ) ) {
	#SB_PLAYER_HTTPWrite( $hash, "mixer", "volume", 
	#"%2B$attr{$name}{volumeStep} " );
	my $volstr = sprintf( "+%02d", $attr{$name}{volumeStep} );
	IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $volstr\n" );

    } elsif( ( $cmd eq "volumeDown" ) || ( $cmd eq "VOLUMEDOWN" ) || 
	     ( $cmd eq "VolumeDown" ) ) {
	#SB_PLAYER_HTTPWrite( $hash, "mixer", "volume", 
	#		   "%2D$attr{$name}{volumeStep}" );
	my $volstr = sprintf( "-%02d", $attr{$name}{volumeStep} );
	IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $volstr\n" );

    } elsif( ( $cmd eq "mute" ) || ( $cmd eq "MUTE" ) || ( $cmd eq "Mute" ) ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} mixer muting toggle\n" );

    } elsif( $cmd eq "on" ) {
	if( $hash->{CANPOWEROFF} eq "0" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} play\n" );
	} else {
	    IOWrite( $hash, "$hash->{PLAYERMAC} power 1\n" );
	}

    } elsif( $cmd eq "off" ) {
	# off command to go here
	if( $hash->{CANPOWEROFF} eq "0" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );
	} else {
	    IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
	}

    } elsif( ( $cmd eq "repeat" ) || ( $cmd eq "REPEAT" ) || 
	     ( $cmd eq "Repeat" ) ) {
	if( @arg != 1 ) {
	    my $msg = "SB_PLAYER_Set: no arguments for repeat given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}
	if( $arg[ 0 ] eq "off" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 0\n" );
	} elsif( $arg[ 0 ] eq "one" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 1\n" );
	} elsif( $arg[ 0 ] eq "all" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 2\n" );
	} else {
	    my $msg = "SB_PLAYER_Set: unknown argument for repeat given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}      
	
    } elsif( ( $cmd eq "shuffle" ) || ( $cmd eq "SHUFFLE" ) || 
	     ( $cmd eq "Shuffle" ) ) {
	if( @arg != 1 ) {
	    my $msg = "SB_PLAYER_Set: no arguments for shuffle given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}
	if( $arg[ 0 ] eq "off" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle 0\n" );
	} elsif( $arg[ 0 ] eq "on" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle 1\n" );
	} else {
	    my $msg = "SB_PLAYER_Set: unknown argument for shuffle given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}      

    } elsif( ( $cmd eq "show" ) || 
	     ( $cmd eq "SHOW" ) || 
	     ( $cmd eq "Show" ) ) {
	# set <name> show line1:text line2:text duration:ss
	my $v = join( " ", @arg );
	my @buf = split( "line1:", $v );
	@buf = split( "line2:", $buf[ 1 ] );
	my $line1 = uri_escape( $buf[ 0 ] );
	@buf = split( "duration:", $buf[ 1 ] );
	my $line2 = uri_escape( $buf[ 0 ] );
	my $duration = $buf[ 1 ];
	my $cmdstr = "$hash->{PLAYERMAC} display $line1 $line2 $duration\n";
	IOWrite( $hash, $cmdstr );

    } elsif( ( $cmd eq "talk" ) || 
	     ( $cmd eq "TALK" ) || 
	     ( $cmd eq "talk" ) ) {
	my $outstr = AttrVal( $name, "ttslink", "none" );
	$outstr .= "tl=" . AttrVal( $name, "ttslanguage", "de" ) . "&q=";
	$outstr .= join( "+", @arg );
	$outstr = uri_escape( $outstr );

	Log3( $hash, 5, "SB_PLAYER_Set: talk: $name: $outstr" );

	# example for making it speak some google text-to-speech
	IOWrite( $hash, "$hash->{PLAYERMAC} playlist play " . $outstr . "\n" );

    } elsif( ( $cmd eq "playlist" ) || 
	     ( $cmd eq "PLAYLIST" ) || 
	     ( $cmd eq "Playlist" ) ) {
	if( ( @arg != 2 ) && ( @arg != 3 ) ) {
	    my $msg = "SB_PLAYER_Set: no arguments for Playlist given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}
	if( @arg == 1 ) {
	    if( $arg[ 0 ] eq "track" ) {
		IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
			 "track.titlesearch:$arg[ 1 ]\n" );
	    } elsif( $arg[ 0 ] eq "album" ) {
		IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
			 "album.titlesearch:$arg[ 1 ]\n" );
	    } elsif( $arg[ 0 ] eq "artist" ) {
		IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
			 "contributor.titlesearch:$arg[ 1 ]\n" );
	    } else {
	    }

	} elsif( @arg == 3 ) {
	    Log3( $hash, 5, "SB_PLAYER_Set($name): implement identifiers with " .
		  "spaces etc. inside" );
	    # the spaces might need %20 so we might need some more here
	    # please introduce a fromat like genre:xxx album:xxx artist:xxx
	    # and then run the results through uri_escape
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadalbum $arg[ 0 ] " . 
		     "$arg[ 1 ] $arg[ 2 ]\n" );
	} else {
	    # what the f... we checked beforehand
	}

    } elsif( $cmd eq "allalarms" ) {
	if( $arg[ 0 ] eq "enable" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} alarm enableall\n" );
	} elsif( $arg[ 0 ] eq "disable" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} alarm disableall\n" );
	} else {
	}


    } elsif( index( $cmd, "alarm" ) != -1 ) {
	my $alarmno = int( substr( $cmd, 5 ) ) + 0;
	Log3( $hash, 5, "SB_PLAYER_Set: $name: alarmid:$alarmno" );
	return( SB_PLAYER_Alarm( $hash, $alarmno, @arg ) );

    } elsif( ( $cmd eq "sleep" ) || ( $cmd eq "SLEEP" ) ||
	     ( $cmd eq "Sleep" ) ) {
	# split the time string up
	my @buf = split( ":", $arg[ 0 ] );
	if( scalar( @buf ) != 3 ) {
	    my $msg = "SB_PLAYER_Set: please use hh:mm:ss for sleep time.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}	      
	my $secs = ( $buf[ 0 ] * 3600 ) + ( $buf[ 1 ] * 60 ) + $buf[ 2 ];
	IOWrite( $hash, "$hash->{PLAYERMAC} sleep $secs\n" );
	return( undef );

    } elsif( ( $cmd eq "cliraw" ) || ( $cmd eq "CLIRAW" ) ||
	     ( $cmd eq "Cliraw" ) ) {
	# write raw messages to the CLI interface per player
	my $v = join( " ", @arg );

	Log3( $hash, 5, "SB_PLAYER_Set: cliraw: $v " ); 
	IOWrite( $hash, "$hash->{PLAYERMAC} $v\n" );
	return( undef );

    } elsif( $cmd eq "statusRequest" ) {
	RemoveInternalTimer( $hash );
	SB_PLAYER_GetStatus( $hash );
	

    } else {
	my $msg = "SB_PLAYER_Set: unsupported command given";
	Log3( $hash, 3, $msg );
	return( $msg );
    }

    return( undef );

}


# ----------------------------------------------------------------------------
#  set Alarms of the Player
# ----------------------------------------------------------------------------
sub SB_PLAYER_Alarm( $$@ ) {
    my ( $hash, $n, @arg ) = @_;

    my $name = $hash->{NAME};

    if( ( $n != 1 ) && ( $n != 2 ) ) {
	Log3( $hash, 1, "SB_PLAYER_Alarm: $name: wrong ID given. Must be 1|2" );
	return;
    }	

    my $id = ReadingsVal( "$name", "alarmid$n", "none" );

    Log3( $hash, 5, "SB_PLAYER_Alarm: $name: ID:$id, N:$n" );
    my $cmdstr = "";

    if( $arg[ 0 ] eq "set" ) {
	# set <name> alarm set 0..6 hh:mm:ss playlist
	if( ( @arg != 4 ) && ( @arg != 3 ) ) {
	    my $msg = "SB_PLAYER_Set: not enough arguments for alarm given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}
	
	if( $id ne "none" ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} alarm delete $id\n" );
	    readingsSingleUpdate( $hash, "alarmid$n", "none", 0 );
	}
	
	my $dow = $arg[ 1 ];
	
	# split the time string up
	my @buf = split( ":", $arg[ 2 ] );
	if( scalar( @buf ) != 3 ) {
	    my $msg = "SB_PLAYER_Set: please use hh:mm:ss for alarm time.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}	      
	my $secs = ( $buf[ 0 ] * 3600 ) + ( $buf[ 1 ] * 60 ) + $buf[ 2 ];
	
	$cmdstr = "$hash->{PLAYERMAC} alarm add dow:$dow repeat:0 enabled:1"; 
	if( defined( $arg[ 3 ] ) ) {
	    $cmdstr .= " playlist:" . $arg[ 3 ];
	}
	$cmdstr .= " time:$secs\n";

	IOWrite( $hash, $cmdstr );

	$hash->{LASTALARM} = $n;

    } elsif( $arg[ 0 ] eq "enable" ) {
	if( $id ne "none" ) {
	    $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
	    $cmdstr .= "enabled:1\n";
	    IOWrite( $hash, $cmdstr );
	}

    } elsif( $arg[ 0 ] eq "disable" ) {
	if( $id ne "none" ) {
	    $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
	    $cmdstr .= "enabled:0\n";
	    IOWrite( $hash, $cmdstr );
	}

    } elsif( $arg[ 0 ] eq "volume" ) {
	if( $id ne "none" ) {
	    $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
	    $cmdstr .= "volume:" . $arg[ 1 ] . "\n";
	    IOWrite( $hash, $cmdstr );
	}

    } elsif( $arg[ 0 ] eq "delete" ) {
	if( $id ne "none" ) {
	    $cmdstr = "$hash->{PLAYERMAC} alarm delete id:$id\n";
	    IOWrite( $hash, $cmdstr );
	    readingsSingleUpdate( $hash, "alarmid$n", "none", 1 );
	}

    } else { 
	my $msg = "SB_PLAYER_Set: unkown argument for alarm given.";
	Log3( $hash, 3, $msg );
	return( $msg );
    }

    return( undef );
}


# ----------------------------------------------------------------------------
#  Status update - just internal use and invoked by the timer
# ----------------------------------------------------------------------------
sub SB_PLAYER_GetStatus( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $strbuf = "";

    Log3( $hash, 5, "SB_PLAYER_GetStatus: called" );

    # we fire the respective questions and parse the answers in parse
    IOWrite( $hash, "$hash->{PLAYERMAC} mode ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} signalstrength ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist name ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist url ?\n" );

    # the other values below are provided by our server. we don't 
    # need to ask again
    if( $hash->{PLAYERIP} eq "?" ) {
	# the server doesn't care about us
	IOWrite( $hash, "$hash->{PLAYERMAC} player ip ?\n" );
    }
    if( $hash->{MODEL} eq "?" ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} player model ?\n" );
    }

    if( $hash->{CANPOWEROFF} eq "?" ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} player canpoweroff ?\n" );
    }

    if( $hash->{PLAYERNAME} eq "?" ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} name ?\n" );
    }

    if( ReadingsVal( $name, "state", "?" ) eq "?" ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} power ?\n" );
    }

    if( ReadingsVal( $name, "connected", "?" ) eq "?" ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} connected ?\n" );
    }

    # do and update of the status
    InternalTimer( gettimeofday() + 300, 
		   "SB_PLAYER_GetStatus", 
		   $hash, 
		   0 );

    Log3( $hash, 5, "SB_PLAYER_GetStatus: leaving" );

    return( );
}


# ----------------------------------------------------------------------------
#  called from the IODev for Broadcastmessages
# ----------------------------------------------------------------------------
sub SB_PLAYER_RecBroadcast( $$@ ) {
    my ( $hash, $cmd, $msg, $bin ) = @_;

    my $name = $hash->{NAME};

    Log3( $hash, 5, "SB_PLAYER_Broadcast($name): called with $msg" ); 

    # let's see what we got. Split the data at the space
    my @args = split( " ", $msg );

    if( $cmd eq "SERVER" ) {
	# a message from the server
	if( $args[ 0 ] eq "OFF" ) {
	    # the server is off, so are we
	    RemoveInternalTimer( $hash );
	    readingsSingleUpdate( $hash, "state", "off", 1 );
	    readingsSingleUpdate( $hash, "power", "off", 1 );
	} elsif( $args[ 0 ] eq "ON" ) {
	    # the server is back
	    # do and update of the status
	    InternalTimer( gettimeofday() + 10, 
			   "SB_PLAYER_GetStatus", 
			   $hash, 
			   0 );
	} else {
	    # unkown broadcast message
	}
    } elsif( $cmd eq "FAVORITES" ) {
	if( $args[ 0 ] eq "ADD" ) {
	    # format: ADD IODEVname ID shortentry
	    $SB_PLAYER_Favs{$name}{$args[3]}{ID} = $args[ 2 ];
	    if( $hash->{FAVSTR} eq "" ) {
		$hash->{FAVSTR} = $args[ 3 ];
	    } else {
		$hash->{FAVSTR} .= "," . $args[ 3 ];
	    }

	} elsif( $args[ 0 ] eq "FLUSH" ) {
	    undef( %{$SB_PLAYER_Favs{$name}} );
	    $hash->{FAVSTR} = "";

	} else {
	}
    } else {

    }

}


# ----------------------------------------------------------------------------
#  parse the return on the alarms status
# ----------------------------------------------------------------------------
sub SB_PLAYER_ParseAlarams( $@ ) {
    my ( $hash, @data ) = @_;

    my $name = $hash->{NAME};

    if( $data[ 0 ] =~ /^([0-9])*/ ) {
	shift( @data );
    }

    if( $data[ 0 ] =~ /^([0-9])*/ ) {
	shift( @data );
    }

    if( $data[ 0 ] =~ /^(fade:)([0|1]?)/ ) {
	shift( @data );
	if( $2 eq "0" ) {
	    $hash->{ALARMSFADEIN} = "yes";
	} else {
	    $hash->{ALARMSFADEIN} = "no";
	}

    } 
    
    if( $data[ 0 ] =~ /^(count:)([0-9].*)/ ) {
	shift( @data );
	$hash->{ALARMSCOUNT} = scalar( $2 );
    }

    if( $hash->{ALARMSCOUNT} > 2 ) {
	Log3( $hash, 2, "SB_PLAYER_Alarms($name): Player has more than " . 
	      "two alarms. So not fully under control by FHEM" );
    }

}



# ----------------------------------------------------------------------------
#  used for checking, if the string contains a valid MAC adress
# ----------------------------------------------------------------------------
sub SB_PLAYER_IsValidMAC( $ ) {
    my $instr = shift( @_ );

    my $d = "[0-9A-Fa-f]";
    my $dd = "$d$d";

    if( $instr =~ /($dd([:-])$dd(\2$dd){4})/og ) {
	return( 1 );
    } else {
	return( 0 );
    }
}

# ----------------------------------------------------------------------------
#  used to turn on our server
# ----------------------------------------------------------------------------
sub SB_PLAYER_ServerTurnOn( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    my $servername;

    Log3( $hash, 5, "SB_PLAYER_ServerTurnOn($name): please implement me" );
    
    return;

    fhem( "set $servername on" );
}


# DO NOT WRITE BEYOND THIS LINE
1;

=pod
    =begin html

    <a name="SB_PLAYER"></a>
    <h3>SB_PLAYER</h3>
    <ul>
    Define a Squeezebox Player. Help needs to be done still.
    <br><br>

    <a name="SB_PLAYERdefine"></a>
    <b>Define</b>
    <ul>
    <code>define &lt;name&gt; SB_PLAYER</code>
    <br><br>

  Example:
    <ul>
    </ul>
    </ul>
    <br>

    <a name="SB_PLAYERset"></a>
    <b>Set</b>
    <ul>
    <code>set &lt;name&gt; &lt;value&gt</code><br>
    Set any value.
    </ul>
    <br>

    <a name="SB_PLAYERget"></a>
    <b>Get</b> <ul>N/A</ul><br>

    <a name="SB_PLAYERattr"></a>
    <b>Attributes</b>
    <ul>
    <li><a name="setList">setList</a><br>
    Space separated list of commands, which will be returned upon "set name ?",
    so the FHEMWEB frontend can construct a dropdown and offer on/off
    switches. Example: attr SB_PLAYERName setList on off
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
    </ul>
    <br>

    </ul>

    =end html
    =cut

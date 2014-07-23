# ############################################################################
#
#  FHEM Modue for Squeezebox Players
#
# ############################################################################
#
#  used to interact with Squeezebox Player
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
#  state            not yet implemented
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
#
#  $Id$
#
# ############################################################################


package main;
use strict;
use warnings;

use IO::Socket;
use URI::Escape;
use Encode qw(decode encode);

# include this for the self-calling timer we use later on
use Time::HiRes qw(gettimeofday);

use constant { true => 1, false => 0 };

# the list of favorites
my %SB_PLAYER_Favs;

# the list of sync masters
my %SB_PLAYER_SyncMasters;

# the list of Server side playlists
my %SB_PLAYER_Playlists;


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
    $hash->{AttrList}  = "volumeStep volumeLimit "; 
    $hash->{AttrList}  .= "ttslanguage:de,en,fr ttslink ";
    $hash->{AttrList}  .= "donotnotify:true,false ";
    $hash->{AttrList}  .= "idismac:true,false ";
    $hash->{AttrList}  .= "serverautoon:true,false ";
    $hash->{AttrList}  .= "fadeinsecs ";
    $hash->{AttrList}  .= "amplifier:on,play ";
    $hash->{AttrList}  .= "coverartheight:50,100,200 ";
    $hash->{AttrList}  .= "coverartwidth:50,100,200 ";
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
    if( ( @a < 3 ) || ( @a > 5 ) ) {
	Log3( $hash, 1, "SB_PLAYER_Define: falsche Anzahl an Argumenten" );
	return( "wrong syntax: define <name> SB_PLAYER <playerid> " .
		"<ampl:FHEM_NAME> <coverart:FHEMNAME>" );
    }
    
    # remove the name and our type
    # my $name = shift( @a );
    shift( @a ); # name
    shift( @a ); # type

    # needed for manual creation of the Player; autocreate checks in ParseFn
    if( SB_PLAYER_IsValidMAC( $a[ 0] ) == 1 ) {
	# the MAC adress is valid
	$hash->{PLAYERMAC} = $a[ 0 ];
    } else {
	my $msg = "SB_PLAYER_Define: playerid ist keine MAC Adresse " . 
	    "im Format xx:xx:xx:xx:xx:xx oder xx-xx-xx-xx-xx-xx";
	Log3( $hash, 1, $msg );
	return( $msg );
    }

    # shift the MAC away
    shift( @a );

    $hash->{AMPLIFIER} = "none";
    $hash->{COVERARTLINK} = "none";
    foreach( @a ) {
	if( $_ =~ /^(ampl:)(.*)/ ) {
	    $hash->{AMPLIFIER} = $2;
	    next;
	} elsif( $_ =~ /^(coverart:)(.*)/ ) {
	    $hash->{COVERARTLINK} = $2;
	    next;
	} else {
	    next;
	}
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
    # the selected favorites
    $hash->{FAVSELECT} = "not";
    # last received answer from the server
    $hash->{LASTANSWER} = "none";
    # for sync group (multi-room)
    $hash->{SYNCMASTER} = "?";
    $hash->{SYNCGROUP} = "?";
    $hash->{SYNCED} = "?";
    # seconds until sleeping
    $hash->{WILLSLEEPIN} = "?";
    # the list of potential sync masters
    $hash->{SYNCMASTERS} = "not,yet,defined";
    # is currently playing a remote stream
    $hash->{ISREMOTESTREAM} = "?";
    # the server side playlists
    $hash->{SERVERPLAYLISTS} = "not,yet,defined";
    # the URL to the artwork
    $hash->{ARTWORKURL} = "?";
    $hash->{COVERARTURL} = "?";
    $hash->{COVERID} = "?";
    # the IP and Port of the Server
    $hash->{SBSERVER} = "?";

    # preset the attributes
    # volume delta settings
    if( !defined( $attr{$name}{volumeStep} ) ) {
	$attr{$name}{volumeStep} = 10;
    }

    # Upper limit for volume setting
    if( !defined( $attr{$name}{volumeLimit} ) ) {
	$attr{$name}{volumeLimit} = 100;
    }

    # how many secs for fade in when going from stop to play
    if( !defined( $attr{$name}{fadeinsecs} ) ) {
	$attr{$name}{fadeinsecs} = 10;
    }

    # do not create FHEM notifies (true=no notifies)
    if( !defined( $attr{$name}{donotnotify} ) ) {
	$attr{$name}{donotnotify} = "true";
    }

    # is the ID the MAC adress
    if( !defined( $attr{$name}{idismac} ) ) {
	$attr{$name}{idismac} = "true";
    }

    # the language for text2speech
    if( !defined( $attr{$name}{ttslanguage} ) ) {
	$attr{$name}{ttslanguage} = "de";
    }

    # link to the text2speech engine
    if( !defined( $attr{$name}{ttslink} ) ) {
	$attr{$name}{ttslink} = "http://translate.google.com" . 
	    "/translate_tts?ie=UTF-8";
    }

    # turn on the server when player is used
    if( !defined( $attr{$name}{serverautoon} ) ) {
	$attr{$name}{serverautoon} = "true";
    }

    # amplifier on/off when play/pause or on/off
    if( !defined( $attr{$name}{amplifier} ) ) {
	$attr{$name}{amplifier} = "play";
    }

    # height and width of the cover art for the URL
    if( !defined( $attr{$name}{coverartwidth} ) ) {
	$attr{$name}{coverartwidth} = 50;
    }
    if( !defined( $attr{$name}{coverartheight} ) ) {
	$attr{$name}{coverartheight} = 50;
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

    if( !defined( $hash->{READINGS}{currentPlaylistUrl}{VAL} ) ) {
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

    # save / recall status
#    if( !defined( $hash->{READINGS}{savedState}{VAL} ) ) {
#	$hash->{READINGS}{savedState}{VAL} = "off";
#	$hash->{READINGS}{savedState}{TIME} = $tn; 
#    }

#    if( !defined( $hash->{READINGS}{savedPlayStatus}{VAL} ) ) {
#	$hash->{READINGS}{savedPlayStatus}{VAL} = "paused";
#	$hash->{READINGS}{savedPlayStatus}{TIME} = $tn; 
#    }

    if( !defined( $hash->{READINGS}{talkStatus}{VAL} ) ) {
	$hash->{READINGS}{talkStatus}{VAL} = "stopped";
	$hash->{READINGS}{talkStatus}{TIME} = $tn; 
    }

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
	    } else {
		SB_SERVER_UpdateVolumeReadings( $hash, $args[ 1 ], true );
	    }
	}

    } elsif( $cmd eq "remote" ) {
	$hash->{ISREMOTESTREAM} = "$args[ 0 ]";

    } elsif( $cmd eq "play" ) {
	readingsBulkUpdate( $hash, "playStatus", "playing" );
	SB_PLAYER_Amplifier( $hash );

    } elsif( $cmd eq "stop" ) {
	readingsBulkUpdate( $hash, "playStatus", "stopped" );
	SB_PLAYER_Amplifier( $hash );

    } elsif( $cmd eq "pause" ) {
	if( $args[ 0 ] eq "0" ) {
	    readingsBulkUpdate( $hash, "playStatus", "playing" );
	    SB_PLAYER_Amplifier( $hash );
	} else {
	    readingsBulkUpdate( $hash, "playStatus", "paused" );
	    SB_PLAYER_Amplifier( $hash );
	} 

    } elsif( $cmd eq "mode" ) {
	#Log3( $hash, 1, "Playmode: $args[ 0 ]" );
	# alittle more complex to fulfill FHEM Development guidelines
	if( $args[ 0 ] eq "play" ) {
	    readingsBulkUpdate( $hash, "playStatus", "playing" );
	    SB_PLAYER_Amplifier( $hash );
	} elsif( $args[ 0 ] eq "stop" ) {
	    readingsBulkUpdate( $hash, "playStatus", "stopped" );
	    SB_PLAYER_Amplifier( $hash );
	} elsif( $args[ 0 ] eq "pause" ) {
	    readingsBulkUpdate( $hash, "playStatus", "paused" );
	    SB_PLAYER_Amplifier( $hash );
	} else {
	    readingsBulkUpdate( $hash, "playStatus", $args[ 0 ] );
	}

    } elsif( $cmd eq "newmetadata" ) {
	# the song has changed, but we are easy and just ask the player
	# sending the requests causes endless loop
	#IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
	#IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
	#IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );
	IOWrite( $hash, "$hash->{PLAYERMAC} remote ?\n" );
	#IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kc\n" );
	SB_PLAYER_CoverArt( $hash );

    } elsif( $cmd eq "playlist" ) {
	if( $args[ 0 ] eq "newsong" ) {
	    # the song has changed, but we are easy and just ask the player
	    IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
	    IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
	    IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );
	    SB_PLAYER_CoverArt( $hash );

	    # the id is in the last return. ID not reported for radio stations
	    # so this will go wrong for e.g. Bayern 3 
#	    if( $args[ $#args ] =~ /(^[0-9]{1,3})/g ) {
#		readingsBulkUpdate( $hash, "currentMedia", $1 );
#	    }
	} elsif( $args[ 0 ] eq "cant_open" ) {
	    #TODO: needs to be handled
	} elsif( $args[ 0 ] eq "open" ) {
	    readingsBulkUpdate( $hash, "currentMedia", "$args[ 1]" );
#	    $args[ 2 ] =~ /^(file:)(.*)/g;
#	    if( defined( $2 ) ) {
	    #readingsBulkUpdate( $hash, "currentMedia", $2 );
#	    }
	    if ($hash->{READINGS}{talkStatus}{VAL} eq "requested") {
		# should be my talk
		Log3( $hash, 5, "SB_PLAYER: talkstatus = " . 
		      $hash->{READINGS}{talkStatus}{VAL} );
		readingsBulkUpdate( $hash, "talkStatus", "playing" );
		SB_PLAYER_Amplifier( $hash );
	    } elsif ($hash->{READINGS}{talkStatus}{VAL} eq "requested " . 
		     "recall pending" ) {
		Log3( $hash, 5, "SB_PLAYER: talkstatus = " . 
		      $hash->{READINGS}{talkStatus}{VAL} );
		readingsBulkUpdate( $hash, "talkStatus", "playing " . 
				      "recall pending", 1 );
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

	} elsif( $args[ 0 ] eq "stop" ) {
	    if( $hash->{READINGS}{talkStatus}{VAL} eq "playing recall pending" ) {
		# I was waiting for the end of the talk and a playlist stopped
		# need to recall saved playlist and saved status
		Log3( $hash, 5, "SB_PLAYER: stop talking - talkStatus was " . 
		      "$hash->{READINGS}{talkStatus}{VAL}" );
		readingsBulkUpdate( $hash, "talkStatus", "stopped" );
		# recall
		if( $hash->{READINGS}{savedState}{VAL} eq "off" ) {
		    # I need to call the playlist and shut off the SB
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume " . 
			     "fhem_$hash->{NAME} noplay:1\n" ); 
		    IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
		    readingsBulkUpdate( $hash, "power", "off" );
		    SB_PLAYER_Amplifier( $hash );
		    Log3( $hash, 5, "SB_PLAYER: recall : off" );
		} elsif( $hash->{READINGS}{savedPlayStatus}{VAL} eq "stopped" ) {
		    # Need to recall playlist + stop
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume " . 
			     "fhem_$hash->{NAME} noplay:1\n" );
		    IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );
		    Log3( $hash, 5, "SB_PLAYER: recall : stop" );
		} elsif( $hash->{READINGS}{savedPlayStatus}{VAL} eq "paused" ) {
		    # Need to recall playlist + pause
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume " . 
			     "fhem_$hash->{NAME} noplay:1\n" );
		    IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
		    Log3( $hash, 5, "SB_PLAYER: recall : pause 1" );
		} else {
		    # Need to recall and play playlist
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume " . 
			     "fhem_$hash->{NAME}\n" );
		    Log3( $hash, 5, "SB_PLAYER: recall now - talkStatus=" . 
			  "$hash->{READINGS}{talkStatus}{VAL}" );
		}
	    } elsif( $hash->{READINGS}{talkStatus}{VAL} eq "playing" ) {
		# I was waiting for the end of the talk and a playlist stopped 
		# keep all like this
		Log3( $hash, 5, "SB_PLAYER: stop talking - talkStatus was " . 
		      "$hash->{READINGS}{talkStatus}{VAL}" );
		readingsBulkUpdate( $hash, "talkStatus", "stopped" );
	    } else {
		# Should be an ordinary playlist stop
		Log3( $hash, 5, "SB_PLAYER: no recall pending - talkstatus " .
		      "= $hash->{READINGS}{talkStatus}{VAL}" );
	    }  
	    
	} else {
	}
	# check if this caused going to play, as not send automatically
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
		readingsBulkUpdate( $hash, "presence", "absent" );
		readingsBulkUpdate( $hash, "state", "off" );
		readingsBulkUpdate( $hash, "power", "off" );
		SB_PLAYER_Amplifier( $hash );
	    } else {
		readingsBulkUpdate( $hash, "state", "on" );
		readingsBulkUpdate( $hash, "power", "on" );
		SB_PLAYER_Amplifier( $hash );
	    }
	} elsif( $args[ 0 ] eq "1" ) {
	    readingsBulkUpdate( $hash, "state", "on" );
	    readingsBulkUpdate( $hash, "power", "on" );
	    SB_PLAYER_Amplifier( $hash );
	} elsif( $args[ 0 ] eq "0" ) {
	    readingsBulkUpdate( $hash, "presence", "absent" );
	    readingsBulkUpdate( $hash, "state", "off" );
	    readingsBulkUpdate( $hash, "power", "off" );
	    SB_PLAYER_Amplifier( $hash );
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

    } elsif( ($cmd eq "unknownir" ) || ($cmd eq "ir" ) ) {
	readingsBulkUpdate( $hash, "lastir", $args[ 0 ] );

    } elsif( $cmd eq "status" ) {
	SB_SERVER_ParsePlayerStatus( $hash, \@args );

    } elsif( $cmd eq "client" ) {
	if( ($args[ 0 ] eq "disconnect") || ($args[ 0 ] eq "connect") ) {
	    # filter "client disconnect" and "client reconnect" messages 
	}

    } elsif( $cmd eq "prefset" ) {
	if( $args[ 0 ] eq "server" ) {
	    if( $args[ 1 ] eq "currentSong" ) {
		readingsBulkUpdate( $hash, "currentMedia", $args[ 2 ] );
	    } elsif( $args[ 1 ] eq "volume" ) {
		SB_SERVER_UpdateVolumeReadings( $hash, $args[ 2 ], true );
	    }
	} else {
	    readingsBulkUpdate( $hash, "lastunkowncmd", 
				  $cmd . " " . join( " ", @args ) );
	}


    } elsif( $cmd eq "NONE" ) {
	# we shall never end up here, as cmd=NONE is used by the server for 
	# autocreate

    } else {
	# unkown command, we push it to the last command thingy
	readingsBulkUpdate( $hash, "lastunkowncmd", 
			      $cmd . " " . join( " ", @args ) );
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
    
    my $name = $hash->{NAME};

    Log3( $hash, 1, "SB_PLAYER_Get: called with @a" );

    if( @a < 2 ) {
	my $msg = "SB_PLAYER_Get: $name: wrong number of arguments";
	Log3( $hash, 5, $msg );
	return( $msg );
    }

    #my $name = shift( @a );
    shift( @a ); # name
    my $cmd  = shift( @a ); 

    if( $cmd eq "?" ) {
	my $res = "Unknown argument ?, choose one of " . 
	    "volume " . $hash->{FAVSET} . " ";
	return( $res );
	
    } elsif( $cmd eq "volume" ) {
	return( scalar( ReadingsVal( "$name", "volumeStraight", 25 ) ) );

    } elsif( $cmd eq $hash->{FAVSET} ) {
	return( "$hash->{FAVSELECT}" );

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
	    "save recall " . 
	    "volume:slider,0,1,100 " . 
	    "volumeUp:noArg volumeDown:noArg " . 
	    "mute:noArg repeat:off,one,all show statusRequest:noArg " . 
	    "shuffle:on,off next:noArg prev:noArg playlist sleep " . 
	    "alarm1 alarm2 allalarms:enable,disable cliraw talk " . 
	    "unsync:noArg ";
	# add the favorites
	$res .= $hash->{FAVSET} . ":" . $hash->{FAVSTR} . " ";
	# ad the syncmasters
	$res .= "sync:" . $hash->{SYNCMASTERS} . " ";
	$res .= "playlists:" . $hash->{SERVERPLAYLISTS} . " ";
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
	if( $arg[ 0 ] <= AttrVal( $name, "volumeLimit", 100 ) ) {
	    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $arg[ 0 ]\n" );
	} else {
	    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume " . 
		     AttrVal( $name, "volumeLimit", 50 ) . "\n" );
	}

    } elsif( $cmd eq $hash->{FAVSET} ) {
	if( defined( $SB_PLAYER_Favs{$name}{$arg[0]}{ID} ) ) {
	    my $fid = $SB_PLAYER_Favs{$name}{$arg[0]}{ID};
	    IOWrite( $hash, "$hash->{PLAYERMAC} favorites playlist " . 
		     "play item_id:$fid\n" );
	    $hash->{FAVSELECT} = $arg[ 0 ];
	    SB_PLAYER_GetStatus( $hash );
	}


    } elsif( ( $cmd eq "volumeUp" ) || ( $cmd eq "VOLUMEUP" ) || 
	     ( $cmd eq "VolumeUp" ) ) {
	# increase volume
	if( ( ReadingsVal( $name, "volumeStraight", 50 ) + 
	      AttrVal( $name, "volumeStep", 10 ) ) <= 
	    AttrVal( $name, "volumeLimit", 100 ) ) {
	    my $volstr = sprintf( "+%02d", AttrVal( $name, "volumeStep", 10 ) );
	    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $volstr\n" );
	} else {
	    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume " . 
		     AttrVal( $name, "volumeLimit", 50 ) . "\n" );
	}

    } elsif( ( $cmd eq "volumeDown" ) || ( $cmd eq "VOLUMEDOWN" ) || 
	     ( $cmd eq "VolumeDown" ) ) {
	my $volstr = sprintf( "-%02d", AttrVal( $name, "volumeStep", 10 ) );
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
	my $outstr = join( "+", @arg );
	$outstr = uri_escape( $outstr );
	$outstr = AttrVal( $name, "ttslink", "none" )  
	    . "&tl=" . AttrVal( $name, "ttslanguage", "de" )
	    . "&q=". $outstr; 

	Log3( $hash, 1, "SB_PLAYER_Set: talk: $name: $outstr" );
	#readingsSingleUpdate( $hash, "talkStatus", "requested", 1 );

	# example for making it speak some google text-to-speech
	#IOWrite( $hash, "$hash->{PLAYERMAC} playlist play " . $outstr . "\n" );

	if( $hash->{READINGS}{talkStatus}{VAL} eq "stopped") {
	    # new talk, no talk already playing
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n" );
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist add ". $outstr . "\n" );
	    IOWrite( $hash, "$hash->{PLAYERMAC} play\n" );
	    Log3( $hash, 1, "SB_PLAYER: talk: initialize playlist" );
	} else {
	    # already playing
	    IOWrite( $hash, "$hash->{PLAYERMAC} playlist add ". $outstr . "\n" );
	    Log3( $hash, 1, "SB_PLAYER: talkStatus = $hash->{READINGS}{talkStatus}{VAL}" );
	    Log3( $hash, 1, "SB_PLAYER: talk: add $outstr" );
	}
	readingsSingleUpdate( $hash, "talkStatus", "requested", 1 );

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

    } elsif( ( $cmd eq "save" ) || ( $cmd eq "SAVE" ) ) {
	# saves player's context

	Log3( $hash, 5, "SB_PLAYER_Set: save " ); 
	readingsSingleUpdate( $hash, 
			      "savedState", 
			      $hash->{READINGS}{state}{VAL}, 
			      1 );
	readingsSingleUpdate( $hash, 
			      "savedPlayStatus", 
			      $hash->{READINGS}{playStatus}{VAL}, 
			      1 );
	IOWrite( $hash, "$hash->{PLAYERMAC} playlist save fhem_$hash->{NAME}\n" );
#	if( $hash->{READINGS}{savedState}{VAL} eq "pause" ) {
#	    #  last commands changed the status to stopped ???
#	    IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
#	}
	return( undef );

    } elsif( ( $cmd eq "recall" ) || ( $cmd eq "RECALL" ) ) {

	if( defined( $hash->{READINGS}{savedState}{VAL} ) ) {
	    # something has been saved
	    Log3( $hash, 1, "SB_PLAYER_Set: recall( $hash->{READINGS}{savedState}{VAL}, $hash->{READINGS}{savedPlayStatus}{VAL})" );
	    if( $hash->{READINGS}{talkStatus}{VAL} ne "stopped" ) {
		# I am talking : need to wait for the end i.e. for a stop
		if( !($hash->{READINGS}{talkStatus}{VAL} =~/pending/ )) {
		    readingsSingleUpdate( $hash, "talkStatus", $hash->{READINGS}{talkStatus}{VAL}." recall pending", 1 );
		}
		Log3( $hash, 1, "SB_PLAYER: recall : need to wait for stop - talkStatus=$hash->{READINGS}{talkStatus}{VAL}" );
	    } else {
		# I am not talking, recall anyway
		if( $hash->{READINGS}{savedState}{VAL} eq "off" ) {
		    # I need to call the playlist and shut off the SB
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME} noplay:1\n" ); 
		    IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
		    readingsSingleUpdate( $hash, "power", "off", 1 );
		    SB_PLAYER_Amplifier( $hash );
		    Log3( $hash, 1, "SB_PLAYER: recall : off" );
		} elsif( $hash->{READINGS}{savedPlayStatus}{VAL} eq "stopped" ) {
		    # Need to recall playlist + stop
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME} noplay:1\n" );
		    IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );
		    Log3( $hash, 1, "SB_PLAYER: recall : stop" );
		} elsif( $hash->{READINGS}{savedPlayStatus}{VAL} eq "paused" ) {
		    # Need to recall playlist + pause
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME} noplay:1\n" );
		    IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
		    Log3( $hash, 1, "SB_PLAYER: recall : pause 1" );
		} else {
		    # Need to recall and play playlist
		    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME}\n" );
		    Log3( $hash, 1, "SB_PLAYER: recall now - talkStatus=$hash->{READINGS}{talkStatus}{VAL}" );
		}
	    }
	} else {
	    Log3( $hash, 1, "SB_PLAYER_Set: recall without save");
	}

	return( undef );


    } elsif( $cmd eq "statusRequest" ) {
	RemoveInternalTimer( $hash );
	SB_PLAYER_GetStatus( $hash );

    } elsif( $cmd eq "sync" ) {
	if( @arg == 1 ) {
	    if( defined( $SB_PLAYER_SyncMasters{$name}{$arg[0]}{MAC} ) ) {
		IOWrite( $hash, "$hash->{PLAYERMAC} sync " . 
			 "$SB_PLAYER_SyncMasters{$name}{$arg[0]}{MAC}\n" );
		SB_PLAYER_GetStatus( $hash );
	    } else {
		my $msg = "SB_PLAYER_Set: no arguments for sync given.";
		Log3( $hash, 3, $msg );
		return( $msg );
	    }
	}

    } elsif( $cmd eq "unsync" ) {
	IOWrite( $hash, "$hash->{PLAYERMAC} sync -\n" );
	SB_PLAYER_GetStatus( $hash );
	
    } elsif( $cmd eq "playlists" ) {
	if( @arg == 1 ) {
	    my $msg;
	    if( defined( $SB_PLAYER_Playlists{$name}{$arg[0]}{ID} ) ) {
		$msg = "$hash->{PLAYERMAC} playlistcontrol cmd:load " . 
		    "playlist_id:$SB_PLAYER_Playlists{$name}{$arg[0]}{ID}";
		Log3( $hash, 5, "SB_PLAYER_Set($name): playlists command = " . 
		      $msg . " ........  with $arg[0]" );
		IOWrite( $hash, $msg . "\n" );
		SB_PLAYER_GetStatus( $hash );

	    } else {
		$msg = "SB_PLAYER_Set: no name for playlist defined.";
		Log3( $hash, 3, $msg );
		return( $msg );
	    }
	} else {
	    my $msg = "SB_PLAYER_Set: no arguments for playlists given.";
	    Log3( $hash, 3, $msg );
	    return( $msg );
	}

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
    IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist url ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} remote ?\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kc\n" );

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
	    SB_PLAYER_Amplifier( $hash );
	} elsif( $args[ 0 ] eq "ON" ) {
	    # the server is back
	    readingsSingleUpdate( $hash, "state", "on", 1 );
	    readingsSingleUpdate( $hash, "power", "on", 1 );
	    # do and update of the status
	    InternalTimer( gettimeofday() + 10, 
			   "SB_PLAYER_GetStatus", 
			   $hash, 
			   0 );
	} elsif( $args[ 0 ] eq "IP" ) {
	    $hash->{SBSERVER} = $args[ 1 ];
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

    } elsif( $cmd eq "SYNCMASTER" ) {
	if( $args[ 0 ] eq "ADD" ) {
	    if( $args[ 1 ] ne $hash->{PLAYERNAME} ) {
		$SB_PLAYER_SyncMasters{$name}{$args[1]}{MAC} = $args[ 2 ];
		if( $hash->{SYNCMASTERS} eq "" ) {
		    $hash->{SYNCMASTERS} = $args[ 1 ];
		} else {
		    $hash->{SYNCMASTERS} .= "," . $args[ 1 ];
		}
	    }
	} elsif( $args[ 0 ] eq "FLUSH" ) {
	    undef( %{$SB_PLAYER_SyncMasters{$name}} );
	    $hash->{SYNCMASTERS} = "";

	} else {
	}

    } elsif( $cmd eq "PLAYLISTS" ) {
	if( $args[ 0 ] eq "ADD" ) {
	    Log3( $hash, 5, "SB_PLAYER_RecbroadCast($name): PLAYLISTS ADD " . 
		  "name:$args[1] id:$args[2] uid:$args[3]" );
	    $SB_PLAYER_Playlists{$name}{$args[3]}{ID} = $args[ 2 ];
	    $SB_PLAYER_Playlists{$name}{$args[3]}{NAME} = $args[ 1 ];
	    if( $hash->{SERVERPLAYLISTS} eq "" ) {
		$hash->{SERVERPLAYLISTS} = $args[ 3 ];
	    } else {
		$hash->{SERVERPLAYLISTS} .= "," . $args[ 3 ];
	    }
	} elsif( $args[ 0 ] eq "FLUSH" ) {
	    undef( %{$SB_PLAYER_Playlists{$name}} );
	    $hash->{SERVERPLAYLISTS} = "";

	} else {
	}

    } else {

    }

}


# ----------------------------------------------------------------------------
#  parse the return on the alarms status
# ----------------------------------------------------------------------------
sub SB_PLAYER_ParseAlarms( $@ ) {
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

# ----------------------------------------------------------------------------
#  used to turn on a connected amplifier
# ----------------------------------------------------------------------------
sub SB_PLAYER_Amplifier( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if( ( $hash->{AMPLIFIER} eq "none" ) || (
	    !defined( $defs{$hash->{AMPLIFIER}} ) ) ) {
	# amplifier not specified
	return;
    }

    my $setvalue = "off";

    Log3( $hash, 4, "SB_PLAYER_Amplifier($name): called" );

    if( AttrVal( $name, "amplifier", "play" ) eq "play" ) {
	my $thestatus = ReadingsVal( $name, "playStatus", "pause" );
	if( ( $thestatus eq "playing" ) || ( $thestatus eq "paused" ) ) {
	    $setvalue = "on";
	}
    } elsif( AttrVal( $name, "amplifier", "on" ) eq "on" ) {
	if( ReadingsVal( $name, "power", "off" ) eq "on" ) {
	    $setvalue = "on";
	}
    } else {
	Log3( $hash, 4, "SB_PLAYER_Amplifier($name): ATTR amplifier " . 
	      "set to wrong value [on|play]" );
    }

    fhem( "set $hash->{AMPLIFIER} $setvalue" );

    return;

}

# ----------------------------------------------------------------------------
#  update the coverart image
# ----------------------------------------------------------------------------
sub SB_PLAYER_CoverArt( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    # compile the link to the album cover
    if( ( $hash->{ISREMOTESTREAM} eq "0" ) ||
	( $hash->{ISREMOTESTREAM} == 0 ) ) {
	$hash->{COVERARTURL} = "http://" . $hash->{SBSERVER} . "/music/" . 
	    "current/cover_" . AttrVal( $name, "coverartheight", 50 ) . 
	    "x" . AttrVal( $name, "coverartwidth", 50 ) . 
	    ".jpg?player=$hash->{PLAYERMAC}";
    } elsif( ( $hash->{ISREMOTESTREAM} eq "1" ) ||
	     ( $hash->{ISREMOTESTREAM} == 1 ) ) {
	$hash->{COVERARTURL} = "http://www.mysqueezebox.com/public/" . 
	    "imageproxy?u=" . $hash->{ARTWORKURL} . 
	    "&h=" . AttrVal( $name, "coverartheight", 50 ) . 
	    "&w=". AttrVal( $name, "coverartwidth", 50 );

    } else {
	$hash->{COVERARTURL} = "http://" . $hash->{SBSERVER} . "/music/" . 
	    "-160206228/cover_" . AttrVal( $name, "coverartheight", 50 ) . 
	    "x" . AttrVal( $name, "coverartwidth", 50 ) . ".jpg";
    }
    if( ( $hash->{COVERARTLINK} eq "none" ) || 
	( !defined( $defs{$hash->{COVERARTLINK}} ) ) || 
	( $hash->{COVERARTURL} eq "?" ) ) {
	# weblink not specified
	return;
    } else {
	fhem( "modify " . $hash->{COVERARTLINK} . " image " . 
	      $hash->{COVERARTURL} );
    }
}

# ----------------------------------------------------------------------------
#  Handle the return for a playerstatus query
# ----------------------------------------------------------------------------
sub SB_SERVER_ParsePlayerStatus( $$ ) {
    my( $hash, $dataptr ) = @_;
    
    my $name = $hash->{NAME};
    
    # typically the start index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
	shift( @{$dataptr} );
    } else {
	Log3( $hash, 5, "SB_SERVER_ParsePlayerStatus($name): entry is " .
	      "not the start number" );
	return;
    }

    # typically the max index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
	shift( @{$dataptr} );
    } else {
	Log3( $hash, 5, "SB_SERVER_ParsePlayerStatus($name): entry is " .
	      "not the end number" );
	return;
    }

    my $datastr = join( " ", @{$dataptr} );
    # replace funny stuff
    $datastr =~ s/mixer volume/mixervolume/g;
    $datastr =~ s/mixertreble/mixertreble/g;
    $datastr =~ s/mixer bass/mixerbass/g;
    $datastr =~ s/mixer pitch/mixerpitch/g;
    $datastr =~ s/playlist repeat/playlistrepeat/g;
    $datastr =~ s/playlist shuffle/playlistshuffle/g;
    $datastr =~ s/playlist index/playlistindex/g;

    Log3( $hash, 5, "SB_SERVER_ParsePlayerStatus($name): data to parse: " .
	  $datastr );

    my @data1 = split( " ", $datastr );

    # the rest of the array should now have the data, we're interested in
    readingsBeginUpdate( $hash );

    # set default values for stuff not always send
    $hash->{SYNCMASTER} = "none";
    $hash->{SYNCGROUP} = "none";
    $hash->{SYNCED} = "no";
    $hash->{COVERID} = "?";
    $hash->{ARTWORKURL} = "?";
    $hash->{ISREMOTESTREAM} = "0";

    # needed for scanning the MAC Adress
    my $d = "[0-9A-Fa-f]";
    my $dd = "$d$d";

    # needed for scanning the IP adress
    my $e = "[0-9]";
    my $ee = "$e$e";

    # loop through the results
    foreach( @data1 ) {
	if( $_ =~ /^(player_connected:)([0-9]*)/ ) {
	    if( $2 == "1" ) {
		readingsBulkUpdate( $hash, "connected", $2 );
		readingsBulkUpdate( $hash, "presence", "present" );
	    } else {
		readingsBulkUpdate( $hash, "connected", $3 );
		readingsBulkUpdate( $hash, "presence", "absent" );
	    }
	    next;

	} elsif( $_ =~ /^(player_ip:)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{3,5})/ ) {
	    if( $hash->{PLAYERIP} ne "?" ) {
		$hash->{PLAYERIP} = $2;
	    }
	    next;

	} elsif( $_ =~ /^(player_name:)(.*)/ ) {
	    if( $hash->{PLAYERNAME} ne "?" ) {
		$hash->{PLAYERNAME} = $2;
	    }
	    next;

	} elsif( $_ =~ /^(power:)([0-9\.]*)/ ) {
	    if( $2 eq "1" ) {
		readingsBulkUpdate( $hash, "power", "on" );
		SB_PLAYER_Amplifier( $hash );
	    } else {
		readingsBulkUpdate( $hash, "power", "off" );
		SB_PLAYER_Amplifier( $hash );
	    }
	    next;

	} elsif( $_ =~ /^(signalstrength:)([0-9\.]*)/ ) {
	    if( $2 eq "0" ) {
		readingsBulkUpdate( $hash, "signalstrength", "wired" );
	    } else {
		readingsBulkUpdate( $hash, "signalstrength", "$2" );
	    }
	    next;

	} elsif( $_ =~ /^(mode:)(.*)/ ) {
	    if( $2 eq "play" ) {
		readingsBulkUpdate( $hash, "playStatus", "playing" );
		SB_PLAYER_Amplifier( $hash );
	    } elsif( $2 eq "stop" ) {
		readingsBulkUpdate( $hash, "playStatus", "stopped" );
		SB_PLAYER_Amplifier( $hash );
	    } else {
		readingsBulkUpdate( $hash, "playStatus", "paused" );
		SB_PLAYER_Amplifier( $hash );
	    }
	    next;

	} elsif( $_ =~ /^(sync_master:)($dd[:|-]$dd[:|-]$dd[:|-]$dd[:|-]$dd[:|-]$dd)/ ) {
	    $hash->{SYNCMASTER} = $2;
	    $hash->{SYNCED} = "yes";
	    next;

	} elsif( $_ =~ /^(sync_slaves:)(.*)/ ) {
	    $hash->{SYNCGROUP} = $2;
	    next;

	} elsif( $_ =~ /^(will_sleep_in:)([0-9\.]*)/ ) {
	    $hash->{WILLSLEEPIN} = "$2 secs";
	    next;

	} elsif( $_ =~ /^(mixervolume:)(.*)/ ) {
	    if( ( index( $2, "+" ) != -1 ) || ( index( $2, "-" ) != -1 ) ) {
		# that was a relative value. We do nothing and fire an update
		IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" );
	    } else {
		SB_SERVER_UpdateVolumeReadings( $hash, $2, true );
	    }
	    next;

	} elsif( $_ =~ /^(playlistshuffle:)(.*)/ ) {
	    if( $2 eq "0" ) {
		readingsBulkUpdate( $hash, "shuffle", "off" );
	    } elsif( $2 eq "1") {
		readingsBulkUpdate( $hash, "shuffle", "song" );
	    } elsif( $2 eq "2") {
		readingsBulkUpdate( $hash, "shuffle", "album" );
	    } else {
		readingsBulkUpdate( $hash, "shuffle", "?" );
	    }
	    next;

	} elsif( $_ =~ /^(playlistrepeat:)(.*)/ ) {
	    if( $2 eq "0" ) {
		readingsBulkUpdate( $hash, "repeat", "off" );
	    } elsif( $2 eq "1") {
		readingsBulkUpdate( $hash, "repeat", "one" );
	    } elsif( $2 eq "2") {
		readingsBulkUpdate( $hash, "repeat", "all" );
	    } else {
		readingsBulkUpdate( $hash, "repeat", "?" );
	    }
	    next;

	} elsif( $_ =~ /^(playlistname:)(.*)/ ) {
	    readingsBulkUpdate( $hash, "currentPlaylistName", $2 );
	    next;

	} elsif( $_ =~ /^(artwork_url:)(.*)/ ) {
	    $hash->{ARTWORKURL} = uri_escape( $2 );
	    next;

	} elsif( $_ =~ /^(coverid:)(.*)/ ) {
	    $hash->{COVERID} = $2;
	    next;

	} elsif( $_ =~ /^(remote:)(.*)/ ) {
	    $hash->{ISREMOTESTREAM} = $2;
	    next;

	} else {
	    next;

	}
    }

    readingsEndUpdate( $hash, 1 );

    # update the cover art
    SB_PLAYER_CoverArt( $hash );

}


# ----------------------------------------------------------------------------
#  update the volume readings
# ----------------------------------------------------------------------------
sub SB_SERVER_UpdateVolumeReadings( $$$ ) {
    my( $hash, $vol, $bulk ) = @_;
    
    my $name = $hash->{NAME};

    if( $bulk == true ) {    
	readingsBulkUpdate( $hash, "volumeStraight", $vol );
	if( $vol > 0 ) {
	    readingsBulkUpdate( $hash, "volume", $vol );
	} else {
	    readingsBulkUpdate( $hash, "volume", "muted" );
	}
    } else {
	readingsSingleUpdate( $hash, "volumeStraight", $vol, 0 );
	if( $vol > 0 ) {
	    readingsSingleUpdate( $hash, "volume", $vol, 0 );
	} else {
	    readingsSingleUpdate( $hash, "volume", "muted", 0 );
	}
    }

    return;
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


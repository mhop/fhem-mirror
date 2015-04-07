# ##############################################################################
# $Id$
#
#  FHEM Module for Squeezebox Players
#
# ##############################################################################
#
#  used to interact with Squeezebox Player
#
# ##############################################################################
#
#  Written by bugster_de
#
#  Contributions from: Siggi85, Oliv06, ChrisD, Markus M., Matthew, KernSani
#
# ##############################################################################
#
#  This is absolutley open source. Please feel free to use just as you
#  like. Please note, that no warranty is given and no liability 
#  granted
#
# ##############################################################################
#
#  we have the following readings
#  state            on or off
#
# ##############################################################################
#
#  we have the following attributes
#  timer            the time frequency how often we check
#  volumeStep       the volume delta when sending the up or down command
#  timeout          the timeout in seconds for the TCP connection
#
# ##############################################################################
#  we have the following internals (all UPPERCASE)
#  PLAYERIP         the IP adress of the player in the network
#  PLAYERID         the unique identifier of the player. Mostly the MAC
#  SERVER           based on the IP and the port as given
#  IP               the IP of the server
#  PLAYERNAME       the name of the Player
#  CONNECTION       the connection status to the server
#  CANPOWEROFF      is the player supporting power off commands
#  MODEL            the model of the player
#  DISPLAYTYPE      what sort of display is there, if any
#
# ##############################################################################


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
# CD 0010 moved to $hash->{helper}{SB_PLAYER_Favs}, fixes problem on module reload
#my %SB_PLAYER_Favs;

# the list of sync masters
# CD 0010 moved to $hash->{helper}{SB_PLAYER_SyncMasters}, fixes problem on module reload
#my %SB_PLAYER_SyncMasters;

# the list of Server side playlists
# CD 0010 moved to $hash->{helper}{SB_PLAYER_Playlists}, fixes problem on module reload
#my %SB_PLAYER_Playlists;

# used for $hash->{helper}{ttsstate}
use constant TTS_IDLE                                    => 0;
use constant TTS_TEXT2SPEECH_BUSY                        => 4;
use constant TTS_TEXT2SPEECH_ACTIVE                      => 6;
use constant TTS_POWERON                                 => 10;
use constant TTS_SAVE                                    => 20;
use constant TTS_UNSYNC                                  => 30;
use constant TTS_SETVOLUME                               => 40;
use constant TTS_LOADPLAYLIST                            => 50;
use constant TTS_DELAY                                   => 55;
use constant TTS_WAITFORPLAY                             => 60;
use constant TTS_PLAYING                                 => 70;
use constant TTS_STOP                                    => 80;
use constant TTS_RESTORE                                 => 90;
use constant TTS_SYNC                                    => 100;
use constant TTS_SYNCGROUPACTIVE                         => 1000;
use constant TTS_EXT_TEXT2SPEECH_BUSY                    => 2004;
use constant TTS_EXT_TEXT2SPEECH_ACTIVE                  => 2006;

my %ttsstates = (   0   =>'idle',
                    4   =>'Text2Speech busy, waiting',
                    6   =>'Text2Speech active',
                    10  =>'power on',
                    20  =>'save state',
                    30  =>'unsync player',
                    40  =>'set volume',
                    50  =>'load playlist',
                    55  =>'delay',
                    60  =>'wait for play',
                    70  =>'playing',
                    80  =>'stopped',
                    90  =>'restore state',
                    100 =>'sync',
                    1000=>'active',
                    2004=>'Text2Speech busy, waiting',
                    2006=>'Text2Speech active');
                    
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

    # CD 0007
    $hash->{AttrFn}  = "SB_PLAYER_Attr";

    # CD 0032
    $hash->{NotifyFn}  = "SB_PLAYER_Notify";
    
    # the attributes we have. Space separated list of attribute values in 
    # the form name:default1,default2
    $hash->{AttrList}  = "IODev ignore:1,0 do_not_notify:1,0 ";
    $hash->{AttrList}  .= "volumeStep volumeLimit "; 
    $hash->{AttrList}  .= "ttslanguage:de,en,fr ttslink ";
    $hash->{AttrList}  .= "donotnotify:true,false ";
    $hash->{AttrList}  .= "idismac:true,false ";
    $hash->{AttrList}  .= "serverautoon:true,false ";
    $hash->{AttrList}  .= "fadeinsecs ";
    $hash->{AttrList}  .= "amplifier:on,play ";
    $hash->{AttrList}  .= "coverartheight:50,100,200 ";
    $hash->{AttrList}  .= "coverartwidth:50,100,200 ";
    # CD 0028
    $hash->{AttrList}  .= "ttsVolume ";
    $hash->{AttrList}  .= "ttsOptions ";
    # CD 0030
    $hash->{AttrList}  .= "ttsDelay ";
    # CD 0032
    $hash->{AttrList}  .= "ttsPrefix "; # DJAlex 665
    # CD 0033
    $hash->{AttrList}  .= "ttsMP3FileDir ";
    # CD 0007
    $hash->{AttrList}  .= "syncVolume ";
    $hash->{AttrList}  .= "amplifierDelayOff ";                     # CD 0012
    $hash->{AttrList}  .= "updateReadingsOnSet:true,false ";        # CD 0017
    $hash->{AttrList}  .= $readingFnAttributes;
}

# CD 0007 start
# ----------------------------------------------------------------------------
#  Attr functions 
# ----------------------------------------------------------------------------
sub SB_PLAYER_Attr( @ ) {
    my $cmd = shift( @_ );
    my $name = shift( @_ );
    my @args = @_;
    my $hash = $defs{$name};
    
    Log( 4, "SB_PLAYER_Attr($name): called with @args" );

    if( $args[ 0 ] eq "syncVolume" ) {
        if( $cmd eq "set" ) {
            if (defined($args[1])) {
                if($args[1] eq "1") {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playerpref syncVolume 1\n" );
                } else {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playerpref syncVolume 0\n" );
                }
            } else {
                IOWrite( $hash, "$hash->{PLAYERMAC} playerpref syncVolume ?\n" );
            }
        } else {
        
        }
    }
    # CD 0012 start - bei Änderung des Attributes Zustand überprüfen
    elsif( $args[ 0 ] eq "amplifier" ) {
        RemoveInternalTimer( "DelayAmplifier:$name");
        InternalTimer( gettimeofday() + 0.01, 
           "SB_PLAYER_tcb_DelayAmplifier",  # CD 0014 Name geändert
           "DelayAmplifier:$name", 
           0 );
    }
    # CD 0028
    elsif( $args[ 0 ] eq "ttsVolume" ) {
        if( $cmd eq "set" ) {
            if (defined($args[1])) {
                return "invalid value for ttsVolume" if(($args[1] < 0)||($args[1] > 100));
                $hash->{helper}{ttsVolume}=$args[1];
            } else {
                return "invalid value for ttsVolume";
            }
        } else {
            delete($hash->{helper}{ttsVolume}) if(defined($hash->{helper}{ttsVolume}));
        }
    }
    elsif( $args[ 0 ] eq "ttsOptions" ) {
        if( $cmd eq "set" ) {
            if (defined($args[1])) {
                my @options=split(',',$args[1]);
                delete($hash->{helper}{ttsOptions}) if(defined($hash->{helper}{ttsOptions}));
                for my $opt (@options) {
                    $hash->{helper}{ttsOptions}{debug}=1 if($opt=~ m/debug/);
                    $hash->{helper}{ttsOptions}{debugsaverestore}=1 if($opt=~ m/debugsaverestore/); # CD 0029
                    $hash->{helper}{ttsOptions}{unsync}=1 if($opt=~ m/unsync/);
                    $hash->{helper}{ttsOptions}{nosaverestore}=1 if($opt=~ m/nosaverestore/);
                    $hash->{helper}{ttsOptions}{forcegroupon}=1 if($opt=~ m/forcegroupon/);
                    $hash->{helper}{ttsOptions}{internalsave}=1 if($opt=~ m/internalsave/);         # CD 0029
                    $hash->{helper}{ttsOptions}{ignorevolumelimit}=1 if($opt=~ m/ignorevolumelimit/);   # CD 0031
                }
            } else {
                return "invalid value for ttsOptions";
            }
        } else {
            delete($hash->{helper}{ttsOptions}) if(defined($hash->{helper}{ttsOptions}));
        }
    }
    # CD 0030
    elsif( $args[ 0 ] eq "ttsDelay" ) { 
        if( $cmd eq "set" ) {
            if (defined($args[1])) {
                my @options=split(',',$args[1]);
                $hash->{helper}{ttsDelay}{PowerIsOn}=$options[0];
                if(defined($options[1])) {
                    $hash->{helper}{ttsDelay}{PowerIsOff}=$options[1];
                } else {
                    $hash->{helper}{ttsDelay}{PowerIsOff}=$options[0];
                }
            } else {
                return "invalid value for ttsDelay";
            }
        } else {
            delete($hash->{helper}{ttsDelay}) if(defined($hash->{helper}{ttsDelay}));
        }
    }    
    return;
    # CD 0012
}
# CD 0007 end

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
        $hash->{PLAYERMAC} = lc($a[ 0 ]);       # CD 0026 lc added
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
    #$hash->{ALARMSFADEIN} = "?";                 # CD 0016 deaktiviert, -> Reading
    # the number of alarms of the player
    $hash->{helper}{ALARMSCOUNT} = 0;             # CD 0016 ALARMSCOUNT nach {helper} verschoben

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

    # the id of the alarm we create                         # CD 0015 deaktiviert
#    if( !defined( $hash->{READINGS}{alarmid1}{VAL} ) ) {
#        $hash->{READINGS}{alarmid1}{VAL} = "none";
#        $hash->{READINGS}{alarmid1}{TIME} = $tn; 
#    }

#    if( !defined( $hash->{READINGS}{alarmid2}{VAL} ) ) {
#        $hash->{READINGS}{alarmid2}{VAL} = "none";
#        $hash->{READINGS}{alarmid2}{TIME} = $tn; 
#    }

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

    if( !defined( $hash->{READINGS}{favorites}{VAL} ) ) {
        $hash->{READINGS}{favorites}{VAL} = "not";
        $hash->{READINGS}{favorites}{TIME} = $tn; 
    }

    if( !defined( $hash->{READINGS}{playlists}{VAL} ) ) {
        $hash->{READINGS}{playlists}{VAL} = "not";
        $hash->{READINGS}{playlists}{TIME} = $tn; 
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

    $hash->{helper}{ttsstate}=TTS_IDLE;  # CD 0028
    
    # do and update of the status
    InternalTimer( gettimeofday() + 10, 
                   "SB_PLAYER_GetStatus", 
                   $hash, 
                   0 );

    return( undef );
}

# CD 0002 start
sub SB_PLAYER_tcb_QueryCoverArt($) {    # CD 0014 Name geändert
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    #Log 0,"delayed cover art query";
    IOWrite( $hash, "$hash->{PLAYERMAC} status - 1 tags:Kcu\n" );   # CD 0030 u added to tags

    # CD 0005 query cover art for synced players
    if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
        if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {    # CD 0018 none hinzugefügt
            my @pl=split(",",$hash->{SYNCGROUP});
            foreach (@pl) {
                IOWrite( $hash, "$_ status - 1 tags:Kc\n" );
            }
        }
    }
}
# CD 0002 end

# CD 0014 start
sub SB_PLAYER_tcb_DeleteRecallPause($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    delete($hash->{helper}{recallPause});
}

sub SB_PLAYER_QueryElapsedTime($) {
    my ($hash) = @_;

    if(!defined($hash->{helper}{lastTimeQuery})||($hash->{helper}{lastTimeQuery}<gettimeofday()-5)) {
    #Log 0,"Querying time, last: $hash->{helper}{lastTimeQuery}, now: ".gettimeofday();
        $hash->{helper}{lastTimeQuery}=gettimeofday();
        IOWrite( $hash, "$hash->{PLAYERMAC} time ?\n" );
    }
}
# CD 0014 end

# CD 0028 start
sub SB_PLAYER_tcb_TTSRestore( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    # CD 0033 start
    if(defined($hash->{helper}{ttsqueue})) {
        SB_PLAYER_SetTTSState($hash,TTS_LOADPLAYLIST,0,0);
        SB_PLAYER_LoadTalk($hash);
    } else {
    # CD 0033 end
        if(!defined($hash->{helper}{ttsOptions}{nosaverestore})) {
            SB_PLAYER_SetTTSState($hash,TTS_RESTORE,0,0);
            SB_PLAYER_Recall( $hash );
        } else {
            SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
        }
    }
}
# CD 0028 end

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
            Log3( undef, 3, "SB_PLAYER_Parse: the unknown ID $id is a valid " . 
                  "MAC Adress" );
            # this line supports autocreate
            return( "UNDEFINED SB_PLAYER_$id SB_PLAYER $idbuf" );
        } else {
            # the MAC adress is not valid
            Log3( undef, 3, "SB_PLAYER_Parse: the unknown ID $id is NOT " . 
                  "a valid MAC Adress" );
            return( undef );
        }
    }
    
    # so the data is for us
    my $name = $hash->{NAME};
    #return "" if(IsIgnored($name));

    Log3( $hash, 5, "SB_PLAYER_Parse: $name CMD:$cmd ARGS:@args..." ); 

    # what ever we have received, signal it
    $hash->{LASTANSWER} = "$cmd @args";

    $hash->{helper}{ttsstate}=TTS_IDLE if(!defined($hash->{helper}{ttsstate})); # CD 0028

    # signal the update to FHEM
    readingsBeginUpdate( $hash );

    if( $cmd eq "mixer" ) {
        if( $args[ 0 ] eq "volume" ) {
            # update the volume 
            if ($args[ 1 ] eq "?") {
                # it is a request
            } else {
                SB_PLAYER_UpdateVolumeReadings( $hash, $args[ 1 ], true );
                # CD 0007 start
                if((defined($hash->{helper}{setSyncVolume}) && ($hash->{helper}{setSyncVolume} != $args[ 1 ]))|| (!defined($hash->{helper}{setSyncVolume}))) {
                    SB_PLAYER_SetSyncedVolume($hash,$args[ 1 ]);
                }
                delete $hash->{helper}{setSyncVolume};
                # CD 0007 end
            }
        }

    } elsif( $cmd eq "remote" ) {
        if( defined( $args[ 0 ] ) ) {
            $hash->{ISREMOTESTREAM} = "$args[ 0 ]";
        } else { 
            $hash->{ISREMOTESTREAM} = "0";
        }


    } elsif( $cmd eq "play" ) {
        if(!defined($hash->{helper}{recallPause})) {    # CD 0014
            readingsBulkUpdate( $hash, "playStatus", "playing" );
            SB_PLAYER_Amplifier( $hash );
        } # CD 0014
    } elsif( $cmd eq "stop" ) {
        readingsBulkUpdate( $hash, "playStatus", "stopped" );
        SB_PLAYER_Amplifier( $hash );

    } elsif( $cmd eq "pause" ) {
        if((defined($args[ 0 ])) && ( $args[ 0 ] eq "0" )) {    # CD 0028 check if $args[0] exists
            readingsBulkUpdate( $hash, "playStatus", "playing" );
            SB_PLAYER_Amplifier( $hash );
        } else {
            readingsBulkUpdate( $hash, "playStatus", "paused" );
            SB_PLAYER_Amplifier( $hash );
        } 

    } elsif( $cmd eq "mode" ) {
        # alittle more complex to fulfill FHEM Development guidelines
        Log3( $hash, 5, "SB_PLAYER_Parse($name): mode:$cmd args:$args[0]" ); 
        if( $args[ 0 ] eq "play" ) {
            # CD 0014 start
            if(defined($hash->{helper}{recallPause})) {
                IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
            } else {
            # CD 0014 end
                readingsBulkUpdate( $hash, "playStatus", "playing" );
                SB_PLAYER_Amplifier( $hash );
                SB_PLAYER_QueryElapsedTime( $hash );    # CD 0014
            } # CD 0014
            # CD 0029 start
            if(defined($hash->{helper}{ttsOptions}{logplay})) {
                Log3( $hash, 0, "SB_PLAYER_Parse: $name: mode play");
                delete($hash->{helper}{ttsOptions}{logplay});
            }
            # CD 0029
            # CD 0028 start
            if($hash->{helper}{ttsstate}==TTS_WAITFORPLAY) {
                SB_PLAYER_SetTTSState($hash,TTS_PLAYING,1,0);
            }
            if(($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE) && ($hash->{SYNCMASTER} eq $hash->{PLAYERMAC})) {
                IOWrite( $hash, $hash->{helper}{ttsMaster} . " fhemrelay ttsplaying\n" );
            }
            # CD 0028 end
        } elsif( $args[ 0 ] eq "stop" ) {
            # CD 0028 start
            if($hash->{helper}{ttsstate}==TTS_PLAYING) {
                SB_PLAYER_TTSStopped($hash);
            }

            # wenn tts auf Slave aktiv ist schickt der LMS den Stop nur an den Master 
            if(($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE) && ($hash->{SYNCMASTER} eq $hash->{PLAYERMAC})) {
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                    my @pl=split(",",$hash->{SYNCGROUP});
                    foreach (@pl) {
                        if ($hash->{PLAYERMAC} ne $_) {
                            IOWrite( $hash, "$_ fhemrelay ttsstopped\n" );
                        }
                    }
                }
            }
            # CD 0028 end
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
        #SB_PLAYER_CoverArt( $hash );       # CD 0026 deaktiviert

    } elsif( $cmd eq "playlist" ) {
        my $queryMode=1;    # CD 0014
    
        if( $args[ 0 ] eq "newsong" ) {
            # the song has changed, but we are easy and just ask the player
            IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );
            # CD 0007 get playlist name
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist name ?\n" );
            # CD 0014 get duration and index
            IOWrite( $hash, "$hash->{PLAYERMAC} duration ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist index ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} time ?\n" );
            # CD 0002 Coverart anfordern, todo: Zeit variabel
            $hash->{helper}{CoverOk}=0;   # CD 0026 added # CD 0027 changed
            # CD 0025 bei lokalen Playlisten schneller abfragen
            if( $hash->{ISREMOTESTREAM} eq "0" ) {
                InternalTimer( gettimeofday() + 3, 
                        "SB_PLAYER_tcb_QueryCoverArt",
                        "QueryCoverArt:$name",
                        0 );
            } else {
                InternalTimer( gettimeofday() + 10, 
                        "SB_PLAYER_tcb_QueryCoverArt",  # CD 0014 Name geändert
                        "QueryCoverArt:$name",          # CD 0014 Name geändert
                        0 );
            }
            # CD 0002 zu früh, CoverArt ist noch nicht verfügbar
            # SB_PLAYER_CoverArt( $hash );

            # CD 0000 start - sync players in same group
            if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {        # CD 0018 none hinzugefügt
                    my @pl=split(",",$hash->{SYNCGROUP});
                    foreach (@pl) {
                        #Log 0,"SB_Player to sync: $_";
                        IOWrite( $hash, "$_ artist ?\n" );
                        IOWrite( $hash, "$_ album ?\n" );
                        IOWrite( $hash, "$_ title ?\n" );
                        # CD 0010
                        IOWrite( $hash, "$_ playlist name ?\n" );
                        # CD 0014
                        IOWrite( $hash, "$_ duration ?\n" );
                        IOWrite( $hash, "$_ playlist index ?\n" );
                    }
                }
            }
            # CD 0000 end

            # CD 0014 start
            if(defined($hash->{helper}{recallPause})) {
                IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
                RemoveInternalTimer( "recallPause:$name");
                InternalTimer( gettimeofday() + 0.5, 
                   "SB_PLAYER_tcb_DeleteRecallPause", 
                   "recallPause:$name", 
                   0 );
            }
            # CD 0014 end

            # the id is in the last return. ID not reported for radio stations
            # so this will go wrong for e.g. Bayern 3 
#           if( $args[ $#args ] =~ /(^[0-9]{1,3})/g ) {
#               readingsBulkUpdate( $hash, "currentMedia", $1 );
#           }
        } elsif( $args[ 0 ] eq "cant_open" ) {
            #TODO: needs to be handled
            # CD 0033 TTS abbrechen bei Fehler
            if($hash->{helper}{ttsstate}==TTS_WAITFORPLAY) {
                SB_PLAYER_TTSStopped($hash);
            }
        } elsif( $args[ 0 ] eq "open" ) {
            readingsBulkUpdate( $hash, "currentMedia", "$args[1]" );
            SB_PLAYER_Amplifier( $hash );
            SB_PLAYER_GetStatus( $hash );       # CD 0014
#           $args[ 2 ] =~ /^(file:)(.*)/g;
#           if( defined( $2 ) ) {
            #readingsBulkUpdate( $hash, "currentMedia", $2 );
#           }
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
            SB_PLAYER_GetStatus( $hash );       # CD 0014
        } elsif( $args[ 0 ] eq "name" ) {
            # CD 0014 start
            $queryMode=0;
            if(!defined($args[ 1 ])) {
                readingsBulkUpdate( $hash, "currentPlaylistName","-");
                readingsBulkUpdate( $hash, "playlists","-");
                #$hash->{FAVSELECT} = '-';                              # CD 0021 deaktiviert
                #readingsBulkUpdate( $hash, "$hash->{FAVSET}", '-' );   # CD 0021 deaktiviert
            }
            # CD 0014 end
            if(defined($args[ 1 ]) && ($args[ 1 ] ne '?')) {            # CD 0009 check empty name - 0011 ignore '?'
                shift( @args );
                readingsBulkUpdate( $hash, "currentPlaylistName", 
                                    join( " ", @args ) );
                my $pn=SB_SERVER_FavoritesName2UID(join( " ", @args ));     # CD 0021 verschoben, decode hinzugefügt # CD 0023 decode entfernt
                # CD 0008 update playlists reading
                readingsBulkUpdate( $hash, "playlists", $pn);           # CD 0021 $pn verwenden wegen Dropdown
                #                   join( "_", @args ) );               # CD 0021 deaktiviert
                # CD 0007 start - check if playlist == fav, 0014 removed debug info
                if( defined($hash->{helper}{SB_PLAYER_Favs}{$pn}) && defined($hash->{helper}{SB_PLAYER_Favs}{$pn}{ID})) {   # CD 0011 check if defined($hash->{helper}{SB_PLAYER_Favs}{$pn})
                    $hash->{FAVSELECT} = $pn;
                    readingsBulkUpdate( $hash, "$hash->{FAVSET}", "$pn" );
                } else {
                    $hash->{FAVSELECT} = '-';                                              # CD 0014
                    readingsBulkUpdate( $hash, "$hash->{FAVSET}", '-' );                   # CD 0014
                }
                # CD 0007 end
            }
            # CD 0009 start
        # CD 0021 start, update favorites if url matches
        } elsif( $args[ 0 ] eq "play" ) {
            if(defined($args[ 1 ])) {
                $args[ 1 ]=~s/\\/\//g;
                $hash->{FAVSELECT}="-";
                foreach my $e ( keys %{$hash->{helper}{SB_PLAYER_Favs}} ) {
                    if($args[ 1 ] eq $hash->{helper}{SB_PLAYER_Favs}{$e}{URL}) {
                        $hash->{FAVSELECT} = $e;
                        last;
                    }
                }
                readingsBulkUpdate( $hash, "$hash->{FAVSET}", "$hash->{FAVSELECT}" );
                # CD 0022 send to synced players # CD 0023 fixed
                if( $hash->{SYNCED} eq "yes") {
                    if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                        my @pl=split(",",$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER});
                        foreach (@pl) {
                            if ($hash->{PLAYERMAC} ne $_) {
                                IOWrite( $hash, "$_ fhemrelay favorites $hash->{FAVSELECT}\n" );
                            }
                        }
                    }
                }
            }
        # CD 0021 end
        } elsif( $args[ 0 ] eq "clear" ) {
            readingsBulkUpdate( $hash, "currentPlaylistName", "none" );
            readingsBulkUpdate( $hash, "playlists", "none" );
            # CD 0009 end
            SB_PLAYER_GetStatus( $hash );       # CD 0014
        } elsif( $args[ 0 ] eq "url" ) {
            shift( @args );
            readingsBulkUpdate( $hash, "currentPlaylistUrl", 
                                join( " ", @args ) );

        } elsif( $args[ 0 ] eq "stop" ) {
            readingsBulkUpdate( $hash, "playStatus", "stopped" );                # CD 0012 'power off' durch 'playStatus stopped' ersetzt
            SB_PLAYER_Amplifier( $hash );
        # CD 0014 start
        } elsif( $args[ 0 ] eq "index" ) {
            readingsBulkUpdate( $hash, "playlistCurrentTrack", $args[ 1 ]+1 );
            $queryMode=0;
        } elsif( $args[ 0 ] eq "addtracks" ) {
            $queryMode=0;
            SB_PLAYER_GetStatus( $hash );
        } elsif( $args[ 0 ] eq "delete" ) {
            $queryMode=0;
            #IOWrite( $hash, "$hash->{PLAYERMAC} alarm playlists 0 200\n" );     # CD 0016 get available elements for alarms    # CD 0026 deaktiviert
            SB_PLAYER_GetStatus( $hash );
        } elsif( $args[ 0 ] eq "load_done" ) {
            if($hash->{helper}{ttsstate}==TTS_PLAYING) {
                #IOWrite( $hash, "$hash->{PLAYERMAC} playlist index +0\n");         
                #IOWrite( $hash, "$hash->{PLAYERMAC} play\n" );
            }
            if($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST) {
                # CD 0030 start
                if(SB_PLAYER_GetTTSDelay($hash)>0) {
                    RemoveInternalTimer( "TTSDelay:$name");
                    InternalTimer( gettimeofday() + SB_PLAYER_GetTTSDelay($hash), 
                       "SB_PLAYER_tcb_TTSDelay",
                       "TTSDelay:$name", 
                       0 ); 
                    SB_PLAYER_SetTTSState($hash,TTS_DELAY,1,0);
                } else {
                # CD 0030 end
                    SB_PLAYER_SetTTSState($hash,TTS_WAITFORPLAY,1,0);
                    IOWrite( $hash, "$hash->{PLAYERMAC} play\n" );
                }
            }
            # CD 0029 start
            if(defined($hash->{helper}{ttsOptions}{logloaddone})) {
                Log3( $hash, 0, "SB_PLAYER_Parse: $name: load_done");
                delete($hash->{helper}{ttsOptions}{logloaddone});
            }
            # CD 0029 end
            if(defined($hash->{helper}{recallPending})) {
                delete($hash->{helper}{recallPending});
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,1,1);
                IOWrite( $hash, "$hash->{PLAYERMAC} play 300\n" );
                IOWrite( $hash, "$hash->{PLAYERMAC} time $hash->{helper}{savedPlayerState}{elapsedTime}\n" );
            }
        } elsif( $args[ 0 ] eq "loadtracks" ) {
            if(defined($hash->{helper}{recallPending})) {
                delete($hash->{helper}{recallPending});
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,1,1);
                IOWrite( $hash, "$hash->{PLAYERMAC} play 300\n" );
                IOWrite( $hash, "$hash->{PLAYERMAC} time $hash->{helper}{savedPlayerState}{elapsedTime}\n" );
            }
        # CD 0014 end
        } else {
        }
        # check if this caused going to play, as not send automatically
        if(!defined($hash->{helper}{lastModeQuery})||($hash->{helper}{lastModeQuery} < gettimeofday()-0.05)) {  # CD 0014 überflüssige Abfragen begrenzen
            IOWrite( $hash, "$hash->{PLAYERMAC} mode ?\n" ) if(!(defined($hash->{helper}{recallPending})||defined($hash->{helper}{recallPause})||($queryMode==0)));   # CD 0014 if(... hinzugefügt
            $hash->{helper}{lastModeQuery} = gettimeofday();    # CD 0014
        }   # CD 0014

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
        if( !( @args ) ) {
            # no arguments were send with the Power command
            # potentially this is a power toggle : should only happen 
            # when called with SB CLI
        } elsif( $args[ 0 ] eq "1" ) {
            readingsBulkUpdate( $hash, "state", "on" );
            readingsBulkUpdate( $hash, "power", "on" );
            
            SB_PLAYER_Amplifier( $hash );
        } elsif( $args[ 0 ] eq "0" ) {
            #readingsBulkUpdate( $hash, "presence", "absent" );      # CD 0013 deaktiviert, power sagt nichts über presence
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
                #readingsBulkUpdate( $hash, "alarmid$hash->{LASTALARM}", $2 );  # CD 0015 deaktiviert
            } else {
            }
            #IOWrite( $hash, "$hash->{PLAYERMAC} alarm playlists 0 200\n" ) if (!defined($hash->{helper}{alarmPlaylists})); # CD 0015 get available elements for alarms CD 0016 nur wenn nicht vorhanden abfragen # CD 0026 wird über Server verteilt
            IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" ); # CD 0015 update alarm list
        } elsif( $args[ 0 ] eq "_cmd" ) {
            #IOWrite( $hash, "$hash->{PLAYERMAC} alarm playlists 0 200\n" ); # CD 0015 get available elements for alarms CD 0016 deaktiviert, nicht nötig
            IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" );  # CD 0015 filter added
        } elsif( $args[ 0 ] eq "update" ) {
            #IOWrite( $hash, "$hash->{PLAYERMAC} alarm playlists 0 200\n" ) if (!defined($hash->{helper}{alarmPlaylists})); # CD 0015 get available elements for alarms CD 0016 nur wenn nicht vorhanden abfragen # CD 0026 wird über Server verteilt
            IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" );  # CD 0015 filter added
        } elsif( $args[ 0 ] eq "delete" ) {
            if(!defined($hash->{helper}{deleteAllAlarms})) {                    # CD 0015 do not query while deleting all alarms
                IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" );  # CD 0015 filter added
            }
        # CD 0015 start
        # verfügbare Elemente für Alarme, zwischenspeichern für Anzeige
        # CD 0026 deaktiviert, kommt über Broadcast vom Server
        #} elsif( $args[ 0 ] eq "playlists" ) {
        #    delete($hash->{helper}{alarmPlaylists}) if (defined($hash->{helper}{alarmPlaylists}));
        #    my @r=split("category:",join(" ",@args));
        #    foreach my $a (@r){
        #        my $i1=index($a," title:");
        #        my $i2=index($a," url:");
        #        my $i3=index($a," singleton:");
        #        if (($i1!=-1)&&($i2!=-1)&&($i3!=-1)) {
        #            my $url=substr($a,$i2+5,$i3-$i2-5);
        #            $url=substr($a,$i1+7,$i2-$i1-7) if ($url eq "");
        #            my $pn=SB_SERVER_FavoritesName2UID(decode('utf-8',$url));               # CD 0021 decode hinzugefügt
        #            $hash->{helper}{alarmPlaylists}{$pn}{category}=substr($a,0,$i1);
        #            $hash->{helper}{alarmPlaylists}{$pn}{title}=substr($a,$i1+7,$i2-$i1-7);
        #            $hash->{helper}{alarmPlaylists}{$pn}{url}=$url;
        #        }
        #    }
        # CD 0015
        } else {
        }


    } elsif( $cmd eq "alarms" ) {
        delete($hash->{helper}{deleteAllAlarms}) if(defined($hash->{helper}{deleteAllAlarms})); # CD 0015
        SB_PLAYER_ParseAlarms( $hash, @args );

    } elsif( $cmd eq "showbriefly" ) {
        # to be ignored, we get two hashes

    } elsif( ($cmd eq "unknownir" ) || ($cmd eq "ir" ) ) {
        readingsBulkUpdate( $hash, "lastir", $args[ 0 ] );

    } elsif( $cmd eq "status" ) {
        SB_PLAYER_ParsePlayerStatus( $hash, \@args );

    } elsif( $cmd eq "client" ) {
        if( $args[ 0 ] eq "new" ) {
            # not to be handled here, should lead to a new FHEM Player
        } elsif( $args[ 0 ] eq "disconnect" ) {
            readingsBulkUpdate( $hash, "presence", "absent" );
            readingsBulkUpdate( $hash, "state", "off" );
            readingsBulkUpdate( $hash, "power", "off" );
            SB_PLAYER_Amplifier( $hash );
            # CD 0031 wenn Player während TTS verschwindet Zustand zurücksetzen
            if(($hash->{helper}{ttsstate}>TTS_IDLE)&&($hash->{helper}{ttsstate}<TTS_RESTORE)) {
                $hash->{helper}{savedPlayerState}{power}="off" if(defined($hash->{helper}{savedPlayerState}));
                SB_PLAYER_SetTTSState($hash,TTS_STOP,1,0);
                RemoveInternalTimer( "TTSRestore:$name");
                InternalTimer( gettimeofday() + 0.01, 
                   "SB_PLAYER_tcb_TTSRestore",
                   "TTSRestore:$name", 
                   0 ); 
            }
            # CD 0031 end
        } elsif( $args[ 0 ] eq "reconnect" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" );         # CD 0030 u added to tags
        } else {
        }

    } elsif( $cmd eq "prefset" ) {
        if( $args[ 0 ] eq "server" ) {
            if( $args[ 1 ] eq "currentSong" ) {
#               readingsBulkUpdate( $hash, "currentMedia", $args[ 2 ] );            # CD 0014 deaktiviert
            } elsif( $args[ 1 ] eq "volume" ) {
                SB_PLAYER_UpdateVolumeReadings( $hash, $args[ 2 ], true );
            # CD 0000 start - handle 'prefset power' message for synced players
            } elsif( $args[ 1 ] eq "power" ) {
                if( $args[ 2 ] eq "1" ) {
                    #Log 0,"$name power on";
                    readingsBulkUpdate( $hash, "state", "on" );
                    readingsBulkUpdate( $hash, "power", "on" );
                    SB_PLAYER_Amplifier( $hash );
                    # CD 0030 send play only after power is on
                    if(defined($hash->{helper}{playAfterPowerOn})) {
                        IOWrite( $hash, "$hash->{PLAYERMAC} play ".$hash->{helper}{playAfterPowerOn}."\n" );
                        delete($hash->{helper}{playAfterPowerOn});
                    }
                    # CD 0030 end
                } elsif( $args[ 2 ] eq "0" ) {
                    #Log 0,"$name power off";
                    #readingsBulkUpdate( $hash, "presence", "absent" );       # CD 0013 deaktiviert, power sagt nichts über presence
                    readingsBulkUpdate( $hash, "state", "off" );
                    readingsBulkUpdate( $hash, "power", "off" );
                    SB_PLAYER_Amplifier( $hash );
                    delete($hash->{helper}{playAfterPowerOn}) if(defined($hash->{helper}{playAfterPowerOn}));   # CD 0030
                    # CD 0031 wenn Player während TTS ausgeschaltet wird nicht wieder einschalten
                    if(($hash->{helper}{ttsstate}>TTS_IDLE)&&($hash->{helper}{ttsstate}<TTS_RESTORE)) {
                        $hash->{helper}{savedPlayerState}{power}="off" if(defined($hash->{helper}{savedPlayerState}));
                        SB_PLAYER_SetTTSState($hash,TTS_STOP,1,0);
                        RemoveInternalTimer( "TTSRestore:$name");
                        InternalTimer( gettimeofday() + 0.01, 
                           "SB_PLAYER_tcb_TTSRestore",
                           "TTSRestore:$name", 
                           0 ); 
                    }
                    # CD 0031 end
                }
            # CD 0000 end
            # CD 0010 start prefset server mute
            } elsif( $args[ 1 ] eq "mute" ) {
                SB_PLAYER_SetSyncedVolume($hash, -1) if ($args[ 2 ] == 1);
                IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" ) if ($args[ 2 ] == 0);
            # CD 0010 end
            # CD 0016 start
            } elsif( $args[ 1 ] eq "alarmTimeoutSeconds" ) {
                readingsBulkUpdate( $hash, "alarmsTimeout", $args[ 2 ]/60 );
            } elsif( $args[ 1 ] eq "alarmSnoozeSeconds" ) {
                readingsBulkUpdate( $hash, "alarmsSnooze", $args[ 2 ]/60 );
            } elsif( $args[ 1 ] eq "alarmDefaultVolume" ) {
                readingsBulkUpdate( $hash, "alarmsDefaultVolume", $args[ 2 ]/60 );
            } elsif( $args[ 1 ] eq "alarmfadeseconds" ) {
                if($args[ 2 ] eq "1") {
                    readingsBulkUpdate( $hash, "alarmsFadeIn", "on" );
                } else {
                    readingsBulkUpdate( $hash, "alarmsFadeIn", "off" );
                }
            # CD 0016 end
            # CD 0018 start
            } elsif( $args[ 1 ] eq "syncgroupid" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" );     # CD 0030 u added to tags
            # CD 0018 end
            }
        } else {
            readingsBulkUpdate( $hash, "lastunkowncmd", 
                                  $cmd . " " . join( " ", @args ) );
        }

    # CD 0007 start
    } elsif( $cmd eq "playerpref" ) {
        if( $args[ 0 ] eq "syncVolume" ) {
            if (defined($args[1])) {
                $hash->{SYNCVOLUME}=$args[1];
                my $sva=AttrVal($hash->{NAME}, "syncVolume", undef);
                # force attribute
                if (defined($sva)) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playerpref syncVolume 0\n" ) if(($sva ne "1") && ($args[1] ne "0"));
                    IOWrite( $hash, "$hash->{PLAYERMAC} playerpref syncVolume 1\n" ) if(($sva eq "1") && ($args[1] ne "1"));
                }
            }
        }
        # CD 0007 end
        # CD 0016 start, von MM übernommen, Namen Readings geändert
        elsif( $args[ 0 ] eq "alarmsEnabled" ) {
          if (defined($args[1])) {
            if( $args[1] eq "1" ) {
                readingsBulkUpdate( $hash, "alarmsEnabled", "on" );    # CD 0016 Internal durch Reading ersetzt # CD 0017 'yes' durch 'on' ersetzt
            } else {
                readingsBulkUpdate( $hash, "alarmsEnabled", "off" );   # CD 0016 Internal durch Reading ersetzt # CD 0017 'no' durch 'off' ersetzt
            }
          }
        }

        elsif( $args[ 0 ] eq "alarmDefaultVolume" ) {
          if (defined($args[1]) && ($args[1] ne "?")) {         # CD 0016 Rückmeldung auf Anfrage ignorieren
            #$hash->{ALARMSVOLUME} = $args[1];                  # CD 0016 nicht benötigt
            readingsBulkUpdate( $hash, "alarmsDefaultVolume", $args[ 1 ] );
          }
        }

        elsif( $args[ 0 ] eq "alarmTimeoutSeconds" ) {
          if (defined($args[1]) && ($args[1] ne "?")) {         # CD 0016 Rückmeldung auf Anfrage ignorieren
            #$hash->{ALARMSTIMEOUT} = $args[1]/60 . " min";     # CD 0016 nicht benötigt
            readingsBulkUpdate( $hash, "alarmsTimeout", $args[ 1 ]/60 );
          }
        }

        elsif( $args[ 0 ] eq "alarmSnoozeSeconds" ) {
          if (defined($args[1]) && ($args[1] ne "?")) {         # CD 0016 Rückmeldung auf Anfrage ignorieren
            #$hash->{ALARMSSNOOZE} = $args[1]/60 . " min";      # CD 0016 nicht benötigt
            readingsBulkUpdate( $hash, "alarmsSnooze", $args[ 1 ]/60 );
          }
        }
        # CD 0016 end
    # CD 0014 start
    } elsif( $cmd eq "duration" ) {
        readingsBulkUpdate( $hash, "duration", $args[ 0 ] );
    } elsif( $cmd eq "time" ) {
        $hash->{helper}{elapsedTime}{VAL}=$args[ 0 ];
        $hash->{helper}{elapsedTime}{TS}=gettimeofday();
        delete($hash->{helper}{saveLocked}) if (($hash->{helper}{ttsstate}==TTS_IDLE) && defined($hash->{helper}{saveLocked}));
    } elsif( $cmd eq "playlist_tracks" ) {
        readingsBulkUpdate( $hash, "playlistTracks", $args[ 0 ] );
    # CD 0014 end
    # CD 0018 sync Meldungen auswerten, alle anderen Player abfragen
    } elsif( $cmd eq "sync" ) {
        foreach my $e ( keys %{$hash->{helper}{SB_PLAYER_SyncMasters}} ) {
            IOWrite( $hash, $hash->{helper}{SB_PLAYER_SyncMasters}{$e}{MAC}." status 0 500 tags:Kc\n" );
        }
    # CD 0018
    # CD 0022 fhemrelay ist keine Meldung des LMS sondern eine Info die von einem anderen Player über 98_SB_PLAYER kommt
    } elsif( $cmd eq "fhemrelay" ) {
        if (defined($args[0])) {
            # CD 0022 Favoriten vom Sync-Master übernehmen
            if ($args[0] eq "favorites") {
                if (defined($args[1])) {
                    $hash->{FAVSELECT} = $args[1];
                    readingsBulkUpdate( $hash, "$hash->{FAVSET}", "$hash->{FAVSELECT}" );
                }
            }
            # CD 0028 tts aktiv
            elsif ($args[0] eq "ttsactive") {
                $hash->{helper}{ttsMaster}=$args[1];
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsactive ".$hash->{helper}{ttsMaster} );
                SB_PLAYER_SetTTSState($hash,TTS_SYNCGROUPACTIVE,1,0);
                # CD 0031 Lautstärke setzen
                if(!defined($hash->{SYNCVOLUME}) || ($hash->{SYNCVOLUME}==0)) {
                    if(defined($hash->{helper}{ttsVolume})) {
                        $hash->{helper}{ttsRestoreVolumeAfterStop}=ReadingsVal($name,"volumeStraight","?");
                        my $vol=$hash->{helper}{ttsVolume};
                        $vol=AttrVal( $name, "volumeLimit", 100 ) if(( $hash->{helper}{ttsVolume} > AttrVal( $name, "volumeLimit", 100 ) )&&!defined($hash->{helper}{ttsOptions}{ignorevolumelimit}));
                        IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".$vol."\n" );
                    }
                }
                # CD 0031 end
            }
            elsif ($args[0] eq "ttsstopped") {
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsstopped" );
                if($hash->{helper}{ttsstate}==TTS_PLAYING) {
                        # CD 0034 delay ttsstopped 
                        RemoveInternalTimer( "TTSStopped:$name");
                        InternalTimer( gettimeofday() + 0.01, 
                           "SB_PLAYER_tcb_TTSStopped",
                           "TTSRestore:$name", 
                           0 );
                }
            }
            elsif ($args[0] eq "ttsplaying") {
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsplaying" );
                if($hash->{helper}{ttsstate}==TTS_WAITFORPLAY) {
                    SB_PLAYER_SetTTSState($hash,TTS_PLAYING,1,0);
                }
            }
            elsif ($args[0] eq "ttsidle") {
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsidle" );
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,1,0);
                # CD 0030 start
                if(defined($hash->{helper}{ttspoweroffafterstop})) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
                    delete($hash->{helper}{ttspoweroffafterstop});
                }
                # CD 0030 end
                # CD 0031 Lautstärke zurücksetzen
                if(defined($hash->{helper}{ttsRestoreVolumeAfterStop})) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".($hash->{helper}{ttsRestoreVolumeAfterStop})."\n" );
                    delete($hash->{helper}{ttsRestoreVolumeAfterStop});
                }
                # CD 0031 end
            }
            elsif ($args[0] eq "ttsadd") {
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsadd $args[1]" );
                push(@{$hash->{helper}{ttsqueue}},$args[1]);
            }
            # CD 0030 start
            elsif ($args[0] eq "ttsforcegroupon") {
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsforcegroupon" );
                if( $hash->{CANPOWEROFF} ne "0" ) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} power 1\n" );
                    $hash->{helper}{ttspoweroffafterstop}=1;
                }
            }
            # CD 0030 end
        }
    # CD 0022 end
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

# CD 0030
# ----------------------------------------------------------------------------
#  delay TTS
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TTSDelay( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    SB_PLAYER_SetTTSState($hash,TTS_WAITFORPLAY,0,0);
    IOWrite( $hash, "$hash->{PLAYERMAC} play\n" );
}
# CD 0030

# CD 0034
# ----------------------------------------------------------------------------
#  delay ttsstopped
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TTSStopped( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    readingsBeginUpdate( $hash );

    SB_PLAYER_TTSStopped($hash);

    if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
        readingsEndUpdate( $hash, 0 );
    } else {
        readingsEndUpdate( $hash, 1 );
    }
}
# CD 0034 end

# ----------------------------------------------------------------------------
#  called when talk is stopped, check if there are queued elements
# ----------------------------------------------------------------------------
sub SB_PLAYER_TTSStopped($) {
    # readingsBulkUpdate muss aktiv sein
    my ($hash) = @_;
    my $name = $hash->{NAME};

    if(defined($hash->{helper}{ttsqueue})) {
        SB_PLAYER_SetTTSState($hash,TTS_LOADPLAYLIST,1,0);
        SB_PLAYER_LoadTalk($hash);  # CD 0033
    } else {
        SB_PLAYER_SetTTSState($hash,TTS_STOP,1,0);
        RemoveInternalTimer( "TTSRestore:$name");
        InternalTimer( gettimeofday() + 0.01, 
           "SB_PLAYER_tcb_TTSRestore",
           "TTSRestore:$name", 
           0 );
    }
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

    Log3( $hash, 4, "SB_PLAYER_Get: called with @a" );

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
        
    } elsif( ( $cmd eq "volume" ) || ( $cmd eq "volumeStraight" ) ) {
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

# CD 0030 start
# ----------------------------------------------------------------------------
#  Calculate delay for TTS
# ----------------------------------------------------------------------------
sub SB_PLAYER_GetTTSDelay( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    
    # todo synced players
  
    if(defined($hash->{helper}{ttsDelay})) {
        if(ReadingsVal($name,"power","x") eq "on") {
            return $hash->{helper}{ttsDelay}{PowerIsOn}
        } else {
            return $hash->{helper}{ttsDelay}{PowerIsOff}
        }
    } else {
        return 0;
    }
}
# CD 0030 end

# CD 0033 start
# ----------------------------------------------------------------------------
#  called after Text2Speech has finished, start talk
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_StartT2STalk( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    if($hash->{helper}{ttsstate}==TTS_TEXT2SPEECH_ACTIVE) {
        # talk ist nicht aktiv
        SB_PLAYER_PrepareTalk($hash);
    }
    SB_PLAYER_LoadTalk($hash);
}
# CD 0033 end

# ----------------------------------------------------------------------------
#  the Notify function
# ----------------------------------------------------------------------------
sub SB_PLAYER_Notify( $$ ) {
    my ( $hash, $dev_hash ) = @_;
    my $name = $hash->{NAME}; # own name / hash
    my $devName = $dev_hash->{NAME}; # Device that created the events

    if ($dev_hash->{NAME} eq "global" && grep (m/^INITIALIZED$|^REREADCFG$/,@{$dev_hash->{CHANGED}})){
    }

    # CD 0033 start
    if(defined($hash->{helper}{text2speech}{name}) && ($hash->{helper}{text2speech}{name} eq $devName)) {
        $hash->{helper}{ttsExtstate}=TTS_IDLE if(!defined($hash->{helper}{ttsExtstate}));
    
        if(($hash->{helper}{ttsstate}==TTS_TEXT2SPEECH_ACTIVE)||($hash->{helper}{ttsExtstate}==TTS_EXT_TEXT2SPEECH_ACTIVE)) {
            foreach my $line (@{$dev_hash->{CHANGED}}) {
                my @args=split(' ',$line);
                if ($args[0] eq $name) {
                    if($args[1] eq "ttsadd") {
                        push(@{$hash->{helper}{ttsqueue}},$hash->{helper}{text2speech}{pathPrefix}.$args[2]);
                    }
                    elsif($args[1] eq 'ttsdone') {
                        RemoveInternalTimer( "StartTalk:$name");
                        InternalTimer( gettimeofday() + 0.01, 
                           "SB_PLAYER_tcb_StartT2STalk",
                           "StartTalk:$name", 
                           0 );
                    }
                }
            }
        } elsif (($hash->{helper}{ttsstate}==TTS_TEXT2SPEECH_BUSY)||($hash->{helper}{ttsExtstate}==TTS_EXT_TEXT2SPEECH_BUSY)) {
            # versuchen Text2Speech zu belegen
            if(defined($dev_hash->{helper}{SB_PLAYER}) || (defined($dev_hash->{helper}{Text2Speech}) && @{$dev_hash->{helper}{Text2Speech}} > 0)) {
                # zu spät, weiter warten
            } else {
                $dev_hash->{helper}{SB_PLAYER}=$name;
                if($hash->{helper}{ttsstate}==TTS_TEXT2SPEECH_BUSY) {
                    SB_PLAYER_SetTTSState($hash,TTS_TEXT2SPEECH_ACTIVE,0,0);
                } else {
                    $hash->{helper}{ttsExtstate}=TTS_EXT_TEXT2SPEECH_ACTIVE;
                }
                fhem("set $devName tts ".($hash->{helper}{text2speech}{text}));
                delete($hash->{helper}{text2speech}{text});
            }
        }
    }
    # CD 0033 end
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
            "save:noArg recall:noArg " . # CD 0014
            "volume:slider,0,1,100 " . 
            "volumeStraight:slider,0,1,100 " . 
            "volumeUp:noArg volumeDown:noArg " . 
            "mute:noArg repeat:off,one,all show statusRequest:noArg " . 
            "shuffle:off,on,song,album next:noArg prev:noArg playlist sleep " . # CD 0017 song und album hinzugefügt
            "allalarms:enable,disable,statusRequest,delete,add " .              # CD 0015 alarm1 alarm2 entfernt
            "alarmsSnooze:slider,0,1,30 alarmsTimeout:slider,0,5,90  alarmsDefaultVolume:slider,0,1,100 alarmsFadeIn:on,off alarmsEnabled:on,off " . # CD 0016, von MM übernommen, Namen geändert
            "cliraw talk sayText " .     # CD 0014 sayText hinzugefügt
            "unsync:noArg " .
            "resetTTS:noArg ";          # CD 0028 hinzugefügt
        # add the favorites
        $res .= $hash->{FAVSET} . ":-," . $hash->{FAVSTR} . " ";    # CD 0014 '-' hinzugefügt
        # add the syncmasters
        $res .= "sync:" . $hash->{SYNCMASTERS} . " ";
        # add the playlists
        $res .= "playlists:-," . $hash->{SERVERPLAYLISTS} . " ";    # CD 0014 '-' hinzugefügt
        # CD 0016 start {ALARMSCOUNT} verschieben nach reload
        if (defined($hash->{ALARMSCOUNT})) {
            $hash->{helper}{ALARMSCOUNT}=$hash->{ALARMSCOUNT};
            delete($hash->{ALARMSCOUNT});
        }
        # CD 0016 end
        # CD 0015 - add the alarms
        if (defined($hash->{helper}{ALARMSCOUNT})&&($hash->{helper}{ALARMSCOUNT}>0)) {  # CD 0016 ALARMSCOUNT nach {helper} verschoben
            for(my $i=1;$i<=$hash->{helper}{ALARMSCOUNT};$i++) {                        # CD 0016 ALARMSCOUNT nach {helper} verschoben
                $res .="alarm$i ";
            }
        }
        return( $res );
    }

    my $updateReadingsOnSet=AttrVal($name, "updateReadingsOnSet", false);           # CD 0017
    my $donotnotify=AttrVal($name, "donotnotify", "true");                          # CD 0017 # CD 0028 added "
    
    # as we have some other command, we need to turn on the server
    #if( AttrVal( $name, "serverautoon", "true" ) eq "true" ) {
       #SB_PLAYER_ServerTurnOn( $hash );
    #}

    if( ( $cmd eq "Stop" ) || ( $cmd eq "STOP" ) || ( $cmd eq "stop" ) ) {
        IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );

    } elsif( ( $cmd eq "Play" ) || ( $cmd eq "PLAY" ) || ( $cmd eq "play" ) ) {
        my $secbuf = AttrVal( $name, "fadeinsecs", 10 );
        # CD 0030 wait until power on
        if(ReadingsVal($name,"power","x") eq "on") {
            IOWrite( $hash, "$hash->{PLAYERMAC} play $secbuf\n" );
        } else {
            $hash->{helper}{playAfterPowerOn}=$secbuf;
            IOWrite( $hash, "$hash->{PLAYERMAC} power 1\n" );
        }
        # CD 0030 end
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
        if(( @arg != 1 )&&( @arg != 2 )) {
            my $msg = "SB_PLAYER_Set: no arguments for Vol given.";
            Log3( $hash, 3, $msg );
            return( $msg );
        }
        # set the volume to the desired level. Needs to be 0..100
        # no error checking here, as the server does this
        if( $arg[ 0 ] <= AttrVal( $name, "volumeLimit", 100 ) ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $arg[ 0 ]\n" );
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,$arg[0]) if (!defined($arg[1]));
        } else {
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume " . 
                     AttrVal( $name, "volumeLimit", 50 ) . "\n" );
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,AttrVal( $name, "volumeLimit", 50 )) if (!defined($arg[1]));
        }

    } elsif( $cmd eq $hash->{FAVSET} ) {
        if ($arg[0] ne '-') {       # CD 0014
            if( defined( $hash->{helper}{SB_PLAYER_Favs}{$arg[0]}{ID} ) ) {
                my $fid = $hash->{helper}{SB_PLAYER_Favs}{$arg[0]}{ID};
                IOWrite( $hash, "$hash->{PLAYERMAC} favorites playlist " . 
                         "play item_id:$fid\n" );
                $hash->{FAVSELECT} = $arg[ 0 ];
                readingsSingleUpdate( $hash, "$hash->{FAVSET}", "$arg[ 0 ]", 1 );
                # SB_PLAYER_GetStatus( $hash ); # CD 0021 deaktiviert, zu früh
            }
        }       # CD 0014

    } elsif( ( $cmd eq "volumeUp" ) || ( $cmd eq "VOLUMEUP" ) || 
             ( $cmd eq "VolumeUp" ) ) {
        # increase volume
        if( ( ReadingsVal( $name, "volumeStraight", 50 ) + 
              AttrVal( $name, "volumeStep", 10 ) ) <= 
            AttrVal( $name, "volumeLimit", 100 ) ) {
            my $volstr = sprintf( "+%02d", AttrVal( $name, "volumeStep", 10 ) );
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $volstr\n" );
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,$volstr);
        } else {
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume " . 
                     AttrVal( $name, "volumeLimit", 50 ) . "\n" );
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,AttrVal( $name, "volumeLimit", 50 ));
        }

    } elsif( ( $cmd eq "volumeDown" ) || ( $cmd eq "VOLUMEDOWN" ) || 
             ( $cmd eq "VolumeDown" ) ) {
        my $volstr = sprintf( "-%02d", AttrVal( $name, "volumeStep", 10 ) );
        IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $volstr\n" );
        # CD 0007
        SB_PLAYER_SetSyncedVolume($hash,$volstr);
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
            readingsSingleUpdate( $hash, "repeat", "off", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        } elsif( $arg[ 0 ] eq "one" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 1\n" );
            readingsSingleUpdate( $hash, "repeat", "one", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        } elsif( $arg[ 0 ] eq "all" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 2\n" );
            readingsSingleUpdate( $hash, "repeat", "all", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
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
            readingsSingleUpdate( $hash, "shuffle", "off", $donotnotify ) if($updateReadingsOnSet);     # CD 0017
        } elsif(( $arg[ 0 ] eq "on" ) || ($arg[ 0 ] eq "song" )) {                                      # CD 0017 'song' hinzugefügt
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle 1\n" );
            readingsSingleUpdate( $hash, "shuffle", "song", $donotnotify ) if($updateReadingsOnSet);    # CD 0017
        # CD 0017 start
        } elsif( $arg[ 0 ] eq "album" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle 2\n" );
            readingsSingleUpdate( $hash, "shuffle", "album", $donotnotify ) if($updateReadingsOnSet);
        # CD 0017 end
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
             ( $cmd eq "talk" ) ||
             ( lc($cmd) eq "saytext" ) ) {  # CD 0014 hinzugefügt

        $hash->{helper}{ttsstate}=TTS_IDLE if(!defined($hash->{helper}{ttsstate}));
        $hash->{helper}{ttsExtstate}=TTS_IDLE if(!defined($hash->{helper}{ttsExtstate}));

        # CD 0032 - Text2Speech verwenden ?
        # CD 0033 - überarbeitet
        my $useText2Speech=0;
        my $errMsg;
        if(AttrVal( $name, "ttslink", "none" )=~m/^Text2Speech/) {
            my @extTTS=split(":",AttrVal( $name, "ttslink", "none" ));
            # Device überhaupt verwendbar ?
            if(defined($extTTS[1]) && defined($defs{$extTTS[1]})) {
                my $ttshash=$defs{$extTTS[1]};
                if(defined($ttshash->{TYPE}) && ($ttshash->{TYPE} eq 'Text2SpeechSB')) {
                    if(defined($ttshash->{ALSADEVICE}) && ($ttshash->{ALSADEVICE} eq 'SB_PLAYER')) {
                        if (AttrVal($hash->{NAME}, "TTS_Ressource", "Google") eq "Google") {
                            $useText2Speech=1;
                            $hash->{helper}{text2speech}{name}=$extTTS[1];
                            $hash->{helper}{text2speech}{pathPrefix}=join(':',@extTTS[2..$#extTTS]) if defined($extTTS[2]);
                            # Zustand Text2Speech ?
                            if(defined($ttshash->{helper}{SB_PLAYER}) || (defined($ttshash->{helper}{Text2Speech}) && @{$ttshash->{helper}{Text2Speech}} > 0)) {
                                # Text2Speech besetzt, warten
                                if($hash->{helper}{ttsstate}==TTS_IDLE) {
                                    SB_PLAYER_SetTTSState($hash,TTS_TEXT2SPEECH_BUSY,0,0);
                                } else {
                                    $hash->{helper}{ttsExtstate}=TTS_EXT_TEXT2SPEECH_BUSY if($hash->{helper}{ttsExtstate}==TTS_IDLE);
                                }
                                if(defined($hash->{helper}{text2speech}{text})) {
                                    $hash->{helper}{text2speech}{text}.=" " . join( " ", @arg );
                                } else {
                                    $hash->{helper}{text2speech}{text}=join( " ", @arg );
                                }
                                return;
                            } else {
                                # Text2Speech belegen
                                $ttshash->{helper}{SB_PLAYER}=$name;
                                if($hash->{helper}{ttsstate}==TTS_IDLE) {
                                    SB_PLAYER_SetTTSState($hash,TTS_TEXT2SPEECH_ACTIVE,0,0);
                                } else {
                                    $hash->{helper}{ttsExtstate}=TTS_EXT_TEXT2SPEECH_ACTIVE;
                                }
                                fhem("set $extTTS[1] tts ".join( " ", @arg ));
                                return;
                            }
                        } else {
                            $errMsg = "SB_PLAYER_Set: ".$extTTS[1].": attribute TTS_Ressource must be set to Google";
                        }
                    } else {
                        $errMsg = "SB_PLAYER_Set: ".$extTTS[1].": Text2Speech uses unsupported ALSADEVICE";
                    }
                } else {
                    $errMsg = "SB_PLAYER_Set: ".$extTTS[1].": unsupported Text2Speech device";
                }
            } else {
                $errMsg = "SB_PLAYER_Set: invalid Text2Speech device";
            }
        }
        if(defined($errMsg)) {
            Log3( $hash, 1, $errMsg );
            return( $errMsg );
        }

        # CD 0028 start - komplett überarbeitet
        # prepare text
        my $ttstext=join( " ", @arg );
        $ttstext = AttrVal( $name, "ttsPrefix", "" )." ".$ttstext;  # CD 0032

        my %Sonderzeichen = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss",
                        "é" => "e", "è" => "e", "ë" => "e", "à" => "a", "ç" => "c" );
        my $Sonderzeichenkeys = join ("|", keys(%Sonderzeichen));

        if (length($ttstext)==0) {
            my $msg = "SB_PLAYER_Set: no text passed for synthesis.";
            Log3( $hash, 3, $msg );
            return( $msg );
        }
        $ttstext .= "." unless ($ttstext =~ m/^.+[.,?!:;]$/);
        my @textlines;
        my $tl='';
        # CD 0033 Unterstützung für Dateien und URLs hinzugefügt, teilweise aus 00_SONOS übernommen
        my $targetSpeakMP3FileDir = AttrVal( $name, "ttsMP3FileDir", "" );  # CD 0033
        if (length($ttstext)>0) {
            my @words=split(' ',$ttstext);
            for my $w (@words) {
                # CD 0033 Datei ?, teilweise aus 00_SONOS übernommen
                if ($w =~ m/\|(.*)\|/) {
                    push(@textlines,$tl) if($tl ne '');
                    $tl='';
                
                    my $filename = $1;
                    $filename = $targetSpeakMP3FileDir.'/'.$filename if ($filename !~ m/^(\/|[a-z]:)/i);
                    $filename = $filename.'.mp3' if ($filename !~ m/\.mp3$/i);
                    push(@textlines, '|'.$filename.'|');            
                } else {
                    $w =~ s/[\\|*~<>^\n\(\)\[\]\{\}[:cntrl:]]/ /g;
                    $w =~ s/\s+/ /g;
                    $w =~ s/^\s|\s$//g;
                    $w =~ s/($Sonderzeichenkeys)/$Sonderzeichen{$1}/g;
                # CD 0032 end
                    if((length($tl)+length($w)+1)<100) {
                        $tl.=' ' if(length($tl)>0);
                        $tl.=$w;
                    } else {
                        push(@textlines,$tl);
                        $tl=$w;
                    }
                }
            }
        }
        push(@textlines,$tl) if($tl ne '');

        if($hash->{helper}{ttsstate}==TTS_IDLE) {
            # talk ist nicht aktiv
            SB_PLAYER_PrepareTalk($hash);
        } else {
        
        }
        for my $outstr (@textlines) {
            if ($outstr =~ m/\|(.*)\|/) {               # CD 0033
                push(@{$hash->{helper}{ttsqueue}},$1);  # CD 0033
            } else {
                $outstr =~ s/\s/+/g;
                $outstr = uri_escape( $outstr );
                $outstr = AttrVal( $name, "ttslink", "none" )  
                    . "&tl=" . AttrVal( $name, "ttslanguage", "de" )
                    . "&q=". $outstr;
                push(@{$hash->{helper}{ttsqueue}},$outstr);
            }
        }
        
        SB_PLAYER_LoadTalk($hash);  # CD 0033

        # CD 0028 end
    } elsif( ( $cmd eq "playlist" ) || 
             ( $cmd eq "PLAYLIST" ) || 
             ( $cmd eq "Playlist" ) ) {
        #if( ( @arg != 2 ) && ( @arg != 3 ) ) {             # CD 0014 deaktiviert
        if( @arg < 2) {                                     # CD 0014
            my $msg = "SB_PLAYER_Set: no arguments for Playlist given.";
            Log3( $hash, 3, $msg );
            return( $msg );
        }
        # CD 0014 start
        if (@arg>1) {
            my $outstr = uri_escape(decode('utf-8',join( " ", @arg[1..$#arg])));        # CD 0017

            Log3( $hash, 5, "SB_PLAYER_Set($name): playlists command = $arg[ 0 ] param = $outstr" );

            if( $arg[ 0 ] eq "track" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
                         "track.titlesearch:$outstr\n" );
            } elsif( $arg[ 0 ] eq "album" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
                         "album.titlesearch:$outstr\n" );
            } elsif( $arg[ 0 ] eq "artist" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
                         "contributor.namesearch:$outstr\n" );           # CD 0014 'titlesearch' durch 'namesearch' ersetzt
            } elsif( $arg[ 0 ] eq "play" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist play $outstr\n" );
            } elsif( $arg[ 0 ] eq "year" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
                         "track.year:$outstr\n" );
            } elsif( $arg[ 0 ] eq "genre" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
                         "genre.namesearch:$outstr\n" );
            #} elsif( $arg[ 0 ] eq "comment" ) {                                # CD 0014 funktioniert nicht
            #    IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " . 
            #             "comments.value:$outstr\n" );
            } else {
            }
        # CD 0014 end
        } else {
            # what the f... we checked beforehand
        }

    } elsif( $cmd eq "allalarms" ) {
        if( $arg[ 0 ] eq "enable" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmsEnabled 1\n" );        # MM 0016
            readingsSingleUpdate( $hash, "alarmsEnabled", "on", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        } elsif( $arg[ 0 ] eq "disable" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmsEnabled 0\n" );        # MM 0016
            readingsSingleUpdate( $hash, "alarmsEnabled", "off", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        } elsif( $arg[ 0 ] eq "statusRequest" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" );  # CD 0015 filter added
            # CD 0016 start
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmsEnabled ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmDefaultVolume ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmTimeoutSeconds ?\n" );
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmSnoozeSeconds ?\n" );
            # CD 0016 end
        # CD 0015 start
        } elsif( $arg[ 0 ] eq "delete" ) {
            $hash->{helper}{deleteAllAlarms}=1;
            for(my $i=1;$i<=$hash->{helper}{ALARMSCOUNT};$i++) {    # CD 0016 ALARMSCOUNT nach {helper} verschoben
                IOWrite( $hash, "$hash->{PLAYERMAC} alarm delete id:". ReadingsVal($name,"alarm".$i."_id","0"). "\n" );
            }
            IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" );  # CD 0015 filter added
        } elsif( $arg[ 0 ] eq "add" ) {
            $arg[ 0 ]="set";
            SB_PLAYER_Alarm( $hash, 0, @arg );
        # CD 0015 end
        } else {
        }
    # CD 0016 start, von MM übernommen, Namen geändert
    } elsif( index( $cmd, "alarms" ) != -1 ) {
        if($cmd eq "alarmsSnooze") {
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmSnoozeSeconds ". $arg[0]*60 ."\n" );
            readingsSingleUpdate( $hash, "alarmsSnooze", $arg[ 0 ], $donotnotify ) if($updateReadingsOnSet);   # CD 0017
        } elsif($cmd eq "alarmsTimeout") {
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmTimeoutSeconds ". $arg[0]*60 ."\n" );
            readingsSingleUpdate( $hash, "alarmsTimeout", $arg[ 0 ], $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        } elsif($cmd eq "alarmsDefaultVolume") {
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmDefaultVolume ". $arg[0] ."\n" );
            readingsSingleUpdate( $hash, "alarmsDefaultVolume", $arg[ 0 ], $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        } elsif($cmd eq "alarmsFadeIn") {
            if($arg[0] eq 'on') {
                IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmfadeseconds 1\n" );
                readingsSingleUpdate( $hash, "alarmsFadeIn", "on", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
            } else {
                IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmfadeseconds 0\n" );
                readingsSingleUpdate( $hash, "alarmsFadeIn", "off", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
            }
        } elsif($cmd eq "alarmsEnabled") {
            if( $arg[ 0 ] eq "on" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmsEnabled 1\n" );
                readingsSingleUpdate( $hash, "alarmsEnabled", "on", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
            } else {
                IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmsEnabled 0\n" );
                readingsSingleUpdate( $hash, "alarmsEnabled", "off", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
            }
        }
    # CD 0016
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

    # CD 0014 start
    } elsif( ( $cmd eq "save" ) || ( $cmd eq "SAVE" ) ) {
        SB_PLAYER_Save($hash);
    } elsif( ( $cmd eq "recall" ) || ( $cmd eq "RECALL" ) ) {
        SB_PLAYER_Recall($hash);
    # CD 0014 end
    } elsif( $cmd eq "statusRequest" ) {
        RemoveInternalTimer( $hash );
        SB_PLAYER_GetStatus( $hash );

    } elsif( $cmd eq "sync" ) {
        # CD 0018 wenn der Player bereits in einer Gruppe ist und 'new' ist vorhanden, wird der Player zuerst aus der Gruppe entfernt
        if(( @arg == 2) && ($arg[1] eq "new") && ($hash->{SYNCED} eq 'yes')) {
            IOWrite( $hash, "$hash->{PLAYERMAC} sync -\n" );
            # CD 0028 start
            if($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE) {
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,1,0);            
            }
            # CD 0028 end
        }
        # CD 0018 end
        # CD 0018 Synchronisation mehrerer Player 
        if(( @arg == 1 ) || ( @arg == 2)) {
            my $msg;
            my $dev;
            my @dvs=();
            my $doGetStatus=0;
            @dvs=split(",",$arg[0]);
            foreach (@dvs) {
                my $dev=$_;
                # CD 0018 end
                if( defined( $hash->{helper}{SB_PLAYER_SyncMasters}{$dev}{MAC} ) ) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} sync " . 
                             "$hash->{helper}{SB_PLAYER_SyncMasters}{$dev}{MAC}\n" );
                    $doGetStatus=1;
                } else {
                    my $msg = "SB_PLAYER_Set: no MAC for player ".$dev.".";
                    Log3( $hash, 3, $msg );
                    #return( $msg );        # CD 0018 wenn keine MAC vorhanden weitermachen
                }
            }   # CD 0018
            SB_PLAYER_GetStatus( $hash ) if($doGetStatus==1);
        }
        # CD 0018 end
    } elsif( $cmd eq "unsync" ) {
        IOWrite( $hash, "$hash->{PLAYERMAC} sync -\n" );
        SB_PLAYER_GetStatus( $hash );
        # CD 0028 start
        if($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE) {
            SB_PLAYER_SetTTSState($hash,TTS_IDLE,1,0);            
        }
        # CD 0028 end
    } elsif( $cmd eq "playlists" ) {
        if( @arg == 1 ) {
            my $msg;
            if( defined( $hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{ID} ) ) {
                $msg = "$hash->{PLAYERMAC} playlistcontrol cmd:load " . 
                    "playlist_id:$hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{ID}";
                Log3( $hash, 5, "SB_PLAYER_Set($name): playlists command = " . 
                      $msg . " ........  with $arg[0]" );
                IOWrite( $hash, $msg . "\n" );
                readingsSingleUpdate( $hash, "playlists", "$arg[ 0 ]", 1 );
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
    } elsif( $cmd eq "resetTTS" ) {
        SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
    } else {
        my $msg = "SB_PLAYER_Set: unsupported command given";
        Log3( $hash, 3, $msg );
        return( $msg );
    }
    
    return( undef );
    
}

# CD 0033 hinzugefügt
# ----------------------------------------------------------------------------
#  add talk segments to playlist
# ----------------------------------------------------------------------------
sub SB_PLAYER_LoadTalk($) {
    # gespeicherte Elemente in Playlist einfügen
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if(defined($hash->{helper}{ttsqueue})) {
        if(($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST)||($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE)) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n" ) if($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST);
            for (@{$hash->{helper}{ttsqueue}}) {
                if($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST) {
                    # ich bin Master und talk ist nicht aktiv
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist add " . $_ . "\n" );
                } else {
                    # talk ist aktiv und ein anderer Player ist Master
                    IOWrite( $hash, $hash->{helper}{ttsMaster}." fhemrelay ttsadd ".$_."\n" );
                }
            }
            delete($hash->{helper}{ttsqueue});

            if($hash->{helper}{ttsstate}!=TTS_SYNCGROUPACTIVE) {
                # andere Player in Gruppe informieren
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                    my @pl=split(",",$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER});
                    foreach (@pl) {
                        if ($hash->{PLAYERMAC} ne $_) {
                            IOWrite( $hash, "$_ fhemrelay ttsactive ".$hash->{PLAYERMAC}."\n" );
                            IOWrite( $hash, "$_ fhemrelay ttsforcegroupon\n" ) if(defined($hash->{helper}{ttsOptions}{forcegroupon}));  # CD 0030
                        }
                    }
                }
            }
        } else {
            # talk ist aktiv und ich bin Master
            # warten bis stop
        }
    }
}

# CD 0033 hinzugefügt
# ----------------------------------------------------------------------------
#  prepare player for talk
# ----------------------------------------------------------------------------
sub SB_PLAYER_PrepareTalk($) {
    # kein readingsBulkUpdate
    # aktuellen Stand abspeichern, playlist löschen, Lautstärke setzen
    
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    # talk ist nicht aktiv
    if(!defined($hash->{helper}{ttsOptions}{nosaverestore})) {
        SB_PLAYER_SetTTSState($hash,TTS_SAVE,0,0);
        SB_PLAYER_Save( $hash ) if(!defined($hash->{helper}{saveLocked}));
    }
    $hash->{helper}{saveLocked}=1;
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 0\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n" );
    if(defined($hash->{helper}{ttsVolume})) {
        SB_PLAYER_SetTTSState($hash,TTS_SETVOLUME,0,0);
        my $vol=$hash->{helper}{ttsVolume};
        $vol=AttrVal( $name, "volumeLimit", 100 ) if(( $hash->{helper}{ttsVolume} > AttrVal( $name, "volumeLimit", 100 ) )&&!defined($hash->{helper}{ttsOptions}{ignorevolumelimit})); # CD 0031
        IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".$vol."\n" );
        SB_PLAYER_SetSyncedVolume($hash,$hash->{helper}{ttsVolume});
    }
    SB_PLAYER_SetTTSState($hash,TTS_LOADPLAYLIST,0,0);
}

# CD 0014 start
# ----------------------------------------------------------------------------
#  recall player state
# ----------------------------------------------------------------------------
sub SB_PLAYER_Recall($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    # wurde überhaupt etwas gespeichert ?
    if(defined($hash->{helper}{savedPlayerState})) {
        # CD 0029 start
        if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
            Log3( $hash, 0, "SB_PLAYER_Recall: $name: restoring...");
            $hash->{helper}{ttsOptions}{logloaddone}=1;
            $hash->{helper}{ttsOptions}{logplay}=1;
        }
        # CD 0029 end
        IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle 0\n");
        if (defined($hash->{helper}{savedPlayerState}{playlistIds})) {
            # wegen Shuffle Playlist neu erzeugen
            # CD 0030 start
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n");
            my @playlistIds=split(',',$hash->{helper}{savedPlayerState}{playlistIds});
            for my $id (@playlistIds) {
                if($id>=0) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlistcontrol cmd:add track_id:".$id."\n");
                } else {
                    if(defined($hash->{helper}{savedPlayerState}{playlistUrls}) && defined($hash->{helper}{savedPlayerState}{playlistUrls}{$id})) {
                        IOWrite( $hash, "$hash->{PLAYERMAC} playlist add ".$hash->{helper}{savedPlayerState}{playlistUrls}{$id}."\n");
                    } else {
                        Log3( $hash, 2, "SB_PLAYER_Recall: $name: no url found for id ".$id);
                    }
                }
            }
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist index ".$hash->{helper}{savedPlayerState}{playlistCurrentTrack}."\n");
            # CD 0030 end
        } else {
            # auf dem Server gespeichterte Playlist fortsetzen
            if( $hash->{helper}{savedPlayerState}{playStatus} eq "playing" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME}\n" );
            } else {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME} noplay:1\n" );
            }
        }
        if ($hash->{helper}{savedPlayerState}{volumeStraight} ne '?') {
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $hash->{helper}{savedPlayerState}{volumeStraight}\n" );
            SB_PLAYER_SetSyncedVolume($hash,$hash->{helper}{savedPlayerState}{volumeStraight});
        }
        if ($hash->{helper}{savedPlayerState}{repeat} ne ReadingsVal($name,"repeat","?")) {
            if( $hash->{helper}{savedPlayerState}{repeat} eq "off" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 0\n" );
            } elsif( $hash->{helper}{savedPlayerState}{repeat} eq "one" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 1\n" );
            } elsif( $hash->{helper}{savedPlayerState}{repeat} eq "all" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 2\n" );
            }
        }
        # CD 0028 start
        if ($hash->{helper}{savedPlayerState}{power} eq "off") {
            IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
            if($hash->{helper}{ttsstate}==TTS_RESTORE) {
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
            }
        } else {
        # CD 0028 end
            if ($hash->{helper}{savedPlayerState}{playStatus} eq "stopped" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );
                # CD 0028 start
                if($hash->{helper}{ttsstate}==TTS_RESTORE) {
                    SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
                }
                # CD 0028 end
            } elsif( $hash->{helper}{savedPlayerState}{playStatus} eq "playing" ) {
                my $secbuf = AttrVal( $name, "fadeinsecs", 10 );
                IOWrite( $hash, "$hash->{PLAYERMAC} play $secbuf\n" );
                IOWrite( $hash, "$hash->{PLAYERMAC} time $hash->{helper}{savedPlayerState}{elapsedTime}\n" ) if(defined($hash->{helper}{savedPlayerState}{elapsedTime}));
                # CD 0028 start
                if($hash->{helper}{ttsstate}==TTS_RESTORE) {
                    SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
                }
                # CD 0028 end
            } elsif( $hash->{helper}{savedPlayerState}{playStatus} eq "paused" ) {
                # paused kann nicht aus stop erreicht werden -> Playlist starten und dann pausieren
                $hash->{helper}{recallPause}=1;
                $hash->{helper}{recallPending}=1;
            }
        }
        # CD 0028 restore names
        readingsSingleUpdate( $hash,"playlists", $hash->{helper}{savedPlayerState}{playlist},(AttrVal($name, "donotnotify", "true") eq "true")?0:1) if(defined($hash->{helper}{savedPlayerState}{playlist}));
        readingsSingleUpdate( $hash,"favorites", $hash->{helper}{savedPlayerState}{favorite},(AttrVal($name, "donotnotify", "true") eq "true")?0:1) if(defined($hash->{helper}{savedPlayerState}{favorite}));
    }
}

sub SB_PLAYER_SetTTSState($$$$) {
    my ( $hash, $state, $bulk, $broadcast ) = @_;
    my $name = $hash->{NAME};

    return if($state eq $hash->{helper}{ttsstate});
    
    $hash->{helper}{ttsstate}=$state;
    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_SetTTSState: $name: ttsstate: ".$ttsstates{$hash->{helper}{ttsstate}} );
    if($bulk==1) {
        readingsBulkUpdate( $hash,"talkStatus", $ttsstates{$hash->{helper}{ttsstate}} );
    } else {
        readingsSingleUpdate( $hash,"talkStatus", $ttsstates{$hash->{helper}{ttsstate}},(AttrVal($name, "donotnotify", "true") eq "true")?0:1);
    }

    if($broadcast==1) {
        if($state==TTS_IDLE) {
            if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                my @pl=split(",",$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER});
                foreach (@pl) {
                    if ($hash->{PLAYERMAC} ne $_) {
                        IOWrite( $hash, "$_ fhemrelay ttsidle\n" );
                    }
                }
            }
        }
    }
    delete($hash->{helper}{ttsqueue}) if(defined($hash->{helper}{ttsqueue}) && ($state==TTS_IDLE));
}

# ----------------------------------------------------------------------------
#  save player state
# ----------------------------------------------------------------------------
sub SB_PLAYER_Save($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    delete($hash->{helper}{savedPlayerState}) if(defined($hash->{helper}{savedPlayerState}));
    SB_PLAYER_EstimateElapsedTime($hash);
    $hash->{helper}{savedPlayerState}{power}=ReadingsVal($name,"power","on");   # CD 0028
    $hash->{helper}{savedPlayerState}{SYNCGROUP}=$hash->{SYNCGROUP} if(defined($hash->{SYNCGROUP}));    # CD 0028
    $hash->{helper}{savedPlayerState}{SYNCMASTER}=$hash->{SYNCMASTER} if(defined($hash->{SYNCMASTER})); # CD 0028
    $hash->{helper}{savedPlayerState}{elapsedTime}=$hash->{helper}{elapsedTime}{VAL};
    $hash->{helper}{savedPlayerState}{playlistCurrentTrack}=ReadingsVal($name,"playlistCurrentTrack",1)-1;
    $hash->{helper}{savedPlayerState}{playStatus}=ReadingsVal($name,"playStatus","?");
    $hash->{helper}{savedPlayerState}{repeat}=ReadingsVal($name,"repeat","?");
    $hash->{helper}{savedPlayerState}{volumeStraight}=ReadingsVal($name,"volumeStraight","?");
    $hash->{helper}{savedPlayerState}{playlist}=ReadingsVal($name,"playlists","-");
    $hash->{helper}{savedPlayerState}{favorite}=ReadingsVal($name,"favorites","-");

    # CD 0029 start
    delete($hash->{helper}{ttsOptions}{logloaddone}) if(defined($hash->{helper}{ttsOptions}{logloaddone}));
    delete($hash->{helper}{ttsOptions}{logplay}) if(defined($hash->{helper}{ttsOptions}{logplay}));
    # CD 0029 end

    # nur 1 Track -> playlist save verwenden
    if((ReadingsVal($name,"playlistTracks",1)<=1)&&(!defined($hash->{helper}{ttsOptions}{internalsave}))) {
        IOWrite( $hash, "$hash->{PLAYERMAC} playlist save fhem_$hash->{NAME} silent:1\n" );
        # CD 0029 start
        if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
            Log3( $hash, 0, "SB_PLAYER_Save: $name: 1 track in playlist, using playlist save");
        }
        # CD 0029 end
    } else {
        # mehr als 1 Track, auf shuffle prüfen (playlist resume funktioniert nicht richtig wenn shuffle nicht auf off steht)
        # bei negativen Ids (Remote-Streams) und shuffle geht die vorherige Reihenfolge verloren, kein Workaround bekannt
        # es werden maximal 500 Ids gespeichert, bei mehr als 500 Einträgen in der Playlists geht die vorherige Reihenfolge verloren (zu ändern)
        if ((    (ReadingsVal($name,"shuffle","?") eq "off") ||
                (!defined($hash->{helper}{playlistIds})) ||
                ($hash->{helper}{playlistIds}=~ /-/) ||
                (ReadingsVal($name,"playlistTracks",0)>500)) && !defined($hash->{helper}{ttsOptions}{internalsave})) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist save fhem_$hash->{NAME} silent:1\n" );
            # CD 0029 start
            if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
                Log3( $hash, 0, "SB_PLAYER_Save: $name: multiple tracks in playlist, using playlist save");
            }
            # CD 0029 end
        } else {
            $hash->{helper}{savedPlayerState}{playlistIds}=$hash->{helper}{playlistIds};
            $hash->{helper}{savedPlayerState}{playlistUrls}=$hash->{helper}{playlistUrls};
            if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
                # CD 0029 start
                if(defined($hash->{helper}{ttsOptions}{internalsave})) {
                    Log3( $hash, 0, "SB_PLAYER_Save: $name: forcing {helper}{playlistIds}: ".$hash->{helper}{playlistIds}) if(defined($hash->{helper}{playlistIds}));  # CD 0033 if added
                    #Log3( $hash, 0, "SB_PLAYER_Save: $name: warning - negative playlist ids cannot be restored") if ($hash->{helper}{playlistIds}=~ /-/);
                } else {
                    Log3( $hash, 0, "SB_PLAYER_Save: $name: multiple tracks in playlist, shuffle active, using {helper}{playlistIds} (".$hash->{helper}{playlistIds}.")");
                }
                # CD 0029 end
            }
        }
    }
    # CD 0029 start
    if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
        Log3( $hash, 0, "SB_PLAYER_Save: $name: power ".$hash->{helper}{savedPlayerState}{power} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: elapsedTime ".$hash->{helper}{savedPlayerState}{elapsedTime} ) if (defined($hash->{helper}{savedPlayerState}{elapsedTime} ));
        Log3( $hash, 0, "SB_PLAYER_Save: $name: playlistCurrentTrack ".$hash->{helper}{savedPlayerState}{playlistCurrentTrack} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: playStatus ".$hash->{helper}{savedPlayerState}{playStatus} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: repeat ".$hash->{helper}{savedPlayerState}{repeat} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: volumeStraight ".$hash->{helper}{savedPlayerState}{volumeStraight} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: playlist ".$hash->{helper}{savedPlayerState}{playlist} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: favorite ".$hash->{helper}{savedPlayerState}{favorite} );
    }
    # CD 0029 end
}
# CD 0014 end

# ----------------------------------------------------------------------------
#  set Alarms of the Player
# ----------------------------------------------------------------------------
# CD 0015 angepasst für größere Anzahl an Alarmen
sub SB_PLAYER_Alarm( $$@ ) {
    my ( $hash, $n, @arg ) = @_;

    my $name = $hash->{NAME};

    # CD 0015 deaktiviert
    #if( ( $n != 1 ) && ( $n != 2 ) ) {
    #    Log3( $hash, 1, "SB_PLAYER_Alarm: $name: wrong ID given. Must be 1|2" );
    #    return;
    #}   

    my $id = ReadingsVal( "$name", "alarm".$n."_id", "none" );  # CD 0015 angepasst
    my $updateReadingsOnSet=AttrVal($name, "updateReadingsOnSet", false);          # CD 0017
    my $donotnotify=AttrVal($name, "donotnotify", true);                           # CD 0017

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
            IOWrite( $hash, "$hash->{PLAYERMAC} alarm delete id:$id\n" );   # CD 0020 'id' fehlt
            # readingsSingleUpdate( $hash, "alarmid$n", "none", 0 );        # CD 0015 deaktiviert
        }
        
        my $dow = SB_PLAYER_CheckWeekdays($arg[ 1 ]);                       # CD 0016 hinzugefügt
      
        # split the time string up
        my @buf = split( ":", $arg[ 2 ] );
        $buf[ 2 ] = 0 if( scalar( @buf ) == 2 );                            # CD 0016, von MM übernommen, geändert
        if( scalar( @buf ) != 3 ) {
            my $msg = "SB_PLAYER_Set: please use hh:mm:ss for alarm time.";
            Log3( $hash, 3, $msg );
            return( $msg );
        }             
        my $secs = ( $buf[ 0 ] * 3600 ) + ( $buf[ 1 ] * 60 ) + $buf[ 2 ];
        
        $cmdstr = "$hash->{PLAYERMAC} alarm add dow:$dow repeat:0 enabled:1"; 
        if( defined( $arg[ 3 ] ) ) {
            # CD 0015 start
            my $url=join( " ", @arg[3..$#arg]);
            if (defined($hash->{helper}{alarmPlaylists})) {
                foreach my $e ( keys %{$hash->{helper}{alarmPlaylists}} ) {
                    if($url eq $hash->{helper}{alarmPlaylists}{$e}{title}) {
                        $url=$hash->{helper}{alarmPlaylists}{$e}{url};
                        last;
                    }
                }
            }
            # CD 0015 end
            # CD 0034 überprüfen ob gültige url, wenn nicht, versuchen file:// anzuhängen
            if($url !~ /:\/\//) {
                $url='/' . $url if ($url =~ /^[a-zA-Z]:\\/); # für Windows
                $url=~ s/\\/\//g;
                $url='file://' . $url;                
            }
            # CD 0034 end
            $cmdstr .= " url:" . uri_escape(decode('utf-8',$url));   # CD 0015 uri_escape und join hinzugefügt # CD 0020 decode hinzugefügt    #  CD 0034 playlist: in url: geändert
        }
        $cmdstr .= " time:$secs\n";

        IOWrite( $hash, $cmdstr );

        $hash->{LASTALARM} = $n;

    } elsif(( $arg[ 0 ] eq "enable" )||( $arg[ 0 ] eq "on" )) {     # CD 0015 'on' hinzugefügt
        if( $id ne "none" ) {
            $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
            $cmdstr .= "enabled:1\n";
            IOWrite( $hash, $cmdstr );
            readingsSingleUpdate( $hash, "alarm".$n."_state", "on", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        }

    } elsif(( $arg[ 0 ] eq "disable" )||( $arg[ 0 ] eq "off" )) {   # CD 0015 'off' hinzugefügt
        if( $id ne "none" ) {
            $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
            $cmdstr .= "enabled:0\n";
            IOWrite( $hash, $cmdstr );
            readingsSingleUpdate( $hash, "alarm".$n."_state", "off", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        }

    } elsif( $arg[ 0 ] eq "volume" ) {
        if( $id ne "none" ) {
            $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
            $cmdstr .= "volume:" . $arg[ 1 ] . "\n";
            IOWrite( $hash, $cmdstr );
            readingsSingleUpdate( $hash, "alarm".$n."_volume", $arg[ 1 ], $donotnotify ) if($updateReadingsOnSet);  # CD 0017
        }
    # CD 0015 start
    } elsif( $arg[ 0 ] eq "sound" ) {
        if( $id ne "none" ) {
            if( defined($arg[ 1 ]) ) {
                $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
                my $url=join( " ", @arg[1..$#arg]);
                readingsSingleUpdate( $hash, "alarm".$n."_sound", $url, $donotnotify ) if($updateReadingsOnSet);  # CD 0017
                if (defined($hash->{helper}{alarmPlaylists})) {
                    foreach my $e ( keys %{$hash->{helper}{alarmPlaylists}} ) {
                        if($url eq $hash->{helper}{alarmPlaylists}{$e}{title}) {
                            $url=$hash->{helper}{alarmPlaylists}{$e}{url};
                            last;
                        }
                    }
                }
                # CD 0034 überprüfen ob gültige url, wenn nicht, versuchen file:// anzuhängen
                if($url !~ /:\/\//) {
                    $url='/' . $url if ($url =~ /^[a-zA-Z]:\\/); # für Windows
                    $url=~ s/\\/\//g;
                    $url='file://' . $url;                
                }
                # CD 0034 end
                $cmdstr .= "url:" . uri_escape(decode('utf-8',$url));          # CD 0017 decode hinzugefügt # CD 0034 playlist: in url: geändert
                IOWrite( $hash, $cmdstr . "\n" );                              # CD 0017 reaktiviert        # CD 0034 \n hinzugefügt
            } else {
                my $msg = "SB_PLAYER_Set: alarm, no value for sound.";
                Log3( $hash, 3, $msg );
                return( $msg );
            }
        }
    } elsif( $arg[ 0 ] eq "repeat" ) {
        if( $id ne "none" ) {
            if( defined($arg[ 1 ]) ) {
                $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
                if(($arg[ 1 ] eq "1")||($arg[ 1 ] eq "on")||($arg[ 1 ] eq "yes")) {
                    $cmdstr .= "repeat:1\n";
                    readingsSingleUpdate( $hash, "alarm".$n."_repeat", "on", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
                } else {
                    $cmdstr .= "repeat:0\n";
                    readingsSingleUpdate( $hash, "alarm".$n."_repeat", "off", $donotnotify ) if($updateReadingsOnSet);  # CD 0017
                }
                IOWrite( $hash, $cmdstr );
            } else {
                my $msg = "SB_PLAYER_Set: alarm, no value for repeat.";
                Log3( $hash, 3, $msg );
                return( $msg );
            }
        } 
    } elsif( $arg[ 0 ] eq "wdays" ) {
        if( $id ne "none" ) {
            if( defined($arg[ 1 ]) ) {
                $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
                my $dow=SB_PLAYER_CheckWeekdays(join( "", @arg[1..$#arg]));     # CD 0017
                $cmdstr .= "dow:" . $dow . "\n";                                # CD 0016 SB_PLAYER_CheckWeekdays verwenden
                IOWrite( $hash, $cmdstr );
                # CD 0017 start
                if($updateReadingsOnSet) {
                    my $rdaystr="";
                    if ($dow ne "") {
                        $rdaystr = "Mo" if( index( $dow, "1" ) != -1 );
                        $rdaystr .= " Tu" if( index( $dow, "2" ) != -1 );
                        $rdaystr .= " We" if( index( $dow, "3" ) != -1 );
                        $rdaystr .= " Th" if( index( $dow, "4" ) != -1 );
                        $rdaystr .= " Fr" if( index( $dow, "5" ) != -1 );
                        $rdaystr .= " Sa" if( index( $dow, "6" ) != -1 );
                        $rdaystr .= " Su" if( index( $dow, "0" ) != -1 );
                    } else {
                        $rdaystr = "none";
                    }
                    $rdaystr =~ s/^\s+|\s+$//g;
                    readingsSingleUpdate( $hash, "alarm".$n."_wdays", $rdaystr, $donotnotify );
                }
                # CD 0017 end
            } else {
                my $msg = "SB_PLAYER_Set: no weekdays specified for alarm.";
                Log3( $hash, 3, $msg );
                return( $msg );
            }
        }
    } elsif( $arg[ 0 ] eq "time" ) {
        if( $id ne "none" ) {
            # split the time string up
            if( !defined($arg[ 1 ]) ) {
                my $msg = "SB_PLAYER_Set: no alarm time given.";
                Log3( $hash, 3, $msg );
                return( $msg );
            }
            my @buf = split( ":", $arg[ 1 ] );
            $buf[ 2 ] = 0 if( scalar( @buf ) == 2 );                            # CD 0016, von MM übernommen, geändert
            if( scalar( @buf ) != 3 ) {
                my $msg = "SB_PLAYER_Set: please use hh:mm:ss for alarm time.";
                Log3( $hash, 3, $msg );
                return( $msg );
            }             
            my $secs = ( $buf[ 0 ] * 3600 ) + ( $buf[ 1 ] * 60 ) + $buf[ 2 ];

            $cmdstr = "$hash->{PLAYERMAC} alarm update id:$id ";
            $cmdstr .= "time:" . $secs . "\n";
            IOWrite( $hash, $cmdstr );
            # CD 0017 start
            if($updateReadingsOnSet) {
                my $buf = sprintf( "%02d:%02d:%02d", 
                                   int( scalar( $secs ) / 3600 ),
                                   int( ( $secs % 3600 ) / 60 ),
                                   int( $secs % 60 ) );
                readingsSingleUpdate( $hash, "alarm".$n."_time", $buf, $donotnotify );
            }
            # CD 0017 end
        }
    # CD 0015 end
    } elsif( $arg[ 0 ] eq "delete" ) {
        if( $id ne "none" ) {
            $cmdstr = "$hash->{PLAYERMAC} alarm delete id:$id\n";
            IOWrite( $hash, $cmdstr );
            # readingsSingleUpdate( $hash, "alarmid$n", "none", 1 );    # CD 0015 deaktiviert
        }

    } else { 
        my $msg = "SB_PLAYER_Set: unkown argument ".$arg[ 0 ]." for alarm given.";
        Log3( $hash, 3, $msg );
        return( $msg );
    }

    return( undef );
}

# CD 0016, neu, von MM übernommen
# ----------------------------------------------------------------------------
#  Check weekdays string
# ----------------------------------------------------------------------------
sub SB_PLAYER_CheckWeekdays( $ ) {
    my ($wdayargs) = @_;
    my $weekdays = '';
    if(index($wdayargs,"Mo") != -1 || index($wdayargs,"1") != -1)
    {
        $weekdays.='1,';
    }
    if(index($wdayargs,"Tu") != -1 || index($wdayargs,"Di") != -1 || index($wdayargs,"2") != -1)
    {
        $weekdays.='2,';
    }
    if(index($wdayargs,"We") != -1 || index($wdayargs,"Mi") != -1 || index($wdayargs,"3") != -1)
    {
        $weekdays.='3,';
    }
    if(index($wdayargs,"Th") != -1 || index($wdayargs,"Do") != -1 || index($wdayargs,"4") != -1)
    {
        $weekdays.='4,';
    }
    if(index($wdayargs,"Fr") != -1 || index($wdayargs,"5") != -1)
    {
        $weekdays.='5,';
    }
    if(index($wdayargs,"Sa") != -1 || index($wdayargs,"6") != -1)
    {
        $weekdays.='6,';
    }
    if(index($wdayargs,"Su") != -1 || index($wdayargs,"So") != -1 || index($wdayargs,"0") != -1)
    {
        $weekdays.='0';
    }
    if(index($wdayargs,"all") != -1 || index($wdayargs,"daily") != -1 || index($wdayargs,"7") != -1)
    {
        $weekdays='0,1,2,3,4,5,6';
    }
    if(index($wdayargs,"none") != -1) # || index($wdayargs,"once") != -1)  # CD 0016 once funktioniert so nicht, muss über repeat gemacht werden
    {
        $weekdays='7';
    }
    $weekdays=~ s/,$//;     # CD 0019 letztes , entfernen
    return $weekdays;
}

# ----------------------------------------------------------------------------
#  Status update - just internal use and invoked by the timer
# ----------------------------------------------------------------------------
sub SB_PLAYER_GetStatus( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $strbuf = "";

    Log3( $hash, 5, "SB_PLAYER_GetStatus: called" );

    # CD 0014 start - Anzahl Anfragen begrenzen
    if(!defined($hash->{helper}{lastGetStatus})||($hash->{helper}{lastGetStatus}<gettimeofday()-0.5)) {
        #Log 0,"Querying status, last: $hash->{helper}{lastGetStatus}, now: ".gettimeofday();
        $hash->{helper}{lastGetStatus}=gettimeofday();
    
        # we fire the respective questions and parse the answers in parse
        IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} album ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} title ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} playlist url ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} remote ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" );     # CD 0030 u added to tags
        #IOWrite( $hash, "$hash->{PLAYERMAC} alarm playlists 0 200\n" ) if (!defined($hash->{helper}{alarmPlaylists}));  # CD 0016 get available elements for alarms before querying the alarms # CD 0026 wird über Server verteilt
        IOWrite( $hash, "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n" );  # CD 0015 filter added
        # MM 0016 start
        IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmsEnabled ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmDefaultVolume ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmTimeoutSeconds ?\n" );
        IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmSnoozeSeconds ?\n" );
        # MM 0016 end
        # CD 0007
        IOWrite( $hash, "$hash->{PLAYERMAC} playerpref syncVolume ?\n" );
        # CD 0009
        IOWrite( $hash, "$hash->{PLAYERMAC} playlist name ?\n" );
        # CD 0014
        IOWrite( $hash, "$hash->{PLAYERMAC} duration ?\n" );
        SB_PLAYER_QueryElapsedTime($hash);
    }   # CD 0014 end
    
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
    RemoveInternalTimer( $hash );   # CD 0014
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
            #readingsSingleUpdate( $hash, "state", "on", 1 );   # CD 0011 ob der Player eingeschaltet ist, ist hier noch nicht bekannt, SB_PLAYER_GetStatus abwarten 
            #readingsSingleUpdate( $hash, "power", "on", 1 );   # CD 0011 ob der Player eingeschaltet ist, ist hier noch nicht bekannt, SB_PLAYER_GetStatus abwarten 
            # do and update of the status
            RemoveInternalTimer( $hash );   # CD 0016
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
            $hash->{helper}{SB_PLAYER_Favs}{$args[3]}{ID} = $args[ 2 ];
            $hash->{helper}{SB_PLAYER_Favs}{$args[3]}{URL} = $args[ 4 ];        # CD 0021 hinzugefügt
            if( $hash->{FAVSTR} eq "" ) {
                $hash->{FAVSTR} = $args[ 3 ];   # CD Test für Leerzeichen join("&nbsp;",@args[ 4..$#args ]);
            } else {
                $hash->{FAVSTR} .= "," . $args[ 3 ];    # CD Test für Leerzeichen join("&nbsp;",@args[ 4..$#args ]);
            }
            # CD 0016 start, provisorisch um alarmPlaylists zu aktualisieren, TODO: muss von 97_SB_SERVER kommen
            RemoveInternalTimer( $hash );   # CD 0016
            InternalTimer( gettimeofday() + 3, 
                           "SB_PLAYER_GetStatus", 
                           $hash, 
                           0 );
            #end
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            undef( %{$hash->{helper}{SB_PLAYER_Favs}} );
            $hash->{FAVSTR} = "";
            delete($hash->{helper}{alarmPlaylists}) if (defined($hash->{helper}{alarmPlaylists}));      # CD 0016
        } else {
        }

    } elsif( $cmd eq "SYNCMASTER" ) {
        if( $args[ 0 ] eq "ADD" ) {
            if( $args[ 1 ] ne $hash->{PLAYERNAME} ) {
                $hash->{helper}{SB_PLAYER_SyncMasters}{$args[1]}{MAC} = $args[ 2 ];
                if( $hash->{SYNCMASTERS} eq "" ) {
                    $hash->{SYNCMASTERS} = $args[ 1 ];
                } else {
                    $hash->{SYNCMASTERS} .= "," . $args[ 1 ];
                }
            }
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            undef( %{$hash->{helper}{SB_PLAYER_SyncMasters}} );
            $hash->{SYNCMASTERS} = "";

        } else {
        }

    } elsif( $cmd eq "PLAYLISTS" ) {
        if( $args[ 0 ] eq "ADD" ) {
            # CD 0014 Playlists mit fhem_* ignorieren
            if($args[3]=~/^fhem_.*/) {
                Log3( $hash, 5, "SB_PLAYER_RecbroadCast($name): - skipping - PLAYLISTS ADD " . 
                      "name:$args[1] id:$args[2] uid:$args[3]" );
            } else {
            # CD 0014 end
                Log3( $hash, 5, "SB_PLAYER_RecbroadCast($name): PLAYLISTS ADD " . 
                      "name:$args[1] id:$args[2] uid:$args[3]" );
                $hash->{helper}{SB_PLAYER_Playlists}{$args[3]}{ID} = $args[ 2 ];
                $hash->{helper}{SB_PLAYER_Playlists}{$args[3]}{NAME} = $args[ 1 ];
                if( $hash->{SERVERPLAYLISTS} eq "" ) {
                    $hash->{SERVERPLAYLISTS} = $args[ 3 ];
                } else {
                    $hash->{SERVERPLAYLISTS} .= "," . $args[ 3 ];
                }
            }   # CD 0014
            # CD 0016 start, provisorisch um alarmPlaylists zu aktualisieren, TODO: muss von 97_SB_SERVER kommen
            RemoveInternalTimer( $hash );   # CD 0016
            InternalTimer( gettimeofday() + 3, 
                           "SB_PLAYER_GetStatus", 
                           $hash, 
                           0 );
            #end
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            undef( %{$hash->{helper}{SB_PLAYER_Playlists}} );
            $hash->{SERVERPLAYLISTS} = "";
            delete($hash->{helper}{alarmPlaylists}) if (defined($hash->{helper}{alarmPlaylists}));      # CD 0016
        } else {
        }

    # CD 0026 start
    } elsif( $cmd eq "ALARMPLAYLISTS" ) {
        if( $args[ 0 ] eq "ADD" ) {
            $hash->{helper}{alarmPlaylists}{$args[ 1 ]}{$args[ 2 ]}=join( " ", @args[3..$#args]);
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            delete($hash->{helper}{alarmPlaylists}) if (defined($hash->{helper}{alarmPlaylists}));
        }
    # CD 0026 end
    } else {

    }

}


# ----------------------------------------------------------------------------
#  parse the return on the alarms status
# ----------------------------------------------------------------------------
# wird von SB_PLAYER_Parse aufgerufen, readingsBeginUpdate ist aktiv
sub SB_PLAYER_ParseAlarms( $@ ) {
    my ( $hash, @data ) = @_;

    my $name = $hash->{NAME};

    # CD 0016 start {ALARMSCOUNT} verschieben nach reload
    if (defined($hash->{ALARMSCOUNT})) {
        $hash->{helper}{ALARMSCOUNT}=$hash->{ALARMSCOUNT};
        delete($hash->{ALARMSCOUNT});
    }
    # CD 0016
    my $lastAlarmCount=$hash->{helper}{ALARMSCOUNT};    # CD 0016 ALARMSCOUNT nach {helper} verschoben
    
    if( $data[ 0 ] =~ /^([0-9])*/ ) {
        shift( @data );
    }

    if( $data[ 0 ] =~ /^([0-9])*/ ) {
        shift( @data );
    }

    fhem( "deletereading $name alarmid.*" );        # CD 0015 alte readings entfernen

    my $alarmcounter=0; # CD 0015
    
    foreach( @data ) {
        if( $_ =~ /^(id:)(\S{8})/ ) {
            # id is 8 non-white-space characters
            # example: id:0ac7f3a2 
            $alarmcounter+=1;                # CD 0015
            readingsBulkUpdate( $hash, "alarm".$alarmcounter."_id", $2 );    # CD 0015
            next;
        } elsif( $_ =~ /^(dow:)([0-9,]*)/ ) {   # C 0016 + durch * ersetzt, für dow: ohne Tage
            # example: dow:1,2,4,5,6 
            my $rdaystr="";                 # CD 0015
            if ($2 ne "") {              # CD 0016
                if( index( $2, "1" ) != -1 ) {
                    $rdaystr = "Mo";          # CD 0015
                }
                if( index( $2, "2" ) != -1 ) {
                    $rdaystr .= " Tu";          # CD 0015
                }
                if( index( $2, "3" ) != -1 ) {
                    $rdaystr .= " We";          # CD 0015
                }
                if( index( $2, "4" ) != -1 ) {
                    $rdaystr .= " Th";          # CD 0015
                }
                if( index( $2, "5" ) != -1 ) {
                    $rdaystr .= " Fr";          # CD 0015
                }
                if( index( $2, "6" ) != -1 ) {
                    $rdaystr .= " Sa";          # CD 0015
                } 
                if( index( $2, "0" ) != -1 ) {
                    $rdaystr .= " Su";          # CD 0015
                }
            } else {                            # CD 0016
                $rdaystr = "none";              # CD 0016
            }                                   # CD 0016
            $rdaystr =~ s/^\s+|\s+$//g;     # CD 0015
            readingsBulkUpdate( $hash, "alarm".$alarmcounter."_wdays", $rdaystr );    # CD 0015
            next;
        } elsif( $_ =~ /^(enabled:)([0|1])/ ) {
            # example: enabled:1 
            if( $2 eq "1" ) {
                readingsBulkUpdate( $hash, "alarm".$alarmcounter."_state", "on" );    # CD 0015
            } else {
                readingsBulkUpdate( $hash, "alarm".$alarmcounter."_state", "off" );    # CD 0015
            }
            next;
        } elsif( $_ =~ /^(repeat:)([0|1])/ ) {
            # example: repeat:1 
            if( $2 eq "1" ) {
                readingsBulkUpdate( $hash, "alarm".$alarmcounter."_repeat", "yes" );    # CD 0015
            } else {
                readingsBulkUpdate( $hash, "alarm".$alarmcounter."_repeat", "no" );    # CD 0015
            }
            next;
        } elsif( $_ =~ /^(time:)([0-9]+)/ ) {
            # example: time:25200 
            my $buf = sprintf( "%02d:%02d:%02d", 
                               int( scalar( $2 ) / 3600 ),
                               int( ( $2 % 3600 ) / 60 ),
                               int( $2 % 60 ) );
            readingsBulkUpdate( $hash, "alarm".$alarmcounter."_time", $buf );    # CD 0015
            next;
        } elsif( $_ =~ /^(volume:)(\d{1,2})/ ) {
            # example: volume:50 
            readingsBulkUpdate( $hash, "alarm".$alarmcounter."_volume", $2 );    # CD 0015
            next;
        } elsif( $_ =~ /^(url:)(\S+)/ ) {
            # CD 0015 start
            my $pn=SB_SERVER_FavoritesName2UID(uri_unescape($2));
            if(defined($hash->{helper}{alarmPlaylists})
                && defined($hash->{helper}{alarmPlaylists}{$pn})) {
                readingsBulkUpdate( $hash, "alarm".$alarmcounter."_sound", $hash->{helper}{alarmPlaylists}{$pn}{title} );
            } else {
                readingsBulkUpdate( $hash, "alarm".$alarmcounter."_sound", $2 );
            }
            # CD 0015 end
            next;
        # CD 0016 start
        } elsif( $_ =~ /^(filter:)(\S+)/ ) {
            next;
        # CD 0016 end
        # MM 0016 start
        } elsif( $_ =~ /^(tags:)(\S+)/ ) {
            next;
        } elsif( $_ =~ /^(fade:)([0|1])/ ) {
            # example: fade:1 
            if( $2 eq "1" ) {
                readingsBulkUpdate( $hash, "alarmsFadeIn", "on" );      # CD 0016 von MM übernommen, Namen geändert
            } else {
                readingsBulkUpdate( $hash, "alarmsFadeIn", "off" );     # CD 0016 von MM übernommen, Namen geändert
            }
            next;
        } elsif( $_ =~ /^(count:)([0-9]+)/ ) {
            $hash->{helper}{ALARMSCOUNT} = $2;  # CD 0016 ALARMSCOUNT nach {helper} verschoben
            next;
        } else {
            Log3( $hash, 1, "SB_PLAYER_Alarms($name): Unknown data ($_)");
            next;
        }
        # MM 0016 end
    }

    # CD 0015 nicht mehr vorhandene Alarme löschen
    if ($lastAlarmCount>$hash->{helper}{ALARMSCOUNT}) { # CD 0016 ALARMSCOUNT nach {helper} verschoben
        for(my $i=$hash->{helper}{ALARMSCOUNT}+1;$i<=$lastAlarmCount;$i++) {    # CD 0016 ALARMSCOUNT nach {helper} verschoben
            fhem( "deletereading $name alarm".$i."_.*" );
        }
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
      if( $instr =~ /^(00[:-]){5}(00)$/) {  # CD 0032 00:00:00:00:00:00 is not a valid MAC
        return( 0 );
      } else {
        return( 1 );
      }
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
# CD 0012 start
sub SB_PLAYER_tcb_DelayAmplifier( $ ) {     # CD 0014 Name geändert
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    #Log 0,"SB_PLAYER_DelayAmplifier";
    $hash->{helper}{AMPLIFIERDELAYOFF}=1;

    SB_PLAYER_Amplifier($hash);
}
# CD 0012 end

sub SB_PLAYER_Amplifier( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    if( ( $hash->{AMPLIFIER} eq "none" ) || 
        ( !defined( $defs{$hash->{AMPLIFIER}} ) ) ) {
        # amplifier not specified
        delete($hash->{helper}{AMPLIFIERDELAYOFF}) if defined($hash->{helper}{AMPLIFIERDELAYOFF});  # CD 0012
        return;
    }

    my $setvalue = "off";
    
    Log3( $hash, 4, "SB_PLAYER_Amplifier($name): called" );

    if( AttrVal( $name, "amplifier", "play" ) eq "play" ) {
        my $thestatus = ReadingsVal( $name, "playStatus", "pause" );

        Log3( $hash, 5, "SB_PLAYER_Amplifier($name): with mode play " . 
              "and status:$thestatus" );

        if( ( $thestatus eq "playing" ) || ( $thestatus eq "paused" ) ) {
            $setvalue = "on";
        } elsif( $thestatus eq "stopped" ) {
            $setvalue = "off";
        } else { 
            $setvalue = "off";
        }
    } elsif( AttrVal( $name, "amplifier", "on" ) eq "on" ) {
        my $thestatus = ReadingsVal( $name, "power", "off" );

        Log3( $hash, 5, "SB_PLAYER_Amplifier($name): with mode on " . 
              "and status:$thestatus" );

        if( $thestatus eq "on" ) {
            $setvalue = "on";
        } else {
            $setvalue = "off";
        }
    } else {
        Log3( $hash, 1, "SB_PLAYER_Amplifier($name): ATTR amplifier " .
              "set to wrong value [on|play]" );
        return;
    }

    my $actualState = ReadingsVal( "$hash->{AMPLIFIER}", "state", "off" );

    Log3( $hash, 5, "SB_PLAYER_Amplifier($name): actual:$actualState " . 
          "and set:$setvalue" );

    if ( $actualState ne $setvalue) {
        # CD 0012 start - Abschalten über Attribut verzögern, generell verzögern damit set-Event funktioniert
        my $delayAmp=($setvalue eq "off")?AttrVal( $name, "amplifierDelayOff", 0 ):0.1;
        $delayAmp=0.01 if($delayAmp==0);
        if (!defined($hash->{helper}{AMPLIFIERDELAYOFF})) {
            Log3( $hash, 5, 'SB_PLAYER_Amplifier($name): delaying amplifier on/off' );
            RemoveInternalTimer( "DelayAmplifier:$name");
            InternalTimer( gettimeofday() + $delayAmp, 
               "SB_PLAYER_tcb_DelayAmplifier",  # CD 0014 Name geändert
               "DelayAmplifier:$name", 
               0 );
            return;
        }
        # CD 0012 end
        fhem( "set $hash->{AMPLIFIER} $setvalue" );
        
        Log3( $hash, 5, "SB_PLAYER_Amplifier($name): amplifier changed to " . 
              $setvalue );
    } else {
        Log3( $hash, 5, "SB_PLAYER_Amplifier($name): no amplifier " . 
              "state change" );
    }
    delete($hash->{helper}{AMPLIFIERDELAYOFF}) if (defined($hash->{helper}{AMPLIFIERDELAYOFF}));

    return;
}


# ----------------------------------------------------------------------------
#  update the coverart image
# ----------------------------------------------------------------------------
sub SB_PLAYER_CoverArt( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    # return if (defined($hash->{helper}{CoverOk}) && ($hash->{helper}{CoverOk} == 1) && ( $hash->{ISREMOTESTREAM} eq "0" ));   # CD 0026 added # CD 0027 removed
    
    # CD 0003 fix missing server    
    if(!defined($hash->{SBSERVER})||($hash->{SBSERVER} eq '?')) {
        if ((defined($hash->{IODev})) && (defined($hash->{IODev}->{IP}))) {
          $hash->{SBSERVER}=$hash->{IODev}->{IP} . ":" . AttrVal( $hash->{IODev}, "httpport", "9000" );
        }
    }
    # CD 0003 end

    my $lastCoverartUrl=$hash->{COVERARTURL};           # CD 0013
    
    # compile the link to the album cover
    if(( $hash->{ISREMOTESTREAM} eq "0" ) || ($hash->{ARTWORKURL} =~ /imageproxy%2F/)) {    # CD 0026 LMS 7.8/7.9
        $hash->{COVERARTURL} = "http://" . $hash->{SBSERVER} . "/music/" . 
            "current/cover_" . AttrVal( $name, "coverartheight", 50 ) . 
            "x" . AttrVal( $name, "coverartwidth", 50 ) . 
            ".jpg?player=$hash->{PLAYERMAC}&x=".int(rand(100000));      # CD 0025 added rand() to force browser refresh 
        $hash->{helper}{CoverOk}=1;                                     # CD 0026 added
    } elsif( $hash->{ISREMOTESTREAM} eq "1" ) { # CD 0017 Abfrage  || ( $hash->{ISREMOTESTREAM} == 1 ) entfernt
        # CD 0011 überprüfen ob überhaupt eine URL vorhanden ist
        if($hash->{ARTWORKURL} ne "?") {
            # CD 0034 Abfrage für Spotify und LMS < 7.8, ungetest, #674, KernSani
            # CD 0035 Code von KernSani übernommen, #676
            if ($hash->{ARTWORKURL} =~ /spotifyimage%2Fspotify/) {
				my $cover = "cover.jpg";
				my $coverArtWithSize = "cover_".AttrVal( $name, "coverartheight", 50 )."x".AttrVal( $name, "coverartwidth", 50 )."_o.jpg";
				$hash->{ARTWORKURL} =~ s/$cover/$coverArtWithSize/g;
                $hash->{COVERARTURL} = "http://" . $hash->{SBSERVER} . "/" . uri_unescape($hash->{ARTWORKURL});
            } else {
                $hash->{COVERARTURL} = "http://www.mysqueezebox.com/public/" . 
                    "imageproxy?u=" . $hash->{ARTWORKURL} . 
                    "&h=" . AttrVal( $name, "coverartheight", 50 ) . 
                    "&w=". AttrVal( $name, "coverartwidth", 50 );
            }
        } else {
            $hash->{COVERARTURL} = "http://" . $hash->{SBSERVER} . "/music/" .
                $hash->{COVERID} . "/cover_" . AttrVal( $name, "coverartheight", 50 ) . 
                "x" . AttrVal( $name, "coverartwidth", 50 ) . ".jpg";
        }
        # CD 0011 Ende
    } else {
        $hash->{COVERARTURL} = "http://" . $hash->{SBSERVER} . "/music/" . 
            $hash->{COVERID} . "/cover_" . AttrVal( $name, "coverartheight", 50 ) .     # CD 0011 -160206228 durch $hash->{COVERID} ersetzt
            "x" . AttrVal( $name, "coverartwidth", 50 ) . ".jpg";
    }

    # CD 0004, url as reading
    readingsBulkUpdate( $hash, "coverarturl", $hash->{COVERARTURL});

    if( ( $hash->{COVERARTLINK} eq "none" ) || 
        ( !defined( $defs{$hash->{COVERARTLINK}} ) ) || 
        ( $hash->{COVERARTURL} eq "?" ) ) {
        # weblink not specified
        return;
    } else {
        if ($lastCoverartUrl ne $hash->{COVERARTURL}) {                 # CD 0013 nur bei Änderung aktualisieren
            fhem( "modify " . $hash->{COVERARTLINK} . " image " . 
                  $hash->{COVERARTURL} );
        }                                                               # CD 0013
    }
}

# ----------------------------------------------------------------------------
#  Handle the return for a playerstatus query
# ----------------------------------------------------------------------------
sub SB_PLAYER_ParsePlayerStatus( $$ ) {
    my( $hash, $dataptr ) = @_;
    
    my $name = $hash->{NAME};
    my $leftover = "";
    my $cur = "";
    my $playlistIds = "";           # CD 0014
    my $refreshIds=0;               # CD 0014
    
    # typically the start index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
        shift( @{$dataptr} );
    } else {
        Log3( $hash, 5, "SB_PLAYER_ParsePlayerStatus($name): entry is " .
              "not the start number" );
        return;
    }

    # typically the max index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
        if($dataptr->[ 0 ]>1) {
            $refreshIds=1;        # CD 0014
            delete($hash->{helper}{playlistUrls}) if(defined($hash->{helper}{playlistUrls}));   # CD 0030
        }
        shift( @{$dataptr} );
    } else {
        Log3( $hash, 5, "SB_PLAYER_ParsePlayerStatus($name): entry is " .
              "not the end number" );
        return;
    }

    my $datastr = join( " ", @{$dataptr} );
    # replace funny stuff
    # CD 0006 all keywords with spaces must be converted here
    $datastr =~ s/mixer volume/mixervolume/g;
    # CD 0006 replaced mixertreble with mixer treble
    $datastr =~ s/mixer treble/mixertreble/g;
    $datastr =~ s/mixer bass/mixerbass/g;
    $datastr =~ s/mixer pitch/mixerpitch/g;
    $datastr =~ s/playlist repeat/playlistrepeat/g;
    $datastr =~ s/playlist shuffle/playlistshuffle/g;
    $datastr =~ s/playlist index/playlistindex/g;
    # CD 0003
    $datastr =~ s/playlist mode/playlistmode/g;

    Log3( $hash, 5, "SB_PLAYER_ParsePlayerStatus($name): data to parse: " .
          $datastr );

    my @data1 = split( " ", $datastr );

    # the rest of the array should now have the data, we're interested in
    # CD 0006 - deaktiviert, SB_PLAYER_ParsePlayerStatus kann nur von SB_PLAYER_Parse aufgerufen werden, dort ist readingsBeginUpdate aber bereits aktiv
    #readingsBeginUpdate( $hash );

    # set default values for stuff not always send
    $hash->{SYNCMASTER} = "none";
    $hash->{SYNCGROUP} = "none";
    $hash->{SYNCMASTERPN} = "none";      # CD 0018
    $hash->{SYNCGROUPPN} = "none";       # CD 0018
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

    # CD 0003 start, fix handling of spaces
    my @data2;
    my $last_d="";

    # loop through the results
    foreach( @data1 ) {
        if( index( $_, ":" ) < 2 ) {
            $last_d = $last_d . " " . $_;
            next;
        }

        if( $last_d ne "" ) {
            push @data2,$last_d;
        }
        $last_d=$_;
    }
    if( $last_d ne "" ) {
        push @data2,$last_d;
    }
    # CD 0003 end
    
    my $lastId=0;   # CD 0030
    
    # loop through the results
    foreach( @data2 ) {
        my $cur=$_;
        if( $cur =~ /^(player_connected:)([0-9]*)/ ) {
            if( $2 == "1" ) {
                readingsBulkUpdate( $hash, "connected", $2 );
                readingsBulkUpdate( $hash, "presence", "present" );
            } else {
                readingsBulkUpdate( $hash, "connected", $3 );
                readingsBulkUpdate( $hash, "presence", "absent" );
            }
            next;

        } elsif( $cur =~ /^(player_ip:)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{3,5})/ ) {
            if( $hash->{PLAYERIP} ne "?" ) {
                $hash->{PLAYERIP} = $2;
            }
            next;

        } elsif( $cur =~ /^(player_name:)(.*)/ ) {
            if( $hash->{PLAYERNAME} ne "?" ) {
                $hash->{PLAYERNAME} = $2;
            }
            next;

        } elsif( $cur =~ /^(power:)([0-9\.]*)/ ) {
            if( $2 eq "1" ) {
                readingsBulkUpdate( $hash, "power", "on" );
                SB_PLAYER_Amplifier( $hash );
            } else {
                readingsBulkUpdate( $hash, "power", "off" );
                SB_PLAYER_Amplifier( $hash );
            }
            next;

        } elsif( $cur =~ /^(signalstrength:)([0-9\.]*)/ ) {
            if( $2 eq "0" ) {
                readingsBulkUpdate( $hash, "signalstrength", "wired" );
            } else {
                readingsBulkUpdate( $hash, "signalstrength", "$2" );
            }
            next;

        } elsif( $cur =~ /^(mode:)(.*)/ ) {
            if( $2 eq "play" ) {
                readingsBulkUpdate( $hash, "playStatus", "playing" );
                SB_PLAYER_Amplifier( $hash );
            } elsif( $2 eq "stop" ) {
                readingsBulkUpdate( $hash, "playStatus", "stopped" );
                SB_PLAYER_Amplifier( $hash );
            } elsif( $2 eq "pause" ) {
                readingsBulkUpdate( $hash, "playStatus", "paused" );
                SB_PLAYER_Amplifier( $hash );
            } else {
                # unkown
            }
            next;

        } elsif( $cur =~ /^(sync_master:)($dd[:|-]$dd[:|-]$dd[:|-]$dd[:|-]$dd[:|-]$dd)/ ) {
            $hash->{SYNCMASTER} = $2;
            $hash->{SYNCED} = "yes";
            $hash->{SYNCMASTERPN} = SB_PLAYER_MACToPlayername($hash,$2);  # CD 0018
            next;

        } elsif( $cur =~ /^(sync_slaves:)(.*)/ ) {
            $hash->{SYNCGROUP} = $2;
            # CD 0018 start
            my @macs=split(",",$hash->{SYNCGROUP});
            my $syncgroup;
            foreach ( @macs ) {
                my $mac=$_;
                my $dev=SB_PLAYER_MACToPlayername($hash,$mac);
                $syncgroup.="," if(defined($syncgroup));
                if(defined($dev)) {
                    $syncgroup.=$dev;
                } else {
                    if($mac eq $hash->{PLAYERMAC}) {
                        $syncgroup.=$name;
                    } else {
                        $syncgroup.=$mac;
                    }
                }
            }
            $hash->{SYNCGROUPPN} = $syncgroup;
            # CD 0018 end
            readingsBulkUpdate( $hash, "synced", "$hash->{SYNCMASTERPN},$hash->{SYNCGROUPPN}" );    # Matthew 0019 hinzugefügt
            next;

        } elsif( $cur =~ /^(will_sleep_in:)([0-9\.]*)/ ) {
            $hash->{WILLSLEEPIN} = "$2 secs";
            next;

        } elsif( $cur =~ /^(mixervolume:)(.*)/ ) {
            if( ( index( $2, "+" ) != -1 ) || ( index( $2, "-" ) != -1 ) ) {
                # that was a relative value. We do nothing and fire an update
                IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" );
            } else {
                SB_PLAYER_UpdateVolumeReadings( $hash, $2, true );
                # CD 0007 start
                if((defined($hash->{helper}{setSyncVolume}) && ($hash->{helper}{setSyncVolume} != $2))|| (!defined($hash->{helper}{setSyncVolume}))) {
                    SB_PLAYER_SetSyncedVolume($hash,$2);
                }
                delete $hash->{helper}{setSyncVolume};
                # CD 0007 end
            }
            next;

        } elsif( $cur =~ /^(playlistshuffle:)(.*)/ ) {
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

        } elsif( $cur =~ /^(playlistrepeat:)(.*)/ ) {
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

        } elsif( $cur =~ /^(playlistname:)(.*)/ ) {
            readingsBulkUpdate( $hash, "currentPlaylistName", $2 );
            next;

        } elsif( $cur =~ /^(artwork_url:)(.*)/ ) {
            $hash->{ARTWORKURL} = uri_escape( $2 );
            #Log 0,"Update Artwork: ".$hash->{ARTWORKURL};
            #SB_PLAYER_CoverArt( $hash );
            next;

        } elsif( $cur =~ /^(coverid:)(.*)/ ) {
            $hash->{COVERID} = $2;
            next;

        } elsif( $cur =~ /^(remote:)(.*)/ ) {
            $hash->{ISREMOTESTREAM} = $2;
            next;
        # CD 0014 start
        } elsif( $cur =~ /^(duration:)(.*)/ ) {
            readingsBulkUpdate( $hash, "duration", $2 );
            next;
        } elsif( $cur =~ /^(time:)(.*)/ ) {
            $hash->{helper}{elapsedTime}{VAL}=$2;
            $hash->{helper}{elapsedTime}{TS}=gettimeofday();
            delete($hash->{helper}{saveLocked}) if (($hash->{helper}{ttsstate}==TTS_IDLE) && defined($hash->{helper}{saveLocked}));
            next;
        } elsif( $cur =~ /^(playlist_tracks:)(.*)/ ) {
            readingsBulkUpdate( $hash, "playlistTracks", $2 );
            next;
        } elsif( $cur =~ /^(playlist_cur_index:)(.*)/ ) {
            readingsBulkUpdate( $hash, "playlistCurrentTrack", $2+1 );
            next;
        } elsif( $cur =~ /^(id:)(.*)/ ) {
            if($refreshIds==1) {
                if($playlistIds) {
                    $playlistIds=$playlistIds.",$2";
                } else {
                    $playlistIds=$2;
                }
                $hash->{helper}{playlistIds}=$playlistIds;
            }
            $lastId=$2; # CD 0030
            next;
        # CD 0030 start
        } elsif( $cur =~ /^(url:)(.*)/ ) {
            if($refreshIds==1) {
                if ($lastId<0) {
                    $hash->{helper}{playlistUrls}{$lastId}=$2;
                }
            }
            next;
        # CD 0030 end
        # CD 0014 end
        } else {
            next;

        }
    }
    # Matthew 0019 start
    if( $hash->{SYNCED} ne "yes") {
        readingsBulkUpdate( $hash, "synced", "none" );
    }
    # Matthew 0019 end

    # CD 0003 moved before readingsEndUpdate
    # update the cover art
    SB_PLAYER_CoverArt( $hash );

    # CD 0006 - deaktiviert, SB_PLAYER_ParsePlayerStatus kann nur von SB_PLAYER_Parse aufgerufen werden, dort ist readingsBeginUpdate aber bereits aktiv
    #readingsEndUpdate( $hash, 1 );


}

# CD 0018 start
# ----------------------------------------------------------------------------
#  convert MAC to playername
# ----------------------------------------------------------------------------
sub SB_PLAYER_MACToPlayername( $$ ) {
    my( $hash, $mac ) = @_;
    my $name = $hash->{NAME};

    return $hash->{PLAYERNAME} if($hash->{PLAYERMAC} eq $mac);

    my $dev;
    foreach my $e ( keys %{$hash->{helper}{SB_PLAYER_SyncMasters}} ) {
        if($mac eq $hash->{helper}{SB_PLAYER_SyncMasters}{$e}{MAC}) {
            $dev=$e;
            last;
        }
    }
    return $dev;
}
# CD 0018 end

# CD 0014 start
# ----------------------------------------------------------------------------
#  estimate elapsed time
# ----------------------------------------------------------------------------
sub SB_PLAYER_EstimateElapsedTime( $ ) {
    my( $hash ) = @_;
    my $name = $hash->{NAME};

    my $d=ReadingsVal($name,"duration",0);
    # nur wenn duration>0
    if(($d ne '?')&&($d>0)) {   # CD 0033 check for '?'
        # wenn {helper}{elapsedTime} bekannt ist als Basis verwenden
        if((defined($hash->{helper}{elapsedTime}))&&($hash->{helper}{elapsedTime}{VAL}>0)) {
            $hash->{helper}{elapsedTime}{VAL}=$hash->{helper}{elapsedTime}{VAL}+(gettimeofday()-$hash->{helper}{elapsedTime}{TS});
            $hash->{helper}{elapsedTime}{TS}=gettimeofday();
        } else {
            my $dTS=time_str2num(ReadingsTimestamp($name,"duration",0));
            my $n=gettimeofday();
            if(($n-$dTS)<=$d) {
                $hash->{helper}{elapsedTime}{VAL}=gettimeofday()-$dTS;
                $hash->{helper}{elapsedTime}{TS}=gettimeofday();
            } else {
                $hash->{helper}{elapsedTime}{VAL}=$d;
                $hash->{helper}{elapsedTime}{TS}=gettimeofday();
            }
        }
    } else {
        delete($hash->{helper}{elapsedTime}) if(defined($hash->{helper}{elapsedTime}));
    }
}
# CD 0014 end

# ----------------------------------------------------------------------------
#  update the volume readings
# ----------------------------------------------------------------------------
sub SB_PLAYER_UpdateVolumeReadings( $$$ ) {
    my( $hash, $vol, $bulk ) = @_;
    
    my $name = $hash->{NAME};

    $vol = int($vol);       # MM 0016, Fix wegen AirPlay-Plugin

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

# ----------------------------------------------------------------------------
#  set volume of synced players
# ----------------------------------------------------------------------------
sub SB_PLAYER_SetSyncedVolume( $$ ) {
    my( $hash, $vol ) = @_;
    
    my $name = $hash->{NAME};

    return if (!defined($hash->{SYNCED}) || ($hash->{SYNCED} ne "yes"));

    my $sva=AttrVal($name, "syncVolume", undef);
    my $t=$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER};
    
    $vol = int($vol);       # MM 0016, Fix wegen AirPlay-Plugin

    $hash->{helper}{setSyncVolume}=$vol;
    
    if(defined($sva) && ($sva ne "0") && ($sva ne "1")) {
        my @pl=split(",",$t);
        my @chlds=devspec2array("TYPE=SB_PLAYER");

        foreach (@pl) {
            if (($_ ne "?") && ($_ ne $hash->{PLAYERMAC})) {
                my $mac=$_;
                foreach(@chlds) {
                    my $chash=$defs{$_};
                    if(defined($chash) && defined($chash->{PLAYERMAC}) && ($chash->{PLAYERMAC} eq $mac)) {
                        my $sva2=AttrVal($chash->{NAME}, "syncVolume", undef);
                        if (defined($sva2) && ($sva eq $sva2)) {
                            if ($vol>0) {   # CD 0010
                                if(ReadingsVal($chash->{NAME}, "volumeStraight", $vol)!=$vol) {
                                    #Log 0,$chash->{NAME}." setting volume to ".$vol." (from ".$hash->{NAME}.")";
                                    $chash->{helper}{setSyncVolume}=$vol;
                                    fhem "set ".$chash->{NAME}." volumeStraight ".$vol." x";
                                }
                                # CD 0010 start
                            } else {
                                if(ReadingsVal($chash->{NAME}, "volume", "x") ne "muted") {
                                    #Log 0,$chash->{NAME}." muting (from ".$hash->{NAME}.")";
                                    IOWrite( $chash, "$chash->{PLAYERMAC} mixer muting 1\n" );
                                }
                            # CD 0010 end
                            }
                        }
                    }
                }
            }
        }
    }
    return;
}

# ##############################################################################
#  No PERL code beyond this line
# ##############################################################################
1;

=pod
=begin html
 
  <a name="SB_PLAYER"></a>
<h3>SB_PLAYER</h3>
<ul>
  <a name="SBplayerdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SB_PLAYER &lt;player_mac_adress&gt; [&lt;ampl&gt;] [&lt;coverart&gt;]</code>
    <br><br>
    This module allows you to control Squeezebox Media Players connected with a defined Logitech Media Server. An SB_SERVER device is needed to work.<br>
   Normally you don't need to define your SB_PLAYERS because autocreate will do that if enabled.<br><br>

   <ul>
      <li><code>&lt;player_mac_adress&gt;</code>: Mac adress of the player found in the LMS.  </li>
   </ul><br>   
   <b>Optional</b><br><br>
   <ul>
      <li><code>&lt;[ampl]&gt;</code>: You can define an FHEM Device to command when an on or off event is received. With the attribute
      <a href="#SBplayeramplifier">amplifier</a> you can specify whether to command the selected FHEM Device on on|off or play|stop.</li>
      <li><code>&lt;[coverart]&gt;</code>: You can define an FHEM weblink. The player will update the weblink with the current coverart.
      Useful for putting coverarts in the floorplan.</li>
   </ul><br><br>
  </ul>
   
  <a name="SBplayerset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>
    This module supports the following commands:<br>
   
    SB_Player related commands:<br><br>
   <ul>
      <li><b>play</b> -  starts the playback (might only work if previously paused).</li>
     <li><b>pause [&lt;0|1&gt;]</b> -  toggles between play and pause. With parameter 0 it unpauses and with 1 it pauses the player, it doesn't matter which state it had before</li>
     <li><b>stop</b> -  stop the playback</li>
     <li><b>next|channelUp</b> -  jump to the next track</li>
     <li><b>prev|channelDown</b> -  jump to the previous track or the beginning of the current track.</li>
     <li><b>mute</b> -  toggles between muted and unmuted</li>
     <li><b>volume &lt;n&gt;</b> -  sets the volume to &lt;n&gt;. &lt;n&gt; must be a number between 0 and 100</li>
     <li><b>volumeStraight &lt;n&gt;</b> -  same as volume</li>
     <li><b>volumeDown &lt;n&gt;</b> -  volume down</li>
     <li><b>volumeUp &lt;n&gt;</b> -  volume up</li>
     <li><b>on</b> -  set the player on if possible. Otherwise it does play</li>
     <li><b>off</b> -  set the player off if possible. Otherwise it does stop</li>
     <li><b>shuffle &lt;on|off|song|album&gt;</b> -  Enables/Disables shuffle mode</li>
     <li><b>repeat &lt;one|all|off&gt;</b> -  Sets the repeat mode</li>
     <li><b>sleep &lt;n&gt;</b> -  Sets the player off in &lt;n&gt; seconds and fade the player volume down</li>   
     <li><b>favorites &lt;favorit&gt;</b> -  Empty the current playlist and start the selected playlist. Favorites are selectable through a dropdown list</li>   
     <li><b>talk|sayText &lt;text&gt;</b> -  Empty the current playlist and speaks the selected text with google TTS</li>
     <li><b>playlist &lt;track|album|artist|genre|year&gt; &lt;x&gt;</b> -  Empty the current playlist and starts the track, album or artist &lt;x&gt;</li>
     <li><b>playlist &lt;genre&gt; &lt;artist&gt; &lt;album&gt;</b> -  Empty the current playlist starts the track which will match the search. You can use * as wildcard for everything</li>
     Example:
     <code>set myplayer playlist * Whigfield *</code>
     <li><b>statusRequest</b> -  Update of all readings</li>
     <li><b>sync</b> -  Sync with other SB_Player for multiroom function. Other players are selectable through a dropdown list. The shown player is the master</li> /* CHECK BESCHREIBUNG
     <li><b>unsync</b> -  Unsync the player from multiroom group</li>
     <li><b>playlists</b> -  Empty the current playlist and start the selected playlist. Playlists are selectable through a dropdown list</li>
     <li><b>cliraw &lt;command&gt;</b> -  Sends the &lt;command&gt; to the LMS CLI for selected player</li>
   </ul>
  <br>Show<br>
   <ul>
      <code>set sbradio show &lt;line1&gt; &lt;line2&gt; &lt;duration&gt;</code>
     <li><b>line1</b> -  Text for first line</li>
     <li><b>line2</b> -  Text for second line</li>
     <li><b>duration</b> -  Duration for apperance in seconds</li>
   </ul>
  <br>Alarms<br>
   <ul>
   You can define up to 2 alarms.
      <code>set sbradio alarm1 set &lt;weekday&gt; &lt;time&gt;</code>
     <li><b>&lt;weekday&gt;</b> -  Number of weekday. The week starts with Sunday and is 0</li>
     <li><b>&lt;time&gt;</b> -  Timeformat HH:MM[:SS]</li>
   Example:<br>
   <code>set sbradio alarm1 set 5 12:23:17<br>
set sbradio alarm2 set 4 17:18:00</code>
     <li><b>alarm&lt;1|2&gt; delete</b> -  Delete alarm</li>
     <li><b>alarm&lt;1|2&gt; volume &lt;n&gt;</b> -  Set volume for alarm to &lt;n&gt;</li>
     <li><b>alarm&lt;1|2&gt; &lt;enable|disable&gt;</b> -  Enable or disable alarm</li>
     <li><b>allalarms &lt;enable|disable&gt;</b> -  Enable or disable all alarms</li>
   </ul>
   <br>
      
  <br>
  </ul>
  <b>Generated Readings</b><br>
  <ul>
   <li><b>READING</b> - READING DESCRIPTIONS</li>  /* CHECK TODO
  </ul>

  <br><br>
  <a name="SBplayerattr"></a>
  <b>Attributes</b>
  <ul>
    <li>IODev<br>
      The name of the SB_SERVER device to which this player is connected.</li><br>
    <li>donotnotify<br>
      Disables all events from the device. Must be explicitly set to <code>false</code> to enable events.</li><br>
    <li>volumeLimit<br>
      Sets the volume limit of the player between 0 and 100. 100 means the function is disabled.</li><br>
    <li><a name="SBplayeramplifier">amplifier</a><br>
      Defines how a configured amplifier will be controlled. If set to <code>on</code>, the amplifier will be turned on and off with the
      player. If set to <code>play</code> the amplifier will be turned on on play and off on stop.</li><br>
    <li>amplifierDelayOff<br>
      Sets the delay in seconds before turning the amplifier off after the player has stopped or been turned off.</li><br>
    <li>updateReadingsOnSet<br>
      If set to true most readings are immediately updated when a set command is executed without waiting for the reply from the server.</li><br>
  </ul>
</ul>
=end html
=cut

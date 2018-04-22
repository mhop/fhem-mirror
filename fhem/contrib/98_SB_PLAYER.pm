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
#  Contributions from: Siggi85, Oliv06, ChrisD, Markus M., Matthew, KernSani,
#                      Heppel, Eberhard, Elektrolurch
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

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use constant { true => 1, false => 0 };

sub SB_PLAYER_SonginfoHandleQueue($);   # CD 0075
sub SB_PLAYER_RemoveInternalTimers($);  # CD 0078
sub SB_PLAYER_ftuiMedialist($);         # CD 0082
sub SB_PLAYER_TTSLogPlayerState($$);    # CD 0097

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
use constant TTS_WAITFORPOWERON                          => 10;
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
                    10  =>'wait for power on',
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
                    1000=>'active (sync group)',
                    2004=>'Text2Speech busy, waiting',
                    2006=>'Text2Speech active');

my $SB_PLAYER_hasDataDumper = 1;        # CD 0036

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
    $hash->{AttrList}  = "IODev do_not_notify:1,0 ";    # CD 0077 ignore:1,0 entfernt, nicht verwendet
    $hash->{AttrList}  .= "volumeStep volumeLimit ";
    $hash->{AttrList}  .= "ttslanguage:de,en,fr ttslink:multiple,Google,VoiceRSS ";
    $hash->{AttrList}  .= "donotnotify:true,false ";
    $hash->{AttrList}  .= "idismac ";      # CD 0077 nicht verwendet, entfernen
    $hash->{AttrList}  .= "serverautoon "; # CD 0077 nicht verwendet, entfernen
    $hash->{AttrList}  .= "fadeinsecs ";
    $hash->{AttrList}  .= "amplifier:on,play ";
    $hash->{AttrList}  .= "coverartheight:50,100,200,400,800,1600 ";
    $hash->{AttrList}  .= "coverartwidth:50,100,200,400,800,1600 ";
    # CD 0028
    $hash->{AttrList}  .= "ttsVolume ";
    $hash->{AttrList}  .= "ttsOptions:multiple-strict,debug,debugsaverestore,unsync,nosaverestore,forcegroupon,ignorevolumelimit,eventondone "; # CD 0062 Auswahl vorgeben

    $hash->{AttrList}  .= "trackPositionQueryInterval "; # CD 0064
    $hash->{AttrList}  .= "sortFavorites:1,0 sortPlaylists:1,0 "; # CD 0064
    $hash->{AttrList}  .= "volumeOffset "; # CD 0065

    # CD 0030
    $hash->{AttrList}  .= "ttsDelay ";
    # CD 0032
    $hash->{AttrList}  .= "ttsPrefix "; # DJAlex 665
    # CD 0033
    $hash->{AttrList}  .= "ttsMP3FileDir ";
    $hash->{AttrList}  .= "ttsAPIKey ";                             # CD 0045
    # CD 0007
    $hash->{AttrList}  .= "syncVolume ";
    $hash->{AttrList}  .= "amplifierDelayOff ";                     # CD 0012
    $hash->{AttrList}  .= "updateReadingsOnSet:true,false ";        # CD 0017
    $hash->{AttrList}  .= "statusRequestInterval ";                 # CD 0037
    $hash->{AttrList}  .= "syncedNamesSource:LMS,FHEM ";            # CD 0055
    $hash->{AttrList}  .= "ftuiSupport:multiple-strict,1,0,medialist,favorites,playlists ";                       # CD 0065 neu # CD 0086 Auswahl hinzugefügt
    $hash->{AttrList}  .= "amplifierMode:exclusive,shared ";            # CD 0088
    $hash->{AttrList}  .= "disable:0,1 ";                           # CD 0091
    $hash->{AttrList}  .= $readingFnAttributes;

    # CD 0036 aus 37_sonosBookmarker
    eval "use Data::Dumper";
    $SB_PLAYER_hasDataDumper = 0 if($@);
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
        return "$name: device is disabled, setting syncVolume is not possible" if(IsDisabled($name));   # CD 0091
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
           0 ) unless(IsDisabled($name));   # CD 0091 bei disable Timer nicht starten
    }
    # CD 0043 start
    elsif( $args[ 0 ] eq "amplifierDelayOff" ) {
      $hash->{helper}{amplifierDelayOffStop}=0;
      $hash->{helper}{amplifierDelayOffPower}=0;
      $hash->{helper}{amplifierDelayOffPause}=0;
      if( $cmd eq "set" ) {
        if (defined($args[1])) {
          my @delays=split(',',$args[1]);
          $hash->{helper}{amplifierDelayOffStop}=$delays[0]+0 if defined($delays[0]);
          $hash->{helper}{amplifierDelayOffPower}=$delays[0]+0 if defined($delays[0]);
          $hash->{helper}{amplifierDelayOffPause}=$delays[1]+0 if defined($delays[1]);
        } else {
            return "missing value for amplifierDelayOff";
        }
      } else {

      }
    }
    # CD 0043 end
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
                    $hash->{helper}{ttsOptions}{doubleescape}=1 if($opt=~ m/doubleescape/);   # CD 0059
                    $hash->{helper}{ttsOptions}{eventondone}=1 if($opt=~ m/eventondone/);   # CD 0061
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
    # CD 0037
    elsif( $args[ 0 ] eq "statusRequestInterval" ) {
      RemoveInternalTimer( $hash );
      if( $cmd eq "set" ) {
        if (defined($args[1])) {
          InternalTimer( gettimeofday() + $args[1],
                         "SB_PLAYER_GetStatus",
                         $hash,
                         0 ) if (($args[1]>0) && !IsDisabled($name));
        } else {
            return "missing value for statusRequestInterval";
        }
      } else {
        InternalTimer( gettimeofday() + 5,
                       "SB_PLAYER_GetStatus",
                       $hash,
                       0 ) unless(IsDisabled($name));   # CD 0091 bei disable Timer nicht starten
      }
    }
    # CD 0055 start
    elsif( $args[ 0 ] eq "syncedNamesSource" ) {
        IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" ) if (($init_done>0) && !IsDisabled($name));
    }
    # CD 0055 end
    # CD 0064 start
    elsif( $args[ 0 ] eq "trackPositionQueryInterval" ) {
      if( $cmd eq "set" ) {
        RemoveInternalTimer( "QueryElapsedTime:$name");
        if ((ReadingsVal($name,"playStatus","x") eq "playing")&&($args[1]>0)) {
          InternalTimer( gettimeofday() + $args[1],
             "SB_PLAYER_tcb_QueryElapsedTime",
             "QueryElapsedTime:$name",
             0 ) unless(IsDisabled($name));   # CD 0091 bei disable Timer nicht starten
        }
      }
    }
    elsif( $args[ 0 ] eq "sortPlaylists" ) {
      if( $cmd eq "set" ) {
        if ($args[1] eq "1") {
          my @radios = split(',',$hash->{SERVERPLAYLISTS});
          $hash->{SERVERPLAYLISTS} = join(',',sort { "\L$a" cmp "\L$b" } @radios);
        }
      }
    }
    elsif( $args[ 0 ] eq "sortFavorites" ) {
      if( $cmd eq "set" ) {
        if ($args[1] eq "1") {
          my @radios = split(',',$hash->{FAVSTR});
          $hash->{FAVSTR} = join(',',sort { "\L$a" cmp "\L$b" } @radios);
        }
      }
    }
    # CD 0064 end
    # CD 0091 start
    elsif( $args[ 0 ] eq "disable" ) {
        if( $cmd eq "set" ) {
            if( $args[1] eq "0" ) {
                InternalTimer( gettimeofday() + 0.01,
                             "SB_PLAYER_GetStatus",
                             $hash,
                             0 );
            } else {
                SB_PLAYER_RemoveInternalTimers($hash);
            }
        } else {
            InternalTimer( gettimeofday() + 0.01,
                         "SB_PLAYER_GetStatus",
                         $hash,
                         0 );
        }
    }
    # CD 0091 end
    # CD 0065 start
    elsif( $args[ 0 ] eq "ftuiSupport" ) {
      my $dodelete=0;

      return "$name: device is disabled, changing ftuiSupport is not possible" if(IsDisabled($name));   # CD 0091
 
      if( $cmd eq "set" ) {
        # CD 0086 Readings einzeln aktivierbar
        my @options=split(',',$args[1]);
        delete($hash->{helper}{ftuiSupport}) if(defined($hash->{helper}{ftuiSupport}));
        $hash->{helper}{ftuiSupport}{enable}=($args[1] eq '0')?0:1;
            
        for my $opt (@options) {
            $hash->{helper}{ftuiSupport}{favorites}=1 if($opt=~ m/favorites/)||($opt eq '1');
            $hash->{helper}{ftuiSupport}{playlists}=1 if($opt=~ m/playlists/)||($opt eq '1');
            $hash->{helper}{ftuiSupport}{medialist}=1 if($opt=~ m/medialist/)||($opt eq '1');
        }
        
        if(defined($hash->{helper}{ftuiSupport})) {
            # CD 0082 Readings setzen (kein manueller statusRequest mehr nötig)
            readingsBeginUpdate( $hash );
            if(defined($hash->{helper}{ftuiSupport}{favorites})) {
                my $t=$hash->{FAVSTR};
                $t=~s/,/:/g;
                readingsBulkUpdate( $hash, "ftuiFavoritesItems", $t );
                $t=~s/_/ /g;
                readingsBulkUpdate( $hash, "ftuiFavoritesAlias", $t );
            }
            if(defined($hash->{helper}{ftuiSupport}{playlists})) {
                my $t=$hash->{SERVERPLAYLISTS};
                $t=~s/,/:/g;
                readingsBulkUpdate( $hash, "ftuiPlaylistsItems", $t );
                $t=~s/_/ /g;
                readingsBulkUpdate( $hash, "ftuiPlaylistsAlias", $t );
            }
            if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
                readingsEndUpdate( $hash, 0 );
            } else {
                readingsEndUpdate( $hash, 1 );
            }
            # CD 0082 end
        
            delete($hash->{SONGINFOQUEUE}) if(defined($hash->{SONGINFOQUEUE})); # CD 0072
            $hash->{helper}{songinfoquery}='';              # CD 0084
            $hash->{helper}{songinfocounter}=0;             # CD 0084
            $hash->{helper}{songinfopending}=0;             # CD 0084
            if(defined($hash->{helper}{ftuiSupport}{medialist})) {
                if(defined($hash->{helper}{playlistIds})) {
                    $hash->{helper}{playlistInfoRetries}=5; # CD 0076
                    my @ids=split(',',$hash->{helper}{playlistIds});
                    foreach(@ids) {
                        # CD 0084 verzögert abfragen, ansonsten Probleme bei schwacher Hardware
                        SB_PLAYER_SonginfoAddQueue($hash,$_,0) unless((defined($hash->{helper}{playlistInfo}{$_}) && !defined($hash->{helper}{playlistInfo}{$_}{remote})) || ($_==0));
                    }
                    SB_PLAYER_SonginfoAddQueue($hash,0,0);
                }
            }
        }
      } else {
        delete($hash->{helper}{ftuiSupport}) if(defined($hash->{helper}{ftuiSupport}));
        $hash->{helper}{ftuiSupport}{enable}=0;
        $dodelete=1;
      }
      # CD 0068 start
      if(($dodelete==1)||!defined($hash->{helper}{ftuiSupport}{medialist})) {
        delete($hash->{READINGS}{ftuiMedialist}) if defined($hash->{READINGS}{ftuiMedialist});
      }
      if(($dodelete==1)||!defined($hash->{helper}{ftuiSupport}{playlists})) {
        delete($hash->{READINGS}{ftuiPlaylistsItems}) if defined($hash->{READINGS}{ftuiPlaylistsItems});
        delete($hash->{READINGS}{ftuiPlaylistsAlias}) if defined($hash->{READINGS}{ftuiPlaylistsAlias});
      }
      if(($dodelete==1)||!defined($hash->{helper}{ftuiSupport}{favorites})) {
        delete($hash->{READINGS}{ftuiFavoritesItems}) if defined($hash->{READINGS}{ftuiFavoritesItems});
        delete($hash->{READINGS}{ftuiFavoritesAlias}) if defined($hash->{READINGS}{ftuiFavoritesAlias});
      }
      # CD 0068 end
    }
    # CD 0065 end

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
        # CD 0089 auf IP-Adresse prüfen
        if( SB_PLAYER_IsValidIPV4( $a[ 0] ) == 1 ) {
            $hash->{PLAYERMAC} = $a[ 0 ];
        } else {
            my $msg = "SB_PLAYER_Define: playerid ist keine MAC Adresse " .
                "im Format xx:xx:xx:xx:xx:xx oder xx-xx-xx-xx-xx-xx";
            Log3( $hash, 1, $msg );
            return( $msg );
        }
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

    if (!defined($hash->{OLDDEF})) {    # CD 0044
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
    }

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
        $attr{$name}{fadeinsecs} = "10";
    }

    # do not create FHEM notifies (true=no notifies)
    if( !defined( $attr{$name}{donotnotify} ) ) {
        $attr{$name}{donotnotify} = "true";
    }

    # is the ID the MAC adress # CD 0077 nicht verwendet, deaktiviert
    #if( !defined( $attr{$name}{idismac} ) ) {
    #    $attr{$name}{idismac} = "true";
    #}

    # the language for text2speech
    if( !defined( $attr{$name}{ttslanguage} ) ) {
        $attr{$name}{ttslanguage} = "de";
    }

    # link to the text2speech engine
    if( !defined( $attr{$name}{ttslink} ) ) {
        $attr{$name}{ttslink} = "http://translate.google.com" .
            "/translate_tts?ie=UTF-8&tl=<LANG>&q=<TEXT>&client=tw-ob";   # CD 0045 Format geändert, &client=t&prev=input hinzugefügt, CD 0048 client=tw-ob verwenden
    }

    # turn on the server when player is used # CD 0077 nicht verwendet, deaktiviert
    #if( !defined( $attr{$name}{serverautoon} ) ) {
    #    $attr{$name}{serverautoon} = "true";
    #}

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
    if( !defined( $hash->{READINGS}{lastunknowncmd}{VAL} ) ) {
        $hash->{READINGS}{lastunknowncmd}{VAL} = "none";
        $hash->{READINGS}{lastunknowncmd}{TIME} = $tn;
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

    # mrbreil 0047 start
    if( !defined( $hash->{READINGS}{currentTrackPosition}{VAL} ) ) {
        $hash->{READINGS}{currentTrackPosition}{VAL} = 0;
        $hash->{READINGS}{currentTrackPosition}{TIME} = $tn;
    }
    # mrbreil 0047 end

    $hash->{helper}{ttsstate}=TTS_IDLE;  # CD 0028

    $hash->{helper}{noStopEventUntil}=0; # CD 0063

    if (!defined($hash->{OLDDEF})) {    # CD 0044
        SB_PLAYER_LoadPlayerStates($hash) if($SB_PLAYER_hasDataDumper==1);   # CD 0036

        $hash->{helper}{playerStatusOK}=0;          # CD 0042
        $hash->{helper}{playerStatusOKCounter}=0;   # CD 0042

        $hash->{helper}{amplifierDelayOffStop}=0;   # CD 0043
        $hash->{helper}{amplifierDelayOffPower}=0;  # CD 0043
        $hash->{helper}{amplifierDelayOffPause}=0;  # CD 0043
        $hash->{helper}{lmsvolume}=0;               # CD 0065
        $hash->{helper}{amplifierLastStatus}='x';   # CD 0087
    }

    $hash->{helper}{songinfoquery}='';              # CD 0084
    $hash->{helper}{songinfocounter}=0;             # CD 0084
    $hash->{helper}{songinfopending}=0;             # CD 0084

    # do and update of the status
    InternalTimer( gettimeofday() + 10,
                   "SB_PLAYER_GetStatus",
                   $hash,
                   0 );

    # CD 0091 statusRequest beim Server auslösen damit Favoriten und Wiedergabelisten übertragen werden
    InternalTimer( gettimeofday() + 15,
            "SB_PLAYER_tcb_ServerStatusRequest",
            "ServerStatusRequest:$name",
            0 );

    notifyRegexpChanged($hash, "global"); # CD 0080

    return( undef );
}

# CD 0091 start
sub SB_PLAYER_tcb_ServerStatusRequest($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));

    if (defined($hash->{IODev}) && defined($hash->{IODev}->{NAME})) {
        if(ReadingsVal($hash->{IODev}->{NAME},'state','x') eq 'opened') {
            fhem('set '.($hash->{IODev}->{NAME}).' statusRequest');
        }
    }
}
# CD 0091 end

# CD 0002 start
sub SB_PLAYER_tcb_QueryCoverArt($) {    # CD 0014 Name geändert
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    #Log 0,"delayed cover art query";
    IOWrite( $hash, "$hash->{PLAYERMAC} status - 1 tags:Kcu\n" );   # CD 0030 u added to tags

    # CD 0005 query cover art for synced players
    if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
        if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {    # CD 0018 none hinzugefügt
            my @pl=split(",",$hash->{SYNCGROUP});
            foreach (@pl) {
                IOWrite( $hash, "$_ status - 1 tags:Kcu\n" );   # CD 0039 u hinzugefügt
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

    delete($hash->{helper}{recallPause}) if (defined($hash->{helper}{recallPause}));
    delete($hash->{helper}{pauseAfterPlay}) if (defined($hash->{helper}{pauseAfterPlay}));  # CD 0095
}

sub SB_PLAYER_QueryElapsedTime($) {
    my ($hash) = @_;

    return if(IsDisabled($hash->{NAME}));   # CD 0091

    my $qi=AttrVal($hash->{NAME}, "trackPositionQueryInterval", 5); # CD 0064

    if(!defined($hash->{helper}{lastTimeQuery})||($hash->{helper}{lastTimeQuery}<gettimeofday()-$qi)) {
    #Log 0,"Querying time, last: $hash->{helper}{lastTimeQuery}, now: ".gettimeofday();
        $hash->{helper}{lastTimeQuery}=gettimeofday();
        IOWrite( $hash, "$hash->{PLAYERMAC} time ?\n" );
    }
}
# CD 0014 end

# CD 0047 start
sub SB_PLAYER_tcb_QueryElapsedTime( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    my $qi=AttrVal($hash->{NAME}, "trackPositionQueryInterval", 5); # CD 0064

    SB_PLAYER_QueryElapsedTime($hash);
    RemoveInternalTimer( "QueryElapsedTime:$name");
    if ((ReadingsVal($name,"playStatus","x") eq "playing")&&($qi>0)) {
      InternalTimer( gettimeofday() + $qi,
         "SB_PLAYER_tcb_QueryElapsedTime",
         "QueryElapsedTime:$name",
         0 );
    }
}
# CD 0047 end

# CD 0028 start
sub SB_PLAYER_tcb_TTSRestore( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    # CD 0033 start
    if(defined($hash->{helper}{ttsqueue})) {
        SB_PLAYER_SetTTSState($hash,TTS_LOADPLAYLIST,0,0);
        SB_PLAYER_LoadTalk($hash);
    } else {
    # CD 0033 end
        if(!defined($hash->{helper}{ttsActiveOptions}{nosaverestore}) && !defined($hash->{helper}{sgTalkActive})) {   # CD 0063 sgTalkActive hinzugefügt
            SB_PLAYER_SetTTSState($hash,TTS_RESTORE,0,0);
            SB_PLAYER_Recall( $hash, "xxTTSxx del" );
        } else {
            SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
            delete $hash->{helper}{sgTalkActive} if defined($hash->{helper}{sgTalkActive}); # CD 0063
        }
    }
}
# CD 0028 end

# CD 0091 start
# ----------------------------------------------------------------------------
#  Player ist nicht (mehr) vorhanden, aufräumen
# ----------------------------------------------------------------------------
sub SB_PLAYER_SetPlayerAbsent( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_PLAYER_SetPlayerAbsent($name) called" );

    readingsBulkUpdate( $hash, 'connected', '0' );  # CD 0091
    readingsBulkUpdate( $hash, 'presence', 'absent' );
    readingsBulkUpdate( $hash, 'state', 'off' );
    readingsBulkUpdate( $hash, 'power', 'off' );
    # CD 0074 bei disconnect playStatus und Timer zurücksetzen
    readingsBulkUpdate( $hash, 'playStatus', 'stopped' );
    RemoveInternalTimer( $hash );
    RemoveInternalTimer( "QueryElapsedTime:$name");
    $hash->{WILLSLEEPIN} = '?'; # CD 0089
    delete($hash->{helper}{recallPause}) if (defined($hash->{helper}{recallPause}));    # CD 0095
    delete($hash->{helper}{pauseAfterPlay}) if (defined($hash->{helper}{pauseAfterPlay}));  # CD 0095
    # CD 0074 end
    SB_PLAYER_Amplifier( $hash );
    # CD 0031 wenn Player während TTS verschwindet Zustand zurücksetzen
    if(($hash->{helper}{ttsstate}>TTS_IDLE)&&($hash->{helper}{ttsstate}<TTS_RESTORE)) {
        $hash->{helper}{savedPlayerState}{power}="off" if(defined($hash->{helper}{savedPlayerState}));
        SB_PLAYER_SetTTSState($hash,TTS_STOP,1,0);
        RemoveInternalTimer( "TTSRestore:$name");
        InternalTimer( gettimeofday() + 0.01,
           'SB_PLAYER_tcb_TTSRestore',
           "TTSRestore:$name",
           0 );
    }
    # CD 0031 end
}
# CD 0091 start

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

    # storing the last in an array is necessary, for tagged responses
    my ( $modtype, $id, @data ) = split(":", $msg, 3 );

    Log3( $iohash, 5, "SB_PLAYER_Parse: type:$modtype, ID:$id CMD:@data" );

    if( $modtype ne "SB_PLAYER" ) {
        # funny stuff happens at the disptach function
        Log3( $iohash, 5, "SB_PLAYER_Parse: wrong type given." );
    }

    # let's see what we got. Split the data at the space
    # necessary, for tagged responses
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
            # CD 0089 auf IP-Adresse prüfen
            if( SB_PLAYER_IsValidIPV4( $id ) == 1 ) {
                $hash->{PLAYERMAC} = $id;
                Log3( undef, 3, "SB_PLAYER_Parse: the unknown ID $id is a valid " .
                      "IPv4 Adress" );
                # this line supports autocreate
                return( "UNDEFINED SB_PLAYER_$id SB_PLAYER $id" );
            } else {
                # the MAC adress is not valid
                Log3( undef, 3, "SB_PLAYER_Parse: the unknown ID $id is NOT " .
                      "a valid MAC Adress" );
                return( undef );
            }
        }
    }

    # so the data is for us
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

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
                # CD 0040 start
                if( ( index( $args[ 1 ], "+" ) != -1 ) || ( index( $args[ 1 ], "-" ) != -1 ) ) {
                    # that was a relative value. We do nothing and fire an update
                    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" );
                } else {
                # CD 0040 end
                    SB_PLAYER_UpdateVolumeReadings( $hash, $args[ 1 ], true );
                    # CD 0007 start
                    if((defined($hash->{helper}{setSyncVolume}) && ($hash->{helper}{setSyncVolume} != $args[ 1 ]))|| (!defined($hash->{helper}{setSyncVolume}))) {
                        SB_PLAYER_SetSyncedVolume($hash,$args[ 1 ],0);
                    }
                    delete $hash->{helper}{setSyncVolume};
                    # CD 0007 end
                }
            }
        }

    } elsif( $cmd eq "remote" ) {
        if( defined( $args[ 0 ] ) ) {
            $hash->{ISREMOTESTREAM} = "$args[ 0 ]";
        } else {
            $hash->{ISREMOTESTREAM} = "0";
        }


    } elsif( $cmd eq "play" ) {
        if(!defined($hash->{helper}{recallPause}) && !defined($hash->{helper}{pauseAfterPlay})) {    # CD 0014 CD 0095
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
        my $updateSyncedPlayers=0;  # CD 0039
        # a little more complex to fulfill FHEM Development guidelines
        Log3( $hash, 5, "SB_PLAYER_Parse($name): mode:$cmd args:$args[0]" );
        if( $args[ 0 ] eq "play" ) {
            # CD 0014 start
            # CD 0095 pause muss an alle Player der Gruppe geschickt werden
            if(defined($hash->{helper}{recallPause}) || defined($hash->{helper}{pauseAfterPlay})) { # CD 0095
                IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                    my @pl=split(",",$hash->{SYNCGROUP});
                    foreach (@pl) {
                        if ($hash->{PLAYERMAC} ne $_) {
                            IOWrite( $hash, "$_ pause 1\n" );
                        }
                    }
                }
                # CD 0095 start
                RemoveInternalTimer( "recallPause:$name");
                InternalTimer( gettimeofday() + 2.0,    # CD 0095 Zeit eventuell nicht ausreichend bei vielen oder langsamen Playern
                   "SB_PLAYER_tcb_DeleteRecallPause",
                   "recallPause:$name",
                   0 );
                # CD 0095 end
            } else {
            # CD 0014 end
                readingsBulkUpdate( $hash, "playStatus", "playing" );
                SB_PLAYER_Amplifier( $hash );
                SB_PLAYER_QueryElapsedTime( $hash );    # CD 0014
                # CD 0047 start
                RemoveInternalTimer( "QueryElapsedTime:$name");
                my $qi=AttrVal($hash->{NAME}, "trackPositionQueryInterval", 5); # CD 0064
                if($qi>0) { # CD 0064
                    InternalTimer( gettimeofday() + $qi,
                      "SB_PLAYER_tcb_QueryElapsedTime",
                      "QueryElapsedTime:$name",
                    0 );
                    # CD 0047 end
                }
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
            $updateSyncedPlayers=1;     # CD 0039 gesyncte Player aktualisieren
        } elsif( $args[ 0 ] eq "stop" ) {
            # CD 0028 start
            if($hash->{helper}{ttsstate}==TTS_PLAYING) {
                RemoveInternalTimer( "TTSStopped:$name");   # CD 0091
                SB_PLAYER_TTSStopped($hash);
            }

            # wenn tts auf Slave aktiv ist schickt der LMS den Stop nur an den Master
            if (ReadingsVal($name,"presence","x") eq "present") {   # CD 0056 Meldung nicht weiterschicken wenn der Master nicht 'present' ist
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
            }
            # CD 0028 end
            readingsBulkUpdate( $hash, "playStatus", "stopped" );
            SB_PLAYER_Amplifier( $hash );
            RemoveInternalTimer( "QueryElapsedTime:$name");         # CD 0047
            readingsBulkUpdate( $hash, "currentTrackPosition", 0 ); # CD 0047
            $updateSyncedPlayers=1;     # CD 0039 gesyncte Player aktualisieren
        } elsif( $args[ 0 ] eq "pause" ) {
            readingsBulkUpdate( $hash, "playStatus", "paused" );
            SB_PLAYER_Amplifier( $hash );
            $updateSyncedPlayers=1;     # CD 0039 gesyncte Player aktualisieren
        } else {
            readingsBulkUpdate( $hash, "playStatus", $args[ 0 ] );
        }

        # CD 0039 gesyncte Player aktualisieren
        if($updateSyncedPlayers==1) {
            if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                    my @pl=split(",",$hash->{SYNCGROUP});
                    foreach (@pl) {
                        if ($hash->{PLAYERMAC} ne $_) {
                            IOWrite( $hash, "$_ mode ?\n" );
                        }
                    }
                }
            }
        }
        # CD 0039 end

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
            if(defined($hash->{helper}{recallPause}) || defined($hash->{helper}{pauseAfterPlay})) { # CD 0095
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
            # CD 0039 Änderung am Master, gesyncte Player aktualisieren
            if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                    my @pl=split(",",$hash->{SYNCGROUP});
                    foreach (@pl) {
                        IOWrite( $hash, "$_ playlist repeat ?\n" );
                    }
                }
            }
            # CD 0039 end
        } elsif( $args[ 0 ] eq "shuffle" ) {
            if(defined($args[ 1 ])) {    # CD 0086
                if( $args[ 1 ] eq "0" ) {
                    readingsBulkUpdate( $hash, "shuffle", "off" );
                } elsif( $args[ 1 ] eq "1") {
                    readingsBulkUpdate( $hash, "shuffle", "song" );
                } elsif( $args[ 1 ] eq "2") {
                    readingsBulkUpdate( $hash, "shuffle", "album" );
                } else {
                    readingsBulkUpdate( $hash, "shuffle", "?" );
                }
                # CD 0039 Änderung am Master, gesyncte Player aktualisieren
                if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                    if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                        my @pl=split(",",$hash->{SYNCGROUP});
                        foreach (@pl) {
                            IOWrite( $hash, "$_ playlist shuffle ?\n" );
                        }
                    }
                }
                # CD 0039 end
                SB_PLAYER_GetStatus( $hash );       # CD 0014
            }
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
                if( defined($pn) && defined($hash->{helper}{SB_PLAYER_Favs}{$pn}) && defined($hash->{helper}{SB_PLAYER_Favs}{$pn}{ID})) {   # CD 0011 check if defined($hash->{helper}{SB_PLAYER_Favs}{$pn}) # CD 0091 check if $pn is defined
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
            $hash->{helper}{noStopEventUntil}=time()+2.0;   # CD 0063
        # CD 0021 end
        } elsif( $args[ 0 ] eq "clear" ) {
            readingsBulkUpdate( $hash, "currentPlaylistName", "none" );
            readingsBulkUpdate( $hash, "playlists", "none" );
            readingsBulkUpdate( $hash, "playlistTracks", 0 );   # CD 0084
            readingsBulkUpdate( $hash, "duration", 0 );         # CD 0084
            $hash->{helper}{playlistIds}='0';   # CD 0084
            readingsBulkUpdate( $hash, "ftuiMedialist", '[{"Artist":"-","Title":"-","Album":"-","Time":"0","File":"-","Track":"0","Cover":"-"}]') if(defined($hash->{helper}{ftuiSupport}{medialist}));  # CD 0084
            # CD 0009 end
            SB_PLAYER_GetStatus( $hash );       # CD 0014
        } elsif( $args[ 0 ] eq "url" ) {
            shift( @args );
            # CD 0091 überprüfen ob HASH vom LMS kommt, ignorieren
            my $plurl=join( " ", @args );
            if($plurl=~/HASH/) {
                readingsBulkUpdate( $hash, "currentPlaylistUrl", '');
            } else {
                readingsBulkUpdate( $hash, "currentPlaylistUrl", $plurl);
            }
        } elsif( $args[ 0 ] eq "stop" ) {
            readingsBulkUpdate( $hash, "playStatus", "stopped" );                # CD 0012 'power off' durch 'playStatus stopped' ersetzt
            SB_PLAYER_Amplifier( $hash );
            # CD 0063 start
            RemoveInternalTimer( "TriggerPlaylistStop:$name");
            InternalTimer( gettimeofday() + 1.0,
               "SB_PLAYER_tcb_TriggerPlaylistStop",
               "TriggerPlaylistStop:$name",
               0 );
            # CD 0063 stop
        # CD 0014 start
        } elsif( $args[ 0 ] eq "index" ) {
            readingsBulkUpdate( $hash, "playlistCurrentTrack", $args[ 1 ] eq '?' ? 0 : $args[ 1 ]+1 );  # Heppel 0056
            $queryMode=0;
        } elsif( $args[ 0 ] eq "addtracks" ) {
            $queryMode=0;
            SB_PLAYER_GetStatus( $hash );
        # CD 0068 start
        } elsif( $args[ 0 ] eq "add" ) {
            $queryMode=0;
            SB_PLAYER_GetStatus( $hash );
        # CD 0068 end
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
                    # CD 0038 Timeout hinzugefügt
                    RemoveInternalTimer( "TimeoutTTSWaitForPlay:$name");
                    InternalTimer( gettimeofday() + 10.00,
                       "SB_PLAYER_tcb_TimeoutTTSWaitForPlay",
                       "TimeoutTTSWaitForPlay:$name",
                       0 );
                    # CD 0038 end
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
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - play" );  # CD 0097
                IOWrite( $hash, "$hash->{PLAYERMAC} play 300\n" );
                IOWrite( $hash, "$hash->{PLAYERMAC} time $hash->{helper}{recallPendingElapsedTime}\n" ) if defined($hash->{helper}{recallPendingElapsedTime});    # CD 0047, Position setzen korrigiert
                delete($hash->{helper}{recallPendingElapsedTime});  # CD 0047
            }
        } elsif( $args[ 0 ] eq "loadtracks" ) {
            if(defined($hash->{helper}{recallPending})) {
                delete($hash->{helper}{recallPending});
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,1,1);
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - play" );  # CD 0097
                IOWrite( $hash, "$hash->{PLAYERMAC} play 300\n" );
                IOWrite( $hash, "$hash->{PLAYERMAC} time $hash->{helper}{recallPendingElapsedTime}\n" );    # CD 0047, Position setzen korrigiert
                delete($hash->{helper}{recallPendingElapsedTime});  # CD 0047
            }
        # CD 0014 end
        # CD 0048 start
        } elsif( $args[ 0 ] eq "path" ) {
            delete $hash->{helper}{path} if defined($hash->{helper}{path});
            if(defined($args[ 1 ]) && ($args[ 1 ] eq "0")) {
                $hash->{helper}{path}=$args[ 2 ] if defined($args[ 2 ]);
            }
        # CD 0048 end
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
        if($args[0] eq '1') {   # CD 0092 nur bei 1 auf present setzen
            readingsBulkUpdate( $hash, "presence", "present" );
        } else {
            SB_PLAYER_SetPlayerAbsent($hash);   # CD 0092
        }
    } elsif( $cmd eq "name" ) {
        $hash->{PLAYERNAME} = join( " ", @args );

    } elsif( $cmd eq "title" ) {
        readingsBulkUpdate( $hash, "currentTitle", join( " ", @args ) );
        RemoveInternalTimer( "ftuiMedialist:$name");    # CD 0085
        InternalTimer( gettimeofday() + 0.01,           # CD 0085
           "SB_PLAYER_tcb_ftuiMedialist",
           "ftuiMedialist:$name",
           0 ) if(defined($hash->{helper}{ftuiSupport}{medialist})); # CD 0082
    } elsif( $cmd eq "artist" ) {
        readingsBulkUpdate( $hash, "currentArtist", join( " ", @args ) );
        RemoveInternalTimer( "ftuiMedialist:$name");
        InternalTimer( gettimeofday() + 0.01,
           "SB_PLAYER_tcb_ftuiMedialist",
           "ftuiMedialist:$name",
           0 ) if(defined($hash->{helper}{ftuiSupport}{medialist})); # CD 0082
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
    # CD 0063 start
    } elsif( $cmd eq "playerdata" ) {
        $hash->{MODEL} = $args[ 0 ] unless $args[ 0 ] eq 'unknown';
        $hash->{CANPOWEROFF} = $args[ 1 ] unless $args[ 1 ] eq 'unknown';
        $hash->{DISPLAYTYPE} = $args[ 2 ] unless $args[ 2 ] eq 'unknown';
        if( $args[ 3 ] ne 'unknown' ) {
            readingsBulkUpdate( $hash, "connected", $args[ 3 ] );
            readingsBulkUpdate( $hash, "presence", "present" );
        }

        $hash->{PLAYERIP} = "$args[ 4 ]" unless $args[ 4 ] eq 'unknown';
        if( defined( $args[ 5 ] ) ) {
            $hash->{PLAYERIP} .= ":$args[ 5 ]";
        }
    # CD 0063 end
    } elsif( $cmd eq "power" ) {
        if( !( @args ) ) {
            # no arguments were send with the Power command
            # potentially this is a power toggle : should only happen
            # when called with SB CLI
        } elsif( $args[ 0 ] eq "1" ) {
            readingsBulkUpdate( $hash, "state", "on" );
            readingsBulkUpdate( $hash, "power", "on" );
            # CD 0091 start
            if(defined($hash->{helper}{playAfterPowerOn})) {
                IOWrite( $hash, "$hash->{PLAYERMAC} play ".$hash->{helper}{playAfterPowerOn}."\n" );
                delete($hash->{helper}{playAfterPowerOn});
            }
            # CD 0091 end
            SB_PLAYER_Amplifier( $hash );
        } elsif( $args[ 0 ] eq "0" ) {
            #readingsBulkUpdate( $hash, "presence", "absent" );      # CD 0013 deaktiviert, power sagt nichts über presence
            readingsBulkUpdate( $hash, "state", "off" );
            readingsBulkUpdate( $hash, "power", "off" );
            SB_PLAYER_Amplifier( $hash );
            $hash->{WILLSLEEPIN} = '?'; # CD 0089
            delete($hash->{helper}{recallPause}) if (defined($hash->{helper}{recallPause}));    # CD 0095
            delete($hash->{helper}{pauseAfterPlay}) if (defined($hash->{helper}{pauseAfterPlay}));  # CD 0095
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
            DoTrigger($name,"alarmSound ".SB_PLAYER_FindAlarmId($hash, $args[ 1 ])) if (SB_PLAYER_check_eocr($hash,'alarmSound'));  # CD 0046 # CD 0054 SB_PLAYER_check_eocr hinzugefügt
        } elsif( $args[ 0 ] eq "end" ) {
            # fired when an alarm ends
            DoTrigger($name,"alarmEnd ".SB_PLAYER_FindAlarmId($hash, $args[ 1 ])) if (SB_PLAYER_check_eocr($hash,'alarmEnd'));  # CD 0046 # CD 0054 SB_PLAYER_check_eocr hinzugefügt
        } elsif( $args[ 0 ] eq "snooze" ) {
            # fired when an alarm is snoozed by the user
            DoTrigger($name,"alarmSnooze ".SB_PLAYER_FindAlarmId($hash, $args[ 1 ])) if (SB_PLAYER_check_eocr($hash,'alarmSnooze'));  # CD 0046 # CD 0054 SB_PLAYER_check_eocr hinzugefügt
        } elsif( $args[ 0 ] eq "snooze_end" ) {
            # fired when an alarm comes back from snooze
            DoTrigger($name,"alarmSnoozeEnd ".SB_PLAYER_FindAlarmId($hash, $args[ 1 ])) if (SB_PLAYER_check_eocr($hash,'alarmSnoozeEnd'));  # CD 0046 # CD 0054 SB_PLAYER_check_eocr hinzugefügt
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
            SB_PLAYER_SetPlayerAbsent($hash);
        } elsif( $args[ 0 ] eq "reconnect" ) {
            IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" );         # CD 0030 u added to tags
            # CD 0079 nach reconnect Status abfragen
            delete($hash->{helper}{disableGetStatus}) if defined($hash->{helper}{disableGetStatus});
            InternalTimer( gettimeofday() + 5,
                           "SB_PLAYER_GetStatus",
                           $hash,
                           0 );
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
                    # CD 0038 start
                    if($hash->{helper}{ttsstate}==TTS_WAITFORPOWERON) {
                        # CD 0042 readingsBulkUpdate abwarten
                        RemoveInternalTimer( "TTSStartAfterPowerOn:$name");
                        InternalTimer( gettimeofday() + 0.01,
                           "SB_PLAYER_tcb_TTSStartAfterPowerOn",
                           "TTSStartAfterPowerOn:$name",
                           0 );
                    }
                    # CD 0038 end
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
                    $hash->{WILLSLEEPIN} = '?'; # CD 0089
                    SB_PLAYER_Amplifier( $hash );
                    delete($hash->{helper}{playAfterPowerOn}) if(defined($hash->{helper}{playAfterPowerOn}));   # CD 0030
                    delete($hash->{helper}{recallPause}) if (defined($hash->{helper}{recallPause}));    # CD 0095
                    delete($hash->{helper}{pauseAfterPlay}) if (defined($hash->{helper}{pauseAfterPlay}));  # CD 0095
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
                SB_PLAYER_SetSyncedVolume($hash, -1, 0) if ($args[ 2 ] == 1);
                IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" ) if ($args[ 2 ] == 0);
            # CD 0010 end
            # CD 0016 start
            } elsif( $args[ 1 ] eq "alarmTimeoutSeconds" ) {
                readingsBulkUpdate( $hash, "alarmsTimeout", $args[ 2 ]/60 );
            } elsif( $args[ 1 ] eq "alarmSnoozeSeconds" ) {
                readingsBulkUpdate( $hash, "alarmsSnooze", $args[ 2 ]/60 );
            } elsif( $args[ 1 ] eq "alarmDefaultVolume" ) {
                readingsBulkUpdate( $hash, "alarmsDefaultVolume", $args[ 2 ] ); # CD 0052 fixed
            } elsif( $args[ 1 ] eq "alarmfadeseconds" ) {
                if($args[ 2 ] ne "0") {
                    readingsBulkUpdate( $hash, "alarmsFadeIn", "on" );
                    readingsBulkUpdate( $hash, "alarmsFadeSeconds", $args[ 2 ] );   # CD 0082
                } else {
                    readingsBulkUpdate( $hash, "alarmsFadeIn", "off" );
                }
            # CD 0016 end
            # CD 0018 start
            } elsif( $args[ 1 ] eq "syncgroupid" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" );     # CD 0030 u added to tags
            # CD 0018 end
            # CD 0039 für gesyncte Player bei Änderung am Slave erhält der Master eine prefset Meldung, an alle Slaves weitergeben
            } elsif( $args[ 1 ] eq "repeat" ) {
                if( $args[ 2 ] eq "0" ) {
                    readingsBulkUpdate( $hash, "repeat", "off" );
                } elsif( $args[ 2 ] eq "1") {
                    readingsBulkUpdate( $hash, "repeat", "one" );
                } elsif( $args[ 2 ] eq "2") {
                    readingsBulkUpdate( $hash, "repeat", "all" );
                } else {
                    readingsBulkUpdate( $hash, "repeat", "?" );
                }
                if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                    if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                        my @pl=split(",",$hash->{SYNCGROUP});
                        if(@pl>1) {
                            foreach (@pl) {
                                IOWrite( $hash, "$_ playlist repeat ?\n" );
                            }
                        }
                    }
                }
            } elsif( $args[ 1 ] eq "shuffle" ) {
                if( $args[ 2 ] eq "0" ) {
                    readingsBulkUpdate( $hash, "shuffle", "off" );
                } elsif( $args[ 2 ] eq "1") {
                    readingsBulkUpdate( $hash, "shuffle", "song" );
                } elsif( $args[ 2 ] eq "2") {
                    readingsBulkUpdate( $hash, "shuffle", "album" );
                } else {
                    readingsBulkUpdate( $hash, "shuffle", "?" );
                }
                if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                    if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                        my @pl=split(",",$hash->{SYNCGROUP});
                        if(@pl>1) {
                            foreach (@pl) {
                                IOWrite( $hash, "$_ playlist shuffle ?\n" );
                            }
                        }
                    }
                }
                SB_PLAYER_GetStatus( $hash );
            # CD 0039 end
            }
        } else {
            readingsBulkUpdate( $hash, "lastunknowncmd",
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
        $args[0]=0 unless defined($args[ 0 ]); # CD 0059
        $args[0]=0 if($args[ 0 ] eq '?'); # CD 0050
        $hash->{helper}{elapsedTime}{VAL}=$args[ 0 ];
        $hash->{helper}{elapsedTime}{TS}=gettimeofday();
        readingsBulkUpdate( $hash, "currentTrackPosition",int($args[ 0 ]+0.5));  # CD 0047
        delete($hash->{helper}{saveLocked}) if (($hash->{helper}{ttsstate}==TTS_IDLE) && defined($hash->{helper}{saveLocked}));
        # CD 0091 Hänger erkennen
        # CD 0093 nur wenn abgespielt wird
        if(ReadingsVal($name,'playStatus','x') eq 'playing') {
            $hash->{helper}{elapsedTime}{last}=$args[ 0 ] unless defined($hash->{helper}{elapsedTime}{last});
            if($hash->{helper}{elapsedTime}{last} eq $args[ 0 ]) {
                $hash->{helper}{elapsedTime}{count}=0 unless defined($hash->{helper}{elapsedTime}{count});
                $hash->{helper}{elapsedTime}{count}++;
                if($hash->{helper}{elapsedTime}{count}>10) {
                    # Player noch vorhanden, Status abfragen
                    if(ReadingsVal($name,"presence","x") eq "present") {
                        Log3( $hash, 2, "SB_PLAYER_Parse($name): currentTrackPosition frozen, player present, sending status request");
                        delete($hash->{helper}{disableGetStatus}) if defined($hash->{helper}{disableGetStatus});
                        SB_PLAYER_GetStatus( $hash );
                        $hash->{helper}{elapsedTime}{count}=0;
                    }
                    if(ReadingsVal($name,"presence","x") eq "absent") {
                        Log3( $hash, 2, "SB_PLAYER_Parse($name): currentTrackPosition frozen, player absent, trying to stop...");
                        IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );
                        $hash->{helper}{elapsedTime}{count}=0;
                    }
                }
            } else {
                $hash->{helper}{elapsedTime}{count}=0;
                $hash->{helper}{elapsedTime}{last}=$args[ 0 ];
            }
        } else {
            $hash->{helper}{elapsedTime}{count}=0;
            $hash->{helper}{elapsedTime}{last}=$args[ 0 ];
        }
    } elsif( $cmd eq "playlist_tracks" ) {
        readingsBulkUpdate( $hash, "playlistTracks", $args[ 0 ] );
    # CD 0014 end
    # CD 0018 sync Meldungen auswerten, alle anderen Player abfragen
    } elsif( $cmd eq "sync" ) {
        foreach my $e ( keys %{$hash->{helper}{SB_PLAYER_SyncMasters}} ) {
            IOWrite( $hash, $hash->{helper}{SB_PLAYER_SyncMasters}{$e}{MAC}." status 0 500 tags:Kcu\n" ) if defined($hash->{helper}{SB_PLAYER_SyncMasters}{$e}{MAC});   # CD 0039 u hinzugefügt # CD 0056 if defined hinzugefügt
        }
        IOWrite( $hash, "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n" ); # CD 0056 auch betroffenen Player abfragen
    # CD 0018
    # CD 0052 jivealarm Meldungen ignorieren
    } elsif( $cmd eq "jivealarm" ) {
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
                        IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".SB_PLAYER_FHEM2LMSVolume($hash, $vol)."\n" );   # CD 0065 SB_PLAYER_FHEM2LMSVolume
                    }
                }
                # CD 0031 end
            }
            elsif ($args[0] eq "ttsstopped") {
                # CD 0056 Meldung ignorieren wenn Player Syncmaster ist
                if ($hash->{PLAYERMAC} eq $hash->{SYNCMASTER}) {
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsstopped, ignoring" );
                } else {
                # CD 0056 end
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_Parse: $name: fhemrelay ttsstopped" );
                    if($hash->{helper}{ttsstate}==TTS_PLAYING) {
                            # CD 0034 delay ttsstopped
                            RemoveInternalTimer( "TTSStopped:$name");
                            InternalTimer( gettimeofday() + 0.01,
                               "SB_PLAYER_tcb_TTSStopped",
                               "TTSStopped:$name",  # CD 0991 Name korrigiert
                               0 );
                    }
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
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - power off" );  # CD 0097
                    IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
                    delete($hash->{helper}{ttspoweroffafterstop});
                }
                # CD 0030 end
                # CD 0031 Lautstärke zurücksetzen
                if(defined($hash->{helper}{ttsRestoreVolumeAfterStop})) {
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - restore volume after stop" );  # CD 0097
                    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".SB_PLAYER_FHEM2LMSVolume($hash, $hash->{helper}{ttsRestoreVolumeAfterStop})."\n" ); # CD 0065 SB_PLAYER_FHEM2LMSVolume
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
    # CD 0065 start
    } elsif( $cmd eq "songinfo" ) {
        my $trackid=0;
        my $title="";
        my $artist="";
        my $album="";
        my $flush=0;

        #Log3( $hash, 3, "SB_PLAYER_Parse: $name: parsing songinfo: $msg" );  # CD 0072
        $hash->{helper}{songinfopending}--;     # CD 0084
        
        foreach( @args ) {
            $flush=0;
            if( $_ =~ /^(id:)(-?[0-9]*)/ ) {
                $trackid=$2;
                # bereits bekannt -> abbrechen
                if(defined($hash->{helper}{playlistInfo}{$2}) && ($trackid>0)) {
                    last;
                }
                if ($trackid<0) {
                    $hash->{helper}{playlistInfo}{$trackid}{artist}=ReadingsVal($name,'currentArtist','-');
                    $hash->{helper}{playlistInfo}{$trackid}{title}=ReadingsVal($name,'currentTitle','-');
                } else {
                    $hash->{helper}{playlistInfo}{$trackid}{artist}='-';
                    $hash->{helper}{playlistInfo}{$trackid}{title}='no data';
                }
                $hash->{helper}{playlistInfo}{$trackid}{album}='-';
                $hash->{helper}{playlistInfo}{$trackid}{coverid}=0;
                $hash->{helper}{playlistInfo}{$trackid}{duration}=0;
                $hash->{helper}{playlistInfo}{$trackid}{tracknum}=0;
                $hash->{helper}{playlistInfo}{$trackid}{url}='-';
                $hash->{helper}{playlistInfo}{$trackid}{artwork_url}="-" unless(defined($hash->{helper}{playlistInfo}{$trackid}{artwork_url})); # CD 0068
                next;
            } elsif( $_ =~ /^(title:)(.*)/ ) {
                $title=$2;
                $flush=6;
            } elsif( $_ =~ /^(artist:)(.*)/ ) {
                $artist=$2;
                $flush=5;
            } elsif( $_ =~ /^(coverid:)(.*)/ ) {
                $hash->{helper}{playlistInfo}{$trackid}{coverid}=$2;
                $flush=7;
            } elsif( $_ =~ /^(remote:)(.*)/ ) {
                $hash->{helper}{playlistInfo}{$trackid}{remote}=1;
                $flush=7;
            } elsif( $_ =~ /^(duration:)(.*)/ ) {
                $hash->{helper}{playlistInfo}{$trackid}{duration}=$2;
                $flush=7;
            } elsif( $_ =~ /^(tracknum:)(.*)/ ) {
                $hash->{helper}{playlistInfo}{$trackid}{tracknum}=$2;
                $flush=7;
            } elsif( $_ =~ /^(album:)(.*)/ ) {
                $album=$2;
                $flush=3;
            } elsif( $_ =~ /^(url:)(.*)/ ) {
                $hash->{helper}{playlistInfo}{$trackid}{url}=$2;
                $flush=7;
#            } elsif( $_ =~ /^(artwork_url:)(http.*)/ ) {
            } elsif( $_ =~ /^(artwork_url:)(.*)/ ) {    # CD 0097 urls beginnen nicht immmer mit http://
                my $url=$2;
                # url beginnt mit http -> direkt übernehmen
                if($url =~ /^http.*/) {
                    $hash->{helper}{playlistInfo}{$trackid}{artwork_url}=$url;
                } elsif ($url =~ /^\/imageproxy.*/) {
                    # url beginnt mit /imageproxy -> Adresse vom Server hinzufügen
                    $hash->{helper}{playlistInfo}{$trackid}{artwork_url}="http://" . $hash->{SBSERVER} . $url;
                } else {
                    # ...
                    # CD 0098 / einfügen wenn URL nicht mit / beginnt
                    if ($url =~ /^\//) {
                        $hash->{helper}{playlistInfo}{$trackid}{artwork_url}="http://" . $hash->{SBSERVER} . $url;
                    } else {
                        $hash->{helper}{playlistInfo}{$trackid}{artwork_url}="http://" . $hash->{SBSERVER} . '/' . $url;
                    }
                }
                $flush=7;
            } elsif( $_ =~ /^(.*:)(.*)/ ) {
                $flush=7;
            } else {
                $title.=" ".$_ if($title ne "");
                $album.=" ".$_ if($album ne "");
                $artist.=" ".$_ if($artist ne "");
                next;
            }
            if(($flush&1)&&($title ne "")) {
                $hash->{helper}{playlistInfo}{$trackid}{title}=$title;
                $title="";
            }
            if(($flush&2)&&($artist ne "")) {
                $hash->{helper}{playlistInfo}{$trackid}{artist}=$artist;
                $artist="";
            }
            if(($flush&4)&&($album ne "")) {
                $hash->{helper}{playlistInfo}{$trackid}{album}=$album;
                $album="";
            }
        }
        $hash->{helper}{playlistInfo}{$trackid}{title}=$title if($title ne "");
        $hash->{helper}{playlistInfo}{$trackid}{artist}=$artist if($artist ne "");
        $hash->{helper}{playlistInfo}{$trackid}{album}=$album if($album ne "");
        # TEST
        #   if (rand() > 0.4) {delete $hash->{helper}{playlistInfo}{$trackid}};
        # TEST
    } elsif( $cmd eq "FHEMupdatePlaylistInfoDone" ) {
        $hash->{helper}{songinfopending}=0;     # CD 0084
        RemoveInternalTimer( "ftuiMedialist:$name");    # CD 0085
        InternalTimer( gettimeofday() + 0.01,           # CD 0085
           "SB_PLAYER_tcb_ftuiMedialist",
           "ftuiMedialist:$name",
           0 );
    # CD 0065 end
    # CD 0089 start
    } elsif( $cmd eq "sleep" ) {
        $hash->{WILLSLEEPIN} = int($args[0])." secs" if defined($args[ 0 ]);
    # CD 0089 end
    } elsif( $cmd eq "NONE" ) {
        # we shall never end up here, as cmd=NONE is used by the server for
        # autocreate

    } else {
        # unknown command, we push it to the last command thingy
        readingsBulkUpdate( $hash, "lastunknowncmd",
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

# CD 0085
# ----------------------------------------------------------------------------
#  delay building ftuiMedialist reading
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_ftuiMedialist( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    if(defined($hash->{helper}{ftuiSupport}{medialist})) {
        my $t31=time;
        readingsBeginUpdate( $hash );
        if((time-$t31)>0.5) {
            Log3($hash,3,"SB_PLAYER_tcb_ftuiMedialist($name), time:".int((time-$t31)*1000)."ms cmd: prepare FHEM event handling");
        }
        $t31=time;
        SB_PLAYER_ftuiMedialist($hash);
        if((time-$t31)>0.5) {
            Log3($hash,3,"SB_PLAYER_tcb_ftuiMedialist($name), time:".int((time-$t31)*1000)."ms cmd: SB_PLAYER_ftuiMedialist");
        }
        $t31=time;
        if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
            readingsEndUpdate( $hash, 0 );
        } else {
            readingsEndUpdate( $hash, 1 );
        }
        if((time-$t31)>0.5) {
            Log3($hash,3,"SB_PLAYER_tcb_ftuiMedialist($name), time:".int((time-$t31)*1000)."ms cmd: execute FHEM event handling");
        }
    }
}

# CD 0082
# ----------------------------------------------------------------------------
#  build ftuiMedialist reading
# ----------------------------------------------------------------------------
sub SB_PLAYER_ftuiMedialist($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

    my $wait=1;
    my $trackcounter=1; # CD 0082
    my $coverbase="http://" . $hash->{SBSERVER} . "/music/";

    return unless defined($hash->{helper}{playlistIds});    # CD 0082
    
    my @ids=split(',',$hash->{helper}{playlistIds});
    my $ftuimedialist="[";
    # [ {"Artist":"abc", "Title":"def", "Album":"yxz", "Time":"123", "File":"spotify:track:123456", "Track":"1", "Cover":"https://...." }, {"Artist":"abc", ... ]
    $hash->{helper}{playlistInfoRetries}--; # CD 0076
    foreach(@ids) {
        if(defined($hash->{helper}{playlistInfo}{$_})) {
            # CD 0082 Artist von Remote-Streams ersetzen
            if(($_<0)&&(ReadingsVal($name,'playlistCurrentTrack',0) eq $trackcounter)) {
                $hash->{helper}{playlistInfo}{$_}{artist}=ReadingsVal($name,'currentArtist',$hash->{helper}{playlistInfo}{$_}{artist});
            }
            if(($_<0)&&(ReadingsVal($name,'playlistCurrentTrack',0) eq $trackcounter)) {
                $hash->{helper}{playlistInfo}{$_}{title}=ReadingsVal($name,'currentTitle',$hash->{helper}{playlistInfo}{$_}{title});
            }

            $hash->{helper}{playlistInfo}{$_}{artist}=~s/\"//g;
            $hash->{helper}{playlistInfo}{$_}{title}=~s/\"//g;
            $hash->{helper}{playlistInfo}{$_}{album}=~s/\"//g;
            $hash->{helper}{playlistInfo}{$_}{artist} =~ s{\\}{\\\\}g;  # CD 0081
            $hash->{helper}{playlistInfo}{$_}{title} =~ s{\\}{\\\\}g;   # CD 0081
            $hash->{helper}{playlistInfo}{$_}{album} =~ s{\\}{\\\\}g;   # CD 0081
            $ftuimedialist.="{\"Artist\":\"".$hash->{helper}{playlistInfo}{$_}{artist}."\",";
            $ftuimedialist.="\"Title\":\"".$hash->{helper}{playlistInfo}{$_}{title}."\",";
            $ftuimedialist.="\"Album\":\"".$hash->{helper}{playlistInfo}{$_}{album}."\",";
            $ftuimedialist.="\"Time\":\"".(int($hash->{helper}{playlistInfo}{$_}{duration}))."\",";
            $ftuimedialist.="\"File\":\"".$hash->{helper}{playlistInfo}{$_}{url}."\",";
            $ftuimedialist.="\"Track\":\"".$hash->{helper}{playlistInfo}{$_}{tracknum}."\",";
            if(defined($hash->{helper}{playlistInfo}{$_}{artwork_url}) && ($hash->{helper}{playlistInfo}{$_}{artwork_url} ne "-")) {
                $ftuimedialist.="\"Cover\":\"".$hash->{helper}{playlistInfo}{$_}{artwork_url}."\"},";
            } else {
                # CD 0082 versuchen Cover von Remote-Streams zu ersetzen
                if(($_<0)&&(ReadingsVal($name,'playlistCurrentTrack',0) eq $trackcounter) && (ReadingsVal($name,'coverarturl','x')!~/radio\.png/)) {
                    $ftuimedialist.="\"Cover\":\"".ReadingsVal($name,'coverarturl',$coverbase.$hash->{helper}{playlistInfo}{$_}{coverid}."/cover_50x50_o").'"},';
                } else {
                # CD 0082 end
                    $ftuimedialist.="\"Cover\":\"".$coverbase.$hash->{helper}{playlistInfo}{$_}{coverid}."/cover_50x50_o\"},";
                }
            }
        } else {
            $ftuimedialist.="{\"Artist\":\"-\",";
            if($hash->{helper}{playlistInfoRetries}>0) {    # CD 0076
                SB_PLAYER_SonginfoAddQueue($hash,$_,$wait) unless ($_==0);   # CD 0072 # CD 0076
                $wait=0;
                # CD 0084 start
                if(ReadingsVal($name,'playlistTracks',0) eq '0') {
                    $ftuimedialist.="\"Title\":\"-\",";
                } else {
                # CD 0084 end
                    $ftuimedialist.="\"Title\":\"loading...\",";
                }
            } else {
                $ftuimedialist.="\"Title\":\"no data\",";   # CD 0076
                Log3( $hash, 4, "SB_PLAYER_Parse: $name: no songinfo for id $_" );  # CD 0072
            }
            $ftuimedialist.="\"Album\":\"-\",";
            $ftuimedialist.="\"Time\":\"0\",";
            $ftuimedialist.="\"File\":\"-\",";
            $ftuimedialist.="\"Track\":\"0\",";
            $ftuimedialist.="\"Cover\":\"-\"},";
        }
        $trackcounter+=1;   # CD 0082
    }
    $ftuimedialist=~s/,$/]/;
    readingsBulkUpdate( $hash, "ftuiMedialist", $ftuimedialist );
}
# CD 0082 end

# CD 0054
# ----------------------------------------------------------------------------
#  check if value is in 'event-on-change-reading' list
# ----------------------------------------------------------------------------
sub SB_PLAYER_check_eocr($$) {
    my ($hash,$reading) = @_;
    my $name = $hash->{NAME};

    my $attreocr = $hash->{".attreocr"};

    # determine whether the reading is listed in any of the attributes
    my $eocr = $attreocr &&
               ( my @eocrv = grep { my $l = $_; $l =~ s/:.*//;
                   ($reading=~ m/^$l$/) ? $_ : undef} @{$attreocr});

    return !($attreocr) || ($eocr);
}

# CD 0030
# ----------------------------------------------------------------------------
#  delay TTS
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TTSDelay( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    SB_PLAYER_SetTTSState($hash,TTS_WAITFORPLAY,0,0);
    IOWrite( $hash, "$hash->{PLAYERMAC} play\n" );
    # CD 0038 Timeout hinzugefügt
    RemoveInternalTimer( "TimeoutTTSWaitForPlay:$name");
    InternalTimer( gettimeofday() + 10.00,
       "SB_PLAYER_tcb_TimeoutTTSWaitForPlay",
       "TimeoutTTSWaitForPlay:$name",
       0 );
    # CD 0038 end
}
# CD 0030

# CD 0038
# ----------------------------------------------------------------------------
#  TTS 'wait for play' timeout
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TimeoutTTSWaitForPlay( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    if($hash->{helper}{ttsstate}==TTS_WAITFORPLAY) {
      Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - timeout waiting for play" );  # CD 0097
      readingsBeginUpdate( $hash );
      SB_PLAYER_TTSStopped($hash);
      if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
          readingsEndUpdate( $hash, 0 );
      } else {
          readingsEndUpdate( $hash, 1 );
      }
    }
}

# ----------------------------------------------------------------------------
#  TTS 'wait for power on' timeout
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TimeoutTTSWaitForPowerOn( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    if($hash->{helper}{ttsstate}==TTS_WAITFORPOWERON) {
        Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - timeout waiting for power on" );  # CD 0097
        SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,0);
    }
}
# CD 0038

# CD 0034
# ----------------------------------------------------------------------------
#  delay ttsstopped
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TTSStopped( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    readingsBeginUpdate( $hash );

    SB_PLAYER_TTSStopped($hash);

    if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
        readingsEndUpdate( $hash, 0 );
    } else {
        readingsEndUpdate( $hash, 1 );
    }
}
# CD 0034 end

# CD 0042
# ----------------------------------------------------------------------------
#  start tts after power on, wait if startup is not complete
# ----------------------------------------------------------------------------
sub SB_PLAYER_tcb_TTSStartAfterPowerOn( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    if(($hash->{helper}{playerStatusOK}==1)||($hash->{helper}{playerStatusOKCounter}>10)) {
        SB_PLAYER_PrepareTalk($hash);
        SB_PLAYER_LoadTalk($hash);
    } else {
        InternalTimer( gettimeofday() + 1,
           "SB_PLAYER_tcb_TTSStartAfterPowerOn",
           "TTSStartAfterPowerOn:$name",
           0 );
        $hash->{helper}{playerStatusOKCounter}++;
    }
}
# CD 0042 end

# ----------------------------------------------------------------------------
#  called when talk is stopped, check if there are queued elements
# ----------------------------------------------------------------------------
sub SB_PLAYER_TTSStopped($) {
    # readingsBulkUpdate muss aktiv sein
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

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

    SB_PLAYER_RemoveInternalTimers( $hash );

    # to be reviewed if that works.
    # check for uc()
    # what is $hash->{DEF}?
    delete $modules{SB_PLAYER}{defptr}{$hash->{FHEMUID}};   # CD 0071 uc($hash->{DEF}) durch $hash->{FHEMUID} ersetzt

    return( undef );
}

# ----------------------------------------------------------------------------
#  Shutdown function - called before fhem shuts down
# ----------------------------------------------------------------------------
sub SB_PLAYER_Shutdown( $$ ) {
    my ($hash, $dev) = @_;

    SB_PLAYER_RemoveInternalTimers( $hash );

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

    return if(IsDisabled($name));   # CD 0091

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
            "volume " . $hash->{FAVSET} . " savedStates alarmPlaylists";    # CD 0045 alarmPlaylists hinzugefügt
        return( $res );

    } elsif( ( $cmd eq "volume" ) || ( $cmd eq "volumeStraight" ) ) {
        return( scalar( ReadingsVal( "$name", "volumeStraight", 25 ) ) );

    } elsif( $cmd eq $hash->{FAVSET} ) {
        return( "$hash->{FAVSELECT}" );

    # CD 0036 start
    } elsif( $cmd eq 'savedStates' ) {
      my $out="";
      if (defined($hash->{helper}{savedPlayerState})) {
        foreach my $pl ( keys %{$hash->{helper}{savedPlayerState}} ) {
          $out.=$pl."\n" unless ($pl=~/xxTTSxx/);
        }
      }
      return( $out );
    # CD 0036 end
    # CD 0045 start
    } elsif( $cmd eq 'alarmPlaylists' ) {
        my $out="";
        if (defined($hash->{helper}{alarmPlaylists})) {
            foreach my $e ( keys %{$hash->{helper}{alarmPlaylists}} ) {
                $out.=$hash->{helper}{alarmPlaylists}{$e}{title}."\n";
            }
        }
        return( $out );
    # CD 0045 end
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

    return if(IsDisabled($name));   # CD 0091

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
  
    return "" if(IsDisabled($name)); # CD 0091 Return without any further action if the module is disabled 
    
    if ($dev_hash->{NAME} eq "global" && grep (m/^INITIALIZED$|^REREADCFG$/,@{$dev_hash->{CHANGED}})){
        # CD 0077 unbenutzte Attribute entfernen
        $modules{$hash->{TYPE}}{AttrList} =~ s/serverautoon.//;
        $modules{$hash->{TYPE}}{AttrList} =~ s/idismac.//;
        # CD 0084
        InternalTimer( gettimeofday() + 1.0,
           "SB_PLAYER_tcb_SonginfoHandleQueue",
           "SonginfoHandleQueue:$name",
           0 );
    }

    # CD 0036 start
    if( grep(m/^SAVE$|^SHUTDOWN$/, @{$dev_hash->{CHANGED}}) ) { # CD 0043 auch bei SHUTDOWN speichern
        # CD 0077 unbenutzte Attribute entfernen
        delete($attr{$name}{serverautoon}) if(defined( $attr{$name}{serverautoon}));
        delete($attr{$name}{idismac}) if(defined( $attr{$name}{idismac}));
        
        SB_PLAYER_SavePlayerStates($hash) if($SB_PLAYER_hasDataDumper==1);
    }
    # CD 0036 end

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

    Log3( $hash, 5, "SB_PLAYER_Set: called with $cmd");

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
            "save " . # CD 0014 # CD 0036 removed :noArg
            "volume:slider,0,1,100 " .
            "volumeStraight:slider,0,1,100 " .
            "volumeUp:noArg volumeDown:noArg " .
            "mute:noArg repeat:off,one,all show statusRequest:noArg " .
            "shuffle:off,song,album next:noArg prev:noArg playlist sleep " . # CD 0017 song und album hinzugefügt # CD 0052 shuffle on entfernt
            "allalarms:enable,disable,statusRequest,delete,add " .              # CD 0015 alarm1 alarm2 entfernt
            "alarmsSnooze:slider,0,1,30 alarmsTimeout:slider,0,5,90  alarmsDefaultVolume:slider,0,1,100 alarmsFadeIn:on,off alarmsEnabled:on,off " . # CD 0016, von MM übernommen, Namen geändert
            "alarmsFadeSeconds " .      # CD 0082 hinzugefügt
            "cliraw talk sayText " .    # CD 0014 sayText hinzugefügt
            "unsync:noArg " .
            "currentTrackPosition " .   # CD 0047 hinzugefügt
            "snooze:noArg " .           # CD 0052 hinzugefügt
            "resetTTS:noArg " .         # CD 0028 hinzugefügt
            "updateFTUImedialist:noArg " .  # CD 0065 hinzugefügt
            "clearFTUIcache:noArg " .   # CD 0065 hinzugefügt
            "track " .                  # CD 0065 hinzugefügt
            "tracknumber ";             # CD 0072 hinzugefügt
        # add the favorites
        $res .= $hash->{FAVSET} . ":-," . $hash->{FAVSTR} . " ";    # CD 0014 '-' hinzugefügt
        # add the syncmasters
        $res .= "sync:" . $hash->{SYNCMASTERS} . " ";
        # add the playlists
        $res .= "playlists:-," . $hash->{SERVERPLAYLISTS} . " ";    # CD 0014 '-' hinzugefügt
        # add player saved lists      # CD 0036
        my $out="";
        if (defined($hash->{helper}{savedPlayerState})) {
          foreach my $pl ( keys %{$hash->{helper}{savedPlayerState}} ) {
            $out.=$pl."," unless (($pl=~/xxTTSxx/)||($pl=~/^xxx_sss_.*/));  # CD 0061 xxx_sss_ hinzugefügt
          }
          $out=~s/,$//;
        }
        $res .= "recall:$out ";
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

    return if(IsDisabled($name));   # CD 0091

    # CD 0038 Befehle ignorieren wenn Player nicht vorhanden ist
    # CD 0040 wieder deaktiviert
    # if(ReadingsVal($name,"presence","x") ne "present") {
        # return "$name: player is not available";
    # }
    # CD 0038 end

    my $updateReadingsOnSet=AttrVal($name, "updateReadingsOnSet", false);           # CD 0017
    my $donotnotify=AttrVal($name, "donotnotify", "true");                          # CD 0017 # CD 0028 added "

    # as we have some other command, we need to turn on the server
    #if( AttrVal( $name, "serverautoon", "true" ) eq "true" ) {
       #SB_PLAYER_ServerTurnOn( $hash );
    #}

    if( ( $cmd eq "Stop" ) || ( $cmd eq "STOP" ) || ( $cmd eq "stop" ) ) {
        IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );

    } elsif( ( $cmd eq "Play" ) || ( $cmd eq "PLAY" ) || ( $cmd eq "play" ) ) {
        my @secbuf = split(',',AttrVal( $name, "fadeinsecs", '10,10' )); # CD 0050 split hinzugefügt
        $secbuf[1]=$secbuf[0] if (@secbuf==1);  # CD 0051
        # CD 0030 wait until power on
        if(ReadingsVal($name,"power","x") eq "on") {
            # CD 0051 2. Wert von fadeinsecs bei pause -> play verwenden
            if (ReadingsVal($name,"playStatus","?") eq 'paused') {
              IOWrite( $hash, "$hash->{PLAYERMAC} play ".$secbuf[1]."\n" );
            } else {
              IOWrite( $hash, "$hash->{PLAYERMAC} play ".$secbuf[0]."\n" );
            }
        } else {
            $hash->{helper}{playAfterPowerOn}=$secbuf[0];
            IOWrite( $hash, "$hash->{PLAYERMAC} power 1\n" );
        }
        # CD 0030 end
    } elsif( ( $cmd eq "Pause" ) || ( $cmd eq "PAUSE" ) || ( $cmd eq "pause" ) ) {
        my @secbuf = split(',',AttrVal( $name, "fadeinsecs", '10,10' )); # CD 0050 split hinzugefügt
        $secbuf[1]=$secbuf[0] if (@secbuf==1);  # CD 0050
        if( @arg == 1 ) {
            if( $arg[ 0 ] eq "1" ) {
                # pause the player
                IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
            } else {
                # unpause the player
                IOWrite( $hash, "$hash->{PLAYERMAC} pause 0 ".$secbuf[1]."\n" );
            }
        } else {
        # IOWrite( $hash, "$hash->{PLAYERMAC} pause $secbuf\n" ); # CD 0050 deaktiviert, funktioniert so nicht, wenn $secbuf verwendet wird muss 0 oder 1 davorstehen
        # CD 0050 start
          if (ReadingsVal($name,"playStatus","?") eq 'playing') {
            IOWrite( $hash, "$hash->{PLAYERMAC} pause 1\n" );
          } else {
            IOWrite( $hash, "$hash->{PLAYERMAC} pause 0 ".$secbuf[1]."\n" );
          }
        # CD 0050 end
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
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".SB_PLAYER_FHEM2LMSVolume($hash, $arg[ 0 ])."\n" );  # CD 0065 SB_PLAYER_FHEM2LMSVolume
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,$arg[0],1) if (!defined($arg[1]));
        } else {
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume " .
                     SB_PLAYER_FHEM2LMSVolume($hash, AttrVal( $name, "volumeLimit", 50 )) . "\n" );  # CD 0065 SB_PLAYER_FHEM2LMSVolume
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,AttrVal( $name, "volumeLimit", 50 ),1) if (!defined($arg[1]));
        }

    } elsif( $cmd eq $hash->{FAVSET} ) {
        if ($arg[0] ne '-') {       # CD 0014
            if( defined( $hash->{helper}{SB_PLAYER_Favs}{$arg[0]}{ID} ) ) {
                my $fid = $hash->{helper}{SB_PLAYER_Favs}{$arg[0]}{ID};

                if($hash->{helper}{SB_PLAYER_Favs}{$arg[0]}{SOURCE} eq 'LMS') {    # CD 0070
                    IOWrite( $hash, "$hash->{PLAYERMAC} favorites playlist " .
                             "play item_id:$fid\n" );
                } else {
                    IOWrite( $hash, "$hash->{PLAYERMAC} $hash->{helper}{SB_PLAYER_Favs}{$arg[0]}{SOURCE} playlist play " .
                             "item_id:$fid\n" );
                }
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
            #SB_PLAYER_SetSyncedVolume($hash,$volstr); # CD 0065 deaktiviert, auf Rückmeldung warten
        } else {
            IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume " .
                     SB_PLAYER_FHEM2LMSVolume($hash, AttrVal( $name, "volumeLimit", 50 )) . "\n" );    # CD 0065 SB_PLAYER_FHEM2LMSVolume
            # CD 0007
            SB_PLAYER_SetSyncedVolume($hash,AttrVal( $name, "volumeLimit", 50 ),1);
        }

    } elsif( ( $cmd eq "volumeDown" ) || ( $cmd eq "VOLUMEDOWN" ) ||
             ( $cmd eq "VolumeDown" ) ) {
        my $volstr = sprintf( "-%02d", AttrVal( $name, "volumeStep", 10 ) );
        IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume $volstr\n" );
        # CD 0007
        #SB_PLAYER_SetSyncedVolume($hash,$volstr); # CD 0065 deaktiviert, auf Rückmeldung warten
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
                if(defined($ttshash->{TYPE}) && (($ttshash->{TYPE} eq 'Text2SpeechSB') || (($ttshash->{TYPE} eq 'Text2Speech') && defined($ttshash->{helper}{supportsSBPlayer})))) {    # CD 0048 Text2Speech (ohne SB) unterstützen
                    if(defined($ttshash->{ALSADEVICE}) && ($ttshash->{ALSADEVICE} eq 'SB_PLAYER')) {
                        if ((AttrVal($ttshash->{NAME}, "TTS_Ressource", "x") =~ m/^(Google|VoiceRSS|SVOX-pico)$/)) { # CD 0049 $ttshash korrigiert
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
                            $errMsg = "SB_PLAYER_Set: ".$extTTS[1].": Text2Speech uses unsupported TTS_Ressource ".AttrVal($ttshash->{NAME}, "TTS_Ressource", "x");   # CD 0049 $ttshash korrigiert
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
        my $filename; # CD 0038

        if (length($ttstext)>0) {
            $ttstext=~s/\|\|/\| \|/g;    # CD 0091
            my @words=split(' ',$ttstext);
            for my $w (@words) {
                # CD 0033 Datei ?, teilweise aus 00_SONOS übernommen
                if ($w =~ m/\|(.*)\|/) {
                    push(@textlines,$tl) if($tl ne '');
                    $tl='';

                    $filename = $1;
                    # CD 0089 kein Dateiname sondern Optionen/Befehle
                    if($filename=~/^opt:(.*)/) {
                    
                    } else {
                        $filename = $targetSpeakMP3FileDir.'/'.$filename if ($filename !~ m/^(\/|[a-z]:)/i);
                        $filename = $filename.'.mp3' if ($filename !~ m/\.mp3$/i);
                    }
                    push(@textlines, '|'.$filename.'|');
                    $filename=undef;
                # CD 0038 Leerzeichen in Dateinamen zulassen
                } elsif ($w =~ m/^\|(.*)/) {
                    $filename = $1;
                } elsif (($w =~ m/(.*)\|/) && defined($filename)) {
                    $filename .= " ".$1;

                    push(@textlines,$tl) if($tl ne '');
                    $tl='';

                    # CD 0089 kein Dateiname sondern Optionen/Befehle
                    if($filename=~/^opt:(.*)/) {
                    
                    } else {
                        $filename = $targetSpeakMP3FileDir.'/'.$filename if ($filename !~ m/^(\/|[a-z]:)/i);
                        $filename = $filename.'.mp3' if ($filename !~ m/\.mp3$/i);
                    }
                    push(@textlines, '|'.$filename.'|');
                    $filename=undef;
                # CD 0038
                } else {
                    $w =~ s/[\\|*~<>^\n\(\)\[\]\{\}[:cntrl:]]/ /g;
                    $w =~ s/\s+/ /g;
                    $w =~ s/^\s|\s$//g;
                    $w =~ s/($Sonderzeichenkeys)/$Sonderzeichen{$1}/g if(AttrVal( $name, "ttslink", "x" ) !~ m/voicerss/i);    # CD 0045 Sonderzeichen für VoiceRSS nicht ersetzen
                    $w = uri_escape( $w ) if defined($hash->{helper}{ttsOptions}{doubleescape});  # CD 0060
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
            # CD 0091 start
            delete($hash->{helper}{ttsActiveOptions}) if defined($hash->{helper}{ttsActiveOptions});
            $hash->{helper}{ttsActiveOptions}{nosaverestore}=$hash->{helper}{ttsOptions}{nosaverestore} if defined($hash->{helper}{ttsOptions}{nosaverestore});
            $hash->{helper}{ttsActiveOptions}{forcegroupon}=$hash->{helper}{ttsOptions}{forcegroupon} if defined($hash->{helper}{ttsOptions}{forcegroupon});
            $hash->{helper}{ttsActiveOptions}{ignorevolumelimit}=$hash->{helper}{ttsOptions}{ignorevolumelimit} if defined($hash->{helper}{ttsOptions}{ignorevolumelimit});
            $hash->{helper}{ttsActiveOptions}{eventondone}=$hash->{helper}{ttsOptions}{eventondone} if defined($hash->{helper}{ttsOptions}{eventondone});
            $hash->{helper}{ttsActiveOptions}{ttslanguage}=AttrVal( $name, "ttslanguage", "de" );
            $hash->{helper}{ttsActiveOptions}{volume}=ReadingsVal($name,'volume',50);
            for my $outstr (@textlines) {
                if (($outstr eq '|opt:nosaverestore|')||($outstr eq '|opt:nosaverestore=1|')) {
                    $hash->{helper}{ttsActiveOptions}{nosaverestore}=1;
                }
                if (($outstr eq '|opt:forcegroupon|')||($outstr eq '|opt:forcegroupon=1|')) {
                    $hash->{helper}{ttsActiveOptions}{forcegroupon}=1;
                }
                if (($outstr eq '|opt:ignorevolumelimit|')||($outstr eq '|opt:ignorevolumelimit=1|')) {
                    $hash->{helper}{ttsActiveOptions}{ignorevolumelimit}=1;
                }
                if (($outstr eq '|opt:eventondone|')||($outstr eq '|opt:eventondone=1|')) {
                    $hash->{helper}{ttsActiveOptions}{eventondone}=1;
                }
                if ($outstr eq '|opt:nosaverestore=0|') {
                    delete($hash->{helper}{ttsActiveOptions}{nosaverestore}) if defined($hash->{helper}{ttsActiveOptions}{nosaverestore});
                }
                if ($outstr eq '|opt:forcegroupon=0|') {
                    delete($hash->{helper}{ttsActiveOptions}{forcegroupon}) if defined($hash->{helper}{ttsActiveOptions}{forcegroupon});
                }
                if ($outstr eq '|opt:ignorevolumelimit=0|') {
                    delete($hash->{helper}{ttsActiveOptions}{ignorevolumelimit}) if defined($hash->{helper}{ttsActiveOptions}{ignorevolumelimit});
                }
                if ($outstr eq '|opt:eventondone=0|') {
                    delete($hash->{helper}{ttsActiveOptions}{eventondone}) if defined($hash->{helper}{ttsActiveOptions}{eventondone});
                }
            }
            # CD 0091 end
            
            SB_PLAYER_TTSLogPlayerState($hash, 'not active, starting...'); # CD 0097 Zustand aller Player ausgeben
            
            # talk ist nicht aktiv
            # CD 0038 Player zuerst einschalten
            if(ReadingsVal($name,"power","x") ne "on") {
                SB_PLAYER_SetTTSState($hash,TTS_WAITFORPOWERON,0,0);
                RemoveInternalTimer( "TimeoutTTSWaitForPowerOn:$name");
                if($hash->{helper}{playerStatusOK}==1) {    # CD 0042
                    IOWrite( $hash, "$hash->{PLAYERMAC} power 1\n" );
                    InternalTimer( gettimeofday() + 5.00,
                       "SB_PLAYER_tcb_TimeoutTTSWaitForPowerOn",
                       "TimeoutTTSWaitForPowerOn:$name",
                       0 );
                    $hash->{helper}{ttsPowerWasOff}=1;
                # CD 0042 start
                } else {
                    InternalTimer( gettimeofday() + 10.00,
                       "SB_PLAYER_tcb_TimeoutTTSWaitForPowerOn",
                       "TimeoutTTSWaitForPowerOn:$name",
                       0 );
                }
                # CD 0042 end
            } else {
            # CD 0038 end
                SB_PLAYER_PrepareTalk($hash);
            }
        } else {

        }
        my $lang=$hash->{helper}{ttsActiveOptions}{ttslanguage};
        for my $outstr (@textlines) {
            if ($outstr =~ m/\|(.*)\|/) {               # CD 0033
                if($1=~m/opt:l=(.*)/) {
                    Log3($hash, defined($hash->{helper}{ttsOptions}{debug})?0:6,"SB_PLAYER_Set: $name: changing tts language to $1");
                    $lang=$1;
                    $hash->{helper}{ttsActiveOptions}{ttslanguage}=$1;
                } elsif($1 eq 'opt:replace') {
                    # CD 0091 wenn tts abgespielt wird, Playlist löschen, SB_PLAYER_LoadTalk kümmert sich um den Rest
                    if((($hash->{helper}{ttsstate}>=TTS_DELAY) && ($hash->{helper}{ttsstate}<=TTS_PLAYING))||($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE)) {
                        Log3($hash, defined($hash->{helper}{ttsOptions}{debug})?0:6,"SB_PLAYER_Set: $name: replacing active tts");
                        IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n" );
                    }
                    # Queue löschen
                    delete($hash->{helper}{ttsqueue}) if defined($hash->{helper}{ttsqueue});
                } else {
                    Log3($hash, defined($hash->{helper}{ttsOptions}{debug})?0:6,"SB_PLAYER_Set: $name: add to ttsqueue: $1"); # CD 0036
                    push(@{$hash->{helper}{ttsqueue}},uri_escape(decode('utf-8',$1)));  # CD 0033 # CD 0038 uri_escape(decode... hinzugefügt
                }
            } else {
                $outstr =~ s/\s/+/g;

                # CD 0054 versuchen Format zu erraten, funktioniert nicht für telnet
                if (decode("utf8",$outstr)=~m/\x{fffd}/) {
                    Log3($hash, defined($hash->{helper}{ttsOptions}{debug})?0:6,"SB_PLAYER_Set: $name: string is not utf-8, using iso-8859-1");
                    $outstr=encode('utf-8',decode("iso-8859-1",$outstr));
                }

                $outstr = uri_escape( $outstr );
                #$outstr = uri_escape( $outstr ) if defined($hash->{helper}{ttsOptions}{doubleescape});  # CD 0059 # CD 0060 zu spät nach oben verschoben

                # CD 0045
                my $ttslink=AttrVal( $name, "ttslink", "" );
                if(defined($ttslink)) {
                    # Profile
                    if ($ttslink =~ m/voicerss/i) { # CD 0047 Sprache auch bei voicerss innerhalb der URL anpassen
                        $lang="de-de" if($lang eq "de");
                        $lang="en-us" if($lang eq "en");
                        $lang="fr-fr" if($lang eq "fr");
                    }

                    $ttslink="http://translate.google.com/translate_tts?ie=UTF-8&tl=<LANG>&q=<TEXT>&client=tw-ob" if ($ttslink eq 'http://translate.google.com/translate_tts?ie=UTF-8'); # CD 0047, CD 0048 client=tw-ob verwenden
                    $ttslink="http://translate.google.com/translate_tts?ie=UTF-8&tl=<LANG>&q=<TEXT>&client=tw-ob" if ($ttslink eq "Google");  # CD 0048 client=tw-ob verwenden
                    $ttslink="http://api.voicerss.org/?key=<APIKEY>&src=<TEXT>&hl=<LANG>" if ($ttslink eq "VoiceRSS");

                    # alte Links anpassen
                    if($ttslink !~ m/<TEXT>/) {
                        $ttslink.="&tl=<LANG>" if($ttslink !~ m/<LANG>/);
                        $ttslink.="&q=<TEXT>";
                    }

                    $ttslink =~ s/<LANG>/$lang/;
                    $ttslink =~ s/<TEXT>/$outstr/;

                    my $apikey=AttrVal( $name, "ttsAPIKey", undef );
                    if(($ttslink =~ m/<APIKEY>/) && !defined($apikey)) {
                        Log3($hash, 2,"SB_PLAYER_Set: $name: talk - missing API key");
                        SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,0);
                    } else {
                        $ttslink =~ s/<APIKEY>/$apikey/;

                        Log3($hash, defined($hash->{helper}{ttsOptions}{debug})?0:6,"SB_PLAYER_Set: $name: add to ttsqueue: $ttslink");  # CD 0036
                        push(@{$hash->{helper}{ttsqueue}},$ttslink);
                    }
                }
            }
        }

        SB_PLAYER_LoadTalk($hash) if(($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST)||($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE));  # CD 0033 # CD 0038 auf TTS_LOADPLAYLIST prüfen # CD 0091 auf TTS_SYNCGROUPACTIVE prüfen

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

            Log3( $hash, 5, "SB_PLAYER_Set($name): playlist command = $arg[ 0 ] param = $outstr" );

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
            # CD 0038 start
            } elsif( $arg[ 0 ] eq "add" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist add $outstr\n" );
            } elsif( $arg[ 0 ] eq "insert" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist insert $outstr\n" );
            # CD 0038 end
            } elsif( $arg[ 0 ] eq "year" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " .
                         "track.year:$outstr\n" );
            } elsif( $arg[ 0 ] eq "genre" ) {
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " .
                         "genre.namesearch:$outstr\n" );
            #} elsif( $arg[ 0 ] eq "comment" ) {                                # CD 0014 funktioniert nicht
            #    IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadtracks " .
            #             "comments.value:$outstr\n" );
            # CD 0038 loadalbum wieder hergestellt und überarbeitet
            } else {
                my $genre='*';
                my $album='*';
                my $artist='*';
                my $t=0;
                foreach( @arg ) {
                    if( $_ =~ /^(genre:)(.*)/ ) {
                        $genre=$2;
                        $t=1;
                    } elsif ( $_ =~ /^(album:)(.*)/ ) {
                        $album=$2;
                        $t=2;
                    } elsif ( $_ =~ /^(artist:)(.*)/ ) {
                        $artist=$2;
                        $t=3;
                    } else {
                        $genre.=" ".$_ if($t==1);
                        $album.=" ".$_ if($t==2);
                        $artist.=" ".$_ if($t==3);
                    }
                }
                if( $t>0 ) {
                    $genre=uri_escape(decode('utf-8',$genre)) if($genre ne '*');
                    $album=uri_escape(decode('utf-8',$album)) if($album ne '*');
                    $artist=uri_escape(decode('utf-8',$artist)) if($artist ne '*');
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist loadalbum " .
                             "$genre $artist $album\n" );
                }
            # CD 0038 end
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
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmfadeseconds ?\n" ); # CD 0082
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
        # CD 0082 start
        } elsif($cmd eq "alarmsFadeSeconds") {
            IOWrite( $hash, "$hash->{PLAYERMAC} playerpref alarmfadeseconds ". $arg[0] ."\n" );
            readingsSingleUpdate( $hash, "alarmsFadeSeconds", $arg[ 0 ], $donotnotify ) if($updateReadingsOnSet);
        }
        # CD 0082 end
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
        if(defined($arg[0])) {
          SB_PLAYER_Save($hash, $arg[0]);
        } else {
          SB_PLAYER_Save($hash, "");
        }
    } elsif( ( $cmd eq "recall" ) || ( $cmd eq "RECALL" ) ) {
        if(defined($arg[0])) {
          SB_PLAYER_Recall($hash, join(" ", @arg));
        } else {
          SB_PLAYER_Recall($hash, "");
        }
    # CD 0014 end
    } elsif( $cmd eq "statusRequest" ) {
        RemoveInternalTimer( $hash );
        delete($hash->{helper}{disableGetStatus}) if defined($hash->{helper}{disableGetStatus});    # CD 0079
        SB_PLAYER_GetStatus( $hash );

    } elsif( $cmd eq "sync" ) {
        # CD 0018 wenn der Player bereits in einer Gruppe ist und 'new' ist vorhanden, wird der Player zuerst aus der Gruppe entfernt
        if(( @arg == 2) && ($arg[1] eq "new") && ($hash->{SYNCED} eq 'yes')) {
            IOWrite( $hash, "$hash->{PLAYERMAC} sync -\n" );
            # CD 0028 start
            if($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE) {
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - cancel tts, sync group changed" );  # CD 0097
                SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,0);  # CD 0066 single statt bulk update
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
                my $mac;
                # CD 0018 end
                if( defined( $hash->{helper}{SB_PLAYER_SyncMasters}{$dev} && defined( $hash->{helper}{SB_PLAYER_SyncMasters}{$dev}{MAC} ) )) {   # CD 0094 zuerst auf {$dev} prüfen
                    $mac=$hash->{helper}{SB_PLAYER_SyncMasters}{$dev}{MAC};
                } else {
                    # CD 0038 Player nicht gefunden, testen ob Name zu einem FHEM-Gerät passt
                    if(defined($defs{$dev}) && defined($defs{$dev}{TYPE}) && ($defs{$dev}{TYPE} eq 'SB_PLAYER') && defined($defs{$dev}{PLAYERMAC})) {
                        $mac=$defs{$dev}{PLAYERMAC};
                    } else {
                    # CD 0038 end
                        my $msg = "SB_PLAYER_Set: no MAC for player ".$dev.".";
                        Log3( $hash, 3, $msg );
                        #return( $msg );        # CD 0018 wenn keine MAC vorhanden weitermachen
                    }
                }
                if(defined($mac)) {
                    # CD 0038 wenn asSlave angegeben ist, wird der erste Player zur Gruppe des 2. hinzugefügt
                    if((@arg == 2) && ($arg[1] eq "asSlave")) {
                        IOWrite( $hash, "$mac sync " .
                                 "$hash->{PLAYERMAC}\n" );
                        # CD 0094 nur zum Test
                        Log3( $hash, 2, "SB_PLAYER_Set($name): sync $dev ($mac) <- $name ($hash->{PLAYERMAC})");
                    } else {
                    # CD 0038 end
                        IOWrite( $hash, "$hash->{PLAYERMAC} sync " .
                                 "$mac\n" );
                        # CD 0094 nur zum Test
                        Log3( $hash, 2, "SB_PLAYER_Set($name): sync $dev ($mac) -> $name ($hash->{PLAYERMAC})");
                    }
                    $doGetStatus=1;
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
            Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - cancel tts, sync group changed" );  # CD 0097
            SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,0);  # CD 0066 single statt bulk update
        }
        # CD 0028 end
    } elsif( $cmd eq "playlists" ) {
        if(( @arg == 1 )||( @arg == 2 )) {
            my $msg;
            if( defined( $hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{ID} ) ) {
                if($hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{SOURCE} eq 'LMS') {    # CD 0070
                    $msg = "$hash->{PLAYERMAC} playlistcontrol cmd:load " .
                        "playlist_id:$hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{ID}";
                } else {
                    $msg = "$hash->{PLAYERMAC} $hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{SOURCE} playlist play " .
                        "item_id:$hash->{helper}{SB_PLAYER_Playlists}{$arg[0]}{ID}";
                }
                Log3( $hash, 5, "SB_PLAYER_Set($name): playlists command = " .
                      $msg . " ........  with $arg[0]" );
                IOWrite( $hash, $msg . "\n" );
                # CD 0095 Player auf stop oder pause setzen
                if(defined($arg[1])) {
                    $hash->{helper}{pauseAfterPlay}=1 if($arg[1] eq 'paused');
                    IOWrite( $hash, $hash->{PLAYERMAC} . " stop\n" ) if($arg[1] eq 'stopped');
                }
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
        delete($hash->{helper}{saveLocked}) if (defined($hash->{helper}{saveLocked}));  # CD 0056
        delete $hash->{helper}{sgTalkActive} if defined($hash->{helper}{sgTalkActive}); # CD 0063
        Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - reset tts" );  # CD 0097
        SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
    # CD 0047 start
    } elsif( lc($cmd) eq "currenttrackposition" ) {
        if(defined($arg[0])) {
            IOWrite( $hash, "$hash->{PLAYERMAC} time $arg[0]\n" );
        }
    # CD 0047 end
    # CD 0052 start
    } elsif( lc($cmd) eq "snooze" ) {
        IOWrite( $hash, "$hash->{PLAYERMAC} jivealarm snooze:1\n" );
    # CD 0052 end
    # CD 0065 start
    } elsif( $cmd eq "updateFTUImedialist" ) {
        delete($hash->{SONGINFOQUEUE}) if(defined($hash->{SONGINFOQUEUE})); # CD 0072
        $hash->{helper}{songinfoquery}='';              # CD 0084
        $hash->{helper}{songinfocounter}=0;             # CD 0084
        $hash->{helper}{songinfopending}=0;             # CD 0084

        if(defined($hash->{helper}{ftuiSupport}{medialist})) {
            if(defined($hash->{helper}{playlistIds})) {
                $hash->{helper}{playlistInfoRetries}=5; # CD 0076
                my @ids=split(',',$hash->{helper}{playlistIds});
                foreach(@ids) {
                    # CD 0084 verzögert abfragen, ansonsten Probleme bei schwacher Hardware
                    SB_PLAYER_SonginfoAddQueue($hash,$_,0) unless(defined($hash->{helper}{playlistInfo}{$_}) && !defined($hash->{helper}{playlistInfo}{$_}{remote}) || ($_==0)); # CD 0076 id 0 ignorieren
                }
                SB_PLAYER_SonginfoAddQueue($hash,0,0);
            }
        }
    } elsif( $cmd eq "clearFTUIcache" ) {
        delete $hash->{helper}{playlistInfo} if defined($hash->{helper}{playlistInfo});
    } elsif(( $cmd eq "track" ) || ( $cmd eq "tracknumber" )) {
        if( @arg != 1 ) {
            my $msg = "SB_PLAYER_Set: no arguments for track given.";
            Log3( $hash, 3, $msg );
            return( $msg );
        }
        if($arg[0]=~/^\d+$/) {
            IOWrite( $hash, $hash->{PLAYERMAC}." playlist index ".($arg[0]-1)."\n" );
        } else {
            IOWrite( $hash, $hash->{PLAYERMAC}." playlist index ".$arg[0]."\n" );
        }
    # CD 0065 end
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

    return if(IsDisabled($name));   # CD 0091

    if(defined($hash->{helper}{ttsqueue})) {
        if(($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST)||($hash->{helper}{ttsstate}==TTS_SYNCGROUPACTIVE)) {
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n" ) if($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST);
            my $arr = $hash->{helper}{ttsqueue};
            my $playlistadd=0;
            if(defined($arr)) {
                # CD 0089 Optionen hinzugefügt
                while(@{$arr} > 0) {
                    my $qe=$arr->[0];
                    #Log 0,$qe;
                    if($hash->{helper}{ttsstate}==TTS_LOADPLAYLIST) {
                        if($qe=~/^opt%3A(.*)/) {
                            my @opts=split '=',uri_unescape($1);
                            if(($opts[0] eq 'v') && (@opts==2)) {
                                last if($playlistadd==1);   # wenn bereits Elemente in die Playlist eingefügt wurden warten bis diese abgespielt wurden
                                $opts[1]=AttrVal( $name, "ttsVolume", 100 ) if($opts[1] eq 'tts');  # CD 0091
                                $opts[1]=$hash->{helper}{ttsActiveOptions}{volume} if($opts[1] eq 'music');  # CD 0091
                                SB_PLAYER_SetTTSVolume($hash,$opts[1],0);
                            }
                        } else {
                            # ich steuere talk
                            IOWrite( $hash, "$hash->{PLAYERMAC} playlist add " . $qe . "\n" );
                            $playlistadd=1;
                        }
                    } else {
                        # ein anderer Player steuert talk
                        IOWrite( $hash, $hash->{helper}{ttsMaster}." fhemrelay ttsadd ". $qe ."\n" );
                        $playlistadd=1;
                    }
                    shift(@{$arr});
                }
                delete($hash->{helper}{ttsqueue}) if(@{$arr} == 0);
            }

            if($hash->{helper}{ttsstate}!=TTS_SYNCGROUPACTIVE) {
                # andere Player in Gruppe informieren
                if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
                    my @pl=split(",",$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER});
                    foreach (@pl) {
                        if ($hash->{PLAYERMAC} ne $_) {
                            IOWrite( $hash, "$_ fhemrelay ttsactive ".$hash->{PLAYERMAC}."\n" );
                            IOWrite( $hash, "$_ fhemrelay ttsforcegroupon\n" ) if(defined($hash->{helper}{ttsActiveOptions}{forcegroupon}));  # CD 0030
                        }
                    }
                }
            }
        } else {
            # talk ist aktiv
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

    return if(IsDisabled($name));   # CD 0091

    # talk ist nicht aktiv
    if(!defined($hash->{helper}{ttsActiveOptions}{nosaverestore}) && !defined($hash->{helper}{sgTalkActive})) {   # CD 0063 sgTalkActive hinzugefügt
        SB_PLAYER_SetTTSState($hash,TTS_SAVE,0,0);
        SB_PLAYER_Save( $hash, "xxTTSxx" ) if(!defined($hash->{helper}{saveLocked}));
    }
    $hash->{helper}{saveLocked}=1;
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 0\n" );
    IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n" );
    if(defined($hash->{helper}{ttsVolume})) {
        SB_PLAYER_SetTTSVolume($hash,$hash->{helper}{ttsVolume},1);
    }
    SB_PLAYER_SetTTSState($hash,TTS_LOADPLAYLIST,0,0);
}

# CD 0089 start
sub SB_PLAYER_SetTTSVolume($$$) {
    my ( $hash, $ttsvolume, $changestate ) = @_;
    my $name = $hash->{NAME};

    return unless defined($ttsvolume);
    return if(IsDisabled($name));   # CD 0091
    
    SB_PLAYER_SetTTSState($hash,TTS_SETVOLUME,0,0) if($changestate==1);
    my $vol=$ttsvolume;
    $vol=AttrVal( $name, "volumeLimit", 100 ) if(( $ttsvolume > AttrVal( $name, "volumeLimit", 100 ) )&&!defined($hash->{helper}{ttsActiveOptions}{ignorevolumelimit})); # CD 0031
    IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".SB_PLAYER_FHEM2LMSVolume($hash, $vol)."\n" );   # CD 0065 SB_PLAYER_FHEM2LMSVolume
    SB_PLAYER_SetSyncedVolume($hash,$ttsvolume,1);
}
# CD 0089 end

# CD 0014 start
# ----------------------------------------------------------------------------
#  recall player state
#
#  CD 0036 added $statename
# ----------------------------------------------------------------------------
sub SB_PLAYER_Recall($$) {
    my ( $hash, $arg ) = @_;   # CD 0036
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

    # CD 0036 start
    my $del=0;
    my $delonly=0;
    my $forceoff=0;
    my $forceon=0;
    my $forceplay=0;
    my $forcestop=0;

    my $statename;
    my @args=split " ",$arg;

    if(defined($args[0])) {
      $statename=$args[0];
    } else {
      $statename='default';
    }

    # Optionen auswerten
    for my $opt (@args) {
        $del=1 if($opt=~ m/^del$/);
        $delonly=1 if($opt=~ m/^delonly$/);
        $forceoff=1 if($opt=~ m/^off$/);
        $forceon=1 if(($opt=~ m/^on$/)||($opt=~ m/^play$/));
        $forceplay=1 if($opt=~ m/^play$/);
        $forcestop=1 if($opt=~ m/^stop$/);
    }

    $forceoff=0 if($forceon==1);
    $forcestop=0 if($forceplay==1);

    # CD 0036 end

    # wurde überhaupt etwas gespeichert ?
    if(defined($hash->{helper}{savedPlayerState}) && defined($hash->{helper}{savedPlayerState}{$statename})) {
        if($delonly==0) {
            # CD 0029 start
            if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
                Log3( $hash, 0, "SB_PLAYER_Recall: $name: restoring...");
                $hash->{helper}{ttsOptions}{logloaddone}=1;
                $hash->{helper}{ttsOptions}{logplay}=1;
            }
            # CD 0029 end
            IOWrite( $hash, "$hash->{PLAYERMAC} playlist shuffle 0\n");
            if (defined($hash->{helper}{savedPlayerState}{$statename}{playlistIds})) {
                # wegen Shuffle Playlist neu erzeugen
                # CD 0030 start
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist clear\n");
                my @playlistIds=split(',',$hash->{helper}{savedPlayerState}{$statename}{playlistIds});
                my $f=0; # CD 0048
                for my $id (@playlistIds) {
                    if($id>=0) {
                        IOWrite( $hash, "$hash->{PLAYERMAC} playlistcontrol cmd:add track_id:".$id."\n");
                    } else {
                        if(defined($hash->{helper}{savedPlayerState}{$statename}{playlistUrls}) && defined($hash->{helper}{savedPlayerState}{$statename}{playlistUrls}{$id})) {
                            if (defined($hash->{helper}{savedPlayerState}{$statename}{path}) && ($f==0)) {     # CD 0048
                                IOWrite( $hash, "$hash->{PLAYERMAC} playlist add ".$hash->{helper}{savedPlayerState}{$statename}{path}."\n"); # CD 0048
                            } else {     # CD 0048
                                IOWrite( $hash, "$hash->{PLAYERMAC} playlist add ".$hash->{helper}{savedPlayerState}{$statename}{playlistUrls}{$id}."\n");
                            }    # CD 0048
                        } else {
                            Log3( $hash, 2, "SB_PLAYER_Recall: $name: no url found for id ".$id);
                        }
                    }
                    $f=1;     # CD 0048
                }
                IOWrite( $hash, "$hash->{PLAYERMAC} playlist index ".$hash->{helper}{savedPlayerState}{$statename}{playlistCurrentTrack}."\n");
                # CD 0030 end
            } else {
                # auf dem Server gespeicherte Playlist fortsetzen
                if( $hash->{helper}{savedPlayerState}{$statename}{playStatus} eq "playing" ) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME}_$statename\n" );
                } else {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist resume fhem_$hash->{NAME}_$statename noplay:1\n" );
                }
            }
            if ($hash->{helper}{savedPlayerState}{$statename}{volumeStraight} ne '?') {
                IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ".SB_PLAYER_FHEM2LMSVolume($hash, $hash->{helper}{savedPlayerState}{$statename}{volumeStraight})."\n" ); # CD 0065 SB_PLAYER_FHEM2LMSVolume
                SB_PLAYER_SetSyncedVolume($hash,$hash->{helper}{savedPlayerState}{$statename}{volumeStraight},1);
            }
            if ($hash->{helper}{savedPlayerState}{$statename}{repeat} ne ReadingsVal($name,"repeat","?")) {
                if( $hash->{helper}{savedPlayerState}{$statename}{repeat} eq "off" ) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 0\n" );
                } elsif( $hash->{helper}{savedPlayerState}{$statename}{repeat} eq "one" ) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 1\n" );
                } elsif( $hash->{helper}{savedPlayerState}{$statename}{repeat} eq "all" ) {
                    IOWrite( $hash, "$hash->{PLAYERMAC} playlist repeat 2\n" );
                }
            }
            # CD 0028 start
            if ((($hash->{helper}{savedPlayerState}{$statename}{power} eq "off") && ($forceon!=1))||($forceoff==1)) {  # CD 0036 added $forceon and $forceoff
                Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - stop and power off" );  # CD 0097
                IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );  # CD 0091
                IOWrite( $hash, "$hash->{PLAYERMAC} power 0\n" );
                if($hash->{helper}{ttsstate}==TTS_RESTORE) {
                    SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
                    delete($hash->{helper}{saveLocked}) if (defined($hash->{helper}{saveLocked}));  # CD 0056
                }
            } else {
            # CD 0028 end
                if ((($hash->{helper}{savedPlayerState}{$statename}{playStatus} eq "stopped" ) && ($forceplay!=1))||($forcestop==1)) { # CD 0036 added $forceplay and $forcestop
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - stop" );  # CD 0097
                    IOWrite( $hash, "$hash->{PLAYERMAC} stop\n" );
                    # CD 0028 start
                    if($hash->{helper}{ttsstate}==TTS_RESTORE) {
                        SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
                        delete($hash->{helper}{saveLocked}) if (defined($hash->{helper}{saveLocked}));  # CD 0056
                    }
                    # CD 0028 end
                } elsif(( $hash->{helper}{savedPlayerState}{$statename}{playStatus} eq "playing" )||($forceplay==1)) {  # CD 0036 added $forceplay
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "$name: ttsdebug - play" );  # CD 0097
                    my @secbuf = split(',',AttrVal( $name, "fadeinsecs", '10,10' )); # CD 0050 split hinzugefügt
                    IOWrite( $hash, "$hash->{PLAYERMAC} play ".$secbuf[0]."\n" );
                    IOWrite( $hash, "$hash->{PLAYERMAC} time $hash->{helper}{savedPlayerState}{$statename}{elapsedTime}\n" ) if(defined($hash->{helper}{savedPlayerState}{$statename}{elapsedTime}));
                    # CD 0028 start
                    if($hash->{helper}{ttsstate}==TTS_RESTORE) {
                        SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
                    }
                    # CD 0028 end
                } elsif( $hash->{helper}{savedPlayerState}{$statename}{playStatus} eq "paused" ) {
                    # paused kann nicht aus stop erreicht werden -> Playlist starten und dann pausieren
                    $hash->{helper}{recallPause}=1;
                    $hash->{helper}{recallPending}=1;
                    $hash->{helper}{recallPendingElapsedTime}=$hash->{helper}{savedPlayerState}{$statename}{elapsedTime};   # CD 0047
                }
            }
            # CD 0028 restore names
            readingsSingleUpdate( $hash,"playlists", $hash->{helper}{savedPlayerState}{$statename}{playlist},(AttrVal($name, "donotnotify", "true") eq "true")?0:1) if(defined($hash->{helper}{savedPlayerState}{$statename}{playlist}));
            readingsSingleUpdate( $hash,"favorites", $hash->{helper}{savedPlayerState}{$statename}{favorite},(AttrVal($name, "donotnotify", "true") eq "true")?0:1) if(defined($hash->{helper}{savedPlayerState}{$statename}{favorite}));
        }
        delete($hash->{helper}{savedPlayerState}{$statename}) if(($del==1)||($delonly==1));
    } else {
    # CD 0056 start
        if($hash->{helper}{ttsstate}==TTS_RESTORE) {
            SB_PLAYER_SetTTSState($hash,TTS_IDLE,0,1);
            delete($hash->{helper}{saveLocked}) if (defined($hash->{helper}{saveLocked}));
        }
    # CD 0056 end
    }
}

# CD 0062 start
sub SB_PLAYER_tcb_TriggerTTSDone($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    DoTrigger($name,"ttsdone");
}
# CD 0062 end

# CD 0063 start
sub SB_PLAYER_tcb_TriggerPlaylistStop($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if(IsDisabled($name));   # CD 0091

    $hash->{helper}{noStopEventUntil}=0 unless defined($hash->{helper}{noStopEventUntil});

    if ((ReadingsVal($name,"playStatus","x") eq "stopped")&&(time()>$hash->{helper}{noStopEventUntil})&&($hash->{helper}{ttsstate}==TTS_IDLE)) {
        DoTrigger($name,"playlistStop");
    }
}
# CD 0063 end

sub SB_PLAYER_SetTTSState($$$$) {
    my ( $hash, $state, $bulk, $broadcast ) = @_;
    my $name = $hash->{NAME};

    return if($state eq $hash->{helper}{ttsstate});
    return if(IsDisabled($name));   # CD 0091

    my $oldstate=$hash->{helper}{ttsstate}; # CD 0062

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
    delete($hash->{helper}{ttsPowerWasOff}) if (defined($hash->{helper}{ttsPowerWasOff}) && ($state==TTS_IDLE));

    # CD 0062 start
    if(($state==TTS_IDLE)&&($oldstate!=TTS_IDLE)) {
        if(defined($hash->{helper}{ttsActiveOptions}{eventondone})) {
            RemoveInternalTimer( "TriggerTTSDone:$name");
            InternalTimer( gettimeofday() + 0.5,
               "SB_PLAYER_tcb_TriggerTTSDone",
               "TriggerTTSDone:$name",
               0 );
        }
        IOWrite( $hash, "$name fhemrelay ttsdone" );

        SB_PLAYER_TTSLogPlayerState($hash, 'idle'); # CD 0097 Zustand aller Player ausgeben
    }
    # CD 0062 end
    
    # CD 0091 Timer aufräumen
    RemoveInternalTimer( "TimeoutTTSWaitForPlay:$name") if ($state!=TTS_WAITFORPLAY);
    RemoveInternalTimer( "TimeoutTTSWaitForPowerOn:$name") if($state!=TTS_WAITFORPOWERON);
    RemoveInternalTimer( "TTSDelay:$name") if($state==TTS_IDLE);
    RemoveInternalTimer( "TTSRestore:$name") if($state==TTS_IDLE);
    RemoveInternalTimer( "TTSStartAfterPowerOn:$name") if($state==TTS_IDLE);
}

# CD 0097 start
# ----------------------------------------------------------------------------
#  log player state for tts
# ----------------------------------------------------------------------------
sub SB_PLAYER_TTSLogPlayerState($$) {
    my ( $hash, $msg ) = @_;
    my $name = $hash->{NAME};

    if(defined($hash->{helper}{ttsOptions}{debug})) {
        Log3($hash, 0,"$name: ttsdebug - $msg"); 
        if (defined($hash->{SYNCGROUP}) && ($hash->{SYNCGROUP} ne '?') && ($hash->{SYNCMASTER} ne 'none')) {
            my @pl=split(",",$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER});
            Log3($hash, 0,"$name: ttsdebug - SM: " . SB_PLAYER_MACToFHEMPlayername($hash,$hash->{SYNCMASTER})); 
            
            foreach (@pl) {
                my $pn=SB_PLAYER_MACToFHEMPlayername($hash,$_);
                Log3($hash, 0,"$name: ttsdebug - $pn power: " . ReadingsVal($pn,'power','x')); 
                Log3($hash, 0,"$name: ttsdebug - $pn presence: " . ReadingsVal($pn,'presence','x')); 
                Log3($hash, 0,"$name: ttsdebug - $pn playStatus: " . ReadingsVal($pn,'playStatus','x')); 
                Log3($hash, 0,"$name: ttsdebug - $pn volume: " . ReadingsVal($pn,'volume','x')); 
            }
        } else {
                Log3($hash, 0,"$name: ttsdebug - power: " . ReadingsVal($name,'power','x')); 
                Log3($hash, 0,"$name: ttsdebug - presence: " . ReadingsVal($name,'presence','x')); 
                Log3($hash, 0,"$name: ttsdebug - playStatus: " . ReadingsVal($name,'playStatus','x')); 
                Log3($hash, 0,"$name: ttsdebug - volume: " . ReadingsVal($name,'volume','x')); 
        }
    }
}
# CD 0097 end

# ----------------------------------------------------------------------------
#  save player state
#
# CD 0036 added $statename
# ----------------------------------------------------------------------------
sub SB_PLAYER_Save($$) {
    my ( $hash, $statename ) = @_;
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

    $statename='default' unless defined($statename);

    delete($hash->{helper}{savedPlayerState}{$statename}) if(defined($hash->{helper}{savedPlayerState}) && defined($hash->{helper}{savedPlayerState}{$statename}));
    SB_PLAYER_EstimateElapsedTime($hash);
    $hash->{helper}{savedPlayerState}{$statename}{power}=ReadingsVal($name,"power","on");   # CD 0028
    $hash->{helper}{savedPlayerState}{$statename}{power}="off" if(($statename eq "xxTTSxx") && defined($hash->{helper}{ttsPowerWasOff})); # CD 0038
    $hash->{helper}{savedPlayerState}{$statename}{SYNCGROUP}=$hash->{SYNCGROUP} if(defined($hash->{SYNCGROUP}));    # CD 0028
    $hash->{helper}{savedPlayerState}{$statename}{SYNCMASTER}=$hash->{SYNCMASTER} if(defined($hash->{SYNCMASTER})); # CD 0028
    $hash->{helper}{savedPlayerState}{$statename}{elapsedTime}=$hash->{helper}{elapsedTime}{VAL};
    $hash->{helper}{savedPlayerState}{$statename}{playlistCurrentTrack}=ReadingsVal($name,"playlistCurrentTrack",1)-1;
    $hash->{helper}{savedPlayerState}{$statename}{playStatus}=ReadingsVal($name,"playStatus","?");
    $hash->{helper}{savedPlayerState}{$statename}{repeat}=ReadingsVal($name,"repeat","?");
    $hash->{helper}{savedPlayerState}{$statename}{volumeStraight}=ReadingsVal($name,"volumeStraight","?");
    $hash->{helper}{savedPlayerState}{$statename}{playlist}=ReadingsVal($name,"playlists","-");
    $hash->{helper}{savedPlayerState}{$statename}{favorite}=ReadingsVal($name,"favorites","-");
    $hash->{helper}{savedPlayerState}{$statename}{path}=$hash->{helper}{path};  # CD 0048

    # CD 0029 start
    delete($hash->{helper}{ttsOptions}{logloaddone}) if(defined($hash->{helper}{ttsOptions}{logloaddone}));
    delete($hash->{helper}{ttsOptions}{logplay}) if(defined($hash->{helper}{ttsOptions}{logplay}));
    # CD 0029 end

    # CD 0036 immer intern speichern
    $hash->{helper}{savedPlayerState}{$statename}{playlistIds}=$hash->{helper}{playlistIds};
    $hash->{helper}{savedPlayerState}{$statename}{playlistUrls}=$hash->{helper}{playlistUrls};
    if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
      Log3( $hash, 0, "SB_PLAYER_Save: $name: saving {helper}{playlistIds}: ".$hash->{helper}{playlistIds}) if(defined($hash->{helper}{playlistIds}));
    }
    # CD 0036

    # CD 0036, alte Version, deaktivert
    # ---------------------------------
    if(1==0) {
      # nur 1 Track -> playlist save verwenden
      if((ReadingsVal($name,"playlistTracks",1)<=1)&&(!defined($hash->{helper}{ttsOptions}{internalsave}))) {
          IOWrite( $hash, "$hash->{PLAYERMAC} playlist save fhem_$hash->{NAME}_$statename silent:1\n" );
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
              IOWrite( $hash, "$hash->{PLAYERMAC} playlist save fhem_$hash->{NAME}_$statename silent:1\n" );
              # CD 0029 start
              if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
                  Log3( $hash, 0, "SB_PLAYER_Save: $name: multiple tracks in playlist, using playlist save");
              }
              # CD 0029 end
          } else {
              $hash->{helper}{savedPlayerState}{$statename}{playlistIds}=$hash->{helper}{playlistIds};
              $hash->{helper}{savedPlayerState}{$statename}{playlistUrls}=$hash->{helper}{playlistUrls};
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
    }
    # ---------------------------------
    # CD 0029 start
    if(($hash->{helper}{ttsstate}!=TTS_IDLE) && defined($hash->{helper}{ttsOptions}{debugsaverestore})) {
        Log3( $hash, 0, "SB_PLAYER_Save: $name: power ".$hash->{helper}{savedPlayerState}{$statename}{power} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: elapsedTime ".$hash->{helper}{savedPlayerState}{$statename}{elapsedTime} ) if (defined($hash->{helper}{savedPlayerState}{$statename}{elapsedTime} ));
        Log3( $hash, 0, "SB_PLAYER_Save: $name: playlistCurrentTrack ".$hash->{helper}{savedPlayerState}{$statename}{playlistCurrentTrack} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: playStatus ".$hash->{helper}{savedPlayerState}{$statename}{playStatus} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: repeat ".$hash->{helper}{savedPlayerState}{$statename}{repeat} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: volumeStraight ".$hash->{helper}{savedPlayerState}{$statename}{volumeStraight} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: playlist ".$hash->{helper}{savedPlayerState}{$statename}{playlist} );
        Log3( $hash, 0, "SB_PLAYER_Save: $name: favorite ".$hash->{helper}{savedPlayerState}{$statename}{favorite} );
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

    return if(IsDisabled($name));   # CD 0091

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

    return if(defined($hash->{helper}{disableGetStatus}));
    return if(IsDisabled($name));   # CD 0091

    # CD 0014 start - Anzahl Anfragen begrenzen
    if(!defined($hash->{helper}{lastGetStatus})||($hash->{helper}{lastGetStatus}<gettimeofday()-0.5)) {
        #Log 0,"Querying status, last: $hash->{helper}{lastGetStatus}, now: ".gettimeofday();
        $hash->{helper}{lastGetStatus}=gettimeofday();

        # we fire the respective questions and parse the answers in parse
        IOWrite( $hash, "$hash->{PLAYERMAC} artist ?\n".
                "$hash->{PLAYERMAC} album ?\n".
                "$hash->{PLAYERMAC} title ?\n".
                "$hash->{PLAYERMAC} playlist url ?\n".
                "$hash->{PLAYERMAC} remote ?\n".
                "$hash->{PLAYERMAC} status 0 500 tags:Kcu\n".   # CD 0030 u added to tags
        #IOWrite( $hash, "$hash->{PLAYERMAC} alarm playlists 0 200\n" ) if (!defined($hash->{helper}{alarmPlaylists}));  # CD 0016 get available elements for alarms before querying the alarms # CD 0026 wird über Server verteilt
                "$hash->{PLAYERMAC} alarms 0 200 tags:all filter:all\n".  # CD 0015 filter added
                # MM 0016 start
                "$hash->{PLAYERMAC} playerpref alarmsEnabled ?\n".
                "$hash->{PLAYERMAC} playerpref alarmDefaultVolume ?\n".
                "$hash->{PLAYERMAC} playerpref alarmTimeoutSeconds ?\n".
                "$hash->{PLAYERMAC} playerpref alarmSnoozeSeconds ?\n".
                "$hash->{PLAYERMAC} playerpref alarmfadeseconds ?\n". # CD 0082
                # MM 0016 end
                "$hash->{PLAYERMAC} playerpref syncVolume ?\n". # CD 0007
                "$hash->{PLAYERMAC} playlist name ?\n".         # CD 0009
                "$hash->{PLAYERMAC} playlist path 0 ?\n".       # CD 0048
                "$hash->{PLAYERMAC} duration ?\n" );            # CD 0014
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

    my $iv=AttrVal($name, "statusRequestInterval", 300);  # CD 0037

    if(ReadingsVal($name,"presence","x") eq "absent") {   # CD 0079
        $iv=0;
        $hash->{helper}{disableGetStatus}=1;
    }
    
    InternalTimer( gettimeofday() + $iv,
                   "SB_PLAYER_GetStatus",
                   $hash,
                   0 ) if $iv>0;

    Log3( $hash, 5, "SB_PLAYER_GetStatus: leaving" );

    return( );
}


# ----------------------------------------------------------------------------
#  called from the IODev for Broadcastmessages
# ----------------------------------------------------------------------------
sub SB_PLAYER_RecBroadcast( $$@ ) {
    my ( $hash, $cmd, $msg, $bin ) = @_;

    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

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
            # CD 0043 bei Änderung von Adresse oder Port COVERART aktualisieren
            readingsBeginUpdate( $hash );
            SB_PLAYER_CoverArt( $hash );
            if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
                readingsEndUpdate( $hash, 0 );
            } else {
                readingsEndUpdate( $hash, 1 );
            }
            # CD 0043 end
        } else {
            # unkown broadcast message
        }

    } elsif( $cmd eq "FAVORITES" ) {
        RemoveInternalTimer( "ServerStatusRequest:$name");  # CD 0091
        if( $args[ 0 ] eq "ADD" ) {
            # format: ADD IODEVname ID shortentry
            $hash->{helper}{SB_PLAYER_Favs}{$args[3]}{ID} = $args[ 2 ];
            $hash->{helper}{SB_PLAYER_Favs}{$args[3]}{URL} = $args[ 4 ];        # CD 0021 hinzugefügt
            $hash->{helper}{SB_PLAYER_Favs}{$args[3]}{SOURCE} = $args[ 5 ];     # CD 0070 hinzugefügt
            if( $hash->{FAVSTR} eq "" ) {
                $hash->{FAVSTR} = $args[ 3 ];   # CD Test für Leerzeichen join("&nbsp;",@args[ 4..$#args ]);
            } else {
                $hash->{FAVSTR} .= "," . $args[ 3 ];    # CD Test für Leerzeichen join("&nbsp;",@args[ 4..$#args ]);
            }

            # CD 0064 start
            if( AttrVal( $name, "sortFavorites", "0" ) eq "1" ) {
                my @radios = split(',',$hash->{FAVSTR});    # CD0064 Elektrolurch
                $hash->{FAVSTR} = join(',',sort { "\L$a" cmp "\L$b" } @radios);   # CD0064 Elektrolurch
            }
            # CD 0064

            # CD 0068 start
            if(defined($hash->{helper}{ftuiSupport}{favorites})) {
                my $t=$hash->{FAVSTR};
                $t=~s/,/:/g;
                readingsSingleUpdate( $hash, "ftuiFavoritesItems", $t, 1 );
                $t=~s/_/ /g;
                readingsSingleUpdate( $hash, "ftuiFavoritesAlias", $t, 1 );
            }
            # CD 0068 end

            # CD 0016 start, provisorisch um alarmPlaylists zu aktualisieren, TODO: muss von 97_SB_SERVER kommen
            RemoveInternalTimer( $hash );   # CD 0016
            InternalTimer( gettimeofday() + 3,
                           "SB_PLAYER_GetStatus",
                           $hash,
                           0 );
            #end
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            if($args[ 1 ] eq 'all') {
                undef( %{$hash->{helper}{SB_PLAYER_Favs}} );
                $hash->{FAVSTR} = "";
                delete($hash->{helper}{alarmPlaylists}) if (defined($hash->{helper}{alarmPlaylists}));      # CD 0016
            } else {
                # CD 0070 gezielt nach Plugin/App löschen
                my $doupdate=0;
                my $favs="";
                foreach my $fa ( keys %{$hash->{helper}{SB_PLAYER_Favs}} ) {
                    if($hash->{helper}{SB_PLAYER_Favs}{$fa}{SOURCE} eq $args[ 1 ]) {
                        delete $hash->{helper}{SB_PLAYER_Favs}{$fa};
                        $doupdate=1;
                    } else {
                        if( $favs eq "" ) {
                            $favs = $fa;
                        } else {
                            $favs .= "," . $fa;
                        }
                    }
                }
                if($doupdate==1) {
                    if( AttrVal( $name, "sortFavorites", "0" ) eq "1" ) {
                        my @radios = split(',',$favs);
                        $hash->{FAVSTR} = join(',',sort { "\L$a" cmp "\L$b" } @radios);
                    } else {
                        $hash->{FAVSTR} = $favs;
                    }
                    if(defined($hash->{helper}{ftuiSupport}{favorites})) {
                        my $t=$hash->{FAVSTR};
                        $t=~s/,/:/g;
                        readingsSingleUpdate( $hash, "ftuiFavoritesItems", $t, 1 );
                        $t=~s/_/ /g;
                        readingsSingleUpdate( $hash, "ftuiFavoritesAlias", $t, 1 );
                    }
                }
            }
        } else {
        }

    } elsif( $cmd eq "SYNCMASTER" ) {
        if( $args[ 0 ] eq "ADD" ) {
            if(( $args[ 1 ] ne $hash->{PLAYERNAME} ) || ( $args[ 2 ] ne $hash->{PLAYERMAC} )) {   # CD 0056 Name oder MAC müssen unterschiedlich sein
                # CD 0056 mehrere Player haben gleichen Namen -> Namen anpassen
                if(( $args[ 1 ] eq $hash->{PLAYERNAME} ) || (defined($hash->{helper}{SB_PLAYER_SyncMasters}{$args[1]}))) {
                    $args[ 1 ]=$args[ 1 ] . "_MAC_" . $args[ 3 ];
                }
                # CD 0056 Ende
                $hash->{helper}{SB_PLAYER_SyncMasters}{$args[1]}{MAC} = $args[ 2 ];
                if( $hash->{SYNCMASTERS} eq "" ) {
                    $hash->{SYNCMASTERS} = $args[ 1 ];
                } else {
                    $hash->{SYNCMASTERS} .= "," . $args[ 1 ];
                }
            } else {
                $hash->{helper}{foundMyself}='1';   # CD 0091
            }
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            undef( %{$hash->{helper}{SB_PLAYER_SyncMasters}} );
            $hash->{SYNCMASTERS} = "";
            $hash->{helper}{foundMyself}='0';   # CD 0091
        # CD 0091 start
        } elsif( $args[ 0 ] eq 'DONE' ) {
            # überprüfen ob Player in der Liste enthalten war, falls nicht 'absent' setzen
            if($hash->{helper}{foundMyself} eq '0') {
                readingsBeginUpdate( $hash );
                SB_PLAYER_SetPlayerAbsent($hash);
                if( AttrVal( $name, "donotnotify", "false" ) eq "true" ) {
                    readingsEndUpdate( $hash, 0 );
                } else {
                    readingsEndUpdate( $hash, 1 );
                }
            } else {
                if (ReadingsVal($name,'presence','x') ne 'present') {
                    readingsSingleUpdate( $hash, 'presence', 'present', 1 );
                }
            }
        # CD 0091 end
        } else {
        }

    } elsif( $cmd eq "PLAYLISTS" ) {
        RemoveInternalTimer( "ServerStatusRequest:$name");  # CD 0091
        if( $args[ 0 ] eq "ADD" ) {
            # CD 0014 Playlists mit fhem_* ignorieren
            if($args[3]=~/^fhem_.*/) {
              # CD 0036 start
              if($args[3]=~/$name/) {
                my $plname=$args[1];
                # kein Name ?
                if($args[1]=~/^fhem_$name$/) {
                  $plname='default';
                } else {
                  $plname=~s/^fhem_$name//;
                  $plname=~s/^_//;
                }
                Log3( $hash, 4, "SB_PLAYER_RecbroadCast($name): - adding - PLAYLISTS ADD " .
                      "name:$args[1] id:$args[2] uid:$plname" );
                $hash->{helper}{myPlaylists}{$plname}{ID} = $args[ 2 ];
                $hash->{helper}{myPlaylists}{$plname}{NAME} = $args[ 1 ];
              } else {
              # CD 0036 end
                Log3( $hash, 5, "SB_PLAYER_RecbroadCast($name): - ignoring - PLAYLISTS ADD " .
                      "name:$args[1] id:$args[2] uid:$args[3]" );
              }
            } else {
            # CD 0014 end
                Log3( $hash, 4, "SB_PLAYER_RecbroadCast($name): PLAYLISTS ADD " .
                      "name:$args[1] id:$args[2] uid:$args[3]" );
                $hash->{helper}{SB_PLAYER_Playlists}{$args[3]}{SOURCE} = $args[ 4 ];    # CD 0070
                $hash->{helper}{SB_PLAYER_Playlists}{$args[3]}{ID} = $args[ 2 ];
                $hash->{helper}{SB_PLAYER_Playlists}{$args[3]}{NAME} = $args[ 1 ];
                if( $hash->{SERVERPLAYLISTS} eq "" ) {
                    $hash->{SERVERPLAYLISTS} = $args[ 3 ];
                } else {
                    $hash->{SERVERPLAYLISTS} .= "," . $args[ 3 ];
                }
            }   # CD 0014
            # CD 0064 start
            if( AttrVal( $name, "sortPlaylists", "0" ) eq "1" ) {
                my @radios = split(',',$hash->{SERVERPLAYLISTS});
                $hash->{SERVERPLAYLISTS} = join(',',sort { "\L$a" cmp "\L$b" } @radios);
            }
            # CD 0064

            # CD 0068 start
            if(defined($hash->{helper}{ftuiSupport}{playlists})) {
                my $t=$hash->{SERVERPLAYLISTS};
                $t=~s/,/:/g;
                readingsSingleUpdate( $hash, "ftuiPlaylistsItems", $t, 1 );
                $t=~s/_/ /g;
                readingsSingleUpdate( $hash, "ftuiPlaylistsAlias", $t, 1 );
            }
            # CD 0068 end

            # CD 0016 start, provisorisch um alarmPlaylists zu aktualisieren, TODO: muss von 97_SB_SERVER kommen
            RemoveInternalTimer( $hash );   # CD 0016
            InternalTimer( gettimeofday() + 3,
                           "SB_PLAYER_GetStatus",
                           $hash,
                           0 );
            #end
        } elsif( $args[ 0 ] eq "FLUSH" ) {
            if($args[ 1 ] eq 'all') {
                undef( %{$hash->{helper}{SB_PLAYER_Playlists}} );
                undef( %{$hash->{helper}{myPlaylists}} );  # CD 0036
                $hash->{SERVERPLAYLISTS} = "";
                delete($hash->{helper}{alarmPlaylists}) if (defined($hash->{helper}{alarmPlaylists}));      # CD 0016
            } else {
                # CD 0070 gezielt nach Plugin/App löschen
                my $doupdate=0;
                my $pls="";
                foreach my $pl ( keys %{$hash->{helper}{SB_PLAYER_Playlists}} ) {
                    if($hash->{helper}{SB_PLAYER_Playlists}{$pl}{SOURCE} eq $args[ 1 ]) {
                        delete $hash->{helper}{SB_PLAYER_Playlists}{$pl};
                        $doupdate=1;
                    } else {
                        if( $pls eq "" ) {
                            $pls = $pl;
                        } else {
                            $pls .= "," . $pl;
                        }
                    }
                }
                if($doupdate==1) {
                    if( AttrVal( $name, "sortPlaylists", "0" ) eq "1" ) {
                        my @radios = split(',',$pls);
                        $hash->{SERVERPLAYLISTS} = join(',',sort { "\L$a" cmp "\L$b" } @radios);
                    } else {
                        $hash->{SERVERPLAYLISTS}=$pls;
                    }

                    if(defined($hash->{helper}{ftuiSupport}{playlists})) {
                        my $t=$hash->{SERVERPLAYLISTS};
                        $t=~s/,/:/g;
                        readingsSingleUpdate( $hash, "ftuiPlaylistsItems", $t, 1 );
                        $t=~s/_/ /g;
                        readingsSingleUpdate( $hash, "ftuiPlaylistsAlias", $t, 1 );
                    }
                }
            }
        } else {
        }

    # CD 0026 start
    } elsif( $cmd eq "ALARMPLAYLISTS" ) {
        RemoveInternalTimer( "ServerStatusRequest:$name");  # CD 0091
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

    return if(IsDisabled($name));   # CD 0091

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

    fhem( "deletereading $name alarmid.*" ) if(ReadingsVal($name,'alarmid1','__xxx__') ne '__xxx__');        # CD 0015 alte readings entfernen # CD 0096 aber nur wenn es die Readings noch gibt, führt zu Hänger (83228)

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
        } elsif( $_ =~ /^(fade:)([0-9]+)/ ) {    # CD 0082 playerpref alarmfadeseconds unterstützen
            # example: fade:1
            if( $2 ne "0" ) {
                readingsBulkUpdate( $hash, "alarmsFadeIn", "on" );      # CD 0016 von MM übernommen, Namen geändert
                readingsBulkUpdate( $hash, "alarmsFadeSeconds", $2 );   # CD 0082
            } else {
                readingsBulkUpdate( $hash, "alarmsFadeIn", "off" );     # CD 0016 von MM übernommen, Namen geändert
            }
            next;
        } elsif( $_ =~ /^(count:)([0-9]+)/ ) {
            $hash->{helper}{ALARMSCOUNT} = $2;  # CD 0016 ALARMSCOUNT nach {helper} verschoben
            next;
        } else {
            Log3( $hash, 2, "SB_PLAYER_Alarms($name): Unknown data ($_)");
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

# CD 0046 start
# ----------------------------------------------------------------------------
#  search for LMS alarm id, return FHEM alarm number
# ----------------------------------------------------------------------------
sub SB_PLAYER_FindAlarmId( $$ ) {
    my ( $hash, $id ) = @_;
    my $name = $hash->{NAME};

    my $n=0;
    for (my $i=0;$i<=$hash->{helper}{ALARMSCOUNT};$i++) {
        if (ReadingsVal($name,"alarm".$i."_id","xxxx") eq $id) {
            $n=$i;
            last;
        }
    }
    return $n;
}
# CD 0046

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

# CD 0089 start
# ----------------------------------------------------------------------------
#  used for checking, if the string contains a valid IP v4 (decimal) address
# ----------------------------------------------------------------------------
sub SB_PLAYER_IsValidIPV4( $ ) {
    my $instr = shift( @_ );

    if( $instr =~ m/^(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)\.(\d\d?\d?)$/ )
    {
        if($1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255)
        {
            return( 1 );
        }
        else
        {
            return( 0 );
        }
    }
    else
    {
        return( 0 );
    }
}
# CD 0089 end

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

    return if(IsDisabled($name));   # CD 0091

    Log3( $hash, 4, "SB_PLAYER_Amplifier($name): called" );

    if( ( $hash->{AMPLIFIER} eq "none" ) ||
        ( !defined( $defs{$hash->{AMPLIFIER}} ) ) ) {
        # amplifier not specified
        delete($hash->{helper}{AMPLIFIERDELAYOFF}) if defined($hash->{helper}{AMPLIFIERDELAYOFF});  # CD 0012
        return;
    }

    # CD 0088 start
    my $amplifierShared=(AttrVal($name,'amplifierMode','exclusive') eq 'shared');
    
    if (defined($hash->{IODev}) && defined($hash->{IODev}->{NAME}) && $amplifierShared) {
        if(ReadingsVal($hash->{IODev}->{NAME},'state','x') ne 'opened') {
            Log3( $hash, 3, "SB_PLAYER_Amplifier($name): SB Server not connected, ignoring" );
            return;
        }
    }
    # CD 0088 end
    
    my $setvalue = "off";
    my $delayAmp=0.01;  # CD 0043

    my $thestatus = ''; # CD 0087
    if( AttrVal( $name, "amplifier", "play" ) eq "play" ) {
        $thestatus = ReadingsVal( $name, "playStatus", "pause" );

        Log3( $hash, 3, "SB_PLAYER_Amplifier($name): with mode play " .
              "and status:$thestatus" );

        if( ( $thestatus eq "playing" ) || (( $thestatus eq "paused" ) && ($hash->{helper}{amplifierDelayOffPause}==0)) ) { # CD 0043 DelayOffPause abfragen
            $setvalue = "on";
        # CD 0043 start
        } elsif(( $thestatus eq "paused" ) && ($hash->{helper}{amplifierDelayOffPause}>0)) {
            $setvalue = "off";
            $delayAmp=$hash->{helper}{amplifierDelayOffPause};
        # CD 0043 end
        } elsif( $thestatus eq "stopped" ) {
            $setvalue = "off";
            $delayAmp=$hash->{helper}{amplifierDelayOffStop}; # CD 0043
        } else {
            $setvalue = "off";
        }
    } elsif( AttrVal( $name, "amplifier", "on" ) eq "on" ) {
        $thestatus = ReadingsVal( $name, "power", "off" );

        Log3( $hash, 3, "SB_PLAYER_Amplifier($name): with mode on " .
              "and status:$thestatus" );

        if( $thestatus eq "on" ) {
            $setvalue = "on";
        } else {
            $setvalue = "off";
            $delayAmp=$hash->{helper}{amplifierDelayOffPower}; # CD 0043
        }
    } else {
        Log3( $hash, 1, "SB_PLAYER_Amplifier($name): ATTR amplifier " .
              "set to wrong value [on|play]" );
        return;
    }

    my $actualState = ReadingsVal( "$hash->{AMPLIFIER}", "state", "off" );

    # CD 0088 start
    if (($thestatus eq "?") && $amplifierShared) {
        Log3( $hash, 3, "SB_PLAYER_Amplifier($name): player state unknown, ignoring");
        return;
    }
    # CD 0088 end
    
    Log3( $hash, 3, "SB_PLAYER_Amplifier($name): actual:$actualState " .
          "and set:$setvalue" );

    if ( $actualState ne $setvalue) {
        # CD 0012 start - Abschalten über Attribut verzögern, generell verzögern damit set-Event funktioniert
        # my $delayAmp=($setvalue eq "off")?AttrVal( $name, "amplifierDelayOff", 0 ):0.1; # CD 0043 deaktiviert, wird oben behandelt
        $delayAmp=0.01 if($delayAmp==0);
        if (!defined($hash->{helper}{AMPLIFIERDELAYOFF})) {
            # CD 0043 Timer nicht neu starten wenn Zustand sich nicht geändert hat
            if ((!defined($hash->{helper}{AMPLIFIERACTIVETIMER})) || ($hash->{helper}{AMPLIFIERACTIVETIMER} ne ($actualState.$setvalue))) {
                if(($hash->{helper}{amplifierLastStatus} ne $thestatus) || !$amplifierShared) {    # CD 0088
                    Log3( $hash, 3, "SB_PLAYER_Amplifier($name): delaying amplifier on/off by $delayAmp" );
                    RemoveInternalTimer( "DelayAmplifier:$name");
                    InternalTimer( gettimeofday() + $delayAmp,
                        "SB_PLAYER_tcb_DelayAmplifier",  # CD 0014 Name geändert
                        "DelayAmplifier:$name",
                        0 );
                    $hash->{helper}{AMPLIFIERACTIVETIMER}=$actualState.$setvalue; # CD 0043
                } else {
                    Log3( $hash, 3, "SB_PLAYER_Amplifier($name): player state didn't change, ignoring" );
                }
            } else {
                Log3( $hash, 3, "SB_PLAYER_Amplifier($name): delay already active" );
            }
            return;
        }
        # CD 0012 end
        if(($hash->{helper}{amplifierLastStatus} ne $thestatus) || !$amplifierShared) {    # CD 0087
            fhem( "set $hash->{AMPLIFIER} $setvalue" );
            $hash->{helper}{amplifierLastStatus}=$thestatus;        # CD 0087
            Log3( $hash, 3, "SB_PLAYER_Amplifier($name): amplifier changed to " .
                  $setvalue );
        }
    } else {
        Log3( $hash, 3, "SB_PLAYER_Amplifier($name): no amplifier " .
              "state change" );
    }
    delete($hash->{helper}{AMPLIFIERDELAYOFF}) if (defined($hash->{helper}{AMPLIFIERDELAYOFF}));
    delete($hash->{helper}{AMPLIFIERACTIVETIMER}) if (defined($hash->{helper}{AMPLIFIERACTIVETIMER}));  # CD 0043

    return;
}


# ----------------------------------------------------------------------------
#  update the coverart image
# ----------------------------------------------------------------------------
sub SB_PLAYER_CoverArt( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

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

    return if(IsDisabled($name));   # CD 0091

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
    my $oldsyncmaster=$hash->{SYNCMASTER};  # CD 0056
    my $oldsyncgroup="";
    $oldsyncgroup=$hash->{SYNCGROUP} if defined($hash->{SYNCGROUP});  # CD 0065

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
    my $willsleepinfound=0; # CD 0089

    my $playerpresent=0;
    my $querymode=0;
    
    # loop through the results
    foreach( @data2 ) {
        my $cur=$_;
        if( $cur =~ /^(player_connected:)([0-9]*)/ ) {
            if( $2 eq "1" ) {
                readingsBulkUpdate( $hash, "connected", $2 );
                readingsBulkUpdate( $hash, "presence", "present" );
                # CD 0091 start
                delete($hash->{helper}{disableGetStatus}) if defined($hash->{helper}{disableGetStatus});
                $playerpresent=1;
                $querymode=1;
                # CD 0091 end
            } else {
                SB_PLAYER_SetPlayerAbsent($hash);
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
            $querymode=0;
            if( $2 eq "1" ) {
                if($playerpresent==1) {   # CD 0079 power nur auf 1 setzen wenn Player verbunden ist # CD 0091 nicht ReadingsVal verwenden da Wert noch nicht gesetzt ist
                    readingsBulkUpdate( $hash, "state", "on" ); # CD 0041 hinzugefügt
                    readingsBulkUpdate( $hash, "power", "on" );
                    SB_PLAYER_Amplifier( $hash );
                    # CD 0042 start
                    if($hash->{helper}{ttsstate}==TTS_WAITFORPOWERON) {
                        RemoveInternalTimer( "TTSStartAfterPowerOn:$name");
                        InternalTimer( gettimeofday() + 0.01,
                           "SB_PLAYER_tcb_TTSStartAfterPowerOn",
                           "TTSStartAfterPowerOn:$name",
                           0 );
                    }
                    # CD 0042 end
                }
            } else {
                # CD 0042 start
                if(($hash->{helper}{playerStatusOK}==0) && ($hash->{helper}{ttsstate}==TTS_WAITFORPOWERON)) {
                    $hash->{helper}{ttsPowerWasOff}=1;
                    IOWrite( $hash, "$hash->{PLAYERMAC} power 1\n" );
                }
                # CD 0042 end
                readingsBulkUpdate( $hash, "state", "off" ); # CD 0041 hinzugefügt
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
            # CD 0056 überprüfen ob Syncmaster gewechselt hat (passiert z.B. bei stop->play wenn aktueller Syncmaster aus ist)
            my $sm=$2;
            if ($oldsyncmaster ne "none") {
                if ($oldsyncmaster ne $2) {
                    Log3( $hash, defined($hash->{helper}{ttsOptions}{debug})?0:6, "SB_PLAYER_ParsePlayerStatus: $name: Syncmaster changed from $oldsyncmaster to $sm" );
                    if (defined($oldsyncgroup) && ($oldsyncgroup ne '?') && ($oldsyncmaster ne 'none')) {
                        my @pl=split(",",$oldsyncgroup.",".$oldsyncmaster);
                        foreach (@pl) {
                            if ($hash->{PLAYERMAC} ne $_) {
                                IOWrite( $hash, "$_ status 0 500 tags:Kcu\n" );
                            }
                        }
                    }
                }
            }
            # CD 0056 end
            $hash->{SYNCMASTER} = $sm;
            $hash->{SYNCED} = "yes";
            $hash->{SYNCMASTERPN} = SB_PLAYER_MACToLMSPlayername($hash,$sm);  # CD 0018
            next;

        } elsif( $cur =~ /^(sync_slaves:)(.*)/ ) {
            $hash->{SYNCGROUP} = $2;
            # CD 0018 start
            my @macs=split(",",$hash->{SYNCGROUP});
            my $syncgroup;
            foreach ( @macs ) {
                my $mac=$_;
                my $dev=SB_PLAYER_MACToLMSPlayername($hash,$mac);
                $syncgroup.="," if(defined($syncgroup));
                if(defined($dev)) {
                    $syncgroup.=$dev;
                } else {
                    if($mac eq $hash->{PLAYERMAC}) {
                        $syncgroup.=$hash->{PLAYERNAME};  # CD 0055 FIX: PLAYERNAME verwenden
                    } else {
                        $syncgroup.=$mac;
                    }
                }
            }
            $hash->{SYNCGROUPPN} = $syncgroup;
            # CD 0018 end
            # CD 0055 start
            if(AttrVal($name, "syncedNamesSource", "LMS") eq "FHEM") {
                my @pn=split ',',"$hash->{SYNCMASTERPN},$hash->{SYNCGROUPPN}";
                my @players=devspec2array("TYPE=SB_PLAYER");
                $syncgroup=undef;

                foreach my $lmsn (@pn) {   # CD 0067
                    foreach(@players) {
                        my $pn=$_;
                        my $phash=$defs{$_};
                        if($phash->{PLAYERNAME} eq $lmsn) { # CD 0067
                            $syncgroup.="," if(defined($syncgroup));
                            $syncgroup.=$pn;
                            last;
                        }
                    }
                }
                readingsBulkUpdate( $hash, "synced", $syncgroup );
            } else {
            # CD 0055 end
                if(defined($hash->{SYNCMASTERPN})) {
                    if(defined($hash->{SYNCGROUPPN})) {
                        readingsBulkUpdate( $hash, "synced", "$hash->{SYNCMASTERPN},$hash->{SYNCGROUPPN}" );    # Matthew 0019 hinzugefügt
                    } else {
                        readingsBulkUpdate( $hash, "synced", "$hash->{SYNCMASTERPN}" );
                    }
                } else {
                    if(defined($hash->{SYNCGROUPPN})) {
                        readingsBulkUpdate( $hash, "synced", "$hash->{SYNCGROUPPN}" );
                    } else {
                        readingsBulkUpdate( $hash, "synced", '' );
                    }
                }
            }
            next;

        } elsif( $cur =~ /^(will_sleep_in:)([0-9\.]*)/ ) {
            $hash->{WILLSLEEPIN} = int($2)." secs";
            $willsleepinfound=1;
            next;

        } elsif( $cur =~ /^(mixervolume:)(.*)/ ) {
            if( ( index( $2, "+" ) != -1 ) || ( index( $2, "-" ) != -1 ) ) {
                # that was a relative value. We do nothing and fire an update
                IOWrite( $hash, "$hash->{PLAYERMAC} mixer volume ?\n" );
            } else {
                SB_PLAYER_UpdateVolumeReadings( $hash, $2, true );
                # CD 0007 start
                if((defined($hash->{helper}{setSyncVolume}) && ($hash->{helper}{setSyncVolume} != $2))|| (!defined($hash->{helper}{setSyncVolume}))) {
                    SB_PLAYER_SetSyncedVolume($hash,$2,0);
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
            readingsBulkUpdate( $hash, "currentTrackPosition", int($2+0.5) );  # CD 0047
            next;
        } elsif( $cur =~ /^(playlist_tracks:)(.*)/ ) {
            readingsBulkUpdate( $hash, "playlistTracks", $2 );
            $hash->{helper}{playlistIds}='0' if($2==0); # CD 0071 wenn playlist leer ist internen Zustand zurücksetzen
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
    $hash->{WILLSLEEPIN} = '?' unless $willsleepinfound==1; # CD 0089
    $hash->{helper}{playerStatusOK}=1;  # CD 0042

    # CD 0091 mode abfragen wenn presence sich geändert hat aber keine Info über power vorhanden war
    IOWrite( $hash, "$hash->{PLAYERMAC} power ?\n" ) if($querymode==1);
    
    # CD 0065 start
    if(defined($hash->{helper}{ftuiSupport}{medialist})) {
        delete($hash->{SONGINFOQUEUE}) if(defined($hash->{SONGINFOQUEUE})); # CD 0072
        $hash->{helper}{songinfoquery}='';              # CD 0084
        $hash->{helper}{songinfocounter}=0;             # CD 0084
        $hash->{helper}{songinfopending}=0;             # CD 0084

        if(defined($hash->{helper}{playlistIds})) {
            $hash->{helper}{playlistInfoRetries}=5; # CD 0076
            my @ids=split(',',$hash->{helper}{playlistIds});
            foreach(@ids) {
#                SB_PLAYER_SonginfoAddQueue($hash,$_,0) unless ($_==0);   # CD 0083
                SB_PLAYER_SonginfoAddQueue($hash,$_,0) unless((defined($hash->{helper}{playlistInfo}{$_}) && !defined($hash->{helper}{playlistInfo}{$_}{remote})) || ($_==0));  # CD 0084
            }
            SB_PLAYER_SonginfoAddQueue($hash,0,0);
        }
    }
    # CD 0065 end

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
#  convert MAC to (LMS) playername
# ----------------------------------------------------------------------------
sub SB_PLAYER_MACToLMSPlayername( $$ ) {
    my( $hash, $mac ) = @_;
    my $name = $hash->{NAME};

    return $hash->{PLAYERNAME} if($hash->{PLAYERMAC} eq $mac);

    my $dev;
    foreach my $e ( keys %{$hash->{helper}{SB_PLAYER_SyncMasters}} ) {
        if(defined($hash->{helper}{SB_PLAYER_SyncMasters}{$e}{MAC})&&($mac eq $hash->{helper}{SB_PLAYER_SyncMasters}{$e}{MAC})) {   # 0056 defined hinzugefügt
            $dev=$e;
            last;
        }
    }
    return $dev;
}
# CD 0018 end

# CD 0097 start
# ----------------------------------------------------------------------------
#  search FHEM device for given MAC
# ----------------------------------------------------------------------------
sub SB_PLAYER_MACToFHEMPlayername( $$ ) {
    my( $hash, $mac ) = @_;
    my $name = $hash->{NAME};

    return $name if($hash->{PLAYERMAC} eq $mac);

    my @players=devspec2array("TYPE=SB_PLAYER");

    foreach (@players) {
        my $phash=$defs{$_};
        if($phash->{PLAYERMAC} eq $mac) {
            return $_;
        }
    }
    
    return undef;
}
# CD 0097 end

# CD 0014 start
# ----------------------------------------------------------------------------
#  estimate elapsed time
# ----------------------------------------------------------------------------
sub SB_PLAYER_EstimateElapsedTime( $ ) {
    my( $hash ) = @_;
    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

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

# CD 0065 start
# ----------------------------------------------------------------------------
#  convert volume from FHEM to LMS
# ----------------------------------------------------------------------------
sub SB_PLAYER_FHEM2LMSVolume( $$ ) {
    my( $hash, $fhemvol ) = @_;

    my $name = $hash->{NAME};

    if($fhemvol=~/[+-]+.*/) {return $fhemvol};    # CD 0069

    $fhemvol = int($fhemvol);

    my $offset=AttrVal($name,'volumeOffset',0);
    my $lmsvol=$fhemvol+$offset;

    $lmsvol=0 if(($lmsvol<0) && ($fhemvol>=0));
    $lmsvol=100 if($lmsvol>100);
    $lmsvol=-100 if($lmsvol<-100);

    return $lmsvol;
}
# CD 0065 end

# ----------------------------------------------------------------------------
#  update the volume readings
# ----------------------------------------------------------------------------
sub SB_PLAYER_UpdateVolumeReadings( $$$ ) {
    my( $hash, $vol, $bulk ) = @_;

    my $name = $hash->{NAME};

    $vol = int($vol);       # MM 0016, Fix wegen AirPlay-Plugin

    # CD 0065 start
    $hash->{helper}{lmsvolume}=$vol;
    my $offset=AttrVal($name,'volumeOffset',0);
    my $fhemvol=$vol-$offset;
    $fhemvol=0 if(($fhemvol<0) && ($vol>=0));
    $fhemvol=100 if($fhemvol>100);
    $fhemvol=-100 if($fhemvol<-100);
    # CD 0065 end

    if( $bulk == true ) {
        readingsBulkUpdate( $hash, "volumeStraight", $fhemvol );    # CD 0065 $fhemvol verwenden
        if( $vol > 0 ) {
            readingsBulkUpdate( $hash, "volume", $fhemvol );    # CD 0065 $fhemvol verwenden
        } else {
            readingsBulkUpdate( $hash, "volume", "muted" );
        }
    } else {
        readingsSingleUpdate( $hash, "volumeStraight", $fhemvol, 0 );    # CD 0065 $fhemvol verwenden
        if( $vol > 0 ) {
            readingsSingleUpdate( $hash, "volume", $fhemvol, 0 );    # CD 0065 $fhemvol verwenden
        } else {
            readingsSingleUpdate( $hash, "volume", "muted", 0 );
        }
    }

    return;
}

# ----------------------------------------------------------------------------
#  set volume of synced players
# ----------------------------------------------------------------------------
sub SB_PLAYER_SetSyncedVolume( $$$ ) {
    my( $hash, $vol, $isFHEMvol ) = @_;

    my $name = $hash->{NAME};

    return if(IsDisabled($name));   # CD 0091

    return if (!defined($hash->{SYNCED}) || ($hash->{SYNCED} ne "yes"));

    my $sva=AttrVal($name, "syncVolume", undef);
    my $t=$hash->{SYNCGROUP}.",".$hash->{SYNCMASTER};

    $vol = int($vol);       # MM 0016, Fix wegen AirPlay-Plugin

    $hash->{helper}{setSyncVolume}=$vol;

    if(defined($sva) && ($sva ne "0") && ($sva ne "1")) {
        my @pl=split(",",$t);
        my @chlds=devspec2array("TYPE=SB_PLAYER");

        # CD 0065 start
        if($isFHEMvol==0) {
            my $fhemvol=$vol-AttrVal($name,'volumeOffset',0);
            $fhemvol=0 if(($fhemvol<0) && ($vol>=0));
            $fhemvol=100 if($fhemvol>100);
            $fhemvol=-100 if($fhemvol<-100);
            #Log 0,$name.": convert volume from ".$vol." to ".$fhemvol;
            $vol=$fhemvol;
        }
        # CD 0065 end

        foreach (@pl) {
            if (($_ ne "?") && ($_ ne $hash->{PLAYERMAC})) {
                my $mac=$_;
                foreach(@chlds) {
                    my $chash=$defs{$_};
                    if(defined($chash) && defined($chash->{PLAYERMAC}) && ($chash->{PLAYERMAC} eq $mac)) {
                        my $sva2=AttrVal($chash->{NAME}, "syncVolume", undef);
                        if (defined($sva2) && ($sva eq $sva2)) {
                            if ($vol>0) {   # CD 0010
                                if(ReadingsVal($chash->{NAME}, "volumeStraight", $vol) ne $vol) {
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

# ----------------------------------------------------------------------------
#  load/save player state
#
#  CD 0036
# ----------------------------------------------------------------------------
sub SB_PLAYER_PlayerStatefileName($)
{
  my( $name ) = @_;

  my $statefile = $attr{global}{statefile};
  $statefile = substr $statefile,0,rindex($statefile,'/')+1;
  return $statefile ."sbps_$name.dd.save";
}

sub SB_PLAYER_SavePlayerStates($)
{
  my( $hash ) = @_;
  my $name = $hash->{NAME};

  return "No saved playlists found" unless(defined($hash->{helper}{savedPlayerState}));
  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = SB_PLAYER_PlayerStatefileName($name);

  if(open(FH, ">$statefile")) {
    my $t = localtime;
    print FH "#$t\n";

    my $dumper = Data::Dumper->new([]);
    $dumper->Terse(1);

    $dumper->Values([$hash->{helper}{savedPlayerState}]);
    print FH $dumper->Dump;

    close(FH);
  } else {

    my $msg = "SB_PLAYER_SavePlayerStates: Cannot open $statefile: $!";
    Log3 $hash, 1, $msg;
  }

  return undef;
}

sub SB_PLAYER_LoadPlayerStates($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = SB_PLAYER_PlayerStatefileName($name);

  if(open(FH, "<$statefile")) {
    my $encoded;
    while (my $line = <FH>) {
      chomp $line;
      next if($line =~ m/^#.*$/);
      $encoded .= $line;
    }
    close(FH);

    return if( !defined($encoded) );

    my $decoded = eval $encoded;
    $hash->{helper}{savedPlayerState} = $decoded;
  } else {
    my $msg = "SB_PLAYER_LoadPlayerStates: no playlists file found";
    Log3 undef, 4, $msg;
  }
  return undef;
}

# CD 0072 start
sub
SB_PLAYER_SonginfoAddQueue($$$) ##################################################
{
    my ($hash, $id, $wait) = @_;
    my $name = $hash->{NAME};

    if(!$hash->{SONGINFOQUEUE}) {
        $hash->{SONGINFOQUEUE} = [ $id ];
        push(@{$hash->{SONGINFOQUEUE}}, $id);
        RemoveInternalTimer( "SonginfoHandleQueue:$name");
        if ($init_done>0) { # CD 0084
            InternalTimer( gettimeofday() + ($wait==1?2.0:0.01),
               "SB_PLAYER_tcb_SonginfoHandleQueue",
               "SonginfoHandleQueue:$name",
               0 );
        }
    } else {
        push(@{$hash->{SONGINFOQUEUE}}, "wait") if ($wait==1);
        push(@{$hash->{SONGINFOQUEUE}}, $id);
    }
}

sub
SB_PLAYER_SonginfoHandleQueue($) ##################################################
{
    my $hash = shift;
    my $name = $hash->{NAME};

    my $arr = $hash->{SONGINFOQUEUE};
    if(defined($arr) && @{$arr} > 0) {
        if($hash->{helper}{songinfopending}<50) {
            shift(@{$arr});
            if(@{$arr} == 0) {
                if($hash->{helper}{songinfocounter}>0) {
                    IOWrite( $hash, $hash->{helper}{songinfoquery});
                    $hash->{helper}{songinfopending}+=$hash->{helper}{songinfocounter};
                    $hash->{helper}{songinfoquery}='';
                    $hash->{helper}{songinfocounter}=0;
                }
                IOWrite( $hash, $hash->{PLAYERMAC}." FHEMupdatePlaylistInfoDone\n" );
                delete($hash->{SONGINFOQUEUE});
                return;
            }
            my $id = $arr->[0];
            if($id ne "wait") {
                if(($id eq "") || ($id==0)) { # CD 0076 id 0 ignorieren
                    SB_PLAYER_SonginfoHandleQueue($hash);
                } else {
                    # CD 0084 Abfragen zusammenfassen
                    $hash->{helper}{songinfoquery}=$hash->{helper}{songinfoquery}.$hash->{PLAYERMAC}." songinfo 0 100 track_id:".$id." tags:acdltuxNK\n";
                    $hash->{helper}{songinfocounter}++;
                    if($hash->{helper}{songinfocounter}>=10) {
                        IOWrite( $hash, $hash->{helper}{songinfoquery});
                        $hash->{helper}{songinfopending}+=$hash->{helper}{songinfocounter};
                        $hash->{helper}{songinfoquery}='';
                        $hash->{helper}{songinfocounter}=0;
                    }
                }
            }
            InternalTimer( gettimeofday() + (($id eq "wait")?2.0:0.01),
               "SB_PLAYER_tcb_SonginfoHandleQueue",
               "SonginfoHandleQueue:$name",
               0 );
        } else {
            InternalTimer( gettimeofday() + 0.05,
               "SB_PLAYER_tcb_SonginfoHandleQueue",
               "SonginfoHandleQueue:$name",
               0 );
        }
    }
}

sub SB_PLAYER_tcb_SonginfoHandleQueue($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    SB_PLAYER_SonginfoHandleQueue($hash);
}
# CD 0072 end

# CD 0078 start
sub SB_PLAYER_RemoveInternalTimers($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer( "DelayAmplifier:$name");
    RemoveInternalTimer( "QueryElapsedTime:$name");
    RemoveInternalTimer( "SonginfoHandleQueue:$name");
    RemoveInternalTimer( "StartTalk:$name");
    RemoveInternalTimer( "TTSDelay:$name");
    RemoveInternalTimer( "TTSRestore:$name");
    RemoveInternalTimer( "TTSStartAfterPowerOn:$name");
    RemoveInternalTimer( "TimeoutTTSWaitForPlay:$name");
    RemoveInternalTimer( "TimeoutTTSWaitForPowerOn:$name");
    RemoveInternalTimer( "TriggerPlaylistStop:$name");
    RemoveInternalTimer( "TriggerTTSDone:$name");
    RemoveInternalTimer( "recallPause:$name");
    RemoveInternalTimer( "ServerStatusRequest:$name");
    RemoveInternalTimer( "ftuiMedialist:$name");    # CD 0085
    RemoveInternalTimer( $hash );
}
# CD 0078 end

# ##############################################################################
#  No PERL code beyond this line
# ##############################################################################
1;

=pod
=item device
=item summary    control Squeezebox Media Players
=item summary_DE Ansteuerung von Squeezebox Media Playern
=begin html

<a name="SB_PLAYER"></a>
<h3>SB_PLAYER</h3>
<ul>
  <a name="SBplayerdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SB_PLAYER &lt;player_mac_address&gt; [ampl:&lt;ampl&gt;] [coverart:&lt;coverart&gt;]</code>
    <br><br>
    This module controls Squeezebox Media Players connected to a defined Logitech Media Server (LMS). A SB_SERVER device is required.<br>
    Usually SB_PLAYER devices are created automatically by autocreate.<br><br>

   <ul>
      <li><code>&lt;player_mac_address&gt;</code>: Mac address of player as seen by LMS.</li>
   </ul><br>
   <b>Optional</b><br><br>
   <ul>
      <li><code>&lt;[ampl]&gt;</code>: A FHEM device to switch on or off when relevant events are received. The attribute
      <a href="#SBplayeramplifier">amplifier</a> specifies whether to switch this device upon reception of on/off or play/pause/stop events.</li>
      <li><code>&lt;[coverart]&gt;</code>: A FHEM weblink to be updated with the current coverart.
      This may be used to show coverart in a floorplan.</li>
   </ul><br><br>
  </ul>

  <a name="SBplayerset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt; [&lt;parameter&gt;]</code>
    <br><br>

    SB_Player related commands:<br><br>
   <ul>
     <li><b>play</b> -  start playback (might not work unless previously paused).</li>
     <li><b>pause [0|1]</b> -  toggle between play and pause states. &ldquo;pause 1&rdquo; and &ldquo;pause 0&rdquo; respectively pause and resume play unconditionally.</li>
     <li><b>stop</b> -  stop playback</li>
     <li><b>next|channelUp</b> -  next track</li>
     <li><b>prev|channelDown</b> -  previous track or the beginning of the current track.</li>
     <li><b>mute</b> -  toggle mute.</li>
     <li><b>volume &lt;n&gt;</b> -  set volume to &lt;n&gt;. &lt;n&gt; must be a number between 0 and 100.</li>
     <li><b>volume +|-&lt;n&gt;</b> - increase|decrease volume by a value given with +|-&lt;n&gt;. &lt;n&gt; must be a number between 0 and 100.</li>
     <li><b>volumeStraight &lt;n&gt;</b> -  same as volume</li>
     <li><b>volumeDown</b> - reduce the volume by a number of steps given with the attribute volumeStep; default 10 steps.</li>
     <li><b>volumeUp</b> - increase the volume by a number of steps given with the attribute volumeStep; default 10 steps.</li>
     <li><b>on</b> -  turn player on if possible. Issue play command otherwise.</li>
     <li><b>off</b> -  turn player off if possible. Issue stop command otherwise.</li>
     <li><b>shuffle off|song|album</b> -  enable/disable shuffle mode.</li>
     <li><b>repeat one|all|off</b> -  Set repeat mode.</li>
     <li><b>sleep &lt;timespec&gt;</b> -  Set player off after &lt;timespec&gt; has expired, fading player volume down. &lt;timespec&gt;'s format is hh:mm:ss.
     &lt;timespec&gt; is a relative time specification. That means: <code>set &lt;myPlayer&gt; sleep 22:00:00</code> doesn’t switch the player off at 10pm but after 22 hours</li>
     <li><b>favorites &lt;favorite&gt;</b> -  Empty current playlist and start &lt;favorite&gt;.
     &lt;favorite&gt; is a selected favorite from out of the favorite-list. The frontend may make favorites selectable by a dropdown list.</li>
     <li><b>talk|sayText &lt;text&gt;</b> -  Save the playlist, speak &lt;text&gt; using Google TTS and resume saved playlist.</li>
     <li><b>playlist track|album|artist|genre|year &lt;x&gt;</b> -  Empty current playlist and play given argument.</li>
     <li><b>playlist genre:&lt;genre&gt; artist:&lt;artist&gt; album:&lt;album&gt;</b> -  Empty current playlist and play all tracks matching the parameters. A * acts as a wildcard for everything.</li>
     <br>Example:<br>
     <code>set myplayer playlist genre:* artist:Whigfield album:*</code><br><br>
     <li><b>playlist play &lt;filename|playlistname&gt;</b> -  Empty current playlist and start the track or playlist.</li>
     <li><b>playlist add &lt;filename|playlistname&gt;</b> -  Add the specified file or playlist at the end of the current playlist.</li>
     <li><b>playlist insert &lt;filename|playlistname&gt;</b> -   Insert specified file or playlist after the current track into
     the current playlist.</li>
     <li><b>track|tracknumber &lt;n|+n|-n&gt;</b> -   Sets the track with the given tracknumber as the current title. An explicitly
     positive or negative number may be used to jump to a song relative to the currently playing song..</li>
     <li><b>statusRequest</b> -  Update all readings.</li>
     <li><b>sync &lt;playerName[,playerName...]&gt; [new|asSlave]</b> - Put playerName(s) into this player's multiroom group. Remove playerName(s) from their existing group(s) if necessary. Options:</li>
        <ul>
          <li>new - create a new group, removing this/these player(s) from any group.</li>
          <li>asSlave - add this player to a player or existing group</li>
        </ul><br>
     Examples:<br>
     <code>set playerA sync playerB</code>&nbsp;&nbsp;&nbsp;&nbsp;add playerB to playerA's group, both playing the content of playerA<br>
     <code>set playerA sync playerB,playerC,playerD</code>&nbsp;&nbsp;&nbsp;&nbsp;add playerB, C and D to playerA's group, all playing the content of playerA<br>
     <code>set playerA sync playerB new</code>&nbsp;&nbsp;&nbsp;&nbsp;create a new group with playerA and B, both playing playerA’s content<br>
     <code>set playerA sync playerB asSlave</code>&nbsp;&nbsp;&nbsp;&nbsp;add playerA to playerB's group, both playing now playerB’s content<br><br>
     <li><b>unsync</b> -  Remove this player from any multiroom group</li>
     <li><b>playlists &lt;name&gt;</b> -  Empty current playlist and start selected playlist.</li>
     <li><b>cliraw &lt;command&gt;</b> - Tell LMS to execute &lt;command&gt; using its command line interface.
     The answer of the LMS ist written to the internal LASTANSWER.</li>
     <li><b>save [&lt;name&gt;]</b> -  Save player state</li>
     <li><b>recall [&lt;name&gt;] [options] </b> -  Recall a saved player state. Options:</li>
        <ul>
          <li>del - delete saved state after restore</li>
          <li>delonly - delete saved state without restoring</li>
          <li>off - ignore saved power setting, turn player off after restore</li>
          <li>on - ignore saved power setting, turn player on after restore</li>
          <li>play - ignore saved play state, start playing after restore</li>
          <li>stop - ignore saved play state, stop playing after restore</li>
        </ul>
     <li><b>show line1:&lt;line1&gt; line2:[&lt;line2&gt;] duration:&lt;duration&gt;</b> - show text on the display of the player for a certain duration.
    If no 2. row should be displayed, the command however must contain 'line2:'</li>
       <ul>
         <li>line1 - Text to be displayed in the first line</li>
         <li>line2 - Text to be displayed in the second line</li>
         <li>duration -  Duration of display in seconds</li>
       </ul>
     <li><b>currentTrackPosition &lt;TimePosition&gt;</b> -  Sets the current timeposition inside the title to the given value.</li>
     <li><b>resetTTS</b> -  Resets TTS, can be necessary if the output via TTS blocks.</li>
     <li><b>updateFTUImedialist</b> -  Manually refresh the reading ftuiMedialist (containing the current songs).</li>
     <li><b>clearFTUIcache</b> -  Clear the cached data used for the FTUI-readings.</li>
    </ul>

   <br>Alarms<br>
   <ul>
   Multiple alarms may be defined.
     <li><b>allalarms add &lt;weekdays&gt; &lt;alarm time&gt; [&lt;playlist|URL&gt;]</b> -  Add a new alarm</li>
     <br>&lt;weekdays&gt; - Active days for this alarm. Format: 0..7|daily|all<br>
     0..6 for Sunday (0) through Saturday (6), 7 for every day<br>
     The first two letters of the english or german names may be used to specify days instead of a single digit. (Su/So, Mo, Tu/Di, We/Mi, Th/Do, Fr, Sa)<br>
     &lt;alarm time&gt; Alarm time specified as hh:mm[:ss]<br>&lt;playlist|URL&gt; If this parameter in not set, the playlist CURRENT is used.<br><br>
     Example:<br>
     <code>set player allalarms add 1DiWe 06:30 AlarmPlaylist</code> - Add a new alarm to sound playlist AlarmPlaylist every Monday through Wednesday at 06:30<br><br>
     <li><b>allalarms enable|disable</b> - Set global enable/disable flag. Setting this to "disable" effectively
     turns off all alarms. Setting this to "enable" allows alarms to honor their individual flags.
     Identical to command alarmsEnabled on|off.</li>
     <li><b>allalarms delete</b> - Delete all alarms.</li>
     <li><b>allalarms statusRequest</b> - Update status of all alarms.</li>
     <li><b>alarmsSnooze &lt;minutes&gt;</b> - Set duration of any snooze in minutes.</li>
     <li><b>alarmsTimeout &lt;minutes&gt;</b> -  Set duration of alarms in minutes. Setting this to 0 will disable the automatic timeout.</li>
     <li><b>alarmsDefaultVolume &lt;vol&gt;</b> -  Set default volume level (0-100) of alarms. This can be overridden by individual levels per alarm.</li>
     <li><b>alarmsFadeIn on|off</b> -  Whether alarms should fade in on this player</li>
     <li><b>alarmsFadeSeconds &lt;seconds&gt;</b> -  Fade-in period in seconds for the alarms.</li>
     <li><b>alarmsEnabled on|off</b> -  Whether any alarm can sound on this player. Set to off to prevent any alarm from sounding; on to allow them to sound</li>
     <li><b>snooze</b> - Switch off a running alarm and start again after a certain time, defined by the reading alarmsSnooze.</li>
     <br>
     <li><b>alarm&lt;X&gt; delete</b> -  Delete alarm &lt;X&gt;</li>
     <li><b>alarm&lt;X&gt; volume &lt;n&gt;</b> -  Set volume for alarm &lt;X&gt; to &lt;n&gt;</li>
     <li><b>alarm&lt;X&gt; enable|disable</b> -  Enable or disable alarm &lt;X&gt;</li>
     <li><b>alarm&lt;X&gt; sound &lt;playlist|URL&gt;</b> - Define playlist or URL to be sounded by alarm &lt;X&gt;</li>
     <li><b>alarm&lt;X&gt; repeat 0|off|no|1|on|yes</b> - Specify one-shot or repeating alarm</li>
     <li><b>alarm&lt;X&gt; wdays &lt;weekdays&gt;</b> - Specify active days for alarm &lt;X&gt;. Format: 0..7|daily|all<br>
     0..6 for Sunday (0) through Saturday (6), 7 for every day<br>
     The first two letters of the english or german names may be used to specify days instead of a single digit. (Su/So, Mo, Tu/Di, We/Mi, Th/Do, Fr, Sa)</li>
     <li><b>alarm&lt;X&gt; time hh:mm[:ss]</b> - Define alarm time</li>
   </ul>
   </ul>
   <br>

  <br><br>
  <a name="SBplayerattr"></a>
  <b>Attributes</b>
  <ul>
    <li>IODev &lt;servername&gt;<br>
      FHEM-Name of the SB_SERVER device controlling this player.</li>
    <li><a href="#do_not_notify">do_not_notify</a> true|false<br>
    Disable FileLog/notify/inform notification for a device. This affects the received signal, the set and trigger commands.
    Possible values are true|false</li>
    <li><a name="SBplayeramplifier">amplifier</a> on|play<br>
      Configure trigger for amplifier device. Possible values:
      <ul>
        <li><code>on</code>: Switch on "on" and "off" events.</li>
        <li><code>play</code>: Switch on "play", "pause" and "stop" events.</li>
      </ul>
    </li>
    <li>amplifierDelayOff &lt;sec1&gt;[,&lt;sec2&gt;]<br>
      Delay in seconds before turning the amplifier off after the player has stopped or been turned off. A second comma separated delay optionally enables switching off the amplifier after receiving a pause event.</li>
    <li>coverartheight 50|100|200<br>Display the coverart with a height of 50, 100 or 200 pixels</li>
    <li>coverartwidth 50|100|200<br>Display the coverart with a width of 50, 100 or 200 pixels</li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a> &lt;expression&gt;<br><br>
      Example:<br>
      <code>attr &lt;playername&gt; event-on-change-reading currentAlbum, currentArtist, currentTitle</code><br>
      Only changes in the readings currentAlbum, currentArtist, currentTitle cause an event.</li><br>
    <li>fadeinsecs &lt;sec1&gt;[,&lt;sec2&gt;]<br>
      Fade-in period in seconds. A second comma separated value optionally specifies the period to use on unpause.</li>
    <li>ftuiSupport 0|1|favorites|playlists|medialist<br>
      Create additional readings for FTUI integration. Warning: Using 1 or medialist may cause high cpu usage and unresponsiveness
      on slower systems.</li>
    <li>sortFavorites 0|1<br>
      If set to 1 the favorites will be sorted alphabetically.</li>
    <li>sortPlaylists 0|1<br>
      If set to 1 the playlists will be sorted alphabetically.</li>
    <li>statusRequestInterval &lt;sec&gt;<br>
      Interval in seconds for automatic status requests. Default: 300</li>
    <li>syncedNamesSource FHEM|LMS<br>
      Determines if the synced reading contains the LMS or FHEM names of the players</li>
    <li>syncVolume 0|1<br>
      Defines whether the loudness of this player is synchronized with the other players of its group</li>
    <li>trackPositionQueryInterval &lt;sec&gt;<br>
      Interval in seconds for querying the current track position, 0 disables the periodic update of the track position</li>
    <li>ttsAPIKey &lt;API-key&gt;<br>
      For the use of T2Speech from the company VoiceRSS (voicerss.org) an API-key is needed. Not needed with Google’s T2Speech.</li>
    <li>ttsDelay &lt;sec1&gt;[,&lt;sec2&gt;]<br>
      Delay in seconds before starting text to speech playback. A second comma separated delay may optionally be given to be used if the player is off.</li>
    <li>ttslanguage de|en|fr<br>
      Specifies the language of the voice output. A complete list of available languages using Google’s TTS can be found at wikipedia.org.</li>
    <li>ttslink &lt;link&gt;<br>
      Enter the link to the TTS-Funktion. Google, VoiceRSS and –with reservations- Text2Speech are supported.<br><br>
      Example of using Google’s TTS:<br>
      <code>attr &lt;playername&gt; ttslink http://translate.google.com/translate_tts?ie=UTF-8&amp;tl=&lt;LANG&gt;&amp;q=&lt;TEXT&gt;&amp;client=tw-ob</code></li><br>
    <li>ttsMP3FileDir &lt;directory&gt;<br>
      Directory to be used by default for text-embedded MP3-Files.</li><br>
      Example:<br>
      <code>attr &lt;SB_device&gt; ttsMP3FileDir /volume1/music/sounds</code><br><br>
    <li>ttsOptions &lt;options&gt;<br>various options, comma-separated, for TTS-output.
      <br><br>Options:<ul>
      <li>debug - Write additional information into the FHEM-logfile</li>
      <li>debugsaverestore - Additional information about loading/saving of player‘s status are written into the logfile</li>
      <li>nosaverestore - Do not save and restore the status of the player, thereby the normal playing stops after using TTS.</li>
      <li>forcegroupon - Switch on all players of the group.</li>
      <li>ignorevolumelimit - Ignore the attribute volumeLimit while using TTS-output.</li>
      <li>eventondone - Fire an event at the end of the TTS output.</li>
      </ul></li>
    <li>ttsPrefix &lt;text&gt;<br>
      Text prepended to every text to speech output</li>
    <li>ttsVolume &lt;value&gt;<br>
      Volume for text to speech. Defaults to current volume. If the attribute <code>ttsoptions</code> contains <code>ignorevolumelimit</code>
      any volume limit will be ignored for text to speech. Possible values: 0-100</li>
    <li>updateReadingsOnSet true|false<br>
      If set to true, most readings are immediately updated when a set command is executed without waiting for a reply from the server.</li>
    <li>volumeLimit &lt;value&gt;<br>
      Upper limit for volume setting by FHEM.</li>
    <li>volumeOffset &lt;value&gt;<br>
    The offset is added to the volume sent to the server. It is subtracted from the volume returned by the server.</li>
    <li>volumeStep &lt;value&gt;<br>
      Sets the volume adjustment to a granularity given by &lt;value&gt;. Possible values: 1–100. Default value: 10</li>
  </ul>
</ul>
=end html

=begin html_DE

<a name="SB_PLAYER"></a>
<h3>SB_PLAYER</h3>
<ul>
  <a name="SBplayerdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SB_PLAYER &lt;player_mac_address&gt; [ampl:&lt;ampl&gt;] [coverart:&lt;coverart&gt;]</code>
    <br><br>
    Dieses Modul steuert Squeezebox-Player, die mit einem bereits definiertem
    Logitech Media Server (LMS) verbunden sind. Ein SB_SERVER-Device ist erforderlich.
    Normalerweise wird das SB_PLAYER Device automatisch durch autocreate erzeugt.<br><br>

   <ul>
      <li><code>&lt;player_mac_address&gt;</code>: Die MAC-Adresse, wie der LMS den Player sieht.</li>
   </ul><br>
   <b>Optional</b><br><br>
   <ul>
      <li><code>&lt;[ampl]&gt;</code>: Ein FHEM-Device welches ein- oder ausgeschaltet werden soll, wenn
      ein passendes Event empfangen wird. Das Attribut
      <a href="#SBplayeramplifier">amplifier</a> gibt an, ob das passende Event on/off oder play/pause sein soll.</li>
      <li><code>&lt;[coverart]&gt;</code>: Unter &lt;coverart&gt; gibt man den Namen eines FHEM weblink image
      Elementes an. Der Player aktualisiert dann jeweils den Link auf das aktuelle Coverart Bild, so dass
      man dieses z.B. im Floorplan anzeigen kann.</li>
   </ul><br><br>
  </ul>

  <a name="SBplayerset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;Name&gt; &lt;Befehl&gt; [&lt;Parameter&gt;]</code>
    <br><br>

    Befehle zur Steuerung des Players:<br><br>
   <ul>
     <li><b>play</b> -  Startet die Wiedergabe (Es kann sein, dass die Wiedergabe nicht funktioniert,
     wenn kein pause-Befehl vorangegangen ist).</li>
     <li><b>pause [0|1]</b> -  Schaltet zwischen play und pause hin und her (Toggle-Funktion).
     &ldquo;pause 1&rdquo; und &ldquo;pause 0&rdquo; schaltet bedingungslos auf Pause resp. Wiedergabe.</li>
     <li><b>stop</b> -  Stoppt die Wiedergabe</li>
     <li><b>next|channelUp</b> -  Springt zum n&auml;chsten Track</li>
     <li><b>prev|channelDown</b> -  Springt zum vorherigen Track bzw. zum Anfang des gegenw&auml;rtig gespielten Tracks.</li>
     <li><b>mute</b> -  Toggelt die Lautst&auml;rke stumm und wieder zur&uuml;ck.</li>
     <li><b>volume &lt;n&gt;</b> -  Stellt die Lautst&auml;rke auf einen Wert &lt;n&gt; ein. Dabei muss &lt;n&gt;
     eine Zahl zwischen 0 und 100 sein.</li>
     <li><b>volume +|-&lt;n&gt;</b> - Erh&ouml;ht oder vermindert die Lautst&auml;rke um den Wert, der durch +|-&lt;n&gt;
     vorgegeben wird. Dabei muss &lt;n&gt; eine Zahl zwischen 0 und 100 sein.</li>
     <li><b>volumeStraight &lt;n&gt;</b> -  mit volume identisch</li>
     <li><b>volumeDown</b> -  Verringert die Lautst&auml;rke um eine bestimmte Anzahl von Schritten die mit dem Attribut
     <a href="#SBplayervolumeStep">volumeStep</a> vorgegeben werden. Wird nichts vorgegeben, werden 10 Schritte verwendet</li>
     <li><b>volumeUp</b> -  Erh&ouml;ht die Lautst&auml;rke um eine bestimmte Anzahl von Schritten, die mit dem Attribut
     <a href="#SBplayervolumeStep">volumeStep</a> vorgegeben werden. Wird nichts vorgegeben, werden 10 Schritte verwendet</li>
     <li><b>on</b> -  Schaltet den Player ein. Ist das nicht m&ouml;glich, wird ein play-Befehl gesendet.</li>
     <li><b>off</b> -  Schaltet den Player aus. Ist das nicht m&ouml;glich, wird ein stop-Befehl gesendet.</li>
     <li><b>shuffle off|song|album</b> -  Schaltet die zuf&auml;llige Wiedergabe aus (off); f&uuml;r Songs einer Wiedergabeliste (song)
     ein oder f&uuml;r eine Liste von Alben ein(album).</li>
     <li><b>repeat one|all|off</b> -  Schaltet die Wiederholung von Tracks einer Wiedergabeliste aus (off), f&uuml;r ein Track
     ein (one) oder f&uuml;r alle St&uuml;cke der Wiedergabeliste ein (all).</li>
     <li><b>sleep &lt;timespec&gt;</b> -  Dauer, nach der sich der Player ausschalten soll,
     Format hh:mm[:ss]. Bei der Zeitangabe handelt es sich um eine relative Zeitangabe ab
     dem Aufruf. Das bedeutet:
     <code>set &lt;myPlayer&gt; sleep 22:00:00</code> schaltet den Player nicht um 10 Uhr abends aus,
     sondern erst 22 Stunden nach dem Aufruf!</li>
     <li><b>favorites &lt;favorite&gt;</b> -  L&ouml;scht die aktuelle Wiedergabeliste und startet den Favoriten &lt;favorite&gt;.
     &lt;favorite&gt; ist der ausgew&auml;hlte Favorit aus einer Favoritenliste. Das Frontend kann eine
     Dropdownliste zur Verf&uuml;gung stellen, aus der der Favorit ausgew&auml;hlt werden kann.</li>
     <li><b>talk|sayText &lt;text&gt;</b> -  Speichert den aktuellen Stand der Playlist, sagt den Text
     &lt;text&gt; unter Zuhilfenahme von GoogleTTS oder VoiceRSS an und setzt die Wiedergabe ab dem
     gespeicherten Punkt fort.</li>
     <li><b>playlist track|album|artist|genre|year &lt;x&gt;</b> -  L&ouml;scht die aktuelle Wiedergabeliste
     und gibt das vorgegebene Argument &lt;x&gt; wieder.</li>
     <li><b>playlist genre:&lt;genre&gt; artist:&lt;artist&gt; album:&lt;album&gt;</b> -
     L&ouml;scht die aktuelle Wiedergabeliste und gibt alle Tracks wieder, die den angegebenen Kriterien entsprechen.
     Ein * steht f&uuml;r beliebige Angaben.</li>
     <br>Beispiel:<br>
     <code>set myplayer playlist genre:* artist:Whigfield album:*</code><br><br>
     <li><b>playlist play &lt;filename|playlistname&gt;</b> -  L&ouml;scht die aktuelle Wiedergabeliste und
     startet die Wiedergabe eines Track oder einer Playlist.</li>
     <li><b>playlist add &lt;filename|playlistname&gt;</b> -  H&auml;ngt die angegebene Datei oder Playlist
     an das Ende der aktuellen Playlist an.</li>
     <li><b>playlist insert &lt;filename|playlistname&gt;</b> -   F&uuml;gt die angegebene Datei oder Playlist
     hinter der aktuellen Datei oder Playlist in der aktuellen Playlist ein.</li>
     <li><b>track|tracknumber &lt;n|+n|-n&gt;</b> -   Aktiviert einen bestimmten Titel der aktiven Playliste. Mit &lt;n&gt; ist
     die laufende Nummer des Titels innerhalb dieser Playliste anzugeben. Ein explizierter Wert mit Vorzeichen,
     springt in der momentanen Playliste um &lt;+n&gt; oder &lt;-n&gt; Titel vor oder zurück.</li>
     <li><b>statusRequest</b> -  Aktualisierung aller Readings.</li>
     <li><b>sync &lt;playerName[,playerName...]&gt; [new|asSlave]</b> - F&uuml;gt den/die Player mit dem/den Namen
     &lt;playerName&gt; der Multiroom-Gruppe desjenigen Players hinzu, der diesen Befehl aufgerufen hat;
     entfernt aber bei Bedarf den Player &lt;playerName&gt; aus seiner bisherigen Gruppe.<br>Optionen:</li>
        <ul>
          <li>new - Bildet eine neue Gruppe und entfernt den/die Player aus seiner/ihren bisherigen Gruppe/n</li>
          <li>asSlave - F&uuml;gt diesen Player zu einem anderen Player oder einer vorhandenen Gruppe hinzu.</li>
        </ul><br>
     Examples:<br>
     <code>set playerA sync playerB</code>&nbsp;&nbsp;&nbsp;&nbsp;F&uuml;gt PlayerB der Gruppe von PlayerA hinzu;
     beide geben den Inhalt von PlayerA wieder.<br>
     <code>set playerA sync playerB,playerC,playerD</code>&nbsp;&nbsp;&nbsp;&nbsp;F&uuml;gt PlayerB, C and D der
     Gruppe von PlayerA hinzu; alle geben den Inhalt von PlayerA wieder.<br>
     <code>set playerA sync playerB new</code>&nbsp;&nbsp;&nbsp;&nbsp;Bildet eine neue Gruppe mit PlayerA
     und PlayerB, beide geben den Inhalt von PlayerA wieder.<br>
     <code>set playerA sync playerB asSlave</code>&nbsp;&nbsp;&nbsp;&nbsp;F&uuml;gt PlayerA der Gruppe von
     PlayerB hinzu; beide geben den Inhalt von PlayerB wieder.<br><br>
     <li><b>unsync</b> -  Entfernt diesen Player aus allen Multiroom-Gruppen</li>
     <li><b>playlists &lt;name&gt;</b> -  L&ouml;scht die aktuelle Playlist und startet die ausgew&auml;hlte Playlist.</li>
     <li><b>cliraw &lt;command&gt;</b> - Kann direkte Befehle an das CLI Interface schicken. Die Antwort
     steht dann im Internal LASTANSWER.</li>
     <li><b>save [&lt;name&gt;]</b> -  Speichert den derzeitigen Player-Status unter dem Namen &lt;name&gt;.</li>
     <li><b>recall [&lt;name&gt;] [options] </b> -  Ruft einen gespeicherten Player-Status auf.<br>Optionen:</li>
        <ul>
          <li>del - L&ouml;scht nach dem Restore den gespeicherten Status</li>
          <li>delonly - L&ouml;scht den gespeicherten Status ohne vorherigem Restore</li>
          <li>off - Beachtet die gespeicherten Einstellungen zum Betriebszustand nicht
          sondern schaltet den Player nach Restore aus.</li>
          <li>on - Beachtet die gespeicherten Einstellungen zum Betriebszustand nicht
          sondern schaltet den Player nach Restore ein.</li>
          <li>play - Beachtet den gespeicherten play-Status nicht sondern startet die Wiedergabe nach Restore.</li>
          <li>stop - Beachtet den gespeicherten play-Status nicht sondern stoppt die Wiedergabe nach Restore.</li>
        </ul>
    <li><b>show line1:&lt;text1&gt; line2:[&lt;text2&gt;] duration:&lt;duration&gt;</b> - Zeigt
    einen beliebigen Text auf dem Display f&uuml;r eine vorgegebene Dauer an. Wenn keine 2. Zeile
    angezeigt werden sollen, muss trotzdem 'line2:' im Aufruf enthalten sein</li>
       <ul>
         <li>text1 - Inhalt der ersten Zeile</li>
         <li>text2 - Inhalt der zweiten Zeile</li>
         <li>duration -  Dauer der Anzeige auf dem Display in Sekunden</li>
       </ul>
     <li><b>currentTrackPosition &lt;TimePosition&gt;</b> -  Setzt die Abspielposition innerhalb des
     Liedes auf den angegebenen Zeitwert (z.B. 0:01:15).</li>
     <li><b>resetTTS</b> -  TTS zur&uuml;cksetzen, kann n&ouml;tig sein wenn die TTS-Ausgabe h&auml;ngt.</li>
     <li><b>updateFTUImedialist</b> -  Erzwingt die Aktualisierung des Readings ftuiMedialist (enth&auml;lt die aktuellen Songs).</li>
     <li><b>clearFTUIcache</b> -  L&ouml;scht alle zwischengespeicherten Daten für die Erstellung der FTUI-Readings.</li>
   </ul>

   <br>Befehlsliste zur Steuerung der Wecker, mehrere Wecker k&ouml;nnen definiert werden.<br><br>
   <ul>
     <li><b>allalarms add &lt;weekdays&gt; &lt;alarm time&gt; [&lt;playlist|URL&gt;]</b> -  F&uuml;gt einen neuen Wecker hinzu.</li>
     <br>&lt;weekdays&gt; - Aktive Tage f&uuml;r diesen Wecker. Format: [0..7|daily|all]
     0 bis 6 f&uuml;r Sonntag bis Samstag. 7, daily und all f&uuml;r t&auml;gliches Wecken.
     Die Wochentage k&ouml;nnen ebenfalls durch die ersten zwei Buchstaben des
     Wochentages sowohl in deutscher und englischer Sprache angegeben werden
     (Su/So, Mo, Tu/Di, We/Mi, Th/Do, Fr, Sa).<br><br>
     &lt;alarm time&gt; Weckzeit im Format hh:mm[:ss]<br>
     &lt;playlist|URL&gt; Weckton, wenn dieser Parameter nicht gesetzt wird, wird die aktuelle Playlist verwendet.<br><br>
     Beispiel:<br>
     <code>set player allalarms add 1DiWe 06:30 AlarmPlaylist</code> - F&uuml;gt einen
     neuen Wecker hinzu. Der Wecker startet jeden Montag bis Mittwoch um 6:30 Uhr
     und spielt die Playlist AlarmPlaylist ab.<br><br>
     <li><b>allalarms enable|disable</b> - Setzt das globale einable/disable Flag f&uuml;r alle Wecker.
     "disable" deaktiviert alle Wecker. “enable" gestattet allen
     Weckern sich nach den individuellen Flags zu richten. Identisch mit dem Befehl alarmsEnabled on|off.</li>
     <li><b>allalarms delete</b> -  L&ouml;scht alle Wecker.</li>
     <li><b>allalarms statusRequest</b> -  Aktualisiert den Zustand aller Wecker.</li>
     <li><b>alarmsSnooze &lt;minutes&gt;</b> -  Setzt die Dauer der Weckwiederholung (in Minuten).</li>
     <li><b>alarmsTimeout &lt;minutes&gt;</b> -  Bestimmt, wie lange ein Wecker l&auml;uft
     bevor er automatisch beendet wird. Ist der Wert 0, l&auml;uft der Wecker, bis er manuell beendet wird.</li>
     <li><b>alarmsDefaultVolume &lt;vol&gt;</b> -  Legt die generelle Lautst&auml;rke (0-100) f&uuml;r den Wecker fest.
     Dieser Wert kann durch eine individuelle Lautst&auml;rkeangabe je Alarm &uuml;berschrieben werden (siehe auch
     <a href="#SBplayeralarmxvolume">alarm&lt;X&gt; volume &lt;n&gt;</a>)</li>
     <li><b>alarmsFadeIn on|off</b> -  Schaltet fadeIn f&uuml;r die Wecker ein (on) oder aus (off).</li>
     <li><b>alarmsFadeSeconds &lt;seconds&gt;</b> -  Fade-in Dauer f&uuml;r die Wecker.</li>
     <li><b>alarmsEnabled on|off</b> -  Gibt an, ob die eingetragenen Wecker &uuml;berhaupt abgespielt
     werden sollen (on) oder nicht (off).</li>
     <li><b>snooze</b> - Schaltet einen gerade laufenden Wecker aus und nach einer durch
     das Reading alarmsSnooze definierten Zeit wieder ein..</li>
     <br>
   </ul>
   Befehle f&uuml;r einzelne Wecker (X entspricht der Nummer des Weckers)
   <ul>
     <br>
     <li><b>alarm&lt;X&gt; delete</b> -  L&ouml;scht den Wecker &lt;X&gt; aus der Weckerliste.</li>
     <li><b><a name="SBplayeralarmxvolume">alarm&lt;X&gt; volume &lt;n&gt;</a></b> -  Stellt
     die Lautst&auml;rke des Weckers &lt;X&gt; auf den Wert &lt;n&gt;.</li>
     <li><b>alarm&lt;X&gt; enable|disable</b> -  Aktiviert bzw. deaktiviert den Wecker &lt;X&gt;</li>
     <li><b>alarm&lt;X&gt; sound &lt;playlist|URL&gt;</b> -  Bestimmt eine Playlist oder URL, die
     beim Wecker &lt;X&gt; abgespielt werden soll.</li>
     <li><b>alarm&lt;X&gt; repeat 0|off|no|1|on|yes</b> -  Bestimmt, ob Wecker &lt;X&gt; einmalig
     (0|off|no) oder mehrfach (1|on|yes) ausgel&ouml;st werden soll.</li>
     <li><b>alarm&lt;X&gt; wdays &lt;weekdays&gt;</b> -  Aktive Tage f&uuml;r diesen Wecker.
     &lt;weekdays&gt; hat die m&ouml;glichen Inhalte 0 bis 6 f&uuml;r Sonntag bis Samstag, 7,
     daily und all f&uuml;r t&auml;gliches Wecken. Die Wochentage k&ouml;nnen ebenfalls durch die ersten
     zwei Buchstaben des Wochentages sowohl in deutscher und englischer Sprache angegeben
     werden (Su/So, Mo, Tu/Di, We/Mi, Th/Do, Fr, Sa).</li>
     <li><b>alarm&lt;X&gt; time hh:mm[:ss]</b> - Weckzeit im Format hh:mm[:ss].</li>
   </ul>
   </ul>

   <br>
  <a name="SBplayerattr"></a>
  <b>Attribute</b>
  <ul>
    <li>IODev &lt;servername&gt;<br>
      FHEM-Name des SB_SERVERS.</li>
    <li><a href="#do_not_notify">do_not_notify</a> true|false<br>
    Mit diesem Attribut kann man einstellen, ob der Player ein FHEM Notify bei jeder &auml;nderung eines Readings lostritt oder nicht.</li>
    <li><a name="SBplayeramplifier">amplifier</a> on|play<br>
      Gibt an, mit welcher Funktion ein zuschaltbarer Verst&auml;rkers eingeschaltet werden soll, entweder bei einem
      Einschaltvorgang (on) oder bei einen Startvorgang zum Abspielen eines Files (play).
    </li>
    <li>amplifierDelayOff &lt;sec1&gt;[,&lt;sec2&gt;]<br>
      Stellt eine Verz&ouml;gerung zwischen dem Ausschaltvorgang des Players und des Verst&auml;rkers in Sekunden ein.
      Wird eine optionale zweite Zeit durch Komma getrennt angegeben, so wird diese bei Pause verwendet. Fehlt
      die zweite Zeitangabe, wird bei Pause nicht abgeschaltet.</li>
    <li>coverartheight 50|100|200<br>Stellt das Cover mit einer vertikalen Aufl&ouml;sung von 50, 100 oder 200 Pixel dar.</li>
    <li>coverartwidth 50|100|200<br>Stellt das Cover mit einer horizontalen Aufl&ouml;sung von 50, 100 oder 200 Pixel dar.</li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a> &lt;expression&gt;<br>Wird <a href="#do_not_notify">do_not_notify</a>
    auf false gesetzt, veranlasst jede &Auml;nderung eines Readings ein Notify. Mit diesem Attribut k&ouml;nnen
    ausl&ouml;sende Ereignisse gefiltert werden.<br><br>
      Beispiel:<br>
      <code>attr &lt;playername&gt; event-on-change-reading currentAlbum, currentArtist, currentTitle</code><br>
      Nur &auml;nderungen der Readings currentAlbum, currentArtist, currentTitle erzeugen Events.</li><br>
    <li>fadeinsecs &lt;sec1&gt;[,&lt;sec2&gt;]<br>
      Fade in f&uuml;r Beginn von Playlisten und neuen Soundfiles. Bezeichnet die Dauer des Vorganges, in der die
      Lautst&auml;rke auf den vorgegebenen Wert ansteigt und wird in Sekunden angegeben. Ein zweiter, durch Komma
      getrennter optionaler Wert, gibt die Dauer des Fadein beim Verlassen des Pausenzustandes an.</li>
    <li>ftuiSupport 0|1|favorites|playlists|medialist<br>
      Zus&auml;tzliche Readings f&uuml;r die Integration in FTUI erzeugen. Achtung: Die Verwendung von 1 oder medialist kann kurzzeitig zu
      erh&ouml;ter Systemlast und H&auml;ngern auf langsamen Systemen f&uuml;hren.</li>
    <li>statusRequestInterval &lt;sec&gt;<br>
      Aktualisierungsintervall der automatischen Status-Abfrage. Default: 300</li>
    <li>sortFavorites 0|1<br>
      Wenn das Attribut den Wert 1 hat wird die Liste der Favoriten alphabetisch sortiert.</li>
    <li>sortPlaylists 0|1<br>
      Wenn das Attribut den Wert 1 hat wird die Liste der Wiedergabelisten alphabetisch sortiert.</li>
    <li>syncedNamesSource FHEM|LMS<br>
      Legt fest ob die FHEM-Ger&auml;tenamen oder die LMS-Namen der Player im synced-Reading verwendet werden.</li>
    <li>syncVolume 0|1<br>
      Legt fest ob die Lautst&auml;rke des Players mit anderen Playern aus der Gruppe synchronisiert wird.</li>
    <li>trackPositionQueryInterval &lt;sec&gt;<br>
      Legt fest wie häufig die abgespielte Zeit abgefragt wird, 0 deaktiviert das Abfragen.</li>
    <li>ttsAPIKey &lt;API-key&gt;<br>
      F&uuml;r die Benutzung von T2Speech der Firma VoiceRSS (voicerss.org) ist ein API-Key erforderlich.
      F&uuml;r Googles T2Speech ist kein Key notwendig.</li>
    <li>ttsDelay &lt;sec1&gt;[,&lt;sec2&gt;]<br>
      Wartezeit in Sekunden bevor die TTS-Ausgabe gestartet wird. Optional kann eine 2. Zeit durch
      Komma getrennt angegeben werden. In diesem Fall wird die 1. Zeit verwendet wenn der Player
      eingeschaltet ist und die 2. wenn er ausgeschaltet ist.</li>
    <li>ttslanguage de|en|fr<br>
      Stellt die gew&uuml;nschte Sprache f&uuml;r die Text-to-Speech Funktion ein. Eine vollst&auml;ndige Liste
      der verf&uuml;gbaren Sprachen findet sich in wikipedia.org</li>
    <li>ttslink &lt;link&gt;<br>
      Link zur TTS-Funktion. Unterst&uuml;tzt werden: Google, VoiceRSS (API-Key wird ben&ouml;tigt) und mit Einschr&auml;nkungen Text2Speech.<br><br>
      Beispiel f&uuml;r Google’s TTS:<br>
      <code>attr &lt;playername&gt; ttslink http://translate.google.com/translate_tts?ie=UTF-8&amp;tl=&lt;LANG&gt;&amp;q=&lt;TEXT&gt;&amp;client=tw-ob</code></li><br>
    <li>ttsMP3FileDir &lt;directory&gt;<br>
      Standard-Verzeichnis f&uuml;r Musik- und Sprachdateien (z.B. Gong, Sirene, Ansagen,...)
      im mp3-Format, die beim TTS eingebunden werden sollen.</li><br>
      Beispiel:<br>
      <code>attr &lt;SB_device&gt; ttsMP3FileDir /volume1/music/sounds</code><br><br>
    <li>ttsOptions &lt;Optionen&gt;<br>Verschiedene durch Komma getrennte Optionen f&uuml;r die TTS-Ausgabe.
      <br><br>Optionen:<ul>
      <li>debug - Schreibt zus&auml;tzliche Meldungen zum TTS ins Log.</li>
      <li>debugsaverestore - Schreibt zus&auml;tzliche Meldungen zum Speichern/Laden des Playerzustandes ins Log.</li>
      <li>nosaverestore - Zustand des Players nicht sichern und wiederherstellen, dadurch stoppt die Wiedergabe nach Abspielen des TTS.</li>
      <li>forcegroupon - Player in der Gruppe werden eingeschaltet.</li>
      <li>ignorevolumelimit - Attribut volumeLimit f&uuml;r die TTS-Ausgabe ignorieren.</li>
      <li>eventondone - Erzeugt ein Event wenn die Sprachausgabe zu Ende ist.</li>
      </ul></li>
    <li>ttsPrefix &lt;text&gt;<br>
      Text, der vor jede TTS-Ausgabe gehangen wird</li>
    <li>ttsVolume &lt;value&gt;<br>
      Lautst&auml;rke f&uuml;r die TTS-Ausgabe. Standardwert ist die gegenw&auml;rtige Lautst&auml;rke. Wenn das Attribut
      ttsOption ignorevolumelimit angegeben worden ist, wird das eingestellte Lautst&auml;rkelimit bei
      TTS nicht beachtet.</li>
    <li>updateReadingsOnSet true|false<br>
      Wird ein Befehl ausgef&uuml;hrt, werden die Readings erst aktualisiert, wenn die Antwort des LMS eintrifft.
      Ist dieses Attribut auf true gesetzt, wird die Antwort nicht abgewartet, sondern die Readings werden
      soweit wie m&ouml;glich sofort aktualisiert.</li>
    <li>volumeLimit &lt;value&gt;<br>
    Oberer Grenzwert zur Lautst&auml;rkeeinstellung durch FHEM.</li>
    <li>volumeOffset &lt;value&gt;<br>
    Offset der zur Lautstärke die zum LMS geschickt wird addiert wird. Für die Anzeige der aktuellen Lautstärke wird der
    Wert von der vom LMS geschickten Lautstärke abgezogen.</li>
    <li>volumeStep &lt;value&gt;<br>
      Hier wird die Granularit&auml;t der Lautst&auml;rkeregelung festgelegt. Default ist 10</li>
  </ul>
</ul>
=end html_DE

=cut

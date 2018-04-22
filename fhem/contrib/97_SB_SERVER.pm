# ############################################################################
# $Id$
#
#  FHEM Module for Squeezebox Servers
#
# ############################################################################
#
#  used to interact with Squeezebox server
#
# ############################################################################
#
#  Written by bugster_de
#
#  Contributions from: Siggi85, Oliv06, ChrisD, Eberhard
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
#  power            on|off
#  version          the version of the SB Server
#  serversecure     is the CLI port protected with a password?
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
# include for using the perl ping command
use Net::Ping;
use Encode qw(decode encode);           # CD 0009 hinzugefügt
#use Text::Unidecode;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

# this will hold the hash of hashes for all instances of SB_SERVER
my %favorites;
my $favsetstring = "favorites: ";

# this is the buffer for commands, we queue up when server is power=off
my %SB_SERVER_CmdStack;

my @SB_SERVER_AL_PLS;
my @SB_SERVER_FAVS;
my @SB_SERVER_PLS;
my @SB_SERVER_SM;

# include this for the self-calling timer we use later on
use Time::HiRes qw(gettimeofday time);

use constant { true => 1, false => 0 };
use constant { TRUE => 1, FALSE => 0 };
use constant SB_SERVER_VERSION => '0049';

my $SB_SERVER_hasDataDumper = 1;        # CD 0024

sub SB_SERVER_RemoveInternalTimers($);

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
    $hash->{NotifyFn}  = "SB_SERVER_Notify";

    $hash->{AttrList} = "alivetimer maxfavorites ";
    $hash->{AttrList} .= "doalivecheck:true,false ";
    $hash->{AttrList} .= "maxcmdstack ";
    $hash->{AttrList} .= "httpport ";
    $hash->{AttrList} .= "disable:0,1 ";    # CD 0046
    $hash->{AttrList} .= "enablePlugins ";
    $hash->{AttrList} .= "ignoredIPs ignoredMACs internalPingProtocol:icmp,tcp,udp,syn,stream,none ";   # CD 0021 none hinzugefügt
    $hash->{AttrList} .= $readingFnAttributes;

    # CD 0024
    eval "use Data::Dumper";
    $SB_SERVER_hasDataDumper = 0 if($@);
}

# CD 0032 start
sub SB_SERVER_SetAttrList( $ ) {
    my ($hash) = @_;

    my $attrList;
    $attrList = "alivetimer maxfavorites ";
    $attrList .= "doalivecheck:true,false ";
    $attrList .= "maxcmdstack ";
    $attrList .= "httpport ";
    $attrList .= "disable:0,1 ";    # CD 0046
    $attrList .= "ignoredIPs ignoredMACs internalPingProtocol:icmp,tcp,udp,syn,stream,none ";   # CD 0021 none hinzugefügt
    my $applist="enablePlugins";
    if (defined($hash->{helper}{apps})) {
        $applist.=":multiple-strict";
        foreach my $app ( sort keys %{$hash->{helper}{apps}} ) {
            $applist.=",$app";
        }
    }
    $attrList .= "$applist ";

    $attrList .= $readingFnAttributes;

    $modules{$defs{$hash->{NAME}}{TYPE}}{AttrList}=$attrList;
}
# CD 0032 end

# CD 0046 start
# ----------------------------------------------------------------------------
# connect to server
# ----------------------------------------------------------------------------
sub SB_SERVER_TryConnect( $$ ) {
    my ($hash,$reopen) = @_;    # CD 0047 reopen hinzugefügt

    return if ($hash->{CLICONNECTION} eq 'on');
    return if (IsDisabled($hash->{NAME}));
    
    delete $hash->{helper}{disableReconnect} if (defined($hash->{helper}{disableReconnect}));

    if(SB_SERVER_IsValidIPV4($hash->{IP})) {
        return DevIo_OpenDev($hash, $reopen, "SB_SERVER_DoInit");
    } else {
        return DevIo_OpenDev($hash, $reopen, "SB_SERVER_DoInit", \&SB_SERVER_DevIoCallback)
    }
}

sub SB_SERVER_DevIoCallback($$)
{
    my ($hash, $err) = @_;
    my $name = $hash->{NAME};
    
    if($err)
    {
        Log3 $name, 2, "SB_SERVER_DevIoCallback ($name) - unable to connect: $err";
        SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
        DevIo_Disconnected( $hash );    # CD 0048 wird nicht von DevIo gemacht ?
        SB_SERVER_setStates($hash, "disconnected"); # CD 0048 wird nicht von DevIo gemacht ?
    }
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
		"[USER:username] [PASSWORD:password] " .                    # CD 0007 changed PASSWord to PASSWORD
		"[RCC:RCC_Name] [WOL:WOLName] [PRESENCE:PRESENCEName]" );   # CD 0007 added PRESENCE
    }

    # remove the name and our type
    my $name = shift( @a );
    shift( @a );

    # assign safe default values
    $hash->{IP} = "127.0.0.1";
    $hash->{CLIPORT}  = 9090;
    $hash->{WOLNAME} = "none";
    $hash->{helper}{wolSetCmd}=' ';         # CD 0047
    $hash->{helper}{wolSetValue}='on';      # CD 0047
    $hash->{PRESENCENAME} = "none";         # CD 0007
    $hash->{helper}{presenceReading}='state';           # CD 0047
    $hash->{helper}{presenceValuePresent}='present';    # CD 0047
    $hash->{helper}{presenceValueAbsent}='absent';      # CD 0047
    $hash->{RCCNAME} = "none";
    $hash->{USERNAME} = "?";
    $hash->{PASSWORD} = "?";

    # CD 0048 versuchen Namen/Adresse zu säubern
    $a[0] =~ s/^https:\/\///;
    $a[0] =~ s/^http:\/\///;
    $a[0] =~ s/\/$//;

    # CD 0046 Hostnamen statt IP-Adresse zulassen
    $hash->{DeviceName} = $a[0];
    if($a[0] =~ m/^(.+):([0-9]+)$/) {
        $hash->{IP} = $1;
        $hash->{CLIPORT}  = $2;
    } else {
        $hash->{IP} = $a[0];
    }

    my ($user,$password);
    my @newDef;
    
    # CD 0041 start
    my @notifyregexp;
    push @notifyregexp,"global";
    push @notifyregexp,$hash->{NAME};
    # CD 0041 end
    
    # parse the user spec
    foreach( @a ) {
	if( $_ =~ /^(RCC:)(.*)/ ) {
	    $hash->{RCCNAME} = $2;
        push @newDef,$_;
        push @notifyregexp,$2;              # CD 0041
	    next;
	} elsif( $_ =~ /^(WOL:)(.*)/ ) {
        push @newDef,$_;
        my @pp=split ':',$2;                # CD 0047
        $hash->{WOLNAME} = $pp[0];
        $hash->{helper}{wolSetCmd}=$pp[1] if defined($pp[1]);        # CD 0047
        $hash->{helper}{wolSetValue}=$pp[2] if defined($pp[2]);      # CD 0047
	    next;
	} elsif( $_ =~ /^(PRESENCE:)(.*)/ ) {   # CD 0007
        push @newDef,$_;
        my @pp=split ':',$2;                # CD 0047
        $hash->{PRESENCENAME} = $pp[0];     # CD 0007 CD 0047
        $hash->{helper}{presenceReading}=$pp[1] if defined($pp[1]);      # CD 0047
        $hash->{helper}{presenceValuePresent}=$pp[2] if defined($pp[2]); # CD 0047
        $hash->{helper}{presenceValueAbsent}=$pp[3] if defined($pp[3]);  # CD 0047
        push @notifyregexp,$pp[0];              # CD 0041
	    next;                               # CD 0007
	} elsif( $_ =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d{3,5})/ ) {
	    $hash->{IP} = $1;
	    $hash->{CLIPORT}  = $2;
        push @newDef,$_;
	    next;
	} elsif( $_ =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/ ) {
	    $hash->{IP} = $1;
	    $hash->{CLIPORT}  = 9090;
        push @newDef,$_;
	    next;
	} elsif( $_ =~ /^(USER:)(.*)/ ) {
        $user=$2 if($2 ne 'yes');
        $hash->{USERNAME} = 'yes';
        push @newDef,'USER:yes';
	} elsif( $_ =~ /^(PASSWORD:)(.*)/ ) {
        $password=$2 if($2 ne 'yes');
        $hash->{PASSWORD} = 'yes';
        push @newDef,'PASSWORD:yes';
	} else {
        push @newDef,$_;
	    next;
	}
    }

    # CD 0031
    if(defined($user) && defined($password)) {
        SB_SERVER_storePassword($hash,$user,$password);
        $hash->{DEF} = join(' ',@newDef);
    }

    $hash->{LASTANSWER} = "none";

    # used for alive checking of the CLI interface
    $hash->{ALIVECHECK} = "?";

    # the status of the CLI connection (on / off)
    $hash->{CLICONNECTION} = "?";

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

    # the port of the HTTP interface as needed for the coverart url
    # CD 0049 auf $hash->{helper}{httpport} umgestellt
    if( !defined( $attr{$name}{httpport} ) ) {
        $hash->{helper}{httpport}='9000';
    } else {
        $hash->{helper}{httpport}=$attr{$name}{httpport};
    }

    # Preset our readings if undefined
    if (!defined($hash->{OLDDEF})) {
        readingsBeginUpdate( $hash );
        # server on / off
        readingsBulkUpdate( $hash, "power", "?" );
        # the server version
        readingsBulkUpdate( $hash, "serverversion", "?" );
        # is the CLI port secured with password?
        readingsBulkUpdate( $hash, "serversecure", "?" );
        # the maximum number of favorites on the server
        readingsBulkUpdate( $hash, "favoritestotal", "?" );
        # is a scan in progress
        readingsBulkUpdate( $hash, "scanning", "?" );
        # the scan in progress
        readingsBulkUpdate( $hash, "scandb", "?" );
        # the scan already completed
        readingsBulkUpdate( $hash, "scanprogressdone", "?" );
        # the scan already completed
        readingsBulkUpdate( $hash, "scanprogresstotal", "?" );
        # did the last scan fail
        readingsBulkUpdate( $hash, "scanlastfailed", "?" );
        # number of players connected to us
        readingsBulkUpdate( $hash, "players", "?" );
        # number of players connected to mysqueezebox
        readingsBulkUpdate( $hash, "players_mysb", "?" );
        # number of players connected to other servers in our network
        readingsBulkUpdate( $hash, "players_other", "?" );
        # number of albums in the database
        readingsBulkUpdate( $hash, "db_albums", "?" );
        # number of artists in the database
        readingsBulkUpdate( $hash, "db_artists", "?" );
        # number of songs in the database
        readingsBulkUpdate( $hash, "db_songs", "?" );
        # number of genres in the database
        readingsBulkUpdate( $hash, "db_genres", "?" );
        readingsEndUpdate( $hash, 0 );
    }

    # initialize the command stack
    $SB_SERVER_CmdStack{$name}{first_n} = 0;
    $SB_SERVER_CmdStack{$name}{last_n} = 0;
    $SB_SERVER_CmdStack{$name}{cnt} = 0;
    $hash->{CMDSTACK}=0;                # CD 0007

    # assign our IO Device
    $hash->{DeviceName} = "$hash->{IP}:$hash->{CLIPORT}";

    $hash->{helper}{pingCounter}=0;     # CD 0004
    $hash->{helper}{lastPRESENCEstate}='?'; # CD 0023
    $hash->{helper}{onAfterAliveCheck}=0;   # CD 0038
    
    # CD 0009 set module version, needed for reload
    $hash->{helper}{SB_SERVER_VERSION}=SB_SERVER_VERSION;

    if (!defined($hash->{OLDDEF})) {    # CD 0024
        SB_SERVER_LoadSyncGroups($hash) if($SB_SERVER_hasDataDumper==1);
        SB_SERVER_LoadServerStates($hash) if($SB_SERVER_hasDataDumper==1);
        SB_SERVER_FixSyncGroupNames($hash);  # CD 0027
        SB_SERVER_UpdateSgReadings($hash);  # CD 0027
    } else {
        # CD 0038
        if( ReadingsVal($name, "state", "unknown") eq "opened" ) {
            DevIo_SimpleWrite( $hash, "listen 0\n", 0 );
        }
        $hash->{helper}{disableReconnect}=1;
        SB_SERVER_RemoveInternalTimers( $hash );
        readingsSingleUpdate( $hash, "power", "off", 1 );
        SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
        DevIo_Disconnected( $hash );
        SB_SERVER_setStates($hash, "disconnected");
    }

    # open the IO device
    my $ret;

    # CD wait for init_done
    if ($init_done>0){
        delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});          # CD 0007 reconnect immediately after modify
        # CD 0016 start
        #if( ReadingsVal($name, "state", "unknown") eq "opened" ) {  # CD 0038 state statt STATE verwenden
        #    DevIo_CloseDev( $hash );
        #    readingsSingleUpdate( $hash, "power", "?", 0 );
        #    #$hash->{STATE}="disconnected";
        #}
        # CD 0016 end
        if (defined($hash->{OLDDEF})) {
            InternalTimer( gettimeofday() + 1,
               "SB_SERVER_tcb_Alive",
               "SB_SERVER_Alive:$name",
               0 );
            $ret=undef;
        } else {
            $ret= SB_SERVER_TryConnect($hash,0);
        }
    }

    # do and update of the status
    # CD disabled
    #InternalTimer( gettimeofday() + 10,
    # 		   "SB_SERVER_Alive",
    # 		   $hash,
    # 		   0 );

    Log3( $hash, 4, "SB_SERVER_Define: leaving" );

    notifyRegexpChanged($hash, "(". (join '|',@notifyregexp) . ")"); # CD 0041
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
    SB_SERVER_RemoveInternalTimers( $hash );

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
    SB_SERVER_RemoveInternalTimers( $hash );

    return( undef );
}


# ----------------------------------------------------------------------------
#  ReadyFn - called when?
# ----------------------------------------------------------------------------
sub SB_SERVER_Ready( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if (IsDisabled($name));  # CD 0046

    #Log3( $hash, 4, "SB_SERVER_Ready: called" );

    # check for bad/missing password
    if (defined($hash->{helper}{SB_SERVER_LMS_Status})) {
        if (time()-($hash->{helper}{SB_SERVER_LMS_Status})<2) {
            if( ( $hash->{USERNAME} ne "?" ) &&
                ( $hash->{PASSWORD} ne "?" ) ) {
                $hash->{LASTANSWER}='invalid username or password ?';
                Log( 1, "SB_SERVER_Ready($name): invalid username or password ?" );
            } else {
                $hash->{LASTANSWER}='missing username and password ?';
                Log( 1, "SB_SERVER_Ready($name): missing username and password ?" );
            }
            $hash->{NEXT_OPEN}=time()+60;
        }
        delete($hash->{helper}{SB_SERVER_LMS_Status});
    }

    # we need to re-open the device
    if( ReadingsVal($name, "state", "unknown") eq "disconnected" ) {    # CD 0038 state statt STATE verwenden
        if( ( ReadingsVal( $name, "power", "on" ) eq "on" ) ||
            ( ReadingsVal( $name, "power", "on" ) eq "?" ) ) {
            # obviously the first we realize the Server is off
            # clean up first
            if ($hash->{helper}{onAfterAliveCheck}==0) {    # CD 0038
                SB_SERVER_RemoveInternalTimers( $hash );
                readingsSingleUpdate( $hash, "power", "off", 1 );

                $hash->{CLICONNECTION} = "off";                         # CD 0007

                # and signal to our clients
                SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
            }
        }
        # CD added init_done
        if ($init_done>0) {
            # CD 0007 faster reconnect after WOL, use PRESENCE
            my $reconnect=0;
            if(defined($hash->{helper}{WOLFastReconnectUntil})) {
                $hash->{TIMEOUT}=1;
                if (time() > $hash->{helper}{WOLFastReconnectNext}) {
                    delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});
                    $hash->{helper}{WOLFastReconnectNext}=time()+15;
                    $reconnect=1;
                }
                if (time() > $hash->{helper}{WOLFastReconnectUntil}) {
                    delete($hash->{TIMEOUT});
                    delete($hash->{helper}{WOLFastReconnectUntil});
                    delete($hash->{helper}{WOLFastReconnectNext});
                }
            }
            if( ReadingsVal( $hash->{PRESENCENAME}, $hash->{helper}{presenceReading}, $hash->{helper}{presenceValuePresent} ) eq $hash->{helper}{presenceValuePresent} ) {  # CD 0047 erweitert
                $reconnect=1;
            }
            if (($reconnect==1)&&(!defined($hash->{helper}{disableReconnect}))) {
                return( SB_SERVER_TryConnect( $hash , 1 ));
            } else {
                return undef;
            }
        } else {
            return undef;
        }
    }
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
    my $hash = $defs{$name};
    my @args = @_;

    Log( 4, "SB_SERVER_Attr($name): called with @args" );

    if( $args[ 0 ] eq "alivetimer" ) {
        if( $cmd eq "set" ) {
            # CD 0021 start
            RemoveInternalTimer( "SB_SERVER_Alive:$name");
            InternalTimer( gettimeofday() + $args[ 1 ],
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );
            # CD 0021 end
        }
    } elsif( $args[ 0 ] eq "httpport" ) {
        # CD 0015 bei Änderung des Ports diesen an Clients schicken
        if( $cmd eq "set" ) {
            $hash->{helper}{httpport}=$args[ 1 ];
            SB_SERVER_Broadcast( $hash, "SERVER",
                     "IP " . $hash->{IP} . ":" .
                     $args[ 1 ] );
        } elsif( $cmd eq 'del' ) {
            DevIo_SimpleWrite( $hash, "pref httpport ?\n", 0 );               # CD 0049
        }
    } elsif( $args[ 0 ] eq "enablePlugins" ) {
        return "$name: device is disabled, modifying enablePlugins is not possible" if(IsDisabled($name));   # CD 0046
        # CD 0070 bei Änderung Status abfragen
        if( $cmd eq "set" ) {
            if($init_done>0) {
                if(defined($hash->{helper}{apps})) {
                    my @enabledApps=split(',',$args[ 1 ]);
                    foreach my $app (@enabledApps) {
                        if(defined($hash->{helper}{apps}{$app})) {
                            DevIo_SimpleWrite( $hash, ($hash->{helper}{apps}{$app}{cmd})." items 0 200\n", 0 );
                        }
                    }
                }
            }
        } else {
            if(defined($hash->{helper}{apps})) {
                my @enabledApps=split(',',AttrVal($name,'enablePlugins',''));
                foreach my $app (@enabledApps) {
                    if(defined($hash->{helper}{apps}{$app})) {
                        SB_SERVER_Broadcast( $hash, "PLAYLISTS", "FLUSH ".($hash->{helper}{apps}{$app}{cmd}), undef );
                        SB_SERVER_Broadcast( $hash, "FAVORITES", "FLUSH ".($hash->{helper}{apps}{$app}{cmd}), undef );
                    }
                }
            }

            delete($hash->{helper}{apps}) if(defined($hash->{helper}{apps}));
            delete($hash->{helper}{appcmd}) if(defined($hash->{helper}{appcmd}));
            DevIo_SimpleWrite( $hash, "apps 0 200\n", 0 );
        }
    # CD 0046 start
    } elsif( $args[ 0 ] eq 'disable' ) {
        if( $cmd eq 'set' ) {
            if($args[ 1 ] eq '1') {
                DevIo_SimpleWrite( $hash, 'listen 0\n', 0 );
                SB_SERVER_RemoveInternalTimers( $hash );
                DevIo_Disconnected( $hash );
                delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});
                $hash->{CLICONNECTION} = 'off';
                SB_SERVER_setStates($hash, 'disabled');
            } else {
                if ($hash->{CLICONNECTION} ne 'on') {
                    SB_SERVER_setStates($hash, 'disconnected');
                    if(!defined($hash->{helper}{disableReconnect})) {
                        readingsSingleUpdate( $hash, 'power', 'off', 0 );
                        delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});
                        InternalTimer( gettimeofday() + 0.1,
                           "SB_SERVER_tcb_Alive",
                           "SB_SERVER_Alive:$name",
                           0 );
                    }
                }
            }
        } elsif( $cmd eq 'del' ) {
            if ($hash->{CLICONNECTION} ne 'on') {
                SB_SERVER_setStates($hash, 'disconnected');
                if(!defined($hash->{helper}{disableReconnect})) {
                    readingsSingleUpdate( $hash, 'power', 'off', 0 );
                    delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});
                    InternalTimer( gettimeofday() + 0.1,
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );
                }
            }
        }
    # CD 0046 end
    }
    return; # 0033 betateilchen/mahowi
}


# ----------------------------------------------------------------------------
#  Set function
# ----------------------------------------------------------------------------
sub SB_SERVER_Set( $@ ) {
    my ($hash, @a) = @_;
    my $name = $hash->{NAME};

    Log( 4, "SB_SERVER_Set($name): called" );

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
        #$res .= "addToFHEMUpdate:noArg removeFromFHEMUpdate:noArg ";  # CD 0019
        $res .= "syncGroup ";  # CD 0024
        $res .= "save ";  # CD 0025
        #$res .= "getData ";  # CD 0030
        my $out="";
        if (defined($hash->{helper}{savedServerStates})) {
            foreach my $pl ( keys %{$hash->{helper}{savedServerStates}} ) {
                $out.=$pl."," unless ($pl=~/xxxSgTalkxxx/);  # CD 0027 xxxSgTalkxxx hinzugefügt
            }
            $out=~s/,$//;
        }
        $res .= "recall:$out ";

        return( $res );
    } elsif( IsDisabled($name) ) {  # CD 0046
        return;
    } elsif( $cmd eq "on" ) {
	if( ReadingsVal( $name, "power", "off" ) eq "off" ) {
        # the server is off, try to reactivate it
        if( $hash->{WOLNAME} ne "none" ) {
            fhem( "set $hash->{WOLNAME} $hash->{helper}{wolSetCmd} $hash->{helper}{wolSetValue}" ); # CD 0047 Befehl und Wert konfigurierbar
            $hash->{helper}{WOLFastReconnectUntil}=time()+120;   # CD 0007
            $hash->{helper}{WOLFastReconnectNext}=time()+30;    # CD 0007
        }
        if( $hash->{RCCNAME} ne "none" ) {
            fhem( "set $hash->{RCCNAME} on" );
        }
	}

    } elsif( $cmd eq "renew" ) {
        Log3( $hash, 5, "SB_SERVER_Set: renew" );
        delete $hash->{helper}{disableReconnect} if (defined($hash->{helper}{disableReconnect}));   # CD 0038
        if( ReadingsVal( $name, "state", "unknown" ) eq "opened" ) {    # CD 0038
            if((defined($a[0])) && ($a[0] eq 'soft')) {
                DevIo_SimpleWrite( $hash, "listen 1\n", 0 );
            } else {
                DevIo_SimpleWrite( $hash, "listen 0\n", 0 );
                $hash->{helper}{disableReconnect}=1;
                SB_SERVER_RemoveInternalTimers( $hash );
                readingsSingleUpdate( $hash, "power", "off", 1 );
                SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
                DevIo_Disconnected( $hash );
                $hash->{CLICONNECTION} = 'off'; # CD 0046
                InternalTimer( gettimeofday() + 5,
                           "SB_SERVER_tcb_Alive",
                           "SB_SERVER_Alive:$name",
                           0 );
            }
        } else {
            # CD 0038 force open
            readingsSingleUpdate( $hash, "power", "off", 1 );
            delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});
            SB_SERVER_Alive($hash);
        }
    } elsif( $cmd eq "abort" ) {
        DevIo_SimpleWrite( $hash, "listen 0\n", 0 ) if( ReadingsVal( $name, "state", "unknown" ) eq "opened" );
        if((defined($a[0])) && ($a[0] eq 'soft')) {
        } else {
            $hash->{helper}{disableReconnect}=1;
            DevIo_Disconnected( $hash );
            readingsSingleUpdate( $hash, "power", "off", 1 );
            SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
            SB_SERVER_RemoveInternalTimers( $hash );
            $hash->{CLICONNECTION} = 'off'; # CD 0046
        }
    } elsif( $cmd eq "statusRequest" ) {
        Log3( $hash, 5, "SB_SERVER_Set: statusRequest" );
        DevIo_SimpleWrite( $hash, "version ?\n", 0 );
        DevIo_SimpleWrite( $hash, "serverstatus 0 200\n", 0 );
        DevIo_SimpleWrite( $hash, "favorites items 0 " .
                   AttrVal( $name, "maxfavorites", 100 ) . " want_url:1\n",      # CD 0009 url mit abfragen
                   0 );
        DevIo_SimpleWrite( $hash, "playlists 0 200\n", 0 );
        DevIo_SimpleWrite( $hash, "alarm playlists 0 300\n", 0 );               # CD 0011
        DevIo_SimpleWrite( $hash, "pref httpport ?\n", 0 );               # CD 0049
        # CD 0032 start
        DevIo_SimpleWrite( $hash, "apps 0 200\n", 0 );
        if(defined($hash->{helper}{apps})) {
            my @enabledApps=split(',',AttrVal($name,'enablePlugins',''));
            foreach my $app (@enabledApps) {
                if(defined($hash->{helper}{apps}{$app})) {
                    DevIo_SimpleWrite( $hash, ($hash->{helper}{apps}{$app}{cmd})." items 0 200\n", 0 );
                }
            }
        }
        # CD 0032 end
    } elsif( $cmd eq "cliraw" ) {
        # write raw messages to the CLI interface per player
        my $v = join( " ", @a );
        $v .= "\n";
        Log3( $hash, 5, "SB_SERVER_Set: cliraw: $v " );
        DevIo_SimpleWrite( $hash, $v, 0 ); # CD 0016 IOWrite in DevIo_SimpleWrite geändert
    } elsif( $cmd eq "rescan" ) {
        DevIo_SimpleWrite( $hash, $cmd . " " . $a[ 0 ] . "\n", 0 );     # CD 0016 IOWrite in DevIo_SimpleWrite geändert
    # CD 0018 start
    } elsif( $cmd eq "addToFHEMUpdate" ) {
        fhem("update add https://raw.githubusercontent.com/ChrisD70/FHEM-Modules/master/autoupdate/sb/controls_squeezebox.txt");
    } elsif( $cmd eq "removeFromFHEMUpdate" ) {
        fhem("update delete https://raw.githubusercontent.com/ChrisD70/FHEM-Modules/master/autoupdate/sb/controls_squeezebox.txt");
    # CD 0018 end
    # CD 0024 start
    } elsif( $cmd eq "syncGroup" ) {
        return( "at least one parameter is needed" ) if( @a < 1 );

        my $updateReadings=0;

        my $subcmd=shift( @a );

        if($subcmd eq 'addp') {
            return( "not enough parameters" ) if( @a < 2 );
            return( "too many parameters" ) if( @a > 2 );   # CD 0027
            my $players=$a[0];
            my $statename=$a[1];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            SB_SERVER_BuildPlayerList($hash) if(!defined($hash->{helper}{players}));

            if(!defined($hash->{helper}{syncGroups}{$statename})) {
                $hash->{helper}{syncGroups}{$statename}{0}{fhemname}='';
                $hash->{helper}{syncGroups}{$statename}{0}{lmsname}='';
                $hash->{helper}{syncGroups}{$statename}{0}{mac}='';
                $hash->{helper}{syncGroups}{$statename}{0}{c}=1;
                $updateReadings=1;
            }

            for my $pl (split(",",$players)) {
                my $found=0;

                foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
                    if($e ne '') {
                        if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                            if(($pl eq $hash->{helper}{syncGroups}{$statename}{$e}{fhemname})
                                or ($pl eq $hash->{helper}{syncGroups}{$statename}{$e}{lmsname})) {
                                $found=1;
                                last;
                            }
                        }
                    }
                }

                if($found==0) {
                    if(defined($hash->{helper}{players}) && defined($hash->{helper}{players}{$pl})) {
                        my $c=$hash->{helper}{syncGroups}{$statename}{0}{c};

                        $hash->{helper}{syncGroups}{$statename}{$c}{fhemname}=$hash->{helper}{players}{$pl}{fhemname};
                        $hash->{helper}{syncGroups}{$statename}{$c}{lmsname}=$hash->{helper}{players}{$pl}{lmsname};
                        $hash->{helper}{syncGroups}{$statename}{$c}{mac}=$hash->{helper}{players}{$pl}{mac};

                        if($hash->{helper}{syncGroups}{$statename}{0}{fhemname} eq '') {
                            $hash->{helper}{syncGroups}{$statename}{0}{fhemname}=$hash->{helper}{players}{$pl}{fhemname};
                            $hash->{helper}{syncGroups}{$statename}{0}{lmsname}=$hash->{helper}{players}{$pl}{lmsname};
                            $hash->{helper}{syncGroups}{$statename}{0}{mac}=$hash->{helper}{players}{$pl}{mac};
                        }
                        $hash->{helper}{syncGroups}{$statename}{0}{c}+=1;
                        $updateReadings=1;  # CD 0028
                    }
                }
            }
        } elsif($subcmd eq 'removep') {
            return( "not enough parameters" ) if( @a < 2 );
            return( "too many parameters" ) if( @a > 2 );   # CD 0027
            my $players=$a[0];
            my $statename=$a[1];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            if((!defined($hash->{helper}{syncGroups}))||(!defined($hash->{helper}{syncGroups}{$statename}))) {
                return( "sync group $statename not found" );
            }

            SB_SERVER_BuildPlayerList($hash) if(!defined($hash->{helper}{players}));

            for my $pl (split(",",$players)) {
                foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
                    if($e ne '') {
                        if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                            if(($pl eq $hash->{helper}{syncGroups}{$statename}{$e}{fhemname})
                                or ($pl eq $hash->{helper}{syncGroups}{$statename}{$e}{lmsname})) {

                                if($e eq '0') {
                                    # master ?
                                    $hash->{helper}{syncGroups}{$statename}{0}{fhemname}='';
                                    $hash->{helper}{syncGroups}{$statename}{0}{lmsname}='';
                                    $hash->{helper}{syncGroups}{$statename}{0}{mac}='';
                                } else {
                                    delete($hash->{helper}{syncGroups}{$statename}{$e});
                                }
                                $updateReadings=1;  # CD 0028
                            }
                        }
                    }
                }
            }
            # neuen Master suchen ?
            if($hash->{helper}{syncGroups}{$statename}{0}{fhemname} eq '') {
                foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
                    if(($e ne '')&&($e ne '0')) {
                        $hash->{helper}{syncGroups}{$statename}{0}{fhemname}=$hash->{helper}{syncGroups}{$statename}{$e}{fhemname};
                        $hash->{helper}{syncGroups}{$statename}{0}{lmsname}=$hash->{helper}{syncGroups}{$statename}{$e}{lmsname};
                        $hash->{helper}{syncGroups}{$statename}{0}{mac}=$hash->{helper}{syncGroups}{$statename}{$e}{mac};
                        last;
                    }
                }
            }
        } elsif($subcmd eq 'masterp') {
            return( "not enough parameters" ) if( @a < 2 );
            return( "too many parameters" ) if( @a > 2 );   # CD 0027
            my $pl=$a[0];
            my $statename=$a[1];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            if((!defined($hash->{helper}{syncGroups}))||(!defined($hash->{helper}{syncGroups}{$statename}))) {
                return( "sync group $statename not found" );
            }

            foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
                if(($e ne '')&&($e ne '0')) {
                    if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                        if(($pl eq $hash->{helper}{syncGroups}{$statename}{$e}{fhemname})
                            or ($pl eq $hash->{helper}{syncGroups}{$statename}{$e}{lmsname})) {

                            $hash->{helper}{syncGroups}{$statename}{0}{fhemname}=$hash->{helper}{syncGroups}{$statename}{$e}{fhemname};
                            $hash->{helper}{syncGroups}{$statename}{0}{lmsname}=$hash->{helper}{syncGroups}{$statename}{$e}{lmsname};
                            $hash->{helper}{syncGroups}{$statename}{0}{mac}=$hash->{helper}{syncGroups}{$statename}{$e}{mac};

                            $updateReadings=1;
                        }
                    }
                }
            }
        } elsif($subcmd eq 'load') {
            my $poweron=0;

            if($a[0] eq 'poweron') {
                $poweron=1;
                shift(@a);
            }

            return( "not enough parameters" ) if( @a == 0 );

            my $statename=$a[0];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            SB_SERVER_LoadSyncGroup($hash, $statename, $poweron);   # CD 0027
        } elsif($subcmd eq 'delete') {
            my $statename=$a[0];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            delete($hash->{helper}{syncGroups}{$statename}) if(defined($hash->{helper}{syncGroups}{$statename}));
            delete($defs{$name}{READINGS}{"sg$statename"}) if(defined($defs{$name}{READINGS}{"sg$statename"})); # CD 0027
            $updateReadings=1;
        # CD 0027 start
        } elsif($subcmd eq 'deleteall') {
            foreach my $e ( keys %{$hash->{helper}{syncGroups}} ) {
                if($e ne '') {
                    if(defined($hash->{helper}{syncGroups}{$e})) {
                        delete($hash->{helper}{syncGroups}{$e});
                        delete($defs{$name}{READINGS}{"sg$e"}) if(defined($defs{$name}{READINGS}{"sg$e"}));
                        $updateReadings=1;
                    }
                }
            }
        } elsif($subcmd eq 'talk') {
            return "talk already in progress" if(defined($hash->{helper}{sgTalkActivePlayer}));

            my $poweron=0;

            if($a[0] eq 'poweron') {
                $poweron=1;
                shift(@a);
            }

            return( "not enough parameters" ) if( @a < 2 );

            my $statename=shift(@a);
            $statename =~ s/[,;:]/_/g;

            if((!defined($hash->{helper}{syncGroups}))||(!defined($hash->{helper}{syncGroups}{$statename}))) {
                return( "sync group $statename not found" );
            }

            # Zustand speichern, Gruppe laden, talk verzögert an Player absetzen
            SB_SERVER_Save($hash, 'xxxSgTalkxxx');
            SB_SERVER_LoadSyncGroup($hash, $statename, $poweron);
            $hash->{helper}{sgTalkPlayers}=ReadingsVal($name,"sg$statename","-");
            if($hash->{helper}{sgTalkPlayers} eq '-') {
                Log3( $hash, 2, "SB_SERVER_Set($name): sgtalk: no players found for group $statename");
                return "no players found";
            }
            $hash->{helper}{sgTalkActivePlayer}='waiting for power on';
            $hash->{helper}{sgTalkData}=join(' ', @a);
            $hash->{helper}{sgTalkTimeoutPowerOn}=time()+3;
            $hash->{helper}{sgTalkGroup}=$statename;    # CD 0031
            RemoveInternalTimer( "StartTalk:$name");
            InternalTimer( gettimeofday() + 0.01,
               "SB_SERVER_tcb_StartTalk",
               "StartTalk:$name",
               0 );
        } elsif($subcmd eq 'resettts') {
            SB_SERVER_Recall($hash,'xxxSgTalkxxx del');
            delete $hash->{helper}{sgTalkActivePlayer};
        } elsif($subcmd eq 'fixnames') {
            SB_SERVER_FixSyncGroupNames($hash);
            SB_SERVER_UpdateSgReadings($hash);
        # CD 0027 end
        # CD 0031 start
        } elsif($subcmd eq 'volume') {
            return( "not enough parameters" ) if( @a != 2 );

            my $statename=$a[0];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            my $vol=$a[1];

            if (SB_SERVER_isSyncGroupActive($hash,$statename)==1) {
                foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
                    if(($e ne '')&&($e ne '0')) {
                        if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                            fhem("set ".$hash->{helper}{syncGroups}{$statename}{$e}{fhemname}." volume ".$vol." nosync");
                        }
                    }
                }
            } else {
                return "Sync group $statename not active";
            }
        # CD 0031 end
        # CD 0031 nur zu Testzwecken
        } elsif($subcmd eq 'isActive') {
            return( "not enough parameters" ) if( @a == 0 );

            my $statename=$a[0];
            $statename =~ s/[,;:]/_/g;   # CD 0027 Sonderzeichen ersetzen

            return SB_SERVER_isSyncGroupActive($hash, $statename);
        } else {
            return( "unknown command $subcmd" );
        }
        # CD 0031 end
        # CD 0025 start
        if($updateReadings==1) {
            SB_SERVER_UpdateSgReadings($hash);
        }
        # CD 0025 end
    # CD 0024 end
    # CD 0025 start
    } elsif( $cmd eq "save" ) {
        if(defined($a[0])) {
            SB_SERVER_Save($hash, $a[0]);
        } else {
            SB_SERVER_Save($hash, "");
        }
    } elsif( $cmd eq "recall" ) {
        if(defined($a[0])) {
            SB_SERVER_Recall($hash, $a[0]);
        } else {
            SB_SERVER_Recall($hash, "");
        }
    # CD 0025 end
    # CD 0030 start
    } elsif( $cmd eq "getData" ) {
        return( "not enough parameters" ) if( @a < 3 );
        $hash->{helper}{getData}{$a[2]}{format}=$a[0];
        $hash->{helper}{getData}{$a[2]}{reading}=$a[1];

        if($a[2] eq 'artists') {
            DevIo_SimpleWrite( $hash, "artists 0 5000\n", 0 );
        }
    # CD 0030 end
    } else {
	;
    }

    return( undef );
}

# CD 0027 start
sub SB_SERVER_tcb_StartTalk($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if (IsDisabled($name));  # CD 0046
    return unless defined($hash->{helper}{sgTalkActivePlayer});

    # alle gesynced ?
    if (SB_SERVER_isSyncGroupActive($hash,$hash->{helper}{sgTalkGroup})==1) {
        # eingeschalteten Player suchen
        my @pls=split(',',$hash->{helper}{sgTalkPlayers});
        foreach my $pl (@pls) {
            if(ReadingsVal($pl,'power','0') eq 'on') {
                $hash->{helper}{sgTalkActivePlayer}=$pl;
                my $phash = $defs{$pl}; # CD 0029
                $phash->{helper}{sgTalkActive}=1;   # CD 0029
                fhem "set $pl talk " . $hash->{helper}{sgTalkData};
                last;
            }
        }
    }

    # keinen eingeschalteten Player gefunden
    if($hash->{helper}{sgTalkTimeoutPowerOn}<time()) {
        # kein Player eingeschaltet, abbrechen
        Log3( $hash, 1, "SB_SERVER_tcb_StartTalk($name): timeout waiting for player power on and sync, aborting");
        SB_SERVER_Recall($hash,'xxxSgTalkxxx del');
        delete $hash->{helper}{sgTalkActivePlayer};
    } else {
        # warten...
        if($hash->{helper}{sgTalkActivePlayer} eq 'waiting for power on') {
            RemoveInternalTimer( "StartTalk:$name");
            InternalTimer( gettimeofday() + 0.2,
               "SB_SERVER_tcb_StartTalk",
               "StartTalk:$name",
               0 );
        }
    }
}

# CD 0031 start
sub SB_SERVER_isSyncGroupActive($$) {
    my ($hash,$statename) = @_;
    my $name = $hash->{NAME};

    if((!defined($hash->{helper}{syncGroups}))||(!defined($hash->{helper}{syncGroups}{$statename}))) {
        return 0;
    }

    my $master=$hash->{helper}{syncGroups}{$statename}{0}{lmsname};
    my $isActive=1;

    foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
        if(($e ne '')&&($e ne '0')) {
            if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                $isActive=0 if (InternalVal($hash->{helper}{syncGroups}{$statename}{$e}{fhemname},'SYNCMASTERPN','?') ne $master)
            }
        }
    }
    return $isActive;
}
# CD 0031 end

sub SB_SERVER_LoadSyncGroup($$$) {
    my ($hash,$statename,$poweron) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 3, "SB_SERVER_LoadSyncGroup($name): load: $statename, poweron: $poweron");

    if((!defined($hash->{helper}{syncGroups}))||(!defined($hash->{helper}{syncGroups}{$statename}))) {
        return( "sync group $statename not found" );
    }

    # unsync all
    foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
        if(($e ne '')&&($e ne '0')) {
            if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                SB_SERVER_Write( $hash, $hash->{helper}{syncGroups}{$statename}{$e}{mac}." sync -\n", "" );
            }
        }
    }

    # sync with new master
    foreach my $e ( keys %{$hash->{helper}{syncGroups}{$statename}} ) {
        if(($e ne '')&&($e ne '0')) {
            if(defined($hash->{helper}{syncGroups}{$statename}{$e})) {
                if($hash->{helper}{syncGroups}{$statename}{$e}{mac} ne $hash->{helper}{syncGroups}{$statename}{0}{mac}) {
                    SB_SERVER_Write( $hash, $hash->{helper}{syncGroups}{$statename}{0}{mac}." sync ".$hash->{helper}{syncGroups}{$statename}{$e}{mac}."\n", "" );
                }
                SB_SERVER_Write( $hash, $hash->{helper}{syncGroups}{$statename}{$e}{mac}." power 1\n", "" ) if($poweron==1);
            }
        }
    }
}

sub SB_SERVER_FixSyncGroupNames($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    foreach my $e ( keys %{$hash->{helper}{syncGroups}} ) {
        if($e ne '') {
            if(defined($hash->{helper}{syncGroups}{$e})) {
                if($e =~ /[,;:\s]/) {
                    my $n=$e;
                    $n =~ s/[,;:\s]/_/g;
                    $hash->{helper}{syncGroups}{$n}=$hash->{helper}{syncGroups}{$e};
                    delete $hash->{helper}{syncGroups}{$e};
                }
            }
        }
    }
}

sub SB_SERVER_UpdateSgReadings($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $sg='';

    readingsBeginUpdate( $hash );

    foreach my $e ( keys %{$hash->{helper}{syncGroups}} ) {
        if($e ne '') {
            if(defined($hash->{helper}{syncGroups}{$e})) {
                $sg.="$e,";

                my $sgd='';

                foreach my $p ( keys %{$hash->{helper}{syncGroups}{$e}} ) {
                    if($p ne '') {
                        if(defined($hash->{helper}{syncGroups}{$e}{$p})) {
                            if(($hash->{helper}{syncGroups}{$e}{$p}{fhemname} ne $hash->{helper}{syncGroups}{$e}{0}{fhemname})||($p eq '0')) { # CD 0029
                                $sgd.=$hash->{helper}{syncGroups}{$e}{$p}{fhemname} . ",";
                            }
                        }
                    }
                }
                $sgd =~ s/,$//;

                if($sgd eq '') {
                    delete($defs{$name}{READINGS}{"sg$e"}) if(defined($defs{$name}{READINGS}{"sg$e"}));
                } else {
                    if(ReadingsVal($name,"sg$e","x") ne $sgd) {
                        readingsBulkUpdate( $hash, "sg$e", $sgd );
                    }
                }
            }
        }
    }
    $sg =~ s/,$//;
    if($sg eq '') {
        delete($defs{$name}{READINGS}{"syncGroups"}) if(defined($defs{$name}{READINGS}{"syncGroups"}));
    } else {
        readingsBulkUpdate( $hash, "syncGroups", $sg );
    }
    readingsEndUpdate( $hash, 1 );
}
# CD 0027 end

# ----------------------------------------------------------------------------
# Read
# called from the global loop, when the select for hash->{FD} reports data
# ----------------------------------------------------------------------------
sub SB_SERVER_Read( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    return if (IsDisabled($name));  # CD 0046

    #my $start = time;   # CD 0019

    Log3( $hash, 4, "SB_SERVER_Read($name): called" );
    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );
    Log3( $hash, 5, "New Squeezebox Server Read cycle starts here" );
    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );

    my $buf = DevIo_SimpleRead( $hash );

    if( !defined( $buf ) ) {
        return( "" );
    }

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
        #Log3( $hash, 5, "SB_SERVER_Read($name): please implement the " .   # CD 0009 Meldung deaktiviert
        #      "sending of the CMDStack." );                                # CD 0009 Meldung deaktiviert
    }

    #my $t1 = time;   # CD 0020

    # if there are remains from the last time, append them now
    $buf = $hash->{PARTIAL} . $buf;

    $buf = uri_unescape( $buf );
    Log3( $hash, 6, "SB_SERVER_Read: the buf: $buf" );  # CD TEST 6

    # CD 0021 start - Server lebt noch, alivetimer neu starten
    RemoveInternalTimer( "SB_SERVER_Alive:$name");
    InternalTimer( gettimeofday() +
               AttrVal( $name, "alivetimer", 10 ),
               "SB_SERVER_tcb_Alive",
               "SB_SERVER_Alive:$name",
               0 );
    # CD 0021 end

    #my $t2 = time;   # CD 0020

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

    #my $t3 = time;   # CD 0020

    # and dispatch the rest
    foreach( @cmds ) {
        my $t31=time;   # CD 0020
        # double check complete line
        my $lastchar = substr( $_, -1);
        SB_SERVER_DispatchCommandLine( $hash, $_  );
        # CD 0020 start
        if((time-$t31)>0.5) {
            Log3($hash,3,"SB_SERVER_Read($name), time:".int((time-$t31)*1000)."ms cmd: ".$_);
        }
        # CD 0020 end
    }

    #my $t4 = time;   # CD 0020

    # CD 0009 check for reload of newer version
    $hash->{helper}{SB_SERVER_VERSION}=0 if (!defined($hash->{helper}{SB_SERVER_VERSION}));     # CD 0012
    if ($hash->{helper}{SB_SERVER_VERSION} ne SB_SERVER_VERSION)
    {
        Log3( $hash, 1,"SB_SERVER_Read: SB_SERVER_VERSION changed from ".$hash->{helper}{SB_SERVER_VERSION}." to ".SB_SERVER_VERSION);  # CD 0012
        $hash->{helper}{SB_SERVER_VERSION}=SB_SERVER_VERSION;
        DevIo_SimpleWrite( $hash, "version ?\n", 0 );
        DevIo_SimpleWrite( $hash, "serverstatus 0 200\n", 0 );
        DevIo_SimpleWrite( $hash, "favorites items 0 " .
                   AttrVal( $name, "maxfavorites", 100 ) . " want_url:1\n",        # CD 0009 url mit abfragen
                   0 );
        DevIo_SimpleWrite( $hash, "pref httpport ?\n", 0 );     # CD 0049
        DevIo_SimpleWrite( $hash, "playlists 0 200\n", 0 );
    }
    # CD 0009 end

    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );
    Log3( $hash, 5, "Squeezebox Server Read cycle ends here" );
    Log3( $hash, 5, "+++++++++++++++++++++++++++++++++++++++++++++++++++++" );

    # CD 0019 start
    #my $end   = time;
    #if (($end - $start)>1) {
    #    Log3( $hash, 0, "SB_SERVER_Read($name), times: ".int(($t1 - $start)*1000)." ".int(($t2 - $t1)*1000)." ".int(($t3 - $t2)*1000)." ".int(($t4 - $t3)*1000)." ".int(($end - $start)*1000)." nCmds: ".$#cmds );
    #}
    # CD 0019 end

    return( undef );
}

# CD 0027 start
sub SB_SERVER_tcb_RecallAfterTalk($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return unless defined($hash->{helper}{sgTalkActivePlayer});

    SB_SERVER_Recall($hash,'xxxSgTalkxxx del');

    delete $hash->{helper}{sgTalkActivePlayer};
}
# CD 0027 end

# ----------------------------------------------------------------------------
# called by the clients to send data
# ----------------------------------------------------------------------------
sub SB_SERVER_Write( $$$ ) {
    my ( $hash, $fn, $msg ) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_Write($name): called with FN:$fn" ); # unless($fn=~m/\?/);  # CD TEST 4

    return if (IsDisabled($name));  # CD 0046

    if( !defined( $fn ) ) {
	return( undef );
    }

    if( defined( $msg ) ) {
	Log3( $hash, 4, "SB_SERVER_Write: MSG:$msg" );
    }

    # CD 0012 fhemrelay Meldungen nicht an den LMS schicken sondern direkt an Dispatch übergeben
    if($fn =~ m/fhemrelay/) {
        # CD 0027 start
        if ($fn =~ m/ttsdone/) {
            my @a=split(' ',$fn);

            # sg talk auf Player aktiv ?
            if(defined($hash->{helper}{sgTalkActivePlayer})) {
                if($a[0] eq $hash->{helper}{sgTalkActivePlayer}) {
                    # recall auslösen
                    RemoveInternalTimer( "RecallAfterTalk:$name");
                    InternalTimer( gettimeofday() + 0.01,
                       "SB_SERVER_tcb_RecallAfterTalk",
                       "RecallAfterTalk:$name",
                       0 );
                }
            }
        } else {
        # CD 0027 end
            SB_SERVER_DispatchCommandLine( $hash, $fn );
        }
        return( undef );
    }

    if( ReadingsVal( $name, "serversecure", "0" ) eq "1" ) {
	if( ( $hash->{USERNAME} ne "?" ) && ( $hash->{PASSWORD} ne "?" ) ) {
	    # we need to send username and password first
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

    return if (IsDisabled($name));  # CD 0046

    Log3( $hash, 4, "SB_SERVER_DoInit($name): called" );

    if( !$hash->{TCPDev} ) {
        Log3( $hash, 2, "SB_SERVER_DoInit: no TCPDev available?" );     # CD 0009 level 5->2
        DevIo_CloseDev( $hash );
    }

    my $state=ReadingsVal($name, "state", "unknown");
    
    Log3( $hash, 3, "SB_SERVER_DoInit($name): state: " . $state . " power: ". ReadingsVal( $name, "power", "X" ));    # CD 0009 level 2 -> 3 # CD 0038 state statt STATE verwenden

    if( $state eq "disconnected" ) {    # CD 0038 state statt STATE verwenden
        # server is off after FHEM start, broadcast to clients
        if( ( ReadingsVal( $name, "power", "on" ) eq "on" ) ||
            ( ReadingsVal( $name, "power", "on" ) eq "?" ) ) {
            Log3( $hash, 3, "SB_SERVER_DoInit($name): " .                   # CD 0009 level 2 -> 3
              "SB-Server in hibernate / suspend?." );

              # obviously the first we realize the Server is off
            readingsSingleUpdate( $hash, "power", "off", 1 );

            # and signal to our clients
            SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );
            SB_SERVER_Broadcast( $hash, "SERVER",
                     "IP " . $hash->{IP} . ":" .
                     $hash->{helper}{httpport} );
        }
        return( 1 );
    } elsif( $state eq "opened" ) { # CD 0038 state statt STATE verwenden
        $hash->{ALIVECHECK} = "?";
        $hash->{CLICONNECTION} = "on";
        if( ( ReadingsVal( $name, "power", "on" ) eq "off" ) ||
            ( ReadingsVal( $name, "power", "on" ) eq "?" ) ||
            ($hash->{helper}{onAfterAliveCheck}==1)) {                       # CD 0038
            Log3( $hash, 3, "SB_SERVER_DoInit($name): " .                   # CD 0009 level 2 -> 3
              "SB-Server is back again." );

            # CD 0007 cleanup
            if(defined($hash->{helper}{WOLFastReconnectUntil})) {
                    delete($hash->{TIMEOUT});
                    delete($hash->{helper}{WOLFastReconnectUntil});
                    delete($hash->{helper}{WOLFastReconnectNext});
            }
            $hash->{helper}{pingCounter}=0;                                 # CD 0007

            SB_SERVER_Broadcast( $hash, "SERVER",
                     "IP " . $hash->{IP} . ":" .
                     $hash->{helper}{httpport} );
            $hash->{helper}{doBroadcast}=1;                                 # CD 0007

            SB_SERVER_LMS_Status( $hash );
            if( AttrVal( $name, "doalivecheck", "false" ) eq "false" ) {
            readingsSingleUpdate( $hash, "power", "on", 1 );
            #SB_SERVER_Broadcast( $hash, "SERVER",  "ON" );                 # CD 0007
            return( 0 );

            } elsif( AttrVal( $name, "doalivecheck", "false" ) eq "true" ) {
            # start the alive checking mechanism
            # CD 0020 SB_SERVER_tcb_Alive verwenden
            RemoveInternalTimer( "SB_SERVER_Alive:$name");
            InternalTimer( gettimeofday() +
                       AttrVal( $name, "alivetimer", 10 ),
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );
            return( 0 );

            } else {
            Log3( $hash, 2, "SB_SERVER_DoInit: doalivecheck has " .
                  "wrong value" );
            return( 1 );
            }

        }

    } else {
	# what the f...
	Log3( $hash, 2, "SB_SERVER_DoInit: unclear status reported" );
	return( 1 );
    }

	#Log3( $hash, 3, "SB_SERVER_DoInit: something went wrong!" );        # CD 0008 nur für Testzwecke 0009 deaktiviert
    #return(0);                                                          # CD 0008 nur für Testzwecke 0009 deaktiviert
    return( 1 );
}

# CD 0032 start
# ----------------------------------------------------------------------------
#  Parse return of app items query
# ----------------------------------------------------------------------------
sub SB_SERVER_ParseAppResponse( $$ ) {
    my ( $hash, $buf ) = @_;
    my $name = $hash->{NAME};
    my $appresponse=0;

    if($buf=~m/items/) {
        my @data=split(' ',$buf);
        #Log 0,$buf;
        if(defined($hash->{helper}{appcmd}) && defined($hash->{helper}{appcmd}{$data[1]})) {
            my $appcmd=$data[1];
            my $appname=$hash->{helper}{appcmd}{$appcmd}{name};
            my $nameactive=0;
            my $save=0;

            if($buf=~m/item_id:/) {
                # app subitems ...
                my $id="0";
                my $pname="";
                my $dest=0;
                my $broadcastPlaylists=0;
                my $broadcastFavorites=0;

                foreach (@data) {
                    if( $_ =~ /^(item_id:)(.*)/ ) {
                        if(defined($hash->{helper}{appcmd}{$appcmd}{playlistsId}) && ($hash->{helper}{appcmd}{$appcmd}{playlistsId} eq $2)) {
                            $dest=1;
                        }
                        if(defined($hash->{helper}{appcmd}{$appcmd}{favoritesId}) && ($hash->{helper}{appcmd}{$appcmd}{favoritesId} eq $2)) {
                            $dest=2;
                        }
                    } elsif( $_ =~ /^(id:)(.*)/ ) {
                        # new entry
                        if($save==1) {
                            if($dest==1) {
                                if(defined($hash->{helper}{appcmd}{$appcmd}{playlists}) && defined($hash->{helper}{appcmd}{$appcmd}{playlists}{$id})) {
                                    $broadcastPlaylists=1 if($hash->{helper}{appcmd}{$appcmd}{playlists}{$id}{name} ne $pname);
                                } else {
                                    $broadcastPlaylists=1;
                                }
                                $hash->{helper}{appcmd}{$appcmd}{playlists}{$id}{name}=$pname;
                            }
                            if($dest==2) {
                                # Bug in squeezecloud ? Element 3.2 funktioniert nicht
                                if($appcmd eq 'squeezecloud') {
                                    if($id-int($id)>0.19) {
                                        $id+=0.1;
                                    }
                                }

                                if(defined($hash->{helper}{appcmd}{$appcmd}{favorites}) && defined($hash->{helper}{appcmd}{$appcmd}{favorites}{$id})) {
                                    $broadcastFavorites=1 if($hash->{helper}{appcmd}{$appcmd}{favorites}{$id}{name} ne $pname);
                                } else {
                                    $broadcastFavorites=1;
                                }
                                $hash->{helper}{appcmd}{$appcmd}{favorites}{$id}{name}=$pname;
                            }
                            $save=0;
                        }
                        $id=$2;
                        $nameactive=0;
                        next;
                    } elsif( $_ =~ /^(name:)(.*)/ ) {
                        $pname=$2;
                        $save=1;
                        $nameactive=1;
                        next;
                    } elsif( $_ =~ /^(type:)(.*)/ ) {
                        $nameactive=0;
                    } else {
                        $pname.=" $_" if($nameactive==1);
                    }
                }
                if($save==1) {
                    if($dest==1) {
                        if(defined($hash->{helper}{appcmd}{$appcmd}{playlists}) && defined($hash->{helper}{appcmd}{$appcmd}{playlists}{$id})) {
                            $broadcastPlaylists=1 if($hash->{helper}{appcmd}{$appcmd}{playlists}{$id}{name} ne $pname);
                        } else {
                            $broadcastPlaylists=1;
                        }
                        $hash->{helper}{appcmd}{$appcmd}{playlists}{$id}{name}=$pname;
                    }
                    if($dest==2) {
                        # Bug in squeezecloud ? Element 3.2 funktioniert nicht
                        if($appcmd eq 'squeezecloud') {
                            if($id-int($id)>0.19) {
                                $id+=0.1;
                            }
                        }

                        if(defined($hash->{helper}{appcmd}{$appcmd}{favorites}) && defined($hash->{helper}{appcmd}{$appcmd}{favorites}{$id})) {
                            $broadcastFavorites=1 if($hash->{helper}{appcmd}{$appcmd}{favorites}{$id}{name} ne $pname);
                        } else {
                            $broadcastFavorites=1;
                        }
                        $hash->{helper}{appcmd}{$appcmd}{favorites}{$id}{name}=$pname;
                    }
                }
                if($broadcastPlaylists==1) {
                    SB_SERVER_Broadcast( $hash, "PLAYLISTS", "FLUSH $appcmd", undef );
                    RemoveInternalTimer( "SB_SERVER_tcb_SendPlaylists:$name");
                    foreach my $pl ( keys %{$hash->{helper}{appcmd}{$appcmd}{playlists}} ) {
                        my $plname=$hash->{helper}{appcmd}{$appcmd}{playlists}{$pl}{name};
                        $plname=~s/ /_/g;
                        $plname=~s/[^[:ascii:]]//g;
                        #$plname=unidecode($plname);
                        my $uniquename = SB_SERVER_FavoritesName2UID( $plname );
                        push @SB_SERVER_PLS, "ADD $plname $pl $uniquename $appcmd";
                    }
                    if(scalar(@SB_SERVER_PLS)>0) {
                        InternalTimer( gettimeofday() + 0.01,
                                   "SB_SERVER_tcb_SendPlaylists",
                                   "SB_SERVER_tcb_SendPlaylists:$name",
                                   0 );
                    }
                }
                if($broadcastFavorites==1) {
                    SB_SERVER_Broadcast( $hash, "FAVORITES", "FLUSH $appcmd", undef );
                    RemoveInternalTimer( "SB_SERVER_tcb_SendFavorites:$name");
                    foreach my $pl ( keys %{$hash->{helper}{appcmd}{$appcmd}{favorites}} ) {
                        my $plname=$hash->{helper}{appcmd}{$appcmd}{favorites}{$pl}{name};
                        $plname=~s/ /_/g;
                        $plname=~s/[^[:ascii:]]//g;
                        #$plname=unidecode($plname);
                        my $uniquename = SB_SERVER_FavoritesName2UID( $plname );
                        push @SB_SERVER_FAVS, "ADD $name $pl $uniquename url $appcmd $plname";
                    }
                    if(scalar(@SB_SERVER_FAVS)>0) {
                        InternalTimer( gettimeofday() + 0.01,
                                   "SB_SERVER_tcb_SendFavorites",
                                   "SB_SERVER_tcb_SendFavorites:$name",
                                   0 );
                    }
                }
            } else {
                # app items ...
                my $id=0;
                my $iname="";
                my $type="";
                my $isaudio=0;
                my $hasitems=0;

                foreach (@data) {
                    if( $_ =~ /^(id:)(.*)/ ) {
                        # new entry
                        if($save==1) {
                            $hash->{helper}{appcmd}{$appcmd}{items}{$id}{name}=$iname;
                            $hash->{helper}{appcmd}{$appcmd}{items}{$id}{type}=$type;
                            $hash->{helper}{appcmd}{$appcmd}{items}{$id}{isaudio}=$isaudio;
                            $hash->{helper}{appcmd}{$appcmd}{items}{$id}{hasitems}=$hasitems;
                            $hash->{helper}{appcmd}{$appcmd}{playlistsId}=$id if($iname eq 'Playlists');
                            $hash->{helper}{appcmd}{$appcmd}{playlistsId}=$id if($iname eq 'Wiedergabelisten'); # CD 0035
                            $hash->{helper}{appcmd}{$appcmd}{playlistsId}=$id if($iname eq 'Listes de lecture'); # CD 0036
                            $hash->{helper}{appcmd}{$appcmd}{favoritesId}=$id if($iname eq 'Likes');
                            $hash->{helper}{appcmd}{$appcmd}{favoritesId}=$id if($iname eq 'Favorites');
                            $save=0;
                        }
                        $id=$2;
                        $nameactive=0;
                        next;
                    } elsif( $_ =~ /^(type:)(.*)/ ) {
                        $type=$2;
                        $save=1;
                        $nameactive=0;
                        next;
                    } elsif( $_ =~ /^(isaudio:)(.*)/ ) {
                        $isaudio=$2;
                        $save=1;
                        $nameactive=0;
                        next;
                    } elsif( $_ =~ /^(hasitems:)(.*)/ ) {
                        $hasitems=$2;
                        $save=1;
                        $nameactive=0;
                        next;
                    } elsif( $_ =~ /^(name:)(.*)/ ) {
                        $iname=$2;
                        $save=1;
                        $nameactive=1;
                        next;
                    } elsif( $_ =~ /^(count:)(.*)/ ) {
                        if($2==0) {
                            delete $hash->{helper}{appcmd}{$appcmd}{items} if defined($hash->{helper}{appcmd}{$appcmd}{items});
                            $save=0;
                            Log3( $hash, 2, "SB_SERVER_ParseAppResponse($name): no valid data for $appname: $buf" );
                            last;
                        }
                    } else {
                        $iname.=" $_" if($nameactive==1);
                    }
                }
                if($save==1) {
                    $hash->{helper}{appcmd}{$appcmd}{items}{$id}{name}=$iname;
                    $hash->{helper}{appcmd}{$appcmd}{items}{$id}{type}=$type;
                    $hash->{helper}{appcmd}{$appcmd}{items}{$id}{isaudio}=$isaudio;
                    $hash->{helper}{appcmd}{$appcmd}{items}{$id}{hasitems}=$hasitems;
                    $hash->{helper}{appcmd}{$appcmd}{playlistsId}=$id if($iname eq 'Playlists');
                    $hash->{helper}{appcmd}{$appcmd}{favoritesId}=$id if($iname eq 'Likes');
                    $hash->{helper}{appcmd}{$appcmd}{favoritesId}=$id if($iname eq 'Favorites');
                }
                if(defined($hash->{helper}{appcmd}{$appcmd}{playlistsId})) {
                    DevIo_SimpleWrite( $hash, "$appcmd items 0 200 item_id:".($hash->{helper}{appcmd}{$appcmd}{playlistsId})."\n", 0 );
                }
                if(defined($hash->{helper}{appcmd}{$appcmd}{favoritesId})) {
                    DevIo_SimpleWrite( $hash, "$appcmd items 0 200 item_id:".($hash->{helper}{appcmd}{$appcmd}{favoritesId})." want_url:1\n", 0 );
                }
            }
            $appresponse=1;
        }
    }
    return $appresponse;
}
# CD 0032 end

# CD 0044 start
# ----------------------------------------------------------------------------
#  used for checking, if the string contains a valid IP v4 (decimal) address
# ----------------------------------------------------------------------------
sub SB_SERVER_IsValidIPV4( $ ) {
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
# CD 0044 end

# CD 0041 start
# ----------------------------------------------------------------------------
#  used for checking if the string contains a valid MAC adress
# ----------------------------------------------------------------------------
sub SB_SERVER_IsValidMAC( $ ) {
    my $instr = shift( @_ );

    my $d = "[0-9A-Fa-f]";
    my $dd = "$d$d";

    if( $instr =~ /($dd([:-])$dd(\2$dd){4})/og ) {
      if( $instr =~ /^(00[:-]){5}(00)$/) {
        return( 0 );
      } else {
        return( 1 );
      }
    } else {
        return( 0 );
    }
}
# CD 0041 end

# ----------------------------------------------------------------------------
#  Dispatch every single line of commands
# ----------------------------------------------------------------------------
sub SB_SERVER_DispatchCommandLine( $$ ) {
    my ( $hash, $buf ) = @_;
    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_DispatchCommandLine($name): Line:$buf..." );

    return if (IsDisabled($name));  # CD 0046

    # try to extract the first answer to the SPACE
    my $indx = index( $buf, " " );
    my $id1  = substr( $buf, 0, $indx );

    # is the first return value a player ID?
    # Player ID is MAC adress, hence : included
    my @id = split( ":", $id1 );
    
    if(( SB_SERVER_IsValidMAC($id1) == 1 ) || ( SB_SERVER_IsValidIPV4($id1) == 1)) { # CD 0041 SB_SERVER_IsValidMAC verwenden # CD 0044 auf IP-Adresse prüfen
        # CD 0032 start
        # check for app response
        if(SB_SERVER_ParseAppResponse($hash,$buf)==0) {
            # we have received a return for a dedicated player

            # create the fhem specific unique id
            my $playerid = join( "", @id );
            Log3( $hash, 5, "SB_SERVER_DispatchCommandLine: fhem-id: $playerid" );

            # create the commands
            my $cmds = substr( $buf, $indx + 1 );
            Log3( $hash, 5, "SB_SERVER__DispatchCommandLine: commands: $cmds" );
            Dispatch( $hash, "SB_PLAYER:$playerid:$cmds", undef );
        }
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

    Log3( $hash, 4, "SB_SERVER_ParseCmds($name): called" );

    my @args = split( " ", $instr );

    $hash->{LASTANSWER} = "@args";

    my $cmd = shift( @args );

    # CD 0007 start
    if (defined($hash->{helper}{doBroadcast})) {
	    SB_SERVER_Broadcast( $hash, "SERVER", "ON" );
	    SB_SERVER_Broadcast( $hash, "SERVER",
				 "IP " . $hash->{IP} . ":" .
                 $hash->{helper}{httpport} );
        delete ($hash->{helper}{doBroadcast});
    }
    # CD 0007 end

    if( $cmd eq "version" ) {
	readingsSingleUpdate( $hash, "serverversion", $args[ 1 ], 0 );

	if( ReadingsVal( $name, "power", "off" ) eq "off" ) {
	    # that also means the server returned from being away
	    readingsSingleUpdate( $hash, "power", "on", 1 );
	    # signal our players
	    SB_SERVER_Broadcast( $hash, "SERVER", "ON" );
	    SB_SERVER_Broadcast( $hash, "SERVER",
				 "IP " . $hash->{IP} . ":" .
                 $hash->{helper}{httpport} );
	}

    } elsif( $cmd eq "pref" ) {
	if( $args[ 0 ] eq "authorize" ) {
	    readingsSingleUpdate( $hash, "serversecure", $args[ 1 ], 0 );
	    if( $args[ 1 ] eq "1" ) {
		# username and password is required
        # CD 0007 zu spät, login muss als erstes gesendet werden, andernfalls bricht der Server die Verbindung sofort ab
		if( ( $hash->{USERNAME} ne "?" ) &&
		    ( $hash->{PASSWORD} ne "?" ) ) {
            my ($user,$password)=SB_SERVER_readPassword($hash); # CD 0031
            if(defined($user)) {
                DevIo_SimpleWrite( $hash, "login " .
                           $user . " " .
                           $password . "\n",
                           0 );
            } else {
                Log3( $hash, 3, "SB_SERVER_ParseCmds($name): login " .
                  "required but no username and password specified" );
            }
		} else {
		    Log3( $hash, 3, "SB_SERVER_ParseCmds($name): login " .
			  "required but no username and password specified" );
		}
		# next step is to wait for the answer of the LMS server
	    } elsif( $args[ 1 ] eq "0" ) {
		# no username password required, go ahead directly
		#SB_SERVER_LMS_Status( $hash );
	    } else {
		Log3( $hash, 3, "SB_SERVER_ParseCmds($name): unkown " .
		      "result for authorize received. Should be 0 or 1" );
	    }
	}
    # CD 0049
        if( $args[ 0 ] eq "httpport" ) {
            if (defined($args[1]) && ($args[1] =~ /^([0-9])*/ )) {
                if(!defined(AttrVal( $name, "httpport", undef ))) {
                    $hash->{helper}{httpport}=$args[1]; 
                    SB_SERVER_Broadcast( $hash, "SERVER",
                         "IP " . $hash->{IP} . ":" .
                         $hash->{helper}{httpport} );
                }
            }
        }    
    } elsif( $cmd eq "login" ) {
	if( ( $args[ 1 ] eq $hash->{USERNAME} ) &&
	    ( $args[ 2 ] eq "******" ) ) {
	    # login has been succesful, go ahead
	    SB_SERVER_LMS_Status( $hash );
	}


    } elsif( $cmd eq "fhemalivecheck" ) {
	$hash->{ALIVECHECK} = "received";
	Log3( $hash, 4, "SB_SERVER_ParseCmds($name): alivecheck received" );

    } elsif( $cmd eq "favorites" ) {
	if( $args[ 0 ] eq "changed" ) {
	    Log3( $hash, 4, "SB_SERVER_ParseCmds($name): favorites changed" );
	    # we need to trigger the favorites update here
	    DevIo_SimpleWrite( $hash, "favorites items 0 " .
			       AttrVal( $name, "maxfavorites", 100 ) .
			       " want_url:1\n", 0 );           # CD 0009 url mit abfragen
        DevIo_SimpleWrite( $hash, "alarm playlists 0 300\n", 0 );       # CD 0011
	} elsif( $args[ 0 ] eq "items" ) {
	    Log3( $hash, 4, "SB_SERVER_ParseCmds($name): favorites items" );
	    # the response to our query of the favorites
	    SB_SERVER_FavoritesParse( $hash, join( " ", @args ) );
	} else {
	}

    } elsif( $cmd eq "serverstatus" ) {
	Log3( $hash, 4, "SB_SERVER_ParseCmds($name): server status" );
	SB_SERVER_ParseServerStatus( $hash, \@args );

    } elsif( $cmd eq "playlists" ) {
        Log3( $hash, 4, "SB_SERVER_ParseCmds($name): playlists" );
        # CD 0004 Playlisten neu anfragen bei Änderung
        if(($args[0] eq "rename")||($args[0] eq "delete")) {
            DevIo_SimpleWrite( $hash, "playlists 0 200\n", 0 );
            DevIo_SimpleWrite( $hash, "alarm playlists 0 300\n", 0 );   # CD 0011
        } else {
            SB_SERVER_ParseServerPlaylists( $hash, \@args );
        }
    } elsif( $cmd eq "client" ) {

    # CD 0011 start
    } elsif( $cmd eq "alarm" ) {
        if( $args[0] eq "playlists" ) {
            SB_SERVER_ParseServerAlarmPlaylists( $hash, \@args );
        }
    # CD 0011 end
    # CD 0016 start
    } elsif( $cmd eq "rescan" ) {
        if( $args[0] eq "done" ) {
        	DevIo_SimpleWrite( $hash, "serverstatus 0 200\n", 0 );
            # CD 0036 start - refresh favorites and playlists after rescan
            DevIo_SimpleWrite( $hash, "favorites items 0 " .
                   AttrVal( $name, "maxfavorites", 100 ) . " want_url:1\n",
                   0 );
            DevIo_SimpleWrite( $hash, "playlists 0 200\n", 0 );
            DevIo_SimpleWrite( $hash, "alarm playlists 0 300\n", 0 );
            # CD 0036 end
            # CD 0039 start
            readingsBeginUpdate( $hash );
            readingsBulkUpdate( $hash, "scanning", "no");
            readingsBulkUpdate( $hash, "scanprogressdone", "0" );
            readingsBulkUpdate( $hash, "scanprogresstotal", "0" );
            readingsBulkUpdate( $hash, "scandb", "?" );
            # CD 0040 start
            if(defined $hash->{helper}{scanstart}) {
                readingsBulkUpdate( $hash, "scanduration", int(time()-$hash->{helper}{scanstart}));
                delete $hash->{helper}{scanstart};
            }
            # CD 0040 end
            readingsEndUpdate( $hash, 1 );
        } else {
            readingsSingleUpdate( $hash, "scanning", "yes", 1 );
            $hash->{helper}{scanstart}=time();                      # CD 0040
            readingsSingleUpdate( $hash, "scanduration", 0, 1 );    # CD 0040
        }
    } elsif( $cmd eq "scanner" ) {
        if((defined $args[0]) && ($args[0] eq 'notify')) {
            if((defined $args[1]) && (substr($args[1],0,8) eq 'progress')) {
                my @params=split '\|\|',$args[1];
                if((defined $params[1]) && ($params[1] eq 'importer')) {
                    readingsBeginUpdate( $hash );
                    readingsBulkUpdate( $hash, "scanprogressdone", $params[3] ) if defined $params[3];
                    readingsBulkUpdate( $hash, "scanprogresstotal", $params[4] ) if defined $params[4];
                    readingsBulkUpdate( $hash, "scandb", $params[2] ) if defined $params[2];
                    # CD 0040 start
                    if(defined $hash->{helper}{scanstart}) {
                        readingsBulkUpdate( $hash, "scanduration", int(time()-$hash->{helper}{scanstart}));
                    }
                    # CD 0040 end
                    readingsEndUpdate( $hash, 1 );
                }
            }
        }
        # CD 0039 end
    # CD 0016 end
    # CD 0030 start
    } elsif( $cmd eq "artists" ) {
        if(defined($hash->{helper}{getData}) && defined($hash->{helper}{getData}{artists})) {
            my ($dev,$reading)=split(':',$hash->{helper}{getData}{artists}{reading});
            if ($hash->{helper}{getData}{artists}{format} eq 'raw') {
                if(defined($defs{$dev})) {
                    readingsSingleUpdate( $defs{$dev}, $reading, $instr, 1 );
                }
            } else {
                my $artistname="";
                my $jout="[";
                my $lout="";
                my $iout="";
                my $artistid=0;

                foreach( @args ) {
                    if( $_ =~ /^(artist:)(.*)/ ) {
                        $artistname=$2;
                        next;
                    } elsif( $_ =~ /^(id:)([0-9]*)/ ) {
                        # start new entry
                        if($artistname ne "") {
                            $artistname=~s/\"/\\\"/g;
                            $jout.="{\"Artist\":\"".$artistname."\",\"Id\":\"".$artistid."\"},";
                            $lout.="\"".$artistname."\":";
                            $iout.=$artistid.":";
                        }
                        $artistid=$2;
                        next;
                    } elsif( $_ =~ /^(count:)([0-9]*)/ ) {
                        next;
                    } elsif( $artistname ne "" ) {
                        $artistname=~s/\"/\\\"/g;
                        $artistname.=" ".$_;
                        next;
                    }
                }
                if($artistname ne "") {
                    $jout.="{\"Artist\":\"".$artistname."\"}";
                    $lout.="\"".$artistname."\"";
                    $iout.=$artistid;
                }
                $jout.="]";
                if(defined($defs{$dev})) {
                    readingsSingleUpdate( $defs{$dev}, $reading, $jout, 1 ) if ($hash->{helper}{getData}{artists}{format} eq 'json');
                    readingsSingleUpdate( $defs{$dev}, $reading, $lout, 1 ) if ($hash->{helper}{getData}{artists}{format} eq 'delimited');
                    readingsSingleUpdate( $defs{$dev}, $reading."_index", $iout, 1 ) if ($hash->{helper}{getData}{artists}{format} eq 'delimited');
                }
            }
            delete $hash->{helper}{getData}{artists};
        }
    # CD 0030 end
    # CD 0032 start
    } elsif( $cmd eq "apps" ) {
        my $save=0;
        my $appcmd="";
        my $appname="";
        my $scansubs=0;

        # 1. Mal ?
        $scansubs=1 unless (defined($hash->{helper}{apps}));

        delete($hash->{helper}{apps}) if(defined($hash->{helper}{apps}));
        delete($hash->{helper}{appcmd}) if(defined($hash->{helper}{appcmd}));

        foreach( @args ) {
            if( $_ =~ /^(icon:)(.*)/ ) {
                # new entry
                if($save==1) {
                    $hash->{helper}{apps}{$appname}{cmd}=$appcmd;
                    $hash->{helper}{appcmd}{$appcmd}{name}=$appname;
                    $save=0;
                }
                next;
            } elsif( $_ =~ /^(cmd:)(.*)/ ) {
                $appcmd=$2;
                $save=1;
                next;
            } elsif( $_ =~ /^(name:)(.*)/ ) {
                $appname=$2;
                $appname=~s/\./_/g;
                $appname=~s/-/_/g;
                $save=1;
                next;
            } elsif( $_ =~ /^(type:)(.*)/ ) {
                $save=0 if($2 ne 'xmlbrowser');
                next;
            }
        }
        if($save==1) {
            $hash->{helper}{apps}{$appname}{cmd}=$appcmd;
            $hash->{helper}{appcmd}{$appcmd}{name}=$appname;
        }
        SB_SERVER_SetAttrList($hash);

        if(defined($hash->{helper}{apps})&&($scansubs==1)) {
            my @enabledApps=split(',',AttrVal($name,'enablePlugins',''));
            foreach my $app (@enabledApps) {
                if(defined($hash->{helper}{apps}{$app})) {
                    DevIo_SimpleWrite( $hash, ($hash->{helper}{apps}{$app}{cmd})." items 0 200\n", 0 );
                }
            }
        }
    # CD 0032 end

    # CD 0032 end
    } else {
	# unkown
    }
}

# CD 0020 start
sub SB_SERVER_tcb_Alive($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    #Log 0,"SB_SERVER_tcb_Alive";
    delete($hash->{helper}{disableReconnect}) if defined($hash->{helper}{disableReconnect});

    SB_SERVER_Alive($hash);
}
# CD 0020 end

# ----------------------------------------------------------------------------
#  Alivecheck of the server
# ----------------------------------------------------------------------------
sub SB_SERVER_Alive( $ ) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $state=ReadingsVal($name, "state", "unknown");   # CD 0038

    return if (IsDisabled($name));  # CD 0046

    # CD 0004 set default to off
    #my $rccstatus = "on";
    #my $pingstatus = "on";
    my $rccstatus = "off";
    my $pingstatus = "off";
    my $nexttime = gettimeofday() + AttrVal( $name, "alivetimer", 120 );

    Log3( $hash, 4, "SB_SERVER_Alive($name): called" );                     # CD 0006 changed log level from 4 to 2 # CD 0009 level 2->3 # CD 0014 level -> 4

    if( AttrVal( $name, "doalivecheck", "false" ) eq "false" ) {
        Log3( $hash, 5, "SB_SERVER_Alive($name): alivechecking is off" );
        $rccstatus  = "on";
        $pingstatus = "on";
        $hash->{helper}{pingCounter}=0;                                     # CD 0004
    } else {
        # check via the RCC element
        if( $hash->{RCCNAME} ne "none" ) {
            # an RCC element has been given as argument
            $rccstatus = ReadingsVal( $hash->{RCCNAME}, "state", "off" );
        }

        # CD 0007 start
        if (($hash->{PRESENCENAME} ne "none")
            && defined($defs{$hash->{PRESENCENAME}})
            && ((defined($defs{$hash->{PRESENCENAME}}->{TIMEOUT_NORMAL})
            && (($defs{$hash->{PRESENCENAME}}->{TIMEOUT_NORMAL}) < AttrVal( $name, "alivetimer", 30 ))) || (GetType($hash->{PRESENCENAME},'x') ne 'PRESENCE'))) {
            Log3( $hash, 4,"SB_SERVER_Alive($name): using $hash->{PRESENCENAME}");                      # CD 0009 level 2->4
            if( ReadingsVal( $hash->{PRESENCENAME}, $hash->{helper}{presenceReading}, "xxxxxxx" ) eq $hash->{helper}{presenceValuePresent} ) {  # CD 0047 erweitert
                $pingstatus = "on";
                $hash->{helper}{pingCounter}=0;
            } else {
                $pingstatus = "off";
                $hash->{helper}{pingCounter}=$hash->{helper}{pingCounter}+1;
                $nexttime = gettimeofday() + 15;
            }
        } else {
        # CD 0007 end
            # CD 0021 start
            my $ipp=AttrVal($name, "internalPingProtocol", "tcp" );
            if($ipp eq "none") {
                if ($state eq "disconnected") {     # CD 0038 state statt STATE verwenden
                    $pingstatus = "off";
                    $hash->{helper}{pingCounter}=3;
                } else {
                    $pingstatus = "on";
                    $hash->{helper}{pingCounter}=0;
                }
            } else {
            # CD 0021 end
                Log3( $hash, 4,"SB_SERVER_Alive($name): using internal ping");                              # CD 0007 # CD 0009 level 2->4
                # check via ping
                my $p;
                # CD 0017 eval hinzugefügt, Absturz auf FritzBox, bei Fehler annehmen dass Host verfügbar ist, internalPingProtocol hinzugefügt

                eval { $p = Net::Ping->new( $ipp ); };
                if($@) {
                    Log3( $hash,1,"SB_SERVER_Alive($name): internal ping failed with $@");
                    $pingstatus = "on";
                    $hash->{helper}{pingCounter}=0;
                } else {
                    eval {  # CD 0048 ungültige Adressen bringen FHEM zum Absturz
                        if( $p->ping( $hash->{IP}, 2 ) ) {
                            $pingstatus = "on";
                            $hash->{helper}{pingCounter}=0;                                 # CD 0004
                        } else {
                            $pingstatus = "off";
                            $hash->{helper}{pingCounter}=$hash->{helper}{pingCounter}+1;    # CD 0004
                        }
                    };
                    if($@) {
                        Log3( $hash,1,"SB_SERVER_Alive($name): internal ping failed with $@");
                        $pingstatus = "on";
                        $hash->{helper}{pingCounter}=0;
                    }
                    # close our ping mechanism again
                    $p->close( );
                }
            } # CD 0021
        } # CD 0007
        Log3( $hash, 5, "SB_SERVER_Alive($name): " .            # CD Test 5
              "RCC:" . $rccstatus . " Ping:" . $pingstatus );               # CD 0006 changed log level from 5 to 2 # CD 0009 level 2->3 # CD 0014 level -> 5
    }

    # set the status of the server accordingly
    # CD 0004 added sensitivity to ping
#    if( ( $rccstatus eq "on" ) || ( $pingstatus eq "on" ) ) {
    if( ( $rccstatus eq "on" ) || ( $hash->{helper}{pingCounter}<3 ) ) {

        # the server is reachable
        if( ReadingsVal( $name, "power", "on" ) eq "off" ) {
            # the first time we see the server being on
            Log3( $hash, 3, "SB_SERVER_Alive($name): " .    # CD 0004 changed log level from 5 to 2 # CD 0009 level 2->3
              "SB-Server is back again." );
            # first time we realized server is away
            if( $state eq "disconnected" ) {        # CD 0038 state statt STATE verwenden
                delete($hash->{NEXT_OPEN}) if($hash->{NEXT_OPEN});                  # CD 0007 remove delay for reconnect
                SB_SERVER_TryConnect( $hash , 1);
            }

            readingsSingleUpdate( $hash, "power", "on", 1 );

            $hash->{ALIVECHECK} = "?";
            $hash->{CLICONNECTION} = "off";
            $hash->{helper}{onAfterAliveCheck}=1;   # CD 0038

            # quicker update to capture CLI connection faster
            $nexttime = gettimeofday() + 10;
        } else {                                                                    # CD 0005
            # check the CLI connection (sub-state)
            if( $hash->{ALIVECHECK} eq "waiting" ) {
                # ups, we did not receive any answer in the last minutes
                # SB Server potentially dead or shut-down
                Log3( $hash, 3, "SB_SERVER_Alive($name): overrun SB-Server dead." );    # CD 0004 changed log level from 5 to 2 # CD 0009 level 2->3

                $hash->{CLICONNECTION} = "off";
                
                $hash->{helper}{onAfterAliveCheck}=0;   # CD 0038

                # signal that to our clients
                SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );

                # close the device
                # CD 0007 use DevIo_Disconnected instead of DevIo_CloseDev
                #DevIo_CloseDev( $hash );
                DevIo_Disconnected( $hash );
                $hash->{helper}{pingCounter}=9999;                                 # CD 0007

                # CD 0000 start - exit infinite loop after socket has been closed
                $hash->{ALIVECHECK} = "?";
                # CD 0038 $hash->{STATE}="disconnected";
                # CD 0005 line above does not work (on Linux), fix:
                # CD 0006 DevIo_setStates requires v7099 of DevIo.pm, replaced with SB_SERVER_setStates
                SB_SERVER_setStates($hash, "disconnected");

                readingsSingleUpdate( $hash, "power", "off", 1 );
                # test: clear stack ?
                $SB_SERVER_CmdStack{$name}{last_n} = 0;
                $SB_SERVER_CmdStack{$name}{first_n} = 0;
                $SB_SERVER_CmdStack{$name}{cnt} = 0;
                # CD end

                # remove all timers we created
                SB_SERVER_RemoveInternalTimers( $hash );
            } else {
                if( $hash->{CLICONNECTION} eq "off" ) {
                    # signal that to our clients
                    # to be revisited, should only be sent after CLI established
                    #SB_SERVER_Broadcast( $hash, "SERVER",  "ON" );             # CD 0007 disabled, wait for SB_SERVER_LMS_Status
                    SB_SERVER_LMS_Status( $hash ) if ($state eq 'opened');  # CD 0038 nur aufrufen wenn Verbindung aufgebaut ist
                }

                $hash->{CLICONNECTION} = "on";

                # just send something to the SB-Server. It will echo it
                # if we receive the echo, the server is still alive
                $hash->{ALIVECHECK} = "waiting";
                DevIo_SimpleWrite( $hash, "fhemalivecheck\n", 0 ) if ($state eq 'opened');  # CD 0038 nur aufrufen wenn Verbindung aufgebaut ist
            }
        }
    } elsif( ( $rccstatus eq "off" ) && ( $pingstatus eq "off" ) ) {
        if( ReadingsVal( $name, "power", "on" ) eq "on" ) {
            # the first time we realize the server is off
            Log3( $hash, 3, "SB_SERVER_Alive($name): " .    # CD 0004 changed log level from 5 to 2 # CD 0009 level 2->3
              "SB-Server in hibernate / suspend?." );

            # first time we realized server is away
            $hash->{CLICONNECTION} = "off";
            readingsSingleUpdate( $hash, "power", "off", 1 );
            $hash->{ALIVECHECK} = "?";

            # signal that to our clients
            SB_SERVER_Broadcast( $hash, "SERVER",  "OFF" );

            # close the device
            # CD 0007 use DevIo_Disconnected instead of DevIo_CloseDev
            #DevIo_CloseDev( $hash );
            DevIo_Disconnected( $hash );
            $hash->{helper}{pingCounter}=9999;                                 # CD 0007
            # CD 0004 set STATE, needed for reconnect
            # CD 0038 $hash->{STATE}="disconnected";
            # CD 0005 line above does not work (on Linux), fix:
            # CD 0006 DevIo_setStates requires v7099 of DevIo.pm, replaced with SB_SERVER_setStates
            SB_SERVER_setStates($hash, "disconnected");
            # remove all timers we created
            SB_SERVER_RemoveInternalTimers( $hash );
        }
    } else {
        # we shouldn't end up here
        Log3( $hash, 5, "SB_SERVER_Alive($name): funny server status " .
              "received. Ping=" . $pingstatus . " RCC=" . $rccstatus );
    }

    # do an update of the status
    # CD 0020 SB_SERVER_tcb_Alive verwenden
    RemoveInternalTimer( "SB_SERVER_Alive:$name");
    if( AttrVal( $name, "doalivecheck", "false" ) eq "true" ) {
        InternalTimer( $nexttime,
               "SB_SERVER_tcb_Alive",
               "SB_SERVER_Alive:$name",
               0 );
    }
}


# ----------------------------------------------------------------------------
#  Broadcast a message to all clients
# ----------------------------------------------------------------------------
sub SB_SERVER_Broadcast( $$@ ) {
    my( $hash, $cmd, $msg, $bin ) = @_;
    my $name = $hash->{NAME};
    my $iodevhash;

    Log3( $hash, 4, "SB_SERVER_Broadcast($name): called with $cmd - $msg" );

    return if (IsDisabled($name));  # CD 0046

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
            ( $defs{$mydev}{TYPE} eq "SB_PLAYER" )){       # CD 0029 umsortiert
                if( ( defined( $iodevhash->{NAME} ) ) &&   # CD 0029 umsortiert
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

    Log3( $hash, 4, "SB_SERVER_ParseServerStatus($name): called " );

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

    my $addplayers = true;
    my %players;
    my $currentplayerid = "none";

    # needed for scanning the MAC Adress
    my $d = "[0-9A-Fa-f]";
    my $dd = "$d$d";

    # needed for scanning the IP adress
    my $e = "[0-9]";
    my $ee = "$e$e";

    my $nameactive=0;
    my $rescanactive=0;

    foreach( @data1 ) {
	if( $_ =~ /^(lastscan:)([0-9]*)/ ) {
	    # we found the lastscan entry
	    my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) =
		localtime( $2 );
	    $year = $year + 1900;
	    readingsBulkUpdate( $hash, "scan_last", "$mday-".($mon+1)."-$year " .   # CD 0016 Monat korrigiert
				"$hour:$min:$sec" );
	    #readingsBulkUpdate( $hash, "scanlast", strftime("%Y-%m-%d %H:%M:%S", localtime($2)));  # CD 0040
	    next;
	} elsif( $_ =~ /^(scanning:)([0-9]*)/ ) {
	    readingsBulkUpdate( $hash, "scanning", $2 );
	    next;
	} elsif( $_ =~ /^(rescan:)([0-9]*)/ ) {
	    if( $2 eq "1" ) {
            readingsBulkUpdate( $hash, "scanning", "yes" );
            $rescanactive=1;
            $hash->{helper}{scanstart}=time() unless defined($hash->{helper}{scanstart});   # CD 0040
	    } else {
            readingsBulkUpdate( $hash, "scanning", "no" );
            # CD 0040 start
            if(defined $hash->{helper}{scanstart}) {
                readingsBulkUpdate( $hash, "scanduration", int(time()-$hash->{helper}{scanstart}));
                delete $hash->{helper}{scanstart};
            }
            # CD 0040 end
	    }
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
	    if( $addplayers == true ) { # CD 0017 fixed ==
		$players{$id}{ID} = $id;
		$players{$id}{MAC} = $2;
		$currentplayerid = $id;
	    }
        $nameactive=0;  # CD 0030
	    next;
    # CD 0044 auf IP-Adresse prüfen
	} elsif( $_ =~ /^(playerid:)(.*)/ ) {
        if (SB_PLAYER_IsValidIPV4( $2 ) == 1) {
            if( $addplayers == true ) {
                $players{$2}{ID} = $2;
                $players{$2}{MAC} = $2;
                $players{$2}{isplayer} = "1";   # für virtuellen Player der angelegt wird wenn stream.mp3 abgerufen wird
                $currentplayerid = $2;
            }
        }
        $nameactive=0;
	    next;
    # CD 0044 end
	} elsif( $_ =~ /^(name:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{name} = $2;
        $nameactive=1;  # CD 0030
	    }
	    next;
	} elsif( $_ =~ /^(displaytype:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{displaytype} = $2;
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(model:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{model} = $2;
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(power:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{power} = $2;
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(canpoweroff:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{canpoweroff} = $2;
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(connected:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{connected} = $2;
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(isplayer:)([0|1])/ ) {
	    if( $currentplayerid ne "none" ) {
            $players{$currentplayerid}{isplayer} = $2 unless defined($players{$currentplayerid}{isplayer});     # CD 0044 Hack für Zugriff über stream.mp3
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(ip:)(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{3,5})/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{IP} = $2;
	    }
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(seq_no:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;  # CD 0030
	    next;
    # CD 0017 start
	} elsif( $_ =~ /^(isplaying:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(snplayercount:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(otherplayercount:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(server:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;  # CD 0030
	    next;
	} elsif( $_ =~ /^(serverurl:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;  # CD 0030
	    next;
    # CD 0017 end
    # CD 0030 firmware und modelname
	} elsif( $_ =~ /^(modelname:)(.*)/ ) {
	    if( $currentplayerid ne "none" ) {
		$players{$currentplayerid}{model} = $2;
	    }
        $nameactive=0;
	    next;
	} elsif( $_ =~ /^(firmware:)(.*)/ ) {
	    # just to take care of the keyword
        $nameactive=0;
	    next;
    } elsif( $_ =~ /:/ ) {
        $nameactive=0;
    # CD 0030 Ende
	} else {
	    # no keyword found, so let us assume it is part of the player name
        # CD 0030 aber nur wenn 'name' noch aktiv ist
	    if(( $currentplayerid ne "none" )&&($nameactive==1)) {
		$players{$currentplayerid}{name} .= $_;
	    }

	}
    }

    if ($rescanactive==0) {
        # set default values for stuff not always send
        readingsBulkUpdate( $hash, "scanning", "no" );
        readingsBulkUpdate( $hash, "scandb", "?" );
        readingsBulkUpdate( $hash, "scanprogressdone", "0" );
        readingsBulkUpdate( $hash, "scanprogresstotal", "0" );
        readingsBulkUpdate( $hash, "scanlastfailed", "none" );
    }
    readingsEndUpdate( $hash, 1 );

    my @ignoredIPs=split(',',AttrVal($name,'ignoredIPs',''));   # CD 0017
    my @ignoredMACs=split(',',AttrVal($name,'ignoredMACs',''));   # CD 0017

    foreach my $player ( keys %players ) {
        my $playerdata;     # CD 0029

        if( defined( $players{$player}{isplayer} ) ) {
            if( $players{$player}{isplayer} eq "0" ) {
            Log3( $hash, 1, "not a player" );
            next;
            }
        }

        # CD 0017 check ignored IPs
        if( defined( $players{$player}{IP} ) ) {
            my @ip=split(':',$players{$player}{IP});
            if ($ip[0] ~~ @ignoredIPs) {
                $players{$player}{ignore}=1;
                next;
            }
        }

        # CD 0017 check ignored MACs
        if( defined( $players{$player}{MAC} ) ) {
            if ($players{$player}{MAC} ~~ @ignoredMACs) {
                $players{$player}{ignore}=1;
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

        # CD 0029 start
        if( defined( $players{$player}{model} ) ) {
            $playerdata=$players{$player}{model}." ";
        } else {
            $playerdata="unknown ";
        }

        if( defined( $players{$player}{canpoweroff} ) ) {
            $playerdata.=$players{$player}{canpoweroff}." ";
        } else {
            $playerdata.="unknown ";
        }

        if( defined( $players{$player}{displaytype} ) ) {
            $playerdata.=$players{$player}{displaytype}." ";
        } else {
            $playerdata.="unknown ";
        }

        if( defined( $players{$player}{connected} ) ) {
            $playerdata.=$players{$player}{connected}." ";
        } else {
            $playerdata.="unknown";
        }

        if( defined( $players{$player}{IP} ) ) {
            $playerdata.=$players{$player}{IP};
        } else {
            $playerdata.="unknown";
        }
        Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" .
              "playerdata $playerdata", undef );

        # CD 0029 end

        if( defined( $players{$player}{power} ) ) {
            Dispatch( $hash, "SB_PLAYER:$players{$player}{ID}:" .
                  "power $players{$player}{power}", undef );
        }
    }

    # the list for the sync masters
    # make all client create e new sync master list
    SB_SERVER_Broadcast( $hash, "SYNCMASTER",
			 "FLUSH all", undef );

    # now send the list for the sync masters
    @SB_SERVER_SM=();
    foreach my $player ( keys %players ) {
        next if defined($players{$player}{ignore});
        my $uniqueid = join( "", split( ":", $players{$player}{MAC} ) );
        Log3( $hash, 1, "SB_SERVER_ParseServerStatus($name): player has no name") unless defined($players{$player}{name});
        Log3( $hash, 1, "SB_SERVER_ParseServerStatus($name): player has no MAC") unless defined($players{$player}{MAC});
        push @SB_SERVER_SM, "ADD $players{$player}{name} " .
                      "$players{$player}{MAC} $uniqueid" # CD 0029 aufteilen wenn Hardware zu schwach
    }
    push @SB_SERVER_SM,'DONE';  # CD 0045
    # CD 0029 start
    if(scalar(@SB_SERVER_SM)>0) {
        RemoveInternalTimer( "SB_SERVER_tcb_SendSyncMasters:$name");
        InternalTimer( gettimeofday() + 0.01,
                   "SB_SERVER_tcb_SendSyncMasters",
                   "SB_SERVER_tcb_SendSyncMasters:$name",
                   0 );
    }
    # CD 0029 end

    SB_SERVER_BuildPlayerList($hash);   # CD 0024

    return;
}

# CD 0029 start
# für schwache Hardware Übertragung aufteilen
sub SB_SERVER_tcb_SendSyncMasters( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    RemoveInternalTimer( "SB_SERVER_tcb_SendSyncMasters:$name");

    my $a;
    my $t=time();

    do {
        $a=shift @SB_SERVER_SM; # CD 0045 Reihenfolge beibehalten
        if (defined($a)) {
            SB_SERVER_Broadcast( $hash, "SYNCMASTER", $a, undef );
        }
    } while ((time()<$t+0.05) && defined($a));

    if(scalar(@SB_SERVER_SM)>0) {
    #Log 0,"SB_SERVER_tcb_SendSyncMasters: ".scalar(@SB_SERVER_SM)." entries remaining";
        InternalTimer( gettimeofday() + 0.05,
                   "SB_SERVER_tcb_SendSyncMasters",
                   "SB_SERVER_tcb_SendSyncMasters:$name",
                   0 );
    }
}
# CD 0029 end

# ----------------------------------------------------------------------------
#  Parse the return values of the favorites items
# ----------------------------------------------------------------------------
sub SB_SERVER_FavoritesParse( $$ ) {
    my ( $hash, $str ) = @_;

    my $name = $hash->{NAME};

    Log3( $hash, 5, "SB_SERVER_FavoritesParse($name): called" );

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
    my $isplaylist = false;
    my $url = "?";           # CD 0009 hinzugefügt

    my $cnt=0;

    foreach ( @data ) {
    #Log 0,$_;
	if( $_ =~ /^(id:|ID:)([A-Za-z0-9\.]*)/ ) {
	    # we found an ID, that is typically the start of a new session
	    # so save the old session first
	    if( $firstone == false ) {
            if(( $hasitemsbuf == false )||($isplaylist == true)) {
                # derive our hash entry
                $namebuf="noname_".$cnt++ if($namebuf=~/^\s*$/);            # CD 0037
                my $entryuid = SB_SERVER_FavoritesName2UID( $namebuf );     # CD 0009 decode hinzugefügt # CD 0010 decode wieder entfernt
                $favorites{$name}{$entryuid} = {
                ID => $idbuf,
                Name => $namebuf,
                URL => $url, };         # CD 0009 hinzugefügt
                $namebuf = "";
                $isaudiobuf = "";
                $url = "?";              # CD 0009 hinzugefügt
                $hasitemsbuf = false;
                $isplaylist = false;
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
    # CD 0018 start
    } elsif( $_ =~ /^(type:)(.*)/ ) {
        $isplaylist = true if($2 eq "playlist");
	    if( $namestarted == true ) {
            $namestarted = false;
	    }
    # CD 0018 end
	#} elsif( $_ =~ /^(name:)([0-9a-zA-Z]*)/ ) {     # CD 0007   # CD 0009 deaktiviert
	} elsif( $_ =~ /^(name:)(.*)/ ) {     # CD 0009 hinzugefügt
	    $namebuf = $2;
	    $namestarted = true;

    # CD 0009 start
	} elsif( $_ =~ /^(url:)(.*)/ ) {
	    $url = $2;
        $url =~ s/file:\/\/\///;
    # CD 0009 end
    } else {
	    # no regexp matched, so it must be part of the name
	    if( $namestarted == true ) {
		$namebuf .= " " . $_;
	    }
	}
    }

    # capture the last element also
    if( ( $namebuf ne "" ) && ( $idbuf ne "" ) ) {
    if(( $hasitemsbuf == false )||($isplaylist == true)) {
	    # CD 0003 replaced ** my $entryuid = join( "", split( " ", $namebuf ) ); ** with:
        $namebuf="noname_".$cnt++ if($namebuf=~/^\s*$/);            # CD 0037
        my $entryuid = SB_SERVER_FavoritesName2UID( $namebuf );             # CD 0009 decode hinzugefügt # CD 0010 decode wieder entfernt
	    $favorites{$name}{$entryuid} = {
		ID => $idbuf,
		Name => $namebuf,
        URL => $url, };         # CD 0009 hinzugefügt
	} else {
	    # that is a folder we found, but we don't handle that
	}
    }

    # make all client create e new favorites list
    SB_SERVER_Broadcast( $hash, "FAVORITES",
			 "FLUSH all", undef );

    # find all the names and broadcast to our clients
    $favsetstring = "favorites:";
    @SB_SERVER_FAVS=(); # CD 0029
    foreach my $titi ( keys %{$favorites{$name}} ) {
        Log3( $hash, 5, "SB_SERVER_ParseFavorites($name): " .
              "ID:" .  $favorites{$name}{$titi}{ID} .
              " Name:" . $favorites{$name}{$titi}{Name} . " $titi" );
        $favsetstring .= "$titi,";
        push @SB_SERVER_FAVS, "ADD $name $favorites{$name}{$titi}{ID} " .
                     "$titi $favorites{$name}{$titi}{URL} LMS $favorites{$name}{$titi}{Name}";     # CD 0009 URL an Player schicken # CD 0029 aufteilen wenn Hardware zu schwach
    }
    # CD 0029 start
    if(scalar(@SB_SERVER_FAVS)>0) {
        RemoveInternalTimer( "SB_SERVER_tcb_SendFavorites:$name");
        InternalTimer( gettimeofday() + 0.01,
                   "SB_SERVER_tcb_SendFavorites",
                   "SB_SERVER_tcb_SendFavorites:$name",
                   0 );
    }
    # CD 0029 end
    #chop( $favsetstring );
    #$favsetstring .= " ";
}

# CD 0029 start
# für schwache Hardware Übertragung aufteilen
sub SB_SERVER_tcb_SendFavorites( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    RemoveInternalTimer( "SB_SERVER_tcb_SendFavorites:$name");

    my $a;
    my $t=time();

    do {
        $a=shift @SB_SERVER_FAVS;   # CD 0045 Reihenfolge beibehalten
        if (defined($a)) {
            SB_SERVER_Broadcast( $hash, "FAVORITES", $a, undef );     # CD 0009 URL an Player schicken
        }
    } while ((time()<$t+0.05) && defined($a));

    if(scalar(@SB_SERVER_FAVS)>0) {
    #Log 0,"SB_SERVER_tcb_SendFavorites: ".scalar(@SB_SERVER_FAVS)." entries remaining";
        InternalTimer( gettimeofday() + 0.05,
                   "SB_SERVER_tcb_SendFavorites",
                   "SB_SERVER_tcb_SendFavorites:$name",
                   0 );
    }
}
# CD 0029 end

# ----------------------------------------------------------------------------
#  generate a UID for the hash entry from the name
# ----------------------------------------------------------------------------
sub SB_SERVER_FavoritesName2UID( $ ) {
    my $namestr = shift( @_ );

    # eliminate spaces
    $namestr = join( "_", split( " ", $namestr ) );     # CD 0009 Leerzeichen durch _ ersetzen statt löschen

    # CD 0009 verschiedene Sonderzeichen ersetzen und nicht mehr löschen
    my %Sonderzeichen = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss",
                        "é" => "e", "è" => "e", "ë" => "e", "à" => "a", "ç" => "c" );
    my $Sonderzeichenkeys = join ("|", keys(%Sonderzeichen));
    $namestr =~ s/($Sonderzeichenkeys)/$Sonderzeichen{$1}/g;
#    $namestr =~ s/($Sonderzeichenkeys)/$Sonderzeichen{$1}||''/g;
    # CD 0009

    # CD 0034 start
    my $rc=eval
    {
        require Text::Unaccent;
        $namestr=Text::Unaccent::unac_string('UTF8', $namestr);
    };
    # CD 0034 end

    # this defines the regexp. Please add new stuff with the seperator |
    # CD 0003 changed öÜ to ö|Ü
    my $tobereplaced = '[Ä|ä|Ö|ö|Ü|ü|\[|\]|\{|\}|\(|\)|\\\\|,|:|\?|;|' .       # CD 0011 ,:? hinzugefügt # CD 0035 ; hinzugefügt
	'\/|\'|\.|\"|\^|°|\$|\||%|@|*|#|&|\+]';     # CD 0009 + hinzugefügt # CD 0070 * und # hinzugefügt

    $namestr =~ s/$tobereplaced//g;

    return( $namestr );
}

# ----------------------------------------------------------------------------
#  push a command to the buffer
# ----------------------------------------------------------------------------
sub SB_SERVER_CMDStackPush( $$ ) {
    my ( $hash, $cmd ) = @_;

    my $name = $hash->{NAME};

    return if (IsDisabled($name));  # CD 0046

    my $n = $SB_SERVER_CmdStack{$name}{last_n};

    $n=0 if(!defined($n));                                          # CD 0007

    if( $n > AttrVal( $name, "maxcmdstack", 200 ) ) {
        Log3( $hash, 5, "SB_SERVER_CMDStackPush($name): limit reached" );
        SB_SERVER_CMDStackPop($hash);                               # CD 0007 added
        #return;                                                    # CD 0007 disabled
    }

    $SB_SERVER_CmdStack{$name}{$n}{CMD} = $cmd;
    $SB_SERVER_CmdStack{$name}{$n}{TS} = time();                    # CD 0007

    $n = $n + 1;

    $SB_SERVER_CmdStack{$name}{last_n} = $n;
    $SB_SERVER_CmdStack{$name}{first_n} = $n if (!defined($SB_SERVER_CmdStack{$name}{first_n}));    # CD 0007

    # update overall number of entries
    $SB_SERVER_CmdStack{$name}{cnt} = $SB_SERVER_CmdStack{$name}{last_n} -
	$SB_SERVER_CmdStack{$name}{first_n} + 1;
    $hash->{CMDSTACK}=$SB_SERVER_CmdStack{$name}{cnt};              # CD 0007
}

# ----------------------------------------------------------------------------
#  pop a command from the buffer
# ----------------------------------------------------------------------------
sub SB_SERVER_CMDStackPop( $ ) {
    my ( $hash ) = @_;

    my $name = $hash->{NAME};

    my $n = $SB_SERVER_CmdStack{$name}{first_n};

    $n=0 if(!defined($n));                                          # CD 0007

    my $res = "";
    # return the first element of the list
    if( defined( $SB_SERVER_CmdStack{$name}{$n} ) ) {
        $res = $SB_SERVER_CmdStack{$name}{$n}{CMD};
        $res = "empty" if($SB_SERVER_CmdStack{$name}{$n}{TS}<time()-300);               # CD 0007 drop commands older than 5 minutes
    } else {
        $res = "empty";
    }

    # and now remove the first element

    delete( $SB_SERVER_CmdStack{$name}{$n} );

    $n = $n + 1;

    if ( $n <= $SB_SERVER_CmdStack{$name}{last_n} ) {                                   # CD 0000 changed first_n to last_n
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
    $hash->{CMDSTACK}=$SB_SERVER_CmdStack{$name}{cnt};          # CD 0007

    return( $res );
}


# CD 0011 start
# ----------------------------------------------------------------------------
#  parse the list of known alarm playlists
# ----------------------------------------------------------------------------
sub SB_SERVER_ParseServerAlarmPlaylists( $$ ) {
    my( $hash, $dataptr ) = @_;

    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_ParseServerAlarmPlaylists($name): called" );

    # force all clients to delete alarm playlists
    SB_SERVER_Broadcast( $hash, "ALARMPLAYLISTS",
			 "FLUSH all", undef );

    @SB_SERVER_AL_PLS=split("category:",join(" ",@{$dataptr}));
    # CD 0029 Übertragung an Player aufteilen
    if(scalar(@SB_SERVER_AL_PLS)>0) {
        RemoveInternalTimer( "SB_SERVER_tcb_SendAlarmPlaylists:$name");
        InternalTimer( gettimeofday() + 0.01,
                   "SB_SERVER_tcb_SendAlarmPlaylists",
                   "SB_SERVER_tcb_SendAlarmPlaylists:$name",
                   0 );
    }
}
# CD 0011 end

# CD 0029 start
# für schwache Hardware Übertragung aufteilen
sub SB_SERVER_tcb_SendAlarmPlaylists( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    RemoveInternalTimer( "SB_SERVER_tcb_SendAlarmPlaylists:$name");

    my $a;
    my $t=time();

    do {
        $a=shift @SB_SERVER_AL_PLS; # CD 0045 Reihenfolge beibehalten
        if (defined($a)) {
            my $i1=index($a," title:");
            my $i2=index($a," url:");
            my $i3=index($a," singleton:");
            if (($i1!=-1)&&($i2!=-1)&&($i3!=-1)) {
                my $url=substr($a,$i2+5,$i3-$i2-5);
                $url=substr($a,$i1+7,$i2-$i1-7) if ($url eq "");
                my $pn=SB_SERVER_FavoritesName2UID(decode('utf-8',$url));
                SB_SERVER_Broadcast( $hash, "ALARMPLAYLISTS",
                            "ADD $pn category ".substr($a,0,$i1), undef );
                SB_SERVER_Broadcast( $hash, "ALARMPLAYLISTS",
                            "ADD $pn title ".substr($a,$i1+7,$i2-$i1-7), undef );
                SB_SERVER_Broadcast( $hash, "ALARMPLAYLISTS",
                            "ADD $pn url $url", undef );
            }
        }
    } while ((time()<$t+0.05) && defined($a));

    if(scalar(@SB_SERVER_AL_PLS)>0) {
    #Log 0,"SB_SERVER_tcb_SendAlarmPlaylists: ".scalar(@SB_SERVER_AL_PLS)." entries remaining";
        InternalTimer( gettimeofday() + 0.05,
                   "SB_SERVER_tcb_SendAlarmPlaylists",
                   "SB_SERVER_tcb_SendAlarmPlaylists:$name",
                   0 );
    }
}
# CD 0029 end

# ----------------------------------------------------------------------------
#  parse the list of known Playlists
# ----------------------------------------------------------------------------
sub SB_SERVER_ParseServerPlaylists( $$ ) {
    my( $hash, $dataptr ) = @_;

    my $name = $hash->{NAME};

    Log3( $hash, 4, "SB_SERVER_ParseServerPlaylists($name): called" );

    my $namebuf = "";
    my $uniquename = "";
    my $idbuf = -1;

    # typically the start index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
	shift( @{$dataptr} );
    } else {
	Log3( $hash, 5, "SB_SERVER_ParseServerPlaylists($name): entry is " .
	      "not the start number" );
	return;
    }

    # typically the max index being a number
    if( $dataptr->[ 0 ] =~ /^([0-9])*/ ) {
	shift( @{$dataptr} );
    } else {
	Log3( $hash, 5, "SB_SERVER_ParseServerPlaylists($name): entry is " .
	      "not the end number" );
	return;
    }

    my $datastr = join( " ", @{$dataptr} );

    Log3( $hash, 5, "SB_SERVER_ParseServerPlaylists($name): data to parse: " .
	  $datastr );

    # make all client create a new favorites list
    SB_SERVER_Broadcast( $hash, "PLAYLISTS",
			 "FLUSH all", undef );

    my @data1 = split( " ", $datastr );

    @SB_SERVER_PLS=();

    my $cnt=1;  # CD 0037

    foreach( @data1 ) {
        if( $_ =~ /^(id:)(.*)/ ) {
            Log3( $hash, 5, "SB_SERVER_ParseServerPlaylists($name): " .
              "id:$idbuf name:$namebuf " );
            if( $idbuf != -1 ) {
                $namebuf="noname_".$cnt++ if($namebuf=~/^\s*$/);                # CD 0037
                $uniquename = SB_SERVER_FavoritesName2UID( $namebuf );          # CD 0009 decode hinzugefügt # CD 0010 decode wieder entfernt
                push @SB_SERVER_PLS, "ADD $namebuf $idbuf $uniquename LMS";         # CD 0029
            }
            $idbuf = $2;
            $namebuf = "";
            $uniquename = "";
            next;
        } elsif( $_ =~ /^(playlist:)(.*)/ ) {
            $namebuf = $2;
            next;
        } elsif( $_ =~ /^(count:)([0-9]*)/ ) {
            # the last entry of the return
            Log3( $hash, 5, "SB_SERVER_ParseServerPlaylists($name): " .
              "id:$idbuf name:$namebuf " );
            if( $idbuf != -1 ) {
                $namebuf="noname_".$cnt++ if($namebuf=~/^\s*$/);                # CD 0037
                $uniquename = SB_SERVER_FavoritesName2UID( $namebuf );          # CD 0009 decode hinzugefügt # CD 0010 decode wieder entfernt
                push @SB_SERVER_PLS, "ADD $namebuf $idbuf $uniquename LMS";         # CD 0029
            }

        } else {
            $namebuf .= "_" . $_;
            next;
        }
    }
    # CD 0029 start
    if(scalar(@SB_SERVER_PLS)>0) {
        InternalTimer( gettimeofday() + 0.01,
                   "SB_SERVER_tcb_SendPlaylists",
                   "SB_SERVER_tcb_SendPlaylists:$name",
                   0 );
    }
    # CD 0029 end
    return;
}

# CD 0029 start
# für schwache Hardware Übertragung aufteilen
sub SB_SERVER_tcb_SendPlaylists( $ ) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    RemoveInternalTimer( "SB_SERVER_tcb_SendPlaylists:$name");

    my $a;
    my $t=time();

    do {
        $a=shift @SB_SERVER_PLS;    # CD 0045 Reihenfolge beibehalten
        if (defined($a)) {
            SB_SERVER_Broadcast( $hash, "PLAYLISTS", $a, undef );
        }
    } while ((time()<$t+0.05) && defined($a));

    if(scalar(@SB_SERVER_PLS)>0) {
    #Log 0,"SB_SERVER_tcb_SendPlaylists: ".scalar(@SB_SERVER_PLS)." entries remaining";
        InternalTimer( gettimeofday() + 0.05,
                   "SB_SERVER_tcb_SendPlaylists",
                   "SB_SERVER_tcb_SendPlaylists:$name",
                   0 );
    }
}
# CD 0029 end

# CD 0008 start
sub SB_SERVER_CheckConnection($) {
    my($in ) = shift;
    my(undef,$name) = split(':',$in);
    my $hash = $defs{$name};

    return if (IsDisabled($name));  # CD 0046

    Log3( $hash, 3, "SB_SERVER_CheckConnection($name): STATE: " . ReadingsVal($name, "state", "unknown") . " power: ". ReadingsVal( $name, "power", "X" )); # CD 0009 level 2->3 # CD 0038 state statt STATE verwenden
    if(ReadingsVal( $name, "power", "X" ) ne "on") {
        Log3( $hash, 3, "SB_SERVER_CheckConnection($name): forcing power on");      # CD 0009 level 2->3

        $hash->{helper}{pingCounter}=0;

        SB_SERVER_Broadcast( $hash, "SERVER",
                 "IP " . $hash->{IP} . ":" .
                 $hash->{helper}{httpport} );
        $hash->{helper}{doBroadcast}=1;

        SB_SERVER_LMS_Status( $hash );
        if( AttrVal( $name, "doalivecheck", "false" ) eq "false" ) {
            readingsSingleUpdate( $hash, "power", "on", 1 );
        } elsif( AttrVal( $name, "doalivecheck", "false" ) eq "true" ) {
            # start the alive checking mechanism
            # CD 0020 SB_SERVER_tcb_Alive verwenden
            RemoveInternalTimer( "SB_SERVER_Alive:$name");
            InternalTimer( gettimeofday() +
                       AttrVal( $name, "alivetimer", 10 ),
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );
        }
    }
    RemoveInternalTimer( "CheckConnection:$name");
}
# CD 0008 end

# ----------------------------------------------------------------------------
#  the Notify function
# ----------------------------------------------------------------------------
sub SB_SERVER_Notify( $$ ) {
    my ( $hash, $dev_hash ) = @_;
    my $name = $hash->{NAME}; # own name / hash
    my $devName = $dev_hash->{NAME}; # Device that created the events

    return if (IsDisabled($name));  # CD 0046

    # CD start
    if ($dev_hash->{NAME} eq "global" && grep (m/^INITIALIZED$|^REREADCFG$/,@{$dev_hash->{CHANGED}})){
        SB_SERVER_TryConnect( $hash , 0) unless defined($hash->{helper}{disableReconnect}); # CD 0038
    }
    # CD end
    #Log3( $hash, 3, "SB_SERVER_Notify($name): called" .
    #    "Own:" . $name . " Device:" . $devName . " Events:" . (join " ",@{$dev_hash->{CHANGED}}) );

    # CD 0024 start
    if( grep(m/^SAVE$|^SHUTDOWN$/, @{$dev_hash->{CHANGED}}) ) { # CD 0043 auch bei SHUTDOWN speichern
        SB_SERVER_SaveSyncGroups($hash) if($SB_SERVER_hasDataDumper==1);
        SB_SERVER_SaveServerStates($hash) if($SB_SERVER_hasDataDumper==1);
    }
    # CD 0024 end

    # CD 0008 start
    if($devName eq $name ) {
        if (grep (m/^DISCONNECTED$/,@{$dev_hash->{CHANGED}})) {
            Log3( $hash, 3, "SB_SERVER_Notify($name): DISCONNECTED - STATE: " . ReadingsVal($name, "state", "unknown") . " power: ". ReadingsVal( $name, "power", "X" ));   # CD 0009 level 2->3
            RemoveInternalTimer( "CheckConnection:$name");
        }
        if (grep (m/^CONNECTED$/,@{$dev_hash->{CHANGED}})) {
            Log3( $hash, 3, "SB_SERVER_Notify($name): CONNECTED - STATE: " . ReadingsVal($name, "state", "unknown") . " power: ". ReadingsVal( $name, "power", "X" ));      # CD 0009 level 2->3
            InternalTimer( gettimeofday() + 2,
                "SB_SERVER_CheckConnection",
                "CheckConnection:$name",
                 0 );
        }
    }
    # CD 0008 end

    if( $devName eq $hash->{RCCNAME} ) {
        if( ReadingsVal( $hash->{RCCNAME}, "state", "off" ) eq "off" ) {
            SB_SERVER_RemoveInternalTimers( $hash );
            # CD 0020 SB_SERVER_tcb_Alive verwenden
            InternalTimer( gettimeofday() + 10,
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );

            # CD 0007 use DevIo_Disconnected instead of DevIo_CloseDev
            #DevIo_CloseDev( $hash );
            DevIo_Disconnected( $hash );
            $hash->{helper}{pingCounter}=9999;                                  # CD 0007
            $hash->{CLICONNECTION} = "off";                                     # CD 0007
            # CD 0005 set state after DevIo_CloseDev
            # CD 0006 DevIo_setStates requires v7099 of DevIo.pm, replaced with SB_SERVER_setStates
            SB_SERVER_setStates($hash, "disconnected");
        } elsif( ReadingsVal( $hash->{RCCNAME}, "state", "off" ) eq "on" ) {
            SB_SERVER_RemoveInternalTimers( $hash );
            # do an update of the status, but SB CLI must come up
            # CD 0020 SB_SERVER_tcb_Alive verwenden
            InternalTimer( gettimeofday() + 20,
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );
        } else {
            return( undef );
        }
        return( "" );
    # CD 0007 start
    } elsif( $devName eq $hash->{PRESENCENAME} ) {
        my $pp=0;
        my $pa=0;
        my $ps;
        
        foreach my $line (@{$dev_hash->{CHANGED}}) {
            my @args=split(':',$line);
            my $ps;
            # Spezialfall 'state'
            $ps=trim($args[0]) if ((@args==1) && ($hash->{helper}{presenceReading} eq 'state'));
            
            # Reading: Value
            $ps=trim($args[1]) if ((@args==2) && ($hash->{helper}{presenceReading} eq trim($args[0])));

            if (defined($ps)) {
                Log3( $hash, 3, "SB_SERVER_Notify($name): $devName changed to ". $ps);    # CD 0023 loglevel 2->3
                $pp=$ps eq $hash->{helper}{presenceValuePresent};
                $pa=$ps eq $hash->{helper}{presenceValueAbsent};
            }
        }
        
        # Serverstatus geändert ?
        if (($pa)||($pp)) {
            $hash->{helper}{lastPRESENCEstate}=$ps;
            # CD 0023 end
            SB_SERVER_RemoveInternalTimers( $hash );
            # do an update of the status, but SB CLI must come up
            # CD 0020 SB_SERVER_tcb_Alive verwenden
            InternalTimer( gettimeofday() + 10,
                       "SB_SERVER_tcb_Alive",
                       "SB_SERVER_Alive:$name",
                       0 );
            return( "" );
        }
        return( undef );
    # CD 0007 end
    } else {
        return( undef );
    }
}

# ----------------------------------------------------------------------------
#  start up the LMS server status
# ----------------------------------------------------------------------------
sub SB_SERVER_LMS_Status( $ ) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME}; # own name / hash

    return if (IsDisabled($name));  # CD 0046

    # CD 0007 login muss als erstes gesendet werden
    $hash->{helper}{SB_SERVER_LMS_Status}=time();
    if( ( $hash->{USERNAME} ne "?" ) &&
        ( $hash->{PASSWORD} ne "?" ) ) {
        my ($user,$password)=SB_SERVER_readPassword($hash); # CD 0031
        if(defined($user)) {
            DevIo_SimpleWrite( $hash, "login " .
                       $user . " " .
                       $password . "\n",
                       0 );
        } else {
            Log3( $hash, 3, "SB_SERVER_LMS_Status($name): login " .
              "required but no username and password specified" );
        }
    }

    # subscribe us
    DevIo_SimpleWrite( $hash, "listen 1\n", 0 );

    # and get some info on the server
    DevIo_SimpleWrite( $hash, "pref authorize ?\n", 0 );
    DevIo_SimpleWrite( $hash, "version ?\n", 0 );
    DevIo_SimpleWrite( $hash, "serverstatus 0 200\n", 0 );
    DevIo_SimpleWrite( $hash, "favorites items 0 " .
		       AttrVal( $name, "maxfavorites", 100 ) . " want_url:1\n", 0 );   # CD 0009 url mit abfragen
    DevIo_SimpleWrite( $hash, "playlists 0 200\n", 0 );
    DevIo_SimpleWrite( $hash, "alarm playlists 0 300\n", 0 );       # CD 0011
    DevIo_SimpleWrite( $hash, "apps 0 200\n", 0 );  # CD 0029
    DevIo_SimpleWrite( $hash, "pref httpport ?\n", 0 );     # CD 0049
    # CD 0032 start
    if(defined($hash->{helper}{apps})) {
        my @enabledApps=split(',',AttrVal($name,'enablePlugins',''));
        foreach my $app (@enabledApps) {
            if(defined($hash->{helper}{apps}{$app})) {
                DevIo_SimpleWrite( $hash, ($hash->{helper}{apps}{$app}{cmd})." items 0 200\n", 0 );
            }
        }
    }
    # CD 0032 end

    return( true );
}

# CD 0038 start
sub SB_SERVER_RemoveInternalTimers($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    RemoveInternalTimer( $hash );
    RemoveInternalTimer( "SB_SERVER_Alive:$name");
    RemoveInternalTimer( "StartTalk:$name");
    RemoveInternalTimer( "RecallAfterTalk:$name");
    RemoveInternalTimer( "SB_SERVER_tcb_SendPlaylists:$name");
    RemoveInternalTimer( "SB_SERVER_tcb_SendFavorites:$name");
    RemoveInternalTimer( "SB_SERVER_tcb_SendSyncMasters:$name");
    RemoveInternalTimer( "SB_SERVER_tcb_SendAlarmPlaylists:$name");
    RemoveInternalTimer( "CheckConnection:$name");
}
# CD 0038 end


# CD 0006 start - added
# ----------------------------------------------------------------------------
#  copied from DevIo.pm 7099
# ----------------------------------------------------------------------------
sub SB_SERVER_setStates($$)
{
  my ($hash, $val) = @_;
  $hash->{STATE} = $val;
  setReadingsVal($hash, "state", $val, TimeNow());
}
# CD 0006 end

# ----------------------------------------------------------------------------
#  load/save sync groups
#
#  CD 0024
# ----------------------------------------------------------------------------
sub SB_SERVER_StatefileName($$)
{
  my( $name,$prefix ) = @_;

  my $statefile = $attr{global}{statefile};
  $statefile = substr $statefile,0,rindex($statefile,'/')+1;
  return $statefile . $prefix . "_$name.dd.save";
}

sub SB_SERVER_SaveSyncGroups($)
{
  my( $hash ) = @_;
  my $name = $hash->{NAME};

  return "No saved syncgroups found" unless(defined($hash->{helper}{syncGroups}));
  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = SB_SERVER_StatefileName($name,'sbsg');

  if(open(FH, ">$statefile")) {
    my $t = localtime;
    print FH "#$t\n";

    my $dumper = Data::Dumper->new([]);
    $dumper->Terse(1);

    $dumper->Values([$hash->{helper}{syncGroups}]);
    print FH $dumper->Dump;

    close(FH);
  } else {

    my $msg = "SB_SERVER_SaveSyncGroups: Cannot open $statefile: $!";
    Log3 $hash, 1, $msg;
  }

  return undef;
}

sub SB_SERVER_LoadSyncGroups($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = SB_SERVER_StatefileName($name,'sbsg');

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
    $hash->{helper}{syncGroups} = $decoded;
  } else {
    my $msg = "SB_SERVER_LoadSyncGroups: no syncgroups file found";
    Log3 undef, 4, $msg;
  }
  return undef;
}

sub SB_SERVER_BuildPlayerList($)
{
    my ($hash) = @_;
    my $name = $hash->{NAME};

    delete( $hash->{helper}{players} ) if (defined($hash->{helper}{players}));

    # build player list
    foreach my $mydev ( keys %defs ) {
        my $iodevhash;

        if( defined( $defs{$mydev}{IODev} ) ) {
            $iodevhash = $defs{$mydev}{IODev};
            if( ( defined( $defs{$mydev}{TYPE} ) ) &&
                ( $defs{$mydev}{TYPE} eq "SB_PLAYER" )){       # CD 0029 umsortiert
                if( ( defined( $iodevhash->{NAME} ) ) &&    # CD 0029 umsortiert
                    ( $iodevhash->{NAME} eq $name ) ) {
                    # we found a valid entry
                    my $chash = $defs{$mydev};
                    my $fn = $chash->{NAME};
                    my $ln = $chash->{PLAYERNAME};

                    if($ln ne '?') {
                        if(!defined($hash->{helper}{players}{$fn})) {
                            $hash->{helper}{players}{$fn}{fhemname}=$fn;
                            $hash->{helper}{players}{$fn}{lmsname}=$ln;
                            $hash->{helper}{players}{$fn}{mac}=$chash->{PLAYERMAC};
                            $hash->{helper}{players}{$fn}{type}='FHEM';
                        }
                        if(!defined($hash->{helper}{players}{$ln})) {
                            $hash->{helper}{players}{$ln}{fhemname}=$fn;
                            $hash->{helper}{players}{$ln}{lmsname}=$ln;
                            $hash->{helper}{players}{$ln}{mac}=$chash->{PLAYERMAC};
                            $hash->{helper}{players}{$ln}{type}='LMS';
                        }
                    }
                }
            }
        }
    }
}

# ----------------------------------------------------------------------------
#  load/save server state
#
#  CD 0025
# ----------------------------------------------------------------------------

sub SB_SERVER_SaveServerStates($)
{
  my( $hash ) = @_;
  my $name = $hash->{NAME};

  return "No server states found" unless(defined($hash->{helper}{savedServerStates}));
  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = SB_SERVER_StatefileName($name,'sbst');

  if(open(FH, ">$statefile")) {
    my $t = localtime;
    print FH "#$t\n";

    my $dumper = Data::Dumper->new([]);
    $dumper->Terse(1);

    $dumper->Values([$hash->{helper}{savedServerStates}]);
    print FH $dumper->Dump;

    close(FH);
  } else {

    my $msg = "SB_SERVER_SaveServerState: Cannot open $statefile: $!";
    Log3 $hash, 1, $msg;
  }

  return undef;
}

sub SB_SERVER_LoadServerStates($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = SB_SERVER_StatefileName($name,'sbst');

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
    $hash->{helper}{savedServerStates} = $decoded;
  } else {
    my $msg = "SB_SERVER_LoadServerState: no server state file found";
    Log3 undef, 4, $msg;
  }
  return undef;
}

sub SB_SERVER_Save($$) {
    my ( $hash, $statename ) = @_;
    my $name = $hash->{NAME};

    $statename='default' unless defined($statename);

    Log3( $hash, 3, "SB_SERVER_Save($name): name: $statename");

    delete($hash->{helper}{savedServerStates}{$statename}) if(defined($hash->{helper}{savedServerStates}) && defined($hash->{helper}{savedServerStates}{$statename}));

    SB_SERVER_BuildPlayerList($hash) if(!defined($hash->{helper}{players}));

    foreach my $e ( keys %{$hash->{helper}{players}} ) {
        if($e ne '') {
            if(defined($hash->{helper}{players}{$e})) {
                if($hash->{helper}{players}{$e}{type} eq 'FHEM') {
                    if( defined( $defs{$e} ) ) {
                        my $phash = $defs{$e};

                        $hash->{helper}{savedServerStates}{$statename}{players}{$e}{mac}=$hash->{helper}{players}{$e}{mac};
                        $hash->{helper}{savedServerStates}{$statename}{players}{$e}{power}=ReadingsVal($e,"power","off");
                        $hash->{helper}{savedServerStates}{$statename}{players}{$e}{volume}=ReadingsVal($e,"volume","0");

                        my $sm=InternalVal($e,"SYNCMASTER","none");
                        $hash->{helper}{savedServerStates}{$statename}{players}{$e}{syncMaster}=$sm;
                        if(($sm eq 'none') || ($sm eq $hash->{helper}{players}{$e}{mac})) {
                            SB_PLAYER_Save($phash,"xxx_sss_".$statename);
                        }
                    }
                }
            }
        }
    }
}

sub SB_SERVER_Recall($$) {
    my ( $hash, $arg ) = @_;   # CD 0036
    my $name = $hash->{NAME};

    my $del=0;
    my $delonly=0;

    my $statename;
    my @args=split " ",$arg;

    if(defined($args[0])) {
        $statename=$args[0];
    } else {
        $statename='default';
    }

    Log3( $hash, 3, "SB_SERVER_Recall($name): name: $statename");

    # Optionen auswerten
    for my $opt (@args) {
        $del=1 if($opt=~ m/^del$/);
        $delonly=1 if($opt=~ m/^delonly$/);
    }

    if(defined($hash->{helper}{savedServerStates}) && defined($hash->{helper}{savedServerStates}{$statename})) {
        if($delonly==0) {
            # unsync all & set power
            foreach my $e ( keys %{$hash->{helper}{savedServerStates}{$statename}{players}} ) {
                if($e ne '') {
                    if(defined($hash->{helper}{savedServerStates}{$statename}{players}{$e})) {
                        my $mac=$hash->{helper}{savedServerStates}{$statename}{players}{$e}{mac};
                        SB_SERVER_Write( $hash, $mac." sync -\n", "" );
                        if($hash->{helper}{savedServerStates}{$statename}{players}{$e}{power} eq 'on') {
                            SB_SERVER_Write( $hash, $mac." power 1\n", "" );
                        } else {
                            SB_SERVER_Write( $hash, $mac." power 0\n", "" );
                        }
                    }
                }
            }

            # sync slaves & set volume
            foreach my $e ( keys %{$hash->{helper}{savedServerStates}{$statename}{players}} ) {
                if($e ne '') {
                    if(defined($hash->{helper}{savedServerStates}{$statename}{players}{$e})) {
                        my $mac=$hash->{helper}{savedServerStates}{$statename}{players}{$e}{mac};
                        if (($hash->{helper}{savedServerStates}{$statename}{players}{$e}{syncMaster} ne 'none')
                            && ($hash->{helper}{savedServerStates}{$statename}{players}{$e}{syncMaster} ne $mac)) {
                            SB_SERVER_Write( $hash, $hash->{helper}{savedServerStates}{$statename}{players}{$e}{syncMaster}." sync $mac\n", "" );
                            SB_SERVER_Write( $hash, "$mac mixer volume ". $hash->{helper}{savedServerStates}{$statename}{players}{$e}{volume}. "\n", "" );
                        }
                    }
                }
            }

            # reload player states
            foreach my $e ( keys %{$hash->{helper}{savedServerStates}{$statename}{players}} ) {
                if($e ne '') {
                    if(defined($hash->{helper}{savedServerStates}{$statename}{players}{$e})) {
                        my $mac=$hash->{helper}{savedServerStates}{$statename}{players}{$e}{mac};
                        if (($hash->{helper}{savedServerStates}{$statename}{players}{$e}{syncMaster} eq 'none')
                            || ($hash->{helper}{savedServerStates}{$statename}{players}{$e}{syncMaster} eq $mac)) { # CD 0026 ne durch eq ersetzt
                            if( defined( $defs{$e} ) ) {
                                my $phash = $defs{$e};

                                SB_PLAYER_Recall($phash,"xxx_sss_".$statename);
                            }
                        }
                    }
                }
            }
        }
        if(($del==1)||($delonly==1)) {
            # delete
            foreach my $e ( keys %{$hash->{helper}{savedServerStates}{$statename}{players}} ) {
                if($e ne '') {
                    if(defined($hash->{helper}{savedServerStates}{$statename}{players}{$e})) {
                        if( defined( $defs{$e} ) ) {
                            my $phash = $defs{$e};

                            SB_PLAYER_Recall($phash,"xxx_sss_".$statename." delonly");
                        }
                    }
                }
            }
            delete($hash->{helper}{savedServerStates}{$statename});
        }
    }
}

# CD 0031 User und Passwort speichern/lesen, aus 72_FRITZBOX
sub SB_SERVER_storePassword($$$)
{
    my ($hash, $user, $password) = @_;

    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;

    my $enc_pwd = "";

    if(eval "use Digest::MD5;1")
    {
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }

    for my $char (split //, $password)
    {
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }

    my $err = setKeyValue($hash->{TYPE}."_".$hash->{NAME}."_user", $user);
    return "error while saving the user - $err" if(defined($err));

    $err = setKeyValue($index, $enc_pwd);
    return "error while saving the password - $err" if(defined($err));

    return "user and password successfully saved";
}

sub SB_SERVER_readPassword($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};

   my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
   my $key = getUniqueId().$index;

   my ($user, $password, $err);

   ($err, $password) = getKeyValue($index);

   if ( defined($err) ) {
      Log3 $hash, 2, "SB_SERVER_readPassword($name): unable to read SB_SERVER password: $err";
      return undef;
   }

   my $dec_pwd = '';

   if ( defined($password) ) {
      if ( eval "use Digest::MD5;1" ) {
         $key = Digest::MD5::md5_hex(unpack "H*", $key);
         $key .= Digest::MD5::md5_hex($key);
      }

      for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
         my $decode=chop($key);
         $dec_pwd.=chr(ord($char)^ord($decode));
         $key=$decode.$key;
      }
   } else {
      Log3 $hash, 2, "SB_SERVER_readPassword($name): No password found";
      return undef;
   }

   ($err, $user) = getKeyValue($hash->{TYPE}."_".$hash->{NAME}."_user");

   if ( defined($err) ) {
      Log3 $hash, 2, "SB_SERVER_readPassword($name): unable to read SB_SERVER user: $err";
      return undef;
   }
   if ( defined($user) ) {
        return ($user,$dec_pwd)
   } else {
      Log3 $hash, 2, "SB_SERVER_readPassword($name): No user found";
      return undef;
   }
}
# CD 0031 end

# ############################################################################
#  No PERL code beyond this line
# ############################################################################
1;

=pod
=item device
=item summary    connect to a Logitech Media Server (LMS)
=item summary_DE Anbindung an Logitech Media Server (LMS)
=begin html

<a name="SB_SERVER"></a>
<h3>SB_SERVER</h3>
<ul>
  <a name="SBserverdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SB_SERVER &lt;ip|hostname[:cliserverport]&gt; [RCC:&lt;RCC&gt;] [WOL:&lt;WOL&gt;[:&lt;command&gt;[:&lt;value&gt;]]] [PRESENCE:&lt;PRESENCE&gt;[:&lt;reading&gt;[:&lt;value for present&gt;[:&lt;value for absent&gt;]]]] [USER:&lt;username&gt;] [PASSWORD:&lt;password&gt;]</code>
    <br><br>

    This module allows you in combination with the module SB_PLAYER to control a
    Logitech Media Server (LMS) and connected Squeezebox Media Players.<br><br>

    Attention:  The <code>[:cliserverport]</code> parameter is
    optional. You just need to configure it if you changed it on the LMS.
    The default TCP port is 9090.<br><br>
    <b>Optional</b>
    <ul>
      <li><code>&lt;[RCC]&gt;</code>: You can define a FHEM RCC Device, if you want to wake it up when you set the SB_SERVER on.  </li>
      <li><code>&lt;[WOL]&gt;</code>: You can define a FHEM WOL Device, if you want to wake it up when you set the SB_SERVER on.
      Command and value can be optionally configured, by default command is empty and 'on' is used as value.</li>
      <li><code>&lt;[PRESENCE]&gt;</code>: You can define a FHEM PRESENCE Device that is used to check if the server is reachable.
      Optionally a reading and values for present and absent can be added,
      by default the reading 'state' and the values 'present' and 'absent' are used.</li>
      <li><code>&lt;username&gt;</code> and <code>&lt;password&gt;</code>: If your LMS is password protected you can define the credentials here.  </li>
    </ul><br>
  </ul>
  <a name="SBserverset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt;</code>
    <br><br>
    This module supports the following SB_Server related commands:<br><br>
    <ul>
      <li><b>abort</b> -  Stops the connection to the server</li>
      <li><b>addToFHEMUpdate</b> -  Includes the modules in the FHEM update, needs to be executed only once</li>
      <li><b>cliraw &lt;cli-command&gt;</b> -  Sends a &lt;cli-command&gt; to the LMS CLI</li>
      <li><b>on</b> -  Tries to switch on the Server by WOL or RCC</li>
      <li><b>removeFromFHEMUpdate</b> -  Removes the modules from the FHEM update</li>
      <li><b>renew</b> -  Renews the connection to the server</li>
      <li><b>rescan</b> -  Starts the scan of the music library of the server</li>
      <li><b>statusRequest</b> -  Update of readings from server and configured players</li>
      <li><b>save [&lt;name&gt;]</b> -  Save all players state</li>
      <li><b>recall [&lt;name&gt;] [options] </b> -  recall all players state<br>Options:</li>
        <ul>
          <li>del - delete saved state after restore</li>
          <li>delonly - delete saved state without restoring</li>
        </ul>
    </ul>
    <br><br>
    The command <code>syncGroup</code> can be used to manage group templates for synchronizing players. Each template
    contains a list of players and can be activated on demand.
    Possible subcommands:<br><br>
    <ul>
      <li><b>addp &lt;playerName[,playerName...]&gt; &lt;template&gt;</b> -  Add the specified player(s) to the template.
      if the template doesn't exist, it is created automatically and the first player will be group master.</li>
      <li><b>removep &lt;playerName[,playerName...]&gt; &lt;template&gt;</b> -  Remove the specified player(s) from the
      template. If one of the players was group master, the first remaining player will become new group master.</li>
      <li><b>masterp &lt;playerName&gt; &lt;template&gt;</b> -  Change the group master.</li>
      <li><b>load [poweron] &lt;template&gt;</b> -  Activate the template. The players of the template are unsynced from their
      groups and added to a new group. With the optional keyword <code>poweron</code>, FHEM tries to power on all the players.</li>
      <li><b>delete &lt;template&gt;</b> -  Delete the template.</li>
      <li><b>deleteall</b> -  Delete all templates.</li>
      <li><b>talk &lt;template&gt; &lt;text&gt;</b> -  Save the state of all the players, activate the template and output &lt;text&gt; using
      the configured TTS provider. Restore the state of all the players after the end of the TTS output.
      With the optional keyword <code>poweron</code>, FHEM tries to power on all the players.</li>
      <li><b>resetTTS</b> -  Reset TTS output.</li>
      <li><b>volume &lt;template&gt; &lt;n&gt;</b> -  Set the volume to &lt;n&gt; if the template is active.</li>
      <li><b>volume &lt;template&gt; +|-&lt;n&gt;</b> - Increase or decrease the volume by the given value if the template is active.</li>
    </ul>
    <br>
  </ul>
  <a name="SBserverattr"></a>
  <b>Attributes</b>
  <ul>
    <li><code>alivetimer &lt;sec&gt;</code><br>
    Default: 120. Every &lt;sec&gt; seconds it is checked, whether the computer with its LMS is still reachable
    – either via an internal ping (that leads regulary to problems) or via PRESENCE (preferred, no problems)
    - and running.</li>
    <li><code>doalivecheck &lt;true|false&gt;</code><br>
    Switches the LMS-monitoring on or off.</li>
    <li><code>enablePlugins &lt;plugin1[,pluginX]&gt;</code><br>
    Adds the playlists and favorites (if available) of the specified LMS-plugins.</li>
    <li><code>httpport &lt;port&gt;</code><br>
    Normally the http-port is automatically detected. This attribute can be used to override the detected value.
    You can check the port-number of the LMS within its setup under Setup – Network – Web Server Port Number.</li>
    <li><a name="SBserver_attribut_ignoredIPs"><code>ignoredIPs &lt;IP-Address[,IP-Address]&gt;</code>
    </a><br />With this attribute you can define IP-addresses of players which will to be ignored by the server, e.g. "192.168.0.11,192.168.0.37"</li>
    <li><a name="SBserver_attribut_ignoredMACs"><code>ignoredMACs &lt;MAC-Address[,MAC-Address]&gt;</code>
    </a><br />With this attribute you can define MAC-addresses of players which will to be ignored by the server, e.g. "00:11:22:33:44:55,ff:ee:dd:cc:bb:aa"</li>
    <li><code>internalPingProtocol icmp|tcp|udp|syn|stream|none</code><br>
    Specifies the protocol for the internal ping, default is tcp.</li>
    <li><code>maxcmdstack &lt;quantity&gt;</code><br>
    By default the stack ist set up to 200. If the connection to the LMS is lost, up to &lt;quantity&gt;
    commands are buffered. After the link is reconnected, commands, that are not older than five minutes,
    are send to the LMS.</li>
    <li><code>maxfavorites &lt;number&gt;</code><br>
    Adjust here the maximal number of the favourites.</li>
  </ul>
</ul>
=end html

=begin html_DE

<a name="SB_SERVER"></a>
<h3>SB_SERVER</h3>
<ul>
  <a name="SBserverdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SB_SERVER &lt;ip|hostname[:cliserverport]&gt; [RCC:&lt;RCC&gt;] [WOL:&lt;WOL&gt;[:&lt;Befehl&gt;[:&lt;Wert&gt;]]] [PRESENCE:&lt;PRESENCE&gt;[:&lt;Reading&gt;[:&lt;Wert für anwesend&gt;[:&lt;Wert für abwesend&gt;]]]] [USER:&lt;Benutzername&gt;] [PASSWORD:&lt;Passwort&gt;]</code>
    <br><br>

    Diese Modul erm&ouml;glicht es - zusammen mit dem Modul SB_PLAYER - einen
    Logitech Media Server (LMS) und die angeschlossenen Squeezebox Media
    Player zu steuern.<br><br>

    Achtung: Die Angabe des Parameters <code>[:cliserverport]</code> ist
    optional und nur dann erforderlich, wenn die Portnummer im LMS vom
    Standardwert (TCP Port 9090) abweichend eingetragen wurde.<br><br>

    <b>Optionen</b>
    <ul>
      <li><code>&lt;[RCC]&gt;</code>: Hier kann ein FHEM RCC Device angegeben werden mit dem der Server aufgeweckt und eingeschaltet werden kann.</li>
      <li><code>&lt;[WOL]&gt;</code>: Hier kann ein FHEM WOL Device angegeben werden mit dem der Server aufgeweckt und eingeschaltet werden kann.
      Optional k&ouml;nnen Befehl und Wert mit angegeben werden, voreingestellt ist kein Befehl und der Wert 'on'.</li>
      <li><code>&lt;[PRESENCE]&gt;</code>: Hier kann ein FHEM PRESENCE Device angegeben
      werden mit dem die Erreichbarkeit des Servers &uuml;berpr&uuml;ft werden kann.
      Optional k&ouml;nnen Reading und Werte f&uuml;r an/abwesend mit angegeben werden,
      voreingestellt ist das Reading 'state' und die Werte 'present' und 'absent'.</li>
      <li><code>&lt;Benutzername&gt;</code> und <code>&lt;Passwort&gt;</code>: Falls der Server durch ein Passwort gesichert wurde, k&ouml;nnen hier die notwendigen Angaben für den Serverzugang angegeben werden.</li>
    </ul><br>
  </ul>
  <a name="SBserverset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;command&gt;</code>
    <br><br>
    Dieses Modul unterst&uuml;tzt folgende SB_SERVER relevanten Befehle:<br><br>
    <ul>
      <li><b>abort</b> -  Bricht die Verbindung zum Server ab.</li>
      <li><b>addToFHEMUpdate</b> -  F&uuml;gt die Module dem FHEM-Update hinzu, muss nur einmalig ausgef&uuml;hrt werden.</li>
      <li><b>cliraw &lt;cli-command&gt;</b> -  Sendet einen CLI-Befehl an das LMS CLI</li>
      <li><b>on</b> -  Versucht den Server per WOL oder RCC einzuschalten.</li>
      <li><b>removeFromFHEMUpdate</b> -  Schlie&szlig;t die Module vom FHEM-Update aus.</li>
      <li><b>renew</b> -  Erneuert die Verbindung zum Server.</li>
      <li><b>rescan</b> -  Startet einen Scan der Musikbibliothek f&uuml;r alle im Server angegebenen Verzeichnisse.</li>
      <li><b>statusRequest</b> -  Aktualisiert die Readings von Server und konfigurierten Playern.</li>
      <li><b>save [&lt;name&gt;]</b> -  Speichert den Zustand aller Player unter dem Namen &lt;name&gt; ab.</li>
      <li><b>recall [&lt;name&gt;] [options] </b> -  Ruft den Zustand aller Player auf.<br>Optionen:</li>
        <ul>
          <li>del - L&ouml;scht nach dem Restore den gespeicherten Status</li>
          <li>delonly - L&ouml;scht den gespeicherten Status ohne vorherigem Restore</li>
        </ul>
    </ul>
    <br><br>
    Der Befehl <code>syncGroup</code> dient zur Verwaltung von Gruppenvorlagen für die Synchronisierung der Player.
    Dar&uuml;ber k&ouml;nnen Gruppen von Playern angelegt werden die sich bei Bedarf aktivieren lassen. Die Vorlagen
    werden bei SAVE und SHUTDOWN von FHEM abgespeichert und beim Start von FHEM geladen.
    Folgende Unterbefehle sind definiert:<br><br>
    <ul>
      <li><b>addp &lt;playerName[,playerName...]&gt; &lt;Vorlage&gt;</b> -  F&uuml;gt die angegebenen Player zur Vorlage hinzu, wenn die
      Vorlage noch nicht existiert wird sie angelegt und der erste Player wird Master.</li>
      <li><b>removep &lt;playerName[,playerName...]&gt; &lt;Vorlage&gt;</b> -  Entfernt die angegebenen Player aus der Vorlage, falls
      einer Master war wird der 1. verbleibende Player der Vorlage zum neuen Master.</li>
      <li><b>masterp &lt;playerName&gt; &lt;Vorlage&gt;</b> -  Legt den angegebenen Player als Master fest.</li>
      <li><b>load [poweron] &lt;Vorlage&gt;</b> -  Aktiviert die angegebene Vorlage, die betroffenen Player werden entsynchronisiert
      und zu einer neuen Gruppe zusammengef&uuml;gt. Wenn zus&auml;tzlich <code>poweron</code> angegeben wird, werden die Player
      eingeschaltet.</li>
      <li><b>delete &lt;Vorlage&gt;</b> -  L&ouml;scht die angegebene Vorlage.</li>
      <li><b>deleteall</b> -  L&ouml;scht alle Gruppenvorlagen.</li>
      <li><b>talk &lt;Vorlage&gt; &lt;Text&gt;</b> -  Speichert den Zustand aller Player ab, aktiviert die angegebene Vorlage und spielt
      den Text &uuml;ber den beim Player konfigurierten TTS-Dienst ab. Nach Ende der Durchsage wird der vorherige Zustand der Player wieder
      hergestellt. Wenn zus&auml;tzlich <code>poweron</code> angegeben wird, wird versucht die Player einzuschalten.</li>
      <li><b>resetTTS</b> -  TTS zur&uuml;cksetzen, kann n&ouml;tig sein wenn die Ausgabe h&auml;ngt.</li>
      <li><b>volume &lt;Vorlage&gt; &lt;n&gt;</b> -  Stellt die Lautst&auml;rke auf einen Wert &lt;n&gt; ein. Dabei muss &lt;n&gt;
      eine Zahl zwischen 0 und 100 sein. Der Befehl wird nur ausgeführt wenn die Vorlage aktiv ist.</li>
      <li><b>volume &lt;Vorlage&gt; +|-&lt;n&gt;</b> - Erh&ouml;ht oder vermindert die Lautst&auml;rke um den Wert, der durch +|-&lt;n&gt;
      vorgegeben wird. Dabei muss &lt;n&gt; eine Zahl zwischen 0 und 100 sein. Der Befehl wird nur ausgeführt wenn die Vorlage aktiv ist.</li>
    </ul>
    <br>
  </ul>
  <a name="SBserverattr"></a>
  <b>Attribute</b>
  <ul>
    <li><code>alivetimer &lt;sec&gt;</code><br>
    Default 120. Alle &lt;sec&gt; Sekunden wird &uuml;berpr&uuml;ft, ob der Rechner mit dem LMS noch erreichbar ist
    - entweder über internen Ping (f&uuml;hrt zu regelm&auml;&szlig;igen H&auml;ngern von FHEM) oder PRESENCE (bevorzugt,
    keine H&auml;nger) - und ob der LMS noch l&auml;uft.</li>
    <li><code>doalivecheck &lt;true|false&gt;</code><br>
    &Uuml;berwachung des LMS ein- oder auschalten.</li>
    <li><code>enablePlugins &lt;plugin1[,pluginX]&gt;</code><br>
    Bindet die Wiedergabelisten und Favoriten (soweit vorhanden) von LMS-Plugins (z.B. Spotify) ein.</li>
    <li><code>httpport &lt;port&gt;</code><br>
    Im Normalfall wird der http-Port automatisch ermittelt. Sollte dies NICHT funktionieren kann er über das Attribut fest vorgegeben werden.
    Zur &Uuml;berpr&uuml;fung kann im Server unter Einstellungen – Erweitert –Netzwerk
    - Anschlussnummer des Webservers nachgeschlagen werden.</li>
    <li><a name="SBserver_attribut_ignoredIPs"><b><code>ignoredIPs &lt;IP-Adresse&gt;[,IP-Adresse]</code></b>
    </a><br />Mit diesem Attribut kann die automatische Erkennung dedizierter Ger&auml;te durch die Angabe derer IP-Adressen unterdrückt werden, z.B. "192.168.0.11,192.168.0.37"</li>
    <li><a name="SBserver_attribut_ignoredMACs"><b><code>ignoredMACs &lt;MAC-Adresse&gt;[,MAC-Adresse]</code></b>
    </a><br />Mit diesem Attribut kann die automatische Erkennung dedizierter Ger&auml;te durch die Angabe derer MAC-Adressen unterdrückt werden, z.B. "00:11:22:33:44:55,ff:ee:dd:cc:bb:aa"</li>
    <li><code>internalPingProtocol icmp|tcp|udp|syn|stream|none</code><br>
    Legt fest welches Protokoll für den internen Ping verwendet wird. Wenn das Attribut nicht definiert ist, wird tcp verwendet.</li>
    <li><code>maxcmdstack &lt;Anzahl&gt;</code><br>
    Default ist der Stack auf eine Gr&ouml;&szlig;e von 200 eingestellt. Wenn die Verbindung zum LMS unterbrochen ist,
    werden bis zu &lt;Anzahl&gt; Befehle zwischengespeichert. Nach dem Verbindungsaufbau werden die Befehle,
    die nicht &auml;lter als 5 Minuten sind, an den LMS geschickt.</li>
    <li><code>maxfavorites &lt;Anzahl&gt;</code><br>
    Die maximale Anzahl der Favoriten wird hier eingestellt.</li>
  </ul>
</ul>
=end html_DE

=cut

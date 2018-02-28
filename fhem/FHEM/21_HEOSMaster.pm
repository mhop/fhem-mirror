###############################################################################
#
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Olaf Schnicke         Thanks for many many Code
#       - Dieter Hehlgans       Thanks for Commandref
#
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

#################################
######### Wichtige Hinweise und Links #################
#
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#  
#   readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
##
##
##
#

################################

package main;

use strict;
use warnings;
#use Data::Dumper;

my $missingModul = "";

eval "use Net::Telnet;1" or $missingModul .= "Net::Telnet ";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Encode;1" or $missingModul .= "Encode ";




my $version = "1.0.3";

my %heosCmds = (
    'enableChangeEvents'        => 'system/register_for_change_events?enable=',
    'checkAccount'              => 'system/check_account',
    'signAccountIn'             => 'system/sign_in?',
    'signAccountOut'            => 'system/sign_out',
    'reboot'                    => 'system/reboot',
    'getMusicSources'           => 'browse/get_music_sources',
    'browseSource'              => 'browse/browse?',
    'getPlayers'                => 'player/get_players',
    'getGroups'                 => 'group/get_groups',
    'getPlayerInfo'             => 'player/get_player_info?',
    'getGroupInfo'              => 'group/get_group_info?',
    'getPlayState'              => 'player/get_play_state?',
    'getPlayMode'               => 'player/get_play_mode?',
    'getMute'                   => 'player/get_mute?',
    'getGroupMute'              => 'group/get_mute?',
    'getQueue'                  => 'player/get_queue?',
    'playQueueItem'             => 'player/play_queue?',
    'clearQueue'                => 'player/clear_queue?',
    'saveQueue'                 => 'player/save_queue?',
    'getVolume'                 => 'player/get_volume?',
    'getGroupVolume'            => 'group/get_volume?',
    'setPlayState'              => 'player/set_play_state?',
    'setPlayMode'               => 'player/set_play_mode?',
    'setMute'                   => 'player/set_mute?',
    'setGroupMute'              => 'group/set_mute?',
    'playNext'                  => 'player/play_next?',
    'playPrev'                  => 'player/play_previous?',
    'playPresetStation'         => 'browse/play_preset?',
    'playInput'                 => 'browse/play_input?',
    'playStream'                => 'browse/play_stream?',
    'playPlaylist'              => 'browse/add_to_queue?',
    'renamePlaylist'            => 'browse/rename_playlist?',
    'deletePlaylist'            => 'browse/delete_playlist?',
    'setVolume'                 => 'player/set_volume?',
    'setGroupVolume'            => 'group/set_volume?',
    'volumeUp'                  => 'player/volume_up?',
    'volumeDown'                => 'player/volume_down?',
    'GroupVolumeUp'             => 'group/volume_up?',
    'GroupVolumeDown'           => 'group/volume_down?',
    'getNowPlayingMedia'        => 'player/get_now_playing_media?',
    'eventChangeVolume'         => 'event/player_volume_changed',
    'createGroup'               => 'group/set_group?',
    'searchCriteria'            => 'browse/get_search_criteria?',
    'search'                    => 'browse/search?'
);


# Declare functions
sub HEOSMaster_Initialize($);
sub HEOSMaster_Define($$);
sub HEOSMaster_Undef($$);
sub HEOSMaster_Set($@);
sub HEOSMaster_Open($);
sub HEOSMaster_Close($);
sub HEOSMaster_Read($);
sub HEOSMaster_Write($@);
sub HEOSMaster_Attr(@);
sub HEOSMaster_FirstRun($);
sub HEOSMaster_ResponseProcessing($$);
sub HEOSMaster_WriteReadings($$);
sub HEOSMaster_GetPlayers($);
sub HEOSMaster_EnableChangeEvents($);
sub HEOSMaster_PreProcessingReadings($$);
sub HEOSMaster_ReOpen($);
sub HEOSMaster_ReadPassword($);
sub HEOSMaster_StorePassword($$);
sub HEOSMaster_GetGroups($);
sub HEOSMaster_ProcessRead($$);
sub HEOSMaster_ParseMsg($$);
sub HEOSMaster_CheckAccount($);
sub HEOSMaster_Get($$@);
sub HEOSMaster_GetFavorites($);
sub HEOSMaster_GetHistory($);
sub HEOSMaster_GetInputs($);
sub HEOSMaster_GetMusicSources($);
sub HEOSMaster_GetPlaylists($);
sub HEOSMaster_GetServers($);
sub HEOSMaster_MakePlayLink($$$$$$$);
sub HEOSMaster_MakeImage($$);




sub HEOSMaster_Initialize($) {

    my ($hash) = @_;

    
    # Provider
    $hash->{ReadFn}     =   "HEOSMaster_Read";
    $hash->{WriteFn}    =   "HEOSMaster_Write";
    $hash->{Clients}    =   ":HEOSPlayer:";
    $hash->{MatchList}  = { "1:HEOSPlayer"      => '.*{"command":."player.*|.*{"command":."event\/player.*|.*{"command":."event\/repeat_mode_changed.*|.*{"command":."event\/shuffle_mode_changed.*|.*{"command":."event\/favorites_changed.*',
                            "2:HEOSGroup"       => '.*{"command":."group.*|.*{"command":."event\/group.*'
                            };

    # Consumer
    $hash->{SetFn}      = "HEOSMaster_Set";
    $hash->{GetFn}      = "HEOSMaster_Get";
    $hash->{DefFn}      = "HEOSMaster_Define";
    $hash->{UndefFn}    = "HEOSMaster_Undef";
    $hash->{AttrFn}     = "HEOSMaster_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          "heosUsername ".
                          $readingFnAttributes;

    foreach my $d(sort keys %{$modules{HEOSMaster}{defptr}}) {
    
        my $hash = $modules{HEOSMaster}{defptr}{$d};
        $hash->{VERSION}    = $version;
    }
}

sub HEOSMaster_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <name> HEOSMaster <HOST>" if( @a != 3 );
    return "Cannot define a HEOS device. Perl modul $missingModul is missing." if ( $missingModul );
    
    my $name            = $a[0];
    my $host            = $a[2];

    $hash->{HOST}       = $host;
    $hash->{VERSION}    = $version;


    Log3 $name, 3, "HEOSMaster ($name) - defined with host $host";
    $attr{$name}{room} = "HEOS" if( !defined( $attr{$name}{room} ) );

    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,'state','Initialized');
    readingsBulkUpdate($hash,'enableChangeEvents', 'off');
    readingsEndUpdate($hash,1);

    if( $init_done ) {
    
        HEOSMaster_FirstRun($hash);
        
    } else {
    
        InternalTimer( gettimeofday()+15, 'HEOSMaster_FirstRun', $hash, 0 ) if( ($hash->{HOST}) );
    }
    
    $modules{HEOSMaster}{defptr}{$host} = $hash;
    return undef;
}

sub HEOSMaster_Undef($$) {

    my ( $hash, $arg ) = @_;
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};

    
    HEOSMaster_Close($hash);
    delete $modules{HEOSMaster}{defptr}{$hash->{HOST}};
    
    Log3 $name, 3, "HEOSMaster ($name) - device $name deleted";
    return undef;
}

sub HEOSMaster_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
        
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "HEOSMaster ($name) - disabled";
            
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSMaster ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
        
            Log3 $name, 3, "HEOSMaster ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        
        } elsif( $cmd eq "del" ) {
        
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HEOSMaster ($name) - delete disabledForIntervals";
        }
    }
    
    return undef;
}

sub HEOSMaster_Get($$@) {

    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;
    my $pid     = $hash->{PID};

    
    if( $cmd eq 'showAccount' ) {
        return "usage: $cmd" if( @args != 0 );
    
        return AttrVal($name,'heosUsername',0) . ":" .HEOSMaster_ReadPassword($hash);
    }
    
    my $list = 'showAccount:noArg';
    return "Unknown argument $cmd, choose one of $list";
}

sub HEOSMaster_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params)  = @args;
    my $action;
    my $heosCmd;

    
    if($cmd eq 'reopen') {
        return "usage: $cmd" if( @args != 0 );
        
        HEOSMaster_ReOpen($hash);
        return undef;
        
    } elsif($cmd eq 'getPlayers') {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'getPlayers';
        $action     = undef;
        
    } elsif($cmd eq 'getGroups') {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = 'getGroups';
        $action     = undef;
        
    } elsif($cmd eq 'enableChangeEvents') {
        my $param = "on|off";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        $heosCmd    = $cmd;
        $action     = $args[0];
        
    } elsif($cmd eq 'checkAccount') {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        $action     = undef;
        
    } elsif($cmd eq 'signAccount') {
        my $param = "In|Out";
        return "usage: $cmd $param" if( @args != 1 || ! grep { $_ =~ /$args[0]/ } split(/\|/, $param) );
        
        return "please set account informattion first" if(AttrVal($name,'heosUsername','none') eq 'none');
        $heosCmd    = $cmd . $args[0];
        $action     = 'un='. AttrVal($name,'heosUsername','none') . '&pw=' . HEOSMaster_ReadPassword($hash) if($args[0] eq 'In');
        
    } elsif($cmd eq 'password') {
        return "usage: $cmd" if( @args != 1 );
        
        return HEOSMaster_StorePassword( $hash, $args[0] );
        
    } elsif($cmd eq 'reboot') {
        return "usage: $cmd" if( @args != 0 );
        
        $heosCmd    = $cmd;
        $action     = undef;
    
    } else {
    
        my  $list = "";
        $list .= "reopen:noArg getPlayers:noArg getGroups:noArg enableChangeEvents:on,off checkAccount:noArg signAccount:In,Out password reboot";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    HEOSMaster_Write($hash,$heosCmd,$action,undef);
}

sub HEOSMaster_Open($) {
    
    my $hash        = shift;
    my $name        = $hash->{NAME};
    my $host        = $hash->{HOST};
    my $port        = 1255;
    my $timeout     = 0.1;
    my $user        = AttrVal($name,'heosUsername',undef);
    my $password    = HEOSMaster_ReadPassword($hash);

    
    Log3 $name, 4, "HEOSMaster ($name) - Build socket connection";

    my $socket = new Net::Telnet ( Host=>$host,
        Port => $port,
        Timeout=>$timeout,
        Errmode=>'return')
        or return Log3 $name, 3, "HEOSMaster ($name) Couldn't connect to $host:$port";

    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $selectlist{$name} = $hash;

    readingsSingleUpdate($hash, 'state', 'connected', 1 );
    Log3 $name, 4, "HEOSMaster ($name) - Socket Connected";

    #hinzugefügt laut Protokoll 2.1.1 Initsequenz
    HEOSMaster_Write($hash,'enableChangeEvents','off',undef);
    Log3 $name, 4, "HEOSMaster ($name) - set enableChangeEvents off";

    #hinzugefügt laut Protokoll 2.1.1 Initsequenz
    if( defined($user) and defined($password) ) {
    
        HEOSMaster_Write($hash,'signAccountIn',"un=$user&pw=$password",undef);
        Log3 $name, 4, "HEOSMaster ($name) - sign in";
    }
    
    HEOSMaster_GetPlayers($hash);
    InternalTimer( gettimeofday()+1, 'HEOSMaster_EnableChangeEvents', $hash, 0 );
    InternalTimer( gettimeofday()+2, 'HEOSMaster_GetMusicSources', $hash, 0 );
    InternalTimer( gettimeofday()+3, 'HEOSMaster_GetGroups', $hash, 0 );
    InternalTimer( gettimeofday()+10, 'HEOSMaster_GetPlayers', $hash, 0 );
}

sub HEOSMaster_Close($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    return if( !$hash->{CD} );
    
    close($hash->{CD}) if($hash->{CD});
    delete($hash->{FD});
    delete($hash->{CD});
    delete($selectlist{$name});
    
    readingsSingleUpdate($hash, 'state', 'not connected', 1 );
}

sub HEOSMaster_ReOpen($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    HEOSMaster_Close($hash);
    HEOSMaster_Open($hash) if( !$hash->{CD} or !defined($hash->{CD}) );
}

sub HEOSMaster_Write($@) {
    
    my ($hash,$heosCmd,$value,$blocking)  = @_;
    my $name                    = $hash->{NAME};
    my $string  = "heos://$heosCmds{$heosCmd}";

    if( defined($value) ) {
    
        $string    .= "${value}" if( $value ne '&' );
    }
    
    if ( defined $blocking ) {
    
        my $idx = $blocking->{cl}{LASTACCESS};
        $hash->{helper}{blocking}{$idx} = $blocking;
        $string .= "&SEQUENCE=$idx";
    }
    
    $string    .= "\r\n";
    Log3 $name, 4, "HEOSMaster ($name) - WriteFn called";
    
    return Log3 $name, 4, "HEOSMaster ($name) - socket not connected"
    unless($hash->{CD});
    
    Log3 $name, 5, "HEOSMaster ($name) - $string";
    syswrite($hash->{CD}, $string);
    
    return undef;
}

sub HEOSMaster_Read($) {
    
    my $hash = shift;
    my $name = $hash->{NAME};
    my $len;
    my $buf;

    
    Log3 $name, 4, "HEOSMaster ($name) - ReadFn gestartet";
    $len = sysread($hash->{CD},$buf,1024);
    
    if( !defined($len) || !$len ) {
    
        Log3 $name, 5, "HEOSMaster ($name) - connection closed by remote Host";
        HEOSMaster_Close($hash);
        return;
    }
    
    unless( defined $buf) {
    
        Log3 $name, 3, "HEOSMaster ($name) - no data received";
        return;
    }
    
    Log3 $name, 5, "HEOSMaster ($name) - received buffer data, start HEOSMaster_ProcessRead: $buf";
    HEOSMaster_ProcessRead($hash,$buf);
}

sub HEOSMaster_ProcessRead($$) {
    
    my ($hash, $data) = @_;
    my $name = $hash->{NAME};
    my $buffer = '';

    
    Log3 $name, 4, "HEOSMaster ($name) - process read";
    #include previous partial message
    
    if(defined($hash->{PARTIAL}) && $hash->{PARTIAL}) {
    
        Log3 $name, 5, "HEOSMaster ($name) - PARTIAL: " . $hash->{PARTIAL};
        $buffer = $hash->{PARTIAL};
    
    } else {
    
        Log3 $name, 4, "HEOSMaster ($name) - No PARTIAL buffer";
    }
    
    Log3 $name, 5, "HEOSMaster ($name) - Incoming data: " . $data;
    
    $buffer = $buffer  . $data;
    
    Log3 $name, 5, "HEOSMaster ($name) - Current processing buffer (PARTIAL + incoming data): " . $buffer;
    
    my ($json,$tail) = HEOSMaster_ParseMsg($hash, $buffer);
    #processes all complete messages
    
    while($json) {
    
        $hash->{LAST_RECV} = time();
        Log3 $name, 5, "HEOSMaster ($name) - Decoding JSON message. Length: " . length($json) . " Content: " . $json;

        my $obj = eval{decode_json($json)};
        if($@){
            Log3 $name, 3, "HEOSMaster ($name) - JSON error while request: $@";
            return;
        }
        
        if(defined($obj->{heos})) {
        
            HEOSMaster_ResponseProcessing($hash,$json);
            Log3 $name, 4, "HEOSMaster ($name) - starte HEOSMaster_ResponseProcessing";
        
        } elsif(defined($obj->{error})) {
        
            Log3 $name, 3, "HEOSMaster ($name) - Received error message: " . $json;
        }
        
        ($json,$tail) = HEOSMaster_ParseMsg($hash, $tail);
    }
    
    $hash->{PARTIAL} = $tail;
    Log3 $name, 5, "HEOSMaster ($name) - Tail: " . $tail;
    Log3 $name, 5, "HEOSMaster ($name) - PARTIAL: " . $hash->{PARTIAL};
    return;
}

sub HEOSMaster_ResponseProcessing($$) {
    
    my ($hash,$json)    = @_;
    my $name            = $hash->{NAME};
    my $decode_json;
    my %message;

    
    Log3 $name, 5, "HEOSMaster ($name) - JSON String: $json";
    return Log3 $name, 3, "HEOSMaster ($name) - empty answer received"
    unless( defined($json));

    Log3 $name, 4, "HEOSMaster ($name) - JSON detected!";
    $decode_json = eval{decode_json(encode_utf8($json))};
    if($@){
        Log3 $name, 3, "HEOSMaster ($name) - JSON error while request: $@";
        return;
    }

    return Log3 $name, 3, "HEOSMaster ($name) - decode_json has no Hash"
    unless(ref($decode_json) eq "HASH");

    return Log3 $name, 4, "HEOSMaster ($name) - heos worked"
    if( defined($decode_json->{heos}{message}) && $decode_json->{heos}{message} =~ /command\sunder\sprocess/ );

    if( defined($decode_json->{heos}{result}) or $decode_json->{heos}{command} =~ /^system/ ) {
    
        HEOSMaster_WriteReadings($hash,$decode_json);
        Log3 $name, 4, "HEOSMaster ($name) - call Sub HEOSMaster_WriteReadings";
    }

    if( defined($decode_json->{heos}{message}) ) {

        %message = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});

        return Log3 $name, 4, "HEOSMaster ($name) - general error ID $message{eid} - $message{text}"
        if( defined($message{eid}) );
    }

    #Player neu einlesen
    if( $decode_json->{heos}{command} =~ /^event\/players_changed/ ) {

        HEOSMaster_Write($hash,'getPlayers',undef,undef);
        return Log3 $name, 4, "HEOSMaster ($name) - player changed";
    }

    #Gruppen neu einlesen
    if( $decode_json->{heos}{command} =~ /^event\/groups_changed/ ) {


        HEOSMaster_Write($hash,'getGroups',undef,undef);
        #Player neu einlesen da Stereopaare sonst nicht erkannt werden
        InternalTimer( gettimeofday()+3, 'HEOSMaster_GetPlayers', $hash, 0 );
        return Log3 $name, 4, "HEOSMaster ($name) - groups changed";
    }

    #Quellen neu einlesen
    if( $decode_json->{heos}{command} =~ /^event\/sources_changed/ ) {        
    
        HEOSMaster_Write($hash,'getMusicSources',undef,undef);
        return Log3 $name, 4, "HEOSMaster ($name) - source changed";
    }

    #User neu einlesen
    if( $decode_json->{heos}{command} =~ /^event\/user_changed/ ) {        
    
        HEOSMaster_Write($hash,'checkAccount',undef,undef);
        return Log3 $name, 4, "HEOSMaster ($name) - user changed";
    }

    #Queue für Player neu einlesen
    if ( $decode_json->{heos}{command} =~ /^event\/player_queue_changed/ ) {

        HEOSMaster_Write($hash,'getQueue',"pid=$message{pid}",undef);
        return Log3 $name, 3, "HEOSMaster ($name) - queue changed";
            
    }

    #Playlisten neu einlesen da Queue als Playlist gespeichert wurde
    if( $decode_json->{heos}{command} =~ /^player\/save_queue/ ) {
    
        HEOSMaster_Write($hash,'browseSource','sid=1025',undef);
        return Log3 $name, 4, "HEOSMaster ($name) - playlist changed";        
    }

    if( $decode_json->{heos}{command} =~ /^browse\/get_music_sources/ and ref($decode_json->{payload}) eq "ARRAY" and scalar(@{$decode_json->{payload}}) > 0) {

        #liest nur die Onlinequellen der Rest wird extra eingelesen
        $hash->{helper}{sources} = [];
        my $i = 4;

        foreach my $payload ( @{$decode_json->{payload}} ) {
            if( $payload->{sid} eq "1024" ) {
            
                $i += 2;
                InternalTimer( gettimeofday()+$i, 'HEOSMaster_GetServers', $hash, 0 );
                Log3 $name, 4, "HEOSMaster ($name) - GetServers in $i seconds";
                
            } elsif( $payload->{sid} eq "1025" ) {
            
                $i += 2;
                InternalTimer( gettimeofday()+$i, 'HEOSMaster_GetPlaylists', $hash, 0 );
                Log3 $name, 4, "HEOSMaster ($name) - GetPlaylists in $i seconds";
                
            } elsif( $payload->{sid} eq "1026" ) {
            
                $i += 2;
                InternalTimer( gettimeofday()+$i, 'HEOSMaster_GetHistory', $hash, 0 );
                Log3 $name, 4, "HEOSMaster ($name) - GetHistory in $i seconds";
                
            } elsif( $payload->{sid} eq "1027" ) {
            
                $i += 2;
                InternalTimer( gettimeofday()+$i, 'HEOSMaster_GetInputs', $hash, 0 );
                Log3 $name, 4, "HEOSMaster ($name) - GetInputs in $i seconds";
                
            } elsif( $payload->{sid} eq "1028" ) {
            
                $i += 2;
                InternalTimer( gettimeofday()+$i, 'HEOSMaster_GetFavorites', $hash, 0 );
                Log3 $name, 4, "HEOSMaster ($name) - GetFavorites in $i seconds";
                
            } else {
            
                #Onlinedienste
                push( @{$hash->{helper}{sources}},$payload);
                Log3 $name, 4, "HEOSMaster ($name) - GetRadioSource {$payload->{name} with sid $payload->{sid}";

                foreach my $source (@{$hash->{helper}{sources}}) {
                    HEOSMaster_Write($hash,'searchCriteria','sid='.$source->{sid},undef);
                }
            }
        }
        
        return Log3 $name, 3, "HEOSMaster ($name) - call Sourcebrowser";        
    }

    if( $decode_json->{heos}{command} =~ /^browse\/browse/ and ref($decode_json->{payload}) eq "ARRAY" and scalar(@{$decode_json->{payload}}) > 0) {
        if ( defined $message{sid} ) {
            if ( defined $message{range} ) { 

                $message{range} =~ s/(\d+)\,\d+/$1/;
                
            } else {
            
                $message{range} = 0;
            }
            
            my $start = $message{range} + $message{returned};

            if( $message{sid} eq '1024' ) {

                #Lokal einlesen
                push( @{$hash->{helper}{sources}}, map { $_->{name} .= " USB" if ( $_->{sid} < 0 ); $_ }  (@{$decode_json->{payload}}) );

                foreach my $source (@{$hash->{helper}{sources}}) {

                    HEOSMaster_Write($hash,'searchCriteria','sid='.$source->{sid},undef);
                    Log3 $name, 3, "HEOSMaster ($name) - call Browser for searchCriteria for sid $source->{sid}";
                }

            } elsif( $message{sid} eq '1025' ) {

                #Playlisten einlesen
                $hash->{helper}{playlists} = [] if ( $message{range} == 0 );
                push( @{$hash->{helper}{playlists}}, (@{$decode_json->{payload}}) );

            } elsif( $message{sid} eq '1026' ) {

                #History einlesen
                $hash->{helper}{history} = [] if ( $message{range} == 0 );
                push( @{$hash->{helper}{history}}, (@{$decode_json->{payload}}) );

            } elsif( $message{sid} eq '1027' ) {

                #Inputs einlesen
                $hash->{helper}{aux} = [] if ( $message{range} == 0 );
                push( @{$hash->{helper}{aux}}, (@{$decode_json->{payload}}) );

                foreach my $item (@{$decode_json->{payload}}) {


                    HEOSMaster_Write($hash,'browseSource',"sid=$item->{sid}",undef);
                    Log3 $name, 3, "HEOSMaster ($name) - call Browser for Input with sid $item->{sid}";
                }

            } elsif( $message{sid} eq '1028' ) {
            
                #Favoriten einlesen
                $hash->{helper}{favorites} = [] if ( $message{range} == 0 );
                push( @{$hash->{helper}{favorites}}, (@{$decode_json->{payload}}) );
                
                if ( $start >=  $message{count} ) {
                
                    #Nachricht an die Player das sich die Favoriten geändert haben
                    foreach my $dev ( devspec2array("TYPE=HEOSPlayer") ) {                        
                    
                        $json  = '{"heos": {"command": "event/favorites_changed", "message": "pid='.$defs{$dev}->{PID}.'"}}';
                        Dispatch($hash,$json,undef);
                        Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for Favorites Changed";
                    }
                }
                
            } else {

                #AUX Eingang des Player im Player abspeichern
                if ( defined $hash->{helper}{aux} && grep( $_->{sid} =~ /^$message{sid}$/, (@{ $hash->{helper}{aux} }) ) ) {

                    my $code = abs($message{sid});
                    $code    = $hash->{NAME} ."-". $code if( defined($hash->{NAME}) );
        
                    if( my $phash    = $modules{HEOSPlayer}{defptr}{$code} ) {
                    
                        $phash->{helper}{aux} = $decode_json->{payload};
                    }

                    $json  = '{"heos": {"command": "event/player_aux_changed", "message": "pid='.$message{sid}.'"}}';
                    Dispatch($hash,$json,undef);
                    Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for AUX Changed";
                    
                }
                
                #aktuelle Medien einlesen
                $hash->{helper}{media} = [] if ( $message{range} == 0 );
                push( @{$hash->{helper}{media}}, (@{$decode_json->{payload}}) );
            }
            
            Log3 $name, 4, "HEOSMaster ($name) - call Browser with sid $message{sid} and $message{returned} items from $message{count} items";
            
            if ( $start <  $message{count} ) {
            
                my $path = "sid=$message{sid}";
                $path .= "&cid=$message{cid}" if ( defined $message{cid} ); 
                $path .= "&SEQUENCE=$message{SEQUENCE}" if ( defined $message{SEQUENCE} ); 
                HEOSMaster_Write($hash,'browseSource',"$path&range=$start,".($start + 100),undef);
                Log3 $name, 3, "HEOSMaster ($name) - call Browser with sid $message{sid} next Range from $message{returned}";

            } else {
                if ( defined $message{SEQUENCE} ) {
                
                    my $idx = $message{SEQUENCE};
                    if( defined $hash->{helper}{blocking}{$idx} && $hash->{helper}{blocking}{$idx}{cl}{canAsyncOutput} ) {
                    
                        my @list;
                        my $xcmd;
                        my $xtext;
                        my $ret;

                        if( $hash->{helper}{blocking}{$idx}{cl}->{TYPE} eq 'FHEMWEB' ) {

                            $ret = '<div class="container">';
                            $ret .= '<h2 style="text-align: center;">'.$hash->{helper}{blocking}{$idx}{sourcename}.'</h2><hr>';

                        } else {
                    
                            $ret .= $hash->{helper}{blocking}{$idx}{sourcename}."\n";
                            $ret .= sprintf( "%-15s %s\n", 'key', 'title' );
                        }

                        if ( $message{sid} eq "1025" ) {
                        
                            @list     = (@{$hash->{helper}{playlists}});
                            
                        } elsif ( $message{sid} eq "1026" ) {
                        
                            @list     = (@{$hash->{helper}{history}});
                            
                        } elsif ( $message{sid} eq "1027" ) {
                        
                            @list     = (@{$hash->{helper}{aux}});
                            
                        } elsif ( $message{sid} eq "1028" ) {
                        
                            @list     = (@{$hash->{helper}{favorites}});
                            
                        } else {
                        
                            @list = (@{$hash->{helper}{media}});
                            
                        }

                        my $x = 0;
                        foreach my $item (@list) {
                            $ret .= HEOSMaster_MakePlayLink($hash->{helper}{blocking}{$idx}{cl}->{TYPE}, $hash->{helper}{blocking}{$idx}{name}, \%message, $item, ++$x, 64, 64);
                        }


                        if( $hash->{helper}{blocking}{$idx}{cl}->{TYPE} eq 'FHEMWEB' ) {

                            $ret .= '</div></div>';
                            $ret =~ s/&/&amp;/g;
                            $ret =~ s/'/&apos;/g;
                            $ret =~ s/\n/<br>/g;
                            $ret = "<pre>$ret</pre>" if( $ret =~ m/  / );
                            $ret = "<html>$ret</html>";
                        }

                        asyncOutput( $hash->{helper}{blocking}{$idx}{cl}, $ret );
                        delete $hash->{helper}{blocking}{$idx};
                    }
                }
            }
            
            return;
        }
    }

    if( $decode_json->{heos}{command} =~ /^browse\/get_search_criteria/ && ref($decode_json->{payload}) eq "ARRAY" && scalar(@{$decode_json->{payload}}) > 0) {
    
        push( @{$hash->{helper}{search}{$message{sid}}}, (@{$decode_json->{payload}}) );
        Log3 $name, 3, "HEOSMaster ($name) - call Browser with sid $message{sid}";
    }

    if( $decode_json->{heos}{command} =~ /^browse\/search/ ) { 

        Log3 $name, 3, "HEOSMaster ($name) - call search for $message{sid}";
                
        if ( defined $message{range} ) { 
                
            $message{range} =~ s/(\d+)\,\d+/$1/;
                    
        } else {
                
            $message{range} = 0; 
            $hash->{helper}{searchresult} = [];
        }
                
        my $start = $message{range} + $message{returned};
        push( @{$hash->{helper}{searchresult}}, (@{$decode_json->{payload}}) );              
                
        if ( $start <  $message{count} ) {
                
            HEOSMaster_Write($hash,"search","sid=$message{sid}&search=$message{search}&scid=$message{scid}",undef);
            Log3 $name, 3, "HEOSMaster ($name) - call Search for $message{sid} next Range from $message{returned}";
            
        } else {

            if( $hash->{helper}{blocking} && $hash->{helper}{blocking}{cl}{canAsyncOutput} ) {
            
                my $ret = '';
                
                $ret .= sprintf( "%-35s %-10s %s\n", 'Fav', 'type', 'title' );
                
                $ret .= "\n\n";
                
                asyncOutput( $hash->{helper}{blocking}{cl}, $ret );
                delete $hash->{helper}{blocking};
            }
        }

        Log3 $name, 4, "HEOSMaster ($name) - call Browser for Search";
    }

    if( $decode_json->{heos}{command} =~ /^player/ or $decode_json->{heos}{command} =~ /^event\/player/ or $decode_json->{heos}{command} =~ /^group/ or $decode_json->{heos}{command} =~ /^event\/group/ or $decode_json->{heos}{command} =~ /^event\/repeat_mode_changed/ or $decode_json->{heos}{command} =~ /^event\/shuffle_mode_changed/ ) {

        if( $decode_json->{heos}{command} =~ /player\/get_players/ ) {
        
            return Log3 $name, 4, "HEOSMaster ($name) - empty ARRAY received"
            unless(scalar(@{$decode_json->{payload}}) > 0);

            my $filter = "TYPE=HEOSPlayer:FILTER=PID!=";

            foreach my $payload (@{$decode_json->{payload}}) {
            
                $json  =    '{"pid": "';
                $json .=    "$payload->{pid}";
                $json .=    '","heos": {"command": "player/get_player_info"}}';
                Dispatch($hash,$json,undef);
                Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for Players";
                $filter .= $payload->{pid}."|";
            }

            chop($filter); #letztes | wieder abschneiden

            #alle Player ausschalten die nicht mehr im HEOS System existieren
            foreach my $dev ( devspec2array($filter) ) {
            
                my $phash = $defs{$dev};
                readingsSingleUpdate( $phash, "state", "off", 1 );
            }
            
        } elsif( $decode_json->{heos}{command} =~ /group\/get_groups/ ) {
        
            my $filter = "TYPE=HEOSGroup";

            if ( scalar(@{$decode_json->{payload}}) > 0 ) {
            
                $filter .= ":FILTER=GID!=";
                
                foreach my $payload (@{$decode_json->{payload}}) {
                
                    $json  =    '{"gid": "';
                    $json .=    "$payload->{gid}";
                    $json .=    '","heos": {"command": "group/get_group_info"}}';
                    Dispatch($hash,$json,undef);
                    Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for Groups";
                    $filter .= $payload->{gid}."|";
                }
                
                chop($filter); #letztes | wieder abschneiden
            }
            
            #alle Gruppe ausschalten die nicht mehr im HEOS System existieren
            foreach my $dev ( devspec2array($filter) ) {
            
                my $ghash = $defs{$dev};
                readingsSingleUpdate( $ghash, "state", "off", 1 );
            }                               

        } elsif( $decode_json->{heos}{command} =~ /player\/get_player_info/ ) { # ist vielleicht verständlicher?
        
            Dispatch($hash,$json,undef);
            Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for PlayerInfo";

        } elsif( $decode_json->{heos}{command} =~ /group\/get_group_info/ ) { # ist vielleicht verständlicher?
        
            Dispatch($hash,$json,undef);
            Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for GroupInfo";

        } elsif( $decode_json->{heos}{command} =~ /player\/get_queue/ ) {

            Log3 $name, 3, "HEOSMaster ($name) - call getQueue for player $message{pid}";
                
            if ( defined $message{range} ) { 
                
                $message{range} =~ s/(\d+)\,\d+/$1/;
                    
            } else {
                
                $message{range} = 0; 
                $hash->{helper}{queue}{$message{pid}} = [];
            }
                
            my $start = $message{range} + $message{returned};
            push( @{$hash->{helper}{queue}{$message{pid}}}, (@{$decode_json->{payload}}) );              
                
            if ( $start <  $message{count} ) {
                
                HEOSMaster_Write($hash,'getQueue',"pid=$message{pid}&range=$start,".($start + 100),undef);
                Log3 $name, 4, "HEOSMaster ($name) - call getQueue for player pid $message{pid} next Range from $start";

            } else {

                my $code = abs($message{pid});
                $code    = $hash->{NAME} ."-". $code if( defined($hash->{NAME}) );
        
                if( my $phash    = $modules{HEOSPlayer}{defptr}{$code} ) {
                
                    $phash->{helper}{queue} = $hash->{helper}{queue}{$message{pid}};
                    delete $hash->{helper}{queue}{$message{pid}};
                }

                $json  = '{"heos": {"command": "event/player_queue_changed", "message": "pid='.$message{pid}.'"}}';
                Dispatch($hash,$json,undef);
                Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher for Queue Changed";
            }

        } elsif( defined($message{pid}) or defined($message{gid}) ) {
        
            Dispatch($hash,$json,undef);
            Log3 $name, 4, "HEOSMaster ($name) - call Dispatcher";
        }
        
        return;
    }
    
    Log3 $name, 4, "HEOSMaster ($name) - no Match for processing data";
}

sub HEOSMaster_WriteReadings($$) {
    
    my ($hash,$decode_json) = @_;
    my $name                = $hash->{NAME};
    
    
    ############################
    #### Aufbereiten der Daten soweit nötig
    my $readingsHash    = HEOSMaster_PreProcessingReadings($hash,$decode_json)
    if( $decode_json->{heos}{command} eq 'system/register_for_change_events'
        or $decode_json->{heos}{command} eq 'system/check_account'
        or $decode_json->{heos}{command} eq 'system/sign_in'
        or $decode_json->{heos}{command} eq 'system/sign_out' );

    ############################
    #### schreiben der Readings

    readingsBeginUpdate($hash);

    ### Event Readings
    if( ref($readingsHash) eq "HASH" ) {
    
        Log3 $name, 4, "HEOSMaster ($name) - response json Hash back from HEOSMaster_PreProcessingReadings";
        my $t;
        my $v;
    
        while( ( $t, $v ) = each (%{$readingsHash}) ) {
        
            readingsBulkUpdate( $hash, $t, $v ) if( defined($v) );               
        }
    }
    
    readingsBulkUpdate( $hash, "lastCommand", $decode_json->{heos}{command} );
    readingsBulkUpdate( $hash, "lastResult", $decode_json->{heos}{result} );

    if( ref($decode_json->{payload}) ne "ARRAY" ) {
    
        readingsBulkUpdate( $hash, "lastPlayerId", $decode_json->{payload}{pid} );
        readingsBulkUpdate( $hash, "lastPlayerName", $decode_json->{payload}{name} );
    }
    
    readingsEndUpdate( $hash, 1 );
    return undef;
}

###################
### my little Helpers

sub HEOSMaster_ParseMsg($$) {
    
    my ($hash, $buffer) = @_;
    my $name = $hash->{NAME};
    my $open = 0;
    my $close = 0;
    my $msg = '';
    my $tail = '';

    
    if($buffer) {
        foreach my $c (split //, $buffer) {
            if($open == $close && $open > 0) {
                $tail .= $c;
                
            } elsif(($open == $close) && ($c ne '{')) {
            
                Log3 $name, 5, "HEOSMaster ($name) - Garbage character before message: " . $c;
                
            } else {
            
                if($c eq '{') {
                
                    $open++;
                    
                } elsif($c eq '}') {
                
                    $close++;
                }
                
                $msg .= $c;
            }
        }
        
        if($open != $close) {
        
            $tail = $msg;
            $msg = '';
        }
    }

    return ($msg,$tail);
}

sub HEOSMaster_PreProcessingReadings($$) {
    
    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    my $reading;
    my %buffer;
    my %message  = map { my ( $key, $value ) = split "="; $key => $value } split('&', $decode_json->{heos}{message});


    Log3 $name, 4, "HEOSMaster ($name) - preprocessing readings";

    if ( $decode_json->{heos}{command} eq 'system/register_for_change_events' ) {        
    
        $buffer{'enableChangeEvents'}   = $message{enable};
        
    } elsif ( $decode_json->{heos}{command} eq 'system/check_account' or $decode_json->{heos}{command} eq 'system/sign_in' ) {
        if ( exists $message{signed_out} || exists $message{eid}  ) {
        
            $buffer{'heosAccount'}  = "signed_out";
            
        } else {
        
            $buffer{'heosAccount'}  = "signed_in as $message{un}";
            HEOSMaster_GetFavorites($hash) if( ReadingsVal($name,"enableChangeEvents", "off") eq "on" );
        }
        
    } else {
    
        Log3 $name, 3, "HEOSMaster ($name) - no match found";
        return undef;
    }
    
    Log3 $name, 4, "HEOSMaster ($name) - Match found for decode_json";
    return \%buffer;
}

sub HEOSMaster_FirstRun($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash,'HEOSMaster_FirstRun');
    HEOSMaster_Open($hash) if( !IsDisabled($name) );
}

sub HEOSMaster_GetPlayers($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash,'HEOSMaster_GetPlayers');
    HEOSMaster_Write($hash,'getPlayers',undef,undef);
    Log3 $name, 4, "HEOSMaster ($name) - getPlayers";
}

sub HEOSMaster_GetGroups($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash,'HEOSMaster_GetGroups');
    HEOSMaster_Write($hash,'getGroups',undef,undef);
    Log3 $name, 4, "HEOSMaster ($name) - getGroups";
}

sub HEOSMaster_EnableChangeEvents($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash,'HEOSMaster_EnableChangeEvents');
    HEOSMaster_Write($hash,'enableChangeEvents','on',undef);
    Log3 $name, 4, "HEOSMaster ($name) - set enableChangeEvents on";
}

sub HEOSMaster_GetMusicSources($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_GetMusicSources');
    HEOSMaster_Write($hash,'getMusicSources',undef,undef);
    Log3 $name, 4, "HEOSMaster ($name) - getMusicSources";
}

sub HEOSMaster_GetFavorites($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_GetFavorites');
    HEOSMaster_Write($hash,'browseSource','sid=1028',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getFavorites";
}

sub HEOSMaster_GetInputs($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_GetInputs');
    HEOSMaster_Write($hash,'browseSource','sid=1027',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getInputs";
}

sub HEOSMaster_GetServers($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_GetServers');
    HEOSMaster_Write($hash,'browseSource','sid=1024',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getServers";
}

sub HEOSMaster_GetPlaylists($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_GetPlaylists');
    HEOSMaster_Write($hash,'browseSource','sid=1025',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getPlaylists";
}

sub HEOSMaster_GetHistory($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_GetHistory');
    HEOSMaster_Write($hash,'browseSource','sid=1026',undef);
    Log3 $name, 4, "HEOSMaster ($name) - getHistory";
}

sub HEOSMaster_CheckAccount($) {
    
    my $hash    = shift;
    my $name    = $hash->{NAME};

    
    RemoveInternalTimer($hash, 'HEOSMaster_CheckAccount');
    HEOSMaster_Write($hash,'checkAccount',undef,undef);
    Log3 $name, 4, "HEOSMaster ($name) - checkAccount";
}

sub HEOSMaster_StorePassword($$) {
    
    my ($hash, $password) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    my $enc_pwd = "";

    
    if(eval "use Digest::MD5;1") {
    
        $key = Digest::MD5::md5_hex(unpack "H*", $key);
        $key .= Digest::MD5::md5_hex($key);
    }
    
    for my $char (split //, $password) {
    
        my $encode=chop($key);
        $enc_pwd.=sprintf("%.2x",ord($char)^ord($encode));
        $key=$encode.$key;
    }
    
    my $err = setKeyValue($index, $enc_pwd);
    return "error while saving the password - $err" if(defined($err));

    return "password successfully saved";
}

sub HEOSMaster_ReadPassword($) {
    
    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_passwd";
    my $key = getUniqueId().$index;
    my ($password, $err);

    
    Log3 $name, 4, "HEOSMaster ($name) - Read password from file";
    
    ($err, $password) = getKeyValue($index);

    if ( defined($err) ) {
    
        Log3 $name, 4, "HEOSMaster ($name) - unable to read password from file: $err";
        return undef;
        
    }
    
    if ( defined($password) ) {
        if ( eval "use Digest::MD5;1" ) {
        
            $key = Digest::MD5::md5_hex(unpack "H*", $key);
            $key .= Digest::MD5::md5_hex($key);
        }
        
        my $dec_pwd = '';
        
        for my $char (map { pack('C', hex($_)) } ($password =~ /(..)/g)) {
        
            my $decode=chop($key);
            $dec_pwd.=chr(ord($char)^ord($decode));
            $key=$decode.$key;
        }
        
        return $dec_pwd;
        
    } else {
    
        Log3 $name, 4, "HEOSMaster ($name) - No password in file";
        return undef;
    }
}

sub HEOSMaster_MakePlayLink3($$$$) {

    my ($name, $message, $item, $idx) = @_;
    my $xcmd;
    my $xtext = $message->{sid};


    if ( (exists $item->{playable} && $item->{playable} eq "yes") || exists $item->{qid} ) {
    
        $xcmd = 'cmd'.uri_escape('=set '.$name.' input '.$message->{sid});
        
    } else {
    
        $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$message->{sid});
    }
    
    if ( defined $item->{sid} ) {
    
        $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$message->{sid});
        $xcmd .= uri_escape(",".$item->{sid});
        $xtext .= ','.$item->{sid};
        
    } elsif ( defined $item->{cid} ) {
        if ( $item->{type} eq "album" ) {
        
            $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$message->{sid});
        }
        
        $xcmd .= uri_escape(",".$item->{cid});
        $xtext .= ','.$item->{cid};
        
    } elsif ( defined $item->{mid} ) {
        if ( $message->{sid} eq "1028" ) {
        
            $xcmd .= ','.$idx; 
            $xtext .= ','.$idx;
            
        } elsif ( defined $message->{cid} ) {
        
            $xcmd .= uri_escape(','.$message->{cid}.','.$item->{mid}); 
            $xtext .= ','.$message->{cid}.','.$item->{mid};
            
        } else {
        
            $xcmd = 'cmd'.uri_escape('=set '.$name.' input 1027');
            $xcmd .= uri_escape(','.$message->{sid}.','.$item->{mid}); 
            $xtext = '1027,'.$message->{sid}.','.$item->{mid};
        }
    } elsif ( defined $item->{qid} ) {
    
        $xcmd .= ','.$item->{qid}; 
        $xtext .= ','.$item->{qid};
    }
    
    $xcmd = "FW_cmd('$FW_ME$FW_subdir?XHR=1&$xcmd')";
    return '<li style="list-style-type: none; display: inline;"><a style="cursor:pointer" onclick="'.$xcmd.'">'.sprintf( "%-35s %-15s %s", $xtext, $item->{type}, $item->{name} )."</a></li>\n";
}

sub HEOSMaster_MakePlayLink($$$$$$$) {

    my ($type, $name, $message, $item, $idx, $xsize, $ysize) = @_;
    my $xcmd;
    my $xtext = $message->{sid};

    $ysize = '10.75em' if (!defined($ysize));

    if ( (exists $item->{playable} && $item->{playable} eq "yes") || exists $item->{qid} ) {

        $xcmd = 'cmd'.uri_escape('=set '.$name.' input '.$message->{sid});
        $xtext = '*'.$xtext;

    } else {

        $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$message->{sid});
    }

    if ( defined $item->{sid} ) {

        $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$message->{sid});
        $xcmd .= uri_escape(",".$item->{sid});
        $xtext .= ','.$item->{sid};

    } elsif ( defined $item->{cid} ) {
        if ( $item->{type} eq "album" ) {

            $xcmd = 'cmd'.uri_escape('=get '.$name.' ls '.$message->{sid});
        }

        $xcmd .= uri_escape(",".$item->{cid});
        $xtext .= ','.$item->{cid};

    } elsif ( defined $item->{mid} ) {
        if ( $message->{sid} eq "1028" ) {

            $xcmd .= ','.$idx;
            $xtext .= ','.$idx;

        } elsif ( defined $message->{cid} ) {

            $xcmd .= uri_escape(','.$message->{cid}.','.$item->{mid});
            $xtext .= ','.$message->{cid}.','.$item->{mid};

        } else {

            $xcmd = 'cmd'.uri_escape('=set '.$name.' input 1027');
            $xcmd .= uri_escape(','.$message->{sid}.','.$item->{mid});
            $xtext = '1027,'.$message->{sid}.','.$item->{mid};
        }
    } elsif ( defined $item->{qid} ) {

        $xcmd .= ','.$item->{qid};
        $xtext .= ','.$item->{qid};
    }

    if( $type eq 'FHEMWEB' ) {
    
        $xcmd = "FW_cmd('$FW_ME$FW_subdir?XHR=1&$xcmd')";

        if ( defined $item->{image_url} && $item->{image_url} ne "" ) {
            return '<a href="#" onClick="'.$xcmd.'" class="list-group-item" style="display: flex;align-items: center;cursor:pointer;"><img style="width: '.$xsize.'px; height: '.$ysize.'px;" src="'.$item->{image_url}.'"><h5 class="list-group-item-heading" style="padding: 10px;">'.$item->{name}.'</h5></a>';

            #return '<div style="clear: left;display: flex;align-items: center;float: left;cursor:pointer;" onclick="'.$xcmd.'"><img style="width: '.$xsize.'px;  height: '.$ysize.'px;" src="'.$item->{image_url}.'"/>'.$item->{name}."</div>\n\n";
        } else {
            return '<a href="#" onClick="'.$xcmd.'" class="list-group-item"><h4 class="list-group-item-heading">'.$item->{name}.'</h4></a>';
            #return '<div style="clear: left;display: flex;align-items: center;float: left;cursor:pointer;" onclick="'.$xcmd.'"><a style="cursor:pointer" onclick="'.$xcmd.'">'.sprintf( "%-35s %-15s %s", $xtext, $item->{type}, $item->{name} )."</a></div>\n\n";
        }

    } else {

        return sprintf( "%-15s %s\n", $xtext, $item->{name} );

    }
}

sub HEOSMaster_MakeImage($$) {

    my ($url, $size) = @_;
    my $ret .= "<img src=\"$url\" &width=$size&height=$size\">\n";

    return $ret;
}








1;




=pod
=item device
=item summary       Modul to controls the Denon multiroom soundsystem
=item summary_DE    Modul zum steuern des Denon Multiroom-Soundsystem

=begin html

<a name="HEOSMaster"></a>
<h3>HEOSMaster</h3>
<ul>
  <u><b>HEOSMaster</b></u>
  <br><br>
  In combination with HEOSPlayer and HEOSGroup this FHEM Module controls the Denon multiroom soundsystem using a telnet socket connection and the HEOS Command Line Interface (CLI).
  <br><br>
  <b>Prerequisite</b>
  <ul>
    <li>Installation of the following packages: apt-get install libjson-perl libnet-telnet-perl libencode-perl
</li>
  </ul>
    <br>
  <a name="HEOSMasterdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; HEOSMaster &lt;IP address&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define MyMasterBox HEOSMaster 192.168.178.67</code><br>
    </ul>
    <br>
    &ltIP address&gt is the IP address of Your HEOS receiver or HEOS box. The master device is created in the room HEOS, then the players of Your system are recognized automatically and created in FHEM. From now on the players can be controlled and changes in the HEOS app or at the Receiver are synchronized with the state and media readings of the players.
  <a name="HEOSMasterreadings"></a>
 <br><br>
  <b>Readings</b>
  <ul>
    <li>enableChangeEvents - state of the event reproduction at CLI master (on|off)</li>
    <li>heosAccount - signed_out | signed_in as &ltHEOSAccount&gt</li>
    <li>lastCommand - last executed command</li>
    <li>lastPlayerId - player id of the device, which executed the last command</li>
    <li>lastPlayerName - player name of the device, which executed the last command</li>
    <li>lastResult - result of the last executed command</li>
    <li>state - state of the HEOSMaster</li>
  </ul>
  <br><br>
  <a name="HEOSMasterset"></a>
  <b>set</b>
  <ul>
    <li>checkAccount - checks Your HEOS account</li>
    <li>enableChangeEvents - activates the event reproduction at the CLI master</li>
    <li>getGroups - get a list of all groups and creates the devices, if not done already</li>
    <li>getPlayers - get a list of all players and creates the devices, if not yet existing</li>
    <li>password - set the password of Your HEOS account</li>
    <li>reboot - reboot of the CLI interface at HEOSMaster</li>
    <li>reopen - tries to establish a new socket connection with CLI master</li>
    <li>signAccount In|Out - sign in|out Your HEOS account (attr MyMasterBox heosUsername &ltusername&gt)</li>
  </ul>
  <br><br>
  <a name="HEOSMasterget"></a>
  <b>get</b>
  <ul>
    <li>ShowAccount - shows Your HEOS account</li>
  </ul>
  <br><br>
  <a name="HEOSMasterstate"></a>
  <b>state</b>
  <ul>
    <li>connected - the HEOSmaster is connected to the CLI Master</li>
    <li>not connected - the HEOSmaster is not connected to the CLI Master</li>
  </ul>
 <br><br>
  <a name="HEOSMasterattributes"></a>
  <b>attributes</b>
  <ul>
    <li>heosUsername - username of Your HEOS account</li>
  </ul>
    <br><br>
  </ul>
</ul>
  
=end html

=begin html_DE

<a name="HEOSMaster"></a>
<h3>HEOSMaster</h3>
<ul>
  <u><b>HEOSMaster</b></u>
  <br><br>
  In Kombination mit HEOSPlayer und HEOSGroup steuert dieses FHEM Modul das Denon Multiroom-Soundsystem mit Hilfe einer telnet Socket-Verbindung und dem HEOS Command Line Interface (CLI).
  <br><br>
  <b>Voraussetzung</b>
  <ul>
    <li>Installation der folgenden Pakete: apt-get install libjson-perl libnet-telnet-perl libencode-perl
</li>
  </ul>
    <br>
  <a name="HEOSMasterdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; HEOSMaster &lt;IP address&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define MyMasterBox HEOSMaster 192.168.178.67</code><br>
    </ul>
    <br>
    &ltIP address&GT ist die IP-Adresse des HEOS Receivers oder der HEOS Box. Das Master Device wird im Raum HEOS angelegt und danach erfolgt das Einlesen und automatische Anlegen der Player.
Von nun an k&oumlnnen die Player gesteuert werden. Au&szligerdem wird der Status und die Media Readings der Player entsprechend ge&aumlndert, wenn man in der HEOS-App oder direkt am Receiver etwas &aumlndert.

  <a name="HEOSMasterreadings"></a>
 <br><br>
  <b>Readings</b>
  <ul>
    <li>enableChangeEvents - Status der Event Wiedergabe auf dem CLI Master</li>
    <li>heosAccount - signed_out | signed_in as &ltHEOSAccount&gt</li>
    <li>lastCommand - zuletzt ausgef&uumlhrtes Kommando</li>
    <li>lastPlayerId - Player-Id des Ger&aumlts, welches das Kommando ausgef&uumlhrt hat</li>
    <li>lastPlayerName - Player-Name des Ger&aumlts, welches das Kommando ausgef&uumlhrt hat</li>
    <li>lastResult - Ergebnis des zuletzt ausgef&uumlhrten Kommandos</li>
    <li>state - Status des HEOSMaster</li>
  </ul>
  <br><br>
  <a name="HEOSMasterset"></a>
  <b>set</b>
  <ul>
    <li>checkAccount - pr&uumlft das HEOS Konto</li>
    <li>enableChangeEvents - aktiviert die Event Wiedergabe auf dem CLI Master</li>
    <li>getGroups - holt eine Liste aller Gruppen und legt die Devices an, sofern noch nicht geschehen</li>
    <li>getPlayers - holt eine Liste aller Player und legt die Devices an, sofern noch nicht vorhanden</li>
    <li>password - setzt das Passwort des HEOS Kontos</li>
    <li>reboot - rebootet das CLI Interface am Master</li>
    <li>reopen - versucht eine neue Socket-Verbindung zum CLI Master aufzubauen</li>
    <li>signAccount In|Out - anmelden|abmelden am HEOS Konto (attr MyMasterBox heosUsername &ltusername&gt)</li>
  </ul>
  <br><br>
  <a name="HEOSMasterget"></a>
  <b>get</b>
  <ul>
    <li>ShowAccount - zeigt das HEOS Konto an</li>
  </ul>
  <br><br>
  <a name="HEOSMasterstate"></a>
  <b>state</b>
  <ul>
    <li>connected - der HEOSmaster ist mit dem CLI Master verbunden</li>
    <li>not connected - der HEOSmaster ist nicht mit dem CLI Master verbunden</li>
  </ul>
 <br><br>
  <a name="HEOSMasterattributes"></a>
  <b>Attributes</b>
  <ul>
    <li>heosUsername - Benutzername des HEOS Kontos</li>
  </ul>
    <br><br>
  </ul>
</ul>

=end html_DE

=cut

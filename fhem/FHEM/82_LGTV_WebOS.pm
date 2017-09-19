###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Vitolinker / Commandref
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

use MIME::Base64;
use IO::Socket::INET;
use Digest::SHA qw(sha1_hex);
use JSON qw(decode_json encode_json);
use Encode qw(encode_utf8 decode_utf8);
use Blocking;





my $version = "1.0.0";





# Declare functions
sub LGTV_WebOS_Initialize($);
sub LGTV_WebOS_Define($$);
sub LGTV_WebOS_Undef($$);
sub LGTV_WebOS_Set($@);
sub LGTV_WebOS_Open($);
sub LGTV_WebOS_Close($);
sub LGTV_WebOS_Read($);
sub LGTV_WebOS_Write($@);
sub LGTV_WebOS_Attr(@);
sub LGTV_WebOS_Handshake($);
sub LGTV_WebOS_ResponseProcessing($$);
sub LGTV_WebOS_Header2Hash($);
sub LGTV_WebOS_Pairing($);
sub LGTV_WebOS_CreateSendCommand($$$;$);
sub LGTV_WebOS_Hybi10Encode($;$$);
sub LGTV_WebOS_WriteReadings($$);
sub LGTV_WebOS_GetCurrentChannel($);
sub LGTV_WebOS_GetForgroundAppInfo($);
sub LGTV_WebOS_GetAudioStatus($);
sub LGTV_WebOS_TimerStatusRequest($);
sub LGTV_WebOS_GetExternalInputList($);
sub LGTV_WebOS_ProcessRead($$);
sub LGTV_WebOS_ParseMsg($$);
sub LGTV_WebOS_Get3DStatus($);
sub LGTV_WebOS_GetChannelProgramInfo($);
sub LGTV_WebOS_FormartStartEndTime($);
sub LGTV_WebOS_Presence($);
sub LGTV_WebOS_PresenceRun($);
sub LGTV_WebOS_PresenceDone($);
sub LGTV_WebOS_PresenceAborted($);
sub LGTV_WebOS_WakeUp_Udp($@);




my %lgCommands = (

            "getServiceList"            => ["ssap://api/getServiceList"],
            "getChannelList"            => ["ssap://tv/getChannelList"],
            "getVolume"                 => ["ssap://audio/getVolume"],
            "getAudioStatus"            => ["ssap://audio/getStatus"],
            "getCurrentChannel"         => ["ssap://tv/getCurrentChannel"],
            "getChannelProgramInfo"     => ["ssap://tv/getChannelProgramInfo"],
            "getForegroundAppInfo"      => ["ssap://com.webos.applicationManager/getForegroundAppInfo"],
            "getAppList"                => ["ssap://com.webos.applicationManager/listApps"],
            "getAppStatus"              => ["ssap://com.webos.service.appstatus/getAppStatus"],
            "getExternalInputList"      => ["ssap://tv/getExternalInputList"],
            "get3DStatus"               => ["ssap://com.webos.service.tv.display/get3DStatus"],
            "powerOff"                  => ["ssap://system/turnOff"],
            "powerOn"                   => ["ssap://system/turnOn"],
            "3DOn"                      => ["ssap://com.webos.service.tv.display/set3DOn"],
            "3DOff"                     => ["ssap://com.webos.service.tv.display/set3DOff"],
            "volumeUp"                  => ["ssap://audio/volumeUp"],
            "volumeDown"                => ["ssap://audio/volumeDown"],
            "channelDown"               => ["ssap://tv/channelDown"],
            "channelUp"                 => ["ssap://tv/channelUp"],
            "play"                      => ["ssap://media.controls/play"],
            "stop"                      => ["ssap://media.controls/stop"],
            "pause"                     => ["ssap://media.controls/pause"],
            "rewind"                    => ["ssap://media.controls/rewind"],
            "fastForward"               => ["ssap://media.controls/fastForward"],
            "closeViewer"               => ["ssap://media.viewer/close"],
            "closeApp"                  => ["ssap://system.launcher/close"],
            "openApp"                   => ["ssap://system.launcher/open"],
            "closeWebApp"               => ["ssap://webapp/closeWebApp"],
            "openChannel"               => ["ssap://tv/openChannel", "channelNumber"],
            "launchApp"                 => ["ssap://system.launcher/launch", "id"],
            "screenMsg"                 => ["ssap://system.notifications/createToast", "message"],
            "mute"                      => ["ssap://audio/setMute", "mute"],
            "volume"                    => ["ssap://audio/setVolume", "volume"],
            "switchInput"               => ["ssap://tv/switchInput", "input"],
);

my %openApps = (

            'Maxdome'                   => 'maxdome',
            'AmazonVideo'               => 'lovefilm.de',
            'YouTube'                   => 'youtube.leanback.v4',
            'Netflix'                   => 'netflix',
            'TV'                        => 'com.webos.app.livetv',
            'GooglePlay'                => 'googleplaymovieswebos',
            'Browser'                   => 'com.webos.app.browser',
            'Chili.tv'                  => 'Chilieu',
            'TVCast'                    => 'de.2kit.castbrowsing',
            'Smartshare'                => 'com.webos.app.smartshare',
            'Scheduler'                 => 'com.webos.app.scheduler',
            'Miracast'                  => 'com.webos.app.miracast',
            'TVGuide'                   => 'com.webos.app.tvguide',
            'Timemachine'               => 'com.webos.app.timemachine',
            'ARDMediathek'              => 'ard.mediathek',
            'Arte'                      => 'com.3827031.168353',
            'WetterMeteo'               => 'meteonews',
            'Notificationcenter'        => 'com.webos.app.notificationcenter',
            'Plex'                      => 'cdp-30'
);

my %openAppsPackageName = (

            'maxdome'                           => 'Maxdome',
            'lovefilm.de'                       => 'AmazonVideo',
            'youtube.leanback.v4'               => 'YouTube',
            'netflix'                           => 'Netflix',
            'com.webos.app.livetv'              => 'TV',
            'googleplaymovieswebos'             => 'GooglePlay',
            'com.webos.app.browser'             => 'Browser',
            'Chilieu'                           => 'Chili.tv',
            'de.2kit.castbrowsing'              => 'TVCast',
            'com.webos.app.smartshare'          => 'Smartshare',
            'com.webos.app.scheduler'           => 'Scheduler',
            'com.webos.app.miracast'            => 'Miracast',
            'com.webos.app.tvguide'             => 'TVGuide',
            'com.webos.app.timemachine'         => 'Timemachine',
            'ard.mediathek'                     => 'ARDMediathek',
            'com.3827031.168353'                => 'Arte',
            'meteonews'                         => 'WetterMeteo',
            'com.webos.app.notificationcenter'  => 'Notificationcenter',
            'cdp-30'                            => 'Plex'
);





sub LGTV_WebOS_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     = "LGTV_WebOS_Read";
    $hash->{WriteFn}    = "LGTV_WebOS_Write";


    # Consumer
    $hash->{SetFn}      = "LGTV_WebOS_Set";
    $hash->{DefFn}      = "LGTV_WebOS_Define";
    $hash->{UndefFn}    = "LGTV_WebOS_Undef";
    $hash->{AttrFn}     = "LGTV_WebOS_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          "channelGuide:1 ".
                          "pingPresence:1 ".
                          "wakeOnLanMAC ".
                          "wakeOnLanBroadcast ".
                          $readingFnAttributes;


    foreach my $d(sort keys %{$modules{LGTV_WebOS}{defptr}}) {
        my $hash = $modules{LGTV_WebOS}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub LGTV_WebOS_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    

    return "too few parameters: define <name> LGTV_WebOS <HOST>" if( @a != 3 );
    


    my $name                                        = $a[0];
    my $host                                        = $a[2];

    $hash->{HOST}                                   = $host;
    $hash->{VERSION}                                = $version;
    $hash->{helper}{device}{channelguide}{counter}  = 0;
    $hash->{helper}{device}{registered}             = 0;
    $hash->{helper}{device}{runsetcmd}              = 0;
    $hash->{helper}{device}{channelguide}{counter}  = 'none';


    Log3 $name, 3, "LGTV_WebOS ($name) - defined with host $host";

    $attr{$name}{devStateIcon} = 'on:10px-kreis-gruen:off off:10px-kreis-rot:on' if( !defined( $attr{$name}{devStateIcon} ) );
    $attr{$name}{room} = 'LGTV' if( !defined( $attr{$name}{room} ) );
    CommandDeleteReading(undef,$name . ' presence') if( AttrVal($name,'pingPresence', 0) == 0 );
    
    
    $modules{LGTV_WebOS}{defptr}{$hash->{HOST}} = $hash;
    
    if( $init_done ) {
        LGTV_WebOS_TimerStatusRequest($hash);
    } else {
        InternalTimer( gettimeofday()+15, "LGTV_WebOS_TimerStatusRequest", $hash, 0 );
    }
    
    return undef;
}

sub LGTV_WebOS_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    
    LGTV_WebOS_Close($hash);
    delete $modules{LGTV_WebOS}{defptr}{$hash->{HOST}};
    
    Log3 $name, 3, "LGTV_WebOS ($name) - device $name deleted";
    
    return undef;
}

sub LGTV_WebOS_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            $hash->{PARTIAL} = '';
            Log3 $name, 3, "LGTV_WebOS ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LGTV_WebOS ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "LGTV_WebOS ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LGTV_WebOS ($name) - delete disabledForIntervals";
        }
    }

    return undef;
}

sub LGTV_WebOS_TimerStatusRequest($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_TimerStatusRequest');
    
    readingsBeginUpdate($hash);
    
    if( !IsDisabled($name) and $hash->{CD} and $hash->{helper}{device}{registered} == 1 ) {
    
        Log3 $name, 4, "LGTV_WebOS ($name) - run get functions";

        
        readingsBulkUpdate($hash, 'state', 'on');
        LGTV_WebOS_Presence($hash) if( AttrVal($name,'pingPresence', 0) == 1 );
        
        if($hash->{helper}{device}{channelguide}{counter} > 2 and AttrVal($name,'channelGuide', 0) == 1 and ReadingsVal($name,'launchApp', 'TV') eq 'TV' ) {
        
            LGTV_WebOS_GetChannelProgramInfo($hash);
            $hash->{helper}{device}{channelguide}{counter}  = 0;
        
        } else {
        
            LGTV_WebOS_GetAudioStatus($hash);
            InternalTimer( gettimeofday()+2, 'LGTV_WebOS_GetCurrentChannel', $hash, 0 ) if( ReadingsVal($name,'launchApp', 'TV') eq 'TV' );
            InternalTimer( gettimeofday()+4, 'LGTV_WebOS_GetForgroundAppInfo', $hash, 0 );
            InternalTimer( gettimeofday()+6, 'LGTV_WebOS_Get3DStatus', $hash, 0 );
            InternalTimer( gettimeofday()+8, 'LGTV_WebOS_GetExternalInputList', $hash, 0 );
        }
    
    } elsif( IsDisabled($name) ) {
    
        LGTV_WebOS_Close($hash);
        $hash->{helper}{device}{runsetcmd}              = 0;
        readingsBulkUpdate($hash, 'state', 'disabled');
    
    } else {
        
        LGTV_WebOS_Presence($hash) if( AttrVal($name,'pingPresence', 0) == 1 );
        
        readingsBulkUpdate($hash, 'state', 'off');
        
        readingsBulkUpdate($hash,'channel','-');
        readingsBulkUpdate($hash,'channelName','-');
        readingsBulkUpdate($hash,'channelMedia','-');
        readingsBulkUpdate($hash,'channelCurrentTitle','-');
        readingsBulkUpdate($hash,'channelCurrentStartTime','-');
        readingsBulkUpdate($hash,'channelCurrentEndTime','-');
        readingsBulkUpdate($hash,'channelNextTitle','-');
        readingsBulkUpdate($hash,'channelNextStartTime','-');
        readingsBulkUpdate($hash,'channelNextEndTime','-');
        
        $hash->{helper}{device}{runsetcmd}              = 0;
    }
    
    readingsEndUpdate($hash, 1);
    
    LGTV_WebOS_Open($hash) if( !IsDisabled($name) and not $hash->{CD} );
    
    $hash->{helper}{device}{channelguide}{counter}  = $hash->{helper}{device}{channelguide}{counter} +1;
    InternalTimer( gettimeofday()+10,"LGTV_WebOS_TimerStatusRequest", $hash, 1 );
}

sub LGTV_WebOS_Set($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params)  = @args;

    my $uri;
    my %payload;
    my $inputs;
    my @inputs;
    
    
    if ( defined( $hash->{helper}{device}{inputs} ) and ref( $hash->{helper}{device}{inputs} ) eq "HASH" ) {
    
        @inputs = keys %{ $hash->{helper}{device}{inputs} };
    }
    
    @inputs = sort(@inputs);
    $inputs = join(",", @inputs);
    
    if($cmd eq 'connect') {
        return "usage: connect" if( @args != 0 );

        LGTV_WebOS_Open($hash);

        return undef;
        
    } elsif($cmd eq 'clearInputList') {
        return "usage: clearInputList" if( @args != 0 );

        delete $hash->{helper}{device}{inputs};
        delete $hash->{helper}{device}{inputapps};

        return undef;

    } elsif($cmd eq 'pairing') {
        return "usage: pairing" if( @args != 0 );

        LGTV_WebOS_Pairing($hash);

        return undef;
        
    } elsif($cmd eq 'screenMsg') {
        return "usage: screenMsg <message>" if( @args < 1 );

        my $msg = join(" ", @args);
        $payload{$lgCommands{$cmd}->[1]}    = decode_utf8($msg);
        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'on' or $cmd eq 'off') {
        return "usage: on/off" if( @args != 0 );

        if($cmd eq 'off') {
            $uri                                = $lgCommands{powerOff};
        } elsif ($cmd eq 'on') {
            if( AttrVal($name,'wakeOnLanMAC','none') ne 'none' ) {
                LGTV_WebOS_WakeUp_Udp($hash,AttrVal($name,'wakeOnLanMAC',0),AttrVal($name,'wakeOnLanBroadcast','255.255.255.255'));
                return;
            } else {
                $uri                                = $lgCommands{powerOn};
            }
        }
        
    } elsif($cmd eq '3D') {
        return "usage: 3D on/off" if( @args != 1 );

        if($args[0] eq 'off') {
            $uri                                = $lgCommands{'3DOff'};
        } elsif ($args[0] eq 'on') {
            $uri                                = $lgCommands{'3DOn'};
        }
        
    } elsif($cmd eq 'mute') {
        return "usage: mute" if( @args != 1 );

        if($args[0] eq 'off') {

            $uri                                = $lgCommands{volumeDown}->[0];
        
        } elsif($args[0] eq 'on') {
        
            $payload{$lgCommands{$cmd}->[1]}    = 'true';
            $uri                                = $lgCommands{$cmd}->[0];
        }

    } elsif($cmd eq 'volume') {
        return "usage: volume" if( @args != 1 );

        $payload{$lgCommands{$cmd}->[1]}    = int(join(" ", @args));
        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'launchApp') {
        return "usage: launchApp" if( @args != 1 );

        $payload{$lgCommands{$cmd}->[1]}    = $openApps{join(" ", @args)};
        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'input') {
        return "usage: input" if( @args != 1 );

        my $inputLabel                          = join(" ", @args);
        $payload{$lgCommands{launchApp}->[1]}   = $hash->{helper}{device}{inputs}{$inputLabel};
        $uri                                    = $lgCommands{launchApp}->[0];
        
    } elsif($cmd eq 'volumeUp') {
        return "usage: volumeUp" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'volumeDown') {
        return "usage: volumeDown" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'channelDown') {
        return "usage: channelDown" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'channelUp') {
        return "usage: channelUp" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'channel') {
        return "usage: channel" if( @args != 1 );

        $payload{$lgCommands{openChannel}->[1]}    = join(" ", @args);
        $uri                                = $lgCommands{openChannel}->[0];
        
    } elsif($cmd eq 'getServiceList') {
        return "usage: getServiceList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];

    } elsif($cmd eq 'getChannelList') {
        return "usage: getChannelList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'getAppList') {
        return "usage: getAppList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'getExternalInputList') {
        return "usage: getExternalInputList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'play') {
        return "usage: play" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'stop') {
        return "usage: stop" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'fastForward') {
        return "usage: fastForward" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'rewind') {
        return "usage: rewind" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'pause') {
        return "usage: pause" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];

    } else {
        my  $list = ""; 
        $list .= "connect:noArg pairing:noArg screenMsg mute:on,off volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg channelDown:noArg channelUp:noArg getServiceList:noArg on:noArg off:noArg launchApp:Maxdome,AmazonVideo,YouTube,Netflix,TV,GooglePlay,Browser,Chilieu,TVCast,Smartshare,Scheduler,Miracast,TVGuide,Timemachine,ARDMediathek,Arte,WetterMeteo,Notificationcenter,Plex 3D:on,off stop:noArg play:noArg pause:noArg rewind:noArg fastForward:noArg clearInputList:noArg input:$inputs channel";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    $hash->{helper}{device}{runsetcmd}  = $hash->{helper}{device}{runsetcmd} + 1;
    LGTV_WebOS_CreateSendCommand($hash,$uri,\%payload);
}

sub LGTV_WebOS_Open($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = 3000;
    my $timeout = 0.1;
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - Baue Socket Verbindung auf";
    

    my $socket = new IO::Socket::INET   (   PeerHost => $host,
                                            PeerPort => $port,
                                            Proto => 'tcp',
                                            Timeout => $timeout
                                        )
        or return Log3 $name, 4, "LGTV_WebOS ($name) Couldn't connect to $host:$port";      # open Socket
        
    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $selectlist{$name} = $hash;
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - Socket Connected";
    
    LGTV_WebOS_Handshake($hash);
    Log3 $name, 4, "LGTV_WebOS ($name) - start Handshake";
    
}

sub LGTV_WebOS_Close($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    return if( !$hash->{CD} );

    close($hash->{CD}) if($hash->{CD});
    delete($hash->{FD});
    delete($hash->{CD});
    delete($selectlist{$name});
    
    Log3 $name, 4, "LGTV_WebOS ($name) - Socket Disconnected";
}

sub LGTV_WebOS_Write($@) {

    my ($hash,$string)  = @_;
    my $name            = $hash->{NAME};
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - WriteFn called";
    
    return Log3 $name, 4, "LGTV_WebOS ($name) - socket not connected"
    unless($hash->{CD});

    Log3 $name, 4, "LGTV_WebOS ($name) - $string";
    syswrite($hash->{CD}, $string);
    return undef;
}

sub LGTV_WebOS_Read($) {

    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $len;
    my $buf;
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - ReadFn started";

    $len = sysread($hash->{CD},$buf,10240);
    
    if( !defined($len) or !$len ) {

        LGTV_WebOS_Close($hash);

        return;
    }
    
	unless( defined $buf) { 
        Log3 $name, 3, "LGTV_WebOS ($name) - no data received";
        return; 
    }
    
    
    if( $buf =~ /({"type":".+}}$)/ ) {
    
        $buf =~ /({"type":".+}}$)/;
        $buf = $1;
        
        Log3 $name, 4, "LGTV_WebOS ($name) - received correct JSON string, start response processing: $buf";
        LGTV_WebOS_ResponseProcessing($hash,$buf);
        
    } elsif( $buf =~ /HTTP\/1.1 101 Switching Protocols/ ) {
    
        Log3 $name, 4, "LGTV_WebOS ($name) - received HTTP data string, start response processing: $buf";
        LGTV_WebOS_ResponseProcessing($hash,$buf);
        
    } else {
    
        Log3 $name, 4, "LGTV_WebOS ($name) - coruppted data found, run LGTV_WebOS_ProcessRead: $buf";
        LGTV_WebOS_ProcessRead($hash,$buf);
    }
}

sub LGTV_WebOS_ProcessRead($$) {

    my ($hash, $data) = @_;
    my $name = $hash->{NAME};
    
    my $buffer = '';
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - process read";

    if(defined($hash->{PARTIAL}) and $hash->{PARTIAL}) {
    
        Log3 $name, 5, "LGTV_WebOS ($name) - PARTIAL: " . $hash->{PARTIAL};
        $buffer = $hash->{PARTIAL};
        
    } else {
    
        Log3 $name, 4, "LGTV_WebOS ($name) - No PARTIAL buffer";
    }

    Log3 $name, 5, "LGTV_WebOS ($name) - Incoming data: " . $data;

    $buffer = $buffer  . $data;
    Log3 $name, 5, "LGTV_WebOS ($name) - Current processing buffer (PARTIAL + incoming data): " . $buffer;

    my ($json,$tail) = LGTV_WebOS_ParseMsg($hash, $buffer);


    while($json) {
    
        $hash->{LAST_RECV} = time();
        
        Log3 $name, 5, "LGTV_WebOS ($name) - Decoding JSON message. Length: " . length($json) . " Content: " . $json;
        Log3 $name, 5, "LGTV_WebOS ($name) - Vor Sub: Laenge JSON: " . length($json) . " Content: " . $json . " Tail: " . $tail;
        
        LGTV_WebOS_ResponseProcessing($hash,$json)
        unless(not defined($tail) and not ($tail));
        
        ($json,$tail) = LGTV_WebOS_ParseMsg($hash, $tail);
        
        Log3 $name, 5, "LGTV_WebOS ($name) - Nach Sub: Laenge JSON: " . length($json) . " Content: " . $json . " Tail: " . $tail;
    }


    $tail = ''
    if(length($tail) > 30000);
    $hash->{PARTIAL} = $tail;
    Log3 $name, 4, "LGTV_WebOS ($name) - PARTIAL lenght: " . length($tail);
    
    
    Log3 $name, 5, "LGTV_WebOS ($name) - Tail: " . $tail;
    Log3 $name, 5, "LGTV_WebOS ($name) - PARTIAL: " . $hash->{PARTIAL};
}

sub LGTV_WebOS_Handshake($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $wsKey   = encode_base64(gettimeofday());
    
    my $wsHandshakeCmd  = "";
    $wsHandshakeCmd     .= "GET / HTTP/1.1\r\n";
    $wsHandshakeCmd     .= "Host: $host\r\n";
    $wsHandshakeCmd     .= "User-Agent: FHEM\r\n";
    $wsHandshakeCmd     .= "Upgrade: websocket\r\n";
    $wsHandshakeCmd     .= "Connection: Upgrade\r\n";
    $wsHandshakeCmd     .= "Sec-WebSocket-Version: 13\r\n";            
    $wsHandshakeCmd     .= "Sec-WebSocket-Key: " . $wsKey . "\r\n";
    
    LGTV_WebOS_Write($hash,$wsHandshakeCmd);
    
    $hash->{helper}{wsKey}  = $wsKey;
    
    Log3 $name, 4, "LGTV_WebOS ($name) - send Handshake to WriteFn";
    
    
    LGTV_WebOS_TimerStatusRequest($hash);
    Log3 $name, 4, "LGTV_WebOS ($name) - start timer status request";
    
    LGTV_WebOS_Pairing($hash);
    Log3 $name, 4, "LGTV_WebOS ($name) - start pairing routine";
}

sub LGTV_WebOS_ResponseProcessing($$) {

    my ($hash,$response)    = @_;
    my $name            = $hash->{NAME};
    
    
    
    
    ########################
    ### Response has HTML Header
    if( $response =~ /HTTP\/1.1 101 Switching Protocols/ ) {
    
        my $data        = $response;
        my $header      = LGTV_WebOS_Header2Hash($data);
        
        ################################
        ### Handshake for first Connect
        if( defined($header->{'Sec-WebSocket-Accept'})) {
    
            my $keyAccept   = $header->{'Sec-WebSocket-Accept'};
            Log3 $name, 5, "LGTV_WebOS ($name) - keyAccept: $keyAccept";
        
            my $wsKey   = $hash->{helper}{wsKey};
            my $expectedResponse = trim(encode_base64(pack('H*', sha1_hex(trim($wsKey)."258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))));
        
            if ($keyAccept eq $expectedResponse) {
        
                Log3 $name, 3, "LGTV_WebOS ($name) - Sucessfull WS connection to $hash->{HOST}";
                readingsSingleUpdate($hash, 'state', 'on', 1 );
        
            } else {
                LGTV_WebOS_Close($hash);
                Log3 $name, 3, "LGTV_WebOS ($name) - ERROR: Unsucessfull WS connection to $hash->{HOST}";
            }
        }
        
        return undef;
    }
    
    
    elsif( $response =~ m/^{"type":".+}}$/ ) {
    
        return Log3 $name, 4, "LGTV_WebOS ($name) - garbage after JSON object"
        if($response =~ m/^{"type":".+}}.+{"type":".+/);
    
        Log3 $name, 4, "LGTV_WebOS ($name) - JSON detected, run LGTV_WebOS_WriteReadings";

        my $json        = $response;
        
        Log3 $name, 4, "LGTV_WebOS ($name) - Corrected JSON String: $json" if($json);
        
        if(not defined($json) or not ($json) ) {
        
            Log3 $name, 4, "LGTV_WebOS ($name) - Corrected JSON String empty";
            return;
        }
        
        my $decode_json     = decode_json(encode_utf8($json));
        if($@){
            Log3 $name, 3, "LGTV_WebOS ($name) - JSON error while request: $@";
            return;
        }

        LGTV_WebOS_WriteReadings($hash,$decode_json);
        
        return undef;
    }
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - no Match found";
}

sub LGTV_WebOS_WriteReadings($$) {

    my ($hash,$decode_json)    = @_;
    
    my $name            = $hash->{NAME};
    my $mute;
    my $response;
    my %channelList;

    
    Log3 $name, 4, "LGTV_WebOS ($name) - Beginn Readings writing";
    
    
    

    readingsBeginUpdate($hash);
    
    if( ref($decode_json->{payload}{services}) eq "ARRAY" and scalar(@{$decode_json->{payload}{services}}) > 0 ) {
        foreach my $services (@{$decode_json->{payload}{services}}) {
        
            readingsBulkUpdate($hash,'service_'.$services->{name},'v.'.$services->{version});
        }
    }
    
    elsif( ref($decode_json->{payload}{devices}) eq "ARRAY" and scalar(@{$decode_json->{payload}{devices}}) > 0 ) {
            
        foreach my $devices ( @{$decode_json->{payload}{devices}} ) {

            if( not defined($hash->{helper}{device}{inputs}{$devices->{label}}) or not defined($hash->{helper}{device}{inputapps}{$devices->{appId}}) ) {
            
                $hash->{helper}{device}{inputs}{$devices->{label}}   = $devices->{appId};
                $hash->{helper}{device}{inputapps}{$devices->{appId}}   = $devices->{label};
            }
            
            readingsBulkUpdate($hash,'extInput_'.$devices->{label},'connect_'.$devices->{connected});
        }
    }
    
    elsif( ref($decode_json->{payload}{programList}) eq "ARRAY" and scalar(@{$decode_json->{payload}{programList}}) > 0 ) {
        
        my $count = 0;
        foreach my $programList ( @{$decode_json->{payload}{programList}} ) {
            
            if($count < 1) {
            
                readingsBulkUpdate($hash,'channelCurrentTitle',$programList->{programName});
                readingsBulkUpdate($hash,'channelCurrentStartTime',LGTV_WebOS_FormartStartEndTime($programList->{localStartTime}));
                readingsBulkUpdate($hash,'channelCurrentEndTime',LGTV_WebOS_FormartStartEndTime($programList->{localEndTime}));
            
            } elsif($count < 2) {
            
                readingsBulkUpdate($hash,'channelNextTitle',$programList->{programName});
                readingsBulkUpdate($hash,'channelNextStartTime',LGTV_WebOS_FormartStartEndTime($programList->{localStartTime}));
                readingsBulkUpdate($hash,'channelNextEndTime',LGTV_WebOS_FormartStartEndTime($programList->{localEndTime}));
            }
            
            $count++;
            return if($count > 1);
        }
    }
    
    elsif( defined($decode_json->{payload}{'mute'}) or defined($decode_json->{payload}{'muted'})) {
    
        if( defined($decode_json->{payload}{'mute'}) and $decode_json->{payload}{'mute'} eq 'true' ) {
    
            readingsBulkUpdate($hash,'mute','on');
            
        } elsif( defined($decode_json->{payload}{'mute'}) ) {
            if( $decode_json->{payload}{'mute'} eq 'false' ) {
        
                readingsBulkUpdate($hash,'mute','off');
            }
        }
        
        if( defined($decode_json->{payload}{'muted'}) and $decode_json->{payload}{'muted'} eq 'true' ) {
        
                readingsBulkUpdate($hash,'mute','on');
            
        } elsif( defined($decode_json->{payload}{'muted'}) and $decode_json->{payload}{'muted'} eq 'false' ) {
        
            readingsBulkUpdate($hash,'mute','off');
        }
    }
    
    elsif( defined($decode_json->{payload}{status3D}{status}) ) {
        if( $decode_json->{payload}{status3D}{status} eq 'false' ) {
        
            readingsBulkUpdate($hash,'3D','off');
        
        } elsif( $decode_json->{payload}{status3D}{status} eq 'true' ) {
        
            readingsBulkUpdate($hash,'3D','on');
        }
        
        readingsBulkUpdate($hash,'3DMode',$decode_json->{payload}{status3D}{pattern});
    }

    elsif( defined($decode_json->{payload}{appId}) ) {
        
        if( $decode_json->{payload}{appId} =~ /com.webos.app.externalinput/ or $decode_json->{payload}{appId} =~ /com.webos.app.hdmi/ ) {

            readingsBulkUpdate($hash,'input',$hash->{helper}{device}{inputapps}{$decode_json->{payload}{appId}});
            readingsBulkUpdate($hash,'launchApp','-');
        
        } else {

            readingsBulkUpdate($hash,'launchApp',$openAppsPackageName{$decode_json->{payload}{appId}});
            readingsBulkUpdate($hash,'input','-');
        }
    }
    
    if( defined($decode_json->{type}) ) {
    
        if( $decode_json->{type} eq 'registered' and defined($decode_json->{payload}{'client-key'}) ) {
        
            $hash->{helper}{device}{registered}     = 1;
        
        } elsif( ($decode_json->{type} eq 'response' and $decode_json->{payload}{returnValue} eq 'true') or ($decode_json->{type} eq 'registered') and defined($decode_json->{payload}{'client-key'}) ) {
        
            $response = 'ok';
            readingsBulkUpdate($hash,'pairing','paired');
            $hash->{helper}{device}{runsetcmd}  = $hash->{helper}{device}{runsetcmd} - 1 if($hash->{helper}{device}{runsetcmd} > 0);
            
        } elsif( $decode_json->{type} eq 'error' ) {
        
            $response = "error - $decode_json->{error}";
            
            if($decode_json->{error} eq '401 insufficient permissions' or $decode_json->{error} eq '401 insufficient permissions (not registered)') {
            
                readingsBulkUpdate($hash,'pairing','unpaired');
            }
            
            $hash->{helper}{device}{runsetcmd}  = $hash->{helper}{device}{runsetcmd} - 1 if($hash->{helper}{device}{runsetcmd} > 0);
        }
    }
    
    
    readingsBulkUpdate($hash,'lgKey',$decode_json->{payload}{'client-key'});
    readingsBulkUpdate($hash,'volume',$decode_json->{payload}{'volume'});
    readingsBulkUpdate($hash,'lastResponse',$response);
    
    if( ReadingsVal($name,'launchApp','none') eq 'TV') {
    
        readingsBulkUpdate($hash,'channel',$decode_json->{payload}{'channelNumber'});
        readingsBulkUpdate($hash,'channelName',$decode_json->{payload}{'channelName'});
        readingsBulkUpdate($hash,'channelMedia',$decode_json->{payload}{'channelTypeName'});
    
    } else {
    
        readingsBulkUpdate($hash,'channelName','-');
        readingsBulkUpdate($hash,'channel','-');
        readingsBulkUpdate($hash,'channelMedia','-');
        readingsBulkUpdate($hash,'channelCurrentTitle','-');
        readingsBulkUpdate($hash,'channelCurrentStartTime','-');
        readingsBulkUpdate($hash,'channelCurrentEndTime','-');
        readingsBulkUpdate($hash,'channelNextTitle','-');
        readingsBulkUpdate($hash,'channelNextStartTime','-');
        readingsBulkUpdate($hash,'channelNextEndTime','-');
    }

    readingsEndUpdate($hash, 1);
}

sub LGTV_WebOS_Pairing($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    my $lgKey;
    
    Log3 $name, 4, "LGTV_WebOS ($name) - HASH handshakePayload";
    
    my %handshakePayload =  (   "pairingType" => "PROMPT",
                                "manifest" => {
                                    "manifestVersion" => 1,
                                    "appVersion" => "1.1",
                                    "signed" => {
                                        "created" => "20161123",
                                        "appId" => "com.lge.test",
                                        "vendorId" => "com.lge",
                                        "localizedAppNames" => {
                                            "" => "FHEM LG Remote",
                                            "de-DE" => "FHEM LG Fernbedienung"
                                            },
                                        "localizedVendorNames" => {
                                            "" => "LG Electronics"
                                        },
                                        "permissions" => [
                                            "TEST_SECURE",
                                            "CONTROL_INPUT_TEXT",
                                            "CONTROL_MOUSE_AND_KEYBOARD",
                                            "READ_INSTALLED_APPS",
                                            "READ_LGE_SDX",
                                            "READ_NOTIFICATIONS",
                                            "SEARCH",
                                            "WRITE_SETTINGS",
                                            "WRITE_NOTIFICATION_ALERT",
                                            "CONTROL_POWER",
                                            "READ_CURRENT_CHANNEL",
                                            "READ_RUNNING_APPS",
                                            "READ_UPDATE_INFO",
                                            "UPDATE_FROM_REMOTE_APP",
                                            "READ_LGE_TV_INPUT_EVENTS",
                                            "READ_TV_CURRENT_TIME"
                                        ],
                                        "serial" => "2f930e2d2cfe083771f68e4fe7bb07"
                                    },
                                    "permissions" => [
                                        "LAUNCH",
                                        "LAUNCH_WEBAPP",
                                        "APP_TO_APP",
                                        "CLOSE",
                                        "TEST_OPEN",
                                        "TEST_PROTECTED",
                                        "CONTROL_AUDIO",
                                        "CONTROL_DISPLAY",
                                        "CONTROL_INPUT_JOYSTICK",
                                        "CONTROL_INPUT_MEDIA_RECORDING",
                                        "CONTROL_INPUT_MEDIA_PLAYBACK",
                                        "CONTROL_INPUT_TV",
                                        "CONTROL_POWER",
                                        "READ_APP_STATUS",
                                        "READ_CURRENT_CHANNEL",
                                        "READ_INPUT_DEVICE_LIST",
                                        "READ_NETWORK_STATE",
                                        "READ_RUNNING_APPS",
                                        "READ_TV_CHANNEL_LIST",
                                        "WRITE_NOTIFICATION_TOAST",
                                        "READ_POWER_STATE",
                                        "READ_COUNTRY_INFO"
                                    ],
                                    "signatures" => [
                                        {
                                            "signatureVersion" => 1,
                                            "signature" => "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw=="
                                        }
                                    ]
                                }
                            );


    my $usedHandshake = \%handshakePayload;
    
    my $key = ReadingsVal($name, 'lgKey', '');

    $usedHandshake->{'client-key'} = $key if( defined($key));
    
    LGTV_WebOS_CreateSendCommand($hash, undef, $usedHandshake, 'register');
    Log3 $name, 4, "LGTV_WebOS ($name) - Send pairing informations";
}

sub LGTV_WebOS_CreateSendCommand($$$;$) {

    my ($hash, $uri, $payload, $type)   = @_;
    
    my $name                            = $hash->{NAME};
    my $err;
    
    
    $type = 'request' if( not defined($type) );
    
    my $command = {};
    $command->{'client-key'} = ReadingsVal($name, 'lgKey', '') if( $type ne 'register' );
    $command->{id} = $type."_".gettimeofday();
    $command->{type} = $type;
    $command->{uri} = $uri if($uri);
    $command->{payload} = $payload if( defined($payload) );
    
    #Log3 $name, 5, "LGTV_WebOS ($name) - Payload Message: $command->{payload}{message}";
    
    my $cmd = encode_json($command);
    
    Log3 $name, 5, "LGTV_WebOS ($name) - Sending command: $cmd";
    
    LGTV_WebOS_Write($hash, LGTV_WebOS_Hybi10Encode($cmd, "text", 1));
    
    return undef;
}

sub LGTV_WebOS_Hybi10Encode($;$$) {

    my ($payload, $type, $masked) = @_;
    
    
    $type //= "text";
    $masked //= 1;

    my @frameHead;
    my $frame = "";
    my $payloadLength = length($payload);

    
    if ($type eq "text") {
    
        # first byte indicates FIN, Text-Frame (10000001):
        $frameHead[0] = 129;
        
    } elsif ($type eq "close") {
    
        # first byte indicates FIN, Close Frame(10001000):
        $frameHead[0] = 136;
        
    } elsif ($type eq "ping") {
    
        # first byte indicates FIN, Ping frame (10001001):
        $frameHead[0] = 137;
    
    } elsif ($type eq "pong") {
    
        # first byte indicates FIN, Pong frame (10001010):
        $frameHead[0] = 138;
    }

    # set mask and payload length (using 1, 3 or 9 bytes)
    if ($payloadLength > 65535) {
    
        # TODO
        my $payloadLengthBin = sprintf('%064b', $payloadLength);
        $frameHead[1] = ($masked) ? 255 : 127;
    
        for (my $i = 0; $i < 8; $i++) {
        
            $frameHead[$i + 2] = oct("0b".substr($payloadLengthBin, $i*8, $i*8+8));
        }

        # most significant bit MUST be 0 (close connection if frame too big)
        if ($frameHead[2] > 127) {
        
            #$this->close(1004);
            return undef;
        }
        
    } elsif ($payloadLength > 125) {
    
        my $payloadLengthBin = sprintf('%016b', $payloadLength);
        $frameHead[1] = ($masked) ? 254 : 126;
        $frameHead[2] = oct("0b".substr($payloadLengthBin, 0, 8));
        $frameHead[3] = oct("0b".substr($payloadLengthBin, 8, 16));
        
    } else {
    
        $frameHead[1] = ($masked) ? $payloadLength + 128 : $payloadLength;
    }

    # convert frame-head to string:
    for (my $i = 0; $i < scalar(@frameHead); $i++) {
    
        $frameHead[$i] = chr($frameHead[$i]);
    }
    
    my @mask;
    if ($masked) {
        # generate a random mask:
        for (my $i = 0; $i < 4; $i++) {
        
            #$mask[$i] = chr(int(rand(255)));
            $mask[$i] = chr(int(25*$i));
        }
        
        @frameHead = (@frameHead, @mask);
    }
    
    $frame = join("", @frameHead);

    # append payload to frame:
    my $char;
    for (my $i = 0; $i < $payloadLength; $i++) {
    
        $char = substr($payload, $i, 1);
        $frame .= ($masked) ? $char ^ $mask[$i % 4] : $char;
    }
    
    return $frame;
}

sub LGTV_WebOS_GetAudioStatus($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetAudioStatus');
    Log3 $name, 4, "LGTV_WebOS ($name) - LGTV_WebOS_GetAudioStatus: " . $hash->{helper}{device}{runsetcmd};
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getAudioStatus},undef) if($hash->{helper}{device}{runsetcmd} == 0);
}

sub LGTV_WebOS_GetCurrentChannel($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetCurrentChannel');
    Log3 $name, 4, "LGTV_WebOS ($name) - LGTV_WebOS_GetCurrentChannel: " . $hash->{helper}{device}{runsetcmd};
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getCurrentChannel},undef) if($hash->{helper}{device}{runsetcmd} == 0);
}

sub LGTV_WebOS_GetForgroundAppInfo($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetForgroundAppInfo');
    Log3 $name, 4, "LGTV_WebOS ($name) - LGTV_WebOS_GetForgroundAppInfo: " . $hash->{helper}{device}{runsetcmd};
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getForegroundAppInfo},undef) if($hash->{helper}{device}{runsetcmd} == 0);
}

sub LGTV_WebOS_GetExternalInputList($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetExternalInputList');
    Log3 $name, 4, "LGTV_WebOS ($name) - LGTV_WebOS_GetExternalInputList: " . $hash->{helper}{device}{runsetcmd};
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getExternalInputList},undef) if($hash->{helper}{device}{runsetcmd} == 0);
}

sub LGTV_WebOS_Get3DStatus($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_Get3DStatus');
    Log3 $name, 4, "LGTV_WebOS ($name) - LGTV_WebOS_Get3DStatus: " . $hash->{helper}{device}{runsetcmd};
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{get3DStatus},undef) if($hash->{helper}{device}{runsetcmd} == 0);
}

sub LGTV_WebOS_GetChannelProgramInfo($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetChannelProgramInfo');
    Log3 $name, 4, "LGTV_WebOS ($name) - LGTV_WebOS_GetChannelProgramInfo: " . $hash->{helper}{device}{runsetcmd};
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getChannelProgramInfo},undef) if($hash->{helper}{device}{runsetcmd} == 0);
}




#############################################
### my little Helper

sub LGTV_WebOS_ParseMsg($$) {

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
                Log3 $name, 5, "LGTV_WebOS ($name) - $open == $close && $open > 0";
                
            } elsif(($open == $close) && ($c ne '{')) {
            
                Log3 $name, 5, "LGTV_WebOS ($name) - Garbage character before message: " . $c;
        
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
    
    Log3 $name, 5, "LGTV_WebOS ($name) - return msg: $msg and tail: $tail";
    return ($msg,$tail);
}

sub LGTV_WebOS_Header2Hash($) {

    my $string  = shift;
    my %hash = ();

    foreach my $line (split("\r\n", $string)) {
        my ($key,$value) = split( ": ", $line );
        next if( !$value );

        $value =~ s/^ //;
        $hash{$key} = $value;
    }     
        
    return \%hash;
}

sub LGTV_WebOS_FormartStartEndTime($) {

    my $string      = shift;
    
    
    my @timeArray   =   split(',', $string);
    
    return "$timeArray[0]-$timeArray[1]-$timeArray[2] $timeArray[3]:$timeArray[4]:$timeArray[5]";
}

############ Presence Erkennung Begin #################
sub LGTV_WebOS_Presence($) {

    my $hash    = shift;    
    my $name    = $hash->{NAME};
    
    
    $hash->{helper}{RUNNING_PID} = BlockingCall("LGTV_WebOS_PresenceRun", $name.'|'.$hash->{HOST}, "LGTV_WebOS_PresenceDone", 5, "LGTV_WebOS_PresenceAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}) );
}

sub LGTV_WebOS_PresenceRun($) {

    my $string          = shift;
    my ($name, $host)   = split("\\|", $string);
    
    my $tmp;
    my $response;

    
    $tmp = qx(ping -c 3 -w 2 $host 2>&1);

    if(defined($tmp) and $tmp ne "") {
    
        chomp $tmp;
        Log3 $name, 5, "LGTV_WebOS ($name) - ping command returned with output:\n$tmp";
        $response = "$name|".(($tmp =~ /\d+ [Bb]ytes (from|von)/ and not $tmp =~ /[Uu]nreachable/) ? "present" : "absent");
    
    } else {
    
        $response = "$name|Could not execute ping command";
    }
    
    Log3 $name, 4, "Sub LGTV_WebOS_PresenceRun ($name) - Sub finish, Call LGTV_WebOS_PresenceDone";
    return $response;
}

sub LGTV_WebOS_PresenceDone($) {

    my ($string)            = @_;
    
    my ($name,$response)    = split("\\|",$string);
    my $hash                = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 4, "Sub LGTV_WebOS_PresenceDone ($name) - Der Helper ist diabled. Daher wird hier abgebrochen" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    readingsSingleUpdate($hash, 'presence', $response, 1);
    
    Log3 $name, 4, "Sub LGTV_WebOS_PresenceDone ($name) - Abschluss!";
}

sub LGTV_WebOS_PresenceAborted($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    
    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,'presence','pingPresence timedout', 1);
    
    Log3 $name, 4, "Sub LGTV_WebOS_PresenceAborted ($name) - The BlockingCall Process terminated unexpectedly. Timedout!";
}

sub LGTV_WebOS_WakeUp_Udp($@) {

    my ($hash,$mac_addr,$host,$port) = @_;
    my $name  = $hash->{NAME};


    $port = 9 if (!defined $port || $port !~ /^\d+$/ );

    my $sock = new IO::Socket::INET(Proto=>'udp') or die "socket : $!";
    if(!$sock) {
        Log3 $name, 3, "Sub LGTV_WebOS_WakeUp_Udp ($name) - Can't create WOL socket";
        return 1;
    }
  
    my $ip_addr   = inet_aton($host);
    my $sock_addr = sockaddr_in($port, $ip_addr);
    $mac_addr     =~ s/://g;
    my $packet    = pack('C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16);

    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "setsockopt : $!";
    send($sock, $packet, 0, $sock_addr) or die "send : $!";
    close ($sock);

    return 1;
}

####### Presence Erkennung Ende ############










1;


=pod
=item device
=item summary       Controls LG SmartTVs run with WebOS Operating System (in beta phase)
=item summary_DE    Steuert LG SmartTVs mit WebOS Betriebssystem (derzeit Beta Status)

=begin html

<a name="LGTV_WebOS"></a>
<h3>LGTV_WebOS</h3>

<ul>
    This module controls SmartTVs from LG based on WebOS as operation system via network. It offers to swtich the TV channel, start and switch applications, send remote control commands, as well as to query the actual status.<p><br /><br />
    
    <strong>Definition </strong><code>define &lt;name&gt; LGTV_WebOS &lt;IP-Address&gt;</code>
    </p>
    <ul>
        <ul>
            When an LGTV_WebOS-Module is defined, an internal routine is triggered which queries the TV's status every 15s and triggers respective Notify / FileLog Event definitions.
        </ul>
    </ul>
    </p>
    <ul>
        <ul>
            Example:
        </ul>
        <ul>
            <code>define TV LGTV_WebOS 192.168.0.10 <br /></code><br /><br /></p>
        </ul>
    </ul>
        <p><code><strong>Set-Commands </strong><code>set &lt;Name&gt; &lt;Command&gt; [&lt;Parameter&gt;]</code></code></p>
    <ul>
        <ul>
            The following commands are supported in the actual version:
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li><strong>connect&nbsp;</strong> -&nbsp; Connects to the TV at the defined address. When triggered the first time, a pairing is conducted</li>
                <li><strong>pairing&nbsp;</strong> -&nbsp;&nbsp; Sends a pairing request to the TV which needs to be confirmed by the user with remote control</li>
                <li><strong>screenMsg</strong> &lt;Text&gt;&nbsp;&nbsp;-&nbsp;&nbsp; Displays a message for 3-5s on the TV in the top right corner of the screen</li>
                <li><strong>mute</strong> on, off&nbsp; -&nbsp; Turns volume to mute. Depending on the audio connection, this needs to be set on the AV Receiver (see volume) </li>
                <li><strong>volume </strong>0-100, Slider -&nbsp;&nbsp; Sets the volume. Depending on the audio connection, this needs to be set on the AV Receiver (see mute)</li>
                <li><strong>volumeUp</strong>&nbsp; -&nbsp;&nbsp; Increases the volume by 1</li>
                <li><strong>volumeDown</strong>&nbsp; -&nbsp;&nbsp; Decreases the volume by 1</li>
                <li><strong>channelUp</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Switches the channel to the next one</li>
                <li><strong>channelDown</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Switches the channel to the previous one</li>
                <li><strong>getServiceList&nbsp;</strong> -&nbsp; Queries the running services on WebOS (in beta phase)</li>
                <li><strong>on</strong> - Turns the TV on, depending on type of device. Only working when LAN or Wifi connection remains active during off state.</li>
                <li><strong>off</strong> - Turns the TV off, when an active connection is established</li>
                <li><strong>launchApp</strong> &lt;Application&gt;&nbsp;&nbsp;-&nbsp;&nbsp; Activates an application out of the following list (Maxdome, AmazonVideo, YouTube, Netflix, TV, GooglePlay, Browser, Chili, TVCast, Smartshare, Scheduler, Miracast, TV)&nbsp; <br />Note: TV is an application in LG's terms and not an input connection</li>
                <li><strong>3D</strong> on,off&nbsp; -&nbsp; 3D Mode is turned on and off. Depending on type of TV there might be different modes (e.g. Side-by-Side, Top-Bottom)</li>
                <li><strong>stop</strong>&nbsp; -&nbsp;&nbsp; Stop command (depending on application)</li>
                <li><strong>play&nbsp; </strong>-&nbsp;&nbsp; Play command (depending on application)</li>
                <li><strong>pause&nbsp; </strong>-&nbsp;&nbsp; Pause command (depending on application)</li>
                <li><strong>rewind&nbsp; </strong>-&nbsp;&nbsp; Rewind command (depending on application)</li>
                <li><strong>fastForward&nbsp; </strong>-&nbsp;&nbsp; Fast Forward command (depending on application)</li>
                <li><strong>clearInputList&nbsp;</strong> -&nbsp;&nbsp; Clears list of Inputs</li>
                <li><strong>input&nbsp;</strong> - Selects the input connection (depending on the actual TV type and connected devices) <br />e.g.: extInput_AV-1, extInput_HDMI-1, extInput_HDMI-2, extInput_HDMI-3)</li>
            </ul>
        </ul>
    </ul><br /><br /></p>
        <p><strong>Get-Command</strong> <code>get &lt;Name&gt; &lt;Readingname&gt;</code><br /></p>
    <ul>
        <ul>
            Currently, GET reads back the values of the current readings. Please see below for a list of Readings / Generated Events.
        </ul>
    </ul>
    <p><br /><strong>Attributes</strong></p>
    <ul>
        <ul>
            <li>disable</li>
            Optional attribute to deactivate the recurring status updates. Manual trigger of update is alsways possible.</br>
            Valid Values: 0 =&gt; recurring status updates, 1 =&gt; no recurring status updates.</p>
        </ul>
    </ul>
    <ul>
        <ul>
            <li>channelGuide</li>
            Optional attribute to deactivate the recurring TV Guide update. Depending on TV and FHEM host, this causes significant network traffic and / or CPU load</br>
            Valid Values: 0 =&gt; no recurring TV Guide updates, 1 =&gt; recurring TV Guide updates.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>pingPresence</li>
            current state of ping presence from TV. create a reading presence with values absent or present.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>wakeOnLanMAC</li>
            Network MAC Address of the LG TV Networkdevice.
        </ul>
    </ul>
    <ul>
        <ul>
            <li>wakeOnLanBroadcast</li>
            Broadcast Address of the Network - wakeOnLanBroadcast &lt;network&gt;.255
        </ul>
    </ul>
</ul>

=end html

=begin html_DE

<a name="LGTV_WebOS"></a>
<h3>LGTV_WebOS</h3>
<ul>
    <ul>
        Dieses Modul steuert SmartTV's des Herstellers LG mit dem Betriebssystem WebOS &uuml;ber die Netzwerkschnittstelle. Es bietet die M&ouml;glichkeit den aktuellen TV Kanal zu steuern, sowie Apps zu starten, Fernbedienungsbefehle zu senden, sowie den aktuellen Status abzufragen.
    </ul>
    <p><br /><br /><strong>Definition </strong><code>define &lt;name&gt; LGTV_WebOS &lt;IP-Addresse&gt;</code> <br /><br /></p>
    <ul>
        <ul>
            <ul>Bei der Definition eines LGTV_WebOS-Moduls wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig alle 15s den Status des TV abfragt und entsprechende Notify-/FileLog-Definitionen triggert.</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>Beispiel: <code>define TV LGTV_WebOS 192.168.0.10 <br /></code><br /><br /></ul>
        </ul>
    </ul>
    <strong>Set-Kommandos </strong><code>set &lt;Name&gt; &lt;Kommando&gt; [&lt;Parameter&gt;]</code>
    <ul>
        <ul>
            <ul>Aktuell werden folgende Kommandos unterst&uuml;tzt.</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <ul>
                    <li><strong>connect&nbsp;</strong> -&nbsp; Verbindet sich zum Fernseher unter der IP wie definiert, f&uuml;hrt beim ersten mal automatisch ein pairing durch</li>
                    <li><strong>pairing&nbsp;</strong> -&nbsp;&nbsp; Berechtigungsanfrage an den Fernseher, hier muss die Anfrage mit der Fernbedienung best&auml;tigt werden</li>
                    <li><strong>screenMsg</strong> &lt;Text&gt;&nbsp;&nbsp;-&nbsp;&nbsp; zeigt f&uuml;r ca 3-5s eine Nachricht auf dem Fernseher oben rechts an</li>
                    <li><strong>mute</strong> on, off&nbsp; -&nbsp; Schaltet den Fernseher Stumm, je nach Anschluss des Audiosignals, muss dieses am Verst&auml;rker (AV Receiver) geschehen (siehe Volume)</li>
                    <li><strong>volume </strong>0-100, Schieberegler&nbsp; -&nbsp;&nbsp; Setzt die Lautst&auml;rke des Fernsehers, je nach Anschluss des Audiosignals, muss dieses am Verst&auml;rker (AV Receiver) geschehen (siehe mute)</li>
                    <li><strong>volumeUp</strong>&nbsp; -&nbsp;&nbsp; Erh&ouml;ht die Lautst&auml;rke um den Wert 1</li>
                    <li><strong>volumeDown</strong>&nbsp; -&nbsp;&nbsp; Verringert die Lautst&auml;rke um den Wert 1</li>
                    <li><strong>channelUp</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet auf den n&auml;chsten Kanal um</li>
                    <li><strong>channelDown</strong> &nbsp;&nbsp;-&nbsp;&nbsp; Schaltet auf den vorherigen Kanal um</li>
                    <li><strong>getServiceList&nbsp;</strong> -&nbsp; Fragrt die Laufenden Dienste des Fernsehers an (derzeit noch in Beta-Phase)</li>
                    <li><strong>on</strong>&nbsp; -&nbsp;&nbsp; Schaltet den Fernseher ein, wenn WLAN oder LAN ebenfalls im Aus-Zustand aktiv ist (siehe Bedienungsanleitung da Typabh&auml;ngig)</li>
                    <li><strong>off</strong> - Schaltet den Fernseher aus, wenn eine Connection aktiv ist</li>
                    <li><strong>launchApp</strong> &lt;Anwendung&gt;&nbsp;&nbsp;-&nbsp;&nbsp; Aktiviert eine Anwendung aus der Liste (Maxdome, AmazonVideo, YouTube, Netflix, TV, GooglePlay, Browser, Chili, TVCast, Smartshare, Scheduler, Miracast, TV)&nbsp; <br />Achtung: TV ist hier eine Anwendung, und kein Ger&auml;teeingang</li>
                    <li><strong>3D</strong> on,off&nbsp; -&nbsp; 3D Modus kann hier ein- und ausgeschaltet werden, je nach Fernseher k&ouml;nnen mehrere 3D Modi unterst&uuml;tzt werden (z.B. Side-by-Side, Top-Bottom)</li>
                    <li><strong>stop</strong>&nbsp; -&nbsp;&nbsp; Stop-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>play&nbsp; </strong>-&nbsp;&nbsp; Play-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>pause&nbsp; </strong>-&nbsp;&nbsp; Pause-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>rewind&nbsp; </strong>-&nbsp;&nbsp; Zur&uuml;ckspulen-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>fastForward&nbsp; </strong>-&nbsp;&nbsp; Schneller-Vorlauf-Befehl (anwendungsabh&auml;ngig)</li>
                    <li><strong>clearInputList&nbsp;</strong> -&nbsp;&nbsp; L&ouml;scht die Liste der Ger&auml;teeing&auml;nge</li>
                    <li><strong>input&nbsp;</strong> - W&auml;hlt den Ger&auml;teeingang aus (Abh&auml;ngig von Typ und angeschossenen Ger&auml;ten) <br />Beispiele: extInput_AV-1, extInput_HDMI-1, extInput_HDMI-2, extInput_HDMI-3)</li>
                </ul>
            </ul>
        </ul>
    </ul>
    <p><strong>Get-Kommandos</strong> <code>get &lt;Name&gt; &lt;Readingname&gt;</code><br /><br /></p>
    <ul>
        <ul>
            <ul>Aktuell stehen via GET lediglich die Werte der Readings zur Verf&uuml;gung. Eine genaue Auflistung aller m&ouml;glichen Readings folgen unter "Generierte Readings/Events".</ul>
        </ul>
    </ul>
    <p><br /><br /><strong>Attribute</strong></p>
    <ul>
        <ul>
            <ul>
                <li>disable</li>
                Optionales Attribut zur Deaktivierung des zyklischen Status-Updates. Ein manuelles Update via statusRequest-Befehl ist dennoch m&ouml;glich.
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>M&ouml;gliche Werte: 0 =&gt; zyklische Status-Updates, 1 =&gt; keine zyklischen Status-Updates.</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>channelGuide</li>
                Optionales Attribut zur Deaktivierung der zyklischen Updates des TV-Guides, dieses beansprucht je nach Hardware einigen Netzwerkverkehr und Prozessorlast
            </ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>M&ouml;gliche Werte: 0 =&gt; keine zyklischen TV-Guide-Updates, 1 =&gt; zyklische TV-Guide-Updates</ul>
        </ul>
    </ul>
    <ul>
        <ul>
            <ul>
                <li>wakeOnLanMAC</li>
                MAC Addresse der Netzwerkkarte vom LG TV
            </ul>
        </ul>        
    </ul>    
    <ul>
        <ul>
            <ul>
                <li>wakeOnLanBroadcast</li>
                Broadcast Netzwerkadresse - wakeOnLanBroadcast &lt;netzwerk&gt;.255
            </ul>
        </ul>
    </ul>
    <p><br /><br /><strong>Generierte Readings/Events:</strong></p>
    <ul>
        <ul>
            <li><strong>3D</strong> - Status des 3D-Wiedergabemodus ("on" =&gt; 3D Wiedergabemodus aktiv, "off" =&gt; 3D Wiedergabemodus nicht aktiv)</li>
            <li><strong>3DMode</strong> - Anzeigemodus (2d, 2dto3d, side_side_half, line_interleave_half, column_interleave, check_board)</li>
            <li><strong>channel</strong> - Die Nummer des aktuellen TV-Kanals</li>
            <li><strong>channelName</strong> - Der Name des aktuellen TV-Kanals</li>
            <li><strong>channelMedia</strong> - Senderinformation</li>
            <li><strong>channelCurrentEndTime </strong>- Ende der laufenden Sendung (Beta)</li>
            <li><strong>channelCurrentStartTime </strong>- Start der laufenden Sendung (Beta)</li>
            <li><strong>channelCurrentTitle</strong> - Der Name der laufenden Sendung (Beta)</li>
            <li><strong>channelNextEndTime </strong>- Ende der n&auml;chsten Sendung (Beta)</li>
            <li><strong>channelNextStartTime </strong>- Start der n&auml;chsten Sendung (Beta)</li>
            <li><strong>channelNextTitle</strong> - Der Name der n&auml;chsten Sendung (Beta)</li>
            <li><strong>extInput_&lt;Ger&auml;teeingang</strong>&gt; - Status der Eingangsquelle (connect_true, connect_false)</li>
            <li><strong>input</strong> - Derzeit aktiver Ger&auml;teeingang</li>
            <li><strong>lastResponse </strong>- Status der letzten Anfrage (ok, error &lt;Fehlertext&gt;)</li>
            <li><strong>launchApp</strong> &lt;Anwendung&gt; - Gegenw&auml;rtige aktive Anwendung</li>
            <li><strong>lgKey</strong> - Der Client-Key, der f&uuml;r die Verbindung verwendet wird</li>
            <li><strong>mute</strong> on,off - Der aktuelle Stumm-Status ("on" =&gt; Stumm, "off" =&gt; Laut)</li>
            <li><strong>pairing</strong> paired, unpaired - Der Status des Pairing</li>
            <li><strong>presence </strong>absent, present - Der aktuelle Power-Status ("present" =&gt; eingeschaltet, "absent" =&gt; ausgeschaltet)</li>
            <li><strong>state</strong> on, off - Status des Fernsehers (&auml;hnlich presence)</li>
            <li><strong>volume</strong> - Der aktuelle Lautst&auml;rkepegel -1, 0-100 (-1 invalider Wert)</li>
        </ul>
    </ul>
</ul>
=end html_DE

=cut

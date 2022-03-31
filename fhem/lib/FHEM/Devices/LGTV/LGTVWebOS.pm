###############################################################################
#
# Developed with VSCodium and richterger perl plugin.
#
#  (c) 2017-2022 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
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
package FHEM::Devices::LGTV::LGTVWebOS;

use strict;
use warnings;
use experimental qw /switch/;

## try / catch
use Try::Tiny;

# use Carp;
use autodie qw /:io/;
##

use FHEM::Meta;
use GPUtils qw(GP_Import);

#-- Run before package compilation
BEGIN {
    #-- Export to main context with different name
    GP_Import(
        qw(
          modules
          init_done
          selectlist
          defs
          )
    );
}

my $missingModul = "";

eval { require MIME::Base64;     1 } or $missingModul .= 'MIME::Base64 ';
eval { require IO::Socket::INET; 1 } or $missingModul .= 'IO::Socket::INET ';

## no critic (Conditional "use" statement. Use "require" to conditionally include a module (Modules::ProhibitConditionalUseStatements))
eval { use Digest::SHA qw /sha1_hex/; 1 } or $missingModul .= 'Digest::SHA ';
eval { use Encode qw /encode_utf8 decode_utf8/; 1 }
  or $missingModul .= 'Encode ';
## use critic

eval { require Blocking; 1 } or $missingModul .= 'Blocking ';

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
} or do {

    # try to use JSON wrapper
    #   for chance of better performance
    eval {
        # JSON preference order
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless ( defined( $ENV{PERL_JSON_BACKEND} ) );

        require JSON;
        import JSON qw( decode_json encode_json );
        1;
    } or do {

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        } or do {

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            } or do {

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                } or do {

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                };
            };
        };
    };
};

my %lgCommands = (

    "getServiceList"        => ["ssap://api/getServiceList"],
    "getChannelList"        => ["ssap://tv/getChannelList"],
    "getVolume"             => ["ssap://audio/getVolume"],
    "getAudioStatus"        => ["ssap://audio/getStatus"],
    "getCurrentChannel"     => ["ssap://tv/getCurrentChannel"],
    "getChannelProgramInfo" => ["ssap://tv/getChannelProgramInfo"],
    "getForegroundAppInfo" =>
      ["ssap://com.webos.applicationManager/getForegroundAppInfo"],
    "getAppList"   => ["ssap://com.webos.applicationManager/listApps"],
    "getAppStatus" => ["ssap://com.webos.service.appstatus/getAppStatus"],
    "getExternalInputList" => ["ssap://tv/getExternalInputList"],
    "get3DStatus" => ["ssap://com.webos.service.tv.display/get3DStatus"],
    "powerOff"    => ["ssap://system/turnOff"],
    "powerOn"     => ["ssap://system/turnOn"],
    "3DOn"        => ["ssap://com.webos.service.tv.display/set3DOn"],
    "3DOff"       => ["ssap://com.webos.service.tv.display/set3DOff"],
    "volumeUp"    => ["ssap://audio/volumeUp"],
    "volumeDown"  => ["ssap://audio/volumeDown"],
    "channelDown" => ["ssap://tv/channelDown"],
    "channelUp"   => ["ssap://tv/channelUp"],
    "play"        => ["ssap://media.controls/play"],
    "stop"        => ["ssap://media.controls/stop"],
    "pause"       => ["ssap://media.controls/pause"],
    "rewind"      => ["ssap://media.controls/rewind"],
    "fastForward" => ["ssap://media.controls/fastForward"],
    "closeViewer" => ["ssap://media.viewer/close"],
    "closeApp"    => ["ssap://system.launcher/close"],
    "openApp"     => ["ssap://system.launcher/open"],
    "closeWebApp" => ["ssap://webapp/closeWebApp"],
    "openChannel" => [ "ssap://tv/openChannel", "channelNumber" ],
    "launchApp"   => [ "ssap://system.launcher/launch", "id" ],
    "screenMsg"   => [ "ssap://system.notifications/createToast", "message" ],
    "mute"        => [ "ssap://audio/setMute", "mute" ],
    "volume"      => [ "ssap://audio/setVolume", "volume" ],
    "switchInput" => [ "ssap://tv/switchInput", "input" ],
);

my %openApps = (
    'Maxdome'            => 'maxdome',
    'AmazonLovefilm'     => 'lovefilm.de',
    'AmazonVideo'        => 'amazon',
    'YouTube'            => 'youtube.leanback.v4',
    'Netflix'            => 'netflix',
    'TV'                 => 'com.webos.app.livetv',
    'GooglePlay'         => 'googleplaymovieswebos',
    'Browser'            => 'com.webos.app.browser',
    'Chili.tv'           => 'Chilieu',
    'TVCast'             => 'de.2kit.castbrowsing',
    'Smartshare'         => 'com.webos.app.smartshare',
    'Scheduler'          => 'com.webos.app.scheduler',
    'Miracast'           => 'com.webos.app.miracast',
    'TVGuide'            => 'com.webos.app.tvguide',
    'Timemachine'        => 'com.webos.app.timemachine',
    'ARDMediathek'       => 'ard.mediathek',
    'Arte'               => 'com.3827031.168353',
    'WetterMeteo'        => 'meteonews',
    'Notificationcenter' => 'com.webos.app.notificationcenter',
    'Plex'               => 'cdp-30',
    'SkyOnline'          => 'de.sky.skyonline',
    'Smart-IPTV'         => 'com.1827622.109556',
    'Spotify'            => 'spotify-beehive',
    'DuplexIPTV'         => 'com.duplexiptv.app',
    'Disney+'            => 'com.disney.disneyplus-prod',
    'Smart-IPTV'         => 'siptv',
    'AppleTV'            => 'com.apple.appletv',
    'Joyn'               => 'joyn',
    'YouTube-Kids'       => 'youtube.leanback.kids.v4',
    'DAZN'               => 'dazn',
    'SkyQ'               => 'com.skygo.app.de.q',
    'WaipuTv'            => 'tv.waipu.app.waipu-lg',
);

my %openAppsPackageName = reverse %openApps;

sub Define {
    my $hash = shift;
    my $def  = shift;
    my $version;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    $version = FHEM::Meta::Get( $hash, 'version' );
    our $VERSION = $version;

    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> LGTV_WebOS <HOST>" if ( @a != 3 );
    return
      "Cannot define LGTV_WebOS device. Perl modul ${missingModul} is missing."
      if ($missingModul);

    my $name = $a[0];
    my $host = $a[2];

    $hash->{HOST}    = $host;
    $hash->{VERSION} = version->parse($VERSION)->normal;
    $hash->{PARTIAL} = '';
    $hash->{helper}{device}{channelguide}{counter} = 0;
    $hash->{helper}{device}{registered}            = 0;
    $hash->{helper}{device}{runsetcmd}             = 0;

    ::Log3( $name, 3, "LGTV_WebOS ($name) - defined with host $host" );

    ::CommandAttr( undef,
        $name . ' devStateIcon on:10px-kreis-gruen:off off:10px-kreis-rot:on' )
      if ( ::AttrVal( $name, 'devStateIcon', 'none' ) eq 'none' );
    ::CommandAttr( undef, $name . ' room LGTV' )
      if ( ::AttrVal( $name, 'room', 'none' ) eq 'none' );

    ::CommandDeleteReading( undef, $name . ' presence' )
      if ( ::AttrVal( $name, 'pingPresence', 0 ) == 0 );

    $modules{LGTV_WebOS}{defptr}{ $hash->{HOST} } = $hash;

    ::readingsSingleUpdate( $hash, 'state', 'Initialized', 1 );

    if ($init_done) {
        TimerStatusRequest($hash);
    }
    else {
        ::InternalTimer( ::gettimeofday() + 15,
            \&FHEM::Devices::LGTV::LGTVWebOS::TimerStatusRequest, $hash );
    }

    $hash->{helper}->{lastResponse} =
      int( ::gettimeofday() );    # Check Socket KeepAlive

    return;
}

sub Undef {
    my $hash = shift;
    my $arg  = shift;

    my $host = $hash->{HOST};
    my $name = $hash->{NAME};

    ::RemoveInternalTimer($hash);
    delete $modules{LGTV_WebOS}{defptr}{ $hash->{HOST} };
    ::Log3( $name, 3, "LGTV_WebOS ($name) - device $name deleted" );

    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    my $orig = $attrVal;

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" && $attrVal eq "1" ) {
            ::RemoveInternalTimer($hash);
            ::readingsSingleUpdate( $hash, "state", "disabled", 1 );
            $hash->{PARTIAL} = '';
            ::Log3( $name, 3, "LGTV_WebOS ($name) - disabled" );
        }

        elsif ( $cmd eq "del" ) {
            ::readingsSingleUpdate( $hash, "state", "active", 1 );
            ::Log3( $name, 3, "LGTV_WebOS ($name) - enabled" );
            TimerStatusRequest($hash);
        }
    }

    if ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            ::Log3( $name, 3,
                "LGTV_WebOS ($name) - enable disabledForIntervals" );
            ::readingsSingleUpdate( $hash, "state", "Unknown", 1 );
        }

        elsif ( $cmd eq "del" ) {
            ::readingsSingleUpdate( $hash, "state", "active", 1 );
            ::Log3( $name, 3,
                "LGTV_WebOS ($name) - delete disabledForIntervals" );
        }
    }

    return;
}

sub TimerStatusRequest {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer( $hash, \&TimerStatusRequest );

    ::readingsBeginUpdate($hash);

    if (   !::IsDisabled($name)
        && $hash->{CD}
        && $hash->{helper}{device}{registered} == 1 )
    {

        ::Log3( $name, 4, "LGTV_WebOS ($name) - run get functions" );

        Presence($hash)
          if ( ::AttrVal( $name, 'pingPresence', 0 ) == 1 );

        if (   $hash->{helper}{device}{channelguide}{counter} > 2
            && ::AttrVal( $name, 'channelGuide', 0 ) == 1
            && ::ReadingsVal( $name, 'launchApp', 'TV' ) eq 'TV' )
        {

            GetChannelProgramInfo($hash);
            $hash->{helper}{device}{channelguide}{counter} = 0;

        }
        else {

            GetAudioStatus($hash);
            ::InternalTimer( ::gettimeofday() + 2,
                \&FHEM::Devices::LGTV::LGTVWebOS::GetCurrentChannel, $hash )
              if ( ::ReadingsVal( $name, 'launchApp', 'TV' ) eq 'TV' );
            ::InternalTimer( ::gettimeofday() + 4,
                \&FHEM::Devices::LGTV::LGTVWebOS::GetForgroundAppInfo, $hash );
            ::InternalTimer( ::gettimeofday() + 6,
                \&FHEM::Devices::LGTV::LGTVWebOS::Get3DStatus, $hash );
            ::InternalTimer( ::gettimeofday() + 8,
                \&FHEM::Devices::LGTV::LGTVWebOS::GetExternalInputList, $hash );
        }

    }
    elsif ( ::IsDisabled($name) ) {

        Close($hash);
        Presence($hash)
          if ( ::AttrVal( $name, 'pingPresence', 0 ) == 1 );
        $hash->{helper}{device}{runsetcmd} = 0;
        ::readingsBulkUpdateIfChanged( $hash, 'state', 'disabled' );

    }
    else {
        ::readingsBulkUpdateIfChanged( $hash, 'state', 'off' )
          if ( ::ReadingsVal( $name, 'state', 'off' ) ne 'off' );

        Presence($hash)
          if ( ::AttrVal( $name, 'pingPresence', 0 ) == 1 );

        ::readingsBulkUpdateIfChanged( $hash, 'channel',                 '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelName',             '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelMedia',            '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentTitle',     '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentStartTime', '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentEndTime',   '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelNextTitle',        '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelNextStartTime',    '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelNextEndTime',      '-' );

        $hash->{helper}{device}{runsetcmd} = 0;
    }

    ::readingsEndUpdate( $hash, 1 );

    Open($hash) if ( !::IsDisabled($name) && !$hash->{CD} );

    $hash->{helper}{device}{channelguide}{counter} =
      $hash->{helper}{device}{channelguide}{counter} + 1;
    ::InternalTimer( ::gettimeofday() + 10,
        \&FHEM::Devices::LGTV::LGTVWebOS::TimerStatusRequest, $hash );

    SocketKeepAlive($hash)
      if ( ::AttrVal( $name, 'keepAliveCheckTime', 0 ) > 0 )
      ;    # Check Socket KeepAlive

    return;
}

sub Set {    ## no critic (Subroutine "Set" with high complexity score)
    my ( $hash, $name, $cmd, @args ) = @_;
    my ( $arg, @params ) = @args;

    my $uri;
    my %payload;

    given ($cmd) {
        when ('connect') {
            return "usage: connect" if ( @args != 0 );

            Open($hash);

            return;

        }
        when ('clearInputList') {
            return "usage: clearInputList" if ( @args != 0 );

            delete $hash->{helper}{device}{inputs};
            delete $hash->{helper}{device}{inputapps};

            return;

        }
        when ('pairing') {
            return "usage: pairing" if ( @args != 0 );

            Pairing($hash);

            return;

        }
        when ('screenMsg') {
            return "usage: screenMsg <message>" if ( @args < 1 );

            my $msg = join( " ", @args );
            $payload{ $lgCommands{$cmd}->[1] } = decode_utf8($msg);
            $uri = $lgCommands{$cmd}->[0];

        }
        when ('off') {
            return "usage: on/off" if ( @args != 0 );

            $uri = $lgCommands{powerOff};
        }
        when ('on') {
            if ( ::AttrVal( $name, 'wakeOnLanMAC', 'none' ) ne 'none' ) {
                WakeUp_Udp(
                    $hash,
                    ::AttrVal( $name, 'wakeOnLanMAC',       0 ),
                    ::AttrVal( $name, 'wakeOnLanBroadcast', '255.255.255.255' )
                );
                return;
            }
            elsif ( ::AttrVal( $name, 'wakeupCmd', 'none' ) ne 'none' ) {
                my $wakeupCmd = ::AttrVal( $name, 'wakeupCmd', 'none' );
                if ( $wakeupCmd =~ s/^[ \t]*\{|\}[ \t]*$//xg ) {
                    ::Log3( $name, 4,
"LGTV_WebOS executing wake-up command (Perl): $wakeupCmd"
                    );
                    eval { $wakeupCmd } or do {
                        ::Log3( $name, 2,
"LGTV_WebOS executing wake-up command (Perl): $wakeupCmd failed"
                        );
                        return;
                    };
                    return;
                }
                else {
                    ::Log3( $name, 4,
"LGTV_WebOS executing wake-up command (fhem): $wakeupCmd"
                    );
                    ::fhem $wakeupCmd;
                    return;
                }
            }
            else {
                $uri = $lgCommands{powerOn};
            }
        }
        when ('3D') {
            return "usage: 3D on/off" if ( @args != 1 );

            if ( $args[0] eq 'off' ) {
                $uri = $lgCommands{'3DOff'};
            }
            elsif ( $args[0] eq 'on' ) {
                $uri = $lgCommands{'3DOn'};
            }

        }
        when ('mute') {
            return "usage: mute" if ( @args != 1 );

            if ( $args[0] eq 'off' ) {

                $uri = $lgCommands{volumeDown}->[0];

            }
            elsif ( $args[0] eq 'on' ) {

                $payload{ $lgCommands{$cmd}->[1] } = 'true';
                $uri = $lgCommands{$cmd}->[0];
            }

        }
        when ('volume') {
            return "usage: volume" if ( @args != 1 );

            $payload{ $lgCommands{$cmd}->[1] } = int( join( " ", @args ) );
            $uri = $lgCommands{$cmd}->[0];

        }
        when ('launchApp') {
            return "usage: launchApp" if ( @args != 1 );

            $payload{ $lgCommands{$cmd}->[1] } =
              $openApps{ join( " ", @args ) };
            $uri = $lgCommands{$cmd}->[0];

        }
        when ('input') {
            return "usage: input" if ( @args != 1 );

            my $inputLabel = join( " ", @args );
            $payload{ $lgCommands{launchApp}->[1] } =
              $hash->{helper}{device}{inputs}{$inputLabel};
            $uri = $lgCommands{launchApp}->[0];

        }
        when ('volumeUp') {
            return "usage: volumeUp" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('volumeDown') {
            return "usage: volumeDown" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('channelDown') {
            return "usage: channelDown" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('channelUp') {
            return "usage: channelUp" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('channel') {
            return "usage: channel" if ( @args != 1 );

            $payload{ $lgCommands{openChannel}->[1] } = join( " ", @args );
            $uri = $lgCommands{openChannel}->[0];

        }
        when ('getServiceList') {
            return "usage: getServiceList" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('getChannelList') {
            return "usage: getChannelList" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('getAppList') {
            return "usage: getAppList" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('getExternalInputList') {
            return "usage: getExternalInputList" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('play') {
            return "usage: play" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('stop') {
            return "usage: stop" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('fastForward') {
            return "usage: fastForward" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('rewind') {
            return "usage: rewind" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        when ('pause') {
            return "usage: pause" if ( @args != 0 );

            $uri = $lgCommands{$cmd}->[0];

        }
        default {
            my $list = "";
            $list .=
'connect:noArg pairing:noArg screenMsg mute:on,off volume:slider,0,1,100 volumeUp:noArg volumeDown:noArg channelDown:noArg channelUp:noArg getServiceList:noArg on:noArg off:noArg';
            $list .=
' 3D:on,off stop:noArg play:noArg pause:noArg rewind:noArg fastForward:noArg clearInputList:noArg channel';
            $list .=
              ## no critic (Expression form of map. See page 169 of PBP)
              ' launchApp:' . join( ',', => map qq{$_} => keys %openApps );
            $list .= ' input:' . join(
                ',',
                ## no critic (Expression form of map. See page 169 of PBP)
                => map qq{$_} => keys %{ $hash->{helper}{device}{inputs} }
              )
              if ( exists( $hash->{helper}{device}{inputs} )
                && ref( $hash->{helper}{device}{inputs} ) eq "HASH" );

            return "Unknown argument $cmd, choose one of $list";
        }
    }

    $hash->{helper}{device}{runsetcmd} = $hash->{helper}{device}{runsetcmd} + 1;
    return CreateSendCommand( $hash, $uri, \%payload );
}

sub Open {
    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = 3000;
    my $timeout = 0.1;

    ::Log3( $name, 4, "LGTV_WebOS ($name) - Baue Socket Verbindung auf" );

    my $socket = IO::Socket::INET->new(
        PeerHost  => $host,
        PeerPort  => $port,
        Proto     => 'tcp',
        KeepAlive => 1,
        Timeout   => $timeout
      )
      or return ::Log3( $name, 4,
        "LGTV_WebOS ($name) Couldn't connect to $host:$port" );    # open Socket

    $hash->{FD} = $socket->fileno();
    $hash->{CD} = $socket;             # sysread / close won't work on fileno
    $selectlist{$name} = $hash;

    $hash->{helper}->{lastResponse} =
      int( ::gettimeofday() );         # Check Socket KeepAlive

    ::Log3( $name, 4, "LGTV_WebOS ($name) - Socket Connected" );

    Handshake($hash);
    ::Log3( $name, 4, "LGTV_WebOS ($name) - start Handshake" );

    return;
}

sub Close {
    my $hash = shift;
    my $name = $hash->{NAME};

    return if ( !$hash->{CD} );

    delete( $hash->{PARTIAL} );

    close( $hash->{CD} ) if ( $hash->{CD} );
    delete( $hash->{CD} );

    delete( $selectlist{$name} );
    delete( $hash->{FD} );

    ::readingsSingleUpdate( $hash, 'state', 'off', 1 );

    ::Log3( $name, 4, "LGTV_WebOS ($name) - Socket Disconnected" );

    return;
}

sub Write {
    my $hash   = shift;
    my $string = shift;

    my $name = $hash->{NAME};

    ::Log3( $name, 4, "LGTV_WebOS ($name) - WriteFn called" );

    return ::Log3( $name, 4, "LGTV_WebOS ($name) - socket not connected" )
      unless ( $hash->{CD} );

    ::Log3( $name, 4, "LGTV_WebOS ($name) - $string" );

    try {
        syswrite( $hash->{CD}, $string );
    }
    catch {
        if ( $_->isa('autodie::exception') && $_->matches(':io') ) {
            ::Log3( $name, 2,
"LGTV_WebOS ($name) - can't write to socket, autodie exception: $_"
            );
            return;
        }
        else {
            ::Log3( $name, 2,
                "LGTV_WebOS ($name) - can't write to socket: $_" );
            return;
        }
    };

    return;
}

sub SocketKeepAlive {
    my $hash = shift;
    my $name = $hash->{NAME};

    if (
        int( ::gettimeofday() ) - int( $hash->{helper}->{lastResponse} ) >
        ::AttrVal( $name, 'keepAliveCheckTime', 0 ) )
    {
        SocketClosePresenceAbsent( $hash, 'absent' );
        ::Log3( $name, 4,
"LGTV_WebOS ($name) - KeepAlive It looks like there no Data more response"
        );
    }

    return;
}

sub Read {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $len;
    my $buf;

    ::Log3( $name, 4, "LGTV_WebOS ($name) - ReadFn started" );

    $hash->{helper}->{lastResponse} =
      int( ::gettimeofday() );    # Check Socket KeepAlive

    try {
        $len = sysread( $hash->{CD}, $buf, 10240 );
    }
    catch {
        if ( $_->isa('autodie::exception') && $_->matches(':io') ) {
            ::Log3( $name, 2,
"LGTV_WebOS ($name) - can't read from socket, autodie exception: $_"
            );
            return;
        }
        else {
            ::Log3( $name, 2,
                "LGTV_WebOS ($name) - can't read from socket: $_" );
            return;
        }
    };

    if ( !defined($len) || !$len ) {

        Close($hash);

        return;
    }

    unless ( defined $buf ) {
        ::Log3( $name, 3, "LGTV_WebOS ($name) - no data received" );
        return;
    }

    if ( $buf =~ /(\{"type":".+}}$)/x ) {

        $buf =~ /(\{"type":".+}}$)/x;
        ## no critic (Capture variable used outside conditional. See page 253 of PBP)
        $buf = $1;
        ## use critic

        ::Log3( $name, 4,
"LGTV_WebOS ($name) - received correct JSON string, start response processing: $buf"
        );

        ResponseProcessing( $hash, $buf );

    }
    elsif ( $buf =~ /HTTP\/1.1 101 Switching Protocols/x ) {

        ::Log3( $name, 4,
"LGTV_WebOS ($name) - received HTTP data string, start response processing: $buf"
        );

        ResponseProcessing( $hash, $buf );

    }
    else {

        ::Log3( $name, 4,
"LGTV_WebOS ($name) - coruppted data found, run LGTV_WebOS_ProcessRead: $buf"
        );

        ProcessRead( $hash, $buf );
    }

    return;
}

sub ProcessRead {
    my $hash = shift;
    my $data = shift;

    my $name = $hash->{NAME};

    my $buffer = '';

    ::Log3( $name, 4, "LGTV_WebOS ($name) - process read" );

    if ( exists( $hash->{PARTIAL} ) && $hash->{PARTIAL} ) {

        ::Log3( $name, 5, "LGTV_WebOS ($name) - PARTIAL: " . $hash->{PARTIAL} );
        $buffer = $hash->{PARTIAL};

    }
    else {

        ::Log3( $name, 4, "LGTV_WebOS ($name) - No PARTIAL buffer" );
    }

    ::Log3( $name, 5, "LGTV_WebOS ($name) - Incoming data: " . $data );

    $buffer = $buffer . $data;
    ::Log3( $name, 5,
"LGTV_WebOS ($name) - Current processing buffer (PARTIAL + incoming data): "
          . $buffer );

    my ( $json, $tail ) = ParseMsg( $hash, $buffer );

    while ($json) {

        $hash->{LAST_RECV} = time();

        ::Log3( $name, 5,
                "LGTV_WebOS ($name) - Decoding JSON message. Length: "
              . length($json)
              . " Content: "
              . $json );
        ::Log3( $name, 5,
                "LGTV_WebOS ($name) - Vor Sub: Laenge JSON: "
              . length($json)
              . " Content: "
              . $json
              . " Tail: "
              . $tail );

        ResponseProcessing( $hash, $json )
          if ( defined($tail) && ($tail) );

        ( $json, $tail ) = ParseMsg( $hash, $tail );

        ::Log3( $name, 5,
                "LGTV_WebOS ($name) - Nach Sub: Laenge JSON: "
              . length($json)
              . " Content: "
              . $json
              . " Tail: "
              . $tail );
    }

    $tail = ''
      if ( length($tail) > 30000 );
    $hash->{PARTIAL} = $tail;
    ::Log3( $name, 4, "LGTV_WebOS ($name) - PARTIAL lenght: " . length($tail) );

    ::Log3( $name, 5, "LGTV_WebOS ($name) - Tail: " . $tail );
    ::Log3( $name, 5, "LGTV_WebOS ($name) - PARTIAL: " . $hash->{PARTIAL} );

    return;
}

sub Handshake {
    my $hash = shift;

    my $name  = $hash->{NAME};
    my $host  = $hash->{HOST};
    my $wsKey = ::encode_base64( ::gettimeofday() );

    my $wsHandshakeCmd = "";
    $wsHandshakeCmd .= "GET / HTTP/1.1\r\n";
    $wsHandshakeCmd .= "Host: $host\r\n";
    $wsHandshakeCmd .= "User-Agent: FHEM\r\n";
    $wsHandshakeCmd .= "Upgrade: websocket\r\n";
    $wsHandshakeCmd .= "Connection: Upgrade\r\n";
    $wsHandshakeCmd .= "Sec-WebSocket-Version: 13\r\n";
    $wsHandshakeCmd .= "Sec-WebSocket-Key: " . $wsKey . "\r\n";

    Write( $hash, $wsHandshakeCmd );

    $hash->{helper}{wsKey} = $wsKey;

    ::Log3( $name, 4, "LGTV_WebOS ($name) - send Handshake to WriteFn" );

    TimerStatusRequest($hash);
    ::Log3( $name, 4, "LGTV_WebOS ($name) - start timer status request" );

    Pairing($hash);
    ::Log3( $name, 4, "LGTV_WebOS ($name) - start pairing routine" );

    return;
}

sub ResponseProcessing {
    my ( $hash, $response ) = @_;
    my $name = $hash->{NAME};

    ########################
    ### Response has HTML Header
    if ( $response =~ /HTTP\/1.1 101 Switching Protocols/x ) {

        my $data   = $response;
        my $header = Header2Hash($data);

        ################################
        ### Handshake for first Connect
        if ( exists( $header->{'Sec-WebSocket-Accept'} ) ) {

            my $keyAccept = $header->{'Sec-WebSocket-Accept'};
            ::Log3( $name, 5, "LGTV_WebOS ($name) - keyAccept: $keyAccept" );

            my $wsKey            = $hash->{helper}{wsKey};
            my $expectedResponse = trim(
                encode_base64(
                    pack(
                        'H*',
                        sha1_hex(
                            trim($wsKey)
                              . "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
                        )
                    )
                )
            );

            if ( $keyAccept eq $expectedResponse ) {

                ::Log3( $name, 3,
"LGTV_WebOS ($name) - Sucessfull WS connection to $hash->{HOST}"
                );
                ::readingsSingleUpdate( $hash, 'state', 'on', 1 );

            }
            else {
                Close($hash);

                ::Log3( $name, 3,
"LGTV_WebOS ($name) - ERROR: Unsucessfull WS connection to $hash->{HOST}"
                );
            }
        }

        return;
    }

    elsif ( $response =~ m/^{"type":".+}}$/x ) {

        return ::Log3( $name, 4,
            "LGTV_WebOS ($name) - garbage after JSON object" )
          if ( $response =~ m/^{"type":".+}}.+{"type":".+/x );

        ::Log3( $name, 4,
            "LGTV_WebOS ($name) - JSON detected, run LGTV_WebOS_WriteReadings"
        );

        my $json = $response;

        ::Log3( $name, 4, "LGTV_WebOS ($name) - Corrected JSON String: $json" )
          if ($json);

        if ( !defined($json) || !($json) ) {

            ::Log3( $name, 4,
                "LGTV_WebOS ($name) - Corrected JSON String empty" );
            return;
        }

        my $decode_json;
        try {
            $decode_json = decode_json( encode_utf8($json) );
        }
        catch {
            if ( $_->isa('autodie::exception') && $_->matches(':io') ) {
                Log3( $name, 3,
                    "LGTV_WebOS ($name) autodie - JSON error while request: $_"
                );
                return;
            }
            else {
                Log3( $name, 3,
                    "LGTV_WebOS ($name) - JSON error while request: $_" );
                return;
            }
        };    # Note semicolon.

        WriteReadings( $hash, $decode_json );

        return;
    }

    ::Log3( $name, 4, "LGTV_WebOS ($name) - no Match found" );

    return;
}

sub WriteServiceReadings {
    my $hash        = shift;
    my $decode_json = shift;

    for my $services ( @{ $decode_json->{payload}{services} } ) {
        ::readingsBulkUpdateIfChanged(
            $hash,
            'service_' . $services->{name},
            'v.' . $services->{version}
        );
    }

    return;
}

sub WriteDeviceReadings {
    my $hash        = shift;
    my $decode_json = shift;

    for my $devices ( @{ $decode_json->{payload}{devices} } ) {

        if (   !exists( $hash->{helper}{device}{inputs}{ $devices->{label} } )
            || !
            exists( $hash->{helper}{device}{inputapps}{ $devices->{appId} } ) )
        {

            $hash->{helper}{device}{inputs}
              { ::makeDeviceName( $devices->{label} ) } = $devices->{appId};
            $hash->{helper}{device}{inputapps}{ $devices->{appId} } =
              ::makeDeviceName( $devices->{label} );
        }

        ::readingsBulkUpdateIfChanged(
            $hash,
            'extInput_' . ::makeDeviceName( $devices->{label} ),
            'connect_' . $devices->{connected}
        );
    }

    return;
}

sub WriteProgramlistReadings {
    my $hash        = shift;
    my $decode_json = shift;

    require Date::Parse;
    my $count = 0;
    for my $programList ( @{ $decode_json->{payload}{programList} } ) {

        if (
            ::str2time( FormartStartEndTime( $programList->{localEndTime} ) ) >
            time() )
        {
            if ( $count < 1 ) {

                ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentTitle',
                    $programList->{programName} );
                ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentStartTime',
                    FormartStartEndTime( $programList->{localStartTime} ) );
                ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentEndTime',
                    FormartStartEndTime( $programList->{localEndTime} ) );

            }
            elsif ( $count < 2 ) {

                ::readingsBulkUpdateIfChanged( $hash, 'channelNextTitle',
                    $programList->{programName} );
                ::readingsBulkUpdateIfChanged( $hash, 'channelNextStartTime',
                    FormartStartEndTime( $programList->{localStartTime} ) );
                ::readingsBulkUpdateIfChanged( $hash, 'channelNextEndTime',
                    FormartStartEndTime( $programList->{localEndTime} ) );
            }

            $count++;
            return if ( $count > 1 );
        }
    }

    return;
}

sub WriteMuteReadings {
    my $hash        = shift;
    my $decode_json = shift;

    if (
        exists( $decode_json->{payload}{'mute'} )
        && (   $decode_json->{payload}{'mute'} eq 'true'
            || $decode_json->{payload}{'mute'} == 1 )
      )
    {

        ::readingsBulkUpdateIfChanged( $hash, 'mute', 'on' );

    }
    elsif ( exists( $decode_json->{payload}{'mute'} ) ) {
        if (   $decode_json->{payload}{'mute'} eq 'false'
            || $decode_json->{payload}{'mute'} == 0 )
        {

            ::readingsBulkUpdateIfChanged( $hash, 'mute', 'off' );
        }
    }

    if (
        exists( $decode_json->{payload}{'muted'} )
        && (   $decode_json->{payload}{'muted'} eq 'true'
            || $decode_json->{payload}{'muted'} == 1 )
      )
    {

        ::readingsBulkUpdateIfChanged( $hash, 'mute', 'on' );

    }
    elsif (
        exists( $decode_json->{payload}{'muted'} )
        && (   $decode_json->{payload}{'muted'} eq 'false'
            || $decode_json->{payload}{'muted'} == 0 )
      )
    {

        ::readingsBulkUpdateIfChanged( $hash, 'mute', 'off' );
    }

    return;
}

sub Write3dReadings {
    my $hash        = shift;
    my $decode_json = shift;

    if (   $decode_json->{payload}{status3D}{status} eq 'false'
        || $decode_json->{payload}{status3D}{status} == 0 )
    {

        ::readingsBulkUpdateIfChanged( $hash, '3D', 'off' );

    }
    elsif ($decode_json->{payload}{status3D}{status} eq 'true'
        || $decode_json->{payload}{status3D}{status} == 1 )
    {

        ::readingsBulkUpdateIfChanged( $hash, '3D', 'on' );
    }

    ::readingsBulkUpdateIfChanged( $hash, '3DMode',
        $decode_json->{payload}{status3D}{pattern} );

    return;
}

sub WriteAppIdReadings {
    my $hash        = shift;
    my $decode_json = shift;

    if (
        (
               $decode_json->{payload}{appId} =~ /com.webos.app.externalinput/x
            || $decode_json->{payload}{appId} =~ /com.webos.app.hdmi/x
        )
        && exists(
            $hash->{helper}{device}{inputapps}{ $decode_json->{payload}{appId} }
        )
        && $hash->{helper}{device}{inputapps}{ $decode_json->{payload}{appId} }
      )
    {

        ::readingsBulkUpdateIfChanged( $hash, 'input',
            $hash->{helper}{device}{inputapps}{ $decode_json->{payload}{appId} }
        );
        ::readingsBulkUpdateIfChanged( $hash, 'launchApp', '-' );

    }
    elsif ( exists( $openAppsPackageName{ $decode_json->{payload}{appId} } )
        && $openAppsPackageName{ $decode_json->{payload}{appId} } )
    {

        ::readingsBulkUpdateIfChanged( $hash, 'launchApp',
            $openAppsPackageName{ $decode_json->{payload}{appId} } );
        ::readingsBulkUpdateIfChanged( $hash, 'input', '-' );
    }

    return;
}

sub WriteTypeReadings {
    my $hash        = shift;
    my $decode_json = shift;

    my $response;

    if ( $decode_json->{type} eq 'registered'
        && exists( $decode_json->{payload}{'client-key'} ) )
    {

        $hash->{helper}{device}{registered} = 1;

    }
    elsif (
        (
            $decode_json->{type} eq 'response'
            && (   $decode_json->{payload}{returnValue} eq 'true'
                || $decode_json->{payload}{returnValue} == 1 )
        )
        || ( $decode_json->{type} eq 'registered' )
        && exists( $decode_json->{payload}{'client-key'} )
      )
    {

        $response = 'ok';
        ::readingsBulkUpdateIfChanged( $hash, 'pairing', 'paired' );
        $hash->{helper}{device}{runsetcmd} =
          $hash->{helper}{device}{runsetcmd} - 1
          if ( $hash->{helper}{device}{runsetcmd} > 0 );

    }
    elsif ( $decode_json->{type} eq 'error' ) {

        $response = "error - $decode_json->{error}"
          if ( $decode_json->{error} ne '404 no such service or method' );

        if (   $decode_json->{error} eq '401 insufficient permissions'
            || $decode_json->{error} eq
            '401 insufficient permissions (not registered)' )
        {

            ::readingsBulkUpdateIfChanged( $hash, 'pairing', 'unpaired' );
        }

        $hash->{helper}{device}{runsetcmd} =
          $hash->{helper}{device}{runsetcmd} - 1
          if ( $hash->{helper}{device}{runsetcmd} > 0 );
    }

    return $response;
}

sub WriteReadings {
    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};
    my $response;

    ::Log3( $name, 4, "LGTV_WebOS ($name) - Beginn Readings writing" );

    ::readingsBeginUpdate($hash);

    if ( ref( $decode_json->{payload}{services} ) eq "ARRAY"
        && scalar( @{ $decode_json->{payload}{services} } ) > 0 )
    {
        WriteServiceReadings( $hash, $decode_json );
    }
    elsif ( ref( $decode_json->{payload}{devices} ) eq "ARRAY"
        && scalar( @{ $decode_json->{payload}{devices} } ) > 0 )
    {
        WriteDeviceReadings( $hash, $decode_json );
    }
    elsif ( ref( $decode_json->{payload}{programList} ) eq "ARRAY"
        && scalar( @{ $decode_json->{payload}{programList} } ) > 0 )
    {
        WriteProgramlistReadings( $hash, $decode_json );
    }

    if (   exists( $decode_json->{payload}{'mute'} )
        || exists( $decode_json->{payload}{'muted'} ) )
    {
        WriteMuteReadings( $hash, $decode_json );
    }
    elsif ( exists( $decode_json->{payload}{status3D}{status} ) ) {
        Write3dReadings( $hash, $decode_json );
    }
    elsif ( exists( $decode_json->{payload}{appId} ) ) {
        WriteAppIdReadings( $hash, $decode_json );
    }

    if ( exists( $decode_json->{type} ) ) {
        $response = WriteTypeReadings( $hash, $decode_json );
    }

    ::readingsBulkUpdateIfChanged( $hash, 'lgKey',
        $decode_json->{payload}{'client-key'} )
      if ( exists( $decode_json->{payload}{'client-key'} ) );
    ::readingsBulkUpdateIfChanged( $hash, 'volume',
        $decode_json->{payload}{'volume'} )
      if ( exists( $decode_json->{payload}{'volume'} ) );
    ::readingsBulkUpdateIfChanged( $hash, 'lastResponse', $response )
      if ( defined($response) );

    if ( ::ReadingsVal( $name, 'launchApp', 'none' ) eq 'TV' ) {

        ::readingsBulkUpdateIfChanged( $hash, 'channel',
            $decode_json->{payload}{'channelNumber'} )
          if ( exists( $decode_json->{payload}{'channelNumber'} ) );
        ::readingsBulkUpdateIfChanged( $hash, 'channelName',
            $decode_json->{payload}{'channelName'} )
          if ( exists( $decode_json->{payload}{'channelName'} ) );
        ::readingsBulkUpdateIfChanged( $hash, 'channelMedia',
            $decode_json->{payload}{'channelTypeName'} )
          if ( exists( $decode_json->{payload}{'channelTypeName'} ) );

    }
    else {

        ::readingsBulkUpdateIfChanged( $hash, 'channelName',             '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channel',                 '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelMedia',            '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentTitle',     '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentStartTime', '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelCurrentEndTime',   '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelNextTitle',        '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelNextStartTime',    '-' );
        ::readingsBulkUpdateIfChanged( $hash, 'channelNextEndTime',      '-' );
    }

    ::readingsBulkUpdateIfChanged( $hash, 'state', 'on' );

    ::readingsEndUpdate( $hash, 1 );

    return;
}

sub Pairing {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::Log3( $name, 4, "LGTV_WebOS ($name) - HASH handshakePayload" );

    my %handshakePayload = (
        "pairingType" => "PROMPT",
        "manifest"    => {
            "manifestVersion" => 1,
            "appVersion"      => "1.1",
            "signed"          => {
                "created"           => "20161123",
                "appId"             => "com.lge.test",
                "vendorId"          => "com.lge",
                "localizedAppNames" => {
                    ""      => "FHEM LG Remote",
                    "de-DE" => "FHEM LG Fernbedienung"
                },
                "localizedVendorNames" => {
                    "" => "LG Electronics"
                },
                "permissions" => [
                    "TEST_SECURE",                "CONTROL_INPUT_TEXT",
                    "CONTROL_MOUSE_AND_KEYBOARD", "READ_INSTALLED_APPS",
                    "READ_LGE_SDX",               "READ_NOTIFICATIONS",
                    "SEARCH",                     "WRITE_SETTINGS",
                    "WRITE_NOTIFICATION_ALERT",   "CONTROL_POWER",
                    "READ_CURRENT_CHANNEL",       "READ_RUNNING_APPS",
                    "READ_UPDATE_INFO",           "UPDATE_FROM_REMOTE_APP",
                    "READ_LGE_TV_INPUT_EVENTS",   "READ_TV_CURRENT_TIME"
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
                    "signature" =>
"eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw=="
                }
            ]
        }
    );

    my $usedHandshake = \%handshakePayload;

    my $key = ::ReadingsVal( $name, 'lgKey', '' );

    $usedHandshake->{'client-key'} = $key if ( defined($key) );

    CreateSendCommand( $hash, undef, $usedHandshake, 'register' );
    ::Log3( $name, 4, "LGTV_WebOS ($name) - Send pairing informations" );

    return;
}

sub CreateSendCommand {
    my ( $hash, $uri, $payload, $type ) = @_;

    my $name = $hash->{NAME};

    $type = 'request' if ( !defined($type) );

    my $command = {};
    $command->{'client-key'} = ::ReadingsVal( $name, 'lgKey', '' )
      if ( $type ne 'register' );
    $command->{id}      = $type . "_" . ::gettimeofday();
    $command->{type}    = $type;
    $command->{uri}     = $uri if ($uri);
    $command->{payload} = $payload if ( defined($payload) );

#::Log3( $name, 5, "LGTV_WebOS ($name) - Payload Message: $command->{payload}{message}" );

    my $cmd;
    try {
        $cmd = encode_json($command);
    }
    catch {
        if ( $_->isa('autodie::exception') && $_->matches(':io') ) {
            Log3( $name, 3,
                "LGTV_WebOS ($name) - can't $cmd encode to json: $_" );
            return;
        }
        else {
            Log3( $name, 3,
                "LGTV_WebOS ($name) - can't $cmd encode to json: $_" );
            return;
        }
    };

    ::Log3( $name, 5, "LGTV_WebOS ($name) - Sending command: $cmd" );

    Write( $hash, Hybi10Encode( $cmd, "text", 1 ) );

    return;
}

sub Hybi10Encode {
    my $payload = shift;
    my $type    = shift // 'text';
    my $masked  = shift // 1;

    my @frameHead;
    my $frame         = "";
    my $payloadLength = length($payload);

    given ($type) {
        when ('text') {

            # first byte indicates FIN, Text-Frame (10000001):
            $frameHead[0] = 129;
        }
        when ('close') {

            # first byte indicates FIN, Close Frame(10001000):
            $frameHead[0] = 136;
        }
        when ('ping') {

            # first byte indicates FIN, Ping frame (10001001):
            $frameHead[0] = 137;
        }
        when ('pong') {

            # first byte indicates FIN, Pong frame (10001010):
            $frameHead[0] = 138;
        }
    }

    # set mask and payload length (using 1, 3 or 9 bytes)
    if ( $payloadLength > 65535 ) {

        # TODO
        my $payloadLengthBin = sprintf( '%064b', $payloadLength );
        $frameHead[1] = ($masked) ? 255 : 127;

        for ( my $i = 0 ; $i < 8 ; $i++ ) {

            $frameHead[ $i + 2 ] =
              oct( "0b" . substr( $payloadLengthBin, $i * 8, $i * 8 + 8 ) );
        }

        # most significant bit MUST be 0 (close connection if frame too big)
        if ( $frameHead[2] > 127 ) {

            #$this->close(1004);
            return;
        }

    }
    elsif ( $payloadLength > 125 ) {

        my $payloadLengthBin = sprintf( '%016b', $payloadLength );
        $frameHead[1] = ($masked) ? 254 : 126;
        $frameHead[2] = oct( "0b" . substr( $payloadLengthBin, 0, 8 ) );
        $frameHead[3] = oct( "0b" . substr( $payloadLengthBin, 8, 16 ) );

    }
    else {

        $frameHead[1] = ($masked) ? $payloadLength + 128 : $payloadLength;
    }

    # convert frame-head to string:
    for ( my $i = 0 ; $i < scalar(@frameHead) ; $i++ ) {

        $frameHead[$i] = chr( $frameHead[$i] );
    }

    my @mask;
    if ($masked) {

        # generate a random mask:
        for ( my $i = 0 ; $i < 4 ; $i++ ) {

            #$mask[$i] = chr(int(rand(255)));
            $mask[$i] = chr( int( 25 * $i ) );
        }

        @frameHead = ( @frameHead, @mask );
    }

    $frame = join( "", @frameHead );

    # append payload to frame:
    my $char;
    for ( my $i = 0 ; $i < $payloadLength ; $i++ ) {

        $char = substr( $payload, $i, 1 );
        $frame .= ($masked) ? $char ^ $mask[ $i % 4 ] : $char;
    }

    return $frame;
}

sub GetAudioStatus {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::Log3( $name, 4,
        "LGTV_WebOS ($name) - LGTV_WebOS_GetAudioStatus: "
          . $hash->{helper}{device}{runsetcmd} );
    CreateSendCommand( $hash, $lgCommands{getAudioStatus}, undef )
      if ( $hash->{helper}{device}{runsetcmd} == 0 );

    return;
}

sub GetCurrentChannel {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer( $hash,
        \&FHEM::Devices::LGTV::LGTVWebOS::GetCurrentChannel );
    ::Log3( $name, 4,
        "LGTV_WebOS ($name) - LGTV_WebOS_GetCurrentChannel: "
          . $hash->{helper}{device}{runsetcmd} );
    CreateSendCommand( $hash, $lgCommands{getCurrentChannel}, undef )
      if ( $hash->{helper}{device}{runsetcmd} == 0 );

    return;
}

sub GetForgroundAppInfo {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer( $hash,
        \&FHEM::Devices::LGTV::LGTVWebOS::GetForgroundAppInfo );
    ::Log3( $name, 4,
        "LGTV_WebOS ($name) - LGTV_WebOS_GetForgroundAppInfo: "
          . $hash->{helper}{device}{runsetcmd} );
    CreateSendCommand( $hash, $lgCommands{getForegroundAppInfo}, undef )
      if ( $hash->{helper}{device}{runsetcmd} == 0 );

    return;
}

sub GetExternalInputList {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer( $hash,
        \&FHEM::Devices::LGTV::LGTVWebOS::GetExternalInputList );
    ::Log3( $name, 4,
        "LGTV_WebOS ($name) - LGTV_WebOS_GetExternalInputList: "
          . $hash->{helper}{device}{runsetcmd} );
    CreateSendCommand( $hash, $lgCommands{getExternalInputList}, undef )
      if ( $hash->{helper}{device}{runsetcmd} == 0 );

    return;
}

sub Get3DStatus {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer( $hash,
        \&FHEM::Devices::LGTV::LGTVWebOS::Get3DStatus );
    ::Log3( $name, 4,
        "LGTV_WebOS ($name) - LGTV_WebOS_Get3DStatus: "
          . $hash->{helper}{device}{runsetcmd} );
    CreateSendCommand( $hash, $lgCommands{get3DStatus}, undef )
      if ( $hash->{helper}{device}{runsetcmd} == 0 );

    return;
}

sub GetChannelProgramInfo {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::Log3( $name, 4,
        "LGTV_WebOS ($name) - LGTV_WebOS_GetChannelProgramInfo: "
          . $hash->{helper}{device}{runsetcmd} );
    CreateSendCommand( $hash, $lgCommands{getChannelProgramInfo}, undef )
      if ( $hash->{helper}{device}{runsetcmd} == 0 );

    return;
}

#############################################
### my little Helper

sub ParseMsg {
    my $hash   = shift;
    my $buffer = shift;

    my $name      = $hash->{NAME};
    my $jsonopen  = 0;
    my $jsonclose = 0;
    my $msg       = '';
    my $tail      = '';

    if ($buffer) {
        for my $c ( split //, $buffer ) {
            if ( $jsonopen == $jsonclose && $jsonopen > 0 ) {
                $tail .= $c;
                ::Log3( $name, 5,
"LGTV_WebOS ($name) - $jsonopen == $jsonclose && $jsonopen > 0"
                );

            }
            elsif ( ( $jsonopen == $jsonclose ) && ( $c ne '{' ) ) {

                ::Log3( $name, 5,
                    "LGTV_WebOS ($name) - Garbage character before message: "
                      . $c );

            }
            else {

                if ( $c eq '{' ) {

                    $jsonopen++;

                }
                elsif ( $c eq '}' ) {

                    $jsonclose++;
                }

                $msg .= $c;
            }
        }

        if ( $jsonopen != $jsonclose ) {

            $tail = $msg;
            $msg  = '';
        }
    }

    ::Log3( $name, 5, "LGTV_WebOS ($name) - return msg: $msg and tail: $tail" );
    return ( $msg, $tail );
}

sub Header2Hash {
    my $string = shift;
    my %hash   = ();

    for my $line ( split( "\r\n", $string ) ) {
        my ( $key, $value ) = split( ": ", $line );
        next if ( !$value );

        $value =~ s/^ //x;
        $hash{$key} = $value;
    }

    return \%hash;
}

sub FormartStartEndTime {
    my $string = shift;

    my @timeArray = split( ',', $string );

    return
"$timeArray[0]-$timeArray[1]-$timeArray[2] $timeArray[3]:$timeArray[4]:$timeArray[5]";
}

############ Presence Erkennung Begin #################
sub Presence {
    my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{RUNNING_PID} = ::BlockingCall(
        'FHEM::Devices::LGTV::LGTVWebOS::PresenceRun',
        $name . '|' . $hash->{HOST},
        'FHEM::Devices::LGTV::LGTVWebOS::PresenceDone',
        5,
        'FHEM::Devices::LGTV::LGTVWebOS::PresenceAborted',
        $hash
    ) unless ( exists( $hash->{helper}{RUNNING_PID} ) );

    return;
}

sub PresenceRun {
    my $string = shift;
    my ( $name, $host ) = split( "\\|", $string );

    my $tmp;
    my $response;

    $tmp = qx(ping -c 3 -w 2 $host 2>&1);  ## no critic (Backtick operator used)

    if ( defined($tmp) && $tmp ne '' ) {

        chomp $tmp;
        ::Log3( $name, 4,
            "LGTV_WebOS ($name) - ping command returned with output:\n$tmp" );
        $response = $name . '|' . (
            $tmp =~
              /\d+ [Bb]ytes (from|von)/ ## no critic (Regular expression without "/x")
              && $tmp !~ /[Uu]nreachable/x
            ? 'present'
            : 'absent'
        );

    }
    else {

        $response = "$name|Could not execute ping command";
    }

    ::Log3( $name, 4,
        "sub PresenceRun ($name) - Sub finish, Call LGTV_WebOS_PresenceDone" );

    return $response;
}

sub PresenceDone {
    my $string = shift;

    my ( $name, $response ) = split( "\\|", $string );
    my $hash = $defs{$name};

    delete( $hash->{helper}{RUNNING_PID} );

    if ( exists( $hash->{helper}{DISABLED} ) ) {
        ::Log3( $name, 4,
            "sub PresenceDone ($name) - Helper is disabled. Stop processing" );

        return;
    }

    ::readingsSingleUpdate( $hash, 'presence', $response, 1 );

    SocketClosePresenceAbsent( $hash, $response );

    ::Log3( $name, 4, "sub PresenceDone ($name) - presence done" );

    return;
}

sub PresenceAborted {
    my $hash = shift;
    my $name = $hash->{NAME};

    delete( $hash->{helper}{RUNNING_PID} );
    ::readingsSingleUpdate( $hash, 'presence', 'pingPresence timedout', 1 );

    ::Log3( $name, 4,
"sub PresenceAborted ($name) - The BlockingCall Process terminated unexpectedly. Timedout!"
    );

    return;
}

sub SocketClosePresenceAbsent {

    my $hash     = shift;
    my $presence = shift;

    my $name = $hash->{NAME};

    Close($hash)
      if ( $presence eq 'absent' && !::IsDisabled($name) && $hash->{CD} )
      ;   # https://forum.fhem.de/index.php/topic,66671.msg694578.html#msg694578
     # Sobald pingPresence absent meldet und der Socket noch steht soll er geschlossen werden, da sonst FHEM nach 4-6 min für 10 min blockiert

    return;
}

sub WakeUp_Udp {
    my ( $hash, $mac_addr, $host, $port ) = @_;
    my $name = $hash->{NAME};

    $port = 9 if ( !defined $port || $port !~ /^\d+$/x );

    my $sock = IO::Socket::INET->new( Proto => 'udp' ) or warn "socket : $!\n";
    if ( !$sock ) {
        ::Log3( $name, 3, "sub WakeUp_Udp ($name) - Can't create WOL socket" );
        return 1;
    }

    my $ip_addr   = ::inet_aton($host);
    my $sock_addr = ::sockaddr_in( $port, $ip_addr );
    $mac_addr =~ s/://xg;
    my $packet =
      pack( 'C6H*', 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, $mac_addr x 16 );

    setsockopt( $sock, ::SOL_SOCKET, ::SO_BROADCAST, 1 )
      or warn "setsockopt : $!\n";
    send( $sock, $packet, 0, $sock_addr ) or warn "send : $!\n";
    close($sock);

    return 1;
}

####### Presence Erkennung Ende ############

1;

__END__

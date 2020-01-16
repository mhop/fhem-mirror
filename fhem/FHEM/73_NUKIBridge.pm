###############################################################################
#
# Developed with Kate
#
#  (c) 2016-2020 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
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

## Beispiel für Logausgabe
# https://forum.fhem.de/index.php/topic,55756.msg508412.html#msg508412

##
#

################################

package main;

use strict;
use warnings;

package FHEM::NUKIBridge;

use strict;
use warnings;
use HttpUtils;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw( decode_json encode_json );
    1;
};

if ($@) {
    $@ = undef;

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
    };

    if ($@) {
        $@ = undef;

        # In rare cases, Cpanel::JSON::XS may
        #   be installed but JSON|JSON::MaybeXS not ...
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        };

        if ($@) {
            $@ = undef;

            # In rare cases, JSON::XS may
            #   be installed but JSON not ...
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            };

            if ($@) {
                $@ = undef;

                # Fallback to built-in JSON which SHOULD
                #   be available since 5.014 ...
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                };

                if ($@) {
                    $@ = undef;

                    # Fallback to JSON::backportPP in really rare cases
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                }
            }
        }
    }
}

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          readingFnAttributes
          defs
          modules
          Log3
          CommandAttr
          AttrVal
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          InternalVal
          ReadingsVal
          RemoveInternalTimer
          HttpUtils_NonblockingGet
          asyncOutput
          data
          TimeNow
          devspec2array
          Dispatch)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      GetCheckBridgeAlive
      Initialize
      CGI
      BridgeCall
      )
);

my %bridgeType = (
    '1' => 'Hardware',
    '2' => 'Software'
);

my %lockActionsSmartLock = (
    'unlock'             => 1,
    'lock'               => 2,
    'unlatch'            => 3,
    'locknGo'            => 4,
    'locknGoWithUnlatch' => 5
);

my %lockActionsOpener = (
    'activateRto'              => 1,
    'deactivateRto'            => 2,
    'electricStrikeActuation'  => 3,
    'activateContinuousMode'   => 4,
    'deactivateContinuousMode' => 5
);

sub Initialize($) {
    my ($hash) = @_;

    # Provider
    $hash->{WriteFn}   = 'FHEM::NUKIBridge::Write';
    $hash->{Clients}   = ':NUKIDevice:';
    $hash->{MatchList} = { '1:NUKIDevice' => '^{.*}$' };

    my $webhookFWinstance =
      join( ",", devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') );

    # Consumer
    $hash->{SetFn}    = 'FHEM::NUKIBridge::Set';
    $hash->{GetFn}    = 'FHEM::NUKIBridge::Get';
    $hash->{DefFn}    = 'FHEM::NUKIBridge::Define';
    $hash->{UndefFn}  = 'FHEM::NUKIBridge::Undef';
    $hash->{NotifyFn} = 'FHEM::NUKIBridge::Notify';
    $hash->{AttrFn}   = 'FHEM::NUKIBridge::Attr';
    $hash->{AttrList} =
        'disable:1 '
      . 'webhookFWinstance:'
      . $webhookFWinstance . ' '
      . 'webhookHttpHostname '
      . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define($$) {
    my ( $hash, $def ) = @_;

    my @a = split( "[ \t][ \t]*", $def );

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return ('too few parameters: define <name> NUKIBridge <HOST> <TOKEN>')
      if ( @a != 4 );

    my $name  = $a[0];
    my $host  = $a[2];
    my $token = $a[3];
    my $port  = 8080;

    $hash->{HOST}                  = $host;
    $hash->{PORT}                  = $port;
    $hash->{TOKEN}                 = $token;
    $hash->{NOTIFYDEV}             = 'global,' . $name;
    $hash->{VERSION}               = version->parse($VERSION)->normal;
    $hash->{BRIDGEAPI}             = FHEM::Meta::Get( $hash, 'x_apiversion' );
    $hash->{helper}->{actionQueue} = [];
    $hash->{helper}->{iowrite}     = 0;
    my $infix = 'NUKIBridge';

    Log3( $name, 3,
"NUKIBridge ($name) - defined with host $host on port $port, Token $token"
    );

    CommandAttr( undef, $name . ' room NUKI' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    if ( addExtension( $name, 'NUKIBridge_CGI', $infix . "-" . $host ) ) {
        $hash->{fhem}{infix} = $infix;
    }

    $hash->{WEBHOOK_REGISTER} = "unregistered";

    readingsSingleUpdate( $hash, 'state', 'Initialized', 1 );

    RemoveInternalTimer($hash);

    $modules{NUKIBridge}{defptr}{ $hash->{HOST} } = $hash;

    return undef;
}

sub Undef($$) {
    my ( $hash, $arg ) = @_;

    my $host = $hash->{HOST};
    my $name = $hash->{NAME};

    if ( defined( $hash->{fhem}{infix} ) ) {
        removeExtension( $hash->{fhem}{infix} );
    }

    RemoveInternalTimer($hash);
    delete $modules{NUKIBridge}{defptr}{ $hash->{HOST} };

    return undef;
}

sub Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;

    my $hash = $defs{$name};
    my $orig = $attrVal;

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' and $attrVal == 1 ) {
            readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            Log3( $name, 3, "NUKIBridge ($name) - disabled" );
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3( $name, 3, "NUKIBridge ($name) - enabled" );
        }
    }

    if ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            Log3( $name, 3,
                "NUKIBridge ($name) - enable disabledForIntervals" );
            readingsSingleUpdate( $hash, 'state', 'Unknown', 1 );
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3( $name, 3,
                "NUKIBridge ($name) - delete disabledForIntervals" );
        }
    }

    ######################
    #### webhook #########

    return (
"Invalid value for attribute $attrName: can only by FQDN or IPv4 or IPv6 address"
      )
      if (  $attrVal
        and $attrName eq 'webhookHttpHostname'
        and $attrVal !~ /^([A-Za-z_.0-9]+\.[A-Za-z_.0-9]+)|[0-9:]+$/ );

    return (
"Invalid value for attribute $attrName: FHEMWEB instance $attrVal not existing"
      )
      if (  $attrVal
        and $attrName eq 'webhookFWinstance'
        and
        ( !defined( $defs{$attrVal} ) or $defs{$attrVal}{TYPE} ne 'FHEMWEB' ) );

    return (
        "Invalid value for attribute $attrName: needs to be an integer value")
      if ( $attrVal and $attrName eq 'webhookPort' and $attrVal !~ /^\d+$/ );

    if ( $attrName =~ /^webhook.*/ ) {

        my $webhookHttpHostname = (
              $attrName eq 'webhookHttpHostname'
            ? $attrVal
            : AttrVal( $name, 'webhookHttpHostname', '' )
        );
        my $webhookFWinstance = (
              $attrName eq 'webhookFWinstance'
            ? $attrVal
            : AttrVal( $name, 'webhookFWinstance', '' )
        );

        $hash->{WEBHOOK_URI} = '/'
          . AttrVal( $webhookFWinstance, 'webname', 'fhem' )
          . '/NUKIBridge' . '-'
          . $hash->{HOST};
        $hash->{WEBHOOK_PORT} = (
            $attrName eq 'webhookPort' ? $attrVal : AttrVal(
                $name, 'webhookPort',
                InternalVal( $webhookFWinstance, 'PORT', '' )
            )
        );

        $hash->{WEBHOOK_URL}     = '';
        $hash->{WEBHOOK_COUNTER} = 0;

        if ( $webhookHttpHostname ne '' and $hash->{WEBHOOK_PORT} ne '' ) {

            $hash->{WEBHOOK_URL} =
                'http://'
              . $webhookHttpHostname . ':'
              . $hash->{WEBHOOK_PORT}
              . $hash->{WEBHOOK_URI};
            my $url =
                'http://'
              . $webhookHttpHostname . ':'
              . $hash->{WEBHOOK_PORT}
              . $hash->{WEBHOOK_URI};

            Log3( $name, 3, "NUKIBridge ($name) - URL ist: $url" );
            Write( $hash, 'callback/add', $url, undef, undef )
              if ($init_done);
            $hash->{WEBHOOK_REGISTER} = 'sent';
        }
        else {
            $hash->{WEBHOOK_REGISTER} = 'incomplete_attributes';
        }
    }

    return undef;
}

sub Notify($$) {

    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};
    return if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    FirstRun($hash)
      if (
        (
            grep /^INITIALIZED$/,
            @{$events}
            or grep /^REREADCFG$/,
            @{$events}
            or grep /^MODIFIED.$name$/,
            @{$events}
            or grep /^DEFINED.$name$/,
            @{$events}
        )
        and $devname eq 'global'
        and $init_done
      );

    return;
}

sub addExtension($$$) {
    my ( $name, $func, $link ) = @_;

    my $url = '/' . $link;

    Log3( $name, 2,
        "NUKIBridge ($name) - Registering NUKIBridge for webhook URI $url ..."
    );

    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;

    return 1;
}

sub removeExtension($) {
    my ($link) = @_;

    my $url  = '/' . $link;
    my $name = $data{FWEXT}{$url}{deviceName};

    Log3( $name, 2,
        "NUKIBridge ($name) - Unregistering NUKIBridge for webhook URL $url..."
    );
    delete $data{FWEXT}{$url};
}

sub Set($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    my ( $arg, @params ) = @args;

    if ( lc($cmd) eq 'getdevicelist' ) {
        return 'usage: getDeviceList' if ( @args != 0 );

        Write( $hash, 'list', undef, undef, undef )
          if ( !IsDisabled($name) );
        return undef;
    }
    elsif ( $cmd eq 'info' ) {
        return 'usage: statusRequest' if ( @args != 0 );

        Write( $hash, 'info', undef, undef, undef )
          if ( !IsDisabled($name) );
        return undef;
    }
    elsif ( lc($cmd) eq 'fwupdate' ) {
        return 'usage: fwUpdate' if ( @args != 0 );

        Write( $hash, 'fwupdate', undef, undef, undef )
          if ( !IsDisabled($name) );
        return undef;
    }
    elsif ( $cmd eq 'reboot' ) {
        return 'usage: reboot' if ( @args != 0 );

        Write( $hash, 'reboot', undef, undef, undef )
          if ( !IsDisabled($name) );
        return undef;
    }
    elsif ( lc($cmd) eq 'clearlog' ) {
        return 'usage: clearLog' if ( @args != 0 );

        Write( $hash, 'clearlog', undef, undef, undef )
          if ( !IsDisabled($name) );
    }
    elsif ( lc($cmd) eq 'factoryreset' ) {
        return 'usage: clearLog' if ( @args != 0 );

        Write( $hash, 'factoryReset', undef, undef, undef )
          if ( !IsDisabled($name) );
    }
    elsif ( lc($cmd) eq 'callbackremove' ) {
        return 'usage: callbackRemove' if ( @args > 1 );

        my $id = ( @args > 0 ? join( ' ', @args ) : 0 );

        Write( $hash, 'callback/remove', $id, undef, undef )
          if ( !IsDisabled($name) );
    }
    else {
        my $list = '';
        $list .= 'info:noArg getDeviceList:noArg ';
        $list .= 'clearLog:noArg fwUpdate:noArg reboot:noArg factoryReset:noArg'
          if ( ReadingsVal( $name, 'bridgeType', 'Software' ) eq 'Hardware' );
        return ( 'Unknown argument ' . $cmd . ', choose one of ' . $list );
    }
}

sub Get($@) {
    my ( $hash, $name, $cmd, @args ) = @_;

    my ( $arg, @params ) = @args;

    if ( lc($cmd) eq 'logfile' ) {
        return 'usage: logFile' if ( @args != 0 );

        Write( $hash, 'log', undef, undef, undef );
    }
    elsif ( lc($cmd) eq 'callbacklist' ) {
        return 'usage: callbackList' if ( @args != 0 );

        Write( $hash, 'callback/list', undef, undef, undef );
    }
    else {
        my $list = '';
        $list .= 'callbackList:noArg ';
        $list .= 'logFile:noArg'
          if ( ReadingsVal( $name, 'bridgeType', 'Software' ) eq 'Hardware' );

        return 'Unknown argument ' . $cmd . ', choose one of ' . $list;
    }
}

sub GetCheckBridgeAlive($) {
    my ($hash) = @_;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    Log3( $name, 4, "NUKIBridge ($name) - GetCheckBridgeAlive" );

    if ( !IsDisabled($name)
        and $hash->{helper}->{iowrite} == 0 )
    {

        Write( $hash, 'info', undef, undef, undef );

        Log3( $name, 4, "NUKIBridge ($name) - run Write" );
    }

    InternalTimer( gettimeofday() + 30,
        'NUKIBridge_GetCheckBridgeAlive', $hash );

    Log3( $name, 4,
        "NUKIBridge ($name) - Call InternalTimer for GetCheckBridgeAlive" );
}

sub FirstRun($) {
    my ($hash) = @_;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    Write( $hash, 'list', undef, undef, undef )
      if ( !IsDisabled($name) );
    InternalTimer( gettimeofday() + 5,
        'NUKIBridge_GetCheckBridgeAlive', $hash );

    return undef;
}

sub Write($@) {
    my ( $hash, $endpoint, $param, $nukiId, $deviceType ) = @_;

    my $obj = {
        endpoint   => $endpoint,
        param      => $param,
        nukiId     => $nukiId,
        deviceType => $deviceType
    };

    $hash->{helper}->{lastDeviceAction} = $obj
      if (
        ( defined($param) and $param )
        or ( defined($nukiId)
            and $nukiId )
      );

    unshift( @{ $hash->{helper}->{actionQueue} }, $obj );

    BridgeCall($hash);
}

sub CreateUri($$) {
    my ( $hash, $obj ) = @_;

    my $name       = $hash->{NAME};
    my $host       = $hash->{HOST};
    my $port       = $hash->{PORT};
    my $token      = $hash->{TOKEN};
    my $endpoint   = $obj->{endpoint};
    my $param      = $obj->{param};
    my $nukiId     = $obj->{nukiId};
    my $deviceType = $obj->{deviceType};

    my $uri = 'http://' . $host . ':' . $port;
    $uri .= '/' . $endpoint if ( defined $endpoint );
    $uri .= '?token=' . $token if ( defined($token) );

    if (    defined($param)
        and defined($deviceType) )
    {
        $uri .= '&action=' . $lockActionsSmartLock{$param}
          if (  $endpoint ne 'callback/add'
            and $deviceType == 0 );

        $uri .= '&action=' . $lockActionsOpener{$param}
          if (  $endpoint ne 'callback/add'
            and $deviceType == 2 );
    }

    $uri .= '&id=' . $param
      if ( defined($param)
        and $endpoint eq 'callback/remove' );

    $uri .= '&url=' . $param
      if ( defined($param)
        and $endpoint eq 'callback/add' );

    $uri .= '&nukiId=' . $nukiId
      if ( defined($nukiId) );
    $uri .= '&deviceType=' . $deviceType
      if ( defined($deviceType) );

    Log3( $name, 4, "NUKIBridge ($name) - created uri: $uri" );
    return $uri;
}

sub BridgeCall($) {
    my $hash = shift;

    my $name     = $hash->{NAME};
    my $obj      = pop( @{ $hash->{helper}->{actionQueue} } );
    my $endpoint = $obj->{endpoint};
    my $nukiId   = $obj->{nukiId};

    if ( $hash->{helper}->{iowrite} == 0 ) {
        my $uri = CreateUri( $hash, $obj );

        if ( defined($uri) and $uri ) {
            $hash->{helper}->{iowrite} = 1;

            my $param = {
                url      => $uri,
                timeout  => 30,
                hash     => $hash,
                nukiId   => $nukiId,
                endpoint => $endpoint,
                header   => 'Accept: application/json',
                method   => 'GET',
                callback => \&Distribution,
            };

            $param->{cl} = $hash->{CL}
              if (
                (
                       $endpoint eq 'callback/list'
                    or $endpoint eq 'log'
                )
                and ref( $hash->{CL} ) eq 'HASH'
              );

            HttpUtils_NonblockingGet($param);
            Log3( $name, 4,
                "NUKIBridge ($name) - Send HTTP POST with URL $uri" );
        }
    }
    else {
        push( @{ $hash->{helper}->{actionQueue} }, $obj )
          if ( defined($endpoint)
            and $endpoint eq 'lockAction' );
    }
}

sub Distribution($$$) {
    my ( $param, $err, $json ) = @_;

    my $hash      = $param->{hash};
    my $doTrigger = $param->{doTrigger};
    my $name      = $hash->{NAME};
    my $host      = $hash->{HOST};

    my $dhash = $hash;

    $dhash = $modules{NUKIDevice}{defptr}{ $param->{'nukiId'} }
      unless ( not defined( $param->{'nukiId'} ) );

    my $dname = $dhash->{NAME};

    Log3( $name, 4, "NUKIBridge ($name) - Response JSON: $json" );
    Log3( $name, 4, "NUKIBridge ($name) - Response ERROR: $err" );
    Log3( $name, 4, "NUKIBridge ($name) - Response CODE: $param->{code}" )
      if ( defined( $param->{code} ) and ( $param->{code} ) );

    $hash->{helper}->{iowrite} = 0
      if ( $hash->{helper}->{iowrite} == 1 );

    readingsBeginUpdate($hash);

    if ( defined($err) ) {
        if ( $err ne '' ) {
            if ( $param->{endpoint} eq 'info' ) {
                readingsBulkUpdate( $hash, 'state', 'not connected' );
                Log3( $name, 5, "NUKIBridge ($name) - Bridge ist offline" );
            }

            readingsBulkUpdate( $hash, 'lastError', $err )
              if ( ReadingsVal( $name, 'state', 'not connected' ) eq
                'not connected' );

            Log3( $name, 4,
                "NUKIBridge ($name) - error while requesting: $err" );
            readingsEndUpdate( $hash, 1 );

            asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
              if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

            return $err;
        }
    }

    if (    ( $json eq '' or $json =~ /Unavailable/i )
        and exists( $param->{code} )
        and $param->{code} != 200 )
    {
        if ( $param->{code} == 503 and $json eq 'HTTP 503 Unavailable' ) {
            Log3( $name, 4,
"NUKIBridge ($name) - Response from Bridge: $param->{code}, $json"
            );
            readingsEndUpdate( $hash, 1 );

            if ( defined( $hash->{helper}->{lastDeviceAction} )
                and $hash->{helper}->{lastDeviceAction} )
            {
                push(
                    @{ $hash->{helper}->{actionQueue} },
                    $hash->{helper}->{lastDeviceAction}
                );

                InternalTimer( gettimeofday() + 1,
                    'NUKIBridge_BridgeCall', $hash );
            }

            asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
              if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

            return;
        }

        readingsBulkUpdate( $hash, 'lastError',
            'Internal error, ' . $param->{code} );
        Log3( $name, 4,
                "NUKIBridge ($name) - received http code "
              . $param->{code}
              . " without any data after requesting" );

        readingsEndUpdate( $hash, 1 );
        return ('received http code '
              . $param->{code}
              . ' without any data after requesting' );

        asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
          if ( $param->{cl} && $param->{cl}{canAsyncOutput} );
    }

    if ( ( $json =~ /Error/i ) and exists( $param->{code} ) ) {

        readingsBulkUpdate( $hash, 'lastError', 'invalid API token' )
          if ( $param->{code} == 401 );
        readingsBulkUpdate( $hash, 'lastError', 'action is undefined' )
          if ( $param->{code} == 400 and $hash == $dhash );

        Log3( $name, 4, "NUKIBridge ($name) - invalid API token" )
          if ( $param->{code} == 401 );
        Log3( $name, 4, "NUKIBridge ($name) - nukiId is not known" )
          if ( $param->{code} == 404 );
        Log3( $name, 4, "NUKIBridge ($name) - action is undefined" )
          if ( $param->{code} == 400 and $hash == $dhash );

        readingsEndUpdate( $hash, 1 );

        asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
          if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

        return $param->{code};
    }

    delete $hash->{helper}->{lastDeviceAction}
      if ( defined( $hash->{helper}->{lastDeviceAction} )
        and $hash->{helper}->{lastDeviceAction} );

    readingsEndUpdate( $hash, 1 );

    readingsSingleUpdate( $hash, 'state', 'connected', 1 );
    Log3( $name, 5, "NUKIBridge ($name) - Bridge ist online" );

    if ( $param->{endpoint} eq 'callback/list' ) {
        getCallbackList( $param, $json );
        return undef;
    }
    elsif ( $param->{endpoint} eq 'log' ) {
        getLogfile( $param, $json );
        return undef;
    }

    if ( $hash == $dhash ) {
        ResponseProcessing( $hash, $json, $param->{endpoint} );
    }
    else {
        my $decode_json = eval { decode_json($json) };
        if ($@) {
            Log3( $name, 3,
                "NUKIBridge ($name) - JSON error while request: $@" );
            return;
        }

        $decode_json->{nukiId} = $param->{nukiId};
        $json = encode_json($decode_json);
        Dispatch( $hash, $json, undef );
    }

    InternalTimer( gettimeofday() + 3, 'NUKIBridge_BridgeCall', $hash )
      if ( defined( $hash->{helper}->{actionQueue} )
        and scalar( @{ $hash->{helper}->{actionQueue} } ) > 0 );

    return undef;
}

sub ResponseProcessing($$$) {
    my ( $hash, $json, $endpoint ) = @_;

    my $name = $hash->{NAME};
    my $decode_json;

    if ( !$json ) {
        Log3( $name, 3, "NUKIBridge ($name) - empty answer received" );
        return undef;
    }
    elsif ( $json =~ m'HTTP/1.1 200 OK' ) {
        Log3( $name, 4, "NUKIBridge ($name) - empty answer received" );
        return undef;
    }
    elsif ( $json !~ m/^[\[{].*[}\]]$/ ) {
        Log3( $name, 3, "NUKIBridge ($name) - invalid json detected: $json" );
        return ("NUKIBridge ($name) - invalid json detected: $json");
    }

    $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    if (   $endpoint eq 'list'
        or $endpoint eq 'info' )
    {
        if (
            (
                    ref($decode_json) eq 'ARRAY'
                and scalar( @{$decode_json} ) > 0
                and $endpoint eq 'list'
            )
            or (    ref($decode_json) eq 'HASH'
                and ref( $decode_json->{scanResults} ) eq 'ARRAY'
                and scalar( @{ $decode_json->{scanResults} } ) > 0
                and $endpoint eq 'info' )
          )
        {
            my @buffer;
            @buffer = split( '\[', $json )
              if ( $endpoint eq 'list' );
            @buffer = split( '"scanResults": \[', $json )
              if ( $endpoint eq 'info' );

            my ( $json, $tail ) = ParseJSON( $hash, $buffer[1] );

            while ($json) {
                Log3( $name, 5,
                        "NUKIBridge ($name) - Decoding JSON message. Length: "
                      . length($json)
                      . " Content: "
                      . $json );

                Log3( $name, 5,
                        "NUKIBridge ($name) - Vor Sub: Laenge JSON: "
                      . length($json)
                      . " Content: "
                      . $json
                      . " Tail: "
                      . $tail );

                Dispatch( $hash, $json, undef )
                  unless ( not defined($tail) and not($tail) );

                ( $json, $tail ) = ParseJSON( $hash, $tail );

                Log3( $name, 5,
                        "NUKIBridge ($name) - Nach Sub: Laenge JSON: "
                      . length($json)
                      . " Content: "
                      . $json
                      . " Tail: "
                      . $tail );
            }
        }

        InfoProcessing( $hash, $decode_json )
          if ( $endpoint eq 'info' );
    }
    else {
        Log3(
            $name, 5, "NUKIBridge ($name) - Rückgabe Path nicht korrekt: 
$json"
        );
        return;
    }

    return undef;
}

sub CGI() {
    my ($request) = @_;

    my $hash;
    my $name;
    while ( my ( $key, $value ) = each %{ $modules{NUKIBridge}{defptr} } ) {
        $hash = $modules{NUKIBridge}{defptr}{$key};
        $name = $hash->{NAME};
    }

    return ('NUKIBridge WEBHOOK - No IODev found')
      unless ( defined($hash) and defined($name) );

    my $json = ( split( '&', $request, 2 ) )[1];

    if ( !$json ) {
        Log3( $name, 3, "NUKIBridge WEBHOOK ($name) - empty message received" );
        return undef;
    }
    elsif ( $json =~ m'HTTP/1.1 200 OK' ) {
        Log3( $name, 4, "NUKIBridge WEBHOOK ($name) - empty answer received" );
        return undef;
    }
    elsif ( $json !~ m/^[\[{].*[}\]]$/ ) {
        Log3( $name, 3,
            "NUKIBridge WEBHOOK ($name) - invalid json detected: $json" );
        return ("NUKIBridge WEBHOOK ($name) - invalid json detected: $json");
    }

    Log3( $name, 5,
        "NUKIBridge WEBHOOK ($name) - Webhook received with JSON: $json" );

    if ( $json =~ m/^\{.*\}$/ ) {
        $hash->{WEBHOOK_COUNTER}++;
        $hash->{WEBHOOK_LAST} = TimeNow();

        Log3(
            $name, 4, "NUKIBridge WEBHOOK ($name) - Received webhook for 
matching NukiId at device $name"
        );

        Dispatch( $hash, $json, undef );

        return ( undef, undef );
    }

    # no data received
    else {
        Log3( $name, 4,
            "NUKIBridge WEBHOOK - received malformed request\n$request" );
    }

    return ( 'text/plain; charset=utf-8', 'Call failure: ' . $request );
}

sub InfoProcessing($$) {
    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};

    my $nukiId;
    my $scanResults;
    my %response_hash;
    my $dname;
    my $dhash;

    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, 'appVersion',
        $decode_json->{versions}->{appVersion} );
    readingsBulkUpdate( $hash, 'firmwareVersion',
        $decode_json->{versions}->{firmwareVersion} );
    readingsBulkUpdate( $hash, 'wifiFirmwareVersion',
        $decode_json->{versions}->{wifiFirmwareVersion} );
    readingsBulkUpdate( $hash, 'bridgeType',
        $bridgeType{ $decode_json->{bridgeType} } );
    readingsBulkUpdate( $hash, 'hardwareId',  $decode_json->{ids}{hardwareId} );
    readingsBulkUpdate( $hash, 'serverId',    $decode_json->{ids}{serverId} );
    readingsBulkUpdate( $hash, 'uptime',      $decode_json->{uptime} );
    readingsBulkUpdate( $hash, 'currentTime', $decode_json->{currentTime} );
    readingsBulkUpdate( $hash, 'serverConnected',
        $decode_json->{serverConnected} );
    readingsEndUpdate( $hash, 1 );
}

sub getLogfile($$) {
    my ( $param, $json ) = @_;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    Log3( $name, 4,
        "NUKIBridge ($name) - Log data are collected and processed" );

    if ( $param->{cl} and $param->{cl}->{TYPE} eq 'FHEMWEB' ) {
        if ( ref($decode_json) eq 'ARRAY' and scalar( @{$decode_json} ) > 0 ) {
            Log3( $name, 4,
                "NUKIBridge ($name) - created Table with log file" );

            my $header = '<html>'
                . '<div style="float: left">Log List</div>';

            my $ret = $header.'<table width=100%><tr><td>';
            $ret .= '<table class="block wide">';

            foreach my $logs ( @{$decode_json} ) {
                $ret .= '<tr class="odd">';

                if ( $logs->{timestamp} ) {
                    $ret .= '<td><b>timestamp:</b> </td>';
                    $ret .= '<td>' . $logs->{timestamp} . '</td>';
                    $ret .= '<td> </td>';
                }

                if ( $logs->{type} ) {
                    $ret .= '<td><b>type:</b> </td>';
                    $ret .= '<td>' . $logs->{type} . '</td>';
                    $ret .= '<td> </td>';
                }

                foreach my $d ( reverse sort keys %{$logs} ) {
                    next if ( $d eq 'type' );
                    next if ( $d eq 'timestamp' );

                    $ret .= '<td><b>' . $d . ':</b> </td>';
                    $ret .= '<td>' . $logs->{$d} . '</td>';
                    $ret .= '<td> </td>';
                }

                $ret .= '</tr>';
            }

            $ret .= '</table></td></tr>';
            $ret .= '</table></html>';

            asyncOutput( $param->{cl}, $ret )
              if ( $param->{cl} and $param->{cl}{canAsyncOutput} );
            return;
        }
    }
}

sub getCallbackList($$) {
    my ( $param, $json ) = @_;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    Log3( $name, 4,
        "NUKIBridge ($name) - Callback data are collected and processed" );

    if ( $param->{cl} and $param->{cl}->{TYPE} eq 'FHEMWEB' ) {
        if ( ref( $decode_json->{callbacks} ) eq 'ARRAY' ) {
            Log3( $name, 4,
                "NUKIBridge ($name) - created Table with log file" );

            my $space = '&nbsp;';
            my $aHref;
            my $header = '<html>'
                . '<div style="float: left">Callback List</div>';

            my $ret = $header.'<table width=100%><tr><td>';
            $ret .= '<table class="block wide">';
            $ret .= '<tr class="odd">';
            $ret .= '<td><b>URL</b></td>';
            $ret .= '<td><b>Remove</b></td>';
            $ret .= '</tr>';

            if ( scalar( @{ $decode_json->{callbacks} } ) > 0 ) {
                foreach my $cb ( @{ $decode_json->{callbacks} } ) {
                    $aHref =
                        "<a href=\""
                    . $::FW_httpheader->{host}
                    . "/fhem?cmd=set+"
                    . $name
                    . "+callbackRemove+"
                    . $cb->{id}
                    . $::FW_CSRF
                    . "\"><font color=\"red\"><b>X</b></font></a>";

                    $ret .= '<td>' . $cb->{url} . '</td>';
                    $ret .= '<td>'.$aHref.'</td>';
                    $ret .= '</tr>';
                }
            }
            else {
                $ret .= '<td>none</td>';
                $ret .= '<td>none</td>';
                $ret .= '<td> </td>';
                $ret .= '</tr>';
            }

            $ret .= '</table></td></tr>';
            $ret .= '</table></html>';

            asyncOutput( $param->{cl}, $ret )
              if ( $param->{cl} and $param->{cl}{canAsyncOutput} );
            return;
        }
    }
}

sub ParseJSON($$) {
    my ( $hash, $buffer ) = @_;

    my $name  = $hash->{NAME};
    my $open  = 0;
    my $close = 0;
    my $msg   = '';
    my $tail  = '';

    if ($buffer) {
        foreach my $c ( split //, $buffer ) {
            if ( $open == $close and $open > 0 ) {
                $tail .= $c;
                Log3( $name, 5,
                    "NUKIBridge ($name) - $open == $close and $open > 0" );

            }
            elsif ( ( $open == $close ) and ( $c ne '{' ) ) {

                Log3( $name, 5,
                    "NUKIBridge ($name) - Garbage character before message: "
                      . $c );

            }
            else {

                if ( $c eq '{' ) {

                    $open++;

                }
                elsif ( $c eq '}' ) {

                    $close++;
                }

                $msg .= $c;
            }
        }

        if ( $open != $close ) {

            $tail = $msg;
            $msg  = '';
        }
    }

    Log3( $name, 5, "NUKIBridge ($name) - return msg: $msg and tail: $tail" );
    return ( $msg, $tail );
}

1;

=pod
=item device
=item summary    Modul to control the Nuki Smartlock's over the Nuki Bridge.
=item summary_DE Modul zur Steuerung des Nuki Smartlock über die Nuki Bridge.

=begin html

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - controls the Nuki Smartlock over the Nuki Bridge</b></u>
  <br>
  The Nuki Bridge module connects FHEM to the Nuki Bridge and then reads all the smartlocks available on the bridge. Furthermore, the detected Smartlocks are automatically created as independent devices.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    This statement creates a NUKIBridge device with the name NBridge1 and the IP 192.168.0.23 as well as the token F34HK6.<br>
    After the bridge device is created, all available Smartlocks are automatically placed in FHEM.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>bridgeAPI - API Version of bridge</li>
    <li>bridgeType - Hardware bridge / Software bridge</li>
    <li>currentTime - Current timestamp</li>
    <li>firmwareVersion - Version of the bridge firmware</li>
    <li>hardwareId - Hardware ID</li>
    <li>lastError - Last connected error</li>
    <li>serverConnected - Flag indicating whether or not the bridge is connected to the Nuki server</li>
    <li>serverId - Server ID</li>
    <li>uptime - Uptime of the bridge in seconds</li>
    <li>wifiFirmwareVersion- Version of the WiFi modules firmware</li>
    <br>
    The preceding number is continuous, starts with 0 und returns the properties of <b>one</b> Smartlock.
   </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>getDeviceList - Prompts to re-read all devices from the bridge and if not already present in FHEM, create the automatically.</li>
    <li>callbackRemove -  Removes a previously added callback</li>
    <li>clearLog - Clears the log of the Bridge (only hardwarebridge)</li>
    <li>factoryReset - Performs a factory reset (only hardwarebridge)</li>
    <li>fwUpdate -  Immediately checks for a new firmware update and installs it (only hardwarebridge)</li>
    <li>info -  Returns all Smart Locks in range and some device information of the bridge itself</li>
    <li>reboot - reboots the bridge (only hardwarebridge)</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeget"></a>
  <b>Get</b>
  <ul>
    <li>callbackList - List of register url callbacks.</li>
    <li>logFile - Retrieves the log of the Bridge</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki Bridge</li>
    <li>webhookFWinstance - Webinstanz of the Callback</li>
    <li>webhookHttpHostname - IP or FQDN of the FHEM Server Callback</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - Steuert das Nuki Smartlock über die Nuki Bridge</b></u>
  <br>
  Das Nuki Bridge Modul verbindet FHEM mit der Nuki Bridge und liest dann alle auf der Bridge verf&uuml;gbaren Smartlocks ein. Desweiteren werden automatisch die erkannten Smartlocks als eigenst&auml;ndige Devices an gelegt.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIBridge Device mit Namen NBridge1 und der IP 192.168.0.23 sowie dem Token F34HK6.<br>
    Nach dem anlegen des Bridge Devices werden alle zur verf&uuml;gung stehende Smartlock automatisch in FHEM an gelegt.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>bridgeAPI - API Version der Bridge</li>
    <li>bridgeType - Hardware oder Software/App Bridge</li>
    <li>currentTime - aktuelle Zeit auf der Bridge zum zeitpunkt des Info holens</li>
    <li>firmwareVersion - aktuell auf der Bridge verwendete Firmwareversion</li>
    <li>hardwareId - ID der Hardware Bridge</li>
    <li>lastError - gibt die letzte HTTP Errormeldung wieder</li>
    <li>serverConnected - true/false gibt an ob die Hardwarebridge Verbindung zur Nuki-Cloude hat.</li>
    <li>serverId - gibt die ID des Cloudeservers wieder</li>
    <li>uptime - Uptime der Bridge in Sekunden</li>
    <li>wifiFirmwareVersion- Firmwareversion des Wifi Modules der Bridge</li>
    <br>
    Die vorangestellte Zahl ist forlaufend und gibt beginnend bei 0 die Eigenschaften <b>Eines</b> Smartlocks wieder.
  </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>getDeviceList - Veranlasst ein erneutes Einlesen aller Devices von der Bridge und falls noch nicht in FHEM vorhanden das automatische anlegen.</li>
    <li>callbackRemove - L&ouml;schen der Callback Instanz auf der Bridge.</li>
    <li>clearLog - l&ouml;scht das Logfile auf der Bridge</li>
    <li>fwUpdate - schaut nach einer neueren Firmware und installiert diese sofern vorhanden</li>
    <li>info - holt aktuellen Informationen &uuml;ber die Bridge</li>
    <li>reboot - veranl&auml;sst ein reboot der Bridge</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeget"></a>
  <b>Get</b>
  <ul>
    <li>callbackList - Gibt die Liste der eingetragenen Callback URL's wieder.</li>
    <li>logFile - Zeigt das Logfile der Bridge an</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert die Nuki Bridge</li>
    <li>webhookFWinstance - zu verwendene Webinstanz für den Callbackaufruf</li>
    <li>webhookHttpHostname - IP oder FQDN vom FHEM Server für den Callbackaufruf</li>
    <br>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 73_NUKIBridge.pm
{
  "abstract": "Modul to control the Nuki Smartlock's over the Nuki Bridge",
  "x_lang": {
    "de": {
      "abstract": "Modul to control the Nuki Smartlock's over the Nuki Bridge"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Smartlock",
    "Nuki",
    "Control"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v1.9.16",
  "x_apiversion": "1.9",
  "author": [
    "Marko Oldenburg <leongaultier@gmail.com>"
  ],
  "x_fhem_maintainer": [
    "CoolTux"
  ],
  "x_fhem_maintainer_github": [
    "LeonGaultier"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 0,
        "JSON": 0,
        "Date::Parse": 0
      },
      "recommends": {
      },
      "suggests": {
      }
    }
  }
}
=end :application/json;q=META.json

=cut

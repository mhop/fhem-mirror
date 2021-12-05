###############################################################################
#
# Developed with Kate
#
#  (c) 2016-2021 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
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
package FHEM::Devices::Nuki::Bridge;

use strict;
use warnings;

use FHEM::Meta;
use HttpUtils;

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

######## Begin Bridge

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

sub Define {
    my $hash = shift;
    my $def  = shift // return;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    my ( $name, undef, $host, $token ) = split( m{\s+}xms, $def );

    my $port  = ::AttrVal( $name, 'port', 8080 );
    my $infix = 'NUKIBridge';
    $hash->{HOST}                  = $host // 'discover';
    $hash->{PORT}                  = $port;
    $hash->{TOKEN}                 = $token // 'discover';
    $hash->{NOTIFYDEV}             = 'global,' . $name;
    $hash->{VERSION}               = version->parse($VERSION)->normal;
    $hash->{BRIDGEAPI}             = FHEM::Meta::Get( $hash, 'x_apiversion' );
    $hash->{helper}->{actionQueue} = [];
    $hash->{helper}->{iowrite}     = 0;

    ::CommandAttr( undef, $name . ' room NUKI' )
      if ( ::AttrVal( $name, 'room', 'none' ) eq 'none' );

    $hash->{WEBHOOK_REGISTER} = "unregistered";

    ::readingsSingleUpdate( $hash, 'state', 'Initialized', 1 );

    ::RemoveInternalTimer($hash);

    return BridgeDiscover( $hash, 'discover' )
      if ( $hash->{HOST} eq 'discover'
        && $hash->{TOKEN} eq 'discover' );

    ::Log3( $name, 3,
"NUKIBridge ($name) - defined with host $host on port $port, Token $token"
    );

    if (
        addExtension(
            $name,
            \&FHEM::Devices::Nuki::Bridge::CGI,
            $infix . "-" . $host
        )
      )
    {
        $hash->{fhem}{infix} = $infix;
    }

    $::modules{NUKIBridge}{defptr}{ $hash->{HOST} } = $hash;

    return;
}

sub Undef {
    my $hash = shift;

    my $host = $hash->{HOST};
    my $name = $hash->{NAME};

    if ( defined( $hash->{fhem}{infix} ) ) {
        removeExtension( $hash->{fhem}{infix} );
    }

    ::RemoveInternalTimer($hash);
    delete $::modules{NUKIBridge}{defptr}{ $hash->{HOST} };

    return;
}

sub Attr {
    my $cmd      = shift;
    my $name     = shift;
    my $attrName = shift;
    my $attrVal  = shift;

    my $hash = $::defs{$name};
    my $orig = $attrVal;

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' && $attrVal == 1 ) {
            ::readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            ::Log3( $name, 3, "NUKIBridge ($name) - disabled" );
        }
        elsif ( $cmd eq 'del' ) {
            ::readingsSingleUpdate( $hash, 'state', 'active', 1 );
            ::Log3( $name, 3, "NUKIBridge ($name) - enabled" );
        }
    }

    if ( $attrName eq 'port' ) {
        if ( $cmd eq 'set' ) {
            $hash->{PORT} = $attrVal;
            ::Log3( $name, 3, "NUKIBridge ($name) - change bridge port" );
        }
        elsif ( $cmd eq 'del' ) {
            $hash->{PORT} = 8080;
            ::Log3( $name, 3,
                "NUKIBridge ($name) - set bridge port to default" );
        }
    }

    if ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            ::Log3( $name, 3,
                "NUKIBridge ($name) - enable disabledForIntervals" );
            ::readingsSingleUpdate( $hash, 'state', 'Unknown', 1 );
        }
        elsif ( $cmd eq 'del' ) {
            ::readingsSingleUpdate( $hash, 'state', 'active', 1 );
            ::Log3( $name, 3,
                "NUKIBridge ($name) - delete disabledForIntervals" );
        }
    }

    ######################
    #### webhook #########

    return (
"Invalid value for attribute $attrName: can only by FQDN or IPv4 or IPv6 address"
      )
      if ( $attrVal
        && $attrName eq 'webhookHttpHostname'
        && $attrVal !~ /^([A-Za-z_.0-9]+\.[A-Za-z_.0-9]+)|[0-9:]+$/ );

    return (
"Invalid value for attribute $attrName: FHEMWEB instance $attrVal not existing"
      )
      if (
           $attrVal
        && $attrName eq 'webhookFWinstance'
        && ( !defined( $::defs{$attrVal} )
            || $::defs{$attrVal}{TYPE} ne 'FHEMWEB' )
      );

    return (
        "Invalid value for attribute $attrName: needs to be an integer value")
      if ( $attrVal
        && $attrName eq 'webhookPort'
        && $attrVal !~ /^\d+$/ );

    if ( $attrName =~ /^webhook.*/ ) {

        my $webhookHttpHostname = (
              $attrName eq 'webhookHttpHostname' && defined($attrVal)
            ? $attrVal
            : ::AttrVal( $name, 'webhookHttpHostname', '' )
        );

        my $webhookFWinstance = (
              $attrName eq 'webhookFWinstance' && defined($attrVal)
            ? $attrVal
            : ::AttrVal( $name, 'webhookFWinstance', '' )
        );

        $hash->{WEBHOOK_URI} = '/'
          . ::AttrVal( $webhookFWinstance, 'webname', 'fhem' )
          . '/NUKIBridge' . '-'
          . $hash->{HOST};
        $hash->{WEBHOOK_PORT} = (
            $attrName eq 'webhookPort' ? $attrVal : ::AttrVal(
                $name, 'webhookPort',
                ::InternalVal( $webhookFWinstance, 'PORT', '' )
            )
        );

        $hash->{WEBHOOK_URL}     = '';
        $hash->{WEBHOOK_COUNTER} = 0;

        if ( $webhookHttpHostname ne '' && $hash->{WEBHOOK_PORT} ne '' ) {

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

            ::Log3( $name, 3, "NUKIBridge ($name) - URL ist: $url" );

            #             Write( $hash, 'callback/add', $url, undef, undef )
            Write( $hash, 'callback/add', '{"param":"' . $url . '"}' )
              if ($::init_done);
            $hash->{WEBHOOK_REGISTER} = 'sent';
        }
        else {
            $hash->{WEBHOOK_REGISTER} = 'incomplete_attributes';
        }
    }

    return;
}

sub Notify {

    my $hash = shift;
    my $dev  = shift // return;
    my $name = $hash->{NAME};

    return if ( ::IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = ::deviceEvents( $dev, 1 );
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
        && $hash->{HOST} ne 'discover'
        && $hash->{TOKEN} ne 'discover'
        && $devname eq 'global'
        && $::init_done
      );

    return;
}

sub addExtension {
    my $name = shift;
    my $func = shift;
    my $link = shift;

    my $url = '/' . $link;

    ::Log3( $name, 2,
        "NUKIBridge ($name) - Registering NUKIBridge for webhook URI $url ..."
    );

    $::data{FWEXT}{$url}{deviceName} = $name;
    $::data{FWEXT}{$url}{FUNC}       = $func;
    $::data{FWEXT}{$url}{LINK}       = $link;

    return 1;
}

sub removeExtension {
    my $link = shift;

    my $url  = '/' . $link;
    my $name = $::data{FWEXT}{$url}{deviceName};

    ::Log3( $name, 2,
        "NUKIBridge ($name) - Unregistering NUKIBridge for webhook URL $url..."
    ) if ( defined($name) );

    delete $::data{FWEXT}{$url};

    return;
}

sub Set {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "set $name needs at least one argument !";
    my $arg  = shift // '';

    my $endpoint;
    my $param;

    if ( lc($cmd) eq 'getdevicelist' ) {
        return 'usage: getDeviceList' if ($arg);
        $endpoint = 'list';
    }
    elsif ( $cmd eq 'info' ) {
        $endpoint = 'info';
    }
    elsif ( lc($cmd) eq 'fwupdate' ) {
        $endpoint = 'fwupdate';
    }
    elsif ( $cmd eq 'reboot' ) {
        return 'usage: reboot' if ( defined($arg) );

        $endpoint = 'reboot';
    }
    elsif ( lc($cmd) eq 'clearlog' ) {
        return 'usage: clearLog' if ( defined($arg) );

        $endpoint = 'clearlog';
    }
    elsif ( lc($cmd) eq 'factoryreset' ) {
        return 'usage: clearLog' if ( defined($arg) );

        $endpoint = 'factoryReset';
    }
    elsif ( lc($cmd) eq 'callbackremove' ) {
        return 'usage: callbackRemove' if ( split( m{\s+}xms, $arg ) > 1 );

        my $id = ( defined($arg) ? $arg : 0 );
        $endpoint = 'callback/remove';
        $param    = '{"param":"' . $id . '"}';
    }
    elsif ( lc($cmd) eq 'configauth' ) {
        return 'usage: configAuth' if ( split( m{\s+}xms, $arg ) > 1 );

        my $configAuth = 'enable=' . ( $arg eq 'enable' ? 1 : 0 );
        $endpoint = 'configAuth';
        $param    = '{"param":"' . $configAuth . '"}';
    }
    else {
        my $list = '';
        $list .= 'info:noArg getDeviceList:noArg ';
        $list .=
'clearLog:noArg fwUpdate:noArg reboot:noArg factoryReset:noArg configAuth:enable,disable'
          if ( ::ReadingsVal( $name, 'bridgeType', 'Software' ) eq 'Hardware' );
        return ( 'Unknown argument ' . $cmd . ', choose one of ' . $list );
    }

    Write( $hash, $endpoint, $param )
      if ( !::IsDisabled($name) );

    return;
}

sub Get {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "set $name needs at least one argument !";
    my $arg  = shift;

    my $endpoint;

    if ( lc($cmd) eq 'logfile' ) {
        return 'usage: logFile' if ( defined($arg) );

        $endpoint = 'log';
    }
    elsif ( lc($cmd) eq 'callbacklist' ) {
        return 'usage: callbackList' if ( defined($arg) );

        $endpoint = 'callback/list';
    }
    else {
        my $list = '';
        $list .= 'callbackList:noArg ';
        $list .= 'logFile:noArg'
          if ( ::ReadingsVal( $name, 'bridgeType', 'Software' ) eq 'Hardware' );

        return 'Unknown argument ' . $cmd . ', choose one of ' . $list;
    }

    return Write( $hash, $endpoint, undef );
}

sub GetCheckBridgeAlive {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer($hash);
    ::Log3( $name, 4, "NUKIBridge ($name) - GetCheckBridgeAlive" );

    if ( !::IsDisabled($name)
        && $hash->{helper}->{iowrite} == 0 )
    {
        Write( $hash, 'list', undef );
        ::Log3( $name, 4, "NUKIBridge ($name) - run Write" );
    }

    ::Log3( $name, 4,
        "NUKIBridge ($name) - Call InternalTimer for GetCheckBridgeAlive" );

    return ::InternalTimer( ::gettimeofday() + 30,
        \&FHEM::Devices::Nuki::Bridge::GetCheckBridgeAlive, $hash );
}

sub FirstRun {
    my $hash = shift;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer($hash);
    Write( $hash, 'list', undef )
      if ( !::IsDisabled($name) );

    ::readingsSingleUpdate( $hash, 'configAuthSuccess', 'unknown', 0 )
      if ( ::ReadingsVal( $name, 'configAuthSuccess', 'none' ) eq 'none' );

    return ::InternalTimer( ::gettimeofday() + 5,
        \&FHEM::Devices::Nuki::Bridge::GetCheckBridgeAlive, $hash );
}

sub Write {
    my $hash     = shift;
    my $endpoint = shift // return;
    my $json     = shift;

    my $decode_json = eval { decode_json($json) }
      if ( defined($json) );

    my $nukiId     = $decode_json->{nukiId}     // undef;
    my $deviceType = $decode_json->{deviceType} // undef;
    my $param      = $decode_json->{param}      // undef;

    my $obj = {
        endpoint   => $endpoint,
        param      => $param,
        nukiId     => $nukiId,
        deviceType => $deviceType
    };

    $hash->{helper}->{lastDeviceAction} = $obj
      if (
        ( defined($param) && $param )
        || ( defined($nukiId)
            && $nukiId )
      );

    unshift( @{ $hash->{helper}->{actionQueue} }, $obj );

    return BridgeCall($hash);
}

sub CreateUri {
    my $hash = shift;
    my $obj  = shift;

    my $name       = $hash->{NAME};
    my $host       = $hash->{HOST};
    my $port       = $hash->{PORT};
    my $token      = $hash->{TOKEN};
    my $endpoint   = $obj->{endpoint};
    my $param      = $obj->{param};
    my $nukiId     = $obj->{nukiId};
    my $deviceType = $obj->{deviceType};

    my $uri = 'http://' . $host . ':' . $port;
    $uri .= '/' . $endpoint    if ( defined $endpoint );
    $uri .= '?token=' . $token if ( defined($token) );

    if (   defined($param)
        && defined($deviceType) )
    {
        $uri .= '&action='
          . $lockActionsSmartLock{$param}
          if (
            $endpoint ne 'callback/add'
            && (   $deviceType == 0
                || $deviceType == 4 )
          );

        $uri .= '&action=' . $lockActionsOpener{$param}
          if ( $endpoint ne 'callback/add'
            && $deviceType == 2 );
    }

    $uri .= '&' . $param
      if ( defined($param)
        && $endpoint eq 'configAuth' );

    $uri .= '&id=' . $param
      if ( defined($param)
        && $endpoint eq 'callback/remove' );

    $uri .= '&url=' . $param
      if ( defined($param)
        && $endpoint eq 'callback/add' );

    $uri .= '&nukiId=' . $nukiId
      if ( defined($nukiId) );
    $uri .= '&deviceType=' . $deviceType
      if ( defined($deviceType) );

    ::Log3( $name, 4, "NUKIBridge ($name) - created uri: $uri" );

    return $uri;
}

sub BridgeCall {
    my $hash = shift;

    my $name     = $hash->{NAME};
    my $obj      = pop( @{ $hash->{helper}->{actionQueue} } );
    my $endpoint = $obj->{endpoint};
    my $nukiId   = $obj->{nukiId};

    if ( $hash->{helper}->{iowrite} == 0 ) {
        my $uri = CreateUri( $hash, $obj );

        if ( defined($uri) && $uri ) {
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
              if ( ( $endpoint eq 'callback/list' || $endpoint eq 'log' )
                && ref( $hash->{CL} ) eq 'HASH' );

            ::HttpUtils_NonblockingGet($param);
            ::Log3( $name, 4,
                "NUKIBridge ($name) - Send HTTP POST with URL $uri" );
        }
    }
    else {
        push( @{ $hash->{helper}->{actionQueue} }, $obj )
          if ( defined($endpoint)
            && $endpoint eq 'lockAction' );
    }

    return;
}

sub Distribution {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};

    #     my $doTrigger = $param->{doTrigger};
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};

    my $dhash = $hash;

    $dhash = $::modules{NUKIDevice}{defptr}{ $param->{'nukiId'} }
      if ( defined( $param->{'nukiId'} ) );

    my $dname = $dhash->{NAME};

    ::Log3( $name, 4, "NUKIBridge ($name) - Response JSON: $json" );
    ::Log3( $name, 4, "NUKIBridge ($name) - Response ERROR: $err" );
    ::Log3( $name, 4, "NUKIBridge ($name) - Response CODE: $param->{code}" )
      if ( defined( $param->{code} )
        && $param->{code} );

    $hash->{helper}->{iowrite} = 0
      if ( $hash->{helper}->{iowrite} == 1 );

    ::readingsBeginUpdate($hash);

    if ( defined($err) ) {
        if ( $err ne '' ) {
            if ( $param->{endpoint} eq 'info' ) {
                ::readingsBulkUpdate( $hash, 'state', 'not connected' );
                ::Log3( $name, 5, "NUKIBridge ($name) - Bridge ist offline" );
            }

            ::readingsBulkUpdate( $hash, 'lastError', $err )
              if ( ::ReadingsVal( $name, 'state', 'not connected' ) eq
                'not connected' );

            ::Log3( $name, 4,
                "NUKIBridge ($name) - error while requesting: $err" );
            ::readingsEndUpdate( $hash, 1 );

            ::asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
              if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

            return $err;
        }
    }

    if (   ( $json eq '' || $json =~ /Unavailable/i )
        && exists( $param->{code} )
        && $param->{code} != 200 )
    {

        if (   $param->{code} == 503
            && $json eq 'HTTP 503 Unavailable' )
        {
            ::Log3( $name, 4,
"NUKIBridge ($name) - Response from Bridge: $param->{code}, $json"
            );

            ::readingsEndUpdate( $hash, 1 );

            if ( defined( $hash->{helper}->{lastDeviceAction} )
                && $hash->{helper}->{lastDeviceAction} )
            {
                push(
                    @{ $hash->{helper}->{actionQueue} },
                    $hash->{helper}->{lastDeviceAction}
                );

                ::InternalTimer( ::gettimeofday() + 1,
                    \&FHEM::Devices::Nuki::Bridge::BridgeCall, $hash );
            }

            ::asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
              if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

            return;
        }

        ::readingsBulkUpdate( $hash, 'lastError',
            'Internal error, ' . $param->{code} );
        ::Log3( $name, 4,
                "NUKIBridge ($name) - received http code "
              . $param->{code}
              . " without any data after requesting" );

        ::readingsEndUpdate( $hash, 1 );

        ::asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
          if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

        return ('received http code '
              . $param->{code}
              . ' without any data after requesting' );
    }

    if ( ( $json =~ /Error/i )
        && exists( $param->{code} ) )
    {

        ::readingsBulkUpdate( $hash, 'lastError', 'invalid API token' )
          if ( $param->{code} == 401 );
        ::readingsBulkUpdate( $hash, 'lastError', 'action is undefined' )
          if ( $param->{code} == 400 && $hash == $dhash );

        ::Log3( $name, 4, "NUKIBridge ($name) - invalid API token" )
          if ( $param->{code} == 401 );
        ::Log3( $name, 4, "NUKIBridge ($name) - nukiId is not known" )
          if ( $param->{code} == 404 );
        ::Log3( $name, 4, "NUKIBridge ($name) - action is undefined" )
          if ( $param->{code} == 400 && $hash == $dhash );

        ::readingsEndUpdate( $hash, 1 );

        ::asyncOutput( $param->{cl}, "Request Error: $err\r\n" )
          if ( $param->{cl} && $param->{cl}{canAsyncOutput} );

        return $param->{code};
    }

    delete $hash->{helper}->{lastDeviceAction}
      if ( defined( $hash->{helper}->{lastDeviceAction} )
        && $hash->{helper}->{lastDeviceAction} );

    ::readingsEndUpdate( $hash, 1 );

    ::readingsSingleUpdate( $hash, 'state', 'connected', 1 );
    ::Log3( $name, 5, "NUKIBridge ($name) - Bridge ist online" );

    if ( $param->{endpoint} eq 'callback/list' ) {
        getCallbackList( $param, $json );
        return;
    }
    elsif ( $param->{endpoint} eq 'log' ) {
        getLogfile( $param, $json );
        return;
    }

    if ( $hash == $dhash ) {
        ResponseProcessing( $hash, $json, $param->{endpoint} );
    }
    else {
        my $decode_json = eval { decode_json($json) };
        if ($@) {
            ::Log3( $name, 3,
                "NUKIBridge ($name) - JSON error while request: $@" );
            return;
        }

        $decode_json->{nukiId} = $param->{nukiId};
        $json = encode_json($decode_json);

        ::Dispatch( $hash, $json, undef );
    }

    ::InternalTimer( ::gettimeofday() + 3,
        \&FHEM::Devices::Nuki::Bridge::BridgeCall, $hash )
      if ( defined( $hash->{helper}->{actionQueue} )
        && scalar( @{ $hash->{helper}->{actionQueue} } ) > 0 );

    return;
}

sub ResponseProcessing {
    my $hash     = shift;
    my $json     = shift;
    my $endpoint = shift;

    my $name = $hash->{NAME};
    my $decode_json;

    if ( !$json ) {
        ::Log3( $name, 3, "NUKIBridge ($name) - empty answer received" );
        return;
    }
    elsif ( $json =~ m'HTTP/1.1 200 OK' ) {
        ::Log3( $name, 4, "NUKIBridge ($name) - empty answer received" );
        return;
    }
    elsif ( $json !~ m/^[\[{].*[}\]]$/ ) {
        ::Log3( $name, 3, "NUKIBridge ($name) - invalid json detected: $json" );
        return ("NUKIBridge ($name) - invalid json detected: $json");
    }

    $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    if (   $endpoint eq 'list'
        || $endpoint eq 'info' )
    {
        if (
            (
                   ref($decode_json) eq 'ARRAY'
                && scalar( @{$decode_json} ) > 0
                && $endpoint eq 'list'
            )
            || (   ref($decode_json) eq 'HASH'
                && ref( $decode_json->{scanResults} ) eq 'ARRAY'
                && scalar( @{ $decode_json->{scanResults} } ) > 0
                && $endpoint eq 'info' )
          )
        {
            my @buffer;
            @buffer = split( '\[', $json )
              if ( $endpoint eq 'list' );
            @buffer = split( '"scanResults": \[', $json )
              if ( $endpoint eq 'info' );

            my ( $json, $tail ) = ParseJSON( $hash, $buffer[1] );

            while ($json) {
                ::Log3( $name, 5,
                        "NUKIBridge ($name) - Decoding JSON message. Length: "
                      . length($json)
                      . " Content: "
                      . $json );

                ::Log3( $name, 5,
                        "NUKIBridge ($name) - Vor Sub: Laenge JSON: "
                      . length($json)
                      . " Content: "
                      . $json
                      . " Tail: "
                      . $tail );

                ::Dispatch( $hash, $json, undef )
                  if ( defined($tail)
                    && $tail );

                ( $json, $tail ) = ParseJSON( $hash, $tail );

                ::Log3( $name, 5,
                        "NUKIBridge ($name) - Nach Sub: Laenge JSON: "
                      . length($json)
                      . " Content: "
                      . $json
                      . " Tail: "
                      . $tail );
            }
        }

        WriteReadings( $hash, $decode_json, $endpoint )
          if ( $endpoint eq 'info' );

        return;
    }
    elsif ( $endpoint eq 'configAuth' ) {
        WriteReadings( $hash, $decode_json, $endpoint );
    }
    else {

        return ::Log3( $name, 5,
            "NUKIBridge ($name) - Rückgabe Path nicht korrekt: $json" );
    }
}

sub CGI() {
    my $request = shift;

    my $hash;
    my $name;

    while ( my ( $key, $value ) = each %{ $::modules{NUKIBridge}{defptr} } ) {
        $hash = $::modules{NUKIBridge}{defptr}{$key};
        $name = $hash->{NAME};
    }

    return ('NUKIBridge WEBHOOK - No IODev found')
      if ( !defined($hash)
        && !defined($name) );

    my $json = ( split( '&', $request, 2 ) )[1];

    if ( !$json ) {
        ::Log3( $name, 3,
            "NUKIBridge WEBHOOK ($name) - empty message received" );
        return;
    }
    elsif ( $json =~ m'HTTP/1.1 200 OK' ) {
        ::Log3( $name, 4,
            "NUKIBridge WEBHOOK ($name) - empty answer received" );
        return;
    }
    elsif ( $json !~ m/^[\[{].*[}\]]$/ ) {
        ::Log3( $name, 3,
            "NUKIBridge WEBHOOK ($name) - invalid json detected: $json" );
        return ("NUKIBridge WEBHOOK ($name) - invalid json detected: $json");
    }

    ::Log3( $name, 5,
        "NUKIBridge WEBHOOK ($name) - Webhook received with JSON: $json" );

    if ( $json =~ m/^\{.*\}$/ ) {
        $hash->{WEBHOOK_COUNTER}++;
        $hash->{WEBHOOK_LAST} = ::TimeNow();

        ::Log3( $name, 3,
"NUKIBridge WEBHOOK ($name) - Received webhook for matching NukiId at device $name"
        );

        ::Dispatch( $hash, $json, undef );

        return ( undef, undef );
    }

    # no data received
    else {
        ::Log3( $name, 4,
            "NUKIBridge WEBHOOK - received malformed request\n$request" );
    }

    ::return( 'text/plain; charset=utf-8', 'Call failure: ' . $request );
}

sub WriteReadings {
    my $hash        = shift;
    my $decode_json = shift;
    my $endpoint    = shift;

    my $name = $hash->{NAME};

    my $nukiId;
    my $scanResults;
    my %response_hash;
    my $dname;
    my $dhash;

    ::readingsBeginUpdate($hash);

    if ( $endpoint eq 'configAuth' ) {
        ::readingsBulkUpdate( $hash, 'configAuthSuccess',
            $decode_json->{success} );
    }
    else {
        ::readingsBulkUpdate( $hash, 'appVersion',
            $decode_json->{versions}->{appVersion} );
        ::readingsBulkUpdate( $hash, 'firmwareVersion',
            $decode_json->{versions}->{firmwareVersion} );
        ::readingsBulkUpdate( $hash, 'wifiFirmwareVersion',
            $decode_json->{versions}->{wifiFirmwareVersion} );
        ::readingsBulkUpdate( $hash, 'bridgeType',
            $bridgeType{ $decode_json->{bridgeType} } );
        ::readingsBulkUpdate( $hash, 'hardwareId',
            $decode_json->{ids}{hardwareId} );
        ::readingsBulkUpdate( $hash, 'serverId',
            $decode_json->{ids}{serverId} );
        ::readingsBulkUpdate( $hash, 'uptime', $decode_json->{uptime} );
        ::readingsBulkUpdate( $hash, 'currentGMTime',
            $decode_json->{currentTime} );
        ::readingsBulkUpdate( $hash, 'serverConnected',
            $decode_json->{serverConnected} );
        ::readingsBulkUpdate( $hash, 'wlanConnected',
            $decode_json->{wlanConnected} );
    }

    ::readingsEndUpdate( $hash, 1 );
    return;
}

sub getLogfile {
    my $param = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    ::Log3( $name, 4,
        "NUKIBridge ($name) - Log data are collected and processed" );

    if (   $param->{cl}
        && $param->{cl}->{TYPE} eq 'FHEMWEB' )
    {

        if ( ref($decode_json) eq 'ARRAY'
            && scalar( @{$decode_json} ) > 0 )
        {
            ::Log3( $name, 4,
                "NUKIBridge ($name) - created Table with log file" );

            my $header = '<html>' . '<div style="float: left">Log List</div>';

            my $ret = $header . '<table width=100%><tr><td>';
            $ret .= '<table class="block wide">';

            for my $logs ( @{$decode_json} ) {
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

                for my $d ( reverse sort keys %{$logs} ) {
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

            ::asyncOutput( $param->{cl}, $ret )
              if ( $param->{cl}
                && $param->{cl}{canAsyncOutput} );
        }
    }

    return;
}

sub getCallbackList {
    my $param = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    ::Log3( $name, 4,
        "NUKIBridge ($name) - Callback data are collected and processed" );

    if (   $param->{cl}
        && $param->{cl}->{TYPE} eq 'FHEMWEB' )
    {

        if ( ref( $decode_json->{callbacks} ) eq 'ARRAY' ) {
            ::Log3( $name, 4,
                "NUKIBridge ($name) - created Table with log file" );

            my $space = '&nbsp;';
            my $aHref;
            my $header =
              '<html>' . '<div style="float: left">Callback List</div>';

            my $ret = $header . '<table width=100%><tr><td>';
            $ret .= '<table class="block wide">';
            $ret .= '<tr class="odd">';
            $ret .= '<td><b>URL</b></td>';
            $ret .= '<td><b>Remove</b></td>';
            $ret .= '</tr>';

            if ( scalar( @{ $decode_json->{callbacks} } ) > 0 ) {
                for my $cb ( @{ $decode_json->{callbacks} } ) {
                    $aHref = "<a href=\""

                      #                       . $::FW_httpheader->{host}
                      . "/fhem?cmd=set+"
                      . $name
                      . "+callbackRemove+"
                      . $cb->{id}
                      . $::FW_CSRF
                      . "\"><font color=\"red\"><b>X</b></font></a>";

                    $ret .= '<td>' . $cb->{url} . '</td>';
                    $ret .= '<td>' . $aHref . '</td>';
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

            ::asyncOutput( $param->{cl}, $ret )
              if ( $param->{cl}
                && $param->{cl}{canAsyncOutput} );
        }
    }

    return;
}

sub getCallbackList2 {
    my $param = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    ::Log3( $name, 4,
        "NUKIBridge ($name) - Callback data are collected and processed" );

    if (   $param->{cl}
        && $param->{cl}->{TYPE} eq 'FHEMWEB' )
    {

        if ( ref( $decode_json->{callbacks} ) eq 'ARRAY' ) {
            ::Log3( $name, 4,
                "NUKIBridge ($name) - created Table with Callback List" );

            my $j1 =
              '<script language=\"javascript\" type=\"text/javascript\">{';
            $j1 .=
"function callbackRemove(){FW_cmd(FW_root+'?cmd=get $name callbackList&XHR=1')}";
            $j1 .= '}</script>';

    #                 FW_cmd(FW_root+"?cmd="+type+" "+dev+
    #                 (params[0]=="state" ? "":" "+params[0])+" "+arg+"&XHR=1");

            my $header = '<html>';
            my $footer = '</html>';

            my $ret =
                '<div style="float: left">Callback List</div>'
              . '<table width=100%><tr><td>'
              . '<table class="block wide">'
              . '<tr class="odd">'
              . '<td><b>URL</b></td>'
              . '<td><b>Remove</b></td>' . '</tr>';

            if ( scalar( @{ $decode_json->{callbacks} } ) > 0 ) {
                for my $cb ( @{ $decode_json->{callbacks} } ) {
                    $ret .= '<td>' . $cb->{url} . '</td>';
                    $ret .=
"<td><input title=\"CallbackRemove\" name=\"Remove\" type=\"button\"  value=\"Remove\" onclick=\" javascript: callbackRemove() \"></td>";
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
            $ret .= '</table>';

            ::Log3( $name, 4,
"NUKIBridge ($name) - Callback List Table created and call asyncOutput Fn"
            );

            ::asyncOutput( $param->{cl}, $header . $ret . $j1 . $footer )
              if ( $param->{cl}
                && $param->{cl}{canAsyncOutput} );
        }
    }

    return;
}

sub ParseJSON {
    my $hash   = shift;
    my $buffer = shift;

    my $name  = $hash->{NAME};
    my $open  = 0;
    my $close = 0;
    my $msg   = '';
    my $tail  = '';

    if ($buffer) {
        for my $c ( split //, $buffer ) {

            if (   $open == $close
                && $open > 0 )
            {
                $tail .= $c;
                ::Log3( $name, 5,
                    "NUKIBridge ($name) - $open == $close and $open > 0" );

            }
            elsif ($open == $close
                && $c ne '{' )
            {
                ::Log3( $name, 5,
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

    ::Log3( $name, 5, "NUKIBridge ($name) - return msg: $msg and tail: $tail" );

    return ( $msg, $tail );
}

sub BridgeDiscover {
    my $hash     = shift;
    my $endpoint = shift;
    my $bridge   = shift;
    my $name     = $hash->{NAME};
    my $url      = (
        $endpoint eq 'discover' && !defined($bridge)
        ? 'https://api.nuki.io/discover/bridges'
        : 'http://' . $bridge->{'ip'} . ':' . $bridge->{'port'} . '/auth'
    );
    my $timeout = (
        $endpoint eq 'discover' && !defined($bridge)
        ? 5
        : 35
    );

    if ( $endpoint eq 'discover' ) {
        ::Log3( $name, 3,
            "NUKIBridge ($name) - Bridge device defined. run discover mode" );

        ::readingsSingleUpdate( $hash, 'state', 'run discovery', 1 );
    }
    elsif ( $endpoint eq 'getApiToken' ) {

        ::Log3( $name, 3,
"NUKIBridge ($name) - Enables the api (if not yet enabled) and get the api token."
        );
    }

    ::HttpUtils_NonblockingGet(
        {
            url      => $url,
            timeout  => $timeout,
            hash     => $hash,
            header   => 'Accept: application/json',
            endpoint => $endpoint,
            host     => $bridge->{'ip'},
            port     => $bridge->{'port'},
            method   => 'GET',
            callback => \&BridgeDiscoverRequest,
        }
    );

    ::Log3( $name, 3,
        "NUKIBridge ($name) - Send Discover request to Nuki Cloud" )
      if ( $endpoint eq 'discover' );

    ::Log3( $name, 3, "NUKIBridge ($name) - get API Token from the Bridge" )
      if ( $endpoint eq 'getApiToken' );

    return;
}

sub BridgeDiscoverRequest {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};

    if ( defined($err)
        && $err ne '' )
    {
        return ::Log3( $name, 3, "NUKIBridge ($name) - Error: $err" );
    }
    elsif ( exists( $param->{code} )
        && $param->{code} != 200 )
    {
        return ::Log3( $name, 3,
            "NUKIBridge ($name) - HTTP error Code present. Code: $param->{code}"
        );
    }

    my $decode_json;
    $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "NUKIBridge ($name) - JSON error while request: $@" );
        return;
    }

    if ( $param->{endpoint} eq 'discover' ) {

        return ::readingsSingleUpdate( $hash, 'state', 'no bridges discovered',
            1 )
          if ( scalar( @{ $decode_json->{bridges} } ) == 0
            && $decode_json->{errorCode} == 0 );

        return BridgeDiscover_getAPIToken( $hash, $decode_json );
    }
    elsif ( $param->{endpoint} eq 'getApiToken' ) {
        ::readingsSingleUpdate( $hash, 'state',
            'modefined bridge device in progress', 1 );

        $decode_json->{host} = $param->{host};
        $decode_json->{port} = $param->{port};

        return ModefinedBridgeDevices( $hash, $decode_json )
          if ( $decode_json->{success} == 1 );

        return ::readingsSingleUpdate( $hash, 'state', 'get api token failed',
            1 );
    }

    return;
}

sub BridgeDiscover_getAPIToken {
    my $hash        = shift;
    my $decode_json = shift;
    my $name        = $hash->{NAME};

    my $pullApiKeyMessage =
      'When issuing this API-call the bridge turns on its LED for 30 seconds.
The button of the bridge has to be pressed within this timeframe. Otherwise the bridge returns a negative success and no token.';

    ::readingsSingleUpdate( $hash, 'state', $pullApiKeyMessage, 1 );

    for ( @{ $decode_json->{bridges} } ) {

        BridgeDiscover( $hash, 'getApiToken', $_ );
    }

    return;
}

sub ModefinedBridgeDevices {
    my $hash        = shift;
    my $decode_json = shift;
    my $name        = $hash->{NAME};

    ::CommandAttr( undef, $name . ' port ' . $decode_json->{port} )
      if ( $decode_json->{port} != 8080 );
    ::CommandDefMod( undef,
            $name
          . ' NUKIBridge '
          . $decode_json->{host} . ' '
          . $decode_json->{token} );

    return;
}

1;

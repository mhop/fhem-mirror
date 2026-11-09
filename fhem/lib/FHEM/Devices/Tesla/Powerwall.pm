###############################################################################
#
# Developed with VSCodium and richterger perl plugin
#
#  (c) 2016-2026 Copyright: Marko Oldenburg (fhemdevelopment at cooltux dot net)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#   Special thanks goes to comitters:
#       - Eckat        Thanks for many Code
#                    - Automatische Recovery bei ungültigem Auth-Token
#                    - Queue-/Timer-Race beseitigt
#                    - Defensiver Umgang mit leerer Queue
#                    - Robustere HTTP-/JSON-Fehlerbehandlung
#                    - Token nicht mehr im Log
#                    - customer/registration als optionaler Endpoint
#                    - Redundanten site_info/site_name-Request entfernt
#
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
##
##
## Das JSON Modul immer in einem eval aufrufen
# $data = eval{decode_json($data)};
#
# if($@){
#   ::Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");
#
#   ::readingsSingleUpdate($hash, "state", "error", 1);
#
#   return;
# }
#
#######
#######
#  URLs zum Abrufen diverser Daten
# https://<ip-Powerwall>/api/system_status/soe
# https://<ip-Powerwall>/api/meters/aggregates
# https://<ip-Powerwall>/api/site_info
# https://<ip-Powerwall>/api/sitemaster
# https://<ip-Powerwall>/api/powerwalls
# https://<ip-Powerwall>/api/networks
# https://<ip-Powerwall>/api/system/networks
# https://<ip-Powerwall>/api/operation
#
##
##

package FHEM::Devices::Tesla::Powerwall;

use strict;
use warnings;

use HttpUtils;
use GPUtils                               qw(GP_Import);
use FHEM::Core::Authentication::Passwords qw(:ALL);

BEGIN {
    # Import from main context
    GP_Import(
        qw( init_done
          defs
        )
    );
}

my $json_loaded  = 0;
my @json_modules = (
    'JSON::MaybeXS',    'JSON',
    'Cpanel::JSON::XS', 'JSON::XS',
    'JSON::PP',         'JSON::backportPP'
);
local $ENV{PERL_JSON_BACKEND} =
  'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
  unless defined( $ENV{PERL_JSON_BACKEND} );

for my $module (@json_modules) {
    if (
        eval "require $module; import $module qw(decode_json encode_json); 1;" )
    {
        $json_loaded = 1;
        last;
    }
}
die "No JSON module found" unless $json_loaded;

my %paths = (
    'statussoe'    => 'system_status/soe',
    'aggregates'   => 'meters/aggregates',
    'meterssite'   => 'meters/site',
    'meterssolar'  => 'meters/solar',
    'siteinfo'     => 'site_info',
    'sitemaster'   => 'sitemaster',
    'powerwalls'   => 'powerwalls',
    'registration' => 'customer/registration',
    'status'       => 'status',
    'gridstatus'   => 'system_status/grid_status',
);

my %cmdPaths = (
    'powerwallsstop' => 'sitemaster/stop',
    'powerwallsrun'  => 'sitemaster/run',
);

# Optional endpoints may disappear with newer Gateway firmware. A 404 on one
# of these paths disables only the automatic polling for the current FHEM
# runtime. Manual get commands remain available and a restart probes again.
my %optionalPaths = ( 'registration' => 1, );

sub decode_json_safe {
    my ( $json, $name ) = @_;
    local $SIG{__DIE__} = 'IGNORE';
    my $decoded = eval { decode_json($json) };
    if ($@) {
        ::Log3 $name, 4,
          "TeslaPowerwall2AC ($name) - error while JSON decoding: $@";
        return undef;
    }
    return $decoded;
}

sub Define {
    my ( $hash, $aArg ) = @_;
    my $version;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    $version = FHEM::Meta::Get( $hash, 'version' );
    our $VERSION = $version;

    return q{too few parameters: define <name> TeslaPowerwall2AC <HOST>}
      if ( scalar( @{$aArg} ) != 3 );

    my $name = $aArg->[0];
    my $host = $aArg->[2];

    $hash->{HOST}        = $host;
    $hash->{INTERVAL}    = 300;
    $hash->{VERSION}     = version->parse($VERSION)->normal;
    $hash->{NOTIFYDEV}   = qq(global,$name);
    $hash->{actionQueue} = [];

    ::CommandAttr( undef, $name . q{ room Tesla} )
      if ( ::AttrVal( $name, 'room', 'none' ) eq 'none' );
    ::Log3 $name, 3,
"TeslaPowerwall2AC ($name) - defined TeslaPowerwall2AC Device with Host $host and Interval $hash->{INTERVAL}";

    ### create password object to handle pass keystore
    $hash->{helper}->{passObj} =
      FHEM::Core::Authentication::Passwords->new( $hash->{TYPE} );

    return;
}

sub Undef {
    my ( $hash, $name ) = @_;

    ::RemoveInternalTimer($hash);
    ::Log3 $name, 3, "TeslaPowerwall2AC ($name) - Device $name deleted";

    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' && $attrVal eq '1' ) {
            ::RemoveInternalTimer($hash);
            ::readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            ::Log3 $name, 3, "TeslaPowerwall2AC ($name) - disabled";

        }
        elsif ( $cmd eq 'del' ) {
            ::Log3 $name, 3, "TeslaPowerwall2AC ($name) - enabled";
        }
    }

    if ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            return
'check disabledForIntervals Syntax HH:MM-HH:MM or \'HH:MM-HH:MM HH:MM-HH:MM ...\''
              unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/x );
            ::Log3 $name, 3, "TeslaPowerwall2AC ($name) - disabledForIntervals";
            ::readingsSingleUpdate( $hash, 'state', 'disabled', 1 );

        }
        elsif ( $cmd eq 'del' ) {
            ::Log3 $name, 3, "TeslaPowerwall2AC ($name) - enabled";
            ::readingsSingleUpdate( $hash, 'state', 'active', 1 );
        }
    }

    if ( $attrName eq 'interval' ) {
        if ( $cmd eq 'set' ) {
            if ( $attrVal < 60 ) {
                ::Log3 $name, 3,
"TeslaPowerwall2AC ($name) - interval too small, please use something >= 60 (sec), default is 300 (sec)";
                return
q{interval too small, please use something >= 60 (sec), default is 300 (sec)};

            }
            else {
                ::RemoveInternalTimer( $hash,
                    \&FHEM::Devices::Tesla::Powerwall::Timer_GetData );
                $hash->{INTERVAL} = $attrVal;
                ::Log3 $name, 3,
                  "TeslaPowerwall2AC ($name) - set interval to $attrVal";
                Timer_GetData($hash);
            }
        }
        elsif ( $cmd eq 'del' ) {
            ::RemoveInternalTimer( $hash,
                \&FHEM::Devices::Tesla::Powerwall::Timer_GetData );
            $hash->{INTERVAL} = 300;
            ::Log3 $name, 3,
              "TeslaPowerwall2AC ($name) - set interval to default";
            Timer_GetData($hash);
        }
    }

    return;
}

sub Notify {
    my ( $hash, $dev ) = @_;

    my $name = $hash->{NAME};
    return if ( ::IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = ::deviceEvents( $dev, 1 );
    return if ( !$events );

    Timer_GetData($hash)
      if (
        (
               grep { /^INITIALIZED$/x } @{$events}
            or grep { /^ATTR.$name.emailaddr$/x } @{$events}
            or grep { /^DELETEATTR.$name.disable$/x } @{$events}
            or grep { /^DELETEATTR.$name.interval$/x } @{$events}
            or grep { /^DEFINED.$name$/x } @{$events}
        )
        && $init_done
      );
    return;
}

sub Get {
    my ( $hash, $aArg ) = @_;

    my $name = shift @$aArg;
    my $cmd  = shift @$aArg // return qq(get $name needs at least one argument);
    my $arg;

    $cmd = lc($cmd);

    my %valid_cmds = map { $_ => 1 }
      qw(statussoe aggregates siteinfo powerwalls sitemaster registration status);

    if ( exists $valid_cmds{$cmd} ) {
        $arg = $cmd;
    }
    else {
        my $list = '';
        $list .=
'statusSOE:noArg aggregates:noArg siteinfo:noArg sitemaster:noArg powerwalls:noArg registration:noArg status:noArg '
          if ( ::AttrVal( $name, 'emailaddr', 'none' ) ne 'none'
            && exists( $hash->{helper}->{passObj} )
            && defined( $hash->{helper}->{passObj}->getReadPassword($name) )
            && defined( $hash->{TOKEN} ) );

        return 'Unknown argument ' . $cmd . ', choose one of ' . $list;
    }

    return 'There are still path commands in the action queue'
      if ( defined( $hash->{actionQueue} )
        && scalar( @{ $hash->{actionQueue} } ) > 0 );

    unshift @{ $hash->{actionQueue} }, $arg;
    Write($hash);

    return;
}

sub Set {    ## no critic (Subroutine with high complexity score)
    my ( $hash, $aArg, $hArg ) = @_;

    my $name = shift @$aArg;
    my $cmd  = shift @$aArg // return qq(set $name needs at least one argument);
    my $arg;

    if ( $cmd eq 'powerwalls' ) {
        $arg = lc( $cmd . $aArg->[0] );
    }
    elsif ( lc $cmd eq 'setpassword' ) {
        return q{please set Attribut emailaddr first}
          if ( ::AttrVal( $name, 'emailaddr', 'none' ) eq 'none' );

        return qq(usage: $cmd pass=<password>)
          if ( scalar( @{$aArg} ) != 0
            || scalar( keys %{$hArg} ) != 1 );
        my ( $passResp, $passErr );

        ( $passResp, $passErr ) = $hash->{helper}->{passObj}
          ->setStorePassword( $name, $hArg->{'pass'} );

        return qq{error while saving the password - $passErr}
          if (!defined($passResp)
            && defined($passErr) );

        return Timer_GetData($hash)
          if ( defined($passResp)
            && !defined($passErr) );
    }
    elsif ( lc $cmd eq 'removepassword' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );

        my ( $passResp, $passErr );
        ( $passResp, $passErr ) =
          $hash->{helper}->{passObj}->setDeletePassword($name);

        return qq{error while saving the password - $passErr}
          if (!defined($passResp)
            && defined($passErr) );

        return q{password successfully removed}
          if ( defined($passResp)
            && !defined($passErr) );
    }
    else {

        my $list = (
            exists( $hash->{helper}->{passObj} )
              && defined( $hash->{helper}->{passObj}->getReadPassword($name) )
            ? 'removePassword:noArg '
            : 'setPassword '
        );

        $list .= 'powerwalls:run,stop'
          if ( ::AttrVal( $name, 'devel', 0 ) == 1
            && exists( $hash->{helper}->{passObj} )
            && defined( $hash->{helper}->{passObj}->getReadPassword($name) )
            && defined( $hash->{TOKEN} ) );

        return 'Unknown argument ' . $cmd . ', choose one of ' . $list;
    }

    unshift @{ $hash->{actionQueue} }, $arg;
    Write($hash);

    return;
}

sub Timer_GetData {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    ::RemoveInternalTimer( $hash,
        \&FHEM::Devices::Tesla::Powerwall::Timer_GetData );

    if (   exists( $hash->{actionQueue} )
        && scalar( @{ $hash->{actionQueue} } ) == 0
        && !$hash->{helper}->{requestInFlight} )
    {
        if ( !::IsDisabled($name) ) {
            return ::readingsSingleUpdate( $hash, 'state',
                'please set Attribut emailaddr first', 1 )
              if ( ::AttrVal( $name, 'emailaddr', 'none' ) eq 'none' );
            return ::readingsSingleUpdate( $hash, 'state',
                'please set password first', 1 )
              if (
                !exists( $hash->{helper}->{passObj} )
                || (
                    exists( $hash->{helper}->{passObj} )
                    && !defined(
                        $hash->{helper}->{passObj}->getReadPassword($name)
                    )
                )
              );

            if ( !exists( $hash->{TOKEN} ) ) {
                unshift @{ $hash->{actionQueue} }, 'login';
            }
            else {
                while ( my $obj = each %paths ) {
                    next
                      if ( exists( $optionalPaths{$obj} )
                        && exists( $hash->{helper}->{unsupportedPaths} )
                        && exists( $hash->{helper}->{unsupportedPaths}->{$obj} )
                      );

                    unshift @{ $hash->{actionQueue} }, $obj;
                }
            }

            Write($hash);
        }
        else {
            return ::readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
        }
    }

    ::InternalTimer( ::gettimeofday() + $hash->{INTERVAL},
        \&FHEM::Devices::Tesla::Powerwall::Timer_GetData, $hash );

    ::Log3 $name, 4,
      "TeslaPowerwall2AC ($name) - Call ::InternalTimer Timer_GetData";

    return;
}

sub Write {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    # Only one HTTP request may be active at a time. The current queue item is
    # removed before HttpUtils calls us back, so an empty queue alone does not
    # mean that the module is idle.
    return
      if ( $hash->{helper}->{requestInFlight} );

    if (  !exists( $hash->{actionQueue} )
        || scalar( @{ $hash->{actionQueue} } ) == 0 )
    {
        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdateIfChanged( $hash, 'actionQueue',
            '0 entries in the Queue' );
        ::readingsBulkUpdateIfChanged( $hash, 'state', 'ready' );
        ::readingsEndUpdate( $hash, 1 );

        ::Log3 $name, 4,
"TeslaPowerwall2AC ($name) - Write called with empty actionQueue, ignoring";
        return;
    }

    my $queueEntry = pop( @{ $hash->{actionQueue} } );
    my ( $uri, $method, $header, $data, $path ) =
      CreateUri( $hash, $queueEntry );

    $hash->{helper}->{requestInFlight} = 1;

    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdateIfChanged( $hash, 'actionQueue',
        scalar( @{ $hash->{actionQueue} } ) . ' entries in the Queue' );
    ::readingsBulkUpdate(
        $hash,
        'state',
        'fetch data - '
          . scalar( @{ $hash->{actionQueue} } )
          . ' entries in the Queue',
        1
    );
    ::readingsEndUpdate( $hash, 1 );

    ::HttpUtils_NonblockingGet(
        {
            url     => 'https://' . $uri,
            timeout => 5,
            method  => $method,
            data    => $data,
            header  => $header,
            hash    => $hash,
            setCmd  => $path,
            sslargs =>
              { SSL_hostname => 0, verify_hostname => 0, SSL_verify_mode => 0 },
            doTrigger => 1,
            callback  => \&ErrorHandling,
        }
    );

    return ::Log3 $name, 4,
      "TeslaPowerwall2AC ($name) - Send with URI: https://$uri";
}

sub ErrorHandling {
    my ( $param, $err, $data ) = @_;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $path = $param->{setCmd};

    # The callback marks completion of the one active HTTP request, regardless
    # of whether it completed successfully or with an error.
    $hash->{helper}->{requestInFlight} = 0;

    my $httpCode = (
        exists( $param->{code} ) && defined( $param->{code} )
        ? $param->{code}
        : 0
    );

    ### Begin Error Handling

    if ( defined($err) && $err ne '' ) {

        $hash->{actionQueue} = [];

        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, 'state',            $err, 1 );
        ::readingsBulkUpdate( $hash, 'lastRequestError', $err, 1 );
        ::readingsBulkUpdateIfChanged( $hash, 'actionQueue',
            '0 entries in the Queue' );
        ::readingsEndUpdate( $hash, 1 );

        ::Log3 $name, 3, "TeslaPowerwall2AC ($name) - RequestERROR: $err";
        return;
    }

    my $decoded;
    if ( defined($data) && $data ne '' ) {
        $decoded = decode_json_safe( $data, $name );
    }

    my $apiCode = (
        ref($decoded) eq 'HASH' && defined( $decoded->{code} )
        ? $decoded->{code}
        : 0
    );

    # The Gateway invalidates the local session, e.g. after firmware updates
    # or a reboot. Renew the session independent of JSON formatting/order.
    if ( ( $httpCode == 401 || $apiCode == 401 )
        && $path ne 'login' )
    {
        my $message = (
            ref($decoded) eq 'HASH' && defined( $decoded->{message} )
            ? $decoded->{message}
            : 'authentication token rejected'
        );

        delete $hash->{TOKEN};
        $hash->{actionQueue} = [];

        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, 'state',
            'authentication expired - renewing session', 1 );
        ::readingsBulkUpdate( $hash, 'lastRequestError',
            'Path: ' . $path . ' 401 - ' . $message );
        ::readingsBulkUpdateIfChanged( $hash, 'actionQueue',
            '0 entries in the Queue' );
        ::readingsEndUpdate( $hash, 1 );

        ::Log3 $name, 3,
"TeslaPowerwall2AC ($name) - authentication token rejected, renewing session";

        unshift @{ $hash->{actionQueue} }, 'login';
        return Write($hash);
    }

    # Optional API paths may be removed by newer Gateway firmware. Remember a
    # 404 for the current FHEM runtime and omit that path from later automatic
    # polling cycles. A restart intentionally probes the path again.
    if (   $httpCode == 404
        && defined($path)
        && exists( $optionalPaths{$path} ) )
    {
        $hash->{helper}->{unsupportedPaths}->{$path} = 1;

        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdateIfChanged( $hash, 'actionQueue',
            scalar( @{ $hash->{actionQueue} } ) . ' entries in the Queue' );
        ::readingsBulkUpdateIfChanged(
            $hash, 'state',
            (
                scalar( @{ $hash->{actionQueue} } ) == 0
                ? 'ready'
                : 'fetch data - '
                  . scalar( @{ $hash->{actionQueue} } )
                  . ' paths in actionQueue'
            )
        );
        ::readingsEndUpdate( $hash, 1 );

        ::Log3 $name, 3,
"TeslaPowerwall2AC ($name) - optional endpoint $path returned HTTP 404, disable automatic polling for current runtime";

        ::InternalTimer( ::gettimeofday() + 3,
            \&FHEM::Devices::Tesla::Powerwall::Write, $hash )
          if ( scalar( @{ $hash->{actionQueue} } ) > 0 );

        return;
    }

    # Handle HTTP errors even if the Gateway sends a plain-text response body.
    # This prevents unexpected non-JSON error bodies from being passed to
    # decode_json.
    if ( $httpCode && $httpCode != 200 ) {
        my $response = defined($data) ? $data : '';
        $response =~ s/[\r\n]+/ /g;
        $response = substr( $response, 0, 200 );

        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, 'state', $httpCode, 1 );
        ::readingsBulkUpdate(
            $hash,
            'lastRequestError',
            'Path: '
              . $path
              . ' HTTP '
              . $httpCode
              . ( $response ne '' ? ' - Response: ' . $response : '' ),
            1
        );
        ::readingsEndUpdate( $hash, 1 );

        ::Log3 $name, 3,
"TeslaPowerwall2AC ($name) - RequestERROR: HTTP $httpCode for path $path";

        ::InternalTimer( ::gettimeofday() + 3,
            \&FHEM::Devices::Tesla::Powerwall::Write, $hash )
          if ( defined( $hash->{actionQueue} )
            && scalar( @{ $hash->{actionQueue} } ) > 0 );

        return;
    }

    # Handle API errors from valid JSON without depending on key order.
    if ( ref($decoded) eq 'HASH' && $apiCode ) {
        my $error =
          defined( $decoded->{error} ) ? $decoded->{error} : '';
        my $message =
          defined( $decoded->{message} ) ? $decoded->{message} : '';

        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, 'state', $apiCode, 1 );
        ::readingsBulkUpdate(
            $hash,
            'lastRequestError',
            'Path: '
              . $path . ' '
              . $apiCode
              . ' - Error: '
              . $error
              . ' Messages: '
              . $message,
            1
        );
        ::readingsEndUpdate( $hash, 1 );

        ::InternalTimer( ::gettimeofday() + 3,
            \&FHEM::Devices::Tesla::Powerwall::Write, $hash )
          if ( defined( $hash->{actionQueue} )
            && scalar( @{ $hash->{actionQueue} } ) > 0 );

        return;
    }

    # A successful HTTP response that is not JSON must not poison the queue.
    if ( defined($data) && $data ne '' && !defined($decoded) ) {
        my $response = $data;
        $response =~ s/[\r\n]+/ /g;
        $response = substr( $response, 0, 200 );

        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, 'state', 'response error', 1 );
        ::readingsBulkUpdate( $hash, 'lastRequestError',
            'Path: ' . $path . ' - invalid JSON response: ' . $response, 1 );
        ::readingsEndUpdate( $hash, 1 );

        ::Log3 $name, 3,
          "TeslaPowerwall2AC ($name) - invalid JSON response for path $path";

        ::InternalTimer( ::gettimeofday() + 3,
            \&FHEM::Devices::Tesla::Powerwall::Write, $hash )
          if ( defined( $hash->{actionQueue} )
            && scalar( @{ $hash->{actionQueue} } ) > 0 );

        return;
    }

    ### End Error Handling

    ::InternalTimer( ::gettimeofday() + 3,
        \&FHEM::Devices::Tesla::Powerwall::Write, $hash )
      if ( defined( $hash->{actionQueue} )
        && scalar( @{ $hash->{actionQueue} } ) > 0 );

    if ( $path eq 'login' ) {
        ::Log3 $name, 4,
"TeslaPowerwall2AC ($name) - Recieve JSON data for login: <token redacted>";
    }
    else {
        ::Log3 $name, 4, "TeslaPowerwall2AC ($name) - Recieve JSON data: $data";
    }

    return ResponseProcessing( $hash, $path, $data );
}

sub ResponseProcessing {
    my ( $hash, $path, $json ) = @_;

    my $name = $hash->{NAME};
    my $readings;

    my $decode_json = decode_json_safe( $json, $name );
    if ( !defined($decode_json) ) {
        ::readingsBeginUpdate($hash);
        ::readingsBulkUpdate( $hash, 'JSON Error', 'decoding failed' );
        ::readingsBulkUpdate( $hash, 'state',      'JSON error' );
        ::readingsEndUpdate( $hash, 1 );
        return;
    }

    return
      if ( ref($decode_json) eq 'HASH'
        && defined( $decode_json->{error} )
        && $decode_json->{error}
        && defined( $decode_json->{code} )
        && $decode_json->{code} );

    #### Verarbeitung der Readings zum passenden Path

    if ( $path eq 'aggregates' ) {
        $readings = ReadingsProcessing_Aggregates( $hash, $decode_json );
    }
    elsif ( $path eq 'powerwalls' ) {
        $readings = ReadingsProcessing_Powerwalls( $hash, $decode_json );
    }
    elsif ( $path eq 'login' ) {
        $hash->{TOKEN} = $decode_json->{token};
        return Timer_GetData($hash);
    }
    elsif ( $path eq 'meterssite' ) {
        $readings = ReadingsProcessing_Meters( $hash, $decode_json, 'site' );
    }
    elsif ( $path eq 'meterssolar' ) {
        $readings = ReadingsProcessing_Meters( $hash, $decode_json, 'solar' );
    }
    else {
        $readings = $decode_json;
    }

    return WriteReadings( $hash, $path, $readings );
}

sub WriteReadings {
    my ( $hash, $path, $readings ) = @_;

    my $name = $hash->{NAME};

    ::Log3 $name, 4, "TeslaPowerwall2AC ($name) - Write Readings";

    ::readingsBeginUpdate($hash);
    while ( my ( $r, $v ) = each %{$readings} ) {
        ::readingsBulkUpdate( $hash, $path . '-' . $r, $v );
    }

    # Newer Gateway firmware already returns site_name and timezone as part of
    # /api/site_info. Keep the historic sitename-* readings for compatibility
    # without polling /api/site_info/site_name separately.
    if ( $path eq 'siteinfo' ) {
        ::readingsBulkUpdate( $hash, 'sitename-site_name',
            $readings->{site_name} )
          if ( defined( $readings->{site_name} ) );

        ::readingsBulkUpdate( $hash, 'sitename-timezone',
            $readings->{timezone} )
          if ( defined( $readings->{timezone} ) );
    }

    ::readingsBulkUpdate( $hash, 'batteryLevel',
        sprintf( "%.1f", $readings->{percentage} ) )
      if ( defined( $readings->{percentage} ) );
    ::readingsBulkUpdate(
        $hash,
        'batteryPower',
        sprintf(
            "%.1f",
            (
                ::ReadingsVal( $name, 'siteinfo-nominal_system_energy_kWh', 0 )
                  / 100
            ) * ::ReadingsVal( $name, 'statussoe-percentage', 0 )
        )
    );

    ::readingsBulkUpdateIfChanged( $hash, 'actionQueue',
        scalar( @{ $hash->{actionQueue} } ) . ' entries in the Queue' );
    ::readingsBulkUpdateIfChanged(
        $hash, 'state',
        (
            defined( $hash->{actionQueue} )
              && scalar( @{ $hash->{actionQueue} } ) == 0
            ? 'ready'
            : 'fetch data - '
              . scalar( @{ $hash->{actionQueue} } )
              . ' paths in actionQueue'
        )
    );

    ::readingsEndUpdate( $hash, 1 );

    return;
}

sub ReadingsProcessing_Aggregates {
    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    if ( ref($decode_json) eq 'HASH' ) {
        while ( my $obj = each %{$decode_json} ) {
            while ( my ( $r, $v ) = each %{ $decode_json->{$obj} } ) {
                $readings{ $obj . '-' . $r } = $v;
            }
        }
    }
    else {
        $readings{'error'} = q{aggregates response is not a Hash};
    }

    return \%readings;
}

sub Flatten_JSON {
    my ( $data, $prefix, $readings ) = @_;

    if ( ref($data) eq 'HASH' ) {
        for my $key ( keys %{$data} ) {
            my $k = $key;

            # Singularform gezielt nur bilden, wenn der Wert ein Array ist
            # (z.B. 'powerwalls' -> 'powerwall', 'checks' -> 'check')
            $k =~ s/s$//xg if ref( $data->{$key} ) eq 'ARRAY';

            my $new_prefix = $prefix eq '' ? $k : "${prefix}_${k}";
            Flatten_JSON( $data->{$key}, $new_prefix, $readings );
        }
    }
    elsif ( ref($data) eq 'ARRAY' ) {
        my $idx = 0;
        for my $item ( @{$data} ) {
            Flatten_JSON( $item, "${prefix}_${idx}", $readings );
            $idx++;
        }

# Der Root-Prefix für das Array wurde oben bereits zu 'powerwall' singularisiert
        $readings->{'numberOfWalls'} = $idx if $prefix eq 'powerwall';
    }
    elsif ( defined $data ) {
        $readings->{$prefix} = $data;
    }
}

sub ReadingsProcessing_Powerwalls {
    my ( $hash, $decode_json ) = @_;
    my %readings;

    if ( ref($decode_json) eq 'HASH' ) {
        Flatten_JSON( $decode_json, '', \%readings );
    }
    else {
        $readings{'error'} = q{powerwalls response is not a Hash};
    }

    return \%readings;
}

sub ReadingsProcessing_Site_Info {
    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};
    my %readings;

    if ( ref($decode_json) eq 'HASH' ) {
        while ( my $obj = each %{$decode_json} ) {
            while ( my ( $r, $v ) = each %{ $decode_json->{$obj} } ) {
                $readings{ $obj . '-' . $r } = $v;
            }
        }
    }
    else {
        $readings{'error'} = q{siteinfo response is not a Hash};
    }

    return \%readings;
}

sub ReadingsProcessing_Meters {
    my ( $hash, $decode_json, $type ) = @_;
    my %readings;

    if ( ref($decode_json) eq 'ARRAY' && scalar( @{$decode_json} ) > 0 ) {
        if ( ref( $decode_json->[0] ) eq 'HASH' ) {
            while ( my $obj = each %{ $decode_json->[0] } ) {
                if ( ref( $decode_json->[0]->{$obj} ) eq 'HASH' ) {
                    while ( my ( $r, $v ) =
                        each %{ $decode_json->[0]->{$obj} } )
                    {
                        if ( ref($v) ne 'HASH' ) {
                            $readings{ $obj . '-' . $r } = $v;
                        }
                        else {
                            while ( my ( $r2, $v2 ) =
                                each %{ $decode_json->[0]->{$obj}->{$r} } )
                            {
                                $readings{ $obj . '-' . $r . '-' . $r2 } = $v2;
                            }
                        }
                    }
                }
                elsif ( ref( $decode_json->[0]->{$obj} ) ne 'ARRAY' ) {
                    $readings{$obj} = $decode_json->[0]->{$obj};
                }
            }
        }
    }
    else {
        $readings{'error'} = "meters $type response is not an Array";
    }

    return \%readings;
}

sub CreateUri {
    my ( $hash, $path ) = @_;

    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $header =
      defined( $hash->{TOKEN} )
      ? 'Cookie: AuthCookie=' . $hash->{TOKEN}
      : undef;

    my $method = 'GET';
    my $uri    = (
          $path ne 'login'
        ? $host . '/api/' . $paths{$path}
        : $host . '/api/login/Basic'
    );
    my $data;

    if ( $path eq 'login' ) {
        $method = 'POST';
        $header = 'Content-Type: application/json';
        $data =
            '{"username":"customer","password":"'
          . $hash->{helper}->{passObj}->getReadPassword($name)
          . '","email":"'
          . ::AttrVal( $name, 'emailaddr', 'test@test.de' )
          . '","force_sm_off":false}';
    }
    elsif ($path eq 'powerwallsstop'
        || $path eq 'powerwallsrun' )
    {
        $uri = $host . '/api/' . $cmdPaths{$path};
    }

    return $uri, $method, $header, $data, $path;
}

sub Rename {
    my ( $new, $old ) = @_;

    my $hash = $defs{$new};

    my ( $passResp, $passErr );
    ( $passResp, $passErr ) =
      $hash->{helper}->{passObj}->setRename( $new, $old );

    ::Log3 $new, 1,
"TeslaPowerwall2AC ($new) - error while change the password hash after rename - $passErr"
      if (!defined($passResp)
        && defined($passErr) );

    ::Log3 $new, 1,
"TeslaPowerwall2AC ($new) - change password hash after rename successfully"
      if ( defined($passResp)
        && !defined($passErr) );

    return;
}

1;

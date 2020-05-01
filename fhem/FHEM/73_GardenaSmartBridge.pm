###############################################################################
#
# Developed with Kate
#
#  (c) 2017-2019 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Michael (mbrak)       Thanks for Commandref
#       - Matthias (Kenneth)    Thanks for Wiki entry
#       - BioS                  Thanks for predefined start points Code
#       - fettgu                Thanks for Debugging Irrigation Control data flow
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
##
##
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
#
#
###### Wichtige Notizen
#
#   apt-get install libio-socket-ssl-perl
#   http://www.dxsdata.com/de/2016/07/php-class-for-gardena-smart-system-api/
#
##
##

package FHEM::GardenaSmartBridge;
use GPUtils qw(GP_Import GP_Export);

# use Data::Dumper;    #only for Debugging

use strict;
use warnings;
use POSIX;
use FHEM::Meta;

use HttpUtils;

my $missingModul = '';
eval "use Encode qw(encode encode_utf8 decode_utf8);1"
  or $missingModul .= "Encode ";

# eval "use JSON;1"            || $missingModul .= 'JSON ';
eval "use IO::Socket::SSL;1" or $missingModul .= 'IO::Socket::SSL ';

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
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          Log3
          CommandAttr
          AttrVal
          ReadingsVal
          CommandDefMod
          modules
          setKeyValue
          getKeyValue
          getUniqueId
          RemoveInternalTimer
          readingFnAttributes
          InternalTimer
          defs
          init_done
          IsDisabled
          deviceEvents
          HttpUtils_NonblockingGet
          gettimeofday
          Dispatch)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      )
);

sub Initialize {
    my $hash = shift;

    # Provider
    $hash->{WriteFn}   = \&Write;
    $hash->{Clients}   = ':GardenaSmartDevice:';
    $hash->{MatchList} = { '1:GardenaSmartDevice' => '^{"id":".*' };

    # Consumer
    $hash->{SetFn}    = \&Set;
    $hash->{DefFn}    = \&Define;
    $hash->{UndefFn}  = \&Undef;
    $hash->{DeleteFn} = \&Delete;
    $hash->{RenameFn} = \&Rename;
    $hash->{NotifyFn} = \&Notify;

    $hash->{AttrFn} = \&Attr;
    $hash->{AttrList} =
        'debugJSON:0,1 '
      . 'disable:1 '
      . 'interval '
      . 'disabledForIntervals '
      . 'gardenaAccountEmail '
      . 'gardenaBaseURL '
      . $readingFnAttributes;
    $hash->{parseParams} = 1;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define {
    my $hash = shift // return;
    my $aArg = shift // return;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'too few parameters: define <NAME> GardenaSmartBridge'
      if ( scalar( @{$aArg} ) != 2 );
    return
        'Cannot define Gardena Bridge device. Perl modul '
      . ${missingModul}
      . ' is missing.'
      if ($missingModul);

    my $name = shift @$aArg;
    $hash->{BRIDGE} = 1;
    $hash->{URL} =
      AttrVal( $name, 'gardenaBaseURL',
        'https://sg-api.dss.husqvarnagroup.net' )
      . '/sg-1';
    $hash->{VERSION}   = version->parse($VERSION)->normal;
    $hash->{INTERVAL}  = 60;
    $hash->{NOTIFYDEV} = "global,$name";

    CommandAttr( undef, $name . ' room GardenaSmart' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    readingsSingleUpdate( $hash, 'token', 'none',        1 );
    readingsSingleUpdate( $hash, 'state', 'initialized', 1 );

    Log3 $name, 3, "GardenaSmartBridge ($name) - defined GardenaSmartBridge";

    $modules{GardenaSmartBridge}{defptr}{BRIDGE} = $hash;

    return;
}

sub Undef {
    my $hash = shift;
    my $name = shift;

    RemoveInternalTimer($hash);
    delete $modules{GardenaSmartBridge}{defptr}{BRIDGE}
      if ( defined( $modules{GardenaSmartBridge}{defptr}{BRIDGE} ) );

    return;
}

sub Delete {
    my $hash = shift;
    my $name = shift;

    setKeyValue( $hash->{TYPE} . '_' . $name . '_passwd', undef );
    return;
}

sub Attr {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' && $attrVal eq '1' ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate( $hash, 'state', 'inactive', 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabled";
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    elsif ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            return
"check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
              if ( $attrVal !~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabledForIntervals";
        }
        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    elsif ( $attrName eq 'interval' ) {
        if ( $cmd eq 'set' ) {
            RemoveInternalTimer($hash);
            return 'Interval must be greater than 0'
              if ( $attrVal == 0 );
            $hash->{INTERVAL} = $attrVal;
            Log3 $name, 3,
              "GardenaSmartBridge ($name) - set interval: $attrVal";
        }
        elsif ( $cmd eq 'del' ) {
            RemoveInternalTimer($hash);
            $hash->{INTERVAL} = 60;
            Log3 $name, 3,
"GardenaSmartBridge ($name) - delete User interval and set default: 60";
        }
    }
    elsif ( $attrName eq 'gardenaBaseURL' ) {
        if ( $cmd eq 'set' ) {
            $hash->{URL} = $attrVal . '/sg-1';
            Log3 $name, 3,
              "GardenaSmartBridge ($name) - set gardenaBaseURL to: $attrVal";
        }
        elsif ( $cmd eq 'del' ) {
            $hash->{URL} = 'https://sg-api.dss.husqvarnagroup.net/sg-1';
        }
    }

    return;
}

sub Notify {
    my $hash = shift // return;
    my $dev  = shift // return;

    my $name = $hash->{NAME};
    return if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    getToken($hash)
      if (
        (
            $devtype eq 'Global'
            && (
                grep /^INITIALIZED$/,
                @{$events} or grep /^REREADCFG$/,
                @{$events} or grep /^DEFINED.$name$/,
                @{$events} or grep /^MODIFIED.$name$/,
                @{$events} or grep /^ATTR.$name.gardenaAccountEmail.+/,
                @{$events}
            )
        )

        || (
            $devtype eq 'GardenaSmartBridge'
            && (
                grep /^gardenaAccountPassword.+/,
                @{$events} || ReadingsVal( '$devname', 'token', '' ) eq 'none'
            )
        )
      );

    getDevices($hash)
      if (
        $devtype eq 'Global'
        && (
            grep /^DELETEATTR.$name.disable$/,
            @{$events} or grep /^ATTR.$name.disable.0$/,
            @{$events} or grep /^DELETEATTR.$name.interval$/,
            @{$events} or grep /^ATTR.$name.interval.[0-9]+/,
            @{$events}
        )
        && $init_done
      );

    if (
        $devtype eq 'GardenaSmartBridge'
        && (
            grep /^state:.Connected$/,
            @{$events} or grep /^lastRequestState:.request_error$/,
            @{$events}
        )
      )
    {

        InternalTimer( gettimeofday() + $hash->{INTERVAL},
            "FHEM::GardenaSmartBridge::getDevices", $hash );
        Log3 $name, 4,
"GardenaSmartBridge ($name) - set internal timer function for recall getDevices sub";
    }

    return;
}

sub Set {
    my $hash = shift // return;
    my $aArg = shift // return;

    my $name = shift @$aArg // return;
    my $cmd  = shift @$aArg // return qq{"set $name" needs at least one argument};
    
#     Das Argument für das Passwort, also das Passwort an sich darf keine = enthalten!!!

    if ( lc $cmd eq 'getdevicesstate' ) {
        getDevices($hash);

    }
    elsif ( lc $cmd eq 'gettoken' ) {
        return "please set Attribut gardenaAccountEmail first"
          if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) eq 'none' );
        return "please set gardenaAccountPassword first"
          if ( not defined( ReadPassword( $hash, $name ) ) );
        return "token is up to date"
          if ( defined( $hash->{helper}{session_id} ) );

        getToken($hash);
    }
    elsif ( lc $cmd eq 'gardenaaccountpassword' ) {
        return "please set Attribut gardenaAccountEmail first"
          if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) eq 'none' );
        return "usage: $cmd <password>" if ( scalar( @{$aArg} ) != 1 );

        StorePassword( $hash, $name, $aArg->[0] );
    }
    elsif ( lc $cmd eq 'deleteaccountpassword' ) {
        return "usage: $cmd" if ( scalar( @{$aArg} ) != 0 );

        DeletePassword($hash);
    }
    else {

        my $list = "getDevicesState:noArg getToken:noArg"
          if ( defined( ReadPassword( $hash, $name ) ) );
        $list .= " gardenaAccountPassword"
          if ( not defined( ReadPassword( $hash, $name ) ) );
        $list .= " deleteAccountPassword:noArg"
          if ( defined( ReadPassword( $hash, $name ) ) );
        return "Unknown argument $cmd, choose one of $list";
    }

    return;
}

sub Write {
    my ( $hash, $payload, $deviceId, $abilities ) = @_;
    my $name = $hash->{NAME};

    my ( $session_id, $header, $uri, $method );

    ( $payload, $session_id, $header, $uri, $method, $deviceId, $abilities ) =
      createHttpValueStrings( $hash, $payload, $deviceId, $abilities );

    HttpUtils_NonblockingGet(
        {
            url       => $hash->{URL} . $uri,
            timeout   => 15,
            hash      => $hash,
            device_id => $deviceId,
            data      => $payload,
            method    => $method,
            header    => $header,
            doTrigger => 1,
            callback  => \&ErrorHandling
        }
    );

    Log3( $name, 4,
"GardenaSmartBridge ($name) - Send with URL: $hash->{URL}$uri, HEADER: secret!, DATA: secret!, METHOD: $method"
    );

#     Log3($name, 3,
#         "GardenaSmartBridge ($name) - Send with URL: $hash->{URL}$uri, HEADER: $header, DATA: $payload, METHOD: $method");

    return;
}

sub ErrorHandling {
    my $param = shift;
    my $err   = shift;
    my $data  = shift;

    my $hash  = $param->{hash};
    my $name  = $hash->{NAME};
    my $dhash = $hash;

    $dhash = $modules{GardenaSmartDevice}{defptr}{ $param->{'device_id'} }
      if ( defined( $param->{'device_id'} ) );

    my $dname = $dhash->{NAME};

    my $decode_json = eval { decode_json($data) };
    if ($@) {
        Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request";
    }

    if ( defined($err) ) {
        if ( $err ne "" ) {

            readingsBeginUpdate($dhash);
            readingsBulkUpdate( $dhash, "state", "$err" )
              if ( ReadingsVal( $dname, "state", 1 ) ne "initialized" );

            readingsBulkUpdate( $dhash, "lastRequestState", "request_error",
                1 );

            if ( $err =~ /timed out/ ) {

                Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: connect to gardena cloud is timed out. check network";
            }

            elsif ($err =~ /Keine Route zum Zielrechner/
                || $err =~ /no route to target/ )
            {

                Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: no route to target. bad network configuration or network is down";

            }
            else {

                Log3 $dname, 5,
                  "GardenaSmartBridge ($dname) - RequestERROR: $err";
            }

            readingsEndUpdate( $dhash, 1 );

            Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: GardenaSmartBridge RequestErrorHandling: error while requesting gardena cloud: $err";

            delete $dhash->{helper}{deviceAction}
              if ( defined( $dhash->{helper}{deviceAction} ) );

            return;
        }
    }

    if ( $data eq "" && exists( $param->{code} ) && $param->{code} != 200 ) {

        readingsBeginUpdate($dhash);
        readingsBulkUpdate( $dhash, "state", $param->{code}, 1 )
          if ( ReadingsVal( $dname, "state", 1 ) ne "initialized" );

        readingsBulkUpdateIfChanged( $dhash, "lastRequestState",
            "request_error", 1 );

        if ( $param->{code} == 401 && $hash eq $dhash ) {

            if ( ReadingsVal( $dname, 'token', 'none' ) eq 'none' ) {
                readingsBulkUpdate( $dhash, "state", "no token available", 1 );
                readingsBulkUpdateIfChanged( $dhash, "lastRequestState",
                    "no token available", 1 );
            }

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: " . $param->{code};

        }
        elsif ($param->{code} == 204
            && $dhash ne $hash
            && defined( $dhash->{helper}{deviceAction} ) )
        {

            readingsBulkUpdate( $dhash, "state", "the command is processed",
                1 );
            InternalTimer(
                gettimeofday() + 5,
                "FHEM::GardenaSmartBridge::getDevices",
                $hash, 1
            );

        }
        elsif ( $param->{code} != 200 ) {

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: " . $param->{code};
        }

        readingsEndUpdate( $dhash, 1 );

        Log3 $dname, 5,
            "GardenaSmartBridge ($dname) - RequestERROR: received http code "
          . $param->{code}
          . " without any data after requesting gardena cloud";

        delete $dhash->{helper}{deviceAction}
          if ( defined( $dhash->{helper}{deviceAction} ) );

        return;
    }

    if (
        $data =~ /Error/
        || (   defined($decode_json)
            && ref($decode_json) eq 'HASH'
            && defined( $decode_json->{errors} ) )
      )
    {
        readingsBeginUpdate($dhash);
        readingsBulkUpdate( $dhash, "state", $param->{code}, 1 )
          if ( ReadingsVal( $dname, "state", 0 ) ne "initialized" );

        readingsBulkUpdate( $dhash, "lastRequestState", "request_error", 1 );

        if ( $param->{code} == 400 ) {
            if ($decode_json) {
                if ( ref( $decode_json->{errors} ) eq "ARRAY"
                    && defined( $decode_json->{errors} ) )
                {
                    readingsBulkUpdate(
                        $dhash,
                        "state",
                        $decode_json->{errors}[0]{error} . ' '
                          . $decode_json->{errors}[0]{attribute},
                        1
                    );
                    readingsBulkUpdate(
                        $dhash,
                        "lastRequestState",
                        $decode_json->{errors}[0]{error} . ' '
                          . $decode_json->{errors}[0]{attribute},
                        1
                    );
                    Log3 $dname, 5,
                        "GardenaSmartBridge ($dname) - RequestERROR: "
                      . $decode_json->{errors}[0]{error} . " "
                      . $decode_json->{errors}[0]{attribute};
                }
            }
            else {
                readingsBulkUpdate( $dhash, "lastRequestState",
                    "Error 400 Bad Request", 1 );
                Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: Error 400 Bad Request";
            }
        }
        elsif ( $param->{code} == 503 ) {

            Log3 $dname, 5,
"GardenaSmartBridge ($dname) - RequestERROR: Error 503 Service Unavailable";
            readingsBulkUpdate( $dhash, "state", "Service Unavailable", 1 );
            readingsBulkUpdate( $dhash, "lastRequestState",
                "Error 503 Service Unavailable", 1 );

        }
        elsif ( $param->{code} == 404 ) {
            if ( defined( $dhash->{helper}{deviceAction} ) && $dhash ne $hash )
            {
                readingsBulkUpdate( $dhash, "state", "device Id not found", 1 );
                readingsBulkUpdate( $dhash, "lastRequestState",
                    "device id not found", 1 );
            }

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: Error 404 Not Found";

        }
        elsif ( $param->{code} == 500 ) {

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: check the ???";

        }
        else {

            Log3 $dname, 5,
              "GardenaSmartBridge ($dname) - RequestERROR: http error "
              . $param->{code};
        }

        readingsEndUpdate( $dhash, 1 );

        Log3 $dname, 5,
            "GardenaSmartBridge ($dname) - RequestERROR: received http code "
          . $param->{code}
          . " receive Error after requesting gardena cloud";

        delete $dhash->{helper}{deviceAction}
          if ( defined( $dhash->{helper}{deviceAction} ) );

        return;
    }

    readingsSingleUpdate( $hash, 'state', 'Connected', 1 )
      if ( defined( $hash->{helper}{locations_id} ) );
    ResponseProcessing( $hash, $data )
      if ( ref($decode_json) eq 'HASH' );

    return;
}

sub ResponseProcessing {
    my $hash = shift;
    my $json = shift;

    my $name = $hash->{NAME};

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3 $name, 3,
          "GardenaSmartBridge ($name) - JSON error while request: $@";

        if ( AttrVal( $name, 'debugJSON', 0 ) == 1 ) {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, 'JSON_ERROR',        $@,    1 );
            readingsBulkUpdate( $hash, 'JSON_ERROR_STRING', $json, 1 );
            readingsEndUpdate( $hash, 1 );
        }
    }

    #     print Dumper $decode_json;

    if ( defined( $decode_json->{sessions} ) && $decode_json->{sessions} ) {

        $hash->{helper}{session_id} = $decode_json->{sessions}{token};
        $hash->{helper}{user_id}    = $decode_json->{sessions}{user_id};

        Write( $hash, undef, undef, undef );
        Log3 $name, 3, "GardenaSmartBridge ($name) - fetch locations id";
        readingsSingleUpdate( $hash, 'token', $hash->{helper}{session_id}, 1 );

        return;

    }
    elsif ( !defined( $hash->{helper}{locations_id} )
        && defined( $decode_json->{locations} )
        && ref( $decode_json->{locations} ) eq 'ARRAY'
        && scalar( @{ $decode_json->{locations} } ) > 0 )
    {
        for my $location ( @{ $decode_json->{locations} } ) {

            $hash->{helper}{locations_id} = $location->{id};

            WriteReadings( $hash, $location );
        }

        Log3 $name, 3,
          "GardenaSmartBridge ($name) - processed locations id. ID is "
          . $hash->{helper}{locations_id};
        Write( $hash, undef, undef, undef );

        return;
    }
    elsif (defined( $decode_json->{devices} )
        && ref( $decode_json->{devices} ) eq 'ARRAY'
        && scalar( @{ $decode_json->{devices} } ) > 0 )
    {

        my @buffer = split( '"devices":\[', $json );

        my ( $json, $tail ) = ParseJSON( $hash, $buffer[1] );

        while ($json) {

            Log3 $name, 5,
                "GardenaSmartBridge ($name) - Decoding JSON message. Length: "
              . length($json)
              . " Content: "
              . $json;
            Log3 $name, 5,
                "GardenaSmartBridge ($name) - Vor Sub: Laenge JSON: "
              . length($json)
              . " Content: "
              . $json
              . " Tail: "
              . $tail;

            if ( defined($tail) and $tail ) {
                $decode_json = eval { decode_json($json) };
                if ($@) {
                    Log3 $name, 5,
"GardenaSmartBridge ($name) - JSON error while request: $@";
                }

                Dispatch( $hash, $json, undef )
                  if ( $decode_json->{category} ne 'gateway' );
                WriteReadings( $hash, $decode_json )
                  if ( defined( $decode_json->{category} )
                    && $decode_json->{category} eq 'gateway' );
            }

            ( $json, $tail ) = ParseJSON( $hash, $tail );

            Log3 $name, 5,
                "GardenaSmartBridge ($name) - Nach Sub: Laenge JSON: "
              . length($json)
              . " Content: "
              . $json
              . " Tail: "
              . $tail;
        }

        return;
    }

    Log3 $name, 3, "GardenaSmartBridge ($name) - no Match for processing data";

    return;
}

sub WriteReadings {
    my $hash        = shift;
    my $decode_json = shift;

    #     print Dumper $decode_json;

    my $name = $hash->{NAME};

    if (   defined( $decode_json->{id} )
        && $decode_json->{id}
        && defined( $decode_json->{name} )
        && $decode_json->{name} )
    {
        readingsBeginUpdate($hash);
        if ( $decode_json->{id} eq $hash->{helper}{locations_id} ) {

            readingsBulkUpdateIfChanged( $hash, 'name', $decode_json->{name} );
            readingsBulkUpdateIfChanged( $hash, 'authorized_user_ids',
                scalar( @{ $decode_json->{authorized_user_ids} } ) );
            readingsBulkUpdateIfChanged( $hash, 'devices',
                scalar( @{ $decode_json->{devices} } ) );

            while ( ( my ( $t, $v ) ) = each %{ $decode_json->{geo_position} } )
            {
                $v = encode_utf8($v);
                readingsBulkUpdateIfChanged( $hash, $t, $v );
            }

            readingsBulkUpdateIfChanged( $hash, 'zones',
                scalar( @{ $decode_json->{zones} } ) );
        }
        elsif ($decode_json->{id} ne $hash->{helper}{locations_id}
            && ref( $decode_json->{abilities} ) eq 'ARRAY'
            && ref( $decode_json->{abilities}[0]{properties} ) eq 'ARRAY' )
        {
            my $properties =
              scalar( @{ $decode_json->{abilities}[0]{properties} } );

            do {
                while ( ( my ( $t, $v ) ) =
                    each
                    %{ $decode_json->{abilities}[0]{properties}[$properties] } )
                {
                    next
                      if ( ref($v) eq 'ARRAY' );

                    #$v = encode_utf8($v);
                    readingsBulkUpdateIfChanged(
                        $hash,
                        $decode_json->{abilities}[0]{properties}[$properties]
                          {name} . '-' . $t,
                        $v
                      )
                      if (
                        $decode_json->{abilities}[0]{properties}[$properties]
                        {name} ne 'ethernet_status'
                        || $decode_json->{abilities}[0]{properties}
                        [$properties]{name} ne 'wifi_status' );

                    if (
                        (
                            $decode_json->{abilities}[0]{properties}
                            [$properties]{name} eq 'ethernet_status'
                            || $decode_json->{abilities}[0]{properties}
                            [$properties]{name} eq 'wifi_status'
                        )
                        && ref($v) eq 'HASH'
                      )
                    {
                        if ( $decode_json->{abilities}[0]{properties}
                            [$properties]{name} eq 'ethernet_status' )
                        {
                            readingsBulkUpdateIfChanged( $hash,
                                'ethernet_status-mac', $v->{mac} );
                            readingsBulkUpdateIfChanged( $hash,
                                'ethernet_status-ip', $v->{ip} )
                              if ( ref( $v->{ip} ) ne 'HASH' );
                            readingsBulkUpdateIfChanged( $hash,
                                'ethernet_status-isconnected',
                                $v->{isconnected} );
                        }
                        elsif ( $decode_json->{abilities}[0]{properties}
                            [$properties]{name} eq 'wifi_status' )
                        {
                            readingsBulkUpdateIfChanged( $hash,
                                'wifi_status-ssid', $v->{ssid} );
                            readingsBulkUpdateIfChanged( $hash,
                                'wifi_status-mac', $v->{mac} );
                            readingsBulkUpdateIfChanged( $hash,
                                'wifi_status-ip', $v->{ip} )
                              if ( ref( $v->{ip} ) ne 'HASH' );
                            readingsBulkUpdateIfChanged( $hash,
                                'wifi_status-isconnected', $v->{isconnected} );
                            readingsBulkUpdateIfChanged( $hash,
                                'wifi_status-signal', $v->{signal} );
                        }
                    }
                }
                $properties--;

            } while ( $properties >= 0 );
        }
        readingsEndUpdate( $hash, 1 );
    }

    Log3 $name, 4, "GardenaSmartBridge ($name) - readings would be written";

    return;
}

####################################
####################################
#### my little helpers Sub's #######

sub getDevices {
    my $hash = shift;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);

    if ( not IsDisabled($name) ) {

        Write( $hash, undef, undef, undef );
        Log3 $name, 4,
          "GardenaSmartBridge ($name) - fetch device list and device states";
    }
    else {

        readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
        Log3 $name, 3, "GardenaSmartBridge ($name) - device is disabled";
    }

    return;
}

sub getToken {
    my $hash = shift;

    my $name = $hash->{NAME};

    return readingsSingleUpdate( $hash, 'state',
        'please set Attribut gardenaAccountEmail first', 1 )
      if ( AttrVal( $name, 'gardenaAccountEmail', 'none' ) eq 'none' );
    return readingsSingleUpdate( $hash, 'state',
        'please set gardena account password first', 1 )
      if ( !defined( ReadPassword( $hash, $name ) ) );
    readingsSingleUpdate( $hash, 'state', 'get token', 1 );

    delete $hash->{helper}{session_id}
      if ( defined( $hash->{helper}{session_id} )
        && $hash->{helper}{session_id} );
    delete $hash->{helper}{user_id}
      if ( defined( $hash->{helper}{user_id} ) && $hash->{helper}{user_id} );
    delete $hash->{helper}{locations_id}
      if ( defined( $hash->{helper}{locations_id} )
        && $hash->{helper}{locations_id} );

    Write(
        $hash,
        '"sessions": {"email": "'
          . AttrVal( $name, 'gardenaAccountEmail', 'none' )
          . '","password": "'
          . ReadPassword( $hash, $name ) . '"}',
        undef,
        undef
    );

    Log3 $name, 3,
"GardenaSmartBridge ($name) - send credentials to fetch Token and locationId";

    return;
}

sub StorePassword {
    my $hash     = shift;
    my $name     = shift;
    my $password = shift;

    my $index   = $hash->{TYPE} . "_" . $name . "_passwd";
    my $key     = getUniqueId() . $index;
    my $enc_pwd = "";

    if ( eval "use Digest::MD5;1" ) {

        $key = Digest::MD5::md5_hex( unpack "H*", $key );
        $key .= Digest::MD5::md5_hex($key);
    }

    for my $char ( split //, $password ) {

        my $encode = chop($key);
        $enc_pwd .= sprintf( "%.2x", ord($char) ^ ord($encode) );
        $key = $encode . $key;
    }

    my $err = setKeyValue( $index, $enc_pwd );
    return "error while saving the password - $err" if ( defined($err) );

    return "password successfully saved";
}

sub ReadPassword {
    my $hash = shift;
    my $name = shift;

    my $index = $hash->{TYPE} . "_" . $name . "_passwd";
    my $key   = getUniqueId() . $index;
    my ( $password, $err );

    Log3 $name, 4, "GardenaSmartBridge ($name) - Read password from file";

    ( $err, $password ) = getKeyValue($index);

    if ( defined($err) ) {

        Log3 $name, 3,
"GardenaSmartBridge ($name) - unable to read password from file: $err";
        return undef;

    }

    if ( defined($password) ) {
        if ( eval "use Digest::MD5;1" ) {

            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = '';

        for my $char ( map { pack( 'C', hex($_) ) } ( $password =~ /(..)/g ) ) {

            my $decode = chop($key);
            $dec_pwd .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }

        return $dec_pwd;

    }
    else {

        Log3 $name, 3, "GardenaSmartBridge ($name) - No password in file";
        return undef;
    }

    return;
}

sub Rename {
    my $new = shift;
    my $old = shift;

    my $hash = $defs{$new};

    StorePassword( $hash, $new, ReadPassword( $hash, $old ) );
    setKeyValue( $hash->{TYPE} . "_" . $old . "_passwd", undef );

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
            if ( $open == $close && $open > 0 ) {
                $tail .= $c;
                Log3 $name, 5,
                  "GardenaSmartBridge ($name) - $open == $close and $open > 0";

            }
            elsif ( ( $open == $close ) && ( $c ne '{' ) ) {

                Log3 $name, 5,
"GardenaSmartBridge ($name) - Garbage character before message: "
                  . $c;

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

    Log3 $name, 5,
      "GardenaSmartBridge ($name) - return msg: $msg and tail: $tail";
    return ( $msg, $tail );
}

sub createHttpValueStrings {
    my ( $hash, $payload, $deviceId, $abilities ) = @_;

    my $session_id = $hash->{helper}{session_id};
    my $header     = "Content-Type: application/json";
    my $uri        = '';
    my $method     = 'POST';
    $header .= "\r\nX-Session: $session_id"
      if ( defined( $hash->{helper}{session_id} ) );
    $payload = '{' . $payload . '}' if ( defined($payload) );
    $payload = '{}' if ( !defined($payload) );

    if ( $payload eq '{}' ) {
        $method = 'GET';
        $uri .= '/locations/?user_id=' . $hash->{helper}{user_id}
          if ( exists( $hash->{helper}{user_id} )
            && !defined( $hash->{helper}{locations_id} ) );
        readingsSingleUpdate( $hash, 'state', 'fetch locationId', 1 )
          if ( !defined( $hash->{helper}{locations_id} ) );
        $uri .= '/sessions' if ( !defined( $hash->{helper}{session_id} ) );
        $uri .= '/devices'
          if (!defined($abilities)
            && defined( $hash->{helper}{locations_id} ) );
    }

    $uri .= '/sessions' if ( !defined( $hash->{helper}{session_id} ) );

    if ( defined( $hash->{helper}{locations_id} ) ) {
        if ( defined($abilities) && $abilities eq 'mower_settings' ) {

            $method = 'PUT';
            my $dhash = $modules{GardenaSmartDevice}{defptr}{$deviceId};
            $uri .=
                '/devices/'
              . $deviceId
              . '/settings/'
              . $dhash->{helper}{STARTINGPOINTID}
              if ( defined($abilities)
                && defined($payload)
                && $abilities eq 'mower_settings' );

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'watering' )
        {
            my $valve_id;
            $method = 'PUT';

            if ( $payload =~ m#watering_timer_(\d)# ) {
                $valve_id = $1;
            }
            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . '/properties/watering_timer_'
              . $valve_id;

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'manual_watering' )
        {
            my $valve_id;
            $method = 'PUT';

            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . '/properties/manual_watering_timer';

        }
        elsif (defined($abilities)
            && defined($payload)
            && $abilities eq 'power' )
        {
            my $valve_id;
            $method = 'PUT';

            $uri .=
                '/devices/'
              . $deviceId
              . '/abilities/'
              . $abilities
              . '/properties/power_timer';

        }
        else {
            $uri .=
              '/devices/' . $deviceId . '/abilities/' . $abilities . '/command'
              if ( defined($abilities) && defined($payload) );
        }

        $uri .= '?locationId=' . $hash->{helper}{locations_id};
    }

    return ( $payload, $session_id, $header, $uri, $method, $deviceId,
        $abilities );
}

sub DeletePassword {
    my $hash = shift;

    setKeyValue( $hash->{TYPE} . "_" . $hash->{NAME} . "_passwd", undef );

    return;
}

1;

=pod

=item device
=item summary       Modul to communicate with the GardenaCloud
=item summary_DE    Modul zur Datenübertragung zur GardenaCloud

=begin html

<a name="GardenaSmartBridge"></a>
<h3>GardenaSmartBridge</h3>
<ul>
  <u><b>Prerequisite</b></u>
  <br><br>
  <li>In combination with GardenaSmartDevice this FHEM Module controls the communication between the GardenaCloud and connected Devices like Mover, Watering_Computer, Temperature_Sensors</li>
  <li>Installation of the following packages: apt-get install libio-socket-ssl-perl</li>
  <li>The Gardena-Gateway and all connected Devices must be correctly installed in the GardenaAPP</li>
</ul>
<br>
<a name="GardenaSmartBridgedefine"></a>
<b>Define</b>
<ul><br>
  <code>define &lt;name&gt; GardenaSmartBridge</code>
  <br><br>
  Beispiel:
  <ul><br>
    <code>define Gardena_Bridge GardenaSmartBridge</code><br>
  </ul>
  <br>
  The GardenaSmartBridge device is created in the room GardenaSmart, then the devices of Your system are recognized automatically and created in FHEM. From now on the devices can be controlled and changes in the GardenaAPP are synchronized with the state and readings of the devices.
  <br><br>
  <a name="GardenaSmartBridgereadings"></a>
  <br><br>
  <b>Readings</b>
  <ul>
    <li>address - your Adress (Longversion)</li>
    <li>authorized_user_ids - </li>
    <li>city - Zip, City</li>
    <li>devices - Number of Devices in the Cloud (Gateway included)</li>
    <li>lastRequestState - Last Status Result</li>
    <li>latitude - Breitengrad des Grundstücks</li>
    <li>longitude - Längengrad des Grundstücks</li>
    <li>name - Name of your Garden – Default „My Garden“</li>
    <li>state - State of the Bridge</li>
    <li>token - SessionID</li>
    <li>zones - </li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeset"></a>
  <b>set</b>
  <ul>
    <li>getDeviceState - Starts a Datarequest</li>
    <li>getToken - Gets a new Session-ID</li>
    <li>gardenaAccountPassword - Passwort which was used in the GardenaAPP</li>
    <li>deleteAccountPassword - delete the password from store</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeattributes"></a>
  <b>Attributes</b>
  <ul>
    <li>debugJSON - </li>
    <li>disable - Disables the Bridge</li>
    <li>interval - Interval in seconds (Default=60)</li>
    <li>gardenaAccountEmail - Email Adresse which was used in the GardenaAPP</li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="GardenaSmartBridge"></a>
<h3>GardenaSmartBridge</h3>
<ul>
  <u><b>Voraussetzungen</b></u>
  <br><br>
  <li>Zusammen mit dem Device GardenaSmartDevice stellt dieses FHEM Modul die Kommunikation zwischen der GardenaCloud und Fhem her. Es k&ouml;nnen damit Rasenm&auml;her, Bew&auml;sserungscomputer und Bodensensoren überwacht und gesteuert werden</li>
  <li>Das Perl-Modul "SSL Packet" wird ben&ouml;tigt.</li>
  <li>Unter Debian (basierten) System, kann dies mittels "apt-get install libio-socket-ssl-perl" installiert werden.</li>
  <li>Das Gardena-Gateway und alle damit verbundenen Ger&auml;te und Sensoren m&uuml;ssen vorab in der GardenaApp eingerichtet sein.</li>
</ul>
<br>
<a name="GardenaSmartBridgedefine"></a>
<b>Define</b>
<ul><br>
  <code>define &lt;name&gt; GardenaSmartBridge</code>
  <br><br>
  Beispiel:
  <ul><br>
    <code>define Gardena_Bridge GardenaSmartBridge</code><br>
  </ul>
  <br>
  Das Bridge Device wird im Raum GardenaSmart angelegt und danach erfolgt das Einlesen und automatische Anlegen der Ger&auml;te. Von nun an k&ouml;nnen die eingebundenen Ger&auml;te gesteuert werden. &Auml;nderungen in der APP werden mit den Readings und dem Status syncronisiert.
  <br><br>
  <a name="GardenaSmartBridgereadings"></a>
  <br><br>
  <b>Readings</b>
  <ul>
    <li>address - Adresse, welche in der App eingetragen wurde (Langversion)</li>
    <li>authorized_user_ids - </li>
    <li>city - PLZ, Stadt</li>
    <li>devices - Anzahl der Ger&auml;te, welche in der GardenaCloud angemeldet sind (Gateway z&auml;hlt mit)</li>
    <li>lastRequestState - Letzter abgefragter Status der Bridge</li>
    <li>latitude - Breitengrad des Grundst&uuml;cks</li>
    <li>longitude - Längengrad des Grundst&uuml;cks</li>
    <li>name - Name für das Grundst&uuml;ck – Default „My Garden“</li>
    <li>state - Status der Bridge</li>
    <li>token - SessionID</li>
    <li>zones - </li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeset"></a>
  <b>set</b>
  <ul>
    <li>getDeviceState - Startet eine Abfrage der Daten.</li>
    <li>getToken - Holt eine neue Session-ID</li>
    <li>gardenaAccountPassword - Passwort, welches in der GardenaApp verwendet wurde</li>
    <li>deleteAccountPassword - l&oml;scht das Passwort aus dem Passwortstore</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeattributes"></a>
  <b>Attribute</b>
  <ul>
    <li>debugJSON - JSON Fehlermeldungen</li>
    <li>disable - Schaltet die Datenübertragung der Bridge ab</li>
    <li>interval - Abfrageinterval in Sekunden (default: 300)</li>
    <li>gardenaAccountEmail - Email Adresse, die auch in der GardenaApp verwendet wurde</li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 73_GardenaSmartBridge.pm
{
  "abstract": "Modul to communicate with the GardenaCloud",
  "x_lang": {
    "de": {
      "abstract": "Modul zur Datenübertragung zur GardenaCloud"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "Garden",
    "Gardena",
    "Smart"
  ],
  "release_status": "stable",
  "license": "GPL_2",
  "version": "v2.0.2",
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
        "IO::Socket::SSL": 0,
        "JSON": 0,
        "HttpUtils": 0,
        "Encode": 0
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

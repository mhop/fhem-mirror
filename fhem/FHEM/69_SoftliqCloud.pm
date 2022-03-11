# $Id$
##############################################################################
#
#     98_SoftliqCloud.pm
#     An FHEM Perl module that retrieves information from SoftliqCloud
#
#     Copyright by KernSani
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#   Changelog:
#   0.1.07: - 2021-05-08 - Optimize garbage JSON processing 
#   0.1.06: - 2021-04-26 - Split JSON strings to avoid processing multiple root nodes
#   0.1.05: Fixed setting numeric parameters
#   0.1.04: ANother fix to avoid "garbage" in JSON
#   0.1.03: Improve error handling
#           Hide access- & refreshToken
#   0.1.02: Suppress Log message "opening device..."
#   0.1.01: Small Fix to avoid "garbage" leading to invalid JSON
#   0.1.00: Initial Release
##############################################################################
##############################################################################
#   Todo:
#   * identify more parameters
#
##############################################################################
package main;
use strict;
use warnings;

package FHEM::Gruenbeck::SoftliqCloud;

use List::Util qw(any first);
use HttpUtils;
use Data::Dumper;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);
use utf8;
use POSIX qw( strftime );
use DevIo;
use B qw(svref_2object);
use utf8;
use Digest::MD5 qw(md5);

use FHEM::Core::Authentication::Passwords qw(:ALL);

my $version = "0.1.07";

my $missingModul = '';
eval 'use MIME::Base64::URLSafe;1'   or $missingModul .= 'MIME::Base64::URLSafe ';
eval 'use Digest::SHA qw(sha256);1;' or $missingModul .= 'Digest::SHA ';

#eval 'use Protocol::WebSocket::Client;1' or $missingModul .= 'Protocol::WebSocket::Client ';

# Taken from RichardCZ https://gl.petatech.eu/root/HomeBot/snippets/2
my $got_module = use_module_prio(
    {   wanted   => [ 'encode_json', 'decode_json' ],
        priority => [
            qw(JSON::MaybeXS
                Cpanel::JSON::XS
                JSON::XS JSON::PP
                JSON::backportPP)
        ],
    }
);
if ( !$got_module ) {
    $missingModul .= 'a JSON module (e.g. JSON::XS) ';
}

# Readonly is recommended, but requires additional module
use constant {
    SQ_MINIMUM_INTERVAL => 300,
    LOG_CRITICAL        => 0,
    LOG_ERROR           => 1,
    LOG_WARNING         => 2,
    LOG_SEND            => 3,
    LOG_RECEIVE         => 4,
    LOG_DEBUG           => 5,
    TCPPACKETSIZE       => 16384,
};
my $EMPTY = q{};
my $SPACE = q{ };
my $COMMA = q{,};

## Import der FHEM Funktionen
BEGIN {
    GP_Import(
        qw(
            AttrVal
            AttrNum
            CommandDeleteReading
            InternalTimer
            InternalVal
            readingsSingleUpdate
            readingsBulkUpdate
            readingsBulkUpdateIfChanged
            readingsBeginUpdate
            readingsDelete
            readingsEndUpdate
            ReadingsNum
            ReadingsVal
            RemoveInternalTimer
            Log3
            gettimeofday
            deviceEvents
            time_str2num
            latin1ToUtf8
            IsDisabled
            HttpUtils_NonblockingGet
            HttpUtils_BlockingGet
            DevIo_IsOpen
            DevIo_CloseDev
            DevIo_OpenDev
            DevIo_SimpleRead
            DevIo_SimpleWrite
            init_done
            readingFnAttributes
            setKeyValue
            getKeyValue
            getUniqueId
            defs
            HOURSECONDS
            MINUTESECONDS
            makeReadingName
            )
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
        Initialize
        )
);

my %paramTexts = (
    pbuzzer                => 'Audiosignal an/aus',
    pbuzzfrom              => 'Audiosignal von (Uhrzeit)',
    pbuzzto                => 'Audiosignal bis (Uhrzeit)',
    pallowemail            => 'Email-Benachrichtigung an/aus',
    pallowpushnotification => 'Push-Benachrichtigung an/aus',
    pmode                  => 'Arbeitsweise',
    pmodemo                => 'Arbeitsweise Montag (Individual)',
    pmodetu                => 'Arbeitsweise Dienstag (Individual)',
    pmodewe                => 'Arbeitsweise Mittwoch (Individual)',
    pmodeth                => 'Arbeitsweise Donnerstag (Individual)',
    pmodefr                => 'Arbeitsweise Freitag (Individual)',
    pmodesa                => 'Arbeitsweise Samstag (Individual)',
    pmodesu                => 'Arbeitsweise Sontag (Individual)',
    pname                  => 'Service - Name',
    ptelnr                 => 'Service - Tel.Nr.',
    pmailadress            => 'Service - EMail',
    pmaintint              => 'Service - Wartungsintervall',
    pregmode               => 'Regeneration - Regenerierungszeitpunkt',
    pregmo1                => 'Regeneration - Regenerierungszeitpunkt Montag 1',
    pregmo2                => 'Regeneration - Regenerierungszeitpunkt Montag 2',
    pregmo3                => 'Regeneration - Regenerierungszeitpunkt Montag 3',
    pregtu1                => 'Regeneration - Regenerierungszeitpunkt Dienstag 1',
    pregtu2                => 'Regeneration - Regenerierungszeitpunkt Dienstag 2',
    pregtu3                => 'Regeneration - Regenerierungszeitpunkt Dienstag 3',
    pregwe1                => 'Regeneration - Regenerierungszeitpunkt Mittwoch 1',
    pregwe2                => 'Regeneration - Regenerierungszeitpunkt Mittwoch 2',
    pregwe3                => 'Regeneration - Regenerierungszeitpunkt Mittwoch 3',
    pregth1                => 'Regeneration - Regenerierungszeitpunkt Donnerstag 1',
    pregth2                => 'Regeneration - Regenerierungszeitpunkt Donnerstag 2',
    pregth3                => 'Regeneration - Regenerierungszeitpunkt Donnerstag 3',
    pregfr1                => 'Regeneration - Regenerierungszeitpunkt Freitag 1',
    pregfr2                => 'Regeneration - Regenerierungszeitpunkt Freitag  2',
    pregfr3                => 'Regeneration - Regenerierungszeitpunkt Freitag  3',
    pregsa1                => 'Regeneration - Regenerierungszeitpunkt Samstag 1',
    pregsa2                => 'Regeneration - Regenerierungszeitpunkt Samstag 2',
    pregsa3                => 'Regeneration - Regenerierungszeitpunkt Samstag 3',
    pregsu1                => 'Regeneration - Regenerierungszeitpunkt Sonntag 1',
    pregsu2                => 'Regeneration - Regenerierungszeitpunkt Sonntag 2',
    pregsu3                => 'Regeneration - Regenerierungszeitpunkt Sonntag 3',
    prawhard               => 'Wasser - Rohwasserh&auml;rte',
    phunit                 => 'Wasser - Einheit ',
);
my %paramValueMap = (
    pmode => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
        '4' => 'Individual'
    },
    pmodemo => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pmodetu => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pmodewe => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pmodeth => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pmodefr => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pmodesa => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pmodesu => {
        '1' => 'Eco',
        '2' => 'Comfort',
        '3' => 'Power',
    },
    pregmode => {
        '0' => 'Auto',
        '1' => 'Fix'
    },
    phunit => {
        '1' => '&deg;dH',
        '2' => '&deg;fH',
        '3' => '&deg;e',
        '4' => 'mol/m&sup3;',
        '5' => 'ppm'
        }

);

sub Initialize {
    my ($hash) = @_;

    $hash->{SetFn}    = \&Set;
    $hash->{GetFn}    = \&Get;
    $hash->{DefFn}    = \&Define;
    $hash->{ReadyFn}  = \&Ready;
    $hash->{ReadFn}   = \&wsReadDevIo;
    $hash->{NotifyFn} = \&Notify;
    $hash->{UndefFn}  = \&Undefine;
    $hash->{AttrFn}   = \&Attr;
    $hash->{RenameFn} = \&Rename;
    my @SQattr = ( "sq_interval", "disable:0,1", "sq_duplex:0,1" );

    $hash->{AttrList} = join( $SPACE, @SQattr ) . $SPACE . $readingFnAttributes;

    #$hash->{AttrList} = $::readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}
###################################
sub Define {
    my $hash = shift;
    my $def  = shift;

    return $@ if ( !FHEM::Meta::SetInternals($hash) );

    my @args = split m{\s+}, $def;

    return "Cannot define device. Please install perl modules $missingModul."
        if ($missingModul);

    my $usage = qq (syntax: define <name> SoftliqCloud <loginName>);
    return $usage if ( @args != 3 );

    my ( $name, $type, $user ) = @args;

    Log3 $name, LOG_SEND, "[$name] SoftliqCloud defined $name";

    $hash->{NAME}    = $name;
    $hash->{USER}    = $user;
    $hash->{VERSION} = $version;

    if ( ReadingsVal( $name, "accessToken", $EMPTY ) ne $EMPTY ) {
        CommandDeleteReading( undef, $name . " accessToken" );
    }
    if ( ReadingsVal( $name, "refreshToken", $EMPTY ) ne $EMPTY ) {
        CommandDeleteReading( undef, $name . " refreshToken" );
    }

    $hash->{helper}->{passObj} = FHEM::Core::Authentication::Passwords->new( $hash->{TYPE} );

    # get password form old storage and save to new format
    if ( !defined( ReadPassword($hash) ) ) {
        if ( defined( ReadPasswordOld($hash) ) ) {
            my ( $passResp, $passErr ) = $hash->{helper}->{passObj}->setStorePassword( $name, ReadPasswordOld($hash) );
            if ( defined($passErr) ) {
                Log3( $name, LOG_CRITICAL, qq([$name] Error while saving the password - $passErr) );
            }
        }
    }

    #start timer
    if ( !IsDisabled($name) && $init_done && defined( ReadPassword($hash) ) ) {
        my $next = int( gettimeofday() ) + 1;
        InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
    }
    if ( IsDisabled($name) ) {
        readingsSingleUpdate( $hash, "state", "inactive", 1 );
        $hash->{helper}{DISABLED} = 1;
    }
    return;
}
###################################
sub Undefine {
    my $hash = shift;
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    return;
}
###################################
sub Notify {
    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};               # own name / hash
    my $events = deviceEvents( $dev, 1 );

    return if ( IsDisabled($name) );
    return if ( !any {m/^INITIALIZED|REREADCFG$/xsm} @{$events} );

    my $next = int( gettimeofday() ) + 1;
    InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
    return;
}
###################################
sub Set {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return qq (Set $name needs at least one argument);
    my $arg  = shift;
    my $val  = shift;

    #delete $hash->{helper}{cmdQueue};

    if ( $cmd eq 'param' ) {

        return qq(Usage is 'set $name $cmd <parameter> <value>') if ( !$cmd || !$val );

        if ( any {/^$arg$/xsm} @{ $hash->{helper}{params} } ) {

            setParam( $hash, $arg, $val );
            return;
        }
        return "Invalid Parameter";
    }
    if ( $cmd eq 'regenerate' ) {
        regenerate($hash);
        return;
    }
    if ( $cmd eq 'refill' ) {
        refill($hash);
        return;
    }
    if ( $cmd eq 'password' ) {

        my $err = StorePassword( $hash, $arg );
        if ( !IsDisabled($name) && defined( ReadPassword($hash) ) ) {
            my $next = int( gettimeofday() ) + 1;
            InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
        }
        return $err;

    }

    return qq (Unknown argument $cmd, choose one of param regenerate:noArg refill:noArg password);

}
###################################
sub Get {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "set $name needs at least one argument";

    if ( !ReadPassword($hash) ) {
        return qq(set password first);
    }

    delete $hash->{helper}{cmdQueue};

    if ( $cmd eq 'query' ) {
        return query($hash);
    }

    if ( $cmd eq 'water' || $cmd eq 'salt' ) {
        getRefreshTokenDirect($hash) if isExpiredToken($hash);
        return getMeasurements( $hash, $cmd );
    }

    if ( $cmd eq 'paramList' ) {
        getRefreshTokenDirect($hash) if isExpiredToken($hash);

        return getParamList($hash);
    }

    if ( $cmd eq 'realtime' ) {
        push @{ $hash->{helper}{cmdQueue} }, \&getRefreshToken if isExpiredToken($hash);
        push @{ $hash->{helper}{cmdQueue} }, \&negotiate;
        processCmdQueue($hash);
        return;
    }

    # those are just for testing
    if ( $cmd eq 'authenticate' ) {
        push @{ $hash->{helper}{cmdQueue} }, \&authenticate;
        push @{ $hash->{helper}{cmdQueue} }, \&login;
        push @{ $hash->{helper}{cmdQueue} }, \&getCode;
        push @{ $hash->{helper}{cmdQueue} }, \&initToken;
        processCmdQueue($hash);
        return;
    }
    if ( $cmd eq 'devices' ) {
        push @{ $hash->{helper}{cmdQueue} }, \&getRefreshToken;
        push @{ $hash->{helper}{cmdQueue} }, \&getDevices;
        processCmdQueue($hash);
        return;
    }
    if ( $cmd eq 'param' ) {
        push @{ $hash->{helper}{cmdQueue} }, \&getRefreshToken;
        push @{ $hash->{helper}{cmdQueue} }, \&getParam;
        processCmdQueue($hash);
        return;
    }

    if ( $cmd eq 'info' ) {
        push @{ $hash->{helper}{cmdQueue} }, \&getRefreshToken;
        push @{ $hash->{helper}{cmdQueue} }, \&getInfo;
        processCmdQueue($hash);
        return;
    }

    return
        qq(Unknown argument $cmd, choose one of realtime:noArg  water:noArg salt:noArg query:noArg paramList:noArg authenticate);
}

sub Attr {
    my $cmd  = shift;
    my $name = shift;
    my $attr = shift;
    my $aVal = shift;

    my $hash = $defs{$name};

    if ( $cmd eq 'set' ) {
        if ( $attr eq 'sq_interval' ) {

            # restrict interval to 5 minutes
            if ( $aVal > SQ_MINIMUM_INTERVAL ) {
                my $next = int( gettimeofday() ) + 1;
                InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
                return;
            }

            # message if interval is less than 5 minutes
            if ( $aVal > 0 ) {
                return qq (Interval for $name has to be > 5 minutes (300 seconds) or 0 to disable);
            }
            RemoveInternalTimer($hash);
            return;
        }
        if ( $attr eq 'disable' ) {
            if ( $aVal == 1 ) {
                RemoveInternalTimer($hash);
                DevIo_CloseDev($hash);
                readingsSingleUpdate( $hash, "state", "inactive", 1 );
                $hash->{helper}{DISABLED} = 1;
                return;
            }
            if ( $aVal == 0 ) {
                readingsSingleUpdate( $hash, "state", "initialized", 1 );
                $hash->{helper}{DISABLED} = 0;
                my $next = int( gettimeofday() ) + 1;
                InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
                return;
            }

        }
    }

    if ( $cmd eq "del" ) {
        if ( $attr eq "sq_interval" ) {
            RemoveInternalTimer($hash);
            return;
        }
        if ( $attr eq "disable" ) {
            readingsSingleUpdate( $hash, "state", "initialized", 1 );
            $hash->{helper}{DISABLED} = 0;
            my $next = int( gettimeofday() ) + 1;
            InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
            return;
        }
    }
    return;
}

###################################
sub refill {
    my $hash = shift;
    my $name = $hash->{NAME};
    readingsSingleUpdate( $hash, "lastRefill", ReadingsVal( $name, 'msaltusage', 0 ), 1 );
    return;
}

sub setParam {
    my $hash  = shift;
    my $param = shift;
    my $value = shift;
    my $body;
    my $name = $hash->{NAME};
    if ( $value =~ /^-?\d+\.?\d*$/xsm ) {
        my $num = $value * 1;
        $body = encode_json( { $param => $num } );
    }
    else {
        $body = encode_json( { $param => $value } );
    }

    Log3 $name, LOG_SEND, qq([$name] Setting parameter $body);

    my $header = {
        "Host"            => "prod-eu-gruenbeck-api.azurewebsites.net",
        "Accept"          => "application/json",
        "User-Agent"      => "Gruenbeck/360 CFNetwork/1220.1 Darwin/20.3.0",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache",
        "Content-Type"    => "application/json",
    };
    my $setparam = {
        header => $header,
        url    => 'https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices/softliQ.D/'
            . ReadingsVal( $name, 'id', $EMPTY )
            . '/parameters?api-version=2021-03-26',
        callback => \&parseParam,
        hash     => $hash,
        method   => 'PATCH',
        data     => $body
    };
    HttpUtils_NonblockingGet($setparam);
    return;
}

sub regenerate {
    my $hash = shift;

    my $name = $hash->{NAME};

    Log3 $name, LOG_RECEIVE, qq([$name] Starting regeneration);

    my $body = '{}';

    my $header = {
        "Host"   => "prod-eu-gruenbeck-api.azurewebsites.net",
        "Accept" => "application/json, text/plain, */*",
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache",
        "Content-Type"    => "application/json",
        "Origin"          => "file://",
        "Content-Length"  => 2
    };
    my $setparam = {
        header => $header,
        url    => 'https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices/'
            . ReadingsVal( $name, 'id', $EMPTY )
            . '/regenerate?api-version=2019-08-09',
        callback => \&parseRegenerate,
        hash     => $hash,
        method   => 'POST',
        data     => $body
    };
    HttpUtils_NonblockingGet($setparam);
    return;

}

sub parseRegenerate {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, LOG_RECEIVE, qq($err / $json);

    # we actually don't expect a response
    return if ( $json eq $EMPTY );

    $json = latin1ToUtf8($json);

    my $data = safe_decode_json( $hash, $json );

    #my $data = @$cdata[0];
    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);

        if ( defined( $data->{error}{type} ) ) {
            readingsBulkUpdate( $hash, "error",             $data->{error}{type} );
            readingsBulkUpdate( $hash, "error_description", '---' );
            readingsEndUpdate( $hash, 1 );
            return;
        }
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;

    }
    return;
}

sub sqTimer {
    my $hash = shift;

    my $name = $hash->{NAME};
    RemoveInternalTimer($hash);
    query($hash);
    Log3 $name, LOG_RECEIVE, qq([$name]: Starting Timer);
    my $next = int( gettimeofday() ) + AttrNum( $name, 'sq_interval', HOURSECONDS );
    InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::sqTimer', $hash, 0 );
    return;
}

sub query {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( ReadingsVal( $name, '.accessToken', $EMPTY ) eq $EMPTY || isExpiredToken($hash) ) {
        push @{ $hash->{helper}{cmdQueue} }, \&authenticate;
        push @{ $hash->{helper}{cmdQueue} }, \&login;
        push @{ $hash->{helper}{cmdQueue} }, \&getCode;
        push @{ $hash->{helper}{cmdQueue} }, \&initToken;
    }
    push @{ $hash->{helper}{cmdQueue} }, \&getRefreshToken;
    push @{ $hash->{helper}{cmdQueue} }, \&getDevices;
    push @{ $hash->{helper}{cmdQueue} }, \&getInfo;
    push @{ $hash->{helper}{cmdQueue} }, \&getParam;
    push @{ $hash->{helper}{cmdQueue} }, \&negotiate;
    processCmdQueue($hash);
    return;

}

sub isExpiredToken {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $now = gettimeofday();
    my $expires = ReadingsVal( $name, "expires_on", '1900-01-01' );
    if ( time_str2num($expires) - MINUTESECONDS > $now ) {
        return 1;
    }
    return;
}

sub authenticate {
    my $hash = shift;
    my $name = $hash->{NAME};

    # if ( AttrVal( $name, 'sq_user', '' ) eq '' || AttrVal( $name, 'sq_password', '' ) eq '' ) {
    #     return "Please maintain user and password attributes first";
    # }

    if ( !exists &{"urlsafe_b64encode"} ) {
        Log3 $name, 1, "urlsafe_b64encode doesn't exist. Exiting";
        return;
    }

    my $auth_code_verifier
        = urlsafe_b64encode( join( '', map { ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9 )[ rand 62 ] } 0 .. 31 ) );
    $auth_code_verifier =~ s/=//xsm;
    $hash->{helper}{code_verifier} = $auth_code_verifier;
    my $auth_code_challenge = urlsafe_b64encode( sha256($auth_code_verifier) );
    $auth_code_challenge =~ s/\=//xsm;
    readingsSingleUpdate( $hash, 'code_challenge', $auth_code_verifier, 0 );

    my $param->{header} = {
        "Accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding" => "br, gzip, deflate",
        "Connection"      => "keep-alive",
        "Accept-Language" => "de-de",
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1"
    };
    my $url
        = "https://gruenbeckb2c.b2clogin.com/a50d35c1-202f-4da7-aa87-76e51a3098c6/b2c_1a_signinup/oauth2/v2.0/authorize?state=NzZDNkNBRkMtOUYwOC00RTZBLUE5MkYtQTNFRDVGNTQ3MUNG"
        . "&x-client-Ver=0.2.2"
        . "&prompt=select_account"
        . "&response_type=code"
        . "&code_challenge_method=S256"
        . "&x-client-OS=12.4.1"
        . "&scope=https%3A%2F%2Fgruenbeckb2c.onmicrosoft.com%2Fiot%2Fuser_impersonation+openid+profile+offline_access"
        . "&x-client-SKU=MSAL.iOS"
        . "&code_challenge="
        . $auth_code_challenge
        . "&x-client-CPU=64"
        . "&client-request-id=FDCD0F73-B7CD-4219-A29B-EE51A60FEE3E&redirect_uri=msal5a83cc16-ffb1-42e9-9859-9fbf07f36df8%3A%2F%2Fauth&client_id=5a83cc16-ffb1-42e9-9859-9fbf07f36df8&haschrome=1"
        . "&return-client-request-id=true&x-client-DM=iPhone";
    $param->{method}   = "GET";
    $param->{url}      = $url;
    $param->{callback} = \&parseAuthenticate;
    $param->{hash}     = $hash;

    #$param->{ignoreredirects} = 1;

    Log3 $name, LOG_DEBUG, "1st Generated URL is $param->{url}";

    my ( $err, $data ) = HttpUtils_NonblockingGet($param);
    return;
}

sub parseAuthenticate {
    my ( $param, $err, $data ) = @_;
    my $hash   = $param->{hash};
    my $name   = $hash->{NAME};
    my $header = $param->{httpheader};
    Log3 $name, LOG_RECEIVE, Dumper($header);
    getCookies( $hash, $header );

    #Log3 undef, 1, $err . " / " . $data;
    my $cdata = $data;
    my $regex = qq /"csrf":"(.*?)",.*"transId":"(.*?)",.*"tenant":"(.*?)",.*"policy":"(.*?)",/;
    my @res   = $cdata =~ /$regex/gmxs;
    my $csrf  = $res[0];
    $hash->{helper}{csrf}    = $csrf;
    $hash->{helper}{tenant}  = $res[2];
    $hash->{helper}{policy}  = $res[3];
    $hash->{helper}{transId} = $res[1];
    Log3 $name, LOG_RECEIVE, Dumper(@res);    # . "\n-" . Dumper($header);    #  ."-". $tenant

    readingsSingleUpdate( $hash, "tenant", $hash->{helper}{tenant}, 0 );

    my $cookies;
    if ( $hash->{HTTPCookieHash} ) {
        foreach my $cookie ( sort keys %{ $hash->{HTTPCookieHash} } ) {
            my $cPath = $hash->{HTTPCookieHash}{$cookie}{Path};
            $cookies .= "; " if ($cookies);
            $cookies .= $hash->{HTTPCookieHash}{$cookie}{Name} . '=' . $hash->{HTTPCookieHash}{$cookie}{Value};
        }
    }
    $hash->{helper}{cookies} = $cookies;
    Log3 $name, LOG_DEBUG, Dumper($cookies);
    processCmdQueue($hash);
    return;
}

sub login {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $newheader = {
        "Content-Type"     => "application/x-www-form-urlencoded; charset=UTF-8",
        "X-CSRF-TOKEN"     => $hash->{helper}{csrf},
        "Accept"           => "application/json, text/javascript, */*; q=0.01",
        "X-Requested-With" => "XMLHttpRequest",
        "Origin"           => "https://gruenbeckb2c.b2clogin.com",
        "Referer" =>
            "https://gruenbeckb2c.b2clogin.com/a50d35c1-202f-4da7-aa87-76e51a3098c6/b2c_1a_signinup/oauth2/v2.0/authorize?state=MTgxQUExQ0QtN0NFMi00NkE1LTgyQTQtNEY0NEREMDYzMTM2&x-client-Ver=0.2.2&prompt=select_account&response_type=code&code_challenge_method=S256&x-client-OS=13.3.1&scope=https%3A%2F%2Fgruenbeckb2c.onmicrosoft.com%2Fiot%2Fuser_impersonation+openid+profile+offline_access&x-client-SKU=MSAL.iOS&code_challenge=z3tSf1frNKpNB0TTGb6VKrLLHwNFvII7c75sv1CG9Is&x-client-CPU=64&client-request-id=1A472478-12F4-445D-81AC-170A578B4F37&redirect_uri=msal5a83cc16-ffb1-42e9-9859-9fbf07f36df8%3A%2F%2Fauth&client_id=5a83cc16-ffb1-42e9-9859-9fbf07f36df8&haschrome=1&return-client-request-id=true&x-client-DM=iPhone",
        "Cookie" => $hash->{helper}{cookies},
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1"
    };
    my $newdata = {
        "request_type"    => 'RESPONSE',
        "logonIdentifier" => InternalVal( $name, 'USER', $EMPTY ),
        "signInName"      => InternalVal( $name, 'USER', $EMPTY ),
        "password"        => ReadPassword($hash),
    };

    my $newparam = {
        header      => $newheader,
        hash        => $hash,
        method      => "POST",
        httpversion => "1.1",
        timeout     => 10,
        url         => "https://gruenbeckb2c.b2clogin.com"
            . $hash->{helper}{tenant}
            . "/SelfAsserted?tx="
            . $hash->{helper}{transId} . "&p="
            . $hash->{helper}{policy},
        callback => \&parseLogin,
        data     => $newdata

    };

    Log3 $name, LOG_DEBUG, "Generated URL is $newparam->{url} \n";

    #Log3 $name, LOG_RECEIVE, Dumper($newparam);

    HttpUtils_NonblockingGet($newparam);
    return;
}

sub parseLogin {

    my ( $param, $err, $data ) = @_;
    my $hash   = $param->{hash};
    my $name   = $hash->{NAME};
    my $header = $param->{httpheader};

    # $data should be {"status":"200"}
    Log3 $name, LOG_RECEIVE, $err . " / " . $data . Dumper($header);
    my $json = safe_decode_json( $hash, $data );
    if ( $json->{status} ne "200" ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $json->{status} );
        readingsBulkUpdate( $hash, "error_description", $json->{message} );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    my $cookies = getCookies( $hash, $header );
    if ( $hash->{HTTPCookieHash} ) {
        foreach my $cookie ( sort keys %{ $hash->{HTTPCookieHash} } ) {
            my $cPath = $hash->{HTTPCookieHash}{$cookie}{Path};
            $cookies .= "; " if ($cookies);
            $cookies .= $hash->{HTTPCookieHash}{$cookie}{Name} . "=" . $hash->{HTTPCookieHash}{$cookie}{Value};
        }
    }

    Log3 $name, LOG_DEBUG, "=================" . Dumper($cookies) . "\nHeader:" . Dumper($header);
    $cookies .= "; x-ms-cpim-csrf=" . $hash->{helper}{csrf};
    Log3 $name, LOG_DEBUG, "=================" . Dumper($cookies) . "\n";
    $hash->{helper}{cookies} = $cookies;
    processCmdQueue($hash);
    return;
}

sub getCode {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $newparam->{header} = {
        "Accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding" => "br, gzip, deflate",
        "Connection"      => "keep-alive",
        "Accept-Language" => "de-de",
        "Cookie"          => $hash->{helper}{cookies},
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1"
    };
    $newparam->{url}
        = "https://gruenbeckb2c.b2clogin.com"
        . $hash->{helper}{tenant}
        . "/api/CombinedSigninAndSignup/confirmed?csrf_token="
        . $hash->{helper}{csrf} . "&tx="
        . $hash->{helper}{transId} . "&p="
        . $hash->{helper}{policy};

    $newparam->{hash} = $hash;

    $newparam->{callback}        = \&parseCode;
    $newparam->{httpversion}     = "1.1";
    $newparam->{ignoreredirects} = 1;
    Log3 $name, LOG_DEBUG, qq(Calling $newparam->{url});
    HttpUtils_NonblockingGet($newparam);

    return;
}

sub parseCode {
    my ( $param, $err, $data ) = @_;
    my $hash   = $param->{hash};
    my $name   = $hash->{NAME};
    my $header = $param->{httpheader};

    my $cookies = getCookies( $hash, $header );
    Log3 $name, LOG_RECEIVE, qq($err / $data);

    my @code = $data =~ /code%3d(.*)\">here/xsm;
    if ( $code[0] eq $EMPTY ) {
        readingsSingleUpdate( $hash, 'error',             'no code found', 1 );
        readingsSingleUpdate( $hash, 'error_description', '---',           1 );
        return;
    }

    Log3 $name, LOG_DEBUG, Dumper(@code);
    $hash->{helper}{code} = $code[0];
    processCmdQueue($hash);
    return;
}

sub initToken {
    my $hash = shift;
    my $name = $hash->{NAME};

    if ( !$hash->{helper}{tenant} ) {
        $hash->{helper}{tenant} = ReadingsVal( $name, "tenant", undef );
    }

    my $newparam->{header} = {
        "Host"                     => "gruenbeckb2c.b2clogin.com",
        "x-client-SKU"             => "MSAL.iOS",
        "Accept"                   => "application/json",
        "x-client-OS"              => "12.4.1",
        "x-app-name"               => "Gruenbeck",
        "x-client-CPU"             => "64",
        "x-app-ver"                => "1.0.7",
        "Accept-Language"          => "de-de",
        "Accept-Encoding"          => "br, gzip, deflate",
        "client-request-id"        => "1A472478-12F4-445D-81AC-170A578B4F37",
        "User-Agent"               => "Gruenbeck/333 CFNetwork/1121.2.2 Darwin/19.3.0",
        "x-client-Ver"             => "0.2.2",
        "x-client-DM"              => "iPhone",
        "return-client-request-id" => "true",

        #        "cache-control"            => "no-cache",
        "Connection"               => "keep-alive",
        "Content-Type"             => "application/x-www-form-urlencoded",
        "return-client-request-id" => "true"
    };
    $newparam->{url} = "https://gruenbeckb2c.b2clogin.com" . $hash->{helper}{tenant} . "/oauth2/v2.0/token";

    my $newdata
        = "client_info=1&scope=https%3A%2F%2Fgruenbeckb2c.onmicrosoft.com%2Fiot%2Fuser_impersonation+openid+profile+offline_access&"
        . "code="
        . $hash->{helper}{code}
        . "&grant_type=authorization_code&"
        . "code_verifier="
        . ReadingsVal( $name, 'code_challenge', $EMPTY )
        . "&redirect_uri=msal5a83cc16-ffb1-42e9-9859-9fbf07f36df8%3A%2F%2Fauth"
        . "&client_id=5a83cc16-ffb1-42e9-9859-9fbf07f36df8";

    $newparam->{httpversion} = '1.1';
    $newparam->{data}        = $newdata;
    $newparam->{hash}        = $hash;
    $newparam->{method}      = 'POST';
    $newparam->{callback}    = \&parseRefreshToken;
    HttpUtils_NonblockingGet($newparam);
    return;
}

sub parseRefreshToken {
    my ( $param, $err, $json ) = @_;
    my $hash   = $param->{hash};
    my $name   = $hash->{NAME};
    my $header = $param->{httpheader};

    Log3 $name, LOG_RECEIVE, qq($err / $json);

    my $data = safe_decode_json( $hash, $json );
    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;
    }
    $hash->{helper}{accessToken}  = $data->{access_token};
    $hash->{helper}{refreshToken} = $data->{refresh_token};

    # seems like access token is valid for 14 days, refresg token for 1 hour
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, ".accessToken",  $data->{access_token} );
    readingsBulkUpdate( $hash, ".refreshToken", $data->{refresh_token} );
    readingsBulkUpdate( $hash, "not_before",    strftime( "%Y-%m-%d %H:%M:%S", localtime( $data->{not_before} ) ) );
    readingsBulkUpdate( $hash, "expires_on",    strftime( "%Y-%m-%d %H:%M:%S", localtime( $data->{expires_on} ) ) );

    readingsEndUpdate( $hash, 1 );

    processCmdQueue($hash);
    return;
}

sub getRefreshTokenHeader {
    my $hash = shift;

    my $name = $hash->{NAME};

    my $header = {
        "Host"                     => "gruenbeckb2c.b2clogin.com",
        "x-client-SKU"             => "MSAL.iOS",
        "Accept"                   => "application/json",
        "x-client-OS"              => "12.4.1",
        "x-app-name"               => "Gruenbeck myProduct",
        "x-client-CPU"             => "64",
        "x-app-ver"                => "1.0.4",
        "Accept-Language"          => "de-de",
        "client-request-id"        => "E85BBC36-160D-48B0-A93A-2694F902BF19",
        "User-Agent"               => "Gruenbeck/320 CFNetwork/978.0.7 Darwin/18.7.0",
        "x-client-Ver"             => "0.2.2",
        "x-client-DM"              => "iPhone",
        "return-client-request-id" => "true",
        "cache-control"            => "no-cache"
    };
    my $newdata
        = "client_id=5a83cc16-ffb1-42e9-9859-9fbf07f36df8&scope=https://gruenbeckb2c.onmicrosoft.com/iot/user_impersonation openid profile offline_access&"
        . "refresh_token="
        . ReadingsVal( $name, '.refreshToken', $EMPTY )    #$hash->{helper}{refreshToken}
        . "&client_info=1&" . "grant_type=refresh_token";
    my $param = {
        header => $header,
        data   => $newdata,
        hash   => $hash,
        method => "POST",
        url    => "https://gruenbeckb2c.b2clogin.com" . ReadingsVal( $name, 'tenant', $EMPTY ) . "/oauth2/v2.0/token"
    };

    return $param;

}

sub getRefreshTokenDirect {
    my $hash = shift;

    my $param = getRefreshTokenHeader($hash);

    my ( $err, $data ) = HttpUtils_BlockingGet($param);
    parseRefreshToken( $param, $err, $data );
    return;
}

sub getRefreshToken {
    my $hash = shift;

    my $param = getRefreshTokenHeader($hash);
    $param->{callback} = \&parseRefreshToken;
    HttpUtils_NonblockingGet($param);
    return;
}

sub getDevices {
    my ($hash) = @_;
    my $name = $hash->{NAME};

    my $header = {
        "Host"            => "prod-eu-gruenbeck-api.azurewebsites.net",
        "Accept"          => "application/json, text/plain, */*",
        "User-Agent"      => "Gruenbeck/358 CFNetwork/1220.1 Darwin/20.3.0",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache"
    };
    my $param = {
        header   => $header,
        url      => "https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices?api-version=2020-08-03",
        callback => \&parseDevices,
        hash     => $hash
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub parseDevices {
    my ( $param, $err, $json ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, LOG_RECEIVE, qq($err / $json);
    $json = latin1ToUtf8($json);

    my $data = safe_decode_json( $hash, $json );
    my $dev = $data->[0];

    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $dev->{error} ) ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $dev->{error} );
        readingsBulkUpdate( $hash, "error_description", $dev->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    readingsBeginUpdate($hash);

    #my @devices;

    #foreach my $dev (@data) {
    #   Log3 undef, 1, Dumper($dev);
    readingsBulkUpdate( $hash, "name", $dev->{name} );
    readingsBulkUpdate( $hash, "id",   $dev->{id} );

    #    push @devices, $dev->{id};
    #}
    #readingsBulkUpdate( $hash, "devices", join( ",", @devices ) );
    readingsEndUpdate( $hash, 1 );
    processCmdQueue($hash);
    return;
}

sub getMeasurements {
    my $hash = shift;
    my $type = shift;

    my $name = $hash->{NAME};

    my $header = {
        "Host"            => "prod-eu-gruenbeck-api.azurewebsites.net",
        "Accept"          => "application/json, text/plain, */*",
        "User-Agent"      => "Gruenbeck/358 CFNetwork/1220.1 Darwin/20.3.0",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache"
    };
    my $param = {
        header => $header,
        url    => "https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices/softliQ.D/"
            . ReadingsVal( $name, 'id', $EMPTY )
            . "/measurements/"
            . $type
            . '/?api-version=2020-08-03/',
        hash => $hash
    };

    my ( $err, $json ) = HttpUtils_BlockingGet($param);
    Log3 $name, LOG_RECEIVE, qq($err / $json);
    $json = latin1ToUtf8($json);

    #my $data = safe_decode_json( $hash, $json );
    my $cdata = safe_decode_json( $hash, $json );
    my $data = $cdata->[0];

    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return $data->{error_description};
    }
    my $ret;
    foreach my $d ( @{$cdata} ) {
        $ret .= '<div>' . $d->{date} . ' : ' . $d->{value} . '</div>';
    }
    return $ret;
}

sub getInfo {
    my $hash = shift;

    my $name = $hash->{NAME};

    my $header = {
        "Host"   => "prod-eu-gruenbeck-api.azurewebsites.net",
        "Accept" => "application/json, text/plain, */*",
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Authorization"   => "Bearer " . ReadingsVal( $name, '.accessToken', undef ),
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache"
    };
    my $param = {
        header   => $header,
        url      => "https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices/" . ReadingsVal( $name, 'id', $EMPTY ),
        callback => \&parseInfo,
        hash     => $hash
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub parseInfo {
    my ( $param, $err, $json ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, LOG_RECEIVE, qq($err / $json);
    $json = latin1ToUtf8($json);

    my @cdata = safe_decode_json( $hash, $json );
    my $data = $cdata[0];
    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    readingsBeginUpdate($hash);
    my %info = %{$data};
    my $i    = 0;
    foreach my $key ( keys %info ) {
        if ( ref( $info{$key} ) eq "ARRAY" ) {
            if ( $key eq "water" || $key eq "salt" ) {
                $i = 0;
                foreach my $dp ( @{ $info{$key} } ) {
                    readingsBulkUpdate( $hash, $key . "_" . $i . "_date",  $dp->{date} );
                    readingsBulkUpdate( $hash, $key . "_" . $i . "_value", $dp->{value} );
                    $i++;
                }
            }
            elsif ( $key eq "errors" ) {
                my $actMsg = 0;
                foreach my $dp ( @{ $info{$key} } ) {
                    my $mkey = 'message_' . makeReadingName( unpack( 'L', md5( $dp->{date} ) ) );

                    #next if (ReadingsVal($name,$mkey.'_date','') eq '');
                    readingsBulkUpdate( $hash, $mkey . '_date',       $dp->{date} );
                    readingsBulkUpdate( $hash, $mkey . '_isResolved', $dp->{isResolved} );
                    readingsBulkUpdate( $hash, $mkey . '_message',    $dp->{message} );
                    readingsBulkUpdate( $hash, $mkey . '_type',       $dp->{type} );
                    if ( $dp->{isResolved} == 0 ) {
                        $actMsg++;
                    }

                }
                readingsBulkUpdate( $hash, 'messageCount', $actMsg );
            }
        }
        else {
            readingsBulkUpdate( $hash, $key, $info{$key} );
        }
    }
    readingsEndUpdate( $hash, 1 );
    processCmdQueue($hash);
    return;
}

sub getParamList {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( defined( $hash->{helper}{params} ) ) {
        my $ret = '<table>';
        foreach my $p ( sort @{ $hash->{helper}{params} } ) {
            $ret .= qq (<tr><td>$p</td>);
            $paramTexts{$p} //= 'N/A'
                ; #The slash slash operator in perl returns the left side value if it is defined, otherwise it returns the right side value.
            $ret .= qq(<td>$paramTexts{$p}</td>);
            my $rv = ReadingsVal( $name, ".$p", $EMPTY );
            $ret .= qq(<td>$rv);
            if ( defined( $paramValueMap{$p} ) ) {
                $ret .= qq / ($paramValueMap{$p}{$rv})/;
            }
            $ret .= '</td></tr>';
        }
        $ret .= '</table>';
        return $ret;
    }

    getParam($hash);
    return qq (ParameterList has to be updated, please try again in a moment);
}

sub getParam {
    my $hash = shift;

    my $name = $hash->{NAME};

    my $header = {
        "Host"   => "prod-eu-gruenbeck-api.azurewebsites.net",
        "Accept" => "application/json, text/plain, */*",
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache"
    };
    my $param = {
        header => $header,
        url    => "https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices/"
            . ReadingsVal( $name, 'id', $EMPTY )
            . '/parameters?api-version=2020-08-03',
        callback => \&parseParam,
        hash     => $hash
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub parseParam {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, LOG_RECEIVE, qq($err / $json);
    $json = latin1ToUtf8($json);

    my $data = safe_decode_json( $hash, $json );

    #my $data = @$cdata[0];
    Log3 $name, LOG_RECEIVE, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);

        if ( defined( $data->{error}{type} ) ) {
            readingsBulkUpdate( $hash, "error",             $data->{error}{type} );
            readingsBulkUpdate( $hash, "error_description", '---' );
            readingsEndUpdate( $hash, 1 );
            return;
        }
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;

    }

    readingsBeginUpdate($hash);
    my %info = %{$data};
    my $i    = 0;
    my @param;
    foreach my $key ( keys %info ) {
        if ( ref( $info{$key} ) eq 'ARRAY' || $key eq 'type' ) {    #we don't want to overwrite the device type

            #we'll have to check that
        }
        else {
            readingsBulkUpdate( $hash, ".$key", $info{$key} );
            push @param, $key;
        }
    }
    readingsEndUpdate( $hash, 1 );
    $hash->{helper}{params} = \@param;

    processCmdQueue($hash);
    return;
}

sub negotiate {
    my $hash = shift;

    my $name = $hash->{NAME};

    my $header = {
        "Content-Type" => "text/plain;charset=UTF-8",
        "Origin"       => "file://",
        "Accept"       => "*/*",
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache"
    };
    my $param = {
        header   => $header,
        url      => "https://prod-eu-gruenbeck-api.azurewebsites.net/api/realtime/negotiate",
        callback => \&parseNegotiate,
        hash     => $hash
    };
    HttpUtils_NonblockingGet($param);
    return;
}

sub parseNegotiate {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, LOG_RECEIVE, qq($err / $json);
    my $data = safe_decode_json( $hash, $json );
    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    $hash->{helper}{wsAccessToken} = $data->{accessToken};
    $hash->{helper}{wsUrl}         = $data->{url};
    Log3 $name, LOG_DEBUG, qq ([$name] wsUrl is $data->{url});

    my $newheader = {
        "Content-Type" => "text/plain;charset=UTF-8",
        "Origin"       => "file://",
        "Accept"       => "*/*",
        "User-Agent" =>
            "   Mozilla/5.0 (iPhone; CPU iPhone OS 13_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Authorization"    => "Bearer " . $hash->{helper}{wsAccessToken},
        "Accept-Language"  => "de-de",
        "X-Requested-With" => "XMLHttpRequest",
        "Content-Length"   => 0
    };
    my $newparam = {
        header   => $newheader,
        url      => "https://prod-eu-gruenbeck-signalr.service.signalr.net/client/negotiate?hub=gruenbeck",
        callback => \&parseWebsocketId,
        hash     => $hash,
        method   => "POST"
    };
    HttpUtils_NonblockingGet($newparam);

    #processCmdQueue($hash);
    return;

}

sub parseWebsocketId {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    Log3 $name, LOG_RECEIVE, qq($err / $json);
    my $data = safe_decode_json( $hash, $json );
    Log3 $name, LOG_DEBUG, Dumper($data);

    if ( defined( $data->{error} ) ) {
        readingsBeginUpdate($hash);
        readingsBulkUpdate( $hash, "error",             $data->{error} );
        readingsBulkUpdate( $hash, "error_description", $data->{error_description} );
        readingsEndUpdate( $hash, 1 );
        return;
    }

    $hash->{helper}{wsId} = $data->{connectionId};
    return if ( !$data->{connectionId} );

    my $url
        = "wss://prod-eu-gruenbeck-signalr.service.signalr.net/client/?hub=gruenbeck&id="
        . $hash->{helper}{wsId}
        . "&access_token="
        . $hash->{helper}{wsAccessToken};

    wsConnect2( $hash, $url );

    realtime( $hash, "enter" );
    realtime( $hash, "refresh" );

    processCmdQueue($hash);
    return;
}

sub realtime {

    my ( $hash, $type ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, LOG_RECEIVE, qq ([$name] Calling realtime for $type);

    my $header = {
        "Content-Length" => 0,
        "Origin"         => "file://",
        "Accept"         => "*/*",
        "User-Agent" =>
            "Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
        "Authorization"   => "Bearer " . $hash->{helper}{accessToken},
        "Accept-Language" => "de-de",
        "cache-control"   => "no-cache"
    };
    my $param = {
        header => $header,
        url    => "https://prod-eu-gruenbeck-api.azurewebsites.net/api/devices/"
            . ReadingsVal( $name, 'id', $EMPTY )
            . "/realtime/$type?api-version=2020-08-03",
        callback => \&parseRealtime,
        hash     => $hash,
        method   => "POST"
    };

    HttpUtils_NonblockingGet($param);
    return;

}

sub parseRealtime {
    my $param = shift;
    my $err   = shift;
    my $json  = shift;

    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    return;
}
### stolen from HTTPMOD
sub getCookies {
    my $hash   = shift;
    my $header = shift;

    my $name = $hash->{NAME};

    delete $hash->{HTTPCookieHash};

    foreach my $cookie ( $header =~ m/set-cookie: ?(.*)/gix ) {
        if ( $cookie =~ /([^,; ]+)=([^,;\s\v]+)[;,\s\v]*([^\v]*)/x ) {

            Log3 $name, LOG_RECEIVE, qq($name: GetCookies parsed Cookie: $1 Wert $2 Rest $3);
            my $cname = $1;
            my $value = $2;
            my $rest  = ( $3 ? $3 : $EMPTY );
            my $path  = $EMPTY;
            if ( $rest =~ /path=([^;,]+)/xsm ) {
                $path = $1;
            }
            my $key = $cname . ';' . $path;
            $hash->{HTTPCookieHash}{$key}{Name}    = $cname;
            $hash->{HTTPCookieHash}{$key}{Value}   = $value;
            $hash->{HTTPCookieHash}{$key}{Options} = $rest;
            $hash->{HTTPCookieHash}{$key}{Path}    = $path;

        }
    }
    return;
}

sub processCmdQueue {
    my $hash = shift;

    my $name = $hash->{NAME};

    return if ( !defined( $hash->{helper}{cmdQueue} ) );

    my $cmd = shift @{ $hash->{helper}{cmdQueue} };

    return if ref($cmd) ne "CODE";
    my $cv = svref_2object($cmd);
    my $gv = $cv->GV;
    Log3 $name, LOG_RECEIVE, "[$name] Processing Queue: " . $gv->NAME;
    $cmd->($hash);
    return;
}

sub safe_decode_json {
    my $hash = shift;
    my $data = shift;
    my $name = $hash->{NAME};

    my $json = undef;
    eval {
        $json = decode_json($data);
        1;
    } or do {
        my $error = $@ || 'Unknown failure';
        Log3 $name, LOG_ERROR, "[$name] - Received invalid JSON: $error" . Dumper($data);

    };
    return $json;
}

# from RichardCz, https://gl.petatech.eu/root/HomeBot/snippets/2

sub use_module_prio {
    my $args_hr = shift // return;    # get named arguments hash or bail out

    my $wanted_lr   = $args_hr->{wanted} //   [];    # get list of wanted methods/functions
    my $priority_lr = $args_hr->{priority} // [];    # get list of modules from most to least wanted

    for my $module ( @{$priority_lr} ) {             # iterate the priorized list of wanted modules
        my $success = eval "require $module";        # require module at runtime, undef if not there
        if ($success) {                              # we catched ourselves a module
            import $module @{$wanted_lr};            # perform the import of the wanted methods
            return $module;
        }
    }

    return;
}

sub StorePassword {
    my $hash     = shift;
    my $password = shift;
    my $name     = $hash->{NAME};

    my ( $passResp, $passErr );
    ( $passResp, $passErr ) = $hash->{helper}->{passObj}->setStorePassword( $name, $password );

    # my $index   = $hash->{TYPE} . "_" . $name . "_passwd";
    # my $key     = getUniqueId() . $index;
    # my $enc_pwd = $EMPTY;

    # if ( eval "use Digest::MD5;1" ) {

    #     $key = Digest::MD5::md5_hex( unpack "H*", $key );
    #     $key .= Digest::MD5::md5_hex($key);
    # }

    # for my $char ( split //, $password ) {

    #     my $encode = chop($key);
    #     $enc_pwd .= sprintf( "%.2x", ord($char) ^ ord($encode) );
    #     $key = $encode . $key;
    # }

    # my $err = setKeyValue( $index, $enc_pwd );
    if ( defined($passErr) ) {
        return "error while saving the password - $passErr";
    }

    return "password successfully saved";
}

sub ReadPassword {
    my $hash = shift;
    my $name = $hash->{NAME};

    return $hash->{helper}->{passObj}->getReadPassword($name);
}

sub ReadPasswordOld {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $index = $hash->{TYPE} . "_" . $name . "_passwd";
    my $key   = getUniqueId() . $index;
    my ( $password, $err );

    Log3 $name, LOG_RECEIVE, "[$name] - Read password from file";

    ( $err, $password ) = getKeyValue($index);

    if ( defined($err) ) {

        Log3 $name, LOG_WARNING, "[$name] - unable to read password from file: $err";
        return;

    }

    if ( defined($password) ) {
        if ( eval "use Digest::MD5;1" ) {

            $key = Digest::MD5::md5_hex( unpack "H*", $key );
            $key .= Digest::MD5::md5_hex($key);
        }

        my $dec_pwd = $EMPTY;

        for my $char ( map { pack( 'C', hex($_) ) } ( $password =~ /(..)/g ) ) {

            my $decode = chop($key);
            $dec_pwd .= chr( ord($char) ^ ord($decode) );
            $key = $decode . $key;
        }

        return $dec_pwd;

    }
    else {

        Log3 $name, LOG_WARNING, "[$name] - No password in file";
        return;
    }

    return;
}

sub Rename {
    my $new = shift;
    my $old = shift;

    my $hash = $defs{$new};
    my $name = $hash->{NAME};

    my $oldhash = $defs{$old};
    Log3( $name, 1, Dumper($oldhash) );

    my ( $passResp, $passErr ) = $hash->{helper}->{passObj}->setRename( $new, $old );

    if ( defined($passErr) ) {
        Log3( $name, LOG_WARNING,
            "[$name]error while saving the password after rename - $passErr. Please set the password again." );
    }
    return;
}

sub wsConnect2 {
    my ( $hash, $url ) = @_;
    my $name = $hash->{NAME};

    #$hash->{loglevel} = 1;
    return if ( DevIo_IsOpen($hash) );

    # Protocol::WebSocket takes a full URL, but IO::Socket::* uses only a host
    #  and port.  This regex section retrieves host/port from URL.
    my ( $proto, $host, $port, $path );
    if ( $url =~ m/^(?:(?<proto>ws|wss):\/\/)?(?<host>[^\/:]+)(?::(?<port>\d+))?(?<path>\/.*)?$/xsm ) {
        $host = $+{host};
        $path = $+{path};

        if ( defined $+{proto} && defined $+{port} ) {
            $proto = $+{proto};
            $port  = $+{port};
        }
        elsif ( defined $+{port} ) {
            $port = $+{port};
            if   ( $port == 443 ) { $proto = 'wss' }
            else                  { $proto = 'ws' }
        }
        elsif ( defined $+{proto} ) {
            $proto = $+{proto};
            if   ( $proto eq 'wss' ) { $port = 443 }
            else                     { $port = 80 }
        }
        else {
            $proto = 'ws';
            $port  = 80;
        }
    }
    else {
        Log3 $name, LOG_ERROR, "[$name] Failed to parse Host/Port from URL.";
    }

    #$url =~ s/wss:\/\//wss:/;
    #$hash->{DeviceName} = $url;
    $hash->{DeviceName}    = 'wss:' . $host . ':' . $port . $path;
    $hash->{SSL}           = 1;
    $hash->{devioLoglevel} = LOG_RECEIVE;
    DevIo_OpenDev( $hash, 0, "FHEM::Gruenbeck::SoftliqCloud::wsStart", "FHEM::Gruenbeck::SoftliqCloud::wsFail" );

    return;
}

sub wsStart {
    my $hash = shift;
    my $name = $hash->{NAME};

    Log3( $name, LOG_RECEIVE, qq([$name] Websocket connected) );
    DevIo_SimpleWrite( $hash, '{"protocol":"json","version":1}', 2 );

    #succesfully connected - start a timer
    my $next = int( gettimeofday() ) + MINUTESECONDS;
    InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::wsClose', $hash, 0 );

    return;
}

# based on https://greg-kennedy.com/wordpress/2019/03/11/writing-a-websocket-client-in-perl-5/
sub wsConnect {
    my ( $hash, $url ) = @_;
    my $name = $hash->{NAME};

    # Protocol::WebSocket takes a full URL, but IO::Socket::* uses only a host
    #  and port.  This regex section retrieves host/port from URL.
    my ( $proto, $host, $port, $path );
    if ( $url =~ m/^(?:(?<proto>ws|wss):\/\/)?(?<host>[^\/:]+)(?::(?<port>\d+))?(?<path>\/.*)?$/xsm ) {
        $host = $+{host};
        $path = $+{path};

        if ( defined $+{proto} && defined $+{port} ) {
            $proto = $+{proto};
            $port  = $+{port};
        }
        elsif ( defined $+{port} ) {
            $port = $+{port};
            if   ( $port == 443 ) { $proto = 'wss' }
            else                  { $proto = 'ws' }
        }
        elsif ( defined $+{proto} ) {
            $proto = $+{proto};
            if   ( $proto eq 'wss' ) { $port = 443 }
            else                     { $port = 80 }
        }
        else {
            $proto = 'ws';
            $port  = 80;
        }
    }
    else {
        Log3 $name, LOG_ERROR, "[$name] Failed to parse Host/Port from URL.";
    }

    # create a connecting socket
    #  SSL_startHandshake is dependent on the protocol: this lets us use one socket
    #  to work with either SSL or non-SSL sockets.
    # my $tcp_socket = IO::Socket::SSL->new(
    #     PeerAddr                   => $host,
    #     PeerPort                   => "$proto($port)",
    #     Proto                      => 'tcp',
    #     SSL_startHandshake         => ( $proto eq 'wss' ? 1 : 0 ),
    #     Blocking                   => 1
    # ) or Log3 $name, 1, "[$name] Failed to connect to socket: $@";

    return if ( DevIo_IsOpen($hash) );
    Log3 $name, LOG_RECEIVE, "[$name] Attempting to open SSL socket to $proto://$host:$port...";
    $hash->{DeviceName}  = $host . ':' . $port;
    $hash->{helper}{url} = $url;
    $hash->{SSL}         = 1;

    #$hash->{WEBSOCKET}   = 1;

    #DevIo_CloseDev($hash) if ( DevIo_IsOpen($hash) );
    DevIo_OpenDev( $hash, 0, "FHEM::Gruenbeck::SoftliqCloud::wsHandshake", "FHEM::Gruenbeck::SoftliqCloud::wsFail" );

    #my $conn = DevIo_OpenDev( $hash, 0, "FHEM::Gruenbeck::SoftliqCloud::wsHandshake");
    #Log3 $name, 1, "[$name] Opening Websocket: $conn... $hash->{TCPDev}";
    return;
}

sub parseWebsocketRead {
    my $hash = shift;
    my $buf  = shift;
    my $name = $hash->{NAME};
    my $json = safe_decode_json( $hash, $buf );
    if ( $json->{type} && $json->{type} ne '6' ) {

        Log3 $name, LOG_RECEIVE, qq([$name] Received from socket: $buf);
        readingsBeginUpdate($hash);
        my @args = @{ $json->{arguments} };
        my %info = %{ $args[0] };
        my $i    = 0;
        foreach my $key ( keys %info ) {

            if ( $key eq 'type' ) {    # no use and there is already a type reading (machine type)
                next;
            }

            if ( $key =~ /2$/x and AttrVal( $name, 'sq_duplex', '0' ) eq '0' ) {
                next;
            }
            if ( $key eq 'msaltusage' ) {
                my $diff = $info{$key} - ReadingsNum( $name, "lastRefill", 0 );
                readingsBulkUpdate( $hash, 'saltUsageSinceRefill', $diff );
            }
            readingsBulkUpdate( $hash, $key, $info{$key} );
        }
        readingsEndUpdate( $hash, 1 );

    }
    return;
}

# sub wsHandshake {
#     my $hash       = shift;
#     my $name       = $hash->{NAME};
#     my $tcp_socket = $hash->{TCPDev};
#     my $url        = $hash->{helper}{url};

#     # create a websocket protocol handler
#     #  this doesn't actually "do" anything with the socket:
#     #  it just encodes / decode WebSocket messages.  We have to send them ourselves.
#     Log3 $name, LOG_RECEIVE, "[$name] Trying to create Protocol::WebSocket::Client handler for $url...";
#     my $client = Protocol::WebSocket::Client->new(
#         url     => $url,
#         version => "13",
#     );

#     # Set up the various methods for the WS Protocol handler
#     #  On Write: take the buffer (WebSocket packet) and send it on the socket.
#     $client->on(
#         write => sub {
#             my $sclient = shift;
#             my ($buf) = @_;

#             syswrite $tcp_socket, $buf;
#         }
#     );

#     # On Connect: this is what happens after the handshake succeeds, and we
#     #  are "connected" to the service.
#     $client->on(
#         connect => sub {
#             my $sclient = shift;

#             # You may wish to set a global variable here (our $isConnected), or
#             #  just put your logic as I did here.  Or nothing at all :)
#             Log3 $name, LOG_RECEIVE, "[$name] Successfully connected to service!" . Dumper($hash);
#             $sclient->write('{"protocol":"json","version":1}');

#             #succesfully connected - start a timer
#             my $next = int( gettimeofday() ) + MINUTESECONDS;
#             InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::wsClose', $hash, 0 );
#             return;

#         }
#     );

#     # On Error, print to console.  This can happen if the handshake
#     #  fails for whatever reason.
#     $client->on(
#         error => sub {
#             my $sclient = shift;
#             my ($buf) = @_;

#             Log3 $name, LOG_ERROR, qq([$name] ERROR ON WEBSOCKET: $buf);
#             $tcp_socket->close;
#             return qq([$name] ERROR ON WEBSOCKET: $buf);
#         }
#     );

#     # On Read: This method is called whenever a complete WebSocket "frame"
#     #  is successfully parsed.
#     # We will simply print the decoded packet to screen.  Depending on the service,
#     #  you may e.g. call decode_json($buf) or whatever.
#     $client->on(
#         read => sub {
#             my $sclient = shift;
#             my ($buf) = @_;
#             $buf =~ s///xsm;
#             parseWebsocketRead( $hash, $buf );

#             #Log3 $name, 3, "[$name] Received from socket: '$buf'";
#             return;
#         }
#     );

#     # Now that we've set all that up, call connect on $client.
#     #  This causes the Protocol object to create a handshake and write it
#     #  (using the on_write method we specified - which includes sysread $tcp_socket)
#     Log3 $name, LOG_RECEIVE, "[$name] Calling connect on client...";
#     $client->connect;

#     # read until handshake is complete.
#     while ( !$client->{hs}->is_done ) {
#         my $recv_data;

#         my $bytes_read = sysread $tcp_socket, $recv_data, TCPPACKETSIZE;

#         if ( !defined $bytes_read ) {
#             Log3 $name, LOG_ERROR, qq([$name] sysread on tcp_socket failed: $!);
#             return qq([$name] sysread on tcp_socket failed: $!);
#         }
#         if ( $bytes_read == 0 ) {
#             Log3 $name, LOG_ERROR, qq([$name] Connection terminated.);
#             return qq([$name] Connection terminated.);
#         }

#         $client->read($recv_data);
#     }

#     # Create a Socket Set for Select.
#     #  We can then test this in a loop to see if we should call read.
#     # my $set = IO::Select->new($tcp_socket);

#     #$hash->{helper}{wsSet}    = $set;
#     $hash->{helper}{wsClient} = $client;

#     # my $next = int( gettimeofday() ) + 1;
#     # $hash->{helper}{wsCount} = 0;
#     #InternalTimer( $next, 'FHEM::Gruenbeck::SoftliqCloud::wsRead', $hash, 0 );
#     return;
# }

sub wsFail {
    my $hash  = shift;
    my $error = shift;
    my $name  = $hash->{NAME};

    #$error //= "Unknown Error";
    return unless $error;

    # create a log emtry with the error message
    Log3 $name, LOG_ERROR, qq ([$name] - error while connecting to Websocket: $error);

    return;
}

sub Ready {
    my $hash = shift;

# try to reopen the connection in case the connection is lost
#return DevIo_OpenDev( $hash, 1, "FHEM::Gruenbeck::SoftliqCloud::wsHandshake", "FHEM::Gruenbeck::SoftliqCloud::wsFail" );
#negotiate($hash);
    return;
}

sub splitTest {
    my $buf = shift;
    my $name = "sd18";
    my @bufs;
    $buf =~ s///xsm;
    my $index = index( $buf, '}{' );
    if ( $index > 0 ) {
        Log3( $name, LOG_RECEIVE, "[$name] - Splitting double-JSON buffer" );
        push( @bufs, decode_json(substr( $buf, 0, $index + 1 ) ));
        push( @bufs, decode_json(substr( $buf, $index + 1 )));
    }
    else {
        push( @bufs, $buf );
    }
    return Dumper(@bufs);
}

sub wsReadDevIo {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my $client = $hash->{helper}{wsClient};

    my $buf = DevIo_SimpleRead($hash);
    if ( !$buf ) {
        return;
    }
    $buf =~ s///xsm;
    $buf =~ s/\\x\{1e\}//xsm;

    #if ( !( $buf =~ /}$/xsm ) ) {
    #    $buf = substr( $buf, 0, rindex( $buf, "}" ) );
    #}
    if ( length($buf) == 0 ) {
        return;
    }
    Log3( $name, LOG_DEBUG, qq([$name] Received from DevIo: $buf) );

    my @bufs;
    my $index = index( $buf, '}{' );
    if ( $index > 0 ) {
        Log3( $name, LOG_RECEIVE, "[$name] - Splitting double-JSON buffer" );
        push( @bufs, substr( $buf, 0, $index + 1 ) );
        push( @bufs, substr( $buf, $index + 1 ) );
    }
    else {
        push( @bufs, $buf );
    }

    foreach my $bufi (@bufs) {
        Log3( $name, LOG_RECEIVE, "[$name] - Extracted" . $bufi );
        parseWebsocketRead( $hash, $bufi );
    }

    #    $client->read($buf);

    return;
}

sub wsClose {
    my $hash   = shift;
    my $name   = $hash->{NAME};
    my $client = $hash->{helper}{wsClient};
    Log3 $name, LOG_RECEIVE, qq ([$name] - Closing Websocket connection);

    #$client->disconnect;
    DevIo_CloseDev($hash);
    readingsSingleUpdate( $hash, "state", "closed", 0 );

    return;
}
1;

=pod
=item helper
=item summary Retrieve data from Softliq Cloud (Grünbeck)
=item summary_DE Daten aus der Softliq Cloud (Grünbeck) auslesen

=begin html

<a name="SoftliqCloud"></a>
<div>
<ul>
The module reads data from Grünbeck Cloud for Softliq (SD series) water softeners. It also allows setting parameters and controlling the water softener to a certain extent
<br><br><a name='SoftliqCloudDefine'></a>
        <b>Define</b>
        <ul>
define the module with <code>define <name> SoftliqCloud <loginName></code> where login name is the login name for the softliq cloud. After that, set your password <code>set <name> password <password></code>
</ul>
<a name='SoftliqCloudGet'></a>
        <b>Get</b>
        <ul>
<li><a name='authenticate'>authenticate</a>: usually not needed, but in rare cases it might be required to re-authenticate</li>
<li><a name='query'>query</a>: reads the data from the cloud</li>
<li><a name='realtime'>realtime</a>: starts the data streaming (similar to the refresh button in the app)</li>
<li><a name='salt/water'>salt/water</a>: display salt/water history</li>
<li><a name='paramList'>paramList</a>: shows a list of available parameters (readings) with current values. If the meaning is known there's a short explanation for it.</li>
 </ul>
<a name='SoftliqCloudSet'></a>
        <b>Set</b>
        <ul>
<li><a name='param'>param</a>: Allows to set parameters (see paramList) <code>set meineSoftliq <parameterName> <parameterValue></code></li>
<li><a name='regenerate'>regenerate</a>: Immediately starts a regeneration (without warning)</li>
<li><a name='refill'>refill</a>: execute after you refilled (25kg) salt. Allows tracking of remaining salt </li>
<li><a name='password'>password</a>: usually only needed initially (or if you change your password in the cloud)</li>
 </ul>
<a name='SoftliqCloudAttr'></a>
        <b>Attributes</b>
        <ul>
<li><a name='sq_duplex'>sq_duplex</a>: set to 1, if you own a duplex machine</li>
<li><a name='sq_interval'>sq_interval</a>: polling interval in seconds (defaults to 3600)</li>
            </ul>
   </ul>
</div>
=end html

=begin html_DE

<a name=></a>
<div>
<ul>
Das Modul liest Daten aus der Grünbeck Cloud für Softliq Wasserenthärter (SD Serie). Es ermöglicht auch das Setzen von Parametern, sowie eine gewisse Steuerung
<br><br><a name='Define'></a>
        <b>Define</b>
        <ul>
Definiere das Modul mit <code>define <name> SoftliqCloud <loginName></code> wobei login name dein login name für die softliq cloud ist. Danach Passwoert setzen: <code>set <name> password <password></code>
</ul>
<a name='SoftliqCloudGet'></a>
        <b>Get</b>
        <ul>
<li><a name='authenticate'>authenticate</a>: Braucht man im Normalfall nicht, beim Testen hatte ich allerdings Fälle, wo ich mich neu authorisieren musste</li>
<li><a name='query'>query</a>: holt alle Daten aus der Cloud</li>
<li><a name='realtime'>realtime</a>:  triggert das "streaming" (entspricht mehr oder weniger dem refresh Button in der App)</li>
<li><a name='salt/water'>salt/water</a>: zeigt die Salz-/Wasser-Verbrauchshistorie an</li>
<li><a name='paramList'>paramList</a>: Zeigt die verfügbaren Einstellungen mit aktuellen Werten an (Readings). Wenn die Bedeutung bekannt ist, gibt es auch eine Erläuterung</li>
 </ul>
<a name='SoftliqCloudSet'></a>
        <b>Set</b>
        <ul>
<li><a name='param'>param</a>: erlaubt das setzen von Einstellungen (siehe paramList) in der Form <code>set meineSoftliq <parameterName> <parameterValue></code></li>
<li><a name='regenerate'>regenerate</a>: startet die manuelle Regeneration (ohne Nachfrage - geht direkt los)</li>
<li><a name='refill'>refill</a>: Auszuführen wenn (25kg) Salz nachgefüllt wurden. Ermöglicht es das verbleibende Salz zu tracken</li>
<li><a name='password'>password</a>: Einmalig auszuführen, um das Passwort im sicheren Speicher zu setzen.</li>
 </ul>
<a name='SoftliqCloudAttr'></a>
        <b>Attributes</b>
        <ul>
<li><a name='sq_duplex'>sq_duplex</a>: Auf 1 setzen, wenn es sich um einen Duplex Entkalker handelt</li>
<li><a name='sq_interval'>sq_interval</a>: Polling Intervall in Sekunden (Default Wert 3600)</li>
            </ul>
   </ul>
</div>
=end html_DE
=cut

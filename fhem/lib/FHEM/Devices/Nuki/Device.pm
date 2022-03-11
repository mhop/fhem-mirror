###############################################################################
#
# Developed with VSCodium and richterger perl plugin
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
package FHEM::Devices::Nuki::Device;

use strict;
use warnings;
use experimental qw( switch );

use FHEM::Meta;

use GPUtils qw(GP_Import);

BEGIN {

    # Import from main context
    GP_Import(
        qw( init_done
          defs
          modules
          )
    );
}

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

######## Begin Device

my %deviceTypes = (
    0 => 'smartlock',
    2 => 'opener',
    3 => 'smartdoor',
    4 => 'smartlock3'
);

my %deviceTypeIds = reverse(%deviceTypes);

my %modes = (
    2 => {
        0 => 'door mode',
        2 => 'door mode'
    },
    3 => {
        0 => '-',
        2 => ' continuous mode'
    }
);

my %lockStates = (
    0 => {
        0 => 'uncalibrated',
        2 => 'untrained',
        4 => 'uncalibrated'
    },
    1 => {
        0 => 'locked',
        2 => 'online',
        4 => 'locked'
    },
    2 => {
        0 => 'unlocking',
        2 => '-',
        4 => 'unlocking'
    },
    3 => {
        0 => 'unlocked',
        2 => 'rto active',
        4 => 'unlocked'
    },
    4 => {
        0 => 'locking',
        2 => '-',
        4 => 'locking'
    },
    5 => {
        0 => 'unlatched',
        2 => 'open',
        4 => 'unlatched'
    },
    6 => {
        0 => 'unlocked (lock ‘n’ go)',
        2 => '-',
        4 => 'unlocked (lock ‘n’ go)'
    },
    7 => {
        0 => 'unlatching',
        2 => 'opening',
        4 => 'unlatching'
    },
    253 => {
        0 => '-',
        2 => 'boot run',
        4 => '-'
    },
    254 => {
        0 => 'motor blocked',
        2 => '-',
        4 => 'motor blocked'
    },
    255 => {
        0 => 'undefined',
        2 => 'undefined',
        4 => 'undefined'
    }
);

my %doorsensorStates = (
    1 => 'deactivated',
    2 => 'door closed',
    3 => 'door opened',
    4 => 'door state unknown',
    5 => 'calibrating'
);

sub Define {
    my $hash = shift;
    my $def  = shift // return;
    my $version;

    return $@ unless ( FHEM::Meta::SetInternals($hash) );

    $version = FHEM::Meta::Get( $hash, 'version' );
    our $VERSION = $version;

    my ( $name, undef, $nukiId, $deviceType ) = split( m{\s+}xms, $def );
    return 'too few parameters: define <name> NUKIDevice <nukiId> <deviceType>'
      if ( !defined($nukiId)
        || !defined($name) );

    $deviceType =
      defined($deviceType)
      ? $deviceType
      : 0;

    $hash->{NUKIID}       = $nukiId;
    $hash->{DEVICETYPEID} = $deviceType;
    $hash->{VERSION}      = version->parse($VERSION)->normal;
    $hash->{STATE}        = 'Initialized';
    $hash->{NOTIFYDEV}    = 'global,autocreate,' . $name;

    my $iodev = ::AttrVal( $name, 'IODev', 'none' );

    ::AssignIoPort( $hash, $iodev ) if ( !$hash->{IODev} );

    if ( defined( $hash->{IODev}->{NAME} ) ) {
        ::Log3( $name, 3,
            "NUKIDevice ($name) - I/O device is " . $hash->{IODev}->{NAME} );
    }
    else {
        ::Log3( $name, 1, "NUKIDevice ($name) - no I/O device" );
    }

    $iodev = $hash->{IODev}->{NAME};

    $hash->{BRIDGEAPI} = $defs{$iodev}->{BRIDGEAPI}
      if ( defined($iodev)
        && $iodev );

    my $d = $modules{NUKIDevice}{defptr}{$nukiId};

    return
        'NUKIDevice device '
      . $name
      . ' on NUKIBridge '
      . $iodev
      . ' already defined.'
      if ( defined($d)
        && $d->{IODev} == $hash->{IODev}
        && $d->{NAME} ne $name );

    ::Log3( $name, 3, "NUKIDevice ($name) - defined with NukiId: $nukiId" );

    ::CommandAttr( undef, $name . ' room NUKI' )
      if ( ::AttrVal( $name, 'room', 'none' ) eq 'none' );
    ::CommandAttr( undef, $name . ' model ' . $deviceTypes{$deviceType} )
      if ( ::AttrVal( $name, 'model', 'none' ) eq 'none' );

    $modules{NUKIDevice}{defptr}{$nukiId} = $hash;

    GetUpdate($hash)
      if ( ::ReadingsVal( $name, 'success', 'none' ) eq 'none'
        && $init_done );

    return;
}

sub Undef {
    my $hash = shift;

    my $nukiId = $hash->{NUKIID};
    my $name   = $hash->{NAME};

    ::Log3( $name, 3, "NUKIDevice ($name) - undefined with NukiId: $nukiId" );
    delete( $modules{NUKIDevice}{defptr}{$nukiId} );

    return;
}

sub Attr {
    my $cmd      = shift;
    my $name     = shift;
    my $attrName = shift;
    my $attrVal  = shift;

    my $hash  = $defs{$name};
    my $token = $hash->{IODev}->{TOKEN};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' && $attrVal == 1 ) {
            ::readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            ::Log3( $name, 3, "NUKIDevice ($name) - disabled" );
        }

        elsif ( $cmd eq 'del' ) {
            ::readingsSingleUpdate( $hash, 'state', 'active', 1 );
            ::Log3( $name, 3, "NUKIDevice ($name) - enabled" );
        }
    }
    elsif ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            ::Log3( $name, 3,
                "NUKIDevice ($name) - enable disabledForIntervals" );
            ::readingsSingleUpdate( $hash, 'state', 'Unknown', 1 );
        }

        elsif ( $cmd eq 'del' ) {
            ::readingsSingleUpdate( $hash, 'state', 'active', 1 );
            ::Log3( $name, 3,
                "NUKIDevice ($name) - delete disabledForIntervals" );
        }
    }
    elsif ( $attrName eq 'model' ) {
        if ( $cmd eq 'set' ) {
            ::Log3( $name, 3, "NUKIDevice ($name) - change model" );
            $hash->{DEVICETYPEID} = $deviceTypeIds{$attrVal};
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

    GetUpdate($hash)
      if (
        (
               grep { /^INITIALIZED$/x } @{$events}
            or grep { /^REREADCFG$/x } @{$events}
            or grep { /^MODIFIED.$name$/x } @{$events}
            or grep { /^DEFINED.$name$/x } @{$events}
        )
        && $devname eq 'global'
        && $init_done
      );

    return;
}

sub Set {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "set $name needs at least one argument !";

    my $lockAction;

    if ( lc($cmd) eq 'statusrequest' ) {

        GetUpdate($hash);
        return;
    }
    elsif ($cmd eq 'lock'
        || lc($cmd) eq 'deactivaterto'
        || $cmd eq 'unlock'
        || lc($cmd) eq 'activaterto'
        || $cmd eq 'unlatch'
        || lc($cmd) eq 'electricstrikeactuation'
        || lc($cmd) eq 'lockngo'
        || lc($cmd) eq 'activatecontinuousmode'
        || lc($cmd) eq 'lockngowithunlatch'
        || lc($cmd) eq 'deactivatecontinuousmode'
        || $cmd eq 'unpair' )
    {
        $lockAction = $cmd;
    }
    else {
        my $list = '';
        $list =
'statusRequest:noArg unlock:noArg lock:noArg unlatch:noArg locknGo:noArg locknGoWithUnlatch:noArg unpair:noArg'
          if ( $hash->{DEVICETYPEID} == 0
            || $hash->{DEVICETYPEID} == 4 );
        $list =
'statusRequest:noArg activateRto:noArg deactivateRto:noArg electricStrikeActuation:noArg activateContinuousMode:noArg deactivateContinuousMode:noArg unpair:noArg'
          if ( $hash->{DEVICETYPEID} == 2 );

        return ( 'Unknown argument ' . $cmd . ', choose one of ' . $list );
    }

    $hash->{helper}{lockAction} = $lockAction;

    ::IOWrite( $hash, 'lockAction',
            '{"param":"'
          . $lockAction
          . '","nukiId":'
          . $hash->{NUKIID}
          . ',"deviceType":'
          . $hash->{DEVICETYPEID}
          . '}' );

    return;
}

sub GetUpdate {
    my $hash = shift;
    my $name = $hash->{NAME};

    if ( !::IsDisabled($name) ) {
        ::IOWrite( $hash, 'lockState',
                '{"nukiId":'
              . $hash->{NUKIID}
              . ',"deviceType":'
              . $hash->{DEVICETYPEID}
              . '}' );

        ::Log3( $name, 2, "NUKIDevice ($name) - GetUpdate Call IOWrite" );
    }

    return;
}

sub Parse {
    my $hash = shift;
    my $json = shift // return;
    my $name = $hash->{NAME};

    ::Log3( $name, 5, "NUKIDevice ($name) - Parse with result: $json" );

    #########################################
    ####### Errorhandling #############

    if ( $json !~ m{\A[\[{].*[}\]]\z}xms ) {
        ::Log3( $name, 3, "NUKIDevice ($name) - invalid json detected: $json" );
        return "NUKIDevice ($name) - invalid json detected: $json";
    }

    #########################################
    #### verarbeiten des JSON Strings #######
    my $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "NUKIDevice ($name) - JSON error while request: $@" );
        return;
    }

    if ( ref($decode_json) ne 'HASH' ) {
        ::Log3( $name, 2,
"NUKIDevice ($name) - got wrong status message for $name: $decode_json"
        );

        return;
    }

    my $nukiId = $decode_json->{nukiId};
    if ( my $dhash = $modules{NUKIDevice}{defptr}{$nukiId} ) {
        my $dname = $dhash->{NAME};

        WriteReadings( $dhash, $decode_json );
        ::Log3( $dname, 4,
            "NUKIDevice ($dname) - find logical device: $dhash->{NAME}" );

        return $dhash->{NAME};
    }
    else {
        ::Log3( $name, 4,
                "NUKIDevice ($name) - autocreate new device "
              . ::makeDeviceName( $decode_json->{name} )
              . " with nukiId $decode_json->{nukiId}, model $decode_json->{deviceType}"
        );
        return
            'UNDEFINED '
          . ::makeDeviceName( $decode_json->{name} )
          . " NUKIDevice $decode_json->{nukiId} $decode_json->{deviceType}";
    }

    ::Log3( $name, 5, "NUKIDevice ($name) - parse status message for $name" );

    return WriteReadings( $hash, $decode_json );
}

sub SmartlockState {
    ############################
    #### Status des Smartlock
    my $hash        = shift;
    my $decode_json = shift;

    if ( defined( $hash->{helper}{lockAction} ) ) {
        my $state;

        if (
            defined( $decode_json->{success} )
            && (   $decode_json->{success} eq 'true'
                || $decode_json->{success} == 1 )
          )
        {
            $state = $hash->{helper}{lockAction};

            ::IOWrite( $hash, 'lockState',
                    '{"nukiId":'
                  . $hash->{NUKIID}
                  . ',"deviceType":'
                  . $hash->{DEVICETYPEID}
                  . '}' )
              if (
                ::ReadingsVal( $hash->{IODev}->{NAME},
                    'bridgeType', 'Software' ) eq 'Software'
              );

        }
        elsif (
            defined( $decode_json->{success} )
            && (   $decode_json->{success} eq 'false'
                || $decode_json->{success} == 0 )
          )
        {

            $state = $deviceTypes{ $hash->{DEVICETYPEID} } . ' response error';

            ::IOWrite( $hash, 'lockState',
                    '{"nukiId":'
                  . $hash->{NUKIID}
                  . ',"deviceType":'
                  . $hash->{DEVICETYPEID}
                  . '}' );
        }

        $decode_json->{'state'} = $state;
        delete $hash->{helper}{lockAction};
    }

    return $decode_json;
}

sub WriteReadings {
    my $hash        = shift;
    my $decode_json = shift;
    my $name        = $hash->{NAME};

    $decode_json = SmartlockState( $hash, $decode_json );

    ::readingsBeginUpdate($hash);

    my $t;
    my $v;

    if ( defined( $decode_json->{lastKnownState} )
        && ref( $decode_json->{lastKnownState} ) eq 'HASH' )
    {
        while ( ( $t, $v ) = each %{ $decode_json->{lastKnownState} } ) {
            $decode_json->{$t} = $v;
        }

        delete $decode_json->{lastKnownState};
    }

    while ( ( $t, $v ) = each %{$decode_json} ) {
        ::readingsBulkUpdate( $hash, $t, $v )
          if ( $t ne 'state'
            && $t ne 'mode'
            && $t ne 'deviceType'
            && $t ne 'paired'
            && $t ne 'batteryCritical'
            && $t ne 'batteryChargeState'
            && $t ne 'batteryCharging'
            && $t ne 'timestamp'
            && $t ne 'doorsensorState'
            && $t ne 'doorsensorStateName' );

        given ($t) {
            when ('state') {
                ::readingsBulkUpdate(
                    $hash, $t,
                    (
                          $v =~ m{\A[0-9]\z}xms
                        ? $lockStates{$v}->{ $hash->{DEVICETYPEID} }
                        : $v
                    )
                );
            }
            when ('mode') {
                ::readingsBulkUpdate( $hash, $t,
                    $modes{$v}{ $hash->{DEVICETYPEID} } );
            }
            when ('deviceType') {
                ::readingsBulkUpdate( $hash, $t, $deviceTypes{$v} );
            }
            when ('doorsensorState') {
                ::readingsBulkUpdate( $hash, $t, $doorsensorStates{$v} );
            }
            when ('paired') {
                ::readingsBulkUpdate( $hash, $t,
                    ( $v == 1 ? 'true' : 'false' ) );
            }
            when ('batteryCharging') {
                ::readingsBulkUpdate( $hash, $t,
                    ( $v == 1 ? 'true' : 'false' ) );
            }
            when ('batteryCritical') {
                ::readingsBulkUpdate( $hash, 'batteryState',
                    ( $v == 1 ? 'low' : 'ok' ) );
            }
            when ('batteryChargeState') {
                ::readingsBulkUpdate( $hash, 'batteryPercent', $v )
            }
        }
    }

    ::readingsEndUpdate( $hash, 1 );

    ::Log3( $name, 5,
        "NUKIDevice ($name) - lockAction readings set for $name" );

    return;
}

1;

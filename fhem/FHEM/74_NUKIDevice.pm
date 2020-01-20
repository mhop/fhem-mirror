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

package main;

use strict;
use warnings;

package FHEM::NUKIDevice;

use strict;
use warnings;
use FHEM::Meta;
use GPUtils qw(GP_Import GP_Export);

main::LoadModule('NUKIBridge');

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
          makeDeviceName
          defs
          modules
          Log3
          CommandAttr
          CommandDefMod
          AttrVal
          IsDisabled
          deviceEvents
          init_done
          InternalVal
          ReadingsVal
          AssignIoPort
          IOWrite
          data)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      )
);

my %deviceTypes = (
    0 => 'smartlock',
    2 => 'opener'
);

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
        2 => 'untrained'
    },
    1 => {
        0 => 'locked',
        2 => 'online'
    },
    2 => {
        0 => 'unlocking',
        2 => '-'
    },
    3 => {
        0 => 'unlocked',
        2 => 'rto active'
    },
    4 => {
        0 => 'locking',
        2 => '-'
    },
    5 => {
        0 => 'unlatched',
        2 => 'open'
    },
    6 => {
        0 => 'unlocked (lock ‘n’ go)',
        2 => '-'
    },
    7 => {
        0 => 'unlatching',
        2 => 'opening'
    },
    253 => {
        0 => '-',
        2 => 'boot run'
    },
    254 => {
        0 => 'motor blocked',
        2 => '-'
    },
    255 => {
        0 => 'undefined',
        2 => 'undefined'
    }
);

my %deviceTypeIds = reverse(%deviceTypes);

sub Initialize($) {
    my ($hash) = @_;

    $hash->{Match} = '^{.*}$';

    $hash->{SetFn}    = 'FHEM::NUKIDevice::Set';
    $hash->{DefFn}    = 'FHEM::NUKIDevice::Define';
    $hash->{UndefFn}  = 'FHEM::NUKIDevice::Undef';
    $hash->{NotifyFn} = 'FHEM::NUKIDevice::Notify';
    $hash->{AttrFn}   = 'FHEM::NUKIDevice::Attr';
    $hash->{ParseFn}  = 'FHEM::NUKIDevice::Parse';

    $hash->{AttrList} =
        'IODev '
      . 'model:opener,smartlock '
      . 'disable:1 '
      . $readingFnAttributes;

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define($$) {
    my ( $hash, $def ) = @_;
    my @a = split( '[ \t][ \t]*', $def );

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return 'too few parameters: define <name> NUKIDevice <nukiId> <deviceType>'
      if ( @a != 4 );

    my $name       = $a[0];
    my $nukiId     = $a[2];
    my $deviceType = ( defined $a[3] ) ? $a[3] : 0;

    $hash->{NUKIID}     = $nukiId;
    $hash->{DEVICETYPE} = ( defined $deviceType ) ? $deviceType : 0;
    $hash->{VERSION}    = version->parse($VERSION)->normal;
    $hash->{STATE}      = 'Initialized';
    $hash->{NOTIFYDEV}  = 'global,autocreate,' . $name;

    my $iodev = AttrVal( $name, 'IODev', 'none' );

    AssignIoPort( $hash, $iodev ) if ( !$hash->{IODev} );

    if ( defined( $hash->{IODev}->{NAME} ) ) {
        Log3( $name, 3,
            "NUKIDevice ($name) - I/O device is " . $hash->{IODev}->{NAME} );
    }
    else {
        Log3( $name, 1, "NUKIDevice ($name) - no I/O device" );
    }

    $iodev = $hash->{IODev}->{NAME};

    $hash->{BRIDGEAPI} = $defs{$iodev}->{BRIDGEAPI};

    my $d = $modules{NUKIDevice}{defptr}{$nukiId};

    return
        'NUKIDevice device '
      . $name
      . ' on NUKIBridge '
      . $iodev
      . ' already defined.'
      if (  defined($d)
        and $d->{IODev} == $hash->{IODev}
        and $d->{NAME} ne $name );

    Log3( $name, 3, "NUKIDevice ($name) - defined with NukiId: $nukiId" );

    CommandAttr( undef, $name . ' room NUKI' )
      if ( AttrVal( $name, 'room', 'none' ) eq 'none' );
    CommandAttr( undef, $name . ' model ' . $deviceTypes{$deviceType} )
      if ( AttrVal( $name, 'model', 'none' ) eq 'none' );

    $modules{NUKIDevice}{defptr}{$nukiId} = $hash;

    GetUpdate($hash)
      if ( ReadingsVal( $name, 'success', 'none' ) eq 'none'
        and $init_done );

    return undef;
}

sub Undef($$) {
    my ( $hash, $arg ) = @_;

    my $nukiId = $hash->{NUKIID};
    my $name   = $hash->{NAME};

    Log3( $name, 3, "NUKIDevice ($name) - undefined with NukiId: $nukiId" );
    delete( $modules{NUKIDevice}{defptr}{$nukiId} );

    return undef;
}

sub Attr(@) {
    my ( $cmd, $name, $attrName, $attrVal ) = @_;

    my $hash  = $defs{$name};
    my $token = $hash->{IODev}->{TOKEN};

    if ( $attrName eq 'disable' ) {
        if ( $cmd eq 'set' and $attrVal == 1 ) {
            readingsSingleUpdate( $hash, 'state', 'disabled', 1 );
            Log3( $name, 3, "NUKIDevice ($name) - disabled" );
        }

        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3( $name, 3, "NUKIDevice ($name) - enabled" );
        }
    }
    elsif ( $attrName eq 'disabledForIntervals' ) {
        if ( $cmd eq 'set' ) {
            Log3( $name, 3,
                "NUKIDevice ($name) - enable disabledForIntervals" );
            readingsSingleUpdate( $hash, 'state', 'Unknown', 1 );
        }

        elsif ( $cmd eq 'del' ) {
            readingsSingleUpdate( $hash, 'state', 'active', 1 );
            Log3( $name, 3,
                "NUKIDevice ($name) - delete disabledForIntervals" );
        }
    }
    elsif ( $attrName eq 'model' ) {
        if ( $cmd eq 'set' ) {
            Log3( $name, 3, "NUKIDevice ($name) - change model" );
            $hash->{DEVICETYPE} = $deviceTypeIds{$attrVal};
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

    GetUpdate($hash)
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

sub Set($$@) {
    my ( $hash, $name, @aa ) = @_;

    my ( $cmd, @args ) = @aa;
    my $lockAction;

    if ( lc($cmd) eq 'statusrequest' ) {
        return ('usage: statusRequest') if ( @args != 0 );

        GetUpdate($hash);
        return undef;
    }
    elsif ($cmd eq 'lock'
        or lc($cmd) eq 'deactivaterto'
        or $cmd eq 'unlock'
        or lc($cmd) eq 'activaterto'
        or $cmd eq 'unlatch'
        or lc($cmd) eq 'electricstrikeactuation'
        or lc($cmd) eq 'lockngo'
        or lc($cmd) eq 'activatecontinuousmode'
        or lc($cmd) eq 'lockngowithunlatch'
        or lc($cmd) eq 'deactivatecontinuousmode'
        or $cmd eq 'unpair' )
    {
        return ( 'usage: ' . $cmd )
          if ( @args != 0 );
        $lockAction = $cmd;

    }
    else {
        my $list = '';
        $list =
'statusRequest:noArg unlock:noArg lock:noArg unlatch:noArg locknGo:noArg locknGoWithUnlatch:noArg unpair:noArg'
          if ( $hash->{DEVICETYPE} == 0 );
        $list =
'statusRequest:noArg activateRto:noArg deactivateRto:noArg electricStrikeActuation:noArg activateContinuousMode:noArg deactivateContinuousMode:noArg unpair:noArg'
          if ( $hash->{DEVICETYPE} == 2 );

        return ( 'Unknown argument ' . $cmd . ', choose one of ' . $list );
    }

    $hash->{helper}{lockAction} = $lockAction;

    IOWrite( $hash, 'lockAction', $lockAction, $hash->{NUKIID},
        $hash->{DEVICETYPE} );

    return undef;
}

sub GetUpdate($) {
    my $hash = shift;

    my $name = $hash->{NAME};

    if ( !IsDisabled($name) ) {
        IOWrite( $hash, 'lockState', undef, $hash->{NUKIID},
            $hash->{DEVICETYPE} );
        Log3( $name, 2, "NUKIDevice ($name) - GetUpdate Call IOWrite" );
    }

    return undef;
}

sub Parse($$) {
    my ( $hash, $json ) = @_;

    my $name = $hash->{NAME};

    Log3( $name, 5, "NUKIDevice ($name) - Parse with result: $json" );
    #########################################
    ####### Errorhandling #############

    if ( $json !~ m/^[\[{].*[}\]]$/ ) {
        Log3( $name, 3, "NUKIDevice ($name) - invalid json detected: $json" );
        return "NUKIDevice ($name) - invalid json detected: $json";
    }

    #########################################
    #### verarbeiten des JSON Strings #######
    my $decode_json = eval { decode_json($json) };
    if ($@) {
        Log3( $name, 3, "NUKIDevice ($name) - JSON error while request: $@" );
        return;
    }

    if ( ref($decode_json) ne 'HASH' ) {
        Log3( $name, 2,
"NUKIDevice ($name) - got wrong status message for $name: $decode_json"
        );
        return undef;
    }

    my $nukiId = $decode_json->{nukiId};

    if ( my $hash = $modules{NUKIDevice}{defptr}{$nukiId} ) {
        my $name = $hash->{NAME};

        WriteReadings( $hash, $decode_json );
        Log3( $name, 4,
            "NUKIDevice ($name) - find logical device: $hash->{NAME}" );

        ##################
        ## Zwischenlösung so für die Umstellung, kann später gelöscht werden
        if ( AttrVal( $name, 'model', '' ) eq '' ) {
            CommandDefMod( undef,
                    $name
                  . ' NUKIDevice '
                  . $hash->{NUKIID} . ' '
                  . $decode_json->{deviceType} );
            CommandAttr( undef,
                    $name
                  . ' model '
                  . $deviceTypes{ $decode_json->{deviceType} } );
            Log3( $name, 2, "NUKIDevice ($name) - redefined Defmod" );
        }

        return $hash->{NAME};
    }
    else {
        Log3( $name, 3,
                "NUKIDevice ($name) - autocreate new device "
              . makeDeviceName( $decode_json->{name} )
              . " with nukiId $decode_json->{nukiId}, model $decode_json->{deviceType}"
        );
        return
            'UNDEFINED '
          . makeDeviceName( $decode_json->{name} )
          . " NUKIDevice $decode_json->{nukiId} $decode_json->{deviceType}";
    }

    Log3( $name, 5, "NUKIDevice ($name) - parse status message for $name" );

    WriteReadings( $hash, $decode_json );
}

sub WriteReadings($$) {
    my ( $hash, $decode_json ) = @_;

    my $name = $hash->{NAME};

    ############################
    #### Status des Smartlock

    if ( defined( $hash->{helper}{lockAction} ) ) {
        my $state;

        if (
            defined( $decode_json->{success} )
            and (  $decode_json->{success} eq 'true'
                or $decode_json->{success} == 1 )
          )
        {
            $state = $hash->{helper}{lockAction};
            IOWrite( $hash, 'lockState', undef, $hash->{NUKIID} )
              if (
                ReadingsVal( $hash->{IODev}->{NAME}, 'bridgeType', 'Software' )
                eq 'Software' );

        }
        elsif (
            defined( $decode_json->{success} )
            and (  $decode_json->{success} eq 'false'
                or $decode_json->{success} == 0 )
          )
        {

            $state = $deviceTypes{ $hash->{DEVICETYPE} } . ' response error';
            IOWrite( $hash, 'lockState', undef, $hash->{NUKIID},
                $hash->{DEVICETYPE} );
        }

        $decode_json->{'state'} = $state;
        delete $hash->{helper}{lockAction};
    }

    readingsBeginUpdate($hash);

    my $t;
    my $v;

    if ( defined( $decode_json->{lastKnownState} )
        and ref( $decode_json->{lastKnownState} ) eq 'HASH' )
    {
        while ( ( $t, $v ) = each %{ $decode_json->{lastKnownState} } ) {
            $decode_json->{$t} = $v;
        }

        delete $decode_json->{lastKnownState};
    }

    while ( ( $t, $v ) = each %{$decode_json} ) {
        readingsBulkUpdate( $hash, $t, $v )
          unless ( $t eq 'state'
            or $t eq 'mode'
            or $t eq 'deviceType'
            or $t eq 'paired'
            or $t eq 'batteryCritical'
            or $t eq 'timestamp' );
        readingsBulkUpdate( $hash, $t,
            ( $v =~ m/^[0-9]$/ ? $lockStates{$v}{ $hash->{DEVICETYPE} } : $v ) )
          if ( $t eq 'state' );
        readingsBulkUpdate( $hash, $t, $modes{$v}{ $hash->{DEVICETYPE} } )
          if ( $t eq 'mode' );
        readingsBulkUpdate( $hash, $t, $deviceTypes{$v} )
          if ( $t eq 'deviceType' );
        readingsBulkUpdate( $hash, $t, ( $v == 1 ? 'true' : 'false' ) )
          if ( $t eq 'paired' );
        readingsBulkUpdate( $hash, 'batteryState',
            ( ( $v eq 'true' or $v == 1 ) ? 'low' : 'ok' ) )
          if ( $t eq 'batteryCritical' );
    }

    readingsEndUpdate( $hash, 1 );

    Log3( $name, 5, "NUKIDevice ($name) - lockAction readings set for $name" );

    return undef;
}

1;

=pod
=item device
=item summary    Modul to control the Nuki Smartlock's
=item summary_DE Modul zur Steuerung des Nuki Smartlocks.

=begin html

<a name="NUKIDevice"></a>
<h3>NUKIDevice</h3>
<ul>
  <u><b>NUKIDevice - Controls the Nuki Smartlock</b></u>
  <br>
  The Nuki module connects FHEM over the Nuki Bridge with a Nuki Smartlock or Nuki Opener. After that, it´s possible to lock and unlock the Smartlock.<br>
  Normally the Nuki devices are automatically created by the bridge module.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt; &lt;Device-Type&gt;</code>
    <br><br>
    Device-Type is 0 for the Smartlock and 2 for the Opener.
    <br><br>
    Example:
    <ul><br>
      <code>define Frontdoor NUKIDevice 1 NBridge1 0</code><br>
    </ul>
    <br>
    This statement creates a NUKIDevice with the name Frontdoor, the NukiId 1 and the IODev device NBridge1.<br>
    After the device has been created, the current state of the Smartlock is automatically read from the bridge.
  </ul>
  <br><br>
  <a name="NUKIDevicereadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status of the Smartlock or error message if any error.</li>
    <li>lockState - current lock status uncalibrated, locked, unlocked, unlocked (lock ‘n’ go), unlatched, locking, unlocking, unlatching, motor blocked, undefined.</li>
    <li>name - name of the device</li>
    <li>paired - paired information false/true</li>
    <li>rssi - value of rssi</li>
    <li>succes - true, false   Returns the status of the last closing command. Ok or not Ok.</li>
    <li>batteryCritical - Is the battery in a critical state? True, false</li>
    <li>batteryState - battery status, ok / low</li>
  </ul>
  <br><br>
  <a name="NUKIDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - retrieves the current state of the smartlock from the bridge.</li>
    <li>lock - lock</li>
    <li>unlock - unlock</li>
    <li>unlatch - unlock / open Door</li>
    <li>unpair -  Removes the pairing with a given Smart Lock</li>
    <li>locknGo - lock when gone</li>
    <li>locknGoWithUnlatch - lock after the door has been opened</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIDeviceattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki device</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NUKIDevice"></a>
<h3>NUKIDevice</h3>
<ul>
  <u><b>NUKIDevice - Steuert das Nuki Smartlock</b></u>
  <br>
  Das Nuki Modul verbindet FHEM über die Nuki Bridge  mit einem Nuki Smartlock oder Nuki Opener. Es ist dann m&ouml;glich das Schloss zu ver- und entriegeln.<br>
  In der Regel werden die Nuki Devices automatisch durch das Bridgemodul angelegt.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt; &lt;Device-Type&gt;</code>
    <br><br>
    Device-Type ist 0 f&uuml;r das Smartlock und 2 f&üuml;r den Opener.
    <br><br>
    Beispiel:
    <ul><br>
      <code>define Haust&uuml;r NUKIDevice 1 NBridge1 0</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIDevice mit Namen Haust&uuml;r, der NukiId 1 sowie dem IODev Device NBridge1.<br>
    Nach dem anlegen des Devices wird automatisch der aktuelle Zustand des Smartlocks aus der Bridge gelesen.
  </ul>
  <br><br>
  <a name="NUKIDevicereadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status des Smartlock bzw. Fehlermeldung von Fehler vorhanden.</li>
    <li>lockState - aktueller Schlie&szlig;status uncalibrated, locked, unlocked, unlocked (lock ‘n’ go), unlatched, locking, unlocking, unlatching, motor blocked, undefined.</li>
    <li>name - Name des Smart Locks</li>
    <li>paired - pairing Status des Smart Locks</li>
    <li>rssi - rssi Wert des Smart Locks</li>
    <li>succes - true, false Gibt des Status des letzten Schlie&szlig;befehles wieder. Geklappt oder nicht geklappt.</li>
    <li>batteryCritical - Ist die Batterie in einem kritischen Zustand? true, false</li>
    <li>batteryState - Status der Batterie, ok/low</li>
  </ul>
  <br><br>
  <a name="NUKIDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - ruft den aktuellen Status des Smartlocks von der Bridge ab.</li>
    <li>lock - verschlie&szlig;en</li>
    <li>unlock - aufschlie&szlig;en</li>
    <li>unlatch - entriegeln/Falle &ouml;ffnen.</li>
    <li>unpair -  entfernt das pairing mit dem Smart Lock</li>
    <li>locknGo - verschlie&szlig;en wenn gegangen</li>
    <li>locknGoWithUnlatch - verschlie&szlig;en nach dem die Falle ge&ouml;ffnet wurde.</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIDeviceattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Nuki Device</li>
    <br>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 74_NUKIDevice.pm
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
  "version": "v1.9.12",
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

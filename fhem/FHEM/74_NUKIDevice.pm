###############################################################################
# 
# Developed with Kate
#
#  (c) 2016 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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
use JSON;
#use Time::HiRes qw(gettimeofday);

my $version = "0.2.1";




sub NUKIDevice_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}	    = "NUKIDevice_Set";
    $hash->{DefFn}	    = "NUKIDevice_Define";
    $hash->{UndefFn}	    = "NUKIDevice_Undef";
    $hash->{AttrFn}	    = "NUKIDevice_Attr";
    
    $hash->{AttrList} 	    = "IODev ".
                              "disable:1 ".
                              "interval ".
                              $readingFnAttributes;



    foreach my $d(sort keys %{$modules{NUKIDevice}{defptr}}) {
	my $hash = $modules{NUKIDevice}{defptr}{$d};
	$hash->{VERSION} 	= $version;
    }
}

sub NUKIDevice_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t]+", $def );
    splice( @a, 1, 1 );
    my $iodev;
    my $i = 0;
    
    foreach my $param ( @a ) {
        if( $param =~ m/IODev=([^\s]*)/ ) {
            $iodev = $1;
            splice( @a, $i, 3 );
            last;
        }
        
        $i++;
    }

    return "too few parameters: define <name> NUKIDevice <nukiId>" if( @a < 2 );

    my ($name,$nukiId)  = @a;

    $hash->{NUKIID} 	= $nukiId;
    $hash->{VERSION} 	= $version;
    $hash->{STATE}      = 'Initialized';
    $hash->{INTERVAL}   = 20;
    
    
    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
    
        Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
    } else {
    
        Log3 $name, 1, "$name: no I/O device";
    }
    
    $iodev = $hash->{IODev}->{NAME};

    
    my $code = $hash->{NUKIID};
    $code = $iodev ."-". $code if( defined($iodev) );
    my $d = $modules{NUKIDevice}{defptr}{$code};
    return "NUKIDevice device $hash->{NUKIID} on NUKIBridge $iodev already defined as $d->{NAME}."
        if( defined($d)
            && $d->{IODev} == $hash->{IODev}
            && $d->{NAME} ne $name );

    $modules{NUKIDevice}{defptr}{$code} = $hash;
  
  
    Log3 $name, 3, "NUKIDevice ($name) - defined with Code: $code";

    $attr{$name}{room} = "NUKI" if( !defined( $attr{$name}{room} ) );
    
    
    RemoveInternalTimer($hash);
    
    if( $init_done ) {
        NUKIDevice_GetUpdateInternalTimer($hash);
    } else {
        InternalTimer(gettimeofday()+20, "NUKIDevice_GetUpdateInternalTimer", $hash, 0);
    }

    return undef;
}

sub NUKIDevice_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $nukiId = $hash->{NUKIID};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);

    my $code = $hash->{NUKIID};
    $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
    Log3 $name, 3, "NUKIDevice ($name) - undefined with Code: $code";
    delete($modules{HUEDevice}{defptr}{$code});

    return undef;
}

sub NUKIDevice_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if( $attrName eq "disable" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal eq "0" ) {
		RemoveInternalTimer( $hash );
		InternalTimer( gettimeofday()+2, "NUKIDevice_GetUpdateInternalTimer", $hash, 0 );
		readingsSingleUpdate ( $hash, "state", "Initialized", 1 );
		Log3 $name, 3, "NUKIDevice ($name) - enabled";
	    } else {
		readingsSingleUpdate ( $hash, "state", "disabled", 1 );
		RemoveInternalTimer( $hash );
		Log3 $name, 3, "NUKIDevice ($name) - disabled";
	    }
	    
	} else {
	
	    RemoveInternalTimer( $hash );
	    InternalTimer( gettimeofday()+2, "NUKIDevice_GetUpdateInternalTimer", $hash, 0 );
	    readingsSingleUpdate ( $hash, "state", "Initialized", 1 );
	    Log3 $name, 3, "NUKIDevice ($name) - enabled";
        }
    }
    
    if( $attrName eq "interval" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal < 10 ) {
		Log3 $name, 3, "NUKIDevice ($name) - interval too small, please use something > 10 (sec), default is 20 (sec)";
		return "interval too small, please use something > 10 (sec), default is 60 (sec)";
	    } else {
		$hash->{INTERVAL} = $attrVal;
		Log3 $name, 3, "NUKIDevice ($name) - set interval to $attrVal";
	    }
	    
	} else {
	
	    $hash->{INTERVAL} = 20;
	    Log3 $name, 3, "NUKIDevice ($name) - set interval to default";
        }
    }
    
    return undef;
}

sub NUKIDevice_Set($$@) {
    
    my ($hash, $name, @aa) = @_;
    my ($cmd, @args) = @aa;

    my $lockAction;


    if( $cmd eq 'statusRequest' ) {
        return "usage: statusRequest" if( @args != 0 );

        NUKIDevice_GetUpdate($hash);
        return undef;
        
    } elsif( $cmd eq 'lock' ) {
        $lockAction = $cmd;

    } elsif( $cmd eq 'unlock' ) {
        $lockAction = $cmd;
        
    } elsif( $cmd eq 'unlatch' ) {
        $lockAction = $cmd;
        
    } elsif( $cmd eq 'locknGo' ) {
        $lockAction = $cmd;
        
    } elsif( $cmd eq 'locknGoWithUnlatch' ) {
        $lockAction = $cmd;
        
    
    } else {
        my $list = "statusRequest:noArg unlock:noArg lock:noArg unlatch:noArg locknGo:noArg locknGoWithUnlatch:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    $hash->{helper}{lockAction} = $lockAction;
    NUKIDevice_ReadFromNUKIBridge($hash,"lockAction",$lockAction,$hash->{NUKIID} );
    
    return undef;
}

sub NUKIDevice_GetUpdate($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    
    NUKIDevice_ReadFromNUKIBridge($hash, "lockState", undef, $hash->{NUKIID} );
    Log3 $name, 5, "NUKIDevice ($name) - NUKIDevice_GetUpdate Call NUKIDevice_ReadFromNUKIBridge";

    return undef;
}

sub NUKIDevice_GetUpdateInternalTimer($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    
    NUKIDevice_GetUpdate($hash);
    Log3 $name, 5, "NUKIDevice ($name) - Call NUKIDevice_GetUpdate";
    
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "NUKIDevice_GetUpdateInternalTimer", $hash, 0) if( $hash->{INTERVAL} );
    Log3 $name, 5, "NUKIDevice ($name) - Call InternalTimer";
}

sub NUKIDevice_ReadFromNUKIBridge($@) {

    my ($hash,@a) = @_;
    my $name = $hash->{NAME};
    
    no strict "refs";
    my $ret;
    unshift(@a,$name);
    
    $ret = IOWrite($hash,$hash,@a);
    use strict "refs";
    return $ret;
    return if(IsDummy($name) || IsIgnored($name));
    my $iohash = $hash->{IODev};
    
    if(!$iohash ||
        !$iohash->{TYPE} ||
        !$modules{$iohash->{TYPE}} ||
        !$modules{$iohash->{TYPE}}{ReadFn}) {
        Log3 $name, 3, "No I/O device or ReadFn found for $name";
        return;
    }

    no strict "refs";
    unshift(@a,$name);
    $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
    use strict "refs";
    return $ret;
}

sub NUKIDevice_Parse($$) {

    my($hash,$result) = @_;
    my $name = $hash->{NAME};


    #########################################
    ####### Errorhandling #############
    
    if( $result =~ /\d{3}/ ) {
        if( $result eq 400 ) {
            readingsSingleUpdate( $hash, "state", "action is undefined", 1 );
            Log3 $name, 3, "NUKIDevice ($name) - action is undefined";
            return;
        }
    
        if( $result eq 404 ) {
            readingsSingleUpdate( $hash, "state", "nukiId is not known", 1 );
            Log3 $name, 3, "NUKIDevice ($name) - nukiId is not known";
            return;
        }
    }
    
    
    #########################################
    #### verarbeiten des JSON Strings #######
    
    my $decode_json = decode_json($result);
    
    if( ref($decode_json) ne "HASH" ) {
        Log3 $name, 2, "$name: got wrong status message for $name: $decode_json";
        return undef;
    }

    Log3 $name, 5, "parse status message for $name";
    
    
    ############################
    #### Status des Smartlock
    
    readingsBeginUpdate($hash);
    
    
    my $battery;
    if( $decode_json->{batteryCritical} eq "false" ) {
        $battery = "ok";
    } else {
        $battery = "low";
    }

    if( defined($hash->{helper}{lockAction}) ) {
    
        my ($state,$lockState);
        
        $state = $hash->{helper}{lockAction} if( $decode_json->{success} eq "true" );
        $state = "error" if( $decode_json->{success} eq "false" );
        $lockState = $hash->{helper}{lockAction} if( $decode_json->{success} eq "true" );
        
        
        readingsBulkUpdate( $hash, "state", $state );
        readingsBulkUpdate( $hash, "lockState", $lockState );
        readingsBulkUpdate( $hash, "success", $decode_json->{success} );
        readingsBulkUpdate( $hash, "batteryCritical", $decode_json->{batteryCritical} );
        readingsBulkUpdate( $hash, "battery", $battery );
        
        delete $hash->{helper}{lockAction};
    
    } else {
        
        readingsBulkUpdate( $hash, "batteryCritical", $decode_json->{batteryCritical} );
        readingsBulkUpdate( $hash, "lockState", $decode_json->{stateName} );
        readingsBulkUpdate( $hash, "state", $decode_json->{stateName} );
        readingsBulkUpdate( $hash, "battery", $battery );
        readingsBulkUpdate( $hash, "success", $decode_json->{success} );
    
        Log3 $name, 5, "readings set for $name";
    }
    
    readingsEndUpdate( $hash, 1 );
    
    return undef;
}



1;




=pod
=item device
=item summary    
=item summary_DE Modul zur Steuerung des Nuki Smartlocks.

=begin html

<a name="NUKIDevice"></a>
<h3>NUKIDevice</h3>
<ul>
  <u><b>NUKIDevice - Controls the Nuki Smartlock</b></u>
  <br>
  The Nuki module connects FHEM over the Nuki Bridge with a Nuki Smartlock. After that, it´s possible to lock and unlock the Smartlock.<br>
  Normally the Nuki devices are automatically created by the bridge module.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Frontdoor NUKIDevice 1 NBridge1</code><br>
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
    <li>succes - true, false   Returns the status of the last closing command. Ok or not Ok.</li>
    <li>batteryCritical - Is the battery in a critical state? True, false</li>
    <li>battery - battery status, ok / low</li>
  </ul>
  <br><br>
  <a name="NUKIDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - retrieves the current state of the smartlock from the bridge.</li>
    <li>lock - lock</li>
    <li>unlock - unlock</li>
    <li>unlatch - unlock / open Door</li>
    <li>locknGo - lock when gone</li>
    <li>locknGoWithUnlatch - lock after the door has been opened</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIDeviceattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki device</li>
    <li>interval - changes the interval for the statusRequest</li>
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
  Das Nuki Modul verbindet FHEM über die Nuki Bridge  mit einem Nuki Smartlock. Es ist dann m&ouml;glich das Schloss zu ver- und entriegeln.<br>
  In der Regel werden die Nuki Devices automatisch durch das Bridgemodul angelegt.
  <br><br>
  <a name="NUKIDevicedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIDevice &lt;Nuki-Id&gt; &lt;IODev-Device&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define Haust&uuml;r NUKIDevice 1 NBridge1</code><br>
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
    <li>succes - true, false Gibt des Status des letzten Schlie&szlig;befehles wieder. Geklappt oder nicht geklappt.</li>
    <li>batteryCritical - Ist die Batterie in einem kritischen Zustand? true, false</li>
    <li>battery - Status der Batterie, ok/low</li>
  </ul>
  <br><br>
  <a name="NUKIDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - ruft den aktuellen Status des Smartlocks von der Bridge ab.</li>
    <li>lock - verschlie&szlig;en</li>
    <li>unlock - aufschlie&szlig;en</li>
    <li>unlatch - entriegeln/Falle &ouml;ffnen.</li>
    <li>locknGo - verschlie&szlig;en wenn gegangen</li>
    <li>locknGoWithUnlatch - verschlie&szlig;en nach dem die Falle ge&ouml;ffnet wurde.</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIDeviceattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Nuki Device</li>
    <li>interval - verändert den Interval für den statusRequest</li>
    <br>
  </ul>
</ul>

=end html_DE
=cut
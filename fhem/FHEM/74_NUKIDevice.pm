###############################################################################
# 
# Developed with Kate
#
#  (c) 2016-2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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


my $version = "0.6.2";




# Declare functions
sub NUKIDevice_Initialize($);
sub NUKIDevice_Define($$);
sub NUKIDevice_Undef($$);
sub NUKIDevice_Attr(@);
sub NUKIDevice_addExtension($$$);
sub NUKIDevice_removeExtension($);
sub NUKIDevice_Set($$@);
sub NUKIDevice_GetUpdate($);
sub NUKIDevice_ReadFromNUKIBridge($@);
sub NUKIDevice_Parse($$);
sub NUKIDevice_WriteReadings($$);
sub NUKIDevice_CGI();





sub NUKIDevice_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}          = "NUKIDevice_Set";
    $hash->{DefFn}          = "NUKIDevice_Define";
    $hash->{UndefFn}        = "NUKIDevice_Undef";
    $hash->{AttrFn}         = "NUKIDevice_Attr";
    
    my $webhookFWinstance   = join( ",", devspec2array('TYPE=FHEMWEB:FILTER=TEMPORARY!=1') );
    
    $hash->{AttrList}       = "IODev ".
                              "disable:1 ".
                              "webhookFWinstance:$webhookFWinstance ".
                              "webhookHttpHostname ".
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

    $hash->{NUKIID}     = $nukiId;
    $hash->{VERSION}    = $version;
    $hash->{STATE}      = 'Initialized';
    my $infix = "NUKIDevice";
    
    
    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
    
        Log3 $name, 3, "NUKIDevice ($name) - I/O device is " . $hash->{IODev}->{NAME};
    } else {
    
        Log3 $name, 1, "NUKIDevice ($name) - no I/O device";
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
    
    if ( NUKIDevice_addExtension( $name, "NUKIDevice_CGI", $infix ) ) {
        $hash->{fhem}{infix} = $infix;
    }

    $hash->{WEBHOOK_REGISTER} = "unregistered";
    
    
    
    if( $init_done ) {
        InternalTimer( gettimeofday()+int(rand(10)), "NUKIDevice_GetUpdate", $hash, 0 );
    } else {
        InternalTimer( gettimeofday()+15+int(rand(5)), "NUKIDevice_GetUpdate", $hash, 0 );
    }

    return undef;
}

sub NUKIDevice_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $nukiId = $hash->{NUKIID};
    my $name = $hash->{NAME};
    
    
    if ( defined( $hash->{fhem}{infix} ) ) {
        NUKIDevice_removeExtension( $hash->{fhem}{infix} );
    }
    
    RemoveInternalTimer($hash);

    my $code = $hash->{NUKIID};
    $code = $hash->{IODev}->{NAME} ."-". $code if( defined($hash->{IODev}->{NAME}) );
    Log3 $name, 3, "NUKIDevice ($name) - undefined with Code: $code";
    delete($modules{NUKIDevice}{defptr}{$code});

    return undef;
}

sub NUKIDevice_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    my $token = $hash->{IODev}->{TOKEN};

    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "NUKIDevice ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "NUKIDevice ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "NUKIDevice ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "NUKIDevice ($name) - delete disabledForIntervals";
        }
    }
    
    ######################
    #### webhook #########
    
    return "Invalid value for attribute $attrName: can only by FQDN or IPv4 or IPv6 address" if ( $attrVal && $attrName eq "webhookHttpHostname" && $attrVal !~ /^([A-Za-z_.0-9]+\.[A-Za-z_.0-9]+)|[0-9:]+$/ );

    return "Invalid value for attribute $attrName: needs to be different from the defined name/address of your Smartlock, we need to know how Smartlock can connect back to FHEM here!" if ( $attrVal && $attrName eq "webhookHttpHostname" && $attrVal eq $hash->{DeviceName} );

    return "Invalid value for attribute $attrName: FHEMWEB instance $attrVal not existing" if ( $attrVal && $attrName eq "webhookFWinstance" && ( !defined( $defs{$attrVal} ) || $defs{$attrVal}{TYPE} ne "FHEMWEB" ) );

    return "Invalid value for attribute $attrName: needs to be an integer value" if ( $attrVal && $attrName eq "webhookPort" && $attrVal !~ /^\d+$/ );
    
    
    
    
    if ( $attrName =~ /^webhook.*/ ) {
    
        my $webhookHttpHostname = ( $attrName eq "webhookHttpHostname" ? $attrVal : AttrVal( $name, "webhookHttpHostname", "" ) );
        my $webhookFWinstance = ( $attrName eq "webhookFWinstance" ? $attrVal : AttrVal( $name, "webhookFWinstance", "" ) );
        
        $hash->{WEBHOOK_URI} = "/" . AttrVal( $webhookFWinstance, "webname", "fhem" ) . "/NUKIDevice";
        $hash->{WEBHOOK_PORT} = ( $attrName eq "webhookPort" ? $attrVal : AttrVal( $name, "webhookPort", InternalVal( $webhookFWinstance, "PORT", "" )) );

        $hash->{WEBHOOK_URL}     = "";
        $hash->{WEBHOOK_COUNTER} = "0";
        
        if ( $webhookHttpHostname ne "" && $hash->{WEBHOOK_PORT} ne "" ) {
        
            $hash->{WEBHOOK_URL} = "http://" . $webhookHttpHostname . ":" . $hash->{WEBHOOK_PORT} . $hash->{WEBHOOK_URI} . "-" . $hash->{NUKIID};
            my $url = "http://$webhookHttpHostname" . ":" . $hash->{WEBHOOK_PORT} . $hash->{WEBHOOK_URI} . "-" . $hash->{NUKIID};

            Log3 $name, 3, "NUKIDevice ($name) - URL ist: $url";
            NUKIDevice_ReadFromNUKIBridge($hash,"callback/add",$url,undef ) if( $init_done );
            $hash->{WEBHOOK_REGISTER} = "sent";
            
        } else {
            $hash->{WEBHOOK_REGISTER} = "incomplete_attributes";
        }
    }
    
    return undef;
}

sub NUKIDevice_addExtension($$$) {

    my ( $name, $func, $link ) = @_;
    my $url = "/$link";

    
    return 0 if ( defined( $data{FWEXT}{$url} ) && $data{FWEXT}{$url}{deviceName} ne $name );

    Log3 $name, 2, "NUKIDevice ($name) - Registering NUKIDevice for webhook URI $url ...";
    
    $data{FWEXT}{$url}{deviceName} = $name;
    $data{FWEXT}{$url}{FUNC}       = $func;
    $data{FWEXT}{$url}{LINK}       = $link;

    return 1;
}

sub NUKIDevice_removeExtension($) {
    
    my ($link) = @_;

    my $url  = "/$link";
    my $name = $data{FWEXT}{$url}{deviceName};
    
    Log3 $name, 2, "NUKIDevice ($name) - Unregistering NUKIDevice for webhook URL $url...";
    delete $data{FWEXT}{$url};
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
    
    } elsif( $cmd eq 'unpair' ) {
        
        NUKIDevice_ReadFromNUKIBridge($hash,"$cmd",undef,$hash->{NUKIID} ) if( !IsDisabled($name) );
        return undef;
    
    } else {
        my  $list = "statusRequest:noArg unlock:noArg lock:noArg unlatch:noArg locknGo:noArg locknGoWithUnlatch:noArg unpair:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    $hash->{helper}{lockAction} = $lockAction;
    NUKIDevice_ReadFromNUKIBridge($hash,"lockAction",$lockAction,$hash->{NUKIID} ) if( !IsDisabled($name) );
    
    return undef;
}

sub NUKIDevice_GetUpdate($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    RemoveInternalTimer($hash);
    
    NUKIDevice_ReadFromNUKIBridge($hash, "lockState", undef, $hash->{NUKIID} ) if( !IsDisabled($name) );
    Log3 $name, 5, "NUKIDevice ($name) - NUKIDevice_GetUpdate Call NUKIDevice_ReadFromNUKIBridge" if( !IsDisabled($name) );

    return undef;
}

sub NUKIDevice_ReadFromNUKIBridge($@) {

    my ($hash,@a) = @_;
    my $name = $hash->{NAME};
    
    Log3 $name, 4, "NUKIDevice ($name) - NUKIDevice_ReadFromNUKIBridge check Bridge connected";
    return "IODev $hash->{IODev} is not connected" if( ReadingsVal($hash->{IODev}->{NAME},"state","not connected") eq "not connected" );
    
    
    no strict "refs";
    my $ret;
    unshift(@a,$name);
    
    Log3 $name, 4, "NUKIDevice ($name) - NUKIDevice_ReadFromNUKIBridge Bridge is connected call IOWrite";
    
    $ret = IOWrite($hash,$hash,@a);
    use strict "refs";
    return $ret;
    return if(IsDummy($name) || IsIgnored($name));
    my $iohash = $hash->{IODev};
    
    if(!$iohash ||
        !$iohash->{TYPE} ||
        !$modules{$iohash->{TYPE}} ||
        !$modules{$iohash->{TYPE}}{ReadFn}) {
        Log3 $name, 3, "NUKIDevice ($name) - No I/O device or ReadFn found for $name";
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

    Log3 $name, 5, "NUKIDevice ($name) - Parse with result: $result";
    #########################################
    ####### Errorhandling #############
    
    if( !$result ) {
        Log3 $name, 3, "NUKIDevice ($name) - empty answer received";
        return undef;
    } elsif( $result =~ m'HTTP/1.1 200 OK' ) {
        Log3 $name, 4, "NUKIDevice ($name) - empty answer received";
        return undef;
    } elsif( $result !~ m/^[\[{].*[}\]]$/ ) {
        Log3 $name, 3, "NUKIDevice ($name) - invalid json detected: $result";
        return "NUKIDevice ($name) - invalid json detected: $result";
    }
    
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
        
        if( $result eq 503 ) {
            readingsSingleUpdate( $hash, "state", "smartlock is offline", 1 );
            Log3 $name, 3, "NUKIDevice ($name) - smartlock is offline";
            return;
        }
    }
    
    
    #########################################
    #### verarbeiten des JSON Strings #######
    my $decode_json = eval{decode_json($result)};
    if($@){
        Log3 $name, 3, "NUKIDevice ($name) - JSON error while request: $@";
        return;
    }
    
    
    if( ref($decode_json) ne "HASH" ) {
        Log3 $name, 2, "NUKIDevice ($name) - got wrong status message for $name: $decode_json";
        return undef;
    }

    Log3 $name, 5, "NUKIDevice ($name) - parse status message for $name";
    
    NUKIDevice_WriteReadings($hash,$decode_json);
}

sub NUKIDevice_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    
    
    ############################
    #### Status des Smartlock
    
    my $battery;
    if( defined($decode_json->{batteryCritical}) ) {
        if( $decode_json->{batteryCritical} eq "false" or $decode_json->{batteryCritical} == 0 ) {
            $battery = "ok";
        } elsif ( $decode_json->{batteryCritical} eq "true" or $decode_json->{batteryCritical} == 1 ) {
            $battery = "low";
        } else {
            $battery = "parseError";
        }
    }


    readingsBeginUpdate($hash);
    
    if( defined($hash->{helper}{lockAction}) ) {
    
        my ($state,$lockState);
        
        
        if( defined($decode_json->{success}) and ($decode_json->{success} eq "true" or $decode_json->{success} eq "1") ) {
        
            $state = $hash->{helper}{lockAction};
            $lockState = $hash->{helper}{lockAction};
            NUKIDevice_ReadFromNUKIBridge($hash, "lockState", undef, $hash->{NUKIID} ) if( ReadingsVal($hash->{IODev}->{NAME},'bridgeType','Software') eq 'Software' );
            
        } elsif ( defined($decode_json->{success}) and ($decode_json->{success} eq "false" or $decode_json->{success} eq "0") ) {
        
            $state = "error";
            NUKIDevice_ReadFromNUKIBridge($hash, "lockState", undef, $hash->{NUKIID} );
        }

        readingsBulkUpdate( $hash, "state", $state );
        readingsBulkUpdate( $hash, "lockState", $lockState );
        readingsBulkUpdate( $hash, "success", $decode_json->{success} );
        
        
        delete $hash->{helper}{lockAction};
        Log3 $name, 5, "NUKIDevice ($name) - lockAction readings set for $name";
    
    } else {
        
        readingsBulkUpdate( $hash, "batteryCritical", $decode_json->{batteryCritical} );
        readingsBulkUpdate( $hash, "lockState", $decode_json->{stateName} );
        readingsBulkUpdate( $hash, "state", $decode_json->{stateName} );
        readingsBulkUpdate( $hash, "battery", $battery );
        readingsBulkUpdate( $hash, "success", $decode_json->{success} );
        
        readingsBulkUpdate( $hash, "name", $decode_json->{name} );
        readingsBulkUpdate( $hash, "rssi", $decode_json->{rssi} );
        readingsBulkUpdate( $hash, "paired", $decode_json->{paired} );
    
        Log3 $name, 5, "NUKIDevice ($name) - readings set for $name";
    }
    
    readingsEndUpdate( $hash, 1 );
    
    
    return undef;
}

sub NUKIDevice_CGI() {

    my ($request) = @_;
    
    my $hash;
    my $name;
    my $nukiId;
    
    
    # data received
    # Testaufruf:
    # curl --data '{"nukiId": 123456, "state": 1,"stateName": "locked", "batteryCritical": false}' http://10.6.6.20:8083/fhem/NUKIDevice-123456
    # wget --post-data '{"nukiId": 123456, "state": 1,"stateName": "locked", "batteryCritical": false}' http://10.6.6.20:8083/fhem/NUKIDevice-123456
    
    
    my $header = join("\n", @FW_httpheader);

    my ($first,$json) = split("&",$request,2);
    
    if( !$json ) {
        Log3 $name, 3, "NUKIDevice ($name) - empty answer received";
        return undef;
    } elsif( $json =~ m'HTTP/1.1 200 OK' ) {
        Log3 $name, 4, "NUKIDevice ($name) - empty answer received";
        return undef;
    } elsif( $json !~ m/^[\[{].*[}\]]$/ ) {
        Log3 $name, 3, "NUKIDevice ($name) - invalid json detected: $json";
        return "NUKIDevice ($name) - invalid json detected: $json";
    }

    my $decode_json = eval{decode_json($json)};
    if($@){
        Log3 $name, 3, "NUKIDevice ($name) - JSON error while request: $@";
        return;
    }
    
    
    if( ref($decode_json) eq "HASH" ) {
        if ( defined( $modules{NUKIDevice}{defptr} ) ) {
            while ( my ( $key, $value ) = each %{ $modules{NUKIDevice}{defptr} } ) {

                $hash = $modules{NUKIDevice}{defptr}{$key};
                $name = $hash->{NAME};
                $nukiId = InternalVal( $name, "NUKIID", undef );
                next if ( !$nukiId or $nukiId ne $decode_json->{nukiId} );

                $hash->{WEBHOOK_COUNTER}++;
                $hash->{WEBHOOK_LAST} = TimeNow();

                Log3 $name, 4, "NUKIDevice ($name) - Received webhook for matching NukiId at device $name";
            
                NUKIDevice_Parse($hash,$json);
            }
        }
        
        return ( undef, undef );
    }
    
    # no data received
    else {
    
        Log3 undef, 4, "NUKIDevice - received malformed request\n$request";
    }

    return ( "text/plain; charset=utf-8", "Call failure: " . $request );
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
    <li>name - name of the device</li>
    <li>paired - paired information false/true</li>
    <li>rssi - value of rssi</li>
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
    <li>webhookFWinstance - Webinstanz of the Callback</li>
    <li>webhookHttpHostname - IP or FQDN of the FHEM Server Callback</li>
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
    <li>name - Name des Smart Locks</li>
    <li>paired - pairing Status des Smart Locks</li>
    <li>rssi - rssi Wert des Smart Locks</li>
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
    <li>webhookFWinstance - zu verwendene Webinstanz für den Callbackaufruf</li>
    <li>webhookHttpHostname - IP oder FQDN vom FHEM Server für den Callbackaufruf</li>
    <br>
  </ul>
</ul>

=end html_DE
=cut

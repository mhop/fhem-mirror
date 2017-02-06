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
use POSIX;

use JSON;
use Blocking;

my $version = "0.6.4";




# Declare functions
sub XiaomiFlowerSens_Initialize($);
sub XiaomiFlowerSens_Define($$);
sub XiaomiFlowerSens_Undef($$);
sub XiaomiFlowerSens_Attr(@);
sub XiaomiFlowerSens_stateRequest($);
sub XiaomiFlowerSens_stateRequestTimer($);
sub XiaomiFlowerSens_Set($$@);
sub XiaomiFlowerSens_Run($);
sub XiaomiFlowerSens_BlockingRun($);
sub XiaomiFlowerSens_callGatttool($@);
sub XiaomiFlowerSens_forRun_encodeJSON($$);
sub XiaomiFlowerSens_forDone_encodeJSON($$$$$$);
sub XiaomiFlowerSens_BlockingDone($);
sub XiaomiFlowerSens_BlockingAborted($);




sub XiaomiFlowerSens_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}      = "XiaomiFlowerSens_Set";
    $hash->{DefFn}      = "XiaomiFlowerSens_Define";
    $hash->{UndefFn}    = "XiaomiFlowerSens_Undef";
    $hash->{AttrFn}     = "XiaomiFlowerSens_Attr";
    $hash->{AttrList}   = "interval ".
                            "disable:1 ".
                            "hciDevice:hci0,hci1,hci2 ".
                            "disabledForIntervals ".
                            $readingFnAttributes;



    foreach my $d(sort keys %{$modules{XiaomiFlowerSens}{defptr}}) {
	my $hash = $modules{XiaomiFlowerSens}{defptr}{$d};
	$hash->{VERSION} 	= $version;
    }
}

sub XiaomiFlowerSens_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    
    return "too few parameters: define <name> XiaomiFlowerSens <BTMAC>" if( @a != 3 );
    

    my $name            = $a[0];
    my $mac             = $a[2];
    
    $hash->{BTMAC}      = $mac;
    $hash->{VERSION} 	= $version;
    $hash->{INTERVAL}   = 300;
        
    $modules{XiaomiFlowerSens}{defptr}{$hash->{BTMAC}} = $hash;
    readingsSingleUpdate ($hash,"state","initialized", 0);
    $attr{$name}{room}          = "FlowerSens" if( !defined($attr{$name}{room}) );
    
    
    
    RemoveInternalTimer($hash);
    
    if( $init_done ) {
        XiaomiFlowerSens_stateRequestTimer($hash);
    } else {
        InternalTimer( gettimeofday()+int(rand(30))+15, "XiaomiFlowerSens_stateRequestTimer", $hash, 0 );
    }
    
    Log3 $name, 3, "XiaomiFlowerSens ($name) - defined with BTMAC $hash->{BTMAC}";
    
    $modules{XiaomiFlowerSens}{defptr}{$hash->{BTMAC}} = $hash;
    return undef;
}

sub XiaomiFlowerSens_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $mac = $hash->{BTMAC};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    
    delete($modules{XiaomiFlowerSens}{defptr}{$mac});
    Log3 $name, 3, "Sub XiaomiFlowerSens_Undef ($name) - delete device $name";
    return undef;
}

sub XiaomiFlowerSens_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};
    
    my $orig                                = $attrVal;
    
    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "XiaomiFlowerSens ($name) - disabled";
        }
	
        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "XiaomiFlowerSens ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "XiaomiFlowerSens ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }
	
        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "XiaomiFlowerSens ($name) - enabled";
        }
    }
    
    if( $attrName eq "interval" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal < 300 ) {
		Log3 $name, 3, "XiaomiFlowerSens ($name) - interval too small, please use something >= 300 (sec), default is 3600 (sec)";
		return "interval too small, please use something >= 300 (sec), default is 3600 (sec)";
	    } else {
		$hash->{INTERVAL} = $attrVal;
		Log3 $name, 3, "XiaomiFlowerSens ($name) - set interval to $attrVal";
	    }
	}
	
	elsif( $cmd eq "del" ) {
	    $hash->{INTERVAL} = 300;
	    Log3 $name, 3, "XiaomiFlowerSens ($name) - set interval to default";
        }
    }
    
    return undef;
}

sub XiaomiFlowerSens_stateRequest($) {

    my ($hash)      = @_;
    my $name        = $hash->{NAME};
    
    
    if( !IsDisabled($name) ) {
    
        readingsSingleUpdate ( $hash, "state", "active", 1 ) if( (ReadingsVal($name, "state", 0) eq "initialized" or ReadingsVal($name, "state", 0) eq "unreachable" or ReadingsVal($name, "state", 0) eq "corrupted data" or ReadingsVal($name, "state", 0) eq "disabled" or ReadingsVal($name, "state", 0) eq "Unknown" or ReadingsVal($name, "state", 0) eq "charWrite faild") );
        
        
        XiaomiFlowerSens_Run($hash);
        
    } else {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }
}

sub XiaomiFlowerSens_stateRequestTimer($) {

    my ($hash)      = @_;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    
    if( !IsDisabled($name) ) {
    
        readingsSingleUpdate ( $hash, "state", "active", 1 ) if( (ReadingsVal($name, "state", 0) eq "initialized" or ReadingsVal($name, "state", 0) eq "unreachable" or ReadingsVal($name, "state", 0) eq "corrupted data" or ReadingsVal($name, "state", 0) eq "disabled" or ReadingsVal($name, "state", 0) eq "Unknown" or ReadingsVal($name, "state", 0) eq "charWrite faild") );
        
        
        XiaomiFlowerSens_Run($hash);
        
    } else {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL}+int(rand(300)), "XiaomiFlowerSens_stateRequestTimer", $hash, 1 );
    
    Log3 $name, 5, "Sub XiaomiFlowerSens_stateRequestTimer ($name) - Request Timer wird aufgerufen";
}

sub XiaomiFlowerSens_Set($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, $arg)         = @aa;
    my $action;

    if( $cmd eq 'statusRequest' ) {
        XiaomiFlowerSens_stateRequest($hash);
    
    } else {
        my $list = "statusRequest:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub XiaomiFlowerSens_Run($) {

    my ( $hash, $cmd ) = @_;
    
    my $name    = $hash->{NAME};
    my $mac     = $hash->{BTMAC};
    my $wfr;
    
    
    if( ReadingsVal($name, "firmware", 0) eq "2.6.2" ) {
        $wfr    = 0;
    } else {
        $wfr    = 1;
    }

        
    my $response_encode = XiaomiFlowerSens_forRun_encodeJSON($mac,$wfr);
        
    $hash->{helper}{RUNNING_PID} = BlockingCall("XiaomiFlowerSens_BlockingRun", $name."|".$response_encode, "XiaomiFlowerSens_BlockingDone", 30, "XiaomiFlowerSens_BlockingAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    Log3 $name, 4, "Sub XiaomiFlowerSens_Run ($name) - start blocking call";
    
    readingsSingleUpdate ( $hash, "state", "call data", 1 ) if( ReadingsVal($name, "state", 0) eq "active" );
}

sub XiaomiFlowerSens_BlockingRun($) {

    my ($string)        = @_;
    my ($name,$data)    = split("\\|", $string);
    my $data_json       = decode_json($data);
    
    my $mac             = $data_json->{mac};
    my $wfr             = $data_json->{wfr};
    
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_BlockingRun ($name) - Running nonBlocking";
    
    
    ##### call sensor data
    
    my ($sensData,$batFwData)  = XiaomiFlowerSens_callGatttool($name,$mac,$wfr);
    
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_BlockingRun ($name) - Processing response data: $sensData";

    
    return "$name|Unknown Error, look at verbose 5 output"     # if error in stdout the error will given to $sensData variable
    unless( defined($batFwData) );
    
    
    
    
    #### processing sensor respons
    
    my @dataSensor  = split(" ",$sensData);
    
    return "$name|charWrite faild"
    unless( $dataSensor[0] ne "aa" and $dataSensor[1] ne "bb" and $dataSensor[2] ne "cc" and $dataSensor[3] ne "dd" and $dataSensor[4] ne "ee" and $dataSensor[5] ne "ff");
    
    my $temp;
    if( $dataSensor[1] eq "ff" ) {
        $temp       = hex("0x".$dataSensor[1].$dataSensor[0]) - hex("0xffff");
    } else {
        $temp       = hex("0x".$dataSensor[1].$dataSensor[0]);
    }
    my $lux         = hex("0x".$dataSensor[4].$dataSensor[3]);
    my $moisture    = hex("0x".$dataSensor[7]);
    my $fertility   = hex("0x".$dataSensor[9].$dataSensor[8]);
    
    
    
    
    ### processing firmware and battery response
    
    my @dataBatFw   = split(" ",$batFwData);
    
    my $blevel      = hex("0x".$dataBatFw[0]);
    my $fw          = ($dataBatFw[2]-30).".".($dataBatFw[4]-30).".".($dataBatFw[6]-30);

    
    
    
    ###### return processing data
    return "$name|corrupted data"
    if( $temp == 0 and $lux == 0 and $moisture == 0 and $fertility == 0 );
    
    my $response_encode = XiaomiFlowerSens_forDone_encodeJSON($temp,$lux,$moisture,$fertility,$blevel,$fw);
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_BlockingRun ($name) - no dataerror, create encode json: $response_encode";
    
    return "$name|$response_encode";
}

sub XiaomiFlowerSens_callGatttool($@) {

    my ($name,$mac,$wfr)    = @_;
    my $hci                 = ReadingsVal($name,"hciDevice","hci0");
    
    my $loop;
    my $wresp;
    my @readSensData;
    my @readBatFwData;
    
    
    $loop = 0;
    while ( (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop = 0) or (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop < 5) ) {
        Log3 $name, 4, "Sub XiaomiFlowerSens ($name) - check gattool is running. loop: $loop";
        sleep 0.5;
        $loop++;
    }
    
    
    
    #### Read Sensor Data
    
    ## support for Firmware 2.6.6, man muß erst einen Characterwert schreiben
    if($wfr == 1) {
        
        $loop = 0;
        do {
        
            $wresp      = qx(gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F 2>&1 /dev/null) if($wfr == 1);
            $loop++;
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call gatttool charWrite loop $loop";
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - charWrite wresp: $wresp" if(defined($wresp));
            
        } while( ($loop < 10) and (not defined($wresp)) );
    }
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - run gatttool";
    
    $loop = 0;
    do {
    
        @readSensData   = split(": ",qx(gatttool -i $hci -b $mac --char-read -a 0x35 2>&1 /dev/null));
        $loop++;
        Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call gatttool charRead loop $loop";
    
    } while( $loop < 10 and not $readSensData[0] =~ /Characteristic value/ );
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - processing gatttool response. sensData[0]: $readSensData[0]";
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - processing gatttool response. sensData: $readSensData[1]";
    
    return ($readSensData[1],undef)
    unless( $readSensData[0] =~ /Characteristic value/ );
    
    
    ### Read Firmware and Battery Data
    $loop = 0;
    do {
    
        @readBatFwData  = split(": ",qx(gatttool -i $hci -b $mac --char-read -a 0x38 2>&1 /dev/null));
        $loop++;
        Log3 $name, 4, "Sub XiaomiFlowerSens ($name) - call gatttool readBatFw loop $loop";
    
    } while( $loop < 10 and not $readSensData[0] =~ /Characteristic value/ );
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - processing gatttool response. batFwData: $readBatFwData[1]";
    
    return ($readBatFwData[1],undef)
    unless( $readBatFwData[0] =~ /Characteristic value/ );
    
    
    
    
    ### no Error in data string
    return ($readSensData[1],$readBatFwData[1])
}

sub XiaomiFlowerSens_forRun_encodeJSON($$) {

    my ($mac,$wfr) = @_;

    my %data = (
        'mac'           => $mac,
        'wfr'           => $wfr
    );
    
    return encode_json \%data;
}

sub XiaomiFlowerSens_forDone_encodeJSON($$$$$$) {

    my ($temp,$lux,$moisture,$fertility,$blevel,$fw)        = @_;

    my %response = (
        'temp'      => $temp,
        'lux'       => $lux,
        'moisture'  => $moisture,
        'fertility' => $fertility,
        'blevel'    => $blevel,
        'firmware'  => $fw
    );
    
    return encode_json \%response;
}

sub XiaomiFlowerSens_BlockingDone($) {

    my ($string)            = @_;
    my ($name,$response)    = split("\\|",$string);
    my $hash                = $defs{$name};
    
    
    delete($hash->{helper}{RUNNING_PID});
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_BlockingDone ($name) - Der Helper ist diabled. Daher wird hier abgebrochen" if($hash->{helper}{DISABLED});
    return if($hash->{helper}{DISABLED});
    
    
    readingsBeginUpdate($hash);
    
    if( $response eq "corrupted data" ) {
        readingsBulkUpdate($hash,"state","corrupted data");
        readingsEndUpdate($hash,1);
        return undef;
        
    } elsif( $response eq "charWrite faild") {
        readingsBulkUpdate($hash,"state","charWrite faild");
        readingsEndUpdate($hash,1);
        return undef;
        
    } elsif( $response eq "Unknown Error, look at verbose 5 output" ) {
        
        readingsBulkUpdate($hash,"lastGattError","$response");
        readingsBulkUpdate($hash,"state","unreachable");
        readingsEndUpdate($hash,1);
        return undef;    
        
    } elsif( ref($response) eq "HASH" ) {
        readingsBulkUpdate($hash,"lastGattError","$response");
        readingsBulkUpdate($hash,"state","unreachable");
        readingsEndUpdate($hash,1);
        return undef;
    }
    
    
    my $response_json = decode_json($response);
    
    readingsBulkUpdate($hash, "batteryLevel", $response_json->{blevel});
    readingsBulkUpdate($hash, "battery", ($response_json->{blevel}>20?"ok":"low") );
    readingsBulkUpdate($hash, "temperature", $response_json->{temp}/10);
    readingsBulkUpdate($hash, "lux", $response_json->{lux});
    readingsBulkUpdate($hash, "moisture", $response_json->{moisture});
    readingsBulkUpdate($hash, "fertility", $response_json->{fertility});
    readingsBulkUpdate($hash, "firmware", $response_json->{firmware});
    readingsBulkUpdate($hash, "state", "active") if( ReadingsVal($name,"state", 0) eq "call data" or ReadingsVal($name,"state", 0) eq "unreachable" or ReadingsVal($name,"state", 0) eq "corrupted data" );
    
    readingsEndUpdate($hash,1);
    
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_BlockingDone ($name) - Abschluss!";
}

sub XiaomiFlowerSens_BlockingAborted($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID});
    readingsSingleUpdate($hash,"state","unreachable", 1);
    Log3 $name, 3, "($name) Sub XiaomiFlowerSens_BlockingAborted - The BlockingCall Process terminated unexpectedly. Timedout";
}











1;








=pod
=item device
=item summary       Modul to retrieves data from a Xiaomi Flower Monitor
=item summary_DE    Modul um Daten vom Xiaomi Flower Monitor aus zu lesen

=begin html

<a name="XiaomiFlowerSens"></a>
<h3>Xiaomi Flower Monitor</h3>
<ul>
  <u><b>XiaomiFlowerSens - Retrieves data from a Xiaomi Flower Monitor</b></u>
  <br>
  With this module it is possible to read the data from a sensor and to set it as reading.</br>
  Gatttool and hcitool is required to use this modul. (apt-get install bluez)
  <br><br>
  <a name="XiaomiFlowerSensdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; XiaomiFlowerSens &lt;BT-MAC&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Weihnachtskaktus XiaomiFlowerSens C4:7C:8D:62:42:6F</code><br>
    </ul>
    <br>
    This statement creates a XiaomiFlowerSens with the name Weihnachtskaktus and the Bluetooth Mac C4:7C:8D:62:42:6F.<br>
    After the device has been created, the current data of the Xiaomi Flower Monitor is automatically read from the device.
  </ul>
  <br><br>
  <a name="XiaomiFlowerSensreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status of the flower sensor or error message if any errors.</li>
    <li>battery - current battery state dependent on batteryLevel.</li>
    <li>batteryLevel - current battery level in percent.</li>
    <li>fertility - Values for the fertilizer content</li>
    <li>firmware - current device firmware</li>
    <li>lux - current light intensity</li>
    <li>moisture - current moisture content</li>
    <li>temperature - current temperature</li>
  </ul>
  <br><br>
  <a name="XiaomiFlowerSensset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - retrieves the current state of the Xiaomi Flower Monitor.</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIDeviceattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki device</li>
    <li>interval - interval in seconds for statusRequest</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

=end html_DE
=cut

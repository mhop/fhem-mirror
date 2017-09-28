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


my $version = "1.0.3";




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
                            "disabledForIntervals ".
                            "hciDevice:hci0,hci1,hci2 ".
                            "minFertility ".
                            "maxFertility ".
                            "minTemp ".
                            "maxTemp ".
                            "minMoisture ".
                            "maxMoisture ".
                            "minLux ".
                            "maxLux ".
                            "sshHost ".
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
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
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
    my ($cmd, @args)         = @aa;
    

    if( $cmd eq 'statusRequest' ) {
        return "usage: statusRequest" if( @args != 0 );
    
        XiaomiFlowerSens_stateRequest($hash);
        
    } elsif( $cmd eq 'clearFirmwareReading' ) {
        return "usage: clearFirmwareReading" if( @args != 0 );
    
        readingsSingleUpdate($hash,'firmware','',0);
    
    } else {
        my $list = "statusRequest:noArg clearFirmwareReading:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub XiaomiFlowerSens_Run($) {

    my ( $hash, $cmd ) = @_;
    
    my $name    = $hash->{NAME};
    my $mac     = $hash->{BTMAC};
    my $wfr;
    
    
    if( ReadingsVal($name, 'firmware', '') eq "2.6.2" ) {
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
    my $hci                 = AttrVal($name,"hciDevice","hci0");
    
    my $loop;
    my $wresp;
    my $sshHost             = AttrVal($name,"sshHost","none");
    my @readSensData;
    my @readBatFwData;
    
    
    $loop = 0;
    
    if( $sshHost ne 'none') {
    
        while ( (qx(ssh $sshHost 'ps ax | grep -v grep | grep "gatttool -b $mac"') and $loop = 0) or (qx(ssh $sshHost 'ps ax | grep -v grep | grep "gatttool -b $mac"') and $loop < 5) ) {
        
            Log3 $name, 4, "Sub XiaomiFlowerSens ($name) - check gattool is running at host $sshHost. loop: $loop";
            sleep 0.5;
            $loop++;
        }
    } else {
    
        while ( (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop = 0) or (qx(ps ax | grep -v grep | grep "gatttool -b $mac") and $loop < 5) ) {
        
            Log3 $name, 4, "Sub XiaomiFlowerSens ($name) - check gattool is running at local host. loop: $loop";
            sleep 0.5;
            $loop++;
        }
    }
    
    
    
    #### Read Sensor Data
    
    ## support for Firmware 2.6.6, man muß erst einen Characterwert schreiben
    Log3 $name, 5, "Sub XiaomiFlowerSens_callGatttool ($name) - WFR: $wfr";
    if($wfr == 1) {
        
        $loop = 0;
        do {

            if( $sshHost ne 'none' ) {
            
                $wresp      = qx(ssh $sshHost 'gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F 2>&1 /dev/null');
                Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - write data to host $sshHost";
                
            } else {
            
                $wresp      = qx(gatttool -i $hci -b $mac --char-write-req -a 0x33 -n A01F 2>&1 /dev/null);
                Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - write data to local host";
            }
            
            $loop++;
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call gatttool charWrite loop $loop";
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - charWrite wresp: $wresp" if(defined($wresp) and ($wresp) );
            
        } while( ($loop < 10) and (not $wresp =~ /^Characteristic value was written successfully$/) );
    }
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - run gatttool";
    
    $loop = 0;
    do {

        if( $sshHost ne 'none' ) {
        
            @readSensData   = split(": ",qx(ssh $sshHost 'gatttool -i $hci -b $mac --char-read -a 0x35 2>&1 /dev/null'));
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call data from host $sshHost";
            
        } else {
        
            @readSensData   = split(": ",qx(gatttool -i $hci -b $mac --char-read -a 0x35 2>&1 /dev/null));
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call data from local host";
        }

        $loop++;
        Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call gatttool charRead loop $loop";
    
    } while( $loop < 10 and not $readSensData[0] =~ /^Characteristic value\/descriptor$/ );
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - processing gatttool response. sensData[0]: $readSensData[0]";
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - processing gatttool response. sensData: $readSensData[1]";
    
    return ($readSensData[1],undef)
    unless( $readSensData[0] =~ /^Characteristic value\/descriptor$/ );
    
    
    ### Read Firmware and Battery Data
    $loop = 0;
    do {

        if( $sshHost ne 'none' ) {
        
            @readBatFwData  = split(": ",qx(ssh $sshHost 'gatttool -i $hci -b $mac --char-read -a 0x38 2>&1 /dev/null'));
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call firm/batt data from host $sshHost";
        
        } else {
        
            @readBatFwData  = split(": ",qx(gatttool -i $hci -b $mac --char-read -a 0x38 2>&1 /dev/null));
            Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - call firm/batt data from host local host";
        }

        $loop++;
        Log3 $name, 4, "Sub XiaomiFlowerSens ($name) - call gatttool readBatFw loop $loop";
    
    } while( $loop < 10 and not $readBatFwData[0] =~ /^Characteristic value\/descriptor$/ );
    
    Log3 $name, 4, "Sub XiaomiFlowerSens_callGatttool ($name) - processing gatttool response. batFwData: $readBatFwData[1]";
    
    return ($readBatFwData[1],undef)
    unless( $readBatFwData[0] =~ /^Characteristic value\/descriptor$/ );
    
    
    
    
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


    DoTrigger($name, 'minFertility ' . ($response_json->{fertility}<AttrVal($name,'minFertility',0)?'low':'ok')) if( AttrVal($name,'minFertility','none') ne 'none' );
    DoTrigger($name, 'maxFertility ' . ($response_json->{fertility}>AttrVal($name,'maxFertility',0)?'high':'ok')) if( AttrVal($name,'maxFertility','none') ne 'none' );
    
    DoTrigger($name, 'minTemp ' . ($response_json->{temp}/10<AttrVal($name,'minTemp',0)?'low':'ok')) if( AttrVal($name,'minTemp','none') ne 'none' );
    DoTrigger($name, 'maxTemp ' . ($response_json->{temp}/10>AttrVal($name,'maxTemp',0)?'high':'ok')) if( AttrVal($name,'maxTemp','none') ne 'none' );
    
    DoTrigger($name, 'minMoisture ' . ($response_json->{moisture}<AttrVal($name,'minMoisture',0)?'low':'ok')) if( AttrVal($name,'minMoisture','none') ne 'none' );
    DoTrigger($name, 'maxMoisture ' . ($response_json->{moisture}>AttrVal($name,'maxMoisture',0)?'high':'ok')) if( AttrVal($name,'maxMoisture','none') ne 'none' );
    
    DoTrigger($name, 'minLux ' . ($response_json->{lux}<AttrVal($name,'minLux',0)?'low':'ok')) if( AttrVal($name,'minLux','none') ne 'none' );
    DoTrigger($name, 'maxLux ' . ($response_json->{lux}>AttrVal($name,'maxLux',0)?'high':'ok')) if( AttrVal($name,'maxLux','none') ne 'none' );


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
    <li>clearFirmwareReading - clear firmware reading for new begin.</li>
    <br>
  </ul>
  <br><br>
  <a name="XiaomiFlowerSensattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the device</li>
    <li>interval - interval in seconds for statusRequest</li>
    <li>minFertility - min fertility value for low warn event</li>
    <li>maxFertility - max fertility value for High warn event</li>
    <li>minMoisture - min moisture value for low warn event</li>
    <li>maxMoisture - max moisture value for High warn event</li>
    <li>minTemp - min temperature value for low warn event</li>
    <li>maxTemp - max temperature value for high warn event</li>
    <li>minlux - min lux value for low warn event</li>
    <li>maxlux - max lux value for high warn event
    <br>
    Event Example for min/max Value's: 2017-03-16 11:08:05 XiaomiFlowerSens Dracaena minMoisture low<br>
    Event Example for min/max Value's: 2017-03-16 11:08:06 XiaomiFlowerSens Dracaena maxTemp high</li>
    <li>sshHost - FQD-Name or IP of ssh remote system / you must configure your ssh system for certificate authentication. For better handling you can config ssh Client with .ssh/config file</li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="XiaomiFlowerSens"></a>
<h3>Xiaomi Flower Monitor</h3>
<ul>
  <u><b>XiaomiFlowerSens - liest Daten von einem Xiaomi Flower Monitor</b></u>
  <br />
  Dieser Modul liest Daten von einem Sensor und legt sie in den Readings ab.<br />
  Auf dem (Linux) FHEM-Server werden gatttool und hcitool vorausgesetzt. (sudo apt install bluez)
  <br /><br />
  <a name="XiaomiFlowerSensdefine"></a>
  <b>Define</b>
  <ul><br />
    <code>define &lt;name&gt; XiaomiFlowerSens &lt;BT-MAC&gt;</code>
    <br /><br />
    Beispiel:
    <ul><br />
      <code>define Weihnachtskaktus XiaomiFlowerSens C4:7C:8D:62:42:6F</code><br />
    </ul>
    <br />
	Der Befehl legt ein Device vom Typ XiaomiFlowerSens an mit dem Namen Weihnachtskaktus und der Bluetooth MAC C4:7C:8D:62:42:6F.<br />
	Nach dem Anlegen des Device werden umgehend und automatisch die aktuellen Daten vom betroffenen Xiaomi Flower Monitor gelesen.
  </ul>
  <br /><br />
  <a name="XiaomiFlowerSensreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Status des Flower Monitor oder eine Fehlermeldung falls Fehler beim letzten Kontakt auftraten.</li>
    <li>battery - aktueller Batterie-Status in Abhängigkeit vom Wert batteryLevel.</li>
    <li>batteryLevel - aktueller Ladestand der Batterie in Prozent.</li>
    <li>fertility - Wert des Fruchtbarkeitssensors (Bodenleitf&auml;higkeit)</li>
    <li>firmware - aktuelle Firmware-Version des Flower Monitor</li>
    <li>lux - aktuelle Lichtintensit&auml;t</li>
    <li>moisture - aktueller Feuchtigkeitswert</li>
    <li>temperature - aktuelle Temperatur</li>
  </ul>
  <br /><br />
  <a name="XiaomiFlowerSensset"></a>
  <b>Set</b>
  <ul>
    <li>statusRequest - aktive Abfrage des aktuellen Status des Xiaomi Flower Monitor und seiner Werte</li>
    <li>clearFirmwareReading - l&ouml;scht das Reading firmware f&uuml;r/nach Upgrade</li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiFlowerSensattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Device</li>
    <li>interval - Interval in Sekunden zwischen zwei Abfragen</li>
    <li>minFertility - min Fruchtbarkeits-Grenzwert f&uuml;r ein Ereignis minFertility low </li>
    <li>maxFertility - max Fruchtbarkeits-Grenzwert f&uuml;r ein Ereignis maxFertility high </li>
    <li>minMoisture - min Feuchtigkeits-Grenzwert f&uuml;r ein Ereignis minMoisture low </li> 
    <li>maxMoisture - max Feuchtigkeits-Grenzwert f&uuml;r ein Ereignis maxMoisture high </li>
    <li>minTemp - min Temperatur-Grenzwert f&uuml;r ein Ereignis minTemp low </li>
    <li>maxTemp - max Temperatur-Grenzwert f&uuml;r ein Ereignis maxTemp high </li>
    <li>minlux - min Helligkeits-Grenzwert f&uuml;r ein Ereignis minlux low </li>
    <li>maxlux - max Helligkeits-Grenzwert f&uuml;r ein Ereignis maxlux high
    <br /><br />Beispiele f&uuml;r min/max-Ereignisse:<br />
    2017-03-16 11:08:05 XiaomiFlowerSens Dracaena minMoisture low<br />
    2017-03-16 11:08:06 XiaomiFlowerSens Dracaena maxTemp high<br /><br /></li>
    <li>sshHost - FQDN oder IP-Adresse eines entfernten SSH-Systems. Das SSH-System ist auf eine Zertifikat basierte Authentifizierung zu konfigurieren. Am elegantesten geschieht das mit einer  .ssh/config Datei auf dem SSH-Client.</li>
  </ul>
</ul>

=end html_DE

=cut

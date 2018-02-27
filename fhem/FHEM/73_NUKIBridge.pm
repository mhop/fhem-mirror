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

#################################
######### Wichtige Hinweise und Links #################

## Beispiel für Logausgabe
# https://forum.fhem.de/index.php/topic,55756.msg508412.html#msg508412

##
#


################################


package main;

use strict;
use warnings;
use JSON;

use HttpUtils;

my $version     = "0.6.2";
my $bridgeapi   = "1.5";



my %lockActions = (
    'unlock'                => 1,
    'lock'                  => 2,
    'unlatch'               => 3,
    'locknGo'               => 4,
    'locknGoWithUnlatch'    => 5
);


# Declare functions
sub NUKIBridge_Initialize ($);
sub NUKIBridge_Define ($$);
sub NUKIBridge_Undef ($$);
sub NUKIBridge_Read($@);
sub NUKIBridge_Attr(@);
sub NUKIBridge_Set($@);
sub NUKIBridge_Get($@);
sub NUKIBridge_GetCheckBridgeAlive($);
sub NUKIBridge_firstRun($);
sub NUKIBridge_Call($$$$$);
sub NUKIBridge_Distribution($$$);
sub NUKIBridge_ResponseProcessing($$$);
sub NUKIBridge_Autocreate($$;$);
sub NUKIBridge_InfoProcessing($$);
sub NUKIBridge_getLogfile($);
sub NUKIBridge_getCallbackList($);
sub NUKIBridge_CallBlocking($$$);





sub NUKIBridge_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     = "NUKIBridge_Read";
    $hash->{WriteFn}    = "NUKIBridge_Read";
    $hash->{Clients}    = ":NUKIDevice:";

      
    # Consumer
    $hash->{SetFn}      = "NUKIBridge_Set";
    $hash->{GetFn}      = "NUKIBridge_Get";
    $hash->{DefFn}      = "NUKIBridge_Define";
    $hash->{UndefFn}    = "NUKIBridge_Undef";
    $hash->{AttrFn}     = "NUKIBridge_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          $readingFnAttributes;


    foreach my $d(sort keys %{$modules{NUKIBridge}{defptr}}) {
        my $hash = $modules{NUKIBridge}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub NUKIBridge_Read($@) {

  my ($hash,$chash,$name,$path,$lockAction,$nukiId)= @_;
  NUKIBridge_Call($hash,$chash,$path,$lockAction,$nukiId );
  
}

sub NUKIBridge_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    

    return "too few parameters: define <name> NUKIBridge <HOST> <TOKEN>" if( @a != 4 );
    


    my $name            = $a[0];
    my $host            = $a[2];
    my $token           = $a[3];
    my $port            = 8080;

    $hash->{HOST}       = $host;
    $hash->{PORT}       = $port;
    $hash->{TOKEN}      = $token;
    $hash->{VERSION}    = $version;
    $hash->{BRIDGEAPI}  = $bridgeapi;
    $hash->{helper}{aliveCount} = 0;
    


    Log3 $name, 3, "NUKIBridge ($name) - defined with host $host on port $port, Token $token";

    $attr{$name}{room} = "NUKI" if( !defined( $attr{$name}{room} ) );
    readingsSingleUpdate($hash, 'state', 'Initialized', 1 );
    
    RemoveInternalTimer($hash);
    
    if( $init_done ) {
        NUKIBridge_firstRun($hash) if( ($hash->{HOST}) and ($hash->{TOKEN}) );
    } else {
        InternalTimer( gettimeofday()+15, 'NUKIBridge_firstRun', $hash, 0 ) if( ($hash->{HOST}) and ($hash->{TOKEN}) );
    }

    $modules{NUKIBridge}{defptr}{$hash->{HOST}} = $hash;
    
    return undef;
}

sub NUKIBridge_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    RemoveInternalTimer( $hash );
    
    delete $modules{NUKIBridge}{defptr}{$hash->{HOST}};
    
    return undef;
}

sub NUKIBridge_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "NUKIBridge ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "NUKIBridge ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "NUKIBridge ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "NUKIBridge ($name) - delete disabledForIntervals";
        }
    }

    return undef;
}

sub NUKIBridge_Set($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;

    
    if($cmd eq 'autocreate') {
        return "usage: autocreate" if( @args != 0 );

        NUKIBridge_Call($hash,$hash,"list",undef,undef) if( !IsDisabled($name) );

        return undef;

    } elsif($cmd eq 'info') {
        return "usage: statusRequest" if( @args != 0 );
    
        NUKIBridge_Call($hash,$hash,"info",undef,undef) if( !IsDisabled($name) );
        
        return undef;
        
    } elsif($cmd eq 'fwUpdate') {
        return "usage: fwUpdate" if( @args != 0 );
    
        NUKIBridge_CallBlocking($hash,"fwupdate",undef) if( !IsDisabled($name) );
        
        return undef;
        
    } elsif($cmd eq 'reboot') {
        return "usage: reboot" if( @args != 0 );
    
        NUKIBridge_CallBlocking($hash,"reboot",undef) if( !IsDisabled($name) );
        
        return undef;
        
    } elsif($cmd eq 'clearLog') {
        return "usage: clearLog" if( @args != 0 );
        
        NUKIBridge_CallBlocking($hash,"clearlog",undef) if( !IsDisabled($name) );
        
    } elsif($cmd eq 'factoryReset') {
        return "usage: clearLog" if( @args != 0 );
        
        NUKIBridge_CallBlocking($hash,"factoryReset",undef) if( !IsDisabled($name) );
        
    } elsif($cmd eq 'callbackRemove') {
        return "usage: callbackRemove" if( @args != 1 );
        my $id = "id=" . join( " ", @args );
        
        my $resp = NUKIBridge_CallBlocking($hash,"callback/remove",$id) if( !IsDisabled($name) );
        if( $resp->{success} eq "true" and !IsDisabled($name) ) {
            return "Success Callback $id removed";
        } else {
            return "remove Callback failed";
        }

    } else {
        my  $list = ""; 
        $list .= "info:noArg autocreate:noArg callbackRemove:0,1,2 ";
        $list .= "clearLog:noArg fwUpdate:noArg reboot:noArg factoryReset:noArg" if( ReadingsVal($name,'bridgeType','Software') eq 'Hardware' );
        return "Unknown argument $cmd, choose one of $list";
    }
}

sub NUKIBridge_Get($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;
    
    if($cmd eq 'logFile') {
        return "usage: logFile" if( @args != 0 );

        NUKIBridge_getLogfile($hash) if( !IsDisabled($name) );
        
    } elsif($cmd eq 'callbackList') {
        return "usage: callbackList" if( @args != 0 );

        NUKIBridge_getCallbackList($hash) if( !IsDisabled($name) );
        
    } else {
        my $list = "";
        $list .= "callbackList:noArg ";
        $list .= "logFile:noArg" if( ReadingsVal($name,'bridgeType','Software') eq 'Hardware' );
        return "Unknown argument $cmd, choose one of $list";
    }
}

sub NUKIBridge_GetCheckBridgeAlive($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    RemoveInternalTimer($hash);
    Log3 $name, 4, "NUKIBridge ($name) - NUKIBridge_GetCheckBridgeAlive";
    
    if( !IsDisabled($name) ) {

        NUKIBridge_Call($hash,$hash,'info',undef,undef);
    
        Log3 $name, 4, "NUKIBridge ($name) - run NUKIBridge_Call";
    }
    
    InternalTimer( gettimeofday()+15+int(rand(15)), 'NUKIBridge_GetCheckBridgeAlive', $hash, 1 );
    
    Log3 $name, 4, "NUKIBridge ($name) - Call InternalTimer for NUKIBridge_GetCheckBridgeAlive";
}

sub NUKIBridge_firstRun($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    NUKIBridge_Call($hash,$hash,'list',undef,undef) if( !IsDisabled($name) );
    InternalTimer( gettimeofday()+15, 'NUKIBridge_GetCheckBridgeAlive', $hash, 1 );

    return undef;
}

sub NUKIBridge_Call($$$$$) {

    my ($hash,$chash,$path,$lockAction,$nukiId) = @_;
    
    my $name    =   $hash->{NAME};
    my $host    =   $hash->{HOST};
    my $port    =   $hash->{PORT};
    my $token   =   $hash->{TOKEN};
    
    
    my $uri = "http://" . $hash->{HOST} . ":" . $port;
    $uri .= "/" . $path if( defined $path);
    $uri .= "?token=" . $token if( defined($token) );
    $uri .= "&action=" . $lockActions{$lockAction} if( defined($lockAction) and $path ne "callback/add" );
    $uri .= "&url=" . $lockAction if( defined($lockAction) and $path eq "callback/add" );
    $uri .= "&nukiId=" . $nukiId if( defined($nukiId) );


    HttpUtils_NonblockingGet(
        {
            url            => $uri,
            timeout        => 30,
            hash           => $hash,
            chash          => $chash,
            endpoint       => $path,
            header         => "Accept: application/json",
            method         => "GET",
            callback       => \&NUKIBridge_Distribution,
        }
    );
    
    Log3 $name, 4, "NUKIBridge ($name) - Send HTTP POST with URL $uri";
}

sub NUKIBridge_Distribution($$$) {

    my ( $param, $err, $json ) = @_;
    my $hash            = $param->{hash};
    my $doTrigger       = $param->{doTrigger};
    my $name            = $hash->{NAME};
    my $host            = $hash->{HOST};
    
    
    Log3 $name, 5, "NUKIBridge ($name) - Response JSON: $json";
    Log3 $name, 5, "NUKIBridge ($name) - Response ERROR: $err";
    Log3 $name, 5, "NUKIBridge ($name) - Response CODE: $param->{code}" if( defined($param->{code}) and ($param->{code}) );
    
    readingsBeginUpdate($hash);
    
    if( defined( $err ) ) {
        if ( $err ne "" ) {
            if ($param->{endpoint} eq "info") {
                readingsBulkUpdate( $hash, "state", "not connected") if( $hash->{helper}{aliveCount} > 1 );
                Log3 $name, 5, "NUKIBridge ($name) - Bridge ist offline";
                $hash->{helper}{aliveCount} = $hash->{helper}{aliveCount} + 1;
            }
            
            readingsBulkUpdate( $hash, "lastError", $err ) if( ReadingsVal($name,"state","not connected") eq "not connected" );
            Log3 $name, 4, "NUKIBridge ($name) - error while requesting: $err";
            readingsEndUpdate( $hash, 1 );
            return $err;
        }
    }

    if( $json eq "" and exists( $param->{code} ) and $param->{code} ne 200 ) {
    
        if( $param->{code} eq 503 ) {
            NUKIDevice_Parse($param->{chash},$param->{code}) if( $hash != $param->{chash} );
            Log3 $name, 4, "NUKIBridge ($name) - smartlock is offline";
            readingsEndUpdate( $hash, 1 );
            return "received http code ".$param->{code}.": smartlock is offline";
        }
        
        readingsBulkUpdate( $hash, "lastError", "Internal error, " .$param->{code} );
        Log3 $name, 4, "NUKIBridge ($name) - received http code " .$param->{code}." without any data after requesting";

        readingsEndUpdate( $hash, 1 );
        return "received http code ".$param->{code}." without any data after requesting";
    }

    if( ( $json =~ /Error/i ) and exists( $param->{code} ) ) {    
        
        readingsBulkUpdate( $hash, "lastError", "invalid API token" ) if( $param->{code} eq 401 );
        readingsBulkUpdate( $hash, "lastError", "action is undefined" ) if( $param->{code} eq 400 and $hash == $param->{chash} );
        
        
        ###### Fehler bei Antwort auf Anfrage eines logischen Devices ######
        NUKIDevice_Parse($param->{chash},$param->{code}) if( $param->{code} eq 404 );
        NUKIDevice_Parse($param->{chash},$param->{code}) if( $param->{code} eq 400 and $hash != $param->{chash} );
        
        
        
        Log3 $name, 4, "NUKIBridge ($name) - invalid API token" if( $param->{code} eq 401 );
        Log3 $name, 4, "NUKIBridge ($name) - nukiId is not known" if( $param->{code} eq 404 );
        Log3 $name, 4, "NUKIBridge ($name) - action is undefined" if( $param->{code} eq 400 and $hash == $param->{chash} );


    ######### Zum testen da ich kein Nuki Smartlock habe ############
    #if ( $param->{code} eq 404 ) {
        #    if( defined($param->{chash}->{helper}{lockAction}) ) {
        #        Log3 $name, 3, "NUKIBridge ($name) - Test JSON String for lockAction";
        #        $json = '{"success": true, "batteryCritical": false}';
        #    } else {
        #        Log3 $name, 3, "NUKIBridge ($name) - Test JSON String for lockState";
        #        $json = '{"state": 1, "stateName": "locked", "batteryCritical": false, "success": "true"}';
        #    }
        #    NUKIDevice_Parse($param->{chash},$json);
        #}
        
        
        readingsEndUpdate( $hash, 1 );
        return $param->{code};
    }
    
    if( $hash == $param->{chash} ) {
        
        # zum testen da ich kein Nuki Smartlock habe
        #$json = '[{"nukiId": 1,"name": "Home","lastKnownState": {"state": 1,"stateName": "locked","batteryCritical": false,"timestamp": "2016-10-03T06:49:00+00:00"}},{"nukiId": 2,"name": "Grandma","lastKnownState": {"state": 3,"stateName": "unlocked","batteryCritical": false,"timestamp": "2016-10-03T06:49:00+00:00"}}]' if( $param->{endpoint} eq "list" );
        
        #$json= '{"bridgeType":2,"ids":{"serverId":142667440},"versions":{"appVersion":"0.2.14"},"uptime":1527,"currentTime":"2017-01-17T04:55:58Z","serverConnected":true,"scanResults":[{"nukiId": 1,"name": "Home","rssi": -87,"paired": true},{"nukiId": 2,"name": "Grandma","rssi": -93,"paired": false}]}' if( $param->{endpoint} eq "info" );
        
        NUKIBridge_ResponseProcessing($hash,$json,$param->{endpoint});
        
    } else {
    
        NUKIDevice_Parse($param->{chash},$json);
    }
    
    readingsEndUpdate( $hash, 1 );
    return undef;
}

sub NUKIBridge_ResponseProcessing($$$) {

    my ($hash,$json,$path) = @_;
    my $name = $hash->{NAME};
    my $decode_json;
    
    
    if( !$json ) {
        Log3 $name, 3, "NUKIBridge ($name) - empty answer received";
        return undef;
    } elsif( $json =~ m'HTTP/1.1 200 OK' ) {
        Log3 $name, 4, "NUKIBridge ($name) - empty answer received";
        return undef;
    } elsif( $json !~ m/^[\[{].*[}\]]$/ ) {
        Log3 $name, 3, "NUKIBridge ($name) - invalid json detected: $json";
        return "NUKIBridge ($name) - invalid json detected: $json";
    }

    my $decode_json = eval{decode_json($json)};
    if($@){
        Log3 $name, 3, "NUKIBridge ($name) - JSON error while request: $@";
        return;
    }
    
    if( ref($decode_json) eq "ARRAY" and scalar(@{$decode_json}) > 0 and $path eq "list" ) {

        NUKIBridge_Autocreate($hash,$decode_json);
        NUKIBridge_Call($hash,$hash,"info",undef,undef) if( !IsDisabled($name) );
    }
    
    elsif( $path eq "info" ) {
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "state", "connected" );
        Log3 $name, 5, "NUKIBridge ($name) - Bridge ist online";
            
        readingsEndUpdate( $hash, 1 );
        $hash->{helper}{aliveCount} = 0;
        
        NUKIBridge_InfoProcessing($hash,$decode_json);
    
    } else {
        Log3 $name, 5, "NUKIBridge ($name) - Rückgabe Path nicht korrekt: $json";
        return;
    }
    
    return undef;
}

sub NUKIBridge_Autocreate($$;$) {

    my ($hash,$decode_json,$force)= @_;
    my $name = $hash->{NAME};

    if( !$force ) {
        foreach my $d (keys %defs) {
            next if($defs{$d}{TYPE} ne "autocreate");
            return undef if(AttrVal($defs{$d}{NAME},"disable",undef));
        }
    }

    my $autocreated = 0;
    my $nukiSmartlock;
    my $nukiId;
    my $nukiName;
    
    readingsBeginUpdate($hash);
    
    foreach $nukiSmartlock (@{$decode_json}) {
        
        $nukiId     = $nukiSmartlock->{nukiId};
        $nukiName   = $nukiSmartlock->{name};
        
        
        my $code = $name ."-".$nukiId;
        if( defined($modules{NUKIDevice}{defptr}{$code}) ) {
            Log3 $name, 3, "NUKIDevice ($name) - NukiId '$nukiId' already defined as '$modules{NUKIDevice}{defptr}{$code}->{NAME}'";
            next;
        }
        
        my $devname = "NUKIDevice" . $nukiId;
        my $define= "$devname NUKIDevice $nukiId IODev=$name";
        Log3 $name, 3, "NUKIDevice ($name) - create new device '$devname' for address '$nukiId'";

        my $cmdret= CommandDefine(undef,$define);
        if($cmdret) {
            Log3 $name, 3, "NUKIDevice ($name) - Autocreate: An error occurred while creating device for nukiId '$nukiId': $cmdret";
        } else {
            $cmdret= CommandAttr(undef,"$devname alias $nukiName");
            $cmdret= CommandAttr(undef,"$devname room NUKI");
            $cmdret= CommandAttr(undef,"$devname IODev $name");
        }

        $defs{$devname}{helper}{fromAutocreate} = 1 ;
        
        readingsBulkUpdate( $hash, "${autocreated}_nukiId", $nukiId );
        readingsBulkUpdate( $hash, "${autocreated}_name", $nukiName );
        
        $autocreated++;
        
        readingsBulkUpdate( $hash, "smartlockCount", $autocreated );
    }
    
    readingsEndUpdate( $hash, 1 );
    
    
    if( $autocreated ) {
        Log3 $name, 2, "NUKIDevice ($name) - autocreated $autocreated devices";
        CommandSave(undef,undef) if( AttrVal( "autocreate", "autosave", 1 ) );
    }

    return "created $autocreated devices";
}

sub NUKIBridge_InfoProcessing($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};
    
    my $nukiId;
    my $scanResults;
    my %response_hash;
    my $dname;
    my $dhash;
    
    my %bridgeType = (
        '1' =>  'Hardware',
        '2' =>  'Software'
    );
    
    
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash,"appVersion",$decode_json->{versions}->{appVersion});
    readingsBulkUpdate($hash,"firmwareVersion",$decode_json->{versions}->{firmwareVersion});
    readingsBulkUpdate($hash,"wifiFirmwareVersion",$decode_json->{versions}->{wifiFirmwareVersion});
    readingsBulkUpdate($hash,"bridgeType",$bridgeType{$decode_json->{bridgeType}});
    readingsBulkUpdate($hash,"hardwareId",$decode_json->{ids}{hardwareId});
    readingsBulkUpdate($hash,"serverId",$decode_json->{ids}{serverId});
    readingsBulkUpdate($hash,"uptime",$decode_json->{uptime});
    readingsBulkUpdate($hash,"currentTime",$decode_json->{currentTime});
    readingsBulkUpdate($hash,"serverConnected",$decode_json->{serverConnected});
    readingsEndUpdate($hash,1);
    
    
    foreach $scanResults (@{$decode_json->{scanResults}}) {
        if( ref($scanResults) eq "HASH" ) {
            if ( defined( $modules{NUKIDevice}{defptr} ) ) {
                while ( my ( $key, $value ) = each %{ $modules{NUKIDevice}{defptr} } ) {

                    $dhash = $modules{NUKIDevice}{defptr}{$key};
                    $dname = $dhash->{NAME};
                    $nukiId = InternalVal( $dname, "NUKIID", undef );
                    next if ( !$nukiId or $nukiId ne $scanResults->{nukiId} );

                    Log3 $name, 4, "NUKIDevice ($dname) - Received scanResults for matching NukiID $nukiId at device $dname";
            
                    %response_hash = ('name'=>$scanResults->{name}, 'rssi'=>$scanResults->{rssi},'paired'=>$scanResults->{paired});
            
                    NUKIDevice_Parse($dhash,encode_json \%response_hash);
                }
            }
        }
    }
}

sub NUKIBridge_getLogfile($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    
    my $decode_json = NUKIBridge_CallBlocking($hash,"log",undef);
    
    Log3 $name, 4, "NUKIBridge ($name) - Log data are collected and processed";
    
    
    if( ref($decode_json) eq "ARRAY" and scalar(@{$decode_json}) > 0 ) {
        Log3 $name, 4, "NUKIBridge ($name) - created Table with log file";
    
        my $ret = '<html><table width=100%><tr><td>';
        $ret .= '<table class="block wide">';
        
        foreach my $logs (@{$decode_json}) {
            $ret .= '<tr class="odd">';
            
            if($logs->{timestamp}) {
                $ret .= "<td><b>timestamp:</b> </td>";
                $ret .= "<td>$logs->{timestamp}</td>";
                $ret .= '<td> </td>';
            }
            
            if($logs->{type}) {
                $ret .= "<td><b>type:</b> </td>";
                $ret .= "<td>$logs->{type}</td>";
                $ret .= '<td> </td>';
            }
            
            foreach my $d (reverse sort keys %{$logs}) {
                next if( $d eq "type" );
                next if( $d eq "timestamp" );
               
                $ret .= "<td><b>$d:</b> </td>";
                $ret .= "<td>$logs->{$d}</td>";
                $ret .= '<td> </td>';
            }
            
            $ret .= '</tr>';
        }
    
        $ret .= '</table></td></tr>';
        $ret .= '</table></html>';
     
        return $ret;
    }
}

sub NUKIBridge_getCallbackList($) {

    my ($hash)  = @_;
    my $name    = $hash->{NAME};

    
    my $decode_json = NUKIBridge_CallBlocking($hash,"callback/list",undef);
    
    Log3 $name, 4, "NUKIBridge ($name) - Callback data is collected and processed";
    
    if( ref($decode_json->{callbacks}) eq "ARRAY" and scalar(@{$decode_json->{callbacks}}) > 0 ) {
        Log3 $name, 4, "NUKIBridge ($name) - created Table with log file";
    
        my $ret = '<html><table width=100%><tr><td>';

        $ret .= '<table class="block wide">';

            $ret .= '<tr class="odd">';
            $ret .= "<td><b>Callback-ID</b></td>";
            $ret .= "<td> </td>";
            $ret .= "<td><b>Callback-URL</b></td>";
            $ret .= '</tr>';
    
        foreach my $cb (@{$decode_json->{callbacks}}) {
        
            $ret .= "<td>$cb->{id}</td>";
            $ret .= "<td> </td>";
            $ret .= "<td>$cb->{url}</td>";
            $ret .= '</tr>';
        }
    
        $ret .= '</table></td></tr>';
        $ret .= '</table></html>';
     
        return $ret;
    }
    
    return "No callback data available or error during processing";
}

sub NUKIBridge_CallBlocking($$$) {

    my ($hash,$path,$obj)  = @_;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = $hash->{PORT};
    my $token   = $hash->{TOKEN};
    
    
    my $url = "http://" . $hash->{HOST} . ":" . $port;
    $url .= "/" . $path if( defined $path);
    $url .= "?token=" . $token if( defined($token) );
    $url .= "&" . $obj if( defined($obj) );
    
    
    my($err,$data)  = HttpUtils_BlockingGet({
      url           => $url,
      timeout       => 3,
      method        => "GET",
      header        => "Content-Type: application/json",
    });


    if( !$data ) {
        Log3 $name, 3, "NUKIDevice ($name) - empty answer received for $url";
        return undef;
    } elsif( $data =~ m'HTTP/1.1 200 OK' ) {
        Log3 $name, 4, "NUKIDevice ($name) - empty answer received for $url";
        return undef;
    } elsif( $data !~ m/^[\[{].*[}\]]$/ and $path ne "log" ) {
        Log3 $name, 3, "NUKIDevice ($name) - invalid json detected for $url: $data";
        return "NUKIDevice ($name) - invalid json detected for $url: $data";
    }


    my $decode_json = eval{decode_json($data)};
    if($@){
        Log3 $name, 3, "NUKIBridge ($name) - JSON error while request: $@";
        return;
    }
    
    return undef if( !$decode_json );
    
    Log3 $name, 5, "NUKIBridge ($name) - Data: $data";
    Log3 $name, 4, "NUKIBridge ($name) - Blocking HTTP Query finished";
    return ($decode_json);
}







1;


=pod
=item device
=item summary    Modul to control the Nuki Smartlock's over the Nuki Bridge.
=item summary_DE Modul zur Steuerung des Nuki Smartlock über die Nuki Bridge.

=begin html

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - controls the Nuki Smartlock over the Nuki Bridge</b></u>
  <br>
  The Nuki Bridge module connects FHEM to the Nuki Bridge and then reads all the smartlocks available on the bridge. Furthermore, the detected Smartlocks are automatically created as independent devices.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    This statement creates a NUKIBridge device with the name NBridge1 and the IP 192.168.0.23 as well as the token F34HK6.<br>
    After the bridge device is created, all available Smartlocks are automatically placed in FHEM.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>0_nukiId - ID of the first found Nuki Smartlock</li>
    <li>0_name - Name of the first found Nuki Smartlock</li>
    <li>smartlockCount - number of all found Smartlocks</li>
    <li>bridgeAPI - API Version of bridge</li>
    <li>bridgeType - Hardware bridge / Software bridge</li>
    <li>currentTime - Current timestamp</li>
    <li>firmwareVersion - Version of the bridge firmware</li>
    <li>hardwareId - Hardware ID</li>
    <li>lastError - Last connected error</li>
    <li>serverConnected - Flag indicating whether or not the bridge is connected to the Nuki server</li>
    <li>serverId - Server ID</li>
    <li>uptime - Uptime of the bridge in seconds</li>
    <li>wifiFirmwareVersion- Version of the WiFi modules firmware</li>
    <br>
    The preceding number is continuous, starts with 0 und returns the properties of <b>one</b> Smartlock.
   </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>autocreate - Prompts to re-read all Smartlocks from the bridge and if not already present in FHEM, create the autimatic.</li>
    <li>callbackRemove -  Removes a previously added callback</li>
    <li>clearLog - Clears the log of the Bridge (only hardwarebridge)</li>
    <li>factoryReset - Performs a factory reset (only hardwarebridge)</li>
    <li>fwUpdate -  Immediately checks for a new firmware update and installs it (only hardwarebridge)</li>
    <li>info -  Returns all Smart Locks in range and some device information of the bridge itself</li>
    <li>reboot - reboots the bridge (only hardwarebridge)</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeget"></a>
  <b>Get</b>
  <ul>
    <li>callbackList - List of register url callbacks. The Bridge register up to 3  url callbacks.</li>
    <li>logFile - Retrieves the log of the Bridge</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attributes</b>
  <ul>
    <li>disable - disables the Nuki Bridge</li>
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="NUKIBridge"></a>
<h3>NUKIBridge</h3>
<ul>
  <u><b>NUKIBridge - Steuert das Nuki Smartlock über die Nuki Bridge</b></u>
  <br>
  Das Nuki Bridge Modul verbindet FHEM mit der Nuki Bridge und liest dann alle auf der Bridge verfügbaren Smartlocks ein. Desweiteren werden automatisch die erkannten Smartlocks als eigenst&auml;ndige Devices an gelegt.
  <br><br>
  <a name="NUKIBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; NUKIBridge &lt;HOST&gt; &lt;API-TOKEN&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define NBridge1 NUKIBridge 192.168.0.23 F34HK6</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein NUKIBridge Device mit Namen NBridge1 und der IP 192.168.0.23 sowie dem Token F34HK6.<br>
    Nach dem anlegen des Bridge Devices werden alle zur verf&uuml;gung stehende Smartlock automatisch in FHEM an gelegt.
  </ul>
  <br><br>
  <a name="NUKIBridgereadings"></a>
  <b>Readings</b>
  <ul>
    <li>0_nukiId - ID des ersten gefundenen Nuki Smartlocks</li>
    <li>0_name - Name des ersten gefunden Nuki Smartlocks</li>
    <li>smartlockCount - Anzahl aller gefundenen Smartlock</li>
    <li>bridgeAPI - API Version der Bridge</li>
    <li>bridgeType - Hardware oder Software/App Bridge</li>
    <li>currentTime - aktuelle Zeit auf der Bridge zum zeitpunkt des Info holens</li>
    <li>firmwareVersion - aktuell auf der Bridge verwendete Firmwareversion</li>
    <li>hardwareId - ID der Hardware Bridge</li>
    <li>lastError - gibt die letzte HTTP Errormeldung wieder</li>
    <li>serverConnected - true/false gibt an ob die Hardwarebridge Verbindung zur Nuki-Cloude hat.</li>
    <li>serverId - gibt die ID des Cloudeservers wieder</li>
    <li>uptime - Uptime der Bridge in Sekunden</li>
    <li>wifiFirmwareVersion- Firmwareversion des Wifi Modules der Bridge</li>
    <br>
    Die vorangestellte Zahl ist forlaufend und gibt beginnend bei 0 die Eigenschaften <b>Eines</b> Smartlocks wieder.
  </ul>
  <br><br>
  <a name="NUKIBridgeset"></a>
  <b>Set</b>
  <ul>
    <li>autocreate - Veranlasst ein erneutes Einlesen aller Smartlocks von der Bridge und falls noch nicht in FHEM vorhanden das autimatische anlegen.</li>
    <li>callbackRemove - Löschen einer Callback Instanz auf der Bridge. Die Instanz ID kann mittels get callbackList ermittelt werden</li>
    <li>clearLog - löscht das Logfile auf der Bridge</li>
    <li>fwUpdate - schaut nach einer neueren Firmware und installiert diese sofern vorhanden</li>
    <li>info - holt aktuellen Informationen über die Bridge</li>
    <li>reboot - veranlässt ein reboot der Bridge</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeget"></a>
  <b>Get</b>
  <ul>
    <li>callbackList - Gibt die Liste der eingetragenen Callback URL's wieder. Die Bridge nimmt maximal 3 auf.</li>
    <li>logFile - Zeigt das Logfile der Bridge an</li>
    <br>
  </ul>
  <br><br>
  <a name="NUKIBridgeattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert die Nuki Bridge</li>
    <br>
  </ul>
</ul>

=end html_DE
=cut

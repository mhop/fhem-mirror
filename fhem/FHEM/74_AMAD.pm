###############################################################################
# 
# Developed with Kate
#
#  (c) 2015-2016 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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
use Time::HiRes qw(gettimeofday);

use HttpUtils;
use TcpServerUtils;
use Encode qw(encode);


my $modulversion = "2.6.6";
my $flowsetversion = "2.6.7";




sub AMAD_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}	= "AMAD_Set";
    $hash->{DefFn}	= "AMAD_Define";
    $hash->{UndefFn}	= "AMAD_Undef";
    $hash->{AttrFn}	= "AMAD_Attr";
    $hash->{ReadFn}	= "AMAD_CommBridge_Read";
    
    $hash->{AttrList} 	= "setOpenApp ".
			  "checkActiveTask ".
			  "setFullscreen:0,1 ".
			  "setScreenOrientation:0,1 ".
			  "setScreenBrightness:noArg ".
			  "setBluetoothDevice ".
			  "setScreenlockPIN ".
			  "setScreenOnForTimer ".
			  "setOpenUrlBrowser ".
			  "setNotifySndFilePath ".
			  "setTtsMsgSpeed ".
			  "setUserFlowState ".
			  "setTtsMsgLang:de,en ".
			  "setAPSSID ".
			  "root:0,1 ".
			  "port ".
			  "disable:1 ".
			  $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{AMAD}{defptr}}) {
	my $hash = $modules{AMAD}{defptr}{$d};
	$hash->{VERSIONMODUL}      = $modulversion;
	$hash->{VERSIONFLOWSET}    = $flowsetversion;
    }
}

sub AMAD_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    return "too few parameters: define <name> AMAD <HOST-IP>" if( $a[0] ne "AMADCommBridge" and @a < 2 and @a > 4 );

    my $name    	= $a[0];
    my $host    	= $a[2] if( $a[2] );
    $a[3] =~ s/@@/ /g if( $a[3] );
    my $apssid          = $a[3] if( $a[3] );
    my $port		= 8090;

    $hash->{HOST} 	= $host if( $host );
    $hash->{PORT} 	= $port;
    $hash->{APSSID}     = $apssid if( $hash->{HOST} );
    $hash->{VERSIONMODUL} 	= $modulversion;
    $hash->{VERSIONFLOWSET} 	= $flowsetversion;
    $hash->{helper}{infoErrorCounter} = 0 if( $hash->{HOST} );
    $hash->{helper}{setCmdErrorCounter} = 0 if( $hash->{HOST} );
    $hash->{helper}{deviceStateErrorCounter} = 0 if( $hash->{HOST} );




    if( ! $hash->{HOST} ) {
	return "there is already a AMAD Bridge, did you want to define a AMAD host use: define <name> AMAD <HOST-IP>" if( $modules{AMAD}{defptr}{BRIDGE} );

	$hash->{BRIDGE} = 1;
	$modules{AMAD}{defptr}{BRIDGE} = $hash;
	$attr{$name}{room} = "AMAD" if( !defined( $attr{$name}{room} ) );
	Log3 $name, 3, "AMAD ($name) - defined Bridge with Socketport $hash->{PORT}";
	Log3 $name, 3, "AMAD ($name) - Attention!!! By the first run, dont forget to \"set $name fhemServerIP <IP-FHEM>\"";
	AMAD_CommBridge_Open( $hash );

    } else {
	if( ! $modules{AMAD}{defptr}{BRIDGE} && $init_done ) {
	    CommandDefine( undef, "AMADCommBridge AMAD" );    
	}   

	Log3 $name, 3, "AMAD ($name) - defined with host $hash->{HOST} on port $hash->{PORT} and AccessPoint-SSID $hash->{APSSID}" if(  $hash->{APSSID} );
	Log3 $name, 3, "AMAD ($name) - defined with host $hash->{HOST} on port $hash->{PORT} and NONE AccessPoint-SSID" if( ! $hash->{APSSID} );
	
	$attr{$name}{room} = "AMAD" if( !defined( $attr{$name}{room} ) );
	readingsSingleUpdate ( $hash, "state", "initialized", 1 ) if( $hash->{HOST} );
	readingsSingleUpdate ( $hash, "deviceState", "unknown", 1 ) if( $hash->{HOST} );
        
        RemoveInternalTimer($hash);
        
        
        if( $init_done ) {
            AMAD_GetUpdate($hash);
        } else {
            InternalTimer( gettimeofday()+30, "AMAD_GetUpdate", $hash, 0 ) if( ($hash->{HOST}) );
        }

	$modules{AMAD}{defptr}{$hash->{HOST}} = $hash;

	return undef;
    }
}

sub AMAD_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    if( $hash->{BRIDGE} or $hash->{TEMPORARY} == 1 ) {
	delete $modules{AMAD}{defptr}{BRIDGE} if( defined($modules{AMAD}{defptr}{BRIDGE}) and $hash->{BRIDGE} );
	TcpServer_Close( $hash );
    } 
    
    elsif( $hash->{HOST} ) {

        delete $modules{AMAD}{defptr}{$hash->{HOST}};
	RemoveInternalTimer( $hash );
    
	foreach my $d(sort keys %{$modules{AMAD}{defptr}}) {
	    my $hash = $modules{AMAD}{defptr}{$d};
	    my $host = $hash->{HOST};
	    
	    return if( $host );
              my $name = $hash->{NAME};
              CommandDelete( undef, $name );
	}
    }
    
    return undef;
}

sub AMAD_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    if( $attrName eq "disable" ) {
	if( $cmd eq "set" ) {
	    if( $attrVal eq "0" ) {
		RemoveInternalTimer( $hash );
		InternalTimer( gettimeofday()+2, "AMAD_GetUpdate", $hash, 0 ) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
		readingsSingleUpdate ( $hash, "state", "active", 1 );
		Log3 $name, 3, "AMAD ($name) - enabled";
	    } else {
		readingsSingleUpdate ( $hash, "state", "disabled", 1 );
		RemoveInternalTimer( $hash );
		Log3 $name, 3, "AMAD ($name) - disabled";
            }
            
        } else {
	    RemoveInternalTimer( $hash );
	    InternalTimer( gettimeofday()+2, "AMAD_GetUpdate", $hash, 0 ) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
	    readingsSingleUpdate ( $hash, "state", "active", 1 );
	    Log3 $name, 3, "AMAD ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "checkActiveTask" ) {
        if( $cmd eq "del" ) {
            CommandDeleteReading( undef, "$name checkActiveTask" ); 
        }
        
        Log3 $name, 3, "AMAD ($name) - $cmd $attrName $attrVal and run statusRequest";
        RemoveInternalTimer( $hash );
        InternalTimer( gettimeofday(), "AMAD_GetUpdate", $hash, 0 )
    }
    
    elsif( $attrName eq "port" ) {
	if( $cmd eq "set" ) {
	    $hash->{PORT} = $attrVal;
	    Log3 $name, 3, "AMAD ($name) - set port to $attrVal";
	    
	    if( $hash->{BRIDGE} ) {
                delete $modules{AMAD}{defptr}{BRIDGE};
                TcpServer_Close( $hash );
                Log3 $name, 3, "AMAD ($name) - CommBridge Port changed. CommBridge are closed and new open!";
                
                AMAD_CommBridge_Open( $hash );
            }

        } else {
	    $hash->{PORT} = 8090;
	    Log3 $name, 3, "AMAD ($name) - set port to default";
	    
	    if( $hash->{BRIDGE} ) {
                delete $modules{AMAD}{defptr}{BRIDGE};
                TcpServer_Close( $hash );
                Log3 $name, 3, "AMAD ($name) - CommBridge Port changed. CommBridge are closed and new open!";
                
                AMAD_CommBridge_Open( $hash );
            }
        }
    }
    
    elsif( $attrName eq "setScreenlockPIN" ) {
	if( $cmd eq "set" && $attrVal ) {
            $attrVal = AMAD_encrypt($attrVal);
        } else {
            CommandDeleteReading( undef, "$name screenLock" );
        }
    }
    
    elsif( $attrName eq "setUserFlowState" ) {
	if( $cmd eq "del" ) {
            CommandDeleteReading( undef, "$name userFlowState" ); 
        }
        
        Log3 $name, 3, "AMAD ($name) - $cmd $attrName $attrVal and run statusRequest";
        RemoveInternalTimer( $hash );
        InternalTimer( gettimeofday(), "AMAD_GetUpdate", $hash, 0 )
    }
    
    
    
    if( $cmd eq "set" ) {
        if( $attrVal && $orig ne $attrVal ) {
            $attr{$name}{$attrName} = $attrVal;
            return $attrName ." set to ". $attrVal if( $init_done );
        }
    }
    
    return undef;
}

sub AMAD_GetUpdate($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $bhash = $modules{AMAD}{defptr}{BRIDGE};
    my $bname = $bhash->{NAME};
    
    RemoveInternalTimer( $hash );

    if( $init_done && ( ReadingsVal( $name, "deviceState", "unknown" ) eq "unknown" or ReadingsVal( $name, "deviceState", "online" ) eq "online" ) && AttrVal( $name, "disable", 0 ) ne "1" && ReadingsVal( $bname, "fhemServerIP", "not set" ) ne "not set" ) {
    
        AMAD_statusRequest( $hash );
        AMAD_checkDeviceState( $hash );
        
    } else {

        Log3 $name, 4, "AMAD ($name) - GetUpdate, FHEM or Device not ready yet";
        Log3 $name, 3, "AMAD ($bname) - GetUpdate, Please set $bname fhemServerIP <IP-FHEM> NOW!" if( ReadingsVal( $bname, "fhemServerIP", "none" ) eq "none" );

        InternalTimer( gettimeofday()+15, "AMAD_GetUpdate", $hash, 0 );
    }
}

sub AMAD_statusRequest($) {

    my ($hash) = @_;
    my $bhash = $modules{AMAD}{defptr}{BRIDGE};
    my $bname = $bhash->{NAME};
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};
    my $bport = $bhash->{PORT};
    my $fhemip = ReadingsVal( $bname, "fhemServerIP", "none" );
    my $activetask = AttrVal( $name, "checkActiveTask", "none" );
    my $userFlowState = AttrVal( $name, "setUserFlowState", "none" );
    my $apssid = "none";
    $apssid = $hash->{APSSID} if( defined($hash->{APSSID}) );
    $apssid = $attr{$name}{setAPSSID} if( defined($attr{$name}{setAPSSID}) );
    

    my $url = "http://" . $host . ":" . $port . "/fhem-amad/deviceInfo/"; # Pfad muß so im Automagic als http request Trigger drin stehen
  
    HttpUtils_NonblockingGet(
	{
	    url		=> $url,
	    timeout	=> 5,
	    hash	=> $hash,
	    method	=> "GET",
	    header	=> "Connection: close\r\nfhemip: $fhemip\r\nfhemdevice: $name\r\nactivetask: $activetask\r\napssid: $apssid\r\nbport: $bport\r\nuserflowstate: $userFlowState",
	    doTrigger	=> 1,
	    callback	=> \&AMAD_statusRequestErrorHandling,
	}
    );
    
    Log3 $name, 5, "AMAD ($name) - Send statusRequest with URL: \"$url\" and Header: \"fhemIP: $fhemip\r\nfhemDevice: $name\r\nactiveTask: $activetask\r\napSSID: $apssid\"";
}

sub AMAD_statusRequestErrorHandling($$$) {
    
    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $doTrigger = $param->{doTrigger};
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    

    ### Begin Error Handling
    if( $hash->{helper}{infoErrorCounter} > 0 ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
	
	if( ReadingsVal( $name, "flow_Informations", "active" ) eq "inactive" && ReadingsVal( $name, "flow_SetCommands", "active" ) eq "inactive" ) {
	    
	    Log3 $name, 5, "AMAD ($name) - statusRequestERROR: CHECK THE LAST ERROR READINGS FOR MORE INFO, DEVICE IS SET OFFLINE";
	     
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    readingsBulkUpdate ( $hash, "state", "AMAD Flows inactive, device set offline");
	}
	
	elsif( $hash->{helper}{infoErrorCounter} > 7 && $hash->{helper}{setCmdErrorCounter} > 4 ) {
	    
	    Log3 $name, 5, "AMAD ($name) - statusRequestERROR: UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
	    
	    $attr{$name}{disable} = 1;
	    readingsBulkUpdate ( $hash, "state", "Unknown Error, device disabled");
	    
	    $hash->{helper}{infoErrorCounter} = 0;
	    $hash->{helper}{setCmdErrorCounter} = 0;
	    
	    return;
	}
	
	elsif( ReadingsVal( $name, "flow_Informations", "active" ) eq "inactive" ) {
	    
	    Log3 $name, 5, "AMAD ($name) - statusRequestERROR: Informations Flow on your Device is inactive, will try to reactivate";
	}
	
	elsif( $hash->{helper}{infoErrorCounter} > 7 ) {
	    
	    Log3 $name, 5, "AMAD ($name) - statusRequestERROR: To many Errors please check your Network or Device Configuration, DEVICE IS SET OFFLINE";
	    
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    readingsBulkUpdate ( $hash, "state", "To many Errors, device set offline");
	    $hash->{helper}{infoErrorCounter} = 0;
	}
	
	elsif($hash->{helper}{infoErrorCounter} > 2 && ReadingsVal( $name, "flow_Informations", "active" ) eq "active" ){
	    
	    Log3 $name, 5, "AMAD ($name) - statusRequestERROR: Please check the AutomagicAPP on your Device";
	}
	
	readingsEndUpdate( $hash, 1 );
    }
    
    if( defined( $err ) ) {
	if( $err ne "" ) {
	    readingsBeginUpdate( $hash );
	    readingsBulkUpdate ( $hash, "state", "$err") if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
	    $hash->{helper}{infoErrorCounter} = ( $hash->{helper}{infoErrorCounter} + 1 );

	    readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
	  
	    if( $err =~ /timed out/ ) {
	    
		Log3 $name, 5, "AMAD ($name) - statusRequestERROR: connect to your device is timed out. check network";
	    }
	    
	    elsif( ( $err =~ /Keine Route zum Zielrechner/ ) && $hash->{helper}{infoErrorCounter} > 1 ) {
	    
		Log3 $name, 5, "AMAD ($name) - statusRequestERROR: no route to target. bad network configuration or network is down";
		
	    } else {

		Log3 $name, 5, "AMAD ($name) - statusRequestERROR: $err";
	    }

	readingsEndUpdate( $hash, 1 );
	
	Log3 $name, 5, "AMAD ($name) - statusRequestERROR: AMAD_statusRequestErrorHandling: error while requesting AutomagicInfo: $err";
	
	return;
	}
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate ( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
	$hash->{helper}{infoErrorCounter} = ( $hash->{helper}{infoErrorCounter} + 1 );
    
	readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
	if( $param->{code} ne 200 ) {

	    Log3 $name, 5, "AMAD ($name) - statusRequestERROR: ".$param->{code};
	}

	readingsEndUpdate( $hash, 1 );
    
	Log3 $name, 5, "AMAD ($name) - statusRequestERROR: received http code ".$param->{code}." without any data after requesting AMAD AutomagicInfo";

	return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state" ,0) ne "initialized" );
	$hash->{helper}{infoErrorCounter} = ( $hash->{helper}{infoErrorCounter} + 1 );

	readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
	    if( $param->{code} eq 404 && ReadingsVal( $name, "flow_Informations", "inactive" ) eq "inactive" ) {

		Log3 $name, 5, "AMAD ($name) - statusRequestERROR: check the informations flow on your device";
	    }
	    
	    elsif( $param->{code} eq 404 && ReadingsVal( $name, "flow_Informations", "active" ) eq "active" ) {
	    
		Log3 $name, 5, "AMAD ($name) - statusRequestERROR: check the automagicApp on your device";
		
	    } else {

		Log3 $name, 5, "AMAD ($name) - statusRequestERROR: http error ".$param->{code};
	    }
	
	readingsEndUpdate( $hash, 1 );
    
	Log3 $name, 5, "AMAD ($name) - statusRequestERROR: received http code ".$param->{code}." receive Error after requesting AMAD AutomagicInfo";

	return;
    }

    ### End Error Handling

    $hash->{helper}{infoErrorCounter} = 0;
}

sub AMAD_ResponseProcessing($$) {

    my ( $hash, $data ) = @_;
    
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};

    ### Begin Response Processing
    Log3 $name, 5, "AMAD ($name) - Processing data: $data";
    readingsSingleUpdate( $hash, "state", "active", 1) if( ReadingsVal( $name, "state", 0 ) ne "initialized" or ReadingsVal( $name, "state", 0 ) ne "active" );
    
    my @valuestring = split( '@@@@', $data );
    my %buffer;
    foreach( @valuestring ) {
	my @values = split( '@@' , $_ );
	$buffer{$values[0]} = $values[1];
    }


    readingsBeginUpdate( $hash );
    
    my $t;
    my $v;
    while( ( $t, $v ) = each %buffer ) {
        if( defined( $v ) ) {
        
            readingsBulkUpdate( $hash, "deviceState", "offline" ) if( $t eq "airplanemode" && $v eq "on" );
            readingsBulkUpdate( $hash, "deviceState", "online" ) if( $t eq "airplanemode" && $v eq "off" );
            $v =~ s/\bnull\b/off/g if( ($t eq "nextAlarmDay" || $t eq "nextAlarmTime") && $v eq "null" );
            
            
            $v =~ s/\bnull\b//g;

            readingsBulkUpdate( $hash, $t, $v );
        }
    }
    
    readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_done" );
    
    
    
    $hash->{helper}{infoErrorCounter} = 0;
    ### End Response Processing
    
    readingsBulkUpdate( $hash, "state", "active" ) if( ReadingsVal( $name, "state", 0 ) eq "initialized" );
    readingsEndUpdate( $hash, 1 );
    
    $hash->{helper}{deviceStateErrorCounter} = 0 if( $hash->{helper}{deviceStateErrorCounter} > 0 and ReadingsVal( $name, "deviceState", "offline") eq "online" );
    
    return undef;
}

sub AMAD_Set($$@) {
    
    my ( $hash, $name, $cmd, @val ) = @_;
    
    my $bhash = $modules{AMAD}{defptr}{BRIDGE};
    my $bname = $bhash->{NAME};
    
    if( $name ne "$bname" ) {
	my $apps = AttrVal( $name, "setOpenApp", "none" );
	my $btdev = AttrVal( $name, "setBluetoothDevice", "none" );
	my $activetask = AttrVal( $name, "setActiveTask", "none" );
  
	my $list = "";
	$list .= "screenMsg ";
	$list .= "ttsMsg ";
	$list .= "volume:slider,0,1,15 ";
	$list .= "mediaGoogleMusic:play,stop,next,back " if( ReadingsVal( $bname, "fhemServerIP", "none" ) ne "none");
	$list .= "mediaAmazonMusic:play,stop,next,back " if( ReadingsVal( $bname, "fhemServerIP", "none" ) ne "none");
	$list .= "mediaSpotifyMusic:play,stop,next,back " if( ReadingsVal( $bname, "fhemServerIP", "none" ) ne "none");
	$list .= "mediaTuneinRadio:play,stop,next,back " if( ReadingsVal( $bname, "fhemServerIP", "none" ) ne "none");
	$list .= "screenBrightness:slider,0,1,255 ";
	$list .= "screen:on,off,lock,unlock ";
	$list .= "screenOrientation:auto,landscape,portrait " if( AttrVal( $name, "setScreenOrientation", "0" ) eq "1" );
	$list .= "screenFullscreen:on,off " if( AttrVal( $name, "setFullscreen", "0" ) eq "1" );
	$list .= "openURL ";
	$list .= "openApp:$apps " if( AttrVal( $name, "setOpenApp", "none" ) ne "none" );
	$list .= "nextAlarmTime:time ";
	$list .= "timer:slider,1,1,60 ";
	$list .= "statusRequest:noArg ";
	$list .= "system:reboot,shutdown,airplanemodeON " if( AttrVal( $name, "root", "0" ) eq "1" );
	$list .= "bluetooth:on,off ";
	$list .= "notifySndFile ";
	$list .= "clearNotificationBar:All,Automagic ";
	$list .= "changetoBTDevice:$btdev " if( AttrVal( $name, "setBluetoothDevice", "none" ) ne "none" );
	$list .= "activateVoiceInput:noArg ";
	$list .= "volumeNotification:slider,0,1,7 ";
	$list .= "vibrate:noArg ";
	$list .= "sendIntent ";
	$list .= "openCall ";
	$list .= "currentFlowsetUpdate:noArg ";
	$list .= "installFlowSource ";
	$list .= "doNotDisturb:never,always,alarmClockOnly,onlyImportant ";
	$list .= "userFlowState ";

	if( lc $cmd eq 'screenmsg'
	    || lc $cmd eq 'ttsmsg'
	    || lc $cmd eq 'volume'
	    || lc $cmd eq 'mediagooglemusic'
	    || lc $cmd eq 'mediaamazonmusic'
	    || lc $cmd eq 'mediaspotifymusic'
	    || lc $cmd eq 'mediatuneinradio'
	    || lc $cmd eq 'screenbrightness'
	    || lc $cmd eq 'screenorientation'
	    || lc $cmd eq 'screenfullscreen'
	    || lc $cmd eq 'screen'
	    || lc $cmd eq 'openurl'
	    || lc $cmd eq 'openapp'
	    || lc $cmd eq 'nextalarmtime'
	    || lc $cmd eq 'timer'
	    || lc $cmd eq 'bluetooth'
	    || lc $cmd eq 'system'
	    || lc $cmd eq 'notifysndfile'
	    || lc $cmd eq 'changetobtdevice'
	    || lc $cmd eq 'clearnotificationbar'
	    || lc $cmd eq 'activatevoiceinput'
	    || lc $cmd eq 'volumenotification'
	    || lc $cmd eq 'screenlock'
	    || lc $cmd eq 'statusrequest'
	    || lc $cmd eq 'sendintent'
	    || lc $cmd eq 'currentflowsetupdate'
	    || lc $cmd eq 'installflowsource'
	    || lc $cmd eq 'opencall'
	    || lc $cmd eq 'donotdisturb'
	    || lc $cmd eq 'userflowstate'
	    || lc $cmd eq 'vibrate') {

	    Log3 $name, 5, "AMAD ($name) - set $name $cmd ".join(" ", @val);
	  
	    return "set command only works if state not equal initialized" if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "initialized");
	    return "Cannot set command, FHEM Device is disabled" if( AttrVal( $name, "disable", "0" ) eq "1" );
	    
	    return "Cannot set command, FHEM Device is unknown" if( ReadingsVal( $name, "deviceState", "online" ) eq "unknown" );
	    return "Cannot set command, FHEM Device is offline" if( ReadingsVal( $name, "deviceState", "online" ) eq "offline" );
	  
	    return AMAD_SelectSetCmd( $hash, $cmd, @val ) if( @val ) || ( lc $cmd eq 'statusrequest' ) || ( lc $cmd eq 'activatevoiceinput' ) || ( lc $cmd eq 'vibrate' ) || ( lc $cmd eq 'currentflowsetupdate' );
	}

	return "Unknown argument $cmd, bearword as argument or wrong parameter(s), choose one of $list";
    }

    elsif( $modules{AMAD}{defptr}{BRIDGE} ) {
    
	my $list = "";
    
	## set Befehle für die AMAD_CommBridge
	$list .= "expertMode:0,1 " if( $modules{AMAD}{defptr}{BRIDGE} );
	$list .= "fhemServerIP " if( $modules{AMAD}{defptr}{BRIDGE} );
	
	if( lc $cmd eq 'expertmode'
	    || lc $cmd eq 'fhemserverip' ) {
	    
	    readingsSingleUpdate( $hash, $cmd, $val[0], 0 );
	    
	    return;
	}
	
	return "Unknown argument $cmd, bearword as argument or wrong parameter(s), choose one of $list";
    }
}

sub AMAD_SelectSetCmd($$@) {

    my ( $hash, $cmd, @data ) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};

    if( lc $cmd eq 'screenmsg' ) {
	my $msg = join( " ", @data );
	
	$msg =~ s/%/%25/g;
	$msg =~ s/\s/%20/g;
	
	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/screenMsg?message=$msg";
	Log3 $name, 4, "AMAD ($name) - Sub AMAD_SetScreenMsg";
	    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'ttsmsg' ) {

        my $msg     = join( " ", @data );
        my $speed   = AttrVal( $name, "setTtsMsgSpeed", "1.0" );
        my $lang    = AttrVal( $name, "setTtsMsgLang","de" );
	
	$msg =~ s/%/%25/g;
	$msg =~ s/\s/%20/g;    
	
	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/ttsMsg?message=".$msg."&msgspeed=".$speed."&msglang=".$lang;
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'userflowstate' ) {

        my $datas = join( " ", @data );
        my ($flow,$state) = split( ":", $datas);
        
	$flow          =~ s/\s/%20/g;    
	
	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/flowState?flowstate=".$state."&flowname=".$flow;
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'volume' ) {
    
	my $vol = join( " ", @data );
	
	if( $vol =~ /^\+(.*)/ or $vol =~ /^-(.*)/ ) {

            if( $vol =~ /^\+(.*)/ ) {
            
                $vol =~ s/^\+//g;
                $vol = ReadingsVal( $name, "volume", 15 ) + $vol;
            }
            
            elsif( $vol =~ /^-(.*)/ ) {
            
                $vol =~ s/^-//g;
                printf $vol;
                $vol = ReadingsVal( $name, "volume", 15 ) - $vol;
            }
	}

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setVolume?volume=$vol";
	
        return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'volumenotification' ) {
    
	my $vol = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setNotifiVolume?notifivolume=$vol";
	
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'mediagooglemusic' or lc $cmd eq 'mediaamazonmusic' or lc $cmd eq 'mediaspotifymusic' or lc $cmd eq 'mediatuneinradio' ) {
    
	my $btn = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/multimediaControl?mplayer=".$cmd."&button=".$btn;
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'screenbrightness' ) {
    
	my $bri = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setBrightness?brightness=$bri";
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'screen' ) {
    
	my $mod = join( " ", @data );
	my $scot = AttrVal( $name, "setScreenOnForTimer", undef );
	$scot = 60 if( !$scot );
	
	if ($mod eq "on" || $mod eq "off") {
            
            my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setScreenOnOff?screen=".$mod."&screenontime=".$scot if ($mod eq "on" || $mod eq "off");
            
            return AMAD_HTTP_POST( $hash,$url );
	}
	
	elsif ($mod eq "lock" || $mod eq "unlock") {
	
            return "Please set \"setScreenlockPIN\" Attribut first" if( AttrVal( $name, "setScreenlockPIN", "none" ) eq "none" );
            my $PIN = AttrVal( $name, "setScreenlockPIN", undef );
            $PIN = AMAD_decrypt($PIN);

            my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/screenlock?lockmod=".$mod."&lockPIN=".$PIN;

            return AMAD_HTTP_POST( $hash,$url );
        }
    }
    
    elsif( lc $cmd eq 'screenorientation' ) {
    
	my $mod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setScreenOrientation?orientation=$mod";
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'activatevoiceinput' ) {

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setvoicecmd";
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'screenfullscreen' ) {
    
	my $mod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setScreenFullscreen?fullscreen=$mod";

	readingsSingleUpdate( $hash, $cmd, $mod, 1 );
	
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'openurl' ) {
    
	my $openurl = join( " ", @data );
	my $browser = AttrVal( $name, "setOpenUrlBrowser", "com.android.chrome|com.google.android.apps.chrome.Main" );
	my @browserapp = split( /\|/, $browser );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/openURL?url=".$openurl."&browserapp=".$browserapp[0]."&browserappclass=".$browserapp[1];
    
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif (lc $cmd eq 'nextalarmtime') {
    
	my $value = join( " ", @data );
	my @alarm = split( ":", $value );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setAlarm?hour=".$alarm[0]."&minute=".$alarm[1];
	
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif (lc $cmd eq 'timer') {
    
	my $timer = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setTimer?minute=$timer";
	
	return AMAD_HTTP_POST( $hash, $url );
    }
    
    elsif( lc $cmd eq 'statusrequest' ) {
    
	AMAD_statusRequest( $hash );
	return undef;
    }
    
    elsif( lc $cmd eq 'openapp' ) {
    
	my $app = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/openApp?app=$app";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'system' ) {
    
	my $systemcmd = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/systemcommand?syscmd=$systemcmd";

	readingsSingleUpdate( $hash, "airplanemode", "on", 1 ) if( $systemcmd eq "airplanemodeON" );
	readingsSingleUpdate( $hash, "deviceState", "offline", 1 ) if( $systemcmd eq "airplanemodeON" || $systemcmd eq "shutdown" );
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'donotdisturb' ) {
    
	my $disturbmod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/donotdisturb?disturbmod=$disturbmod";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'bluetooth' ) {
    
	my $mod = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setbluetooth?bluetooth=$mod";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'notifysndfile' ) {
    
	my $notify = join( " ", @data );
	my $filepath = AttrVal( $name, "setNotifySndFilePath", "/storage/emulated/0/Notifications/" );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/playnotifysnd?notifyfile=".$notify."&notifypath=".$filepath;
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'changetobtdevice' ) {
    
	my $swToBtDevice = join( " ", @data );    
	my @swToBtMac = split( /\|/, $swToBtDevice );
	my $btDevices = AttrVal( $name, "setBluetoothDevice", "none" ) if( AttrVal( $name, "setBluetoothDevice", "none" ) ne "none" );
	my @btDevice = split( ',', $btDevices );
	my @btDeviceOne = split( /\|/, $btDevice[0] );
	my @btDeviceTwo = split( /\|/, $btDevice[1] );
	
	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setbtdevice?swToBtDeviceMac=".$swToBtMac[1]."&btDeviceOne=".$btDeviceOne[1]."&btDeviceTwo=".$btDeviceTwo[1];
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'clearnotificationbar' ) {
    
	my $appname = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/clearnotificationbar?app=$appname";
    
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'vibrate' ) {

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/setvibrate";
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'sendintent' ) {
    
        my $intentstring = join( " ", @data );
        my ( $action, $exkey1, $exval1, $exkey2, $exval2 ) = split( "[ \t][ \t]*", $intentstring );
        $exkey1 = "" if( !$exkey1 );
        $exval1 = "" if( !$exval1 );
        $exkey2 = "" if( !$exkey2 );
        $exval2 = "" if( !$exval2 );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/sendIntent?action=".$action."&exkey1=".$exkey1."&exval1=".$exval1."&exkey2=".$exkey2."&exval2=".$exval2;
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'installflowsource' ) {
    
        my $flowname = join( " ", @data );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/installFlow?flowname=$flowname";
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'opencall' ) {
    
        my $string = join( " ", @data );
        my ($callnumber, $time) = split( "[ \t][ \t]*", $string );
        $time = "none" if( !$time );

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/setCommands/openCall?callnumber=".$callnumber."&hanguptime=".$time;
	
	return AMAD_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'currentflowsetupdate' ) {

	my $url = "http://" . $host . ":" . $port . "/fhem-amad/currentFlowsetUpdate";
	
	return AMAD_HTTP_POST( $hash,$url );
    }

    return undef;
}

sub AMAD_HTTP_POST($$) {

    my ( $hash, $url ) = @_;
    my $name = $hash->{NAME};
    
    my $state = ReadingsVal( $name, "state", 0 );
    
    readingsSingleUpdate( $hash, "state", "Send HTTP POST", 1 );
    
    HttpUtils_NonblockingGet(
	{
	    url		=> $url,
	    timeout	=> 15,
	    hash	=> $hash,
	    method	=> "POST",
	    header	=> "Connection: close",
	    doTrigger	=> 1,
	    callback	=> \&AMAD_HTTP_POSTerrorHandling,
	}
    );
    Log3 $name, 4, "AMAD ($name) - Send HTTP POST with URL $url";

    readingsSingleUpdate( $hash, "state", $state, 1 );

    return undef;
}

sub AMAD_HTTP_POSTerrorHandling($$$) {

    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    

    ### Begin Error Handling
    if( $hash->{helper}{setCmdErrorCounter} > 2 ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "lastSetCommandState", "statusRequest_error" );
	
	if( ReadingsVal( $name, "flow_Informations", "active" ) eq "inactive" && ReadingsVal( $name, "flow_SetCommands", "active" ) eq "inactive" ) {
	    Log3 $name, 5, "AMAD ($name) - setCommandERROR: CHECK THE LAST ERROR READINGS FOR MORE INFO, DEVICE IS SET OFFLINE";
	     
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    readingsBulkUpdate( $hash, "state", "AMAD Flows inactive, device set offline" );
	}
	
	elsif( $hash->{helper}{infoErrorCounter} > 7 && $hash->{helper}{setCmdErrorCounter} > 4 ) {
	    
	    Log3 $name, 5, "AMAD ($name) - setCommandERROR: UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
	    
	    $attr{$name}{disable} = 1;
	    readingsBulkUpdate( $hash, "state", "Unknown Error, device disabled" );
	    $hash->{helper}{infoErrorCounter} = 0;
	    $hash->{helper}{setCmdErrorCounter} = 0;
	    
	    return;
	}
	
	elsif( ReadingsVal( $name, "flow_SetCommands", "active" ) eq "inactive" ) {
	    
	    Log3 $name, 5, "AMAD ($name) - setCommandERROR: Flow SetCommands on your Device is inactive, will try to reactivate";
	}
	
	elsif( $hash->{helper}{setCmdErrorCounter} > 9 ) {
	    
	    Log3 $name, 5, "AMAD ($name) - setCommandERROR: To many Errors please check your Network or Device Configuration, DEVICE IS SET OFFLINE";
	    
	    readingsBulkUpdate( $hash, "deviceState", "offline" );
	    readingsBulkUpdate( $hash, "state", "To many Errors, device set offline" );
	    $hash->{helper}{setCmdErrorCounter} = 0;
	}
	
	elsif( $hash->{helper}{setCmdErrorCounter} > 4 && ReadingsVal( $name, "flow_SetCommands", "active" ) eq "active" ){
	    
	    Log3 $name, 5, "AMAD ($name) - setCommandERROR: Please check the AutomagicAPP on your Device";
	}
	
	readingsEndUpdate( $hash, 1 );
    }
    
    if( defined( $err ) ) {
	if( $err ne "" ) {
	  readingsBeginUpdate( $hash );
	  readingsBulkUpdate( $hash, "state", $err ) if( ReadingsVal( $name, "state", 0 ) ne "initialized" );
	  $hash->{helper}{setCmdErrorCounter} = ($hash->{helper}{setCmdErrorCounter} + 1);
	  
	  readingsBulkUpdate( $hash, "lastSetCommandState", "setCmd_error" );
	  
	  if( $err =~ /timed out/ ) {
	  
	      Log3 $name, 5, "AMAD ($name) - setCommandERROR: connect to your device is timed out. check network";
	  }
	  
	  elsif( $err =~ /Keine Route zum Zielrechner/ ) {
	  
	      Log3 $name, 5, "AMAD ($name) - setCommandERROR: no route to target. bad network configuration or network is down";
	      
	  } else {
	  
	      Log3 $name, 5, "AMAD ($name) - setCommandERROR: $err";
	  }
	  
	  readingsEndUpdate( $hash, 1 );
	  
	  Log3 $name, 5, "AMAD ($name) - setCommandERROR: error while POST Command: $err";
	  
	  return;
	}
    }
 
    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $hash, "state", 0 ) ne "initialized" );
	
	$hash->{helper}{setCmdErrorCounter} = ( $hash->{helper}{setCmdErrorCounter} + 1 );

	readingsBulkUpdate($hash, "lastSetCommandState", "setCmd_error" );

	readingsEndUpdate( $hash, 1 );
    
	Log3 $name, 5, "AMAD ($name) - setCommandERROR: received http code ".$param->{code};

	return;
    }
        
    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {
	readingsBeginUpdate( $hash );
	readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state", 0 ) ne "initialized" );
	
	$hash->{helper}{setCmdErrorCounter} = ( $hash->{helper}{setCmdErrorCounter} + 1 );

	readingsBulkUpdate( $hash, "lastSetCommandState", "setCmd_error" );
    
	    if( $param->{code} eq 404 ) {
	    
		readingsBulkUpdate( $hash, "lastSetCommandError", "" );
		Log3 $name, 5, "AMAD ($name) - setCommandERROR: setCommands flow is inactive on your device!";
		
	    } else {
	    
		Log3 $name, 5, "AMAD ($name) - setCommandERROR: http error ".$param->{code};
	    }
	
	return;
    }
    
    ### End Error Handling
    
    readingsSingleUpdate( $hash, "lastSetCommandState", "setCmd_done", 1 );
    $hash->{helper}{setCmdErrorCounter} = 0;
    
    return undef;
}

sub AMAD_checkDeviceState($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 4, "AMAD ($name) - AMAD_checkDeviceState: run Check";

    RemoveInternalTimer( $hash );
    
    if( ReadingsAge( $name, "deviceState", 90 ) > 90 ) {
    
        AMAD_statusRequest( $hash ) if( $hash->{helper}{deviceStateErrorCounter} == 0 );
        readingsSingleUpdate( $hash, "deviceState", "offline", 1 ) if( ReadingsAge( $name, "deviceState", 180) > 180 and $hash->{helper}{deviceStateErrorCounter} > 0 );
        $hash->{helper}{deviceStateErrorCounter} = ( $hash->{helper}{deviceStateErrorCounter} + 1 );
    }
    
    InternalTimer( gettimeofday()+90, "AMAD_checkDeviceState", $hash, 0 );
    
    Log3 $name, 4, "AMAD ($name) - AMAD_checkDeviceState: set new Timer";
}

sub AMAD_CommBridge_Open($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $port = $hash->{PORT};
    

    # Oeffnen des TCP Sockets
    my $ret = TcpServer_Open( $hash, $port, "global" );
    
    if( $ret && !$init_done ) {
	Log3 $name, 3, "$ret. Exiting.";
	exit(1);
    }
    
    readingsSingleUpdate ( $hash, "state", "opened", 1 );
    Log3 $name, 5, "Socket wird geöffnet.";
    
    return $ret;
}

sub AMAD_CommBridge_Read($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my $bhash = $modules{AMAD}{defptr}{BRIDGE};
    my $bname = $bhash->{NAME};
    
    
    
    if( $hash->{SERVERSOCKET} ) {               # Accept and create a child
        TcpServer_Accept( $hash, "AMAD" );
        return;
    }

    # Read 1024 byte of data
    my $buf;
    my $ret = sysread($hash->{CD}, $buf, 1024);



    # When there is an error in connection return
    if( !defined($ret ) || $ret <= 0 ) {
        CommandDelete( undef, $hash->{NAME} );
        return;
    }
    
    
    #### Verarbeitung der Daten welche über die AMADCommBridge kommen ####

    Log3 $bname, 5, "AMAD ($bname) - Receive RAW Message in Debugging Mode: $buf";
    
    ###
    ## Consume Content
    ###

    my @data = split( '\R\R', $buf );
    
    my $header = AMAD_Header2Hash( $data[0] );
    my $response;
    my $c;
    my $device = $header->{FHEMDEVICE} if(defined($header->{FHEMDEVICE}));
    my $fhemcmd = $header->{FHEMCMD} if(defined($header->{FHEMCMD}));
    my $dhash = $defs{$device} if(defined($device));




    if ( $data[0] =~ /currentFlowsetUpdate.xml/ ) {

        my $fhempath = $attr{global}{modpath};
        $response = qx(cat $fhempath/FHEM/lib/74_AMADautomagicFlowset_$flowsetversion.xml);
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;

        return;
    }
    
    elsif ( $data[0] =~ /installFlow_([^.]*.xml)/ ) {

        if( defined($1) ){
            $response = qx(cat /tmp/$1);
            $c = $hash->{CD};
            print $c "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain\r\n",
                "Connection: close\r\n",
                "Content-Length: ".length($response)."\r\n\r\n",
                $response;

            return;
        }
    }



    elsif( !defined($device) ) {
        readingsSingleUpdate( $bhash, "transmitterERROR", $name." has no device name sends", 1 ) if( ReadingsVal( $bname, "expertMode", 0 ) eq "1" );
        Log3 $name, 4, "AMAD ($name) - ERROR - no device name given. please check your global variable in automagic";
        
        $response = "header lines: \r\n AMADCommBridge receive no device name. please check your global variable in automagic\r\n FHEM to do nothing\r\n";
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
        
        return;
    }



    elsif ( $fhemcmd =~ /setreading\b/ ) {
	my $tv = $data[1];

        Log3 $bname, 4, "AMAD ($bname) - AMAD_CommBridge: processing receive reading values - Device: $device Data: $tv";
    
        AMAD_ResponseProcessing($dhash,$tv);
        
        $response = "header lines: \r\n AMADCommBridge receive Data complete\r\n FHEM was processes\r\n";
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;

        return;
    }

    elsif ( $fhemcmd =~ /set\b/ ) {
        my $fhemCmd = $data[1];
        
        fhem ("set $fhemCmd") if( ReadingsVal( $bname, "expertMode", 0 ) eq "1" );
	readingsSingleUpdate( $bhash, "receiveFhemCommand", "set ".$fhemCmd, 0 );
	Log3 $bname, 4, "AMAD ($bname) - AMAD_CommBridge: set reading receive fhem command";
	
	$response = "header lines: \r\n AMADCommBridge receive Data complete\r\n FHEM execute set command now\r\n";
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
	
	return;
    }
    
    elsif ( $fhemcmd =~ /voiceinputvalue\b/ ) {
        my $fhemCmd = lc $data[1];
        
        readingsBeginUpdate( $bhash);
	readingsBulkUpdate( $bhash, "receiveVoiceCommand", $fhemCmd );
	readingsBulkUpdate( $bhash, "receiveVoiceDevice", $device );
	readingsEndUpdate( $bhash, 1 );
	Log3 $bname, 4, "AMAD ($bname) - AMAD_CommBridge: set reading receive voice command: $fhemCmd from Device $device";
	
	$response = "header lines: \r\n AMADCommBridge receive Data complete\r\n FHEM was processes\r\n";
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
            
	return;
    }
    
    elsif ( $fhemcmd =~ /readingsval\b/ ) {
        my $fhemCmd = $data[1];
        my @datavalue = split( ' ', $fhemCmd );

        $response = ReadingsVal( $datavalue[0], $datavalue[1], $datavalue[2] );
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
        
	Log3 $bname, 4, "AMAD ($bname) - AMAD_CommBridge: response ReadingsVal Value to Automagic Device";
	return;
    }
    
    elsif ( $fhemcmd =~ /fhemfunc\b/ ) {
        my $fhemCmd = $data[1];
	
	Log3 $bname, 4, "AMAD ($bname) - AMAD_CommBridge: receive fhem-function command";
	
        if( $fhemCmd =~ /^{.*}$/ ) {
        
            $response = $fhemCmd if( ReadingsVal( $bname, "expertMode", 0 ) eq "1" );
            
	} else {
	
            $response = "header lines: \r\n AMADCommBridge receive no typical FHEM function\r\n FHEM to do nothing\r\n";
	}
	
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
	
	return;
    }


    $response = "header lines: \r\n AMADCommBridge receive incomplete or corrupt Data\r\n FHEM to do nothing\r\n";
    $c = $hash->{CD};
    print $c "HTTP/1.1 200 OK\r\n",
        "Content-Type: text/plain\r\n",
        "Connection: close\r\n",
        "Content-Length: ".length($response)."\r\n\r\n",
        $response;
}

sub AMAD_Header2Hash($) {

    my ( $string ) = @_;
    my %hash = ();

    foreach my $line (split("\r\n", $string)) {
        my ($key,$value) = split( ": ", $line );
        next if( !$value );

        $value =~ s/^ //;
        $hash{$key} = $value;
    }     
        
    return \%hash;
}

sub AMAD_encrypt($) {

    my ($decodedPIN) = @_;
    my $key = getUniqueId();
    my $encodedPIN;
    
    return $decodedPIN if( $decodedPIN =~ /^crypt:(.*)/ );

    for my $char (split //, $decodedPIN) {
        my $encode = chop($key);
        $encodedPIN .= sprintf("%.2x",ord($char)^ord($encode));
        $key = $encode.$key;
    }
    
    return 'crypt:'. $encodedPIN;
}

sub AMAD_decrypt($) {

    my ($encodedPIN) = @_;
    my $key = getUniqueId();
    my $decodedPIN;

    $encodedPIN = $1 if( $encodedPIN =~ /^crypt:(.*)/ );

    for my $char (map { pack('C', hex($_)) } ($encodedPIN =~ /(..)/g)) {
        my $decode = chop($key);
        $decodedPIN .= chr(ord($char)^ord($decode));
        $key = $decode.$key;
    }

    return $decodedPIN;
}




1;

=pod

=item device
=item summary    Integrates Android devices into FHEM and displays several settings.
=item summary_DE Integriert Android-Geräte in FHEM und zeigt verschiedene Einstellungen an.

=begin html

<a name="AMAD"></a>
<h3>AMAD</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u>
  <br>
  This module integrates Android devices into FHEM and displays several settings <b><u>using the Android app "Automagic"</u></b>.
  Automagic is comparable to the "Tasker" app for automating tasks and configuration settings. But Automagic is more user-friendly. The "Automagic Premium" app currently costs EUR 2.90.
  <br>
  Any information retrievable by Automagic can be displayed in FHEM by this module. Just define your own Automagic-"flow" and send the data to the AMADCommBridge. One even can control several actions on Android devices.
  <br>
  To be able to make use of all these functions the Automagic app and additional flows need to be installed on the Android device. The flows can be retrieved from the FHEM directory, the app can be bought in Google Play Store.
  <br><br>
  <b>How to use AMAD?</b>
  <ul>
    <li>install the "Automagic Premium" app from the Google Play store.</li>
    <li>install the flowset 74_AMADautomagicFlowset$VERSION.xml from the directory $INSTALLFHEM/FHEM/lib/ on your Android device and activate.</li>
  </ul>
  <br>
  Now you need to define a device in FHEM.
  <br><br>
  <a name="AMADdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AMAD &lt;IP-ADDRESS&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define WandTabletWohnzimmer AMAD 192.168.0.23</code><br>
    </ul>
    <br>
    With this command two new AMAD devices in a room called AMAD are created. The parameter &lt;IP-ADDRESS&lt; defines the IP address of your Android device. The second device created is the AMADCommBridge which serves as a communication device from each Android device to FHEM.<br>
    !!!Coming Soon!!! The communication port of each AMAD device may be set by the definition of the "port" attribute. <b>One needs background knowledge of Automagic and HTTP requests as this port will be set in the HTTP request trigger of both flows, therefore the port also needs to be set there.
    <br>
    The communication port of the AMADCommBridge device can easily be changed within the attribut "port".</b>
  </ul>
  <br><a name="AMADCommBridge"></a>
  <b>AMAD Communication Bridge</b>
  <ul>
    Creating your first AMAD device automatically creates the AMADCommBridge device in the room AMAD. With the help  of the AMADCommBridge any Android device communicates initially to FHEM.<b>To make the IP addresse of the FHEM server known to the Android device, the FHEM server IP address needs to be configured in the AMADCommBridge. WITHOUT THIS STEP THE AMADCommBridge WILL NOT WORK PROPERLY.</b><br>
    Please us the following command for configuration of the FHEM server IP address in the AMADCommBridge: <i>set AMADCommBridge fhemServerIP &lt;FHEM-IP&gt;.</i><br>
    Additionally the <i>expertMode</i> may be configured. By this setting a direct communication with FHEM will be established without the restriction of needing to make use of a notify to execute set commands.
  </ul><br>
  <br>
  <b><u>You are finished now! After 15 seconds latest the readings of your AMAD Android device should be updated. Consequently each 15 seconds a status request will be sent. If the state of your AMAD Android device does not change to "active" over a longer period of time one should take a look into the log file for error messages.</u></b>
  <br><br><br>
  <a name="AMADreadings"></a>
  <b>Readings</b>
  <ul>
    <li>airplanemode - on/off, state of the aeroplane mode</li>
    <li>androidVersion - currently installed version of Android</li>
    <li>automagicState - state of the Automagic App <b>(prerequisite Android >4.3). In case you have Android >4.3 and the reading says "not supported", you need to enable Automagic inside Android / Settings / Sound & notification / Notification access</b></li>
    <li>batteryHealth - the health of the battery (1=unknown, 2=good, 3=overheat, 4=dead, 5=over voltage, 6=unspecified failure, 7=cold)</li>
    <li>batterytemperature - the temperature of the battery</li>
    <li>bluetooth - on/off, bluetooth state</li>
    <li>checkActiveTask - state of an app (needs to be defined beforehand). 0=not active or not active in foreground, 1=active in foreground, <b>see note below</b></li>
    <li>connectedBTdevices - list of all devices connected via bluetooth</li>
    <li>connectedBTdevicesMAC - list of MAC addresses of all devices connected via bluetooth</li>
    <li>currentMusicAlbum - currently playing album of mediaplayer</li>
    <li>currentMusicApp - currently playing player app (Amazon Music, Google Play Music, Google Play Video, Spotify, YouTube, TuneIn Player, Aldi Life Music)</li>
    <li>currentMusicArtist - currently playing artist of mediaplayer</li>
    <li>currentMusicIcon - cover of currently play album<b>Noch nicht fertig implementiert</b></li>
    <li>currentMusicState - state of currently/last used mediaplayer</li>
    <li>currentMusicTrack - currently playing song title of mediaplayer</li>
    <li>daydream - on/off, daydream currently active</li>
    <li>deviceState - state of Android devices. unknown, online, offline.</li>
    <li>doNotDisturb - state of do not Disturb Mode</li>
    <li>dockingState - undocked/docked, Android device in docking station</li>
    <li>flow_SetCommands - active/inactive, state of SetCommands flow</li>
    <li>flow_informations - active/inactive, state of Informations flow</li>
    <li>flowsetVersionAtDevice - currently installed version of the flowsets on the Android device</li>
    <li>intentRadioName - name of the most-recent streamed intent radio</li>
    <li>intentRadioState - state of intent radio player</li>
    <li>keyguardSet - 0/1 keyguard set, 0=no 1=yes, does not indicate whether it is currently active</li>
    <li>lastSetCommandError - last error message of a set command</li>
    <li>lastSetCommandState - last state of a set command, command send successful/command send unsuccessful</li>
    <li>lastStatusRequestError - last error message of a statusRequest command</li>
    <li>lastStatusRequestState - ast state of a statusRequest command, command send successful/command send unsuccessful</li>
    <li>nextAlarmDay - currently set day of alarm</li>
    <li>nextAlarmState - alert/done, current state of "Clock" stock-app</li>
    <li>nextAlarmTime - currently set time of alarm</li>
    <li>powerLevel - state of battery in %</li>
    <li>powerPlugged - 0=no/1,2=yes, power supply connected</li>
    <li>screen - on locked,unlocked/off locked,unlocked, state of display</li>
    <li>screenBrightness - 0-255, level of screen-brightness</li>
    <li>screenFullscreen - on/off, full screen mode</li>
    <li>screenOrientation - Landscape/Portrait, screen orientation (horizontal,vertical)</li>
    <li>screenOrientationMode - auto/manual, mode for screen orientation</li>
    <li>state - current state of AMAD device</li>
    <li>userFlowState - current state of a Flow, established under setUserFlowState Attribut</li>
    <li>volume - media volume setting</li>
    <li>volumeNotification - notification volume setting</li>
    <br>
    Prerequisite for using the reading checkActivTask the package name of the application to be checked needs to be defined in the attribute <i>checkActiveTask</i>. Example: <i>attr Nexus10Wohnzimmer
    checkActiveTask com.android.chrome</i> f&uuml;r den Chrome Browser.
    <br><br>
  </ul>
  <br><br>
  <a name="AMADset"></a>
  <b>Set</b>
  <ul>
    <li>activateVoiceInput - start voice input on Android device</li>
    <li>bluetooth - on/off, switch bluetooth on/off</li>
    <li>clearNotificationBar - All/Automagic, deletes all or only Automagic notifications in status bar</li>
    <li>currentFlowsetUpdate - start flowset update on Android device</li>
    <li>installFlowSource - install a Automagic flow on device, <u>XML file must be stored in /tmp/ with extension xml</u>. <b>Example:</b> <i>set TabletWohnzimmer installFlowSource WlanUebwerwachen.xml</i></li>
    <li>doNotDisturb - sets the do not Disturb Mode, always Disturb, never Disturb, alarmClockOnly alarm Clock only, onlyImportant only important Disturbs</li>
    <li>mediaAmazonMusic - play/stop/next/back , controlling the amazon music media player</li>
    <li>mediaGoogleMusic - play/stop/next/back , controlling the google play music media player</li>
    <li>mediaSpotifyMusic - play/stop/next/back , controlling the spotify media player</li>
    <li>nextAlarmTime - sets the alarm time. Only valid for the next 24 hours.</li>
    <li>notifySndFile - plays a media-file <b>which by default needs to be stored in the folder "/storage/emulated/0/Notifications/" of the Android device. You may use the attribute setNotifySndFilePath for defining a different folder.</b></li>
    <li>screenBrightness - 0-255, set screen brighness</li>
    <li>screenMsg - display message on screen of Android device</li>
    <li>sendintent - send intent string <u>Example:</u><i> set $AMADDEVICE sendIntent org.smblott.intentradio.PLAY url http://stream.klassikradio.de/live/mp3-192/stream.klassikradio.de/play.m3u name Klassikradio</i>, first parameter contains the action, second parameter contains the extra. At most two extras can be used.</li>
    <li>statusRequest - Get a new status report of Android device. Not all readings can be updated using a statusRequest as some readings are only updated if the value of the reading changes.</li>
    <li>timer - set a countdown timer in the "Clock" stock app. Only seconds are allowed as parameter.</li>
    <li>ttsMsg - send a message which will be played as voice message</li>
    <li>userFlowState - set Flow/s active or inactive,<b><i>set Nexus7Wohnzimmer Badezimmer:inactive vorheizen</i> or <i>set Nexus7Wohnzimmer Badezimmer vorheizen,Nachtlicht Steven:inactive</i></b></li>
    <li>vibrate - vibrate Android device</li>
    <li>volume - set media volume. Works on internal speaker or, if connected, bluetooth speaker or speaker connected via stereo jack</li>
    <li>volumeNotification - set notifications volume</li>
  </ul>
  <br>
  <b>Set (depending on attribute values)</b>
  <ul>
    <li>changetoBtDevice - switch to another bluetooth device. <b>Attribute setBluetoothDevice needs to be set. See note below!</b></li>
    <li>openApp - start an app. <b>attribute setOpenApp</b></li>
    <li>openURL - opens a URLS in the standard browser as long as no other browser is set by the <b>attribute setOpenUrlBrowser</b>.<b>Example:</b><i> attr Tablet setOpenUrlBrowser de.ozerov.fully|de.ozerov.fully.MainActivity, first parameter: package name, second parameter: Class Name</i></li>
    <li>screen - on/off/lock/unlock, switch screen on/off or lock/unlock screen. In Automagic "Preferences" the "Device admin functions" need to be enabled, otherwise "Screen off" does not work. <b>attribute setScreenOnForTimer</b> changes the time the display remains switched on!</li>
    <li>screenFullscreen - on/off, activates/deactivates full screen mode. <b>attribute setFullscreen</b></li>
    <li>screenLock - Locks screen with request for PIN. <b>attribute setScreenlockPIN - enter PIN here. Only use numbers, 4-16 numbers required.</b></li>
    <li>screenOrientation - Auto,Landscape,Portait, set screen orientation (automatic, horizontal, vertical). <b>attribute setScreenOrientation</b></li>
    <li>system - issue system command (only with rooted Android devices). reboot,shutdown,airplanemodeON (can only be switched ON) <b>attribute root</b>, in Automagic "Preferences" "Root functions" need to be enabled.</li>
    <li>setAPSSID - set WLAN AccesPoint SSID to prevent WLAN sleeps</li>
    <li>setNotifySndFilePath - set systempath to notifyfile (default /storage/emulated/0/Notifications/</li>
    <li>setTtsMsgSpeed - set speaking speed for TTS (Value between 0.5 - 4.0, 0.5 Step) default is 1.0</li>
    <li>setTtsMsgLang - set speaking language for TTS, de or en (default is de)</li>
    <br>
    To be able to use "openApp" the corresponding attribute "setOpenApp" needs to contain the app package name.
    <br><br>
    To be able to switch between bluetooth devices the attribute "setBluetoothDevice" needs to contain (a list of) bluetooth devices defined as follows: <b>attr &lt;DEVICE&gt; BTdeviceName1|MAC,BTDeviceName2|MAC</b> No spaces are allowed in any BTdeviceName. Defining MAC please make sure to use the character : (colon) after each  second digit/character.<br>
    Example: <i>attr Nexus10Wohnzimmer setBluetoothDevice Logitech_BT_Adapter|AB:12:CD:34:EF:32,Anker_A3565|GH:56:IJ:78:KL:76</i> 
  </ul>
  <br><br>
  <a name="AMADstate"></a>
  <b>state</b>
  <ul>
    <li>initialized - shown after initial define.</li>
    <li>active - device is active.</li>
    <li>disabled - device is disabled by the attribute "disable".</li>
  </ul>
  <br><br><br>
  <u><b>Further examples and reading:</b></u>
  <ul><br>
    <a href="http://www.fhemwiki.de/wiki/AMAD#Anwendungsbeispiele">Wiki page for AMAD (german only)</a>
  </ul>
  <br><br><br>
</ul>

=end html
=begin html_DE

<a name="AMAD"></a>
<h3>AMAD</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u>
  <br>
  Dieses Modul liefert, <b><u>in Verbindung mit der Android APP Automagic</u></b>, diverse Informationen von Android Ger&auml;ten.
  Die AndroidAPP Automagic (welche nicht von mir stammt und 2.90 Euro kostet) funktioniert wie Tasker, ist aber bei weitem User freundlicher.
  <br>
  Mit etwas Einarbeitung k&ouml;nnen jegliche Informationen welche Automagic bereit stellt in FHEM angezeigt werden. Hierzu bedarf es lediglich eines eigenen Flows welcher seine Daten an die AMADCommBridge sendet. Das Modul gibt auch die M&ouml;glichkeit Androidger&auml;te zu steuern.
  <br>
  F&uuml;r all diese Aktionen und Informationen wird auf dem Androidger&auml;t "Automagic" und ein so genannter Flow ben&ouml;tigt. Die App ist &uuml;ber den Google PlayStore zu beziehen. Das ben&ouml;tigte Flowset bekommt man aus dem FHEM Verzeichnis.
  <br><br>
  <b>Wie genau verwendet man nun AMAD?</b>
  <ul>
    <li>man installiert die App "Automagic Premium" aus dem PlayStore.</li>
    <li>dann installiert man das Flowset 74_AMADautomagicFlowset$VERSION.xml aus dem Ordner $INSTALLFHEM/FHEM/lib/ auf dem Androidger&auml;t und aktiviert die Flows.</li>
  </ul>
  <br>
  Es mu&szlig; noch ein Device in FHEM anlegt werden.
  <br><br>
  <a name="AMADdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AMAD &lt;IP-ADRESSE&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define WandTabletWohnzimmer AMAD 192.168.0.23</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt zwei neues AMAD-Device im Raum AMAD.Der Parameter &lt;IP-ADRESSE&gt; legt die IP Adresse des Android Ger&auml;tes fest.<br>
    Das zweite Device ist die AMADCommBridge welche als Kommunikationsbr&uuml;cke vom Androidger&auml;t zu FHEM diehnt. !!!Comming Soon!!! Wer den Port &auml;ndern m&ouml;chte, kann dies &uuml;ber das Attribut "port" tun. <b>Ihr solltet aber wissen was Ihr tut, da dieser Port im HTTP Request Trigger der beiden Flows eingestellt ist. Demzufolge mu&szlig; der Port dort auch ge&auml;ndert werden. Der Port f&uuml;r die Bridge kann ohne Probleme im Bridge Device mittels dem Attribut "port" ver&auml;ndert werden.
    <br>
    Der Port f&uuml;r die Bridge kann ohne Probleme im Bridge Device mittels dem Attribut "port" ver&auml;ndert werden.</b>
  </ul>
  <br><a name="AMADCommBridge"></a>
  <b>AMAD Communication Bridge</b>
  <ul>
    Beim ersten anlegen einer AMAD Deviceinstanz wird automatisch ein Ger&auml;t Namens AMADCommBridge im Raum AMAD mit angelegt. Dieses Ger&auml;t diehnt zur Kommunikation vom Androidger&auml;t zu FHEM ohne das zuvor eine Anfrage von FHEM aus ging. <b>Damit das Androidger&auml;t die IP von FHEM kennt, muss diese sofort nach dem anlegen der Bridge &uuml;ber den set Befehl in ein entsprechendes Reading in die Bridge  geschrieben werden. DAS IST SUPER WICHTIG UND F&Uuml;R DIE FUNKTION DER BRIDGE NOTWENDIG.</b><br>
    Hierf&uuml;r mu&szlig; folgender Befehl ausgef&uuml;hrt werden. <i>set AMADCommBridge fhemServerIP &lt;FHEM-IP&gt;.</i><br>
    Als zweites Reading kann <i>expertMode</i> gesetzen werden. Mit diesem Reading wird eine unmittelbare Komminikation mit FHEM erreicht ohne die Einschr&auml;nkung &uuml;ber ein
    Notify gehen zu m&uuml;ssen und nur reine set Befehle ausf&uuml;hren zu k&ouml;nnen.
  </ul><br>
  <b><u>NUN bitte die Flows AKTIVIEREN!!!</u></b><br>
  <br>
  <b><u>Fertig! Nach anlegen der Ger&auml;teinstanz und dem eintragen der fhemServerIP in der CommBridge sollten nach sp&auml;testens 15 Sekunden bereits die ersten Readings reinkommen. Nun wird alle 15 Sekunden probiert einen Status Request erfolgreich ab zu schlie&szlig;en. Wenn der Status sich &uuml;ber einen l&auml;ngeren Zeitraum nicht auf "active" &auml;ndert, sollte man im Log nach eventuellen Fehlern suchen.</u></b>
  <br><br><br>
  <a name="AMADreadings"></a>
  <b>Readings</b>
  <ul>
    <li>airplanemode - Status des Flugmodus</li>
    <li>androidVersion - aktuell installierte Androidversion</li>
    <li>automagicState - Statusmeldungen von der AutomagicApp <b>(Voraussetzung Android >4.3). Ist Android gr&ouml;&szlig;er 4.3 vorhanden und im Reading steht "wird nicht unterst&uuml;tzt", mu&szlig; in den Androideinstellungen unter Ton und Benachrichtigungen -> Benachrichtigungszugriff ein Haken f&uuml;r Automagic gesetzt werden</b></li>
    <li>batteryHealth - Zustand der Battery (1=unbekannt, 2=gut, 3=&Uuml;berhitzt, 4=tot, 5=&Uumlberspannung, 6=unbekannter Fehler, 7=kalt)</li>
    <li>batterytemperature - Temperatur der Batterie</li>
    <li>bluetooth - on/off, Bluetooth Status an oder aus</li>
    <li>checkActiveTask - Zustand einer zuvor definierten APP. 0=nicht aktiv oder nicht aktiv im Vordergrund, 1=aktiv im Vordergrund, <b>siehe Hinweis unten</b></li>
    <li>connectedBTdevices - eine Liste der verbundenen Ger&auml;t</li>
    <li>connectedBTdevicesMAC - eine Liste der MAC Adressen aller verbundender BT Ger&auml;te</li>
    <li>currentMusicAlbum - aktuell abgespieltes Musikalbum des verwendeten Mediaplayers</li>
    <li>currentMusicApp - aktuell verwendeter Mediaplayer (Amazon Music, Google Play Music, Google Play Video, Spotify, YouTube, TuneIn Player, Aldi Life Music)</li>
    <li>currentMusicArtist - aktuell abgespielter Musikinterpret des verwendeten Mediaplayers</li>
    <li>currentMusicIcon - Cover vom aktuell abgespielten Album <b>Noch nicht fertig implementiert</b></li>
    <li>currentMusicState - Status des aktuellen/zuletzt verwendeten Mediaplayers</li>
    <li>currentMusicTrack - aktuell abgespielter Musiktitel des verwendeten Mediaplayers</li>
    <li>daydream - on/off, Daydream gestartet oder nicht</li>
    <li>deviceState - Status des Androidger&auml;tes. unknown, online, offline.</li>
    <li>doNotDisturb - aktueller Status des nicht st&ouml;ren Modus</li>
    <li>dockingState - undocked/docked Status ob sich das Ger&auml;t in einer Dockinstation befindet.</li>
    <li>flow_SetCommands - active/inactive, Status des SetCommands Flow</li>
    <li>flow_informations - active/inactive, Status des Informations Flow</li>
    <li>flowsetVersionAtDevice - aktuell installierte Flowsetversion auf dem Device</li>
    <li>intentRadioName - zuletzt gesrreamter Intent Radio Name</li>
    <li>intentRadioState - Status des IntentRadio Players</li>
    <li>keyguardSet - 0/1 Displaysperre gesetzt 0=nein 1=ja, bedeutet nicht das sie gerade aktiv ist</li>
    <li>lastSetCommandError - letzte Fehlermeldung vom set Befehl</li>
    <li>lastSetCommandState - letzter Status vom set Befehl, Befehl erfolgreich/nicht erfolgreich gesendet</li>
    <li>lastStatusRequestError - letzte Fehlermeldung vom statusRequest Befehl</li>
    <li>lastStatusRequestState - letzter Status vom statusRequest Befehl, Befehl erfolgreich/nicht erfolgreich gesendet</li>
    <li>nextAlarmDay - aktiver Alarmtag</li>
    <li>nextAlarmState - aktueller Status des <i>"Androidinternen"</i> Weckers</li>
    <li>nextAlarmTime - aktive Alarmzeit</li>
    <li>powerLevel - Status der Batterie in %</li>
    <li>powerPlugged - Netzteil angeschlossen? 0=NEIN, 1|2=JA</li>
    <li>screen - on locked/unlocked, off locked/unlocked gibt an ob der Bildschirm an oder aus ist und gleichzeitig gesperrt oder nicht gesperrt</li>
    <li>screenBrightness - Bildschirmhelligkeit von 0-255</li>
    <li>screenFullscreen - on/off, Vollbildmodus (An,Aus)</li>
    <li>screenOrientation - Landscape,Portrait, Bildschirmausrichtung (Horizontal,Vertikal)</li>
    <li>screenOrientationMode - auto/manual, Modus f&uuml;r die Ausrichtung (Automatisch, Manuell)</li>
    <li>state - aktueller Status</li>
    <li>userFlowState - aktueller Status eines Flows, festgelegt unter dem setUserFlowState Attribut</li>
    <li>volume - Media Lautst&auml;rkewert</li>
    <li>volumeNotification - Benachrichtigungs Lautst&auml;rke</li>
    <br>
    Beim Reading checkActivTask mu&szlig; zuvor der Packagename der zu pr&uuml;fenden App als Attribut <i>checkActiveTask</i> angegeben werden. Beispiel: <i>attr Nexus10Wohnzimmer
    checkActiveTask com.android.chrome</i> f&uuml;r den Chrome Browser.
    <br><br>
  </ul>
  <br><br>
  <a name="AMADset"></a>
  <b>Set</b>
  <ul>
    <li>activateVoiceInput - aktiviert die Spracheingabe</li>
    <li>bluetooth - on/off, aktiviert/deaktiviert Bluetooth</li>
    <li>clearNotificationBar - All,Automagic, l&ouml;scht alle Meldungen oder nur die Automagic Meldungen in der Statusleiste</li>
    <li>currentFlowsetUpdate - f&uuml;rt ein Flowsetupdate auf dem Device durch</li>
    <li>doNotDisturb - schaltet den nicht st&ouml;ren Modus, always immer st&ouml;ren, never niemals st&ouml;ren, alarmClockOnly nur Wecker darf st&ouml;ren, onlyImportant nur wichtige St&ouml;rungen</li>
    <li>installFlowSource - installiert einen Flow auf dem Device, <u>das XML File muss unter /tmp/ liegen und die Endung xml haben</u>. <b>Bsp:</b> <i>set TabletWohnzimmer installFlowSource WlanUebwerwachen.xml</i></li>
    <li>mediaAmazonMusic - play, stop, next, back  ,steuert den Amazon Musik Mediaplayer</li>
    <li>mediaGoogleMusic - play, stop, next, back  ,steuert den Google Play Musik Mediaplayer</li>
    <li>mediaSpotifyMusic - play, stop, next, back  ,steuert den Spotify Mediaplayer</li>
    <li>nextAlarmTime - setzt die Alarmzeit. gilt aber nur innerhalb der n&auml;chsten 24Std.</li>
    <li>screenBrightness - setzt die Bildschirmhelligkeit, von 0-255.</li>
    <li>screenMsg - versendet eine Bildschirmnachricht</li>
    <li>sendintent - sendet einen Intentstring <u>Bsp:</u><i> set $AMADDEVICE sendIntent org.smblott.intentradio.PLAY url http://stream.klassikradio.de/live/mp3-192/stream.klassikradio.de/play.m3u name Klassikradio</i>, der erste Befehl ist die Aktion und der zweite das Extra. Es k&ouml;nnen immer zwei Extras mitgegeben werden.</li>
    <li>statusRequest - Fordert einen neuen Statusreport beim Device an. Es k&ouml;nnen nicht von allen Readings per statusRequest die Daten geholt werden. Einige wenige geben nur bei Status&auml;nderung ihren Status wieder.</li>
    <li>timer - setzt einen Timer innerhalb der als Standard definierten ClockAPP auf dem Device. Es k&ouml;nnen nur Sekunden angegeben werden.</li>
    <li>ttsMsg - versendet eine Nachricht welche als Sprachnachricht ausgegeben wird</li>
    <li>userFlowState - aktiviert oder deaktiviert einen oder mehrere Flows,<b><i>set Nexus7Wohnzimmer Badezimmer vorheizen:inactive</i> oder <i>set Nexus7Wohnzimmer Badezimmer vorheizen,Nachtlicht Steven:inactive</i></b></li>
    <li>vibrate - l&auml;sst das Androidger&auml;t vibrieren</li>
    <li>volume - setzt die Medialautst&auml;rke. Entweder die internen Lautsprecher oder sofern angeschlossen die Bluetoothlautsprecher und per Klinkenstecker angeschlossene Lautsprecher, + oder - vor dem Wert reduziert die aktuelle Lautst&auml;rke um den Wert</li>
    <li>volumeNotification - setzt die Benachrichtigungslautst&auml;rke.</li>
  </ul>
  <br>
  <b>Set abh&auml;ngig von gesetzten Attributen</b>
  <ul>
    <li>changetoBtDevice - wechselt zu einem anderen Bluetooth Ger&auml;t. <b>Attribut setBluetoothDevice mu&szlig; gesetzt sein. Siehe Hinweis unten!</b></li>
    <li>notifySndFile - spielt die angegebene Mediadatei auf dem Androidger&auml;t ab. <b>Die aufzurufende Mediadatei sollte sich im Ordner /storage/emulated/0/Notifications/ befinden. Ist dies nicht der Fall kann man &uuml;ber das Attribut setNotifySndFilePath einen Pfad vorgeben.</b></li>
    <li>openApp - &ouml;ffnet eine ausgew&auml;hlte App. <b>Attribut setOpenApp</b></li>
    <li>openURL - &ouml;ffnet eine URL im Standardbrowser, sofern kein anderer Browser &uuml;ber das <b>Attribut setOpenUrlBrowser</b> ausgew&auml;hlt wurde.<b> Bsp:</b><i> attr Tablet setOpenUrlBrowser de.ozerov.fully|de.ozerov.fully.MainActivity, das erste ist der Package Name und das zweite der Class Name</i></li>
    <li>setAPSSID - setzt die AccessPoint SSID um ein WLAN sleep zu verhindern</li>
    <li>screen - on/off/lock/unlock schaltet den Bildschirm ein/aus oder sperrt/entsperrt ihn, in den Automagic Einstellungen muss "Admin Funktion" gesetzt werden sonst funktioniert "Screen off" nicht. <b>Attribut setScreenOnForTimer</b> &auml;ndert die Zeit wie lange das Display an bleiben soll!</li>
    <li>screenFullscreen - on/off, (aktiviert/deaktiviert) den Vollbildmodus. <b>Attribut setFullscreen</b></li>
    <li>screenLock - Sperrt den Bildschirm mit Pinabfrage. <b>Attribut setScreenlockPIN - hier die Pin daf&uuml;r eingeben. Erlaubt sind nur Zahlen. Es m&uuml;&szlig;en mindestens 4, bis max 16 Zeichen verwendet werden.</b></li>
    <li>screenOrientation - Auto,Landscape,Portait,  aktiviert die Bildschirmausrichtung (Automatisch,Horizontal,Vertikal). <b>Attribut setScreenOrientation</b></li>
    <li>system - setzt Systembefehle ab (nur bei gerootetet Ger&auml;en). reboot,shutdown,airplanemodeON (kann nur aktiviert werden) <b>Attribut root</b>, in den Automagic Einstellungen muss "Root Funktion" gesetzt werden</li>
    <li>setNotifySndFilePath - setzt den korrekten Systempfad zur Notifydatei (default ist /storage/emulated/0/Notifications/</li>
    <li>setTtsMsgSpeed - setzt die Sprachgeschwindigkeit bei der Sprachausgabe(Werte zwischen 0.5 bis 4.0 in 0.5er Schritten) default ist 1.0</li>
    <li>setTtsMsgSpeed - setzt die Sprache bei der Sprachausgabe, de oder en (default ist de)</li>
    <br>
    Um openApp verwenden zu k&ouml;nnen, muss als Attribut der Package Name der App angegeben werden.
    <br><br>
    Um zwischen Bluetoothger&auml;ten wechseln zu k&ouml;nnen, mu&szlig; das Attribut setBluetoothDevice mit folgender Syntax gesetzt werden. <b>attr &lt;DEVICE&gt; BTdeviceName1|MAC,BTDeviceName2|MAC</b> Es muss
    zwingend darauf geachtet werden das beim BTdeviceName kein Leerzeichen vorhanden ist. Am besten zusammen oder mit Unterstrich. Achtet bei der MAC darauf das Ihr wirklich nach jeder zweiten Zahl auch
    einen : drin habt<br>
    Beispiel: <i>attr Nexus10Wohnzimmer setBluetoothDevice Logitech_BT_Adapter|AB:12:CD:34:EF:32,Anker_A3565|GH:56:IJ:78:KL:76</i> 
  </ul>
  <br><br>
  <a name="AMADstate"></a>
  <b>state</b>
  <ul>
    <li>initialized - Ist der Status kurz nach einem define.</li>
    <li>active - die Ger&auml;teinstanz ist im aktiven Status.</li>
    <li>disabled - die Ger&auml;teinstanz wurde &uuml;ber das Attribut disable deaktiviert</li>
  </ul>
  <br><br><br>
  <u><b>Anwendungsbeispiele:</b></u>
  <ul><br>
    <a href="http://www.fhemwiki.de/wiki/AMAD#Anwendungsbeispiele">Hier verweise ich auf den gut gepflegten Wikieintrag</a>
  </ul>
  <br><br><br>
</ul>

=end html_DE
=cut
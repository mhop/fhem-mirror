###############################################################################
# 
# Developed with Kate
#
#  (c) 2015-2018 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Jens Wohlgemuth       Thanks for Commandref
#       - Schlimbo              Tasker integration and Tasker Commandref
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




package main;


my $missingModul = "";

use strict;
use warnings;

eval "use Encode qw(encode encode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";



my $modulversion = "4.2.3";
my $flowsetversion = "4.2.1";




# Declare functions
sub AMADDevice_Attr(@);
sub AMADDevice_Notify($$);
sub AMADDevice_checkDeviceState($);
sub AMADDevice_decrypt($);
sub AMADDevice_Define($$);
sub AMADDevice_encrypt($);
sub AMADDevice_GetUpdate($);
sub AMADDevice_Initialize($);
sub AMADDevice_WriteReadings($$);
sub AMADDevice_Set($$@);
sub AMADDevice_Undef($$);
sub AMADDevice_Parse($$);
sub AMADDevice_statusRequest($);
sub AMADDevice_CreateVolumeValue($$@);
sub AMADDevice_CreateTtsMsgValue($@);
sub AMADDevice_CreateScreenValue($$);
sub AMADDevice_CreateChangeBtDeviceValue($$);




sub AMADDevice_Initialize($) {

    my ($hash) = @_;
    
    $hash->{Match}          = '{"amad": \{"amad_id":.+}}';


    $hash->{SetFn}      = "AMADDevice_Set";
    $hash->{DefFn}      = "AMADDevice_Define";
    $hash->{UndefFn}    = "AMADDevice_Undef";
    $hash->{AttrFn}     = "AMADDevice_Attr";
    $hash->{NotifyFn}   = "AMADDevice_Notify";
    $hash->{ParseFn}    = "AMADDevice_Parse";
    
    $hash->{AttrList}   = "setOpenApp ".
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
                "setTtsMsgLang:de,en ".
                "setTtsMsgVol ".
                "setUserFlowState ".
                "setVolUpDownStep:1,2,4,5 ".
                "setVolMax ".
                "setVolFactor:2,3,4,5 ".
                "setNotifyVolMax ".
                "setRingSoundVolMax ".
                "setAPSSID ".
                "root:0,1 ".
                "disable:1 ".
                "IODev ".
                "remoteServer:Automagic,Autoremote,TNES,other ".
                "setTakeScreenshotResolution:1280x720,1920x1080,1920x1200 ".
                "setTakePictureResolution:800x600,1024x768,1280x720,1600x1200,1920x1080 ".
                "setTakePictureCamera:Back,Front ".
                $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{AMADDevice}{defptr}}) {
    
        my $hash = $modules{AMADDevice}{defptr}{$d};
        $hash->{VERSIONMODUL}      = $modulversion;
        $hash->{VERSIONFLOWSET}    = $flowsetversion;
    }
}

sub AMADDevice_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t]+", $def );
    
    return "too few parameters: define <name> AMADDevice <HOST-IP> <amad_id> <remoteServer>" if( @a != 5 );
    return "Cannot define a AMADDevice device. Perl modul $missingModul is missing." if ( $missingModul );


    my $name                                    = $a[0];
    my $host                                    = $a[2];
    my $amad_id                                 = $a[3];
    my $remoteServer                            = $a[4];
    
    $hash->{HOST}                               = $host;
    $hash->{AMAD_ID}                            = $amad_id;
    $hash->{VERSIONMODUL}                       = $modulversion;
    $hash->{VERSIONFLOWSET}                     = $flowsetversion;
    $hash->{NOTIFYDEV}                          = "global,$name";
    
    $hash->{PORT}                               = 8090 if($remoteServer eq 'Automagic');
    $hash->{PORT}                               = 1817 if($remoteServer eq 'Autoremote');
    $hash->{PORT}                               = 8765 if($remoteServer eq 'TNES');
    $hash->{PORT}                               = 1111 if($remoteServer eq 'other');        # Dummy Port for other
    
    $hash->{helper}{infoErrorCounter}           = 0;
    $hash->{helper}{setCmdErrorCounter}         = 0;
    $hash->{helper}{deviceStateErrorCounter}    = 0;



    CommandAttr(undef,"$name IODev $modules{AMADCommBridge}{defptr}{BRIDGE}->{NAME}") if(AttrVal($name,'IODev','none') eq 'none');

    my $iodev           = AttrVal($name,'IODev','none');
    
    AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
    
    if(defined($hash->{IODev}->{NAME})) {
        Log3 $name, 3, "AMADDevice ($name) - I/O device is " . $hash->{IODev}->{NAME};
    } else {
        Log3 $name, 1, "AMADDevice ($name) - no I/O device";
    }


    $iodev = $hash->{IODev}->{NAME};
    
    my $d = $modules{AMADDevice}{defptr}{$amad_id};
    
    return "AMADDevice device $name on AMADCommBridge $iodev already defined."
    if( defined($d) and $d->{IODev} == $hash->{IODev} and $d->{NAME} ne $name );

    

    CommandAttr(undef,"$name room AMAD") if(AttrVal($name,'room','none') eq 'none');
    CommandAttr(undef,"$name remoteServer $remoteServer") if(AttrVal($name,'remoteServer','none') eq 'none');
        
    readingsBeginUpdate($hash);
    readingsBulkUpdateIfChanged( $hash, "state", "initialized",1);
    readingsBulkUpdateIfChanged( $hash, "deviceState", "unknown",1);
    readingsEndUpdate($hash,1);
    
    
    Log3 $name, 3, "AMADDevice ($name) - defined with AMAD_ID: $amad_id on port $hash->{PORT}";


    $modules{AMADDevice}{defptr}{$amad_id} = $hash;

    return undef;
}

sub AMADDevice_Undef($$) {

    my ( $hash, $arg )  = @_;
    my $name            = $hash->{NAME};
    my $amad_id         = $hash->{AMAD_ID};
    
    
    RemoveInternalTimer( $hash );
    delete $modules{AMADDevice}{defptr}{$amad_id};

    return undef;
}

sub AMADDevice_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    if( $attrName eq "remoteServer" ) {
        if( $cmd eq "set" ) {
            if( $attrVal eq "Automagic" ) {
                $hash->{PORT}   = 8090;
                Log3 $name, 3, "AMADDevice ($name) - set remoteServer to Automagic";
            
            } elsif( $attrVal eq "Autoremote" ) {
                $hash->{PORT}   = 1817;
                Log3 $name, 3, "AMADDevice ($name) - set remoteServer to Autoremote";
            
            } elsif( $attrVal eq "TNES" ) {
                $hash->{PORT}   = 8765;
                Log3 $name, 3, "AMADDevice ($name) - set remoteServer to TNES";
            
            } elsif( $attrVal eq "other" ) {
                $hash->{PORT}   = 1111;
                Log3 $name, 3, "AMADDevice ($name) - set remoteServer to other";
            }
            
            $hash->{DEF} = "$hash->{HOST} $hash->{AMAD_ID} $attrVal";
        }
    }
    
    elsif( $attrName eq "disable" ) {
        if( $cmd eq "set" ) {
            if( $attrVal eq "0" ) {
                readingsSingleUpdate ( $hash, "state", "active", 1 );
                Log3 $name, 3, "AMADDevice ($name) - enabled";
            } else {
                RemoveInternalTimer($hash);
                readingsSingleUpdate ( $hash, "state", "disabled", 1 );
                Log3 $name, 3, "AMADDevice ($name) - disabled";
            }
            
        } else {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "AMADDevice ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "checkActiveTask" ) {
        if( $cmd eq "del" ) {
            CommandDeleteReading( undef, "$name checkActiveTask" ); 
        }
        
        Log3 $name, 3, "AMADDevice ($name) - $cmd $attrName $attrVal and run statusRequest";
    }
    
    elsif( $attrName eq "setScreenlockPIN" ) {
        if( $cmd eq "set" and $attrVal ) {
        
            $attrVal = AMADDevice_encrypt($attrVal);
            
        } else {
        
            CommandDeleteReading( undef, "$name screenLock" );
        }
    }
    
    elsif( $attrName eq "setUserFlowState" ) {
        if( $cmd eq "del" ) {
        
            CommandDeleteReading( undef, "$name userFlowState" ); 
        }
        
        Log3 $name, 3, "AMADDevice ($name) - $cmd $attrName $attrVal and run statusRequest";
    }
    
    
    
    if( $cmd eq "set" ) {
        if( $attrVal and $orig ne $attrVal ) {
        
            $attr{$name}{$attrName} = $attrVal;
            return $attrName ." set to ". $attrVal if( $init_done );
        }
    }
    
    return undef;
}

sub AMADDevice_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    AMADDevice_statusRequest($hash) if( (grep /^DELETEATTR.$name.setAPSSID$/,@{$events}
                                                    or grep /^ATTR.$name.setAPSSID.*/,@{$events}
                                                    or grep /^DELETEATTR.$name.checkActiveTask$/,@{$events}
                                                    or grep /^ATTR.$name.checkActiveTask.*/,@{$events}
                                                    or grep /^DELETEATTR.$name.setUserFlowState$/,@{$events}
                                                    or grep /^ATTR.$name.setUserFlowState.*/,@{$events})
                                                    and $init_done and $devname eq 'global' );

    AMADDevice_GetUpdate($hash) if( (grep /^DEFINED.$name$/,@{$events}
                                                    or grep /^INITIALIZED$/,@{$events}
                                                    or grep /^MODIFIED.$name$/,@{$events})
                                                    and $devname eq 'global' and $init_done  );
                                                    
    AMADDevice_checkDeviceState($hash) if( (grep /^DELETEATTR.$name.disable$/,@{$events}
                                                    or grep /^ATTR.$name.disable.0$/,@{$events})
                                                    and $devname eq 'global' and $init_done );

    return;
}

sub AMADDevice_GetUpdate($) {

    my ( $hash ) = @_;
    my $name    = $hash->{NAME};
    my $bname   = $hash->{IODev}->{NAME};
    
    
    RemoveInternalTimer( $hash );
    
    if( $init_done and ( ReadingsVal( $name, "deviceState", "unknown" ) eq "unknown" or ReadingsVal( $name, "deviceState", "online" ) eq "online" ) and AttrVal( $name, "disable", 0 ) ne "1" and ReadingsVal( $bname, "fhemServerIP", "not set" ) ne "not set" ) {

        AMADDevice_statusRequest($hash);
        AMADDevice_checkDeviceState( $hash );
        
    } else {

        Log3 $name, 4, "AMADDevice ($name) - GetUpdate, FHEM or Device not ready yet";
        Log3 $name, 3, "AMADDevice ($bname) - GetUpdate, Please set $bname fhemServerIP <IP-FHEM> NOW!" if( ReadingsVal( $bname, "fhemServerIP", "none" ) eq "none" );

        InternalTimer( gettimeofday()+30, "AMADDevice_GetUpdate", $hash, 0 );
    }
}

sub AMADDevice_statusRequest($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    my $host                = $hash->{HOST};
    my $port                = $hash->{PORT};
    my $amad_id             = $hash->{AMAD_ID};
    my $uri                 = $hash->{HOST} . ":" . $hash->{PORT};
    my $header              = 'Connection: close';
    my $path;
    my $method;
    
    
    my $activetask      = AttrVal( $name, "checkActiveTask", "none" );
    my $userFlowState   = AttrVal( $name, "setUserFlowState", "none" );
    my $apssid          = AttrVal( $name, "setAPSSID", "none" );
    my $fhemip          = ReadingsVal($hash->{IODev}->{NAME}, "fhemServerIP", "none");
    my $fhemCtlMode     = AttrVal($hash->{IODev}->{NAME},'fhemControlMode','none' );
    my $bport           = $hash->{IODev}->{PORT};

    $header  .= "\r\nfhemip: $fhemip\r\nfhemdevice: $name\r\nactivetask: $activetask\r\napssid: $apssid\r\nbport: $bport\r\nuserflowstate: $userFlowState\r\nfhemctlmode: $fhemCtlMode";
    
    $method  = "GET" if( AttrVal($name,'remoteServer','Automagic') eq 'Automagic' );
    $method  = "POST" if (AttrVal($name,'remoteServer','Automagic') ne 'Automagic' );
    
    $path     ="/fhem-amad/deviceInfo/";       # Pfad muß so im Automagic als http request Trigger drin stehen


    IOWrite($hash,$amad_id,$uri,$path,$header,$method);
    Log3 $name, 5, "AMADDevice ($name) - IOWrite: $uri $method IODevHash=$hash->{IODev}";
}

sub AMADDevice_WriteReadings($$) {

    my ( $hash, $decode_json ) = @_;
    
    my $name = $hash->{NAME};


    ############################
    #### schreiben der Readings

    Log3 $name, 5, "AMADDevice ($name) - Processing data: $decode_json";
    readingsSingleUpdate( $hash, "state", "active", 1) if( ReadingsVal( $name, "state", 0 ) ne "initialized" and ReadingsVal( $name, "state", 0 ) ne "active" );
    
    ### Event Readings
    my $t;
    my $v;
    
    
    readingsBeginUpdate($hash);
    
    while( ( $t, $v ) = each %{$decode_json->{payload}} ) {
        
        $v =~ s/\bnull\b/off/g if( ($t eq "nextAlarmDay" or $t eq "nextAlarmTime") and $v eq "null" );
        $v =~ s/\bnull\b//g;
        $v = encode_utf8($v);
        
        readingsBulkUpdateIfChanged($hash, $t, $v, 1)   if( defined( $v ) and ($t ne 'deviceState'
                                                            or $t ne 'incomingCallerName'
                                                            or $t ne 'incomingCallerNumber'
                                                            or $t ne 'incomingTelegramMessage'
                                                            or $t ne 'incomingSmsMessage'
                                                            or $t ne 'incomingWhatsAppMessage'
                                                            or $t ne 'nfcLastTagID')
                                                        );

        readingsBulkUpdateIfChanged( $hash, $t, ($v / AttrVal($name,'setVolFactor',1)) ) if( $t eq 'volume' and AttrVal($name,'setVolFactor',1) > 1 );
        readingsBulkUpdate( $hash, '.'.$t, $v ) if( $t eq 'deviceState' );
        readingsBulkUpdate( $hash, $t, $v ) if( defined( $v ) and ($t eq 'incomingCallerName'
                                                    or $t eq 'incomingCallerNumber'
                                                    or $t eq 'incomingTelegramMessage'
                                                    or $t eq 'incomingSmsMessage'
                                                    or $t eq 'incomingWhatsAppMessage'
                                                    or $t eq 'nfcLastTagID')
                                            );
    }
    
    readingsBulkUpdateIfChanged( $hash, "deviceState", "offline", 1 ) if( $decode_json->{payload}{airplanemode} and $decode_json->{payload}{airplanemode} eq "on" );
    readingsBulkUpdateIfChanged( $hash, "deviceState", "online", 1 ) if( $decode_json->{payload}{airplanemode} and $decode_json->{payload}{airplanemode} eq "off" );

    readingsBulkUpdateIfChanged( $hash, "lastStatusRequestState", "statusRequest_done", 1 );
    
    if( ReadingsVal($name,'volume',1) > 0 ) {
        readingsBulkUpdateIfChanged( $hash, "mute", "off", 1 );
    } else {
        readingsBulkUpdateIfChanged( $hash, "mute", "on", 1 );
    }

    $hash->{helper}{infoErrorCounter} = 0;
    ### End Response Processing
    
    readingsBulkUpdateIfChanged( $hash, "state", "active", 1 ) if( ReadingsVal( $name, "state", 0 ) eq "initialized" );
    readingsEndUpdate( $hash, 1 );
    
    $hash->{helper}{deviceStateErrorCounter} = 0 if( $hash->{helper}{deviceStateErrorCounter} > 0 and ReadingsVal( $name, "deviceState", "offline") eq "online" );
    
    return undef;
}

sub AMADDevice_Set($$@) {

    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)        = @aa;

    my $amad_id             = $hash->{AMAD_ID};
    my $header              = 'Connection: close';
    my $uri                 = $hash->{HOST} . ":" . $hash->{PORT};
    my $path;
    my $method;
    
    my @playerList          = ('GoogleMusic','SamsungMusic','AmazonMusic','SpotifyMusic','TuneinRadio','AldiMusic','YouTube',
                                'YouTubeKids','VlcPlayer','Audible','Deezer','Poweramp','MXPlayerPro');
    my @playerCmd           = ('mediaPlay','mediaStop','mediaNext','mediaBack');
    
    my $volMax              = AttrVal($name,'setVolMax',15);
    my $notifyVolMax        = AttrVal($name,'setNotifyVolMax',7);
    my $ringSoundVolMax     = AttrVal($name,'setRingSoundVolMax',7);
    

    if( lc $cmd eq 'screenmsg' ) {
        my $msg = join( " ", @args );

        $path   = "/fhem-amad/setCommands/screenMsg?message=".urlEncode($msg);
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'ttsmsg' ) {
        my ($msg,$speed,$lang,$ttsmsgvol)   = AMADDevice_CreateTtsMsgValue($hash,@args);
        
        $path   = "/fhem-amad/setCommands/ttsMsg?message=".urlEncode($msg)."&msgspeed=".$speed."&msglang=".$lang."&msgvol=".$ttsmsgvol;
        $method                             = "POST";
    }
    
    elsif( lc $cmd eq 'userflowstate' ) {
        my $datas           = join( " ", @args );
        my ($flow,$state)   = split( ":", $datas);

        $path   = "/fhem-amad/setCommands/flowState?flowstate=".$state."&flowname=".urlEncode($flow);
        $method     = "POST";
    }
    
    elsif( lc $cmd eq 'userflowrun' ) {
        my $flow            = join( " ", @args );

        $path   = "/fhem-amad/setCommands/flowRun?flowname=".urlEncode($flow);
        $method     = "POST";
    }
    
    elsif( lc $cmd eq 'volume' or $cmd eq 'mute' or $cmd =~ 'volume[Down|Up]' ) {
        my $vol     = AMADDevice_CreateVolumeValue($hash,$cmd,@args);
    
        $path   = "/fhem-amad/setCommands/setVolume?volume=$vol";
        $method     = "POST";
    }
    
    elsif( lc $cmd eq 'volumenotification' ) {
        my $volnote = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setNotifiVolume?notifivolume=$volnote";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'volumeringsound' ) {
        my $volring = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setRingSoundVolume?ringsoundvolume=$volring";
        $method = "POST";
    }
    
    elsif( lc $cmd =~ /^media/ ) {
        my $mplayer = join( " ", @args );

        $path   = "/fhem-amad/setCommands/multimediaControl?button=".$cmd."&mplayer=".$mplayer;
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'screenbrightness' ) {
        my $bri = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setBrightness?brightness=$bri";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'screen' ) {
        my $mod = join( " ", @args );


        $path        = AMADDevice_CreateScreenValue($hash,$mod);
        return "Please set \"setScreenlockPIN\" Attribut first"
        unless($path ne 'NO PIN');
        $method     = "POST";
    }
    
    elsif( lc $cmd eq 'screenorientation' ) {
    
        my $mod = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setScreenOrientation?orientation=$mod";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'activatevoiceinput' ) {
        $path   = "/fhem-amad/setCommands/setvoicecmd";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'screenfullscreen' ) {
        my $mod = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setScreenFullscreen?fullscreen=$mod";
        $method = "POST";
        readingsSingleUpdate( $hash, $cmd, $mod, 1 );
    }
    
    elsif( lc $cmd eq 'openurl' ) {
        my $openurl = join( " ", @args );
        my $browser = AttrVal( $name, "setOpenUrlBrowser", "com.android.chrome|com.google.android.apps.chrome.Main" );
        my @browserapp = split( /\|/, $browser );

        $path   = "/fhem-amad/setCommands/openURL?url=".$openurl."&browserapp=".$browserapp[0]."&browserappclass=".$browserapp[1];
        $method     = "POST";
    }
    
    elsif (lc $cmd eq 'nextalarmtime') {
        my $value   = join( " ", @args );
        my @alarm   = split( ":", $value );

        $path   = "/fhem-amad/setCommands/setAlarm?hour=".$alarm[0]."&minute=".$alarm[1];
        $method     = "POST";
    }
    
    elsif (lc $cmd eq 'timer') {
        my $timer   = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setTimer?minute=$timer";
        $method     = "POST";
    }

    elsif( lc $cmd eq 'statusrequest' ) {

       AMADDevice_statusRequest($hash);
       return;
    }

    elsif( lc $cmd eq 'openapp' ) {
        my $app = join( " ", @args );

        $path   = "/fhem-amad/setCommands/openApp?app=".$app;
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'nfc' ) {
        my $mod = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setnfc?nfc=".$mod;
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'system' ) {
        my $systemcmd   = join( " ", @args );

        $path   = "/fhem-amad/setCommands/systemcommand?syscmd=$systemcmd";
        $method         = "POST";
        readingsSingleUpdate( $hash, "airplanemode", "on", 1 ) if( $systemcmd eq "airplanemodeON" );
        readingsSingleUpdate( $hash, "deviceState", "offline", 1 ) if( $systemcmd eq "airplanemodeON" or $systemcmd eq "shutdown" );
    }
    
    elsif( lc $cmd eq 'donotdisturb' ) {
        my $disturbmod  = join( " ", @args );

        $path   = "/fhem-amad/setCommands/donotdisturb?disturbmod=$disturbmod";
        $method         = "POST";
    }
    
    elsif( lc $cmd eq 'bluetooth' ) {
        my $mod = join( " ", @args );

        $path   = "/fhem-amad/setCommands/setbluetooth?bluetooth=$mod";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'notifysndfile' ) {
        my $notify      = join( " ", @args );
        my $filepath    = AttrVal( $name, "setNotifySndFilePath", "/storage/emulated/0/Notifications/" );

        $path   = "/fhem-amad/setCommands/playnotifysnd?notifyfile=".$notify."&notifypath=".$filepath;
        $method         = "POST";
    }
    
    elsif( lc $cmd eq 'changetobtdevice' ) {
        my $swToBtDevice = join( " ", @args );    

        my ($swToBtMac,$btDeviceOne,$btDeviceTwo) = AMADDevice_CreateChangeBtDeviceValue($hash,$swToBtDevice);
        $path   = "/fhem-amad/setCommands/setbtdevice?swToBtDeviceMac=".$swToBtMac."&btDeviceOne=".$btDeviceOne."&btDeviceTwo=".$btDeviceTwo;
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'clearnotificationbar' ) {
        my $appname = join( " ", @args );

        $path   = "/fhem-amad/setCommands/clearnotificationbar?app=$appname";
        $method     = "POST";
    }
    
    elsif( lc $cmd eq 'vibrate' ) {

        $path   = "/fhem-amad/setCommands/setvibrate";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'showhomescreen' ) {

        $path   = "/fhem-amad/setCommands/showhomescreen";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'takepicture' ) {

        return "Please set \"setTakePictureResolution\" Attribut first"
        unless(AttrVal($name,'setTakePictureResolution','none') ne 'none');
        
        return "Please set \"setTakePictureCamera\" Attribut first"
        unless(AttrVal($name,'setTakePictureCamera','none') ne 'none');
        
        $path   = "/fhem-amad/setCommands/takepicture?pictureresolution=".AttrVal($name,'setTakePictureResolution','none')."&picturecamera=".AttrVal($name,'setTakePictureCamera','none');
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'takescreenshot' ) {

        return "Please set \"setTakeScreenshotResolution\" Attribut first"
        unless(AttrVal($name,'setTakeScreenshotResolution','none') ne 'none');
        
        $path   = "/fhem-amad/setCommands/takescreenshot?screenshotresolution=".AttrVal($name,'setTakeScreenshotResolution','none');
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'sendintent' ) {
        my $intentstring = join( " ", @args );
        my ( $action, $exkey1, $exval1, $exkey2, $exval2 ) = split( "[ \t][ \t]*", $intentstring );
        $exkey1 = "" if( !$exkey1 );
        $exval1 = "" if( !$exval1 );
        $exkey2 = "" if( !$exkey2 );
        $exval2 = "" if( !$exval2 );

        $path   = "/fhem-amad/setCommands/sendIntent?action=".$action."&exkey1=".$exkey1."&exval1=".$exval1."&exkey2=".$exkey2."&exval2=".$exval2;
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'installflowsource' ) {
        my $flowname    = join( " ", @args );

        $path   = "/fhem-amad/setCommands/installFlow?flowname=$flowname";
        $method         = "POST";
    }
    
    elsif( lc $cmd eq 'opencall' ) {
        my $string = join( " ", @args );
        my ($callnumber, $time) = split( "[ \t][ \t]*", $string );
        $time   = "none" if( !$time );

        $path   = "/fhem-amad/setCommands/openCall?callnumber=".$callnumber."&hanguptime=".$time;
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'closecall' ) {

        $path   = "/fhem-amad/setCommands/closeCall";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'startdaydream' ) {

        $path   = "/fhem-amad/setCommands/startDaydream";
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'currentflowsetupdate' ) {

        if( ReadingsVal($name,'flowsetVersionAtDevice','') lt '4.1.99.6' ) {
            $path   = "/fhem-amad/currentFlowsetUpdate";
        } else {
            $path   = "/fhem-amad/setCommands/currentFlowsetUpdate";
        }
        
        $method = "POST";
    }
    
    elsif( lc $cmd eq 'sendsms' ) {
        my $string = join( " ", @args );
        my ($smsmessage, $smsnumber) = split( "\\|", $string );
    
        $path   = "/fhem-amad/setCommands/sendSms?smsmessage=".urlEncode($smsmessage)."&smsnumber=".$smsnumber;
        $method = "POST";
        
    } else {
    
        my $apps = AttrVal( $name, "setOpenApp", "none" );
        my $btdev = AttrVal( $name, "setBluetoothDevice", "none" );
        

        my $list = '';
        foreach(@playerCmd) {
            $list .= $_ . ':' . join(',',@playerList) . ' ';
        }
        
        $list .= "screenMsg ttsMsg screenBrightness:slider,0,1,255 screen:on,off,lock,unlock openURL nextAlarmTime:time timer:slider,1,1,60 statusRequest:noArg bluetooth:on,off notifySndFile clearNotificationBar:All,Automagic activateVoiceInput:noArg vibrate:noArg sendIntent openCall closeCall:noArg currentFlowsetUpdate:noArg installFlowSource doNotDisturb:never,always,alarmClockOnly,onlyImportant userFlowState userFlowRun sendSMS startDaydream:noArg volumeUp:noArg volumeDown:noArg mute:on,off showHomeScreen:noArg takePicture:noArg takeScreenshot:noArg";

        $list .= " screenOrientation:auto,landscape,portrait"   if( AttrVal( $name, "setScreenOrientation", "0" ) eq "1" );
        $list .= " screenFullscreen:on,off"                     if( AttrVal( $name, "setFullscreen", "0" ) eq "1" );
        $list .= " openApp:$apps"                               if( AttrVal( $name, "setOpenApp", "none" ) ne "none" );
        $list .= " system:reboot,shutdown,airplanemodeON"       if( AttrVal( $name, "root", "0" ) eq "1" );
        $list .= " changetoBTDevice:$btdev"                     if( AttrVal( $name, "setBluetoothDevice", "none" ) ne "none" );
        $list .= " nfc:on,off"                                  if( AttrVal( $name, "root", "0" ) eq "1" );
        $list .= " volume:slider,0,1,$volMax";
        $list .= " volumeNotification:slider,0,1,$notifyVolMax";
        $list .= " volumeRingSound:slider,0,1,$ringSoundVolMax";
        


        return "Unknown argument $cmd, choose one of $list";
    }
    
    
    IOWrite($hash,$amad_id,$uri,$path,$header,$method);
    Log3 $name, 5, "AMADDevice ($name) - IOWrite: $uri $method IODevHash=$hash->{IODev}";

    return undef;
}

sub AMADDevice_Parse($$) {

    my ($io_hash,$json) = @_;
    my $name            = $io_hash->{NAME};


    my $decode_json     = eval{decode_json($json)};
    if($@){
        Log3 $name, 3, "AMADDevice ($name) - JSON error while request: $@";
        return;
    }
    
    Log3 $name, 4, "AMADDevice ($name) - ParseFn was called";
    Log3 $name, 5, "AMADDevice ($name) - ParseFn was called, !!! AMAD_ID: $decode_json->{amad}{amad_id}";


    my $fhemDevice  = $decode_json->{firstrun}{fhemdevice} if( defined($decode_json->{firstrun}) and defined($decode_json->{firstrun}{fhemdevice}) );
    my $amad_id     = $decode_json->{amad}{amad_id};
        
    if( my $hash        = $modules{AMADDevice}{defptr}{$amad_id} ) {        
        my $name        = $hash->{NAME};
                        
        AMADDevice_WriteReadings($hash,$decode_json);
        Log3 $name, 4, "AMADDevice ($name) - find logical device: $hash->{NAME}";
                        
        return $hash->{NAME};
            
    } else {

        return "UNDEFINED $fhemDevice AMADDevice $decode_json->{firstrun}{'amaddevice_ip'} $decode_json->{amad}{'amad_id'} $decode_json->{firstrun}{remoteserver}";
    }
}

##################################
##################################
#### my little helpers ###########

sub AMADDevice_checkDeviceState($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 4, "AMADDevice ($name) - AMADDevice_checkDeviceState: run Check";

    
    if( ReadingsAge( $name, ".deviceState", 240 ) > 240 ) {
    
        AMADDevice_statusRequest( $hash ) if( $hash->{helper}{deviceStateErrorCounter} == 0 );
        readingsSingleUpdate( $hash, "deviceState", "offline", 1 ) if( ReadingsAge( $name, ".deviceState", 300) > 300 and $hash->{helper}{deviceStateErrorCounter} > 0 and ReadingsVal($name,'deviceState','online') ne 'offline' );
        $hash->{helper}{deviceStateErrorCounter} = ( $hash->{helper}{deviceStateErrorCounter} + 1 );
    }
    
    InternalTimer( gettimeofday()+240, "AMADDevice_checkDeviceState", $hash, 0 );
    
    Log3 $name, 4, "AMADDevice ($name) - AMADDevice_checkDeviceState: set new Timer";
}

sub AMADDevice_encrypt($) {

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

sub AMADDevice_decrypt($) {

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

sub AMADDevice_CreateVolumeValue($$@) {

    my ($hash,$cmd,@args)       = @_;
    
    my $name                    = $hash->{NAME};
    my $vol;
    

    if( $cmd eq 'volume' ) {
        $vol = join( " ", @args );

        if( $vol =~ /^\+(.*)/ or $vol =~ /^-(.*)/ ) {

            if( $vol =~ /^\+(.*)/ ) {
                
                $vol =~ s/^\+//g;
                $vol = ReadingsVal( $name, "volume", 0 ) + $vol;
            }
                
            elsif( $vol =~ /^-(.*)/ ) {
                
                $vol =~ s/^-//g;
                $vol = ReadingsVal( $name, "volume", 15 ) - $vol;
            }
        }
            
    } elsif( $cmd eq 'mute') {
        if($args[0] eq 'on') {
            $vol = 0;
            readingsSingleUpdate($hash,'.volume',ReadingsVal($name,'volume',0),0);
        } else {
            $vol = ReadingsVal($name,'.volume',0);
        }
            
    } elsif( $cmd =~ 'volume[Down|Up]') {
        if( $cmd eq 'volumeUp' ) {
            $vol = ReadingsVal( $name, "volume", 0 ) + AttrVal($name,'setVolUpDownStep',3);
        } else {
            $vol = ReadingsVal( $name, "volume", 0 ) - AttrVal($name,'setVolUpDownStep',3);
        }
    }
        
    return $vol;
}

sub AMADDevice_CreateTtsMsgValue($@) {

    my ($hash,@args)       = @_;
    
    my $name        = $hash->{NAME};
    my $msg;
    my $speed;

    my $lang        = AttrVal( $name, "setTtsMsgLang","de" );
    my $ttsmsgvol   = AttrVal( $name, "setTtsMsgVol","none");
    
    if( AttrVal($name,"remoteServer","Automagic") ne 'Automagic') {
        $speed = AttrVal( $name, "setTtsMsgSpeed", "5" );
    } else {
        $speed = AttrVal( $name, "setTtsMsgSpeed", "1.0" );
    }


    $msg    = join( " ", @args );
    
    unless($args[0] ne '&en;' and $args[0] ne '&de;') {
        $lang   = substr(splice(@args,0,1),1,2);
        $msg    = join( " ", @args );
    }
        
    return ($msg,$speed,$lang,$ttsmsgvol);
}

sub AMADDevice_CreateScreenValue($$) {

    my ($hash,$mod)     = @_;

    my $name            = $hash->{NAME};
    my $scot            = AttrVal( $name, "setScreenOnForTimer", undef );
    $scot               = 60 if( !$scot );

    if ($mod eq "on" or $mod eq "off") {
        return ("/fhem-amad/setCommands/setScreenOnOff?screen=".$mod."&screenontime=".$scot);
    }

    elsif ($mod eq "lock" or $mod eq "unlock") {
        return "NO PIN"
        unless( AttrVal( $name, "setScreenlockPIN", "none" ) ne "none" );
        my $PIN = AttrVal( $name, "setScreenlockPIN", undef );
        $PIN = AMADDevice_decrypt($PIN);

        return ("/fhem-amad/setCommands/screenlock?lockmod=".$mod."&lockPIN=".$PIN);
    }
}

sub AMADDevice_CreateChangeBtDeviceValue($$) {

    my ($hash,$swToBtDevice)    = @_;

    my $name                    = $hash->{NAME};
    my @swToBtMac               = split( /\|/, $swToBtDevice );
    my $btDevices               = AttrVal( $name, "setBluetoothDevice", "none" ) if( AttrVal( $name, "setBluetoothDevice", "none" ) ne "none" );
    my @btDevice                = split( ',', $btDevices );
    my @btDeviceOne             = split( /\|/, $btDevice[0] );
    my @btDeviceTwo             = split( /\|/, $btDevice[1] );
    
    
    return($swToBtMac[1],$btDeviceOne[1],$btDeviceTwo[1]);
}





1;

=pod

=item device
=item summary    Integrates Android devices into FHEM and displays several settings.
=item summary_DE Integriert Android-Geräte in FHEM und zeigt verschiedene Einstellungen an.

=begin html

<a name="AMADDevice"></a>
<h3>AMADDevice</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u>
  <br>
  This module integrates Android devices into FHEM and displays several settings <b><u>using the Android app "Automagic" or "Tasker"</u></b>.
  Automagic is comparable to the "Tasker" app for automating tasks and configuration settings. But Automagic is more user-friendly. The "Automagic Premium" app currently costs EUR 2.90.
  <br>
  Any information retrievable by Automagic/Tasker can be displayed in FHEM by this module. Just define your own Automagic-"flow" or Tasker-"task" and send the data to the AMADCommBridge. One even can control several actions on Android devices.
  <br>
  To be able to make use of all these functions the Automagic/Tasker app and additional flows/Tasker-project need to be installed on the Android device. The flows/Tasker-project can be retrieved from the FHEM directory, the app can be bought in Google Play Store.
  <br><br>
  <b>How to use AMADDevice?</b>
  <ul>
    <li>first, make sure that the AMADCommBridge in FHEM was defined</li>
    <li><b>Using Automagic</b></li>
        <ul>
        <li>install the "Automagic Premium" app from the PlayStore</li>
        <li>install the flowset 74_AMADDeviceautomagicFlowset$VERSION.xml file from the $INSTALLFHEM/FHEM/lib/ directory on the Android device</li>
        <li>activate the "installation assistant" Flow in Automagic. If one now sends Automagic into the background, e.g. Homebutton, the assistant starts and creates automatically a FHEM device for the android device</li>
        </ul>
    <li><b>Using Tasker</b></li>
        <ul>
        <li>install the "Tasker" app from the PlayStore</li>
        <li>install the Tasker-project 74_AMADtaskerset_$VERSION.prj.xml file from the $INSTALLFHEM/FHEM/lib/ directory on the Android device</li>
        <li>run the "AMAD" task in Tasker and make your initial setup, by pressing the "create Device" button it will automatically create the device in FHEM</li>
        </ul>
  </ul>
  <br><br>
  <u><b>Define a AMADDevice device by hand.</b></u>
  <br><br>
  <a name="AMADDevicedefine"></a>
  <b>Define</b>
  <ul><br>
  10.6.9.10 1496497380000 IODev=AMADBridge
    <code>define &lt;name&gt; AMADDevice &lt;IP-ADRESSE&gt; &lt;AMAD_ID&gt; &lt;REMOTESERVER&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define WandTabletWohnzimmer AMADDevice 192.168.0.23 123456 Automagic</code><br>
    </ul>
    <br>
    In this case, an AMADDevice is created by hand. The AMAD_ID, here 123456, must also be entered exactly as a global variable in Automagic/Tasker.
  </ul>
  <br><br><br>
  <a name="AMADDevicereadings"></a>
  <b>Readings</b>
  <ul>
    <li>airplanemode - on/off, state of the aeroplane mode</li>
    <li>androidVersion - currently installed version of Android</li>
    <li>automagicState - state of the Automagic or Tasker App <b>(prerequisite Android >4.3). In case you have Android >4.3 and the reading says "not supported", you need to enable Automagic/Tasker inside Android / Settings / Sound & notification / Notification access</b></li>
    <li>batteryHealth - the health of the battery (1=unknown, 2=good, 3=overheat, 4=dead, 5=over voltage, 6=unspecified failure, 7=cold) (Automagic only)</li>
    <li>batterytemperature - the temperature of the battery (Automagic only)</li>
    <li>bluetooth - on/off, bluetooth state</li>
    <li>checkActiveTask - state of an app (needs to be defined beforehand). 0=not active or not active in foreground, 1=active in foreground, <b>see note below</b> (Automagic only)</li>
    <li>connectedBTdevices - list of all devices connected via bluetooth (Automagic only)</li>
    <li>connectedBTdevicesMAC - list of MAC addresses of all devices connected via bluetooth (Automagic only)</li>
    <li>currentMusicAlbum - currently playing album of mediaplayer (Automagic only)</li>
    <li>currentMusicApp - currently playing player app (Amazon Music, Google Play Music, Google Play Video, Spotify, YouTube, TuneIn Player, Aldi Life Music) (Automagic only)</li>
    <li>currentMusicArtist - currently playing artist of mediaplayer (Automagic only)</li>
    <li>currentMusicIcon - cover of currently play album <b>Not yet fully implemented</b> (Automagic only)</li>
    <li>currentMusicState - state of currently/last used mediaplayer (Automagic only)</li>
    <li>currentMusicTrack - currently playing song title of mediaplayer (Automagic only)</li>
    <li>daydream - on/off, daydream currently active</li>
    <li>deviceState - state of Android devices. unknown, online, offline.</li>
    <li>doNotDisturb - state of do not Disturb Mode</li>
    <li>dockingState - undocked/docked, Android device in docking station</li>
    <li>flow_SetCommands - active/inactive, state of SetCommands flow</li>
    <li>flow_informations - active/inactive, state of Informations flow</li>
    <li>flowsetVersionAtDevice - currently installed version of the flowsets on the Android device</li>
    <li>incomingCallerName - Callername from last Call</li>
    <li>incomingCallerNumber - Callernumber from last Call</li>
    <li>incomingWhatsAppMessage - last WhatsApp message</li>
    <li>incomingTelegramMessage - last telegram message</li>
    <li>incomingSmsMessage - last SMS message</li>
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
    <li>nfc - state of nfc service on/off</li>
    <li>nfcLastTagID - nfc_id of last scan nfc Tag / In order for the ID to be recognized correctly, the trigger NFC TagIDs must be processed in Flow NFC Tag Support and the TagId's Commase-separated must be entered. (Automagic only)</li>
    <li>powerLevel - state of battery in %</li>
    <li>powerPlugged - 0=no/1,2=yes, power supply connected</li>
    <li>screen - on locked,unlocked/off locked,unlocked, state of display</li>
    <li>screenBrightness - 0-255, level of screen-brightness</li>
    <li>screenFullscreen - on/off, full screen mode (Automagic only)</li>
    <li>screenOrientation - Landscape/Portrait, screen orientation (horizontal,vertical)</li>
    <li>screenOrientationMode - auto/manual, mode for screen orientation</li>
    <li>state - current state of AMAD device</li>
    <li>userFlowState - current state of a Flow, established under setUserFlowState Attribut (Automagic only)</li>
    <li>volume - media volume setting</li>
    <li>volumeNotification - notification volume setting</li>
    <li>wiredHeadsetPlugged - 0/1 headset plugged out or in</li>
    <br>
    Prerequisite for using the reading checkActivTask the package name of the application to be checked needs to be defined in the attribute <i>checkActiveTask</i>. Example: <i>attr Nexus10Wohnzimmer
    checkActiveTask com.android.chrome</i> f&uuml;r den Chrome Browser.
    <br><br>
  </ul>
  <br><br>
  <a name="AMADDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>activateVoiceInput - start voice input on Android device</li>
    <li>bluetooth - on/off, switch bluetooth on/off</li>
    <li>clearNotificationBar - All/Automagic, deletes all or only Automagic/Tasker notifications in status bar</li>
    <li>closeCall - hang up a running call</li>
    <li>currentFlowsetUpdate - start flowset/Tasker-project update on Android device</li>
    <li>installFlowSource - install a Automagic flow on device, <u>XML file must be stored in /tmp/ with extension xml</u>. <b>Example:</b> <i>set TabletWohnzimmer installFlowSource WlanUebwerwachen.xml</i> (Automagic only)</li>
    <li>doNotDisturb - sets the do not Disturb Mode, always Disturb, never Disturb, alarmClockOnly alarm Clock only, onlyImportant only important Disturbs</li>
    <li>mediaPlay - play command to media App</li>
    <li>mediaStop - stop command to media App</li>
    <li>mediaNext - skip Forward command to media App</li>
    <li>mediaBack - skip Backward to media App</li>
    <li>nextAlarmTime - sets the alarm time. Only valid for the next 24 hours.</li>
    <li>notifySndFile - plays a media-file <b>which by default needs to be stored in the folder "/storage/emulated/0/Notifications/" of the Android device. You may use the attribute setNotifySndFilePath for defining a different folder.</b></li>
    <li>openCall - initial a call and hang up after optional time / set DEVICE openCall 0176354 10 call this number and hang up after 10s</li>
    <li>screenBrightness - 0-255, set screen brighness</li>
    <li>screenMsg - display message on screen of Android device</li>
    <li>sendintent - send intent string <u>Example:</u><i> set $AMADDEVICE sendIntent org.smblott.intentradio.PLAY url http://stream.klassikradio.de/live/mp3-192/stream.klassikradio.de/play.m3u name Klassikradio</i>, first parameter contains the action, second parameter contains the extra. At most two extras can be used.</li>
    <li>sendSMS - Sends an SMS to a specific phone number. Bsp.: sendSMS Dies ist ein Test|555487263</li>
    <li>startDaydream - start Daydream</li>
    <li>statusRequest - Get a new status report of Android device. Not all readings can be updated using a statusRequest as some readings are only updated if the value of the reading changes.</li>
    <li>timer - set a countdown timer in the "Clock" stock app. Only minutes are allowed as parameter.</li>
    <li>ttsMsg - send a message which will be played as voice message (to change laguage temporary set first character &en; or &de;)</li>
    <li>userFlowState - set Flow/Tasker-profile active or inactive,<b><i>set Nexus7Wohnzimmer Badezimmer:inactive vorheizen</i> or <i>set Nexus7Wohnzimmer Badezimmer vorheizen,Nachtlicht Steven:inactive</i></b></li>
    <li>userFlowRun - executes the specified flow/task</li>
    <li>vibrate - vibrate Android device</li>
    <li>volume - set media volume. Works on internal speaker or, if connected, bluetooth speaker or speaker connected via stereo jack</li>
    <li>volumeNotification - set notifications volume</li>
  </ul>
  <br>
  <b>Set (depending on attribute values)</b>
  <ul>
    <li>changetoBtDevice - switch to another bluetooth device. <b>Attribute setBluetoothDevice needs to be set. See note below!</b> (Automagic only)</li>
    <li>nfc - activate or deactivate the nfc Modul on/off. <b>attribute root</b></li>
    <li>openApp - start an app. <b>attribute setOpenApp</b></li>
    <li>openURL - opens a URLS in the standard browser as long as no other browser is set by the <b>attribute setOpenUrlBrowser</b>.<b>Example:</b><i> attr Tablet setOpenUrlBrowser de.ozerov.fully|de.ozerov.fully.MainActivity, first parameter: package name, second parameter: Class Name</i></li>
    <li>screen - on/off/lock/unlock, switch screen on/off or lock/unlock screen. In Automagic "Preferences" the "Device admin functions" need to be enabled, otherwise "Screen off" does not work. <b>attribute setScreenOnForTimer</b> changes the time the display remains switched on! (Tasker supports only "off" command)</li>
    <li>screenFullscreen - on/off, activates/deactivates full screen mode. <b>attribute setFullscreen</b> (Automagic only)</li>
    <li>screenLock - Locks screen with request for PIN. <b>attribute setScreenlockPIN - enter PIN here. Only use numbers, 4-16 numbers required.</b> (Automagic only)</li>
    <li>screenOrientation - Auto,Landscape,Portait, set screen orientation (automatic, horizontal, vertical). <b>attribute setScreenOrientation</b></li>
    <li>system - issue system command (only with rooted Android devices). reboot,shutdown,airplanemodeON (can only be switched ON) <b>attribute root</b>, in Automagic "Preferences" "Root functions" need to be enabled.</li>
    <li>takePicture - take a camera picture <b>Attribut setTakePictureResolution</b></li>
    <li>takeScreenshot - take a Screenshot picture <b>Attribut setTakeScreenshotResolution</b></li>
  </ul>
  <br><br>
  <a name="AMADDeviceattribut"></a>
  <b>Attribut</b>
  <ul>
    <li>setAPSSID - set WLAN AccesPoint SSID to prevent WLAN sleeps (Automagic only)</li>
    <li>setNotifySndFilePath - set systempath to notifyfile (default /storage/emulated/0/Notifications/</li>
    <li>setTtsMsgSpeed - set speaking speed for TTS (For Automagic: Value between 0.5 - 4.0, 0.5 Step, default: 1.0)(For Tasker: Value between 1 - 10, 1 Step, default: 5)</li>
    <li>setTtsMsgLang - set speaking language for TTS, de or en (default is de)</li>
    <li>setTtsMsgVol - is set, change automatically the media audio end set it back</li>
    <li>set setTakePictureResolution - set the camera resolution for takePicture action (800x600,1024x768,1280x720,1600x1200,1920x1080)</li>
    <li>setTakePictureCamera - which camera do you use (Back,Front).</li>
    <br>
    To be able to use "openApp" the corresponding attribute "setOpenApp" needs to contain the app package name.
    <br><br>
    To be able to switch between bluetooth devices the attribute "setBluetoothDevice" needs to contain (a list of) bluetooth devices defined as follows: <b>attr &lt;DEVICE&gt; BTdeviceName1|MAC,BTDeviceName2|MAC</b> No spaces are allowed in any BTdeviceName. Defining MAC please make sure to use the character : (colon) after each  second digit/character.<br>
    Example: <i>attr Nexus10Wohnzimmer setBluetoothDevice Logitech_BT_Adapter|AB:12:CD:34:EF:32,Anker_A3565|GH:56:IJ:78:KL:76</i> 
  </ul>
  <br><br>
  <a name="AMADDevicestate"></a>
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

<a name="AMADDevice"></a>
<h3>AMADDevice</h3>
<ul>
  <u><b>AMADDevice - Automagic Android Device</b></u>
  <br>
  Dieses Modul liefert, <b><u>in Verbindung mit der Android APP Automagic oder Tasker</u></b>, diverse Informationen von Android Ger&auml;ten.
  Die Android APP Automagic (welche nicht von mir stammt und 2.90 Euro kostet) funktioniert wie Tasker, ist aber bei weitem User freundlicher.
  <br>
  Mit etwas Einarbeitung k&ouml;nnen jegliche Informationen welche Automagic/Tasker bereit stellt in FHEM angezeigt werden. Hierzu bedarf es lediglich eines eigenen Flows/Task welcher seine Daten an die AMADDeviceCommBridge sendet. Das Modul gibt auch die M&ouml;glichkeit Androidger&auml;te zu steuern.
  <br>
  F&uuml;r all diese Aktionen und Informationen wird auf dem Androidger&auml;t "Automagic/Tasker" und ein so genannter Flow/Task ben&ouml;tigt. Die App ist &uuml;ber den Google PlayStore zu beziehen. Das ben&ouml;tigte Flowset/Tasker-Projekt bekommt man aus dem FHEM Verzeichnis.
  <br><br>
  <b>Wie genau verwendet man nun AMADDevice?</b>
  <ul>
    <li>stelle sicher das als aller erstes die AMADCommBridge in FHEM definiert wurde</li>
    <li><b>Bei verwendung von Automagic</b></li>
        <ul>
        <li>installiere die App "Automagic Premium" aus dem PlayStore.</li>
        <li>installiere das Flowset 74_AMADDeviceautomagicFlowset$VERSION.xml aus dem Ordner $INSTALLFHEM/FHEM/lib/ auf dem Androidger&auml;t</li>
        <li>aktiviere den Installationsassistanten Flow in Automagic. Wenn man nun Automagic in den Hintergrund schickt, z.B. Hometaste dr&uuml;cken, startet der Assistant und legt automatisch ein Device für das Androidger&auml;t an.</li>
        </ul>
    <li><b>Bei verwendung von Tasker</b></li>
        <ul>
        <li>installiere die App "Tasker" aus dem PlayStore.</li>
        <li>installiere das Tasker Projekt 74_AMADtaskerset_$VERSION.prj.xml aus dem Ordner $INSTALLFHEM/FHEM/lib/ auf dem Androidger&auml;t</li>
        <li>Starte den Task "AMAD", es erscheint eine Eingabemaske in der alle Einstellungen vorgenommen werden k&ouml;nnen, durch einen Klick auf "create Device" wird das Ger&auml;t in FHEM erstellt.</li>
        </ul>
  </ul>
  <br><br>
  <u><b>Ein AMADDevice Ger&auml;t von Hand anlegen.</b></u>
  <br><br>
  <a name="AMADDevicedefine"></a>
  <b>Define</b>
  <ul><br>
  10.6.9.10 1496497380000 IODev=AMADBridge
    <code>define &lt;name&gt; AMADDevice &lt;IP-ADRESSE&gt; &lt;AMAD_ID&gt; &lt;REMOTESERVER&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define WandTabletWohnzimmer AMADDevice 192.168.0.23 123456 Automagic</code><br>
    </ul>
    <br>
    In diesem Fall wird ein AMADDevice von Hand angelegt. Die AMAD_ID, hier 123456, mu&szlig; auch exakt so als globale Variable in Automagic/Tasker eingetragen sein.
  </ul>
  <br><br><br>
  <a name="AMADDevicereadings"></a>
  <b>Readings</b>
  <ul>
    <li>airplanemode - Status des Flugmodus</li>
    <li>androidVersion - aktuell installierte Androidversion</li>
    <li>automagicState - Statusmeldungen von der Automagic oder Tasker App <b>(Voraussetzung Android >4.3). Ist Android gr&ouml;&szlig;er 4.3 vorhanden und im Reading steht "wird nicht unterst&uuml;tzt", mu&szlig; in den Androideinstellungen unter Ton und Benachrichtigungen -> Benachrichtigungszugriff ein Haken f&uuml;r Automagic/Tasker gesetzt werden</b></li>
    <li>batteryHealth - Zustand der Battery (1=unbekannt, 2=gut, 3=&Uuml;berhitzt, 4=tot, 5=&Uuml;berspannung, 6=unbekannter Fehler, 7=kalt) (nur Automagic)</li>
    <li>batterytemperature - Temperatur der Batterie (nur Automagic)</li>
    <li>bluetooth - on/off, Bluetooth Status an oder aus</li>
    <li>checkActiveTask - Zustand einer zuvor definierten APP. 0=nicht aktiv oder nicht aktiv im Vordergrund, 1=aktiv im Vordergrund, <b>siehe Hinweis unten</b> (nur Automagic)</li>
    <li>connectedBTdevices - eine Liste der verbundenen Ger&auml;t (nur Automagic)</li>
    <li>connectedBTdevicesMAC - eine Liste der MAC Adressen aller verbundender BT Ger&auml;te (nur Automagic)</li>
    <li>currentMusicAlbum - aktuell abgespieltes Musikalbum des verwendeten Mediaplayers (nur Automagic)</li>
    <li>currentMusicApp - aktuell verwendeter Mediaplayer (Amazon Music, Google Play Music, Google Play Video, Spotify, YouTube, TuneIn Player, Aldi Life Music) (nur Automagic)</li>
    <li>currentMusicArtist - aktuell abgespielter Musikinterpret des verwendeten Mediaplayers (nur Automagic)</li>
    <li>currentMusicIcon - Cover vom aktuell abgespielten Album <b>Noch nicht fertig implementiert</b> (nur Automagic)</li>
    <li>currentMusicState - Status des aktuellen/zuletzt verwendeten Mediaplayers (nur Automagic)</li>
    <li>currentMusicTrack - aktuell abgespielter Musiktitel des verwendeten Mediaplayers (nur Automagic)</li>
    <li>daydream - on/off, Daydream gestartet oder nicht</li>
    <li>deviceState - Status des Androidger&auml;tes. unknown, online, offline.</li>
    <li>doNotDisturb - aktueller Status des nicht st&ouml;ren Modus</li>
    <li>dockingState - undocked/docked Status ob sich das Ger&auml;t in einer Dockinstation befindet.</li>
    <li>flow_SetCommands - active/inactive, Status des SetCommands Flow</li>
    <li>flow_informations - active/inactive, Status des Informations Flow</li>
    <li>flowsetVersionAtDevice - aktuell installierte Flowsetversion auf dem Device</li>
    <li>incomingCallerName - Anrufername des eingehenden Anrufes</li>
    <li>incomingCallerNumber - Anrufernummer des eingehenden Anrufes</li>
    <li>incomingWhatsAppMessage - letzte WhatsApp Nachricht</li>
    <li>incomingTelegramMessage - letzte Telegram Nachricht</li>
    <li>incomingSmsMessage - letzte SMS Nachricht</li>
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
    <li>nfc - Status des NFC on/off</li>
    <li>nfcLastTagID - nfc_id des zu letzt gescannten Tag's / Damit die ID korrekt erkannt wird muss im Flow NFC Tag Support der Trigger NFC TagIDs bearbeitet werden und die TagId's Kommasepariert eingetragen werden. (nur Automagic)</li>
    <li>powerLevel - Status der Batterie in %</li>
    <li>powerPlugged - Netzteil angeschlossen? 0=NEIN, 1|2=JA</li>
    <li>screen - on locked/unlocked, off locked/unlocked gibt an ob der Bildschirm an oder aus ist und gleichzeitig gesperrt oder nicht gesperrt</li>
    <li>screenBrightness - Bildschirmhelligkeit von 0-255</li>
    <li>screenFullscreen - on/off, Vollbildmodus (An,Aus) (nur Automagic)</li>
    <li>screenOrientation - Landscape,Portrait, Bildschirmausrichtung (Horizontal,Vertikal)</li>
    <li>screenOrientationMode - auto/manual, Modus f&uuml;r die Ausrichtung (Automatisch, Manuell)</li>
    <li>state - aktueller Status</li>
    <li>userFlowState - aktueller Status eines Flows, festgelegt unter dem setUserFlowState Attribut (nur Automagic)</li>
    <li>volume - Media Lautst&auml;rkewert</li>
    <li>volumeNotification - Benachrichtigungs Lautst&auml;rke</li>
    <li>wiredHeadsetPlugged - 0/1 gibt an ob ein Headset eingesteckt ist oder nicht</li>
    <br>
    Beim Reading checkActivTask mu&szlig; zuvor der Packagename der zu pr&uuml;fenden App als Attribut <i>checkActiveTask</i> angegeben werden. Beispiel: <i>attr Nexus10Wohnzimmer
    checkActiveTask com.android.chrome</i> f&uuml;r den Chrome Browser.
    <br><br>
  </ul>
  <br><br>
  <a name="AMADDeviceset"></a>
  <b>Set</b>
  <ul>
    <li>activateVoiceInput - aktiviert die Spracheingabe</li>
    <li>bluetooth - on/off, aktiviert/deaktiviert Bluetooth</li>
    <li>clearNotificationBar - All,Automagic, l&ouml;scht alle Meldungen oder nur die Automagic/Tasker Meldungen in der Statusleiste</li>
    <li>closeCall - beendet einen laufenden Anruf</li>
    <li>currentFlowsetUpdate - f&uuml;rt ein Flowset/Tasker-Projekt update auf dem Device durch</li>
    <li>doNotDisturb - schaltet den nicht st&ouml;ren Modus, always immer st&ouml;ren, never niemals st&ouml;ren, alarmClockOnly nur Wecker darf st&ouml;ren, onlyImportant nur wichtige St&ouml;rungen</li>
    <li>installFlowSource - installiert einen Flow auf dem Device, <u>das XML File muss unter /tmp/ liegen und die Endung xml haben</u>. <b>Bsp:</b> <i>set TabletWohnzimmer installFlowSource WlanUebwerwachen.xml</i> (nur Automagic)</li>
    <li>mediaPlay - play Befehl zur Media App</li>
    <li>mediaStop - stop Befehl zur Media App</li>
    <li>mediaNext - nächster Titel Befehl zur Media App</li>
    <li>mediaBack - vorheriger Titel zur Media App</li>
    <li>nextAlarmTime - setzt die Alarmzeit. gilt aber nur innerhalb der n&auml;chsten 24Std.</li>
    <li>openCall - ruft eine Nummer an und legt optional nach X Sekunden auf / set DEVICE openCall 01736458 10 / ruft die Nummer an und beendet den Anruf nach 10s</li>
    <li>screenBrightness - setzt die Bildschirmhelligkeit, von 0-255.</li>
    <li>screenMsg - versendet eine Bildschirmnachricht</li>
    <li>sendintent - sendet einen Intentstring <u>Bsp:</u><i> set $AMADDeviceDEVICE sendIntent org.smblott.intentradio.PLAY url http://stream.klassikradio.de/live/mp3-192/stream.klassikradio.de/play.m3u name Klassikradio</i>, der erste Befehl ist die Aktion und der zweite das Extra. Es k&ouml;nnen immer zwei Extras mitgegeben werden.</li>
    <li>sendSMS - sendet eine SMS an eine bestimmte Telefonnummer. Bsp.: sendSMS Dies ist ein Test|555487263</li>
    <li>startDaydream - startet den Daydream</li>
    <li>statusRequest - Fordert einen neuen Statusreport beim Device an. Es k&ouml;nnen nicht von allen Readings per statusRequest die Daten geholt werden. Einige wenige geben nur bei Status&auml;nderung ihren Status wieder.</li>
    <li>timer - setzt einen Timer innerhalb der als Standard definierten ClockAPP auf dem Device. Es k&ouml;nnen nur Minuten angegeben werden.</li>
    <li>ttsMsg - versendet eine Nachricht welche als Sprachnachricht ausgegeben wird (um die Sprache für diese eine Durchsage zu ändern setze vor Deinem eigentlichen Text &en; oder &de;)</li>
    <li>userFlowState - aktiviert oder deaktiviert einen oder mehrere Flows/Tasker-Profile,<b><i>set Nexus7Wohnzimmer Badezimmer vorheizen:inactive</i> oder <i>set Nexus7Wohnzimmer Badezimmer vorheizen,Nachtlicht Steven:inactive</i></b></li>
    <li>userFlowRun - führt den angegebenen Flow/Task aus</li>
    <li>vibrate - l&auml;sst das Androidger&auml;t vibrieren</li>
    <li>volume - setzt die Medialautst&auml;rke. Entweder die internen Lautsprecher oder sofern angeschlossen die Bluetoothlautsprecher und per Klinkenstecker angeschlossene Lautsprecher, + oder - vor dem Wert reduziert die aktuelle Lautst&auml;rke um den Wert. Der maximale Sliderwert kann &uuml;ber das Attribut setVolMax geregelt werden.</li>
    <li>volumeUp - erh&ouml;ht die Lautst&auml;rke um den angegeben Wert im entsprechenden Attribut. Ist kein Attribut angegeben wird per default 2 genommen.</li>
    <li>volumeDown - reduziert die Lautst&auml;rke um den angegeben Wert im entsprechenden Attribut. Ist kein Attribut angegeben wird per default 2 genommen.</li>
    <li>volumeNotification - setzt die Benachrichtigungslautst&auml;rke.</li>
  </ul>
  <br>
  <b>Set abh&auml;ngig von gesetzten Attributen</b>
  <ul>
    <li>changetoBtDevice - wechselt zu einem anderen Bluetooth Ger&auml;t. <b>Attribut setBluetoothDevice mu&szlig; gesetzt sein. Siehe Hinweis unten!</b> (nur Automagic)</li>
    <li>notifySndFile - spielt die angegebene Mediadatei auf dem Androidger&auml;t ab. <b>Die aufzurufende Mediadatei sollte sich im Ordner /storage/emulated/0/Notifications/ befinden. Ist dies nicht der Fall kann man &uuml;ber das Attribut setNotifySndFilePath einen Pfad vorgeben.</b></li>
    <li>nfc -  schaltet nfc an oder aus /on/off<b>Attribut root</b></li>
    <li>openApp - &ouml;ffnet eine ausgew&auml;hlte App. <b>Attribut setOpenApp</b></li>
    <li>openURL - &ouml;ffnet eine URL im Standardbrowser, sofern kein anderer Browser &uuml;ber das <b>Attribut setOpenUrlBrowser</b> ausgew&auml;hlt wurde.<b> Bsp:</b><i> attr Tablet setOpenUrlBrowser de.ozerov.fully|de.ozerov.fully.MainActivity, das erste ist der Package Name und das zweite der Class Name</i></li>
    <li>screen - on/off/lock/unlock schaltet den Bildschirm ein/aus oder sperrt/entsperrt ihn, in den Automagic Einstellungen muss "Admin Funktion" gesetzt werden sonst funktioniert "Screen off" nicht. <b>Attribut setScreenOnForTimer</b> &auml;ndert die Zeit wie lange das Display an bleiben soll! (Tasker unterst&uuml;tzt nur "screen off")</li>
    <li>screenFullscreen - on/off, (aktiviert/deaktiviert) den Vollbildmodus. <b>Attribut setFullscreen</b></li>
    <li>screenLock - Sperrt den Bildschirm mit Pinabfrage. <b>Attribut setScreenlockPIN - hier die Pin daf&uuml;r eingeben. Erlaubt sind nur Zahlen. Es m&uuml;&szlig;en mindestens 4, bis max 16 Zeichen verwendet werden.</b></li>
    <li>screenOrientation - Auto,Landscape,Portait, aktiviert die Bildschirmausrichtung (Automatisch,Horizontal,Vertikal). <b>Attribut setScreenOrientation</b> (Tasker unterst&uuml;tzt nur Auto on/off)</li>
    <li>system - setzt Systembefehle ab (nur bei gerootetet Ger&auml;en). reboot,shutdown,airplanemodeON (kann nur aktiviert werden) <b>Attribut root</b>, in den Automagic Einstellungen muss "Root Funktion" gesetzt werden</li>
    <li>takePicture - löst die Kamera aus für ein Foto <b>Attribut setTakePictureResolution</b></li>
    <li>takeScreenshot - macht ein Screenshot <b>Attribut setTakeScreenshotResolution</b></li>
  </ul>
  <br><br>
  <a name="AMADDeviceattribute"></a>
  <b>Attribute</b>
  <ul>
    <li>setNotifySndFilePath - setzt den korrekten Systempfad zur Notifydatei (default ist /storage/emulated/0/Notifications/</li>
    <li>setTtsMsgSpeed - setzt die Sprachgeschwindigkeit bei der Sprachausgabe(Für Automagic: Werte zwischen 0.5 bis 4.0 in 0.5er Schritten, default:1.0)(Für Tasker: Werte zwischen 1 bis 10 in 1er Schritten, default:5)</li>
    <li>setTtsMsgLang - setzt die Sprache bei der Sprachausgabe, de oder en (default ist de)</li>
    <li>setTtsMsgVol - wenn gesetzt wird der Wert als neues Media Volume f&uuml; die Sprachansage verwendet und danach wieder der alte Wert eingestellt</li>
    <li>setVolUpDownStep - setzt den Step f&uuml;r volumeUp und volumeDown</li>
    <li>setVolMax - setzt die maximale Volume Gr&uoml;e f&uuml;r den Slider</li>
    <li>setNotifyVolMax - setzt den maximalen Lautst&auml;rkewert für Benachrichtigungslautst&auml;rke f&uuml;r den Slider</li>
    <li>setRingSoundVolMax - setzt den maximalen Lautst&auml;rkewert für Klingellautst&auml;rke f&uuml;r den Slider</li>
    <li>setAPSSID - setzt die AccessPoint SSID um ein WLAN sleep zu verhindern (nur Automagic)</li>
    <li>setTakePictureResolution - welche Kameraauflösung soll verwendet werden? (800x600,1024x768,1280x720,1600x1200,1920x1080)</li>
    <li>setTakePictureCamera - welche Kamera soll verwendet werden (Back,Front).</li>
    <br>
    Um openApp verwenden zu k&ouml;nnen, muss als Attribut der Package Name der App angegeben werden.
    <br><br>
    Um zwischen Bluetoothger&auml;ten wechseln zu k&ouml;nnen, mu&szlig; das Attribut setBluetoothDevice mit folgender Syntax gesetzt werden. <b>attr &lt;DEVICE&gt; BTdeviceName1|MAC,BTDeviceName2|MAC</b> Es muss
    zwingend darauf geachtet werden das beim BTdeviceName kein Leerzeichen vorhanden ist. Am besten zusammen oder mit Unterstrich. Achtet bei der MAC darauf das Ihr wirklich nach jeder zweiten Zahl auch
    einen : drin habt<br>
    Beispiel: <i>attr Nexus10Wohnzimmer setBluetoothDevice Logitech_BT_Adapter|AB:12:CD:34:EF:32,Anker_A3565|GH:56:IJ:78:KL:76</i> 
  </ul>
  <br><br>
  <a name="AMADDevicestate"></a>
  <b>state</b>
  <ul>
    <li>initialized - Ist der Status kurz nach einem define.</li>
    <li>active - die Ger&auml;teinstanz ist im aktiven Status.</li>
    <li>disabled - die Ger&auml;teinstanz wurde &uuml;ber das Attribut disable deaktiviert</li>
  </ul>
  <br><br><br>
  <u><b>Anwendungsbeispiele:</b></u>
  <ul><br>
    <a href="http://www.fhemwiki.de/wiki/AMADDevice#Anwendungsbeispiele">Hier verweise ich auf den gut gepflegten Wikieintrag</a>
  </ul>
  <br><br><br>
</ul>

=end html_DE
=cut

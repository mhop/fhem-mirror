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
###### Möglicher Aufbau eines JSON Strings für die AMADCommBridge
#
#  first initial String
#   {"amad": {"amad_id": "1495827100156","fhemcmd": "setreading"},"firstrun": {"fhemdevice": "TabletWohnzimmer","fhemserverip": "fhem02.tuxnet.local","amaddevice_ip": "10.6.9.35"}}
#   {"amad": {"amad_id": "1495827100156","fhemcmd": "setreading"},"firstrun": {"fhemdevice": "TabletWohnzimmer","fhemserverip": "fhem02.tuxnet.local","amaddevice_ip": "10.6.9.35"}}
#
#  default String
#   {"amad": {"amad_id": "37836534","fhemcmd": "setreading"},"payload": {"reading0": "value0","reading1": "value1","readingX": "valueX"}}
#   Aufruf zum testens
#   curl --data '{"amad": {"amad_id": "37836534","fhemcmd": "setreading"},"payload": {"reading0": "value0","reading1": "value1","readingX": "valueX"}}' localhost:8090
#
#
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
use TcpServerUtils;

eval "use Encode qw(encode encode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";



my $modulversion = "4.2.2";
my $flowsetversion = "4.2.3";




# Declare functions
sub AMADCommBridge_Attr(@);
sub AMADCommBridge_Open($);
sub AMADCommBridge_Read($);
sub AMADCommBridge_Define($$);
sub AMADCommBridge_Initialize($);
sub AMADCommBridge_Set($@);
sub AMADCommBridge_Write($@);
sub AMADCommBridge_Undef($$);
sub AMADCommBridge_ResponseProcessing($$);
sub AMADCommBridge_Close($);
sub AMADCommBridge_ErrorHandling($$$);
sub AMADCommBridge_ProcessRead($$);
sub AMADCommBridge_ParseMsg($$);




sub AMADCommBridge_Initialize($) {

    my ($hash) = @_;

    
    # Provider
    $hash->{ReadFn}     = "AMADCommBridge_Read";
    $hash->{WriteFn}    = "AMADCommBridge_Write";
    $hash->{Clients}    = ":AMADDevice:";
    $hash->{MatchList}  = { "1:AMADDevice"      => '{"amad": \{"amad_id":.+}}' };
    
    
    # Consumer
    $hash->{SetFn}      = "AMADCommBridge_Set";
    $hash->{DefFn}      = "AMADCommBridge_Define";
    $hash->{UndefFn}    = "AMADCommBridge_Undef";
    
    $hash->{AttrFn}     = "AMADCommBridge_Attr";
    $hash->{AttrList}   = "fhemControlMode:trigger,setControl,thirdPartControl ".
                          "debugJSON:0,1 ".
                          "enableSubCalls:0,1 ".
                          "disable:1 ".
                          "allowfrom ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{AMADCommBridge}{defptr}}) {
    
        my $hash = $modules{AMADCommBridge}{defptr}{$d};
        $hash->{VERSIONMODUL}      = $modulversion;
        $hash->{VERSIONFLOWSET}    = $flowsetversion;
    }
}

sub AMADCommBridge_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <name> AMADCommBridge '<tcp-port>'" if( @a < 2 and @a > 3 );
    return "Cannot define a AMADCommBridge device. Perl modul $missingModul is missing." if ( $missingModul );
    
    my $name                = $a[0];
    
    my $port;
    $port                   = $a[2] if($a[2]);
    $port                   = 8090 if( not defined($port) and (!$port) );
    
    $hash->{BRIDGE}         = 1;
    $hash->{PORT}           = $port;
    $hash->{VERSIONMODUL}   = $modulversion;
    $hash->{VERSIONFLOWSET} = $flowsetversion;


    CommandAttr(undef,"$name room AMAD") if(AttrVal($name,'room','none') eq 'none');
    
    Log3 $name, 3, "AMADCommBridge ($name) - defined AMADCommBridge with Socketport $port";

    AMADCommBridge_Open( $hash );
    
    $modules{AMADCommBridge}{defptr}{BRIDGE} = $hash;

    return undef;
}

sub AMADCommBridge_Undef($$) {

    my ( $hash, $arg ) = @_;


    delete $modules{AMADCommBridge}{defptr}{BRIDGE} if( defined($modules{AMADCommBridge}{defptr}{BRIDGE}) and $hash->{BRIDGE} );
    TcpServer_Close( $hash );

    return undef;
}

sub AMADCommBridge_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    if( $attrName eq "disable" ) {
        if( $cmd eq "set" ) {
            if( $attrVal eq "0" ) {
            
                readingsSingleUpdate ( $hash, "state", "enabled", 1 );
                AMADCommBridge_Open($hash);
                Log3 $name, 3, "AMADCommBridge ($name) - enabled";
            } else {

                AMADCommBridge_Close($hash);
                readingsSingleUpdate ( $hash, "state", "disabled", 1 ) if( not defined($hash->{FD}) );
                Log3 $name, 3, "AMADCommBridge ($name) - disabled";
            }
            
        } else {

            readingsSingleUpdate ( $hash, "state", "enabled", 1 );
            AMADCommBridge_Open($hash);
            Log3 $name, 3, "AMADCommBridge ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "fhemControlMode" ) {
        if( $cmd eq "set" ) {
        
            CommandSet(undef,'set TYPE=AMADDevice:FILTER=deviceState=online statusRequest');
            Log3 $name, 3, "AMADCommBridge ($name) - set fhemControlMode global Variable at Device";
            
        } else {

            CommandSet(undef,'set TYPE=AMADDevice:FILTER=deviceState=online statusRequest');
            Log3 $name, 3, "AMADCommBridge ($name) - set fhemControlMode global Variable NONE at Device";
        }
    }
    
    return undef;
}

sub AMADCommBridge_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;
    
    
    if( $cmd eq 'open' ) {
    
        AMADCommBridge_Open($hash);
    
    } elsif( $cmd eq 'close' ) {
    
        AMADCommBridge_Close($hash);
        
    } elsif( $cmd eq 'fhemServerIP' ) {
    
        readingsSingleUpdate($hash,$cmd,$arg,1);
    
    } else {
        my $list = "open:noArg close:noArg fhemServerIP";
        return "Unknown argument $cmd, choose one of $list";
    }
}

sub AMADCommBridge_Write($@) {

    my ($hash,$amad_id,$uri,$path,$header,$method)    = @_;
    my $name                                    = $hash->{NAME};
    my $dhash                                   = $modules{AMADDevice}{defptr}{$amad_id};
    my $param;
    my $remoteServer                            = AttrVal($dhash->{NAME},'remoteServer','Automagic');


    Log3 $name, 4, "AMADCommBridge ($name) - AMADCommBridge_Write Path: $path";
    
    
    if($remoteServer ne 'Automagic' and $path =~ /\?/) {
        $path .= "&amad_id=$amad_id";
    } elsif($remoteServer ne 'Automagic') {
        $path .= "?amad_id=$amad_id";
    }

    return readingsSingleUpdate($dhash,'lastSetCommand',$path,1)
    if( $remoteServer eq 'other' );

    $param = { url => "http://" . $uri . $path, timeout => 15, hash => $hash, amad_id => $amad_id, method => $method, header => $header . "\r\namadid: $amad_id", doTrigger => 1, callback => \&AMADCommBridge_ErrorHandling } if($remoteServer eq 'Automagic');


    $param =    {   url => "http://" . $uri . "/",
                    data => "{\"message\":\"AMAD=:=$path\", \"sender\":\"AMAD\", \"ttl\":60, \"communication_base_params\":{\"type\":\"Message\", \"fallback\":false, \"via\":\"Wifi\"},\"version\":\"1.62\"}",
                    timeout => 15, hash => $hash, amad_id => $amad_id, method => $method,
                    header => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
                    doTrigger => 1, callback => \&AMADCommBridge_ErrorHandling 
                } if($remoteServer eq 'Autoremote');


    $param =    {   url => "http://" . $uri . "/",
                    data => "device=AMAD&cmd=".urlEncode($path),
                    timeout => 15, hash => $hash, amad_id => $amad_id, method => $method,
                    header => "agent: TeleHeater/2.2.3\r\nUser-Agent: TeleHeater/2.2.3\r\nAccept: application/json",
                    doTrigger => 1, callback => \&AMADCommBridge_ErrorHandling 
                } if($remoteServer eq 'TNES');



    my $logtext = "AMADCommBridge ($name) - Send with remoteServer: $remoteServer URL: $param->{url}, HEADER: $param->{header}, METHOD: $method";
        $logtext .= ", DATA: $param->{data}" if( $remoteServer ne 'Automagic' );
    Log3 $name, 5, "$logtext";
    

    HttpUtils_NonblockingGet($param) if( defined($param) );
}

sub AMADCommBridge_ErrorHandling($$$) {

    my ($param,$err,$data)    = @_;
    
    my $hash                        = $param->{hash};
    my $dhash                       = $modules{AMADDevice}{defptr}{$param->{'amad_id'}};
    my $dname                       = $dhash->{NAME};


    
    
    if( $param->{method} eq 'GET' ) {
    
        ### Begin Error Handling
        if( $dhash->{helper}{infoErrorCounter} > 0 ) {
        
            readingsBeginUpdate( $dhash );
            readingsBulkUpdate( $dhash, "lastStatusRequestState", "statusRequest_error", 1 );

            if( ReadingsVal( $dname, "flow_Informations", "active" ) eq "inactive" && ReadingsVal( $dname, "flow_SetCommands", "active" ) eq "inactive" ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: CHECK THE LAST ERROR READINGS FOR MORE INFO, DEVICE IS SET OFFLINE";
            
                readingsBulkUpdate( $dhash, "deviceState", "offline", 1 );
                readingsBulkUpdate ( $dhash, "state", "AMAD Flows inactive, device set offline",1);
            }

            elsif( $dhash->{helper}{infoErrorCounter} > 7 && $dhash->{helper}{setCmdErrorCounter} > 4 ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
        
                $attr{$dname}{disable} = 1;
                readingsBulkUpdate ( $dhash, "state", "Unknown Error, device disabled", 1);
        
                $dhash->{helper}{infoErrorCounter} = 0;
                $dhash->{helper}{setCmdErrorCounter} = 0;
        
                return;
            }

            elsif( ReadingsVal( $dname, "flow_Informations", "active" ) eq "inactive" ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: Informations Flow on your Device is inactive, will try to reactivate";
            }

            elsif( $dhash->{helper}{infoErrorCounter} > 7 ) {

                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: To many Errors please check your Network or Device Configuration, DEVICE IS SET OFFLINE";
            
                readingsBulkUpdate( $dhash, "deviceState", "offline", 1 );
                readingsBulkUpdate ( $dhash, "state", "To many Errors, device set offline", 1);
                $dhash->{helper}{infoErrorCounter} = 0;
            }
        
            elsif($dhash->{helper}{infoErrorCounter} > 2 && ReadingsVal( $dname, "flow_Informations", "active" ) eq "active" ){
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: Please check the AutomagicAPP on your Device";
            }

            readingsEndUpdate( $dhash, 1 );
        }
        
        if( defined( $err ) ) {
            if( $err ne "" ) {
            
                readingsBeginUpdate( $dhash );
                readingsBulkUpdate ( $dhash, "state", "$err") if( ReadingsVal( $dname, "state", 1 ) ne "initialized" );
                $dhash->{helper}{infoErrorCounter} = ( $dhash->{helper}{infoErrorCounter} + 1 );

                readingsBulkUpdate( $dhash, "lastStatusRequestState", "statusRequest_error", 1 );
        
                if( $err =~ /timed out/ ) {
        
                    Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: connect to your device is timed out. check network";
                }
        
                elsif( ( $err =~ /Keine Route zum Zielrechner/ ) && $dhash->{helper}{infoErrorCounter} > 1 ) {
        
                    Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: no route to target. bad network configuration or network is down";
        
                } else {

                    Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: $err";
                }

                readingsEndUpdate( $dhash, 1 );

                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: AMADCommBridge_statusRequestErrorHandling: error while requesting AutomagicInfo: $err";

                return;
            }
        }

        if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
        
            readingsBeginUpdate( $dhash );
            readingsBulkUpdate ( $dhash, "state", $param->{code}, 1 ) if( ReadingsVal( $dname, "state", 1 ) ne "initialized" );
            $dhash->{helper}{infoErrorCounter} = ( $dhash->{helper}{infoErrorCounter} + 1 );

            readingsBulkUpdate( $dhash, "lastStatusRequestState", "statusRequest_error", 1 );
        
            if( $param->{code} ne 200 ) {

                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: ".$param->{code};
            }

            readingsEndUpdate( $dhash, 1 );
        
            Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: received http code ".$param->{code}." without any data after requesting AMAD AutomagicInfo";

            return;
        }

        if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
            readingsBeginUpdate( $dhash );
            readingsBulkUpdate( $dhash, "state", $param->{code}, 1 ) if( ReadingsVal( $dname, "state" ,0) ne "initialized" );
            $dhash->{helper}{infoErrorCounter} = ( $dhash->{helper}{infoErrorCounter} + 1 );

            readingsBulkUpdate( $dhash, "lastStatusRequestState", "statusRequest_error", 1 );

            if( $param->{code} eq 404 && ReadingsVal( $dname, "flow_Informations", "inactive" ) eq "inactive" ) {

                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: check the informations flow on your device";
            }
        
            elsif( $param->{code} eq 404 && ReadingsVal( $dname, "flow_Informations", "active" ) eq "active" ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: check the automagicApp on your device";
        
            } else {

                Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: http error ".$param->{code};
            }

            readingsEndUpdate( $dhash, 1 );
        
            Log3 $dname, 5, "AMADCommBridge ($dname) - statusRequestERROR: received http code ".$param->{code}." receive Error after requesting AMAD AutomagicInfo";

            return;
        }

        ### End Error Handling

        readingsSingleUpdate( $dhash, "lastStatusRequestState", "statusRequest_done", 1 );
        $dhash->{helper}{infoErrorCounter} = 0;
    }
    
    elsif( $param->{method} eq 'POST' ) {

        ### Begin Error Handling
        if( $dhash->{helper}{setCmdErrorCounter} > 2 ) {
        
        readingsBeginUpdate( $dhash );
        readingsBulkUpdate( $dhash, "lastSetCommandState", "statusRequest_error", 1 );

            if( ReadingsVal( $dname, "flow_Informations", "active" ) eq "inactive" && ReadingsVal( $dname, "flow_SetCommands", "active" ) eq "inactive" ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: CHECK THE LAST ERROR READINGS FOR MORE INFO, DEVICE IS SET OFFLINE";

                readingsBulkUpdate( $dhash, "deviceState", "offline", 1 );
                readingsBulkUpdate( $dhash, "state", "AMAD Flows inactive, device set offline", 1 );
            }

            elsif( $dhash->{helper}{infoErrorCounter} > 7 && $dhash->{helper}{setCmdErrorCounter} > 4 ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";
        
                $attr{$dname}{disable} = 1;
                readingsBulkUpdate( $dhash, "state", "Unknown Error, device disabled", 1 );
                $dhash->{helper}{infoErrorCounter} = 0;
                $dhash->{helper}{setCmdErrorCounter} = 0;

                return;
            }

            elsif( ReadingsVal( $dname, "flow_SetCommands", "active" ) eq "inactive" ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: Flow SetCommands on your Device is inactive, will try to reactivate";
            }

            elsif( $dhash->{helper}{setCmdErrorCounter} > 9 ) {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: To many Errors please check your Network or Device Configuration, DEVICE IS SET OFFLINE";
        
                readingsBulkUpdate( $dhash, "deviceState", "offline", 1 );
                readingsBulkUpdate( $dhash, "state", "To many Errors, device set offline", 1 );
                $dhash->{helper}{setCmdErrorCounter} = 0;
            }

            elsif( $dhash->{helper}{setCmdErrorCounter} > 4 && ReadingsVal( $dname, "flow_SetCommands", "active" ) eq "active" ){
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: Please check the AutomagicAPP on your Device";
            }

            readingsEndUpdate( $dhash, 1 );
        }
        
        if( defined( $err ) ) {
            if( $err ne "" ) {
                readingsBeginUpdate( $dhash );
                readingsBulkUpdate( $dhash, "state", $err, 1 ) if( ReadingsVal( $dname, "state", 0 ) ne "initialized" );
                $dhash->{helper}{setCmdErrorCounter} = ($dhash->{helper}{setCmdErrorCounter} + 1);
        
                readingsBulkUpdate( $dhash, "lastSetCommandState", "setCmd_error", 1 );
        
                if( $err =~ /timed out/ ) {

                    Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: connect to your device is timed out. check network";
                }
        
                elsif( $err =~ /Keine Route zum Zielrechner/ ) {

                    Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: no route to target. bad network configuration or network is down";

                } else {
        
                    Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: $err";
                }
        
                readingsEndUpdate( $dhash, 1 );

                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: error while POST Command: $err";

                return;
            }
        }
    
        if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
        
            readingsBeginUpdate( $dhash );
            readingsBulkUpdate( $dhash, "state", $param->{code}, 1 ) if( ReadingsVal( $dhash, "state", 0 ) ne "initialized" );

            $dhash->{helper}{setCmdErrorCounter} = ( $dhash->{helper}{setCmdErrorCounter} + 1 );

            readingsBulkUpdate($dhash, "lastSetCommandState", "setCmd_error", 1 );

            readingsEndUpdate( $dhash, 1 );
        
            Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: received http code ".$param->{code};

            return;
        }
            
        if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {
        
            readingsBeginUpdate( $dhash );
            readingsBulkUpdate( $dhash, "state", $param->{code}, 1 ) if( ReadingsVal( $dname, "state", 0 ) ne "initialized" );

            $dhash->{helper}{setCmdErrorCounter} = ( $dhash->{helper}{setCmdErrorCounter} + 1 );

            readingsBulkUpdate( $dhash, "lastSetCommandState", "setCmd_error", 1 );
        
            if( $param->{code} eq 404 ) {
        
                readingsBulkUpdate( $dhash, "lastSetCommandError", "", 1 );
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: setCommands flow is inactive on your device!";
        
            } else {
        
                Log3 $dname, 5, "AMADCommBridge ($dname) - setCommandERROR: http error ".$param->{code};
            }

            return;
        }
        
        ### End Error Handling
        
        readingsSingleUpdate( $dhash, "lastSetCommandState", "setCmd_done", 1 );
        $dhash->{helper}{setCmdErrorCounter} = 0;
        
        return undef;
    }
    
    
}

sub AMADCommBridge_Open($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $port    = $hash->{PORT};
    

    if( not defined($hash->{FD}) and (! $hash->{FD}) ) {
        # Oeffnen des TCP Sockets
        my $ret = TcpServer_Open( $hash, $port, "global" );
    
        if( $ret && !$init_done ) {
    
            Log3 $name, 3, "AMADCommBridge ($name) - $ret. Exiting.";
            exit(1);
        }
    
        readingsSingleUpdate ( $hash, "state", "opened", 1 ) if( defined($hash->{FD}) );
        Log3 $name, 3, "AMADCommBridge ($name) - Socket opened.";

        return $ret;
    
    } else {
    
        Log3 $name, 3, "AMADCommBridge ($name) - Socket already opened";
    }
    
    return;
}

sub AMADCommBridge_Close($) {

    my $hash    = shift;
    
    my $name    = $hash->{NAME};
    
    delete $modules{AMADCommBridge}{defptr}{BRIDGE};
    TcpServer_Close( $hash );
    
    if( not defined($hash->{FD}) ) {
        readingsSingleUpdate ( $hash, "state", "closed", 1 );
        Log3 $name, 3, "AMADCommBridge ($name) - Socket closed.";
        
    } else {
        Log3 $name, 3, "AMADCommBridge ($name) - can't close Socket.";
    }
    
    return;
}

sub AMADCommBridge_Read($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};


    if( $hash->{SERVERSOCKET} ) {               # Accept and create a child
        TcpServer_Accept( $hash, "AMADCommBridge" );
        return;
    }

    # Read 1024 byte of data
    my $buf;
    my $ret = sysread($hash->{CD}, $buf, 2048);


    # When there is an error in connection return
    if( !defined($ret ) or $ret <= 0 ) {
        CommandDelete( undef, $name );
        Log3 $name, 5, "AMADCommBridge ($name) - Connection closed for $name";
        return;
    }
    
    AMADCommBridge_ProcessRead($hash,$buf);
}

sub AMADCommBridge_ProcessRead($$) {

    my ($hash, $buf)    = @_;
    my $name            = $hash->{NAME};
    
    my @data            = split( '\R\R', $buf );
    my $data            = $data[0];
    my $json            = $data[1];
    my $buffer          = '';
    
    
    
    
    Log3 $name, 4, "AMADCommBridge ($name) - process read";
    
    
    my $response;
    my $c;
    
    my $fhempath = $attr{global}{modpath};
    
    if ( $data =~ /currentFlowsetUpdate.xml/ ) {

        $response = qx(cat $fhempath/FHEM/lib/74_AMADautomagicFlowset_$flowsetversion.xml);
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;

        return;
        
    } elsif( $data =~ /currentTaskersetUpdate.prj.xml/ ) {
    
        $response = qx(cat $fhempath/FHEM/lib/74_AMADtaskerset_$flowsetversion.prj.xml);
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;

        return;
    
    } elsif ( $data =~ /installFlow_([^.]*.xml)/ ) {

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


    if(defined($hash->{PARTIAL}) and $hash->{PARTIAL}) {
    
        Log3 $name, 5, "AMADCommBridge ($name) - PARTIAL: " . $hash->{PARTIAL};
        $buffer = $hash->{PARTIAL};
        
    } else {
    
        Log3 $name, 4, "AMADCommBridge ($name) - No PARTIAL buffer";
    }

    Log3 $name, 5, "AMADCommBridge ($name) - Incoming data: " . $json;

    $buffer = $buffer . $json;
    Log3 $name, 4, "AMADCommBridge ($name) - Current processing buffer (PARTIAL + incoming data): " . $buffer;

    my ($correct_json,$tail) = AMADCommBridge_ParseMsg($hash, $buffer);


    while($correct_json) {
    
        $hash->{LAST_RECV} = time();
        
        Log3 $name, 5, "AMADCommBridge ($name) - Decoding JSON message. Length: " . length($correct_json) . " Content: " . $correct_json;
        Log3 $name, 5, "AMADCommBridge ($name) - Vor Sub: Laenge JSON: " . length($correct_json) . " Content: " . $correct_json . " Tail: " . $tail;
        
        AMADCommBridge_ResponseProcessing($hash,$correct_json)
        unless(not defined($tail) and not ($tail));
        
        ($correct_json,$tail) = AMADCommBridge_ParseMsg($hash, $tail);
        
        Log3 $name, 5, "AMADCommBridge ($name) - Nach Sub: Laenge JSON: " . length($correct_json) . " Content: " . $correct_json . " Tail: " . $tail;
    }


    $hash->{PARTIAL} = $tail;
    Log3 $name, 4, "AMADCommBridge ($name) - PARTIAL lenght: " . length($tail);
    
    
    Log3 $name, 5, "AMADCommBridge ($name) - Tail: " . $tail;
    Log3 $name, 5, "AMADCommBridge ($name) - PARTIAL: " . $hash->{PARTIAL};
    
}

sub AMADCommBridge_ResponseProcessing($$) {

    my ($hash,$json)     = @_;
    
    my $name        = $hash->{NAME};
    my $bhash       = $modules{AMADCommBridge}{defptr}{BRIDGE};
    my $bname       = $bhash->{NAME};
    
    
    
    
    #### Verarbeitung der Daten welche über die AMADCommBridge kommen ####
    
    Log3 $bname, 4, "AMADCommBridge ($name) - Receive RAW Message in Debugging Mode: $json";


    my $response;
    my $c;


    my $decode_json =   eval{decode_json($json)};
    if($@){
        Log3 $bname, 4, "AMADCommBridge ($name) - JSON error while request: $@";
        
        if( AttrVal( $bname, 'debugJSON', 0 ) == 1 ) {
            readingsBeginUpdate($bhash);
            readingsBulkUpdate($bhash, 'JSON_ERROR', $@, 1);
            readingsBulkUpdate($bhash, 'JSON_ERROR_STRING', $json, 1);
            readingsEndUpdate($bhash, 1);
        }
        
        $response = "header lines: \r\n AMADCommBridge receive a JSON error\r\n AMADCommBridge to do nothing\r\n";
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
        return;
    }

    my $amad_id     = $decode_json->{amad}{amad_id};
    my $fhemcmd     = $decode_json->{amad}{fhemcmd};
    my $fhemDevice;
    
    if( defined($decode_json->{firstrun}) and ($decode_json->{firstrun}) ) {
    
        $fhemDevice  = $decode_json->{firstrun}{fhemdevice} if( defined($decode_json->{firstrun}{fhemdevice}) );
        
    } else {
    
        $fhemDevice  = $modules{AMADDevice}{defptr}{$amad_id}->{NAME};
    }




    if( !defined($amad_id) or !defined($fhemDevice) ) {
        readingsSingleUpdate( $bhash, "transmitterERROR", $hash->{NAME}." has no correct amad_id", 1 );
        Log3 $bname, 4, "AMADCommBridge ($name) - ERROR - no device name given. please check your global variable amad_id in automagic";
        
        $response = "header lines: \r\n AMADCommBridge receive no device name. please check your global variable amad_id in automagic\r\n FHEM to do nothing\r\n";
        $c = $hash->{CD};
        print $c "HTTP/1.1 200 OK\r\n",
            "Content-Type: text/plain\r\n",
            "Connection: close\r\n",
            "Content-Length: ".length($response)."\r\n\r\n",
            $response;
        
        return;
    }

    
    if( defined($fhemcmd) and ($fhemcmd) ) {
        if ( $fhemcmd eq 'setreading' ) {
            return Log3 $bname, 3, "AMADCommBridge ($name) - AMADCommBridge: processing receive no reading values from Device: $fhemDevice"
            unless( (defined($decode_json->{payload}) and ($decode_json->{payload})) or (defined($decode_json->{firstrun}) and ($decode_json->{firstrun})) );
            
            Log3 $bname, 4, "AMADCommBridge ($bname) - AMADCommBridge: processing receive reading values - Device: $fhemDevice Data: $decode_json->{payload}"
            if( defined($decode_json->{payload}) and ($decode_json->{payload}) );

            Dispatch($bhash,$json,undef);
            Log3 $bname, 4, "AMADCommBridge ($bname) - call Dispatcher";
            readingsSingleUpdate($bhash,'fhemServerIP',$decode_json->{firstrun}{'fhemserverip'},1) if( defined($decode_json->{firstrun}{'fhemserverip'}));
        
            $response = "header lines: \r\n AMADCommBridge receive Data complete\r\n FHEM was processes\r\n";
            $c = $hash->{CD};
            print $c "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain\r\n",
                "Connection: close\r\n",
                "Content-Length: ".length($response)."\r\n\r\n",
                $response;

            return;
        }

        elsif ( $fhemcmd eq 'set' ) {
            my $fhemCmd = encode_utf8($decode_json->{payload}{setcmd});
            AnalyzeCommandChain($bhash, 'set '.$fhemCmd) if( AttrVal( $bname, 'fhemControlMode', 'trigger' ) eq 'setControl' );
            readingsSingleUpdate( $bhash, "receiveFhemCommand", "set ".$fhemCmd, 1 ) if( AttrVal( $bname, 'fhemControlMode', 'trigger' ) eq 'trigger' );
            Log3 $bname, 4, "AMADCommBridge ($name) - AMADCommBridge_CommBridge: set reading receive fhem command";

            $response = "header lines: \r\n AMADCommBridge receive Data complete\r\n FHEM response\r\n";
            $c = $hash->{CD};
            print $c "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain\r\n",
                "Connection: close\r\n",
                "Content-Length: ".length($response)."\r\n\r\n",
                $response;

            return;
        }
    
        elsif ( $fhemcmd eq 'voiceinputvalue' ) {
            my $fhemCmd = lc(encode_utf8($decode_json->{payload}{voiceinputdata}));
        
            readingsBeginUpdate( $bhash);
            readingsBulkUpdate( $bhash, "receiveVoiceCommand", $fhemCmd, 1 );
            readingsBulkUpdate( $bhash, "receiveVoiceDevice", $fhemDevice, 1 );
            readingsEndUpdate( $bhash, 1 );
            Log3 $bname, 4, "AMADCommBridge ($name) - AMADCommBridge_CommBridge: set reading receive voice command: $fhemCmd from Device $fhemDevice";

            $response = "header lines: \r\n AMADCommBridge receive Data complete\r\n FHEM was processes\r\n";
            $c = $hash->{CD};
            print $c "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain\r\n",
                "Connection: close\r\n",
                "Content-Length: ".length($response)."\r\n\r\n",
                $response;
            
            return;
        }
    
        elsif ( $fhemcmd eq 'readingsval' ) {
            my $fhemCmd = $decode_json->{payload}{readingsvalcmd};
            my @datavalue = split( ' ', $fhemCmd );

            $response = ReadingsVal($datavalue[0],$datavalue[1],$datavalue[2]);
            $c = $hash->{CD};
            print $c "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain\r\n",
                "Connection: close\r\n",
                "Content-Length: ".length($response)."\r\n\r\n",
                $response;

            return;
        }

        elsif ( $fhemcmd eq 'fhemfunc' ) {
            my $fhemCmd = $decode_json->{payload}{fhemsub};
 
            Log3 $bname, 4, "AMADCommBridge ($name) - AMADCommBridge_CommBridge: receive fhem-function command";
 
            if( AttrVal( $bname, 'enableSubCalls', 0 ) == 1 ) {

                $response = AnalyzeCommand($bhash, '{'.$fhemCmd.'}');
                    
            } else {
            
                $response = "header lines: \r\n Attribut enableSubCalls is not set or value is 0\r\n FHEM to do nothing\r\n";
                Log3 $bname, 3, "AMADCommBridge ($name) - Attribut enableSubCalls is not set or value is 0, FHEM to do nothing";
            }
 
            $c = $hash->{CD};
            print $c "HTTP/1.1 200 OK\r\n",
                "Content-Type: text/plain\r\n",
                "Connection: close\r\n",
                "Content-Length: ".length($response)."\r\n\r\n",
                $response;
 
            return;
         }
    }



    $response = "header lines: \r\n AMADCommBridge receive incomplete or corrupt Data\r\n FHEM to do nothing\r\n";
    $c = $hash->{CD};
    print $c "HTTP/1.1 200 OK\r\n",
        "Content-Type: text/plain\r\n",
        "Connection: close\r\n",
        "Content-Length: ".length($response)."\r\n\r\n",
        $response;
}


##################
### my little helper
##################

sub AMADCommBridge_ParseMsg($$) {

    my ($hash, $buffer) = @_;
    
    my $name = $hash->{NAME};
    my $open = 0;
    my $close = 0;
    my $msg = '';
    my $tail = '';
    
    
    if($buffer) {
        foreach my $c (split //, $buffer) {
            if($open == $close && $open > 0) {
                $tail .= $c;
                Log3 $name, 5, "AMADCommBridge ($name) - $open == $close && $open > 0";
                
            } elsif(($open == $close) && ($c ne '{')) {
            
                Log3 $name, 5, "AMADCommBridge ($name) - Garbage character before message: " . $c;
        
            } else {
      
                if($c eq '{') {

                    $open++;
                
                } elsif($c eq '}') {
                
                    $close++;
                }
                
                $msg .= $c;
            }
        }
        
        if($open != $close) {
    
            $tail = $msg;
            $msg = '';
        }
    }
    
    Log3 $name, 5, "AMADCommBridge ($name) - return msg: $msg and tail: $tail";
    return ($msg,$tail);
}

##### bleibt zu Anschauungszwecken erhalten
#sub AMADCommBridge_Header2Hash($) {
#
#    my $string  = shift;
#    my %hash    = ();
#
#    foreach my $line (split("\r\n", $string)) {
#        my ($key,$value) = split( ": ", $line );
#        next if( !$value );
#
#        $value =~ s/^ //;
#        $hash{$key} = $value;
#    }     
#        
#    return \%hash;
#}









1;

=pod

=item device
=item summary    Integrates Android devices into FHEM and displays several settings.
=item summary_DE Integriert Android-Geräte in FHEM und zeigt verschiedene Einstellungen an.

=begin html

<a name="AMADCommBridge"></a>
<h3>AMADCommBridge</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u></p>
  <b>AMADCommBridge - Communication bridge for all AMAD devices</b>
  </br>
  This module is the central point for the successful integration of Android devices in FHEM. It also provides a link level between AMAD supported devices and FHEM. All communication between AMAD Android and FHEM runs through this interface.</br>
  Therefore, the initial setup of an AMAD device is also performed exactly via this module instance.
  </br></br>
  In order to successfully establish an Android device in FHEM, an AMADCommBridge device must be created in the first step.
  <br><br>
  <a name="AMADCommBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AMADCommBridge</code>
    <br><br>
    Example:
    <ul><br>
      <code>define AMADBridge AMADCommBridge</code><br>
    </ul>
    <br>
    This statement creates a new AMADCommBridge device named AMADBridge.
  </ul></br>
  The APP Automagic or Tasker can be used on the Android device.</br>
  <br>
  <b>For Autoremote:</b><br>
  In the following, only the Flowset has to be installed on the Android device and the Flow 'First Run Assistant' run. (Simply press the Homebutton)</br>
  The wizard then guides you through the setup of your AMAD device and ensures that at the end of the installation process the Android device is created as an AMAD device in FHEM.</br>
  <br>
  <b>For Tasker:</b><br>
  When using Tasker, the Tasker-project must be loaded onto the Android device and imported into Tasker via the import function.<br>
  For the initial setup on the Android device there is an Tasker input mask (Scene), in which the required parameters (device name, device IP, bridgeport etc.)</br>
  can be entered, these fields are filled (if possible) automatically, but can also be adjusted manually.</br>
  To do this, run the "AMAD" task.</br>
  For quick access, a Tasker shortcut can also be created on the home screen for this task.</br>
  Information on the individual settings can be obtained by touching the respective text field.</br>
  If all entries are complete, the AMAD Device can be created via the button "create Device".</br>
  For control commands from FHEM to Tasker, the APP "Autoremote" or "Tasker Network Event Server (TNES)" is additionally required.
  <br><br>
  <a name="AMADCommBridgereadings"></a>
  <b>Readings</b>
  <ul><br>
    <li>JSON_ERROR - JSON Error message reported by Perl</li>
    <li>JSON_ERROR_STRING - The string that caused the JSON error message</li>
    <li>fhemServerIP - The IP address of the FHEM server, is set by the module based on the JSON string from the installation wizard. Can also be set by user using set command</li>
    <li>receiveFhemCommand - is set the fhemControlMode attribute to trigger, the reading is set as soon as an FHEM command is sent. A notification can then be triggered.</br>
    If set instead of trigger setControl as value for fhemControlMode, the reading is not executed but the set command executed immediately.</li>
    <li>receiveVoiceCommand - The speech control is activated by AMAD (set DEVICE activateVoiceInput), the last recognized voice command is written into this reading.</li>
    <li>receiveVoiceDevice - Name of the device from where the last recognized voice command was sent</li>
    <li>state - state of the Bridge, open, closed</li>
  </ul>
  <br><br>
  <a name="AMADCommBridgeattribute"></a>
  <b>Attributes</b>
  <ul><br>
    <li>allowFrom - Regexp the allowed IP addresses or hostnames. If this attribute is set, only connections from these addresses are accepted.</br>
    Attention: If allowfrom is not set, and no kind allowed instance is defined, and the remote has a non-local address, then the connection is rejected. The following addresses are considered local:</br>
    IPV4: 127/8, 10/8, 192.168/16, 172.16/10, 169.254/16</br>
    IPV6: ::1, fe80/10</li>
    <li>debugJSON - If set to 1, JSON error messages are written in readings. See JSON_ERROR * under Readings</li>
    <li>fhemControlMode - Controls the permissible type of control of FHEM devices. You can control the bridge in two ways FHEM devices. Either by direct FHEM command from a flow, or as a voice command by means of voice control (set DEVICE activateVoiceInput)
    <ul><li>trigger - If the value trigger is set, all FHEM set commands sent to the bridge are written to the reading receiveFhemCommand and can be executed using notify. Voice control is possible; readings receiveVoice * are set. On the Android device several voice commands can be linked by means of "and". Example: turn on the light scene in the evening and turn on the TV</li>
    <li>setControl - All set commands sent via the flow are automatically executed. The triggering of a reading is not necessary. The control by means of language behaves like the value trigger</li>
    <li>thirdPartControl - Behaves as triggered, but in the case of voice control, a series of voice commands by means of "and" is not possible. Used for voice control via modules of other module authors ((z.B. 39_TEERKO.pm)</li></ul>
    </li>
  </ul>
  </br></br>
  If you have problems with the wizard, an Android device can also be applied manually, you will find in the Commandref to the AMADDevice module.
</ul>

=end html
=begin html_DE

<a name="AMADCommBridge"></a>
<h3>AMADCommBridge</h3>
<ul>
  <u><b>AMAD - Automagic Android Device</b></u></p>
  <b>AMADCommBridge - Kommunikationsbr&uuml;cke für alle AMAD Ger&auml;te</b>
  </br>
  Dieses Modul ist das Ausgangsmodul zur erfolgreichen Integration von Androidger&auml;ten in FHEM. Es stellt ferner eine Verbindungsebene zwischen AMAD unterst&uuml;tzten Ger&auml;ten und FHEM zur Verf&uuml;gung. Alle Kommunikation zwischen AMAD Android und FHEM l&auml;uft &uuml;ber diese Schnittstelle.</br>
  Daher erfolgt die Ersteinrichtung eines AMAD Devices auch genau &uuml;ber diese Modulinstanz.
  </br></br>
  Damit erfolgreich ein Androidger&auml;t in FHEM eingerichtet werden kann, muss im ersten Schritt ein AMADCommBridge Device angelegt werden.
  <br><br>
  <a name="AMADCommBridgedefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; AMADCommBridge</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define AMADBridge AMADCommBridge</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein neues AMADCommBridge Device Namens AMADBridge. 
  </ul></br>
  Es kann wahlweise die APP Automagic oder Tasker auf dem Android Ger&auml;t verwendet werden.
  <br>
  <b>F&uuml;r Autoremote:</b><br>
  Im folgenden mu&szlig; lediglich das Flowset auf dem Android Ger&auml;t installiert werden und der Flow 'First Run Assistent' ausgef&uuml;hrt werden. (einfach den Homebutton drücken)</br>
  Der Assistent geleitet Dich dann durch die Einrichtung Deines AMAD Ger&auml;tes und sorgt daf&uuml;r das am Ende des Installationsprozess das Androidger&auml;t als AMAD Device in FHEM angelegt wird.</br>
  <br>
  <b>F&uuml;r Tasker:</b><br>
  Bei Verwendung von Tasker muss das Tasker-Projekt auf das Android Ger&auml;t geladen und in Tasker &uuml;ber die Import Funktion importiert werden.<br>
  F&uuml;r die Ersteinrichtung auf dem Android Ger&auml;t gibt es eine Eingabemaske (Scene), in der die ben&ouml;tigten Parameter (Device Name, Device IP, Bridgeport usw.)</br>
  eingegeben werden k&ouml;nnen, diese Felder werden (soweit m&ouml;glich) automatisch bef&uuml;llt, k&ouml;nnen aber auch manuell angepasst werden.</br>
  Hierf&uuml;r den Task &quot;AMAD&quot; ausf&uuml;hren.</br>
  F&uuml;r schnellen Zugriff kann f&uuml;r diesen Task auch ein Tasker-Shortcut auf dem Homescreen angelegt werden.</br>
  Infos zu den einzelnen Einstellungen erh&auml;lt man durch einen Touch auf das jeweiligen Textfeld.</br>
  Sind alle Eingaben vollst&auml;ndig, kann das AMAD Device &uuml;ber die Schaltfl&auml;che &quot;create Device&quot; erstellt werden.</br>
  Damit Steuerbefehle von FHEM zu Tasker funktionieren wird zus&auml;tzlich noch die APP "Autoremote" oder "Tasker Network Event Server (TNES)" ben&ouml;tigt.
  <br><br>
  <a name="AMADCommBridgereadings"></a>
  <b>Readings</b>
  <ul><br>
    <li>JSON_ERROR - JSON Fehlermeldung welche von Perl gemeldet wird</li>
    <li>JSON_ERROR_STRING - der String welcher die JSON Fehlermeldung verursacht hat</li>
    <li>fhemServerIP - die Ip-Adresse des FHEM Servers, wird vom Modul auf Basis des JSON Strings vom Installationsassistenten gesetzt. Kann aber auch mittels set Befehles vom User gesetzt werden</li>
    <li>receiveFhemCommand - ist das Attribut fhemControlMode auf trigger gestellt, wird das Reading gesetzt sobald ein FHEM Befehl übersendet wird. Hierauf kann dann ein Notify triggern.</br>
    Wird anstelle von trigger setControl als Wert für fhemControlMode eingestellt, wird das Reading nicht gestzt sondern der set Befehl sofort ausgeführt.</li>
    <li>receiveVoiceCommand - wird die Sprachsteuerung von AMAD aktiviert (set DEVICE activateVoiceInput) so wird der letzte erkannten Sprachbefehle in dieses Reading geschrieben.</li>
    <li>receiveVoiceDevice - Name des Devices von wo aus der letzte erkannte Sprachbefehl gesendet wurde</li>
    <li>state - Status der Bridge, open, closed</li>
  </ul>
  <br><br>
  <a name="AMADCommBridgeattribute"></a>
  <b>Attribute</b>
  <ul><br>
    <li>allowFrom - Regexp der erlaubten IP-Adressen oder Hostnamen. Wenn dieses Attribut gesetzt wurde, werden ausschließlich Verbindungen von diesen Adressen akzeptiert.</br>
    Achtung: falls allowfrom nicht gesetzt ist, und keine gütige allowed Instanz definiert ist, und die Gegenstelle eine nicht lokale Adresse hat, dann wird die Verbindung abgewiesen. Folgende Adressen werden als local betrachtet:</br>
    IPV4: 127/8, 10/8, 192.168/16, 172.16/10, 169.254/16</br>
    IPV6: ::1, fe80/10</li>
    <li>debugJSON - wenn auf 1 gesetzt, werden JSON Fehlermeldungen in Readings geschrieben. Siehe hierzu JSON_ERROR* unter Readings</li>
    <li>fhemControlMode - steuert die zulässige Art der Kontrolle von FHEM Devices. Du kannst über die Bridge auf 2 Arten FHEM Devices steuern. Entweder per direktem FHEM Befehl aus einem Flow heraus, oder als Sprachbefehl mittels Sprachsteuerung (set DEVICE activateVoiceInput)
    <ul><li>trigger - ist der Wert trigger gesetzt, werden alle an die Bridge gesendeten FHEM set Befehle in das Reading receiveFhemCommand geschrieben und können so mittels notify ausgeführt werden. Sprachsteuerung ist möglich, es werden Readings receiveVoice* gesetzt. Auf dem Androidgerät können bei Sprachsteuerung mehrere Sprachbefehle mittels "und" verknüpft/aneinander gereiht werden. Bsp: schalte die Lichtszene Abends an und schalte den Fernsehr an</li>
    <li>setControl - alle set Befehle welche mittels eines Flows über die Bridge gesendet werden, werden automatisch ausgeführt. Das triggern eines Readings ist nicht nötig. Die Steuerung mittels Sprache verhält sich wie beim Wert trigger</li>
    <li>thirdPartControl - verhält sich wie trigger, bei der Sprachsteuerung ist jedoch ein anreihen von Sprachbefehlen mittels "und" nicht möglich. Dient der Sprachsteuerung über Module anderer Modulautoren ((z.B. 39_TEERKO.pm)</li></ul>
    </li>
  </ul>
  </br></br>
  Wie man bei Problemen mit dem Assistenten ein Androidger&auml;t auch von Hand anlegen kann, erf&auml;hrst Du in der Commandref zum AMADDevice Modul.
</ul>

=end html_DE
=cut

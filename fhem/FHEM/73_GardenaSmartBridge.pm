###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - Michael (mbrak)       Thanks for Commandref
#       - Matthias (Kenneth)    Thanks for Wiki entry
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
###### Wichtige Notizen
#
#   apt-get install libio-socket-ssl-perl
#   http://www.dxsdata.com/de/2016/07/php-class-for-gardena-smart-system-api/
#   
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
use Data::Dumper;   #debugging

eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use IO::Socket::SSL;1" or $missingModul .= "IO::Socket::SSL ";
###todo Hier fehlt noch Modulabfrage für ssl


my $version = "0.2.2";




# Declare functions
sub GardenaSmartBridge_Attr(@);
sub GardenaSmartBridge_Define($$);
sub GardenaSmartBridge_Initialize($);
sub GardenaSmartBridge_Set($@);
sub GardenaSmartBridge_Write($@);
sub GardenaSmartBridge_Undef($$);
sub GardenaSmartBridge_ResponseProcessing($$);
sub GardenaSmartBridge_ErrorHandling($$$);
sub GardenaSmartBridge_encrypt($);
sub GardenaSmartBridge_decrypt($);
sub GardenaSmartBridge_WriteReadings($$);
sub GardenaSmartBridge_ParseJSON($$);
sub GardenaSmartBridge_getDevices($);
sub GardenaSmartBridge_getToken($);
sub GardenaSmartBridge_InternalTimerGetDeviceData($);
sub GardenaSmartBridge_createHttpValueStrings($@);




sub GardenaSmartBridge_Initialize($) {

    my ($hash) = @_;

    
    # Provider
    $hash->{WriteFn}    = "GardenaSmartBridge_Write";
    $hash->{Clients}    = ":GardenaSmartDevice:";
    $hash->{MatchList}  = { "1:GardenaSmartDevice"      => '^{"id":".*' };
    
    
    # Consumer
    $hash->{SetFn}      = "GardenaSmartBridge_Set";
    $hash->{DefFn}      = "GardenaSmartBridge_Define";
    $hash->{UndefFn}    = "GardenaSmartBridge_Undef";
    
    $hash->{AttrFn}     = "GardenaSmartBridge_Attr";
    $hash->{AttrList}   = "debugJSON:0,1 ".
                          "disable:1 ".
                          "interval ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{GardenaSmartBridge}{defptr}}) {
    
        my $hash = $modules{GardenaSmartBridge}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub GardenaSmartBridge_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <NAME> GardenaSmartBridge <Email> <Passwort>" if( @a != 4 ) ;
    return "Cannot define Gardena Bridge device. Perl modul ${missingModul}is missing." if ( $missingModul );
    
    my $name                = $a[0];
    my $user                = $a[2];
    my $pass                = $a[3];
    $hash->{BRIDGE}         = 1;
    $hash->{URL}            = 'https://sg-api.dss.husqvarnagroup.net/sg-1';
    $hash->{VERSION}        = $version;
    $hash->{INTERVAL}       = 300;
    
    my $username            = GardenaSmartBridge_encrypt($user);
    my $password            = GardenaSmartBridge_encrypt($pass);
    Log3 $name, 3, "GardenaSmartBridge ($name) - encrypt $user/$pass to $username/$password" if($user ne $username || $pass ne $password);
    $hash->{DEF} = "$username $password";
    
    $hash->{helper}{username} = $username;
    $hash->{helper}{password} = $password;
    


    $attr{$name}{room} = "GardenaSmart" if( !defined( $attr{$name}{room} ) );
    
    readingsSingleUpdate($hash,'state','initialized',1);
    readingsSingleUpdate($hash,'token','none',1);
    Log3 $name, 3, "GardenaSmartBridge ($name) - defined GardenaSmartBridge and crypt your credentials";

    
    if( $init_done ) {
    
        GardenaSmartBridge_getToken($hash);
        readingsSingleUpdate($hash,'state','get token',1);
        
    } else {
    
        InternalTimer( gettimeofday()+15, "GardenaSmartBridge_getToken", $hash, 0 );
    }
    
    
    $modules{GardenaSmartBridge}{defptr}{BRIDGE} = $hash;

    return undef;
}

sub GardenaSmartBridge_Undef($$) {

    my ( $hash, $arg ) = @_;


    RemoveInternalTimer($hash);
    delete $modules{GardenaSmartBridge}{defptr}{BRIDGE} if( defined($modules{GardenaSmartBridge}{defptr}{BRIDGE}) );

    return undef;
}

sub GardenaSmartBridge_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "inactive", 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            GardenaSmartBridge_InternalTimerGetDeviceData($hash);
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "GardenaSmartBridge ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "inactive", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "GardenaSmartBridge ($name) - enabled";
        }
    }
    
    elsif( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            $hash->{INTERVAL}   = $attrVal;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "GardenaSmartBridge ($name) - set interval: $attrVal";
            GardenaSmartBridge_InternalTimerGetDeviceData($hash);
        }

        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL}   = 300;
            RemoveInternalTimer($hash);
            Log3 $name, 3, "GardenaSmartBridge ($name) - delete User interval and set default: 300";
            GardenaSmartBridge_InternalTimerGetDeviceData($hash);
        }
    }

    return undef;
}

sub GardenaSmartBridge_Set($@) {
    
    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params) = @args;
    
    
    if( lc $cmd eq 'getdevicesstate' ) {
    
        GardenaSmartBridge_getDevices($hash);
        
    } elsif( lc $cmd eq 'gettoken' ) {
    
        return "token is up to date" if( defined($hash->{helper}{session_id}) );
        GardenaSmartBridge_getToken($hash);
    
    } else {
    
        my $list = "getDevicesState:noArg getToken:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return undef;
}

sub GardenaSmartBridge_InternalTimerGetDeviceData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    if( not IsDisabled($name) ) {
    
        GardenaSmartBridge_getDevices($hash);
        Log3 $name, 4, "GardenaSmartBridge ($name) - set internal timer function for recall InternalTimerGetDeviceData sub";
        
    } else {
    
        readingsSingleUpdate($hash,'state','disabled',1);
        Log3 $name, 3, "GardenaSmartBridge ($name) - device is disabled";
    }
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL},"GardenaSmartBridge_InternalTimerGetDeviceData", $hash, 1 );
}

sub GardenaSmartBridge_Write($@) {

    my ($hash,$payload,$deviceId,$abilities)  = @_;
    my $name                                = $hash->{NAME};
    
    my ($session_id,$header,$uri,$method);
    

    
    
    ($payload,$session_id,$header,$uri,$method,$deviceId,$abilities)      = GardenaSmartBridge_createHttpValueStrings($hash,$payload,$deviceId,$abilities);
    
    HttpUtils_NonblockingGet(
        {
            url         => $hash->{URL} . $uri,
            timeout     => 15,
            hash        => $hash,
            device_id   => $deviceId,
            data        => $payload,
            method      => $method,
            header      => $header,
            doTrigger   => 1,
            callback    => \&GardenaSmartBridge_ErrorHandling
        }
    );

    Log3 $name, 4, "GardenaSmartBridge ($name) - Send with URL: $hash->{URL}$uri, HEADER: $header, DATA: $payload, METHOD: $method";
}

sub GardenaSmartBridge_ErrorHandling($$$) {

    my ($param,$err,$data)    = @_;
    
    my $hash                        = $param->{hash};
    my $name                        = $hash->{NAME};
    
    my $dhash;
    if( defined( $param->{'device_id'}) ) {
        $dhash                      = $modules{GardenaSmartDevice}{defptr}{$param->{'device_id'}};
    } else {
        $dhash                      = $hash;
    }
    my $dname                       = $dhash->{NAME};


    ###todo Das gesamte Errorhandling muss hier noch rein
    
    #Log3 $name, 1, "GardenaSmartBridge ($name) - Header:\n".Dumper($param->{header});
    #Log3 $name, 1, "GardenaSmartBridge ($name) - CODE:\n".Dumper($param->{code});
    #Log3 $name, 1, "GardenaSmartBridge ($name) - Error:\n".Dumper($err);
    #Log3 $name, 1, "GardenaSmartBridge ($name) - Data:\n".Dumper($data);
    
    
    
    
    #### Ein Fehler der Behandelt werden muss
   # Data:
   # '<html>
   #     <head>
   #         <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
   #         <title>Error 400 Bad Request</title>
   #     </head>
   #     <body><h2>HTTP ERROR 400</h2>
   #         <p>Problem accessing /sg-1/devices/2ad0d816-8bc3-4f0a-8c52-8b0dc8d7b2ec/abilities/watering_computer/command. Reason:
   #         <pre>    Bad Request</pre></p><hr><i><small>Powered by Jetty://</small></i><hr/>
   #
   #     </body>
   # </html>
   # ';
   
   # '<html>
   #    <head>
   #         <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
   #         <title>Error 503 Service Unavailable</title>
   #     </head>
   #     <body><h2>HTTP ERROR 503</h2>
   #         <p>Problem accessing /sg-1/devices/2ad0d816-8bc3-4f0a-8c52-8b0dc8d7b2ec/abilities/outlet/command. Reason:
   #         <pre>    Service Unavailable</pre></p><hr><i><small>Powered by Jetty://</small></i><hr/>
   # 
   #     </body>
   # </html>
   # ';
   
   
   # 2017.08.10 11:17:20 1: GardenaSmartBridge (myGardena) - Data:
   # $VAR1 = '{"errors":[{"attribute":"password","error":"invalid"}]}';

   
   
   
   if( defined( $err ) ) {
        if( $err ne "" ) {
            
            readingsBeginUpdate( $dhash );
            readingsBulkUpdate( $dhash, "state", "$err") if( ReadingsVal( $dname, "state", 1 ) ne "initialized" );

            readingsBulkUpdate( $dhash, "lastRequestState", "request_error", 1 );
        
            if( $err =~ /timed out/ ) {
        
                Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: connect to gardena cloud is timed out. check network";
            }
        
            elsif( $err =~ /Keine Route zum Zielrechner/ or $err =~ /no route to target/ ) {
        
                Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: no route to target. bad network configuration or network is down";
        
            } else {

                Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: $err";
            }

            readingsEndUpdate( $dhash, 1 );

            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: GardenaSmartBridge RequestErrorHandling: error while requesting gardena cloud: $err";

            delete $dhash->{helper}{deviceAction} if( defined($dhash->{helper}{deviceAction}) );
            
            return;
        }
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} != 200 ) {
        
        readingsBeginUpdate( $dhash );
        readingsBulkUpdate( $dhash, "state", $param->{code}, 1 ) if( ReadingsVal( $dname, "state", 1 ) ne "initialized" );

        readingsBulkUpdateIfChanged( $dhash, "lastRequestState", "request_error", 1 );
        
        if( $param->{code} == 401  and $hash eq $dhash ) {
        
            if( ReadingsVal($dname,'token','none') eq 'none' ) {
                readingsBulkUpdate( $dhash, "state", "no token available", 1);
                readingsBulkUpdateIfChanged( $dhash, "lastRequestState", "no token available", 1 );
            }
            
            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: ".$param->{code};
        
        } elsif( $param->{code} == 204 and $dhash ne $hash and defined($dhash->{helper}{deviceAction}) ) {
            
            readingsBulkUpdate( $dhash, "state", "the command is processed", 1);
            InternalTimer( gettimeofday()+3,"GardenaSmartBridge_getDevices", $hash, 1 );
        
        } elsif( $param->{code} != 200 ) {

            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: ".$param->{code};
        }

        readingsEndUpdate( $dhash, 1 );
        
        Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: received http code ".$param->{code}." without any data after requesting gardena cloud";
        
        delete $dhash->{helper}{deviceAction} if( defined($dhash->{helper}{deviceAction}) );

        return;
    }

    if( ( ($data =~ /Error/ ) or defined(eval{decode_json($data)}->{errors}) ) and exists( $param->{code} ) ) {    
        readingsBeginUpdate( $dhash );
        readingsBulkUpdate( $dhash, "state", $param->{code}, 1 ) if( ReadingsVal( $dname, "state" ,0) ne "initialized" );

        readingsBulkUpdate( $dhash, "lastRequestState", "request_error", 1 );

        if( $param->{code} == 400 ) {
            if( eval{decode_json($data)} ) {
                if( ref(eval{decode_json($data)}->{errors}) eq "ARRAY" and defined(eval{decode_json($data)}->{errors}) ) {
                    readingsBulkUpdate( $dhash, "state", eval{decode_json($data)}->{errors}[0]{error} . ' ' . eval{decode_json($data)}->{errors}[0]{attribute}, 1);
                    readingsBulkUpdate( $dhash, "lastRequestState", eval{decode_json($data)}->{errors}[0]{error} . ' ' . eval{decode_json($data)}->{errors}[0]{attribute}, 1 );
                    Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: " . eval{decode_json($data)}->{errors}[0]{error} . " " . eval{decode_json($data)}->{errors}[0]{attribute};
                }
            } else {
                readingsBulkUpdate( $dhash, "lastRequestState", "Error 400 Bad Request", 1 );
                Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: Error 400 Bad Request";
            }
        } elsif( $param->{code} == 503 ) {

            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: Error 503 Service Unavailable";
            readingsBulkUpdate( $dhash, "state", "Service Unavailable", 1 );
            readingsBulkUpdate( $dhash, "lastRequestState", "Error 503 Service Unavailable", 1 );
            
        } elsif( $param->{code} == 404 ) {
            if( defined($dhash->{helper}{deviceAction}) and $dhash ne $hash ) {
                readingsBulkUpdate( $dhash, "state", "device Id not found", 1 );
                readingsBulkUpdate( $dhash, "lastRequestState", "device id not found", 1 );
            }
            
            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: Error 404 Not Found";
        
        } elsif( $param->{code} == 500 ) {
        
            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: check the ???";
        
        } else {

            Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: http error ".$param->{code};
        }

        readingsEndUpdate( $dhash, 1 );
        
        Log3 $dname, 5, "GardenaSmartBridge ($dname) - RequestERROR: received http code ".$param->{code}." receive Error after requesting gardena cloud";
        
        delete $dhash->{helper}{deviceAction} if( defined($dhash->{helper}{deviceAction}) );

        return;
    }
    
    




    readingsSingleUpdate($hash,'state','connect to cloud',1) if( defined($hash->{helper}{locations_id}) );
    GardenaSmartBridge_ResponseProcessing($hash,$data);
}

sub GardenaSmartBridge_ResponseProcessing($$) {

    my ($hash,$json)    = @_;
    
    my $name            = $hash->{NAME};


    my $decode_json =   eval{decode_json($json)};
    if($@){
        Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request: $@";
        
        if( AttrVal( $name, 'debugJSON', 0 ) == 1 ) {
            readingsBeginUpdate($hash);
            readingsBulkUpdate($hash, 'JSON_ERROR', $@, 1);
            readingsBulkUpdate($hash, 'JSON_ERROR_STRING', $json, 1);
            readingsEndUpdate($hash, 1);
        }
    }
    
    
    
    if( defined($decode_json->{sessions}) and $decode_json->{sessions}) {
    
        $hash->{helper}{session_id}         = $decode_json->{sessions}{token};
        $hash->{helper}{user_id}            = $decode_json->{sessions}{user_id};
        
        GardenaSmartBridge_Write($hash,undef,undef,undef);
        Log3 $name, 3, "GardenaSmartBridge ($name) - fetch locations id";
        readingsSingleUpdate($hash,'token',$hash->{helper}{session_id},1);
        
        return;
    
    } elsif( not defined($hash->{helper}{locations_id}) and defined($decode_json->{locations}) and ref($decode_json->{locations}) eq "ARRAY" and scalar(@{$decode_json->{locations}}) > 0) {
    
        foreach my $location ( @{$decode_json->{locations}} ) {
        
            $hash->{helper}{locations_id}    = $location->{id};

            GardenaSmartBridge_WriteReadings($hash,$location);
        }
        
        Log3 $name, 3, "GardenaSmartBridge ($name) - processed locations id. ID ist " . $hash->{helper}{locations_id};
        GardenaSmartBridge_Write($hash,undef,undef,undef);
        
        return;
        
    } elsif( defined($decode_json->{devices}) and ref($decode_json->{devices}) eq "ARRAY" and scalar(@{$decode_json->{devices}}) > 0) {

        my @buffer   = split('"devices":\[',$json);
        
        
        my ($json,$tail) = GardenaSmartBridge_ParseJSON($hash, $buffer[1]);


        while($json) {
        
            Log3 $name, 5, "GardenaSmartBridge ($name) - Decoding JSON message. Length: " . length($json) . " Content: " . $json;
            Log3 $name, 5, "GardenaSmartBridge ($name) - Vor Sub: Laenge JSON: " . length($json) . " Content: " . $json . " Tail: " . $tail;
            
            
            unless( not defined($tail) and not ($tail) ) {
            
                $decode_json =   eval{decode_json($json)};
                if($@){
                    Log3 $name, 3, "GardenaSmartBridge ($name) - JSON error while request: $@";
                }
                
                Dispatch($hash,$json,undef)
                unless( $decode_json->{category} eq 'gateway' );
            }
            
            ($json,$tail) = GardenaSmartBridge_ParseJSON($hash, $tail);
        
            Log3 $name, 5, "GardenaSmartBridge ($name) - Nach Sub: Laenge JSON: " . length($json) . " Content: " . $json . " Tail: " . $tail;
        }

        return;
    }

        Log3 $name, 3, "GardenaSmartBridge ($name) - no Match for processing data"
}

sub GardenaSmartBridge_WriteReadings($$) {

    my ($hash,$decode_json)     = @_;
    my $name                    = $hash->{NAME};


    if( defined($decode_json->{id}) and $decode_json->{id} and defined($decode_json->{name}) and $decode_json->{name} ) {

        readingsBeginUpdate($hash);
        readingsBulkUpdateIfChanged($hash,'name',$decode_json->{name});
        readingsBulkUpdateIfChanged($hash,'authorized_user_ids',scalar(@{$decode_json->{authorized_user_ids}}));
        readingsBulkUpdateIfChanged($hash,'devices',scalar(@{$decode_json->{devices}}));
        
        while( ( my ($t,$v) ) = each %{$decode_json->{geo_position}} ) {
            $v  = encode_utf8($v);
            readingsBulkUpdateIfChanged($hash,$t,$v);
        }
        
        readingsBulkUpdateIfChanged($hash,'zones',scalar(@{$decode_json->{zones}}));
        readingsEndUpdate( $hash, 1 );
    }

    Log3 $name, 3, "GardenaSmartBridge ($name) - readings would be written";
}


####################################
####################################
#### my little helpers Sub's #######

sub GardenaSmartBridge_getDevices($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    GardenaSmartBridge_Write($hash,undef,undef,undef);
    Log3 $name, 4, "GardenaSmartBridge ($name) - fetch device list and device states";
}

sub GardenaSmartBridge_getToken($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    
    delete $hash->{helper}{session_id}      if( defined($hash->{helper}{session_id}) and $hash->{helper}{session_id} );
    delete $hash->{helper}{user_id}         if( defined($hash->{helper}{user_id}) and $hash->{helper}{user_id} );
    delete $hash->{helper}{locations_id}    if( defined($hash->{helper}{locations_id}) and $hash->{helper}{locations_id} );
        
    GardenaSmartBridge_Write($hash,'"sessions": {"email": "'.GardenaSmartBridge_decrypt($hash->{helper}{username}).'","password": "'.GardenaSmartBridge_decrypt($hash->{helper}{password}).'"}',undef,undef);
    
    Log3 $name, 3, "GardenaSmartBridge ($name) - send credentials to fetch Token and locationId";
    
    RemoveInternalTimer($hash);
    InternalTimer( gettimeofday()+$hash->{INTERVAL},"GardenaSmartBridge_InternalTimerGetDeviceData", $hash, 1 );
}

sub GardenaSmartBridge_encrypt($) {

    my ($decoded) = @_;
    my $key = getUniqueId();
    my $encoded;

    return $decoded if( $decoded =~ /crypt:/ );

    for my $char (split //, $decoded) {
        my $encode = chop($key);
        $encoded .= sprintf("%.2x",ord($char)^ord($encode));
        $key = $encode.$key;
    }

    return 'crypt:'.$encoded;
}

sub GardenaSmartBridge_decrypt($) {

    my ($encoded) = @_;
    my $key = getUniqueId();
    my $decoded;

    return $encoded if( $encoded !~ /crypt:/ );
  
    $encoded = $1 if( $encoded =~ /crypt:(.*)/ );

    for my $char (map { pack('C', hex($_)) } ($encoded =~ /(..)/g)) {
        my $decode = chop($key);
        $decoded .= chr(ord($char)^ord($decode));
        $key = $decode.$key;
    }

    return $decoded;
}

sub GardenaSmartBridge_ParseJSON($$) {

    my ($hash, $buffer) = @_;
    
    my $name    = $hash->{NAME};
    my $open    = 0;
    my $close   = 0;
    my $msg     = '';
    my $tail    = '';
    
    
    if($buffer) {
        foreach my $c (split //, $buffer) {
            if($open == $close && $open > 0) {
                $tail .= $c;
                Log3 $name, 5, "GardenaSmartBridge ($name) - $open == $close && $open > 0";
                
            } elsif(($open == $close) && ($c ne '{')) {
            
                Log3 $name, 5, "GardenaSmartBridge ($name) - Garbage character before message: " . $c;
        
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
    
    Log3 $name, 4, "GardenaSmartBridge ($name) - return msg: $msg and tail: $tail";
    return ($msg,$tail);
}

sub GardenaSmartBridge_createHttpValueStrings($@) {

    my ($hash,$payload,$deviceId,$abilities)  = @_;
    my $session_id                  = $hash->{helper}{session_id};
    my $header                      = "Content-Type: application/json";
    my $uri                         = '';
    my $method                      = 'POST';
    $header                         .= "\r\nX-Session: $session_id"                                         if( defined($hash->{helper}{session_id}) );
    $payload                        = '{' . $payload . '}'                                                  if( defined($payload) );
    $payload                        = '{}'                                                                  if( not defined($payload) );


    if( $payload eq '{}' ) {
        $method                         = 'GET';
        $uri                            .= '/locations/?user_id=' . $hash->{helper}{user_id}                if( not defined($hash->{helper}{locations_id}) );
            readingsSingleUpdate($hash,'state','fetch locationId',1)                                        if( not defined($hash->{helper}{locations_id}) );
        $uri                            .= '/sessions'                                                      if( not defined($hash->{helper}{session_id}));
        $uri                            .= '/devices'                                                       if( not defined($abilities) and defined($hash->{helper}{locations_id}) );
    }
    
    $uri                            .= '/sessions'                                                          if( not defined($hash->{helper}{session_id}));
    
    if( defined($hash->{helper}{locations_id}) ) {
        $uri                            .= '/devices/' . $deviceId . '/abilities/' . $abilities . '/command'    if( defined($abilities) and defined($payload) );
        $uri                            .= '?locationId=' . $hash->{helper}{locations_id};
    }

    return ($payload,$session_id,$header,$uri,$method,$deviceId,$abilities);
}




1;






=pod

=item device
=item summary       Modul to communicate with the GardenaCloud
=item summary_DE    Modul zur Datenübertragung zur GardenaCloud

=begin html

<a name="GardenaSmartBridge"></a>
<h3>GardenaSmartBridge</h3>
<ul>
  <u><b>Prerequisite</b></u>
  <br><br>
  <li>In combination with GardenaSmartDevice this FHEM Module controls the communication between the GardenaCloud and connected Devices like Mover, Watering_Computer, Temperature_Sensors</li>
  <li>Installation of the following packages: apt-get install libio-socket-ssl-perl</li>
  <li>The Gardena-Gateway and all connected Devices must be correctly installed in the GardenaAPP</li>
</ul>
<br>
<a name="GardenaSmartBridgedefine"></a>
<b>Define</b>
<ul><br>
  <code>define &lt;name&gt; GardenaSmartBridge &lt;Account-EMail&gt; &lt;Account-Passwort&gt;</code>
  <br><br>
  Beispiel:
  <ul><br>
    <code>define Gardena_Bridge GardenaSmartBridge me@email.me secret</code><br>
  </ul>
  <br>
  &lt;Account-EMail&gt; Email Adresse which was used in the GardenaAPP<br>
  &lt;Account-Passwort&gt; Passwort which was used in the GardenaAPP<br>
  The GardenaSmartBridge device is created in the room GardenaSmart, then the devices of Your system are recognized automatically and created in FHEM. From now on the devices can be controlled and changes in the GardenaAPP are synchronized with the state and readings of the devices.
  <br><br>
  <a name="GardenaSmartBridgereadings"></a>
  <br><br>
  <b>Readings</b>
  <ul>
    <li>address - your Adress (Longversion)</li>
    <li>authorized_user_ids - </li>
    <li>city - Zip, City</li>
    <li>devices - Number of Devices in the Cloud (Gateway included)</li>
    <li>lastRequestState - Last Status Result</li>
    <li>latitude - Breitengrad des Grundstücks</li>
    <li>longitude - Längengrad des Grundstücks</li>
    <li>name - Name of your Garden – Default „My Garden“</li>
    <li>state - State of the Bridge</li>
    <li>token - SessionID</li>
    <li>zones - </li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeset"></a>
  <b>set</b>
  <ul>
    <li>getDeviceState - Starts a Datarequest</li>
    <li>getToken - Gets a new Session-ID</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeattributes"></a>
  <b>Attributes</b>
  <ul>
    <li>debugJSON - </li>
    <li>disable - Disables the Bridge</li>
    <li>interval - Interval in seconds (Default=300)</li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="GardenaSmartBridge"></a>
<h3>GardenaSmartBridge</h3>
<ul>
  <u><b>Voraussetzungen</b></u>
  <br><br>
  <li>Zusammen mit dem Device GardenaSmartDevice stellt dieses FHEM Modul die Kommunikation zwischen der GardenaCloud und Fhem her. Es k&ouml;nnen damit Rasenm&auml;her, Bew&auml;sserungscomputer und Bodensensoren überwacht und gesteuert werden</li>
  <li>Das Perl-Modul "SSL Packet" wird ben&ouml;tigt.</li>
  <li>Unter Debian (basierten) System, kann dies mittels "apt-get install libio-socket-ssl-perl" installiert werden.</li>
  <li>Das Gardena-Gateway und alle damit verbundenen Ger&auml;te und Sensoren m&uuml;ssen vorab in der GardenaApp eingerichtet sein.</li>
</ul>
<br>
<a name="GardenaSmartBridgedefine"></a>
<b>Define</b>
<ul><br>
  <code>define &lt;name&gt; GardenaSmartBridge &lt;Account-EMail&gt; &lt;Account-Passwort&gt;</code>
  <br><br>
  Beispiel:
  <ul><br>
    <code>define Gardena_Bridge GardenaSmartBridge me@email.me secret</code><br>
  </ul>
  <br>
  &lt;Account-EMail&gt; Email Adresse, die auch in der GardenaApp verwendet wurde<br>
  &lt;Account-Passwort&gt; Passwort, welches in der GardenaApp verwendet wurde<br>
  Das Bridge Device wird im Raum GardenaSmart angelegt und danach erfolgt das Einlesen und automatische Anlegen der Ger&auml;te. Von nun an k&ouml;nnen die eingebundenen Ger&auml;te gesteuert werden. &Auml;nderungen in der APP werden mit den Readings und dem Status syncronisiert.
  <br><br>
  <a name="GardenaSmartBridgereadings"></a>
  <br><br>
  <b>Readings</b>
  <ul>
    <li>address - Adresse, welche in der App eingetragen wurde (Langversion)</li>
    <li>authorized_user_ids - </li>
    <li>city - PLZ, Stadt</li>
    <li>devices - Anzahl der Ger&auml;te, welche in der GardenaCloud angemeldet sind (Gateway z&auml;hlt mit)</li>
    <li>lastRequestState - Letzter abgefragter Status der Bridge</li>
    <li>latitude - Breitengrad des Grundst&uuml;cks</li>
    <li>longitude - Längengrad des Grundst&uuml;cks</li>
    <li>name - Name für das Grundst&uuml;ck – Default „My Garden“</li>
    <li>state - Status der Bridge</li>
    <li>token - SessionID</li>
    <li>zones - </li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeset"></a>
  <b>set</b>
  <ul>
    <li>getDeviceState - Startet eine Abfrage der Daten.</li>
    <li>getToken - Holt eine neue Session-ID</li>
  </ul>
  <br><br>
  <a name="GardenaSmartBridgeattributes"></a>
  <b>Attribute</b>
  <ul>
    <li>debugJSON - JSON Fehlermeldungen</li>
    <li>disable - Schaltet die Daten&uuml;bertragung der Bridge ab</li>
    <li>interval - Abfrageinterval in Sekunden (default: 300)</li>
  </ul>
</ul>

=end html_DE
=cut

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
use Blocking;

my $version = "0.2.5";




sub HOMBOT_Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}	= "HOMBOT_Set";
    $hash->{DefFn}	= "HOMBOT_Define";
    $hash->{UndefFn}	= "HOMBOT_Undef";
    $hash->{AttrFn}	= "HOMBOT_Attr";
    $hash->{FW_detailFn}  = "HOMBOT_DetailFn";
    
    $hash->{AttrList} 	= "interval ".
                "disable:1 ".
                $readingFnAttributes;



    foreach my $d(sort keys %{$modules{HOMBOT}{defptr}}) {
        my $hash = $modules{HOMBOT}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub HOMBOT_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    

    return "too few parameters: define <name> HOMBOT <HOST>" if( @a != 3 );
    return "please check if ssh installed" unless( -X "/usr/bin/ssh" );
    return "please check if $attr{global}{modpath}/.ssh/known_hosts or /root/.ssh/known_hosts exist" unless( -R "$attr{global}{modpath}/.ssh/known_hosts" or -R "/root/.ssh/known_hosts" );
    return "please check if sshpass installed" unless( -X "/usr/bin/sshpass" or -X "/usr/local/bin/sshpass" );
    


    my $name    	= $a[0];
    my $host    	= $a[2];
    my $port		= 6260;
    my $interval  	= 180;

    $hash->{HOST} 	= $host;
    $hash->{PORT} 	= $port;
    $hash->{INTERVAL} 	= $interval;
    $hash->{VERSION} 	= $version;
    $hash->{helper}{requestErrorCounter} = 0;
    $hash->{helper}{setErrorCounter} = 0;
    $hash->{helper}{sshpass} = "/usr/bin/sshpass";
    $hash->{helper}{sshpass} = "/usr/local/bin/sshpass" unless( -X "/usr/bin/sshpass");


    Log3 $name, 3, "HOMBOT ($name) - defined with host $hash->{HOST} on port $hash->{PORT} and interval $hash->{INTERVAL} (sec)";

    $attr{$name}{room} = "HOMBOT" if( !defined( $attr{$name}{room} ) );    # sorgt für Diskussion, überlegen ob nötig
    readingsSingleUpdate ( $hash, "hombotState", "ONLINE", 1 );
    readingsSingleUpdate ( $hash, "state", "initialized", 1 );
    readingsSingleUpdate( $hash, "luigiHttpSrvState", "running", 1 );

    HOMBOT_Get_stateRequestLocal( $hash );      # zu Testzwecken mal eingebaut
    InternalTimer( gettimeofday()+$hash->{INTERVAL}, "HOMBOT_Get_stateRequest", $hash, 0 );
    
    $modules{HOMBOT}{defptr}{$hash->{HOST}} = $hash;

    return undef;
}

sub HOMBOT_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    delete $modules{HOMBOT}{defptr}{$hash->{HOST}};
    RemoveInternalTimer( $hash );
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    
    return undef;
}

sub HOMBOT_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if( $attrName eq "disable" ) {
        if( $cmd eq "set" ) {
            if( $attrVal eq "0" ) {
            RemoveInternalTimer( $hash );
            InternalTimer( gettimeofday()+2, "HOMBOT_Get_stateRequest", $hash, 0 ) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HOMBOT ($name) - enabled";
            } else {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            RemoveInternalTimer( $hash );
            Log3 $name, 3, "HOMBOT ($name) - disabled";
            }
        }
        elsif( $cmd eq "del" ) {
            RemoveInternalTimer( $hash );
            InternalTimer( gettimeofday()+2, "HOMBOT_Get_stateRequest", $hash, 0 ) if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "disabled" );
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "HOMBOT ($name) - enabled";

        } else {
            if($cmd eq "set") {
            $attr{$name}{$attrName} = $attrVal;
            Log3 $name, 3, "HOMBOT ($name) - $attrName : $attrVal";
            }
            elsif( $cmd eq "del" ) {
            }
        }
        }
        
        if( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            if( $attrVal < 60 ) {
            Log3 $name, 3, "HOMBOT ($name) - interval too small, please use something > 60 (sec), default is 180 (sec)";
            return "interval too small, please use something > 60 (sec), default is 180 (sec)";
            } else {
            $hash->{INTERVAL} = $attrVal;
            Log3 $name, 3, "HOMBOT ($name) - set interval to $attrVal";
            }
        }
        elsif( $cmd eq "del" ) {
            $hash->{INTERVAL} = 180;
            Log3 $name, 3, "HOMBOT ($name) - set interval to default";
        
        } else {
            if( $cmd eq "set" ) {
            $attr{$name}{$attrName} = $attrVal;
            Log3 $name, 3, "HOMBOT ($name) - $attrName : $attrVal";
            }
            elsif( $cmd eq "del" ) {
            }
        }
    }
    
    return undef;
}

sub HOMBOT_Get_stateRequestLocal($) {

my ( $hash ) = @_;
    my $name = $hash->{NAME};

    HOMBOT_RetrieveHomebotInfomations( $hash ) if( AttrVal( $name, "disable", 0 ) ne "1" );
    
    return 0;
}

sub HOMBOT_Get_stateRequest($) {

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    
 
    HOMBOT_RetrieveHomebotInfomations( $hash ) if( ReadingsVal( $name, "hombotState", "OFFLINE" ) ne "OFFLINE" && AttrVal( $name, "disable", 0 ) ne "1" );

    InternalTimer( gettimeofday()+$hash->{INTERVAL}, "HOMBOT_Get_stateRequest", $hash, 1 );
    
    Log3 $name, 4, "HOMBOT ($name) - Call HOMBOT_Get_stateRequest";

    return 1;
}

sub HOMBOT_RetrieveHomebotInfomations($) {
    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    
    HOMBOT_getStatusTXT( $hash );
    HOMBOT_getSchedule( $hash ) if( ReadingsVal( "$name","hombotState","WORKING" ) eq "CHARGING" || ReadingsVal( "$name","hombotState","WORKING" ) eq "STANDBY" );
    HOMBOT_getStatisticHTML( $hash ) if( ReadingsVal( "$name","hombotState","WORKING" ) eq "CHARGING" || ReadingsVal( "$name","hombotState","WORKING" ) eq "STANDBY" );
    
    return undef;
}

sub HOMBOT_getStatusTXT($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};

    
    my $url = "http://" . $host . ":" . $port . "/status.txt";


    HttpUtils_NonblockingGet(
    {
        url         => $url,
        timeout     => 10,
        hash        => $hash,
        method      => "GET",
        doTrigger   => 1,
        callback    => \&HOMBOT_RetrieveHomebotInfoFinished,
        id          => "statustxt",
    });
    
    Log3 $name, 4, "HOMBOT ($name) - NonblockingGet get URL";
    Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Retrieve status.txt Information: calling Host: $host";
}

sub HOMBOT_getStatisticHTML($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};

    
    my $url = "http://" . $host . ":" . $port . "/sites/statistic.html";


    HttpUtils_NonblockingGet(
    {
        url         => $url,
        timeout     => 10,
        hash        => $hash,
        method      => "GET",
        doTrigger   => 1,
        callback    => \&HOMBOT_RetrieveHomebotInfoFinished,
        id          => "statistichtml",
    });
    
    Log3 $name, 4, "HOMBOT ($name) - NonblockingGet get URL";
    Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Retrieve statistic.html Information: calling Host: $host";
}

sub HOMBOT_getSchedule($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};

    
    my $url = "http://" . $host . ":" . $port . "/sites/schedule.html";


    HttpUtils_NonblockingGet(
    {
        url         => $url,
        timeout     => 10,
        hash        => $hash,
        method      => "GET",
        doTrigger   => 1,
        callback    => \&HOMBOT_RetrieveHomebotInfoFinished,
        id          => "schedule",
    });
    
    Log3 $name, 4, "HOMBOT ($name) - NonblockingGet get URL";
    Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Retrieve Schedule Information: calling Host: $host";
}

sub HOMBOT_RetrieveHomebotInfoFinished($$$) {

    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $parsid = $param->{id};
    my $doTrigger = $param->{doTrigger};
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};

    Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Response Infomations: processed response data";



    ### Begin Error Handling
    if( $hash->{helper}{requestErrorCounter} > 1 ) {

    readingsSingleUpdate( $hash, "lastStatusRequestState", "statusRequest_error", 1 );

        if( $hash->{helper}{requestErrorCounter} > 1 && ReadingsVal( $name, "luigiHttpSrvState", "not running" ) eq "running"  ) {
        
                Log3 $name, 3, "HOMBOT ($name) - Connecting Problem, will check Luigi HTTP Server" unless(exists($hash->{helper}{RUNNING_PID}));
                
                $hash->{helper}{RUNNING_PID} = BlockingCall("HOMBOT_Check_Bot_Alive", $name."|request", "HOMBOT_Evaluation_Bot_Alive", 15, "HOMBOT_Aborted_Bot_Alive", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
        }

        readingsBeginUpdate( $hash );

        if( $hash->{helper}{requestErrorCounter} > 6 && $hash->{helper}{setErrorCounter} > 3 && ReadingsVal( $name, "luigiHttpSrvState", "running" ) eq "running" ) {

            readingsBulkUpdate( $hash, "lastStatusRequestError", "unknown error, please contact the developer" );

            Log3 $name, 4, "HOMBOT ($name) - UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";

            $attr{$name}{disable} = 1;
            readingsBulkUpdate ( $hash, "state", "Unknown Error, device disabled");

            $hash->{helper}{requestErrorCounter} = 0;
            $hash->{helper}{setErrorCounter} = 0;

            return;
        }

        if( $hash->{helper}{requestErrorCounter} > 6 && $hash->{helper}{setErrorCounter} == 0 && ReadingsVal( $name, "luigiHttpSrvState", "running" ) eq "running" ) {
            readingsBulkUpdate( $hash, "lastStatusRequestError", "Homebot is offline" );

            Log3 $name, 4, "HOMBOT ($name) - Homebot is offline";

            readingsBulkUpdate ( $hash, "hombotState", "OFFLINE");
            readingsBulkUpdate ( $hash, "state", "Homebot offline");

            $hash->{helper}{requestErrorCounter} = 0;
            $hash->{helper}{setErrorCounter} = 0;

            return;
        }

        elsif( $hash->{helper}{requestErrorCounter} > 6 && $hash->{helper}{setErrorCounter} > 0 && ReadingsVal( $name, "luigiHttpSrvState", "running" ) eq "running" ) {
            readingsBulkUpdate( $hash, "lastStatusRequestError", "to many errors, check your network configuration" );

            Log3 $name, 4, "HOMBOT ($name) - To many Errors please check your Network Configuration";

            readingsBulkUpdate ( $hash, "hombotState", "OFFLINE");
            readingsBulkUpdate ( $hash, "state", "To many Errors");
            $hash->{helper}{requestErrorCounter} = 0;
        }
    
    readingsEndUpdate( $hash, 1 );
    
    }
    
    if( defined( $err ) && $err ne "" ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate ( $hash, "state", "$err") if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
        $hash->{helper}{requestErrorCounter} = ( $hash->{helper}{requestErrorCounter} + 1 );

        readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
        readingsBulkUpdate($hash, "lastStatusRequestError", $err );

        readingsEndUpdate( $hash, 1 );

        Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Parse_HomebotInfomations: error while request: $err";
        return;
    }

    elsif( $data eq "" and exists( $param->{code} ) ) {
        readingsBeginUpdate( $hash );
        readingsBulkUpdate ( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state", 1 ) ne "initialized" );
        $hash->{helper}{requestErrorCounter} = ( $hash->{helper}{requestErrorCounter} + 1 );
    
        readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
        if( $param->{code} ne 200 ) {
            readingsBulkUpdate( $hash," lastStatusRequestError", "http Error ".$param->{code} );
        }

        readingsBulkUpdate( $hash, "lastStatusRequestError", "empty response" );
        readingsEndUpdate( $hash, 1 );

        Log3 $name, 4, "HOMBOT ($name) - HOMBOT_RetrieveHomebotInfomationsFinished: received http code ".$param->{code}." without any data after requesting HOMBOT Device";

        return;
    }

    elsif( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state" ,0) ne "initialized" );
        $hash->{helper}{requestErrorCounter} = ( $hash->{helper}{requestErrorCounter} + 1 );

        readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_error" );
    
        if( $param->{code} eq 404 ) {
            readingsBulkUpdate( $hash, "lastStatusRequestError", "HTTP Server at Homebot offline" );
        } else {
            readingsBulkUpdate( $hash, "lastStatusRequestError", "http error ".$param->{code} );
        }

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Parse_HomebotInfomations: received http code ".$param->{code}." receive Error after requesting HOMBOT";

        return;
    }

    ### End Error Handling

    $hash->{helper}{requestErrorCounter} = 0;
    $hash->{helper}{setErrorCounter} = 0;
 
    ### Begin Parse Processing
    readingsSingleUpdate( $hash, "state", "active", 1) if( ReadingsVal( $name, "state", 0 ) ne "initialized" or ReadingsVal( $name, "state", 0 ) ne "active" );
    
    my $previousHombotState = ReadingsVal( $name, "hombotState", "none" );
    

    readingsBeginUpdate( $hash );
    
    
    my $t;      # fuer Readings Name
    my $v;      # fuer Readings Value
    
    if( $parsid eq "statustxt" ) {
    
        Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Parse_status.txt";
    
        my @valuestring = split( '\R',  $data );
        my %buffer;
    
        foreach( @valuestring ) {
    
            my @values = split( '="' , $_ );
            $buffer{$values[0]} = $values[1];
        }
    
        while( ( $t, $v ) = each %buffer ) {
    
            $v =~ tr/"//d;
            $t =~ s/CPU_IDLE/cpu_IDLE/g;
            $t =~ s/CPU_USER/cpu_USER/g;
            $t =~ s/CPU_SYS/cpu_SYS/g;
            $t =~ s/CPU_NICE/cpu_NICE/g;
            $t =~ s/JSON_MODE/cleanMode/g;
            $t =~ s/JSON_NICKNAME/nickname/g;
            $t =~ s/JSON_REPEAT/repeat/g;
            $t =~ s/JSON_TURBO/turbo/g;
            $t =~ s/JSON_ROBOT_STATE/hombotState/g;
            $t =~ s/CLREC_CURRENTBUMPING/currentBumping/g;
            
            if( $t eq "CLREC_LAST_CLEAN" ) {
                my @lctime = split( '/' , $v );
                $v = $lctime[2].".".$lctime[1].".".$lctime[0]." ".$lctime[3].":".$lctime[4];
                $t = "lastClean";
            }
            
            $t =~ s/JSON_BATTPERC/batteryPercent/g;
            $t =~ s/JSON_VERSION/firmware/g;
            $t =~ s/LGSRV_VERSION/luigiSrvVersion/g;
            
            
            readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/[a-z]/s && defined( $t ) && defined( $v ) );
        }
        
        readingsBulkUpdate( $hash, "hombotState", "UNKNOWN" ) if( ReadingsVal( $name, "hombotState", "UNKNOWN" ) eq "" );
    }
    
    elsif( $parsid eq "statistichtml" ) {
    
        Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Parse_statistic.html";
        
        while( $data =~ m/<th>(.*?):<\/th>\s*<td>(.*?)<\/td>/g ) {
            $t = $1 if( defined( $1 ) );
            $v = $2 if( defined( $2 ) );
            
            $t =~ s/NUM START ZZ/numZZ_Begin/g;
            $t =~ s/NUM FINISH ZZ/numZZ_Ende/g;
            $t =~ s/NUM START SB/numSB_Begin/g;
            $t =~ s/NUM FINISH SB/numSB_Ende/g;
            $t =~ s/NUM START SPOT/numSPOT_Begin/g;
            $t =~ s/NUM FINISH SPOT/numSPOT_Ende/g;
            
            readingsBulkUpdate( $hash, $t, $v ) if( $t =~ m/num/s );
        }
    }
    
    elsif ( $parsid eq "schedule" ) {
    
        Log3 $name, 4, "HOMBOT ($name) - HOMBOT_Parse_schedule.html";
        
        my $i = 0;
        
        while( $data =~ m/name="(.*?)"\s*size="20" maxlength="20" value="(.*?)"/g ) {
            $t = $1 if( defined( $1 ) );
            $v = $2 if( defined( $2 ) );

            readingsBulkUpdate( $hash, "at_".$i."_".$t, $v );
            $i = ++$i;
        }
    }


    readingsBulkUpdate( $hash, "lastStatusRequestState", "statusRequest_done" );
    
    $hash->{helper}{requestErrorCounter} = 0;
    ### End Response Processing
    
    readingsBulkUpdate( $hash, "luigiHttpSrvState", "running" );
    
    readingsBulkUpdate( $hash, "state", "active" ) if( ReadingsVal( $name, "state", 0 ) eq "initialized" );
    readingsEndUpdate( $hash, 1 );
    
    $hash->{PREVIOUSHOMBOTSTATE} = $previousHombotState if( $previousHombotState ne ReadingsVal( $name, "hombotState", "none" ) );
    
    ## verändert das INTERVAL in Abhängigkeit vom Arbeitsstatus des Bots
    if( ReadingsVal( $name, "hombotState", "CHARGING" ) eq "WORKING" || ReadingsVal( $name, "hombotState", "CHARGING" ) eq "HOMING" || ReadingsVal( $name, "hombotState", "CHARGING" ) eq "DOCKING" ) {
        
        $hash->{INTERVAL} = 30;

    } else {
        my $interval = AttrVal( $name, "interval", 0 );
    
        if( $interval > 0 ) {
            $hash->{INTERVAL} = $interval;
        } else {
            $hash->{INTERVAL} = 180;
        }
    }




    return undef;
}

sub HOMBOT_Set($$@) {
    
    my ( $hash, $name, $cmd, @val ) = @_;


    my $list = "";
    $list .= "cleanStart:noArg ";
    $list .= "homing:noArg ";
    $list .= "pause:noArg ";
    $list .= "statusRequest:noArg ";
    $list .= "cleanMode:SB,ZZ,SPOT ";
    $list .= "repeat:true,false ";
    $list .= "turbo:true,false ";
    $list .= "nickname ";
    $list .= "schedule ";


    if( lc $cmd eq 'cleanstart'
        || lc $cmd eq 'homing'
        || lc $cmd eq 'pause'
        || lc $cmd eq 'statusrequest'
        || lc $cmd eq 'cleanmode'
        || lc $cmd eq 'repeat'
        || lc $cmd eq 'turbo' 
        || lc $cmd eq 'nickname'
        || lc $cmd eq 'schedule' ) {

        Log3 $name, 5, "HOMBOT ($name) - set $name $cmd ".join(" ", @val);


        my $val = join( " ", @val );
        my $wordlenght = length($val);

        return HOMBOT_SelectSetCmd( $hash, $cmd, @val ) if( lc $cmd eq 'statusrequest' );
        return "set command only works if state not equal initialized, please wait for next interval run" if( ReadingsVal( $hash->{NAME}, "state", 0 ) eq "initialized");
        return "to many character for Nickname" if(( $wordlenght < 2 || $wordlenght > 16 ) && lc $cmd eq 'nickname' );

        return HOMBOT_SelectSetCmd( $hash, $cmd, @val ) if( ( ( @val ) || lc $cmd eq 'cleanstart'|| lc $cmd eq 'homing' || lc $cmd eq 'pause' ) );
    }

    return "Unknown argument $cmd, bearword as argument or wrong parameter(s), choose one of $list";
}

sub HOMBOT_SelectSetCmd($$@) {

    my ( $hash, $cmd, @data ) = @_;
    my $name = $hash->{NAME};
    my $host = $hash->{HOST};
    my $port = $hash->{PORT};

    if( lc $cmd eq 'cleanstart' ) {

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22COMMAND%22:%22CLEAN_START%22%7d";

        Log3 $name, 4, "HOMBOT ($name) - Homebot start cleaning";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'homing' ) {

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22COMMAND%22:%22HOMING%22%7d";

        Log3 $name, 4, "HOMBOT ($name) - Homebot come home";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'pause' ) {

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22COMMAND%22:%22PAUSE%22%7d";

        Log3 $name, 4, "HOMBOT ($name) - Homebot paused";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'cleanmode' ) {
        my $mode = join( " ", @data );

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22COMMAND%22:%7b%22CLEAN_MODE%22:%22CLEAN_".$mode."%22%7d%7d";

        Log3 $name, 4, "HOMBOT ($name) - set Cleanmode to $mode";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'statusrequest' ) {
        HOMBOT_Get_stateRequestLocal( $hash );
        return undef;
    }
    
    elsif( lc $cmd eq 'repeat' ) {
        my $repeat = join( " ", @data );

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22COMMAND%22:%7b%22REPEAT%22:%22".$repeat."%22%7d%7d";

        Log3 $name, 4, "HOMBOT ($name) - set Repeat to $repeat";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'turbo' ) {
        my $turbo = join( " ", @data );

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22COMMAND%22:%7b%22TURBO%22:%22".$turbo."%22%7d%7d";

        Log3 $name, 4, "HOMBOT ($name) - set Turbo to $turbo";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'nickname' ) {
        my $nick = join( " ", @data );

        my $url = "http://" . $host . ":" . $port . "/json.cgi?%7b%22NICKNAME%22:%7b%22SET%22:%22".$nick."%22%7d%7d";

        Log3 $name, 4, "HOMBOT ($name) - set Nickname to $nick";

        return HOMBOT_HTTP_POST( $hash,$url );
    }
    
    elsif( lc $cmd eq 'schedule' ) {

        #my $mo = $data[0];
        $data[0] =~ s/Mo/MONDAY/g;
        #my $tu = $data[1];
        $data[1] =~ s/Di/TUESDAY/g;
        #my $we = $data[2];
        $data[2] =~ s/Mi/WEDNESDAY/g;
        #my $th = $data[3];
        $data[3] =~ s/Do/THURSDAY/g;
        #my $fr = $data[4];
        $data[4] =~ s/Fr/FRIDAY/g;
        #my $sa = $data[5];
        $data[5] =~ s/Sa/SATURDAY/g;
        #my $su = $data[6];
        $data[6] =~ s/So/SUNDAY/g;

        my $url = "http://" . $host . ":" . $port . "/sites/schedule.html?".$data[0]."&".$data[1]."&".$data[2]."&".$data[3]."&".$data[4]."&".$data[5]."&".$data[6]."&SEND=Save";

        Log3 $name, 4, "HOMBOT ($name) - set schedule to $data[0],$data[1],$data[2],$data[3],$data[4],$data[5],$data[6]";

        return HOMBOT_HTTP_POST( $hash,$url );
    }

    return undef;
}

sub HOMBOT_HTTP_POST($$) {

    my ( $hash, $url ) = @_;
    my $name = $hash->{NAME};
    
    my $state = ReadingsVal( $name, "state", 0 );
    
    readingsSingleUpdate( $hash, "state", "Send HTTP POST", 1 );
    
    HttpUtils_NonblockingGet(
    {
        url         => $url,
        timeout     => 10,
        hash        => $hash,
        method      => "GET",
        doTrigger   => 1,
        callback    => \&HOMBOT_HTTP_POSTerrorHandling,
    });
    
    Log3 $name, 4, "HOMBOT ($name) - Send HTTP POST with URL $url";

    readingsSingleUpdate( $hash, "state", $state, 1 );

    return undef;
}

sub HOMBOT_HTTP_POSTerrorHandling($$$) {

    my ( $param, $err, $data ) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    

    ### Begin Error Handling
    if( $hash->{helper}{setErrorCounter} > 1 ) {

        readingsSingleUpdate( $hash, "lastSetCommandState", "statusRequest_error", 1 );


        if( $hash->{helper}{setErrorCounter} > 1 && ReadingsVal( $name, "luigiHttpSrvState", "not running" ) eq "running"  ) {

            Log3 $name, 3, "HOMBOT ($name) - Connecting Problem, will check Luigi HTTP Server" unless(exists($hash->{helper}{RUNNING_PID}));
            
            $hash->{helper}{RUNNING_PID} = BlockingCall("HOMBOT_Check_Bot_Alive", $name."|set", "HOMBOT_Evaluation_Bot_Alive", 15, "HOMBOT_Aborted_Bot_Alive", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
        }
        
        readingsBeginUpdate( $hash );

        if( $hash->{helper}{requestErrorCounter} > 6 && $hash->{helper}{setErrorCounter} > 2 && ReadingsVal( $name, "luigiHttpSrvState", "running" ) eq "running" ) {
            readingsBulkUpdate($hash, "lastSetCommandError", "unknown error, please contact the developer" );

            Log3 $name, 4, "HOMBOT ($name) - UNKNOWN ERROR, PLEASE CONTACT THE DEVELOPER, DEVICE DISABLED";

            $attr{$name}{disable} = 1;
            readingsBulkUpdate( $hash, "state", "Unknown Error" );
            $hash->{helper}{requestErrorCounter} = 0;
            $hash->{helper}{setErrorCounter} = 0;

            return;
        }

        elsif( $hash->{helper}{setErrorCounter} > 3 && ReadingsVal( $name, "luigiHttpSrvState", "running" ) eq "not running" ){
            readingsBulkUpdate( $hash, "lastSetCommandError", "HTTP Server at Homebot offline" );
            readingsBulkUpdate ( $hash, "hombotState", "OFFLINE");

            Log3 $name, 4, "HOMBOT ($name) - Please check HTTP Server at Homebot";

            $hash->{helper}{requestErrorCounter} = 0;
            $hash->{helper}{setErrorCounter} = 0;
        } 

        elsif( $hash->{helper}{setErrorCounter} > 3 && ReadingsVal( $name, "luigiHttpSrvState", "running" ) eq "running" ) {
            readingsBulkUpdate( $hash, "lastSetCommandError", "to many errors, check your network or device configuration" );

            Log3 $name, 4, "HOMBOT ($name) - To many Errors please check your Network or Device Configuration";

            readingsBulkUpdate( $hash, "state", "To many Errors" );
            readingsBulkUpdate ( $hash, "hombotState", "OFFLINE");

            $hash->{helper}{setErrorCounter} = 0;
            $hash->{helper}{requestErrorCounter} = 0;
        }
        
        readingsEndUpdate( $hash, 1 );
    }
    
    if( defined( $err ) && $err ne "" ) {

        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "state", $err ) if( ReadingsVal( $name, "state", 0 ) ne "initialized" );
        $hash->{helper}{setErrorCounter} = ($hash->{helper}{setErrorCounter} + 1);

        readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_error" );
        readingsBulkUpdate( $hash, "lastSetCommandError", "$err" );
          
        readingsEndUpdate( $hash, 1 );

        Log3 $name, 5, "HOMBOT ($name) - HOMBOT_HTTP_POST: error while POST Command: $err";

        return;
    }
 
    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $hash, "state", 0 ) ne "initialized" );

        $hash->{helper}{setErrorCounter} = ( $hash->{helper}{setErrorCounter} + 1 );

        readingsBulkUpdate($hash, "lastSetCommandState", "cmd_error" );
        readingsBulkUpdate($hash, "lastSetCommandError", "http Error ".$param->{code} );
        readingsEndUpdate( $hash, 1 );

        Log3 $name, 5, "HOMBOT ($name) - HOMBOT_HTTP_POST: received http code ".$param->{code};

        return;
    }
        
    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, "state", $param->{code} ) if( ReadingsVal( $name, "state", 0 ) ne "initialized" );

        $hash->{helper}{setErrorCounter} = ( $hash->{helper}{setErrorCounter} + 1 );

        readingsBulkUpdate( $hash, "lastSetCommandState", "cmd_error" );
    
        if( $param->{code} eq 404 ) {
            readingsBulkUpdate( $hash, "lastSetCommandError", "HTTP Server at Homebot is offline!" );
        } else {
            readingsBulkUpdate( $hash, "lastSetCommandError", "http error ".$param->{code} );
        }

        return;
    }
    
    ### End Error Handling
    
    readingsSingleUpdate( $hash, "lastSetCommandState", "cmd_done", 1 );
    $hash->{helper}{requestErrorCounter} = 0;
    $hash->{helper}{setErrorCounter} = 0;
    
    HOMBOT_Get_stateRequestLocal( $hash );
    
    return undef;
}

sub HOMBOT_Check_Bot_Alive($) {

    my ($string) = @_;
    my ( $name, $callingtype ) = split("\\|", $string);
    
    my $hash = $defs{$name};
    my $host = $hash->{HOST};
    my $sshalive;
    my $sshpass = $hash->{helper}{sshpass};
    
    Log3 $name, 3, "HOMBOT ($name) - Start SSH Connection for check Hombot alive";
    
    
    $sshalive = qx($sshpass -p 'most9981' /usr/bin/ssh root\@$host 'uname' );
    
    if( $sshalive ) {
        
        my $lgSrvPID = ((split (/\s+/,qx($sshpass -p 'most9981' /usr/bin/ssh root\@$host 'ps | grep -v grep | grep /usr/bin/lg.srv' )))[1]);
            
        if( not defined( $lgSrvPID ) ) {

            qx($sshpass -p 'most9981' /usr/bin/ssh root\@$host '/usr/bin/lg.srv &' );
                
            return "$name|$callingtype|restarted";

        } else {

            return "$name|$callingtype|running";
        }
        
    } else {
    
        return "$name|$callingtype|offline";
    }
}

sub HOMBOT_Evaluation_Bot_Alive($) {

    my ( $string ) = @_;
    
    return unless(defined($string));
    
    my @a = split("\\|",$string);
    my $hash = $defs{$a[0]};
    my $name = $hash->{NAME};
    my $callingtype = $a[1];
    my $alivestate = $a[2];

    delete($hash->{helper}{RUNNING_PID});
    
    return if($hash->{helper}{DISABLED});
    
    readingsBeginUpdate( $hash );
    
    if( $callingtype eq "request" ) {
        if( $alivestate eq "restarted" ) {
        
            $hash->{helper}{requestErrorCounter} = 0;
            
            readingsBulkUpdate( $hash, "luigiHttpSrvState", "running");
            readingsBulkUpdate( $hash, "hombotState", "ONLINE");
            HOMBOT_Get_stateRequestLocal( $hash );
        
            Log3 $name, 3, "HOMBOT ($name) - Luigi Webserver was restarted";
        }
        
        elsif( $alivestate eq "running" ) {
        
            $hash->{helper}{requestErrorCounter} = 0;
            
            readingsBulkUpdate( $hash, "luigiHttpSrvState", "running");
            readingsBulkUpdate( $hash, "hombotState", "ONLINE");
            HOMBOT_Get_stateRequestLocal( $hash );
        
            Log3 $name, 3, "HOMBOT ($name) - Luigi Webserver is running";
        }
        
        elsif( $alivestate eq "offline" ) {
        
            $hash->{helper}{requestErrorCounter} = 0;
            
            readingsBulkUpdate( $hash, "luigiHttpSrvState", "running");
            readingsBulkUpdate ( $hash, "hombotState", "OFFLINE");
            readingsBulkUpdate ( $hash, "state", "Homebot offline");
        
            Log3 $name, 3, "HOMBOT ($name) - Hombot is not online";
        }
    }
    
    elsif( $callingtype eq "set" ) {
        if( $alivestate eq "restarted" ) {
        
            $hash->{helper}{setErrorCounter} = 0;
            
            readingsBulkUpdate( $hash, "luigiHttpSrvState", "running");
            readingsBulkUpdate( $hash, "hombotState", "ONLINE");
            HOMBOT_Get_stateRequestLocal( $hash );
        
            Log3 $name, 3, "HOMBOT ($name) - Luigi Webserver was restarted";
        }
        
        elsif( $alivestate eq "running" ) {
        
            $hash->{helper}{setErrorCounter} = 0;
            
            readingsBulkUpdate( $hash, "luigiHttpSrvState", "running");
            readingsBulkUpdate( $hash, "hombotState", "ONLINE");
            HOMBOT_Get_stateRequestLocal( $hash );
        
            Log3 $name, 3, "HOMBOT ($name) - Luigi Webserver is running";
        }
        
        elsif( $alivestate eq "offline" ) {
        
            $hash->{helper}{setErrorCounter} = 0;
            
            readingsBulkUpdate( $hash, "luigiHttpSrvState", "running");
            readingsBulkUpdate ( $hash, "hombotState", "OFFLINE");
            readingsBulkUpdate ( $hash, "state", "Homebot offline");
        
            Log3 $name, 3, "HOMBOT ($name) - Hombot is not online";
        }
    }
    
    readingsEndUpdate( $hash, 1 );
}

sub HOMBOT_Aborted_Bot_Alive($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};

    delete($hash->{helper}{RUNNING_PID});
    Log3 $name, 3, "HOMBOT ($name) - The BlockingCall Process terminated unexpectedly. Timedout";
}

sub HOMBOT_DetailFn() {         # Patch von Andre (justme1968)

    my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
    my $hash = $defs{$d};

    return if( !defined( $hash->{HOST} ) );

    return "<b><u><a href=\"http://$hash->{HOST}:6260\" target=\"_blank\">Control Center</a></u></b><br>"
}




1;




=pod
=item summary    connection to LG Homebot robotic vacuum cleaner
=item summary_DE Anbindung LG Homebot Staubsaugerroboter
=begin html

<a name="HOMBOT"></a>
<h3>HOMBOT</h3>
<ul>
  <u><b>HOMBOT - LG Homebot robotic vacuum cleaner</b></u>
  <br>
  After successfully hacking (WiFi-Mod) your Hombot, this Modul enables you to integrate your Hombot to FHEM.
  The Connection-Interface between FHEM and Hombot is served by Luigi HTTP Server.
  With this Module, the following is possible:
  <ul>
    <li>Readings about the Status will be saved.</li>
    <li>Choice of cleaning mode</li>
    <li>Start cleaning</li>
    <li>Stop cleaning</li>
    <li>Return to Homebase</li>
    <li>Assign Nickname</li>
    <li>Schedule Weekprogram</li>
    <li>Activate 'Repeat' and 'Turbo'</li>
  </ul>
  
  <br>
  You need to set up the device for the Hombot like this.
  <br><br>
  <a name="HOMBOTdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; HOMBOT &lt;IP-ADRESS&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define Roberta HOMBOT 192.168.0.23</code><br>
    </ul>
    <br>
    This command creates a HOMBOT-Device in room HOMBOT. The parameter &lt;IP-ADRESS&gt; determines the IP-Address of your Hombot.<br>
    The standard query interval is 180 seconds. You can change it with attribute interval. The interval is dynamic in dependency of the workstatus. For example, the status WORKING is 30 seconds.
    <br>
  </ul>
  <br><br> 
  <b><u>The first Readings should already appear after setting up the Device entity. </u></b>
  <br><br><br>
  <a name="HOMBOTreadings"></a>
  <b>Readings</b>
  <ul>
    <li>at_* - Reading for the week schedule. Start time for respective day.</li>
    <li>batteryPercent - Battery status in percent %</li>
    <li>cleanMode - Current cleanmode</li>
    <li>cpu_* - Information about CPU load</li>
    <li>currentBumping - Count of collisions with obstacles</li>
    <li>firmware - current installed firmware version</li>
    <li>hombotState - Status of Hombot</li>
    <li>lastClean - Date and Time of last cleaning</li>
    <li>lastSetCommandError - last error message from set command</li>
    <li>lastSetCommandState - last status from set command. Command (un)successfully send</li>
    <li>lastStatusRequestError - last error message from statusRequest command</li>
    <li>lastStatusRequestState - last status from statusRequest command. Command (un)successfully send</li>
    <li>luigiSrvVersion - Version of Luigi HTTP Servers of Hombot</li>
    <li>nickname - Name of Hombot</li>
    <li>num* - Previous started and ended cleanings in corresponding modes</li>
    <li>repeat - Cleaning will repeated Yes/No</li>
    <li>state - Module status</li>
    <li>turbo - Turbo active Yes/No</li>
  </ul>
  <br><br>
  <a name="HOMBOTset"></a>
  <b>Set</b>
  <ul>
    <li>cleanMode - set cleaning mode (ZZ-ZigZag / SB-Cell by Cell / SPOT-Spiralcleaning</li>
    <li>cleanStart - Start cleaning</li>
    <li>homing - Stop cleaning and move Hombot back to Base</li>
    <li>nickname - Sets HomBot's Nickname. Not visible in Reading until restart of Luigi-Server or HomBot itself.</li>
    <li>pause - Will pause the cleaning process</li>
    <li>repeat - Repeat cleaning? (true/false)</li>
    <li>schedule - Set of Week schedule. For example, set Roberta schedule Mo=13:30 Di= Mi=14:00,ZZ Do=15:20 Fr= Sa=11:20 So=  therefore you can also add modes!</li>
    <li>statusRequest - Requests new Statusreport from Device</li>
    <li>turbo - Activation of Turbomode (true/false)</li>
  </ul>
  <br><br>
</ul>

=end html
=begin html_DE

<a name="HOMBOT"></a>
<h3>HOMBOT</h3>
<ul>
  <u><b>HOMBOT - LG Homebot Staubsaugerroboter</b></u>
  <br>
  Dieses Modul gibt Euch die M&ouml;glichkeit Euren Hombot nach erfolgreichen Hack in FHEM ein zu binden.
  Voraussetzung ist das Ihr den Hombot Hack gemacht und einen WLAN Stick eingebaut habt. Als Schnittstelle zwischen FHEM und Bot wird der Luigi HTTP Server verwendet. Was genau k&ouml;nnt Ihr nun mit dem Modul machen:
  <ul>
    <li>Readings &uuml;ber den Status des Hombots werden angelegt</li>
    <li>Auswahl des Reinigungsmodus ist m&ouml;glich</li>
    <li>Starten der Reinigung</li>
    <li>Beenden der Reinigung</li>
    <li>zur&uuml;ck zur Homebase schicken</li>
    <li>Namen vergeben</li>
    <li>Wochenprogramm einstellen</li>
    <li>Repeat und Turbo aktivieren</li>
  </ul>
  <br>
  !!! Voraussetzungen schaffen !!!
  <br>Ihr ben&ouml;tigt zum verwenden des Modules die Programme ssh und sshpass. Desweiteren mu&szlig; im Homeverzeichnis des fhem Users das Verzeichniss .ssh existieren und darin die Datei known_hosts. Diese sollte eine Passphrass des Bots beinhalten. Am besten Ihr macht als normaler User eine ssh Session zum Bot und kopiert danach die known_hosts Eures normalen Users in das .ssh Verzeichnis des fhem Users. Rechte anpassen nicht vergessen.
  <br>
  Das Device f&uuml;r den Hombot legt Ihr wie folgt in FHEM an.
  <br><br>
  <a name="HOMBOTdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; HOMBOT &lt;IP-ADRESSE&gt;</code>
    <br><br>
    Beispiel:
    <ul><br>
      <code>define Roberta HOMBOT 192.168.0.23</code><br>
    </ul>
    <br>
    Diese Anweisung erstellt ein neues HOMBOT-Device im Raum HOMBOT.Der Parameter &lt;IP-ADRESSE&gt; legt die IP Adresse des LG Hombot fest.<br>
    Das Standard Abfrageinterval ist 180 Sekunden und kann &uuml;ber das Attribut intervall ge&auml;ndert werden. Das Interval ist in Abhängigkeit des Arbeitsstatus dynamisch. Im Status WORKING beträgt es z.B. 30 Sekunden.
    <br>
  </ul>
  <br><br> 
  <b><u>Nach anlegen der Ger&auml;teinstanz sollten bereits die ersten Readings erscheinen.</u></b>
  <br><br><br>
  <a name="HOMBOTreadings"></a>
  <b>Readings</b>
  <ul>
    <li>at_* - Reading f&uuml;r das Wochenprogramm. Startzeit f&uuml;r den jeweiligen Tag</li>
    <li>batteryPercent - Status der Batterie in %</li>
    <li>cleanMode - aktuell eingestellter Reinigungsmodus</li>
    <li>cpu_* - Informationen &uuml;ber die Prozessorauslastung</li>
    <li>currentBumping - Anzahl der Zusammenst&ouml;&szlig;e mit Hindernissen</li>
    <li>firmware - aktuell installierte Firmwareversion</li>
    <li>hombotState - Status des Hombots</li>
    <li>lastClean - Datum und Uhrzeit der letzten Reinigung</li>
    <li>lastSetCommandError - letzte Fehlermeldung vom set Befehl</li>
    <li>lastSetCommandState - letzter Status vom set Befehl, Befehl erfolgreich/nicht erfolgreich gesendet</li>
    <li>lastStatusRequestError - letzte Fehlermeldung vom statusRequest Befehl</li>
    <li>lastStatusRequestState - letzter Status vom statusRequest Befehl, Befehl erfolgreich/nicht erfolgreich gesendet</li>
    <li>luigiSrvVersion - Version des Luigi HTTP Servers auf dem Hombot</li>
    <li>nickname - Name des Hombot</li>
    <li>num* - Bisher begonnene und beendete Reinigungen im entsprechenden Modus</li>
    <li>repeat - Reinigung wird wiederholt Ja/Nein</li>
    <li>state - Modulstatus</li>
    <li>turbo - Turbo aktiv Ja/Nein</li>
  </ul>
  <br><br>
  <a name="HOMBOTset"></a>
  <b>Set</b>
  <ul>
    <li>cleanMode - setzen des Reinigungsmodus (ZZ-ZickZack / SB-Cell by Cell / SPOT-Spiralreinigung</li>
    <li>cleanStart - Reinigung starten</li>
    <li>homing - Beendet die Reinigung und l&auml;sst die Bot zur&uuml;ck zur Bases kommen</li>
    <li>nickname - setzt des Bot-Namens. Wird im Reading erst nach einem neustart des Luigiservers oder des Bots sichtbar</li>
    <li>pause - l&auml;sst den Reinigungspro&szlig;ess pausieren</li>
    <li>repeat - Reinigung wiederholen? (true/false)</li>
    <li>schedule - setzen des Wochenprogrammes Bsp. set Roberta schedule Mo=13:30 Di= Mi=14:00,ZZ Do=15:20 Fr= Sa=11:20 So=  Man kann also auch den Modus mitgeben!</li>
    <li>statusRequest - Fordert einen neuen Statusreport beim Device an</li>
    <li>turbo - aktivieren des Turbomodus (true/false)</li>
  </ul>
  <br><br>
</ul>

=end html_DE
=cut

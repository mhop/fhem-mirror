###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
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
#######
#######
#  URLs zum Abrufen diverser Daten
# http://<ip-Powerwall>/api/system_status/soe 
# http://<ip-Powerwall>/api/meters/aggregates
# http://<ip-Powerwall>/api/site_info
# http://<ip-Powerwall>/api/sitemaster
# http://<ip-Powerwall>/api/powerwalls
# http://<ip-Powerwall>/api/networks
# http://<ip-Powerwall>/api/system/networks
# http://<ip-Powerwall>/api/operation
#
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
eval "use JSON;1" or $missingModul .= "JSON ";


my $version = "0.2.3";




# Declare functions
sub TeslaPowerwall2AC_Attr(@);
sub TeslaPowerwall2AC_Define($$);
sub TeslaPowerwall2AC_Initialize($);
sub TeslaPowerwall2AC_Get($@);
sub TeslaPowerwall2AC_Notify($$);
sub TeslaPowerwall2AC_GetData($);
sub TeslaPowerwall2AC_Undef($$);
sub TeslaPowerwall2AC_ResponseProcessing($$$);
sub TeslaPowerwall2AC_ReadingsProcessing_Aggregates($$);
sub TeslaPowerwall2AC_ReadingsProcessing_Powerwalls($$);
sub TeslaPowerwall2AC_ErrorHandling($$$);
sub TeslaPowerwall2AC_WriteReadings($$$);
sub TeslaPowerwall2AC_Timer_GetData($);




my %paths = (   'statussoe'         => 'system_status/soe',
                'aggregates'        => 'meters/aggregates',
                'siteinfo'          => 'site_info',
                'sitemaster'        => 'sitemaster',
                'powerwalls'        => 'powerwalls',
                'registration'      => 'customer/registration',
                'status'            => 'status'
);


sub TeslaPowerwall2AC_Initialize($) {

    my ($hash) = @_;
    
    # Consumer
    $hash->{GetFn}      = "TeslaPowerwall2AC_Get";
    $hash->{DefFn}      = "TeslaPowerwall2AC_Define";
    $hash->{UndefFn}    = "TeslaPowerwall2AC_Undef";
    $hash->{NotifyFn}   = "TeslaPowerwall2AC_Notify";
    
    $hash->{AttrFn}     = "TeslaPowerwall2AC_Attr";
    $hash->{AttrList}   = "interval ".
                          "disable:1 ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{TeslaPowerwall2AC}{defptr}}) {
    
        my $hash = $modules{TeslaPowerwall2AC}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub TeslaPowerwall2AC_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <name> TeslaPowerwall2AC <HOST>" if( @a != 3);
    return "Cannot define a TeslaPowerwall2AC device. Perl modul $missingModul is missing." if ( $missingModul );
    
    my $name                = $a[0];
    
    my $host                = $a[2];
    $hash->{HOST}           = $host;
    $hash->{INTERVAL}       = 300;
    $hash->{PORT}           = 80;
    $hash->{VERSION}        = $version;
    $hash->{NOTIFYDEV}      = "global";
    $hash->{actionQueue}    = [];


    $attr{$name}{room}                      = "Tesla" if( !defined( $attr{$name}{room} ) );
    
    Log3 $name, 3, "TeslaPowerwall2AC ($name) - defined TeslaPowerwall2AC Device with Host $host, Port $hash->{PORT} and Interval $hash->{INTERVAL}";
    
    $modules{TeslaPowerwall2AC}{defptr}{HOST} = $hash;

    return undef;
}

sub TeslaPowerwall2AC_Undef($$) {

    my ( $hash, $arg )  = @_;
    
    my $name            = $hash->{NAME};


    Log3 $name, 3, "TeslaPowerwall2AC ($name) - Device $name deleted";
    delete $modules{TeslaPowerwall2AC}{defptr}{HOST} if( defined($modules{TeslaPowerwall2AC}{defptr}{HOST}) and $hash->{HOST} );

    return undef;
}

sub TeslaPowerwall2AC_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "TeslaPowerwall2AC ($name) - disabled";
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "TeslaPowerwall2AC ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "TeslaPowerwall2AC ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "TeslaPowerwall2AC ($name) - enabled";
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }
    
    if( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            if( $attrVal < 30 ) {
                Log3 $name, 3, "TeslaPowerwall2AC ($name) - interval too small, please use something >= 30 (sec), default is 300 (sec)";
                return "interval too small, please use something >= 30 (sec), default is 300 (sec)";
            
            } else {
                RemoveInternalTimer($hash);
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "TeslaPowerwall2AC ($name) - set interval to $attrVal";
                TeslaPowerwall2AC_Timer_GetData($hash);
            }
        } elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "TeslaPowerwall2AC ($name) - set interval to default";
            TeslaPowerwall2AC_Timer_GetData($hash);
        }
    }
    
    return undef;
}

sub TeslaPowerwall2AC_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    TeslaPowerwall2AC_Timer_GetData($hash) if( grep /^INITIALIZED$/,@{$events}
                                                or grep /^DELETEATTR.$name.disable$/,@{$events}
                                                or (grep /^DEFINED.$name$/,@{$events} and $init_done) );
    return;
}

sub TeslaPowerwall2AC_Get($@) {
    
    my ($hash, $name, $cmd) = @_;
    my $arg;


    if( $cmd eq 'statusSOE' ) {

        $arg    = lc($cmd);
        
    } elsif( $cmd eq 'aggregates' ) {
    
        $arg    = lc($cmd);
    
    } elsif( $cmd eq 'siteinfo' ) {
    
        $arg    = lc($cmd);

    } elsif( $cmd eq 'powerwalls' ) {
    
        $arg    = lc($cmd);
        
    } elsif( $cmd eq 'sitemaster' ) {
    
        $arg    = lc($cmd);
        
    } elsif( $cmd eq 'registration' ) {
    
        $arg    = lc($cmd);

    } elsif( $cmd eq 'status' ) {
    
        $arg    = lc($cmd);

    } else {
    
        my $list = 'statusSOE:noArg aggregates:noArg siteinfo:noArg sitemaster:noArg powerwalls:noArg registration:noArg status:noArg';
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return 'There are still path commands in the action queue'
    if( defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) > 0 );
    
    unshift( @{$hash->{actionQueue}}, $arg );
    TeslaPowerwall2AC_GetData($hash);

    return undef;
}

sub TeslaPowerwall2AC_Timer_GetData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};


    if( defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) == 0 ) {
        if( not IsDisabled($name) ) {
            while( my $obj = each %paths ) {
                unshift( @{$hash->{actionQueue}}, $obj );
            }
        
            TeslaPowerwall2AC_GetData($hash);
        
        } else {
            readingsSingleUpdate($hash,'state','disabled',1);
        }
    }
    
    InternalTimer( gettimeofday()+$hash->{INTERVAL}, 'TeslaPowerwall2AC_Timer_GetData', $hash );
    Log3 $name, 4, "TeslaPowerwall2AC ($name) - Call InternalTimer TeslaPowerwall2AC_Timer_GetData";
}

sub TeslaPowerwall2AC_GetData($) {

    my ($hash)          = @_;
    
    my $name            = $hash->{NAME};
    my $host            = $hash->{HOST};
    my $port            = $hash->{PORT};
    my $path            = pop( @{$hash->{actionQueue}} );
    my $uri             = $host . ':' . $port . '/api/' . $paths{$path};


    readingsSingleUpdate($hash,'state','fetch data - ' . scalar(@{$hash->{actionQueue}}) . ' entries in the Queue',1);

    HttpUtils_NonblockingGet(
        {
            url         => "http://" . $uri,
            timeout     => 5,
            method      => 'GET',
            hash        => $hash,
            setCmd      => $path,
            doTrigger   => 1,
            callback    => \&TeslaPowerwall2AC_ErrorHandling,
        }
    );
    
    Log3 $name, 4, "TeslaPowerwall2AC ($name) - Send with URI: http://$uri";
}

sub TeslaPowerwall2AC_ErrorHandling($$$) {

    my ($param,$err,$data)  = @_;
    
    my $hash                = $param->{hash};
    my $name                = $hash->{NAME};


    ### Begin Error Handling
    
    if( defined( $err ) ) {
        if( $err ne "" ) {
        
            readingsBeginUpdate( $hash );
            readingsBulkUpdate( $hash, 'state', $err, 1);
            readingsBulkUpdate( $hash, 'lastRequestError', $err, 1 );
            readingsEndUpdate( $hash, 1 );
            
            Log3 $name, 3, "TeslaPowerwall2AC ($name) - RequestERROR: $err";
            
            $hash->{actionQueue} = [];
            return;
        }
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );

        readingsBulkUpdate( $hash, 'lastRequestError', $param->{code}, 1 );

        Log3 $name, 3, "TeslaPowerwall2AC ($name) - RequestERROR: ".$param->{code};

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 5, "TeslaPowerwall2AC ($name) - RequestERROR: received http code ".$param->{code}." without any data after requesting";

        $hash->{actionQueue} = [];
        return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) { 
    
        readingsBeginUpdate( $hash );
        
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );
        readingsBulkUpdate( $hash, "lastRequestError", $param->{code}, 1 );

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 3, "TeslaPowerwall2AC ($name) - statusRequestERROR: http error ".$param->{code};

        $hash->{actionQueue} = [];
        return;
        ### End Error Handling
    }
    
    TeslaPowerwall2AC_GetData($hash)
    if( defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) > 0 );
    
    Log3 $name, 4, "TeslaPowerwall2AC ($name) - Recieve JSON data: $data";
    
    TeslaPowerwall2AC_ResponseProcessing($hash,$param->{setCmd},$data);
}

sub TeslaPowerwall2AC_ResponseProcessing($$$) {

    my ($hash,$path,$json)        = @_;
    
    my $name                = $hash->{NAME};
    my $decode_json;
    my $readings;


    $decode_json    = eval{decode_json($json)};
    if($@){
        Log3 $name, 4, "TeslaPowerwall2AC ($name) - error while request: $@";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'JSON Error', $@);
        readingsBulkUpdate($hash, 'state', 'JSON error');
        readingsEndUpdate($hash,1);
        return;
    }
    
    #### Verarbeitung der Readings zum passenden Path
    
    if( $path eq 'aggregates') {
        $readings = TeslaPowerwall2AC_ReadingsProcessing_Aggregates($hash,$decode_json);
        
    } elsif( $path eq 'powerwalls') {
        $readings = TeslaPowerwall2AC_ReadingsProcessing_Powerwalls($hash,$decode_json);
        
    } else {
        $readings = $decode_json;
    }
    
    TeslaPowerwall2AC_WriteReadings($hash,$path,$readings);
}

sub TeslaPowerwall2AC_WriteReadings($$$) {

    my ($hash,$path,$readings)    = @_;
    
    my $name                = $hash->{NAME};
    
    
    Log3 $name, 4, "TeslaPowerwall2AC ($name) - Write Readings";
    
    
    readingsBeginUpdate($hash);
    while( my ($r,$v) = each %{$readings} ) {
        readingsBulkUpdate($hash,$path.'-'.$r,$v);
    }
    
    readingsBulkUpdate($hash,'batteryLevel',sprintf("%.1f",$readings->{percentage})) if( defined($readings->{percentage}) );
    readingsBulkUpdate($hash,'batteryPower',sprintf("%.1f",(ReadingsVal($name,'siteinfo-nominal_system_energy_kWh',0)/100) * ReadingsVal($name,'statussoe-percentage',0) ) );
    readingsBulkUpdateIfChanged($hash,'actionQueue',scalar(@{$hash->{actionQueue}}) . ' entries in the Queue');
    readingsBulkUpdateIfChanged($hash,'state',(defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) == 0 ? 'ready' : 'fetch data - ' . scalar(@{$hash->{actionQueue}}) . ' paths in actionQueue'));
    readingsEndUpdate($hash,1);
}

sub TeslaPowerwall2AC_ReadingsProcessing_Aggregates($$) {
    
    my ($hash,$decode_json)     = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    if( ref($decode_json) eq "HASH" ) {
        while( my $obj = each %{$decode_json} ) {
            while( my ($r,$v) = each %{$decode_json->{$obj}} ) {
                $readings{$obj.'-'.$r}   = $v;
            }
        }
        
    } else {
        $readings{'error'} = 'aggregates response is not a Hash';
    }
    
    return \%readings;
}

sub TeslaPowerwall2AC_ReadingsProcessing_Powerwalls($$) {
    
    my ($hash,$decode_json)     = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    if( ref($decode_json->{powerwalls}) eq "ARRAY" and scalar(@{$decode_json->{powerwalls}}) > 0 ) {
    
        foreach my $powerwall (@{$decode_json->{powerwalls}}) {
            if( ref($powerwall) eq "HASH" ) {
            
                while( my ($r,$v) = each %{$powerwall} ) {
                    $readings{$r}   = $v;
                }
            }
        }

    } else {
        $readings{'error'} = 'aggregates response is not a Array';
    }
    
    return \%readings;
}




1;


=pod

=item device
=item summary       Modul to retrieves data from a Tesla Powerwall 2AC
=item summary_DE 

=begin html

<a name="TeslaPowerwall2AC"></a>
<h3>Tesla Powerwall 2 AC</h3>
<ul>
    <u><b>TeslaPowerwall2AC - Retrieves data from a Tesla Powerwall 2AC System</b></u>
    <br>
    With this module it is possible to read the data from a Tesla Powerwall 2AC and to set it as reading.
    <br><br>
    <a name="TeslaPowerwall2ACdefine"></a>
    <b>Define</b>
    <ul><br>
        <code>define &lt;name&gt; TeslaPowerwall2AC &lt;HOST&gt;</code>
    <br><br>
    Example:
    <ul><br>
        <code>define myPowerWall TeslaPowerwall2AC 192.168.1.34</code><br>
    </ul>
    <br>
    This statement creates a Device with the name myPowerWall and the Host IP 192.168.1.34.<br>
    After the device has been created, the current data of Powerwall is automatically read from the device.
    </ul>
    <br><br>
    <a name="TeslaPowerwall2ACreadings"></a>
    <b>Readings</b>
    <ul>
        <li>actionQueue     - information about the entries in the action queue</li>
        <li>aggregates-*    - readings of the /api/meters/aggregates response</li>
        <li>batteryLevel    - battery level in percent</li>
        <li>batteryPower    - battery capacity in kWh</li>
        <li>powerwalls-*    - readings of the /api/powerwalls response</li>
        <li>registration-*  - readings of the /api/customer/registration response</li>
        <li>siteinfo-*      - readings of the /api/site_info response</li>
        <li>sitemaster-*    - readings of the /api/sitemaster response</li>
        <li>state           - information about internel modul processes</li>
        <li>status-*        - readings of the /api/status response</li>
        <li>statussoe-*     - readings of the /api/system_status/soe response</li>
    </ul>
    <a name="TeslaPowerwall2ACget"></a>
    <b>get</b>
    <ul>
        <li>aggregates      - fetch data from url path /api/meters/aggregates</li>
        <li>powerwalls      - fetch data from url path /api/powerwalls</li>
        <li>registration    - fetch data from url path /api/customer/registration</li>
        <li>siteinfo        - fetch data from url path /api/site_info</li>
        <li>sitemaster      - fetch data from url path /api/sitemaster</li>
        <li>status          - fetch data from url path /api/status</li>
        <li>statussoe       - fetch data from url path /api/system_status/soe</li>
    </ul>
    <a name="TeslaPowerwall2ACattribute"></a>
    <b>Attribute</b>
    <ul>
        <li>interval - interval in seconds for automatically fetch data (default 300)</li>
    </ul>
</ul>

=end html
=begin html_DE

<a name="TeslaPowerwall2AC"></a>
<h3>Tesla Powerwall 2 AC</h3>

=end html_DE
=cut

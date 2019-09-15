###############################################################################
# 
# $Id$
#
#  By (c) 2018 Felix Martens  (felix at martensmail dot de)
#
#  Based on 46_TeslaPowerwall2AC by
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#
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

#
##
##



package main;


my $solarEdgeAPI_missingModul = "";

use strict;
use warnings;

use HttpUtils;
eval "use JSON;1" or $solarEdgeAPI_missingModul .= "JSON ";

my $solarEdgeAPI_version = "1.0.0";




# Declare functions
sub SolarEdgeAPI_Attr(@);
sub SolarEdgeAPI_Define($$);
sub SolarEdgeAPI_Initialize($);
sub SolarEdgeAPI_Get($@);
sub SolarEdgeAPI_Notify($$);
sub SolarEdgeAPI_GetData($);
sub SolarEdgeAPI_Undef($$);
sub SolarEdgeAPI_ResponseProcessing($$$);
sub SolarEdgeAPI_ReadingsProcessing_Aggregates($$);
sub SolarEdgeAPI_ReadingsProcessing_Status($$);
sub SolarEdgeAPI_ErrorHandling($$$);
sub SolarEdgeAPI_WriteReadings($$$);
sub SolarEdgeAPI_Timer_GetData($);




my %solarEdgeAPI_paths = (   'status'         => 'currentPowerFlow.json',
                'aggregates'        => 'energyDetails'
);


sub SolarEdgeAPI_Initialize($) {

    my ($hash) = @_;
    
    # Consumer
    $hash->{GetFn}      = "SolarEdgeAPI_Get";
    $hash->{DefFn}      = "SolarEdgeAPI_Define";
    $hash->{UndefFn}    = "SolarEdgeAPI_Undef";
    $hash->{NotifyFn}   = "SolarEdgeAPI_Notify";
    
    $hash->{AttrFn}     = "SolarEdgeAPI_Attr";
    $hash->{AttrList}   = "interval ".
                          "disable:1 ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{SolarEdgeAPI}{defptr}}) {
    
        my $hash = $modules{SolarEdgeAPI}{defptr}{$d};
        $hash->{VERSION}      = $solarEdgeAPI_version;
    }
}

sub SolarEdgeAPI_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );

    
    return "too few parameters: define <name> SolarEdgeAPI <API-Key> <Site-ID> <interval>" if(int(@a) != 5);
    return "Cannot define a SolarEdgeAPI device. Perl modul $solarEdgeAPI_missingModul is missing." if ( $solarEdgeAPI_missingModul );
    
    my $name                = $a[0];
    
    my $apikey                = $a[2];
    my $siteid                = $a[3];
    my $interval                = $a[4]||'auto';

    $hash->{APIKEY}           = $apikey;
    $hash->{SITEID}           = $siteid;

    $hash->{INTERVAL}       = $interval;
    $hash->{PORT}           = 80;
    $hash->{VERSION}        = $solarEdgeAPI_version;
    $hash->{NOTIFYDEV}      = "global";
    $hash->{actionQueue}    = [];


    $attr{$name}{room}                      = "Photovoltaik" if( !defined( $attr{$name}{room} ) );
    
    Log3 $name, 3, "SolarEdgeAPI ($name) - defined SolarEdgeAPI Device with SiteID $hash->{SITEID} and Interval $hash->{INTERVAL}";
    
    $modules{SolarEdgeAPI}{defptr}{SITEID} = $hash;

    return undef;
}

sub SolarEdgeAPI_Undef($$) {

    my ( $hash, $arg )  = @_;
    
    my $name            = $hash->{NAME};


    Log3 $name, 3, "SolarEdgeAPI ($name) - Device $name deleted";
    delete $modules{SolarEdgeAPI}{defptr}{SITEID} if( defined($modules{SolarEdgeAPI}{defptr}{SITEID}) and $hash->{SITEID} );

    return undef;
}

sub SolarEdgeAPI_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "SolarEdgeAPI ($name) - disabled";
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "SolarEdgeAPI ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "SolarEdgeAPI ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "SolarEdgeAPI ($name) - enabled";
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }
    
    if( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
			if($attrVal eq "auto" || $attrVal > 120){
				RemoveInternalTimer($hash);
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "SolarEdgeAPI ($name) - set interval to $attrVal";
                SolarEdgeAPI_Timer_GetData($hash);
			}else {
                Log3 $name, 3, "SolarEdgeAPI ($name) - interval too small, please use something >= 120 (sec), default is 300 (sec)";
                return "interval too small, please use something >= 120 (sec), default is 300 (sec) daytime and 1200 (sec) nighttime";
            }
            
        } elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            $hash->{INTERVAL} = 'auto';
            Log3 $name, 3, "SolarEdgeAPI ($name) - set interval to default";
            SolarEdgeAPI_Timer_GetData($hash);
        }
    }
    
    return undef;
}

sub SolarEdgeAPI_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    SolarEdgeAPI_Timer_GetData($hash) if( grep /^INITIALIZED$/,@{$events}
                                                or grep /^DELETEATTR.$name.disable$/,@{$events}
                                                or grep /^DELETEATTR.$name.interval$/,@{$events}
                                                or (grep /^DEFINED.$name$/,@{$events} and $init_done) );
    return;
}

sub SolarEdgeAPI_Get($@) {
    
    my ($hash, $name, $cmd) = @_;
    my $arg;


    if( $cmd eq 'status' ) {

        $arg    = lc($cmd);
        
    } elsif( $cmd eq 'aggregates' ) {
    
        $arg    = lc($cmd);
    
    } else {
    
        my $list = 'status:noArg aggregates:noArg';
        
        return "Unknown argument $cmd, choose one of $list";
    }
    
    return 'There are still path commands in the action queue'
    if( defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) > 0 );
    
    unshift( @{$hash->{actionQueue}}, $arg );
    SolarEdgeAPI_GetData($hash);

    return undef;
}

sub SolarEdgeAPI_Timer_GetData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
	my $interval   = $hash->{INTERVAL};

    if( defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) == 0 ) {
        if( not IsDisabled($name) ) {
            while( my $obj = each %solarEdgeAPI_paths ) {
                unshift( @{$hash->{actionQueue}}, $obj );
            }
        
            SolarEdgeAPI_GetData($hash);
        
        } else {
            readingsSingleUpdate($hash,'state','disabled',1);
        }
    }
    
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime(time);
    
    if($interval eq "auto"){
		if ($hour > 6&& $hour < 22) { $interval = 300;}
		else				 { $interval = 1200;}
    }
    
    InternalTimer( gettimeofday()+$interval, 'SolarEdgeAPI_Timer_GetData', $hash );
    Log3 $name, 4, "SolarEdgeAPI ($name) - Call InternalTimer SolarEdgeAPI_Timer_GetData with interval $interval";
}

sub SolarEdgeAPI_GetData($) {

    my ($hash)          = @_;
    
    my $name            = $hash->{NAME};
    my $siteid            = $hash->{SITEID};

    my $host            = "monitoringapi.solaredge.com/site/" . $siteid;
    my $apikey            = $hash->{APIKEY};
    my $path            = pop( @{$hash->{actionQueue}} );
    my $params 			= "";
    if($path eq "aggregates" ){
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
                                                localtime(time);
			$params= "&timeUnit=QUARTER_OF_AN_HOUR&startTime=" . (1900+$year) . "-" . (1+$mon) . "-" . $mday . "%2000:00:00&endTime=" . (1900+$year) . "-" . (1+$mon) . "-" . $mday . "%20" . $hour . ":" . $min . ":" . $sec;
	}
    my $uri             = $host . '/' . $solarEdgeAPI_paths{$path} . "?api_key=" . $apikey.$params;
    



    readingsSingleUpdate($hash,'state','fetch data - ' . scalar(@{$hash->{actionQueue}}) . ' entries in the Queue',1);

    HttpUtils_NonblockingGet(
        {
            url         => "https://" . $uri,
            timeout     => 5,
            method      => 'GET',
            hash        => $hash,
            setCmd      => $path,
            doTrigger   => 1,
            callback    => \&SolarEdgeAPI_ErrorHandling,
        }
    );
    
    Log3 $name, 4, "SolarEdgeAPI ($name) - Send with URI: http://$uri";
}

sub SolarEdgeAPI_ErrorHandling($$$) {

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
            
            Log3 $name, 3, "SolarEdgeAPI ($name) - RequestERROR: $err";
            
            $hash->{actionQueue} = [];
            return;
        }
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );

        readingsBulkUpdate( $hash, 'lastRequestError', $param->{code}, 1 );

        Log3 $name, 3, "SolarEdgeAPI ($name) - RequestERROR: ".$param->{code};

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 5, "SolarEdgeAPI ($name) - RequestERROR: received http code ".$param->{code}." without any data after requesting";

        $hash->{actionQueue} = [];
        return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) { 
    
        readingsBeginUpdate( $hash );
        
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );
        readingsBulkUpdate( $hash, "lastRequestError", $param->{code}, 1 );

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 3, "SolarEdgeAPI ($name) - statusRequestERROR: http error ".$param->{code};

        $hash->{actionQueue} = [];
        return;
        ### End Error Handling
    }
    
    SolarEdgeAPI_GetData($hash)
    if( defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) > 0 );
    
    Log3 $name, 4, "SolarEdgeAPI ($name) - Recieve JSON data: $data";
    
    SolarEdgeAPI_ResponseProcessing($hash,$param->{setCmd},$data);
}

sub SolarEdgeAPI_ResponseProcessing($$$) {

    my ($hash,$path,$json)        = @_;
    
    my $name                = $hash->{NAME};
    my $decode_json;
    my $readings;


    $decode_json    = eval{decode_json($json)};
    if($@){
        Log3 $name, 4, "SolarEdgeAPI ($name) - error while request: $@";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'JSON Error', $@);
        readingsBulkUpdate($hash, 'state', 'JSON error');
        readingsEndUpdate($hash,1);
        return;
    }
    
    #### Verarbeitung der Readings zum passenden Path
    
    if( $path eq 'aggregates') {
        $readings = SolarEdgeAPI_ReadingsProcessing_Aggregates($hash,$decode_json);
        
    } elsif( $path eq 'status') {
        $readings = SolarEdgeAPI_ReadingsProcessing_Status($hash,$decode_json);
        
    } else {
        $readings = $decode_json;
    }
    
    SolarEdgeAPI_WriteReadings($hash,$path,$readings);
}

sub SolarEdgeAPI_WriteReadings($$$) {

    my ($hash,$path,$readings)    = @_;
    
    my $name                = $hash->{NAME};
    
    
    Log3 $name, 4, "SolarEdgeAPI ($name) - Write Readings";
    
    
    readingsBeginUpdate($hash);
    while( my ($r,$v) = each %{$readings} ) {
        readingsBulkUpdate($hash,$path.'-'.$r,$v);
    }
    
    readingsBulkUpdateIfChanged($hash,'actionQueue',scalar(@{$hash->{actionQueue}}) . ' entries in the Queue');
    readingsBulkUpdateIfChanged($hash,'state',(defined($hash->{actionQueue}) and scalar(@{$hash->{actionQueue}}) == 0 ? 'ready' : 'fetch data - ' . scalar(@{$hash->{actionQueue}}) . ' paths in actionQueue'));
    readingsEndUpdate($hash,1);
}

sub SolarEdgeAPI_ReadingsProcessing_Aggregates($$) {
    
    my ($hash,$decode_json)     = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
    
    
    if( ref($decode_json) eq "HASH" ) {
		my $data = $decode_json->{'energyDetails'};
		$readings{'unit'} = $data->{'unit'}||"Error Reading Response";		
		$readings{'timeUnit'} = $data->{'timeUnit'}||"Error Reading Response";		
		$data = $decode_json->{'energyDetails'}->{'meters'};

		my $meter_type = "";
		my $meter_cum = 0;
		my $meter_val = 0;
		
		foreach my $meter ( @{$decode_json->{'energyDetails'}->{'meters'}}) {
			# Meters
			$meter_type = $meter->{'type'};
			$meter_cum = 0;
			$meter_val = 0;
		foreach my $meterTelemetry (@{$meter -> {'values'}}) {
				my $v = $meterTelemetry->{'value'};
                $meter_cum = $meter_cum + $v;
                $meter_val = $v;
         }
            $readings{$meter_type . "-recent15min"} = $meter_val;
            $readings{$meter_type . "-cumToday"} = $meter_cum;
        }
        
    } else {
       $readings{'error'} = 'aggregates response is not a Hash';
    }
    
    return \%readings;
}

sub SolarEdgeAPI_ReadingsProcessing_Status($$) {
    
    my ($hash,$decode_json)     = @_;
    
    my $name                    = $hash->{NAME};
    my %readings;
  	my $data = $decode_json->{'siteCurrentPowerFlow'};

    
    	$readings{'unit'} = $data->{'unit'}||"Error Reading Response";		
		$readings{'updateRefreshRate'} = $data->{'updateRefreshRate'}||"Error Reading Response";		
		
		# Connections / Directions
		
		my $pv2load = 0;
		my $pv2storage = 0;
		my $load2storage = 0;
		my $storage2load = 0;
		my $load2grid = 0;
		my $grid2load = 0;
		foreach my $connection ( @{ $data->{'connections'} }) {
			my $from = lc($connection->{'from'});
			my $to = lc($connection->{'to'});
			if($from  eq 'grid'&&$to  eq "load"){ $grid2load = 1;}
			if($from eq "load"&&$to  eq 'grid') {$load2grid = 1;}
			if($from eq 'load'&&$to eq "storage"){ $load2storage = 1;}
			if($from eq 'pv'&&$to eq "storage") {$pv2storage = 1;}
			if($from eq 'pv'&&$to eq "load") {$pv2load = 1;}
			if($from eq 'storage'&&$to eq "load"){ $storage2load = 1;}
			
		}
		
	
		# GRID
		
		$readings{'grid_status'} = $data->{'GRID'}->{"status"}||"Error Reading Response";		
		$readings{'grid_power'} = ($load2grid >0 ? "-" : "") . $data->{'GRID'}->{"currentPower"};
		
		# LOAD
		$readings{'load_status'} = $data->{'LOAD'}->{"status"}||"Error Reading Response";	
		$readings{'load_power'} = $data->{'LOAD'}->{"currentPower"};		
		
		# PV
		
		$readings{'pv_status'} = $data->{'PV'}->{"status"}||"Error Reading Response";	
		$readings{'pv_power'} = $data->{'PV'}->{"currentPower"};		
		
		
		
		# Storage
		
		$readings{'storage_status'} = $data->{'STORAGE'}->{"status"}||"No storage found";
			if	($readings{'storage_status'} ne "No storage found"){		
				$readings{'storage_power'} = ($storage2load >0 ? "-" : "") . $data->{'STORAGE'}->{"currentPower"};
				$readings{'storage_level'} = $data->{'STORAGE'}->{"chargeLevel"}||"Error Reading Response";		
				$readings{'storage_critical'} = $data->{'STORAGE'}->{"critical"};		
			}
		
    
    return \%readings;
}




1;


=pod
=item device
=item summary       Modul to retrieve data from a SolarEdge PV System via official API
=item summary_DE 
=begin html

<a name="SolarEdgeAPI"></a>
<h3>SolarEdge API</h3>
<ul>
    <u><b>SolarEdge API - Retrieves data from the SolarEdge Monitoring API</b></u>
    <br>
    With this module it is possible to read the data from a SolarEdge PV and to set it as reading.
    <br><br>
    <a name="SolarEdgeAPIdefine"></a>
    <b>Define</b>
    <ul><br>
        <code>define &lt;name&gt; SolarEdgeAPI &lt;API-Key&gt; &lt;API-Key&gt;</code>
    <br><br>
    Example:
    <ul><br>
        <code>define myPVSite SolarEdgeAPI ABC123 123456</code><br>
    </ul>
    <br>
    This statement creates a Device with the name myPV using API-Key ABC123 for fetching data of Site-Id 123456<br>
    After the device has been created, the current data of the site is automatically read from the API.
    The API-Key has to be enabled in the "Admin" Section of the Monitoring-Portal. There you can find your Site-ID, too.
    According to the docs there is a limit of 300 total requests per day.
    </ul>
    <br><br>
    <a name="SolarEdgeAPIreadings"></a>
    <b>Readings</b>
    <ul>
        <li>actionQueue     - information about the entries in the action queue</li>
        <li>aggregates-*    - cumulative data of the energyDetails response</li>
        <li>status-*        - readings of the currentPowerFlow response</li>
    </ul>
    <a name="SolarEdgeAPIget"></a>
    <b>get</b>
    <ul>
        <li>aggregates      - fetch data from energyDetails.json</li>
        <li>status          - fetch data currentPowerFlow.json </li>
    </ul>
    <a name="SolarEdgeAPIattribute"></a>
    <b>Attribute</b>
    <ul>
        <li>interval - interval in seconds for automatically fetch data (default auto = 300 (sec) daytime and 1200 (sec) nighttime)</li>
    </ul>
</ul>
=end html

=begin html_DE

<a name="SolarEdgeAPI"></a>
<h3>SolarEdge API Anbindung</h3>
=end html_DE
=cut

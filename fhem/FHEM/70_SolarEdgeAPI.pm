###############################################################################
#
# $Id$
#
# By (c) 2019 FHEM user 'pizmus' (pizmus at web de)
#
# Based on 70_SolarEdgeAPI.pm from https://github.com/felixmartens/fhem by 
# (c) 2018 Felix Martens (felix at martensmail dot de)
#
# Based on 46_TeslaPowerwall2AC by
# (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#
# All rights reserved
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# any later version.
#
# The GNU General Public License can be found at
# http://www.gnu.org/copyleft/gpl.html.
# A copy is found in the textfile GPL.txt and important notices to the license
# from the author is found in LICENSE.txt distributed with these scripts.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
###############################################################################

package main;

use strict;
use warnings;
use HttpUtils;

###############################################################################
#
# Note: Always call the JSON module via "eval":
#
# $data = eval{decode_json($data)};
# if($@){
#   Log3($SELF, 2, "$TYPE ($SELF) - error while request: $@");  
#   readingsSingleUpdate($hash, "state", "error", 1);
#   return;
# }
#
###############################################################################

my $solarEdgeAPI_missingModul = "";
eval "use JSON;1" or $solarEdgeAPI_missingModul .= "JSON ";

###############################################################################
#
# versioning scheme: <majorVersion>.<minorVersion>.<patchVersion>[betaXYZ]
#
# The <majorVersion> is incremented for changes which are not backward compatible.
# A change of the <majorVersion> may require adaptations on the user side, for
# some or all users, e.g. because a reading is removed or has a new meaning.
#
# The <minorVersion> is incremented for changes which are backward compatible,
# e.g. added functionality which does not impact old functionality.
#
# The <patchVersion> is incremented for small bug fixes, changes of source code
# comments or documentation.
#
# A string starting with "beta" is attached for release candidates which are 
# distributed for testing. If no issues are found in a beta version, the "beta" 
# string is removed and the source file is submitted.
#
###############################################################################
# 
# 1.0.0     initial version as copied from https://github.com/felixmartens/fhem
#           with minimal changes to be able to submit it to FHEM SVN
#
# 1.1.0     Detect that site does not support the "currentPowerFlow" API.
#           Read "overview" API to get the current power.
#           Added attributes enableStatusReadings, enableAggregatesReadings, 
#           and enableOverviewReadings.
#
###############################################################################

my $solarEdgeAPI_version = "1.1.0beta";

###############################################################################

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
sub SolarEdgeAPI_ReadingsProcessing_Overview($$);
sub SolarEdgeAPI_ErrorHandling($$$);
sub SolarEdgeAPI_WriteReadings($$$);
sub SolarEdgeAPI_Timer_GetData($);

my %solarEdgeAPI_paths = (
  'status' => 'currentPowerFlow.json',
  'aggregates' => 'energyDetails',
  'overview' => 'overview'
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
                          "enableStatusReadings:1,0 " .
                          "enableAggregatesReadings:1,0 " .
                          "enableOverviewReadings:1,0 " .
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
            if($attrVal eq "auto" || $attrVal > 120) {
                RemoveInternalTimer($hash);
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "SolarEdgeAPI ($name) - set interval to $attrVal";
                SolarEdgeAPI_Timer_GetData($hash);
            } else {
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
   
    if ($attrName eq "enableStatusReadings") 
    {
        if($cmd eq "set")
        {
            if (not (($attrVal eq "0") || ($attrVal eq "1")))
            {
                my $message = "illegal value for enableStatusReadings";
                Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
                return $message; 
            }
        } 
    }
    
    if ($attrName eq "enableAggregatesReadings") 
    {
        if($cmd eq "set")
        {
            if (not (($attrVal eq "0") || ($attrVal eq "1")))
            {
                my $message = "illegal value for enableAggregatesReadings";
                Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
                return $message; 
            }
        } 
    }
  
    if ($attrName eq "enableOverviewReadings") 
    {
        if($cmd eq "set")
        {
            if (not (($attrVal eq "0") || ($attrVal eq "1")))
            {
                my $message = "illegal value for enableOverviewReadings";
                Log3 $name, 3, "SolarEdgeAPI ($name) - ".$message;
                return $message; 
            }
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
    
    } elsif( $cmd eq 'overview' ) {
    
        $arg    = lc($cmd);
    
    } else {
    
        my $list = 'status:noArg aggregates:noArg overview:noArg';
        
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
            while( my $obj = each %solarEdgeAPI_paths ) 
            {
                if ( (($obj eq "status") and (AttrVal($name, "enableStatusReadings", 1))) or
                     (($obj eq "aggregates") and (AttrVal($name, "enableAggregatesReadings", 1))) or
                     (($obj eq "overview") and (AttrVal($name, "enableOverviewReadings", 0))) )
                {
                    unshift( @{$hash->{actionQueue}}, $obj );
                }
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
    
    Log3 $name, 4, "SolarEdgeAPI ($name) - Receive JSON data: $data";
    
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

    } elsif( $path eq 'overview') {
        $readings = SolarEdgeAPI_ReadingsProcessing_Overview($hash,$decode_json);

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

    if ((defined $data) && (!defined $data->{'unit'}))
    {
        Log3 $name, 3, "SolarEdgeAPI ($name) - API currentPowerFlow is not supported. Avoid unsuccessful server queries by setting attribute enableStatusReadings=0.";
        $readings{'error'} = 'API currentPowerFlow is not supported by site.';
    }
    else
    {
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
        if ($readings{'storage_status'} ne "No storage found")
        {		
            $readings{'storage_power'} = ($storage2load >0 ? "-" : "") . $data->{'STORAGE'}->{"currentPower"};
            $readings{'storage_level'} = $data->{'STORAGE'}->{"chargeLevel"}||"Error Reading Response";		
            $readings{'storage_critical'} = $data->{'STORAGE'}->{"critical"};		
        }
    }
    
    return \%readings;
}

sub SolarEdgeAPI_ReadingsProcessing_Overview($$) {
    my ($hash, $decode_json) = @_;
    my $name = $hash->{NAME};
    
    my %readings;
    my $data = $decode_json->{'overview'};
    
    $readings{'power'} = $data->{'currentPower'}->{"power"};            
    
    return \%readings;
}


1;


=pod
=item device
=item summary       Retrieves data from a SolarEdge PV system via the SolarEdge Monitoring API
=item summary_DE 
=begin html

<a name="SolarEdgeAPI"></a>
<h3>SolarEdgeAPI</h3>

<ul>
  This module retrieves data from a SolarEdge PV system via the SolarEdge Server Monitoring API.<br>
  <br>
  Data is retrieved from the server periodically. The interval during day time is higher compared<br>
  to night time. According to the API documentation the total number of server queries per day is<br>
  limited to 300.<br>
  The total number of queries per day can be controlled with attributes. In each interval each enabled<br>
  group of readings is generated once. You can reduce the number of server queries by disabling groups<br>
  of readings and by increasing the interval.<br>
  <br>

  <a name="SolarEdgeAPI_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SolarEdgeAPI &lt;API Key&gt; &lt;Site ID&gt; &lt;interval&gt|auto;</code><br>
    The &lt;API Key&gt; and the &lt;Site ID&gt can be retrieved from the SolarEdge<br>
    Monitoring Portal. The &lt;API Key&gt; has to be enabled in the "Admin" Secion<br>
    of the web portal.<br>
  </ul>
  <br>
    
  <a name="SolarEdgeAPI_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>actionQueue     - information about the entries in the action queue (for debug only)</li>
    <li>status-*        - readings generated from currentPowerFlow API response. This API is not supported by all sites.</li>
    <li>aggregates-*    - cumulative data of the energyDetails response</li>
    <li>overview-*      - readings generated from overview API response</li>    
  </ul>
  <br>
    
  <a name="SolarEdgeAPI_Get"></a>
  <b>Get</b>
  <ul>
    <li>status          - fetch data from currentPowerFlow API (for debug only)</li>
    <li>aggregates      - fetch data from energyDetails API (for debug only)</li>
    <li>overview        - fetch data from overview API (for debug only)</li>
  </ul>
  <br>
    
  <a name="SolarEdgeAPI_Attributes"></a>
  <b>Attributes</b>
  <ul>
    <li>interval - interval in seconds for automatically fetch data (default auto = 300 (sec) daytime and 1200 (sec) nighttime)</li>
    <li>enableStatusReadings Enable the status-* readings. Default: 1</li>
    <li>enableAggregatesReadings Enable the aggregates-* readings. Default: 1</li>
    <li>enableOverviewReadings Enable the overview-* readings. Default: 0 (for backward compatiblity)</li> 
  </ul>
  <br>
  
</ul>

=end html

=cut

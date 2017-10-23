###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#   Special thanks goes to comitters:
#       - maddhin(FHEM Forum)         Thanks for Readings and Commandref
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
#######
#######
#
##
##



package main;


my $missingModul = "";

use strict;
use warnings;

use HttpUtils;
eval "use Encode qw(encode encode_utf8 decode_utf8);1" or $missingModul .= "Encode ";
eval "use JSON;1" or $missingModul .= "JSON ";


my $version = "0.2.0";




### Air Quality Index scale
my %AQIS = (
            1   => { 'i18nde' => 'Gut'                                          ,'i18nen' => 'Good'                             ,'bgcolor' => '#009966'},
            2   => { 'i18nde' => 'Moderat'                                      ,'i18nen' => 'Moderate'                         ,'bgcolor' => '#ffde33'},
            3   => { 'i18nde' => 'Ungesund für empfindliche Personengruppen'    ,'i18nen' => 'Unhealthy for Sensitive Groups'   ,'bgcolor' => '#ff9933'},
            4   => { 'i18nde' => 'Ungesund'                                     ,'i18nen' => 'Unhealthy'                        ,'bgcolor' => '#cc0033'},
            5   => { 'i18nde' => 'Sehr ungesund'                                ,'i18nen' => 'Very Unhealthy'                   ,'bgcolor' => '#660099'},
            6   => { 'i18nde' => 'Gefährlich'                                   ,'i18nen' => 'Hazardous'                        ,'bgcolor' => '#7e0023'},
    );



# Declare functions
sub Aqicn_Attr(@);
sub Aqicn_Define($$);
sub Aqicn_Initialize($);
sub Aqicn_Get($$@);
sub Aqicn_Notify($$);
sub Aqicn_GetData($;$);
sub Aqicn_Undef($$);
sub Aqicn_ResponseProcessing($$$);
sub Aqicn_ReadingsProcessing_SearchStationResponse($$);
sub Aqicn_ReadingsProcessing_AqiResponse($);
sub Aqicn_ErrorHandling($$$);
sub Aqicn_WriteReadings($$);
sub Aqicn_Timer_GetData($);
sub Aqicn_AirPollutionLevel($);
sub Aqicn_HtmlStyle($);
sub Aqicn_i18n_de($);
sub Aqicn_i18n_en($);
sub Aqicn_HealthImplications($$);






my %paths = (   'statussoe'         => 'system_status/soe',
                'aggregates'        => 'meters/aggregates',
                'siteinfo'          => 'site_info',
                'sitemaster'        => 'sitemaster',
                'powerwalls'        => 'powerwalls',
                'registration'      => 'customer/registration',
                'status'            => 'status'
);


sub Aqicn_Initialize($) {

    my ($hash) = @_;
    
    # Consumer
    $hash->{GetFn}      = "Aqicn_Get";
    $hash->{DefFn}      = "Aqicn_Define";
    $hash->{UndefFn}    = "Aqicn_Undef";
    $hash->{NotifyFn}   = "Aqicn_Notify";
    
    $hash->{AttrFn}     = "Aqicn_Attr";
    $hash->{AttrList}   = "interval ".
                          "disable:1 ".
                          "language:de,en ".
                          $readingFnAttributes;
    
    foreach my $d(sort keys %{$modules{Aqicn}{defptr}}) {
    
        my $hash = $modules{Aqicn}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

sub Aqicn_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    
    
    if( $a[2] =~ /^token=/ ) {
        $a[2] =~ m/token=([^\s]*)/;
        $hash->{TOKEN} = $1;
    
    } else {
        $hash->{UID} = $a[2];
    }
    
    return "Cannot define a Aqicn device. Perl modul $missingModul is missing." if ( $missingModul );
    return "too few parameters: define <name> Aqicn <OPTION-PARAMETER>" if( @a != 3 );
    return "too few parameters: define <name> Aqicn token=<TOKEN-KEY>" if( not defined($hash->{TOKEN}) and not defined($modules{Aqicn}{defptr}{TOKEN}) );
    return "too few parameters: define <name> Aqicn <STATION-UID>" if( not defined($hash->{UID}) and defined($modules{Aqicn}{defptr}{TOKEN}) );
    
    
    my $name                = $a[0];

    $hash->{VERSION}        = $version;
    $hash->{NOTIFYDEV}      = "global";
    
    
    
    
    
    if( defined($hash->{TOKEN}) ) {
        return "there is already a Aqicn Head Device, did you want to define a Aqicn station use: define <name> Aqicn <STATION-UID>" if( $modules{Aqicn}{defptr}{TOKEN} );

        $hash->{HOST}                           = 'api.waqi.info';
        $attr{$name}{room}                      = "AQICN" if( !defined( $attr{$name}{room} ) );
    
        readingsSingleUpdate ( $hash, "state", "ready for search", 1 );
        
        Log3 $name, 3, "Aqicn ($name) - defined Aqicn Head Device with API-Key $hash->{TOKEN}";
        $modules{Aqicn}{defptr}{TOKEN}         = $hash;

    } elsif( defined($hash->{UID}) ) {  

        $attr{$name}{room}                      = "AQICN" if( !defined( $attr{$name}{room} ) );
        $hash->{INTERVAL}                       = 3600;
        $hash->{HEADDEVICE}                     = $modules{Aqicn}{defptr}{TOKEN}->{NAME};
        
        readingsSingleUpdate ( $hash, "state", "initialized", 1 );
        
        Log3 $name, 3, "Aqicn ($name) - defined Aqicn Station Device with Station UID $hash->{UID}";
        
        $modules{Aqicn}{defptr}{UID}            = $hash;
    }

    return undef;
}

sub Aqicn_Undef($$) {

    my ( $hash, $arg )  = @_;
    
    my $name            = $hash->{NAME};


    if( defined($modules{Aqicn}{defptr}{TOKEN}) and $hash->{TOKEN} ) {
        return "there is a Aqicn Station Device present, please delete all Station Device first"
        unless( not defined($modules{Aqicn}{defptr}{UID}) );
        
        delete $modules{Aqicn}{defptr}{TOKEN};
    
    } elsif( defined($modules{Aqicn}{defptr}{UID}) and $hash->{UID} ) {
        delete $modules{Aqicn}{defptr}{UID};
    }
    
    RemoveInternalTimer( $hash );
    Log3 $name, 3, "Aqicn ($name) - Device $name deleted";

    return undef;
}

sub Aqicn_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash                                = $defs{$name};


    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            RemoveInternalTimer($hash);
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "Aqicn ($name) - disabled";
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "Aqicn ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'"
            unless($attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/);
            Log3 $name, 3, "Aqicn ($name) - disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
        
        } elsif( $cmd eq "del" ) {
            Log3 $name, 3, "Aqicn ($name) - enabled";
            readingsSingleUpdate( $hash, "state", "active", 1 );
        }
    }
    
    if( $attrName eq "interval" ) {
        if( $cmd eq "set" ) {
            if( $attrVal < 30 ) {
                Log3 $name, 3, "Aqicn ($name) - interval too small, please use something >= 30 (sec), default is 300 (sec)";
                return "interval too small, please use something >= 30 (sec), default is 300 (sec)";
            
            } else {
                RemoveInternalTimer($hash);
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "Aqicn ($name) - set interval to $attrVal";
                Aqicn_Timer_GetData($hash);
            }
        } elsif( $cmd eq "del" ) {
            RemoveInternalTimer($hash);
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "Aqicn ($name) - set interval to default";
            Aqicn_Timer_GetData($hash);
        }
    }
    
    return undef;
}

sub Aqicn_Notify($$) {

    my ($hash,$dev) = @_;
    my $name = $hash->{NAME};
    return if (IsDisabled($name));
    
    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events = deviceEvents($dev,1);
    return if (!$events);


    Aqicn_Timer_GetData($hash) if( (grep /^INITIALIZED$/,@{$events}
                                    or grep /^DELETEATTR.$name.disable$/,@{$events}
                                    or (grep /^DEFINED.$name$/,@{$events} and $init_done))
                                    and defined($hash->{UID}) );
    return;
}

sub Aqicn_Get($$@) {
    
    my ($hash, $name, @aa)  = @_;
    my ($cmd, @args)        = @aa;


    if( $cmd eq 'update' ) {
        
        Aqicn_GetData($hash);
        return undef;
        
    } elsif( $cmd eq 'stationSearchByCity' ) {
        return "usage: $cmd" if( @args == 0 );
        
        my $city = join( " ", @args );
        my $ret;
        $ret = Aqicn_GetData($hash,$city);
        return $ret;

    } else {
    
        my $list = '';
        $list .= 'update:noArg' if( defined($hash->{UID}) );
        $list .= 'stationSearchByCity' if( defined($hash->{TOKEN}) );
        
        return "Unknown argument $cmd, choose one of $list";
    }
}

sub Aqicn_Timer_GetData($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};


    if( not IsDisabled($name) ) {
        Aqicn_GetData($hash);
        
    } else {
        readingsSingleUpdate($hash,'state','disabled',1);
    }

    InternalTimer( gettimeofday()+$hash->{INTERVAL}, 'Aqicn_Timer_GetData', $hash );
    Log3 $name, 4, "Aqicn ($name) - Call InternalTimer Aqicn_Timer_GetData";
}

sub Aqicn_GetData($;$) {

    my ($hash,$cityName)    = @_;
    
    my $name                = $hash->{NAME};
    my $host                = $modules{Aqicn}{defptr}{TOKEN}->{HOST};
    my $token               = $modules{Aqicn}{defptr}{TOKEN}->{TOKEN};
    my $uri;
    
    
    if( $hash->{UID} ) {
        my $uid     = $hash->{UID};
        $uri        = $host . '/feed/@' . $hash->{UID} . '/?token=' . $token;
        readingsSingleUpdate($hash,'state','fetch data',1);
    
    } else {
        $uri        = $host . '/search/?token=' . $token . '&keyword=' . urlEncode($cityName);
    }

    my $param = {
            url         => "https://".$uri,
            timeout     => 5,
            method      => 'GET',
            hash        => $hash,
            doTrigger   => 1,
            callback    => \&Aqicn_ErrorHandling,
        };
        
    $param->{cl} = $hash->{CL} if( $hash->{TOKEN} and ref($hash->{CL}) eq 'HASH' );
    
    HttpUtils_NonblockingGet($param);
    Log3 $name, 4, "Aqicn ($name) - Send with URI: https://$uri";
}

sub Aqicn_ErrorHandling($$$) {

    my ($param,$err,$data)  = @_;
    
    my $hash                = $param->{hash};
    my $name                = $hash->{NAME};


    Log3 $name, 4, "Aqicn ($name) - Recieve JSON data: $data";
    #Log3 $name, 3, "Aqicn ($name) - Recieve HTTP Code: $param->{code}";
    #Log3 $name, 3, "Aqicn ($name) - Recieve Error: $err";

    ### Begin Error Handling
    
    if( defined( $err ) ) {
        if( $err ne "" ) {
            if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
                asyncOutput( $param->{cl}, "Request Error: $err\r\n" );
            }

            readingsBeginUpdate( $hash );
            readingsBulkUpdate( $hash, 'state', $err, 1);
            readingsBulkUpdate( $hash, 'lastRequestError', $err, 1 );
            readingsEndUpdate( $hash, 1 );
            
            Log3 $name, 3, "Aqicn ($name) - RequestERROR: $err";

            return;
        }
    }

    if( $data eq "" and exists( $param->{code} ) && $param->{code} ne 200 ) {
        #if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
        #    asyncOutput( $param->{cl}, "Request Error: $param->{code}\r\n" );
        #}
    
        readingsBeginUpdate( $hash );
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );

        readingsBulkUpdate( $hash, 'lastRequestError', $param->{code}, 1 );

        Log3 $name, 3, "Aqicn ($name) - RequestERROR: ".$param->{code};

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 5, "Aqicn ($name) - RequestERROR: received http code ".$param->{code}." without any data after requesting";

        return;
    }

    if( ( $data =~ /Error/i ) and exists( $param->{code} ) ) {
        #if( $param->{cl} && $param->{cl}{canAsyncOutput} ) {
        #    asyncOutput( $param->{cl}, "Request Error: $param->{code}\r\n" );
        #}
    
        readingsBeginUpdate( $hash );
        
        readingsBulkUpdate( $hash, 'state', $param->{code}, 1 );
        readingsBulkUpdate( $hash, "lastRequestError", $param->{code}, 1 );

        readingsEndUpdate( $hash, 1 );
    
        Log3 $name, 3, "Aqicn ($name) - statusRequestERROR: http error ".$param->{code};

        return;
        ### End Error Handling
    }
    
    Log3 $name, 4, "Aqicn ($name) - Recieve JSON data: $data";
    
    Aqicn_ResponseProcessing($hash,$data,$param);
}

sub Aqicn_ResponseProcessing($$$) {

    my ($hash,$json,$param) = @_;
    
    my $name                = $hash->{NAME};
    my $decode_json;
    my $readings;


    $decode_json    = eval{decode_json($json)};
    if($@){
        Log3 $name, 4, "Aqicn ($name) - error while request: $@";
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, 'JSON_Error', $@);
        readingsBulkUpdate($hash, 'httpCode', $param->{code});
        readingsBulkUpdate($hash, 'state', 'JSON error');
        readingsEndUpdate($hash,1);
        return;
    }
    
    
    #### Verarbeitung der Readings zum passenden
    if( $hash->{TOKEN} ) {
        Aqicn_ReadingsProcessing_SearchStationResponse($decode_json,$param);
        readingsSingleUpdate($hash,'state','search finished',1);
        return;
    } elsif( $hash->{UID} ) {
        $readings = Aqicn_ReadingsProcessing_AqiResponse($decode_json);
    }
    
    
    Aqicn_WriteReadings($hash,$readings);
}

sub Aqicn_WriteReadings($$) {

    my ($hash,$readings)    = @_;
    
    my $name                = $hash->{NAME};
    
    
    Log3 $name, 4, "Aqicn ($name) - Write Readings";
    
    
    readingsBeginUpdate($hash);
    while( my ($r,$v) = each %{$readings} ) {
        readingsBulkUpdate($hash,$r,$v);
    }
    
    if( defined($readings->{'PM2.5-AQI'}) ) {
        readingsBulkUpdateIfChanged($hash,'htmlStyle','<div style="background-color: '.$AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'bgcolor'}.';">'.( ((AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en') ? "$AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'i18nde'}: $readings->{'PM2.5-AQI'} " : " $AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'i18nen'}: $readings->{'PM2.5-AQI'}").'</div>');
        
        readingsBulkUpdateIfChanged($hash,'state',( ((AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en') ? "$AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'i18nde'}: $readings->{'PM2.5-AQI'}" : "$AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'i18nen'}: $readings->{'PM2.5-AQI'}") );
        
         readingsBulkUpdateIfChanged($hash,'APL',( ((AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en') ? "$AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'i18nde'}" : "$AQIS{Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})}{'i18nen'}") );
        
         readingsBulkUpdateIfChanged($hash,'healthImplications',Aqicn_HealthImplications($hash,Aqicn_AirPollutionLevel($readings->{'PM2.5-AQI'})) );
    } else {
        readingsBulkUpdateIfChanged($hash,'htmlStyle','<div style="background-color: '.$AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'bgcolor'}.';">'.( ((AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en') ? "$AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'i18nde'}: $readings->{'AQI'} " : " $AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'i18nen'}: $readings->{'AQI'}").'</div>');
    
        readingsBulkUpdateIfChanged($hash,'state',( ((AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en') ? "$AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'i18nde'}: $readings->{'AQI'}" : "$AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'i18nen'}: $readings->{'AQI'}") );
        
        readingsBulkUpdateIfChanged($hash,'APL',( ((AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en') ? "$AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'i18nde'}" : "$AQIS{Aqicn_AirPollutionLevel($readings->{'AQI'})}{'i18nen'}") );
        
        readingsBulkUpdateIfChanged($hash,'healthImplications',Aqicn_HealthImplications($hash,Aqicn_AirPollutionLevel($readings->{'AQI'})) );
    }
        
    readingsEndUpdate($hash,1);
}

#####
#####
## my little Helper
sub Aqicn_ReadingsProcessing_SearchStationResponse($$) {
    
    my ($decode_json,$param)     = @_;
    
    
    if( $param->{cl} and $param->{cl}->{TYPE} eq 'FHEMWEB' ) {
        
        my $ret = '<html><table><tr><td>';
        $ret .= '<table class="block wide">';
        $ret .= '<tr class="even">';
        $ret .= "<td><b>City</b></td>";
        $ret .= "<td><b>Last Update Time</b></td>";
        $ret .= "<td><b>Latitude</b></td>";
        $ret .= "<td><b>Longitude</b></td>";
        $ret .= "<td></td>";
        $ret .= '</tr>';

        
        
        if( ref($decode_json->{data}) eq "ARRAY" and scalar(@{$decode_json->{data}}) > 0 ) {
            
            my $linecount=1;
            foreach my $dataset (@{$decode_json->{data}}) {
                if ( $linecount % 2 == 0 ) {
                    $ret .= '<tr class="even">';
                } else {
                    $ret .= '<tr class="odd">';
                }

                $dataset->{station}{name} =~ s/'//g;
                $ret .= "<td>".encode_utf8($dataset->{station}{name})."</td>";
                $ret .= "<td>$dataset->{'time'}{stime}</td>";
                $ret .= "<td>$dataset->{station}{geo}[0]</td>";
                $ret .= "<td>$dataset->{station}{geo}[1]</td>";
                
                
                ###### create Links
                my $aHref;
                
                # create Google Map Link
                $aHref="<a target=\"_blank\" href=\"https://www.google.de/maps/search/".$dataset->{station}{geo}[0]."+".$dataset->{station}{geo}[1]."\">Station on Google Maps</a>";
                $ret .= "<td>".$aHref."</td>";

                # create define Link
                my @headerHost = grep /Origin/, @FW_httpheader;
                $headerHost[0] = 'Origin: no Hostname at FHEMWEB Header available'
                unless( defined($headerHost[0]) );
                $headerHost[0] =~ m/Origin:.([^\s]*)/;
                $headerHost[0] = $1;
                $aHref="<a href=\"".$headerHost[0]."/fhem?cmd=define+".makeDeviceName($dataset->{station}{name})."+Aqicn+".$dataset->{uid}.$FW_CSRF."\">Create Station Device</a>";
                $ret .= "<td>".$aHref."</td>";
                $ret .= '</tr>';
                $linecount++;
            }
        }
        
        $ret .= '</table></td></tr>';
        $ret .= '</table></html>';

        asyncOutput( $param->{cl}, $ret ) if( $param->{cl} and $param->{cl}{canAsyncOutput} );
        return;
        
    } elsif( $param->{cl} and $param->{cl}->{TYPE} eq 'telnet' ) {
        my $ret = '';
        
        foreach my $dataset (@{$decode_json->{data}}) {
            $ret .= encode_utf8($dataset->{station}{name}) . "| $dataset->{'time'}{stime} | $dataset->{station}{geo}[0] | $dataset->{station}{geo}[1] | define " . makeDeviceName($dataset->{station}{name}) . " Aqicn $dataset->{uid}\r\n";
        }

        asyncOutput( $param->{cl}, $ret ) if( $param->{cl} && $param->{cl}{canAsyncOutput} );
        return;
    }
}

sub Aqicn_ReadingsProcessing_AqiResponse($) {
    
    my ($decode_json)     = @_;

    my %readings;


    $readings{'CO-AQI'}         = $decode_json->{data}{iaqi}{co}{v};
    $readings{'NO2-AQI'}        = $decode_json->{data}{iaqi}{no2}{v};
    $readings{'PM10-AQI'}       = $decode_json->{data}{iaqi}{pm10}{v};
    $readings{'PM2.5-AQI'}      = $decode_json->{data}{iaqi}{pm25}{v};
    $readings{'AQI'}            = $decode_json->{data}{aqi};
    $readings{'O3-AQI'}         = $decode_json->{data}{iaqi}{o3}{v};
    $readings{'SO2-AQI'}        = $decode_json->{data}{iaqi}{so2}{v};
    $readings{'temperature'}    = $decode_json->{data}{iaqi}{t}{v};
    $readings{'pressure'}       = $decode_json->{data}{iaqi}{p}{v};
    $readings{'humidity'}       = $decode_json->{data}{iaqi}{h}{v};
    $readings{'status'}         = $decode_json->{status};
    $readings{'pubDate'}        = $decode_json->{data}{time}{s};
    $readings{'pubUnixTime'}    = $decode_json->{data}{time}{v};
    $readings{'pubTimezone'}    = $decode_json->{data}{time}{tz};
    $readings{'windSpeed'}      = $decode_json->{data}{iaqi}{w}{v};
    $readings{'windDirection'}  = $decode_json->{data}{iaqi}{wd}{v};
    $readings{'dewpoint'}       = $decode_json->{data}{iaqi}{d}{v};
    $readings{'dominatPoll'}    = $decode_json->{data}{dominentpol};

    return \%readings;
}

sub Aqicn_AirPollutionLevel($) {

    my $aqi = shift;

    my $apl;


    if($aqi < 51)       { $apl = 1}
    elsif($aqi < 101)   { $apl = 2}
    elsif($aqi < 151)   { $apl = 3}
    elsif($aqi < 201)   { $apl = 4}
    elsif($aqi < 301)   { $apl = 5}
    else                { $apl = 6}
    
    return $apl;
}

sub Aqicn_HealthImplications($$) {

    my ($hash,$apl) = @_;

    my $name        = $hash->{NAME};

    my %HIen = (
            1   => 'Air quality is acceptable; however, for some pollutants there may be a moderate health concern for a very small number of people who are unusually sensitive to air pollution.',
            2   => 'Air quality is acceptable; however, for some pollutants there may be a moderate health concern for a very small number of people who are unusually sensitive to air pollution.',
            3   => 'Members of sensitive groups may experience health effects. The general public is not likely to be affected.',
            4   => 'Everyone may begin to experience health effects; members of sensitive groups may experience more serious health effects',
            5   => 'Health warnings of emergency conditions. The entire population is more likely to be affected.',
            6   => 'Health alert: everyone may experience more serious health effects'
        );
        
     my %HIde = (
            1   => 'Die Qualität der Luft gilt als zufriedenstellend und die Luftverschmutzung stellt ein geringes oder kein Risiko dar',
            2   => 'Die Luftqualität ist insgesamt akzeptabel. Bei manchen Schadstoffe besteht jedoch eventuell eine geringe Gesundheitsgefahr für einen sehr kleinen Personenkreis, der sehr empfindlich auf Luftverschmutzung ist.',
            3   => 'Bei Mitgliedern von empfindlichen Personengruppen können gesundheitliche Auswirkungen auftreten. Die allgemeine Öffentlichkeit ist wahrscheinlich nicht betroffen.',
            4   => 'Erste gesundheitliche Auswirkungen können sich bei allen Personen einstellen. Bei empfindlichen Personengruppen können ernstere gesundheitliche Auswirkungen auftreten.',
            5   => 'Gesundheitswarnung aufgrund einer Notfallsituation. Die gesamte Bevölkerung ist voraussichtlich betroffen.',
            6   => 'Gesundheitsalarm: Jeder muss mit dem Auftreten ernsterer Gesundheitsschäden rechnen'
        );
        
        
        return ( (AttrVal('global','language','none') eq 'DE' or AttrVal($name,'language','none') eq 'de') and AttrVal($name,'language','none') ne 'en' ? $HIde{$apl} : $HIen{$apl} );    
}





1;


=pod

=item device
=item summary       Air Quality Index proving a transparent Air Quality information
=item summary_DE    Air Quality Index Nachweis einer transparenten Luftqualitätsinformation

=begin html

<a name="Aqicn"></a>
<h3>Air Quality Index</h3>
<ul>
    This modul fetch Air Quality data from http://aqicn.org.
    <br><br>
    <a name="Aqicndefine"></a>
    <b>Define</b>
    <ul><br>
        <code>define &lt;name&gt; Aqicn</code>
    <br><br>
    Example:
    <ul><br>
        <code>define aqicnMaster Aqicn</code><br>
    </ul>
    <br>
    This statement creates the Aqicn Master Device.<br>
    After the device has been created, you can search Aqicn Station by city name and create automatically the station device.
    </ul>
    <br><br>
    <a name="Aqicnreadings"></a>
    <b>Readings</b>
    <ul>
        <li>APL - Air Pollution Level</li>
        <li>AQI - Air Quality Index (AQI) of the dominant pollutant in city. Values are converted from µg/m³ to AQI level using US EPA standards. For more detailed information: https://en.wikipedia.org/wiki/Air_quality_index and https://www.airnow.gov/index.cfm?action=aqi_brochure.index. </li>
        <li>CO-AQI - AQI of CO (carbon monoxide). An AQI of 100 for carbon monoxide corresponds to a level of 9 parts per million (averaged over 8 hours).</li>
        <li>NO2-AQI - AQI of NO2 (nitrogen dioxide). See also https://www.airnow.gov/index.cfm?action=pubs.aqiguidenox</li>
        <li>PM10-AQI - AQI of PM10 (respirable particulate matter). For particles up to 10 micrometers in diameter: An AQI of 100 corresponds to 150 micrograms per cubic meter (averaged over 24 hours).</li>
        <li>PM2.5-AQI - AQI of PM2.5 (fine particulate matter). For particles up to 2.5 micrometers in diameter: An AQI of 100 corresponds to 35 micrograms per cubic meter (averaged over 24 hours).</li>
        <li>O3-AQI - AQI of O3 (ozone). An AQI of 100 for ozone corresponds to an ozone level of 0.075 parts per million (averaged over 8 hours). See also https://www.airnow.gov/index.cfm?action=pubs.aqiguideozone</li>
        <li>SO2-AQI - AQI of SO2 (sulfur dioxide). An AQI of 100 for sulfur dioxide corresponds to a level of 75 parts per billion (averaged over one hour).</li>
        <li>temperature - Temperature in degrees Celsius</li>
        <li>pressure - Atmospheric pressure in hectopascals (hPa)</li>
        <li>humidity - Relative humidity in percent</li>
        <li>state- Current AQI and air pollution level</li>
        <li>status - condition of the data</li>
        <li>pubDate- Local time of publishing the data</li>
        <li>pubUnixTime - Unix time stamp of local time but converted wrongly, if local time is e.g. 1300 GMT+1, the time stamp shows 1300 UTC.</li>
        <li>pubTimezone - Time zone of the city (UTC)</li>
        <li>windspeed - Wind speed in kilometer per hour</li>
        <li>windDirection - Wind direction</li>
        <li>dominatPoll - Dominant pollutant in city</li>
        <li>dewpoint - Dew in degrees Celsius</li>
        <li>healthImplications - Information about Health Implications</li>
        <li>htmlStyle - can be used to format the STATE and FHEMWEB (Example: stateFormate htmlStyle</li>
    </ul>
    <br>
    <a name="Aqicnget"></a>
    <b>get</b>
    <ul>
        <li>stationSearchByCity - search station by city name and open the result in seperate popup window</li>
        <li>update - fetch new data every x times</li>
    </ul>
    <br>
    <a name="Aqicnattribute"></a>
    <b>Attribute</b>
    <ul>
        <li>interval - interval in seconds for automatically fetch data (default 3600)</li>
    </ul>
</ul>

=end html
=begin html_DE

<a name="Aqicn"></a>
<h3>Air Quality Index</h3>

=end html_DE
=cut

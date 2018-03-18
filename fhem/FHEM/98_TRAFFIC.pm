#########################################################################
# $Id$
# fhem Modul which provides traffic details with Google Distance API
#   
#     This file is part of fhem.
# 
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
# 
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
# 
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
#     versioning: MAJOR.MINOR.PATCH, increment the:
#     MAJOR version when you make incompatible API changes
#      - includes changing CLI options, changing log-messages
#     MINOR version when you add functionality in a backwards-compatible manner
#      - includes adding new features and log-messages (as long as they don't break anything existing)
#     PATCH version when you make backwards-compatible bug fixes.
#
##############################################################################
#   Changelog:
#
#   2016-07-26 initial release
#   2016-07-28 added eta, readings in minutes
#   2016-08-01 changed JSON decoding/encofing, added stateReading attribute, added outputReadings attribute
#   2016-08-02 added attribute includeReturn, round minutes & smart zero'ing, avoid negative values, added update burst 
#   2016-08-05 fixed 3 perl warnings
#   2016-08-09 added auto-update if status returns UNKOWN_ERROR, added outputReading average
#   2016-09-25 bugfix Blocking, improved errormessage
#   2016-10-07 version 1.0, adding to SVN
#   2016-10-15 adding attribute updateSchedule to provide flexible updates, changed internal interval to INTERVAL
#   2016-12-13 adding travelMode, fixing stateReading with value 0
#   2016-12-15 adding reverseWaypoints attribute, adding weblink with auto create route via gmaps on verbose 5
#   2017-04-21 reduced log entries if verbose is not set, fixed JSON error, Map available through FHEM-Web-toggle, and direct link
#              Map https, with APIKey, Traffic & customizable, new attributes  GoogleMapsStyle,GoogleMapsSize,GoogleMapsLocation,GoogleMapsStroke,GoogleMapsDisableUI
#   2017-04-21 added buttons to save current map settings, renamed attribute GoogleMapsLocation to GoogleMapsCenter
#   2017-04-22 v1.3.2 stroke supports weight and opacity, minor fixes
#   2017-12-51 v1.3.3 catch JSON decode issue, addedn Dbog_splitFn, added reading summary, new attr GoogleMapsFixedMap, net attr alternatives, new reading alternatives, alternatives, lighter&thinner on map
#   2018-01-26 v1.3.4 fixed Dbog_splitFn, improved exception handling 
#   2018-01-28 v1.3.5 fixed Dbog_splitFn again
#   2018-01-28 v1.3.6 removed perl warning on module load
#   2018-03-02 v1.3.7 fixed issue with special character in readings, updateschedule supports multiple timeframes per day
#
##############################################################################

package main;

use strict;                          
use warnings;                        
use Data::Dumper;
use Time::HiRes qw(gettimeofday);
use Time::Local;
use LWP::Simple qw($ua get);
use Blocking;
use POSIX;
use JSON;
die "MIME::Base64 missing!" unless(eval{require MIME::Base64});
die "JSON missing!" unless(eval{require JSON});

sub TRAFFIC_Initialize($);
sub TRAFFIC_Define($$);
sub TRAFFIC_Undef($$);
sub TRAFFIC_Set($@);
sub TRAFFIC_Attr(@);
sub TRAFFIC_GetUpdate($);
sub TRAFFIC_DbLog_split($);

my %TRcmds = (
    'update' => 'noArg',
);
my $TRVersion = '1.3.7';

sub TRAFFIC_Initialize($){

    my ($hash) = @_;

    $hash->{DefFn}      = "TRAFFIC_Define";
    $hash->{UndefFn}    = "TRAFFIC_Undef";
    $hash->{SetFn}      = "TRAFFIC_Set";

    $hash->{AttrFn}     = "TRAFFIC_Attr";
    $hash->{AttrList}   = 
      "disable:0,1 start_address end_address raw_data:0,1 language waypoints returnWaypoints stateReading outputReadings travelMode:driving,walking,bicycling,transit includeReturn:0,1 updateSchedule GoogleMapsStyle:default,silver,dark,night GoogleMapsSize GoogleMapsZoom GoogleMapsCenter GoogleMapsStroke GoogleMapsTrafficLayer:0,1 GoogleMapsDisableUI:0,1 GoogleMapsFixedMap:0,1 alternatives:0,1 " .
      $readingFnAttributes;  

    $data{FWEXT}{"/TRAFFIC"}{FUNC} = "TRAFFIC";
    $data{FWEXT}{"/TRAFFIC"}{FORKABLE} = 1; 

    $hash->{FW_detailFn}   = "TRAFFIC_fhemwebFn";
    $hash->{DbLog_splitFn} = "TRAFFIC_DbLog_split";

}

sub TRAFFIC_Define($$){

    my ($hash, $allDefs) = @_;
    
    my @deflines = split('\n',$allDefs);
    my @apiDefs = split('[ \t]+', shift @deflines);
    
    if(int(@apiDefs) < 3) {
        return "too few parameters: 'define <name> TRAFFIC <APIKEY>'";
    }

    $hash->{NAME}    = $apiDefs[0];
    $hash->{APIKEY}  = $apiDefs[2];
    $hash->{VERSION} = $TRVersion;
    delete($hash->{BURSTCOUNT}) if $hash->{BURSTCOUNT};
    delete($hash->{BURSTINTERVAL}) if $hash->{BURSTINTERVAL};

    my $name = $hash->{NAME};

    #clear all readings
    foreach my $clearReading ( keys %{$hash->{READINGS}}){
        Log3 $hash, 5, "TRAFFIC: ($name) READING: $clearReading deleted";
        delete($hash->{READINGS}{$clearReading}); 
    }
    
    #clear all helpers
    foreach my $helperName ( keys %{$hash->{helper}}){
        delete($hash->{helper}{$helperName});
    }
    
    # clear weblink
    FW_fC("delete ".$name."_weblink");
    
    # basic update INTERVAL
    if(scalar(@apiDefs) > 3 && $apiDefs[3] =~ m/^\d+$/){
        $hash->{INTERVAL} = $apiDefs[3];
    }else{
        $hash->{INTERVAL} = 3600;
    }
    Log3 $hash, 4, "TRAFFIC: ($name) defined ".$hash->{NAME}.' with interval set to '.$hash->{INTERVAL};
    
    # put in default verbose level
    $attr{$name}{"verbose"} = 1 if !$attr{$name}{"verbose"};
    $attr{$name}{"outputReadings"} = "text" if !$attr{$name}{"outputReadings"};
    
    readingsSingleUpdate( $hash, "state", "Initialized", 1 );
    
    my $firstTrigger = gettimeofday() + 2;
    $hash->{TRIGGERTIME}     = $firstTrigger;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($firstTrigger);

    RemoveInternalTimer($hash);
    InternalTimer($firstTrigger, "TRAFFIC_StartUpdate", $hash, 0);
    Log3 $hash, 5, "TRAFFIC: ($name) InternalTimer set to call GetUpdate in 2 seconds for the first time";
    return undef;
}


sub TRAFFIC_Undef($$){      
    my ( $hash, $arg ) = @_;       
    RemoveInternalTimer ($hash);
    return undef;                  
}    

sub TRAFFIC_fhemwebFn($$$$) {
    my ($FW_wname, $device, $room, $pageHash) = @_; # pageHash is set for summaryFn.
    my $name = $device;
    my $hash = $defs{$name};

    my $mapState = ReadingsVal($device,".map", "off") eq "on" ? "off" : "on";
    my $web = "<span><a href=\"$FW_ME?detail=$device&amp;cmd.$device=setreading $device .map $mapState$FW_CSRF\">toggle Map</a>&nbsp;&nbsp;</span><br>";
    
    if (ReadingsVal($device,".map","off") eq "on") {
        $web .= TRAFFIC_GetMap($device);
        $web .= TRAFFIC_weblink($device);

        $web .= "<form method=\"$FW_formmethod\" action=\"$FW_ME$FW_subdir\" >";
        $web .= FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}) if($FW_CSRF);
        $web .= FW_hidden("detail", $device);
        $web .= FW_hidden("dev.attr$device", $device);
        $web .= "<input style='display:none' type='submit' value='save Zoom' class='attr' id='currentMapZoomSubmit'>";
        $web .= "<input type='hidden' name='val.attr$device' value='' id='currentMapZoom'>";
        $web .= "<input type='hidden' name='cmd.attr$device' value='attr'>";
        $web .= "<input type='hidden' name='arg.attr$device' value='GoogleMapsZoom'>";
        $web .= "</form>";

        $web .= "<form method=\"$FW_formmethod\" action=\"$FW_ME$FW_subdir\" >";
        $web .= FW_hidden("fwcsrf", $defs{$FW_wname}{CSRFTOKEN}) if($FW_CSRF);
        $web .= FW_hidden("detail", $device);
        $web .= FW_hidden("dev.attr$device", $device);
        $web .= "<input style='display:none'  type='submit' value='save Center' class='attr' id='currentMapCenterSubmit'>";
        $web .= "<input type='hidden' name='val.attr$device' value='' id='currentMapCenter'>";
        $web .= "<input type='hidden' name='cmd.attr$device' value='attr'>";
        $web .= "<input type='hidden' name='arg.attr$device' value='GoogleMapsCenter'>";
        $web .= "</form>";
    }
    return $web;
}

sub TRAFFIC_GetMap($@){
    my $device = shift();
    my $name = $device;
    my $hash = $defs{$name};
    
    my $debugPoly=1;
    my @alternativesPoly    = split(',',decode_base64($hash->{helper}{'Poly'}));
    my $returnDebugPoly     = $hash->{helper}{'return_Poly'};
    my $GoogleMapsCenter    = AttrVal($name, "GoogleMapsCenter", $hash->{helper}{'GoogleMapsCenter'});

    if(!$debugPoly || !$GoogleMapsCenter){
        return "<div>please update your device first</div>";
    }
    
    my%GoogleMapsStyles=(
        'default'   => "[]",
        'silver'    => '[{"elementType":"geometry","stylers":[{"color":"#f5f5f5"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#f5f5f5"}]},{"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"geometry","stylers":[{"color":"#eeeeee"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#e5e5e5"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#ffffff"}]},{"featureType":"road.arterial","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#dadada"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"transit.line","elementType":"geometry","stylers":[{"color":"#e5e5e5"}]},{"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#eeeeee"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#c9c9c9"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]}]',
        'dark'      => '[{"elementType":"geometry","stylers":[{"color":"#212121"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#212121"}]},{"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#757575"}]},{"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#9e9e9e"}]},{"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#bdbdbd"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#181818"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"poi.park","elementType":"labels.text.stroke","stylers":[{"color":"#1b1b1b"}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2c"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8a8a8a"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#373737"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3c3c3c"}]},{"featureType":"road.highway.controlled_access","elementType":"geometry","stylers":[{"color":"#4e4e4e"}]},{"featureType":"road.local","elementType":"labels.text.fill","stylers":[{"color":"#616161"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#757575"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#000000"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d3d"}]}]',
        'night'     => '[{"elementType":"geometry","stylers":[{"color":"#242f3e"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#263c3f"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#6b9a76"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#38414e"}]},{"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#212a37"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#9ca5b3"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#746855"}]},{"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1f2835"}]},{"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#f3d19c"}]},{"featureType":"transit","elementType":"geometry","stylers":[{"color":"#2f3948"}]},{"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#d59563"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#515c6d"}]},{"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#17263c"}]}]',
    );
    my $selectedGoogleMapsStyle = $GoogleMapsStyles{ AttrVal($name, "GoogleMapsStyle", 'default' )};
    if(!$selectedGoogleMapsStyle){$selectedGoogleMapsStyle = $GoogleMapsStyles{'default'}}; #catch attribute mistake here
    
    # load map scale and zoom from attr, override if empty/na
    my ( $GoogleMapsWidth, $GoogleMapsHeight )   = AttrVal($name, "GoogleMapsSize", '800,600') =~ m/(\d+),(\d+)/;
    my ( $GoogleMapsZoom )   = AttrVal($name, "GoogleMapsZoom", '10');
    
    my ( $GoogleMapsStroke1Color, $GoogleMapsStroke1Weight, $GoogleMapsStroke1Opacity, $GoogleMapsStroke2Color, $GoogleMapsStroke2Weight, $GoogleMapsStroke2Opacity ) = AttrVal($name, "GoogleMapsStroke", '#4cde44,6,100,#FF0000,1,100') =~ m/^(#[a-zA-z0-9]+),?(\d*),?(\d*),?(#[a-zA-z0-9]+)?,?(\d*),?(\d*)/;
    
    # catch incomplete configuration here and put in defaults
    $GoogleMapsStroke1Color     = '#4cde44' if !$GoogleMapsStroke1Color;
    $GoogleMapsStroke1Weight    = '6'       if !$GoogleMapsStroke1Weight;
    $GoogleMapsStroke1Opacity   = '100'     if !$GoogleMapsStroke1Opacity;
    
    $GoogleMapsStroke2Color     = '#FF0000' if !$GoogleMapsStroke2Color;
    $GoogleMapsStroke2Weight    = '1'       if !$GoogleMapsStroke2Weight;
    $GoogleMapsStroke2Opacity   = '100'     if !$GoogleMapsStroke2Opacity;

    # make percent value to 50 to 0.5 etc
    $GoogleMapsStroke1Opacity = ($GoogleMapsStroke1Opacity / 100); 
    $GoogleMapsStroke2Opacity = ($GoogleMapsStroke2Opacity / 100);
    
    # pregenerate the alternatives colors, bit darker and thinner than the primary route
    my $GoogleMapsStrokeAColor     = '#'.lightHex($GoogleMapsStroke1Color, '0.3');
    my $GoogleMapsStrokeAWeight    = int($GoogleMapsStroke1Weight - 3);
    my $GoogleMapsStrokeAOpacity   = $GoogleMapsStroke1Opacity;

    my $GoogleMapsDisableUI = '';
    $GoogleMapsDisableUI = "disableDefaultUI: true," if AttrVal($name, "GoogleMapsDisableUI", 0) eq 1;
    
    my $GoogleMapsFixedMap = '';
    $GoogleMapsFixedMap = "draggable: false," if AttrVal($name, "GoogleMapsFixedMap", 0) eq 1;
    
    Log3 $hash, 4, "TRAFFIC: ($name) drawing map in style ".AttrVal($name, "GoogleMapsStyle", 'default' )." in $GoogleMapsWidth x $GoogleMapsHeight px";

    my $map;
    $map .= '<div><script type="text/javascript" src="https://maps.google.com/maps/api/js?key='.$hash->{APIKEY}.'&libraries=geometry&amp"></script>';
    
    foreach my $polyIndex (0..$#alternativesPoly){
        $map .=   '<input size="200" type="hidden" id="path'.$polyIndex.'" value="'.$alternativesPoly[$polyIndex].'">';
    }
    
    $map .= '<input size="200" type="hidden" id="pathR" value="'.decode_base64($returnDebugPoly).'">' if $returnDebugPoly && decode_base64($returnDebugPoly);
    $map .= '
        <div id="map"></div>
        <style>
            #map {width:'.$GoogleMapsWidth.'px;height:'.$GoogleMapsHeight.'px;}
        </style>
        <script type="text/javascript">

        function initialize() {
            var myLatlng = new google.maps.LatLng('.$GoogleMapsCenter.');
            var myOptions = {
                zoom: '.$GoogleMapsZoom.',
                '.$GoogleMapsFixedMap.'
                center: myLatlng,
                '.$GoogleMapsDisableUI.'
                mapTypeId: google.maps.MapTypeId.ROADMAP,
                styles: '.$selectedGoogleMapsStyle.'
            }
            var map = new google.maps.Map(document.getElementById("map"), myOptions);
            ';
     
    foreach my $polyIndex (1..$#alternativesPoly){
        $map .='var decodedPath = google.maps.geometry.encoding.decodePath(document.getElementById("path'.$polyIndex.'").value); 
            var decodedLevels = decodeLevels("");
            var setRegion = new google.maps.Polyline({
                path: decodedPath,
                levels: decodedLevels,
                strokeColor: "'.$GoogleMapsStrokeAColor.'",
                strokeOpacity: '.$GoogleMapsStrokeAOpacity.',
                strokeWeight: '.$GoogleMapsStrokeAWeight.',
                map: map
            });
            ';
    }
            
    $map .= 'var decodedPathR = google.maps.geometry.encoding.decodePath(document.getElementById("pathR").value); 
            var decodedLevelsR = decodeLevels("");
            var setRegionR = new google.maps.Polyline({
                path: decodedPathR,
                levels: decodedLevels,
                strokeColor: "'.$GoogleMapsStroke2Color.'",
                strokeOpacity: '.$GoogleMapsStroke2Opacity.',
                strokeWeight: '.$GoogleMapsStroke2Weight.',
                map: map
            });' if $returnDebugPoly && decode_base64($returnDebugPoly );

    $map .='var decodedPath = google.maps.geometry.encoding.decodePath(document.getElementById("path0").value); 
            var decodedLevels = decodeLevels("");
            var setRegion = new google.maps.Polyline({
                path: decodedPath,
                levels: decodedLevels,
                strokeColor: "'.$GoogleMapsStroke1Color.'",
                strokeOpacity: '.$GoogleMapsStroke1Opacity.',
                strokeWeight: '.$GoogleMapsStroke1Weight.',
                map: map
            });
            ';
    $map .= 'var trafficLayer = new google.maps.TrafficLayer();
             trafficLayer.setMap(map);' if AttrVal($name, "GoogleMapsTrafficLayer", 0) eq 1;

    $map .='
            map.addListener("zoom_changed", function() {
                document.getElementById("currentMapZoom").value = map.getZoom();
                document.getElementById("currentMapZoomSubmit").style.display = "block";
            });
            map.addListener("dragend", function() {
                document.getElementById("currentMapCenter").value = map.getCenter().lat() + "," + map.getCenter().lng();
                document.getElementById("currentMapCenterSubmit").style.display = "block";
            });
        }
        
        function decodeLevels(encodedLevelsString) {
            var decodedLevels = [];
            for (var i = 0; i < encodedLevelsString.length; ++i) {
                var level = encodedLevelsString.charCodeAt(i) - 63;
                decodedLevels.push(level);
            }
            return decodedLevels;
        }
        initialize();
        </script></div>';
        
    return $map;
}

  
#
# Attr command 
#########################################################################
sub TRAFFIC_Attr(@){

	my ($cmd,$name,$attrName,$attrValue) = @_;
    # $cmd can be "del" or "set" 
    # $name is device name
    my $hash = $defs{$name};

    if ($cmd eq "set") {        
        addToDevAttrList($name, $attrName);
        Log3 $hash, 4, "TRAFFIC: ($name)  attrName $attrName set to attrValue $attrValue";
    }
    if($attrName eq "disable" && $attrValue eq "1"){
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }
    
    if($attrName eq "outputReadings" || $attrName eq "includeReturn" || $attrName eq "verbose"){
        #clear all readings
        foreach my $clearReading ( keys %{$hash->{READINGS}}){
            Log3 $hash, 5, "TRAFFIC: ($name) READING: $clearReading deleted";
            delete($hash->{READINGS}{$clearReading}); 
        }
        #clear all helpers
        foreach my $helperName ( keys %{$hash->{helper}}){
            delete($hash->{helper}{$helperName});
        }
        # start update
        InternalTimer(gettimeofday() + 1, "TRAFFIC_StartUpdate", $hash, 0); 
    }
    return undef;
}

sub TRAFFIC_Set($@){

	my ($hash, @param) = @_;
	return "\"set <TRAFFIC>\" needs at least one argument: \n".join(" ",keys %TRcmds) if (int(@param) < 2);

    my $name = shift @param;
	my $set = shift @param;
    
    $hash->{VERSION} = $TRVersion if $hash->{VERSION} ne $TRVersion;
    
    if(AttrVal($name, "disable", 0 ) == 1){
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
        Log3 $hash, 3, "TRAFFIC: ($name) is disabled, $set not set!";
        return undef;
    }else{
        Log3 $hash, 5, "TRAFFIC: ($name) set $name $set";
    }
    
    my $validCmds = join("|",keys %TRcmds);
	if($set !~ m/$validCmds/ ) {
        return join(' ', keys %TRcmds);
	
    }elsif($set =~ m/update/){
        Log3 $hash, 5, "TRAFFIC: ($name) update command recieved";
        
        # if update burst ist specified
        if( (my $burstCount = shift @param) && (my $burstInterval = shift @param)){
            Log3 $hash, 5, "TRAFFIC: ($name) update burst is set to $burstCount $burstInterval";
            $hash->{BURSTCOUNT} = $burstCount;
            $hash->{BURSTINTERVAL} = $burstInterval;
        }else{
            Log3 $hash, 5, "TRAFFIC: ($name) no update burst set";
        }
        
        # update internal timer and update NOW
        my $updateTrigger = gettimeofday() + 1;
        $hash->{TRIGGERTIME}     = $updateTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($updateTrigger);
        RemoveInternalTimer($hash);

        # start update
        InternalTimer($updateTrigger, "TRAFFIC_StartUpdate", $hash, 0);            

        return undef;
    }

}


sub TRAFFIC_StartUpdate($){

    my ( $hash ) = @_;
    my $name = $hash->{NAME};
    my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);
    $wday=7 if $wday == 0; #sunday 0 -> sunday 7, monday 0 -> monday 1 ...


    if(AttrVal($name, "disable", 0 ) == 1){
        RemoveInternalTimer ($hash);
        Log3 $hash, 3, "TRAFFIC: ($name) is disabled";
        return undef;
    }
    if ( $hash->{INTERVAL}) {
        RemoveInternalTimer ($hash);
        delete($hash->{UPDATESCHEDULE});

        my $nextTrigger = gettimeofday() + $hash->{INTERVAL};
        
        if(defined(AttrVal($name, "updateSchedule", undef ))){
            Log3 $hash, 5, "TRAFFIC: ($name) flexible update Schedule defined";
            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
            my @updateScheduleDef = split('\|', AttrVal($name, "updateSchedule", undef ));
            foreach my $upSched (@updateScheduleDef){
                my ($upFrom, $upTo, $upDay, $upInterval ) = $upSched =~ m/(\d+)-(\d+)\s(\d{1,})\s?(\d{1,})?/;
                if (!$upInterval){
                    $upInterval = $upDay;
                    $upDay='';
                }
                Log3 $hash, 5, "TRAFFIC: ($name) parsed schedule to upFrom $upFrom, upTo $upTo, upDay $upDay, upInterval $upInterval";
Log3 $hash, 2, "TRAFFIC: ($name) DEBUG  parsed schedule to upFrom $upFrom, upTo $upTo, upDay $upDay, upInterval $upInterval";

                if(!$upFrom || !$upTo || !$upInterval){
                    Log3 $hash, 1, "TRAFIC: ($name) updateSchedule $upSched not defined correctly";
                }else{
                    if($hour >= $upFrom && $hour < $upTo){ #if we are INSIDE the updateSchedule
                        if(!$upDay || $upDay == $wday ){
                            $nextTrigger = gettimeofday() + $upInterval;
                            Log3 $hash, 4, "TRAFFIC: ($name) schedule $upSched matches ($upFrom to $upTo (on day $upDay) every $upInterval seconds), matches NOW (current hour $hour day $wday), nextTrigger set to $nextTrigger";
Log3 $hash, 2, "TRAFFIC: ($name) DEBUG schedule $upSched matches ($upFrom to $upTo (on day $upDay) every $upInterval seconds), matches NOW (current hour $hour day $wday), nextTrigger set to $nextTrigger";
                            $hash->{UPDATESCHEDULE} = $upSched;
                            last; # we have our next match, end the search
                        }else{
                            Log3 $hash, 4, "TRAFFIC: ($name) $upSched does match the time but not the day ($wday)";
Log3 $hash, 2, "TRAFFIC: ($name) DEBUG $upSched does match the time but not the day ($wday)";
                        }
                    }elsif($hour < $upFrom && ( $wday == $upDay || !$upDay) ){ #get the next upcoming updateSchedule for today
                        my $upcomingTrigger = timelocal(0,0,$upFrom,$mday,$mon,$year);
Log3 $hash, 2, "TRAFFIC: ($name) DEBUG $upcomingTrigger <= $nextTrigger";                        
                        if($upcomingTrigger <= $nextTrigger){
                            $nextTrigger = $upcomingTrigger;
Log3 $hash, 2, "TRAFFIC: ($name) DEBUG $upSched is the next upcoming updateSchedule, nextTrigger is generated to $nextTrigger";                        
                        }
                    }else{
                        Log3 $hash, 5, "TRAFFIC: ($name) schedule $upSched does not match hour ($hour)";
                    }
                }
            }
        }
        
        if(defined($hash->{BURSTCOUNT}) && $hash->{BURSTCOUNT} > 0){
            $nextTrigger = gettimeofday() + $hash->{BURSTINTERVAL};
            Log3 $hash, 3, "TRAFFIC: ($name) next update defined by burst";
            $hash->{BURSTCOUNT}--;
        }elsif(defined($hash->{BURSTCOUNT}) && $hash->{BURSTCOUNT} == 0){
            delete($hash->{BURSTCOUNT});
            delete($hash->{BURSTINTERVAL});
            Log3 $hash, 4, "TRAFFIC: ($name) burst update is done";
        }
        
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "TRAFFIC_StartUpdate", $hash, 0);            
        Log3 $hash, 4, "TRAFFIC: ($name) internal interval timer set to call StartUpdate again at " . $hash->{TRIGGERTIME_FMT};
    }

    
    
    if(defined(AttrVal($name, "start_address", undef )) && defined(AttrVal($name, "end_address", undef ))){
        
        BlockingCall("TRAFFIC_DoUpdate",$hash->{NAME}.';;;normal',"TRAFFIC_FinishUpdate",60,"TRAFFIC_AbortUpdate",$hash);    

        if(defined(AttrVal($name, "includeReturn", undef )) && AttrVal($name, "includeReturn", undef ) eq 1){
            BlockingCall("TRAFFIC_DoUpdate",$hash->{NAME}.';;;return',"TRAFFIC_FinishUpdate",60,"TRAFFIC_AbortUpdate",$hash);    
        }
        
    }else{
        readingsSingleUpdate( $hash, "state", "incomplete configuration", 1 );
        Log3 $hash, 1, "TRAFFIC: ($name) is not configured correctly, please add start_address and end_address";
    }
}

sub TRAFFIC_AbortUpdate($){
    # doto
}


sub TRAFFIC_DoUpdate(){

    my ($string) = @_;
    my ($hName, $direction) = split(";;;", $string); # direction is normal or return
    my $hash = $defs{$hName};

    my $dotrigger = 1; 
    my $name = $hash->{NAME};
    my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);

    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC DoUpdate start";

    if ( $hash->{INTERVAL}) {
        RemoveInternalTimer ($hash);
        my $nextTrigger = gettimeofday() + $hash->{INTERVAL};
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "TRAFFIC_StartUpdate", $hash, 0);
        Log3 $hash, 4, "TRAFFIC: ($name) internal interval timer set to call GetUpdate again in " . int($hash->{INTERVAL}). " seconds";
    }
    
    my $returnJSON;
    
    my $TRlanguage = '';
    if(defined(AttrVal($name,"language",undef))){
        $TRlanguage = '&language='.AttrVal($name,"language","");
    }else{
        Log3 $hash, 5, "TRAFFIC: ($name) no language specified";
    }

    my $TRwaypoints = ''; 
    if(defined(AttrVal($name,"waypoints",undef))){
        $TRwaypoints = '&waypoints=via:' . join('|via:', split('\|', AttrVal($name,"waypoints",undef)));
    }else{
        Log3 $hash, 4, "TRAFFIC: ($name) no waypoints specified";
    }
    if($direction eq "return"){
        if(defined(AttrVal($name,"returnWaypoints",undef))){
            $TRwaypoints = '&waypoints=via:' . join('|via:', split('\|', AttrVal($name,"returnWaypoints",undef)));
            Log3 $hash, 4, "TRAFFIC: ($name) using returnWaypoints";
        }elsif(defined(AttrVal($name,"waypoints",undef))){
            $TRwaypoints = '&waypoints=via:' . join('|via:', reverse split('\|', AttrVal($name,"waypoints",undef)));    
            Log3 $hash, 4, "TRAFFIC: ($name) reversing waypoints";
        }else{
            Log3 $hash, 4, "TRAFFIC: ($name) no waypoints for return specified";
        }
    }
    
    my $origin       = AttrVal($name, "start_address", 0 );
    my $destination  = AttrVal($name, "end_address", 0 );
    my $travelMode   = AttrVal($name, "travelMode", 'driving' );
    my $alternatives = 'false';
       $alternatives = 'true' if (AttrVal($name, "alternatives", undef ));
    
    if($direction eq "return"){
        $origin         = AttrVal($name, "end_address", 0 );
        $destination    = AttrVal($name, "start_address", 0 );
        $alternatives   = 'false';
    }
    
    my $url = 'https://maps.googleapis.com/maps/api/directions/json?origin='.$origin.'&destination='.$destination.'&mode='.$travelMode.$TRlanguage.'&departure_time=now'.$TRwaypoints.'&key='.$hash->{APIKEY}.'&alternatives='.$alternatives;
    Log3 $hash, 4, "TRAFFIC: ($name) using $url";
    
    my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );
    $ua->default_header("HTTP_REFERER" => "www.google.de");
    my $body = $ua->get($url);
    
    
    # test json decode and catch error nicely

    eval {
        my $testJson = decode_json($body->decoded_content); 
        1;
    };
    if($@) {
        my $e = $@;
        Log3 $hash, 1, "TRAFFIC: ($name) decode_json on googles return failed, cant continue";
        Log3 $hash, 5, "TRAFFIC: ($name) received: ".Dumper($body->decoded_content);
        my %errorReturn = ('status' => 'API error','action' => 'retry');                        
        return "$name;;;$direction;;;".encode_json(\%errorReturn);
    };
    my $json = JSON->new->utf8(0)->decode($body->decoded_content); #utf8 decoding to support special characters in return & readings
    
    
    my $duration_sec            = $json->{'routes'}[0]->{'legs'}[0]->{'duration'}->{'value'} ;
    my $duration_in_traffic_sec = $json->{'routes'}[0]->{'legs'}[0]->{'duration_in_traffic'}->{'value'};

    $returnJSON->{'READINGS'}->{'duration'}               = $json->{'routes'}[0]->{'legs'}[0]->{'duration'}->{'text'}             if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'READINGS'}->{'duration_in_traffic'}    = $json->{'routes'}[0]->{'legs'}[0]->{'duration_in_traffic'}->{'text'}  if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'READINGS'}->{'distance'}               = $json->{'routes'}[0]->{'legs'}[0]->{'distance'}->{'text'}             if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'READINGS'}->{'state'}                  = $json->{'status'};
    $returnJSON->{'READINGS'}->{'status'}                 = $json->{'status'};
    $returnJSON->{'READINGS'}->{'eta'}                    = FmtTime( gettimeofday() + $duration_in_traffic_sec ) if defined($duration_in_traffic_sec); 
    $returnJSON->{'READINGS'}->{'summary'}                = $json->{'routes'}[0]->{'summary'};
    
    # handling alternatives
    $returnJSON->{'READINGS'}->{'alternatives'} =  join( ", ", map {  $_->{summary}.' - '.$_->{'legs'}[0]->{'duration_in_traffic'}->{'text'}   } @{$json->{'routes'}} );
    
    $returnJSON->{'HELPER'}->{'Poly'}                     = encode_base64 (join(',', map{ $_->{overview_polyline}->{points} } @{$json->{'routes'}} ));
    $returnJSON->{'HELPER'}->{'GoogleMapsCenter'}         = $json->{'routes'}[0]->{'legs'}[0]->{start_location}->{lat}.','.$json->{'routes'}[0]->{'legs'}[0]->{start_location}->{lng};

    if($duration_in_traffic_sec && $duration_sec){
        $returnJSON->{'READINGS'}->{'delay'}              = prettySeconds($duration_in_traffic_sec - $duration_sec)  if AttrVal($name, "outputReadings", "" ) =~ m/text/;
        Log3 $hash, 4, "TRAFFIC: ($name) delay in seconds = $duration_in_traffic_sec - $duration_sec";
        
        if (AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_in_traffic_sec) && defined($duration_sec)){
            $returnJSON->{'READINGS'}->{'delay_min'} = int($duration_in_traffic_sec - $duration_sec);
        }
        if(defined($returnJSON->{'READINGS'}->{'delay_min'})){
            if( ( $returnJSON->{'READINGS'}->{'delay_min'} && $returnJSON->{'READINGS'}->{'delay_min'} =~ m/^-/ ) || $returnJSON->{'READINGS'}->{'delay_min'} < 60){
                Log3 $hash, 5, "TRAFFIC: ($name) delay_min was negative or less than 1min (".$returnJSON->{'READINGS'}->{'delay_min'}."), set to 0";
                $returnJSON->{'READINGS'}->{'delay_min'} = 0;
            }else{
                $returnJSON->{'READINGS'}->{'delay_min'} = int($returnJSON->{'READINGS'}->{'delay_min'} / 60 + 0.5); #divide 60 and round
            }
        }
    }else{
        Log3 $hash, 1, "TRAFFIC: ($name) did not receive duration_in_traffic, not able to calculate delay";
        
    }
    
    # condition based values
    $returnJSON->{'READINGS'}->{'error_message'} = $json->{'error_message'} if $json->{'error_message'};
    # output readings
    $returnJSON->{'READINGS'}->{'duration_min'}               = int($duration_sec / 60  + 0.5)            if AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_sec);
    $returnJSON->{'READINGS'}->{'duration_in_traffic_min'}    = int($duration_in_traffic_sec / 60  + 0.5) if AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_in_traffic_sec);
    $returnJSON->{'READINGS'}->{'duration_sec'}               = $duration_sec                             if AttrVal($name, "outputReadings", "" ) =~ m/sec/; 
    $returnJSON->{'READINGS'}->{'duration_in_traffic_sec'}    = $duration_in_traffic_sec                  if AttrVal($name, "outputReadings", "" ) =~ m/sec/; 
    # raw data (seconds)
    $returnJSON->{'READINGS'}->{'distance'} = $json->{'routes'}[0]->{'legs'}[0]->{'distance'}->{'value'}  if AttrVal($name, "raw_data", 0);
    

    # average readings
    if(AttrVal($name, "outputReadings", "" ) =~ m/average/){
        
        # calc average
        $returnJSON->{'READINGS'}->{'average_duration_min'}               = int($hash->{READINGS}{'average_duration_min'}{VAL} + $returnJSON->{'READINGS'}->{'duration_min'}) / 2                        if $returnJSON->{'READINGS'}->{'duration_min'};
        $returnJSON->{'READINGS'}->{'average_duration_in_traffic_min'}    = int($hash->{READINGS}{'average_duration_in_traffic_min'}{VAL} + $returnJSON->{'READINGS'}->{'duration_in_traffic_min'}) / 2  if $returnJSON->{'READINGS'}->{'duration_in_traffic_min'};
        $returnJSON->{'READINGS'}->{'average_delay_min'}                  = int($hash->{READINGS}{'average_delay_min'}{VAL} + $returnJSON->{'READINGS'}->{'delay_min'}) / 2                              if $returnJSON->{'READINGS'}->{'delay_min'};
        
        # override if this is the first average
        $returnJSON->{'READINGS'}->{'average_duration_min'}               = $returnJSON->{'READINGS'}->{'duration_min'}             if !$hash->{READINGS}{'average_duration_min'}{VAL};
        $returnJSON->{'READINGS'}->{'average_duration_in_traffic_min'}    = $returnJSON->{'READINGS'}->{'duration_in_traffic_min'}  if !$hash->{READINGS}{'average_duration_in_traffic_min'}{VAL};
        $returnJSON->{'READINGS'}->{'average_delay_min'}                  = $returnJSON->{'READINGS'}->{'delay_min'}                if !$hash->{READINGS}{'average_delay_min'}{VAL};
    }
    
    
    Log3 $hash, 5, "TRAFFIC: ($name) returning from TRAFFIC DoUpdate: ".encode_json($returnJSON);
    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC DoUpdate done";
    return "$name;;;$direction;;;".encode_json($returnJSON);
}

sub TRAFFIC_FinishUpdate($){
    my ($name,$direction,$rawJson) = split(/;;;/,shift);
    my $hash = $defs{$name};
    my %sensors;
    my $dotrigger = 1;


    my $json = decode_json($rawJson);
    
    # before we update anything, check if the status contains error, if yes -> retry
    if(defined($json->{'status'}) && $json->{'status'} =~ m/error/i){   # this handles potential JSON decode issues and retries
        if ($json->{'action'} eq 'retry'){
            Log3 $hash, 1, "TRAFFIC: ($name) TRAFFIC doUpdate returned an error \"".$json->{'status'}. "\" will schedule a retry in 5 seconds";
            RemoveInternalTimer ($hash);
            my $nextTrigger = gettimeofday() + 5;
            $hash->{TRIGGERTIME}     = $nextTrigger;
            $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
            InternalTimer($nextTrigger, "TRAFFIC_StartUpdate", $hash, 0);
        }else{
            Log3 $hash, 1, "TRAFFIC: ($name) TRAFFIC doUpdate returned an error: ".$json->{'status'};
        }
        
    }else{ #JSON decode did not return an error, lets update the device
    
    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC_FinishUpdate start";
    readingsBeginUpdate($hash);
    
    my $readings = $json->{'READINGS'};
    my $helper = $json->{'HELPER'};

    foreach my $helperName (keys %{$helper}){
        if($direction eq 'return'){
            Log3 $hash, 4, "TRAFFIC: ($name) HelperUpdate: return_".$helperName." - ".$helper->{$helperName};
            $hash->{helper}{'return_'.$helperName} = $helper->{$helperName}; #testme        
        }else{
            Log3 $hash, 4, "TRAFFIC: ($name) HelperUpdate: $helperName - ".$helper->{$helperName};
            $hash->{helper}{$helperName} = $helper->{$helperName}; #testme        
        }
    }
    
    foreach my $readingName (keys %{$readings}){
        Log3 $hash, 4, "TRAFFIC: ($name) ReadingsUpdate: $readingName - ".$readings->{$readingName};
        if($direction eq 'return'){
            readingsBulkUpdate($hash,'return_'.$readingName,$readings->{$readingName});
        }else{
            readingsBulkUpdate($hash,$readingName,$readings->{$readingName});
        }
    }

    if(my $stateReading = AttrVal($name,"stateReading",undef)){
        Log3 $hash, 5, "TRAFFIC: ($name) stateReading defined, override state";
        if(defined($json->{'READINGS'}->{$stateReading})){
            readingsBulkUpdate($hash,'state',$json->{'READINGS'}->{$stateReading});
        }else{
            
            Log3 $hash, 1, "TRAFFIC: ($name) stateReading $stateReading not found";
        }
    }
    # if Google returned an error, we gonna try again in 3 seconds
    if(defined($json->{'READINGS'}->{'status'}) && $json->{'READINGS'}->{'status'} =~ m/error/i){ # UNKNOWN_ERROR indicates a directions request could not be processed due to a server error. The request may succeed if you try again.
        Log3 $hash, 1, "TRAFFIC: ($name) auto-retry as Google returned an error: ".$json->{'READINGS'}->{'status'};
        InternalTimer(gettimeofday() + 3, "TRAFFIC_StartUpdate", $hash, 0); 
    }elsif(defined($hash->{READINGS}->{'error_message'})){
        Log3 $hash, 3, "TRAFFIC: ($name) removing reading error_message, status: ".$json->{'READINGS'}->{'status'};
        fhem("deletereading $name error_message");
    }

    readingsEndUpdate($hash, $dotrigger);
    Log3 $hash, 4, "TRAFFIC: ($name) TRAFFIC_FinishUpdate done";
    Log3 $hash, 5, "TRAFFIC: ($name) Helper: ".Dumper($hash->{helper}); 
    }# not an error
}

sub TRAFFIC_weblink{
    my $name = shift();
    return "<a href='$FW_ME/TRAFFIC?name=$name'>$FW_ME/TRAFFIC?name=$name</a><br>";
}

sub TRAFFIC(){
    my $name    = $FW_webArgs{name};
    return if(!defined($name));

    $FW_RETTYPE = "text/html; charset=UTF-8";
    $FW_RET="";

    my $web .= TRAFFIC_GetMap($name);

    FW_pO $web;
    return ($FW_RETTYPE, $FW_RET);
}

sub TRAFFIC_DbLog_split($) {
    my ($event, $device) = @_;
    my $hash = $defs{$device};
    Log3 $hash, 5, "TRAFFIC: ($device) TRAFFIC_DbLog_split received event $event on device $device";
    
    my $readings;   # this holds all possible readings and their units
        $readings->{'update'} = 'text';
        $readings->{'duration'} = 'text';
        $readings->{'duration_in_traffic'} = 'text';
        $readings->{'distance'} = 'text';
        $readings->{'state'} = 'text';
        $readings->{'status'} = 'text';
        $readings->{'eta'} = 'time';
        $readings->{'summary'} = 'text';
        $readings->{'alternatives'} = 'text';
        $readings->{'delay'} = 'text';
        $readings->{'delay_min'} = 'min';
        $readings->{'error_message'} = 'text';
        $readings->{'duration_min'} = 'min';
        $readings->{'duration_in_traffic_min'} = 'min';
        $readings->{'duration_sec'} = 'sec';
        $readings->{'duration_in_traffic_sec'} = 'sec';
        $readings->{'distance'} = 'km';
        $readings->{'average_duration_min'} = 'min';
        $readings->{'average_duration_in_traffic_min'} = 'min';
        $readings->{'average_delay_min'} = 'min';
        $readings->{'average_duration_min'} = 'min';
        $readings->{'average_duration_in_traffic_min'} = 'min';
        $readings->{'average_delay_min'} = 'min';

    my ($reading, $value, $unit) = "";

    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    my $alternativeReading = $reading;
    $alternativeReading =~ s/^return_//; 
    $value = join(" ",@parts);
    
    if($readings->{$reading}){
        $unit = $readings->{$reading};
        $value =~ s/$unit$//; #try to remove the unit from the value
    }elsif($readings->{$alternativeReading}){
        $unit = $readings->{$alternativeReading};
        $value =~ s/$unit$//; #try to remove the unit from the value
    }else{
        Log3 $hash, 5, "TRAFFIC: ($device) TRAFFIC_DbLog_split auto detect unit for reading $reading value $value";
        $unit = 'min' if ($reading) =~ m/_min$/;
        $unit = 'sec' if ($reading) =~ m/_sec$/;
        $unit = 'km' if ($reading) =~ m/_km$/;
    }
    
    Log3 $hash, 5, "TRAFFIC: ($device) TRAFFIC_DbLog_split returning $reading, $value, $unit";
    return ($reading, $value, $unit);
}

sub prettySeconds {
    my $time = shift;
    
    if($time =~ m/^-/){
        return "0 min";
    }
    my $days = int($time / 86400);
    $time -= ($days * 86400);
    my $hours = int($time / 3600);
    $time -= ($hours * 3600);
    my $minutes = int($time / 60);
    my $seconds = $time % 60;

    $days = $days < 1 ? '' : $days .' days ';
    $hours = $hours < 1 ? '' : $hours .' hours ';
    $minutes = $minutes < 1 ? '' : $minutes . ' min ';
    $time = $days . $hours . $minutes;
    if(!$time){
        return "0 min";
    }else{
        return $time;
    }
}

sub minHex{ $_[0]<$_[1] ? $_[0] : $_[1] }

sub degradeHex{
    my ($rgb, $degr) = (hex(shift), pop);
    $rgb -= minHex( $rgb&(0xff<<$_), $degr<<$_ ) for (0,8,16);
    return '%06x', $rgb;
}

sub lightHex {
    $_[0] =~ s/#//g;
  return sprintf '%02x'x3,
      map{ ($_ *= 1+$_[1]) > 0xff ? 0xff : $_  }
      map hex, unpack 'A2'x3, $_[0];
}

1;

#======================================================================
#======================================================================
#
# HTML Documentation for help and commandref
#
#======================================================================
#======================================================================
=pod
=item device
=item summary    provide traffic details with Google Distance API
=item summary_DE stellt Verkehrsdaten mittels Google Distance API bereit
=begin html

<a name="TRAFFIC"></a>
<h3>TRAFFIC</h3>
<ul>
  <u><b>TRAFFIC - google maps directions module</b></u>
  <br>
  <br>
  This FHEM module collects and displays data obtained via the google maps directions api<br>
  requirements:<br>
  perl JSON module<br>
  perl LWP::SIMPLE module<br>
  perl MIME::Base64 module<br>
  Google maps API key<br>
  <br>
    <b>Features:</b>
  <br>
  <ul>
    <li>get distance between start and end location</li>
    <li>get travel time for route</li>
    <li>get travel time in traffic for route</li>
    <li>define additional waypoints</li>
    <li>calculate delay between travel-time and travel-time-in-traffic</li>
    <li>choose default language</li>
    <li>disable the device</li>
    <li>5 log levels</li>
    <li>get outputs in seconds / meter (raw_data)</li>
    <li>state of google maps returned in error reading (i.e. The provided API key is invalid)</li>
    <li>customize update interval (default 3600 seconds)</li>
    <li>calculate ETA with localtime and delay</li>
    <li>configure the output readings with attribute outputReadings, text, min sec</li>
    <li>configure the state-reading </li>
    <li>optionally display the same route in return</li>
    <li>one-time-burst, specify the amount and interval between updates</li>
    <li>different Travel Modes (driving, walking, bicycling and transit)</li>
    <li>flexible update schedule</li>
    <li>integrated Map to visualize configured route or embed to external GUI</li>
  </ul>
  <br>
  <br>
  <a name="TRAFFICdefine"></a>
  <b>Define:</b>
  <ul><br>
    <code>define &lt;name&gt; TRAFFIC &lt;YOUR-API-KEY&gt; [UPDATE-INTERVAL]</code>
    <br><br>
    example:<br>
       <code>define muc2berlin TRAFFIC ABCDEFGHIJKLMNOPQRSTVWYZ 600</code><br>
  </ul>
  <br>
  <br>
  <b>Attributes:</b>
  <ul>
    <li>"start_address" - Street, zipcode City  <b>(mandatory)</b></li>
    <li>"end_address" -  Street, zipcode City <b>(mandatory)</b></li>
    <li>"raw_data" -  0:1</li>
    <li>"alternatives" -  0:1, include alternative routes into readings and Map</li>
    <li>"language" - de, en etc.</li>
    <li>"waypoints" - Lat, Long coordinates, separated by | </li>
    <li>"returnWaypoints" - Lat, Long coordinates, separated by | </li>
    <li>"disable" - 0:1</li>
    <li>"stateReading" - name the reading which will be used in device state</li>
    <li>"outputReadings" - define what kind of readings you want to get: text, min, sec, average</li>
    <li>"updateSchedule" - define a flexible update schedule, syntax &lt;starthour&gt;-&lt;endhour&gt; [&lt;day&gt;] &lt;seconds&gt; , multiple entries by sparated by |<br> <i>example:</i> 7-9 1 120 - Monday between 7 and 9 every 2minutes <br> <i>example:</i> 17-19 120 - every Day between 17 and 19 every 2minutes <br> <i>example:</i> 6-8 1 60|6-8 2 60|6-8 3 60|6-8 4 60|6-8 5 60 - Monday till Friday, 60 seconds between 6 and 8 am</li>
    <li>"travelMode" - default: driving, options walking, bicycling or transit </li>
    <li>"GoogleMapsStyle" - choose your colors from: default,silver,dark,night</li>
    <li>"GoogleMapsSize" - Map size in pixel, &lt;width&gt;,&lt;height&gt;</li>
    <li>"GoogleMapsCenter" - Lat, Long coordinates of your map center, spearated by ,</li>
    <li>"GoogleMapsZoom" - sets your map zoom level</li>
    <li>"GoogleMapsStroke" - customize your map poly-strokes in color, weight and opacity <br> &lt;hex-color-code&gt;,[stroke-weight],[stroke-opacity],&lt;hex-color-code-of-return&gt;,[stroke-weight-of-return],[stroke-opacity-of-return]<br>must beginn with #color of each stroke, weight and opacity is optional<br><i>example:</i> #019cdf,#ffeb19<br><i>example:</i> #019cdf,20,#ffeb19<br><i>example:</i> #019cdf,20,#ffeb19,15<br><i>example:</i> #019cdf,#ffeb19,15<br><i>example:</i> #019cdf,20,80,#ffeb19<br><i>example:</i> #019cdf,#ffeb19,15,50<br><i>example:</i> #019cdf,20,80<br><i>default:</i> #4cde44,6,100,#FF0000,1,100</li>
    <li>"GoogleMapsTrafficLayer" - enable the basic Google Maps Traffic Layer</li>
    <li>"GoogleMapsDisableUI" - hide the map controls</li>
  </ul>
  <br>
  <br>
  
  <a name="TRAFFICreadings"></a>
  <b>Readings:</b>
  <ul>
    <li>alternatives</li>
    <li>delay</li>
    <li>delay_min</li>
    <li>distance</li>
    <li>duration</li>
    <li>duration_in_traffic</li>
    <li>duration_in_traffic_min</li>
    <li>duration_min</li>
    <li>error_message</li>
    <li>eta</li>
    <li>state</li>
    <li>summary</li>
  </ul>
  <br><br>
  <a name="TRAFFICset"></a>
  <b>Set</b>
  <ul>
    <li>update [burst-update-count] [burst-update-interval] - update readings manually</li>
  </ul>
  <br><br>
</ul>


=end html
=cut


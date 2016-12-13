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


package main;

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    
use Data::Dumper;
use LWP::Simple qw($ua get);
use JSON;
use POSIX;
use Blocking;

sub TRAFFIC_Initialize($);
sub TRAFFIC_Define($$);
sub TRAFFIC_Undef($$);
sub TRAFFIC_Set($@);
sub TRAFFIC_Attr(@);
sub TRAFFIC_GetUpdate($);

my %TRcmds = (
    'update' => 'noArg',
);
my $TRVersion = '1.1';

sub TRAFFIC_Initialize($){

    my ($hash) = @_;

    $hash->{DefFn}      = "TRAFFIC_Define";
    $hash->{UndefFn}    = "TRAFFIC_Undef";
    $hash->{SetFn}      = "TRAFFIC_Set";
    $hash->{AttrFn}     = "TRAFFIC_Attr";
    $hash->{AttrList}   = 
      "disable:0,1 start_address end_address raw_data:0,1 language waypoints stateReading outputReadings travelMode:driving,walking,bicycling,transit includeReturn:0,1 updateSchedule " .
      $readingFnAttributes;  
      
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
    
    # basic update INTERVAL
    if(scalar(@apiDefs) > 3 && $apiDefs[3] =~ m/^\d+$/){
        $hash->{INTERVAL} = $apiDefs[3];
    }else{
        $hash->{INTERVAL} = 3600;
    }
    Log3 $hash, 3, "TRAFFIC: ($name) defined ".$hash->{NAME}.' with interval set to '.$hash->{INTERVAL};
    
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
        Log3 $hash, 3, "TRAFFIC: ($name)  attrName $attrName set to attrValue $attrValue";
    }
    if($attrName eq "disable" && $attrValue eq "1"){
        readingsSingleUpdate( $hash, "state", "disabled", 1 );
    }
    if($attrName eq "outputReadings" || $attrName eq "includeReturn"){
        #clear all readings
        foreach my $clearReading ( keys %{$hash->{READINGS}}){
            Log3 $hash, 5, "TRAFFIC: ($name) READING: $clearReading deleted";
            delete($hash->{READINGS}{$clearReading}); 
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

                if(!$upFrom || !$upTo || !$upInterval){
                    Log3 $hash, 1, "TRAFIC: ($name) updateSchedule $upSched not defined correctly";
                }else{
                    if($hour >= $upFrom && $hour < $upTo){
                        if(!$upDay || $upDay == $wday ){
                            $nextTrigger = gettimeofday() + $upInterval;
                            Log3 $hash, 3, "TRAFFIC: ($name) schedule from $upFrom to $upTo (on day $upDay) every $upInterval seconds, matches (current hour $hour), nextTrigger set to $nextTrigger";
                            $hash->{UPDATESCHEDULE} = $upSched;
                            last;
                        }else{
                            Log3 $hash, 3, "TRAFFIC: ($name) $upSched does match the time but not the day ($wday)";
                        }
                    }else{
                        Log3 $hash, 5, "TRAFFIC: ($name) schedule $upSched does not match ($hour)";
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
            Log3 $hash, 3, "TRAFFIC: ($name) burst update is done";
        }
        
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "TRAFFIC_StartUpdate", $hash, 0);            
        Log3 $hash, 3, "TRAFFIC: ($name) internal interval timer set to call StartUpdate again at " . $hash->{TRIGGERTIME_FMT};
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

}


sub TRAFFIC_DoUpdate(){

    my ($string) = @_;
    my ($hName, $direction) = split(";;;", $string); # direction is normal or return
    my $hash = $defs{$hName};

    my $dotrigger = 1; 
    my $name = $hash->{NAME};
    my ($sec,$min,$hour,$dayn,$month,$year,$wday,$yday,$isdst) = localtime(time);

    Log3 $hash, 3, "TRAFFIC: ($name) TRAFFIC_DoUpdate start";

    if ( $hash->{INTERVAL}) {
        RemoveInternalTimer ($hash);
        my $nextTrigger = gettimeofday() + $hash->{INTERVAL};
        $hash->{TRIGGERTIME}     = $nextTrigger;
        $hash->{TRIGGERTIME_FMT} = FmtDateTime($nextTrigger);
        InternalTimer($nextTrigger, "TRAFFIC_DoUpdate", $hash, 0);            
        Log3 $hash, 3, "TRAFFIC: ($name) internal interval timer set to call GetUpdate again in " . int($hash->{INTERVAL}). " seconds";
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
        
        if($direction eq "return"){
            $TRwaypoints = '&waypoints=via:' . join('|via:', reverse split('\|', AttrVal($name,"waypoints",undef)));
            Log3 $hash, 5, "TRAFFIC: ($name) reversing waypoints";
        }
    }else{
        Log3 $hash, 5, "TRAFFIC: ($name) no waypoints specified";
    }
    
    my $origin = AttrVal($name, "start_address", 0 );
    my $destination = AttrVal($name, "end_address", 0 );
    my $travelMode = AttrVal($name, "travelMode", 'driving' );
    
    if($direction eq "return"){
        $origin = AttrVal($name, "end_address", 0 );
        $destination = AttrVal($name, "start_address", 0 );
    }
    
    my $url = 'https://maps.googleapis.com/maps/api/directions/json?origin='.$origin.'&destination='.$destination.'&mode='.$travelMode.$TRlanguage.'&departure_time=now'.$TRwaypoints.'&key='.$hash->{APIKEY};
    Log3 $hash, 2, "TRAFFIC: ($name) using $url";
    
    my $ua = LWP::UserAgent->new( ssl_opts => { verify_hostname => 0 } );
    $ua->default_header("HTTP_REFERER" => "www.google.de");
    my $body = $ua->get($url);
    my $json = decode_json($body->decoded_content);
    
    my $duration_sec            = $json->{'routes'}[0]->{'legs'}[0]->{'duration'}->{'value'} ;
    my $duration_in_traffic_sec = $json->{'routes'}[0]->{'legs'}[0]->{'duration_in_traffic'}->{'value'};

    $returnJSON->{'duration'}               = $json->{'routes'}[0]->{'legs'}[0]->{'duration'}->{'text'}             if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'duration_in_traffic'}    = $json->{'routes'}[0]->{'legs'}[0]->{'duration_in_traffic'}->{'text'}  if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'distance'}               = $json->{'routes'}[0]->{'legs'}[0]->{'distance'}->{'text'}             if AttrVal($name, "outputReadings", "" ) =~ m/text/;
    $returnJSON->{'state'}                  = $json->{'status'};
    $returnJSON->{'status'}                 = $json->{'status'};
    $returnJSON->{'eta'}                    = FmtTime( gettimeofday() + $duration_in_traffic_sec ) if defined($duration_in_traffic_sec); 
    
    if($duration_in_traffic_sec && $duration_sec){
        $returnJSON->{'delay'}              = prettySeconds($duration_in_traffic_sec - $duration_sec)  if AttrVal($name, "outputReadings", "" ) =~ m/text/;
        Log3 $hash, 3, "TRAFFIC: ($name) delay in seconds = $duration_in_traffic_sec - $duration_sec";
        
        if (AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_in_traffic_sec) && defined($duration_sec)){
            $returnJSON->{'delay_min'} = int($duration_in_traffic_sec - $duration_sec);
        }
        if(defined($returnJSON->{'delay_min'})){
            if( ( $returnJSON->{'delay_min'} && $returnJSON->{'delay_min'} =~ m/^-/ ) || $returnJSON->{'delay_min'} < 60){
                Log3 $hash, 5, "TRAFFIC: ($name) delay_min was negative or less than 1min (".$returnJSON->{'delay_min'}."), set to 0";
                $returnJSON->{'delay_min'} = 0;
            }else{
                $returnJSON->{'delay_min'} = int($returnJSON->{'delay_min'} / 60 + 0.5); #divide 60 and round
            }
        }
    }else{
        Log3 $hash, 1, "TRAFFIC: ($name) did not receive duration_in_traffic, not able to calculate delay";
        
    }
    
    # condition based values
    $returnJSON->{'error_message'} = $json->{'error_message'} if $json->{'error_message'};
    # output readings
    $returnJSON->{'duration_min'}               = int($duration_sec / 60  + 0.5)            if AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_sec);
    $returnJSON->{'duration_in_traffic_min'}    = int($duration_in_traffic_sec / 60  + 0.5) if AttrVal($name, "outputReadings", "" ) =~ m/min/ && defined($duration_in_traffic_sec);
    $returnJSON->{'duration_sec'}               = $duration_sec                             if AttrVal($name, "outputReadings", "" ) =~ m/sec/; 
    $returnJSON->{'duration_in_traffic_sec'}    = $duration_in_traffic_sec                  if AttrVal($name, "outputReadings", "" ) =~ m/sec/; 
    # raw data (seconds)
    $returnJSON->{'distance'} = $json->{'routes'}[0]->{'legs'}[0]->{'distance'}->{'value'}  if AttrVal($name, "raw_data", 0);
    

    # average readings
    if(AttrVal($name, "outputReadings", "" ) =~ m/average/){
        
        # calc average
        $returnJSON->{'average_duration_min'}               = int($hash->{READINGS}{'average_duration_min'}{VAL} + $returnJSON->{'duration_min'}) / 2                        if $returnJSON->{'duration_min'};
        $returnJSON->{'average_duration_in_traffic_min'}    = int($hash->{READINGS}{'average_duration_in_traffic_min'}{VAL} + $returnJSON->{'duration_in_traffic_min'}) / 2  if $returnJSON->{'duration_in_traffic_min'};
        $returnJSON->{'average_delay_min'}                  = int($hash->{READINGS}{'average_delay_min'}{VAL} + $returnJSON->{'delay_min'}) / 2                              if $returnJSON->{'delay_min'};
        
        # override if this is the first average
        $returnJSON->{'average_duration_min'}               = $returnJSON->{'duration_min'}             if !$hash->{READINGS}{'average_duration_min'}{VAL};
        $returnJSON->{'average_duration_in_traffic_min'}    = $returnJSON->{'duration_in_traffic_min'}  if !$hash->{READINGS}{'average_duration_in_traffic_min'}{VAL};
        $returnJSON->{'average_delay_min'}                  = $returnJSON->{'delay_min'}                if !$hash->{READINGS}{'average_delay_min'}{VAL};
    }
    
    
    Log3 $hash, 5, "TRAFFIC: ($name) returning from TRAFFIC_DoUpdate: ".encode_json($returnJSON);
    Log3 $hash, 3, "TRAFFIC: ($name) TRAFFIC_DoUpdate done";
    return "$name;;;$direction;;;".encode_json($returnJSON);
}

sub TRAFFIC_FinishUpdate($){
    my ($name,$direction,$rawJson) = split(/;;;/,shift);
    my $hash = $defs{$name};
    my %sensors;
    my $dotrigger = 1;

    Log3 $hash, 3, "TRAFFIC: ($name) TRAFFIC_FinishUpdate start";

    my $json = decode_json($rawJson); 
    readingsBeginUpdate($hash);

    foreach my $readingName (keys %{$json}){
        Log3 $hash, 3, "TRAFFIC: ($name) ReadingsUpdate: $readingName - ".$json->{$readingName};
        if($direction eq 'return'){
            readingsBulkUpdate($hash,'return_'.$readingName,$json->{$readingName});
        }else{
            readingsBulkUpdate($hash,$readingName,$json->{$readingName});
        }
    }
    
    if($json->{'status'} eq 'UNKNOWN_ERROR'){ # UNKNOWN_ERROR indicates a directions request could not be processed due to a server error. The request may succeed if you try again.
        InternalTimer(gettimeofday() + 3, "TRAFFIC_StartUpdate", $hash, 0); 
    }

    if(my $stateReading = AttrVal($name,"stateReading",undef)){
        Log3 $hash, 5, "TRAFFIC: ($name) stateReading defined, override state";
        if(defined($json->{$stateReading})){
            readingsBulkUpdate($hash,'state',$json->{$stateReading});
        }else{
            
            Log3 $hash, 1, "TRAFFIC: ($name) stateReading $stateReading not found";
        }
    }

    readingsEndUpdate($hash, $dotrigger);
    Log3 $hash, 3, "TRAFFIC: ($name) TRAFFIC_FinishUpdate done";
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
    <li>"language" - de, en etc.</li>
    <li>"waypoints" - Lat, Long coordinates, separated by | </li>
    <li>"disable" - 0:1</li>
    <li>"stateReading" - name the reading which will be used in device state</li>
    <li>"outputReadings" - define what kind of readings you want to get: text, min, sec, average</li>
    <li>"updateSchedule" - define a flexible update schedule, syntax &lt;starthour&gt;-&lt;endhour&gt; [&lt;day&gt;] &lt;seconds&gt; , multiple entries by sparated by |<br> <i>example:</i> 7-9 1 120 - Monday between 7 and 9 every 2minutes <br> <i>example:</i> 17-19 120 - every Day between 17 and 19 every 2minutes <br> <i>example:</i> 6-8 1 60|6-8 2 60|6-8 3 60|6-8 4 60|6-8 5 60 - Monday till Friday, 60 seconds between 6 and 8 am</li>
    <li>"travelMode" - default: driving, options walking, bicycling or transit </li>
    <li>"includeReturn" - 0:1</li>
  </ul>
  <br>
  <br>
  
  <a name="TRAFFICreadings"></a>
  <b>Readings:</b>
  <ul>
     <li>delay </li>
     <li>distance </li>
     <li>duration </li>
     <li>duration_in_traffic </li>
     <li>state </li>
     <li>eta</li>
     <li>delay_min</li>
     <li>duration_min</li>
     <li>duration_in_traffic_min</li>
     <li>error_message</li>
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


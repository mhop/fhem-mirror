##############################################
# $Id$
# from myUtilsTemplate.pm 21509 2020-03-25 11:20:51Z rudolfkoenig
# utils for valetudo v2 API MQTT Implementation
# They are then available in every Perl expression.

# for zone cleaning after release 2022.05 a Reading .zones as json String is needed 
# {"Zone1": copy of string in the UI,"Zone2": copy of string in the UI }

package main;

use strict;
use warnings;

sub
valetudoUtils_Initialize {
    my $hash = shift;
    return;
}
# Enter you functions below _this_ line.

#######
# decode_json() croaks on error, this function should prevent fhem crashes
# https://metacpan.org/pod/Perl::Critic::Policy::ErrorHandling::RequireCheckingReturnValueOfEval
sub decode_j {
  use JSON qw(decode_json);
  my $maybe_json = shift;
  my $data;
  if ( eval { $data = decode_json($maybe_json); 1 } ) { return $data }
  Log3(undef, 1, "JSON decoding error, >$maybe_json< seems not to be valid JSON data: $@");
  return q{}
}

#######
# return a string for dynamic selection setList (widgets)
sub valetudo_w {
    my $NAME = shift;
    my $setter = shift;
    # this part reads segments, it's only filled if Provide map data is enabled in connectivity
    if ($setter eq 'segments') {
        my $json = ReadingsVal($NAME,'.segments','{}');
        if ($json eq '{}') {$json = '{"1":"no_Segment_or_not_supported"}'};
        my $decoded = decode_j($json);
        return join ',', sort values %{$decoded}
    }
    # this part read presets which contains a full json for preset zones or locations
    # depending on the valetudo release, there was a fundamental change in 2022.05
    if ($setter eq 'zones' or $setter eq 'locations') {
      if (ReadingsVal($NAME,'valetudo_release','') lt '2022.05.0') {
        # old code
        my $json = ReadingsVal($NAME,'.'.$setter.'Presets','{}');
        if ($json eq '{}') {$json = '{"1":"no_Segment_or_not_supported"}'};
        my $decoded = decode_j($json);
        my @array;
        for ( keys %{$decoded} ) { push @array, $decoded->{$_}->{'name'} }
        return join ',', sort @array
      } else {
        my $json = ReadingsVal($NAME,'.'.$setter,'{}');
        if ($json eq '{}') {$json = '{"1":"no_Segment_or_not_supported"}'};
        my $decoded = decode_j($json);
        return join ',', sort keys %{$decoded};
        #attr MQTT2_ClumsyQuirkyCattle userReadings zoneRename:.zones.* { join ' ',sort keys %{ decode_j(ReadingsVal($name,'.zones','')) } }
      }
    }
    # this part is for study purpose to read the full json segments with the REST API like
    # setreading alias=DreameL10pro json_segments {(qx(wget -qO - http://192.168.90.21/api/v2/robot/capabilities/MapSegmentationCapability))}
    if ($setter eq 'json_segments') {
        my $json = ReadingsVal($NAME,'json_segments','select');
        my $decoded = decode_j($json);
        my @array=@{$decoded};
        my %t;
        for (@array) { $t{$_->{'name'}} = $_->{'id'} }
        return join ',', sort keys %t 
    }
}
#######
# valetudo_c return a complete string for setList right part
sub valetudo_c {
    my $NAME = shift;
    my ($cmd,$load) = split q{ }, shift, 2;
    my $ret = 'error';
    my $devicetopic = AttrVal($NAME,'devicetopic',"valetudo/$NAME");

    # x_raw_payload like
    # /MapSegmentationCapability/clean/set {"segment_ids":["6"],"iterations":1,"customOrder":true}
    if ($cmd eq 'x_raw_payload') { $ret=$devicetopic.$load }

    # this part return an array of segment id's according to selected Names from segments (simple json)
    if ($cmd eq 'clean_segment') {
        my @rooms = split ',', $load;
        my $json = ReadingsVal($NAME,'.segments','{}');
        if ($json eq '{}') {$json = '{"1":"no_Segment_or_not_supported"}'};
        my $decoded = decode_j($json);
        my @ids;
        for ( @rooms ) { push @ids, {reverse %{$decoded} }->{$_} }
        my %Hcmd = ( clean_segment => {segment_ids => \@ids,iterations => 1,customOrder => 'true' } );
        $ret = $devicetopic.'/MapSegmentationCapability/clean/set '.toJSON $Hcmd{$cmd}
    }

    # this part return the zone/location id according to the selected Name from presets (zones/locations)
    # depending on the valetudo release, there was a fundamental change in 2022.05
    if ($cmd eq 'clean_zone') {
       if (ReadingsVal($NAME,'valetudo_release','') lt '2022.05.0') {
         # old code
          my $json = ReadingsVal($NAME,'.zonesPresets',q{});
          my $decoded = decode_j($json);
          for (keys %{$decoded}) { 
            if ( $decoded->{$_}->{'name'} eq $load ) {$ret = $devicetopic.'/ZoneCleaningCapability/start/set '.$_ } 
          }
       } else {
           my $json = ReadingsVal($NAME,'.zones',q{});
           my $decoded = decode_j($json);
           for (keys %{$decoded}) { 
               if ( $_ eq $load ) {$ret = $devicetopic.'/ZoneCleaningCapability/start/set '.toJSON $decoded->{$_} } 
           }
       }
    }

    if ($cmd eq 'goto') {
       if (ReadingsVal($NAME,'valetudo_release','') lt '2022.05.0') {
        my $json = ReadingsVal($NAME,'.locationsPresets',q{});
        my $decoded = decode_j($json);
        for (keys %{$decoded}) { 
            if ( $decoded->{$_}->{'name'} eq $load ) {$ret = $devicetopic.'/GoToLocationCapability/go/set '.$_ }
        }
    } else {
        my $json = ReadingsVal($NAME,'.locations',q{});
        my $decoded = decode_j($json);
           for (keys %{$decoded}) { 
               if ( $_ eq $load ) {$ret = $devicetopic.'/GoToLocationCapability/go/set '.toJSON $decoded->{$_} } 
           }
	   }
	}

    # this part is for study purpose to read the full json segments with the REST API
    # this part return an array of segment id's according to selected Names from json_segments (complex json)
    if ($cmd eq 'clean_segment_j') {
        $cmd = 'clean_segment';             # only during Test
        my @rooms = split ',', $load;
        my $json = ReadingsVal($NAME,'json_segments',q{});
        my $decoded = decode_j($json);
        my @array=@{$decoded};
        my %t;
        for (@array) { $t{$_->{'name'}} = $_->{'id'} }
        my @ids;
        for ( @rooms ) {push @ids, $t{$_}}
        my %Hcmd = ( clean_segment => {segment_ids => \@ids,iterations => 1,customOrder => 'true' } );
        $ret = $devicetopic.'/MapSegmentationCapability/clean/set '.toJSON $Hcmd{$cmd}
    }
    return $ret
}
#######
# handling .zones Reading
sub valetudo_z {
   my $NAME = shift;
   my ($cmd,$load) = split q{ }, shift, 2;
   my $ret = 'error';
   my $reading = $cmd =~ m,^zone, ? 'zone':'location';
   my $json = ReadingsVal($NAME,'.'.$reading.'s','');
   if ($cmd =~ m,New$,) {
     $load =~ s/[\n\r\s]//g;
     if ($json ne '') {
        my $decoded = decode_j($json);
        my $zone_name = 'Zjson'.((keys %{$decoded} )+ 1);
        my ($key, $val) = ($zone_name, decode_j $load);
        $decoded->{$key} = $val;
        $ret = toJSON ($decoded);
      } else {$ret = "{\"Zjson1\":$load}"}
    }
    if ($cmd =~ m,Rename$,) {
       my ($part1,$part2) = split q{ },$load;
       my @keys = keys %{ decode_j($json) };
       for (@keys) { if($_ eq $part1){ $json =~ s/$part1/$part2/ } }
       $ret = $json;
       #fhem("setreading $NAME $cmd ".join ' ',(sort keys %{ decode_j($ret) } ) );
    }
    fhem("setreading $NAME ".$reading."Rename ".join ' ',(reverse sort keys %{ decode_j($ret) } ) );
    fhem("setreading $NAME .".$reading."s ".$ret);
    return undef
}

####### 
# ask the robot via REST API for Featurelist and feature and return true false
sub valetudo_f {
    my $NAME = shift;   # Devicename of the robot
    my $substr = shift; # requested Feature like GoToLocation or MapSegmentation
    my $ip = ReadingsVal($NAME,'ip4',(split ',',ReadingsVal($NAME,'ips','error'))[0]);
    #my $ip = ( split '_', InternalVal($NAME,ReadingsVal($NAME,'IODev','').'_CONN','error') )[-2] ;
    my $string = GetHttpFile($ip, '/api/v2/robot/capabilities');
    index($string, $substr) == -1 ? 0:1;
}

#######
# used for readingList. return readingname -> value pairs
# look https://valetudo.cloud/pages/integrations/mqtt.html for details mqtt implementation
sub valetudo_r {
    my $NAME = shift;
    my $feature = shift;
    my $value = shift;
    my $EVENT = shift;
    #Log3(undef, 1, "Name $NAME, featur $feature, value $value, $EVENT");
     
    if ($feature =~ m,(^Att.*|^Basic.*|^Consum.*|^Loc.*),)
       {return {"$value"=>$EVENT} }
    if ($feature eq 'BatteryStateAttribute')
       {return $value eq 'level' ? {"batteryPercent"=>$EVENT}:
               $value eq 'status' ? {"batteryState"=>$EVENT}:{"$value"=>$EVENT} }
    if ($feature eq 'CurrentStatisticsCapability')
       {return $value eq 'area' ? {"area"=>sprintf("%.2f",($EVENT / 10000))." m²"}:{"$value"=>$EVENT} }
    if ($feature eq 'FanSpeedControlCapability')
       {return $value eq 'preset' ? {"fanSpeed"=>$EVENT}:{"$value"=>$EVENT} }
    if ($feature eq 'GoToLocationCapability' or $feature eq 'ZoneCleaningCapability' or $feature eq 'MapSegmentationCapability')
       {return {} }
    if ($feature eq 'MapData')
       {return $value eq 'map-data' ? {}:
               $value eq 'segments' ? {".segments"=>$EVENT}:{"$value"=>$EVENT} }
    if ($feature eq 'OperationModeControlCapability')
       {return $value eq 'preset' ? {"operationMode"=>$EVENT}:{"$value"=>$EVENT} }
    if ($feature eq 'StatusStateAttribute')
       {return $value eq 'status' ? {"state"=>$EVENT,"cleanerState"=>$EVENT}:
               $value eq 'detail' ? {"stateDetail"=>$EVENT}:
               $value eq 'error' ? {"stateError"=>$EVENT}:{"$value"=>$EVENT} }
    if ($feature eq 'WaterUsageControlCapability')
       {return $value eq 'preset' ? {"waterUsage"=>$EVENT}:{"$value"=>$EVENT} }
    if ($feature eq 'WifiConfigurationCapability')
       { 
       # two possibilities to return more than one reading
       # may be more than two for (split q{,}, $EVENT){}
       my $ret = {"ip4"=>(split q{,},$EVENT)[0],"ip6"=>(split q{,},$EVENT)[1]};
       return $value eq 'ips' ? $ret :{"$value"=>$EVENT} }
       #my %h;
       #$h{"ip4"}=(split q{,},$EVENT)[0];
       #$h{"ip6"}=(split q{,},$EVENT)[1];
       #return $value eq 'ips' ? \%h :{"$value"=>$EVENT} }
       #{return $value eq 'ips' ? {"ip4"=>(split q{,},$EVENT)[0]}:{"$value"=>$EVENT} }
}

#######
# get some Information with Rest Api
sub valetudo_g {
    my $NAME = shift;
    my ($cmd,$load) = split q{ }, shift, 2;
    #Log3(undef, 1, "Name $NAME, cmd $cmd, load $load");
    my $ip = (split q{ },$load)[1] || ReadingsVal($NAME,'ip4',(split q{_}, InternalVal($NAME,ReadingsVal($NAME,'IODev','').'_CONN','') )[-2] || return 'error no ip');
    if ($load eq 'segments'){
       my $url = '/api/v2/robot/capabilities/MapSegmentationCapability';
       my $json = GetHttpFile($ip, $url);
       my $decoded = decode_j($json);
       my @array=@{$decoded};
       my %t;
       for (@array) { $t{$_->{'id'}} = $_->{'name'} }; 
       my $ret = toJSON \%t; 
       fhem("setreading $NAME .segments $ret");
       return undef;
    }
    if ($load eq 'release'){
       my $url = '/api/v2/valetudo/version';
       my $json = GetHttpFile($ip, $url);
       my $ret = decode_j($json)->{release};
       #Log3(undef, 1, "setreading $NAME valetudo_release $ret" );
       fhem("setreading $NAME valetudo_release $ret");
       return undef;
    }
    if ($load =~ m,^ip.*,){ fhem("setreading $NAME ip4 $ip") }
    return undef;
}

#######
# setup according supported features
sub valetudo_s {
    my $NAME = shift;
    if (valetudo_f($NAME,'MapSegmentation') ) {
        CommandAttr_multiline($NAME,'setList',q(  clean_segment:{'multiple-strict,'.valetudo_w($name,'segments')} { valetudo_c($NAME,$EVENT) }) );
        fhem("set $NAME get segments");
    }
    if (valetudo_f($NAME,'GoToLocation') ) {
        CommandAttr_multiline($NAME,'setList',q(  goto:{valetudo_w($name,'locations')} { valetudo_c($NAME,$EVENT) }) );
        CommandAttr_multiline($NAME,'setList',q(  locationNew:textField { valetudo_z($NAME,$EVENT) }) );
        CommandAttr_multiline($NAME,'setList',q(  locationRename:textField { valetudo_z($NAME,$EVENT) }) );
    }
    if (valetudo_f($NAME,'WaterUsageControl') ) {
        CommandAttr_multiline($NAME,'setList',q(  waterUsage:low,medium,high $DEVICETOPIC/WaterUsageControlCapability/preset/set $EVTPART1) );
    }
}

#######
# add a line to multiline Attribute setList or regList
# CommandAttr_multiline( 'MQTT2_valetudo_xxx','setList',q(  clean_segment:{"multiple-strict,".valetudo_w($name,"segments")} { valetudo_c($NAME,$EVENT) }) )
sub CommandAttr_multiline {
    my $NAME = shift;
    my $attr = shift;
    my $item = shift;
    if ($attr ne 'setList' and $attr ne 'readingList') {return 'use only for multiline attrib'}
    my $val = AttrVal($NAME,$attr,'')."\n".$item;
    CommandAttr(undef, "$NAME $attr $val");
}

1;
=pod
=item summary    generic MQTT2 vacuum valetudo Device
=item summary_DE generische MQTT2 Staubsauger gerootet mit valetudo
=begin html
Subroutines for generic MQTT2 vacuum cleaner Devices rooted with valetudo.
<a id="MQTT2 valetudo"></a>
<h3>MQTT2 valetudoUtils</h3>
<ul>
  subroutines<br>
  <b>valetudo_w</b> return a string for dynamic selection setList<br>
  <b>valetudo_c</b> return a complete string for setList right part of setList<br>
  <b>valetudo_z</b> handling .zones Reading<br>
  <b>valetudo_f</b> ask the robot via REST API for Featurelist and feature and return true false<br>
  <b>valetudo_r</b> used for readingList. return readingname -> value pairs<br>
  <b>valetudo_g</b> get some Information with Rest Api<br>
  <b>valetudo_s</b> doing model spezific setup<br>
  <b>CommandAttr_multiline</b> add a line to multiline Attribute setList or regList<br>
  CommandAttr_multiline( 'MQTT2_valetudo_xxx','setList',q(  clean_segment:{"multiple-strict,".valetudo_w($name,"segments")} { valetudo_c($NAME,$EVENT) }) )<br>
  <br>
  <a id="MQTT2_DEVICE-setList"></a>
  <b>attr setList</b>
  <ul>
    <code>clean_segment:{"multiple-strict,".valetudo_w($name,"segments")} { valetudo_c($NAME,$EVENT) }</code>
    <br><br>
    To use dynamic setList. The $EVENT is parsed inside utils.<br>
  </ul>
  <br>
</ul>
=end html
=begin html_DE
Subroutines for generic MQTT2 vacuum cleaner Devices rooted with valetudo.
<a id="MQTT2 valetudo"></a>
<h3>MQTT2 valetudoUtils</h3>
<ul>
  subroutines<br>
  <b>valetudo_w</b> return a string for dynamic selection setList<br>
  <b>valetudo_c</b> return a complete string for setList right part of setList<br>
  <b>valetudo_z</b> handling .zones Reading<br>
  <b>valetudo_f</b> ask the robot via REST API for Featurelist and feature and return true false<br>
  <b>valetudo_r</b> used for readingList. return readingname -> value pairs<br>
  <b>valetudo_g</b> get some Information with Rest Api<br>
  <b>valetudo_s</b> doing model spezific setup<br>
  <b>CommandAttr_multiline</b> add a line to multiline Attribute setList or regList<br>
  CommandAttr_multiline( 'MQTT2_valetudo_xxx','setList',q(  clean_segment:{"multiple-strict,".valetudo_w($name,"segments")} { valetudo_c($NAME,$EVENT) }) )<br>
  <br>
  <a id="MQTT2_DEVICE-setList"></a>
  <b>attr setList</b>
  <ul>
    <code>clean_segment:{"multiple-strict,".valetudo_w($name,"segments")} { valetudo_c($NAME,$EVENT) }</code>
    <br><br>
    To use dynamic setList. The $EVENT is parsed inside utils.<br>
  </ul>
  <br>
</ul>
=end html_DE
=cut

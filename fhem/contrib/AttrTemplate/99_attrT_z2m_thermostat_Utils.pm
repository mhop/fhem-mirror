##############################################
# $Id$
#

package FHEM::attrT_z2m_thermostat_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;
use JSON qw(decode_json);
#use Time::HiRes qw( gettimeofday );
#use List::Util qw( min max );

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          AttrVal
          InternalVal
          CommandGet
          CommandSet
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsVal
          ReadingsNum
          ReadingsAge
          json2nameValue
          defs
          Log3
          )
    );
}

sub main::attrT_z2m_thermostat_Utils_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

#attr DEVICE userReadings charger_state:car.* { my $val = ReadingsVal($name,"car","none");; my %rets = ("none" => "-1","1" => "Ready","2" => "Charging","3" => "waiting for car","4" => "Charging finished",);; $rets{$val}}, energy_total:eto.* { ReadingsVal($name,"eto",0)*0.1 }, energy_akt:dws.* { ReadingsVal($name,"dws",0)*2.77 }
  
  #attr DEVICE jsonMap alw:Activation amp:Ampere tmp:temperature
  

my %jsonmap = ( 
    
);

sub z2t_send_weekprofile {
  my $name       = shift;
  my $wp_name    = shift;
  my $wp_profile = shift // return;
  my $model      = shift // ReadingsVal($name,'week','5+2');
  my $topic      = shift // AttrVal($name,'devicetopic','') . '/set';
  
  my $hash = $defs{$name};
  $topic   .= ' ';
    
  my $wp_profile_data = CommandGet(undef,"$wp_name profile_data $wp_profile 0");
  if ($wp_profile_data =~ m{(profile.*not.found|usage..profile_data..name)}xms ) {
    Log3( $hash, 3, "[$name] weekprofile $wp_name: no profile named \"$wp_profile\" available" );
    return;
  }
    
  my @D = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat");
  my $payload;
  my @days = (0..6);
  my $text = decode_json($wp_profile_data);
  
  if ( $model eq '5+2' || $model eq '6+1') {
    @days = (0,1);
    #$payload = '{"holidays":[';
  } elsif ($model eq '7') {
    @days = (1);
    #$payload = '{"workdays":[';
  }
  
  for my $i (@days) {
      $payload = '{';
      
      for my $j (0..7) {
        if (defined $text->{$D[$i]}{'time'}[$j]) {
          my $time = $text->{$D[$i]}{'time'}[$j-1] // "00:00";
          my ($hour,$minute) = split m{:}xms, $time;
          $hour = 0 if $hour == 24;
          $payload .= '"hour":' . abs($hour) .',"minute":'. abs($minute) .',"temperature":'.$text->{$D[$i]}{'temp'}[$j];
          $payload .= '},{' if defined $text->{$D[$i]}{'time'}[$j+1];
        }
      }
      $payload .='}';
      if ( $i == 0 && ( $model eq '5+2' || $model eq '6+1') ) {
        #$payload .='},'if $i == 0 || $i > 1 && $i != $days[-1];
        #$payload .='],"workdays":[' if $i == 1;
        CommandSet($defs{$name},"$name holidays $payload");
        $payload = '{';
      }
      CommandSet($defs{$name},"$name workdays $payload") if $model eq '5+2' || $model eq '6+1' || $model eq '7';
  }
  #$payload .=']}';
  readingsSingleUpdate( $defs{$name}, 'weekprofile', "$wp_name $wp_profile",1);
  return;
}
  

1;

__END__

=pod
=begin html

<a name="attrT_z2m_thermostat_Utils"></a>
<h3>attrT_z2m_thermostat_Utils</h3>
<ul>
  <b>z2t_send_weekprofile</b>
  <br>
  This is a special function to request temperature list data from <i>weekprofile</i> and convert and send it out via MQTT<br>
  <br>
  General requirements and prerequisites:<br>
  <ul>
  <li>existing <i>weekprofile</i> device with activated <i>useTopic</i> feature</li>
  <li>weekprofile attribute set at calling MQTT2_DEVICE</li>
  </ul>
  <br>
  Special remarks for usage with attrTemplate <i>zigbee2mqtt_thermostat_with_weekrofile</i>:<br>
  <ul>
  <li>existing <i>setList</i> entries required (<i>workdays</i> and <i>holidays</i>)</li>
  <li>for conversion from <i>weekprofile</i> data to entries <i>workdays</i> and <i>holidays</i> only monday and sunday data will be used, other days will be ignored</li>
  <li>as parameters, <i>$name</i> (name of the calling MQTT2_DEVICE), <i>$wp_name</i> (name of the weekprofile device) and $wp_profile (in "topic:entity" format) have to be used, when topic changes are done via weekprofile, the relevent data will be sent to the MQTT2_DEVICE instances with suitable <i>weekprofile</i> attribute automatically.<br>
  Additionally you may force sending holiday data by adding a forth parameter ($model) and set that to '5+2'.<br>
  So entire Perl command for <i>zigbee2mqtt_thermostat_with_weekrofile</i> should look like:
  <ul>
   <code>FHEM::attrT_z2m_thermostat_Utils::z2t_send_weekprofile($NAME, $EVTPART1, $EVTPART2)</code><br>
  </ul><br>or 
  <ul>
   <code>FHEM::attrT_z2m_thermostat_Utils::z2t_send_weekprofile($NAME, $EVTPART1, $EVTPART2, '5+2')</code><br>
  </ul>
  </ul>
</ul>
=end html
=cut

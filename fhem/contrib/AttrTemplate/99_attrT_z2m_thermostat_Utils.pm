##############################################
# $Id$
#

package FHEM::attrT_z2m_thermostat_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;
use JSON qw(decode_json);
use Carp qw(carp);
#use POSIX qw(strftime);
#use List::Util qw( min max );
#use Scalar::Util qw(looks_like_number);
#use Time::HiRes qw( gettimeofday );

use GPUtils qw(GP_Import);

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {
    # Import from main context
    GP_Import(
        qw(
          AttrVal
          InternalVal
          ReadingsVal
          ReadingsNum
          ReadingsAge
          CommandGet
          CommandSet
          readingsSingleUpdate
          json2nameValue
          defs
          Log3
          )
    );
}

sub ::attrT_z2m_thermostat_Utils_Initialize { goto &Initialize }

# initialize ##################################################################
sub Initialize {
  my $hash = shift;
  return;
}

# Enter you functions below _this_ line.

my %jsonmap = ( 

);

sub z2t_send_weekprofile {
  my $name       = shift // carp q[No device name provided!]              && return;
  my $wp_name    = shift // carp q[No weekprofile device name provided!]  && return;
  my $wp_profile = shift // carp q[No weekprofile profile name provided!] && return;
  my $model      = shift // ReadingsVal($name,'week','5+2');
  my $topic      = shift // AttrVal($name,'devicetopic','') . '/set';

  my $hash = $defs{$name};
  $topic   .= ' ';

  my $wp_profile_data = CommandGet(undef,"$wp_name profile_data $wp_profile 0");
  if ($wp_profile_data =~ m{(profile.*not.found|usage..profile_data..name)}xms ) {
    Log3( $hash, 3, "[$name] weekprofile $wp_name: no profile named \"$wp_profile\" available" );
    return;
  }

  my @D = qw(Sun Mon Tue Wed Thu Fri Sat); # eqals to my @D = ("Sun","Mon","Tue","Wed","Thu","Fri","Sat");
  my $payload;
  my @days = (0..6);
  my $decoded;
  if ( !eval { $decoded  = decode_json($wp_profile_data) ; 1 } ) {
    Log3($name, 1, "JSON decoding error in $wp_profile provided by $wp_name: $@");
    return;
  }

  if ( $model eq '5+2' || $model eq '6+1') {
    @days = (0,1);
  } elsif ($model eq '7') {
    @days = (1);
  }

  for my $i (@days) {
      $payload = '{';

      for my $j (0..7) {
        if (defined $decoded->{$D[$i]}{'time'}[$j]) {
          my $time = $decoded->{$D[$i]}{'time'}[$j-1] // "00:00";
          my ($hour,$minute) = split m{:}xms, $time;
          $hour = 0 if $hour == 24;
          $payload .= '"hour":' . abs($hour) .',"minute":'. abs($minute) .',"temperature":'.$decoded->{$D[$i]}{'temp'}[$j];
          $payload .= '},{' if defined $decoded->{$D[$i]}{'time'}[$j+1];
        }
      }
      $payload .='}';
      if ( $i == 0 && ( $model eq '5+2' || $model eq '6+1') ) {
        CommandSet($hash,"$name holidays $payload");
        $payload = '{';
      }
      CommandSet($hash,"$name workdays $payload") if $model eq '5+2' || $model eq '6+1' || $model eq '7';
  }
  readingsSingleUpdate( $hash, 'weekprofile', "$wp_name $wp_profile",1);
  return;
}

1;

__END__

=pod
=item summary helper functions needed for zigbee2mqtt thermostats in MQTT2_DEVICE
=item summary_DE Hilfsfunktionen für zigbee2mqtt MQTT2_DEVICE-Thermostate 
=begin html
<a id="attrT_z2m_thermostat_Utils"></a>
  There may be room for improvement, please adress any issues in https://forum.fhem.de/index.php/topic,116535.0.html.
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

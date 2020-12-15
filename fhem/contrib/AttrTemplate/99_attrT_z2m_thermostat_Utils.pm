##############################################
# $Id: attrT_z2m_thermostat_Utils.pm 2020-12-10 Beta-User $
#

package FHEM::attrT_z2m_thermostat_Utils;    ## no critic 'Package declaration'

use strict;
use warnings;
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
          readingsSingleUpdate
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          ReadingsVal
          ReadingsNum
          ReadingsAge
		  decode_json
          json2nameValue
          defs
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
  my $topic      = shift // AttrVal($name,'devicetopic','') . '/set';
  my $model      = shift // ReadingsVal($name,'week','5+2');
  
  my $hash = $defs{$name};
  $topic   .= ' ';
    
  my $wp_profile_data = CommandGet(undef,"$wp_name profile_data $wp_profile");
  if ($wp_profile_data =~ m{(profile.*not.found|usage..profile_data..name)}xms ) {
    Log3( $hash, 3, "[$name] weekprofile $wp_name: no profile named \"$wp_profile\" available" );
    return;
  }
    
  my @D = ("Sat","Sun","Mon","Tue","Wed","Thu","Fri");
  my $payload;
  my @days = (0..6);
  my $text = decode_json($wp_profile_data);
  
  if ( $model eq '5+2' || $model eq '6+1') {
    @days = (1,2);
	$payload = '{"holidays":[';
  } elsif ($model eq '7') {
    @days = (2);
	$payload = '{"workdays":[';
  }
  
  for my $i (@days) {
      $payload.='{';
      
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
	  if ($model eq '5+2' || $model eq '6+1') {
        $payload .='},'if $i == 0 || $i > 1 && $i != $days[-1];
	    $payload .='],"workdays":[' if $i == 1;
      }
  }
  $payload .=']}';
  readingsSingleUpdate( $defs{$name}, 'weekprofile', "$wp_name $wp_profile",1);
  return "$topic $payload";
}
  

1;

__END__

=pod
=begin html

<a name="attrT_z2m_thermostat_Utils"></a>
<h3>attrT_z2m_thermostat_Utils</h3>

=end html
=cut

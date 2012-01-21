#
#
# 59_Weather.pm
# written by Dr. Boris Neubert 2009-06-01
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Weather::Google;

#####################################
sub Weather_Initialize($) {

  my ($hash) = @_;

# Provider
#  $hash->{Clients} = undef;

# Consumer
  $hash->{DefFn}   = "Weather_Define";
  $hash->{UndefFn} = "Weather_Undef";
  $hash->{GetFn}   = "Weather_Get";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5";

}

###################################
sub f_to_c($) {

  my ($f)= @_;
  return int(($f-32)*5/9+0.5);
}

###################################
sub Weather_UpdateReading($$$$$$) {

  my ($hash,$prefix,$key,$tn,$value,$n)= @_;

  return 0 if(!defined($value) || $value eq "");
  
  if($key eq "temp") {
  	$key= "temp_c";
   	$value= f_to_c($value) if($hash->{READINGS}{unit_system}{VAL} ne "SI");  # assume F to C conversion required
  } elsif($key eq "low") {
  	$key= "low_c";
      	$value= f_to_c($value) if($hash->{READINGS}{unit_system}{VAL} ne "SI");  
  } elsif($key eq "high") {
  	$key= "high_c"; 
    	$value= f_to_c($value) if($hash->{READINGS}{unit_system}{VAL} ne "SI");  
  }

  my $reading= $prefix . $key;
  my $r= $hash->{READINGS};
  $r->{$reading}{TIME}= $tn;
  $r->{$reading}{VAL} = $value;

  my $name= $hash->{NAME};
  Log 1, "Weather $name: $reading= $value";

  $hash->{CHANGED}[$n]= "$key: $value";
  
  return 1;
}

###################################
sub Weather_GetUpdate($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Weather_GetUpdate", $hash, 1);
  }

  my $name = $hash->{NAME};

  my $n= 0;


  # time
  my $tn = TimeNow();


  # get weather information from Google weather API
  # see http://search.cpan.org/~possum/Weather-Google-0.03/lib/Weather/Google.pm

  my $location= $hash->{LOCATION};
  my $lang= $hash->{LANG}; 
  my $WeatherObj;
  Log 4, "$name: Updating weather information for $location, language $lang."; 
  eval {
 	$WeatherObj= new Weather::Google($location, {language => $lang}); 
  };
  if($@) {
	Log 1, "$name: Could not retrieve weather information.";
	return 0;
  }

  my $current = $WeatherObj->current_conditions;
  foreach my $condition ( keys ( %$current ) ) {
  	my $value= $current->{$condition};
  	Weather_UpdateReading($hash,"",$condition,$tn,$value,$n);
  	$n++;
  }

  my $fci= $WeatherObj->forecast_information;
  foreach my $i ( keys ( %$fci ) ) {
  	my $reading= $i;
  	my $value= $fci->{$i};
  	Weather_UpdateReading($hash,"",$i,$tn,$value,$n);
        $n++;
  }

  for(my $t= 0; $t<= 3; $t++) {
  	my $fcc= $WeatherObj->forecast_conditions($t);
  	my $prefix= sprintf("fc%d_", $t);
	foreach my $condition ( keys ( %$fcc ) ) {
  		my $value= $fcc->{$condition};
	  	Weather_UpdateReading($hash,$prefix,$condition,$tn,$value,$n);
        $n++;
  	}
  }

  return 1;
}

# Perl Special: { $defs{Weather}{READINGS}{condition}{VAL} }
# conditions: Mostly Cloudy, Overcast, Clear, Chance of Rain

###################################
sub Weather_Get($@) {

  my ($hash, @a) = @_;

  return "argument is missing" if(int(@a) != 2);

  $hash->{LOCAL} = 1;
  Weather_GetUpdate($hash);
  delete $hash->{LOCAL};

  my $reading= $a[1];
  my $value;

  if(defined($hash->{READINGS}{$reading})) {
  	$value= $hash->{READINGS}{$reading}{VAL};
  } else {
  	return "no such reading: $reading";
  }

  return "$a[0] $reading => $value";
}


#####################################
sub Weather_Define($$) {

  my ($hash, $def) = @_;

  # define <name> Weather <location> [interval]
  # define MyWeather Weather "Maintal,HE" 3600

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Weather <location> [interval [en|de|fr|es]]" 
    if(int(@a) < 3 && int(@a) > 5); 

  $hash->{STATE} = "Initialized";

  my $name	= $a[0];
  my $location	= $a[2];
  my $interval	= 3600;
  my $lang	= "en"; 
  if(int(@a)>=4) { $interval= $a[3]; }
  if(int(@a)==5) { $lang= $a[4]; } 

  $hash->{LOCATION}	= $location;
  $hash->{INTERVAL}	= $interval;
  $hash->{LANG}		= $lang; 
  $hash->{READINGS}{current_date_time}{TIME}= TimeNow();
  $hash->{READINGS}{current_date_time}{VAL}= "none";

  $hash->{LOCAL} = 1;
  Weather_GetUpdate($hash);
  delete $hash->{LOCAL};

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "Weather_GetUpdate", $hash, 0);

  return undef;
}

#####################################
sub Weather_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

#####################################


1;

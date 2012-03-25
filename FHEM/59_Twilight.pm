#
# 59_Twilight.pm
# written by Sebastian Stuecker based on Twilight.tcl http://www.homematic-wiki.info/mw/index.php/TCLScript:twilight
#
##############################################

package main;
use strict;
use warnings;
use Switch;
use POSIX;

sub dayofyear {
    my ($day1,$month,$year)=@_;
    my @cumul_d_in_m =
(0,31,59,90,120,151,181,212,243,273,304,334,365);
    my $doy=$cumul_d_in_m[--$month]+$day1;
    return $doy if $month < 2;
    return $doy unless $year % 4 == 0;
    return ++$doy unless $year % 100 == 0;
    return $doy unless $year % 400 == 0;
    return ++$doy;
}

sub my_gmt_offset {
	# inspired by http://stackoverflow.com/questions/2143528/whats-the-best-way-to-get-the-utc-offset-in-perl
	# avoid use of any CPAN module and ensure system independent behavior
	my $t = time;
    my @a = localtime($t);
    my @b = gmtime($t);
    my $hh = $a[2] - $b[2];
    my $mm = $a[1] - $b[1];
    # in the unlikely event that localtime and gmtime are in different years
    if ($a[5]*366+$a[4]*31+$a[3] > $b[5]*366+$b[4]*31+$b[3]) {
      $hh += 24;
    } elsif ($a[5]*366+$a[4]*31+$a[3] < $b[5]*366+$b[4]*31+$b[3]) {
      $hh -= 24;
    }
    if ($hh < 0 && $mm > 0) {
      $hh++;
      $mm = 60-$mm;
    }
    return $hh+($mm/60);
}

##################################### 
sub Twilight_Initialize($) {

  my ($hash) = @_;

# Provider#  $hash->{Clients} = undef;

# Consumer
  $hash->{DefFn}   = "Twilight_Define";
  $hash->{UndefFn} = "Twilight_Undef";
  $hash->{GetFn}   = "Twilight_Get";
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5 event-on-update-reading event-on-change-reading";

}

sub Twilight_Get($@) {

  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  $hash->{LOCAL} = 1;
  Twilight_GetUpdate($hash);
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


sub Twilight_Define($$) {

  my ($hash, $def) = @_;
  # define <name> Twilight <latitude> <longitude> [indoor_horizon [Weather_Position]]
  # define MyTwilight Twilight 48.47 11.92 Weather_Position

  my @a = split("[ \t][ \t]*", $def);

  return "syntax: define <name> Twilight <latitude> <longitude> [indoor_horizon [Weather]]"
    if(int(@a) < 4 && int(@a) > 6);

  $hash->{STATE} = "0";
  my $latitude;
  my $longitude;
  my $name      = $a[0];
  if ($a[2] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[2] !~ /^[\. ]*$/ ) {
     $latitude  = $a[2];
	 if($latitude>90){$latitude=90;}
	 if($latitude<-90){$latitude=-90;}
	 }else{return "Argument Latitude is not a valid number";}
  if ($a[3] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[3] !~ /^[\. ]*$/ ) {
     $longitude  = $a[3];
	 if($longitude>180){$longitude=180;}
	 if($longitude<-180){$longitude=-180;}
	 }else{return "Argument Longitude is not a valid number";}
  my $weather   = "";
  my $indoor_horizon="4";
  if(int(@a)>5) { $weather=$a[5] }
  if(int(@a)>4) { if ($a[4] =~ /^[\+-]*[0-9]*\.*[0-9]*$/ && $a[4] !~ /^[\. ]*$/ ) {
	$indoor_horizon  = $a[4];
	if($indoor_horizon>20){ $indoor_horizon=20;}
	if($indoor_horizon<0){$indoor_horizon=0;}
  }else{return "Argument Indoor_Horizon is not a valid number";} }
   
  $hash->{LATITUDE}     = $latitude;
  $hash->{LONGITUDE}    = $longitude;
  $hash->{WEATHER}      = $weather;
  $hash->{INDOOR_HORIZON} = $indoor_horizon;
 
   Twilight_GetUpdate($hash);
   return undef;
}

sub Twilight_Undef($$) {

  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}


sub twilight_midnight_seconds() { my @time = localtime(); my $secs = ($time[2] * 3600) + ($time[1] * 60) + $time[0]; return $secs; }


sub Twilight_GetUpdate($){
   my ($hash) = @_; 
   my @sunrise_set;   
   
   readingsBeginUpdate($hash);
   my $sunrise;
   my $sunset;
   my $latitude=$hash->{LATITUDE};
   my $longitude=$hash->{LONGITUDE};
   my $horizon=$hash->{HORIZON};
   my $now=time;
   my $midnight=twilight_midnight_seconds();
   my $midseconds=$now-$midnight;
   my $year=strftime("%Y",localtime);
   my $month=strftime("%m",localtime);
   my $day=strftime("%d",localtime);
   my $doy = dayofyear($day,$month,$year)+(($year%4)/4);
   $doy+=($doy/365.0)/4.0;
   my $timezone=my_gmt_offset();
   my $timediff=-0.171*sin(0.0337*$doy+0.465) - 0.1299*sin(0.01787 * $doy - 0.168);
   my $declination=0.4095*sin(0.016906*($doy-80.086));
   my $twilight_midnight=$now+(0-$timediff-$longitude/15+$timezone)*3600;
   my $yesterday_offset;
   if($now<$twilight_midnight){
      $yesterday_offset=86400;
   }else{
      $yesterday_offset=0; 
   }
   $year=strftime("%Y",localtime($now-$yesterday_offset));
   $month=strftime("%m",localtime($now-$yesterday_offset));
   $day=strftime("%d",localtime($now-$yesterday_offset));
   $doy = dayofyear($day,$month,$year)+(($year%4)/4);
   
   $sunrise_set[0]{SR_NAME}="sr_astro";
   $sunrise_set[0]{SS_NAME}="ss_astro";
   $sunrise_set[0]{DEGREE}=-18;
   $sunrise_set[1]{SR_NAME}="sr_naut";
   $sunrise_set[1]{SS_NAME}="ss_naut";
   $sunrise_set[1]{DEGREE}=-12;
   $sunrise_set[2]{SR_NAME}="sr_civil";
   $sunrise_set[2]{SS_NAME}="ss_civil";
   $sunrise_set[2]{DEGREE}=-6;
   $sunrise_set[3]{SR_NAME}="sr";
   $sunrise_set[3]{SS_NAME}="ss";
   $sunrise_set[3]{DEGREE}=0;
   $sunrise_set[4]{SR_NAME}="sr_indoor";
   $sunrise_set[4]{SS_NAME}="ss_indoor";
   $sunrise_set[4]{DEGREE}=$hash->{INDOOR_HORIZON};
   $sunrise_set[5]{SR_NAME}="sr_weather";
   $sunrise_set[5]{SS_NAME}="ss_weather";
   $hash->{WEATHER_HORIZON}=Twilight_getWeatherHorizon($hash->{WEATHER})+$hash->{INDOOR_HORIZON};
   if($hash->{WEATHER_HORIZON}>(89-$hash->{LATITUDE}+$declination)){$hash->{WEATHER_HORIZON}=89-$hash->{LATITUDE}+$declination;}
   $sunrise_set[5]{DEGREE}=$hash->{WEATHER_HORIZON};
   

   for(my $i=0;$i<6;$i++){
      ($sunrise_set[$i]{RISE},$sunrise_set[$i]{SET})=
         twilight_calc($latitude,$longitude,$sunrise_set[$i]{DEGREE},$declination,$timezone,$midseconds,$timediff);
         readingsUpdate($hash,$sunrise_set[$i]{SR_NAME},strftime("%H:%M:%S",localtime($sunrise_set[$i]{RISE})));
         readingsUpdate($hash,$sunrise_set[$i]{SS_NAME},strftime("%H:%M:%S",localtime($sunrise_set[$i]{SET})));
   }     
   my $k=0;
   my $half="RISE";   
   my $nexttime;
   my $licht;
   for(my $i=0;$i < 12;$i++){
       $nexttime=$sunrise_set[6-abs($i-6)-$k]{$half};
       if($nexttime > $now && $nexttime!=2000000000){
         readingsUpdate($hash,"light", 6-abs($i-6));
         if($i<6){
			readingsUpdate($hash,"nextEvent",$sunrise_set[6-abs($i-6)-$k]{SR_NAME});
		 }else{
		    readingsUpdate($hash,"nextEvent",$sunrise_set[6-abs($i-6)-$k]{SS_NAME});
		 }
         readingsUpdate($hash,"nextEventTime",strftime("%H:%M:%S",localtime($nexttime)));
         if($i==5 || $i==6){
		    $nexttime = ($nexttime-$now)/2;
		    $nexttime=120 if($nexttime<120);
		    $nexttime=900 if($nexttime>900);
         }else{
		    $nexttime = $nexttime-$now+10;
	 }
	 if(!$hash->{LOCAL}) {
	    InternalTimer(sprintf("%.0f",$now+$nexttime), "Twilight_GetUpdate", $hash, 0);
 	    readingsUpdate($hash,"nextUpdate",strftime("%H:%M:%S",localtime($now+$nexttime)));
	 }
	 $hash->{STATE}=$i;
	 last;
       }
      if ($i == 5){
         $k=1;
         $half="SET";
      }
	  if($nexttime<$now && $i==11){
		if(!$hash->{LOCAL}) {
			InternalTimer($now+900, "Twilight_GetUpdate", $hash, 0);
		}
		readingsUpdate($hash,"light", 0);
		$hash->{STATE}=0;
	  }
   }
   
   readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1)); 
   return 1;
}

sub twilight_calc() {
   my $latitude=shift;
   my $longitude=shift;
   my $horizon=shift;
   my $declination=shift;
   my $timezone=shift;
   my $midseconds=shift;
   my $timediff=shift;
   my $suntime=0;
   my $sunrise=0;
   my $sunset=0;
   eval {
        $suntime=12*acos((sin($horizon/57.29578)-sin($latitude/57.29578)*sin($declination))/(cos($latitude/57.29578)*cos($declination)))/3.141592 ;
        $sunrise=$midseconds+(12-$timediff-$suntime-$longitude/15+$timezone)*3600;
        $sunset=$midseconds+(12-$timediff+$suntime-$longitude/15+$timezone)*3600;
   };
   if($@){
      $sunrise=0;
      $sunset=2000000000;
   }
   return $sunrise, $sunset;
}

sub Twilight_getWeatherHorizon(){
   my $location=shift;
   #my $xml = GetHttpFile("www.google.com:80", "/ig/api?weather=" . $location . "&hl=en");
   #$xml =~/\<current_conditions\>(.*)\<\/current_conditions\>/;
   #my $current=$1;
   #$current=~/<condition data="(.*)"\/\>\<temp_f/;
   
   my $xml = GetHttpFile("weather.yahooapis.com:80","/forecastrss?w=".$location."&u=c");
   $xml=~/code="(.*)"(\ *)temp/;
   my $current=$1;
   switch($current){
      case 0				{return 25;}
	  case 1				{return 25;}
	  case 2				{return 25;}
	  case 3				{return 25;}
	  case 4				{return 20;}
	  case 5				{return 10;}
	  case 6				{return 10;}
	  case 7				{return 10;}
	  case 8				{return 10;}
	  case 9				{return 10;}
	  case 10				{return 10;}
	  case 11				{return 7;}
	  case 12				{return 7;}
	  case 13				{return 7;}
	  case 14				{return 5;}
	  case 15				{return 10;}
	  case 17				{return 6;}
	  case 18				{return 6;}
	  case 19				{return 6;}
	  case 20				{return 10;}
	  case 21				{return 6;}
	  case 22				{return 6;}
	  case 23				{return 6;}
	  case 24				{return 6;}
	  case 25				{return 6;}
	  case 26				{return 6;}
	  case 27				{return 5;}
	  case 28				{return 5;}
	  case 29				{return 3;}
	  case 30				{return 3;}
	  case 31				{return 0;}
	  case 32				{return 0;}
	  case 33				{return 0;}
	  case 34				{return 0;}
	  case 35				{return 7;}
	  case 36				{return 0;}
	  case 37				{return 15;}
	  case 38				{return 15;}
	  case 39				{return 15;}
	  case 40				{return 9;}
	  case 41				{return 15;}
	  case 42				{return 8;}
	  case 43				{return 5;}
	  case 44				{return 12;}
	  case 45				{return 6;}
	  case 46				{return 8;}
	  case 47				{return 8;}
	  else					{return 1;}
	  }
   if($current eq "Light rain"){return 2;}else{return 15;}
}


1;


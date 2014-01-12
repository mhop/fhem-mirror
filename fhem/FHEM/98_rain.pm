#  $Id$
##############################################
#
# Rain computing 
#
# based / modified from dewpoint.pm (C) by Rudolf Koenig
#
# Copyright (C) 2012 Andreas Vogt
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# The GNU General Public License may also be found at http://www.gnu.org/licenses/gpl-2.0.html .
#

package main;
use strict;
use warnings;
use Time::Local;
    
# Debug this module? YES = 1, NO = 0
my $rain_debug = 0;

##########################
sub
rain_Initialize($)
{
  my ($hash) = @_;
  $hash->{DefFn}   = "rain_Define";
  $hash->{NotifyFn} = "rain_Notify";
  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} =   "disable:0,1 ".
  						"DayChangeTime ".
  						"CorrectionValue ".
  						"DontUseIsRaining:1,0 ".
  						$readingFnAttributes;
}

##########################
sub
rain_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> rain devicename [rain_name] [israining_name] [new_name]"
    if(@a < 3);

  my $name = $a[0];
  my $devname = $a[2];

  	if(@a == 6) {
  		$hash->{RAIN_NAME} = $a[3];
  		$hash->{ISRAINING_NAME} = $a[4];
  		$hash->{NEW_NAME} = $a[5];
  	} elsif (@a == 3) {
  		$hash->{RAIN_NAME} = "rain";
  		$hash->{ISRAINING_NAME} = "israining";
  		$hash->{NEW_NAME} = "rain_calc";
	} else {
		return "wrong syntax: define <name> rain devicename-regex [rain_name israining_name new_name]"
	}
 
  eval { "Hallo" =~ m/^$devname$/ };
  return "Bad regecaxp: $@" if($@);
  $hash->{DEV_REGEXP} = $devname;

  $hash->{STATE} = "active";
  return undef;
}


##########################
sub
rain_Notify($$)
{
  my ($hash, $dev) = @_;
  my $hashName = $hash->{NAME};
  
  return "" if(AttrVal($hashName, "disable", undef));
  return "" if(!defined($hash->{DEV_REGEXP}));

    my @txt = ( "rain", "rain_h", "rain_d", "humidity", "temperature",
                "israining", "unknown1", "unknown2", "unknown3");
    my @sfx = ( "(counter)", "(l/m2)", "(km/h)", "(%)", "(Celsius)",
                "(yes/no)", "","","");
    my %repchanged = ("rain"=>1, "wind"=>1, "humidity"=>1, "temperature"=>1,
                "israining"=>1, "rain_all"=>1);

    # time
    my $tm = TimeNow();
    my $tsecs= time();  # number of non-leap seconds since January 1, 1970, UTC
    
    # The next instr wont work for empty hashes, so we init it now
    $dev->{READINGS}{$txt[0]}{VAL} = 0 if(!$dev->{READINGS});
    my $r = $dev->{READINGS};
    
  my $devName = $dev->{NAME};

  my $re = $hash->{DEV_REGEXP};

  # rain
  my $rain_name = "rain";
  my $israining_name = "israining";
  my $new_name = "rain_calc";
  # fan
  my $devname_out = "";
  my $min_rain = 0;
  # alarm
  my $devname_ref = "";
  my $diff_rain = 0;
    
  if (!defined($hash->{RAIN_NAME}) || !defined($hash->{ISRAINING_NAME}) || !defined($hash->{NEW_NAME})) {
		# should never happen!
		Log3 $hash, 1, "Error rain: RAIN_NAME || ISRAINING_NAME || NEW_NAME undefined";
		return "";
  	}
  	$rain_name = $hash->{RAIN_NAME};
  	$israining_name = $hash->{ISRAINING_NAME};
  	$new_name = $hash->{NEW_NAME};
  	Log3 $hash, 5, "rain_notify: devname=$devName rainname=$hashName, dev=$devName, dev_regex=$re rain_name=$rain_name israining_name=$israining_name";
 	      
  my $DayChangeTime = "0730";
  my $DayChangeTimeHour = "07";    #use as checked value
  my $DayChangeTimeMinutes = "30"; #use as checked value
  my $HourChangeTimeMinutes = "30"; #use as checked value
  my $CorrectionValue = 1;
  my $DontUseIsRaining = 0;
  Log3 $hash, 1, "rain_notify: rain_Notify Defaults: DayChangeTime='$DayChangeTime' DontUseIsRaining='$DontUseIsRaining' CorrectionValue='$CorrectionValue'" if ($rain_debug == 1);
 	
 	if(defined($attr{$hashName}) &&
       defined($attr{$hashName}{"DayChangeTime"}) &&
       !($attr{$hashName}{"DayChangeTime"} eq "")) {
       		my $DayChangeTimeCheck = $attr{$hashName}{"DayChangeTime"}; #do not overwrite the default value until value is check
       		#(\d{2})(\d{2}) <-RegExp for 2x2 digits
       		#([012][\d])([012345][\d]) <-RegExp for 4 digit with timecode
       		#\([012][\d]\)\([012345][\d]\) <-RegExp for 4 digit with timecode
       			       					
			if ($DayChangeTimeCheck =~ /([012][\d])([012345][\d])/) {
       			#my $FistDigits = $DayChangeTimeCheck =~ s/([012][\d])([012345][\d])/$1/ ;
       			#my $SecondDigits = $DayChangeTimeCheck =~ s/([012][\d])([012345][\d])/$2/ ;
       			$DayChangeTimeHour = $1;
       			$DayChangeTimeMinutes = $2;
       			$HourChangeTimeMinutes = $DayChangeTimeMinutes;
       			Log3 $hash, 4, "Attribut matchs TimeCode DayChangeTime='$DayChangeTimeHour:$DayChangeTimeMinutes' ";
   				# tue etwas ...
			}
			else
			{
				Log3 $hash, 1, "Attribut DayChangeTime is not a correct timecode. will use '$DayChangeTimeHour:$DayChangeTimeMinutes' ";
			}
 			Log3 $hash, 1, "rain_notify: rain_Notify Attribut use DayChangeTime='$DayChangeTime' " if ($rain_debug == 1);
       }
       
       #my $cache = AttrVal($hashName, "DayChangeTime", undef);
			#if(defined($cache)){
				#AttrVal($hashName, "DayChangeTime", "");
			#	Log3 $hash, 1, "rain_notify: rain_Notify D Attribut defined CacheDayChangeTime='$cache' " if ($rain_debug == 1);
			#}
              
    #my $cache= (AttrVal($hash->{RAIN_NAME},"DayChangeTime","")) ? "default" : (AttrVal($hash->{RAIN_NAME},"DayChangeTime",""));
    #Log3 $hash, 1, "rain_notify: rain_Notify D Attribut defined CacheDayChangeTime='$cache' " if ($rain_debug == 1);
       
    if(defined($attr{$hashName}) &&
       defined($attr{$hashName}{"CorrectionValue"}) &&
       !($attr{$hashName}{"CorrectionValue"} eq "")) {
       		$CorrectionValue = $attr{$hashName}{"CorrectionValue"};
 			Log3 $hash, 1, "rain_notify: rain_Notify Attribut defined CorrectionValue='$CorrectionValue' " if ($rain_debug == 1);
       }
     
     if(defined($attr{$hashName}) &&
       defined($attr{$hashName}{"DontUseIsRaining"}) &&
       !($attr{$hashName}{"DontUseIsRaining"} eq "")) {
       		$DontUseIsRaining = $attr{$hashName}{"DontUseIsRaining"};
 			Log3 $hash, 1, "rain_notify: rain_Notify Attribut defined DontUseIsRaining='$DontUseIsRaining' " if ($rain_debug == 1);
       }
 
 
    Log3 $hash, 1, "rain_notify: rain_Notify DayChangeTime='$DayChangeTimeHour:$DayChangeTimeMinutes' DontUseIsRaining='$DontUseIsRaining' CorrectionValue='$CorrectionValue'" if ($rain_debug == 1);
 
 	$rain_name = $hash->{RAIN_NAME}; 
 		
  my $max = int(@{$dev->{CHANGED}});   
  my $n = -1;
  my $lastval;

  return "" if($devName !~ m/^$re$/);

  Log3 $hash, 1, "rain_notify: max='$max'" if ($rain_debug == 1);
  
  my $rain_value = "";
  my $israining = "";

  for (my $i = 0; $i < $max; $i++) {
    	my $s = $dev->{CHANGED}[$i];

    	Log3 $hash, 1, "rain_notify: s='$s'" if ($rain_debug == 1);

    	################
    	# Filtering
    	next if(!defined($s));
    	my ($evName, $val, $rest) = split(" ", $s, 3); # resets $1
    	next if(!defined($evName));
    	next if(!defined($val));
    	Log3 $hash, 1, "rain_notify: evName='$evName' val=$val'" if ($rain_debug == 1);
	if (($evName eq "R:") && ($rain_name eq "R")) {
		$n = $i;
   		#my ($evName1, $val1, $evName2, $val2, $rest) = split(" ", $s, 5); # resets $1
		#$lastval = $evName1." ".$val1." ".$evName2." ".$val2;		
		$lastval = $s;
		if ($s =~ /T: [-+]?([0-9]*\.[0-9]+|[0-9]+)/) {	
			$rain_value = $1;
		}
		if ($s =~ /H: [-+]?([0-9]*\.[0-9]+|[0-9]+)/) {	
			$israining = $1;
		}
    		Log3 $hash, 1, "rain_notify T: H:, rain=$rain_value unit=$israining" if ($rain_debug == 1);
	} elsif ($evName eq $rain_name.":") {
		$rain_value = $val;
    		Log3 $hash, 1, "rain_notify rain_value! rain=$rain_value" if ($rain_debug == 1);
	} elsif ($evName eq $israining_name.":") {
		$israining = $val;
    		Log3 $hash, 1, "rain_notify israining! unit=$israining" if ($rain_debug == 1);
	}
 
  }

  #if Attribut DontUSeIsRaining is set to 1 - set israining also to 1 / ignors device entry
  $israining = 1 if ($DontUseIsRaining == 1);
  
  Log3 $hash, 3, "rain_notify: n='$n'" if ($rain_debug == 1);
  Log3 $hash, 3, "rain_notify: rain_name='$rain_name'" if ($rain_debug == 1);
  
  if ($n == -1) { $n = $max; }
  
  Log3 $hash, 5, "rain_notify: get the following values rain_value=$rain_value " . ($rain_value eq "") . " israining=$israining " . ($israining eq "") if ($rain_debug == 1);
  
  if (($rain_value eq "") || ($israining eq "")) { Log3 $hash, 1, "rain_notify: no values for calculation found!"; }
  if (($rain_value eq "") || ($israining eq "")) { return undef; } # no way to calculate rain!

  # We found rain_value and israining. so we can calculate rain first
  
  # my $rain = sprintf("%.1f", rain($rain_value,$israining));
  my $rain = sprintf("%.1f", $rain_value * $CorrectionValue);
  
  Log3 $hash, 1, "rain_notify: rain=$rain" if ($rain_debug == 1);


	# >define <name> rain <devicename> [<rain_name> <israining_name> <new_name>]
	#
	# Calculates rain for device <devicename> from rain_value and israining and write it 
	# to new Reading rain. 
	# If optional <rain_name>, <israining_name> and <newname> is specified
	# then read rain_value from reading <rain_name>, israining from reading <israining_name>
	# and write rain to reading <rain_name>.
	# if rain_name eq "R" then use rain_value from state T: H: R:, add <newname> to the state
	# Example:
	# define raintest1 rain rain .*
	# define raintest2 rain rain .* T H D
	my $sensor = $new_name;
	my $current;

		$current = $rain;
        	
#		$dev->{READINGS}{$sensor}{TIME} = $tm;
#		$dev->{READINGS}{$sensor}{VAL} = $current;
#		$dev->{CHANGED}[$n++] = $sensor . ": " . $current;
		
				my $rain_value_prev=0;
	           	my $rain_h_last=0;
           	    my $rain_h_curr=0;
           	    my $rain_h_start;
           	    
           	    my $rain_d_last=0;
           	    my $rain_d_curr=0;
           	    my $rain_d_start;
           	    
           	    my $rain_h_trig_tsecs;
           	    my $rain_d_trig_tsecs;
           	    
           	    my $rain_tsecs_prev;
           	           
           	 # get previous tsecs
       if(defined($r->{$sensor ."_tsecs"})) {
         $rain_tsecs_prev= $r->{$sensor ."_tsecs"}{VAL};
       } else{
         $rain_tsecs_prev= 0; # 1970-01-01
       }
       
       	$r->{$sensor ."_tsecs"}{TIME} = $tm;
		$r->{$sensor ."_tsecs"}{VAL} = $tsecs;
		$dev->{CHANGED}[$n++] = $sensor . "_tsecs: " . $tsecs;
		
		#TODO there should be a handling for new created devices (rain is existing with a large value for the last day)
		#TODO there should be a handling batterie replacement (rain could not be negativ)
		#TODO is the value "israining" needed?
		
		     # get previous value
       if(defined($r->{$sensor ."_now_value"})) {
         $rain_value_prev= $r->{$sensor ."_now_value"}{VAL};
       } else{
         $rain_value_prev= 0; # 0
       }
       
		$r->{$sensor ."_now_value"}{TIME} = $tm;
		$r->{$sensor ."_now_value"}{VAL} = $current;
		$dev->{CHANGED}[$n++] = $sensor . "_now_value: " . $current;
            
        my $rain_diff = $current - $rain_value_prev;
            
        $r->{$sensor ."_now_diff"}{TIME} = $tm;
		$r->{$sensor ."_now_diff"}{VAL} = $rain_diff;
		$dev->{CHANGED}[$n++] = $sensor . "_now_diff: " . $rain_diff;
       
             # get previous tsecs
       if(defined($r->{$sensor ."_h_start"})) {      
         $rain_h_start= $r->{$sensor ."_h_start"}{VAL};
       } else{      
         $rain_h_start= 0; # 1970-01-01
       }
       
              # get previous tsecs
       if(defined($r->{$sensor ."_d_start"})) {      
         $rain_d_start= $r->{$sensor ."_d_start"}{VAL};
       } else{      
         $rain_d_start= 0; # 1970-01-01
       }
      
       # get previous rain_h_last
       if(defined($r->{$sensor ."_h_last"})) {      
         $rain_h_last= $r->{$sensor ."_h_last"}{VAL};
       } else{      
         $rain_h_last= 0; 
       }
       
       # get previous rain_d_last
       if(defined($r->{$sensor ."_d_last"})) {      
         $rain_d_last= $r->{$sensor ."_d_last"}{VAL};
       } else{      
         $rain_d_last= 0; 
       }
       
              # get previous tsecs
       if(defined($r->{$sensor ."_h_trig_tsecs"})) {      
         $rain_h_trig_tsecs= $r->{$sensor ."_h_trig_tsecs"}{VAL};
       } else{  
         $rain_h_trig_tsecs= 0; # 1970-01-01
       }
       
              # get previous tsecs
       if(defined($r->{$sensor ."_d_trig_tsecs"})) {     
         $rain_d_trig_tsecs= $r->{$sensor ."_d_trig_tsecs"}{VAL};
       } else{
         $rain_d_trig_tsecs= 0; # 1970-01-01
       }
       
    Log3 $hash, 1, "get rain_h_trig IS " . localtime($rain_h_trig_tsecs) if ($rain_debug == 1);
    Log3 $hash, 1, "get rain_d_trig IS " . localtime($rain_d_trig_tsecs) if ($rain_debug == 1);
    
    # look forward to the next hour trigger event
    my @th=localtime($tsecs+1800);
    # time for the hour-trigger (every houre at) 30 min by default
    #my $rain_h_trig=sprintf("%04d-%02d-%02d_%02d:%02d",$th[5]+1900,$th[4]+1,$th[3],$th[2],"30");
    my $rain_h_trig=sprintf("%04d-%02d-%02d_%02d:%02d",$th[5]+1900,$th[4]+1,$th[3],$th[2],$HourChangeTimeMinutes);
    Log3 $hash, 1, "NEW rain_h_trigger would be = $rain_h_trig" if ($rain_debug == 1);

    Log3 $hash, 1, "rain_h_trigger_tsecs = $rain_h_trig_tsecs" if ($rain_debug == 1);
    Log3 $hash, 1, "secunds until hour-reset = " . ($rain_h_trig_tsecs-$tsecs) if ($rain_debug == 1);
    
    if (($rain_h_trig_tsecs-$tsecs)>3600){ # something is wrong
    
	    ### debughelper -->
	    #$DB::single = 1;
    	Log3 $hash, 1, "something is wrong! the diff until next reset should not be greater than one hour. Now set New Trigger" if ($rain_debug == 1);
    	
    	#my @timeData = gmtime(time);
 		#Debug "timeData: ". join(' ', @timeData); 
 		
 		#my @utcData = utcdate(time);
 		#Debug "utcData: ". join(' ', @utcData);

 		#my @gmData = gmtime(time);
 		#Debug "gmData: ". join(' ', @gmData);
    	
    	#TODO should be 5:30 UTC?
    	#$rain_h_trig_tsecs = timelocal(0,30,7,$th[3],$th[4],$th[5]+1900);
    	$rain_h_trig_tsecs = timelocal(0,$DayChangeTimeMinutes,$DayChangeTimeHour,$th[3],$th[4],$th[5]+1900);
    		
    		# remember $rain_d_trig_tsecs     / trigger-time for next event to zero rain
	    $r->{$sensor ."_h_trig_tsecs"}{TIME} = $tm;
	    $r->{$sensor ."_h_trig_tsecs"}{VAL} = "$rain_h_trig_tsecs";
    }
	    
     if($tsecs>$rain_h_trig_tsecs){ # wenn now groesser ist, als der letzte trigger-wert, dann beginnt eine neue einheit
		Log3 $hash, 1, "Detect new rain hour!" if ($rain_debug == 1);
	    Log3 $hash, 1, "NEW rain_h_trigger IS = $rain_h_trig" if ($rain_debug == 1);
	    
	    #$time = timelocal($sec,$min,$hour,$mday,$mon,$year);
	    #$rain_h_trig_tsecs = timelocal(0,30,$th[2],$th[3],$th[4],$th[5]+1900);
	    $rain_h_trig_tsecs = timelocal(0,$HourChangeTimeMinutes,$th[2],$th[3],$th[4],$th[5]+1900);
	    Log3 $hash, 1, "rain_h_trigger_tsecs = $rain_h_trig_tsecs" if ($rain_debug == 1);
	    
		#$rain_h_last = sprintf("%0.1f", ($rain_raw_adj-$rain_raw_h_start) * $def->{RAINUNIT} / 1000);		
		$rain_h_last = sprintf("%0.1f", $current-$rain_h_start);
		    # remember $rain_h_last
	    $r->{$sensor ."_h_last"}{TIME} = $tm;
	    $r->{$sensor ."_h_last"}{VAL} = "$rain_h_last";
	    
	    	# set new rain_raw_hour_start_value
	    $rain_h_start = $current;
	        # remember $rain_raw_h_start
	    $r->{$sensor ."_h_start"}{TIME} = $tm;
	    $r->{$sensor ."_h_start"}{VAL} = "$rain_h_start";
	    
	    	# remember $rain_h_trig_tsecs     / trigger-time for next event to zero rain
	    $r->{$sensor ."_h_trig_tsecs"}{TIME} = $tm;
	    $r->{$sensor ."_h_trig_tsecs"}{VAL} = "$rain_h_trig_tsecs";
	}
	
	# look forward to the next day trigger event
	@th=localtime($tsecs+86400);
    #  the time for the day-trigger:           7:30 Uhr
    #my $rain_d_trig=sprintf("%04d-%02d-%02d_%02d:%02d",$th[5]+1900,$th[4]+1,$th[3],"7","30");
    my $rain_d_trig=sprintf("%04d-%02d-%02d_%02d:%02d",$th[5]+1900,$th[4]+1,$th[3],$DayChangeTimeHour,$DayChangeTimeMinutes);
    Log3 $hash, 1, "NEW rain_d_trigger would be= $rain_d_trig" if ($rain_debug == 1);

    Log3 $hash, 1, "rain_d_trigger_tsecs = $rain_d_trig_tsecs" if ($rain_debug == 1);	    
    Log3 $hash, 1, "secunds until day-reset = " . ($rain_d_trig_tsecs-$tsecs) if ($rain_debug == 1);
    
    if (($rain_d_trig_tsecs-$tsecs)>86400){ # something is wrong
    	Log3 $hash, 1, "something is wrong! the diff until next reset should not be greater than one day. Now set New Trigger" if ($rain_debug == 1);
    	#$rain_d_trig_tsecs = timelocal(0,30,7,$th[3],$th[4],$th[5]+1900);
    	$rain_d_trig_tsecs = timelocal(0,$DayChangeTimeMinutes,$DayChangeTimeHour,$th[3],$th[4],$th[5]+1900);
    		
    		# remember $rain_d_trig_tsecs     / trigger-time for next event to zero rain
	    $r->{$sensor ."_d_trig_tsecs"}{TIME} = $tm;
	    $r->{$sensor ."_d_trig_tsecs"}{VAL} = "$rain_d_trig_tsecs";
    }
	    
	if($tsecs>$rain_d_trig_tsecs){
		
		Log3 $hash, 1, "Detect new rain day!" if ($rain_debug == 1);
		Log3 $hash, 1, "NEW rain_d_trigger IS= $rain_d_trig" if ($rain_debug == 1);
	    
	    #         $time = timelocal($sec,$min,$hour,$mday,$mon,$year);
	    #$rain_d_trig_tsecs = timelocal(0,30,7,$th[3],$th[4],$th[5]+1900);
	    $rain_d_trig_tsecs = timelocal(0,$DayChangeTimeMinutes,$DayChangeTimeHour,$th[3],$th[4],$th[5]+1900);
	    Log3 $hash, 1, "rain_d_trigger_tsecs = $rain_d_trig_tsecs" if ($rain_debug == 1);
	    
		$rain_d_last = sprintf("%0.1f", ($current-$rain_d_start));
			
		    # remember $rain_h_last
	    $r->{$sensor ."_d_last"}{TIME} = $tm;
	    $r->{$sensor ."_d_last"}{VAL} = "$rain_d_last";
	    
	    	# set new rain_raw_day_start_value
	    $rain_d_start=$current;
	        # remember $rain_raw_h_start
	    $r->{$sensor ."_d_start"}{TIME} = $tm;
	    $r->{$sensor ."_d_start"}{VAL} = "$rain_d_start";
		          
	    	# remember $rain_d_trig_tsecs     / trigger-time for next event to zero rain
	    $r->{$sensor ."_d_trig_tsecs"}{TIME} = $tm;
	    $r->{$sensor ."_d_trig_tsecs"}{VAL} = "$rain_d_trig_tsecs";
	    
	}

    $rain_h_curr = sprintf("%0.1f", ($current-$rain_h_start));
	  #remember $rain_raw_h_start
    $r->{$sensor ."_h_curr"}{TIME} = $tm;
    $r->{$sensor ."_h_curr"}{VAL} = $rain_h_curr;
	   
    $rain_d_curr = sprintf("%0.1f", ($current-$rain_d_start));
	  #remember $rain_raw_d_start
    $r->{$sensor ."_d_curr"}{TIME} = $tm;
    $r->{$sensor ."_d_curr"}{VAL} = $rain_d_curr;
    
	Log3 $hash, 1, "Rain Curr h: $rain_h_curr / Rain Last h: $rain_h_last" if ($rain_debug == 1);
	Log3 $hash, 1, "Rain Curr d: $rain_d_curr / Rain Last d: $rain_d_last" if ($rain_debug == 1);
	
    Log3 $hash, 1, "r1(prev) and r2: $rain_value_prev / $current" if ($rain_debug == 1);      

    my $tsecs_dif = $tsecs-$rain_tsecs_prev;
    my $rain_now_rate=0;
    if ($tsecs_dif!=0){
    	$rain_now_rate=sprintf("%0.1f",($current-$rain_value_prev)*3600/$tsecs_dif);	
    }
    
    Log3 $hash, 1, "rdif r2-r1=" . ($current-$rain_value_prev) if ($rain_debug == 1);   
    Log3 $hash, 1, "rain_nowrate (tsec_dif=". ($tsecs_dif) .") $rain_now_rate" if ($rain_debug == 1);    

	 	# remember $rain_d_trig_tsecs     / trigger-time for next event to zero rain
	$r->{$sensor ."_now_rate"}{TIME} = $tm;
	$r->{$sensor ."_now_rate"}{VAL} = "$rain_now_rate";
	    
    # For logging/summary
    my $rain_all = "cH: $rain_h_curr lH: $rain_h_last cD: $rain_d_curr lD: $rain_d_last IR: $israining Rnow: $rain_now_rate Rdif: $rain_diff";
#    Log GetLogLevel($def->{NAME},4), "KS300 $dev: $rain_all" if ($rain_debug == 1);
    Log3 $hash, 1, "$rain_all" if ($rain_debug == 1);
        # remember rain
    $r->{$sensor ."_all"}{TIME} = $tm;
    $r->{$sensor ."_all"}{VAL} = "$rain_all";
    
    #$dev->{STATE} = $val;
    $dev->{CHANGED}[$n++] = $sensor ."_all: $rain_all";


    Log3 $hash, 1, "rain_notify: current=$current" if ($rain_debug == 1);


  return undef;
}


1;


=pod
=begin html

<a name="rain"></a>
<h3>rain</h3>
<ul>
  Rain calculations. Offers different values from a rain sensor. <br>

  <a name="raindefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; rain &lt;devicename-regex&gt; [&lt;rain_name&gt; &lt;israining_name&gt; &lt;new_name&gt;]</code><br>
    <br>
    <ul>
      	Calculates rain values for device &lt;devicename-regex&gt; from incremental rain-value and israining-state
	and write it to some new readings named rain_calc_???????.
	If optional &lt;rain_name&gt;, &lt;israining_name&gt; and &lt;new_name&gt; is specified
	then read rain from reading &lt;rain_name&gt;, israining from reading &lt;israining_name&gt;
	and write the calculated rain to reading &lt;new_name&gt;.
    </ul>
    
    The following values are generated:
    <ul>
	    <li>rain_calc_all      --> all values in one line</li>
	    <li>rain_calc_d_curr   --> liter rain at the current day (from 7:30 local time)</li>
	    <li>rain_calc_d_last   --> liter rain of 24h before 7:30 local time</li>
	    <li>rain_calc_d_start  --> first incremental rain value from the rain device after 7:30 local time</li>
	    <li>rain_calc_h_curr   --> liter rain at the current hour (from XX:30)</li>
	    <li>rain_calc_h_last   --> liter rain of 1 hour before the last XX:30 time</li>
	    <li>rain_calc_h_start  --> first incremental rain value from the rain device after last XX:30</li>
	    <li>rain_calc_now_diff --> fallen rain in liter since last value from rain device</li>
	    <li>rain_calc_now_rate --> fallen rain in liter/hour since last value from rain device</li>
	    
    </ul>

    <br>

    Example:<PRE>
    # Compute the rain for the rain/israining
    # events of the ks300 device and generate reading rain_calc.
    define rain_ks300 rain ks300

    </PRE>
  </ul>

  <a name="rainset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="rainget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="rainattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li>DontUseIsRaining 0/1
    		<br>
    		Don't use the devicevalue IsRaining, if set to 1
    		</li>
    <li>DayChangeTime HHMM
    		<br>
    		Change the default (day)time of the 'set value to zero' time (use the timecode as four digits!)
    		<br>
    		The minutevalue is used to set the (hour)time of the 'set value to zero' time 
    		</li>
    
    <li>CorrectionValue 1
            <br>
            Use this value if you wish to do a correction of the rain-device-values. It is used as an factor. The value 1 will not change anything.
            </li>
    <br>
  </ul>
</ul>


=end html
=cut

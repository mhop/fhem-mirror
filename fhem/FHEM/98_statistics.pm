##############################################
# $Id$
#
#  98_statistic.pm
#
#  Copyright notice
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module computes statistic data of and for readings of other modules
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################
#
# define <name> statistics <regexp>
#
##############################################################################

package main;
use strict;
use warnings;
use Time::Local;

sub statistics_PeriodChange($);
sub statistics_DoStatisticsAll($$);
sub statistics_DoStatistics ($$$);
sub statistics_doStatisticMinMax ($$$$$);
sub statistics_doStatisticMinMaxSingle ($$$$$$$);
sub statistics_doStatisticDelta ($$$$$); 
sub statistics_doStatisticDuration ($$$$); 
sub statistics_doStatisticDurationSingle ($$$$$$); 
sub statistics_storeSingularReadings ($$$$$$$$$$);
sub statistics_getStoredDevices($);
sub statistics_FormatDuration($);

# Modul Version for remote debugging
  my $modulVersion = "2014-05-13";

##############################################################
# Syntax: deviceType, readingName, statisticType, decimalPlaces
#     statisticType: 0=noStatistic | 1=minMaxAvg | 2=delta | 3=stateDuration
##############################################################
  my @knownReadings = ( ["brightness", 1, 0] 
   ,["count", 2, 0] 
   ,["current", 1, 3] 
   ,["energy", 2, 0] 
   ,["energy_current", 1, 1] 
   ,["energy_total", 2, 3] 
   ,["humidity", 1, 0]
   ,["lightsensor", 3, 1] 
   ,["lock", 3, 1] 
   ,["motion", 3, 1] 
   ,["power", 1, 1] 
   ,["rain", 2, 1] 
   ,["rain_rate", 1, 1] 
   ,["rain_total", 2, 1] 
   ,["temperature", 1, 1] 
   ,["total", 2, 2] 
   ,["voltage", 1, 1] 
   ,["wind", 1, 0] 
   ,["wind_speed", 1, 1] 
   ,["windSpeed", 1, 0] 
   ,["Window", 3, 1] 
   ,["window", 3, 1] 
  );
##############################################################

sub ##########################################
statistics_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "statistics_Define";
  $hash->{UndefFn}   = "statistics_Undefine";
  $hash->{NotifyFn}  = "statistics_Notify";
  $hash->{NOTIFYDEV} = "global";
  $hash->{SetFn}     = "statistics_Set";

  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "disable:0,1 "
                   ."dayChangeTime "
                   ."deltaReadings "
                   ."durationReadings "
                   ."excludedReadings "
                   ."minAvgMaxReadings "
                   ."periodChangePreset "
                   ."singularReadings "
                   .$readingFnAttributes;
}

##########################
sub
statistics_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> statistics <devicename-regexp> [prefix]"
    if(3>@a || @a>4);

  my $name = $a[0];
  my $devName = $a[2];

  if (@a == 4) {$hash->{PREFIX} = $a[3];}
  else {$hash->{PREFIX} = "stat";}
 
  eval { "Hallo" =~ m/^$devName$/ };
  return "Bad regexp: $@" if($@);
  $hash->{DEV_REGEXP} = $devName;

  $hash->{STATE} = "Waiting for notifications";

  RemoveInternalTimer($hash);
  
 # Run period change procedure next full hour (15 seconds before).
  my $periodEndTime = 3600 * ( int(gettimeofday()/3600) + 1 ) - 15 ;
  InternalTimer( $periodEndTime, "statistics_PeriodChange", $hash, 0);

  return undef;
}

sub ########################################
statistics_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  return undef;
}

sub ########################################
statistics_Set($$@)
{
  my ($hash, $name, $cmd, $val) = @_;
  my $resultStr = "";
  
   if ($cmd eq 'resetStatistics') {
      if ($val ne "") {
         my $regExp;
         if ($val eq "all") { $regExp = ""; } 
         else { $regExp = $val.":.*"; } 
         foreach (sort keys %{ $hash->{READINGS} }) {
            if ($_ =~ /^\.$regExp/ && $_ ne "state") {
               delete $hash->{READINGS}{$_};
               $resultStr .= "\n * " . substr $_, 1;
            }
         }
      }
      if ( $resultStr eq "" ) {
         $resultStr = "$name: No statistics to reset";
      } else {
         $resultStr = "$name: Statistic value(s) reset:" . $resultStr;
         readingsSingleUpdate($hash,"state","Statistic value(s) reset: $val",1);
      }
      # Log3 $hash, 3, $resultStr;
      return $resultStr;
   
   } elsif ($cmd eq 'doStatistics') {
      statistics_DoStatisticsAll($hash,0);
      return undef;
   }
  my $list = "resetStatistics:all" . statistics_getStoredDevices($hash);
    $list .= " doStatistics:noArg";
  return "Unknown argument $cmd, choose one of $list";
}

sub ########################################
statistics_Notify($$)
{
   my ($hash, $dev) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};

 # At startup: delete old Readings of monitored devices and rebuild from hidden readings 
  if ($devName eq "global" && grep (m/^INITIALIZED|REREADCFG$/,@{$dev->{CHANGED}})) {
     foreach my $r (keys %{$hash->{READINGS}}) {
         if ($r =~ /^monitoredDevices.*/) {
            Log3 $name,5,"$name: Initialization - Delete old reading '$r'.";
            delete($hash->{READINGS}{$r}); 
         }
     }
     statistics_DoStatisticsAll $hash, 0;
     my %unknownDevices;
     foreach my $r (keys %{$hash->{READINGS}}) {
         if ($r =~ /^\.(.*):.*/) { $unknownDevices{$1}++; }
     }
     my $val="";
     foreach my $device (sort (keys(%unknownDevices))) {
        if (not exists ($defs{$device})) {
         if ($val ne "") { $val.=","; }
         $val .= $device;
        }
     }
     if ($val ne "") {
       Log3 $name,4,"$name: Initialization - Found hidden readings for device(s) '$val'.";
       readingsSingleUpdate($hash,"monitoredDevicesUnknownType",$val,1);
     }
     return;
   }
  
 # ignore my own notifications
  if($devName eq $name) {
      Log3 $name,5,"$name: Notifications of myself received.";
      return "" ;
  }
 # Return if the notifying device is not monitored
  return "" if(!defined($hash->{DEV_REGEXP}));
  my $regexp = $hash->{DEV_REGEXP};
  if($devName !~ m/^($regexp)$/) {
      Log3 $name,5,"$name: Notification of '".$dev->{NAME}."' received. Device not monitored.";
      return "" ;
  }

  # Check if it notifies only for the statistic values
   my $prefix = $hash->{PREFIX};
   my $normalReadingFound = 0;
   my $max = int(@{$dev->{CHANGED}});   
   for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      next if(!defined($s));
      if ($s !~ /^$prefix[A-Z]/) { $normalReadingFound = 1;}
   }

   if ($normalReadingFound==1) {
      statistics_DoStatistics $hash, $dev, 0;
      Log3 $name,5,"$name: Notification of '".$dev->{NAME}."' received. Update statistics.";
   } else {
      Log3 $name,5,"$name: Notification of '".$dev->{NAME}."' received but for my own readings only.";
   }
   
   WriteStatefile();
   
   return;
}


sub ########################################
statistics_PeriodChange($)
{
   my ($hash) = @_;
   my $name = $hash->{NAME};
   my $dummy;
   my $val;
   my $periodChangePreset = AttrVal($name, "periodChangePreset", 5);
   my $isDayChange = ( ReadingsVal($name, "nextPeriodChangeCalc", "") =~ /Day Change/ );

  # Determine the next day change time
   my @th=localtime();
   my $dayChangeDelay = 0;
   my $dayChangeTime = timelocal(0,0,0,$th[3],$th[4],$th[5]+1900);
   if (AttrVal($name, "dayChangeTime", "00:00") =~ /(\d+):(\d+)/ && $1<24 && $1 >=0 && $2<60 && $2>=0) {
      $dayChangeDelay = $1 * 3600 + $2 * 60;
      $dayChangeTime += $dayChangeDelay - $periodChangePreset;
   }

   RemoveInternalTimer($hash);
 # Run period change procedure each full hour ("periodChangePreset" second before).
   my $periodEndTime = 3600 * ( int((gettimeofday()+1800)/3600) + 1 ) - $periodChangePreset ;
 # Run procedure also for given dayChangeTime  
   $val = "";
   if ( $dayChangeDelay>0 && gettimeofday()<$dayChangeTime && $dayChangeTime<=$periodEndTime ) {
      $periodEndTime = $dayChangeTime;
      $val = " (Day Change)";
   } 
   $val = strftime ("%Y-%m-%d %H:%M:%S", localtime($periodEndTime)) . $val;
   InternalTimer( $periodEndTime, "statistics_PeriodChange", $hash, 1);
   readingsSingleUpdate($hash, "nextPeriodChangeCalc", $val, 0);
   Log3 $name,4,"$name: Next period change will be calculated at ".strftime ("%H:%M:%S", localtime($periodEndTime));

   return if( AttrVal($name, "disable", 0 ) == 1 );
   
 # Determine if time period switched (day, month, year)
 # Get deltaValue and Tariff of previous call
 
   my $periodSwitch = 0;
   my $yearLast;
   my $monthLast;
   my $dayLast;
   my $hourLast;
   my $hourNow;
   my $dayNow;
   my $monthNow;
   my $yearNow;

   if ($dayChangeDelay>0 && $isDayChange) {
         ($dummy, $dummy, $hourLast, $dayLast, $monthLast, $yearLast) = localtime (gettimeofday() - $dayChangeDelay);
         ($dummy, $dummy, $hourNow, $dayNow, $monthNow, $yearNow) = localtime (gettimeofday() + $periodEndTime);
         if ($yearNow != $yearLast) { $periodSwitch = -4; }
         elsif ($monthNow != $monthLast) { $periodSwitch = -3; }
         elsif ($dayNow != $dayLast) { $periodSwitch = -2; }
         if ($dayChangeDelay % 3600 == 0) { $periodSwitch = abs($periodSwitch); }
   } else {
      ($dummy, $dummy, $hourLast, $dayLast, $monthLast, $yearLast) = localtime (gettimeofday() - 1800);
      ($dummy, $dummy, $hourNow, $dayNow, $monthNow, $yearNow) = localtime (gettimeofday() + 1800);
      if ($yearNow != $yearLast) { $periodSwitch = 4; }
      elsif ($monthNow != $monthLast) { $periodSwitch = 3; }
      elsif ($dayNow != $dayLast) { $periodSwitch = 2; }
      elsif ($hourNow != $hourLast) { $periodSwitch = 1; }
   }

   statistics_DoStatisticsAll $hash, $periodSwitch;

   return undef;
}

##########################
sub
statistics_DoStatisticsAll($$)
{
   my ($hash,$periodSwitch) = @_;
   my $name = $hash->{NAME};
   return "" if(!defined($hash->{DEV_REGEXP}));
   my $regexp = $hash->{DEV_REGEXP};
   foreach my $devName (sort keys %defs) {
     if ($devName ne $name && $devName =~ m/^($regexp)$/) {
         Log3 $name,4,"$name: Doing statistics (type $periodSwitch) for device '$devName'";
         statistics_DoStatistics($hash, $defs{$devName}, $periodSwitch);
      }
   }
}


##########################
sub
statistics_DoStatistics($$$)
{
  my ($hash, $dev, $periodSwitch) = @_;
  my $hashName = $hash->{NAME};
  my $devName = $dev->{NAME};
  my $devType = $dev->{TYPE};
  my $statisticDone = 0;
  
  return "" if(AttrVal($hashName, "disable", undef));

   my $readingName;
   my $exclReadings = AttrVal($hashName, "excludedReadings", "");
   my $regExp = '^'.$devName.'$|^'.$devName.',|,'.$devName.'$|,'.$devName.',';

 # Return if the notifying device is already served by another statistics instance
   if (exists ($dev->{helper}{_98_statistics})) {
      my $servedBy = $dev->{helper}{_98_statistics};
      if ($servedBy ne $hashName) {
         my $monReadingValue = ReadingsVal($hashName,"monitoredDevicesUnserved","");
         if ($monReadingValue !~ /$regExp/) {
            if($monReadingValue eq "") { $monReadingValue = $devName;}
            else {$monReadingValue .= ",".$devName;}
            readingsSingleUpdate($hash,"monitoredDevicesUnserved",$monReadingValue,1);
            Log3 $hashName,3,"$hashName: Device '$devName' identified as supported but already servered by '$servedBy'.";
         }
         return;
      }
   } else {
      $dev->{helper}{_98_statistics}=$hashName;
   }
   
   readingsBeginUpdate($dev);
   
  # Loop through all known device types and readings
   foreach my $f (@knownReadings) 
   {
    # notifing device has known reading, no statistic for excluded readings
      $readingName = $$f[0];
      my $completeReadingName = $devName.":".$readingName;
      next if ($completeReadingName =~ m/^($exclReadings)$/ );
      next if not exists ($dev->{READINGS}{$readingName});
      $statisticDone = 1;
      if ($$f[1] == 1) { statistics_doStatisticMinMax ($hash, $dev, $readingName, $$f[2], $periodSwitch);}
      if ($$f[1] == 2) { statistics_doStatisticDelta ($hash, $dev, $readingName, $$f[2], $periodSwitch);}
      if ($$f[1] == 3) { statistics_doStatisticDuration ($hash, $dev, $readingName, $periodSwitch);}
   }
    
   my @specialReadings = split /,/, AttrVal($hashName, "deltaReadings", "");
   foreach $readingName (@specialReadings) 
   {
      my $completeReadingName = $devName.":".$readingName;
      next if ($completeReadingName =~ m/^($exclReadings)$/ );
      next if not exists ($dev->{READINGS}{$readingName});
      $statisticDone = 1;
      statistics_doStatisticDelta ($hash, $dev, $readingName, 1, $periodSwitch);
   }
   
   @specialReadings = split /,/, AttrVal($hashName, "durationReadings", "");
   foreach $readingName (@specialReadings) 
   {
      my $completeReadingName = $devName.":".$readingName;
      next if ($completeReadingName =~ m/^($exclReadings)$/ );
      next if not exists ($dev->{READINGS}{$readingName});
      $statisticDone = 1;
      statistics_doStatisticDuration ($hash, $dev, $readingName, $periodSwitch);
   }

   @specialReadings = split /,/, AttrVal($hashName, "minAvgMaxReadings", "");
   foreach $readingName (@specialReadings) 
   {
      my $completeReadingName = $devName.":".$readingName;
      next if ($completeReadingName =~ m/^($exclReadings)$/ );
      next if not exists ($dev->{READINGS}{$readingName});
      $statisticDone = 1;
      statistics_doStatisticMinMax ($hash, $dev, $readingName, 1, $periodSwitch);
   }

   if ($statisticDone != 1) { 
      if (exists ($dev->{READINGS}{state})) { 
         statistics_doStatisticDuration $hash, $dev, "state", $periodSwitch;
         $statisticDone = 1;
      }
   }

   if ($periodSwitch >0) {readingsEndUpdate($dev,1);}
   else {readingsEndUpdate($dev,0);}
   

   # Record device as monitored
   my $monReadingName;
   if ($statisticDone == 1) { 
      $monReadingName = "monitoredDevices".$devType; 
      readingsSingleUpdate($hash,"state","Updated stats for: $devName",1);
   } else {
      $monReadingName = "monitoredDevicesUnsupported";
      $devName .= "#$devType";
      $regExp = '^'.$devName.'$|^'.$devName.',|,'.$devName.'$|,'.$devName.',';
   }
   my $monReadingValue = ReadingsVal($hashName,$monReadingName,"");
   if ($monReadingValue !~ /$regExp/) {
      if($monReadingValue eq "") { $monReadingValue = $devName;}
      else {$monReadingValue .= ",".$devName;}
      readingsSingleUpdate($hash,$monReadingName,$monReadingValue,1);

      my $monReadingValue = ReadingsVal($hashName,"monitoredDevicesUnknownType","");
      if ($monReadingValue =~ /$regExp/) {
         $monReadingValue =~ s/$devName,?//;
         $monReadingValue =~ s/,$//;
         if ($monReadingValue ne "") {
            readingsSingleUpdate($hash,"monitoredDevicesUnknownType",$monReadingValue,1);
         } else {
            delete $hash->{READINGS}{monitoredDevicesUnknownType};
         }
      }
   } 

  return undef;
}

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
statistics_doStatisticMinMax ($$$$$) 
{
   my ($hash, $dev, $readingName, $decPlaces, $periodSwitch) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};
   return if not exists ($dev->{READINGS}{$readingName});
  
  # Get reading, cut out first number without units
   my $value = $dev->{READINGS}{$readingName}{VAL};
   $value =~ s/^[\D]*([\d.]*).*/$1/eg;

   Log3 $name, 4, "Calculating min/avg/max statistics for '".$dev->{NAME}.":$readingName = $value'";
  # statistics_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast, decPlaces
  # Daily Statistic
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Day", $value, ($periodSwitch >= 2), $decPlaces;
  # Monthly Statistic 
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Month", $value, ($periodSwitch >= 3), $decPlaces;
  # Yearly Statistic 
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Year", $value, ($periodSwitch == 4), $decPlaces;

   return ;

}

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
statistics_doStatisticMinMaxSingle ($$$$$$$) 
{
   my ($hash, $dev, $readingName, $period, $value, $saveLast, $decPlaces) = @_;
   my $result;
   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName.$period;
   my $name=$hash->{NAME};
   my $devName = $dev->{NAME};
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName).$period;
   my @hidden;
   my @stat;
   my $firstRun = not exists($hash->{READINGS}{$hiddenReadingName});
 
   if ( $firstRun ) { 
  # Show since-Value
      $hidden[1] = 0; $hidden[3] = 0; $hidden[9] = 1;
      $stat[1] = $value; $stat[3] = $value; $stat[5] = $value;
      $stat[7] = strftime ("%Y-%m-%d_%H:%M:%S",localtime()  );
   } else {
  # Do calculations if hidden reading exists
      @hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; # Internal values
      @stat = split / /, $dev->{READINGS}{$statReadingName}{VAL};
      my $timeDiff = int(gettimeofday())-$hidden[7];
      $hidden[1] += $hidden[5] * $timeDiff; # sum
      $hidden[3] += $timeDiff; # time
      if ($value < $stat[1]) { $stat[1]=$value; } # Min
      if ($hidden[3]>0) {$stat[3] = $hidden[1] / $hidden[3];} # Avg
      if ($value > $stat[5]) { $stat[5]=$value; } # Max
   }

  # Prepare new current reading
   $result = sprintf( "Min: %.".$decPlaces."f Avg: %.".$decPlaces."f Max: %.".$decPlaces."f", $stat[1], $stat[3], $stat[5]);
   if ($hidden[9] == 1) { $result .= " (since: $stat[7] )"; }

  # Store current reading as last reading, Reset current reading
   if ($saveLast) { 
      readingsBulkUpdate($dev, $statReadingName . "Last", $result, 1); 
      Log3 $name, 5, "Set '".$statReadingName . "Last'='$result'";
      $hidden[1] = 0; $hidden[3] = 0; $hidden[9] = 0; # No since value anymore
      $result = "Min: $value Avg: $value Max: $value";
   }

  # Store current reading
   readingsBulkUpdate($dev, $statReadingName, $result, 0);
   Log3 $name, 5, "Set '$statReadingName'='$result'";
 
  # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      # statistics_storeSingularReadings $hashName,$singleReading,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$value,$saveLast
      my $statValue = sprintf  "%.".$decPlaces."f", $stat[1];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Min",$period,$statValue,$value,$saveLast);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[3];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Avg",$period,$statValue,$value,$saveLast);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[5];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Max",$period,$statValue,$value,$saveLast);
   }

  # Store hidden reading
   $result = "Sum: $hidden[1] Time: $hidden[3] LastValue: ".$value." LastTime: ".int(gettimeofday())." ShowDate: $hidden[9]";
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   Log3 $name, 5, "Set '$hiddenReadingName'='$result'";

   return;
}

# Calculates deltas for day, month and year
sub ######################################## 
statistics_doStatisticDelta ($$$$$) 
{
   my ($hash, $dev, $readingName, $decPlaces, $periodSwitch) = @_;
   my $dummy;
   my $result;
   my $showDate;
   my $name = $hash->{NAME};
   
   return if not exists ($dev->{READINGS}{$readingName});
   
  # Get reading, cut out first number without units
   my $value = $dev->{READINGS}{$readingName}{VAL};
   $value =~ s/^[\D]*([\d.]*).*/$1/eg;
   Log3 $name, 4, "Calculating delta statistics for '".$dev->{NAME}.":$readingName = $value'";

   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName;
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName);
  
   my @hidden; my @stat; my @last;
   my $firstRun = not exists($hash->{READINGS}{$hiddenReadingName});

   if ( $firstRun ) { 
  # Show since-Value and initialize all readings
      $showDate = 8;
      @stat = split / /, "Hour: 0 Day: 0 Month: 0 Year: 0";
      $stat[9] = strftime ("%Y-%m-%d_%H:%M:%S",localtime()  );
      @last = split / /,  "Hour: - Day: - Month: - Year: -";
      Log3 $name,4,"$name: Initializing statistic of '$hiddenReadingName'.";
   } else {
  # Do calculations if hidden reading exists
      @stat = split / /, $dev->{READINGS}{$statReadingName}{VAL};
      @hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; # Internal values
      $showDate = $hidden[3];
      if (exists ($dev->{READINGS}{$statReadingName."Last"})) { 
         @last = split / /,  $dev->{READINGS}{$statReadingName."Last"}{VAL};
      } else {
         @last = split / /,  "Hour: - Day: - Month: - Year: -";
      }
      my $deltaValue = $value - $hidden[1];
      
    # Do statistic
      $stat[1] += $deltaValue;
      $stat[3] += $deltaValue;
      $stat[5] += $deltaValue;
      $stat[7] += $deltaValue;

    # Determine if "since" value has to be shown in current and last reading
    # If change of year, change yearly statistic
      if ($periodSwitch == 4 || $periodSwitch == -4) {
         $last[7] = sprintf "%.".$decPlaces."f", $stat[7];
         $stat[7] = 0;
         if ($showDate == 1) { $showDate = 0; } # Do not show the "since:" value for year changes anymore
         if ($showDate >= 2) { $showDate = 1; $last[9] = $stat[9]; } # Shows the "since:" value for the first year change
         Log3 $name,4,"$name: Shifting current year in last value of '$statReadingName'.";
      }
    # If change of month, change monthly statistic 
      if ($periodSwitch >= 3 || $periodSwitch <= -3){
         $last[5] = sprintf "%.".$decPlaces."f", $stat[5];
         $stat[5] = 0;
         if ($showDate == 3) { $showDate = 2; } # Do not show the "since:" value for month changes anymore
         if ($showDate >= 4) { $showDate = 3; $last[9] = $stat[9]; } # Shows the "since:" value for the first month change
         Log3 $name,4,"$name: Shifting current month in last value of '$statReadingName'.";
      }
    # If change of day, change daily statistic
      if ($periodSwitch >= 2 || $periodSwitch <= -2){
         $last[3] = $stat[3];
         $stat[3] = 0;
         if ($showDate == 5) { $showDate = 4; } # Do not show the "since:" value for day changes anymore
         if ($showDate >= 6) { # Shows the "since:" value for the first day change
            $showDate = 5; 
            $last[9] = sprintf "%.".$decPlaces."f", $stat[9];
           # Next monthly and yearly values start at 00:00 and show only date (no time)
            $stat[5] = 0;
            $stat[7] = 0;
            $stat[9] = strftime "%Y-%m-%d", localtime(); # start
         } 
         Log3 $name,4,"$name: Shifting current day in last value of '$statReadingName'.";
      }
    # If change of hour, change hourly statistic 
      if ($periodSwitch >= 1){
         $last[1] = sprintf "%.".$decPlaces."f", $stat[1];
         $stat[1] = 0;
         if ($showDate == 7) { $showDate = 6; } # Do not show the "since:" value for day changes anymore
         if ($showDate >= 8) { $showDate = 7; $last[9] = $stat[9]; } # Shows the "since:" value for the first hour change
         Log3 $name,4,"$name: Shifting current hour in last value of '$statReadingName'.";
      }
   }

 # Store visible statistic readings (delta values)
   $result = sprintf "Hour: %.".$decPlaces."f Day: %.".$decPlaces."f Month: %.".$decPlaces."f Year: %.".$decPlaces."f", $stat[1], $stat[3], $stat[5], $stat[7];
   if ( $showDate >=2 ) { $result .= " (since: $stat[9] )"; }
   readingsBulkUpdate($dev,$statReadingName,$result, 1);
   Log3 $name,5,"$name: Set '$statReadingName'='$result'";
   
 # if changed, store previous visible statistic (delta) values
   if ($periodSwitch >= 1) {
      $result = "Hour: $last[1] Day: $last[3] Month: $last[5] Year: $last[7]";
      if ( $showDate =~ /1|3|5|7/ ) { $result .= " (since: $last[9] )"; }
      readingsBulkUpdate($dev,$statReadingName."Last",$result, 1); 
      Log3 $name,4,"$name: Set '".$statReadingName."Last'='$result'";
   }

 # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      # statistics_storeSingularReadings $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast
      my $statValue = sprintf  "%.".$decPlaces."f", $stat[1];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Hour",$statValue,$last[1],$periodSwitch >= 1);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[3];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Day",$statValue,$last[3],$periodSwitch >= 2);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[5];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Month",$statValue,$last[5],$periodSwitch >= 3);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[7];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Year",$statValue,$last[7],$periodSwitch >= 4);
   }
   
  # Store hidden reading
   $result = "LastValue: $value ShowDate: $showDate ";  
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   Log3 $name,5,"$name: Set '$hiddenReadingName'='$result'";

   return ;
}

# Calculates single Duration Values and informs about end of day and month
sub ######################################## 
statistics_doStatisticDuration ($$$$) 
{
   my ($hash, $dev, $readingName, $periodSwitch) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};
   return if not exists ($dev->{READINGS}{$readingName});
  
  # Get reading, cut out first number without units
   my $state = $dev->{READINGS}{$readingName}{VAL};

   Log3 $name, 4, "Calculating duration statistics for '".$dev->{NAME}.":$readingName = $state'";
  # Daily Statistic
   statistics_doStatisticDurationSingle $hash, $dev, $readingName, "Day", $state, ($periodSwitch >= 2);
  # Monthly Statistic 
   statistics_doStatisticDurationSingle $hash, $dev, $readingName, "Month", $state, ($periodSwitch >= 3);

   return ;

}

# Calculates single duration values
sub ######################################## 
statistics_doStatisticDurationSingle ($$$$$$) 
{
   my ($hash, $dev, $readingName, $period, $state, $saveLast) = @_;
   my $result;
   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName.$period;
   my $name=$hash->{NAME};
   my $devName = $dev->{NAME};
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName).$period;
   my %hidden;
   my $firstRun = not exists($hash->{READINGS}{$hiddenReadingName});
   my $lastState = $state;
   my $statValue = "00:00:00";
   
   if ( $firstRun ) { 
  # Show since-Value
      $hidden{"showDate:"} = 1;
      $saveLast = 0;
      # $stat[7] = strftime ("%Y-%m-%d_%H:%M:%S",localtime()  );
   } else {
  # Do calculations if hidden reading exists
      %hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; # Internal values
      $lastState = $hidden{"lastState:"};
      my $timeDiff = int(gettimeofday())-$hidden{"lastTime:"};
      $hidden{$lastState.":"} += $timeDiff;
      $statValue = statistics_FormatDuration ($hidden{$lastState.":"});
   }
   $hidden{"lastState:"} = $state;
   $hidden{"lastTime:"} = int(gettimeofday());

   
  # Prepare new current reading, delete hidden reading if it is used again
   $result = "";
   while (my ($key, $duration) = each(%hidden)){
      if ($key !~ /lastState:|lastTime:|showDate:/) {
         if ($result ne "") {$result .= " ";}
         $result .= "$key ".statistics_FormatDuration($duration); 
         if ($saveLast) { delete $hidden{$key}; }
      }
   }
   if ($result eq "") {$result = "$state: 0";} 
   # if ($hidden[9] == 1) { $result .= " (since: $stat[7] )"; }

  # Store current reading as last reading, Reset current reading
    if ($saveLast) { 
      readingsBulkUpdate($dev, $statReadingName . "Last", $result, 1); 
      Log3 $name, 5, "Set '".$statReadingName . "Last'='$result'";
      $result = "$state: 00:00:00";
      $hidden{"showDate:"} = 0;
   }

  # Store current reading
   readingsBulkUpdate($dev, $statReadingName, $result, 0);
   Log3 $name, 5, "Set '$statReadingName'='$result'";
 
  # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      # statistics_storeSingularReadings $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$value,$saveLast
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,ucfirst($lastState),$period,$statValue,0,$saveLast);
   }

  # Store hidden reading
   $result = "";
   while (my ($key, $duration) = each(%hidden)){
      if ($result ne "") {$result .= " ";}
      $result .= "$key $duration"; 
   }
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   Log3 $name, 5, "Set '$hiddenReadingName = $result'";

   return;
}


sub ####################
statistics_storeSingularReadings ($$$$$$$$$$)
{
   my ($hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast) = @_;
   return if $singularReadings eq "";
   
   if ($statType eq "Delta") { $statReadingName .= $period;}
   else { $statReadingName .= $statType;}
   my $devName=$dev->{NAME};
   if ("$devName:$readingName:$statType:$period" =~ /^($singularReadings)$/) {
      readingsBulkUpdate($dev, $statReadingName, $statValue, 1);
      Log3 $hashName, 5, "Set ".$statReadingName." = $statValue";
      if ($saveLast) {
         readingsBulkUpdate($dev, $statReadingName."Last", $lastValue, 1);
         Log3 $hashName, 5, "Set ".$statReadingName."Last = $lastValue";
      } 
   }
}


sub ####################
statistics_getStoredDevices ($)
{
   my ($hash) = @_;
   my $result="";
   foreach my $r (sort keys %{$hash->{READINGS}}) {
      if ($r =~ /^\.(.*):.*/) { 
         my $device = $1;
         my $regExp = '^'.$1.'$|^'.$1.',|,'.$1.'$|,'.$1.',';
         if ($result !~ /$regExp/) {
            $result.="," . $device;
         }
      }
   }
   return $result;
}

sub ########################################
statistics_FormatDuration($)
{
  my ($value) = @_;
  #Tage
  my $returnstr ="";
  if ($value > 86400) { $returnstr = sprintf "%dd ", int($value/86400); }
  # Stunden
  $value %= 86400;
  $returnstr .= sprintf "%02d:", int($value/3600);
  $value %= 3600;
  $returnstr .= sprintf "%02d:", int($value/60);
  $value %= 60;
  $returnstr .= sprintf "%02d", $value;
  
  return $returnstr;
}

1;

=pod
=begin html

<a name="statistics"></a>
<h3>statistics</h3>
<ul style="width:800px">
  This modul calculates for certain readings of given devices statistical values and adds them to the devices.
  <br>
   Until now statistics for the following readings are automatically built:
   <ul>
      <li><b>Minimal, average  and maximal values:</b> brightness, current, humidity, temperature, voltage, wind, windSpeed</li>
      <li><b>Delta values:</b> count, energy, power, total, rain, rain_total</li>
      <li><b>Duration of states:</b> Window, state <i>(if no other reading is valid)</i></li>
   </ul> 
   Further readings can be added via the correspondent <a href="#statisticsattr">attribut</a>.
  <br>&nbsp;
  <br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; statistics &lt;deviceNameRegExp&gt; [Prefix]</code>
    <br>
    Beispiel: <code>define Statistik statistics Sensor_.*|Wettersensor</code>
    <br>&nbsp;
    <li><code>[Prefix]</code>
      <br>
      Optional. Prefix set is place before statistical data. Default is <i>stat</i>
    </li><br>
    <li><code>&lt;DeviceNameRegExp&gt;</code>
      <br>
      Regular expression of device names. !!! Not the device readings !!!
      <br>
    </li>
  </ul>
  
  <br>
  <b>Set</b>
   <ul>not implemented yet
  </ul>
  <br>

  <b>Get</b>
   <ul>not implemented yet
  </ul>
  <br>

  <a name="statisticsattr"></a>
   <b>Attributes</b>
   <ul>
    <li><code>dayChangeTime &lt;Zeit&gt;</code>
      <br>
      Time of day change. Default is 00:00. For weather data the day change is e.g. 06:50. 
      <br>
    </li><br>
    <li><code>deltaReadings &lt;Ger&auml;tewerte&gt;</code>
      <br>
      Comma separated list of reading names for which a delta statistic shall be calculated. 
    </li><br>
    <li><code>durationReadings &lt;Ger&auml;tewerte&gt;</code>
      <br>
      Comma separated list of reading names for which a duration statistic shall be calculated. 
    </li><br>
    <li><code>excludedReadings <code>&lt;DeviceRegExp:ReadingNameRegExp&gt;</code></code>
      <br>
      Regular expression of the readings that shall be excluded from the statistics.<br>
      The reading have to be entered in the form <i>deviceName:readingName</i>. E.g. "FritzDect:current|Sensor_.*:humidity"
      <br>
    </li><br>
    <li><code>minAvgMaxReadings &lt;Ger&auml;tewerte&gt;</code>
      <br>
      Comma separated list of reading names for which a min/average/max statistic shall be   calculated. 
    </li><br>
    <li><code>periodChangePreset &lt;Sekunden&gt;</code>
      <br>
      Start of the calculation of periodical data, default is 5 Sekunden before each full hour,
      <br>
      Allows the correct timely assignment within plots, can be adapted to the cpu load.
      <br>
    </li><br>
    <li><code>singularReadings &lt;DeviceRegExp:ReadingRegExp&gt;:statTypes<i>(Min|Avg|Max|Delta)</i>:period<i>(Hour|Day|Month|Year)</i></code>
      <br>
      Regulare expression of statistic values, which shall not be shown in summary but also in singular readings. Eases the creation of plots.
      <br>
      z.B. <code>Wettersensor:rain:Delta:(Hour|Day))|(FritzDect:(current|power):(Avg|Max|Delta):(Hour|Day)</code>
      <br>
    </li><br>
   </ul>
</ul>

=end html

=begin html_DE

<a name="statistics"></a>
<h3>statistics</h3>
<ul style="width:800px">
  Dieses Modul wertet von den angegebenen Ger&auml;ten (als regul&auml;rer Ausdruck) bestimmte Werte statistisch aus und f&uuml;gt das Ergebnis den jeweiligen Ger&auml;ten als neue Werte hinzu.
  <br>
  Derzeit werden Statistiken f&uuml;r folgende Ger&auml;tewerte vom Modul automatisch berechnet:
   <ul>
      <li><b>Minimal-, Mittel- und Maximalwerte:</b> brightness, current, humidity, temperature, voltage, wind, windSpeed</li>
      <li><b>Deltawerte:</b> count, energy, power, total, rain, rain_total</li>
      <li><b>Dauer der Stati:</b> Window, state <i>(wenn kein anderer Ger&auml;tewert g&uuml;ltig)</i></li>
  </ul>
  Weitere Ger&auml;tewerte k&ouml;nnen &uuml;ber die entsprechenden <a href="#statisticsattr">Attribute</a> hinzugef&uuml;gt werden
  <br>&nbsp;
  <br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;Name&gt; statistics &lt;Ger&auml;teNameRegExp&gt; [Prefix]</code>
    <br>
    Beispiel: <code>define Statistik statistics Sensor_.*|Wettersensor</code>
    <br>&nbsp;
    <li><code>&lt;Ger&auml;teNameRegExp&gt;</code>
      <br>
      Regul&auml;rer Ausdruck f&uuml;r den Ger&auml;tenamen. !!! Nicht die Ger&auml;tewerte !!!
    </li><br>
    <li><code>[Prefix]</code>
      <br>
      Optional. Der Prefix wird vor den Namen der statistischen Ger&auml;tewerte gesetzt. Standardm&auml;ssig <i>stat</i>
    </li><br>
  </ul>
  
  <br>
  <b>Set</b>
   <ul>
      <li><code>resetStatistics &lt;All|Ger&auml;tename&gt;</code>
      <br>
      Setzt die Statistiken der ausgew&auml;hlten Ger&auml;te zur&uuml;ck
      <br></li>
  </ul>
  <br>

  <b>Get</b>
   <ul>nicht implementiert
  </ul>
  <br>

  <a name="statisticsattr"></a>
   <b>Attributes</b>
   <ul>
    <li><code>dayChangeTime &lt;Zeit&gt;</code>
      <br>
      Uhrzeit des Tageswechsels. Standardm&auml;ssig 00:00. Bei Wetterdaten erfolgt der Tageswechsel z.B. 6:50. 
      <br>
    </li><br>
    <li><code>deltaReadings &lt;Ger&auml;tewerte&gt;</code>
      <br>
      Durch Kommas getrennte Liste von Ger&auml;tewerten 
    </li><br>
    <li><code>durationReadings &lt;Ger&auml;tewerte&gt;</code>
      <br>
      Durch Kommas getrennte Liste von Ger&auml;tewerten 
    </li><br>
    <li><code>excludedReadings &lt;Ger&auml;tenameRegExp:Ger&auml;tewertRegExp&gt;</code>
      <br>
      regul&auml;rer Ausdruck der Ger&auml;tewerte die nicht ausgewertet werden sollen.
      z.B. "FritzDect:current|Sensor_.*:humidity"
      <br>
    </li><br>
    <li><code>minAvgMaxReadings &lt;Ger&auml;tewerte&gt;</code>
      <br>
      Durch Kommas getrennte Liste von Ger&auml;tewerten 
    </li><br>
    <li><code>periodChangePreset &lt;Sekunden&gt;</code>
      <br>
      Start der Berechnung der periodischen Daten, standardm&auml;ssig 5 Sekunden vor der vollen Stunde,
      <br>
      Erlaubt die korrekte zeitliche Zuordnung in Plots, kann je nach Systemauslastung verringert oder vergr&ouml;&szlig;ert werden
      <br>
    </li><br>
    <li><code>singularReadings &lt;Ger&auml;tenameRegExp:Ger&auml;tewertRegExp&gt;:Statistiktypen<i>(Min|Avg|Max|Delta)</i>:ZeitPeriode<i>(Hour|Day|Month|Year)</i></code>
      <br>
      Regul&auml;rer Ausdruck statistischer Werte, die nicht nur in zusammengefassten sondern auch als einzelne Werte gespeichert werden sollen.
      Erleichtert die Erzeugung von Plots. 
      <br>
      z.B. <code>Wettersensor:rain:Delta:(Hour|Day))|(FritzDect:(current|power):(Avg|Max|Delta):(Hour|Day)</code>
      <br>
    </li><br>
    <li><a href="#readingFnAttributes">readingFnAttributes</a>
    </li><br>
   </ul>
</ul>

=end html_DE

=cut
##############################################
# $Id$
#
#  98_statistic.pm
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#
#  This module computes statistic data of and for readings of other modules
#
#  Copyright notice
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
sub statistics_doStatisticMinMaxSingle ($$$$$$);
sub statistics_doStatisticTendency ($$$);
sub statistics_doStatisticDelta ($$$$); 
sub statistics_doStatisticDuration ($$$$); 
sub statistics_doStatisticDurationSingle ($$$$$$); 
sub statistics_storeSingularReadings ($$$$$$$$$$);
sub statistics_getStoredDevices($);
sub statistics_FormatDuration($);
sub statistics_maxDecPlaces($$);
sub statistics_UpdateDevReading($$$$);

# Modul Version for remote debugging
  my $MODUL        = "statistics";

##############################################################
# Syntax: readingName => statisticType
#     statisticType: 0=noStatistic | 1=minMaxAvg(daily) | 2=delta | 3=stateDuration | 4=tendency | 5=minMaxAvg(hourly)
##############################################################
  my %knownReadings = ( 
    "brightness" => 1 
   ,"count" => 2 
   ,"current" => 1 
   ,"energy" => 2 
   ,"energy_current" => 1 
   ,"energy_total" => 2 
   ,"energyCalc" => 2 
   ,"Total.Energy" => 2 
   ,"humidity" => 1
   ,"lightsensor" => 3 
   ,"lock" => 3 
   ,"motion" => 3 
   ,"power" => 1 
   ,"pressure" => 4 
   ,"rain" => 2 
   ,"rain_rate" => 1 
   ,"rain_total" => 2 
   ,"temperature" => 1 
   ,"total" => 2 
   ,"voltage" => 1 
   ,"wind" => 5 
   ,"wind_speed" => 5 
   ,"windSpeed" => 5 
   ,"Window" => 3 
   ,"window" => 3 
  );

##############################################################
# Syntax: attributeName => statisticType
#     statisticType: 0=noStatistic | 1=minMaxAvg(daily) | 2=delta | 3=stateDuration | 4=tendency | 5=minMaxAvg(hourly)
##############################################################
   my %addedReadingsAttr = (
      "deltaReadings" => 2
     ,"durationReadings" => 3
     ,"minAvgMaxReadings" => 5
     ,"tendencyReadings" => 4
   );

##############################################################

##########################################
sub statistics_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/statistics_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

##########################################
sub statistics_Initialize($)
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
                   ."ignoreDefaultAssignments:0,1 "
                   ."minAvgMaxReadings "
                   ."periodChangePreset "
                   ."specialDeltaPeriodHours "
                   ."specialPeriod "
                   ."singularReadings "
                   ."tendencyReadings "
                   .$readingFnAttributes;
}

##########################
sub statistics_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> statistics <devicename-regexp> [prefix]"
    if(@a<3 || @a>4);

  my $name = $a[0];
  my $devName = $a[2];

  if (@a == 4) {$hash->{PREFIX} = $a[3];}
  else {$hash->{PREFIX} = "stat";}
 
  eval { "Hallo" =~ m/^$devName$/ };
  return "Bad regexp: $@" if($@);
  $hash->{DEV_REGEXP} = $devName;

  $hash->{STATE} = "Waiting for notifications";
  $hash->{fhem}{modulVersion} = '$Date$';

  RemoveInternalTimer($hash);
  
  InternalTimer( gettimeofday() + 11, "statistics_PeriodChange", $hash, 0);

  return undef;
}

########################################
sub statistics_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  return undef;
}

########################################
sub statistics_Set($$@)
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
      # statistics_Log $hash, 3, $resultStr;
      return $resultStr;
   
   } elsif ($cmd eq 'doStatistics') {
      statistics_DoStatisticsAll($hash,0);
      return undef;
   }
  my $list = "resetStatistics:all" . statistics_getStoredDevices($hash);
    $list .= " doStatistics:noArg";
  return "Unknown argument $cmd, choose one of $list";
}

########################################
sub statistics_Notify($$)
{
   my ($hash, $dev) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};

 # At startup: delete old Readings of monitored devices and rebuild from hidden readings 
  if ($devName eq "global" && grep (m/^INITIALIZED|REREADCFG$/,@{$dev->{CHANGED}})) {
     foreach my $r (keys %{$hash->{READINGS}}) {
         if ($r =~ /^monitoredDevices.*/) {
            statistics_Log $hash,5,"Initialization - Delete old reading '$r'.";
            delete($hash->{READINGS}{$r}); 
         }
     }
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
       statistics_Log $hash, 4, "Initialization - Found hidden readings for device(s) '$val'.";
       readingsSingleUpdate($hash,"monitoredDevicesUnknown",$val,1);
     }
     return;
   }
  
 # Ignore my own notifications
  if($devName eq $name) {
      statistics_Log $hash, 5, "Notifications of myself received.";
      return "" ;
  }
 # Return if the notifying device is not monitored
  return "" if(!defined($hash->{DEV_REGEXP}));
  my $regexp = $hash->{DEV_REGEXP};
  if($devName !~ m/^($regexp)$/) {
      statistics_Log $hash, 5, "Notification of '".$dev->{NAME}."' received. Device not monitored.";
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
      statistics_Log $hash, 5, "Notification of '".$dev->{NAME}."' received. Update statistics.";
   } else {
      statistics_Log $hash, 5, "Notification of '".$dev->{NAME}."' received but for my own readings only.";
   }
   
   return;
}

########################################
sub statistics_PeriodChange($)
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
      if ($dayChangeDelay == 0) { $dayChangeTime += 24*3600; } # Otherwise it would always lay in the past
      $dayChangeTime += $dayChangeDelay - $periodChangePreset;
   }

   RemoveInternalTimer($hash);
 # Run period change procedure each full hour ("periodChangePreset" second before).
   my $periodEndTime = 3600 * ( int((gettimeofday()+$periodChangePreset)/3600) + 1 ) - $periodChangePreset ;
 # Run procedure also for given dayChangeTime  
   $val = "";
   if ( gettimeofday()<$dayChangeTime && $dayChangeTime<=$periodEndTime ) {
      $periodEndTime = $dayChangeTime;
      $val = " (Day Change)";
   } 
   $val = strftime ("%Y-%m-%d %H:%M:%S", localtime($periodEndTime)) . $val;
   InternalTimer( $periodEndTime, "statistics_PeriodChange", $hash, 1);
   readingsSingleUpdate($hash, "nextPeriodChangeCalc", $val, 0);
   statistics_Log $hash, 4, "Next period change will be calculated at $val";

   return if( AttrVal($name, "disable", 0 ) == 1 );
   
 # Determine if time period switched (day, month, year)
 
   my $periodSwitch = 0;
   my $yearLast;
   my $monthLast;
   my $dayLast;
   my $hourLast;
   my $hourNow;
   my $dayNow;
   my $monthNow;
   my $yearNow;

   if ($isDayChange) {
      statistics_Log $hash, 4, "Calculating day change";
      ($dummy, $dummy, $hourLast, $dayLast, $monthLast, $yearLast) = localtime (gettimeofday() - $dayChangeDelay + $periodChangePreset - 59);
      ($dummy, $dummy, $hourNow, $dayNow, $monthNow, $yearNow) = localtime (gettimeofday() + $periodChangePreset);
      if ($yearNow != $yearLast) { $periodSwitch = -4; }
      elsif ($monthNow != $monthLast) { $periodSwitch = -3; }
      elsif ($dayNow != $dayLast) { $periodSwitch = -2; }
      if ($dayChangeDelay % 3600 == 0) { $periodSwitch = abs($periodSwitch); }
   } else {
      ($dummy, $dummy, $hourLast, $dummy, $dummy, $dummy) = localtime (gettimeofday());
      ($dummy, $dummy, $hourNow, $dummy, $dummy, $dummy) = localtime (gettimeofday() + $periodChangePreset);
      if ($hourNow != $hourLast) { 
         $periodSwitch = 1; 
         statistics_Log $hash,4,"Calculating hour change";
      } else {
         statistics_Log $hash,4,"Calculating statistics at startup";
      }
   }

   statistics_DoStatisticsAll $hash, $periodSwitch;

   return undef;
}

##########################
# Take each notified reading and perform the calculation
sub statistics_DoStatisticsAll($$)
{
   my ($hash,$periodSwitch) = @_;
   my $name = $hash->{NAME};
   return "" if(!defined($hash->{DEV_REGEXP}));
   my $regexp = $hash->{DEV_REGEXP};
   foreach my $devName (sort keys %defs) {
     if ($devName ne $name && $devName =~ m/^($regexp)$/) {
         statistics_Log $hash,4,"Doing statistics (period $periodSwitch) for device '$devName'";
         statistics_DoStatistics($hash, $defs{$devName}, $periodSwitch);
      }
   }
   
   if ($periodSwitch != 0 ) { WriteStatefile(); }
}

##########################
sub statistics_DoStatistics($$$)
{
   my ($hash, $dev, $periodSwitch) = @_;
   my $hashName = $hash->{NAME};
   my $devName = $dev->{NAME};
   my $devType = $dev->{TYPE};
   my $statisticDone = 0;
   my %statReadings = ();
  
   return if( AttrVal($hashName, "disable", 0 ) == 1 );

   my $ignoreDefAssign = AttrVal($hashName, "ignoreDefaultAssignments", 0);
   my $exclReadings = AttrVal($hashName, "excludedReadings", "");
   my $regExp = '^'.$devName.'$|^'.$devName.',|,'.$devName.'$|,'.$devName.',';

 # Return if the notifying device is already served by another statistics instance with same prefix
   my $instanceMarker = "_98_statistics_".$hash->{PREFIX};
   if (exists ($dev->{helper}{$instanceMarker})) {
      my $servedBy = $dev->{helper}{$instanceMarker};
      if ($servedBy ne $hashName) {
         my $monReadingValue = ReadingsVal($hashName,"monitoredDevicesUnserved","");
         if ($monReadingValue !~ /$regExp/) {
            if($monReadingValue eq "") { $monReadingValue = $devName;}
            else {$monReadingValue .= ",".$devName;}
            readingsSingleUpdate($hash,"monitoredDevicesUnserved",$monReadingValue,1);
            statistics_Log $hash, 3, "Device '$devName' identified as supported but already servered by '$servedBy' with some reading prefix.";
         }
         return;
      }
   } else {
      $dev->{helper}{_98_statistics}=$hashName;
   }
   
# Build up Statistic-Reading-Hash, add readings defined in attributes to Statistic-Reading-Hash
   %statReadings = %knownReadings
      unless $ignoreDefAssign == 1;
   while (my ($aName, $statType) = each (%addedReadingsAttr) )
   {
      my @addedReadings = split /,/, AttrVal($hashName, $aName, "");
      foreach( @addedReadings )
      {
             statistics_Log $hash, 5, "Assigned reading '$_' from attribute '$aName' to statistic type $statType.";
             $statReadings{$_} = $statType;
      }
   }

   readingsBeginUpdate($dev);
   
# Loop through Statistic-Reading-Hash and start statistic calculation if the readings exists in the notifying device
   while ( my ($rName, $statType) = each (%statReadings) ) 
   {
    # notifing device has known reading, no statistic for excluded readings
      my $completeReadingName = $devName.":".$rName;
      next if ($completeReadingName =~ m/^($exclReadings)$/ );
      next if not exists ($dev->{READINGS}{$rName});
      
      if ($statType == 1) { statistics_doStatisticMinMax ( $hash, $dev, $rName, $periodSwitch, 0 );}
      elsif ($statType == 2) { statistics_doStatisticDelta ( $hash, $dev, $rName, $periodSwitch );}
      elsif ($statType == 3) { statistics_doStatisticDuration ( $hash, $dev, $rName, $periodSwitch ); }
      elsif ($statType == 4 && $periodSwitch>=1) { statistics_doStatisticTendency ( $hash, $dev, $rName );}
      elsif ($statType == 5) { statistics_doStatisticMinMax ( $hash, $dev, $rName, $periodSwitch, 1 );}
      $statisticDone = 1;
   }
       
# If no statistic-reading has been found, do a duration stat for the device-state
   if ($statisticDone != 1 && $ignoreDefAssign != 1)
   {
      if ( exists ($dev->{READINGS}{state}) && $dev->{READINGS}{state}{VAL} ne "defined" ) { 
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

# Calculates Min/Average/Max Values
########################################
sub statistics_doStatisticMinMax ($$$$$) 
{
   my ($hash, $dev, $readingName, $periodSwitch, $doHourly) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};
   return if not exists ($dev->{READINGS}{$readingName});
  
  # Get reading, cut out first number without units
   my $value = $dev->{READINGS}{$readingName}{VAL};
   $value =~ s/\s*(-?[\d.]*).*/$1/e;

   statistics_Log $hash, 4, "Calculating min/avg/max statistics for '".$dev->{NAME}.":$readingName = $value'";
  # statistics_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast
  # Hourly statistic (if needed)
   if ($doHourly) { statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Hour", $value, ($periodSwitch != 0); }
  # Daily statistic
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Day", $value, ( $periodSwitch >= 2 || $periodSwitch <= -2 );
  # Monthly statistic 
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Month", $value, ( $periodSwitch >= 3 || $periodSwitch <= -3 );
  # Yearly statistic 
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName, "Year", $value, ( $periodSwitch == 4 || $periodSwitch == -4 );

   return ;

}

# Calculates single MaxMin Values and informs about end of day and month
######################################## 
sub statistics_doStatisticMinMaxSingle ($$$$$$) 
{
   my ($hash, $dev, $readingName, $period, $value, $saveLast) = @_;
   my $result;
   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName.$period;
   my $name=$hash->{NAME};
   my $devName = $dev->{NAME};
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName).$period;
   my @hidden;
   my @stat;
   my $lastValue;
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
   
   my $decPlaces = statistics_maxDecPlaces($value, $hidden[11]);

  # Prepare new current reading
   $result = sprintf( "Min: %.".$decPlaces."f Avg: %.".$decPlaces."f Max: %.".$decPlaces."f", $stat[1], $stat[3], $stat[5]);
   if ($hidden[9] == 1) { $result .= " (since: $stat[7] )"; }

  # Store current reading as last reading, Reset current reading
   if ($saveLast) {      
      readingsBulkUpdate($dev, $statReadingName . "Last", $result, 1); 
      statistics_Log $hash, 4, "Set '".$statReadingName . "Last'='$result'";
      $hidden[1] = 0; $hidden[3] = 0; $hidden[9] = 0; # No since value anymore
      $result = "Min: $value Avg: $value Max: $value";
   }

  # Store current reading
   readingsBulkUpdate($dev, $statReadingName, $result, 0);
   statistics_Log $hash, 5, "Set '$statReadingName'='$result'";
 
  # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      # statistics_storeSingularReadings $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast
      my $statValue = sprintf  "%.".$decPlaces."f", $stat[1];
      if ($saveLast) { $lastValue = $statValue; $statValue = $value; }
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Min",$period,$statValue,$lastValue,$saveLast);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[3];
      if ($saveLast) { $lastValue = $statValue; $statValue = $value; }
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Avg",$period,$statValue,$lastValue,$saveLast);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[5];
      if ($saveLast) { $lastValue = $statValue; $statValue = $value; }
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Max",$period,$statValue,$lastValue,$saveLast);
   }

  # Store hidden reading
   $result = "Sum: $hidden[1] Time: $hidden[3] LastValue: ".$value." LastTime: ".int(gettimeofday())." ShowDate: $hidden[9] DecPlaces: $decPlaces";
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   statistics_Log $hash, 5, "Set '$hiddenReadingName'='$result'";

   return;
}

# Calculates tendency values 
######################################## 
sub statistics_doStatisticTendency ($$$) 
{
   my ($hash, $dev, $readingName) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};
   my $decPlaces = 0;
   return if not exists ($dev->{READINGS}{$readingName});
   
  # Get reading, cut out first number without units
   my $value = $dev->{READINGS}{$readingName}{VAL};
   $value =~ s/\s*(-?[\d.]*).*/$1/e;
   statistics_Log $hash, 4, "Calculating hourly tendency statistics for '".$dev->{NAME}.":$readingName = $value'";

   my $statReadingName = $hash->{PREFIX} . ucfirst($readingName) . "Tendency";
   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName."Tendency";
  
   my @hidden; my @stat;
   my $firstRun = not exists($hash->{READINGS}{$hiddenReadingName});

   if ( $firstRun ) { 
      @stat = split / /, "1h: - 2h: - 3h: - 6h: -";
      statistics_Log $hash,4,"Initializing statistic of '$hiddenReadingName'.";
      $hash->{READINGS}{$hiddenReadingName}{VAL} = "";
    } else {
      @stat = split / /, $dev->{READINGS}{$statReadingName}{VAL};
   }

   my $result = $value;
   statistics_Log $hash, 4, "Add $value to $hiddenReadingName";
   if (exists ($hash->{READINGS}{$hiddenReadingName}{VAL})) { $result .= " " . $hash->{READINGS}{$hiddenReadingName}{VAL}; }
   @hidden = split / /, $result; # Internal values

# determine decPlaces with stored values
   foreach (@hidden)
   {
      $decPlaces = statistics_maxDecPlaces($_, $decPlaces);
   }
   
   if ( exists($hidden[7]) ) { 
      statistics_Log $hash, 4, "Remove last value ".$hidden[7]." from '$hiddenReadingName'";
      delete $hidden[7]; 
   }
   if ( exists($hidden[1]) ) {$stat[1] = sprintf "%+.".$decPlaces."f", $value-$hidden[1];}
   if ( exists($hidden[2]) ) {$stat[3] = sprintf "%+.".$decPlaces."f", $value-$hidden[2];}
   if ( exists($hidden[3]) ) {$stat[5] = sprintf "%+.".$decPlaces."f", $value-$hidden[3];}
   if ( exists($hidden[6]) ) {$stat[7] = sprintf "%+.".$decPlaces."f", $value-$hidden[6];}

   $result = "1h: " . $stat[1] ." 2h: ". $stat[3] ." 3h: ". $stat[5] ." 6h: ". $stat[7];
   readingsBulkUpdate($dev, $statReadingName, $result, 1);

  # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      # statistics_storeSingularReadings $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Tendency","1h",$stat[1],0,0);
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Tendency","2h",$stat[1],0,0);
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Tendency","3h",$stat[1],0,0);
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Tendency","6h",$stat[1],0,0);
   }

   $result = join( " ", @hidden );
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   statistics_Log $hash, 4, "Set '$hiddenReadingName = $result'";
   
   return ;
}

# Calculates deltas for day, month and year
######################################## 
sub statistics_doStatisticDelta ($$$$) 
{
   my ($hash, $dev, $readingName, $periodSwitch) = @_;
   my $dummy;
   my $result;
   my $showDate;
   my $name = $hash->{NAME};
   my $decPlaces = 0;
   return if not exists ($dev->{READINGS}{$readingName});

   
  # Get reading, extract first number without units
   my $value = $dev->{READINGS}{$readingName}{VAL};
   $value =~ s/\s*(-?[\d.]*).*/$1/e;
   statistics_Log $hash, 4, "Calculating delta statistics for '".$dev->{NAME}.":$readingName = $value'";

   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName;
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName);
  
   my @hidden; my @stat; my @last;
   my $firstRun = not exists($hash->{READINGS}{$hiddenReadingName});

  # Show since-Value and initialize all readings
   if ( $firstRun ) { 
      $showDate = 8;
      @stat = split / /, "Hour: 0 Day: 0 Month: 0 Year: 0";
      $stat[9] = strftime "%Y-%m-%d_%H:%M:%S", localtime();
      @last = split / /,  "Hour: - Day: - Month: - Year: -";
      statistics_Log $hash, 4, "Initializing statistic of '$hiddenReadingName'.";
   } 
  # Do calculations if hidden reading exists
   else {
      @stat = split / /, $dev->{READINGS}{$statReadingName}{VAL};
      @hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; # Internal values
      $showDate = $hidden[3];
      $decPlaces = statistics_maxDecPlaces($value, $hidden[5]);
      if (exists ($dev->{READINGS}{$statReadingName."Last"})) { 
         @last = split / /,  $dev->{READINGS}{$statReadingName."Last"}{VAL};
      } 
      else {
         @last = split / /,  "Hour: - Day: - Month: - Year: -";
      }
      my $deltaValue = $value - $hidden[1];
      
    # Do statistic
      $stat[1] += $deltaValue;
      $stat[3] += $deltaValue;
      $stat[5] += $deltaValue;
      $stat[7] += $deltaValue;

   if ($periodSwitch>=1) { statistics_doStatisticSpecialPeriod ( $hash, $dev, $readingName, $decPlaces, $stat[1] ); }

    # Determine if "since" value has to be shown in current and last reading
    # If change of year, change yearly statistic
      if ($periodSwitch == 4 || $periodSwitch == -4) {
         $last[7] = sprintf "%.".$decPlaces."f", $stat[7];
         $stat[7] = 0;
         if ($showDate == 1) { $showDate = 0; } # Do not show the "since:" value for year changes anymore
         if ($showDate >= 2) { $showDate = 1; $last[9] = $stat[9]; } # Shows the "since:" value for the first year change
         statistics_Log $hash, 4, "Shifting current year in last value of '$statReadingName'.";
      }
    # If change of month, change monthly statistic 
      if ($periodSwitch >= 3 || $periodSwitch <= -3){
         $last[5] = sprintf "%.".$decPlaces."f", $stat[5];
         $stat[5] = 0;
         if ($showDate == 3) { $showDate = 2; } # Do not show the "since:" value for month changes anymore
         if ($showDate >= 4) { $showDate = 3; $last[9] = $stat[9]; } # Shows the "since:" value for the first month change
         statistics_Log $hash, 4, "Shifting current month in last value of '$statReadingName'.";
      }
    # If change of day, change daily statistic
      if ($periodSwitch >= 2 || $periodSwitch <= -2){
         $last[3] = sprintf "%.".$decPlaces."f", $stat[3];
         $stat[3] = 0;
         if ($showDate == 5) { $showDate = 4; } # Do not show the "since:" value for day changes anymore
         if ($showDate >= 6) { # Shows the "since:" value for the first day change
            $showDate = 5; 
            $last[9] = $stat[9];
           # Next monthly and yearly values start normaly at 00:00 and show only date (no time)
            if (AttrVal($name, "dayChangeTime", "00:00") =~ /00:00|0:00/) {
               my $periodChangePreset = AttrVal($name, "periodChangePreset", 5);
               $stat[5] = 0;
               $stat[7] = 0;
               $stat[9] = strftime "%Y-%m-%d", localtime(gettimeofday()+$periodChangePreset); # start
            }
         } 
         statistics_Log $hash,4,"Shifting current day in last value of '$statReadingName'.";
      }
    # If change of hour, change hourly statistic 
      if ($periodSwitch >= 1){
         $last[1] = sprintf "%.".$decPlaces."f", $stat[1];
         $stat[1] = 0;
         if ($showDate == 7) { $showDate = 6; } # Do not show the "since:" value for day changes anymore
         if ($showDate >= 8) { $showDate = 7; $last[9] = $stat[9]; } # Shows the "since:" value for the first hour change
         statistics_Log $hash, 4, "Shifting current hour in last value of '$statReadingName'.";
      }
   }

  # Store hidden reading
   $result = "LastValue: $value ShowDate: $showDate DecPlaces: $decPlaces";  
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   statistics_Log $hash, 5, "Set '$hiddenReadingName'='$result'";

 # Store visible statistic readings (delta values)
   $result = sprintf "Hour: %.".$decPlaces."f Day: %.".$decPlaces."f Month: %.".$decPlaces."f Year: %.".$decPlaces."f", $stat[1], $stat[3], $stat[5], $stat[7];
   if ( $showDate >=2 ) { $result .= " (since: $stat[9] )"; }
   readingsBulkUpdate($dev,$statReadingName,$result, 1);
   statistics_Log $hash, 5, "Set '$statReadingName'='$result'";
   
 # if changed, store previous visible statistic (delta) values
   if ($periodSwitch != 0) {
      $result = "Hour: $last[1] Day: $last[3] Month: $last[5] Year: $last[7]";
      if ( $showDate =~ /1|3|5|7/ ) { $result .= " (since: $last[9] )"; }
      readingsBulkUpdate($dev,$statReadingName."Last",$result, 1); 
      statistics_Log $hash, 4, "Set '".$statReadingName."Last'='$result'";
   }

 # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      # statistics_storeSingularReadings $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast
      my $statValue = sprintf  "%.".$decPlaces."f", $stat[1];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Hour",$statValue,$last[1],$periodSwitch >= 1);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[3];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Day",$statValue,$last[3],$periodSwitch >= 2 || $periodSwitch <= -2);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[5];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Month",$statValue,$last[5],$periodSwitch >= 3 || $periodSwitch <= -3);
      $statValue = sprintf  "%.".$decPlaces."f", $stat[7];
      statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,"Delta","Year",$statValue,$last[7],$periodSwitch == 4 || $periodSwitch == -4);
   }

   return ;
}

# Calculates deltas for period of several hours
######################################## 
sub statistics_doStatisticSpecialPeriod ($$$$$) 
{
   my ($hash, $dev, $readingName, $decPlaces, $value) = @_;
   my $name = $hash->{NAME};
   
   my $specialPeriod = AttrVal($name, "specialDeltaPeriodHours", 0);
   
   return   if $specialPeriod == 0;

   my $statReadingName = $hash->{PREFIX} . ucfirst($readingName) . "SpecialPeriod";
   my $hiddenReadingName = ".".$dev->{NAME} . ":" . $readingName . "SpecialPeriod";

  # Update hidden stack
   my @hidden = ();
   if (exists ($hash->{READINGS}{$hiddenReadingName}{VAL})) 
      { @hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; }

   unshift @hidden, $value;
      statistics_Log $hash, 4, "Add $value to $hiddenReadingName";
   while ( $#hidden > $specialPeriod ) { 
      my $lastValue = pop @hidden;
         statistics_Log $hash, 4, "Remove last value '$lastValue' from '$hiddenReadingName'";
   }
   
  # Calculate specialPeriodValue
   my $result = 0;
   foreach (@hidden) { $result += $_; }
   $result = sprintf "%.".$decPlaces."f", $result;
   if ($#hidden != $specialPeriod) { $result .= " (".$#hidden.".hours)"; }
   readingsBulkUpdate($dev, $statReadingName, $result, 1);
   
  # Store hidden stack
   $result = join( " ", @hidden );
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
      statistics_Log $hash, 4, "Set '$hiddenReadingName = $result'";

}

# Calculates deltas for period of several hours
######################################## 
sub statistics_doStatisticSpecialPeriod2 ($$$$$) 
{
   my ($hash, $dev, $readingName,$statType, $period, $decPlaces, $value) = @_;
   my $name = $hash->{NAME};
   
   my $specialPeriod = AttrVal($name, "specialPeriod", "");
   
   return   unless $specialPeriod;

   # if ("$devName:$readingName:$statType:$period=([\d:]+)" =~ /^($specialPeriod)$/) {

   my $statReadingName = $hash->{PREFIX} . ucfirst($readingName) . ucfirst($statType) . ucfirst($period);
   my $hiddenReadingName = ".".$dev->{NAME} . ":" . $readingName . ":" . $statType . ":" . $period;

  # Update hidden stack
   my @hidden = ();
   if (exists ($hash->{READINGS}{$hiddenReadingName}{VAL})) 
      { @hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; }

   unshift @hidden, $value;
      statistics_Log $hash, 4, "Add $value to $hiddenReadingName";
   while ( $#hidden > $specialPeriod ) { 
      my $lastValue = pop @hidden;
         statistics_Log $hash, 4, "Remove last value '$lastValue' from '$hiddenReadingName'";
   }
   
  # Calculate specialPeriodValue
   my $result = 0;
   foreach (@hidden) { $result += $_; }
   $result = sprintf "%.".$decPlaces."f", $result;
   if ($#hidden != $specialPeriod) { $result .= " (".$#hidden.".hours)"; }
   readingsBulkUpdate($dev, $statReadingName, $result, 1);
   
  # Store hidden stack
   $result = join( " ", @hidden );
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
      statistics_Log $hash, 4, "Set '$hiddenReadingName = $result'";

}

# Calculates single Duration Values and informs about end of day and month
######################################## 
sub statistics_doStatisticDuration ($$$$) 
{
   my ($hash, $dev, $readingName, $periodSwitch) = @_;
   my $name = $hash->{NAME};
   my $devName = $dev->{NAME};
   return if not exists ($dev->{READINGS}{$readingName});
  
  # Get reading
   my $state = $dev->{READINGS}{$readingName}{VAL};

   statistics_Log $hash, 4, "Calculating duration statistics for '".$dev->{NAME}.":$readingName = $state'";
  # Daily Statistic
   statistics_doStatisticDurationSingle $hash, $dev, $readingName, "Day", $state, ($periodSwitch >= 2 || $periodSwitch <= -2);
  # Monthly Statistic 
   statistics_doStatisticDurationSingle $hash, $dev, $readingName, "Month", $state, ($periodSwitch >= 3 || $periodSwitch <= -3);

   return ;

}

# Calculates single duration values
######################################## 
sub statistics_doStatisticDurationSingle ($$$$$$) 
{
   my ($hash, $dev, $readingName, $period, $state, $saveLast) = @_;
   my $result;
   my $hiddenReadingName = ".".$dev->{NAME}.":".$readingName.$period;
   my $name=$hash->{NAME};
   my $devName = $dev->{NAME};
   $state =~ s/ /_/g;
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName).$period;
   my %hidden;
   my %stat;
   my $firstRun = not exists($hash->{READINGS}{$hiddenReadingName});
   my $lastState;
   
  # Show since-Value
   if ( $firstRun ) { 
      $hidden{"showDate:"} = 1;
      $saveLast = 0;
      $lastState = $state;
      $hidden{"(since:"} = strftime ("%Y-%m-%d_%H:%M:%S)",localtime()  );
      $hidden{$state} = 0;
      $hidden{$state."_Count"} = 1; 
   } 
  # Do calculations if hidden reading exists
   else {
      %hidden = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; # Internal values
      $lastState = $hidden{"lastState:"};
      my $timeDiff = int(gettimeofday())-$hidden{"lastTime:"};
      $hidden{$lastState.":"} += $timeDiff;
      $hidden{$state."_Count:"}++
         if $state ne $lastState;
   }
   $hidden{"lastState:"} = $state;
   $hidden{"lastTime:"} = int(gettimeofday());
   
  # Prepare new current reading, delete hidden reading if it is used again
   $result = "";
   foreach my $key (sort keys %hidden) {
      if ($key !~ /^(lastState|lastTime|showDate|\(since):$/) {
         # Create current summary reading
         $result .= " " if $result;
         if ($key !~ /_Count:$/) {
            #Store current value for single readings
            $stat{$key} = statistics_FormatDuration($hidden{$key});
            $result .= "$key ".$stat{$key};
            # Reset hidden reading if period change
            if ($saveLast) { delete $hidden{$key}; }
         }
         else {
            $result .= "$key ".$hidden{$key};
            #Store current value for single readings
            $stat{$key} = $hidden{$key};
            # Reset hidden reading if period change
            if ($saveLast && $key ne $state."_Count") {
               delete $hidden{$key};
            }
            elsif ($saveLast && $key eq $state."_Count") {
               $hidden{$key} = 1;
            }
         }
      }
   }
   if ($hidden{"showDate:"} == 1) { $result .= " (since: ".$hidden{"(since:"}; }

  # Store current reading as last reading, Reset current reading
    if ($saveLast) { 
      readingsBulkUpdate($dev, $statReadingName . "Last", $result, 1); 
      statistics_Log $hash, 4, "Set '".$statReadingName . "Last = $result'";
      $result = $state.": 00:00:00 ".$state."_Count: 1";
      $hidden{$state.":"} = 0;
      $hidden{$state."_Count:"} = 1;
      $hidden{"showDate:"} = 0;
   }

  # Store current reading
   readingsBulkUpdate($dev, $statReadingName, $result, 0);
   statistics_Log $hash, 5, "Set '$statReadingName = $result'";
 
  # Store single readings
   my $singularReadings = AttrVal($name, "singularReadings", "");
   if ($singularReadings ne "") {
      while (my ($statKey, $statValue) = each(%stat) ) {  
         unless ($saveLast) {
            chop ($statKey);
            # statistics_storeSingularReadings  
            # $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast
            statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,$statKey,$period,$statValue,0,$saveLast);
         }
         else {
            my $newValue = $hidden{$statKey};
            chop ($statKey);
            # statistics_storeSingularReadings  
            # $hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast
            statistics_storeSingularReadings ($name,$singularReadings,$dev,$statReadingName,$readingName,$statKey,$period,$newValue,$statValue,$saveLast);
         }
      }
   }

  # Store hidden reading
   $result = "";
   while ( my ($key, $duration) = each(%hidden) ) {
      $result .= " " if $result;
      $result .= "$key $duration"; 
   }
   readingsSingleUpdate($hash, $hiddenReadingName, $result, 0);
   statistics_Log $hash, 5, "Set '$hiddenReadingName = $result'";

   return;
}

####################
sub statistics_storeSingularReadings ($$$$$$$$$$)
{
   my ($hashName,$singularReadings,$dev,$statReadingName,$readingName,$statType,$period,$statValue,$lastValue,$saveLast) = @_;
   return if $singularReadings eq "";
   
   if ($statType =~ /Delta|Tendency/) { $statReadingName .= $period; }
   else { $statReadingName .= $statType; }
   my $devName=$dev->{NAME};
   if ("$devName:$readingName:$statType:$period" =~ /^($singularReadings)$/) {
      readingsBulkUpdate($dev, $statReadingName, $statValue, 1);
         statistics_Log $hashName, 5, "Set ".$statReadingName." = $statValue"; # Fehler um 24 Uhr
      if ($saveLast) {
         readingsBulkUpdate($dev, $statReadingName."Last", $lastValue, 1);
            statistics_Log $hashName, 5, "Set ".$statReadingName."Last = $lastValue";
      } 
   }
}

####################
sub statistics_getStoredDevices ($)
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

########################################
sub statistics_FormatDuration($)
{
   my ($value) = @_;
   #Tage
   my $returnstr ="";
   if ($value > 86400) { $returnstr = sprintf "%dd ", int($value/86400); }
   # Stunden
   if ($value == 86400) { 
      $returnstr = "24:00:00";
   } else {
      $value %= 86400;
      $returnstr .= sprintf "%02d:", int($value/3600);
      $value %= 3600;
      $returnstr .= sprintf "%02d:", int($value/60);
      $value %= 60;
      $returnstr .= sprintf "%02d", $value;
   }
   return $returnstr;
}

########################################
sub statistics_maxDecPlaces($$)
{
   my ($value, $decMax) = @_;
   $decMax = 0 if ! defined $decMax;
   if ( $value =~ /.*\.(.*)/ ) {
      my $decPlaces = length($1);
      $decMax = $decPlaces >= $decMax ? $decPlaces : $decMax;
   }
   return $decMax;
}

########################################
sub statistics_UpdateDevReading($$$$)
{
   my ($dev, $rname, $val, $event) = @_;
   $dev->{READINGS}{$rname}{VAL} = $val;
   $dev->{READINGS}{$rname}{TIME} = TimeNow(); 
   if  ($event==1) {
      if (exists ($dev->{CHANGED})) {
         my $max = int(@{$dev->{CHANGED}});
         $dev->{CHANGED}[$max] = "$rname: $val";
      }
   } else {
      readingsBulkUpdate($dev, $rname, $val, 1);
   }
}
##########################

1;

=pod
=begin html

<a name="statistics"></a>
<h3>statistics</h3>
(en | <a href="http://fhem.de/commandref_DE.html#statistics">de</a>)
<div style="width:800px">
<ul>
  This modul calculates for certain readings of given devices statistical values and adds them to the devices.
   <br>
   For detail instructions, look at and please maintain the <a href="http://www.fhemwiki.de/wiki/statistics"><b>FHEM-Wiki</b></a>.
  <br>
   Until now statistics for the following readings are automatically built:
   <ul>
      <br>
      <li><b>Min|Avg|Max</b> Minimum, average  and maximum of instantaneous values:
         <br>
         over a period of day, month and year:
         <br>
         <i>brightness, current, energy_current, humidity, temperature, voltage</i>
         <br>
         over a period of hour, day, month and year:
         <br>
         <i>wind, wind_speed, windSpeed</i>
      </li><br>
      <li><b>Tendency</b> over 1h, 2h, 3h und 6h: <i>pressure</i>
      </li><br>
      <li><b>Delta</b> between start and end values - over a period of hour, day, month and year:
         <br>
         <i>count, energy, energy_total, power, total, rain, rain_rate, rain_total</i>
      </li><br>
      <li><b>Duration</b> (and counter) of the states (on, off, open, closed...) over a period of day, month and year:
         <br>
         <i>lightsensor, lock, motion, Window, window, state (if no other reading is recognized)</i>
      </li><br>
  </ul>
   Further readings can be added via the <a href="#statisticsattr">attributes</a> <code>deltaReadings, durationReadings, minAvgMaxReadings, tendencyReadings</code>.
   This allows also to assign a reading to another statistic type.
  <br>&nbsp;
  <br>
  
  <b>Define</b>
  <ul>
  <br>
    <code>define &lt;name&gt; statistics &lt;deviceNameRegExp&gt; [Prefix]</code>
    <br>
    Example: <code>define Statistik statistics Sensor_.*|Wettersensor</code>
    <br>&nbsp;
    <li><code>&lt;DeviceNameRegExp&gt;</code>
      <br>
      Regular expression of device names. <b>!!! Not the device readings !!!</b>
    </li><br>
    <li><code>[Prefix]</code>
      <br>
      Optional. Prefix set is place before statistical data. Default is <i>stat</i>
    </li><br>
  </ul>

  <br>
  <b>Set</b>
   <ul>
      <br>
      <li><code>resetStatistics &lt;All|DeviceName&gt;</code>
      <br>
      Resets the statistic values of the selected device.
      </li><br>
      <li><code>doStatistics</code>
      <br>
      Calculates the current statistic values of all monitored devices.
      </li><br>
  </ul>

  <br>
  <b>Get</b>
   <ul>not implemented yet
  </ul>

  <br>
  <a name="statisticsattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>dayChangeTime &lt;time&gt;</code>
         <br>
         Time of day change. Default is 00:00. For weather data the day change can be set e.g. to 06:50. 
      </li><br>
      <li><code>deltaReadings &lt;readings&gt;</code>
         <br>
         Comma separated list of reading names for which a delta statistic shall be calculated. 
      </li><br>
      <li><code>durationReadings &lt;readings&gt;</code>
         <br>
         Comma separated list of reading names for which a duration statistic shall be calculated. 
      </li><br>
      <li><code>excludedReadings &lt;DeviceRegExp:ReadingNameRegExp&gt;</code>
      <br>
      Regular expression of the readings that shall be excluded from the statistics.<br>
      The reading have to be entered in the form <i>deviceName:readingName</i>.
      <br>
      E.g. <code>FritzDect:current|Sensor_.*:humidity</code>
      <br>
    </li><br>
   
   <li><code>ignoreDefaultAssignments <code>&lt; 0 | 1 &gt;</code></code>
      <br>
      Ignores the default assignments of readings to a statistic type (see above).<br>
      So, only the readings that are listed in the specific attributes are evaluated.
      <br>
    </li><br>
     
    <li><code>minAvgMaxReadings &lt;readings&gt;</code>
      <br>
      Comma separated list of reading names for which a min/average/max statistic shall be calculated. 
    </li><br>
    <li><code>periodChangePreset &lt;seconds&gt;</code>
      <br>
      Preponed start of the calculation of periodical data. Default is 5 seconds before each full hour.
      <br>
      Allows thus the correct timely assignment within plots. Should be adapted to the CPU speed or load of the server.
      <br>
    </li><br>
    <li><code>singularReadings &lt;DeviceRegExp:ReadingRegExp&gt;:statTypes:period</code>
      <ul>
         <li>statTypes: Min|Avg|Max|Delta|<i>DurationState</i>|<span style="color:blue;">Tendency</span></li>
         <li>period: Hour|Day|Month|Year|<span style="color:blue;">1h|2h|3h|6h</span></li>
      </ul>
      <br>
      Regulare expression of statistic values, which for which singular readings are created <u>additionally</u> to the summary readings. Eases the creation of plots. For duration readings the name of the state has to be used as statTypes.
      <br>
       Example: <code>Wettersensor:rain:Delta:(Hour|Day)|(FritzDect:(current|power):(Avg|Max|Delta):(Hour|Day)</code>
      <br>
       <code>Badfenster:Window:(Open|Open_Count):Month</code>
      <br>
    </li><br>
   <li><code>specialDeltaPeriodHours &lt;hours&gt;</code>
      <br>
      Adds, for readings of delta statistics, a singular reading for the given period of hours (e.g. for the rain of the last 72 hours)
   </li><br>
    <li><code>tendencyReadings &lt;readings&gt;</code>
      <br>
      Comma separated list of reading names for which a tendendy statistic shall be calculated. 
    </li><br>
  </ul>
</ul>
</div>
=end html

=begin html_DE

<a name="statistics"></a>
<h3>statistics</h3>
(<a href="http://fhem.de/commandref.html#statistics">en</a> | de)
<div  style="width:800px">
<ul>
  Dieses Modul wertet von den angegebenen Ger&auml;ten (als regul&auml;rer Ausdruck) bestimmte Werte statistisch aus und f&uuml;gt das Ergebnis den jeweiligen Ger&auml;ten als neue Werte hinzu.
   <br>
   F&uuml;r detailierte Anleitungen bitte die <a href="http://www.fhemwiki.de/wiki/Statistics"><b>FHEM-Wiki</b></a> konsultieren und erg&auml;nzen.
   <br>&nbsp;
   <br>
   Es unterscheidet in vier Statistik-Typen denen bereits standardm&auml;ssig Ger&auml;tewerte zugeordnet sind:
   <ul>
      <li><b>Min|Avg|Max</b> Minimum, Durchschnitt und Maximum von Momentanwerten:
         <br>
         &uuml;ber den Zeitraum Tag, Monat und Jahr:
         <br>
         <i>brightness, current, energy_current, humidity, temperature, voltage</i>
         <br>
         &uuml;ber den Zeitraum Stunde, Tag, Monat und Jahr:
         <br>
         <i>wind, wind_speed, windSpeed</i>
      </li><br>
      <li><b>Tendency</b> Tendenz &uuml;ber 1h, 2h, 3h und 6h: <i>pressure</i>
      </li><br>
      <li><b>Delta</b> Differenz zwischen Anfangs- und Endwerte innerhalb eines Zeitraums (Stunde, Tag, Monat, Jahr):
         <br>
         <i>count, energy, energy_total, power, total, rain, rain_rate, rain_total</i>
      </li><br>
      <li><b>Duration</b> Dauer und Anzahl der Zust&auml;nde (on, off, open, closed...) innerhalb eines Zeitraums (Tag, Monat, Jahr):
         <br>
         <i>lightsensor, lock, motion, Window, window, state (wenn kein anderer Ger&auml;tewert g&uuml;ltig)</i>
      </li><br>
  </ul>
  &Uuml;ber die <a href="#statisticsattr">Attribute</a> <code>deltaReadings, durationReadings, minAvgMaxReadings, tendencyReadings</code> k&ouml;nnen weitere Ger&auml;tewerte hinzugef&uuml;gt oder
  einem anderen Statistik-Typ zugeordnet werden. 
  <br>&nbsp;
  <br>
  
  <b>Define</b>
  <ul>
      <br>
      <code>define &lt;Name&gt; statistics &lt;Ger&auml;teNameRegExp&gt; [Prefix]</code>
      <br>
      Beispiel: <code>define Statistik statistics Wettersensor|Badsensor</code>
      <br>&nbsp;
      <li><code>&lt;Ger&auml;teNameRegExp&gt;</code>
         <br>
         Regul&auml;rer Ausdruck f&uuml;r den Ger&auml;tenamen. <b>!!! Nicht die Ger&auml;tewerte !!!</b>
      </li><br>
      <li><code>[Prefix]</code>
         <br>
         Optional. Der Prefix wird vor den Namen der statistischen Ger&auml;tewerte gesetzt. Standardm&auml;ssig <i>stat</i>
      </li><br>
   </ul>
  
   <br>
   <b>Set</b>
   <ul>
      <br>
      <li><code>resetStatistics &lt;All|Ger&auml;tename&gt;</code>
         <br>
         Setzt die Statistiken der ausgew&auml;hlten Ger&auml;te zur&uuml;ck.
      </li><br>
      <li><code>doStatistics</code>
         <br>
         Berechnet die aktuellen Statistiken aller beobachteten Ger&auml;te.
      </li><br>
  </ul>
  <br>

  <b>Get</b>
   <ul>nicht implementiert
  </ul>
  <br>

  <a name="statisticsattr"></a>
   <b>Attributes</b>
   <ul>
      <br>
      <li><code>dayChangeTime &lt;Zeit&gt;</code>
         <br>
         Uhrzeit des Tageswechsels. Standardm&auml;ssig 00:00. Bei Wetterdaten kann der Tageswechsel z.B. auf 6:50 gesetzt werden. 
      </li><br>
      <li><code>deltaReadings &lt;Ger&auml;tewerte&gt;</code>
         <br>
         Durch Kommas getrennte Liste von weiteren Ger&auml;tewerten, f&uuml;r welche die Differenz zwischen den Werten am Anfang und Ende einer Periode (Stunde/Tag/Monat/Jahr) bestimmt wird. 
      </li><br>
      <li><code>durationReadings &lt;Ger&auml;tewerte&gt;</code>
         <br>
         Durch Kommas getrennte Liste von weiteren Ger&auml;tewerten, f&uuml;r welche die Dauer einzelner Ger&auml;tewerte innerhalb bestimmte Zeitr&auml;ume (Stunde/Tag/Monat/Jahr) erfasst wird.
      </li><br>
      <li><code>excludedReadings &lt;Ger&auml;tenameRegExp:Ger&auml;tewertRegExp&gt;</code>
         <br>
         Regul&auml;rer Ausdruck der Ger&auml;tewerte die nicht ausgewertet werden sollen.
         z.B. <code>FritzDect:current|Sensor_.*:humidity</code>
         <br>
      </li><br>

   <li><code>ignoreDefaultAssignments <code>&lt;0 | 1&gt;</code></code>
      <br>
      Ignoriert die Standardzuordnung von Ger&auml;tewerten zu Statistiktypen..<br>
      D.h., nur die Ger&auml;tewerte, die &uuml;ber Attribute den Statistiktypen zugeordnet sind, werden ausgewertet.
      <br>
    </li><br>
     
      <li><code>hideAllSummaryReadings &lt;0 | 1&gt;</code>
         <br>
         noch nicht implementiert - Es werden keine gesammelten Statistiken angezeigt, sondern nur die unter "singularReadings" definierten Einzelwerte 
      </li><br>
      <li><code>minAvgMaxReadings &lt;Ger&auml;tewerte&gt;</code>
         <br>
         Durch Kommas getrennte Liste von Ger&auml;tewerten, f&uuml;r die in bestimmten Zeitr&auml;umen (Tag, Monat, Jahr) Minimum, Mittelwert und Maximum erfasst werden. 
      </li><br>
      <li><code>periodChangePreset &lt;Sekunden&gt;</code>
         <br>
         Start der Berechnung der periodischen Daten, standardm&auml;ssig 5 Sekunden vor der vollen Stunde,
         <br>
         Erlaubt die korrekte zeitliche Zuordnung in Plots, kann je nach Systemauslastung verringert oder vergr&ouml;&szlig;ert werden.
         <br>
      </li><br>
      <li><code>singularReadings &lt;Ger&auml;tRegExp:Ger&auml;teWertRegExp:Statistiktyp:Zeitraum&gt;</code>
         <ul>
            <li>Statistiktyp: Min|Avg|Max|Delta|<i>DurationState</i>|<span style="color:blue;">Tendency</span></li>
            <li>Zeitraum: Hour|Day|Month|Year|<span style="color:blue;">1h|2h|3h|6h</span></li>
         </ul>
         Regul&auml;rer Ausdruck statistischer Werte, die <u>zus&auml;tzlich</u> auch als einzelne Werte gespeichert werden sollen.
         Erleichtert die Erzeugung von Plots und anderer Auswertungen (notify).
         <br>
         F&uuml;r "duration"-Ger&auml;tewerte muss der Name des jeweiligen Statuswertes als <code>Statistiktyp</code> eingesetzt werden.
         <br>
          Beispiel:
         <br>
          <code>Wettersensor:rain:Delta:(Hour|Day)|FritzDect:power:Delta:Day</code>
         <br>
          <code>Badfenster:Window:(Open|Open_Count):Month</code>
      </li><br>
      <li><code>specialDeltaPeriodHours &lt;Stunden&gt;</code>
         <br>
         F&uuml;gt den Delta-Statistiken einen singul&auml;ren Ger&auml;tewert f&uuml;r die angegebenen Stunden hinzu (z.b. f&uuml;r den Regen in den letzten 72 Stunden)
      </li><br>
      <li><code>tendencyReadings &lt;Ger&auml;tewerte&gt;</code>
         <br>
         Durch Kommas getrennte Liste von weiteren Ger&auml;tewerten, f&uuml;r die innerhalb bestimmter Zeitr&auml;ume (1h, 2h, 3h, 6h) die Differenz zwischen Anfangs- und Endwert ermittelt wird. 
      </li><br>
      <li><a href="#readingFnAttributes">readingFnAttributes</a>
      </li><br>
   </ul>
</ul>
</div>

=end html_DE

=cut
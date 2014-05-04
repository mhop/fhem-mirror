##############################################
#
#  98_statistic.pm
#
#  Copyright notice
#
#  (c) 2014 Torsten Poitzsch < torsten . poitzsch at gmx . de >
#   inspired by 98_rain.pm of Andreas Vogt
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

sub statistics_doStatisticMinMax ($$$$);
sub statistics_doStatisticMinMaxSingle ($$$$$$);

# Modul Version for remote debugging
  my $modulVersion = "2014-05-04";

##############################################################
# Syntax: deviceType, readingName, statisticType, decimalPlaces
#     statisticType: 0=noStatistic | 1=maxMinAvgStatistic | 2=integralTimeStatistic | 3=onOffTimeCount
##############################################################
  my @knownDeviceReadings = (
    ["CUL_WS", "humidity", 1, 0]
   ,["CUL_WS", "temperature", 1, 1] 
   ,["KS300", "humidity", 1, 0]
   ,["KS300", "temperature", 1, 1] 
   ,["KS300", "wind", 1, 0] 
   ,["KS300", "rain", 2, 1] 
   ,["FBDECT", "energy", 2, 0] 
   ,["FBDECT", "power", 1, 2] 
   ,["FBDECT", "voltage", 1, 1] 
  );
##############################################################

sub ##########################################
statistics_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}   = "statistics_Define";
  $hash->{NotifyFn} = "statistics_Notify";

  $hash->{NotifyOrderPrefix} = "10-";   # Want to be called before the rest
  $hash->{AttrList} = "disable:0,1 "
                   ."DayChangeTime "
                   ."CorrectionValue "
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
  my $devname = $a[2];

  if (@a == 4) {$hash->{PREFIX} = $a[3];}
  else {$hash->{PREFIX} = "stat";}
 
  eval { "Hallo" =~ m/^$devname$/ };
  return "Bad regexp: $@" if($@);
  $hash->{DEV_REGEXP} = $devname;

  $hash->{STATE} = "active";
  return undef;
}


##########################
sub
statistics_Notify($$)
{
  my ($hash, $dev) = @_;
  my $hashName = $hash->{NAME};
  my $devName = $dev->{NAME};
  my $devType = $dev->{TYPE};
  
  return "" if(AttrVal($hashName, "disable", undef));

 # Return if the notifying device is not monitored
  return "" if(!defined($hash->{DEV_REGEXP}));
  my $regexp = $hash->{DEV_REGEXP};
  return "" if($devName !~ m/^($regexp)$/);
  
  my $output = $devName." (".$devType.")" ;
  my $max = int(@{$dev->{CHANGED}});   
  my $readingName;
  my $value;
 # Loop through all known device types and readings
   foreach my $f (@knownDeviceReadings) 
   {
      $readingName = $$f[1];
    # notifing device type is known and the device has also the known reading
      if ($$f[0] eq $devType && exists ($dev->{READINGS}{$readingName})) { 
         if ($$f[2] == 1) { statistics_doStatisticMinMax ($hash, $dev, $readingName, $$f[3]);}
      }
   }
   
 # Record device as monitored
   my $monReadingName = "monitoredDevices".$devType;
   my $monReadingValue = ReadingsVal($hashName,$monReadingName,"");
   my $temp = '^'.$devName.'$|^'.$devName.',|,'.$devName.'$|,'.$devName.',';
   if ($monReadingValue !~ /$temp/) {
      if($monReadingValue eq "") { $monReadingValue = $devName;}
      else {$monReadingValue .= ",".$devName;}
      readingsSingleUpdate($hash,$monReadingName,$monReadingValue,0);
   } 

  return undef;
}

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
statistics_doStatisticMinMax ($$$$) 
{
   my ($hash, $dev, $readingName, $decPlaces) = @_;
   my $dummy;

   my $lastReading;
   my $lastSums;
   my @newReading;
   
   my $yearLast;
   my $monthLast;
   my $dayLast;
   my $dayNow;
   my $monthNow;
   my $yearNow;
   
   my $prefix = $hash->{PREFIX};
   my $value = $dev->{READINGS}{$readingName}{VAL};
   $value =~ s/^([\d.]*).*/$1/eg;

   # Determine date of last and current reading
   if (exists($dev->{READINGS}{$prefix.ucfirst($readingName)."Day"}{TIME})) {
      ($yearLast, $monthLast, $dayLast) = $dev->{READINGS}{$prefix.ucfirst($readingName)."Day"}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d)/;
   } else {
      ($dummy, $dummy, $dummy, $dayLast, $monthLast, $yearLast) = localtime;
      $yearLast += 1900;
      $monthLast ++;
   }
   ($dummy, $dummy, $dummy, $dayNow, $monthNow, $yearNow) = localtime;
   $yearNow += 1900;
   $monthNow ++;

  # Daily Statistic
   #statistics_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast, decPlaces
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName."Day", $value, ($dayNow != $dayLast), $decPlaces;
   
  # Monthly Statistic 
   #statistics_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast, decPlaces
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName."Month", $value, ($monthNow != $monthLast), $decPlaces;
    
  # Yearly Statistic 
   #statistics_doStatisticMinMaxSingle: $hash, $readingName, $value, $saveLast, decPlaces
   statistics_doStatisticMinMaxSingle $hash, $dev, $readingName."Year", $value, ($yearNow != $yearLast), $decPlaces;

   return ;

}

# Calculates single MaxMin Values and informs about end of day and month
sub ######################################## 
statistics_doStatisticMinMaxSingle ($$$$$$) 
{
   my ($hash, $dev, $readingName, $value, $saveLast, $decPlaces) = @_;
   my $result;
   my $hiddenReadingName = ".".$dev->{NAME}.".".$readingName;
   
   my $statReadingName = $hash->{PREFIX};
   $statReadingName .= ucfirst($readingName);
   
   my $lastReading = $dev->{READINGS}{$statReadingName}{VAL} || "";
   
 # Initializing
   if ( $lastReading eq "" ) { 
      my $since = strftime "%Y-%m-%d_%H:%M:%S", localtime(); 
      $result = "Count: 1 Sum: $value ShowDate: 1";
      readingsSingleUpdate($hash, $hiddenReadingName, $result,0);

      $value = sprintf( "%.".$decPlaces."f", $value);
      $result = "Min: $value Avg: $value Max: $value (since: $since )";
      readingsSingleUpdate($dev, $statReadingName, $result,0);

 # Calculations
   } else { 
      my @a = split / /, $hash->{READINGS}{$hiddenReadingName}{VAL}; # Internal values
      my @b = split / /, $lastReading;
    # Do calculations
      $a[1]++; # Count
      $a[3] += $value; # Sum
      if ($value < $b[1]) { $b[1]=$value; } # Min
      $b[3] = $a[3] / $a[1]; # Avg
      if ($value > $b[5]) { $b[5]=$value; } # Max

    # in case of period change, save "last" values and reset counters
      if ($saveLast) {
         $result = "Min: $b[1] Avg: $b[3] Max: $b[5]";
         if ($a[5] == 1) { $result .= " (since: $b[7] )"; }
         readingsSingleUpdate($dev, $statReadingName . "Last", $lastReading,0);
         $a[1] = 1;   $a[3] = $value;   $a[5] = 0;
         $b[1] = $value;   $b[3] = $value;   $b[5] = $value;
      }
    # Store internal calculation values
      $result = "Count: $a[1] Sum: $a[3] ShowDate: $a[5]";  
      readingsSingleUpdate($hash, $hiddenReadingName, $result,0);
    # Store visible Reading
      $result = "Min: ". sprintf( "%.".$decPlaces."f", $b[1]);
      $result .= " Avg: ". sprintf( "%.".$decPlaces."f", $b[3]);
      $result .= " Max: ". sprintf( "%.".$decPlaces."f", $b[5]);
      if ($a[5] == 1) { $result .= " (since: $b[7] )"; }
      readingsSingleUpdate($dev, $statReadingName, $result,0);
   }
   return;
}


# Calculates deltas for day, month and year
sub ######################################## 
statistics_doStatisticDelta ($$$$$) 
{
   my ($hash, $readingName, $value, $special, $activeTariff) = @_;
   my $dummy;
   my $result;
   
   my $deltaValue;
   my $previousTariff; 
   my $showDate;
   
 # Determine if time period switched (day, month, year)
 # Get deltaValue and Tariff of previous call
   my $periodSwitch = 0;
   my $yearLast; my $monthLast; my $dayLast; my $hourLast;  my $hourNow; my $dayNow; my $monthNow; my $yearNow;
   if (exists($hash->{READINGS}{"." . $readingName . "Before"})) {
      ($yearLast, $monthLast, $dayLast, $hourLast) = ($hash->{READINGS}{"." . $readingName . "Before"}{TIME} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)/);
      $yearLast -= 1900;
      $monthLast --;
      ($dummy, $deltaValue, $dummy, $previousTariff, $dummy, $showDate) = split / /,  $hash->{READINGS}{"." . $readingName . "Before"}{VAL} || "";
      $deltaValue = $value - $deltaValue;
   } else {
      ($dummy, $dummy, $hourLast, $dayLast, $monthLast, $yearLast) = localtime;
      $deltaValue = 0;
      $previousTariff = 0; 
      $showDate = 8;
   }
   ($dummy, $dummy, $hourNow, $dayNow, $monthNow, $yearNow) = localtime;

   if ($yearNow != $yearLast) { $periodSwitch = 4; }
   elsif ($monthNow != $monthLast) { $periodSwitch = 3; }
   elsif ($dayNow != $dayLast) { $periodSwitch = 2; }
   elsif ($hourNow != $hourLast) { $periodSwitch = 1; }

   # Determine if "since" value has to be shown in current and last reading
   if ($periodSwitch == 4) {
      if ($showDate == 1) { $showDate = 0; } # Do not show the "since:" value for year changes anymore
      if ($showDate >= 2) { $showDate = 1; } # Shows the "since:" value for the first year change
   }
   if ($periodSwitch >= 3){
      if ($showDate == 3) { $showDate = 2; } # Do not show the "since:" value for month changes anymore
      if ($showDate >= 4) { $showDate = 3; } # Shows the "since:" value for the first month change
   }
   if ($periodSwitch >= 2){
      if ($showDate == 5) { $showDate = 4; } # Do not show the "since:" value for day changes anymore
      if ($showDate >= 6) { $showDate = 5; } # Shows the "since:" value for the first day change
   }
   if ($periodSwitch >= 1){
      if ($showDate == 7) { $showDate = 6; } # Do not show the "since:" value for day changes anymore
      if ($showDate >= 8) { $showDate = 7; } # Shows the "since:" value for the first hour change
   }

 # statistics_doStatisticDeltaSingle; $hash, $readingName, $deltaValue, $special, $periodSwitch, $showDate, $firstCall
   statistics_doStatisticDeltaSingle ($hash, $readingName, $deltaValue, $special, $periodSwitch, $showDate);

   foreach (1,2,3,4,5,6,7,8,9) {
      if ( $previousTariff == $_ ) {
         statistics_doStatisticDeltaSingle ($hash, $readingName."Tariff".$_, $deltaValue, 0, $periodSwitch, $showDate);
      } elsif ($activeTariff == $_ || ($periodSwitch > 0 && exists($hash->{READINGS}{$readingName . "Tariff".$_}))) {
         statistics_doStatisticDeltaSingle ($hash, $readingName."Tariff".$_, 0, 0 , $periodSwitch, $showDate);
      }
   }
      
   # Hidden storage of current values for next call(before values)
   $result = "Value: $value Tariff: $activeTariff ShowDate: $showDate ";  
   readingsBulkUpdate($hash, ".".$readingName."Before", $result);

   return ;
}

sub ######################################## 
statistics_doStatisticDeltaSingle ($$$$$$) 
{
   my ($hash, $readingName, $deltaValue, $special, $periodSwitch, $showDate) = @_;
   my $dummy;
   my $result; 

 # get existing statistic reading
   my @curr;
   if (exists($hash->{READINGS}{$readingName}{VAL})) {
      @curr = split / /, $hash->{READINGS}{$readingName}{VAL} || "";
      if ($curr[0] eq "Day:") { $curr[9]=$curr[7]; $curr[7]=$curr[5]; $curr[5]=$curr[3]; $curr[3]=$curr[1]; $curr[1]=0; }
   } else {
      $curr[1] = 0; $curr[3] = 0;  $curr[5] = 0; $curr[7] = 0;
      $curr[9] = strftime "%Y-%m-%d_%H:%M:%S", localtime(); # start
   }
   
 # get statistic values of previous period
   my @last;
   if ($periodSwitch >= 1) {
      if (exists ($hash->{READINGS}{$readingName."Last"})) { 
         @last = split / /,  $hash->{READINGS}{$readingName."Last"}{VAL};
         if ($last[0] eq "Day:") { $last[9]=$last[7]; $last[7]=$last[5]; $last[5]=$last[3]; $last[3]=$last[1]; $last[1]="-"; }
      } else {
         @last = split / /,  "Hour: - Day: - Month: - Year: -";
      }
   }
   
 # Do statistic
   $curr[1] += $deltaValue;
   $curr[3] += $deltaValue;
   $curr[5] += $deltaValue;
   $curr[7] += $deltaValue;

 # If change of year, change yearly statistic
   if ($periodSwitch == 4){
      $last[7] = $curr[7];
      $curr[7] = 0;
      if ($showDate == 1) { $last[9] = $curr[9]; }
   }

 # If change of month, change monthly statistic 
   if ($periodSwitch >= 3){
      $last[5] = $curr[5];
      $curr[5] = 0;
      if ($showDate == 3) { $last[9] = $curr[9];}
   }

 # If change of day, change daily statistic
   if ($periodSwitch >= 2){
      $last[3] = $curr[3];
      $curr[3] = 0;
      if ($showDate == 5) {
         $last[9] = $curr[9];
        # Next monthly and yearly values start at 00:00 and show only date (no time)
         $curr[5] = 0;
         $curr[7] = 0;
         $curr[9] = strftime "%Y-%m-%d", localtime(); # start
      }
   }

 # If change of hour, change hourly statistic 
   if ($periodSwitch >= 1){
      $last[1] = $curr[1];
      $curr[1] = 0;
      if ($showDate == 7) { $last[9] = $curr[9];}
   }

 # Store visible statistic readings (delta values)
   $result = "Hour: $curr[1] Day: $curr[3] Month: $curr[5] Year: $curr[7]";
   if ( $showDate >=2 ) { $result .= " (since: $curr[9] )"; }
   readingsBulkUpdate($hash,$readingName,$result);
   
   if ($special == 1) { readingsBulkUpdate($hash,$readingName."Today",$curr[3]) };

 # if changed, store previous visible statistic (delta) values
   if ($periodSwitch >= 1) {
      $result = "Hour: $last[1] Day: $last[3] Month: $last[5] Year: $last[7]";
      if ( $showDate =~ /1|3|5|7/ ) { $result .= " (since: $last[9] )";}
      readingsBulkUpdate($hash,$readingName."Last",$result); 
   }
}

1;

=pod
=begin html

<a name="statistics"></a>
<h3>statistics</h3>
<ul>
  This modul calculates for certain readings of given devices statistical values and adds them to the devices.
  &nbsp;
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
      Until now the following device types and readings are analysed:
      <ul><li><b>CUL_WS:</b> humidity, temperature</li>
          <li><b>KS300:</b> humidity, temperature, wind, rain</li>
          <li><b>FBDECT:</b> energy, power, voltage</li>
      </ul>
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

  <a name="JSONMETERattr"></a>
   <b>Attributes</b>
   <ul>not implemented yet
   </ul>
</ul>

=end html

=begin html_DE

<a name="statistics"></a>
<h3>statistics</h3>
<ul>
  Dieses Modul wertet von den angegebenen Ger&auml;ten bestimmte Werte statistisch aus und fügt sie den jeweiligen Ger&auml;ten als neue Werte hinzu.
  &nbsp;
  <br>
  
  <b>Define</b>
  <ul>
    <code>define &lt;Name&gt; statistics &lt;Ger&auml;teNameRegExp&gt; [Prefix]</code>
    <br>
    Beispiel: <code>define Statistik statistics Sensor_.*|Wettersensor</code>
    <br>&nbsp;
    <li><code>[Prefix]</code>
      <br>
      Optional. Der Prefix wird vor den Namen der statistischen Gerätewerte gesetzt. Standardm&auml;ssig <i>stat</i>
    </li><br>
    <li><code>&lt;Ger&auml;teNameRegExp&gt;</code>
      <br>
      Regularer Ausdruck für den Ger&auml;tenamen. !!! Nicht die Gerätewerte !!!
      <br>
      Derzeit werden folgende Ger&auml;tetypen und Ger&auml;tewerte ausgewertet:
      <ul><li><b>CUL_WS:</b> humidity, temperature</li>
          <li><b>KS300:</b> humidity, temperature, wind, rain</li>
          <li><b>FBDECT:</b> energy, power, voltage</li>
      </ul>
    </li>
  </ul>
  
  <br>
  <b>Set</b>
   <ul>noch nicht implementiert
  </ul>
  <br>

  <b>Get</b>
   <ul>noch nicht implementiert
  </ul>
  <br>

  <a name="JSONMETERattr"></a>
   <b>Attributes</b>
   <ul>noch nicht implementiert
   </ul>
</ul>

=end html_DE

=cut
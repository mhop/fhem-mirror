# $Id: 99_UtilsHourCounter.pm 2014-12-16 20:15:33 john $
#
#	This ist a reference implementation for enhanced features for modul hourCounter
#
#	This module is written by john.
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# Changelog
#
#  04.02.14 - 1.00 modul created
#  06.02.14 - 1.01 fixed: wrong timing in assignment appUtilization
#  17.03.14 - 1.01 added: appHC_OnYear
#  10.12.14 - 1.0.1.0 fixed: with integration of interval and support of cyclically updates
#                     we need some changes: 
#                     instead of value and countsOverall , now tickChanged is used


package main;

use strict;
use warnings;
use POSIX;
use vars qw(%defs);
use vars qw(%modules);

#require "98_HourCounter.pm";

my $UtilsHourCounter_Version="1.0.1.0 - 10.12.2014 (john)";
sub Log3($$$);

# --------------------------------------------------
sub UtilsHourCounter_Initialize($$)
{
  my ($hash) = @_;
  
  Log3 '', 3, "[UtilsHourCounter] Init Done with Version $UtilsHourCounter_Version";
}

# --------------------------------------------------
# yearly tasks
# 
sub appHC_OnYear($$$)
{
   my ($name,$part0,$part1) = @_;  # name objects, name des parameters, wert des parameters 
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));
   
   my $appCountsPerYear     = ReadingsVal ($name, 'appCountsPerYearTemp'  ,0);
   my $appOpHoursPerYear    = ReadingsVal ($name, 'appOpHoursPerYearTemp'  ,0);
      
      #---------------
   readingsBeginUpdate($hash);
   
   readingsBulkUpdate ($hash, 'appCountsPerYearTemp'  , 0 );
   readingsBulkUpdate ($hash, 'appCountsPerYear'     , $appCountsPerYear );
   
   readingsBulkUpdate ($hash, 'appOpHoursPerYearTemp'  , 0 );
   readingsBulkUpdate ($hash, 'appOpHoursPerYear'     , $appOpHoursPerYear );
   
   readingsEndUpdate($hash, 1)
}

# --------------------------------------------------
# monthly tasks
# 
sub appHC_OnMonth($$$)
{
   my ($name,$part0,$part1) = @_;  # name objects, name des parameters, wert des parameters 
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));
   
   my $appCountsPerMonth     = ReadingsVal ($name, 'appCountsPerMonthTemp'  ,0);
   my $appOpHoursPerMonth    = ReadingsVal ($name, 'appOpHoursPerMonthTemp'  ,0);
      
      #---------------
   readingsBeginUpdate($hash);
   
   readingsBulkUpdate ($hash, 'appCountsPerMonthTemp'  , 0 );
   readingsBulkUpdate ($hash, 'appCountsPerMonth'     , $appCountsPerMonth );
   
   readingsBulkUpdate ($hash, 'appOpHoursPerMonthTemp'  , 0 );
   readingsBulkUpdate ($hash, 'appOpHoursPerMonth'     , $appOpHoursPerMonth );
   
   readingsEndUpdate($hash, 1)
}

# --------------------------------------------------
# weekly tasks
sub appHC_OnWeek($$$)
{
   my ($name,$part0,$part1) = @_;  # name objects, name des parameters, wert des parameters 
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));
   
   my $appCountsPerWeek      = ReadingsVal ($name, 'appCountsPerWeekTemp'  ,0);
   my $appOpHoursPerWeek     = ReadingsVal ($name, 'appOpHoursPerWeekTemp'  ,0);
   
   readingsBeginUpdate($hash);
   
   readingsBulkUpdate ($hash, 'appCountsPerWeekTemp'        , 0); 
   readingsBulkUpdate ($hash, 'appCountsPerWeek'            , $appCountsPerWeek); 
    
   readingsBulkUpdate ($hash, 'appOpHoursPerWeekTemp'       , 0); 
   readingsBulkUpdate ($hash, 'appOpHoursPerWeek'           , $appOpHoursPerWeek); 
   
   readingsEndUpdate( $hash, 1 );   
   
}

# --------------------------------------------------
# dayly tasks
sub appHC_OnDay($$$)
{
   my ($name,$part0,$part1) = @_;  # name objects, name des parameters, wert des parameters 
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));
   
   my $appCountsPerDay = ReadingsVal($name, 'countsPerDay',0);
   my $pulseTimePerDay = ReadingsVal($name, 'pulseTimePerDay',0);
   
   #HourCounter_Log $hash, 2, "pulseTimePerDay:$pulseTimePerDay";   
       
   my $appOpHoursPerDay  = $pulseTimePerDay/3600;
   my $appOpHoursPerWeekTemp = ReadingsVal ($name,'appOpHoursPerWeekTemp',0 )+$appOpHoursPerDay; 
   my $appOpHoursPerMonthTemp =ReadingsVal ($name,'appOpHoursPerMonthTemp',0 )+$appOpHoursPerDay; 
   my $appOpHoursPerYearTemp  =ReadingsVal ($name,'appOpHoursPerYearTemp',0 )+$appOpHoursPerDay; 
   
   my $appUtilizationTempOld = ReadingsVal ($name,'appUtilizationTempOld',0 ); 
     
   readingsBeginUpdate($hash); 
   
   readingsBulkUpdate ($hash, 'appCountsPerDay'       , $appCountsPerDay); 
   readingsBulkUpdate ($hash, 'appOpHoursPerDay'      , $appOpHoursPerDay);
   readingsBulkUpdate ($hash, 'appOpHoursPerDayTemp'  , 0);
   
   readingsBulkUpdate ($hash, 'appOpHoursPerWeekTemp' , $appOpHoursPerWeekTemp);
   readingsBulkUpdate ($hash, 'appOpHoursPerMonthTemp', $appOpHoursPerMonthTemp);
   readingsBulkUpdate ($hash, 'appOpHoursPerYearTemp' , $appOpHoursPerYearTemp);
      
   readingsBulkUpdate ($hash, 'appUtilization', $appUtilizationTempOld);   
       
   readingsEndUpdate( $hash, 1 );   
}

# --------------------------------------------------
# hourly tasks
sub appHC_OnHour($$$)
{
   my ($name,$part0,$part1) = @_;  # name objects, name des parameters, wert des parameters 
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));

   my $appCountsPerHourTemp = ReadingsVal($name, 'appCountsPerHourTemp',0); 
   
   readingsBeginUpdate($hash); 
   readingsBulkUpdate ($hash, 'appCountsPerHourTemp', 0 );     
   readingsBulkUpdate ($hash, 'appCountsPerHour', $appCountsPerHourTemp); 
   readingsEndUpdate( $hash, 1 );   
   
}
# --------------------------------------------------
# task on count change
sub appHC_OnCount($$$)
{
   my ($name,$part0,$part1) = @_;  # name objects, name des parameters, wert des parameters 
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));
   
   
   my $appCountsPerHourTemp  = ReadingsVal($name,'appCountsPerHourTemp',0) +  1; 
   my $appCountsPerWeekTemp  = ReadingsVal($name,'appCountsPerWeekTemp',0) +  1; 
   my $appCountsPerMonthTemp = ReadingsVal($name,'appCountsPerMonthTemp',0)+  1; 
   my $appCountsPerYearTemp  = ReadingsVal($name,'appCountsPerYearTemp',0) +  1; 

   readingsBeginUpdate($hash); 
   readingsBulkUpdate ($hash, 'appCountsPerHourTemp', $appCountsPerHourTemp );     
   readingsBulkUpdate ($hash, 'appCountsPerWeekTemp', $appCountsPerWeekTemp );     
   readingsBulkUpdate ($hash, 'appCountsPerMonthTemp',$appCountsPerMonthTemp );     
   readingsBulkUpdate ($hash, 'appCountsPerYearTemp',$appCountsPerYearTemp );     
   readingsEndUpdate( $hash, 1 );   
     
}

# --------------------------------------------------
# task on value change
sub appHC_OnUpdate($$$)
{
   my ($name,$part0,$part1) = @_;  # object name, parameter name, parameter value
   $part0='' if (!defined($part0));
   my $hash = $defs{$name}; 
   return undef if (!defined ($hash));
   
   # acquire needed values
   my $secs= HourCounter_SecondsOfDay();
   my $pulseTimePerDay = ReadingsVal($name,'pulseTimePerDay',0);
    
   # calc utilization
   $secs= 1 if ($secs==0);         # no zero division
   my $appUtilizationTempOld = ReadingsVal($name,'appUtilizationTemp',0);
   my $appUtilizationTemp = $pulseTimePerDay/$secs*100;

   # calc operating hours
   my $appOpHoursPerDayTemp  =$pulseTimePerDay/3600;  # operating time per Day temporary
   
   readingsBeginUpdate($hash); 
   readingsBulkUpdate ($hash, 'appOpHoursPerDayTemp'   , $appOpHoursPerDayTemp);
   readingsBulkUpdate ($hash, 'appUtilizationTemp'     , $appUtilizationTemp );         
   readingsBulkUpdate ($hash, 'appUtilizationTempOld'  , $appUtilizationTempOld );         
   readingsEndUpdate( $hash, 1 );   
   
}

# --------------------------------------------------
# central event dispatcher
sub appHCNotify($$$)
{
    my ($name,$part0,$part1) = @_;   # object name, parameter name, parameter value
    $name = "?" if (!defined($name));
    $part0='' if (!defined($part0));
    my $hash = $defs{$name}; 
    
    return undef if (!defined ($hash));
    my $value = ReadingsVal($name,'value',0);
    #HourCounter_Log ($hash, 2, "Name:$name part0:$part0 part1:$part1 value:$value"); 
     
    if ($part0 eq "tickUpdated:")
    {
       HourCounter_cmdQueueAdd($hash,"appHC_OnUpdate q($name),q($part0),q($part1)");
    }
    elsif ($part0 eq "tickChanged:")
    {
       # count only if rising edge
       if ( $value == 1) 
       { 
         HourCounter_cmdQueueAdd($hash,"appHC_OnCount q($name),q($part0),q($part1)");
       }
    }
    elsif ($part0 eq "tickHour:")  # trigger CN.Test tickHour: 1
    {
       HourCounter_cmdQueueAdd($hash,"appHC_OnHour q($name),q($part0),q($part1)");
    }
    elsif ($part0 eq "tickDay:")  # trigger CN.Test tickDay: 1
    {
       HourCounter_cmdQueueAdd($hash,"appHC_OnDay q($name),q($part0),q($part1)");
    }
    elsif ($part0 eq "tickWeek:")  
    {
       HourCounter_cmdQueueAdd($hash,"appHC_OnWeek q($name),q($part0),q($part1)");
    }
    elsif ($part0 eq "tickMonth:")  
    {
       HourCounter_cmdQueueAdd($hash,"appHC_OnMonth q($name),q($part0),q($part1)");
    }
    elsif ($part0 eq "tickYear:")  
    {
       HourCounter_cmdQueueAdd($hash,"appHC_OnYear q($name),q($part0),q($part1)");
    }
    
    return '';

}




1;


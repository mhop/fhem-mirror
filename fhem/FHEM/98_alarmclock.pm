# $Id$
########################################################################################
#
#  98_alarmclock.pm
#  Fhem Modul to set up a Alarmclock
#
#  2017 Florian Zetlmeisl
#
#
#  This programm is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
########################################################################################


package main;

use strict;
use warnings;


########################################################################################
#
#   Globale Variablen                                           
#
########################################################################################



my %alarmclock_sets = 
(
    "AlarmTime1_Monday"     => "09:00",
    "AlarmTime2_Tuesday"    => "09:00",
    "AlarmTime3_Wednesday"  => "09:00",
    "AlarmTime4_Thursday"   => "09:00",
    "AlarmTime5_Friday"     => "09:00",
    "AlarmTime6_Saturday"   => "10:00",
    "AlarmTime7_Sunday"     => "10:00",
    "AlarmTime8_Holiday"    => "10:00",
    "AlarmOff"              => "NONE",
    "AlarmTime_Weekdays"    => "09:00",
    "AlarmTime_Weekend"     => "09:00",
    "save"                  => "NONE",
    "load"                  => "NONE",
    "disable"               => "0"

);

my %alarmday = 
( 
    "1"     => "AlarmTime1_Monday",
    "2"     => "AlarmTime2_Tuesday",
    "3"     => "AlarmTime3_Wednesday",
    "4"     => "AlarmTime4_Thursday",
    "5"     => "AlarmTime5_Friday",
    "6"     => "AlarmTime6_Saturday",
    "0"     => "AlarmTime7_Sunday",
    "8"     => "AlarmTime8_Holiday"
);


my @mapping_attrs =
qw( 
    AlarmRoutine:textField-long
    AlarmRoutineOff:textField-long 
    PreAlarmRoutine:textField-long 
    OffRoutine:textField-long
    HardAlarmRoutine:textField-long
    SnoozeRoutine:textField-long
);


########################################################################################
#
#   Alarmclock Initialize                                           
#
########################################################################################

sub alarmclock_Initialize($)
{

  my ($hash) = @_;


  $hash->{DefFn}     = "alarmclock_Define";
  $hash->{UndefFn}   = "alarmclock_Undefine";
  $hash->{SetFn}     = "alarmclock_Set";
  $hash->{AttrFn}    = "alarmclock_Attr";
  $hash->{NotifyFn}  = "alarmclock_Notify";
  $hash->{AttrList}  = " "
                        . join( " ", @mapping_attrs )
                        . " PreAlarmRoutine"
                        . " AlarmRoutine"
                        . " AlarmRoutineOff"
                        . " PreAlarmTimeInSec"
                        . " EventForSnooze"
                        . " EventForAlarmOff"
                        . " SnoozeTimeInSec"
                        . " OffDefaultTime"
                        . " OffRoutine"
                        . " HardAlarmTimeInSec"
                        . " HardAlarmRoutine"
                        . " MaxAlarmDurationInSec"
                        . " SnoozeRoutine"
                        . " HolidayDevice"
                        . " HolidayCheck:1,0"
                        . " disable:1,0"
                        . " $readingFnAttributes";

}


########################################################################################
#
#   Alarmclock Define                                               
#
########################################################################################

sub alarmclock_Define($$)
{

  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my ($name, $type) = @a;
  
   
  return "Wrong syntax: use define <name> alarmclock" if(int(@a) != 2);
  
  return undef;
  
}


########################################################################################
#
#   Alarmclock Undefine                                             
#
########################################################################################

sub alarmclock_Undefine($$)
{

  my ($hash,$arg) = @_;
  
  RemoveInternalTimer($hash);
  
  return undef;
  
}


########################################################################################
#
#   Alarmclock Set                                                  
#
########################################################################################

sub alarmclock_Set($$)
{

    my ($hash, @param) = @_;
    my $name = shift @param;
    my $opt = shift @param;
    my $value = join("", @param);
    
    if(!defined($alarmclock_sets{$opt})) {
        my $list =   " AlarmTime1_Monday"
                    ." AlarmTime2_Tuesday"
                    ." AlarmTime3_Wednesday"
                    ." AlarmTime4_Thursday"
                    ." AlarmTime5_Friday"
                    ." AlarmTime6_Saturday"
                    ." AlarmTime7_Sunday"
                    ." AlarmTime8_Holiday"
                    ." AlarmOff:1_Monday,2_Tuesday,3_Wednesday,4_Thursday,5_Friday,6_Saturday,7_Sunday,8_Holiday,Weekdays,Weekend,All"
                    ." AlarmTime_Weekdays"
                    ." AlarmTime_Weekend"
                    ." save:Weekprofile_1,Weekprofile_2,Weekprofile_3,Weekprofile_4,Weekprofile_5"
                    ." load:Weekprofile_1,Weekprofile_2,Weekprofile_3,Weekprofile_4,Weekprofile_5"
                    ." disable:1,0";                    


        return "Unknown argument $opt, choose one of $list";
    }

### AlarmTime ###   
    
    if ($opt =~ /^AlarmTime(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday)/)
    {
        if ($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/)
        {
            readingsSingleUpdate( $hash, $opt, $value, 1 ); 
            alarmclock_createtimer($hash);        
        }
        elsif (!($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/))
        {
            return "Please Set $opt HH:MM" ;     
        }
    }   
    
    
### AlarmOff ###
    
    if ($opt eq "AlarmOff") 
    {
        if ($value =~ /^(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday)$/)
        {
            readingsSingleUpdate( $hash, "AlarmTime$value", "off", 1 );
            alarmclock_createtimer($hash);
        }   
        elsif ($value eq "Weekdays")
        {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "AlarmTime1_Monday", "off");
            readingsBulkUpdate( $hash, "AlarmTime2_Tuesday", "off");
            readingsBulkUpdate( $hash, "AlarmTime3_Wednesday", "off");
            readingsBulkUpdate( $hash, "AlarmTime4_Thursday", "off");
            readingsBulkUpdate( $hash, "AlarmTime5_Friday", "off");
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);
        }
        elsif ($value eq "Weekend")
        {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "AlarmTime6_Saturday", "off");
            readingsBulkUpdate( $hash, "AlarmTime7_Sunday", "off");
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);
        }
        elsif ($value eq "All")
        {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "AlarmTime1_Monday", "off");
            readingsBulkUpdate( $hash, "AlarmTime2_Tuesday", "off");
            readingsBulkUpdate( $hash, "AlarmTime3_Wednesday", "off");
            readingsBulkUpdate( $hash, "AlarmTime4_Thursday", "off");
            readingsBulkUpdate( $hash, "AlarmTime5_Friday", "off");
            readingsBulkUpdate( $hash, "AlarmTime6_Saturday", "off");
            readingsBulkUpdate( $hash, "AlarmTime7_Sunday", "off");
            readingsBulkUpdate( $hash, "AlarmTime8_Holiday", "off");
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);
        }
        elsif (!($value =~ /^(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|Weekdays|Weekend|All)$/))
        {
            return "Please Set $opt (1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|Weekdays|Weekend|All)";
        }
    }


### AlarmTime_Weekdays ###  
    
    if ($opt eq "AlarmTime_Weekdays")
    {
        if ($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/)
        {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "AlarmTime1_Monday", $value);
            readingsBulkUpdate( $hash, "AlarmTime2_Tuesday", $value);
            readingsBulkUpdate( $hash, "AlarmTime3_Wednesday", $value);
            readingsBulkUpdate( $hash, "AlarmTime4_Thursday", $value);
            readingsBulkUpdate( $hash, "AlarmTime5_Friday", $value);
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);        
        }
        elsif (!($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/))
        {
            return "Please Set $opt HH:MM" ;     
        }
    }   
    
### AlarmTime_Weekend ###   
    
    if ($opt eq "AlarmTime_Weekend") 
    {
        if ($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/)
        {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "AlarmTime6_Saturday", $value);
            readingsBulkUpdate( $hash, "AlarmTime7_Sunday", $value);
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);        
        }
        elsif (!($value =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):[0-5]?[0-9]$/))
        {
            return "Please Set $opt HH:MM" ;     
        }
    }
    
### save Weekprofile ###    
    
    if ($opt eq "save") 
    {
        if ($value =~ /^(Weekprofile_1|Weekprofile_2|Weekprofile_3|Weekprofile_4|Weekprofile_5)$/)
        {

                my $time1 = ReadingsVal($hash->{NAME},"AlarmTime1_Monday","off");
                my $time2 = ReadingsVal($hash->{NAME},"AlarmTime2_Tuesday","off");
                my $time3 = ReadingsVal($hash->{NAME},"AlarmTime3_Wednesday","off");
                my $time4 = ReadingsVal($hash->{NAME},"AlarmTime4_Thursday","off");
                my $time5 = ReadingsVal($hash->{NAME},"AlarmTime5_Friday","off");
                my $time6 = ReadingsVal($hash->{NAME},"AlarmTime6_Saturday","off");
                my $time7 = ReadingsVal($hash->{NAME},"AlarmTime7_Sunday","off");
      
    
                readingsSingleUpdate( $hash, $value,"$time1,$time2,$time3,$time4,$time5,$time6,$time7", 1 );       
        }

    }
    
### load Weekprofile ###    
    
    if ($opt eq "load") 
    {
        if ($value =~ /^(Weekprofile_1|Weekprofile_2|Weekprofile_3|Weekprofile_4|Weekprofile_5)$/)
        {
            my @time = split(/,/, ReadingsVal($hash->{NAME}, $value,""));
      
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "AlarmTime1_Monday", $time[0]);
            readingsBulkUpdate( $hash, "AlarmTime2_Tuesday", $time[1]);
            readingsBulkUpdate( $hash, "AlarmTime3_Wednesday", $time[2]);
            readingsBulkUpdate( $hash, "AlarmTime4_Thursday", $time[3]);
            readingsBulkUpdate( $hash, "AlarmTime5_Friday", $time[4]);
            readingsBulkUpdate( $hash, "AlarmTime6_Saturday", $time[5]);
            readingsBulkUpdate( $hash, "AlarmTime7_Sunday", $time[6]);
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);
    
        }

    }   

### disable ###

    if ($opt eq "disable")
    {
        if ($value eq "1")
        {
            RemoveInternalTimer($hash);
            readingsSingleUpdate( $hash,"state", "deactivated", 1 );
            Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - deactivated";        
        }
        if ($value eq "0")
        {
            readingsSingleUpdate( $hash,"state", "activated", 1 );
            alarmclock_createtimer($hash);
            Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - activated";         
        }
    }   
    

    return undef;
}


########################################################################################
#
#   Alarmclock Attr                                                 
#
########################################################################################

sub alarmclock_Attr(@) 
{

    my ($cmd,$name,$attr_name,$attrVal) = @_;
    my $hash = $defs{$name};

    
    if(($attr_name eq "OffDefaultTime") 
        && ($attrVal =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/))
    {
        InternalTimer(gettimeofday()+1, "alarmclock_createtimer", $hash, 0);
    }
    
    if(($attr_name eq "PreAlarmTimeInSec") 
        && ($attrVal =~ /^([0-9]?[0-9]?[0-9]?[0-9])$/))
    {
        InternalTimer(gettimeofday()+1, "alarmclock_createtimer", $hash, 0);
    }
    
###disable###   

    if($attr_name eq "disable")
    {
        if( $cmd eq "set" )
        {
            if($attrVal eq "1")
            {
                RemoveInternalTimer($hash);
                readingsSingleUpdate( $hash,"state", "deactivated", 1 );
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - deactivated";
            }
            elsif($attrVal eq "0")
            {
                InternalTimer(gettimeofday()+1, "alarmclock_createtimer", $hash, 0);
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - activated";
            }
        }
        elsif( $cmd eq "del" )
        {
            InternalTimer(gettimeofday()+1, "alarmclock_createtimer", $hash, 0);
            Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - activated";
        }   
    }
    
###HolidayCheck###  

    if($attr_name eq "HolidayCheck")
    {
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+1, "alarmclock_createtimer", $hash, 0);
    }   

    

    return undef;
}   


########################################################################################
#
#   Timer für die heutige Alarmzeit wird erstellt
#
########################################################################################

sub alarmclock_createtimer($)
{

    my ($hash) = @_;

    
    my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
    my $alarmtimetoday = $alarmday{$WDayNow};
    my $HourinSec = $HourNow * 3600;
    my $MininSec = $MinNow * 60;
    my $NowinSec = $HourinSec + $MininSec + $SecNow;
    
    

if ((AttrVal($hash->{NAME}, "disable", 0 ) ne "1" ) && (ReadingsVal($hash->{NAME},"state","activated") ne "deactivated"))
{
    
### Check HolidayDevice ###
    
    if ((AttrVal($hash->{NAME}, "HolidayDevice", "NONE" ) ne "NONE" ) && (AttrVal($hash->{NAME}, "HolidayCheck", "1" ) ne "0" ))
    {
        my @HolidayDevice = split(/:/, AttrVal($hash->{NAME},"HolidayDevice",""),3);
        
        if (scalar(@HolidayDevice) eq "1")
        {
            if (ReadingsVal($HolidayDevice[0],"state","none") ne "none")
            {
                $alarmtimetoday = $alarmday{8};
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - holiday";
            }
        }   
        elsif (scalar(@HolidayDevice) eq "2")   
        {   
            if (ReadingsVal($HolidayDevice[0],"state","NONE") eq $HolidayDevice[1])
            {
                $alarmtimetoday = $alarmday{8};
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - holiday";
            }
        }   
        elsif (scalar(@HolidayDevice) eq "3")
        {   
            my $HolidayEvent = $HolidayDevice[2];
                $HolidayEvent =~ s/ //g;
            if (ReadingsVal($HolidayDevice[0],$HolidayDevice[1],"NONE") eq $HolidayEvent)
            {
                $alarmtimetoday = $alarmday{8};
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - holiday";
            }
        }
    }
    
### Ende Holiday ###

    
    if ((ReadingsVal($hash->{NAME},$alarmtimetoday,"NONE")) =~ /^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$/)
    {
        ReadingsVal($hash->{NAME},$alarmtimetoday,"NONE") =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/;
        my $AlarmHour = 0;
        my $AlarmMin = 0;
        $AlarmHour = $1;
        $AlarmMin = $2;
        my $AlarmHourinSec = $AlarmHour * 3600;
        my $AlarmMininSec = $AlarmMin * 60;
        my $AlarminSec = $AlarmHourinSec + $AlarmMininSec;


        
            if($NowinSec < $AlarminSec)
            {
                my $AlarmIn = $AlarminSec - $NowinSec;
                RemoveInternalTimer($hash);
                InternalTimer(gettimeofday()+$AlarmIn, "alarmclock_alarmroutine_start", $hash, 0);
                readingsSingleUpdate( $hash,"state", "next Alarm at $AlarmHour:$AlarmMin", 1 );
                Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - alarm-timer created with $AlarmIn sec";


### Check für Pre-Alarm ###
    
                if((AttrVal($hash->{NAME},"PreAlarmTimeInSec","NONE")) =~ /^([0-9]?[0-9]?[0-9]?[0-9])$/)
                {
                    my $PreAlarmTime = AttrVal($hash->{NAME},"PreAlarmTimeInSec","NONE");
                    
                    if($NowinSec < $AlarminSec - $PreAlarmTime)
                    {
                        my $PreAlarmIn = $AlarmIn - $PreAlarmTime;
                        InternalTimer(gettimeofday()+$PreAlarmIn, "alarmclock_prealarmroutine_start", $hash, 0);
                        Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - pre-alarm timer created with $PreAlarmIn sec";
                    }   
                    else
                    {
                        Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - pre-alarm time has been in the past";
                    }
                }
                else
                {
                    Log3 $hash->{NAME}, 4, "alarmclock: $hash->{NAME} - no PreAlarmTimeInSec is set";
                }   
                
### Ende Pre-Alarm ###

                
            }
            
            else
            {
                alarmclock_midnight_timer($hash);
                Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - alarm time today has been in the past => midnight-timer started.";
            }
    }
    
    
### Check für OffDefaultTime ###    
    
    elsif((ReadingsVal($hash->{NAME},$alarmtimetoday,"NONE")) eq "off")
    {
        if((AttrVal($hash->{NAME},"OffDefaultTime","NONE")) =~ /^([0-9]|0[0-9]|1?[0-9]|2[0-3]):([0-5]?[0-9])$/)
        {
            my $OffDefaultTimeHour = 0;
            my $OffDefaultTimeMin = 0;
            $OffDefaultTimeHour = $1;
            $OffDefaultTimeMin = $2;
            my $OffDefaultTimeHourinSec = $OffDefaultTimeHour * 3600;
            my $OffDefaultTimeMininSec = $OffDefaultTimeMin * 60;
            my $OffDefaultTimeinSec = $OffDefaultTimeHourinSec + $OffDefaultTimeMininSec;
        
            if($NowinSec < $OffDefaultTimeinSec)
            {
                my $OffDefaultTimeIn = $OffDefaultTimeinSec - $NowinSec;
                RemoveInternalTimer($hash);
                InternalTimer(gettimeofday()+$OffDefaultTimeIn, "alarmclock_offroutine_start", $hash, 0);
                readingsSingleUpdate( $hash,"state", "next OffRoutine at $OffDefaultTimeHour:$OffDefaultTimeMin", 1 );
                Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - off-routine-timer created with $OffDefaultTimeIn sec";
            }
            else
            {
                alarmclock_midnight_timer($hash);
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - OffDefaultTime has been in the past";
            }
        }
        else
        {
            alarmclock_midnight_timer($hash);
            Log3 $hash->{NAME}, 4, "alarmclock: $hash->{NAME} - no OffDefaultTime is set";
        }   
    }

### Ende OffDefaultTime ### 
    
    
    else 
    {
        alarmclock_midnight_timer($hash);
        Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - no alarm today => midnight-timer started";
    }
}
    
}


########################################################################################
#
#   Zeit bis Mitternacht wird berrechnet und ein Timer bis Mitternacht + 5Sekunden wird gesetzt         
#
########################################################################################

sub alarmclock_midnight_timer($)
{
    my ($hash) = @_;
    my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
    my $HourinSec = $HourNow * 3600;
    my $MininSec = $MinNow * 60;
    my $NowinSec = $HourinSec + $MininSec + $SecNow;
    my $SectoMidnight = 86405 - $NowinSec;

if ((AttrVal($hash->{NAME}, "disable", 0 ) ne "1" ) && (ReadingsVal($hash->{NAME},"state","activated") ne "deactivated"))
{
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$SectoMidnight, "alarmclock_createtimer", $hash, 0);
    readingsSingleUpdate( $hash,"state", "OK", 1 );
    Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - midnight-timer created with $SectoMidnight sec.";
}
    
}


########################################################################################
#
#   Alarm-Routine wird gestartet 
#
########################################################################################

sub alarmclock_alarmroutine_start($)
{

    my ($hash) = @_;

    fhem("".AttrVal($hash->{NAME},"AlarmRoutine",""));      
    readingsSingleUpdate( $hash,"state", "Alarm is running", 1 );
    alarmclock_hardalarm_timer($hash);
    alarmclock_maxalarmduration_timer($hash);
    Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - AlarmRoutine started.";
    
}


########################################################################################
#
#   Alarm-Routine wird gestoppt
#
########################################################################################

sub alarmclock_alarmroutine_stop($)
{

    my ($hash) = @_;

    fhem("".AttrVal($hash->{NAME},"AlarmRoutineOff",""));       
    readingsSingleUpdate( $hash,"state", "Alarm stopped", 1 );
    Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - alarmroutine stopped.";
    RemoveInternalTimer($hash, "alarmclock_hardalarmroutine_start");
    RemoveInternalTimer($hash, "alarmclock_alarmroutine_stop");
    alarmclock_createtimer($hash);

}


########################################################################################
#
#   Pre-Alarm-Routine wird gestartet 
#
########################################################################################

sub alarmclock_prealarmroutine_start($)
{

    my ($hash) = @_;

    fhem("".AttrVal($hash->{NAME},"PreAlarmRoutine",""));
    readingsSingleUpdate( $hash,"state", "PreAlarm is running", 1 );
    Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - PreAlarmRoutine started.";  

}


########################################################################################
#
#   Alarm Snooze  
#
########################################################################################

sub alarmclock_snooze_start($)
{

    my ($hash) = @_;

    
    if((AttrVal($hash->{NAME},"SnoozeTimeInSec","NONE")) =~ /^([0-9]?[0-9]?[0-9]?[0-9])$/)
    {
        my $SnoozeTime = AttrVal($hash->{NAME},"SnoozeTimeInSec","");
        fhem("".AttrVal($hash->{NAME},"SnoozeRoutine",""));
        InternalTimer(gettimeofday()+$SnoozeTime, "alarmclock_alarmroutine_start", $hash, 0);
        readingsSingleUpdate( $hash,"state", "Snooze for $SnoozeTime sec", 1 );
        RemoveInternalTimer($hash, "alarmclock_hardalarmroutine_start");
        RemoveInternalTimer($hash, "alarmclock_alarmroutine_stop");
        Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - snooze-timer created with $SnoozeTime sec.";
    }

    else
    {
        Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - no SnoozeTimeInSec is set.";
    }   

}


########################################################################################
#
#   Alarm OffRoutine  
#
########################################################################################

sub alarmclock_offroutine_start($)
{

    my ($hash) = @_;

    
    fhem("".AttrVal($hash->{NAME},"OffRoutine",""));
    readingsSingleUpdate( $hash,"state", "OffRoutine is running", 1 );
    alarmclock_createtimer($hash);
    Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - OffRoutine started.";   

}


########################################################################################
#
#   HardAlarm Timer 
#
########################################################################################

sub alarmclock_hardalarm_timer($)
{

    my ($hash) = @_;

    if((AttrVal($hash->{NAME},"HardAlarmTimeInSec","NONE")) =~ /^([0-9]?[0-9]?[0-9]?[0-9])$/)
    {
        my $HardAlarmTime = AttrVal($hash->{NAME},"HardAlarmTimeInSec","");
        InternalTimer(gettimeofday()+$HardAlarmTime, "alarmclock_hardalarmroutine_start", $hash, 0);
        Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - HardAlarm created with $HardAlarmTime sec.";
    }

    else
    {
        Log3 $hash->{NAME}, 4, "alarmclock: $hash->{NAME} - no HardAlarmTimeInSec is set.";
    }
}


########################################################################################
#
#   MaxAlarmDuration 
#
########################################################################################

sub alarmclock_maxalarmduration_timer($)
{

    my ($hash) = @_;

    if((AttrVal($hash->{NAME},"MaxAlarmDurationInSec","NONE")) =~ /^([0-9]?[0-9]?[0-9]?[0-9])$/)
    {
        my $MaxAlarmDuration = AttrVal($hash->{NAME},"MaxAlarmDurationInSec","");
        InternalTimer(gettimeofday()+$MaxAlarmDuration, "alarmclock_alarmroutine_stop", $hash, 0);
        Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - MaxAlarmDuration created with $MaxAlarmDuration sec.";
    }

}

########################################################################################
#
#   HardAlarm wird gestartet
#
########################################################################################

sub alarmclock_hardalarmroutine_start($)
{

    my ($hash) = @_;

    fhem("".AttrVal($hash->{NAME},"HardAlarmRoutine",""));
    Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - HardAlarmRoutine started.";
}



########################################################################################
#
#   Notify
#
########################################################################################

sub alarmclock_Notify($$)
{
  my ($hash, $devhash) = @_;
 
  return "" if(IsDisabled($hash->{NAME})); # Return without any further action if the module is disabled
 
  my $devName = $devhash->{NAME}; # Device that created the events
 
  my $events = deviceEvents($devhash,0);
  return if( !$events );
  
  
### alarmclock_createtimer wird nach dem start von fhem aufgerufen ###
  
    if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
    {
         alarmclock_createtimer($hash);
    }  
  
 
### Notify Alarm off ### 
  
    if((ReadingsVal($hash->{NAME},"state",0)) =~ /^(Alarm is running|Snooze for.*)/)
    {
        if(my @AlarmOffDevice = split(/:/, AttrVal($hash->{NAME},"EventForAlarmOff",""),2))
        {
            if(($devName eq $AlarmOffDevice[0]) && (grep { $AlarmOffDevice[1] eq $_ } @{$events}))
            {
                alarmclock_alarmroutine_stop($hash);
            }
        }
    }
    
    
### Notify Snooze ### 
  
    if((ReadingsVal($hash->{NAME},"state",0)) eq "Alarm is running")
    {
        if(my @SnoozeDevice = split(/:/, AttrVal($hash->{NAME},"EventForSnooze",""),2))
        {
            if(($devName eq $SnoozeDevice[0]) && (grep { $SnoozeDevice[1] eq $_ } @{$events}))
            {
                alarmclock_snooze_start($hash);
            }
        }
    }   
  
}


1;


=pod
=item helper
=item summary    Fhem Modul to set up a Alarmclock
=item summary_DE Fhem Weckermodul 
=begin html

<a name="alarmclock"></a>
<h3>alarmclock</h3>
<ul>
    Fhem Modul to set up a Alarmclock
    <br><br>
    <a name="alarmclock_Define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; alarmclock</code>
        <br>
        Example: <code>define Wecker alarmclock</code>
        <br>
    </ul>
    <br>
    
    <a name="alarmclock_Set"></a>
    <b>Set</b><br>
    <ul>
            <li><b>AlarmTime(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday)</b> HH:MM<br>
                Sets a alarm time for each day.
            </li>
            <li><b>AlarmTime_Weekdays</b> HH:MM<br>
                Sets the same alarm time for each working day.
            </li>
            <li><b>AlarmTime_Weekend</b> HH:MM<br>
                Sets the same alarm time for Saturday and Sunday.
            </li>
            <li><b>AlarmOff</b> (1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|Weekdays|Weekend|All)<br>
                Sets the alarm time of the respective day to off.
            </li>
            <li><b>save</b> (Weekprofile_1|Weekprofile_2|Weekprofile_3|Weekprofile_4|Weekprofile_5)<br>
                Save alarm times in a profile.
            </li>
            <li><b>load</b> (Weekprofile_1|Weekprofile_2|Weekprofile_3|Weekprofile_4|Weekprofile_5)<br>
                Load alarm times from profile.
            </li>
            <li><b>disable</b> (1|0|)<br>
                Deactivated/Activated the alarmclock.
            </li>           
    </ul>
    <br>

    <br>
    
    <a name="alarmclock_Attr"></a>
    <b>Attributes</b>
    <ul>
            <li><b>AlarmRoutine</b> <br>
                A list separated by semicolon (;) which Fhem should run at the alarm time.<br>
                Example: attr &lt;name&gt; AlarmRoutine set Licht on;set Radio on
            </li>
            <li><b>AlarmRoutineOff</b> <br>
                A list separated by semicolon (;) which Fhem should execute to terminate the alarm.<br> 
                Example: attr &lt;name&gt; AlarmRoutineOff set Licht off;set Radio off
            </li>
            <li><b>EventForAlarmOff</b> <br>
                Fhem-event to end the alarm.<br>
                There are 2 possibilities:<br>
                1.Trigger on state.<br>
                &lt;devicename&gt;:&lt;state&gt; Example: attr &lt;name&gt; EventForAlarmOff Taster:off <br>
                2.Trigger on reading. <br>
                &lt;devicename&gt;:&lt;readingname&gt;: &lt;value&gt; Example: attr &lt;name&gt; EventForAlarmOff Taster:cSceneSet: on <br>
            </li>
            <li><b>EventForSnooze</b> <br>
                Fhem-event to interrupt the alarm.<br>
                The syntax is identical to EventForAlarmOff.<br>
                Example: attr &lt;name&gt; EventForSnooze Taster:cSceneSet: off <br>
            </li>
            <li><b>SnoozeRoutine</b> <br>
                A list separated by semicolon (;) which Fhem operate to interrupt the running alarm.<br>
                Example: attr &lt;name&gt; SnoozeRoutine set Licht off;set Radio off
            </li>
            <li><b>SnoozeTimeInSec</b> <br>
                Time in seconds how long the alarm should be interrupted.<br>
                Example: attr &lt;name&gt; SnoozeTimeInSec 240 <br>
            </li>
            <li><b>PreAlarmRoutine</b> <br>
                A list separated by semicolon (;) which Fhem operate at the pre-alarm.<br>
                Example: attr &lt;name&gt; PreAlarmRoutine set Licht dim 30;set Radio on
            </li>
            <li><b>PreAlarmTimeInSec</b> <br>
                Time in seconds between the alarm and the pre-alarm.<br>
                Example: attr &lt;name&gt; PreAlarmTimeInSec 300<br>
                In the example, the PreAlarmRoutine is executed 5 minutes before the regular alarm.
            </li>
            <li><b>HardAlarmRoutine</b> <br>
                A list separated by semicolon (;) which is to be executed to force the awakening.<br>
                Example: attr &lt;name&gt; HardAlarmRoutine set Sonos_Schlafzimmer Volume 40;set Licht dim 90
            </li>
            <li><b>HardAlarmTimeInSec</b> <br>
                Here you can specify in seconds how long the alarm can "run" until HardAlarmRoutine is started.<br>
                Example: attr &lt;name&gt; HardAlarmTimeInSec 300
            </li>
            <li><b>OffRoutine</b> <br>
                A list separated by semicolon (;) which Fhem operate at the OffDefaultTime.<br>
                Example: attr &lt;name&gt; OffRoutine set rr_Florian home;set Heizung on
            </li>
            <li><b>OffDefaultTime</b> <br>
                Default time for the OffRoutine.<br>
                Example: attr &lt;name&gt; OffDefaultTime 07:30
            </li>
            <li><b>MaxAlarmDurationInSec</b> <br>
                Duration in seconds to stop automatically the running alarm.<br>
                Example: attr &lt;name&gt;  MaxAlarmDurationInSec 120
            </li>
            <li><b>HolidayDevice</b> <br>
                Name of the holiday device.<br>
            </li>
            <li><b>HolidayCheck</b> <br>
                0 disables monitoring the holiday device<br>
                1 activates monitoring
            </li>
            <li><b>disable</b> <br>
                1 disables all alarms<br>
                0 activates this again
            </li>
    </ul>
</ul>

=end html

=cut

# $Id$
########################################################################################
#
#  98_alarmclock.pm
#  Fhem Modul to set up a Alarmclock
#
#  2017 Florian Zetlmeisl
#
#  Parts of the holiday and vacation identification
#  are written by Prof. Dr. Peter A. Henning
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
    "AlarmTime9_Vacation"   => "10:00",
    "AlarmOff"              => "NONE",
    "AlarmTime_Weekdays"    => "09:00",
    "AlarmTime_Weekend"     => "09:00",
    "stop"                  => "NONE",
    "skip"                  => "NONE",
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
    "8"     => "AlarmTime8_Holiday",
    "9"     => "AlarmTime9_Vacation"

);


my @mapping_attrs =
qw(
    AlarmRoutine:textField-long
    AlarmRoutineOff:textField-long
    PreAlarmRoutine:textField-long
    OffRoutine:textField-long
    HardAlarmRoutine:textField-long
    SnoozeRoutine:textField-long
    RepRoutine1:textField-long
    RepRoutine2:textField-long
    RepRoutine3:textField-long
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
                        . " HolidayDays"
                        . " VacationDevice"
                        . " VacationCheck:1,0"
                        . " VacationDays"
                        . " PresenceDevice"
                        . " PresenceCheck:1,0"
                        . " RepRoutine1"
                        . " RepRoutine1WaitInSec"
                        . " RepRoutine1Repeats"
                        . " RepRoutine1Mode:Alarm,PreAlarm,off"
                        . " RepRoutine1Stop:Snooze,off"
                        . " RepRoutine2"
                        . " RepRoutine2WaitInSec"
                        . " RepRoutine2Repeats"
                        . " RepRoutine2Mode:Alarm,PreAlarm,off"
                        . " RepRoutine2Stop:Snooze,off"
                        . " RepRoutine3"
                        . " RepRoutine3WaitInSec"
                        . " RepRoutine3Repeats"
                        . " RepRoutine3Mode:Alarm,PreAlarm,off"
                        . " RepRoutine3Stop:Snooze,off"
                        . " WeekprofileName"
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

  $hash->{helper}{Repeat1} = 0;
  $hash->{helper}{Repeat2} = 0;
  $hash->{helper}{Repeat3} = 0;
  $hash->{helper}{Today} = 0;
  $hash->{helper}{Tomorrow} = 0;

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

    my $Weekprofile = AttrVal($hash->{NAME},"WeekprofileName","Weekprofile_1,Weekprofile_2,Weekprofile_3,Weekprofile_4,Weekprofile_5");

    if(!defined($alarmclock_sets{$opt})) {
        my $list =   " AlarmTime1_Monday"
                    ." AlarmTime2_Tuesday"
                    ." AlarmTime3_Wednesday"
                    ." AlarmTime4_Thursday"
                    ." AlarmTime5_Friday"
                    ." AlarmTime6_Saturday"
                    ." AlarmTime7_Sunday"
                    ." AlarmTime8_Holiday"
                    ." AlarmTime9_Vacation"
                    ." AlarmOff:1_Monday,2_Tuesday,3_Wednesday,4_Thursday,5_Friday,6_Saturday,7_Sunday,8_Holiday,9_Vacation,Weekdays,Weekend,All"
                    ." AlarmTime_Weekdays"
                    ." AlarmTime_Weekend"
                    ." stop:Alarm"
                    ." skip:NextAlarm,None"
                    ." save:$Weekprofile"
                    ." load:$Weekprofile"
                    ." disable:1,0";


        return "Unknown argument $opt, choose one of $list";
    }



### AlarmTime ###

    if ($opt =~ /^AlarmTime(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|9_Vacation)/)
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
        if ($value =~ /^(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|9_Vacation)$/)
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
            readingsBulkUpdate( $hash, "AlarmTime9_Vacation", "off");
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);
        }
        elsif (!($value =~ /^(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|9_Vacation|Weekdays|Weekend|All)$/))
        {
            return "Please Set $opt (1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|9_Vacation|Weekdays|Weekend|All)";
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

### stop Alarm ###

    if ($opt eq "stop")
    {
        if (($value eq "Alarm") && ((ReadingsVal($hash->{NAME},"state",0)) =~ /^(Alarm is running|PreAlarm is running|Snooze for.*)/))
        {
            alarmclock_alarmroutine_stop($hash);
        }
    }


### save Weekprofile ###

    if ($opt eq "save")
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

### load Weekprofile ###

    if ($opt eq "load")
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

### skip ###

    if ($opt eq "skip")
    {
        if ($value eq "NextAlarm")
        {
            readingsBeginUpdate($hash);
            readingsBulkUpdate( $hash, "state", "skip next Alarm");
            readingsBulkUpdate( $hash, "skip", "next Alarm");
            readingsEndUpdate($hash,1);
            alarmclock_createtimer($hash);
        }
        if ($value eq "None")
        {
            readingsSingleUpdate( $hash, "skip", "none", 1 );
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

###Holiday###

    if($attr_name eq "HolidayCheck")
    {
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+1, "alarmclock_createtimer", $hash, 0);
    }

###Vacation###

    if($attr_name eq "VacationCheck")
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

    $hash->{helper}{Today} = $WDayNow;

    if ($WDayNow =~ /^(0|1|2|3|4|5)/)
    {
        $hash->{helper}{Tomorrow} = $WDayNow + 1;
    }
    else
    {
        $hash->{helper}{Tomorrow} = 0;
    }

    my $HourinSec = $HourNow * 3600;
    my $MininSec = $MinNow * 60;
    my $NowinSec = $HourinSec + $MininSec + $SecNow;



if ((AttrVal($hash->{NAME}, "disable", 0 ) ne "1" ) && (ReadingsVal($hash->{NAME},"state","activated") ne "deactivated"))
{


### Vacation ###
    alarmclock_vacation_check($hash);

### Holiday ###
    alarmclock_holiday_check($hash);

    my $alarmtimetoday = $alarmday{$hash->{helper}{Today}};
    my $alarmtimetomorrow = $alarmday{$hash->{helper}{Tomorrow}};


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



            if(($NowinSec < $AlarminSec) && (ReadingsVal($hash->{NAME},"skip","none") eq "none"))
            {
                my $AlarmIn = $AlarminSec - $NowinSec;
                RemoveInternalTimer($hash);
                InternalTimer(gettimeofday()+$AlarmIn, "alarmclock_alarmroutine_start", $hash, 0);
                readingsSingleUpdate( $hash,"state", "next Alarm at $AlarmHour:$AlarmMin", 1 );
                Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - alarm-timer created with $AlarmIn sec";


### PreAlarm ###

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

### End PreAlarm ###

            }

### skip next Alarmtime ###

            elsif(($NowinSec < $AlarminSec) && (ReadingsVal($hash->{NAME},"skip","none") ne "none"))
            {
                my $AlarmIn2 = $AlarminSec - $NowinSec;
                RemoveInternalTimer($hash);
                InternalTimer(gettimeofday()+$AlarmIn2, "alarmclock_skip", $hash, 0);
                Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - skip next Alarm";
            }
### End skip next Alarmtime ###

            else
            {
                alarmclock_midnight_timer($hash);
                Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - alarm time today has been in the past => midnight-timer started.";
            }
    }


### OffDefaultTime ###

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

### End OffDefaultTime ###

    else
    {
        alarmclock_midnight_timer($hash);
        Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - no alarm today => midnight-timer started";
    }

### Alarm Reading ###

    my $AlarmToday = ReadingsVal($hash->{NAME},$alarmtimetoday," ");
    my $AlarmTomorrow = ReadingsVal($hash->{NAME},$alarmtimetomorrow," ");
    readingsBeginUpdate($hash);
    readingsBulkUpdate( $hash, "AlarmToday", $AlarmToday);
    readingsBulkUpdate( $hash, "AlarmTomorrow", $AlarmTomorrow);
    readingsEndUpdate($hash,1);

}

}


########################################################################################
#
#   Midnight-timer + 5 seconds
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
    Log3 $hash->{NAME}, 5, "alarmclock: $hash->{NAME} - midnight-timer created with $SectoMidnight sec.";
    if (ReadingsVal($hash->{NAME},"skip","none") ne "none")
    {
        readingsSingleUpdate( $hash, "state", "skip next Alarm", 1);
    }
    else
    {
        readingsSingleUpdate( $hash,"state", "OK", 1 );
    }
}

}


########################################################################################
#
#   Alarm-Routine start
#
########################################################################################

sub alarmclock_alarmroutine_start($)
{

    my ($hash) = @_;
    my $Mode = "Alarm";

    if (alarmclock_presence_check($hash))
    {
        fhem("".AttrVal($hash->{NAME},"AlarmRoutine",""));
        readingsSingleUpdate( $hash,"state", "Alarm is running", 1 );
        alarmclock_hardalarm_timer($hash);
        alarmclock_maxalarmduration_timer($hash);
        alarmclock_reproutine($hash, $Mode);
        Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - AlarmRoutine started.";
    }
    else
    {
        alarmclock_createtimer($hash);
    }
}


########################################################################################
#
#   Alarm-Routine stop
#
########################################################################################

sub alarmclock_alarmroutine_stop($)
{

    my ($hash) = @_;

    fhem("".AttrVal($hash->{NAME},"AlarmRoutineOff",""));
    readingsSingleUpdate( $hash,"state", "Alarm stopped", 1 );
    Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - alarmroutine stopped.";
    RemoveInternalTimer($hash);
    alarmclock_midnight_timer($hash);

}


########################################################################################
#
#   Pre-Alarm-Routine start
#
########################################################################################

sub alarmclock_prealarmroutine_start($)
{

    my ($hash) = @_;
    my $Mode = "PreAlarm";

    if (alarmclock_presence_check($hash))
    {
        fhem("".AttrVal($hash->{NAME},"PreAlarmRoutine",""));
        readingsSingleUpdate( $hash,"state", "PreAlarm is running", 1 );
        alarmclock_reproutine($hash, $Mode);
        Log3 $hash->{NAME}, 3, "alarmclock: $hash->{NAME} - PreAlarmRoutine started.";
    }
}


########################################################################################
#
#   Alarm Snooze
#
########################################################################################

sub alarmclock_snooze_start($)
{

    my ($hash) = @_;
    my $Mode = "Snooze";

    if((AttrVal($hash->{NAME},"SnoozeTimeInSec","NONE")) =~ /^([0-9]?[0-9]?[0-9]?[0-9])$/)
    {
        my $SnoozeTime = AttrVal($hash->{NAME},"SnoozeTimeInSec","");
        fhem("".AttrVal($hash->{NAME},"SnoozeRoutine",""));
        InternalTimer(gettimeofday()+$SnoozeTime, "alarmclock_alarmroutine_start", $hash, 0);
        readingsSingleUpdate( $hash,"state", "Snooze for $SnoozeTime sec", 1 );
        RemoveInternalTimer($hash, "alarmclock_hardalarmroutine_start");
        RemoveInternalTimer($hash, "alarmclock_alarmroutine_stop");
        alarmclock_reproutine_stop($hash, $Mode);
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
#   HardAlarm start
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
#   RepRoutine
#
########################################################################################

sub alarmclock_reproutine($$)
{

    my ($hash, $Mode) = @_;

    if(((AttrVal($hash->{NAME},"RepRoutine1","NONE")) ne "NONE") &&
        (AttrVal($hash->{NAME},"RepRoutine1Mode","off")) eq $Mode)
    {
        $hash->{helper}{Repeat1} = 0;
        my $WaitTime1 = AttrVal($hash->{NAME},"RepRoutine1WaitInSec","10");
        InternalTimer(gettimeofday()+$WaitTime1, "alarmclock_reproutine1_start", $hash, 0);
    }
    if(((AttrVal($hash->{NAME},"RepRoutine2","NONE")) ne "NONE") &&
        (AttrVal($hash->{NAME},"RepRoutine2Mode","off")) eq $Mode)
    {
        $hash->{helper}{Repeat2} = 0;
        my $WaitTime2 = AttrVal($hash->{NAME},"RepRoutine2WaitInSec","10");
        InternalTimer(gettimeofday()+$WaitTime2, "alarmclock_reproutine2_start", $hash, 0);
    }
    if(((AttrVal($hash->{NAME},"RepRoutine3","NONE")) ne "NONE") &&
        (AttrVal($hash->{NAME},"RepRoutine3Mode","off")) eq $Mode)
    {
        $hash->{helper}{Repeat3} = 0;
        my $WaitTime3 = AttrVal($hash->{NAME},"RepRoutine3WaitInSec","10");
        InternalTimer(gettimeofday()+$WaitTime3, "alarmclock_reproutine3_start", $hash, 0);
    }

}


########################################################################################
#
#   RepRoutine stop
#
########################################################################################

sub alarmclock_reproutine_stop($$)
{

    my ($hash, $Mode) = @_;

    if((AttrVal($hash->{NAME},"RepRoutine1Stop","Snooze")) eq $Mode)
    {
        RemoveInternalTimer($hash, "alarmclock_reproutine1_start");
    }
    if((AttrVal($hash->{NAME},"RepRoutine2Stop","Snooze")) eq $Mode)
    {
        RemoveInternalTimer($hash, "alarmclock_reproutine2_start");
    }
    if((AttrVal($hash->{NAME},"RepRoutine3Stop","Snooze")) eq $Mode)
    {
        RemoveInternalTimer($hash, "alarmclock_reproutine3_start");
    }

}


########################################################################################
#
#   RepRoutine1 start
#
########################################################################################

sub alarmclock_reproutine1_start($)
{

    my ($hash) = @_;

    my $WaitTime = AttrVal($hash->{NAME},"RepRoutine1WaitInSec","10");
    my $Repeats = AttrVal($hash->{NAME},"RepRoutine1Repeats","2");
    my $RNow = $hash->{helper}{Repeat1};

    if ($Repeats > $RNow)
    {
        my $RNext = $RNow + 1;
        $hash->{helper}{Repeat1} = $RNext;
        fhem("".AttrVal($hash->{NAME},"RepRoutine1",""));
        InternalTimer(gettimeofday()+$WaitTime, "alarmclock_reproutine1_start", $hash, 0);
    }

}


########################################################################################
#
#   RepRoutine2 start
#
########################################################################################

sub alarmclock_reproutine2_start($)
{

    my ($hash) = @_;

    my $WaitTime = AttrVal($hash->{NAME},"RepRoutine2WaitInSec","10");
    my $Repeats = AttrVal($hash->{NAME},"RepRoutine2Repeats","2");
    my $RNow = $hash->{helper}{Repeat2};

    if ($Repeats > $RNow)
    {
        my $RNext = $RNow + 1;
        $hash->{helper}{Repeat2} = $RNext;
        fhem("".AttrVal($hash->{NAME},"RepRoutine2",""));
        InternalTimer(gettimeofday()+$WaitTime, "alarmclock_reproutine2_start", $hash, 0);
    }

}


########################################################################################
#
#   RepRoutine3 start
#
########################################################################################

sub alarmclock_reproutine3_start($)
{

    my ($hash) = @_;

    my $WaitTime = AttrVal($hash->{NAME},"RepRoutine3WaitInSec","10");
    my $Repeats = AttrVal($hash->{NAME},"RepRoutine3Repeats","2");
    my $RNow = $hash->{helper}{Repeat3};

    if ($Repeats > $RNow)
    {
        my $RNext = $RNow + 1;
        $hash->{helper}{Repeat3} = $RNext;
        fhem("".AttrVal($hash->{NAME},"RepRoutine3",""));
        InternalTimer(gettimeofday()+$WaitTime, "alarmclock_reproutine3_start", $hash, 0);
    }

}

########################################################################################
#
#   Presence Check
#
########################################################################################

sub alarmclock_presence_check($)
{

    my ($hash) = @_;

    if ((AttrVal($hash->{NAME}, "PresenceDevice", "NONE" ) ne "NONE" ) && (AttrVal($hash->{NAME}, "PresenceCheck", "1" ) ne "0" ))
    {
        my @Presence = split(/\|/, AttrVal($hash->{NAME},"PresenceDevice",""));

        my $a = 0;
        my $b = scalar(@Presence);

        while ($a < $b)
        {

            my @PresenceDevice = split(/:/,$Presence[$a]);

            if (scalar(@PresenceDevice) eq "1")
            {
                if (ReadingsVal($PresenceDevice[0],"state","present") ne "present")
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - absent";
                    return 0;
                }
            }
            elsif (scalar(@PresenceDevice) eq "2")
            {
                if (ReadingsVal($PresenceDevice[0],"state","NONE") eq $PresenceDevice[1])
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - absent";
                    return 0;
                }
            }
            elsif (scalar(@PresenceDevice) eq "3")
            {
                my $PresenceEvent = $PresenceDevice[2];
                    $PresenceEvent =~ s/ //g;
                if (ReadingsVal($PresenceDevice[0],$PresenceDevice[1],"NONE") eq $PresenceEvent)
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - absent";
                    return 0;
                }
            }

            $a ++;

        }
    }
    return 1;

}


########################################################################################
#
#   Holiday Check
#
########################################################################################

sub alarmclock_holiday_check($)
{

    my ($hash) = @_;
    my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
    my $WDayToday = $WDayNow;
    my $WDayTomorrow = $WDayNow + 1;
    if ($WDayToday == 0)
    {
        $WDayToday = 7;
    }

    if ((AttrVal($hash->{NAME}, "HolidayDevice", "NONE" ) ne "NONE" ) && (AttrVal($hash->{NAME}, "HolidayCheck", "1" ) ne "0" ))
    {
        my @HolidayDays = split(/\|/, AttrVal($hash->{NAME},"HolidayDays","1|2|3|4|5|6|7"));
        my $DayToday = grep {$_==$WDayToday;} @HolidayDays;
        my $DayTomorrow = grep {$_==$WDayTomorrow;} @HolidayDays;
        my @Holiday = split(/\|/, AttrVal($hash->{NAME},"HolidayDevice",""));
        my $a = 0;
        my $b = scalar(@Holiday);

        while ($a < $b)
        {
            my @HolidayDevice = split(/:/,$Holiday[$a]);

            if (scalar(@HolidayDevice) eq "1")
            {
                if( IsDevice( $HolidayDevice[0], "holiday" ))
                {
                    my $today = strftime("%2m-%2d", localtime(time));
                    my $tomorrow = strftime("%2m-%2d", localtime(time+86400));
                    my $todayevent = holiday_refresh($HolidayDevice[0],$today);
                    if (($todayevent ne "none") && ($DayToday == 1))
                    {
                        Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - holiday => $HolidayDevice[0] - $todayevent";
                        $hash->{helper}{Today} = 8;
                    }
                    my $tomorrowevent = holiday_refresh($HolidayDevice[0],$tomorrow);
                    if (($tomorrowevent ne "none") && ($DayTomorrow == 1))
                    {
                        $hash->{helper}{Tomorrow} = 8;
                    }
                }
                elsif( IsDevice($HolidayDevice[0], "Calendar" ))
                {
                    my $stoday = strftime("%2d.%2m.20%2y", localtime(time));
                    my $stomorrow = strftime("%2d.%2m.20%2y", localtime(time+86400));
                    my $line = Calendar_Get($defs{$HolidayDevice[0]},"get","events","format:text");
                    if ($line)
                    {
                        chomp($line);
                        my @lines = split('\n',$line);
                        foreach $line (@lines)
                        {
                            chomp($line);
                            my $date = substr($line,0,10);
                            if (($date eq $stoday) && ($DayToday == 1))
                            {
                                my $todaydesc = substr($line,15);
                                Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - holiday => $HolidayDevice[0] - $todaydesc";
                                $hash->{helper}{Today} = 8;
                            }
                            if (($date eq $stomorrow) && ($DayTomorrow == 1))
                            {
                                $hash->{helper}{Tomorrow} = 8;
                            }
                        }
                    }
                }
            }
            elsif (scalar(@HolidayDevice) eq "2")
            {
                if ((ReadingsVal($HolidayDevice[0],"state","NONE") eq $HolidayDevice[1]) && ($DayToday == 1))
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - holiday => $HolidayDevice[0] - $HolidayDevice[1]";
                    $hash->{helper}{Today} = 8;
                }
            }
            elsif (scalar(@HolidayDevice) eq "3")
            {
                my $HolidayEvent = $HolidayDevice[2];
                $HolidayEvent =~ s/ //g;
                if ((ReadingsVal($HolidayDevice[0],$HolidayDevice[1],"NONE") eq $HolidayEvent) && ($DayToday == 1))
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - holiday => $HolidayDevice[0] - $HolidayDevice[1] - $HolidayEvent";
                    $hash->{helper}{Today} = 8;
                }
            }
            $a ++;
        }
    }
}


########################################################################################
#
#   Vacation Check
#
########################################################################################

sub alarmclock_vacation_check($)
{

    my ($hash) = @_;
    my ($SecNow, $MinNow, $HourNow, $DayNow, $MonthNow, $YearNow, $WDayNow, $YDNow, $SumTimeNow) = localtime(time);
    my $WDayToday = $WDayNow;
    my $WDayTomorrow = $WDayNow + 1;
    if ($WDayToday == 0)
    {
        $WDayToday = 7;
    }

    if ((AttrVal($hash->{NAME}, "VacationDevice", "NONE" ) ne "NONE" ) && (AttrVal($hash->{NAME}, "VacationCheck", "1" ) ne "0" ))
    {

        my @VacationDays = split(/\|/, AttrVal($hash->{NAME},"VacationDays","1|2|3|4|5|6|7"));
        my $DayToday = grep {$_==$WDayToday;} @VacationDays;
        my $DayTomorrow = grep {$_==$WDayTomorrow;} @VacationDays;
        my @Vacation = split(/\|/, AttrVal($hash->{NAME},"VacationDevice",""));
        my $a = 0;
        my $b = scalar(@Vacation);

        while ($a < $b)
        {
            my @VacationDevice = split(/:/,$Vacation[$a]);

            if (scalar(@VacationDevice) eq "1")
            {
                if( IsDevice( $VacationDevice[0], "holiday" ))
                {
                    my $today = strftime("%2m-%2d", localtime(time));
                    my $tomorrow = strftime("%2m-%2d", localtime(time+86400));
                    my $todayevent = holiday_refresh($VacationDevice[0],$today);
                    if (($todayevent ne "none") && ($DayToday == 1))
                    {
                        Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - vacation => $VacationDevice[0] - $todayevent";
                        $hash->{helper}{Today} = 9;
                    }
                    my $tomorrowevent = holiday_refresh($VacationDevice[0],$tomorrow);
                    if (($tomorrowevent ne "none") && ($DayTomorrow == 1))
                    {
                        $hash->{helper}{Tomorrow} = 9;
                    }
                }
                elsif( IsDevice($VacationDevice[0], "Calendar" ))
                {
                    my $stoday = strftime("%2d.%2m.%2y", localtime(time));
                    my $stomorrow = strftime("%2d.%2m.%2y", localtime(time+86400));
                    my @tday = split('\.',$stoday);
                    my @tmor = split('\.',$stomorrow);
                    my $fline = Calendar_Get($defs{$VacationDevice[0]},"get","events","format:full");
                    my @lines = split('\n',$fline);
                    foreach $fline (@lines)
                    {
                        chomp($fline);
                        my @chunks = split(' ',$fline);
                        my @sday = split('\.',$chunks[2]);
                        my @eday = split('\.',substr($chunks[3],6,10));
                        my $rets = ($sday[2]-$tday[2]-2000)*365+($sday[1]-$tday[1])*31+($sday[0]-$tday[0]);
                        my $rete = ($eday[2]-$tday[2]-2000)*365+($eday[1]-$tday[1])*31+($eday[0]-$tday[0]);
                        if (($rete>=0) && ($rets<=0) && ($DayToday == 1))
                        {
                            my $todaydesc = $chunks[5];
                            Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - vacation => $VacationDevice[0] - $todaydesc";
                            $hash->{helper}{Today} = 9;
                        }
                        $rets = ($sday[2]-$tmor[2]-2000)*365+($sday[1]-$tmor[1])*31+($sday[0]-$tmor[0]);
                        $rete = ($eday[2]-$tmor[2]-2000)*365+($eday[1]-$tmor[1])*31+($eday[0]-$tmor[0]);
                        if (($rete>=0) && ($rets<=0) && ($DayTomorrow == 1))
                        {
                            $hash->{helper}{Tomorrow} = 9;
                        }
                    }
                }
            }
            elsif (scalar(@VacationDevice) eq "2")
            {
                if ((ReadingsVal($VacationDevice[0],"state","NONE") eq $VacationDevice[1]) && ($DayToday == 1))
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - vacation => $VacationDevice[0] - $VacationDevice[1]";
                    $hash->{helper}{Today} = 9;
                }
            }
            elsif (scalar(@VacationDevice) eq "3")
            {
                my $VacationEvent = $VacationDevice[2];
                $VacationEvent =~ s/ //g;
                if ((ReadingsVal($VacationDevice[0],$VacationDevice[1],"NONE") eq $VacationEvent)&& ($DayToday == 1))
                {
                    Log3 $hash->{NAME}, 1, "alarmclock: $hash->{NAME} - vacation => $VacationDevice[0] - $VacationDevice[1] - $VacationEvent";
                    $hash->{helper}{Today} = 9;
                }
            }
            $a ++;
        }
    }
}



########################################################################################
#
#   skip
#
########################################################################################

sub alarmclock_skip($)
{
    my ($hash) = @_;

    readingsSingleUpdate( $hash, "skip", "none", 1 );
    alarmclock_createtimer($hash);

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

    if((ReadingsVal($hash->{NAME},"state",0)) =~ /^(Alarm is running|PreAlarm is running|Snooze for.*)/)
    {
        if(my @AlarmOffDevice = split(/\|/, AttrVal($hash->{NAME},"EventForAlarmOff","")))
        {
            foreach my $AlarmOffDevice(@AlarmOffDevice)
            {
                my @AlarmOffDevicePart = split(/:/, $AlarmOffDevice,2);
                if(($devName eq $AlarmOffDevicePart[0]) && (grep { $AlarmOffDevicePart[1] eq $_ } @{$events}))
                {
                    alarmclock_alarmroutine_stop($hash);
                }
            }
        }
    }


### Notify Snooze ###

    if((ReadingsVal($hash->{NAME},"state",0)) eq "Alarm is running")
    {
        if(my @SnoozeDevice = split(/\|/, AttrVal($hash->{NAME},"EventForSnooze","")))
        {
            foreach my $SnoozeDevice(@SnoozeDevice)
            {
                my @SnoozeDevicePart = split(/:/, $SnoozeDevice,2);
                if(($devName eq $SnoozeDevicePart[0]) && (grep { $SnoozeDevicePart[1] eq $_ } @{$events}))
                {
                    alarmclock_snooze_start($hash);
                }
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
            <li><b>AlarmTime(1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|9_Vacation)</b> HH:MM<br>
                Sets a alarm time for each day.
            </li>
            <li><b>AlarmTime_Weekdays</b> HH:MM<br>
                Sets the same alarm time for each working day.
            </li>
            <li><b>AlarmTime_Weekend</b> HH:MM<br>
                Sets the same alarm time for Saturday and Sunday.
            </li>
            <li><b>AlarmOff</b> (1_Monday|2_Tuesday|3_Wednesday|4_Thursday|5_Friday|6_Saturday|7_Sunday|8_Holiday|9_Vacation|Weekdays|Weekend|All)<br>
                Sets the alarm time of the respective day to off.
            </li>
            <li><b>stop</b> (Alarm)<br>
                Stops a running alarm.
            </li>
            <li><b>save</b> (Weekprofile_1|Weekprofile_2|Weekprofile_3|Weekprofile_4|Weekprofile_5)<br>
                Save alarm times in a profile.
            </li>
            <li><b>load</b> (Weekprofile_1|Weekprofile_2|Weekprofile_3|Weekprofile_4|Weekprofile_5)<br>
                Load alarm times from profile.
            </li>
            <li><b>skip</b> (NextAlarm|None)<br>
                Skips the next alarm.
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
            <li><b>RepRoutine</b> <br>
                A list separated by semicolon (;) which is to be repeated.<br>
                Example: attr &lt;name&gt;  RepRoutine1 set Licht_Schlafzimmer dim 1
            </li>
            <li><b>RepRoutineWaitInSec</b> <br>
                Time in seconds between the repetitions from RepRoutine.<br>
                Example: attr &lt;name&gt;  RepRoutine1WaitInSec 20
            </li>
            <li><b>RepRoutineRepeats</b> <br>
                Number of repetitions of RepRoutine.<br>
                Example: attr &lt;name&gt;  RepRoutine1Repeats 15
            </li>
            <li><b>RepRoutineMode(Alarm|PreAlarm|off)</b> <br>
                Alarm:Reproutine is started with the alarm.<br>
                PreAlarm:Reproutine is started with the pre-alarm.<br>
                off:Reproutine is deactivated.
            </li>
            <li><b>RepRoutineStop(Snooze|off)</b> <br>
                Snooze:Reproutine is stopped with snooze.<br>
                off:Reproutine is not stopped with snooze.
            </li>
            <li><b>HolidayDevice</b> <br>
                Name of the holiday device.<br>
                There are 3 possibilities:<br>
                1.holiday device from typ holiday or Calendar.<br>
                &lt;devicename&gt;<br>
                Example: attr &lt;name&gt; HolidayDevice Feiertage <br>
                2.On state of a device.For example a dummy <br>
                &lt;devicename&gt;:&lt;value&gt; <br>
                Example: attr &lt;name&gt; HolidayDevice MyDummy:Holiday <br>
                Here the AlarmTime 8_Holiday takes effect when the state of the dummy has the value Holiday <br>
                3.On a reading of a device. <br>
                &lt;devicename&gt;:&lt;readingname&gt;:&lt;value&gt;<br>
                Example: attr &lt;name&gt; HolidayDevice MyDummy:Today:Holiday <br>
            </li>
            <li><b>HolidayCheck</b> <br>
                0 disables monitoring the holiday device<br>
                1 activates monitoring
            </li>
            <li><b>HolidayDays</b> <br>
                List of days on which the alarmtime 8_Holiday may take effect<br>
                Example: attr &lt;name&gt;  HolidayDays 1|2|3|4|5 <br>
                Default: 1|2|3|4|5|6|7
            </li>
            <li><b>VacationDevice</b> <br>
                Name of the vacation device.<br>
                There are 3 possibilities:<br>
                1.vacation device from typ holiday or Calendar.<br>
                &lt;devicename&gt; <br>
                Example: attr &lt;name&gt; VacationDevice Ferien <br>
                2.On state of a device.For example a dummy <br>
                &lt;devicename&gt;:&lt;value&gt; <br>
                Example: attr &lt;name&gt; VacationDevice MyDummy:Vacation <br>
                Here the AlarmTime 9_Vacation takes effect when the state of the dummy has the value Vacation <br>
                3.On a reading of a device. <br>
                &lt;devicename&gt;:&lt;readingname&gt;:&lt;value&gt; <br>
                Example: attr &lt;name&gt; VacationDevice MyDummy:Today:Vacation <br>
            </li>
            <li><b>VacationCheck</b> <br>
                0 disables monitoring the vacation device<br>
                1 activates monitoring
            </li>
            <li><b>VacationDays</b> <br>
                List of days on which the alarmtime 9_Vacation may take effect<br>
                Example: attr &lt;name&gt;  VacationDays 1|2|3|4|5 <br>
                Default: 1|2|3|4|5|6|7
            </li>
            <li><b>PresenceDevice</b> <br>
                Name of the presence device.<br>
                There are 3 possibilities:<br>
                1.presence device from Typ presence.<br>
                &lt;devicename&gt; <br>
                Example: attr &lt;name&gt; PresenceDevice Presence <br>
                Alarmclock cancel alarm when state is absent <br>
                2.On state of a device.For example a dummy <br>
                &lt;devicename&gt;:&lt;value&gt; <br>
                Example: attr &lt;name&gt; PresenceDevice MyDummy:absent <br>
                Here the Alarmclock cancel alarm when the state of the dummy has the value absent <br>
                3.On a reading of a device. <br>
                &lt;devicename&gt;:&lt;readingname&gt;:&lt;value&gt; <br>
                Example: attr &lt;name&gt; PresenceDevice MyDummy:user:notathome <br>
            </li>
            <li><b>PresenceCheck</b> <br>
                0 disables monitoring the presence device<br>
                1 activates monitoring
            </li>
            <li><b>WeekprofileName</b> <br>
                Optional list with name for storing the week profiles<br>
                Example: attr &lt;name&gt;  WeekprofileName MyWeek1,MyWeek2,MyWeek3 <br>
            </li>
            <li><b>disable</b> <br>
                1 disables all alarms<br>
                0 activates this again
            </li>
    </ul>
</ul>

=end html

=cut

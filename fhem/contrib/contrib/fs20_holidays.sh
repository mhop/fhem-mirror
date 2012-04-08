#!/bin/bash
#
# script to generate a random number of on/off events to simulate presence eg.
# while on holidays.  normally this script would be executed by an event like a
# dawn-sensor (you wouldn't want light during the day...:-)
# 
# Copyright STefan Mayer <stefan@clumsy.ch>

################## configuration ###########################
#number of events (min - max)
event_min=5
event_max=20

#maximum delay in minutes
delay_max=240

#minimum and maximum ontime in minutes
ontime_min=5
ontime_max=60

#devices to consider
declare -a devices='("dg.gang" "dg.wand" "dg.dusche" "dg.bad" "dg.reduit")'

#output variant [oft|onoff]
#oft: use one at with on-for-timer of system
#onoff: use two at, one for on one for off
variant="onoff"

#command to execute
#command_start="/opt/fhem/fhem.pl 7072 \""
command_start="echo /opt/fhem/fhem.pl 7072 \""
command_end="\""


##################### Shouldnt need any changes below here #####################

# count number of devices
count=0
for i in ${devices[*]}
do
  ((count++))
done
# echo $count

# maximum random in bash: 32768
random_max=32768

#number of events
event=$(($RANDOM * (($event_max - $event_min)) / $random_max +$event_min))

#initialize command
command=$command_start

for ((i=0; i<$event; i++))
do
  #calculate starttime
  starttime=$(($RANDOM * $delay_max / $random_max))
  hour=$(($starttime / 60))
  minute=$(($starttime % 60))
  second=$(($RANDOM * 60 / $random_max))

  #calculate ontime
  ontime=$(($RANDOM * (($ontime_max - $ontime_min)) / $random_max +$ontime_min))

  #choose device
  dev=$(($RANDOM * $count / $random_max))

  case $variant in
    oft)
      printf "event %02d: define at.random.%02d at +%02d:%02d:%02d set %s on-for-timer %d\n" $i $i $hour $minute $second ${devices[$dev]} $ontime
      command=`printf "$command define at.random.%02d at +%02d:%02d:%02d set %s on-for-timer %d;;" $i $hour $minute $second ${devices[$dev]} $ontime`
      ;;
    onoff)
      offtime=$(($starttime + $ontime))
      hour_off=$(($offtime / 60))
      minute_off=$(($offtime % 60))
      second_off=$(($RANDOM * 60 / $random_max))
      printf "event %02d/on : define at.random.on.%02d at +%02d:%02d:%02d set %s on\n" $i $i $hour $minute $second ${devices[$dev]}
      printf "event %02d/off: define at.random.off.%02d at +%02d:%02d:%02d set %s off\n" $i $i $hour_off $minute_off $second_off ${devices[$dev]}
      command=`printf "$command define at.random.on.%02d at +%02d:%02d:%02d set %s on;;" $i $hour $minute $second ${devices[$dev]}`
      command=`printf "$command define at.random.off.%02d at +%02d:%02d:%02d set %s off;;" $i $hour_off $minute_off $second_off ${devices[$dev]}`
      ;;
    *)
      echo "no variant specifieno variant specified!!"
      ;;
   esac

done
command="$command $command_end"

#execute command
eval "$command"



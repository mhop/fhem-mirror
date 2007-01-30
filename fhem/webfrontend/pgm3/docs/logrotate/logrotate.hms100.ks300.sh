#!/bin/bash
# this script should be installed in e.g. /etc/crontab:
# 0 3 * * *       root /usr/local/bin/logrotate.hms100.ks300.sh > /dev/null 2>&1
# then there are only about 4 days in the logfile for the HMS/KS300-Device

logpath=/var/tmp
logs="heating laundry ks300"



for dev in $logs 
do
newlogs="0"

	# first time
	if [ ! -f $logpath/$dev.log.main ]; then cp -p $logpath/$dev.log $logpath/$dev.log.main; fi;

	cat $logpath/$dev.log | while read line;

                        do
                                if [ "$newlogs" = "1" ]; 
					then echo $line  >>$logpath/$dev.log.main; fi;
	                                if [ "$line" = "NEWLOGS" ]; then newlogs="1"; fi;

                        done;
	# 1900 for about 5 days
	tail -1900 $logpath/$dev.log.main >$logpath/$dev.log
	echo "NEWLOGS" >>$logpath/$dev.log

done;

#!/bin/bash
# this script should be installed in e.g. /etc/crontab:
# 0 3 * * *       root /usr/local/bin/logrotate.wz.sh > /dev/null 2>&1
# then there are only about 5 days in the logfile for the FHT-Device

logs="adi bao bau leo wz wzo"

for fht in $logs 
do
newlogs="0"

	# first time
	[[ ! -f /var/tmp/$fht.log.main ]] && cp -p /var/tmp/$fht.log /var/tmp/$fht.log.main 

	cat /var/tmp/$fht.log | while read line;
                  do
                    [[ "$newlogs" = "1" ]] && echo $line | egrep -v 'measured-temp: [0-2]\.' >>/var/tmp/$fht.log.main
	            [[ "$line" = "NEWLOGS" ]] && newlogs="1"
                  done;
	# 4500 for about 5 days
	tail -4500 /var/tmp/$fht.log.main >/var/tmp/$fht.log
	echo "NEWLOGS" >>/var/tmp/$fht.log

done;

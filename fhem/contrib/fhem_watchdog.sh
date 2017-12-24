#!/bin/sh
#
# $Id$
#
# Simple watchdog solution to monitor and restart fhem on Linux.
#
# Add this define to the fhem configuration:
#  define at_FhemPulse at +*00:10 {system("/bin/date +%s > /opt/fhem/log/fhem_pulse.log")}
#
# Add a cron job that runs every ten minutes -> crontab -e
#  */10 * * * * /opt/fhem/contrib/fhem_watchdog.sh


LOGFILE="/opt/fhem/log/fhem_pulse.log"

if [ `systemctl status fhem|grep inactive|wc -l` -eq "0" ]; then
  # fhem service was started
  
  if [ ! -e "${LOGFILE}" ]; then
    # There is no pulse log file
    systemctl restart fhem
    exit 0
  fi
  if [ $(expr $(/bin/date +%s) - $(cat ${LOGFILE})) -gt 900 ]; then
    # Last pulse is older than 15min.
    systemctl restart fhem
    exit 0
  fi
fi

exit 0


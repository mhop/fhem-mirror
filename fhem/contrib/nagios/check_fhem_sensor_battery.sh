#!/bin/bash
# -*- bash -*-
# vim: ft=bash
#
# check_fhem_sensor_battery.sh - check the battery state of FHT/HMS devices
# (other devices may also work (untested)). The device must have "battery" readings.
#
# FHEM must be installed and configured and reacheable via telnet (network or localhost).
# Copy this file to your nagios-plugins directory (utils.sh has to be in the same path).
#
# 2012 Oliver Voelker <code@magenbrot.net>
#
# LICENSE
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

PROGNAME=`basename $0`
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
REVISION="1.0"
DEVICE=$1

if [ "$2" ]; then HOST=$2; else HOST="localhost"; fi
if [ "$3" ]; then PORT=$3; else PORT=7072; fi

. $PROGPATH/utils.sh


print_usage() {
	echo "Usage: $PROGNAME <fhem-device> <optional:host port>"
}

print_help() {
	print_revision $PROGNAME $REVISION
	echo ""
	print_usage
	echo ""
	echo "This plugin checks the battery state of various fhem sensors."
	exit 0
}

case "$1" in
	--help|-h)
		print_help
		exit 0
		;;
	--version|-V)
   	print_revision $PROGNAME $REVISION
		exit 0
		;;
	*)
		bat=`echo -e "{ ReadingsVal('${DEVICE}', 'battery', 'notok')}\nquit\n" | nc ${HOST} ${PORT}`
		status=$?
		if test ${status} -eq 127; then
			echo "SENSORS UNKNOWN - command not found (did you install lmsensors?)"
			exit -1
		elif test ${status} -ne 0 ; then
			echo "WARNING - sensors returned state $status"
			exit 1
		fi
		if echo ${bat} | egrep "^ok$"  > /dev/null; then
			echo "BATTERY OK"
			exit 0
		else
			echo "BATTERY CRITICAL"
			exit 2
		fi
		;;
esac

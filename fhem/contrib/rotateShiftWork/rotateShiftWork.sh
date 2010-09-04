#!/bin/bash
################################################################
#
#  Copyright notice
#
#  (c) 2008 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
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
################################################################
#
# For a proper work it is necessary to set retrycount >4,
# e.g. "attr FHT_device retrycount 7"
#
# Write the following line to your config to automatically change the weekplan, e.g.:
# define timerEGwzHeizung at *00:15:00 "<path_to_script>/rotateShiftWork.sh EGwzHeizung"

# define work days
WORK="mon tue wed thu fri"
# define recreation days
FREE="sat sun"
# define range for odd weeks, e.g. "Frühschicht",
# (from1 to1 from2 to2)
odd=(12:30 22:30 24:00 24:00)
# define range for even weeks, e.g. "Spätschicht",
# (from1 to1 from2 to2)
even=(08:30 11:30 16:30 22:30)
# define range for recreation, e.g. "Wochenende",
# (from1 to1 from2 to2)
free=(08:30 23:50 24:00 24:00)
# define fhem.pl host:port
FHEM_BIN="/usr/bin/fhem.pl localhost:7072"
# define file for rotation
WEEKFILE="/var/fhem/week.save"

###########################################################
#
# do not change
#

[[ $# -lt 1 ]] && { echo "usage: $0 FHT_device [FHT_device] [FHT_device]"; exit 1; } || FHT_SET="$*"

# calculate week
let WEEK="`date +%V`%2"

# check week
[[ -f ${WEEKFILE} ]] && {
	. ${WEEKFILE}
	[[ ${WEEK} = ${LAST} ]] && exit 0
}

# write current week to file
echo "LAST=${WEEK}" > ${WEEKFILE}

# set "Frühschicht" or "Spätschicht"
[[ ${WEEK} -eq 0 ]] && week=(${even[*]}) || week=(${odd[*]})

# declare range
span=(from1 to1 from2 to2)

# set work days
for ((i=0; i<${#span[@]};i++)); do
	for DAY in ${WORK}; do
		VALUE="${VALUE}${DAY}-${span[$i]} ${week[$i]} "
	done
	for FHT in ${FHT_SET}; do
		${FHEM_BIN} "set ${FHT} ${VALUE}"
	done
	unset VALUE
done

# set recreation days
for ((i=0; i<${#span[@]};i++)); do
	for DAY in ${FREE}; do
		VALUE="${VALUE}${DAY}-${span[$i]} ${free[$i]} "
	done
	for FHT in ${FHT_SET}; do
		${FHEM_BIN} "set ${FHT} ${VALUE}"
	done
	unset VALUE
done

# refreshvalues
for FHT in ${FHT_SET}; do
	${FHEM_BIN} "set ${FHT} report1 255 report2 255"
done

exit 0

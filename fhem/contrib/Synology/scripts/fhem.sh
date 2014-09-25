#!/bin/sh
#
#
HOME='/var/packages/FHEM/target'
PERL=/usr/bin/perl
KMOD=/var/packages/usb-driver-kernel
PATH=$HOME:$PERL:$PATH
export PATH

fhem_BIN=${HOME}/fhem.pl
test -x ${fhem_BIN} || { echo "${fhem_BIN} not installed";
	if [ "$1" = "stop" ]; then exit 0;
	else exit 5; fi; }

# Check for existence of needed config file and read it
fhem_CONFIG=${HOME}/fhem.cfg
test -r ${fhem_CONFIG} || { echo "${fhem_CONFIG} not existing";
	if [ "$1" = "stop" ]; then exit 0;
	else exit 6; fi; }

fhem_LOG=/var/log/fhem-`date +"%Y-%m"`.log

perl_BIN=`which perl`

#
case "$1" in
	start)
		echo "Starting fhem "
		if [ -d "${KMOD}" ]; then
			if [ ! -f "${KMOD}/enabled" ]; then
				${KMOD}/scripts/start-stop-status start
				touch ${KMOD}/enabled && chmod 775 ${KMOD}/enabled
			fi
		fi

		${perl_BIN} $fhem_BIN $fhem_CONFIG
		;;
	stop)
		echo "Shutting down fhem "
		${perl_BIN} $fhem_BIN 7072 shutdown
		;;
	restart)
		$0 stop
		$0 start
		;;
	status)
		echo -n "Checking for service fhem "
		ps|grep fhem.pl
		;;
	log)
		test -r $fhem_LOG || { echo "$fhem_LOG not existing"; exit 0; }
		echo $fhem_LOG
		;;
	*)
		echo "Usage: $0 {start|stop|status|restart|log}"
		exit 1
		;;
esac
exit 0

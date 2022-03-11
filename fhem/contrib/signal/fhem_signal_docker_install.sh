#!/bin/bash
SCRIPTVERSION="$Id:2.1$"
# Author: Adimarantis
# License: GPL
#Install script for FHEM including signal-cli
FHEMVERSION=6.0
FHEMUSER=fhem
FHEMGROUP=fhem
SIGNALVAR=/var/lib/signal-cli
SIGNALBOTSOURCE=https://github.com/bublath/FHEM-Signalbot
LOG=/tmp/docker_install.log
TMPFILE=/tmp/signal$$.tmp
OPERATION=$1
BUILDDIR=$HOME/fhem
#Space separated list of additional packages, installed with apt (linux), cpan (perl) or npm (node.js)
APT="usbutils libimage-librsvg-perl perl libcpan-changes-perl liburi-perl"
CPAN="local::lib"
NPM=
#for signal-cli
APT="$APT wget default-jre zip base-files  libdbus-1-dev zip build-essential"
#APT="$APT wget haveged default-jre qrencode pkg-config gcc zip libexpat1-dev libxml-parser-perl libtemplate-perl libxml-xpath-perl build-essential xml-twig-tools base-files"
CPAN="$CPAN Protocol::DBus"
#for DBLOG
APT="$APT default-mysql-client libdbd-mysql libdbd-mysql-perl"
#for FRITZBOX
#APT="$APT libjson-perl libwww-perl libsoap-lite-perl libjson-xs-perl libnet-telnet-perl"
#for GoogleCast
#APT="$APT python3 python3-pip python3-dev libffi-dev libssl-dev libjpeg-dev zlib1g-dev autoconf build-essential libglib2.0-dev libdbus-1-dev bluez libbluetooth-dev"
#CPAN="$PERL Protocol::WebSocket"
#for Alexa
#APT="$APT nodejs npm"
#NPM="$NPM alexa-fhem"
#gassistent
#APT="$APT nodejs npm libjson-perl"
#NPM="$NPM gassistant-fhem"


#Get OS data
if [ -e /etc/os-release ]; then
	source /etc/os-release
	cat /etc/os-release >$LOG
else
	echo "Could not find OS release data - are you on Linux?"
	exit
fi

if grep -q docker /proc/1/cgroup; then 
   echo "Cannot install Docker inside Docker"
   exit
fi

USER=`id | grep root`
if [ -z "$USER" ]; then
	echo "Docker Installation needs to run under root"
	exit
fi

FHEM_UID=`id -u $FHEMUSER`
FHEM_GID=`id -g $FHEMGROUP`

echo "Will create a Docker FHEM instance including signal-cli for Signalbot usage"
echo
echo "Please verify that these settigns are correct:"
echo "FHEM-Version:              $FHEMVERSION"
echo "SIGNALBOT Repository       $SIGNALBOTSOURCE"
echo "BUILD directory            $BUILDDIR"
echo "User $FHEMUSER ($FHEM_UID)"
echo "Group $FHEMGROUP ($FHEM_GID)"

#
install_and_check() {
#Check availability of tools and install via apt if missing
	TOOL=$1
	PACKAGE=$2
	echo -n "Checking for $TOOL..."
	WHICH=`which $TOOL`
	if [ -z "$WHICH" ]; then
		echo -n "installing ($PACKAGE)"
		apt-get -q -y install $PACKAGE >>$LOG
		WHICH=`which $TOOL`
		if [ -z "$TOOL" ]; then
			echo "Failed to install $TOOL"
			exit
		else
			echo "done"
		fi
	else
		echo "available"
	fi
}

install_by_file() {
#Check availability of tools and install via apt if missing
	FILE=$1
	PACKAGE=$2
	echo -n "Checking for $FILE..."
	if ! [ -e "$FILE" ]; then
		echo -n "installing ($PACKAGE)"
		apt-get -q -y install $PACKAGE >>$LOG
		if ! [ -e "$FILE" ]; then
			echo "Failed to install $FILE"
			exit
		else
			echo "done"
		fi
	else
		echo "available"
	fi
}


check_and_create_path() {
#Check if path is available and create of not
	CHECK=$1
	echo -n "Checking for $CHECK..."
	if ! [ -d $CHECK ]; then
		mkdir $1
		if ! [ -d $CHECK ]; then
			echo "Failed to create $CHECK - did you run on sudo?"
			exit
		else
			echo "created"
		fi
	else
		echo "found"
	fi
	if ! [ -w $CHECK ]; then
		echo "Cannot write to $CHECK - did you start this script with sudo?"
		exit
	fi
}

check_and_compare_file() {
#Check if a file exists and compare if its the same as our internal reference file
	CHECK=$1
	COMPARE=$2
	echo -n "Checking for $CHECK..."
	if [ -e $CHECK ]; then
		echo "found"
		diff $CHECK $COMPARE
		DIFF=`diff -q $CHECK $COMPARE`
		if ! [ -z "$DIFF" ]; then
			echo "$CHECK differs, update (Y/n)? "
			read REPLY
			if [ "$REPLY" = "y" ]; then
				cp $COMPARE $CHECK
				echo "$CHECK updated"
			else 
			echo "$CHECK left untouched"
			fi
		fi
	else
		cp $COMPARE $CHECK
		echo "$CHECK installed"
	fi
}

#Main part - do always, check basic system requirements like OS, packages etc - does not install any signal specific stuff

ARCH=`arch`
OSNAME=`uname`
RASPI=""

if [ $OSNAME != "Linux" ]; then
	echo "Only Linux systems are supported (you: $OSNAME), quitting"
	exit
fi

if [ "$ID" = "raspbian" ] || [ "$ID" = "Raspian" ] || [ "$ARCH" = "armv7l" ]; then
	echo "You seem to be on a Raspberry pi with $ARCH"
	RASPI=1
else 
	if [ "$ID" = "ubuntu" ] || [ "$ID" = "Ubuntu" ]; then
		echo "You seem to run Ubuntu on $ARCH"
	else
		echo "Your configuration"
		uname -a
		echo "has not been tested, continue at own risk"
	fi
fi

check_and_update() {

APTCMD=`which apt`

if [ -z "$APTCMD" ]; then
	echo "Can't find apt command - are you on a supported system?"
	exit
fi

check_and_create_path $BUILDDIR

install_and_check docker docker.io
install_and_check wget wget

cd $BUILDDIR

cat >docker-compose.yml <<EOF
version: '2'

services:
    fhem:
        hostname: fhemsignal
        build: .
        image: fhem/signal
        container_name: fhem_signal
        stdin_open: true
        tty: true
        volumes:
          - "./fhem-$FHEMVERSION/:/opt/fhem/"
          - "./signal/:/var/lib/signal-cli"
        ports:
            - "8083:8083"
            - "7072:7072"
        networks:
            - fhem-network
        #devices:
        #    - "/dev/ttyUSB0:/dev/ttyUSB0"
        environment:
            FHEM_UID: $FHEM_UID
            FHEM_GID: $FHEM_GID
            FHEMUSER: $FHEMUSER
            FHEMGROUP: $FHEMGROUP
            TIMEOUT: 10
            RESTART: 1
            TELNETPORT: 7072
            TZ: Europe/Berlin

networks:
    fhem-network:
        driver: bridge

EOF

cat >Dockerfile <<EOF
ARG BASE_IMAGE="ubuntu"
ARG BASE_IMAGE_TAG="latest"
FROM \${BASE_IMAGE}:\${BASE_IMAGE_TAG}
RUN addgroup --gid $FHEM_GID fhem
RUN useradd -r -u $FHEM_UID -g fhem fhem
RUN mkdir /run/dbus

# Install base environment

RUN DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y base-files locales apt-utils sudo
RUN dpkg --configure -a 
RUN DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y $APT
RUN cpan install -f $CPAN
RUN if [ -n "$NPM" ]; then npm install $NPM ; fi
COPY org.asamk.Signal.conf /etc/dbus-1/system.d/org.asamk.Signal.conf
COPY org.asamk.Signal.service /usr/share/dbus-1/system-services/org.asamk.Signal.service
WORKDIR "/opt/fhem"
ENTRYPOINT [ "./entry.sh" ]
CMD [ "start" ]
EOF

cat >entry.sh <<EOF
#!/bin/bash
cd /opt/fhem
if [ -e /tmp/signal_install.log ]; then
	export FHEMUSER
	./signal_install.sh start >/tmp/start.log 2>/tmp/start.err
fi
	sudo -u $FHEMUSER perl fhem.pl fhem.cfg
	echo -n "Waiting for fhem to terminate."
	WAIT="runs"
	while [ -n "\$WAIT" ]
	do
		WAIT=\`ps -eo pid,command | grep fhem.pl | grep -v grep\`
		echo -n "."
		sleep 1
		done
echo "stopped"
EOF


cat >org.asamk.Signal.conf <<EOF
<?xml version="1.0"?> <!--*-nxml-*-->
	<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
	  "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
	
	<busconfig>
	  <policy user="$FHEMUSER">
	          <allow own="org.asamk.Signal"/>
	          <allow send_destination="org.asamk.Signal"/>
	          <allow receive_sender="org.asamk.Signal"/>
	  </policy>
	
	  <policy context="default">
	          <allow send_destination="org.asamk.Signal"/>
	          <allow receive_sender="org.asamk.Signal"/>
	  </policy>
	</busconfig>

EOF

cat >org.asamk.Signal.service <<EOF
[D-BUS Service]
Name=org.asamk.Signal
Exec=/bin/false
User=$FHEMUSER
SystemdService=dbus-org.asamk.Signal.service
EOF
}

create_docker() {
	REINST=0
	cd $BUILDDIR
	if [ -d fhem-$FHEMVERSION ]; then
		echo "FHEM $FHEMVERSION directory already exists"
		echo "delete and reinstall (y/N)?"
		read REPLY
		if [ "$REPLY" = "y" ]; then
			REINST=1
		fi
	fi	
	if [ $REINST = 1 ]; then
		echo -n "Downloading fhem $FHEMVERSION..."
		wget -qN http://fhem.de/fhem-$FHEMVERSION.tar.gz
		if ! [ -e fhem-$FHEMVERSION.tar.gz ]; then
			echo "failed"
			exit
		else
			echo "done"
			echo "Unpacking ..."
			tar xf $BUILDDIR/fhem-$FHEMVERSION.tar.gz
		fi
		cd $BUILDDIR
		chown -R $FHEMUSER: fhem-$FHEMVERSION 
	fi
	check_and_create_path $BUILDDIR/signal
	chown -R $FHEMUSER: $BUILDDIR/signal
	if ! [ -d $BUILDDIR/signal/data ]; then
		echo "Can't find any signal-cli registration data. You will need to do this later or register a new device"
		echo "Or just copy it to $BUILDDIR/signal now"
		echo -n "Press return to continue"
		read REPLY
	fi
	#Get latest scripts anyway
	echo -n "Downloading/Updating Signalbot..."
	cd $BUILDDIR/fhem-$FHEMVERSION
	wget -qN wget https://svn.fhem.de/fhem/trunk/fhem/contrib/signal/signal_install.sh
	chmod a+rx signal_install.sh
	echo "done"
	echo -n "Adjusting permissions..."
	chown -R $FHEMUSER: $BUILDDIR/fhem-$FHEMVERSION 
	chown -R $FHEMUSER: $SIGNALVAR
	echo "done"
	cd $BUILDDIR
	cp entry.sh fhem-$FHEMVERSION
	docker-compose up -d
	docker exec -ti fhem_signal /opt/fhem/signal_install.sh docker
# Restart container now that everything is set
	docker-compose down
	docker-compose up -d
}


remove_all() {
#just in case paths are wrong to not accidentially remove wrong things
 cd /tmp
echo "Warning. This will the container environment including images previously created by this script"
echo
echo -n "Continue (y/N)? "
read REPLY
if ! [ "$REPLY" = "y" ]; then
	echo "Abort"
	exit
fi
docker stop fhem_signal
docker rm fhem_signal

docker rmi fhem/signal
docker system prune 
}


if [ -z $OPERATION ]; then
	echo "This will create a container environment for fhem and signal-cli"
	echo
	echo "To do this rather step by step use the command line arguments or just proceed to do system,install,register:"
	echo "system   : prepare required system packages (docker, script files"
	echo "docker   : Create the docker and run the installation/configuration"
	echo "remove   : Docker container and image"
	echo
	echo "!!! Everything needs to run with sudo !!!"
else
	echo "Your chose the following option: $OPERATION"
fi
echo
echo -n "Proceed (Y/n)? "
read REPLY
if [ "$REPLY" = "n" ]; then
	echo "Aborting..."
	exit
fi

# Main flow without option: intall, register
if [ -z "$OPERATION" ] || [ $1 = "system" ]; then
	check_and_update
fi

if [ -z "$OPERATION" ] || [ $1 = "docker" ]; then
	create_docker
fi

rm -f $TMPFILE

if [ -z "$OPERATION" ]; then
	exit
fi

# Other options
if [ $OPERATION = "remove" ]; then 
	remove_all
fi

rm -f $TMPFILE

exit

# /bin/sh
#
# FHEMHelper.sh
#
# Script file to perform various external tasks for DoorPi
#
# Prof. Dr. Peter A. Henning, 2017
# 
#  $Id: FHEMHelper 2017-05 - pahenning $
#
########################################################################################
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
#########################################################################################
#  History
#  no_Legend 2016-09-28: Hinzufügen von verschiedenen Variablen, sowie bedingte Ausführung
#                        der Textausgaben auf einem TTS_Device.
#########################################################################################

checkstream() {
  streampid=`pidof mjpg_streamer`
  if [ -z "$streampid" ]; then
    stream="off"
  else
    stream="on"
  fi
}

FHEMDP="A.Door.Pi"              # FHEM Devicename for DoorPi
FHEMIP="XX.XX.XX.XX"            # IP address for DoorPi
FHEMPORT="8083"                 # Port number for DoorPi
FHEMHTTPS="false"               # true for HTTPS, false without HTTPS
curlprog="curl"
curlargs=""	                    # -k to disable HTTPS certificate check, 
                                # -u user:password for user and password 	
HOME="/home/doorpi"             # Doorpi Standard /usr/local/etc/DoorPi/ 
default_target="xxxxxx"         # default telephone number to be called
FHEMTTS="true"                  # true for TTS output, false without TTS
FHEMTTSDEVICE="AllTablets"      # FHEM Devicename for TTS device

### FHEM path ###
if [ $FHEMHTTPS = "true" ]; then
		FHEM="https://$FHEMIP:$FHEMPORT/fhem?XHR=1&cmd.$FHEMDP"
	else
		FHEM="http://$FHEMIP:$FHEMPORT/fhem?XHR=1&cmd.$FHEMDP"
	fi
	
### execute commands ##
case $1 in 

 init) #-- send current target to FHEM
       target=`cat $HOME/calltarget`
       $curlprog $curlargs "$FHEM=setreading%20$FHEMDP%20call_target%20$target" &
       #-- send state of mjpg_streamer to FHEM
       streampid=`pidof mjpg_streamer`
       if [ -z "$streampid" ]; then
         $curlprog $curlargs "$FHEM=setreading%20$FHEMDP%20stream%20off" &
       else
         $curlprog $curlargs "$FHEM=setreading%20$FHEMDP%20stream%20on" &
       fi
       ;;

 doorunlockandopen) 
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20door%20unlockandopen" &
       if [ $FHEMTTS = "true" ]; then
	     $curlprog $curlargs "$FHEM=set%20$FHEMTTSDEVICE%20audioPlay%20Music/066_zutrittbewohner.mp3" &			
       fi
       ;;

 dooropened) 
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20door%20opened" &
       ;;

 wrongid)
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20call%20wrong_id" &
       if [ $FHEMTTS = "true" ]; then
	   $curlprog $curlargs "$FHEM=set%20$FHEMTTSDEVICE%20audioPlay%20Music/065_zutrittsversuch.mp3" &
       fi
       ;;

 softlock)
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20door%20softlock" &
       ;;

 call) 
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20call%20$2" &
       ;;

 gettarget)
       echo "{ReadingsVal('$FHEMDP','call_target','$default_target')}" | socat -t50 - TCP:$FHEMIP:7072 > $HOME/calltarget
       ;;

 purge)
       find $HOME/records/ -type f -ctime +1 -delete
       ;;

 movement)
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20call%20movement" &
       ;;

 sabotage)
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20call%20sabotage" &
       ;;

 alive)
       $curlprog $curlargs "$FHEM=set%20$FHEMDP%20call%20alive" &
       ;;


esac

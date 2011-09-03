#!/bin/sh

## FritzBox 7390
## Beispiel fuer das Senden von FHEM Kommandos ueber den Telefoncode
## #95*x* wobei x hier 1 bzw 2 entspricht.

case $1 in
1) echo "set Steckdose on" | /sbin/socat -  TCP:127.0.0.1:7072
   ;;
2) echo "set Steckdose off" | /sbin/socat - TCP:127.0.0.1:7072
   ;;
esac



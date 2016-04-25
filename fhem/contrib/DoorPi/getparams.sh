# ! /usr/bin/sh
# get FHEM values
callnumber='{ReadingsVal("A.Haus.T.Klingel","callnumber",0)}'
FHEM=`echo -e "$callnumber" | socat -t50 - TCP:192.168.0.90:7072`

echo "$FHEM"  > /var/DoorPi/callnumber


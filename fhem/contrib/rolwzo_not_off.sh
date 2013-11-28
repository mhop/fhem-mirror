#!/bin/bash

# What do I want: If I'am sitting e.g. outside I don't want that the rollo goes
# down.  solution: if the button for e.g. rollo will be pressed after 16:59
# o'clock then the at-job for going down by sunset will be deleted

# put something like the following into your fhz100.cfg:
# define rolzwo_not_off notify rolwzo /usr/local/bin/rolwzo_not_off.sh


FHZ="/usr/bin/fhem.pl 7072"
order="delete rolwzo_off"

DATESTRING=`date +"%H"`
[[ $DATESTRING > 16 ]] && $FHZ "$order"

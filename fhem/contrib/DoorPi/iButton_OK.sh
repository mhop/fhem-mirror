# ! /usr/bin/sh
aplay -D plughw:1,0 /home/doorpi/sounds/067_willkommen.wav
curl "http://192.168.0.90:8085/fhem?XHR=1&cmd.GalaxyTab=set%20GalaxyTab%20ttsSay%20Ein%20Bewohner%20betritt%20das%20Haus"

 


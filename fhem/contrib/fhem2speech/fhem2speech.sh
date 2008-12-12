#!/bin/bash
if [ $# = 0 ]; then
  echo "Usage: `basename $0` -f [filename]"
  echo "       `basename $0` -s \"Text\""
  exit 1;
elif [ $1 = -f ]; then
  /usr/share/txt2pho/txt2pho -i $2 -f | /usr/bin/mbrola /usr/share/mbrola/de7/de7 - - \
  | /usr/bin/bplay -s 22050 -b 16 -q
elif [ $1 = -s ]; then
  echo $2 | /usr/share/txt2pho/txt2pho -f | /usr/bin/mbrola /usr/share/mbrola/de7/de7 - - \
  | /usr/bin/bplay -s 22050 -b 16 -q 
fi

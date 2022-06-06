#!/bin/bash
#
# sendphoto.sh
#
# Script file to send a doorpi photo per telegram
#
# Prof. Dr. Peter A. Henning, 2017
# 
#  $Id: sendphoto.sh 2017-05 - pahenning $
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
last=`ls -tr /home/doorpi/records/*.jpg | tail -1`
Token=TELEGRAMTOKEN
ChatId=CHATID
echo "Sending photo $last" > /home/doorpi/sendphoto.log
curl -s -k "https://api.telegram.org/bot${Token}/sendPhoto" -d photo="http://URLURLURL/doorpi/$last" -d chat_id=$ChatId >> /home/doorpi/sendphoto.log 
exit 0


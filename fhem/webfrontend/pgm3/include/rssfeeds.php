<?php

#### RSS-Feeds-- Provides RSS-Feeds

################################################################
#
#  Copyright notice
#
#  (c) 2006 Copyright: Martin Haas (fhz@martin-haas.de)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
#  Homepage:  http://martin-haas.de/fhz

##################################################################################

## make your settings in the config.php

###############################   end of settings



header("Content-Type: text/xml");


$fs20list=array();


echo "<?xml version=\"1.0\" encoding=\"utf-8\"?>


<rss version=\"2.0\">

<channel>
    <title>$RSStitel</title>
    <link>http://www.fhem.de</link>
    <description>RSS-Feeds for FHEM</description>
    <item>\n<title>Last Update: $now</title>\n<link>$forwardurl</link>\n</item>
";

    ##### Let's go.... :-)))))
        for($i=0; $i < count($stack[0][children]); $i++)
        {
        ############################
              if (substr($stack[0][children][$i][name],0,5)=='FS20_')
              {
                        $type=$stack[0][children][$i][name];
                        $counter=0;
                        for($j=0; $j < count($stack[0][children][$i][children]); $j++)
                         {
                         $fs20=$stack[0][children][$i][children][$j][attrs][name];
                         $state=$stack[0][children][$i][children][$j][attrs][state];
                        $room='';
                        for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
                        {
                           $check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
                         if ($check='STATE')
                          {
                                $measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
                          }
                         if ($check='ATTR')
                          {
                                if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
                                {
                                  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
                                }
                          }
                        }
                         if (($state=='on') or ($state=='dimup'))
                         {$order="set $fs20 off";}
                         else
                         {$order="set $fs20 on";};
			 $url=$forwardurl.'rssorder='.$order;
				echo $url;
                         if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
                         {
#			echo "<item>\n<title>$fs20   $state</title>\n<link>$url</link>\n</item>\n";
			 array_push( $fs20list,array($fs20,$state,$room,$measured,$url));
                         };
                         }
               }
	
        ############################
	 elseif (substr($stack[0][children][$i][name],0,4)=='FHT_')
               {
    			echo "<item>\n<title>*************  FHT state *************</title>\n<link>$forwardurl</link>\n</item>";
                        $type=$stack[0][children][$i][name];
                        for($j=0; $j < count($stack[0][children][$i][children]); $j++)
                         {
                                $room="";
                                for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
                                {
                                   $check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
                                   if ( $check=="room")
                                        {$room=$stack[0][children][$i][children][$j][children][$k][attrs][value]; }
                                   if ( $check=="measured-temp")
                                        {$measuredtemp=$stack[0][children][$i][children][$j][children][$k][attrs][value]; 
					$measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
					$pos=strpos($measured,' ');
					$measured=substr($measured,$pos,strlen($measured));
					$pos=strpos($measuredtemp,' ');
					$measuredtemp=substr($measuredtemp,0,$pos);
					}
                                }
                 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
                 {
                         $FHTdev=$stack[0][children][$i][children][$j][attrs][name];
			echo "<item>\n<title>$FHTdev  $measuredtemp $measured</title>\n<link>$forwardurl</link>\n</item>\n";

                        }
                }
               }
        ############################
               elseif (substr($stack[0][children][$i][name],0,4)=='HMS_')
               {
    			echo "<item>\n<title>*************  HMS state *************</title>\n<link>$forwardurl</link>\n</item>";
                        $type=$stack[0][children][$i][name];
                        for($j=0; $j < count($stack[0][children][$i][children]); $j++)
                         {
                                $room="";
				unset($state);
				unset($humidity);
                                for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
                                {
                                   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="room")
                                        {$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
                                        }
                                   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="type")
                                        {$type=$stack[0][children][$i][children][$j][children][$k][attrs][value];};
                                   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="humidity")
                                        {$humidity=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					};
                                   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="temperature")
                                        {
					$state=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					$pos=strpos($state,'(');
					$state=substr($state,0,$pos);
					$measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
					$pos=strpos($measured,' ');
					$measured=substr($measured,$pos,strlen($measured));
					$state=$humidity.$state;
					};
                                }
                 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
                 {
                        $HMSdev=$stack[0][children][$i][children][$j][attrs][name];
			echo "<item>\n<title>$HMSdev  $state $measured</title>\n<link>$forwardurl</link>\n</item>\n";


                }

                       }
               }
        ############################
               elseif (substr($stack[0][children][$i][name],0,6)=='KS300_' or substr($stack[0][children][$i][name],0,6)=='WS300_')
               {
    			echo "<item>\n<title>***********  KS300/WS300 ***********</title>\n<link>$forwardurl</link>\n</item>";
                        $type=$stack[0][children][$i][name];
                        for($j=0; $j < count($stack[0][children][$i][children]); $j++)
                         {
                         $KSdev=$stack[0][children][$i][children][$j][attrs][name];
                        $room='';
                        for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
                        {
                                 if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="STATE")
                                 {$state=$stack[0][children][$i][children][$j][children][$k][attrs][value];};
                                 if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="temperature")
				$measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
                        }
			$pos=strpos($measured,' ');
			$measured=substr($measured,$pos,strlen($measured));
			echo "<item>\n<title>$KSdev $state $measured</title>\n<link>$forwardurl</link>\n</item>\n";

                        }
                }

        ############################
}


# now the FS20-Devices
	if (count($fs20list) > 0 )
	 echo "<item>\n<title>*************  FS20 state *************</title>\n<link>$forwardurl</link>\n</item>";

 for ($x = 0; $x < count($fs20list); $x++)
        {
		$parts = explode(" ", $fs20list[$x]);
		$fs20= $fs20list[$x][0];
		$state= $fs20list[$x][1];
		$measured= $fs20list[$x][3];
		$pos=strpos($measured,' ');
		$measured=substr($measured,$pos,strlen($measured));
		$url= $fs20list[$x][4];
		echo "<item>\n<title> $fs20    $state $measured</title>\n<link>$url</link>\n</item>\n";


	}



echo "
</channel>
</rss>
";




?>

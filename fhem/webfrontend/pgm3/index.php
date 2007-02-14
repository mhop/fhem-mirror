<?php

#### pgm3 -- a PHP-webfrontend for fhz1000.pl 

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

error_reporting(E_ALL ^ E_NOTICE);
include "config.php";
include "include/gnuplot.php";


$pgm3version='0.7.0b';

	
	$Action		=	$_POST['Action'];
	$order		= 	$_POST['order'];
	$showfht	=	$_POST['showfht'];
	$showks		=	$_POST['showks'];
	$kstyp		=	$_POST['kstyp'];
	$showroom	=	$_POST['showroom'];
	$showmenu	=	$_POST['showmenu'];
	$showhmsgnu	=	$_POST['showhmsgnu'];
	$temp		=	$_POST['temp'];
	$dofht		=	$_POST['dofht'];
	$orderpulldown	=	$_POST['orderpulldown'];
	$valuetime	=	$_POST['valuetime'];
	$atorder	=	$_POST['atorder'];
	$attime		=	$_POST['attime'];

	$fhtdev		=	$_POST['fhtdev'];
	$fs20dev	=	$_POST['fs20dev'];
	$errormessage	=	$_POST['errormessage'];

	if (! isset($showhmsgnu)) $showhmsgnu=$_GET['showhmsgnu'];
	if ($showhmsgnu=="") unset($showhmsgnu);

	if (! isset($showfht)) $showfht=$_GET['showfht'];
	if ($showfht=="") unset($showfht);
	if ($showfht=="none") unset($showfht);

	if (! isset($showmenu)) $showmenu=$_GET['showmenu'];
	if ($showmenu=="") unset($showmenu);
	if ($showmenu=="none") unset($showmenu);

	if (! isset($showhist))  $showhist=$_GET['showhist'];
	if ($showhist=="none") unset($showhist);
	
	if (! isset($showlogs))  $showlogs=$_GET['showlogs'];
	if ($showlogs=="none") unset($showlogs);
	
	if (! isset($showat)) $showat=$_GET['showat'];
	if ($showat=="none") unset($showat);
	
	if (! isset($shownoti)) $shownoti=$_GET['shownoti'];
	if ($shownoti=="none") unset($shownoti);
	
	if (! isset($showroom)) $showroom=$_GET['showroom'];
	if ($showroom=="") unset($showroom);

	if (! isset($showks)) $showks=$_GET['showks'];
	if ($showks=="") unset($showks);

	if (! isset($kstyp)) $kstyp=$_GET['kstyp'];
	if ($kstyp=="") unset($kstyp);

	if (! isset($Action)) $Action=$_GET['Action'];
	if ($Action=="") unset($Action);

	if (! isset($order)) $order=$_GET['order'];
	if ($order=="") unset($order);

	if (! isset($orderpulldown)) $orderpulldown=$_GET['orderpulldown'];
	if ($orderpulldown=="") unset($orderpulldown);

	if (! isset($valuetime)) $valuetime=$_GET['valuetime'];
	if ($valuetime=="") unset($valuetime);

	if (! isset($fhtdev)) $fhtdev=$_GET['fhtdev'];
	if ($fhtdev=="") unset($fhtdev);

	if (! isset($fs20dev)) $fs20dev=$_GET['fs20dev'];
	if ($fs20dev=="") unset($fs20dev);

	if (! isset($errormessage)) $errormessage=$_GET['errormessage'];
	if ($errormessage=="") unset($errormessage);



# try to get the URL:
	$homeurl='http://'.$_SERVER['HTTP_HOST'].$_SERVER['SCRIPT_NAME'];
	 $forwardurl=$homeurl.'?';
	$testFirstStart=$_SERVER['QUERY_STRING'];
	if ($testFirstStart=='')  ##new session (??) then start-values
	{
		if ($showAT=='yes') $showat='yes';
		if ($showLOGS=='yes') $showlogs='yes';
		if ($showNOTI=='yes') $shownoti='yes';
		if ($showHIST=='yes') $showhist='yes';
	}


	if (isset ($showfht)) { $forwardurl=$forwardurl.'&showfht='.$showfht;};
	if (isset ($fs20dev)) 
	{ $forwardurl=$forwardurl.'&fs20dev='.$fs20dev.'&orderpulldown='.$orderpulldown.'&showmenu='.$showmenu.'&showroom='.$showroom;};
	if (isset ($showks)) { $forwardurl=$forwardurl.'&showks='.$showks.'&kstyp='.$kstyp;};
	if (isset ($showhmsgnu)) { $forwardurl=$forwardurl.'&showhmsgnu='.$showhmsgnu;};
	if (isset ($showroom)) { $forwardurl=$forwardurl.'&showroom='.$showroom;};
	if (isset ($shownoti)) { $forwardurl=$forwardurl.'&shownoti';};
	if (isset ($showlogs)) { $forwardurl=$forwardurl.'&showlogs';};
	if (isset ($showat)) { $forwardurl=$forwardurl.'&showat';};
	if (isset ($showhist)) { $forwardurl=$forwardurl.'&showhist';};
	if (isset ($showmenu)) 
	{ $forwardurl=$forwardurl.'&fs20dev='.$fs20dev.'&orderpulldown='.$orderpulldown.'&showmenu='.$showmenu.'&showroom='.$showroom;}
	unset($link);
	if (isset ($showlogs)) $link=$link.'&showlogs'; 
	if (isset ($shownoti)) $link=$link.'&shownoti'; 
	if (isset ($showhist)) $link=$link.'&showhist'; 
	if (isset ($showat)) $link=$link.'&showat'; 
	if (isset ($showmenu)) $link=$link.'&showmenu='.$showmenu; 
	if (isset ($showfht)) $link=$link.'&showfht='.$showfht; 
	if (isset ($showhmsgnu)) $link=$link.'&showhmsgnu='.$showhmsgnu; 
	if (isset ($showks)) $link=$link.'&showks='.$showks; 


switch ($Action):
	Case exec:
		if ($kioskmode=='off') 
		{
			$order=str_replace("\\","",$order);
			$order=str_replace("@","+",$order);
	#		echo $order; exit;
			execFHZ($order,$fhz1000,$fhz1000port);
		}
		header("Location:  $forwardurl&errormessage=$errormessage");
		break;
	Case exec2:
		$order="$atorder $attime set $fs20dev $orderpulldown $valuetime";
		if ($kioskmode=='off') execFHZ($order,$fhz1000,$fhz1000port);
		header("Location:  $forwardurl");
	Case exec3:
		$order="$atorder $attime set $fhtdev $orderpulldown $valuetime";
		if ($kioskmode=='off') execFHZ($order,$fhz1000,$fhz1000port);
	Case execfht:
		$order="set $dofht desired-temp $temp";
		if ($kioskmode=='off') execFHZ($order,$fhz1000,$fhz1000port);
		header("Location:  $forwardurl");
		break;
	Case showfht|showroom|showks|showhmsgnu|hide:
		header("Location: $forwardurl");
		break;
	default:
endswitch;



if (! isset($showroom)) $showroom="ALL";
if ($taillog==1) exec($taillogorder,$tailoutput);


#executes over the network to the fhz1000.pl (or localhost)
function execFHZ($order,$machine,$port)
{
global $errormessage;

$version = explode('.', phpversion());

if ( $version[0] == 4 )
{
	include "config.php";
	$order="$fhz1000_pl $port '$order'";  #PHP4, only localhost
         exec($order,$errormessage);
}
else
{
$fp = stream_socket_client("tcp://$machine:$port", $errno, $errstr, 30);
        if (!$fp) {
           echo "$errstr ($errno)<br />\n";
        } else {
           fwrite($fp, "$order\n;quit\n");
               	$errormessage= fgets($fp, 1024);
           fclose($fp);
        }
}
return $errormessage;
}


###### make an array from the xmllist
unset($output);
$stack = array();
$output=array();


$version = explode('.', phpversion());

if ( $version[0] == 4 )
{
        $xmllist="$fhz1000_pl $fhz1000port xmllist";
        exec($xmllist,$output);
}
else
{
	$fp = stream_socket_client("tcp://$fhz1000:$fhz1000port", $errno, $errstr, 30);
	if (!$fp) {
	   echo "$errstr ($errno)<br />\n";
	} else {
	   fwrite($fp, "xmllist\r\n;quit\r\n");
	   while (!feof($fp)) {
	       $outputvar = fgets($fp, 1024);
		array_push($output,$outputvar);
	   }
	   fclose($fp);
	}
}



#  start_element_handler ( resource parser, string name, array attribs )
function startElement($parser, $name, $attribs)
{
   global $stack;
   $tag=array("name"=>$name,"attrs"=>$attribs);
   array_push($stack,$tag);
}

#  end_element_handler ( resource parser, string name )
function endElement($parser, $name)
{
   global $stack;
   $stack[count($stack)-2]['children'][] = $stack[count($stack)-1];
   array_pop($stack);
}


function new_xml_parser($live)
{
   global $parser_live;
   $xml_parser = xml_parser_create();
   xml_parser_set_option($xml_parser, XML_OPTION_CASE_FOLDING, 0);
   xml_set_element_handler($xml_parser, "startElement", "endElement");
 
   if (!is_array($parser_live)) {
       settype($parser_live, "array");
   }
   $parser_live[$xml_parser] = $live;
   return array($xml_parser, $live);
}

# go parsing
if (!(list($xml_parser, $live) = new_xml_parser($live))) {
   die("could not parse XML input");
}

foreach($output as $data) { 
  if (!xml_parse($xml_parser, $data)) {
       die(sprintf("XML error: %s at line %d\n",
                   xml_error_string(xml_get_error_code($xml_parser)),
                   xml_get_current_line_number($xml_parser)));
   }
}

xml_parser_free($xml_parser);

#for testing
#print_r($stack);exit;


#searching for rooms/fs20
	$rooms=array();
	$fs20devs=array();
	$fhtdevs=array();
      if ($showroombuttons==1)
	for($i=0; $i < count($stack[0][children]); $i++) 
	{
	      if ($stack[0][children][$i][name]=='FS20_DEVICES')
	      {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 $fs20devxml=$stack[0][children][$i][children][$j][attrs][name];
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   $check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
			 if ($check='ATTR')
			  {
				if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
				{
			  	  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
				}
			  }
			}
		  	 if ((! in_array($fs20devxml,$fs20devs)) AND ( $room != 'hidden')) array_push($fs20devs,$fs20devxml);
			}
	      }#FS20
	       elseif ($stack[0][children][$i][name]=='FHT_DEVICES')
	       {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 	$fhtdevxml=$stack[0][children][$i][children][$j][attrs][name];
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   $check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
				   if ( $check=="room") 
					{$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
					}
				}

			  	 if ((! in_array($fhtdevxml,$fhtdevs)) AND ( $room != 'hidden')) array_push($fhtdevs,$fhtdevxml);
			 }
		} #FHT
	       elseif ($stack[0][children][$i][name]=='HMS_DEVICES')
	       {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="room") 
					{$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
					}
				}
		       }
	       } # HMS
	       elseif ($stack[0][children][$i][name]=='KS300_DEVICES')
	       {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   $check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
			 if ($check='ATTR')
			  {
				if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
				{
			  	  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
					}
				}
			  }
			}
		}
	} # end searching rooms
	array_push($rooms,'ALL');
	sort($rooms);

#print_r($rooms); echo "Count: $countrooms"; exit;
#print_r($fs20devs);  exit;

# Print Array on Screen

 $now=date($timeformat);

 echo "
         <html>
	 <head>
	 <meta http-equiv='refresh' content='$urlreload; URL=$forwardurl'>
	 <meta http-equiv='pragma' content='no-cache'>
	 <meta http-equiv='Cache-Control' content='no-cache'>
 	 <link rel='shortcut icon' href='include/fs20.ico' >
	 <title>$titel</title>";
 	  include ("include/style.css");	 
 echo "	 </head>";

 echo"      <body $bodybg>
	$errormessage
	<table width='800' cellspacing='1' cellpadding='10' border='0' $bgcolor1><tr><td></td></tr></table>
	<table width='800' cellspacing='1' cellpadding='0' border='0' align='CENTER' $bg4>
	  <tr> 
	      <td bgcolor='#6394BD' width='100%'> 
	      <table bgcolor='#FFFFFF' width='100%' cellspacing='0' cellpadding='0' border='0'>
	              <tr> <td>
	<table width='100%' cellspacing='2' cellpadding='2' align=center border='0'>
	<tr><td $bg1 colspan=4><br>
		<font size=+1 $fontcolor1><center><b>$titel</b></font>
	 	<font size=3 $fontcolor1><br><b>$now</b>
		</font></center>
		 <font size=-2 $fontcolor1><div align='right'>v$pgm3version</div></font>
		</td></tr>";
	
	############################ FHZ
	echo "<tr><td $bg1 colspan=4><font $fontcolor1><table  cellspacing='0' cellpadding='0' width='100%'>
		<tr><td><font $fontcolor1>FHZ_DEVICE</td><td align=right><font $fontcolor1><b>";
	if ($showmenu != '1')	
		{ echo "<a href=$formwardurl?showmenu=1&showroom=$showroom$link>show menu</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showmenu=none>hide menu</a>";}

	echo "</b></font></td></tr></table>";
	echo "</font></td></tr>";


	if (($show_general=='1') AND ($showmenu=='1'))
	{echo "
		<tr>
		<td colspan=3 align=right $bg2><font  $fontcolor3>
		General: </font></td><td align=left $bg2><font $fontcolor3>	
		<form action=$forwardurl method='POST'>
		<input type=text name=order size=30>
		<input type=hidden name=showfht value=$showfht>
		<input type=hidden name=showhms value=$showhms>
		<input type=hidden name=showmenu value=$showmenu>
		<input type=hidden name=Action value=exec>
		<input type=submit value='go!'></form></td></tr>";
	};
	
	if (($show_fs20pulldown=='1') AND ($showmenu=='1')) include 'include/fs20pulldown.php';
	if (($show_fhtpulldown=='1') AND ($showmenu=='1')) include 'include/fhtpulldown.php';

	############################ ROOMS
	if (($showroombuttons==1) and (count($rooms)>1))
	{
		echo "<tr><td $bg1 colspan=4><font $fontcolor1>";
		echo "ROOMS ";
		echo "</font></td></tr>";
		echo "<tr><td $bg2 colspan=4>";
		$counter=0;
	 	for($i=0; $i < count($rooms); $i++)
		 	{
				 $room=$rooms[$i];
				 if ($room != 'hidden')
		 		{
				echo"<a href='index.php?Action=showroom&showroom=$room$link'><img src='include/room.php?room=$room&showroom=$showroom'></a>";
				$counter++;

				if  (fmod($counter,$roommaxiconperline)== 0.0) echo "<br>";
				} else $counter--;
			}
		echo "</td></tr>";
	}	

#####################################################################################################################
	##### Let's go.... :-)))))
	for($i=0; $i < count($stack[0][children]); $i++) 
	{
	############################
	      if ($stack[0][children][$i][name]=='FS20_DEVICES')
	      {
			$type=$stack[0][children][$i][name];
			echo "<tr><td $bg1 colspan=4><font $fontcolor1>";
	      		echo "$type</font></td></tr>";
			$counter=0;
			echo "<tr><td $bg2 colspan=4>";
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
			 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
			 {
			 	$counter++;
				echo"<a href='index.php?Action=exec&order=$order&showroom=$showroom$link'><img src='include/fs20.php?drawfs20=$fs20&statefs20=$state&datefs20=$measured&room=$room'></a>";
				if  (fmod($counter,$fs20maxiconperline)== 0.0) echo "<br>";
			 };
			 }
			 	echo "</td></tr>";
	       }
	############################
	       elseif ($stack[0][children][$i][name]=='FHT_DEVICES')
	       {
			$type=$stack[0][children][$i][name];
			echo "<tr><td $bg1 colspan=4><font $fontcolor1>";
	      		echo "$type</font></td></tr>";
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
				$room="";
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   $check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
				   if ( $check=="room") 
					{$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					}
				}
		 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
		 {
		    
			 $FHTdev=$stack[0][children][$i][children][$j][attrs][name];
			 if ($showfht == $FHTdev)
			 	{echo "<tr valign=center><td align=center $bg2 valign=center> 
				       <form action=$forwardurl method='POST'>
				       <input type=hidden name=Action value=hide>
				       <input type=hidden name=showfht value=none>
			 		<input type=hidden name=showroom value=$showroom>
				       <input type=submit value='hide'></form>";}
			 else
			 	{echo "<tr valign=center><td align=center $bg2 valign=center> 
				       <form action=$forwardurl method='POST'>
				       <input type=hidden name=Action value=showfht>
				       <input type=hidden name=showfht value=$FHTdev>
			 		<input type=hidden name=showroom value=$showroom>
		    	      	       <input type=hidden name=showhms value=$showhms>
				       <input type=submit value='show'></form></td>";
			 };
			 echo "<td align=center valign=center $bg2><b>
			 <font  $fontcolor3>$FHTdev</font></b></td><td $bg2 align=center valign=center>
			 <form action=$forwardurl method='POST'><font  $fontcolor3>desired-temp</font> 
			 <input type=hidden name=Action value=execfht>
			 <input type=hidden name=showfht value=$showfht>
			 <input type=hidden name=showroom value=$showroom>
		   	 <input type=hidden name=showhms value=$showhms>
			 <input type=hidden name=dofht value=$FHTdev>";
			 echo "<select name=temp size=1>
			 <option>12.0</option><option>17.0</option><option>18.0</option>
			 <option>19.0</option><option>20.0</option><option>21.0</option><option selected>22.0</option>
			 <option>23.0</option><option>24.0</option><option>25.0</option><option>26.0</option></select>
			 <input type=submit value=go></form></td>
			 ";
				   
				echo "<td $bg2> 
				<img src='include/fht.php?drawfht=$FHTdev&room=$room' width='$imgmaxxfht' height='$imgmaxyfht'>
				</td>";
				echo "</tr>";
			 	
				if ($showfht==$FHTdev and $showgnuplot == 1)
			 	{   
                                 	drawgnuplot($FHTdev,"FHT",$gnuplot,$pictype,$logpath);
					$FHTdev1=$FHTdev.'1';
                                	echo "<tr><td colspan=5 align=center><img src='tmp/$FHTdev.$pictype'><br>
					<img src='tmp/$FHTdev1.$pictype'>
                                        </td></tr>
			 		      <tr><td colspan=4><hr color='#AFC6DB'></td></tr>";
				}
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				  if ( $showfht==$FHTdev)
				   {
				   	$name=$stack[0][children][$i][children][$j][children][$k][attrs][name];
					$value=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					$measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
			        	echo "<tr><td colspan=1> $FHTdev (FHT): </td><td>$name</td><td>$value
					      </td><td>$measured</td></tr>";
				   }
				}
			}
		}
	       }
	############################
	       elseif ($stack[0][children][$i][name]=='HMS_DEVICES')
	       {
			$type=$stack[0][children][$i][name];
			echo "<tr><td $bg1 colspan=4><font $fontcolor1>";
	      		echo "$type</font></td></tr>";
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
				$room="";
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="room") 
					{$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					}
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][name]=="type") 
					{$type=$stack[0][children][$i][children][$j][children][$k][attrs][value];};
				}
		 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
		 {
			$HMSdev=$stack[0][children][$i][children][$j][attrs][name];
			if ($type=="HMS100T" or $type=="HMS100TF")
			{
			if ($showhmsgnu== $HMSdev)
			{$formvalue="hide";$gnuvalue="";}
			else {$formvalue="show";$gnuvalue=$HMSdev;};
			echo "</td></tr><tr valign=center><td align=center $bg2 valign=center>
                                       <form action=$forwardurl method='POST'>
                                       <input type=hidden name=Action value=showhmsgnu>
                                        <input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=showhmsgnu value=$gnuvalue>
                                       <input type=submit value='$formvalue'></form></td><td $bg2>";
				
			}
			else
		 	echo "</td></tr><tr><td $bg2 colspan=2>";
		       	echo "<font  $fontcolor3><b> $HMSdev</b></font> </td>
			<td $bg2 colspan=2><img src='include/hms100.php?drawhms=$HMSdev&room=$room&type=$type' width='$imgmaxxhms' height='$imgmaxyhms'></td> </tr>";
		
		if ($showhmsgnu == $HMSdev and $showgnuplot == 1)
                                { drawgnuplot($HMSdev,$type,$gnuplot,$pictype,$logpath);
				$HMSdev1=$HMSdev.'1';
                                echo "<tr><td colspan=5 align=center><img src='tmp/$HMSdev.$pictype'><br>
					<img src='tmp/$HMSdev1.$pictype'>
                                        </td></tr>";
                }
		}

		       }
	       }
	############################
	       elseif ($stack[0][children][$i][name]=='KS300_DEVICES')
	       {
			$type=$stack[0][children][$i][name];
			echo "<tr><td $bg1 colspan=4><font $fontcolor1>";
	      		echo "$type</font></td></tr>";
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 $KSdev=$stack[0][children][$i][children][$j][attrs][name];
			$room='';
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   $check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
			 if ($check='STATE')
			  {
			   	$name=$stack[0][children][$i][children][$j][children][$k][attrs][name];
				$value=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				$measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
				if ($name=='temperature')  {$KSmeasured=$measured;}
				elseif ($name=='avg_month') {$KSavgmonth=$value;}
				elseif ($name=='avg_day') {$KSavgday=$value;};
			  }
			 if ($check='ATTR')
			  {
				if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
				{
			  	  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				}
			  }
			}
		 	if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
		 	{
			 $Xks=$imgmaxxks;
			 $Yks=$imgmaxyks*4;
			##gnuplot
			if ($showks == $KSdev)
                                {echo "<tr valign=center><td align=center $bg2 valign=center>
                                       <form action=$forwardurl method='POST'>
                                       <input type=hidden name=Action value=hide>
                                        <input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=showks value=''>
                                       <input type=submit value='hide'></form></td>";}
                         else
                                {echo "<tr valign=center><td align=center $bg2 valign=center>
                                       <form action=$forwardurl method='POST'>
                                       <input type=hidden name=Action value=showks><br>Temp./Hum.<br>
					<input type=radio name=kstyp value=\"1\" checked><br><br>Wind/Rain<br>
					<input type=radio name=kstyp value=\"2\"><br><br>
                                        <input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=showks value=$KSdev>
                                       <input type=submit value='show'></form></td>";
                         };
			 echo "<td $bg2<font  $fontcolor3><b>  $KSdev</font></b> </td><td $bg2 center=align colspan=2>";
			 echo "<img src='include/ks300.php?drawks=$KSdev&room=$room&avgmonth=$KSavgmonth&avgday=$KSavgday' width='$Xks' height='$Yks'>";
			 echo "</td></tr>";
			if (($showks == $KSdev) and  $showgnuplot=='1')
				 {
				if ($kstyp=="1")drawgnuplot($KSdev,"KS300_t1",$gnuplot,$pictype,$logpath);
				else  drawgnuplot($KSdev,"KS300_t2",$gnuplot,$pictype,$logpath);
				$KSdev1=$KSdev.'1';
				echo "<tr><td colspan=5 align=center><img src='tmp/$KSdev.$pictype'><br>
					<img src='tmp/$KSdev1.$pictype'>
					</td></tr>";
			}

			}
			}
		}
	############################
	       elseif ($stack[0][children][$i][name]=='LOGS')
	       {
		echo "<tr><td $bg1 colspan=4><font $fontcolor1>
			<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>LOGS</td><td align=right><font $fontcolor1><b>";
		if (! isset ($showlogs))	
		{ echo "<a href=$formwardurl?showlogs&showroom=$showroom$link>show</a>";}
		else
		{ 
		echo "<a href=$formwardurl?showroom=$showroom$link&showlogs=none>hide</a>";}
	
	      		echo "</font></td></tr></table></td></tr>";
		if (isset ($showlogs))
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 	$name=$stack[0][children][$i][children][$j][attrs][name];
				$definition=$stack[0][children][$i][children][$j][attrs][definition];
				if ($definition != "")
			 	{echo "<tr><td colspan=2 border=0>Log:</td>
					<td colspan=2 border=0>$definition</td></tr>";
				}
			 }
		} 
	############################
	       elseif ($stack[0][children][$i][name]=='NOTIFICATIONS')
	       {
		echo "<tr><td $bg1 colspan=4><font $fontcolor1>
			<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>NOTIFICATIONS</td><td align=right><font $fontcolor1><b>";
		if (! isset ($shownoti))	
		{ echo "<a href=$formwardurl?shownoti&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&shownoti=none>hide</a>";}
	      	echo "</font></td></tr></table></td></tr>";

		if (isset ($shownoti))
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 	$event=$stack[0][children][$i][children][$j][attrs][event];
				$command=$stack[0][children][$i][children][$j][attrs][command];
				$measured=$stack[0][children][$i][children][$j][children][0][attrs][measured];
			 	echo "<tr><td colspan=2>Notification:</td><td colspan=2>$event $command</td></tr>";
			 }
		} 
	############################
	       elseif ($stack[0][children][$i][name]=='AT_JOBS')
	       {
		echo "<tr><td $bg1 colspan=4><font $fontcolor1>
			<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>AT_JOBS</td><td align=right><font $fontcolor1><b>";
		if (! isset ($showat))	
		{ echo "<a href=$formwardurl?showat&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showat=none>hide</a>";}
	      	echo "</font></td></tr></table></td></tr>";


		if (isset ($showat))
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
				$command=$stack[0][children][$i][children][$j][attrs][command];
				$next=$stack[0][children][$i][children][$j][attrs][next];
				$order=$command;
				$order=str_replace("+","@",$order);
				$order='del at '.$order;
				if ($next != '') {$nexttxt='('.$next .')';} else {$nexttxt='';};
			 	echo "<tr><td> AT-Job: </td><td><a href='index.php?Action=exec&order=$order$link'>del</a></td><td colspan=2>$command $nexttxt</td></tr>";
			 }
		} 
	};
	if ($taillog==1) 
	{
		echo "<tr><td $bg1 colspan=4><font $fontcolor1>
			<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>$taillogorder</td><td align=right><font $fontcolor1><b>";
		if (! isset ($showhist))	
		{ echo "<a href=$formwardurl?showhist&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showhist=none>hide</a>";}
	      	echo "</font></td></tr></table></td></tr>";
	if (isset ($showhist)) {foreach($tailoutput as $data) echo "<tr><td colspan=2>History</td><td colspan=2>$data</td></tr>";};
	

	};
	echo "</td></tr></table></td></tr></table></font></table></body></html>";

?>

<?php

#### pgm3 -- a PHP-webfrontend for fhem.pl 

################################################################
#
#  Copyright notice
#
#  (c) 2006-2010 Copyright: Martin Haas (fhz@martin-haas.de)
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
$userdef=array();
include "config.php";
include "include/gnuplot.php";
include "include/functions.php";


$pgm3version='120520';
	


	$Action		=	$_POST['Action'];
	$order		= 	$_POST['order'];
	$showfht	=	$_POST['showfht'];
	$showks		=	$_POST['showks'];
	$kstyp		=	$_POST['kstyp'];
	$showroom	=	$_POST['showroom'];
	$showmenu	=	$_POST['showmenu'];
	$showweath	=	$_POST['showweath'];
	$showhmsgnu	=	$_POST['showhmsgnu'];
	$showuserdefgnu	=	$_POST['showuserdefgnu'];
	$temp		=	$_POST['temp'];
	$dofht		=	$_POST['dofht'];
	$orderpulldown	=	$_POST['orderpulldown'];
	$valuetime	=	$_POST['valuetime'];
	$atorder	=	$_POST['atorder'];
	$attime		=	$_POST['attime'];

	$fhtdev		=	$_POST['fhtdev'];
	$fs20dev	=	$_POST['fs20dev'];
	$culhmdev	=	$_POST['culhmdev'];
	$errormessage	=	$_POST['errormessage'];



	if (! isset($showrss)) $showrss=$_GET['showrss'];
	if (! isset($rssorder)) $rssorder=$_GET['rssorder'];
	if ($rssorder=="") 
		{unset($rssorder);}
	else
		{$Action='exec'; $order=$rssorder;}

	
	if (! isset($showhmsgnu)) $showhmsgnu=$_GET['showhmsgnu'];
	if ($showhmsgnu=="") unset($showhmsgnu);

	if (! isset($showuserdefgnu)) $showuserdefgnu=$_GET['showuserdefgnu'];
	if ($showuserdefgnu=="") unset($showuserdefgnu);

	if (! isset($showfs20)) $showfs20=$_GET['showfs20'];
	if ($showfs20=="") unset($showfs20);

	if (! isset($showfht)) $showfht=$_GET['showfht'];
	if ($showfht=="") unset($showfht);
	if ($showfht=="none") unset($showfht);

	if (! isset($showweath)) $showweath=$_GET['showweath'];
	if ($showweath=="") unset($showweath);
	if ($showweath=="none") unset($showweath);

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

	if (! isset($culhmdev)) $culhmdev=$_GET['culhmdev'];
	if ($culhmdev=="") unset($culhmdev);

	if (! isset($errormessage)) $errormessage=$_GET['errormessage'];
	if ($errormessage=="") unset($errormessage);
	
	if (! isset($showpics)) $showpics=$_GET['showpics'];
	if ($showpics=="none") unset($showpics);



# try to get the URL:
	$homeurl='http://'.$_SERVER['HTTP_HOST'].$_SERVER['SCRIPT_NAME'];
	 $forwardurl=$homeurl.'?';
         $phpfileurl=$_SERVER['SCRIPT_NAME'];
	$testFirstStart=$_SERVER['QUERY_STRING'];
	if ($testFirstStart=='')  ##new session (??) then start-values
	{
		if ($showAT=='yes') $showat='yes';
		if ($showLOGS=='yes') $showlogs='yes';
		if ($showNOTI=='yes') $shownoti='yes';
		if ($showHIST=='yes') $showhist='yes';
		if ($showPICS=='yes') $showpics='yes';
		if ($showWeath=='yes') $showweath='1';
	}


	if (isset ($showfht)) { $forwardurl=$forwardurl.'&showfht='.$showfht;};
	if (isset ($fs20dev)) 
	{ $forwardurl=$forwardurl.'&fs20dev='.$fs20dev.'&orderpulldown='.$orderpulldown.'&showmenu='.$showmenu.'&showroom='.$showroom.'&showweath'.$showweath;};
	if (isset ($culhmdev)) 
	{ $forwardurl=$forwardurl.'&culhmdev='.$culhmdev.'&orderpulldown='.$orderpulldown.'&showmenu='.$showmenu.'&showroom='.$showroom.'&showweath'.$showweath;};
	if (isset ($showks)) { $forwardurl=$forwardurl.'&showks='.$showks.'&kstyp='.$kstyp;};
	if (isset ($showhmsgnu)) { $forwardurl=$forwardurl.'&showhmsgnu='.$showhmsgnu;};
	if (isset ($showuserdefgnu)) { $forwardurl=$forwardurl.'&showuserdefgnu='.$showuserdefgnu;};
	if (isset ($showroom)) { $forwardurl=$forwardurl.'&showroom='.$showroom;};
	if (isset ($shownoti)) { $forwardurl=$forwardurl.'&shownoti';};
	if (isset ($showlogs)) { $forwardurl=$forwardurl.'&showlogs';};
	if (isset ($showat)) { $forwardurl=$forwardurl.'&showat';};
	if (isset ($showpics)) { $forwardurl=$forwardurl.'&showpics';};
	if (isset ($showhist)) { $forwardurl=$forwardurl.'&showhist';};
	if (isset ($showfs20)) { $forwardurl=$forwardurl.'&showfs20='.$showfs20;};
	if (isset ($showculhm)) { $forwardurl=$forwardurl.'&showculhm='.$showculhm;};
	if (isset ($showweath)) { $forwardurl=$forwardurl.'&showweath='.$showweath;};
	if (isset ($showmenu)) 
	{ $forwardurl=$forwardurl.'&fs20dev='.$fs20dev.'&orderpulldown='.$orderpulldown.'&valuetime='.$valuetime.'&showmenu='.$showmenu.'&showroom='.$showroom;}
	unset($link);
	if (isset ($showlogs)) $link=$link.'&showlogs'; 
	if (isset ($shownoti)) $link=$link.'&shownoti'; 
	if (isset ($showhist)) $link=$link.'&showhist'; 
	if (isset ($showat)) $link=$link.'&showat'; 
	if (isset ($showmenu)) $link=$link.'&showmenu='.$showmenu; 
	if (isset ($showweath)) $link=$link.'&showweath='.$showweath; 
	if (isset ($showfht)) $link=$link.'&showfht='.$showfht; 
	if (isset ($showhmsgnu)) $link=$link.'&showhmsgnu='.$showhmsgnu; 
	if (isset ($showuserdefgnu)) $link=$link.'&showuserdefgnu='.$showuserdefgnu; 
	if (isset ($showks)) $link=$link.'&showks='.$showks; 
	if (isset ($showpics)) $link=$link.'&showpics'; 


switch ($Action):
	Case exec:
		if ($kioskmode=='off') 
		{
			$order=str_replace("\\","",$order);
			$order=str_replace("@","+",$order);
			execFHZ($order,$fhem,$fhemport);
		}
		header("Location:  $forwardurl&errormessage=$errormessage");
		break;
	Case exec2:
		if ($atorder=='at') 
		{ $atorder='define '.randdefine().' '.$atorder; }
		$order="$atorder $attime set $fs20dev $orderpulldown $valuetime";
		if ($kioskmode=='off') execFHZ($order,$fhem,$fhemport);
		header("Location:  $forwardurl");
	Case exec3:
		if ($atorder=='at') 
		{ $atorder='define '.randdefine().' '.$atorder; }
		if (! isset($fhtdev)) {echo "FHT-Device not set - exit"; break;}
		$order="$atorder $attime set $fhtdev $orderpulldown $valuetime";
		if ($kioskmode=='off') execFHZ($order,$fhem,$fhemport);
	Case exec4:
		if ($atorder=='at') 
		{ $atorder='define '.randdefine().' '.$atorder; }
		$order="$atorder $attime set $culhmdev $orderpulldown $valuetime";
		if ($kioskmode=='off') execFHZ($order,$fhem,$fhemport);
		header("Location:  $forwardurl");
	Case execfht:
		$order="set $dofht desired-temp $temp";
		if ($kioskmode=='off') execFHZ($order,$fhem,$fhemport);
		header("Location:  $forwardurl");
		break;
	Case showfht|showroom|showks|showhmsgnu|hide|showuserdefgnu|showpics:
		header("Location: $forwardurl");
		break;
	default:
endswitch;


if (! isset($showroom)) $showroom="ALL";
if (($taillog==1) and (isset ($showhist)) ) exec($taillogorder,$tailoutput);

#####################################################################################################################################
#executes over the network to the fhem.pl (or localhost)
function execFHZ($order,$machine,$port)
{
global $errormessage;

 $fp = stream_socket_client("tcp://$machine:$port", $errno, $errstr, 30);
         if (!$fp) {
           echo "$errstr ($errno)<br />\n";
        } else {
           fwrite($fp, "$order;quit\n");
		#buggy in fhem by notify?
               	#$errormessage= fgets($fp);
           fclose($fp);
        }
return $errormessage;
}



###### make an array from the xmllist
unset($output);
$stack = array();
$output=array();
unset($longxml);

$version = explode('.', phpversion());


######################################################################
# get the xmllist from fhem
	$fp = stream_socket_client("tcp://$fhem:$fhemport", $errno, $errstr, 30);
	if (!$fp) {
	   echo "$errstr ($errno)<br />\n";
	} else {
	   fwrite($fp, "xmllist;quit\n");
	   $outputvar=stream_get_contents($fp);
	   array_push($output,$outputvar);
	   fclose($fp);
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
   xml_parser_set_option($parser, XML_OPTION_TARGET_ENCODING, "UTF-8");
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




#change the xmllist into an intern array
$data = $output[0];
  if (!xml_parse($xml_parser, $data)) {
        $now=date($timeformat);
        echo("There is a xmllist file for debugging: $AbsolutPath/tmp/debugxml$now<br><br>");
        $handle=fopen("tmp/debugxml$now","w");
        fwrite($handle,$outputvar);
        $warning=sprintf("XML error: %s at line %d\n",
           xml_error_string(xml_get_error_code($xml_parser)),
           xml_get_current_line_number($xml_parser));
	echo $warning;
	fwrite($handle,$warning);
        fclose($handle);
   }




xml_parser_free($xml_parser);




#print_r($stack);
#exit;


#searching for rooms/fs20/HomeMatic/Logpaths
	$rooms=array();
	$fs20devs=array();
	$culhmdevs=array();
	$fhtdevs=array();
	$logpaths=array();
	$actors=array();

	for($i=0; $i < count($stack[0][children]); $i++) 
	{
	      if ((substr($stack[0][children][$i][name],0,5)=='FS20_') 
		  || (substr($stack[0][children][$i][name],0,4)=='X10_'))
	      {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 $fs20devxml=$stack[0][children][$i][children][$j][attrs][name];
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   #$check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
			# if ($check=='ATTR')
			  #{
				if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
				{
			  	  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
				}
			  #}#
			}
		  	 if ((! in_array($fs20devxml,$fs20devs)) AND ( $room != 'hidden')) array_push($fs20devs,$fs20devxml);
			}
	      }#FS20



####################################################  HomeMatic

	      elseif ((substr($stack[0][children][$i][name],0,7)=='CUL_HM_')) 
	      {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 $culhmdevxml=$stack[0][children][$i][children][$j][attrs][name];
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			  # $check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
			 #if ($check='ATTR')
			  #{
				if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
				{
			  	  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
				}
			  #}#
			}
		  	 if ((! in_array($culhmdevxml,$culhmdevs)) AND ( $room != 'hidden')) array_push($culhmdevs,$culhmdevxml);
			}
	      }#HomeMatic


####################################################  FHTs


	       elseif (substr($stack[0][children][$i][name],0,4)=='FHT_')
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



####################################################  HMS and CUL_WS



	       elseif ((substr($stack[0][children][$i][name],0,4)=='HMS_') || (substr($stack[0][children][$i][name],0,7)=='CUL_WS_'))

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
	       } # HMS and CUL_WS

#################################################### LogpathFileLOG


	       elseif (substr($stack[0][children][$i][name],0,8)=='FileLog_')
	       {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="currentlogfile") 
					{$logpathstack=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($logpathistack,$logpaths)) array_push($logpaths,$logpathstack);
					}
				}
		       }
	       } # FileLog



#################################################### INTERNAL Logpath


	       elseif (substr($stack[0][children][$i][name],0,9)=='_internal')
	       {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="currentlogfile") 
					{$fhemlog=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($fhemlog,$logpaths)) array_push($logpaths,$fhemlog);
					}
				}
		       }
	       } # _internal_



#################################################### SCIVT


	       elseif (substr($stack[0][children][$i][name],0,6)=='SCIVT_')
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
	       } # SCIVT



#################################################### SCIVT

	       elseif (substr($stack[0][children][$i][name],0,6)=='KS300_')
	       {
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			 #  $check=$stack[0][children][$i][children][$j][children][$k][attrs][name];
			 #if ($check='ATTR')
			  #{
				if (($stack[0][children][$i][children][$j][children][$k][attrs][key])=='room')
				{
			  	  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				  	 if (! in_array($room,$rooms)) array_push($rooms,$room);
					}
			#	}
			  }
			}
		}
	} # end searching rooms /logpaths in the array from fhem
	# user defined rooms?
	if ($UserDefs==1)
	{
		for($i=0; $i < count($userdef); $i++)
                {
                         $room=$userdef[$i]['room'];
		  	if (! in_array($room,$rooms)) array_push($rooms,$room);
		}
	}


	array_push($rooms,'ALL');
	sort($rooms);




#print_r($rooms); echo "Count: $countrooms"; exit;
#print_r($fs20devs); # exit;
#echo "#################################";
#print_r($culhmdevs);  exit;
#echo count($stack[0][children]);exit;
#print_r($logpaths);  exit;
#exit;




# Print Array on Screen

 $now=date($timeformat);


# only RSS-Feeds?? 
 if (isset($showrss)) { include "include/rssfeeds.php"; exit; }



###### write the header on screen
 echo "
         <html>
	 <head>
	 <meta http-equiv='refresh' content='$urlreload; URL=$forwardurl'>
	 <meta http-equiv='pragma' content='no-cache'>
	 <meta http-equiv='expires' content='0'>
	 <meta http-equiv='Cache-Control' content='no-cache'>
	 <meta http-equiv='content-type' content='text/html; charset=UTF-8'>

	 <link rel='alternate' type='application/rss+xml' title='$RSStitel' href='$phpfileurl?showrss'>
 	 <link rel='shortcut icon' href='include/fs20.ico' >
	 <title>$titel</title>";
 	  include ("include/style.css");	 
 echo "	 </head>";


 echo"      <body $bodybg>
	$errormessage
	\r<table width='$winsize' cellspacing='1' cellpadding='10' border='0' $bgcolor1><tr><td></td></tr>\r</table>
	\r<table width='$winsize' cellspacing='1' cellpadding='0' border='0' align='CENTER' $bg4>
	  <tr> 
	      <td $bg4 width='100%'> 
	      \r<table $bg5 width='100%' cellspacing='0' cellpadding='0' border='0'>
	              <tr> <td>
	\r<table width='100%' cellspacing='2' cellpadding='2' align=center border='0'>
	<tr><td $bg1 colspan=4><br>
		<font size=3 $fontcolor1><center><b>$titel $now</b></font>
		</font></center>
		 <font size=-2 $fontcolor1><div align='right'>v$pgm3version</div></font>
		</td></tr>";
	
	###################### Webcam
	
 	if ($showwebcam==1)
	{	
	    echo "  <tr>
                <td $bg1 colspan=4><font $fontcolor1>
                \r<table  cellspacing='0' cellpadding='0' width='100%'>
                        <tr>
                        <td><font $fontcolor1> WEBCAM </font>";
		 if (! isset($showpics))
                 { echo "<a href=$formwardurl?showpics$link>show pics</a>";}
                else
                { echo "<a href=$formwardurl?$link&showpics=none>hide pics</a>";}

                        
   	    echo"	</td>
                        <td align=right>
	    ";
     if (($webcamroom != 'hidden') 
         and ($showroom=='ALL' or $showroom==$webcamroom or $webcamroom=='donthide'))
	    if (isset($showpics))
	    {
	    for($i=0; $i < count($webcam); $i++)
            {  
		$webcam1=$webcam[$i];
		$pos = strpos($webcam1,'://'); # e.g. http://..
		if ($pos === false) # picture instead of an URL
		{
			$webcamname=$webcam[$i];
		}
		else
		{
			$webcamname=str_replace("/","",$webcam1);
			$webcamname=str_replace(":","",$webcamname);
			$order="$wgetpath -O tmp/$webcamname $webcam1";
			exec($order,$res);
        		$errormessage = $res[0];
			echo $errormessage;
		}
	 	echo"<a href='tmp/$webcamname'><img src='tmp/$webcamname' width='$webcamwidth' border=2></a>";
	     }   
	     }
	     echo"
			</td>
			</tr>
		\r</table>
		</td>
		</tr>
		";
	
	};




       ############################ WEATHER
     if ($enableweather==1)
	{
	echo "<tr><td $bg1 colspan=4><font $fontcolor1>\r<table  cellspacing='0' cellpadding='0' width='100%'>
		<tr><td><font $fontcolor1>WEATHER</td><td align=right><font $fontcolor1><b>";
	if ($showweath != '1')	
		{ echo "<a href=$formwardurl?showweath=1&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showweath=none>hide</a>";}

	echo "</b></font></td></tr>\r</table>";
	echo "</font></td></tr>";
     if (($weatherroom != 'hidden') 
         and ($showroom=='ALL' or $showroom==$weatherroom or $weatherroom=='donthide') 
         and ($showweath==1)) include 'include/weather.php';
     }



       ############################ FHZ
	if ($show_fs20pulldown==1 or $show_general==1 or $show_hmpulldown==1 or $show_fhtpulldown==1)
	{
	echo "<tr><td $bg1 colspan=4><font $fontcolor1>\r<table  cellspacing='0' cellpadding='0' width='100%'>
		<tr><td><font $fontcolor1>FHZ_DEVICE</td><td align=right><font $fontcolor1><b>";
	if ($showmenu != '1')	
		{ echo "<a href=$formwardurl?showmenu=1&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showmenu=none>hide</a>";}

	echo "</b></font></td></tr>\r</table>";
	echo "</font></td></tr>";
	}


	if ($showmenu=='1')
	{
		if ($show_general=='1') 
		{echo "
		<tr>
		<td colspan=1 align=right $bg2><font  $fontcolor3> General: </font></td>
		<td align=left $bg2 colspan=1><font $fontcolor3>
		<form action=$forwardurl method='POST'>
		<input type=text name=order size=61>
		<input type=hidden name=showfht value=$showfht>
		<input type=hidden name=showhms value=$showhms>
		<input type=hidden name=showmenu value=$showmenu>
		<input type=hidden name=Action value=exec>
		<input type=submit value='go!'></form></td>
		</tr>";
		};

	if ($show_fs20pulldown=='1') include 'include/fs20pulldown.php';
	if ($show_hmpulldown=='1') include 'include/hmpulldown.php';
	if ($show_fhtpulldown=='1') include 'include/fhtpulldown.php';
	if ($show_logpulldown=='1') include 'include/logpulldown.php';
	};



	############################ ROOMS
	if (($showroombuttons==1) and (count($rooms)>1))
	{

echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>                    
                        \r\r<table  cellspacing='0' cellpadding='0' width='100%'
>                                                                               
                        <tr><td><font $fontcolor1>ROOMS</td><td align=rig
ht><font $fontcolor1><b>                                                        
                        </font></td></tr>\r</table></td></tr>\r";

		echo "<tr><td $bg2 colspan=4>";
		$counter=0;
	 	for($i=0; $i < count($rooms); $i++)
		 	{
				 $room=$rooms[$i];
				 if ($room != 'hidden')
		 		{
				echo"<a href='$phpfileurl?Action=showroom&showroom=$room$link'><img src='include/room.php?room=$room&showroom=$showroom'></a>";
				$counter++;

				if  (fmod($counter,$roommaxiconperline)== 0.0) echo "<br>";
				} else $counter--;
			}
		echo "</td></tr>";
	}	

#####################################################################################################################

	## now the xmllist will be writen on screen as html
	##### Let's go.... :-)))))
	for($i=0; $i < count($stack[0][children]); $i++) 
	{
	############################
	      if ((substr($stack[0][children][$i][name],0,5)=='FS20_')
		  || (substr( $stack[0][children][$i][name],0,4)=='X10_')
		  || (substr( $stack[0][children][$i][name],0,7)=='CUL_HM_'))
	      {
			$type=$stack[0][children][$i][name];
			echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>
                        \r\r<table  cellspacing='0' cellpadding='0' width='100%'>
                        <tr><td><font $fontcolor1>$type</td><td align=right><font $fontcolor1><b>
                        </font></td></tr>\r</table></td></tr>\r";
			$counter=0;
			echo "<tr><td $bg2 colspan=4>";
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			 $fs20=$stack[0][children][$i][children][$j][attrs][name];
			 $state=$stack[0][children][$i][children][$j][attrs][state];
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			$check=$stack[0][children][$i][children][$j][children][$k][name];
				switch ($check) {
				   case 'STATE':
			      	   $measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
					break;
				}
			

			$check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
			 switch ($check) {
				case 'room':
			  	        $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];break;
				case 'webCmd':
			  	  	$wcmd=$stack[0][children][$i][children][$j][children][$k][attrs][value];break;
				case 'follow-on-for-timer':
			  	  	$foft=$stack[0][children][$i][children][$j][children][$k][attrs][value];break;
				case 'icon':
			  	  	$icon=$stack[0][children][$i][children][$j][children][$k][attrs][value];break;
				case 'eventMap':
			  	  	$eventMap=$stack[0][children][$i][children][$j][children][$k][attrs][value];break;
				case 'subType':
			  	  	$subType=$stack[0][children][$i][children][$j][children][$k][attrs][value];break;
			  }
					
			}



			 If (($eventMap!='')) {
			    If ((substr($eventMap,0,1)==',') or (substr($eventMap,0,1)=='/')) {
				$eMap_sign=(substr($eventMap,0,1));
				$eventMap=substr($eventMap,1);
				$eventMap=str_replace($eMap_sign, ":", $eventMap);
			    }
			    else {
				$eventMap=str_replace(" ", ":", $eventMap);
			    }
			    $eMapsep=explode(":",$eventMap);
			    if ($state==$eMapsep[1]) {
			      $state=$eMapsep[0];
			      $emap=$eMapsep[1];
			    }
			    elseif ($state==$eMapsep[3]) {
			      $state=$eMapsep[2];
			      $emap=$eMapsep[3];
			    }
			    elseif ($state=='off') {
			      $emap=$eMapsep[3];
			    }
			    elseif ($state!='off') {
			      $emap=$eMapsep[1];
			    }
			 };

			 $tmp_file=$AbsolutPath."/tmp/FS20.".$fs20."_foft.txt";
			 if (($state=='off') and (file_exists($tmp_file))) {
			    $delfile2=$AbsolutPath."/tmp/FS20.".$fs20.".log.".$measured.".png";
			       unlink ($tmp_file);
			       unlink ($delfile2);
			 }

			 if (($state=='off') and (substr($wcmd,0,12)=='on-for-timer')) {
			    $wcmd_count = strpos($wcmd, ':',0); 
			    $wcmd_order = substr($wcmd, 0, $wcmd_count);
			    $order="set $fs20 $wcmd_order";
			 }
			 elseif (($state!='off')) {
			    $order="set $fs20 off";
			    if ((substr($state,0,12)=='on-for-timer')) {
			       if (file_exists($tmp_file))
			       {}
			       else{
				      $x1=fopen ($tmp_file, "w");
				      fwrite ($x1,$foft);
				      fclose ($x1);
			       }
			    }
			 }
			 else {
			 $order="set $fs20 on";
			 };


			 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
			 {
			 	$counter++;
				echo"<a href='$phpfileurl?Action=exec&order=$order&showroom=$showroom$link'><img src='include/fs20.php?drawfs20=$fs20&statefs20=$state&datefs20=$measured&icon=$icon&emap=$emap&subType=$subType&room=$room'></a>";
				if  (fmod($counter,$fs20maxiconperline)== 0.0) echo "<br>";
				array_push($actors,array($phpfileurl,$order,$showroom,$link,$fs20,$state,$measured,$icon,$emap,$subType,$room));
			 };
#			 $fs20="";
			 $state="";
			 $check="";
			 $measured="";
			 $room="";
			 $wcmd="";
			 $foft="";
			 $icon="";
			 $eventMap="";
			 $subType="";
			 $emap="";
			 }
			 	echo "</td></tr>\r";
				if (isset($showfs20) and $showgnuplot == 1)
			 	{   
                                 	drawgnuplot($showfs20,"FS20",$gnuplot,$pictype,$logpath, $FHTyrange,$FHTy2range,$DBUse);
					$FS20dev1=$showfs20.'1';
                                	echo "\r<tr><td colspan=5 align=center><br><img src='tmp/$showfs20.$pictype'><br><br><br>
					<img src='tmp/$FS20dev1.$pictype'><br><br>
                                        </td></tr>
			 		      <tr><td colspan=4><hr color='#AFC6DB'></td></tr>";
				}
	       }
	############################
	       elseif (substr($stack[0][children][$i][name],0,4)=='FHT_')
	       {
			$type=$stack[0][children][$i][name];
			#echo "<tr><td $bg1 colspan=4><font $fontcolor1>";
	      		#echo "$type</font></td></tr>\r";
			echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>
                        \r\r<table  cellspacing='0' cellpadding='0' width='100%'>
                        <tr><td><font $fontcolor1>$type</td><td align=right><font $fontcolor1><b>
                        </font></td></tr>\r</table></td></tr>\r";



		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
				$room="";
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   $check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
				   if ( $check=="room") 
					{$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					}
				   if ( $check=="warnings") 
					{$battery=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					}
				}
		 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
		 {
		    
			 $FHTdev=$stack[0][children][$i][children][$j][attrs][name];
			 if ($showfht == $FHTdev)
			 	{echo "\r<tr valign=center><td align=center $bg2 valign=center> 
				       <form action=$forwardurl method='POST'>
				       <input type=hidden name=Action value=hide>
				       <input type=hidden name=showfht value=none>
				       <input type=hidden name= value=none>
			 		<input type=hidden name=showroom value=$showroom>
				       <input type=submit value='hide'></form>
					<a href=$forwardurl&showmenu=1&fhtdev=$FHTdev&orderpulldown=desired-temp&valuetime=20.0>adjust</a></td>";
			 	}
			 else
			 	{echo "\r<tr valign=center><td align=center $bg2 valign=center> 
				       <form action=$forwardurl method='POST'>
				       <input type=hidden name=Action value=showfht>
				       <input type=hidden name=showfht value=$FHTdev>
			 		<input type=hidden name=showroom value=$showroom>
		    	      	       <input type=hidden name=showhms value=$showhms>
				       <input type=submit value='show'></form>
					<a href=$forwardurl&showmenu=1&fhtdev=$FHTdev&orderpulldown=desired-temp&valuetime=20.0>adjust</a></td>";
			 	};
				   
				echo "\r<td $bg2 colspan='3'> 
				<img src='include/fht.php?drawfht=$FHTdev&room=$room&battery=$battery' width='$imgmaxxfht' height='$imgmaxyfht'>
				</td>";
				echo "</tr>";
			 	
				if ($showfht==$FHTdev and $showgnuplot == 1)
			 	{   
                                 	drawgnuplot($FHTdev,"FHT",$gnuplot,$pictype,$logpath, $FHTyrange,$FHTy2range,$DBUse);
					$FHTdev1=$FHTdev.'1';
                                	echo "\r<tr><td colspan=5 align=center><br><img src='tmp/$FHTdev.$pictype'><br><br><br>
					<img src='tmp/$FHTdev1.$pictype'><br><br>
                                        </td></tr>
			 		      <tr><td colspan=4><hr color='#AFC6DB'></td></tr>";
				}
				if ( $showfht==$FHTdev)
				{
				echo "\r<tr><td colspan=4>\r<table border=0><tr>";
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   	$name=$stack[0][children][$i][children][$j][children][$k][attrs][key];
					$value=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					$measured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
			        	echo "\r<td><tr><td colspan=1> $FHTdev (FHT): </td><td>$name</td><td>$value
					      </td><td>$measured</td></tr></td>";
				   }
				echo "</tr>\r</table></td></tr>\r\r";
				}
			}
		}
	       }
	############################
	       elseif ((substr($stack[0][children][$i][name],0,4)=='HMS_') or (substr($stack[0][children][$i][name],0,6)=='CUL_WS'))
	       {
			$type=$stack[0][children][$i][name];
			#echo "\r<tr><td $bg1 colspan=4><font $fontcolor1>";
#	      		echo "$type</font></td></tr>";
			echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>
                        \r\r<table  cellspacing='0' cellpadding='0' width='100%'>
                        <tr><td><font $fontcolor1>$type</td><td align=right><font $fontcolor1><b>
                        </font></td></tr>\r</table></td></tr>\r";




		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
				$room="";
			 	for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
				{
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="battery") 
					{$battery=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					}
				   if ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="room") 
					{$room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
					}
				   if (( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="type")  or
				      ( $stack[0][children][$i][children][$j][children][$k][attrs][key]=="TYPE") )
					{$type=$stack[0][children][$i][children][$j][children][$k][attrs][value];};
				}
		 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
		 {
			$HMSdev=$stack[0][children][$i][children][$j][attrs][name];
			if ($type=="HMS100T" or $type=="HMS100TF" or $type=="CUL_WS")
			{
			if ($showhmsgnu== $HMSdev) {$formvalue="hide";$gnuvalue="";}
			else {$formvalue="show";$gnuvalue=$HMSdev;};
			echo "\r<tr valign=center><td align=center $bg2 valign=center>
                                       <form action=$forwardurl method='POST'>
                                       <input type=hidden name=Action value=showhmsgnu>
                                        <input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=battery value=$battery>
                                        <input type=hidden name=showhmsgnu value=$gnuvalue>
                                       <input type=submit value='$formvalue'></form></td><td $bg2 colspan=3>";
				
			}
			else
		 	{echo "\<tr><td $bg2><td $bg2 colspan=3> ";}
		       	
			echo "<img src='include/hms100.php?drawhms=$HMSdev&room=$room&type=$type&battery=$battery' width='$imgmaxxhms' height='$imgmaxyhms'></td> </tr>";
		
		if ($showhmsgnu == $HMSdev and $showgnuplot == 1)
                                { drawgnuplot($HMSdev,$type,$gnuplot,$pictype,$logpath,0,0,$DBUse);
				$HMSdev1=$HMSdev.'1';
                                echo "\r<tr><td colspan=5 align=center><br><img src='tmp/$HMSdev.$pictype'><br><br><br>
					<img src='tmp/$HMSdev1.$pictype'><br><br>
                                        </td></tr>";
                }
		}

		       }
	       }
	############################
	       elseif (substr($stack[0][children][$i][name],0,6)=='KS300_' or substr($stack[0][children][$i][name],0,6)=='WS300_')
	       {
			$type=$stack[0][children][$i][name];
			echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>
                        \r\r<table  cellspacing='0' cellpadding='0' width='100%'>
                        <tr><td><font $fontcolor1>$type</td><td align=right><font $fontcolor1><b>
                        </font></td></tr>\r</table></td></tr>\r";
                        for($j=0; $j < count($stack[0][children][$i][children]); $j++)
                         {
                         $KSdev=$stack[0][children][$i][children][$j][attrs][name];
                        $room='';
                        for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
                        {
                           $check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
                           $check2=$stack[0][children][$i][children][$j][children][$k][attrs][name];
                         if ($check=='room')  $room=$stack[0][children][$i][children][$j][children][$k][attrs][value];
                         elseif ($check=='willi') $willi=1;
                         elseif ($check=='avg_day') $KSavgday=$stack[0][children][$i][children][$j][children][$k][attrs][value];
                         elseif ($check=='temperature') $KSmeasured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
                         elseif ($check=='avg_month') $KSavgmonth=$stack[0][children][$i][children][$j][children][$k][attrs][value];
				#  for older versions...
                         if ($check2=='avg_month') $KSavgmonth=$stack[0][children][$i][children][$j][children][$k][attrs][value];
                         elseif ($check2=='avg_day') $KSavgday=$stack[0][children][$i][children][$j][children][$k][attrs][value];
                         elseif ($check2=='temperature') $KSmeasured=$stack[0][children][$i][children][$j][children][$k][attrs][measured];
                         elseif ($check2=='willi') $willi=1;
                        }

		 	if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
		 	{
			 $Xks=$imgmaxxks;
			 $Yks=$imgmaxyks*4;
			##gnuplot
			if ($showks == $KSdev)
                                {echo "\r<tr valign=center><td align=center $bg2 valign=center>
                                       <form action=$forwardurl method='POST'>
                                       <input type=hidden name=Action value=hide>
                                        <input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=showks value=''>
                                       <input type=submit value='hide'></form></td>";}
                         else
					{echo "\r<tr valign=center><td align=center $bg2 valign=center>
                                       <form action=$forwardurl method='POST'>";

                                        echo "<input type=hidden name=Action value=showks><br>Temp./Hum.<br>
                                                <input type=radio name=kstyp value=\"1\" checked><br><br>";
                                        if (! isset ($willi)) echo "Wind/Rain<br>"; else  echo "Air Pressure/ Willi<br>";
                                        echo "<input type=radio name=kstyp value=\"2\"><br><br>";

                                        echo "<input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=showks value=$KSdev>
                                       <input type=submit value='show'></form></td>";
                         };

			 echo "\r<td $bg2 center=align colspan=3>";
                         echo "<img src='include/ks300.php?drawks=$KSdev&room=$room&avgmonth=$KSavgmonth&avgday=$KSavgday' width='$Xks' height='$Yks'>";
                         echo "</td></tr>";
                         if (! isset ($willi)) $drawtype="KS300"; else $drawtype="WS300";
                        if (($showks == $KSdev) and  $showgnuplot=='1')
                                 {
                                if ($kstyp=="1")
                                {
                                        drawgnuplot($KSdev,$drawtype."_t1",$gnuplot,$pictype,$logpath,0,0,$DBUse);
                                }
                                else
                                {
                                        drawgnuplot($KSdev,$drawtype."_t2",$gnuplot,$pictype,$logpath,0,0,$DBUse);
                                }
                                $KSdev1=$KSdev.'1';
                                echo "\r<tr><td colspan=5 align=center><br><img src='tmp/$KSdev.$pictype'><br><br><br>
                                        <img src='tmp/$KSdev1.$pictype'><br><br>
                                        </td></tr>";
                        }

                        }
                        }
                }
			 
	############################
	       elseif ($stack[0][children][$i][name]=='LOGS'or $stack[0][children][$i][name]=='FileLog_LIST')
	       {
		echo "\r<tr><td $bg1 colspan=4><font $fontcolor1>
			\r<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>LOGS</td><td align=right><font $fontcolor1><b>";
		if (! isset ($showlogs))	
		{ echo "<a href=$formwardurl?showlogs&showroom=$showroom$link>show</a>";}
		else
		{ 
		echo "<a href=$formwardurl?showroom=$showroom$link&showlogs=none>hide</a>";}
	
	      		echo "</font></td></tr>\r</table></td></tr>\r";
		if (isset ($showlogs))
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   	$check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
			 	if ($check=='DEF')
			  	{
				$value=$stack[0][children][$i][children][$j][children][$k][attrs][value];
			  	}	
			}
			 	$name=$stack[0][children][$i][children][$j][attrs][name];
			 	echo "\r<tr><td colspan=1 border=0>Log:</td>
					<td colspan=2 border=0>$value / $name </td></tr>";
				
			 }
		} 
	############################
	       elseif ($stack[0][children][$i][name]=='NOTIFICATIONS' or $stack[0][children][$i][name]=='notify_LIST')
	       {
		echo "\r<tr><td $bg1 colspan=4><font $fontcolor1>
			\r<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>NOTIFICATIONS</td><td align=right><font $fontcolor1><b>";
		if (! isset ($shownoti))	
		{ echo "<a href=$formwardurl?shownoti&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&shownoti=none>hide</a>";}
	      	echo "</font></td></tr>\r</table></td></tr>\r\r";

		if (isset ($shownoti))
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   	$check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
			 	if ($check=='DEF')
			  	{
				$value=$stack[0][children][$i][children][$j][children][$k][attrs][value];
			  	}	
			}
			 	$name=$stack[0][children][$i][children][$j][attrs][name];
			 	echo "\r<tr><td colspan=1>Notification:</td><td colspan=2>$value / $name</td></tr>";
			 }
		} 
	############################
	       elseif ($stack[0][children][$i][name]=='AT_JOBS' or $stack[0][children][$i][name]=='at_LIST')
	       {
		echo "\r<tr><td $bg1 colspan=4><font $fontcolor1>
			\r<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>AT_JOBS</td><td align=right><font $fontcolor1><b>";
		if (! isset ($showat))	
		{ echo "<a href=$formwardurl?showat&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showat=none>hide</a>";}
	      	echo "</font></td></tr>\r</table></td></tr>\r\r";


		if (isset ($showat))
		 	for($j=0; $j < count($stack[0][children][$i][children]); $j++)
			 {
				$command=$stack[0][children][$i][children][$j][attrs][name];
				$next=$stack[0][children][$i][children][$j][attrs][state];
				$order=$command;
			for($k=0; $k < count($stack[0][children][$i][children][$j][children]); $k++)
			{
			   	$check=$stack[0][children][$i][children][$j][children][$k][attrs][key];
			 	if ($check=='DEF')
			  	{
				$value=$stack[0][children][$i][children][$j][children][$k][attrs][value];
			  	}	
			}

				$order='delete '.$order;
			 	echo "\r<tr><td> AT-Job: </td><td><a href='$phpfileurl?Action=exec&order=$order$link'>del </a> $value / $next / $command</td></tr>";
			 }
		} 
	};
## that is all of fhem
##################### User defined graphics??
	if ($UserDefs==1)
        {
	 echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>
                        \r\r<table  cellspacing='0' cellpadding='0' width='100%'>
                        <tr><td><font $fontcolor1>USER DEFINED</td><td align=right><font $fontcolor1><b>
			</font></td></tr>\r</table></td></tr>\r";

		 $type='userdef';

                for($i=0; $i < count($userdef); $i++)
                {
                      $room=$userdef[$i]['room'];
		      $UserDef=$userdef[$i]['name'];
		      $imgmaxxuserdef=$userdef[$i]['imagemax'];
		      $imgmaxyuserdef=$userdef[$i]['imagemay'];


		 if (($room != 'hidden') and ($showroom=='ALL' or $showroom==$room))
                 {
                        if ($showuserdefgnu== $UserDef) {$formvalue="hide";$gnuvalue="";}
                        else {$formvalue="show";$gnuvalue=$UserDef;};
                        echo "\r<tr valign=center><td align=center $bg2 valign=center colspan=1>
                                       \r<form action=$forwardurl method='POST'>
                                       <input type=hidden name=Action value=showuserdefgnu>
                                        <input type=hidden name=showroom value=$showroom>
                                        <input type=hidden name=showuserdefgnu value=$gnuvalue>
                                       <input type=submit value='$formvalue'></form></td><td $bg2 colspan=1>\r";

                        echo "\r<img src='include/userdefs.php?userdefnr=$i' width='$imgmaxxuserdef' height='$imgmaxyuserdef'></td> </tr>";

                if ($showuserdefgnu == $UserDef and $showgnuplot == 1)
                                {drawgnuplot($UserDef,$type,$gnuplot,$pictype,$logpath,$userdef[$i],$i,$DBUse);
                                $UserDef1=$UserDef.'1';
                                echo "\r<tr><td colspan=5 align=center><br><img src='tmp/$UserDef.$pictype'><br><br><br>
                                        <img src='tmp/$UserDef1.$pictype'><br><br>
                                        </td></tr>";
                }
                }# /not room hidden

                }

        } #/userdefs

##################### taillog


	if ($taillog==1) 
	{
		echo "\r\r<tr><td $bg1 colspan=4><font $fontcolor1>
			\r\r<table  cellspacing='0' cellpadding='0' width='100%'>
			<tr><td><font $fontcolor1>$taillogorder</td><td align=right><font $fontcolor1><b>";
		if (! isset ($showhist))	
		{ echo "<a href=$formwardurl?showhist&showroom=$showroom$link>show</a>";}
		else
		{ echo "<a href=$formwardurl?showroom=$showroom$link&showhist=none>hide</a>";}
	      	echo "</font></td></tr>\r</table></td></tr>";
	if (isset ($showhist)) {foreach($tailoutput as $data) echo "\r<tr><td  colspan=1>History</td><td colspan=2>$data</td></tr>";};
	

	};
	echo "\r</td></tr>\r</table></td></tr>\r</table></font>\r</table></body></html>";

?>

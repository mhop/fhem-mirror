<?php
	
	
	
################# Creates graphics vor pgm3


################

include "../config.php";
include "functions.php";


$drawhms=$_GET['drawhms'];
$room=$_GET['room'];
$type=$_GET['type'];
$battery=$_GET['battery'];
$supported_HMS= array('HMS100T','HMS100TF','HMS100WD','HMS100MG','HMS100TFK','HMS100W','RM100-2','HMS100CO','CUL_WS');

	
#Supported Device. Use UserDefs if you have other devices
if (! in_array($type,$supported_HMS)) show_error_type($imgmaxxhms,$imgmaxyhms,$type);



if ($DBUse=="1") {                                                              
                $sqlquery=mysql_query("select timestamp from history where device='".$drawhms."' and (reading='data' or reading like '% Detect') order by timestamp desc limit 1");     
	$query=mysql_fetch_object($sqlquery);
                $date=str_replace(" ","_",$query->timestamp);                   
        }                                                                       
        else {


	$file="$logpath/$drawhms.log"; 
        if (! file_exists($file)) show_error($file,$drawhms,$imgmaxxhms,$imgmaxyhms,$type);

	## do we really need a new graphic??
	$execorder=$tailpath.' -1 '.$file;
	exec($execorder,$tail1);
 	$parts = explode(" ", $tail1[0]);
	$date=$parts[0];

} #DBUse
	

	$savefile=$AbsolutPath."/tmp/HMS.".$drawhms.".log.".$date.".png";

	if (file_exists($savefile)) {

		$im2 = @ImageCreateFromPNG($savefile);
		header("Content-type: image/png");
		imagePng($im2);
		exit; # ;-))) we do not need a new graphic
	}
	else #delete old pngs
	{
		$delfile=$AbsolutPath."/tmp/HMS.".$drawhms.".log.*.png";
		foreach (glob($delfile) as $filename) {
   		unlink($filename);
		}
	}



	
	$_SESSION["arraydata"] = array();
	
	$im = ImageCreateTrueColor($imgmaxxhms,$imgmaxyhms);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg1p = ImageColorAllocate($im, $bg1_R,$bg1_G,$bg1_B);
	$bg2p = ImageColorAllocate($im, $buttonBg_R,$buttonBg_G,$buttonBg_B);
	$bg3p = ImageColorAllocate($im, $fontcol_grap_R,$fontcol_grap_G,$fontcol_grap_B);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$gray= ImageColorAllocate($im, 133, 133, 133);
	$red = ImageColorAllocate($im, 255, 0, 0);
	$green = ImageColorAllocate($im, 0, 255, 0);
	$yellow= ImageColorAllocate($im, 255, 255, 0);
	$orange= ImageColorAllocate($im, 255, 230, 25);


	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxhms-1, $imgmaxyhms-1, $white);


if ($DBUse=="1")
        { 
        $array=array();
        $sqlarray=mysql_query("select timestamp,event from history where device='".$drawhms."' and (reading='data' or reading like '% Detect') order by timestamp desc limit ".$logrotateHMSlines."") or die (mysql_error());
        while ( $row=mysql_fetch_object($sqlarray))
                { 
                $date=str_replace(" ","_",$row->timestamp);
                array_push($array,$date.' '.$drawhms.' '.$row->event);
                } 
        $array=array_reverse($array); 
        }
        else $array = file($file);


	$oldmin=0; //only the data from every 10min
	$oldhour=0; //only the data from every 10min
	$mintemp=100;
	$maxtemp=-100;
	$counter=count($array);
	#if ($maxcountHMS <  $counter)  {$counter=$maxcountHMS;};
	
	#Logrotate
	if ((($logrotateHMSlines+100) < $counter) and ($logrotate == 'yes') and ($DBUse!="1")) LogRotate($array,$file,$logrotateHMSlines);

#print_r($array[1]);  
#print_r($array[1][12]);  exit;
###########################################################################

if ( $type == "HMS100T" or $type == "HMS100TF" or $type == "CUL_WS")  ## hms100t-Device.  
{
	
   	for ($x = 0; $x < $counter; $x++)
	{
		list ($date,$hms,$t,$temp,$h,$hum) = preg_split("/[\s,]+/", $array[$x]);
		if  ((($array[$x][14] != $oldmin) or ($array[$x][12] != $oldhour)  or ($x==$counter-1))
				and ( $date !="NEWLOGS"))
		{
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $_SESSION["arraydata"],array($date,$temp,$hum));
		}
     	}

	$resultreverse = array_reverse($_SESSION["arraydata"]);
	$xold=$imgmaxxhms;
	
	if ( $imgmaxxhms > count ($resultreverse) )
	{ $_SESSION["maxdata"] = count ($resultreverse); }
	else
	{ $_SESSION["maxdata"] = $imgmaxxhms; };

	###################
        ### min/max
      	$mintemp=100;
      	$maxtemp=-100;
      	for ($x = 0; $x <= $_SESSION["maxdata"]; $x++)
      	{
              if ( $resultreverse[$x][1] > $maxtemp ) $maxtemp=$resultreverse[$x][1];
              if ( ($resultreverse[$x][1] < $mintemp) and ($resultreverse[$x][1]>-100) ) $mintemp=$resultreverse[$x][1];
      	}
      	$tempdiff=$maxtemp-$mintemp;
      	if ($tempdiff==0) $tempdiff=1;
      	$fac=$imgmaxyhms/$tempdiff;
	$yold=round($imgmaxyhms-(($resultreverse[0][1]-$mintemp)*$fac));
	 ###################
	

	if ($maxcountHMS <   $_SESSION["maxdata"])  {$anzlines=$maxcountHMS;} else {$anzlines= $_SESSION["maxdata"];}
	for ($x = 0; $x < $anzlines; $x++)

        {
 		$parts = explode("_", $resultreverse[$x][0]);
		if ( ($parts[0] != $olddate) )
		{
			$olddate=$parts[0];
			ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $bg1p);
		}
		$y = round($imgmaxyhms-(($resultreverse[$x][1]-$mintemp)*$fac));
		ImageLine($im, $imgmaxxhms-$x, $y, $xold, $yold, $red);
		$xold=$imgmaxxhms-$x;
		$yold=$y;
	};
	ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $yellow);
	ImageLine($im, $imgmaxxhms-$maxcountHMS, 0,$imgmaxxhms-$maxcountHMS , $imgmaxyhms, $white);
	$tempTEMP=$temp;
}; #HMS100T


if (( $type == "HMS100TF") or ( $type == "CUL_WS"))  ## hms100tf-Device.  
{
#Humidity...

	#$oldmin=0; //only the data from every 10min
	$min=100;
	$max=-100;

	if ($maxcountHMS <   $_SESSION["maxdata"])  {$anzlines=$maxcountHMS;} else {$anzlines= $_SESSION["maxdata"];}
	for ($x = 0; $x < $anzlines; $x++)
        {
	$temp=$resultreverse[$x][2];
	if ( $temp > $max ) $max=$temp;
	if ( $temp < $min ) $min=$temp;
	}
	$temp=$resultreverse[0][2];
	$tempdiff=$max-$min;
	$fac=$imgmaxyhms/$tempdiff;


	$xold=$imgmaxxhms;
	$yold=round($imgmaxyhms-(($resultreverse[0][2]-$min)*$fac));

	if ($maxcountHMS <   $_SESSION["maxdata"])  {$anzlines=$maxcountHMS;} else {$anzlines= $_SESSION["maxdata"];}
	for ($x = 0; $x < $anzlines; $x++)
	#for ($x = 0; $x < count($resultreverse); $x++)
        {
		$y = round($imgmaxyhms-(($resultreverse[$x][2]-$min)*$fac));
		ImageLine($im, $imgmaxxhms-$x, $y, $xold, $yold, $white);
		$xold=$imgmaxxhms-$x;
		$yold=$y;
	};
        
	$text="Humidity";
	$fontsize=7;
        $txtcolor=$white; 
        ImageTTFText ($im, $fontsize, 0, 5, 23, $txtcolor, $fontttf, $text);
	$txtcolor=$white;
	
	$fontsize=9;
	$text=$temp." %";
	$hvalue=$temp;
        ImageTTFText ($im, $fontsize, 0, 210, 35, $txtcolor, $fontttfb, $text);

        $txtcolor=$white; 
	$fontsize=7;
	$text="min= $min max= $max";
        ImageTTFText ($im,  $fontsize, 0, 182, 47, $txtcolor, $fontttf, $text);


};



#############################################################################
if ( $type == "HMS100T" or $type == "HMS100TF"  or $type == "CUL_WS")
{

	$text="Temperature";
	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
        $txtcolor=$bg3p; 
	$fontsize=9;
	$text=$tempTEMP." &#176;C";
	$tvalue=$tempTEMP;
        ImageTTFText ($im, $fontsize, 0, 90-$XcorrectMainTextHMS, 37, $txtcolor, $fontttfb, $text);

        $txtcolor=$bg3p; 
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im,  $fontsize, 0, 67-$XcorrectMainTextHMS, 49, $txtcolor, $fontttf, $text);
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxhms-127,  13, $txtcolor, $fontttf, $text);
};
#############################################################################
## dew point
if ( $type == "HMS100TF" and $showdewpoint=='yes' )
{
	$dp  = sprintf("%3.1f", dewpoint($tvalue,$hvalue));
	$fontsize=9;
	$text=$dp." &#176;C";
        ImageTTFText ($im, $fontsize, 0, 350, 35, $bg1p, $fontttfb, $text);
        $txtcolor=$orange; 
	$fontsize=7;
	$text="Dewpoint";
        ImageTTFText ($im,  $fontsize, 0, 350, 47, $bg1p, $fontttf, $text);
}

#############################################################################
## general
        $txtcolor=$bg3p; 
	$fontsize=9;
	$text= $drawhms;
        ImageTTFText ($im, 8, 0,90-$XcorrectMainTextHMS, 22, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text='Bat: '.$battery;
	if ($type=="CUL_WS") $text="";
	if ($battery == 'empty') {$txtcolor=$red; $text='Bat: low';};
        ImageTTFText ($im,  $fontsize, 0, 105, 10, $txtcolor, $fontttf, $text);
	$fontsize=7;
        $txtcolor=$bg3p; 

	$text=$txtroom.$room;
        ImageTTFText ($im,  $fontsize, 0, 3,  $imgmaxyhms-7, $txtcolor, $fontttf, $text);
	$text=$type;
        ImageTTFText ($im,  $fontsize, 0, 5,  $imgmaxyhms-17, $txtcolor, $fontttf, $text);


#############################################################################
if ( $type == "HMS100WD" or $type == "HMS100MG" or $type == "HMS100W" 
	or $type == "HMS100TFK" or $type=="RM100-2" or $type=="HMS100CO")
{
  for ($x = 0; $x < $counter; $x++)
        {
               if ( $type=="RM100-2" ) 

		{list ($date,$hms,$detect,$onoff) = preg_split("/[\s,]+/", $array[$x]);}
	       else
                {list ($date,$hms,$kind,$detect,$onoff) = preg_split("/[\s,]+/", $array[$x]);};
                if  ($x!=$counter-1 and  $date !="NEWLOGS")
                {
                        array_push( $_SESSION["arraydata"],array($date,$onoff));
                }
        }

        $resultreverse = array_reverse($_SESSION["arraydata"]);
        $xold=$imgmaxxhms;

        if ( $imgmaxxhms > count ($resultreverse) )
        { $_SESSION["maxdata"] = count ($resultreverse); }
        else
        { $_SESSION["maxdata"] = $imgmaxxhms; };

	if ($maxcountHMS <   $_SESSION["maxdata"])  {$anzlines=$maxcountHMS;} else {$anzlines= $_SESSION["maxdata"];}
	for ($x = 0; $x < $anzlines; $x++)
        {
                $parts = explode("_", $resultreverse[$x][0]);
                if ( ($parts[0] != $olddate) )
                {
                        $olddate=$parts[0];
                        ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $bg1p);
                }
                $y = round($imgmaxyhms/2);
	 	$isonoff=rtrim($resultreverse[$x][1]);
       	 	if ( $isonoff == "off" )
                { ImageLine($im, $imgmaxxhms-$x, $y, $imgmaxxhms-$x,$y, $white);}
                else
                { ImageLine($im, $imgmaxxhms-$x, $y-1, $imgmaxxhms-$x,$y+1, $red);
		};

                $xold=$imgmaxxhms-$x;
                $yold=$y;
        };
        ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $yellow);
       
	 if ($type=='HMS100WD' or $type=='HMS100W'){$text="Water detected:";}
	elseif ($type=='HMS100MG'){$text="Gas detected:";}
 	elseif ($type=='HMS100CO'){$text="CO detected:";}
	elseif ($type=='RM100-2'){$text="Smoke detected:";}
	else {$text="Switch open:";}
 	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 180, 18, $txtcolor, $fontttf, $text);

        if ($isonoff == "off" )
        {ImageTTFText ($im, 9, 0, 265, 18, $white, $fontttf,'no');}
        else
        {ImageTTFText ($im, 9, 0, 265, 18, $red, $fontttfb,'YES');}

        $txtcolor=$bg3p; 
	$fontsize=7;
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxhms-127,  13, $txtcolor, $fontttf, $text);

};

#ok. let's draw
	
	imagePng($im,$savefile);
	header("Content-type: image/png");
	imagePng($im);



###############################################################
## first start: shows the required logfiles
function show_error($file,$drawhms,$imgmaxx,$imgmaxy,$type)
{
	$im = ImageCreateTrueColor($imgmaxx,$imgmaxy);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg2p = ImageColorAllocate($im, 175,198,219);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$red = ImageColorAllocate($im, 255, 0, 0);

	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxx-1, $imgmaxy-1, $white);

	include "../config.php";
	$bg3p = ImageColorAllocate($im, $fontcol_grap_R,$fontcol_grap_G,$fontcol_grap_B);
 	$text="There is a new supported $type-Device but no Logfile $file";
        $fontsize=9;
        $txtcolor=$bg3p;
        ImageTTFText ($im, $fontsize, 0, 5, 17, $txtcolor, $fontttf, $text);
 	$text="Please add the following to your fhem.cfg and restart fhem.pl:";
        $fontsize=7;
        ImageTTFText ($im, $fontsize, 0, 5, 30, $txtcolor, $fontttf, $text);
	$logname=$drawhms."log";
        $fontsize=9;
	if ($type=='HMS100WD')
	{
		$text="define $logname FileLog $file $drawhms:.*Water.*";
	}
	elseif ($type=='RM100-2')
	{
		$text="define $logname FileLog $file $drawhms:.*smoke*";
	}
	elseif ($type=='HMS100W')
	{
		$text="define $logname FileLog $file $drawhms:.*Water.*";
	}
	elseif ($type=='HMS100MG')
	{
		$text="define $logname FileLog $file $drawhms:.*Gas.*";
	}
	elseif ($type=='HMS100CO')
        {
                $text="define $logname FileLog $file $drawhms:.*CO.*";
        }
	elseif ($type=='HMS100TFK')
	{
		$text="define $logname FileLog $file $drawhms:.*Switch.*";
	}
	else
	{
		$text="define $logname FileLog $file $drawhms:.*T:.*";
	}
        ImageTTFText ($im, $fontsize, 0, 5, 45, $txtcolor, $fontttf, $text);

	imagePng($im,$savefile);
	header("Content-type: image/png");
	imagePng($im);
	exit;
}

###############################################################
## supported HMS??
function show_error_type($imgmaxx,$imgmaxy,$type)
{
	$im = ImageCreateTrueColor($imgmaxx,$imgmaxy);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg2p = ImageColorAllocate($im, 175,198,219);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$red = ImageColorAllocate($im, 255, 0, 0);
	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxx-1, $imgmaxy-1, $white);

	include "../config.php";
	$bg3p = ImageColorAllocate($im, $fontcol_grap_R,$fontcol_grap_G,$fontcol_grap_B);
 	$text="HMS-Device $type is not supported";
	if ($type=="HMS_LIST") $text="Waiting for the first message from the HMS-Device...";
        $fontsize=7;
        $txtcolor=$bg3p;
        ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);

	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxx-1, $imgmaxy-1, $white);
	
	imagePng($im,$savefile);
	header("Content-type: image/png");
	imagePng($im);
	exit;
}

?>

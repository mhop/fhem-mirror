<?php
	
	
	
################# Creates graphics vor pgm3


################

include "../config.php";
include "functions.php";

setlocale (LC_ALL, 'de_DE.utf8');

	
	$drawfht=$_GET['drawfht'];
	$room=$_GET['room'];

	$file="$logpath/$drawfht.log";

        if (! file_exists($file)) show_error($file,$drawfht,$imgmaxxfht,$imgmaxyfht);



 ## do we really need a new graphic??
        $execorder=$tailpath.' -1 '.$file;
        exec($execorder,$tail1);
        $parts = explode(" ", $tail1[0]);
        $date=$parts[0];

	#if the expected graphic already exist then do not redraw the picture

	$savefile=$AbsolutPath."/tmp/FHT.".$drawfht.".log.".$parts[0].".png";
	if (file_exists($savefile)) {

		$im2 = @ImageCreateFromPNG($savefile);
		header("Content-type: image/png");
		imagePng($im2);
		exit; # ;-)))
	}
	else #delete old pngs
	{
		$delfile=$AbsolutPath."/tmp/FHT.".$drawfht.".log.*.png";
		foreach (glob($delfile) as $filename) {
   		unlink($filename);
		}
	}


	
	$_SESSION["arraydata"] = array();
	

  	$array = file($file); 
	$oldmin=0; //only the data from every 10min
	$oldhour=0; //only the data from every 10min
	$actuator="00%";
	$actuator_date="unknown";
	$counter=count($array);


	$arraydesired=array();
	$arrayactuator=array();

	
	#Logrotate
	if ((($logrotateFHTlines+200) < $counter) and ($logrotate == 'yes')) LogRotate($array,$file,$logrotateFHTlines);

   	for ($x = 0; $x < $counter; $x++)
	{
		$parts = explode(" ", $array[$x]);
		$date=$parts[0];
		$type=$parts[2];
		$temp=$parts[3];
		if ($type=="desired-temp:") 
			{$desired_temp=$temp;$desired_date=$date;}
		if ($type=="actuator:") 
			{$actuator=rtrim($temp);$actuator_date=$date;}
		if  ((($array[$x][14] != $oldmin) or ($array[$x][12] != $oldhour)) and ($type=="measured-temp:"))
		{
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $_SESSION["arraydata"],array($date,$type,$temp));
			array_push( $arraydesired,$desired_temp);
			array_push( $arrayactuator,$actuator);

		}
     	}


	$resultreverse = array_reverse($_SESSION["arraydata"]);


	$im = ImageCreateTrueColor($imgmaxxfht,$imgmaxyfht);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg1p = ImageColorAllocate($im, 110,148,183);
	$bg2p = ImageColorAllocate($im, 175,198,219);
	$bg3p = ImageColorAllocate($im, $fontcol_grap_R,$fontcol_grap_G,$fontcol_grap_B);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$gray= ImageColorAllocate($im, 133, 133, 133);
	#$lightgray= ImageColorAllocate($im, 200, 198, 222);
	$red = ImageColorAllocate($im, 255, 0, 0);
	$green = ImageColorAllocate($im, 0, 255, 0);
	$yellow= ImageColorAllocate($im, 255, 255, 0);
	$lightyellow= ImageColorAllocate($im, 255, 247,222 );
	$orange= ImageColorAllocate($im, 255, 230, 25);
	$actuatorcolor =  ImageColorAllocate($im, $actR, $actG, $actB);
	$desiredcolor =  ImageColorAllocate($im, $desR, $desG, $desB);


	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxfht-1, $imgmaxyfht-1, $white);

	
	$reversedesired = array_reverse($arraydesired);
	$reverseactuator = array_reverse($arrayactuator);
	$xold=$imgmaxxfht;
	
	if ( $imgmaxxfht > count ($resultreverse) )
	{ $_SESSION["maxdata"] = count ($resultreverse); }
	else
	{ $_SESSION["maxdata"] = $imgmaxxfht+1; };


	###################
	### min/max
	$mintemp=100;
	$maxtemp=-100;
	for ($x = 0; $x < $_SESSION["maxdata"]; $x++)
	{
		if ( $resultreverse[$x][2] > $maxtemp ) $maxtemp=$resultreverse[$x][2];
		if ( ($resultreverse[$x][2] < $mintemp) and ($resultreverse[$x][2]>-100) ) $mintemp=$resultreverse[$x][2];
	}
	$tempdiff=$maxtemp-$mintemp;
	if ($tempdiff==0) $tempdiff=1;
	$fac=$imgmaxyfht/$tempdiff;
	$fac2=$imgmaxyfht/100;
	$yold=round($imgmaxyfht-(($resultreverse[0][1]-$mintemp)*$fac));
	###################



	if ($maxcount > $_SESSION["maxdata"]) {$counter=$_SESSION["maxdata"];} else {$counter=$maxcount;};
	for ($x = 0; $x < $counter; $x++)

        {
 	$parts = explode("_", $resultreverse[$x][0]);
	if ( ($parts[0] != $olddate) )
	{
		$olddate=$parts[0];
		ImageLine($im, $imgmaxxfht-$x, 0,$imgmaxxfht-$x , $imgmaxyfht, $bg1p);
	};
	$y = round($imgmaxyfht-(($resultreverse[$x][2]-$mintemp)*$fac));
	$y2 = round($imgmaxyfht-(($reversedesired[$x]-$mintemp)*$fac));
	$y3 = round($imgmaxyfht-(($reverseactuator[$x])*$fac2));
	if ($show_actuator== 1) ImageLine($im, $imgmaxxfht-$x+1, $y3, $xold, $yold3, $actuatorcolor);
	if ($show_desiredtemp == 1) ImageLine($im, $imgmaxxfht-$x+1, $y2, $xold, $yold2, $desiredcolor);
	ImageLine($im, $imgmaxxfht-$x, $y, $xold, $yold, $red);
	$xold=$imgmaxxfht-$x;
	$yold=$y;
	$yold2=$y2;
	$yold3=$y3;
	};
	
	#print_r($resultreverse);
	#print_r($reversedesired);
	#exit;
	ImageLine($im, $imgmaxxfht-$x, 0,$imgmaxxfht-$x , $imgmaxyfht, $yellow);
	ImageLine($im, $imgmaxxfht-$maxcount, 0,$imgmaxxfht-$maxcount , $imgmaxyfht, $white);
###ttf
	
#	$text2=$resultreverse[0][0];
	$text="Temperature";
	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
	$text=$resultreverse[0][2]." &#176;C";

        ImageTTFText ($im, 9, 0, 90-$XcorrectMainText, 37, $txtcolor, $fontttfb, $text);
        
	$text= $drawfht;
        ImageTTFText ($im, 8, 0, 90-$XcorrectMainText, 22, $txtcolor, $fontttfb, $text);
        $txtcolor=$bg3p; 
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im,  $fontsize, 0, 67-$XcorrectMainText, 49, $txtcolor, $fontttf, $text);
        
	$text=$txtroom.$room;
        ImageTTFText ($im,  $fontsize, 0, 3,  49, $txtcolor, $fontttf, $text);
        
	 $text="desired: $desired_temp";

         ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-230-$XcorrectDate, 23, $txtcolor, $fontttf, $text);
       
	# Time of desired-temp
	 $text=substr($desired_date,11,5);
      	 ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-160-$XcorrectDate, 23, $txtcolor, $fontttf, $text);




 
	$text="Actuator: $actuator";
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-230-$XcorrectDate, 33, $txtcolor, $fontttf, $text);
        	
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-127, 13, $txtcolor, $fontttf, $text);

	imagePng($im,$savefile);
	header("Content-type: image/png");
	imagePng($im);



function show_error($file,$drawfht,$imgmaxxfht,$imgmaxyfht)
{
	$im = ImageCreateTrueColor($imgmaxxfht,$imgmaxyfht);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg2p = ImageColorAllocate($im, 175,198,219);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$red = ImageColorAllocate($im, 255, 0, 0);

	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxfht-1, $imgmaxyfht-1, $white);
	imagestring($im, 3, 5, 5, "Error, there is no $file", $black);
	imagestring($im, 1, 3, 25, "Please add the following to your fhz1000.cfg", $black);
	$logname=$drawfht."log";
	imagestring($im, 1, 3, 35, "define $logname FileLog $file $drawfht:.*(temp|actuator|desired).*", $black);
	header("Content-type: image/png");
	imagePng($im);
	exit;
}



?>

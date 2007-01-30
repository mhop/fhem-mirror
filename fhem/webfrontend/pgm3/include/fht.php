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
	
	$_SESSION["arraydata"] = array();
	
	$im = ImageCreateTrueColor($imgmaxxfht,$imgmaxyfht);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg1p = ImageColorAllocate($im, 110,148,183);
	$bg2p = ImageColorAllocate($im, 175,198,219);
	$bg3p = ImageColorAllocate($im, $fontcol_grap_R,$fontcol_grap_G,$fontcol_grap_B);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$gray= ImageColorAllocate($im, 133, 133, 133);
	$red = ImageColorAllocate($im, 255, 0, 0);
	$green = ImageColorAllocate($im, 0, 255, 0);
	$yellow= ImageColorAllocate($im, 255, 255, 0);
	$orange= ImageColorAllocate($im, 255, 230, 25);


	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxfht-1, $imgmaxyfht-1, $white);

  	$array = file($file); 
	$oldmin=0; //only the data from every 10min
	$oldhour=0; //only the data from every 10min
	$actuator=0;
	$actuator_date="unknown";
	$counter=count($array);

	#echo $counter; exit;
	
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
		}
     	}

	$resultreverse = array_reverse($_SESSION["arraydata"]);
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
	$yold=round($imgmaxyfht-(($resultreverse[0][1]-$mintemp)*$fac));
	###################


	
	for ($x = 0; $x < $_SESSION["maxdata"]; $x++)

        {
 	$parts = explode("_", $resultreverse[$x][0]);
	if ( ($parts[0] != $olddate) )
	{
		$olddate=$parts[0];
		ImageLine($im, $imgmaxxfht-$x, 0,$imgmaxxfht-$x , $imgmaxyfht, $bg1p);
	};
	$y = round($imgmaxyfht-(($resultreverse[$x][2]-$mintemp)*$fac));
	ImageLine($im, $imgmaxxfht-$x, $y, $xold, $yold, $red);
	$xold=$imgmaxxfht-$x;
	$yold=$y;
	};
	
	#print_r($resultreverse);
	#exit;
	ImageLine($im, $imgmaxxfht-$x, 0,$imgmaxxfht-$x , $imgmaxyfht, $yellow);
###ttf
	$text="Temperature";
	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
	#setlocale (LC_ALL, 'de_DE.UTF-8');
	$text=$resultreverse[0][2]." &#176;C";
        ImageTTFText ($im, 9, 0, 90, 35, $txtcolor, $fontttfb, $text);
        
	$text= $drawfht;
        ImageTTFText ($im, 8, 0, 90, 18, $txtcolor, $fontttfb, $text);
        $txtcolor=$bg3p; 
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im,  $fontsize, 0, 67, 47, $txtcolor, $fontttf, $text);
        
	$text=$txtroom.$room;
        ImageTTFText ($im,  $fontsize, 0, 5,  $imgmaxyfht-7, $txtcolor, $fontttf, $text);
        
	$text="desired-temp: $desired_temp";
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-230, 23, $txtcolor, $fontttf, $text);
        
	$text=$desired_date;
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-127, 23, $txtcolor, $fontttf, $text);
        
	$text="Actuator [%]: $actuator";
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-230, 33, $txtcolor, $fontttf, $text);
        	
	$text=$actuator_date;
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-127, 33, $txtcolor, $fontttf, $text);
        
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxfht-127, 13, $txtcolor, $fontttf, $text);

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

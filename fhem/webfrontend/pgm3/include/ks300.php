<?php
	
	
	
################# Creates graphics vor pgm3


################
include "../config.php";  #make your settings there
include "functions.php";  

$drawks=$_GET['drawks'];
$room=$_GET['room'];
$avgday=$_GET['avgday'];
$avgmonth=$_GET['avgmonth'];


        $file="$logpath/$drawks.log";
        if (! file_exists($file)) show_error($file,$drawks,$imgmaxxks,$imgmaxyks);
	
	$arraydata = array();
	
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
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






#temperature
		ImageFill($im, 0, 0, $bg2p);
		ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

		$array = file($file); 
		$oldmin=0; //only the data from every 10min
		$oldhour=0; //only the data from every 10min
		$mintemp=100;
		$maxtemp=-100;
		$counter=count($array);
	
#Logrotate
	if ((($logrotateKS300lines+200) < $counter) and ($logrotate == 'yes')) LogRotate($array,$file,$logrotateKS300lines);

# go	
	for ($x = 0; $x < $counter; $x++)
		{
			list ($date,$ks300,$t,$temp,$h,$hum,$w,$wind,$r,$rain,$ir,$israin) = preg_split("/[\s,]+/", $array[$x]);
		if  (
				(($array[$x][14] != $oldmin) 
				or ($array[$x][12] != $oldhour) 
				or ($x==$counter-1))
				and ($date!="NEWLOGS"))
			{
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $arraydata,array($date,$temp,$hum,$wind,$rain,$israin));

			}
		}

		$resultreverse = array_reverse($arraydata);
		$xold=$imgmaxxks;
		
		if ( $imgmaxxks > count ($resultreverse) )
		{ $maxdata = count ($resultreverse); }
		else
		{ $maxdata = $imgmaxxks; };
		
	
	        ###################
        	### min/max
	        $mintemp=100;
	        $maxtemp=-100;
	        for ($x = 0; $x <= $maxdata; $x++)
	        {
	                if ( $resultreverse[$x][1] > $maxtemp ) $maxtemp=$resultreverse[$x][1];
	                if ( ($resultreverse[$x][1] < $mintemp) and ($resultreverse[$x][1]>-100) ) $mintemp=$resultreverse[$x][1];
	        }
	        $tempdiff=$maxtemp-$mintemp;
	        if ($tempdiff==0) $tempdiff=1;
	        $fac=$imgmaxyks/$tempdiff;
		$yold=round($imgmaxyks-(($resultreverse[0][1]-$mintemp)*$fac));
	        ###################
	
		
		for ($x = 0; $x <= $maxdata; $x++)
		{
		$y = round($imgmaxyks-(($resultreverse[$x][1]-$mintemp)*$fac));
		ImageLine($im, $imgmaxxks-$x, $y, $xold, $yold, $red);
		$xold=$imgmaxxks-$x;
		$yold=$y;
 		$parts = explode("_", $resultreverse[$x][0]);
		if ( ($parts[0] != $olddate) )
		{
			$olddate=$parts[0];
			ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $bg1p);
		};
		};
		ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $yellow);
		if ($mintemp < 0) 
		{
			$y = round($imgmaxyks-((0-$mintemp)*$fac));
			ImageLine($im, $imgmaxxks, $y,0 , $y, $bg1p);
		}
		$text="Temperature";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp." &#176;C";
        ImageTTFText ($im, $fontsize, 0, 80, 35, $txtcolor, $fontttfb, $text);
	$text= $drawks;
        ImageTTFText ($im, 8, 0, 80, 18, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im, $fontsize, 0, 60, 47, $txtcolor, $fontttf, $text);
		$imt=$im;

#humidity
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);



	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=100;
	$max=-100;

	for ($x = 0; $x <= $maxdata-1; $x++)
        {
	$temp=$resultreverse[$x][2];
	if ( $temp > $max ) $max=$temp;
	if ( ($temp < $min) and ($temp != '')) $min=$temp;
	}
	$temp=$resultreverse[0][2];
	$tempdiff=$max-$min;
	if ($tempdiff==0) $tempdiff=1;
	$fac=$imgmaxyks/$tempdiff;


	$xold=$imgmaxxks;
	$yold=round($imgmaxyks-(($resultreverse[0][2]-$min)*$fac));

	$olddate = ($resultreverse[0][0][9]);
	for ($x = 0; $x < count($resultreverse); $x++)
        {
	$y = round($imgmaxyks-(($resultreverse[$x][2]-$min)*$fac));
	ImageLine($im, $imgmaxxks-$x, $y, $xold, $yold, $red);
	$xold=$imgmaxxks-$x;
	$yold=$y;
 	$parts = explode("_", $resultreverse[$x][0]);
	if ( ($parts[0] != $olddate) )
	{
		$olddate=$parts[0];
		ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $bg1p);
	};
	};
	ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $yellow);
		$text="Humidity";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp." %";
        ImageTTFText ($im, $fontsize, 0, 80, 35, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text="min= $min max= $max";
        ImageTTFText ($im, $fontsize, 0, 60, 47, $txtcolor, $fontttf, $text);

	$imh=$im;

#wind
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=120;
	$max=-100;

	for ($x = 0; $x <= $maxdata; $x++)
        {
	$temp=$resultreverse[$x][3];
	if ( $temp > $max ) $max=$temp;
	if ( $temp < $min and ($temp != '')) $min=$temp;
	}
	$temp=$resultreverse[0][3];
	$tempdiff=$max-$min;
	if ($tempdiff==0) $tempdiff=1;
	$fac=$imgmaxyks/$tempdiff;


	$xold=$imgmaxxks;
	$yold=round($imgmaxyks-(($resultreverse[0][3]-$min)*$fac));

	for ($x = 0; $x < count($resultreverse); $x++)
        {
	$y = round($imgmaxyks-(($resultreverse[$x][3]-$min)*$fac));
	ImageLine($im, $imgmaxxks-$x, $y, $xold, $yold, $red);
	$xold=$imgmaxxks-$x;
	$yold=$y;
 	$parts = explode("_", $resultreverse[$x][0]);
	if ( ($parts[0] != $olddate) )
	{
		$olddate=$parts[0];
		ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $bg1p);
	};
	};
	ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $yellow);
		$text="Wind";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp." km/h";
        ImageTTFText ($im, $fontsize, 0, 80, 35, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	
	if ($showbft==1)
	{
	$text="( ".bft($temp)."  Bft)";
        ImageTTFText ($im, $fontsize, 0, 150, 35, $txtcolor, $fontttfb, $text);
        $text2="min= $min  max= $max (".bft($max)." Bft)";
	}
	else
	{
	$text2="min= $min max= $max";
	}
        ImageTTFText ($im, $fontsize, 0, 60, 47, $txtcolor, $fontttf, $text2);

	$imw=$im;

#rain
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=120;
	$max=-100;

	for ($x = 0; $x <= $maxdata; $x++)
        {
	$temp=$resultreverse[$x][4];
	if ( $temp > $max ) $max=$temp;
	if ( $temp < $min and ($temp != '')) $min=$temp;
	}
	$temp=$resultreverse[0][4];
	$israin=rtrim($resultreverse[0][5]);
	$tempdiff=$max-$min;
	if ( $temdiff == 0 ) $tempdiff=1;
	$fac=$imgmaxyks/$tempdiff;


	$xold=$imgmaxxks;
	$yold=round($imgmaxyks-(($resultreverse[0][4]-$min)*$fac));

	for ($x = 0; $x <= $maxdata; $x++)
        {
 	$parts = explode("_", $resultreverse[$x][0]);
	if ( ($parts[0] != $olddate) )
	{
		$olddate=$parts[0];
		ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $bg1p);
	};
	$y = round($imgmaxyks-(($resultreverse[$x][4]-$min)*$fac));
	ImageLine($im, $imgmaxxks-$x, $y, $xold, $yold, $red);
	$israin2=rtrim($resultreverse[$x][5]);
	if ( $israin2 == "no" ) 
		{ ImageLine($im, $imgmaxxks-$x, 18, $imgmaxxks-$x,18, $white);}
		else
		{ ImageLine($im, $imgmaxxks-$x, 17, $imgmaxxks-$x,19, $red);};

	$xold=$imgmaxxks-$x;
	$yold=$y;
	
	};
	ImageLine($im, $imgmaxxks-$x, 0,$imgmaxxks-$x , $imgmaxyks, $yellow);
	$fontsize=7;
	$text="Is raining:";
        ImageTTFText ($im, $fontsize, 0, 50, 14, $txtcolor, $fontttf, $text);

	if ($israin == "no" )
		{ imagestring($im, 5, 110, 2, $israin, $white);}
		else
		{ imagestring($im, 5, 110, 2, $israin, $red);};
		$text="Rain";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp." l/m2";
        ImageTTFText ($im, $fontsize, 0, 80, 35, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text="min= $min max= $max";
        ImageTTFText ($im, $fontsize, 0,  $imgmaxxks-130, 30, $txtcolor, $fontttf, $text);
	$text=$resultreverse[0][0];
        ImageTTFText ($im, $fontsize, 0,  $imgmaxxks-130, 15, $txtcolor, $fontttf, $text);
	$text="avg_day: ".$avgday;
        ImageTTFText ($im, $fontsize, 0,  70, 47, $txtcolor, $fontttf, $text);
	$text="avg_mon: ".$avgmonth;
        ImageTTFText ($im, $fontsize, 0,  320, 47, $txtcolor, $fontttf, $text);
	$text=$room;
        ImageTTFText ($im, $fontsize, 0,  7, 47, $txtcolor, $fontttf, $text);
	$imr=$im;





# big picture
$imall = ImageCreateTrueColor($imgmaxxks,$imgmaxyks*4);
ImageFill($imall, 0, 0, $bg2p);
ImageCopy ($imall,$imt,0,0,0,0,$imgmaxxks,$imgmaxyks);
ImageCopy ($imall,$imh,0,$imgmaxyks,0,0,$imgmaxxks,$imgmaxyks);
ImageCopy ($imall,$imw,0,$imgmaxyks*2,0,0,$imgmaxxks,$imgmaxyks);
ImageCopy ($imall,$imr,0,$imgmaxyks*3,0,0,$imgmaxxks,$imgmaxyks);


header("Content-type: image/png");
imagePng($imall);








function show_error($file,$draw,$imgmaxx,$imgmaxy)
{
	$im = ImageCreateTrueColor($imgmaxx,$imgmaxy*4);
	$black = ImageColorAllocate($im, 0, 0, 0);
	$bg2p = ImageColorAllocate($im, 175,198,219);
	$white = ImageColorAllocate($im, 255, 255, 255);
	$red = ImageColorAllocate($im, 255, 0, 0);

	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxx-1, $imgmaxy-1, $white);
	imagestring($im, 3, 5, 5, "Error, there is no $file", $black);
	imagestring($im, 1, 3, 25, "Please add the following to your fhz1000.cfg", $black);
	$logname=$draw."log";
	imagestring($im, 1, 3, 35, "define $logname FileLog $file $draw:.*H:.*", $black);
	header("Content-type: image/png");
	imagePng($im);
	exit;
}

?>

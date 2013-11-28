<?php
	
	
	
################# Creates graphics vor pgm3


################
include "../config.php";  #make your settings there
include "functions.php";  

$drawks=$_GET['drawks'];
$room=$_GET['room'];
$avgday=$_GET['avgday'];
$avgmonth=$_GET['avgmonth'];


if ($DBUse=="1") {                                                      
                $sqlquery=mysql_query("select timestamp from history where device='".$drawks."'  order by timestamp desc limit 1");              
		$query=mysql_fetch_object($sqlquery);                           
                $date=str_replace(" ","_",$query->timestamp);                   
        }                                                                       
        else {    


        $file="$logpath/$drawks.log";
        if (! file_exists($file)) show_error($file,$drawks,$imgmaxxks,$imgmaxyks);
	
	## do we really need a new graphic??
	$execorder=$tailpath.' -1 '.$file;
	exec($execorder,$tail1);
 	$parts = explode(" ", $tail1[0]);
	$date=$parts[0];
} #dbuse
	

	#if the expected graphic already exist then do not redraw the picture 
	$savefile=$AbsolutPath."/tmp/KS.".$drawks.".log.".$date.".png";
	if (file_exists($savefile)) {

		$im2 = @ImageCreateFromPNG($savefile);
		header("Content-type: image/png");
		imagePng($im2);
		exit; # ;-)))
	}
	else #delete old pngs
	{
		#echo "not exist: $savefile"; exit;
		$delfile=$AbsolutPath."/tmp/KS.".$drawks.".log.*.png";
		foreach (glob($delfile) as $filename) {
   		unlink($filename);
		}
	}

	


	$arraydata = array();
	
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
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






#temperature
		ImageFill($im, 0, 0, $bg2p);
		ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	if ($DBUse=="1") 
	{
	$array=array();
	$sqlarray=mysql_query("select timestamp,event from history where device='".$drawks."' and reading='data' order by timestamp desc limit ".$logrotateKS300lines."") or die (mysql_error()); 
	while ( $row=mysql_fetch_object($sqlarray))
		{
		$date=str_replace(" ","_",$row->timestamp);
		array_push($array,$date.' '.$drawks.' '.$row->event);
		}
	$array=array_reverse($array);
	#print_r($array); #debug
	#exit;
	}

        else $array = file($file);  



		$oldmin=0; //only the data from every 10min
		$oldhour=0; //only the data from every 10min
		$mintemp=100;
		$maxtemp=-100;
		$counter=count($array);
	
#Logrotate
	if ((($logrotateKS300lines+200) < $counter) and ($logrotate == 'yes') and ($DBUse!="1")) LogRotate($array,$file,$logrotateKS300lines);

# go	
	for ($x = 0; $x < $counter; $x++)
		{
			list ($date,$ks300,$t,$temp,$h,$hum,$w,$wind,$r,$rain,$ir,$israin) = preg_split("/[\s,]+/", $array[$x]);
		if  (
				(($array[$x][14] != $oldmin) 
				or ($array[$x][12] != $oldhour) 
				or ($x==$counter-1))
				and ($t!="avg_day")
				and ($date!="NEWLOGS")
				and ($t=="T:")
		    )
			{
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $arraydata,array($date,$temp,$hum,$wind,$rain,$israin));
			}
		}
		#WS300 has Willi instead other things
		if ($r=="Willi:") {$willi=1;};

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
	
		if ($maxcountKS < $maxdata) {$anzlines=$maxcountKS;}	else {$anzlines=$maxdata;}
		for ($x = 0; $x < $anzlines; $x++)
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
		ImageLine($im, $imgmaxxks-$maxcountKS, 0,$imgmaxxks-$maxcountKS , $imgmaxyks, $white);
		if ($mintemp < 0) 
		{
			$y = round($imgmaxyks-((0-$mintemp)*$fac));
			#ImageLine($im, $imgmaxxks-$maxcountKS, $y,0 , $y, $bg1p);
			ImageLine($im, $imgmaxxks, $y,$imgmaxxks-$maxcountKS , $y, $bg1p);
		}
		$text="Temperature";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$temp=$resultreverse[0][1]; #Martin
	$text=$temp." &#176;C";
	$tvalue= $temp;
        ImageTTFText ($im, $fontsize, 0, 90-$XcorrectMainTextKS, 37, $txtcolor, $fontttfb, $text);
	$text= $drawks;
        ImageTTFText ($im, 8, 0,  90-$XcorrectMainTextKS, 22, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im, $fontsize, 0, 67-$XcorrectMainTextKS, 49, $txtcolor, $fontttf, $text);
		$imt=$im;

#humidity
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);



	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=100;
	$max=-100;

	if ($maxcountKS < $maxdata) {$anzlines=$maxcountKS;}	else {$anzlines=$maxdata;}
	for ($x = 0; $x < $anzlines; $x++)
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
	$countresultrev=count($resultreverse);
	if ($maxcountKS < $countresultrev) {$anzlines=$maxcountKS;}else {$anzlines=$countresultrev;}
	for ($x = 0; $x < $anzlines; $x++)
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
	ImageLine($im, $imgmaxxks-$maxcountKS, 0,$imgmaxxks-$maxcountKS , $imgmaxyks, $white);
		$text="Humidity";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp." %";
	$hvalue= $temp;
        ImageTTFText ($im, $fontsize, 0,  90-$XcorrectMainText, 37, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text="min= $min max= $max";
        ImageTTFText ($im, $fontsize, 0,  67-$XcorrectMainText, 49, $txtcolor, $fontttf, $text);

	$imh=$im;


	# dewpoint
	if ($showdewpointks300='yes')
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

#wind/Air Pressure
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=120000;
	$max=-100;

	if ($maxcountKS < $maxdata) {$anzlines=$maxcountKS;}	else {$anzlines=$maxdata;}
	for ($x = 0; $x < $anzlines; $x++)
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

	$countresultrev=count($resultreverse);
	if ($maxcountKS < $countresultrev) {$anzlines=$maxcountKS;}else {$anzlines=$countresultrev;}
	for ($x = 0; $x < $anzlines; $x++)
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
	ImageLine($im, $imgmaxxks-$maxcountKS, 0,$imgmaxxks-$maxcountKS , $imgmaxyks, $white);
		if (isset($willi)) $text="Air Pressure"; else $text="Wind";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
	$fontsize=9;
	if (isset($willi)) $text=$temp." hPa"; else $text=$temp." km/h";
        ImageTTFText ($im, $fontsize, 0, 80-$XcorrectMainTextKS, 37, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	
	if (($showbft==1) and (! isset($willi)))
	{
	$text="( ".bft($temp)."  Bft)";
        ImageTTFText ($im, $fontsize, 0, 140-$XcorrectMainTextKS, 37, $txtcolor, $fontttfb, $text);
        $text2="min= $min  max= $max (".bft($max)." Bft)";
	}
	else
	{
	$text2="min= $min max= $max";
	}
        ImageTTFText ($im, $fontsize, 0, 57-$XcorrectMainTextKS, 49, $txtcolor, $fontttf, $text2);

	$imw=$im;

#rain/willi

if (! isset($willi))
{
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=120;
	$max=-100;

	if ($maxcountKS < $maxdata) {$anzlines=$maxcountKS;}	else {$anzlines=$maxdata;}
	for ($x = 0; $x < $anzlines; $x++)
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

	if ($maxcountKS < $maxdata) {$anzlines=$maxcountKS;}	else {$anzlines=$maxdata;}
	for ($x = 0; $x < $anzlines; $x++)
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
	ImageLine($im, $imgmaxxks-$maxcountKS, 0,$imgmaxxks-$maxcountKS , $imgmaxyks, $white);
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
        	ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp." l/m2";
        ImageTTFText ($im, $fontsize, 0, 90-$XcorrectMainTextKS, 37, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text="min= $min max= $max";
        ImageTTFText ($im, $fontsize, 0,  $imgmaxxks-130, 30, $txtcolor, $fontttf, $text);
	$text=$resultreverse[0][0];
        ImageTTFText ($im, $fontsize, 0,  $imgmaxxks-130, 15, $txtcolor, $fontttf, $text);
	$text="avg_day: ".$avgday;
        ImageTTFText ($im, $fontsize, 0,  70, 49, $txtcolor, $fontttf, $text);
	$text="avg_mon: ".$avgmonth;
        ImageTTFText ($im, $fontsize, 0,  320, 49, $txtcolor, $fontttf, $text);
	$text=$room;
        ImageTTFText ($im, $fontsize, 0,  3, 49, $txtcolor, $fontttf, $text);
	$imr=$im;
}
else # Willi:
{
	$im = ImageCreateTrueColor($imgmaxxks,$imgmaxyks);
	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxxks-1, $imgmaxyks-1, $white);

	$oldmin=0; //only the data from every 10min
	$min=120000;
	$max=-100;

	if ($maxcountKS < $maxdata) {$anzlines=$maxcountKS;}	else {$anzlines=$maxdata;}
	for ($x = 0; $x < $anzlines; $x++)
        {
	$temp=$resultreverse[$x][4];
	if ( $temp > $max ) $max=$temp;
	if ( $temp < $min and ($temp != '')) $min=$temp;
	}
	$temp=$resultreverse[0][4];
	$tempdiff=$max-$min;
	if ($tempdiff==0) $tempdiff=1;
	$fac=$imgmaxyks/$tempdiff;


	$xold=$imgmaxxks;
	$yold=round($imgmaxyks-(($resultreverse[0][4]-$min)*$fac));

	for ($x = 0; $x < count($resultreverse); $x++)
        {
	$y = round($imgmaxyks-(($resultreverse[$x][4]-$min)*$fac));
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
	ImageLine($im, $imgmaxxks-$maxcountKS, 0,$imgmaxxks-$maxcountKS , $imgmaxyks, $white);
		$text="Willi";
		$fontsize=7;
        	$txtcolor=$bg3p; 
        	ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
	$fontsize=9;
	$text=$temp;
        ImageTTFText ($im, $fontsize, 0, 80, 35, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	
	$text2="min= $min max= $max";
        ImageTTFText ($im, $fontsize, 0, 60, 47, $txtcolor, $fontttf, $text2);
	$text=$resultreverse[0][0];
        ImageTTFText ($im, $fontsize, 0,  $imgmaxxks-130, 15, $txtcolor, $fontttf, $text);
	$text=$room;
        ImageTTFText ($im, $fontsize, 0,  7, 47, $txtcolor, $fontttf, $text);
	$imr=$im;
}




# big picture
$imall = ImageCreateTrueColor($imgmaxxks,$imgmaxyks*4);
ImageFill($imall, 0, 0, $bg2p);
ImageCopy ($imall,$imt,0,0,0,0,$imgmaxxks,$imgmaxyks);
ImageCopy ($imall,$imh,0,$imgmaxyks,0,0,$imgmaxxks,$imgmaxyks);
ImageCopy ($imall,$imw,0,$imgmaxyks*2,0,0,$imgmaxxks,$imgmaxyks);
ImageCopy ($imall,$imr,0,$imgmaxyks*3,0,0,$imgmaxxks,$imgmaxyks);


imagePng($imall,$savefile);
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
	imagestring($im, 1, 3, 25, "Please add the following to your fhem.cfg", $black);
	$logname=$draw."log";
	imagestring($im, 1, 3, 35, "define $logname FileLog $file $draw:*", $black);
	header("Content-type: image/png");
	imagePng($im);
	exit;
}

?>

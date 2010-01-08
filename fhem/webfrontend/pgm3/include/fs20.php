<?php

################# Creates graphics for pgm3
################

include "../config.php";


	$drawfs20=$_GET['drawfs20'];
	$statefs20=$_GET['statefs20'];
	$datefs20=$_GET['datefs20'];
	$room=$_GET['room'];


	## do we really need a new graphic??
	#$execorder=$tailpath.' -1 '.$file;
	#exec($execorder,$tail1);
 	#$parts = explode(" ", $tail1[0]);
	#$date=$parts[0];
	

	$savefile=$AbsolutPath."/tmp/FS20.".$drawfs20.".log.".$datefs20.".png";
	if (file_exists($savefile)) {

		$im2 = @ImageCreateFromPNG($savefile);
		header("Content-type: image/png");
		imagePng($im2);
		exit; # ;-)))
	}
	else #delete old pngs
	{
		$delfile=$AbsolutPath."/tmp/FS20.".$drawfs20.".log.*.png";
		foreach (glob($delfile) as $filename) {
   		unlink($filename);
		}
	}






	$im = ImageCreateTrueColor($imgmaxxfs20,$imgmaxyfs20);
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
	ImageRectangle($im, 0, 0, $imgmaxxfs20-1, $imgmaxyfs20-1, $white);

	if ((rtrim($statefs20)=="on" ) or (rtrim($statefs20)=="dimup") or (rtrim($statefs20)=="thermo-on"))
	{ 
	$im2 = ImageCreateFromGIF("FS20.on.gif");
	}
	else
	{
	$im2 = ImageCreateFromGIF("FS20.off.gif");
	};
	$w = imagesx($im2);
	$h = imagesy($im2);

	$datefs20sep=explode(" ",$datefs20);
	if ((substr($statefs20,0,12)=="on-for-timer" )
	   or
	    ($statefs20=="toggle"))
	{
	$im2 = ImageCreateFromGIF("FS20.on.gif");
	$im3 = ImageCreateFromGIF("FS20.off.gif");
   	Imagecopy($im,$im3,($imgmaxxfs20/2)-12,($imgmaxyfs20/2)-14,0,0,$w,$h);	
   	Imagecopy($im,$im2,($imgmaxxfs20/2)-2,($imgmaxyfs20/2)-14,0,0,$w,$h);	
	}
	else
	{
   	Imagecopy($im,$im2,($imgmaxxfs20/2)-8,($imgmaxyfs20/2)-14,0,0,$w,$h);	
	};
###ttf

	$txtcolor=$bg3p;
        $text=$statefs20;
	$fontsize=7;
        $box = @imageTTFBbox($fontsize,0, $fontttfb,$text);
        $textwidth = abs($box[4] - $box[0]);
        $textheight = abs($box[5] - $box[1]);
        $xcord = ($imgmaxxfs20/2)-($textwidth/2)-2;
        $ycord = ($imgmaxyfs20/2)+20;
        ImageTTFText ($im, $fontsize, 0, $xcord, $ycord, $txtcolor, $fontttfb, $text);

        $text=$datefs20sep[0];
        $box = @imageTTFBbox($fontsize,0, $fontttf,$text);
        $textwidth = abs($box[4] - $box[0]);
        $textheight = abs($box[5] - $box[1]);
        $xcord = ($imgmaxxfs20/2)-($textwidth/2)-2;
        $ycord = ($imgmaxyfs20/2)+30;
        ImageTTFText ($im, $fontsize, 0, $xcord, $ycord, $txtcolor, $fontttf, $text);
        
	$text=$datefs20sep[1];
        $box = @imageTTFBbox($fontsize,0, $fontttf,$text);
        $textwidth = abs($box[4] - $box[0]);
        $textheight = abs($box[5] - $box[1]);
        $xcord = ($imgmaxxfs20/2)-($textwidth/2)-2;
        $ycord = ($imgmaxyfs20/2)+40;
        ImageTTFText ($im, $fontsize, 0, $xcord, $ycord, $txtcolor, $fontttf, $text);

	$txtcolor=$bg3p;

	ImageTTFText ($im,  $fs20fontsizetitel, 0, 5, 15, $txtcolor, $fontttfb, $drawfs20);
	if ($room != '') {ImageTTFText ($im, 7, 0, 5, 26, $txtcolor, $fontttf, $txtroom.$room);};

	
	imagePng($im,$savefile);
	header("Content-type: image/png");
	imagePng($im);
?>

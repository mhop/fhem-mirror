<?php

################# Creates graphics for pgm3
################

include "../config.php";


	$drawfs20=$_GET['drawfs20'];
	$statefs20=$_GET['statefs20'];
	$datefs20=$_GET['datefs20'];
	$room=$_GET['room'];

	$im = ImageCreateTrueColor($imgmaxxfs20,$imgmaxyfs20);
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

	
	header("Content-type: image/png");
	imagePng($im);
?>

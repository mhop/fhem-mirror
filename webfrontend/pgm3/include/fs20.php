<?php

################# Creates graphics for pgm3
################

include "../config.php";


	$drawfs20=$_GET['drawfs20'];
	$statefs20=$_GET['statefs20'];
	$datefs20=$_GET['datefs20'];
	$icon=$_GET['icon'];
	$emap=$_GET['emap'];
	$subType=$_GET['subType'];
	$room=$_GET['room'];

	$img_path=$AbsolutPath."/include/img/";


	## do we really need a new graphic??
	#$execorder=$tailpath.' -1 '.$file;
	#exec($execorder,$tail1);
 	#$parts = explode(" ", $tail1[0]);
	#$date=$parts[0];
	

	$savefile=$AbsolutPath."/tmp/FS20.".$drawfs20.".log.".$datefs20.".png";

	if ((file_exists($savefile)) and (substr($statefs20,0,3) != 'MIS')) {
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

	$datefs20sep=explode(" ",$datefs20);
	$statefs20sep=explode(" ",$statefs20);


#echo (substr($statefs20sep[0],0,3)); 
#exit;

	if (($icon!='')) {
	   if ((substr($statefs20sep[0],0,3)=='dim')) {
	      $statefs20tmp = 'on';
	   }
	   else 
	   if ((substr($statefs20sep[0],0,3)=='MIS')) {
	      $statefs20tmp = 'missing';
	   }
	   else {
	      $statefs20tmp = $statefs20sep[0];
	   }
	   $im2 = ImageCreateFromPNG($img_path.$icon.".".$statefs20tmp.".png");
	}
	else {
	   $im2 = ImageCreateFromPNG($img_path.$statefs20sep[0].".png");
	}

	$w = imagesx($im2);
	$h = imagesy($im2);

	if ($roomname=='0') {
	   $roomc=$roomcorr;
	}
	else {
	   $roomc='0';
	}

   	Imagecopy($im,$im2,($imgmaxxfs20/2)-20,($imgmaxyfs20/2)-7-$roomc,0,0,$w,$h);	


	$datefs20sep_1=explode(" ",$datefs20);
	if (($dategerman == '1')) {
	   $datefs20_tmp_1 = $datefs20sep_1[0];
	   $datefs20sep_2=explode("-",$datefs20_tmp_1);
	   $date_button = $datefs20sep_2[2].".".$datefs20sep_2[1].".".$datefs20sep_2[0];
	}
	else {
	   $date_button = $datefs20sep_1[0];
	}
	$time_button = $datefs20sep_1[1];


	if ($namesortbutton == '1') {
	   $pos_1 = strpos($drawfs20,$namesortbuttonsign);
	   if ($pos_1 > 0) {
	      $drawfs20=substr($drawfs20,$pos_1+1);
	   }
	}

	if ($namereplacebutton == '1') {
	   $drawfs20=str_replace($namereplacebuttonsign, " ", $drawfs20);
	}



###ttf

	if ($emap=='') {
	   $text=$statefs20;
	}
	else {
	   $text=$emap;
	}
#echo $text;
#exit;

	$txtcolor=$bg3p;
	$fontsize=7;
        $box = @imageTTFBbox($fontsize,0, $fontttfb,$text);
        $textwidth = abs($box[4] - $box[0]);
        $textheight = abs($box[5] - $box[1]);
        $xcord = ($imgmaxxfs20/2)-($textwidth/2)-2;
        $ycord = ($imgmaxyfs20/2)+23;
        ImageTTFText ($im, $fontsize, 0, $xcord, $ycord, $txtcolor, $fontttfb, $text);

        $text=$date_button;
        $box = @imageTTFBbox($fontsize,0, $fontttf,$text);
        $textwidth = abs($box[4] - $box[0]);
        $textheight = abs($box[5] - $box[1]);
        #$xcord = ($imgmaxxfs20/2)-($textwidth/2)+53;
        $xcord = ($imgmaxxfs20)-($textwidth)-2;
        $ycord = ($imgmaxyfs20/2)+33;
        ImageTTFText ($im, $fontsize, 0, $xcord, $ycord, $txtcolor, $fontttf, $text);
        
	 $text=$time_button;
        $box = @imageTTFBbox($fontsize,0, $fontttf,$text);
        $textwidth = abs($box[4] - $box[0]);
        $textheight = abs($box[5] - $box[1]);
        #$xcord = ($imgmaxxfs20/2)-($textwidth/2)-58;
        $xcord = 3;
        $ycord = ($imgmaxyfs20/2)+33;
        ImageTTFText ($im, $fontsize, 0, $xcord, $ycord, $txtcolor, $fontttf, $text);

	$txtcolor=$bg3p;


	ImageTTFText ($im,  $fs20fontsizetitel, 0, 5, 15, $txtcolor, $fontttfb, $drawfs20);
	if ($room != '' and $roomname=='1') {
	   ImageTTFText ($im, 7, 0, 5, 26, $txtcolor, $fontttf, $txtroom.$room);
	};

	
	imagePng($im,$savefile);
	header("Content-type: image/png");
	imagePng($im);
?>

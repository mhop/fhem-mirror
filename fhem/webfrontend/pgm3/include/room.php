<?php

################# Creates graphics for pgm3
################

include "../config.php";


	$room=$_GET['room'];
	$showroom=$_GET['showroom'];

	$im = ImageCreateTrueColor($imgmaxxroom,$imgmaxyroom);
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
	
	if ($room==$showroom)
	{
		$imgcolor=$bg1p;
		$txtcolor=$white;
	}
	else
	{
		$imgcolor=$bg2p;
		$txtcolor=$bg3p;
	}

	ImageFill($im, 0, 0, $imgcolor);
	ImageRectangle($im, 0, 0, $imgmaxxroom-1, $imgmaxyroom-1, $white);
###ttf
	$text=$room;
	$box = @imageTTFBbox($roomfontsizetitel,0, $fontttfb,$text);
	$textwidth = abs($box[4] - $box[0]);
	$textheight = abs($box[5] - $box[1]);
	$xcord = ($imgmaxxroom/2)-($textwidth/2)-2;
	$ycord = ($imgmaxyroom/2)+($textheight/2);
	ImageTTFText ($im, $roomfontsizetitel, 0, $xcord, $ycord, $txtcolor, $fontttfb, $text);

	header("Content-type: image/png");
	imagePng($im);
?>

<?php
	
	
	
################# Creates graphics vor pgm3


################

include "../config.php";
include "functions.php";


	$userdefnr=$_GET['userdefnr'];

	$room=$userdef[$userdefnr]['room'];
#echo "Raum: $room"; exit;



	$file= $userdef[$userdefnr]['logpath'];
	$drawuserdef=$userdef[$userdefnr]['name'];
	$imgmaxxuserdef=$userdef[$userdefnr]['imagemax'];
	$imgmaxyuserdef=$userdef[$userdefnr]['imagemay'];
	$SemanticLong=$userdef[$userdefnr]['semlong'];
	$SemanticShort=$userdef[$userdefnr]['semshort'];
	$type='UserDef '.$userdefnr;
	$logrotateUSERDEFlines=$userdef[0]['logrotatelines'];
	$maxcountUSERDEF=$userdef[0]['maxcount'];
	$XcorrectMainTextUSERDEF=$userdef[0]['XcorrectMainText'];



	#if (! in_array($type,$supported_USERDEF)) show_error_type($imgmaxxuserdef,$imgmaxyuserdef,$type);
        if (! file_exists($file)) show_error($file,$drawuserdef,$imgmaxxuserdef,$imgmaxyuserdef,$type,$userdefnr);
	
	$_SESSION["arraydata"] = array();
	
	$im = ImageCreateTrueColor($imgmaxxuserdef,$imgmaxyuserdef);
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
	ImageRectangle($im, 0, 0, $imgmaxxuserdef-1, $imgmaxyuserdef-1, $white);

  	$array = file($file); 
	$oldmin=0; //only the data from every 10min
	$oldhour=0; //only the data from every 10min
	$mintemp=100;
	$maxtemp=-100;
	$counter=count($array);
	#if ($maxcountUSERDEF <  $counter)  {$counter=$maxcountUSERDEF;};
	
	#Logrotate
	if ((($logrotateUSERDEFlines+100) < $counter) and ($logrotate == 'yes')) LogRotate($array,$file,$logrotateUSERDEFlines);

#print_r($array[1]);  
#print_r($array[1][12]);  exit;
###########################################################################

   	for ($x = 0; $x < $counter; $x++)
	{
		list ($date,$userdef,$t,$temp,$h,$hum) = preg_split("/[\s,]+/", $array[$x]);
		if  ((($array[$x][14] != $oldmin) or ($array[$x][12] != $oldhour)  or ($x==$counter-1))
				and ( $date !="NEWLOGS"))
		{
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $_SESSION["arraydata"],array($date,$temp,$hum));
		}
     	}

	$resultreverse = array_reverse($_SESSION["arraydata"]);
	$xold=$imgmaxxuserdef;
	
	if ( $imgmaxxuserdef > count ($resultreverse) )
	{ $_SESSION["maxdata"] = count ($resultreverse); }
	else
	{ $_SESSION["maxdata"] = $imgmaxxuserdef; };

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
      	$fac=$imgmaxyuserdef/$tempdiff;
	$yold=round($imgmaxyuserdef-(($resultreverse[0][1]-$mintemp)*$fac));
	 ###################
	

	if ($maxcountUSERDEF <   $_SESSION["maxdata"])  {$anzlines=$maxcountUSERDEF;} else {$anzlines= $_SESSION["maxdata"];}
	for ($x = 0; $x < $anzlines; $x++)

        {
 		$parts = explode("_", $resultreverse[$x][0]);
		if ( ($parts[0] != $olddate) )
		{
			$olddate=$parts[0];
			ImageLine($im, $imgmaxxuserdef-$x, 0,$imgmaxxuserdef-$x , $imgmaxyuserdef, $bg1p);
		}
		$y = round($imgmaxyuserdef-(($resultreverse[$x][1]-$mintemp)*$fac));
		ImageLine($im, $imgmaxxuserdef-$x, $y, $xold, $yold, $red);
		$xold=$imgmaxxuserdef-$x;
		$yold=$y;
	};
	ImageLine($im, $imgmaxxuserdef-$x, 0,$imgmaxxuserdef-$x , $imgmaxyuserdef, $yellow);
	ImageLine($im, $imgmaxxuserdef-$maxcountUSERDEF, 0,$imgmaxxuserdef-$maxcountUSERDEF , $imgmaxyuserdef, $white);
	$tempTEMP=$temp;





#############################################################################

	$text=$SemanticLong;
	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 3, 10, $txtcolor, $fontttf, $text);
        $txtcolor=$bg3p; 
	$fontsize=9;
	$text=$tempTEMP." ".$SemanticShort;
	$tvalue=$tempTEMP;
        ImageTTFText ($im, $fontsize, 0, 90-$XcorrectMainTextUSERDEF, 37, $txtcolor, $fontttfb, $text);

        $txtcolor=$bg3p; 
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im,  $fontsize, 0, 67-$XcorrectMainTextUSERDEF, 49, $txtcolor, $fontttf, $text);
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxuserdef-127,  13, $txtcolor, $fontttf, $text);
#############################################################################
## general
        $txtcolor=$bg3p; 
	$fontsize=9;
	$text= $drawuserdef;
        ImageTTFText ($im, 8, 0,90-$XcorrectMainTextUSERDEF, 22, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text=$txtroom.$room;
        ImageTTFText ($im,  $fontsize, 0, 3,  $imgmaxyuserdef-7, $txtcolor, $fontttf, $text);
	$text=$type;
        ImageTTFText ($im,  $fontsize, 0, 5,  $imgmaxyuserdef-17, $txtcolor, $fontttf, $text);


#############################################################################
#ok. let's draw
	
	header("Content-type: image/png");
	imagePng($im);



###############################################################
## first start: shows the required logfiles
function show_error($file,$drawuserdef,$imgmaxx,$imgmaxy,$type,$section)
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
 	$text="Please check the userdef[$section] of <pgm3>/config.php and refresh your browser";
        #$fontsize=7;
        #ImageTTFText ($im, $fontsize, 0, 5, 30, $txtcolor, $fontttf, $text);
	#$logname=$drawuserdef."log";
        #$fontsize=9;
	#$text="define $logname FileLog $file $drawuserdef:.*s:.*";
        ImageTTFText ($im, $fontsize, 0, 5, 45, $txtcolor, $fontttf, $text);

	header("Content-type: image/png");
	imagePng($im);
	exit;
}

###############################################################

?>

<?php
	
	
	
################# Creates graphics vor pgm3


################

include "../config.php";
include "functions.php";


	$userdefnr=$_GET['userdefnr'];
#$userdefnr=0;

	$room=$userdef[$userdefnr]['room'];

	$file= $userdef[$userdefnr]['logpath'];
	$drawuserdef=$userdef[$userdefnr]['name'];
	$imgmaxxuserdef=$userdef[$userdefnr]['imagemax'];
	$imgmaxyuserdef=$userdef[$userdefnr]['imagemay'];
	$SemanticLong=$userdef[$userdefnr]['semlong'];
	$SemanticShort=$userdef[$userdefnr]['semshort'];
	$valuefield=$userdef[$userdefnr]['valuefield'];
	$type='UserDef '.$userdefnr;
	$logrotateUSERDEFlines=$userdef[$userdefnr]['logrotatelines'];
	$maxcountUSERDEF=$userdef[$userdefnr]['maxcount'];
	$XcorrectMainTextUSERDEF=$userdef[$userdefnr]['XcorrectMainText'];
	$gnuplottype=$userdef[$userdefnr]['gnuplottype'];


#	echo "userdefnr: $userdefnr";
#	echo "file: $file";
#exit;
        if (! file_exists($file)) show_error($file,$drawuserdef,$imgmaxxuserdef,$imgmaxyuserdef,$type,$userdefnr);
	


	## do we really need a new graphic??
	$execorder=$tailpath.' -1 '.$file;
	exec($execorder,$tail1);
 	$parts = explode(" ", $tail1[0]);


	$today= date("H");
        $savefile=$AbsolutPath."/tmp/USERDEF.".$drawuserdef.".log.".$parts[0].".png";
	if (file_exists($savefile)) {
		$fmtime=date ("H", filemtime($savefile)); #at least one new graphic per hour (gnuplot)
	     if ($fmtime == $today) {
		$im2 = @ImageCreateFromPNG($savefile);
		header("Content-type: image/png");
		imagePng($im2);
		exit; # ;-)))
	     }
	}
	else #delete old pngs
	{
                $delfile=$AbsolutPath."/tmp/USERDEF.".$drawuserdef.".log.*.png";
		foreach (glob($delfile) as $filename) {
   		unlink($filename);
		}
	}

	
	


	$_SESSION["arraydata"] = array();
	

  	$array = file($file); 
	$oldmin=0; //only the data from every 10min
	$oldhour=0; //only the data from every 10min
	$mintemp=100;
	$maxtemp=-100;
	$counter=count($array);
	
	#Logrotate
	if ((($logrotateUSERDEFlines+100) < $counter) and ($logrotate == 'yes')) LogRotate($array,$file,$logrotateUSERDEFlines);

#echo "test1";
#print_r($array[1]);  
#print_r($array[1][12]);  exit;
###########################################################################

   	for ($x = 0; $x < $counter; $x++)
	{
		list ($date,$f2,$f3,$f4,$f5,$f6,$f7,$f8,$f9,$f10) = preg_split("/[\s,]+/", $array[$x]);
		if  ((($array[$x][14] != $oldmin) or ($array[$x][12] != $oldhour)  or ($x==$counter-1))
				and ( $date !="NEWLOGS"))
		{

	switch ($valuefield):
        	Case 1: $value=$date;break;
        	Case 2: $value=$f2;break;
	        Case 3: $value=$f3;break;
        	Case 4: $value=$f4;break;
	        Case 5: $value=$f5;break;
        	Case 6: $value=$f6;break;
	        Case 7: $value=$f7;break;
        	Case 8: $value=$f8;break;
	        Case 9: $value=$f9;break;
        	Case 10: $value=$f10;break;
	endswitch; 
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $_SESSION["arraydata"],array($date,$value));
			$temp=$value;
		}
     	}
	


	# Start Graphic
	$im = ImageCreateTrueColor($imgmaxxuserdef,$imgmaxyuserdef);
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
	ImageRectangle($im, 0, 0, $imgmaxxuserdef-1, $imgmaxyuserdef-1, $white);




	$xold=$imgmaxxuserdef;
	$resultreverse = array_reverse($_SESSION["arraydata"]);
	
	if ( $imgmaxxuserdef > count ($resultreverse) )
	{ $_SESSION["maxdata"] = count ($resultreverse); }
	else
	{ $_SESSION["maxdata"] = $imgmaxxuserdef; };

	###################
        ### min/max
      	$mintemp=1000;
      	$maxtemp=-1000;
      	for ($x = 0; $x <= $_SESSION["maxdata"]; $x++)
      	{
              if ( $resultreverse[$x][1] > $maxtemp ) $maxtemp=$resultreverse[$x][1];
              if ( ($resultreverse[$x][1] < $mintemp) and ($resultreverse[$x][1]>-1000) ) $mintemp=$resultreverse[$x][1];
      	}
      	$tempdiff=$maxtemp-$mintemp;
      	if ($tempdiff==0) $tempdiff=1;
      	$fac=$imgmaxyuserdef/$tempdiff;
	$yold=round($imgmaxyuserdef-(($resultreverse[0][1]-$mintemp)*$fac));
	 ###################
	

	if ($maxcountUSERDEF <   $_SESSION["maxdata"])  {$anzlines=$maxcountUSERDEF;} else {$anzlines= $_SESSION["maxdata"];}



if ($gnuplottype=='piri' or $gnuplottype=='fs20')
{
			$datumtomorrow= mktime (0,0,0,date("m")  ,date("d")+1,date("Y"));
			$xrange1= date ("Y-m-d",$datumtomorrow);
			$datumyesterday= mktime (0,0,0,date("m")  ,date("d")-5,date("Y"));
			$xrange2= date ("Y-m-d",$datumyesterday);
			$xrange="set xrange ['$xrange2':'$xrange1']";
			$gnuplotfile=$AbsolutPath."/tmp/".$drawuserdef;
			$gnuplotpng=$drawuserdef.".sm.png";
			
			$messageA=<<<EOD
			#set terminal png transparent crop size 625,83
			#set terminal png transparent crop size $imgmaxxuserdef-$x+5,83
			set terminal png transparent crop size $imgmaxxuserdef-100,$imgmaxyuserdef+31
			set output '$AbsolutPath/tmp/$gnuplotpng' 
			set key off
			set xdata time 
			set timefmt '%Y-%m-%d_%H:%M:%S' 
			set noytics 
			#set border linecolor rgbcolor "#F5F5F5"
			set border linecolor rgbcolor "#6394BD"
			#set border linecolor rgbcolor "#6E94B7"
			#set border linecolor rgb "$bg2"
			#set border linecolor rgb "white"
			#set noborder
			#set noxtics
			unset label
			$xrange
			set grid linetype 1 linecolor rgb "white"
			set yrange [-0.3:1.3]
			#set size 0.8,0.15
			set format x ''

EOD;
}


switch ($gnuplottype):
        	Case 'piri':
			$messageB=<<<EOD
			plot "< awk '{print $1, 1; }' $file "\
		        using 1:2 title '' with impulses
EOD;
			break;
        	Case 'fs20':
			$actdate= date("Y-m-d_H:i:s");
			$newlastline=$actdate." ".$f2." ".$f3." ".$f4." ".$f5." ".$f6;
			array_push( $array ,$newlastline);
			$filename=substr($file,strrpos($file, '/')+1);
			$filename=$AbsolutPath.'/tmp/'.$filename.'.tmp';
 			$f1=fopen("$filename","w");
			 for ($x = 0; $x <= count($array); $x++)
        		{
				fputs($f1,$array[$x]);
			}
			fputs($f1,"\n");
                        fclose($f1);


			$messageB=<<<EOD
			plot "< awk '{print $1, $3==\"on\"? 1 : $3==\"dimup\"? 1 : $3==\"dimdown\"? 0 : $3==\"off\"? 0 : 0.5;}' \
			$filename" using 1:2 title '' with steps

EOD;
			break;

		default: 
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
	break;
endswitch;


if ($gnuplottype=='piri' or $gnuplottype=='fs20')
{
			$message=$messageA.$messageB;
			$f1=fopen("$AbsolutPath/tmp/$drawuserdef","w+");
			fputs($f1,$message);
			fclose($f1);
			exec("$gnuplot $AbsolutPath/tmp/$drawuserdef",$output);
			#echo "output: $output";exit;
		#sleep(3);

			$w = imagesx($im);
			$h = imagesy($im);

			$im2 = imagecreatefrompng("$AbsolutPath/tmp/$gnuplotpng");
			$w2 = imagesx($im2);
			$h2 = imagesy($im2);
			#ImageCopy($im,$im2,163,10,0,0,$w2,$h2);
			ImageCopy($im,$im2,153,5,0,0,$w2,$h2);
}



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
	if (is_numeric($mintemp) || is_numeric($maxtemp)) {
		$text="min= $mintemp max= $maxtemp";
			ImageTTFText ($im,  $fontsize, 0, 67-$XcorrectMainTextUSERDEF, 49, $txtcolor, $fontttf, $text);
	}
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxuserdef-127,  15, $txtcolor, $fontttf, $text);
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
	
	imagePng($im,$savefile);
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
        ImageTTFText ($im, $fontsize, 0, 5, 45, $txtcolor, $fontttf, $text);

	header("Content-type: image/png");
	imagePng($im);
	exit;
}

###############################################################

?>

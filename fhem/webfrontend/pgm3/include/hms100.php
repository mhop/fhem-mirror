<?php
	
	
	
################# Creates graphics vor pgm3


################

include "../config.php";
include "functions.php";


$drawhms=$_GET['drawhms'];
$room=$_GET['room'];
$type=$_GET['type'];
$supported_HMS= array('HMS100T','HMS100TF','HMS100WD','HMS100MG','HMS100TFK','HMS100W','RM100-2');




	$file="$logpath/$drawhms.log"; 
	if (! in_array($type,$supported_HMS)) show_error_type($imgmaxxhms,$imgmaxyhms,$type);
        if (! file_exists($file)) show_error($file,$drawhms,$imgmaxxhms,$imgmaxyhms,$type);
	
	$_SESSION["arraydata"] = array();
	
	$im = ImageCreateTrueColor($imgmaxxhms,$imgmaxyhms);
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
	ImageRectangle($im, 0, 0, $imgmaxxhms-1, $imgmaxyhms-1, $white);

  	$array = file($file); 
	$oldmin=0; //only the data from every 10min
	$oldhour=0; //only the data from every 10min
	$mintemp=100;
	$maxtemp=-100;
	$counter=count($array);
	
	#Logrotate
	if ((($logrotateHMSlines+100) < $counter) and ($logrotate == 'yes')) LogRotate($array,$file,$logrotateHMSlines);

#print_r($array[1]);  
#print_r($array[1][12]);  exit;
###########################################################################

if ( $type == "HMS100T" or $type == "HMS100TF" )  ## hms100t-Device.  
{
	
   	for ($x = 0; $x < $counter; $x++)
	{
		list ($date,$hms,$t,$temp,$h,$hum) = preg_split("/[\s,]+/", $array[$x]);
		if  ((($array[$x][14] != $oldmin) or ($array[$x][12] != $oldhour)  or ($x==$counter-1))
				and ( $date !="NEWLOGS"))
		{
			$oldmin=$array[$x][14]; 
			$oldhour=$array[$x][12]; 
			array_push( $_SESSION["arraydata"],array($date,$temp,$hum));
		}
     	}

	$resultreverse = array_reverse($_SESSION["arraydata"]);
	$xold=$imgmaxxhms;
	
	if ( $imgmaxxhms > count ($resultreverse) )
	{ $_SESSION["maxdata"] = count ($resultreverse); }
	else
	{ $_SESSION["maxdata"] = $imgmaxxhms; };

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
      	$fac=$imgmaxyhms/$tempdiff;
	$yold=round($imgmaxyhms-(($resultreverse[0][1]-$mintemp)*$fac));
	 ###################
	

	for ($x = 0; $x <= $_SESSION["maxdata"]; $x++)

        {
 		$parts = explode("_", $resultreverse[$x][0]);
		if ( ($parts[0] != $olddate) )
		{
			$olddate=$parts[0];
			ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $bg1p);
		}
		$y = round($imgmaxyhms-(($resultreverse[$x][1]-$mintemp)*$fac));
		ImageLine($im, $imgmaxxhms-$x, $y, $xold, $yold, $red);
		$xold=$imgmaxxhms-$x;
		$yold=$y;
	};
	ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $yellow);
	$tempTEMP=$temp;
}; #HMS100T


if ( $type == "HMS100TF")  ## hms100tf-Device.  
{
#Humidity...

	#$oldmin=0; //only the data from every 10min
	$min=100;
	$max=-100;

	for ($x = 0; $x <= $_SESSION["maxdata"]; $x++)
        {
	$temp=$resultreverse[$x][2];
	if ( $temp > $max ) $max=$temp;
	if ( $temp < $min ) $min=$temp;
	}
	$temp=$resultreverse[0][2];
	$tempdiff=$max-$min;
	$fac=$imgmaxyhms/$tempdiff;


	$xold=$imgmaxxhms;
	$yold=round($imgmaxyhms-(($resultreverse[0][2]-$min)*$fac));

	for ($x = 0; $x < count($resultreverse); $x++)
        {
		$y = round($imgmaxyhms-(($resultreverse[$x][2]-$min)*$fac));
		ImageLine($im, $imgmaxxhms-$x, $y, $xold, $yold, $white);
		$xold=$imgmaxxhms-$x;
		$yold=$y;
	};
        
	$text="Humidity";
	$fontsize=7;
        $txtcolor=$white; 
        ImageTTFText ($im, $fontsize, 0, 5, 23, $txtcolor, $fontttf, $text);
	$txtcolor=$white;
	
	$fontsize=9;
	$text=$temp." %";
	$hvalue=$temp;
        ImageTTFText ($im, $fontsize, 0, 210, 35, $txtcolor, $fontttfb, $text);

        $txtcolor=$white; 
	$fontsize=7;
	$text="min= $min max= $max";
        ImageTTFText ($im,  $fontsize, 0, 182, 47, $txtcolor, $fontttf, $text);


# Taupunkt
#	$tp  = Taupunkt($tvalue,$hvalue);
#	$fontsize=9;
#	$text=$tp." °C";
#       ImageTTFText ($im, $fontsize, 0, 350, 35, $bg1p, $fontttfb, $text);
#       $txtcolor=$orange; 
#	$fontsize=7;
#	$text="Taupunkt";
#        ImageTTFText ($im,  $fontsize, 0, 350, 47, $bg1p, $fontttf, $text);
};



#############################################################################
if ( $type == "HMS100T" or $type == "HMS100TF" )
{

	$text="Temperature";
	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);
        $txtcolor=$bg3p; 
	$fontsize=9;
	$text=$tempTEMP." &#176;C";
	$tvalue=$tempTEMP;
        ImageTTFText ($im, $fontsize, 0, 80, 35, $txtcolor, $fontttfb, $text);

        $txtcolor=$bg3p; 
	$fontsize=7;
	$text="min= $mintemp max= $maxtemp";
        ImageTTFText ($im,  $fontsize, 0, 62, 47, $txtcolor, $fontttf, $text);
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxhms-127,  13, $txtcolor, $fontttf, $text);
};
#############################################################################
## general
        $txtcolor=$bg3p; 
	$fontsize=9;
	$text= $drawhms;
        ImageTTFText ($im, 8, 0, 80, 18, $txtcolor, $fontttfb, $text);
	$fontsize=7;
	$text=$txtroom.$room;
        ImageTTFText ($im,  $fontsize, 0, 5,  $imgmaxyhms-7, $txtcolor, $fontttf, $text);
	$text=$type;
        ImageTTFText ($im,  $fontsize, 0, 5,  $imgmaxyhms-17, $txtcolor, $fontttf, $text);


#############################################################################
if ( $type == "HMS100WD" or $type == "HMS100MG" or $type == "HMS100W" 
	or $type == "HMS100TFK" or $type=="RM100-2")
{
  for ($x = 0; $x < $counter; $x++)
        {
               if ( $type=="RM100-2" ) 

		{list ($date,$hms,$detect,$onoff) = preg_split("/[\s,]+/", $array[$x]);}
	       else
                {list ($date,$hms,$kind,$detect,$onoff) = preg_split("/[\s,]+/", $array[$x]);};
                if  ($x!=$counter-1 and  $date !="NEWLOGS")
                {
                        array_push( $_SESSION["arraydata"],array($date,$onoff));
                }
        }

        $resultreverse = array_reverse($_SESSION["arraydata"]);
        $xold=$imgmaxxhms;

        if ( $imgmaxxhms > count ($resultreverse) )
        { $_SESSION["maxdata"] = count ($resultreverse); }
        else
        { $_SESSION["maxdata"] = $imgmaxxhms; };

   for ($x = 0; $x < $_SESSION["maxdata"]-1; $x++)

        {
                $parts = explode("_", $resultreverse[$x][0]);
                if ( ($parts[0] != $olddate) )
                {
                        $olddate=$parts[0];
                        ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $bg1p);
                }
                $y = round($imgmaxyhms/2);
	 	$isonoff=rtrim($resultreverse[$x][1]);
       	 	if ( $isonoff == "off" )
                { ImageLine($im, $imgmaxxhms-$x, $y, $imgmaxxhms-$x,$y, $white);}
                else
                { ImageLine($im, $imgmaxxhms-$x, $y-1, $imgmaxxhms-$x,$y+1, $red);
		};

                $xold=$imgmaxxhms-$x;
                $yold=$y;
        };
        ImageLine($im, $imgmaxxhms-$x, 0,$imgmaxxhms-$x , $imgmaxyhms, $yellow);
       
	 if ($type=='HMS100WD' or $type=='HMS100W'){$text="Water detected:";}
	elseif ($type=='HMS100MG'){$text="Gas detected:";}
	elseif ($type=='RM100-2'){$text="Smoke detected:";}
	else {$text="Switch open:";}
 	$fontsize=7;
        $txtcolor=$bg3p; 
        ImageTTFText ($im, $fontsize, 0, 180, 18, $txtcolor, $fontttf, $text);

        if ($isonoff == "off" )
        {ImageTTFText ($im, 9, 0, 265, 18, $white, $fontttf,'no');}
        else
        {ImageTTFText ($im, 9, 0, 265, 18, $red, $fontttfb,'YES');}

        $txtcolor=$bg3p; 
	$fontsize=7;
	$text=$resultreverse[0][0];
        ImageTTFText ($im,  $fontsize, 0, $imgmaxxhms-127,  13, $txtcolor, $fontttf, $text);

};

#ok. let's draw
	
	header("Content-type: image/png");
	imagePng($im);



###############################################################
## first start: shows the required logfiles
function show_error($file,$drawhms,$imgmaxx,$imgmaxy,$type)
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
 	$text="Please add the following to your fhz1000.cfg and restart fhz1000.pl:";
        $fontsize=7;
        ImageTTFText ($im, $fontsize, 0, 5, 30, $txtcolor, $fontttf, $text);
	$logname=$drawhms."log";
        $fontsize=9;
	if ($type=='HMS100WD')
	{
		$text="define $logname FileLog $file $drawhms:.*Water.*";
	}
	elseif ($type=='RM100-2')
	{
		$text="define $logname FileLog $file $drawhms:.*smoke*";
	}
	elseif ($type=='HMS100W')
	{
		$text="define $logname FileLog $file $drawhms:.*Water.*";
	}
	elseif ($type=='HMS100MG')
	{
		$text="define $logname FileLog $file $drawhms:.*Gas.*";
	}
	elseif ($type=='HMS100TFK')
	{
		$text="define $logname FileLog $file $drawhms:.*Switch.*";
	}
	else
	{
		$text="define $logname FileLog $file $drawhms:.*T:.*";
	}
        ImageTTFText ($im, $fontsize, 0, 5, 45, $txtcolor, $fontttf, $text);

	header("Content-type: image/png");
	imagePng($im);
	exit;
}

###############################################################
## supported HMS??
function show_error_type($imgmaxx,$imgmaxy,$type)
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
 	$text="HMS-Device $type is not supported";
        $fontsize=7;
        $txtcolor=$bg3p;
        ImageTTFText ($im, $fontsize, 0, 5, 12, $txtcolor, $fontttf, $text);

	ImageFill($im, 0, 0, $bg2p);
	ImageRectangle($im, 0, 0, $imgmaxx-1, $imgmaxy-1, $white);
	
	header("Content-type: image/png");
	imagePng($im);
	exit;
}

?>

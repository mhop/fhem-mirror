<?php

##Functions for pgm3


function LogRotate($array,$file,$logrotatelines)
{
	$counter=count($array);
	$filename=$file;
	
	if (!$handle = fopen($filename, "w")) {
         print "Logrotate: cannot open $filename -- correct rights??";
         exit;
   	}
        for ($x = $counter-$logrotatelines; $x < $counter; $x++)
        {fwrite($handle, $array[$x]);};

	fclose($handle);
}


function bft($windspeed)        # wind speed in Beaufort
{
        if($windspeed>= 118.5) { $bft= 12; }
        elseif($windspeed>= 103.7) { $bft= 11; }
        elseif($windspeed>=  88.9) { $bft= 10; }
        elseif($windspeed>=  75.9) { $bft=  9; }
        elseif($windspeed>=  63.0) { $bft=  8; }
        elseif($windspeed>=  51.9) { $bft=  7; }
        elseif($windspeed>=  40.7) { $bft=  6; }
        elseif($windspeed>=  29.6) { $bft=  5; }
        elseif($windspeed>=  20.4) { $bft=  4; }
        elseif($windspeed>=  13.0) { $bft=  3; }
        elseif($windspeed>=   7.4) { $bft=  2; }
        elseif($windspeed>=   1.9) { $bft=  1; }
	else $bft= 0;
        return($bft);
}


function randdefine()
{
	$rand1 = rand(500,20000);
        $rand2 = rand(500,20000);
        $rq = md5($rand1.$rand2);
        $randdefine=substr($rq,0,5);
return ($randdefine);
}


?>

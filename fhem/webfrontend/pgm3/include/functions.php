<?php

##Functions for pgm3

### If DB-query is used, this is the only point of connect. ###
#if ($DBUse=="1") {
#  @mysql_connect($DBNode, $DBUser, $DBPass) or die("Can't connect");
#  @mysql_select_db($DBName) or die("No database found");
#}

function LogRotate($array,$file,$logrotatelines)
{
	$counter=count($array);
	$filename=$file;
	
	if (!$handle = fopen($filename, "w")) {
         print "Logrotate: cannot open $filename -- correct rights?? Read the chapter in the config.php!";
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


# see http://de.wikipedia.org/wiki/Taupunkt, http://en.wikipedia.org/wiki/Dewpoint
# The dew point (or dewpoint) is the temperature to which a given parcel of air must be cooled, at constant 
# barometric pressure, for water vapor to condense into water. The condensed water is called dew. The dew point 
# is a saturation point.
# approximation valid for -30°C < $temp < 70°C
function dewpoint($temp,$hum)	# dew point and temperature in °C, humidity in % 
{
	$log= log($hum/100.0);
	return( (241.2*$log+(4222.03716*$temp)/(241.2+$temp))/(17.5043-$log-(17.5043*$temp)/(241.22+$temp)) );
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

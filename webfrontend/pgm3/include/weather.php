<?php


setlocale (LC_ALL, 'de_DE.utf8');

#include '../config.php'; #only debug



function website_WEATHER($station, $land,  $sprache)
{
	$icons_src="/";
	$icons_google = "/ig/images/weather/";
	
	$api = simplexml_load_string(utf8_encode(file_get_contents("http://www.google.com/ig/api?weather=".$station."&hl=".$sprache)));
	if (! $api->weather->forecast_information) { $WEATHER="FALSE"; return $WEATHER;};
	#print_r($api);
	#exit;
	
	$WEATHER = array();

	$WEATHER['city'] = $api->weather->forecast_information->city->attributes()->data;

	$WEATHER['datum'] = $api->weather->forecast_information->forecast_date->attributes()->data;
	
	$WEATHER['zeit'] = $api->weather->forecast_information->current_date_time->attributes()->data;
	
	$WEATHER[0]['condition'] = $api->weather->current_conditions->condition->attributes()->data;
	$WEATHER[0]['temperatur'] = $api->weather->current_conditions->temp_c->attributes()->data;
	$WEATHER[0]['humidity'] = $api->weather->current_conditions->humidity->attributes()->data;
	$WEATHER[0]['wind'] = $api->weather->current_conditions->wind_condition->attributes()->data;
	$WEATHER[0]['icon'] = str_replace($icons_google, $icons_src, $api->weather->current_conditions->icon->attributes()->data);
	
	$i = 1;
	foreach($api->weather->forecast_conditions as $weather)
	{
		$WEATHER[$i]['weekday'] = $weather->day_of_week->attributes()->data;
		$WEATHER[$i]['condition'] = $weather->condition->attributes()->data;
		$WEATHER[$i]['low'] = $weather->low->attributes()->data;
		$WEATHER[$i]['high'] = $weather->high->attributes()->data;
		$WEATHER[$i]['icon'] = str_replace($icons_google, $icons_src, $weather->icon->attributes()->data);
		$i++;
	}
	
	return $WEATHER;
}



$WEATHER = website_WEATHER($weathercity, $weathercountry, $weatherlang);
    if ($WEATHER=="FALSE")
    {
	echo "<td colspan=4 $bg2>Google-Weather-Api failed.</td>";
    } 
    else
    {


	$city=str_replace(" ","<br>",$WEATHER['city']);
	echo "<td colspan=4 $bg2><table cellspacing='1' cellpadding='0' align='center' border=0 width='100%' $bg2><tr $bg2>";
	echo "<td $bg2><font $fontcolor3><b>".$city."</b></font></td><font $fontcolor3>";
	if ($weatherlang=='de') {$now='Jetzt';} else $now='Now';

	echo "<td><font $fontcolor3><b>$now: </b>";
	echo $WEATHER[0]['condition']."<br/>\n";

  	$pos=strrpos($WEATHER[0]['humidity'],':');
  	$hum=substr($WEATHER[0]['humidity'],$pos+2,strlen($WEATHER[0]['humidity']));

	echo "T/Hum: ".$WEATHER[0]['temperatur']."&deg; / $hum<br/>\n";
	echo $WEATHER[0]['wind']."<br/>\n";
	echo "<img src=\"http://www.google.com/ig/images/weather".$WEATHER[0]['icon']."\" alt=\"".$WEATHER[0]['condition']."\" />\n";
	echo "</font></td><td>";

	for($i=1; $i<5; $i++)
	{
		echo "<b><font $fontcolor3>".$WEATHER[$i]['weekday']."</b><br/>\n";
		echo $WEATHER[$i]['condition']."<br/>\n";
		echo "min. ".$WEATHER[$i]['low']."&deg; max. ".$WEATHER[$i]['high']."&deg;<br/>\n";
		echo "<img src=\"http://www.google.com/ig/images/weather".$WEATHER[$i]['icon']."\" alt=\"".$WEATHER[$i]['condition']."\" />\n";
		echo "</font></td><td>";
	}

	echo "</font></td></tr></table></td></tr>";

    }
?>

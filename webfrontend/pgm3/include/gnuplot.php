<?php

################# Creates automatically gnuplot-graphics for pgm3
# Thanks to Rudi for his inspiration to automate gnuplot
# (look at his fhzweb.pl in pgm2)
################


function drawgnuplot($gnudraw,$gnutyp,$gnuplot,$pictype,$logpath,$FHTyrange,$FHTy2range,$DBUse)
{

	if ($gnutyp=="userdef")
	{
		$userdef=$FHTyrange; # workaround
		$userdefnr=$FHTy2range; # workaround
		
		
		$gnuplottype= $userdef['gnuplottype'];
		$logfile= $userdef['logpath'];
        	$drawuserdef=$userdef['name'];
        	$SemanticLong=$userdef['semlong'];
        	$SemanticShort=$userdef['semshort'];
		$valuefield=$userdef['valuefield'];
        	$type='UserDef '.$userdefnr;
		$IN="$gnudraw ($gnutyp $userdefnr)";
		if ($gnuplottype=='piri') $gnutyp='piri';
		if ($gnuplottype=='fs20') $gnutyp='FS20';
		
	}	
	else
	{
	$logfile=$logpath."/".$gnudraw.".log";
	$IN="$gnudraw ($gnutyp)";

	}


### DBUse for
	if ($DBUse == '1' and ( $gnutyp=='FHT' or $gnutyp=='HMS100T' or $gnutyp=='HMS100TF' or $gnutyp=='CUL_WS' or $gnutyp=='KS300_t1' or $gnutyp=='KS300_t2' or $gnutyp=='WS300_t1' or $gnutyp=='WS300_t2'))
	{
	include "config.php";
	$logfile="tmp/".$gnudraw.".log";
	$f1=fopen($logfile,"w+");
	};




	$gnudraw1=$gnudraw.'1';
	$OUT1="set output 'tmp/$gnudraw.$pictype'";
	$OUT2="set output 'tmp/$gnudraw1.$pictype'";

$gplothdr="
	set terminal $pictype crop
	set xdata time 
	set timefmt '%Y-%m-%d_%H:%M:%S' 
	set xlabel ' ' 
	set ytics nomirror 
	set y2tics
	set title '$IN'
	set grid
	";


$datumtomorrow= mktime (0,0,0,date("m")  ,date("d")+1,date("Y"));
$xrange1= date ("Y-m-d",$datumtomorrow);
$datumyesterday= mktime (0,0,0,date("m")  ,date("d")-1,date("Y"));
$datumweek= mktime (0,0,0,date("m")  ,date("d")-6,date("Y"));
$xrange2= date ("Y-m-d",$datumyesterday);
$xrange3= date ("Y-m-d",$datumweek);
$xrange="set xrange ['$xrange2':'$xrange1'] ";
$xrangeweek="set xrange ['$xrange3':'$xrange1'] ";






switch ($gnutyp):
        Case FS20:  ############################################
$gplotmain=<<<EOD

set size 1,0.5
set noytics 
set noy2tics 
set yrange [-0.2:1.2]
set ylabel "On/Off"  
plot "< awk '{print $1, $3==\"on\"? 1 : $3==\"dimup\"? 1 : $3==\"dimdown\"? 0 : $3==\"off\"? 0 : 0.5;}' $logfile" using 1:2 title '' with steps
EOD;

break;






        Case WS300_t1:  ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' and reading='data' order by timestamp  desc limit ".$logrotateKS300lines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->value\n");
      		}
		fclose($f1);
		}
		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2,\
     		'$logfile' using 1:6 axes x1y2 title 'Rel. Humidity (%)' with lines
		";
		break;






        Case WS300_t2:  ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' and reading='data' order by timestamp  desc limit ".$logrotateKS300lines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->value\n");
      		}
		fclose($f1);
		}
$gplotmain=<<<EOD
set ylabel "Air Pressure (hPa)"
set y2label "Willi"
plot "< grep -v avg $logfile" using 1:8 axes x1y1 title 'Air Pressure' with lines, \
"< grep -v avg $logfile" using 1:10 axes x1y2 title 'Willi' with lines
EOD;
		break;






        Case KS300_t1:  ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' and reading='data' order by timestamp  desc limit ".$logrotateKS300lines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->value\n");
      		}
		fclose($f1);
		}
		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2,\
     		'$logfile' using 1:6 axes x1y2 title 'Rel. Humidity (%)' with lines
		";
		break;





        Case KS300_t2:  ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' and reading='data' order by timestamp  desc limit ".$logrotateKS300lines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->value\n");
     		}
		fclose($f1);
		}
	$gplotmain="
	set ylabel 'Wind (Km/h)'
	set y2label 'Rain (l/m2)'
	plot '$logfile' using 1:8 axes x1y1 title 'Wind' with lines, \
	'$logfile' using 1:10 axes x1y2 title 'Rain' with lines
	";
		break;





        Case FHT:   ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' order by timestamp  desc limit ".$logrotateFHTlines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->reading $row->value\n");
      		}
		fclose($f1);
		}


		$gplotmain="
		set ylabel 'Temperature (Celsius)'  
		set yrange [$FHTyrange]
		set grid ytics
		set y2label 'Actuator (%)'
		set y2range [$FHTy2range]
		";
		$gplotmain2="
		set ylabel 'Temperature (Celsius)'  
		set grid ytics
		";
		$gplotmaintmp = <<<EOD

plot "< awk '/measured/{print $1, $4}' $logfile"\
using 1:2 axes x1y1 title 'Measured temperature' with lines lw 2,\
"< awk '/actuator/{print $1, $4+0}'  $logfile"\
using 1:2 axes x1y2 title 'Actuator (%)' with steps lw 1,\
"< awk '/desired/{print $1, $4}'  $logfile"\
using 1:2 axes x1y1 title 'Desired temperature' with steps
EOD;
		
$gplotmainonlymeasured = <<<EOD

plot "< awk '/measured/{print $1, $4}' $logfile"\
using 1:2 axes x1y1 title 'Measured temperature' with lines lw 2
EOD;
		$gplotmain=$gplotmain.$gplotmaintmp;
		$gplotmain2=$gplotmain2.$gplotmainonlymeasured;
		break;

        Case HMS100T:  ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' and reading='data' and type='HMS' order by timestamp  desc limit ".$logrotateHMSlines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->value\n");
      		}
		fclose($f1);
		}
		$gplotmain="
		set ylabel 'Temperature (Celsius)'  
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2
		";
		break;

        Case userdef:  ############################################
$gplotmain=<<<EOD
\n set ylabel '$SemanticLong ( $SemanticShort )'  
set size 1,0.5
set noy2tics 
plot "$logfile" using 1:$valuefield axes x1y1 title '$SemanticLong' with lines lw 2
EOD;
		break;
        Case piri:  ############################################
$gplotmain=<<<EOD
\n set ylabel '$drawuserdef'  
set noytics
set noy2tics
set size 1,0.5
set yrange [-1.2:2.2]
plot "< awk '{print $1, 1; }' $logfile "\
        using 1:2 title '$drawuserdef' with impulses

plot "$logfile" using 1:$valuefield axes x1y1 title '$SemanticLong' with lines lw 2
EOD;
		break;

        Case HMS100TF:  ############################################
        Case CUL_WS:  ############################################
		if ($DBUse==1)
		{
		$sqlarray=mysql_query("select timestamp,reading,value from history where device='".$gnudraw."' and reading='data' and (type='HMS' or type='CUL_WS') order by timestamp  desc limit ".$logrotateHMSlines."") 		or die (mysql_error());
	while ($row = mysql_fetch_object($sqlarray)) {
		$date=str_replace(" ","_",$row->timestamp);
		fputs($f1,"$date $gnudraw $row->value\n");
      		}
		fclose($f1);
		}

		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2,\
		'$logfile' using 1:6 axes x1y2 title 'Rel. Humidity (%)' with lines 
		";
		break;
	default:
endswitch;	




$message=$OUT1.$gplothdr.$xrangeweek.$gplotmain;
$f3=fopen("tmp/gnu1","w+");
fputs($f3,$message);
fclose($f3);
exec("$gnuplot tmp/gnu1",$output);

$message=$OUT2.$gplothdr.$xrange.$gplotmain;
$f2=fopen("tmp/gnu2","w");
fputs($f2,$message);
fclose($f2);
exec("$gnuplot tmp/gnu2",$output);
$FOUT='tmp/'.$gnudraw1.'.'.$pictype;
$FS=filesize($FOUT);
	if (($FS == '0') and ($gnutyp != "userdef"))  ##Grafic mistake (e.G. no actuator). Draw againg without actuator
	{
		$message=$OUT1.$gplothdr.$gplotmain2;
		$f1=fopen("tmp/gnu1","w");
		fputs($f1,$message);
		fclose($f1);
		exec("$gnuplot tmp/gnu1",$output);
		$message=$OUT2.$gplothdr.$xrange.$gplotmain2;
		$f2=fopen("tmp/gnu2","w");
		fputs($f2,$message);
		fclose($f2);
		exec("$gnuplot tmp/gnu2",$output);

	}


};

?>

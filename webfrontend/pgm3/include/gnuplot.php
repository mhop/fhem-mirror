<?php

################# Creates automatically gnuplot-graphics for pgm3
# Thanks to Rudi for his inspiration to automate gnuplot
# (look at his fhzweb.pl in pgm2)
################


function drawgnuplot($gnudraw,$gnutyp,$gnuplot,$pictype,$logpath)
{

	$IN="$gnudraw ($gnutyp)";
	$logfile=$logpath."/".$gnudraw.".log";
	$gnudraw1=$gnudraw.'1';
	$OUT1="set output 'tmp/$gnudraw.$pictype'";
	$OUT2="set output 'tmp/$gnudraw1.$pictype'";

$gplothdr="
	set terminal $pictype 
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
$xrange2= date ("Y-m-d",$datumyesterday);
$xrange="set xrange ['$xrange2':'$xrange1']
	";


switch ($gnutyp):
        Case KS300_t1:  ############################################
		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 3,\
     		'$logfile' using 1:6 axes x1y2 title 'Rel. Humidity (%)' with lines
		";
		break;

        Case KS300_t2:  ############################################
$gplotmain=<<<EOD
set ylabel "Wind (Km/h)"
set y2label "Rain (l/m2)"
plot "< grep -v avg $logfile" using 1:8 axes x1y1 title 'Wind' with lines, \
"< grep -v avg $logfile" using 1:10 axes x1y2 title 'Rain' with lines
EOD;
		break;

        Case FHT:   ############################################
		$gplotmain="
		set ylabel 'Temperature (Celsius)'  
		set yrange [15:31]
		set grid ytics
		set y2label 'Actuator (%)'
		set y2range [0:70]
		";
		$gplotmaintmp = <<<EOD

plot "< awk '/measured/{print $1, $4}' $logfile"\
using 1:2 axes x1y1 title 'Measured temperature' with lines lw 3,\
"< awk '/actuator/{print $1, $4+0}'  $logfile"\
using 1:2 axes x1y2 title 'Actuator (%)' with steps lw 1,\
"< awk '/desired/{print $1, $4}'  $logfile"\
using 1:2 axes x1y1 title 'Desired temperature' with steps
EOD;
		$gplotmain=$gplotmain.$gplotmaintmp;
		break;

        Case HMS100T:  ############################################
		$gplotmain="
		set ylabel 'Temperature (Celsius)'  
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 3
		";
		break;

        Case HMS100TF:  ############################################
		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2,\
		'$logfile' using 1:6 axes x1y2 title 'Rel. Humidity (%)' with lines 
		";
		break;
	default:
endswitch;	


$message=$OUT1.$gplothdr.$gplotmain;
$f1=fopen("tmp/gnu1","w");
fputs($f1,$message);
fclose($f1);
exec("$gnuplot tmp/gnu1",$output);

$message=$OUT2.$gplothdr.$xrange.$gplotmain;
$f2=fopen("tmp/gnu2","w");
fputs($f2,$message);
fclose($f2);
exec("$gnuplot tmp/gnu2",$output);


};

?>

<?php

################# Creates automatically gnuplot-graphics for pgm3
# Thanks to Rudi for his inspiration to automate gnuplot
# (look at his fhzweb.pl in pgm2)
################


function drawgnuplot($gnudraw,$gnutyp,$gnuplot,$pictype,$logpath,$FHTyrange,$FHTy2range)
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
        Case FS20:  ############################################
$gplotmain=<<<EOD
set size 1,0.5
set noytics 
set noy2tics 
set yrange [-0.2:1.2]
set ylabel "On/Off"  
plot "< awk '{print $1, $3==\"on\"? 1 : $3==\"dimup\"? 1 : $3==\"dimdown\"? 0 : $3==\"off\"? 0 : 0.5;}' $logfile" using 1:2 title '' with steps
EOD;
#plot "< awk '{print $1, $3==\"on\"? 1 : $3==\"dimup\"? 0.8 : $3==\"dimdown\"? 0.2 : $3==\"off\"? 0 : 0.5;}' $logfile" using 1:2 title '' with steps
break;

        Case WS300_t1:  ############################################
		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2,\
     		'$logfile' using 1:6 axes x1y2 title 'Rel. Humidity (%)' with lines
		";
		break;

        Case WS300_t2:  ############################################
$gplotmain=<<<EOD
set ylabel "Air Pressure (hPa)"
set y2label "Willi"
plot "< grep -v avg $logfile" using 1:8 axes x1y1 title 'Air Pressure' with lines, \
"< grep -v avg $logfile" using 1:10 axes x1y2 title 'Willi' with lines
EOD;
		break;

        Case KS300_t1:  ############################################
		$gplotmain="
		set ylabel 'Temperature (Celsius)'
		set y2label 'Humidity (%)'
		plot '$logfile' using 1:4 axes x1y1 title 'Temperature' with lines lw 2,\
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
$f1=fopen("tmp/gnu1","w+");
fputs($f1,$message);
fclose($f1);
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

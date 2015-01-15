# $Id: 57_CALVIEW.pm 7006 2015-01-13 20:15:00Z chris1284 $
###########################
#	CALVIEW
#	
#	needs a defined Device 57_Calendar
###########################
package main;

use strict;
use warnings;
use POSIX;

sub CALVIEW_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}   = "CALVIEW_Define";	
	$hash->{UndefFn} = "CALVIEW_Undef";	
	$hash->{SetFn}   = "CALVIEW_Set";		
	$hash->{AttrList} = "do_not_notify:1,0 " . 
						"maxreadings " .
						"oldStyledReadings:1,0 " .						
						$readingFnAttributes; 
}
sub CALVIEW_Define($$){
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );
	return "\"set CALVIEW\" needs at least an argument" if ( @a < 2 );
	my $name 		= $a[0];   
	my $calender	= $a[2];		
	my $inter	= 43200; 
	my $modes = $a[3];
	return "invalid Calendername \"$calender\", define it first" if((devspec2array("NAME=$calender")) != 1 );
	$hash->{NAME} 	= $name;
	$hash->{KALENDER} 	= $calender;
	$hash->{STATE}	= "Initialized";
	$hash->{INTERVAL} = $inter;
	if($modes == 1)	{$hash->{MODES} = "modeStarted;modeUpcoming";	}
	elsif($modes == 0){$hash->{MODES} = "modeStarted";}
	elsif($modes == 2){$hash->{MODES} = "all";	}
	InternalTimer(gettimeofday()+2, "CALVIEW_GetUpdate", $hash, 0);
	return undef;
}
sub CALVIEW_Undef($$){
	my ( $hash, $arg ) = @_;
	#DevIo_CloseDev($hash);			         
	RemoveInternalTimer($hash);    
	return undef;                  
}
sub CALVIEW_Set($@){
	my ( $hash, @a ) = @_;
	return "\"set CALVIEW\" needs at least an argument" if ( @a < 2 );
    return "\"set CALVIEW\" Unknown argument $a[1], choose one of update interval" if($a[1] eq '?'); 
	my $name = shift @a;
	my $opt = shift @a;
	my $arg = join("", @a);
	if($opt eq "update"){CALVIEW_GetUpdate($hash);}
	if($opt eq "interval"){
		if(defined $arg && $arg =~ /^[+-]?\d+$/)
		{$hash->{INTERVAL} = $arg;}
	}
}
sub CALVIEW_GetUpdate($){	
	my ($hash) = @_;
	my $calendername = $hash->{KALENDER};
	my $name = $hash->{NAME};
	#cleanup readings
	delete ($hash->{READINGS});
	# new timer
	InternalTimer(gettimeofday()+$hash->{INTERVAL}, "CALVIEW_GetUpdate", $hash, 1);
	readingsBeginUpdate($hash); #start update
	my @termine =  getsummery($hash);
	my $max = AttrVal($name,"maxreadings",0);
	if(defined $max && $max =~ /^[+-]?\d+$/){if($max > 190){$max = 190;}}
	else{my $max = 190;}
	my $counter = 1;
	my $samedatecounter = 2;
	my $lastterm;
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
    $year += 1900; $mon += 1; my $nextday= $mday + 1;
    if($nextday < 10){$nextday = "0$nextday";}
	if($mday < 10){$mday = "0$mday";}
    if($mon < 10){$mon = "0$mon";}
	my $date = "$mday.$mon.$year";
	my $datenext = "$nextday.$mon.$year";
	my @termineNew;
	foreach my $item (@termine ){
		my @tempstart=split(/\s+/,$item->[0]);
		my @tempend=split(/\s+/,$item->[2]);
		push @termineNew,{
			bdate => $tempstart[0],
			btime => $tempstart[1],
			summary => $item->[1],
			edate => $tempend[0],
			etime => $tempend[1]};}
	#my $termin= \@termineNew;
	my $todaycounter = 1;
	my $tomorrowcounter = 1;
	my $readingstyle = AttrVal($name,"oldStyledReadings",0);	
	# sort the data in the array by bdate 
	my @sdata = map  $_->[0], 
			sort { $a->[1][2] <=> $b->[1][2] or  # year
                   $a->[1][1] <=> $b->[1][1] or  # month
                   $a->[1][0] <=> $b->[1][0] }   # day
            map  [$_, [split /\./, $_->{bdate}]], @termineNew;
	if($readingstyle == 0){		
		for my $termin (@sdata){	#termin als reading term_[3steliger counter]
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_bdate", $termin->{bdate});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_btime", $termin->{btime});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_summary", $termin->{summary});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_edate", $termin->{edate});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_etime", $termin->{etime});
			last if ($counter++ == $max);
		};
		for my $termin (@sdata){	#check ob temin heute
			if ($date eq $termin->{bdate}){
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_bdate", "heute"); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_btime", $termin->{btime}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_summary", $termin->{summary}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_edate", $termin->{edate}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_etime", $termin->{etime}); 
				$todaycounter ++;}
			#check ob termin morgen
			elsif ($datenext eq $termin->{bdate}){
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_btime", "morgen"); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_btime", $termin->{btime}); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_summary", $termin->{summary}); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_edate", $termin->{edate}); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_etime", $termin->{etime}); 
				$tomorrowcounter++;}
		};
		readingsBulkUpdate($hash, "state", "t: ".($counter-1)." td: ".($todaycounter-1)." tm: ".($tomorrowcounter-1)); 
		readingsBulkUpdate($hash, "c-term", $counter-1); 
		readingsBulkUpdate($hash, "c-tomorrow", $tomorrowcounter-1); 
		readingsBulkUpdate($hash, "c-today", $todaycounter-1); 
	}
	else{
		my $lastreadingname = "";
		my $doppelcounter = 2;
		my $inverteddate;
		for my $termin (@sdata){	#termin als reading term_[3steliger counter]
			my @tempvar = split /\./, $termin->{bdate};
			$inverteddate = "$tempvar[2].$tempvar[1].$tempvar[0]";
			if($lastreadingname eq $termin->{bdate}."-".$termin->{btime}){ readingsBulkUpdate($hash, $inverteddate."-".$termin->{btime}."-$doppelcounter" , $termin->{summary}); $doppelcounter ++;}
			else{readingsBulkUpdate($hash, $inverteddate."-".$termin->{btime} , $termin->{summary}); $doppelcounter = 2;}
			$lastreadingname = $termin->{bdate}."-".$termin->{btime};
			last if ($counter++ == $max);
		};
		for my $termin (@sdata){	#check ob temin heute
			if ($date eq $termin->{bdate}){readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter).$termin->{btime}, $termin->{summary});$todaycounter ++;}
			#check ob termin morgen
			elsif ($datenext eq $termin->{bdate}){readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter).$termin->{btime}, $termin->{summary});$tomorrowcounter++;}
		};
	}
	readingsEndUpdate($hash,1); #end update
}
sub getsummery($)
{
	my ($hash) = @_;
	my @terminliste ;
	my $name = $hash->{NAME};
	my $calendername  = $hash->{KALENDER};
	my $modi = $hash->{MODES};
	my @modes = split(/;/,$modi);
	foreach my $mode (@modes){
		my $all = ReadingsVal($calendername, $mode, "");
		my @uids=split(/;/,$all);
		foreach my $uid (@uids){
			my $terminstart = CallFn($calendername, "GetFn", $defs{$calendername},(" ","start", $uid));
			my $termintext = CallFn($calendername, "GetFn", $defs{$calendername}, (" ","summary", $uid));
			my $terminend = CallFn($calendername, "GetFn", $defs{$calendername}, (" ","end", $uid));
			push(@terminliste, [$terminstart, $termintext, $terminend]);
		};
	};
	return @terminliste;
}
1;
=pod
=begin html

<a name="CALVIEW"></a>
<h3>CALVIEW</h3>
<ul>This module creates a device with deadlines based on a calendar-device of the 57_Calendar.pm module.</ul>
<b>Define</b>
<ul><code>define &lt;Name&gt; CALVIEW &lt;calendarname&gt; &lt;0 for modeStarted Termine; 1 for modeStarted;modeUpcoming Termine&gt;</code></ul><br>
<ul><code>define myView CALVIEW Googlecalendar 1</code></ul><br>
<a name="CALVIEW set"></a>
<b>Set</b>
<ul>update readings:</ul>
<ul><code>set &lt;Name&gt; update</code></ul>
<ul><code>set myView update</code></ul><br>
<ul>set updateintervall:</ul>
<ul><code>set &lt;Name&gt; intervall &lt;[time]&gt;</code></ul>
<ul><code>set myView intervall 300</code></ul><br>
<b>Attribute</b>
<li>maxreadings<br>
        defines the number of max term as readings
</li><br>
<li>oldStyledReadings<br>
		1 readings look like "2015.06.21-00:00" with value "Start of Summer"
		0 the default style of readings
</li><br>
=end html

=begin html_DE

<a name="CALVIEW"></a>
<h3>CALVIEW</h3>
<ul>Dieses Modul erstellt ein Device welches als Readings Termine eines Kalenders, basierend auf dem 57_Calendar.pm Modul, besitzt.</ul>
<b>Define</b>
<ul><code>define &lt;Name&gt; CALVIEW &lt;Kalendername&gt; &lt;0 für modeStarted Termine; 1 für modeStarted;modeUpcoming Termine&gt;</code></ul><br>
<ul><code>define myView CALVIEW Googlekalender 1</code></ul><br>
<a name="CALVIEW set"></a>
<b>Set</b>
<ul>update readings:</ul>
<ul><code>set &lt;Name&gt; update</code></ul>
<ul><code>set myView update</code></ul><br>
<ul>set updateintervall:</ul>
<ul><code>set &lt;Name&gt; intervall &lt;[Zeit]&gt;</code></ul>
<ul><code>set myView intervall 300</code></ul><br>
<b>Attributes</b>
<li>maxreadings<br>
        bestimmt die Anzahl der Termine als Readings
</li><br>
<li>oldStyledReadings<br>
		1 aktiviert die Termindarstellung im "alten" Format "2015.06.21-00:00" mit Wert "Start of Summer"
		0 aktivert die Standarddarstellung bdate, btime, usw 
</li><br>
=end html_DE
=cut
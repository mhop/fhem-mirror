# $Id$
############################
#	CALVIEW
#	needs a defined Device 57_Calendar
#   needs perl-modul Date::Parse
############################
package main;

use strict;
use warnings;
use POSIX;
use Date::Parse;

sub CALVIEW_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}   = "CALVIEW_Define";	
	$hash->{UndefFn} = "CALVIEW_Undef";	
	$hash->{SetFn}   = "CALVIEW_Set";
	$hash->{NotifyFn}	= "CALVIEW_Notify";	
	$hash->{AttrList} = "disable:0,1 " .
						"do_not_notify:1,0 " .
						"isbirthday:1,0 " .						
						"maxreadings " .
						"modes:next ".
						"oldStyledReadings:1,0 " .
						"yobfield:_location,_description " .
						$readingFnAttributes; 
}
sub CALVIEW_Define($$){
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );
	return "\"set CALVIEW\" needs at least an argument" if ( @a < 2 );
	my $name = $a[0];   
	my $inter = 43200; 
	$inter= $a[4] if($#a==4);
	my $modes = $a[3];
	my @calendars = split( ",", $a[2] );
	$hash->{NAME} 	= $name;
	my $calcounter = 1;
	foreach my $calender (@calendars)
	{
		return "invalid Calendername \"$calender\", define it first" if((devspec2array("NAME=$calender")) != 1 );	
	}
	$hash->{KALENDER} 	= $a[2];
	$hash->{STATE}	= "Initialized";
	$hash->{INTERVAL} = $inter;
	$modes = "next" if (!defined($modes));
	if ( $modes =~ /^\d+$/) {
		if($modes == 1)	{$attr{$name}{modes} = "next";}
		elsif($modes == 0){$attr{$name}{modes} = "next";}
		elsif($modes == 2){$attr{$name}{modes} = "next";}
		elsif($modes == 3){$attr{$name}{modes} = "next";}
	}
	elsif($modes eq "next"){$attr{$name}{modes} = "next";}
	else {return "invalid mode \"$modes\", use 0,1,2 or next!"}
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
    return "\"set CALVIEW\" Unknown argument $a[1], choose one of update" if($a[1] eq '?'); 
	my $name = shift @a;
	my $opt = shift @a;
	my $arg = join("", @a);
	if($opt eq "update"){CALVIEW_GetUpdate($hash);}
}
sub CALVIEW_GetUpdate($){	
	my ($hash) = @_;
	my $name = $hash->{NAME};
	#cleanup readings
	delete ($hash->{READINGS});
	# new timer
	RemoveInternalTimer($hash); 
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
	$year += 1900; $mon += 1; 	
	my $date = sprintf('%02d.%02d.%04d', $mday, $mon, $year);
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time + 86400);
	$year += 1900; $mon += 1; 		
	my $datenext = sprintf('%02d.%02d.%04d', $mday, $mon, $year);
	my @termineNew;
	foreach my $item (@termine ){
		my @tempstart=split(/\s+/,$item->[0]);
		my @tempend=split(/\s+/,$item->[2]);
		my ($D,$M,$Y)=split(/\./,$tempstart[0]);
		my @bts=str2time($M."/".$D."/".$Y." ".$tempstart[1]);
		#replace the "\," with ","
		if(length($item->[1]) > 0){ $item->[1] =~ s/\\,/,/g; }
		if( defined($item->[4]) && length($item->[4]) > 0){ $item->[4] =~ s/\\,/,/g; }
		if( defined($item->[5]) && length($item->[5]) > 0){ $item->[5] =~ s/\\,/,/g; }
		push @termineNew,{
			bdate => $tempstart[0],
			btime => $tempstart[1],
			summary => $item->[1],
			source => $item->[3],
			location => $item->[4],
			description => $item->[5],
			edate => $tempend[0],
			etime => $tempend[1],
			btimestamp => $bts[0],
			mode => $item->[6]};	
	}
	my $todaycounter = 1;
	my $tomorrowcounter = 1;
	my $readingstyle = AttrVal($name,"oldStyledReadings",0);	
	my $isbday = AttrVal($name,"isbirthday",0);	
	my $yobfield = AttrVal($name,"yobfield","_description");
	# sort the array by btimestamp
	my @sdata = map  $_->[0], 
			sort { $a->[1][0] <=> $b->[1][0] }
			map  [$_, [$_->{btimestamp}]], @termineNew;
			
	if($readingstyle == 0){
		my $age = 0;
		my @termyear;
		for my $termin (@sdata){	
			#alter berechnen wenn attribut gesetzt ist. alter wird aus "jahr des termins" - "geburtsjahr aus location oder description" errechnet
			if($isbday == 1 ){
				@termyear = split(/\./,$termin->{bdate});
				if($yobfield eq "_location" && length($termin->{location}) > 0 && $termin->{location}=~ /^\d+$/ ) { $age = $termyear[2] - ($termin->{location});}
				elsif($yobfield eq "_description" && length($termin->{description}) > 0 && $termin->{description}=~ /^\d+$/) { $age = $termyear[2] - ($termin->{description});}
				else {$age = "no calculation passible"}
			}
			#standard reading t_[3steliger counter] anlegen
			if($isbday == 1 ){ readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_age", $age);}
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_bdate", $termin->{bdate});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_btime", $termin->{btime});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_summary", $termin->{summary});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_source", $termin->{source});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_location", $termin->{location});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_description", $termin->{description});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_edate", $termin->{edate});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_etime", $termin->{etime});
			readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_mode", $termin->{mode}); 
			#wenn termin heute today readings anlegen
			if ($date eq $termin->{bdate} ){
				if($isbday == 1 ){ readingsBulkUpdate($hash, "today_".sprintf ('%03d', $counter)."_age", $age);}
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_bdate", "heute"); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_btime", $termin->{btime}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_summary", $termin->{summary}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_source", $termin->{source}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_location", $termin->{location});
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_description", $termin->{description});
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_edate", $termin->{edate}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_etime", $termin->{etime}); 
				readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_mode", $termin->{mode});
				$todaycounter ++;
			}
			#wenn termin morgen tomorrow readings anlegen
			elsif ($datenext eq $termin->{bdate}){
				if($isbday == 1 ){readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $counter)."_age", $age);}
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_bdate", "morgen"); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_btime", $termin->{btime}); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_summary", $termin->{summary}); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_source", $termin->{source});
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_location", $termin->{location});
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_description", $termin->{description});
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_edate", $termin->{edate}); 
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_etime", $termin->{etime});
				readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_mode", $termin->{mode});
				$tomorrowcounter++;
			}			
			last if ($counter++ == $max);
		};
		for my $termin (@sdata){	
			#check ob temin heute

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
	my @calendernamen = split( ",", $hash->{KALENDER}); 
	my $modi = $attr{$name}{modes};
	my @modes = split(/,/,$modi);
	foreach my $calendername (@calendernamen){
			my $all = CallFn($calendername, "GetFn", $defs{$calendername},(" ","uid", "next"));
			my @termine=split(/\n/,$all);
			
			foreach my $uid (@termine){
				#für jedes event die einzelnen infos holen
				my $tmpstarts = CallFn($calendername, "GetFn", $defs{$calendername},(" ","start", $uid));
				my @starts  = split(/\n/,$tmpstarts);
				my $tmpends = CallFn($calendername, "GetFn", $defs{$calendername},(" ","end", $uid));
				my @ends  = split(/\n/,$tmpends);
				my $tmpsummarys = CallFn($calendername, "GetFn", $defs{$calendername},(" ","summary", $uid));
				my @summarys  = split(/\n/,$tmpsummarys);
				my $tmplocations = CallFn($calendername, "GetFn", $defs{$calendername},(" ","location", $uid));
				my @locations = split(/\n/,$tmplocations);				
				my $tmpdescriptions = CallFn($calendername, "GetFn", $defs{$calendername},(" ","description", $uid));
				my @description = split(/\n/,$tmpdescriptions);
				
				for(my $i = 1; $i <= (scalar(@starts)); $i++) {
					my $internali = $i-1;
					my $terminstart = $starts[$internali];
					my $termintext = $summarys[$internali];
					my $terminend = $ends[$internali];
					my $terminort = $locations[$internali];
					my $termindescription = $description[$internali];
					push(@terminliste, [$terminstart, $termintext, $terminend, $calendername, $terminort, $termindescription, "next"]);
				}
			};
	};
	return @terminliste;
}

sub CALVIEW_Notify($$)
{
	my ($hash, $extDevHash) = @_;
	my $name = $hash->{NAME}; # name calview device
	my $extDevName = $extDevHash->{NAME}; # name externes device 
	my @calendernams = split( ",", $hash->{KALENDER}); 
	my $event;
	return "" if(IsDisabled($name)); # wenn attr disabled keine reaktion	
	foreach my $calendar (@calendernams){
		if ($extDevName eq $calendar) {
			foreach $event (@{$extDevHash->{CHANGED}}) {
				if ($event eq "triggered") { 
					Log3 $name , 3,  "CALVIEW $name - CALENDAR:$extDevName triggered, updating CALVIEW $name ...";
					CALVIEW_GetUpdate($hash); 
				}
			}
		}
	}
}

1;
=pod
=item device
=item summary provides calendar events in a readable form
=begin html

<a name="CALVIEW"></a>
<h3>CALVIEW</h3>
<ul>This module creates a device with deadlines based on calendar-devices of the 57_Calendar.pm module. You need to install the  perl-modul Date::Parse!</ul>
<ul>Actually the module supports only the "get <> next" function of the CALENDAR-Modul.</ul>
<b>Define</b>
<ul><code>define &lt;Name&gt; CALVIEW &lt;calendarname(s) separate with ','&gt; &lt;next&gt; &lt;updateintervall in sec (default 43200)&gt;</code></ul>
<ul><code>define myView CALVIEW Googlecalendar next</code></ul>
<ul><code>define myView CALVIEW Googlecalendar,holiday next 900</code></ul>
<ul>- setting the update interval is not needed normally because every calendar update triggers a caview update</ul>
<a name="CALVIEW set"></a>
<b>Set</b>
<ul><code>set &lt;Name&gt; update</code></ul>
<ul><code>set myView update</code></ul>
<ul>this will manually update all readings from the given CALENDAR Devices</ul>
<b>Attribute</b>
<li>disable<br>
        0 / not set - internal notify function enabled (default) <br>
		1 - disable the internal notify-function of CALVIEW wich is triggered when one of the given CALENDAR devices has updated
</li><br>
<li>isbirthday<br>
        0 / not set - no age calculation (default)  <br>
		1 - age calculation active. The module calculates the age with year given in description or location (see att yobfield).
</li><br>
<li>maxreadings<br>
        defines the number of max term as readings
</li><br>
<li>modes<br>
		here the CALENDAR modes can be selected , to be displayed in the view
</li><br>
<li>oldStyledReadings<br>
		0 the default style of readings <br>
		1 readings look like "2015.06.21-00:00" with value "Start of Summer" 
</li><br>
<li>yobfield<br>
		_description  - (default) year of birth will be read from term description <br>
		_location - year of birth will be read from term location 
</li><br>
=end html

=begin html_DE

<a name="CALVIEW"></a>
<h3>CALVIEW</h3>
<ul>Dieses Modul erstellt ein Device welches als Readings Termine eines oder mehrere Kalender(s), basierend auf dem 57_Calendar.pm Modul, besitzt. Ihr müsst das Perl-Modul Date::Parse installieren!</ul>
<ul>Aktuell wird nur die "get <> next" Funktion vom CALENDAR untertstützt.</ul>
<b>Define</b>
<ul><code>define &lt;Name&gt; CALVIEW &lt;Kalendername(n) getrennt durch ','&gt; &lt;next&gt; &lt;updateintervall in sek (default 43200)&gt;</code></ul>
<ul><code>define myView CALVIEW Googlekalender next</code></ul>
<ul><code>define myView CALVIEW Googlekalender,holiday next 900</code></ul>
<ul>- die Einstellung des Aktualisierungsintervalls wird normalerweise nicht benötigt, da jede Kalenderaktualisierung ein Caview-Update auslöst</ul>
<a name="CALVIEW set"></a>
<b>Set</b>
<ul>update readings:</ul>
<ul><code>set &lt;Name&gt; update</code></ul>
<ul><code>set myView update</code></ul><br>
<b>Attributes</b>
<li>disable<br>
        0 / nicht gesetzt - aktiviert die interne Notify-Funktion (Standard) <br>
		1 - deaktiviert die interne Notify-Funktion welche ausgelöst wird wenn sich einer der Kalender aktualisiert hat
</li><br>
<li>isbirthday<br>
        0 / nicht gesetzt - keine Altersberechnung (Standard) <br>
		1 - aktiviert die Altersberechnung im Modul. Das Alter wird aus der in der Terminbeschreibung (description) angegebenen Jahreszahl (Geburtsjahr) berechnet.
</li><br>
<li>maxreadings<br>
        bestimmt die Anzahl der Termine als Readings
</li><br>
<li>modes<br>
        hier können die CALENDAR modi gewählt werden, welche in der View angezeigt werden sollen
</li><br>
<li>oldStyledReadings<br> 
		0 die Standarddarstellung für Readings <br>
		1 aktiviert die Termindarstellung im "alten" Format "2015.06.21-00:00" mit Wert "Start of Summer"
</li><br>
<li>yobfield<br>
		_description  - (der Standard) Geburtsjahr wird aus der Terminbechreibung gelesen <br>
		_location - Geburtsjahr wird aus dem Terminort gelesen 
</li><br>
=end html_DE
=cut
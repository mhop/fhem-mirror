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
#use Date::Calc qw(Day_of_Week);

sub CALVIEW_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}   = "CALVIEW_Define";	
	$hash->{UndefFn} = "CALVIEW_Undef";	
	$hash->{SetFn}   = "CALVIEW_Set";
	$hash->{NotifyFn}	= "CALVIEW_Notify";	
	$hash->{AttrList} = "datestyle:ISO8601 " .
						"disable:0,1 " .
						"do_not_notify:1,0 " .
						"filterSummary:textField-long " .
						"fulldaytext " .
						"isbirthday:1,0 " .						
						"maxreadings " .
						"modes:next ".
						"oldStyledReadings:1,0 " .
						"sourcecolor:textField-long " .
						"timeshort:1,0 " .
						"yobfield:_location,_description,_summary " .
						"weekdayformat:de-long,de-short,en-long,en-short " .
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
	my @tempstart;
	my @bts;
	my @tempend;
	my $isostarttime;
	my $isoendtime;
	my ($D,$M,$Y);
	my ($eD,$eM,$eY);
	my @arrWeekdayDe = ("Sonntag","Montag", "Dienstag","Mittwoch","Donnerstag","Freitag","Samstag");
	my @arrWeekdayDeShrt = ("So","Mo", "Di","Mi","Do","Fr","Sa");
	my @arrWeekdayEn = ("Sunday","Monday", "Tuesday","Wednesday","Thursday","Friday","Saturday");
	my @arrWeekdayEnShrt = ("Sun","Mon", "Tue","Wed","Thu","Fri","Sat");
	foreach my $item (@termine ){
		#start datum und zeit behandeln
		if( defined($item->[0])&& length($item->[0]) > 0) { 	
			@tempstart=split(/\s+/,$item->[0]);
			($D,$M,$Y)=split(/\./,$tempstart[0]);
			@bts=str2time($M."/".$D."/".$Y." ".$tempstart[1]);
			$isostarttime = $Y."-".$M."-".$D."T".$tempstart[1];
		}
		else {$item->[0] = "no startdate"}
		#end datum und zeit behandeln	
		if( defined($item->[2])&& length($item->[2]) > 0) { 
			@tempend=split(/\s+/,$item->[2]);	
			($eD,$eM,$eY)=split(/\./,$tempend[0]);
			$isoendtime = $eY."-".$eM."-".$eD."T".$tempend[1];
		}
		else {$item->[2] = "no enddate"}
		#replace the "\," with ","
		if(length($item->[1]) > 0){ $item->[1] =~ s/\\,/,/g; }
		if( defined($item->[4]) && length($item->[4]) > 0){ $item->[4] =~ s/\\,/,/g; } elsif( !defined($item->[4])){$item->[4] = " ";} 
		if( defined($item->[5]) && length($item->[5]) > 0){ $item->[5] =~ s/\\,/,/g; } elsif( !defined($item->[5])){$item->[5] = " ";} 
		#berechnen verbleibender tage bis zum termin
		my $eventDate = fhemTimeLocal(0,0,0,$D,$M-1,$Y-1900);
		my $daysleft = floor(($eventDate - time) / 60 / 60 / 24 + 1);
		my $daysleft_long;
		#my $weekday = Day_of_Week($Y, $M, $D);
		my ($tsec,$tmin,$thour,$tmday,$tmon,$year,$weekday,$tyday,$tisdst) = localtime(time + (86400 * $daysleft));
		#"weekdayname:de-long,de-short,en-long,en-short " .
		my $weekdayname;
		if ( AttrVal($name,"weekdayformat","de-long") eq "de-short") {$weekdayname = $arrWeekdayDeShrt[$weekday]}
		elsif (AttrVal($name,"weekdayformat","de-long") eq "en-long") {$weekdayname = $arrWeekdayEn[$weekday]}
		elsif (AttrVal($name,"weekdayformat","de-long") eq "en-short") {$weekdayname = $arrWeekdayEnShrt[$weekday]}
		else {$weekdayname = $arrWeekdayDe[$weekday]}
		
		if( !defined($item->[6])){$item->[6] = " ";}  
		
		if( $daysleft == 0){$daysleft_long = "heute";}
		elsif( $daysleft == 1){$daysleft_long = "morgen";}
		else{$daysleft_long = "in ".$daysleft." Tagen";}
		push @termineNew,{
			bdate => $tempstart[0],
			btime => $tempstart[1],
			bdatetimeiso => $isostarttime,
			daysleft => $daysleft,
			daysleftLong => $daysleft_long,
			summary => $item->[1],
			source => $item->[3],
			location => $item->[4],
			description => $item->[5],
			categories => $item->[6],
			edate => $tempend[0],
			etime => $tempend[1],
			edatetimeiso => $isoendtime,
			btimestamp => $bts[0],
			mode => $item->[7],
			weekday => $weekday,
			weekdayname => $weekdayname,
			duration => $item->[8]};
	}
	my $todaycounter = 1;
	my $tomorrowcounter = 1;
	my $readingstyle = AttrVal($name,"oldStyledReadings",0);	
	my $isbday = AttrVal($name,"isbirthday",0);	
	my $yobfield = AttrVal($name,"yobfield","_description");
	my $filterSummary = AttrVal($name,"filterSummary",".*:.*");
	my @arrFilters = split(',' , $filterSummary );
	my $sourceColor = AttrVal($name,"sourcecolor","");
	my @arrSourceColors = split(',' , $sourceColor );
	
	# sort the array by btimestamp
	my @sdata = map  $_->[0], 
			sort { $a->[1][0] <=> $b->[1][0] }
			map  [$_, [$_->{btimestamp}]], @termineNew;
			
	if($readingstyle == 0){
		my $age = 0;
		my @termyear;
		my $validterm = 0;
	
		for my $termin (@sdata){
			my $termcolor="white";
			#if($termin->{summary} =~ /$filterSummary/ ){
			foreach my $filter (@arrFilters){ 
				my @arrFilter= split(':' , $filter); 
				my $sourceFilter = $arrFilter[0]; 
				my $summaryFilter = $arrFilter[1]; 
				if( $termin->{source} =~ /$sourceFilter/i && $termin->{summary} =~ /$summaryFilter/i ){ $validterm =1;}
			};
			foreach my $color (@arrSourceColors){ 
				my @arrSourceColor = split(':' , $color); 
				my $sourceName = $arrSourceColor[0]; 
				my $sourceColor = $arrSourceColor[1]; 
				if( $termin->{source} =~ /$sourceName/i ){ $termcolor = $sourceColor;}
			};
			if ($validterm ==1){
					#alter berechnen wenn attribut gesetzt ist. alter wird aus "jahr des termins" - "geburtsjahr aus location oder description" errechnet
					if($isbday == 1 ){
						@termyear = split(/\./,$termin->{bdate});
						if($yobfield eq "_location" && defined($termin->{location}) && length($termin->{location}) > 0 && $termin->{location} =~ /(\d{4})/) { my ($byear) = $termin->{location} =~ /(\d{4})/ ; $age = $termyear[2] - $byear;}
						elsif($yobfield eq "_description" && defined($termin->{description})&& length($termin->{description}) > 0 && $termin->{description} =~ /(\d{4})/) { my ($byear) = $termin->{description} =~ /(\d{4})/ ; $age = $termyear[2] - $byear;}
						elsif($yobfield eq "_summary" && defined($termin->{summary}) && length($termin->{summary}) > 0 && $termin->{summary} =~ /(\d{4})/ ) { my ($byear) = $termin->{summary} =~ /(\d{4})/ ; $age = $termyear[2] -  $byear;}
						else {$age = " "}
					}
					my $timeshort = "";
					my($startday,$startmonth,$startyear)=split(/\./,$termin->{bdate});
					my($endday,$endmonth,$endyear)=split(/\./,$termin->{edate});
					my $nextday = $startday + 1;
					$nextday = sprintf ('%02d', $nextday);
					Log3 $name , 5,  "CALVIEW $name - nextday = $nextday , endday = $endday , startday = $startday , btime ".$termin->{btime}." , etime ".$termin->{etime}."";
					#if( $endday eq $nextday && $termin->{btime} eq $termin->{etime} ){ $timeshort = AttrVal($name,"fulldaytext","ganztägig"); }
					if( $termin->{duration} == 86400 ){ $termin->{duration} = AttrVal($name,"fulldaytext","ganztägig");$timeshort = AttrVal($name,"fulldaytext","ganztägig"); }
					else { 
						if(AttrVal($name,"timeshort","0") eq 0) {$timeshort = $termin->{btime}." - ".$termin->{etime}; }
						elsif(AttrVal($name,"timeshort","0") eq 1) {
							my $tmps = substr $termin->{btime},0,5 ;
							my $tmpe = substr $termin->{etime},0,5 ;
							$timeshort = $tmps." - ".$tmpe ; 
						}
					}
					
					#standard reading t_[3steliger counter] anlegen
					if($isbday == 1 ){ readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_age", $age);}
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_bdate", $termin->{bdate});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_btime", $termin->{btime});
					if(AttrVal($name,"datestyle","_description") eq "ISO8601"){readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_bdatetimeiso", $termin->{bdatetimeiso});readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_edatetimeiso", $termin->{edatetimeiso});}
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_daysleft", $termin->{daysleft});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_daysleftLong", $termin->{daysleftLong});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_summary", $termin->{summary});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_source", $termin->{source});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_sourcecolor", $termcolor);
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_location", $termin->{location});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_description", $termin->{description});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_categories", $termin->{categories});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_edate", $termin->{edate});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_etime", $termin->{etime});
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_mode", $termin->{mode}); 
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_timeshort", $timeshort );
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_weekday", $termin->{weekday} );
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_weekdayname", $termin->{weekdayname} );
					readingsBulkUpdate($hash, "t_".sprintf ('%03d', $counter)."_duration", $termin->{duration});
					#wenn termin heute today readings anlegen
					if ($date eq $termin->{bdate} ){
						if($isbday == 1 ){ readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_age", $age);}
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_bdate", "heute"); 
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_btime", $termin->{btime});
						if(AttrVal($name,"datestyle","_description") eq "ISO8601"){readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_bdatetimeiso", $termin->{bdatetimeiso});readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_edatetimiso", $termin->{edatetimeiso});}
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $counter)."_daysleft", $termin->{daysleft});	
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $counter)."_daysleftLong", $termin->{daysleftLong});						
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_summary", $termin->{summary}); 
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_source", $termin->{source}); 
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_sourcecolor", $termcolor); 
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_location", $termin->{location});
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_description", $termin->{description});
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_categories", $termin->{categories});
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_edate", $termin->{edate}); 
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_etime", $termin->{etime}); 
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_mode", $termin->{mode});
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_timeshort", $timeshort );
						readingsBulkUpdate($hash, "today_".sprintf ('%03d', $todaycounter)."_duration", $termin->{duration});
						$todaycounter ++;
					}
					#wenn termin morgen tomorrow readings anlegen
					elsif ($datenext eq $termin->{bdate}){
						if($isbday == 1 ){readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_age", $age);}
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_bdate", "morgen"); 
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_btime", $termin->{btime}); 
						if(AttrVal($name,"datestyle","_description") eq "ISO8601"){readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_bdatetimeiso", $termin->{bdatetimeiso});readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_edatetimeiso", $termin->{edatetimeiso});}
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_daysleft", $termin->{daysleft});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_daysleftLong", $termin->{daysleftLong});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_summary", $termin->{summary}); 
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_source", $termin->{source});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_sourcecolor", $termcolor);
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_location", $termin->{location});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_description", $termin->{description});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_categories", $termin->{categories});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_edate", $termin->{edate}); 
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_etime", $termin->{etime});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_mode", $termin->{mode});
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_timeshort", $timeshort );
						readingsBulkUpdate($hash, "tomorrow_".sprintf ('%03d', $tomorrowcounter)."_duration", $termin->{duration});
						$tomorrowcounter++;
					}
					$endday = '';
					$nextday ='';		
					last if ($counter++ == $max);
				
			}
			$validterm = 0;
			$age = " ";
			
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
			my $all = CallFn($calendername, "GetFn", $defs{$calendername},("-","events","format:custom='\$U|\$T1|\$T2|\$S|\$L|\$DS|\$CA|\$d'"));
			Log3 $name , 5,  "CALVIEW $name - All data: \n$all ...";
			my @termine=split(/\n/,$all);
			foreach my $line (@termine){
				Log3 $name , 5,  "CALVIEW $name - Termin: $line";
				my @lineparts  = split(/\|/,$line);
				#my $terminstart = $lineparts[1];
				#my $terminend = $lineparts[2];
				#my $termintext = $lineparts[3];
				#my $terminort = $lineparts[4];
				#my $termindescription = $lineparts[5];
				#my $termincategories = $lineparts[6];
				#Log3 $name , 5,  "CALVIEW $name - Termin splitted : $terminstart, $termintext, $terminend, $calendername, $terminort, $termindescription, $termincategories";
				push(@terminliste, [$lineparts[1], $lineparts[3], $lineparts[2], $calendername, $lineparts[4], $lineparts[5], $lineparts[6], "next", $lineparts[7]]);
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
					Log3 $name , 5,  "CALVIEW $name - CALENDAR:$extDevName triggered, updating CALVIEW $name (CALVIEW_Notify) ...";
					CALVIEW_GetUpdate($hash); 
					Log3 $name , 5,  "CALVIEW $name - CALENDAR:$extDevName successfully got all updates for CALVIEW $name (CALVIEW_Notify). Now process updates...";
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
<li>datestyle<br>
        not set  - the default, disables displaying readings bdatetimeiso / edatetimeiso<br>
		ISO8601  - enables readings bdatetimeiso / edatetimeiso (start and end time of term ISO8601 formated like 2017-02-27T00:00:00)
</li><br>
<li>disable<br>
        0 / not set - internal notify function enabled (default) <br>
		1 - disable the internal notify-function of CALVIEW wich is triggered when one of the given CALENDAR devices has updated
</li><br>filterSummary
<li>filterSummary &lt;filtersouce&gt;:&lt;filtersummary&gt;[,&lt;filtersouce&gt;:&lt;filtersummary&gt;]<br>
        not set - displays all terms (default .*:.*) <br>
		&lt;filtersouce&gt;:&lt;filtersummary&gt;[,&lt;filtersouce&gt;:&lt;filtersummary&gt;] - CALVIEW will display term where summary matches the &lt;filtersouce&gt;:&lt;filtersummary&gt;, several filters must be separated by comma (,)
		e.g.: 	filterSummary Kalender_Abfall:Leichtverpackungen,Kalender_Abfall:Bioabfall
				filterSummary Kalender_Abfall:Leichtverpackungen,Kalender_Feiertage:.*,Kalender_Christian:.*,Kalender_Geburtstage:.*
</li><br>
<li>fulldaytext [text]<br>
		this text will be displayed in _timeshort reading for fullday terms (default ganztägig)
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
<li>sourcecolor &lt;calendername&gt;:&lt;colorcode&gt;[,&lt;calendername&gt;:&lt;colorcode&gt;]<br>
		here you can define the termcolor for terms from your calendars for the calview tabletui widget, several calendar:color pairs must be separated by comma
</li><br>
<li>timeshort<br>
		0 time in _timeshort readings formated 00:00:00 <br>
		1 time in _timeshort readings formated 00:00  
</li><br>
<li>yobfield<br>
		_description  - (default) year of birth will be read from term description <br>
		_location - year of birth will be read from term location <br>
		_summary - year of birth will be read from summary (uses the first sequence of 4 digits in the string)
</li><br>
<li>weekdayformat<br>
		formats the name of the reading weekdayname <br>
		- de-long - (default) german, long name like Dienstag <br>
		- de-short - german, short name like Di <br>
		- en-long - english, long name like Tuesday <br>
		- en-short - english, short name like Tue <br>
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
<li>datestyle<br>
        nicht gesetzt - Standard, Readings bdatetimeiso / edatetimeiso werden nicht gezeigt<br>
		ISO8601  - aktiviert die readings bdatetimeiso / edatetimeiso (zeigen Terminstart und Ende im ISO8601 Format zB. 2017-02-27T00:00:00)
</li><br>
<li>disable<br>
        0 / nicht gesetzt - aktiviert die interne Notify-Funktion (Standard) <br>
		1 - deaktiviert die interne Notify-Funktion welche ausgelöst wird wenn sich einer der Kalender aktualisiert hat
</li><br>
<li>filterSummary &lt;filtersouce&gt;:&lt;filtersummary&gt;[,&lt;filtersouce&gt;:&lt;filtersummary&gt;]<br>
        not set - zeigt alle Termine (Standard) <br>
		&lt;filtersouce&gt;:&lt;filtersummary&gt;[,&lt;filtersouce&gt;:&lt;filtersummary&gt;] - CALVIEW filtert Termine die &lt;filtersquelle&gt;:&lt;filtertitel&gt; entsprechen, mehrere Filter sind durch Komma (,) zu trennen.
		
		zb.: 	filterSummary Kalender_Abfall:Leichtverpackungen,Kalender_Abfall:Bioabfall
				filterSummary Kalender_Abfall:Leichtverpackungen,Kalender_Feiertage:.*,Kalender_Christian:.*,Kalender_Geburtstage:.*
																	
</li><br>
<li>fulldaytext [text]<br>
		Dieser Text wird bei ganztägigen Terminen in _timeshort Readings genutzt (default ganztägig)
</li><br>
<li>isbirthday<br>
        0 / nicht gesetzt - keine Altersberechnung (Standard) <br>
		1 - aktiviert die Altersberechnung im Modul. Das Alter wird aus der in der Terminbeschreibung (description) angegebenen Jahreszahl (Geburtsjahr) berechnet. (siehe Attribut yobfield)
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
<li>sourcecolor &lt;calendername&gt;:&lt;colorcode&gt;[,&lt;calendername&gt;:&lt;colorcode&gt;]<br>
		Hier kann man die Farben für die einzelnen Calendar definieren die dann zb im Tabletui widget genutzt werden kann.
		Die calendar:color Elemente sind durch Komma zu trennen.
		So kann man zb die google-Kalender Farben auch in der TUI für eine gewohnte Anzeige nutzen.
</li><br>
<li>timeshort<br>
		0 Zeit in _timeshort Readings im Format 00:00:00 - 00:00:00 <br>
		1 Zeit in _timeshort Readings im Format 00:00 - 00:00
</li><br>
<li>yobfield<br>
		_description  - (der Standard) Geburtsjahr wird aus der Terminbechreibung gelesen <br>
		_location - Geburtsjahr wird aus dem Terminort gelesen <br>
		_summary - Geburtsjahr wird aus dem Termintiele gelesen (verwendet wird die erste folge von 4 Ziffern im String))
</li><br>
<li>weekdayformat<br>
		formatiert den Namen im Reading weekdayname <br>
		- de-long - (default) Deutsch, lang zb Dienstag <br>
		- de-short - Deutsch, kurze zb Di <br>
		- en-long - English, lang zb Tuesday <br>
		- en-short - English, kurze zb Tue <br>
</li><br>
=end html_DE
=cut

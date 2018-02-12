################################################################
#
#  Copyright notice
#
#  (c) 2018 Oliver Georgi
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################
# $Id$
#
# 13.12.2017 0.0.2	diverses
#
# 16.12.2017 0.0.3	neuer pass check: else in @ sowie %
#			nicht alle pass keys werden durchlaufen sondern nur die geforderten
#			pass ^()$ ergänzt
#
# 19.12.2017 0.1.0	FHEM-Modul Funktionen eingefügt
#			Attribute T2F_keywordlist und T2F_modwordlist erzeugt
## 30.12.2017 0.2.0	Umgebungssuchen in regexp unterstützt 
#			# Kommentierung ermöglicht
#			Syntaxcheck der Definition
#			Multiple Datumsangaben korrigiert
#			Wochentagsangaben korrigiert 
#			Syntaxvereinfachung
#			Regexp-Listen erweitert
#			Multilingual DE EN
# 02.01.2018 0.2.1	Liste der erase Wörter erweitert
#			problem bei wordlist ergänzung
#			multideviceable
#			Regexp in HASH auswertung
#			Automatische Umlautescaping
# 			komma in wordlists
# 26.01.2018 0.3.2	extra word search && in phrase
#			reihenfolge der DEF wird berücksichtigt
#			FHEM helper hash für globale verwendet
#			Code aufgeräumt
#			including definition files
#			zugriff auf Umgebungsmuster und Zeitphrasen
#			Phraseindikator ? und !
#			$n@ for keylistsaccess added
#			Zahlenwörter in Zeitphrase konvertieren
#			Eventgesteurte Befehle
#			Leerer set parameter löst den letzten befehl nochmal aus
# 10.02.2018 0.4.0	set CLEARTRIGGERS
#			wieder Erkennung verbessert
#			Logikfehler bei verschachtelten Sätzen mit "und" behoben
#			Neue pass checks float, numeral
#			Extraktion des Klammernarrays auch bei Keylistenselector $n@
#			Bug on none existing namelists
#			Fhem $_ modifikations bug behoben
# 		    	Log ausgaben verbessert
#			Neues Attribut T2F_if
#			Neues Attribut T2F_origin
#			Neuer GET standardfilter
#			Neuer GET log
#			Neue Variable $IF
#			Errormessages detaliert
#			Neuer Get @keylist @modlist 
# 12.02.2018 0.4.1	Community Notes
#			Nested Modifikations
#			Neuer Get modificationtypes
################################################################
# TODO:
# 
# device verundung durch regexp klammern? eher durch try and error
# get compare lists
# answerx
# klammern in keywordlists sollen die $n nummerierung nicht beeinflussen
# 

package main;

use strict;
use warnings;
use POSIX;
use Data::Dumper;
use Time::Local;
use Text::ParseWords;
use Encode qw(decode encode);
my %Talk2Fhem_globals;


$Talk2Fhem_globals{version}="0.4.1";

$Talk2Fhem_globals{EN}{erase} = ['\bplease\b', '\balso\b', '^msgtext:'];
$Talk2Fhem_globals{EN}{pass} = {
	true	=> '^(yes|1|true|on|open|up|bright.*)$',
	false	=> '^(no|0|false|off|close|down|dark.*)$',
	integer	=> '\d+',
	word	=> '\b(\S{4,})\b',
	empty	=> '^\s*$'
}; 
$Talk2Fhem_globals{EN}{numbers} = {
'^one\S*' => 1
,'^(two|twice)' => 2
,'^(three|third)' => 3
,'^four\S*' => 4
,'^five\S*' => 5
,'^six\S*' => 6
,'^seven\S*' => 7
,'^eight\S*' => 8
,'^nine\S*' => 9
,'^ten\S*' => 10
,'^eleven\S*' => 11
,'^twelve\S*' => 12
};$Talk2Fhem_globals{EN}{datephrase} = {
	'tomorrow'=> {days=>1}
,	'day after tomorrow'=> {days=>2}
,	'yesterday'=> {days=>-1}
,	'the day before yesterday'=> {days=>-2}
,	'in (\d+) week\S?'=> {days=>'(7*$1)'}
,	'in (\d+) month(\S\S)?'=> {month=>'"$1"'}
,	'in (\d+) year(\S\S)?'=> {year=>'"$1"'}
,	'next week'=> {days=>7}
,	'next month'=> {month=>1}
,	'next year'=> {year=>1}
,	'(on )?sunday'=> {wday=>0}
,	'(on )?monday'=> {wday=>1}
,	'(on )?tuesday'=> {wday=>2}
,	'(on )?Wednesday'=> {wday=>3}
,	'(on )?thursday'=> {wday=>4}
,	'(on )?friday'=> {wday=>5}
,	'(on )?saturday'=> {wday=>6}
,	'in (\d+) days?'=> {days=>'"$1"'}
,	'on (\d\S*(\s\d+)?)'=> {date=>'"$1"'}
};
$Talk2Fhem_globals{EN}{timephrase} = {
	'(in|and|after)? (\d+) hours?' => {hour=>'"$2"'}
,	'(in|and|after)? (\d+) minutes?' => {min=>'"$2"'}
,	'(in|and|after)? (\d+) seconds?' => {sec=>'"$2"'}
,	'now' => {min=>3}
,	'after' => {min=>30}
,	'later' => {hour=>1}
,	'right now' => {unix=>'time'}
,	'immediately' => {unix=>'time'}
,	'by (\d+) (o.clock)?' => {time=>'"$1"'}
,	'at (\d+) (o.clock)?' => {time=>'"$1"'}
,	'morning' => {time=>'"09:00"'}
,	'evening' => {time=>'"18:00"'}
,	'afternoon' => {time=>'"16:00"'}
,	'morning' => {time=>'"10:30"'}
,	'noon' => {time=>'"12:00"'}
,	'at lunchtime' => {time=>'"12:00"'}
,	'today'	=> {time=>'"12:00"'}
};


#$Talk2Fhem_globals{DE}{erase} = ['\bbitte\b', '\bauch\b', '\smachen\b', '\sschalten\b', '\sfahren\b', '\bkann\b', '\bsoll\b', '\bnach\b', '^msgtext:'];
$Talk2Fhem_globals{DE}{erase} = ['\bbitte\b', '\bauch\b','\bkann\b', '\bsoll\b'];
#	true	=> '^(ja|1|true|wahr|ein|eins.*|auf.*|öffnen|an.*|rauf.*|hoch.*|laut.*|hell.*)$',
#	false	=> '^(nein|0|false|falsch|aus.*|null|zu.*|schlie\S\S?en|runter.*|ab.*|leise.*|dunk.*)$',
$Talk2Fhem_globals{DE}{numbers} = {
'(ein\S*|erste\S*)' => 1
,'zwei\S*' => 2
,'(drei\S*|dritt\S*)' => 3
,'vier\S*' => 4
,'fünf\S*' => 5
,'sechs\S*' => 6
,'sieb\S*' => 7
,'acht\S*' => 8
,'neun\S*' => 9
,'zehn\S*' => 10
,'elf\S*' => 11
,'zwölf\S*' => 12
};
$Talk2Fhem_globals{DE}{numberre} = join("|", ('\d+', keys %{$Talk2Fhem_globals{DE}{numbers}}));
$Talk2Fhem_globals{DE}{pass} = {
	true	=> '\b(ja|1|true|wahr|ein|eins.*|auf.*|öffnen|an.*|rauf.*|hoch.*|laut.*|hell.*|start.*|(ab)?spiele\S?)\b',
	false	=> '\b(nein|0|false|falsch|aus.*|null|zu.*|schlie\S\S?en|runter.*|ab.*|leise.*|dunk.*|stop.*|beende\S?)\b',
	numeral	=> {re=>"($Talk2Fhem_globals{DE}{numberre})",fc=>sub{
						return ($_[0]) if $_[0] =~ /\d+/;
						my $v = $_[0];
						foreach ( keys %{$Talk2Fhem_globals{DE}{numbers}} ) {
							my $tmp = Talk2Fhem_escapeumlauts($_);
							last if ($v =~ s/$tmp/$Talk2Fhem_globals{DE}{numbers}{$_}/i);
						}
						return($v);}
						},
	integer	=> '\b(\d+)\b',
	float	=> {re=>'\b(\d+)(\s*[,.])?(\s*(\d+))?\b',fc=>'"$1".("$4"?".$4":"")'},
	word	=> '\b(\S{4,})\b',
	empty	=> '^\s*$'
}; 
$Talk2Fhem_globals{DE}{datephrase} = {
	'(?<!guten )morgen'=> {days=>1}
,	'übermorgen'=> {days=>2}
,	'gestern'=> {days=>-1}
,	'vorgestern'=> {days=>-2}
,	'in ('.$Talk2Fhem_globals{DE}{numberre}.') woche\S?'=> {days=>'(7*$1)'}
,	'in ('.$Talk2Fhem_globals{DE}{numberre}.') monat(\S\S)?'=> {month=>'"$1"'}
,	'in ('.$Talk2Fhem_globals{DE}{numberre}.') jahr(\S\S)?'=> {year=>'"$1"'}
,	'nächste.? woche'=> {days=>7}
,	'nächste.? monat'=> {month=>1}
,	'nächste.? jahr'=> {year=>1}
,	'(am )?sonntag'=> {wday=>0}
,	'(am )?montag'=> {wday=>1}
,	'(am )?dienstag'=> {wday=>2}
,	'(am )?mittwoch'=> {wday=>3}
,	'(am )?donnerstag'=> {wday=>4}
,	'(am )?freitag'=> {wday=>5}
,	'(am )?samstag'=> {wday=>6}
,	'in ('.$Talk2Fhem_globals{DE}{numberre}.') tag(\S\S)?'=> {days=>'"$1"'}
,	'am (\d\S*(\s\d+)?)'=> {date=>'"$1"'}
};
$Talk2Fhem_globals{DE}{timephrase} = {
	'(in|und|nach)? ('.$Talk2Fhem_globals{DE}{numberre}.') stunde.?' => {hour=>'"$2"'}
,	'(in|und|nach)? ('.$Talk2Fhem_globals{DE}{numberre}.') minute.?' => {min=>'"$2"'}
,	'(in|und|nach)? ('.$Talk2Fhem_globals{DE}{numberre}.') sekunde.?' => {sec=>'"$2"'}
,	'gleich' => {min=>3}
,	'nachher' => {min=>30}
,	'später' => {hour=>1}
,	'jetzt' => {unix=>'time'}
,	'sofort' => {unix=>'time'}
,	'um ('.$Talk2Fhem_globals{DE}{numberre}.') (uhr)?' => {time=>'"$1"'}
,	'um ('.$Talk2Fhem_globals{DE}{numberre}.') uhr ('.$Talk2Fhem_globals{DE}{numberre}.')' => {hour=>'"$1"', min=>'"$1"'} ############ ZU TESTEN
,	'früh' => {time=>'"09:00"'}
,	'(?<!guten )abends?' => {time=>'"18:00"'}
,	'nachmittags?' => {time=>'"16:00"'}
,	'vormittags?' => {time=>'"10:30"'}
,	'mittags?' => {time=>'"12:00"'}
,	'heute'	=> {time=>'"12:00"'}
};


sub Talk2Fhem_Initialize($);
sub Talk2Fhem_Define($$);
sub Talk2Fhem_Undef($$);
sub Talk2Fhem_Delete($$);
sub Talk2Fhem_Notify($$);
sub Talk2Fhem_Set($@);
sub Talk2Fhem_addND($);
sub Talk2Fhem_UpdND($);
sub Talk2Fhem_Get($$@);
sub Talk2Fhem_Attr(@);
sub Talk2Fhem_Loadphrase($$$);
sub Talk2Fhem_parseParams($);
sub Talk2Fhem_realtrim($);
sub Talk2Fhem_normalize($);
sub Talk2Fhem_parseArray($;$$);
sub Talk2Fhem_loadList($$;$);
sub Talk2Fhem_language($);
sub Talk2Fhem_mkattime($$);
sub Talk2Fhem_exec($$$);
sub T2FL($$$);
sub Talk2Fhem_Initialize($)
{
	my ($hash) = @_;

	$hash->{DefFn}		= "Talk2Fhem_Define";
	$hash->{UndefFn}	= "Talk2Fhem_Undef";
#	$hash->{DeleteFn}	= "X_Delete";
	$hash->{SetFn}		= "Talk2Fhem_Set";
	$hash->{GetFn}		= "Talk2Fhem_Get";
#	$hash->{ReadFn}		= "X_Read";
#	$hash->{ReadyFn}	= "X_Ready";
	$hash->{AttrFn}     = "Talk2Fhem_Attr";
	$hash->{NotifyFn}	= "Talk2Fhem_Notify";
#	$hash->{RenameFn}	= "X_Rename";
#	$hash->{ShutdownFn}	= "X_Shutdown";
	$hash->{AttrList} =
		"disable:0,1 T2F_disableumlautescaping:0,1 T2F_origin T2F_filter T2F_if:textField-long T2F_keywordlist:textField-long T2F_modwordlist:textField-long T2F_language:EN,DE";


		
}

sub Talk2Fhem_Define($$)
{
	my ( $hash, $def ) = @_;
	
	$hash->{STATE} = "Loading";
	
	if ($def =~ /^\S+ Talk2Fhem$/) {
		$hash->{DEF} = "";
		
		return;
	}
	
	my $error = undef;

	my @def = split(/ /, $def);
	my $name = shift(@def);
	my $dev = shift(@def);


	$error = Talk2Fhem_Loadphrase($hash, "phrase", "@def");

	($_ = Talk2Fhem_loadList($hash, "T2F_keywordlist")) && return;
	($_ = Talk2Fhem_loadList($hash, "T2F_modwordlist")) && return;

	T2FL($name, 1, $error) if $error;
#	T2FL($name, 5, "T2F Phrasehash:\n".Dumper($Talk2Fhem_phrase{$name})) unless $error;
	T2FL($name, 5, "T2F Phrasehash:\n".Dumper($hash->{helper}{phrase})) unless $error;
	
	$hash->{STATE} = "Initialized";
	return $error;
}

sub Talk2Fhem_Loadphrase($$$) {
	
	my $hash = shift;
	my $target = shift;
	my $text = "@_";
	my @h = Talk2Fhem_parseParams($text);
	return ("Error while parsing Definition.\n$h[0]"."\n\n$text" ) unless(ref($h[0]) eq "HASH");

	# Not ready yet
	return unless $hash->{helper};
	
	my $disu =AttrVal($hash, "T2F_disableumlautescaping", 0);
	my %keylist = %{$hash->{helper}{T2F_keywordlist}} if $hash->{helper}{T2F_keywordlist};


	my $i=0;
	while ($i <= $#h) { 
		my $elmnt = $h[$i];
		if ($$elmnt{key} eq '$include') {
			T2FL $hash->{NAME}, 4, "Loading Configfile $$elmnt{val}";

#			open(my $fh, '<:encoding(UTF-8)', $$elmnt{val})
#			open fh, "<", $$elmnt{val}
#			  or return "Could not open file '$$elmnt{val}' $!";
			my ($error, @content) = FileRead($$elmnt{val});
			return "$error '$$elmnt{val}'" if $error;
			
			#local $/;			
			my @file = Talk2Fhem_parseParams(join("\n",@content));
			#close("fh");
			return ("Error while parsing File $$elmnt{val}.\n$file[0]"."\n\n$text" ) unless(ref($file[0]) eq "HASH");
			splice @h, $i, 1;
			splice @h, $i, 0, @file;

#			push(@h, @file);
			next;
		}
		
		

		if ($$elmnt{val} =~ /^\((.*)\)/) {
			#my %r = eval($$elmnt{val});
				#Log 1, "Hallo: ".$1;
				my %r;
					my $harr = Talk2Fhem_parseArray($1, undef, 1);
					for (@$harr) {
						my $h = Talk2Fhem_parseArray($_, "=>", /^[^=]*=>[\t\s\n]*[^"']/);
						#my @arr = /(.*?)=>(.*)/; 
						#$h = Talk2Fhem_parseArray($_, "=>", 1) if $$h[0]=~ /answer/;
						
						$r{$$h[0]} = $$h[1];					
					}
			return("Error while parsing Definition HASH.\n".$$elmnt{val}."\n\n$text") unless (%r);
			$$elmnt{val} = \%r;
		}elsif ($$elmnt{val} =~ /^\(.*[^)]$/) {
			return("Error while parsing Definition HASH.\nDid you forget closing ')' in:\n".$$elmnt{val}."\n\n$text");
		} else {
			my $tmp=$$elmnt{val};
			$$elmnt{val} = undef;
			$$elmnt{val}{($target eq "phrase") ? "cmd" : $target} = $tmp;
#			$$elmnt{val}{cmd} = $tmp;
		} 
		
		#alternative syntax wenn nur ein value
#		elsif ($$elmnt{key} =~ /^\$if.*?\s+(.*)/) {
			#return("Syntax Error. Can't locate IF condition.") unless $1;
			#return("Syntax Error. Can't locate IF regexp.") unless $$elmnt{val};
			#$hash->{helper}{ifs} = { IF=>$$elmnt{val}, regexp=>"$1" };
			#splice @h, $i, 1;
			#next;
#		}
		$i++;
	
		# Regexp Auflösung und Analyse
		my $d=0;
		my @hitnokeylist=(AttrVal($hash->{NAME}, "T2F_origin", undef));
		my @phrs = map { Talk2Fhem_realtrim($_) } split(/[\t\s]*\&\&[\t\s]*/, $$elmnt{key});
		for my $phr (@phrs) {
		my $keylistname;
		my $tmp = $phr;
		# klammern zählen die nicht geslasht sind und kein spezialklammern sind (?
		while ($tmp =~ /(?<!\\)\((?!\?)(@(\w+))?/g) {
			$d++;
			if ($1) {
				$keylistname = $2; 
				unless ($keylist{$keylistname}) {
					return(T2FL($hash, 1, "Unkown keywordlist $1. In phrase: $phr"));
				}
				my $re = join("|", @{$keylist{$keylistname}});
				$phr =~ s/@(\w+)/$re/;
				#speichern welcher array in welcher klammer steht
				$hitnokeylist[$d] = $keylistname;
			}
		}

		push(@{$$elmnt{regexps}}, Talk2Fhem_escapeumlauts($phr, $disu));
		$$elmnt{hitnokeylist} = \@hitnokeylist;
		}

	}
	
#	for (@h) {
#		next unless ($$_{val}{if});
#		my $test = AnalyzeCommandChain ($hash, "IF ((".$$_{val}{if}.")) ({1})");
#		if ($test and $test ne "1") {
#			T2FL $hash, 1, "Condition ".$$_{val}{if}." failed: ".$test;
#			return($test."\n\n".$text);
#		}
#	}
	
		
	$hash->{helper}{$target} = \@h;

	return(undef);

}


sub Talk2Fhem_Undef($$)    
{                     
	my ( $hash, $name) = @_;       

	$hash->{helper} = undef;
	
	return undef;                  
}

sub Talk2Fhem_Delete($$)
{
	my ( $hash, $name ) = @_;
 
	return undef;
}

sub Talk2Fhem_Notify($$)
{
	my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; 
 
	my $devName; # Device that created the events
	for (@{$$own_hash{helper}{notifiers}}) {
		$devName = $dev_hash->{NAME} if $_ eq $dev_hash->{NAME};
	}
	return "" unless $devName;
	my $events = deviceEvents($dev_hash, 1);

	my @nots = @{$$own_hash{helper}{notifies}};
	my $i=0;
#	for my $i (0 .. $#nots) {
	while ($i <= $#{$$own_hash{helper}{notifies}}) {
		my $not = ${$$own_hash{helper}{notifies}}[$i];
		if (grep { $devName eq $_ } (@{$$not{devs}})) {
			T2FL $own_hash, 4, "Event detected ".$$not{if};
			my $res = fhem($$not{if});
			T2FL $own_hash, 5, "Result: ".$res; 
			if ($res == 1) {
				T2FL $own_hash, 3, "Execute command: ".$$not{cmd}; 
				
				my $fhemres = fhem($$not{cmd});
				readingsSingleUpdate($own_hash, "response", $fhemres, 1);	
				splice(@{$$own_hash{helper}{notifies}}, $i--, 1);
				Talk2Fhem_UpdND($own_hash);
			} elsif ($res) {
				T2FL $own_hash, 1, "Error on condition ($$not{if}): $res";
				readingsSingleUpdate($own_hash, "response", $res, 1);	
				splice(@{$$own_hash{helper}{notifies}}, $i--, 1);
				Talk2Fhem_UpdND($own_hash);
			}
		}
	$i++;
	}
	
	return "" if(IsDisabled($ownName));
	
	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
		 #Talk2Fhem_parseKeys($own_hash);
	}
}

sub Talk2Fhem_Set($@)
{
	my ( $hash, $name, @args ) = @_;
	(return "\"set $name\" needs at least one argument") unless(scalar(@args));
    (return "Unknown argument ?, choose one of ! cleartriggers:noArg cleartimers:noArg") if($args[0] eq "?");
	
	if ($hash->{STATE} ne "Initialized") {
		#Fülle nur cmds array
 	} elsif ($args[0] eq "cleartimers") {
		AnalyzeCommand($hash->{CL}, "delete at_".$name."_.*");
 	} elsif ($args[0] eq "cleartriggers") {
		
		$$hash{helper}{notifies} = [];
		Talk2Fhem_UpdND($hash);
	} else {
		$hash->{STATE} = "Loading";
		shift @args if $args[0] eq "!";
		@args = ReadingsVal($name, "set", undef) unless(scalar(@args));
		
		#my $txt = s/[^\x00-\xFF]//g;
		#my $txt = decode("utf8", "@args");
		my $txt = "@args";
		Talk2Fhem_Loadphrase($hash, "phrase", $hash->{DEF}) unless $hash->{helper}{phrase}; 
		Talk2Fhem_Loadphrase($hash, "if", AttrVal($name, "T2F_if","")) if (AttrVal($name, "T2F_if",0) and ! $hash->{helper}{if}); 
		
		readingsSingleUpdate($hash, "set", "$txt", 1);	

		$hash->{STATE} = "Initialized";
		
		$hash->{STATE} = "Working";
		
		
		
		my %res = Talk2Fhem_exec("$txt", $hash, $name);

		if (%res && ! $res{err} && $res{cmds}) {
				#Ausführen
			if ($res{cmds}) {
				for my $h (@{$res{cmds}}) {
					my $fhemcmd = ($$h{at}?Talk2Fhem_mkattime($name, $$h{at})." ":"").$$h{cmd};
					
					unless ($$h{ifs}) { # kein IF
										
						T2FL $name, 5, "Executing Command: ".$fhemcmd;
						my $fhemres = AnalyzeCommandChain ($hash->{CL}, $fhemcmd) unless (IsDisabled($name));
						$$h{"fhemcmd"} = $fhemcmd;
						push(@{$res{fhemres}}, $fhemres) if ($fhemres);
						T2FL $name, 5, "Pushed: ".$fhemcmd;
					} else { # If 
						#Event erstellen
						my %r;
						$r{hash} = $hash;
						$r{if} = "IF ((".(join(") and (", @{$$h{ifs}})).")) ({1})";
						my $test = AnalyzeCommandChain ($hash->{CL}, $r{if});
						if ($test and $test ne "1") {
							T2FL $name, 1, "Condition $r{if} failed: ".$test;
							push(@{$res{fhemres}}, $test);
							next;
						}						my %s = (); # make it unique
						push(@{$r{devs}}, grep { ! $s{$_}++ } map {/\[(.*?)[:\]]/g} @{$$h{ifs}});
						$r{cmd} = $fhemcmd;
						Talk2Fhem_addND(\%r);
					}
				}
			}
		} else {
		# Nothing to do
			T2FL $name, 1, "Nothing to do: ".$txt;
		}
		
		#push(@{$res{err}}, "FHEM: ".$fhemres) if $fhemres;
		
		my $status;
		if ($res{fhemres})  { $status = "response"  }
		elsif (IsDisabled($name)) {$status = "disabled"}
		elsif ($res{err}) {$status = "err"}
		elsif ($res{answers}) {$status = "answers"}
		else {$status = "done"}

		
		readingsBeginUpdate($hash);
		#T2FL($hash, 1, "CL:\n".Dumper($hash->{CL}));
		#readingsBulkUpdate($hash, "client", $hash->{CL}{NAME});
		readingsBulkUpdate($hash, "ifs", join(" and ", @{$res{ifs}})) if $res{ifs};
		#readingsBulkUpdate($hash, "cmds", join(";\n", map { ($$_{at}?Talk2Fhem_mkattime($name, $$_{at})." ":"").$$_{cmd} } @{$res{cmds}})) if $res{cmds};
		readingsBulkUpdate($hash, "cmds", join(";\n", map { $$_{"fhemcmd"} } @{$res{cmds}})) if $res{cmds};
		readingsBulkUpdate($hash, "answers", join(" und ", @{$res{answers}})) if $res{answers};
		readingsBulkUpdate($hash, "err", join("\n", @{$res{err}})) if $res{err};
		readingsBulkUpdate($hash, "response", join("\n", @{$res{fhemres}})) if $res{fhemres};
		readingsBulkUpdate($hash, "status", $status);
		### in done könnte 
		readingsEndUpdate($hash, 1);
		

	}
	$hash->{STATE} = "Initialized";
	return;
}

sub Talk2Fhem_addND($) {
	#Log 1, Dumper $_[0]{cmds};
	my $hash = $_[0]{hash};
	unless(IsDisabled($$hash{NAME})) {
	my %h;
	for (keys %{$_[0]}) {
		next if /hash/;
		$h{$_} = $_[0]{$_};
	}
		push(@{$$hash{helper}{notifies}}, \%h);
		Talk2Fhem_UpdND($hash);
	}
}

sub Talk2Fhem_UpdND($) {
	my ($hash) = @_;
	my %s = (); # make it unique
	my @ntfs = @{$$hash{helper}{notifies}};
	@{$$hash{helper}{notifiers}} =  grep { ! $s{$_}++ } map { @{$$_{devs}} } @ntfs;
	#$$hash{NOTIFYDEV} = join ",",@{$$hash{helper}{notifiers}};
	notifyRegexpChanged($hash, join "|",@{$$hash{helper}{notifiers}});
	readingsSingleUpdate($hash, "notifies", join( "\\n", map {$$_{if}} @ntfs), 1);	
	T2FL $hash, 4, "Updated NotifyDev: ".join( "|", @{$$hash{helper}{notifiers}});
	T2FL $hash, 5, "Updated NotifyDev: ".Dumper @ntfs;
}

sub Talk2Fhem_Get($$@) 
{
	my ( $hash, $name, $opt, @args ) = @_;
	my $lang = Talk2Fhem_language($hash);
	return "\"get $name\" needs at least one argument" unless(defined($opt));

	if($opt eq "keylistno") 
	{
		my $res;
		my $keylist = Talk2Fhem_parseParams(AttrVal($name, "T2F_keywordlist", ""));
		foreach (keys %$keylist) {
			$res .= $_.":\n";
			my $arr = Talk2Fhem_parseArray($$keylist{$_});			
			for (my $i=0;$i<=$#$arr;$i++) {
				$res .= ($i+1).": ".$arr->[$i]."\n";
			}
		}
		return $res;
	}
	elsif($opt =~ /^\@/)
	{
		my $keylist = Talk2Fhem_parseParams(AttrVal($name, "T2F_keywordlist", ""));
		my $modlist = Talk2Fhem_parseParams(AttrVal($name, "T2F_modwordlist", ""));

		
		my $r; 

		(my $kwl = $opt) =~ s/^\@//;
		(my $mwl = $args[0]) =~ s/^\@//;
		my $kw = Talk2Fhem_parseArray($$keylist{$kwl});
		my $mw = Talk2Fhem_parseArray($$modlist{$mwl});

		my $l=11;
		map { $l = length($_) if length($_) > $l } (@$kw);
		$r .= "Keywordlist".(" " x ($l-11))." : "."Modwordlist\n";
		$r .= $opt.(" " x ($l-length($opt)))." : ".$args[0]."\n\n";

		for my $i (0..$#$kw) {
			$r .= ($$kw[$i]//"").(" " x ($l-length(($$kw[$i]//""))))." : ".($$mw[$i]//"")."\n";
		}
		
		
		return($r);
	}
	elsif($opt eq "standardfilter")
	{
		my $atr=AttrVal($name, "T2F_filter", 0);
		my $filter = join(',',@{$Talk2Fhem_globals{Talk2Fhem_language($name)}{erase}});
		if ($atr) {
			return("Attribute T2F_filter is not empty please delete it.");
		} else {
			fhem("attr $name T2F_filter $filter");
			return("Filterattribute set to standard.");
		}
	}
	elsif($opt eq "log")
	{
		return($hash->{helper}{LOG});
	}
	elsif($opt eq "modificationtypes")
	{
		my $res = ref $Talk2Fhem_globals{$lang}{pass}{$args[0]} && $Talk2Fhem_globals{$lang}{pass}{$args[0]}{re} || $Talk2Fhem_globals{$lang}{pass}{$args[0]}; 
		return(($lang eq "DE" ? "Folgende RegExp wird erwartet:\n" : "The following regexp is expected:\n").$res);
	}
	elsif($opt eq "datedefinitions")
	{
		return(Dumper %{$Talk2Fhem_globals{$lang}{datephrase}});
	}
	elsif($opt eq "timedefinitions")
	{
		return(Dumper %{$Talk2Fhem_globals{$lang}{timephrase}});
	}
	elsif($opt eq "version")
	{
		return(Dumper $Talk2Fhem_globals{version});
	}
#	...
	else
	{
		my $keylist = Talk2Fhem_parseParams(AttrVal($name, "T2F_keywordlist", ""));
		my $modlist = Talk2Fhem_parseParams(AttrVal($name, "T2F_modwordlist", ""));
		return "Unknown argument $opt, choose one of keylistno:noArg log:noArg standardfilter:noArg version:noArg".
			" @".join(" @",map { $_.":@".join(",@", sort keys %$modlist) } sort keys %$keylist).
			" modificationtypes:".join(",", sort keys %{$Talk2Fhem_globals{$lang}{pass}}).
			" datedefinitions:noArg timedefinitions:noArg";
	}
}

sub Talk2Fhem_Attr(@)
{
	my ( $cmd, $name, $attrName, $attrValue ) = @_;
    
  	# $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attrName/$attrValue sind Attribut-Name und Attribut-Wert
    
	#Log 1, Dumper @_;
	if ($attrName eq "T2F_keywordlist" or $attrName eq "T2F_modwordlist") {
		$defs{$name}{helper}{phrase} = undef;
		$defs{$name}{helper}{if} = undef;
		if ($cmd eq "set") {
			T2FL $name, 4, "Attribute checking!"; 
			return Talk2Fhem_loadList($defs{$name}, $attrName, $attrValue);
		} else {
			delete $defs{$name}{helper}{$attrName};			
		}
	} 

	if ($attrName eq "T2F_if") {
		if ($cmd eq "set") {
			return(Talk2Fhem_Loadphrase($defs{$name}, "if", $attrValue));
		} else {
			delete $defs{$name}{helper}{if};			
		}
	}
		
	
	#elsif ($attrName eq "T2F_filter") {
		#Log 1, "HALLO".$defs{global}{STATE};  
		#my $preattr = AttrVal($name, "T2F_filter", "");
		#if ($preattr eq "") {
		#	$_[3] = join(",", @{$Talk2Fhem_globals{Talk2Fhem_language($name)}{erase}}).",".$attrValue;
		#}}
	return undef;
}

sub Talk2Fhem_parseParams_old($) 
{
	my ($val) = @_;
	my %res; my $i=0;
	foreach my $v (split(/\n/,$val)) {
#	if ($v =~ /^[ \t]*(?!#)(.*?)[ \t]+=[ \t]+(.*?)[ \t]*$/) {
	$i++;
	$v =~ s/#.*//;
	next unless $v;

	if ($v =~ /^[ \t]*(.*?)[ \t]+=[ \t]+(.*?)[ \t]*$/) {
		return ("#$i Missing REGEXP '$v'") unless ($1);
		return ("#$i Missing Command '$v'") unless ($2);
		$res{$1} = $2;
	} else {
		return ("#$i Syntaxerror. '$v'\nDid you forget whitespace before or after '='");
	}
	}
	return(\%res);
}

sub Talk2Fhem_realtrim($)
{ 
   my $string = shift;
   $string =~ s/^[\s\t\n]*|[\s\t\n]*$//g;
#   $string =~ s/^[\s\t\n]*|[\s\t\n]*$//g;
   return $string;
}

sub Talk2Fhem_normalize($)
{ 
   my $string = shift;
   $string =~ s/\s{2,}|\b\w\b|\t|\n|['".,;:\!\?]/ /g;
   return $string;
}

sub Talk2Fhem_parseParams($) 
{
	my ($def) = @_;
	my $val = $def;
	my $i=0;
	my %hres;
	my @res;
	while ($val =~ /(.*?)[ \t]+=[ \t\n]+((.|\n)*?)(?=(\n.*?[ \t]+=[ \t\n]|$))/) {
	my $pre = Talk2Fhem_realtrim($`);
	if ($pre) {
		return ("Syntaxerror: $pre") if ($pre !~ /^#/);
	}
	$val = $';
	next if (Talk2Fhem_realtrim($1) =~ /^#/);
	my $key = $1;
	my $val = $2; my $r;
	$key = Talk2Fhem_realtrim($key);
	foreach my $line (split("\n", $val)) {
		$line =~ s/#.*//;
		$line = Talk2Fhem_realtrim($line);
		$r .= $line;
	}
	if ( wantarray ) {
		push(@res, {key => $key, val => $r});
	} else {
		$hres{$key} = $r;
	}
	
	}
	return ("Syntaxerror: $val") if (Talk2Fhem_realtrim($val));
	
	return(@res) if ( wantarray );
	return(\%hres);
	
}

sub Talk2Fhem_parseArray($;$$) 
{
	my ($val, $split, $keep) = @_;
	$split = "," unless $split;
	my @r = map {Talk2Fhem_realtrim($_)} quotewords($split, $keep, $val);
	return(\@r);
}

sub Talk2Fhem_loadList($$;$)
{
my $hash = shift;
my $type = shift;
my $list = (shift || AttrVal($hash->{NAME}, $type, ""));

	$list = Talk2Fhem_parseParams($list);
	#Log 1, Dumper $list;
	return ("Error while parsing Keywordlist.\n$list" ) unless(ref($list) eq "HASH");
	foreach (keys %$list) {
#			$$list{$_} = Talk2Fhem_parseArray($$list{$_});			
		$hash->{helper}{$type}{$_} = Talk2Fhem_parseArray($$list{$_});			
	}
	
#		my $modlist = Talk2Fhem_parseParams(AttrVal($name, "T2F_modwordlist", ""));;
#		return ("Error while parsing Modwordlist.\n$modlist" ) unless(ref($modlist) eq "HASH");
#		foreach (keys %$modlist) {
##			$$modlist{$_} = Talk2Fhem_parseArray($$modlist{$_});			
#			$hash->{helper}{modlist}{$_} = Talk2Fhem_parseArray($$modlist{$_});			
#		}
}

sub Talk2Fhem_language($) 
{
my ($name) = @_;
my $lang = AttrVal($name, "T2F_language", AttrVal("global", "language", "DE"));
$lang=uc($lang);
$lang = "DE" unless $lang =~ /DE|EN/;
return($lang);
}

sub Talk2Fhem_mkattime($$) {
my $myname = $_[0];
my $i = $_[1];
my @ltevt = localtime($i);
my $d=0; my $dev="at_".$myname."_".$i."_".$d;
while ($defs{$dev}) {$dev =  "at_".$myname."_".$i."_".++$d}
 
return("define at_".$myname."_".$i."_".$d." at "
	.($ltevt[5]+1900)
	."-".sprintf("%02d", ($ltevt[4]+1))
	."-".sprintf("%02d", $ltevt[3])
	."T".sprintf("%02d", $ltevt[2])
	.":".sprintf("%02d", $ltevt[1])
	.":".sprintf("%02d", $ltevt[0]));
}


sub Talk2Fhem_exec($$$) {

my %assires;
my %lastcmd;

sub Talk2Fhem_get_time_by_phrase($$$$$%);
sub Talk2Fhem_addevt($$$$;$$);
sub Talk2Fhem_err($$$;$);
sub Talk2Fhem_filter($$);
sub Talk2Fhem_escapeumlauts($;$);
sub Talk2Fhem_test($$);

my ($txt, $me, $myname) = @_;
$me->{helper}{LOG}="";

#my $kl = $me->{helper}{T2F_keywordlist};
#my $ml = $me->{helper}{T2F_modwordlist};

(Talk2Fhem_err($myname, "No Text given!",\%assires,1) && return(%assires)) unless $txt;

my $lang = Talk2Fhem_language($myname);

my %Talk2Fhem = %{$Talk2Fhem_globals{$lang}};

T2FL($myname, 5, "Talk2Fhem Version: ".$Talk2Fhem_globals{version});
T2FL($myname, 3, "Decoding Text: ".$txt);
my $t2ffilter = AttrVal($myname,"T2F_filter",0);
T2FL($me, 5, "Using User Filter: ".$t2ffilter) if $t2ffilter;

my $lastevt;
my $lastif;
my $lastifmatch;


my $origin = AttrVal($myname, "T2F_origin", "");
$txt =~ s/$origin//;
$origin = $&;
$txt = Talk2Fhem_normalize(Talk2Fhem_realtrim($txt));
readingsSingleUpdate($me, "origin", $origin, 1);	

#Zeiten könnten auch ein und enthalten deswegen nicht wenn auf und eine Zahl folgt
my @cmds = split(/ und (?!$Talk2Fhem_globals{DE}{numberre})/, $txt);


foreach (@cmds) {
 next unless $_;
 my $cmd = $_;
 my $specials;
 $$specials{origin} = $origin;
 
 
T2FL($myname, 4, "Command part: '$cmd'");
 my $rawcmd = $cmd;


my $time = time;
 ### wieder und dann/danach am Anfang legen die zeit auf das vorherige event
if ($lastevt and ($cmd =~ /\bwieder |^(dann|danach).*/i)) {
	T2FL($myname, 5, "Word again found. Reusing timeevent. ".localtime($lastevt)); 
	$time = $lastevt;
}
my $evtime = Talk2Fhem_get_time_by_phrase($myname, $time, $time, \$cmd, \$specials, %{$Talk2Fhem{datephrase}});
$evtime = Talk2Fhem_get_time_by_phrase($myname, $evtime, $time, \$cmd, \$specials, %{$Talk2Fhem{timephrase}});

#T2FL($myname, 4, "Extracted Timephrase. '$$specials{timephrase}'") if $$specials{timephrase};
T2FL($myname, 4, "Extracted Timephrase. '$$specials{timephrase}'") if $$specials{timephrase};
T2FL($myname, 5, "Commandpart after datedecoding. '$cmd'") if $cmd ne $rawcmd;

unless($evtime) { 
	Talk2Fhem_err($myname, "Error while time calculating: $rawcmd",\%assires,1);
	next;
}

$cmd = Talk2Fhem_filter($myname, $cmd);

if ($time < $evtime) {
	T2FL($myname, 4, "Eventtime found: ".localtime($evtime));
	$lastevt=$evtime;
} elsif ($time-10 > $evtime) { 
	T2FL($myname, 3, "Time is in past: $time $evtime");
	$lastevt=0;
} elsif ($lastevt) {$lastevt++}

foreach my $phr (@{$me->{helper}{if}}) {
	my $sc = Talk2Fhem_addevt($myname, $phr, $lastevt, $cmd, \%assires, $specials);
}

push(@{$$specials{ifs}} , @{$lastif}) if ($lastif);
$lastif = $$specials{ifs};
$lastifmatch .= ($lastifmatch ? " und " : " ").$$specials{match};
$$specials{ifmatch} = $lastifmatch;

$cmd = Talk2Fhem_normalize(Talk2Fhem_realtrim($cmd));

# Maximal 2 Wörter vor dem wieder, ansonsten wird von einem neuen Kommando ausgegangen.
# dann wird nach der letzten Zahl, wort länger als 3 buchstaben oder wahr falsch wörter gesucht.
#if ($cmd =~ /^.?(\S+\s){0,2}wieder.* (\S+)$/i) {
if (%lastcmd and
(	$cmd =~ /wieder\b.*($Talk2Fhem{pass}{float})/i ||
	$cmd =~ /wieder\b.*($Talk2Fhem{pass}{integer})/i ||
	$cmd =~ /wieder\b.*($Talk2Fhem{pass}{word})/i ||
	$cmd =~ /wieder\b.*($Talk2Fhem{pass}{true})/i ||
	$cmd =~ /wieder\b.*($Talk2Fhem{pass}{false})/i ||
	$cmd =~ /wieder\b.*($Talk2Fhem{numberre})/i)) {
	$$specials{dir} = $1;
	# hier erfolgt ein hitcheck, damit erkannt wird ob das kommando ohne wieder ein eigenständiger befehl ist. 
	# frage ist ob zusätzlich über specials eine rückgabe gegeben werden soll ob die konfig "wieder" fähig ist. z.b. überhaupt ein $n vorhanden ist.
	# ist der 2 wörter check noch notwendig?
	unless (Talk2Fhem_test($me, $cmd =~ s/\s?wieder\s/ /r)) {
		#Vorhiges Kommando mit letztem wort als "direction"
	#	Log 1, Dumper Talk2Fhem_test($me, $_ =~ s/\s?wieder\s/ /r);
		T2FL($myname, 4, "Word again with direction ($$specials{dir}) found. Using last command. ${$lastcmd{phr}}{key}");
		Talk2Fhem_addevt($myname, $lastcmd{phr}, $lastevt, $lastcmd{cmd}, \%assires, $specials);
		next;
	} else {
		T2FL($myname, 3, "Again word ignored because Command matches own Phrase!");
		$$specials{dir} = undef;
	}
}
#wieder wird nicht mehr benötigt
$cmd =~ s/\bwieder\b|^(dann|danach) / /g;
$cmd = Talk2Fhem_filter($myname, $cmd);

T2FL($myname, 4, "Command left: '$cmd'") if $rawcmd ne $cmd;
	
 my $sc;
 
 #foreach my $phr (keys(%{$Talk2Fhem_phrase{$myname}})) {
 foreach my $phr (@{$me->{helper}{phrase}}) {
	#Teste Phrasenregex
	$lastcmd{phr} = $phr;
	$lastcmd{cmd} = $cmd;
	$sc = Talk2Fhem_addevt($myname, $phr, $lastevt, $cmd, \%assires, $specials);
	# undef nicht gefunden, 0 fehler beim umwandeln, 1 erfolgreich
	last if defined($sc);
 }

 unless ($sc) {
	unless(defined($sc)) {
		# undef
		Talk2Fhem_err($myname, "No match: '$rawcmd'",\%assires,1);
	} else {
		# 0
		Talk2Fhem_err($myname, "Error on Command: '$rawcmd'",\%assires,1) unless $assires{err};
		last;
	}
 }
# eventuell ganz abbrechen bei fehler, jetzt wird noch das nächste und ausgewertet
next;
 
}
return(%assires);

sub Talk2Fhem_filter($$) {
 my ($name, $cmd) = @_;
 my $filter = AttrVal($name,"T2F_filter",$Talk2Fhem_globals{Talk2Fhem_language($name)}{erase});
unless (ref($filter) eq "ARRAY") {
	$filter = Talk2Fhem_parseArray($filter);
};
 
 for (@$filter) {
	$cmd =~ s/$_/ /gi;
 }
 $cmd =~ s/\s{2,}/ /g;
 return(Talk2Fhem_realtrim($cmd));
}

sub Talk2Fhem_get_time_by_phrase($$$$$%) {
my ($myname, $evt, $now, $cmd, $spec, %tp) = @_;
#T2FL($myname, 5, "get_time_by_phrase. Using eventtime: ".localtime($evt)." now: ".localtime($now)." command: ".$$cmd);
return(0) unless ($evt); 
my @lt = localtime($evt);
my @now = localtime($now);
my $disu = AttrVal($myname, "T2F_disableumlautescaping", 0);

	foreach my $key (keys(%tp)) {
		my $esckey = Talk2Fhem_escapeumlauts($key, $disu);
		my @opt = ($$cmd =~ /\b$esckey\b/i);
		while ($$cmd =~ s/\b$esckey\b/ /i) {
			$$$spec{timephrase} .= $&." ";
			my %tf = %{$tp{$key}};
			T2FL($myname, 4, "Timephrase found: =~ s/\\b$key\\b/");
			foreach my $datemod (keys(%tf)) {
				# Suche Ersetzungsvariablen
				my $dmstore = $tf{$datemod};
				while ($tf{$datemod} =~ /\$(\d+)/) {
				my $d=$1;
				my $v = $opt[($d-1)];
				if ($v !~ /^\d+$/) {
				#Log 1, "KEINE Zahl ".$v;
					foreach ( keys %{$Talk2Fhem_globals{DE}{numbers}} ) {
						my $tmp = Talk2Fhem_escapeumlauts($_, $disu);
						last if ($v =~ s/$tmp/$Talk2Fhem_globals{DE}{numbers}{$_}/i);
					}
				}
				$tf{$datemod} =~ s/\$\d+/$v/;
				}
				$tf{$datemod} = eval($tf{$datemod});
				T2FL($myname, 5, "TIMEPHRASEDATA mod: '$datemod' raw: '$dmstore' result: '$tf{$datemod}' opt: '@opt'");
				if ($datemod eq "days") {
					$evt = POSIX::mktime(0,0,12,($lt[3]+$tf{days}),$lt[4],$lt[5]) || 0;
				} elsif ($datemod eq "wday") {
					$evt = POSIX::mktime(0,0,12,($lt[3]-$lt[6]+$tf{wday}+(( $tf{wday} <= $lt[6] )?7:0)),$lt[4],$lt[5]) || 0;
				} elsif ($datemod eq "year") {
					$evt = POSIX::mktime(0,0,12,$lt[3],$lt[4],($lt[5]+$tf{year})) || 0;
				} elsif ($datemod eq "month") {
					$evt = POSIX::mktime(0,0,12,$lt[3],($lt[4]+$tf{month}),$lt[5]) || 0;
				} elsif ($datemod eq "sec") {
					$evt = POSIX::mktime(($now[0]+$tf{sec}),$now[1],$now[2],$lt[3],$lt[4],$lt[5]) || 0;
				} elsif ($datemod eq "min") {
					$evt = POSIX::mktime($now[0],($now[1]+$tf{min}),$now[2],$lt[3],$lt[4],$lt[5]) || 0;
				} elsif ($datemod eq "hour") {
					$evt = POSIX::mktime($now[0],$now[1],($now[2]+$tf{hour}),$lt[3],$lt[4],$lt[5]) || 0;
				} elsif ($datemod eq "time") {
					my @t = split(":", $tf{time});
					$evt = POSIX::mktime($t[2] || 0,$t[1] || 0,$t[0],$lt[3],$lt[4],$lt[5]) || 0;
				} elsif ($datemod eq "date") {
					my @t = split(/\.|\s/, $tf{date});
					if ($t[1]) {$t[1]--} else {$t[1] = $now[4]+1}
					if ($t[2]) {if (length($t[2]) eq 2) { $t[2] = "20".$t[2] }; $t[2]=$t[2]-1900} else {$t[2] = $now[5]}
					$evt = POSIX::mktime(0,0,12,$t[0], $t[1], $t[2]) || 0;
				} elsif ($datemod eq "unix") {
					$evt = localtime($tf{unix});
				}
				@now = localtime($evt);
			}
			@lt = localtime($evt);
		}
	}
return($evt);
}

sub Talk2Fhem_test($$) {
my ($hash, $cmd) = @_;
	 foreach my $phr (@{$hash->{helper}{phrase}}) {
		my $r = Talk2Fhem_addevt($hash->{NAME}, $phr, undef, $cmd);
		return $r if $r;
	 }
}

sub Talk2Fhem_addevt($$$$;$$) {
#print Dumper @_;
my ($myname, $phr, $lastevt, $cmd, $res, $spec) = @_;
my $success;
my $rawcmd = $cmd;
my $cmdref = \$_[3];
my $disu =AttrVal($myname, "T2F_disableumlautescaping", 0);

my %keylist = %{$defs{$myname}{helper}{T2F_keywordlist}} if $defs{$myname}{helper}{T2F_keywordlist};
my %modlist = %{$defs{$myname}{helper}{T2F_modwordlist}} if $defs{$myname}{helper}{T2F_modwordlist};
#T2FL($me, 5, "Using lists:\n".Dumper(%keylist, %modlist));

# my @phrs = map { Talk2Fhem_realtrim($_) } split(/[\t\s]*\&\&[\t\s]*/, $$phr{key});

my @hitnokeylist = @{$$phr{hitnokeylist}};
my @fphrs = @{$$phr{regexps}};

my $pmatch;
my $punmatch = $cmd;

my @dir = ($$spec{origin});
T2FL($myname, 5, "$myname Evaluate search:\n$cmd =~ /$$phr{key}/i") if ref $res;
for my $fphr (@fphrs) {
#	if (my @d = ($cmd =~ qr/$fphr/i)){
	if ($fphr =~ s/^\?//){
		my @d = ($cmd =~ /$fphr/i);
		my $m = $&;
		#Log 1, "A: ".$fphr;
		#Log 1, "A: ".Dumper $m;
		#Log 1, "B: ".Dumper @d;
		my $b = () = $fphr =~ m/(?<!\\)\((?!\?)/g;
		#Log 1, "C: $#d".Dumper $b;
		# Wenn die klammer kein erfolg hat wird auch @d nicht gefüllt und muß manuell gefüllt werden
		if ($#d == -1) {
		for (1..$b) {
			push(@d, undef);
#			push(@d, "");
		}
		}
		push(@dir, @d);
		
		next if $m eq "?";
		$pmatch .= $m;
		$punmatch =~ s/$m//gi;
		#$cmd =~ s/$m//gi;
	} elsif ($fphr =~ /^\!/) {
		return if ($cmd =~ /$'/i);
	} elsif (my @d = ($cmd =~ /$fphr/i)){
		my $m = $&;
		$pmatch .= $m;
		$punmatch =~ s/$m//gi;
		#$cmd =~ s/$m//gi;
		# Klammerinhalt speichern wenn Klammer vorhanden
		push(@dir, @d) if $fphr =~ /(?<!\\)\((?!\?)/;
#		push(@dir, @d) if $fphr =~ /\((?!\?)/;
		
	} else {
		#T2FL($myname, 5, "$myname No hit with:\n$cmd =~ /$fphr/i");
		return;
	}
}

$$spec{match} = $pmatch;
$$spec{unmatch} = $punmatch;

return(1) unless ref $res;

T2FL($myname, 5, "Command after Phrasecheck: ".$cmd) if $cmd ne $rawcmd;
T2FL($myname, 5, "Keylists: ".Dumper @hitnokeylist);
T2FL($myname, 5, "Filled lists: ".Dumper @fphrs);
T2FL($myname, 5, "Words: ".Dumper @dir);

#$pmatch=Talk2Fhem_realtrim($pmatch);
$punmatch=Talk2Fhem_realtrim($punmatch);
T2FL($myname, 5, "Match: ".$pmatch);
T2FL($myname, 5, "Unmatch: ".$punmatch); 


#$success;
T2FL($myname, 4, "Hit with phrase: qr/$$phr{key}/i");

my %react;
%react=%{$$phr{val}};
####### TODO:
####### $[1..n,n,...] für multiple hit auswahl !!! Was ist das trennzeichen in der ausgabe?

	
	my %exec;
	my @types = ("if", "cmd","answer");
	my $mainbracket;
	foreach my $type (@types) {

		my $raw = $react{$type};
		next unless $raw;
		my $mainbracket = (sort { $b <=> $a } ($raw =~ /\$(\d+)/g))[0] unless ($mainbracket);
		my $do = $raw;
		my $dirbracket = $react{offset};
		T2FL($myname, 5, "Handle reaction $type: $raw");
		if ($raw) {
			# Suche Ersetzungsvariablen
			
			$do =~ s/\!\$\&/$punmatch/g;
			$do =~ s/\$\&/$pmatch/g;
			$do =~ s/\$DATE/$$spec{timephrase}/g;
			my $tagain = ($$spec{dir} ? "wieder" : "");
			$do =~ s/\$AGAIN/$tagain/g;
			$do =~ s/\$TIME/$lastevt/g;
			$do =~ s/\$NAME/$myname/g;
#			$do =~ s/\$ORIGIN/$$spec{origin}/g;
			$do =~ s/\$IF/$$spec{ifmatch}/g;
			
			while ($do =~ /\$(\d+)\@/) {
				my $no = $1;
				my @keywords;
				# wenn kein @array in klammer clipno
				unless ($hitnokeylist[$no]) {
					T2FL($myname, 5, "Clipnumber $no is no array! Try to extract by seperator '|'");
					my @cs = map { my @t = split('\|', $_ =~ s/^\(|\)$//gr); \@t } $$phr{key} =~ /(?<!\\)\((?!\?).*?\)/g;
					@keywords = @{$cs[($no-1)]};
					#wenn keine Liste in Klammer ist
					if ($#keywords == -1) {
						Talk2Fhem_err($myname, T2FL($myname, 1, "Clipnumber $no includes no array in '$$phr{key}!"),$res,1);
						return(0);								
					}
				} elsif ($hitnokeylist[$no]) {
					@keywords = map { Talk2Fhem_escapeumlauts($_, $disu) } @{$keylist{$hitnokeylist[$no]}};
				} 
				my $i;
				for($i=0;$i<=$#keywords;$i++){
					last if $dir[$no] =~ /^$keywords[$i]$/i;
				}
				my $k = ($$spec{dir} and ($no) == $mainbracket) ? $$spec{dir} : $keywords[$i];
				T2FL($myname, 5, "Simple bracket selection (No. $no) with Keyword $i: '$k'");
				$do =~ s/\$$no\@(?!(\[|\{|\(|\d))/$k/;
			}
			# Einfache Variablenersetzung ohne Array oder Hash
			while ($do =~ /\$(\d+)(?!(\[|\{|\(|\d))/) {
				my $r = ($$spec{dir} and ($1) == $mainbracket) ? $$spec{dir} : $dir[$1];
				T2FL($myname, 5, "Simple bracket selection (No. $1): '$r'") if $r;
				$do =~ s/\$$1(?!(\[|\{|\(|\d))/${r}/;
			}
			T2FL($myname, 4, "Replaced bracket: $raw -> $do") if $raw ne $do;


			while ($do =~ s/(.*)\$(\d+)(\[|\{|\()(.*?)(\]|\}|\))/$1###/) {
				#Klammer aus Value in Hash überführen
				my $clipno = $2;
				my $uhash = $4;
				my $utype = $3;
				T2FL($myname, 4, "Advanced bracket replacement. \$$clipno$uhash = $do");
				if ($uhash =~ /@(\w+)/) {
					if ($modlist{$1}) {
						$uhash = $`.'"'.Talk2Fhem_escapeumlauts(join('","', @{$modlist{$1}}), $disu).'"'.$' ;
						#ersetze ,, durch "","",
						# zwei mal weil immer eins zu weit geschoben wird
						#### ist noch notwendig???
						$uhash =~ s/([\[,])([,\]])/$1""$2/g;
						$uhash =~ s/([\[,])([,\]])/$1""$2/g;
						T2FL($myname, 5, "Adding modlist: ".$uhash); 
					} else {
						Talk2Fhem_err($myname, T2FL($myname, 1, "Unbekannte modwordlist in '$$phr{key}' \@$1"),$res,1);
						return(0);
					}
				}
				
				my $hash;
				if ($utype eq "[") {
					$hash = Talk2Fhem_parseArray($uhash)
				} elsif ($utype eq "{") {
					#$hash = eval($uhash)
					my $harr = Talk2Fhem_parseArray($uhash);
					for (@$harr) {
						my $h = Talk2Fhem_parseArray($_, "=>");
						$$hash{$$h[0]} = $$h[1];					
					}
				} elsif ($utype eq "(") {
				##### klappt nicht weil in while regex nicht bis zur schließenden klammer getriggert wird wenn vorher ein } oder ] kommt
					#$hash = eval($uhash);
						T2FL($myname, 1, '$n() has no function at this moment. Possible worng Syntax: '.$$phr{key});
						next;
					
				} else {
						#sollte eigentlich nie eintreffen weil auf die zeichen explizit gesucht wird
						T2FL($myname, 1, "Unkown modwordtype ($utype) in '$$phr{key}'");
						next;
				}
				#aktuelles Wort im Key auswählen
				if (($clipno-1) > $#dir) {
					T2FL($myname, 1, "Not enough clips in phrase '$$phr{key} =~ $raw'");
					next;
				}
				my $d = ($$spec{dir} and ($clipno) == $mainbracket) ? $$spec{dir} : $dir[$clipno];
				
				T2FL($myname, 4, "Keyword (".($clipno)."): '".Dumper($d)."'"); 
				
				# Wort übersetzen
				if (ref($hash) eq "HASH") {
					T2FL($myname, 5, "HASH evaluation:\n".Dumper($hash));
					#my $passed=0;
					foreach my $h (keys(%$hash)) {
						#sollte eigentlich in den syntaxcheck
						unless (defined $$hash{$h}) {
							T2FL($myname, 1, "Empty replacementstring! $h");
							#return(0);							
							next;							
						};
						next if ($h eq "else");
						unless ($h =~ /^\/.*\/$/ or defined ${$Talk2Fhem{pass}}{$h}) {
							T2FL($myname, 1, "Replacementtype unkown! $h");
							#return(0);							
							next;
						};
						
						#$passed=1;
						next if ($h eq "empty");
						next unless $d;

						my $re;
						my $fc;
						if ($h =~ /^\/(.*)\/$/) {
							$re = $1;
						} else {
							$re = ${$Talk2Fhem{pass}}{$h};
							if (ref($re) eq "HASH") {
								$fc=$$re{fc};
								$re=$$re{re};
							}
						}
						
						$re = Talk2Fhem_escapeumlauts($re, $disu);
						
						if ($d =~ qr/$re/i) {
							my $rp = $$hash{$h};
							if (ref $fc eq "CODE") {
								T2FL($myname,5,"Functionmod '$fc' $rp");
								my @res = $d =~ qr/$re/i;
								$rp = &$fc(@res);
							} elsif ($fc) {
								T2FL($myname,5,"Functionmod '$$fc' $rp");
								my $ev = eval($fc);
								$rp =~ s/$re/$ev/gi;
							}
							T2FL($myname, 5, "Word found ($h): '$d' replace with '$rp'");
							$do =~ s/###/$rp/;
							last;
						}
					}
					# empty != undef
#					if (defined($d) and $d =~ qr/${$Talk2Fhem{pass}}{empty}/ and ($$hash{empty} or (! $$hash{empty} and $$hash{else}))) {
					# empty  undef
					if (! defined($d) or $d =~ qr/${$Talk2Fhem{pass}}{empty}/) {
							#$d existiert nicht
							my $e = ($$hash{empty} || $$hash{else});
							T2FL($myname, 5, "Empty word replace with '$e'");
							$do =~ s/###/$e/;
					}					
					
					
					######### 
					if ($do =~ /###/) {
						#Vergleich fehlgeschlagen
						if ($$hash{else}) {
							T2FL($myname, 5, "Unkown word '$d' replace with '$$hash{else}'");
							$do =~ s/###/$$hash{else}/;
						} else {
							T2FL($myname, 1, "HASH Replacement Failed! $do");
							#%$res = undef; 
							#return();
						}
					}
				}
				
				if (ref($hash) eq "ARRAY") {
					my $else="";
					my $empty="";
					# keywords else und empty löschen und nächsten wert als parameter nehmen
					@$hash = grep { 
						if ("$_" eq "else") { $else = " "; 0 }
						else { if ($else eq " ") { $else = $_; 0 } 
							else { 1 } } } @$hash;
					@$hash = grep { 
						if ("$_" eq "empty") { $empty = " "; 0 }
						else { if ($empty eq " ") { $empty = $_; 0 } 
							else { 1 } } } @$hash;

					T2FL($myname, 5, "ARRAY evaluation: else: $else empty: $empty\narray: @$hash");
#					if (($d =~ qr/${$Talk2Fhem{pass}}{empty}/) and defined($d)) {
					if (($d =~ qr/${$Talk2Fhem{pass}}{empty}/) or ! defined($d)) {
						T2FL($myname, 5, "Empty word replace with! $empty");
						$do =~ s/###/$empty/;				
					} elsif (IsInt($d)) {
						unless ($$hash[$d]) {
							my $err = T2FL($myname, 3, "Field #$d doesn't exist in Array!");
							if ($else eq "") {
								Talk2Fhem_err($myname, $err, $res,1);
								return(0);
							}
						
						} else {
							T2FL($myname, 5, "Integer ($d) used for array selection! $$hash[$d]");
							$do =~ s/###/$$hash[$d]/ if $$hash[$d];
						}
					} elsif ($d) {
						my @keywords;
						# wenn kein @array in klammer clipno
						unless (defined($hitnokeylist[$clipno])) {
							T2FL($myname, 5, "Clipnumber $clipno is no array! Try to extract by seperator '|'");
							my @cs = map { my @t = split('\|', $_ =~ s/^\(|\)$//gr); \@t } $$phr{key} =~ /(?<!\\)\((?!\?).*?\)/g;
							@keywords = @{$cs[($clipno-1)]};
							#wenn keine Liste in Klammer ist
							if ($#keywords == -1) {
								Talk2Fhem_err($myname, T2FL($myname, 1, "Clipnumber $clipno includes no array or integer in '$$phr{key}!"),$res,1);
								return(0);								
							}
						} else {
							@keywords = @{$keylist{$hitnokeylist[$clipno]}};
						}
						@keywords = map { Talk2Fhem_escapeumlauts($_, $disu) } @keywords;
						T2FL($myname, 4, "Searching position of $d in @keywords");
						my $i=0;
						foreach (@keywords) {
							if ($d =~ /^$_$/i) {
								unless (defined($$hash[$i])) {
									my $err = T2FL($myname, 1, "Not enough elements in modwordlist! Position $i in (@$hash) doesn't exist.");
									if ($else eq "") {
										Talk2Fhem_err($myname, $err, $res,1);
										return(0);
									}
								} else {
									$do =~ s/###/$$hash[$i]/;
								}
							}
							$i++;
						}
					} 

					if ($do =~ /###/) {
						if ($else ne "") {
							T2FL($myname, 5, "Unkown word '$d' replace with '$else'");
							$do =~ s/###/$else/;
						} else {
							T2FL($myname, 1, "ARRAY Replacement Failed! $do");
						}
					}
				}
			}

			if ($do and ($do !~ /###/)) {
				my $result;
				#2016-01-25T02:02:00
				if ($type eq "if") {
					push(@{$$spec{ifs}}, $do);
					#push(@{$exec{$type}}, $do);
					$$cmdref = $punmatch;
					T2FL($myname, 3, "New Command after IF: ".$$cmdref);					
				} elsif ($type eq "cmd") {
					my $at;
#					$at=Talk2Fhem_mkattime($myname, ($react{offset}) ? ($lastevt+$react{offset}) : $lastevt) if ($lastevt);
					$$result{cmd} = $do;
					$$result{at} = (($react{offset}) ? ($lastevt+$react{offset}) : $lastevt) if ($lastevt);
					$$result{ifs} = $$spec{ifs} if $$spec{ifs};
					#$$spec{ifs} = undef;
					$success = 1;
					
				} elsif ($type eq "answer") {
					T2FL($myname, 4, "Answer eval: $do");
					my $answ = eval("$do");
					if (defined($answ)) {
						$result = $answ;
						#$exec{$type} = $answ;
						$success = 1;
					} else {
						Talk2Fhem_err($myname, T2FL($myname, 1, "Error in answer eval: ".$do),$res,1);
						return(0);
					}
				} elsif ($type eq "offset") { 
				} else {
					T2FL($myname, 1, "Unkown KEY $type in Commandhash");
				}
				
				T2FL($myname, 3, "Result of $type: ".Dumper $result);
				$exec{$type."s"} = $result if ($result);
				#push(@{$$res{$type."s"}}, $result) if ($result);
			} else {
				T2FL($myname, 1, "No hit on advanced bracket selection: ".($do || $raw));
				#%{$res} = undef;
				$success = undef;
				last;
			}
		}
	}
	
	
#Hier Befehle ausführen.
	
if ($success) {
for (keys %exec) {
	push(@{$$res{$_}}, $exec{$_});
}
}
return($success);
	 
} 


sub Talk2Fhem_err($$$;$) {
	my ($myname, $t, $res, $v) = @_;
	$v = 1 unless $v;
	T2FL($myname, $v, $t);
	push(@{${$res}{err}}, $t);
}

sub Talk2Fhem_escapeumlauts($;$) {

 my ($cmd, $disable) = @_;

 return($cmd) if $disable;
 (my $res = $cmd) =~ s/[äöüß]/\\S\\S?/gi;
#Umlaute sind Arschlöcher
 $res =~ s/(\\S\\S\?){2}/\\S\\S?/g;
 return($res);

}

}
sub T2FL($$$) {
Log3($_[0], $_[1], $_[2]);
	my $h = $_[0];
	$h = ref $h && $h || $defs{$h} || return;
	if ($defs{$h->{NAME}}) {
		$h->{helper}{LOG} .= $_[2]."\n";		
	}
return($_[2]);
}

1;


# Beginn der Commandref

=pod
=item helper
=item summary A RegExp based language control module
=item summary_DE Ein auf RegExp basierendes Sprachsteuerung Modul

=begin html

<a name="Talk2Fhem"></a>
<h3>Talk2Fhem</h3>
<ul>
    The module <i>Talk2Fhem</i> is a connection between natural language and FHEM commands.
	The configuration is carried out conveniently via the FHEM web frontend.<br>
	For a more detailed description and further examples see <a href="http://wiki.fhem.de/wiki/Modul_Talk2Fhem">Talk2Fhem Wiki</a>.
	<br><br>
    <a name="Talk2Fhemdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Talk2Fhem</code>
        <br><br>
        Example: <code>define talk Talk2Fhem</code>
        <br><br>
        The actual configuration should first be done on the FHEM side.
        <br><br>
		The individual language phrases are configured line by line. A configuration
		always starts by the regular expression, followed by at least one space or tab
		from an equal sign. <br>
		The command part begins after the equals sign with a space, tab, or newline. <br> <br>
        <code>&lt;regexp&gt; = &lt;command&gt;</code>
        <br><br>
        Example: <code>helo world = {Log 1, Helo World}</code>
        <br><br>
		Everything after a hashtag '#' is ignored until the end of the line.
        <br><br>
		&lt;regexp&gt;
		<ul>Regular expression describing the text at which the command should be executed</ul>
        <br><br>
		&lt;command&gt;
		<ul>
			The executive part. The following formats are allowed:
			<li>FHEM Command</li>
			<li>{Perlcode}</li>
			<li>(&lt;option&gt; =&gt; '&lt;value&gt;' , ... )</li>
			<ul>
				<br><i>&lt;option&gt;</i><br>
				<li><b>cmd</b><br>FHEM command as above</li>
				<li><b>offset</b><br>Integer value in seconds that is added at the time</li>
				<li><b>answer</b><br>Perl code whose return is written in the Reading answer</li>
			</ul>
		</ul>
		<br>
		Bracket transfer:
		<ul>
			Brackets set in the regular expression can be transferred to the command section with $1, $2, [...], $n and
			be modified. The following modification options are available here.
			<li>$n <br>Get the word straight without change.</li>
			<li>$n{&lt;type&gt; =&gt; &lt;value&gt;}<br>
			Types are:<br>
			true, false, integer, empty, else<br>
			true, false, integer, float, numeral, /&lt;regexp&gt;/, word, empty, else<br>
			<b>true</b> corresponds to: ja|1|true|wahr|ein|eins.*|auf.*|..?ffnen|an.*|rauf.*|hoch.*|laut.*|hell.*<br>
			<b>false</b> corresponds to: nein|0|false|falsch|aus.*|null|zu.*|schlie..?en|runter.*|ab.*|leise.*|dunk.*<br>
			<b>integer</b> Word is an integer<br>
			<b>float</b> Word is a float number<br>
			<b>numeral</b> Word is numeral or an integer<br>
			<b>/&lt;regexp&gt;/</b> Word is matching &lt;regexp&gt;<br>
			<b>word</b> Word contains 4 or more letters<br>
			<b>empty</b> Word Contains an empty string<br>
			<b>else</b> If none of the cases apply<br>
			If a &lt;type&gt; is identified for $n the &lt;value&gt; is beeing used.
	        Example: <code>light (\S*) = set light $1{true =&gt; on,false =&gt; off}</code>
			</li>
			<li>$n[&lt;list&gt;]<br>
			Comma separated list: [value1,value2,...,[else,value], [empty,value]] or [@modwordlist]<br>
			If $n is a number, the word at that position in &lt;list&gt; is selected.<br><br>
			If $n is a text, it searches for a list in its parenthesis in the <regexp> part. (a|b|c) or (@keywordlist)
			In this list, $n is searched for and successively positioned in &lt;list&gt; chosen for $n.
	        <br>Example: <code>light .* (kitchen|corridor|bad) (\S*) on = set $1[dev_a,dev_b,dev_c] $2{true =&gt; on,false =&gt; off}</code>
			</li>
			<li>$n@<br>The word is adopted as it is written in the list in the &lt;regexp&gt;-part.</li>
		</ul>
		<br>
		Environment variables::
		<ul>
			There are a number of variables that can be accessed in the &lt;command&gt;-part.
			<li><b>$&</b> Contains all found words </li>
			<li><b>!$&</b> Contains the rest that was not included by RegExp</li>
			<li><b>$DATE</b> Contains the time and date text of the voice </li>
			<li><b>$AGAIN</b> Contains the word again if it is a command again</li>
			<li><b>$TIME</b> Contains the found time.</li>
			<li><b>$NAME</b> Contains the devicename.</li>
			<li><b>$IF</b> Contains the text of the detected T2F_if configuration.</li>
			<li><b>$0</b> Contains the text of the detected T2F_origin regexp.</li>
		</ul>	
	</ul>
    <br>
    
    <a name="Talk2Fhemset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; [!]&lt;text&gt;</code>
        <br><br>
        The text is sent to the module via the <i>set</i> command.
		See <a href="http://fhem.de/commandref.html#set">commandref#set</a> for more help.
		<li>cleartimers</li> Removes the pending time-related commands
		<li>cleartriggers</li> Removes the pending event-related commands
    </ul>
    <br>

    <a name="Talk2Fhemget"></a>
    <b>Get</b><br>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
		Information can be read from the module via <i>get</i>.
        See <a href="http://fhem.de/commandref.html#get">commandref#get</a> for more information on "get".    <br><br>
        &lt;option&gt;
		<ul>
              <li><i>@keywordlist</i> <i>@modwordlist</i><br>
                  Compare the two lists word by word.</li>
              <li><i>keylistno</i><br>
                  A list of the configured "keyword" lists. For easier positioning of "modword" lists </li>
              <li><i>log</i><br>
                  Shows the log entries of the last command </li>
              <li><i>modificationtypes</i><br>
                  Shows the regexp of the modificationtypes. </li>
              <li><i>standardfilter</i><br>
                  Load the standartfilter and print it in the Attribute T2F_filter if its empty </li>
              <li><i>version</i><br>
                  The module version</li>
        </ul>

    <br>

	<a name="Talk2Fhemreadings"></a>
    <b>Readings</b>
    <ul>
		<li><i>set</i><br>
			Contains the last text sent via "set".
		</li>
		<li><i>cmds</i><br>
			Contains the last executed command. Is also set with disable = 1.
		</li>
		<li><i>answer</i><br>
			Contains the response text of the last command.
		</li>
		<li><i>err</i><br>
			Contains the last error message. <br>
			"No match" match with no RegExp. <br>
			"Error on Command" see FHEM log.
		</li>
		<li><i>response</i><br>
			Got the response of the fhem Command.
		</li>
		<li><i>origin</i><br>
			Contains the found string of the RegExp defined in the attribute T2F_origin.
		</li>
		<li><i>status</i><br>
			Got the status of the request.
			response, disabled, err, answers, done
		</li>
		<li><i>ifs</i><br>
			Contains the conditions at which the command will be executed.
		</li>
		<li><i>notifies</i><br>
			Contains a list of the devices that are relevant for the currently waiting conditional commands. There is an internal notify on these devices.
		</li>
    </ul>

    <br>
     
    <a name="Talk2Fhemattr"></a>
    <b>Attribute</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> for more information about the attributes.
        <br><br>
        Attributes:
        <ul>
            <li><i>T2F_keywordlist</i> &lt;name&gt; = &lt;list&gt;<br>
				A comma-separated list of keywords such as: rooms, names, colors, etc ... <br>
				In other words, things named with a natural name.            </li>
            <li><i>T2F_modwordlist</i> &lt;name&gt; = &lt;list&gt;<br>
				A comma seperated list of substitution words used for the keywords.
				For example: device names in FHEM <br>            </li>
            <li><i>T2F_if</i><br>
				A collection of event-driven configurations. The syntax is that of the definition. Command part is an IF condition. <br>
				z.B.: (when|if) .*?door = [door] eq "open"
			</li>
            <li><i>T2F_filter</i><br>
				Comma-separated list of RegExp generally removed. <br>
				Standard: \bplease\b,\balso\b
			</li>
            <li><i>T2F_origin</i><br>
				A RegExp which is generally removed and whose output can be accessed via $0. <br>
				Can be used for<user mapping.</li>
            <li><i>T2F_language</i>DE|EN<br>
				The used language can be set via the global attribute "language". Or overwritten with this attribute.
			</li>
			<li><i>T2F_disableumlautescaping</i> &lt;0|1&gt;<br>
				Disable convertimg umlauts to "\S\S?"</li>
			<li><i>disable</i> &lt;0|1&gt;<br>
				Can be used for test purposes. If the attribute is set to 1, the FHEM command is not executed
				but written in reading cmds.
            </li>
        </ul>
    </ul>
</ul>


=end html
=begin html_DE

<a name="Talk2Fhem"></a>
<h3>Talk2Fhem</h3>
<ul>
    Das Modul <i>Talk2Fhem</i> stellt eine Verbindung zwischen natürlicher Sprache und FHEM Befehlen her.
	Die Konfiguration erfolgt dabei komfortabel über das FHEM Webfrontend.<br>
	Für eine genauere Beschreibung und weiterführende Beispiele siehe  <a href="http://wiki.fhem.de/wiki/Modul_Talk2Fhem">Talk2Fhem Wiki</a>.
    <br><br>
    <a name="Talk2Fhemdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Talk2Fhem</code>
        <br><br>
        Beispiel: <code>define talk Talk2Fhem</code>
        <br><br>
        Die eigentliche Konfigration sollte erst auf der FHEM Seite erfolgen.
        <br><br>
		Die einzelnen Sprachphrasen werden Zeile für Zeile konfiguriert. Hierbei fängt eine Konfiguration
		immer mit dem Regulärem Ausdruck an, gefolgt von mindestens einem Leerzeichen oder Tabulator gefolgt
		von einem Gleichheitszeichen.<br>
		Der Kommandoteil fängt nach dem Gleichheitszeichen mit einem Leerzeichen, Tabulator oder Zeilenumbruch an.<br><br>
        <code>&lt;regexp&gt; = &lt;command&gt;</code>
        <br><br>
        Beispiel: <code>hallo welt = {Log 1, Hallo Welt}</code>
        <br><br>
		Alles nach einem Hashtag '#' wird bis zum Zeilenende ignoriert.
        <br><br>
		&lt;regexp&gt;
		<ul>Regulärer Ausdruck der den Text beschreibt, bei dem das Kommando ausgeführt werden soll</ul>
        <br><br>
		&lt;command&gt;
		<ul>
			Der ausführende Teil. Folgende Formate sind Zulässig:
			<li>FHEM Kommando</li>
			<li>{Perlcode}</li>
			<li>(&lt;option&gt; =&gt; '&lt;wert&gt;' , ... )</li>
			<ul>
				<br><i>&lt;option&gt;</i><br>
				<li><b>cmd</b><br>FHEM Kommando wie oben</li>
				<li><b>offset</b><br>Ganzzahliger Wert in Sekunden der auf den Zeitpunkt addiert wird</li>
				<li><b>answer</b><br>Perl Code dessen Rückgabe in das Reading answer geschrieben wird</li>
			</ul>
		</ul>
		<br>
		Klammerüberführung:
		<ul>
			Im Regulärem Ausdruck gesetzte Klammern können in den Kommandoteil mit $1, $2, [...], $n überführt und
			modifiziert werden. Folgende Modifizierungsmöglichkeiten stehen hierbei zur Verfügung.
			<li>$n<br>Ohne Änderung direkt das Wort überführen.</li>
			<li>$n{&lt;typ&gt; =&gt; &lt;wert&gt;}<br>
			Die Typen sind:<br>
			true, false, integer, float, numeral, /&lt;regexp&gt;/, word, empty, else<br>
			<b>true</b> entspricht: ja|1|true|wahr|ein|eins.*|auf.*|..?ffnen|an.*|rauf.*|hoch.*|laut.*|hell.*<br>
			<b>false</b> entspricht: nein|0|false|falsch|aus.*|null|zu.*|schlie..?en|runter.*|ab.*|leise.*|dunk.*<br>
			<b>integer</b> Wort enthält eine Zahl
			<b>float</b> Wort enthält eine Gleitkommazahl
			<b>numeral</b> Word ist ein Zahlenwort oder Zahl <br>
			<b>/&lt;regexp&gt;/</b> Wort entspricht der &lt;regexp&gt;
			<b>word</b> Wort enthält gleich oder mehr als 4 Zeichen
			<b>empty</b> Wort enthält eine Leere Zeichenkette
			<b>else</b> Falls keines der Fälle zutrifft
			Wird ein &lt;typ&gt; identifiziert wird für $n der &lt;wert&gt; eingesetzt<br>
	        Beispiel: <code>licht (\S*) = set light $1{true =&gt; on,false =&gt; off}</code>
			</li>
			<li>$n[&lt;list&gt;]<br>
			Kommaseparierte Liste: [wert1,wert2,...,[else,value], [empty,value]] oder [@modwordlist]<br>
			Ist $n eine Zahl, wird das Wort das an dieser Position in &lt;list&gt; steht gewählt.<br><br>
			Ist $n ein Text wird in der zugehörigen Klammer im &lt;regexp&gt;-Teil nach einer Liste gesucht. (a|b|c) oder (@keywordlist)
			In dieser Liste, wird nach $n gesucht und bei erfolg dessen Position in &lt;list&gt; für $n gewählt.
	        <br>Beispiel: <code>licht .* (küche|flur|bad) (\S*) an = set $1[dev_a,dev_b,dev_c] $2{true =&gt; on,false =&gt; off}</code>
			</li>
			<li>$n@<br>Das Wort wird so übernommen wie es in der Liste im &lt;regexp&gt;-Teil steht.</li>
		</ul>
		<br>
		Umgebungsvariablen:
		<ul>
			Es stehen eine Reihe von Variablen zur Verfügung auf die im &lt;command&gt;-Teil zugegriffen werden können.
			<li><b>$&</b> Enthält alle gefundenen Wörter</li>
			<li><b>!$&</b> Enthält den Rest der nicht von der RegExp eingeschlossen wurde</li>
			<li><b>$DATE</b> Enthält den Zeit und Datumstext des Sprachbefehls</li>
			<li><b>$AGAIN</b> Enthält das Wort wieder wenn es sich um ein wieder Kommando handelt</li>
			<li><b>$TIME</b> Enthält die erkannte Zeit.</li>
			<li><b>$NAME</b> Enthält den Devicenamen.</li>
			<li><b>$IF</b> Enthält den Text der erkannten T2F_if Konfiguration.</li>
			<li><b>$0</b> Enthält den Text der erkannten T2F_origin RegExp.</li>
		</ul>
		
	</ul>
    <br>
    
    <a name="Talk2Fhemset"></a>
    <b>Set</b><br>
    <ul>
        <code>set &lt;name&gt; [!]&lt;text&gt;</code>
        <br><br>
        Über das <i>set</i> Kommando wird der zu interpretierende Text an das Modul gesendet.
		Schaue unter <a href="http://fhem.de/commandref.html#set">commandref#set</a> für weiterführende Hilfe.
		<li>cleartimers</li> Entfernt die wartenden zeitbezogenen Kommandos 
		<li>cleartriggers</li> Entfernt die wartenden ereignisbezogenen Kommandos
    </ul>
    <br>

    <a name="Talk2Fhemget"></a>
    <b>Get</b><br>
        <code>get &lt;name&gt; &lt;option&gt;</code>
        <br><br>
        Über <i>get</i> lassen sich Informationen aus dem Modul auslesen.
        Siehe <a href="http://fhem.de/commandref.html#get">commandref#get</a> für weitere Informationen zu "get".
    <br><br>
        &lt;option&gt;
		<ul>
              <li><i>@keywordlist</i> <i>@modwordlist</i><br>
                  Vergleich der zwei Listen Wort für Wort</li>
              <li><i>keylistno</i><br>
                  Eine Auflistung der Konfigurierten "Keyword"-Listen. Zur einfacheren Positionierung der "Modword"-Listen</li>
              <li><i>log</i><br>
                  Zeigt die Logeinträge des letzten Kommandos</li>
              <li><i>modificationtypes</i><br>
                  Zeigt die RegExp der Modifikationstypen. </li>
              <li><i>standardfilter</i><br>
                  Lädt den Standardfilter und schreibt ihn in das Attribut T2F_filter wenn er leer ist</li>
              <li><i>version</i><br>
                  Die Modulversion</li>
        </ul>

    <br>

	<a name="Talk2Fhemreadings"></a>
    <b>Readings</b>
    <ul>
		<li><i>set</i><br>
			Enthält den zuletzt über "set" gesendeten Text.
		</li>
		<li><i>cmds</i><br>
			Enthält das zuletzt ausgeführte Kommando. Wird auch bei disable=1 gesetzt.
		</li>
		<li><i>answer</i><br>
			Enthält den Antworttext des letzten Befehls.
		</li>
		<li><i>err</i><br>
			Enthält die letzte Fehlermeldung.<br>
			"No match" Übereinstimmung mit keiner RegExp.<br>
			"Error on Command" siehe FHEM log.
		</li>
		<li><i>response</i><br>
			Enthällt die Rüclgabe des FHEM Befhels.
		</li>
		<li><i>origin</i><br>
			Enthält die gefundene Zeichenkette der in dem Attribut T2F_origin definierten RegExp.
		</li>
		<li><i>status</i><br>
			Enthält den Status der Ausgabe.
			response, disabled, err, answers, done
		</li>
		<li><i>ifs</i><br>
			Enthält die Bedingungen bei denen das Kommando ausgeführt werden wird.
		</li>
		<li><i>notifies</i><br>
			Enthält eine Auflistung der Devices die für die aktuell wartenden bedingten Kommandos relevant sind. Auf diesen Devices liegt ein internes notify.
		</li>
    </ul>

    <br>
    
    <a name="Talk2Fhemattr"></a>
    <b>Attribute</b>
    <ul>
        <code>attr &lt;name&gt; &lt;attribute&gt; &lt;value&gt;</code>
        <br><br>
        Siehe <a href="http://fhem.de/commandref.html#attr">commandref#attr</a> für weitere Informationen zu den Attributen.
        <br><br>
        Attribute:
        <ul>
            <li><i>T2F_keywordlist</i> &lt;name&gt; = &lt;list&gt;<br>
                Eine Komma seperierte Liste von Schlüsselwörtern wie z.B.: Räumen, Namen, Farben usw...<br>
				Mit anderen Worten, mit natürlichem Namen benannte Sachen.
            </li>
            <li><i>T2F_modwordlist</i> &lt;name&gt; = &lt;list&gt;<br>
                Eine Komma seperierte Liste von Ersetzungswörten die für die Schlüsselwörter eingesetzt werden. 
				z.B.: Gerätenamen in FHEM<br>
            </li>
            <li><i>T2F_if</i><br>
				Eine Auflistung von ereignisgesteuerten Konfigurationen. Die Syntax ist die der Definition. Kommandoteil ist eine IF Bedingung.<br>
				z.B.: wenn .*?tür = [door] eq "open"
			</li>
            <li><i>T2F_filter</i><br>
				Kommaseparierte Liste von RegExp die generell entfernt werden.<br>
				Standard: \bbitte\b,\bauch\b,\bkann\b,\bsoll\b 
			</li>
            <li><i>T2F_origin</i><br>
				Eine RegExp die generell entfernt wird und deren Ausgabe über $0 angesprochen werden kann.<br>
				Kann für eine Benutzerzuordnung verwendet werden.
			</li>
            <li><i>T2F_language</i>DE|EN<br>
				Die verwendete Sprache kann über das globale Attribut "language" gesetzt werden. Oder über dieses Attribut überschrieben werden. 
			</li>
			<li><i>T2F_disableumlautescaping</i> &lt;0|1&gt;<br>
				Deaktiviert das Konvertieren der Umlaute in "\S\S?"</li>
            <li><i>disable</i> &lt;0|1&gt;<br>
                Kann zu Testzwecken verwendet werden. Steht das Attribut auf 1, wird das FHEM-Kommando nicht ausgeführt
				aber in das Reading cmds geschrieben.
            </li>
        </ul>
    </ul>
</ul>


=end html_DE
=cut

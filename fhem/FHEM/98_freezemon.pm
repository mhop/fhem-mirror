# $Id$ 
##############################################################################
#
#     98_FreezeMon.pm
#     An FHEM Perl module that tries to combine some features of PERFMON and apptime
#
#     Copyright by KernSani
#     based on 99_PERFMON and apptime
#     
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
# 	  Changelog:
#		0.0.09:	fixed incomplete renaming of Attribute fm_freezeThreshold
#		0.0.08:	trimming of very long lines in "get freeze" 
#				start freezemon only after INITIALIZED|REREADCFG (and as late as possible)
#		0.0.07:	just for fun - added some color to "get freeze"
#				Fixed bug with uninitialized value (Thanks Micheal.Winkler)
#		0.0.06:	Code cleanup
#				Fixed bug with dayLast reading
#		0.0.05:	Experimental coding to improve bad guy detection
#				German and English documentation added		
#		0.0.04:	Added Get function to get last 20 freezes
#		0.0.03:	Added dynamic loglevel attribute fm_log
#				Added missing "isDisabled" check in define function
#				Do some checks not every second
#				Fixed PERL WARNING "uninitialized value" if no Device found 
#				minor adjustments and bugfixes
#		0.0.02:	Fixed logical issue with freezetime Attribute
#				Renamed Attributes
#				added dayLast readings 
#				fixed delete attribute "disable"	
#				fixed issue with missing svref_2object
#				minor adjustments and bugfixes
#	  	0.0.01:	initial version
##############################################################################
##############################################################################
# 	  Todo:
#	  	adjust to optimized handleTimeout
#		
# 		
# 		
##############################################################################


package main;

use strict;
use warnings;
use Data::Dumper;
use POSIX;
use Time::HiRes qw(gettimeofday);
use B qw(svref_2object);



my $version     = "0.0.09";

###################################
sub freezemon_Initialize($) {
    my ($hash) = @_;
	my $name = $hash->{NAME};
	
    # Module specific attributes
    my @freezemon_attr =
      ( "fm_forceApptime:0,1 fm_freezeThreshold disable:0,1 fm_log");

    $hash->{GetFn}    = "freezemon_Get";
    #$hash->{SetFn}    = "freezemon_Set";
    $hash->{DefFn}    = "freezemon_Define";
    $hash->{UndefFn}  = "freezemon_Undefine";
	$hash->{NotifyFn}  = "freezemon_Notify";
	$hash->{NotifyDev}  = "global";
	$hash->{NotifyOrderPrefix} = "99-"; 				# we want to be notified late.
    $hash->{AttrFn}   = "freezemon_Attr";
	$hash->{AttrList} = join( " ", @freezemon_attr ) . " " . $readingFnAttributes;
	
	
	#map new Attribute names
	$hash->{AttrRenameMap} = { "fmForceApptime:0,1" => "fm_forceApptime:0,1",
                           "fmFreezeTime" => "fm_freezeThreshold"
							};
	
}

###################################
sub freezemon_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

	RemoveInternalTimer($hash);
	
    my $usage = "syntax: define <name> freezemon";

    my ( $name, $type ) = @a;
    if ( int(@a) != 2 ) {
        return $usage;
    }

    Log3 $name, 3, "freezemon defined $name $type";

    $hash->{VERSION} = $version;
    $hash->{STATE}   = "Initialized";
	$hash->{NAME} = $name;

	# start the timer
	if (!IsDisabled($name) && $init_done) {
		my $next = int(gettimeofday()) + 1; 
		$hash->{helper}{TIMER} = $next;
		InternalTimer($next, 'freezemon_ProcessTimer', $hash, 0);
		Log3 $name, 2, "FreezeMon: $name ready to watch out for delays greater than ".AttrVal($name, "fm_freezeThreshold",1)." second(s)";
	}
	$hash->{VERSION} = $version;
    
    return undef;
}

###################################
sub freezemon_Undefine($$) {

    my ( $hash, $name ) = @_;

    RemoveInternalTimer($hash);

    return undef;
}
###################################
sub freezemon_Notify($$)
{
	my ($hash, $dev) = @_;
	my $name = $hash->{NAME}; # own name / hash
	my $events = deviceEvents($dev,1);
	
	return "" if(IsDisabled($name)); # Return without any further action if the module is disabled
	return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$events}));
  
	my $next = int(gettimeofday()) + 1; 
	$hash->{helper}{TIMER} = $next;
	InternalTimer($next, 'freezemon_ProcessTimer', $hash, 0);
	Log3 $name, 2, "FreezeMon: $name ready to watch out for delays greater than ".AttrVal($name, "fm_freezeThreshold",1)." second(s)";
 }
###################################
sub freezemon_ProcessTimer($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  #RemoveInternalTimer($hash);
  
  my $now = gettimeofday();
  my $freeze = $now - $hash->{helper}{TIMER};
  
  
  #Check Freezes
  if ($freeze > AttrVal($name, "fm_freezeThreshold",1))
  {
	my $dev = $hash->{helper}{apptime};
	my $guys = "";
	$dev //= "";
	my $start = strftime("%H:%M:%S",localtime($hash->{helper}{TIMER})); 
	my $end = strftime("%H:%M:%S",localtime($now)); 
    $freeze = int($freeze * 1000) / 1000;

	# Find the internal timers that are still in the hash
	my @olddev = split (" ",$dev);
	my @newdev = split (" ",freezemon_apptime());
	
	my %nd = map { $_ => 1 } @newdev
;
	foreach my $d (@olddev) {
		if (!exists($nd{$d})) {
			my @a = split ("-",$d);
			$guys .= $a[1]." ";
		}
	}

	$dev = $guys;
	$dev =~ s/^\s+|\s+$//g;
	if ($dev eq "") {
		$dev = "no bad guy found :-(";
	}
	# Build hash with 20 last freezes
	my @freezes = ();
	push @freezes, split(",", ReadingsVal($name,".fm_freezes",undef));
	push @freezes, "s:$start e:$end f:$freeze d:$dev";
	while (keys @freezes > 20) { 
		shift @freezes;
	}
	my $freezelist = join(",",@freezes);

	# determine relevant loglevel
	my $loglevel = 1;
	my %params = map{split /\:/, $_}(split /\ /, AttrVal($name, "fm_log", ""));
	foreach my $param (reverse sort {$a <=> $b} keys %params) {
				if ($freeze > $param) {
					$loglevel = $params{$param};
					last;
				}
			}

	Log3 $name, $loglevel, strftime("FreezeMon: $name possible freeze starting at %H:%M:%S, delay is $freeze possibly caused by $dev", localtime($hash->{helper}{TIMER}));
	my $fcDay = ReadingsVal($name,"fcDay",0)+1;
	my $ftDay = ReadingsVal($name,"ftDay",0)+$freeze;
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, ".fm_freezes", $freezelist, 1);
	readingsBulkUpdate($hash, "state", "s:$start e:$end f:$freeze d:$dev", 1);
	readingsBulkUpdate($hash, "freezeTime", $freeze, 1);
	readingsBulkUpdate($hash, "fcDay", $fcDay, 1);
	readingsBulkUpdate($hash, "ftDay", $ftDay, 1);
	readingsBulkUpdate($hash, "freezeDevice",$dev, 1);
	readingsEndUpdate($hash,1);
  }

  # ---- Some stuff not required every second
  $hash->{helper}{intCount} //= 0;
  $hash->{helper}{intCount} += 1;
  if ($hash->{helper}{intCount} >= 60) {
	$hash->{helper}{intCount} = 0;
	  Log3 $name, 5, "FreezeMon: $name Checking some stuff";

	  #Update dayLast readings if we have a new day
		my $last = ReadingsVal($name,".lastDay","");
		my $dnow = strftime("%Y-%m-%d",localtime);
		if ($last eq "") {
			readingsSingleUpdate($hash, ".lastDay", $dnow,0);
		}
		elsif ($dnow gt $last)
		{
			my $fcDay = ReadingsVal($name,"fcDay",0);
			my $ftDay = ReadingsVal($name,"ftDay",0);
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "fcDayLast", $fcDay, 1);
			readingsBulkUpdate($hash, "ftDayLast", $ftDay, 1);
			readingsBulkUpdate($hash, "fcDay", 0, 1);
			readingsBulkUpdate($hash, "ftDay", 0, 1);
			readingsBulkUpdate($hash, ".lastDay", $dnow, 1);
			readingsEndUpdate($hash,1);
		}

	  if (AttrVal($name,"fm_forceApptime",0) ==1 and !defined($cmds{"apptime"})) {
		fhem("apptime",1);
		}
	}
  # start next timer
  $hash->{helper}{fn} = "";
  $hash->{helper}{apptime} = freezemon_apptime();
  $hash->{helper}{TIMER} = int($now) + 1;
  InternalTimer($hash->{helper}{TIMER}, 'freezemon_ProcessTimer', $hash, 0);
}

###################################
sub freezemon_Get($@) {
    my ( $hash, @a ) = @_;
    my $name  = $hash->{NAME};
    my $state = $hash->{STATE};
	my $ret = "";
    return "No Argument given" if ( !defined( $a[1] ) );
	
	Log3 $name, 5,
      "freezemon $name: called function freezemon_Get() with " . Dumper(@a);

    my $usage =
      "Unknown argument " . $a[1] . ", choose one of freeze:noArg";
    my $error = undef;

    # Get freeze entries
    if ( $a[1] eq "freeze" ) {
		my @colors = ("red","yellow","green","white","gray");
		my @freezes =  split(",", ReadingsVal($name,".fm_freezes",""));
		foreach (@freezes) {
			my $loglevel = 1;
			my $freeze = $_;
			if ($freeze =~ /f:(.*)d:/) {
				$freeze = $1;
			}
			my %params = map{split /\:/, $_}(split /\ /, AttrVal($name, "fm_log", ""));
			foreach my $param (reverse sort {$a <=> $b} keys %params) {
				if ($freeze > $param) {
					$loglevel = $params{$param};
					last;
				}
			}
			$_ =~s/(?<=.{160}).{1,}$/.../;
			$ret .= "<font color='$colors[$loglevel-1]'><b>".$loglevel."</b></font> - ".$_."<br>";
		}
		return $ret;
    }

    # return usage hint
    else {
        return $usage;
    }
    return $error;
}
###################################
sub freezemon_Attr($) {

    my ( $cmd, $name, $aName, $aVal ) = @_;
	my $hash = $defs{$name};
    # $cmd can be "del" or "set"
    # $name is device name
    # aName and aVal are Attribute name and value
	Log3 $name, 3, "$cmd $aName $aVal";
    if ( $cmd eq "set" ) {

        
        if ( $aName eq "fm_forceApptime" ) {
            if ( $aVal > 1 or $aVal < 0 ) {
                Log3 $name, 3,
                  "$name: $aName is either 0 or 1: $aVal";
                return "Attribute " . $aName
                  . " is either 0 or 1";
            }
        }
		if ( $aName eq "fm_freezeThreshold" ) {
			if (!looks_like_number($aVal) ) {
				return "Attribute " . $aName. " has to be a number (seconds) ";
			}
		}
		if ( $aName eq "fm_freezeThreshold" ) {
			
		}
		
		if ( $aName eq "disable" ) {
			if ($aVal == 1) {
				RemoveInternalTimer($hash);
				$hash->{helper}{DISABLED} = 1;
				readingsSingleUpdate($hash, "state", "disabled",1);
			}
			elsif ($aVal == 0)  {
				readingsSingleUpdate($hash, "state", "initialized",0) if(exists($hash->{helper}{DISABLED}) and $hash->{helper}{DISABLED} == 1);
				$hash->{helper}{DISABLED} = 0;
				my $next = int(gettimeofday()) + 1;
				$hash->{helper}{TIMER} = $next;
				InternalTimer($hash->{helper}{TIMER}, 'freezemon_ProcessTimer', $hash, 0);
			}

		}
	}
	elsif ( $cmd eq "del" ) {
		if ( $aName eq "disable" ) {
			readingsSingleUpdate($hash, "state", "initialized",0) if(exists($hash->{helper}{DISABLED}) and $hash->{helper}{DISABLED} == 1);
			$hash->{helper}{DISABLED} = 0;
			my $next = int(gettimeofday()) + 1;
			$hash->{helper}{TIMER} = $next;
			InternalTimer($hash->{helper}{TIMER}, 'freezemon_ProcessTimer', $hash, 0);
		}
    }

    return undef;
	
}	


###################################
# Helper Functions                #
###################################
sub freezemon_apptime() {
my @intAtKeys = keys(%intAt);
my $now = gettimeofday();
my $minCoverExec = 10;     					# Let's see if we can find more if we look ahead further
my $minCoverWait = 0.00;
my $ret = "";

  my @intAtSort = (sort {$intAt{$a}{TRIGGERTIME} <=>
                         $intAt{$b}{TRIGGERTIME} }
                    (grep {($intAt{$_}->{TRIGGERTIME}-$now) <= $minCoverExec}
                       @intAtKeys)); # get the timers to execute due to timeout and sort ascending by time
my ($fn,$tim,$cv,$fnname,$arg, $shortarg);
			   
foreach my $i (@intAtSort) {
    $tim = $intAt{$i}{TRIGGERTIME};
    if ($tim - gettimeofday() > $minCoverWait) {
		#next;
    }
	if ($intAt{$i}{FN} eq "freezemon_ProcessTimer") {
		next;
	}
	
	$fn = $intAt{$i}{FN};
	if (ref($fn) ne "") {
      $cv = svref_2object($fn);
      $fnname = $cv->GV->NAME;
	  $ret .= $intAt{$i}{TRIGGERTIME}."-".$fnname;
    }
	else {
		$ret .= $intAt{$i}{TRIGGERTIME}."-".$fn;
	}
	 $arg = $intAt{$i}{ARG};
	
	 $shortarg = (defined($arg)?$arg:"");
	 if (ref($shortarg) eq "HASH") {
		 if (!defined($shortarg->{NAME})) {
		 $shortarg = "N/A";
		 }
		 else {
		 $shortarg = $shortarg->{NAME};
		 }
	 }
	 ($shortarg,undef) = split(/:|;/,$shortarg,2);
	 $ret.= "(".$shortarg.") ";
}
if(%prioQueues) {
    my $nice = minNum(keys %prioQueues);
    my $entry = shift(@{$prioQueues{$nice}});
    
    $cv = svref_2object($entry->{fn});
    $fnname = $cv->GV->NAME;
	$ret .= $fnname;
    $shortarg = (defined($entry->{arg})?$entry->{arg}:"");
	if (ref($shortarg) eq "HASH") {
		 if (!defined($shortarg->{NAME})) {
		 $shortarg = "N/A";
		}
		else {
		 $shortarg = $shortarg->{NAME};
		}
	}
    ($shortarg,undef) = split(/:|;/,$shortarg,2);
	$ret.= "(".$shortarg.") ";
	}
	
	return $ret;
}

 
=pod
=item helper
=item summary An adjusted version of PERFMON that helps detecting freezes
=item summary_DE Eine angepasste Version von PERFMON, die beim Erkennen von freezes hilft
=begin html

<a name="freezemon"></a>
<h3>freezemon</h3>
<div>
	<ul>
		FREEZEMON monitors - similar to PERFMON possible freezes, however FREEZEMON is a real module, hence it has:<br><br>
		<ul>
			<li>Readings - which might be logged for easier analysis</li>
			<li>Attributes - to influence the behaviour of the module</li>
			<li>additional functionality - which tries to identify the device causing the freeze</li>
		</ul>
		It's recommended to deactivate PERFMON once FREEZEMON is active. They anyways detect the same freezes thus everything would be duplicated.<br><br>
		<b>Please note!</b> FREEZEMON just does an educated guess, which device could have caused the freeze based on timers that were supposed to run. There might be a lot of other factors (internal or external) causing freezes. FREEZEMON doesn't replace a more detailed analysis. The module just tries to give you some hints what could be optimized.<br><br>
<a name="freezemonDefine"></a>
  <b>Define</b>
  <ul>
	FREEZEMON will be defined without Parameters.
	<br><br>
	<code>define &lt;devicename&gt; freezemon</code><br><br>
	With that freezemon is active (and you should see a message in the log) <br><br>
  </ul>
  <a name="freezemonSet"></a>
  <b>Set</b>
  <ul>
  Currently no SET commands are supported.<br><br>
  </ul>	
<a name="freezemonGet"></a>
  <b>Get</b>
  <ul>
  freeze: returns the last 20 (in compact view, like in state) - This is for a quick overview. For detailed analysis the data should be logged.<br><br>
  </ul>
  
 <a name="freezemonReadings"></a>
  <b>Readings</b>
		<ul>
			<ul>
				<li>freezeTime: Duration of the freeze</li>
				<li>freezeDevice: List of functions(Devices) that possibly caused the freeze</li>
				<li>fcDay: cumulated no. of freezes per day</li>
				<li>ftDay: cumulated duration of freezes per day</li>
				<li>fcDayLast: stores cumulated no. of freezes of the last day (for daily plots)</li>
				<li>fcDayLast: stores cumulated duration of freezes of the last day (for daily plots)</li>
				<li>state: s:<startTime> e:<endTime> f:<Duration> d:<Devices></li>
			</ul>
		</ul>

<a name="freezemonAttributes"></a>
  <b>Attributes</b>
		<ul>
			<ul>
				<li>fm_freezeThreshold: Value in seconds (Default: 1) - Only freezes longer than fm_freezeThreshold will be considered as a freeze</li>
				<li>fm_forceApptime: When FREEZEMON is active, apptime will automatically be started (if not yet active)</li>
				<li>fm_log: dynamic loglevel, takes a string like 10:1 5:2 1:3 , which means: freezes > 10 seconds will be logged with loglevel 1 , >5 seconds with loglevel 2 etc...</li>
				<li>disable: activate/deactivate freeze detection</li>
			</ul>
		</ul>
	</ul>
</div>

=end html

=begin html_DE

<a name="freezemon"></a>
	<h3>freezemon</h3>
	<div>
	<ul>
		FREEZEMON überwacht - ähnlich wie PERFMON mögliche Freezes, allerdings ist FREEZEMON ein echtes Modul und hat daher:<br>
		<ul>
		<li>Readings - die geloggt werden können und damit viel einfacher ausgewertet werden können</li>
		<li>Attribute - mit denen das Verhalten von freezemon beeinflusst werden kann</li>
		<li>zusätzliche Funktionalität - die versucht das den Freeze verursachende Device zu identifizieren</li>
		</ul>
		Ich würde empfehlen, PERFMON zu deaktivieren, wenn FREEZEMON aktiv ist, da beide auf die selbe Art Freezes erkennen und dann nur alles doppelt kommt.
		<b>Bitte beachten!</b> FREEZEMON versucht nur intelligent zu erraten, welches Device einen freeze verursacht haben könnte (basierend auf den Timern die laufen sollten). Es gibt eine Menge anderer Faktoren (intern oder extern) die einen Freeze verursachen können. FREEZEMON ersetzt keine detaillierte Analyse. Das Modul versucht nur Hinweise zu geben, was optimiert werden könnte.<br><br>
		<br>
		<br>
	<a name="freezemonDefine"></a>
	<b>Define</b>
	<ul>
		FREEZEMON wird ohne Parameter definiert.<br><br>
		<code>define &lt;devicename&gt; freezemon</code><br><br>
		damit ist der Freezemon aktiv (im Log sollte eine entsprechende Meldung geschrieben werden)
		<br><br>
	</ul>
  <a name="freezemonSet"></a>
  <b>Set</b>
  <ul>
	Derzeit gibt es keine SET Kommandos<br><br>
  </ul>	
  <a name="freezemonGet"></a>
  <b>Get</b>
  <ul>
  freeze: gibt die letzten 20 freezes zurück (in Kompakter Darstellung, wie im state) - Dies dient einem schnellen Überblick, für detailliertere Auswertungen empfehle ich die Daten zu loggen.<br><br>
  </ul>

  <a name="freezemonReadings"></a>
  <b>Readings</b>
  <ul>
		<ul>
			<li>freezeTime: Dauer des Freezes</li>
			<li>freezeDevice: Liste von möglicherweise den Freeze auslösenden Funktionen(Devices)</li>
			<li>fcDay: kumulierte Anzahl der Freezes pro Tag</li>
			<li>ftDay: kumulierte Dauer der Freezes pro Tag </li>
			<li>fcDayLast: speichert die kumulierte Anzahl der Freezes des vergangenen Tages (um tageweise plots zu erstellen)</li>
			<li>fcDayLast: speichert die kumulierte Dauer der Freezes des vergangenen Tages (um tageweise plots zu erstellen)</li>
			<li>state: s:<StartZeit> e:<EndeZeit>f:<Dauer> d:<Devices></li>
		</ul>
  </ul>

<a name="freezemonAttributes"></a>
  <b>Attribute</b>
  <ul>
		<ul>
			<li>fm_freezeThreshold: Wert in Sekunden (Default: 1) - Nur Freezes länger als fm_freezeThreshold werden als Freeze betrachtet </li>
			<li>fm_forceApptime: Wenn FREEZEMON aktiv ist wird automatisch apptime gestartet (falls nicht aktiv)</li>
			<li>fm_log: dynamischer Loglevel, nimmt einen String der Form 10:1 5:2 1:3 entgegen, was bedeutet: Freezes > 10 Sekunden werden mit Loglevel 1 geloggt, >5 Sekunden mit Loglevel 2 usw...</li>
			<li>disable: aktivieren/deaktivieren der Freeze-Erkennung</li>
		</ul>
  </ul>
</ul>
</div>

=end html_DE
=cut


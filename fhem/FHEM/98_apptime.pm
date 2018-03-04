################################################################
# 98_apptime:application timing
# $Id$
# based on $Id$
################################################################

# for use with fhem.pl 16214+ due to change in timers

#####################################################
#
package main;

use strict;
use warnings;
use B qw(svref_2object);

use vars qw(%defs);		# FHEM device/button definitions
use vars qw(%intAt);
use vars qw($nextat);
use vars qw(@intAtA);   # Internal timer array (new!)
use vars qw(%prioQueues);     

sub apptime_getTiming($$$@);
sub apptime_Initialize($);

use constant DEBUG_OUTPUT_INTATA => 0;

my $apptimeStatus;

sub apptime_Initialize($){
  $apptimeStatus  = 1;#set active by default

  $cmds{"apptime"}{Fn} = "apptime_CommandDispTiming";
  $cmds{"apptime"}{Hlp} = "[clear|<field>|timer|nice] [top|all] [<filter>],application function calls and duration";
}

my $intatlen       = 0;
my $maxintatlen    = 0;
my $maxintatdone   = 0;
my $minTmrHandleTm = 1000000;
my $maxTmrHandleTm = 0;

my $totDly         = 0;
my $totCnt         = 0;

sub HandleTimeout() {
  return undef if(!$nextat);

  if (DEBUG_OUTPUT_INTATA) {
    my $ms = 0;
    my $n = int(@intAtA);
    my $j;
    for ($j=0; $j < ($n-1); $j++) {
      if (!defined($intAtA[$j])) {
        Log 0, "Error in intAtA, undefined element $j/$n\n";
      }
      elsif (!defined($intAtA[$j]->{TRIGGERTIME})) {
        Log 0, "Error in intAtA, undefined tim $j/$n\n";
      }
      next if ($intAtA[$j]->{TRIGGERTIME} <= $intAtA[$j+1]->{TRIGGERTIME});
      if (!$ms) {
        Log 0, "Error in intAtA, sortErr $j/$n\n";
        $ms = 1;
      }
    }
    $j = $n-1;
    if (!defined($intAtA[$j])) {
      Log 0, "Error in intAtA, undefined element $j/$n\n";
    }
    elsif (!defined($intAtA[$j]->{TRIGGERTIME})) {
      Log 0, "Error in intAtA, undefined tim $j/$n\n";
    }
  }

  my $now = gettimeofday();
  if($now < $nextat) {
    $selectTimestamp = $now;
    return ($nextat-$now);
  }

  my $handleStart = $now;

  #############
  # Check the internal list.
  $intatlen = int(@intAtA);
  $maxintatlen = $intatlen if ($maxintatlen < $intatlen);

  my $nd = 0;

  my ($fn,$arg,$fnname,$shortarg,$cv);
  $nextat = 0;
  while(@intAtA) { # may be changed by timer execution !
    my $at = $intAtA[0];
    my $tim = $at->{TRIGGERTIME};
    if($tim && $tim > $now) {
      $nextat = $tim;
      last;
    }
    delete $intAt{$at->{atNr}} if($at->{atNr}); # "handling" of old %intAt
    shift(@intAtA);

    $fn = $at->{FN};
    $fnname = $fn;
    if (ref($fn) ne "") {
      $cv = svref_2object($fn);
      $fnname = $cv->GV->NAME;
    }
    $arg = $at->{ARG};
    $shortarg = (defined($arg)?$arg:"");
    $shortarg = "HASH_unnamed" if (   (ref($shortarg) eq "HASH")
                                   && !defined($shortarg->{NAME}) );
    ($shortarg,undef) = split(/:|;/,$shortarg,2); # for special long args with delim ;
    apptime_getTiming("global","tmr-".$fnname.";".$shortarg, $fn, $tim, $arg); # this can delete a timer and can add a timer
    $nd++;

  }

  $maxintatdone = $nd if ($maxintatdone < $nd);

  $now = gettimeofday();

  if(%prioQueues) {
    my $nice = minNum(keys %prioQueues);
    my $entry = shift(@{$prioQueues{$nice}});
    delete $prioQueues{$nice} if(!@{$prioQueues{$nice}});

    $cv = svref_2object($entry->{fn});
    $fnname = $cv->GV->NAME;
    $shortarg = (defined($entry->{arg})?$entry->{arg}:"");
    $shortarg = "HASH_unnamed" if (   (ref($shortarg) eq "HASH")
                                   && !defined($shortarg->{NAME}) );
    ($shortarg,undef) = split(/:|;/,$shortarg,2);
    apptime_getTiming("global","nice-".$fnname.";".$shortarg, $entry->{fn}, $now, $entry->{arg});

    $nextat = 1 if(%prioQueues);
  }

  $now = gettimeofday(); # if some callbacks took longer
  $selectTimestamp = $now;

  $handleStart = $now - $handleStart;
  $minTmrHandleTm = $handleStart if ($minTmrHandleTm > $handleStart);
  $maxTmrHandleTm = $handleStart if ($maxTmrHandleTm < $handleStart);

  return undef if !$nextat;
 
  return ($now < $nextat) ? ($nextat-$now) : 0;
}
sub CallFn(@) {
  my $d = shift;
  my $n = shift;

  if(!$d || !$defs{$d}) {
    $d = "<undefined>" if(!defined($d));
    Log 0, "Strange call for nonexistent $d: $n";
    return undef;
  }
  if(!$defs{$d}{TYPE}) {
    Log 0, "Strange call for typeless $d: $n";
    return undef;
  }
  my $fn = $modules{$defs{$d}{TYPE}}{$n};
  return "" if(!$fn);
 
  my @ret = apptime_getTiming($d,$fn,$fn,0,@_);

  if(wantarray){return @ret;}
  else         {return $ret[0];}
}

sub apptime_getTiming($$$@) {
  my ($e,$fnName,$fn,$tim,@arg) = @_;
  my $h;
  my $ts1;
  if ($apptimeStatus){
    if (!$defs{$e}{helper} ||
        !$defs{$e}{helper}{bm} ||
        !$defs{$e}{helper}{bm}{$fnName} ){
   
      %{$defs{$e}{helper}{bm}{$fnName}} =(max => 0, mAr => "",
                                          cnt => 1, tot => 0,
                                          dmx => -1000, dtotcnt => 0, dtot => 0,
                                          mTS => "");
   
      $h = $defs{$e}{helper}{bm}{$fnName};
    }
    else{
      $h = $defs{$e}{helper}{bm}{$fnName};
      $h->{cnt}++;
    }
    $ts1 = gettimeofday();
    if ($tim > 1){
      my $td = $ts1-$tim;
      $totCnt++;
      $totDly    += $td;
      $totDly    = 0 if(!$totCnt);
      $h->{dtotcnt}++;
      $h->{dtot} += $td;
      $h->{dtot} = 0 if(!$h->{dtotcnt});
      $h->{dmx}  = $td if ($h->{dmx} < $td);
    }
  }

  no strict "refs";
  my @ret = &{$fn}(@arg);
  use strict "refs";

  if ($apptimeStatus){
    $ts1 = gettimeofday()-$ts1;
    if ($ts1 && $h->{max} < $ts1){
      $h->{max} = $ts1;
      $h->{mAr} = @arg?\@arg:undef;
      $h->{mTS}= strftime("%d.%m. %H:%M:%S", localtime());
    }
   
    $h->{tot} += $ts1;
    $h->{tot} = 0 if(!$h->{cnt});
  }
  return @ret;
}

#####################################
sub apptime_CommandDispTiming($$@) {
  my ($cl,$param) = @_;
  my ($sFld,$top,$filter) = split" ",$param;
  $sFld = "max" if (!$sFld);
  $top = "top" if (!$top);
  my %fld = (name=>0,function=>1,max=>2,count=>3,total=>4,average=>5,maxDly=>6,avgDly=>7,cont=>98,pause=>98,clear=>99,timer=>2,nice=>2);
  return "$sFld undefined field, use one of ".join(",",sort keys %fld)
        if(!defined $fld{$sFld});
  my @bmArr;
  my @a = map{"$defs{$_}:$_"} keys (%defs); # prepare mapping hash 2 name
  $_ =~ s/[HASH\(\)]//g foreach(@a);
 
  if    ($sFld eq "pause"){# no further collection of data, clear also
    $apptimeStatus  = 0;#stop collecting data
  }
  elsif ($sFld eq "cont") {# further collection of data, clear also
    $apptimeStatus  = 1;#continue collecting data
  }
  elsif ($sFld eq "timer"){
    $sFld = "max";
    $filter = defined($filter)?$filter:"";
    $filter = "\^tmr-.*".$filter if ($filter !~ /^\^tmr-/);
  }
  elsif ($sFld eq "nice") {
    $sFld = "max";
    $filter = defined($filter)?$filter:"";
    $filter = "\^nice-.*".$filter if ($filter !~ /^\^nice-/);
  }

  foreach my $d (sort keys %defs) {
    next if(!$defs{$d}{helper}||!$defs{$d}{helper}{bm});
    if ($sFld eq "clear"){
      delete $defs{$d}{helper}{bm};
      $totDly         = 0;
      $totCnt         = 0;
      $maxintatlen    = 0;
      $maxintatdone   = 0;
    }
    elsif ($sFld =~ m/(pause|cont)/){
    }
    else{
      foreach my $f (sort keys %{$defs{$d}{helper}{bm}}) {
        next if(!defined $defs{$d}{helper}{bm}{$f}{cnt} || !$defs{$d}{helper}{bm}{$f}{cnt});
        next if($filter && $d !~ m/$filter/ && $f !~ m/$filter/);
        my ($n,$t) = ($d,$f);
        ($n,$t) = split(";",$f,2) if ($d eq "global");
        $t = "" if (!defined $t);
        my $h = $defs{$d}{helper}{bm}{$f};
     
        my $arg = "";
        if ($h->{mAr} && scalar(@{$h->{mAr}})){
          foreach my $i (0..scalar(@{$h->{mAr}})){
            if(ref(${$h->{mAr}}[$i]) eq 'HASH' and exists(${$h->{mAr}}[$i]->{NAME})){
              ${$h->{mAr}}[$i] = "HASH(".${$h->{mAr}}[$i]->{NAME}.")";
            }
          }
          $arg = join ("; ", map { $_ // "(undef)" } @{$h->{mAr}});
         }
     
        push @bmArr,[($n,$t
                     ,$h->{max}*1000
                     ,$h->{cnt}
                     ,$h->{tot}*1000
                     ,($h->{cnt}?($h->{tot}/$h->{cnt})*1000:0)
                     ,(($h->{dmx}>-1000)?$h->{dmx}*1000:0)
                     ,($h->{dtotcnt}?($h->{dtot}/$h->{dtotcnt})*1000:0)
                     ,$h->{mTS}
                     ,$arg
                    )];
      }
    }
  }

  return "apptime initialized\n\nUse apptime ".$cmds{"apptime"}{Hlp} if ($maxTmrHandleTm < $minTmrHandleTm);

  my $field = $fld{$sFld};
  if ($field>1){@bmArr = sort { $b->[$field] <=> $a->[$field] } @bmArr;}
  else         {@bmArr = sort { $b->[$field] cmp $a->[$field] } @bmArr;}
  my $ret = sprintf("active-timers: %d; max-active timers: %d; max-timer-load: %d  ",$intatlen,$maxintatlen,$maxintatdone);
  $ret .= sprintf("min-tmrHandlingTm: %0.1fms; max-tmrHandlingTm: %0.1fms; totAvgDly: %0.1fms\n",$minTmrHandleTm*1000,$maxTmrHandleTm*1000,($totCnt?$totDly/$totCnt*1000:0));
  $ret .= ($apptimeStatus ? "" : "------ apptime PAUSED data collection ----------\n")
            .sprintf("\n %-40s %-35s %6s %8s %10s %8s %8s %8s %-15s %s",
                     "name","function","max","count","total","average","maxDly","avgDly","TS Max call","param Max call");
  my $end = ($top && $top eq "top")?40:@bmArr-1;
  $end = @bmArr-1 if ($end>@bmArr-1);

  $ret .= sprintf("\n %-40s %-35s %6d %8d %10.2f %8.2f %8.2f %8.2f %-15s %s",@{$bmArr[$_]})for (0..$end);
  return $ret;
}

1;
=pod
=item command
=item summary    support to analyse function performance
=item summary_DE Unterst&uuml;tzung bei der Performanceanalyse von Funktionen
=begin html

<a name="apptime"></a>
<h3>apptime</h3>
<div style="padding-left: 2ex;">
  <h4><code>apptime</code></h4>
    <p>
        apptime provides information about application procedure execution time.
        It is designed to identify long running jobs causing latency as well as
        general high <abbr>CPU</abbr> usage jobs.
    </p>
    <p>
        No information about <abbr>FHEM</abbr> kernel times and delays will be provided.
    </p>
    <p>
        Once started, apptime  monitors tasks. User may reset counter during operation.
        apptime adds about 1% <abbr>CPU</abbr> load in average to <abbr>FHEM</abbr>.
    </p>
    <p>
        In order to remove apptime, <kbd>shutdown restart</kbd> is necessary.
    </p>
    <p>
        <strong>Features</strong>
    </P>
    <dl>
      <dt><code><kbd>apptime</kbd></code></dt>
        <dd>
            <p>
              <kbd>apptime</kbd> is started with the its first call and continously monitor operations.<br>
              To unload apptime, <kbd>shutdown restart</kbd> is necessary.<br> </li>
            </p>
        </dd>
      <dt><code><kbd>apptime clear</code></dt>
          <dd>
            <p>
                Reset all counter and start from zero.
            </p>
          </dd>
      <dt><code><kbd>apptime pause</code></dt>
          <dd>
            <p>
                Suspend accumulation of data. Data is not cleared.
            </p>
          </dd>
      <dt><code><kbd>apptime cont</code></dt>
          <dd>
            <p>
                Continue data collection after pause.
            </p>
          </dd>
      <dt><code><kbd>apptime [count|function|average|clear|max|name|total] [all]</kbd></code></dt>
        <dd>
            <p>
                Display a table sorted by the field selected.
            </p>
            <p>
                <strong><kbd>all</kbd></strong> will display the complete table while by default only the top lines are printed.<
            </p>
        </dd>
    </dl>
    <p>
        <strong>Columns:</strong>
    </p>
    <dl>
      <dt><strong>name</strong></dt>
        <dd>
            <p>
                Name of the entity executing the procedure.
            </p>
            <p>
                If it is a function called by InternalTimer the name starts with <var>tmr-</var>.
                By then it gives the name of the function to be called.
            </p>
        </dd>
      <dt><strong>function</strong><dt>
          <dd>
            <p>
                Procedure name which was executed.
            </p>
            <p>
                If it is an <var>InternalTimer</var> call it gives its calling parameter.
            </p>
          </dd>
      <dt><strong>max</strong></dt>
        <dd>
            <p>
                Longest duration measured for this procedure in <abbr>ms</abbr>.
            </p>
        </dd>
      <dt><strong>count</strong></dt>
        <dd>
            <p>
                Number of calls for this procedure.
            </p>
        </dt>
      <dt><strong>total</strong></dt>
        <dd>
            <p>
                Accumulated duration of this procedure over all calls monitored.
            </p>
        </dd>
      <dt><strong>average</strong></dt>
        <dd>
            <p>
                Average time a call of this procedure takes.
            </p>
        </dd>
      <dt><strong>maxDly</strong></dt>
        <dd>
            <p>
                Maximum delay of a timer call to its schedules time.
                This column is not relevant for non-timer calls.
            </p>
        </dd>
      <dt><strong>param Max call</strong></dt>
        <dd>
            <p>
                Gives the parameter of the call with the longest duration.
            </p>
        </dd>
    </dl>
</div>

=end html
=cut

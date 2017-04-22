################################################################
# 98_apptime:application timing 
# $Id$
################################################################

#####################################################
# 
package main;

use strict;
use warnings;

use vars qw(%defs);		# FHEM device/button definitions
use vars qw(%intAt);
use vars qw($nextat);

sub apptime_Initialize($);
my $apptimeStatus;
sub apptime_Initialize($){
  $apptimeStatus  = 1;#set active by default

  $cmds{"apptime"}{Fn} = "apptime_CommandDispTiming";
  $cmds{"apptime"}{Hlp} = "[clear|<field>] [top|all] [<filter>],application function calls and duration";
}

sub HandleTimeout() {
  return undef if(!$nextat);

  my $now = gettimeofday();
  return ($nextat-$now) if($now < $nextat);

  $now += 0.01;# need to cover min delay at least
  $nextat = 0;
  #############
  # Check the internal list.
  foreach my $i (sort { $intAt{$a}{TRIGGERTIME} <=>
                        $intAt{$b}{TRIGGERTIME} } keys %intAt) {
    my $tim = $intAt{$i}{TRIGGERTIME};
    my $fn = $intAt{$i}{FN};
    if(!defined($tim) || !defined($fn)) {
      delete($intAt{$i});
      next;
    } elsif($tim <= $now) {
      my $arg = $intAt{$i}{ARG};
      $arg = "" if (!$arg);
      
      apptime_getTiming("global","tmr-".$fn.";".$arg,$fn,$tim,$arg);

      delete($intAt{$i});
    } else {
      $nextat = $tim if(!$nextat || $nextat > $tim);
	}
  }

  return undef if(!$nextat);
  $now = gettimeofday(); # possibly some tasks did timeout in the meantime
                         # we will cover them 
  return ($now+ 0.01 < $nextat) ? ($nextat-$now) : 0.01;
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
    
      %{$defs{$e}{helper}{bm}{$fnName}} =(max =>0, mAr =>"",
                                          cnt =>1, tot =>0,
                                          dmx =>0);
    
      $h = $defs{$e}{helper}{bm}{$fnName};
    }
    else{
      $h = $defs{$e}{helper}{bm}{$fnName};
      $h->{cnt}++;
    }
    $ts1 = gettimeofday();
    if ($tim){
      my $td = int(($ts1-$tim)*1000);
      $h->{dmx} = $td if ($h->{dmx} < $td);
    }
  }

  no strict "refs";
  my @ret = &{$fn}(@arg);
  use strict "refs";

  if ($apptimeStatus){
    $ts1 = int((gettimeofday()-$ts1)*1000);
    if ($ts1 && $h->{max} < $ts1){
      $h->{max} = $ts1;
      $h->{mAr} = \@arg;
    }
    
    $h->{tot} += $ts1;
  }
  return @ret;
}

#####################################
sub apptime_CommandDispTiming($$@) {
  my ($cl,$param) = @_;
  my ($sFld,$top,$filter) = split" ",$param;
  $sFld = "max" if (!$sFld);
  $top = "top" if (!$top);
  my %fld = (name=>0,funktion=>1,max=>2,count=>3,total=>4,average=>5,maxDly=>6,cont=>98,pause=>98,clear=>99);
  return "$sFld undefined field, use one of ".join(",",keys %fld) 
        if(!defined $fld{$sFld});
  my @bmArr;
  my @a = map{"$defs{$_}:$_"} keys (%defs); # prepare mapping hash 2 name
  $_ =~ s/[HASH\(\)]//g foreach(@a);
  
  if ($sFld eq "pause"){# no further collection of data, clear also
    $apptimeStatus  = 0;#stop collecting data
  }
  elsif ($sFld eq "cont"){# no further collection of data, clear also
    $apptimeStatus  = 1;#continue collecting data
  }

  foreach my $d (sort keys %defs) {
    next if(!$defs{$d}{helper}||!$defs{$d}{helper}{bm});
    if ($sFld eq "clear"){
      delete $defs{$d}{helper}{bm};
    }
    elsif ($sFld =~ m/(pause|cont)/){
    }
    else{
      foreach my $f (sort keys %{$defs{$d}{helper}{bm}}) {
        next if(!defined $defs{$d}{helper}{bm}{$f}{cnt});
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
          $arg = join ("; ",@{$h->{mAr}});
        }
      
        push @bmArr,[($n,$t
                     ,$h->{max}
                     ,$h->{cnt}
                     ,$h->{tot}
                     ,$h->{tot} /$h->{cnt}
                     ,$h->{dmx}
                     ,$arg
                    )];
      }
    }
  }
  my $field = $fld{$sFld};
  if ($field>1){@bmArr = sort { $b->[$field] <=> $a->[$field] } @bmArr;}
  else         {@bmArr = sort { $b->[$field] cmp $a->[$field] } @bmArr;}
  my $ret = ($apptimeStatus ? "" : "------ apptime PAUSED data collection ----------\n")
            .sprintf("\n %35s %20s %6s %6s %8s %8s %s",
                     "name","function","max","count","total","average","maxDly","param Max call");
  my $end = ($top && $top eq "top")?20:@bmArr-1;
  $end = @bmArr-1 if ($end>@bmArr-1);

  $ret .= sprintf("\n %35s %20s %6d %6d %8d %8.2f %6d %s",@{$bmArr[$_]})for (0..$end);
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
      <dt><code><kbd>apptime [count|funktion|average|clear|max|name|total] [all]</kbd></code></dt>
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
      <dt><strong>funktion</strong><dt>
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

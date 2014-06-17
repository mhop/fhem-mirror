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

sub apptime_Initialize($){
  $cmds{"apptime"}{Fn} = "apptime_CommandDispTiming";
  $cmds{"apptime"}{Hlp} = "[clear|<field>] [top|all] [<filter>] application function calls and duration";
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
  my $ts1 = gettimeofday();
  if ($tim){
    my $td = int(($ts1-$tim)*1000);
    $h->{dmx} = $td if ($h->{dmx} < $td);
  }

  no strict "refs";
  my @ret = &{$fn}(@arg);
  use strict "refs";

  $ts1 = int((gettimeofday()-$ts1)*1000);
  if ($ts1 && $h->{max}<$ts1){
    $h->{max}=$ts1;
    $h->{mAr}= \@arg;
  }

  $h->{tot}+=$ts1;
  return @ret;
}

#####################################
sub apptime_CommandDispTiming($$@) {
  my ($cl,$param) = @_;
  my ($sFld,$top,$filter) = split" ",$param;
  $sFld = "max" if (!$sFld);
  $top = "top" if (!$top);
  my %fld = (name=>0,funktion=>1,max=>2,count=>3,total=>4,average=>5,maxDly=>6,clear=>99);
  return "$sFld undefined field, use one of ".join(",",keys %fld) 
        if(!defined $fld{$sFld});
  my @bmArr;
  my @a = map{"$defs{$_}:$_"} keys (%defs); # prepare mapping hash 2 name
  $_ =~ s/[HASH\(\)]//g foreach(@a);
  foreach my $d (sort keys %defs) {
    next if(!$defs{$d}{helper}||!$defs{$d}{helper}{bm});
    if ($sFld eq "clear"){
      delete $defs{$d}{helper}{bm};
      next;
    }
    foreach my $f (sort keys %{$defs{$d}{helper}{bm}}) {
      next if(!defined $defs{$d}{helper}{bm}{$f}{cnt});
      next if($filter && $d !~ m/$filter/ && $f !~ m/$filter/);
      my ($n,$t) = ($d,$f);
      ($n,$t) = split(";",$f,2) if ($d eq "global");
      $t = "" if (!defined $t);
      my $h = $defs{$d}{helper}{bm}{$f};

      my $arg = "";
      if ($h->{mAr}){
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
  my $field = $fld{$sFld};
  if ($field>1){@bmArr = sort { $b->[$field] <=> $a->[$field] } @bmArr;}
  else         {@bmArr = sort { $b->[$field] cmp $a->[$field] } @bmArr;}
  my $ret = sprintf("\n %35s %20s %6s %6s %8s %8s %s",
            "name","function","max","count","total","average","maxDly","param Max call");
  my $end = ($top && $top eq "top")?20:@bmArr-1;
  $end = @bmArr-1 if ($end>@bmArr-1);

  $ret .= sprintf("\n %35s %20s %6d %6d %8d %8.2f %6d %s",@{$bmArr[$_]})for (0..$end);
  return $ret;
}

1;
=pod
=begin html

<a name="apptime"></a>
<h3>apptime</h3>
<ul>
  <code>apptime</code>
  <br>
  <br>
    apptime provides information about application procedure execution time. 
    It is designed to identify long runner jobs causing latency as well as 
    overall high cpu usage jobs<br>
    No information about FHEM kernel times and delays will be provided.  <br>
    Once started apptime monitors tasks. User may reset counter during operation. 
    apptime adds about 1% CPU load in average to FHEM. 
    in order to remove apptime shutdown restart is necessary.
  <br>
  <br>
    <b>Features:</b><br>
    <ul>
      <li><code>apptime</code><br>
          apptime is started with the its first call nad continously monitor operation.<br>
          To unload apptime shutdown restart is necessary<br> </li>
      <li><code>apptime clear</code><br>
          reset all counter and start fom Zero<br>      </li>
      <li><code>apptime [count|funktion|average|clear|max|name|total] [all]</code><br>
          display a table sorted by the field selected<br>
          <b>all</b> will display the complete table while by default only the top lines are printed. <br></li>
    </ul>
    <br>
    <b>Columns:</b><br>
    <ul>
      <li><b>name</b><br>
          name of the entity executing the procedure<br>
          if it is a function called by InternalTimer the name starts with <b>tmr-</b>.
          by then it gives the name of the funktion to be called<br>
          </li>
      <li><b>function</b><br>
          procedure name which was executed<br>
          if it is an InternalTimer call it gives its calling parameter <br>
          </li>
      <li><b>max</b><br>
          longest duration measured for this procedure in ms <br> </li>
      <li><b>count</b><br>
          number of calls for this procedure<br> </li>
      <li><b>total</b><br>
          accumulated duration of this procedure over all calls monitored<br> </li>
      <li><b>average</b><br>
          average time a call of this procedure takes<br> </li>
      <li><b>maxDly</b><br>
          maximum delay of a timer call to its schedules time. This column is not relevant 
          for non-timer calls.<br> </li>
      <li><b>param Max call</b><br>
          gives the parameter of the call with the max duration<br> </li>
    </ul>
    <br>
</ul>

=end html
=cut

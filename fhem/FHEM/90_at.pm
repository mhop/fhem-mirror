##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

#####################################
sub
at_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "at_Define";
  $hash->{UndefFn}  = "at_Undef";
  $hash->{AttrFn}   = "at_Attr";
  $hash->{StateFn}  = "at_State";
  $hash->{AttrList} = "disable:0,1 skip_next:0,1 loglevel:0,1,2,3,4,5,6 ".
                      "alignTime";
}


my $oldattr;

#####################################
sub
at_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, undef, $tm, $command) = split("[ \t]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
      RemoveInternalTimer($name);
      (undef, $command) = split("[ \t]+", $hash->{OLDDEF}, 2);
      $hash->{DEF} = "$tm $command";
    } else {
      return "Usage: define <name> at <timespec> <command>";
    }
  }
  return "Wrong timespec, use \"[+][*[{count}]]<time or func>\""
                                        if($tm !~ m/^(\+)?(\*({\d+})?)?(.*)$/);
  my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
  my ($err, $hr, $min, $sec, $fn) = GetTimeSpec($tspec);
  return $err if($err);

  $rel = "" if(!defined($rel));
  $rep = "" if(!defined($rep));
  $cnt = "" if(!defined($cnt));

  my $ot = $data{AT_TRIGGERTIME} ? $data{AT_TRIGGERTIME} : gettimeofday();
  $ot = int($ot) if(!$rel);     # No way to specify subseconds
  my @lt = localtime($ot);
  my $nt = $ot;

  $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0])         # Midnight for absolute time
                        if($rel ne "+");
  $nt += ($hr*3600+$min*60+$sec); # Plus relative time
  $nt += SecondsTillTomorrow($ot) if($ot >= $nt);  # Do it tomorrow...

  @lt = localtime($nt);
  my $ntm = sprintf("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
  if($rep) {    # Setting the number of repetitions
    $cnt =~ s/[{}]//g;
    return undef if($cnt eq "0");
    $cnt = 0 if(!$cnt);
    $cnt--;
    $hash->{REP} = $cnt; 
  } else {
    $hash->{VOLATILE} = 1;      # Write these entries to the statefile
  }
  $hash->{NTM} = $ntm if($rel eq "+" || $fn);
  $hash->{TRIGGERTIME} = $nt;
  RemoveInternalTimer($name);
  InternalTimer($nt, "at_Exec", $name, 0);

  $hash->{STATE} = ($oldattr && $oldattr->{disable} ? "disabled" : ("Next: ".FmtTime($nt)));
  
  return undef;
}

sub
at_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($name);
  return undef;
}

sub
at_Exec($)
{
  my ($name) = @_;
  my ($skip, $disable) = ("","");

  return if(!$defs{$name});           # Just deleted
  Log GetLogLevel($name,5), "exec at command $name";

  if(defined($attr{$name})) {
    $skip    = 1 if($attr{$name} && $attr{$name}{skip_next});
    $disable = 1 if($attr{$name} && $attr{$name}{disable});
  }

  delete $attr{$name}{skip_next} if($skip);
  my (undef, $command) = split("[ \t]+", $defs{$name}{DEF}, 2);
  $command = SemicolonEscape($command);
  my $ret = AnalyzeCommandChain(undef, $command) if(!$skip && !$disable);
  Log GetLogLevel($name,3), $ret if($ret);

  return if(!$defs{$name});           # Deleted in the Command

  my $count = $defs{$name}{REP};
  my $def = $defs{$name}{DEF};

  $oldattr = $attr{$name};           # delete removes the attributes too

  # Avoid drift when the timespec is relative
  $data{AT_TRIGGERTIME} = $defs{$name}{TRIGGERTIME} if($def =~ m/^\+/);

  my $oldCfgfn = $defs{$name}{CFGFN};
  my $oldNr    = $defs{$name}{NR};
  CommandDelete(undef, $name);          # Recreate ourselves

  if($count) {
    $def =~ s/{\d+}/{$count}/ if($def =~ m/^\+?\*{\d+}/);  # Replace the count
    Log GetLogLevel($name,5), "redefine at command $name as $def";

    $data{AT_RECOMPUTE} = 1;                 # Tell sunrise compute the next day
    CommandDefine(undef, "$name at $def");   # Recompute the next TRIGGERTIME
    delete($data{AT_RECOMPUTE});
    $attr{$name} = $oldattr;
    $defs{$name}{CFGFN} = $oldCfgfn if($oldCfgfn);
    $defs{$name}{NR} = $oldNr;
    $oldattr = undef;
  }
  delete($data{AT_TRIGGERTIME});
}

sub
at_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $do = 0;

  if($cmd eq "set" && $attrName eq "alignTime") {
    return "alignTime needs a list of timespec parameters" if(!$attrVal);
    my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($attrVal);
    return "$name alignTime: $alErr" if($alErr);

    my ($tm, $command) = split("[ \t]+", $defs{$name}{DEF}, 2);
    $tm =~ m/^(\+)?(\*({\d+})?)?(.*)$/;
    my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
    return "startTimes: $name is not relative" if(!$rel);
    my (undef, $hr, $min, $sec, undef) = GetTimeSpec($tspec);

    my $alTime = ($alHr*60+$alMin)*60+$alSec;
    my $step = ($hr*60+$min)*60+$sec;
    my $ttime = int($defs{$name}{TRIGGERTIME});
    my $off = ($ttime % 86400) - 86400;
    while($off < $alTime) {
      $off += $step;
    }
    $ttime += ($alTime-$off);
    $ttime += $step if($ttime < time());

    RemoveInternalTimer($name);
    InternalTimer($ttime, "at_Exec", $name, 0);
    $defs{$name}{TRIGGERTIME} = $ttime;
    $defs{$name}{STATE} = "Next: " . FmtTime($ttime);
  }

  if($cmd eq "set" && $attrName eq "disable") {
    $do = (!defined($attrVal) || $attrVal) ? 1 : 2;
  }
  $do = 2 if($cmd eq "del" && (!$attrName || $attrName eq "disable"));
  return if(!$do);
  $defs{$name}{STATE} = ($do == 1 ?
        "disabled" :
        "Next: " . FmtTime($defs{$name}{TRIGGERTIME}));

  return undef;
}

#############
# Adjust one-time relative at's after reboot, the execution time is stored as
# state
sub
at_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  return undef if($hash->{DEF} !~ m/^\+\d/ ||
                  $val !~ m/Next: (\d\d):(\d\d):(\d\d)/);

  my ($h, $m, $s) = ($1, $2, $3);
  my $then = ($h*60+$m)*60+$s;
  my $now = time();
  my @lt = localtime($now);
  my $ntime = ($lt[2]*60+$lt[1])*60+$lt[0];
  return undef if($ntime > $then); 

  my $name = $hash->{NAME};
  RemoveInternalTimer($name);
  InternalTimer($now+$then-$ntime, "at_Exec", $name, 0);
  $hash->{NTM} = "$h:$m:$s";
  $hash->{STATE} = $val;
  
  return undef;
}

1;

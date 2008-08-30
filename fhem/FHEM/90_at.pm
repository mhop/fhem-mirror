##############################################
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
  $hash->{AttrFn}   = "at_Attr";
  $hash->{AttrList} = "disable:0,1 skip_next:0,1";
}


#####################################
sub
at_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, undef, $tm, $command) = split("[ \t]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
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

  my $ot = gettimeofday();
  my @lt = localtime($ot);
  my $nt = $ot;

  $nt -= ($lt[2]*3600+$lt[1]*60+$lt[0])         # Midnight for absolute time
                        if($rel ne "+");
  $nt += ($hr*3600+$min*60+$sec); # Plus relative time
  $nt += 86400 if($ot >= $nt);# Do it tomorrow...

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
  InternalTimer($nt, "at_Exec", $name, 0);

  $hash->{STATE} = "Next: " . FmtTime($nt);
     if(!($attr{$name} && $attr{$name}{disable}));
  
  return undef;
}

sub
at_Exec($)
{
  my ($name) = @_;
  my ($skip, $disable);

  if(defined($attr{$name})) {
    $skip    = 1 if($attr{$name} && $attr{$name}{skip_next});
    $disable = 1 if($attr{$name} && $attr{$name}{disable});
  }

  delete $attr{$name}{skip_next} if($skip);
  return if(!$defs{$name}{DEF});           # Just deleted
  my (undef, $command) = split("[ \t]+", $defs{$name}{DEF}, 2);
  $command = SemicolonEscape($command);
  AnalyzeCommandChain(undef, $command) if(!$skip && !$disable);

  my $count = $defs{$name}{REP};
  my $def = $defs{$name}{DEF};
  delete $defs{$name};

  if($count) {
    $def =~ s/{\d+}/{$count}/ if($def =~ m/^\+?\*{/);   # Replace the count }
    CommandDefine(undef, "$name at $def");   # Recompute the next TRIGGERTIME
  }
}

sub
at_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ?
        "disabled" :
        "Next: " . FmtTime($defs{$a[1]}{TRIGGERTIME}));

  return undef;
}

1;

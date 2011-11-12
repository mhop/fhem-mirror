##############################################
# $Id$
package main;

use strict;
use warnings;

#####################################
sub
notify_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "notify_Define";
  $hash->{NotifyFn} = "notify_Exec";
  $hash->{AttrFn}   = "notify_Attr";
  $hash->{AttrList} = "disable:0,1";
}


#####################################
sub
notify_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $re, $command) = split("[ \t]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
      (undef, $command) = split("[ \t]+", $hash->{OLDDEF}, 2);
      $hash->{DEF} = "$re $command";
    } else {
      return "Usage: define <name> notify <regexp> <command>";
    }
  }

  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$re$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $re;
  $hash->{STATE} = "active";

  return undef;
}

#####################################
sub
notify_Exec($$)
{
  my ($ntfy, $dev) = @_;

  my $ln = $ntfy->{NAME};
  return "" if($attr{$ln} && $attr{$ln}{disable});

  my $n = $dev->{NAME};
  my $re = $ntfy->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $t = $dev->{TYPE};

  my $ret = "";
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    my $found = ($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/);
    if(!$found && AttrVal($n, "eventMap", undef)) {
      (undef, $s) = ReplaceEventMap($n, [$n,$s], 0);
      $found = ("$n:$s" =~ m/^$re$/);
    }
    if($found) {
      my (undef, $exec) = split("[ \t]+", $ntfy->{DEF}, 2);

      my %specials= (
                "%NAME" => $n,
                "%TYPE" => $t,
                "%EVENT" => $s
      );
      $exec= EvalSpecials($exec, %specials);

      my $r = AnalyzeCommandChain(undef, $exec);
      Log 3, $r if($r);
      $ret .= " $r" if($r);
    }
  }
  return $ret;
}

sub
notify_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");
  return undef;
}
1;

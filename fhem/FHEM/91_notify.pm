##############################################
package main;

use strict;
use warnings;
use IO::File;

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
  my ($re, $command) = split("[ \t]+", $def, 2);
  
  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$re$/ };
  return "Bad regexp: $@" if($@);
  $hash->{CMD} = SemicolonEscape($command);
  $hash->{REGEXP} = $re;
  $hash->{STATE} = "active";

  return undef;
}

#####################################
sub
notify_Exec($$)
{
  my ($log, $dev) = @_;

  my $ln = $log->{NAME};
  return if($attr{$ln} && $attr{$ln}{disable});

  my $n = $dev->{NAME};
  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});

  my $ret = "";
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
      my $exec = $log->{CMD};

      $exec =~ s/%%/____/g;
      $exec =~ s/%/$s/g;
      $exec =~ s/____/%/g;

      $exec =~ s/@@/____/g;
      $exec =~ s/@/$n/g;
      $exec =~ s/____/@/g;

      my $r = AnalyzeCommandChain(undef, $exec);
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

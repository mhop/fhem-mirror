##############################################
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

#####################################
sub
watchdog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "watchdog_Define";
  $hash->{NotifyFn} = "watchdog_Notify";
  $hash->{AttrList} = "disable:0,1";
}


#####################################
# defined watchme watchdog reg1 timeout reg2 command
sub
watchdog_Define($$)
{
  my ($ntfy, $def) = @_;
  my ($name, $type, $re1, $to, $re2, $command) = split("[ \t]+", $def, 6);
  
  return "Usage: define <name> watchdog <re1> <timeout> <re2> <command>"
    if(!$command);

  # Checking for misleading regexps
  eval { "Hallo" =~ m/^$re1$/ };
  return "Bad regexp 1: $@" if($@);
  $re2 = $re1 if($re2 eq "SAME");
  eval { "Hallo" =~ m/^$re2$/ };
  return "Bad regexp 2: $@" if($@);

  return "Wrong timespec, must be HH:MM[:SS]"
        if($to !~ m/^(\d\d):(\d\d)(:\d\d)?$/);
  $to = $1*3600+$2*60+($3 ? substr($3,1) : 0);

  $ntfy->{RE1} = $re1;
  $ntfy->{RE2} = $re2;
  $ntfy->{TO}  = $to;
  $ntfy->{CMD} = $command;


  $ntfy->{STATE} = ($re1 eq ".") ? "active" : "defined";
  watchdog_Activate($ntfy) if($ntfy->{STATE} eq "active");

  return undef;
}

#####################################
sub
watchdog_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $ln = $ntfy->{NAME};
  return "" if($attr{$ln} && $attr{$ln}{disable});

  my $n   = $dev->{NAME};
  my $re1 = $ntfy->{RE1};
  my $re2 = $ntfy->{RE2};
  my $max = int(@{$dev->{CHANGED}});

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));

    if($ntfy->{STATE} =~ m/Next:/) {
      if($n =~ m/^$re2$/ || "$n:$s" =~ m/^$re2$/) {
        RemoveInternalTimer($ntfy);
        if($re1 eq $re2) {
          watchdog_Activate($ntfy);
        } else {
          $ntfy->{STATE} = "defined";
        }
      }
    } elsif($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/) {
      watchdog_Activate($ntfy);
    }
  }
  return "";
}

sub
watchdog_Trigger($)
{
  my ($ntfy) = @_;
  Log(3, "Watchdog $ntfy->{NAME} triggered");
  my $exec = SemicolonEscape($ntfy->{CMD});;
  AnalyzeCommandChain(undef, $exec);
  $ntfy->{STATE} = "triggered";
}

sub
watchdog_Activate($)
{
  my ($ntfy) = @_;
  my $nt = gettimeofday() + $ntfy->{TO};
  $ntfy->{STATE} = "Next: " . FmtTime($nt);
  RemoveInternalTimer($ntfy);
  InternalTimer($nt, "watchdog_Trigger", $ntfy, 0)
}


1;

##############################################
# $Id$
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
  $hash->{UndefFn} = "watchdog_Undef";
  $hash->{NotifyFn} = "watchdog_Notify";
  $hash->{AttrList} = "disable:0,1 regexp1WontReactivate:0,1";
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


  if($re1 eq ".") {
    watchdog_Activate($ntfy)

  } else {
    $ntfy->{STATE} = "defined";

  }

  return undef;
}

#####################################
sub
watchdog_Notify($$)
{
  my ($ntfy, $dev) = @_;

  my $ln = $ntfy->{NAME};
  return "" if($attr{$ln} && $attr{$ln}{disable});
  return "" if($ntfy->{INWATCHDOG});

  my $n   = $dev->{NAME};
  my $re1 = $ntfy->{RE1};
  my $re2 = $ntfy->{RE2};
  my $max = int(@{$dev->{CHANGED}});

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    my $dotTrigger = ($ln eq $n && $s eq "."); # trigger w .
    my $dontReAct = AttrVal($ln, "regexp1WontReactivate", 0);

    if($ntfy->{STATE} =~ m/Next:/) {

      if($n =~ m/^$re2$/ || "$n:$s" =~ m/^$re2$/) {
        RemoveInternalTimer($ntfy);

        if(($re1 eq $re2 || $re1 eq ".") && !$dontReAct) {
          watchdog_Activate($ntfy);
          return "";

        } else {
          $ntfy->{STATE} = "defined";

        }

      } elsif($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/) {
        watchdog_Activate($ntfy) if(!$dontReAct);

      }

    } elsif($ntfy->{STATE} eq "defined") {
      if($dotTrigger ||      # trigger w .
         ($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/)) {
        watchdog_Activate($ntfy)
      }

    } elsif($dotTrigger) {
      $ntfy->{STATE} = "defined";       # trigger w . 

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
  $ntfy->{STATE} = "triggered";
  $ntfy->{INWATCHDOG} = 1;
  my $ret = AnalyzeCommandChain(undef, $exec);
  Log 3, $ret if($ret);
  $ntfy->{INWATCHDOG} = 0;
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

sub
watchdog_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  return undef;
}

1;

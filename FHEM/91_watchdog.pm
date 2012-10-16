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
  my ($watchdog, $def) = @_;
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

  $watchdog->{RE1} = $re1;
  $watchdog->{RE2} = $re2;
  $watchdog->{TO}  = $to;
  $watchdog->{CMD} = $command;


  if($re1 eq ".") {
    watchdog_Activate($watchdog)

  } else {
    $watchdog->{STATE} = "defined";

  }

  return undef;
}

#####################################
sub
watchdog_Notify($$)
{
  my ($watchdog, $dev) = @_;

  my $ln = $watchdog->{NAME};
  return "" if($attr{$ln} && $attr{$ln}{disable});
  my $dontReAct = AttrVal($ln, "regexp1WontReactivate", 0);

  my $n   = $dev->{NAME};
  my $re1 = $watchdog->{RE1};
  my $re2 = $watchdog->{RE2};
  my $max = int(@{$dev->{CHANGED}});

  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    my $dotTrigger = ($ln eq $n && $s eq "."); # trigger w .

    if($watchdog->{STATE} =~ m/Next:/) {

      if($n =~ m/^$re2$/ || "$n:$s" =~ m/^$re2$/) {
        RemoveInternalTimer($watchdog);

        if(($re1 eq $re2 || $re1 eq ".") && !$dontReAct) {
          watchdog_Activate($watchdog);
          return "";

        } else {
          $watchdog->{STATE} = "defined";

        }

      } elsif($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/) {
        watchdog_Activate($watchdog) if(!$dontReAct);

      }

    } elsif($watchdog->{STATE} eq "defined") {
      if($dotTrigger ||      # trigger w .
         ($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/)) {
        watchdog_Activate($watchdog)
      }

    } elsif($dotTrigger) {
      $watchdog->{STATE} = "defined";       # trigger w . 

    }

  }
  return "";
}

sub
watchdog_Trigger($)
{
  my ($watchdog) = @_;
  Log(3, "Watchdog $watchdog->{NAME} triggered");
  my $exec = SemicolonEscape($watchdog->{CMD});;
  $watchdog->{STATE} = "triggered";
  
  $watchdog->{READINGS}{Triggered}{TIME} = TimeNow();
  $watchdog->{READINGS}{Triggered}{VAL} = $watchdog->{STATE};
  
  my $ret = AnalyzeCommandChain(undef, $exec);
  Log 3, $ret if($ret);
}

sub
watchdog_Activate($)
{
  my ($watchdog) = @_;
  my $nt = gettimeofday() + $watchdog->{TO};
  $watchdog->{STATE} = "Next: " . FmtTime($nt);
  RemoveInternalTimer($watchdog);
  InternalTimer($nt, "watchdog_Trigger", $watchdog, 0)
}

sub
watchdog_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  return undef;
}

1;

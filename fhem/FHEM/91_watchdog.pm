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
  return "" if(AttrVal($ln, "disable", 0));
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
  my $name = $watchdog->{NAME};

  if(AttrVal($name, "disable", 0)) {
    $watchdog->{STATE} = "defined";
    return "";
  }

  Log3 $name, 3, "Watchdog $name triggered";
  my $exec = SemicolonEscape($watchdog->{CMD});;
  $watchdog->{STATE} = "triggered";
  
  $watchdog->{READINGS}{Triggered}{TIME} = TimeNow();
  $watchdog->{READINGS}{Triggered}{VAL} = $watchdog->{STATE};
  
  my $ret = AnalyzeCommandChain(undef, $exec);
  Log3 $name, 3, $ret if($ret);
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

=pod
=begin html

<a name="watchdog"></a>
<h3>watchdog</h3>
<ul>
  <br>

  <a name="watchdogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; watchdog &lt;regexp1&gt; &lt;timespec&gt; &lt;regexp2&gt; &lt;command&gt;</code><br>
    <br>
    Start an arbitrary fhem.pl command if after &lt;timespec&gt; receiving an
    event matching &lt;regexp1&gt; no event matching &lt;regexp2&gt; is
    received.<br>
    The syntax for &lt;regexp1&gt; and &lt;regexp2&gt; is the same as the
    regexp for <a href="#notify">notify</a>.<br>
    &lt;timespec&gt; is HH:MM[:SS]<br>
    &lt;command&gt; is a usual fhem command like used int the <a
    href="#at">at</a> or <a href="#notify">notify</a>
    <br><br>

    Examples:
    <code><ul>
    # Request data from the FHT80 _once_ if we do not receive any message for<br>
    # 15 Minutes.<br>
    define w watchdog FHT80 00:15:00 SAME set FHT80 date<br>

    # Request data from the FHT80 _each_ time we do not receive any message for<br>
    # 15 Minutes, i.e. reactivate the watchdog after it triggered.  Might be<br>
    # dangerous, as it can trigger in a loop.<br>
    define w watchdog FHT80 00:15:00 SAME set FHT80 date;; trigger w .<br>

    # Shout once if the HMS100-FIT is not alive<br>
    define w watchdog HMS100-FIT 01:00:00 SAME "alarm-fit.sh"<br>

    # Send mail if the window is left open<br>
    define w watchdog contact1:open 00:15 contact1:closed "mail_me close window1"<br>
    attr w regexp1WontReactivate<br>
    </ul></code>

    Notes:<br>
    <ul>
      <li>if &lt;regexp1&gt; is . (dot), then activate the watchdog at
          definition time. Else it will be activated when the first matching
          event is received.</li>
      <li>&lt;regexp1&gt; resets the timer of a running watchdog, to avoid it
          use the regexp1WontReactivate attribute.</li>
      <li>if &lt;regexp2&gt; is SAME, then it will be the same as the first
          regexp, and it will be reactivated, when it is received.
          </li>
      <li>trigger &lt;watchdogname&gt; . will activate the trigger if its state
          is defined, and set it into state defined if its state is
          triggered. You always have to reactivate the watchdog with this
          command once it has triggered (unless you restart fhem)</li>
      <li>a generic watchdog (one watchdog responsible for more devices) is
          currently not possible.</li>
    </ul>

    <br>
  </ul>

  <a name="watchdogset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="watchdogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="watchdogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a name="regexp1WontReactivate">regexp1WontReactivate</a><br>
        When a watchdog is active, a second event matching regexp1 will
        normally reset the timeout. Set this attribute to prevents this.
    </li>
  </ul>
  <br>
</ul>

=end html
=cut

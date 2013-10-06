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
  $hash->{AttrList} = "disable:0,1 skip_next:0,1 alignTime";
}


my $at_stt_sec;
my $at_stt_day;

sub
at_SecondsTillTomorrow($)  # 86400, if tomorrow is no DST change
{
  my $t = shift;
  my $day = int($t/86400);

  if(!$at_stt_day || $day != $at_stt_day) {
    my $t = $day*86400+12*3600;
    my @l1 = localtime($t);
    my @l2 = localtime($t+86400);
    $at_stt_sec = 86400+
                ($l1[2]-$l2[2])*3600+
                ($l1[1]-$l2[1])*60;
    $at_stt_day = $day;
  }

  return $at_stt_sec;
}


#####################################
sub
at_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, undef, $tm, $command) = split("[ \t]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
      RemoveInternalTimer($hash);
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
  $nt += at_SecondsTillTomorrow($ot) if($ot >= $nt);  # Do it tomorrow...
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
  $hash->{TRIGGERTIME_FMT} = FmtDateTime($nt);
  RemoveInternalTimer($hash);
  InternalTimer($nt, "at_Exec", $hash, 0);

  $hash->{STATE} = AttrVal($name, "disable", undef) ?
                        "disabled" : ("Next: ".FmtTime($nt));
  return undef;
}

sub
at_Undef($$)
{
  my ($hash, $name) = @_;
  $hash->{DELETED} = 1;
  RemoveInternalTimer($hash);
  return undef;
}

sub
at_Exec($)
{
  my ($hash) = @_;

  return if($hash->{DELETED});           # Just deleted
  my $name = $hash->{NAME};
  Log3 $name, 5, "exec at command $name";

  my $skip    = AttrVal($name, "skip_next", undef);
  my $disable = AttrVal($name, "disable", undef);

  delete $attr{$name}{skip_next} if($skip);
  my (undef, $command) = split("[ \t]+", $hash->{DEF}, 2);
  $command = SemicolonEscape($command);
  my $ret = AnalyzeCommandChain(undef, $command) if(!$skip && !$disable);
  Log3 $name, 3, "$name: $ret" if($ret);

  return if($hash->{DELETED});           # Deleted in the Command

  my $count = $hash->{REP};
  my $def = $hash->{DEF};

  # Avoid drift when the timespec is relative
  $data{AT_TRIGGERTIME} = $hash->{TRIGGERTIME} if($def =~ m/^\+/);

  if($count) {
    $def =~ s/{\d+}/{$count}/ if($def =~ m/^\+?\*{\d+}/);  # Replace the count
    Log3 $name, 5, "redefine at command $name as $def";

    $data{AT_RECOMPUTE} = 1;             # Tell sunrise compute the next day
    at_Define($hash, "$name at $def");   # Recompute the next TRIGGERTIME
    delete($data{AT_RECOMPUTE});

  } else {
    CommandDelete(undef, $name);          # We are done

  }
  delete($data{AT_TRIGGERTIME});
}

sub
at_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $do = 0;

  my $hash = $defs{$name};

  if($cmd eq "set" && $attrName eq "alignTime") {
    return "alignTime needs a list of timespec parameters" if(!$attrVal);
    my ($alErr, $alHr, $alMin, $alSec, undef) = GetTimeSpec($attrVal);
    return "$name alignTime: $alErr" if($alErr);

    my ($tm, $command) = split("[ \t]+", $hash->{DEF}, 2);
    $tm =~ m/^(\+)?(\*({\d+})?)?(.*)$/;
    my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
    return "startTimes: $name is not relative" if(!$rel);
    my (undef, $hr, $min, $sec, undef) = GetTimeSpec($tspec);

    my $alTime = ($alHr*60+$alMin)*60+$alSec;
    my $step = ($hr*60+$min)*60+$sec;
    my $ttime = int($hash->{TRIGGERTIME});
    my $off = ($ttime % 86400) - 86400;
    while($off < $alTime) {
      $off += $step;
    }
    $ttime += ($alTime-$off);
    $ttime += $step if($ttime < time());

    RemoveInternalTimer($hash);
    InternalTimer($ttime, "at_Exec", $hash, 0);
    $hash->{TRIGGERTIME} = $ttime;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($ttime);
    $hash->{STATE} = "Next: " . FmtTime($ttime);
  }

  if($cmd eq "set" && $attrName eq "disable") {
    $do = (!defined($attrVal) || $attrVal) ? 1 : 2;
  }
  $do = 2 if($cmd eq "del" && (!$attrName || $attrName eq "disable"));
  return if(!$do);
  $hash->{STATE} = ($do == 1 ?
        "disabled" :
        "Next: " . FmtTime($hash->{TRIGGERTIME}));

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
  RemoveInternalTimer($hash);
  InternalTimer($now+$then-$ntime, "at_Exec", $hash, 0);
  $hash->{NTM} = "$h:$m:$s";
  $hash->{STATE} = $val;
  
  return undef;
}

1;

=pod
=begin html

<a name="at"></a>
<h3>at</h3>
<ul>

  Start an arbitrary fhem.pl command at a later time.<br>
  <br>

  <a name="atdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; at &lt;timespec&gt; &lt;command&gt;</code><br>
    <br>
    <code>&lt;timespec&gt;</code> format: [+][*{N}]&lt;timedet&gt;<br>
    <ul>
      The optional <code>+</code> indicates that the specification is
      <i>relative</i>(i.e. it will be added to the current time).<br>
      The optional <code>*</code> indicates that the command should be
      executed <i>repeatedly</i>.<br>
      The optional <code>{N}</code> after the * indicates,that the command
      should be repeated <i>N-times</i> only.<br>
      &lt;timedet&gt; is either HH:MM, HH:MM:SS or {perlfunc()}, where perlfunc
      must return a HH:MM or HH:MM:SS date. Note: {perlfunc()} may not contain
      any spaces or tabs.
    </ul>
    <br>

    Examples:
    <PRE>
    # absolute ones:
    define a1 at 17:00:00 set lamp on                            # fhem command
    define a2 at 17:00:00 { Log 1, "Teatime" }                   # Perl command
    define a3 at 17:00:00 "/bin/echo "Teatime" > /dev/console"   # shell command
    define a4 at *17:00:00 set lamp on                           # every day

    # relative ones
    define a5 at +00:00:10 set lamp on                  # switch on in 10 seconds
    define a6 at +00:00:02 set lamp on-for-timer 1      # Blink once in 2 seconds
    define a7 at +*{3}00:00:02 set lamp on-for-timer 1  # Blink 3 times

    # Blink 3 times if the piri sends a command
    define n1 notify piri:on.* define a8 at +*{3}00:00:02 set lamp on-for-timer 1

    # Switch the lamp on from sunset to 11 PM
    define a9 at +*{sunset_rel()} set lamp on
    define a10 at *23:00:00 set lamp off

    # More elegant version, works for sunset > 23:00 too
    define a11 at +*{sunset_rel()} set lamp on-till 23:00

    # Only do this on weekend
    define a12 at +*{sunset_rel()} { fhem("set lamp on-till 23:00") if($we) }

    # Switch lamp1 and lamp2 on from 7:00 till 10 minutes after sunrise
    define a13 at *07:00 set lamp1,lamp2 on-till {sunrise(+600)}

    # Switch the lamp off 2 minutes after sunrise each day
    define a14 at +{sunrise(+120)} set lamp on

    # Switch lamp1 on at sunset, not before 18:00 and not after 21:00
    define a15 at *{sunset(0,"18:00","21:00")} set lamp1 on

    </PRE>

    Notes:<br>
    <ul>
      <li>if no <code>*</code> is specified, then a command will be executed
          only once, and then the <code>at</code> entry will be deleted.  In
          this case the command will be saved to the statefile (as it
          considered volatile, i.e. entered by cronjob) and not to the
          configfile (see the <a href="#save">save</a> command.)
      </li>

      <li>if the current time is greater than the time specified, then the
          command will be executed tomorrow.</li>

      <li>For even more complex date handling you either have to call fhem from
          cron or filter the date in a perl expression, see the last example and
          the section <a href="#perl">Perl special</a>.
      </li>
    </ul>
    <br>
  </ul>


  <a name="atset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="atget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="atattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="disable"></a>
    <li>disable<br>
        Can be applied to at/watchdog/notify/FileLog devices.<br>
        Disables the corresponding at/notify or FileLog device. Note:
        If applied to an <a href="#at">at</a>, the command will not be executed,
        but the next time will be computed.</li><br>

    <a name="skip_next"></a>
    <li>skip_next<br>
        Used for at commands: skip the execution of the command the next
        time.</li><br>

    <a name="alignTime"></a>
    <li>alignTime<br>
        Applies only to relative at definitions: adjust the time of the next
        command execution so, that it will also be executed at the desired
        alignTime. The argument is a timespec, see above for the
        definition.<br>
        Example:<br>
        <ul>
        # Make sure that it chimes when the new hour begins<br>
        define at2 at +*01:00 set Chime on-for-timer 1<br>
        attr atr2 alignTime 00:00<br>
        </ul>
        </li><br>

  </ul>
  <br>

</ul>

=end html
=cut

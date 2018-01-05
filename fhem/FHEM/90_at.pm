##############################################
# $Id$
package main;

use strict;
use warnings;
use POSIX;
use Time::HiRes qw(gettimeofday);

#####################################
sub
at_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "at_Define";
  $hash->{UndefFn}  = "at_Undef";
  $hash->{SetFn}    = "at_Set";
  $hash->{AttrFn}   = "at_Attr";
  $hash->{StateFn}  = "at_State";
  $hash->{AttrList} = "disable:0,1 disabledForIntervals ".
                        "skip_next:0,1 alignTime computeAfterInit";
  $hash->{FW_detailFn} = "at_fhemwebFn";
}


my %at_stt;
my $at_detailFnCalled;

sub
at_SecondsTillTomorrow($)  # 86400, if tomorrow is no DST change
{
  my $t = shift;
  my $dayHour = int($t/3600);

  if(!$at_stt{$dayHour}) {
    my @l1 = localtime($t);
    my @l2 = localtime($t+86400);
    $at_stt{$dayHour} = 86400+($l1[8]-$l2[8])*3600;
  }

  return $at_stt{$dayHour};
}


#####################################
sub
at_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, undef, $tm, $command) = split("[ \t\n]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
      RemoveInternalTimer($hash);
      (undef, $command) = split("[ \t]+", $hash->{OLDDEF}, 2);
      $hash->{DEF} = "$tm $command";
    } else {
      return "Usage: define <name> at [timespec or datespec] <command>";
    }
  }

  return "Wrong timespec, use \"[+][*[{count}]]<time or func>\""
                                        if($tm !~ m/^(\+)?(\*({\d+})?)?(.*)$/);
  my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);

  my ($abstime, $err, $hr, $min, $sec, $fn);
  if($tspec =~ m/^\d{10}$/) {
    $abstime = $tspec;

  } elsif($tspec =~ m/^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)$/) {
    my ($y,$m,$d,$h,$m2,$s) = ($1,$2,$3,$4,$5,$6);
    $abstime = mktime($s,$m2,$h,$d,$m-1,$y-1900, 0,0,-1);

  } else {
    ($err, $hr, $min, $sec, $fn) = GetTimeSpec($tspec);
    return $err if($err);

  }
  return "datespec is not allowed with + or *" if($abstime && ($rel || $rep));

  if($hash->{CL}) {     # Do not check this for definition
    $err = perlSyntaxCheck($command, ());
    return $err if($err);
  }

  $rel = "" if(!defined($rel));
  $rep = "" if(!defined($rep));
  $cnt = "" if(!defined($cnt));
  delete $hash->{VOLATILE} if (defined($hash->{VOLATILE}));
  $hash->{RELATIVE} = ($rel ? "yes" : "no");
  $hash->{PERIODIC} = ($rep ? "yes" : "no");
  $hash->{TIMESPEC} = $tspec;
  $hash->{COMMAND} = $command;


  my $ot = $data{AT_TRIGGERTIME} ? $data{AT_TRIGGERTIME} : gettimeofday();
  $ot = int($ot) if(!$rel);     # No way to specify subseconds
  my $nt = $ot;

  if($abstime) {
    $nt = $abstime;

  } elsif($rel eq "+") {
    $nt += ($hr*3600+$min*60+$sec); # Relative time

  } else {
    my @lt = localtime($ot);
    ($lt[2], $lt[1], $lt[0]) = ($hr+0, $min+0, $sec+0);
    $lt[8] = -1; # Forum #52074
    $nt = mktime(@lt);
    $nt += at_SecondsTillTomorrow($nt) if($ot >= $nt);  # Do it tomorrow...

  }

  my @lt = localtime($nt);
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

  my $alTime = AttrVal($name, "alignTime", undef);
    
  if(!$data{AT_RECOMPUTE} && $alTime) {
    my $ret = at_adjustAlign($hash, $alTime);
    return $ret if($ret);

  } else {
    my $fmt = FmtDateTime($nt);
    $hash->{TRIGGERTIME} = $nt;
    $hash->{TRIGGERTIME_FMT} = $fmt;
    if($hash->{PERIODIC} eq "no") {      # Need for restart
      $fmt =~ s/ /T/;
      $hash->{DEF} = $fmt." ".$hash->{COMMAND};
    }
    RemoveInternalTimer($hash);
    InternalTimer($nt, "at_Exec", $hash, 0);
    $hash->{NTM} = $ntm if($rel eq "+" || $fn);
    my $d = IsDisabled($name);  # 1
    my $val = ($d==3 ? "inactive" : ($d ? "disabled":("Next: ".
                        ($abstime ? FmtDateTime($nt) : FmtTime($nt)) )));
    readingsSingleUpdate($hash, "state", $val,
          !$hash->{READINGS}{state} || $hash->{READINGS}{state}{VAL} ne $val);
  }

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

  my $skip = AttrVal($name, "skip_next", undef);
  delete $attr{$name}{skip_next} if($skip);
  $hash->{TEMPORARY} = 1 if($hash->{VOLATILE}); # 68680
  delete $hash->{VOLATILE};

  if(!$skip && !IsDisabled($name)) {
    Log3 $name, 5, "exec at command $name";
    my $ret = AnalyzeCommandChain(undef, SemicolonEscape($hash->{COMMAND}));
    Log3 $name, 3, "$name: $ret" if($ret);
  }

  return if($hash->{DELETED});           # Deleted in the Command

  my $count = $hash->{REP};
  my $def = $hash->{DEF};

  # Avoid drift when the timespec is relative
  $data{AT_TRIGGERTIME} = $hash->{TRIGGERTIME} if($def =~ m/^\+/);

  if($count) {
    $def =~ s/\{\d+\}/{$count}/ if($def =~ m/^\+?\*\{\d+\}/); # Replace count
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
at_adjustAlign($$)
{
  my($hash, $attrVal) = @_;

  my ($tm, $command) = split("[ \t]+", $hash->{DEF}, 2);
  $tm =~ m/^(\+)?(\*({\d+})?)?(.*)$/;
  my ($rel, $rep, $cnt, $tspec) = ($1, $2, $3, $4);
  return "startTimes: $hash->{NAME} is not relative" if(!$rel);

  my ($err, $ttime) = computeAlignTime($tspec, $attrVal,$hash->{TRIGGERTIME});
  return "$hash->{NAME} $err" if($err);

  RemoveInternalTimer($hash);
  InternalTimer($ttime, "at_Exec", $hash, 0);
  $hash->{TRIGGERTIME} = $ttime;
  $hash->{TRIGGERTIME_FMT} = FmtDateTime($ttime);
  $hash->{STATE} = "Next: " . FmtTime($ttime);
  $hash->{NTM} = FmtTime($ttime);
  readingsSingleUpdate($hash, "state", $hash->{STATE}, 1)
           if(!IsDisabled($hash->{NAME}));
  return undef;
}

sub
at_Set($@)
{
  my ($hash, @a) = @_;

  my %sets = (modifyTimeSpec=>1, inactive=>0, active=>0, execNow=>0);
  my $cmd = join(" ", sort keys %sets);
  $cmd =~ s/modifyTimeSpec/modifyTimeSpec:time/ if($at_detailFnCalled);
  $at_detailFnCalled = 0;
  return "no set argument specified" if(int(@a) < 2);
  return "Unknown argument $a[1], choose one of $cmd"
    if(!defined($sets{$a[1]}));
    
  if($a[1] eq "modifyTimeSpec") {
    my ($err, undef) = GetTimeSpec($a[2]);
    return $err if($err);

    my $def = ($hash->{RELATIVE} eq "yes" ? "+":"").
              ($hash->{PERIODIC} eq "yes" ? "*":"").
              $a[2];
    $hash->{OLDDEF} = $hash->{DEF};
    my $ret = at_Define($hash, "$hash->{NAME} at $def");
    delete $hash->{OLDDEF};
    return $ret;

  } elsif($a[1] eq "inactive") {
    readingsSingleUpdate($hash, "state", "inactive", 1);
    return undef;

  } elsif($a[1] eq "active") {
    readingsSingleUpdate($hash,"state","Next: ".FmtTime($hash->{TRIGGERTIME}),1)
      if(!AttrVal($hash->{NAME}, "disable", undef));
    return undef;
   
  } elsif($a[1] eq "execNow") {
    my $name = $hash->{NAME};
    my $ret = AnalyzeCommandChain(undef, SemicolonEscape($hash->{COMMAND}));
    Log3 $name, 3, "$name: $ret" if($ret);

  }

}
  
sub
at_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $do = 0;

  my $hash = $defs{$name};

  if($cmd eq "set" && $attrName eq "computeAfterInit" &&
     $attrVal && !$init_done) {
    InternalTimer(1, sub(){
      $hash->{OLDDEF} = $hash->{DEF};
      at_Define($hash, "$name at $hash->{DEF}");
      delete($hash->{OLDDEF});
    }, $name, 0);
    return undef;
  }

  if($cmd eq "set" && $attrName eq "alignTime") {
    return "alignTime needs a list of timespec parameters" if(!$attrVal);
    my $ret = at_adjustAlign($hash, $attrVal);
    return $ret if($ret);
  }

  if($cmd eq "set" && $attrName eq "disable") {
    $do = (!defined($attrVal) || $attrVal) ? 1 : 2;
  }
  $do = 2 if($cmd eq "del" && (!$attrName || $attrName eq "disable"));
  return if(!$do);
  my $val = ($do == 1 ?  "disabled" :
                         "Next: " . FmtTime($hash->{TRIGGERTIME}));
  readingsSingleUpdate($hash, "state", $val, 1);
  return undef;
}

#############
# Adjust one-time relative at's after reboot, the execution time is stored as
# state
sub
at_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  if($vt eq "state" && $val eq "inactive") {
    readingsSingleUpdate($hash, "state", "inactive", 1);
  }
  return undef;
}

#########################
sub
at_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};

  $at_detailFnCalled = 1 if(!$pageHash);

  my $ts = $hash->{TIMESPEC}; $ts =~ s/'/\\'/g;
  my $isPerl = ($ts =~ m/^{(.*)}/);
  $ts = $1 if($isPerl);

  my $h1 .= "<div class='makeTable wide'><span>Change wizard</span>".
"<table class='block wide' id='atWizard' nm='$hash->{NAME}' ts='$ts' ".
       "rl='$hash->{RELATIVE}' ".
       "pr='$hash->{PERIODIC}' ip='$isPerl' class='block wide'>".<<'EOF';
  <tr class="even"><td>Change the timespec:</td></tr>
  <tr class="odd">
    <td>Relative <input type="checkbox" id="aw_rl" value="yes">&nbsp;
        Periodic <input type="checkbox" id="aw_pr" value="yes">&nbsp;
        Use perl function for timespec <input type="checkbox" id="aw_ip"></td>
  </tr><tr class="even"><td><input type="text" name="aw_pts"></td>
  </tr><tr class="even"><td><input type="text" name="aw_ts"></td>
  </tr><tr class="odd"><td><input type="button" id="aw_md"
        value="Change the timespec"></td>
  </tr>
EOF

  my $j1 = << 'EOF';
<script type="text/javascript">
  {
    var t=$("#atWizard"), ip=$(t).attr("ip"), ts=$(t).attr("ts");
    FW_replaceWidget("[name=aw_ts]", "aw_ts", ["time"], "12:00");
    $("[name=aw_ts] input[type=text]").attr("id", "aw_ts");

    function ipClick() {
      var c = $("#aw_ip").prop("checked");
      $("[name=aw_ts]") .closest("tr").css("display",!c ? "table-row" : "none");
      $("[name=aw_pts]").closest("tr").css("display", c ? "table-row" : "none");
    }
    $("#aw_rl").prop("checked", $(t).attr("rl")=="yes");
    $("#aw_pr").prop("checked", $(t).attr("pr")=="yes");
    $("#aw_ip").prop("checked", ip);
    $("[name=aw_ts]").val(ip ? "12:00" : ts);
    $("[name=aw_pts]").val(ip ? ts : 'sunset()');
    $("#aw_ip").change(ipClick);
    ipClick();
    $("#aw_md").click(function(){
      var nm = $(t).attr("nm");
      var def = nm+" ";
      def += $("#aw_rl").prop("checked") ? "+":"";
      def += $("#aw_pr").prop("checked") ? "*":"";
      def += $("#aw_ip").prop("checked") ? 
               "{"+$("[name=aw_pts]").val()+"}" : $("[name=aw_ts]").val();
      def = def.replace(/\+/g, "%2b");
      def = def.replace(/;/g, ";;");
      location = location.pathname+"?detail="+nm+"&cmd=modify "+addcsrf(def);
    });
  }
</script>
EOF
 
  my @d = split(" ",$hash->{DEF},2);
  LoadModule("notify");
  my ($h2, $j2) = notfy_addFWCmd($d, $d[0], 2);
  return "$h1$h2</table></div><br>$j1$j2";
}

1;

=pod
=item summary    start an FHEM command at a later time
=item summary_DE FHEM Befehl zu einem sp&auml;teren Zeitpunkt starten
=item helper
=begin html

<a name="at"></a>
<h3>at</h3>
<ul>

  Start an arbitrary FHEM command at a later time.<br>
  <br>

  <a name="atdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; at [&lt;timespec&gt;|&lt;datespec&gt;]
                &lt;command&gt;</code><br>
    <br>
    <code>&lt;timespec&gt;</code> format: [+][*{N}]&lt;timedet&gt;<br>
    <ul>
      The optional <code>+</code> indicates that the specification is
      <i>relative</i>(i.e. it will be added to the current time).<br>
      The optional <code>*</code> indicates that the command should be
      executed <i>repeatedly</i>.<br>
      The optional <code>{N}</code> after the * indicates,that the command
      should be repeated <i>N-times</i> only.<br>

      &lt;timespec&gt; is either HH:MM, HH:MM:SS or {perlfunc()}. perlfunc must
      return a string in timedet format.  Note: {perlfunc()} may not contain
      any spaces or tabs.<br>

      &lt;datespec&gt; is either ISO8601 (YYYY-MM-DDTHH:MM:SS) or number of
      seconds since 1970.
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
    define a5 at +00:00:10 set lamp on                 # switch on in 10 seconds
    define a6 at +00:00:02 set lamp on-for-timer 1     # Blink once in 2 seconds
    define a7 at +*{3}00:00:02 set lamp on-for-timer 1 # Blink 3 times

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
    define a14 at *{sunrise(+120)} set lamp on

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
  <b>Set</b>
  <ul>
    <a name="modifyTimeSpec"></a>
    <li>modifyTimeSpec &lt;timespec&gt;<br>
        Change the execution time. Note: the N-times repetition is ignored.
        It is intended to be used in combination with
        <a href="#webCmd">webCmd</a>, for an easier modification from the room
        overview in FHEMWEB.</li>
    <li>inactive<br>
        Inactivates the current device. Note the slight difference to the
        disable attribute: using set inactive the state is automatically saved
        to the statefile on shutdown, there is no explicit save necesary.<br>
        This command is intended to be used by scripts to temporarily
        deactivate the at.<br>
        The concurrent setting of the disable attribute is not recommended.
        </li>
    <li>active<br>
        Activates the current device (see inactive).</li>
    <li>execNow<br>
        Execute the command associated with the at. The execution of a relative
        at is not affected by this command.</li>
  </ul><br>



  <a name="atget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="atattr"></a>
  <b>Attributes</b>
  <ul>
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
        attr at2 alignTime 00:00<br>
        </ul>
        </li><br>

    <a name="computeAfterInit"></a>
    <li>computeAfterInit<br>
        If perlfunc() in the timespec relies on some other/dummy readings, then
        it will return a wrong time upon FHEM start, as the at define is
        processed before the readings are known. If computeAfterInit is set,
        FHEM will recompute timespec after the initialization is finished.
        </li><br>

    <a name="disable"></a>
    <li>disable<br>
        Can be applied to at/watchdog/notify/FileLog devices.<br>
        Disables the corresponding at/notify or FileLog device. Note:
        If applied to an <a href="#at">at</a>, the command will not be executed,
        but the next time will be computed.</li><br>

    <a name="disabledForIntervals"></a>
    <li>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM...<br>
        Space separated list of HH:MM or D@HH:MM tupels. If the current time is
        between the two time specifications, the current device is disabled.
        Instead of HH:MM you can also specify HH or HH:MM:SS. D is the day of
        the week, with 0 indicating Sunday and 3 indicating Wednesday. To
        specify an interval spawning midnight, you have to specify two
        intervals, e.g.:
        <ul>
          23:00-24:00 00:00-01:00
        </ul>
        If parts of the attribute value are enclosed in {}, they are evaluated:
        <ul>
          {sunset_abs()}-24 {sunrise_abs()}-08
        </ul>
        </li><br>

    <a name="skip_next"></a>
    <li>skip_next<br>
        Used for at commands: skip the execution of the command the next
        time.</li><br>

    <li><a href="#perlSyntaxCheck">perlSyntaxCheck</a></li>

  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="at"></a>
<h3>at</h3>
<ul>

  Startet einen beliebigen FHEM Befehl zu einem sp&auml;teren Zeitpunkt.<br>
  <br>

  <a name="atdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; at [&lt;timespec&gt;|&lt;datespec&gt;]
                &lt;command&gt;</code><br>
    <br>
    <code>&lt;timespec&gt;</code> Format: [+][*{N}]&lt;timedet&gt;<br>
    <ul>
      Das optionale <code>+</code> zeigt, dass die Angabe <i>relativ</i> ist 
      (also zur jetzigen Zeit dazugez&auml;hlt wird).<br>

      Das optionale <code>*</code> zeigt, dass die Ausf&uuml;hrung
      <i>wiederholt</i> erfolgen soll.<br>

      Das optionale <code>{N}</code> nach dem * bedeutet, dass der Befehl genau
      <i>N-mal</i> wiederholt werden soll.<br>

      &lt;timespec&gt; ist entweder HH:MM, HH:MM:SS oder {perlfunc()}.  perlfunc
      muss ein String in timedet Format zurueckliefern.  Achtung: {perlfunc()}
      darf keine Leerzeichen enthalten.<br>

      &lt;datespec&gt; ist entweder ISO8601 (YYYY-MM-DDTHH:MM:SS) oder Anzahl
      der Sekunden seit 1970.

    </ul>
    <br>

    Beispiele:
    <PRE>
    # Absolute Beispiele:
    define a1 at 17:00:00 set lamp on                            # fhem Befehl
    define a2 at 17:00:00 { Log 1, "Teatime" }                   # Perl Befehl
    define a3 at 17:00:00 "/bin/echo "Teatime" > /dev/console"   # shell Befehl
    define a4 at *17:00:00 set lamp on                           # Jeden Tag

    # Realtive Beispiele:
    define a5 at +00:00:10 set lamp on                  # Einschalten in 10 Sekunden
    define a6 at +00:00:02 set lamp on-for-timer 1      # Einmal blinken in 2 Sekunden
    define a7 at +*{3}00:00:02 set lamp on-for-timer 1  # Blinke 3 mal

    # Blinke 3 mal wenn  piri einen Befehl sendet
    define n1 notify piri:on.* define a8 at +*{3}00:00:02 set lamp on-for-timer 1

    # Lampe von Sonnenuntergang bis 23:00 Uhr einschalten
    define a9 at +*{sunset_rel()} set lamp on
    define a10 at *23:00:00 set lamp off

    # Elegantere Version, ebenfalls von Sonnenuntergang bis 23:00 Uhr
    define a11 at +*{sunset_rel()} set lamp on-till 23:00

    # Nur am Wochenende ausf&uuml;hren
    define a12 at +*{sunset_rel()} { fhem("set lamp on-till 23:00") if($we) }

    # Schalte lamp1 und lamp2 ein von 7:00 bis 10 Minuten nach Sonnenaufgang
    define a13 at *07:00 set lamp1,lamp2 on-till {sunrise(+600)}

    # Schalte lamp jeden Tag 2 Minuten nach Sonnenaufgang aus
    define a14 at *{sunrise(+120)} set lamp on

    # Schalte lamp1 zum Sonnenuntergang ein, aber nicht vor 18:00 und nicht nach 21:00
    define a15 at *{sunset(0,"18:00","21:00")} set lamp1 on

    </PRE>

    Hinweise:<br>
    <ul>
      <li>wenn kein <code>*</code> angegeben wird, wird der Befehl nur einmal
      ausgef&uuml;hrt und der entsprechende <code>at</code> Eintrag danach
      gel&ouml;scht. In diesem Fall wird der Befehl im Statefile gespeichert
      (da er nicht statisch ist) und steht nicht im Config-File (siehe auch <a
      href="#save">save</a>).</li>

      <li>wenn die aktuelle Zeit gr&ouml;&szlig;er ist als die angegebene Zeit,
      dann wird der Befehl am folgenden Tag ausgef&uuml;hrt.</li>

      <li>F&uuml;r noch komplexere Datums- und Zeitabl&auml;ufe muss man den
      Aufruf entweder per cron starten oder Datum/Zeit mit perl weiter
      filtern. Siehe hierzu das letzte Beispiel und das <a href="#perl">Perl
      special</a>.  </li>

    </ul>
    <br>
  </ul>


  <a name="atset"></a>
  <b>Set</b>
  <ul>
    <a name="modifyTimeSpec"></a>
    <li>modifyTimeSpec &lt;timespec&gt;<br>
        &Auml;ndert die Ausf&uuml;hrungszeit. Achtung: die N-malige
        Wiederholungseinstellung wird ignoriert. Gedacht zur einfacheren
        Modifikation im FHEMWEB Raum&uuml;bersicht, dazu muss man
        modifyTimeSpec in <a href="webCmd">webCmd</a> spezifizieren.
        </li>
    <li>inactive<br>
        Deaktiviert das entsprechende Ger&auml;t. Beachte den leichten
        semantischen Unterschied zum disable Attribut: "set inactive"
        wird bei einem shutdown automatisch in fhem.state gespeichert, es ist
        kein save notwendig.<br>
        Der Einsatzzweck sind Skripte, um das at tempor&auml;r zu
        deaktivieren.<br>
        Das gleichzeitige Verwenden des disable Attributes wird nicht empfohlen.
        </li>
    <li>active<br>
        Aktiviert das entsprechende Ger&auml;t, siehe inactive.
        </li>
    <li>execNow<br>
        F&uuml;hrt das mit dem at spezifizierte Befehl aus. Beeinflu&szlig;t
        nicht die Ausf&uuml;hrungszeiten relativer Spezifikationen.
        </li>
  </ul><br>


  <a name="atget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="atattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="alignTime"></a>
    <li>alignTime<br>
        Nur f&uuml;r relative Definitionen: Stellt den Zeitpunkt der
        Ausf&uuml;hrung des Befehls so, dass er auch zur alignTime
        ausgef&uuml;hrt wird.  Dieses Argument ist ein timespec. Siehe oben
        f&uuml; die Definition<br>

        Beispiel:<br>
        <ul>
        # Stelle sicher das es gongt wenn eine neue Stunde beginnt.<br>
        define at2 at +*01:00 set Chime on-for-timer 1<br>
        attr at2 alignTime 00:00<br>
        </ul>
        </li><br>

    <a name="computeAfterInit"></a>
    <li>computeAfterInit<br>
        Falls perlfunc() im timespec Readings or Statusinformationen
        ben&ouml;gt, dann wird sie eine falsche Zeit beim FHEM-Start
        zurueckliefern, da zu diesem Zeitpunkt die Readings noch nicht aktiv
        sind. Mit gesetztem computeAfterInit wird perlfunc nach Setzen aller
        Readings erneut ausgefuehrt. (Siehe Forum #56706)
        </li><br>

    <a name="disable"></a>
    <li>disable<br>
        Deaktiviert das entsprechende Ger&auml;t.<br>
        Hinweis: Wenn angewendet auf ein <a href="#at">at</a>, dann wird der
        Befehl nicht ausgef&uuml;hrt, jedoch die n&auml;chste
        Ausf&uuml;hrungszeit berechnet.</li><br>

    <a name="disabledForIntervals"></a>
    <li>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM...<br>
        Das Argument ist eine Leerzeichengetrennte Liste von Minuszeichen-
        getrennten HH:MM oder D@HH:MM Paaren. Falls die aktuelle Uhrzeit
        zwischen diesen Werten f&auml;llt, dann wird die Ausf&uuml;hrung, wie
        beim disable, ausgesetzt. Statt HH:MM kann man auch HH oder HH:MM:SS
        angeben.  D ist der Tag der Woche, mit 0 als Sonntag and 3 als
        Mittwoch.  Um einen Intervall um Mitternacht zu spezifizieren, muss man
        zwei einzelne angeben, z.Bsp.:
        <ul>
          23:00-24:00 00:00-01:00
        </ul>
        Falls Teile des Wertes in {} eingeschlossen sind, dann werden sie als
        ein Perl Ausdruck ausgewertet:
        <ul>
          {sunset_abs()}-24 {sunrise_abs()}-08
        </ul>
        </li><br>

    <a name="skip_next"></a>
    <li>skip_next<br>
        Wird bei at Befehlen verwendet um die n&auml;chste Ausf&uuml;hrung zu
        &uuml;berspringen</li><br>

    <li><a href="#perlSyntaxCheck">perlSyntaxCheck</a></li>

  </ul>
  <br>

</ul>

=end html_DE

=cut

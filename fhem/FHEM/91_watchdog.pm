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
  $hash->{AttrFn}   = "watchdog_Attr";
  $hash->{SetFn}    = "watchdog_Set";
  $hash->{NotifyFn} = "watchdog_Notify";
  no warnings 'qw';
  my @attrList = qw(
    activateOnStart:0,1
    addStateEvent:0,1
    autoRestart:0,1
    disable:0,1
    disabledForIntervals
    execOnReactivate
    regexp1WontReactivate:0,1
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);

  # acivateOnStart handling
  InternalTimer(1, sub() {
    my @arr = devspec2array("TYPE=watchdog");
    my $now = time();
    foreach my $wd (@arr) {
      next if(!AttrVal($wd, "activateOnStart", 0));
      my $wh = $defs{$wd};
      my $aTime = ReadingsTimestamp($wd, "Activated", undef);
      my $tTime = ReadingsTimestamp($wd, "Triggered", undef);
      next if(!$aTime ||
              ($tTime && $tTime gt $aTime) ||
              time_str2num($aTime)+$wh->{TO} <= $now);
      my $remaining = time_str2num($aTime)+$wh->{TO};
      watchdog_Activate($wh, $remaining);
    }
  }, 1) if(!$init_done);
}


#####################################
# defined watchme watchdog reg1 timeout reg2 command
sub
watchdog_Define($$)
{
  my ($watchdog, $def) = @_;
  my ($name, $type, $re1, $to, $re2, $cmd) = split("[ \t]+", $def, 6);
  

  if(defined($watchdog->{TO})) { # modify
    $re1 = $watchdog->{RE1} if(!defined($re1));
    $to  = $watchdog->{TO}  if(!defined($to));
    $re2 = $watchdog->{RE2} if(!defined($re2));
    $cmd = $watchdog->{CMD} if(!defined($cmd));
    $watchdog->{DEF} = "$re1 $to $re2 $cmd";

  } else {
    return "Usage: define <name> watchdog <re1> <timeout> <re2> <command>"
      if(!$cmd);

  }

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
  $watchdog->{CMD} = $cmd;

  if($re1 eq ".") {
    watchdog_Activate($watchdog)

  } else {
    $watchdog->{STATE} = "defined";

  }

  InternalTimer(1, sub($){
    my $re = ($re1 eq "." ? "" : $re1).
             (($re2 eq "SAME" || $re2 eq $re1) ? "" : "|$re2");
    $re .= "|$name";    # for trigger w .
    notifyRegexpChanged($watchdog, $re);
  }, $watchdog, 0);

  return undef;
}

#####################################
sub
watchdog_Notify($$)
{
  my ($watchdog, $dev) = @_;

  my $ln = $watchdog->{NAME};
  return "" if(IsDisabled($ln) || $watchdog->{STATE} eq "inactive");
  my $dontReAct = AttrVal($ln, "regexp1WontReactivate", 0);

  my $n   = $dev->{NAME};
  my $re1 = $watchdog->{RE1};
  my $re2 = $watchdog->{RE2};
  
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  my $max = int(@{$events});

  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $dotTrigger = ($ln eq $n && $s eq "."); # trigger w .

    if($watchdog->{STATE} =~ m/Next:/) {

      if($dotTrigger) {
        RemoveInternalTimer($watchdog);
        $watchdog->{STATE} = "defined";
        return;
      }

      if($n =~ m/^$re2$/ || "$n:$s" =~ m/^$re2$/) {
        my $isRe1 = ($re1 eq $re2 || $re1 eq ".");
        return if($isRe1 && $dontReAct); # 60414

        RemoveInternalTimer($watchdog);

        if($re1 eq $re2 || $re1 eq ".") {
          watchdog_Activate($watchdog);
          return "";

        } else {
          $watchdog->{STATE} = "defined";

        }

      } elsif($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/) {
        watchdog_Activate($watchdog) if(!$dontReAct);

      }

    } elsif($watchdog->{STATE} eq "defined") {
      if($dotTrigger || ($n =~ m/^$re1$/ || "$n:$s" =~ m/^$re1$/)) {
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

  if(IsDisabled($name) || $watchdog->{STATE} eq "inactive") {
    $watchdog->{STATE} = "defined";
    return "";
  }

  Log3 $name, 3, "Watchdog $name triggered";
  my $exec = SemicolonEscape($watchdog->{CMD});
  $watchdog->{STATE} = "triggered";
  
  setReadingsVal($watchdog, "Triggered", "triggered", TimeNow());
  
  my $ret = AnalyzeCommandChain(undef, $exec);
  Log3 $name, 3, $ret if($ret);

  if(AttrVal($name, "autoRestart", 0)) {
      $watchdog->{STATE} = "defined";       # auto trigger w . 
  }
}

sub
watchdog_Activate($;$)
{
  my ($watchdog, $remaining) = @_;
  my $nt = ($remaining ? $remaining : gettimeofday() + $watchdog->{TO});
  $watchdog->{STATE} = "Next: " . FmtTime($nt);
  RemoveInternalTimer($watchdog);
  InternalTimer($nt, "watchdog_Trigger", $watchdog, 0);

  my $eor = AttrVal($watchdog->{NAME}, "execOnReactivate", undef);
  if($eor) {
    my $wName = $watchdog->{NAME};
    my $aTime = ReadingsTimestamp($wName, "Activated", "");
    my $tTime = ReadingsTimestamp($wName, "Triggered", "");
    $eor = undef if(!$aTime || !$tTime || $aTime ge $tTime)
  }
  setReadingsVal($watchdog, "Activated","activated", TimeNow()) if(!$remaining);

  AnalyzeCommandChain(undef, SemicolonEscape($eor)) if($eor);
}

sub
watchdog_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($hash);
  return undef;
}

sub
watchdog_Attr(@)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $do = 0;

  my $hash = $defs{$name};

  if($cmd eq "set" && $attrName eq "disable") {
    $do = (!defined($attrVal) || $attrVal) ? 1 : 2;
  }
  $do = 2 if($cmd eq "del" && (!$attrName || $attrName eq "disable"));
  return if(!$do);
  $hash->{STATE} = ($do == 1 ?  "disabled" : "defined");
  return undef;
}

sub
watchdog_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};

  return "no set argument specified" if(int(@a) < 2);
  my %sets = (inactive=>0, active=>0);
  
  my $cmd = $a[1];
  return "Unknown argument $cmd, choose one of ".join(" ", sort keys %sets)
    if(!defined($sets{$cmd}));
  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 2);

  if($cmd eq "inactive") {
    readingsSingleUpdate($hash, "state", "inactive", 1);

  }
  elsif($cmd eq "active") {
    readingsSingleUpdate($hash, "state", "defined", 1)
        if(!AttrVal($me, "disable", undef));
  }
  
  return undef;
}

1;

=pod
=item helper
=item summary    execute a command, if no event is received within timeout
=item summary_DE f&uuml;hrt Befehl aus, falls innerhalb des Timeouts kein Event empfangen wurde
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
    Start an arbitrary FHEM command if after &lt;timespec&gt; receiving an
    event matching &lt;regexp1&gt; no event matching &lt;regexp2&gt; is
    received.<br>
    The syntax for &lt;regexp1&gt; and &lt;regexp2&gt; is the same as the
    regexp for <a href="#notify">notify</a>.<br>
    &lt;timespec&gt; is HH:MM[:SS]<br>
    &lt;command&gt; is a usual fhem command like used in the <a
    href="#at">at</a> or <a href="#notify">notify</a>
    <br><br>

    Examples:
    <code><ul>
    # Request data from the FHT80 _once_ if we do not receive any message for<br>
    # 15 Minutes.<br>
    define w watchdog FHT80 00:15:00 SAME set FHT80 date<br>

    # Request data from the FHT80 _each_ time we do not receive any message for
    <br>
    # 15 Minutes, i.e. reactivate the watchdog after it triggered.  Might be<br>
    # dangerous, as it can trigger in a loop.<br>
    define w watchdog FHT80 00:15:00 SAME set FHT80 date;; trigger w .<br>

    # Shout once if the HMS100-FIT is not alive<br>
    define w watchdog HMS100-FIT 01:00:00 SAME "alarm-fit.sh"<br>

    # Send mail if the window is left open<br>
    define w watchdog contact1:open 00:15 contact1:closed
        "mail_me close window1"<br>
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
          is defined, and set it into state defined if its state is active
          (Next:...) or triggered. You always have to reactivate the watchdog
          with this command once it has triggered (unless you restart
          fhem)</li>
      <li>a generic watchdog (one watchdog responsible for more devices) is
          currently not possible.</li>
      <li>with modify all parameters are optional, and will not be changed if
          not specified.</li>
    </ul>

    <br>
  </ul>

  <a name="watchdogset"></a>
  <b>Set </b>
  <ul>
    <li>inactive<br>
        Inactivates the current device. Note the slight difference to the
        disable attribute: using set inactive the state is automatically saved
        to the statefile on shutdown, there is no explicit save necesary.<br>
        This command is intended to be used by scripts to temporarily
        deactivate the notify.<br>
        The concurrent setting of the disable attribute is not recommended.</li>
    <li>active<br>
        Activates the current device (see inactive).</li>
    </ul>
    <br>

  <a name="watchdogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="watchdogattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="#activateOnStart">activateOnStart</a><br>
      if set, the watchdog will be activated after a FHEM start if appropriate,
      determined by the Timestamp of the Activated and the Triggered readings.
      Note: since between shutdown and startup events may be missed, this
      attribute is 0 (disabled) by default.
    </li>

    <li><a href="#addStateEvent">addStateEvent</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <li><a name="regexp1WontReactivate">regexp1WontReactivate</a><br>
        When a watchdog is active, a second event matching regexp1 will
        normally reset the timeout. Set this attribute to prevents this.</li>

    <li><a href="#execOnReactivate">execOnActivate</a>
      If set, its value will be executed as a FHEM command when the watchdog is
      reactivated (after triggering) by receiving an event matching regexp1.
      </li>
    <li><a href="#autoRestart">autoRestart</a>
      When the watchdog has triggered it will be automatically re-set to state
      defined again (waiting for regexp1) if this attribute is set to 1.
    </li>
  </ul>
  <br>
</ul>

=end html

=begin html_DE

<a name="watchdog"></a>
<h3>watchdog</h3>
<ul>
  <br>

  <a name="watchdogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; watchdog &lt;regexp1&gt; &lt;timespec&gt;
    &lt;regexp2&gt; &lt;command&gt;</code><br>
    <br>

    Startet einen beliebigen FHEM Befehl wenn nach dem Empfang des
    Ereignisses &lt;regexp1&gt; nicht innerhalb von &lt;timespec&gt; ein
    &lt;regexp2&gt; Ereignis empfangen wird.<br>

    Der Syntax f&uuml;r &lt;regexp1&gt; und &lt;regexp2&gt; ist der gleiche wie
    regexp f&uuml;r <a href="#notify">notify</a>.<br>

    &lt;timespec&gt; ist HH:MM[:SS]<br>

    &lt;command&gt; ist ein gew&ouml;hnlicher fhem Befehl wie z.B. in <a
    href="#at">at</a> oderr <a href="#notify">notify</a>
    <br><br>

    Beispiele:
    <code><ul>
    # Frage Daten vom FHT80 _einmalig_ ab, wenn wir keine Nachricht f&uuml;r<br>
    # 15 Minuten erhalten haben.<br>
    define w watchdog FHT80 00:15:00 SAME set FHT80 date<br><br>

    # Frage Daten vom FHT80 jedes Mal ab, wenn keine Nachricht f&uuml;r<br>
    # 15 Minuten emfpangen wurde, d.h. reaktiviere den Watchdog nachdem er
    getriggert wurde.<br>

    # Kann gef&auml;hrlich sein, da er so in einer Schleife getriggert werden
    kann.<br>
    define w watchdog FHT80 00:15:00 SAME set FHT80 date;; trigger w .<br><br>

    # Alarmiere einmalig wenn vom HMS100-FIT f&uuml;r eine Stunde keine
    Nachricht empfangen wurde.<br>
    define w watchdog HMS100-FIT 01:00 SAME "alarm-fit.sh"<br><br>

    # Sende eine Mail wenn das Fenster offen gelassen wurde<br>
    define w watchdog contact1:open 00:15 contact1:closed "mail_me close
    window1"<br>
    attr w regexp1WontReactivate<br><br>
    </ul></code>

    Hinweise:<br>
    <ul>
      <li>Wenn &lt;regexp1&gt; . (Punkt) ist, dann aktiviere den Watchdog zur
      definierten Zeit.  Sonst wird er durch den Empfang des ersten passenden
      Events aktiviert.</li>

      <li>&lt;regexp1&gt; Resetet den Timer eines laufenden Watchdogs. Um das
      zu verhindern wird das regexp1WontReactivate Attribut gesetzt.</li>

      <li>Wenn &lt;regexp2&gt; SAME ist , dann ist es das gleiche wie das erste
      regexp, und wird reaktiviert wenn es empfangen wird.  </li>

      <li>trigger &lt;watchdogname&gt; . aktiviert den Trigger wenn dessen
      Status defined ist und setzt ihn in den Status defined wenn sein status
      triggered oder aktiviert (Next:...) ist.<br>

      Der Watchdog musst immer mit diesem Befehl reaktiviert werden wenn er
      getriggert wurde.</li>

      <li>Ein generischer Watchdog (ein Watchdog, verantwortlich f&uuml;r
      mehrere Devices) ist derzeit nicht m&ouml;glich.</li>

      <li>Bei modify sind alle Parameter optional, und werden nicht geaendert,
      falls nicht spezifiziert.</li>

    </ul>

    <br>
  </ul>

  <a name="watchdogset"></a>
  <b>Set </b>
  <ul>
    <li>inactive<br>
        Deaktiviert das entsprechende Ger&auml;t. Beachte den leichten
        semantischen Unterschied zum disable Attribut: "set inactive"
        wird bei einem shutdown automatisch in fhem.state gespeichert, es ist
        kein save notwendig.<br>
        Der Einsatzzweck sind Skripte, um das notify tempor&auml;r zu
        deaktivieren.<br>
        Das gleichzeitige Verwenden des disable Attributes wird nicht empfohlen.
        </li>
    <li>active<br>
        Aktiviert das entsprechende Ger&auml;t, siehe inactive.
        </li>
    </ul>
    <br>


  <a name="watchdogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="watchdogattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a name="#activateOnStart">activateOnStart</a><br>
      Falls gesetzt, wird der Watchdog nach FHEM-Neustart aktiviert, je nach
      Zeitstempel der Activated und Triggered Readings. Da zwischen Shutdown
      und Neustart Events verlorengehen k&ouml;nnen, ist die Voreinstellung 0
      (deaktiviert).
    </li>


    <li><a href="#addStateEvent">addStateEvent</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>
    <li><a name="regexp1WontReactivate">regexp1WontReactivate</a><br>
      Wenn ein Watchdog aktiv ist, wird ein zweites Ereignis das auf regexp1
      passt normalerweise den Timer zur&uuml;cksetzen. Dieses Attribut wird
      das verhindern.</li>

    <li><a href="#execOnReactivate">execOnActivate</a>
      Falls gesetzt, wird der Wert des Attributes als FHEM Befehl
      ausgef&uuml;hrt, wenn ein regexp1 Ereignis den Watchdog
      aktiviert nachdem er ausgel&ouml;st wurde.</li>

    <li><a href="#autoRestart">autoRestart</a>
      Wenn dieses Attribut gesetzt ist, wird der Watchdog nach dem er
      getriggert wurde, automatisch wieder in den Zustand defined
      gesetzt (Wartet also wieder auf Aktivierung durch regexp1)</li>
  </ul>

  <br>
</ul>

=end html_DE
=cut

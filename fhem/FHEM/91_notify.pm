##############################################
# $Id$
package main;

use strict;
use warnings;
use vars qw($FW_ME);      # webname (default is fhem)

#####################################
sub
notify_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "notify_Define";
  $hash->{NotifyFn} = "notify_Exec";
  $hash->{AttrFn}   = "notify_Attr";
  $hash->{AttrList} ="disable:1,0 disabledForIntervals forwardReturnValue:1,0 ".
                     "readLog:1,0 showtime:1,0 addStateEvent:1,0 ignoreRegexp";
  $hash->{SetFn}    = "notify_Set";
  $hash->{StateFn}  = "notify_State";
  $hash->{FW_detailFn} = "notify_fhemwebFn";
}


#####################################
sub
notify_Define($$)
{
  my ($hash, $def) = @_;
  my ($name, $type, $re, $command) = split("[ \t\n]+", $def, 4);

  if(!$command) {
    if($hash->{OLDDEF}) { # Called from modify, where command is optional
      (undef, $command) = split("[ \t]+", $hash->{OLDDEF}, 2);
      $hash->{DEF} = "$re $command";
    } else {
      return "Usage: define <name> notify <regexp> <command>";
    }
  }

  # Checking for misleading regexps
  return "Bad regexp: starting with *" if($re =~ m/^\*/);
  eval { "Hallo" =~ m/^$re$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $re;
  my %specials= (
    "%NAME" => $name,
    "%TYPE" => $name,
    "%EVENT" => "1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0",
    "%SELF" => $name,
  );
  my $err = perlSyntaxCheck($command, %specials);
  return $err if($err);
  $hash->{".COMMAND"} = $command;

  my $doTrigger = ($name !~ m/^$re$/);            # Forum #34516
  readingsSingleUpdate($hash, "state", "active", $doTrigger);
  InternalTimer(0, sub(){  notifyRegexpChanged($hash, $re); }, $hash);

  return undef;
}

#####################################
sub
notify_Exec($$)
{
  my ($ntfy, $dev) = @_;

  my $ln = $ntfy->{NAME};
  return "" if(IsDisabled($ln));

  my $n = $dev->{NAME};
  my $re = $ntfy->{REGEXP};
  my $iRe = AttrVal($ln, "ignoreRegexp", undef);
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  return if(!$events); # Some previous notify deleted the array.
  my $max = int(@{$events});
  my $t = $dev->{TYPE};

  my $ret = "";
  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $found = ($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/);
    if(!$found && AttrVal($n, "eventMap", undef)) {
      my @res = ReplaceEventMap($n, [$n,$s], 0);
      shift @res;
      $s = join(" ", @res);
      $found = ("$n:$s" =~ m/^$re$/);
    }
    if($found) {
      next if($iRe && ($n =~ m/^$iRe$/ || "$n:$s" =~ m/^$iRe$/));
      Log3 $ln, 5, "Triggering $ln";
      my %specials= (
                "%NAME" => $n,
                "%TYPE" => $t,
                "%EVENT" => $s,
                "%SELF" => $ln
      );
      my $exec = EvalSpecials($ntfy->{".COMMAND"}, %specials);

      Log3 $ln, 4, "$ln exec $exec";
      my $r = AnalyzeCommandChain(undef, $exec);
      Log3 $ln, 3, "$ln return value: $r" if($r);
      $ret .= " $r" if($r);
      $ntfy->{STATE} =
        AttrVal($ln,'showtime',1) ? $dev->{NTFY_TRIGGERTIME} : 'active';
    }
  }
  
  return $ret if(AttrVal($ln, "forwardReturnValue", 0));
  return undef;
}

sub
notify_Attr(@)
{
  my @a = @_;
  my $do = 0;
  my $hash = $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "readLog") {
    if(!defined($a[3]) || $a[3]) {
      $logInform{$a[1]} = sub($$){
        my ($me, $msg) = @_;
        return if(defined($hash->{CHANGED}));
        $hash->{CHANGED}[0] = $msg;
        notify_Exec($hash, $hash);
        delete($hash->{CHANGED});
      }
    } else {
      delete $logInform{$a[1]};
    }
    return;
  }

  if($a[0] eq "set" && $a[2] eq "ignoreRegexp") {
    return "Missing argument for ignoreRegexp" if(!defined($a[3]));
    eval { "HALLO" =~ m/$a[3]/ };
    return $@;
  }

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  readingsSingleUpdate($hash, "state", $do==1 ? "disabled":"active", 1);
  return undef;
}

###################################

sub
notify_Set($@)
{
  my ($hash, @a) = @_;
  my $me = $hash->{NAME};

  return "no set argument specified" if(int(@a) < 2);
  my %sets = (addRegexpPart=>2, removeRegexpPart=>1, inactive=>0, active=>0);
  
  my $cmd = $a[1];
  if(!defined($sets{$cmd})) {
    my $ret ="Unknown argument $cmd, choose one of ".join(" ", sort keys %sets);
    $ret =~ s/active/active:noArg/g;
    return $ret;
  }
  return "$cmd needs $sets{$cmd} parameter(s)" if(@a-$sets{$cmd} != 2);

  if($cmd eq "addRegexpPart") {
    my %h;
    my $re = "$a[2]:$a[3]";
    map { $h{$_} = 1 } split(/\|/, $hash->{REGEXP});
    $h{$re} = 1;
    $re = join("|", sort keys %h);
    return "Bad regexp: starting with *" if($re =~ m/^\*/);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp: $@" if($@);
    $hash->{REGEXP} = $re;
    $hash->{DEF} = "$re ".$hash->{".COMMAND"};
    notifyRegexpChanged($hash, $re);
    
  } elsif($cmd eq "removeRegexpPart") {
    my %h;
    map { $h{$_} = 1 } split(/\|/, $hash->{REGEXP});
    return "Cannot remove regexp part: not found" if(!$h{$a[2]});
    return "Cannot remove last regexp part" if(int(keys(%h)) == 1);
    delete $h{$a[2]};
    my $re = join("|", sort keys %h);
    return "Bad regexp: starting with *" if($re =~ m/^\*/);
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp: $@" if($@);
    $hash->{REGEXP} = $re;
    $hash->{DEF} = "$re ".$hash->{".COMMAND"};
    notifyRegexpChanged($hash, $re);

  } elsif($cmd eq "inactive") {
    readingsSingleUpdate($hash, "state", "inactive", 1);

  }
  elsif($cmd eq "active") {
    readingsSingleUpdate($hash, "state", "active", 1)
        if(!AttrVal($me, "disable", undef));
  }
  
  return undef;
}

#############
sub
notify_State($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;

  return undef if($vt ne "state" || $val ne "inactive");
  readingsSingleUpdate($hash, "state", "inactive", 1);
  return undef;
}


#########################
sub
notify_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.
  my $hash = $defs{$d};

  my $ret .= "<div class='makeTable wide'><span>Change wizard</span>".
             "<table class='block wide'>";
  my $row = 0;
  my @ra = split(/\|/, $hash->{REGEXP});
  $ret .= "<tr class='".(($row++&1)?"odd":"even").
        "'><td colspan='2'>Change the condition:</td></tr>";
  if(@ra > 1) {
    foreach my $r (@ra) {
      $ret .= "<tr class='".(($row++&1)?"odd":"even")."'>";
      my $cmd = "cmd.X= set $d removeRegexpPart&val.X=$r"; # =.set: avoid JS
      $ret .= "<td>$r</td>";
      $ret .= FW_pH("$cmd&detail=$d", "removeRegexpPart", 1,undef,1);
      $ret .= "</tr>";
    }
  }

  my @et = devspec2array("TYPE=eventTypes");
  if(!@et) {
    $ret .= "<tr class='".(($row++&1)?"odd":"even")."'>";
    $ret .= FW_pH("$FW_ME/docs/commandref.html#eventTypes",
                  "To add a regexp an eventTypes definition is needed",
                  1, undef, 1)."</tr>";
  } else {
    my %dh;
    my $etList = AnalyzeCommand(undef, "get $et[0] list");
    $etList = "" if(!$etList);
    foreach my $l (split("\n", $etList)) {
      my @a = split(/[ \r\n]/, $l);
      $a[1] = "" if(!defined($a[1]));
      $a[1] =~ s/\.\*//g;
      $a[1] =~ s/,.*//g;
      next if(@a < 2);
      $dh{$a[0]}{".*"} = 1;
      $dh{$a[0]}{$a[1].".*"} = 1;
    }
    my $list = "";
    foreach my $dev (sort keys %dh) {
      $list .= " $dev:" . join(",", sort keys %{$dh{$dev}});
    }
    $list =~ s/(['"])/./g;

    $ret .= "<tr class=\"".(($row++&1)?"odd":"even")."\">";
    $ret .= '<td colspan="2">';
    $ret .= FW_detailSelect($d, "set", $list, "addRegexpPart");
    $ret .= "</td></tr>";
  }
  my ($tr, $js) = notfy_addFWCmd($d, $hash->{REGEXP}, $row);
  return "$ret$tr</table></div><br>$js";
}

sub
notfy_addFWCmd($$$)
{
  my ($d, $param, $row) = @_;

  my $ret="";
  $ret .= "<tr class='".(($row++&1)?"odd":"even")."'><td colspan='2'>".
                "&nbsp;</td></tr>";
  $ret .= "<tr class='".(($row++&1)?"odd":"even")."'><td colspan='2'>".
                "Change the executed command:</td></tr>";
  $ret .= "<tr class='".(($row++&1)?"odd":"even")."'><td colspan='2'>";

  my @list = grep { !$defs{$_}{TEMPORARY} && $_ ne $d && 
                    $modules{$defs{$_}{TYPE}}{SetFn} } sort keys %defs;
  $ret .= "<input class='set' id='modCmd' type='submit' value='modify' ".
             "data-d='$d' data-p='$param'>";
  $ret .= "<div class='set downText'>&nbsp;$d $param set </div>";
  $ret .= FW_select("modDev", "mod", \@list, undef, "set");
  $ret .= "<select class='set' id='modArg'></select>";
  $ret .= "<input type='text' name='modVal' size='10'/>";
  $ret .= "</td></tr>";

  my $js = << 'END';
<script>
  var ntArr, ntDev;

  function
  ntfyCmd()
  {
    ntDev=$("#modDev").val();
    FW_cmd(FW_root+
      "?cmd="+addcsrf(encodeURIComponent("set "+ntDev+" ?"))+"&XHR=1",
      function(ret) {
        ret = ret.replace(/[\r\n]/g,'');
        ntArr=ret.substr(ret.indexOf("choose one of")+14,ret.length).split(" ");
        var str="";
        for(var i1=0; i1<ntArr.length; i1++) {
          var off = ntArr[i1].indexOf(":");
          str += "<option value="+i1+">"+
                    (off==-1 ? ntArr[i1] : ntArr[i1].substr(0,off))+
                 "</option>";
        }
        $("#modArg").html(str);
        ntfyArg();
      });
  }

  function
  ntfyArg()
  {
    var v=ntArr[$("#modArg").val()];
    var vArr = [];
    if(v.indexOf(":") > 0)
      vArr = v.substr(v.indexOf(":")+1).split(",");
    FW_replaceWidget($("#modArg").next(), ntDev, vArr);
  }

  function
  ntfyGo()
  {
    var d=$("#modCmd").attr("data-d");
    var p=$("#modCmd").attr("data-p");
    var cmd = "modify "+d+" "+p+" set "+$("#modDev").val()+" "+
              $("#modArg :selected").text()+" "+$("[name=modVal]").val();
    location=FW_root+"?cmd="+addcsrf(encodeURIComponent(cmd))+"&detail="+d;
  }
  
  $(document).ready(function(){
    $("#modDev").change(ntfyCmd);
    $("#modArg").change(ntfyArg);
    $("#modCmd").click(ntfyGo);
    $("#").change(ntfyArg);
    ntfyCmd();
  });
</script>
END

  return ($ret, $js);
}

1;

=pod
=item helper
=item summary    execute a command upon receiving an event
=item summary_DE f&uuml;hrt bei Events Anweisungen aus
=begin html

<a name="notify"></a>
<h3>notify</h3>
<ul>
  <br>

  <a name="notifydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; notify &lt;pattern&gt; &lt;command&gt;</code>
    <br><br>
    Execute a command when received an event for the <a

    href="#define">definition</a> <code>&lt;pattern&gt;</code>. If
    &lt;command&gt; is enclosed in {}, then it is a perl expression, if it is
    enclosed in "", then it is a shell command, else it is a "plain" fhem.pl
    command (chain).  See the <a href="#trigger">trigger</a> command for
    testing it.

    Examples:
    <ul>
      <code>define b3lampV1 notify btn3 set lamp $EVENT</code><br>
      <code>define b3lampV2 notify btn3 { fhem "set lamp $EVENT" }</code><br>
      <code>define b3lampV3 notify btn3 "/usr/local/bin/setlamp "$EVENT""</code><br>
      <code>define b3lampV3 notify btn3 set lamp1 $EVENT;;set lamp2 $EVENT</code><br>
      <code>define wzMessLg notify wz:measured.* "/usr/local/bin/logfht $NAME "$EVENT""</code><br>
      <code>define LogUndef notify global:UNDEFINED.* "send-me-mail.sh "$EVENT""</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li><code>&lt;pattern&gt;</code> is either the name of the triggering
         device, or <code>devicename:event</code>.</li>

      <li><code>&lt;pattern&gt;</code> must completely (!)
        match either the device name, or the compound of the device name and
        the event.  To identify the events use the inform command from the
        telnet prompt or the "Event Monitor" link in the browser
        (FHEMWEB), and wait for the event to be printed. See also the
        eventTypes device.</li>

      <li>in the command section you can access the event:
      <ul>
        <li>The variable $EVENT will contain the complete event, e.g.
          <code>measured-temp: 21.7 (Celsius)</code></li>
        <li>$EVTPART0,$EVTPART1,$EVTPART2,etc contain the space separated event
          parts (e.g. <code>$EVTPART0="measured-temp:", $EVTPART1="21.7",
          $EVTPART2="(Celsius)"</code>. This data is available as a local
          variable in perl, as environment variable for shell scripts, and will
          be textually replaced for FHEM commands.</li>
        <li>$NAME and $TYPE contain the name and type of the device triggering
          the event, e.g. myFht and FHT</li>
       </ul></li>

      <li>Note: the following is deprecated and will be removed in a future
        release. It is only active for featurelevel up to 5.6.
        The described replacement is attempted if none of the above
        variables ($NAME/$EVENT/etc) found in the command.
      <ul>
        <li>The character <code>%</code> will be replaced with the received
        event, e.g. with <code>on</code> or <code>off</code> or
        <code>measured-temp: 21.7 (Celsius)</code><br> It is advisable to put
        the <code>%</code> into double quotes, else the shell may get a syntax
        error.</li>

        <li>The character @ will be replaced with the device
        name.</li>

        <li>To use % or @ in the text itself, use the double mode (%% or
        @@).</li>

        <li>Instead of % and @, the parameters %EVENT (same as %), %NAME (same
        as @) and %TYPE (contains the device type,
        e.g.  FHT) can be used. The space separated event "parts"
        are available as %EVTPART0, %EVTPART1, etc.  A single %
        looses its special meaning if any of these parameters appears in the
        definition.</li>
      </ul></li>

      <li>Following special events will be generated for the device "global"
      <ul>
          <li>INITIALIZED after initialization is finished.</li>
          <li>REREADCFG after the configuration is reread.</li>
          <li>SAVE before the configuration is saved.</li>
          <li>SHUTDOWN before FHEM is shut down.</li>
          <li>DEFINED &lt;devname&gt; after a device is defined.</li>
          <li>DELETED &lt;devname&gt; after a device was deleted.</li>
          <li>RENAMED &lt;old&gt; &lt;new&gt; after a device was renamed.</li>
          <li>UNDEFINED &lt;defspec&gt; upon reception of a message for an
          undefined device.</li>
      </ul></li>

      <li>Notify can be used to store macros for manual execution. Use the <a
          href="#trigger">trigger</a> command to execute the macro.
          E.g.<br>
          <code>fhem> define MyMacro notify MyMacro { Log 1, "Hello"}</code><br>
          <code>fhem> trigger MyMacro</code><br>
          </li>

    </ul>
  </ul>
  <br>


  <a name="notifyset"></a>
  <b>Set </b>
  <ul>
    <li>addRegexpPart &lt;device&gt; &lt;regexp&gt;<br>
        add a regexp part, which is constructed as device:regexp.  The parts
        are separated by |.  Note: as the regexp parts are resorted, manually
        constructed regexps may become invalid. </li>
    <li>removeRegexpPart &lt;re&gt;<br>
        remove a regexp part.  Note: as the regexp parts are resorted, manually
        constructed regexps may become invalid.<br>
        The inconsistency in addRegexpPart/removeRegexPart arguments originates
        from the reusage of javascript functions.</li>
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


  <a name="notifyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="notifyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a name="addStateEvent"></a>
    <li>addStateEvent<br>
      The event associated with the state Reading is special, as the "state: "
      string is stripped, i.e $EVENT is not "state: on" but just "on". In some
      circumstances it is desireable to get the event without "state: "
      stripped. In such a case the addStateEvent attribute should be set to 1
      (default is 0, i.e. strip the "state: " string).<br>

      Note 1: you have to set this attribute for the event "receiver", i.e.
      notify, FileLog, etc.<br>

      Note 2: this attribute will only work for events generated by devices
      supporting the <a href="#readingFnAttributes">readingFnAttributes</a>.
      </li>

    <a name="forwardReturnValue"></a>
    <li>forwardReturnValue<br>
        Forward the return value of the executed command to the caller,
        default is disabled (0).  If enabled (1), then e.g. a set command which
        triggers this notify will also return this value. This can cause e.g
        FHEMWEB to display this value, when clicking "on" or "off", which is
        often not intended.</li>

    <a name="ignoreRegexp"></a>
    <li>ignoreRegexp regexp<br>
        It is hard to create a regexp which is _not_ matching something, this
        attribute helps in this case, as the event is ignored if matches the
        argument. The syntax is the same as for the original regexp.
        </li>

    <a name="readLog"></a>
    <li>readLog<br>
        Execute the notify for messages appearing in the FHEM Log. The device
        in this case is set to the notify itself, e.g. checking for the startup
        message looks like:
        <ul><code>
          define n notify n:.*Server.started.* { Log 1, "Really" }<br>
          attr n readLog
        </code></ul>
        </li>

    <a name="perlSyntaxCheck"></a>
    <li>perlSyntaxCheck<br>
        by setting the <b>global</b> attribute perlSyntaxCheck, a syntax check
        will be executed upon definition or modification, if the command is
        perl and FHEM is already started.
        </li>

  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a name="notify"></a>
<h3>notify</h3>
<ul>
  <br>

  <a name="notifydefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; notify &lt;Suchmuster&gt; &lt;Anweisung&gt;</code>
    <br><br>
    F&uuml;hrt eine oder mehrere Anweisungen aus, wenn ein Event generiert
    wurde, was dem &lt;Suchmuster&gt; (Ger&auml;tename oder
    Ger&auml;tename:Event) entspricht.

    Die Anweisung ist einer der FHEM <a href="#command">Befehlstypen</a>.
    Zum Test dient das <a href="#trigger">trigger</a>-Kommando.
    <br><br>

    Beispiele:
    <ul>
      <code>define b3lampV1 notify btn3 set lamp $EVENT</code><br>
      <code>define b3lampV2 notify btn3 { fhem "set lamp $EVENT" }</code><br>
      <code>define b3lampV3 notify btn3 "/usr/local/bin/setlamp
      "$EVENT""</code><br>

      <code>define b3lampV3 notify btn3 set lamp1 $EVENT;;set lamp2
      $EVENT</code><br>

      <code>define wzMessLg notify wz:measured.* "/usr/local/bin/logfht $NAME
      "$EVENT""</code><br>

      <code>define LogUndef notify global:UNDEFINED.* "send-me-mail.sh
      "$EVENT""</code><br>

    </ul>
    <br>

    Hinweise:
    <ul>
      <li><code>&lt;Suchmuster&gt;</code> ist entweder der Name des
      ausl&ouml;senden ("triggernden") Ger&auml;tes oder die Kombination aus
      Ger&auml;t und ausl&ouml;sendem Ereignis (Event)
      <code>Ger&auml;tename:Event</code>.</li>

      <li>Das <code>&lt;Suchmuster&gt;</code> muss exakt (!)
        entweder dem Ger&auml;tenamen entsprechen oder der Zusammenf&uuml;gung
        aus Ger&auml;tename:Event.   Events lassen sich mit "inform" in Telnet
        oder durch Beobachtung des "Event-Monitors" in FHEMWEB ermitteln.</li>

      <li>In der Anweisung von Notify kann das ausl&ouml;sende Ereignis (Event)
        genutzt werden:

        <ul>
          <li>Die Anweisung $EVENT wird das komplette Ereignis (Event)
            beinhalten, z.B.  <code>measured-temp: 21.7 (Celsius)</code></li>

          <li>$EVTPART0,$EVTPART1,$EVTPART2,etc enthalten die durch Leerzeichen
            getrennten Teile des Events der Reihe nach (im Beispiel also
            <code>$EVTPART0="measured-temp:", $EVTPART1="21.7",
            $EVTPART2="(Celsius)"</code>.<br> Diese Daten sind verf&uuml;gbar
            als lokale Variablen in Perl, als Umgebungs-Variablen f&uuml;r
            Shell-Scripts, und werden als Text ausgetauscht in
            FHEM-Kommandos.</li>

          <li>$NAME und $TYPE enthalten den Namen bzw. Typ des Ereignis
            ausl&ouml;senden Ger&auml;tes, z.B. myFht und FHT</li>
       </ul></li>

      <li>Achtung: Folgende Vorgehensweise ist abgek&uuml;ndigt, funktioniert
          bis featurelevel 5.6 und wird in einem zuk&uuml;nftigen Release von
          FHEM nicht mehr unterst&uuml;tzt.  Wenn keine der oben genannten
          Variablen ($NAME/$EVENT/usw.) in der Anweisung gefunden wird, werden
          Platzhalter ersetzt.

        <ul>
          <li>Das Zeichen % wird ersetzt mit dem empfangenen
          Ereignis (Event), z.B. mit on oder off oder
          <code>measured-temp: 21.7 (Celsius)</code>.
          </li>

          <li>Das Zeichen @ wird ersetzt durch den
          Ger&auml;tenamen.</li>

          <li>Um % oder @ im Text selbst benutzen zu k&ouml;nnen, m&uuml;ssen
          sie verdoppelt werden (%% oder @@).</li>

          <li>Anstelle von % und @, k&ouml;nnen die
          Parameter %EVENT (funktionsgleich mit %),
          %NAME (funktionsgleich mit @) und
          %TYPE (enth&auml;lt den Typ des Ger&auml;tes, z.B.
          FHT) benutzt werden. Die von Leerzeichen unterbrochenen
          Teile eines Ereignisses (Event) sind verf&uuml;gbar als %EVTPART0,
          %EVTPART1, usw.  Ein einzeln stehendes % verliert seine
          oben beschriebene Bedeutung, falls auch nur einer dieser Parameter
          in der Definition auftaucht.</li>

        </ul></li>

      <li>Folgende spezielle Ereignisse werden f&uuml;r das Ger&auml;t "global"
      erzeugt:
      <ul>
          <li>INITIALIZED sobald die Initialization vollst&auml;ndig ist.</li>
          <li>REREADCFG nachdem die Konfiguration erneut eingelesen wurde.</li>
          <li>SAVE bevor die Konfiguration gespeichert wird.</li>
          <li>SHUTDOWN bevor FHEM heruntergefahren wird.</li>
          <li>DEFINED &lt;devname&gt; nach dem Definieren eines
          Ger&auml;tes.</li>
          <li>DELETED &lt;devname&gt; nach dem L&ouml;schen eines
          Ger&auml;tes.</li>
          <li>RENAMED &lt;old&gt; &lt;new&gt; nach dem Umbenennen eines
          Ger&auml;tes.</li>
          <li>UNDEFINED &lt;defspec&gt; beim Auftreten einer Nachricht f&uuml;r
          ein undefiniertes Ger&auml;t.</li>
      </ul></li>

      <li>Notify kann dazu benutzt werden, um Makros f&uuml;r eine manuelle
        Ausf&uuml;hrung zu speichern. Mit einem <a
        href="#trigger">trigger</a> Kommando k&ouml;nnen solche Makros dann
        ausgef&uuml;hrt werden.  Z.B.<br> <code>fhem> define MyMacro notify
        MyMacro { Log 1, "Hello"}</code><br> <code>fhem> trigger
        MyMacro</code><br> </li>

    </ul>
  </ul>
  <br>


  <a name="notifyset"></a>
  <b>Set </b>
  <ul>
    <li>addRegexpPart &lt;device&gt; &lt;regexp&gt;<br>
        F&uuml;gt ein regexp Teil hinzu, der als device:regexp aufgebaut ist.
        Die Teile werden nach Regexp-Regeln mit | getrennt.  Achtung: durch
        hinzuf&uuml;gen k&ouml;nnen manuell erzeugte Regexps ung&uuml;ltig
        werden.</li>
    <li>removeRegexpPart &lt;re&gt;<br>
        Entfernt ein regexp Teil.  Die Inkonsistenz von addRegexpPart /
        removeRegexPart-Argumenten hat seinen Ursprung in der Wiederverwendung
        von Javascript-Funktionen.</li>
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

  <a name="notifyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="notifyattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a name="addStateEvent"></a>
    <li>addStateEvent<br>
      Das mit dem state Reading verkn&uuml;pfte Event ist speziell, da das
      dazugeh&ouml;rige Prefix "state: " entfernt wird, d.h. $EVENT ist nicht
      "state: on", sondern nur "on". In manchen F&auml;llen ist es aber
      erw&uuml;nscht das unmodifizierte Event zu bekommen, d.h. wo "state: "
      nicht entfernt ist. F&uuml;r diese F&auml;lle sollte addStateEvent auf 1
      gesetzt werden, die Voreinstellung ist 0 (deaktiviert).<br>

      Achtung:
      <ul>
        <li>dieses Attribut muss beim Empf&auml;nger (notify, FileLog, etc)
        gesetzt werden.</li>

        <li>dieses Attribut zeigt nur f&uuml;r solche Ger&auml;te-Events eine
        Wirkung, die <a href="#readingFnAttributes">readingFnAttributes</a>
        unterst&uuml;tzen.</li>
      </ul>
      </li>

    <a name="forwardReturnValue"></a>
    <li>forwardReturnValue<br>
        R&uuml;ckgabe der Werte eines ausgef&uuml;hrten Kommandos an den
        Aufrufer.  Die Voreinstellung ist 0 (ausgeschaltet), um weniger
        Meldungen im Log zu haben.
        </li>

    <a name="ignoreRegexp"></a>
    <li>ignoreRegexp regexp<br>
        Es ist nicht immer einfach ein Regexp zu bauen, was etwas _nicht_
        matcht. Dieses Attribu hilft in diesen F&auml;llen: das Event wird
        ignoriert, falls den angegebenen Regexp. Syntax ist gleich wie in der
        Definition.
        </li>

    <a name="readLog"></a>
    <li>readLog<br>
        Das notify wird f&uuml;r Meldungen, die im FHEM-Log erscheinen,
        ausgegef&uuml;hrt. Das "Event-Generierende-Ger&auml;t" wird auf dem
        notify selbst gesetzt. Z.Bsp. kann man mit folgendem notify auf die
        Startup Meldung reagieren:
        <ul><code>
          define n notify n:.*Server.started.* { Log 1, "Wirklich" }<br>
          attr n readLog
        </code></ul>
        </li>

    <a name="perlSyntaxCheck"></a>
    <li>perlSyntaxCheck<br>
        nach setzen des <b>global</b> Attributes perlSyntaxCheck wird eine 
        Syntax-Pr&uuml;fung der Anweisung durchgef&uuml;hrt bei jeder
        &Auml;nderung (define oder modify), falls die Anweisung Perl ist, und
        FHEM bereits gestartet ist.  </li>

  </ul>
  <br>

</ul>

=end html_DE

=cut

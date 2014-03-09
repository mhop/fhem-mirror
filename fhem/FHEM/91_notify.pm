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
  $hash->{AttrList} = "disable:0,1 disabledForIntervals forwardReturnValue:0,1";
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
  notifyRegexpChanged($hash, $re);

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
  return if(!$dev->{CHANGED}); # Some previous notify deleted the array.
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
      Log3 $ln, 5, "Triggering $ln";
      my (undef, $exec) = split("[ \t]+", $ntfy->{DEF}, 2);

      my %specials= (
                "%NAME" => $n,
                "%TYPE" => $t,
                "%EVENT" => $s
      );
      $exec= EvalSpecials($exec, %specials);

      Log3 $ln, 4, "$ln exec $exec";
      my $r = AnalyzeCommandChain(undef, $exec);
      Log3 $ln, 3, "$ln return value: $r" if($r);
      $ret .= " $r" if($r);
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

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");
  return undef;
}
1;

=pod
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
      <!-- <code>define LogHToDB notify .*H:.* {DbLog("$NAME","$EVENT")}</code><br> -->
      <code>define LogUndef notify global:UNDEFINED.* "send-me-mail.sh "$EVENT""</code><br>
    </ul>
    <br>

    Notes:
    <ul>
      <li><code>&lt;pattern&gt;</code> is either the name of the triggering
         device, or <code>devicename:event</code>.</li>

      <li><code>&lt;pattern&gt;</code> must completely (!)
        match either the device name, or the compound of the device name and the
        event.  To identify the events use "inform" command in telnet or "Event
        Monitor" in FHEMWEB.</li>
      <li>in the command section you can access the event:
      <ul>
        <li>The variable $EVENT will contain the complete event, e.g.
          <code>measured-temp: 21.7 (Celsius)</code></li>
        <li>$EVTPART0,$EVTPART1,$EVTPART2,etc contain the space separated event
          parts (e.g. <code>$EVTPART0="measured-temp:", $EVTPART1="21.7",
          $EVTPART2="(Celsius)"</code>. This data is available as a local
          variable in perl, as environment variable for shell scripts, and will
          be textually replaced for FHEM commands.</li>
        <li>$NAME contains the device triggering the event, e.g.
          <code>myFht</code></li>
       </ul></li>

      <li>Note: the following is deprecated and will be removed in a future
        release. The described replacement is attempted if none of the above
        variables ($NAME/$EVENT/etc) found in the command.
      <ul>
        <li>The character <code>%</code> will be replaced with the received
        event, e.g. with <code>on</code> or <code>off</code> or
        <code>measured-temp: 21.7 (Celsius)</code><br> It is advisable to put
        the <code>%</code> into double quotes, else the shell may get a syntax
        error.</li>

        <li>The character <code>@</code> will be replaced with the device
        name.</li>

        <li>To use % or @ in the text itself, use the double mode (%% or
        @@).</li>

        <li>Instead of <code>%</code> and <code>@</code>, the parameters
        <code>%EVENT</code> (same as <code>%</code>), <code>%NAME</code> (same
        as <code>@</code>) and <code>%TYPE</code> (contains the device type,
        e.g.  <code>FHT</code>) can be used. The space separated event "parts"
        are available as %EVTPART0, %EVTPART1, etc.  A single <code>%</code>
        looses its special meaning if any of these parameters appears in the
        definition.</li>
      </ul></li>

      <li>To use database logging, define a dblog instance and change the
      $dbconn parameter in the file.</li>

      <li>Following special events will be generated for the device "global"
      <ul>
          <li>INITIALIZED after initialization is finished.</li>
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
  <b>Set</b> <ul>N/A</ul><br>

  <a name="notifyget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="notifyattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a name="forwardReturnValue"></a>
    <li>forwardReturnValue<br>
        Forward the return value of the executed command to the caller,
        default is disabled (0).  If enabled (1), then e.g. a set command which
        triggers this notify will also return this value. This can cause e.g
        FHEMWEB to display this value, when clicking "on" or "off", which is
        often not intended.</li>
  </ul>
  <br>

</ul>

=end html
=cut

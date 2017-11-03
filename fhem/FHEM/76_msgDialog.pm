# Id ##########################################################################
# $Id$

# copyright ###################################################################
#
# 76_msgDialog.pm
#
# Copyright by igami
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# FHEM is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with FHEM.  If not, see <http://www.gnu.org/licenses/>.

# packages ####################################################################
package main;
  use strict;
  use warnings;

# variables ###################################################################
my $msgDialog_devspec = "TYPE=(ROOMMATE|GUEST):FILTER=msgContactPush=.+";

# forward declarations ########################################################
sub msgDialog_Initialize($);

sub msgDialog_Define($$);
sub msgDialog_Set($@);
sub msgDialog_Get($@);
sub msgDialog_Notify($$);

sub msgDialog_progress($$$;$);
sub msgDialog_reset($);
sub msgDialog_evalSpecials($$);
sub msgDialog_updateAllowed;

# initialize ##################################################################
sub msgDialog_Initialize($) {
  my ($hash) = @_;
  my $TYPE = "msgDialog";

  $hash->{DefFn}    = "$TYPE\_Define";
  $hash->{SetFn}    = "$TYPE\_Set";
  $hash->{GetFn}    = "$TYPE\_Get";
  $hash->{AttrFn}   = "$TYPE\_Attr";
  $hash->{NotifyFn} = "$TYPE\_Notify";

  $hash->{AttrList} =
    "allowed:multiple-strict,everyone ".
    "disable:0,1 ".
    "disabledForIntervals ".
    "evalSpecials:textField-long ".
    "msgCommand ".
    $readingFnAttributes
  ;
}

# regular Fn ##################################################################
sub msgDialog_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, $DEF) = split(/[\s]+/, $def, 3);
  my $rc = eval{
    require JSON;
    JSON->import();
    1;
  };

  return(
    "Error loading JSON. Maybe this module is not installed? ".
    "\nUnder debian (based) system it can be installed using ".
    "\"apt-get install libjson-perl\""
  ) unless($rc);
  return(
    "No global configuration device defined: ".
    "Please define a msgConfig device first"
  ) unless($modules{msgConfig}{defptr});

  my $msgConfig = $modules{msgConfig}{defptr}{NAME};

  addToDevAttrList($msgConfig, "$TYPE\_evalSpecials:textField-long ");
  addToDevAttrList($msgConfig, "$TYPE\_msgCommand:textField ");

  $DEF = msgDialog_evalSpecials($hash, $DEF);
  $DEF = eval{JSON->new->decode($DEF)};

  if($@){
    Log3($SELF, 2, "$TYPE ($SELF) - DEF is not a valid JSON: $@");
    return("Usage: define <name> $TYPE {JSON}\n\n$@");
  }

  my @TRIGGER;

  foreach (keys(%{$DEF})){
    next if(defined($DEF->{$_}{setOnly}));

    push(@TRIGGER, $_);
  }

  $hash->{TRIGGER} = join(",", @TRIGGER);
  $hash->{NOTIFYDEV} = "TYPE=(ROOMMATE|GUEST)";

  msgDialog_update_msgCommand($hash);
  msgDialog_reset($hash);
  msgDialog_updateAllowed();

  return;
}

sub msgDialog_Set($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return "\"set $TYPE\" needs at least one argument" if(@a < 2);

  my $SELF = shift @a;
	my $argument = shift @a;
  my $value = join(" ", @a) if (@a);
  my %sets = (
    "reset"         => "reset:noArg",
    "say"           => "say:textField",
    "updateAllowed" => "updateAllowed:noArg"
  );

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Set");

  return(
    "Unknown argument $argument, choose one of ".join(" ", values %sets)
  ) unless(exists($sets{$argument}));

  if($argument eq "reset"){
    msgDialog_reset($hash);
  }
  elsif($argument eq "updateAllowed"){
    msgDialog_updateAllowed();
  }

  return if(IsDisabled($SELF));

  if($argument eq "say" && $value){
    my $recipients = join(",", ($value =~ m/@(\S+)\s+/g));
    $recipients = AttrVal($SELF, "allowed", "") unless($recipients);
    my (undef, $say) = ($value =~ m/(^|\s)([^@].+)/g);

    return unless($recipients || $say);

    msgDialog_progress($hash, $recipients, $say, 1);
  }

  return;
}

sub msgDialog_Get($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return "\"get $TYPE\" needs at least one argument" if(@a < 2);

  my $SELF = shift @a;
	my $argument = shift @a;
  my $value = join(" ", @a) if (@a);
  my %gets = (
    "trigger" => "trigger:noArg"
  );

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Get");

  return(
    "Unknown argument $argument, choose one of ".join(" ", values %gets)
  ) unless(exists($gets{$argument}));

  return if(IsDisabled($SELF));

  if($argument eq "trigger"){
    return(join("\n", split(",", InternalVal($SELF, "TRIGGER", undef))));
  }

  return;
}

sub msgDialog_Attr(@) {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Attr");

  if($attribute eq "disable"){
    if($cmd eq "set" and $value == 1){
      readingsSingleUpdate($hash, "state", "Initialized", 1);
    }
    else{
      readingsSingleUpdate($hash, "state", "disabled", 1);
    }
  }
  elsif($attribute eq "msgCommand"){
    if($cmd eq "set"){
      $attr{$SELF}{$attribute} = $value;
    }
    else{
      delete($attr{$SELF}{$attribute});
    }

    msgDialog_update_msgCommand($hash);
  }

  return;
}

sub msgDialog_Notify($$) {
  my ($hash, $dev_hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $device = $dev_hash->{NAME};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Notify");

  return if(IsDisabled($SELF));

  my @events = @{deviceEvents($dev_hash, 1)};

  return unless(
    @events && AttrVal($SELF, "allowed", "") =~ m/(^|,)($device|everyone)(,|$)/
  );

  foreach my $event (@events){
    next unless($event =~ m/(fhemMsgPushReceived|fhemMsgRcvPush): (.+)/);

    Log3($SELF, 4 , "$TYPE ($SELF) triggered by \"$device $event\"");

    msgDialog_progress($hash, $device, $2);
  }

  return;
}

# module Fn ###################################################################
sub msgDialog_evalSpecials($$) {
  my ($hash, $string) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_evalSpecials");

  my $msgConfig = $modules{msgConfig}{defptr}{NAME}
    if($modules{msgConfig}{defptr});
  $string =~ s/\$SELF/$SELF/g;
  my $evalSpecials =
    AttrVal($msgConfig, "$TYPE\_evalSpecials", "").
    " ".
    AttrVal($SELF, "evalSpecials", "")
  ;

  return($string) if($evalSpecials eq " ");

  (undef, $evalSpecials) = parseParams($evalSpecials, "\\s", " ");

  return($string) unless($evalSpecials);

  foreach(keys(%{$evalSpecials})){
    $evalSpecials->{$_} = eval $evalSpecials->{$_}
      if($evalSpecials->{$_} =~ m/^{.*}$/);
  }

  my $specials = join("|", keys(%{$evalSpecials}));
  $string =~ s/%($specials)%/$evalSpecials->{$1}/g;

  return($string);
}

sub msgDialog_progress($$$;$) {
  my ($hash, $recipients, $message, $force) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  $recipients = join(",", devspec2array($msgDialog_devspec))
    if($recipients eq "everyone");

  return unless($recipients);

  Log3(
    $SELF, 5 , "$TYPE ($SELF)"
    . "\n    entering msgDialog_progress"
    . "\n        recipients: $recipients"
    . "\n        message:    $message"
    . "\n        force:      ".($force ? $force : 0)
  );

  my @oldHistory;
  @oldHistory = split("\\|", ReadingsVal($SELF, "$recipients\_history", ""))
    unless($force);
  push(@oldHistory, split("\\|", $message));
  my (@history);
  my $dialog =$hash->{DEF};
  $dialog = msgDialog_evalSpecials($hash, $dialog);
  $dialog =~ s/\$recipient/$recipients/g;
  $dialog = eval{JSON->new->decode($dialog)};

  foreach (@oldHistory){
    $message = $_;

    if(defined($dialog->{$message})){
      $dialog = $dialog->{$message};
      push(@history, $message);
    }
    else{
      foreach (keys(%{$dialog})){
        next unless(
          $dialog->{$_} =~ m/HASH/ &&
          defined($dialog->{$_}{match}) &&
          $message =~ m/^$dialog->{$_}{match}$/
        );

        $dialog = $dialog->{$_};
        push(@history, $_);

        last;
      }
    }
  }

  return if(@history != @oldHistory || !$force && $dialog->{setOnly});

  $dialog = eval{JSON->new->encode($dialog)};
  $dialog =~ s/\$message/$message/g;
  $dialog = eval{JSON->new->decode($dialog)};
  my $history = "";

  foreach (keys(%{$dialog})){
    if($_ !~ m/(setOnly|match|commands|message)/){
      $history = join("|", @history);

      last;
    }
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, $_."_history", $history)
    foreach (split(",", $recipients));
  readingsBulkUpdate($hash, "state", "$recipients: $message");
  readingsEndUpdate($hash, 1);

  if($dialog->{commands}){
    my @commands =
      $dialog->{commands} =~ m/ARRAY/ ?
        @{$dialog->{commands}}
      : $dialog->{commands}
    ;

    foreach (@commands){
      $_ =~ s/;/;;/g;
      my $ret = AnalyzeCommandChain(undef, $_);

      Log3($SELF, 4, "$TYPE ($SELF) - return from command \"$_\": $ret")
        if($ret);
    }
  }

  if($dialog->{message}){
    my @message =
      $dialog->{message} =~ m/ARRAY/ ?
        @{$dialog->{message}}
      : $dialog->{message}
    ;

    foreach (@message){
      if($_ =~ m/^{.*}$/s){
        $_ =~ s/;/;;/g;
        $_ = AnalyzePerlCommand(undef, $_);
      }
    }

    my $message = join("\n", @message);
    my $msgCommand = '"'.InternalVal($SELF, "MSGCOMMAND", "").'"';
    $msgCommand = eval($msgCommand);

    fhem($msgCommand);
  }

  return;
}

sub msgDialog_reset($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_reset");

  delete($hash->{READINGS});

  readingsSingleUpdate($hash, "state", "Initialized", 1)
    unless(IsDisabled($SELF));

  return;
}

sub msgDialog_updateAllowed {
  Log(5, "msgDialog - entering msgDialog_updateAllowed");

  my $allowed = join(",", sort(devspec2array($msgDialog_devspec)));

  $modules{msgDialog}{AttrList} =~
    s/allowed:multiple-strict,\S*/allowed:multiple-strict,everyone,$allowed/;
}

sub msgDialog_update_msgCommand($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $msgConfig = $modules{msgConfig}{defptr}{NAME};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_update_msgCommand");

  $hash->{MSGCOMMAND} =
    AttrVal($SELF, "msgCommand",
      AttrVal($msgConfig, "$TYPE\_msgCommand",
        'msg push \@$recipients $message'
      )
    )
  ;

  return;
}

1;

# commandref ##################################################################
=pod
=item helper
=item summary    dialogs for instant messaging
=item summary_DE Dialoge f&uuml;r Sofortnachrichten

=begin html

<a name="msgDialog"></a>
<h3>msgDialog</h3>
<ul>
  With msgDialog you can define dialogs for instant messages via TelegramBot, Jabber and yowsup (WhatsApp).<br>
  The communication uses the msg command. Therefore, a device of type msgConfig must be defined first.<br>
  For each dialog you can define which person is authorized to do so. Devices of the type ROOMMATE or GUEST with a defined msgContactPush attribute are required for this. Make sure that the reading fhemMsgRcvPush generates an event.<br>
  <br>
  Prerequisites:
  <ul>
    The Perl module "JSON" is required.<br>
    Under Debian (based) system, this can be installed using
    <code>"apt-get install libjson-perl"</code>.
  </ul>
  <br>

  <a name="msgDialogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; msgDialog &lt;JSON&gt;</code><br>
    Because of the complexity, it is easiest to define an empty dialog first.
    <code>define &lt;name&gt; msgDialog {}</code>
    Then edit the DEF in the detail view.
    <PRE>
{
  "&lt;TRIGGER&gt;": {
    "match": "&lt;regex&gt;",
    "setOnly": (true|false),
    "commands": "(fhem command|{perl code})",
    "message": [
      "{perl code}",
      "text"
    ],
    "&lt;NEXT TRIGGER 1&gt;": {
      ...
    },
    "&lt;NEXT TRIGGER 2&gt;": {
      ...
    }
  }
}
    </PRE>
    <li>
      <code>TRIGGER</code><br>
      Can be any text. The device checks whether the incoming message equals it. If so, the dialogue will be continued at this point.
    </li>
    <br>
    <li>
      <code>match</code><br>
      If you do not want to allow only one message, you can specify a regex. The regex must apply to the whole incoming message.
    </li>
    <br>
    <li>
      <code>setOnly</code><br>
      Can be optionally set to true or false. In both cases, the TRIGGER will
      not be returned at "get &lt;name&gt; trigger".<br>
      If setOnly is set to true, the dialog at this point cannot be triggered
      by incoming messages, but only by using "get &lt;name&gt; say
      TRIGGER".<br>
      This can be used to initiate a dialog from FHEM.
    </li>
    <br>
    <li>
      <code>commands</code><br>
      Can contain a single or multiple commands:
      <PRE>
"commands": "single command"

"commands": [
"command 1",
"command 2",
"{perl command}"
]
      </PRE>
    </li>
    <li>
      <code>message</code><br>
      Can contain a single or multiple text that is connected by a line break:
      <PRE>
"message": "text"

"message": [
"text 1",
"text 2",
"{return from perl command}"
]
      </PRE>
    </li>
    For multi-level dialogs, this structure is specified nested.<br>
    <br>
    Variables and placeholders defined under the attribute evalSpecials are
    evaluated.<br>
    Variables:
    <li>
      <code>$SELF</code><br>
      name of the msgDialog
    </li>
    <br>
    <li>
      <code>$message</code><br>
      received message
    </li>
    <br>
    <li>
      <code>$recipient</code><br>
      Name of the dialog partner
    </li>
  </ul>
  <br>

  <a name="msgDialogset"></a>
  <b>Set</b>
  <ul>
    <li>
      <code>reset</code><br>
      Resets the dialog for all users.
    </li>
    <br>
    <li>
      <code>
        say [@&lt;recipient1&gt;[,&lt;recipient2&gt;,...]]
        &lt;TRIGGER&gt;[|&lt;NEXT TRIGGER&gt;|...]
      </code><br>
      The dialog is continued for all specified recipients at the specified
      position.<br>
      If no recipients are specified, the dialog is continued for all
      recipients specified under the allowed attribute.
    </li>
    <br>
    <li>
      <code>updateAllowed</code><br>
      Updates the selection for the allowed attribute.
    </li>
  </ul>
  <br>

  <a name="msgDialogget"></a>
  <b>Get</b>
  <ul>
    <li>
      <code>trigger</code><br>
      Lists all TRIGGERs of the first level where setOnly is not specified.
    </li>
  </ul>
  <br>

  <a name="msgDialogattr"></a>
  <b>Attribute</b>
  <ul>
    <li>
      <code>allowed</code><br>
      List with all RESIDENTS and ROOMMATE that are authorized for this dialog.
    </li>
    <br>
    <li>
      <code>disable 1</code><br>
      Dialog is deactivated.
    </li>
    <br>
    <li>
      <a href="#disabledForIntervals">
        <u><code>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM ...</code></u>
      </a>
    </li>
    <br>
    <li>
      <code>evalSpecials key1=value1 key2=value2 ...</code><br>
      Space Separate list of name=value pairs.<br>
      Value may contain spaces if included in "" or {}.<br>
      Value is evaluated as a perl expression if it is included in {}.<br>
      In the DEF, %Name% strings are replaced by the corresponding value.<br>
      This attribute is available as "msgDialog_evalSpecials" in the msgConfig
      device.<br>
      If the same name was defined in the msgConfig and msgDialog, the value
      from msgDialog is used.
    </li>
    <br>
    <li>
      <code>msgCommand &lt;command&gt;</code><br>
      Command used to send a message.<br>
      The default is
      <code>"msg push \@$recipients $message"</code>.<br>
      This attribute is available as "msgDialog_msgCommand" in the msgConfig device.
    </li>
  </ul>
  <br>

  <a name="msgDialogreadings"></a>
  <b>Reading</b>
  <ul>
    <li>
      <code>$recipient_history</code><br>
      | separated list of TRIGGERS to save the current state of the dialog.<br>
      A readings is created for each dialog partner. When the dialog is
      finished, the reading will be cleared.
    </li>
  </ul>
  <br>

  <a name="msgDialogTelegramBot"></a>
  <b>Notes for use with TelegramBot:</b>
  <ul>
    It may be necessary to set the attribute "utf8specials" to 1 in the
    TelegramBot, for messages with special characters to be sent.<br>
    <br>
    The msg command supports the TelegramBot_MTYPE. The default is message. The
    queryInline value can be used to create an inline keyboard.
  </ul>
  <br>

  <a name="msgDialogJabber"></a>
  <b>Notes for use with Jabber:</b>
  <ul>
    The msg command supports the TelegramBot_MTYPE. The default is empty. The
    value otr can be used to send an OTR message.
  </ul>
  <br>

  <a name="msgDialogyowsub"></a>
  <b>Notes for use with yowsub (WhatsApp):</b>
  <ul>
    No experiences so far.
  </ul>
  <br>

  <a name="msgDialogexamples"></a>
  <b>Examples:</b>
  <ul>
    <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
      <u>
        The following example codes can be imported by "Raw defnition".
      </u>
    </a>
    <br>
    <br>
    All examples are designed for communication via the TelegramBot. When using
    Jabber or yowsup, they may need to be adjusted.<br>
    It is assumed that the msgConfig device contains the evalSpecials "me" with
    a name which is used to call the bot.<br>
    <br>
    <b>Meta dialog for listing all authorized dialogs:</b>
    <ul>
<PRE>
defmod meta_Dialog msgDialog {\
  "%me%": {\
    "match": "\/?(start|%me%)",\
    "commands": "deletereading TYPE=msgDialog $recipient_history",\
    "message": [\
      "{return('(' . join(') (', sort(split('\n', fhem('get TYPE=msgDialog:FILTER=NAME!=$SELF:FILTER=allowed=.*($recipient|everyone).* trigger'))), 'abbrechen') . ') ')}",\
      "Ich kann folgendes f&uuml;r dich tun:"\
    ]\
  },\
  "zur&uuml;ck": {\
    "commands": "set $recipient_history=.+|.+ say @$recipient {(ReadingsVal($DEV, '$recipient_history', '') =~ m/(.+)\\|.+$/;; return $2 ? $2 : $1;;)}"\
  },\
  "abbrechen": {\
    "match": "\/?abbrechen",\
    "commands": "deletereading TYPE=msgDialog $recipient_history",\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Dialog abgebrochen."\
    ]\
  },\
  "beenden": {\
    "match": "\/?beenden",\
    "commands": "deletereading TYPE=msgDialog $recipient_history",\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Dialog beendet."\
    ]\
  }\
}
attr meta_Dialog allowed everyone
</PRE>
    </ul>
    <b>Request of current fuel prices</b>
    <ul>
<PRE>
defmod Tankstelle_Dialog msgDialog {\
  "Tankstelle": {\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Krafstoffpreise der betragen aktuell folgende Werte:",\
      "",\
      "AIVA",\
      "",\
      "[%AIVA%:Diesel] €/l Diesel",\
      "[%AIVA%:Super] €/l Super",\
      "[%AIVA%:E10] €/l E10",\
      "[%AIVA%:Autogas] €/l Autogas"\
    ]\
  }\
}
attr Tankstelle_Dialog evalSpecials AIVA=AIVA_petrolStation
</PRE>
    </ul>
    <b>Programming of the washing machine</b>
    <ul>
<PRE>
defmod Waschmaschine_Dialog msgDialog { "Waschmaschine": {\
    "message": [\
      "{return('(Zeitprogramm stoppen) ') if(ReadingsVal('%controlUnit%', 'controlMode', '') eq 'auto')}",\
      "{return('(programmieren) ') if(ReadingsVal('%actor%', 'state', '') ne 'on')}",\
      "{return('(einschalten) ') if(ReadingsVal('%actor%', 'state', '') ne 'on')}",\
      "(Verlaufsdiagramm) ",\
      "(abbrechen) ",\
      "{return('Waschmaschine: ' . (ReadingsVal('%actor%', 'state', '') eq 'on' ? 'eingeschaltet' : 'ausgeschaltet'))}",\
      "{return('Modus: ' . (ReadingsVal('%controlUnit%', 'controlMode', '') eq 'auto' ? 'Automatik' : 'Manuell (' . ReadingsVal('%controlUnit%', 'time', '') . ')'))}"\
    ],\
    "Zeitprogramm stoppen": {\
      "commands": "set %controlUnit% controlMode manual",\
      "message": [\
        "TelegramBot_MTYPE=queryInline (%me%) ",\
        "Das Zeitprogramm wurde gestoppt."\
      ]\
    },\
    "programmieren": {\
      "message": [\
        "(best&auml;tigen|zur&uuml;ck|abbrechen) ",\
        "( 00:00 | 00:15 | 00:30 | 00:45 ) ",\
        "( 01:00 | 01:15 | 01:30 | 01:45 ) ",\
        "( 02:00 | 02:15 | 02:30 | 02:45 ) ",\
        "( 03:00 | 03:15 | 03:30 | 03:45 ) ",\
        "( 04:00 | 04:15 | 04:30 | 04:45 ) ",\
        "( 05:00 | 05:15 | 05:30 | 05:45 ) ",\
        "( 06:00 | 06:15 | 06:30 | 06:45 ) ",\
        "( 07:00 | 07:15 | 07:30 | 07:45 ) ",\
        "( 08:00 | 08:15 | 08:30 | 08:45 ) ",\
        "( 09:00 | 09:15 | 09:30 | 09:45 ) ",\
        "( 10:00 | 10:15 | 10:30 | 10:45 ) ",\
        "( 11:00 | 11:15 | 11:30 | 11:45 ) ",\
        "( 12:00 | 12:15 | 12:30 | 12:45 ) ",\
        "( 13:00 | 13:15 | 13:30 | 13:45 ) ",\
        "( 14:00 | 14:15 | 14:30 | 14:45 ) ",\
        "( 15:00 | 15:15 | 15:30 | 15:45 ) ",\
        "( 16:00 | 16:15 | 16:30 | 16:45 ) ",\
        "( 17:00 | 17:15 | 17:30 | 17:45 ) ",\
        "( 18:00 | 18:15 | 18:30 | 18:45 ) ",\
        "( 19:00 | 19:15 | 19:30 | 19:45 ) ",\
        "( 20:00 | 20:15 | 20:30 | 20:45 ) ",\
        "( 21:00 | 21:15 | 21:30 | 21:45 ) ",\
        "( 22:00 | 22:15 | 22:30 | 22:45 ) ",\
        "( 23:00 | 23:15 | 23:30 | 23:45 ) ",\
        "Wann soll die W&auml;sche fertig sein?",\
        "Bitte Uhrzeit in HH:MM angeben.",\
        "Aktuell ist [%controlUnit%:time] Uhr eingestellt."\
      ],\
      "Uhrzeit": {\
        "match": " ?([0-1][0-9]|2[0-3]):[0-5][0-9] ?",\
        "commands": [\
          "set %controlUnit% time $message",\
          "set $SELF say @$recipient Waschmaschine|programmieren|best&auml;tigen"\
        ]\
      },\
      "best&auml;tigen": {\
        "commands": "set %controlUnit% controlMode auto",\
        "message": [\
          "TelegramBot_MTYPE=queryInline (%me%) ",\
          "Das Zeitprogramm wurde eingestellt.",\
          "Die W&auml;sche wird voraussichtlich um [%controlUnit%:time] Uhr fertig sein.",\
          "Bitte die Waschmaschine vorbereiten."\
        ]\
      }\
    },\
    "einschalten": {\
      "commands": [\
        "set %controlUnit% controlMode manual",\
        "set %actor% on"\
      ]\
    },\
    "Verlaufsdiagramm": {\
      "commands": "set %TelegramBot% cmdSend {plotAsPng('%plot%')}",\
      "message": "TelegramBot_MTYPE=queryInline (%me%) $message"\
    }\
  },\
  "auto": {\
    "setOnly": true,\
    "commands": [\
      "set %actor% on",\
      "set %controlUnit% controlMode manual"\
    ],\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Wachmaschine wurde automatisch eingeschaltet."\
    ]\
  },\
  "manual": {\
    "setOnly": true,\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Wachmaschine wurde manuell eingeschaltet."\
    ]\
  },\
  "done": {\
    "setOnly": true,\
    "commands": "set %actor% off",\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Wachmaschine ist fertig."\
    ]\
  }\
}
attr Waschmaschine_Dialog evalSpecials actor=HM_2C10D8_Sw\
controlUnit=Waschkeller_washer_controlUnit\
plot=Waschkeller_washer_SVG
</PRE>
    </ul>
  </ul>
</ul>

=end html

=begin html_DE

<a name="msgDialog"></a>
<h3>msgDialog</h3>
<ul>
  Mit msgDialog k&ouml;nnen Dialoge f&uuml;r Sofortnachrichten &uuml;ber
  TelegramBot, Jabber und yowsup (WhatsApp) definiert werden.<br>
  Die Kommunikation erfolgt &uuml;ber den msg Befehl. Daher muss ein Ger&auml;t
  vom Typ msgConfig zuerst definiert werden.<br>
  F&uuml;r jeden Dialog kann festgelegt werden welche Person dazu berechtigt
  ist. Dazu sind Ger&auml;te vom Typ ROOMMATE oder GUEST mit definiertem
  msgContactPush Attribut erforderlich. Es ist darauf zu achten, dass das
  Reading fhemMsgRcvPush ein Event erzeugt.<br>
  <br>
  Vorraussetzungen:
  <ul>
    Das Perl-Modul "JSON" wird ben&ouml;tigt.<br>
    Unter Debian (basierten) System, kann dies mittels
    <code>"apt-get install libjson-perl"</code> installiert werden.
  </ul>
  <br>

  <a name="msgDialogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; msgDialog &lt;JSON&gt;</code><br>
    Aufgrunder komplexit&auml;t ist es am einfachsten erst einen leeren Dialog
    zu definieren.
    <code>define &lt;name&gt; msgDialog {}</code>
    Anschließend die DEF dann in der Detail-Ansicht bearbeiten.
    <PRE>
{
  "&lt;TRIGGER&gt;": {
    "match": "&lt;regex&gt;",
    "setOnly": (true|false),
    "commands": "(fhem command|{perl code})",
    "message": [
      "{perl code}",
      "text"
    ],
    "&lt;NEXT TRIGGER 1&gt;": {
      ...
    },
    "&lt;NEXT TRIGGER 2&gt;": {
      ...
    }
  }
}
    </PRE>
    <li>
      <code>TRIGGER</code><br>
      Kann ein beliebiger Text sein. Es wird gepr&uuml;ft ob die eingehende
      Nachricht damit &uuml;bereinstimmt. Falls ja, wird der Dialog an dieser
      Stelle fortgesetzt.
    </li>
    <br>
    <li>
      <code>match</code><br>
      Wenn nicht nur genau eine Nachricht zugelassen werden soll, kann noch
      eine regex angegeben werden. Die regex muss auf die gesamte eingehnde
      Nachricht zutreffen.
    </li>
    <br>
    <li>
      <code>setOnly</code><br>
      Kann optional auf true oder false gestellt werden. In beiden
      f&auml;llen wird der TRIGGER dann nicht bei "get &lt;name&gt; trigger"
      zur&uuml;ck gegeben.<br>
      Wenn setOnly auf true gestellt wird kann der Dialog an dieser Stelle
      nicht durch eingehnde Nachrichten ausgel&ouml;st werden, sondern nur
      &uuml;ber "get &lt;name&gt; say TRIGGER".<br>
      Dies kann dazu genutzt werden um einen Dialog von FHEM zu aus zu
      initieren.
    </li>
    <br>
    <li>
      <code>commands</code><br>
      Kann einen einzelnen oder mehrere Befehle enthalten:
      <PRE>
"commands": "single command"

"commands": [
"command 1",
"command 2",
"{perl command}"
]
      </PRE>
    </li>
    <li>
      <code>message</code><br>
      Kann einen einzelnen oder mehrere Textte enthalten die mit einen
      Zeilenumbruch verbunden werden:
      <PRE>
"message": "text"

"message": [
"text 1",
"text 2",
"{return from perl command}"
]
      </PRE>
    </li>
    Bei mehrstufigen Dialogen wird diese Struktur ineinander verschachtelt
    angegeben.<br>
    <br>
    Es werden Variablen und unter dem Attribut evalSpecials definierte
    Platzhalter ausgewertet.<br>
    Variablen:
    <li>
      <code>$SELF</code><br>
      Eigenname des msgDialog
    </li>
    <br>
    <li>
      <code>$message</code><br>
      eingegangene Nachricht
    </li>
    <br>
    <li>
      <code>$recipient</code><br>
      Name des Dialogpartners
    </li>
  </ul>
  <br>

  <a name="msgDialogset"></a>
  <b>Set</b>
  <ul>
    <li>
      <code>reset</code><br>
      Setzt den Dialog f&uuml;r alle Benutzer zur&uuml;ck.
    </li>
    <br>
    <li>
      <code>
        say [@&lt;recipient1&gt;[,&lt;recipient2&gt;,...]]
        &lt;TRIGGER&gt;[|&lt;NEXT TRIGGER&gt;|...]
      </code><br>
      Der Dialog wird f&uuml;r alle angegeben Emp&auml;nger an der angegeben
      Stelle fortgef&uuml;hrt.<br>
      Sind keine Empf&auml;nger angegeben wird der Dialog f&uuml;r alle unter
      dem Attribut allowed angegebenen Empf&auml;nger fortgef&uuml;hrt.
    </li>
    <br>
    <li>
      <code>updateAllowed</code><br>
      Aktualisiert die Auswahl f&uuml;r das Attribut allowed.
    </li>
  </ul>
  <br>

  <a name="msgDialogget"></a>
  <b>Get</b>
  <ul>
    <li>
      <code>trigger</code><br>
      Listet alle TRIGGER der ersten Ebene auf bei denen nicht setOnly
      angegeben ist.
    </li>
  </ul>
  <br>

  <a name="msgDialogattr"></a>
  <b>Attribute</b>
  <ul>
    <li>
      <code>allowed</code><br>
      Liste mit allen RESIDENTS und ROOMMATE die f&uuml;r diesen Dialog
      berechtigt sind.
    </li>
    <br>
    <li>
      <code>disable 1</code><br>
      Dialog ist deaktiviert.
    </li>
    <br>
    <li>
      <a href="#disabledForIntervals">
        <u><code>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM ...</code></u>
      </a>
    </li>
    <br>
    <li>
      <code>evalSpecials key1=value1 key2=value2 ...</code><br>
      Leerzeichen getrennte Liste von Name=Wert Paaren.<br>
      Wert kann Leerzeichen enthalten, falls es in "" oder {} eingeschlossen
      ist.<br>
      Wert wird als
      perl-Ausdruck ausgewertet, falls es in {} eingeschlossen ist.<br>
      In der DEF werden %Name% Zeichenketten durch den zugeh&ouml;rigen Wert
      ersetzt.<br>
      Dieses Attribut ist als "msgDialog_evalSpecials" im msgConfig Gerät
      vorhanden.<br>
      Wenn der selbe Name im msgConfig und msgDialog definiert wurde, wird der
      Wert aus msgDialog verwendet.
    </li>
    <br>
    <li>
      <code>msgCommand &lt;command&gt;</code><br>
      Befehl der zum Versenden einer Nachricht verwendet wird.<br>
      Die Vorgabe ist
      <code>"msg push \@$recipients $message"</code><br>
      Dieses Attribut ist als "msgDialog_msgCommand" im msgConfig Gerät
      vorhanden.
    </li>
  </ul>
  <br>

  <a name="msgDialogreadings"></a>
  <b>Reading</b>
  <ul>
    <li>
      <code>$recipient_history</code><br>
      Durch | getrennte Liste von TRIGGERN um den aktuellen Zustand des Dialogs
      zu sichern.<br>
      F&uuml;r jeden Dialogpartner wird ein Readings angelegt. Wenn der Dialog
      beendet ist wird das Reading zur&uuml;ckgesetzt.
    </li>
  </ul>
  <br>

  <a name="msgDialogTelegramBot"></a>
  <b>Hinweise zur Benutzung mit Telegram:</b>
  <ul>
    Es kann notwendig sein, dass im TelegramBot das Attribut "utf8specials" auf
    1 gesetzt wird, damit Nachrichten mit Umlauten gesendert werden.<br>
    <br>
    Bei dem msg Befehl kann der TelegramBot_MTYPE angegeben werden. Die Vorgabe
    ist message. Durch den Wert queryInline lässt sich ein inline Keyboard
    erzeugen.
  </ul>
  <br>

  <a name="msgDialogJabber"></a>
  <b>Hinweise zur Benutzung mit Jabber:</b>
  <ul>
    Bei dem msg Befehl kann der Jabber_MTYPE angegeben werden. Die Vorgabe ist
    leer. Durch den Wert otr lässt sich eine OTR Nachricht versenden.
  </ul>
  <br>

  <a name="msgDialogyowsub"></a>
  <b>Hinweise zur Benutzung mit yowsub (WhatsApp):</b>
  <ul>
    Bisher noch keine Erfahungen.
  </ul>
  <br>

  <a name="msgDialogexamples"></a>
  <b>Beispiele:</b>
  <ul>
    <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
      <u>
        Die folgenden beispiel Codes k&ouml;nnen nur per "Raw defnition"
        importiert werden.
      </u>
    </a>
    <br>
    <br>
    Alle Beispiele sind f&uuml;r die Kommunikation &uuml;ber den TelegramBot
    ausgelegt. Bei der Verwendung von Jabber oder yowsup m&uuml;ssen diese
    gegebenenfalls angepasst werden.<br>
    Es wird davon ausgegangen, dass im msgConfig Ger&auml;t das evalSpecials
    "me" mit einem Namen gepflegt ist, &uuml;ber welchen der Bot angesprochen
    wird.<br>
    <br>
    <b>Meta Dialog zur auflistung aller Berechtigten Dialoge:</b>
    <ul>
<PRE>
defmod meta_Dialog msgDialog {\
  "%me%": {\
    "match": "\/?(start|%me%)",\
    "commands": "deletereading TYPE=msgDialog $recipient_history",\
    "message": [\
      "{return('(' . join(') (', sort(split('\n', fhem('get TYPE=msgDialog:FILTER=NAME!=$SELF:FILTER=allowed=.*($recipient|everyone).* trigger'))), 'abbrechen') . ') ')}",\
      "Ich kann folgendes f&uuml;r dich tun:"\
    ]\
  },\
  "zur&uuml;ck": {\
    "commands": "set $recipient_history=.+|.+ say @$recipient {(ReadingsVal($DEV, '$recipient_history', '') =~ m/(.+)\\|.+$/;; return $2 ? $2 : $1;;)}"\
  },\
  "abbrechen": {\
    "match": "\/?abbrechen",\
    "commands": "deletereading TYPE=msgDialog $recipient_history",\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Dialog abgebrochen."\
    ]\
  },\
  "beenden": {\
    "match": "\/?beenden",\
    "commands": "deletereading TYPE=msgDialog $recipient_history",\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Dialog beendet."\
    ]\
  }\
}
attr meta_Dialog allowed everyone
</PRE>
    </ul>
    <b>Abfrage der aktuellen Krafstoffpreise</b>
    <ul>
<PRE>
defmod Tankstelle_Dialog msgDialog {\
  "Tankstelle": {\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Krafstoffpreise der betragen aktuell folgende Werte:",\
      "",\
      "AIVA",\
      "",\
      "[%AIVA%:Diesel] €/l Diesel",\
      "[%AIVA%:Super] €/l Super",\
      "[%AIVA%:E10] €/l E10",\
      "[%AIVA%:Autogas] €/l Autogas"\
    ]\
  }\
}
attr Tankstelle_Dialog evalSpecials AIVA=AIVA_petrolStation
</PRE>
    </ul>
    <b>Programmierung der Waschmaschine</b>
    <ul>
<PRE>
defmod Waschmaschine_Dialog msgDialog { "Waschmaschine": {\
    "message": [\
      "{return('(Zeitprogramm stoppen) ') if(ReadingsVal('%controlUnit%', 'controlMode', '') eq 'auto')}",\
      "{return('(programmieren) ') if(ReadingsVal('%actor%', 'state', '') ne 'on')}",\
      "{return('(einschalten) ') if(ReadingsVal('%actor%', 'state', '') ne 'on')}",\
      "(Verlaufsdiagramm) ",\
      "(abbrechen) ",\
      "{return('Waschmaschine: ' . (ReadingsVal('%actor%', 'state', '') eq 'on' ? 'eingeschaltet' : 'ausgeschaltet'))}",\
      "{return('Modus: ' . (ReadingsVal('%controlUnit%', 'controlMode', '') eq 'auto' ? 'Automatik' : 'Manuell (' . ReadingsVal('%controlUnit%', 'time', '') . ')'))}"\
    ],\
    "Zeitprogramm stoppen": {\
      "commands": "set %controlUnit% controlMode manual",\
      "message": [\
        "TelegramBot_MTYPE=queryInline (%me%) ",\
        "Das Zeitprogramm wurde gestoppt."\
      ]\
    },\
    "programmieren": {\
      "message": [\
        "(best&auml;tigen|zur&uuml;ck|abbrechen) ",\
        "( 00:00 | 00:15 | 00:30 | 00:45 ) ",\
        "( 01:00 | 01:15 | 01:30 | 01:45 ) ",\
        "( 02:00 | 02:15 | 02:30 | 02:45 ) ",\
        "( 03:00 | 03:15 | 03:30 | 03:45 ) ",\
        "( 04:00 | 04:15 | 04:30 | 04:45 ) ",\
        "( 05:00 | 05:15 | 05:30 | 05:45 ) ",\
        "( 06:00 | 06:15 | 06:30 | 06:45 ) ",\
        "( 07:00 | 07:15 | 07:30 | 07:45 ) ",\
        "( 08:00 | 08:15 | 08:30 | 08:45 ) ",\
        "( 09:00 | 09:15 | 09:30 | 09:45 ) ",\
        "( 10:00 | 10:15 | 10:30 | 10:45 ) ",\
        "( 11:00 | 11:15 | 11:30 | 11:45 ) ",\
        "( 12:00 | 12:15 | 12:30 | 12:45 ) ",\
        "( 13:00 | 13:15 | 13:30 | 13:45 ) ",\
        "( 14:00 | 14:15 | 14:30 | 14:45 ) ",\
        "( 15:00 | 15:15 | 15:30 | 15:45 ) ",\
        "( 16:00 | 16:15 | 16:30 | 16:45 ) ",\
        "( 17:00 | 17:15 | 17:30 | 17:45 ) ",\
        "( 18:00 | 18:15 | 18:30 | 18:45 ) ",\
        "( 19:00 | 19:15 | 19:30 | 19:45 ) ",\
        "( 20:00 | 20:15 | 20:30 | 20:45 ) ",\
        "( 21:00 | 21:15 | 21:30 | 21:45 ) ",\
        "( 22:00 | 22:15 | 22:30 | 22:45 ) ",\
        "( 23:00 | 23:15 | 23:30 | 23:45 ) ",\
        "Wann soll die W&auml;sche fertig sein?",\
        "Bitte Uhrzeit in HH:MM angeben.",\
        "Aktuell ist [%controlUnit%:time] Uhr eingestellt."\
      ],\
      "Uhrzeit": {\
        "match": " ?([0-1][0-9]|2[0-3]):[0-5][0-9] ?",\
        "commands": [\
          "set %controlUnit% time $message",\
          "set $SELF say @$recipient Waschmaschine|programmieren|best&auml;tigen"\
        ]\
      },\
      "best&auml;tigen": {\
        "commands": "set %controlUnit% controlMode auto",\
        "message": [\
          "TelegramBot_MTYPE=queryInline (%me%) ",\
          "Das Zeitprogramm wurde eingestellt.",\
          "Die W&auml;sche wird voraussichtlich um [%controlUnit%:time] Uhr fertig sein.",\
          "Bitte die Waschmaschine vorbereiten."\
        ]\
      }\
    },\
    "einschalten": {\
      "commands": [\
        "set %controlUnit% controlMode manual",\
        "set %actor% on"\
      ]\
    },\
    "Verlaufsdiagramm": {\
      "commands": "set %TelegramBot% cmdSend {plotAsPng('%plot%')}",\
      "message": "TelegramBot_MTYPE=queryInline (%me%) $message"\
    }\
  },\
  "auto": {\
    "setOnly": true,\
    "commands": [\
      "set %actor% on",\
      "set %controlUnit% controlMode manual"\
    ],\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Wachmaschine wurde automatisch eingeschaltet."\
    ]\
  },\
  "manual": {\
    "setOnly": true,\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Wachmaschine wurde manuell eingeschaltet."\
    ]\
  },\
  "done": {\
    "setOnly": true,\
    "commands": "set %actor% off",\
    "message": [\
      "TelegramBot_MTYPE=queryInline (%me%) ",\
      "Die Wachmaschine ist fertig."\
    ]\
  }\
}
attr Waschmaschine_Dialog evalSpecials actor=HM_2C10D8_Sw\
controlUnit=Waschkeller_washer_controlUnit\
plot=Waschkeller_washer_SVG
</PRE>
    </ul>
  </ul>
</ul>

=end html_DE
=cut

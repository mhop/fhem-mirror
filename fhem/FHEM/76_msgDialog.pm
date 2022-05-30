# Id ##########################################################################
# $Id$
#
# copyright ###################################################################
#
# 76_msgDialog.pm
#
# Originally initiated by igami
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
package FHEM::Communication::msgDialog; ##no critic qw(Package)
use strict;
use warnings;
#use Carp qw(carp);
use GPUtils qw(GP_Import);
use JSON (); # qw(decode_json encode_json);
use Encode;
#use HttpUtils;
use utf8;
use Time::HiRes qw(gettimeofday);

sub ::msgDialog_Initialize { goto &Initialize }

# variables ###################################################################
my $msgDialog_devspec = 'TYPE=(ROOMMATE|GUEST):FILTER=msgContactPush=.+';

BEGIN {

  GP_Import( qw(
    addToDevAttrList 
    readingsSingleUpdate
    readingsBeginUpdate
    readingsBulkUpdate
    readingsEndUpdate
    Log3
    defs attr modules L
    init_done
    InternalTimer
    RemoveInternalTimer
    readingFnAttributes
    IsDisabled
    AttrVal
    InternalVal
    ReadingsVal
    devspec2array
    AnalyzeCommandChain
    AnalyzeCommand
    EvalSpecials
    AnalyzePerlCommand
    perlSyntaxCheck
    parseParams
    ResolveDateWildcards
    FileRead
    getAllSets
    setNotifyDev setDisableNotifyFn
    deviceEvents
    trim
  ) )
};

# initialize ##################################################################
sub Initialize {
  my $hash = shift // return;
  $hash->{DefFn}       = \&Define;
  $hash->{SetFn}       = \&Set;
  $hash->{GetFn}       = \&Get;
  $hash->{AttrFn}      = \&Attr;
  $hash->{NotifyFn}    = \&Notify;
  $hash->{AttrList} =
    "allowed:multiple-strict,everyone ".
    "disable:0,1 ".
    "disabledForIntervals ".
    "evalSpecials:textField-long ".
    "msgCommand configFile ".
    $readingFnAttributes
  ;
  return;
}

# regular Fn ##################################################################
sub Define {
  my $hash = shift // return;
  my $def  = shift // return;
  my ($SELF, $TYPE, $DEF) = split m{[\s]+}x, $def, 3;
  if (!eval{
    require JSON;
    JSON->import();
    1;
  } ) { return (
    "Error loading JSON. Maybe this module is not installed? ".
    "\nUnder debian (based) system it can be installed using ".
    "\"apt-get install libjson-perl\""
    )
  }
  return $init_done ? firstInit($hash) : InternalTimer(time+1, \&firstInit, $hash );
}

sub firstInit {
  my $hash = shift // return;
  my $name = $hash->{NAME};

  return(
    "No global configuration device defined: ".
    "Please define a msgConfig device first"
  ) if !$modules{msgConfig}{defptr};

  my $msgConfig = $modules{msgConfig}{defptr}{NAME};

  addToDevAttrList($msgConfig, 'msgDialog_evalSpecials:textField-long', 'msgDialog');
  addToDevAttrList($msgConfig, 'msgDialog_msgCommand:textField', 'msgDialog');

  if (!IsDisabled($name) ) {
      setDisableNotifyFn($hash, 0);
      setNotifyDev($hash,'TYPE=(ROOMMATE|GUEST)');
  }

  my $cfg  = AttrVal($name,'configFile',undef);
  my $content;
  if ($cfg) {
    (my $ret, $content) = _readConfigFromFile($hash, $cfg);
    return $ret if $ret;
    $hash->{DIALOG} = $content;
  } else {
    $content = InternalVal($name, 'DEF', '{}');
    delete $hash->{DIALOG};
  }
  delete $hash->{TRIGGER};


  my $content2 = msgDialog_evalSpecials($hash, $content);
  if ( !eval{ $content2 = JSON->new->decode($content2); 1;} ){ #decode_json will cause problems with utf8
    Log3($hash, 2, "msgDialog ($name) - DEF or configFile is not a valid JSON: $@");
    return("Usage: define <name> msgDialog {JSON}\n\n$@");
  }

  my @TRIGGER;

  for (keys %{$content2}){
    next if ref $content2->{$_} ne 'HASH';
    next if defined $content2->{$_}->{setOnly}; # && $content2->{$_}->{setOnly} eq 'true';

    push @TRIGGER, $_;
  }

  $hash->{TRIGGER} = join q{,}, @TRIGGER;

  msgDialog_update_msgCommand($hash);
  msgDialog_reset($hash);
  msgDialog_updateAllowed();

  return;
}

sub Set {
  my ($hash,$SELF,$argument,@values) = @_;
  my $TYPE = $hash->{TYPE};

  return qq("set $TYPE" needs at least one argument) if !$argument;

  my $value = join q{ }, @values;
  my %sets = (
    reset         => 'reset:noArg',
    say           => 'say:textField',
    updateAllowed => 'updateAllowed:noArg',
    update        => 'update:allowed,configFile'
  );

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Set");

  return 
    "Unknown argument $argument, choose one of ".join q{ }, values %sets
   if !defined $sets{$argument};

  if ( $argument eq 'reset' ){
    return msgDialog_reset($hash);
  }
  if( $argument eq 'update'){
    return msgDialog_updateAllowed() if $values[0] eq 'allowed';
    return firstInit($hash) if $values[0] eq 'configFile';
  }

  if( $argument eq 'updateAllowed'){
    return msgDialog_updateAllowed();
  }

  return if IsDisabled($SELF);

  if ( $argument eq 'say' && $value ){
    my $recipients = join q{,}, ($value =~ m/@(\S+)\s+/g);
    $recipients = AttrVal($SELF, 'allowed', '') if !$recipients;
    my (undef, $say) = ($value =~ m/(^|\s)([^@].+)/g);

    return if !$recipients && !$say;

    msgDialog_progress($hash, $recipients, $say, 1);
  }

  return;
}

sub Get {
  my ($hash,$SELF,$argument,@values) = @_;
  my $TYPE = $hash->{TYPE};

  return "\"get $TYPE\" needs at least one argument" if !$argument;

  my $value = join q{ }, @values;
  my %gets = (
    trigger => 'trigger:noArg'
  );

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Get");

  return "Unknown argument $argument, choose one of ".join q{ }, values %gets
    if !exists $gets{$argument};

  return if IsDisabled($SELF);

  if($argument eq 'trigger'){
    return join "\n", split q{,}, InternalVal($SELF, 'TRIGGER', undef); #we need the soft variant
  }

  return;
}

sub Attr {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my $hash = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Attr");

  if ($attribute eq 'disable'){
    if($cmd eq 'set' and $value == 1){
      setDisableNotifyFn($hash, 1);
      return readingsSingleUpdate($hash, 'state', 'Initialized', 1); #Beta-User: really?!?
    }
    readingsSingleUpdate($hash, 'state', 'disabled', 1);
    return firstInit($hash) if $init_done;
    return;
  }

  if ( $attribute eq 'msgCommand'){
    if($cmd eq 'set'){
      $attr{$SELF}{$attribute} = $value;
    }
    else{
      delete $attr{$SELF}{$attribute};
    }

    return msgDialog_update_msgCommand($hash);
  }

  if ( $attribute eq 'configFile' ) {
    if ($cmd ne 'set') {
        delete $hash->{CONFIGFILE};
        delete $hash->{DIALOG};
        $value = undef;
        delete $attr{$SELF}{$attribute};
    }
    $attr{$SELF}{$attribute} = $value;
    return firstInit($hash);
  }

  return;
}

sub Notify {
  my $hash     = shift // return;
  my $dev_hash = shift // return;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $device = $dev_hash->{NAME};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_Notify");

  return if IsDisabled($SELF);

  my @events = @{deviceEvents($dev_hash, 1)};

  return if !@events || AttrVal($SELF, 'allowed', '') !~ m{\b(?:$device|everyone)(?:\b|\z)}xms;

  for my $event (@events){
    next if $event !~ m{(?:fhemMsgPushReceived|fhemMsgRcvPush):.(.+)}xms;

    Log3($SELF, 4 , "$TYPE ($SELF) triggered by \"$device $event\"");

    msgDialog_progress($hash, $device, $1);
  }

  return;
}

# module Fn ###################################################################
sub msgDialog_evalSpecials {
  my $hash   = shift // return;
  my $string = shift // return;

  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_evalSpecials");

  my $msgConfig;
  $msgConfig = $modules{msgConfig}{defptr}{NAME}
    if $modules{msgConfig}{defptr};
  $string =~ s/\$SELF/$SELF/g;
  my $evalSpecials = AttrVal($msgConfig, 'msgDialog_evalSpecials', '');
    $evalSpecials .= ' ';
    $evalSpecials .= AttrVal($SELF, 'evalSpecials', '');

  return $string if $evalSpecials eq ' ';

  (undef, $evalSpecials) = parseParams($evalSpecials, "\\s", " ");

  return $string if !$evalSpecials;

  for ( keys %{$evalSpecials} ) {
    $evalSpecials->{$_} = AnalyzePerlCommand($hash, $evalSpecials->{$_})
      if($evalSpecials->{$_} =~ m/^{.*}$/);
  }

  my $specials = join q{|}, keys %{$evalSpecials};
  $string =~ s{%($specials)%}{$evalSpecials->{$1}}g;

  return $string;
}

sub msgDialog_progress {
  my $hash       = shift // return;
  my $recipients = shift // return;
  my $message    = shift // return;
  my $force      = shift;

  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  $recipients = join q{,}, devspec2array($msgDialog_devspec)
    if $recipients eq 'everyone';

  return if !$recipients;

  Log3(
    $SELF, 5 , "$TYPE ($SELF)"
    . "\n    entering msgDialog_progress"
    . "\n        recipients: $recipients"
    . "\n        message:    $message"
    . "\n        force:      ".($force ? $force : 0)
  );

  my @oldHistory;
  @oldHistory = split "\\|", ReadingsVal($SELF, "$recipients\_history", "")
    if !$force;
  push @oldHistory, split "\\|", $message;
  my (@history);
  my $dialog = $hash->{DIALOG} // $hash->{DEF} // q{};
  $dialog = msgDialog_evalSpecials($hash, $dialog);
  $dialog =~ s{\$recipient}{$recipients}g;
  if ( !eval{ $dialog = JSON->new->decode($dialog); 1;} ){
    return Log3($SELF, 2, "$TYPE ($SELF) - Error decoding JSON: $@");
  }

  for (@oldHistory){
    $message = $_;

    if ( defined $dialog->{$message} ){
      $dialog = $dialog->{$message};
      push @history, $message;
    }
    else{
      for (keys %{$dialog}){
        next if $dialog->{$_} !~ m{HASH} 
                || !defined($dialog->{$_}{match}) 
                || $message !~ m{\A$dialog->{$_}{match}\z}
        ;

        $dialog = $dialog->{$_};
        push @history, $_;

        last;
      }
    }
  }

  return if @history != @oldHistory || !$force && $dialog->{setOnly};

  #$dialog = eval{JSON->new->encode($dialog)};
  if ( !eval{ $dialog = JSON->new->encode($dialog); 1;} ) {
    return Log3($SELF, 2, "$TYPE ($SELF) - Error encoding JSON: $@");
  }

  $dialog =~ s{\$message}{$message}g;
  if ( !eval{ $dialog = JSON->new->decode($dialog); 1;} ) {
    return Log3($SELF, 2, "$TYPE ($SELF) - Error decoding JSON: $@");
  }
  my $history = '';

  for ( keys %{$dialog} ) {
    if($_ !~ m{(?:setOnly|match|commands|message)}){
      $history = join q{|}, @history;

      last;
    }
  }

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, $_."_history", $history)
    for ( split q{,}, $recipients );
  readingsBulkUpdate($hash, 'state', "$recipients: $message");
  readingsEndUpdate($hash, 1);

  if($dialog->{commands}){
    my @commands =
      $dialog->{commands} =~ m{ARRAY} ?
        @{$dialog->{commands}}
      : $dialog->{commands}
    ;

    for (@commands){
      $_ =~ s{;}{;;}g if $_ =~ m{\A\{.*\}\z}s;
      my $ret = AnalyzeCommandChain($hash, $_);

      Log3($SELF, 4, "$TYPE ($SELF) - return from command \"$_\": $ret")
        if $ret;
    }
  }

  return if !$dialog->{message};

  my @message =
      $dialog->{message} =~ m{ARRAY} ?
        @{$dialog->{message}}
      : $dialog->{message}
  ;

  for (@message){
      if($_ =~  m{\A\{.*\}\z}s){
        $_ =~ s{;}{;;}g;
        $_ = AnalyzePerlCommand($hash, $_);
      }
  }

  $message = join "\n", @message; #we need the soft variant
  my $msgCommand = InternalVal($SELF, 'MSGCOMMAND', '');

  my %specials   = ( 
        "%SELF"       => $SELF,
        "%TYPE"       => $TYPE,
        "%recipients" => $recipients,
        "%message"    => $message
        );
  $msgCommand  = EvalSpecials($msgCommand, %specials);
  $msgCommand =~ s{\\[\@]}{@}x;
  AnalyzeCommandChain($hash, $msgCommand);
  #$msgCommand =~ s{\\[\@]}{@}x;
  #$msgCommand =~ s{(\$\w+)}{$1}eegx;
  #AnalyzeCommand($hash, $msgCommand);
  return;
}

sub msgDialog_reset {
  my $hash = shift // return;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_reset");

  delete $hash->{READINGS};

  readingsSingleUpdate($hash, 'state', 'Initialized', 1)
    if !IsDisabled($SELF);

  return;
}

sub msgDialog_updateAllowed {
  Log3('global',5, 'msgDialog - entering msgDialog_updateAllowed');

  my $allowed = join q{,}, devspec2array($msgDialog_devspec);

  $modules{msgDialog}{AttrList} =~
    s{allowed:multiple-strict,\S*}{allowed:multiple-strict,everyone,$allowed};
  return;
}

sub msgDialog_update_msgCommand {
  my $hash = shift // return;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};
  my $msgConfig = $modules{msgConfig}{defptr}{NAME};

  Log3($SELF, 5, "$TYPE ($SELF) - entering msgDialog_update_msgCommand");

  $hash->{MSGCOMMAND} =
    AttrVal($SELF, 'msgCommand',
      AttrVal($msgConfig, "$TYPE\_msgCommand",
        'msg push \@$recipients $message'
      )
    )
  ;

  return;
}

sub _getDataFile {
    my $hash     = shift // return;
    my $filename = shift;
    my $name = $hash->{NAME};
    $filename = $filename // AttrVal($name,'configFile',undef);
    my @t = localtime gettimeofday();
    $filename = ResolveDateWildcards($filename, @t);
    $hash->{CONFIGFILE} = $filename; # for configDB migration
    return $filename;
}

sub _readConfigFromFile {
    my $hash = shift // return 'no device reference provided!', undef;
    my $cfg  = shift // return 'no filename provided!', undef;

    my $name = $hash->{NAME};
    my $filename = _getDataFile($hash, $cfg);
    Log3($name, 5, "trying to read config from $filename");
    my ($ret, @content) = FileRead($filename);
    if ($ret) {
        Log3($name, 1, "$name failed to read configFile $filename!") ;
        return $ret, undef;
    }
    my @cleaned = grep { $_ !~ m{\A\s*[#]}x } @content;

    return 0, join q{ }, @cleaned;
}

1;

__END__

# commandref ##################################################################
=pod
=encoding utf8

=item helper
=item summary    dialogs for instant messaging
=item summary_DE Dialoge f&uuml;r Sofortnachrichten

=begin html

<a id="msgDialog"></a>
<h3>msgDialog</h3>
<ul>
  With msgDialog you can define dialogs for instant messages via TelegramBot, Jabber and yowsup (WhatsApp).<br>
  The communication uses the msg command. Therefore, a device of type <a href="#msgConfig">msgConfig</a> must be defined first.<br>
  For each dialog you can define which person is authorized to do so. Devices of the type <a href="#ROOMMATE">ROOMMATE</a> or <a href="#GUEST">GUEST</a> with a defined msgContactPush attribute are required for this. Make sure that the reading fhemMsgRcvPush generates an event.<br>
  <br>
  Prerequisites:
  <ul>
    The Perl module "JSON" is required.<br>
    Under Debian (based) system, this can be installed using
    <code>"apt-get install libjson-perl"</code>.
  </ul>
  <br>

  <a id="msgDialog-define"></a>
  <h4>Define</h4>
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
      by incoming messages, but only by using "set &lt;name&gt; say
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

  <a id="msgDialog-set"></a>
  <h4>Set</h4>
  <ul>
    <a id="msgDialog-set-reset"></a>
    <li>
      <code>reset</code><br>
      Resets the dialog for all users.
    </li>
    <br>
    <a id="msgDialog-set-say"></a>
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
    <a id="msgDialog-set-updateAllowed"></a>
    <li>
      <code>updateAllowed</code><br>
      Updates the selection for the allowed attribute.
    </li>
    <a id="msgDialog-set-update"></a>
    <li>
      <code>update &lt;allowed or configFile&gt;</code><br>
      <ul>
        <li>allowed - updates the selection for the allowed attribute.</li>
        <li>configFile - rereads configFile (e.g. after editing).</li>
      </ul>
    </li>
  </ul>
  <br>

  <a id="msgDialog-get"></a>
  <h4>Get</h4>
  <ul>
    <a id="msgDialog-get-trigger"></a>
    <li>
      <code>trigger</code><br>
      Lists all TRIGGERs of the first level where setOnly is not specified.
    </li>
  </ul>
  <br>

  <a id="msgDialog-attr"></a>
  <h4>Attributes</h4>
  <ul>
    <a id="msgDialog-attr-allowed"></a>
    <li>
      <code>allowed</code><br>
      List with all RESIDENTS and ROOMMATE that are authorized for this dialog.
    </li>
    <br>
    <a id="msgDialog-attr-disable"></a>
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
    <a id="msgDialog-attr-evalSpecials" data-pattern=".*evalSpecials"></a>
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
    <a id="msgDialog-attr-msgCommand" data-pattern=".*msgCommand"></a>
    <li>
      <code>msgCommand &lt;command&gt;</code><br>
      Command used to send a message.<br>
      The default is
      <code>"msg push \@$recipients $message"</code>.<br>
      This attribute is available in the msgConfig device.
    </li>
    <li>
      <a id="msgDialog-attr-configFile"></a><b>configFile</b><br>
      <p>Path to a configuration file for the dialogue. This is an alternative way to using DEF.<br>
      The file itself must contain a JSON-encoded dialogue structure - just as described in define.
      <p>Example (placed in the same dir fhem.pl is located):</p>
      <p><code>attr &lt;msgDialogDevice&gt; configFile ./metaDialogue.cfg</code></p>
    </li>
  </ul>
  <br>

  <a id="msgDialog-readings"></a>
  <h4>Readings</h4>
  <ul>
    <li>
      <code>$recipient_history</code><br>
      | separated list of TRIGGERS to save the current state of the dialog.<br>
      A readings is created for each dialog partner. When the dialog is
      finished, the reading will be cleared.
    </li>
  </ul>
  <br>

  <a id="msgDialog-TelegramBot"></a>
  <b>Notes for use with TelegramBot:</b>
  <ul>
    It may be necessary to set the attribute "utf8specials" to 1 in the
    TelegramBot, for messages with special characters to be sent.<br>
    <br>
    The msg command supports the TelegramBot_MTYPE. The default is message. The
    queryInline value can be used to create an inline keyboard.
  </ul>
  <br>

  <a id="msgDialog-Jabber"></a>
  <b>Notes for use with Jabber:</b>
  <ul>
    The msg command supports the TelegramBot_MTYPE. The default is empty. The
    value otr can be used to send an OTR message.
  </ul>
  <br>

  <a id="msgDialog-yowsub"></a>
  <b>Notes for use with yowsub (WhatsApp):</b>
  <ul>
    No experiences so far.
  </ul>
  <br>

  <a id="msgDialog-examples"></a>
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

<a id="msgDialog"></a>
<h3>msgDialog</h3>
<ul>
  Mit msgDialog k&ouml;nnen Dialoge f&uuml;r Sofortnachrichten &uuml;ber
  TelegramBot, Jabber und yowsup (WhatsApp) definiert werden.<br>
  Die Kommunikation erfolgt &uuml;ber den msg Befehl. Daher muss ein Ger&auml;t
  vom Typ <a href="#msgConfig">msgConfig</a> zuerst definiert werden.<br>
  F&uuml;r jeden Dialog kann festgelegt werden welche Person dazu berechtigt
  ist. Dazu sind Ger&auml;te vom Typ <a href="#ROOMMATE">ROOMMATE</a> oder <a href="#GUEST">GUEST</a> mit definiertem
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

  <a id="msgDialog-define"></a>
  <h4>Define</h4>
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
      &uuml;ber "set &lt;name&gt; say TRIGGER".<br>
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

  <a id="msgDialog-set"></a>
  <h4>Set</h4>
  <ul>
    <a id="msgDialog-set-reset"></a>
    <li>
      <code>reset</code><br>
      Setzt den Dialog f&uuml;r alle Benutzer zur&uuml;ck.
    </li>
    <br>
    <a id="msgDialog-set-say"></a>
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
    <a id="msgDialog-set-updateAllowed"></a>
    <li>
      <code>updateAllowed</code><br>
      Aktualisiert die Auswahl f&uuml;r das Attribut allowed.
    </li>
    <a id="msgDialog-set-update"></a>
    <li>
      <code>update &lt;allowed or configFile&gt;</code><br>
      <ul>
        <li>allowed - aktualisiert die Auswahl für das Attribut allowed.</li>
        <li>configFile - liest die configFile neu ein (z.B. nach Änderung).</li>
      </ul>
    </li>
  </ul>
  <br>

  <a id="msgDialog-get"></a>
  <h4>Get</h4>
  <ul>
    <li>
      <code>trigger</code><br>
      Listet alle TRIGGER der ersten Ebene auf bei denen nicht setOnly
      angegeben ist.
    </li>
  </ul>
  <br>

<a id="msgDialog-attr"></a>
  <h4>Attribute</h4>
  <ul>
    <a id="msgDialog-attr-allowed"></a>
      <li>
      <code>allowed</code><br>
      Liste mit allen RESIDENTS und ROOMMATE die f&uuml;r diesen Dialog
      berechtigt sind.
    </li>
    <br>
    <a id="msgDialog-attr-disable"></a>
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
    <a id="msgDialog-attr-evalSpecials" data-pattern=".*evalSpecials"></a>
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
    <a id="msgDialog-attr-msgCommand" data-pattern=".*msgCommand"></a>
    <li>
      <code>msgCommand &lt;command&gt;</code><br>
      Befehl der zum Versenden einer Nachricht verwendet wird.<br>
      Die Vorgabe ist
      <code>"msg push \@$recipients $message"</code><br>
      Dieses Attribut ist als "msgDialog_msgCommand" im msgConfig Gerät
      vorhanden.
    </li>
    <li>
      <a id="msgDialog-attr-configFile"></a><b>configFile</b><br>
      <p>Alternativ zur Eingabe des Dialogs in der DEF kann eine Datei eingelesen werden, die die Konfigurationsinformationen zum Dialog enthält. Anzugeben ist der Pfad zu dieser Datei.<br>
      Die Datei selbst muss den Dialog in einer JSON-Structur beinhalten (Kommentar-Zeilen beginnend mit # sind erlaubt) - ansonsten gilt dasselbe wie in define beschrieben.
      <p>Beispiel (die Datei liegt im Modul-Verzeichnis):</p>
      <p><code>attr &lt;msgDialogDevice&gt; configFile ./FHEM/metaDialogue.cfg</code></p>
    </li>
  </ul>
  <br>

  <a if="msgDialog-readings"></a>
  <h4>Readings</h4>
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

  <a id="msgDialog-TelegramBot"></a>
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

  <a id="msgDialog-Jabber"></a>
  <b>Hinweise zur Benutzung mit Jabber:</b>
  <ul>
    Bei dem msg Befehl kann der Jabber_MTYPE angegeben werden. Die Vorgabe ist
    leer. Durch den Wert otr lässt sich eine OTR Nachricht versenden.
  </ul>
  <br>

  <a id="msgDialog-yowsub"></a>
  <b>Hinweise zur Benutzung mit yowsub (WhatsApp):</b>
  <ul>
    Bisher noch keine Erfahungen.
  </ul>
  <br>

  <a id="msgDialog-examples"></a>
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

# Id ##########################################################################
# $Id$

# copyright ###################################################################
#
# 98_monitoring.pm
#
# Copyright by igami
#
# This file is part of FHEM.
#
# FHEM is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 2 of the License, or (at your option) any later
# version.
#
# FHEM is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# FHEM.  If not, see <http://www.gnu.org/licenses/>.

# packages ####################################################################
package main;
  use strict;
  use warnings;

# forward declarations ########################################################
sub monitoring_Initialize($);

sub monitoring_Define($$);
sub monitoring_Undefine($$);
sub monitoring_Set($@);
sub monitoring_Get($@);
sub archetype_Attr(@);
sub monitoring_Notify($$);

sub monitoring_modify($);
sub monitoring_RemoveInternalTimer($);
sub monitoring_return($$);
sub monitoring_setActive($);

# initialize ##################################################################
sub monitoring_Initialize($) {
  my ($hash) = @_;
  my $TYPE = "monitoring";

  $hash->{DefFn}    = $TYPE."_Define";
  $hash->{UndefFn}  = $TYPE."_Undefine";
  $hash->{SetFn}    = $TYPE."_Set";
  $hash->{GetFn}    = $TYPE."_Get";
  $hash->{AttrFn}   = $TYPE."_Attr";
  $hash->{NotifyFn} = $TYPE."_Notify";

  $hash->{AttrList} =
    "addStateEvent:1,0 ".
    "blacklist:textField-long ".
    "disable:1,0 ".
    "disabledForIntervals ".
    "errorFuncAdd:textField-long ".
    "errorFuncRemove:textField-long ".
    "errorWait ".
    "errorReturn:textField-long ".
    "getDefault:all,error,warning ".
    "setActiveFunc:textField-long ".
    "warningFuncAdd:textField-long ".
    "warningFuncRemove:textField-long ".
    "warningWait ".
    "warningReturn:textField-long ".
    "whitelist:textField-long ".
    $readingFnAttributes
  ;
}

# regular Fn ##################################################################
sub monitoring_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, @re) = split(/[\s]+/, $def, 5);

  return("Usage: define <name> $TYPE <add-event> [<remove-event>]")
    if(int(@re) < 1 || int(@re) > 2);

  monitoring_NOTIFYDEV($hash);
  monitoring_setActive($hash) if($init_done);

  return;
}

sub monitoring_Undefine($$) {
  my ($hash, $arg) = @_;

  monitoring_RemoveInternalTimer($hash);

  return;
}

sub monitoring_Set($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};

  return("\"set $TYPE\" needs at least one argument") if(@a < 2);

  my $SELF     = shift @a;
  my $argument = shift @a;
  my $value    = join(" ", @a) if (@a);
  my %monitoring_sets = (
    "active"        => "active:noArg",
    "clear"         => "clear:all,error,warning",
    "errorAdd"      => "errorAdd:textField",
    "errorRemove"   => "errorRemove:".
                       join(",", ReadingsVal($SELF, "error", "")),
    "inactive"      => "inactive:noArg",
    "warningAdd"    => "warningAdd:textField",
    "warningRemove" => "warningRemove:".
                       join(",", ReadingsVal($SELF, "warning", ""))
  );

  return(
    "Unknown argument $argument, choose one of ".
    join(" ", sort(values %monitoring_sets))
  ) unless(exists($monitoring_sets{$argument}));

  if($argument eq "active"){
    monitoring_setActive($hash);
  }
  elsif($argument eq "inactive"){
    readingsSingleUpdate($hash, "state", $argument, 0);

    Log3($SELF, 3, "$SELF ($TYPE) set $SELF inactive");

    monitoring_RemoveInternalTimer($hash);
  }
  elsif($argument eq "clear"){
    readingsBeginUpdate($hash);

    if($value =~ m/^(warning|all)$/){
      readingsBulkUpdate($hash, "warning", "", 0);
      readingsBulkUpdate($hash, "warningCount", 0, 0);

      foreach my $r (keys %{$hash->{READINGS}}){
        if($r =~ m/(warning)Add_(.+)/){
          RemoveInternalTimer("$SELF|$1|add|$2");

          delete $hash->{READINGS}{$r};
        }
      }
    }
    if($value =~ m/^(error|all)$/){
      readingsBulkUpdate($hash, "error", "", 0);
      readingsBulkUpdate($hash, "errorCount", 0, 0);

      foreach my $r (keys %{$hash->{READINGS}}){
        if($r =~ m/(error)Add_(.+)/){
          RemoveInternalTimer("$SELF|$1|add|$2");

          delete $hash->{READINGS}{$r};
        }
      }
    }

    readingsBulkUpdate($hash, "state", "$argument $value", 0)
      unless(IsDisabled($SELF));
    readingsEndUpdate($hash, 0);

    Log3($SELF, 2, "$TYPE ($SELF) set $SELF $argument $value");
  }
  elsif($argument =~ /^(error|warning)(Add|Remove)$/){
    monitoring_modify("$SELF|$1|".lc($2)."|$value");
  }

  return;
}

sub monitoring_Get($@) {
  my ($hash, @a) = @_;
  my $TYPE = $hash->{TYPE};
  my $SELF = shift @a;

  return if(IsDisabled($SELF));
  return("\"get $TYPE\" needs at least one argument") if(@a < 1);

  my $argument = shift @a;
  my $value = join(" ", @a) if (@a);
  my $default = AttrVal($SELF, "getDefault", "all");
  my %monitoring_gets = (
    "all"     => "all:noArg",
    "default" => "default:noArg",
    "error"   => "error:noArg",
    "warning" => "warning:noArg"
  );
  my @ret;

  return(
    "Unknown argument $argument, choose one of ".
    join(" ", sort(values %monitoring_gets))
  ) unless(exists($monitoring_gets{$argument}));

  if($argument eq "all" || ($argument eq "default" && $default eq "all")){
    push(@ret, monitoring_return($hash, "error"));
    push(@ret, monitoring_return($hash, "warning"));
  }
  elsif($argument eq "default"){
    push(@ret, monitoring_return($hash, $default));
  }
  elsif($argument eq "error"){
    push(@ret, monitoring_return($hash, "error"));
  }
  elsif($argument eq "warning"){
    push(@ret, monitoring_return($hash, "warning"));
  }

  return(join("\n\n", @ret)."\n") if(@ret);
  return;
}

sub monitoring_Attr(@) {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my ($hash) = $defs{$SELF};

  if($attribute =~  "blacklist" && $value){
    my @blacklist;

    push(@blacklist, devspec2array($_)) foreach (split(/[\s]+/, $value));

    my %blacklist = map{$_, 1} @blacklist;

    foreach my $name (sort(keys %blacklist)){
      monitoring_modify("$SELF|warning|remove|$name");
      monitoring_modify("$SELF|error|remove|$name");
    }
  }
  elsif($attribute eq "whitelist"){
    monitoring_NOTIFYDEV($hash);

    if($value){
      my @whitelist;

      push(@whitelist, devspec2array($_)) foreach (split(/[\s]+/, $value));

      foreach my $list ("warning", "error"){
        foreach my $name (split(",", ReadingsVal($SELF, $list, ""))){
          monitoring_modify("$SELF|$list|remove|$name")
            unless(grep(/$name/, @whitelist));
        }
      }
    }
  }
  elsif($attribute eq "disable"){
    if($cmd eq "set" and $value == 1){
      monitoring_setActive($hash);
    }
    else{
      readingsSingleUpdate($hash, "state", "disabled", 0);
      Log3($SELF, 3, "$hash->{TYPE} ($SELF) attr $SELF disabled");
    }
  }

  return;
}

sub monitoring_Notify($$) {
  my ($hash, $dev_hash) = @_;
  my $SELF = $hash->{NAME};
  my $name  = $dev_hash->{NAME};
  my $TYPE = $hash->{TYPE};

  return if(
    !$init_done ||
    IsDisabled($SELF) ||
    IsDisabled($name) ||
    $SELF eq $name # do not process own events
  );

  my $events = deviceEvents($dev_hash, AttrVal($SELF, "addStateEvent", 0));

  return unless($events);

  if($name eq "global" && "INITIALIZED" =~ m/\Q@{$events}\E/){
    monitoring_setActive($hash);

    return;
  }

  my ($addRegex, $removeRegex) = split(/[\s]+/, InternalVal($SELF, "DEF", ""));

  return unless(
    $addRegex =~ m/^$name:/ ||
    $removeRegex && $removeRegex =~ m/^$name:/ ||
    $events
  );

  my @blacklist;

  push(@blacklist, devspec2array($_))
    foreach (split(/[\s]+/, AttrVal($SELF, "blacklist", "")));

  return if(@blacklist && grep(/$name/, @blacklist));

  my @whitelist;

  push(@whitelist, devspec2array($_))
    foreach (split(/[\s]+/, AttrVal($SELF, "whitelist", "")));

  return if(@whitelist && !(grep(/$name/, @whitelist)));

  foreach my $event (@{$events}){
    next unless($event);

    my $addMatch = "$name:$event" =~ m/^$addRegex$/;
    my $removeMatch = $removeRegex ? "$name:$event" =~ m/^$removeRegex$/ : 0;

    next unless(defined($event) && ($addMatch || $removeMatch));

    Log3($SELF, 4 , "$TYPE ($SELF) triggered by \"$name $event\"");

    foreach my $list ("error", "warning"){
      my $listFuncAdd = AttrVal($SELF, $list."FuncAdd", "preset");
      my $listFuncRemove = AttrVal($SELF, $list."FuncRemove", "preset");
      my $listWait = eval(AttrVal($SELF, $list."Wait", 0));
      $listWait = 0 unless(looks_like_number($listWait));

      if($listFuncAdd eq "preset" && $listFuncRemove eq "preset"){
        Log3(
          $SELF, 5, "$TYPE ($SELF) ".
          $list."FuncAdd and $list"."FuncRemove are preset"
        );
        if(!$removeRegex){
          if($listWait == 0){
            Log3(
              $SELF, 2, "$TYPE ($SELF) ".
              "set \"$list"."Wait\" while \"$list".
              "FuncAdd\" and \"$list"."FuncRemove\" are same"
            ) if($list eq "error");

            next;
          }

          Log3($SELF, 5, "$TYPE ($SELF) only addRegex is defined");

          monitoring_modify("$SELF|$list|remove|$name");
          monitoring_modify("$SELF|$list|add|$name|$listWait");

          next;
        }
        else{
          next unless($list eq "error" || AttrVal($SELF, "errorWait", undef));

          Log3(
            $SELF, 5, "$TYPE ($SELF) ".
            "addRegex ($addRegex) and removeRegex ($removeRegex) are defined"
          );

          monitoring_modify("$SELF|$list|remove|$name") if($removeMatch);
          monitoring_modify("$SELF|$list|add|$name|$listWait") if($addMatch);

          next;
        }
      }

      $listFuncAdd = 1 if($listFuncAdd eq "preset" && $addMatch);

      if(!$removeRegex){
        Log3($SELF, 5, "$TYPE ($SELF) only addRegex is defined");

        if($listFuncRemove eq "preset"){
          if($listWait == 0){
            Log3(
              $SELF, 2, "$TYPE ($SELF) ".
              "set \"$list"."Wait\" while \"$list".
              "FuncAdd\" and \"$list"."FuncRemove\" are same"
            ) if($list eq "error");

            next;
          }

          $listFuncRemove = $listFuncAdd;
        }
      }
      else{
        Log3(
          $SELF, 5, "$TYPE ($SELF) ".
          "addRegex ($addRegex) and removeRegex ($removeRegex) are defined"
        );

        $listFuncRemove = 1 if($listFuncRemove eq "preset" && $removeMatch);
      }

      $listFuncAdd = eval($listFuncAdd) if($listFuncAdd =~ /^\{.*\}$/s);
      $listFuncRemove = eval($listFuncRemove)
        if($listFuncRemove =~ /^\{.*\}$/s);

      monitoring_modify("$SELF|$list|remove|$name")
        if($listFuncRemove && $listFuncRemove eq "1");
      monitoring_modify("$SELF|$list|add|$name|$listWait")
        if($listFuncAdd && $listFuncAdd eq "1");

      next;
    }
  }

  return;
}

# module Fn ###################################################################
sub monitoring_modify($) {
  my ($SELF, $list, $operation, $value, $wait) = split("\\|", shift);
  my ($hash) = $defs{$SELF};

  return unless(defined($hash));
  return if(IsDisabled($SELF));

  my $at = eval($wait + gettimeofday()) if($wait);
  my $TYPE = $hash->{TYPE};
  my (@change, %readings);
  %readings = map{$_, 1} split(",", ReadingsVal($SELF, $list, ""));
  my $arg = "$SELF|$list|$operation|$value";
  my $reading = $list."Add_".$value;

  Log3(
    $SELF, 5 , "$TYPE ($SELF)".
    "\n    entering monitoring_modify".
    "\n        reading:   $list".
    "\n        operation: $operation".
    "\n        value:     $value".
    "\n        at:        ".($at ? FmtDateTime($at) : "now")
  );

  if($operation eq "add"){
    return if(
      $readings{$value} ||
      ReadingsVal($SELF, "error", "") =~ m/(?:^|,)$value(?:,|$)/
    );

    if($at){
      return if($hash->{READINGS}{$reading});

      readingsSingleUpdate($hash, $reading, FmtDateTime($at), 0);
      InternalTimer($at, "monitoring_modify", $arg);

      return;
    }
    else{
      monitoring_modify("$SELF|warning|remove|$value") if($list eq "error");
      $readings{$value} = 1;
      delete $hash->{READINGS}{$reading};
    }
  }
  elsif($operation eq "remove"){
    push(@change, 1) if(delete $readings{$value});
    delete $hash->{READINGS}{"$reading"};
  }

  RemoveInternalTimer("$SELF|$list|add|$value");

  return unless(@change || $operation eq "add");

  my $allCount =
    int(keys %readings) +
    ReadingsNum($SELF, ($list eq "warning" ? "error" : "warning")."Count", 0)
  ;

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "state", "$list $operation: $value");
  readingsBulkUpdate($hash, $list, join(",", sort(keys %readings)));
  readingsBulkUpdate($hash, $list."Count", int(keys %readings));
  readingsBulkUpdate($hash, "allCount", $allCount);
  readingsEndUpdate($hash, 1);

  return;
}

sub monitoring_NOTIFYDEV($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $NOTIFYDEV =
    AttrVal($SELF, "whitelist", undef) ||
    join(",", (InternalVal($SELF, "DEF", undef) =~ m/(?:^|\s)([^:\s]+):/g))
  ;
  $NOTIFYDEV =~ s/\s/,/g;

  notifyRegexpChanged($hash, $NOTIFYDEV);
}

sub monitoring_RemoveInternalTimer($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};

  foreach my $reading (sort(keys %{$hash->{READINGS}})){
    RemoveInternalTimer("$SELF|$1|add|$2")
      if($reading =~ m/(error|warning)Add_(.+)/);
  }

  return;
}

sub monitoring_return($$) {
  my ($hash, $list) = @_;
  my $SELF = $hash->{NAME};
  my @errors = split(",", ReadingsVal($SELF, "error", ""));
  my @warnings = split(",", ReadingsVal($SELF, "warning", ""));
  my $value = ReadingsVal($SELF, $list, undef);
  my $ret = AttrVal($SELF, $list."Return", undef);
  $ret = '"$list: $value"' if(!$ret && $value);

  return unless($ret);
  return eval($ret);
}

sub monitoring_setActive($) {
  my ($hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  readingsSingleUpdate($hash, "state", "active", 0);
  Log3($SELF, 3, "$TYPE ($SELF) set $SELF active");

  foreach my $reading (reverse sort(keys %{$hash->{READINGS}})){
    if($reading =~ m/(error|warning)Add_(.+)/){
      my $wait = time_str2num(ReadingsVal($SELF, $reading, ""));

      next unless(looks_like_number($wait));

      $wait -= gettimeofday();

      if($wait > 0){
        Log3($SELF, 4 , "$TYPE ($SELF) restore Timer \"$SELF|$1|add|$2\"");

        monitoring_modify("$SELF|$1|add|$2|$wait");
      }
      else{
        monitoring_modify("$SELF|$1|add|$2");
      }
    }
  }

  AnalyzeCommandChain(undef, AttrVal($SELF, "setActiveFunc", "preset"));

  return;
}

1;

# commandref ##################################################################
=pod
=item helper
=item summary    monitors devices towards events and stores them in two lists
=item summary_DE überwacht Geräte auf Events und speichert diese in zwei Listen

=begin html

<a name="monitoring"></a>
<h3>monitoring</h3>
( en | <a href="commandref_DE.html#monitoring"><u>de</u></a> )
<div>
  <ul>
    Each monitoring has a warning and an error list, which are stored
    as readings. <br>
    When a defined add-event occurs, the device is set to the warning
    list after a predefined time.<br>
    After a further predefined time, the device is deleted from the
    warning list and set to the error list.<br>
    If a defined remove-event occurs, the device is deleted from both
    lists and still running timers are canceled.<br>
    This makes it easy to create group messages and send them
    formatted by two attributes.<br>
    <br>
    The following applications are possible and are described
    <a href="#monitoringexamples"><u>below</u></a>:<br>
    <ul>
      <li>opened windows</li>
      <li>battery warnings</li>
      <li>activity monitor</li>
      <li>
        regular maintenance (for example changing the table water
        filter or cleaning rooms)
      </li>
      <li>
        operating hours dependent maintenance (for example clean the
        Beamer filter)
      </li>
    </ul>
    <br>
    The monitor does not send a message by itself, a notify or DOIF is
    necessary, which responds to the event "&lt;monitoring-name&gt; error
    add: &lt;name&gt;" and then sends the return value of "get
    &lt;monitoring-name&gt; default".
    <br>
    <br>
    <a name="monitoringdefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; monitoring  &lt;add-event&gt; [&lt;remove-event&gt;]
      </code>
      <br>
      The syntax for &lt;add-event&gt; and &lt;remove-event&gt; is the
      same as the pattern for <a href="#notify">notify</a>
      (device-name or device-name:event).<br>
      If only an &lt;add-event&gt; is defined, the device is deleted from
      both lists as it occurs and the timers for warning and error are
      started.<br>
    </ul>
    <br>
    <a name="monitoringset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>active</code><br>
        Two things will happen:<br>
        1. Restores pending timers, or sets the devices immediately to the
        corresponding list if the time is in the past.<br>
        2. Executes the commands specified under the "setActiveFunc" attribute.
      </li>
      <li>
        <code>clear (warning|error|all)</code><br>
        Removes all devices from the specified list and aborts timers for this
        list. With "all", all devices are removed from both lists and all
        running timers are aborted.
      </li>
      <li>
        <code>errorAdd &lt;name&gt;</code><br>
        Add &lt;name&gt; to the error list.
      </li>
      <li>
        <code>errorRemove &lt;name&gt;</code><br>
        Removes &lt;name&gt; from the error list.
      </li>
      <li>
        <code>inactive</code><br>
        Inactivates the current device. Note the slight difference to the
        disable attribute: using set inactive the state is automatically saved
        to the statefile on shutdown, there is no explicit save necesary.
      </li>
      <li>
        <code>warningAdd &lt;name&gt;</code><br>
        Add &lt;name&gt; to the warning list.
      </li>
      <li>
        <code>warningRemove &lt;name&gt;</code><br>
        Removes &lt;name&gt; from the warning list.
      </li>
    </ul>
    <br>
    <a name="monitoringget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>all</code><br>
        Returns the error and warning list, separated by a blank line.<br>
        The formatting can be set with the attributes "errorReturn" and
        "warningReturn".
      </li>
      <li>
        <code>default</code><br>
        The "default" value can be set in the attribute "getDefault" and is
        intended to leave the configuration for the return value in the
        monitoring device. If nothing is specified "all" is used.
      </li>
      <li>
        <code>error</code><br>
        Returns the error list.<br>
        The formatting can be set with the attribute "errorReturn".
      </li>
      <li>
        <code>warning</code><br>
        Returns the warning list.<br>
        The formatting can be set with the attribute "warningReturn".
      </li>
    </ul>
    <br>
    <a name="monitoringreadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>allCount</code><br>
        Displays the amount of devices on the warning and error list..
      </li>
      <li>
        <code>error</code><br>
        Comma-separated list of devices.
      </li>
      <li>
        <code>errorAdd_&lt;name&gt;</code><br>
        Displays the time when the device will be set to the error list.
      </li>
      <li>
        <code>errorCount</code><br>
        Displays the amount of devices on the error list.
      </li>
      <li>
        <code>state</code><br>
        Displays the status (active, inactive, or disabled). In "active" it
        displays which device added to which list or was removed from which
        list.
      </li>
      <li>
        <code>warning</code><br>
        Comma-separated list of devices.
      </li>
      <li>
        <code>warningAdd_&lt;name&gt;</code><br>
        Displays the time when the device will be set to the warning list.
      </li>
      <li>
        <code>warningCount</code><br>
        Displays the amount of devices on the warning list.
      </li>
    </ul>
    <br>
    <a name="monitoringattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <a href="#addStateEvent">
          <u><code>addStateEvent</code></u>
        </a>
      </li>
      <li>
        <code>blacklist</code><br>
        Space-separated list of devspecs which will be ignored.<br>
        If the attribute is set all devices which are specified by the devspecs
        are removed from both lists.
      </li>
      <li>
        <code>disable (1|0)</code><br>
        1: Disables the monitoring.<br>
        0: see "set active"
      </li>
      <li>
        <a href="#disabledForIntervals">
          <u><code>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM ...</code></u>
        </a>
      </li>
      <li>
        <code>errorFuncAdd {&lt;perl code&gt;}</code><br>
        The following variables are available in this function:
        <br>
        <ul>
          <li>
            <code>$name</code><br>
            Name of the event triggering device
          </li>
          <li>
            <code>$event</code><br>
            Includes the complete event, e.g.
            <code>measured-temp: 21.7 (Celsius)</code>
          </li>
          <li>
            <code>$addMatch</code><br>
            Has the value 1 if the add-event is true
          </li>
          <li>
            <code>$removeMatch</code><br>
            Has the value 1 if the remove-event is true
          </li>
          <li>
            <code>$SELF</code><br>
            Name of the monitoring
          </li>
        </ul>
        If the function returns a 1, the device is set to the error list after
        the wait time.<br>
        If the attribute is not set, it will be checked for
        <code>$addMatch</code>.
      </li>
      <li>
        <code>errorFuncRemove {&lt;perl code&gt;}</code><br>
        This function provides the same variables as for "errorFuncAdd".<br>
        If the function returns a 1, the device is removed from the error list
        and still running timers are canceled.<br>
        If the attribute is not set, it will be checked for
        <code>$removeMatch</code> if there is a
        <code>&lt;remove-event&gt;</code> in the DEF, otherwise it will be
        checked for <code>errorFuncAdd</code>.
      </li>
      <li>
        <code>errorWait &lt;perl code&gt;</code><br>
        Wait until the device is set to the error list.
      </li>
      <li>
        <code>errorReturn {&lt;perl code&gt;}</code><br>
        The following variables are available in this attribute:
        <ul>
          <li>
            <code>@errors</code><br>
            Array with all devices on the error list.
          </li>
          <li>
            <code>@warnings</code><br>
            Array with all devices on the warning list.
          </li>
          <li>
            <code>$SELF</code><br>
            Name of the monitoring
          </li>
        </ul>
        With this attribute the output created with "get &lt;name&gt; error"
        can be formatted.
      </li>
      <li>
        <code>getDefault (all|error|warning)</code><br>
        This attribute can be used to specify which list(s) are / are returned
        by "get &lt;name&gt; default". If the attribute is not set, "all" will
        be used.
      </li>
      <li>
        <code>setActiveFunc &lt;Anweisung&gt;</code><br>
        The statement is one of the FHEM command types and is executed when you
        define the monitoring or "set active".<br>
        For a battery message <code>"trigger battery=low battery: low"</code>
        can be useful.
      </li>
      <li>
        <code>warningFuncAdd {&lt;perl code&gt;}</code><br>
        Like errorFuncAdd, just for the warning list.
      </li>
      <li>
        <code>warningFuncRemove {&lt;perl code&gt;}</code><br>
        Like errorFuncRemove, just for the warning list.
      </li>
      <li>
        <code>warningWait &lt;perl code&gt;</code><br>
        Like errorWait, just for the warning list.
      </li>
      <li>
        <code>warningReturn {&lt;perl code&gt;}</code><br>
        Like errorReturn, just for the warning list.
      </li>
      <li>
        <code>whitelist {&lt;perl code&gt;}</code><br>
        Space-separated list of devspecs which are allowed.<br>
        If the attribute is set all devices which are not specified by the
        devspecs are removed from both lists.
      </li>
      <li>
        <a href="#readingFnAttributes">
          <u><code>readingFnAttributes</code></u>
        </a>
      </li>
    </ul>
    <br>
    <a name="monitoringexamples"></a>
    <b>Examples</b>
    <ul>
      <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
        <u>The following sample codes can be imported via "Raw definition".</u>
      </a>
      <br><br>
      <li>
        <b>
          Global, flexible opened windows/doors message
          <a href="https://forum.fhem.de/index.php/topic,36504">
            <u>(similar to those described in the forum)</u>
          </a>
        </b>
        <br>
<pre>defmod Fenster_monitoring monitoring .*:(open|tilted) .*:closed
attr Fenster_monitoring errorReturn {return unless(@errors);;\
 $_ = AttrVal($_, "alias", $_) foreach(@errors);;\
 return("Das Fenster \"$errors[0]\" ist schon l&auml;nger ge&ouml;ffnet.") if(int(@errors) == 1);;\
 @errors = sort {lc($a) cmp lc($b)} @errors;;\
 return(join("\n - ", "Die folgenden ".@errors." Fenster sind schon l&auml;nger ge&ouml;ffnet:", @errors))\
}
attr Fenster_monitoring errorWait {AttrVal($name, "winOpenTimer", 60*10)}
attr Fenster_monitoring warningReturn {return unless(@warnings);;\
 $_ = AttrVal($_, "alias", $_) foreach(@warnings);;\
 return("Das Fenster \"$warnings[0]\" ist seit kurzem ge&ouml;ffnet.") if(int(@warnings) == 1);;\
 @warnings = sort {lc($a) cmp lc($b)} @warnings;;\
 return(join("\n - ", "Die folgenden ".@warnings." Fenster sind seit kurzem ge&ouml;ffnet:", @warnings))\
}</pre>
        As soon as a device triggers an "open" or "tilded" event, the device is
        set to the warning list and a timer is started after which the device
        is moved from the warning to the error list. The waiting time can be
        set for each device via userattr "winOpenTimer". The default value is
        10 minutes.<br>
        As soon as a device triggers a "closed" event, the device is deleted
        from both lists and still running timers are stopped.
      </li>
      <br>
      <li>
        <b>Battery monitoring</b><br>
<pre>defmod Batterie_monitoring monitoring .*:battery:.low .*:battery:.ok
attr Batterie_monitoring errorReturn {return unless(@errors);;\
 $_ = AttrVal($_, "alias", $_) foreach(@errors);;\
 return("Bei dem Ger&auml;t \"$errors[0]\" muss die Batterie gewechselt werden.") if(int(@errors) == 1);;\
 @errors = sort {lc($a) cmp lc($b)} @errors;;\
 return(join("\n - ", "Die folgenden ".@errors." Ger&auml;ten muss die Batterie gewechselt werden:", @errors))\
}
attr Batterie_monitoring errorWait 60*60*24*14
attr Batterie_monitoring warningReturn {return unless(@warnings);;\
 $_ = AttrVal($_, "alias", $_) foreach(@warnings);;\
 return("Bei dem Ger&auml;t \"$warnings[0]\" muss die Batterie demn&auml;chst gewechselt werden.") if(int(@warnings) == 1);;\
 @warnings = sort {lc($a) cmp lc($b)} @warnings;;\
 return(join("\n - ", "Die folgenden ".@warnings." Ger&auml;ten muss die Batterie demn&auml;chst gewechselt werden:", @warnings))\
}</pre>
        As soon as a device triggers a "battery: low" event, the device is set
        to the warning list and a timer is started after which the device is
        moved from the warning to the error list. The waiting time is set to 14
        days.<br>
        As soon as a device triggers a "battery: ok" event, the device is
        deleted from both lists and still running timers are stopped.
      </li>
      <br>
      <li>
        <b>Activity Monitor</b><br>
<pre>defmod Activity_monitoring monitoring .*:.*
attr Activity_monitoring errorReturn {return unless(@errors);;\
 $_ = AttrVal($_, "alias", $_) foreach(@errors);;\
 return("Das Ger&auml;t \"$errors[0]\" hat sich seit mehr als 24 Stunden nicht mehr gemeldet.") if(int(@errors) == 1);;\
 @errors = sort {lc($a) cmp lc($b)} @errors;;\
 return(join("\n - ", "Die folgenden ".@errors." Ger&auml;ten haben sich seit mehr als 24 Stunden nicht mehr gemeldet:", @errors))\
}
attr Activity_monitoring errorWait 60*60*24
attr Activity_monitoring warningReturn {return unless(@warnings);;\
 $_ = AttrVal($_, "alias", $_) foreach(@warnings);;\
 return("Das Ger&auml;t \"$warnings[0]\" hat sich seit mehr als 12 Stunden nicht mehr gemeldet.") if(int(@warnings) == 1);;\
 @warnings = sort {lc($a) cmp lc($b)} @warnings;;\
 return(join("\n - ", "Die folgenden ".@warnings." Ger&auml;ten haben sich seit mehr als 12 Stunden nicht mehr gemeldet:", @warnings))\
}
attr Activity_monitoring warningWait 60*60*12</pre>
        Devices are not monitored until they have triggered at least one event.
        If the device does not trigger another event in 12 hours, it will be
        set to the warning list. If the device does not trigger another event
        within 24 hours, it will be moved from the warning list to the error
        list.<br>
        <br>
        Note: It is recommended to use the whitelist attribute.
      </li>
      <br>
      <li>
        <b>Regular maintenance (for example changing the table water filter)</b>
        <br>
<pre>defmod Wasserfilter_monitoring monitoring Wasserfilter_DashButton:.*:.short
attr Wasserfilter_monitoring errorReturn {return unless(@errors);;\
 return "Der Wasserfilter muss gewechselt werden.";;\
}
attr Wasserfilter_monitoring errorWait 60*60*24*30
attr Wasserfilter_monitoring warningReturn {return unless(@warnings);;\
 return "Der Wasserfilter muss demn&auml;chst gewechselt werden.";;\
}
attr Wasserfilter_monitoring warningWait 60*60*24*25</pre>
        A <a href="#dash_dhcp"><u>DashButton</u></a> is used to tell FHEM that
        the water filter has been changed.<br>
        After 30 days, the DashButton is set to the error list.
      </li>
      <br>
      <li>
        <b>Regular maintenance (for example cleaning rooms)</b>
        <br>
<pre>defmod putzen_DashButton dash_dhcp
attr putzen_DashButton allowed AC:63:BE:2E:19:AF,AC:63:BE:49:23:48,AC:63:BE:49:5E:FD,50:F5:DA:93:2B:EE,AC:63:BE:B2:07:78
attr putzen_DashButton devAlias ac-63-be-2e-19-af:Badezimmer\
ac-63-be-49-23-48:Küche\
ac-63-be-49-5e-fd:Schlafzimmer\
50-f5-da-93-2b-ee:Arbeitszimmer\
ac-63-be-b2-07-78:Wohnzimmer
attr putzen_DashButton event-min-interval .*:5
attr putzen_DashButton port 6767
attr putzen_DashButton userReadings state {return (split(":", @{$hash->{CHANGED}}[0]))[0];;}
attr putzen_DashButton widgetOverride allowed:textField-long devAlias:textField-long

defmod putzen_monitoring monitoring putzen_DashButton:.*:.short
attr putzen_monitoring errorFuncAdd {$event =~ m/^(.+):/;;\
 $name = $1;;\
 return 1;;\
}
attr putzen_monitoring errorReturn {return unless(@errors);;\
 return("Der Raum \"$errors[0]\" muss wieder geputzt werden.") if(int(@errors) == 1);;\
 return(join("\n - ", "Die folgenden Räume müssen wieder geputzt werden:", @errors))\
}
attr putzen_monitoring errorWait 60*60*24*7</pre>
        Several <a href="#dash_dhcp"><u>DashButton</u></a> are used to inform
        FHEM that the rooms have been cleaned.<br>
        After 7 days, the room is set to the error list.<br>
        However, the room name is not the device name but the readings name and
        is changed in the <code>errorFuncAdd</code> attribute.
      </li>
      <br>
      <li>
        <b>
        Operating hours dependent maintenance
        (for example, clean the Beamer filter)
        </b>
        <br>
<pre>defmod BeamerFilter_monitoring monitoring Beamer_HourCounter:pulseTimeOverall BeamerFilter_DashButton:.*:.short
attr BeamerFilter_monitoring userattr errorInterval
attr BeamerFilter_monitoring errorFuncAdd {return 1\
   if(ReadingsVal($name, "pulseTimeOverall", 0) >= \
        ReadingsVal($name, "pulseTimeService", 0)\
      + (AttrVal($SELF, "errorInterval", 0))\
      && $addMatch\
   );;\
 return;;\
}
attr BeamerFilter_monitoring errorFuncRemove {return unless($removeMatch);;\
 $name = "Beamer_HourCounter";;\
 fhem(\
    "setreading $name pulseTimeService "\
   .ReadingsVal($name, "pulseTimeOverall", 0)\
 );;\
 return 1;;\
}
attr BeamerFilter_monitoring errorInterval 60*60*200
attr BeamerFilter_monitoring errorReturn {return unless(@errors);;\
 return "Der Filter vom Beamer muss gereinigt werden.";;\
}
attr BeamerFilter_monitoring warningFuncAdd {return}
attr BeamerFilter_monitoring warningFuncRemove {return}</pre>
        An <a href="#HourCounter"><u>HourCounter</u></a> is used to record the
        operating hours of a beamer and a
        <a href="#dash_dhcp"><u>DashButton</u></a>  to tell FHEM that the filter
        has been cleaned.<br>
        If the filter has not been cleaned for more than 200 hours, the device
        is set to the error list.<br>
        If cleaning is acknowledged with the DashButton, the device is removed
        from the error list and the current operating hours are stored in the
        HourCounter device.
      </li>
    </ul>
  </ul>
</div>

=end html

=begin html_DE

<a name="monitoring"></a>
<h3>monitoring</h3>
( <a href="commandref.html#monitoring"><u>en</u></a> | de )
<div>
  <ul>
    Jedes monitoring verf&uuml;gt &uuml;ber eine warning- und eine error-Liste,
    welche als Readings gespeichert werden.<br>
    Beim auftreten eines definierten add-events wird das Ger&auml;t nach einer
    vorgegeben Zeit auf die warning-Liste gesetzt.<br>
    Nach einer weiteren vorgegeben Zeit wird das Ger&auml;t von der
    warning-Liste gel&ouml;scht und auf die error-Liste gesetzt.<br>
    Beim auftreten eines definierten remove-events wird das Ger&auml;t von
    beiden Listen gel&ouml;scht und noch laufende Timer abgebrochen.<br>
    Hiermit lassen sich auf einfache Weise Sammelmeldungen erstellen und durch
    zwei Attribute formatiert ausgeben.<br>
    <br>
    Folgende Anwendungen sind m&ouml;glich und werden
    <a href="#monitoringexamples"><u>unten</u></a> beschrieben:<br>
    <ul>
      <li>ge&ouml;ffnete Fenster</li>
      <li>Batterie Warnungen</li>
      <li>Activity Monitor</li>
      <li>
        regelm&auml;&szlig;ige Wartungsarbeiten
        (z.B. Tischwasserfilter wechseln oder Räume putzen)
      </li>
      <li>
        Betriebsstunden abh&auml;ngige Wartungsarbeiten
        (z.B. Beamer Filter reinigen)
      </li>
    </ul>
    <br>
    Das monitor sendet selbst keine Benachrichtung, hierf&uuml;r ist ein notify
    oder DOIF notwendig, welches auf das Event "&lt;monitoring-name&gt; error
    add: &lt;name&gt;" reagiert und dann den R&uuml;ckgabewert von
    "get &lt;monitoring-name&gt; default" versendet.
    <br>
    <br>
    <a name="monitoringdefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; mointoring &lt;add-event&gt; [&lt;remove-event&gt;]
      </code>
      <br>
      Die Syntax f&uuml;r &lt;add-event&gt; und &lt;remove-event&gt; ist die
      gleiche wie f&uuml;r das Suchmuster von
      <a href="commandref_DE.html#notify"><u>notify</u></a> (Ger&auml;tename
      oder Ger&auml;tename:Event).<br>
      Ist nur ein &lt;add-event&gt; definiert wird beim auftreten das
      Ger&auml;t von beiden Listen gel&ouml;scht und die Timer f&uuml;r warning
      und error werden gestartet.<br>
    </ul>
    <br>
    <a name="monitoringset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>active</code><br>
        Es passieren zwei Dinge:<br>
        1. Stellt noch ausstehende Timer wieder her, bzw. setzt die Ger&auml;te
        sofort auf die entsprechende Liste, falls der Zeitpunkt in der
        Vergangenheit liegt.<br>
        2. F&uuml;hrt die unter dem Attribut "setActiveFunc" angegeben Befehle
        aus.
      </li>
      <li>
        <code>clear (warning|error|all)</code><br>
        Entfernt alle Ger&auml;te von der angegeben Liste und bricht f&uuml;r
        diese Liste laufende Timer ab. Bei "all" werden alle Ger&auml;te von
        beiden Listen entfernt und alle laufenden Timer abgebrochen.
      </li>
      <li>
        <code>errorAdd &lt;name&gt;</code><br>
        F&uuml;gt &lt;name&gt; zu der error-Liste hinzu.
      </li>
      <li>
        <code>errorRemove &lt;name&gt;</code><br>
        Entfernt &lt;name&gt; von der error-Liste.
      </li>
      <li>
        <code>inactive</code><br>
        Deaktiviert das monitoring. Beachte den leichten semantischen
        Unterschied zum disable Attribut: "set inactive" wird bei einem
        shutdown automatisch in fhem.state gespeichert, es ist kein save
        notwendig.
      </li>
      <li>
        <code>warningAdd &lt;name&gt;</code><br>
        F&uuml;gt &lt;name&gt; zu der warning-Liste hinzu.
      </li>
      <li>
        <code>warningRemove &lt;name&gt;</code><br>
        Entfernt &lt;name&gt; von der warning-Liste.
      </li>
    </ul>
    <br>
    <a name="monitoringget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>all</code><br>
        Gibt, durch eine Leerzeile getrennt, die error- und warning-Liste
        zur&uuml;ck.<br>
        Die Formatierung kann dabei mit den Attributen "errorReturn" und
        "warningReturn" eingestellt werden.
      </li>
      <li>
        <code>default</code><br>
        Der "default" Wert kann in dem Attribut "getDefault" festgelegt werden
        und ist dazu gedacht um die Konfiguration f&uuml;r den
        R&uuml;ckgabewert im monitoring Ger&auml;t zu belassen. Wird nichts
        angegeben wird "all" verwendent.
      </li>
      <li>
        <code>error</code><br>
        Gibt die error-Liste zur&uuml;ck.<br>
        Die Formatierung kann dabei mit dem Attribut "errorReturn" eingestellt
        werden.
      </li>
      <li>
        <code>warning</code><br>
        Gibt die warning-Liste zur&uuml;ck.<br>
        Die Formatierung kann dabei mit dem Attribut "warningReturn"
        eingestellt werden.
      </li>
    </ul>
    <br>
    <a name="monitoringreadings"></a>
    <b>Readings</b><br>
    <ul>
      <li>
        <code>allCount</code><br>
        Zeigt die Anzahl der Geräte in der warning- und error-Liste an.
      </li>
      <li>
        <code>error</code><br>
        Durch Komma getrennte Liste von Ger&auml;ten.
      </li>
      <li>
        <code>errorAdd_&lt;name&gt;</code><br>
        Zeigt den Zeitpunkt an wann das Ger&auml;t auf die error-Liste gesetzt
        wird.
      </li>
      <li>
        <code>errorCount</code><br>
        Zeigt die Anzahl der Geräte in der error-Liste an.
      </li>
      <li>
        <code>state</code><br>
        Zeigt den Status (active, inactive oder disabled) an. Bei "active" wird
        angezeigt welches Gerät zu welcher Liste hinzugefügt bzw. von welcher
        Liste entfernt wurde.
      </li>
      <li>
        <code>warning</code><br>
        Durch Komma getrennte Liste von Ger&auml;ten.
      </li>
      <li>
        <code>warningAdd_&lt;name&gt;</code><br>
        Zeigt den Zeitpunkt an wann das Ger&auml;t auf die warning-Liste
        gesetzt wird.
      </li>
      <li>
        <code>warningCount</code><br>
        Zeigt die Anzahl der Geräte in der warning-Liste an.
      </li>
    </ul>
    <br>
    <a name="monitoringattr"></a>
    <b>Attribute</b>
    <ul>
      <li>
        <a href="#addStateEvent">
          <u><code>addStateEvent</code></u>
        </a>
      </li>
      <li>
        <code>blacklist</code><br>
        Durch Leerzeichen getrennte Liste von devspecs die ignoriert werden.<br>
        Wenn das Attribut gesetzt wird werden alle Geräte die durch die
        devspecs definiert sind von beiden Listen gelöscht.
      </li>
      <li>
        <code>disable (1|0)</code><br>
        1: Deaktiviert das monitoring.<br>
        0: siehe "set active"
      </li>
      <li>
        <a href="#disabledForIntervals">
          <u><code>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM ...</code></u>
        </a>
      </li>
      <li>
        <code>errorFuncAdd {&lt;perl code&gt;}</code><br>
        In dieser Funktion stehen die folgende Variablen zur Verf&uuml;gung:
        <br>
        <ul>
          <li>
            <code>$name</code><br>
            Name des Event ausl&ouml;senden Ger&auml;tes
          </li>
          <li>
            <code>$event</code><br>
            Beinhaltet das komplette Event, z.B.
            <code>measured-temp: 21.7 (Celsius)</code>
          </li>
          <li>
            <code>$addMatch</code><br>
            Hat den Wert 1, falls das add-event zutrifft
          </li>
          <li>
            <code>$removeMatch</code><br>
            Hat den Wert 1, falls das remove-event zutrifft
          </li>
          <li>
            <code>$SELF</code><br>
            Eigenname des monitoring
          </li>
        </ul>
        Gibt die Funktion eine 1 zur&uuml;ck, wird das Ger&auml;t, nach der
        Wartezeit, auf die error-Liste gesetzt.<br>
        Wenn das Attribut nicht gesetzt ist wird auf <code>$addMatch</code>
        gepr&uuml;ft.
      </li>
      <li>
        <code>errorFuncRemove {&lt;perl code&gt;}</code><br>
        In dieser Funktion stehen die selben Variablen wie bei "errorFuncAdd"
        zur Verf&uuml;gung.<br>
        Gibt die Funktion eine 1 zur&uuml;ck, wird das Ger&auml;t von der
        error-Liste entfernt und noch laufende Timer werden abgebrochen.<br>
        Wenn das Attribut nicht gesetzt ist wird bei einer DEF mit
        <code>&lt;remove-event&gt;</code> auf <code>$removeMatch</code>
        gepr&uuml;ft und bei einer DEF ohne <code>&lt;remove-event&gt;</code>
        auf <code>errorFuncAdd</code>.
      </li>
      <li>
        <code>errorWait &lt;perl code&gt;</code><br>
        Wartezeit bis das Ger&auml;t auf die error-Liste gesetzt wird.
      </li>
      <li>
        <code>errorReturn {&lt;perl code&gt;}</code><br>
        In diesem Attribut stehen folgende Variablen zur Verf&uuml;gung:
        <ul>
          <li>
            <code>@errors</code><br>
            Array mit allen Ger&auml;ten auf der error-Liste.
          </li>
          <li>
            <code>@warnings</code><br>
            Array mit allen Ger&auml;ten auf der warning-Liste.
          </li>
          <li>
            <code>$SELF</code><br>
            Eigenname des monitoring
          </li>
        </ul>
        Mit diesem Attribut kann die Ausgabe die mit "get &lt;name&gt; error"
        erzeugt wird angepasst werden.
      </li>
      <li>
        <code>getDefault (all|error|warning)</code><br>
        Mit diesem Attribut kann festgelegt werden welche Liste/n mit "get
        &lt;name&gt; default" zur&uuml;ck gegeben wird/werden. Wenn das
        Attribut nicht gesetzt ist wird "all" verwendet.
      </li>
      <li>
        <code>setActiveFunc &lt;Anweisung&gt;</code><br>
        Die Anweisung ist einer der FHEM
        <a href="#command"><u>Befehlstypen</u></a> und wird beim definieren des
        monitoring oder bei "set active" ausgef&uuml;hrt.<br>
        F&uuml;r eine Batterie Meldung kann <code>"trigger battery=low
        battery:low"</code> sinnvoll sein.
      </li>
      <li>
        <code>warningFuncAdd {&lt;perl code&gt;}</code><br>
        Wie errorFuncAdd, nur f&uuml;r die warning-Liste.
      </li>
      <li>
        <code>warningFuncRemove {&lt;perl code&gt;}</code><br>
        Wie errorFuncRemove, nur f&uuml;r die warning-Liste.
      </li>
      <li>
        <code>warningWait &lt;perl code&gt;</code><br>
        Wie errorWait, nur f&uuml;r die warning-Liste.
      </li>
      <li>
        <code>warningReturn {&lt;perl code&gt;}</code><br>
        Wie errorReturn, nur f&uuml;r die warning-Liste.
      </li>
      <li>
        <code>whitelist {&lt;perl code&gt;}</code><br>
        Durch Leerzeichen getrennte Liste von devspecs die erlaubt sind
        werden.<br>
        Wenn das Attribut gesetzt wird werden alle Geräte die nicht durch die
        devspecs definiert sind von beiden Listen gelöscht.
      </li>
      <li>
        <a href="#readingFnAttributes">
          <u><code>readingFnAttributes</code></u>
        </a>
      </li>
    </ul>
    <br>
    <a name="monitoringexamples"></a>
    <b>Beispiele</b>
    <ul>
      <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
        <u>
          Die folgenden beispiel Codes k&ouml;nnen per "Raw defnition"
          importiert werden.
        </u>
      </a>
      <br><br>
      <li>
        <b>
          Globale, flexible Fenster-/T&uuml;r-Offen-Meldungen
          <a href="https://forum.fhem.de/index.php/topic,36504">
            <u>(&auml;hnlich wie im Forum beschrieben)</u>
          </a>
        </b>
        <br>
<pre>defmod Fenster_monitoring monitoring .*:(open|tilted) .*:closed
attr Fenster_monitoring errorReturn {return unless(@errors);;\
 $_ = AttrVal($_, "alias", $_) foreach(@errors);;\
 return("Das Fenster \"$errors[0]\" ist schon l&auml;nger ge&ouml;ffnet.") if(int(@errors) == 1);;\
 @errors = sort {lc($a) cmp lc($b)} @errors;;\
 return(join("\n - ", "Die folgenden ".@errors." Fenster sind schon l&auml;nger ge&ouml;ffnet:", @errors))\
}
attr Fenster_monitoring errorWait {AttrVal($name, "winOpenTimer", 60*10)}
attr Fenster_monitoring warningReturn {return unless(@warnings);;\
 $_ = AttrVal($_, "alias", $_) foreach(@warnings);;\
 return("Das Fenster \"$warnings[0]\" ist seit kurzem ge&ouml;ffnet.") if(int(@warnings) == 1);;\
 @warnings = sort {lc($a) cmp lc($b)} @warnings;;\
 return(join("\n - ", "Die folgenden ".@warnings." Fenster sind seit kurzem ge&ouml;ffnet:", @warnings))\
}</pre>
        Sobald ein Ger&auml;t ein "open" oder "tilded" Event ausl&ouml;st wird
        das Ger&auml;t auf die warning-Liste gesetzt und es wird ein Timer
        gestartet nach dessen Ablauf das Ger&auml;t von der warning- auf die
        error-Liste verschoben wird. Die Wartezeit kann f&uuml;r jedes
        Ger&auml;t per userattr "winOpenTimer" festgelegt werden. Der
        Vorgabewert sind 10 Minuten.<br>
        Sobald ein Ger&auml;t ein "closed" Event ausl&ouml;st wird das
        Ger&auml;t von beiden Listen gel&ouml;scht und noch laufende Timer
        werden gestoppt.
      </li>
      <br>
      <li>
        <b>Batterie&uuml;berwachung</b><br>
<pre>defmod Batterie_monitoring monitoring .*:battery:.low .*:battery:.ok
attr Batterie_monitoring errorReturn {return unless(@errors);;\
 $_ = AttrVal($_, "alias", $_) foreach(@errors);;\
 return("Bei dem Ger&auml;t \"$errors[0]\" muss die Batterie gewechselt werden.") if(int(@errors) == 1);;\
 @errors = sort {lc($a) cmp lc($b)} @errors;;\
 return(join("\n - ", "Die folgenden ".@errors." Ger&auml;ten muss die Batterie gewechselt werden:", @errors))\
}
attr Batterie_monitoring errorWait 60*60*24*14
attr Batterie_monitoring warningReturn {return unless(@warnings);;\
 $_ = AttrVal($_, "alias", $_) foreach(@warnings);;\
 return("Bei dem Ger&auml;t \"$warnings[0]\" muss die Batterie demn&auml;chst gewechselt werden.") if(int(@warnings) == 1);;\
 @warnings = sort {lc($a) cmp lc($b)} @warnings;;\
 return(join("\n - ", "Die folgenden ".@warnings." Ger&auml;ten muss die Batterie demn&auml;chst gewechselt werden:", @warnings))\
}</pre>
        Sobald ein Ger&auml;t ein "battery: low" Event ausl&ouml;st wird das
        Ger&auml;t auf die warning-Liste gesetzt und es wird ein Timer
        gestartet nach dessen Ablauf das Ger&auml;t von der warning- auf die
        error-Liste verschoben wird. Die Wartezeit ist auf 14 Tage
        eingestellt.<br>
        Sobald ein Ger&auml;t ein "battery: ok" Event ausl&ouml;st wird das
        Ger&auml;t von beiden Listen gel&ouml;scht und noch laufende Timer
        werden gestoppt.
      </li>
      <br>
      <li>
        <b>Activity Monitor</b><br>
<pre>defmod Activity_monitoring monitoring .*:.*
attr Activity_monitoring errorReturn {return unless(@errors);;\
 $_ = AttrVal($_, "alias", $_) foreach(@errors);;\
 return("Das Ger&auml;t \"$errors[0]\" hat sich seit mehr als 24 Stunden nicht mehr gemeldet.") if(int(@errors) == 1);;\
 @errors = sort {lc($a) cmp lc($b)} @errors;;\
 return(join("\n - ", "Die folgenden ".@errors." Ger&auml;ten haben sich seit mehr als 24 Stunden nicht mehr gemeldet:", @errors))\
}
attr Activity_monitoring errorWait 60*60*24
attr Activity_monitoring warningReturn {return unless(@warnings);;\
 $_ = AttrVal($_, "alias", $_) foreach(@warnings);;\
 return("Das Ger&auml;t \"$warnings[0]\" hat sich seit mehr als 12 Stunden nicht mehr gemeldet.") if(int(@warnings) == 1);;\
 @warnings = sort {lc($a) cmp lc($b)} @warnings;;\
 return(join("\n - ", "Die folgenden ".@warnings." Ger&auml;ten haben sich seit mehr als 12 Stunden nicht mehr gemeldet:", @warnings))\
}
attr Activity_monitoring warningWait 60*60*12</pre>
        Ger&auml;te werden erst &uuml;berwacht, wenn sie mindestens ein Event
        ausgel&ouml;st haben. Sollte das Ger&auml;t in 12 Stunden kein weiterer
        Event ausl&ouml;sen, wird es auf die warning-Liste gesetzt. Sollte das
        Ger&auml;t in 24 Stunden kein weiteres Event ausl&ouml;sen, wird es von
        der warning- auf die error-Liste verschoben.<br>
        <br>
        Hinweis: Es ist empfehlenswert das whitelist Attribut zu verwenden.
      </li>
      <br>
      <li>
        <b>
          regelm&auml;&szlig;ige Wartungsarbeiten
          (z.B. Tischwasserfilter wechseln)
        </b>
        <br>
<pre>defmod Wasserfilter_monitoring monitoring Wasserfilter_DashButton:.*:.short
attr Wasserfilter_monitoring errorReturn {return unless(@errors);;\
 return "Der Wasserfilter muss gewechselt werden.";;\
}
attr Wasserfilter_monitoring errorWait 60*60*24*30
attr Wasserfilter_monitoring warningReturn {return unless(@warnings);;\
 return "Der Wasserfilter muss demn&auml;chst gewechselt werden.";;\
}
attr Wasserfilter_monitoring warningWait 60*60*24*25</pre>
        Hierbei wird ein <a href="#dash_dhcp"><u>DashButton</u></a> genutzt um
        FHEM mitzuteilen, dass der Wasserfilter gewechselt wurde.<br>
        Nach 30 Tagen wird der DashButton auf die error-Liste gesetzt.
      </li>
      <br>
      <li>
        <b>
          regelm&auml;&szlig;ige Wartungsarbeiten
          (z.B. Räume putzen)
        </b>
        <br>
<pre>defmod putzen_DashButton dash_dhcp
attr putzen_DashButton allowed AC:63:BE:2E:19:AF,AC:63:BE:49:23:48,AC:63:BE:49:5E:FD,50:F5:DA:93:2B:EE,AC:63:BE:B2:07:78
attr putzen_DashButton devAlias ac-63-be-2e-19-af:Badezimmer\
ac-63-be-49-23-48:Küche\
ac-63-be-49-5e-fd:Schlafzimmer\
50-f5-da-93-2b-ee:Arbeitszimmer\
ac-63-be-b2-07-78:Wohnzimmer
attr putzen_DashButton event-min-interval .*:5
attr putzen_DashButton port 6767
attr putzen_DashButton userReadings state {return (split(":", @{$hash->{CHANGED}}[0]))[0];;}
attr putzen_DashButton widgetOverride allowed:textField-long devAlias:textField-long

defmod putzen_monitoring monitoring putzen_DashButton:.*:.short
attr putzen_monitoring errorFuncAdd {$event =~ m/^(.+):/;;\
 $name = $1;;\
 return 1;;\
}
attr putzen_monitoring errorReturn {return unless(@errors);;\
 return("Der Raum \"$errors[0]\" muss wieder geputzt werden.") if(int(@errors) == 1);;\
 return(join("\n - ", "Die folgenden Räume müssen wieder geputzt werden:", @errors))\
}
attr putzen_monitoring errorWait 60*60*24*7</pre>
        Hierbei werden mehrere <a href="#dash_dhcp"><u>DashButton</u></a>
        genutzt um FHEM mitzuteilen, dass die Räume geputzt wurden.<br>
        Nach 7 Tagen wird der Raum auf die error-Liste gesetzt.<br>
        Der Raum Name ist hierbei jedoch nicht der Geräte-Name, sondern der
        Readings-Name und wird in dem <code>errorFuncAdd</code>-Attribut
        geändert.
      </li>
      <br>
      <li>
        <b>
          Betriebsstunden abh&auml;ngige Wartungsarbeiten
          (z.B. Beamer Filter reinigen)
        </b>
        <br>
<pre>defmod BeamerFilter_monitoring monitoring Beamer_HourCounter:pulseTimeOverall BeamerFilter_DashButton:.*:.short
attr BeamerFilter_monitoring userattr errorInterval
attr BeamerFilter_monitoring errorFuncAdd {return 1\
   if(ReadingsVal($name, "pulseTimeOverall", 0) >= \
        ReadingsVal($name, "pulseTimeService", 0)\
      + (AttrVal($SELF, "errorInterval", 0))\
      && $addMatch\
   );;\
 return;;\
}
attr BeamerFilter_monitoring errorFuncRemove {return unless($removeMatch);;\
 $name = "Beamer_HourCounter";;\
 fhem(\
    "setreading $name pulseTimeService "\
   .ReadingsVal($name, "pulseTimeOverall", 0)\
 );;\
 return 1;;\
}
attr BeamerFilter_monitoring errorInterval 60*60*200
attr BeamerFilter_monitoring errorReturn {return unless(@errors);;\
 return "Der Filter vom Beamer muss gereinigt werden.";;\
}
attr BeamerFilter_monitoring warningFuncAdd {return}
attr BeamerFilter_monitoring warningFuncRemove {return}</pre>
        Hierbei wird ein <a href="#HourCounter"><u>HourCounter</u></a> genutzt
        um die Betriebsstunden eine Beamer zu erfassen und ein
        <a href="#dash_dhcp"><u>DashButton</u></a> um FHEM mitzuteilen, dass der
        Filter gereinigt wurde.<br>
        Wurde der Filter l&auml;nger als 200 Betriebsstunden nicht gereinigt
        wird das Ger&auml;t auf die error-Liste gesetzt.<br>
        Wurde die Reinigung mit dem DashButton quittiert wird das Ger&auml;t
        von der error-Liste entfernt und der aktuelle Betriebsstunden-Stand in
        dem HourCounter Ger&auml;t gespeichert.
      </li>
    </ul>
  </ul>
</div>

=end html_DE
=cut

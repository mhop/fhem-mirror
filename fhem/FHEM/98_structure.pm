# $Id$
##############################################################################
#
#     98_structure.pm
#     Copyright by 
#     e-mail: 
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
package main;

use strict;
use warnings;
#use Data::Dumper;

sub structure_getChangedDevice($);


#####################################
sub
structure_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "structure_Define";
  $hash->{UndefFn}   = "structure_Undef";
  $hash->{NotifyFn}  = "structure_Notify";
  $hash->{SetFn}     = "structure_Set";
  $hash->{AttrFn}    = "structure_Attr";
  $hash->{AttrList}  = "async_delay clientstate_priority ".
                 "clientstate_behavior:relative,relativeKnown,absolute,last ".
                 "disable disabledForIntervals evaluateSetResult:1,0 ".
                 $readingFnAttributes;

  my %ahash = ( Fn=>"CommandAddStruct",
                Hlp=>"<structure> <devspec>,add <devspec> to <structure>" );
  $cmds{addstruct} = \%ahash;

  my %dhash = ( Fn=>"CommandDelStruct",
                Hlp=>"<structure> <devspec>,delete <devspec> from <structure>");
  $cmds{delstruct} = \%dhash;
}

sub structAdd($$);
sub
structAdd($$)
{
  my ($d, $attrList) = @_;
  return if(!$defs{$d});
  $defs{$d}{INstructAdd} = 1;
  foreach my $c (@{$defs{$d}{".memberList"}}) {
    if($defs{$c} && $defs{$c}{INstructAdd}) {
      Log 1, "recursive structure definition"

    } else {
      addToDevAttrList($c, $attrList);
      structAdd($c, $attrList) if($defs{$c} && $defs{$c}{TYPE} eq "structure");
    }
  }
  delete $defs{$d}{INstructAdd} if($defs{$d});
}

sub structure_setDevs($;$);

#############################
sub
structure_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $u = "wrong syntax: define <name> structure <struct-type> [device ...]";
  return $u if(int(@a) < 4);

  my $devname = shift(@a);
  my $modname = shift(@a);
  my $stype   = shift(@a);

  $hash->{ATTR} = $stype;
  $hash->{CHANGEDCNT} = 0;
  $hash->{".asyncQueue"} = [];

  structure_setDevs($hash, $def); # needed by set while init is running
  InternalTimer(1, sub {          # repeat it for devices defined later
    structure_setDevs($hash, $def);
    structure_Attr("set", $devname, $stype, $devname);
  }, undef, 0);

  return undef;
}

sub
structure_setDevs($;$)
{
  my ($hash, $def) = @_;
  $def = "$hash->{NAME} structure $hash->{DEF}" if(!$def);
  my $c = $hash->{".memberHash"};

  my @a = split("[ \t][ \t]*", $def);
  my $devname = shift(@a);
  my $modname = shift(@a);
  my $stype   = shift(@a);

  my (%list, @list);
  my $aList = "$stype ${stype}_map structexclude";
  foreach my $a (@a) {
    foreach my $d (devspec2array($a)) {
      next if(!$defs{$d} || $list{$d});
      $hash->{DEVSPECDEF} = 1 if($a ne $d);
      $list{$d} = 1;
      push(@list, $d);
      next if($c && $c->{$d});
      addToDevAttrList($d, $aList);
      structAdd($d, $aList) if($defs{$d} && $defs{$d}{TYPE} eq "structure");
    }
  }
  $hash->{".memberHash"} = \%list;
  $hash->{".memberList"} = \@list;
  delete $hash->{".cachedHelp"};
}

#############################
sub
structure_Undef($$)
{
  my ($hash, $def) = @_;
  my @a = ( "del", $hash->{NAME}, $hash->{ATTR} );
  structure_Attr(@a);
  return undef;
}

#############################
# returns the really changed Device
#############################

sub
structure_getChangedDevice($) 
{
  my ($dev) = @_;
  my $lastDevice = ReadingsVal($dev, "LastDevice", undef);
  $dev = structure_getChangedDevice($lastDevice)
        if($lastDevice && $defs{$dev}->{TYPE} eq "structure");
  return $dev;
}

#############################
sub
structure_Notify($$)
{
  my ($hash, $dev) = @_;
  my $me = $hash->{NAME};
  my $devmap = $hash->{ATTR}."_map";

  if($dev->{NAME} eq "global") {
    my $max = int(@{$dev->{CHANGED}});
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      $s = "" if(!defined($s));

      if($s =~ m/^RENAMED ([^ ]*) ([^ ]*)$/) {
        my ($old, $new) = ($1, $2);
        if($hash->{".memberHash"}{$old}) {
          $hash->{DEF} =~ s/\b$old\b/$new/;
          structure_setDevs($hash);
        }

      } elsif($s =~ m/^DELETED ([^ ]*)$/) {
        my $n = $1;
        if($hash->{".memberHash"}{$n}) {
          $hash->{DEF} =~ s/\b$n\b//;
          structure_setDevs($hash)
        }

      } elsif($s =~ m/^DEFINED ([^ ]*)$/) {
        structure_setDevs($hash) if($hash->{NAME} ne $1 && $hash->{DEVSPECDEF});

      }
    }
    return;
  }

  return "" if(IsDisabled($me));

  return "" if (! exists $hash->{".memberHash"}->{$dev->{NAME}});

  my $behavior = AttrVal($me, "clientstate_behavior", "absolute");
  my %clientstate;

  my @structPrio = attrSplit($attr{$me}{clientstate_priority})
        if($attr{$me} && $attr{$me}{clientstate_priority});

  return "" if($hash->{INSET} && !AttrVal($me, "evaluateSetResult", 0));
  return "" if(@{$hash->{".asyncQueue"}}); # Do not trigger during async set 

  if($hash->{INNTFY}) {
    Log3 $me, 1, "ERROR: endless loop detected in structure_Notify $me";
    return "";
  }
  $hash->{INNTFY} = 1;

  my %priority;
  my (@priority, @foo); 
  for (my $i=0; $i<@structPrio; $i++) {
      @foo = split(/\|/, $structPrio[$i]);
      for (my $j=0; $j<@foo;$j++) {
        $priority{$foo[$j]} = $i+1;
        $priority[$i+1]=$foo[0];
      }
  }
  
  my $minprio = 99999;
  my $devstate;

  foreach my $d (sort keys %{ $hash->{".memberHash"} }) {
    next if(!$defs{$d});

    if($attr{$d} && $attr{$d}{$devmap}) {
      my @gruppe = attrSplit($attr{$d}{$devmap});
      my @value;
      for (my $i=0; $i<@gruppe; $i++) {
        @value = split(":", $gruppe[$i]);
        if(@value == 1) {                # value[0]:.* -> .*
          $devstate = ReadingsVal($d, $value[0], undef);

        } elsif(@value == 2) {           # state:value[0] -> value[1]
          $devstate = ReadingsVal($d, "state", undef);
          $devstate = $defs{$d}{STATE} if(!defined($devstate));
          if(defined($devstate) && $devstate =~ m/^$value[0]/){
            $devstate = $value[1];
            $i=99999; # RKO: ??
          } else {
            $devstate = undef;
          }

        } elsif(@value == 3) {           # value[0]:value[1] -> value[2]
          $devstate = ReadingsVal($d, $value[0], undef);
          if(defined($devstate) && $devstate =~ m/^$value[1]/){
            $devstate = $value[2];
          } else {
            $devstate = undef;
          }
        }

        if(defined($devstate)) {
          if(!$priority{$devstate} && $behavior eq "relativeKnown") {
            delete($hash->{INNTFY});
            return "";
          }
          $minprio = $priority{$devstate}
                if($priority{$devstate} && $priority{$devstate} < $minprio);
          $clientstate{$devstate} = 1;
        }
      }

    } else {
      $devstate = ReadingsVal($d, "state", undef);
      $devstate = $defs{$d}{STATE} if(!defined($devstate));
      if(defined($devstate)) {
        if(!$priority{$devstate} && $behavior eq "relativeKnown") {
          delete($hash->{INNTFY});
          return "";
        }
        $minprio = $priority{$devstate}
              if($priority{$devstate} && $priority{$devstate} < $minprio);
        $clientstate{$devstate} = 1;
      }
    }

    $hash->{".memberHash"}{$d} = $devstate;
  }

  my $newState = "undefined";
  if($behavior eq "absolute"){
    my @cKeys = keys %clientstate;
    $newState = (@cKeys == 1 ? $cKeys[0] : "undefined");

  } elsif($behavior =~ "^relative" && $minprio < 99999) {
    $newState = $priority[$minprio];

  } elsif($behavior eq "last"){
    my $readingName = AttrVal($dev->{NAME}, $devmap, "state");
    $newState = ReadingsVal($dev->{NAME}, $readingName, undef);
    $newState = "undefined" if(!defined($newState));

  }

  Log3 $me, 5, "Update structure '$me' to $newState" .
              " because device $dev->{NAME} has changed";
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "LastDevice", $dev->{NAME}, 0);
  readingsBulkUpdate($hash, "LastDevice_Abs",
                                structure_getChangedDevice($dev->{NAME}), 0);
  readingsBulkUpdate($hash, "state", $newState);
  readingsEndUpdate($hash, 1);
  $hash->{CHANGEDCNT}++;

  delete($hash->{INNTFY});
  undef;
}

#####################################
sub
CommandAddStruct($)
{
  my ($cl, $param) = @_;
  my @a = split(" ", $param);

  if(int(@a) != 2) {
    return "Usage: addstruct <structure_device> <devspec>";
  }
  my $name = shift(@a);
  my $hash = $defs{$name};

  if(!$hash || $hash->{TYPE} ne "structure") {
    return "$a is not a structure device";
  }

  foreach my $d (devspec2array($a[0])) {
    $hash->{".memberHash"}{$d} = 1;
    $hash->{DEF} .= " $d";
  }

  @a = ( "set", $hash->{NAME}, $hash->{ATTR}, $hash->{NAME} );
  structure_Attr(@a);
  delete $hash->{".cachedHelp"};
  return undef;
}

#####################################
sub
CommandDelStruct($)
{
  my ($cl, $param) = @_;
  my @a = split(" ", $param);

  if(int(@a) != 2) {
    return "Usage: delstruct <structure_device> <devspec>";
  }

  my $name = shift(@a);
  my $hash = $defs{$name};
  if(!$hash || $hash->{TYPE} ne "structure") {
    return "$a is not a structure device";
  }

  foreach my $d (devspec2array($a[0])) {
    delete($hash->{".memberHash"}{$d});
    $hash->{DEF} =~ s/\b$d\b//g;
  }
  $hash->{DEF} =~ s/  / /g;

  @a = ( "del", $hash->{NAME}, $hash->{ATTR} );
  structure_Attr(@a);
  delete $hash->{".cachedHelp"};
  return undef;
}


###################################
sub
structure_Set($@)
{
  my ($hash, @list) = @_;
  my $me = $hash->{NAME};
  my $ret = "";
  my %pars;

  # see Forum # 28623 for .cachedHelp
  return $hash->{".cachedHelp"} if($list[1] eq "?" && $hash->{".cachedHelp"});

  my @devList = @{$hash->{".memberList"}};
  if(@list > 1 && $list[$#list] eq "reverse") {
    pop @list;
    @devList = reverse @devList;
  }

  if($list[1] =~ m/^(save|restore)StructState$/) {
    return "Usage: set $me $list[1] readingName" if(@list != 3);
    return "Bad reading name $list[2]" if(!goodReadingName($list[2]));

    if($1 eq "save") {
      readingsSingleUpdate($hash, $list[2],
                   join(",", map { ReadingsVal($_,"state","on") } @devList), 1);
      return;
    }

    my @sl = split(",", ReadingsVal($me, $list[2], ""));
    for(my $i1=0; $i1<@devList && $i1<@sl; $i1++) {
      AnalyzeCommand($hash->{CL}, "set $devList[$i1] $sl[$i1]");
    }
    return;
  }

  $hash->{INSET} = 1;
  my $startAsyncProcessing;

  my $filter;
  if($list[1] ne "?") {
    my $state = join(" ", @list[1..@list-1]);
    readingsSingleUpdate($hash, "state", $state, 1);

    if($state =~ /^\[(FILTER=.*)]/) {
      delete($hash->{INSET}); # Experimental, Forum #35382
      $filter = $1;
      @list = split(" ", $list[0] ." ". substr($state, length($filter)+2));
    }
  }

  foreach my $d (@devList) {
    next if(!$defs{$d});
    if($defs{$d}{INSET}) {
      Log3 $hash, 1, "ERROR: endless loop detected for $d in $me";
      next;
    }

    if($attr{$d} && $attr{$d}{structexclude}) {
      my $se = $attr{$d}{structexclude};
      next if($me =~ m/$se/);
    }

    my $dl0 = $defs{$d};
    my $is_structure = defined($dl0) && $dl0->{TYPE} eq "structure";
    my $async_delay = AttrVal($me, "async_delay", undef);

    my $cmd;
    if(!$filter) {
      $cmd = "set $d ". join(" ", @list[1..@list-1]);

    } elsif( $is_structure ) {
      $cmd = "set $d [$filter] ". join(" ", @list[1..@list-1]);

    } else {
      $cmd = "set $d:$filter ". join(" ", @list[1..@list-1]);

    }

    if(defined($async_delay) && $list[1] ne "?") {
      $startAsyncProcessing = $async_delay if(!@{$hash->{".asyncQueue"}});
      push @{$hash->{".asyncQueue"}}, $cmd;

    } else {
      my ($ostate,$ocnt) = ($dl0->{STATE}, $dl0->{CHANGEDCNT});
      my $sret = AnalyzeCommand(undef, $cmd);
      if($is_structure && $dl0->{CHANGEDCNT} == $ocnt) { # Forum #70488
        $dl0->{STATE} = $dl0->{READINGS}{state}{VAL} = $ostate;
        structure_Notify($hash, $dl0);
      }

      if($sret) {
        $ret .= "\n" if($ret);
        $ret .= $sret;
      }
      if($list[1] eq "?") {
        $sret =~ s/.*one of //;
        map { $pars{$_} = 1 } split(" ", $sret);
      }
    }
  }
  delete($hash->{INSET});
  Log3 $hash, 5, "SET: $ret" if($ret);

  if(defined($startAsyncProcessing)) {
    InternalTimer(gettimeofday(), "structure_asyncQueue", $hash, 0);
  }

  return $ret if($list[1] ne "?");
  $hash->{".cachedHelp"} = "Unknown argument ?, choose one of " .
                join(" ", sort keys(%pars)).
                     " saveStructState restoreStructState";
  return $hash->{".cachedHelp"};
}

sub
structure_asyncQueue(@) 
{
  my ($hash) = @_;

  my $next_cmd = shift @{$hash->{".asyncQueue"}};
  if(defined $next_cmd) {
    AnalyzeCommand(undef, $next_cmd);
    my $async_delay = AttrVal($hash->{NAME}, "async_delay", 0);
    InternalTimer(gettimeofday()+$async_delay,"structure_asyncQueue",$hash,0);
  }
  return undef;
}

###################################
sub
structure_Attr($@)
{
  my ($type, @list) = @_;
  my %ignore = (
    alias=>1,
    async_delay=>1,
    clientstate_behavior=>1,
    clientstate_priority=>1,
    devStateIcon=>1,
    disable=>1,
    disabledForIntervals=>1,
    group=>1,
    icon=>1,
    room=>1,
    stateFormat=>1,
    webCmd=>1,
    userattr=>1
  );

  return undef if($ignore{$list[1]} || !$init_done);

  my $me = $list[0];
  my $hash = $defs{$me};

  if($hash->{INATTR}) {
    Log3 $me, 1, "ERROR: endless loop detected in structure_Attr for $me";
    return;
  }
  $hash->{INATTR} = 1;

  my $ret = "";
  my @devList = @{$hash->{".memberList"}};
  foreach my $d (@devList) {
    next if(!$defs{$d});
    if($attr{$d} && $attr{$d}{structexclude}) {
      my $se = $attr{$d}{structexclude};
      next if("$me:$list[1]" =~ m/$se/);
    }

    $list[0] = $d;
    my $sret;
    if($type eq "del") {
      $sret .= CommandDeleteAttr(undef, join(" ", @list));
    } else {
      $sret .= CommandAttr(undef, join(" ", @list));
    }
    if($sret) {
      $ret .= "\n" if($ret);
      $ret .= $sret;
    }
  }
  delete($hash->{INATTR});
  Log3 $me, 4, "Stucture attr $type: $ret" if($ret);
  return undef;
}

1;

=pod
=item helper
=item summary    organize/structure multiple devices
=item summary_DE mehrere Ger&auml;te zu einem zusammenfassen
=begin html

<a name="structure"></a>
<h3>structure</h3>
<ul>
  <br>
  <a name="structuredefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; structure &lt;struct_type&gt; &lt;dev1&gt; &lt;dev2&gt; ...</code>
    <br><br>
    The structure device is used to organize/structure devices in order to
    set groups of them at once (e.g. switching everything off in a house).<br>

    The list of attached devices can be modified through the addstruct /
    delstruct commands. Each attached device will get the attribute
    &lt;struct_type&gt;=&lt;name&gt;<br> when it is added to the list, and the
    attribute will be deleted if the device is deleted from the structure.
    <br>
    The structure devices can also be added to a structure, e.g. you can have
    a building consisting of levels which consists of rooms of devices.
    <br>

    Example:<br>
    <ul>
      <li>define kitchen structure room lamp1 lamp2</li>
      <li>addstruct kitchen TYPE=FS20</li>
      <li>delstruct kitchen lamp1</li>
      <li>define house structure building kitchen living</li>
      <li>set house off</li>
    </ul>
    <br>
  </ul>

  <br>
  <a name="structureset"></a>
  <b>Set</b>
  <ul>
    <li>saveStructState &lt;readingName&gt;<br>
      The state reading of all members is stored comma separated in the
      specified readingName.
      </li><br>
    <li>restoreStructState &lt;readingName&gt;<br>
      The state of all members will be restored from readingName by calling
      "set memberName storedStateValue".
      </li><br>
    Every other set command is propagated to the attached devices. Exception:
    if an
    attached device has an attribute structexclude, and the attribute value
    matches (as a regexp) the name of the current structure.<br>
    If the set is of the form <code>set &lt;structure&gt;
    [FILTER=&lt;filter&gt;] &lt;type-specific&gt;</code> then
    :FILTER=&lt;filter&gt; will be appended to the device name in the
    propagated set for the attached devices like this: <code>set
    &lt;devN&gt;:FILTER=&lt;filter&gt; &lt;type-specific&gt;</code><br>
    If the last set parameter is "reverse", then execute the set commands in
    the reverse order.
  </ul>
  <br>

  <a name="structureget"></a>
  <b>Get</b>
  <ul>
    get is not supported through a structure device.
  </ul>
  <br>

  <a name="structureattr"></a>
  <b>Attributes</b>
  <ul>
    <a name="async_delay"></a>
    <li>async_delay<br>
        If this attribute is defined, unfiltered set commands will not be
        executed in the clients immediately. Instead, they are added to a queue
        to be executed later. The set command returns immediately, whereas the
        clients will be set timer-driven, one at a time. The delay between two
        timercalls is given by the value of async_delay (in seconds) and may be
        0 for fastest possible execution.  This way, excessive delays often
        known from large structures, can be broken down in smaller junks.
        </li> 

    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a name="clientstate_behavior"></a>
    <li>clientstate_behavior<br>
        The backward propagated status change from the devices to this structure
        works in two different ways.
        <ul>
        <li>absolute<br>
          The structure status will changed to the common device status of all
          defined devices to this structure if all devices are identical.
          Otherwise the structure status is "undefined".
          </li>
        <li>relative<br>
          See below for clientstate_priority.
          </li>
        <li>relativeKnown<br>
          Like relative, but do not trigger on events not described in
          clientstate_priority. Needed e.g. for HomeMatic devices.
          </li>
        <li>last<br>
          The structure state corresponds to the state of the device last changed.
          </li>
        </ul>
        </li>

    <a name="clientstate_priority"></a>
    <li>clientstate_priority<br>
        If clientstate_behavior is set to relative, then you have to set the
        attribute "clientstate_priority" with all states of the defined devices
        to this structure in descending order. Each group is delemited by
        space or /. Each entry of one group is delimited by "pipe".  The status
        represented by the structure is the first entry of each group.
        Example:<br>
        <ul>
          <li>attr kitchen clientstate_behavior relative</li>
          <li>attr kitchen clientstate_priority An|On|on Aus|Off|off</li>
          <li>attr house clientstate_priority Any_On|An All_Off|Aus</li>
        </ul>
        In this example the status of kitchen is either on or off.  The status
        of house is either Any_on or All_off.
        </li>
    <li>&lt;struct_type&gt;_map<br>
        With this attribute, which has to specified for the structure-
        <b>member</b>, you can redefine the value reported by a specific
        structure-member for the structure value. The attribute has three
        variants:
        <ul>
          <li>readingName<br>
            take the value from readingName instead of state.
            </li>
          <li>oldVal:newVal<br>
            if the state reading matches oldVal, then replace it with newVal
            </li>
          <li>readingName:oldVal:newVal<br>
            if readingName matches oldVal, then replace it with newVal
            </li>
        </ul>
        Example:
        <ul>
          <li>define door OWSWITCH &lt;ROMID&gt</li>
          <li>define lamp1 dummy</li>
          <li>attr lamp1 cmdlist on off</li>
          <li>define kitchen structure struct_kitchen lamp1 door</li>
          <li>attr kitchen clientstate_priority An|on OK|Aus|off</li>
          <li>attr lamp1 struct_kitchen_map on:An off:Aus</li>
          <li>attr door struct_kitchen_map A:open:on A:closed:off</li>
          <li>attr door2 struct_kitchen_map A</li>
        </ul>
        </li>

    <a name="evaluateSetResult"></a>
    <li>evaluateSetResult<br>
      if a set command sets the state of the structure members to something
      different from the set command (like set statusRequest), then you have to
      set this attribute to 1 in order to enable the structure instance to
      compute the new status.
      </li>

    <a name="structexclude"></a>
    <li>structexclude<br>
        exclude the device from set/notify or attribute operations. For the set
        and notify the value of structexclude must match the structure name,
        for the attr/deleteattr commands ist must match the combination of
        structure_name:attribute_name. Examples:<br>
        <ul>
          <code>
          define kitchen structure room lamp1 lamp2<br>
          attr lamp1 structexclude kitchen<br>
          attr lamp1 structexclude kitchen:stateFormat<br>
          </code>
        </ul>
        </li>

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>

  </ul>
  <br>
</ul>

=end html
=begin html_DE

<a name="structure"></a>
<h3>structure</h3>
<ul>
  <br>
  <a name="structuredefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; structure &lt;struct_type&gt; &lt;dev1&gt;
    &lt;dev2&gt; ...</code> <br><br>

    Mit dem Device "Structure" werden Strukturen/Zusammenstellungen von anderen
    Devices erstellt um sie zu Gruppen zusammenzufassen. (Beispiel: im Haus
    alles ausschalten) <br>

    Die Liste der Devices die einer Struktur zugeordnet sind kann duch das
    Kommando <code>addstruct / delstruct</code> im laufenden Betrieb
    ver&auml;ndert werden. Es k&ouml;nnen sowohl einzelne Devices als auch
    Gruppen von Devices (TYPE=FS20) zugef&uuml;gt werden.  Jedes zugef&uuml;gt
    Device erh&auml;lt zwei neue Attribute &lt;struct_type&gt;=&lt;name&gt;
    sowie &lt;struct_type&gt;_map wenn es zu einer Struktur zugef&uuml;gt
    wurde. Diese Attribute werden wieder automatisch entfernt, sobald das
    Device von der Struktur entfernt wird.<br>

    Eine Struktur kann ebenfalls zu einer anderen Struktur zugef&uuml;gt
    werden. Somit k&ouml;nnen z b. kaskadierende Strukturen erstellt werden.
    (Z.b. KG,EG,OG, Haus)

    Beispiel:<br>
    <ul>
      <li>define Kueche structure room lampe1 lampe2</li>
      <li>addstruct Kueche TYPE=FS20</li>
      <li>delstruct Kueche lampe1</li>
      <li>define house structure building kitchen living</li>
      <li>set house off</li>
    </ul>
    <br> 
  </ul>

  <br>
  <a name="structureset"></a>
  <b>Set</b>
  <ul>
    <li>saveStructState &lt;readingName&gt;<br>
      Der Status (genauer: state Reading) aller Mitglieder wird im angegebenen
      Reading Komma separiert gespeichert.
      </li><br>
    <li>restoreStructState &lt;readingName&gt;<br>
      Der Status der Mitglieder wird aus dem angegebenen Reading gelesen, und
      via "set Mitgliedsname StatusWert" gesetzt.
      </li><br>
    Jedes andere set Kommando wird an alle Devices dieser Struktur
    weitergegeben.<br>
    Aussnahme: das Attribut structexclude ist in einem Device definiert und
    dessen Attributwert matched als Regexp zum Namen der aktuellen
    Struktur.<br> Wenn das set Kommando diese Form hat <code>set
    &lt;structure&gt; [FILTER=&lt;filter&gt;] &lt;type-specific&gt;</code> wird
    :FILTER=&lt;filter&gt; bei der Weitergebe der set an jeden Devicenamen wie
    folgt angeh&auml;ngt: <code>set &lt;devN&gt;:FILTER=&lt;filter&gt;
    &lt;type-specific&gt;</code><br>
    Falls der letzte Parameter reverse ist, dann werden die Befehle in der
    umgekehrten Reihenfolge ausgef&uuml;hrt.
  </ul>
  <br>
  <a name="structureget"></a>
  <b>Get</b>
  <ul>
    Get wird im Structur-Device nicht unterst&uuml;tzt.
  </ul>
  <br>

  <a name="structureattr"></a>
  <b>Attribute</b>
  <ul>
    <a name="async_delay"></a>
    <li>async_delay<br>
      Wenn dieses Attribut gesetzt ist, werden ungefilterte set Kommandos nicht
      sofort an die Clients weitergereicht. Stattdessen werden sie einer
      Warteschlange hinzugef&uuml;gt, um sp&auml;ter ausgef&uuml;hrt zu werden.
      Das set Kommando kehrt sofort zur&uuml;ck, die Clients werden danach
      timer-gesteuert einzeln abgearbeitet. Die Zeit zwischen den
      Timer-Aufrufen ist dabei durch den Wert von async_delay (in Sekunden)
      gegeben, ein Wert von 0 entspricht der schnellstm&ouml;glichen Abfolge.
      So k&ouml;nnen besonders lange Verz&ouml;gerungen, die gerade bei
      gro&szlig;en structures vorkommen k&ouml;nnen, in unproblematischere
      H&auml;ppchen zerlegt werden. 

      </li>

    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a name="clientstate_behavior"></a>
    <li>clientstate_behavior<br>
      Der Status einer Struktur h&auml;ngt von den Status der zugef&uuml;gten
      Devices ab.  Dabei wird das propagieren der Status der Devices in zwei
      Gruppen klassifiziert und mittels diesem Attribut definiert:
      <ul>
      <li>absolute<br>
        Die Struktur wird erst dann den Status der zugef&uuml;gten Devices
        annehmen, wenn alle Devices einen identischen Status vorweisen. Bei
        unterschiedlichen Devictypen kann dies per Attribut
        &lt;struct_type&gt;_map pro Device beinflusst werden. Andernfalls hat
        die Struktur den Status "undefined".
        </li>
      <li>relative<br>
        S.u. clientstate_priority.
        </li>
      <li>relativeKnown<br>
        wie relative, reagiert aber nicht auf unbekannte, in
        clientstate_priority nicht beschriebene Ereignisse. Wird f&uuml;r
        HomeMatic Ger&auml;te ben&ouml;tigt.
        </li>
      <li>last<br>
        Die Struktur &uuml;bernimmt den Status des zuletzt ge&auml;nderten
        Ger&auml;tes.
        </li>
      </ul>
      </li>

    <a name="clientstate_priority"></a>
    <li>clientstate_priority<br>
      Wird die Struktur auf ein relatives Verhalten eingestellt, so wird die
      Priorit&auml;t der Devicestatus &uuml;ber das Attribut
      <code>clientstate_priority</code> beinflusst. Die Priorit&auml;ten sind
      in absteigender Reihenfolge anzugeben.  Dabei k&ouml;nnen Gruppen mit
      identischer Priorit&auml;t angegeben werden, um zb.  unterschiedliche
      Devicetypen zusammenfassen zu k&ouml;nnen. Jede Gruppe wird durch
      Leerzeichen oder /, jeder Eintrag pro Gruppe durch Pipe getrennt. Der
      Status der Struktur ist der erste Eintrag in der entsprechenden Gruppe.
      <br>Beispiel:
      <ul>
        <li>attr kueche clientstate_behavior relative</li>
        <li>attr kueche clientstate_priority An|On|on Aus|Off|off</li>
        <li>attr haus clientstate_priority Any_On|An All_Off|Aus</li>
      </ul>
      In diesem Beipiel nimmt die Struktur <code>kueche</code>entweder den
      Status <code>An</code> oder <code>Aus</code> an. Die Struktur
      <code>haus</code> nimmt entweder den Status <code>Any_on</code> oder
      <code>All_off</code> an.  Sobald ein Device der Struktur
      <code>haus</code> den Status <code>An</code> hat nimmt die Struktur den
      Status <code>Any_On</code> an. Um dagegen den Status <code>All_off</code>
      anzunehmen, m&uuml;ssen alle Devices dieser Struktur auf <code>off</code>
      stehen. 
      </li>

    <li>&lt;struct_type&gt;_map<br>
      Mit diesem Attribut, das dem Struktur-<b>Mitglied</b> zugewiesen werden
      muss, koennen die Werte, die die einzelnen Struktur- Mitglieder melden,
      umdefiniert werden, damit man unterschiedliche Geraeteklassen
      zusammenfassen kann. Es existieren drei Varianten:
      <ul>
        <li>readingName<br>
          nehme den Wert von readingName anstatt von state
          </li>
        <li>oldVal:newVal<br>
          falls der Wert der state Reading oldVal (als regex) ist, dann ersetze
          diesen mit newVal.
          </li>
        <li>readingName:oldVal:newVal<br>
          falls der Wert der readingName oldVal (als regex) ist, dann ersetze
          diesen mit newVal.
          </li>
      </ul>
      Beispiel:<br>
      <ul>
        <li>define tuer OWSWITCH &lt;ROMID&gt</li>
        <li>define lampe1 dummy</li>
        <li>attr lampe1 cmdlist on off</li>
        <li>define kueche structure struct_kitchen lamp1 door</li>
        <li>attr kueche clientstate_priority An|on OK|Aus|off</li>
        <li>attr lampe1 struct_kitchen_map on:An off:Aus</li>
        <li>attr tuer struct_kitchen_map A:open:on A:closed:off</li>
        <li>attr tuer2 struct_kitchen_map A</li>
      </ul>
      </li>

    <a name="evaluateSetResult"></a>
    <li>evaluateSetResult<br>
      Falls ein set Befehl den Status der Struktur-Mitglieder auf was
      unterschiedliches setzt (wie z.Bsp. beim set statusRequest), dann muss
      dieses Attribut auf 1 gesetzt werden, wenn die Struktur Instanz diesen
      neuen Status auswerten soll.
      </li>


    <li>structexclude<br>
      Bei gesetztem Attribut wird set, attr/deleteattr ignoriert.  Dies
      trifft ebenfalls auf die Weitergabe des Devicestatus an die Struktur zu.
      Fuer set und fuer die Status-Weitergabe muss der Wert den Strukturnamen
      matchen, bei einem Attribut-Befehl die Kombination
      Strukturname:Attributname.
      Beispiel:
        <ul>
          <code>
          define kitchen structure room lamp1 lamp2<br>
          attr lamp1 structexclude kitchen<br>
          attr lamp1 structexclude kitchen:stateFormat<br>
          </code>
        </ul>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut

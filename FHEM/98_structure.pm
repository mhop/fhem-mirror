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
  $hash->{AttrList}  = "clientstate_priority ".
                       "clientstate_behavior:relative,absolute,last loglevel:0,5 ".
                       $readingFnAttributes;

  addToAttrList("structexclude");

  my %ahash = ( Fn=>"CommandAddStruct",
                Hlp=>"<structure> <devspec>,add <devspec> to <structure>" );
  $cmds{addstruct} = \%ahash;

  my %dhash = ( Fn=>"CommandDelStruct",
                Hlp=>"<structure> <devspec>,delete <devspec> from <structure>");
  $cmds{delstruct} = \%dhash;
}


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

  addToAttrList($stype);
  addToAttrList($stype . "_map");
  $hash->{ATTR} = $stype;

  my %list;
  foreach my $a (@a) {
    foreach my $d (devspec2array($a)) {
      $list{$d} = 1;
    }
  }
  $hash->{CONTENT} = \%list;

  @a = ( "set", $devname, $stype, $devname );
  structure_Attr(@a);

  return undef;
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
# returns the unique keys of the given array
# @my_array = ("one","two","three","two","three");
# print join(" ", @my_array), "\n";
# print join(" ", uniq(@my_array)), "\n";

sub uniq {
    return keys %{{ map { $_ => 1 } @_ }};
}


#############################
sub structure_Notify($$)
{
  my ($hash, $dev) = @_;
  #Log 1, Dumper($hash);
  my $me = $hash->{NAME};
  my $devmap = $hash->{ATTR}."_map";

  return "" if(AttrVal($me,"disable", undef));

  #pruefen ob Devices welches das notify ausgeloest hat Mitglied dieser
  # Struktur ist
  return "" if (!$hash->{CONTENT}->{$dev->{NAME}});

  # lade das Verhalten, Standard ist absolute 
  my $behavior = AttrVal($me, "clientstate_behavior", "absolute");
  my @clientstate;

  # hier nur den Struktur-Status anpassen wenn 
  # a) behavior=absolute oder 
  # b) behavior=relative UND das Attr clientstate_priority gefaellt ist
  my @structPrio = split(" ", $attr{$me}{clientstate_priority})
        if($attr{$me}{clientstate_priority});
  return "" if (!@structPrio && $behavior eq "relative");


  if($hash->{INNTFY}) {
    Log 1, "ERROR: endless loop detected in structure_Notify $me";
    return "";
  }
  $hash->{INNTFY} = 1;

  # assoziatives Array aus Prioritaetsliste aufbauen
  # Bsp: Original: "On|An Off|Aus"
  # wobei der erste Wert der "Oder"-Liste als Status der Struktur uebernommen
  # wird hier also On oder Off
  # priority[On]=0
  # priority[An]=0
  # priority[Off]=1
  # priority[Aus]=1 
  my %priority;
  my (@priority, @foo); 
  for (my $i=0; $i<@structPrio; $i++) {
      @foo = split(/\|/, $structPrio[$i]);
      for (my $j=0; $j<@foo;$j++) {
        $priority{$foo[$j]} = $i+1;
        $priority[$i+1]=$foo[0];
      }
  }
  undef @foo;
  undef @structPrio;
  #Log 1, Dumper(%priority) . "\n";
  
  my $minprio = 99999;
  my $devstate;

  #ueber jedes Device das zu dieser Struktur gehoert
  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    next if(!$defs{$d});

    # wenn zum Device das "structexclude" gesetzt ist, wird dieses nicht
    # beruecksichtigt
    if($attr{$d} && $attr{$d}{structexclude}) {
      my $se = $attr{$d}{structexclude};
      next if($me =~ m/$se/);
    }


    # Status des Devices gemaess den Regeln des gesetztes StrukturAttr
    # umformatieren
    if($attr{$d} && $attr{$d}{$devmap}) {
      my @gruppe = split(" ", $attr{$d}{$devmap});
      my @value;
      for (my $i=0; $i<@gruppe; $i++) {
        @value = split(":", $gruppe[$i]);
        if(@value == 1) {
          # nur das zu lesende Reading ist angegeben, zb. bei 1wire Modul
          # OWSWITCH
          #Bsp: A --> nur Reading A gehoert zur Struktur
          #Bsp: A B --> Reading A und B gehoert zur Struktur
          $devstate = ReadingsVal($d, $value[0], undef);
          push(@clientstate, $devstate) if(defined($devstate));

        } elsif(@value == 2) {
          # zustand wenn der Status auf dem in der Struktur definierten
          # umdefiniert werden muss
          # bsp: on:An
          $devstate = ReadingsVal($d, "state", undef);
          if(defined($devstate) && $devstate eq $value[0]){
            $devstate = $value[1];
            push(@clientstate, $devstate);
            $i=99999;
          }

        } elsif(@value == 3) {
          # Das zu lesende Reading wurde mit angegeben:
          # Reading:OriginalStatus:NeuerStatus wenn zb. ein Device mehrere
          # Readings abbildet, zb. 1wire DS2406, DS2450 Bsp: A:Zu.:Geschlossen
          $devstate = ReadingsVal($d, $value[0], undef);
          if(defined($devstate) && $devstate eq $value[1]){
            $devstate = $value[2];
            push(@clientstate, $devstate);
            # $i=99999; entfernt, wenn Device mehrere Ports/Readings abbildet
            # wird beim ersten Auftreten sonst nicht weiter geprueft
          }
        }
        # Log 1, "Dev: ".$d." Anzahl: ".@value." Value:".$value[0]." devstate:
        # ".$devstate;
        $minprio = $priority{$devstate}
                if(defined($devstate) &&
                   $priority{$devstate} &&
                   $priority{$devstate} < $minprio);
      }
    } else {
      # falls kein mapping im Device angegeben wurde
      $devstate = ReadingsVal($d, "state", undef);
      $minprio = $priority{$devstate}
               if(defined($devstate) &&
                  $priority{$devstate} &&
                  $priority{$devstate} < $minprio);
      push(@clientstate, $devstate) if(defined($devstate));
    }

    #besser als 1 kann minprio nicht werden
    last if($minprio == 1);
  } #foreach

  @clientstate = uniq(@clientstate);# eleminiere alle Dubletten

  #ermittle Endstatus
  my $newState = "undefined";
  if($behavior eq "absolute"){
    # wenn absolute, dann gebe undefinierten Status aus falls die Clients
    # unterschiedliche Stati haben  
    $newState = (@clientstate == 1 ? $clientstate[0] : "undefined");

  } elsif($behavior eq "relative" && $minprio < 99999) {
    $newState = $priority[$minprio];

  } elsif($behavior eq "last"){
    $newState = ReadingsVal($dev->{NAME}, "state", undef);

  }

  #eigenen Status jetzt setzen, nur wenn abweichend
  my $oldState = ReadingsVal($me, "state", "");
  if($oldState ne $newState) {
    Log GetLogLevel($me,5), "Update structure '$me' to $newState" .
                " because device $dev->{NAME} has changed";
    readingsSingleUpdate($hash, "state", $newState, 1);
  }
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
    $hash->{CONTENT}{$d} = 1;
  }

  @a = ( "set", $hash->{NAME}, $hash->{ATTR}, $hash->{NAME} );
  structure_Attr(@a);
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
    delete($hash->{CONTENT}{$d});
  }

  @a = ( "del", $hash->{NAME}, $hash->{ATTR} );
  structure_Attr(@a);
  return undef;
}


###################################
sub
structure_Set($@)
{
  my ($hash, @list) = @_;
  my $ret = "";
  my %pars;

  $hash->{INSET} = 1;

  $hash->{STATE} = join(" ", @list[1..@list-1])
    if($list[1] ne "?");

  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    next if(!$defs{$d});
    if($defs{$d}{INSET}) {
      Log 1, "ERROR: endless loop detected for $d in " . $hash->{NAME};
      next;
    }

    if($attr{$d} && $attr{$d}{structexclude}) {
      my $se = $attr{$d}{structexclude};
      next if($hash->{NAME} =~ m/$se/);
    }

    $list[0] = $d;
    my $sret .= CommandSet(undef, join(" ", @list));
    if($sret) {
      $ret .= "\n" if($ret);
      $ret .= $sret;
      if($list[1] eq "?") {
        $sret =~ s/.*one of //;
        map { $pars{$_} = 1 } split(" ", $sret);
      }
    }
  }
  delete($hash->{INSET});
  Log GetLogLevel($hash->{NAME},5), "SET: $ret" if($ret);
  return $list[1] eq "?"
           ? "Unknown argument ?, choose one of " . join(" ", sort keys(%pars))
           : undef;
}

###################################
sub
structure_Attr($@)
{
  my ($type, @list) = @_;

  return undef if($list[1] eq "alias" ||
                  $list[1] eq "room" ||
                  $list[1] =~ m/clientstate/ ||
                  $list[1] eq "loglevel");

  my $me = $list[0];
  my $hash = $defs{$me};

  if($hash->{INATTR}) {
    Log 1, "ERROR: endless loop detected in structure_Attr for $me";
    next;
  }
  $hash->{INATTR} = 1;

  my $ret = "";
  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
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
  Log GetLogLevel($me,4), "Stucture attr $type: $ret" if($ret);
  return undef;
}

1;

=pod
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
    Every set command is propagated to the attached devices. Exception: if an
    attached device has an attribute structexclude, and the attribute value
    matches (as a regexp) the name of the current structure.
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
        space. Each entry of one group is delimited by "pipe".  The status
        represented by the structure is the first entry of each group.
        Example:<br>
        <ul>
          <li>attr kitchen clientstate_behavior relative</li>
          <li>attr kitchen clientstate_priority An|On|on Aus|Off|off</li>
          <li>attr house clientstate_priority Any_On|An All_Off|Aus</li>
        </ul>
        In this example the status of kitchen is either on or off.  The status
        of house is either Any_on or All_off.
        <br>
        To group more devices from different types of devices you can define
        a clientstate redefining on each device with the attribute &lt;struct_type&gt;_map.
        For example the reading "A" of device door is "open" or "closed"
        and the state of device lamp1 should redefine from "on" to "An" and "off" to "Aus".
        A special case is a device with more than 1 input port (eg. OWSWITCH). The last
        example shows the attribute only with a value of "A". The propagated
        value of the device depends only on port A with an unmodified state.
        <br>Example:<br>
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
    <code>define &lt;name&gt; structure &lt;struct_type&gt; &lt;dev1&gt; &lt;dev2&gt; ...</code>
    <br><br>
    Mit dem Device "Structure" werden Strukturen/Zusammenstellungen von anderen
    Devices erstellt um sie zu Gruppen zusammenzufassen. (Beispiel: im Haus alles ausschalten)
    <br>
    Die Liste der Devices die einer Struktur zugeordnet sind kann duch das Kommando
    <code>addstruct / delstruct</code> im laufenden Betrieb ver&auml;ndert werden. Es k&ouml;nnen
    sowohl einzelne Devices als auch Gruppen von Devices (TYPE=FS20) zugef&uuml;gt werden.
    Jedes zugef&uuml;gt Device erh&auml;lt zwei neue Attribute &lt;struct_type&gt;=&lt;name&gt;
    sowie &lt;struct_type&gt;_map wenn es zu einer Struktur zugef&uuml;gt wurde. Diese
    Attribute werden wieder automatisch entfernt, sobald das Device von der Struktur
    entfernt wird.<br>
    Eine Struktur kann ebenfalls zu einer anderen Struktur zugef&uuml;gt werden. Somit
    k&ouml;nnen z b. kaskadierende Strukturen erstellt werden. (Z.b. KG,EG,OG, Haus)

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
    Jedes set Kommando wird an alle Devices dieser Struktur weitergegeben.<br>
    Aussnahme: das Attribut structexclude ist in einem Device definiert und
    dessen Attributwert matched als Regexp zum Namen der aktuellen Struktur.
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
    <a name="clientstate_behavior"></a>
    <li>clientstate_behavior<br>
      Der Status einer Struktur h&auml;ngt von den Stati der zugef&uuml;gten Devices ab.
      Dabei wird das propagieren der Stati der Devices in zwei Gruppen klassifiziert
      und mittels diesem Attribut definiert:
      <ul>
      <li>absolute</li>
      <ul>
        Die Struktur wird erst dann den Status der zugef&uuml;gten Devices annehmen,
        wenn alle Devices einen identischen Status vorweisen. Bei unterschiedlichen
        Devictypen kann dies per Attribut &lt;struct_type&gt;_map pro Device
        beinflusst werden. Andernfalls hat die Struktur den Status "undefined".
      </ul>
      <li>relative</li>
      <ul>
        S.u. clientstate_priority.
      </ul>
      <li>last</li>
      <ul>
        Die Struktur &uuml;bernimmt den Status des zuletzt ge&auml;nderten Ger&auml;tes.
      </ul>
    </li>
  </ul>

    <a name="clientstate_priority"></a>
    <li>clientstate_priority<br>
      Wird die Struktur auf ein relatives Verhalten eingestellt, so wird die
      Priorit&auml;t der Devicestati &uuml;ber das Attribut <code>clientstate_priority</code>
      beinflusst. Die Priorit&auml;ten sind in absteigender Reihenfolge anzugeben.
      Dabei k&ouml;nnen Gruppen mit identischer Priorit&auml;t angegeben werden, um zb.
      unterschiedliche Devicetypen zusammenfassen zu k&ouml;nnen. Jede Gruppe wird durch
      Leerzeichen, jeder Eintrag pro Gruppe durch Pipe getrennt. Der Status der
      Struktur ist der erste Eintrag in der entsprechenden Gruppe.
    </li>
    <br>Beispiel:<br>
    <ul>
      <li>attr kueche clientstate_behavior relative</li>
      <li>attr kueche clientstate_priority An|On|on Aus|Off|off</li>
      <li>attr haus clientstate_priority Any_On|An All_Off|Aus</li>
    </ul>
    In diesem Beipiel nimmt die Struktur <code>kueche</code>entweder den Status
    <code>An</code> oder <code>Aus</code> an. Die Struktur <code>haus</code> nimmt
    entweder den Status <code>Any_on</code> oder <code>All_off</code> an. Sobald ein
    Device der Struktur <code>haus</code> den Status <code>An</code> hat nimmt die
    Struktur den Status <code>Any_On</code> an. Um dagegen den Status
    <code>All_off</code> anzunehmen, m&uuml;ssen alle Devices dieser Struktur auf
    <code>off</code> stehen.
    <br>
    Um mehrere Devices unterschiedlicher Typen gruppieren zu k&ouml;nnen ist ein
    Status-Mapping auf jedem einzelnen Device mittels Attribut &lt;struct_type&gt;_map
    m&ouml;glich.
    Im folgenden Beispiel nimmt das Reading "A" den Status "offen" oder "geschlossen"
    an, und des Reading "state" von "lampe1" den Status "on" oder "off".
    Die Struktur "kueche" reagiert nun auf "An" bzw "on" (Prio 1) bzw.
    auf "OK", "Aus", "off". Der Status den diese Struktur schlussendlich annehmen kann
    ist entweder "An" oder "OK".<br>
    Der Status des Devices lampe1 wird umdefiniert von "on" nach "An" bzw "off" nach "Aus".
    Das Device "tuer", welches vom Type "OWSWITCH" ist, bringt ausschlie&szlig;lich
    das Reading A in die Struktur ein welches von "open" nach "on" sowie "clesed"
    nach "Aus" umdefiniert wird.<br>
    Die Struktur <code>kueche</code> wird folglich nur dann "An" ausgeben,
    wenn a) das Device lampe1 den Status "on" und(!) b) das Device tuer den Status
    open im Reading A aufweist. Die Struktur wird sofort auf den Status "OK" wechseln,
    sobald eines der beiden Devices den Status wechselt.<br>
    Ist im Attribut &lt;struct_type&gt;_map nur das Reading angegeben, so wird dessen
    Status unmodifiziert an die Struktur weitergegeben.<br>
    Ist das Attribut &lt;struct_type&gt;_map nicht definiert, so wird das
    Reading <code>state</code> an die Struktur weitergegeben.
    <br>Beispiel:<br>
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

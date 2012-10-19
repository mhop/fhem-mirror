##############################################
# $Id$
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
  $hash->{AttrList}  = "clientstate_priority clientstate_behavior:relative,absolute";

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
  $hash->{STATE} = "defined";

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

  # lade das Verhalten, Standard ist absolute 
  my $behavior = AttrVal($me,"clientstate_behavior", "absolute");
  my @clientstate;

  return "" if($attr{$me} && $attr{$me}{disable});

  #pruefen ob Devices welches das notify ausgeloest hat Mitglied dieser
  # Struktur ist
  return "" if (!$hash->{CONTENT}->{$dev->{NAME}});

  # hier nur den Struktur-Status anpassen wenn 
  # a) behavior=absolute oder 
  # b) behavior=relative UND das Attr clientstate_priority gefaellt ist
  my @structPrio = split(" ", $attr{$me}{clientstate_priority})
        if($attr{$me}{clientstate_priority});
  return "" if (!@structPrio && $behavior eq "relative");

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
  
  $hash->{INSET} = 1;
  
  my $minprio = 99999;
  my $devstate;

  #ueber jedes Device das zu dieser Struktur gehoert
  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    next if(!$defs{$d});
    if($defs{$d}{INSET}) {
      Log 1, "ERROR: endless loop detected for $d in " . $hash->{NAME};
      next;
    }

    # wenn zum Device das "structexclude" gesetzt ist, wird dieses nicht
    # beruecksichtigt
    if($attr{$d} && $attr{$d}{structexclude}) {
      my $se = $attr{$d}{structexclude};
      next if($hash->{NAME} =~ m/$se/);
    }


    # Status des Devices gemaess den Regeln des gesetztes StrukturAttr
    # umformatieren
    if ($attr{$d}{$devmap}) {
      my @gruppe = split(" ", $attr{$d}{$devmap});
      my @value;
      for (my $i=0; $i<@gruppe; $i++) {
        @value = split(":", $gruppe[$i]);
        if(@value == 1) {
          # nur das zu lesende Reading ist angegeben, zb. bei 1wire Modul
          # OWSWITCH
          #Bsp: A --> nur Reading A gehuert zur Struktur
          #Bsp: A B --> Reading A und B gehuert zur Struktur
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
  my $newState = "";
  if($behavior eq "absolute"){
    # wenn absolute, dann gebe undefinierten Status aus falls die Clients
    # unterschiedliche Status' haben  
    if(@clientstate > 1) { $newState = "undefined";}
    elsif(@clientstate > 0) { $newState = $clientstate[0];}
  } elsif($behavior eq "relative" && $minprio < 99999) {
    $newState = $priority[$minprio];
  } else {
    $newState = "undefined";
  }

  delete($hash->{INSET});

  #eigenen Status jetzt setzen, nur wenn abweichend
  if(!defined($hash->{STATE}) || ($hash->{STATE} ne $newState)) {
    Log 3, "Update structure '" .$me . "' to " . $newState .
                " because device '" .$dev->{NAME}. "' has changed";
    $hash->{STATE} = $newState;
    readingsBeginUpdate($hash);
    readingsUpdate($hash, "state", $newState);
    readingsEndUpdate($hash, 1);
  }
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
  Log 5, "SET: $ret" if($ret);
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
                  $list[1] eq "room");
  my $hash = $defs{$list[0]};
  $hash->{INATTR} = 1;
  my $ret = "";
  foreach my $d (sort keys %{ $hash->{CONTENT} }) {
    next if(!$defs{$d});
    if($defs{$d}{INATTR}) {
      Log 1, "ERROR: endless loop detected for $d in " . $hash->{NAME};
      next;
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
  Log 5, "ATTR: $ret" if($ret);
  return undef;
}

1;

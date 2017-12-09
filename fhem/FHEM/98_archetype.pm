# Id ##########################################################################
# $Id$

# copyright ###################################################################
#
# 98_archetype.pm
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

# verbose
#   Set the verbosity level. Possible values:
#     0 - server start/stop
#     1 - error messages or unknown packets
#     2 - major events/alarms.
#     3 - commands sent out will be logged.
#     4 - you'll see whats received by the different devices.
#     5 - debugging.

package main;
  use strict;
  use warnings;

# forward declarations ########################################################
sub archetype_Initialize($);

sub archetype_Define($$);
sub archetype_Undef($$);
sub archetype_Set($@);
sub archetype_Get($@);
sub archetype_Attr(@);
sub archetype_Notify($$);

sub archetype_AnalyzeCommand($$$$$);
sub archetype_attrCheck($$$$;$);
sub archetype_DEFcheck($$;$) ;
sub archetype_define_inheritors($;$$$);
sub archetype_derive_attributes($;$$$);
sub archetype_devspec($;$);
sub archetype_evalSpecials($$;$);
sub archetype_inheritance($;$$);

sub CommandClean($$);

# initialize ##################################################################
sub archetype_Initialize($) {
  my ($hash) = @_;
  my $TYPE = "archetype";

  Log(5, "$TYPE - call archetype_Initialize");

  $hash->{DefFn}      = "$TYPE\_Define";
  $hash->{UndefFn}    = "$TYPE\_Undef";
  $hash->{SetFn}      = "$TYPE\_Set";
  $hash->{GetFn}      = "$TYPE\_Get";
  $hash->{AttrFn}     = "$TYPE\_Attr";
  $hash->{NotifyFn}   = "$TYPE\_Notify";

  $hash->{AttrList} = ""
    . "actual_.+ "
    . "actualTYPE "
    . "attributes "
    . "autocreate:1,0 "
    . "deleteAttributes:0,1 "
    . "disable:0,1 "
    . "initialize:textField-long "
    . "metaDEF:textField-long "
    . "metaNAME:textField-long "
    . "readingList "
    . "relations "
    . "setList:textField-long "
    . "splitRooms:0,1 "
    . $readingFnAttributes
  ;

  addToAttrList("attributesExclude");

  my %hash = (
    Fn  => "CommandClean",
    Hlp => "[check]"
  );
  $cmds{clean} = \%hash;
}

# regular Fn ##################################################################
sub archetype_Define($$) {
  my ($hash, $def) = @_;
  my ($SELF, $TYPE, $DEF) = split(/[\s]+/, $def, 3);

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Define");

  if($hash->{DEF} eq "derive attributes"){
    my $derive_attributes = $modules{$TYPE}{derive_attributes};

    return(
        "$TYPE for deriving attributes already definded as "
      . "$derive_attributes->{NAME}"
    ) if($derive_attributes);

    $modules{$TYPE}{derive_attributes} = $hash;
  }

  $hash->{DEF} = "defined_by=$SELF" unless($DEF);
  $hash->{NOTIFYDEV} = "global";
  $hash->{STATE} = "active"
    unless(AttrVal($SELF, "stateFormat", undef) || IsDisabled($SELF));

  return;
}

sub archetype_Undef($$) {
  my ($hash, $SELF) = @_;
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Undef");

  delete $modules{$TYPE}{derive_attributes}
    if($hash->{DEF} eq "derive attributes");

  return;
}

sub archetype_Set($@) {
	my ($hash, @arguments) = @_;
  my $SELF = shift @arguments;
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Set");

  return "\"set $TYPE\" needs at least one argument" unless(@arguments);

	my $argument = shift @arguments;
  my $value = join(" ", @arguments) if(@arguments);
  my %archetype_sets;

  if($hash->{DEF} eq "derive attributes"){
    %archetype_sets = (
        "addToAttrList" => "addToAttrList:textField"
      , "derive" => "derive:attributes"
    );
  }
  else{
    %archetype_sets = (
        "define" => "define:inheritors"
      , "inheritance" => "inheritance:noArg"
      , "initialize" => "initialize:inheritors"
      , "raw" => "raw:textField"
    );
    $archetype_sets{(split(":", $_))[0]} = $_
      foreach (split(/[\s]+/, AttrVal($SELF, "setList", "")));
  }

  return(
      "Unknown argument $argument, choose one of "
    . join(" ", values %archetype_sets)
  ) unless(exists($archetype_sets{$argument}));

  if($argument eq "addToAttrList"){
    addToAttrList($value);
  }
  elsif($argument eq "derive" && $value eq "attributes"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument $value");

    archetype_derive_attributes($SELF);

    Log3($SELF, 3, "$TYPE ($SELF) - $argument $value done");
  }
  elsif($argument eq "define" && $value eq "inheritors"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument $value");

    archetype_define_inheritors($SELF);

    Log3($SELF, 3, "$TYPE ($SELF) - $argument $value done");
  }
  elsif($argument eq "inheritance"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument inheritors");

    archetype_inheritance($SELF);
  }
  elsif($argument eq "initialize" && $value eq "inheritors"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument $value");

    archetype_define_inheritors($SELF, $argument);

    Log3($SELF, 3, "$TYPE ($SELF) - $argument $value done");
  }
  elsif($argument eq "raw" && $value){
    (my $command, $value) = split(/[\s]+/, $value, 2);

    return "\"set $TYPE\" $argument at least one command and argument"
      unless($value);

    Log3($SELF, 3, "$TYPE ($SELF) - $command <inheritors> $value");

    fhem("$command " . join(",", archetype_devspec($SELF)) . " $value");
  }
  else{
    my @readingList = split(/[\s]+/, AttrVal($SELF, "readingList", ""));

    if(@readingList && grep(/\b$argument\b/, @readingList)){
      Log3($SELF, 3, "$TYPE set $SELF $argument $value");

      readingsSingleUpdate($hash, $argument, $value, 1);
    }
    else{
      Log3($SELF, 3, "$TYPE set $SELF $argument $value");

      readingsSingleUpdate($hash, "state", "$argument $value", 1);
    }
  }

  return;
}

sub archetype_Get($@) {
	my ($hash, @arguments) = @_;
  my $SELF = shift @arguments;
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Get");

  return "\"get $TYPE\" needs at least one argument" unless(@arguments);

  my $argument = shift @arguments;
  my $value = join(" ", @arguments) if(@arguments);
  my $derive_attributes = $hash->{DEF} eq "derive attributes";
  my %archetype_gets;

  if($derive_attributes){
    %archetype_gets = (
      "inheritors" => "inheritors:noArg",
      "pending" => "pending:attributes"
      );
  }else{
    %archetype_gets = (
      "inheritors" => "inheritors:noArg",
      "pending" => "pending:attributes,inheritors",
      "relations" => "relations:noArg"
    );
  }

  return(
      "Unknown argument $argument, choose one of "
    . join(" ", values %archetype_gets)
  ) unless(exists($archetype_gets{$argument}));

  return "$SELF is disabled" if(IsDisabled($SELF));

  if($argument =~ /^(inheritors|relations)$/){
    Log3($SELF, 3, "$TYPE ($SELF) - starting request $argument");

    my @devspec;

    if($derive_attributes){
      @devspec = archetype_devspec($SELF, "specials");
    }
    elsif($argument eq "relations"){
      @devspec = archetype_devspec($SELF, "relations");
    }
    else{
      @devspec = archetype_devspec($SELF);
    }

    Log3($SELF, 3, "$TYPE ($SELF) - request $argument done");

    return @devspec ? join("\n", @devspec) : "no $argument defined";
  }
  elsif($argument eq "pending"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting request $argument $value");

    my @ret;

    if($value eq "attributes"){
      my @attributes = sort(split(/[\s]+/, AttrVal($SELF, "attributes", "")));

      if($derive_attributes){
        @ret = archetype_derive_attributes($SELF, 1);
      }
      else{
        foreach (archetype_devspec($SELF)){
          for my $attribute (@attributes){
            my $desired =
              AttrVal(
                $SELF, "actual_$attribute", AttrVal($SELF, $attribute, "")
              );

            next if($desired eq "");

            push(@ret, archetype_attrCheck($SELF, $_, $attribute, $desired, 1));
          }
        }
      }
    }
    elsif($value eq "inheritors"){
      @ret = archetype_define_inheritors($SELF, 0, 1);
    }

    Log3($SELF, 3, "$TYPE ($SELF) - request $argument $value done");

    return(@ret ? join("\n", @ret) : "no $value $argument");
    return(
        "Unknown argument $value, choose one of "
      . join(" ", split(",", (split(":", $archetype_gets{$argument}))[1]))
    );
  }
}

sub archetype_Attr(@) {
  my ($cmd, $SELF, $attribute, $value) = @_;
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Attr");

  if($attribute eq "disable" && ($cmd eq "del" || $value eq "0")){
    if(AttrVal($SELF, "stateFormat", undef)){
      evalStateFormat($hash);
    }
    else{
      $hash->{STATE} = "active";
    }

    Log3($SELF, 3, "$TYPE ($SELF) - starting inheritance inheritors");

    archetype_inheritance($SELF);
  }
  elsif($attribute =~ /^actual_/){
    if($cmd eq "set"){
      addToDevAttrList($SELF, $attribute)
    }
    else{
      my %values =
        map{$_, 0} split(" ", AttrVal($SELF, "userattr", ""));
      delete $values{$attribute};
      my $values = join(" ", sort(keys %values));

      if($values eq ""){
        CommandDeleteAttr(undef, "$SELF userattr");
      }
      else{
        $attr{$SELF}{userattr} = $values;
      }
    }
  }

  return if(IsDisabled($SELF));

  my @attributes = AttrVal($SELF, "attributes", "");

  if(
    $cmd eq "del"
    && $attribute ne "disable"
    && AttrVal($SELF, "deleteAttributes", 0) eq "1"
  ){
    CommandDeleteAttr(
        undef
      , join(",", archetype_devspec($SELF))
      . ":FILTER=a:attributesExclude!=.*$attribute.* $attribute"
    );
  }
  elsif($cmd eq "del" && $attribute ne "stateFormat"){
    $hash->{STATE} = "active";
  }
  elsif(
    $cmd eq "set"
    && (
      grep(/\b$attribute\b/, @attributes)
      || $attribute =~ /^actual_(.+)$/ && grep(/\b$1\b/, @attributes)
    )
  ){
    $attribute = $1 if($1);
    Log3(
      $SELF, 3
      , "$TYPE ($SELF) - "
      . "starting inheritance attribute \"$attribute\" to inheritors"
    );

    archetype_inheritance($SELF, undef, $attribute);
  }
  elsif($attribute eq "attributes" && $cmd eq "set"){
    if($value =~ /actual_/ && $value !~ /userattr/){
      $value = "userattr $value";
      $_[3] = $value;
      $attr{$SELF}{$attribute} = $value;
    }

    Log3($SELF, 3, "$TYPE ($SELF) - starting inheritance inheritors");

    archetype_inheritance($SELF, undef, $value);
  }
  elsif($attribute eq "disable" && $cmd eq "set" && $value eq "1"){
    $hash->{STATE} = "disabled";
  }

  return;
}

sub archetype_Notify($$) {
  my ($hash, $dev_hash) = @_;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Notify");

  return if(IsDisabled($SELF));
  return unless(AttrVal($SELF, "autocreate", 1));

  my @events = @{deviceEvents($dev_hash, 1)};

  return unless(@events);

  foreach my $event (@events){
    next unless($event);

    Log3($SELF, 4, "$TYPE ($SELF) - triggered by event: \"$event\"");

    my ($argument, $name, $attr, $value) = split(/[\s]+/, $event, 4);

    return unless($name);

    if($argument eq "DEFINED" && grep(/\b$name\b/, archetype_devspec($SELF))){
      Log3($SELF, 3, "$TYPE ($SELF) - starting inheritance $name");

      archetype_inheritance($SELF, $name);
    }
    elsif(
      $argument eq "DEFINED"
      && grep(/\b$name\b/, archetype_devspec($SELF, "relations"))
    ){
      Log3($SELF, 3, "$TYPE ($SELF) - starting define inheritors");

      archetype_define_inheritors($SELF, undef, undef, $name);

      Log3($SELF, 3, "$TYPE ($SELF) - define inheritors done");
    }
    elsif(
      $hash->{DEF} eq "derive attributes"
      && $argument eq "ATTR"
      && grep(/\b$name\b/, archetype_devspec($SELF, "specials"))
    ){
      for my $attribute (split(" ", AttrVal($SELF, "attributes", ""))){
        my @specials = archetype_evalSpecials(
          undef, AttrVal($SELF, "actual_$attribute", ""), "all"
        );

        if(grep(/\b$attr\b/, @specials)){
          archetype_derive_attributes($SELF, undef, $name, $attribute);

          last;
        }
      }
    }
  }

  return;
}

# module Fn ###################################################################
sub archetype_AnalyzeCommand($$$$$) {
  # Wird ausgefuehrt um metaNAME und metaDEF auszuwerten.
  my ($cmd, $name, $room, $relation, $SELF) = @_;
  if($SELF){
    my ($hash) = $defs{$SELF};
    my $TYPE = $hash->{TYPE};

    Log3($SELF, 5, "$TYPE ($SELF) - call archetype_AnalyzeCommand");
  }

  return unless($cmd);

  # # Stellt Variablen fuer Zeit und Datum zur Verfuegung.
  # my ($sec, $min, $hour, $mday, $month, $year, $wday, $yday, $hms, $we) =
  #   split(" ",
  #     AnalyzePerlCommand(
  #       undef, '"$sec $min $hour $mday $month $year $wday $yday $hms $we"'
  #     )
  #   );;

  # Falls es sich nicht um einen durch {} gekennzeichneten Perl Befehlt
  # handelt, werden alle Anfuehrungszeichen maskiert und der Befehl in
  # Anfuehrungszeichen gesetzt um eine korrekte Auswertung zu gewaehrleisten.
  unless($cmd =~ m/^\{.*\}$/){
    $cmd =~ s/"/\\"/g;
    $cmd = "\"$cmd\""
  }

  $cmd = eval($cmd);

  return($cmd);
}

sub archetype_attrCheck($$$$;$) {
  # Wird fuer jedes vererbende Attribut und fuer jeden Erben ausgefuehrt um zu
  # pruefen ob das Attribut den vorgaben entspricht.
  my ($SELF, $name, $attribute, $desired, $check) = @_;
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};
  my $actual = AttrVal($name, $attribute, "");

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_attrCheck");

  return if(AttrVal($name, "attributesExclude", "") =~ /$attribute/);


  if($desired =~ m/^least(\((.*)\))?:(.+)/){
    my $seperator = $2 ? $2 : " ";
    my %values =
      map{$_, 0} (split(($seperator), $actual), split($seperator, $3));
    $desired = join($seperator, sort(keys %values));
  }
  elsif($desired =~ m/^undef/){
    return if(AttrVal($name, $attribute, undef));
    $desired = (split(":", $desired, 2))[1];
  }

  if($hash->{DEF} eq "derive attributes"){
    $desired = eval($desired) if($desired =~ m/^\{.*\}$/);
    $desired = archetype_evalSpecials($name, $desired) if($desired =~ m/%/);
  }

  return unless($desired);

  if($actual ne $desired){
    if($check){
      my $ret;
      $ret .= "-attr $name $attribute $actual\n" if($actual ne "");
      $ret .= "+attr $name $attribute $desired";

      return $ret;
    }

    fhem("attr $name $attribute $desired");
    # CommandAttr(undef, "$name $attribute $desired");
  }

  return;
}

sub archetype_DEFcheck($$;$) {
  my ($name, $type, $expected) = @_;
  my ($hash) = $defs{$name};

  if($expected && $expected ne InternalVal($name, "DEF", " ")){
    CommandDefMod(undef, "$name $type $expected");
  }else{
    CommandDefMod(undef, "$name $type") unless(IsDevice($name, $type));
  }
}

sub archetype_define_inheritors($;$$$) {
  my ($SELF, $init, $check, $relation) = @_;
  my ($hash) = $defs{$SELF};

  return if(IsDisabled($SELF));

  my @relations = $relation ? $relation : archetype_devspec($SELF, "relations");

  return unless(@relations);

  my @ret;
  my $TYPE = AttrVal($SELF, "actualTYPE", "dummy");
  my $initialize = AttrVal($SELF, "initialize", undef);
  if($initialize && $initialize !~ /^\{.*\}$/s){
  	$initialize =~ s/\"/\\"/g;
    $initialize = "\"$initialize\"";
  }

  foreach my $relation (@relations){
    my $room = AttrVal($relation, "room", "Unsorted");

    foreach $room (
      AttrVal($SELF, "splitRooms", 0) eq "1" ? split(",", $room) : $room
    ){
      my $name = archetype_AnalyzeCommand(
        AttrVal($SELF, "metaNAME", ""), undef, $room, $relation, $SELF
      );
      my $DEF = archetype_AnalyzeCommand(
        AttrVal($SELF, "metaDEF", " "), $name, $room, $relation, $SELF
      );
      my $defined = IsDevice($name, $TYPE) ? 1 : 0;

      unless($defined && InternalVal($name, "DEF", " ") eq $DEF){
        if($check){
          push(@ret, $name);

          next;
        }
        unless($init){
          archetype_DEFcheck($name, $TYPE, $DEF);
          addToDevAttrList($name, "defined_by");
          $attr{$name}{defined_by} = $SELF;
        }
      }

      next if($check);

      fhem(eval($initialize)) if(
        $initialize
        && IsDevice($name, $TYPE)
        && (!$defined || $init)
      );

      archetype_inheritance($SELF, $name) unless($init);
    }
  }

  if($check){
    my %ret = map{$_, 1} @ret;
    return sort(keys %ret);
  }

  return;
}

sub archetype_derive_attributes($;$$$) {
  my ($SELF, $check, $name, $attribute) = @_;
  my ($hash) = $defs{$SELF};
  my @ret;
  my @devspecs = $name ? $name : archetype_devspec($SELF, "specials");
  my @attributes =
    $attribute ?
      $attribute
    : sort(split(/[\s]+/, AttrVal($SELF, "attributes", "")))
  ;

  foreach (@devspecs){
    for my $attribute (@attributes){
      my $desired = AttrVal(
        $_, "actual_$attribute", AttrVal($SELF, "actual_$attribute", "")
      );

      next if($desired eq "");

      if($check){
        push(@ret, archetype_attrCheck($SELF, $_, $attribute, $desired, 1));

        next;
      }

      archetype_attrCheck($SELF, $_, $attribute, $desired);
    }
  }

  return(@ret);
}

sub archetype_devspec($;$) {
  my ($SELF, $devspecs) = @_;
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_devspec");

  if(!$devspecs){
    $devspecs = InternalVal($SELF, "DEF", "");
  }
  elsif($devspecs eq "relations"){
    $devspecs = AttrVal($SELF, "relations", "");
  }
  elsif($devspecs eq "specials"){
    $devspecs = "";
    for my $attribute (split(" ", AttrVal($SELF, "attributes", ""))){
      no warnings;

      $devspecs .= " a:actual_$attribute=.+";
      my $actual_attribute = AttrVal($SELF, "actual_$attribute", "");

      if($actual_attribute =~ m/^\{.*\}$/){
        $devspecs .= " .+";
      }
      else{
        my $mandatory = join(" ", archetype_evalSpecials(
          $SELF, $actual_attribute, "mandatory"
        ));

        while($mandatory =~ m/[^\|]\|[^\|]/){
          my @parts = split("\\|\\|", $mandatory);;
          $_ =~ s/(.* )?(\S+)\|(\S+)( .*)?/$1$2$4\|\|$1$3$4/ for(@parts);;
          $mandatory = join("\|\|", @parts);;
        }

        for my $mandatory (split("\\|\\|", $mandatory)){
          $devspecs .= " .+";
          $devspecs .= ":FILTER=a:$_=.+" for(split(" ", $mandatory));
        }
      }
    }
  }

  my @devspec;
  push(@devspec, devspec2array($_)) foreach (split(/[\s]+/, $devspecs));
  my %devspec = map{$_, 1}@devspec;
  delete $devspec{$SELF};

  return sort(keys %devspec);
}

sub archetype_evalSpecials($$;$) {
  my ($name, $pattern, $get) = @_;
  my $value;

  if($get){
    $pattern =~ s/\[[^]]*\]//g if($get eq "mandatory");

    return(($pattern =~ m/%(\S+)%/g));
  }

  for my $part (split(/\[/, $pattern)){
    for my $special ($part =~ m/%(\S+)%/g){
      foreach (split("\\|", $special)){
        my $AttrVal = AttrVal($name, $_, undef);
        $AttrVal = archetype_AnalyzeCommand(
          $AttrVal, $name, AttrVal($name, "room", undef), undef, undef
        ) if($AttrVal);

        if($AttrVal){
          $part =~ s/\Q%$special%\E/$AttrVal/;

          last;
        }
      }
    }

    ($part, my $optional) = ($part =~ m/([^\]]+)(\])?$/);

    return unless($optional || $part !~ m/%\S+%/);

    $value .= $part unless($optional && $part =~ m/%\S+%/);
  }

  return $value;
}

sub archetype_inheritance($;$$) {
  my $SELF = shift;
  my ($hash) = $defs{$SELF};
  my $TYPE = $hash->{TYPE};
  my @devices = shift;
  @devices = archetype_devspec($SELF) unless($devices[0]);
  my @attributes = shift;

  if($attributes[0]){
    @attributes = split(/[\s]+/, $attributes[0]);
  }
  else{
    @attributes = split(/[\s]+/, AttrVal($SELF, "attributes", ""));
  }

  foreach my $attribute (@attributes){
    my $value =
      AttrVal($SELF, "actual_$attribute", AttrVal($SELF, $attribute, ""));

    next if($value eq "");

    archetype_attrCheck($SELF, $_, $attribute, $value) for (@devices);
  }

  Log3($SELF, 3, "$TYPE ($SELF) - inheritance inheritors done")
    if(@devices > 1);
  Log3($SELF, 3, "$TYPE ($SELF) - inheritance @devices done")
    if(@devices == 1);

  return;
}

# command Fn ##################################################################
sub CommandClean($$) {
  my ($client_hash, $arguments) = @_;
  my @archetypes = devspec2array("TYPE=archetype");
  my (@pendingAttributes, @pendingInheritors);
  my %pendingAttributes;

  if($arguments && $arguments eq "check"){
    foreach my $SELF (@archetypes){
      my $ret = archetype_Get($defs{$SELF}, $SELF, "pending", "attributes");

      next if(
        $ret =~ /no attributes pending|Unknown argument pending|is disabled/
      );

      foreach my $pending (split("\n", $ret)){
        my ($sign, $name, $attribute, $value) = split(" ", $pending, 4);
        $sign =~ s/^\+//;
        $pendingAttributes{$pending} = "$name $attribute $sign $value";
      }
    }

    foreach my $SELF (@archetypes){
      my $ret = archetype_Get($defs{$SELF}, $SELF, "pending", "inheritors");

      push(@pendingInheritors, $ret) if(
        $ret !~ /no inheritors pending|Unknown argument pending|is disabled/
      );
    }

    @pendingAttributes =
      sort { lc($pendingAttributes{$a}) cmp lc($pendingAttributes{$b}) }
      keys %pendingAttributes
    ;
    @pendingInheritors = sort(@pendingInheritors);

    return(
        (@pendingAttributes ?
           "pending attributes:\n" . join("\n", @pendingAttributes)
         : "no attributes pending"
        )
      . "\n\n"
      . (@pendingInheritors ?
           "pending inheritors:\n" . join("\n", @pendingInheritors)
         : "no inheritors pending"
        )
    );
  }

  fhem(
      "set TYPE=archetype:FILTER=DEF!=derive.attributes define inheritors;"
    . "set TYPE=archetype:FILTER=DEF!=derive.attributes inheritance;"
    . "set TYPE=archetype:FILTER=DEF=derive.attributes derive attributes;"
  );

  return(
      "clean done"
    . "\n\n"
    . CommandClean($client_hash, "check")
  );
}

1;

# commandref ##################################################################
=pod
=item helper
=item summary    inheritance attributes and defines devices
=item summary_DE vererbt Attribute und definiert Geräte

=begin html

<a name="archetype"></a>
<h3>archetype</h3>
( en | <a href="commandref_DE.html#archetype">de</a> )
<div>
  <ul>
    With an archetype, attributes are transferred to inheritors, other devices.
    The inheritors can be defined according to a given pattern in the archetype
    and for relations, a certain group of devices.<br>
    <br>
    Notes:
    <ul>
      <li>
        <code>$name</code><br>
        name of the inheritor
      </li><br>
      <li>
        <code>$room</code><br>
        room of the inheritor
      </li><br>
      <li>
        <code>$relation</code><br>
        name of the relation
      </li><br>
      <li>
        <code>$SELF</code><br>
        name of the archetype
      </li>
    </ul>
    <br>
    <a name="archetypecommand"></a>
    <b>Commands</b>
    <ul>
      <code>clean [check]</code><br>
      Defines all inheritors for all relations und inheritance all inheritors
      with the attributes specified under the attribute attribute.<br>
      If the "check" parameter is specified, all outstanding attributes and
      inheritors are displayed.
    </ul>
    <br>
    <a name="archetypedefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; archetype [&lt;devspec&gt;] [&lt;devspec&gt;] [...]
      </code><br>
      In the &lt;devspec&gt; are described all the inheritors for this
      archetype. Care should be taken to ensure that each inheritor is
      associated with only one archetype.<br>
      If no &lt;devspec&gt; is specified, this is set with "defined_by=$SELF".
      This devspec is also always checked, even if it is not specified.<br>
      See the section on
      <a href="#devspec">device specification</a>
      for details of the &lt;devspec&gt;.<br>
      <br>
      <code>define &lt;name&gt; archetype derive attributes</code><br>
      If the DEF specifies "derive attributes" it is a special archetype. It
      derives attributes based on a pattern.<br>
      The pattern is described with the actual_. + Attributes.<br>
      All devices with all the mandatory attributes of a pattern are listed as
      inheritors.
    </ul>
    <br>
    <a name="archetypeset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>addToAttrList &lt;attribute&gt;</code><br>
        The command is only possible for an archetype with DEF
        "derive attributes".<br>
        Add an entry to the userattr of the global device so that it is
        available to all of the devices.<br>
        This can be useful to derive the alias according to a pattern.
      </li>
      <br>
      <li>
        <code>define inheritors</code><br>
        Defines an inheritor for all relations according to the pattern:<br>
        <ul>
          <code>
            define &lt;metaNAME&gt; &lt;actualTYPE&gt; [&lt;metaDEF&gt;]
          </code>
        </ul>
        When an inheritor Is defined, it is initialized with the commands
        specified under the initialize attribute, and the archetype assign the
        defined_by attribute to the value $ SELF.<br>
        The relations, metaNAME, actualTYPE, and metaDEF are described in
        the attributes.
      </li>
      <br>
      <li>
        <code>derive attributes</code><br>
        This command is only possible for an archetype with DEF
        "derive attributes".<br>
        Derives all attributes specified under the attributes attribute for all
        inheritors.
      </li>
      <br>
      <li>
        <code>inheritance</code><br>
        Inheritance all attributes specified under the attributes attribute for
        all inheritors.
      </li>
      <br>
      <li>
        <code>initialize inheritors</code><br>
        Executes all commands specified under the attributes initialize for all
        inheritors.
      </li>
      <br>
      <li>
        <code>raw &lt;command&gt;</code><br>
        Executes the command for all inheritors.
      </li>
    </ul>
    <br>
    <a name="archetypeget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>inheritors</code><br>
        Displays all inheritors.
      </li>
      <br>
      <li>
        <code>relations</code><br>
        Displays all relations.
      </li>
      <br>
      <li>
        <code>pending attributes</code><br>
        Displays all outstanding attributes specified under the attributes
        attributes for all inheritors, which do not match the attributes of the
        archetype.
      </li>
      <br>
      <li>
        <code>pending inheritors</code><br>
        Displays all outstanding inheritors, which should be defined on the
        basis of the relations
      </li>
    </ul>
    <br>
    <a name="archetypeattr"></a>
    <b>Attribute</b>
    <ul>
      Notes:<br>
      All attributes that can be inherited can be pre-modified with a modifier.
      <ul>
        <li>
          <code>attr archetype &lt;attribute&gt; undef:&lt;...&gt;</code><br>
          If <code>undef:</code>  preceded, the attribute is inherited only if
          the inheritors does not already have this attribute.
        </li><br>
        <li>
          <code>
            attr archetype &lt;attribute&gt;
            least[(&lt;seperator&gt;)]:&lt;...&gt;
          </code><br>
          If a list is inherited, it can be specified that these elements
          should be at least present, by prepending the
          <code>least[(&lt;seperator&gt;)]:</code>.<br>
          If no separator is specified, the space is used as separator.
        </li>
      </ul>
      <br>
      <li>
        <code>actual_&lt;attribute&gt; &lt;value&gt;</code><br>
        &lt;value&gt; can be specified as &lt;text&gt; or {perl code}.<br>
        If the attribute &lt;attribute&gt; becomes inheritance the return
        value of the attribute actual_&lt;attribute&gt; is replacing the value
        of the attribute.<br>
        The archetype with DEF "derive attributes" can be used to define
        patterns.<br>
        Example:
        <code>
          actual_alias %captionRoom|room%: %description%[ %index%][%suffix%]
        </code><br>
        All terms enclosed in% are attributes. An order can be achieved by |.
        If an expression is included in [] it is optional.<br>
        The captionRoom, description, index, and suffix expressions are added
        by addToAttrList.<br>
      </li>
      <br>
      <li>
        <code>actualTYPE &lt;TYPE&gt;</code><br>
        Sets the TYPE of the inheritor. The default value is dummy.
      </li>
      <br>
      <li>
        <code>attributes &lt;attribute&gt; [&lt;attribute&gt;] [...]</code><br>
        Space-separated list of attributes to be inherited.
      </li>
      <br>
      <li>
        <code>
          attributesExclude &lt;attribute&gt; [&lt;attribute&gt;] [...]
        </code><br>
        A space-separated list of attributes that are not inherited to these
        inheritors.
      </li>
      <br>
      <li>
        <code>autocreate 0</code><br>
        The archetype does not automatically inherit attributes to new devices,
        and inheritors are not created automatically for new relations.<br>
        The default value is 1.
      </li>
      <br>
      <li>
        <code>defined_by &lt;...&gt;</code><br>
        Auxiliary attribute to recognize by which archetype the inheritor was
        defined.
      </li>
      <br>
      <li>
        <code>delteAttributes 1</code><br>
        If an attribute is deleted in the archetype, it is also deleted for all
        inheritors.<br>
        The default value is 0.
      </li>
      <br>
      <li>
        <code>disable 1</code><br>
        No attributes are inherited and no inheritors are defined.
      </li>
      <br>
      <li>
        <code>initialize &lt;initialize&gt;</code><br>
        &lt;initialize&gt; can be specified as &lt;text&gt; or {perl code}.<br>
        The &lt;text&gt; or the return of {perl code} must be a list of FHEM
        commands separated by a semicolon (;). These are used to initialize the
        inheritors when they are defined.
      </li>
      <br>
      <li>
        <code>metaDEF &lt;metaDEF&gt;</code><br>
        &lt;metaDEF&gt; can be specified as &lt;text&gt; or {perl code} and
        describes the structure of the DEF for the inheritors.
      </li>
      <br>
      <li>
        <code>metaNAME &lt;metaNAME&gt;</code><br>
        &lt;metaNAME&gt; can be specified as &lt;text&gt; or {perl code} and
        describes the structure of the name for the inheritors.
      </li>
      <br>
      <li>
        <code><a href="#readingList">readingList</a></code>
      </li>
      <br>
      <li>
        <code>relations &lt;devspec&gt; [&lt;devspec&gt;] [...]</code><br>
        The relations describes all the relations that exist for this
        archetype.<br>
        See the section on
        <a href="#devspec">device specification</a>
        for details of the &lt;devspec&gt;.
      </li>
      <br>
      <li>
        <code><a href="#setList">setList</a></code>
      </li>
      <br>
      <li>
        <code>splitRooms 1</code><br>
        Returns every room seperatly for each relation in $room.
      </li>
      <br>
    </ul>
    <br>
    <a name="archetypeexamples"></a>
    <b>Examples</b>
    <ul>
      <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
        <u>The following sample codes can be imported via "Raw definition".</u>
      </a>
      <br>
      <br>
      <li>
        <b>
          All plots should be moved to the group "history":
        </b>
        <ul>
<pre>defmod SVG_archetype archetype TYPE=SVG
attr SVG_archetype group verlaufsdiagramm
attr SVG_archetype attributes group</pre>
        </ul>
      </li>
      <li>
        <b>
          In addition, a weblink should be created for all plots:
        </b>
        <ul>
<pre>defmod SVG_link_archetype archetype
attr SVG_link_archetype relations TYPE=SVG
attr SVG_link_archetype actualTYPE weblink
attr SVG_link_archetype metaNAME $relation\_link
attr SVG_link_archetype metaDEF link ?detail=$relation
attr SVG_link_archetype initialize attr $name room $room;;
attr SVG_link_archetype group verlaufsdiagramm
attr SVG_link_archetype attributes group</pre>
        </ul>
      </li>
    </ul>
  </ul>
</div>

=end html

=begin html_DE

<a name="archetype"></a>
<h3>archetype</h3>
( <a href="commandref.html#archetype">en</a> | de )
<div>
  <ul>
    Mit einem archetype werden Attribute auf Erben (inheritors), andere
    Ger&auml;te, &uuml;bertragen. Die Erben k&ouml;nnen, nach einem vorgegeben
    Muster im archetype und f&uuml;r Beziehungen (relations), eine bestimmte
    Gruppe von Ger&auml;ten, definiert werden.<br>
    <br>
    Hinweise:
    <ul>
      <li>
        <code>$name</code><br>
        Name des Erben
      </li><br>
      <li>
        <code>$room</code><br>
        Raum der Beziehung
      </li><br>
      <li>
        <code>$relation</code><br>
        Name der Beziehung
      </li><br>
      <li>
        <code>$SELF</code><br>
        Name des archetype
      </li>
    </ul>
    <br>
    <a name="archetypecommand"></a>
    <b>Befehle</b>
    <ul>
      <code>clean [check]</code><br>
      Definiert für alle Beziehungen aller archetype die Erben, vererbt für
      alle archetype die unter dem Attribut attributes angegeben Attribute auf
      alle Erben.<br>
      Wird optinal der Parameter "check" angegeben werden alle ausstehenden
      Attribute und Erben angezeigt.
    </ul>
    <br>
    <a name="archetypedefine"></a>
    <b>Define</b>
    <ul>
      <code>
        define &lt;name&gt; archetype [&lt;devspec&gt;] [&lt;devspec&gt;] [...]
      </code><br>
      In den &lt;devspec&gt; werden alle Erben beschrieben die es für dieses
      archetype gibt. Es sollte darauf geachtet werden, dass jeder Erbe nur
      einem archetype zugeordnet ist.<br>
      Wird keine &lt;devspec&gt; angegeben wird diese mit "defined_by=$SELF"
      gesetzt. Diese devspec wird auch immer &uuml;berpr&uuml;ft, selbst wenn
      sie nicht angegeben ist.<br>
      Siehe den Abschnitt &uuml;ber
      <a href="#devspec">Ger&auml;te-Spezifikation</a>
      f&uuml;r Details der &lt;devspec&gt;.<br>
      <br>
      <code>define &lt;name&gt; archetype derive attributes</code><br>
      Wird in der DEF "derive attributes" angegeben handelt es sich um ein
      besonderes archetype. Es leitet Attribute anhand eines Musters ab.<br>
      Das Muster wird mit den Attributen actual_.+ beschrieben.<br>
      Als Erben werden alle Ger&auml;te aufgelistet welche alle Pflicht-
      Attribute eines Musters besitzen.
    </ul>
    <br>
    <a name="archetypeset"></a>
    <b>Set</b>
    <ul>
      <li>
        <code>addToAttrList &lt;attribute&gt;</code><br>
        Der Befehl ist nur bei einem archetype mit der DEF "derive attributes"
        m&ouml;glich.<br>
        F&uuml;gt global einen Eintrag unter userattr hizu, sodass er f&uuml;r
        alle Ge&auml;r&auml;te zur Verf&uuml;gung steht.<br>
        Dies kann sinnvoll sein um den alias nach einem Muster abzuleiten.
      </li>
      <br>
      <li>
        <code>define inheritors</code><br>
        Definiert f&uuml;r alle Beziehungen einen Erben nach dem Muster:<br>
        <ul>
          <code>
            define &lt;metaNAME&gt; &lt;actualTYPE&gt; [&lt;metaDEF&gt;]
          </code>
        </ul>
        Wenn ein Erbe definiert wird, wird er, mit den unter dem Attribut
        initialize angegebenen Befehlen, initialisiert und ihm wir das Attribut
        defined_by mit dem Wert $SELF zugewiesen.<br>
        Die Beziehungen, metaNAME, actualTYPE und metaDEF werden in Attributen
        beschrieben.
      </li>
      <br>
      <li>
        <code>derive attributes</code><br>
        Der Befehl ist nur bei einem archetype mit der DEF "derive attributes"
        m&ouml;glich.<br>
        Leitet f&uuml;r alle Erben die unter dem Attribut attributes angegeben
        Attribute ab.
      </li>
      <br>
      <li>
        <code>inheritance</code><br>
        Vererbt die eigenen unter dem Attribut attributes angegeben Attribute
        auf alle Erben.
      </li>
      <br>
      <li>
        <code>initialize inheritors</code><br>
        F&uuml;hrt f&uuml;r alle Erben die unter dem Attribut initialize
        angegebenen Befehle aus.
      </li>
      <br>
      <li>
        <code>raw &lt;Befehl&gt;</code><br>
        F&uuml;hrt f&uuml;r alle Erben den Befehl aus.
      </li>
    </ul>
    <br>
    <a name="archetypeget"></a>
    <b>Get</b>
    <ul>
      <li>
        <code>inheritors</code><br>
        Listet alle Erben auf.
      </li>
      <br>
      <li>
        <code>relations</code><br>
        Listet alle Beziehungen auf.
      </li>
      <br>
      <li>
        <code>pending attributes</code><br>
        Listet f&uuml;r jeden Erben die unter dem Attribut attributes angegeben
        Attribute auf, die nicht mit den Attributen des archetype
        &uuml;bereinstimmen.
      </li>
      <br>
      <li>
        <code>pending inheritors</code><br>
        Listet alle Erben auf die aufgrund der Beziehungen noch definiert
        werden sollen.
      </li>
    </ul>
    <br>
    <a name="archetypeattr"></a>
    <b>Attribute</b>
    <ul>
      Hinweise:
      <ul>
        Alle Attribute die vererbt werden k&ouml;nnen, k&ouml;nnen vorab mit
        einem Modifikator versehen werden.
        <li>
          <code>attr archetype &lt;attribute&gt; undef:&lt;...&gt;</code><br>
          Wird <code>undef:</code> vorangestellt wird das Attribut nur vererbt,
          sofern der Erbe dieses Attribut noch nicht besitzt.
        </li><br>
        <li>
          <code>
            attr archetype &lt;attribute&gt;
            least[(&lt;Trennzeichen&gt;)]:&lt;...&gt;
          </code><br>
          Wird eine Liste vererbt kann mit dem voranstellen von
          <code>least[(&lt;Trennzeichen&gt;)]:</code>
          angegeben werden, dass diese Elemente mindestens vorhanden sein
          sollen.<br>
          Wird kein Trennzeichen angegeben wird das Leerzeichen als
          Trennzeichen verwendet.
        </li>
      </ul>
      <br>
      <li>
        <code>actual_&lt;attribute&gt; &lt;value&gt;</code><br>
        &lt;value&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden.<br>
        Wir das Attribut &lt;attribute&gt; vererbt, ersetz die R&uuml;ckgabe
        des actual_&lt;attribute&gt; Wert des Attributes.<br>
        Bei dem archetype mit der DEF "derive attributes" können Muster
        definiert werden.<br>
        Beispiel:
        <code>
          actual_alias %captionRoom|room%: %description%[ %index%][%suffix%]
        </code><br>
        Alle in % eingeschlossenen Ausdrücke sind Attribute. Eine Reihenfolge
        lässt sich durch | erreichen. Ist ein Ausdruck in [] eingeschlossen ist
        er optional.<br>
        Die Ausdrücke captionRoom, description, index und suffix sind hierbei
        durch addToAttrList hinzugefügte Attribute.<br>
      </li>
      <br>
      <li>
        <code>actualTYPE &lt;TYPE&gt;</code><br>
        Legt den TYPE des Erben fest. Der Standardwert ist dummy.
      </li>
      <br>
      <li>
        <code>attributes &lt;attribute&gt; [&lt;attribute&gt;] [...]</code><br>
        Leerzeichen-getrennte Liste der zu vererbenden Attribute.
      </li>
      <br>
      <li>
        <code>
          attributesExclude &lt;attribute&gt; [&lt;attribute&gt;] [...]
        </code><br>
        Leerzeichen-getrennte Liste von Attributen die nicht auf diesen Erben
        vererbt werden.
      </li>
      <br>
      <li>
        <code>autocreate 0</code><br>
        Durch das archetype werden Attribute auf neue devices nicht automatisch
        vererbt und Erben werden nicht automatisch für neue Beziehungen
        angelegt.<br>
        Der Standardwert ist 1.
      </li>
      <br>
      <li>
        <code>defined_by &lt;...&gt;</code><br>
        Hilfsattribut um zu erkennen, durch welchen archetype der Erbe
        definiert wurde.
      </li>
      <br>
      <li>
        <code>delteAttributes 1</code><br>
        Wird ein Attribut im archetype gelöscht, wird es auch bei allen Erben
        gelöscht.<br>
        Der Standardwert ist 0.
      </li>
      <br>
      <li>
        <code>disable 1</code><br>
        Es werden keine Attribute mehr vererbt und keine Erben definiert.
      </li>
      <br>
      <li>
        <code>initialize &lt;initialize&gt;</code><br>
        &lt;initialize&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden.<br>
        Der &lt;Text&gt; oder die R&uuml;ckgabe vom  {perl code} muss eine
        durch Semikolon (;) getrennte Liste von FHEM-Befehlen sein. Mit diesen
        werden die Erben initialisiert, wenn sie definiert werden.
      </li>
      <br>
      <li>
        <code>metaDEF &lt;metaDEF&gt;</code><br>
        &lt;metaDEF&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden und beschreibt den Aufbau der DEF f&uuml;r die Erben.
      </li>
      <br>
      <li>
        <code>metaNAME &lt;metaNAME&gt;</code><br>
        &lt;metaNAME&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden und beschreibt den Aufbau des Namen f&uuml;r die Erben.
      </li>
      <br>
      <li>
        <code><a href="#readingList">readingList</a></code>
      </li>
      <br>
      <li>
        <code>relations &lt;devspec&gt; [&lt;devspec&gt;] [...]</code><br>
        In den &lt;relations&gt; werden alle Beziehungen beschrieben die es für
        dieses archetype gibt.<br>
        Siehe den Abschnitt &uuml;ber
        <a href="#devspec">Ger&auml;te-Spezifikation</a>
        f&uuml;r Details der &lt;devspec&gt;.
      </li>
      <br>
      <li>
        <code><a href="#setList">setList</a></code>
      </li>
      <br>
      <li>
        <code>splitRooms 1</code><br>
        Gibt für jede Beziehung jeden Raum separat in $room zurück.
      </li>
      <br>
    </ul>
    <br>
    <a name="archetypeexamples"></a>
    <b>Beispiele</b>
    <ul>
      <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
        <u>
          Die folgenden beispiel Codes k&ouml;nnen per "Raw defnition"
          importiert werden.
        </u>
      </a>
      <br>
      <br>
      <li>
        <b>
          Es sollen alle Plots in die Gruppe "verlaufsdiagramm" verschoben
          werden:
        </b>
        <br>
<pre>defmod SVG_archetype archetype TYPE=SVG
attr SVG_archetype group verlaufsdiagramm
attr SVG_archetype attributes group</pre>
      </li>
      <br>
      <li>
        <b>
          Zus&auml;tzlich soll f&uuml;r alle Plots ein weblink angelegt werden:
        </b>
        <br>
<pre>defmod SVG_link_archetype archetype
attr SVG_link_archetype relations TYPE=SVG
attr SVG_link_archetype actualTYPE weblink
attr SVG_link_archetype metaNAME $relation\_link
attr SVG_link_archetype metaDEF link ?detail=$relation
attr SVG_link_archetype initialize attr $name room $room;;
attr SVG_link_archetype group verlaufsdiagramm
attr SVG_link_archetype attributes group</pre>
      </li>
    </ul>
  </ul>
</div>

=end html_DE
=cut

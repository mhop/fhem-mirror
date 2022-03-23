# Id ##########################################################################
# $Id$
#
# copyright ###################################################################
#
# 98_archetype.pm
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

=pod
defmod acFHEMapp archetype LichtAussenTerrasse
attr acFHEMapp userattr actual_appOptions
attr acFHEMapp actual_appOptions {genericDeviceType2appOption($name)}
attr acFHEMapp attributes appOptions
attr acFHEMapp splitRooms 1
=cut

package archetype; ##no critic qw(Package)
use strict;
use warnings;
use GPUtils qw(GP_Import);
use JSON (); # qw(decode_json encode_json);
use utf8;
use List::Util 1.45 qw(max min uniq);
#use FHEM::Meta;

sub ::archetype_Initialize { goto &Initialize }

BEGIN {

  GP_Import( qw(
    addToAttrList 
    addToDevAttrList
    readingsSingleUpdate
    Log3
    defs attr cmds modules
    DAYSECONDS HOURSECONDS MINUTESECONDS
    init_done
    InternalTimer
    RemoveInternalTimer
    CommandAttr
    CommandDeleteAttr
    readingFnAttributes
    IsDisabled IsDevice
    AttrVal
    InternalVal
    ReadingsVal
    devspec2array
    AnalyzeCommandChain
    AnalyzeCommand
    CommandDefMod
    CommandDelete
    EvalSpecials
    AnalyzePerlCommand
    perlSyntaxCheck
    evalStateFormat
    getAllAttr
    setNotifyDev
    deviceEvents
  ) )
};


# initialize ##################################################################
sub Initialize {
  my $hash = shift // return;
  my $TYPE = 'archetype';

  $hash->{DefFn}      = \&Define;
  $hash->{UndefFn}    = \&Undef;
  $hash->{SetFn}      = \&Set;
  $hash->{GetFn}      = \&Get;
  $hash->{AttrFn}     = \&Attr;
  $hash->{NotifyFn}   = \&Notify;

  $hash->{AttrList} = 
      "actual_.+ "
    . "actualTYPE "
    . "attributes "
    . "autocreate:1,0 "
    . "deleteAttributes:0,1 "
    . "disable:0,1 "
    . "initialize:textField-long "
    . "metaDEF:textField-long metaNAME:textField-long "
    . "readingList setList:textField-long "
    . "relations "
    . "splitRooms:0,1 " #useEval:0,1 "
    . $readingFnAttributes
  ;

  addToAttrList('attributesExclude','archetype');

  my %hash = (
    Fn  => 'CommandClean',
    Hlp => 'archetype [clean or check], set attributes according to settings in archetypes'
  );
  $cmds{archetype} = \%hash;
  return;
}


# regular Fn ##################################################################
sub Define {
  my $hash = shift // return;
  my $def  = shift // return;
  #return $@ if !FHEM::Meta::SetInternals($hash);
  my ($SELF, $TYPE, $DEF) = split m{\s+}xms, $def, 3;

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Define");

  if($hash->{DEF} eq 'derive attributes'){
    #https://forum.fhem.de/index.php/topic,53402.msg452468.html#msg452468  - 'derive attributes' als spezielle DEF implementieren um den alias nach dem Muster <room>: <description> [<index>] [<suffix>] abzuleiten
    #https://forum.fhem.de/index.php/topic,53402.msg453030.html#msg453030 - für ein archetype mit der DEF "derive attributes" die Befehle "set <archetype> derive attributes" und "get <archetype> pending attributes" implementieren
    #- Muster für derive attributes im archetype konfigurierbar machen
    my $derive_attributes = $modules{$TYPE}{derive_attributes};

    return(
        "$TYPE for deriving attributes already definded as "
      . "$derive_attributes->{NAME}"
    ) if $derive_attributes;

    $modules{$TYPE}{derive_attributes} = $hash;
  }

  $hash->{DEF} = "defined_by=$SELF" if !$DEF;
  setNotifyDev($hash,'global');
  #$hash->{NOTIFYDEV} = 'global';
  if ( !IsDisabled($SELF) ) {
    readingsSingleUpdate($hash, 'state', 'active', 0);
    evalStateFormat($hash);
  }

  return $init_done ? firstInit($hash) : InternalTimer(time+100, \&firstInit, $hash );
}


sub firstInit {
    my $hash = shift // return;
    my $name = $hash->{NAME};
    for (devspec2array('defined_by=.+')) {
        addToDevAttrList($_, 'defined_by','archetype');
    }
    return;
}


sub Undef {
  my $hash = shift // return;
  my $SELF = shift // return;
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Undef");

  delete $modules{$TYPE}{derive_attributes}
    if $hash->{DEF} eq 'derive attributes';

  return;
}

sub Set { #($@)
  my $hash = shift // return;
  my $SELF = shift // return;
  my $argument = shift // return '"set <archetype>" needs at least one argument';
  my @arguments = @_;
  
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Set");

  my $value = @arguments ? join q{ }, @arguments : undef;
  my %archetype_sets;

  if ( $hash->{DEF} eq 'derive attributes' ) {
    %archetype_sets = (
        addToAttrList => 'addToAttrList:textField'
      , derive => 'derive:attributes'
    );
  }
  else{
    %archetype_sets = (
       define => 'define:inheritors',
       inheritance => 'inheritance:noArg',
       initialize => 'initialize:inheritors',
       raw => 'raw:textField'
    );
    my $inheritors = join q{,}, archetype_devspec($SELF);
    if ($inheritors) { $archetype_sets{import} = "import:select,$inheritors" };
    $archetype_sets{(split m{:}x, $_)[0]} = $_
      for ( split m{[\s]+}x, AttrVal($SELF, 'setList', '') );
  }

  return(
      "Unknown argument $argument, choose one of "
    . join q{ }, values %archetype_sets
  ) if !exists $archetype_sets{$argument};

  if($argument eq 'addToAttrList'){
    return addToAttrList($value);
  }
  if($argument eq "derive" && $value eq "attributes"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument $value");

    derive_attributes($SELF);

    Log3($SELF, 3, "$TYPE ($SELF) - $argument $value done");
    return;
  }

  if($argument eq "define" && $value eq "inheritors"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument $value");

    define_inheritors($SELF);

    Log3($SELF, 3, "$TYPE ($SELF) - $argument $value done");
    return;
  }

  if($argument eq "inheritance"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument inheritors");

    _inheritance($SELF);
    return;
  }

  if($argument eq "initialize" && $value eq "inheritors"){
    Log3($SELF, 3, "$TYPE ($SELF) - starting $argument $value");

    define_inheritors($SELF, $argument);

    return Log3($SELF, 3, "$TYPE ($SELF) - $argument $value done");
  }

  if($argument eq "raw" && $value){
    (my $command, $value) = split m{[\s]+}x, $value, 2;

    if ( !$value ) {
        return qq("set $TYPE $argument" needs at least one command and one argument);
    }

    Log3($SELF, 3, "$TYPE ($SELF) - $command <inheritors> $value");

    #fhem("$command " . join(",", archetype_devspec($SELF)) . " $value");
    my $targets = join q{,}, archetype_devspec($SELF);
    return if !$targets;
    return AnalyzeCommandChain($hash, "$command $targets $value");
  }
  
  if($argument eq 'import' && $value){
    $hash->{'.importing'} = 1;
    return qq("set $TYPE $argument" requires an existing device as argument)
      if !$value || !defined $defs{$value};

    my @toImport = split m{[\s,]+}x, AttrVal($SELF, 'attributes', getAllAttr($value));
    for (@toImport) {
        $_ = (split m{:}x, $_, 2)[0];
    }
    my $ownlist = AttrVal($SELF, 'attributes', undef);
    my @newlist;
    
    for my $import ( @toImport ) {
        next if $import =~ m{\A[.]}x; # no hidden attributes!
        my $cont = AttrVal($value, $import, undef);
        next if !$cont;
        push @newlist, $import;
        $cont = $cont =~ m{\A\{.*\}\z}xms ? "undef,Perl:$cont" : "undef:$cont";
        CommandAttr(undef, "$SELF actual_$import $cont");
    }
    if (!$ownlist) {
        $ownlist = join q{ }, @newlist;
        CommandAttr(undef, "$SELF attributes $ownlist");
    }
    delete $hash->{'.importing'};
    return;
  }
  
  #else{
    my @readingList = split(/[\s]+/, AttrVal($SELF, "readingList", ""));

    if( @readingList && grep { m/\b$argument\b/ } @readingList ){
      Log3($SELF, 3, "$TYPE set $SELF $argument $value");

      readingsSingleUpdate($hash, $argument, $value, 1);
    }
    else{
      Log3($SELF, 3, "$TYPE set $SELF $argument $value");

      readingsSingleUpdate($hash, "state", "$argument $value", 1);
    }
  #}

  return;
}

sub Get {
  #($@) my ($hash, @arguments) = @_;
  my $hash = shift // return;
  my $SELF = shift // return;
  my $argument = shift // return '"get <archetype>" needs at least one argument';
  my @arguments = @_;

  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Get");

  my $value = @arguments ? join q{ }, @arguments : undef;
  my $derive_attributes = $hash->{DEF} eq 'derive attributes';
  my %archetype_gets;

  if($derive_attributes){
    %archetype_gets = (
      inheritors => 'inheritors:noArg',
      pending    => 'pending:attributes'
      );
  }else{
    %archetype_gets = (
      inheritors => 'inheritors:noArg',
      pending    => 'pending:attributes,inheritors',
      relations  => 'relations:noArg'
    );
  }

  return(
      "Unknown argument $argument, choose one of "
    . join q{ }, values %archetype_gets
  ) if !exists $archetype_gets{$argument};

  return "$SELF is disabled" if IsDisabled($SELF);

  if ($argument =~ m{\A(inheritors|relations)\z}xms){
    Log3($SELF, 3, "$TYPE ($SELF) - starting request $argument");

    my @devspec;

    if($derive_attributes){
      @devspec = archetype_devspec($SELF, 'specials');
    }
    elsif($argument eq 'relations'){
      @devspec = archetype_devspec($SELF, 'relations');
    }
    else{
      @devspec = archetype_devspec($SELF);
    }

    Log3($SELF, 3, "$TYPE ($SELF) - request $argument done");

    return @devspec ? join "\n", @devspec : "no $argument defined";
  }
  if($argument eq 'pending'){
    Log3($SELF, 3, "$TYPE ($SELF) - starting request $argument $value");

    my @ret;

    if($value eq 'attributes'){
      my @attributes = sort(split(/[\s]+/, AttrVal($SELF, "attributes", "")));

      if($derive_attributes){
        @ret = derive_attributes($SELF, 1);
      }
      else{
        for my $ds (archetype_devspec($SELF)){
          for my $attribute (@attributes){
            my $desired = _get_desired($SELF, $attribute, $ds);
              #AttrVal(
              #  $SELF, "actual_$attribute", AttrVal($SELF, $attribute, "")
              #);

            next if !$desired || $desired eq '';

            push @ret, _attrCheck($SELF, $ds, $attribute, $desired, 1);
          }
        }
      }
    }
    elsif($value eq 'inheritors'){
      @ret = define_inheritors($SELF, 0, 1);
    }

    Log3($SELF, 3, "$TYPE ($SELF) - request $argument $value done");

    return @ret ? join "\n", @ret : "no $value $argument"; #soft form required
  }
  return "Unknown argument $value, choose one of "
         . join q{ }, split m{,}x, (split m{:}x, $archetype_gets{$argument})[1];
}

sub _get_desired {
    my $SELF      = shift // return; #Beta-User: only first argument seem to be mandatory
    my $attribute = shift // return;
    my $devspec   = shift;

    my $desired = AttrVal($devspec, "actual_$attribute", undef); #compability layer
    return $desired if $desired;

    $desired = AttrVal( $SELF, "actual_$attribute", AttrVal($SELF, $attribute, ''));

    my @filterattr = grep { $_ =~ m{\Aactual_${attribute}_}x } split m{\s+}x, getAllAttr($SELF);
    return $desired if !@filterattr;
    for my $tocheck (@filterattr) {
        my ($filter, $desired2) = split m{\s+}, AttrVal($SELF,$tocheck,'');
        #Debug("FILTER: $filter");
        next if !devspec2array("$devspec:FILTER=$filter");
        #Debug("FILTERed: $desired2");
        return $desired2;
    }
    return $desired;
}

sub Attr {
  my ($cmd, $SELF, $attribute, $value) = @_;

  my $hash = $defs{$SELF};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Attr");

  if( $attribute eq 'disable' ) {
    if ($cmd eq 'del' || $value eq '0') {
        readingsSingleUpdate($hash, 'state', 'active', 0);
        evalStateFormat($hash);
        Log3($SELF, 3, "$TYPE ($SELF) - starting inheritance inheritors");
        return _inheritance($SELF);
    }
    readingsSingleUpdate($hash, 'state', 'disabled', 0);
    evalStateFormat($hash);
    return;
  }

  return if !$init_done;

  if($attribute =~ /^actual_/) {
    if ($cmd eq 'set') {
        addToDevAttrList($SELF, $attribute, 'archetype');
        return ;
    }
    # delete case
    my %values =
        map{$_, 0} split(" ", AttrVal($SELF, "userattr", ""));
      delete $values{$attribute};
      my $values = join q{ }, sort keys %values;

      if($values eq ''){
        CommandDeleteAttr(undef, "$SELF userattr");
      }
      else{
        #$attr{$SELF}{userattr} = $values;
        CommandAttr($hash, "$SELF -silent userattr $values");
      }
  }

  return if IsDisabled($SELF);

  my @attributes = AttrVal($SELF, "attributes", "");

  if(
    $cmd eq 'del'
    && $attribute ne 'disable'
    && AttrVal($SELF, 'deleteAttributes', 0) == 1
  ){
    CommandDeleteAttr(
        undef
      , join q{,}, archetype_devspec($SELF)
      . ":FILTER=a:attributesExclude!=.*$attribute.* $attribute"
    );
  }
  elsif($cmd eq "del" && $attribute ne "stateFormat"){
    readingsSingleUpdate($hash, 'state', 'active', 0);
    evalStateFormat($hash);
  }
  elsif(
    $cmd eq "set"
    && (
      grep { m/\b$attribute\b/ } @attributes
      || $attribute =~ /^actual_(.+)$/ && grep { m/\b$1\b/ } @attributes
    )
  ){
    $attribute = $1 if($1);
    return if $hash->{'.importing'};
    Log3(
      $SELF, 3
      , "$TYPE ($SELF) - "
      . "starting inheritance attribute \"$attribute\" to inheritors"
    );

    return _inheritance($SELF, undef, $attribute);
  }
  
  if($attribute eq 'attributes' && $cmd eq 'set'){
    if($value =~ /actual_/ && $value !~ /userattr/){
      $value = "userattr $value";
      $_[3] = $value;
      $attr{$SELF}{$attribute} = $value;
      #CommandAttr($hash, "$SELF -silent $attribute $value");
    } else {
        my $posAttr = getAllAttr($SELF);
        for my $elem ( split m{ }, $value ) {
            addToDevAttrList($SELF, "actual_$elem") if $posAttr !~ m{\b$elem(?:[\b:\s]|\z)}xms;
        }
    }

    return if $hash->{'.importing'} && $cmd eq 'set';

    Log3($SELF, 3, "$TYPE ($SELF) - starting inheritance inheritors");
    _inheritance($SELF, undef, $value);
  }
  return;
}

sub Notify {
  my $hash     = shift // return; 
  my $dev_hash = shift // return;
  my $SELF = $hash->{NAME};
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_Notify");

  return if IsDisabled($SELF);
  return if !AttrVal($SELF, 'autocreate', 1);

  my @events = @{deviceEvents($dev_hash, 1)};

  return if !@events;

  for my $event (@events){
    next if !$event;

    Log3($SELF, 4, "$TYPE ($SELF) - triggered by event: \"$event\"");

    my ($argument, $name, $attr, $value) = split m{[\s]+}x, $event, 4;

    return if !$name;

    if( $argument eq 'DEFINED' && grep { m/\b$name\b/ } archetype_devspec($SELF)) {
      Log3($SELF, 3, "$TYPE ($SELF) - starting inheritance $name");

      _inheritance($SELF, $name);
    }
    elsif(
      $argument eq 'DEFINED'
      && grep { m/\b$name\b/ } archetype_devspec($SELF, "relations")
    ){
      Log3($SELF, 3, "$TYPE ($SELF) - starting define inheritors");

      define_inheritors($SELF, undef, undef, $name);

      Log3($SELF, 3, "$TYPE ($SELF) - define inheritors done");
    }
    elsif(
      $hash->{DEF} eq "derive attributes"
      && $argument eq "ATTR"
      && grep { m/\b$name\b/ } archetype_devspec($SELF, "specials")
    ){
      for my $attribute ( split m{ }, AttrVal($SELF, 'attributes', '') ) {
        my @specials = archetype_evalSpecials(
          undef, AttrVal($SELF, "actual_$attribute", ""), "all"
        );

        if ( grep { m/\b$attr\b/ } @specials ){
          derive_attributes($SELF, undef, $name, $attribute);

          last;
        }
      }
    }
  }

  return;
}

# module Fn ###################################################################
sub archetype_AnalyzeCommand {
  # Wird ausgefuehrt um metaNAME und metaDEF auszuwerten.
  #($$$$$) my ($cmd, $name, $room, $relation, $SELF) = @_;
  my $cmd      = shift // return;
  my $name     = shift;
  my $room     = shift;
  my $relation = shift;
  my $SELF     = shift;

  my $hash; my $TYPE;
  if ( $SELF ) {
    $hash = $defs{$SELF};
    $TYPE = $hash->{TYPE};
    Log3($SELF, 5, "$TYPE ($SELF) - call archetype_AnalyzeCommand");
  }

  my %specials = (
         '%name'     => $name,
         '%room'     => $room,
         '%relation' => $relation
  );
  $specials{'%SELF'} = $SELF if $SELF;
  $specials{'%TYPE'} = $TYPE if $TYPE;

  # Falls es sich nicht um einen durch {} gekennzeichneten Perl Befehl
  # handelt, werden alle Anfuehrungszeichen maskiert und der Befehl in
  # Anfuehrungszeichen gesetzt um eine korrekte Auswertung zu gewaehrleisten.
  if ($cmd !~ m/^\{.*\}$/){
    $cmd =~ s/"/\\"/g;
    $cmd = "\"$cmd\"";
    #Debug("no Perl in aAC, starting with $cmd");
    #$cmd  = EvalSpecials($cmd, %specials);
    $cmd = eval($cmd);# if AttrVal($SELF,'useEval',0); #seems we don't have much other opportunities for simple text replacements...?
    
    #Debug("evaluated to $cmd");
=pod
    for my $special ( sort { length $b <=> length $a } keys %specials) {
        last if AttrVal($SELF,'useEval',0);
        my $short = substr $special, 1 - length $special;
        Log3($SELF, 3, "short is $short, special was $special");
        $cmd =~ s/\$$short/$specials{$special}/g;
    }
=cut
    return $cmd;
  }


  #Debug("cmd in aAC oiginally was $cmd");
  #$cmd = eval($cmd);
  $cmd = "$cmd";
  #Debug("cmd in aAC was $cmd");
  $cmd  = EvalSpecials($cmd, %specials);
  #Debug("cmd now is $cmd");

  $cmd = AnalyzeCommandChain( $hash, $cmd );
  #Debug("cmd via ACC now is $cmd");
  return $cmd;
  # CMD ausführen
  #$cmd = eval($cmd);

  #return $cmd;
}

sub _attrCheck {
  # Wird fuer jedes vererbende Attribut und fuer jeden Erben ausgefuehrt um zu
  # pruefen ob das Attribut den vorgaben entspricht.
  #($$$$;$) my ($SELF, $name, $attribute, $desired, $check) = @_;
  my $SELF      = shift // return;
  my $name      = shift // return;
  my $attribute = shift // return;
  my $desired   = shift // return; #Beta-User: all arguments seem to be mandatory
  my $check     = shift;

  my $hash = $defs{$SELF} // return;
  my $TYPE = $hash->{TYPE};
  my $actual = AttrVal($name, $attribute, '');

  Log3($SELF, 5, "$TYPE ($SELF) - call _attrCheck");

  return if AttrVal($name, 'attributesExclude', '') =~ m{$attribute};

  #if ( AttrVal($SELF, "actual_$attribute", undef ) ) {
  if ( getAllAttr($SELF) =~ m{\bactual_$attribute(?:_.+|[\b:\s]|\z)}xms ) {
    my %specials = (
         '%SELF'      => $SELF,
         '%name'      => $name,
         '%TYPE'      => $TYPE,
         '%attribute' => $attribute
    );

    #$desired = eval($desired) if $desired =~ m{\A\{.*\}\z};
    if ( $desired =~ m{\A\{.*\}\z} ) {
        $desired  = EvalSpecials($desired, %specials);
        # CMD ausführen
        $desired = AnalyzePerlCommand( $hash, $desired );
    }

    $desired = archetype_evalSpecials($name, $desired) if $desired =~ m/%/;
  }

  if ( $desired =~ m{\Aleast(\((.*)\))?:(.+)} ){
    my $seperator = $2 ? $2 : " ";
    my %values =
      map{$_, 0} (split( $seperator, $actual), split $seperator, $3 );
    $desired = join $seperator, sort keys %values;
  }
  elsif( $desired =~ m{\Aundef} ){
    return if AttrVal($name, $attribute, undef);
    $desired = ( split m{:}x, $desired, 2)[1];
  }
  elsif( $desired =~ m{\APerl:} ){
    $desired = ( split m{:}x, $desired, 2)[1];
  }

  return if !$desired;

  return if $actual eq $desired;

  if ( $check ) {
      my $ret;
      $ret .= "-attr $name $attribute $actual\n" if $actual ne '';
      $ret .= "+attr $name $attribute $desired";

      return $ret;
  }

    #fhem("attr $name $attribute $desired");
    CommandAttr(undef, "$name $attribute $desired");

  return;
}

sub _DEFcheck {
  #($$;$) my ($name, $type, $expected) = @_;
  my $name     = shift // return;
  my $type     = shift // return; 
  my $expected = shift;

  if($expected && $expected ne InternalVal($name, "DEF", " ")){
    CommandDefMod(undef, "$name $type $expected");
  } else {
    CommandDefMod(undef, "$name $type") if !IsDevice($name, $type);
    return 1;
  }
  return;
}

sub define_inheritors {
  #($;$$$) my ($SELF, $init, $check, $relation) = @_;
  my $SELF     = shift // return; #Beta-User: only first argument seems to be mandatory
  my $init     = shift;
  my $check    = shift;
  my $relation = shift;

  my $hash = $defs{$SELF} // return;

  return if IsDisabled($SELF);

  my @relations;
  if ( $relation ) {
      $relations[0] = $relation;
  } else {
      @relations = archetype_devspec($SELF, 'relations');
      return if !@relations;
  }

  my @ret;
  my $TYPE = AttrVal($SELF, 'actualTYPE', 'dummy');
  my $initialize = AttrVal($SELF, 'initialize', undef);
  #Log3($SELF, 3, "$TYPE ($SELF) - call archetype_devspec");

  if ( $initialize && $initialize !~ /^\{.*\}$/s ) {
    $initialize =~ s/\"/\\"/g;
    $initialize = "\"$initialize\"";
  }

  for my $relative (@relations){
    my @rooms;
    push @rooms, AttrVal($relative, 'room', 'Unsorted');
    @rooms = split q{,}, $rooms[0] if AttrVal($SELF, 'splitRooms', 0);
    for my $room ( @rooms ) {
      my $name = archetype_AnalyzeCommand(
        AttrVal($SELF, 'metaNAME', ''), undef, $room, $relative, $SELF
      );
      next if !$name;
      my $DEF = archetype_AnalyzeCommand(
        AttrVal($SELF, 'metaDEF', ' '), $name, $room, $relative, $SELF
      );
      my $defined = IsDevice($name, $TYPE) ? 1 : 0;

      if ( !$defined || InternalVal($name, 'DEF', '') ne $DEF) {
      #unless($defined && InternalVal($name, "DEF", " ") eq $DEF){
        if($check){
          push @ret, $name;
          next;
        }
        if (!$init){
          _DEFcheck($name, $TYPE, $DEF); #my $new = 
          #_inheritance($SELF, $name) if $new; #new!
          addToDevAttrList($name, 'defined_by', 'archetype');
          CommandAttr($hash, "$name defined_by $SELF");
        }

      }

      next if $check;

      #fhem(eval($initialize)) if( ##Beta-User: fhem/eval
      if ( $initialize
        && IsDevice($name, $TYPE)
        && (!$defined || $init)
        ) {
            $initialize = eval($initialize) if AttrVal($SELF,'useEval',0); #for simple text replacement....
            #Debug("init after eval replacement: $initialize");
            #fhem(eval($initialize))
            my %specials = (
                '%SELF'     => $SELF,
                '%name'     => $name,
                '%TYPE'     => $TYPE,
                '%room'     => $room,
                '%relation' => $relative
                );
=pod            for my $special ( sort { length $b <=> length $a } keys %specials) {
                last if AttrVal($SELF,'useEval',0);
                my $short = substr $special, 1 - length $special;
                $initialize =~ s/\$$short/$specials{$special}/g;
            }
=cut

            $initialize  = EvalSpecials($initialize, %specials);
            #Debug("init now is: $initialize");
      
            # CMD ausführen
            AnalyzeCommandChain( $hash, $initialize );
        }

      _inheritance($SELF, $name) if !$init;
    }
  }

  if ($check) {
    my %ret = map{$_, 1} @ret;
    my @slist = sort keys %ret;
    return @slist; #Beta-User: use uniq instead?
  }

  return;
}

sub derive_attributes {
  #($;$$$) my ($SELF, $check, $name, $attribute) = @_;
  my $SELF      = shift // return; #Beta-User: only first argument seem to be mandatory
  my $check     = shift;
  my $name      = shift;
  my $attribute = shift;

  my $hash = $defs{$SELF} // return;
  my @ret;
  my @devspecs = $name ? $name : archetype_devspec($SELF, 'specials');
  my @attributes =
    $attribute ?
      $attribute
    : sort split m{[\s]+}xms, AttrVal($SELF, 'attributes', '')
  ;

  for my $ds (@devspecs){
    for my $attribute (@attributes){
      my $desired = _get_desired($SELF, $attribute, $ds);
      #AttrVal(
      #  $_, "actual_$attribute", AttrVal($SELF, "actual_$attribute", "")
      #);

      next if $desired eq '';

      if($check){
        push(@ret, _attrCheck($SELF, $ds, $attribute, $desired, 1));

        next;
      }

      _attrCheck($SELF, $ds, $attribute, $desired);
    }
  }

  return(@ret);
}

sub archetype_devspec {
  #($;$) my ($SELF, $devspecs) = @_;
  my $SELF     = shift // return;
  my $devspecs = shift;

  my $hash = $defs{$SELF} // return;
  my $TYPE = $hash->{TYPE};

  Log3($SELF, 5, "$TYPE ($SELF) - call archetype_devspec");

  if ( !$devspecs ) {
    $devspecs = InternalVal($SELF, 'DEF', '');
  }
  elsif ( $devspecs eq 'relations' ) {
    $devspecs = AttrVal($SELF, 'relations', '');
  }
  elsif ( $devspecs eq 'specials' ) {
    $devspecs = '';
    for my $attribute (split m{ }, AttrVal($SELF, 'attributes', '')){
      no warnings;

      $devspecs .= " a:actual_$attribute=.+";
      my $actual_attribute = AttrVal($SELF, "actual_$attribute", "");

      if($actual_attribute =~ m/^\{.*\}$/){
        $devspecs .= " .+";
      }
      else{
        my $mandatory = join q{ }, archetype_evalSpecials(
          $SELF, $actual_attribute, 'mandatory'
        );

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
  push @devspec, devspec2array($_) for (split m{[\s]+}x, $devspecs);

  my %devspec = map{$_, 1}@devspec;
  delete $devspec{$SELF};
  @devspec = sort keys %devspec;

  return @devspec;
}

sub archetype_evalSpecials {
  #($$;$) my ($name, $pattern, $get) = @_;
  my $name    = shift // return;
  my $pattern = shift // return;
  my $get     = shift;

  my $value;

  if ( $get ) {
    $pattern =~ s/\[[^]]*\]//g if $get eq 'mandatory';
    return(($pattern =~ m/%(\S+)%/g));
  }

  for my $part (split(/\[/, $pattern)){
    for my $special ($part =~ m/%(\S+)%/g){
      for (split("\\|", $special)){
        my $AttrVal = AttrVal($name, $_, undef);
        $AttrVal = archetype_AnalyzeCommand(
          $AttrVal, $name, AttrVal($name, 'room', undef), undef, undef
        ) if $AttrVal;

        if($AttrVal){
          $part =~ s/\Q%$special%\E/$AttrVal/;

          last;
        }
      }
    }

    ($part, my $optional) = ($part =~ m/([^\]]+)(\])?$/);

    #return unless($optional || $part !~ m/%\S+%/);
    return if !$optional && $part =~ m/%\S+%/;

    #$value .= $part unless($optional && $part =~ m/%\S+%/);
    $value .= $part if !$optional || $part !~ m/%\S+%/;
  }

  return $value;
}

sub _inheritance { #($;$$)
  my $SELF     = shift // return;
  my @devices  = shift // archetype_devspec($SELF);
  my $attrlist = shift // AttrVal($SELF, 'attributes', '');

  my $hash = $defs{$SELF} // return;
  my $TYPE = $hash->{TYPE};

  for my $attribute ( split m{[\s]+}xms, $attrlist ){
    for my $ds (@devices) {
        my $value = _get_desired($SELF, $attribute, $ds);
        #AttrVal($SELF, "actual_$attribute", AttrVal($SELF, $attribute, ""));

        next if !$value || $value eq '';

        _attrCheck($SELF, $ds, $attribute, $value); #    for (@devices);
    }
  }

  Log3($SELF, 3, "$TYPE ($SELF) - inheritance inheritors done")
    if(@devices > 1);
  Log3($SELF, 3, "$TYPE ($SELF) - inheritance @devices done")
    if(@devices == 1);

  return;
}

# command Fn ##################################################################
sub CommandClean {
  #($$) my ($client_hash, $arguments) = @_;
  my $client_hash = shift // return;
  my $arguments   = shift // return;

  my @archetypes = devspec2array('TYPE=archetype');
  my (@pendingAttributes, @pendingInheritors);
  my %pendingAttributes;

  return 'command archetype needs either <clean> or <check> as arguments' if !$arguments || $arguments ne 'clean' && $arguments ne 'check';

  if ( $arguments eq 'check' ){
    for my $SELF (@archetypes){
      my $ret = archetype_Get($defs{$SELF}, $SELF, "pending", "attributes");

      next if $ret =~ m{no attributes pending|Unknown argument pending|is disabled};

      for my $pending ( split m{\n}x, $ret ){
        my ($sign, $name, $attribute, $value) = split q{ }, $pending, 4;
        $sign =~ s/^\+//;
        $pendingAttributes{$pending} = "$name $attribute $sign $value";
      }
    }

    for my $SELF (@archetypes){
      my $ret = archetype_Get($defs{$SELF}, $SELF, "pending", "inheritors");

      push @pendingInheritors, $ret if $ret !~ m{no inheritors pending|Unknown argument pending|is disabled};
    }

    @pendingAttributes =
      sort { lc $pendingAttributes{$a} cmp lc $pendingAttributes{$b} }
      keys %pendingAttributes
    ;
    @pendingInheritors = sort @pendingInheritors;

    return(
        (@pendingAttributes ?
           "pending attributes:\n" . join "\n", @pendingAttributes
         : 'no attributes pending'
        )
      . "\n\n"
      . (@pendingInheritors ?
           'pending inheritors:\n' . join "\n", @pendingInheritors
         : 'no inheritors pending'
        )
    );
  }

  #fhem(
  AnalyzeCommandChain( undef,
      'set TYPE=archetype:FILTER=DEF!=derive.attributes define inheritors;'
    . 'set TYPE=archetype:FILTER=DEF!=derive.attributes inheritance;'
    . 'set TYPE=archetype:FILTER=DEF=derive.attributes derive attributes;'
  );

  return 'clean done'
         . "\n\n"
         . CommandClean($client_hash, 'check');
}

1;

__END__

# commandref ##################################################################
=pod

statistic: 04.2.2022: # installations: 13, # defines: 113

=item helper
=item summary    inheritance attributes and defines devices
=item summary_DE vererbt Attribute und definiert Geräte
=encoding utf8

=begin html

<a id="archetype"></a>
<h3>archetype</h3>
<div>
  <ul>
    With an archetype, attributes are transferred to other devices, so called inheritors.
    The inheritors can be defined according to a given pattern in the archetype
    and for relations, a certain group of devices.<br>
    <br>
    As this is rather an abstract description that only may be self-explaining for those 
    beeing familiar with concepts of <a href="https://en.wikipedia.org/wiki/Inheritance_(object-oriented_programming)">inheritence in programming</a>, 
    here's some examples how <i>archetype</i> can be used:
    <ul>
      <li>transfer attributes (and their values) from an <i>archetype</i> to arbitrary other devices and/or</li>
      <li>new devices (as well within the <a href="#autocreate">autocreate</a> process) can be 
      <ul>
        <li>supplied with define and attr commands derived according to patterns</li>
        <li>supplied with default attribute values</li>
        <li>initialized with default attribute values and/or Reading-values</li>
      </ul></li>
      <li>indicate and/or correct differences between actual and desired attribute values</li>
    </ul><br>
    
    <br>
    These variables may be used within inheritence instructions:
    <ul>
      <li><code>$name</code> name of the inheritor</li>
      <li><code>$room</code> room of the inheritor</li>
      <li><code>$relation</code> name of the relation</li>
      <li><code>$SELF</code> name of the archetype</li>
    </ul>
    <br>
    Note: FHEM commands <a href="#setdefaultattr">setdefaultattr</a> and <a href="#template">template</a>
    provide partly similar functionality.
    <a id="archetype-command"></a>
    <h4>Commands</h4>
    <ul>
    <a id="archetype-command-archetype"></a>
      <code>archetype &lt;clean or check&gt;</code><br>
      "clean" will define all inheritors for all relations and process all inheritances to 
      all inheritors with the attributes specified under the attribute attribute.<br>
      If the "check" parameter is specified, all outstanding actions are displayed.
    </ul>
    <br>
    <a id="archetype-define"></a>
    <h4>Define</h4>
    <ul>
      <code>
        define &lt;name&gt; archetype [&lt;devspec&gt;] [&lt;devspec&gt;] [...]
      </code><br>
      The &lt;devspec&gt; arguments point to all inheritors for this archetype. Make shure 
      there are no conflicting actions described when using more than one archetype pointing 
      to an inheritor. Basically it's recommended to associate each inheritor with just one 
      archetype.<br>
      If no &lt;devspec&gt; is specified, it is set to "defined_by=$SELF".
      This devspec is also always checked, even if it is not specified explicitly.<br>
      See the section on <a href="#devspec">device specification</a>
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
    <a id="archetype-set"></a>
    <h4>Set</h4>
    <ul>
      <a id="archetype-set-addToAttrList"></a><li>
        <code>addToAttrList &lt;attribute&gt;</code><br>
        The command is only possible for an archetype with DEF
        "derive attributes".<br>
        Add an entry to the userattr of the <i>global</i> device so that it is
        available to all of the devices.<br>
        This can be useful to derive the alias according to a pattern.
      </li>
      <br>
      <a id="archetype-set-define"></a><li>
        <code>define inheritors</code><br>
        Defines an inheritor for all relations according to the pattern:<br>
        <ul>
          <code>
            define &lt;metaNAME&gt; &lt;actualTYPE&gt; [&lt;metaDEF&gt;]
          </code>
        </ul>
        When an inheritor is defined, it is initialized with the commands
        specified under the <a href="#archetype-attr-initialize">initialize</a> attribute, 
        and the archetype assign thedefined_by attribute to the value $ SELF.<br>
        The relations (<a href="#archetype-attr-metaDEF">metaNAME</a>, <a href="#archetype-attr-metaTYPE">
        metaTYPE</a> and <a href="#archetype-attr-metaDEF">metaDEF</a>) are described in
        the respective attributes.
      </li>
      <br>
      <a id="archetype-set-derive"></a><li>
        <code>derive attributes</code><br>
        This command is only availabe for an archetype with DEF
        "derive attributes".<br>
        Derives all attributes specified under the <a href="#archetype-attr-attributes">
        attributes</a> attribute for all inheritors.
      </li>
      <br>
      <a id="archetype-set-inheritance"></a><li>
        <code>inheritance</code><br>
        Inheritance all attributes specified under the <a href="#archetype-attr-attributes">attributes</a> attribute for
        all inheritors. Attribute values will be taken - if available - from the respective <a href="#archetype-attr-actual_attribute">actual_.+-attribute</a>, otherwise the value will be taken from the archetype's attribute with the same name.
      </li>
      <br>
      <a id="archetype-set-import"></a><li>
        <code>import</code><br>
        Helper funktion to create an <i>archetype</i>.
        <ul>
          <li>Imports all attributes from the given device as listed in <i>archetype's</i> <a href="#archetype-attr-attributes">attributes</a> list.</li>
          <li>If <i>attributes</i> was not set before, all attributes <u>from the given device</u> will be imported (as <a href="#archetype-attr-actual_attribute">actual_.+-attribute</a>) to the archetype; <i>attributes</i> will be filled with a list of the importierted attributes.</li>
          <li>The values form the attributs will also be imported for further usage in the archetype (marked as optional with the "undef"-prefix).</li>
        </ul>
        Note: While import is running, no values will be forwarded to the inheritors.
      </li>
      <br>
      <a id="archetype-set-initialize"></a><li>
        <code>initialize inheritors</code><br>
        Executes all commands specified under the attributes <a href="#archetype-attr-initialize">initialize</a> for all
        inheritors.
      </li>
      <br>
      <a id="archetype-set-raw"></a><li>
        <code>raw &lt;command&gt;</code><br>
        Executes the command for all inheritors.
      </li>
    </ul>
    <br>
    <a id="archetype-get"></a>
    <h4>Get</h4>
    <ul>
      <a id="archetype-get-inheritors"></a><li>
        <code>inheritors</code><br>
        Displays all inheritors.
      </li>
      <br>
      <a id="archetype-get-relations"></a><li>
        <code>relations</code><br>
        Displays all relations.
      </li>
      <br>
      <a id="archetype-get-pending"></a><li>
       <ul>
          <li>
            <code>pending attributes</code><br>
            Displays all outstanding attributes specified under the <a href="#archetype-attr-attributes">attributes</a>
            attribute for all inheritors, which do not match the (not optional) 
            attributes of the archetype.
          </li>
          <br>
          <li>
            <code>pending inheritors</code><br>
            Displays all outstanding inheritors, which shall be defined 
            based on the described relations.
          </li>
       </ul>
      </li>
    </ul>
    <br>
    <a id="archetype-attr"></a>
    <h4>Attributes</h4>
    <ul>
      Notes:<br>
      All attributes that can be inherited can be pre-modified with a modifier.
      <ul>
        <a id="archetype-attr-undef"></a><li>
          <code>attr archetype &lt;attribute&gt; undef:&lt;...&gt;</code><br>
          If <code>undef:</code>  preceded, the attribute is not inherited 
          if the inheritors does not already have this attribute (no matter which value it is set to).
        </li><br>
        <a id="archetype-attr-least"></a><li>
          <code>
            attr archetype &lt;attribute&gt;
            least[(&lt;seperator&gt;)]:&lt;...&gt;
          </code><br>
          If a list is inherited, it can be specified that these elements
          should be at least present, by prepending the
          <code>least[(&lt;seperator&gt;)]:</code>.<br>
          If no separator is specified, the space is used as separator.
        </li>
        <a id="archetype-attr-Perl"></a><li>
          <code>attr archetype &lt;attribute&gt; Perl:&lt;...&gt;</code><br>
          <code>attr archetype &lt;attribute&gt; undef,Perl:&lt;...&gt;</code><br>
          Default behaviour for Perl code in any attribute is: Code will be evaluated and the result 
          will be the value to be set in the inheritor's attribute.
          (Additional) modifier <code>Perl:</code> will change that so the (unevaluated) Perl code 
          will be used directly as attribute value (e.g. usefull for <i>devStateIcon</i> or <i>stateFormat</i>).
        </li><br>
      </ul>
      <br>
      <a id="archetype-attr-actual_attribute" data-pattern="actual_.*"></a><li>
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
        The captionRoom, description, index, and suffix expressions are added (e.g.)
        by <a href="#archetype-set-addToAttrList">addToAttrList</a>.<br>
        <b>Remarks and options:</b>
        <ul>
          <li><i>no return value</i></li>
            If an <i>actual_&lt;attribute&gt;</i> is set, it will be used instead of the 
            identically named <i>&lt;attribute&gt;</i>. If it contains Perl code to be evaluated
            and evaluation returns no value, no changes will be derived.
          <li><i>Filtering</i></li>
            Extending the attribute names indicates filtering is desired. Syntax is:
            <code>actual_&lt;attribute&gt;_&lt;index&gt; &lt;FILTER&gt; &lt;value&gt;</code>. 
            This may be helpful to configure devices with more than one channels or different models
            by a common archetype. If the given filter matches, this will prevent useage of 
            content of <i>actual_&lt;attribute&gt;</i> (and <i>&lt;attribute&gt;</i> as well), 
            even if the evaluation of Perl code will return nothing.<br>
            Example:<br>
            <code>define archHM_CC archetype TYPE=CUL_HM:FILTER=model=(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)<br>
            attr archHM_CC attributes devStateIcon icon<br>
            attr archHM_CC actual_devStateIcon_RT model=HM-CC-RT-DN:FILTER=chanNo=04 Perl:{devStateIcon_Clima($name)}<br>
            attr archHM_CC actual_devStateIcon_WT model=HM-TC-IT-WM-W-EU:FILTER=chanNo=02 Perl:{devStateIcon_Clima($name)}<br>
            attr archHM_CC actual_icon hm-cc-rt-dn<br>
            attr archHM_CC actual_icon_2 model=HM-TC-IT-WM-W-EU hm-tc-it-wm-w-eu</code>
          <li><i>Frontend availability</i></li>
            <i>actual_&lt;attribute&gt;</i> is a "wildcard" attribute, intended to be set (initially) 
            using FHEM command field. Wrt. to useage of <i>filtering</i>, this is the only way to set 
            this type of attribute, all items from the <a href="#archetype-attr-attributes">attributes</a> list 
            will added as <i>actual_&lt;attribute&gt;</i> as well and then can be accessed
            directly by the regular drop-down menu in FHEMWEB.
        </ul>
      </li>
      <br>
      <a id="archetype-attr-actualTYPE"></a><li>
        <code>actualTYPE &lt;TYPE&gt;</code><br>
        Sets the TYPE of the inheritor. The default value is <i>dummy</i>.
      </li>
      <br>
      <a id="archetype-attr-attributes"></a><li>
        <code>attributes &lt;attribute&gt; [&lt;attribute&gt;] [...]</code><br>
        Space-separated list of attributes to be inherited. Values of the attributes 
        in the inheritence process will be taken from the attributes with either (lower 
        to higher priority) from
         <ul>
          <li>attribute with exactly the same name</li>
          <li>attribute following the name sheme <a href="#archetype-attr-actual_attribute">actual_&lt;attribute&gt;</a></li>
          <li>attribute following the name sheme <a href="#archetype-attr-actual_attribute">actual_&lt;attribute&gt;_&lt;index&gt;</a> in combination with matching filter</li>
        </ul>
      </li>
      <br>
      <a id="archetype-attr-attributesExclude"></a><li>
        <code>
          attributesExclude &lt;attribute&gt; [&lt;attribute&gt;] [...]
        </code><br>
        A space-separated list of attributes that are not inherited to these
        inheritors.
      </li>
      <br>
      <a id="archetype-attr-autocreate"></a><li>
        <code>autocreate 0</code><br>
        If set to 0, the archetype does not automatically inherit attributes to new devices,
        and inheritors are not created automatically for new relations.<br>
        The default value is 1.
      </li>
      <br>
      <a id="archetype-attr-defined_by"></a><li>
        <code>defined_by &lt;...&gt;</code><br>
        Auxiliary attribute to recognize by which <a href="#archetype">archetype</a>
        the device has been defined as inheritor.
      </li>
      <br>
      <a id="archetype-attr-deleteAttributes"></a><li>
        <code>deleteAttributes 1</code><br>
        If set to 1 and then an attribute is deleted in the archetype, it is also deleted for all
        inheritors.<br>
        The default value is 0.
      </li>
      <br>
      <a id="archetype-attr-disable"></a><li>
        <code>disable 1</code><br>
        No attributes are inherited and no inheritors are defined.
      </li>
      <br>
      <a id="archetype-attr-initialize"></a><li>
        <code>initialize &lt;initialize&gt;</code><br>
        &lt;initialize&gt; can be specified as &lt;text&gt; or {perl code}.<br>
        The &lt;text&gt; or the return of {perl code} must be a list of FHEM
        commands separated by a semicolon (;). These are used to initialize the
        inheritors when they are defined.<br>
        Note: This functionality is limited to "<a href="#archetype-attr-relations">relations</a>"!
      </li>
      <br>
      <a id="archetype-attr-metaDEF"></a><li>
        <code>metaDEF &lt;metaDEF&gt;</code><br>
        &lt;metaDEF&gt; can be specified as &lt;text&gt; or {perl code} and
        describes the structure of the DEF for the inheritors.
      </li>
      <br>
      <a id="archetype-attr-metaNAME"></a><li>
        <code>metaNAME &lt;metaNAME&gt;</code><br>
        &lt;metaNAME&gt; can be specified as &lt;text&gt; or {perl code} and
        describes the structure of the name for the inheritors.
      </li>
      <br>
      <a id="archetype-attr-readingList" data-pattern="(reading|set)List"></a><li>
        <code>readingList &lt;values&gt;</code><br>
        <code>setList &lt;values&gt;</code><br>
        Both work as same attributes in <a href="#dummy">dummy</a>. They are intented
        to set initial values for "initialize"-actions that may he handed over to heirs.
      </li>
      <br>
      <a id="archetype-attr-relations"></a><li>
        <code>relations &lt;devspec&gt; [&lt;devspec&gt;] [...]</code><br>
        The relations describes all the relations that exist for this
        archetype.<br>
        See the section on
        <a href="#devspec">device specification</a>
        for details of the &lt;devspec&gt;.
      </li>
      <br>
      <a id="archetype-attr-splitRooms"></a><li>
        <code>splitRooms 1</code><br>
        Returns every room seperatly for each relation in $room.
      </li>
      <br>
    </ul>
    <br>
    <a id="archetype-examples"></a>
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
attr SVG_archetype attributes group
attr SVG_archetype group history
</pre>
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
attr SVG_link_archetype group history
attr SVG_link_archetype attributes group</pre>
        </ul>
      </li>
    </ul>
  </ul>
</div>

=end html

=begin html_DE

<a id="archetype"></a>
<h3>archetype</h3>
<div>
  <ul>
    <i>archetype</i> (lt. Duden Synonym u.a. für: <i>Urbild, Urform, Urgestalt, Urtyp, Ideal, Inbegriff, Musterbild, Vorbild</i>) kann:
    <ul>
      <li>Attribute vom <i>archetype</i> auf andere Geräte übertragen und/oder</li>
      <li>neue Geräte (auch z.B. solche, die von <a href="#autocreate">autocreate</a> erzeugt werden)
      <ul>
        <li>nach einem bestimmten Muster anlegen</li>
        <li>mit Standardattributen versorgen</li>
        <li>mit Standardattributen und/oder Reading-Werte initialisieren</li>
      </ul></li>
      <li>vorhandene Abweichungen zu gewünschten Standard-Attribut-Inhalten aufzeigen und beheben</li>
    </ul><br>
    Die verwendeten Begriffe sind angelehnt an <a href="https://de.wikipedia.org/wiki/Vererbung_%28Programmierung%29">Vererbung</a> 
    in der Programmierung. 
    Mit einem <i>archetype</i> werden Attribute auf <i>Erben</i> (inheritors), andere
    Geräte, übertragen. Die Erben können, nach einem vorgegeben
    Muster im <i>archetype</i> und für <i>Beziehungen</i> (relations), eine bestimmte
    Gruppe von Geräten, definiert werden.<br>
    <br>
    Folgende Variablen können für Übertragungsvorgänge genutzt werden:
    <ul>
      <li><code>$name</code> Name des Erben</li>
      <li><code>$room</code> Raum der Beziehung</li>
      <li><code>$relation</code> Name der Beziehung</li>
      <li><code>$SELF</code> Name des archetype</li>
    </ul>
    <br>
    Hinweis: Für in Teilen ähnliche Funktionalitäten siehe auch die Kommandos <a href="#setdefaultattr">setdefaultattr</a> sowie <a href="#template">template</a>.
    <a id="archetype-command"></a>
    <h4>Befehle</h4>
    <ul>
    <a id="archetype-command-archetype"></a>
      <code>archetype &lt;clean or check&gt;</code><br>
      Definiert für alle Beziehungen aller archetype die Erben, vererbt für
      alle <i>archetype</i> die unter dem Attribut <i>attributes</i> angegeben Attribute auf
      alle Erben.<br>
      Wird optinal der Parameter "check" angegeben werden alle ausstehenden
      Attribute und Erben angezeigt.
    </ul>
    <a id="archetype-define"></a>
    <h4>Define</h4>
    <ul>
      <code>
        define &lt;name&gt; archetype [&lt;devspec&gt;] [&lt;devspec&gt;] [...]
      </code><br>
      In den &lt;devspec&gt; werden alle Erben beschrieben die es für dieses
      archetype gibt. Es sollte darauf geachtet werden, dass jeder Erbe nur
      einem archetype zugeordnet ist und keine widerstreitenden Angaben für 
      diesselben Attribute aus unterschiedlichen archetype abgeleitet werden sollen.
      .<br>
      Wird keine &lt;devspec&gt; angegeben wird diese mit "defined_by=$SELF"
      gesetzt. Diese devspec wird auch immer überprüft, selbst wenn
      sie nicht angegeben ist.<br>
      Siehe den Abschnitt über <a href="#devspec">Geräte-Spezifikation</a>
      für Details zu &lt;devspec&gt;.<br>
      <br>
      <code>define &lt;name&gt; archetype derive attributes</code><br>
      Wird in der DEF "derive attributes" angegeben, handelt es sich um ein
      besonderes archetype. Es leitet Attribute anhand eines Musters ab.<br>
      Das Muster wird mit den Attributen actual_.+ beschrieben.<br>
      Als Erben werden alle Geräte aufgelistet welche alle Pflicht-
      Attribute eines Musters besitzen.
    </ul>
    <a id="archetype-set"></a>
    <h4>Set</h4>
    <ul>
      <a id="archetype-set-addToAttrList"></a><li>
        <code>addToAttrList &lt;attribute&gt;</code><br>
        Der Befehl ist nur bei einem archetype mit der DEF "derive attributes"
        möglich.<br>
        Fügt global einen Eintrag unter userattr hinzu, sodass er für
        alle Geräte zur Verfügung steht.<br>
        Dies kann sinnvoll sein, um (z.B.) den alias nach einem Muster abzuleiten.
      </li>
      <br>
      <a id="archetype-set-define"></a><li>
        <code>define inheritors</code><br>
        Definiert für alle Beziehungen einen Erben nach dem Muster:<br>
        <ul>
          <code>
            define &lt;metaNAME&gt; &lt;actualTYPE&gt; [&lt;metaDEF&gt;]
          </code>
        </ul>
        Wenn ein Erbe definiert wird, wird er mit den unter dem Attribut
        initialize angegebenen Befehlen initialisiert und ihm wird das Attribut
        <i>defined_by</i> mit dem Wert $SELF zugewiesen.<br>
        Die Beziehungen (<a href="#archetype-attr-metaDEF">metaNAME</a>, <a href="#archetype-attr-metaTYPE">
        metaTYPE</a> und <a href="#archetype-attr-metaDEF">metaDEF</a>) werden 
        in den gleichnamigen Attributen beschrieben.
      </li>
      <br>
      <a id="archetype-set-derive"></a><li>
        <code>derive attributes</code><br>
        Der Befehl ist nur bei einem archetype mit der DEF "derive attributes"
        möglich.<br>
        Leitet für alle Erben die unter dem Attribut <a href="#archetype-attr-attributes">attributes</a>
        angegeben Attribute ab.
      </li>
      <br>
      <a id="archetype-set-inheritance"></a><li>
        <code>inheritance</code><br>
        Vererbt die eigenen unter dem Attribut <a href="#archetype-attr-attributes">attributes</a>
        angegeben Attribute auf alle Erben. Dabei werden - wenn vorhanden - die Vorgaben aus dem
        zugehörigen <a href="#archetype-attr-actual_attribute">actual_.+-Attribut</a> entnommen,
        hilfsweise aus dem gleichnamigen Attribut des archetype.
      </li>
      <br>
      <a id="archetype-set-import"></a><li>
        <code>import</code><br>
        Hilfsfunktion zum Erstellen eines <i>archetype</i>.
        <ul>
          <li>Importiert alle Attribute vom ausgewählten Device, die im <i>archetype</i> unter <i>attributes</i> gelistet sind.</li>
          <li>Ist <i>attributes</i> nicht gesetzt, werden alle <u>im genannten Device gesetzten</u> Attribute (als <a href="#archetype-attr-actual_attribute">actual_.+-attribute</a>) in das archetype importiert und <i>attributes</i> wird mit der Liste der importierten Attribute gefüllt</li>
          <li>die Attribut-Werte werden ebenfalls importiert und können dann nachbearbeitet werden. Sie werden dabei als nicht zwingende Attributwerte (mit "undef"-Präfix) übernommen.</li>
        </ul>
        Hinweis: Beim Import werden die Attribute nicht direkt wieder weitervererbt.
      </li>
      <br>
      <a id="archetype-set-initialize"></a><li>
        <code>initialize inheritors</code><br>
        Führt für alle Erben die unter dem Attribut <a href="#archetype-attr-initialize">initialize</a> angegebenen Befehle aus.
      </li>
      <br>
      <a id="archetype-set-raw"></a><li>
        <code>raw &lt;Befehl&gt;</code><br>
        Führt für alle Erben den Befehl aus.
      </li>
    </ul>
    <a id="archetype-get"></a>
    <h4>Get</h4>
    <ul>
      <a id="archetype-get-inheritors"></a><li>
        <code>inheritors</code><br>
        Listet alle Erben auf.
      </li>
      <br>
      <a id="archetype-get-relations"></a><li>
        <code>relations</code><br>
        Listet alle Beziehungen auf.
      </li>
      <br>
      <a id="archetype-get-pending"></a><li>
          <ul><li>
            <code>pending attributes</code><br>
            Listet für jeden Erben die unter dem Attribut <a href="#archetype-attr-attributes">attributes</a> angegeben
            Attribute auf, die nicht mit den (zwingenden) Attribut-Vorgaben des archetype
            übereinstimmen.
          </li>
          <br>
          <li>
            <code>pending inheritors</code><br>
            Listet alle Erben auf die aufgrund der Beziehungen noch definiert
            werden sollen.
          </li>
        </ul>
      </li>
    </ul>
    <a id="archetype-attr"></a>
    <h4>Attribute</h4>
    <ul>
      Hinweise:
      <ul>
        Alle Attribute, die vererbt werden können, können vorab mit
        einem Modifikator versehen werden.
        <a id="archetype-attr-undef"></a><li>
          <code>attr archetype &lt;attribute&gt; undef:&lt;...&gt;</code><br>
          Wird <code>undef:</code> vorangestellt wird das Attribut nur vererbt,
          sofern dieses Attribut an dem Erbe noch gar nicht vorhanden ist.
        </li><br>
        <a id="archetype-attr-least"></a><li>
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
        <a id="archetype-attr-Perl"></a><li>
          <code>attr archetype &lt;attribute&gt; Perl:&lt;...&gt;</code><br>
          <code>attr archetype &lt;attribute&gt; undef,Perl:&lt;...&gt;</code><br>
          Wird <code>Perl:</code> (mit) vorangestellt wird der folgende Perl-Code nicht zur Ermittlung des Attributwerts vorab ausgeführt, sondern direkt als Attributwert übernommen (z.B. für <i>devStateIcon</i> oder <i>stateFormat</i>).
        </li><br>
      </ul>
      <br>
      <a id="archetype-attr-actual_attribute" data-pattern="actual_.*"></a><li>
        <code>actual_&lt;attribute&gt; &lt;value&gt;</code><br>
        &lt;value&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden.<br>
        Wird das Attribut &lt;attribute&gt; vererbt, ersetzt die Rückgabe
        des actual_&lt;attribute&gt; den Wert des gleichnamigen Attributes.<br>
        Bei dem archetype mit der DEF "derive attributes" können Muster
        definiert werden.<br>
        Beispiel:
        <code>
          actual_alias %captionRoom|room%: %description%[ %index%][%suffix%]
        </code><br>
        Alle in % eingeschlossenen Ausdrücke sind Attribute. Eine Reihenfolge
        lässt sich durch | erreichen. Ist ein Ausdruck in [] eingeschlossen ist
        er optional.<br>
        Die Ausdrücke <i>captionRoom</i>, <i>description</i>, <i>index</i> und <i>suffix</i> sind hierbei
        z.B. durch <a href="#archetype-set-addToAttrList">addToAttrList</a> hinzugefügte (globale) Attribute.<br><br>
        <b>Weitere Hinweise und Optionen</b>
        <ul>
          <li><i>keine Rückgabe</i></li>
            Ist in einem Attribut (z.B. nach der Evaluierung einer Perl-Funktion) kein Inhalt definiert, 
            wird keine Änderung vorgenommen.
          <li><i>Filterungen</i></li>
            Duch weitere Zusätze zum Attributnamen können zusätzliche Filterungen realisiert werden. 
            Dies erfolgt in der Form <code>actual_&lt;attribute&gt;_&lt;index&gt; &lt;FILTER&gt;
            &lt;value&gt;</code>. Dies kann genutzt werden, um z.B. Geräte mit mehreren Kanälen oder
            ähnliche Modelle über ein gemeinsames archetype abzubilden. Falls der angegebene Filter paßt, wird ein eventuell vorhandenes gleichnamiges <i>actual_&lt;attribute&gt;</i> nicht ausgewertet, selbst, wenn ggf. die Evaluierung von Perl-Code keinen Rückgabewert ergibt.<br>
            Beispiel:<br>
            <code>define archHM_CC archetype TYPE=CUL_HM:FILTER=model=(HM-CC-RT-DN|HM-TC-IT-WM-W-EU)<br>
            attr archHM_CC attributes devStateIcon icon<br>
            attr archHM_CC actual_devStateIcon_RT model=HM-CC-RT-DN:FILTER=chanNo=04 Perl:{devStateIcon_Clima($name)}<br>
            attr archHM_CC actual_devStateIcon_WT model=HM-TC-IT-WM-W-EU:FILTER=chanNo=02 Perl:{devStateIcon_Clima($name)}<br>
            attr archHM_CC actual_icon hm-cc-rt-dn<br>
            attr archHM_CC actual_icon_2 model=HM-TC-IT-WM-W-EU hm-tc-it-wm-w-eu</code>
          <li><i>Verfügbarkeit im FHEMWEB-Frontend</i></li>
            Es handelt sich um "wildcard"-Attribute, die (initial) über das FHEM-Kommandofeld gesetzt
            werden können bzw. (im Fall der <i>Filterung</i>) müssen. Ein Attribut, das in 
            <a href="#archetype-attr-attributes">attributes</a> gelistet ist, erhält automatisch 
            einen passenden actual_&lt;attribute&gt;-Eintrag und kann dann auch direkt das drop-down 
            Menü der Attribut-Liste in FHEMWEB gesetzt werden.
        </ul>
      </li>
      <br>
      <a id="archetype-attr-actualTYPE"></a><li>
        <code>actualTYPE &lt;TYPE&gt;</code><br>
        Legt den TYPE des Erben fest. Der Standardwert ist <i>dummy</i>.
      </li>
      <br>
      <a id="archetype-attr-attributes"></a><li>
        <code>attributes &lt;attribute&gt; [&lt;attribute&gt;] [...]</code><br>
        Leerzeichen-getrennte Liste der zu vererbenden Attribute. Die Werte der
        Attribute werden (mit steigender Priorität) im Vererbungsprozess entnommen aus 
        dem Attribut mit:
         <ul>
          <li>genau demselben Namen</li>
          <li>dem Namens-Schema: <a href="#archetype-attr-actual_attribute">actual_&lt;attribute&gt;</a></li>
          <li>dem Namens-Schema <a href="#archetype-attr-actual_attribute">actual_&lt;attribute&gt;_&lt;index&gt;</a>,
          sofern der dort angegebene Filter paßt.</li>
        </ul>
      </li>
      <br>
      <a id="archetype-attr-attributesExclude"></a><li>
        <code>
          attributesExclude &lt;attribute&gt; [&lt;attribute&gt;] [...]
        </code><br>
        Leerzeichen-getrennte Liste von Attributen die nicht auf diesen Erben
        vererbt werden.
      </li>
      <br>
      <a id="archetype-attr-autocreate"></a><li>
        <code>autocreate <0 oder 1></code><br>
        Legt fest, ob durch das archetype automatisch Attribute auf neue Devices vererbt werden 
        sollen bzw. ob Erben automatisch für neue Beziehungen angelegt werden.<br>
        Der Standardwert ist 1.
      </li>
      <br>
      <a id="archetype-attr-defined_by"></a><li>
        <code>defined_by &lt;...&gt;</code><br>
        Hilfsattribut um zu erkennen, durch welchen <a href="#archetype">archetype</a> ein 
        Device als Erbe definiert wurde.
      </li>
      <br>
      <a id="archetype-attr-deleteAttributes"></a><li>
        <code>deleteAttributes 1</code><br>
        Wenn gesetzt, wird ein im archetype gelöschtes Attribut auch bei allen Erben
        gelöscht.<br>
        Der Standardwert ist 0 (deaktiviert).
      </li>
      <br>
      <a id="archetype-attr-disable"></a><li>
        <code>disable 1</code><br>
        Es werden keine Attribute mehr vererbt und keine Erben definiert.
      </li>
      <br>
      <a id="archetype-attr-initialize"></a><li>
        <code>initialize &lt;initialize&gt;</code><br>
        &lt;initialize&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden.<br>
        Der &lt;Text&gt; oder die Rückgabe vom {perl code} muss eine
        durch Semikolon (;) getrennte Liste von FHEM-Befehlen sein. Mit diesen
        werden die Erben initialisiert, wenn sie definiert werden bzw. der 
        Befehl <a href="#archetype-set-initialize">initialize</a> angewandt wird.<br>
        Hinweis: Die Funktion ist beschränkt auf "<a href="#archetype-attr-relations">relations</a>"!
      </li>
      <br>
      <a id="archetype-attr-metaDEF"></a><li>
        <code>metaDEF &lt;metaDEF&gt;</code><br>
        &lt;metaDEF&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden und beschreibt den Aufbau der DEF für die Erben.
      </li>
      <br>
      <a id="archetype-attr-metaNAME"></a><li>
        <code>metaNAME &lt;metaNAME&gt;</code><br>
        &lt;metaNAME&gt; kann als &lt;Text&gt; oder als {perl code} angegeben
        werden und beschreibt den Aufbau des Namens für die Erben.
      </li>
      <br>
      <a id="archetype-attr-relations"></a><li>
        <code>relations &lt;devspec&gt; [&lt;devspec&gt;] [...]</code><br>
        In den &lt;relations&gt; werden alle Beziehungen beschrieben, die es für
        dieses archetype gibt.<br>
        Siehe den Abschnitt über <a href="#devspec">Geräte-Spezifikation</a>
        für Details zu &lt;devspec&gt;.
      </li>
      <br>
      <a id="archetype-attr-readingList" data-pattern="(reading|set)List"></a><li>
        <code>readingList &lt;values&gt;</code><br>
        <code>setList &lt;values&gt;</code><br>
        Ermöglichen zusammen das Vorbelegen von Reading-Werten, die z.B. bei einer "initialize"-Aktion ausgewertet und an die Erben weitergereicht werden können. Siehe auch die entsprechenden Attributbeschreibungen in <a href="#dummy">dummy</a>.
      </li>
      <br>
      <a id="archetype-attr-splitRooms"></a><li>
        <code>splitRooms 1</code><br>
        Gibt für jede Beziehung jeden Raum separat in $room zurück.
      </li>
    </ul>
    <a id="archetype-examples"></a>
    <h4>Beispiele</h4>
    <ul>
      <a href="https://wiki.fhem.de/wiki/Import_von_Code_Snippets">
        <u>
          Die folgenden beispiel Codes können per "Raw defnition"
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
attr SVG_archetype attributes group
attr SVG_archetype group verlaufsdiagramm</pre>
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

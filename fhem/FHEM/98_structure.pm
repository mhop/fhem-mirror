##############################################
package main;

use strict;
use warnings;

#####################################
sub
structure_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}     = "structure_Define";
  $hash->{UndefFn}   = "structure_Undef";

  $hash->{SetFn}     = "structure_Set";
  $hash->{AttrFn}    = "structure_Attr";
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

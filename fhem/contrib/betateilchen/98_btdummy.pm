##############################################
# $Id$
# forked from 98_dummy.pm
#

package FHEM::Automation::btdummy; ##no critic qw(Package)

  use strict;
  use warnings;
  use SetExtensions;

  use GPUtils qw(GP_Import);

sub ::btdummy_Initialize { goto &Initialize }

BEGIN {

  GP_Import( qw(
    attr
    AttrVal
    InternalTimer
    IsDisabled
    Log3
    readingFnAttributes
    readingsSingleUpdate
  ) )
};

sub Initialize {
  my $hash = shift // return;

  $hash->{DefFn}       = \&Define;
  $hash->{SetFn}       = \&Set;
  $hash->{AttrFn}      = \&Attr;


  $hash->{AttrList} =
    "disable:1,0 ".
    "disabledForIntervals:textField-long ".
    "onDefineFn:textField-long ".
    "readingList:textField-long ".
    "setExtensionsEvent:1,0 ".
    "setList:textField-long ".
    "useSetExtensions:1,0 ".
    $readingFnAttributes;
  return;
}

sub Set {
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "no set value specified" if(int(@a) < 1);
  my $setList = AttrVal($name, "setList", " ");
  $setList =~ s/\n/ /g;

  if(AttrVal($name,"useSetExtensions",undef)) {
    my $a0 = $a[0]; $a0 =~ s/([.?*])/\\$1/g;
    if($setList !~ m/\b$a0\b/) {
      unshift @a, $name;
      return SetExtensions($hash, $setList, @a) 
    }
    SetExtensionsCancel($hash);
  } else {
    return "Unknown argument ?, choose one of $setList" if($a[0] eq "?");
  }

  return undef
    if($attr{$name} &&  # Avoid checking it if only STATE is inactive
       ($attr{$name}{disable} || $attr{$name}{disabledForIntervals}) &&
       IsDisabled($name));

  my @rl = split(" ", AttrVal($name, "readingList", ""));
  my $doRet;
  eval {
    if(@rl && grep /^$a[0]$/, @rl) {
      my $v = shift @a;
      readingsSingleUpdate($hash, $v, join(" ",@a), 1);
      $doRet = 1;
    }
  };
  return if($doRet);

  my $v = join(" ", @a);
  Log3 $name, 4, "dummy set $name $v";

  $v = $hash->{SetExtensionsCommand}
        if($hash->{SetExtensionsCommand} &&
           AttrVal($name, "setExtensionsEvent", undef));
  readingsSingleUpdate($hash,"state",$v,1);
  return undef;
}

sub Define {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Wrong syntax: use btdefine <name> dummy" if(int(@a) != 2);
  return undef;
}

sub Attr {
  my @a = @_;

  $a[2] = "" if(!defined($a[2]));
  $a[3] = "" if(!defined($a[3]));

  if($a[2] eq "onDefineFn") {
    if($a[0] eq "set"){
      InternalTimer(0,$a[3],$a[1],1);
    }
    return;
  }
}

1;

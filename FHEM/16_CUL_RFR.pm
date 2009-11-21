##############################################
package main;

use strict;
use warnings;

my %defptr;

# Adjust TOTAL to you meter:
# {$defs{emwz}{READINGS}{basis}{VAL}=<meter>/<corr2>-<total_cnt> }

#####################################
sub
CUL_RFR_Initialize($)
{
  my ($hash) = @_;

  # Message is like
  # K41350270

  $hash->{WriteFn}   = "CUL_RFR_Write";
  $hash->{Clients}   = $modules{CUL}->{Clients};
  $hash->{Match}     = "^[0-9][0-9]U...";
  $hash->{DefFn}     = "CUL_RFR_Define";
  $hash->{UndefFn}   = "CUL_RFR_Undef";
  $hash->{ParseFn}   = "CUL_RFR_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 model:CUL,CUN,CUR loglevel";
}

#####################################
sub
CUL_RFR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_RFR <code>"
            if(int(@a) != 3 || $a[2] !~ m/[0-9][0-9]/);
  $hash->{CODE} = $a[2];
  $defptr{$a[2]} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
CUL_RFR_Write($$)
{
  my ($hash,$fn,$msg) = @_;
}

#####################################
sub
CUL_RFR_Undef($$)
{
  my ($hash, $name) = @_;
  delete($defptr{$hash->{CODE}});
  return undef;
}

#####################################
sub
CUL_RFR_Parse($$)
{
  my ($iohash,$msg) = @_;

  # 0123456789012345678
  # E01012471B80100B80B -> Type 01, Code 01, Cnt 10
  my ($cde, $omsg) = split("U", $msg, 2);
  if(!$defptr{$cde}) {
    Log 1, "CUL_RFR detected, Code $cde, MSG $omsg";
    return;
  }
  my $hash = $defptr{$cde};
  my $name = $hash->{NAME};
  CUL_Parse($hash, $iohash, $hash->{NAME}, $omsg, "X21");
  return "";
}

1;


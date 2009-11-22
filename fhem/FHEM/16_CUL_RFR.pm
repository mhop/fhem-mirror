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

  my $cl = $modules{CUL}->{Clients};
  $cl =~ s/CUL_RFR//;                       # Dont want to be my own client.

  $hash->{Clients}   = $cl;
  $hash->{Match}     = "^[0-9A-F]{4}U.";
  $hash->{DefFn}     = "CUL_RFR_Define";
  $hash->{UndefFn}   = "CUL_RFR_Undef";
  $hash->{ParseFn}   = "CUL_RFR_Parse";
  $hash->{AttrList}  = "IODev do_not_notify:0,1 model:CUL,CUN,CUR loglevel";

  $hash->{WriteFn}   = "CUL_RFR_Write";
  $hash->{GetFn}     = "CUL_Get";
  $hash->{SetFn}     = "CUL_Set";
}


#####################################
sub
CUL_RFR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_RFR <id> <routerid>"
            if(int(@a) != 4 ||
               $a[2] !~ m/[0-9A-F]{2}/i ||
               $a[3] !~ m/[0-9A-F]{2}/i);
  $hash->{ID} = $a[2];
  $hash->{ROUTERID} = $a[3];
  $defptr{"$a[2]$a[3]"} = $hash;
  AssignIoPort($hash);
  return undef;
}

#####################################
sub
CUL_RFR_Write($$)
{
  my ($hash,$fn,$msg) = @_;

  ($fn, $msg) = CUL_WriteTranslate($hash, $fn, $msg);
  return if(!defined($fn));
  $msg = $hash->{ID} . $hash->{ROUTERID} . $fn . $msg;
  IOWrite($hash, "u", $msg);
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
  $msg =~ m/^([0-9AF]{2})([0-9AF]{2})U(.*)/;
  my ($rid, $id, $smsg) = ($1,$2,$3);
  my $cde = "${id}${rid}";

  if(!$defptr{$cde}) {
    Log 1, "CUL_RFR detected, Id $id, Router $rid, MSG $smsg";
    return;
  }
  my $hash = $defptr{$cde};
  my $name = $hash->{NAME};
  CUL_Parse($hash, $iohash, $hash->{NAME}, $smsg, "X21");
  return "";
}

sub
CUL_RFR_DelPrefix($)
{
  my ($prefix, $msg) = split("U", shift);
  return $msg;
}

sub
CUL_RFR_AddPrefix($$)
{
  my ($hash, $msg) = @_;
  return "u" . $hash->{ID} . $hash->{ROUTERID} . $msg;
}

1;


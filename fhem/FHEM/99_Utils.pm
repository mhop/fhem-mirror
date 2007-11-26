package main;
use strict;
use warnings;
use POSIX;

sub
Utils_Initialize($$)
{
  my ($hash) = @_;
}

sub
time_str2num($)
{
  my ($str) = @_;
  my @a = split("[- :]", $str);
  return mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
}


##############################################
# $Id$
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

sub
min($$)
{
  my ($a,$b) = @_;
  return $a if($a lt $b);
  return $b;
}

sub
max($$)
{
  my ($a,$b) = @_;
  return $a if($a gt $b);
  return $b;
}

sub
abstime2rel($)
{
  my ($h,$m,$s) = split(":", shift);
  $m = 0 if(!$m);
  $s = 0 if(!$s);
  my $t1 = 3600*$h+60*$m+$s;

  my @now = localtime;
  my $t2 = 3600*$now[2]+60*$now[1]+$now[0];
  my $diff = $t1-$t2;
  $diff += 86400 if($diff <= 0);

  return sprintf("%02d:%02d:%02d", $diff/3600, ($diff/60)%60, $diff%60);
}


######## trim #####################################################
# What  : cuts blankspaces from the beginning and end of a string
# Call  : { trim(" Hello ") }
# Source: http://www.somacon.com/p114.php , 
#         http://www.fhemwiki.de/wiki/TRIM-Funktion-Anfangs/EndLeerzeichen_aus_Strings_entfernen
sub trim($)
{ 
   my $string = shift;
   $string =~ s/^\s+//;
   $string =~ s/\s+$//;
   return $string;
} 

######## ltrim ####################################################
# What  : cuts blankspaces from the beginning of a string
# Call  : { ltrim(" Hello") }
# Source: http://www.somacon.com/p114.php , 
#         http://www.fhemwiki.de/wiki/TRIM-Funktion-Anfangs/EndLeerzeichen_aus_Strings_entfernensub ltrim($)
sub ltrim($)
{
   my $string = shift;
   $string =~ s/^\s+//;
   return $string;
}

######## rtrim ####################################################
# What  : cuts blankspaces from the end of a string
# Call  : { rtrim("Hello ") }
# Source: http://www.somacon.com/p114.php , 
#         http://www.fhemwiki.de/wiki/TRIM-Funktion-Anfangs/EndLeerzeichen_aus_Strings_entfernensub ltrim($)
sub rtrim($)
{
   my $string = shift;
   $string =~ s/\s+$//;
   return $string;
}


1;

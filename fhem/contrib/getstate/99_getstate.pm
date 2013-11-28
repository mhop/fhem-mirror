################################################################
#
# $Id: 99_getstate.pm,v 1.3 2009-12-16 16:46:00 m_fischer Exp $
#
#  Copyright notice
#
#  (c) 2008 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################

package main;
use strict;
use warnings;
use POSIX;

sub CommandGetState($);
sub stringToNumber($);
sub stripNumber($);
sub isNumber;
sub isInteger;
sub isFloat;

#####################################
sub
GetState_Initialize($$)
{
  my %lhash = ( Fn=>"CommandGetState",
                Hlp=>"<devspec>,list short status info" );
  $cmds{getstate} = \%lhash;
}


#####################################
sub
CommandGetState($)
{

  my ($cl, $param) = @_;

  return "Usage: getstate <devspec>" if(!$param);

  my $str;
  my $sdev = $param;

  if(!defined($defs{$sdev})) {
    $str = "Please define $sdev first";
  } else {

    my $r = $defs{$sdev}{READINGS};
    my $val;
    my $v;

    if($r && $defs{$sdev}{TYPE} ne "CUL_WS") {
      foreach my $c (sort keys %{$r}) {
        undef($v);
        $val = $r->{$c}{VAL};
        $val =~ s/\s+$//g;
        $val = stringToNumber($val);
        $val = stripNumber($val);
        $val =~ s/\s+$//g;
        $v = $val if (isNumber($val) && !$v);
        $v = $val if (isInteger($val) && !$v);
        $v = $val if (isFloat($val) && !$v);
        $c =~ s/:/-/g;
        $str .= sprintf("%s:%s ",$c,$v) if(defined($v));
      }

    }
    if ($r && $defs{$sdev}{TYPE} eq "CUL_WS") {
      $v = $defs{$sdev}{READINGS}{state}{VAL};
      $v =~ s/:\s+/:/g;
      $v =~ s/\s+/ /g;
      $str = $v;
    }

  }

  return $str;

}

#####################################
sub stringToNumber($)
{
  my $s = shift;

  $s = "0" if($s =~ m/^(off|no \(yes\/no\))$/);
  $s = "1" if($s =~ m/^(on|yes \(yes\/no\))$/);

  return $s;
}

#####################################
sub stripNumber($)
{
  my $s = shift;
  my @strip = (" (Celsius)", " (l/m2)", " (counter)", " (%)", " (km/h)" , "%");

  foreach my $pattern (@strip) {
    $s =~ s/\Q$pattern\E//gi;
  }

  return $s;
}

#####################################
sub isNumber
{
  $_[0] =~ /^\d+$/
}

#####################################
sub isInteger
{
  $_[0] =~ /^[+-]?\d+$/
}

#####################################
sub isFloat
{
  $_[0] =~ /^[+-]?\d+\.?\d*$/
} 

1;

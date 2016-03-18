# $Id$
#
package main;
use strict;
use warnings;

sub CommandSvn;

sub svn_Initialize($$) {
  my %hash = (  Fn => "CommandSvn", Hlp => "[<command>],execute svn commands)" );
  $cmds{svn} = \%hash;
}

sub CommandSvn {
  my ($cl, $arg) = @_;
  return qx(svn $arg);
}


1;

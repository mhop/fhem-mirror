# $Id: 98_svn.pm 11079 2016-03-18 12:50:58Z betateilchen $
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

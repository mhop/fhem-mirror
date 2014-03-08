# $Id$
# Wrapper module for configDB
package main;

use strict;
use warnings;
use feature qw/say switch/;

sub configDB_Initialize($) {
  my ($hash) = @_;
  $hash->{DefFn}     = "configDB_Define";
  $hash->{SetFn}     = "configDB_Set";
  $hash->{GetFn}     = "configDB_Get";
  $hash->{AttrList}  = "private:1,0 ";
}

sub configDB_Define($$) {
  return "configDB not enabled!" unless $attr{global}{configfile} eq 'configDB';
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  return "Wrong syntax: use define <name> configDB" if(int(@a) != 2);
  readingsSingleUpdate($hash, 'state', 'active', 0);
  readingsSingleUpdate($hash, 'version', cfgDB_svnId, 0);
  return undef;
}

sub configDB_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage = "Unknown argument, choose one of reorg recover";
	return $usage if(int(@a) < 2);
	my $ret;

	given ($a[1]) {

		when ('reorg') {
			$a[2] = $a[2] ? $a[2] : 3;
			$ret = cfgDB_Reorg($a[2]);
		}

		when ('recover') {
			$a[2] = $a[2] ? $a[2] : 3;
			$ret = cfgDB_Recover($a[2]);
		}

		default { $ret = $usage; }

	}

	return $ret;

}

sub configDB_Get($@) {

	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $usage = "Unknown argument, choose one of diff info:noArg list";
	return $usage if(int(@a) < 2);
	my $ret;

	given ($a[1]) {

		when ('info') {
			$ret = cfgDB_Info;
		}

		when ('list') {
			$a[2] = $a[2] ? $a[2] : '%';
			$a[3] = $a[3] ? $a[3] : 0;
			$ret = cfgDB_List($a[2],$a[3]);
		}

		when ('diff') {
			$ret = cfgDB_Diff($a[2],$a[3]);
		}

		default { $ret = $usage; }

	}

	return $ret;
}

1;

#!/usr/bin/perl
#
################################################################
#
#  Copyright notice
#
#  (c) 2007 Copyright: Dr. Boris Neubert (omega at online dot de)
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
#  This copyright notice MUST APPEAR in all copies of the script!
#
################################################################


# 
# this script returns the current reading for a device stored in
# the fhem logging database
#

# Usage: 
#   fhemdb_get.pl <device> <reading> [<reading> ...]
# Example:
#   fhemdb_get.pl ext.ks300 temperature humidity
#
#

#
# global configuration
#
my $dbconn      = "mysql:database=fhem;host=db;port=3306";
my $dbuser      = "fhemuser";
my $dbpassword  = "fhempassword";

#
# nothing to change below this line
#

use strict;
use warnings;
use DBI;

(@ARGV>=2) || die "Usage: fhemdb_get.pl <device> <reading> [<reading> ... ]";

my $device= $ARGV[0];
my @readings=@ARGV; shift @readings;
my $set= join(",", map({"\'" . $_ . "\'"} @readings));

my $dbh= DBI->connect_cached("dbi:$dbconn", $dbuser, $dbpassword) || 
	die "Cannot connect to $dbconn: $DBI::errstr";
my $stm= "SELECT READING, VALUE FROM current WHERE
	(DEVICE='$device') AND
	(READING IN ($set))"; 
my $sth= $dbh->prepare($stm) || 
	die "Cannot prepare statement $stm: $DBI::errstr";
my $rc= $sth->execute() ||
	die "Cannot execute statement $stm: $DBI::errstr";

my %rs;
my $reading;
my $value;
while( ($reading,$value)= $sth->fetchrow_array) {
	$rs{$reading}= $value;
}
foreach $reading (@readings) {
	$value= $rs{$reading};
	$value= "NULL" if(!defined($value));
	print "$reading:$value ";
}
print "\n";
die $sth->errstr if $sth->err;
$dbh->disconnect();








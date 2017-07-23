#!/usr/bin/perl -w
# $Id$

use strict;
use warnings;
use DBI;

my $limit = "datetime('now', '-13 months')";

# directory cointains databases
my $datadir  = "./data";
my $dbf      = "$datadir/fhem_statistics_2017.sqlite";
my $dsn      = "dbi:SQLite:dbname=$dbf";
my $sth;
my $dbh      = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
               die "Cannot connect: $DBI::errstr";

print "Deleting records...\n";
$dbh->do("DELETE FROM jsonNodes where lastSeen < $limit");
print "VACUUM...\n";
$dbh->do("VACUUM");
$dbh->disconnect();
print "Done.\n";

1;

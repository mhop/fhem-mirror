#!/usr/bin/perl -w
# $Id$

use strict;
use warnings;
use JSON;
use POSIX qw(mktime strftime);
use DBI;

my ($limit,$tnYear,$datadir,$dbf,$dsn,$sth,$dbh,$sql,@dbInfo,$dbInfo);

# define limits for outdated data
$limit  = "datetime('now', '-13 months')";
$tnYear = strftime("%Y", localtime)-2; # delete all entries (current Year -2)

# database connection
print "Establishing database connection...";
   $datadir = "./data";
   $dbf     = "$datadir/fhem_statistics_2017.sqlite";
   $dsn     = "dbi:SQLite:dbname=$dbf";
   $dbh     = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
             die "Cannot connect: $DBI::errstr";
   print "connected.\n";

# delete records older than limit
print "Deleting records...\n";
   $dbh->do("DELETE FROM jsonNodes where lastSeen < $limit");

# delete outdated statistics data for submissionsPerDay 
print "Deleting submissionsPerDay in $tnYear\n";
   $sql = q(SELECT * from jsonNodes where uniqueID = 'databaseInfo');
   $sth = $dbh->prepare( $sql );
   $sth->execute();
   @dbInfo = $sth->fetchrow_array();
   $dbInfo = decode_json $dbInfo[3];
   delete $dbInfo->{'submissionsPerDay'}{$tnYear};
   $dbInfo = encode_json $dbInfo;
   $sth = $dbh->prepare(q{INSERT OR REPLACE INTO jsonNodes(uniqueID,json) VALUES(?,?)});
   $sth->execute('databaseInfo',$dbInfo);
   $sth->finish();

# shrink database
print "Shrinking database.\n";
   $dbh->do("VACUUM");

# Done.
   $dbh->disconnect();
   print "Done.\n";

1;

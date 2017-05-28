#!/usr/bin/perl -w

=for comment

$Id$

This script free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
any later version.

The GNU General Public License can be found at
http://www.gnu.org/copyleft/gpl.html.
A copy is found in the textfile GPL.txt and important notices to the license
from the author is found in LICENSE.txt distributed with these scripts.

This script is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut

use strict;
use warnings;
use DBI;
use JSON;
use Data::Dumper;

sub _init_dbInfo();
sub _make_Geo($);
sub _make_System(@);
sub _make_Modules($);

my $start = time();

# directory cointains databases
my $datadir  = "./data";
my $dbf_old  = "$datadir/fhem_statistics_db.sqlite";
my $dsn_old  = "dbi:SQLite:dbname=$dbf_old";
my $dbf_new  = "$datadir/fhem_statistics_2017.sqlite";
my $dsn_new  = "dbi:SQLite:dbname=$dbf_new";
my $dbh_old  = DBI->connect($dsn_old,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
               die "Cannot connect: $DBI::errstr";
my $dbh_new  = DBI->connect($dsn_new,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
               die "Cannot connect: $DBI::errstr";

my ($sql,$sth_new,$sth_old,$migrated,%fhemInfo);

# ---------- start processing

print "\033[2J";    #clear the screen
print "\033[0;0H";  #jump to 0,0

# ---------- create table and init

   print "Initializing database...";
   $dbh_new->do("DROP TABLE IF EXISTS jsonNodes");
   $sql    = "CREATE TABLE IF NOT EXISTS jsonNodes(uniqueID VARCHAR(32) PRIMARY KEY UNIQUE, ".
             "lastSeen TIMESTAMP DEFAULT CURRENT_TIMESTAMP, geo BLOB, json BLOB)";
   $dbh_new->do($sql);

# 1. read from nodes
# 2. create geoip info hash
# 3. create system info hash
# 4. create module info hash

   # 1. read from nodes
   $sql = "SELECT * from nodes where lastSeen >= '2016-05-01'";
   $sth_old = $dbh_old->prepare( $sql );
   $sth_old->execute();

   while (my @line = $sth_old->fetchrow_array()) {
      next unless $line[0];
      $migrated++;
      %fhemInfo = ();
      print "\n".sprintf("%05d",$migrated)." $line[0]";
      
      # 2. create geoip info hash
      my $geoJson    = _make_Geo($line[0]);

      # 3. create system info hash
      _make_System(@line);
      
      # 4. create module info hash
      _make_Modules($line[0]);

      # write database entry
      my $json = encode_json \%fhemInfo; #print "\n$json\n";
      $sth_new = $dbh_new->prepare(q{INSERT INTO jsonNodes(uniqueID,lastSeen,geo,json) VALUES(?,?,?,?)});
      $sth_new->execute($line[0],$line[6],$geoJson,$json);
   }

# ---------- cleanup

   $sth_new->finish();
   print "\nUpdating databaseInfo\n";
   my $dbInfo   = _init_dbInfo();
   $sth_new = $dbh_new->prepare(q{INSERT OR REPLACE INTO jsonNodes(uniqueID,json) VALUES(?,?)});
   $sth_new->execute("databaseInfo",$dbInfo);

   $sth_new->finish();
   $dbh_new->disconnect();
   $dbh_old->disconnect();

   print "Done.\n";
   print "Migration time for $migrated records: ".sprintf("%.0f",time()-$start)." seconds\n\n";

# ---------- finished...

sub _make_Modules($) {
   my ($uid) = @_;
   my ($table,$found,$sql,$sth2,$module);
   $found = $dbh_old->selectrow_array("select count (uniqueID) from modules where uniqueID = '$uid'");
   if ($found) {
      $table = "modules";
   } else {
      $table = "modules_old";
      $found = $dbh_old->selectrow_array("select count (uniqueID) from modules_old where uniqueID = '$uid'");
   }
   print " $table"; print "(not found)" unless $found;

   # get the column names
   $sth2 = $dbh_old->prepare("SELECT * FROM $table WHERE 1=0");
   $sth2->execute();
   my $fields = $sth2->{NAME};
   my @fields = @$fields;

   foreach $module (@fields) {
      next unless $module;
      next if $module eq 'uniqueID';
      my ($count) = $dbh_old->selectrow_array("SELECT $module from $table where uniqueID = '$uid'");
      if ($count > 0) {
         $fhemInfo{$module}{'migratedData'} = 1;
      }
   }
}

sub _make_Geo($) {
  print " GeoIP";
  my ($uid) = @_;
  my %geoIP = ();
  my $sql = "SELECT * from locations where uniqueID = '$uid' limit 1";
  my $sth2 = $dbh_old->prepare( $sql );
     $sth2->execute();
     while (my @line = $sth2->fetchrow_array()) {
        %geoIP = (
        countrycode   => $line[1],
        countrycode3  => $line[2],
        countryname   => $line[3],
        region        => $line[4],
        regionname    => $line[5],
        city          => $line[6],
        latitude      => $line[7],
        longitude     => $line[8],
        timezone      => $line[9],
        continentcode => $line[10],
        );
   }
   return encode_json(\%geoIP);
}

sub _make_System(@) {
   print " SystemInfo";
   my (@line) = @_;
   $fhemInfo{'system'}{'uniqueID'} = $line[0];
   $fhemInfo{'system'}{'release'}  = $line[1];
   $fhemInfo{'system'}{'feature'}  = '';
   $fhemInfo{'system'}{'os'}       = $line[3];
   $fhemInfo{'system'}{'arch'}     = $line[4];
   $fhemInfo{'system'}{'perl'}     = $line[5];
   return;

# 0 4d32486783ede1459d1c72e621ce9ed3| 
# 1 5.7|
# 2 DEVELOPMENT|
# 3 linux|
# 4 arm-linux-gnueabihf-thread-multi-64int|
# 5 v5.20.2|
# 6 2016-05-25 10:24:41

}

sub _init_dbInfo() {
   my %dbInfo;
   $dbInfo{'submissionsSince'} = '2012-12-02 16:20:20';
   $dbInfo{'submissionsTotal'} = '19611';
   $dbInfo{'migratedData'} = $migrated;
   return encode_json \%dbInfo;
}

1;

#

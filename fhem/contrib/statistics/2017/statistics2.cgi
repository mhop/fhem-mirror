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
--------------------------------------------------------------------------------

database stuff provided by betateilchen
visualisation provided by markusbloch

=cut

use strict;
use warnings;
use Time::HiRes qw(time);
use DBI;
use lib "./lib";
use Geo::IP;
use JSON;
use CGI qw(:standard Vars);

use Data::Dumper;

sub insertDB();
sub getLocation();
sub add2total();
sub doAggregate();
sub viewStatistics();

my $start = time(); # used for generation time calculation

my $ua   = $ENV{HTTP_USER_AGENT};
   $ua //= "";
   
my $geoip   = $ENV{HTTP_X_FORWARDED_FOR};
   $geoip //= $ENV{REMOTE_ADDR};
   
my %data  = Vars();

# database stuff
my $datadir  = "./data";
my $dbf      = "$datadir/fhem_statistics_2017.sqlite";
my $dsn      = "dbi:SQLite:dbname=$dbf";
my $dbh;
my $sth;
my $limit  = "datetime('now', '-12 months')";

  
# ---------- decide target ----------

if ($ua =~ m/FHEM/) {
  my $result = insertDB();
  print header("application/x-www-form-urlencoded");
  if ($result) {
    print "==> ok"
  } else {
    print "==> error"
  }
} else {
  viewStatistics();
}

# ---------- collect data into database ----------
# ---------- reached by "fheminfo send" ----------

sub insertDB() {
  my $uniqueID = $data{uniqueID};
  my $json     = $data{json};
  my $geo      = getLocation();

  $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
          die "Cannot connect: $DBI::errstr";
  $sth = $dbh->prepare(q{INSERT OR REPLACE INTO jsonNodes(uniqueID,geo,json) VALUES(?,?,?)});
  my $result = $sth->execute($uniqueID,$geo,$json);
  add2total() if $result;
  $dbh->disconnect();
  return $result;
}

sub getLocation() {
  my $geoIPDat = "$datadir/GeoLiteCity.dat";
  my %geoIP    = ();
  my $geo      = Geo::IP->open($geoIPDat, GEOIP_STANDARD);
  my $rec      = $geo->record_by_addr($geoip);

  if(!$rec) {
    return "";
  } else {
    my %geoIP = (
              countrycode   => $rec->country_code,
              countrycode3  => $rec->country_code3,
              countryname   => $rec->country_name,
              region        => $rec->region,
              regionname    => $rec->region_name,
              city          => $rec->city,
              latitude      => $rec->latitude,
              longitude     => $rec->longitude,
              timezone      => $rec->time_zone,
              continentcode => $rec->continent_code,
             );
    return encode_json(\%geoIP);
  }
}

sub add2total() {
   my $sql = q(SELECT * from jsonNodes where uniqueID = 'databaseInfo');
   my $sth = $dbh->prepare( $sql );
   $sth->execute();
   my @dbInfo = $sth->fetchrow_array();
   my $dbInfo = decode_json $dbInfo[3];
   $dbInfo->{'submissionsTotal'}++;
   my $new = encode_json $dbInfo;
   
   $sth = $dbh->prepare(q{INSERT OR REPLACE INTO jsonNodes(uniqueID,json) VALUES(?,?)});
   $sth->execute("databaseInfo",$new);
   $sth->finish();
}

# ---------- count everything for statistics ----------
# ---------- called by viewStatistics() ----------

sub doAggregate() {
   $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
          die "Cannot connect: $DBI::errstr";

   my ($sql,@dbInfo,%countAll,$decoded,$res);

   $sql = q(SELECT * from jsonNodes where uniqueID = 'databaseInfo');
   $sth = $dbh->prepare( $sql );
   $sth->execute();
   @dbInfo = $sth->fetchrow_array();

   my $dbInfo     = decode_json $dbInfo[3];
   my $updated    = $dbInfo[1];
   my $started    = $dbInfo->{'submissionsSince'};
   my $nodesTotal = $dbInfo->{'submissionsTotal'};
   my $nodes12    = 0;

   $sql  = "SELECT geo,json FROM jsonNodes WHERE uniqueID <> 'databaseInfo' ";
   $sql .= "AND geo <> '' AND json <> '' and lastseen > $limit";
   $sth = $dbh->prepare( $sql );
   $sth->execute();

   while (my @line = $sth->fetchrow_array()) {
      $nodes12++;
      # process GeoIP data
      $decoded  = decode_json( $line[0] );

      $res      = $decoded->{'regionname'} ;
      if($decoded->{'countrycode'} && $decoded->{'countrycode'} eq "DE") {
        $countAll{'geo'}{'regionname'}{$decoded->{'countrycode'}}{$res}++ if $res;
      }
      $res      = $decoded->{'countrycode'};
      $countAll{'geo'}{'countrycode'}{$res}{count}++ if $res;
      $countAll{'geo'}{'countrycode'}{$res}{name} = $decoded->{'countryname'} if $res;
      ($decoded,$res) = (undef,undef);

      # process system data
      $decoded  = decode_json( $line[1] );
      $res      = $decoded->{'system'}{'os'};
      $countAll{'system'}{'os'}{$res}++;
      $res      = $decoded->{'system'}{'perl'};
      $countAll{'system'}{'perl'}{$res}++;
      $res      = $decoded->{'system'}{'release'};
      $countAll{'system'}{'release'}{$res}++;
      ($res) = (undef);
      
      # process modules and model data
      my @keys = keys %{$decoded};

      foreach my $type (sort @keys) {
         next if $type eq 'system';
         $countAll{'modules'}{$type}{'definitions'} += $decoded->{$type}{'noModel'} ? $decoded->{$type}{'noModel'} : 0;
         $countAll{'modules'}{$type}{'installations'} += 1;
         while ( my ($model, $count) = each( %{$decoded->{$type}}) ) { 
            next if($model eq "noModel");
            $countAll{'modules'}{$type}{'definitions'}         += $count; 
            next if($model eq "migratedData");
            $countAll{'models'}{$type}{$model}{'definitions'} += $count;
            $countAll{'models'}{$type}{$model}{'installations'}+= 1;
         }
      }
   }

   $dbh->disconnect();

   return ($updated,$started,$nodesTotal,$nodes12,%countAll);
}

# ---------- do the presentation ----------
# ---------- reached by browser access ----------

sub viewStatistics() {
   my $q = new CGI; 
   $q->charset('utf-8'); 
   if($data{type} && $data{type} eq "json") { # return result als JSON object
     my ($updated,$started,$nodesTotal,$nodes12,%countAll) = doAggregate();
    
     my $json = encode_json({updated    => $updated,
                             generated  => time()-$start,
                             started    => $started,
                             nodesTotal => $nodesTotal,
                             nodes12    => $nodes12,
                             data       => \%countAll
                       });
      print $q->header( -type => "application/json",
                        -Content_length => length($json)); # for gzip/deflate
      print $json;
   }
   else {
      print $q->redirect('statistics.html'); # redirect to HTML file
   }   
}



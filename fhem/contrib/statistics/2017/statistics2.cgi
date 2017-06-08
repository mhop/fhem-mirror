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

my $ua    = $ENV{HTTP_USER_AGENT};
   $ua  //= "";
my $geoip = $ENV{REMOTE_ADDR};
my %data  = Vars();

# database stuff
my $datadir  = "./data";
my $dbf      = "$datadir/fhem_statistics_2017.sqlite";
my $dsn      = "dbi:SQLite:dbname=$dbf";
my $dbh;
my $sth;
my $limit  = "datetime('now', '-12 months')";

# css stuff (to be changed for real use)
my $css    = "style.css";
  
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
      $res      = $decoded->{'continentcode'};
      $countAll{'geo'}{'continent'}{$res}++ if $res;
      $res      = $decoded->{'countryname'};
      $countAll{'geo'}{'countryname'}{$res}++ if $res;
      $res      = $decoded->{'regionname'};
      $countAll{'geo'}{'regionname'}{$res}++ if $res;
      ($decoded,$res) = (undef,undef);

      # process system data
      $decoded  = decode_json( $line[1] );
      $res      = $decoded->{'system'}{'os'};
      $countAll{'system'}{'os'}{$res}++;
      $res      = $decoded->{'system'}{'arch'};
      $countAll{'system'}{'arch'}{$res}++;
      $res      = $decoded->{'system'}{'perl'};
      $countAll{'system'}{'perl'}{$res}++;
      $res      = $decoded->{'system'}{'release'};
      $countAll{'system'}{'release'}{$res}++;
      ($decoded,$res) = (undef,undef);
      
      # process modules and model data
      $decoded  = decode_json( $line[1] );
      my @keys = keys %{$decoded};

      foreach my $type (sort @keys) {
         next if $type eq 'system';
         $countAll{'modules'}{$type} += $decoded->{$type}{'noModel'} ? $decoded->{$type}{'noModel'} : 0;
         while ( my ($model, $count) = each(%{$decoded->{$type}}) ) { 
            $countAll{'modules'}{$type}         += $count unless $model eq 'noModel';
            $countAll{'models'}{$type}{$model}  += $count unless $model eq 'noModel';
         }
      }
   }

   $dbh->disconnect();

   return ($updated,$started,$nodesTotal,$nodes12,%countAll);
}

# ---------- do the presentation ----------
# ---------- reached by browser access ----------

sub viewStatistics() {
   my ($updated,$started,$nodesTotal,$nodes12,%countAll) = doAggregate();
   my $countSystem  = $countAll{'system'};
   my $countGeo     = $countAll{'geo'};
   my $countModules = $countAll{'modules'};
   my $countModels  = $countAll{'models'};

   my $q = new CGI;
   print $q->header( "text/html" ),
         $q->start_html( -title   => "FHEM statistics 2017", 
                         -style   => {-src => $css}, 
                         -meta    => {'keywords' => 'fhem homeautomation statistics'},
         ),

         $q->h2( "FHEM statistics 2017 (experimental)" ),
         $q->p( "graphics to be implemented..." ),
         $q->hr,
         $q->p( "<b>Statistics database</b><br>created: $started, updated: $updated<br>".
                "entries (total): $nodesTotal, entries (12 months): $nodes12<br>".
                "Generation time: ".sprintf("%.3f",time()-$start)." seconds"),
#         $q->hr,
#         $q->p( "System info <br>".            Dumper $countSystem ),
#         $q->p( "GeoIP info <br>".             Dumper $countGeo ),
#         $q->p( "Modules info <br>".           Dumper $countModules ),
#         $q->p( "Models per module info <br>". Dumper $countModels ),

         $q->end_html;
}

1;

#

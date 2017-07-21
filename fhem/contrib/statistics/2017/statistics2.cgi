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
use DBI;
use CGI qw(:standard Vars);
#use Data::Dumper;
use JSON;
use POSIX qw(mktime);
use Time::HiRes qw(time);

use lib "./lib";
use Geo::IP;

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

# database stuff for statistics
my $datadir  = "./data";
my $dbf      = "$datadir/fhem_statistics_2017.sqlite";
my $dsn      = "dbi:SQLite:dbname=$dbf";
my $dbh;
my $sth;
my $limit  = "datetime('now', '-12 months')";

# path to working copy 
my $fhemPathSvn = '/opt/fhem';
  
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

  my $decoded  = decode_json($json);
  if (defined($decoded->{'system'}{'revision'})) {
     # replace revision number with revision date
     my $rev      = $decoded->{'system'}{'revision'} + 1;
     if($rev =~ /^\d+$/) {
       my $d = (split(/ /,qx(sudo -u rko /usr/bin/svn info -r $rev $fhemPathSvn|grep Date:)))[3];
       return undef unless (defined($d));
       my ($year,$mon,$mday) = split(/-/,$d);
       $decoded->{'system'}{'revdate'} = mktime(0,0,7,$mday,($mon-1),($year-1900),0,0,0);
       $json = encode_json $decoded;
     }
  }
  
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
   my $started    = substr($dbInfo->{'submissionsSince'},0,10);
   my $nodesTotal = $dbInfo->{'submissionsTotal'};
   my $nodes12    = 0;

   map { $countAll{system}{age}{$_} = 0; } (0,7,30,180,365,999);

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
      $res     =~ s/^v//;
      $countAll{'system'}{'perl'}{$res}++;

      $res      = $decoded->{'system'}{'release'};
      $countAll{'system'}{'release'}{$res}++;

      if (defined($decoded->{'system'}{'revdate'})){
         $res = $decoded->{'system'}{'revdate'};
#         my $age = sprintf("%.1f",(time - $res)/86400);
         my $age = int((time - $res)/86400);
         $countAll{'system'}{'age'}{'0'}++   if ($age <= 1);
         $countAll{'system'}{'age'}{'7'}++   if ($age > 1  && $age <= 7);
         $countAll{'system'}{'age'}{'30'}++  if ($age > 7  && $age <= 30);
         $countAll{'system'}{'age'}{'180'}++ if ($age > 30 && $age <= 180);
         $countAll{'system'}{'age'}{'365'}++ if ($age > 180 && $age <= 366);
         $countAll{'system'}{'age'}{'999'}++ if ($age > 366); 
      } 
      
      $res = undef;
      
      # process modules and model data
      my @keys = keys %{$decoded};

      foreach my $type (sort @keys) {
         next if $type eq 'system';
         $countAll{'modules'}{$type}{'definitions'} += $decoded->{$type}{'noModel'} ? $decoded->{$type}{'noModel'} : 0;
         $countAll{'modules'}{$type}{'installations'} += 1;
         while ( my ($model, $count) = each( %{$decoded->{$type}}) ) { 
            next if($model eq "noModel");
            $countAll{'modules'}{$type}{'definitions'} += $count; 
            next if($model eq "migratedData");
            $countAll{'models'}{$type}{$model}{'definitions'} += $count;
            $countAll{'models'}{$type}{$model}{'installations'} += 1;
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
   } else {
      print $q->redirect('statistics.html'); # redirect to HTML file
   }
}



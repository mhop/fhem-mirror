#!/usr/bin/perl -w
# $Id$
use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use DBI;
use Geo::IP;
use JSON;
use CGI qw(:standard Vars);

sub insertDB();
sub viewStatistics();
sub getLocation();
sub countDB();

my $ua    = $ENV{HTTP_USER_AGENT};
my $geoip = $ENV{REMOTE_ADDR};
my %data  = Vars();

# directory cointains databases
my $datadir  = "./data";
my $dbf      = "$datadir/fhem_statistics.sqlite";
my $dsn      = "dbi:SQLite:dbname=$dbf";
my $sth;
  
if(index($ua,"FHEM") > -1) {
  insertDB();
  print header("application/x-www-form-urlencoded");
  print "==> ok";
} else {
  viewStatistics();
}

sub insertDB() {
  my $uniqueID = $data{uniqueID};
  my $json     = $data{json};
  my $geo      = getLocation();

  my $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
          die "Cannot connect: $DBI::errstr";
  $sth = $dbh->prepare(q{INSERT OR REPLACE INTO jsonNodes(uniqueID,geo,json) VALUES(?,?,?)});
  $sth->execute($uniqueID,$geo,$json);
  $dbh->disconnect();
}

sub viewStatistics() {

   my $q = new CGI;
   my $timestamp = localtime;

   print $q->header( "text/html" ),
         $q->start_html( -title   => "FHEM statistics 2017", 
                         -bgcolor => "#ffffff" ),
         $q->h2( "FHEM statistics 2017" ),
         $q->hr,
         $q->p( "to be implemented..." ),
         $q->p("Statistics database contains ".countDB()." entries."),
         $q->end_html;
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

sub countDB() {
   my $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
          die "Cannot connect: $DBI::errstr";
   my $count = $dbh->selectrow_array("SELECT count (*) from jsonNodes");
   $dbh->disconnect();
   return $count-1; # without the creation entry
}


1;

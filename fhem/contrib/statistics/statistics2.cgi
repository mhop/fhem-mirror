#!/usr/bin/perl -w
# $Id$
use strict;
use warnings;
use Time::HiRes qw(time);
use DBI;
use Geo::IP;
use JSON;
use CGI qw(:standard Vars);

use Data::Dumper;

sub insertDB();
sub getLocation();
sub doAggregate();
sub viewStatistics();

my $start = time();

my $ua    = $ENV{HTTP_USER_AGENT};
   $ua  //= "";
my $geoip = $ENV{REMOTE_ADDR};
my %data  = Vars();

# directory cointains databases
my $datadir  = "./data";
my $dbf      = "$datadir/fhem_statistics.sqlite";
my $dsn      = "dbi:SQLite:dbname=$dbf";
my $dbh;
my $sth;

my $css    = "style.css";
my $limit  = "datetime('now', '-12 months')";
#my $limit = "datetime('now', '-2 hour')";
  
# ---------- decide task ----------

if(index($ua,"FHEM") > -1) {
  insertDB();
  print header("application/x-www-form-urlencoded");
  print "==> ok";
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
  $sth->execute($uniqueID,$geo,$json);
  $dbh->disconnect();
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

# ---------- count everything for statistics ----------

sub doAggregate() {
   $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
          die "Cannot connect: $DBI::errstr";

   my $created = $dbh->selectrow_array("SELECT lastSeen from jsonNodes where uniqueID = 'databaseCreated'");

   my $sql = "SELECT geo,json FROM jsonNodes WHERE lastSeen > $limit AND uniqueID <> 'databaseCreated'";
   $sth = $dbh->prepare( $sql );
   $sth->execute();

   my (%countAll,$decoded,$nodes,$res);
   $nodes = 0;
   
   while (my @line = $sth->fetchrow_array()) {
      $nodes++;
      # process GeoIP data
      $decoded  = decode_json( $line[0] );
      $res      = $decoded->{'continentcode'};
      $countAll{'geo'}{'continent'}{$res}++;
      $res      = $decoded->{'countryname'};
      $countAll{'geo'}{'countryname'}{$res}++;
      $res      = $decoded->{'regionname'};
      $countAll{'geo'}{'regionname'}{$res}++;
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

   return ($created,$nodes,%countAll);
}

# ---------- do the presentation ----------
# ---------- reached by browser access ----------

sub viewStatistics() {
   my ($created,$count,%countAll) = doAggregate();
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
         $q->p( "Statistics database created $created contains $count entries (last 12 months)\n"),
         $q->p( "System info <br>".            Dumper $countSystem ),
         $q->p( "GeoIP info <br>".             Dumper $countGeo ),
         $q->p( "Modules info <br>".           Dumper $countModules ),
         $q->p( "Models per module info <br>". Dumper $countModels ),
         $q->hr,
         $q->p( "Generation time: ".sprintf("%.3f",time()-$start)." seconds" ),

         $q->end_html;
}

1;

#
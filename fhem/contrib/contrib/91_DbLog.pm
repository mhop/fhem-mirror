##############################################
# Example for logging KS300 data into a DB.
#
# Prerequisites:
# - The DBI and the DBD::<dbtype> modules must be installed.
# - a Database is created/configured
# - a db table: create table FHZLOG (TIMESTAMP varchar(20), TEMP varchar(5),
#                            HUM varchar(3), WIND varchar(4), RAIN varchar(8));
# - Change the content of the dbconn variable below
# - extend your FHEM config file with
#     notify .*H:.* {DbLog("@","%")}
# - copy this file into the <modpath>/FHEM and restart fhem.pl
# 
# If you want to change this setup, your starting point is the DbLog function 

my $dbconn = "Oracle:DBNAME:user:password";

package main;
use strict;
use warnings;
use DBI;

my $dbh;

sub DbDo($);
sub DbConnect();


################################################################
sub
DbLog_Initialize($)
{
  my ($hash) = @_;

  # Lets connect here, so we see the error at startup
  DbConnect();
}

################################################################
sub
DbLog($$)
{
  my ($a1, $a2) = @_;

  # a2 is like "T: 21.2  H: 37  W: 0.0  R: 0.0 IR: no"
  my @a = split(" ", $a2);
  my $tm = TimeNow();
  
  DbDo("insert into FHZLOG (TIMESTAMP, TEMP, HUM, WIND, RAIN) values " .
         "('$tm', '$a[1]', '$a[3]', '$a[5]', '$a[7]')");
}


################################################################
sub
DbConnect()
{
  return 1 if($dbh);
  Log 5, "Connecting to database $dbconn";
  my @a = split(":",  $dbconn);
  $dbh = DBI->connect("dbi:$a[0]:$a[1]", $a[2], $a[3]);
  if(!$dbh) {
    Log 1, "Can't connect to $a[1]: $DBI::errstr";
    return 0;
  }
  Log 5, "Connection to db $a[1] established";
  return 1;
}

################################################################
sub
DbDo($)
{
  my $str = shift;

  return 0 if(!DbConnect());
  Log 5, "Executing $str";
  my $sth = $dbh->do($str);
  if(!$sth) {
    Log 2, "DB: " . $DBI::errstr;
    $dbh->disconnect;
    $dbh = 0;
   return 0 if(!DbConnect());
#retry
    $sth = $dbh->do($str);
    if($sth)
      {
      Log 2, "Retry ok: $str";
      return 1;
      }
#
    return 0;
  }
  return 1;
}

1;

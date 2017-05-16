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

=pod
=begin html

<a name="DbLog"></a>
<h3>DbLog</h3>
<ul>
  <br>

  <a name="DbLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

    Log events to a database. The database connection is defined in
    <code>&lt;configfilename&gt;</code> (see sample configuration file
    <code>db.conf</code>). The configuration is stored in a separate file
    to avoid storing the password in the main configuration file and to have it
    visible in the output of the <a href="#list">list</a> command.
    <br><br>

    You must have <code>93_DbLog.pm</code> in the <code>FHEM</code> subdirectory
    to make this work. Additionally, the modules <code>DBI</code> and
    <code>DBD::&lt;dbtype&gt;</code> need to be installed (use
    <code>cpan -i &lt;module&gt;</code> if your distribution does not have it).
    <br><br>
    <code>&lt;regexp&gt;</code> is the same as in <a href="#FileLog">FileLog</a>.
    <br><br>
    Sample code to create a MySQL database is in <code>fhemdb_create.sql</code>.
    The database contains two tables: <code>current</code> and
    <code>history</code>. The latter contains all events whereas the former only
    contains the last event for any given reading and device.
    The columns have the following meaning:
    <ol>
    <li>TIMESTAMP: timestamp of event, e.g. <code>2007-12-30 21:45:22</code></li>
    <li>DEVICE: device name, e.g. <code>Wetterstation</code></li>
    <li>TYPE: device type, e.g. <code>KS300</code></li>
    <li>EVENT: event specification as full string,
                                        e.g. <code>humidity: 71 (%)</code></li>
    <li>READING: name of reading extracted from event,
                    e.g. <code>humidity</code></li>
    <li>VALUE: actual reading extracted from event,
                    e.g. <code>71</code></li>
    <li>UNIT: unit extracted from event, e.g. <code>%</code></li>
    </ol>
    The content of VALUE is optimized for automated post-processing, e.g.
    <code>yes</code> is translated to <code>1</code>.
    <br><br>
    The current values can be retrieved by means of the perl script
    <code>fhemdb_get.pl</code>. Its output is adapted to what a
    <a href="www.cacti.net">Cacti</a> data input method expects.
    Call <code>fhemdb_get.pl</code> without parameters to see the usage
    information.
    <br><br>
    Examples:
    <ul>
        <code># log everything to database</code><br>
        <code>define logdb DbLog /etc/fhem/db.conf .*:.*</code>
    </ul>
  </ul>


  <a name="DbLogset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="DbLogget"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a name="DbLogattr"></a>
  <b>Attributes</b> <ul>N/A</ul><br>

</ul>

=end html
=cut

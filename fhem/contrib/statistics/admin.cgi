#!/usr/bin/perl -w
################################################################
# $Id:$
# vim: ts=2:et
#
#  (c) 2012 Copyright: Martin Fischer (m_fischer at gmx dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
################################################################
use CGI qw(:standard :html3 :header Vars);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser carpout);
use CGI::Session;
use DBI; #requires libdbd-sqlite3-perl
use File::Copy;
use LWP::Simple;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use lib "./lib";
use Geo::IP;
use strict;
use warnings;
no warnings 'uninitialized';

# directory cointains databases
my $datadir = "./data";

# geo ip database file from http://www.maxmind.com/download/geoip/database/
# should be updated once per month
my $geoIPDat = "$datadir/GeoLiteCity.dat";

# database
my $dbf = "$datadir/fhem_statistics_db.sqlite";
my $dsn = "dbi:SQLite:dbname=$dbf";
my $sth;

# requirements for housekeeping;
my $controlFileURL = "http://fhem.de/fhemupdate4/svn/controls_fhem.txt";

# fhem node
my $ua = $ENV{HTTP_USER_AGENT};
my $ip = $ENV{REMOTE_ADDR};

# cascading style sheets
my $css = "http://fhem.de/../css/style.css";
my $myStyle=<<END;
ul.menu {
  margin: 0;
  padding: 0;
}

ul.menu li {
  list-style: none;
  display: inline;
  margin: 0;
  padding-right: 2px;
}
END

my $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
  die "Cannot connect: $DBI::errstr";

my $cgi = new CGI;
my $session = new CGI::Session(undef, $cgi, {Directory=>'/tmp'});

my $cookie = $cgi->cookie(CGISESSID => $session->id );

&init($cgi,$session);

if($session->param("~login-trials") >= 3) {
  print $cgi->header(),
        $cgi->start_html(
          -title  => 'fhem.de - Statistics Maintainance mode',
          -author => 'm_fischer@gmx.de',
          -base   => 'true',
          -style  => {-src => $css,-code => $myStyle},
        ),
        $cgi->p("You failed 3 times in a row.<br>" .
                "Your session is blocked. Please contact us with the details of your action"
        ),
        $cgi->end_html;
  exit(0);
}

unless($session->param("~logged-in")) {
  print login_page($cgi,$session);
  exit(0);
}

&maintainance($cgi,$session);

exit(0);

########################################
sub login_page {
  my ($cgi,$session) = @_;
  print $cgi->header(-cookie=>$cookie),
        $cgi->start_html(
          -title  => 'fhem.de - Statistics Maintainance mode',
          -author => 'm_fischer@gmx.de',
          -base   => 'true',
          -style  => {-src => $css,-code => $myStyle},
          ),
        $cgi->h3("fhem.de - Statistics Maintainance mode"),
        $cgi->start_form,
          $cgi->hidden(-name=>'_cmd',-value=>$cgi->param('_cmd')),
          $cgi->hidden(-name=>'_act',-value=>$cgi->param('_act')),
          $cgi->strong("<code>Username: </code>"),
          $cgi->textfield(-name=>'username'),br,
          $cgi->strong("<code>Password: </code>"),
          $cgi->password_field(-name=>'password'),br,
          $cgi->submit(-value=>'Login'),
          $cgi->end_form,
        $cgi->end_html;
}

########################################
sub init($$) {
  my ($cgi,$session) = @_;

  if($session->param("~logged-in")) {
    return 1;
  }

  my $username = $cgi->param("username") or return;
  my $password = $cgi->param("password") or return;

  if(my $profile = authUser($username,$password)) {
    $session->param("~profile", $profile);
    $session->param("~logged-in", 1);
    $session->clear(["~login-trials"]);
    return 1;
  }

  my $trials = $session->param("~login-trials") || 0;
  return $session->param("~login-trials", ++$trials);
}

########################################
sub authUser($$) {
  my ($username,$password) = @_;

  my %credentials;
  my $fh;
  if(open($fh,"<$datadir/.maintainance.pwd")) {
    while (my $line = <$fh>) {
      chomp $line;
      my ($user,$pass) = split(":",$line);
      $credentials{$user} = $pass;
    }
    close $fh;
  }

  if(exists $credentials{$username} &&
     crypt($password,"Fhem") eq $credentials{$username}) {
      my $p_mask = "x" . length($credentials{$username});
      return {username=>$username, password=>$p_mask};
  }
  return undef;
}

########################################
sub maintainance($$) {
  my ($cgi,$session) = @_;
  my $url = url(-path_info=>1);
  my $profile = $session->param("~profile");
  my @geo = getLocation($ip);
    
  if($cgi->param("_file")) {
    &cmdDownload($cgi,$session,param("_file"));
  }

  print $cgi->header(),
        $cgi->start_html(
          -title  => 'fhem.de - Statistics Maintainance mode',
          -author => 'm_fischer@gmx.de',
          -base   => 'true',
          -style  => {-src => $css,-code => $myStyle},
        ),
        $cgi->h3("fhem.de - Statistics Maintainance mode");

  print $cgi->p("Welcome $profile->{username} ..."),
        $cgi->p("IP: $ip, countryname:$geo[2] city:$geo[5] lat:$geo[6] lon:$geo[7]"),
        $cgi->ul({-class=>'menu'},
          $cgi->li([
            "<span>[</span>",
            $cgi->a({href=>$url},"home"),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=backup"},"backup"),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=dir"},"dir"),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=housekeeping"},"housekeeping"),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=update"},"update"),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=help"},"help"),
            "<span>|</span>",
            $cgi->a({href=>"http://fhem.de/stats/statistics.cgi",-target=>'_blank'},"view statistics"),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=logout"},"logout"),
            "<span>]</span>",
          ])
        ),
        $cgi->hr;

  my $cmd = $cgi->param("_cmd");
  my $act = $cgi->param("_act");

  if($cmd) {

    my $error;
    my @t = localtime;
    my $timeNow = sprintf("%04d%02d%02d-%02d%02d%02d",$t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
    my $ret;

    if($cmd eq "help") {
      &cmdHelp($cgi,$session);
    } elsif($cmd eq "backup") {
      &cmdBackup($cgi,$session,$act);
    } elsif($cmd eq "dir") {
      &cmdDir($cgi,$session);
    } elsif($cmd eq "housekeeping") {
      &cmdHousekeeping($cgi,$session,$act);
    } elsif($cmd eq "update") {
      &cmdUpdate($cgi,$session,$act);
    } elsif($cmd eq "logout") {
      $session->clear(["~logged-in"]);
      print "<META HTTP-EQUIV=refresh CONTENT=\"1;URL=$url\">\n";
    }

    if($error) {
      print $cgi->p("Error: $error");
    }

  }

  print end_html;

}

########################################
sub cmdHelp($$) {
  my ($cgi,$session) = @_;

  print $cgi->h4("Help"),
  $cgi->table({-border=>0,-cellpadding=>'5'},
    $cgi->Tr({-align=>'left',-valign=>'top'},
      [
        $cgi->th([
          "command",
          "action",
          "short description"
        ]),
        $cgi->td([
          "<code>help</code>",
          "",
          "<code>show this info.</code>"
        ]),
        $cgi->td([
          "<code>backup</code>",
          "<code>statistics</code>",
          "<code>backup statisitc database with timestamp extension</code>"
        ]),
        $cgi->td([
          "<code>backup</code>",
          "<code>geoip</code>",
          "<code>backup geoip databae with timestamp extension</code>"
        ]),
        $cgi->td([
          "<code>dir</code>",
          "",
          "<code>show content of datadir '$datadir'</code>"
        ]),
        $cgi->td([
          "<code>housekeeping</code>",
          "<code>modules</code>",
          "<code>get controlfile from '$controlFileURL' and remove inofficial modules from table 'modules'</code>"
        ]),
        $cgi->td([
          "<code>update</code>",
          "<code>geoip</code>",
          "<code>get new version of geoip database 'GeoLiteCity.dat', unzip and install it.</code>"
        ]),
      ]
    )
  );
  return undef;
}

########################################
sub cmdBackup($$$) {
  my ($cgi,$session,$act) = @_;
  my $url = url(-path_info=>1);
  my $timeNow = TimeNow();
  my $error;

  print $cgi->h4("Backup"),
        $cgi->ul({-class=>'menu'},
          $cgi->li([
            "<span>[</span>",
            $cgi->a({href=>$url."?_cmd=backup;_act=statistics"},"statistics database "),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=backup;_act=geoip"},"geoip database "),
            "<span>|</span>",
            $cgi->a({href=>$url."?_cmd=backup;_act=download;_file=$dbf"},"download statistics database "),
            "<span>]</span>",
          ])
        );

  if($act eq "statistics") {
    print $cgi->h5("backup $dbf");
    copy($dbf,$dbf."-".$timeNow) or $error = "Copy failed: $!";
    print $cgi->p("<code>copy $dbf to $dbf-$timeNow done.</code>");
  }

  if($act eq "geoip") {
    print $cgi->h5("backup $geoIPDat");
    copy($geoIPDat,$geoIPDat."-".$timeNow) or $error = "Copy failed: $!";
    print $cgi->p("<code>copy $geoIPDat to $geoIPDat-$timeNow done.</code>");
  }

  if($error) {
    print $cgi->p("Error: $error");
  }

  return undef;
}

########################################
sub cmdDownload($$$) {
  my ($cgi,$session,$file) = @_;
  my $error;

  my $filename = substr $file,rindex($file,'/')+1;
  open(my $DLFILE,"<$file") or $error = "Open failed: $!";

  print $cgi->header(-type => 'application/x-download',
                     -attachment => $filename,
                     -Content_length => -s "$file",
  );
 
  binmode $DLFILE;
  print while <$DLFILE>;
  undef ($DLFILE);

  if($error) {
    print $cgi->p("Error: $error");
  }
  
}

########################################
sub cmdDir($$$) {
  my ($cgi,$session,$act) = @_;
  my $error;

  print $cgi->h4("Content of directory $datadir");

  opendir(my $dh, $datadir) or $error = "Can't opendir $datadir: $!";
  my @dir = grep { !/^\./ && -f "$datadir/$_" } readdir($dh);
  closedir $dh;

  for my $file (sort @dir) {
    print $cgi->code($file),$cgi->br;
  }

  if($error) {
    print $cgi->p("Error: $error");
  }

  return undef;
}

########################################
sub cmdUpdate($$$) {
  my ($cgi,$session,$act) = @_;
  my $url = url(-path_info=>1);
  my $timeNow = TimeNow();
  my $error;

  print $cgi->h4("Update"),
        $cgi->ul({-class=>'menu'},
          $cgi->li([
            "<span>[</span>",
            $cgi->a({href=>$url."?_cmd=update;_act=geoip"},"GeoLiteCity.dat"),
            "<span>]</span>",
          ])
        );

  if($act eq "geoip") {
    print $cgi->h5("update GeoLiteCity.dat");

    my $url = "http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz";
    my $infile = "$datadir/GeoLiteCity.dat.gz";
    my $outfile = "$datadir/GeoLiteCity.dat";
    my $data = getstore($url,$infile);

    if($data == "200") {
      copy($geoIPDat,$geoIPDat."-".$timeNow) or $error = "Copy failed: $!";
      print $cgi->p("<code>copy $geoIPDat to $geoIPDat-$timeNow done.</code>");
      gunzip $infile => $outfile or $error = "gunzip failed: $GunzipError";
      print $cgi->p("<code>New $outfile installed.</code>");
    } else {
      $error = "response for $infile: $data";
    }
  }

  if($error) {
    print $cgi->p("Error: $error");
  }

  return undef;
}

########################################
sub cmdHousekeeping($$$) {
  my ($cgi,$session,$act) = @_;
  my $url = url(-path_info=>1);
  my $error;

  print $cgi->h4("Housekeeping"),
        $cgi->ul({-class=>'menu'},
          $cgi->li([
            "<span>[</span>",
            $cgi->a({href=>$url."?_cmd=housekeeping;_act=modules"},"remove inofficial modules"),
            "<span>]</span>",
          ])
        );

  if($act eq "modules") {

    my $control = get($controlFileURL);
    my $control_ref = {};
    ($error,$control_ref) = parseControlFile("fhem",$control,$control_ref,0);

    print $cgi->h5("Housekeeping for table 'modules'");
    my @ignoreColumns = qw(Global uniqueID);

    my %columnOld = %{ $dbh->column_info(undef, undef, 'modules', undef)->fetchall_hashref('COLUMN_NAME') };
    my %columnNew = %columnOld;

    my $removeColumns;
    foreach my $col (sort keys %columnOld) {
      if(!exists $control_ref->{$col} && !grep {/$col/} @ignoreColumns) {
        delete $columnNew{$col};
        $removeColumns .= "$col ";
      }
    }

    if(!$removeColumns) {
      print $cgi->p("<p><code>inofficial modules found:<br />none</code>");
    } else {
      print $cgi->p("<p><code>inofficial modules found:<br />$removeColumns</code>");

      copy($dbf,$dbf."-".TimeNow()) or $error = "Copy of $dbf failed: $!";

      if(!$error) {
        delete $columnNew{uniqueID};
        my $createTable = "CREATE TABLE modules (uniqueID VARCHAR(32) PRIMARY KEY UNIQUE";
        my $selectColumns = "uniqueID";
        foreach my $col (sort keys %columnNew) {
          $createTable .= ", $col INTEGER DEFAULT 0";
          $selectColumns .= ", $col";
        }
        $createTable .= ");";

        my $sql;
        $sql = "ALTER TABLE 'modules' RENAME TO 'modules_old';";
        print $cgi->p("<code>sql:<br />$sql</code>");
        $dbh->do($sql);

        $sql = $createTable;
        print $cgi->p("<code>sql:<br />$sql</code>");
        $dbh->do($sql);

        $sql = "INSERT INTO 'modules' ($selectColumns) SELECT $selectColumns FROM 'modules_old';";
        print $cgi->p("<code>sql:<br />$sql</code>");
        $dbh->do($sql);

        $sql = "DROP TABLE 'modules_old';";
        print $cgi->p("<code>sql:<br />$sql</code>");
        $dbh->do($sql);
      }
    }
  }

  if($error) {
    print $cgi->p("Error: $error");
  }

  return undef;
}

########################################
sub parseControlFile($$$$) {
  my ($pack,$controlFile,$control_ref,$local) = @_;
  my %control = %$control_ref if ($control_ref && ref($control_ref) eq "HASH");
  my $from = ($local ? "local" : "remote");
  my $ret;

  if ($local) {
    my $str = "";
    # read local controlfile in string
    if (open FH, "$controlFile") {
      $str = do { local $/; <FH> };
    }
    close(FH);
    $controlFile = $str
  }
  # parse file
  if ($controlFile) {
    foreach my $l (split("[\r\n]", $controlFile)) {
      chomp($l);
      my ($ctrl,$date,$size,$file,$move) = "";
      if ($l =~ m/^(UPD) (20\d\d-\d\d-\d\d_\d\d:\d\d:\d\d) (\d+) (\S+)$/) {
        $ctrl = $1;
        $date = $2;
        $size = $3;
        $file = $4;
      } elsif ($l =~ m/^(DIR) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
      } elsif ($l =~ m/^(MOV) (\S+) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
        $move = $3;
      } elsif ($l =~ m/^(DEL) (\S+)$/) {
        $ctrl = $1;
        $file = $2;
      } else {
        $ctrl = "ESC"
      }
      if ($ctrl eq "ESC") {
        $ret = "File 'controls_".lc($pack).".txt' ($from) is corrupt";
      }
      last if ($ret);
      if ($l =~ m/^UPD/ && $file =~ m/^FHEM/) {
        if ($file =~ m/^.*(\d\d_)(.*).pm$/) {
          my $modName = $2;
          $control{$modName} = $file;
        }
      }
    }
  }
  return ($ret, \%control);
}

########################################
sub getLocation($) {
  my ($ip) = shift;
  my $gi = Geo::IP->open($geoIPDat, GEOIP_STANDARD);
  my $rec = $gi->record_by_addr($ip);

  if(!$rec) {
    return;
  } else {
    return (
      $rec->country_code,$rec->country_code3,$rec->country_name,$rec->region,$rec->region_name,$rec->city,
      $rec->latitude,$rec->longitude,$rec->time_zone,$rec->continent_code
    );
  }
}

########################################
sub TimeNow() {
  my @t = localtime;
  return sprintf("%04d%02d%02d-%02d%02d%02d",$t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
}

1;

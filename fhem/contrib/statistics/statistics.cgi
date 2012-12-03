#!/usr/bin/perl -w
################################################################
# $Id$
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
use CGI qw(:standard Vars);
use CGI::Carp qw(warningsToBrowser fatalsToBrowser);
use DBI; #requires libdbd-sqlite3-perl
use lib "./lib";
use Geo::IP;
use strict;
use warnings;
no warnings 'uninitialized';

sub createDB();
sub insertDB();
sub checkColumn($$);
sub getLocation($);
sub googleVisualizationLib($);
sub drawMarkersMap(@);
sub drawPieChart(@);
sub drawRegionsMap(@);
sub drawTable(@);
sub drawColumnChartTop10Modules(@);
sub drawColumnChartTop10ModDef(@);
sub drawBarChartModules(@);
sub viewStatistics();

# cascading style sheet
my $css = "http://fhem.de/../css/style.css";

# exclude modules from top 10 graph
my $excludeFromTop10modules = "at autocreate notify telnet weblink FileLog SUNRISE_EL";
my $excludeFromTop10definitions = "at autocreate notify telnet weblink FileLog SUNRISE_EL";

# geo ip database file from http://www.maxmind.com/download/geoip/database/
# should be updated once per month
my $geoIPDat = "./data/GeoLiteCity.dat";

# database
my $dbf = "./data/fhem_statistics_db.sqlite";
my $dsn = "dbi:SQLite:dbname=$dbf";
my $sth;

# fhem node
my $ua = $ENV{HTTP_USER_AGENT};
my $ip = $ENV{REMOTE_ADDR};
my %data = Vars();

# create database if not exists
createDB() if (! -e $dbf);

my $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
  die "Cannot connect: $DBI::errstr";

if(index($ua,"Fhem") > -1) {
  print header("application/x-www-form-urlencoded");
  insertDB();
  print "==> ok";
} else {
  viewStatistics();
}

sub viewStatistics() {
  my $visLib        = googleVisualizationLib("'corechart','geochart','table'");
  my $cOS           = drawPieChart("nodes","os","Operating System",390,300,"chart_os");
  my $cArch         = drawPieChart("nodes","arch","Architecture",390,300,"chart_arch");
  my $cRelease      = drawPieChart("nodes","release","FHEM Release",390,300,"chart_release");
  my $cPerl         = drawPieChart("nodes","perl","Perl Version",390,300,"chart_perl");
  my $cModulesTop10 = drawColumnChartTop10Modules("modules","modulestop10",,"Used",800,300,"chart_modulestop10");
  my $cModDefTop10  = drawColumnChartTop10ModDef("modules","definitions","Definitions",800,300,"chart_moddeftop10");
  #my $cModules      = drawBarChartModules("modules","modules","Used","Definitions",800,600,"chart_modules");
  my $mWorld        = drawRegionsMap("locations","countryname","world","map_world");
  my $mEU           = drawRegionsMap("locations","countryname","150","map_europe");
  my $mWesternEU    = drawMarkersMap("locations","city","155","map_germany");
  my $tModules      = drawTable3cols("modules","total_modules","string","Module","number","Used","number","Definitions","table_modules");
  #my $tModDef       = drawTable("modules","total_moddef","string","Module","number","Definitions","table_moddef");
  my $tModels       = drawTable2cols("models","total_models","string","Model","boolean","defined","table_models");
  my @res = $dbh->selectrow_array("SELECT created FROM db");
  my $since = "@res";

  print header;
  print start_html(
        -title  => 'fhem.de - Statistics',
        -author => 'm_fischer@gmx.de',
        -base   => 'true',
        -style  => {-src => $css},
        -meta   => {'keywords' => 'fhem houseautomation statistics'},
        -script => [
                      { -type => 'text/javascript',
                        -src  => 'https://www.google.com/jsapi',
                      },
                      $visLib,
                      $cOS, $cArch, $cRelease, $cPerl,
                      $cModulesTop10, $cModDefTop10,
                      #$cModules,
                      $mWorld, $mEU, $mWesternEU,
                      $tModules, $tModels,
                   ],
  );

  my ($nodes) = $dbh->selectrow_array("SELECT COUNT(uniqueID) FROM nodes");

  print <<END;
  <div id="logo"></div>
  <div id="menu">
    <table><tbody><tr><td>
    <table id="room">
      <tr><td></td></tr>
      <tr><td><b>back to</b></td></tr>
      <tr><td></td></tr> 
      <tr><td><a href="http://fhem.de">Homepage</a></td></tr>
      <tr><td></td></tr>
    </tbody></table>
    </td></tr></tbody></table>
  </div>

  <div id="right">
    <noscript>
      <div style="text-align:center; border: 2px solid red; background: #D7FFFF;">
        <div style="text-align:center; background: #D7FFFF; color: red;">
          <h4>Please enable Javascript on your Browser!</h4>
        </div>
      </div>
    </noscript>

    <h3>Fhem Statistics ($nodes submissions since $since)</h3>
    <h4>Installed on...</h4>
    <div id="chart_os" style="float:left; border: 1px solid black; margin-right:18px;"></div>
    <div id="chart_arch" style="float:left; border: 1px solid black;"></div>
    <div style="clear:both;"></div>

    <h4>Versions...</h4>
    <div id="chart_release" style="float:left; border: 1px solid black; margin-right:18px;"></div>
    <div id="chart_perl" style="float:left; border: 1px solid black;"></div>
    <div style="clear:both;"></div>

    <h4>Top 10 of most commonly used modules<small><sup>1</sup></small>...</h4>
    <div id="chart_modulestop10" style="width: 800px; height: 300px; border: 1px solid black;"></div>
    <small><sup>1</sup> excluded from graph: $excludeFromTop10modules</small>

    <h4>Top 10 of total definitions by module<small><sup>1</sup></small>...</h4>
    <div id="chart_moddeftop10" style="width: 800px; height: 300px; border: 1px solid black;"></div>
    <small><sup>1</sup> excluded from graph: $excludeFromTop10definitions</small>

<!--
//    <h4>Top 20 of most commonly used modules (with total definitions by module)...</h4>
//    <div id="chart_modules" style="width: 825px; height: 600px; border: 1px solid black;"></div>
//-->

    <h4>Locations worldwide...</h4>
    <div id="map_world" style="width: 800px; height: 500px; border: 1px solid black;"></div>

    <h4>Locations in Europe...</h4>
    <div id="map_europe" style="width: 800px; height: 500px; border: 1px solid black;"></div>

    <h4>Locations in Western Europe...</h4>
    <div id="map_germany" style="width: 800px; height: 500px; border: 1px solid black;"></div>

    <div style="float:left; width: 390px; margin-right:20px;">
      <h4>List of total used modules (with definitions)...</h4>
      <div id="table_modules" style="width: 390px; border: 1px solid black;"></div>
      <small><strong>Note:</strong> Click on a column header for sorting</small>
    </div>

    <div style="float:left; width: 390px;">
      <h4>List of defined models...</h4>
      <div id="table_models" style="width: 390px; border: 1px solid black;"></div>
      <small><strong>Note:</strong> Click on a column header for sorting</small>
    </div>
    <div style="clear:both;"></div>

    <div id="footer" style="position:relative; left: -100px; text-align: center;">
      <p><small>Layout by M. Fischer - Click <a href="http://www.fischer-net.de/kontakt.html">here</a> to leave your comments.</small></p>
    </div>
  </div>
END
  print end_html;
}

sub googleVisualizationLib($) {
  my $packages = shift;
  my $code =<<END;
// Load the Visualization API library
google.load('visualization', '1.0', {'packages':[$packages]});
END
  return $code;
}

sub drawPieChart(@) {
  my ($table,$column,$title,$width,$height,$divID) = @_;
  my $res = $dbh->selectall_arrayref("SELECT DISTINCT $column FROM $table ORDER BY $column ASC");

  my %hash = ();
  foreach my $row (@$res) {
    my ($value) = @$row;
    my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM $table WHERE $column = '$value'");
    $hash{$value} = $count;
  }

  my $addRows;
  foreach my $value (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    $addRows .= "\t['$value',$hash{$value}],\n";
  }
  chop($addRows);

  my $code =<<END;
  google.setOnLoadCallback(drawChart_$column);

  function drawChart_$column() {
    var data = new google.visualization.DataTable();
    data.addColumn('string', 'Topping');
    data.addColumn('number', 'Slices');
    data.addRows([
    $addRows
    ]);

    var options = {
      title     : '$title',
      width     : $width,
      height    : $height,
      is3D      : true,
      tooltip   : { showColorCode: true, },
      chartArea : { height:'80%',width:'95%', },
    };

    var chart = new google.visualization.PieChart(document.getElementById('$divID'));
    chart.draw(data, options);
  };
END

  return $code;
}

sub drawColumnChartTop10Modules(@) {
  my ($table,$postfix,$rowtitle,$width,$height,$divID) = @_;
  $sth = $dbh->prepare("SELECT * FROM $table where 1=0");
  $sth->execute();
  my $res = $sth->{NAME};
  $sth->finish;

  my %hash = ();
  foreach my $column (@$res) {
    #my ($sum) = $dbh->selectrow_array("SELECT sum($column) FROM $table");
    my ($sum) = $dbh->selectrow_array("SELECT count($column) FROM $table WHERE $column != 0");
    $hash{$column} = $sum;
  }

  my $data;
  my $i=0;
  foreach my $column (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    next if($column eq "uniqueID");
    next if($excludeFromTop10modules =~ /$column/);
    $data .= "\t['$column',$hash{$column}],\n";
    $i++;
    last if($i == 10);
  }
  chop($data);

  my $code =<<END;
  google.setOnLoadCallback(drawChart_$postfix);
  function drawChart_$postfix() {
    var data = google.visualization.arrayToDataTable([
      ['Module','$rowtitle'],
    $data
    ]);

    var options = {
      // title  : 'title',
      legend    : { position:'none' },
      chartArea : { width:"90%" },
      fontSize  : 12,
      vAxis     : { minValue:0, },
    };

    var chart = new google.visualization.ColumnChart(document.getElementById('$divID'));
    chart.draw(data, options);
  };
END
  return $code;
}

sub drawColumnChartTop10ModDef(@) {
  my ($table,$postfix,$rowtitle,$width,$height,$divID) = @_;
  $sth = $dbh->prepare("SELECT * FROM $table where 1=0");
  $sth->execute();
  my $res = $sth->{NAME};
  $sth->finish;

  my %hash = ();
  foreach my $column (@$res) {
    my ($sum) = $dbh->selectrow_array("SELECT sum($column) FROM $table");
    $hash{$column} = $sum;
  }

  my $data;
  my $i=0;
  foreach my $column (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    next if($column eq "uniqueID");
    next if($excludeFromTop10definitions =~ /$column/);
    $data .= "\t['$column',$hash{$column}],\n";
    $i++;
    last if($i == 10);
  }
  chop($data);

  my $code =<<END;
  google.setOnLoadCallback(drawChart_$postfix);
  function drawChart_$postfix() {
    var data = google.visualization.arrayToDataTable([
      ['Module','$rowtitle'],
    $data
    ]);

    var options = {
      // title  : 'title',
      legend    : { position:'none' },
      chartArea : { width:"90%" },
      fontSize  : 12,
      vAxis     : { minValue:0, },
    };

    var chart = new google.visualization.ColumnChart(document.getElementById('$divID'));
    chart.draw(data, options);
  };
END
  return $code;
}

sub drawBarChartModules(@) {
  my ($table,$postfix,$row1title,$row2title,$width,$height,$divID) = @_;
  $sth = $dbh->prepare("SELECT * FROM $table where 1=0");
  $sth->execute();
  my $res = $sth->{NAME};
  $sth->finish;

  my %hash = ();
  foreach my $column (@$res) {
    next if($column eq "uniqueID");
    my ($count) = $dbh->selectrow_array("SELECT count($column) FROM $table WHERE $column != 0");
    my ($sum)   = $dbh->selectrow_array("SELECT sum($column) FROM $table");
    $hash{$column}{count} = $count;
    $hash{$column}{sum}   = $sum;
  }

  my $data;
  my $i=0;
  foreach my $column (sort {$hash{$b}{count} <=> $hash{$a}{count}} keys %hash) {
    $data .= "\t['$column',$hash{$column}{count},$hash{$column}{sum}],\n";
    $i++;
    last if($i == 20);
  }
  chop($data);

  my $code =<<END;
  google.setOnLoadCallback(drawChart_$postfix);
  function drawChart_$postfix() {
    var data = google.visualization.arrayToDataTable([
      ['Module','$row1title','$row2title'],
    $data
    ]);

    var options = {
      height    : $height,
      width     : $width,
      chartArea : {left:150,top:20,width:"65%",height:"90%"},
      // title  : 'title',
    };

    var chart = new google.visualization.BarChart(document.getElementById('$divID'));
    chart.draw(data, options);
  };
END
  return $code;
}

sub drawMarkersMap(@) {
  my ($table,$column,$region,$divID) = @_;
  my $res = $dbh->selectall_arrayref("SELECT DISTINCT $column FROM $table ORDER BY $column ASC");

  my %hash = ();
  foreach my $row (@$res) {
    my ($value) = @$row;
    my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM $table WHERE $column = '$value'");
    #$value = "Germany" if($value eq "");
    next if($value eq "");
    $hash{$value} = $count;
  }

  my $addRows;
  foreach my $value (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    $addRows .= "\t['$value',$hash{$value}],\n";
  }
  chop($addRows);

  my $code=<<END;
  google.setOnLoadCallback(drawMarkersMap_$region);

  function drawMarkersMap_$region() {
    var data = google.visualization.arrayToDataTable([
      ['City','Installations'],
      $addRows
    ]);

    var options = {
      region: '$region',
      displayMode: 'markers',
      colorAxis: {colors: ['gold', 'darkgreen']},
      backgroundColor : 'lightblue',
    };

    var chart = new google.visualization.GeoChart(document.getElementById('$divID'));
    chart.draw(data, options);
  };
END

  return $code;
}

sub drawRegionsMap(@) {
  my ($table,$column,$region,$divID) = @_;
  my $res = $dbh->selectall_arrayref("SELECT DISTINCT $column FROM $table ORDER BY $column ASC");

  my %hash = ();
  foreach my $row (@$res) {
    my ($value) = @$row;
    my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM $table WHERE $column = '$value'");
    $hash{$value} = $count;
  }

  my $addRows;
  foreach my $value (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    $addRows .= "\t['$value',$hash{$value}],\n";
  }
  chop($addRows);

  my $code=<<END;
  google.setOnLoadCallback(drawRegionsMap_$region);

  function drawRegionsMap_$region() {
    var data = google.visualization.arrayToDataTable([
      ['Country','Installations'],
      $addRows
    ]);

    var options = {
      region: '$region',
      // colorAxis: {colors: ['#FFFF80', 'darkgreen']},
      backgroundColor : 'lightblue',
    };

    var chart = new google.visualization.GeoChart(document.getElementById('$divID'));
    chart.draw(data, options);
  };
END
  return $code;
}

sub drawTable2cols(@) {
  my ($table,$postfix,$type1,$title1,$type2,$title2,$divID) = @_;
  $sth = $dbh->prepare("SELECT * FROM $table where 1=0");
  $sth->execute();
  my $res = $sth->{NAME};
  $sth->finish;

  my %hash = ();
  foreach my $column (@$res) {
    my ($sum) = $dbh->selectrow_array("SELECT sum(\"$column\") FROM $table");
    $hash{$column} = $sum;
  }

  my $data;
  if($type2 eq "boolean") {
    foreach my $column (sort keys %hash) {
      next if($column eq "uniqueID");
      $data .= "\t['$column',true],\n";
    }
  } else {
    foreach my $column (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
      next if($column eq "uniqueID");
      $data .= "\t['$column',$hash{$column}],\n";
    }
  }
  chop($data);

  my $code=<<END;
  google.setOnLoadCallback(drawTable_$postfix);
  function drawTable_$postfix() {
    var data = new google.visualization.DataTable();
    data.addColumn('$type1', '$title1');
    data.addColumn('$type2', '$title2');
    data.addRows([
    $data
    ]);

    var options = {
      showRowNumber : false,
      sortAscending : true,
      sortColumn    : 0,
      height        : 400,
    };

    var table = new google.visualization.Table(document.getElementById('$divID'));
    table.draw(data,options);
  };
END
  return $code;
}

sub drawTable3cols(@) {
  my ($table,$postfix,$type1,$title1,$type2,$title2,$type3,$title3,$divID) = @_;
  $sth = $dbh->prepare("SELECT * FROM $table where 1=0");
  $sth->execute();
  my $res = $sth->{NAME};
  $sth->finish;

  my %hash = ();
  foreach my $column (@$res) {
    my ($count) = $dbh->selectrow_array("SELECT count(\"$column\") FROM $table WHERE \"$column\" != 0");
    my ($sum)   = $dbh->selectrow_array("SELECT sum(\"$column\") FROM $table");
    $hash{$column}{count} = $count;
    $hash{$column}{sum}   = $sum;
  }

  my $data;
  foreach my $column (sort {$hash{$b} <=> $hash{$a}} keys %hash) {
    next if($column eq "uniqueID");
    $data .= "\t['$column',$hash{$column}{count},$hash{$column}{sum}],\n";
  }
  chop($data);

  my $code=<<END;
  google.setOnLoadCallback(drawTable_$postfix);
  function drawTable_$postfix() {
    var data = new google.visualization.DataTable();
    data.addColumn('$type1', '$title1');
    data.addColumn('$type2', '$title2');
    data.addColumn('$type3', '$title3');
    data.addRows([
    $data
    ]);

    var options = {
      showRowNumber : false,
      sortAscending : false,
      sortColumn    : 1,
      height        : 400,
    };

    var table = new google.visualization.Table(document.getElementById('$divID'));
    table.draw(data,options);
  };
END
  return $code;
}

sub createDB() {
  my $dbh = DBI->connect($dsn,"","", { RaiseError => 1, ShowErrorStatement => 1 }) ||
    die "Cannot connect: $DBI::errstr";
  $dbh->do("CREATE TABLE db (created TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
  $dbh->do("CREATE TABLE nodes (uniqueID VARCHAR(32) PRIMARY KEY UNIQUE, release VARCHAR(16), branch VARCHAR(32), os VARCHAR(32), arch VARCHAR(64), perl VARCHAR(16), lastSeen TIMESTAMP DEFAULT CURRENT_TIMESTAMP)");
  $dbh->do("CREATE TABLE locations (uniqueID VARCHAR(32) PRIMARY KEY UNIQUE, countrycode VARCHAR(2), countrycode3 VARCHAR(3), countryname VARCHAR(64), region CHAR(2) ,regionname VARCHAR(64), city VARCHAR(255), latitude FLOAT(8,6), longitude FLOAT(8,6), timezone VARCHAR(64), continentcode CHAR(2))");
  $dbh->do("CREATE TABLE modules (uniqueID VARCHAR(32) PRIMARY KEY UNIQUE)");
  $dbh->do("CREATE TABLE models (uniqueID VARCHAR(32) PRIMARY KEY UNIQUE)");
  $dbh->do("INSERT INTO db (created) VALUES (CURRENT_TIMESTAMP)");
  $dbh->disconnect();
  return;
}

sub insertDB() {
  my $uniqueID = $data{uniqueID};
  my $modules = $data{modules};
  my $models = $data{models};
  my $sth;

  # insert or update fhem node
  my ($release,$branch,$os,$arch,$perl);
  foreach (split(/\|/,$data{system})) {
    my ($k,$v) = split /:/;
    $release = $v if($k eq "Release");
    $branch  = $v if($k eq "Branch");
    $os      = $v if($k eq "OS");
    $arch    = $v if($k eq "Arch");
    $perl    = $v if($k eq "Perl");
  }
  $sth = $dbh->prepare(q{REPLACE INTO nodes (uniqueID,release,branch,os,arch,perl,lastSeen) VALUES(?,?,?,?,?,?,CURRENT_TIMESTAMP)});
  $sth->execute($uniqueID,$release,$branch,$os,$arch,$perl);

  # insert or update goe location of fhem node
#### TODO: sprachcode 84.191.75.195
  my @geo = getLocation($ip);

  if(@geo) {
    $sth = $dbh->prepare(q{REPLACE INTO locations (uniqueID,countrycode,countrycode3,countryname,region,regionname,city,latitude,longitude,timezone,continentcode) VALUES(?,?,?,?,?,?,?,?,?,?,?)});
    $sth->execute($uniqueID,$geo[0],$geo[1],$geo[2],$geo[3],$geo[4],$geo[5],$geo[6],$geo[7],$geo[8],$geo[9]);
  }

  # delete old modules of fhem node
  $sth = $dbh->prepare(q{DELETE FROM modules WHERE uniqueID=?});
  $sth->execute($uniqueID);

  # insert new modules of fhem node
  $sth = $dbh->prepare("INSERT INTO modules (uniqueID) VALUES (?)");
  $sth->execute($uniqueID);

  foreach (split(/\|/,$data{modules})) {
    my ($k,$v) = split /:/;
    checkColumn("modules",$k);

    $sth = $dbh->prepare("UPDATE modules SET '$k'='$v' WHERE uniqueID='$uniqueID'");
    $sth->execute();
  }

  if($data{models}) {
    # delete old models of fhem node
    $sth = $dbh->prepare(q{DELETE FROM models WHERE uniqueID=?});
    $sth->execute($uniqueID);

    # insert new modules of fhem node
    $sth = $dbh->prepare("INSERT INTO models (uniqueID) VALUES (?)");
    $sth->execute($uniqueID);

    foreach (split(/\|/,$data{models})) {
      my @models = split /,/;
      foreach my $m (@models) {
        checkColumn("models",$m);
        $sth = $dbh->prepare("UPDATE models SET '$m'='1' WHERE uniqueID='$uniqueID'");
        $sth->execute();
      }
    }
  }

  $sth->finish();
  $dbh->disconnect();
  
  return;
}

sub checkColumn($$) {
  my ($t,$k) = @_;

  # get table info
  $sth = $dbh->prepare("PRAGMA table_info($t)");
  $sth->execute();

  # check if column exists
  my @row;
  my @match = ();
  while (@row = $sth->fetchrow_array()) {
    @match = grep { /\b$k\b/ } @row;
    last if(@match != 0);
  }

  # create column if not exists
  if(@match == 0) {
    $sth = $dbh->prepare("ALTER TABLE $t ADD COLUMN '$k' INTEGER DEFAULT 0");
    $sth->execute();
  }
  $sth->finish;
  return;
}

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

1;

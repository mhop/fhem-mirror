
##############################################
# $Id$
#
# 93_DbLog.pm
# written by Dr. Boris Neubert 2007-12-30
# e-mail: omega at online dot de
#
# modified by Tobias Faust 2012-06-26
# e-mail: tobias dot faust at online dot de
#
##############################################

package main;
use strict;
use warnings;
use DBI;
use Data::Dumper;

sub DbLog($$$);

################################################################
sub
DbLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "DbLog_Define";
  $hash->{UndefFn}  = "DbLog_Undef";
  $hash->{NotifyFn} = "DbLog_Log";
  $hash->{GetFn}    = "DbLog_Get";
  $hash->{AttrFn}   = "DbLog_Attr";
  $hash->{AttrList} = "disable:0,1 DbLogType:Current,History,Current/History";

  addToAttrList("DbLogExclude");
}

###############################################################
sub
DbLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> DbLog configuration regexp"
    if(int(@a) != 4);

  my $regexp = $a[3];

  eval { "Hallo" =~ m/^$regexp$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $regexp;

  $hash->{CONFIGURATION}= $a[2];

  return "Can't connect to database." if(!DbLog_Connect($hash));

  $hash->{STATE} = "active";

  return undef;
}

#####################################
sub
DbLog_Undef($$)
{
  my ($hash, $name) = @_;
  my $dbh= $hash->{DBH};
  $dbh->disconnect() if(defined($dbh));
  return undef;
}

################################################################
#
# Wird bei jeder Aenderung eines Attributes dieser
# DbLog-Instanz aufgerufen
#
################################################################
sub
DbLog_Attr(@)
{
  my @a = @_;
  my $do = 0;

  if($a[0] eq "set" && $a[2] eq "disable") {
    $do = (!defined($a[3]) || $a[3]) ? 1 : 2;
  }
  $do = 2 if($a[0] eq "del" && (!$a[2] || $a[2] eq "disable"));
  return if(!$do);

  $defs{$a[1]}{STATE} = ($do == 1 ? "disabled" : "active");

  return undef;
}

################################################################
#
# Parsefunktion, abhaengig vom Devicetyp
#
################################################################
sub
DbLog_ParseEvent($$$)
{
  my ($device, $type, $event)= @_;
  my @result;

  # split the event into reading and argument
  # "day-temp: 22.0 (Celsius)" -> "day-temp", "22.0 (Celsius)"
  my @parts   = split(/: /,$event);
  my $reading = shift @parts;
  my $value   = join(": ", @parts);
  my $unit    = "";

  #default
  if(!defined($reading)) { $reading = ""; }
  if(!defined($value))   { $value   = ""; }
  if( $value eq "" ) {
    $reading= "state";
    $value= $event;
  }

  # the interpretation of the argument depends on the device type
  # EMEM, M232Counter, M232Voltage return plain numbers
  if(($type eq "M232Voltage") ||
     ($type eq "M232Counter") ||
     ($type eq "EMEM")) {
  }
  #OneWire 
  elsif(($type eq "OWMULTI")) {
    if(int(@parts)>1) {
      $reading = "data";
      $value = $event;
    } else {
      @parts = split(/\|/, AttrVal($device, $reading."VUnit", ""));
      $unit = $parts[1] if($parts[1]);
      if(lc($reading) =~ m/temp/) {
        $value=~ s/ \(Celsius\)//;
        $value=~ s/([-\.\d]+).*/$1/;
        $unit= "°C";
      }
      elsif(lc($reading) =~ m/(humidity|vwc)/) { 
        $value=~ s/ \(\%\)//; 
        $unit= "%"; 
      }
    }
  }
  # Onewire
  elsif(($type eq "OWAD") ||
        ($type eq "OWSWITCH")) {
      if(int(@parts)>1) {
        $reading = "data";
        $value = $event;
      } else {
        @parts = split(/\|/, AttrVal($device, $reading."Unit", ""));
        $unit = $parts[1] if($parts[1]);
      }
  }

  # MAX
  elsif(($type eq "MAX")) {
    $unit= "°C" if(lc($reading) =~ m/temp/);
    $unit= "%"   if(lc($reading) eq "valveposition");
  }

  # FS20
  elsif(($type eq "FS20") ||
        ($type eq "X10")) {
    if($reading =~ m/^dim(\d+).*/o) {
      $value = $1;
      $reading= "dim";
      $unit= "%";
    }
    elsif(!defined($value) || $value eq "") {
      $value= $reading;
      $reading= "data";
    }
  }

  # FHT
  elsif($type eq "FHT") {
    if($reading =~ m(-from[12]\ ) || $reading =~ m(-to[12]\ )) {
      @parts= split(/ /,$event);
      $reading= $parts[0];
      $value= $parts[1];
      $unit= "";
    }
    elsif($reading =~ m(-temp)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading =~ m(temp-offset)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading =~ m(^actuator[0-9]*)) {
      if($value eq "lime-protection") {
        $reading= "actuator-lime-protection";
        undef $value;
      }
      elsif($value =~ m(^offset:)) {
        $reading= "actuator-offset";
        @parts= split(/: /,$value);
        $value= $parts[1];
        if(defined $value) {
          $value=~ s/%//; $value= $value*1.; $unit= "%";
        }
      }
      elsif($value =~ m(^unknown_)) {
        @parts= split(/: /,$value);
        $reading= "actuator-" . $parts[0];
        $value= $parts[1];
        if(defined $value) {
          $value=~ s/%//; $value= $value*1.; $unit= "%";
        }
      }
      elsif($value eq "synctime") {
        $reading= "actuator-synctime";
        undef $value;
      }
      elsif($value eq "test") {
        $reading= "actuator-test";
        undef $value;
      }
      elsif($value eq "pair") {
        $reading= "actuator-pair";
        undef $value;
      }
      else {
        $value=~ s/%//; $value= $value*1.; $unit= "%";
      }
    }
  }
  # KS300
  elsif($type eq "KS300") {
    if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
    elsif($event =~ m(avg_day)) { $reading= "data"; $value= $event; }
    elsif($event =~ m(avg_month)) { $reading= "data"; $value= $event; }
    elsif($reading eq "temperature") { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
    elsif($reading eq "wind") { $value=~ s/ \(km\/h\)//; $unit= "km/h"; }
    elsif($reading eq "rain") { $value=~ s/ \(l\/m2\)//; $unit= "l/m2"; }
    elsif($reading eq "rain_raw") { $value=~ s/ \(counter\)//; $unit= ""; }
    elsif($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
    elsif($reading eq "israining") {
      $value=~ s/ \(yes\/no\)//;
      $value=~ s/no/0/;
      $value=~ s/yes/1/;
    }
  }
  # HMS
  elsif($type eq "HMS" ||
        $type eq "CUL_WS" ||
        $type eq "OWTHERM") {
    if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
    elsif($reading eq "temperature") {
      $value=~ s/ \(Celsius\)//; 
      $value=~ s/([-\.\d]+).*/$1/; #OWTHERM
      $unit= "°C"; 
    }
    elsif($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
    elsif($reading eq "battery") {
      $value=~ s/ok/1/;
      $value=~ s/replaced/1/;
      $value=~ s/empty/0/;
    }
  }
  # CUL_HM
  elsif ($type eq "CUL_HM") {
    # remove trailing %  
    $value=~ s/ \%$//;
  }

  # BS
  elsif($type eq "BS") {
    if($event =~ m(brightness:.*)) {
      @parts= split(/ /,$event);
      $reading= "lux";
      $value= $parts[4]*1.;
      $unit= "lux";
    }
  }

  # RFXTRX Lighting
  elsif($type eq "TRX_LIGHT") {
    if($reading =~ m/^level (\d+)/) {
        $value = $1;
        $reading= "level";
    }
  }

  # RFXTRX Sensors
  elsif($type eq "TRX_WEATHER") {
    if($reading eq "energy_current") { $value=~ s/ W//; }
    elsif($reading eq "energy_total") { $value=~ s/ kWh//; }
    elsif($reading eq "battery") {
      if ($value=~ m/(\d+)\%/) { 
        $value= $1; 
      }
      else {
        $value= ($value eq "ok");
      }
    }
  }

  # Weather
  elsif($type eq "WEATHER") {
    if($event =~ m(^wind_condition)) {
      @parts= split(/ /,$event); # extract wind direction from event
      if(defined $parts[0]) {
        $reading = "wind_direction";
        $value= $parts[2];
      }
    }
    elsif($reading eq "wind_chill") { $unit= "°C"; }
    elsif($reading eq "wind_direction") { $unit= ""; }
    elsif($reading =~ m(^wind)) { $unit= "km/h"; } # wind, wind_speed
    elsif($reading =~ m(^temperature)) { $unit= "°C"; } # wenn reading mit temperature beginnt
    elsif($reading =~ m(^humidity)) { $unit= "%"; }
    elsif($reading =~ m(^pressure)) { $unit= "hPa"; }
    elsif($reading =~ m(^pressure_trend)) { $unit= ""; }
  }

  # FHT8V
  elsif($type eq "FHT8V") {
    if($reading =~ m(valve)) {
      @parts= split(/ /,$event);
      $reading= $parts[0];
      $value= $parts[1];
      $unit= "%";
    }
  }

  # Dummy
  elsif($type eq "DUMMY")  {
    if( $value eq "" ) {
      $reading= "data";
      $value= $event;
    }
    $unit= "";
  }

  @result= ($reading,$value,$unit);
  return @result;
}


################################################################
#
# Hauptroutine zum Loggen. Wird bei jedem Eventchange
# aufgerufen
#
################################################################
sub
DbLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;

  return undef if($log->{STATE} eq "disabled");

  # name and type required for parsing
  my $n= $dev->{NAME};
  my $t= uc($dev->{TYPE});

  # timestamp in SQL format YYYY-MM-DD hh:mm:ss
  #my ($sec,$min,$hr,$day,$mon,$yr,$wday,$yday,$isdst)= localtime(time);
  #my $ts= sprintf("%04d-%02d-%02d %02d:%02d:%02d", $yr+1900,$mon+1,$day,$hr,$min,$sec);

  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  my $ts_0 = TimeNow();
  my $now = gettimeofday(); # get timestamp in seconds since epoch
  my $DbLogExclude = AttrVal($dev->{NAME}, "DbLogExclude", undef);
  
  my $dbh= $log->{DBH};
  $dbh->{RaiseError} = 1;
  
  my $DbLogType = AttrVal($log->{NAME}, "DbLogType", "Current/History");
      
  #one Transaction
  eval {
    $dbh->begin_work();
    
    my $sth_ih = $dbh->prepare_cached("INSERT INTO history (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)") if ($DbLogType =~ m(History) );
    my $sth_uc = $dbh->prepare_cached("UPDATE current SET TIMESTAMP=?, TYPE=?, EVENT=?, VALUE=?, UNIT=? WHERE (DEVICE=?) AND (READING=?)") if ($DbLogType =~ m(Current) );
    my $sth_ic = $dbh->prepare_cached("INSERT INTO current (TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES (?,?,?,?,?,?,?)") if ($DbLogType =~ m(Current) );
    
    for (my $i = 0; $i < $max; $i++) {
      my $s = $dev->{CHANGED}[$i];
      $s = "" if(!defined($s));
      if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
        my $ts = $ts_0;
        $ts = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
        # $ts is in SQL format YYYY-MM-DD hh:mm:ss
    
        my @r= DbLog_ParseEvent($n, $t, $s);
        my $reading= $r[0];
        my $value= $r[1];
        my $unit= $r[2];
        if(!defined $reading) { $reading= ""; }
        if(!defined $value) { $value= ""; }
        if(!defined $unit || $unit eq "") {
          $unit = AttrVal("$n", "unit", "");
        }

        #keine Readings loggen die in DbLogExclude explizit ausgeschlossen sind
        my $DoIt = 1;
        if($DbLogExclude) {
          # Bsp: "(temperature|humidity):300 battery:3600"
          my @v1 = split(/,/, $DbLogExclude);
          for (my $i=0; $i<int(@v1); $i++) {
            my @v2 = split(/:/, $v1[$i]);
            $DoIt = 0 if(!$v2[1] && $reading =~ m/^$v2[0]$/); #Reading matcht auf Regexp, kein MinIntervall angegeben
            if(($reading =~ m/^$v2[0]$/) && ($v2[1] =~ m/^(\d+)$/)) {
              #Regexp matcht und MinIntervall ist angegeben
              my $lt = $defs{$dev->{NAME}}{'.userReadings'}{$reading}{"DBLOG_".$log->{NAME}}{TIME};
              my $lv = $defs{$dev->{NAME}}{'.userReadings'}{$reading}{"DBLOG_".$log->{NAME}}{VALUE};
              $lt = 0 if(!$lt);
              $lv = "" if(!$lv);

              if(($now-$lt < $v2[1]) && ($lv eq $value)) {
                # innerhalb MinIntervall und LastValue=Value
                $DoIt = 0;
              }
            }
          }
        }
        next if($DoIt == 0);

        $defs{$dev->{NAME}}{'.userReadings'}{$reading}{"DBLOG_".$log->{NAME}}{TIME}  = $now;
        $defs{$dev->{NAME}}{'.userReadings'}{$reading}{"DBLOG_".$log->{NAME}}{VALUE} = $value;

        my @is= ($ts, $n, $t, $s, $reading, $value, $unit);

        # insert into history
        if ($DbLogType =~ m(History) ) {
          my $rv_ih = $sth_ih->execute(@is);
        }

        if ($DbLogType =~ m(Current) ) {
          # update or insert current
          my $rv_uc = $sth_uc->execute(($ts, $t, $s, $value, $unit, $n, $reading));
          if ($rv_uc == 0) {
            my $rv_ic = $sth_ic->execute(@is);
          }
        }

      }
    } 
    $dbh->commit();
  };
  if ($@) {
    Log3 $dev->{NAME}, 2, "DbLog: Failed to insert new readings into database: $@";
    $dbh->{RaiseError} = 0;  
    $dbh->rollback();
    # reconnect
    $dbh->disconnect();  
    DbLog_Connect($log);
  }
  else {
    $dbh->{RaiseError} = 0;  
  }
  
  return "";
}

################################################################
#
# zerlegt uebergebenes FHEM-Datum in die einzelnen Bestandteile
# und fuegt noch Defaultwerte ein
# uebergebenes SQL-Format: YYYY-MM-DD HH24:MI:SS
#
################################################################
sub
DbLog_explode_datetime($%) {
  my ($t, %def) = @_;
  my %retv;

  my (@datetime, @date, @time);
  @datetime = split(" ", $t); #Datum und Zeit auftrennen
  @date = split("-", $datetime[0]);
  @time = split(":", $datetime[1]) if ($datetime[1]);
  if ($date[0]) {$retv{year}  = $date[0];} else {$retv{year}  = $def{year};}
  if ($date[1]) {$retv{month} = $date[1];} else {$retv{month} = $def{month};}
  if ($date[2]) {$retv{day}   = $date[2];} else {$retv{day}   = $def{day};}
  if ($time[0]) {$retv{hour}  = $time[0];} else {$retv{hour}  = $def{hour};}
  if ($time[1]) {$retv{minute}= $time[1];} else {$retv{minute}= $def{minute};}
  if ($time[2]) {$retv{second}= $time[2];} else {$retv{second}= $def{second};}

  $retv{datetime}=DbLog_implode_datetime($retv{year}, $retv{month}, $retv{day}, $retv{hour}, $retv{minute}, $retv{second});

  #Log 1, Dumper(%retv);
  return %retv
}

sub
DbLog_implode_datetime($$$$$$) {
  my ($year, $month, $day, $hour, $minute, $second) = @_;
  my $retv = $year."-".$month."-".$day." ".$hour.":".$minute.":".$second;

  return $retv;
}
################################################################
#
# Verbindung zur DB aufbauen
#
################################################################
sub
DbLog_Connect($)
{
  my ($hash)= @_;

  my $configfilename= $hash->{CONFIGURATION};
  if(!open(CONFIG, $configfilename)) {
    Log3 $hash->{NAME}, 1, "Cannot open database configuration file $configfilename.";
    return 0; }
  my @config=<CONFIG>;
  close(CONFIG);

  my %dbconfig;
  eval join("", @config);

  my $dbconn= $dbconfig{connection};
  my $dbuser= $dbconfig{user};
  my $dbpassword= $dbconfig{password};

  #check the database model
  if($dbconn =~ m/pg:/i) {
    $hash->{DBMODEL}="POSTGRESQL";
  } elsif ($dbconn =~ m/mysql:/i) {
    $hash->{DBMODEL}="MYSQL";
  } elsif ($dbconn =~ m/oracle:/i) {
    $hash->{DBMODEL}="ORACLE";
  } elsif ($dbconn =~ m/sqlite:/i) {
    $hash->{DBMODEL}="SQLITE";
  } else {
    $hash->{DBMODEL}="unknown";
    Log3 $hash->{NAME}, 3, "Unknown dbmodel type in configuration file $configfilename.";
    Log3 $hash->{NAME}, 3, "Only Mysql, Postgresql, Oracle, SQLite are fully supported.";
    Log3 $hash->{NAME}, 3, "It may cause SQL-Erros during generating plots.";
  }

  Log3 $hash->{NAME}, 3, "Connecting to database $dbconn with user $dbuser";
  my $dbh = DBI->connect_cached("dbi:$dbconn", $dbuser, $dbpassword);
  if(!$dbh) {
    Log3 $hash->{NAME}, 2, "Can't connect to $dbconn: $DBI::errstr";
    return 0;
  }
  Log3 $hash->{NAME}, 3, "Connection to db $dbconn established";
  $hash->{DBH}= $dbh;
  
  if ($hash->{DBMODEL} eq "SQLITE") {
    $dbh->do("PRAGMA temp_store=MEMORY");
    $dbh->do("PRAGMA synchronous=NORMAL");
    $dbh->do("PRAGMA journal_mode=WAL");
    $dbh->do("PRAGMA cache_size=4000");
    $dbh->do("CREATE TEMP TABLE IF NOT EXISTS current (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(512), READING varchar(32), VALUE varchar(32), UNIT varchar(32))");
    $dbh->do("CREATE TABLE IF NOT EXISTS history (TIMESTAMP TIMESTAMP, DEVICE varchar(32), TYPE varchar(32), EVENT varchar(512), READING varchar(32), VALUE varchar(32), UNIT varchar(32))");
    $dbh->do("CREATE INDEX IF NOT EXISTS Search_Idx ON `history` (DEVICE, READING, TIMESTAMP)");
  }
  
  # creating an own connection for the webfrontend, saved as DBHF in Hash
  # this makes sure that the connection doesnt get lost due to other modules
  my $dbhf = DBI->connect_cached("dbi:$dbconn", $dbuser, $dbpassword);
  if(!$dbhf) {
    Log3 $hash->{NAME}, 2, "Can't connect to $dbconn: $DBI::errstr";
    return 0;
  }
  Log3 $hash->{NAME}, 3, "Connection to db $dbconn established";
  $hash->{DBHF}= $dbhf;

  return 1;
}

################################################################
#
# Prozeduren zum Ausfuehren des SQLs
#
################################################################
sub
DbLog_ExecSQL1($$$)
{
  my ($hash,$dbh,$sql)= @_;

  my $sth = $dbh->do($sql);
  if(!$sth) {
    Log3 $hash->{NAME}, 2, "DBLog error: " . $DBI::errstr;
    return 0;
  }
  return $sth;
}

sub
DbLog_ExecSQL($$)
{
  my ($hash,$sql)= @_;
  Log3 $hash->{NAME}, 4, "Executing $sql";
  my $dbh= $hash->{DBH};
  my $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
  if(!$sth) {
    #retry
    $dbh->disconnect();
    if(!DbLog_Connect($hash)) {
      Log3 $hash->{NAME}, 2, "DBLog reconnect failed.";
      return 0;
    }
    $dbh= $hash->{DBH};
    $sth = DbLog_ExecSQL1($hash,$dbh,$sql);
    if(!$sth) {
      Log3 $hash->{NAME}, 2, "DBLog retry failed.";
      return 0;
    }
    Log3 $hash->{NAME}, 2, "DBLog retry ok.";
  }
  return $sth;
}

################################################################
#
# GET Funktion
# wird zb. zur Generierung der Plots implizit aufgerufen
#
################################################################
sub
DbLog_Get($@)
{
  my ($hash, @a) = @_;

  return "Usage: get $a[0] <in> <out> <from> <to> <column_spec>...\n".
     "  where column_spec is <device>:<reading>:<default>:<fn>\n" .
     "  see the #DbLog entries in the .gplot files\n" .
     "  <in> is not used, only for compatibility for FileLog, please use - \n" .
     "  <out> is a prefix, - means stdout\n"
    if(int(@a) < 5);
  shift @a;
  my $inf  = shift @a;
  my $outf = shift @a;
  my $from = shift @a;
  my $to   = shift @a; # Now @a contains the list of column_specs
  my ($internal, @fld);

  if($outf eq "INT") {
    $outf = "-";
    $internal = 1;
  } elsif (uc($outf) eq "WEBCHART") {
    # redirect the get request to the chartQuery function
    return chartQuery($hash, @_);
  }

  my @readings = ();
  my (%sqlspec, %from_datetime, %to_datetime);

  #uebergebenen Timestamp anpassen
  #moegliche Formate: YYYY | YYYY-MM | YYYY-MM-DD | YYYY-MM-DD_HH24
  $from =~ s/_/\ /g;
  $to   =~ s/_/\ /g;
  %from_datetime = DbLog_explode_datetime($from, DbLog_explode_datetime("2000-01-01 00:00:00", ()));
  %to_datetime   = DbLog_explode_datetime($to, DbLog_explode_datetime("2099-01-01 00:00:00", ()));
  $from = $from_datetime{datetime};
  $to = $to_datetime{datetime};


  my ($retval,$sql_timestamp,$sql_value, $type, $event, $unit) = "";
  my $writeout = 0;
  my (@min, @max, @sum, @cnt, @lastv, @lastd);
  my (%tstamp, %lasttstamp, $out_tstamp, $out_value, $minval, $maxval); #fuer delta-h/d Berechnung

  #extract the Device:Reading arguments into @readings array
  for(my $i = 0; $i < int(@a); $i++) {
    @fld = split(":", $a[$i], 5);
    $readings[$i][0] = $fld[0]; # Device
    $readings[$i][1] = $fld[1]; # Reading
    $readings[$i][2] = $fld[2]; # Default
    $readings[$i][3] = $fld[3]; # function
    $readings[$i][4] = $fld[4]; # regexp
  }

  my $dbh= $hash->{DBH};

  #vorbereiten der DB-Abfrage, DB-Modell-abhaengig
  if ($hash->{DBMODEL} eq "POSTGRESQL") {
    $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{reading_clause} = "(DEVICE || '|' || READING)";
  } elsif ($hash->{DBMODEL} eq "ORACLE") {
    $sqlspec{get_timestamp}  = "TO_CHAR(TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{from_timestamp} = "TO_TIMESTAMP('$from', 'YYYY-MM-DD HH24:MI:SS')";
    $sqlspec{to_timestamp}   = "TO_TIMESTAMP('$to', 'YYYY-MM-DD HH24:MI:SS')";
  } elsif ($hash->{DBMODEL} eq "MYSQL") {
    $sqlspec{get_timestamp}  = "DATE_FORMAT(TIMESTAMP, '%Y-%m-%d %H:%i:%s')";
    $sqlspec{from_timestamp} = "STR_TO_DATE('$from', '%Y-%m-%d %H:%i:%s')";
    $sqlspec{to_timestamp}   = "STR_TO_DATE('$to', '%Y-%m-%d %H:%i:%s')";
  } elsif ($hash->{DBMODEL} eq "SQLITE") {
    $sqlspec{get_timestamp}  = "TIMESTAMP";
    $sqlspec{from_timestamp} = "'$from'";
    $sqlspec{to_timestamp}   = "'$to'";
  } else {
    $sqlspec{get_timestamp}  = "TIMESTAMP";
    $sqlspec{from_timestamp} = "'$from'";
    $sqlspec{to_timestamp}   = "'$to'";
  }

  if(uc($outf) eq "ALL") {
    $sqlspec{all}  = ",TYPE,EVENT,UNIT";
  } else {
    $sqlspec{all}  = "";
  }

  for(my $i=0; $i<int(@readings); $i++) {
    # ueber alle Readings
    # Variablen initialisieren
    $min[$i]   =  999999;
    $max[$i]   = -999999;
    $sum[$i]   = 0;
    $cnt[$i]   = 0;
    $lastv[$i] = 0;
    $lastd[$i] = "undef";
    $minval    =  999999;
    $maxval    = -999999;

    my $stm= "SELECT
          $sqlspec{get_timestamp},
          VALUE
          $sqlspec{all}
        FROM history
        WHERE
          DEVICE  = '".$readings[$i]->[0]."'
          AND READING = '".$readings[$i]->[1]."'
          AND TIMESTAMP > $sqlspec{from_timestamp}
          AND TIMESTAMP < $sqlspec{to_timestamp}
        ORDER BY TIMESTAMP";

    Log3 $hash->{NAME}, 5, "Executing $stm";

    my $sth= $dbh->prepare($stm) ||
      return "Cannot prepare statement $stm: $DBI::errstr";
    my $rc= $sth->execute() ||
      return "Cannot execute statement $stm: $DBI::errstr";

    if(uc($outf) eq "ALL") {
        $sth->bind_columns(undef, \$sql_timestamp, \$sql_value, \$type, \$event, \$unit);
        
        $retval .= "Timestamp: Device, Type, Event, Reading, Value, Unit\n";
        $retval .= "=====================================================\n";
    }
    else {
        $sth->bind_columns(undef, \$sql_timestamp, \$sql_value);
    }

    while($sth->fetch()) {
      $writeout   = 0;
      $out_value  = "";
      $out_tstamp = "";

      ############ Auswerten des 5. Parameters: Regexp ###################
      # die Regexep wird vor der Function ausgewertet und der Wert im Feld
      # Value angepasst.
      ####################################################################
      if($readings[$i]->[4] && $readings[$i]->[4]) {
        #evaluate
        my $val = $sql_value;
        my $ts  = $sql_timestamp;
        eval("$readings[$i]->[4]");
        $sql_value = $val;
        $sql_timestamp = $ts;
        if($@) {Log3 $hash->{NAME}, 3, "DbLog: Error in inline function: <".$readings[$i]->[4].">, Error: $@";}
        $out_tstamp = $sql_timestamp;
        $writeout=1;
      }

      ############ Auswerten des 4. Parameters: function ###################
      if($readings[$i]->[3] && $readings[$i]->[3] eq "int") {
        #nur den integerwert uebernehmen falls zb value=15°C
        $out_value = $1 if($sql_value =~ m/^(\d+).*/o);
        $out_tstamp = $sql_timestamp;
        $writeout=1;

      } elsif ($readings[$i]->[3] && $readings[$i]->[3] =~ m/^int(\d+).*/o) {
        #Uebernehme den Dezimalwert mit den angegebenen Stellen an Nachkommastellen
        $out_value = $1 if($sql_value =~ m/^([-\.\d]+).*/o);
        $out_tstamp = $sql_timestamp;
        $writeout=1;

      } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-ts" && lc($sql_value) !~ m(ignore)) {
        #Berechung der vergangen Sekunden seit dem letten Logeintrag
        #zb. die Zeit zwischen on/off
        my @a = split("[- :]", $sql_timestamp);
        my $akt_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
        if($lastd[$i] ne "undef") {
          @a = split("[- :]", $lastd[$i]);
        }
        my $last_ts = mktime($a[5],$a[4],$a[3],$a[2],$a[1]-1,$a[0]-1900,0,0,-1);
        $out_tstamp = $sql_timestamp;
        $out_value = sprintf("%02d", $akt_ts - $last_ts);
        if(lc($sql_value) =~ m(hide)){$writeout=0;} else {$writeout=1;}

      } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-h") {
        #Berechnung eines Stundenwertes
        %tstamp = DbLog_explode_datetime($sql_timestamp, ());
        if($lastd[$i] eq "undef") {
          %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
        } else {
          %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
        }
        if("$tstamp{hour}" ne "$lasttstamp{hour}") {
          # Aenderung der stunde, Berechne Delta
          $out_value = sprintf("%0.1f", $maxval - $minval);
          $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00");
          $minval =  999999;
          $maxval = -999999;
          $writeout=1;
        }
      } elsif ($readings[$i]->[3] && $readings[$i]->[3] eq "delta-d") {
        #Berechnung eines Tageswertes
        %tstamp = DbLog_explode_datetime($sql_timestamp, ());
        if($lastd[$i] eq "undef") {
          %lasttstamp = DbLog_explode_datetime($sql_timestamp, ());
        } else {
          %lasttstamp = DbLog_explode_datetime($lastd[$i], ());
        }
        if("$tstamp{day}" ne "$lasttstamp{day}") {
          # Aenderung des Tages, Berechne Delta
          $out_value = sprintf("%0.1f", $maxval - $minval);
          $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "00", "00", "00");
          $minval =  999999;
          $maxval = -999999;
          $writeout=1;
        }
      } else {
        $out_value = $sql_value;
        $out_tstamp = $sql_timestamp;
        $writeout=1;
      }

      ###################### Ausgabe ###########################
      if($writeout) {
          if(uc($outf) eq "ALL") {
            $retval .= sprintf("%s: %s, %s, %s, %s, %s, %s\n", $out_tstamp, $readings[$i]->[0], $type, $event, $readings[$i]->[1], $out_value, $unit);
          } else {
            $out_tstamp =~ s/\ /_/g; #needed by generating plots
            $retval .= "$out_tstamp $out_value\n";
          }
      }

      if(Scalar::Util::looks_like_number($sql_value)){
        #nur setzen wenn nummerisch
        $min[$i] = $sql_value if($sql_value < $min[$i]);
        $max[$i] = $sql_value if($sql_value > $max[$i]);;
        $sum[$i] += $sql_value;
        $minval = $sql_value if($sql_value < $minval);
        $maxval = $sql_value if($sql_value > $maxval);
      } else {
        $min[$i] = 0;
        $max[$i] = 0;
        $sum[$i] = 0;
        $minval  = 0;
        $maxval  = 0;
      }
      $cnt[$i]++;
      $lastv[$i] = $sql_value;
      $lastd[$i] = $sql_timestamp;

    } #while fetchrow

    ######## den letzten Abschlusssatz rausschreiben ##########
    if($readings[$i]->[3] && ($readings[$i]->[3] eq "delta-h" || $readings[$i]->[3] eq "delta-d")) {
      $out_value = sprintf("%0.1f", $maxval - $minval);
      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, $lasttstamp{hour}, "30", "00") if($readings[$i]->[3] eq "delta-h");
      $out_tstamp = DbLog_implode_datetime($lasttstamp{year}, $lasttstamp{month}, $lasttstamp{day}, "00", "00", "00") if($readings[$i]->[3] eq "delta-d");
      if(uc($outf) eq "ALL") {
        $retval .= sprintf("%s: %s %s %s %s %s %s\n", $out_tstamp, $readings[$i]->[0], $type, $event, $readings[$i]->[1], $out_value, $unit);
        } else {
          $out_tstamp =~ s/\ /_/g; #needed by generating plots
          $retval .= "$out_tstamp $out_value\n";
        }
    }
    # DatenTrenner setzen
    $retval .= "#$readings[$i]->[0]";
    $retval .= ":";
    $retval .= "$readings[$i]->[1]" if($readings[$i]->[1]);
    $retval .= ":";
    $retval .= "$readings[$i]->[2]" if($readings[$i]->[2]);
    $retval .= ":";
    $retval .= "$readings[$i]->[3]" if($readings[$i]->[3]);
    $retval .= ":";
    $retval .= "$readings[$i]->[4]" if($readings[$i]->[4]);
    $retval .= "\n";
  } #for @readings

  #Ueberfuehren der gesammelten Werte in die globale Variable %data
  for(my $j=0; $j<int(@readings); $j++) {
    my $k = $j+1;
    $data{"min$k"} = $min[$j] == 999999 ? "undef" : $min[$j];
    $data{"max$k"} = $max[$j] == -999999 ? "undef" : $max[$j];
    $data{"avg$k"} = $cnt[$j] ? sprintf("%0.1f", $sum[$j]/$cnt[$j]) : "undef";
    $data{"sum$k"} = $sum[$j];
    $data{"cnt$k"} = $cnt[$j] ? $cnt[$j] : "undef";
    $data{"currval$k"} = $lastv[$j];
    $data{"currdate$k"} = $lastd[$j];
  }

  if($internal) {
    $internal_data = \$retval;
    return undef;
  }
  return $retval;
}

################################################################
#
# Charting Specific functions start here
#
################################################################

################################################################
#
# Error handling, returns a JSON String
#
################################################################
sub jsonError($) {
  my $errormsg = $_[0]; 
  my $json = '{"success": "false", "msg":"'.$errormsg.'"}';
  return $json;
}


################################################################
#
# Prepare the SQL String
#
################################################################
sub prepareSql(@) {

    my ($hash, @a) = @_;
    my $starttime = $_[5];
    $starttime =~ s/_/ /;
    my $endtime   = $_[6];
    $endtime =~ s/_/ /;
    my $device = $_[7];
    my $userquery = $_[8];
    my $xaxis = $_[9]; 
    my $yaxis = $_[10]; 
    my $savename = $_[11]; 
    my $jsonChartConfig = $_[12];
    my $pagingstart = $_[13]; 
    my $paginglimit = $_[14]; 
    my $dbmodel = $hash->{DBMODEL};
    my ($sql, $jsonstring, $countsql, $hourstats, $daystats, $weekstats, $monthstats, $yearstats);

    if ($dbmodel eq "POSTGRESQL") {
        ### POSTGRESQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT to_char(timestamp, 'YYYY-MM-DD HH24:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $hourstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $hourstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT to_char(timestamp, 'YYYY-MM-DD 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $daystats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $daystats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_trunc('week',timestamp) AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $weekstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $weekstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### month:
        $monthstats = "SELECT to_char(timestamp, 'YYYY-MM-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $monthstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $monthstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT to_char(timestamp, 'YYYY-01-01 00:00:00') AS TIMESTAMP, SUM(VALUE::float) AS SUM, ";
        $yearstats .= "AVG(VALUE::float) AS AVG, MIN(VALUE::float) AS MIN, MAX(VALUE::float) AS MAX, ";
        $yearstats .= "COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";
   
    } elsif ($dbmodel eq "MYSQL") {
        ### MYSQL Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT date_format(timestamp, '%Y-%m-%d %H:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $hourstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $hourstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $hourstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### day:
        $daystats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $daystats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $daystats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $daystats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### week:
        $weekstats = "SELECT date_format(timestamp, '%Y-%m-%d 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $weekstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $weekstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $weekstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' ";
        $weekstats .= "GROUP BY date_format(timestamp, '%Y-%u 00:00:00') ORDER BY 1;";

        ### month:
        $monthstats = "SELECT date_format(timestamp, '%Y-%m-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $monthstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $monthstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $monthstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

        ### year:
        $yearstats = "SELECT date_format(timestamp, '%Y-01-01 00:00:00') AS TIMESTAMP, SUM(CAST(VALUE AS DECIMAL(12,4))) AS SUM, ";
        $yearstats .= "AVG(CAST(VALUE AS DECIMAL(12,4))) AS AVG, MIN(CAST(VALUE AS DECIMAL(12,4))) AS MIN, ";
        $yearstats .= "MAX(CAST(VALUE AS DECIMAL(12,4))) AS MAX, COUNT(VALUE) AS COUNT FROM history WHERE READING = '$yaxis' ";
        $yearstats .= "AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY 1 ORDER BY 1;";

    } elsif ($hash->{DBMODEL} eq "SQLITE") {
        ### SQLITE Queries for Statistics ###
        ### hour:
        $hourstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $hourstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $hourstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $hourstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d %H:00:00', TIMESTAMP);";
  
        ### day:
        $daystats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $daystats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $daystats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $daystats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m-%d 00:00:00', TIMESTAMP);";

        ### week:
        $weekstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $weekstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $weekstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $weekstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%W 00:00:00', TIMESTAMP);";

        ### month:
        $monthstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $monthstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $monthstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $monthstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y-%m 00:00:00', TIMESTAMP);";

        ### year:
        $yearstats = "SELECT TIMESTAMP, SUM(CAST(VALUE AS FLOAT)) AS SUM, AVG(CAST(VALUE AS FLOAT)) AS AVG, ";
        $yearstats .= "MIN(CAST(VALUE AS FLOAT)) AS MIN, MAX(CAST(VALUE AS FLOAT)) AS MAX, COUNT(VALUE) AS COUNT ";
        $yearstats .= "FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
        $yearstats .= "AND TIMESTAMP Between '$starttime' AND '$endtime' GROUP BY strftime('%Y 00:00:00', TIMESTAMP);";

    } else {
        $sql = "errordb";
    }

    if($userquery eq "getreadings") {
        $sql = "SELECT distinct(reading) FROM history WHERE device = '".$device."'";
    } elsif($userquery eq "getdevices") {
        $sql = "SELECT distinct(device) FROM history";
    } elsif($userquery eq "timerange") {
        $sql = "SELECT ".$xaxis.", VALUE FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' AND TIMESTAMP Between '$starttime' AND '$endtime';";
    } elsif($userquery eq "hourstats") {
        $sql = $hourstats;
    } elsif($userquery eq "daystats") {
        $sql = $daystats;
    } elsif($userquery eq "weekstats") {
        $sql = $weekstats;
    } elsif($userquery eq "monthstats") {
        $sql = $monthstats;
    } elsif($userquery eq "yearstats") {
        $sql = $yearstats;
    } elsif($userquery eq "savechart") {
        $sql = "INSERT INTO frontend (TYPE, NAME, VALUE) VALUES ('savedchart', '$savename', '$jsonChartConfig')";
    } elsif($userquery eq "renamechart") {
        $sql = "UPDATE frontend SET NAME = '$savename' WHERE ID = '$jsonChartConfig'";
    } elsif($userquery eq "deletechart") {
        $sql = "DELETE FROM frontend WHERE TYPE = 'savedchart' AND ID = '".$savename."'";
    } elsif($userquery eq "updatechart") {
        $sql = "UPDATE frontend SET VALUE = '$jsonChartConfig' WHERE ID = '".$savename."'";
    } elsif($userquery eq "getcharts") {
        $sql = "SELECT * FROM frontend WHERE TYPE = 'savedchart'";
    } elsif($userquery eq "getTableData") {
        if ($device ne '""' && $yaxis ne '""') {
            $sql = "SELECT * FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'"; 
            $countsql = "SELECT count(*) FROM history WHERE READING = '$yaxis' AND DEVICE = '$device' "; 
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'"; 
        } elsif($device ne '""' && $yaxis eq '""') {  
            $sql = "SELECT * FROM history WHERE DEVICE = '$device' ";
            $sql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM history WHERE DEVICE = '$device' ";
            $countsql .= "AND TIMESTAMP Between '$starttime' AND '$endtime'";
        } else {
            $sql = "SELECT * FROM history";
            $sql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'"; 
            $sql .= " LIMIT '$paginglimit' OFFSET '$pagingstart'";
            $countsql = "SELECT count(*) FROM history"; 
            $countsql .= " WHERE TIMESTAMP Between '$starttime' AND '$endtime'"; 
        }
        return ($sql, $countsql);
    } else {
        $sql = "error";
    }

    return $sql;
}

################################################################
#
# Do the query
#
################################################################
sub chartQuery($@) {

    my ($sql, $countsql) = prepareSql(@_);

    if ($sql eq "error") {
       return jsonError("Could not setup SQL String. Maybe the Database is busy, please try again!");
    } elsif ($sql eq "errordb") {
       return jsonError("The Database Type is not supported!");
    }

    my ($hash, @a) = @_;
    my $dbhf= $hash->{DBHF};

    my $totalcount;
    
    if (defined $countsql && $countsql ne "") {
        my $query_handle = $dbhf->prepare($countsql) 
        or return jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$countsql);
        
        $query_handle->execute() 
        or return jsonError("Could not execute statement: " . $query_handle->errstr);

        my @data = $query_handle->fetchrow_array();
        $totalcount = join(", ", @data);
        
    }

    # prepare the query
    my $query_handle = $dbhf->prepare($sql) 
        or return jsonError("Could not prepare statement: " . $dbhf->errstr . ", SQL was: " .$sql);
    
    # execute the query
    $query_handle->execute() 
        or return jsonError("Could not execute statement: " . $query_handle->errstr);
    
    my $columns = $query_handle->{'NAME'};
    my $columncnt;

    # When columns are empty but execution was successful, we have done a successful INSERT, UPDATE or DELETE
    if($columns) {
        $columncnt = scalar @$columns;
    } else {
        return '{"success": "true", "msg":"All ok"}';
    }

    my $i = 0;
    my $jsonstring = '{"data":[';

    while ( my @data = $query_handle->fetchrow_array()) {

        if($i == 0) {
            $jsonstring .= '{';
        } else {
            $jsonstring .= ',{';
        } 
 
        for ($i = 0; $i < $columncnt; $i++) {
            $jsonstring .= '"';
            $jsonstring .= uc($query_handle->{NAME}->[$i]); 
            $jsonstring .= '":';

            if (defined $data[$i]) {
                my $fragment =  substr($data[$i],0,1);
                if ($fragment eq "{") {
                    $jsonstring .= $data[$i];
                } else {
                    $jsonstring .= '"'.$data[$i].'"';
                }
            } else {
                $jsonstring .= '""'
            }
            
            if($i != ($columncnt -1)) {
               $jsonstring .= ','; 
            }
        }
        $jsonstring .= '}'; 
    }
    $jsonstring .= ']';
    if (defined $totalcount && $totalcount ne "") {
        $jsonstring .= ',"totalCount": '.$totalcount.'}';
    } else {
        $jsonstring .= '}';
    }
    return $jsonstring;
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
    <code>contrib/dblog/db.conf</code>). The configuration is stored in a separate file
    to avoid storing the password in the main configuration file and to have it
    visible in the output of the <a href="../docs/commandref.html#list">list</a> command.
    <br><br>

    The modules <code>DBI</code> and <code>DBD::&lt;dbtype&gt;</code>
    need to be installed (use <code>cpan -i &lt;module&gt;</code>
    if your distribution does not have it).
    <br><br>

    <code>&lt;regexp&gt;</code> is the same as in <a href="../docs/commandref.html#FileLog">FileLog</a>.
    <br><br>
    Sample code to create a MySQL/PostgreSQL database is in
    <code>&lt;DBType&gt;_create.sql</code>.
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
    <code>yes</code> is translated to <code>1</code>
    <br><br>
    The current values can be retrieved by the following code like FileLog:<br>
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature::</code>
    </ul>
    <br><br>
    <b>Examples:</b>
    <ul>
        <code># log everything to database</code><br>

        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code>
    </ul>
  </ul>


  <a name="DbLogset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="DbLogget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Read data from the Database, used by frontends to plot data without direct
    access to the Database.<br>

    <ul>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Always set to <code>-</code></li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Set it to <code>-</code>
        to check the output for plot-computing.<br>Set it to the special keyword
        <code>all</code> to get all columns from Database.</li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat or
        an initial substring of it:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;column_spec&gt;<br>
        For each column_spec return a set of data separated by
        a comment line on the current connection.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            The name of the device. Case sensitive</li>
          <li>&lt;reading&gt;<br>
            The reading of the given device to select. Case sensitive.
            </li>
          <li>&lt;default&gt;<br>
            no implemented yet
            </li>
          <li>&lt;fn&gt;
            One of the following:
            <ul>
              <li>int<br>
                Extract the integer at the beginning of the string. Used e.g.
                for constructs like 10%</li>
              <li>int&lt;digit&gt;<br>
                Extract the decimal digits including negative character and
                decimal point at the beginning og the string. Used e.g.
                for constructs like 15.7&deg;C</li>
              <li>delta-h / delta-d<br>
                Return the delta of the values for a given hour or a given day.
                Used if the column contains a counter, as is the case for the
                KS300 rain column.</li>
              <li>delta-ts<br>
                Replaced the original value with a measured value of seconds since
                the last and the actual logentry.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              The string is evaluated as a perl expression.  The regexp is executed
              before &lt;fn&gt; parameter.<br>
              Note: The string/perl expression cannot contain spaces,
              as the part after the space will be considered as the
              next column_spec.<br>
              <b>Keywords</b>
              <li>$val is the current value returned from the Database.</li>
              <li>$ts is the current timestamp returned from the Database.</li>
              <li>This Logentry will not print out if $val contains th keyword "hide".</li>
              <li>This Logentry will not print out and not used in the following processing
                  if $val contains th keyword "ignore".</li>
            </li>
        </ul></li>
      </ul>
    <br><br>
    Examples:
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           like from 10am until 08pm at 10.11.2012</li>
        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           return 1 for all occurance of on* (on|on-for-timer etc) and 0 for all off*</li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Example of OWAD: value like this: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           and output for port B is like this: <code>2012-11-20_10:23:54 66.647</code></li>
        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Setting up a "Counter of Uptime". The function delta-ts gets the seconds between the last and the
           actual logentry. The keyword "hide" will hide the logentry of "on" because this time 
           is a "counter of Downtime"</li>

      </ul>
    <br><br>
  </ul>

  <b>Get</b> when used for webcharts
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </code>
    <br><br>
    Query the Database to retrieve JSON-Formatted Data, which is used by the charting frontend.
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        The name of the defined DbLog, like it is given in fhem.cfg.</li>
      <li>&lt;in&gt;<br>
        A dummy parameter for FileLog compatibility. Always set to <code>-</code></li>
      <li>&lt;out&gt;<br>
        A dummy parameter for FileLog compatibility. Set it to <code>webchart</code>
        to use the charting related get function.
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Used to select the data. Please use the following timeformat:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;device&gt;<br>
        A string which represents the device to query.</li>
      <li>&lt;querytype&gt;<br>
        A string which represents the method the query should use. Actually supported values are: <br>
          <code>getreadings</code> to retrieve the possible readings for a given device<br>
          <code>getdevices</code> to retrieve all available devices<br>
          <code>timerange</code> to retrieve charting data, which requires a given xaxis, yaxis, device, to and from<br>
          <code>savechart</code> to save a chart configuration in the database. Requires a given xaxis, yaxis, device, to and from, and a 'savename' used to save the chart<br>
          <code>deletechart</code> to delete a saved chart. Requires a given id which was set on save of the chart<br>
          <code>getcharts</code> to get a list of all saved charts.<br>
          <code>getTableData</code> to get jsonformatted data from the database. Uses paging Parameters like start and limit.<br>
          <code>hourstats</code> to get statistics for a given value (yaxis) for an hour.<br>
          <code>daystats</code> to get statistics for a given value (yaxis) for a day.<br>
          <code>weekstats</code> to get statistics for a given value (yaxis) for a week.<br>
          <code>monthstats</code> to get statistics for a given value (yaxis) for a month.<br>
          <code>yearstats</code> to get statistics for a given value (yaxis) for a year.<br>
      </li>
      <li>&lt;xaxis&gt;<br>
        A string which represents the xaxis</li>
      <li>&lt;yaxis&gt;<br>
         A string which represents the yaxis</li>
      <li>&lt;savename&gt;<br>
         A string which represents the name a chart will be saved with</li>
      <li>&lt;chartconfig&gt;<br>
         A jsonstring which represents the chart to save</li>
      <li>&lt;pagingstart&gt;<br>
         An integer used to determine the start for the sql used for query 'getTableData'</li>
      <li>&lt;paginglimit&gt;<br>
         An integer used to set the limit for the sql used for query 'getTableData'</li>
      </ul>
    <br><br>
    Examples:
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Retrieves all saved charts from the Database</li>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Retrieves all available devices from the Database</li>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Retrieves all available Readings for a given device from the Database</li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Retrieves charting data, which requires a given xaxis, yaxis, device, to and from<br>
            Will ouput a JSON like this: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Will save a chart in the database with the given name and the chart configuration parameters</li>      
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Will delete a chart from the database with the given id</li>
      </ul>
    <br><br>
  </ul>
  <a name="DbLogattr"></a>
  <b>Attributes</b> 
  <ul><b>DbLogExclude</b>
    <br>
    <ul>
      <code>
      set &lt;device&gt; DbLogExclude regex:MinInterval [regex:MinInterval] ...
      </code>
    </ul>
    A new Attribute DbLogExclude will be propagated
    to all Devices if DBLog is used. DbLogExclude will work as regexp to exclude 
    defined readings to log. Each individual regexp-group are separated by comma. 
    If a MinInterval is set, the logentry is dropped if the 
    defined interval is not reached and value vs. lastvalue is eqal .
    <br>
    <b>Example</b>
    <ul>
      <code>attr MyDevice1 DbLogExclude .*</code>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code>
    </ul>
  </ul><br>
</ul>

=end html
=begin html_DE

<a name="DbLog"></a>
<h3>DbLog</h3>
<ul>
  <br>

  <a name="DbLogdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DbLog &lt;configfilename&gt; &lt;regexp&gt;</code>
    <br><br>

    Speichert Events in eine Datenbank. Die Datenbankverbindungsparameter werden
    definiert in <code>&lt;configfilename&gt;</code>. (Vergleiche
    Beipspielkonfigurationsdatei in <code>contrib/dblog/db.conf</code>).<br>
    Die Konfiguration ist in einer sparaten Datei abgelegt um das Datenbankpasswort
    nicht in Klartext in der FHEM-Haupt-Konfigurationsdatei speichern zu müssen.
    Ansonsten wäre es mittels des <a href="../docs/commandref.html#list">list</a>
    Befehls einfach auslesbar.
    <br><br>

    Die Perl-Module <code>DBI</code> and <code>DBD::&lt;dbtype&gt;</code>
    müssen installiert werden (use <code>cpan -i &lt;module&gt;</code>
    falls die eigene Distribution diese nicht schon mitbringt).
    <br><br>

    <code>&lt;regexp&gt;</code> ist identisch wie <a href="../docs/commandref.html#FileLog">FileLog</a>.
    <br><br>
    Ein Beispielcode zum Erstellen einer MySQL/PostGreSQL Datenbak ist in
    <code>contrib/dblog/&lt;DBType&gt;_create.sql</code> zu finden.
    Die Datenbank beinhaltet 2 Tabellen: <code>current</code> und
    <code>history</code>. Die Tabelle <code>current</code> enthält den letzten Stand
    pro Device und Reading. In der Tabelle <code>history</code> sind alle
    Events historisch gespeichert.

    Die Tabellenspalten haben folgende Bedeutung:
    <ol>
    <li>TIMESTAMP: Zeitpunkt des Events, z.B. <code>2007-12-30 21:45:22</code></li>
    <li>DEVICE: name des Devices, z.B. <code>Wetterstation</code></li>
    <li>TYPE: Type des Devices, z.B. <code>KS300</code></li>
    <li>EVENT: das auftretende Event als volle Zeichenkette
                                        z.B. <code>humidity: 71 (%)</code></li>
    <li>READING: Name des Readings, ermittelt aus dem Event,
                    z.B. <code>humidity</code></li>

    <li>VALUE: aktueller Wert des Readings, ermittelt aus dem Event,
                    z.B. <code>71</code></li>
    <li>UNIT: Einheit, ermittelt aus dem Event, z.B. <code>%</code></li>
    </ol>
    Der Wert des Rreadings ist optimiert für eine automatisierte Nachverarbeitung
    z.B. <code>yes</code> ist transformiert nach <code>1</code>
    <br><br>
    Die gespeicherten Werte können mittels GET Funktion angezeigt werden:
    <ul>
      <code>get myDbLog - - 2012-11-10 2012-11-10 KS300:temperature</code>
    </ul>
    <br><br>
    <b>Beispiel:</b>
    <ul>
        <code>Speichert alles in der Datenbank</code><br>

        <code>define myDbLog DbLog /etc/fhem/db.conf .*:.*</code>
    </ul>
  </ul>


  <a name="DbLogset"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a name="DbLogget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;column_spec&gt; </code>
    <br><br>
    Ließt Daten aus der Datenbank. Wird durch die Frontends benutzt um Plots
    zu generieren ohne selbst auf die Datenank zugreifen zu müssen.
    <br>

    <ul>
      <li>&lt;in&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist immer auf <code>-</code> zu setzen.
      </li>
      <li>&lt;out&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist immer auf <code>-</code> zu setzen um die
        Ermittlung der Daten aus der Datenbank für die Plotgenerierung zu prüfen.<br>
        Durchd ie Angabe des Schlüsselworts <code>all</code> werden alle
        Spalten der Datenbank ausgegeben.
          </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat oder ein Teilstring davon zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;column_spec&gt;<br>
        Für jede column_spec Gruppe wird ein Datenset zurückgegeben welches
        durch einen Kommentar getrennt wird. Dieser Kommentar repräsentiert
        die column_spec.<br>
        Syntax: &lt;device&gt;:&lt;reading&gt;:&lt;default&gt;:&lt;fn&gt;:&lt;regexp&gt;<br>
        <ul>
          <li>&lt;device&gt;<br>
            Der Name des Devices. Achtung: Groß/Kleinschreibung beachten!</li>
          <li>&lt;reading&gt;<br>
            Das REading des angegebenen Devices zur Datenselektion.
            Achtung: Groß/Kleinschreibung beachten!
          </li>
          <li>&lt;default&gt;<br>
            Zur Zeit noch nicht implementiert.
          </li>
          <li>&lt;fn&gt;
            Angabe einer speziellen Funktion:
            <ul>
              <li>int<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE". Benutzt z.B. für Ausprägungen wie 10%.
              </li>
              <li>int&lt;digit&gt;<br>
                Ermittelt den Zahlenwert ab dem Anfang der Zeichenkette aus der
                Spalte "VALUE", inclusive negativen Vorzeichen und Dezimaltrenner.
                Benutzt z.B. für Ausprägungen wie -5.7&deg;C.
              </li>
              <li>delta-h / delta-d<br>
                Ermittelt die relative Veränderung eines Zahlenwertes pro Stunde
                oder pro Tag. Wird benutzt z.B. für Spalten die einen
                hochlaufenden Zähler enthalten wie im Falle für ein KS300 Regenzähler
                oder dem 1-wire Modul OWCOUNT.
              </li>
              <li>delta-ts<br>
                Ermittelt die vergangene Zeit zwischen dem letzten und dem aktuellen Logeintrag
                in Sekunden und ersetzt damit den originalen Wert.
              </li>
            </ul></li>
            <li>&lt;regexp&gt;<br>
              Diese Zeichenkette wird als Perl Befehl ausgewertet. Die regexp wird vor dem angegebenen &lt;fn&gt; Parameter ausgeführt.
              <br>
              Bitte zur Beachtung: Diese Zeichenkette darf keine Leerzeichen
              enthalten da diese sonst als &lt;column_spec&gt; Trennung
              interpretiert werden und alles nach dem Leerzeichen als neue
              &lt;column_spec&gt; gesehen wird.<br>
              <b>Schlüsselwörter</b>
              <li>$val ist der aktuelle Wert die die Datenbank für ein Device/Reading ausgibt.</li>
              <li>$ts ist der aktuelle Timestamp des Logeintrages.</li>
              <li>Wird als $val das Schlüsselwort "hide" zurückgegeben, so wird dieser Logeintrag nicht
                  ausgegeben, trotzdem aber für die Zeitraumberechnung verwendet.</li>
              <li>Wird als $val das Schlüsselwort "ignore" zurückgegeben, so wird dieser Logeintrag
                  nicht für eine Folgeberechnung verwendet.</li>
            </li>
        </ul></li>
      </ul>
    <br><br>
    <b>Beispiele:</b>
      <ul>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10_10 2012-11-10_20 KS300:temperature::int1</code><br>
           gibt Daten aus von 10Uhr bis 20Uhr am 10.11.2012</li>
        <li><code>get myDbLog - all 2012-11-10 2012-11-20 KS300:temperature</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 KS300:temperature KS300:rain::delta-h KS300:rain::delta-d</code></li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 MyFS20:data:::$val=~s/(on|off).*/$1eq"on"?1:0/eg</code><br>
           gibt 1 zurück für alle Ausprägungen von on* (on|on-for-timer etc) und 0 für alle off*</li>
        <li><code>get myDbLog - - 2012-11-10 2012-11-20 Bodenfeuchte:data:::$val=~s/.*B:\s([-\.\d]+).*/$1/eg</code><br>
           Beispiel von OWAD: Ein Wert wie z.B.: <code>"A: 49.527 % B: 66.647 % C: 9.797 % D: 0.097 V"</code><br>
           und die Ausgabe ist für das Reading B folgende: <code>2012-11-20_10:23:54 66.647</code></li>
        <li><code>get DbLog - - 2013-05-26 2013-05-28 Pumpe:data::delta-ts:$val=~s/on/hide/</code><br>
           Realisierung eines Betriebsstundenzählers.Durch delta-ts wird die Zeit in Sek zwischen den Log-
           einträgen ermittelt. Die Zeiten werden bei den on-Meldungen nicht ausgegeben welche einer Abschaltzeit 
           entsprechen würden.</li>
      </ul>
    <br><br>
  </ul>

  <b>Get</b> für die Nutzung von webcharts
  <ul>
    <code>get &lt;name&gt; &lt;infile&gt; &lt;outfile&gt; &lt;from&gt;
          &lt;to&gt; &lt;device&gt; &lt;querytype&gt; &lt;xaxis&gt; &lt;yaxis&gt; &lt;savename&gt; </code>
    <br><br>
    Liest Daten aus der Datenbank aus und gibt diese in JSON formatiert aus. Wird für das Charting Frontend genutzt
    <br>

    <ul>
      <li>&lt;name&gt;<br>
        Der Name des definierten DbLogs, so wie er in der fhem.cfg angegeben wurde.</li>
      <li>&lt;in&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen.
        Dieser Parameter ist immer auf <code>-</code> zu setzen.</li>
      <li>&lt;out&gt;<br>
        Ein Dummy Parameter um eine Kompatibilität zum Filelog herzustellen. 
        Dieser Parameter ist auf <code>webchart</code> zu setzen um die Charting Get Funktion zu nutzen.
      </li>
      <li>&lt;from&gt; / &lt;to&gt;<br>
        Wird benutzt um den Zeitraum der Daten einzugrenzen. Es ist das folgende
        Zeitformat zu benutzen:<br>
        <ul><code>YYYY-MM-DD_HH24:MI:SS</code></ul></li>
      <li>&lt;device&gt;<br>
        Ein String, der das abzufragende Device darstellt.</li>
      <li>&lt;querytype&gt;<br>
        Ein String, der die zu verwendende Abfragemethode darstellt. Zur Zeit unterstützte Werte sind: <br>
          <code>getreadings</code> um für ein bestimmtes device alle Readings zu erhalten<br>
          <code>getdevices</code> um alle verfügbaren devices zu erhalten<br>
          <code>timerange</code> um Chart-Daten abzufragen. Es werden die Parameter 'xaxis', 'yaxis', 'device', 'to' und 'from' benötigt<br>
          <code>savechart</code> um einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration abzuspeichern<br>
          <code>deletechart</code> um einen zuvor gespeicherten Chart unter Angabe einer id zu löschen<br>
          <code>getcharts</code> um eine Liste aller gespeicherten Charts zu bekommen.<br>
          <code>getTableData</code> um Daten aus der Datenbank abzufragen und in einer Tabelle darzustellen. Benötigt paging Parameter wie start und limit.<br>
          <code>hourstats</code> um Statistiken für einen Wert (yaxis) für eine Stunde abzufragen.<br>
          <code>daystats</code> um Statistiken für einen Wert (yaxis) für einen Tag abzufragen.<br>
          <code>weekstats</code> um Statistiken für einen Wert (yaxis) für eine Woche abzufragen.<br>
          <code>monthstats</code> um Statistiken für einen Wert (yaxis) für einen Monat abzufragen.<br>
          <code>yearstats</code> um Statistiken für einen Wert (yaxis) für ein Jahr abzufragen.<br>
      </li>
      <li>&lt;xaxis&gt;<br>
        Ein String, der die X-Achse repräsentiert</li>
      <li>&lt;yaxis&gt;<br>
         Ein String, der die Y-Achse repräsentiert</li>
      <li>&lt;savename&gt;<br>
         Ein String, unter dem ein Chart in der Datenbank gespeichert werden soll</li>
      <li>&lt;chartconfig&gt;<br>
         Ein jsonstring der den zu speichernden Chart repräsentiert</li>
      <li>&lt;pagingstart&gt;<br>
         Ein Integer um den Startwert für die Abfrage 'getTableData' festzulegen</li>
      <li>&lt;paginglimit&gt;<br>
         Ein Integer um den Limitwert für die Abfrage 'getTableData' festzulegen</li>
      </ul>
    <br><br>
    Beispiele:
      <ul>
        <li><code>get logdb - webchart "" "" "" getcharts</code><br>
            Liefert alle gespeicherten Charts aus der Datenbank</li>
        <li><code>get logdb - webchart "" "" "" getdevices</code><br>
            Liefert alle verfügbaren Devices aus der Datenbank</li>
        <li><code>get logdb - webchart "" "" ESA2000_LED_011e getreadings</code><br>
            Liefert alle verfügbaren Readings aus der Datenbank unter Angabe eines Gerätes</li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e timerange TIMESTAMP day_kwh</code><br>
            Liefert Chart-Daten, die auf folgenden Parametern basieren: 'xaxis', 'yaxis', 'device', 'to' und 'from'<br>
            Die Ausgabe erfolgt als JSON, z.B.: <code>[{'TIMESTAMP':'2013-02-11 00:10:10','VALUE':'0.22431388090756'},{'TIMESTAMP'.....}]</code></li>
        <li><code>get logdb - webchart 2013-02-11_00:00:00 2013-02-12_00:00:00 ESA2000_LED_011e savechart TIMESTAMP day_kwh tageskwh</code><br>
            Speichert einen Chart unter Angabe eines 'savename' und seiner zugehörigen Konfiguration</li>
        <li><code>get logdb - webchart "" "" "" deletechart "" "" 7</code><br>
            Löscht einen zuvor gespeicherten Chart unter Angabe einer id</li>
      </ul>
    <br><br>
  </ul>

  <a name="DbLogattr"></a>
  <b>Attribute</b>
  <ul><b>DbLogExclude</b>
    <ul>
      <code>
      set &lt;device&gt; DbLogExclude regex:MinInterval [regex:MinInterval] ...
      </code>
    </ul>
    <br>
    Wenn DbLog genutzt wird, wird in alle Devices das Attribut <i>DbLogExclude</i>
    propagiert. Der Wert des Attributes wird als Regexp ausgewertet und schließt die 
    damit matchenden Readings von einem Logging aus. Einzelne Regexp werden durch 
    Kommata getrennt. Ist MinIntervall angegeben, so wird der Logeintrag nur
    dann nicht geloggt, wenn das Intervall noch nicht erreicht und der Wert des 
    Readings sich nicht verändert hat.
    <br>
    <b>Beispiele</b>
    <ul>
      <code>attr MyDevice1 DbLogExclude .*</code>
      <code>attr MyDevice2 DbLogExclude state,(floorplantext|MyUserReading):300,battery:3600</code>
    </ul>
  </ul><br>

</ul>

=end html_DE
=cut

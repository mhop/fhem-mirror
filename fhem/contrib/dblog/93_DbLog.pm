##############################################
#
# 93_DbLog.pm
# written by Dr. Boris Neubert 2007-12-30
# e-mail: omega at online dot de
#
##############################################

package main;
use strict;
use warnings;
use DBI;

sub DbLog($$$);


################################################################
sub
DbLog_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "DbLog_Define";
  $hash->{UndefFn} = "DbLog_Undef";
  $hash->{NotifyFn} = "DbLog_Log";
  $hash->{AttrFn}   = "DbLog_Attr";
  $hash->{AttrList} = "disable:0,1";
}

#####################################
sub
DbLog_Define($@)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> DbLog configuration regexp" 
	if(int(@a) != 4);

  my $regexp    	= $a[3];

  eval { "Hallo" =~ m/^$regexp$/ };
  return "Bad regexp: $@" if($@);
  $hash->{REGEXP} = $regexp;

  $hash->{configuration}= $a[2];

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
sub
DbLog_ParseEvent($$)
{
  my ($type, $event)= @_;
  my @result;

  # split the event into reading and argument
  # "day-temp: 22.0 (Celsius)" -> "day-temp", "22.0 (Celsius)"
  my @parts= split(/: /,$event);
  my $reading= $parts[0]; if(!defined($reading)) { $reading= ""; }
  my $arg= $parts[1];

  # the interpretation of the argument depends on the device type

  #default
  my $value= $arg; if(!defined($value)) { $value= ""; }
  my $unit= "";


  # EMEM, M232Counter, M232Voltage return plain numbers
  if(($type eq "M232Voltage") || 
     ($type eq "M232Counter") ||
     ($type eq "EMEM")) {
  }
  # FS20
  elsif($type eq "FS20") {
     @parts= split(/ /,$value);
     my $reading= $parts[0]; if(!defined($reading)) { $reading= ""; }
     if($#parts>=1) {
     	$value= join(" ", shift @parts);
	     if($reading =~ m(^dim*%$)) { 
		$value= substr($reading,3,length($reading)-4);
     		$reading= "dim";
		$unit= "%";
	}
      else {
      	$value= "";
      }
     }
  }
  # FHT 
  elsif($type eq "FHT") {
     if($reading =~ m(-temp)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
     if($reading =~ m(temp-offset)) { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
     if($reading eq "actuator") { 
		if($value eq "lime-protection") {
			$reading= "actuator-lime-protection";
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
     if($event =~ m(avg_day)) { $reading= "data"; $value= $event; }
     if($event =~ m(avg_month)) { $reading= "data"; $value= $event; }
     if($reading eq "temperature") { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
     if($reading eq "wind") { $value=~ s/ \(km\/h\)//; $unit= "km/h"; }
     if($reading eq "rain") { $value=~ s/ \(l\/m2\)//; $unit= "l/m2"; }
     if($reading eq "rain_raw") { $value=~ s/ \(counter\)//; $unit= ""; }
     if($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
     if($reading eq "israining") { 
	$value=~ s/ \(yes\/no\)//; 
        $value=~ s/no/0/;
        $value=~ s/yes/1/;
      }
  }
  # HMS
  elsif($type eq "HMS") {
     if($event =~ m(T:.*)) { $reading= "data"; $value= $event; }
     if($reading eq "temperature") { $value=~ s/ \(Celsius\)//; $unit= "°C"; }
     if($reading eq "humidity") { $value=~ s/ \(\%\)//; $unit= "%"; }
     if($reading eq "battery") { 
        $value=~ s/ok/1/;
        $value=~ s/replaced/1/;
        $value=~ s/empty/0/;
     }
   }
  

  @result= ($reading,$value,$unit);
  return @result;
}


################################################################
sub
DbLog_Log($$)
{
  # Log is my entry, Dev is the entry of the changed device
  my ($log, $dev) = @_;
 
  # name and type required for parsing
  my $n= $dev->{NAME};
  my $t= $dev->{TYPE};

  # timestamp in SQL format YYYY-MM-DD hh:mm:ss
  #my ($sec,$min,$hr,$day,$mon,$yr,$wday,$yday,$isdst)= localtime(time);
  #my $ts= sprintf("%04d-%02d-%02d %02d:%02d:%02d", $yr+1900,$mon+1,$day,$hr,$min,$sec);

  my $re = $log->{REGEXP};
  my $max = int(@{$dev->{CHANGED}});
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    $s = "" if(!defined($s));
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/) {
      my $ts = TimeNow();
      $ts = $dev->{CHANGETIME}[$i] if(defined($dev->{CHANGETIME}[$i]));
      # $ts is in SQL format YYYY-MM-DD hh:mm:ss

      my @r= DbLog_ParseEvent($t, $s);
      my $reading= $r[0];
      my $value= $r[1];
      my $unit= $r[2];

      my $is= "(TIMESTAMP, DEVICE, TYPE, EVENT, READING, VALUE, UNIT) VALUES " .
         "('$ts', '$n', '$t', '$s', '$reading', '$value', '$unit')";
      DbLog_ExecSQL($log, "INSERT INTO history" . $is);
      DbLog_ExecSQL($log, "DELETE FROM current WHERE (DEVICE='$n') AND (READING='$reading')");
      DbLog_ExecSQL($log, "INSERT INTO current" . $is);


    }
  }

  return "";
}


################################################################
sub
DbLog_Connect($)
{
  my ($hash)= @_;

  my $configfilename= $hash->{configuration};
  if(!open(CONFIG, $configfilename)) {
	Log 1, "Cannot open database configuration file $configfilename.";
	return 0; }
  my @config=<CONFIG>;
  close(CONFIG);

  my %dbconfig;
  eval join("", @config);

  my $dbconn= $dbconfig{connection};
  my $dbuser= $dbconfig{user};
  my $dbpassword= $dbconfig{password};

  Log 3, "Connecting to database $dbconn with user $dbuser";
  my $dbh = DBI->connect_cached("dbi:$dbconn", $dbuser, $dbpassword);
  if(!$dbh) {
    Log 1, "Can't connect to $dbconn: $DBI::errstr";
    return 0;
  }
  Log 3, "Connection to db $dbconn established";
  $hash->{DBH}= $dbh;
  return 1;
}

################################################################
sub
DbLog_ExecSQL1($$)
{
  my ($dbh,$sql)= @_;
 
  my $sth = $dbh->do($sql);
  if(!$sth) {
    Log 2, "DBLog error: " . $DBI::errstr;
    return 0;
  }
  return 1;
}

sub
DbLog_ExecSQL($$)
{
  my ($hash,$sql)= @_;
 
  Log 5, "Executing $sql";
  my $dbh= $hash->{DBH};
  if(!DbLog_ExecSQL1($dbh,$sql)) {
    #retry
    $dbh->disconnect();
    if(!DbLog_Connect($hash)) {
      Log 2, "DBLog reconnect failed.";
      return 0;
    }
    $dbh= $hash->{DBH};
    if(!DbLog_ExecSQL1($dbh,$sql)) {
      Log 2, "DBLog retry failed.";
      return 0;
    }
    Log 2, "DBLog retry ok.";
  }
  return 1;
}

################################################################
1;

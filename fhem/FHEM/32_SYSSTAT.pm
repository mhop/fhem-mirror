
# $Id$

package main;

use strict;
use warnings;
use Data::Dumper;

use JSON;
use Blocking;

my $SYSSTAT_hasSNMP = 1;

my %SYSSTAT_diskTypes = (
  ".1.3.6.1.2.1.25.2.1.1" => 'Other',
  ".1.3.6.1.2.1.25.2.1.2" => 'Ram',
  ".1.3.6.1.2.1.25.2.1.3" => 'VirtualMemory',
  ".1.3.6.1.2.1.25.2.1.4" => 'FixedDisk',
  ".1.3.6.1.2.1.25.2.1.5" => 'RemovableDisk',
  ".1.3.6.1.2.1.25.2.1.6" => 'FloppyDisk',
  ".1.3.6.1.2.1.25.2.1.7" => 'CompactDisk',
  ".1.3.6.1.2.1.25.2.1.8" => 'RamDisk',
  ".1.3.6.1.2.1.25.2.1.9" => 'FlashMemory',
  ".1.3.6.1.2.1.25.2.1.10" => 'NetworkDisk',
);


sub
SYSSTAT_Initialize($)
{
  my ($hash) = @_;

  eval "use Net::SNMP";
  $SYSSTAT_hasSNMP = 0 if($@);

  $hash->{ReadFn}   = "SYSSTAT_Read";

  $hash->{DefFn}    = "SYSSTAT_Define";
  $hash->{UndefFn}  = "SYSSTAT_Undefine";
  $hash->{ShutdownFn}  = "SYSSTAT_Shutdown";
  $hash->{NotifyFn} = "SYSSTAT_Notify";
  $hash->{SetFn}    = "SYSSTAT_Set";
  $hash->{GetFn}    = "SYSSTAT_Get";
  $hash->{AttrFn}   = "SYSSTAT_Attr";
  $hash->{AttrList} = "disable:1 disabledForIntervals raspberrycpufreq:1 raspberrytemperature:0,1,2 synologytemperature:0,1,2 stat:1 uptime:1,2 load:0 noSSH:1,0 ssh_user";
  $hash->{AttrList} .= " snmp:1,0 mibs:textField-long snmpVersion:1,2 snmpCommunity" if( $SYSSTAT_hasSNMP );
  $hash->{AttrList} .= " filesystems showpercent readings:textField-long readingsFormat:textField-long";
  $hash->{AttrList} .= " useregex:1";
  $hash->{AttrList} .= " $readingFnAttributes";
}

#####################################

sub
SYSSTAT_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> SYSSTAT [interval [interval_fs [host]]]"  if(@a < 2);

  my $interval = 60;
  if(int(@a)>=3) { $interval = $a[2]; }
  if( $interval < 60 ) { $interval = 60; }

  my $interval_fs = $interval * 60;
  if(int(@a)>=4) { $interval_fs = $a[3]; }
  if( $interval_fs < $interval ) { $interval_fs = $interval; }
  if( $interval_fs == $interval ) { $interval_fs = undef; }

  my $host = $a[4] if(int(@a)>=5);;

  delete( $hash->{INTERVAL_FS} );
  delete( $hash->{HOST} );

  $hash->{"HAS_Net::SNMP"} = $SYSSTAT_hasSNMP;

  $hash->{STATE} = "Initialized";
  $hash->{INTERVAL} = $interval;
  $hash->{INTERVAL_FS} = $interval_fs if( defined( $interval_fs ) );

  $hash->{HOST} = $host if( defined( $host ) );

  $hash->{interval_fs} = $interval_fs;

  SYSSTAT_InitSNMP( $hash ) if( $init_done );
  SYSSTAT_Connect($hash) if( $init_done );

  if( !$hash->{HOST} ) {
    $hash->{helper}{has_proc_stat} = ( -r '/proc/stat' );
    $hash->{helper}{has_proc_uptime} = ( -r '/proc/uptime' );
    $hash->{helper}{has_proc_loadavg} = ( -r '/proc/loadavg' );

    my $name = $hash->{NAME};
    Log3 $name, 4, "$name: has_proc_stat: $hash->{helper}{has_proc_stat}";
    Log3 $name, 4, "$name: has_proc_uptime: $hash->{helper}{has_proc_uptime}";
    Log3 $name, 4, "$name: has_proc_loadavg: $hash->{helper}{has_proc_loadavg}";
  }

  return undef;
}
sub
SYSSTAT_Disconnect($)
{
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  RemoveInternalTimer($hash);

  readingsSingleUpdate($hash, 'connection', 'disconnected', 1) if( $hash->{STATE} eq 'Started' ) ;

  return if( !$hash->{FD} );

  if( $hash->{PID} ) {
    kill( 9, $hash->{PID} );
    return;
  }

  close($hash->{FH}) if($hash->{FH});
  delete($hash->{FH});
  delete($hash->{FD});
  delete($selectlist{$name});

  $hash->{PARTIAL} ='';

  $hash->{STATE} = "Disconnected";
  Log3 $name, 3, "$name: Disconnected";
  $hash->{LAST_DISCONNECT} = FmtDateTime( gettimeofday() );
}
sub
SYSSTAT_Connect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  SYSSTAT_Disconnect($hash);

  if( !$hash->{HOST} ) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, "SYSSTAT_GetUpdate", $hash, 0);

    return;

  } elsif( AttrVal($name, "noSSH", undef ) ) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, "SYSSTAT_GetUpdate", $hash, 0);

    return;
  }

  return undef if( AttrVal($name, "disable", undef ) );

  my @queue = ();
  $hash->{QUEUE} = \@queue;

  $hash->{SENT} = 0;
  $hash->{PARSED} = 0;
  $hash->{PARTIAL} ='';
  $hash->{STARTED} = 0;

  my ($child, $parent);
  if( socketpair($child, $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ) {
    $child->autoflush(1);
    $parent->autoflush(1);

    my $pid = fhemFork();

    if(!defined($pid)) {
      close $parent;
      close $child;

      my $msg = "$name: Cannot fork: $!";
      Log 1, $msg;
      return $msg;
    }

    if( $pid ) {
      close $parent;
      $child->blocking(0);

      $hash->{STATE} = "Started";
      $hash->{CONNECTS}++;

      $hash->{FH} = $child;
      $hash->{FD} = fileno($child);
      $hash->{PID} = $pid;

      $selectlist{$name} = $hash;

      SYSSTAT_Write( $hash, 'uname -a' );

      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday()+5, "SYSSTAT_GetUpdate", $hash, 0);

    } else {
      close $child;

      close STDIN;
      close STDOUT;
      close STDERR;

      my $fn = $parent->fileno();
      open(STDIN, "<&$fn") or die "can't redirect STDIN $!";
      open(STDOUT, ">&$fn") or die "can't redirect STDOUT $!";
      open(STDERR, ">&$fn") or die "can't redirect STDOUT $!";

      #select STDIN; $| = 1;
      #select STDOUT; $| = 1;

      #STDIN->autoflush(1);
      STDOUT->autoflush(1);

      close $parent;

      $ENV{PYTHONUNBUFFERED} = 1;

      if( my $home = AttrVal($name, "home", undef ) ) {
        $home = $ENV{'PWD'} if( $home eq 'PWD' );
        $ENV{'HOME'} = $home;
        Log3 $name, 2, "$name: setting \$HOME to $home";
      }

      my $cmd = qx(which ssh);
      chomp( $cmd );
      my $user = AttrVal($hash->{NAME}, "ssh_user", undef );
      $cmd .= ' -q ';
      $cmd .= $user."\@" if( defined($user) );
      $cmd .= $hash->{HOST};
      Log3 $name, 2, "$name: starting: $cmd";

      exec split( ' ', $cmd ) or Log3 $name, 1, "exec failed";

      POSIX::_exit(0);;
    }

  } else {
    $hash->{STATE} = "Stopped";
    Log3 $name, 3, "$name: socketpair failed";
    InternalTimer(gettimeofday()+20, "SYSSTAT_Connect", $hash, 0);
  }
}

sub
SYSSTAT_Write($$;$)
{
  my ($hash,$cmd,$key) = @_;
  my $name = $hash->{NAME};

  return undef if( !$hash->{FH} );

  #FIXME: reconnect if QUEUE > xxx?

  push @{$hash->{QUEUE}}, {cmd => $cmd, key => $key, };
  return if( scalar @{$hash->{QUEUE}} > 1 );

  Log3 $name, 4, "$name: sending: $cmd";
  syswrite $hash->{FH}, "echo \">>>cmd start $hash->{SENT}<<<\"\n";
  syswrite $hash->{FH}, "$cmd\n";
  syswrite $hash->{FH}, "echo \">>>cmd end $hash->{SENT}<<<\"\n";
  ++$hash->{SENT};

  return undef;
}
sub SYSSTAT_Parse($$$);
sub
SYSSTAT_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $ret = sysread($hash->{FH}, $buf, 65536 );
  my $err = int($!);

  if( my $phash = $hash->{phash} ) {

    if( $ret <= 0 ) {
      $hash->{cleanup} = 1;
      SYSSTAT_killChild( $hash );
      return;
    }

    readingsBeginUpdate($phash);
    my $key = $hash->{key};
    my $cmd = $hash->{cmd};
    $buf =~ s/\n$// if( $buf );
    SYSSTAT_Parse($phash,$key?$key:$cmd,$buf);
    readingsEndUpdate($phash, 1);

    return;
  }

  if(!defined($ret) && $err == EWOULDBLOCK) {
    return;
  }

  if(!defined($ret) || $ret <= 0) {
    SYSSTAT_Disconnect( $hash );
    delete $hash->{PID};

    Log3 $name, 3, "$name: read: error during sysread: $!" if(!defined($ret));
    Log3 $name, 3, "$name: read: end of file reached while sysread" if(defined($ret) && $ret <= 0);

    InternalTimer(gettimeofday()+10, "SYSSTAT_Connect", $hash, 0);
    return undef;
  }

  if( $buf =~ m/^(.*)?>>>cmd start (\d+)<<<\n(.*)\n>>>cmd end (\d+)<<<\n(.*)?/ ) {
    $buf = $3;
    $hash->{PARTIAL} = $5;

    $hash->{STARTED} = 0;

  } elsif( $buf =~ m/^>>>cmd start (\d+)<<<(.*)?/ ) {
    $hash->{PARTIAL} = $2;

    $hash->{STARTED} = 1;
    return;

  } elsif( $buf =~ m/(.*)>>>cmd end (\d+)<<<\n?$/ms ) {
    $buf = $hash->{PARTIAL} . $1;

    $hash->{STARTED} = 0;

  } elsif( !$hash->{STARTED} ) {
    return;

  } else {
    $hash->{PARTIAL} .= $buf;
    return;
  }

  my $entry = shift @{$hash->{QUEUE}};

  if( scalar @{$hash->{QUEUE}} ) {
    my $cmd = $hash->{QUEUE}[0]->{cmd};
    Log3 $name, 4, "$name: sending: $cmd";
    syswrite $hash->{FH}, "echo \">>>cmd start $hash->{SENT}<<<\"\n";
    syswrite $hash->{FH}, "$cmd\n";
    syswrite $hash->{FH}, "echo \">>>cmd end $hash->{SENT}<<<\"\n";
    ++$hash->{SENT};
  }

  readingsBeginUpdate($hash);
  my $key = $entry->{key};
  my $cmd = $entry->{cmd};
  $buf =~ s/\n$// if( $buf );
  SYSSTAT_Parse($hash,$key?$key:$cmd,$buf);
  readingsEndUpdate($hash, 1);

  ++$hash->{PARSED};

  return undef;
}
sub
SYSSTAT_killChild($)
{
  my ($chash) = @_;
  my $name = $chash->{NAME};

  kill( 9, $chash->{PID} );

  if( !$chash->{cleanup} ) {
    my $pname = $chash->{phash}->{NAME};
    Log3 $pname, 2, "$pname: timeout reached, killing pid $chash->{PID} for cmd $chash->{cmd}";
  }

  RemoveInternalTimer($chash);

  delete($defs{$name});
  delete($selectlist{$name});
}

sub
SYSSTAT_Parse($$$)
{
  my ($hash,$key,$data) = @_;
  my $name = $hash->{NAME};

  return undef if( !$key ); #FIXME: reconnect ?

  Log3 $name, 5, "$name: parsing: $key <- $data";

  if( $key eq 'uname -a' && $data ) {
    readingsSingleUpdate($hash, 'connection', 'connected', 1);
    $hash->{STATE} = "Connected";

    $hash->{uname} = $data;

    SYSSTAT_Write( $hash, 'ls /proc/stat' );
    SYSSTAT_Write( $hash, 'ls /proc/uptime' );
    SYSSTAT_Write( $hash, 'ls /proc/loadavg' );

  } elsif( $key eq 'ls /proc/stat' && $data ) {
    $hash->{helper}{has_proc_stat} = $data =~ m'^/proc/stat' ? 1 : 0;

    Log3 $name, 4, "$name: has_proc_stat: $hash->{helper}{has_proc_stat}";

  } elsif( $key eq 'ls /proc/uptime' && $data ) {
    $hash->{helper}{has_proc_uptime} = $data =~ m'^/proc/uptime' ? 1 : 0;

    Log3 $name, 4, "$name: has_proc_uptime: $hash->{helper}{has_proc_uptime}";

  } elsif( $key eq 'ls /proc/loadavg' && $data ) {
    $hash->{helper}{has_proc_loadavg} = $data =~ m'^/proc/loadavg' ? 1 : 0;

    Log3 $name, 4, "$name: has_proc_loadavg: $hash->{helper}{has_proc_loadavg}";

  } elsif( $key =~ m/#reading:(.*)/ && $data ) {
    my $reading = $1;
    my $VALUE = $data;

    if( my $value_format = $hash->{helper}{readingsFormat} ) {
      if( ref($value_format) eq 'HASH' ) {
        my $vf = "";
        $vf = $value_format->{$reading} if( defined($reading) && exists($value_format->{$reading}) );
        $vf = $value_format->{$reading.'.'.$VALUE} if( defined($reading) && exists($value_format->{$reading.'.'.$VALUE}) );

        if( !ref($vf) && $vf =~ m/^{.*}$/s) {
          eval $vf;
          $VALUE = $data if( $@ );
          Log3 $name, 2, "$name: $@" if( $@ );

        }

      } else {
        Log3 $name, 2, "$name: readingsFormat is not a hash";

      }
    }

    if( ref($VALUE) eq 'ARRAY' ) {
      my $i = 1;
      foreach my $value (@{$VALUE}) {
        readingsBulkUpdate($hash, $reading.$i, $value);
        ++$i
      }
    } else {
      readingsBulkUpdate($hash, $reading, $VALUE);
    }

  } elsif( $key eq 'cat /proc/loadavg' && $data ) {
    my ($avg_1, $avg_5, $avg_15) = split( ' ', $data, 4 );

    readingsBulkUpdate($hash, 'state', "$avg_1 $avg_5 $avg_15");
    readingsBulkUpdate($hash, 'load', $avg_1);

  } elsif( $key eq 'cat /proc/stat' && $data ) {
    my(undef,@values) = split( ' ', $data, 12 );
    pop @values;
    if( !defined($hash->{helper}{proc_stat_old}) ) {
      $hash->{helper}{proc_stat_old} = \@values;
      return undef;

    } else {
      my @diff = map { $values[$_] - $hash->{helper}{proc_stat_old}->[$_] } 0 .. 4;
      $hash->{helper}{proc_stat_old} = \@values;

      my $sum = 0;
      $sum += $_ for @diff;

      my @percent = map { int($diff[$_]*1000 / $sum)/10 } 0 .. 4;
      if( @percent ) {
        #my($user,$nice,$system,$idle,$iowait,$irq,$softirq,$steal,$guest,$guest_nice) = @percent;
        readingsBulkUpdate($hash,"user", $percent[0]);
        readingsBulkUpdate($hash,"system", $percent[2]);
        readingsBulkUpdate($hash,"idle", $percent[3]);
        readingsBulkUpdate($hash,"iowait", $percent[4]);
      }
    }

  } elsif( $key eq 'cat /proc/uptime' && $data ) {
    my ($uptime) = split(' ', $data, 2 );

    if( AttrVal($name, "uptime", 0) != 2 ) {
      # cut off partial seconds
      $uptime = int( $uptime );
      my $seconds = $uptime % 60;
      $uptime = int($uptime / 60);
      my $minutes = $uptime % 60;
      $uptime = int($uptime / 60);

      my $hours = $uptime % 24;
      my $days = int($uptime / 24);

      $uptime = sprintf( "%d days, %d:%.2d:%.2d", $days, $hours, $minutes, $seconds);
    }

    if( $hash->{BlockingResult} ) {
      $hash->{BlockingResult}{uptime} = $uptime;
    } else {
      readingsBulkUpdate($hash,"uptime",$uptime);
    }

  } elsif( $key eq 'uptime' && $data ) {
    if( $data =~ m/(([.,\d]+)\s([.,\d]+)\s([.,\d]+))$/ ) {
      my $loadavg = $1;
      $loadavg =~ s/, / /g;
      $loadavg =~ s/,/./g;
      SYSSTAT_Parse($hash, 'cat /proc/loadavg', $loadavg);
    }

    if( AttrVal($name, "uptime", 0) > 0 ) {
      ############# match uptime time statement with the different formats seen on linux
      # examples
      #     18:52:21 up 26 days, 21:08,  2 users,  load average: 0.04, 0.03, 0.05
      #     18:52:21 up 26 days, 55 min,  1 user,  load average: 0.05, 0.05, 0.05
      #     18:52:21 up 55 min,  1 user,  load average: 0.05, 0.05, 0.05
      #     18:52:21 up 21:08,  1 user,  load average: 0.05, 0.05, 0.05
      #
      # complex expression to match only the time parts of the uptime result
      # $1 is complete up time information of uptime result
      # $2 is # days part of the uptime
      # $3 just the # from the "# days"" part or nothing if no days are given
      # $4 is complete hour/minutes or # min information
      # $5 is hours part if hours:min are given
      # $6 is minutes part if hours:min are given
      # $7 is minutes if # min is given
      if( $data =~ m/[[:alpha:]]{2}\s*(((\d*)\s*[[:alnum:]]*,?)?\s+((\d+):(\d+)|(\d+)\s+[[:alpha:]]+in[[:alpha:]]*)),?/ ) {
        my $days = $3?$3:0;
        my $hours = $5?$5:0;
        my $minutes = $6?$6:$7;

        my $uptime = $days * 24;
        $uptime += $hours;
        $uptime *= 60;
        $uptime += $minutes;
        $uptime *= 60;

        SYSSTAT_Parse($hash, 'cat /proc/uptime', $uptime);
        return;
      }
    }

  } elsif( $key eq '#freq1000' && $data ) {
    readingsBulkUpdate($hash,"cpufreq",$data/1000);

  } elsif( $key eq '#temp' && $data ) {
    if( $data > 0 && $data < 200  ) {
      if( AttrVal($name, "raspberrytemperature", 0) eq 2 ) {
          $data = sprintf( "%.1f", (3 * ReadingsVal($name,"temperature",$data) + $data ) / 4 );
        } elsif( AttrVal($name, "synologytemperature", 0) eq 2 ) {
          $data = sprintf( "%.1f", (3 * ReadingsVal($name,"temperature",$data) + $data ) / 4 );
        }
      readingsBulkUpdate($hash, 'temperature', $data);
    }

  } elsif( $key eq '#temp1000' && $data ) {
    SYSSTAT_Parse($hash, '#temp', $data/1000);

  } elsif( $data && $key =~ m/#filesystems(:(.*))/ ) {
    my $cl = $2;
    my %filesystems = ();
    foreach my $line (split(/\n/, $data)) {
      next unless $line =~ /^(.+?)\s+(\d+\s+\d+\s+\d+\s.*)$/;
      @{$filesystems{$1}}{qw(
          total
          used
          free
          usageper
          mountpoint
      )} = (split /\s+/, $2)[0..4];

      $filesystems{$1}{usageper} =~ s/%//;
    }

    $hash->{helper}{filesystems} = \%filesystems;

    if( $hash->{filesystems} ) {
      my $usage = $hash->{helper}{filesystems};

      my $type = 'free';
      if( AttrVal($name, "showpercent", "") ne "" ) {
        $type = 'usageper';
      }

      if( AttrVal($name, "useregex", "") eq "" ) {
        for my $filesystem (@{$hash->{filesystems}}) {
          my $fs = $usage->{$filesystem};
          readingsBulkUpdate($hash,$fs->{mountpoint},$fs->{$type});
        }
      } else {
        for my $filesystem (@{$hash->{filesystems}}) {
          foreach my $key (keys %{$usage}) {
            if( $key =~ /$filesystem/ ) {
              my $fs = $usage->{$key};
              readingsBulkUpdate($hash,$fs->{mountpoint},$fs->{$type});
            }
          }
        }
      }
    }

    if( $cl && $defs{$cl} ) {

      my $ret;
      foreach my $filesystem (sort { $a cmp $b } keys %{$hash->{helper}{filesystems}} ) {
        $ret .= sprintf( "%30s  %s\n", $filesystem, $hash->{helper}{filesystems}->{$filesystem}->{mountpoint} );
      }
      $ret = sprintf( "%30s  %s", "<filesystem>", "<mountpoint>\n" ) .$ret if( $ret );

      asyncOutput( $defs{$cl}, $ret ) if( $ret );
    }

  } else {
    Log3 $name, 3, "$name: $key: $data";

  }
}


sub
SYSSTAT_InitSNMP($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  delete( $hash->{session} );

  return if( !$SYSSTAT_hasSNMP );
  return if( !$hash->{USE_SNMP} );

  my $host = "localhost";
  my $community = "public";

  $host = $hash->{HOST} if( defined($hash->{HOST} ) );

  my ( $session, $error ) = Net::SNMP->session(
           -hostname  => $host,
           -community => AttrVal($name,"snmpCommunity","public"),
           -port      => 161,
           -version   => AttrVal($name,"snmpVersion",1),
           -translate =>    [ -timeticks => 0x0 ],
                        );
  if( $error ) {
    Log3 $name, 2, "$name: $error";
  } elsif ( !defined($session) ) {
    Log3 $name, 2, "$name: can't connect to host $host";
  } else {
    $session->timeout(3);
    $hash->{session} = $session;

    my @snmpoids = ( '.1.3.6.1.2.1.1.1.0', '.1.3.6.1.2.1.1.5.0' );
    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);
    $hash->{SystemDescription} = $response->{".1.3.6.1.2.1.1.1.0"};
    $hash->{SystemName} = $response->{".1.3.6.1.2.1.1.5.0"};
  }
}

sub
SYSSTAT_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  SYSSTAT_Disconnect($hash);

  return undef;
}

sub
SYSSTAT_Shutdown($)
{
  my ($hash) = @_;

  RemoveInternalTimer($hash);

  SYSSTAT_Disconnect($hash);

  return undef;
}

sub
SYSSTAT_Notify($$)
{
  my ($hash,$dev) = @_;

  return if($dev->{NAME} ne "global");
  return if(!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  SYSSTAT_InitSNMP( $hash );
  SYSSTAT_Connect($hash);
}

sub
SYSSTAT_Set($@)
{
  my ($hash, $name, $cmd, $arg, @params) = @_;
  return "$name: set needs at least one parameter" if( !$cmd );

  if( $cmd eq 'reconnect' ) {
    SYSSTAT_Connect( $hash );
    return

  } elsif( $cmd eq "raw" ) {
    return "usage: raw <args>" if( !$arg );

    SYSSTAT_Write( $hash, $arg. ' '. join(' ', @params )  );
    return;

  } elsif( $cmd eq "snmpDebug" ) {
    if( defined($hash->{session}) ) {
      $hash->{session}->debug($arg eq 'on' ? 0xff : 0x00 );
    } else {
      return 'no snmp session';
    }

    return;
  }

  my $list = '';
  $list .= 'raw:noArg reconnect:noArg' if( $hash->{HOST} );
  $list .= ' snmpDebug:on,off,' if( $SYSSTAT_hasSNMP );

  return "Unknown argument $cmd, choose one of $list";
}

sub
SYSSTAT_Get($@)
{
  my ($hash, $name, $cmd, $arg, @params) = @_;
  return "$name: get needs at least one parameter" if( !$cmd );

  if($cmd eq "filesystems") {
    my $ret;

    if( !$hash->{HOST} || $hash->{CONNECTS} ) {
      SYSSTAT_getFilesystems($hash);

      return undef;

    } elsif( $hash->{USE_SNMP} && defined($hash->{session}) ) {
      my $types = SYSSTAT_readOIDs($hash,".1.3.6.1.2.1.25.2.3.1.2");
      my $response = SYSSTAT_readOIDs($hash,".1.3.6.1.2.1.25.2.3.1.3");
      foreach my $oid ( sort { ($a =~/\.(\d+)$/)[0] <=> ($b =~/\.(\d+)$/)[0]} keys %$response ) {
        $ret .= "\n" if( $ret );
        my $id = ($oid =~/\.(\d+)$/)[0];
        $ret .= sprintf( "%15s  %s (%s)", $id, $response->{$oid}, $SYSSTAT_diskTypes{$types->{".1.3.6.1.2.1.25.2.3.1.2.$id"}} );
      }
      $ret = sprintf( "%15s  %s", "<filesystem>", "<mountpoint>\n" ) .$ret if( $ret );

    }

    return $ret;

  } elsif( $cmd eq "update" ) {
    $hash->{LOCAL} = 1;
    SYSSTAT_GetUpdate( $hash );
    delete $hash->{LOCAL};
    return;

  }

  return "Unknown argument $cmd, choose one of update:noArg filesystems:noArg";
}

sub
SYSSTAT_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  $attrVal= "" unless defined($attrVal);
  my $orig = $attrVal;
  $attrVal = "1" if($attrName eq "snmp");
  $attrVal = "1" if($attrName eq "useregex");
  $attrVal = "1" if($attrName eq "showpercent");
  $attrVal = "1" if($attrName eq "raspberrycpufreq");

  my $hash = $defs{$name};
  if( $attrName eq 'disable') {
    if( $cmd eq 'set' && $attrVal ne '0' ) {
      $attr{$name}{$attrName} = $attrVal;
    } else {
      $hash->{STATE} = "Disabled";
      RemoveInternalTimer($hash);
      delete $attr{$name}{$attrName};
    }
    $hash->{$attrName} = $attrVal;

    SYSSTAT_Connect($hash)

  } elsif( $attrName eq 'noSSH') {
    if( $cmd eq 'set' && $attrVal ne '0' ) {
      $attr{$name}{$attrName} = $attrVal;
      if( $hash->{HOST} ) {
        SYSSTAT_Disconnect($hash);
        delete $hash->{CONNECTS};
        delete $hash->{helper}{has_proc_loadavg};
        delete $hash->{helper}{has_proc_stat};
        delete $hash->{helper}{has_proc_uptime};
      }

    } else {
      SYSSTAT_Connect($hash);

    }

  } elsif( $attrName eq 'filesystems') {
    my @filesystems = split(',',$attrVal);
    @{$hash->{filesystems}} = @filesystems;

  } elsif( $attrName eq 'ssh_user') {
    $attr{$name}{$attrName} = $attrVal;
    SYSSTAT_Connect( $hash ) if( $init_done );

  } elsif( $attrName eq 'snmpVersion' && $SYSSTAT_hasSNMP ) {
    $hash->{$attrName} = $attrVal;
    SYSSTAT_InitSNMP( $hash );

  } elsif( $attrName eq 'snmpCommunity' && $SYSSTAT_hasSNMP ) {
    $hash->{$attrName} = $attrVal;
    SYSSTAT_InitSNMP( $hash );

  } elsif ($attrName eq 'snmp' && $SYSSTAT_hasSNMP ) {
    if( $cmd eq 'set' && $attrVal ne '0' ) {
      $hash->{USE_SNMP} = $attrVal;
      SYSSTAT_InitSNMP( $hash );
    } else {
      delete $hash->{USE_SNMP};
    }

  } elsif ($attrName eq 'readingsFormat' ) {
    if( $cmd eq "set" ) {
      my $attrVal = $attrVal;

      my %specials= (
        "%VALUE" => "1",
      );

      my $err = perlSyntaxCheck($attrVal, %specials);
      return $err if($err);

      if( $attrVal =~ m/^{.*}$/s && $attrVal =~ m/=>/ ) {
        my $av = eval $attrVal;
        if( $@ ) {
          Log3 $hash->{NAME}, 2, "$hash->{NAME}: $@";
        } else {
          $attrVal = $av if( ref($av) eq "HASH" );
        }
      }

      $hash->{helper}{$attrName} = $attrVal;
    } else {
      delete $hash->{helper}{$attrName};
    }
  }

  if( $cmd eq 'set' ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return "$attrName set to $attrVal";
    }
  }

  return;
}

sub
SYSSTAT_getFilesystems($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: trying /proc/loadavg";

  my $cl = '';
  $cl = ":$hash->{CL}{NAME}" if( $hash->{CONNECTS} && $hash->{CL} );

  if( !$hash->{HOST} || $hash->{CONNECTS} ) {
    if( my $df = SYSSTAT_readCmd($hash, 'df -kP',"#filesystems$cl") ) {
      my $interactive = !defined($hash->{'.updateTimestamp'});
      readingsBeginUpdate($hash) if( $interactive );
      SYSSTAT_Parse($hash, '#filesystems', $df) if( $df );
      readingsEndUpdate($hash, 1) if( $interactive );

      return undef;
    }
  }

  #Log3 $name, 2, "$name: filesystems error";
}
sub
SYSSTAT_getFilesystemsSNMP($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    my %filesystems = ();

    my $showpercent = AttrVal($name, 'showpercent', '') ne '';
    my @snmpoids = ();
    for my $id (@{$hash->{filesystems}}) {
      push @snmpoids, ".1.3.6.1.2.1.25.2.3.1.3.$id";
      push @snmpoids, ".1.3.6.1.2.1.25.2.3.1.4.$id" if( !$showpercent );
      push @snmpoids, ".1.3.6.1.2.1.25.2.3.1.5.$id";
      push @snmpoids, ".1.3.6.1.2.1.25.2.3.1.6.$id";
    }
    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);
    if( $response ) {
      for my $id (@{$hash->{filesystems}}) {
        my $unit = $response->{".1.3.6.1.2.1.25.2.3.1.4.$id"};
        my $free = $response->{".1.3.6.1.2.1.25.2.3.1.5.$id"} - $response->{".1.3.6.1.2.1.25.2.3.1.6.$id"};

        if( $showpercent ) {
          $free =  100 * $response->{".1.3.6.1.2.1.25.2.3.1.6.$id"} / $response->{".1.3.6.1.2.1.25.2.3.1.5.$id"};
          $free = sprintf( '%.1f', $free );
        } else {
          $free *= $unit;
        }
        my $name = $response->{".1.3.6.1.2.1.25.2.3.1.3.$id"};
        if( $name =~ m/^([[:alpha:]]:\\)/ ) {
          $name = $1;
          $name =~ s.\\./.g;
        } else {
          $name =~ s/ //g;
        }

        $hash->{BlockingResult}{$name} = $free;
      }

      return undef;
    }
  }

  Log3 $name, 2, "$name: snmp filesystems error";
}

sub SYSSTAT_getLoadAVG($);
sub SYSSTAT_getPiTemp($);
sub SYSSTAT_getUptime($);
sub
SYSSTAT_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( AttrVal($name, "noSSH", undef) ) {
    my @queue = ();
    $hash->{QUEUE} = \@queue;

  } elsif( $hash->{QUEUE} && scalar @{$hash->{QUEUE}} ) {
    Log3 $name, 2, "$name: unanswered query in queue, reconnecting";
    SYSSTAT_Connect($hash);
    return;
  }

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, 'SYSSTAT_GetUpdate', $hash, 0);

    return if( IsDisabled($name) > 0 );
  }

  my $do_diskusage = 1;
  if( defined($hash->{INTERVAL_FS} ) ) {
    $do_diskusage = 0;
    $hash->{interval_fs} -= $hash->{INTERVAL};

    if( $hash->{interval_fs} <= 0 ) {
      $do_diskusage = 1;
      $hash->{interval_fs} += $hash->{INTERVAL_FS};
    }

    if( $hash->{LOCAL} ) {
      $do_diskusage = 1;
    }
  }

  if( !$hash->{HOST} || $hash->{CONNECTS} ) {
    readingsBeginUpdate($hash);

    SYSSTAT_getLoadAVG( $hash );

    SYSSTAT_getFilesystems($hash) if( $do_diskusage && $#{$hash->{filesystems}} >= 0 );

    SYSSTAT_getPiTemp($hash) if( AttrVal($name, 'raspberrytemperature', 0) > 0 );
    SYSSTAT_getPiFreq($hash) if( AttrVal($name, 'raspberrycpufreq', 0) > 0 );

    SYSSTAT_getStat($hash) if( AttrVal($name, 'stat', 0) > 0 );

    SYSSTAT_getUptime($hash) if( AttrVal($name, 'uptime', 0) > 0 );


    if( my $readings = AttrVal($name, 'readings', undef) ) {
      foreach my $entry (split(/[\n]/, $readings)) {
        next if( !$entry );
        my($reading,$cmd) = split(':', $entry );

        if( my $value = SYSSTAT_readCmd($hash, $cmd, "#reading:$reading") ) {
          SYSSTAT_Parse($hash, "#reading:$reading", $value) if( $value );
        }
      }
    }

    readingsEndUpdate($hash, defined($hash->{LOCAL} ? 0 : 1));
  }

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    $hash->{do_diskusage} = $do_diskusage;
    $hash->{helper}{RUNNING_PID} = BlockingCall("SYSSTAT_BlockingCall", $hash, "SYSSTAT_BlockingDone", 300, "SYSSTAT_BlockingAborted", $hash) unless(exists($hash->{helper}{RUNNING_PID}));
    delete $hash->{do_diskusage};
  }
}
sub
SYSSTAT_GetUpdateSNMP($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( !$hash->{USE_SNMP} || !defined($hash->{session}) ) {
    return undef;
  }

  if(!$hash->{LOCAL}) {
    return undef if( IsDisabled($name) > 0 );
  }

  SYSSTAT_getLoadAVGSNMP($hash) if( AttrVal($name, 'load', 1) > 0 );

  SYSSTAT_getFilesystemsSNMP($hash) if( $hash->{do_diskusage} && $#{$hash->{filesystems}} >= 0 );

  SYSSTAT_getSynoTempSNMP($hash) if( AttrVal($name, 'synologytemperature', 0) > 0 );

  SYSSTAT_getStatSNMP($hash) if( AttrVal($name, 'stat', 0) > 0 );
  SYSSTAT_getUptimeSNMP($hash) if( AttrVal($name, 'uptime', 0) > 0 );

  SYSSTAT_getMIBS($hash);
}

sub
SYSSTAT_getMIBS($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $mibs = AttrVal($name, 'mibs', undef);
  return undef if( !$mibs );

  my @snmpoids;
  foreach my $entry (split(/[ ,\n]/, $mibs)) {
    next if( !$entry );
    my($mib,undef) = split(':', $entry );
    next if( !$mib );

    push @snmpoids, $mib;
  }

  return undef if( !@snmpoids );

  my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

  foreach my $entry (split(/[ ,\n]/, $mibs)) {
    next if( !$entry );
    my($mib,$reading) = split(':', $entry );
    next if( !$mib );
    next if( !$reading );

    my $result = $response->{$mib};
    $hash->{BlockingResult}{$reading} = $result;
  }
}

sub
SYSSTAT_BlockingCall($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{BlockingResult} = {};

  SYSSTAT_GetUpdateSNMP($hash);

  return "$name:".encode_json( $hash->{BlockingResult} );
}

sub
SYSSTAT_BlockingDone($)
{
  my ($string) = @_;
  my ($name,$json) = split(":", $string, 2);
  my $hash = $defs{$name};

  Log3 $name, 4, "$name: BlockingCall finished: $hash->{helper}{RUNNING_PID}{fn}";
  delete($hash->{helper}{RUNNING_PID});

#Log 1, $json;

  my $decoded = decode_json( $json );
  my $in_update = !defined($hash->{'.updateTimestamp'});
  readingsBeginUpdate($hash) if( $in_update );
  foreach my $key (keys %{$decoded}) {
    my $reading = $key;
    my $VALUE = $decoded->{$key};

    if( my $value_format = $hash->{helper}{readingsFormat} ) {
      if( ref($value_format) eq 'HASH' ) {
        my $vf = "";
        $vf = $value_format->{$reading} if( defined($reading) && exists($value_format->{$reading}) );
        $vf = $value_format->{$reading.'.'.$VALUE} if( defined($reading) && exists($value_format->{$reading.'.'.$VALUE}) );

        if( !ref($vf) && $vf =~ m/^{.*}$/s) {
          eval $vf;
          $VALUE = $decoded->{$key} if( $@ );
          Log3 $name, 2, "$name: $@" if( $@ );

        }

      } else {
        Log3 $name, 2, "$name: readingsFormat is not a hash";

      }
    }

    readingsBulkUpdate($hash, $key, $VALUE);
  }
  readingsEndUpdate($hash, 1) if( $in_update );
}
sub
SYSSTAT_BlockingAborted($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 2, "$name: BlockingCall aborted: $hash->{helper}{RUNNING_PID}{fn}";

  delete($hash->{helper}{RUNNING_PID});
}

sub SYSSTAT_readFile($$;$);
sub SYSSTAT_readCmd($$;$);
sub
SYSSTAT_getLoadAVG($ )
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{helper}{has_proc_loadavg} ) {
    Log3 $name, 5, "$name: trying /proc/loadavg";

    my $loadavg = SYSSTAT_readFile($hash, '/proc/loadavg');
    SYSSTAT_Parse($hash, 'cat /proc/loadavg', $loadavg) if( $loadavg );
    return;
  }

  return if( $hash->{USE_SNMP} && defined($hash->{session}) );

  Log3 $name, 5, "$name: trying uptime";
  my $uptime = SYSSTAT_readCmd($hash, 'uptime');
  SYSSTAT_Parse($hash, 'uptime', $uptime ) if( $uptime );
}
sub
SYSSTAT_getLoadAVGSNMP($ )
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( $hash->{helper}{has_proc_loadavg} );

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    Log3 $name, 5, "$name: trying snmp load avg";

    my @snmpoids = ( '.1.3.6.1.4.1.2021.10.1.3.1', '.1.3.6.1.4.1.2021.10.1.3.2', '.1.3.6.1.4.1.2021.10.1.3.3' );
    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    if( !$response ) {
      my $response = SYSSTAT_readOIDs($hash,'.1.3.6.1.2.1.25.3.3.1.2');
      my $avg;
      my %lavg = ();
      my $load;
      foreach my $key (keys %{$response}) {
        $avg .= ',' if( $avg );
        $avg .= $response->{$key};
        $load = 0 if( !$load );
        $load += $response->{$key} / 100;
      }

      $hash->{BlockingResult}{state} = $avg if( defined($avg) );
      $hash->{BlockingResult}{load} = $load if( defined($load) );
      #readingsBulkUpdate($hash, 'state', $avg) if( $avg );
      #readingsBulkUpdate($hash, 'load', $load) if( $load );
      return undef;
    }

    my $avg_1 = $response->{'.1.3.6.1.4.1.2021.10.1.3.1'};
    my $avg_5 = $response->{'.1.3.6.1.4.1.2021.10.1.3.2'};
    my $avg_15 = $response->{'.1.3.6.1.4.1.2021.10.1.3.3'};
    $hash->{BlockingResult}{state} = "$avg_1 $avg_5 $avg_15";
    $hash->{BlockingResult}{load} = $avg_1;
    #readingsBulkUpdate($hash, 'state', "$avg_1 $avg_5 $avg_15");
    #readingsBulkUpdate($hash, 'load', $avg_1);
    return undef;
  }

  Log3 $name, 2, "$name: snmp loadavg error";
}

sub
SYSSTAT_readOIDs($$)
{
  my ($hash,$snmpoids) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{session}) );

  my $response;

  if( ref($snmpoids) eq 'ARRAY' ) {
    $response = $hash->{session}->get_request( @{$snmpoids} );
    Log3 $name, 4, "$name: got empty result from snmp query ".$hash->{session}->error() if( !$response );
  } else {
    $response = $hash->{session}->get_next_request($snmpoids);

    my @snmpoids = ();
    my @nextid   = keys %$response;
    while ( @nextid && $nextid[0] && $nextid[0] =~ m/^$snmpoids/ ) {
      push( @snmpoids, $nextid[0] );

      $response = $hash->{session}->get_next_request( $nextid[0] );
      @nextid   = keys %$response;
    }

    $response = $hash->{session}->get_request( @snmpoids );
    #Log3 $name, 4, "$name: got empty result from snmp query ".$hash->{session}->error() if( !$response );
  }

  return $response;
}

sub
SYSSTAT_readCmd($$;$)
{
  my ($hash,$command,$key) = @_;
  my $name = $hash->{NAME};

  if( defined($hash->{HOST}) ) {
    SYSSTAT_Write( $hash, $command, $key );
    return undef;

    } else {
      if( my $pid = open( my $fh, '-|', $command ) ) {
        if( 1 ) {
          #non-blocking
          my %chash = ();
          $chash{NR}     = $devcount++;
          $chash{STATE}  = $command;
          $chash{TYPE} = $hash->{TYPE};
          $chash{NAME} = "$name:cmd:$chash{NR}";

          $chash{key}   = $key;
          $chash{cmd}   = $command;
          $chash{phash} = $hash;

          $chash{TEMPORARY} = 1;
          $attr{$chash{NAME}}{room} = 'hidden';

          $chash{FH}  = $fh;
          $chash{FD}  = fileno($fh);
          $chash{PID} = $pid;

          $defs{$chash{NAME}} = \%chash;
          $selectlist{$chash{NAME}} = \%chash;
          InternalTimer(gettimeofday()+5, 'SYSSTAT_killChild', \%chash, 0);

          return undef;

        } else {
          #blocking FIXME: does not work if ssh is used somewhere else
          my $value = `$command`;
          return $value;
        }
      }
    }

  return undef;
}
sub
SYSSTAT_readFile($$;$)
{
  my ($hash,$filename,$key) = @_;

  my $value;
  if( defined($hash->{HOST}) ) {
    SYSSTAT_Write( $hash, "cat $filename", $key );
    return undef;

  } else {
    if( open( my $fh, '<', $filename ) )
      {
        $value = <$fh>;

        close($fh);
      }
  }

  return $value;
}

sub
SYSSTAT_getPiTemp($)
{
  my ($hash) = @_;

  my $temp = SYSSTAT_readFile($hash, '/sys/class/thermal/thermal_zone0/temp', '#temp1000');
  SYSSTAT_Parse($hash, '#temp1000', $temp) if( $temp );
}
sub
SYSSTAT_getSynoTempSNMP($)
{
  my ($hash) = @_;

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    my @snmpoids = ( '.1.3.6.1.4.1.6574.1.2.0' );

    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    $hash->{BlockingResult}{temperature} = $response->{'.1.3.6.1.4.1.6574.1.2.0'};
  }
}

sub
SYSSTAT_getPiFreq($)
{
  my ($hash) = @_;

  my $freq = SYSSTAT_readFile($hash, '/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq', '#freq1000');
  SYSSTAT_Parse($hash, '#freq1000', $freq) if( $freq );
}

sub
SYSSTAT_getUptime($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{helper}{has_proc_uptime} ) {
    Log3 $name, 5, "$name: trying /proc/uptime";

    my $uptime = SYSSTAT_readFile($hash, '/proc/uptime');
    SYSSTAT_Parse($hash, 'cat /proc/uptime', $uptime) if( $uptime );
    return;
  }
}
sub
SYSSTAT_getUptimeSNMP($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( $hash->{helper}{has_proc_uptime} );

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    Log3 $name, 5, "$name: trying snmp uptime";

    my @snmpoids = ( '.1.3.6.1.2.1.1.3.0' );

    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    my $uptime = $response->{'.1.3.6.1.2.1.1.3.0'};
    if( defined($uptime) ) {
      SYSSTAT_Parse($hash, 'cat /proc/uptime', $uptime/100);
      return;
    }

    @snmpoids = ( '.1.3.6.1.2.1.25.1.1.0' );

    $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    $uptime = $response->{'.1.3.6.1.2.1.25.1.1.0'};
    if( defined($uptime) ) {
      SYSSTAT_Parse($hash, 'cat /proc/uptime', $uptime/100);
      return;
    }

  }

  Log3 $name, 2, "$name: snmp uptime error";
}

sub
SYSSTAT_getStat($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{helper}{has_proc_stat} ) {
    Log3 $name, 5, "$name: trying /proc/stat";

    my $line = SYSSTAT_readFile($hash, '/proc/stat');
    SYSSTAT_Parse($hash, 'cat /proc/stat', $line) if( $line );
    return;
  }

  return if( $hash->{USE_SNMP} && defined($hash->{session}) );

  Log3 $name, 2, "$name: stat error";
}
sub
SYSSTAT_getStatSNMP($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return if( $hash->{helper}{has_proc_stat} );

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    Log3 $name, 5, "$name: trying snmp stat";

    my @snmpoids = ( '.1.3.6.1.4.1.2021.11.9.0', '.1.3.6.1.4.1.2021.11.10.0', '.1.3.6.1.4.1.2021.11.11.0'  );

    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);
    $hash->{BlockingResult}{user}   = $response->{'.1.3.6.1.4.1.2021.11.9.0'};
    $hash->{BlockingResult}{system} = $response->{'.1.3.6.1.4.1.2021.11.10.0'};
    $hash->{BlockingResult}{idle}   = $response->{'.1.3.6.1.4.1.2021.11.11.0'};

    return;
  }

  Log3 $name, 2, "$name: snmp stat error";
}


1;

=pod
=item device
=item summary    system statistics for local and remote linux (and windows) systems
=item summary_DE Systemstatistiken f&uuml;r lokale und entfernte Linux (und Windows) Rechner
=begin html

<a name="SYSSTAT"></a>
<h3>SYSSTAT</h3>
<ul>
  Provides system statistics for the host FHEM runs on or a remote Linux system that is reachable by preconfigured passwordless ssh access.<br><br>

  Notes:
  <ul>
    <li>To monitor a target by snmp <code>Net::SNMP</code> hast to be installed.<br></li>

    <li>To plot the load values the following code can be used:
  <PRE>
  define sysstatlog FileLog /usr/local/FHEM/var/log/sysstat-%Y-%m.log sysstat
  attr sysstatlog nrarchive 1
  define svg_sysstat SVG sysstatlog:sysstat:CURRENT
  attr wl_sysstat label "Load Min: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"
  attr wl_sysstat room System
  </PRE></li>
    <li>to match the root filesystem  (mount point '/') in diskusage plots use
  '<code>#FileLog 4:/\x3a:0:</code>' or '<code>#FileLog 4:\s..\s:0:</code>'
  and <b>not</b> '<code>#FileLog 4:/:0:</code>' as the later will match all mount points</li>.
  </ul>

  <a name="SYSSTAT_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SYSSTAT [&lt;interval&gt; [&lt;interval_fs&gt;] [&lt;host&gt;]]</code><br>
    <br>

    Defines a SYSSTAT device.<br><br>

    The load is updated every &lt;interval&gt; seconds. The default and minimum is 60.<br><br>
    The diskusage is updated every &lt;interval_fs&gt; seconds. The default is &lt;interval&gt;*60 and the minimum is 60.
    &lt;interval_fs&gt; is only aproximated and works best if &lt;interval_fs&gt; is an integral multiple of &lt;interval&gt;.<br><br>

    If &lt;host&gt; is given it has to be accessible by ssh without the need for a password.

    Examples:
    <ul>
      <code>define sysstat SYSSTAT</code><br>
      <code>define sysstat SYSSTAT 300</code><br>
      <code>define sysstat SYSSTAT 60 600</code><br>
    </ul>
  </ul><br>

  <a name="SYSSTAT_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>load<br>
    the 1 minute load average (for windows targets monitored by snmp aproximated value</li>
    <li>state<br>
    the 1, 5 and 15 minute load averages (or windows targets monitored by snmp the per cpu utilization)</li>
    <li>user,system,idle,iowait<br>
    respective percentage of systemutilization (linux targets only)</li>
    <li>&lt;mountpoint&gt;<br>
    free bytes for &lt;mountpoint&gt;</li>
  </ul><br>

  <a name="SYSSTAT_Set"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of<br><br>
    <li>raw &lt;command&gt;<br>
    Sends &lt;command&gt; to the remote system by ssh.<br>
    <code>set &lt;name&gt; raw shutdown -h now</code></li>
  </ul><br>

  <a name="SYSSTAT_Get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of<br><br>
    <li>filesystems<br>
    Lists the filesystems that can be monitored.</li>
  </ul><br>

  <a name="SYSSTAT_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>noSSH<br>
      </li>
    <li>disable<br>
      keep timers running but disable collection of statistics.</li>
    <li>filesystems<br>
      List of comma separated filesystems (not mountpoints) that should be monitored.<br>
    Examples:
    <ul>
      <code>attr sysstat filesystems /dev/md0,/dev/md2</code><br>
      <code>attr sysstat filesystems /dev/.*</code><br>
      <code>attr sysstat filesystems 1,3,5</code><br>
    </ul></li></lu>
    <li>disabledForIntervals HH:MM-HH:MM HH:MM-HH-MM...</li>
    <li>mibs<br>
      space separated list of &lt;mib&gt;:&lt;reding&gt; pairs that sould be polled.</li>
    <li>readings<br>
      Newline separated liste aus &lt;reading&gt;:&lt;command&gt; pairs should be executed.<br>
<pre>
attr <device> readings processes:ps ax | wc -l\
                        temperature:snmpwalk -c public -v 1 10.0.1.21 .1.3.6.1.4.1.6574.1.2.0 | grep -oE ..$
</pre>
</li>
    <li>readingsFormat<br>
<pre>
attr <device> readings temperature:cat /sys/class/thermal/thermal*/temp\
                        temperatures:cat /sys/class/thermal/thermal*/temp\
                        frequency:cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq

attr <device> readingsFormat { frequency => '{ $VALUE = [map {int($_ / 1000)} split("\n", $VALUE)] }',\
                        temperature => '{ $VALUE = [map {$_ / 1000} split("\n", $VALUE)] }',\
                        temperatures => '{ $VALUE =~ s/\n/ /g }' }
</pre>
    </li>
    <li>showpercent<br>
      If set the usage is shown in percent. If not set the remaining free space in bytes is shown.</li>
    <li>snmp<br>
      1 -> use snmp to monitor load, uptime and filesystems (including physical and virtual memory)</li>
    <li>stat<br>
      1 -> monitor user,system,idle and iowait percentage of system utilization (available only for linux targets)</li>
    <li>raspberrytemperature<br>
      If set and > 0 the raspberry pi on chip termal sensor is read.<br>
      If set to 2 a geometric average over the last 4 values is created.</li>
    <li>synologytemperature<br>
      If set and > 0 the main temperaure of a synology diskstation is read. requires snmp.<br>
      If set to 2 a geometric average over the last 4 values is created.</li>
    <li>raspberrycpufreq<br>
      If set and > 0 the raspberry pi on chip termal sensor is read.</li>
    <li>uptime<br>
      If set and > 0 the system uptime is read.<br>
      If set to 2 the uptime is displayed in seconds.</li>
    <li>load<br>
      If set and = 0 the system load is not read.</li>
    <li>useregex<br>
      If set the entries of the filesystems list are treated as regex.</li>
    <li>ssh_user<br>
      The username for ssh remote access.</li>
    <li>snmpVersion</li>
    <li>snmpCommunity</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>

=end html

=begin html_DE

<a name="SYSSTAT"></a>
<h3>SYSSTAT</h3>
<ul>
  Das Modul stellt Systemstatistiken f&uuml;r den Rechner, auf dem FHEM l&auml;uft bzw.
  f&uuml;r ein entferntes Linux System, das per vorkonfiguriertem ssh Zugang ohne Passwort
  erreichbar ist, zur Vef&uuml;gung.<br><br>

  Notes:
  <ul>
    <li>Dieses Modul ben&ouml;tigt  <code>Sys::Statistics::Linux</code> f&uuml;r Linux.<br>
        Es kann mit '<code>cpan install Sys::Statistics::Linux</code>'<br>
        bzw. auf Debian mit '<code>apt-get install libsys-statistics-linux-perl</code>'
        installiert werden.</li>

    <li>Um einen Zielrechner mit snmp  zu &uuml;berwachen, muss
    <code>Net::SNMP</code> installiert sein.<br></li>

    <li>Um die Lastwerte zu plotten, kann der folgende Code verwendet werden:
  <pre>
  define sysstatlog FileLog /usr/local/FHEM/var/log/sysstat-%Y-%m.log sysstat
  attr sysstatlog nrarchive 1
  define svg_sysstat SVG sysstatlog:sysstat:CURRENT
  attr wl_sysstat label "Load Min: $data{min1}, Max: $data{max1}, Aktuell: $data{currval1}"
  attr wl_sysstat room System
  </pre></li>
    <li>Um das Wurzel-Dateisystem (Mountpunkt '/') bei Plots der Plattennutzung zu erhalten,
    sollte dieser Code '<code>#FileLog 4:/\x3a:0:</code>' bzw. '<code>#FileLog 4:\s..\s:0:</code>'
    und <b>nicht</b> dieser Code '<code>#FileLog 4:/:0:</code>' verwendet werden, da der letztere
    alle Mountpunkte darstellt.</li>.
  </ul>

  <a name="SYSSTAT_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SYSSTAT [&lt;interval&gt; [&lt;interval_fs&gt;] [&lt;host&gt;]]</code><br>
    <br>

    definiert ein SYSSTAT Device.<br><br>

    Die (Prozessor)last wird alle &lt;interval&gt; Sekunden aktualisiert. Standard bzw. Minimum ist 60.<br><br>
    Die Plattennutzung wird alle &lt;interval_fs&gt; Sekunden aktualisiert. Standardwert ist &lt;interval&gt;*60
    und Minimum ist 60.
    &lt;interval_fs&gt; wird nur angen&auml;hert und funktioniert am Besten, wenn &lt;interval_fs&gt;
    ein ganzzahliges Vielfaches von &lt;interval&gt; ist.<br><br>

    Wenn &lt;host&gt; angegeben wird, muss der Zugang per ssh ohne Passwort m&ouml;glich sein.<br><br>

    Beispiele:
    <ul>
      <code>define sysstat SYSSTAT</code><br>
      <code>define sysstat SYSSTAT 300</code><br>
      <code>define sysstat SYSSTAT 60 600</code>
    </ul>
  </ul><br>

  <a name="SYSSTAT_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>load<br>
    die durchschnittliche (Prozessor)last der letzten 1 Minute (f&uuml;r Windows Rechner mit
    snmp angen&auml;hertem Wert)</li>
    <li>state<br>
    die durchschnittliche (Prozessor)last der letzten 1, 5 und 15 Minuten (f&uuml;r Windows
    Rechner die Nutzung pro CPU via snmp ermittelt)</li>
    <li>user, system, idle, iowait<br>
    den Prozentsatz der entsprechenden Systemlast (nur f&uuml;r Linux Systeme)</li>
    <li>&lt;mountpoint&gt;<br>
    Anzahl der freien Bytes f&uuml;r &lt;mountpoint&gt;</li>
  </ul><br>

  <a name="SYSSTAT_Set"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    Werte f&uuml;r <code>value</code> sind<br><br>
    <li>raw &lt;command&gt;<br>
    Sendet &lt;command&gt; per ssh and das entfernte System.<br>
    <code>set &lt;name&gt; raw shutdown -h now</code></li>
  </ul><br>

  <a name="SYSSTAT_Get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    Werte f&uuml;r <code>value</code> sind<br><br>
    <li>filesystems<br>
    zeigt die Dateisysteme an, die &uuml;berwacht werden k&ouml;nnen.</li>
  </ul><br>

  <a name="SYSSTAT_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>noSSH<br>
      </li>
    <li>disable<br>
      l&auml;sst die Timer weiterlaufen, aber stoppt die Speicherung der Daten.</li>
    <li>filesystems<br>
      Liste mit Komma getrennten Dateisystemen (nicht Mountpunkten) die &uuml;berwacht
      werden sollen.<br>
    Beispiele:
    <ul>
      <code>attr sysstat filesystems /dev/md0,/dev/md2</code><br>
      <code>attr sysstat filesystems /dev/.*</code><br>
      <code>attr sysstat filesystems 1,3,5</code><br>
    </ul></li>
    <li>mibs<br>
      Leerzeichen getrennte Liste aus &lt;mib&gt;:&lt;reding&gt; Paaren die abgefragt werden sollen.</li>
    <li>readings<br>
      Newline getrennte Liste aus &lt;reading&gt;:&lt;kommando&gt; Paaren die ausgef&uuml;hrt werden sollen.<br>
<pre>
attr <device> readings processes:ps ax | wc -l\
                        temperature:snmpwalk -c public -v 1 10.0.1.21 .1.3.6.1.4.1.6574.1.2.0 | grep -oE ..$
</pre>
</li>
    <li>readingsFormat<br>
<pre>
attr <device> readings temperature:cat /sys/class/thermal/thermal*/temp\
                        temperatures:cat /sys/class/thermal/thermal*/temp\
                        frequency:cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq

attr <device> readingsFormat { frequency => '{ $VALUE = [map {int($_ / 1000)} split("\n", $VALUE)] }',\
                        temperature => '{ $VALUE = [map {$_ / 1000} split("\n", $VALUE)] }',\
                        temperatures => '{ $VALUE =~ s/\n/ /g }' }
</pre>

    </li>
    <li>showpercent<br>
      Wenn gesetzt, wird die Nutzung in Prozent angegeben. Wenn nicht gesetzt, wird der verf&uuml;bare
      Platz in Bytes angezeigt.</li>
    <li>snmp<br>
      1 -> snmp wird verwendet, um Last, Einschaltzeit und Dateisysteme (inkl. physikalischem und
      virtuellem Speicher) zu &uuml;berwachen</li>
    <li>stat<br>
      1 -> &uuml;berwacht Prozentsatz der user, system, idle und iowait Last
      (nur auf Linux Systemen verf&uuml;gbar)</li>
    <li>raspberrytemperature<br>
      Wenn gesetzt und  > 0 wird der Temperatursensor auf dem Raspberry Pi ausgelesen.<br>
      Wenn Wert 2 ist, wird ein geometrischer Durchschnitt der letzten 4 Werte dargestellt.</li>
    <li>synologytemperature<br>
      Wenn gesetzt und  > 0 wird die Temperatur einer Synology Diskstation ausgelesen (erfordert snmp).<br>
      Wenn Wert 2 ist, wird ein geometrischer Durchschnitt der letzten 4 Werte dargestellt.</li>
    <li>raspberrycpufreq<br>
      Wenn gesetzt und > 0 wird die Raspberry Pi CPU Frequenz ausgelesen.</li>
    <li>uptime<br>
      Wenn gesetzt und > 0 wird die Betriebszeit (uptime) des Systems ausgelesen.<br>
      Wenn Wert 2 ist, wird die Betriebszeit (uptime) in Sekunden angezeigt.</li>
    <li>load<br>
      Wenn gesetzt und = 0 wird die  last (load) des nicht Systems ausgelesen.</li>
    <li>useregex<br>
      Wenn Wert gesetzt, werden die Eintr&auml;ge der Dateisysteme als regex behandelt.</li>
    <li>ssh_user<br>
      Der Username f&uuml;r den ssh Zugang auf dem entfernten Rechner.</li>
    <li>snmpVersion</li>
    <li>snmpCommunity</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>

=end html_DE
=cut

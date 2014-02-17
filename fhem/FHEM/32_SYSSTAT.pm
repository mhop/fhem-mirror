
# $Id$

package main;

use strict;
use warnings;
use Data::Dumper;

my $SYSSTAT_hasSysStatistics = 1;
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

  eval "use Sys::Statistics::Linux::LoadAVG";
  $SYSSTAT_hasSysStatistics = 0 if($@);
  eval "use Sys::Statistics::Linux::DiskUsage";
  $SYSSTAT_hasSysStatistics = 0 if($@);

  eval "use Net::SNMP";
  $SYSSTAT_hasSNMP = 0 if($@);

  $hash->{DefFn}    = "SYSSTAT_Define";
  $hash->{UndefFn}  = "SYSSTAT_Undefine";
  $hash->{GetFn}    = "SYSSTAT_Get";
  $hash->{AttrFn}   = "SYSSTAT_Attr";
  $hash->{AttrList} = "disable:1 raspberrycpufreq:1 raspberrytemperature:0,1,2 synologytemperature:0,1,2 stat:1 uptime:1,2 ssh_user ";
  $hash->{AttrList} .= " snmp:1";
  $hash->{AttrList} .= " filesystems showpercent";
  $hash->{AttrList} .= " useregex:1" if( $SYSSTAT_hasSysStatistics );
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

  $hash->{"HAS_Sys::Statistics"} = $SYSSTAT_hasSysStatistics;
  $hash->{"HAS_Net::SNMP"} = $SYSSTAT_hasSNMP;

  $hash->{STATE} = "Initialized";
  $hash->{INTERVAL} = $interval;
  $hash->{INTERVAL_FS} = $interval_fs if( defined( $interval_fs ) );

  $hash->{HOST} = $host if( defined( $host ) );

  $hash->{interval_fs} = $interval_fs;
  SYSSTAT_InitSys( $hash ) if( $SYSSTAT_hasSysStatistics );
  SYSSTAT_InitSNMP( $hash ) if( $SYSSTAT_hasSNMP );

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SYSSTAT_GetUpdate", $hash, 0);

  return undef;
}
sub
SYSSTAT_InitSys($)
{
  my ($hash) = @_;

  return if( !$SYSSTAT_hasSysStatistics );

  if( defined($hash->{HOST}) ) {
    my $cmd = qx(which ssh);
    chomp( $cmd );
    my $user = AttrVal($hash->{NAME}, "ssh_user", undef );
    $cmd .= ' ';
    $cmd .= $user."\@" if( defined($user) );
    $cmd .= $hash->{HOST}." df -kP 2>/dev/null";
    $hash->{loadavg} = Sys::Statistics::Linux::LoadAVG->new;
    $hash->{diskusage} = Sys::Statistics::Linux::DiskUsage->new( cmd => { path => '',
                                                                          df => $cmd } );
  } else {
    $hash->{loadavg} = Sys::Statistics::Linux::LoadAVG->new;
    $hash->{diskusage} = Sys::Statistics::Linux::DiskUsage->new;
  }
}
sub
SYSSTAT_InitSNMP($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  delete( $hash->{session} );

  return if( !$SYSSTAT_hasSNMP );

  my $host = "localhost";
  my $community = "public";

  $host = $hash->{HOST} if( defined($hash->{HOST} ) );

  my ( $session, $error ) = Net::SNMP->session(
           -hostname  => $host,
           -community => $community,
           -port      => 161,
           -version   => 1
                        );
  if( $error ) {
    Log3 $name, 2, "$name: $error";
  } elsif ( !defined($session) ) {
    Log3 $name, 2, "$name: can't connect to host $host";
  } else {
    $hash->{session} = $session;
  }
}

sub
SYSSTAT_Undefine($$)
{
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

sub
SYSSTAT_Get($@)
{
  my ($hash, @a) = @_;

  my $name = $a[0];
  return "$name: get needs at least one parameter" if(@a < 2);

  my $cmd= $a[1];

  if($cmd eq "filesystems") {
    my $ret;

    if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
      my $types = SYSSTAT_readOIDs($hash,".1.3.6.1.2.1.25.2.3.1.2");
      my $response = SYSSTAT_readOIDs($hash,".1.3.6.1.2.1.25.2.3.1.3");
      foreach my $oid ( sort { ($a =~/\.(\d+)$/)[0] <=> ($b =~/\.(\d+)$/)[0]} keys %$response ) {
        $ret .= "\n" if( $ret );
        my $id = ($oid =~/\.(\d+)$/)[0];
        $ret .= $id ." <= ". $response->{$oid} ."  (". $SYSSTAT_diskTypes{$types->{".1.3.6.1.2.1.25.2.3.1.2.$id"}} .")";
      }
      $ret = "<id> => <filesystem>\n$ret" if( $ret );
    } elsif(defined($hash->{diskusage})) {
      my $filesystems = $hash->{diskusage}->get;
      $ret = "<filesystem> <= <mountpoint>";
      foreach my $filesystem (keys %$filesystems ) {
        $ret .= "\n" if( $ret );
        $ret .= $filesystem ." <= ". $filesystems->{$filesystem}->{mountpoint};
      }
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

  if( $attrName eq "filesystems") {
    my $hash = $defs{$name};
    my @filesystems = split(",",$attrVal);
    @{$hash->{filesystems}} = @filesystems;
  } elsif( $attrName eq "ssh_user") {
    $attr{$name}{$attrName} = $attrVal;
    my $hash = $defs{$name};
    SYSSTAT_InitSys( $hash ) if( $SYSSTAT_hasSysStatistics );
  } elsif ($attrName eq "snmp" && $SYSSTAT_hasSNMP ) {
    my $hash = $defs{$name};
    if( $cmd eq "set" && $attrVal ne "0" ) {
      $hash->{USE_SNMP} = $attrVal;
    } else {
      delete $hash->{USE_SNMP};
    }
  }

  if( $cmd eq "set" ) {
    if( $orig ne $attrVal ) {
      $attr{$name}{$attrName} = $attrVal;
      return $attrName ." set to ". $attrVal;
    }
  }

  return;
}

sub SYSSTAT_getLoadAVG($);
sub SYSSTAT_getPiTemp($);
sub SYSSTAT_getUptime($);
sub
SYSSTAT_GetUpdate($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SYSSTAT_GetUpdate", $hash, 0);

    return if( AttrVal($name,"disable", 0) > 0 );
  }

  my $load = SYSSTAT_getLoadAVG( $hash );

  readingsBeginUpdate($hash);

  my $state = undef;
  $state = $load->{state} if( defined($load->{state}) );
  $state = $load->{avg_1} . " " . $load->{avg_5} . " " . $load->{avg_15} if( !$state && defined($load->{avg_1}) );

  readingsBulkUpdate($hash,"state",$state);

  readingsBulkUpdate($hash,"load",$load->{avg_1});

  my $do_diskusage = 1;
  if( defined($hash->{INTERVAL_FS} ) ) {
    $do_diskusage = 0;
    $hash->{interval_fs} -= $hash->{INTERVAL};

    if( $hash->{interval_fs} <= 0 ) {
        $do_diskusage = 1;
        $hash->{interval_fs} += $hash->{INTERVAL_FS};
      }
  }

  if( $do_diskusage
      && $#{$hash->{filesystems}} >= 0 ) {

    if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
      my $showpercent = AttrVal($name, "showpercent", "") ne "";
      my @snmpoids = ();
      for my $id (@{$hash->{filesystems}}) {
        push @snmpoids, sprintf( ".1.3.6.1.2.1.25.2.3.1.3.%i", $id );
        push @snmpoids, sprintf( ".1.3.6.1.2.1.25.2.3.1.4.%i", $id ) if( !$showpercent );
        push @snmpoids, sprintf( ".1.3.6.1.2.1.25.2.3.1.5.%i", $id );
        push @snmpoids, sprintf( ".1.3.6.1.2.1.25.2.3.1.6.%i", $id );
      }
      my $response = SYSSTAT_readOIDs($hash,\@snmpoids);
      for my $id (@{$hash->{filesystems}}) {
        my $unit = $response->{sprintf( ".1.3.6.1.2.1.25.2.3.1.4.%i", $id )};
        my $free = $response->{sprintf( ".1.3.6.1.2.1.25.2.3.1.5.%i", $id )} - $response->{sprintf( ".1.3.6.1.2.1.25.2.3.1.6.%i", $id )};

       if( $showpercent ) {
         $free =  100 * $response->{sprintf( ".1.3.6.1.2.1.25.2.3.1.6.%i", $id )} / $response->{sprintf( ".1.3.6.1.2.1.25.2.3.1.5.%i", $id )};
         $free = sprintf( "%.1f", $free );
       } else {
         $free *= $unit;
       }
        my $name = $response->{sprintf( ".1.3.6.1.2.1.25.2.3.1.3.%i", $id )};
        if( $name =~ m/^([[:alpha:]]:\\)/ ) {
          $name = $1
        } else {
          $name =~ s/ //g;
        }

        readingsBulkUpdate($hash,$name,$free);
      }

    } elsif( defined($hash->{diskusage} ) ) {
      my $usage = $hash->{diskusage}->get;

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
          foreach my $key (keys %$usage) {
            if( $key =~ /$filesystem/ ) {
              my $fs = $usage->{$key};
              readingsBulkUpdate($hash,$fs->{mountpoint},$fs->{$type});
            }
          }
        }
      }
    }
  }

  if( AttrVal($name, "raspberrytemperature", 0) > 0 ) {
    my $temp = SYSSTAT_getPiTemp($hash);
    if( $temp > 0 && $temp < 200  ) {
      if( AttrVal($name, "raspberrytemperature", 0) eq 2 ) {
          $temp = sprintf( "%.1f", (3 * ReadingsVal($name,"temperature",$temp) + $temp ) / 4 );
        }
      readingsBulkUpdate($hash,"temperature",$temp);
    }
  } elsif( AttrVal($name, "synologytemperature", 0) > 0 ) {
    my $temp = SYSSTAT_getSynoTemp($hash);
    if( $temp > 0 && $temp < 200  ) {
      if( AttrVal($name, "raspberrytemperature", 0) eq 2 ) {
          $temp = sprintf( "%.1f", (3 * ReadingsVal($name,"temperature",$temp) + $temp ) / 4 );
        }
      readingsBulkUpdate($hash,"temperature",$temp);
    }
  }

  if( AttrVal($name, "raspberrycpufreq", 0) > 0 ) {
    my $freq = SYSSTAT_getPiFreq($hash);
    readingsBulkUpdate($hash,"cpufreq",$freq);
  }

  if( AttrVal($name, "stat", 0) > 0 ) {
    my @percent = SYSSTAT_getStat($hash);

    if( @percent ) {
      #my($user,$nice,$system,$idle,$iowait,$irq,$softirq,$steal,$guest,$guest_nice) = @percent;
      readingsBulkUpdate($hash,"user", $percent[0]);
      readingsBulkUpdate($hash,"system", $percent[2]);
      readingsBulkUpdate($hash,"idle", $percent[3]);
      readingsBulkUpdate($hash,"iowait", $percent[4]);
    }
  }

  if( AttrVal($name, "uptime", 0) > 0 ) {
    my $uptime = SYSSTAT_getUptime($hash);
    readingsBulkUpdate($hash,"uptime",$uptime);
  }

  readingsEndUpdate($hash,defined($hash->{LOCAL} ? 0 : 1));
}

sub
SYSSTAT_getLoadAVG($ )
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    my @snmpoids = ( ".1.3.6.1.4.1.2021.10.1.3.1", ".1.3.6.1.4.1.2021.10.1.3.2", ".1.3.6.1.4.1.2021.10.1.3.3" );
    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    if( !$response ) {
      my $response = SYSSTAT_readOIDs($hash,".1.3.6.1.2.1.25.3.3.1.2");
      my $avg = "";
      my %lavg = ();
      my $load = 0;
      foreach my $key (keys %$response) {
        $avg .= "," if( $avg ne "" );
        $avg .= $response->{$key};
        $load += $response->{$key} / 100;
      }
      $lavg{avg_1} = $load if( $avg ne "" );
      $lavg{state} = $avg if( $avg ne "" );
      return \%lavg;
    }

    my %lavg = ();
    $lavg{avg_1} = $response->{".1.3.6.1.4.1.2021.10.1.3.1"};
    $lavg{avg_5} = $response->{".1.3.6.1.4.1.2021.10.1.3.2"};
    $lavg{avg_15} = $response->{".1.3.6.1.4.1.2021.10.1.3.3"};
    return \%lavg;
  }

  return undef if( !defined($hash->{loadavg}) );

  if( defined($hash->{HOST}) ) {
    no strict;
    no warnings 'redefine';
    local *Sys::Statistics::Linux::LoadAVG::get = sub {
      my $self  = shift;
      my $class = ref $self;
      my $file  = $self->{files};
      my %lavg  = ();

      my $cmd = qx(which ssh);
      chomp( $cmd );
      my $user = AttrVal($hash->{NAME}, "ssh_user", undef );
      $cmd .= ' ';
      $cmd .= $user."\@" if( defined($user) );
      $cmd .= $hash->{HOST}." cat /proc/loadavg 2>/dev/null";
      my $fh;
      if( open($fh, "$cmd|" ) ) {
        ( $lavg{avg_1}
        , $lavg{avg_5}
        , $lavg{avg_15}
        ) = (split /\s+/, <$fh>)[0..2];

        close($fh);
      }
      return \%lavg;
    };

    return $hash->{loadavg}->get;
  }

  return $hash->{loadavg}->get;
}

sub
SYSSTAT_readOIDs($$)
{
  my ($hash,$snmpoids) = @_;
  my $name = $hash->{NAME};

  return undef if( !defined($hash->{session}) );

  my $response;

  if( ref($snmpoids) eq "ARRAY" ) {
    $response = $hash->{session}->get_request( @{$snmpoids} );
    Log3 $name, 4, "$name: got empty result from snmp query" if( !$response );
  } else {
    $response = $hash->{session}->get_next_request($snmpoids);

    my @snmpoids = ();
    my @nextid   = keys %$response;
    while ( $nextid[0] =~ m/^$snmpoids/ ) {
      push( @snmpoids, $nextid[0] );

      $response = $hash->{session}->get_next_request( $nextid[0] );
      @nextid   = keys %$response;
    }

    $response = $hash->{session}->get_request( @snmpoids )
  }

  return $response;
}

sub
SYSSTAT_readCmd($$$)
{
  my ($hash,$command,$default) = @_;

  my $value = $default;
  if( defined($hash->{HOST}) ) {
      my $cmd = qx(which ssh);
      chomp( $cmd );
      my $user = AttrVal($hash->{NAME}, "ssh_user", undef );
      $cmd .= ' ';
      $cmd .= $user."\@" if( defined($user) );
      $cmd .= $hash->{HOST}." $command 2>/dev/null";
      if( open(my $fh, "$cmd|" ) ) {
        $value = <$fh>;
        close($fh);
      }
    } else {
      if( open( my $fh, "$command|" ) )
        {
          $value = <$fh>;

          close($fh);
        }
    }

  return $value;
}
sub
SYSSTAT_readFile($$$)
{
  my ($hash,$filename,$default) = @_;

  my $value = $default;
  if( defined($hash->{HOST}) ) {
      my $cmd = qx(which ssh);
      chomp( $cmd );
      my $user = AttrVal($hash->{NAME}, "ssh_user", undef );
      $cmd .= ' ';
      $cmd .= $user."\@" if( defined($user) );
      $cmd .= $hash->{HOST}." cat ". $filename ." 2>/dev/null";
      if( open(my $fh, "$cmd|" ) ) {
        $value = <$fh>;
        close($fh);
      }
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

  my $temp = SYSSTAT_readFile($hash,"/sys/class/thermal/thermal_zone0/temp",-1);

  return $temp / 1000;
}
sub
SYSSTAT_getSynoTemp($)
{
  my ($hash) = @_;

  my $temp = -1;
  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    my @snmpoids = ( ".1.3.6.1.4.1.6574.1.2.0" );

    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    $temp = $response->{".1.3.6.1.4.1.6574.1.2.0"};
  }

  return $temp;
}

sub
SYSSTAT_getPiFreq($)
{
  my ($hash) = @_;

  my $freq = SYSSTAT_readFile($hash,"/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq",0);

  return $freq / 1000;
}

sub
SYSSTAT_getUptime($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
      my @snmpoids = ( ".1.3.6.1.2.1.25.1.1.0" );

      my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

      my $uptime = $response->{".1.3.6.1.2.1.25.1.1.0"};
      if( AttrVal($name, "uptime", 0) == 2 ) {
        if( $uptime && $uptime =~ m/(\d+)\s\D+,\s(\d+):(\d+):(\d+)/ ) {
          my $days = $1?$1:0;
          my $hours = $2;
          my $minutes = $3;
          my $seconds = $4;

          $uptime = $days * 24;
          $uptime += $hours;
          $uptime *= 60;
          $uptime += $minutes;
          $uptime *= 60;
          $uptime += $seconds;
        }
      }

      return $uptime;
    }

  my $uptime = SYSSTAT_readCmd($hash,"uptime",0);

  $uptime = $1 if( $uptime && $uptime =~ m/[[:alpha:]]{2}\s+(((\d+)\D+,?\s+)?(\d+):(\d+))/ );
  $uptime = "0 days, $uptime" if( $uptime && !$2);

  if( AttrVal($name, "uptime", 0) == 2 ) {
    my $days = $3?$3:0;
    my $hours = $4;
    my $minutes = $5;

    $uptime = $days * 24;
    $uptime += $hours;
    $uptime *= 60;
    $uptime += $minutes;
    $uptime *= 60;
  }

  return $uptime;
}

sub
SYSSTAT_getStat($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if( $hash->{USE_SNMP} && defined($hash->{session}) ) {
    my @snmpoids = ( ".1.3.6.1.4.1.2021.11.9.0", ".1.3.6.1.4.1.2021.11.10.0", ".1.3.6.1.4.1.2021.11.11.0"  );

    my $response = SYSSTAT_readOIDs($hash,\@snmpoids);

    my @percent = ( $response->{".1.3.6.1.4.1.2021.11.9.0"},        # user
                    undef,
                    $response->{".1.3.6.1.4.1.2021.11.10.0"},       # system
                    $response->{".1.3.6.1.4.1.2021.11.11.0"} );     # idle

    return @percent;
  }

  my $line = SYSSTAT_readFile($hash,"/proc/stat","");
  #my($user,$nice,$system,$idle,$iowait,$irq,$softirq,$steal,$guest,$guest_nice) = split( " ", $Line );
  my($dummy,@values) = split( " ", $line );

  if( !defined($hash->{values}) ) {
    $hash->{values} = \@values;
    return undef;
  } else {
    my @diff = map { $values[$_] - $hash->{values}->[$_] } 0 .. $#values;
    $hash->{values} = \@values;

    my $sum = 0;
    $sum += $_ for @diff;

    my @percent = map { int($diff[$_]*1000 / $sum)/10 } 0 .. $#values;
    return @percent;
  }
}


1;

=pod
=begin html

<a name="SYSSTAT"></a>
<h3>SYSSTAT</h3>
<ul>
  Provides system statistics for the host FHEM runs on or a remote Linux system that is reachable by preconfigured passwordless ssh access.<br><br>

  Notes:
  <ul>
    <li>This module needs <code>Sys::Statistics::Linux</code> on Linux.<br>
        It can be installed with '<code>cpan install Sys::Statistics::Linux</code>'<br>
        or on debian with '<code>apt-get install libsys-statistics-linux-perl</code>'</li>

    <li>To monitor a target by snmp <code>Net::SNMP</code> hast to be installed.<br></li>

    <li>To plot the load values the following code can be used:
  <PRE>
  define sysstatlog FileLog /usr/local/FHEM/var/log/sysstat-%Y-%m.log sysstat
  attr sysstatlog nrarchive 1
  define wl_sysstat weblink fileplot sysstatlog:sysstat:CURRENT
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
    <li>useregex<br>
      If set the entries of the filesystems list are treated as regex.</li>
    <li>ssh_user<br>
      The username for ssh remote access.</li>
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
  define wl_sysstat weblink fileplot sysstatlog:sysstat:CURRENT
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
    <li>useregex<br>
      Wenn Wert gesetzt, werden die Eintr&auml;ge der Dateisysteme als regex behandelt.</li>
    <li>ssh_user<br>
      Der Username f&uuml;r den ssh Zugang auf dem entfernten Rechner.</li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
</ul>

=end html_DE
=cut

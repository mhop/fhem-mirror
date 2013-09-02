
# $Id$

package main;

use strict;
use warnings;
use Sys::Statistics::Linux::LoadAVG;
use Sys::Statistics::Linux::DiskUsage;

sub
SYSSTAT_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "SYSSTAT_Define";
  $hash->{UndefFn}  = "SYSSTAT_Undefine";
  $hash->{GetFn}    = "SYSSTAT_Get";
  $hash->{AttrFn}   = "SYSSTAT_Attr";
  $hash->{AttrList} = "filesystems raspberrycpufreq:1 raspberrytemperature:0,1,2 showpercent:1 uptime:1,2 useregex:1 ssh_user ".
                       $readingFnAttributes;
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

  $hash->{STATE} = "Initialized";
  $hash->{INTERVAL} = $interval;
  $hash->{INTERVAL_FS} = $interval_fs if( defined( $interval_fs ) );

  $hash->{HOST} = $host if( defined( $host ) );

  $hash->{interval_fs} = $interval_fs;
  SYSSTAT_InitSys( $hash );

  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SYSSTAT_GetUpdate", $hash, 0);

  return undef;
}
sub
SYSSTAT_InitSys($)
{
  my ($hash) = @_;

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

    my $filesystems = $hash->{diskusage}->get;

    my $ret;
    $ret .= "<filesystem> <= <mountpoint>\n";
    foreach my $filesystem (keys %$filesystems ) {
      $ret .= $filesystem ." <= ". $filesystems->{$filesystem}->{mountpoint} ."\n";
    }
    return $ret;
  }

  return "Unknown argument $cmd, choose one of filesystems:noArg";
}

sub
SYSSTAT_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  $attrVal= "" unless defined($attrVal);
  my $orig = $attrVal;
  $attrVal= "1" if($attrName eq "useregex");
  $attrVal= "1" if($attrName eq "showpercent");
  $attrVal= "1" if($attrName eq "raspberrycpufreq");

  if( $attrName eq "filesystems") {
    my $hash = $defs{$name};
    my @filesystems = split(",",$attrVal);
    @{$hash->{filesystems}} = @filesystems;
  } elsif( $attrName eq "ssh_user") {
    $attr{$name}{$attrName} = $attrVal;
    my $hash = $defs{$name};
    SYSSTAT_InitSys( $hash );
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
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SYSSTAT_GetUpdate", $hash, 1);
  }

  #my $load = $hash->{loadavg}->get;
  my $load = SYSSTAT_getLoadAVG( $hash );

  readingsBeginUpdate($hash);

  my $state = $load->{avg_1} . " " . $load->{avg_5} . " " . $load->{avg_15} if( defined($load->{avg_1}) );

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

  if( AttrVal($name, "raspberrytemperature", "0") > 0 ) {
    my $temp = SYSSTAT_getPiTemp($hash);
    if( $temp > 0 && $temp < 200  ) {
      if( AttrVal($name, "raspberrytemperature", "0") eq 2 ) {
          $temp = sprintf( "%.1f", (3 * ReadingsVal($name,"temperature",$temp) + $temp ) / 4 );
        }
      readingsBulkUpdate($hash,"temperature",$temp);
    }
  }

  if( AttrVal($name, "raspberrycpufreq", "0") > 0 ) {
    my $freq = SYSSTAT_getPiFreq($hash);
    readingsBulkUpdate($hash,"cpufreq",$freq);
  }

  if( AttrVal($name, "uptime", "0") > 0 ) {
    my $uptime = SYSSTAT_getUptime($hash);
    readingsBulkUpdate($hash,"uptime",$uptime);
  }


  readingsEndUpdate($hash,defined($hash->{LOCAL} ? 0 : 1));
}

sub
SYSSTAT_getLoadAVG($ )
{
  my ($hash) = @_;

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

  my $uptime = SYSSTAT_readCmd($hash,"uptime",0);

  $uptime = $1 if( $uptime =~ m/up\s+(((\d+)\D+,\s+)?(\d+):(\d+))/ ); 
  $uptime = "0 days, $uptime" if( !$2);

  if( AttrVal($name, "uptime", "0") == 2 ) {
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


1;

=pod
=begin html

<a name="SYSSTAT"></a>
<h3>SYSSTAT</h3>
<ul>
  Provides system statistics for the host FHEM runs on or a remote Linux system that is reachable by preconfigured passwordless ssh access.<br><br>

  Notes:
  <ul>
    <li>currently only Linux is supported.</li>
    <li>This module needs <code>Sys::Statistics::Linux</code> on Linux.<br>
        It can be installed with '<code>cpan install Sys::Statistics::Linux</code>'<br>
        or on debian with '<code>apt-get install libsys-statistics-linux-perl</code>'</li>

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
    the 1 minute load average</li>
    <li>state<br>
    the 1, 5 and 15 minute load averages</li>
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
    <li>filesystems<br>
      List of comma separated filesystems (not mountpoints) that should be monitored.<br>
    Examples:
    <ul>
      <code>attr sysstat filesystems /dev/md0,/dev/md2</code><br>
      <code>attr sysstat filesystems /dev/.*</code><br>
    </ul></li></lu>
    <li>showpercent<br>
      If set the usage is shown in percent. If not set the remaining free space in bytes is shown.</li>
    <li>raspberrytemperature<br>
      If set and > 0 the raspberry pi on chip termal sensor is read.<br>
      If set to 2 a geometric average over the last 4 values is created.</li>
    <li>raspberrycpufreq<br>
      If set and > 0 the raspberry pi on chip termal sensor is read.<br>
      If set to 2 a geometric average over the last 4 values is created.</li>
    <li>uptime<br>
      If set and > 0 the system uptime is read.<br>
      If set to 2 the uptime is displayed in seconds.</li>
    <li>useregex<br>
      If set the entries of the filesystems list are treated as regex.</li>
    <li>ssh_user<br>
      The username for ssh remote access.</li>
    <li>readingFnAttributes</li>
  </ul>
</ul>

=end html
=cut

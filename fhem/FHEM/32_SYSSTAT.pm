
package main;

use strict;
use warnings;
use Sys::Statistics::Linux;

sub
SYSSTAT_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "SYSSTAT_Define";
  $hash->{UndefFn}  = "SYSSTAT_Undefine";
  $hash->{GetFn}    = "SYSSTAT_Get";
  $hash->{AttrFn}   = "SYSSTAT_Attr";
  $hash->{AttrList} = "filesystems showpercent:1 useregex:1 loglevel:0,1,2,3,4,5,6 ".
                       $readingFnAttributes;
}

#####################################

sub
SYSSTAT_Define($$)
{
  my ($hash, $def) = @_;

  my @a = split("[ \t][ \t]*", $def);

  return "Usage: define <name> SYSSTAT [interval]"  if(@a < 2);

  my $interval = 60;
  if(int(@a)>=3) { $interval = $a[2]; }
  if( $interval < 60 ) { $interval = 60; }

  $hash->{STATE} = "Initialized";
  $hash->{INTERVAL} = $interval;

  $hash->{xls} = Sys::Statistics::Linux->new( loadavg => 1 );

  InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SYSSTAT_GetUpdate", $hash, 0);

  return undef;
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

    my $sys  = Sys::Statistics::Linux->new(diskusage => 1);
    my $filesystems = $sys->get->{diskusage};

    my $ret;
    $ret .= "<filesystem> <= <mountpoint>\n";
    foreach my $filesystem (keys %$filesystems ) { 
      $ret .= $filesystem ." <= ". $filesystems->{$filesystem}->{mountpoint} ."\n";
    }
    return $ret;
  } else {
    return "Unknown argument $cmd, choose one of filesystems";
  }   
}     

sub
SYSSTAT_Attr($$$)
{
  my ($cmd, $name, $attrName, $attrVal) = @_;

  $attrVal= "" unless defined($attrVal);
  my $orig = $attrVal;
  $attrVal= "1" if($attrName eq "useregex");
  $attrVal= "1" if($attrName eq "showpercent");

  if( $attrName eq "filesystems") {
    my $hash = $defs{$name};
    my @filesystems = split(",",$attrVal);
    @{$hash->{filesystems}} = @filesystems;

    if( $#filesystems >= 0 ) {
      $hash->{xls}->set( loadavg => 1,
                         diskusage => 1 );
    } else {
      $hash->{xls}->set( loadavg => 1,
                         diskusage => 0 );
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

sub
SYSSTAT_GetUpdate($)
{
  my ($hash) = @_;

  if(!$hash->{LOCAL}) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SYSSTAT_GetUpdate", $hash, 1);
  }

  my $stat = $hash->{xls}->get;

  my $load = $stat->{loadavg};

  $hash->{STATE} = $load->{avg_1} . " " . $load->{avg_5} . " " . $load->{avg_15};

  readingsSingleUpdate($hash,"load",$load->{avg_1},defined($hash->{LOCAL} ? 0 : 1));

  if( defined(my $usage = $stat->{diskusage}) ){

    my $type = 'free';
    if( AttrVal($hash->{NAME}, "showpercent", "") ne "" ) {
      $type = 'usageper';
    }

    if( AttrVal($hash->{NAME}, "useregex", "") eq "" ) {
      for my $filesystem (@{$hash->{filesystems}}) {
        my $fs = $usage->{$filesystem};
        readingsSingleUpdate($hash,$fs->{mountpoint},$fs->{$type},defined($hash->{LOCAL} ? 0 : 1));
      }
    } else {
      for my $filesystem (@{$hash->{filesystems}}) {
        foreach my $key (keys %$usage) {
          if( $key =~ /$filesystem/ ) {
            my $fs = $usage->{$key};
            readingsSingleUpdate($hash,$fs->{mountpoint},$fs->{$type},defined($hash->{LOCAL} ? 0 : 1));
          }
        }
      }
    }
  }
}

1;

=pod
=begin html

<a name="SYSSTAT"></a>
<h3>SYSSTAT</h3>
<ul>
  Provides system statistics for the host FHEM runs on.<br><br>

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
  </ul>

  <a name="SYSSTAT_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SYSSTAT [&lt;interval&gt;]</code><br>
    <br>

    Defines a SYSSTAT device.<br><br>

    The statistics are updated &lt;interval&gt; seconds. The default and minimum is 60.<br><br>

    Examples:
    <ul>
      <code>define sysstat SYSSTAT</code><br>
      <code>define sysstat SYSSTAT 300</code><br>
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
    <li>useregex<br>
      If set the entries of the filesystems list are treated as regex.</li>
  </ul>
</ul>

=end html
=cut

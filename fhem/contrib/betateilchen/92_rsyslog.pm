##############################################
# $Id: 92_rsyslog.pm 11101 2016-03-20 15:00:59Z betateilchen $

package main;

use strict;
use warnings;
use Sys::Syslog; # apt-get install libsys-syslog-perl

#####################################
sub rsyslog_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}    = "rsyslog_Define";
  $hash->{UndefFn}  = "rsyslog_Undef";
  $hash->{DeleteFn} = "rsyslog_Undef";
  $hash->{NotifyFn} = "rsyslog_Log";

  no warnings 'qw';
  my @attrList = qw(
    disable:0,1
    disabledForIntervals
    rsl_timestamp:0,1
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);

}

#####################################
sub rsyslog_Define($@) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  
  return "You must not define more than one rsyslog device!" if int(devspec2array('TYPE=rsyslog')) > 1;
  
  return "wrong syntax: define <name> rsyslog <ident> <logopt> <facility> <regexp>"
        if(int(@a) != 6);

  return "Bad regexp: starting with *" if($a[5] =~ m/^\*/);
  eval { "Hallo" =~ m/^$a[5]$/ };
  return "Bad regexp: $@" if($@);

  openlog($a[2],$a[3],$a[4]);

  $hash->{REGEXP}   = $a[5];
  $hash->{STATE}    = "active";
#  notifyRegexpChanged($hash, $a[5]);

  return undef;
}

sub rsyslog_Undef($$) {
  closelog();
  return undef;
}

sub rsyslog_Log($$) {
  my ($log, $dev) = @_;

  my $ln = $log->{NAME};
  return if(IsDisabled($ln));
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  return if(!$events);

  my $n   = $dev->{NAME};
  my $re  = $log->{REGEXP};
  my $max = int(@{$events});
  my $tn  = $dev->{NTFY_TRIGGERTIME};
  my $ct  = $dev->{CHANGETIME};

  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    my $t = (($ct && $ct->[$i]) ? $ct->[$i] : $tn);
    if($n =~ m/^$re$/ || "$n:$s" =~ m/^$re$/ || "$t:$n:$s" =~ m/^$re$/) {
      $t =~ s/ /_/; 
      my $output = "$n: $s";
      $output = "$t $output" if AttrVal($ln,'rsl_timestamp',0);
      syslog("info",$output) if defined &syslog;
    }
  }
  return "";
}


1;

=pod
=item helper
=begin html

<a name="rsyslog"></a>
<h3>rsyslog</h3>
<ul>
  Log fhem events to local syslog instance.<br/>
  <br/>
  <b>Prerequisits</b>
  <ul>
    <br/>
    Additional perl module Sys::Syslog must be installed on your system. Install this package from cpan or <br/>
    by <code>apt-get install libsys-syslog-perl</code> (only on Debian based installations)<br/>
  </ul>
  <br/>
  <a name="rsyslogdefine"></a>
  <b>Define</b>
  <ul>
    <br/>
    <code>define &lt;name&gt; rsyslog &lt;ident&gt; &lt;logopt&gt; &lt;facility&gt; &lt;regexp&gt;</code><br/>
    <br/>
    Detailed descriptions of parameters ident, logopt, facility can be found on <a href="http://perldoc.perl.org/Sys/Syslog.html">perldoc</a><br/>
    <br/>
    Example to log anything:<br/>
    <br/>
    <code>define rsl rsyslog fhem ndelay local0 .* </code><br/>
    <br/>
    will produce output like:<br/>
    <pre>Mar 20 15:25:22 fhem-vm-8 fhem: global: SAVE
Mar 20 15:25:44 fhem-vm-8 fhem: global: SHUTDOWN
Mar 20 15:25:57 fhem-vm-8 fhem: global: INITIALIZED
Mar 20 15:26:05 fhem-vm-8 fhem: PegelCux: Niedrigwasser-1: 20.03.2016 18:03
Mar 20 15:26:05 fhem-vm-8 fhem: PegelCux: Hochwasser-1: 20.03.2016 23:45</pre>
  </ul>
  <br/>
  <a name="rsyslogattr"></a>
  <b>Attributes</b>
  <ul>
    <br/>
    <a name="rsl_timestamp"></a>
    <li><code>rsl_timestamp</code><br>
        <br/>
        If set to 1, fhem timestamps will be looged, too.<br/>
        Default behavior is to not log these timestamps, because syslog uses own timestamps.<br/>
        Maybe useful if mseclog is activated in fhem.<br/>
        <br/>
        Example output:<br/>
        <pre>Mar 20 15:47:42 fhem-vm-8 fhem: 2016-03-20_15:47:42 global: SAVE
Mar 20 15:47:46 fhem-vm-8 fhem: 2016-03-20_15:47:46 global: SHUTDOWN
Mar 20 15:47:53 fhem-vm-8 fhem: 2016-03-20_15:47:53 global: INITIALIZED</pre>
    </li><br>
  </ul>
  <br/>
</ul>

=end html

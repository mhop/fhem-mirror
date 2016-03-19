##############################################
# $Id$

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
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);

}

#####################################
sub rsyslog_Define($@) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  return "wrong syntax: define <name> rsyslog <ident> <logopt> <facility> <regexp>"
        if(int(@a) != 6);

  return "Bad regexp: starting with *" if($a[5] =~ m/^\*/);
  eval { "Hallo" =~ m/^$a[5]$/ };
  return "Bad regexp: $@" if($@);

  openlog($a[2],$a[3],$a[4]);

#  $hash->{ident}    = $a[2];
#  $hash->{logopt}   = $a[3];
#  $hash->{facility} = $a[4];
  $hash->{REGEXP}   = $a[5];
  $hash->{STATE}    = "active";
  notifyRegexpChanged($hash, $a[5]);

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
      syslog("info","$n: $s") if defined &syslog;
    }
  }
  return "";
}

sub rsyslog_Undef($$) {
  closelog();
  return undef;
}

1;

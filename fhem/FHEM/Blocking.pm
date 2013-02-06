##############################################
# $Id: $
package main;

=pod
### Usage:
sub TestBlocking() { BlockingCall("DoSleep", 5, "SleepDone", 8); }
sub DoSleep($)     { sleep(shift); return "I'm done"; }
sub SleepDone($)   { Log 1, "SleepDone: " . shift; }
=cut


use strict;
use warnings;
use IO::Socket::INET;

sub BlockingCall($$@);
sub BlockingExit($);
sub BlockingKill($);

sub
BlockingCall($$@)
{
  my ($blockingFn, $arg, $finishFn, $timeout) = @_;

  # Look for the telnetport
  # must be done before forking to be able to create a temporary device
  my $telnetDevice;
  if($finishFn) {
    my $tName = "telnetForBlockingFn";
    $telnetDevice = $tName if($defs{$tName});

    if(!$telnetDevice) {
      foreach my $d (sort keys %defs) {
        my $h = $defs{$d};
        next if(!$h->{TYPE} || $h->{TYPE} ne "telnet" || $h->{TEMPORARY});
        next if($attr{$d}{SSL} || $attr{$d}{password});
        next if($h->{DEF} =~ m/IPV6/);
        $telnetDevice = $d;
        last;
      }
    }

    # If not suitable telnet device found, create a temporary one
    if(!$telnetDevice) {
      foreach my $port (7073..7083) {
        if(!CommandDefine(undef, "$tName telnet $port")) {
          CommandAttr(undef, "$tName room hidden");
          $telnetDevice = $tName;
          $defs{$tName}{TEMPORARY} = 1;
          last;
        }
      }
    }

    if(!$telnetDevice) {
      my $msg = "CallBlockingFn: No telnet port found and cannot create one.";
      Log 1, $msg;
      return $msg;
    }
  }

  # do fork
  my $pid = fork;
  if(!defined($pid)) {
    Log 1, "Cannot fork: $!";
    return undef;
  }

  if($pid) {
    InternalTimer(gettimeofday()+$timeout, "BlockingKill", $pid, 0)
      if($timeout);
    return $pid;
  }

  # Child here
  no strict "refs";
  my $ret = &{$blockingFn}($arg);
  use strict "refs";

  BlockingExit(undef) if(!$finishFn);

  # Write the data back, calling the function
  my $addr = "localhost:$defs{$telnetDevice}{PORT}";
  my $client = IO::Socket::INET->new(PeerAddr => $addr);
  Log 1, "CallBlockingFn: Can't connect to $addr\n" if(!$client);
  $ret =~ s/'/\\'/g;
  syswrite($client, "{$finishFn('$ret')}\n");
  BlockingExit($client);
}

sub
BlockingKill($)
{
  my $pid = shift;
  Log 1, "Terminated $pid" if($pid && kill(9, $pid));
}

sub
BlockingExit($)
{
  my $client = shift;

  if($^O =~ m/Win/) {
    close($client) if($client);
    threads->exit();

  } else {
    exit(0);

  }
}


1;

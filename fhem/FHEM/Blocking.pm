##############################################
# $Id: $
package main;

=pod
### Usage:
sub TestBlocking() { BlockingCall("DoSleep", 5, "SleepDone", 8); }
sub DoSleep($)     { sleep(shift); return "I'm done"; }
sub SleepDone($)   { Log 1, "SleepDone: " . shift; }
sub TestBlocking2() { BlockingCall("DoSleep", 5, "SleepDone", 2); }
=cut


use strict;
use warnings;
use IO::Socket::INET;

sub BlockingCall($$@);
sub BlockingExit();
sub BlockingKill($);
sub BlockingInformParent($;$$);

my $telnetDevice;

sub
BlockingCall($$@)
{
  my ($blockingFn, $arg, $finishFn, $timeout) = @_;

  # Look for the telnetport
  # must be done before forking to be able to create a temporary device
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

  # do fork
  my $pid = fork;
  if(!defined($pid)) {
    Log 1, "Cannot fork: $!";
    return undef;
  }

  if($pid) {
    my %h = ( pid=>$pid, fn=>$blockingFn, finishFn=>$finishFn );
    if($timeout) {
      InternalTimer(gettimeofday()+$timeout, "BlockingKill", \%h, 0);
    }
    return \%h;
  }

  # Child here
  no strict "refs";
  my $ret = &{$blockingFn}($arg);
  use strict "refs";

  BlockingExit() if(!$finishFn);

  # Write the data back, calling the function
  BlockingInformParent($finishFn, $ret, 0);
  BlockingExit();
}

sub
BlockingInformParent($;$$)
{
  my ($informFn, $param, $waitForRead) = @_;
  my $ret = undef;
  $waitForRead = 1 if (!defined($waitForRead));
	
  # Write the data back, calling the function
  my $addr = "localhost:$defs{$telnetDevice}{PORT}";
  my $client = IO::Socket::INET->new(PeerAddr => $addr);
  Log 1, "CallBlockingFn: Can't connect to $addr\n" if(!$client);

  if (defined($param)) {
    $param =~ s/'/\\'/g;
    $param = "'$param'"
  } else {
  	$param = "";
  }

  syswrite($client, "{$informFn($param)}\n");

  if ($waitForRead) {
    my $len = sysread($client, $ret, 4096);
    chop($ret);
    $ret = undef if(!defined($len));
  }

  close($client) if($client);
  
  return $ret;
}

sub
BlockingKill($)
{
  my $h = shift;
  if($^O !~ m/Win/) {
    if($h->{pid} && kill(9, $h->{pid})) {
      Log 1, "Timeout for $h->{fn} reached, terminated process $h->{pid}";
      if($h->{finishFn}) {
        no strict "refs";
        my $ret = &{$h->{finishFn}}();
        use strict "refs";
      }
    }
  }
}

sub
BlockingExit()
{

  if($^O =~ m/Win/) {
    eval "require threads;";
    threads->exit();

  } else {
    POSIX::_exit(0);

  }
}


1;


# $Id$

use strict;

use vars qw(%cmds);
use vars qw(%defs);
use vars qw($init_done);
use vars qw(%selectlist);

sub CoProcess::Info($$@);

my %hash = (
  Fn  => "CoProcess::Info",
  Hlp => ",show info about processes started by CoProcess"
);
$cmds{coprocessinfo} = \%hash;

sub
CoProcess_Initialize() {
}


package CoProcess;

use POSIX;
use Socket;

sub
Info($$@) {
  my @ret;

  foreach my $d (keys %main::defs) {
    my $h =$main::defs{$d};
    next if( !defined($h->{CoProcess}) );

    my $line;

    $line = sprintf( "%-15s %-15s %-35s %-19s %-19s %8s %s", $h->{NAME}, $h->{CoProcess}{name}, $h->{CoProcess}{state}, $h->{LAST_START}, $h->{LAST_STOP}, $h->{PID}, $h->{logfile} );

    push @ret, $line;
  }
 
  unshift @ret, sprintf( "\n%-15s %-15s %-35s %-19s %-19s %8s %s", 'DEVICE', 'NAME', 'state', 'LAST START', 'LAST STOP', 'PID', 'logfile' ) if( @ret );
  push @ret, "No CoProcesses are currently used" if(!@ret);

  return join("\n", @ret) ."\n";
}


sub
callFn($$) {
  my ($hash,$n,@params) = @_;
  my $name = $hash->{NAME};

  if( !defined($hash->{CoProcess}) || !defined($hash->{CoProcess}{$n}) ) {
    main::Log3 $name, 4, "$name: CoProcess: no such function: $n";
    return undef;
  }

  my $fn = "main::$hash->{CoProcess}{$n}";
  if(wantarray) {
    no strict "refs";
    my @ret = &{$fn}($hash, @params);
    use strict "refs";
    return @ret;
  } else {
    no strict "refs";
    my $ret = &{$fn}($hash, @params);
    use strict "refs";
    return $ret;
  }
}
sub
openLogfile($;$) {
  my ($hash,$logfile) = @_;
  my $name = $hash->{NAME};

  closeLogfile($hash) if( $hash->{log} );

  if( !$logfile ) {
    $logfile = $hash->{logfile};

    if( !$logfile ) {
      $logfile = main::AttrVal($name, 'CoProc-log', undef);
      $hash->{logfile} = $logfile if( $logfile );
    }

    if( $logfile && $logfile ne 'FHEM' ) {
      $hash->{logfile} = $logfile;
      my @t = localtime(time());
      $logfile = main::ResolveDateWildcards($logfile, @t);
    }
  }

  if( $logfile && $logfile ne 'FHEM' ) {
    $hash->{currentlogfile} = $logfile;

    main::HandleArchiving($hash);

    if( open( my $fh, ">>$logfile") ) {
      $fh->autoflush(1);

      $hash->{log} = $fh;

      main::Log3 $name, 3, "$name: using logfile: $logfile";

    } else {
      main::Log3 $name, 2, "$name: failed to open logile: $logfile: $!";
    }
  }
  main::Log3 $name, 3, "$name: using FHEM logfile" if( !$hash->{log} );
}
sub
closeLogfile($) {
  my ($hash) = @_;

  close($hash->{log}) if( $hash->{log} );
  delete $hash->{log};

  delete $hash->{currentlogfile};
}


# start co process
sub
start($;$) {
  my ($hash,$cmd) = @_;
  my $name = $hash->{NAME};
  my $error;
  ($cmd,$error) = callFn($hash,'cmdFn') if( !$cmd );

  if( $error ) {
    $hash->{CoProcess}{state} = "stopped; $error";
    main::readingsSingleUpdate($hash, $hash->{CoProcess}{name}, $hash->{CoProcess}{state}, 1 ) if( $hash->{CoProcess}{name} );
    main::Log3 $name, 2, "$name: $error";
  }

  return undef if( !$cmd );
  return undef if( !$main::init_done );
  return undef if( !$hash->{CoProcess} );
  return undef if( main::IsDisabled($name) );

  if( $hash->{PID} ) {
    $hash->{restart} = 1;
    stop($hash);
    return undef;
  }
  delete $hash->{restart};

  my ($child, $parent);
  # SOCK_NONBLOCK ?
  if( socketpair($child, $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) ) {
    $child->autoflush(1);
    $parent->autoflush(1);

    my $pid = main::fhemFork();

    if( !defined($pid) ) {
      close $parent;
      close $child;

      main::Log3 $name, 1, "$name: Cannot fork: $!";
      return;
    }

    if( $pid ) {
      close $parent;

      $hash->{STARTS}++;

      $hash->{FH} = $child;
      $hash->{FD} = fileno($child);
      $hash->{PID} = $pid;

      $main::selectlist{$name} = $hash;

      main::Log3 $name, 3, "$name: starting";
      $hash->{LAST_START} = main::FmtDateTime( time() );
      $cmd = (split( ' ', $cmd, 2 ))[0];
      $hash->{CoProcess}{state} = "running $cmd";
      main::readingsSingleUpdate($hash, $hash->{CoProcess}{name}, $hash->{CoProcess}{state}, 1 ) if( $hash->{CoProcess}{name} );

      openLogfile($hash);

    } else {
      close $child;

      close STDIN;
      close STDOUT;
      close STDERR;

      my $fn = $parent->fileno();
      open(STDIN, "<&$fn") or die "can't redirect STDIN $!";
      open(STDOUT, ">&$fn") or die "can't redirect STDOUT $!";
      open(STDERR, ">&$fn") or die "can't redirect STDERR $!";

      STDOUT->autoflush(1);
      STDERR->autoflush(1);

      close $parent;

      exec split( ' ', $cmd ) or main::Log3 $name, 1, "exec failed";

      main::Log3 $name, 1, "set the alexaFHEM-cmd attribut to: <path>/alexa-fhem";

      POSIX::_exit(0);;
    }

  } else {
    main::Log3 $name, 3, "$name: socketpair failed";
    main::InternalTimer(time()+20, "CoProcess::start", $hash, 0);
  }
}

# stop coprocess
sub
stop($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  main::RemoveInternalTimer($hash);

  return undef if( !$hash->{PID} );

  if( $hash->{PID} ) {
    kill( SIGTERM, $hash->{PID} );
    #kill( SIGkILL, $hash->{PID} );
    #  waitpid($hash->{PID}, 0);
    #  delete $hash->{PID};
  }

  $hash->{CoProcess}{state} = 'stopping';
  main::readingsSingleUpdate($hash, $hash->{CoProcess}{name}, $hash->{CoProcess}{state}, 1 ) if( $hash->{CoProcess}{name} );

  main::InternalTimer(time()+5, "CoProcess::terminate", $hash, 0);
}

# kill co process imediately
sub
terminate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  main::RemoveInternalTimer($hash);

  return undef if( !$hash->{PID} );
  return undef if( !$hash->{FD} );

  kill( SIGKILL, $hash->{PID} );
  waitpid($hash->{PID}, 0);
  delete $hash->{PID};

  close($hash->{FH}) if($hash->{FH});
  delete($hash->{FH});
  delete($hash->{FD});
  delete($main::selectlist{$name});

  closeLogfile($hash) if( $hash->{log} );

  $hash->{PARTIAL} = "" if( defined($hash->{PARTIAL}) );

  main::Log3 $name, 3, "$name: stopped";
  $hash->{LAST_STOP} = main::FmtDateTime( time() );

  $hash->{CoProcess}{state} = 'stopped';
  if( $hash->{reason} ) {
    $hash->{CoProcess}{state} .= "; $hash->{reason}";
    delete $hash->{reason};
  }
  main::readingsSingleUpdate($hash, $hash->{CoProcess}{name}, $hash->{CoProcess}{state}, 1 ) if( $hash->{CoProcess}{name} );

  if( $hash->{undefine} ) {
    my $cl = $hash->{undefine};

    delete $hash->{undefine};
    main::CommandDelete(undef, $name);
    main::Log3 $name, 2, "$name: deleted";

    main::asyncOutput( $cl, "$name: deleted\n" ) if( ref($cl) eq 'HASH' && $cl->{canAsyncOutput} );

  } elsif( $hash->{shutdown} ) {
    my $cl = $hash->{shutdown};

    delete $hash->{shutdown};
    main::asyncOutput( $cl, "$name: stopped\n" ) if( ref($cl) eq 'HASH' && $cl->{canAsyncOutput} );
    main::CancelDelayedShutdown($name);

  } elsif( $hash->{restart} ) {
    start($hash)

  }
}

#read from co process and handle logging
sub
readFn($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $buf;
  my $ret = sysread($hash->{FH}, $buf, 65536 );

  if(!defined($ret) || $ret <= 0) {
    main::Log3 $name, 3, "$name: read: error during sysread: $!" if(!defined($ret));
    main::Log3 $name, 3, "$name: read: end of file reached while sysread" if( $ret <= 0);

    my $oldstate = $hash->{CoProcess}{state};

    terminate($hash);

    return undef if( $oldstate !~ m/^running/ );

    my $delay = 20;
    if( $hash->{'LAST_START'} && $hash->{'LAST_STOP'} ) {
      my $diff = main::time_str2num($hash->{'LAST_STOP'}) - main::time_str2num($hash->{'LAST_START'});

      if( $diff > 60 ) {
        $delay = 0;
        main::Log3 $name, 4, "$name: last run duration was $diff sec, restarting imediately";
      } else {
        main::Log3 $name, 4, "$name: last run duration was only $diff sec, restarting with delay";
      }
    } else {
      main::Log3 $name, 4, "$name: last run duration unknown, restarting with delay";
    }
    main::InternalTimer(time()+$delay, "CoProcess::start", $hash, 0);

    return undef;
  }

  if( $hash->{logfile} ) {
    if( $hash->{log} ) {
      my @t = localtime(time());
      my $logfile = main::ResolveDateWildcards($hash->{logfile}, @t);
      openLogfile($hash, $logfile) if( $hash->{currentlogfile} ne $logfile );
     }

    if( $hash->{log} ) {
      print {$hash->{log}} "$buf";

    } else {
      #my $buf = $buf;
      $buf =~ s/\n$//s;
      main::Log3 $name, 3, "$name: $buf";

    }
  }

  if( my $disabled = main::IsDisabled($hash) && !$hash->{CoProcess}{state} eq 'stopping' ) {
    $hash->{reason} = 'disabledForIntervals';
    CoProcess::stop($hash);

    if( $disabled == 2 ) {
      $hash->{disabled} = 1;
      #FIXME: add timer to restart coprocess if disabledForIntervals has elapsed
    }
  }

  return $buf;
}

# add CoProcess specific commands
sub
setCommands($$@) {
  my ($hash, $list, $cmd, @a) = @_;

  #my %cp_list = (
  #  'start'     => ':noArg',
  #  'stop'      => ':noArg',
  #  'restart'   => ':noArg',
  #);


  if( $cmd eq 'start' ) {
    start($hash);

    return undef;

  } elsif( $cmd eq 'stop' ) {
    stop($hash);

    return undef;

  } elsif( $cmd eq 'restart' ) {
    start($hash);

    return undef;
  }


  $list .= ' ' if( $list );
  $list .= 'start:noArg stop:noArg restart:noArg';
  #foreach my $key ( sort keys %cp_list ) {
  #  if( $list !~ m/\b$key\b/ ) {
  #    $list .= ' ' if( $list );
  #    $list .= $key.$cp_list{$key};
  #  }
  #}

  return "Unknown argument $cmd, choose one of $list";
}

# add CoProcess specific attributes
use vars qw($CoProcessAttributes);
#no warnings 'qw';
my @attrList = qw(
  CoProc-cmd
  CoProc-log
  CoProc-params
  CoProc-sshHost
  CoProc-sshUser
);
$CoProcessAttributes = join(" ", @attrList);

#TODO...

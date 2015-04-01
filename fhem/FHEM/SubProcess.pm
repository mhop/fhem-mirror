# $Id$

##############################################################################
#
#     SubProcess.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package SubProcess;
use warnings;
use strict;
use POSIX ":sys_wait_h";
use Socket;
use IO::Handle;

# creates a new subprocess
sub new() {
  my ($class, $args)= @_;

  my ($child, $parent);
  socketpair($child, $parent, AF_UNIX, SOCK_STREAM, PF_UNSPEC) || return undef; # die "socketpair: $!";
  $child->autoflush(1);
  $parent->autoflush(1);
  
  my $self= {
    
    onRun => $args->{onRun},
    onExit => $args->{onExit},
    timeout => $args->{timeout},
    child => $child,
    parent => $parent,
   
  };  # we are a hash reference

  return bless($self, $class); # make $self an object of class $class
 
}

sub pid() {
  
    my $self= shift;
    return $self->{pid};
}
    

# check if child process is still running
sub running() {

  my $self= shift;
  my $pid= $self->{pid};

  return waitpid($pid, WNOHANG) > 0 ? 1 : 0;
}

# waits for the child process to terminate
sub wait() {

  my $self= shift;
  my $pid= $self->{pid};
  if(defined($pid)) {
    main::Log3 $pid, 5, "Waiting for SubProcess $pid...";
    waitpid($pid, 0);
    main::Log3 $pid, 5, "SubProcess $pid terminated...";
  }
}

# 
sub signal() {

  my ($self, $signal)= @_;
  my $pid= $self->{pid};
  main::Log3 $pid, 5, "Sending signal $signal to SubProcess $pid...";
  return kill $signal, $pid;
}

# terminates a child process (HUP)
sub terminate() {

  my $self= shift;
  return $self->signal('HUP');
}

# terminates a child process (KILL)
sub kill() {

  my $self= shift;
  return $self->signal('KILL');
}

sub child() {
  my $self= shift;
  return $self->{child};
}

sub parent() {
  my $self= shift;
  return $self->{parent};
}

# this function is called from the parent to read from the child
# returns undef on error or if nothing was read
sub read() {

  my $self= shift;
  my ($bytes, $result);
  $bytes= sysread($self->child(), $result, 1024*1024);
  return defined($bytes) ? $result : undef;
}

# starts the child process
sub run() {

  my $self= shift;

  my $pid= fork;
  if(!defined($pid)) {
      main::Log3 undef, 2, "SubProcess: Cannot fork: $!";
      return undef;
  }

  $self->{pid}= $pid;
  
  if(!$pid) {
    # CHILD
    #close(CHILD);
    #main::Debug "PARENT FD= " . fileno $self->{parent};
    
    # run
    my $onRun= $self->{onRun};
    if(defined($onRun)) {
      eval { &$onRun($self) };
      main::Log3 undef, 2, "SubProcess: onRun returned error: $@" if($@);
    }
    
    # exit
    my $onExit= $self->{onExit};
    if(defined($onExit)) {
      eval { &$onExit($self) };
      main::Log3 undef, 2, "SubProcess: onExit returned error: $@" if($@);
    }
    
    #close(PARENT);
    POSIX::_exit(0);
    
  } else {
    # PARENT 
    #close(PARENT);
    #main::Debug "CHILD FD= " . fileno $self->{child};

    main::Log3 $pid, 5, "SubProcess $pid created.";
   
    return $pid;
  }  

}


1;

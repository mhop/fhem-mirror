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

#
# creates a new subprocess
#
sub new() {
  my ($class, $args)= @_;

  my ($child, $parent);
  # http://perldoc.perl.org/functions/socketpair.html
  # man 2 socket
  # AF_UNIX         Local communication
  # SOCK_STREAM     Provides sequenced, reliable,  two-way,  connection-based
  #                 byte streams.  An out-of-band data transmission mechanism
  #                 may be supported
  #
  socketpair($child, $parent, AF_UNIX, SOCK_STREAM || SOCK_NONBLOCK, PF_UNSPEC) || 
    return undef; # die "socketpair: $!";
  $child->autoflush(1);
  $parent->autoflush(1);

  # Buffers are not used in this version of SubProcess.pm
  # Revision  8393 had it
  my %childBuffer= ();
  my %parentBuffer= ();
  
  my $self= {
    
    onRun => $args->{onRun},
    onExit => $args->{onExit},
    timeout => $args->{timeout},
    timeoutread => $args->{timeoutread},
    timeoutwrite => $args->{timeoutwrite},
    child => $child,
    parent => $parent,
    pid => undef,
    childBufferRef => \%childBuffer,
    parentBufferRef => \%parentBuffer,
    lasterror => ''
   
  };  # we are a hash reference

  # Timeout must be defined and > 0
  # 0 = Polling, undef = Block until data available
  if(defined($self->{timeout})) {
    $self->{timeout} = 0.001 if ($self->{timeout} <= 0.0);
  }
  else {
    $self->{timeout} = 0.001;
  }
  if (!defined ($self->{timeoutread})) {
    $self->{timeoutread} = $self->{timeout};
  }
  if (!defined ($self->{timeoutwrite})) {
    $self->{timeoutwrite} = $self->{timeout};
  }
  
  return bless($self, $class); # make $self an object of class $class
 
}

sub lasterror() {
  my $self = shift;
  return exists ($self->{lasterror}) ? $self->{lasterror} : '';
}

#
# returns the pid of the subprocess
# undef if subprocess not available
#
sub pid() {
  
    my $self= shift;
    return $self->{pid};
}
    
#
# return 1 if subprocess is still running, else 0
#
sub running() {

  my $self= shift;
  my $pid= $self->{pid};

  return waitpid($pid, WNOHANG) > 0 ? 1 : 0;
}

#
# waits for the subprocess to terminate
#
sub wait() {

  my $self= shift;
  my $pid= $self->{pid};
  if(defined($pid)) {
    main::Log3 $pid, 5, "Waiting for SubProcess $pid...";
    waitpid($pid, 0);
    main::Log3 $pid, 5, "SubProcess $pid terminated.";
  }
}

# 
# send a POSIX signal to the subproess
#
sub signal() {

  my ($self, $signal)= @_;
  my $pid= $self->{pid};
  main::Log3 $pid, 5, "Sending signal $signal to SubProcess $pid...";
  return kill $signal, $pid;
}

#
# terminates thr subprocess (HUP)
#
sub terminate() {

  my $self= shift;
  return $self->signal('HUP');
}

#
# kills the subprocess (KILL)
#
sub kill() {

  my $self= shift;
  return $self->signal('KILL');
}

#
# the socket used by the parent to communicate with the subprocess
#
sub child() {
  my $self= shift;
  return $self->{child};
}

#
# the socket used by the subprocess to communicate with the parent
#
sub parent() {
  my $self= shift;
  return $self->{parent};
}

# this is a helper function for reading
# returns 1 datagram or undef on error
sub readFrom() {
  my ($self, $fh) = @_;

  my $header;
  my $data;

  # Check if data is available
  my $rin= '';
  vec($rin, fileno($fh), 1) = 1;
  my $nfound = select($rin, undef, undef, $self->{timeoutread});
  if ($nfound < 0) {
    $self->{lasterror} = $!;
    return undef;
  }
  elsif ($nfound == 0) {
    $self->{lasterror} = "read: no data";
    return undef;
  }
  
  # Read datagram size	
  my $sbytes = sysread ($fh, $header, 4);
  if (!defined ($sbytes)) {
    $self->{lasterror} = $!;
    return undef;
  }
  elsif ($sbytes != 4) {
    $self->{lasterror} = "read: short header";
    return undef;
  }

  # Read datagram
  my $size = unpack ('N', $header);
  my $buffer;
  while($size> 0) {
    my $bytes = sysread ($fh, $buffer, $size);
    if (!defined ($bytes)) {
      $self->{lasterror} = $!;
      return undef;
    }
    $data.= $buffer;
    $size-= $bytes;
  }

  return $data;
}

# this is a helper function for writing
# writes 4 byte datagram size + datagram
sub writeTo() {
  my ($self, $fh, $msg) = @_;

  my $win= '';
  vec($win, fileno($fh), 1)= 1;
  my $nfound = select (undef, $win, undef, $self->{timeoutwrite});
  if ($nfound < 0) {
    $self->{lasterror} = $!;
    return undef;
  }
  elsif ($nfound == 0) {
    $self->{lasterror} = "write: no reader";
    return undef;
  }

  my $size= pack("N", length($msg));
  my $bytes= syswrite ($fh, $size . $msg);
  if (!defined ($bytes)) {
    $self->{lasterror} = $!;
    return undef;
  }
  elsif ($bytes != length ($size.$msg)) {
    $self->{lasterror} = "write: incomplete data";
    return undef;
  }
  
  return $bytes;
}

    

# this function is called from the parent to read from the subprocess
# returns undef on error or if nothing was read
sub readFromChild() {

  my $self= shift;
  
  return $self->readFrom($self->child());
}


# this function is called from the parent to write to the subprocess
# returns 0 on error, else 1
sub writeToChild() {

  my ($self, $msg)= @_;
  return $self->writeTo($self->child(), $msg);
}


# this function is called from the subprocess to read from the parent
# returns undef on error or if nothing was read
sub readFromParent() {

  my $self= shift;
  return $self->readFrom($self->parent());
}


# this function is called from the subprocess to write to the parent
# returns 0 on error, else 1
sub writeToParent() {

  my ($self, $msg)= @_;
  return $self->writeTo($self->parent(), $msg);
}


#
# starts the subprocess
#
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
    
    # run
    main::Log3 undef, 5, "SubProcess $$ started.";
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
    
    main::Log3 undef, 5, "SubProcess $$ ended.";
    POSIX::_exit(0);
    
  } else {
    # PARENT 

    main::Log3 $pid, 5, "SubProcess $pid created.";
   
    return $pid;
  }  

}


1;

# Perl Protothreads Version 1.04
# 
# a lightwight pseudo-threading framework for perl that is
# heavily inspired by Adam Dunkels protothreads for the c-language
# 
# LICENSE AND COPYRIGHT
#
# Copyright (C) 2014 ntruchsess (norbert.truchsess@t-online.de)
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of either: the GNU General Public License as published
# by the Free Software Foundation; or the Artistic License.
#
# See http://dev.perl.org/licenses/ for more information.
#
#PT_THREAD(sub)
#Declare a protothread
#
#PT_INIT(thread)
#Initialize a thread
#
#PT_BEGIN(thread);
#Declare the start of a protothread inside the sub implementing the protothread.
#
#PT_WAIT_UNTIL(condition);
#Block and wait until condition is true.
#
#PT_WAIT_WHILE(condition);
#Block and wait while condition is true.
#
#PT_WAIT_THREAD(thread);
#Block and wait until another protothread completes.
#
#PT_SPAWN(thread);
#Spawn a child protothread and wait until it exits.
#
#PT_RESTART;
#Restart the protothread.
#
#PT_EXIT;
#Exit the protothread. Use PT_EXIT(value) to pass an exit-value to PT_EXITVAL
#
#PT_END;
#Declare the end of a protothread.
#
#PT_SCHEDULE(protothread);
#Schedule a protothread.
#
#PT_YIELD;
#Yield from the current protothread.
#
#PT_YIELD_UNTIL(condition);
#Yield from the current protothread until the condition is true.
#
#PT_RETVAL
#return the value that has been (optionaly) passed by PT_EXIT(value)

package ProtoThreads;

use constant {
  PT_INITIAL   => 0,
  PT_WAITING   => 1,
  PT_YIELDED   => 2,
  PT_EXITED    => 3,
  PT_ENDED     => 4,
  PT_ERROR     => 5,
  PT_CANCELED  => 6,
};

my $DEBUG=0;

use Exporter 'import';
@EXPORT = qw(PT_THREAD PT_INITIAL PT_WAITING PT_YIELDED PT_EXITED PT_ENDED PT_ERROR PT_CANCELED PT_INIT PT_SCHEDULE);
@EXPORT_OK = qw();

use Text::Balanced qw (
  extract_codeblock
);

sub PT_THREAD($) {
  my $method = shift;
  return bless({
    PT_THREAD_STATE => PT_INITIAL,
    PT_THREAD_POSITION => 0,
    PT_THREAD_METHOD => $method
  }, "ProtoThreads");
}

sub PT_INIT($) {
  my $self = shift;
  $self->{PT_THREAD_POSITION} = 0;
  $self->{PT_THREAD_STATE} = PT_INITIAL;
  delete $self->{PT_THREAD_ERROR};
}

sub PT_SCHEDULE(@) {
  my ($self) = @_;
  my $state = $self->{PT_THREAD_METHOD}(@_); 
  return ($state == PT_WAITING or $state == PT_YIELDED);
}

sub PT_CANCEL($) {
  my ($self,$cause) = @_;
  $self->{PT_THREAD_POSITION} = 0;
  $self->{PT_THREAD_ERROR} = $cause;
  $self->{PT_THREAD_STATE} = PT_CANCELED;
}

sub PT_RETVAL() {
  my $self = shift;
  return $self->{PT_THREAD_RETURN};
}

sub PT_STATE() {
  my $self = shift;
  return $self->{PT_THREAD_STATE};
}

sub PT_CAUSE() {
  my $self = shift;
  return $self->{PT_THREAD_ERROR};
}

sub PT_NEXTCOMMAND($$) {
  my ($code,$command) = @_;
  if ($code =~ /$command\s*(?=\()/s) {
    if ($') {
      my $before = $`;
      my $after = $';
      my ($match,$remains,$prefix) = extract_codeblock($after,"()");
      $match =~ /(^\()(.*)(\)$)/;
      my $arg = $2 if defined $2;
      $remains =~ s/^\s*;//sg;
      return (1,$before,$arg,$remains);
    }
  }
  return undef;
}

use Filter::Simple;

FILTER_ONLY
  executable => sub {
   
  my $code = $_;
  my $counter = 1;
  my ($success,$before,$arg,$after,$beforeblock);
  
  while(1) {
    ($success,$beforeblock,$arg,$after) = PT_NEXTCOMMAND($code,"PT_BEGIN");
    if ($success) {
      if ($after =~ /PT_END\s*;/s) {
        my $thread = $arg;
        my $block = $thread."->{PT_THREAD_STATE} = eval { my \$PT_YIELD_FLAG = 1; goto ".$thread."->{PT_THREAD_POSITION} if ".$thread."->{PT_THREAD_POSITION};".$`.$thread."->{PT_THREAD_POSITION} = 0; delete ".$thread."->{PT_THREAD_RETURN}; return PT_ENDED; }; if (\$\@) {".$thread."->{PT_THREAD_STATE} = PT_ERROR; ".$thread."->{PT_THREAD_ERROR} = \$\@; }; return ".$thread."->{PT_THREAD_STATE};";
        my $afterblock = $';
        while (1) {
          ($success,$before,$arg,$after) = PT_NEXTCOMMAND($block,"PT_YIELD_UNTIL");
          if ($success) {
            $block=$before."\$PT_YIELD_FLAG = 0; ".$thread."->{PT_THREAD_POSITION} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_YIELDED unless (\$PT_YIELD_FLAG and ($arg));".$after;
            $counter++;
            next;
          }
          if ($block =~ /PT_YIELD\s*;/s) {
            $block = $`."\$PT_YIELD_FLAG = 0; ".$thread."->{PT_THREAD_POSITION} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_YIELDED unless \$PT_YIELD_FLAG;".$';
            $counter++;
            next;
          }
          ($success,$before,$arg,$after) = PT_NEXTCOMMAND($block,"PT_WAIT_UNTIL");
          if ($success) {
            $block=$before.$thread."->{PT_THREAD_POSITION} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_WAITING unless ($arg);".$after;
            $counter++;
            next;
          }
          ($success,$before,$arg,$after) = PT_NEXTCOMMAND($block,"PT_WAIT_WHILE");
          if ($success) {
            $block=$before.$thread."->{PT_THREAD_POSITION} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_WAITING if ($arg);".$after;
            $counter++;
            next;
          }
          ($success,$before,$arg,$after) = PT_NEXTCOMMAND($block,"PT_WAIT_THREAD");
          if ($success) {
            $block=$before."PT_WAIT_WHILE(PT_SCHEDULE(".$arg."));".$after;
            next;
          }
          ($success,$before,$arg,$after) = PT_NEXTCOMMAND($block,"PT_SPAWN");
          if ($success) {
            $block=$before.$arg."->{PT_THREAD_POSITION} = 0; PT_WAIT_THREAD($arg);".$after;
            next;
          }
          ($success,$before,$arg,$after) = PT_NEXTCOMMAND($block,"PT_EXIT");
          if ($success) {
            $block=$before.$thread."->{PT_THREAD_POSITION} = 0; ".$thread."->{PT_THREAD_RETURN} = $arg; return PT_EXITED;".$after;
            next;
          }
          if ($block =~ /PT_EXIT(\s*;|\s+)/s) {
            $block = $`.$thread."->{PT_THREAD_POSITION} = 0; delete ".$thread."->{PT_THREAD_RETURN}; return PT_EXITED".$1.$';
            next;
          }
          if ($block =~ /PT_RESTART(\s*;|\s)/s) {
            $block = $`.$thread."->{PT_THREAD_POSITION} = 0; return PT_WAITING;".$1.$';
            next;
          }
          last;
        }
        $code = $beforeblock.$block.$afterblock;
      } else {
        die "PT_END expected"
      }
      next;
    }
    last;
  };
  
  print $code if $DEBUG;
  
  $_ = $code;
  
  };

1;

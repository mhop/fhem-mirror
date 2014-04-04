# Perl Protothreads
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
  PT_WAITING => 0,
  PT_EXITED => 1,
  PT_ENDED => 2,
  PT_YIELDED => 3,
};

my $DEBUG=0;

use Exporter 'import';
@EXPORT = qw(PT_THREAD PT_WAITING PT_EXITED PT_ENDED PT_YIELDED PT_INIT PT_SCHEDULE);
@EXPORT_OK = qw();

use Text::Balanced qw (
  extract_codeblock
);

sub PT_THREAD($) {
  my $method = shift;
  return bless({
    PT_THREAD_STATE => 0,
    PT_THREAD_METHOD => $method 
  }, "ProtoThreads");
}

sub PT_INIT($) {
  my $self = shift;
  $self->{PT_THREAD_STATE} = 0;
}

sub PT_SCHEDULE(@) {
  my ($self) = @_;
  my $state = $self->{PT_THREAD_METHOD}(@_); 
  return ($state == PT_WAITING or $state == PT_YIELDED);
}

sub PT_RETVAL() {
  my $self = shift;
  return $self->{PT_THREAD_RETURN};
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
  my ($success,$before,$arg,$after);
  
  while(1) {
    my $thread = " - no PT_BEGIN before use of thread - ";
    ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_BEGIN");
    if ($success) {
      $thread = $arg;
      $code=$before."{ my \$PT_YIELD_FLAG = 1; goto ".$thread."->{PT_THREAD_STATE} if ".$thread."->{PT_THREAD_STATE};".$after;
      while (1) {
        ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_YIELD_UNTIL");
        if ($success) {
          $code=$before."\$PT_YIELD_FLAG = 0; ".$thread."->{PT_THREAD_STATE} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_YIELDED unless (\$PT_YIELD_FLAG and ($arg));".$after;
          $counter++;
          next;
        }
        if ($code =~ /PT_YIELD\s*;/s) {
          $code = $`."\$PT_YIELD_FLAG = 0; ".$thread."->{PT_THREAD_STATE} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_YIELDED unless \$PT_YIELD_FLAG;".$';
          $counter++;
          next;
        }
        ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_WAIT_UNTIL");
        if ($success) {
          $code=$before.$thread."->{PT_THREAD_STATE} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_WAITING unless ($arg);".$after;
          $counter++;
          next;
        }
        ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_WAIT_WHILE");
        if ($success) {
          $code=$before.$thread."->{PT_THREAD_STATE} = 'PT_LABEL_$counter'; PT_LABEL_$counter: return PT_WAITING if ($arg);".$after;
          $counter++;
          next;
        }
        ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_WAIT_THREAD");
        if ($success) {
          $code=$before."PT_WAIT_WHILE(PT_SCHEDULE(".$arg."));".$after;
          next;
        }
        ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_SPAWN");
        if ($success) {
          $code=$before.$arg."->{PT_THREAD_STATE} = 0; PT_WAIT_THREAD($arg);".$after;
          next;
        }
        ($success,$before,$arg,$after) = PT_NEXTCOMMAND($code,"PT_EXIT");
        if ($success) {
          $code=$before.$thread."->{PT_THREAD_STATE} = 0; ".$thread."->{PT_THREAD_RETURN} = $arg; return PT_EXITED;".$after;
          next;
        }
        if ($code =~ /PT_EXIT(\s*;|\s+)/s) {
          $code = $`.$thread."->{PT_THREAD_STATE} = 0; delete ".$thread."->{PT_THREAD_RETURN}; return PT_EXITED".$1.$';
          next;
        }
        if ($code =~ /PT_RESTART(\s*;|\s)/s) {
          $code = $`.$thread."->{PT_THREAD_STATE} = 0; return PT_WAITING;".$1.$';
          next;
        }
        if ($code =~ /PT_END\s*;/s) {
          $code = $`."} ".$thread."->{PT_THREAD_STATE} = 0; delete ".$thread."->{PT_THREAD_RETURN}; return PT_ENDED;".$';
        }
        last;
      }
      next;
    }
    last;
  };
  
  print $code if $DEBUG;
  
  $_ = $code;
  
  };

1;

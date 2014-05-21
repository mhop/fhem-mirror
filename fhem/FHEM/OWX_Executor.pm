##############################################
# $Id$
##############################################
package OWX_Executor;

use strict;
use warnings;

use constant {
	DISCOVER => 1,
	ALARMS   => 2,
	VERIFY   => 3,
	EXECUTE  => 4,
	EXIT     => 5,
	LOG      => 6
};

sub new() {
	my $class = shift;
	my $self = {};
	$self->{worker} = OWX_Worker->new($self);
	return bless $self,$class;
};

sub discover($) {
	my ($self,$hash) = @_;
	if($self->{worker}->submit( { command => DISCOVER }, $hash )) {
		$self->poll($hash);
		return 1;
	}
	return undef;
}

sub alarms($) {
	my ($self,$hash) = @_;
	if($self->{worker}->submit( { command => ALARMS }, $hash )) {
		$self->poll($hash);
		return 1;
	}
	return undef;
}

sub verify($$) {
  my ($self,$hash,$device) = @_;
  if($self->{worker}->submit( { command => VERIFY, address => $device }, $hash )) {
    $self->poll($hash);
    return 1;
  }
  return undef;
}

sub execute($$$$$$$) {
	my ( $self, $hash, $context, $reset, $owx_dev, $data, $numread, $delay ) = @_;
	if($self->{worker}->submit( {
		command   => EXECUTE,
		context   => $context,
		reset     => $reset,
		address   => $owx_dev,
		writedata => $data,
		numread   => $numread,
		delay     => $delay
 		}, $hash )) {
		$self->poll($hash);
		return 1;
	}
	return undef;
};

sub exit($) {
	my ( $self,$hash ) = @_;
	if($self->{worker}->submit( { command => EXIT }, $hash )) {
		$self->poll($hash);
		return 1;
	}
	return undef;
}

sub poll($) {
	my ( $self,$hash ) = @_;
	$self->read();
	$self->{worker}->PT_SCHEDULE($hash);
	$self->{worker}->scheduleNext($hash);
}

# start of worker code

package OWX_Worker;

use Time::HiRes qw( gettimeofday tv_interval usleep );
use ProtoThreads;
no warnings 'deprecated';

use vars qw/@ISA/;
@ISA='ProtoThreads';

sub new($) {
	my ($class,$owx) = @_;
	
	my $worker = PT_THREAD(\&pt_main);
	
	$worker->{commands} = [];
	$worker->{delayed} = {};
	$worker->{owx} = $owx;
	
	return bless $worker,$class;  
}

sub submit($$) {
	my ($self,$command,$hash) = @_;
	push @{$self->{commands}}, $command;
    $self->PT_SCHEDULE($hash);
	return 1;
}

sub pt_main($) {
	my ( $self, $hash ) = @_;
    my $item = $self->{item};
    PT_BEGIN($self);
	PT_YIELD_UNTIL($item = $self->nextItem($hash));
	$self->{item} = $item;
		
	REQUEST_HANDLER: {
		my $command = $item->{command};
		
		$command eq OWX_Executor::DISCOVER and do {
			PT_WAIT_THREAD($self->{owx}->{pt_discover},$self->{owx});
			my $devices = $self->{owx}->{pt_discover}->PT_RETVAL();
			if (defined $devices) {
				main::OWX_ASYNC_AfterSearch($hash,$devices);
			}
			PT_EXIT;
		};
		
		$command eq OWX_Executor::ALARMS and do {
			PT_WAIT_THREAD($self->{owx}->{pt_alarms},$self->{owx});
			my $devices = $self->{owx}->{pt_alarms}->PT_RETVAL();
			if (defined $devices) {
				main::OWX_ASYNC_AfterAlarms($hash,$devices);
			}
			PT_EXIT;
		};
		
		$command eq OWX_Executor::VERIFY and do {
			PT_WAIT_THREAD($self->{owx}->{pt_verify},$self->{owx},$item->{address});
			my $devices = $self->{owx}->{pt_verify}->PT_RETVAL();
			if (defined $devices) {
				main::OWX_ASYNC_AfterVerify($hash,$devices);
			}
			PT_EXIT;
		};

		$command eq OWX_Executor::EXECUTE and do {
		    PT_WAIT_THREAD($self->{owx}->{pt_execute},$self->{owx},$hash,$item->{context},$item->{reset},$item->{address},$item->{writedata},$item->{numread});
		    my $res = $self->{owx}->{pt_execute}->PT_RETVAL();
		    unless (defined $res) {
		      main::OWX_ASYNC_AfterExecute($hash,$item->{context},undef,$item->{reset},$item->{address},$item->{writedata},$item->{numread},undef);
		      PT_EXIT;
		    }
       		my $writelen = defined $item->{writedata} ? split (//,$item->{writedata}) : 0;
       		my @result = split (//, $res);
       		my $readdata = 9+$writelen < @result ? substr($res,9+$writelen) : ""; 
       		main::OWX_ASYNC_AfterExecute($hash,$item->{context},1,$item->{reset},$item->{address},$item->{writedata},$item->{numread},$readdata);
        	if (my $delay = $item->{delay}) {
       			my ($seconds,$micros) = gettimeofday;
       			my $len = length ($delay); #delay is millis, tv_address works with [sec,micros]
       			if ($len>3) {
       				$seconds += substr($delay,0,$len-3);
       				$micros += (substr ($delay,-3)*1000);
       			} else {
       				$micros += ($delay*1000);
       			}
       			
        		if (my $address = $item->{address}) {
        			my $delayed = $self->{delayed};
        			unless ($delayed->{$address}) {
        				$delayed->{$address} = { items => [] };
        			}
        			$delayed->{$address}->{'until'} = [$seconds,$micros];
        			main::Log3 $hash->{NAME},5,"delay after $item->{context} until: $seconds,$micros"
        		} else {
        		  $self->{execute_delayed} = [$seconds,$micros];
        		  PT_YIELD_UNTIL(tv_interval($self->{execute_delayed})>=0);
        		}
        	}
			PT_EXIT;
		};
		
		$command eq OWX_Executor::EXIT and do {
			main::OWX_ASYNC_Disconnected($hash);
			PT_EXIT;
		};
		main::Log3($hash->{NAME},3,"OWX_Executor: unexpected command: "+$command);
	};
	PT_END;
};

sub nextItem($) {
	my ( $self,$hash ) = @_;
	my ($item,$nexttime,$nextaddress);
	my $delayed = $self->{delayed};
	foreach my $address (keys %$delayed) {
		next if (tv_interval($delayed->{$address}->{'until'}) < 0);
		my $delayed_items = $delayed->{$address}->{'items'}; 
		$item = shift @$delayed_items;
		delete $delayed->{$address} unless @$delayed_items;
		last;
	};
	unless ($item) {
		$item = shift @{$self->{commands}};
		if ($item and my $address = $item->{address}) {
			if ($delayed->{$address}) {
				push @{$delayed->{$address}->{'items'}},$item;
				return undef; 
			};
		};
	};
	if ($item) {
	  if($item->{context}) {
	    main::Log3 $hash->{NAME},5,"OWX_Executor: item $item->{context} for ".(defined $item->{address} ? $item->{address} : "---")." eligible to run";
	  } else {
	    main::Log3 $hash->{NAME},5,"OWX_Executor: command $item->{command} eligible to run";
	  }
	}
	return $item;
}

sub scheduleNext($) {
  my ($self,$hash) = @_;
  my $delayed = $self->{delayed};
  my $nexttime;
	foreach my $address (keys %$delayed) {
		if (my $until = $delayed->{$address}->{'until'}) {
			$nexttime = $until unless ($nexttime and tv_interval($nexttime,$until) < 0);
		}
	};
	if ($nexttime) {
		main::RemoveInternalTimer($hash);
		main::Log3 $hash->{NAME},5,"schedule next item at $nexttime->[0].$nexttime->[1] ".tv_interval($nexttime);
		main::InternalTimer( "$nexttime->[0].$nexttime->[1]", "OWX_ASYNC_Poll", $hash, 0 );
	}
}

1;

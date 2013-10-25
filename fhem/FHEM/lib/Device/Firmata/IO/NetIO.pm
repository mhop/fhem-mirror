package Device::Firmata::IO::NetIO;

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;

use vars qw//;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

sub listen {
# --------------------------------------------------
    my ( $pkg, $ip, $port, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

	# flush after every write
	$| = 1;
	
	my $socket;
		
	# creating object interface of IO::Socket::INET modules which internally does
	# socket creation, binding and listening at the specified port address.
	$socket = new IO::Socket::INET (
	LocalHost => $ip,
	LocalPort => $port,
	Proto => 'tcp',
	Listen => 5,
	Reuse => 1
	) or die "ERROR in Socket Creation : $!\n";

	$self->{'socket'} = $socket;
	return $self;
}

sub accept {
	
	my ($self,$timeout) = @_;
	# waiting for new client connection.
	my $s = $self->{'select'};
	if (!($s)) {
		$s = IO::Select->new();
		$s->add($self->{'socket'});
		$self->{'select'} = $s;
	}
	if(my @ready = $s->can_read($timeout)) {
		my $socket = $self->{'socket'};
		foreach my $fh (@ready) {
			if ($fh == $socket) {
				if (my $client_socket = $socket->accept()) {
					return $self->attach($client_socket);
				}
			}
		}
	}
	return undef;
}

sub close {
	my $self = shift;
	if ($self->{'select'} && $self->{'socket'}) {
		$self->{'select'}->remove($self->{'socket'});
		delete $self->{'select'};
	}
	if ($self->{'socket'}) {
		$self->{'socket'}->close();
		delete $self->{'socket'};
	}
	if ($self->{clients}) {
		foreach my $client (@{$self->{clients}}) {
			$client->close();
		}
		delete $self->{clients};
	}
}

sub attach {
    my ( $pkg, $client_socket, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

	my $clientpackage = "Device::Firmata::IO::NetIO::Client";
	eval "require $clientpackage";
	
	my $clientio = $clientpackage->attach($client_socket);
	
    my $package = "Device::Firmata::Platform";
    eval "require $package";
  	my $platform = $package->attach( $clientio, $opts ) or die "Could not connect to Firmata Server";

	my $s = $self->{'select'};
	if (!($s)) {
		$s = IO::Select->new();
		$self->{'select'} = $s;
	}
	$s->add($client_socket);
	my $clients = $self->{clients};
	if (!($clients)) {
		$clients = [];
		$self->{clients} = $clients;
	}
	push $clients, $platform;

	# Figure out what platform we're running on
    $platform->probe();

    return $platform;
}

sub poll {
	my ($self,$timeout) = @_;
	my $s = $self->{'select'};
	return unless $s;
	if(my @ready = $s->can_read($timeout)) {
		my $socket = $self->{'socket'};
		my $clients = $self->{clients};
		if (! defined($clients)) {
			$clients = [];
			$self->{clients} = $clients;
		}
		my @readyclients = ();
		foreach my $fh (@ready) {
			if ($fh != $socket) {
				push @readyclients, grep { $fh == $_->{io}->{client}; } @$clients;
			}
		}
		foreach my $readyclient (@readyclients) {
			$readyclient->poll();
		}
	}
}

package Device::Firmata::IO::NetIO::Client;

use strict;
use warnings;
use IO::Socket::INET;

use vars qw//;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
    };

sub attach {
    my ( $pkg, $client_socket, $opts ) = @_;

    my $self = ref $pkg ? $pkg : $pkg->new($opts);

    $self->{client} = $client_socket;
   
    return $self;
}

=head2 data_write

Dump a bunch of data into the comm port

=cut

sub data_write {
# --------------------------------------------------
    my ( $self, $buf ) = @_;
    $Device::Firmata::DEBUG and print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
    return $self->{client}->write( $buf );
}


=head2 data_read

We fetch up to $bytes from the comm port
This function is non-blocking

=cut

sub data_read {
# --------------------------------------------------
    my ( $self, $bytes ) = @_;
	my ($buf, $res);
	$res = $self->{client}->sysread($buf, 512);
    $buf = "" if(!defined($res));
    
    if ( $Device::Firmata::DEBUG and $buf ) {
        print "<".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
    }
    return $buf;
}

=head2 close

close the underlying connection

=cut

sub close {
	my $self = shift;
	$self->{client}->close() if (($self->{client}) and $self->{client}->connected());
}

1;

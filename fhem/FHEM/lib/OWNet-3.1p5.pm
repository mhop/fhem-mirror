package OWNet ;

# OWNet module for perl
# $Id$
#
# Paul H Alfille -- copyright 2007
# Part of the OWFS suite:
#  http://www.owfs.org
#  http://owfs.sourceforge.net

=head1 NAME

OWNet -
Light weight access to B<owserver>

=head1 SYNOPSIS

OWNet is an easy way to access B<owserver> and thence the 1-wire bus.

Dallas Semiconductor's 1-wire system uses simple wiring and unique addresses for its interesting devices. The B<One Wire File System (OWFS)> is a suite of programs that hide 1-wire details behind a file system metaphor. B<owserver> connects to the 1-wire bus and provides network access.

B<OWNet> is a perl module that connects to B<owserver> and allows reading, writing and listing the 1-wire bus.

Example perl program that prints the temperature:

 use OWNet ;
 print OWNet::read( "localhost:4304" , "/10.67C6697351FF/temperature" ) ."\n" ;

There is the alternative object oriented form:

 use OWNet ;
 my $owserver = OWNet->new( "localhost:4304" ) ;
 print $owserver->read( "/10.67C6697351FF/temperature" ) ."\n" ;

=head1 SYNTAX

=head2 methods

=over

=item B<new>

 my $owserver = OWNet -> new( address ) ;

=item B<read>

 OWNet::read( address, path [,size [,offset]] )
 $owserver -> read( path [,size [,offset]] )

=item B<write>

 OWNet::write( address, path, value [,offset] )
 $owserver -> write( path, value [,offset] )

=item B<dir>

 OWNet::dir( address, path )
 $owserver -> dir( path )

=back

=head2 I<address>

TCP/IP I<address> of B<owserver>. Valid forms:

=over

=item I<name> test.owfs.net:4304

=item I<quad> number: 123.231.312.213:4304

=item I<host> localhost:4304

=item I<port> 4304

=back

=head2 I<additional arguments>

Additional arguments to add to address

Temperature scale can also be specified in the I<address>. Same syntax as the other OWFS programs:

=over

=item -C Celsius (Centigrade)

=item -F Fahrenheit

=item -K Kelvin

=item -R Rankine

=back

Pressure scale can also be specified in the I<address>. Same syntax as the other OWFS programs:

=over

=item -mbar     millibar (default)

=item -atm      atmosphere

=item -mmHg     mm Mercury

=item -inHg     inch Mercury

=item -psi      pounds per inch^2

=item -Pa       pascal

=back

Device display format (1-wire unique address) can also be specified in the I<address>, with the general form of -ff[.]i[[.]c] (I<f>amily I<i>d I<c>rc):

=over

=item -ff.i   /10.67C6697351FF (default)

=item -ffi    /1067C6697351FF

=item -ff.i.c /10.67C6697351FF.8D

=item -ff.ic  /10.67C6697351FF8D

=item -ffi.c  /1067C6697351FF.8D

=item -ffic   /1067C6697351FF8D

=back

Show directories that are themselves directories with a '/' suffix ( e.g. /10.67C6697351FF/ )

=over

=item --slash  show directory elements

=back

Trim whitespace from numeric values

=over

=item -trim  trim spaces

=back

Warning messages will only be displayed if verbose flag is specified in I<address>

=over

=item -v      verbose

=back

=head2 I<path>

B<owfs>-type I<path> to an item on the 1-wire bus. Valid forms:

=over

=item main directories

Used for the I<dir> method. E.g. "/" "/uncached" "/1F.321432320000/main"

=item device directory

Used for the I<dir> and I<present> method. E.g. "/10.4300AC220000" "/statistics"

=item device properties

Used to I<read>, I<write>. E.g. "/10.4300AC220000/temperature"

=back

=head2 I<value>

New I<value> for a device property. Used by I<write>.

=head1 METHODS

=over

=cut

BEGIN { }

use 5.008 ;
use warnings ;
use strict ;

use IO::Socket::INET ;
use bytes ;

my $MSG_READ = 2 ;
my $MSG_WRITE = 3 ;
my $MSG_DIR = 4 ;
my $MSG_PRESENCE = 6 ;
my $MSG_DIRALL = 7 ;
my $MSG_DIRALLSLASH = 9 ;

# return value should be negative for error, but the networking layer uses 32bit unsigned integers. This is the boundary.
my $MAX_RETURN = 66000 ;
# Network timeout in ms
my $MAX_WAIT = 3000 ;
my $RECV_FLAGS = 0 ;
my $SEND_FLAGS = 0 ;
my $NO_OFFSET = 0 ;

my $PERSISTENCE_BIT = 0x04 ;
# PresenceCheck, Return bus list,  and apply aliases
my $DEFAULT_SG = 0x100 + 0x2 + 0x8 ;
my $DEFAULT_BLOCK_LENGTH = 33000 ;

our $VERSION=(split(/ /,q[$Revision$]))[1] ;

sub _new($$) {
	my ($self,$addr) = @_ ;

	$addr =~ s/--/-/g ;

	my $tempscale = 0 ;
	TEMPSCALE: {
		$tempscale = 0x00000 , last TEMPSCALE if $addr =~ /-C/ ;
		$tempscale = 0x10000 , last TEMPSCALE if $addr =~ /-F/ ;
		$tempscale = 0x20000 , last TEMPSCALE if $addr =~ /-K/ ;
		$tempscale = 0x30000 , last TEMPSCALE if $addr =~ /-R/ ;
	}

	my $presscale = 0 ;
	PRESSCALE: {
		$presscale = 0x000000 , last PRESSCALE if $addr =~ /-mbar/i ;
		$presscale = 0x040000 , last PRESSCALE if $addr =~ /-atm/i ;
		$presscale = 0x080000 , last PRESSCALE if $addr =~ /-mmhg/i ;
		$presscale = 0x0C0000 , last PRESSCALE if $addr =~ /-inhg/i ;
		$presscale = 0x100000 , last PRESSCALE if $addr =~ /-psi/i ;
		$presscale = 0x140000 , last PRESSCALE if $addr =~ /-pa/i ;
	}

	my $format = 0 ;
	FORMAT: {
		$format = 0x2000000 , last FORMAT if $addr =~ /-ff\.i\.c/ ;
		$format = 0x4000000 , last FORMAT if $addr =~ /-ffi\.c/ ;
		$format = 0x3000000 , last FORMAT if $addr =~ /-ff\.ic/ ;
		$format = 0x5000000 , last FORMAT if $addr =~ /-ffic/ ;
		$format = 0x0000000 , last FORMAT if $addr =~ /-ff\.i/ ;
		$format = 0x1000000 , last FORMAT if $addr =~ /-ffi/ ;
		$format = 0x2000000 , last FORMAT if $addr =~ /-f\.i\.c/ ;
		$format = 0x4000000 , last FORMAT if $addr =~ /-fi\.c/ ;
		$format = 0x3000000 , last FORMAT if $addr =~ /-f\.ic/ ;
		$format = 0x5000000 , last FORMAT if $addr =~ /-fic/ ;
		$format = 0x0000000 , last FORMAT if $addr =~ /-f\.i/ ;
		$format = 0x1000000 , last FORMAT if $addr =~ /-fi/ ;
	}

	my $trim = 0 ;
	TRIM: {
		$trim = 0x00000040 , last TRIM if $addr =~ /-trim/ ;
	}

	# Verbose flag
	$self->{VERBOSE} = 1 if $addr =~ /-v/i ;
	
	# slash after directory elements
	$self->{SLASH} = 1 if $addr =~ /-slash/i ;

	$addr =~ s/-[\w\.]*//g ;
	$addr =~ s/ //g ;

	my $port ;
	if ( $addr =~ /(.*):(.*)/ ) {
		$addr = $1 ;
		$port = $2 ;
	} elsif ( $addr =~/\D/ ) {
		$port = '' ;
	} else {
		$port = $addr ;
		$addr = '' ;
	}

	$self->{ADDR} = $addr ;
	$self->{PORT} = $port ;
	$self->{SG} = $DEFAULT_SG + $tempscale + $presscale + $format + $trim ;
	$self->{VER} = 0 ;
}

sub _Sock($) {
	my $self = shift ;

	# persistent socket already there?
	if ( defined($self->{SOCK} && $self->{PERSIST} != 0  ) ) {
		return 1 ;
	}

	# defaults
	my $addr = $self->{ADDR} ;
	my $port = $self->{PORT} ;
	$addr = '127.0.0.1' if $addr eq '' ;
	$port = 'owserver(4304)' if $port eq '' ;

	# New socket
	$self->{SOCK} = IO::Socket::INET->new(
	    PeerAddr=>$addr,
	    PeerPort=>$port,
	    Proto=>'tcp')
	|| do {
		warn("Can't open $addr:$port ($!) \n") if $self->{VERBOSE} ;
		$self->{SOCK} = undef ;
		return ;
	} ;
	return 1 ;
}

sub _self($) {
	my $addr = shift ;
	my $self ;

	if ( ref($addr) ) {
		$self = $addr ;
		$self->{PERSIST} = $PERSISTENCE_BIT ;
	} else {
		$self = {} ;
		_new($self,$addr)  ;
		$self->{PERSIST} = 0 ;
	}

	if ( ($self->{ADDR} eq '') && ($self->{PORT} eq '') ) {
		_BonjourLookup($self) || _Sock($self) || return ;
	} else {
		_Sock($self) || return ;
	}
	return $self;
}

sub _BonjourLookup($) {
	my $self = shift ;

	eval { require Net::Rendezvous; };
	if ($@) {
		print "$@\n" if $self->{VERBOSE} ;
		return ;
	}

	my $owservers = Net::Rendezvous->new('owserver') || do {
		print "Unable to start owserver discovery via Net::Rendezvous $!\n" if $self->{VERBOSE} ;
		return ;
	} ;

	$owservers->discover ;
	my $owserver_selected = $owservers->shift_entry || do {
		print "No owserver discovered by Net::Rendezvous\n" if $self->{VERBOSE} ;
		return ;
	} ;
	print $owserver_selected->host.":".$owserver_selected->port."\n" if $self->{VERBOSE} ;

	# New socket
	$self->{SOCK} = IO::Socket::INET->new(PeerAddr=>$owserver_selected->host,PeerPort=>$owserver_selected->port,Proto=>'tcp') || do {
		warn("Can't open Bonjour (autodiscovered) port ($!) \n") if $self->{VERBOSE} ;
		$self->{SOCK} = undef ;
	return ;
	} ;
	$self->{ADDR} = $self->{SOCK}->peeraddr || return ;
	$self->{PORT} = $self->{SOCK}->peerport || return ;
	return 1 ;
}

sub _ToServer ($$$$;$) {
	my ($self, $msg_type, $size, $offset, $payload_data) = @_ ;
	my $f = "N6" ;
	my $payload_length = length($payload_data);
	$f .= 'A'.$payload_length ;
	my $message = pack($f,$self->{VER},$payload_length,$msg_type,$self->{SG}|$self->{PERSIST},$size,$offset,$payload_data) ;

	# try to send
	send( $self->{SOCK}, $message, $SEND_FLAGS ) && return 1 ;

	# maybe bad persistent connection
	if ( $self->{PERSIST} != 0 ) {
		$self->{SOCK} = undef ;
		_Sock($self) || return ;
		send( $self->{SOCK}, $message, $SEND_FLAGS ) && return 1 ;
	}

	warn("Send problem $! \n") if $self->{VERBOSE} ;
	return ;
}

sub _FromServerBinaryParse($$) {
	my $self = shift ;

	my $length_wanted = shift ;
	return '' if $length_wanted == 0 ;

	my $fileno = $self->{SOCK}->fileno  or return undef ;
	my $selectreadbits = '' ;
	vec($selectreadbits,$fileno,1) = 1 ;

	my $remaininglength = $length_wanted ;
	my $fullread = '' ;
	do {
		select($selectreadbits,undef,undef,$MAX_WAIT) ;
		return if vec($selectreadbits,$fileno,1) == 0 ;
		my $partialread ;
		defined( recv( $self->{SOCK}, $partialread, $remaininglength, $RECV_FLAGS ) ) || do {
			warn("Trouble getting data back $! after $remaininglength of $length_wanted") if $self->{VERBOSE} ;
			return ;
		} ;
		$fullread .= $partialread ;
		$remaininglength = $length_wanted - length($fullread) ;
	} while $remaininglength > 0 ;

	return $fullread ;
}

sub _FromServer($) {
	my $self = shift ;
	my ( $version, $payload_length, $return_status, $sg, $size, $offset, $payload_data ) ;

	do {
		my $r = _FromServerBinaryParse( $self,24 ) || do {
			warn("Trouble getting header $!") if $self->{VERBOSE} ;
			return ;
		} ;
		($version, $payload_length, $return_status, $sg, $size, $offset) = unpack('N6', $r ) ;
		return if $return_status > $MAX_RETURN ;
	} while $payload_length > $MAX_RETURN ;

	$payload_data = _FromServerBinaryParse( $self,$payload_length ) ;
	if ( !defined($payload_data) ) {
		warn("Trouble getting payload $!") if $self->{VERBOSE} ;
		return ;
	} ;
	$payload_data = substr($payload_data,0,$size) ;
	$self->{PERSIST} = $sg & $PERSISTENCE_BIT ;
	return ($version, $payload_length, $return_status, $sg, $size, $offset, $payload_data ) ;
}

=item B<new>

Object-oriented (only):

B<OWNet::new>( I<address> )

Create a new OWNet object -- corresponds to an B<owserver>.

Error (and undef return value) if:

=over

=item 1 Badly formed tcp/ip I<address>

=item 2 No B<owserver> at I<address>

=back

=cut

sub new($$) {
	my $class = shift ;
	my $addr = shift || "" ;
	my $self = {} ;
	_new($self,$addr) ;
	if ( !defined($self->{ADDR}) ) {
		return ;
	} ;
	bless $self, $class ;
	return $self ;
}

=item B<read>

=over

=item Non object-oriented:

B<OWNet::read>( I<address> , I<path> [ , I<size> [ , I<offset> ] ] )

=item Object-oriented:

$ownet->B<read>( I<path> [ , I<size> [ , I<offset> ] ] )

=back


Read the value of a 1-wire device property. Returns the (scalar string) value of the property.

I<size> (number of bytes to read) is optional

I<offset> (number of bytes from start of field to start write) is optional

Error (and undef return value) if:

=over

=item 1 (Non object) No B<owserver> at I<address>

=item 2 (Object form) Not called with a valid OWNet object

=item 3 Bad I<path>

=item 4 I<path> not a readable device property

=back

=cut

sub read($$) {
	my $self = _self(shift) || return ;
	my $path = shift ;
	my $read_length = shift || $DEFAULT_BLOCK_LENGTH ;
	my $offset = shift || $NO_OFFSET ;

	_ToServer($self,$MSG_READ,$read_length,$offset,$path) ;
	my @r = _FromServer($self) ;
	if ( !@r ) {
		return ;
	}
	return $r[6] ;
}

=item B<write>

=over

=item Non object-oriented:

B<OWNet::write>( I<address> , I<path> , I<value> [ , I<offset> ] )

=item Object-oriented:

$ownet->B<write>( I<path> , I<value> [ , I<offset> ] )

=back

Set the value of a 1-wire device property. Returns "1" on success.

I<offset> (number of bytes from start of field to start write) is optional

Error (and undef return value) if:

=over

=item 1 (Non object) No B<owserver> at I<address>

=item 2 (Object form) Not called with a valid OWNet object

=item 3 Bad I<path>

=item 4 I<path> not a writable device property

=item 5 I<value> incorrect size or format

=back

=cut

sub write($$$;$) {
	my $self = _self(shift) || return ;
	my $path = shift ;
	my $val = shift ;
	my $offset = shift || $NO_OFFSET ;

	my $value_length = length($val) ;
	my $path_length = length($path)+1 ;
	my $payload = pack( 'Z'.$path_length.'A'.$value_length,$path,$val ) ;
	_ToServer($self,$MSG_WRITE,$value_length,$offset,$payload) ;
	my @r = _FromServer($self) ;
	if ( !@r ) {
		return;
	}
	return $r[2]>=0 ;
}

=item B<dir>

=over

=item Non object-oriented:

B<OWNet::dir>( I<address> , I<path> )

=item Object-oriented:

$ownet->B<dir>( I<path> )

=back

Return a comma-separated list of the entries in I<path>. Entries are equivalent to "fully qualified names" -- full path names.

Error (and undef return value) if:

=over

=item 1 (Non object) No B<owserver> at I<address>

=item 2 (Object form) Not called with a valid OWNet object

=item 3 Bad I<path>

=item 4 I<path> not a directory

=back

=cut

sub dir($$) {
	my $self = _self(shift) || return ;
	my $path = shift ;

	# DIRALLSLASH method -- single packet with slash (/) after each dir entry
	if ( $self->{SLASH}) {
		_ToServer($self,$MSG_DIRALLSLASH,$DEFAULT_BLOCK_LENGTH,$NO_OFFSET,$path) || return ;
		my @r = _FromServer($self) ;
		if (@r) {
			$self->{SOCK} = undef if $self->{PERSIST} == 0 ;
			return $r[6] ;
		} ;
	}

	# new MSG_DIRALL method -- single packet
	_ToServer($self,$MSG_DIRALL,$DEFAULT_BLOCK_LENGTH,$NO_OFFSET,$path) || return ;
	my @r = _FromServer($self) ;
	return if !@r ;
	if (@r) {
		$self->{SOCK} = undef if $self->{PERSIST} == 0 ;
		return $r[6] ;
	} ;

	# old MSG_DIR method -- many packets
	_Sock($self) || return ;
	_ToServer($self,$MSG_DIR,$DEFAULT_BLOCK_LENGTH,$NO_OFFSET,$path) || return ;
	my $dirlist = '' ;
	while (1) {
		@r = _FromServer($self) || return ;
		return if !@r ;
	if ( $r[1] == 0 ) { # last null packet
		$self->{SOCK} = undef if $self->{PERSIST} == 0 ;
		return substr($dirlist,1) ; # not starting comma
	}
		$dirlist .= ','.$r[6] ;
	}
}


return 1 ;

END { }

=item B<present> (deprecated)

=over

=item Non object-oriented:

B<OWNet::present>( I<address> , I<path> )

=item Object-oriented:

$ownet->B<present>( I<path> )

=back

Test if a 1-wire device exists.

Error (and undef return value) if:

=over

=item 1 (Non object) No B<owserver> at I<address>

=item 2 (Object form) Not called with a valid OWNet object

=item 3 Bad I<path>

=item 4 I<path> not a device

=back

=cut

sub present($$) {
	my $self = _self(shift) || return ;
	my $path = shift ;
	_ToServer($self,$MSG_PRESENCE,$DEFAULT_BLOCK_LENGTH,$NO_OFFSET,$path) ;
	my @r = _FromServer($self) ;
		return if !@r ;
	return $r[2]>=0 ;
}

=back

=head1 DESCRIPTION

=head2 OWFS

I<OWFS> is a suite of programs that allows easy access to I<Dallas Semiconductor>'s 1-wire bus and devices. 
I<OWFS> provides a consistent naming scheme, safe multplexing of 1-wire traffice, multiple methods of access and display, and network access. 
The basic I<OWFS> metaphor is a file-system, with the bus beinng the root directory, each device a subdirectory, and the the device properties (e.g. voltage, temperature, memory) a file.

=head2 1-Wire

I<1-wire> is a protocol allowing simple connection of inexpensive devices. 
Each device has a unique ID number (used in its OWFS address) and is individually addressable. 
The bus itself is extremely simple -- a data line and a ground. The data line also provides power. 
1-wire devices come in a variety of packages -- chips, commercial boxes, and iButtons (stainless steel cans). 
1-wire devices have a variety of capabilities, from simple ID to complex voltage, temperature, current measurements, memory, and switch control.

=head2 Programs

Connection to the 1-wire bus is either done by bit-banging a digital pin on the processor, or by using a bus master -- USB, serial, i2c, parallel. 
The heavy-weight I<OWFS> programs: B<owserver> B<owfs> B<owhttpd> B<owftpd> and the heavy-weight perl module B<OW> all link in the full I<OWFS> library and can connect directly to the bus master(s) and/or to B<owserver>.

B<OWNet> is a light-weight module. It connects only to an B<owserver>, does not link in the I<OWFS> library, and should be more portable..

=head2 Object-oriented

B<OWNet> can be used in either a classical (non-object-oriented) manner, or with objects. 
The object stored the ip address of the B<owserver> and a network socket to communicate. 
B<OWNet> will use persistent tcp connections for the object form -- potentially a performance boost over a slow network.

=head1 EXAMPLES

=head2 owserver

B<owserver> is a separate process that must be accessible on the network. It allows multiple clients, and can connect to many physical 1-wire adapters and 1-wire devices. It's address must be discoverable -- either set on the command line, or at it's default location, or by using Bonjour (zeroconf) service discovery.

An example owserver invocation for a serial adapter and explicitly chooses the default port:

 owserver -d /dev/ttyS0 -p 4304

=head2 OWNet

 use OWNet ;

 # Create owserver object
 my $owserver = OWNet->new('localhost:4304 -v -F') ; #default location, verbose errors, Fahrenheit degrees
 # my $owserver = OWNet->new() ; #simpler, again default location, no error messages, default Celsius

 #print directory
 print $owserver->dir('/') ;

 #print temperature from known device (DS18S20,  ID: 10.13224366A280)
 print "Temperature: ".$owserver->read('/uncached/10.13224366A280/temperature') ;

 # Now for some fun -- a tree of everything:
 sub Tree($$) {
   my $ow = shift ;
   my $path = shift ;

   print "$path\t" ;

   # first try to read
   my $value = $ow->read($path) ;
   if ( defined($value) ) {
     print "$value\n";
     return ;
   }

   # not readable, try as directory
   my $dirstring = $ow->dir($path) ;
   if ( defined($dirstring) ) {
     print "<directory>\n" ;
     my @dir = split /,/ ,  $ow->dir($path) ;
     foreach (@dir) {
        Tree($ow,$_) ;
     }
     return ;
   }

   # can't read, not directory
   print "<write-only>\n" ;
   return ;
 }

 Tree( $owserver, '/' ) ;

=head1 INTERNALS

=head2 Object properties (All private)

=over

=item ADDR

literal sting for the IP address, in dotted-quad or host format. This property is also used to indicate a substantiated object.

=item PORT

string for the port number (or service name). Service name must be specified as :owserver or the like.

=item SG

Flag sent to server, and returned, that encodes temperature scale and display format. Persistence is also encoded in this word in the actual tcp message, but kept separately in the object.

=item VERBOSE

Print error messages? Set by "-v" in object invocation.

=item SLASH

Add "/" to the end of directory entries. Set by "-slash" in object invocation.

=item SOCK

Socket address (object) for communication. Stays defined for persistent connections, else deleted between calls.

=item PERSIST

State of socket connection (persistent means the same socket is used which speeds network communication).

=item VER

owprotocol version number (currently 0)

=back

=head2 Private methods

=over

=item _self

Takes either the implicit object reference (if called on an object) or the ip address in non-object format. 
In either case a socket is created, the persistence bit is properly set, and the address parsed. 
Returns the object reference, or undef on error. 
Called by each external method (read,write,dir) on the first parameter.

=item _new

Takes command line invocation parameters (for an object or not) and properly parses and sets up the properties in a hash array.

=item _Sock

Socket processing, including tests for persistence and opening.
If no host is specified, localhost (127.0.0.1) is used.
If no port is specified, uses the IANA allocated well known port (4304) for owserver. First looks in /etc/services, then just tries 4304.

=item _ToServer

Sends a message to owserver. Formats in owserver protocol. If a persistent socket fails, retries after new socket created.

=item _FromServerBinaryParse

Reads a specified length from server

=item _FromServer

Reads whole packet from server, using _FromServerBinaryParse (first for header, then payload). Discards ping packets silently.

=item _BonjourLookup

Uses the mDNS service discovery protocol to find an available owserver.
Employs NET::Rendezvous (an earlier name or Apple's Bonjour)
This module is loaded only if available. (Uses the method of http://sial.org/blog/2006/12/optional_perl_module_loading.html)

=back

=head1 AUTHOR

Paul H Alfille paul.alfille@gmail.com

=head1 BUGS

Support for proper timeout using the "select" function seems broken in perl. This might leave the routines vulnerable to network timing errors.

=head1 SEE ALSO

=over

=item http://www.owfs.org

Documentation for the full B<owfs> program suite, including man pages for each of the supported 1-wire devices, and more extensive explanatation of owfs components.

=item http://owfs.sourceforge.net/projects/owfs

Location where source code is hosted.

=back

=head1 COPYRIGHT

Copyright (c) 2007 Paul H Alfille. All rights reserved.
 This program is free software; you can redistribute it and/or
 modify it under the same terms as Perl itself.

=cut

# $Id$
##############################################

use strict;
use warnings;
require Exporter;
use Config;
use AutoLoader;


require "44_S7_Client.pm" ;

#use Socket;
use IO::Socket::INET;
use IO::Select;

#todo

#fehler in settimino:
#function :WriteArea & ReadArea
#bit shift opteratin in wrong direction
# PDU.H[23]=NumElements<<8; -->  PDU.H[23]=NumElements>>8;
# PDU.H[24]=NumElements;


our @ISA = qw(Exporter);

our %EXPORT_TAGS = (
	'all' => [
		qw(
		  errTCPConnectionFailed
		  errTCPConnectionReset
		  errTCPDataRecvTout
		  errTCPDataSend
		  errTCPDataRecv
		  errISOConnectionFailed
		  errISONegotiatingPDU
		  errISOInvalidPDU
		  errS7InvalidPDU
		  errS7SendingPDU
		  errS7DataRead
		  errS7DataWrite
		  errS7Function
		  errBufferTooSmall
		  Code7Ok
		  Code7AddressOutOfRange
		  Code7InvalidTransportSize
		  Code7WriteDataSizeMismatch
		  Code7ResItemNotAvailable
		  Code7ResItemNotAvailable1
		  Code7InvalidValue
		  Code7NeedPassword
		  Code7InvalidPassword
		  Code7NoPasswordToClear
		  Code7NoPasswordToSet
		  Code7FunNotAvailable
		  Code7DataOverPDU
		  S7_PG
		  S7_OP
		  S7_Basic
		  ISOSize
		  isotcp
		  MinPduSize
		  MaxPduSize
		  CC
		  S7Shift
		  S7WLBit
		  S7WLByte
		  S7WLWord
		  S7WLDWord
		  S7WLReal
		  S7WLCounter
		  S7WLTimer
		  S7CpuStatusUnknown
		  S7CpuStatusRun
		  S7CpuStatusStop
		  RxOffset
		  Size_RD
		  Size_WR
		  Size_DT
		  )
	]
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  errTCPConnectionFailed
  errTCPConnectionReset
  errTCPDataRecvTout
  errTCPDataSend
  errTCPDataRecv
  errISOConnectionFailed
  errISONegotiatingPDU
  errISOInvalidPDU
  errS7InvalidPDU
  errS7SendingPDU
  errS7DataRead
  errS7DataWrite
  errS7Function
  errBufferTooSmall
  Code7Ok
  Code7AddressOutOfRange
  Code7InvalidTransportSize
  Code7WriteDataSizeMismatch
  Code7ResItemNotAvailable
  Code7ResItemNotAvailable1
  Code7InvalidValue
  Code7NeedPassword
  Code7InvalidPassword
  Code7NoPasswordToClear
  Code7NoPasswordToSet
  Code7FunNotAvailable
  Code7DataOverPDU
  S7_PG
  S7_OP
  S7_Basic
  ISOSize
  isotcp
  MinPduSize
  MaxPduSize
  CC
  S7Shift
  S7WLBit
  S7WLByte
  S7WLWord
  S7WLDWord
  S7WLReal
  S7WLCounter
  S7WLTimer
  S7CpuStatusUnknown
  S7CpuStatusRun
  S7CpuStatusStop
  RxOffset
  Size_RD
  Size_WR
  Size_DT
);

package S7Client;

use strict;

#use S7ClientBase;


our @ISA = qw(S7ClientBase);    # inherits from Person

# Error Codes
# from 0x0001 up to 0x00FF are severe errors, the Client should be disconnected
# from 0x0100 are S7 Errors such as DB not found or address beyond the limit etc..
# For Arduino Due the error code is a 32 bit integer but this doesn't change the constants use.

use constant errTCPConnectionFailed => 0x0001;
use constant errTCPConnectionReset  => 0x0002;
use constant errTCPDataRecvTout     => 0x0003;
use constant errTCPDataSend         => 0x0004;
use constant errTCPDataRecv         => 0x0005;
use constant errISOConnectionFailed => 0x0006;
use constant errISONegotiatingPDU   => 0x0007;
use constant errISOInvalidPDU       => 0x0008;

use constant errS7InvalidPDU => 0x0100;
use constant errS7SendingPDU => 0x0200;
use constant errS7DataRead   => 0x0300;
use constant errS7DataWrite  => 0x0400;
use constant errS7Function   => 0x0500;

use constant errBufferTooSmall => 0x0600;

#CPU Errors

# S7 outcoming Error code
use constant Code7Ok                    => 0x0000;
use constant Code7AddressOutOfRange     => 0x0005;
use constant Code7InvalidTransportSize  => 0x0006;
use constant Code7WriteDataSizeMismatch => 0x0007;
use constant Code7ResItemNotAvailable   => 0x000A;
use constant Code7ResItemNotAvailable1  => 0xD209;
use constant Code7InvalidValue          => 0xDC01;
use constant Code7NeedPassword          => 0xD241;
use constant Code7InvalidPassword       => 0xD602;
use constant Code7NoPasswordToClear     => 0xD604;
use constant Code7NoPasswordToSet       => 0xD605;
use constant Code7FunNotAvailable       => 0x8104;
use constant Code7DataOverPDU           => 0x8500;

# Connection Type
use constant S7_PG    => 0x01;
use constant S7_OP    => 0x02;
use constant S7_Basic => 0x03;

# ISO and PDU related constants
use constant ISOSize    => 7;      # Size of TPKT + COTP Header
use constant isotcp     => 102;    # ISOTCP Port
use constant MinPduSize => 16;     # Minimum S7 valid telegram size
use constant MaxPduSize =>
  247;    # Maximum S7 valid telegram size (we negotiate 240 bytes + ISOSize)
use constant CC => 0xD0;    # Connection confirm
use constant S7Shift =>
  17;    # We receive data 17 bytes above to align with PDU.DATA[]

# WordLength
use constant S7WLBit     => 0x01;
use constant S7WLByte    => 0x02;
use constant S7WLChar    => 0x03;
use constant S7WLWord    => 0x04;
use constant S7WLInt     => 0x05;
use constant S7WLDWord   => 0x06;
use constant S7WLDInt    => 0x07;
use constant S7WLReal    => 0x08;
use constant S7WLCounter => 0x1C;
use constant S7WLTimer   => 0x1D;

# Result transport size
use constant TS_ResBit   => 0x03;
use constant TS_ResByte  => 0x04;
use constant TS_ResInt   => 0x05;
use constant TS_ResReal  => 0x07;
use constant TS_ResOctet => 0x09;

use constant S7CpuStatusUnknown => 0x00;
use constant S7CpuStatusRun     => 0x08;
use constant S7CpuStatusStop    => 0x04;

use constant RxOffset => 18;
use constant Size_DT  => 25;
use constant Size_RD  => 31;
use constant Size_WR  => 35;




sub new {
	my $class = shift;
	
	my $self = $class->SUPER::new();
	
	$self->{LocalTSAP_HI}   = 0x01;
	$self->{LocalTSAP_LO}   = 0x00;
	$self->{RemoteTSAP_HI}   = 0x01;
	$self->{RemoteTSAP_LO}   = 0x02;
	$self->{ConnType}   = &S7_PG;
	$self->{LastError}   = 0;
	$self->{LastPDUType}   = 0;
	$self->{Peer} = "";
	$self->{ISO_CR} = "";
	$self->{S7_PN} = "";
	$self->{S7_RW} = "";
	$self->{PDU} = {};
	$self->{cntword} = 0;
	
	#ISO Connection Request telegram (contains also ISO Header and COTP Header)
	$self->{ISO_CR} = pack(
		"C22",

		# TPKT (RFC1006 Header)
		0x03,    # RFC 1006 ID (3)
		0x00,    # Reserved, always 0
		0x00
		, # High part of packet length (entire frame, payload and TPDU included)
		0x16
		,  # Low part of packet length (entire frame, payload and TPDU included)
		   # COTP (ISO 8073 Header)
		0x11,    # PDU Size Length
		0xE0,    # CR - Connection Request ID
		0x00,    # Dst Reference HI
		0x00,    # Dst Reference LO
		0x00,    # Src Reference HI
		0x01,    # Src Reference LO
		0x00,    # Class + Options Flags
		0xC0,    # PDU Max Length ID
		0x01,    # PDU Max Length HI

		0x0A,    # PDU Max Length LO # snap7 value Bytes 1024

		#		0x09, # PDU Max Length LO # libnodave value Bytes 512

		0xC1,    # Src TSAP Identifier
		0x02,    # Src TSAP Length (2 bytes)
		0x01,    # Src TSAP HI (will be overwritten by ISOConnect())
		0x00,    # Src TSAP LO (will be overwritten by ISOConnect())
		0xC2,    # Dst TSAP Identifier
		0x02,    # Dst TSAP Length (2 bytes)
		0x01,    # Dst TSAP HI (will be overwritten by ISOConnect())
		0x02     # Dst TSAP LO (will be overwritten by ISOConnect())
	);

	# S7 PDU Negotiation Telegram (contains also ISO Header and COTP Header)
	$self->{S7_PN} = pack(
		"C25",
		0x03, 0x00, 0x00, 0x19, 0x02, 0xf0,
		0x80,    # TPKT + COTP (see above for info)
		0x32, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00,    #snap7 trace
		0x00, 0xf0, 0x00, 0x00, 0x01, 0x00, 0x01,

		#		0x00, 0xf0 # PDU Length Requested = HI-LO 240 bytes
		#		0x01, 0xe0 # PDU Length Requested = HI-LO 480 bytes
		0x03, 0xc0    # PDU Length Requested = HI-LO 960 bytes
	);

	# S7 Read/Write Request Header (contains also ISO Header and COTP Header)
	$self->{S7_RW} = pack(
		"C35",        # 31-35 bytes
		0x03, 0x00,
		0x00, 0x1f,          # Telegram Length (Data Size + 31 or 35)
		0x02, 0xf0, 0x80,    # COTP (see above for info)
		0x32,                # S7 Protocol ID
		0x01,                # Job Type
		0x00, 0x00,    # Redundancy identification (AB_EX)
		0x05, 0x00,    # PDU Reference #snap7 (increment by every read/write)
		0x00, 0x0e,    # Parameters Length
		0x00, 0x00,    # Data Length = Size(bytes) + 4
		0x04,          # Function 4 Read Var, 5 Write Var
		               #reqest param head
		0x01,          # Items count
		0x12,          # Var spec.
		0x0a,          # Length of remaining bytes
		0x10,          # Syntax ID
		&S7WLByte,     # Transport Size
		0x00, 0x00,    # Num Elements
		0x00, 0x00,    # DB Number (if any, else 0)
		0x84,          # Area Type
		0x00, 0x00, 0x00,    # Area Offset
		                     # WR area
		0x00,                # Reserved
		0x04,                # Transport size
		0x00, 0x00,          # Data Length * 8 (if not timer or counter)
	);

	$self->{PDU}->{H} = pack( "C35",
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 );
	$self->{PDU}->{DATA} = "";
	$self->{TCPClient} = undef;
	return bless $self, $class;
}


#-----------------------------------------------------------------------------
sub GetNextWord {
	my $self = shift;
	$self->{cntword} = 0 if ( $self->{cntword} == 0xFFFF );
	return $self->{cntword}++;
}

#-----------------------------------------------------------------------------
sub SetLastError {
	my ( $self, $Error ) = @_;
	$self->{LastError} = $Error;
	return $Error;
}

#-----------------------------------------------------------------------------

sub WaitForData {
	my ( $self, $Size, $Timeout ) = @_;
	my $BytesReady;

	$Timeout = $Timeout / 1000;

	#	$Timeout = 1 if ($Timeout < 1); #deactivated in V2.9
	my @ready = $self->{TCPClientSel}->can_read($Timeout);

	if ( scalar(@ready) ) {
		return $self->SetLastError(0);
	}

	# Here we are in timeout zone, if there's something into the buffer, it must be discarded.
	$self->{TCPClient}->flush();
	if ( !$self->{TCPClient}->connected() ) {
		return $self->SetLastError(&errTCPConnectionReset);
	}

	return $self->SetLastError(&errTCPDataRecvTout);
}

#-----------------------------------------------------------------------------
sub IsoPduSize {
	my ($self) = @_;

	my @buffer = unpack( "C" x 4, $self->{PDU}->{H} );
	my $Size = $buffer[2];
	return ( $Size << 8 ) + $buffer[3];

}

#-----------------------------------------------------------------------------
sub RecvPacket {
	my ( $self, $Size ) = @_;
	my $buf;

	$self->WaitForData( $Size, $self->{RecvTimeout} );
	if ( $self->{LastError} != 0 ) {

		return $self->{LastError};
	}

	my $res = $self->{TCPClient}->recv( $buf, $Size );

	if ( defined($buf) && length($buf) == $Size ) {
		return ( $self->SetLastError(0), $buf );
	}
	else {

		if ( defined($buf) ) {

			if ( $main::attr{global}{verbose} <= 3 ) {
				my $b = join( ", ", unpack( "H2 " x length($buf), $buf ) );
				main::Log3 (undef, 3,  "TCPClient RecvPacket error (IP= ". $self->{Peer} . "): " . $b);
			}
		}
		else {
			main::Log3 (undef, 3, "TCPClient RecvPacket error (IP= " . $self->{Peer} . ").");
		}
		return $self->SetLastError( &errTCPConnectionReset, $buf );
	}
}

#-----------------------------------------------------------------------------
sub SetConnectionParams {

	my ( $self, $Address, $LocalTSAP, $RemoteTSAP ) = @_;

	$self->{Peer}          = $Address;
	$self->{LocalTSAP_HI}  = $LocalTSAP >> 8;
	$self->{LocalTSAP_LO}  = $LocalTSAP & 0x00FF;
	$self->{RemoteTSAP_HI} = $RemoteTSAP >> 8;
	$self->{RemoteTSAP_LO} = $RemoteTSAP & 0x00FF;
}

#-----------------------------------------------------------------------------
sub SetConnectionType {
	my ( $self, $ConnectionType ) = @_;

	$self->{ConnType} = $ConnectionType;
}

#-----------------------------------------------------------------------------
sub ConnectTo {
	my ( $self, $Address, $Rack, $Slot ) = @_;

	$self->SetConnectionParams( $Address, 0x0100,
		( $self->{ConnType} << 8 ) + ( $Rack * 0x20 ) + $Slot );

	return $self->Connect();
}

#-----------------------------------------------------------------------------

sub Connect {	
	my ($self) = @_;
	$self->{LastError} = 0;
	if ( !$self->{Connected} ) {
		$self->TCPConnect();
		if ( $self->{LastError} == 0 )    # First stage : TCP Connection
		{
			$self->ISOConnect();
			if ( $self->{LastError} ==
				0 )    # Second stage : ISOTCP (ISO 8073) Connection
			{
				$self->{LastError} = $self->NegotiatePduLength()
				  ;    # Third stage : S7 PDU negotiation
			}
		}
	}

	if ( $self->{LastError} == 0 ) {
		$self->{Connected} = 1;
	}
	else {
		$self->{Connected} = 0;
	}
	return $self->{LastError};
}

#-----------------------------------------------------------------------------
sub Disconnect {
	my ($self) = @_;
	if ( $self->{Connected} ) {

		$self->{TCPClientSel} = undef;

		if ( defined( $self->{TCPClient} ) ) {
			my $res = shutdown( $self->{TCPClient}, 1 );
			if ( defined($res) ) {
				$self->{TCPClient}->flush() if ( $res == 0 );
			}
			$self->{TCPClient}->close();

			$self->{TCPClient} = undef;
		}
		$self->{Connected}     = 0;
		$self->{PDULength}     = 0;
		$self->{MaxReadLength} = 0;
		$self->{LastError}     = 0;
	}
}

#-----------------------------------------------------------------------------
sub TCPConnect {
	my ($self) = @_;

 #	# 1. create a socket handle (descriptor)
 #	my($sock);
 #	socket($sock, AF_INET, SOCK_STREAM, IPPROTO_TCP);#TCP_NODELAY,
 #
 #		or die "ERROR in Socket Creation: $!";
 #
 #	# 2. connect to remote server
 #	my $remote = $self->{Peer};
 #
 #	my $iaddr = inet_aton($remote) or die "Unable to resolve hostname : $remote";
 #	my $paddr = sockaddr_in(&isotcp, $iaddr);    #socket address structure
 #
 #	connect($sock , $paddr) or die "connect to $remote failed : $!";
 #	$self->{TCPClient} = $sock;
 #	return $self->SetLastError(0);
 #
 #	$self->{TCPClientSel} = new IO::Select($self->{TCPClient});

	$self->{TCPClient} = new IO::Socket::INET(
		PeerAddr => $self->{Peer},

		#		PeerHost => $self->{Peer},
		PeerPort => &isotcp,
		Type     => Socket::SOCK_STREAM,    # probably needed on some systems

		Proto => 'tcp',
	) or die "ERROR in Socket Creation: $!";

	$self->{TCPClient}->sockopt( &Socket::TCP_NODELAY, 1 );

	$self->{TCPClient}->autoflush(1);

	$self->{TCPClientSel} = new IO::Select( $self->{TCPClient} );

	return $self->SetLastError(0);

}

#-----------------------------------------------------------------------------

sub RecvISOPacket {

	my ($self) = @_;
	my $Size;

	my $Done      = 0;
	my $pdubuffer = "";
	my $res;

	$self->{LastError} = 0;
	while ( ( $self->{LastError} == 0 ) && !$Done ) {

		# Get TPKT (4 bytes)
		( $res, $pdubuffer ) = $self->RecvPacket(4);
		if ( $self->{LastError} == 0 ) {

			my $b = join( ", ", unpack( "H2 " x 4, $pdubuffer ) );

			$self->{PDU}->{H} = $pdubuffer . substr( $self->{PDU}->{H}, 4 );
			$Size = $self->IsoPduSize();
			main::Log3(undef, 5, "TCPClient RecvISOPacket Expected Size = $Size");

			# Check 0 bytes Data Packet (only TPKT+COTP - 7 bytes)
			if ( $Size == 7 ) {
				$pdubuffer = "";
				( $res, $pdubuffer ) = $self->RecvPacket(3);

				$self->{PDU}->{H} = $pdubuffer . substr( $self->{PDU}->{H}, 3 );

			}
			else {
				my $maxlen = $self->{PDULength} + &ISOSize;
				if ( $maxlen <= &MinPduSize ) {
					$maxlen = &MaxPduSize;
				}

				#				if (($Size > &MaxPduSize) || ($Size < &MinPduSize)) {
				if ( ( $Size > $maxlen ) || ( $Size < &MinPduSize ) ) {
					main::Log3 (undef, 3,   "TCPClient RecvISOPacket PDU overflow (IP= " . $self->{Peer} . "): size = $Size , maxPDULength = "  . $self->{PDULength});
					$self->{LastError} = &errISOInvalidPDU;
				}
				else {
					$Done = 1;    # a valid Length !=7 && >16 && <247
				}
			}
		}
	}
	if ( $self->{LastError} == 0 ) {
		$pdubuffer = "";
		( $res, $pdubuffer ) = $self->RecvPacket(3);

		$self->{PDU}->{H} = $pdubuffer
		  . substr( $self->{PDU}->{H}, 3 );    # Skip remaining 3 COTP bytes

		my @mypdu = unpack( "C2", $self->{PDU}->{H} );

		$self->{LastPDUType} = $mypdu[1];      # Stores PDU Type, we need it
		$Size -= &ISOSize;

		# We need to align with PDU.DATA

		$pdubuffer = "";
		( $res, $pdubuffer ) = $self->RecvPacket($Size);

		if ( $main::attr{global}{verbose} >= 5 ) {
			my $b = join( ", ", unpack( "H2 " x $Size, $pdubuffer ) );
			main::Log3 (undef, 5, "TCPClient RecvISOPacket (IP= " . $self->{Peer} . "): $b");
		}

		#we write the data starting at position 17 (shift) into the PDU.H
		if ( $self->{LastError} == 0 ) {

			if ( $Size > &Size_WR - &S7Shift ) {
				my $headerSize = &Size_WR - &S7Shift;

				$self->{PDU}->{H} =
				    substr( $self->{PDU}->{H}, 0, &S7Shift )
				  . substr( $pdubuffer, 0, $headerSize );

				$self->{PDU}->{DATA} = substr( $pdubuffer, $headerSize );

			}
			else {

				$self->{PDU}->{H} =
				    substr( $self->{PDU}->{H}, 0, &S7Shift )
				  . $pdubuffer
				  . substr( $self->{PDU}->{H}, &Size_WR - &S7Shift - $Size );
			}
		}

	}
	if ( $self->{LastError} != 0 ) {
		$self->{TCPClient}->flush();
	}
	return ( $self->{LastError}, $Size );
}

#-----------------------------------------------------------------------------

sub ISOConnect {
	my ($self) = @_;

	my $Done     = 0;
	my $myLength = 0;
	my $res;

	# Setup TSAPs
	my @myISO_CR = unpack( "C22", $self->{ISO_CR} );
	$myISO_CR[16] = $self->{LocalTSAP_HI};
	$myISO_CR[17] = $self->{LocalTSAP_LO};
	$myISO_CR[20] = $self->{RemoteTSAP_HI};
	$myISO_CR[21] = $self->{RemoteTSAP_LO};
	$self->{ISO_CR} = pack( "C22", @myISO_CR );

	my $b = join( ", ", unpack( "H2 " x 22, $self->{ISO_CR} ) );

	if ( $self->{TCPClient}->send( $self->{ISO_CR} ) == 22 )

	  #	if (send($self->{TCPClient}, $self->{ISO_CR}, &MSG_NOSIGNAL)==22)
	{
		( $res, $myLength ) = $self->RecvISOPacket();

		if (   ( $self->{LastError} == 0 )
			&& ( $myLength == 15 )
		  )    # 15 = 22 (sizeof CC telegram) - 7 (sizeof Header)
		{
			if ( $self->{LastPDUType} == &CC ) {    #Connection confirm
				return 0;
			}
			else {
				return $self->SetLastError(&errISOInvalidPDU);
			}
		}
		else {
			return $self->{LastError};
		}
	}
	else {
		return $self->SetLastError(&errISOConnectionFailed);
	}
}

#-----------------------------------------------------------------------------
sub NegotiatePduLength {
	my ($self) = @_;

	my $myLength;
	my $res;

	# Setup TSAPs
	my @myS7_PN = unpack( "C25", $self->{S7_PN} );
	my $myPDUID = $self->GetNextWord();
	$myS7_PN[11] = $myPDUID % 256;
	$myS7_PN[12] = ( $myPDUID >> 8 ) % 256;
	$self->{S7_PN} = pack( "C25", @myS7_PN );

	if ( $self->{TCPClient}->send( $self->{S7_PN} ) == 25 )

	  #	if (send($self->{TCPClient}, $self->{S7_PN}, &MSG_NOSIGNAL)==25)
	{
		( $res, $myLength ) = $self->RecvISOPacket();
		if ( $self->{LastError} == 0 ) {

			# check S7 Error
			my @myPDUheader = unpack( "C35", $self->{PDU}->{H} );

			if (   ( $myLength == 20 )
				&& ( $myPDUheader[27] == 0 )
				&& ( $myPDUheader[28] == 0 ) )   # 20 = size of Negotiate Answer
			{
				my @myPDUdata = unpack( "C2", $self->{PDU}->{DATA} );

				$self->{PDULength} = $myPDUdata[0];
				$self->{PDULength} =
				  ( $self->{PDULength} << 8 ) +
				  $myPDUdata[1];                 # Value negotiated

				$self->{MaxReadLength} = ( $self->{PDULength} - 18 );

				if ( $self->{PDULength} > 0 ) {
					return 0;
				}
				else {
					return $self->SetLastError(&errISONegotiatingPDU);
				}
			}
			else {
				return $self->SetLastError(&errISONegotiatingPDU);
			}
		}
		else {
			return $self->{LastError};
		}
	}
	else {
		return $self->SetLastError(&errISONegotiatingPDU);
	}
}

sub getPDULength() {
	my ($self) = @_;

	if ( $self->{Connected} ) {
		return $self->{PDULength};
	}

	return -1;
}

#-----------------------------------------------------------------------------
sub ReadArea () {

	my ( $self, $Area, $DBNumber, $Start, $Amount, $WordLen ) = @_;

	my $ptrData = "";

	my $Address;
	my $NumElements;
	my $MaxElements;
	my $TotElements;
	my $SizeRequested;
	my $myLength;
	my $res;

	my $WordSize = 1;

	$self->{LastError} = 0;

	# If we are addressing Timers or counters the element size is 2
	$WordSize = 2 if ( ( $Area == &S7ClientBase::S7AreaCT ) || ( $Area == &S7ClientBase::S7AreaTM ) );

	$MaxElements =
	  ( $self->{PDULength} - 18 ) / $WordSize;    # 18 = Reply telegram header
	$TotElements = $Amount;

	while ( ( $TotElements > 0 ) && ( $self->{LastError} == 0 ) ) {
		$NumElements = $TotElements;
		$NumElements = $MaxElements if ( $NumElements > $MaxElements );

		$SizeRequested = $NumElements * $WordSize;

		# Setup the telegram
		my @myPDU =
		  unpack( "C" x &Size_RD, substr( $self->{S7_RW}, 0, &Size_RD ) );

		#my $b = join( ", ", unpack("H2 " x &Size_RD,$self->{S7_RW}));
		# print "ReadArea: S7_RW      :".$b."\n";

		#set PDU Ref
		my $myPDUID = $self->GetNextWord();
		$myPDU[11] = $myPDUID % 256;
		$myPDU[12] = ( $myPDUID >> 8 ) % 256;

		$myPDU[20] = 0x0a;    # Length of remaining bytes
		$myPDU[21] = 0x10;    # syntag ID

		# Set DB Number
		$myPDU[27] = $Area;
		if ( $Area == &S7ClientBase::S7AreaDB ) {
			$myPDU[25] = ( $DBNumber >> 8 ) % 256;
			$myPDU[26] = $DBNumber % 256;
		}
		else {
			$myPDU[25] = 0x00;
			$myPDU[26] = 0x00;
		}

		# Adjusts Start
		if (   ( $WordLen == &S7WLBit )
			|| ( $WordLen == &S7WLCounter )
			|| ( $WordLen == &S7WLTimer ) )
		{
			$Address = $Start;
		}
		else {
			$Address = $Start << 3;
		}

		#set word length
		$myPDU[22] = $WordLen;

		# Num elements
		$myPDU[23] = ( $NumElements >> 8 )
		  % 256;    # hier ist denke ich ein fehler in der settimino.cpp

		$myPDU[24] = ($NumElements) % 256;

		# Address into the PLC
		$myPDU[30] = ($Address) % 256;
		$Address   = $Address >> 8;
		$myPDU[29] = ($Address) % 256;
		$Address   = $Address >> 8;
		$myPDU[28] = ($Address) % 256;

		$self->{PDU}->{H} =
		  pack( "C" x &Size_RD, @myPDU )
		  . substr( $self->{PDU}->{H}, &Size_RD );

		if ( $main::attr{global}{verbose} >= 5 ) {
			$b = join( ", ", unpack( "H2 " x &Size_RD, $self->{PDU}->{H} ) );
			main::Log3 (undef, 5, "TCPClient ReadArea (IP= " . $self->{Peer} . "): $b");
		}

		$b = substr( $self->{PDU}->{H}, 0, &Size_RD );
		if ( $self->{TCPClient}->send($b) == &Size_RD )
		{    #Achtung PDU.H ist größer als &Size_RD

#	if (send($self->{TCPClient}, $b, &MSG_NOSIGNAL)== &Size_RD) #Achtung PDU.H ist größer als &Size_RD

			( $res, $myLength ) = $self->RecvISOPacket();
			if ( $self->{LastError} == 0 ) {
				if ( $myLength >= 18 ) {

					@myPDU = unpack( "C" x &Size_WR, $self->{PDU}->{H} );

					if ( ( $myLength - 18 == $SizeRequested ) ) {

						#response was OK
						$ptrData =
						  substr( $self->{PDU}->{DATA}, 0, $SizeRequested )
						  ;    # Copies in the user's buffer
					}
					else {     # PLC reports an error
						if ( $myPDU[31] == 0xFF ) {

							my $b = join(
								", ",
								unpack(
									"H2 " x $myLength,
									$self->{PDU}->{H} . $self->{PDU}->{DATA}
								)
							);
							main::Log3 (undef, 3,  "TCPClient ReadArea error (IP= "  . $self->{Peer}. ") returned data not expected size: $b");
						}
						else {
							my $b = join(
								", ",
								unpack(
									"H2 " x (
										length( $self->{PDU}->{H} ) +
										  length( $self->{PDU}->{DATA} )
									),
									$self->{PDU}->{H} . $self->{PDU}->{DATA}
								)
							);
							main::Log3 (undef, 3,
							    "TCPClient ReadArea error (IP= "
							  . $self->{Peer}
							  . ") returned data not OK: $b");
						}
						$self->{LastError} = &errS7DataRead;
					}
				}
				else {
					$self->{LastError} = &errS7InvalidPDU;
				}
			}
		}
		else {
			$self->{LastError} = &errTCPDataSend;
		}

		$TotElements -= $NumElements;
		$Start += $NumElements * $WordSize;
	}
	return ( $self->{LastError}, $ptrData );
}

#-----------------------------------------------------------------------------

sub WriteArea {
	my ( $self, $Area, $DBNumber, $Start, $Amount, $WordLen, $ptrData ) = @_;

	my $Address;
	my $NumElements;
	my $MaxElements;
	my $TotElements;
	my $DataSize;
	my $IsoSize;
	my $myLength;

	my $Offset   = 0;
	my $WordSize = 1;
	my $res;

	$self->{LastError} = 0;

	# If we are addressing Timers or counters the element size is 2
	$WordSize = 2 if ( ( $Area == &S7ClientBase::S7AreaCT ) || ( $Area == &S7ClientBase::S7AreaTM ) );

	$MaxElements =
	  ( $self->{PDULength} - 35 ) / $WordSize;    # 35 = Write telegram header
	$TotElements = $Amount;

	while ( ( $TotElements > 0 ) && ( $self->{LastError} == 0 ) ) {
		$NumElements = $TotElements;
		if ( $NumElements > $MaxElements ) {
			$NumElements = $MaxElements;
		}

		#If we use the internal buffer only, we cannot exced the PDU limit
		$DataSize =
		  $NumElements * $WordSize; #<------ Fehler Datasize sollte in Byte sein
		$IsoSize = &Size_WR + $DataSize;

		# Setup the telegram
		my @myPDU =
		  unpack( "C" x &Size_WR, substr( $self->{S7_RW}, 0, &Size_WR ) );

		# Whole telegram Size
		# PDU Length
		$myPDU[2] = ( $IsoSize >> 8 ) % 256;
		$myPDU[3] = $IsoSize % 256;

		#set PDU Ref

		my $myPDUID = $self->GetNextWord();
		$myPDU[11] = $myPDUID % 256;
		$myPDU[12] = ( $myPDUID >> 8 ) % 256;

		# Data Length
		$myLength  = $DataSize + 4;
		$myPDU[15] = ( $myLength >> 8 ) % 256;
		$myPDU[16] = $myLength % 256;

		# Function
		$myPDU[17] = 0x05;

		$myPDU[20] = 0x0a;    # Length of remaining bytes
		$myPDU[21] = 0x10;    # syntag ID

		# Set DB Number
		$myPDU[27] = $Area;
		if ( $Area == &S7ClientBase::S7AreaDB ) {
			$myPDU[25] = ( $DBNumber >> 8 ) % 256;
			$myPDU[26] = $DBNumber % 256;
		}

		# Adjusts Start
		if (   ( $WordLen == &S7WLBit )
			|| ( $WordLen == &S7WLCounter )
			|| ( $WordLen == &S7WLTimer ) )
		{
			$Address = $Start;
		}
		else {
			$Address = $Start << 3;
		}

		# Address into the PLC
		$myPDU[30] = $Address % 256;
		$Address   = $Address >> 8;
		$myPDU[29] = $Address % 256;
		$Address   = $Address >> 8;
		$myPDU[28] = $Address % 256;

		#transport size
		my $bytesProElement;

		if ( $WordLen == &S7WLBit ) {
			$myPDU[32] = &TS_ResBit;
			$bytesProElement = 1;
		}

		#		elsif ($WordLen ==  &S7WLWord) { #V2.8 will be send as Bytes!
		#			$myPDU[32] = &TS_ResInt;
		#			$bytesProElement = 2;
		#		}
		#		elsif ($WordLen ==  &S7WLDWord) {
		#			$myPDU[32] = &TS_ResInt;
		#			$bytesProElement = 4;
		#		}
		elsif ( $WordLen == &S7WLInt ) {
			$myPDU[32] = &TS_ResInt;
			$bytesProElement = 2;
		}
		elsif ( $WordLen == &S7WLDInt ) {
			$myPDU[32] = &TS_ResInt;
			$bytesProElement = 4;
		}
		elsif ( $WordLen == &S7WLReal ) {
			$myPDU[32] = &TS_ResReal;
			$bytesProElement = 4;
		}
		elsif ( $WordLen == &S7WLChar ) {
			$myPDU[32] = &TS_ResOctet;
			$bytesProElement = 1;
		}
		elsif ( $WordLen == &S7WLCounter ) {
			$myPDU[32] = &TS_ResOctet;
			$bytesProElement = 2;
		}
		elsif ( $WordLen == &S7WLTimer ) {
			$myPDU[32] = &TS_ResOctet;
			$bytesProElement = 2;
		}
		else {
			$myPDU[32] = &TS_ResByte;
			$bytesProElement = 1;
		}

		if (   ( $myPDU[32] != &TS_ResOctet )
			&& ( $myPDU[32] != &TS_ResReal )
			&& ( $myPDU[32] != &TS_ResBit ) )
		{
			$myLength = $DataSize << 3;

		}
		else {
			$myLength = $DataSize;
		}

		# Num elements
		my $nElements = int( $NumElements / $bytesProElement );
		$myPDU[23] = ( $nElements >> 8 ) % 256;
		$myPDU[24] = ($nElements) % 256;

		#set word length
		$myPDU[22] = $WordLen;

		# Length
		$myPDU[33] = ( $myLength >> 8 ) % 256;
		$myPDU[34] = $myLength % 256;
		$self->{PDU}->{H} = pack( "C" x &Size_WR, @myPDU );

		# Copy data
		$self->{PDU}->{DATA} = substr( $ptrData, $Offset, $DataSize );

		if ( $main::attr{global}{verbose} <= 5 ) {
			my $b = join(
				", ",
				unpack(
					"H2 " x $IsoSize,
					$self->{PDU}->{H} . $self->{PDU}->{DATA}
				)
			);
			main::Log3 (undef, 5,
			  "TCPClient WriteArea (IP= " . $self->{Peer} . "): $b");
		}
		if (
			$self->{TCPClient}->send( $self->{PDU}->{H} . $self->{PDU}->{DATA} )
			== $IsoSize )
		{

# 	 	if (send($self->{TCPClient}, $self->{PDU}->{H}.$self->{PDU}->{DATA}, &MSG_NOSIGNAL)== $IsoSize)
			( $res, $myLength ) = $self->RecvISOPacket();
			if ( $self->{LastError} == 0 ) {

				if ( $myLength == 15 ) {
					@myPDU = unpack( "C" x &Size_WR, $self->{PDU}->{H} );

					if (   ( $myPDU[27] != 0x00 )
						|| ( $myPDU[28] != 0x00 )
						|| ( $myPDU[31] != 0xFF ) )
					{
						$self->{LastError} = &errS7DataWrite;

						#CPU has sent an Error?
						my $cpuErrorCode = $myPDU[31];
						my $error        = $self->getCPUErrorStr($cpuErrorCode);

						my $msg =
						  "TCPClient WriteArea error: $cpuErrorCode = $error";
						main::Log3 (undef, 3, $msg);

					}

				}
				else {
					$self->{LastError} = &errS7InvalidPDU;
				}
			}
		}
		else {
			$self->{LastError} = &errTCPDataSend;
		}

		$Offset += $DataSize;
		$TotElements -= $NumElements;
		$Start += $NumElements * $WordSize;
	}
	return $self->{LastError};
}

#-----------------------------------------------------------------------------
sub getPLCDateTime() {
	my ($self) = @_;
	my $IsoSize;
	my $res;
	my $TotElements;

	main::Log3 (undef, 3, "TCPClient getPLCDateTime:");

	# Setup the telegram
	my @myPDU = unpack( "C" x &Size_DT, substr( $self->{S7_RW}, 0, &Size_DT ) );

	# Whole telegram Size
	# PDU Length
	$IsoSize = &Size_DT;

	$myPDU[2] = ( $IsoSize >> 8 ) % 256;
	$myPDU[3] = $IsoSize % 256;

	$myPDU[8] = 0x07;    #job type = userdata

	$myPDU[9]  = 0x00;   # Redundancy identification
	$myPDU[10] = 0x00;

	#set PDU Ref
	my $myPDUID = $self->GetNextWord();
	$myPDU[11] = ( $myPDUID >> 8 ) % 256;
	$myPDU[12] = $myPDUID % 256;

	#parameter length
	$myPDU[13] = 0x00;
	$myPDU[14] = 0x08;

	# Data Length
	my $myLength = 4;
	$myPDU[15] = ( $myLength >> 8 ) % 256;
	$myPDU[16] = $myLength % 256;

	# Function
	$myPDU[17] = 0x04;    #read

	#set parameter heads
	$myPDU[18] = 0x01;    # Items count
	$myPDU[19] = 0x12;    # Var spec.
	$myPDU[20] = 0x04;    # Length of remaining bytes
	$myPDU[21] = 0x11;    # uk
	$myPDU[22] = 0x47;    # tg = grClock
	$myPDU[23] = 0x01;    #subfunction: Read Clock (Date and Time)
	$myPDU[24] = 0x00;    #Seq

	$self->{PDU}->{H} =
	  pack( "C" x &Size_DT, @myPDU ) . substr( $self->{PDU}->{H}, &Size_DT );

	my $b = join( ", ", unpack( "H2 " x &Size_DT, $self->{PDU}->{H} ) );
	main::Log3 (undef, 3,
	  "TCPClient getPLCDateTime (IP= " . $self->{Peer} . "): $b");

	$b = substr( $self->{PDU}->{H}, 0, &Size_DT );
	if ( $self->{TCPClient}->send($b) == &Size_DT ) {

		#		main::Log3 undef, 3,"TCPClient getPLCDateTime request sent";
		( $res, $myLength ) = $self->RecvISOPacket();
		main::Log3 (undef, 3, "TCPClient getPLCDateTime RecvISOPacket $res");
		if ( $self->{LastError} == 0 ) {
			if ( $myLength >= 18 ) {

				@myPDU = unpack( "C" x $myLength, $self->{PDU}->{H} );
				my $b = join(
					", ",
					unpack(
						"H2 " x $myLength,
						$self->{PDU}->{H} . $self->{PDU}->{DATA}
					)
				);
				main::Log3 (undef, 3,
				  "TCPClient getPLCDateTime getPLCTime Result (IP= "
				  . $self->{Peer} . "): $b");

			}
			else {
				$self->{LastError} = &errS7InvalidPDU;
				main::Log3 (undef, 3,
				  "TCPClient getPLCDateTime errS7InvalidPDU length $myLength");

			}
		}
	}
	else {
		$self->{LastError} = &errTCPDataSend;
		main::Log3 (undef, 3, "TCPClient getPLCDateTime errTCPDataSend");
	}
	return ( $self->{LastError}, 0 );
}

#-----------------------------------------------------------------------------

sub version {
	return "1.1";
}

#-----------------------------------------------------------------------------

sub getErrorStr {
	my ( $self, $errorCode ) = @_;

	if ( $errorCode == &errTCPConnectionFailed ) {
		return "TCP Connection error";
	}
	elsif ( $errorCode == &errTCPConnectionReset ) {
		return "Connection reset by the peer";
	}
	elsif ( $errorCode == &errTCPDataRecvTout ) {
		return "A timeout occurred waiting a reply.";
	}
	elsif ( $errorCode == &errTCPDataSend ) {
		return "Ethernet driver returned an error sending the data";
	}
	elsif ( $errorCode == &errTCPDataRecv ) {
		return "Ethernet driver returned an error receiving the data.";
	}
	elsif ( $errorCode == &errISOConnectionFailed ) {
		return "ISO connection failed.";
	}
	elsif ( $errorCode == &errISONegotiatingPDU ) {
		return "ISO PDU negotiation failed";
	}
	elsif ( $errorCode == &errISOInvalidPDU ) {
		return "Malformed PDU supplied.";
	}
	elsif ( $errorCode == &errS7InvalidPDU ) { return "Invalid PDU received."; }
	elsif ( $errorCode == &errS7SendingPDU ) { return "Error sending a PDU."; }
	elsif ( $errorCode == &errS7DataRead ) { return "Error during data read"; }
	elsif ( $errorCode == &errS7DataWrite ) {
		return "Error during data write";
	}
	elsif ( $errorCode == &errS7Function ) {
		return "The PLC reported an error for this function.";
	}
	elsif ( $errorCode == &errBufferTooSmall ) {
		return "The buffer supplied is too small.";
	}
	else { return "unknown errorcode"; }

}

sub getCPUErrorStr {
	my ( $self, $errorCode ) = @_;

	if ( $errorCode == &Code7Ok ) { return "CPU: OK"; }
	elsif ( $errorCode == &Code7AddressOutOfRange ) {
		return "CPU: AddressOutOfRange";
	}
	elsif ( $errorCode == &Code7InvalidTransportSize ) {
		return "CPU: Invalid Transport Size";
	}
	elsif ( $errorCode == &Code7WriteDataSizeMismatch ) {
		return "CPU: Write Data Size Mismatch";
	}
	elsif ( $errorCode == &Code7ResItemNotAvailable ) {
		return "CPU: ResItem Not Available";
	}
	elsif ( $errorCode == &Code7ResItemNotAvailable1 ) {
		return "CPU: ResItem Not Available1";
	}
	elsif ( $errorCode == &Code7InvalidValue ) { return "CPU: Invalid Value"; }
	elsif ( $errorCode == &Code7NeedPassword ) { return "CPU: Need Password"; }
	elsif ( $errorCode == &Code7InvalidPassword ) {
		return "CPU: Invalid Password";
	}
	elsif ( $errorCode == &Code7NoPasswordToClear ) {
		return "CPU: No Password To Clear";
	}
	elsif ( $errorCode == &Code7NoPasswordToSet ) {
		return "CPU: No Password To Set";
	}
	elsif ( $errorCode == &Code7FunNotAvailable ) {
		return "CPU: Fun Not Available";
	}
	elsif ( $errorCode == &Code7DataOverPDU ) { return "CPU: DataOverPDU"; }
	else                                      { return "unknown errorcode"; }
}

1;
=pod
=item summary low level interface to S7
=item summary_DE low level interface to S7

=begin html

<p><a name="S7_S7Client"></a></p>
<h3>S7_S7Client</h3>
<ul>
<ul>low level interface to S7</ul>
</ul>

=end html
=begin html_DE

<p><a name="S7_S7Client"></a></p>
<h3>S7_S7Client</h3>
<ul>
<ul>low level interface to S7</ul>
</ul>

=end html_DE

=cut
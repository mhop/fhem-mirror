# $Id$
##############################################

use strict;
use warnings;
require Exporter;
use Config;
use AutoLoader;

require "44_S7_Client.pm";

package S5Client;

#use S7ClientBase;
our @ISA = qw(S7ClientBase);    # inherits from Person

#---------------------- constants for communication

use constant DLE => 0x10;
use constant ETX => 0x03;
use constant STX => 0x02;
use constant SYN => 0x16;
use constant NAK => 0x15;
use constant EOT => 0x04;       #  for S5
use constant ACK => 0x06;       #  for S5

use constant daveS5BlockType_DB => 0x01;
use constant maxSysinfoLen      => 87;
use constant daveMaxRawLen      => 2048;

use constant MaxPduSize =>
  240; 


sub new {
	my $class = shift;

	my $self = $class->SUPER::new();

	$self->{S5PAEAddress}     = 0;
	$self->{S5PAAAddress}     = 0;
	$self->{S5flagsAddress}   = 0;
	$self->{S5timerAddress}   = 0;
	$self->{S5counterAddress} = 0;

	$self->{__davet1006} = [ &DLE, &ACK ];
	$self->{__daveT161003} = [ 0x16, &DLE, &ETX ];
	$self->{__davet121003} = [ 0x12, &DLE, &ETX ];
	
	$self->{PDULength} = &MaxPduSize;
	$self->{MaxReadLength} = ($self->{PDULength} - 18);
		

	#my @__davet1006 = ( &DLE, &ACK );
	#my @__daveT161003 = ( 0x16, &DLE, &ETX );
	#my @{$self->{__davet121003}} = ( 0x12, &DLE, &ETX );

	return bless $self, $class;
}

# ----------- compare arrays

sub compare {
	my ( $self, $a_ref, $b_ref ) = @_;
	my @a = @{$a_ref};    # dereferencing and copying each array
	my @b = @{$b_ref};

	if ( @a != @b ) {

		return 0;
	}
	else {
		foreach ( my $i = 0 ; $i < @a ; $i++ ) {

			# Ideally, check for undef/value comparison here as well
			if ( $a[$i] != $b[$i] )
			{             # use "ne" if elements are strings, not numbers
				          # Or you can use generic sub comparing 2 values
				return 0;
			}
		}
		return 1;
	}
}

#
# -----------    This writes a single chracter to the serial interface
#

sub S5SendSingle($$) {
	my ( $self, $c ) = @_;
	my $buffer = pack( 'C*', $c );

	my $tbuffer = join( ", ", unpack( "H2 " x length($buffer), $buffer ) );
	main::Log3( undef, 5, "S5Client S5SendSingle <-- " . $tbuffer );

	$self->{serial}->write($buffer);
}

#---------------------------------------------------reqest transaction with PLC

sub S5ReqTrans($$) {
	my ( $self, $trN ) = @_;
	my $buffer;
	my $count;
	my $tbuffer;

	$self->S5SendSingle(&STX);    #start trasmission
	                              #expected S5 awnswer DLE,ACK

	( $count, $buffer ) = $self->{serial}->read(2);
	my @cbuffer = unpack( "C" x $count, $buffer );

	if ( $main::attr{global}{verbose} >= 5 ) {
		$tbuffer = join( ", ", unpack( "H2 " x $count, $buffer ) );
		main::Log3( undef, 5, "S5Client S5ReqTrans $tbuffer -->" );
	}

	if ( $self->compare( \@cbuffer, \@{ $self->{__davet1006} } ) == 0 ) {
		main::Log3( undef, 3, "S5Client S5ReqTrans: no DLE,ACK before send" );
		return -1;
	}
	$self->S5SendSingle($trN);
	( $count, $buffer ) = $self->{serial}->read(1);

	if ( $main::attr{global}{verbose} >= 5 ) {
		$tbuffer = join( ", ", unpack( "H2 " x $count, $buffer ) );
		main::Log3( undef, 5, "S5Client S5ReqTrans $tbuffer -->" );
	}

	if ( $count != 1 ) {

		#error awnser is too short
		return -1;
	}
	@cbuffer = unpack( "C" x $count, $buffer );

	if ( $cbuffer[0] ne &STX ) {
		main::Log3( undef, 3, "S5Client S5ReqTrans: no STX before send" );
		return -2;
	}

	$self->S5SendDLEACK();
	( $count, $buffer ) = $self->{serial}->read(3);

	if ( $main::attr{global}{verbose} >= 5 ) {
		$tbuffer = join( ", ", unpack( "H2 " x $count, $buffer ) );
		main::Log3( undef, 5, "S5Client S5ReqTrans $tbuffer -->" );
	}

	@cbuffer = unpack( "C" x $count, $buffer );
	if ( $self->compare( \@cbuffer, \@{ $self->{__daveT161003} } ) == 0 ) {
		main::Log3( undef, 3, "S5Client S5ReqTrans: no accept0 from plc" );
		return -3;
	}

	$self->S5SendDLEACK();
	return 0;
}

sub S5SendDLEACK($) {
	my ($self) = @_;

	my $buffer = pack( 'C2', @{ $self->{__davet1006} } );

	if ( $main::attr{global}{verbose} >= 5 ) {
		my $tbuffer = join( ", ", unpack( "H2 " x 2, $buffer ) );
		main::Log3( undef, 5, "S5Client S5SendDLEACK <-- $tbuffer" );
	}

	return $self->{serial}->write($buffer);
}

#---------------------------------------------- S5 Exchange data

sub S5ExchangeAS511($$$$$) {
	my ( $self, $b, $len, $maxlen, $trN ) = @_;

	my ( $res, $i, $b1, $count );
	my @cbuffer;
	my $msgIn = "";
	my $tbuffer;

	$res = $self->S5ReqTrans($trN);
	if ( $res < 0 ) {

		main::Log3( undef, 3,
			"S5Client S5ExchangeAS511: Error in Exchange.ReqTrans request" );
		return ( $res - 10, "" );
	}

	if ( $trN == 8 ) {    #Block write functions have advanced syntax
		                  #LOG1("trN 8\n");
		$self->S5SendWithDLEDup( $b, 4 );

		#LOG1("trN 8 done\n");
	}
	else {

		#LOG3("trN %d len %d\n",trN,len);
		$self->S5SendWithDLEDup( $b, $len );

		#LOG2("trN %d done\n",trN);
	}

	( $count, $b1 ) = $self->{serial}->read(2);

#	if ( $main::attr{global}{verbose} >= 5 ) {
		$tbuffer = join( ", ", unpack( "H2 " x $count, $b1 ) );
		main::Log3( undef, 5, "S5Client S5ExchangeAS511 $tbuffer -->" );
#	}

	@cbuffer = unpack( "C" x $count, $b1 );
	if ( $self->compare( \@cbuffer, \@{ $self->{__davet1006} } ) == 0 ) {
		main::Log3( undef, 3,
			"S5Client S5ExchangeAS511: no DLE,ACK in Exchange request" );
		return ( -1, "" );
	}

	if ( ( $trN != 3 ) && ( $trN != 7 ) && ( $trN != 9 ) ) {

		#write bytes, compress & delblk
		if ( !$self->S5ReadSingle() eq &STX ) {
			main::Log3( undef, 3,
				"S5Client S5ExchangeAS511: no STX in Exchange request" );
			return ( -2, "" );
		}

		$self->S5SendDLEACK();
		$res     = 0;
		@cbuffer = ();
		my $buffer = "";
		do {

			( $i, $b1 ) = $self->{serial}->read(1);

			$res += $i;
			push( @cbuffer, unpack( "C" x $i, $b1 ) ) if ( $i > 0 );

		  } while (
			( $i > 0 )
			&& (   ( $cbuffer[ $res - 2 ] != &DLE )
				|| ( $cbuffer[ $res - 1 ] != &ETX ) )
		  );

		if ( $main::attr{global}{verbose} >= 5 ) {
			$tbuffer =
			  join( ", ", unpack( "H2 " x @cbuffer, pack( "C*", @cbuffer ) ) );
			main::Log3( undef, 5, "S5Client S5ExchangeAS511 $tbuffer -->" );
		}

		#LOG3( "%s *** got %d bytes.\n", dc->iface->name, res );

		if ( $res < 0 ) {
			main::Log3( undef, 3,
				"S5Client S5ExchangeAS511: Error in Exchange.ReadChars request"
			);

			return ( $res - 20, "" );
		}

		if (   ( $cbuffer[ $res - 2 ] != &DLE )
			|| ( $cbuffer[ $res - 1 ] != &ETX ) )
		{
			main::Log3( undef, 3,
				"S5Client S5ExchangeAS511: No DLE,ETX in Exchange data." );
			return ( -4, "" );
		}

		( $res, $msgIn ) = $self->S5DLEDeDup( \@cbuffer );
		if ( $res < 0 ) {
			main::Log3( undef, 3,
				"S5Client S5ExchangeAS511: Error in Exchange rawdata." );
			return ( -3, "" );
		}

		$self->S5SendDLEACK();
	}

	if ( $trN == 8 ) {    # Write requests have more differences from others
		@cbuffer = unpack( "C" x length($msgIn), $msgIn );

		if ( $cbuffer[0] != 9 ) {    #todo fix
			main::Log3( undef, 3,
				"S5Client S5ExchangeAS511 No 0x09 in special Exchange request."
			);
			return ( -5, "" );
		}
		$self->S5SendSingle(&STX);

		( $count, $b1 ) = $self->{serial}->read(2);

		if ( $main::attr{global}{verbose} >= 5 ) {
			$tbuffer = $tbuffer = join( ", ", unpack( "H2 " x $count, $b1 ) );
			main::Log3( undef, 5, "S5Client S5ExchangeAS511 $tbuffer -->" );
		}

		@cbuffer = unpack( "C" x $count, $b1 );
		if ( $self->compare( \@cbuffer, \@{ $self->{__davet1006} } ) == 0 ) {
			main::Log3( undef, 3,
"S5Client S5ExchangeAS511 no DLE,ACK in special Exchange request"
			);
			return ( -6, "" );
		}

		my $b2 = substr( $b, 4 );
		$self->S5SendWithDLEDup( $b2, $len );    # todo need testing !!!
		     #$self->S5SendWithDLEDup(dc->iface,b+4,len); #

		( $count, $b1 ) = $self->{serial}->read(2);

		if ( $main::attr{global}{verbose} >= 5 ) {
			$tbuffer = join( ", ", unpack( "H2 " x $count, $b1 ) );
			main::Log3( undef, 5, "S5Client S5ExchangeAS511 $tbuffer -->" );
		}

		@cbuffer = unpack( "C" x $count, $b1 );
		if ( $self->compare( \@cbuffer, \@{ $self->{__davet1006} } ) == 0 ) {
			main::Log3( undef, 3,
"S5Client S5ExchangeAS511 no DLE,ACK after transfer in Exchange."
			);
			return ( -7, "" );
		}
	}

	if ( $trN == 7 ) {
	}
	$res = $self->S5EndTrans();
	if ( $res < 0 ) {
		main::Log3( undef, 3,
			"S5Client S5ExchangeAS511 Error in Exchange.EndTrans request." );
		return ( $res - 30, "" );
	}
	return ( 0, $msgIn );
}

#
#    Sends a sequence of characters after doubling DLEs and adding DLE,EOT.
#
sub S5SendWithDLEDup($$$) {
	my ( $self, $b, $size ) = @_;

	#	uc target[&daveMaxRawLen];
	my @target;
	my $res;
	my $i;    #preload

	my @cbuffer = unpack( "C" x $size, $b );

	#LOG1("SendWithDLEDup: \n");
	#_daveDump("I send",b,size);

	for ( $i = 0 ; $i < $size ; $i++ ) {
		push( @target, $cbuffer[$i] );

		if ( $cbuffer[$i] == &DLE ) {
			push( @target, &DLE );
		}
	}

	push( @target, &DLE );
	push( @target, &EOT );

	#LOGx_daveDump("I send", target, targetSize);

	my $buffer = pack( 'C*', @target );

	$res = $self->{serial}->write($buffer);

	if ( $main::attr{global}{verbose} >= 5 ) {
		my $tbuffer = join( ", ", unpack( "H2 " x length($buffer), $buffer ) );
		main::Log3( undef, 5, "S5Client S5SendWithDLEDup <-- $tbuffer" );
	}

	#if(daveDebug & daveDebugExchange)
	#LOG2("send: res:%d\n",res);
	return 0;
}

#
#    Remove the DLE doubling:
#

sub S5DLEDeDup($$) {

	my ( $self, $b ) = @_;
	my @rawBuf = @{$b};

	my @msg = ();

	my $j = 0;
	my $k;
	for ( $k = 0 ; $k < @rawBuf - 2 ; $k++ ) {
		push( @msg, $rawBuf[$k] );

		if ( DLE == $rawBuf[$k] ) {
			if ( DLE != $rawBuf[ $k + 1 ] ) {
				return ( -1, "" );    #Bad doubling found
			}
			$k++;
		}
	}

	push( @msg, $rawBuf[$k] );
	$k++;
	push( @msg, $rawBuf[$k] );

	$b = pack( 'C*', @msg );

	return ( 0, $b );
}

#
#    Executes part of the dialog required to terminate transaction:
#

sub S5EndTrans($) {
	my ($self) = @_;

	#LOG2("%s daveEndTrans\n", dc->iface->name);
	if ( $self->S5ReadSingle() ne &STX ) {

		#LOG2("%s daveEndTrans *** no STX at eot sequense.\n", dc->iface->name);
		#return -1;
	}
	$self->S5SendDLEACK();

	my ( $res, $b1 ) = $self->{serial}->read(3);

	if ( $main::attr{global}{verbose} >= 5 ) {
		my $tbuffer = join( ", ", unpack( "H2 " x $res, $b1 ) );
		main::Log3( undef, 5, "S5Client S5EndTrans $tbuffer -->" );
	}

	#_daveDump("3got",b1, res);

	my @cbuffer = unpack( "C" x $res, $b1 );
	if ( $self->compare( \@cbuffer, \@{ $self->{__davet121003} } ) == 0 ) {
		main::Log3( undef, 3,
			"S5Client S5EndTransno accept of eot/ETX from plc." );
		return -2;
	}

	$self->S5SendDLEACK();
	return 0;

}

#
#    This reads a single chracter from the serial interface:

sub S5ReadSingle ($) {
	my ($self) = @_;
	my ( $res, $i );

	( $i, $res ) = $self->{serial}->read(1);
	if ( $main::attr{global}{verbose} >= 5 ) {
		my $tbuffer = join( ", ", unpack( "H2 " x $i, $res ) );
		main::Log3( undef, 5, "S5Client S5ReadSingle $tbuffer -->" );
	}

	#if ((daveDebug & daveDebugSpecialChars)!=0)
	#    LOG3("readSingle %d chars. 1st %02X\n",i,res);
	if ( $i == 1 ) {
		return $res;
	}
	return 0;

}

#--------------------------------------------------------------------------------
# Connect to S5 CPU
#

sub S5ConnectPLCAS511($$) {
	my ( $self, $portName ) = @_;
	my $b1 = "";
	my $ttyPort;

	if($^O =~ m/Win/) {
		require Win32::SerialPort;
		#eval ("use Win32::SerialPort;");
		$self->{serial} = new Win32::SerialPort ($portName);
	}else{
		#eval ("use Device::SerialPort;");
		require Device::SerialPort;
		$self->{serial} = new Device::SerialPort ($portName);
    }

	main::Log3( undef, 3, "Can't open serial port $portName" )
	  unless ( $self->{serial} );
	die unless ( $self->{serial} );

	$self->{serial}->baudrate(9600);
	$self->{serial}->databits(8);
	$self->{serial}->parity('even');
	$self->{serial}->stopbits(1);

	$self->{serial}->read_const_time(500);    # 500 milliseconds = 0.5 seconds
	$self->{serial}->read_char_time(10);      # avg time between read char

	#$ttyPort->handshake('none');
	#$ttyPort->stty_icrnl(1);
	#$ttyPort->stty_ocrnl(1);
	#$ttyPort->stty_onlcr(1);
	#$ttyPort->stty_opost(1)

	$self->{serial}->write_settings();

	$b1 = pack( "C*", 0, 0 );
	my ( $res, $msgIn ) =
	  $self->S5ExchangeAS511( $b1, 2, &maxSysinfoLen, 0x18 );

	if ( $res < 0 ) {
		main::Log3( undef, 3,
			"S5Client S5ConnectPLCAS511 ImageAddr.Exchange sequence" );
		return $res - 10;
	}
	if ( length($msgIn) < 47 ) {
		main::Log3( undef, 3,
			"S5Client S5ConnectPLCAS511 Too few chars in ImageAddr data" );
		return -2;
	}

	#_daveDump("connect:",dc->msgIn, 47);

	my @cbuffer = unpack( "C" x length($msgIn), $msgIn );
	$self->{S5PAEAddress} =
	  $self->WordAt( \@cbuffer, 5 );    # start of inputs;
	$self->{S5PAAAddress} = $self->WordAt( \@cbuffer, 7 );    # start of outputs
	$self->{S5flagsAddress} =
	  $self->WordAt( \@cbuffer, 9 );    #  start of flag (marker) memory;
	$self->{S5timerAddress} =
	  $self->WordAt( \@cbuffer, 11 );    #start of timer memory;
	$self->{S5counterAddress} =
	  $self->WordAt( \@cbuffer, 13 );    #start of counter memory

	main::Log3( undef, 3,
		"S5Client ->S5ConnectPLCAS511 start of inputs in memory "
		  . $self->{S5PAEAddress} );
	main::Log3( undef, 3,
		"S5Client ->S5ConnectPLCAS511 start of outputs in memory "
		  . $self->{S5PAAAddress} );
	main::Log3( undef, 3,
		"S5Client ->S5ConnectPLCAS511 start of flags in memory "
		  . $self->{S5flagsAddress} );
	main::Log3( undef, 3,
		"S5Client ->S5ConnectPLCAS511 start of timers in memory "
		  . $self->{S5timerAddress} );
	main::Log3( undef, 3,
		"S5Client ->S5ConnectPLCAS511 start of counters in memory "
		  . $self->{S5counterAddress} );
		  
	

	return 0;

}

#
#    Reads <count> bytes from area <BlockN> with offset <offset>,
#    that can be readed with daveGetInteger etc. You can read bytes from
#    PBs & FBs too, but use daveReadBlock for this:
#

sub S5ReadS5Bytes($$$$$) {
	my ( $self, $area, $BlockN, $offset, $count ) = @_;
	my ( $res, $dataend, $datastart, $b1, $msgIn );

	if ( $area == &S7ClientBase::S7AreaDB ) {    #DB
		( $res, $datastart ) = $self->S5ReadS5BlockAddress( $area, $BlockN );
		if ( $res < 0 ) {
			main::Log3( undef, 3,
				"S5Client S5ReadS5Bytes Error in ReadS5Bytes.BlockAddr request"
			);
			return ( $res - 50, "" );
		}
	}
	elsif ( $area == &S7ClientBase::S7AreaPE ) {    #inputs

		$datastart =
		  $self->{S5PAEAddress};   #need to get this information from a property

	}
	elsif ( $area == &S7ClientBase::S7AreaPA ) {    #outputs

		$datastart =
		  $self->{S5PAAAddress};   #need to get this information from a property

	}
	elsif ( $area == &S7ClientBase::S7AreaMK ) {    #flags

		$datastart =
		  $self->{S5flagsAddress}; #need to get this information from a property

	}
	elsif ( $area == &S7ClientBase::S7AreaTM ) {    #timers

		$datastart =
		  $self->{S5timerAddress}; #need to get this information from a property

	}
	elsif ( $area == &S7ClientBase::S7AreaCT ) {    #counters

		$datastart = $self
		  ->{S5counterAddress};    #need to get this information from a property
	}
	else {
		main::Log3( undef, 3,
			"S5Client S5ReadS5Bytes Unknown area in ReadS5Bytes request" );
		return ( -1, "" );

	}

	if ( $count > &daveMaxRawLen ) {
		main::Log3( undef, 3,
			"S5Client S5ReadS5Bytes: Requested data is out-of-range" );
		return ( -1, "" );
	}
	$datastart += $offset;
	$dataend = $datastart + $count - 1;

	$b1 = pack( "C*",
		$datastart / 256,
		$datastart % 256,
		$dataend / 256,
		$dataend % 256 );

	( $res, $msgIn ) = $self->S5ExchangeAS511( $b1, 4, 2 * $count + 7, 0x04 );

	if ( $res < 0 ) {
		main::Log3( undef, 3,
			"S5Client S5ReadS5Bytes Error in ReadS5Bytes.Exchange sequence" );
		return ( $res - 10, "" );
	}

#if (dc->AnswLen<count+7) { #todo implement this check
#    LOG3("%s *** Too few chars (%d) in ReadS5Bytes data.\n", dc->iface->name,dc->AnswLen);
#return (-5,"");
#}

	my @cbuffer = unpack( "C" x length($msgIn), $msgIn );

	if (   ( $cbuffer[0] != 0 )
		|| ( $cbuffer[1] != 0 )
		|| ( $cbuffer[2] != 0 )
		|| ( $cbuffer[3] != 0 )
		|| ( $cbuffer[4] != 0 ) )
	{
		main::Log3( undef, 3,
			"S5Client S5ReadS5Bytes Wrong ReadS5Bytes data signature" );
		return ( -6, "" );
	}

	$msgIn = substr( $msgIn, 5, -2 );
	return ( 0, $msgIn );

}

#
#    Requests physical addresses and lengths of blocks in PLC memory and writes
#    them to ai structure:
#

sub S5ReadS5BlockAddress($$$) {
	my ( $self, $area, $BlockN ) = @_;
	my ( $res, $msgIn, $dbaddr, $dblen, $ai );

	my $b1 = pack( "C*", &daveS5BlockType_DB, $BlockN )
	  ;    #note we only support DB, no PB,FB,SB

	( $res, $msgIn ) = $self->S5ExchangeAS511( $b1, 2, 24, 0x1A );

	if ( $res < 0 ) {
		main::Log3( undef, 3,
"S5Client >S5ReadS5BlockAddress Error in BlockAddr.Exchange sequense"
		);
		return ( $res - 10, 0, 0 );
	}
	if ( length($msgIn) < 15 ) {
		main::Log3( undef, 3,
			"S5Client S5ReadS5BlockAddress Too few chars in BlockAddr data." );
		return ( -2, 0, 0 );
	}

	my @cbuffer = unpack( "C" x length($msgIn), $msgIn );

	if (   ( $cbuffer[0] != 0 )
		|| ( $cbuffer[3] != 0x70 )
		|| ( $cbuffer[4] != 0x70 )
		|| ( $cbuffer[5] != 0x40 + &daveS5BlockType_DB )
		|| ( $cbuffer[6] != $BlockN ) )
	{
		main::Log3( undef, 3,
			"S5Client S5ReadS5BlockAddress Wrong BlockAddr data signature." );

		return ( -3, 0, 0 );
	}

	$dbaddr = $cbuffer[1];
	$dbaddr =
	  $dbaddr * 256 +
	  $cbuffer[2];    #Let make shift operations to compiler's optimizer

	$dblen = $cbuffer[11];
	$dblen =
	  ( $dblen * 256 + $cbuffer[12] - 5 ) *
	  2;              #PLC returns dblen in words including
	                  #5 word header (but returnes the
	                  #start address after the header) so
	                  #dblen is length of block body
	return ( 0, $dbaddr, $dblen );

}

#
#    Writes <count> bytes from area <BlockN> with offset <offset> from buf.
#    You can't write data to the program blocks because you can't syncronize
#    with PLC cycle. For this purposes use daveWriteBlock:
#

sub S5WriteS5Bytes($$$$$$) {
	my ( $self, $area, $BlockN, $offset, $count, $buf ) = @_;
	my ( $res, $datastart, $dblen, $b1, $msgIn );

	if ( $area == &S7ClientBase::S7AreaDB ) {    #DB
		( $res, $datastart, $dblen ) =
		  $self->S5ReadS5BlockAddress( $area, $BlockN );
		if ( $res < 0 ) {
			main::Log3( undef, 3,
"S5Client S5WriteS5Bytes Error in ReadS5Bytes.BlockAddr request."
			);
			return $res - 50;
		}
	}
	elsif ( $area == &S7ClientBase::S7AreaPE ) {    #inputs

		$datastart =
		  $self->{S5PAEAddress};   #need to get this information from a property
		  
		$dblen = 128;

	}
	elsif ( $area == &S7ClientBase::S7AreaPA ) {    #outputs

		$datastart =
		  $self->{S5PAAAddress};   #need to get this information from a property
		  
		$dblen = 128;  

	}
	elsif ( $area == &S7ClientBase::S7AreaMK ) {    #flags

		$datastart =
		  $self->{S5flagsAddress}; #need to get this information from a property
		
		#$dblen = 128; # S5-90U
		$dblen = 256; # S5-95U

	}
	elsif ( $area == &S7ClientBase::S7AreaTM ) {    #timers

		$datastart =
		  $self->{S5timerAddress}; #need to get this information from a property
		  
		#$dblen = 32 *2; # S5-90U
		$dblen = 128 *2; # S5-95U

	}
	elsif ( $area == &S7ClientBase::S7AreaCT ) {    #counters

		$datastart = $self
		  ->{S5counterAddress};    #need to get this information from a property
		  
		#$dblen = 32 *2; # S5-90U
		$dblen = 128 * 2; # S5-95U
		  
	}
	else {
		main::Log3( undef, 3,
			"S5Client S5WriteS5Bytes Unknown area in WriteS5Bytes request." );
		return -1;
	}
	
	
	

	if ( ( $count > &daveMaxRawLen ) || ( $offset + $count > $dblen ) ) {
		main::Log3( undef, 3,
			"S5Client S5WriteS5Bytes Requested data is out-of-range." );
		return -1;
	}

	#LOG2("area start is %04x, ",datastart);
	$datastart += $offset;

	#LOG2("data start is %04x\n",datastart);

	$b1 = pack( "C*", $datastart / 256, $datastart % 256 );

	$b1 = $b1 . $buf;

	( $res, $msgIn ) = $self->S5ExchangeAS511( $b1, 2 + $count, 0, 0x03 );
	if ( $res < 0 ) {
		main::Log3( undef, 3,
			"S5Client S5WriteS5Bytes Error in WriteS5Bytes.Exchange sequense."
		);
		return $res - 10;
	}
	return 0;
}
1;
=pod
=item summary low level interface to S5
=item summary_DE low level interface to S5

=begin html

<p><a name="S7_S5Client"></a></p>
<h3>S7_S5Client</h3>
<ul>
<ul>low level interface to S5</ul>
</ul>
=end html
=begin html_DE

<p><a name="S7_S5Client"></a></p>
<h3>S7_S5Client</h3>
<ul>
<ul>low level interface to S5</ul>
</ul>

=end html_DE

=cut

# $Id$
####################################################

package main;

use strict;
use warnings;

#use Devel::NYTProf; #profiler

require "44_S7_S7Client.pm";
require "44_S7_S5Client.pm";

my %gets = (
	"S7TCPClientVersion" => "",
	"PLCTime"            => ""
);

my %sets = (
	"intervall" => ""
);

my @areasconfig = (
	"ReadInputs-Config",  "ReadOutputs-Config",
	"ReadFlags-Config",   "ReadDB-Config",
	"WriteInputs-Config", "WriteOutputs-Config",
	"WriteFlags-Config",  "WriteDB-Config"
);
my @s7areas = (
	&S7ClientBase::S7AreaPE, &S7ClientBase::S7AreaPA, &S7ClientBase::S7AreaMK,
	&S7ClientBase::S7AreaDB, &S7ClientBase::S7AreaPE, &S7ClientBase::S7AreaPA,
	&S7ClientBase::S7AreaMK, &S7ClientBase::S7AreaDB
);
my @areaname =
  ( "inputs", "outputs", "flags", "db", "inputs", "outputs", "flags", "db" );

#####################################
sub S7_Initialize($) {    #S5_OK

	my $hash = shift @_;

	# Provider
	$hash->{Clients} = ":S7_DRead:S7_ARead:S7_AWrite:S7_DWrite:";
	my %matchList = (
		"1:S7_DRead"  => "^DR",
		"2:S7_DWrite" => "^DW",
		"3:S7_ARead"  => "^AR",
		"4:S7_AWrite" => "^AW"
	);

	$hash->{MatchList} = \%matchList;

	# Consumer
	$hash->{DefFn}    = "S7_Define";
	$hash->{UndefFn}  = "S7_Undef";
	$hash->{GetFn}    = "S7_Get";
	$hash->{SetFn}   = "S7_Set";
	
	$hash->{AttrFn}   = "S7_Attr";
	$hash->{AttrList} = "disable:0,1 MaxMessageLength Intervall receiveTimeoutMs " . $readingFnAttributes;

	#	$hash->{AttrList} = join( " ", @areasconfig )." PLCTime";
}

#####################################
sub S7_connect($) {
	my $hash = shift @_;

	my $name = $hash->{NAME};

	if ( $hash->{STATE} eq "connected to PLC" ) {
		Log3( $name, 2, "$name S7_connect: allready connected!" );
		return;
	}

	Log3( $name, 4,
		    "S7: $name connect PLC_address="
		  . $hash->{plcAddress}
		  . ", LocalTSAP="
		  . $hash->{LocalTSAP}
		  . ", RemoteTSAP="
		  . $hash->{RemoteTSAP}
		  . " " );

	if ( !defined( $hash->{S7PLCClient} ) ) {
		S7_reconnect($hash);
		return;
	}

	$hash->{STATE} = "disconnected";
	main::readingsSingleUpdate( $hash, "state", "disconnected", 1 );
	my $res;

	if ( $hash->{S7TYPE} eq "S5" ) {
		eval {
			local $SIG{__DIE__} = sub {
				my ($s) = @_;
				Log3( $hash, 0, "S7_connect: $s" );
				$res = -1;
			};
			$res =
			  $hash->{S7PLCClient}->S5ConnectPLCAS511( $hash->{plcAddress} );
		};
	}
	else {
		$hash->{S7PLCClient}
		  ->SetConnectionParams( $hash->{plcAddress}, $hash->{LocalTSAP},
			$hash->{RemoteTSAP} );

		eval {
			local $SIG{__DIE__} = sub {
				my ($s) = @_;
				Log3( $hash, 0, "S7_connect: $s" );
				$res = -1;
			};
			$res = $hash->{S7PLCClient}->Connect();
		};
	}

	if ($res) {
		Log3( $name, 2, "S7_connect: $name Could not connect to PLC ($res)" );
		return;
	}

	my $PDUlength = $hash->{S7PLCClient}->{PDULength};
	$hash->{maxPDUlength} = $PDUlength;

	Log3( $name, 3,
		"$name S7_connect: connect to PLC with maxPDUlength=$PDUlength" );

	$hash->{STATE} = "connected to PLC";
	main::readingsSingleUpdate( $hash, "state", "connected to PLC", 1 );

	return undef;

}

#####################################
sub S7_disconnect($) {    #S5 OK
	my $hash = shift @_;
	my ( $ph, $res, $di );
	my $name  = $hash->{NAME};
	my $error = "";

	$hash->{S7PLCClient}->Disconnect() if ( defined( $hash->{S7PLCClient} ) );
	$hash->{S7PLCClient} = undef;    #PLC Client freigeben

	$hash->{STATE} = "disconnected";
	main::readingsSingleUpdate( $hash, "state", "disconnected", 1 );

	Log3( $name, 2, "$name S7 disconnected" );

}

#####################################
sub S7_reconnect($) {                #S5 OK
	my $hash = shift @_;
	S7_disconnect($hash) if ( defined( $hash->{S7PLCClient} ) );

	
	
	if ( $hash->{S7TYPE} eq "S5" ) {
		$hash->{S7PLCClient} = S5Client->new();
	}
	else {
		$hash->{S7PLCClient} = S7Client->new();
	}
	InternalTimer( gettimeofday() + 3, "S7_connect", $hash, 1 )
	  ;                              #wait 3 seconds for reconnect
}

#####################################
sub S7_Define($$) {                  # S5 OK
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );

	my ( $name, $PLC_address, $LocalTSAP, $RemoteTSAP, $res, $PDUlength, $rack,
		$slot );

	$name = $a[0];

	if ( uc $a[2] eq "S5" ) {
		$hash->{S7TYPE}   = "S5";
		$PLC_address      = $a[3];
		if (@a > 4) {
			$hash->{Interval} = $a[4];
		} else {
			$hash->{Interval} = 1;
		} 
		$LocalTSAP        = -1;
		$RemoteTSAP       = -1;

		$PDUlength = 240;

	}
	elsif ( uc $a[2] eq "LOGO7" || uc $a[2] eq "LOGO8" ) {
		$PLC_address      = $a[3];
		$LocalTSAP        = 0x0100;
		$RemoteTSAP       = 0x0200;
		if (@a > 4) {
			$hash->{Interval} = $a[4];
		} else {
			$hash->{Interval} = 1;
		} 
		if ( uc $a[2] eq "LOGO7" ) {
			$hash->{S7TYPE} = "LOGO7";
		}
		else {
			$hash->{S7TYPE} = "LOGO8";
		}
		$PDUlength = 240;

	}
	else {

		$PLC_address = $a[2];

		$rack = int( $a[3] );
		return "invalid rack parameter (0 - 15)"
		  if ( $rack < 0 || $rack > 15 );

		$slot = int( $a[4] );
		return "invalid slot parameter (0 - 15)"
		  if ( $slot < 0 || $slot > 15 );

		$hash->{Interval} = 1;
		if ( int(@a) == 6 ) {
			$hash->{Interval} = int( $a[5] );
			return "invalid intervall parameter (1 - 86400)"
			  if ( $hash->{Interval} < 1 || $hash->{Interval} > 86400 );
		}
		$LocalTSAP = 0x0100;
		$RemoteTSAP = ( &S7Client::S7_PG << 8 ) + ( $rack * 0x20 ) + $slot;

		$PDUlength = 0x3c0;

		$hash->{S7TYPE} = "NATIVE";
	}

	$hash->{plcAddress}   = $PLC_address;
	$hash->{LocalTSAP}    = $LocalTSAP;
	$hash->{RemoteTSAP}   = $RemoteTSAP;
	$hash->{maxPDUlength} = $PDUlength;     #initial PDU length
    $hash->{receiveTimeoutMs} = 500; #default receiving timeout = 500ms
	Log3 $name, 4,
"S7: define $name PLC_address=$PLC_address,LocalTSAP=$LocalTSAP, RemoteTSAP=$RemoteTSAP ";

	$hash->{STATE} = "disconnected";
	main::readingsSingleUpdate( $hash, "state", "disconnected", 1 );

    if (!S7_isDisabled($hash)) {
	    S7_connect($hash);
	    InternalTimer( gettimeofday() + $hash->{Interval},
		     "S7_GetUpdate", $hash, 0 );
    }
	return undef;
}

#####################################
sub S7_Undef($) {    #S5 OK
	my $hash = shift;

	RemoveInternalTimer($hash);

	S7_disconnect($hash);

	delete( $modules{S7}{defptr} );

	return undef;
}


#####################################
sub S7_Set($@) {
	
	
}


#####################################
sub S7_Get($@) {    #S5 OK
	my ( $hash, @a ) = @_;
	return "Need at least one parameters" if ( @a < 2 );
	return "Unknown argument $a[1], choose one of "
	  . join( " ", sort keys %gets )
	  if ( !defined( $gets{ $a[1] } ) );
	my $name = shift @a;
	my $cmd  = shift @a;

  ARGUMENT_HANDLER: {
		$cmd eq "S7TCPClientVersion" and do {

			return $hash->{S7PLCClient}->version();
			last;
		};
		$cmd eq "PLCTime" and do {
			return $hash->{S7PLCClient}->getPLCDateTime();
			last;
		};
	}

}

#####################################
sub S7_Attr(@) {
	my ( $cmd, $name, $aName, $aVal ) = @_;

	my $hash = $defs{$name};

	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value

	if ( $cmd eq "set" ) {
		if ( $aName eq "MaxMessageLength" ) {

			if ( $aVal < $hash->{S7PLCClient}->{MaxReadLength} ) {

				$hash->{S7PLCClient}->{MaxReadLength} = $aVal;

				Log3( $name, 3, "$name S7_Attr: setting MaxReadLength= $aVal" );
			}
		} elsif ($aName eq "Intervall") {
			if ( $aVal >= 1 ) {

				$hash->{Interval} = $aVal;

				Log3( $name, 3, "$name S7_Attr: setting Intervall= $aVal" );
			}			
		} elsif ($aName eq "receiveTimeoutMs") {
			if ( $aVal > 100 &&  $aVal < 10000) {

				$hash->{receiveTimeoutMs} = $aVal;

				Log3( $name, 3, "$name S7_Attr: setting receiveTimeoutMs= $aVal" );
				
				#reconnect with the new receiving timeout

				$hash->{S7PLCClient}->setRecvTimeout($hash->{receiveTimeoutMs}) if ( defined( $hash->{S7PLCClient} ) );				
			}			
		
		} elsif ($aName eq "disable") {
			if ($aVal == 1 &&  $attr{$name}{disable}==0) {
				#disconnection will be done by the update timer

			} elsif ($aVal == 0 &&  $attr{$name}{disable}==1) {
				#reconnect 
				S7_reconnect($hash);
				InternalTimer( gettimeofday() + $hash->{Interval} + 3,
					"S7_GetUpdate", $hash, 0 );				
			}
		}
				
		###########

		if (   $aName eq "WriteInputs-Config"
			|| $aName eq "WriteOutputs-Config"
			|| $aName eq "WriteFlags-Config"
			|| $aName eq "WriteDB-Config" )
		{
			my $PDUlength = $hash->{maxPDUlength};

			my @a = split( "[ \t][ \t]*", $aVal );
			if ( int(@a) % 3 != 0 || int(@a) == 0 ) {
				Log3( $name, 3,
					"S7: Invalid $aName in attr $name $aName $aVal: $@" );
				return
"Invalid $aName $aVal \n Format: <DB> <STARTPOSITION> <LENGTH> [<DB> <STARTPOSITION> <LENGTH> ]";
			}
			else {

				for ( my $i = 0 ; $i < int(@a) ; $i++ ) {
					if ( $a[$i] ne int( $a[$i] ) ) {
						my $s = $a[$i];
						Log3( $name, 3,
"S7: Invalid $aName in attr $name $aName $aVal ($s is not a number): $@"
						);
						return "Invalid $aName $aVal: $s is not a number";
					}
					if ( $i % 3 == 0 && ( $a[$i] < 0 || $a[$i] > 1024 ) ) {
						Log3( $name, 3,
							"S7: Invalid $aName db. valid db 0 - 1024: $@" );
						return
						  "Invalid $aName length: $aVal db: valid db 0 - 1024";

					}
					if ( $i % 3 == 1 && ( $a[$i] < 0 || $a[$i] > 32768 ) ) {
						Log3( $name, 3,
"S7: Invalid $aName startposition. valid startposition 0 - 32768: $@"
						);
						return
"Invalid $aName startposition: $aVal db: valid startposition 0 - 32768";

					}
					if ( $i % 3 == 2
						&& ( $a[$i] < 1 || $a[$i] > $PDUlength ) )
					{
						Log3( $name, 3,
"S7: Invalid $aName length. valid length 1 - $PDUlength: $@"
						);
						return
"Invalid $aName lenght: $aVal: valid length 1 - $PDUlength";
					}

				}

				return undef if ( $hash->{STATE} ne "connected to PLC" );

				#we need to fill-up the internal buffer from current PLC values
				my $hash = $defs{$name};

				my $res =
				  S7_getAllWritingBuffersFromPLC( $hash, $aName, $aVal );
				if ( int($res) != 0 ) {

					#quit because of error
					return $res;
				}

			}
		}
	}
	return undef;
}

#####################################

sub S7_getAreaIndex4AreaName($) {    #S5 OK
	my ($aName) = @_;

	my $AreaIndex = -1;
	for ( my $j = 0 ; $j < int(@areaname) ; $j++ ) {
		if ( $aName eq $areasconfig[$j] || $aName eq $areaname[$j] ) {
			$AreaIndex = $j;
			last;
		}
	}
	if ( $AreaIndex < 0 ) {
		Log3( undef, 2, "S7_Attr: Internal error invalid WriteAreaIndex" );
		return "Internal error invalid WriteAreaIndex";
	}
	return $AreaIndex;

}

#####################################
sub S7_WriteToPLC($$$$$$) {
	my ( $hash, $areaIndex, $dbNr, $startByte, $WordLen, $dataBlock ) = @_;

	my $PDUlength = -1;
	if ( defined $hash->{maxPDUlength} ) {
		$PDUlength = $hash->{maxPDUlength};
	}
	my $name = $hash->{NAME};

	my $res          = -1;
	my $Bufferlength  = 59999; 
	$Bufferlength = length($dataBlock);

	if ( $Bufferlength <= $PDUlength ) {
		if ( $hash->{STATE} eq "connected to PLC" ) {

			my $bss = join( ", ", unpack( "H2" x $Bufferlength, $dataBlock ) );
			Log3( $name, 5,
"$name S7_WriteToPLC: Write Bytes to PLC: $areaIndex, $dbNr,$startByte , $Bufferlength, $bss"
			);

			eval {
				local $SIG{__DIE__} = sub {
					my ($s) = @_;
					print "DIE:$s";
					Log3( $hash, 0, "DIE:$s" );
					$res = -2;
				};

				if ( $hash->{S7TYPE} eq "S5" ) {
					$res = $hash->{S7PLCClient}->S5WriteS5Bytes(
						$s7areas[$areaIndex], $dbNr, $startByte, $Bufferlength,
						$dataBlock
					);
				}
				else {
					$res =
					  $hash->{S7PLCClient}
					  ->WriteArea( $s7areas[$areaIndex], $dbNr, $startByte,
						$Bufferlength, $WordLen, $dataBlock );
				}

			};
			if ( $res != 0 ) {
				my $error = $hash->{S7PLCClient}->getErrorStr($res);

				my $msg = "$name S7_WriteToPLC WriteArea error: $res=$error";
				Log3( $name, 3, $msg );

				S7_reconnect($hash);    #lets try a reconnect
				return ( -2, $msg );
			}
		}
		else {
			my $msg = "$name S7_WriteToPLC: PLC is not connected ";

			Log3( $name, 3, $msg );

			S7_reconnect($hash);        #lets try a reconnect

			return ( -2, $msg );
		}

	}
	else {
		my $msg =
"S7_WriteToPLC: wrong block length  $Bufferlength (max length $PDUlength)";
		Log3( $name, 3, $msg );
		return ( -1, $msg );
	}
}
#####################################
sub S7_WriteBitToPLC($$$$$) {
	my ( $hash, $areaIndex, $dbNr, $bitPosition, $bitValue ) = @_;

	my $PDUlength = -1;
	if ( defined $hash->{maxPDUlength} ) {
		$PDUlength = $hash->{maxPDUlength};
	}
	my $name = $hash->{NAME};

	my $res          = -1;
	my $Bufferlength = 1;

	if ( $Bufferlength <= $PDUlength ) {
		if ( $hash->{STATE} eq "connected to PLC" ) {

			my $bss = join( ", ", unpack( "H2" x $Bufferlength, $bitValue ) );
			Log3( $name, 5,
"$name S7_WriteBitToPLC: Write Bytes to PLC: $areaIndex, $dbNr, $bitPosition , $Bufferlength, $bitValue"
			);

			eval {
				local $SIG{__DIE__} = sub {
					my ($s) = @_;
					print "DIE:$s";
					Log3 $hash, 0, "DIE:$s";
					$res = -2;
				};

				if ( $hash->{S7TYPE} eq "S5" ) {

					#todo fix S5 Handling
				}
				else {
					$res =
					  $hash->{S7PLCClient}
					  ->WriteArea( $s7areas[$areaIndex], $dbNr, $bitPosition,
						$Bufferlength, &S7Client::S7WLBit, chr($bitValue) );
				}
			};
			if ( $res != 0 ) {
				my $error = $hash->{S7PLCClient}->getErrorStr($res);

				my $msg = "$name S7_WriteBitToPLC WriteArea error: $res=$error";
				Log3 $name, 3, $msg;

				S7_reconnect($hash);    #lets try a reconnect
				return ( -2, $msg );
			}
		}
		else {
			my $msg = "$name S7_WriteBitToPLC: PLC is not connected ";
			Log3 $name, 3, $msg;
			return ( -1, $msg );
		}

	}
	else {
		my $msg =
"S7_WriteBitToPLC: wrong block length  $Bufferlength (max length $PDUlength)";
		Log3 $name, 3, $msg;
		return ( -1, $msg );
	}
}

#####################################
#sub S7_WriteBlockToPLC($$$$$) {
#	my ( $hash, $areaIndex, $dbNr, $startByte, $dataBlock ) = @_;
#
#
#	return S7_WriteToPLC($hash, $areaIndex, $dbNr, $startByte, &S7Client::S7WLByte, $dataBlock);
#
#}
#####################################

sub S7_ReadBlockFromPLC($$$$$) {
	my ( $hash, $areaIndex, $dbNr, $startByte, $requestedLength ) = @_;

	my $PDUlength = -1;
	if ( defined $hash->{maxPDUlength} ) {
		$PDUlength = $hash->{maxPDUlength};
	}
	my $name       = $hash->{NAME};
	my $readbuffer = "";
	my $res        = -1;

	if ( $requestedLength <= $PDUlength ) {
		if ( $hash->{STATE} eq "connected to PLC" ) {

			eval {
				local $SIG{__DIE__} = sub {
					my ($s) = @_;
					print "DIE:$s";
					Log3 $hash, 0, "DIE:$s";
					$res = -2;
				};

				if ( $hash->{S7TYPE} eq "S5" ) {
					( $res, $readbuffer ) =
					  $hash->{S7PLCClient}
					  ->S5ReadS5Bytes( $s7areas[$areaIndex], $dbNr, $startByte,
						$requestedLength );
				}
				else {
					( $res, $readbuffer ) =
					  $hash->{S7PLCClient}
					  ->ReadArea( $s7areas[$areaIndex], $dbNr, $startByte,
						$requestedLength, &S7Client::S7WLByte );
				}
			};

			if ( $res != 0 ) {

				my $error = $hash->{S7PLCClient}->getErrorStr($res);
				my $msg =
				  "$name S7_ReadBlockFromPLC ReadArea error: $res=$error";
				Log3( $name, 3, $msg );

				S7_reconnect($hash);    #lets try a reconnect
				return ( -2, $msg );
			}
			else {

				#reading was OK
				return ( 0, $readbuffer );
			}
		}
		else {
			my $msg = "$name S7_ReadBlockFromPLC: PLC is not connected ";
			Log3( $name, 3, $msg );
			return ( -1, $msg );

		}
	}
	else {
		my $msg =
"$name S7_ReadBlockFromPLC: wrong block length (max length $PDUlength)";
		Log3( $name, 3, $msg );
		return ( -1, $msg );
	}
}

#####################################

sub S7_setBitInBuffer($$$) {    #S5 OK
	my ( $bitPosition, $buffer, $newValue ) = @_;

	my $Bufferlength = ( length($buffer) + 1 ) / 3;
	my $bytePosition = int( $bitPosition / 8 );

#	Log3 undef, 3, "S7_setBitInBuffer in: ".length($buffer)." , $Bufferlength , $bytePosition , $bitPosition";

	if ( $bytePosition < 0 || $bytePosition > $Bufferlength - 1 ) {

		#out off buffer request !!!!!
		#		Log3 undef, 3, "S7_setBitInBuffer out -1 : ".length($buffer);

		return ( -1, undef );
	}

	my @Writebuffer = unpack( "C" x $Bufferlength,
		pack( "H2" x $Bufferlength, split( ",", $buffer ) ) );

	my $intrestingBit = $bitPosition % 8;

	if ( $newValue eq "on" || $newValue eq "trigger" ) {
		$Writebuffer[$bytePosition] |= ( 1 << $intrestingBit );
	}
	else {
		$Writebuffer[$bytePosition] &= ( ( ~( 1 << $intrestingBit ) ) & 0xff );
	}

	my $resultBuffer = join(
		",",
		unpack(
			"H2" x $Bufferlength,
			pack( "C" x $Bufferlength, @Writebuffer )
		)
	);

	$Bufferlength = length($resultBuffer);

	#	Log3 undef, 3, "S7_setBitInBuffer out: $Bufferlength";

	return ( 0, $resultBuffer );
}

#####################################
sub S7_getBitFromBuffer($$) {    #S5 OK
	my ( $bitPosition, $buffer ) = @_;

	my $Bufferlength = ( length($buffer) * 3 ) - 1;
	my $bytePosition = int( $bitPosition / 8 );
	if ( $bytePosition < 0 || $bytePosition > length($Bufferlength) ) {

		#out off buffer request !!!!!
		return "unknown";
	}
	my @Writebuffer = unpack( "C" x $Bufferlength,
		pack( "H2" x $Bufferlength, split( ",", $buffer ) ) );

	my $intrestingByte = $Writebuffer[$bytePosition];
	my $intrestingBit  = $bitPosition % 8;

	if ( ( $intrestingByte & ( 1 << $intrestingBit ) ) != 0 ) {

		return "on";
	}
	else {
		return "off";
	}

}

#####################################
sub S7_getAllWritingBuffersFromPLC($$$) {    #S5 OK

	#$hash ... from S7 physical modul
	#$writerConfig ... writer Config
	#$aName ... area name

	my ( $hash, $aName, $writerConfig ) = @_;

	Log3( $aName, 4, "S7: getAllWritingBuffersFromPLC called" );

	my @a = split( "[ \t][ \t]*", $writerConfig );

	my $PDUlength = $hash->{maxPDUlength};

	my @writingBuffers = ();
	my $readbuffer;

	my $writeAreaIndex = S7_getAreaIndex4AreaName($aName);
	return $writeAreaIndex if ( $writeAreaIndex ne int($writeAreaIndex) );

	my $nr = int(@a);

	#	Log3 undef, 4, "S7: getAllWritingBuffersFromPLC $nr";

	my $res;
	for ( my $i = 0 ; $i < int(@a) ; $i = $i + 3 ) {
		my $readbuffer;
		my $res;

		my $dbnr            = $a[$i];
		my $startByte       = $a[ $i + 1 ];
		my $requestedLength = $a[ $i + 2 ];

		( $res, $readbuffer ) =
		  S7_ReadBlockFromPLC( $hash, $writeAreaIndex, $dbnr, $startByte,
			$requestedLength );
		if ( $res == 0 ) {    #reading was OK
			my $hexbuffer =
			  join( ",", unpack( "H2" x length($readbuffer), $readbuffer ) );
			push( @writingBuffers, $hexbuffer );
		}
		else {

			#error in reading so just return the error MSG
			return $readbuffer;
		}
	}

	if ( int(@writingBuffers) > 0 ) {
		$hash->{"${areaname[$writeAreaIndex]}_DBWRITEBUFFER"} =
		  join( " ", @writingBuffers );
	}
	else {
		$hash->{"${areaname[$writeAreaIndex]}_DBWRITEBUFFER"} = undef;
	}
	return 0;
}

#####################################
sub S7_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3( $name, 4, "S7: $name GetUpdate called ..." );

	my $res = S7_readFromPLC($hash);

	if (!S7_isDisabled($hash)) {
		if ( $res == 0 ) {
			InternalTimer( gettimeofday() + $hash->{Interval},
				"S7_GetUpdate", $hash, 1 );
		}else {

			#an error has occoured --> 10sec break
			InternalTimer( gettimeofday() + 10, "S7_GetUpdate", $hash, 1 );
		}
	} else {
		S7_disconnect($hash);
	}
}

#####################################
sub S7_dispatchMsg($$$$$$$$) {
	my ( $hash, $msgprefix, $areaIndex, $dbNr, $startByte, $hexbuffer, $length,
		$clientsNames )
	  = @_;

	my $name = $hash->{NAME};
	my $dmsg =
	    $msgprefix . " "
	  . $areaname[$areaIndex] . " "
	  . $dbNr . " "
	  . $startByte . " "
	  . $length . " "
	  . $name . " "
	  . $hexbuffer . " "
	  . $clientsNames;

	Log3( $name, 5, $name . " S7_dispatchMsg " . $dmsg );

	Dispatch( $hash, $dmsg, {} );

}
#####################################
sub S7_readAndDispatchBlockFromPLC($$$$$$$$$$) {    #S5 OK
	my (
		$hash,              $area,             $dbnr,
		$blockstartpos,     $blocklength,      $hasAnalogReading,
		$hasDigitalReading, $hasAnalogWriting, $hasDigitalWriting,
		$clientsNames
	) = @_;

	my $name      = $hash->{NAME};
	my $state     = $hash->{STATE};
	my $areaIndex = S7_getAreaIndex4AreaName($area);

	Log3( $name, 4,
		    $name
		  . " READ Block AREA="
		  . $area . " ("
		  . $areaIndex
		  . "), DB ="
		  . $dbnr
		  . ", ADDRESS="
		  . $blockstartpos
		  . ", LENGTH="
		  . $blocklength );

	if ( $state ne "connected to PLC" ) {
		Log3 $name, 3, "$name is disconnected ? --> reconnect";
		S7_reconnect($hash);    #lets try a reconnect
		    #@nextreadings[ $i / 4 ] = $now + 10;    #retry in 10s
		return -2;
	}

	my $res;
	my $readbuffer;

	( $res, $readbuffer ) =
	  S7_ReadBlockFromPLC( $hash, $areaIndex, $dbnr, $blockstartpos,
		$blocklength );

	if ( $res == 0 ) {

		#reading was OK
		my $length = length($readbuffer);
		my $hexbuffer = join( ",", unpack( "H2" x $length, $readbuffer ) );

		#dispatch to reader
		S7_dispatchMsg( $hash, "AR", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer, $length, $clientsNames )
		  if ( $hasAnalogReading > 0 );
		S7_dispatchMsg( $hash, "DR", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer, $length, $clientsNames )
		  if ( $hasDigitalReading > 0 );

		#dispatch to writer
		S7_dispatchMsg( $hash, "AW", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer, $length, $clientsNames )
		  if ( $hasAnalogWriting > 0 );
		S7_dispatchMsg( $hash, "DW", $areaIndex, $dbnr, $blockstartpos,
			$hexbuffer, $length, $clientsNames )
		  if ( $hasDigitalWriting > 0 );
		return 0;
	}
	else {

		#reading failed
		return -1;
	}

}
#####################################
sub S7_getReadingsList($) {    #S5 OK
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my @readings;

	# Jetzt suchen wir alle Readings
	my @mykeys;
	my %logoClients;

	@mykeys =
	  grep $defs{$_}{TYPE} =~ /^S7_/ && $defs{$_}{IODev}{NAME} eq $hash->{NAME},
	  keys(%defs);
	@logoClients{@mykeys} =
	  @defs{@mykeys};    #jetzt haben wir alle clients in logoClients

	#we need to find out the unique areas
	my %tmphash = map { $logoClients{$_}{AREA} => 1 } keys %logoClients;
	my @uniqueArea = keys %tmphash;

	foreach my $Area (@uniqueArea) {
		my %logoClientsArea;
		@mykeys =
		     grep $defs{$_}{TYPE} =~ /^S7_/
		  && $defs{$_}{IODev}{NAME} eq $hash->{NAME}
		  && $defs{$_}{AREA} eq $Area, keys(%defs);
		@logoClientsArea{@mykeys} = @defs{@mykeys};

		#now we findout which DBs are used (unique)
		%tmphash = map { $logoClientsArea{$_}{DB} => 1 } keys %logoClientsArea;
		my @uniqueDB = keys %tmphash;

		foreach my $DBNr (@uniqueDB) {

			#now we filter all readinfy by DB!
			my %logoClientsDB;

			@mykeys =
			     grep $defs{$_}{TYPE} =~ /^S7_/
			  && $defs{$_}{IODev}{NAME} eq $hash->{NAME}
			  && $defs{$_}{AREA} eq $Area
			  && $defs{$_}{DB} == $DBNr, keys(%defs);
			@logoClientsDB{@mykeys} = @defs{@mykeys};

			#next step is, sorting all clients by ADDRESS
			my @positioned = sort {
				$logoClientsDB{$a}{ADDRESS} <=> $logoClientsDB{$b}{ADDRESS}
			} keys %logoClientsDB;

			my $blockstartpos = -1;
			my $blocklength   = 0;

			my $hasAnalogReading  = 0;
			my $hasDigitalReading = 0;
			my $hasAnalogWriting  = 0;
			my $hasDigitalWriting = 0;
			my $clientsName       = "";

			for ( my $i = 0 ; $i < int(@positioned) ; $i++ ) {
				if ( $blockstartpos < 0 ) {

					#we start a new block
					$blockstartpos =
					  int( $logoClientsDB{ $positioned[$i] }{ADDRESS} );
					$blocklength = $logoClientsDB{ $positioned[$i] }{LENGTH};

					$hasAnalogReading++
					  if (
						$logoClientsDB{ $positioned[$i] }{TYPE} eq "S7_ARead" );
					$hasDigitalReading++
					  if (
						$logoClientsDB{ $positioned[$i] }{TYPE} eq "S7_DRead" );
					$hasAnalogWriting++
					  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
						"S7_AWrite" );
					$hasDigitalWriting++
					  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
						"S7_DWrite" );

					$clientsName = $logoClientsDB{ $positioned[$i] }{NAME};

				}
				else {

					if ( $logoClientsDB{ $positioned[$i] }{ADDRESS} +
						$logoClientsDB{ $positioned[$i] }{LENGTH} -
						$blockstartpos <=
						$hash->{S7PLCClient}->{MaxReadLength} )
					{

						#extend existing block
						if (
							int( $logoClientsDB{ $positioned[$i] }{ADDRESS} ) +
							$logoClientsDB{ $positioned[$i] }{LENGTH} -
							$blockstartpos > $blocklength )
						{
							$blocklength =
							  int( $logoClientsDB{ $positioned[$i] }{ADDRESS} )
							  + $logoClientsDB{ $positioned[$i] }{LENGTH} -
							  $blockstartpos;

							$hasAnalogReading++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_ARead" );
							$hasDigitalReading++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_DRead" );
							$hasAnalogWriting++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_AWrite" );
							$hasDigitalWriting++
							  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
								"S7_DWrite" );

						}
						$clientsName .=
						  "," . $logoClientsDB{ $positioned[$i] }{NAME};
					}
					else {

						#block would exeed MaxReadLength

						#read and dispatch block from PLC
						#block in liste speichern
						push(
							@readings,
							[
								$logoClientsDB{ $positioned[$i] }{AREA},
								$logoClientsDB{ $positioned[$i] }{DB},
								$blockstartpos,
								$blocklength,
								$hasAnalogReading,
								$hasDigitalReading,
								$hasAnalogWriting,
								$hasDigitalWriting,
								$clientsName
							]
						);

						$hasAnalogReading  = 0;
						$hasDigitalReading = 0;
						$hasAnalogWriting  = 0;
						$hasDigitalWriting = 0;

						#start new block new time
						$blockstartpos =
						  int( $logoClientsDB{ $positioned[$i] }{ADDRESS} );
						$blocklength =
						  $logoClientsDB{ $positioned[$i] }{LENGTH};

						$hasAnalogReading++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_ARead" );
						$hasDigitalReading++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_DRead" );
						$hasAnalogWriting++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_AWrite" );
						$hasDigitalWriting++
						  if ( $logoClientsDB{ $positioned[$i] }{TYPE} eq
							"S7_DWrite" );

						$clientsName = $logoClientsDB{ $positioned[$i] }{NAME};
					}

				}

			}
			if ( $blockstartpos >= 0 ) {

				#read and dispatch block from PLC

				push(
					@readings,
					[
						$logoClientsDB{ $positioned[ int(@positioned) - 1 ] }
						  {AREA},
						$logoClientsDB{ $positioned[ int(@positioned) - 1 ] }
						  {DB},
						$blockstartpos,
						$blocklength,
						$hasAnalogReading,
						$hasDigitalReading,
						$hasAnalogWriting,
						$hasDigitalWriting,
						$clientsName
					]
				);

			}
		}
	}
	@{ $hash->{ReadingList} } = @readings;
	return 0;

}

#####################################
sub S7_readFromPLC($) {    #S5 OK
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $res;

	if ( ( !defined( $hash->{dirty} ) ) || $hash->{dirty} == 1 ) {
		S7_getReadingsList($hash);
		$hash->{dirty} = 0;
	}

	my @readingList = @{ $hash->{ReadingList} };

	for ( my $i = 0 ; $i < int(@readingList) ; $i++ ) {
		my @readingSet = @{ $readingList[$i] };
		$res = S7_readAndDispatchBlockFromPLC(
			$hash,          $readingSet[0], $readingSet[1], $readingSet[2],
			$readingSet[3], $readingSet[4], $readingSet[5], $readingSet[6],
			$readingSet[7], $readingSet[8]
		);

		return $res if ( $res != 0 );
	}
	return 0;
}

sub S7_isDisabled($) {
    my ($hash) = @_;
    my $name = $hash->{NAME};
	
    return $attr{$name}{disable} == 1 if (defined ($attr{$name}{disable}));
	return 0;
}

1;


=pod
=item summary basic interface to a SIEMENS S7 / S5
=item summary_DE Schnittstelle zu einer Siemens S7 / S5
=begin html

<p><a name="S7"></a></p>
<h3>S7</h3>
<ul>
<ul>
<ul>This module connects a SIEMENS PLC (S7,S5,SIEMENS Logo!). The TCP communication (S7, Siemens LOGO!) module is based on settimino (http://settimino.sourceforge.net). The serial Communication is based on a libnodave portation.</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>You can found a german wiki here: httl://www.fhemwiki.de/wiki/S7</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>For the communication the following modules have been implemented:
<ul>
<li>S7 &hellip; sets up the communication channel to the PLC</li>
<li>S7_ARead &hellip; Is used for reading integer Values from the PLC</li>
<li>S7_AWrite &hellip; Is used for write integer Values to the PLC</li>
<li>S7_DRead &hellip; Is used for read bits</li>
<li>S7_DWrite &hellip; Is used for writing bits.</li>
</ul>
</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>Reading work flow:</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>The S7 module reads periodically the configured DB areas from the PLC and stores the data in an internal buffer. Then all reading client modules are informed. Each client module extracts his data and the corresponding readings are set. Writing work flow:</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>At the S7 module you need to configure the PLC writing target. Also the S7 module holds a writing buffer. Which contains a master copy of the data needs to send.</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>(Note: after configuration of the writing area a copy from the PLC is read and used as initial fill-up of the writing buffer)</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>Note: The S7 module will send always the whole data block to the PLC. When data on the clients modules is set then the client module updates the internal writing buffer on the S7 module and triggers the writing to the PLC.</ul>
</ul>
<p><br /><br /><a name="S7define"></a><strong>Define</strong><code>define &lt;name&gt; S7 &lt;PLC_address&gt; &lt;rack&gt; &lt;slot&gt; [&lt;Interval&gt;] </code><br /><br /><code>define logo S7 10.0.0.241 2 0 </code></p>
<ul>
<ul>
<ul>
<ul>
<li>PLC_address &hellip; IP address of the S7 PLC (For S5 see below)</li>
<li>rack &hellip; rack of the PLC</li>
<li>slot &hellip; slot of the PLC</li>
<li>Interval &hellip; Intervall how often the modul should check if a reading is required</li>
</ul>
</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>Note: For Siemens logo you should use a alternative (more simply configuration method):</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul><code>define logo S7 LOGO7 10.0.0.241</code></ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>Note: For Siemens S5 you must use a alternative (more simply configuration method):</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>define logo S7 S5 /dev/tty1 in this case the PLC_address is the serial port number</ul>
</ul>
</ul>
<p><br /><br /><strong>Attr</strong></p>
<ul>
<ul>The following attributes are supported:</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>
<li>MaxMessageLength</li>
<li>receiveTimeoutMs</li>
<li>Intervall</li>
</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>MaxMessageLength ... restricts the packet length if lower than the negioated PDULength. This could be used to increate the processing speed. 2 small packages may be smaler than one large package</ul>
<ul>receiveTimeoutMs ... timeout in ms for TCP receiving packages. Default Value 500ms.&nbsp;</ul>
<ul>Intervall ... polling&nbsp;intervall in s&nbsp;</ul>
</ul>

=end html

=begin html_DE


<p><a name="S7"></a></p>
<h3>S7</h3>
<ul>
<ul>
<ul>This module connects a SIEMENS PLC (S7,S5,SIEMENS Logo!). The TCP communication (S7, Siemens LOGO!) module is based on settimino (http://settimino.sourceforge.net). The serial Communication is based on a libnodave portation.</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>You can found a german wiki here: httl://www.fhemwiki.de/wiki/S7</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>For the communication the following modules have been implemented:
<ul>
<li>S7 &hellip; sets up the communication channel to the PLC</li>
<li>S7_ARead &hellip; Is used for reading integer Values from the PLC</li>
<li>S7_AWrite &hellip; Is used for write integer Values to the PLC</li>
<li>S7_DRead &hellip; Is used for read bits</li>
<li>S7_DWrite &hellip; Is used for writing bits.</li>
</ul>
</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>Reading work flow:</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>The S7 module reads periodically the configured DB areas from the PLC and stores the data in an internal buffer. Then all reading client modules are informed. Each client module extracts his data and the corresponding readings are set. Writing work flow:</ul>
</ul>
<p><br /><br /></p>
<ul>
<ul>At the S7 module you need to configure the PLC writing target. Also the S7 module holds a writing buffer. Which contains a master copy of the data needs to send.</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>(Note: after configuration of the writing area a copy from the PLC is read and used as initial fill-up of the writing buffer)</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>Note: The S7 module will send always the whole data block to the PLC. When data on the clients modules is set then the client module updates the internal writing buffer on the S7 module and triggers the writing to the PLC.</ul>
</ul>
<p><br /><br /><a name="S7define"></a><strong>Define</strong><code>define &lt;name&gt; S7 &lt;PLC_address&gt; &lt;rack&gt; &lt;slot&gt; [&lt;Interval&gt;] </code><br /><br /><code>define logo S7 10.0.0.241 2 0 </code></p>
<ul>
<ul>
<ul>
<ul>
<li>PLC_address &hellip; IP address of the S7 PLC (For S5 see below)</li>
<li>rack &hellip; rack of the PLC</li>
<li>slot &hellip; slot of the PLC</li>
<li>Interval &hellip; Intervall how often the modul should check if a reading is required</li>
</ul>
</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>Note: For Siemens logo you should use a alternative (more simply configuration method):</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul><code>define logo S7 LOGO7 10.0.0.241</code></ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>Note: For Siemens S5 you must use a alternative (more simply configuration method):</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>define logo S7 S5 /dev/tty1 in this case the PLC_address is the serial port number</ul>
</ul>
</ul>
<p><br /><br /><strong>Attr</strong></p>
<ul>
<ul>The following attributes are supported:</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>
<ul>
<li>MaxMessageLength</li>
<li>receiveTimeoutMs</li>
<li>Intervall</li>
</ul>
</ul>
</ul>
<p>&nbsp;</p>
<ul>
<ul>MaxMessageLength ... restricts the packet length if lower than the negioated PDULength. This could be used to increate the processing speed. 2 small packages may be smaler than one large package</ul>
<ul>receiveTimeoutMs ... timeout in ms for TCP receiving packages. Default Value 500ms.&nbsp;</ul>
<ul>Intervall ... polling&nbsp;intervall in s&nbsp;</ul>
</ul>
=end html_DE

=cut

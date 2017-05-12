# $Id$
##############################################

use strict;
use warnings;
require Exporter;
use Config;
use AutoLoader;

#todo fix timeout in ms

our @ISA = qw(Exporter);
our %EXPORT_TAGS = (
	'all' => [
		qw(
		  S7AreaPE
		  S7AreaPA
		  S7AreaMK
		  S7AreaDB
		  S7AreaCT
		  S7AreaTM
		  )
	]
);

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
  S7AreaPE
  S7AreaPA
  S7AreaMK
  S7AreaDB
  S7AreaCT
  S7AreaTM
);


#Base class for S7 and S5 Connections
package S7ClientBase;

# S7 ID Area (Area that we want to read/write)
use constant S7AreaPE => 0x81;
use constant S7AreaPA => 0x82;
use constant S7AreaMK => 0x83;
use constant S7AreaDB => 0x84;
use constant S7AreaCT => 0x1C;
use constant S7AreaTM => 0x1D;


sub new {
	my $class = shift;
	my $self  = {

		Connected     => 0,        # = false
		PDULength     => 0,
		MaxReadLength => 0,
		RecvTimeout   => 500,      # 500 ms
	};

	return bless $self, $class;
}

#-----------------------------------------------------------------------------
sub DESTROY {
	my $self = shift;
	$self->Disconnect();
}


#-----------------------------------------------------------------------------

sub Connect {
	my ($self) = @_;
	return 0;
}

#-----------------------------------------------------------------------------
sub Disconnect {
	my ($self) = @_;
	if ( $self->{Connected} ) {

		$self->{Connected}     = 0;
		$self->{PDULength}     = 0;
		$self->{MaxReadLength} = 0;
		$self->{LastError}     = 0;
	}
}


#-----------------------------------------------------------------------------
sub ReadArea () {
}

#-----------------------------------------------------------------------------

sub WriteArea {
}

#-----------------------------------------------------------------------------
sub getPLCDateTime() {
}

#-----------------------------------------------------------------------------
sub BitAt {

	my ( $self, $Buffer, $ByteIndex, $BitIndex ) = @_;

	return 0 if ( $BitIndex > 7 );

	my @mask = ( 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80 );

	my @myBuffer = unpack( "C" x $ByteIndex + 1, $Buffer );

	return 1 if ( ( $myBuffer[$ByteIndex] & $mask[$BitIndex] ) != 0 );
	return 0;

}

#-----------------------------------------------------------------------------

sub ByteAt {
	my @myBuffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index    = $_[2];

	return $myBuffer[$index];
}

#-----------------------------------------------------------------------------
sub WordAt {

	my @myBuffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index    = $_[2];

	my $hi = $myBuffer[$index] << 8;

	return ( $hi + $myBuffer[ $index + 1 ] );
}

#-----------------------------------------------------------------------------

sub DWordAt {
	my @myBuffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index    = $_[2];

	my $dw1;

	$dw1 = $myBuffer[$index] << 8;

	$dw1 = ( $dw1 + $myBuffer[ $index + 1 ] ) << 8;

	$dw1 = ( $dw1 + $myBuffer[ $index + 2 ] ) << 8;

	$dw1 = ( $dw1 + $myBuffer[ $index + 3 ] );

	return $dw1;
}

#-----------------------------------------------------------------------------
sub FloatAt {
	my @myBuffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index    = $_[2];

	my @bytes = (
		$myBuffer[$index],
		$myBuffer[ $index + 1 ],
		$myBuffer[ $index + 2 ],
		$myBuffer[ $index + 3 ]
	);

	if ( $Config::Config{byteorder} =~ /^1/ )
	{                             #take care of the machines byte order
		return unpack( 'f', pack( 'C4', reverse @bytes ) );
	}
	return unpack( 'f', pack( 'C4', @bytes ) );
}

#-----------------------------------------------------------------------------
sub ShortAt {
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };      # ersten Parameter dereferenzieren
	my $index  = $_[2];

	#	my ( $self, $Buffer, $index ) = @_;

	my $b = $self->ByteAt( \@Buffer, $index );

	if ( ( $b & 0x80 ) != 0 ) {

		return -( ( ~$b & 0xff ) + 1 );
	}
	return $b;
}

#-----------------------------------------------------------------------------

sub IntegerAt {
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];

	#	my ( $self, $Buffer, $index ) = @_;
	#	my $w = $self->WordAt( $Buffer, $index );

	my $w = $self->WordAt( \@Buffer, $index );

	return ( $w & 0x8000 ) ? -( ( ( ~$w ) & 0xffff ) + 1 ) : $w;

}

#-----------------------------------------------------------------------------
sub DintAt {
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];

	my $dw = $self->DWordAt( \@Buffer, $index );

	#	my ( $self, $Buffer, $index ) = @_;

	#	my $dw = $self->DWordAt( $Buffer, $index );

	return ( $dw & 0x80000000 ) ? -( ( ~$dw & 0xffffffff ) + 1 ) : $dw;
}

#-----------------------------------------------------------------------------
sub GetU8from {
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->ByteAt( \@Buffer, $index );

	#	my ( $self, $Buffer, $index ) = @_;
	#	return $self->ByteAt( $Buffer, $index );
}

#-----------------------------------------------------------------------------

sub GetS8from {

	#	my ( $self, $Buffer, $index ) = @_;
	#	return ShortAt( $Buffer, $index );
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->ShortAt( \@Buffer, $index );
}

#-----------------------------------------------------------------------------
sub GetU16from {

	#	my ( $self, $Buffer, $index ) = @_;
	#	return $self->WordAt( $Buffer, $index );
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->WordAt( \@Buffer, $index );
}

#-----------------------------------------------------------------------------

sub GetS16from {

	#	my ( $self, $Buffer, $index ) = @_;
	#	return $self->IntegerAt( $Buffer, $index );
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->IntegerAt( \@Buffer, $index );
}

#-----------------------------------------------------------------------------

sub GetU32from {

	#	my ( $self, $Buffer, $index ) = @_;
	#	return $self->DWordAt( $Buffer, $index );
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->DWordAt( \@Buffer, $index );

}

#-----------------------------------------------------------------------------
sub GetS32from {

	#	my ( $self, $Buffer, $index ) = @_;
	#	return $self->DintAt( $Buffer, $index );
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->DintAt( \@Buffer, $index );

}

#-----------------------------------------------------------------------------

sub GetFloatfrom {

	#	my ( $self, $Buffer, $index ) = @_;
	#	return $self->FloatAt( $Buffer, $index );
	my $self   = $_[0];
	my @Buffer = @{ $_[1] };    # ersten Parameter dereferenzieren
	my $index  = $_[2];
	return $self->FloatAt( \@Buffer, $index );

}

#-----------------------------------------------------------------------------

sub setByteAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	my @myBuffer = unpack( "C" x length($Buffer), $Buffer );

	$myBuffer[$index] = $value % 256;

	return pack( "C" x length($Buffer), @myBuffer );
}

#-----------------------------------------------------------------------------
sub setWordAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	my @myBuffer = unpack( "C" x length($Buffer), $Buffer );

	$myBuffer[$index] = $value >> 8;
	$myBuffer[ $index + 1 ] = $value % 256;

	return pack( "C" x length($Buffer), @myBuffer );
}

#-----------------------------------------------------------------------------

sub setDWordAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	my @myBuffer = unpack( "C" x length($Buffer), $Buffer );

	$myBuffer[ $index + 3 ] = $value % 256;
	$value                  = $value >> 8;
	$myBuffer[ $index + 2 ] = $value % 256;
	$value                  = $value >> 8;
	$myBuffer[ $index + 1 ] = $value % 256;
	$value                  = $value >> 8;
	$myBuffer[$index]       = $value % 256;

	return pack( "C" x length($Buffer), @myBuffer );
}

#-----------------------------------------------------------------------------
sub setFloatAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	my @myBuffer = unpack( "C" x length($Buffer), $Buffer );

	my @bytes = unpack( 'C4', pack( 'f', $value ) );
	if ( $Config::Config{byteorder} =~ /^1/ )
	{    #take care of the machines byte order
		$myBuffer[$index]       = $bytes[3];
		$myBuffer[ $index + 1 ] = $bytes[2];
		$myBuffer[ $index + 2 ] = $bytes[1];
		$myBuffer[ $index + 3 ] = $bytes[0];
	}
	else {
		$myBuffer[$index]       = $bytes[0];
		$myBuffer[ $index + 1 ] = $bytes[1];
		$myBuffer[ $index + 2 ] = $bytes[2];
		$myBuffer[ $index + 3 ] = $bytes[3];
	}

	return pack( "C" x length($Buffer), @myBuffer );

}

#-----------------------------------------------------------------------------
sub setShortAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	$value = ( ( ~( -$value ) ) & 0xff ) + 1 if ( $value < 0 );
	return $self->setByteAt( $Buffer, $index, $value );
}

#-----------------------------------------------------------------------------

sub setIntegerAt {

	my ( $self, $Buffer, $index, $value ) = @_;
	$value = ( ( ~( -$value ) ) & 0xffff ) + 1 if ( $value < 0 );
	return $self->setWordAt( $Buffer, $index, $value );

}

#-----------------------------------------------------------------------------
sub setDintAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	$value = ( ( ~( -$value ) ) & 0xffffffff ) + 1 if ( $value < 0 );
	return $self->setDWordAt( $Buffer, $index, $value );
}

#-----------------------------------------------------------------------------

sub Put8At {
	my ( $self, $Buffer, $index, $value ) = @_;
	return $self->setByteAt( $Buffer, $index, $value );
}

#-----------------------------------------------------------------------------
sub Put16At {
	my ( $self, $Buffer, $index, $value ) = @_;
	return $self->setIntegerAt( $Buffer, $index, $value );
}

#-----------------------------------------------------------------------------
sub Put32At {
	my ( $self, $Buffer, $index, $value ) = @_;
	return $self->setDintAt( $Buffer, $index, $value );
}

#-----------------------------------------------------------------------------

sub PutFloatAt {
	my ( $self, $Buffer, $index, $value ) = @_;
	return $self->setFloatAt( $Buffer, $index, $value );
}


#-----------------------------------------------------------------------------
sub setRecvTimeout {

	my ( $self, $newRecvTimeout ) = @_;
	
	$self->{RecvTimeout} = $newRecvTimeout;
}
#-----------------------------------------------------------------------------

sub version {
	return "1.1";
}

#-----------------------------------------------------------------------------



sub getErrorStr {

}

1;

=pod
=item summary abstract interface layer S7 / S5
=item summary_DE abstract interface layer S7 / S5
=begin html

<p><a name="S7_Client"></a></p>
<h3>S7_Client</h3>
<ul>
<ul>abstract interface layer S7 / S5</ul>
</ul>
=end html
=begin html_DE

<p><a name="S7_Client"></a></p>
<h3>S7_Client</h3>
<ul>
<ul>abstract interface layer S7 / S5</ul>
</ul>
=end html_DE

=cut

package Device::Firmata::IO::SerialIO;

=head1 NAME

Device::Firmata::IO::SerialIO - implement the low level serial IO

=cut

use strict;
use warnings;

use vars qw/ $SERIAL_CLASS /;
use Device::Firmata::Base
    ISA => 'Device::Firmata::Base',
    FIRMATA_ATTRIBS => {
        handle   => undef,
        baudrate => 57600,
    };

$SERIAL_CLASS = $^O eq 'MSWin32' ? 'Win32::SerialPort'
                                 : 'Device::SerialPort';
eval "require $SERIAL_CLASS";


=head2 open

=cut

sub open {
# --------------------------------------------------
  my ( $pkg, $serial_port, $opts ) = @_;
  my $self = ref $pkg ? $pkg : $pkg->new($opts);
  my $serial_obj = $SERIAL_CLASS->new( $serial_port, 1, 0 ) or return;
  $self->attach($serial_obj,$opts);
  $self->{handle}->baudrate($self->{baudrate});
  $self->{handle}->databits(8);
  $self->{handle}->stopbits(1);
  return $self;
}

sub attach {
  my ( $pkg, $serial_obj, $opts ) = @_;
  my $self = ref $pkg ? $pkg : $pkg->new($opts);
  $self->{handle} = $serial_obj;
  return $self;
}

=head2 data_write

Dump a bunch of data into the comm port

=cut

sub data_write {
# --------------------------------------------------
  my ( $self, $buf ) = @_;
  $Device::Firmata::DEBUG and print ">".join(",",map{sprintf"%02x",ord$_}split//,$buf)."\n";
  return $self->{handle}->write( $buf );
}


=head2 data_read

We fetch up to $bytes from the comm port
This function is non-blocking

=cut

sub data_read {
# --------------------------------------------------
  my ( $self, $bytes ) = @_;
  my ( $count, $string ) = $self->{handle}->read($bytes);
  print "<".join(",",map{sprintf"%02x",ord$_}split//,$string)."\n" if ( $Device::Firmata::DEBUG and $string );
  return $string;
}

1;

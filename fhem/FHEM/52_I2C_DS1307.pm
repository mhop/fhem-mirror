package main;

use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
  if ( !grep( /FHEM\/lib$/, @INC ) ) {
    foreach my $inc ( grep( /FHEM$/, @INC ) ) {
      push @INC, $inc . "/lib";
    }
  }
}

#####################################

my %sets = (
  "datetime" => "",
  "now"      => ""
);

my %gets = (
  "second"   => "",
  "minute"   => "",
  "hour"     => "",
  "day"      => "",
  "month"    => "",
  "year"     => "",
  "datetime" => "",
  "date"     => "",
  "time"     => ""
);

sub I2C_DS1307_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}   = "I2C_DS1307_Define";
  $hash->{InitFn}  = "I2C_DS1307_Init";
  $hash->{SetFn}   = "I2C_DS1307_Set";
  $hash->{AttrFn}  = "I2C_DS1307_Attr";
  
  $hash->{I2CRecFn} = "I2C_DS1307_Receive";

  $hash->{AttrList} = "IODev poll_interval $main::readingFnAttributes";
}

sub I2C_DS1307_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );

  $hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { I2C_DS1307_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_DS1307_Catch($@) if $@;
  }
  return undef;
}

sub I2C_DS1307_Init($$) {
  my ( $hash, $args ) = @_;
  my $u =
    "wrong syntax: define <name> I2C_DS1307 [<address>]";

  return $u if (defined $args and int(@$args) > 1 );

  my $name = $hash->{NAME};
  my $address = defined $args ? shift @$args : 0b1101000; #default address
  $hash->{I2C_Address} = $address;
  if (! (defined AttrVal($name,"stateFormat",undef))) {
    $main::attr{$name}{"stateFormat"} = "datetime";
  }
  eval {
    main::AssignIoPort( $hash, AttrVal( $name, "IODev", undef ) );
    $hash->{DS1307} = Device::DS1307->new($address);
    $hash->{DS1307}->attach(I2C_DS1307_IO->new($hash));
    $hash->{STATE} = "Initialized";
  };
  return I2C_DS1307_Catch($@) if $@;
  I2C_DS1307_Poll($hash);
  return undef;
}

sub I2C_DS1307_Attr($$$$) {
  my ( $command, $name, $attribute, $value ) = @_;
  my $hash = $main::defs{$name};
  eval {
    if ( $command eq "set" )
    {
    ARGUMENT_HANDLER: {
        $attribute eq "IODev" and do {
          if ( $main::init_done and ( !defined( $hash->{IODev} ) or $hash->{IODev}->{NAME} ne $value ) )
          {
            main::AssignIoPort( $hash, $value );
            my @def = split( ' ', $hash->{DEF} ) if defined $hash->{DEF};
            I2C_DS1307_Init( $hash, \@def ) if ( defined( $hash->{IODev} ) );
          }
          last;
        };
        $attribute eq "poll_interval" and do {
          $hash->{POLL_INTERVAL} = $value;
          if ( $main::init_done )
          {
            I2C_DS1307_Poll($hash);
          }
          last;
        }
      }
    }
  };
  my $ret = I2C_DS1307_Catch($@) if $@;
  if ($ret) {
    $hash->{STATE} = "error setting $attribute to $value: " . $ret;
    return "cannot $command attribute $attribute to $value for $name: " . $ret;
  }
}

sub I2C_DS1307_Set(@) {
  my ( $hash, @a ) = @_;
  return "Need at least one parameters" if ( @a < 2 );
  shift @a;
  my $command = shift @a;
  if ( !defined( $sets{$command} ) ) {
    my @commands = ();
    foreach my $key ( sort keys %sets ) {
      push @commands,
        $sets{$key} ? $key . ":" . join( ",", $sets{$key} ) : $key;
    }
    return "Unknown argument $command, choose one of " . join( " ", @commands );
  }
  my $ds1307 = $hash->{DS1307};
  return unless defined $ds1307;

  eval {
    COMMAND_HANDLER: {
      $command eq "datetime" and do {
        $ds1307->setDatetime(join (' ',@a));
        main::readingsSingleUpdate( $hash, "datetime", $ds1307->getDatetime(), 1 );
        last;
      };
      $command eq "now" and do {
        $ds1307->setTime(time());
        main::readingsSingleUpdate( $hash, "datetime", $ds1307->getDatetime(), 1 );
        last;
      };
    }
  };
  return I2C_DS1307_Catch($@) if $@;
  return undef;
}

sub I2C_DS1307_Poll {
  my ( $hash ) = @_;
  RemoveInternalTimer($hash);
  eval {
    $hash->{DS1307}->read();
  };
  my $ret = I2C_DS1307_Catch($@) if $@;
  if ($ret) {
    $hash->{STATE} = "error reading DS1307: " . $ret;
    main::Log3 $hash->{NAME},4,"error reading DS1307: ".$ret;
  }
  InternalTimer(gettimeofday()+$hash->{POLL_INTERVAL}, 'I2C_DS1307_Poll', $hash, 0) if defined $hash->{POLL_INTERVAL};
}

# package:
# i2caddress => $data->{address},
# direction  => "i2cread",
# reg        => $data->{register},
# nbyte      => scalar(@{$data->{data}}),
# data       => join (' ',@{$data->{data}})

sub I2C_DS1307_Receive {
  my ( $hash, $package ) = @_;
  
  $hash->{DS1307}->receive(
    split (' ',$package->{data})
  );
  main::readingsSingleUpdate( $hash, "datetime", $hash->{DS1307}->getDatetime(), 1 );
}

sub I2C_DS1307_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

package I2C_DS1307_IO;

use strict;
use warnings;

sub new {
  my ( $class, $hash ) = @_;
  return bless { hash => $hash, }, $class;
}

sub i2c_write {
  my ( $self, $address, @data ) = @_;
  my $hash = $self->{hash};
  if ( defined( my $iodev = $hash->{IODev} ) ) {
    main::CallFn(
      $iodev->{NAME},
      "I2CWrtFn",
      $iodev,
      {
        i2caddress => $address,
        direction  => "i2cwrite",
        data       => join( ' ', @data ),
      }
    );
  }
  else {
    die "no IODev assigned to '$hash->{NAME}'";
  }
}

sub i2c_read {
  my ( $self, $address, $reg, $nbyte ) = @_;
  my $hash = $self->{hash};
  if ( defined( my $iodev = $hash->{IODev} ) ) {
    main::CallFn(
      $iodev->{NAME},
      "I2CWrtFn",
      $iodev,
      {
        i2caddress => $address,
        direction  => "i2cread",
        reg        => $reg,
        nbyte      => $nbyte,
      }
    );
  }
  else {
    die "no IODev assigned to '$hash->{NAME}'";
  }
}

package Device::DS1307;

use strict;
use warnings;

# DS1307 ADDRESS MAP

use constant DS1307_SECONDS => 0x00;
use constant DS1307_MINUTES => 0x01;
use constant DS1307_HOURS   => 0x02;
use constant DS1307_DAY     => 0x03;
use constant DS1307_DATE    => 0x04;
use constant DS1307_MONTH   => 0x05;
use constant DS1307_YEAR    => 0x06;
use constant DS1307_CONTROL => 0x07;
use constant DS1307_RAM     => 0x08; 
# RAM 56 x 8 ?
# ...
# 0x3F

# DS1307 Control Register:
use constant DS1307_OUT  => 0x40; # BIT 7 OUT
use constant DS1307_SQWE => 0x10; # BIT 4 SQWE
use constant DS1307_RS1  => 0x02; # BIT 1 RS1
use constant DS1307_RS0  => 0x01; # BIT 0 RS0

sub new {
  my ( $class, $address, $timezone, $century ) = @_;
  return bless { 
    address  => $address,
    time => time(),
  }, $class;
}

sub getDatetime {
  my ( $self ) = @_;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($self->{datetime});
  return sprintf "%04d-%02d-%02d %02d:%02d:%02d", ($year+1900,$mon+1,$mday,$hour,$min,$sec);
}

sub setDatetime {
  my ( $self, $value ) = @_;
  $self->{datetime} = main::time_str2num($value);
  $self->write();
}

sub setTime {
  my ( $self, $value ) = @_;
  $self->{datetime} = $value;
  $self->write();
}

sub attach {
  my ( $self, $io ) = @_;
  $self->{io} = $io;
}

sub read {
  my ( $self ) = @_;
  $self->{io}->i2c_read( $self->{address}, 0, 7 );
}

sub receive {
  my ($self, @data) = @_;

  my $sec  = shift @data;
  my $min  = shift @data;
  my $hour = shift @data;
  my $wday = shift @data;
  my $mday = shift @data;
  my $mon  = shift @data;
  my $year = shift @data;
  
  #$self->{time} = mktime(sec, min, hour, mday, mon, year, wday = 0, yday = 0, isdst = -1)
  $self->{datetime} = main::mktime($sec, $min, $hour, $mday, $mon, $year, $wday, 0, -1);
}

sub write {
  my ( $self ) = @_;
  if (defined $self->{io}) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($self->{datetime});
    $self->{io}->i2c_write(
      $self->{address}, #slave address
      0,                #register
      $sec,             #data...
      $min,
      $hour,
      $wday,            #DS1307 week starts on Sunday
      $mday,
      $mon,
      $year,
      0);               #control
  }
};

1;

=pod
=begin html

<a name="I2C_DS1307"></a>
<h3>I2C_DS1307</h3>
<ul>
  reads a DS1307 real-time clock chip via I2C.

  Requires a defined <a href="#I2C">I2C</a>-device to work.<br>

  <a name="I2C_DS1307define"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; I2C_DS1307 &lt;i2c-address&gt;</code> <br>
  Specifies the I2C_DS1307 device.<br>
  <li>i2c-address is the (device-specific) address of the ic on the i2c-bus</li>
  </ul>
  
  <br>
  <a name="I2C_DS1307set"></a>
  <b>Set</b><br>
  <ul>
      <li><code>set &lt;name&gt; datetime</code>; set DS1307 time. Format is JJJJ-MM-DD HH:MM:SSdisplayed&gt;<br></li>
      <li><code>set &lt;name&gt; now</code><br></li>
  </ul>
  
  <a name="I2C_I2Cget"></a>
  <b>Get</b><br>
  <ul>
  N/A<br>
  </ul><br>
  <a name="I2C_DS1307attr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>poll_interval &lt;seconds&gt;</li>
      <li><a href="#IODev">IODev</a><br>
      Specify which <a href="#I2C">I2C</a> to use. (Optional, only required if there is more
      than one I2C-device defined.)
      </li>
      <li><a href="#eventMap">eventMap</a><br></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a><br></li>
    </ul>
  </ul>
<br>

=end html
=cut

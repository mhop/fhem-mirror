##############################################
# I2C_K30.pm: heavily based on I2C_SHT21.pm
#
# $Id$

package main;

use strict;
use warnings;

use constant {
  # For details, see SenseAir "I2C communication guide for K20/K21/K22/K30 platforms"
  K30_I2C_ADDRESS => 0x68,
  K30_REQ_READ_RAM => 0x20,
  K30_RESP_READ_COMPLETE => 0x21,
  K30_ADDR_CO2 => 0x08,
  K30_LEN_CO2 => 2
};

##################################################
# Forward declarations
#
sub I2C_K30_Initialize($);
sub I2C_K30_Define($$);
sub I2C_K30_Attr(@);
sub I2C_K30_Poll($);
sub I2C_K30_Set($@);
sub I2C_K30_Undef($$);
sub I2C_K30_DbLog_splitFn($);

my %sets = (
  'readValues' => 1,
);

sub I2C_K30_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}    = 'I2C_K30_Define';
  $hash->{InitFn}   = 'I2C_K30_Init';
  $hash->{AttrFn}   = 'I2C_K30_Attr';
  $hash->{SetFn}    = 'I2C_K30_Set';
  $hash->{UndefFn}  = 'I2C_K30_Undef';
  $hash->{I2CRecFn} = 'I2C_K30_I2CRec';
  $hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
            $readingFnAttributes;
  $hash->{DbLog_splitFn} = "I2C_K30_DbLog_splitFn";
}

sub I2C_K30_Define($$) {
  my ($hash, $def) = @_;
  my @a = split('[ \t][ \t]*', $def);
  
  $hash->{STATE} = "defined";

  if ($main::init_done) {
    eval { I2C_K30_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_K30_Catch($@) if $@;
  }
  return undef;
}

sub I2C_K30_Init($$) {
  my ( $hash, $args ) = @_;
  
  my $name = $hash->{NAME};

  if (defined $args && int(@$args) > 1)
  {
    Log3 $hash, 1, "Define: Wrong syntax. Can't initialize sensor.";
    return;
  }
   
  if (defined (my $address = shift @$args)) {
    $hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address;
    return "$name I2C Address not valid" unless ($address < 128 && $address > 3);
  } else {
    $hash->{I2C_Address} = K30_I2C_ADDRESS;
  }


  my $msg = '';
  # create default attributes
  if (AttrVal($name, 'poll_interval', '?') eq '?') {  
    $msg = CommandAttr(undef, $name . ' poll_interval 5');
    if ($msg) {
      Log3 ($hash, 1, $msg);
      return $msg;
    }
  }
  AssignIoPort($hash);  
  $hash->{STATE} = 'Initialized';

  return undef;
}

sub I2C_K30_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

sub I2C_K30_Attr (@) {# hier noch Werteueberpruefung einfuegen
  my ($command, $name, $attr, $val) =  @_;
  my $hash = $defs{$name};
  my $msg = '';
  if ($command && $command eq "set" && $attr && $attr eq "IODev") {
    eval {
      if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
        main::AssignIoPort($hash,$val);
        my @def = split (' ',$hash->{DEF});
        I2C_K30_Init($hash,\@def) if (defined ($hash->{IODev}));
      }
    };
    return I2C_K30_Catch($@) if $@;
  }
  if ($attr eq 'poll_interval') {
    if ($val > 0) {
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday() + 5, 'I2C_K30_Poll', $hash, 0);
    } else {
      $msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
    }
  } 
  return ($msg) ? $msg : undef;
}

sub I2C_K30_Poll($) {
  my ($hash) =  @_;
  my $name = $hash->{NAME};
  
  # Read values
  I2C_K30_Set($hash, ($name, 'readValues'));
  
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  if ($pollInterval > 0) {
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_K30_Poll', $hash, 0);
  }
}

sub I2C_K30_Set($@) {
  my ($hash, @a) = @_;
  my $name = $a[0];
  my $cmd =  $a[1];

  if(!defined($sets{$cmd})) {
    return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
  }
  
  if ($cmd eq 'readValues') {
    I2C_K30_readCO2($hash);
  }
}

sub I2C_K30_Undef($$) {
  my ($hash, $arg) = @_;

  RemoveInternalTimer($hash);
  return undef;
}

sub I2C_K30_I2CRec ($$) {
  my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};  
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  while ( my ( $k, $v ) = each %$clientmsg ) {
    #erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
    $hash->{$k} = $v if $k =~ /^$pname/ ;
  } 
    
  # Read Complete Response 
  if ( $clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
    if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
      Log3 $hash, 4, "empfangen: $clientmsg->{received}";    
      my @raw = split(" ",$clientmsg->{received});
      I2C_K30_ParseCO2 ($hash, $clientmsg->{received}) if ($raw[0] == K30_RESP_READ_COMPLETE) && $clientmsg->{nbyte} == 4;
    }
  }
}

sub I2C_K30_ParseCO2 ($$) {
  my ($hash, $rawdata) = @_;
  my @raw = split(" ",$rawdata);
  if ( defined (my $crc = I2C_K30_CheckCrc(@raw)) ) {    #CRC Test
    Log3 $hash, 3, "CRC error CO2 data: $rawdata, Checksum calculated: $crc";
    $hash->{CRCError}++;
    return;
  }  
  my $co2 = $raw[1] << 8 | $raw[2];
  $co2 = sprintf('%i', $co2);
  readingsBeginUpdate($hash);
  readingsBulkUpdate(
    $hash,
    'state',
    'CO2: ' . $co2
  );
  readingsBulkUpdate($hash, 'CO2', $co2);
  readingsEndUpdate($hash, 1);  
}

sub I2C_K30_readCO2($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return "$name: no IO device defined" unless ($hash->{IODev});
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
    
  my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
  # read CO2 from sensor RAM, last byte: "checksum" of all preceding bytes
  $i2creq->{data} = join(" ", (K30_REQ_READ_RAM | K30_LEN_CO2, 0, K30_ADDR_CO2, (K30_REQ_READ_RAM + K30_LEN_CO2 + 0 + K30_ADDR_CO2) ) );
  CallFn($pname, "I2CWrtFn", $phash, $i2creq);
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + 1, 'I2C_K30_readValue', $hash, 0); #nach 1s Wert lesen (min. 20ms lt. Datenblatt)
  return;
}

sub I2C_K30_readValue($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return "$name: no IO device defined" unless ($hash->{IODev});
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  
  # Reset Internal Timer to Poll Sub
  RemoveInternalTimer($hash);
  my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
  InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_K30_Poll', $hash, 0) if ($pollInterval > 0);
  # Read the three byte result from device + 1byte CRC
  my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
  $i2cread->{nbyte} = 4;
  CallFn($pname, "I2CWrtFn", $phash, $i2cread);
  
  return;
}

sub I2C_K30_CheckCrc(@) {
  my @data = @_;
  my $crc = 0;
  for (my $n = 0; $n < (scalar(@data) - 1); ++$n) {
    $crc += $data[$n];
  }
  return ($crc = $data[3] ? undef : $crc);
}

sub I2C_K30_DbLog_splitFn($) {
  my ($event) = @_;
  Log3 undef, 3, "in DbLog_splitFn empfangen: $event"; 
  my ($reading, $value, $unit) = "";
  my @parts = split(/ /,$event);
  $reading = shift @parts;
  $reading =~ tr/://d;
  $value = $parts[0];
  $unit = "ppm"   if(lc($reading) =~ m/CO2/);
  return ($reading, $value, $unit);
}

1;

=pod
=item device
=item summary read SenseAir K30 CO2 sensor via I2C bus
=item summary_DE SenseAir K30 CO2 Sensor über I2C auslesen
=begin html

<a name="I2C_K30"></a>
<h3>I2C_K30</h3>
(en | <a href="commandref_DE.html#I2C_K30">de</a>)
<ul>
  <a name="I2C_K30"></a>
    Provides an interface to the K30 CO2 sensor from <a href="www.senseair.com">SenseAir</a>. This module
    expects the sensor to be connected via I2C (for a quick summary, see
    <a href="http://co2meters.com/Documentation/AppNotes/AN142-RaspberryPi-K_series.pdf">Application Note 142 "K-30/K-33 I2C on Raspberry Pi"</a> 
    from co2meters.com).<br> 

    On my Raspberry Pi 2, I needed to reduce I2C frequency to 90 kHz, otherwise most read/write cycles failed (add
    "options i2c_bcm2708 baudrate=90000", e.g. to /etc/modprobe.d/i2c-options.conf). I still see sporadic errors (about 5% of all readings 
    fail), but this seems to be expected - the datasheet warns that the uC on the sensor will only correctly handle I2C when it's not busy
    doing CO2 measurement.

    The I2C messages are sent through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
    or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
    <b>attribute IODev must be set</b><br>
  <a name="I2C_K30Define"></a><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; I2C_K30 [&lt;I2C Address&gt;]</code><br>
    where <code>&lt;I2C Address&gt;</code> is the configured I2C address of the sensor (default: 104, i.e. 0x68) <br>
  </ul>
  <a name="I2C_K30Set"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; readValues</code><br>
    Reads the current CO2 value from sensor.<br><br>
  </ul>
  <a name="I2C_K30Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>poll_interval<br>
      Set the polling interval in minutes to query data from sensor<br>
      Default: 5, valid values: 1,2,5,10,20,30<br><br>
    </li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
  </ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_K30"></a>
<h3>I2C_K30</h3>
(<a href="commandref.html#I2C_K30">en</a> | de)
<ul>
  <a name="I2C_K30"></a>
    Erm&ouml;glicht die Verwendung eines K30 CO2 Sensors von <a href="www.senseair.com">SenseAir</a>. Der Sensor
    muss &uuml;ber I2C angeschlossen sein (siehe z.B. 
    <a href="http://co2meters.com/Documentation/AppNotes/AN142-RaspberryPi-K_series.pdf">Application Note 142 "K-30/K-33 I2C on Raspberry Pi"</a> 
    von co2meters.com).

    Auf meinem Raspberry Pi 2 musste ich die I2C-Frequenz auf 90 kHz reduzieren, sonst sind die meisten I2C-Zugriffe fehlgeschlagen 
    ("options i2c_bcm2708 baudrate=90000", z.B. in /etc/modprobe.d/i2c-options.conf eintragen). Nach wie vor gehen ca. 5 % der Zugriffe schief,
    aber das scheint normal zu sein - zumindest warnt das Datenblatt, dass I2C-Zugriffe fehlschlagen k&ouml;nnen, wenn der Microcontroller auf dem 
    Sensor gerade mit einer CO2-Messung besch&auml;ftigt ist.

    I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
    oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
    <b>Das Attribut IODev muss definiert sein.</b><br>
  <a name="I2C_K30Define"></a><br>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; I2C_K30 [&lt;I2C Address&gt;]</code><br>
    Der Wert <code>&lt;I2C Address&gt;</code> ist die konfigurierte I2C-Adresse des Sensors (Standard: 104 bzw. 0x68)<br>
  </ul>
  <a name="I2C_K30Set"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; readValues</code><br>
    Aktuellen CO2 Wert vom Sensor lesen.<br><br>
  </ul>
  <a name="I2C_K30Attr"></a>
  <b>Attribute</b>
  <ul>
    <li>poll_interval<br>
      Aktualisierungsintervall aller Werte in Minuten.<br>
      Standard: 5, g&uuml;ltige Werte: 1,2,5,10,20,30<br><br>
    </li>
    <li><a href="#IODev">IODev</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#showtime">showtime</a></li>
  </ul><br>
</ul>

=end html_DE

=cut

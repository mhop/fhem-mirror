=head1
	51_I2C_BMP180.pm

=head1 SYNOPSIS
	Modul for FHEM for reading a BMP180 or BMP085 digital pressure sensor via I2C
	connected to the Raspberry Pi.

	contributed by Dirk Hoffmann 2013
	$Id$

=head1 DESCRIPTION
	51_I2C_BMP180.pm reads the air pressure of the digital pressure sensor BMP180
	or BMP085 via i2c bus connected to the Raspberry Pi.

	This module needs the HiPi Perl Modules
	see: http://raspberrypi.znix.com/hipidocs/
	
	For a simple automated installation:<br>
	wget http://raspberry.znix.com/hipifiles/hipi-install
	perl hipi-install

	Example:
	define BMP180 I2C_BMP180 /dev/i2c-0
	attr BMP180 poll_iterval 5
	attr BMP180 oversampling_settings 3

=head1 AUTHOR - Dirk Hoffmann
	dirk@FHEM_Forum (forum.fhem.de)
=cut

package main;

use strict;
use warnings;

use HiPi::Device::I2C;
use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
use Error qw(:try);

use constant {
	BMP180_I2C_ADDRESS => '0x77',
};

##################################################
# Forward declarations
#
sub I2C_BMP180_Initialize($);
sub I2C_BMP180_Define($$);
sub I2C_BMP180_Attr(@);
sub I2C_BMP180_Poll($);
sub I2C_BMP180_Set($@);
sub I2C_BMP180_Undef($$);
sub I2C_BMP180_ReadInt($$;$);
sub I2C_BMP180_readUncompensatedTemperature($);
sub I2C_BMP180_readUncompensatedPressure($$);
sub I2C_BMP180_calcTrueTemperature($$);
sub I2C_BMP180_calcTruePressure($$$);

my %sets = (
	'readValues' => 1,
);

=head2 I2C_BMP180_Initialize
	Title:		I2C_BMP180_Initialize
	Function:	Implements the initialize function.
	Returns:	-
	Args:		named arguments:
				-argument1 => hash
=cut
sub I2C_BMP180_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_BMP180_Define';
	$hash->{AttrFn}   = 'I2C_BMP180_Attr';
	$hash->{SetFn}    = 'I2C_BMP180_Set';
	$hash->{UndefFn}  = 'I2C_BMP180_Undef';

	$hash->{AttrList} = 'do_not_notify:0,1 showtime:0,1 model:BMP180,BMP085 ' .
	                    'poll_interval:1,2,5,10,20,30 oversampling_settings:0,1,2,3 ' .
						'roundPressureDecimal:0,1,2 roundTemperatureDecimal:0,1,2 ' .
						$readingFnAttributes;
}

=head2 I2C_BMP180_Define
	Title:		I2C_BMP180_Define
	Function:	Implements the define function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash
				-argument2 => string
=cut
sub I2C_BMP180_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	my $name = $a[0];
	my $dev = $a[2];

	my $msg = '';
	if( (@a < 3)) {
		$msg = 'wrong syntax: define <name> I2C_BMP180 devicename';
	}

	# create default attributes
	$msg = CommandAttr(undef, $name . ' poll_interval 5');
	$msg = CommandAttr(undef, $name . ' oversampling_settings 3');

	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
	}
	
	# check for existing i2c device
	my $i2cModulesLoaded = 0;
	$i2cModulesLoaded = 1 if -e $dev;

	if ($i2cModulesLoaded) {
		$hash->{devBPM180} = HiPi::Device::I2C->new( 
			devicename	=> $dev,
			address		=> hex(BMP180_I2C_ADDRESS),
			busmode		=> 'i2c',
		);
		
		# read calibration data from sensor
		$hash->{calibrationData}{ac1} = I2C_BMP180_ReadInt($hash, 0xAA);
		if ( defined($hash->{calibrationData}{ac1}) ) {
			$hash->{calibrationData}{ac2} = I2C_BMP180_ReadInt($hash, 0xAC);
			$hash->{calibrationData}{ac3} = I2C_BMP180_ReadInt($hash, 0xAE);
			$hash->{calibrationData}{ac4} = I2C_BMP180_ReadInt($hash, 0xB0, 0);
			$hash->{calibrationData}{ac5} = I2C_BMP180_ReadInt($hash, 0xB2, 0);
			$hash->{calibrationData}{ac6} = I2C_BMP180_ReadInt($hash, 0xB4, 0);
			$hash->{calibrationData}{b1}  = I2C_BMP180_ReadInt($hash, 0xB6);
			$hash->{calibrationData}{b2}  = I2C_BMP180_ReadInt($hash, 0xB8);
			$hash->{calibrationData}{mb}  = I2C_BMP180_ReadInt($hash, 0xBA);
			$hash->{calibrationData}{mc}  = I2C_BMP180_ReadInt($hash, 0xBC);
			$hash->{calibrationData}{md}  = I2C_BMP180_ReadInt($hash, 0xBE);
		} else {
			return $name . ': Error! I2C failure: Please check your i2c bus ' . $dev . ' and the connected device address: ' . BMP180_I2C_ADDRESS;
		}
	
		$hash->{STATE} = 'Initialized';
	} else {
		return $name . ': Error! I2C device not found: ' . $dev . '. Please check kernelmodules must loaded: i2c_bcm2708, i2c_dev';
	}
	
	return undef;
}

=head2 I2C_BMP180_Attr
	Title:		I2C_BMP180_Attr
	Function:	Implements AttrFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => array
=cut
sub I2C_BMP180_Attr (@) {
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	if ($attr eq 'poll_interval') {
		my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		
		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_BMP180_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	}

	return ($msg) ? $msg : undef;
}

=head2 I2C_BMP180_Poll
	Title:		I2C_BMP180_Poll
	Function:	Start polling the sensor at interval defined in attribute
	Returns:	-
	Args:		named arguments:
				-argument1 => hash
=cut
sub I2C_BMP180_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	# Read values
	I2C_BMP180_Set($hash, ($name, 'readValues'));
	
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_BMP180_Poll', $hash, 0);
	}
}

=head2 I2C_BMP180_Set
	Title:		I2C_BMP180_Set
	Function:	Implements SetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array
=cut
sub I2C_BMP180_Set($@) {
	my ($hash, @a) = @_;

	my $name =$a[0];
	my $cmd = $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}
	
	if ($cmd eq 'readValues') {
		my $overSamplingSettings = AttrVal($hash->{NAME}, 'oversampling_settings', 3);
		
		# query sensor
		my $ut = I2C_BMP180_readUncompensatedTemperature($hash);
		my $up = I2C_BMP180_readUncompensatedPressure($hash, $overSamplingSettings);
		
		my $temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			I2C_BMP180_calcTrueTemperature($hash, $ut) / 10
		);
		
		my $pressure = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundPressureDecimal', 1) . 'f',
			I2C_BMP180_calcTruePressure($hash, $up, $overSamplingSettings) / 100
		);

		my $altitude = AttrVal('global', 'altitude', 0);
		
		# simple barometric height formula
		my $pressureNN = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundPressureDecimal', 1) . 'f',
			$pressure + ($altitude / 8.5)
		);
		
		readingsBeginUpdate($hash);
		readingsBulkUpdate(
			$hash,
			'state',
			'T: ' . $temperature . ' P: ' . $pressure . ' P-NN: ' . $pressureNN
		);
		readingsBulkUpdate($hash, 'temperature', $temperature);
		readingsBulkUpdate($hash, 'pressure', $pressure);

		readingsBulkUpdate($hash, 'pressure-nn', $pressureNN);
		readingsBulkUpdate($hash, 'altitude', $altitude, 0);

		readingsEndUpdate($hash, 1);
	}
}

=head2 I2C_BMP180_Undef
	Title:		I2C_BMP180_Undef
	Function:	Implements UndefFn function.
	Returns:	undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array
=cut
sub I2C_BMP180_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

=head2 I2C_BMP180_ReadInt
	Title:		I2C_BMP180_ReadInt
	Function:	Read 2 bytes from i2c device from given register.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash			hash of device
				-argument2 => number:	$register
				-argument3 => boolean:	$returnSigned	1, if number returned signed (optional)
=cut
sub I2C_BMP180_ReadInt($$;$) {
	my ($hash, $register, $returnSigned) = @_;
	my $name = $hash->{NAME};
	
	$returnSigned = (!defined($returnSigned) || $returnSigned == 1) ? 1 : 0; 

	my $retVal = undef;

	try {
		my @values = $hash->{devBPM180}->bus_read($register, 2);

		$retVal = $values[0] << 8 | $values[1];
		
		# check if we need return signed or unsigned int
		if ($returnSigned == 1) {
			$retVal = $retVal >> 15 ? $retVal - 2**16 : $retVal;
		}

	} catch Error with {
		Log3 ($hash, 1, ': ERROR: I2C_BMP180: i2c-bus_read failure');
	};  
	
	return $retVal;
}

=head2 I2C_BMP180_readUncompensatedTemperature
	Title:		I2C_BMP180_readUncompensatedTemperature
	Function:	Read the uncompensated temperature value.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash			hash of device
=cut
sub I2C_BMP180_readUncompensatedTemperature($) {
	my ($hash) = @_;

	# Write 0x2E into Register 0xF4. This requests a temperature reading
	$hash->{devBPM180}->bus_write( (0xF4, 0x2E) );
	
	usleep(4500);

	# Read the two byte result from address 0xF6
	my @values = $hash->{devBPM180}->bus_read(0xF6, 2);
	
	my $retVal = $values[0] << 8 | $values[1];
	return $retVal;
}

=head2 I2C_BMP180_readUncompensatedPressure
	Title:		I2C_BMP180_readUncompensatedPressure
	Function:	Read the uncompensated pressure value.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash			hash of device
				-argument2 => number:	$overSamplingSettings
=cut
sub I2C_BMP180_readUncompensatedPressure($$) {
	my ($hash, $overSamplingSettings) = @_;

	# Write 0x34+($overSamplingSettings << 6) into register 0xF4
	# Request a pressure reading with oversampling setting
	$hash->{devBPM180}->bus_write( (0xF4, 0x34 + ($overSamplingSettings << 6)) );
	
	# Wait for conversion, delay time dependent on oversampling setting
	usleep( (2 + (3 << $overSamplingSettings)) * 1000 );
	
	# Read the three byte result from 0xF6. 0xF6 = MSB, 0xF7 = LSB and 0xF8 = XLSB
	my @values = $hash->{devBPM180}->bus_read(0xF6, 3);
	my $retVal = ( ( ($values[0] << 16) | ($values[1] << 8) | $values[2] ) >> (8 - $overSamplingSettings) );
	
	return $retVal;
}

=head2 I2C_BMP180_calcTrueTemperature
	Title:		I2C_BMP180_calcTrueTemperature
	Function:	Calculate temperature from given uncalibrated temperature
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => number:	$ut		uncalibrated temperature
=cut
sub I2C_BMP180_calcTrueTemperature($$) {
	my ($hash, $ut) = @_;
	
	my $x1 = ($ut - $hash->{calibrationData}{ac6}) * $hash->{calibrationData}{ac5} / 32768;
	my $x2 = ($hash->{calibrationData}{mc} * 2048) / ($x1 + $hash->{calibrationData}{md});

	$hash->{calibrationData}{b5} = $x1 + $x2;

	my $retVal = (($hash->{calibrationData}{b5} + 8) / 16);

	return $retVal;
}

=head2 I2C_BMP180_calcTruePressure
	Title:		I2C_BMP180_calcTruePressure
	Function:	Calculate the pressure from given uncalibrated pressure
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash					hash of device
				-argument2 => number:	$up						uncalibrated pressure
				-argument3 => number:	$overSamplingSettings
=cut
sub I2C_BMP180_calcTruePressure($$$) {
	my ($hash, $up, $overSamplingSettings) = @_;

	my $b6 = $hash->{calibrationData}{b5} - 4000;

	my $x1 = ($hash->{calibrationData}{b2} * ($b6 * $b6 / 4096)) / 2048;
	my $x2 = ($hash->{calibrationData}{ac2} * $b6) / 2048;
	my $x3 = $x1 + $x2;
	my $b3 = ((($hash->{calibrationData}{ac1} * 4 + $x3) << $overSamplingSettings) + 2) / 4;

	$x1 = $hash->{calibrationData}{ac3} * $b6 / 8192;
	$x2 = ($hash->{calibrationData}{b1} * ($b6 * $b6 / 4096)) / 65536;
	$x3 = (($x1 + $x2) + 2) / 4;
	my $b4 = $hash->{calibrationData}{ac4} * ($x3 + 32768) / 32768;

	my $b7 = ($up - $b3) * (50000 >> $overSamplingSettings);
	my $p = ($b7 < 0x80000000) ? (($b7 * 2) / $b4) : (($b7 / $b4) * 2);
	
	$x1 = ($p / 256) * ($p / 256);
	$x1 = ($x1 * 3038) / 65536;
	$x2 = (-7357 * $p) / 65536;
	$p += (($x1 + $x2 + 3791) / 16);

	return $p;
}

1;

=pod
=begin html

<a name="I2C_BMP180"></a>
<h3>I2C_BMP180</h3>
<ul>
  <a name="I2C_BMP180"></a>
  <p>
    With this module you can read values from the digital pressure sensors BMP180 and BMP085
    via the i2c bus on Raspberry Pi.<br><br>
    
    Before you can use the Modul on the Raspberry Pi you must load the I2C kernel
    modules.<br>
    Add these two lines to your <b>/etc/modules</b> file to load the kernel modules
    automaticly during booting your Raspberry Pi.<br>
    <code><pre>
     i2c-bcm2708 
     i2c-dev
    </pre></code>
      
    <b>Please note:</b><br>
    For the i2c communication, the perl modules HiPi::Device::I2C
    are required.<br>
    For a simple automated installation:<br>
    <code>wget http://raspberry.znix.com/hipifiles/hipi-install<br>
    perl hipi-install</code><br><br>
    
    To change the permissions of the I2C device you must create the following
    file <b>/etc/udev/rules.d/98_i2c.rules</b> with this content:<br>
    <code>SUBSYSTEM=="i2c-dev", MODE="0666"</code><br><br>
    After these changes you must restart your Raspberry Pi.<br><br>

    If you want to use the sensor on the second I2C bus at the P5 connector
    (only available at the version 2 of the Raspberry Pi) you must add the bold
    line of this code in your FHEM start script:
    <code><pre>
    case "$1" in
    'start')
        <b>sudo hipi-i2c e 0 1</b>
        ...
    </pre></code>
  <p>
  
  <b>Define</b>
  <ul>
    <code>define BMP180 I2C_BMP180 &lt;I2C device&gt;</code><br>
    <br>
    Examples:
    <pre>
      define BMP180 I2C_BMP180 /dev/i2c-0
      attr BMP180 oversampling_settings 3
      attr BMP180 poll_interval 5
    </pre>
  </ul>

  <a name="I2C_BMP180set"></a>
  <b>Set</b>
  <ul>
    <code>set BMP180  &lt;readValues&gt;</code>
    <br><br>
    Reads the current temperature and pressure values from sensor.<br>
    Normaly this execute automaticly at each poll intervall. You can execute
    this manually if you want query the current values.
    <br><br>
  </ul>

  <a name="I2C_BMP180get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="I2C_BMP180attr"></a>
  <b>Attributes</b>
  <ul>
    <li>oversampling_settings<br>
      Controls the oversampling setting of the pressure measurement in the sensor.<br>
      Default: 3, valid values: 0, 1, 2, 3<br><br>
    </li>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the sensor for new measured
      values.<br>
      Default: 5, valid values: 1, 2, 5, 10, 20, 30<br><br>
    </li>
    <li>roundTemperatureDecimal<br>
      Round temperature values to given decimal places.<br>
      Default: 1, valid values: 0, 1, 2<br><br>
    </li>
    <li>roundPressureDecimal<br>
      Round temperature values to given decimal places.<br>
      Default: 1, valid values: 0, 1, 2<br><br>
    </li>
    <li>altitude<br>
      if set, this altitude is used for calculating the pressure related to sea level (nautic null) NN<br><br>
      Note: this is a global attributes, e.g<br> 
      <ul>
        attr global altitude 220
      </ul>
    </li>
</ul>
  <br>
</ul>

=end html
=cut

=pod
=begin html_DE

<a name="I2C_BMP180"></a>
<h3>I2C_BMP180</h3>
<ul>
  <a name="I2C_BMP180"></a>
  <p>
    Dieses Modul erm&ouml;glicht das Auslesen der digitalen (Luft)drucksensoren
    BMP085 und BMP180 &uuml;ber den I2C Bus des Raspberry Pi.<br><br>
    
    Vor Verwendung des Moduls m&uuml;ssen auf dem Raspberry Pi die I2C Kernel
    Module geladen werden.<br>
    Diese beiden Zeilen m&uuml;ssen in die Datei <b>/etc/modules</b> angef&uuml;gt werden,
    um die Kernel Module automatisch beim Booten des Raspberry Pis zu laden.<br>
    
    <code><pre>
    i2c-bcm2708 
    i2c-dev</pre></code>
    <b>Bemerkung:</b><br>
    F&uuml;r die Kommunikation &uuml;ber den I2C Bus wird das Perl Modul <b>HiPi::Device::I2C</b>
    ben&ouml;tigt.<br>
    Die Installation erfolgt automatisch mit folgenden Befehlen auf der Konsole des 
    Raspberry Pis:<br>
    
    <code><pre>
    wget http://raspberry.znix.com/hipifiles/hipi-install
    perl hipi-install</pre></code>
    
    Um die Rechte des I2C Devices anzupassen, muss die Datei
    <b>/etc/udev/rules.d/98_i2c.rules</b> mit folgendem Inhalt erzeugt werden:<br>
    <code><pre>
    SUBSYSTEM=="i2c-dev", MODE="0666"</pre></code>
    Danach muss der Raspberry Pi neu gestartet werden.<br><br>
    
    Wenn der Sensor am zweiten I2C Bus am Stecker P5 (nur in der Version 2 des
    Raspberry Pi vorhanden) verwendet werden soll, muss die fett gedruckte Zeile
    des folgenden Codes in das FHEM Start Skript aufgenommen werden:
    <code><pre>
    case "$1" in
    'start')
        <b>sudo hipi-i2c e 0 1</b>
        ...
    </pre></code>
  <p>
  
  <b>Define</b>
  <ul>
    <code>define BMP180 &lt;BMP180_name&gt; &lt;I2C_device&gt;</code><br>
    <br>
    Beispiel:
    <pre>
      define BMP180 I2C_BMP180 /dev/i2c-0
      attr BMP180 oversampling_settings 3
      attr BMP180 poll_interval 5
    </pre>
  </ul>

  <a name="I2C_BMP180set"></a>
  <b>Set</b>
  <ul>
    <code>set BMP180 readValues</code>
    <br><br>
    Liest die aktuelle Temperatur und den Luftdruck des Sensors aus.<br>
    Dies wird automatisch nach Ablauf des definierten Intervalls ausgef&uuml;hrt.
    Wenn der aktuelle Wert gelesen werden soll, kann dieser Befehl auch manuell
    ausgef&uuml;hrt werden.
    <br><br>
  </ul>

  <a name="I2C_BMP180get"></a>
  <b>Get</b>
  <ul>
    N/A
  </ul>
  <br>

  <a name="I2C_BMP180attr"></a>
  <b>Attribute</b>
  <ul>
    <li>oversampling_settings<br>
      Steuert das Oversampling der Druckmessung im Sensor.<br>
      Default: 3, g&uuml;ltige Werte: 0, 1, 2, 3<br><br>
    </li>
    <li>poll_interval<br>
      Definiert das Poll Intervall in Minuten f&uuml;r das Auslesen einer neuen Messung.<br>
      Default: 5, g&uuml;ltige Werte: 1, 2, 5, 10, 20, 30<br><br>
    </li>
    <li>roundTemperatureDecimal<br>
      Rundet den Temperaturwert mit den angegebenen Nachkommastellen.<br>
      Default: 1, g&uuml;ltige Werte: 0, 1, 2<br><br>
    </li>
    <li>roundPressureDecimal<br>
      Rundet die Drucksensorwerte mit den angegebenen Nachkommastellen.<br>
      Default: 1, valid values: 0, 1, 2<br><br>
    </li>
    <li>altitude<br>
      Wenn dieser Wert definiert ist, wird diese Angabe zus&auml; f&uuml;r die Berechnung des 
      Luftdrucks bezogen auf Meeresh&ouml;he (Normalnull) NN herangezogen.<br>
      Bemerkung: Dies ist ein globales Attribut.<br><br>
      <code>attr global altitude 220</code>
    </li>
</ul>
  <br>
</ul>

=end html_DE
=cut

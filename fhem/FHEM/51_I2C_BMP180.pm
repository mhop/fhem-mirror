# $Id$
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
	modified for use with physical I2C devices by Klaus Wittstock (klausw)
=cut

package main;

use strict;
use warnings;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);

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
sub I2C_BMP180_readUncompensatedTemperature($);
sub I2C_BMP180_readUncompensatedPressure($$);
sub I2C_BMP180_calcTrueTemperature($$);
sub I2C_BMP180_calcTruePressure($$$);

my $libcheck_hasHiPi = 1;

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

	eval "use HiPi::Device::I2C;";
  $libcheck_hasHiPi = 0 if($@);
	
	$hash->{DefFn}    = 'I2C_BMP180_Define';
	$hash->{InitFn}   = 'I2C_BMP180_Init';
	$hash->{AttrFn}   = 'I2C_BMP180_Attr';
	$hash->{SetFn}    = 'I2C_BMP180_Set';
	$hash->{UndefFn}  = 'I2C_BMP180_Undef';
  $hash->{I2CRecFn} = 'I2C_BMP180_I2CRec';

	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 model:BMP180,BMP085 ' .
	                    'poll_interval:1,2,5,10,20,30 oversampling_settings:0,1,2,3 ' .
											'roundPressureDecimal:0,1,2 roundTemperatureDecimal:0,1,2 ' .
											$readingFnAttributes;
	$hash->{AttrList} .= " useHiPiLib:0,1 " if( $libcheck_hasHiPi );
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
	$hash->{STATE} = 'defined';
	
	my $name = $a[0];

	my $msg = '';
	$hash->{HiPi_exists} = $libcheck_hasHiPi if($libcheck_hasHiPi);
	if (@a == 3) {
		if ($libcheck_hasHiPi) {
			$hash->{HiPi_used} = 1;
		} else {
			$msg = '$name error: HiPi library not installed';
		}
	} elsif((@a < 2)) {
		$msg = 'wrong syntax: define <name> I2C_BMP180 [devicename]';
	}
	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
	}
	if ($main::init_done || $hash->{HiPi_used}) {
    eval { I2C_BMP180_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_BMP180_Catch($@) if $@;
  }
	
}

sub I2C_BMP180_Init($$) {
	my ( $hash, $args ) = @_;
	my $name = $hash->{NAME};
	$hash->{I2C_Address} = hex(BMP180_I2C_ADDRESS);
	my $msg = '';
	# create default attributes
	$msg = CommandAttr(undef, $name . ' poll_interval 5');
	$msg = CommandAttr(undef, $name . ' oversampling_settings 3');
	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
	}
	
	if ($hash->{HiPi_used}) {
		my $dev = shift @$args;
		my $i2cModulesLoaded = 0;
		$i2cModulesLoaded = 1 if -e $dev;
		if ($i2cModulesLoaded) {
			$hash->{devBPM180} = HiPi::Device::I2C->new( 
				devicename	=> $dev,
				address		=> hex(BMP180_I2C_ADDRESS),
				busmode		=> 'i2c',
			);
		} else {
			return $name . ': Error! I2C device not found: ' . $dev . '. Please check kernelmodules must loaded: i2c_bcm2708, i2c_dev';
		}
	} else {
		AssignIoPort($hash);	
	}
	$hash->{STATE} = 'getCalData';
	I2C_BMP180_i2cread($hash, hex("AA"), 22);
	return undef;
}

sub I2C_BMP180_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
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

	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}
	
	if ($cmd eq 'readValues') {
		my $overSamplingSettings = AttrVal($hash->{NAME}, 'oversampling_settings', 3);
		
		if (defined($hash->{calibrationData}{ac1})) {	# query sensor
			I2C_BMP180_readUncompensatedTemperature($hash);
			I2C_BMP180_readUncompensatedPressure($hash, $overSamplingSettings);
		} else {																			#..but get calibration variables first
			I2C_BMP180_i2cread($hash, hex("AA"), 22);
		}
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

sub I2C_BMP180_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};  
	my $pname = undef;
	unless ($hash->{HiPi_used}) {#nicht nutzen wenn HiPi Bibliothek in Benutzung
		my $phash = $hash->{IODev};
		$pname = $phash->{NAME};
		while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
			$hash->{$k} = $v if $k =~ /^$pname/ ;
		}
	}
	
	if ( $clientmsg->{direction} && $clientmsg->{reg} && (
			 ($pname && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok")
				|| $hash->{HiPi_used}) ) {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
			Log3 $hash, 5, "$name empfangen: $clientmsg->{received}";
		  I2C_BMP180_GetCal   ($hash, $clientmsg->{received}) if $clientmsg->{reg} == hex("AA");
			I2C_BMP180_GetTemp  ($hash, $clientmsg->{received}) if $clientmsg->{reg} == hex("F6") && $clientmsg->{nbyte} == 2;
			I2C_BMP180_GetPress ($hash, $clientmsg->{received}) if $clientmsg->{reg} == hex("F6") && $clientmsg->{nbyte} == 3;
		}
	}
}

sub I2C_BMP180_GetCal ($$) {
	my ($hash, $rawdata) = @_;
  my @raw = split(" ",$rawdata);
	my $n = 0;
	Log3 $hash, 5, "in get cal: $rawdata";
	$hash->{calibrationData}{ac1} = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{ac2} = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{ac3} = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{ac4} = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++], 0);
	$hash->{calibrationData}{ac5} = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++], 0);
	$hash->{calibrationData}{ac6} = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++], 0);
	$hash->{calibrationData}{b1}  = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{b2}  = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{mb}  = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{mc}  = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{md}  = I2C_BMP180_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{STATE} = 'Initialized';
	return
}

sub I2C_BMP180_GetCalVar ($$;$) {
	my ($msb, $lsb, $returnSigned) = @_;

	$returnSigned = (!defined($returnSigned) || $returnSigned == 1) ? 1 : 0; 
	my $retVal = undef;
	$retVal = $msb << 8 | $lsb;
	# check if we need return signed or unsigned int
	if ($returnSigned == 1) {
		$retVal = $retVal >> 15 ? $retVal - 2**16 : $retVal;
	}
	return $retVal;	
}

sub I2C_BMP180_GetTemp ($$) {
	my ($hash, $rawdata) = @_;
  my @raw = split(" ",$rawdata);
  $hash->{uncompTemp} = $raw[0] << 8 | $raw[1];
}

sub I2C_BMP180_GetPress ($$) {
	my ($hash, $rawdata) = @_;
  my @raw = split(" ",$rawdata);
	my $overSamplingSettings = AttrVal($hash->{NAME}, 'oversampling_settings', 3);
	
  my $ut = $hash->{uncompTemp};
	delete $hash->{uncompTemp};
	my $up = ( ( ($raw[0] << 16) | ($raw[1] << 8) | $raw[2] ) >> (8 - $overSamplingSettings) );

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
	#readingsBulkUpdate($hash, 'altitude', $altitude, 0);
	readingsEndUpdate($hash, 1);	
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
	I2C_BMP180_i2cwrite($hash, hex("F4"), hex("2E"));
	
	usleep(4500);

	# Read the two byte result from address 0xF6
	I2C_BMP180_i2cread($hash, hex("F6"), 2);
	
	return;
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
	my $data = hex("34") + ($overSamplingSettings << 6);
	I2C_BMP180_i2cwrite($hash, hex("F4"), $data);
	
	# Wait for conversion, delay time dependent on oversampling setting
	usleep( (2 + (3 << $overSamplingSettings)) * 1000 );
	
	# Read the three byte result from 0xF6. 0xF6 = MSB, 0xF7 = LSB and 0xF8 = XLSB
	I2C_BMP180_i2cread($hash, hex("F6"), 3);
	
	return;
}

sub I2C_BMP180_i2cread($$$) {
	my ($hash, $reg, $nbyte) = @_;
	if ($hash->{HiPi_used}) {
		eval {
			my @values = $hash->{devBPM180}->bus_read($reg, $nbyte);
			I2C_BMP180_I2CRec($hash, {
				direction  => "i2cread",
				i2caddress => $hash->{I2C_Address},
				reg => 				$reg,
				nbyte => 			$nbyte,
				received => 	join (' ',@values),
			});
		}; 
		Log3 ($hash, 1, $hash->{NAME} . ': ' . I2C_BMP180_Catch($@)) if $@;;
	} else {
		if (defined (my $iodev = $hash->{IODev})) {
			CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			direction  => "i2cread",
			i2caddress => $hash->{I2C_Address},
			reg => 				$reg,
			nbyte => 			$nbyte
			});
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}
	}
}

sub I2C_BMP180_i2cwrite($$$) {
	my ($hash, $reg, @data) = @_;
	if ($hash->{HiPi_used}) {
		eval {
			$hash->{devBPM180}->bus_write($reg, join (' ',@data));
			I2C_BMP180_I2CRec($hash, {
				direction  => "i2cwrite",
				i2caddress => $hash->{I2C_Address},
				reg => 				$reg,
				data => 			join (' ',@data),
			});
		}; 
		Log3 ($hash, 1, $hash->{NAME} . ': ' . I2C_BMP180_Catch($@)) if $@;;
	} else {
		if (defined (my $iodev = $hash->{IODev})) {
			CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
			direction  => "i2cwrite",
			i2caddress => $hash->{I2C_Address},
			reg => 				$reg,
			data => 			join (' ',@data),
			});
		} else {
			return "no IODev assigned to '$hash->{NAME}'";
		}
	}
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
    <b>There are two possibilities connecting to I2C bus:</b><br>
    <ul>
	<li><b>via RPII2C module</b><br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
		<b>attribute IODev must be set</b><br><br>
    </li>
	<li><b>via HiPi library</b><br>	
		Add these two lines to your <b>/etc/modules</b> file to load the I2C relevant kernel modules
		automaticly during booting your Raspberry Pi.<br>
		<code><pre>	i2c-bcm2708 
        i2c-dev</pre></code>
		Install HiPi perl modules:<br>
		<code><pre>	wget http://raspberry.znix.com/hipifiles/hipi-install
        perl hipi-install</pre></code>
		To change the permissions of the I2C device create file:<br>
		<code><pre>	/etc/udev/rules.d/98_i2c.rules</pre></code>
		with this content:<br>
		<code><pre>	SUBSYSTEM=="i2c-dev", MODE="0666"</pre></code>
		<b>Reboot</b><br><br>

		To use the sensor on the second I2C bus at P5 connector
		(only for version 2 of Raspberry Pi) you must add the bold
		line of following code to your FHEM start script:
		<code><pre>	case "$1" in
        'start')
        <b>sudo hipi-i2c e 0 1</b>
        ...</pre></code>
	</li></ul>
	<p>
  
  <b>Define</b>
  <ul>
    <code>define BMP180 I2C_BMP180 [&lt;I2C device&gt;]</code><br><br>
	&lt;I2C device&gt; must not be used if you connect via RPII2C module. For HiPi it's mandatory. <br>
    <br>
    Examples:
    <pre>
      define BMP180 I2C_BMP180 /dev/i2c-0
      attr BMP180 oversampling_settings 3
      attr BMP180 poll_interval 5
    </pre>
	<pre>
      define BMP180 I2C_BMP180
      attr BMP180 IODev RPiI2CMod
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

=begin html_DE

<a name="I2C_BMP180"></a>
<h3>I2C_BMP180</h3>
<ul>
  <a name="I2C_BMP180"></a>
    <p>
    Dieses Modul erm&ouml;glicht das Auslesen der digitalen (Luft)drucksensoren
    BMP085 und BMP180 &uuml;ber den I2C Bus des Raspberry Pi.<br><br>
    <b>Es gibt zwei M&ouml;glichkeiten das Modul mit dem I2C Bus zu verbinden:</b><br>
	<ul>
	<li><b>&Uuml;ber das RPII2C Modul</b><br>
		I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
		<b>Das Attribut IODev muss definiert sein.</b><br><br>
	</li>
	<li><b>&Uuml;ber die HiPi Bibliothek</b><br>	
		Diese beiden Zeilen m&uuml;ssen in die Datei <b>/etc/modules</b> angef&uuml;gt werden,
		um die Kernel Module automatisch beim Booten des Raspberry Pis zu laden.<br>
		<code><pre>	i2c-bcm2708 
        i2c-dev</pre></code>
		Installation des HiPi Perl Moduls:<br>
		<code><pre>	wget http://raspberry.znix.com/hipifiles/hipi-install
        perl hipi-install</pre></code>
		Um die Rechte f&uuml;r die I2C Devices anzupassen, folgende Datei:<br>
		<code><pre>	/etc/udev/rules.d/98_i2c.rules</pre></code>
		mit diesem Inhalt anlegen:<br>
		<code><pre>	SUBSYSTEM=="i2c-dev", MODE="0666"</pre></code>
		<b>Reboot</b><br><br>
		Falls der Sensor am zweiten I2C Bus am Stecker P5 (nur in Version 2 des
		Raspberry Pi) verwendet werden soll, muss die fett gedruckte Zeile
		des folgenden Codes in das FHEM Start Skript aufgenommen werden:
		<code><pre>	case "$1" in
        'start')
        <b>sudo hipi-i2c e 0 1</b>
        ...</pre></code>
	</li></ul>
  <p>
  
  <b>Define</b>
  <ul>
    <code>define BMP180 &lt;BMP180_name&gt; &lt;I2C_device&gt;</code><br><br>
	&lt;I2C device&gt; darf nicht verwendet werden, wenn der I2C Bus &uuml;ber das RPII2C Modul angesprochen wird. For HiPi ist es allerdings notwendig. <br>
    <br>
    Beispiel:
    <pre>
      define BMP180 I2C_BMP180 /dev/i2c-0
      attr BMP180 oversampling_settings 3
      attr BMP180 poll_interval 5
    </pre>
	<pre>
      define BMP180 I2C_BMP180
      attr BMP180 IODev RPiI2CMod
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

=head1
	51_I2C_TSL2561.pm

=head1 SYNOPSIS
	Modul for FHEM for reading a TSL2561 luminosity sensor via I2C
	connected to the Raspberry Pi.

	contributed by Kai Stuke 2014
	$Id$

=head1 DESCRIPTION
	51_I2C_TSL2561.pm reads the luminosity of the digital luminosity sensor TSL2561
	via i2c bus connected to the Raspberry Pi.

	This module needs the HiPi Perl Modules
	see: http://raspberrypi.znix.com/hipidocs/
	
	For a simple automated installation:<br>
	wget http://raspberry.znix.com/hipifiles/hipi-install
	perl hipi-install

	Example:
	define Luminosity I2C_TSL2561 /dev/i2c-0 0x39
	attr Luminosity poll_interval 5

=head1 CAVEATS
	Make sure that the user fhem.pl is running as has read/write access to the i2c device file
	(e.g. /dev/i2c-0).
	This can be achieved by adding the user to the group i2c (sudo usermod -G i2c -a fhem).
	
	The pinout of the i2c-bus pins differs between revision 1 and revision 2 Raspberry Pi Model B boards.
	On revision 1, only bus 0 is accessible, on revision 2 bus 1 is connected to the standard pin header instead.
	
	There is a problem with newer kernel versions (>3.9?) when both i2c and 1-wire are used.
	If i2cdetect shows devices on all addresses you are affected by this bug.
	To avoid this the kernel modules must be loaded in a specific order.
	
	Try these settings in /etc/modules
		w1_therm
		w1-gpio
		i2c-dev
		i2c-bcm2708
		snd-bcm2835

	and in /etc/modprobe.d/raspi-blacklist.conf
		blacklist spi-bcm2708
		blacklist i2c-bcm2708

	
	
=head1 CREDITS
	Based on the module 51_I2C_BMP180.pm by Dirk Hoffmann
	TSL2651 specific code based on the python module by schwabbel as posted on 
	http://forums.adafruit.com/viewtopic.php?f=8&t=34922&start=75
	which in turn is based on the code by Adafruit
	https://github.com/adafruit/Adafruit_TSL2561
	Lux calculation algorithm is based on the code in the TSL2561 datasheet
	http://www.adafruit.com/datasheets/TSL2561.pdf
	newer version
	http://www.ams.com/eng/content/download/250094/975485/142937
	
=head1 AUTHOR - Kai Stuke
	kaihs@FHEM_Forum (forum.fhem.de)

=cut

package main;

use strict;
use warnings;

use HiPi::Device::I2C;
use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
use Error qw(:try);


use constant {
	TSL2561_VISIBLE           =>2,       # channel 0 - channel 1,
	TSL2561_INFRARED          =>1,       # channel 1,
	TSL2561_FULLSPECTRUM      =>0,       # channel 0,

	# I2C address options
	TSL2561_ADDR_LOW          => '0x29',
	TSL2561_ADDR_FLOAT        => '0x39',    # Default address (pin left floating)
	TSL2561_ADDR_HIGH         => '0x49',

	# Lux calculations differ slightly for CS package
	TSL2561_PACKAGE_CS        =>0b0001,
	TSL2561_PACKAGE_T_FN_CL   =>0b0101,

	TSL2561_COMMAND_BIT       =>0x80,    # Must be 1,
	TSL2561_CLEAR_BIT         =>0x40,    # Clears any pending interrupt (write 1 to clear)
	TSL2561_WORD_BIT          =>0x20,    # 1 = read/write word (rather than byte)
	TSL2561_BLOCK_BIT         =>0x10,    # 1 = using block read/write

	TSL2561_CONTROL_POWERON   =>0x03,
	TSL2561_CONTROL_POWEROFF  =>0x00,

	TSL2561_LUX_LUXSCALE      =>14,      # Scale by 2^14,
	TSL2561_LUX_RATIOSCALE    =>9,       # Scale ratio by 2^9,
	TSL2561_LUX_CHSCALE       =>10,      # Scale channel values by 2^10,
	TSL2561_LUX_CHSCALE_TINT0 =>0x7517,  # 322/11 * 2^TSL2561_LUX_CHSCALE
	TSL2561_LUX_CHSCALE_TINT1 =>0x0FE7,  # 322/81 * 2^TSL2561_LUX_CHSCALE

	# T, FN and CL package values
	TSL2561_LUX_K1T           =>0x0040,  # 0.125 * 2^RATIO_SCALE
	TSL2561_LUX_B1T           =>0x01f2,  # 0.0304 * 2^LUX_SCALE
	TSL2561_LUX_M1T           =>0x01be,  # 0.0272, * 2^LUX_SCALE
	TSL2561_LUX_K2T           =>0x0080,  # 0.250 * 2^RATIO_SCALE
	TSL2561_LUX_B2T           =>0x0214,  # 0.0325 * 2^LUX_SCALE
	TSL2561_LUX_M2T           =>0x02d1,  # 0.0440 * 2^LUX_SCALE
	TSL2561_LUX_K3T           =>0x00c0,  # 0.375 * 2^RATIO_SCALE
	TSL2561_LUX_B3T           =>0x023f,  # 0.0351, * 2^LUX_SCALE
	TSL2561_LUX_M3T           =>0x037b,  # 0.0544, * 2^LUX_SCALE
	TSL2561_LUX_K4T           =>0x0100,  # 0.50 * 2^RATIO_SCALE
	TSL2561_LUX_B4T           =>0x0270,  # 0.0381 * 2^LUX_SCALE
	TSL2561_LUX_M4T           =>0x03fe,  # 0.0624, * 2^LUX_SCALE
	TSL2561_LUX_K5T           =>0x0138,  # 0.61 * 2^RATIO_SCALE
	TSL2561_LUX_B5T           =>0x016f,  # 0.0224, * 2^LUX_SCALE
	TSL2561_LUX_M5T           =>0x01fc,  # 0.0310, * 2^LUX_SCALE
	TSL2561_LUX_K6T           =>0x019a,  # 0.80, * 2^RATIO_SCALE
	TSL2561_LUX_B6T           =>0x00d2,  # 0.0128 * 2^LUX_SCALE
	TSL2561_LUX_M6T           =>0x00fb,  # 0.0153, * 2^LUX_SCALE
	TSL2561_LUX_K7T           =>0x029a,  # 1.3, * 2^RATIO_SCALE
	TSL2561_LUX_B7T           =>0x0018,  # 0.00146 * 2^LUX_SCALE
	TSL2561_LUX_M7T           =>0x0012,  # 0.00112 * 2^LUX_SCALE
	TSL2561_LUX_K8T           =>0x029a,  # 1.3, * 2^RATIO_SCALE
	TSL2561_LUX_B8T           =>0x0000,  # 0.000 * 2^LUX_SCALE
	TSL2561_LUX_M8T           =>0x0000,  # 0.000 * 2^LUX_SCALE
   
	# CS package values
	TSL2561_LUX_K1C           =>0x0043,  # 0.130 * 2^RATIO_SCALE
	TSL2561_LUX_B1C           =>0x0204,  # 0.0315 * 2^LUX_SCALE
	TSL2561_LUX_M1C           =>0x01ad,  # 0.0262, * 2^LUX_SCALE
	TSL2561_LUX_K2C           =>0x0085,  # 0.260 * 2^RATIO_SCALE
	TSL2561_LUX_B2C           =>0x0228,  # 0.0337 * 2^LUX_SCALE
	TSL2561_LUX_M2C           =>0x02c1,  # 0.0430 * 2^LUX_SCALE
	TSL2561_LUX_K3C           =>0x00c8,  # 0.390 * 2^RATIO_SCALE
	TSL2561_LUX_B3C           =>0x0253,  # 0.0363 * 2^LUX_SCALE
	TSL2561_LUX_M3C           =>0x0363,  # 0.0529 * 2^LUX_SCALE
	TSL2561_LUX_K4C           =>0x010a,  # 0.520, * 2^RATIO_SCALE
	TSL2561_LUX_B4C           =>0x0282,  # 0.0392 * 2^LUX_SCALE
	TSL2561_LUX_M4C           =>0x03df,  # 0.0605, * 2^LUX_SCALE
	TSL2561_LUX_K5C           =>0x014d,  # 0.65, * 2^RATIO_SCALE
	TSL2561_LUX_B5C           =>0x0177,  # 0.0229 * 2^LUX_SCALE
	TSL2561_LUX_M5C           =>0x01dd,  # 0.0291, * 2^LUX_SCALE
	TSL2561_LUX_K6C           =>0x019a,  # 0.80, * 2^RATIO_SCALE
	TSL2561_LUX_B6C           =>0x0101,  # 0.0157 * 2^LUX_SCALE
	TSL2561_LUX_M6C           =>0x0127,  # 0.0180 * 2^LUX_SCALE
	TSL2561_LUX_K7C           =>0x029a,  # 1.3, * 2^RATIO_SCALE
	TSL2561_LUX_B7C           =>0x0037,  # 0.00338 * 2^LUX_SCALE
	TSL2561_LUX_M7C           =>0x002b,  # 0.00260, * 2^LUX_SCALE
	TSL2561_LUX_K8C           =>0x029a,  # 1.3, * 2^RATIO_SCALE
	TSL2561_LUX_B8C           =>0x0000,  # 0.000 * 2^LUX_SCALE
	TSL2561_LUX_M8C           =>0x0000,  # 0.000 * 2^LUX_SCALE

	# Auto-gain thresholds
	TSL2561_AGC_THI_13MS      =>4850,    # Max value at Ti 13ms = 5047,
	TSL2561_AGC_TLO_13MS      =>100,
	TSL2561_AGC_THI_101MS     =>36000,   # Max value at Ti 101ms = 37177,
	TSL2561_AGC_TLO_101MS     =>200,
	TSL2561_AGC_THI_402MS     =>63000,   # Max value at Ti 402ms = 65535,
	TSL2561_AGC_TLO_402MS     =>500,

	# Clipping thresholds
	TSL2561_CLIPPING_13MS     =>4900,
	TSL2561_CLIPPING_101MS    =>37000,
	TSL2561_CLIPPING_402MS    =>65000,

	TSL2561_REGISTER_CONTROL          => 0x00,
	TSL2561_REGISTER_TIMING           => 0x01,
	TSL2561_REGISTER_THRESHHOLDL_LOW  => 0x02,
	TSL2561_REGISTER_THRESHHOLDL_HIGH => 0x03,
	TSL2561_REGISTER_THRESHHOLDH_LOW  => 0x04,
	TSL2561_REGISTER_THRESHHOLDH_HIGH => 0x05,
	TSL2561_REGISTER_INTERRUPT        => 0x06,
	TSL2561_REGISTER_CRC              => 0x08,
	TSL2561_REGISTER_ID               => 0x0A,
	TSL2561_REGISTER_CHAN0_LOW        => 0x0C,
	TSL2561_REGISTER_CHAN0_HIGH       => 0x0D,
	TSL2561_REGISTER_CHAN1_LOW        => 0x0E,
	TSL2561_REGISTER_CHAN1_HIGH       => 0x0F,
   
	TSL2561_INTEGRATIONTIME_13MS      => 0x00,    # 13.7ms
	TSL2561_INTEGRATIONTIME_101MS     => 0x01,    # 101ms
	TSL2561_INTEGRATIONTIME_402MS     => 0x02,    # 402ms
   
	TSL2561_GAIN_1X                   => 0x00,    # No gain
	TSL2561_GAIN_16X                  => 0x10,    # 16x gain
	
};

##################################################
# Forward declarations
#
sub I2C_TSL2561_Initialize($);
sub I2C_TSL2561_Define($$);
sub I2C_TSL2561_Attr(@);
sub I2C_TSL2561_Poll($);
sub I2C_TSL2561_Set($@);
sub I2C_TSL2561_Get($);
sub I2C_TSL2561_Undef($$);
sub I2C_TSL2561_ReadWord($$);
sub I2C_TSL2561_ReadByte($$);
sub I2C_TSL2561_Enable($);
sub I2C_TSL2561_Disable($);
sub I2C_TSL2561_GetData($);
sub I2C_TSL2561_SetIntegrationTime($$);
sub I2C_TSL2561_SetGain($$);
sub I2C_TSL2561_GetLuminosity($);
sub I2C_TSL2561_CalculateLux($);

my %sets = (
	'gain' => "",
	'integrationTime' => "",
	'autoGain' => "",
);

my %gets = (
	"luminosity" => "",
	"broadband" => "",
	"ir" => "",
);

my %validAdresses = (
	"0x29" => TSL2561_ADDR_LOW,
	"0x39" => TSL2561_ADDR_FLOAT, 
	"0x49" => TSL2561_ADDR_HIGH
);

my %validPackages = (
	"CS" => TSL2561_PACKAGE_CS,
	"T" => TSL2561_PACKAGE_T_FN_CL,
	"FN" => TSL2561_PACKAGE_T_FN_CL,
	"CL" => TSL2561_PACKAGE_T_FN_CL,
);

=head2 I2C_TSL2561_Initialize
	Title:		I2C_TSL2561_Initialize
	Function:	Implements the initialize function.
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub I2C_TSL2561_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_TSL2561_Define';
	$hash->{AttrFn}   = 'I2C_TSL2561_Attr';
	#$hash->{SetFn}    = 'I2C_TSL2561_Set';
	$hash->{GetFn}    = 'I2C_TSL2561_Get';
	$hash->{UndefFn}  = 'I2C_TSL2561_Undef';

	$hash->{AttrList} = 'do_not_notify:0,1 showtime:0,1 ' .
	                    'loglevel:0,1,2,3,4,5,6 poll_interval:1,2,5,10,20,30 ' .
	                    'gain:1,16 integrationTime:13,101,402 autoGain:0,1 ' . $readingFnAttributes;
	$hash->{tsl2561IntegrationTime} = TSL2561_INTEGRATIONTIME_13MS;
	$hash->{tsl2561Gain} = TSL2561_GAIN_1X;
	$hash->{tsl2561AutoGain} = 1;
}

=head2 I2C_TSL2561_Define
	Title:		I2C_TSL2561_Define
	Function:	Implements the define function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash
				-argument2 => string

=cut

sub I2C_TSL2561_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	my $name = $a[0];
	my $dev = $a[2];
	my $address = lc $a[3];

	Log3 $name, 5, "I2C_TSL2561_Define start";
	my $msg = '';
	if( (@a < 4)) {
		$msg = 'wrong syntax: define <name> I2C_TSL2561 devicename address';
		return undef;
	} 
	
	$hash->{address} = $validAdresses{$address};
	if (!defined($hash->{address})) {
	        $msg = 'Wrong address, must be one of 0x29, 0x39, 0x49';
	        return undef;
	}

	# create default attributes
	$msg = CommandAttr(undef, $name . ' poll_interval 5');
	#$msg = CommandAttr(undef, $name . ' gain 1');
	#$msg = CommandAttr(undef, $name . ' integrationTime 13');

	if ($msg) {
		Log (1, $msg);
		return $msg;
	}
	
	# check for existing i2c device
	my $i2cModulesLoaded = 0;
	$i2cModulesLoaded = 1 if -e $dev;

	if ($i2cModulesLoaded) {
		if (-r $dev && -w $dev) {
			$hash->{devTSL2561} = HiPi::Device::I2C->new( 
				devicename	=> $dev,
				address		=> hex($address),
				busmode		=> 'i2c',
			);
			Log3 $name, 3, "I2C_TSL2561_Define device created";
			
			# Make sure we're actually connected
			
			my $sensorId = I2C_TSL2561_ReadByte($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_ID);
			if ( !($sensorId & 0b00010000) ) {
				return $name . ': Error! I2C failure: Please check your i2c bus ' . $dev . ' and the connected device address: ' . $address;
			}
			my $package = '';
			$hash->{tsl2561Package} = $sensorId >> 4;
			if ($hash->{tsl2561Package} == TSL2561_PACKAGE_CS) {
				$package = 'CS';
			} else {
				$package = 'T/FN/CL';
			}
			$hash->{sensorType} = 'TSL2561 Package' . $package . ' Rev. ' . ( $sensorId & 0x0f );
			
			Log3 $name, 5, 'sensorId ' . $hash->{sensorType}; 
		
			$hash->{tsl2561IntegrationTime} = TSL2561_INTEGRATIONTIME_13MS;
			$hash->{tsl2561Gain} = TSL2561_GAIN_1X;
			
			I2C_TSL2561_SetIntegrationTime($hash,TSL2561_INTEGRATIONTIME_13MS);
			I2C_TSL2561_SetGain($hash, TSL2561_GAIN_1X);
			readingsSingleUpdate($hash, 'state', 'Initialized',1);
		} else {
			my @groups = split '\s', $(;
			return "$name :Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " . 
				getgrgid($_) . " " foreach(@groups); 
		}
		
	} else {
		return $name . ': Error! I2C device not found: ' . $dev . '. Please check that these kernelmodules are loaded: i2c_bcm2708, i2c_dev';
	}
	Log3 $name, 5, "I2C_TSL2561_Define end";
	
	return undef;
}

=head2 I2C_TSL2561_Attr
	Title:		I2C_TSL2561_Attr
	Function:	Implements AttrFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => array

=cut

sub I2C_TSL2561_Attr (@) {
	my (undef, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	Log3 $name, 5, "I2C_TSL2561_Attr: attr " . $attr . " val " . $val; 
	if ($attr eq 'poll_interval') {
		my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		
		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_TSL2561_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
        } elsif ($attr eq 'gain') {
		my $gain = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		
		Log3 $name, 5, "attr gain is" . $gain;
		if ($gain == 1) {
		        I2C_TSL2561_SetGain($hash, TSL2561_GAIN_1X);
		} elsif ($gain == 16) {
		        I2C_TSL2561_SetGain($hash, TSL2561_GAIN_16X);
		} else {
			$msg = 'Wrong gain defined. must be 1 or 16';
		}
	} elsif ($attr eq 'integrationTime') {
		my $time = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		
		if ($time == 13) {
		        I2C_TSL2561_SetIntegrationTime($hash, TSL2561_INTEGRATIONTIME_13MS);
		} elsif ($time == 101) {
		        I2C_TSL2561_SetIntegrationTime($hash, TSL2561_INTEGRATIONTIME_101MS);
		} elsif ($time == 402) {
		        I2C_TSL2561_SetIntegrationTime($hash, TSL2561_INTEGRATIONTIME_402MS);
		} else {
			$msg = 'Wrong integrationTime defined. must be 13 or 101 or 402';
		}
	} elsif ($attr eq 'autoGain') {
		my $autoGain = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
		
		$hash->{tsl2561AutoGain} = $autoGain;
	}	

	return ($msg) ? $msg : undef;
}

=head2 I2C_TSL2561_Poll
	Title:		I2C_TSL2561_Poll
	Function:	Start polling the sensor at interval defined in attribute
	Returns:	-
	Args:		named arguments:
				-argument1 => hash

=cut

sub I2C_TSL2561_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	# Read values
	I2C_TSL2561_Get($hash);
	
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_TSL2561_Poll', $hash, 0);
	}
}

=head2 I2C_TSL2561_Get
	Title:		I2C_TSL2561_Get
	Function:	Implements GetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub I2C_TSL2561_Get($) {
	my ( $hash ) = @_;
	my $name = $hash->{NAME};
	
	my $lux = I2C_TSL2561_CalculateLux($hash);
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash,"luminosity",$lux);
	readingsBulkUpdate($hash,"broadband",$hash->{broadband});
	readingsBulkUpdate($hash,"ir",$hash->{ir});
	readingsEndUpdate($hash,1);
		
	#readingsSingleUpdate($hash,"failures",ReadingsVal($hash->{NAME},"failures",0)+1,1); 

}

=head2 I2C_TSL2561_Set
	Title:		I2C_TSL2561_Set
	Function:	Implements SetFn function.
	Returns:	string|undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub I2C_TSL2561_Set($@) {
	my ($hash, @a) = @_;

	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}
	
	if ($cmd eq 'readValues') {

	} 
}

=head2 I2C_TSL2561_Undef
	Title:		I2C_TSL2561_Undef
	Function:	Implements UndefFn function.
	Returns:	undef
	Args:		named arguments:
				-argument1 => hash:		$hash	hash of device
				-argument2 => array:	@a		argument array

=cut

sub I2C_TSL2561_Undef($$) {
	my ($hash, $arg) = @_;
	
	RemoveInternalTimer($hash);
	$hash->{devTSL2561}->close( ).
	return undef;
}

=head2 I2C_TSL2561_ReadWord
	Title:		I2C_TSL2561_ReadWord
	Function:	Read 2 bytes from i2c device from given register.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash			hash of device
				-argument2 => number:	$register

=cut

sub I2C_TSL2561_ReadWord($$) {
	my ($hash, $register) = @_;
	my $name = $hash->{NAME};
	
	my $retVal = undef;

	try {
		my @values = $hash->{devTSL2561}->bus_read($register, 2);

		$retVal = $values[0] | $values[1] << 8;
		
	} catch Error with {
		Log3 $name, 1, 'ERROR: I2C_TSL2561_ReadWord: i2c-bus_read failure';
	};  
	
	return $retVal;
}

=head2 I2C_TSL2561_ReadByte
	Title:		I2C_TSL2561_ReadByte
	Function:	Read 1 byte from i2c device from given register.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:	$hash			hash of device
				-argument2 => number:	$register

=cut

sub I2C_TSL2561_ReadByte($$) {
	my ($hash, $register) = @_;
	my $name = $hash->{NAME};
	
	my $retVal = undef;

	try {
		Log3 $name, 5,'I2C_TSL2561_ReadByte: start ';
		my @bytes = $hash->{devTSL2561}->bus_read($register, 1);
		$retVal = $bytes[0];

		Log3 $name, 5, 'I2C_TSL2561_ReadByte: ' . $retVal;
	} catch Error with {
		Log3 $name, 1, 'ERROR: I2C_TSL2561_ReadByte: i2c-bus_read failure';
	};  
	
	return $retVal;
}


=head2 I2C_TSL2561_Enable
	Title:		I2C_TSL2561_Enable
	Function:	Enables the device
	Returns:	-
	Args:		named arguments:
				-argument1 => hash:	$hash			hash of device

=cut

sub I2C_TSL2561_Enable($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $enabled = 0;
	
	Log3 $name, 5, 'I2C_TSL2561_Enable: start ';
	try {
		$hash->{devTSL2561}->bus_write( TSL2561_COMMAND_BIT | TSL2561_REGISTER_CONTROL, TSL2561_CONTROL_POWERON );
		$enabled = I2C_TSL2561_ReadByte( $hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_CONTROL);
		if ($enabled == TSL2561_CONTROL_POWERON) {
			Log3 $name, 5, "I2C_TSL2561_Enable: is enabled";
		} else {
			Log3 $name, 5, "I2C_TSL2561_Enable: is not enabled";
			readingsSingleUpdate($hash, 'state', 'Error',1);
		}
	} catch Error with {
		Log3 $name, 1, 'ERROR: I2C_TSL2561_Enable: i2c-bus_write failure';
	};  
	Log3 $name, 5, 'I2C_TSL2561_Enable: end ';
	return $enabled;
}

=head2 I2C_TSL2561_Disable
	Title:		I2C_TSL2561_Disable
	Function:	Enables the device
	Returns:	-
	Args:		named arguments:
				-argument1 => hash:	$hash			hash of device

=cut

sub I2C_TSL2561_Disable($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	

	Log3 $name, 5, 'I2C_TSL2561_Disable: start ';
	try {
	        $hash->{devTSL2561}->bus_write( (TSL2561_COMMAND_BIT | TSL2561_REGISTER_CONTROL, TSL2561_CONTROL_POWEROFF) );
	} catch Error with {
		Log (1, $name . ': ERROR: I2C_TSL2561_Disable: i2c-bus_write failure');
	}
	Log3 $name, 5, 'I2C_TSL2561_Disable: end ';
}

=head2 I2C_TSL2561_GetData
	Title:		I2C_TSL2561_GetData
	Function:	Private function to read luminosity on both channels
	Returns:	-
	Args:		named arguments:
				-argument1 => hash:	$hash			hash of device

=cut

sub I2C_TSL2561_GetData($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	# Enable the device by setting the control bit to 0x03
	I2C_TSL2561_Enable( $hash );

	# Wait x ms for ADC to complete
	if ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS) {
	    usleep(14000); # 14ms
	} elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS) {
	    usleep(102000); # 102ms
	} else {
	    usleep(403000); # 403ms
	}
	
        # Reads a two byte value from channel 0 (visible + infrared) 
        $hash->{broadband} = I2C_TSL2561_ReadWord($hash, TSL2561_COMMAND_BIT | TSL2561_WORD_BIT | TSL2561_REGISTER_CHAN0_LOW);

        # Reads a two byte value from channel 1 (infrared) 
        $hash->{ir} = I2C_TSL2561_ReadWord($hash, TSL2561_COMMAND_BIT | TSL2561_WORD_BIT | TSL2561_REGISTER_CHAN1_LOW);
        
        # Turn the device off to save power 
        I2C_TSL2561_Disable( $hash );	    
}

=head2 I2C_TSL2561_SetIntegrationTime
	Title:		I2C_TSL2561_SetIntegrationTime
	Function:	Sets the integration time for the TSL2561
	Returns:	-
	Args:		named arguments:
				-argument1 => hash:	$hash		hash of device
				-argument1 => number:	$time		constant for integration time setting

=cut

sub I2C_TSL2561_SetIntegrationTime($$) {
	my ($hash, $time) = @_;
	my $name = $hash->{NAME};
	
	# Enable the device by setting the control bit to 0x03
	I2C_TSL2561_Enable( $hash );

	#try {
                # Update the timing register 
		Log3 $name, 5, "I2C_TSL2561_SetIntegrationTime: time is " . $time ;
                Log3 $name, 5, "I2C_TSL2561_SetIntegrationTime: gain is " . $hash->{tsl2561Gain};
	        $hash->{devTSL2561}->bus_write( (TSL2561_COMMAND_BIT | TSL2561_REGISTER_TIMING, $time | $hash->{tsl2561Gain}) );
	#} catch Error with {
	#	Log3 $name, 1, 'ERROR: I2C_TSL2561_SetIntegrationTime: i2c-bus_write failure';
	#}
        # Update value placeholders 
        $hash->{tsl2561IntegrationTime} = $time;
        
        # Turn the device off to save power 
        I2C_TSL2561_Disable( $hash );    
}

=head2 I2C_TSL2561_SetGain
	Title:		I2C_TSL2561_SetGain
	Function:	 Adjusts the gain on the TSL2561 (adjusts the sensitivity to light)
	Returns:	-
	Args:		named arguments:
				-argument1 => hash:	$hash		hash of device
				-argument1 => number:	$gain		constant for gain

=cut

sub I2C_TSL2561_SetGain($$) {
	my ($hash, $gain) = @_;
	my $name = $hash->{NAME};
	my $timing = 0;
	
	# Enable the device by setting the control bit to 0x03
	I2C_TSL2561_Enable( $hash );

	#try {
		Log3 $name, 5, 'I2C_TSL2561_SetGain: gain is ' . $gain;
                Log3 $name, 5, 'I2C_TSL2561_SetGain: time is ' . $hash->{tsl2561IntegrationTime};
                $timing = $gain | $hash->{tsl2561IntegrationTime};
                Log3 $name, 5, ' I2C_TSL2561_SetGain: timing is ' . sprintf("%x", $timing);
                # Update the timing register 
	        my $ret = $hash->{devTSL2561}->bus_write( (TSL2561_COMMAND_BIT | TSL2561_REGISTER_TIMING, $timing) );
	        Log3 $name, 5, "I2C_TSL2561_SetGain: return from write is " . sprintf("%x", $ret);
	        $ret = I2C_TSL2561_ReadByte($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_TIMING );
	        Log3 $name, 5, "I2C_TSL2561_SetGain: register read is " . sprintf("%x", $ret);
	#} catch Error with {
	#	Log3 $name, 1,'ERROR: I2C_TSL2561_SetGain: i2c-bus_write failure';
	#}
        # Update value placeholders 
        $hash->{tsl2561Gain} = $gain;
        
        # Turn the device off to save power 
        I2C_TSL2561_Disable( $hash );    
}

=head2 I2C_TSL2561_GetLuminosity
	Title:		I2C_TSL2561_GetLuminosity
	Function:	Gets the broadband (mixed lighting) and IR only values from the TSL2561, adjusting gain if auto-gain is enabled
	Returns:	luminosity
	Args:		named arguments:
				-argument1 => hash:	$hash		hash of device

=cut

sub I2C_TSL2561_GetLuminosity($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $valid = 0;

        # If Auto gain disabled get a single reading and continue
	if ($hash->{tsl2561AutoGain}) {
	  I2C_TSL2561_GetData($hash);
	  return;
	}

        # Read data until we find a valid range 
        my $agcCheck = 0;
        my $hi = 0;
        my $lo = 0;
        my $it = 0;
        my $lux = 0;
        while (!$valid) {
            $it = $hash->{tsl2561IntegrationTime};

            # Get the hi/low threshold for the current integration time
            if ($it==TSL2561_INTEGRATIONTIME_13MS) {
                $hi = TSL2561_AGC_THI_13MS;
                $lo = TSL2561_AGC_TLO_13MS;
            } elsif ( $it==TSL2561_INTEGRATIONTIME_101MS) {
                $hi = TSL2561_AGC_THI_101MS;
                $lo = TSL2561_AGC_TLO_101MS;
            } else {
                $hi = TSL2561_AGC_THI_402MS;
                $lo = TSL2561_AGC_TLO_402MS;
            }

            I2C_TSL2561_GetData($hash);

            # Run an auto-gain check if we haven't already done so ... 
            if ($agcCheck) {
                if (($hash->{broadband} < $lo) && ($hash->{tsl2561Gain} == TSL2561_GAIN_1X)) {
                    # Increase the gain and try again 
                    I2C_TSL2561_SetGain($hash, TSL2561_GAIN_16X);
                    # Drop the previous conversion results 
                    I2C_TSL2561_GetData($hash);
                    # Set a flag to indicate we've adjusted the gain 
                    $agcCheck = 1;
                } elsif (($hash->{broadband} > $hi) && ($hash->{tsl2561Gain} == TSL2561_GAIN_16X)) {
                    # Drop gain to 1x and try again 
                    I2C_TSL2561_SetGain($hash, TSL2561_GAIN_1X);
                    # Drop the previous conversion results 
                    I2C_TSL2561_GetData($hash);
                    # Set a flag to indicate we've adjusted the gain 
                    $agcCheck = 1;
                } else {
                    # Nothing to look at here, keep moving ....
                    # Reading is either valid, or we're already at the chips limits 
                    $valid = 1;
                }
            } else {
                # If we've already adjusted the gain once, just return the new results.
                # This avoids endless loops where a value is at one extreme pre-gain,
                # and the the other extreme post-gain 
                $valid = 1;
            }
      }
}

=head2 I2C_TSL2561_CalculateLux
	Title:		I2C_TSL2561_CalculateLux
	Function:	Converts the raw sensor values to the standard SI lux equivalent. Returns 0 if the sensor is saturated and the values are unreliable.
	Returns:	number
	Args:		named arguments:
				-argument1 => hash:		$hash			hash of device

=cut

sub I2C_TSL2561_CalculateLux($) {
	my ($hash) = @_;
        my $clipThreshold = 0;
        my $chScale = 0;
        
        I2C_TSL2561_GetLuminosity($hash);
        # Make sure the sensor isn't saturated! 
        if ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS) {
            $clipThreshold = TSL2561_CLIPPING_13MS;
        } elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS) {
            $clipThreshold = TSL2561_CLIPPING_101MS;
        } else {
            $clipThreshold = TSL2561_CLIPPING_402MS;
        }

        # Return 0 lux if the sensor is saturated 
        if (($hash->{broadband} > $clipThreshold) || ($hash->{ir} > $clipThreshold)) {
            readingsSingleUpdate($hash, 'state', 'Saturated',1);
            return 0;
        }

        # Get the correct scale depending on the integration time 
        if ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS) {
            $chScale = TSL2561_LUX_CHSCALE_TINT0;
        } elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS) {
            $chScale = TSL2561_LUX_CHSCALE_TINT1;
        } else {
            $chScale = (1 << TSL2561_LUX_CHSCALE);
        }

        # Scale for gain (1x or 16x) 
        if (!$hash->{tsl2561Gain}) {
            $chScale = $chScale << 4;
        }

        # Scale the channel values 
        my $channel0 = ($hash->{broadband} * $chScale) >> TSL2561_LUX_CHSCALE;
        my $channel1 = ($hash->{ir} * $chScale) >> TSL2561_LUX_CHSCALE;

        # Find the ratio of the channel values (Channel1/Channel0) 
        my $ratio1 = 0;
        if ($channel0 != 0) {
            $ratio1 = ($channel1 << (TSL2561_LUX_RATIOSCALE+1)) / $channel0;
        }

        # round the ratio value  
        my $ratio = ($ratio1 + 1) >> 1;
        
        my $b=0;
        my $m=0;

        if ($hash->{tsl2561Package} == TSL2561_PACKAGE_CS) {
	    #  CS package
            if (($ratio >= 0) && ($ratio <= TSL2561_LUX_K1C)) {
                $b=TSL2561_LUX_B1C;
                $m=TSL2561_LUX_M1C;
            } elsif ($ratio <= TSL2561_LUX_K2C) {
                $b=TSL2561_LUX_B2C;
                $m=TSL2561_LUX_M2C;
            } elsif ($ratio <= TSL2561_LUX_K3C) {
                $b=TSL2561_LUX_B3C;
                $m=TSL2561_LUX_M3C;
            } elsif ($ratio <= TSL2561_LUX_K4C) {
                $b=TSL2561_LUX_B4C;
                $m=TSL2561_LUX_M4C;
            } elsif ($ratio <= TSL2561_LUX_K5C) {
                $b=TSL2561_LUX_B5C;
                $m=TSL2561_LUX_M5C;
            } elsif ($ratio <= TSL2561_LUX_K6C) {
                $b=TSL2561_LUX_B6C;
                $m=TSL2561_LUX_M6C;
            } elsif ($ratio <= TSL2561_LUX_K7C) {
                $b=TSL2561_LUX_B7C;
                $m=TSL2561_LUX_M7C;
            } elsif ($ratio > TSL2561_LUX_K8C) {
                $b=TSL2561_LUX_B8C;
                $m=TSL2561_LUX_M8C;
            }
        } elsif ($hash->{tsl2561Package} == TSL2561_PACKAGE_T_FN_CL) {
            #  T, FN and CL package
            if (($ratio >= 0) && ($ratio <= TSL2561_LUX_K1T)) {
                $b=TSL2561_LUX_B1T;
                $m=TSL2561_LUX_M1T;
            } elsif ($ratio <= TSL2561_LUX_K2T) {
                $b=TSL2561_LUX_B2T;
                $m=TSL2561_LUX_M2T;
            } elsif ($ratio <= TSL2561_LUX_K3T) {
                $b=TSL2561_LUX_B3T;
                $m=TSL2561_LUX_M3T;
            } elsif ($ratio <= TSL2561_LUX_K4T) {
                $b=TSL2561_LUX_B4T;
                $m=TSL2561_LUX_M4T;
            } elsif ($ratio <= TSL2561_LUX_K5T) {
                $b=TSL2561_LUX_B5T;
                $m=TSL2561_LUX_M5T;
            } elsif ($ratio <= TSL2561_LUX_K6T) {
                $b=TSL2561_LUX_B6T;
                $m=TSL2561_LUX_M6T;
            } elsif ($ratio <= TSL2561_LUX_K7T) {
                $b=TSL2561_LUX_B7T;
                $m=TSL2561_LUX_M7T;
            } elsif ($ratio > TSL2561_LUX_K8T) {
                $b=TSL2561_LUX_B8T;
                $m=TSL2561_LUX_M8T;
            }
        }

        my $temp = (($channel0 * $b) - ($channel1 * $m));

        # Do not allow negative lux value 
        if ($temp < 0) {
            $temp = 0;
        }

        # Round lsb (2^(LUX_SCALE-1)) 
        $temp += (1 << (TSL2561_LUX_LUXSCALE-1));

        # Strip off fractional portion 
        my $lux = $temp >> TSL2561_LUX_LUXSCALE;

        # Signal I2C had no errors 
        return $lux;
}

1;

=pod
=begin html

<a name="I2C_TSL2561"></a>
<h3>I2C_TSL2561</h3>
<ul>
  <a name="I2C_TSL2561"></a>
  <p>
    With this module you can read values from the digital luminosity sensor TSL2561
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
    <code>define TSL2561 I2C_TSL2561 &lt;I2C device&gt; &lt;I2C address&gt</code><br>
    <br>
    Examples:
    <pre>
      define TSL2561 I2C_TSL2561 /dev/i2c-0 0x39
      attr TSL2561 poll_interval 5
    </pre>
  </ul>

  <a name="I2C_TSL2561attr"></a>
  <b>Attributes</b>
  <ul>
    <li>poll_interval<br>
      Set the polling interval in minutes to query the sensor for new measured
      values.<br>
      Default: 5, valid values: 1, 2, 5, 10, 20, 30<br><br>
    </li>
    <li>integrationTime<br>
      time in ms the sensor takes to measure the light.<br>
      Default: 13, valid values: 13, 101, 402
      see this <a href="https://learn.sparkfun.com/tutorials/tsl2561-luminosity-sensor-hookup-guide/using-the-arduino-library">tutorial</a>
      for more details
    </li>
    <li>gain<br>
      gain factor
      Default: 1, valid values: 1, 16
    </li>
    <li>autoGain<br>
      enable auto gain
      Default: 1, valid values: 0, 1
      if set to 1,the gain parameter is set automatically depending on light conditions
    </li>
</ul>
  <br>
</ul>


=end html

=cut

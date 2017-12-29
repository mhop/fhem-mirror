# $Id$
=head1
  51_I2C_TSL2561.pm

=head1 SYNOPSIS
  Modul for FHEM for reading a TSL2561 ambient light sensor via I2C
  connected to the Raspberry Pi.

  contributed by Kai Stuke 2014

=head1 DESCRIPTION
  51_I2C_TSL2561.pm reads the illumination of the the ambient light sensor TSL2561
  via i2c bus connected to the Raspberry Pi.

  This module needs IODev FHEM modules or the HiPi perl modules
  IODev see: <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a> or <a href="#NetzerI2C">NetzerI2C</a>
  HiPi see: http://raspberrypi.znix.com/hipidocs/
  
  For a simple automated installation of the HiPi perl modules:<br>
  wget http://raspberry.znix.com/hipifiles/hipi-install
  perl hipi-install

  HiPi Example:
  define Luminosity I2C_TSL2561 /dev/i2c-0 0x39
  attr Luminosity poll_interval 5
  
  IODev Example:
  define Luminosity I2C_TSL2561 0x39
  attr Luminosity IODev I2CModule
  attr Luminosity poll_interval 5
  
=head1 HiPi CAVEATS
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
  
=head1 CHANGES
  18.03.2015 jensb
    IODev support added as alternative to HiPi
    I2C error detection for IODev mode added 
    hotplug support (reinit TLS2561 afer each I2C error)
    luminosity calculation alternative with float arithmetic for improved precision, especially with ir ratio below 50% and below 10 lux (new default, can be disabled)
    scale readings 'broadband' and 'ir' with actual gain and integration time ratios to get values that can be directly used (e.g. for plots) 
    'luminosity', 'broadband' and 'ir' readings are not updated if state is 'Saturated' or 'I2C Error' so that timestamp of readings show last valid time
    attribute and reading restoration added in I2C_TSL2561_Define
    autoGain attribute inversion fix
    'Saturation' state freeze fix
  22.03.2015 jensb
    round luminosity to 3 significant digits or max. 1 fractional digit when float arithmetics are enabled
  11.04.2015 jensb
    unblock FHEM while waiting for end of integration time - this makes using long integration times preferable
    changing attribute 'gain' or 'integrationTime' no longer powers up the TSL2561
    attribute 'disable' added
    attribute 'autoIntegrationTime' added (decrease when measurement gets saturated, increase when value gets low)
    I2C auto address mode added for IODev to compensate floating address selection
    improved I2C read error handling for RPII2C IODev
  16.04.2015 jensb
    make scaling of readings 'broadband' and 'ir' depended on new attribute 'normalizeRawValues'
  18.04.2015 jensb
    new readings 'gain' and 'integrationTime'
  20.04.2015 jensb
    update reading 'state' in bulk along with luminosity when toggling between 'Initialized' and 'Saturated'
  17.11.2015 jensb
    register InitFn for IODev post initialization and do not init IOdev in Define if FHEM is not initialized
  19.12.2015 jensb
    constants renamed with module specific prefix
    state machines modified to become I2C read driven for Firmata compatibility (non-blocking I2C I/O)
    changing gain/integrationTime attributes will no longer write to device but will be used at next poll
  26.12.2015 kaihs
    CalculateLux float arithmetics formula fix
  02.01.2017 jensb
    inverted check of I2C IO result (not "Ok" instead of "error")
    
    
=head1 TODO
  manual integration time (optional)
  
=head1 CREDITS
  Based on the module 51_I2C_BMP180.pm by Dirk Hoffmann and Klaus Wittstock
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
  modified by Jens Beyer jensb@FHEM_Forum (forum.fhem.de)

=cut

package main;

use strict;
use warnings;

use Time::HiRes qw(tv_interval);
use Scalar::Util qw(looks_like_number);

use constant {
  # I2C address options
  TSL2561_ADDR_LOW          => '0x29',
  TSL2561_ADDR_FLOAT        => '0x39',    # Default address (pin left floating)
  TSL2561_ADDR_HIGH         => '0x49',
  TSL2561_ADDR_AUTO         => 'AUTO',

  # I2C registers
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
   
  # I2C register values
  TSL2561_COMMAND_BIT                  => 0x80,   # Must be 1,
  TSL2561_CLEAR_BIT                    => 0x40,   # Clears any pending interrupt (write 1 to clear)
  TSL2561_WORD_BIT                     => 0x20,   # 1 = read/write word (rather than byte)
  TSL2561_BLOCK_BIT                    => 0x10,   # 1 = using block read/write
  TSL2561_CONTROL_POWERON              => 0x03,
  TSL2561_CONTROL_POWEROFF             => 0x00,
  TSL2561_PACKAGE_CS                   => 0b0001,
  TSL2561_PACKAGE_T_FN_CL              => 0b0101,
  TSL2561_GAIN_1X                      => 0x00,   # No gain
  TSL2561_GAIN_16X                     => 0x10,   # 16x gain
  TSL2561_INTEGRATIONTIME_13MS         => 0x00,   # 13.7ms
  TSL2561_INTEGRATIONTIME_101MS        => 0x01,   # 101ms
  TSL2561_INTEGRATIONTIME_402MS        => 0x02,   # 402ms
  TSL2561_INTEGRATIONTIME_MANUAL_STOP  => 0x03,   # stop manual integration cycle (not implemented)
  TSL2561_INTEGRATIONTIME_MANUAL_START => 0x0b,   # start manual integration cycle (not implemented)

  # Auto-gain thresholds
  TSL2561_AGC_THI_13MS              => 4850,    # Max value at Ti 13.7ms = 5047,
  TSL2561_AGC_TLO_13MS              => 100,
  TSL2561_AGC_THI_101MS             => 36000,   # Max value at Ti 101ms = 37177,
  TSL2561_AGC_TLO_101MS             => 200,
  TSL2561_AGC_THI_402MS             => 63000,   # Max value at Ti 402ms = 65535,
  TSL2561_AGC_TLO_402MS             => 500,

  # Saturation clipping thresholds
  TSL2561_CLIPPING_13MS             => 4946,    # 2% below 13.7 ms max. of 5047
  TSL2561_CLIPPING_101MS            => 36433,   # 2% below 101 ms max. of 37177
  TSL2561_CLIPPING_402MS            => 64224,   # 2% below 402 ms max. of 65535
  
  # Lux calculations differ slightly for CS package
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

  TSL2561_STATE_UNDEFINED   => 'Undefined',
  TSL2561_STATE_DEFINED     => 'Defined',
  TSL2561_STATE_INITIALIZED => 'Initialized',
  TSL2561_STATE_SATURATED   => 'Saturated',
  TSL2561_STATE_I2C_ERROR   => 'I2C Error',
  TSL2561_STATE_DISABLED    => 'Disabled',
  
  TSL2561_ACQUI_STATE_IDLE              => 0,
  TSL2561_ACQUI_STATE_SETUP             => 1,
  TSL2561_ACQUI_STATE_ENABLE_REQUESTED  => 2,
  TSL2561_ACQUI_STATE_ENABLED           => 3,
  TSL2561_ACQUI_STATE_DATA_AVAILABLE    => 4,
  TSL2561_ACQUI_STATE_DATA_REQUESTED    => 5,
  TSL2561_ACQUI_STATE_DATA_CH0_RECEIVED => 6,
  TSL2561_ACQUI_STATE_DATA_CH1_RECEIVED => 7,
  TSL2561_ACQUI_STATE_ERROR             => 8,

  TSL2561_CALC_STATE_IDLE           => 0,
  TSL2561_CALC_STATE_DATA_REQUESTED => 1,
  TSL2561_CALC_STATE_DATA_RECEIVED  => 2,
  TSL2561_CALC_STATE_ERROR          => 3,
  TSL2561_CALC_STATE_COMPLETED      => 4,
  
  TSL2561_MAX_CONSECUTIVE_OPERATIONS => 20,
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
sub I2C_TSL2561_Enable($);
sub I2C_TSL2561_Disable($);
sub I2C_TSL2561_GetData($);
sub I2C_TSL2561_SetTimingRegister($);
sub I2C_TSL2561_SetIntegrationTime($$);
sub I2C_TSL2561_SetGain($$);
sub I2C_TSL2561_GetLuminosity($);
sub I2C_TSL2561_CalculateLux($);

my $libcheck_hasHiPi = 1;

my %sets = (
  "update" => "",
);

my %validAdresses = (
  "0x29" => TSL2561_ADDR_LOW,
  "0x39" => TSL2561_ADDR_FLOAT, 
  "0x49" => TSL2561_ADDR_HIGH,
  "auto" => TSL2561_ADDR_AUTO,
);

my %validPackages = (
  "CS" => TSL2561_PACKAGE_CS,
  "T"  => TSL2561_PACKAGE_T_FN_CL,
  "FN" => TSL2561_PACKAGE_T_FN_CL,
  "CL" => TSL2561_PACKAGE_T_FN_CL,
);

my @fsmSubs = (\&I2C_TSL2561_StartMeasurement, \&I2C_TSL2561_GetMeasurement);

=head2 I2C_TSL2561_Initialize
  Title:    I2C_TSL2561_Initialize
  Function:  Implements the initialize function.
  Returns:  -
  Args:    named arguments:
        -argument1 => hash

=cut

sub I2C_TSL2561_Initialize($) {
  my ($hash) = @_;
    
  eval "use HiPi::Device::I2C;";
  $libcheck_hasHiPi = 0 if($@);    

  $hash->{DefFn}    = 'I2C_TSL2561_Define';
  $hash->{InitFn}   = 'I2C_TSL2561_Init';
  $hash->{AttrFn}   = 'I2C_TSL2561_Attr';
  $hash->{SetFn}    = 'I2C_TSL2561_Set';
  $hash->{UndefFn}  = 'I2C_TSL2561_Undef';
  $hash->{I2CRecFn} = 'I2C_TSL2561_I2CRec';

  $hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 ' .
                      'loglevel:0,1,2,3,4,5,6 poll_interval:1,2,5,10,20,30 ' .
                      'gain:1,16 integrationTime:13,101,402 ' . 
                      'autoGain:0,1 autoIntegrationTime:0,1 normalizeRawValues:0,1 ' .
                      'floatArithmetics:0,1 disable:0,1 ' . $readingFnAttributes;
  $hash->{AttrList} .= " useHiPiLib:0,1 " if ($libcheck_hasHiPi);
}

sub I2C_TSL2561_Define($$) {
  my ($hash, $def) = @_;
  my @a = split('[ \t][ \t]*', $def);
  my $name = $a[0];
  my $device;
  
  readingsSingleUpdate($hash, 'state', TSL2561_STATE_UNDEFINED, 1);

  Log3 $name, 1, "I2C_TSL2561_Define start: " . @a . "/" . join(' ', @a);
  
  $hash->{HiPi_exists} = $libcheck_hasHiPi if ($libcheck_hasHiPi);    
  $hash->{HiPi_used} = 0;
  
  my $address = undef;
  my $msg = '';
  if (@a < 3) {
    $msg = 'wrong syntax: define <name> I2C_TSL2561 [devicename] address';
  } elsif (@a == 3) {
    $address = lc($a[2]);
  } else {
    $device = $a[2];
    $address = lc($a[3]);
    if ($libcheck_hasHiPi) {
      $hash->{HiPi_used} = 1;
      delete $validAdresses{'auto'};
    } else {
      $msg = '$name error: HiPi library not installed';
    }                
  }
  if ($msg) {
    Log3 ($hash, 1, $msg);
    return $msg;
  }    
  
  $address = $validAdresses{$address};
  if (!defined($address)) {
    $msg = "Wrong address, must be one of " . join(' ', keys %validAdresses);
    Log3 ($hash, 1, $msg);
    return $msg;
  }
  
  if ($address eq TSL2561_ADDR_AUTO) {
    # start with lowest address in auto mode
    $hash->{autoAddress} = 1;
    $address = TSL2561_ADDR_LOW;
  } else {
    $hash->{autoAddress} = 0;
  }
  if ($hash->{HiPi_used}) {
    $hash->{autoAddress} = 0;
  }
  $hash->{I2C_Address} = hex($address);
  
  # create default attributes
  if (AttrVal($name, 'poll_interval', '?') eq '?') {  
    $msg = CommandAttr(undef, $name . ' poll_interval 5');
    if ($msg) {
      Log (1, $msg);
      return $msg;
    }
  }
  if (AttrVal($name, 'floatArithmetics', '?') eq '?') {  
    $msg = CommandAttr(undef, $name . ' floatArithmetics 1');
    if ($msg) {
      Log (1, $msg);
      return $msg;
    }
  }
  
  # preset some internal readings
  if (!defined($hash->{tsl2561IntegrationTime})) {
    my $attrVal = AttrVal($name, 'integrationTime', 13);  
    $hash->{tsl2561IntegrationTime} = $attrVal == 402? TSL2561_INTEGRATIONTIME_402MS : $attrVal == 101? TSL2561_INTEGRATIONTIME_101MS : TSL2561_INTEGRATIONTIME_13MS;
  }
  if (!defined($hash->{tsl2561Gain})) {
    my $attrVal = AttrVal($name, 'gain', 1);
    $hash->{tsl2561Gain} = $attrVal == 16? TSL2561_GAIN_16X : TSL2561_GAIN_1X;
  }
  if (!defined($hash->{acquiState})) {
    $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
  }
  if (!defined($hash->{calcState})) {
    $hash->{calcState} = TSL2561_CALC_STATE_IDLE;
  }
  if (!defined($hash->{operationCounter})) {
    $hash->{operationCounter} = 0;
  }
  if (!defined($hash->{blockingIO})) {
    $hash->{blockingIO} = 0;
  }

  readingsSingleUpdate($hash, 'state', TSL2561_STATE_DEFINED, 1);
  
  if ($main::init_done || $hash->{HiPi_used}) {
    eval { 
      I2C_TSL2561_Init($hash, [ $device ]); 
    };
    Log3 ($hash, 1, $hash->{NAME} . ': ' . I2C_TSL2561_Catch($@)) if $@;;
  }

  Log3 $name, 5, "I2C_TSL2561_Define end";
  return undef;
}
  
sub I2C_TSL2561_Init($$) {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};
  
  if ($hash->{HiPi_used}) {
    # check for existing i2c device  
    my $i2cModulesLoaded = 0;
    $i2cModulesLoaded = 1 if -e $dev;
    if ($i2cModulesLoaded) {
      if (-r $dev && -w $dev) {
        $hash->{devTSL2561} = HiPi::Device::I2C->new( 
            devicename  => $dev,
            address    => $hash->{I2C_Address},
            busmode    => 'i2c',
        );
        Log3 $name, 3, "I2C_TSL2561_Define device created";
      } else {
        my @groups = split '\s', $(;
        return "$name :Error! $dev isn't readable/writable by user " . getpwuid( $< ) . " or group(s) " . 
          getgrgid($_) . " " foreach(@groups); 
      }
    } else {
      return $name . ': Error! I2C device not found: ' . $dev . '. Please check that these kernelmodules are loaded: i2c_bcm2708, i2c_dev';
    }
  } else {
    AssignIoPort($hash);
  }

  # clear package identification to force device reinitialization (device may have been powered off)
  $hash->{tsl2561Package} = undef;
  
  # start new measurement cycle
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + 10, 'I2C_TSL2561_Poll', $hash, 0);
  
  return undef;
}

sub I2C_TSL2561_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

=head2 I2C_TSL2561_Attr
  Title:    I2C_TSL2561_Attr
  Function:  Implements AttrFn function.
  Returns:  string|undef
  Args:    named arguments:
        -argument1 => array

=cut

sub I2C_TSL2561_Attr (@) {
  my ($cmd, $name, $attr, $val) =  @_;
  my $hash = $defs{$name};
  my $msg = '';

  Log3 $name, 5, "I2C_TSL2561_Attr: start cmd=$cmd attr=$attr"; 
  if ($attr eq 'poll_interval') {
    my $pollInterval = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;    
    if ($val > 0) {
      # start new measurement cycle
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday() + 1, 'I2C_TSL2561_Poll', $hash, 0);
    } elsif (defined($val)) {
      $msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
    }
  } elsif ($attr eq 'gain') {
    my $gain = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
    
    Log3 $name, 5, "I2C_TSL2561_Attr: attr gain is " . $gain;
    if ($gain == 1) {
      I2C_TSL2561_SetGain($hash, TSL2561_GAIN_1X);
    } elsif ($gain == 16) {
      I2C_TSL2561_SetGain($hash, TSL2561_GAIN_16X);
    } elsif (defined($val)) {
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
    } elsif (defined($val)) {
      $msg = 'Wrong integrationTime defined. must be 13 or 101 or 402';
    }
  } elsif ($attr eq 'autoGain') {
    my $autoGain = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
    $hash->{timingModified} = 1;    
  } elsif ($attr eq 'autoIntegrationTime') {
    my $autoIntegrationTime = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
    $hash->{timingModified} = 1;    
  } elsif ($attr eq 'normalizeRawValues') {
    my $normalizeRawValues = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
  } elsif ($attr eq 'floatArithmetics') {
    my $floatArithmetics = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
    } elsif ($attr eq "disable") {
      my $disable = (defined($val) && looks_like_number($val) && $val > 0) ? $val : 0;
  }  

  return ($msg) ? $msg : undef;
}

=head2 I2C_TSL2561_Poll
  Title:    I2C_TSL2561_Poll
  Function: Start polling the sensor at interval defined in attribute
  Returns:  -
  Args:     named arguments:
            - argument1 => hash
=cut

sub I2C_TSL2561_Poll($) {
  my ($hash) =  @_;
  my $name = $hash->{NAME};
  RemoveInternalTimer($hash);
  
  Log3 $name, 5, "I2C_TSL2561_Poll: start";
  
  my $pollDelay = 60*AttrVal($hash->{NAME}, 'poll_interval', 0); # seconds polling
  if (!AttrVal($hash->{NAME}, "disable", 0)) {
    # Request new samples from TSL2561 and calculate luminosity
    my $lux = I2C_TSL2561_GetLuminosity($hash);
    if ($hash->{calcState} == TSL2561_CALC_STATE_DATA_REQUESTED) {
      # Measurement in progress
      if ($hash->{acquiState} == TSL2561_ACQUI_STATE_ENABLED) {
        $pollDelay = I2C_TSL2561_GetIntegrationTime($hash) + 0.003; # seconds measurement time
        if (!$hash->{blockingIO}) {
          $pollDelay += 0.200; # extra time for async transport jitter compensation
        }
      } else {
        $pollDelay = 0.400; # seconds async I2C read reply timeout
      }
    } else {
      # Measurement completed
      if ($hash->{calcState} == TSL2561_CALC_STATE_COMPLETED) {
        # success, update readings based on new data
        my $chScale = 1;
        if (AttrVal($hash->{NAME}, "normalizeRawValues", 0)) {
          $chScale = I2C_TSL2561_GetChannelScale($hash);
        }
        readingsBeginUpdate($hash);
        readingsBulkUpdate($hash, "gain",            I2C_TSL2561_GetGain($hash));
        readingsBulkUpdate($hash, "integrationTime", I2C_TSL2561_GetIntegrationTime($hash));
        readingsBulkUpdate($hash, "broadband",       ceil($chScale*$hash->{broadband}));
        readingsBulkUpdate($hash, "ir",              ceil($chScale*$hash->{ir}));
        if (defined($lux)) {
          readingsBulkUpdate($hash, "luminosity", $lux);
        }
        my $state = ReadingsVal($name, 'state', '');
        if ($state ne TSL2561_STATE_SATURATED && $hash->{saturated}) {
          readingsBulkUpdate($hash, 'state', TSL2561_STATE_SATURATED, 1);
        } elsif ($state ne TSL2561_STATE_INITIALIZED && !$hash->{saturated}) {
          readingsBulkUpdate($hash, 'state', TSL2561_STATE_INITIALIZED, 1);
        }
        readingsEndUpdate($hash, 1);
      }

      # backup required operations (for diagnostics)
      $hash->{requiredOperations} = $hash->{operationCounter};
      
      # Reset state
      $hash->{calcState} = TSL2561_CALC_STATE_IDLE;
      $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
      $hash->{operationCounter} = 0;
    }
  } else {
    readingsSingleUpdate($hash, 'state', TSL2561_STATE_DISABLED, 1);
  }
  
  # Schedule next polling
  Log3 $name, 5, "I2C_TSL2561_Poll: $pollDelay s";
  if ($pollDelay > 0) {
    InternalTimer(gettimeofday() + $pollDelay, 'I2C_TSL2561_Poll', $hash, 0);
  }
  
  return undef;
}

sub I2C_TSL2561_Set($@) {
  my ( $hash, @args ) = @_;
  my $name = $hash->{NAME};

  my $cmd = $args[1];

  if(!defined($sets{$cmd})) {
    return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
  }
  
  I2C_TSL2561_Poll($hash);
  return undef;
}

sub I2C_TSL2561_Undef($$) {
  my ($hash, $arg) = @_;
  
  RemoveInternalTimer($hash);
  if ($hash->{HiPi_used}) {
    $hash->{devTSL2561}->close()
  }
  
  return undef;
}

#
# process received control register
#
sub I2C_TSL2561_I2CRcvControl($$) {
  my ($hash, $control) = @_;
  my $name = $hash->{NAME};
  
  my $enabled = $control & 0x3;
  if ($enabled == TSL2561_CONTROL_POWERON) {
    Log3 $name, 5, "I2C_TSL2561_I2CRcvControl: is enabled";
    $hash->{acquiState} = TSL2561_ACQUI_STATE_ENABLED;
    $hash->{acquiStarted} = [gettimeofday];
  } else {
    Log3 $name, 5, "I2C_TSL2561_I2CRcvControl: is disabled";
    $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
  }
  
  if (!$hash->{blockingIO}) {
    I2C_TSL2561_Poll($hash);
  }
  return undef;
}

#
# process received ID register 
#
sub I2C_TSL2561_I2CRcvID($$) {
  my ($hash, $sensorId) = @_;
  my $name = $hash->{NAME};
  
  if ( !($sensorId & 0b00010000) ) {
    return $name . ': Error! I2C failure: Please check your i2c bus and the connected device address: ' . $hash->{I2C_Address};
  }
  
  my $package = '';
  $hash->{tsl2561Package} = $sensorId >> 4;
  if ($hash->{tsl2561Package} == TSL2561_PACKAGE_CS) {
    $package = 'CS';
  } else {
    $package = 'T/FN/CL';
  }
  $hash->{sensorType} = 'TSL2561 Package ' . $package . ' Rev. ' . ( $sensorId & 0x0f );
  Log3 $name, 5, 'I2C_TSL2561_I2CRcvID: sensorId ' . $hash->{sensorType}; 
  
  # init state
  $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
  readingsSingleUpdate($hash, 'state', TSL2561_STATE_INITIALIZED, 1);
  
  # force preset of integration time and gain (device may have been powered off)
  $hash->{timingModified} = 1;

  # I2C-API blocking/non-blocking detection
  $hash->{blockingIO} = $hash->{operationInProgress};
  
  if (!$hash->{blockingIO}) {
    I2C_TSL2561_Poll($hash);
  }
  return undef;
}

#
# process received timing register 
#
sub I2C_TSL2561_I2CRcvTiming ($$) {
  my ($hash, $timing) = @_;
  my $name = $hash->{NAME};
  
  $hash->{tsl2561IntegrationTime} = $timing & 0x03;
  $hash->{tsl2561Gain}            = $timing & 0x10;          
  Log3 $name, 4, "I2C_TSL2561_I2CRcvTiming: time $hash->{tsl2561IntegrationTime}, gain $hash->{tsl2561Gain}";
  
  $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
  if (!$hash->{blockingIO}) {
    I2C_TSL2561_Poll($hash);
  }
  return undef;
}

#
# process received ADC channel 0 register 
#
sub I2C_TSL2561_I2CRcvChan0 ($$) {
  my ($hash, $broadband) = @_;
  my $name = $hash->{NAME};
    
  $hash->{broadband} = $broadband;
  Log3 $name, 4, 'I2C_TSL2561_I2CRcvChan0 ' . $broadband; 
  
  $hash->{acquiState} = TSL2561_ACQUI_STATE_DATA_CH0_RECEIVED;
  return undef;
}

#
# process received ADC channel 1 register 
#
sub I2C_TSL2561_I2CRcvChan1 ($$) {
  my ($hash, $ir) = @_;
  my $name = $hash->{NAME};
  
  $hash->{ir} = $ir;
  Log3 $name, 4, 'I2C_TSL2561_I2CRcvChan1 ' . $ir;   

  $hash->{acquiState} = TSL2561_ACQUI_STATE_DATA_CH1_RECEIVED;
  if (!$hash->{blockingIO}) {
    I2C_TSL2561_Poll($hash);
  }
  return undef;
}

#
# preprocess received data from I2C bus
#
sub I2C_TSL2561_I2CRec ($$) {
  my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};
  
  my $pname = undef;
  unless ($hash->{HiPi_used}) { #nicht nutzen wenn HiPi Bibliothek in Benutzung
    my $phash = $hash->{IODev};
    $pname = $phash->{NAME};
    while (my ( $k, $v ) = each %$clientmsg) { #erzeugen von Internals für alle Keys in $clientmsg die mit dem physical Namen beginnen
      $hash->{$k} = $v if $k =~ /^$pname/;
    }
  }
  
  if ($clientmsg->{direction} && $clientmsg->{reg} && 
    (($pname && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") 
     || $hash->{HiPi_used})) {
    if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received})) {
      my $register = $clientmsg->{reg} & 0xF;
      Log3 $hash, 5, "$name RX register $register, $clientmsg->{nbyte} byte: $clientmsg->{received}";
      my $byte = undef;
      my $word = undef;
      my @raw = split(" ", $clientmsg->{received});
      if ($clientmsg->{nbyte} == 1) {
        $byte = $raw[0];
      } elsif ($clientmsg->{nbyte} == 2) {
        $word = $raw[1] << 8 | $raw[0];
      }
      if ($register == TSL2561_REGISTER_CONTROL) {
        I2C_TSL2561_I2CRcvControl($hash, $byte); 
      } elsif ($register == TSL2561_REGISTER_ID) {
        I2C_TSL2561_I2CRcvID($hash, $byte); 
      } elsif ($register == TSL2561_REGISTER_TIMING) {
        I2C_TSL2561_I2CRcvTiming($hash, $byte); 
      } elsif ($register == TSL2561_REGISTER_CHAN0_LOW) {
        I2C_TSL2561_I2CRcvChan0($hash, $word); 
      } elsif ($register == TSL2561_REGISTER_CHAN1_LOW) {
        I2C_TSL2561_I2CRcvChan1($hash, $word); 
      } else {
        Log3 $name, 3, "I2C_TSL2561_I2CRec unsupported register $register";
      }
    }
  }
  return undef;
}

=head2 I2C_TSL2561_Enable
  Title:    I2C_TSL2561_Enable
  Function: Enables the device
  Returns:  1 if enabling sensor was initiated, 0 if enabling sensor failed
  Args:     named arguments:
            - argument1 => hash:  $hash      hash of device
=cut

sub I2C_TSL2561_Enable($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 5, 'I2C_TSL2561_Enable: start ';  
  my $success = 0;
  if (I2C_TSL2561_i2cwrite($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_CONTROL, TSL2561_CONTROL_POWERON)) {
    $success = I2C_TSL2561_i2cread($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_CONTROL, 1);
  }
  Log3 $name, 5, 'I2C_TSL2561_Enable: end '; 
  
  return $success;
}

=head2 I2C_TSL2561_Disable
  Title:    I2C_TSL2561_Disable
  Function: Disables the device
  Returns:  1 if disabling sensor was initiated, 0 if disabling sensor failed
  Args:     named arguments:
            - argument1 => hash:  $hash      hash of device
=cut

sub I2C_TSL2561_Disable($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, 'I2C_TSL2561_Disable: start ';
  my $success = I2C_TSL2561_i2cwrite($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_CONTROL, TSL2561_CONTROL_POWEROFF);
  Log3 $name, 5, 'I2C_TSL2561_Disable: end ';
  
  return $success;
}

=head2 I2C_TSL2561_GetData
  Title:    I2C_TSL2561_GetData
  Function: Private function to read luminosity on both channels
  Returns:  -
  Args:     named arguments:
            - argument1 => hash:  $hash      hash of device
=cut

sub I2C_TSL2561_GetData($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  # Data acquisition state machine with asynchronous wait
  my $success = 1;
  my $operations = 0;
  while (1) {
    $operations++;
    if ($hash->{acquiState} == TSL2561_ACQUI_STATE_ERROR) {
      $success = 0;
      last; # Abort, Start again at next slow poll
    } elsif ($operations > 10) {
      # Too many consecutive operations, abort
      $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
      Log3 $name, 5, "I2C_TSL2561_GetData: state machine stuck, aborting";
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_IDLE) {
      if (!defined($hash->{tsl2561Package})) {
        # Choose an address to scan the I2C bus for device in auto address mode
        if ($hash->{autoAddress}) {
          if ($hash->{I2C_Address} == hex(TSL2561_ADDR_LOW)) {
            $hash->{I2C_Address} = hex(TSL2561_ADDR_FLOAT);
          } elsif ($hash->{I2C_Address} == hex(TSL2561_ADDR_FLOAT)) {
            $hash->{I2C_Address} = hex(TSL2561_ADDR_HIGH);
          } else {
            $hash->{I2C_Address} = hex(TSL2561_ADDR_LOW);
          }      
        }
        # Detect TLS2561 package type and init integration time and gain
        Log3 $name, 5, "I2C_TSL2561_GetData: request device id";
        $hash->{acquiState} = TSL2561_ACQUI_STATE_SETUP;
        if (I2C_TSL2561_i2cread($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_ID, 1)) {
          last; # Wait for id confirmation, check again after next fast poll
        } else {
          $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
        }
      } elsif ($hash->{timingModified}) {
        $hash->{acquiState} = TSL2561_ACQUI_STATE_SETUP;
        if (I2C_TSL2561_SetTimingRegister($hash)) {
          last; # Wait new timing to be confirmed, check again after next fast poll
        } else {
          $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
        }
      } else {
        # Enable the device
        $hash->{acquiState} = TSL2561_ACQUI_STATE_ENABLE_REQUESTED;
        if (I2C_TSL2561_Enable($hash)) {
          last; # Wait for enable confirmation, check again after next fast poll
        } else {
          $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
        }
      }
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_SETUP) {
      last; # Wait for setup confirmation, check again after next fast poll
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_ENABLE_REQUESTED) {
      last; # Wait for enable confirmation, check again after next fast poll
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_ENABLED) {
      # Wait x ms for ADC to complete
      my $now = [gettimeofday];
      if (tv_interval($hash->{acquiStarted}, $now) >= I2C_TSL2561_GetIntegrationTime($hash)) {
        $hash->{acquiState} = TSL2561_ACQUI_STATE_DATA_AVAILABLE;
      } else {
        last; # Wait for measurement to complete, check again after next fast poll
      }
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_DATA_AVAILABLE) {
      # Read a two byte value from channel 0 and channel 1 (visible + infrared) 
      $hash->{acquiState} = TSL2561_ACQUI_STATE_DATA_REQUESTED;
      if (I2C_TSL2561_i2cread($hash,  TSL2561_COMMAND_BIT | TSL2561_WORD_BIT | TSL2561_REGISTER_CHAN0_LOW, 2)) {
        if (!I2C_TSL2561_i2cread($hash,  TSL2561_COMMAND_BIT | TSL2561_WORD_BIT | TSL2561_REGISTER_CHAN1_LOW, 2)) {
          $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
        }
      } else {
        $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
      }
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_DATA_REQUESTED) {
      last; # Wait for channel 0 or channel 1 data to be read
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_DATA_CH0_RECEIVED) {
      # Read a two byte value from channel 1 (infrared) 
      $hash->{acquiState} = TSL2561_ACQUI_STATE_DATA_REQUESTED;
      last; # Wait for channel 1 data to be read
    } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_DATA_CH1_RECEIVED) {
      $hash->{calcState} = TSL2561_CALC_STATE_DATA_RECEIVED;
      # Try to turn the device off to save power 
      I2C_TSL2561_Disable($hash);
      $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
      last; # Done, start again at next slow poll
    } else {
      # Undefined state
      $hash->{acquiState} = TSL2561_ACQUI_STATE_ERROR;
    }
  }
  
  return $success;
}

#
# write integration time and gain to device
#
sub I2C_TSL2561_SetTimingRegister($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $success = 0;
  if (!AttrVal($hash->{NAME}, "disable", 0) && defined($hash->{tsl2561Package})) {
    # Update the timing register 
    my $autoGain = AttrVal($name, 'autoGain', 1);      
    if (!$autoGain) {
      my $attrVal = AttrVal($name, 'gain', 1);
      $hash->{tsl2561Gain} = $attrVal == 16? TSL2561_GAIN_16X : TSL2561_GAIN_1X;
    }
    my $autoIntegrationTime = AttrVal($name, 'autoIntegrationTime', 0);
    if (!$autoIntegrationTime) {
      my $attrVal = AttrVal($name, 'integrationTime', 13);  
      $hash->{tsl2561IntegrationTime} = $attrVal == 402? TSL2561_INTEGRATIONTIME_402MS : $attrVal == 101? TSL2561_INTEGRATIONTIME_101MS : TSL2561_INTEGRATIONTIME_13MS;
    }
    Log3 $name, 4, "I2C_TSL2561_SetTimingRegister: time $hash->{tsl2561IntegrationTime}, gain $hash->{tsl2561Gain}";
    if (I2C_TSL2561_i2cwrite($hash, TSL2561_COMMAND_BIT | TSL2561_REGISTER_TIMING, $hash->{tsl2561IntegrationTime} | $hash->{tsl2561Gain})) {
      if (I2C_TSL2561_i2cread($hash,  TSL2561_COMMAND_BIT | TSL2561_REGISTER_TIMING, 1)) {
        $success = 1;
      }
    }
  }
  $hash->{timingModified} = 0;  
 
  return $success;
}

=head2 I2C_TSL2561_SetIntegrationTime
  Title:    I2C_TSL2561_SetIntegrationTime
  Function:  Sets the integration time for the TSL2561
  Returns:  -
  Args:    named arguments:
        -argument1 => hash:  $hash    hash of device
        -argument1 => number:  $time    constant for integration time setting

=cut

sub I2C_TSL2561_SetIntegrationTime($$) {
  my ($hash, $time) = @_;
  my $name = $hash->{NAME};
 
  # store the value even if $hash->{tsl2561Package} is not set (yet). That happens
  # during fhem startup.
  if (defined($hash->{tsl2561IntegrationTime}) && $hash->{tsl2561IntegrationTime} != $time) {
    Log3 $name, 4, "I2C_TSL2561_SetIntegrationTime: $hash->{tsl2561IntegrationTime} -> $time";
  }
  $hash->{tsl2561IntegrationTime} = $time;  
  $hash->{timingModified} = 1;  
  
  return undef;
}

#
# decode TSL2561 integration time into decimal value
# @param device hash
# @return integration time in seconds that was last reported by the TSL2561
#
sub I2C_TSL2561_GetIntegrationTime($) {
  my ($hash) = @_;
  my $tsl2561IntegrationTime = $hash->{tsl2561IntegrationTime};

  my $integrationTime = 0.402;   # 402 ms
  if ($tsl2561IntegrationTime == TSL2561_INTEGRATIONTIME_13MS) {
    $integrationTime = 0.0137; # 13.7 ms
  } elsif ($tsl2561IntegrationTime == TSL2561_INTEGRATIONTIME_101MS) {
    $integrationTime = 0.101;  # 101 ms
  }
  
  return $integrationTime;
}

=head2 I2C_TSL2561_SetGain
  Title:    I2C_TSL2561_SetGain
  Function: Adjusts the gain on the TSL2561 (adjusts the sensitivity to light)
  Returns:  -
  Args:     named arguments:
            - argument1 => hash:   $hash    hash of device
            - argument1 => number: $gain    constant for gain
=cut

sub I2C_TSL2561_SetGain($$) {
  my ($hash, $gain) = @_;
  my $name = $hash->{NAME};

  # store the value even if $hash->{tsl2561Package} is not set (yet). That happens
  # during fhem startup.
  if (defined($hash->{tsl2561Gain}) && $hash->{tsl2561Gain} != $gain) {
    Log3 $name, 4, "I2C_TSL2561_SetGain: $hash->{tsl2561Gain} -> $gain";
  }
  $hash->{tsl2561Gain} = $gain;
  $hash->{timingModified} = 1;  

  return undef;
}

#
# decode TSL2561 gain into decimal value
# @param device hash
# @return decimal gain factor that was last reported by the TSL2561
#
sub I2C_TSL2561_GetGain($) {
  my ($hash) = @_;
  my $tsl2561Gain = $hash->{tsl2561Gain};
  
  my $gain = 1;
  if (defined($tsl2561Gain) && $tsl2561Gain) {
    $gain = 16;
  }
  
  return $gain;
}

=head2 I2C_TSL2561_GetLuminosity
  Title:    I2C_TSL2561_GetLuminosity
  Function:  Gets the broadband (mixed lighting) and IR only values from the TSL2561, adjusting gain if auto-gain is enabled and calculate luminosity
  Returns:  luminosity
  Args:    named arguments:
        -argument1 => hash:  $hash    hash of device

=cut

sub I2C_TSL2561_GetLuminosity($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

#  Log3 $name, 5, "I2C_TSL2561_GetLuminosity: start";

  $hash->{operationInProgress} = 1;

  # Luminosity calculation state machine
  my $lux = undef;
  while(1) {
    $hash->{operationCounter}++;
    Log3 $name, 5, "I2C_TSL2561_GetLuminosity: calc state $hash->{calcState} acqui state $hash->{acquiState}";
    if ($hash->{calcState} == TSL2561_CALC_STATE_ERROR) {
      Log3 $name, 5, "I2C_TSL2561_GetLuminosity: error, aborting";
      # Try to turn the device off to save power 
      I2C_TSL2561_Disable($hash);
      # Reset package to force device reinitialization
      $hash->{tsl2561Package} = undef;
      # Claim I2C error
      readingsSingleUpdate($hash, 'state', TSL2561_STATE_I2C_ERROR, 1);      
      last; # Abort, start again at next slow poll
    } elsif ($hash->{operationCounter} > TSL2561_MAX_CONSECUTIVE_OPERATIONS) {
      # Too many consecutive operations, abort
      $hash->{calcState} = TSL2561_CALC_STATE_ERROR;
      Log3 $name, 5, "I2C_TSL2561_GetLuminosity: state machine stuck, aborting";
    } elsif ($hash->{calcState} == TSL2561_CALC_STATE_IDLE) {
      # Enable device and request data
      Log3 $name, 5, "I2C_TSL2561_GetLuminosity: starting new measurement";
      if (I2C_TSL2561_GetData($hash)) {
        $hash->{calcState} = TSL2561_CALC_STATE_DATA_REQUESTED;
      } else {      
        $hash->{calcState} = TSL2561_CALC_STATE_ERROR;
      }      
    } elsif ($hash->{calcState} == TSL2561_CALC_STATE_DATA_REQUESTED) {
      # Wait for device
      if (I2C_TSL2561_GetData($hash)) {
        if ($hash->{acquiState} == TSL2561_ACQUI_STATE_SETUP) {
          last; # Wait for setup confirmation, check again after next fast poll
        } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_ENABLE_REQUESTED) {
          last; # Wait for enable to be confirmed, check again at next fast poll
        } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_ENABLED) {
          last; # Wait for measurement to complete, check again at next fast poll
        } elsif ($hash->{acquiState} == TSL2561_ACQUI_STATE_DATA_REQUESTED) {
          last; # Wait for data to be read, check again at next fast poll
        }
      } else {
        $hash->{calcState} = TSL2561_CALC_STATE_ERROR;
      }
    } elsif ($hash->{calcState} == TSL2561_CALC_STATE_DATA_RECEIVED) {
      # Data was received, optimize gain
      my $autoGain = AttrVal($name, 'autoGain', 1);
      if ($autoGain) {
        # Get the hi/low threshold for the current integration time
        my $it = $hash->{tsl2561IntegrationTime};
        my $hi = TSL2561_AGC_THI_402MS;
        my $lo = TSL2561_AGC_TLO_402MS;
        if ($it == TSL2561_INTEGRATIONTIME_13MS) {
          $hi = TSL2561_AGC_THI_13MS;
          $lo = TSL2561_AGC_TLO_13MS;
        } elsif ($it == TSL2561_INTEGRATIONTIME_101MS) {
          $hi = TSL2561_AGC_THI_101MS;
          $lo = TSL2561_AGC_TLO_101MS;
        } 
        if (($hash->{broadband} < $lo) && ($hash->{tsl2561Gain} == TSL2561_GAIN_1X)) {
          # Increase gain and try again 
          I2C_TSL2561_SetGain($hash, TSL2561_GAIN_16X);
          $hash->{calcState} = TSL2561_CALC_STATE_IDLE;
          $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
          next;
        } elsif (($hash->{broadband} > $hi) && ($hash->{tsl2561Gain} == TSL2561_GAIN_16X)) {
          # Drop gain and try again 
          I2C_TSL2561_SetGain($hash, TSL2561_GAIN_1X);
          $hash->{calcState} = TSL2561_CALC_STATE_IDLE;
          $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
          next;
        } else {
          # Reading is either valid, or we're already at the chips limits 
        }
      } else {
        # Auto gain disabled, always valid
      }

      # Optimize integration time (make sure the sensor isn't saturated at 402 ms)
      my $clipThreshold = 0;
      if ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS) {
        $clipThreshold = TSL2561_CLIPPING_13MS;
      } elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS) {
        $clipThreshold = TSL2561_CLIPPING_101MS;
      } else {
        $clipThreshold = TSL2561_CLIPPING_402MS;
      }
      my $autoIntegrationTime = AttrVal($name, 'autoIntegrationTime', 0);
      if (($hash->{broadband} > $clipThreshold) || ($hash->{ir} > $clipThreshold)) {
        # ADC saturated, try to decrease integration time
        if ($autoIntegrationTime && $hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_402MS) {
          # Drop integration time and try again
          I2C_TSL2561_SetIntegrationTime($hash, TSL2561_INTEGRATIONTIME_101MS);
          $hash->{calcState} = TSL2561_CALC_STATE_IDLE;
          $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
          next;
        } else {
          # Integration time fixed or already below 402 ms, give up
          $hash->{saturated} = 1; 
        }
      } elsif ($autoIntegrationTime
           && ($hash->{broadband} < ($clipThreshold >> 2) && $hash->{ir} < ($clipThreshold >> 2)) 
           && ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS || $hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS)) {
        # Integration time below 178 ms, maximize and try again
        I2C_TSL2561_SetIntegrationTime($hash, TSL2561_INTEGRATIONTIME_402MS);
        $hash->{calcState} = TSL2561_CALC_STATE_IDLE;
        $hash->{acquiState} = TSL2561_ACQUI_STATE_IDLE;
        next;
      } else {
        # Readings are not saturated or auto integration time is disabled
        $hash->{saturated} = 0; 
      }

      # Received data is valid, calculate luminosity
      $lux = I2C_TSL2561_CalculateLux($hash);
      $hash->{calcState} = TSL2561_CALC_STATE_COMPLETED;
      last; # Done, start again at next slow poll
    } else {
      # Undefined state
      $hash->{calcState} = TSL2561_CALC_STATE_ERROR;
    }
  }
  
  $hash->{operationInProgress} = 0;
  
#  Log3 $name, 5, "I2C_TSL2561_GetLuminosity: end";
  
  return $lux;
}

#
# get channel scale
#
sub I2C_TSL2561_GetChannelScale($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $chScale = 0;
  
  if (AttrVal($name, 'floatArithmetics', 0)) {
    # Get the correct scale depending on the integration time 
    if (!defined($hash->{tsl2561IntegrationTime})) {
      $chScale = 1.0;
    } elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS) {
      $chScale = 322.0/11; 
    } elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS) {
      $chScale = 322.0/81;
    } else {
      $chScale = 1.0;
    }

    # Scale for gain (1x or 16x) 
    if (!defined($hash->{tsl2561Gain}) || !$hash->{tsl2561Gain}) {
      $chScale = $chScale*16;
    }
  } else {
    # Get the correct scale depending on the integration time 
    if ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_13MS) {
      $chScale = TSL2561_LUX_CHSCALE_TINT0;
    } elsif ($hash->{tsl2561IntegrationTime} == TSL2561_INTEGRATIONTIME_101MS) {
      $chScale = TSL2561_LUX_CHSCALE_TINT1;
    } else {
      $chScale = (1 << TSL2561_LUX_CHSCALE);
    }

    # Scale for gain (1x or 16x) 
    if (!defined($hash->{tsl2561Gain}) || !$hash->{tsl2561Gain}) {
      $chScale = $chScale << 4;
    }
  }
  
  return $chScale;
}

=head2 I2C_TSL2561_CalculateLux
  Title:    I2C_TSL2561_CalculateLux
  Function: Converts the raw sensor values to the standard SI lux equivalent. Returns 0 if the sensor is saturated and the values are unreliable.
  Returns:  number
  Args:     named arguments:
            - argument1 => hash:    $hash      hash of device
=cut

sub I2C_TSL2561_CalculateLux($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # Get the correct scale depending on gain and integration time 
  my $chScale = I2C_TSL2561_GetChannelScale($hash);
  if (AttrVal($name, 'floatArithmetics', 0)) {
    # Scale the channel values 
    my $channel0 = $chScale*$hash->{broadband};
    my $channel1 = $chScale*$hash->{ir};

    # Find the ratio of the channel values (Channel1/Channel0) 
    my $ratio = 0.0;
    if ($channel0 != 0) {
      $ratio = $channel1/$channel0;
    }
    
    # Calculate luminosity (see TSL2561 data sheet)
    my $lux = undef;
    if ($hash->{tsl2561Package} == TSL2561_PACKAGE_CS) {
      #  CS package
      if ($ratio <= 0.52) {
        $lux = 0.0315*$channel0 - 0.0593*$channel0*pow($ratio, 1.4);
      } elsif ($ratio <= 0.65) {
        $lux = 0.0229*$channel0 - 0.0291*$channel1;
      } elsif ($ratio <= 0.80) {
        $lux = 0.0157*$channel0 - 0.0180*$channel1;
      } elsif ($ratio <= 1.30) {
        $lux = 0.00338*$channel0 - 0.00260*$channel1;
      } else {
        $lux = 0.0;
      }
    } else {
      #  T, FN and CL package
      if ($ratio <= 0.50) {
        $lux = 0.0304*$channel0 - 0.062*$channel0*pow($ratio, 1.4);
      } elsif ($ratio <= 0.61) {
        $lux = 0.0224*$channel0 - 0.031*$channel1;
      } elsif ($ratio <= 0.80) {
        $lux = 0.0128*$channel0 - 0.0153*$channel1;
      } elsif ($ratio <= 1.30) {
        $lux = 0.00146*$channel0 - 0.00112*$channel1;
      } else {
        $lux = 0.0;
      }
    }
    
    if ($lux >= 100) {
      # Round to 3 significant digits if at least 100
      my $roundFactor = 10**(floor(log($lux)/log(10)) - 2);
      $lux = $roundFactor*floor($lux/$roundFactor + 0.5);
    } else {
      # Round to 1 fractional digit if less than 100
      $lux = floor(10*$lux + 0.5)/10;
    }
    
    return $lux;
  } else {
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
}

=head2 I2C_TSL2561_i2cread
  Title:     I2C_TSL2561_i2cread
  Function:  implements I2C read operation abstraction
  Returns:   1 on success, 0 on error
  Args:      - argument1 => hash
             - argument2 => I2C register
             - argument3 => number of bytes to read
=cut

sub I2C_TSL2561_i2cread($$$) {
  my ($hash, $reg, $nbyte) = @_;
  my $success = 1;
  
  local $SIG{__WARN__} = sub {
    my $message = shift;
    # turn warnings from RPII2C_HWACCESS_ioctl into exception
    if ($message =~ /Exiting subroutine via last at.*00_RPII2C.pm/) {
      die;
    } else {
      warn($message);
    }
  };
  
  if ($hash->{HiPi_used}) {
    eval {
      my @values = $hash->{devTSL2561}->bus_read($reg, $nbyte);
      I2C_TSL2561_I2CRec($hash, {
        direction => "i2cread",
        i2caddress => $hash->{I2C_Address},
        reg => $reg,
        nbyte => $nbyte,
        received => join (' ',@values),
      });
    };
    Log3 ($hash, 1, $hash->{NAME} . ': ' . I2C_TSL2561_Catch($@)) if $@;
  } elsif (defined (my $iodev = $hash->{IODev})) {
    eval {
      CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
      direction => "i2cread",
      i2caddress => $hash->{I2C_Address},
      reg => $reg,
      nbyte => $nbyte
      });
    };
    my $sendStat = $hash->{$iodev->{NAME}.'_SENDSTAT'};
    if (defined($sendStat) && $sendStat ne 'Ok') {
      readingsSingleUpdate($hash, 'state', TSL2561_STATE_I2C_ERROR, 1);
      Log3 ($hash, 5, $hash->{NAME} . ": i2cread on $iodev->{NAME} failed");
      $success = 0;
    } 
  } else {
    Log3 ($hash, 1, $hash->{NAME} . ': ' . "no IODev assigned to '$hash->{NAME}'");
    $success = 0;
  }
  
  return $success;
}

sub I2C_TSL2561_i2cwrite($$$) {
  my ($hash, $reg, @data) = @_;
  my $success = 1;
  
  if ($hash->{HiPi_used}) {
    eval {
      $hash->{devTSL2561}->bus_write($reg, join (' ',@data));
      I2C_TSL2561_I2CRec($hash, {
        direction => "i2cwrite",
        i2caddress => $hash->{I2C_Address},
        reg => $reg,
        data => join (' ',@data),
      });
    };
    Log3 ($hash, 1, $hash->{NAME} . ': ' . I2C_TSL2561_Catch($@)) if $@;
  } elsif (defined (my $iodev = $hash->{IODev})) {
    eval {
      CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
      direction => "i2cwrite",
      i2caddress => $hash->{I2C_Address},
      reg => $reg,
      data => join (' ',@data), 
      });
    };
    my $sendStat = $hash->{$iodev->{NAME}.'_SENDSTAT'};
    if (defined($sendStat) && $sendStat ne 'Ok') {
      readingsSingleUpdate($hash, 'state', TSL2561_STATE_I2C_ERROR, 1);
      Log3 ($hash, 5, $hash->{NAME} . ": i2cwrite on $iodev->{NAME} failed");
      $success = 0;
    }
  } else {
    Log3 ($hash, 1, $hash->{NAME} . ': ' . "no IODev assigned to '$hash->{NAME}'");
    $success = 0;
  }
  
  return $success;
}

1;

=pod
=item summary TSL2561 luminosity sensor
=item summary_DE TSL2561 Helligkeitssensor
=begin html

<a name="I2C_TSL2561"></a>
<h3>I2C_TSL2561</h3>
<ul>
    <a name="I2C_TSL2561"></a>
    <p>
    With this module you can read values from the ambient light sensor TSL2561
    via the i2c bus on Raspberry Pi.<br>
    The luminosity value returned is a good human eye reponse approximation of an 
    illumination measurement in the range of 0.1 to 40000+ lux (but not a replacement for a 
    precision measurement, relation between measured value and true value may vary by 40%).
    <br><br>
    
    <b>There are two possibilities connecting to I2C bus:</b><br>
    <ul>
        <li><b>via IODev module</b><br>
            The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
            or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
            <b>attribute IODev must be set</b><br>
            <br>
        </li>
        <li><b>via HiPi library</b><br>
            Add these two lines to your <b>/etc/modules</b> file to load the I2C relevant kernel modules
            automaticly during booting your Raspberry Pi.<br>
            <code><pre> 
            i2c-bcm2708
            i2c-dev
            </pre></code>
            Install HiPi perl modules:<br>
            <code><pre> wget http://raspberry.znix.com/hipifiles/hipi-install perl hipi-install</pre></code>
            To change the permissions of the I2C device create file:<br>
            <code><pre> /etc/udev/rules.d/98_i2c.rules</pre></code>
            with this content:<br>
            <code><pre> SUBSYSTEM=="i2c-dev", MODE="0666"</pre></code>
            <b>Reboot</b><br>
            <br>
            To use the sensor on the second I2C bus at P5 connector
            (only for version 2 of Raspberry Pi) you must add the bold
            line of following code to your FHEM start script:
            <code><pre>
            case "$1" in
            'start')
                <b>sudo hipi-i2c e 0 1</b>
            ...
            </pre></code>
        </li>
    </ul>
    <p>

    <b>Define</b>
    <ul>
        <code>define TSL2561 I2C_TSL2561 [&lt;I2C device&gt;] &lt;I2C address&gt</code><br><br>
        &lt;I2C device&gt; mandatory for HiPi, must be omitted if you connect via IODev<br>
        &lt;I2C address&gt; may be 0x29, 0x39 or 0x49 (and 'AUTO' when using IODev to search for device at startup and after an I2C error)<br>
        <br>
        Examples:
        <pre>
        define TSL2561 I2C_TSL2561 /dev/i2c-0 0x39
        attr TSL2561 poll_interval 5
        </pre>
        <pre>
        define TSL2561 I2C_TSL2561 0x39
        attr TSL2561 IODev I2CModule
        attr TSL2561 poll_interval 5
        </pre>
        <pre>
        define TSL2561 I2C_TSL2561 AUTO
        attr TSL2561 IODev I2CModule
        attr TSL2561 poll_interval 5
        </pre>
    </ul>

    <b>Set</b>
    <ul>
        <code>get &lt;name&gt; update</code><br><br>
        Force immediate illumination measurement and restart a new poll_interval.<br><br>
        Note that the new readings are not yet available after set returns because the
        measurement is performed asynchronously. Depending on the attributes integration time,
        autoGain and autoIntegrationTime this may require more than one second to complete.
    </ul>
    <p>

    <b>Readings</b>
    <ul>
        <li>luminosity<br>
            Good human eye reponse approximation of an illumination measurement in the range of 0.1 to 40000+ lux.<br>
            Rounded to 3 significant digits or one fractional digit.
        </li>
        <li>broadband<br>
            Broadband spectrum sensor sample.<br>
            Enable attribute normalizeRawValues for continuous readings independed of actual gain and integration time settings.
        </li>
        <li>ir<br>
            Infrared spectrum sensor sample.<br>
            Enable attribute normalizeRawValues for continuous readings independed of actual gain and integration time settings.
        </li>
        <li>gain<br>
            sensor gain used for current luminosity measurement (1 or 16)<br>
        </li>
        <li>integrationTime<br>
            integration time in seconds used for current luminosity measurement<br>
        </li>
        <li>state<br>
            Default: Initialized, valid values: Undefined, Defined, Initialized, Saturated, Disabled, I2C Error
        </li>
    </ul>
    <p>
     
    <a name="I2C_TSL2561attr"></a>
    <b>Attributes</b>
    <ul>
        <li>IODev<br>
            Set the name of an IODev module. If undefined the perl modules HiPi::Device::I2C are required.<br>
            Default: undefined<br>
        </li>
        <li>poll_interval<br>
            Set the polling interval in minutes to query the sensor for new measured  values.
            By changing this attribute a new illumination measurement will be triggered.<br>
            Default: 5, valid values: 1, 2, 5, 10, 20, 30<br>
        </li>
        <li>gain<br>
            Set gain factor. Attribute will be ignored if autoGain is enabled.<br>
            Default: 1, valid values: 1, 16
        </li>
        <li>integrationTime<br>
            Set time in ms the sensor takes to measure the light. Attribute will be ignored if autoIntegrationTime is enabled.<br>
            Default: 13, valid values: 13, 101, 402<br>
            See this <a href="https://learn.sparkfun.com/tutorials/tsl2561-luminosity-sensor-hookup-guide/using-the-arduino-library">tutorial</a>
            for more details.
        </li>
        <li>autoGain<br>
            Enable auto gain. If set to 1, the gain parameter is adjusted automatically depending on light conditions.<br>
            Default: 1, valid values: 0, 1<br>            
        </li>
        <li>autoIntegrationTime<br>
            Enable auto integration time. If set to 1, the integration time parameter is adjusted automatically depending on light conditions.<br>
            Default: 0, valid values: 0, 1<br>
        </li>
        <li>normalizeRawValues<br>
            Scale the sensor raw values broadband and ir depending on actual gain and integrationTime to the equivalent of the settings for maximum sensitivity (gain=16 and integrationTime=403ms). This feature may be useful when autoGain or autoIntegrationTime is enabled to provide continuous values instead of jumping values when gain or integration time changes.<br>
            Default: 0, valid values: 0, 1<br>
        </li>
        <li>floatArithmetics<br>
            Enable float arithmetics.<br>
            If set to 0, the luminosity is calculated using int arithmetics (for very low powered platforms).<br>
            If set to 1, the luminosity is calculated using float arithmetics, yielding some additional precision.
            Default: 1, valid values: 0, 1<br>            
        </li>
        <li>disable<br>
            Disable I2C bus access.<br>
            Default: 0, valid values: 0, 1
        </li>
    </ul>
    <p>

    <b>Notes</b>
    <ul>
      <li>Because the measurement may take several 100 milliseconds a measurement cycle will be executed asynchronously, so
          do not expect to have new values immediately available after "set update" returns. If autoGain or autoIntegrationTime
          are enabled, more than one measurement cycle will be required if light conditions change.
      </li>
      <li>With HiPi and especially IODev there are several I2C interfaces available, some blocking, some non-blocking and 
          some with different physical layers. The module has no knowledge of the specific properties of an interface and
          therefore module operation and timing may not be exactly the same with each interface type.
      </li>
      <li>If AUTO is used as device address, one address per measurement cycle will be tested. Depending on your device address 
          it may be necessary to execute "set update" several times to find your device.
      </li>
      <li>When using Firmata the I2C write/read delay attribute "i2c-config" of the FRM module can be set to any value.
      </li>
    </ul>
    <br>
</ul>

=end html

=cut

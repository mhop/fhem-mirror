# $Id$

package WMBus;

use strict;
use warnings;
use feature qw(say);
use Digest::CRC; # libdigest-crc-perl
eval "use Crypt::Mode::CBC"; # cpan -i Crypt::Mode::CBC
my $hasCBC = ($@)?0:1;
eval "use Crypt::Mode::CTR"; # cpan -i Crypt::Mode::CTR
my $hasCTR = ($@)?0:1;

require Exporter;
my @ISA = qw(Exporter);
my @EXPORT = qw(new parse parseLinkLayer parseApplicationLayer manId2ascii type2string);

sub manId2ascii($$);


use constant {
  # Transport Layer block size
  TL_BLOCK_SIZE => 10,
  # Link Layer block size
  LL_BLOCK_SIZE => 16,
  # size of CRC in bytes
  CRC_SIZE => 2,

  # sent by meter
  SND_NR => 0x44, # Send, no reply
  SND_IR => 0x46, # Send installation request, must reply with CNF_IR
  ACC_NR => 0x47,
  ACC_DMD => 0x48,
  
  # sent by controller
  SND_NKE => 0x40, # Link reset
  CNF_IR => 0x06, 
  
  # CI field
  CI_RESP_4 => 0x7a,  # Response from device, 4 Bytes
  CI_RESP_12 => 0x72, # Response from device, 12 Bytes
  CI_RESP_0 => 0x78,  # Response from device, 0 Byte header, variable length
  CI_ERROR => 0x70,   # Error from device, only specified for wired M-Bus but used by Easymeter WMBUS module
  CI_TL_4 => 0x8a,    # Transport layer from device, 4 Bytes
  CI_TL_12 => 0x8b,   # Transport layer from device, 12 Bytes
  CI_ELL_2 => 0x8c,   # Extended Link Layer, 2 Bytes
  CI_ELL_6 => 0x8e,   # Extended Link Layer, 6 Bytes
  CI_ELL_8 => 0x8d,   # Extended Link Layer, 8 Bytes (see https://www.telit.com/wp-content/uploads/2017/09/Telit_Wireless_M-bus_2013_Part4_User_Guide_r14.pdf, 2.3.4)
  CI_ELL_16 => 0x8f,  # Extended Link Layer, 16 Bytes (see https://www.telit.com/wp-content/uploads/2017/09/Telit_Wireless_M-bus_2013_Part4_User_Guide_r14.pdf, 2.3.4)
  CI_AFL => 0x90,     # Authentification and Fragmentation Layer, variable size
  CI_RESP_SML_4 => 0x7e, # Response from device, 4 Bytes, application layer SML encoded
  CI_RESP_SML_12 => 0x7f, # Response from device, 12 Bytes, application layer SML encoded  
  
  # DIF types (Data Information Field), see page 32
  DIF_NONE => 0x00,
  DIF_INT8 => 0x01,
  DIF_INT16 => 0x02,
  DIF_INT24 => 0x03,
  DIF_INT32 => 0x04,
  DIF_FLOAT32 => 0x05,
  DIF_INT48 => 0x06,
  DIF_INT64 => 0x07,
  DIF_READOUT => 0x08,
  DIF_BCD2 => 0x09,
  DIF_BCD4 => 0x0a,
  DIF_BCD6 => 0x0b,
  DIF_BCD8 => 0x0c,
  DIF_VARLEN => 0x0d,
  DIF_BCD12 => 0x0e,
  DIF_SPECIAL => 0x0f,

  
  DIF_IDLE_FILLER => 0x2f,
  
  DIF_EXTENSION_BIT => 0x80,
  
  VIF_EXTENSION        => 0xFB,                     # true VIF is given in the first VIFE and is coded using table 8.4.4 b) (128 new VIF-Codes)
  VIF_EXTENSION_BIT    => 0x80,
  

  ERR_NO_ERROR => 0,
  ERR_CRC_FAILED => 1,
  ERR_UNKNOWN_VIFE => 2,
  ERR_UNKNOWN_VIF => 3,
  ERR_TOO_MANY_DIFE => 4,
  ERR_UNKNOWN_LVAR => 5,
  ERR_UNKNOWN_DATAFIELD => 6,
  ERR_UNKNOWN_CIFIELD => 7,
  ERR_DECRYPTION_FAILED => 8,
  ERR_NO_AESKEY => 9,
  ERR_UNKNOWN_ENCRYPTION => 10,
  ERR_TOO_MANY_VIFE => 11,
  ERR_MSG_TOO_SHORT => 12,
  ERR_SML_PAYLOAD => 13,
  ERR_FRAGMENT_UNSUPPORTED => 14,
  ERR_UNKNOWN_COMPACT_FORMAT => 15,
  ERR_CIPHER_NOT_INSTALLED => 16,
  
  # TYPE C transmission uses two different frame types
  # see http://www.st.com/content/ccc/resource/technical/document/application_note/3f/fb/35/5a/25/4e/41/ba/DM00233038.pdf/files/DM00233038.pdf/jcr:content/translations/en.DM00233038.pdf
  FRAME_TYPE_A => 'A',
  FRAME_TYPE_B => 'B',
};

sub valueCalcNumeric($$) {
  my $value = shift;
  my $dataBlock = shift;
  
  return $value * $dataBlock->{valueFactor}; 
}

sub valueCalcDate($$) {
  my $value = shift;
  my $dataBlock = shift;
  
  #value is a 16bit int
  
  #day: UI5 [1 to 5] <1 to 31>
  #month: UI4 [9 to 12] <1 to 12>
  #year: UI7[6 to 8,13 to 16] <0 to 99>
  
  #   YYYY MMMM YYY DDDDD
  # 0b0000 1100 111 11111 = 31.12.2007
  # 0b0000 0100 111 11110 = 30.04.2007

  my $day = ($value & 0b11111);
  my $month = (($value & 0b111100000000) >> 8);
  my $year = ((($value & 0b1111000000000000) >> 9) | (($value & 0b11100000) >> 5)) + 2000;
  if ($day > 31 || $month > 12 || $year > 2099) {
    return sprintf("invalid: %x", $value);
  } else {
    return sprintf("%04d-%02d-%02d", $year, $month, $day);
  }
}

sub valueCalcDateTime($$) {
  my $value = shift;
  my $dataBlock = shift;

#min: UI6 [1 to 6] <0 to 59>
#hour: UI5 [9 to13] <0 to 23>
#day: UI5 [17 to 21] <1 to 31>
#month: UI4 [25 to 28] <1 to 12>
#year: UI7[22 to 24,29 to 32] <0 to 99>
# IV:
# B1[8] {time invalid}:
# IV<0> :=
#valid,
#IV>1> := invalid
#SU: B1[16] {summer time}:
#SU<0> := standard time,
#SU<1> := summer time
#RES1: B1[7] {reserved}: <0>
#RES2: B1[14] {reserved}: <0>
#RES3: B1[15] {reserved}: <0>
  
  
  my $datePart = $value >> 16;
  my $timeInvalid = $value & 0b10000000;
  
  my $dateTime = valueCalcDate($datePart, $dataBlock);
  if ($timeInvalid == 0) {
    my $min = ($value & 0b111111);
    my $hour = ($value >> 8) & 0b11111;
    my $su = ($value & 0b1000000000000000);
    if ($min > 59 || $hour > 23) {
      $dateTime = sprintf('invalid: %x', $value);
    } else {
      $dateTime .= sprintf(' %02d:%02d %s', $hour, $min, $su ? 'DST' : '');
    }
  }
  
  return $dateTime;  
}

sub valueCalcHex($$) {
  my $value = shift;
  my $dataBlock = shift;

  return sprintf("%x", $value);
}

sub valueCalcu($$) {
  my $value = shift;
  my $dataBlock = shift;

  my $result = '';
  
  $result = ($value & 0b00001000 ? 'upper' : 'lower') . ' limit';
  return $result;
}

sub valueCalcufnn($$) {
  my $value = shift;
  my $dataBlock = shift;

  my $result = '';
  
  $result = ($value & 0b00001000 ? 'upper' : 'lower') . ' limit';
  $result .= ', ' . ($value & 0b00000100 ? 'first' : 'last');
  $result .= sprintf(', duration %d', $value & 0b11);
  return $result;
}

sub valueCalcMultCorr1000($$) {
  my $value = shift;
  my $dataBlock = shift;
  
  $dataBlock->{value} *= 1000;

  return "correction by factor 1000";
}


my %TimeSpec = (
  0b00 => 's', # seconds
  0b01 => 'm', # minutes
  0b10 => 'h', # hours
  0b11 => 'd', # days
);

sub valueCalcTimeperiod($$) {
  my $value = shift;
  my $dataBlock = shift;
  
  $dataBlock->{unit} = $TimeSpec{$dataBlock->{exponent}};
  return $value;
}

# VIF types (Value Information Field), see page 32
my %VIFInfo = (
  VIF_ENERGY_WATT  => {                     #  10(nnn-3) Wh  0.001Wh to 10000Wh
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00000000,
    bias         => -3,
    unit         => 'Wh',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ENERGY_JOULE   => {                     #  10(nnn) J     0.001kJ to 10000kJ
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00001000,
    bias         => 0,
    unit         => 'J',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_VOLUME           => {                     #  10(nnn-6) m3  0.001l to 10000l
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00010000,
    bias         => -6,
    unit         => 'm³',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_MASS             => {                     #  10(nnn-3) kg  0.001kg to 10000kg
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00011000,
    bias         => -3,
    unit         => 'kg',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ON_TIME_SEC      => {                     #  seconds
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100000,
    bias         => 0,
    unit         => 'sec',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ON_TIME_MIN      => {                     #  minutes
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100001,
    bias         => 0,
    unit         => 'min',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ON_TIME_HOURS    => {                     #  hours
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100010,
    bias         => 0,
    unit         => 'hours',
  },
  VIF_ON_TIME_DAYS    => {                     #  days
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100011,
    bias         => 0,
    unit         => 'days',
  },
  VIF_OP_TIME_SEC      => {                     #  seconds
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100100,
    bias         => 0,
    unit         => 'sec',
  },
  VIF_OP_TIME_MIN      => {                     #  minutes
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100101,
    bias         => 0,
    unit         => 'min',
  },
  VIF_OP_TIME_HOURS    => {                     #  hours
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100110,
    bias         => 0,
    unit         => 'hours',
  },
  VIF_OP_TIME_DAYS    => {                     #  days
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100111,
    bias         => 0,
    unit         => 'days',
  },
  VIF_ELECTRIC_POWER   => {                     #  10(nnn-3) W   0.001W to 10000W
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00101000,
    bias         => -3,
    unit         => 'W',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_THERMAL_POWER    =>  {                    #  10(nnn) J/h   0.001kJ/h to 10000kJ/h
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00110000,
    bias         => 0,
    unit         => 'J/h',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_VOLUME_FLOW      => {                     #  10(nnn-6) m3/h 0.001l/h to 10000l/h
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b00111000,
    bias         => -6,
    unit         => 'm³/h',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_VOLUME_FLOW_EXT1 => {                     #  10(nnn-7) m3/min 0.0001l/min to 10000l/min
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b01000000,
    bias         => -7,
    unit         => 'm³/min',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_VOLUME_FLOW_EXT2 => {                     #  10(nnn-9) m3/s 0.001ml/s to 10000ml/s
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b01001000,
    bias         => -9,
    unit         => 'm³/s',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_MASS_FLOW         => {                   #  10(nnn-3) kg/h 0.001kg/h to 10000kg/h
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b01010000,
    bias         => -3,
    unit         => 'kg/h',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_FLOW_TEMP         => {                   #  10(nn-3) °C 0.001°C to 1°C
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b01011000,
    bias         => -3,
    unit         => '°C',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_RETURN_TEMP       => {                   #  10(nn-3) °C 0.001°C to 1°C
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b01011100,
    bias         => -3,
    unit         => '°C',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_TEMP_DIFF        => {                    #  10(nn-3) K 1mK to 1000mK
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b01100000,
    bias         => -3,
    unit         => 'K',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_EXTERNAL_TEMP    => {                   #  10(nn-3) °C 0.001°C to 1°C
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b01100100,
    bias         => -3,
    unit         => '°C',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_PRESSURE    => {                        #  10(nn-3) bar  1mbar to 1000mbar
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b01101000,
    bias         => -3,
    unit         => 'bar',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_TIME_POINT_DATE => {                    #  data type G
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01101100,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcDate,
  },
  VIF_TIME_POINT_DATE_TIME => {               #  data type F
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01101101,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcDateTime,
  },
  VIF_HCA              =>  {                  # Unit for Heat Cost Allocator, dimensonless
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01101110,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_FABRICATION_NO =>  {                    # Fabrication No
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01111000,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_OWNER_NO =>  {                          # Eigentumsnummer (used by Easymeter even though the standard allows this only for writing to a slave)
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01111001,
    bias         => 0,
    unit         => '',
  },  
  VIF_AVERAGING_DURATION_SEC      => {                     #  seconds
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110000,
    bias         => 0,
    unit         => 'sec',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_AVERAGING_DURATION_MIN      => {                     #  minutes
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110001,
    bias         => 0,
    unit         => 'min',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_AVERAGING_DURATION_HOURS    => {                     #  hours
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110010,
    bias         => 0,
    unit         => 'hours',
  },
  VIF_AVERAGING_DURATION_DAYS    => {                     #  days
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110011,
    bias         => 0,
    unit         => 'days',
  },  
  VIF_ACTUALITY_DURATION_SEC      => {                     #  seconds
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110100,
    bias         => 0,
    unit         => 'sec',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ACTUALITY_DURATION_MIN      => {                     #  minutes
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110101,
    bias         => 0,
    unit         => 'min',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ACTUALITY_DURATION_HOURS    => {                     #  hours
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110110,
    bias         => 0,
    unit         => 'hours',
  },
  VIF_ACTUALITY_DURATION_DAYS    => {                     #  days
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110111,
    bias         => 0,
    unit         => 'days',
  },  
);  

# Codes used with extension indicator $FD, see 8.4.4 on page 80
my %VIFInfo_FD = (  
  VIF_CREDIT  => {                        #  Credit of 10nn-3 of the nominal local legal currency units
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b00000000,
    bias         => -3,
    unit         => '€',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_DEBIT  => {                         #  Debit of 10nn-3 of the nominal local legal currency units
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b00000100,
    bias         => -3,
    unit         => '€',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ACCESS_NO  => {                     #  Access number (transmission count)
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00001000,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_MEDIUM  => {                        #  Medium (as in fixed header)
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00001001,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_MODEL_VERSION => {                  #  Model / Version
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00001100,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ERROR_FLAGS => {                    #  Error flags (binary)
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00010111,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcHex,
  },
  VIF_DURATION_SINCE_LAST_READOUT => {    #   Duration since last readout [sec(s)..day(s)]
    typeMask     => 0b01111100,
    expMask      => 0b00000011,
    type         => 0b00101100,
    bias         => 0,
    unit         => 's',
    calcFunc     => \&valueCalcTimeperiod,
  },
  VIF_VOLTAGE => {                        #  10nnnn-9 Volts
    typeMask     => 0b01110000,
    expMask      => 0b00001111,
    type         => 0b01000000,
    bias         => -9,
    unit         => 'V',
    calcFunc     => \&valueCalcNumeric,
  },  
  VIF_ELECTRICAL_CURRENT => {             #  10nnnn-12 Ampere
    typeMask     => 0b01110000,
    expMask      => 0b00001111,
    type         => 0b01010000,
    bias         => -12,
    unit         => 'A',
    calcFunc     => \&valueCalcNumeric,
  },  
  VIF_RECEPTION_LEVEL => {                  #   reception level of a received radio device.
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01110001,
    bias         => 0,
    unit         => 'dBm',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_FD_RESERVED => {                   # Reserved
    typeMask     => 0b01110000,
    expMask      => 0b00000000,
    type         => 0b01110000,
    bias         => 0,
    unit         => 'Reserved',
  },
  
);

# Codes used with extension indicator $FB
my %VIFInfo_FB = (                              
  VIF_ENERGY  => {                     #  Energy 10(n-1) MWh  0.1MWh to 1MWh
    typeMask     => 0b01111110,
    expMask      => 0b00000001,
    type         => 0b00000000,
    bias         => -1,
    unit         => 'MWh',
    calcFunc     => \&valueCalcNumeric,
  },
);


# Codes used for an enhancement of VIFs other than $FD and $FB
my %VIFInfo_other = (       
  VIF_ERROR_NONE => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00000000,
    bias         => 0,
    unit         => 'No error',
  },
  VIF_TOO_MANY_DIFES => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00000001,
    bias         => 0,
    unit         => 'Too many DIFEs',
  },

  VIF_ILLEGAL_VIF_GROUP => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00001100,
    bias         => 0,
    unit         => 'Illegal VIF-Group',
  },



  VIF_PER_SECOND => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100000,
    bias         => 0,
    unit         => 'per second',
  },
  VIF_PER_MINUTE => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100001,
    bias         => 0,
    unit         => 'per minute',
  },
  VIF_PER_HOUR => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100010,
    bias         => 0,
    unit         => 'per hour',
  },
  VIF_PER_DAY => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100011,
    bias         => 0,
    unit         => 'per day',
  },
  VIF_PER_WEEK => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100100,
    bias         => 0,
    unit         => 'per week',
  },
  VIF_PER_MONTH => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100101,
    bias         => 0,
    unit         => 'per month',
  },
  VIF_PER_YEAR => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100110,
    bias         => 0,
    unit         => 'per year',
  },
  VIF_PER_REVOLUTION => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00100111,
    bias         => 0,
    unit         => 'per revolution/measurement',
  },
  VIF_PER_INCREMENT_INPUT => {
    typeMask     => 0b01111110,
    expMask      => 0b00000000,
    type         => 0b00101000,
    bias         => 0,
    unit         => 'increment per input pulse on input channnel #',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_PER_INCREMENT_OUTPUT => {
    typeMask     => 0b01111110,
    expMask      => 0b00000000,
    type         => 0b00101010,
    bias         => 0,
    unit         => 'increment per output pulse on output channnel #',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_PER_LITER => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00101100,
    bias         => 0,
    unit         => 'per liter',
  },

  VIF_START_DATE_TIME => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00111001,
    bias         => 0,
    unit         => 'start date(/time) of',
  },
  
  VIF_ACCUMULATION_IF_POSITIVE => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b00111011,
    bias         => 0,
    unit         => 'Accumulation only if positive contribution',
  },
  
  VIF_DURATION_NO_EXCEEDS => {
    typeMask     => 0b01110111,
    expMask      => 0b00000000,
    type         => 0b01000001,
    bias         => 0,
    unit         => '# of exceeds',
    calcFunc     => \&valueCalcu,
  },

  VIF_DURATION_LIMIT_EXCEEDED => {
    typeMask     => 0b01110000,
    expMask      => 0b00000000,
    type         => 0b01010000,
    bias         => 0,
    unit         => 'duration of limit exceeded',
    calcFunc     => \&valueCalcufnn,
  },

  VIF_MULTIPLICATIVE_CORRECTION_FACTOR => {
    typeMask     => 0b01111000,
    expMask      => 0b00000111,
    type         => 0b01110000,
    bias         => -6,
    unit         => '',
  },  
  VIF_MULTIPLICATIVE_CORRECTION_FACTOR_1000 => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01111101,
    bias         => 0,
    unit         => '',
    calcFunc     => \&valueCalcMultCorr1000,
  },  
  VIF_FUTURE_VALUE => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01111110,
    bias         => 0,
    unit         => '',
  },  
  VIF_MANUFACTURER_SPECIFIC => {
    typeMask     => 0b01111111,
    expMask      => 0b00000000,
    type         => 0b01111111,
    bias         => 0,
    unit         => 'manufacturer specific',
  },  
  
);

# For Easymeter (manufacturer specific)
my %VIFInfo_ESY = (       
  VIF_ELECTRIC_POWER_PHASE => {
    typeMask     => 0b01000000,
    expMask      => 0b00000000,
    type         => 0b00000000,
    bias         => -2,
    unit         => 'W',
    calcFunc     => \&valueCalcNumeric,
  },
  VIF_ELECTRIC_POWER_PHASE_NO => {
    typeMask     => 0b01111110,
    expMask      => 0b00000000,
    type         => 0b00101000,
    bias         => 0,
    unit         => 'phase #',
    calcFunc     => \&valueCalcNumeric,
  },
);

# For Kamstrup (manufacturer specific)
my %VIFInfo_KAM = (       
  VIF_KAMSTRUP_INFO => {
    typeMask     => 0b00000000,
    expMask      => 0b00000000,
    type         => 0b00000000,
    bias         => 0,
    unit         => '',
  },
);


# see 4.2.3, page 24
my %validDeviceTypes = (
 0x00 => 'Other',
 0x01 => 'Oil',
 0x02 => 'Electricity',
 0x03 => 'Gas',
 0x04 => 'Heat',
 0x05 => 'Steam',
 0x06 => 'Warm Water (30 °C ... 90 °C)',
 0x07 => 'Water',
 0x08 => 'Heat Cost Allocator',
 0x09 => 'Compressed Air',
 0x0a => 'Cooling load meter (Volume measured at return temperature: outlet)',
 0x0b => 'Cooling load meter (Volume measured at flow temperature: inlet)',
 0x0c => 'Heat (Volume measured at flow temperature: inlet)',
 0x0d => 'Heat / Cooling load meter',
 0x0e => 'Bus / System component',
 0x0f => 'Unknown Medium',
 0x10 => 'Reserved for utility meter',
 0x11 => 'Reserved for utility meter',
 0x12 => 'Reserved for utility meter',
 0x13 => 'Reserved for utility meter',
 0x14 => 'Calorific value',
 0x15 => 'Hot water (> 90 °C)',
 0x16 => 'Cold water',
 0x17 => 'Dual register (hot/cold) Water meter',
 0x18 => 'Pressure',
 0x19 => 'A/D Converter',
 0x1a => 'Smokedetector',
 0x1b => 'Room sensor (e.g. temperature or humidity)',
 0x1c => 'Gasdetector',
 0x1d => 'Reserved for sensors',
 0x1e => 'Reserved for sensors',
 0x1f => 'Reserved for sensors',
 0x20 => 'Breaker (electricity)',
 0x21 => 'Valve (gas)',
 0x22 => 'Reserved for switching devices',
 0x23 => 'Reserved for switching devices',
 0x24 => 'Reserved for switching devices',
 0x25 => 'Customer unit (Display device)',
 0x26 => 'Reserved for customer units',
 0x27 => 'Reserved for customer units',
 0x28 => 'Waste water',
 0x29 => 'Garbage',
 0x2a => 'Carbon dioxide',
 0x2b => 'Environmental meter',
 0x2c => 'Environmental meter',
 0x2d => 'Environmental meter',
 0x2e => 'Environmental meter',
 0x2f => 'Environmental meter',
 0x31 => 'OMS MUC',
 0x32 => 'OMS unidirectional repeater',
 0x33 => 'OMS bidirectional repeater',
 0x37 => 'Radio converter (Meter side)',
);


# bitfield, errors can be combined, see 4.2.3.2 on page 22
my %validStates = (
  0x00 => 'no errors',
  0x01 => 'application busy',
  0x02 => 'any application error',
  0x03 => 'abnormal condition/alarm',
  0x04 => 'battery low',
  0x08 => 'permanent error',
  0x10 => 'temporary error',
  0x20 => 'specific to manufacturer',
  0x40 => 'specific to manufacturer',
  0x80 => 'specific to manufacturer',
  
);

my %encryptionModes = (
  0x00 => 'standard unsigned',
  0x01 => 'signed data telegram',
  0x02 => 'static telegram',
  0x03 => 'reserved',
);

my %functionFieldTypes = (
  0b00 => 'Instantaneous value',
  0b01 => 'Maximum value',
  0b10 => 'Minimum value',
  0b11 => 'Value during error state',
);


sub type2string($$) {
  my $class = shift;
  my $type = shift;
  
  return $validDeviceTypes{$type} || 'unknown';
}

sub state2string($$) {
  my $class = shift;
  my $state = shift;
  
  my @result = ();
  
  if ($state) {
    foreach my $stateMask ( keys %validStates ) {
      push @result, $validStates{$stateMask} if $state & $stateMask;
    }
  } else {
    @result = ($validStates{0});
  }
  return @result;
}


sub checkCRC($$) {
  my $self = shift;
  my $data = shift;
  my $ctx = Digest::CRC->new(width=>16, init=>0x0000, xorout=>0xffff, refout=>0, poly=>0x3D65, refin=>0, cont=>0);

  $ctx->add($data);

  return $ctx->digest;  
}


sub removeCRC($$)
{
  my $self = shift;
  my $msg = shift;
  my $i;
  my $res;
  my $crc;
  my $blocksize = LL_BLOCK_SIZE;
  my $blocksize_with_crc = LL_BLOCK_SIZE + $self->{crc_size};
  my $crcoffset;
  
  my $msgLen = $self->{datalen}; # size without CRCs
  my $noOfBlocks = $self->{datablocks}; # total number of data blocks, each with a CRC appended
  my $rest = $msgLen % LL_BLOCK_SIZE; # size of the last data block, can be smaller than 16 bytes
  
  
  #print "crc_size $self->{crc_size}\n";
  
  return $msg if $self->{crc_size} == 0;

  # each block is 16 bytes + 2 bytes CRC
  
  #print "Länge $msgLen Anz. Blöcke $noOfBlocks rest $rest\n";
  
  for ($i=0; $i < $noOfBlocks; $i++) {
    $crcoffset = $blocksize_with_crc * $i + LL_BLOCK_SIZE;
    #print "$i: crc offset $crcoffset\n";
    if ($rest > 0 && $crcoffset + $self->{crc_size} > ($noOfBlocks - 1) * $blocksize_with_crc + $rest) {
      # last block is smaller
      $crcoffset = ($noOfBlocks - 1) * $blocksize_with_crc + $rest;
      #print "last crc offset $crcoffset\n";
      $blocksize = $msgLen - ($i * $blocksize); 
    }
    
    $crc = unpack('n',substr($msg, $crcoffset, $self->{crc_size}));
    #printf("%d: CRC %x, calc %x blocksize $blocksize\n", $i, $crc, $self->checkCRC(substr($msg, $blocksize_with_crc*$i, $blocksize))); 
    if ($crc != $self->checkCRC(substr($msg, $blocksize_with_crc*$i, $blocksize))) {
      $self->{errormsg} = "crc check failed for block $i";
      $self->{errorcode} = ERR_CRC_FAILED;
      return 0;
    }
    $res .= substr($msg, $blocksize_with_crc*$i, $blocksize);
  }

  return $res;
}


sub manId2hex($$)
{
  my $class = shift;
  my $idascii = shift;
  
  return (ord(substr($idascii,1,1))-64) << 10 | (ord(substr($idascii,2,1))-64) << 5 | (ord(substr($idascii,3,1))-64);
}

sub manId2ascii($$)
{
  my $class = shift;
  my $idhex = shift;
    
  return chr(($idhex >> 10) + 64) . chr((($idhex >> 5) & 0b00011111) + 64) . chr(($idhex & 0b00011111) + 64);
}


sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;
  
  $self->_initialize();
  return $self;
}

sub _initialize {
  my $self = shift;
  
  $self->{crc_size} = CRC_SIZE;
  $self->{frame_type} = FRAME_TYPE_A; # default
}

sub setCRCsize {
  my $self = shift;

  $self->{crc_size} = shift;
}

sub getCRCsize {
  my $self = shift;

  return $self->{crc_size};
}

sub decodeConfigword($) {
  my $self = shift;
  
  #printf("cw: %01x %01x\n", $self->{cw_1}, $self->{cw_2});
  $self->{cw_parts}{mode}             = ($self->{cw_2} & 0b00011111);
  #printf("mode: %02x\n", $self->{cw_parts}{mode});
  if ($self->{cw_parts}{mode} == 5 || $self->{cw_parts}{mode} == 0) {
    $self->{cw_parts}{bidirectional}    = ($self->{cw_2} & 0b10000000) >> 7;
    $self->{cw_parts}{accessability}    = ($self->{cw_2} & 0b01000000) >> 6;
    $self->{cw_parts}{synchronous}      = ($self->{cw_2} & 0b00100000) >> 5;
    $self->{cw_parts}{encrypted_blocks} = ($self->{cw_1} & 0b11110000) >> 4;
    $self->{cw_parts}{content}          = ($self->{cw_1} & 0b00001100) >> 2;
    $self->{cw_parts}{repeated_access}  = ($self->{cw_1} & 0b00000010) >> 1;
    $self->{cw_parts}{hops}             = ($self->{cw_1} & 0b00000001);
  } #elsif ($self->{cw_parts}{mode} == 7) {
    # ToDo: wo kommt das dritte Byte her?
  #  $self->{cw_parts}{mode}             = $self->{cw} & 0b0000111100000000 >> 8;
  #}
}

sub decodeBCD($$$) {
  my $self = shift;
  my $digits = shift;
  my $bcd = shift;
  my $byte;
  my $val=0;
  my $mult=1;
  
  #print "bcd:" . unpack("H*", $bcd) . "\n";
  
  for (my $i = 0; $i < $digits/2; $i++) {
    $byte = unpack('C',substr($bcd, $i, 1));
    $val += ($byte & 0x0f) * $mult;
    $mult *= 10;
    $val += (($byte & 0xf0) >> 4) * $mult;
    $mult *= 10;
  }
  return $val;
}

sub findVIF($$$) {
  my $vif = shift;
  my $vifInfoRef = shift;
  my $dataBlockRef = shift;
  my $bias;
  
  if (defined $vifInfoRef) {
    VIFID: foreach my $vifType ( keys %$vifInfoRef ) { 
    
      #printf "vifType $vifType VIF $vif typeMask $vifInfoRef->{$vifType}{typeMask} type $vifInfoRef->{$vifType}{type}\n"; 
    
      if (($vif & $vifInfoRef->{$vifType}{typeMask}) == $vifInfoRef->{$vifType}{type}) {
        #printf " match vifType $vifType\n"; 
        
        $bias = $vifInfoRef->{$vifType}{bias};
        $dataBlockRef->{exponent} = $vif & $vifInfoRef->{$vifType}{expMask};
        
        $dataBlockRef->{type} = $vifType;
        $dataBlockRef->{unit} = $vifInfoRef->{$vifType}{unit};
        if (defined $dataBlockRef->{exponent} && defined $bias) {
          $dataBlockRef->{valueFactor} = 10 ** ($dataBlockRef->{exponent} + $bias);
        } else {
          $dataBlockRef->{valueFactor} = 1;
        }
        $dataBlockRef->{calcFunc} = $vifInfoRef->{$vifType}{calcFunc};
        
        #printf("type %s bias %d exp %d valueFactor %d unit %s\n", $dataBlockRef->{type}, $bias, $dataBlockRef->{exponent}, $dataBlockRef->{valueFactor},$dataBlockRef->{unit});
        return 1;
      }
    }
    #printf "no match!\n";
    return 0;
  }
  return 1;
}

sub decodeValueInformationBlock($$$) {
  my $self = shift;
  my $vib = shift;
  my $dataBlockRef = shift;
  
  my $offset = 0;
  my $vif;
  my $vifInfoRef;
  my $vifExtension = 0;
  my $vifExtNo = 0;
  my $isExtension;
  my $dataBlockExt;
  my @VIFExtensions = ();
  my $analyzeVIF = 1;

  $dataBlockRef->{type}  = '';
  # The unit and multiplier is taken from the table for primary VIF
  $vifInfoRef = \%VIFInfo;
  

  EXTENSION: while (1) {
    $vif = unpack('C', substr($vib,$offset++,1));
    $isExtension = $vif & VIF_EXTENSION_BIT;
    #printf("vif: %x isExtension %d\n", $vif, $isExtension);
    
    # Is this an extension?
    last EXTENSION if (!$isExtension);
    
    # yes, process extension

    $vifExtNo++;
    if ($vifExtNo > 10) {
      $dataBlockRef->{errormsg} = 'too many VIFE';
      $dataBlockRef->{errorcode} = ERR_TOO_MANY_VIFE;
      last EXTENSION;
    }
    
    # switch to extension codes
    $vifExtension = $vif;
    $vif &= ~VIF_EXTENSION_BIT;
    #printf("vif ohne extension: %x\n", $vif);
    if ($vif == 0x7D) {
      $vifInfoRef = \%VIFInfo_FD;
    } elsif ($vif == 0x7B) {
      $vifInfoRef = \%VIFInfo_FB;
    } elsif ($vif == 0x7C) {
      # Plaintext VIF
      my $vifLength = unpack('C', substr($vib,$offset++,1));
      $dataBlockRef->{type} = "see unit";
      $dataBlockRef->{unit} = unpack(sprintf("C%d",$vifLength), substr($vib, $offset, $vifLength));
      $offset += $vifLength;
      $analyzeVIF = 0;
      last EXTENSION;
    } elsif ($vif == 0x7F) {
      
      if ($self->{manufacturer} eq 'ESY') {
        # Easymeter
        $vif = unpack('C', substr($vib,$offset++,1));
        $vifInfoRef = \%VIFInfo_ESY;
      } elsif ($self->{manufacturer} eq 'KAM') {
        $vif = unpack('C', substr($vib,$offset++,1));
        $vifInfoRef = \%VIFInfo_KAM;       
      } else {
        # manufacturer specific data, can't be interpreted
        
        $dataBlockRef->{type} = "MANUFACTURER SPECIFIC";
        $dataBlockRef->{unit} = "";
        $analyzeVIF = 0;
      }
      last EXTENSION;
    } else {
      # enhancement of VIFs other than $FD and $FB (see page 84ff.)
      #print "other extension\n";
      $dataBlockExt = {};
      if ($self->{manufacturer} eq 'ESY') {
        $vifInfoRef = \%VIFInfo_ESY;
        $dataBlockExt->{value} = unpack('C',substr($vib,2,1)) * 100;
      } else {
        $dataBlockExt->{value} = $vif;
        $vifInfoRef = \%VIFInfo_other;
      }
      
      if (findVIF($vif, $vifInfoRef, $dataBlockExt)) {
        push @VIFExtensions, $dataBlockExt;
      } else {
        $dataBlockRef->{type} = 'unknown';
        $dataBlockRef->{errormsg} = "unknown VIFE " . sprintf("%x", $vifExtension) . " at offset " . ($offset-1);
        $dataBlockRef->{errorcode} = ERR_UNKNOWN_VIFE;    
      }    
    }
    last EXTENSION if (!$isExtension);
  }

  if ($analyzeVIF) {  
    if (findVIF($vif, $vifInfoRef, $dataBlockRef) == 0) {
      $dataBlockRef->{errormsg} = "unknown VIF " . sprintf("%x", $vifExtension) . " at offset " . ($offset-1);
      $dataBlockRef->{errorcode} = ERR_UNKNOWN_VIFE;    
    }
  }
  $dataBlockRef->{VIFExtensions} = \@VIFExtensions;

  if ($dataBlockRef->{type} eq '') {
    $dataBlockRef->{type} = 'unknown';
    $dataBlockRef->{errormsg} = sprintf("in VIFExtension %x unknown VIF %x",$vifExtension, $vif);
    $dataBlockRef->{errorcode} = ERR_UNKNOWN_VIF;
  }
  
  return $offset;
  
  
}


sub decodeDataInformationBlock($$$) {
  my $self = shift;
  my $dib = shift;
  my $dataBlockRef = shift;
  
  my $dif;
  my $tariff = 0;
  my $difExtNo = 0;
  my $offset;
  my $devUnit = 0;
  
  $dif = unpack('C', $dib);
  $offset = 1;
  my $isExtension = $dif & DIF_EXTENSION_BIT;
  my $storageNo = ($dif & 0b01000000) >> 6;
  my $functionField = ($dif & 0b00110000) >> 4;
  my $df = $dif & 0b00001111;

  #printf("dif %x storage %d\n", $dif, $storageNo);
  
  EXTENSION: while ($isExtension) {
    $dif = unpack('C', substr($dib,$offset,1));
    last EXTENSION if (!defined $dif);
    $offset++;
    $isExtension = $dif & DIF_EXTENSION_BIT;
    $difExtNo++;
    if ($difExtNo > 10) {
      $dataBlockRef->{errormsg} = 'too many DIFE';
      $dataBlockRef->{errorcode} = ERR_TOO_MANY_DIFE;
      last EXTENSION;
    }
    
    $storageNo |= ($dif & 0b00001111) << ($difExtNo*4)+1;
    $tariff    |= (($dif & 0b00110000 >> 4)) << (($difExtNo-1)*2);
    $devUnit   |= (($dif & 0b01000000 >> 6)) << ($difExtNo-1);
    #printf("dife %x extno %d storage %d\n", $dif, $difExtNo, $storageNo);
  }
  
  $dataBlockRef->{functionField} = $functionField;
  $dataBlockRef->{functionFieldText} = $functionFieldTypes{$functionField};
  $dataBlockRef->{dataField} = $df;
  $dataBlockRef->{storageNo} = $storageNo;
  $dataBlockRef->{tariff} = $tariff;
  $dataBlockRef->{devUnit} = $devUnit;
  
  #printf("in DIF: datafield %x\n", $dataBlockRef->{dataField});
  #print "offset in dif $offset\n";
  return $offset;
}

sub decodeDataRecordHeader($$$) {
  my $self = shift;
  my $drh = shift;
  my $dataBlockRef = shift;
  
  my $offset = $self->decodeDataInformationBlock($drh,$dataBlockRef);

  
  $offset += $self->decodeValueInformationBlock(substr($drh,$offset),$dataBlockRef);
  #printf("in DRH: type %s\n", $dataBlockRef->{type});
  
  return $offset;
}



sub decodePayload($$) {
  my $self = shift;
  my $payload = shift;
  my $offset = 0;
  my $dif;
  my $vif;
  my $scale;
  my $value;
  my $dataBlockNo = 0;
  
  
  my @dataBlocks = ();
  my $dataBlock;

  
  PAYLOAD: while ($offset < length($payload)) {
    $dataBlockNo++;
    
    # create a new anonymous hash reference
    $dataBlock = {};
    $dataBlock->{number} = $dataBlockNo;
    $dataBlock->{unit} = '';
    
    while (unpack('C',substr($payload,$offset,1)) == 0x2f) {
      # skip filler bytes
      #printf("skipping filler at offset %d of %d\n", $offset, length($payload));
      $offset++;
      if ($offset >= length($payload)) {
        last PAYLOAD;
      }
    }
    
    $offset += $self->decodeDataRecordHeader(substr($payload,$offset), $dataBlock);
    #printf("No. %d, type %x at offset %d\n", $dataBlockNo, $dataBlock->{dataField}, $offset-1);
    
    if ($dataBlock->{dataField} == DIF_NONE) {
    } elsif ($dataBlock->{dataField} == DIF_READOUT) {
      $self->{errormsg} = "in datablock $dataBlockNo: unexpected DIF_READOUT";
      $self->{errorcode} = ERR_UNKNOWN_DATAFIELD;
      return 0;
    } elsif ($dataBlock->{dataField} == DIF_BCD2) {
      $value = $self->decodeBCD(2, substr($payload,$offset,1));
      $offset += 1;
    } elsif ($dataBlock->{dataField} == DIF_BCD4) {
      $value = $self->decodeBCD(4, substr($payload,$offset,2));
      $offset += 2;
    } elsif ($dataBlock->{dataField} == DIF_BCD6) {
      $value = $self->decodeBCD(6, substr($payload,$offset,3));
      $offset += 3;
    } elsif ($dataBlock->{dataField} == DIF_BCD8) {
      $value = $self->decodeBCD(8, substr($payload,$offset,4));
      $offset += 4;
    } elsif ($dataBlock->{dataField} == DIF_BCD12) {
      $value = $self->decodeBCD(12, substr($payload,$offset,6));
      $offset += 6;
    } elsif ($dataBlock->{dataField} == DIF_INT8) {
      $value = unpack('C', substr($payload, $offset, 1));
      $offset += 1;
    } elsif ($dataBlock->{dataField} == DIF_INT16) {
      $value = unpack('v', substr($payload, $offset, 2));
      $offset += 2;
    } elsif ($dataBlock->{dataField} == DIF_INT24) {
      my @bytes = unpack('CCC', substr($payload, $offset, 3));
      $offset += 3;
      $value = $bytes[0] + $bytes[1] << 8 + $bytes[2] << 16;
    } elsif ($dataBlock->{dataField} == DIF_INT32) {
      $value = unpack('V', substr($payload, $offset, 4));
      $offset += 4;
    } elsif ($dataBlock->{dataField} == DIF_INT48) {
      my @words = unpack('vvv', substr($payload, $offset, 6));
      $value = $words[0] + $words[1] << 16 + $words[2] << 32;
      $offset += 6;
    } elsif ($dataBlock->{dataField} == DIF_INT64) {
      $value = unpack('Q<', substr($payload, $offset, 8));
      $offset += 8;
    } elsif ($dataBlock->{dataField} == DIF_FLOAT32) {
      #not allowed according to wmbus standard, Qundis seems to use it nevertheless
      $value = unpack('f', substr($payload, $offset, 4));
      $offset += 4;
    } elsif ($dataBlock->{dataField} == DIF_VARLEN) {
      my $lvar = unpack('C',substr($payload, $offset++, 1));
      #print "in datablock $dataBlockNo: LVAR field " . sprintf("%x", $lvar) . "\n";
      #printf "payload len %d offset %d\n", length($payload), $offset;
      if ($lvar <= 0xbf) {
        if ($dataBlock->{type} eq "MANUFACTURER SPECIFIC") {
          # special handling, LSE seems to lie about this
          $value = unpack('H*',substr($payload, $offset, $lvar));
          #print "VALUE: " . $value . "\n";
        } else {
          #  ASCII string with LVAR characters
          $value = unpack('a*',substr($payload, $offset, $lvar));
          if ($self->{manufacturer} eq 'ESY') {
            # Easymeter stores the string backwards!
            $value = reverse($value);
          }
        }
        $offset += $lvar;
      } elsif ($lvar >= 0xc0 && $lvar <= 0xcf) {
        #  positive BCD number with (LVAR - C0h) • 2 digits
        $value = $self->decodeBCD(($lvar-0xc0)*2, substr($payload,$offset,($lvar-0xc0)));
        $offset += ($lvar-0xc0);
      } elsif ($lvar >= 0xd0 && $lvar <= 0xdf) {
        #  negative BCD number with (LVAR - D0h) • 2 digits
        $value = -$self->decodeBCD(($lvar-0xd0)*2, substr($payload,$offset,($lvar-0xd0)));
        $offset += ($lvar-0xd0);
      } else {
        $self->{errormsg} = "in datablock $dataBlockNo: unhandled LVAR field " . sprintf("%x", $lvar);
        $self->{errorcode} = ERR_UNKNOWN_LVAR;
        return 0;
      }
    } elsif ($dataBlock->{dataField} == DIF_SPECIAL) {
      # special functions
      #print "DIF_SPECIAL at $offset\n";
      $value = unpack("H*", substr($payload,$offset));
      last PAYLOAD;
    }  else {
      $self->{errormsg} = "in datablock $dataBlockNo: unhandled datafield " . sprintf("%x",$dataBlock->{dataField});
      $self->{errorcode} = ERR_UNKNOWN_DATAFIELD;
      return 0;
    }
    
    if (defined $dataBlock->{calcFunc}) {
      $dataBlock->{value} = $dataBlock->{calcFunc}->($value, $dataBlock); 
      #print "Value raw " . $value . " value calc " . $dataBlock->{value} ."\n";
    } elsif (defined $value) {
      $dataBlock->{value} = $value;
    } else {
      $dataBlock->{value} = "";
    }
    
    my $VIFExtensions = $dataBlock->{VIFExtensions};
    for my $VIFExtension (@$VIFExtensions) {
      $dataBlock->{extension} = $VIFExtension->{unit};
      if (defined $VIFExtension->{calcFunc}) {
        #printf("Extension value %d, valueFactor %d\n", $VIFExtension->{value}, $VIFExtension->{valueFactor});
        $dataBlock->{extension} .= ", " . $VIFExtension->{calcFunc}->($VIFExtension->{value}, $dataBlock); 
      } elsif (defined $VIFExtension->{value}) {
        $dataBlock->{extension} .= ", " . sprintf("%x",$VIFExtension->{value});
      } else {
        #$dataBlock->{extension} = "";
      }
    }
    undef $value;
    
    push @dataBlocks, $dataBlock;
  }
  
  $self->{datablocks} = \@dataBlocks;
  return 1;
}

sub decrypt($) {
  my $self = shift;
  my $encrypted = shift;
  
  # see 4.2.5.3, page 26      
  my $initVector = substr($self->{msg},2,8);
  for (1..8) {
    $initVector .= pack('C',$self->{access_no});
  }
  my $cipher = Crypt::Mode::CBC->new('AES', 2);
  return $cipher->decrypt($encrypted, $self->{aeskey}, $initVector);
}

sub decrypt_mode7($) {
  my $self = shift;
  my $encrypted = shift;
  
  # see 9.2.4, page 59      
  my $initVector = '';
  for (1..16) {
    $initVector .= pack('C',0x00);
  }
  my $cipher = Crypt::Mode::CBC->new('AES', 2);
  return $cipher->decrypt($encrypted, $self->{aeskey}, $initVector);
}

# Generate MAC of data
#
# Parameter 1: private key as byte string, 16bytes
# Parameter 2: data fro which mac should be calculated in hexadecimal format, len variable
# Parameter 3: length of MAC to be generated in bytes
#
# Returns: MAC in hexadecimal format
#
# This function currently supports data with lentgh of less then 16bytes,
# MAC for longer data is untested but specified
#
# copied from 10_EnOcean.pm
sub generateMAC($$$$) {
  my $self = shift;
	my $private_key = $_[0];
	my $data = $_[1];
	my $cmac_len = $_[2];

	#print "Calculating MAC for data $data\n";

	# Pack data to 16byte byte string, padd with 10..0 binary
	my $data_expanded = pack('H32', $data.'80');

	#print "Exp. data  ".unpack('H32', $data_expanded)."\n";

	# Constants according to specification
	my $const_zero = pack('H32','00');
	my $const_rb = pack('H32', '00000000000000000000000000000087');

	# Encrypt zero data with private key to get L
	my $cipher = Crypt::Rijndael->new($private_key);
  my $l = $cipher->encrypt($const_zero);
	#print "L          ".unpack('H32', $l)."\n";
	#print "L          ".unpack('B128', $l)."\n";

	# Expand L to 128bit string
	my $l_bit = unpack('B128', $l);

	# K1 and K2 stored as 128bit string
	my $k1_bit;
	my $k2_bit;

	# K1 and K2 as binary
	my $k1;
	my $k2;

	# Store L << 1 in K1
	$l_bit =~ /^.(.{127})/;
	$k1_bit = $1.'0';
	$k1 = pack('B128', $k1_bit);

	# If MSB of L == 1, K1 = K1 XOR const_Rb
	if($l_bit =~ m/^1/) {
		#print "MSB of L is set\n";
		$k1 = $k1 ^ $const_rb;
		$k1_bit = unpack('B128', $k1);
	} else {
		#print "MSB of L is unset\n";
	}

	# Store K1 << 1 in K2
	$k1_bit =~ /^.(.{127})/;
	$k2_bit = $1.'0';
	$k2 = pack('B128', $k2_bit);

	# If MSB of K1 == 1, K2 = K2 XOR const_Rb
	if($k1_bit =~ m/^1/) {
		#print "MSB of K1 is set\n";
		$k2 = $k2 ^ $const_rb;
	} else {
		#print "MSB of K1 is unset\n";
	}

	# XOR data with K2
	$data_expanded ^= $k2;

	# Encrypt data
	my $cmac = $cipher->encrypt($data_expanded);

	#print "CMAC ".unpack('H32', $cmac)."\n";

	# Extract specified len of MAC
	my $cmac_pattern = '^(.{'.($cmac_len * 2).'})';
	unpack('H32', $cmac) =~ /$cmac_pattern/;

	# Return MAC in hexadecimal format
	return uc($1);
}


sub decodeAFL($$) {
  my $self = shift;
  my $afl = shift;
  my $offset = 0;
  
  
  $self->{afl}{fcl} = unpack('v', $afl);
  $offset += 2;
  $self->{afl}{fcl_mf}   = ($self->{afl}{fcl} & 0b0100000000000000) != 0;
  $self->{afl}{fcl_mclp} = ($self->{afl}{fcl} & 0b0010000000000000) != 0;
  $self->{afl}{fcl_mlp}  = ($self->{afl}{fcl} & 0b0001000000000000) != 0;
  $self->{afl}{fcl_mcrp} = ($self->{afl}{fcl} & 0b0000100000000000) != 0;
  $self->{afl}{fcl_macp} = ($self->{afl}{fcl} & 0b0000010000000000) != 0;
  $self->{afl}{fcl_kip}  = ($self->{afl}{fcl} & 0b0000001000000000) != 0;
  $self->{afl}{fcl_fid}  =  $self->{afl}{fcl} & 0b0000000011111111;
  
  if ($self->{afl}{fcl_mclp}) {
    # AFL Message Control Field (AFL.MCL)
    $self->{afl}{mcl} = unpack('C', substr($afl, $offset, 1));
    $offset += 1;
    $self->{afl}{mcl_mlmp} = ($self->{afl}{mcl} & 0b01000000) != 0; 
    $self->{afl}{mcl_mcmp} = ($self->{afl}{mcl} & 0b00100000) != 0; 
    $self->{afl}{mcl_kimp} = ($self->{afl}{mcl} & 0b00010000) != 0; 
    $self->{afl}{mcl_at}   = ($self->{afl}{mcl} & 0b00001111); 
  }
  if ($self->{afl}{fcl_mcrp}) {
    # AFL Message Counter Field (AFL.MCR)
    $self->{afl}{mcr} = unpack('V', substr($afl, $offset));
    #printf "AFL MC %08x\n", $self->{afl}{mcr};
    $offset += 4;
  }
  if ($self->{afl}{fcl_mlp}) {
    # AFL Message Length Field (AFL.ML)
    $self->{afl}{ml} = unpack('v', substr($afl, $offset));
    $offset += 2;
  }
  if ($self->{afl}{fcl_macp}) {
    # AFL MAC Field (AFL.MCL)
    # The length of the MAC field depends on the selected option AFL.MCL.AT indicated by the
    # AFL.MCL field.
    my $mac_len = 0;
    if ($self->{afl}{mcl_at} == 4) {
      $mac_len = 4;
      $self->{afl}{mac} = unpack('N', substr($afl, $offset, $mac_len));
    } elsif ($self->{afl}{mcl_at} == 5) { 
      $mac_len = 8;
      $self->{afl}{mac} = (unpack('N', substr($afl, $offset, 4))) << 32 | ((unpack('N', substr($afl, $offset+4, 4))));
    } elsif ($self->{afl}{mcl_at} == 6) { 
      $mac_len = 12;
    } elsif ($self->{afl}{mcl_at} == 7) { 
      $mac_len = 16;
    }
    #printf "AFL MAC %16x\n", $self->{afl}{mac};
    $offset += $mac_len;
  }
  if ($self->{afl}{fcl_kip}) {
    # AFL Key Information-Field (AFL.KI)
    $self->{afl}{ki} = unpack('v', $afl);
    $self->{afl}{ki_key_version}   = ($self->{afl}{ki} & 0b1111111100000000) >> 8;
    $self->{afl}{ki_kdf_selection} = ($self->{afl}{ki} & 0b0000000001110000) >> 4;
    $self->{afl}{ki_key_id}        = ($self->{afl}{ki} & 0b0000000000001111);
    $offset += 2;
  }
  return $offset;
}

sub decodeApplicationLayer($) {
  my $self = shift;
  my $applicationlayer = $self->{applicationlayer};
  my $payload;
  
  #print unpack("H*", $applicationlayer) . "\n";
  
  if ($self->{errorcode} != ERR_NO_ERROR) {
    # CRC check failed
    return 0;
  }
  $self->{cifield} = unpack('C', $applicationlayer);

  my $offset = 1;

  if ($self->{cifield} == CI_ELL_2) {
    # Extended Link Layer
    ($self->{ell}{cc}, $self->{ell}{access_no}) = unpack('CC', substr($applicationlayer,$offset));
    $offset += 2;
  } elsif ($self->{cifield} == CI_ELL_6) {
    # Extended Link Layer
    ($self->{ell}{cc}, $self->{ell}{access_no}) = unpack('CC', substr($applicationlayer,$offset));
    $offset += 6;
  } elsif ($self->{cifield} == CI_ELL_8) {
    # Extended Link Layer, payload CRC is part of (encrypted) payload
    ($self->{ell}{cc}, $self->{ell}{access_no}, $self->{ell}{session_number}) = unpack('CCV', substr($applicationlayer, $offset));
    $offset += 6;
  } elsif ($self->{cifield} == CI_ELL_16) {
    # Extended Link Layer
    ($self->{ell}{cc}, $self->{ell}{access_no}, $self->{ell}{m2}, $self->{ell}{a2}, $self->{ell}{session_number}) = unpack('CCvC6V', substr($applicationlayer,$offset));
    $offset += 14;
  }
  
  if (exists($self->{ell})) {
    $self->{ell}{session_number_enc} = $self->{ell}{session_number} >> 29;
    $self->{ell}{session_number_time} = ($self->{ell}{session_number} & 0b0001111111111111111111111111111) >> 4;
    $self->{ell}{session_number_session} = $self->{ell}{session_number} & 0b1111;
    $self->{isEncrypted} = $self->{ell}{session_number_enc} != 0;
    $self->{decrypted} = 0;
    
    if ($self->{isEncrypted}) {
      if ($self->{aeskey}) {
        if ($hasCTR) {
          # AES IV
          # M-field, A-field, CC, SN, 00, 0000
          my $initVector = pack("v", $self->{mfield}) . $self->{afield} . pack("CV", $self->{ell}{cc}, $self->{ell}{session_number}) . pack("H*", "000000");
          my $m = Crypt::Mode::CTR->new('AES', 1);
          my $ciphertext = substr($applicationlayer,$offset); # payload CRC must also be decrypted
          #printf("##ciphertext: %s\n", unpack("H*", $ciphertext));
          $payload = $m->decrypt($ciphertext, $self->{aeskey}, $initVector);
        
          #printf("##plaintext   %s\n", unpack("H*", $payload));
        } else {
          $self->{errormsg} = 'Crypt::Mode::CTR is not installed, please install it (sudo cpan -i Crypt::Mode::CTR)';
          $self->{errorcode} = ERR_CIPHER_NOT_INSTALLED;
          return 0;
        }
      } else {
        $self->{errormsg} = 'encrypted message and no aeskey provided';
        $self->{errorcode} = ERR_NO_AESKEY;
        return 0;
      }
    }   
    $self->{ell}{crc} = unpack('v', $payload);
    $offset += 2;
    # PayloadCRC is  a  cyclic  redundancy  check  covering  the  remainder  of  the  frame  (excluding the CRC fields)
    # payload CRC is also encrypted
    if ($self->{ell}{crc} != $self->checkCRC(substr($payload, 2, $self->{lfield}-20))) {
      #printf("crc %x, calculated %x\n", $self->{ell}{crc}, $self->checkCRC(substr($payload, 2, $self->{lfield}-20))); 
      $self->{errormsg} = "Payload CRC check failed on ELL" . ($self->{isEncrypted} ? ", wrong AES key?" : "");
      $self->{errorcode} = ERR_CRC_FAILED;
      return 0;
    } else {
      $self->{decrypted} = 1;
    }
    $applicationlayer = $payload;
    $offset = 2; # skip PayloadCRC
  }
  
  if ($offset > 1) {
    $applicationlayer = substr($applicationlayer,$offset);
    $self->{cifield} = unpack('C', $applicationlayer);
    $offset = 1;
    if ($self->{cifield} == CI_AFL) {
      # Authentification and Fragmentation Layer
      $self->{afl}{afll} = unpack('C', substr($applicationlayer, $offset));
      #printf "AFL AFLL %02x\n", $self->{afl}{afll};
      $offset += 1;
      $self->decodeAFL(substr($applicationlayer,$offset,$self->{afl}{afll}));
      $offset += $self->{afl}{afll};
      if ($self->{afl}{fcl_mf}) {
        $self->{errormsg} = "fragmented messages are not yet supported";
        $self->{errorcode} = ERR_FRAGMENT_UNSUPPORTED;
        return 0;
      }
    }
  }
  
  if ($offset > 1) {
    $applicationlayer = substr($applicationlayer,$offset);
    $self->{cifield} = unpack('C', $applicationlayer); 
    $offset = 1;
  }

  # initialize some fields
  $self->{cw_1} = 0;
  $self->{cw_2} = 0;
  $self->{status} = 0;
  $self->{statusstring} = "";
  $self->{access_no} = 0;
  
  if ($self->{cifield} == CI_RESP_4 || $self->{cifield} == CI_RESP_SML_4) {
    # Short header
    #print "short header\n";
    ($self->{access_no}, $self->{status}, $self->{cw_1}, $self->{cw_2}) = unpack('CCCC', substr($applicationlayer,$offset));
    $offset += 4;
  } elsif ($self->{cifield} == CI_RESP_12 || $self->{cifield} == CI_RESP_SML_12) {
    # Long header
    #print "Long header\n";
    ($self->{meter_id}, $self->{meter_man}, $self->{meter_vers}, $self->{meter_dev}, $self->{access_no}, $self->{status}, $self->{cw_1}, $self->{cw_2}) 
      = unpack('VvCCCCCC', substr($applicationlayer,$offset)); 
    $self->{meter_id} = sprintf("%08d", $self->{meter_id});  
    $self->{meter_devtypestring} =  $validDeviceTypes{$self->{meter_dev}} || 'unknown'; 
    $self->{meter_manufacturer} = uc($self->manId2ascii($self->{meter_man}));
    $offset += 12;
  } elsif ($self->{cifield} == CI_RESP_0) {
    # no header
    #print "No header\n";

  } elsif ($self->{cifield} == 0x79 && $self->{manufacturer} eq 'KAM') {
    #print "Kamstrup compact frame header\n";
    $self->{format_signature} = unpack("v", substr($applicationlayer,$offset, 2));
    $offset += 2;
    $self->{full_frame_payload_crc} = unpack("v", substr($applicationlayer, $offset, 2));
    $offset += 2;
    if ($self->{format_signature} == $self->checkCRC(pack("H*", "02FF20" . "0413" . "4413"))) {
      # Info, Volume, Target Volume
      # convert into full frame
      $applicationlayer =   pack("H*", "02FF20") . substr($applicationlayer, 5, 2) # Info
                          . pack("H*", "0413") . substr($applicationlayer,7,4) # volume
                          . pack("H*", "4413") . substr($applicationlayer,11,4); # target volume 
      $offset = 0;
    } elsif ($self->{format_signature} == $self->checkCRC(pack("H*", "02FF20" . "0413" . "523B"))) {
      # Info, Volume, Max flow
      # convert into full frame
      $applicationlayer =   pack("H*", "02FF20") . substr($applicationlayer, 5, 2) # Info
                          . pack("H*", "0413") . substr($applicationlayer,7,4) # volume
                          . pack("H*", "523B") . substr($applicationlayer,11,2); # max flow 
      $offset = 0;
    } elsif ($self->{format_signature} == $self->checkCRC(pack("H*", "02FF20" . "0413" . "4413" . "615B" . "6167"))) {
      # Info, Volume, Max flow, flow temp, external temp
      # convert into full frame
      $applicationlayer =   pack("H*", "02FF20") . substr($applicationlayer, 5, 2) # Info
                          . pack("H*", "0413") . substr($applicationlayer,7,4) # volume
                          . pack("H*", "4413") . substr($applicationlayer,11,4) # target volume 
                          . pack("H*", "615B") . substr($applicationlayer,15,1) # flow temp 
                          . pack("H*", "6167") . substr($applicationlayer,16,1); # external temp
      $offset = 0;
    } else {
      $self->{errormsg} = 'Unknown Kamstrup compact frame format';
      $self->{errorcode} = ERR_UNKNOWN_COMPACT_FORMAT;
      return 0;
    }
    if ($self->{full_frame_payload_crc} != $self->checkCRC($applicationlayer)) {
      $self->{errormsg} = 'Kamstrup compact frame format payload CRC error';
      $self->{errorcode} = ERR_CRC_FAILED;
      return 0;
    }
  } else {
    # unsupported
    $self->decodeConfigword();
    $self->{errormsg} = 'Unsupported CI Field ' . sprintf("%x", $self->{cifield}) . ", remaining payload is " . unpack("H*", substr($applicationlayer,$offset));
    $self->{errorcode} = ERR_UNKNOWN_CIFIELD;
    return 0;
  }
  $self->{statusstring} = join(", ", $self->state2string($self->{status}));

  $self->decodeConfigword();
  
  $self->{encryptionMode} = $encryptionModes{$self->{cw_parts}{mode}};
  if ($self->{cw_parts}{mode} == 0) {
    # no encryption
    if (!defined $self->{isEncrypted}) {
      $self->{isEncrypted} = 0;
      $self->{decrypted} = 1;
    }
    $payload = substr($applicationlayer, $offset);
  } elsif ($self->{cw_parts}{mode} == 5) {
    # data is encrypted with AES 128, dynamic init vector
    # decrypt data before further processing
    $self->{isEncrypted} = 1;
    $self->{decrypted} = 0;

    if ($self->{aeskey}) { 
      if ($hasCBC) {
        $payload = $self->decrypt(substr($applicationlayer,$offset));
        #printf("decrypted payload %s\n", unpack("H*", $payload));
        if (unpack('n', $payload) == 0x2f2f) {
          $self->{decrypted} = 1;
        } else {
          # Decryption verification failed
          $self->{errormsg} = 'Decryption failed, wrong key?';
          $self->{errorcode} = ERR_DECRYPTION_FAILED;
          #printf("%x\n", unpack('n', $payload));
          return 0;
        }
      } else {
        $self->{errormsg} = 'Crypt::Mode::CBC is not installed, please install it (sudo cpan -i Crypt::Mode::CBC)';
        $self->{errorcode} = ERR_CIPHER_NOT_INSTALLED;
        return 0;
      }
    } else {
      $self->{errormsg} = 'encrypted message and no aeskey provided';
      $self->{errorcode} = ERR_NO_AESKEY;
      return 0;
    }

  } else {
    # error, encryption mode not implemented
    $self->{errormsg} = sprintf('Encryption mode %x not implemented', $self->{cw_parts}{mode});
    $self->{errorcode} = ERR_UNKNOWN_ENCRYPTION;
    $self->{isEncrypted} = 1;
    $self->{decrypted} = 0;
    return 0;
  }
  
  if ($self->{cifield} == CI_RESP_SML_4 || $self->{cifield} == CI_RESP_SML_12) {
    # payload is SML encoded, that's not implemented
    $self->{errormsg} = "payload is SML encoded, can't be decoded, SML payload is " . unpack("H*", substr($applicationlayer,$offset));
    $self->{errorcode} = ERR_SML_PAYLOAD;
    return 0;
  } else {
    return $self->decodePayload($payload);  
  }
  
}

sub decodeLinkLayer($$)
{
  my $self = shift;
  my $linklayer = shift;


  ($self->{lfield}, $self->{cfield}, $self->{mfield}) = unpack('CCv', $linklayer);
  $self->{afield} = substr($linklayer,4,6);
  $self->{afield_id} = sprintf("%08d", $self->decodeBCD(8,substr($linklayer,4,4)));
  ($self->{afield_ver}, $self->{afield_type}) = unpack('CC', substr($linklayer,8,2));
  
  #printf("lfield %d\n", $self->{lfield});

  if ($self->{frame_type} eq FRAME_TYPE_A) {
    if ($self->{crc_size} > 0) {
      $self->{crc0} = unpack('n', substr($linklayer,TL_BLOCK_SIZE, $self->{crc_size}));
    
      #printf("crc0 %x calc %x\n", $self->{crc0}, $self->checkCRC(substr($linklayer,0,10)));
    
      if ($self->{crc0} != $self->checkCRC(substr($linklayer,0,TL_BLOCK_SIZE))) {
        $self->{errormsg} = "CRC check failed on link layer";
        $self->{errorcode} = ERR_CRC_FAILED;
        #print "CRC check failed on link layer\n";
        return 0;
      }
    }

    # header block is 10 bytes + 2 bytes CRC, each following block is 16 bytes + 2 bytes CRC, the last block may be smaller
    $self->{datalen} = $self->{lfield} - (TL_BLOCK_SIZE - 1); # this is without CRCs and the lfield itself
    $self->{datablocks} = int($self->{datalen} / LL_BLOCK_SIZE);
    $self->{datablocks}++ if $self->{datalen} % LL_BLOCK_SIZE != 0;
    $self->{msglen} = TL_BLOCK_SIZE + $self->{crc_size} + $self->{datalen} + $self->{datablocks} * $self->{crc_size};
      
    #printf("calc len %d, actual %d\n", $self->{msglen}, length($self->{msg}));
    $self->{applicationlayer} = $self->removeCRC(substr($self->{msg},TL_BLOCK_SIZE + $self->{crc_size}));
  
  } else {
    # FRAME TYPE B
    # each block is at most 129 bytes long.
    # first contains the header (TL_BLOCK), L field and trailing crc
    # L field is included in crc calculation
    # each following block contains only data and trailing crc
    my $length = 129;
    if ($self->{lfield} < $length) {
      $length = $self->{lfield};
    }
    if ($self->{crc_size} > 0) {
      $length -= $self->{crc_size};
      $length++; # for L field
      #print "length: $length\n";
      $self->{crc0} = unpack('n', substr($self->{msg}, $length, $self->{crc_size}));
      
      #printf "crc in msg %x crc calculated %x\n", $self->{crc0}, $self->checkCRC(substr($self->{msg}, 0, $length));
      if ($self->{crc0} != $self->checkCRC(substr($self->{msg}, 0, $length))) {
        $self->{errormsg} = "CRC check failed on block 1";
        $self->{errorcode} = ERR_CRC_FAILED;
        return 0;
      }
    }
    
    $self->{datablocks} = int($self->{lfield} / 129);
    $self->{datablocks}++ if $self->{lfield} % 129 != 0;
    # header block is 10 bytes, following block 
    $self->{datalen} = $self->{lfield} - (TL_BLOCK_SIZE - 1) - ($self->{datablocks} * $self->{crc_size}) ; # this is with CRCs but without the lfield itself
    $self->{msglen} = $self->{lfield};

    if ($self->{datablocks} == 2) {
      # TODO
    } else {
      $self->{applicationlayer} = substr($self->{msg}, TL_BLOCK_SIZE, $length - TL_BLOCK_SIZE); # - $self->{crc_size});
    }
  }

  if (length($self->{msg}) > $self->{msglen}) {
    $self->{remainingData} = substr($self->{msg},$self->{msglen});
  } elsif (length($self->{msg}) < $self->{msglen}) {
    $self->{errormsg} = "message too short, expected " . $self->{msglen} . ", got " . length($self->{msg}) . " bytes";
    $self->{errorcode} = ERR_MSG_TOO_SHORT;
    return 0;
  }
  
  
  # according to the MBus spec only upper case letters are allowed.
  # some devices send lower case letters none the less
  # convert to upper case to make them spec conformant
  $self->{manufacturer} = uc($self->manId2ascii($self->{mfield}));
  $self->{typestring} =  $validDeviceTypes{$self->{afield_type}} || 'unknown';
  return 1;
}

sub setFrameType($)
{
  my $self = shift;
  $self->{frame_type} = shift;
}

sub parse($$)
{
  my $self = shift;
  $self->{msg} = shift;
  
  $self->{errormsg} = '';
  $self->{errorcode} = ERR_NO_ERROR;
  
  if (length($self->{msg}) < 12) {
    $self->{errormsg} = "Message too short";
    $self->{errorcode} = ERR_MSG_TOO_SHORT;
    return 1;
  }
  if (substr($self->{msg}, 0, 4) eq pack("H*", "543D543D")) {
    $self->setFrameType(FRAME_TYPE_B);
    $self->{msg} = substr($self->{msg},4);
  }
  if ($self->decodeLinkLayer(substr($self->{msg},0,12)) != 0)  {
    $self->{linkLayerOk} = 1;
    return $self->decodeApplicationLayer();
  }
  return 0;

}

sub parseLinkLayer($$)
{
  my $self = shift;
  $self->{msg} = shift;

  $self->{errormsg} = '';
  $self->{errorcode} = ERR_NO_ERROR;
  $self->{linkLayerOk} = $self->decodeLinkLayer(substr($self->{msg},0,12));
  return $self->{linkLayerOk};
}

sub parseApplicationLayer($)
{
  my $self = shift;

  $self->{errormsg} = '';
  $self->{errorcode} = ERR_NO_ERROR;
  return $self->decodeApplicationLayer();
}

1;

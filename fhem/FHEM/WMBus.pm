# $Id: $

package WMBus;

use strict;
use warnings;
use feature qw(say);
use Crypt::CBC;  # libcrypt-cbc-perl
use Digest::CRC; # libdigest-crc-perl

# there seems to be no debian package for Crypt::OpenSSL::AES, so use
# sudo apt-get install libssl-dev
# sudo cpan -i Crypt::OpenSSL::AES

require Exporter;
my @ISA = qw(Exporter);
my @EXPORT = qw(new parse parseLinkLayer parseApplicationLayer manId2ascii type2string);


use constant {
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
	
	# DIF types (Data Information Field), see page 32
	DIF_NONE => 0x00,
	DIF_INT8 => 0x01,
	DIF_INT16 => 0x02,
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
		return "invalid";
	} else {
		return $year . "-" . $month . "-" . $day; 
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
	my $min = ($value & 0b111111);
	my $hour = ($value & 0b11111) >> 6;
	
	return valueCalcDate($datePart, $dataBlock) . sprintf(' %02d:%02d', $hour, $min);
}

sub valueCalcHex($$) {
	my $value = shift;
	my $dataBlock = shift;

	return sprintf("%x", $value);
}

# VIF types (Value Information Field), see page 32
my %VIFInfo = (
	VIF_ELECTRIC_ENERGY  => {                     #  10(nnn-3) Wh  0.001Wh to 10000Wh
	  typeMask     => 0b01111000,
	  expMask      => 0b00000111,
	  type         => 0b00000000,
		bias         => -3,
		unit         => 'Wh',
		calcFunc     => \&valueCalcNumeric,
	},
	VIF_THERMAL_ENERGY   => {                     #  10(nnn) J     0.001kJ to 10000kJ
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
	VIF_HCA              =>  {                  # dimensionless
	  typeMask     => 0b01111111,
	  expMask      => 0b00000000,
	  type         => 0b01101110,
		bias         => 0,
		unit         => '',
		calcFunc     => \&valueCalcNumeric,
	},
);	

# Codes used with extension indicator $FD
my %VIFInfo_FD = (                              
	VIF_ACCESS_NO  => {                     #  Access number (transmission count)
	  typeMask     => 0b01111111,
	  expMask      => 0b00000000,
	  type         => 0b00001000,
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
	VIF_ERROR_FLAGS => {                  #  Error flags (binary)
	  typeMask     => 0b01111111,
	  expMask      => 0b00000000,
	  type         => 0b00010111,
		bias         => 0,
		unit         => '',
		calcFunc     => \&valueCalcHex,
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
 0x28 => 'Waste water',
 
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
	
	my $msgLen = length($msg);
	my $noOfBlocks = int($msgLen / 18);
	my $rest = $msgLen % 18;
	
	
	#print "Länge "  . $msgLen . "\n";
	
	for ($i=0; $i < $noOfBlocks; $i++) {

		$crc = unpack('n',substr($msg, 18*$i+16, 2));
		#printf("%d: CRC %x, calc %x\n", $i, $crc, $self->checkCRC(substr($msg, 18*$i, 16))); 
		if ($crc != $self->checkCRC(substr($msg, 18*$i, 16))) {
			$self->{errormsg} = "crc check failed for block $i";
			$self->{errorcode} = ERR_CRC_FAILED;
			return 0;
		}
		$res .= substr($msg, 18*$i, 16);
	}

	if ($rest != 0) {
		$res .= substr($msg, $noOfBlocks*18, $rest - 2);
		$crc = unpack('n',substr($msg, $msgLen-2, 2));
		if ($crc != $self->checkCRC(substr($msg, $noOfBlocks*18, $rest - 2))) {
			$self->{errormsg} = "crc check failed for block $i";
			$self->{errorcode} = ERR_CRC_FAILED;
		  #printf("rest %d: CRC %x, calc %x\n", $rest, $crc, $self->checkCRC(substr($msg, $noOfBlocks*18, $rest - 2))); 
			return 0;
		}
	}
	return $res;
}


sub manId2hex($$)
{
	my $self = shift;
	my $idascii = shift;
	
	return (ord(substr($idascii,1,1))-64) << 10 | (ord(substr($idascii,2,1))-64) << 5 | (ord(substr($idascii,3,1))-64);
}

sub manId2ascii($$)
{
	my $self = shift;
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
	
	#$self->{dataBlocks} = [];
}

sub decodeConfigword($) {
	my $self = shift;
	
  $self->{cw_parts}{bidirectional}    = $self->{cw} & 0b1000000000000000 >> 15;
	$self->{cw_parts}{accessability}    = $self->{cw} & 0b0100000000000000 >> 14;
	$self->{cw_parts}{synchronous}      = $self->{cw} & 0b0010000000000000 >> 13;
	$self->{cw_parts}{mode}             = $self->{cw} & 0b0000111100000000 >> 8;
	$self->{cw_parts}{encrypted_blocks} = $self->{cw} & 0b0000000011110000 >> 4;
	$self->{cw_parts}{content}          = $self->{cw} & 0b0000000000001100 >> 2;
	$self->{cw_parts}{hops}             = $self->{cw} & 0b0000000000000011;
}

sub decodeBCD($$$) {
	my $self = shift;
	my $digits = shift;
	my $bcd = shift;
	my $byte;
	my $val=0;
	my $mult=1;
	
	for (my $i = 0; $i < $digits/2; $i++) {
		$byte = unpack('C',substr($bcd, $i, 1));
		$val += ($byte & 0x0f) * $mult;
		$mult *= 10;
		$val += (($byte & 0xf0) >> 4) * $mult;
		$mult *= 10;
	}
	return $val;
}

sub decodeValueInformationBlock($$$) {
	my $self = shift;
	my $vib = shift;
	my $dataBlockRef = shift;
	
	my $offset = 0;
	my $vif;
	my $bias;
	my $exponent;
	my $vifInfoRef = \%VIFInfo;
	
	$vif = unpack('C', $vib);
	$offset = 1;
	
	my $isExtension = $vif & VIF_EXTENSION_BIT;

	if ($isExtension) {
		# switch to extension codes
		if ($vif == 0xFD) {
			$vifInfoRef = \%VIFInfo_FD;
		} elsif ($vif == 0xFB) {
			$vifInfoRef = \%VIFInfo_FB;
		} elsif ($vif == 0xFF) {
			# manufacturer specific data, can't be interpreted
			$dataBlockRef->{type} = "MANUFACTURER SPECIFIC";
			$dataBlockRef->{unit} = "";
			return $offset;
	  } else {
			$self->{errormsg} = "unknown VIFE " . sprintf("%x", $vif) . " at offset $offset-1";
			$self->{errorcode} = ERR_UNKNOWN_VIFE;		
		}
		$vif = unpack('C', substr($vib,$offset++,1));
	}

	
	$vif &= ~VIF_EXTENSION_BIT;
	
	#printf("vif: %x\n", $vif);
	$dataBlockRef->{type} = '';
	VIFID: foreach my $vifType ( keys $vifInfoRef ) { 
	
		#printf "vifType $vifType\n"; 
	
		if (($vif & $vifInfoRef->{$vifType}{typeMask}) == $vifInfoRef->{$vifType}{type}) {
			#printf "vifType $vifType matches\n"; 
			
			$bias = $vifInfoRef->{$vifType}{bias};
			$exponent = $vif & $vifInfoRef->{$vifType}{expMask};
			
			$dataBlockRef->{type} = $vifType;
			$dataBlockRef->{unit} = $vifInfoRef->{$vifType}{unit};
			$dataBlockRef->{valueFactor} = 10 ** ($exponent + $bias);
			$dataBlockRef->{calcFunc} = $vifInfoRef->{$vifType}{calcFunc};
			
			#printf("type %s bias %d exp %d valueFactor %d unit %s\n", $dataBlockRef->{type}, $bias, $exponent, $dataBlockRef->{valueFactor},$dataBlockRef->{unit});
			last VIFID;
		}
	}
	
	if ($dataBlockRef->{type} eq '') {
		$self->{errormsg} = "unknown VIF " . sprintf("%x",$vif);
		$self->{errorcode} = ERR_UNKNOWN_VIF;
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
			$self->{errormsg} = 'too many DIFE';
			$self->{errorcode} = ERR_TOO_MANY_DIFE;
			last EXTENSION;
		}
		
		$storageNo |= ($dif & 0b00001111) << ($difExtNo*4)+1;
		$tariff    |= (($dif & 0b00110000 >> 4)) << (($difExtNo-1)*2);
		$devUnit   |= (($dif & 0b01000000 >> 6)) << ($difExtNo-1);
	}
	
	$dataBlockRef->{functionField} = $functionField;
	$dataBlockRef->{dataField} = $df;
	$dataBlockRef->{storageNo} = $storageNo;
	$dataBlockRef->{tariff} = $tariff;
	$dataBlockRef->{devUnit} = $devUnit;
	
	#printf("in DIF: datafield %x\n", $dataBlockRef->{dataField});
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
		
		if ($dataBlock->{dataField} == DIF_NONE || $dataBlock->{dataField} == DIF_READOUT) {
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
		} elsif ($dataBlock->{dataField} == DIF_INT8) {
			$value = unpack('C', substr($payload, $offset, 1));
			$offset += 1;
		} elsif ($dataBlock->{dataField} == DIF_INT16) {
			$value = unpack('v', substr($payload, $offset, 2));
			$offset += 2;
		} elsif ($dataBlock->{dataField} == DIF_INT32) {
			$value = unpack('V', substr($payload, $offset, 4));
			$offset += 4;
		} elsif ($dataBlock->{dataField} == DIF_VARLEN) {
			my $lvar = unpack('C',substr($payload, $offset++, 1));
			if ($lvar <= 0xbf) {
				#  ASCII string with LVAR characters
        $value = unpack('a*',substr($payload, $offset, $lvar));
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
			last PAYLOAD;
		}	else {
			$self->{errormsg} = "in datablock $dataBlockNo: unhandled datafield " . sprintf("%x",$dataBlock->{dataField});
			$self->{errorcode} = ERR_UNKNOWN_DATAFIELD;
			return 0;
		}
		
		if (defined $dataBlock->{calcFunc}) {
			$dataBlock->{value} = $dataBlock->{calcFunc}->($value, $dataBlock); 
			#print "Value raw " . $value . " value calc " . $dataBlock->{value} ."\n";
		}
		
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
  my $cipher = Crypt::CBC->new(
                -key         => $self->{aeskey},
                -cipher      => "Crypt::OpenSSL::AES",
                -header      => "none",
                -iv          => $initVector,
                -literal_key => "true",
                -keysize     => 16,
        );             

  return $cipher->decrypt($encrypted);	
}

sub decodeApplicationLayer($) {
	my $self = shift;
	my $applicationlayer = $self->removeCRC(substr($self->{msg},12));
	
	if ($self->{errorcode} != ERR_NO_ERROR) {
		# CRC check failed
		return 0;
	}
	$self->{cifield} = unpack('C', $applicationlayer);

	my $offset = 1;

	if ($self->{cifield} == CI_RESP_4) {
		# Short header
		#print "short header\n";
		($self->{access_no}, $self->{status}, $self->{cw}) = unpack('CCn', substr($applicationlayer,$offset));
		$offset += 4;
	} elsif ($self->{cifield} == CI_RESP_12) {
		# Long header
		#print "Long header\n";
		($self->{meter_id}, $self->{meter_man}, $self->{meter_vers}, $self->{meter_dev}, $self->{access_no}, $self->{status}, $self->{cw}) 
			= unpack('VvCCCCn', substr($applicationlayer,$offset)); 
	  $self->{meter_devtypestring} =  $validDeviceTypes{$self->{meter_dev}} || 'unknown'; 
  	$self->{meter_manufacturer} = $self->manId2ascii($self->{meter_man});
		$offset += 12;
  } else {
		# unsupported
		$self->{errormsg} = 'Unsupported CI Field ' . sprintf("%x", $self->{cifield});
		$self->{errorcode} = ERR_UNKNOWN_CIFIELD;
		return 0;
	}
	$self->{statusstring} = join(", ", $self->state2string($self->{status}));
	
	$self->decodeConfigword();
	
	my $payload;
	
	$self->{encryptionMode} = $encryptionModes{$self->{cw_parts}{mode}};
	if ($self->{cw_parts}{mode} == 0) {
		# no encryption
		$self->{isEncrypted} = 0;
		$self->{decrypted} = 1;
  	$payload = substr($applicationlayer, $offset);
	} elsif ($self->{cw_parts}{mode} == 5) {
		# data is encrypted with AES 128, dynamic init vector
		# decrypt data before further processing
		$self->{isEncrypted} = 1;
		$self->{decrypted} = 0;

		if ($self->{aeskey}) { 
			$payload = $self->decrypt(substr($applicationlayer,$offset));
			if (unpack('n', $payload) == 0x2f2f) {
				$self->{decrypted} = 1;
			} else {
				# Decryption verification failed
				$self->{errormsg} = 'Decryption failed';
				$self->{errorcode} = ERR_DECRYPTION_FAILED;
				#printf("%x\n", unpack('n', $payload));
				return 0;
			}
		} else {
			$self->{errormsg} = 'encrypted message and no aeskey given';
	  	$self->{errorcode} = ERR_NO_AESKEY;
			return 0;
		}

	} else {
		# error, encryption mode not implemented
		$self->{errormsg} = 'Encryption mode not implemented';
  	$self->{errorcode} = ERR_UNKNOWN_ENCRYPTION;
		$self->{decrypted} = 0;
		return 0;
	}
		
	return $self->decodePayload($payload);	
	
}

sub decodeLinkLayer($$)
{
	my $self = shift;
	my $linklayer = shift;

	$self->{datalen} = length($self->{msg}) - 12;
	$self->{datablocks} = $self->{datalen} / 18; # header block is 12 bytes, each following block is 16 bytes + 2 bytes CRC
	$self->{datablocks}++ if $self->{datalen} % 18 != 0;

	
	($self->{lfield}, $self->{cfield}, $self->{mfield}) = unpack('CCv', $linklayer);
	$self->{afield_id} = $self->decodeBCD(8,substr($linklayer,4,4));
	($self->{afield_ver}, $self->{afield_type}, $self->{crc0}) = unpack('CCn', substr($linklayer,8,4));

	#printf("lfield %d\n", $self->{lfield});
	#printf("crc0 %x calc %x\n", $self->{crc0}, $self->checkCRC(substr($linklayer,0,10)));
	
  if ($self->{crc0} != $self->checkCRC(substr($linklayer,0,10))) {
		$self->{errormsg} = "CRC check failed on link layer";
		$self->{errorcode} = ERR_CRC_FAILED;
		#print "CRC check failed on link layer\n";
		return 0;
	}

	$self->{manufacturer} = $self->manId2ascii($self->{mfield});
	$self->{typestring} =  $validDeviceTypes{$self->{afield_type}} || 'unknown';
	return 1;
}


sub parse($$)
{
	my $self = shift;
	$self->{msg} = shift;
	
	$self->{errormsg} = '';
	$self->{errorcode} = ERR_NO_ERROR;
	if ($self->decodeLinkLayer(substr($self->{msg},0,12)) != 0)	{
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
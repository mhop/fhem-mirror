##############################################
# $Id$
# Credits:
# Texas Instruments for the Chip - Documentation at https://www.ti.com/lit/ds/sbas444d/sbas444d.pdf (ADS111x) 
#                                               and https://www.ti.com/lit/ds/sbas473e/sbas473e.pdf (ADS101x)
# Karsten Grüttner - for the initial ADS1x1x implementation
# Klaus Wittstock: for the PCF8574 module that I used as a basis for this revised ADS1x1x implementation
#
#
package main;

use strict;
use warnings;
use SetExtensions;
use Scalar::Util qw(looks_like_number);
use List::Util qw(sum);

my %I2C_ADS1x1x_Config =
(

	'State' => #	Bit [15]
		{
			'SINGLE'  => 	1 << 15,  	# Write: Begin a single conversion (when in power-down mode)
			'BUSY'    =>  	0,  		# Read: Bit = 0 Device is currently performing a conversion
			'NOT_BUSY' => 	1 << 15   	# Read: Bit = 1 Device is not currently performing a conversion	
		},		
	'Mux' =>  #	 Bits [14:12]
		{
			'COMP_0_1' => 0 , 		# AINP = AIN0 and AINN = AIN1 , default
			'COMP_0_3' => 1 << 12,	# AINP = AIN0 and AINN = AIN3
			'COMP_1_3' => 2 << 12 , # AINP = AIN1 and AINN = AIN3
			'COMP_2_3' => 3 << 12 , # AINP = AIN2 and AINN = AIN3
			'SINGLE_0' => 4 << 12 , # AINP = AIN0 and AINN = GND
			'SINGLE_1' => 5 << 12 , # AINP = AIN1 and AINN = GND
			'SINGLE_2' => 6 << 12 , # AINP = AIN2 and AINN = GND 
			'SINGLE_3' => 7 << 12 	# AINP = AIN3 and AINN = GND	
		},
	'Gain' => # Bits [11:9]
		{
		    '6V' => 	{ code => 0, 		refVoltage => 6.144 },
			'4V' => 		{ code => 1 << 9, 	refVoltage => 4.096 },   # default
			'2V' => 		{ code => 2 << 9, 	refVoltage => 2.048 },
			'1V' => 		{ code => 3 << 9, 	refVoltage => 1.024 },
			'0.5V' => 		{ code => 4 << 9, 	refVoltage => 0.512 },
			'0.25V' => 	{ code => 5 << 9,  	refVoltage => 0.256 }
			
		},
	'Data_Rate' => # Bits [7:5] "delay" refers to ADS111x only, but not used at all currently
		{
			'1/16x'   	=> { code => 0,			delay => 1.0/8   },
			'1/8x'    	=> { code => 1 << 5,	delay => 1.0/16  },
			'1/4x'    	=> { code => 2 << 5,	delay => 1.0/32  },
			'1/2x'    	=> { code => 3 << 5,	delay => 1.0/64  },
			'1x'   	=> { code => 4 << 5,	delay => 1.0/128 }, # default
			'2x'   	=> { code => 5 << 5,	delay => 1.0/250 },
			'4x'   	=> { code => 6 << 5,	delay => 1.0/475 },
			'8x'	=> { code => 7 << 5,	delay => 1.0/860 }
		},		
	'Operation_Mode' => # Bit [8]
		{
			'Continuously' 	=> 0, 		# einmalig initialisiert, kann immer gelesen werden, geeignet für Dauerüberwachung 
			'SingleShot'	=> 1 << 8 	# wacht zum einmaligen Lesen auf und legt sich wieder schlafen, geeignet für Messungen mit großen Pausen dazwischen
		},

	'Comparator_Mode' =>	# Bit [4]
		{
			'Traditional' => 	0,
			'Window' =>			1 << 4
		},
	'Comparator_Polarity' =>	# Bit [3]
		{
			'ActiveLow' => 0,  		# default
			'ActiveHigh' => 1 << 3	
			
		},
	'Latching_Comparator' =>	# Bit [2]
		{
			'off' => 	0,			, # default	
			'on' => 	1 << 2
		},
	'Comparator_Queue_Disable' => # Bits [1:0]
		{
			'AfterOneConversion' 	=> 0, 
			'AfterTwoConversions' 	=> 1, 
			'AfterFourConversions' 	=> 2,
			'disable'				=> 3 	# default	
		}
		
);

sub I2C_ADS1x1x_Initialize($) {
  my ($hash) = @_;

  $hash->{DefFn}     = 	"I2C_ADS1x1x_Define";
  $hash->{InitFn}  	 =  'I2C_ADS1x1x_Init';
  $hash->{AttrFn}    = 	"I2C_ADS1x1x_Attr";
  $hash->{SetFn}     = 	"I2C_ADS1x1x_Set";
  $hash->{StateFn}   =  "I2C_ADS1x1x_State";
  $hash->{GetFn}     = 	"I2C_ADS1x1x_Get";
  $hash->{UndefFn}   = 	"I2C_ADS1x1x_Undef";
  $hash->{I2CRecFn}  = 	"I2C_ADS1x1x_I2CRec";
  $hash->{AttrList}  = 	"IODev do_not_notify:1,0 ignore:1,0 showtime:1,0 ".
												"a0_mode:RTD,NTC,RAW,RES,off ".
												"a1_mode:RTD,NTC,RAW,RES,off ".
												"a2_mode:RTD,NTC,RAW,RES,off ".
												"a3_mode:RTD,NTC,RAW,RES,off ".
												"a0_res a1_res a2_res a3_res ".
												"a0_r0 a1_r0 a2_r0 a3_r0 ".
												"a0_avg a1_avg a2_avg a3_avg ".
												"a0_bval a1_bval a2_bval a3_bval ".												
												"a0_gain:6V,4V,2V,1V,0.5V,0.25V ".
												"a1_gain:6V,4V,2V,1V,0.5V,0.25V ".
												"a2_gain:6V,4V,2V,1V,0.5V,0.25V ".
												"a3_gain:6V,4V,2V,1V,0.5V,0.25V ".
												"decimals:0,1,2,3,4,5 ".
												"sys_voltage " .
												"data_rate:1/16x,1/8x,1/4x,1/2x,1x,2x,4x,8x ".
												"mux:SINGLE ".
												"device:ADS1013,ADS1014,ADS1015,ADS1113,ADS1114,ADS1115 ".
												#"comparator_polarity:ActiveLow,ActiveHigh ".
												#"operation_mode:SingleShot,Continuously ".  ### Does not make sense with multiple inputs
												#"comparator_mode:Traditional,Window ".
												#"latching_comparator:on,off ".
												#"comparator_queue_disable:AfterOneConversion,AfterTwoConversion,AfterFourConversion,disable ".
												"poll_interval ".
												"poll_interleave ".
												"$readingFnAttributes";
}
################################### Todo: Set or Attribute for Mode? Other sets needed?
sub I2C_ADS1x1x_Set($@) {					#
	my ($hash, @a) = @_;
	my $name =$a[0];
	my $cmd = $a[1];
	my $val = $a[2];	
 
	if ( $cmd && $cmd eq "Update") {
		#Make sure there is no reading cycle running and re-start polling (which starts with an inital read)
		RemoveInternalTimer($hash) if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ); 
		$hash->{helper}{state}=0; #Reset state machine
		InternalTimer(gettimeofday() + 1, 'I2C_ADS1x1x_Execute', $hash, 0);
		return undef;
	} else {
		my $list = "Update:noArg";
		return "Unknown argument $a[1], choose one of " . $list if defined $list;
		return "Unknown argument $a[1]";
	}
	if (!defined $hash->{IODev}) {
		readingsSingleUpdate($hash, 'state', 'No IODev defined',0);
		return "$name: no IO device defined";
	}
  	return undef;
}
################################### 
sub I2C_ADS1x1x_Get($@) {
	#Nothing to be done here, let all updates run asychroniously with timers
	return undef;
}

sub I2C_ADS1x1x_Execute($@) {
	my ($hash) = @_;
	my $state=$hash->{helper}{state};
	my $channels=$hash->{helper}{channels};
	#Default time between reading channels
	my $nexttimer=AttrVal($hash->{NAME}, 'poll_interleave', 0.008);
	my $interleave=$nexttimer;
	if (!defined($state)) {$state=0};
	if ($state%2 == 0) {$nexttimer=0.008;} #8 ms conversiontime for even numbers
	if ($state<($channels*2-1)) {
		$hash->{helper}{state}+=1;	
	} else {
		$hash->{helper}{state}=0;
		#Interleave to next complete read cycle is poll interval
		$nexttimer = AttrVal($hash->{NAME}, 'poll_interval', 5)*60 - $channels*(0.008+$interleave); #Substract channel timers to have more or less constant interval
	}
	Log3 $hash->{NAME}, 5, $hash->{NAME}." => Processing state $state timer $nexttimer channels: $channels newstate:".$hash->{helper}{state};
	if (!defined AttrVal($hash->{NAME}, "IODev", undef)) {return;}
	if ($state==0) {
		I2C_ADS1x1x_InitConfig($hash,0);
	} elsif ($state==1) {
		I2C_ADS1x1x_ReadData($hash,0);
	} elsif ($state==2) {
		I2C_ADS1x1x_InitConfig($hash,1);
	} elsif ($state==3) {
		I2C_ADS1x1x_ReadData($hash,1);
	} elsif ($state==4) {
		I2C_ADS1x1x_InitConfig($hash,2);
	} elsif ($state==5) {
		I2C_ADS1x1x_ReadData($hash,2);
	} elsif ($state==6) {
		I2C_ADS1x1x_InitConfig($hash,3);
	} elsif ($state==7) {
		I2C_ADS1x1x_ReadData($hash,3);
	}
	
	#Initalize next Timer for Reading Results in 8ms (time required for conversion to be ready)
	InternalTimer(gettimeofday()+$nexttimer, \&I2C_ADS1x1x_Execute, $hash,0) unless $nexttimer<=0;
	return undef;
}

sub I2C_ADS1x1x_InitConfig(@) {
	my ($hash, $sensor) = @_;
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	my $mux=AttrVal($hash->{NAME}, "mux", "SINGLE");
	return undef if ($mux ne "SINGLE"); #Only SINGLE mode supported

	my $mode=AttrVal($hash->{NAME}, "a".$sensor."_mode", "RAW");

	if ($mode ne "off") {
		my $sensval=$mux."_".$sensor;
		my $gain=AttrVal($hash->{NAME}, "a".$sensor."_gain", "4V"); 
		my $config = $hash->{helper}{configword}|
			$I2C_ADS1x1x_Config{'Mux'}{$sensval}|
			$I2C_ADS1x1x_Config{'Gain'}{$gain}{code};
				
		my $low_byte = $config & 0xff;
		my $high_byte = ($config & 0xff00) >> 8;	
		my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cwrite", reg=> 1, sensor=>$sensor, data => $high_byte. " " .$low_byte);
		Log3 $hash->{NAME}, 4, $hash->{NAME}." => $pname CONFIG adr:".$hash->{I2C_Address}." Sensor $sensor Byte0:$high_byte Byte1:$low_byte";
	    CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
	}
}

sub I2C_ADS1x1x_ReadData(@) {
	my ($hash, $sensor) = @_;
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	#Gain needs to be passed through for calculation
	my $gain=AttrVal($hash->{NAME}, "a".$sensor."_gain", "4V"); 
	my %sendpackage = ( i2caddress => $hash->{I2C_Address}, direction => "i2cread", reg=> 0, sensor=>$sensor, gain=>$gain, nbyte => 2);
	Log3 $hash->{NAME}, 5, $hash->{NAME}." => $pname READ adr:".$hash->{I2C_Address}." Sensor $sensor Gain $gain";
	CallFn($pname, "I2CWrtFn", $phash, \%sendpackage);
}

################################### 
sub I2C_ADS1x1x_Attr(@) {					#
 my ($command, $name, $attr, $val) = @_;
 my $hash = $defs{$name};
 my $msg = undef;
  if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_ADS1x1x_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
  if ($attr eq 'poll_interval') {
    if ( defined($val) ) {
      if ( looks_like_number($val) && $val >= 0) {
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday()+1, 'I2C_ADS1x1x_Execute', $hash, 0) if $val>0;
      } else {
        $msg = "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number >= 0";
      }    
    } else {
      RemoveInternalTimer($hash);
    }
  } elsif ($attr eq 'device') {
	my $channels=1;
	if (!defined $val or $val =~ m/^ADS1[0|1]15$/i ) {
		$channels=4;  # Only these two devices have 4 channels
	} 
	$hash->{helper}{channels}=$channels;
  }

  #check for correct values while setting so we need no error handling later
  foreach ('sys_voltage','a0_res','a1_res','a2_res','a3_res', 'a0_r0', 'a1_r0', 'a2_r0', 'a3_r0', 'a0_bval', 'a1_bval', 'a2_bval', 'a3_bval') {
	if ($attr eq $_) {
		if ( defined($val) ) {
			if ( !looks_like_number($val) || $val <= 0) {
				$msg = "$hash->{NAME}: ".$attr." must be a number > 0";
			}
		}
	}
  }
  I2C_ADS1x1x_Prepare($hash); #Update predefined variables so any attribute changes are reflected
  return $msg;	
}
################################### 
sub I2C_ADS1x1x_Define($$) {			#
 my ($hash, $def) = @_;
 my @a = split("[ \t]+", $def);
 if ($main::init_done) {
    eval { I2C_ADS1x1x_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
    return I2C_ADS1x1x_Catch($@) if $@;
  }
  return undef;
}
################################### 
sub I2C_ADS1x1x_Init($$) {				#
	my ( $hash, $args ) = @_;
	#my @a = split("[ \t]+", $args);
	my $name = $hash->{NAME};
	if (defined $args && int(@$args) != 1)	{
		return "Define: Wrong syntax. Usage:\n" .
		       "define <name> I2C_ADS1x1x <i2caddress>";
	}
	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address; 
	} else {
		readingsSingleUpdate($hash, 'state', 'Invalid I2C Adress',0);
 		return "$name I2C Address not valid";
	}
  	AssignIoPort($hash);
	readingsSingleUpdate($hash, 'state', 'Initialized',0);
	I2C_ADS1x1x_Set($hash, $name, "setfromreading");
	I2C_ADS1x1x_Prepare($hash);
	RemoveInternalTimer($hash);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 5)*60;
	InternalTimer(gettimeofday() + $pollInterval, 'I2C_ADS1x1x_Execute', $hash, 0) if ($pollInterval > 0);
	return;
}

sub I2C_ADS1x1x_Prepare($) {
	my ($hash)=@_;
	$hash->{helper}{state}=0; #initalize state machine
	$hash->{helper}{channels}=4; #for default ADS1115, will be overwritten with different ATTR setting
	my $mux=AttrVal($hash->{NAME}, "mux", "SINGLE");
	my $device=AttrVal($hash->{NAME}, "device", "ADS1115");
	my $rate=AttrVal($hash->{NAME}, "data_rate", "1x");
	my $opmode=AttrVal($hash->{NAME}, "operation_mode", "SingleShot");
	my $cmode=AttrVal($hash->{NAME}, "comparator_mode", "Traditional");
	my $lcomp=AttrVal($hash->{NAME}, "latching_comparator", "on");
	my $cqueue=AttrVal($hash->{NAME}, "comparator_queue_disable", "AfterOneConversion");
	my $cpol=AttrVal($hash->{NAME}, "comparator_polarity", "ActiveLow");
	my $config = $I2C_ADS1x1x_Config{'State'}{SINGLE}|
		$I2C_ADS1x1x_Config{'Data_Rate'}{$rate}{code}|
		$I2C_ADS1x1x_Config{'Operation_Mode'}{$opmode}|
		$I2C_ADS1x1x_Config{'Comparator_Mode'}{$cmode}|
		$I2C_ADS1x1x_Config{'Latching_Comparator'}{$lcomp}|
		$I2C_ADS1x1x_Config{'Comparator_Queue_Disable'}{$cqueue}|				
		$I2C_ADS1x1x_Config{'Comparator_Polarity'}{$cpol};
	$hash->{helper}{configword}=$config;
}

################################### 
sub I2C_ADS1x1x_Catch($) {
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}
################################### 
sub I2C_ADS1x1x_State($$$$) {			#reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	#No persistant data needed, using only attributes
	return undef;
}
################################### 
sub I2C_ADS1x1x_Undef($$) {				#
	my ($hash, $name) = @_;
	RemoveInternalTimer($hash) if ( defined (AttrVal($hash->{NAME}, "poll_interval", undef)) ); 
	return undef;
}

# Calculate temperature for PT1000/PT100 platinum temperature sensors
# ax_r0 = Resistance in Ohm at zero degrees C
sub I2C_ADS1x1x_RTD($@) {
	my ($resistance,$sensor,$r0) = @_;
    #my $aa=0.003851; #Deutscher Standard? 
    my $aa=0.0039083; #ITU-90 Standard 
    my $bb=-5.05E-08; #my own value
    #my $bb=-5.7750E-07; #ITU-90 Standard
	my $temperature=0;
	my $root = $aa*$aa*$r0*$r0-4*$bb*$r0*($r0-$resistance);
	if ($root>=0) {
		$temperature=(-$aa*$r0+sqrt($root))/(2*$bb*$r0);
	}
	return $temperature;
}

# Calculate temperature for NTC Sensors 
# ax_r0 = Resistance in Ohm at 25 degrees C (typically 50K)
# ax_b = B-Value according to datasheet (for 50K often 3950)
sub I2C_ADS1x1x_NTC($@) {
	my ($resistance,$sensor,$r0,$bval) = @_;
	if ($resistance<0) {return 0;} # Prevent issue in error case
	my $steinhart;
	$steinhart = $resistance / $r0;    # (R/Ro)
	$steinhart = log($steinhart); # ln(R/Ro)
	$steinhart = $steinhart/$bval;                 # 1/B * ln(R/Ro)
	$steinhart = $steinhart+ 1.0 / (25.0 + 273.15);  # + (1/To)
	$steinhart = 1.0 / $steinhart;       # Invert
	$steinhart = $steinhart-273.15;               # convert to C
	return $steinhart;
}

################################### 

sub I2C_ADS1x1x_I2CRec($@) {				# ueber CallFn vom physical aufgerufen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	my $clientHash = $defs{$name};
	my $msg = "";
	while ( my ( $k, $v ) = each %$clientmsg ) { 	#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
		$msg = $msg . " $k=$v";
	} 
	Log3 $hash,5 , "$name: I2C reply:$msg";
	my $sval;	
	if ($clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
		readingsBeginUpdate($hash);
		if ($clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received})) {
			my ($high,$low) = split(/ /, $clientmsg->{received});
			my $value= $high<<8|$low;
			Log3 $hash,5 , "$name:value:$value";
			my $gain=$clientmsg->{gain};
			my $refvoltage=$I2C_ADS1x1x_Config{'Gain'}{$gain}{refVoltage};

			my $device=AttrVal($hash->{NAME}, "device", "ADS1115");
			my $mask=0x7fff;
			my $bits=16;
			#No differentiation for 12bit since those devices still submit 16bits with the 4 lower bits set to zero
			my $voltage = ($value & $mask) * 						# filtere Bit 2^15 (0x8000) raus, das ist Vorzeichenmerkmal
			( $refvoltage/$mask) * 									# normiere anhand der Auflösung 2^15 im positiven Bereich
			( 1.0 - (2.0 *  (($value & ($mask+1)) >> ($bits-1)))); 		# bei gesetzten Bit 2^15 Faktor -1, ansonsten +1	($mask+1 = 0x8000/0x800)

			my $sensor= $clientmsg->{sensor};

			#Build average with floating windows to smoothe shaky sensors
			my @avg=();
			my $avgs=$hash->{helper}{"a".$sensor};
			if (defined $avgs) {
				@avg=@$avgs;
			}
			my $avgmax=AttrVal($name,"a".$sensor."_avg",1);
			push @avg,$voltage;
			while (@avg>$avgmax) { shift @avg; }
			$hash->{helper}{"a".$sensor}=[@avg];
			$voltage=sum(@avg)/@avg;
			
			#rounded voltage only for reading, continue calculation will full precision
			my $voltager = sprintf( '%.' . AttrVal($clientHash->{NAME}, 'decimals', 3) . 'f', $voltage 	); 
			Log3 $hash,5 , "$name:voltage=$voltage, ref=".$I2C_ADS1x1x_Config{'Gain'}{$gain}{refVoltage};
     		readingsBulkUpdate($hash, "a".$sensor."_voltage", $voltager) if (ReadingsVal($name,"a".$sensor."_voltage",0) != $voltager);
			my $divider=AttrVal($name,"a".$sensor."_res",1000);
			my $highvoltage=AttrVal($name,"sys_voltage",3.3);
			#Always calculate resistance but only write to reading in case of "RES" mode 
			my $resistance=$divider*$voltage/($highvoltage-$voltage);
			my $resistancer = sprintf( '%.' . AttrVal($name, 'decimals', 3) . 'f', $resistance 	);	
			my $temperature=0;
			my $mode=AttrVal($name,"a".$sensor."_mode","");
			Log3 $hash,5 , "$name:resistance=$resistance, with divider=$divider system_voltage=$highvoltage";
			if ($mode eq "RES") {
				readingsBulkUpdate($hash, "a".$sensor."_resistance", $resistancer) if (ReadingsVal($name,"a".$sensor."_resistance",0) != $resistancer);
			} elsif ($mode eq "RTD") {
				$temperature=sprintf( '%.1f', I2C_ADS1x1x_RTD($resistance,$sensor,AttrVal($name,"a".$sensor."_r0",1000.0)));
				Log3 $hash,5 , "$name:RTD Temp=$temperature °C";
				readingsBulkUpdate($hash, "a".$sensor."_temperature", $temperature) if (ReadingsVal($name,"a".$sensor."_temperature",0) != $temperature);
			} elsif ($mode eq "NTC") {
				$temperature=sprintf( '%.1f', I2C_ADS1x1x_NTC($resistance,$sensor,AttrVal($name,"a".$sensor."_res",50000.0),AttrVal($name,"a".$sensor."_b",3950.0)));
				Log3 $hash,5 , "$name:NTC Temp=$temperature °C";
				readingsBulkUpdate($hash, "a".$sensor."_temperature", $temperature) if (ReadingsVal($name,"a".$sensor."_temperature",0) != $temperature);
			}
		} elsif ($clientmsg->{direction} eq "i2cwrite" && defined($clientmsg->{data})) {
			#reply from write - ignore
		}
    	readingsEndUpdate($hash, 1);
	}
}

1;

#Todo Write update documentation

=pod
=item device
=item summary reads/converts data from an via I2C connected ADS1x1x A/D converter
=item summary_DE liest/konvertiert Daten eines via angeschlossenen ADS1x1x A/D Wandlers
=begin html

<h3>I2C_ADS1x1x</h3>
(en | <a href="commandref_DE.html#I2C_ADS1x1x">de</a>)
<ul>
<a id="I2C_ADS1x1x"></a>
		Provides an interface to an ADS1x1x A/D converter via I2C.<br>
		The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
		or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br><br>
		<b>Limitations:</b><br>
		For simplification most settings can only be set for all 4 channels globally.<br>
		Comparator Mode (delta between two channels) is not supported.<br>
		Temperatures are in centigrade only<br><br>
		<br><b>Special features:</b><br>
		Device supports reading voltages (RAW), resistance (RES) with divider resistor and temperature measurements of RTD (Platin Resistors like PT1000 or PT100) and NTC.
		<br>
		<br><b>Circuit:</b><br>
		To measure resistance and temperature (thermistors) your circuit should look like this:
		<br>
		<code>
		(T)----GND<br>
		  |<br>
		  |-----(A0)-----(R0)-----VCC<br>
		 <br>
		 T= Temperature Sensor or Resistor<br>
		 R0= Pull-up Resistor (typically in the same range as the resistance you measure (e.g 1KOhm for PT1000)<br>
		 A0= Connected to A0 Port of ADS1x1x (same for A1,A2,A3)<br>
		</code>
		<br>
		<br><b>Attribute <a href="#IODev">IODev</a> must be set. This is typically the name of a defined <a href="#RPII2C">RPII2C</a> device </b><br>         
	<a id="I2C_ADS1x1x-define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_ADS1x1x &lt;I2C Address&gt;</code><br>
		where <code>&lt;I2C Address&gt;</code> is without direction bit<br>
		<br>
	</ul>

	<a id="I2C_ADS1x1x-set"></a>
	<b>Set</b>
	<ul>
		<li><b>update</b><br>
		<a id="I2C_ADS1x1x-set-update"></a>
		<code>set &lt;name&gt; update</code><br>
		Trigger a reading. Resets the timers so the first reading will start within 1s - 
		continuing with the other channels based on the polling_interleave attribute.<br>
		<br>
		</li>
	</ul>

	<a id="I2C_ADS1x1x-attr"></a>
	<b>Attributes</b>
	<ul>
	    
		<li><b>device</b><br>
			<a id="I2C_ADS1x1x-attr-device"></a>
			Defines the Texas Instruments ADS1x1x device that is actually being used.
			<ul>
				<li>ADS1013 - 12Bit, 1 channel</li>
				<li>ADS1014 - 12Bit, 1 channel with Comparator</li>
				<li>ADS1015 - 12Bit, 4 channels with Comparator</li>
				<li>ADS1113 - 16Bit, 1 channel</li>
				<li>ADS1114 - 16Bit, 1 channel with Comparator</li>
				<li>ADS1115 - 16Bit, 4 channels with Comparator</li>
			</ul>
			<br>
			Note that the comparator feature is not supported by this module 
			(so no difference between ADSxx13 and ADSxx14 is made).<br>
			<b>Default:</b> ADS1115<br>
		</li>
		<br>
		<li><b>poll_interval</b><br>
			<a id="I2C_ADS1x1x-attr-poll_interval"></a>
			Set the polling interval in minutes to query a new reading from enabled channels<br>
			By setting this number to 0, the device can be set to manual mode (new readings only by "set update").<br>
			<b>Default:</b> 5, valid values: decimal number<br>
		</li>
		<br>
		<li><b>poll_interleave</b><br>
			<a id="I2C_ADS1x1x-attr-poll_interleave"></a>
			Interleave between reading 2 channels in seconds (only valid for multi channel devices). 
			Can be used to distribute the load more evenly.<br>
			<b>Default</b>: 0.008, valid values: decimal number<br>
		</li>	
		<br>
		<li><b>sys_voltage</b><br>
			<a id="I2C_ADS1x1x-attr-sys_voltage"></a>
			System voltage running the chip and typically connected to the pull-up resistor (e.g. 3.3V with a Raspberry Pi)<br>
			<b>Default:</b> 3.3, valid values: float number<br>
		</li>
		<br>
		<li><b>decimals</b><br>
			<a id="I2C_ADS1x1x-attr-decimals"></a>
			Number of decimals (after the decimal point) for voltage and resistance to make results more readable. 
			Calculations are still based on full precision. Temperatures are fixed to one decimal.<br>
			<b>Default:</b> 3, valid values: 0,1,2,3,4,5<br>
		</li>
		<br>
		<li><b>a[0-3]_gain</b><br>
			<a id="I2C_ADS1x1x-attr-a0_gain"></a>
			<a id="I2C_ADS1x1x-attr-a1_gain"></a>
			<a id="I2C_ADS1x1x-attr-a2_gain"></a>
			<a id="I2C_ADS1x1x-attr-a3_gain"></a>
			Gain amplifier value (sensibility and range of measurement) used per channel a0-a3. 
			Standard is 4V which can measure a range between 0 and 4 Volts. 
			If measuring smaller voltage, the amplification can be increased to get more accurate readings. 
			The module will automatically calculate the value back to the correct voltage output.<br>
			<b>Default:</b> 4V, valid values: 6V,4V,2V,1V,0.5V,0.25V<br>
		</li>
		<br>
		<li><b>a[0-3]_mode</b><br>
			<a id="I2C_ADS1x1x-attr-a0_mode"></a>
			<a id="I2C_ADS1x1x-attr-a1_mode"></a>
			<a id="I2C_ADS1x1x-attr-a2_mode"></a>
			<a id="I2C_ADS1x1x-attr-a3_mode"></a>
			Determines how the results are interpreted.
			<ul>
			<li>off: The channel is not measured</li>
			<li>RAW: Only voltage is measured and placed in reading a[0-3]_voltage</li>
			<li>RES: Plain resistor measurement, typically needs a pull-up resistor defined by a[0-3]_res. 
					 Reading in a[0-3]_resistance</li>
			<li>RTD: For Platin temperature resistors (PT1000,PT100), like RES needs a pull-up and also reference resistance at 0°C in a[0-3]_r0. 
			         Reading in a[0-3]_temperature</li>
			<li>NTC: For NTC Thermistors, like RES needs a pull-up, reference resistance at 25°C in a[0-3]_r0 and B-value in a[0-3]_b. 
			         Reading in a[0-3]_temperature</li>
			</ul>
		</li>
		<br>		
		<li><b>a[0-3]_res</b><br>
			<a id="I2C_ADS1x1x-attr-a0_res"></a>
			<a id="I2C_ADS1x1x-attr-a1_res"></a>
			<a id="I2C_ADS1x1x-attr-a2_res"></a>
			<a id="I2C_ADS1x1x-attr-a3_res"></a>
			Value of pull-up resistor for resistance and temperature measurement. Connected between A0 and VCC (defined in "sys_voltage")<br>
			<b>Default:</b> 1000, valid values: float numbers<br>
		</li>
		<br>		
		<li><b>a[0-3]_r0</b><br>
			<a id="I2C_ADS1x1x-attr-a0_r0"></a>
			<a id="I2C_ADS1x1x-attr-a1_r0"></a>
			<a id="I2C_ADS1x1x-attr-a2_r0"></a>
			<a id="I2C_ADS1x1x-attr-a3_r0"></a>
			Reference resistance for temperature measurements at 0°C (for RTD) and 25°C (for NTC) in Ohm.<br>
			<b>Default:</b> 1000.0 in RTD and 50000.0 in NTC mode, valid values: float numbers<br>
		</li>
		<br>		
		<li><b>a[0-3]_bval</b><br>
			<a id="I2C_ADS1x1x-attr-a0_bval"></a>
			<a id="I2C_ADS1x1x-attr-a1_bval"></a>
			<a id="I2C_ADS1x1x-attr-a2_bval"></a>
			<a id="I2C_ADS1x1x-attr-a3_bval"></a>
			B-Value for NTC Thermistors (define the increase from the base value).<br>
			<b>Default</b>: 3950.0, valid values: float numbers<br>
		</li>
		<br>		
		<li><b>a[0-3]_avg</b><br>
			<a id="I2C_ADS1x1x-attr-a0_avg"></a>
			<a id="I2C_ADS1x1x-attr-a1_avg"></a>
			<a id="I2C_ADS1x1x-attr-a2_avg"></a>
			<a id="I2C_ADS1x1x-attr-a3_avg"></a>
			Sometimes measurements can fluctuate. To get smoother values, this attribute will enable creating an average of n numbers, which should result in more stable results.<br>
			<b>Default</b>: 1, valid values: integers<br>
		</li>
		<br>		
		<li><b>data_rate (1/16x,1/8x,1/4x,1/2x,1x,2x,4x,8x )</b><br>
			<a id="I2C_ADS1x1x-attr-data_rate"></a>
			<ul>
			Conversion speed - default is 1x. The 12-bit chips use 1600 SPS as default rate, while the 16-bit chips are slower with 128 SPS. 
			Below table translates the settings based on the actual device used.<br><br>
			<table>
			<tr>
				<td>Data Rate</td>
				<td>ADS101x Setting</td>
				<td>ADS111x Settings</td>
			</tr>
            <tr>
				<td>1/16x</td>
				<td>128_SPS</td>
				<td>8_SPS</td>
			</tr>
            <tr>
				<td>1/8x</td>
				<td>250_SPS</td>
				<td>16_SPS</td>
			</tr>
            <tr>
				<td>1/4x</td>
				<td>490_SPS</td>
				<td>32_SPS</td>
			</tr>
            <tr>
				<td>1/2x</td>
				<td>920_SPS</td>
				<td>64_SPS</td>
			</tr>
            <tr>
				<td>1x (default)</td>
				<td>1600_SPS</td>
				<td>128_SPS</td>
			</tr>
            <tr>
				<td>2x</td>
				<td>2400_SPS</td>
				<td>250_SPS</td>
			</tr>
            <tr>
				<td>4x</td>
				<td>3300_SPS</td>
				<td>475_SPS</td>
			</tr>
            <tr>
				<td>8x</td>
				<td>3300_SPS</td>
				<td>860_SPS</td>
			</tr>
			</table>
			</ul>
		</li>

		<br><br>
	</ul>	
	The following entries are only valid in comparator mode and with thresholds which are currently disabled or not implemented, 
	since my use case is a plain 4-channel A/D conversion.<br>
	Please refer to ADS1x1x chip documentation for more details on the effect of these settings.<br>
	If you have a valid use case, please contact me in the FHEM forum to discuss a potential implementation.<br>
	<br>
	<ul>
		<li><b>operation_mode</b><br>
			<ul>
			Not implemented, since Continuous Mode make no sense when using multiple input registers and is meant to read values in very high speed (e.g. one value every 8 ms) which IMHO makes no sense with FHEM.<br> 
			<li>SingleShot: Do one reading and then power down</li>
			<li>Continuously: Keep powered on and continiously read data</li>
			</ul>
		</li>
		<li><b>comparator_mode</b> (Traditional|Window)<br>
			<ul>
			Not implemented.
			</ul>
		</li>
		<br>
		<li><b>comparator_polarity</b> (ActiveHigh|ActiveLow)<br>
			<ul>
			Not implemented.
			</ul>
		</li>
		<br>
		<li><b>comparator_queue_disable</b> (AfterOneConversion|AfterTwoConversions|AfterFourConversions|disable)<br>
			<ul>
			Define for how many conversions the chip remains active (powered on)<br>
			</ul>
		</li>
		<br>		
		<li><b>latching_comparator (on|off)</b><br>
			<ul>
			Not implemented.
			</ul>
		</li>
		<br>			
		<br>			
	</ul>	
	<br>
	<br>
</ul>

=end html

=begin html_DE

<h3>I2C_ADS1x1x</h3>
(<a href="commandref.html#I2C_ADS1x1x">en</a> | de)
<ul>
	<a id="I2C_ADS1x1x"></a>
		Bitte englische Dokumentation verwenden.<br>
	<a id="I2C_ADS1x1x-define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; I2C_ADS1x1x &lt;I2C Address&gt;</code><br>
		Der Wert <code>&lt;I2C Address&gt;</code> ist ohne das Richtungsbit<br>
	</ul>

	<a id="I2C_ADS1x1x-attr-set"></a>
	<b>Set</b>
	<ul>
	</ul>

	<a id="I2C_ADS1x1x-attr"></a>
	<b>Attribute</b>
	<ul>
		<li>poll_interval<br>
			Aktualisierungsintervall aller Werte in Minuten.<br>
			Standard: 5, g&uuml;ltige Werte: Dezimalzahl<br><br>
		</li>
	</ul>
	<br>
</ul>

=end html_DE

=cut

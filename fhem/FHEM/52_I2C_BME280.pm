# $Id$
=head1
	52_I2C_BME280.pm

=head1 SYNOPSIS
	Modul for FHEM for reading a BME280 digital pressure/humidity sensor via I2C
=cut

package main;

use strict;
use warnings;

use constant {
	BME280_I2C_ADDRESS => 0x76,
};

##################################################
# Forward declarations
#
sub I2C_BME280_I2CRec ($$);
sub I2C_BME280_GetReadings ($$);
sub I2C_BME280_GetTemp ($@);
sub I2C_BME280_GetPress ($@);
sub I2C_BME280_GetHum ($@);
sub I2C_BME280_calcTrueTemperature($$);
sub I2C_BME280_calcTrueHumidity($$);
sub I2C_BME280_calcTruePressure($$);

my %sets = (
	'readValues' => 1,
);

sub I2C_BME280_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_BME280_Define';
	$hash->{InitFn}   = 'I2C_BME280_Init';
	$hash->{AttrFn}   = 'I2C_BME280_Attr';
	$hash->{SetFn}    = 'I2C_BME280_Set';
	#$hash->{GetFn}    = 'I2C_BME280_Get';
	$hash->{UndefFn}  = 'I2C_BME280_Undef';
	$hash->{I2CRecFn} = 'I2C_BME280_I2CRec';
	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
						'oversampling_t:0,1,2,3,4,5 oversampling_p:0,1,2,3,4,5 oversampling_h:0,1,2,3,4,5 ' .
						'roundPressureDecimal:0,1,2 roundTemperatureDecimal:0,1,2 roundHumidityDecimal:0,1,2 ' .
						$readingFnAttributes;
    $hash->{DbLog_splitFn} = "I2C_BME280_DbLog_splitFn";
}

sub I2C_BME280_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	$hash->{STATE} = 'defined';
	
	my $name = $a[0];

	my $msg = '';
	if((@a < 2)) {
		$msg = 'wrong syntax: define <name> I2C_BME280 [I2C-Address]';
	}
	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
	}
	if ($main::init_done) {
		eval { I2C_BME280_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_BME280_Catch($@) if $@;
	}
}

sub I2C_BME280_Init($$) {					# wird bei FHEM start Define oder wieder
	my ( $hash, $args ) = @_;
	my $name = $hash->{NAME};
	
	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0x.*$/ ? oct($address) : $address; 
		return "$name: I2C Address not valid" unless ($hash->{I2C_Address} < 128 && $hash->{I2C_Address} > 3);
	} else {
		$hash->{I2C_Address} = BME280_I2C_ADDRESS;
	}
	my $msg = '';
	# create default attributes
	#if (AttrVal($name, 'poll_interval', '?') eq '?') {  
    #	$msg = CommandAttr(undef, $name . ' poll_interval 5');
    #	if ($msg) {
    #  		Log3 ($hash, 1, $msg);
    #  		return $msg;
    #	}
	#}
	eval {
		AssignIoPort($hash, AttrVal($hash->{NAME},"IODev",undef));	
		I2C_BME280_i2cread($hash, 0xD0, 1);		#get Id
		$hash->{STATE} = 'getCalData';
		I2C_BME280_i2cread($hash, 0x88, 26);
		I2C_BME280_i2cread($hash, 0xE1, 8);
	    };
    return I2C_BME280_Catch($@) if $@;
}

sub I2C_BME280_Catch($) {					# Fehlermeldungen formattieren
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}

sub I2C_BME280_Attr (@) {					# Wird beim Attribut anlegen/aendern aufgerufen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	if (defined $command && $command eq "set" && $attr eq "IODev") {
		eval {
			if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
				main::AssignIoPort($hash,$val);
				my @def = split (' ',$hash->{DEF});
				I2C_BME280_Init($hash,\@def) if (defined ($hash->{IODev}));
			}
        };
		$msg = I2C_BME280_Catch($@) if $@;
	} elsif ($attr eq 'poll_interval') {
		if (defined($val)) {
			if ($val =~ m/^(0*[1-9][0-9]*)$/) {
				RemoveInternalTimer($hash);
				I2C_BME280_Poll($hash) if ($main::init_done);
				#InternalTimer(gettimeofday() + 5, 'I2C_BME280_Poll', $hash, 0) if ($main::init_done);
			} else {
				$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
			}
		} else {
			RemoveInternalTimer($hash);
		}
	} elsif ($attr =~ m/^oversampling_.$/ && defined($val)) {
		$msg = 'Wrong value: $val for $attr defined. value must be a one of 0,1,2,3,4,5' unless ($val =~ m/^(0*[0-5])$/);
	} elsif ($attr =~ m/^round(Pressure|Temperature|Humidity)Decimal$/ && defined($val)) {
		$msg = 'Wrong value: $val for $attr defined. value must be a one of 0,1,2' unless ($val =~ m/^(0*[0-2])$/);
	}
	return ($msg) ? $msg : undef;
}

sub I2C_BME280_Poll($) {					# Messwerte regelmaessig anfordern 
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	
	I2C_BME280_Set($hash, ($name, 'readValues'));						# Read values
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_BME280_Poll', $hash, 0);
	}
}

sub I2C_BME280_Set($@) {					# Messwerte manuell anfordern
	my ($hash, @a) = @_;

	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)  . ":noArg"
	}
	
	if ($cmd eq 'readValues') {
		if (defined($hash->{calibrationData}{dig_H6})) {	# query sensor
			I2C_BME280_i2cwrite($hash, 0xF2, AttrVal($name, 'oversampling_h', 1) & 7);
			my $data =  ( AttrVal($name, 'oversampling_t', 1) & 7 ) << 5 | ( AttrVal($name, 'oversampling_p', 1) & 7 ) << 2 | 1; #Register 0xF4 “ctrl_meas” zusammenbasteln
			I2C_BME280_i2cwrite($hash, 0xF4, $data);		
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 1, 'I2C_BME280_UpdateReadings', $hash, 0); 											#nach 1s Werte auslesen
		} else {											#..but get calibration variables first
			Log3 $hash, 5, "$name: in set but no calibrationData, requesting again"; 
			I2C_BME280_i2cread($hash, 0x88, 26);
			I2C_BME280_i2cread($hash, 0xE1, 8);
		}
	}
	return undef
}


sub I2C_BME280_Get($@) {					# Messwerte manuell anfordern
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];

	if (defined($cmd) && $cmd eq 'readValues') {
		if (defined($hash->{calibrationData}{dig_H6})) {	# query sensor
			I2C_BME280_i2cwrite($hash, 0xF2, AttrVal($name, 'oversampling_h', 1) & 7);
			my $data =  ( AttrVal($name, 'oversampling_t', 1) & 7 ) << 5 | ( AttrVal($name, 'oversampling_p', 1) & 7 ) << 2 | 1; #Register 0xF4 “ctrl_meas” zusammenbasteln
			I2C_BME280_i2cwrite($hash, 0xF4, $data);		
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 1, 'I2C_BME280_UpdateReadings', $hash, 0); 											#nach 1s Werte auslesen
		} else {											#..but get calibration variables first
			Log3 $hash, 5, "$name: in set but no calibrationData, requesting again"; 
			I2C_BME280_i2cread($hash, 0x88, 26);
			I2C_BME280_i2cread($hash, 0xE1, 8);
		}
	} else {
		return 'Unknown argument ' . $cmd . ', choose one of readValues:noArg';
	}
	return undef
}


sub I2C_BME280_UpdateReadings($) {			# Messwerte auslesen
	my ($hash) = @_;
	I2C_BME280_i2cread($hash, 0xF7, 8);	# alle Werte auslesen
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);	#poll_interval Timer wiederherstellen
	InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_BME280_Poll', $hash, 0) if ($pollInterval > 0);
}

sub I2C_BME280_Undef($$) {					# Device loeschen
	my ($hash, $arg) = @_;
	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_BME280_I2CRec ($$) {				# wird vom IODev aus aufgerufen wenn I2C Daten vorliegen		
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};  
	my $pname = undef;
	my $phash = $hash->{IODev};
	$pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	}

	if ( $clientmsg->{direction} && $clientmsg->{reg} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
			Log3 $hash, 5, "$name Rx, Reg: $clientmsg->{reg}, Data: $clientmsg->{received}";
			I2C_BME280_GetCal1  	($hash, $clientmsg->{received}) if $clientmsg->{reg} == 0x88 && $clientmsg->{nbyte} == 26;
			I2C_BME280_GetCal2  	($hash, $clientmsg->{received}) if $clientmsg->{reg} == 0xE1 && $clientmsg->{nbyte} >= 8;
			I2C_BME280_GetId   		($hash, $clientmsg->{received}) if $clientmsg->{reg} == 0xD0;
			I2C_BME280_GetReadings  ($hash, $clientmsg->{received}) if $clientmsg->{reg} == 0xF7 && $clientmsg->{nbyte} == 8;
		}
	}
	
	return undef
}

sub I2C_BME280_GetId ($$) {					# empfangenes Id Byte auswerten
	my ($hash, $rawdata) = @_;
	if ($rawdata == hex("60")) {
		$hash->{DeviceType} = "BME280";
	} elsif ($rawdata == hex("58")) {
		$hash->{DeviceType} = "BMP280";
	} if ($rawdata == hex("56") || $rawdata == hex("57")) {
		$hash->{DeviceType} = "BMP280s";
	}
}

sub I2C_BME280_GetCal1 ($$) {				# empfangene Cal Daten in Internals Speichern 
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);
	my $n = 0;
	$hash->{calibrationData}{dig_T1} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++], 0); # unsigned
	$hash->{calibrationData}{dig_T2} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_T3} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P1} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++], 0); # unsigned
	$hash->{calibrationData}{dig_P2} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P3} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P4} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P5} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P6} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P7} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P8} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_P9} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$n++;
	$hash->{calibrationData}{dig_H1} = $raw[$n++]; # unsigned
	$hash->{STATE} = 'First calibration block received';
	return
}

sub I2C_BME280_GetCal2 ($$) {				# empfangene Cal Daten in Internals Speichern Teil 2
	my ($hash, $rawdata) = @_;
	my @raw = split(" ",$rawdata);
	my $n = 0;
	$hash->{calibrationData}{dig_H2} = I2C_BME280_GetCalVar($raw[$n++], $raw[$n++]);
	$hash->{calibrationData}{dig_H3} = $raw[$n++]; # unsigned
	$hash->{calibrationData}{dig_H4} =  ($raw[$n++] << 4) | $raw[$n] & 0xF;				# signed word, kann aber nur positiv sein, da nur 12 bit
	$hash->{calibrationData}{dig_H5} = (($raw[$n++] >> 4) & 0x0F) | ($raw[$n++] << 4);	# signed word, kann aber nur positiv sein, da nur 12 bit
	$hash->{calibrationData}{dig_H6} = I2C_BME280_GetCalVar($raw[$n++], undef);			# signed 8bit #geht das? oder muss I2C_BME280_GetCalVar ($;$$) angepasst werden
	$hash->{STATE} = 'Initialized';
	I2C_BME280_Poll($hash) if defined(AttrVal($hash->{NAME}, 'poll_interval', undef));			# wenn poll_interval definiert -> timer starten 
	return
}

sub I2C_BME280_GetCalVar ($$;$) {			# Variablen aus Bytes zusammenbauen (signed und unsigned)
	my ($lsb, $msb, $returnSigned) = @_;

	$returnSigned = (!defined($returnSigned) || $returnSigned == 1) ? 1 : 0; 
	my $retVal = undef;
	if (defined $msb) {		# 16 bit Variable
		$retVal = $msb << 8 | $lsb;
		# check if we need return signed or unsigned int
		if ($returnSigned == 1) {
			$retVal = $retVal >> 15 ? $retVal - 2**16 : $retVal;
		}
	} else {				# 8 bit Variable
		$retVal = $lsb >> 7 ? $lsb - 2 ** 8 : $lsb;
	}
	return $retVal;	
}

sub I2C_BME280_GetReadings ($$) {			# Empfangene Messwerte verarbeiten
		my ($hash, $rawdata) = @_;
		my @raw = split(" ",$rawdata);
		my @pres = splice(@raw,0,3);
		my @temp = splice(@raw,0,3);
		I2C_BME280_GetTemp  ($hash, @temp );
		I2C_BME280_GetPress ($hash, @pres);
		I2C_BME280_GetHum	($hash, @raw );
		
		my $tem = ReadingsVal($hash->{NAME},"temperature", undef);
		my $hum = ReadingsVal($hash->{NAME},"humidity", undef);
		my $prs = ReadingsVal($hash->{NAME},"pressure", undef);
		readingsSingleUpdate(
			$hash,
			'state',
			((defined $tem ? "T: $tem " : "") . (defined $hum ? "H: $hum " : "") . (defined $prs ? ("P: $prs P-NN: " . ReadingsVal($hash->{NAME},"pressure-nn", 0)) : "")),
			1
		);
}

sub I2C_BME280_GetTemp ($@) {				# Temperatur Messwerte verarbeiten
	my ($hash, @raw) = @_;
	if ( $raw[0] == 0x80 && $raw[1] == 0 && $raw[2] == 0 ) {			# 0x80000 (MSB = 0x80) wird ausgegeben, wenn Temperaturmessung deaktiviert (oversampling_t = 0)
		Log3 $hash, 4, "temperature reading deleted due to oversampling_t = 0";  
		delete ($hash->{READINGS}{temperature});
	} else {
		my $ut = $raw[0] << 12 | $raw[1] << 4 | $raw[2] >> 4 ;
		my $temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			I2C_BME280_calcTrueTemperature($hash, $ut)
		);
		readingsSingleUpdate($hash, 'temperature', $temperature, 1);
	}
}

sub I2C_BME280_GetPress ($@) {				# Luftdruck Messwerte verarbeiten
	my ($hash, @raw) = @_;
	if ( $raw[0] == 0x80 && $raw[1] == 0 && $raw[2] == 0 ) {			# 0x80000 (MSB = 0x80) wird ausgegeben, wenn Luftdruckmessung deaktiviert (oversampling_p = 0)
		Log3 $hash, 4, "pressure readings seleted due to oversampling_p = 0";  
		delete ($hash->{READINGS}{'pressure'});
		delete ($hash->{READINGS}{'pressure-nn'});		
	} else {
		my $up = $raw[0] << 12 | $raw[1] << 4 | $raw[2] >> 4 ;
		my $pressure = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundPressureDecimal', 1) . 'f',
			I2C_BME280_calcTruePressure($hash, $up) / 100
		);
		my $altitude = AttrVal('global', 'altitude', 0);
		# simple barometric height formula
		my $pressureNN = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundPressureDecimal', 1) . 'f',
			$pressure + ($altitude / 8.5)
		);
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash, 'pressure', $pressure);
		readingsBulkUpdate($hash, 'pressure-nn', $pressureNN);
		readingsEndUpdate($hash, 1);
	}
}

sub I2C_BME280_GetHum ($@) {				# Luftfeuchte Messwerte verarbeiten
	my ($hash, @raw) = @_;
	if ( $raw[0] == 0x80 && $raw[1] == 0 ) {			# 0x8000 (MSB = 0x80) wird ausgegeben, wenn Feuchtemessung deaktiviert (oversampling_h = 0)
		Log3 $hash, 4, "humidity readings seleted due to oversampling_h = 0";  
		delete ($hash->{READINGS}{humidity})
	} else {
		my $uh  = $raw[0] << 8 | $raw[1];
		my $humidity = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundHumidityDecimal', 1) . 'f',
			I2C_BME280_calcTrueHumidity($hash, $uh)
		);
		readingsSingleUpdate($hash, 'humidity', $humidity, 1);
	}
}

sub I2C_BME280_i2cread($$$) {				# Lesebefehl an Hardware absetzen (antwort kommt in I2C_*****_I2CRec an)
	my ($hash, $reg, $nbyte) = @_;
	if (defined (my $iodev = $hash->{IODev})) {
		Log3 $hash, 5, "$hash->{NAME}: $hash->{I2C_Address} read $nbyte Byte from Register $reg";
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

sub I2C_BME280_i2cwrite($$$) {				# Schreibbefehl an Hardware absetzen
	my ($hash, $reg, @data) = @_;
	if (defined (my $iodev = $hash->{IODev})) {
		Log3 $hash, 5, "$hash->{NAME}: $hash->{I2C_Address} write " . join (' ',@data) . " to Register $reg";
		CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
		direction  => "i2cwrite",
		i2caddress => $hash->{I2C_Address},
		reg => $reg,
		data => join (' ',@data),
		});
	} else {
		return "no IODev assigned to '$hash->{NAME}'";
	}
}

sub I2C_BME280_calcTrueTemperature($$) {	# Temperatur aus Rohwerten berechnen
	my ($hash, $ut) = @_;
	my $dig_T1 = $hash->{calibrationData}{dig_T1};
	my $dig_T2 = $hash->{calibrationData}{dig_T2};
	my $dig_T3 = $hash->{calibrationData}{dig_T3};
	
	my $h1 = ( $ut / 16384.0 - $dig_T1 / 1024.0 ) * $dig_T2;
	my $h2 = ( ( $ut / 131072.0 - $dig_T1 / 8192.0 ) * ( $ut / 131072.0 - $dig_T1 / 8192.0 ) ) * $dig_T3;
	$hash->{calibrationData}{t_fine} = $h1 + $h2;
	my $ct = $hash->{calibrationData}{t_fine} / 5120.0;
	
	return $ct;
}

sub I2C_BME280_calcTruePressure($$) {		# Luftdruck aus Rohwerten berechnen
	my ($hash, $up) = @_;

	my $t_fine = $hash->{calibrationData}{t_fine};
	my $dig_P1 = $hash->{calibrationData}{dig_P1};
	my $dig_P2 = $hash->{calibrationData}{dig_P2};
	my $dig_P3 = $hash->{calibrationData}{dig_P3};
	my $dig_P4 = $hash->{calibrationData}{dig_P4};
	my $dig_P5 = $hash->{calibrationData}{dig_P5};
	my $dig_P6 = $hash->{calibrationData}{dig_P6};
	my $dig_P7 = $hash->{calibrationData}{dig_P7};
	my $dig_P8 = $hash->{calibrationData}{dig_P8};
	my $dig_P9 = $hash->{calibrationData}{dig_P9};
	
	my $h1 = ($t_fine / 2) - 64000.0;
	my $h2 = $h1 * $h1 * $dig_P6 / 32768;
	$h2 = $h2 + $h1 * $dig_P5 * 2;
	$h2 = $h2 / 4 + $dig_P4 * 65536;	
	#$h1 = $dig_P3 * $h1 * $h1 / 524288 + $dig_P2 * $h1 / 524288;
	$h1 = ((($dig_P3 * ((($h1/4.0) * ($h1/4.0)) / 8192)) / 8) + (($dig_P2 * $h1) / 2.0)) / 262144;
	#$h1 = ( 1 + $h1 / 32768) * $dig_P1;
	$h1 = ((32768 + $h1) * $dig_P1) / 32768;
	return 0 if ($h1 == 0);
	my $p = ((1048576 - $up) - ($h2 / 4096)) * 3125;
	if ($p < 0x80000000) {
		$p = ($p * 2) / $h1;
	} else {
		$p = ($p / $h1) * 2 ;
	}
	#$p = ( $p - $h2 / 4096 ) * 6250 / $h1;
	$h1 = ($dig_P9 * ((($p/8.0) * ($p/8.0)) / 8192.0)) / 4096;
	$h2 = (($p/4.0) * $dig_P8) / 8192.0;
	$p = $p + (($h1 + $h2 + $dig_P7) / 16);
	return $p;
}

sub I2C_BME280_calcTrueHumidity($$) {		# Luftfeuchte aus Rohwerten berechnen
	my ($hash, $uh) = @_;
	
	my $t_fine = $hash->{calibrationData}{t_fine};
	my $dig_H1 = $hash->{calibrationData}{dig_H1};
	my $dig_H2 = $hash->{calibrationData}{dig_H2};
	my $dig_H3 = $hash->{calibrationData}{dig_H3};
	my $dig_H4 = $hash->{calibrationData}{dig_H4};
	my $dig_H5 = $hash->{calibrationData}{dig_H5};
	my $dig_H6 = $hash->{calibrationData}{dig_H6};
	
	my $t1 = $t_fine - 76800;
	$t1 = ( $uh - ( $dig_H4 * 64 + $dig_H5 / 16384 * $t1 ) ) * ( $dig_H2 / 65536 * ( 1 + $dig_H6 / 67108864 * $t1 * ( 1 + $dig_H3 / 67108864 * $t1 ) ) );
	$t1 = $t1 * ( 1 - $dig_H1 * $t1 / 524288);
	if ($t1 > 100) {
		$t1 = 100;
	} elsif ($t1 < 0) {
		$t1 = 0; 
	}
	return $t1;
}

sub I2C_BME280_DbLog_splitFn($) {  			# Einheiten
    my ($event) = @_;
    Log3 undef, 5, "in DbLog_splitFn empfangen: $event"; 
    my ($reading, $value, $unit) = "";

    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    $value = $parts[0];
    $unit = "\xB0C" if(lc($reading) =~ m/temp/);
    $unit = "hPa" 	if(lc($reading) =~ m/pres/);
	$unit = "%" 	if(lc($reading) =~ m/humi/);
    return ($reading, $value, $unit);
}

1;

=pod
=item device
=item summary reads pressure, humidity and temperature from an via I2C connected BME280
=item summary_DE lese Druck, Feuchte und Temperatur eines &uuml;ber I2C angeschlossenen BME280
=begin html

<a name="I2C_BME280"></a>
<h3>I2C_BME280</h3>
(en | <a href="commandref_DE.html#I2C_BME280">de</a>)
<ul>
  <a name="I2C_BME280"></a>
    Provides an interface to the digital pressure/humidity sensor BME280
    The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
	or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
	<b>attribute IODev must be set</b><br>
  <b>Define</b>
  <ul>
    <code>define BME280 I2C_BME280 [&lt;I2C Address&gt;]</code><br><br>
    <code>&lt;I2C Address&gt;</code> may be an 2 digit hexadecimal value (0xnn) or an decimal value<br>
	Without defined <code>&lt;I2C Address&gt;</code> 0x76 (hexadecimal) = 118 (decimal) will be used.<br>
	An I2C address are 7 MSB, the LSB is the R/W bit.<br>
    <br>
    Examples:
    <pre>
      define BME280 I2C_BME280 0x77
      attr BME280 poll_interval 5
    </pre>
  </ul>

  <a name="I2C_BME280set"></a>
  <b>Set</b>
  <ul>
    <code>set BME280 &lt;readValues&gt;</code>
    <br><br>
    Reads current temperature, humidity and pressure values from the sensor.<br>
    Normaly this execute automaticly at each poll intervall. You can execute
    this manually if you want query the current values.
    <br><br>
  </ul>

	<a name="I2C_BME280attr"></a>
	<b>Attributes</b>
	<ul>
		<li>oversampling_t,oversampling_h,oversampling_p<br>
			Controls the oversampling settings of the temperature,humidity or pressure measurement in the sensor.<br>
			Default: 1, valid values: 0, 1, 2, 3, 4, 5<br>
			0 switches the respective measurement off<br>
			1 to 5 complies to oversampling value 2^value/2<br><br>
		</li>
		<li>poll_interval<br>
			Set the polling interval in minutes to query the sensor for new measured
			values.<br>
			Default: 5, valid values: any whole number<br><br>
		</li>
		<li>roundTemperatureDecimal,roundHumidityDecimal,roundPressureDecimal<br>
			Round temperature, humidity or pressure values to given decimal places.<br>
			Default: 1, valid values: 0, 1, 2<br><br>
		</li>
		<li>altitude<br>
			if set, this altitude is used for calculating the pressure related to sea level (nautic null) NN<br><br>
			Note: this is a global attributes, e.g<br> 
			<code>attr global altitude 220</code>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_BME280"></a>
<h3>I2C_BME280</h3>
(<a href="commandref.html#I2C_BME280">en</a> | de)
<ul>
  <a name="I2C_BME280"></a>
    Erm&ouml;glicht die Verwendung eines digitalen (Luft)druck/feuchtesensors BME280 &uuml;ber den I2C Bus des Raspberry Pi.<br><br>
	I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
	oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
	<b>Das Attribut IODev muss definiert sein.</b><br>
  
	<b>Define</b>
	<ul>
		<code>define BME280 &lt;BME280_name&gt; [&lt;I2C Addresse&gt;]</code><br><br>
		<code>&lt;I2C Address&gt;</code> kann ein zweistelliger Hex-Wert (0xnn) oder ein Dezimalwert sein<br>
		Fehlt <code>&lt;I2C Address&gt;</code> wird 0x76 (hexadezimal) = 118 (dezimal) verwendet.<br>
		Als I2C Adresse verstehen sich die 7 MSB, das LSB ist das R/W Bit.<br>
		<br>
		Beispiel:
		<pre>
			define BME280 I2C_BME280 0x77
			attr BME280 poll_interval 5
		</pre>
	</ul>

	<a name="I2C_BME280set"></a>
	<b>Set</b>
	<ul>
		<code>set BME280 readValues</code>
		<br><br>
		<code>set &lt;name&gt; readValues</code><br>
		Aktuelle Temperatur, Feuchte und Luftdruck Werte vom Sensor lesen.<br><br>
	</ul>

	<a name="I2C_BME280attr"></a>
	<b>Attribute</b>
		<ul>
		<li>oversampling_t,oversampling_h,oversampling_p<br>
			Steuert das jeweils das Oversampling der Temperatur-, Feuchte-, oder Druckmessung im Sensor.<br>
			Standard: 1, g&uuml;ltige Werte: 0, 1, 2, 3, 4, 5<br>
			0 deaktiviert die jeweilige Messung<br>
			1 to 5 entspricht einem Oversampling von 2^zahl/2<br><br>
		</li>
		<li>poll_interval<br>
			Definiert das Poll Intervall in Minuten f&uuml;r das Auslesen einer neuen Messung.<br>
			Default: 5, g&uuml;ltige Werte: 1, 2, 5, 10, 20, 30<br><br>
		</li>
		<li>roundTemperatureDecimal, roundHumidityDecimal, roundPressureDecimal<br>
			Rundet jeweils den Temperatur-, Feuchte-, oder Druckwert mit den angegebenen Nachkommastellen.<br>
			Standard: 1, g&uuml;ltige Werte: 0, 1, 2<br><br>
		</li>
		<li>altitude<br>
			Wenn dieser Wert definiert ist, wird diese Angabe zus&auml; f&uuml;r die Berechnung des 
			Luftdrucks bezogen auf Meeresh&ouml;he (Normalnull) NN herangezogen.<br>
			Bemerkung: Dies ist ein globales Attribut.<br><br>
			<code>attr global altitude 220</code>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
		</ul><br>
</ul>

=end html_DE
=cut
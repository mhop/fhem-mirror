##############################################
#
# Modul for reading a EMC1001 digital temperature sensor via I2C
# (see http://ww1.microchip.com/downloads/en/DeviceDoc/20005411A.pdf)
#
# Copyright (C) 2018 Stephan Eisler
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id$
#
##############################################

package main;

use strict;
use warnings;

use constant {
	EMC1001_I2C_ADDRESS 	=> 0x48,    # EMC1001 I2C ADDRESS
	Reg_TMP_HB		=> 0x00,    # R temperature value high byte
	Reg_STATUS    		=> 0x01,    # RC Status
	Reg_TMP_LB    		=> 0x02,    # R low byte containing 1/4 deg fraction
	Reg_Config    		=> 0x03,    # R/W Configuration
	Reg_Cnv_Rate 		=> 0x04,    # R/W Conversion Rate
	Reg_THL_HB    		=> 0x05,    # R/W Temperature High Limit High Byte
	Reg_THL_LB    		=> 0x06,    # R/W Temperature High Limit Low Byte
	Reg_TLL_HB    		=> 0x07,    # R/W Temperature Low Limit High Byte
	Reg_TLL_LB    		=> 0x08,    # R/W Temperature Low Limit Low Byte
	Reg_One_Sht   		=> 0x0f,    # R One-Shot
	Reg_THM_LMT   		=> 0x20,    # R/W THERM Limit
	Reg_THM_HYS   		=> 0x21,    # R/W THERM Hysteresis
	Reg_SMB_TO    		=> 0x22,    # R/W SMBus Timeout Enable
	Reg_Prd_ID    		=> 0xfd,    # R Product ID Register
	Reg_Mnf_ID    		=> 0xfe,    # R Manufacture ID
	Reg_Rev_No    		=> 0xff     # R Revision Number
};

##################################################
# Forward declarations
#
sub I2C_EMC1001_I2CRec ($$);
sub I2C_EMC1001_GetReadings ($$);
sub I2C_EMC1001_GetTemp ($@);
sub I2C_EMC1001_calcTrueTemperature($$);


my %sets = (
	'readValues' => 1,
);

sub I2C_EMC1001_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_EMC1001_Define';
	$hash->{InitFn}   = 'I2C_EMC1001_Init';
	$hash->{AttrFn}   = 'I2C_EMC1001_Attr';
	$hash->{SetFn}    = 'I2C_EMC1001_Set';
	#$hash->{GetFn}    = 'I2C_EMC1001_Get';
	$hash->{UndefFn}  = 'I2C_EMC1001_Undef';
	$hash->{I2CRecFn} = 'I2C_EMC1001_I2CRec';
	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:1,2,5,10,20,30 ' .
	          					'roundTemperatureDecimal:0,1,2 ' .
											$readingFnAttributes;
  $hash->{DbLog_splitFn} = "I2C_EMC1001_DbLog_splitFn";
}

sub I2C_EMC1001_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);
	$hash->{STATE} = 'defined';

	my $name = $a[0];

	my $msg = '';
	if((@a < 2)) {
		$msg = 'wrong syntax: define <name> I2C_EMC1001 [I2C-Address]';
	}
	if ($msg) {
		Log3 ($hash, 1, $msg);
		return $msg;
	}
	if ($main::init_done) {
		eval { I2C_EMC1001_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_EMC1001_Catch($@) if $@;
	}
}

sub I2C_EMC1001_Init($$) {					# wird bei FHEM start Define oder wieder
	my ( $hash, $args ) = @_;
	my $name = $hash->{NAME};

	if (defined (my $address = shift @$args)) {
		$hash->{I2C_Address} = $address =~ /^0x.*$/ ? oct($address) : $address;
		return "$name: I2C Address not valid" unless ($hash->{I2C_Address} < 128 && $hash->{I2C_Address} > 3);
	} else {
		$hash->{I2C_Address} = EMC1001_I2C_ADDRESS;
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
				I2C_EMC1001_i2cread($hash, Reg_Prd_ID, 1);		#get Prd Id
				I2C_EMC1001_i2cread($hash, Reg_Mnf_ID, 1);		#get Mnf Id
				I2C_EMC1001_i2cread($hash, Reg_Rev_No, 1);		#get Reg Rev No
			};
    return I2C_EMC1001_Catch($@) if $@;
}

sub I2C_EMC1001_Catch($) {					# Fehlermeldungen formattieren
	my $exception = shift;
	if ($exception) {
		$exception =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	return undef;
}

sub I2C_EMC1001_Attr (@) {					# Wird beim Attribut anlegen/aendern aufgerufen
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';

	if (defined $command && $command eq "set" && $attr eq "IODev") {
		eval {
			if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
				main::AssignIoPort($hash,$val);
				my @def = split (' ',$hash->{DEF});
				I2C_EMC1001_Init($hash,\@def) if (defined ($hash->{IODev}));
			}
        };
		$msg = I2C_EMC1001_Catch($@) if $@;
	} elsif ($attr eq 'poll_interval') {
		if (defined($val)) {
			if ($val =~ m/^(0*[1-9][0-9]*)$/) {
				RemoveInternalTimer($hash);
				I2C_EMC1001_Poll($hash) if ($main::init_done);
				#InternalTimer(gettimeofday() + 5, 'I2C_EMC1001_Poll', $hash, 0) if ($main::init_done);
			} else {
				$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
			}
		} else {
			RemoveInternalTimer($hash);
		}
	} elsif ($attr =~ m/^round(Temperature)Decimal$/ && defined($val)) {
		$msg = 'Wrong value: $val for $attr defined. value must be a one of 0,1,2' unless ($val =~ m/^(0*[0-2])$/);
	}
	return ($msg) ? $msg : undef;
}

sub I2C_EMC1001_Poll($) {					# Messwerte regelmaessig anfordern
	my ($hash) =  @_;
	my $name = $hash->{NAME};

	I2C_EMC1001_Set($hash, ($name, 'readValues'));						# Read values
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_EMC1001_Poll', $hash, 0);
	}
}

sub I2C_EMC1001_Set($@) {					# Messwerte manuell anfordern
	my ($hash, @a) = @_;

	my $name = $a[0];
	my $cmd =  $a[1];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)  . ":noArg"
	}

	if ($cmd eq 'readValues') {
			I2C_EMC1001_i2cread($hash, Reg_TMP_HB, 1);
			I2C_EMC1001_i2cread($hash, Reg_TMP_LB, 1);
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 1, 'I2C_EMC1001_UpdateReadings', $hash, 0);
	}
	return undef
}

sub I2C_EMC1001_Get($@) {					# Messwerte manuell anfordern
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];

	if (defined($cmd) && $cmd eq 'readValues') {
			I2C_EMC1001_i2cread($hash, Reg_TMP_HB, 1);
			I2C_EMC1001_i2cread($hash, Reg_TMP_LB, 1);
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday() + 1, 'I2C_EMC1001_UpdateReadings', $hash, 0);
	} else {
		return 'Unknown argument ' . $cmd . ', choose one of readValues:noArg';
	}
	return undef
}

sub I2C_EMC1001_UpdateReadings($) {			# Messwerte auslesen
	my ($hash) = @_;
	I2C_EMC1001_i2cread($hash, Reg_TMP_HB, 1);
	I2C_EMC1001_i2cread($hash, Reg_TMP_LB, 1);
	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);	#poll_interval Timer wiederherstellen
	InternalTimer(gettimeofday() + ($pollInterval * 60), 'I2C_EMC1001_Poll', $hash, 0) if ($pollInterval > 0);
}

sub I2C_EMC1001_Undef($$) {					# Device loeschen
	my ($hash, $arg) = @_;
	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_EMC1001_I2CRec ($$) {				# wird vom IODev aus aufgerufen wenn I2C Daten vorliegen
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $pname = undef;
	my $phash = $hash->{IODev};
	$pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 																#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	}

	if ( $clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
		if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
			Log3 $hash, 5, "$name Rx, Reg: $clientmsg->{reg}, Data: $clientmsg->{received}";
			I2C_EMC1001_GetProdId ($hash, $clientmsg->{received}) if $clientmsg->{reg} == Reg_Prd_ID && $clientmsg->{nbyte} == 1;
			I2C_EMC1001_GetMnfId ($hash, $clientmsg->{received}) if $clientmsg->{reg} == Reg_Mnf_ID && $clientmsg->{nbyte} == 1;
			I2C_EMC1001_GetRevN ($hash, $clientmsg->{received}) if $clientmsg->{reg} == Reg_Rev_No && $clientmsg->{nbyte} == 1;
			I2C_EMC1001_GetReadingsTemperatureValueHighByte ($hash, $clientmsg->{received}) if $clientmsg->{reg} == Reg_TMP_HB && $clientmsg->{nbyte} == 1;
			I2C_EMC1001_GetReadingsTemperatureValueLowByte ($hash, $clientmsg->{received}) if $clientmsg->{reg} == Reg_TMP_LB && $clientmsg->{nbyte} == 1;
		}
	}

	return undef
}

sub I2C_EMC1001_GetProdId ($$) {
	my ($hash, $rawdata) = @_;
	if ($rawdata == hex("00")) {
		$hash->{DeviceType} = "EMC1001";
	} elsif ($rawdata == hex("01")) {
		$hash->{DeviceType} = "EMC1001-1";
	}
	readingsSingleUpdate($hash, 'DeviceType', $hash->{DeviceType}, 1);
	$hash->{STATE} = 'Initialized';
	I2C_EMC1001_Poll($hash) if defined(AttrVal($hash->{NAME}, 'poll_interval', undef));			# wenn poll_interval definiert -> timer starten 
}

sub I2C_EMC1001_GetMnfId ($$) {
	my ($hash, $rawdata) = @_;
	readingsSingleUpdate($hash, 'DeviceManufactureId', sprintf("0x%X", $rawdata), 1);
}

sub I2C_EMC1001_GetRevN ($$) {
	my ($hash, $rawdata) = @_;
	readingsSingleUpdate($hash, 'DeviceRevisionNumber', sprintf("%d", $rawdata), 1);
}

sub I2C_EMC1001_GetReadingsTemperatureValueHighByte ($$) {			# empfangenes Temperature High Byte verarbeiten
		my ($hash, $rawdata) = @_;
		Log3 $hash, 5, "ReadingsTemperatureValueHighByte: $rawdata";
		$hash->{TemperatureValueHighByte} = $rawdata;
}

sub I2C_EMC1001_GetReadingsTemperatureValueLowByte ($$) {			# empfangenes Temperature Low Byte verarbeiten
		my ($hash, $rawdata) = @_;
		Log3 $hash, 5, "ReadingsTemperatureValueLowByte: $rawdata";
		$hash->{TemperatureValueLowByte} = $rawdata;
		I2C_EMC1001_GetTemp($hash, $rawdata);

		my $tem = ReadingsVal($hash->{NAME},"temperature", undef);
		readingsSingleUpdate(
			$hash,
			'state',
			(defined $tem ? "T: $tem " : ""),
			1
		);
}

sub I2C_EMC1001_GetTemp($@) {				# Temperatur Messwerte verarbeiten
	my ($hash, @raw) = @_;

	my $temp= $hash->{TemperatureValueHighByte};
	my $templo= $hash->{TemperatureValueLowByte};

	$templo = $templo >> 6;

	if ($temp < 0) {
	        $templo = 3-$templo;
	}
		my $temperature = sprintf(
			'%.' . AttrVal($hash->{NAME}, 'roundTemperatureDecimal', 1) . 'f',
			sprintf("%d.%d", $temp, $templo*25)
		);
		readingsSingleUpdate($hash, 'temperature', $temperature, 1);
}

sub I2C_EMC1001_i2cread($$$) {				# Lesebefehl an Hardware absetzen (antwort kommt in I2C_*****_I2CRec an)
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

sub I2C_EMC1001_i2cwrite($$$) {				# Schreibbefehl an Hardware absetzen
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

sub I2C_EMC1001_DbLog_splitFn($) {  			# Einheiten
    my ($event) = @_;
    Log3 undef, 5, "in DbLog_splitFn empfangen: $event";
    my ($reading, $value, $unit) = "";

    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    $value = $parts[0];
    $unit = "\xB0C" if(lc($reading) =~ m/temp/);
    return ($reading, $value, $unit);
}

1;

=pod
=item device
=item summary reads temperature from an via I2C connected EMC1001
=item summary_DE lese Temperatur eines &uuml;ber I2C angeschlossenen EMC1001
=begin html

<a name="I2C_EMC1001"></a>
<h3>I2C_EMC1001</h3>
(en | <a href="commandref_DE.html#I2C_EMC1001">de</a>)
<ul>
  <a name="I2C_EMC1001"></a>
    Provides an interface to the digital temperature sensor EMC1001
    The I2C messages are send through an I2C interface module like <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
	or <a href="#NetzerI2C">NetzerI2C</a> so this device must be defined first.<br>
	<b>attribute IODev must be set</b><br>
  <b>Define</b>
  <ul>
    <code>define EMC1001 I2C_EMC1001 [&lt;I2C Address&gt;]</code><br><br>
    without defined <code>&lt;I2C Address&gt;</code> 0x48 will be used as address<br>
    <br>
    Examples:
    <pre>
      define EMC1001 I2C_EMC1001 0x48
      attr EMC1001 poll_interval 5
			attr roundTemperatureDecimal 2
    </pre>
  </ul>

  <a name="I2C_EMC1001set"></a>
  <b>Set</b>
  <ul>
    <code>set EMC1001 &lt;readValues&gt;</code>
    <br><br>
    Reads current temperature values from the sensor.<br>
    Normaly this execute automaticly at each poll intervall. You can execute
    this manually if you want query the current values.
    <br><br>
  </ul>

	<a name="I2C_EMC1001attr"></a>
	<b>Attributes</b>
	<ul>
		<li>poll_interval<br>
			Set the polling interval in minutes to query the sensor for new measured
			values.<br>
			Default: 5, valid values: any whole number<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Round temperature values to given decimal places.<br>
			Default: 1, valid values: 0, 1, 2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul><br>
</ul>

=end html

=begin html_DE

<a name="I2C_EMC1001"></a>
<h3>I2C_EMC1001</h3>
(<a href="commandref.html#I2C_EMC1001">en</a> | de)
<ul>
  <a name="I2C_EMC1001"></a>
    Erm&ouml;glicht die Verwendung eines digitalen Temperatur EMC1001 &uuml;ber den I2C Bus des Raspberry Pi.<br><br>
	I2C-Botschaften werden &uuml;ber ein I2C Interface Modul wie beispielsweise das <a href="#RPII2C">RPII2C</a>, <a href="#FRM">FRM</a>
	oder <a href="#NetzerI2C">NetzerI2C</a> gesendet. Daher muss dieses vorher definiert werden.<br>
	<b>Das Attribut IODev muss definiert sein.</b><br>

	<b>Define</b>
	<ul>
		<code>define EMC1001 &lt;EMC1001_name&gt; [&lt;I2C Addresse&gt;]</code><br><br>
		Fehlt <code>&lt;I2C Address&gt;</code> wird 0x48 verwendet<br>
		<br>
		Beispiel:
		<pre>
			define EMC1001 I2C_EMC1001 0x48
			attr EMC1001 poll_interval 5
			attr roundTemperatureDecimal 2
		</pre>
	</ul>

	<a name="I2C_EMC1001set"></a>
	<b>Set</b>
	<ul>
		<code>set EMC1001 readValues</code>
		<br><br>
		<code>set &lt;name&gt; readValues</code><br>
		Aktuelle Temperatur Werte vom Sensor lesen.<br><br>
	</ul>

	<a name="I2C_EMC1001attr"></a>
	<b>Attribute</b>
		<ul>
		<li>poll_interval<br>
			Definiert das Poll Intervall in Minuten f&uuml;r das Auslesen einer neuen Messung.<br>
			Default: 5, g&uuml;ltige Werte: 1, 2, 5, 10, 20, 30<br><br>
		</li>
		<li>roundTemperatureDecimal<br>
			Rundet jeweils den Temperaturwert mit den angegebenen Nachkommastellen.<br>
			Standard: 1, g&uuml;ltige Werte: 0, 1, 2<br><br>
		</li>
		<li><a href="#IODev">IODev</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
		</ul><br>
</ul>

=end html_DE
=cut


##############################################
# $Id$
#
# Version: 1.8
# Date: 2017-06-29
# Corrected documentation.
#
# Version: 1.7
# Date: 2015-12-29
# Updated documentation for new attribute
#
# Version: 1.6
# Date: 2015-12-29
# Added attribute to select if leading zero's are trimmed off
#
# Version: 1.5
# Date: 2015-12-28
# Added extra values
#
# Version: 1.4
# Date: 2015-12-28
# Fixed problem where wilcard was not removed and
# added power returned values
#
# Version: 1.3
# Date: 2015-12-24
# Removed the wildcard between value and unit
#
# Version: 1.2
# Date: 2015-12-23
# Added code to handle other protocol from smartmeter. (DSMR P1)

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use Data::Dumper;
use DBI;

sub SmartMeterP1_Attr(@);
sub SmartMeterP1_ParseTelegramLine($$$@);
sub SmartMeterP1_Parse($$$$);
sub SmartMeterP1_Read($);
sub SmartMeterP1_Ready($);

sub
SmartMeterP1_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "SmartMeterP1_Read";
  $hash->{ReadyFn} = "SmartMeterP1_Ready";

# Normal devices
  $hash->{DefFn}   = "SmartMeterP1_Define";
  $hash->{UndefFn} = "SmartMeterP1_Undef";
  $hash->{AttrFn}  = "SmartMeterP1_Attr";
  $hash->{AttrList}= "dbName dbHost dbPort dbUser dbPassword write2db:1,0 dbUpdateInterval:0,1,5,10,15,20,25,30,45,60 removeUnitSeparator:false,true removeLeadingZero:false,true " .
                     $readingFnAttributes;

  $hash->{ShutdownFn} = "SmartMeterP1_Shutdown";

}

#####################################
sub
SmartMeterP1_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> SmartMeterP1 {none | devicename[\@baudrate]} ";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];

  if($dev eq "none") {
    Log3 $name, 1, "$name device is none, will use deault /dev/ttyUSB0@115200";
  }

  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "SmartMeterP1_DoInit");

  $hash->{Telegram} = {};
  $hash->{TelegramStart} = 0;

  $hash->{DBH} = undef;

  return $ret;
}

#####################################
sub
SmartMeterP1_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  DevIo_CloseDev($hash);

  $hash->{DBH}->disconnect if (defined($hash->{DBH}));

  return undef;
}

#####################################
sub
SmartMeterP1_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub
SmartMeterP1_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  readingsSingleUpdate($hash, "state", "Initialized", 1);

  return undef;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
SmartMeterP1_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};

  my $culdata = $hash->{PARTIAL};
  Log3 $name, 5, "SmartMeterP1/RAW: $culdata/$buf";
  $culdata .= $buf;

  while($culdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$culdata) = split("\n", $culdata, 2);
    $rmsg =~ s/\r//;
    SmartMeterP1_Parse($hash, $hash, $name, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $culdata;
}

sub
ConvertTelegramTime($)
{
  my $inTime = shift;

  $inTime =~ s/(..)(..)(..)(..)(..)(..)[SW]*/20$1\-$2\-$3 $4\:$5\:$6/;

  return $inTime;  
}

sub
SmartMeterP1_Connect2DB($$$)
{
  my ($hash,$name,$write2db) = @_;

  if ($write2db == 1) {
	if (defined($hash->{DBH})) {
		$hash->{DBH}->disconnect;
	}

	my $dbHost = AttrVal($name,"dbHost",undef);
	my $dbPort = AttrVal($name,"dbPort",3306);
	my $dbName = AttrVal($name,"dbName",undef);
	my $dbUser = AttrVal($name,"dbUser",undef);
	my $dbPassword = AttrVal($name,"dbPassword",undef);

	Log3 $name, 5, "SmartMeterP1:Connecting to DBI:mysql:database=$dbName;host=$dbHost;port=$dbPort,$dbUser,$dbPassword";

	if (defined($dbHost) && defined($dbPort) && defined($dbName) && defined($dbUser) && defined($dbPassword)) {

		$hash->{DBH} = DBI->connect("DBI:mysql:database=$dbName;host=$dbHost;port=$dbPort",$dbUser,$dbPassword);

		if (!defined($hash->{DBH})) {
			Log3 $name, 1, "ERROR connecting to database: ".DBI->errstr;
		}
		else {
			Log3 $name, 3, "SmartMeterP1:Connected to database DBI:mysql:database=$dbName;host=$dbHost;port=$dbPort;user=$dbUser";
			$hash->{dbInsertSQL} = $hash->{DBH}->prepare('INSERT INTO smartmeter (`date`,obis_ref,value,unit) VALUES (?,?,?,?)')
		}
	}
  }

}

sub
SmartMeterP1_Write2DB($$$$$)
{
  my ($hash,$name,$obis_ref,$date,$valueStr) = @_;

  SmartMeterP1_Connect2DB($hash,$name,AttrVal($name,"write2db",0)) if (!defined($hash->{DBH}));
  if (!defined($hash->{DBH})) {
	Log3 $name, 4, "SmartMeterP1: Error reconnecting to database.";
	return;
  }

  my $dateValue = myStr2Date($date);
  my $interval = AttrVal($name,"dbUpdateInterval", 5);
  if (defined($hash->{$obis_ref})) {
	return if ($dateValue < ($hash->{$obis_ref} + ($interval*60)));
  }

  $hash->{$obis_ref} = $dateValue;

  my $value;
  my $unit;
  if ( AttrVal($name,"removeUnitSeparator", "false") eq "true" ) {
	($value,$unit) = split(/ /, $valueStr, 2);
  }
  else {
	($value,$unit) = split(/\*/, $valueStr, 2);
  }

  $hash->{dbInsertSQL}->execute($date,$obis_ref,$value,$unit);
  if (DBI->err) {
	SmartMeterP1_Connect2DB($hash,$name,AttrVal($name,"write2db",0));
	if (defined($hash->{DBH})) {
		$hash->{dbInsertSQL}->execute($date,$obis_ref,$value,$unit);
	}
	else {
		Log3 $name, 1, "SmartMeterP1: Error reconnecting to database.";
		return;
	}
  }
  $hash->{dbInsertSQL}->finish;
}

sub
RemoveLeadingZero($$)
{
  my ($name, $value) = @_;

  if ( AttrVal($name,"removeLeadingZero", "false") eq "true" ) {
  	$value =~ s/^(0*)?([0-9]+\..*)/$2/;
  }

  return $value;
}

sub
RemoveUnitSeparator($$)
{
  my ($name, $value) = @_;

  if ( AttrVal($name,"removeUnitSeparator", "false") eq "true" ) {
  	$value =~ s/(.*)?\*(.*)/$1 $2/;
  }

  $value = RemoveLeadingZero($name,$value);

  return $value;
}

sub
SmartMeterP1_ParseTelegramLine($$$@)
{
  my ($hash,$name,$obis_ref,@attributes) = @_;

  Log3 $name, 4, " Telegram obis: $obis_ref";
  Log3 $name, 4, " Telegram attr: ".Dumper(@attributes);

  if ($obis_ref eq "0-0:1.0.0") {
	#Date-time stamp of the P1 message
	# YYMMDDhhmmssW
	$hash->{TelegramTime} = ConvertTelegramTime($attributes[0]);
	readingsSingleUpdate($hash,"TelegramTime",$hash->{TelegramTime},1);
  }
  elsif ($obis_ref eq "1-0:1.8.1") {
	# Meter reading electricity delivered to client low Tariff in 0,001 kWh
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityDeliveredLowTariff", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityDeliveredLowTariff",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "1-0:1.8.2") {
	# Meter reading electricity delivered to client normal Tariff in 0,001 kWh
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityDeliveredNormalTariff", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityDeliveredNormalTariff",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "1-0:2.8.1") {
	# Meter reading electricity delivered by client low Tariff in 0,001 kWh
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityProducedLowTariff", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityProducedLowTariff",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "1-0:2.8.2") {
	# Meter reading electricity delivered by client normal Tariff in 0,001 kWh
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityProducedNormalTariff", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityProducedNormalTariff",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "1-0:1.7.0") {
	# Actual electricity power delivered (+P) in 1 Watt resolution
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityPowerDelivered", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityPowerDelivered",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "1-0:2.7.0") {
	# Actual electricity power received (-P) in 1 Watt resolution
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityPowerProduced", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityPowerProduced",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "0-0:17.0.0") {
	# The actual threshold Electricity in kW
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ElectricityThreshold", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ElectricityThreshold",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "0-0:96.14.0") {
	# Tariff indicator electricity.
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"TariffIndicatorElectricity", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"TariffIndicatorElectricity",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "0-0:96.3.10") {
	# Switch position electricity
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"SwitchPositionElectricity", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"SwitchPositionElectricity",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
  elsif ($obis_ref eq "0-1:24.2.1") {
	# Last hourly value gas delivered to client in m3
	$hash->{".updateTimestamp"} = ConvertTelegramTime($attributes[0]);
	my $tmp = ReadingsVal($name,"GasDeliveredTime", "-");
	if (($tmp eq "-") || ($tmp ne ConvertTelegramTime($attributes[0]))) {
		readingsSingleUpdate($hash,"GasDeliveredTime",ConvertTelegramTime($attributes[0]),1);
		$attributes[1] = RemoveUnitSeparator($name, $attributes[1]);
		readingsSingleUpdate($hash,"GasDelivered",$attributes[1],1);
		SmartMeterP1_Write2DB($hash,$name,$obis_ref,ConvertTelegramTime($attributes[0]),$attributes[1]);
	}
  }
  elsif ($obis_ref eq "0-1:24.3.0") {
	$hash->{Telegram}->{Gas}->{used} = 1;
	$hash->{Telegram}->{Gas}->{time} = ConvertTelegramTime($attributes[0]);
	$hash->{Telegram}->{Gas}->{obis_ref} = $attributes[4];
	$hash->{Telegram}->{Gas}->{unit} = $attributes[5];
  }
  elsif ($obis_ref eq "") {
	if (($hash->{Telegram}->{Gas}->{used} == 1) && ($hash->{Telegram}->{Gas}->{obis_ref} eq "0-1:24.2.1" )) {
		# Last hourly value gas delivered to client in m3
		$hash->{".updateTimestamp"} = $hash->{Telegram}->{Gas}->{time};
		my $tmp = ReadingsVal($name,"GasDeliveredTime", "-");
		$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
		if (($tmp eq "-") || ($tmp ne $hash->{Telegram}->{Gas}->{time})) {
			readingsSingleUpdate($hash,"GasDeliveredTime",$hash->{Telegram}->{Gas}->{time},1);
			if ( AttrVal($name,"removeUnitSeparator", "false") eq "true" ) {
				readingsSingleUpdate($hash,"GasDelivered",$attributes[0]." ".$hash->{Telegram}->{Gas}->{unit},1);
				SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{Telegram}->{Gas}->{time},$attributes[0]." ".$hash->{Telegram}->{Gas}->{unit});
			}
			else {
				readingsSingleUpdate($hash,"GasDelivered",$attributes[0]."*".$hash->{Telegram}->{Gas}->{unit},1);
				SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{Telegram}->{Gas}->{time},$attributes[0]."*".$hash->{Telegram}->{Gas}->{unit});
			}
		}
		$hash->{Telegram}->{Gas}->{used} = 0;
	}
  }
  elsif ($obis_ref eq "0-1:24.4.0") {
	# Valve position Gas
	$hash->{".updateTimestamp"} = $hash->{TelegramTime};
	my $tmp = ReadingsVal($name,"ValvePositionGas", "-");
	$attributes[0] = RemoveUnitSeparator($name, $attributes[0]);
	readingsSingleUpdate($hash,"ValvePositionGas",$attributes[0],1) if (($tmp eq "-") || ($tmp ne $attributes[0]));
	SmartMeterP1_Write2DB($hash,$name,$obis_ref,$hash->{TelegramTime},$attributes[0]) if (($tmp eq "-") || ($tmp ne $attributes[0]));
  }
}

sub
SmartMeterP1_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  Log3 $name, 5, "SmartMeterP1/Telegramline: $rmsg";

  if ($rmsg =~ m/^\/(.*)/) {
	$hash->{TelegramStart} = 1;
	$hash->{Telegram} = {};
	$hash->{Telegram}->{Gas} = {};
	$hash->{Telegram}->{Gas}->{used} = 0;
	Log3 $name, 4, " Telegram start: $1";
  }
  else {
	if ($hash->{TelegramStart} == 1) {
		if ($rmsg =~ m/^\!(....)/) {
			Log3 $name, 4, " Telegram end: $1";
		}
		elsif ($rmsg =~ m/^\!/) {
			Log3 $name, 4, " Telegram end.";
		}
		else {
			Log3 $name, 4, " Telegram line: $rmsg";
			my $obis_ref;
			my @attributes;
			($obis_ref,@attributes) = split('\(', $rmsg);

			my $count = 0;
			while ($count < @attributes) {
				$attributes[$count] =~ s/\)//;
				$count++;
			}

			SmartMeterP1_ParseTelegramLine($hash,$name,$obis_ref,@attributes);
		}
	}
  }

}


#####################################
sub
SmartMeterP1_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "SmartMeterP1_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

sub
SmartMeterP1_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;

  my $hash = $defs{$name};

  Log3 $name, 3, "SmartMeterP1:Updating attribute '$aName' to '$aVal'";

  if (($aName eq "write2db") || ($aName eq "dbHost") || ($aName eq "dbPort") || ($aName eq "dbName") || ($aName eq "dbUser") || ($aName eq "dbPassword")) {

	# Something in the db attributes changed reconnect.
	if (defined($hash->{DBH})) {
		$hash->{DBH}->disconnect;
		undef $hash->{DBH};
	}

#	if ($aName eq "write2db") {
#		SmartMeterP1_Connect2DB($hash,$name,$aVal);
#	}
#	else {
#		SmartMeterP1_Connect2DB($hash,$name,AttrVal($name,"write2db",0));
#	}
  }
  return undef;
}


1;

=pod
=item device
=item summary    Read data from your Electricity and Gas smart meter
=begin html

<a name="SmartMeterP1"></a>
<h3>SmartMeterP1</h3>
<ul>

  <table>
  <tr><td>
  The SmartMeterP1 is a module which can interpret the data received from
  a Smart Meter used to keep track of electricity and gas usage.<br><br>

  Currently it can proces P1 protocol DSMR 4.0. Probably also others but
  not tested.<br>
  Tested with a Landys+Gyr E350 and a Iskra - ME382.<br><br>

  Note: This module may require the <code>Device::SerialPort</code> or
  <code>Win32::SerialPort</code> module if you attach the device via USB
  and the OS sets strange default parameters for serial devices.<br><br>

  </td><td>
  <img src="Landis-Gyr-E350-meter.jpg"/>
  </td></tr>
  </table>

  <a name="SmartMeterP1define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SmartMeterP1 &lt;device&gt;</code> <br>
    <br>
    USB-connected device (P1 USB-Serial cable):<br><ul>
      &lt;device&gt; specifies the serial port to read the incoming data from.
      The name of the serial-device depends on your distribution, under
      linux the ftdi-sio kernel module is responsible, and usually a
      /dev/ttyUSB0 device will be created.<br><br>

      You can specify a baudrate of 115200, e.g.: /dev/ttyUSB0@115200<br><br>

      For the Landys+Gyr E350 use: define SmartMeterP1 SmartMeterP1 /dev/ttyUSB0@115200<BR>
      For the Iskra - ME382 use: define SmartMeterP1 SmartMeterP1 /dev/p1usb@9600,7,E,1<BR><BR>

    </ul>
    <br>
    If the device is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>
  </ul>
  <br>

  <a name="SmartMeterP1attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="write2db">write2db</a><br>
	If you would like to store your read data into a mysql database you can activate 
	it with this setting. Allowed values are:<BR>
	0 - Do not write to datbase (default)<BR>
	1 - Write to database<BR><BR>

	If you want to write to a database you need to specify also the following attributes:<BR><BR>
	<code>dbHost<BR>
	dbName<BR>
	dbPassword<BR>
	dbPort<BR>
	dbUpdateInterval<BR>
	dbUser</code>
	<BR><BR>
	And create a table in your database called 'smartmeter with the following syntax:<BR>
<code>CREATE TABLE `smartmeter` (
  `date` datetime NOT NULL,
  `obis_ref` varchar(45) COLLATE utf8_bin NOT NULL,
  `value` float DEFAULT NULL,
  `unit` varchar(45) COLLATE utf8_bin DEFAULT NULL,
  PRIMARY KEY (`date`,`obis_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin</code>
        </li><br>
    <li><a name="dbHost">dbHost</a><br>
	The hostname or ip address of the MySQL server.
        </li><br>
    <li><a name="dbPort">dbPort</a><br>
	The TCP port the MySQL server is listening on. Default is 3306.
        </li><br>
    <li><a name="dbName">dbName</a><br>
	The name of the dabase to use.
        </li><br>
    <li><a name="dbUsername">dbUsername</a><br>
	The name of the MySQL use which has read and write access to the database
	and table 'smartmeter'.
        </li><br>
    <li><a name="dbPassword">dbPassword</a><br>
	Password of the MySQL user.
        </li><br>
    <li><a name="dbUpdateInterval">dbUpdateInterval</a><br>
	How often should the measured value be written to the database.<BR>
	This value is in minutes.<BR><BR>

	So when a new value is read from the smartmeter the time will be checked
	to the time of the last value written to the database. If the difference is
	bigger than this interval the value will be written to the database.<BR><BR>

	With this value you can control how much and how fast data is written into your database.
        </li><br>
    <li><a name="removeUnitSeparator">removeUnitSeparator</a><br>
	When set to true it will replace the unit asterisk separator by a space character.
	So 00900.701*m3 becomes 00900.701 m3
        </li><br>

    <li><a name="removeLeadingZero">removeLeadingZero</a><br>
	When set to true it will remove all leading zeros in a value.
	So 00900.701 m3 becomes 900.701 m3 and <BR>
        0000.123 kWh becomes 0.123 kWh
        </li><br>

  </ul>
  <br>
  </ul>

=end html

=cut

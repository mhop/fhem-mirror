################################################################################
# FHEM-Modul see www.fhem.de
# 18_JSN.pm
# JeeSensorNode
#
# Usage: define  <Name> JSN <Node-Nr>
################################################################################
# This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################
# Autor: Axel Rieger
# Version: 1.0
# Datum: 07.2011
# Kontakt: fhem [bei] anax [punkt] info
################################################################################
package main;
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use vars qw(%defs);
use vars qw(%attr);
use vars qw(%data);
use vars qw(%modules);
################################################################################
sub JSN_Initialize($)
{
  my ($hash) = @_;

  # Match/Prefix
  my $match = "JSN";
  $hash->{Match}     = "^JSN";
  $hash->{DefFn}     = "JSN_Define";
  $hash->{UndefFn}   = "JSN_Undef";
  $hash->{ParseFn}   = "JSN_Parse";
  $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,5 disable:0,1";
  #-----------------------------------------------------------------------------
  # Arduino/JeeNodes-Variables:
  # http://arduino.cc/en/Reference/HomePage
  # Integer = 2 Bytes -> form -32,768 to 32,767
  # Long (unsigned) = 4 Bytes -> from 0 to 4,294,967,295
  # Long (signed) = 4 Bytes -> from -2,147,483,648 to 2,147,483,647
  #

  # JeeConf
  # $data{JEECONF}{<SensorType>}{ReadingName}
  # $data{JEECONF}{<SensorType>}{DataBytes}
  # $data{JEECONF}{<SensorType>}{Prefix}
  # $data{JEECONF}{<SensorType>}{CorrFactor}
  # $data{JEECONF}{<SensorType>}{Function}
  # <SensorType>: 0-9 -> Reserved/not Used
  # <SensorType>: 10-99 -> Default
  # <SensorType>: 100-199 -> Userdifined
  # <SensorType>: 200-255 -> Internal/Test
  # Default-2-Bytes-------------------------------------------------------------
  $data{JEECONF}{12}{ReadingName} = "SensorData";
  $data{JEECONF}{12}{DataBytes} = 2;
  $data{JEECONF}{12}{Prefix} = $match;
  # Temperature ----------------------------------------------------------------
  $data{JEECONF}{11}{ReadingName} = "temperature";
  $data{JEECONF}{11}{DataBytes} = 2;
  $data{JEECONF}{11}{Prefix} = $match;
  $data{JEECONF}{11}{CorrFactor} = 0.1;
  # Brightness- ----------------------------------------------------------------
  $data{JEECONF}{12}{ReadingName} = "brightness";
  $data{JEECONF}{12}{DataBytes} = 4;
  $data{JEECONF}{12}{Prefix} = $match;
  # Triple-Axis-X-Y-Z----------------------------------------------------------
  $data{JEECONF}{13}{ReadingName} = "rtiple_axis";
  $data{JEECONF}{13}{Function} = "JSN_parse_12";
  $data{JEECONF}{13}{DataBytes} = 12;
  $data{JEECONF}{13}{Prefix} = $match;
  #-----------------------------------------------------------------------------
  # 14 Used by 18_JME
  # Counter --------------------------------------------------------------------
  # $data{JEECONF}{14}{ReadingName} = "counter";
  # $data{JEECONF}{14}{DataBytes} = 4;
  # $data{JEECONF}{14}{Prefix} = $match;
  # Pressure -------------------------------------------------------------------
  $data{JEECONF}{15}{ReadingName} = "pressure";
  $data{JEECONF}{15}{DataBytes} = 4;
  $data{JEECONF}{15}{CorrFactor} = 0.01;
  $data{JEECONF}{15}{Prefix} = $match;
  # Humidity -------------------------------------------------------------------
  $data{JEECONF}{16}{ReadingName} = "humidity";
  $data{JEECONF}{16}{DataBytes} = 1;
  $data{JEECONF}{16}{Prefix} = $match;
  # Light LDR ------------------------------------------------------------------
  $data{JEECONF}{17}{ReadingName} = "light_ldr";
  $data{JEECONF}{17}{DataBytes} = 1;
  $data{JEECONF}{17}{Prefix} = $match;
  # Motion ---------------------------------------------------------------------
  $data{JEECONF}{18}{ReadingName} = "motion";
  $data{JEECONF}{18}{DataBytes} = 1;
  $data{JEECONF}{18}{Prefix} = $match;
  # JeeNode InternalTemperatur -------------------------------------------------
  $data{JEECONF}{251}{ReadingName} = "AtmelTemp";
  $data{JEECONF}{251}{DataBytes} = 2;
  $data{JEECONF}{251}{Prefix} = $match;
  # JeeNode InternalRefVolatge -------------------------------------------------
  $data{JEECONF}{252}{ReadingName} = "PowerSupply";
  $data{JEECONF}{252}{DataBytes} = 2;
  $data{JEECONF}{252}{CorrFactor} = 0.0001;
  $data{JEECONF}{252}{Prefix} = $match;
  # JeeNode RF12 LowBat --------------------------------------------------------
  $data{JEECONF}{253}{ReadingName} = "RF12LowBat";
  $data{JEECONF}{253}{DataBytes} = 1;
  $data{JEECONF}{253}{Prefix} = $match;
  # JeeNode Milliseconds -------------------------------------------------------
  $data{JEECONF}{254}{ReadingName} = "Millis";
  $data{JEECONF}{254}{DataBytes} = 4;
  $data{JEECONF}{254}{Prefix} = $match;

}
################################################################################
sub JSN_Define($){
  # define J001 JSN <Node-Nr> [<Path_to_User_Conf_File>]
  # hash = New Device
  # defs = $a[0] <DEVICE-NAME> $a[1] DEVICE-TYPE $a[2]<Parameter-1-> $a[3]<Parameter-2->
  my ($hash, $def) = @_;
  my @a = split(/\s+/, $def);
  return "JSN: Unknown argument count " . int(@a) . " , usage define <NAME>
  NodeID [<Path_to_User_Conf_File>]"  if(int(@a) != 3);
  my $NodeID = $a[2];
  if(defined($modules{JSN}{defptr}{$NodeID})) {
    return "Node $NodeID allready define";
  }
  $hash->{CODE} = $NodeID;
  $hash->{STATE} = "NEW: " . TimeNow();
  $hash->{OrderID} = $NodeID;
  $modules{JSN}{defptr}{$NodeID}   = $hash;
  return undef;
}
################################################################################
sub JSN_Undef($$){
  my ($hash, $name) = @_;
  Log 4, "JeeNode Undef: " . Dumper(@_);
  my $NodeID = $hash->{NodeID};
  if(defined($modules{JSN}{defptr}{$NodeID})) {
    delete $modules{JSN}{defptr}{$NodeID}
  }
  return undef;
}
################################################################################
sub JSN_Parse($$) {
  my ($iodev, $rawmsg) = @_;
  # $rawmsg = JeeNodeID + SensorType + SensorData
  # rawmsg = JSN 03 252 03 65
  Log 5, "JSN PARSE RAW-MSG: " . $rawmsg . " IODEV:" . $iodev->{NAME};
  #
  my @data = split(/\s+/,$rawmsg);
  my $NodeID = $data[1];
  # my $NodeID = sprintf("%02x" ,($data[1]));
  # $NodeID = hex($NodeID);
  # my $NodeID = chr(ord($data[1]));
  my $SType = $data[2];
  my $data_bytes = $data{JEECONF}{$SType}{DataBytes};
  my $data_end = int(@data) - 1;
  # $array[$#array];
  Log 5, "JSN PARSE N:$NodeID S:$SType B:$data_bytes CNT:" . @data . " END:" . $data_end;
  my @SData = @data[3..$data_end];

	my ($hash,$name);
	if(defined($modules{JSN}{defptr}{$NodeID})) {
		$hash =  $modules{JSN}{defptr}{$NodeID};
		$name = $hash->{NAME};
	}
	else {
			return "UNDEFINED JSN_$NodeID JSN $NodeID";};
  my %readings;
  # Function-Data --------------------------------------------------------------
  # If defined $data{JEECONF}{<SensorType>}{Function} then the function handels
  # data parsing...return a hash key:reading_name Value:reading_value
  # Param to Function: $iodev,$name,$NodeID, $SType,@SData
  # Function-Data --------------------------------------------------------------
  if(defined($data{JEECONF}{$SType}{Function})) {
	my $func = $data{JEECONF}{$SType}{Function};
	if(!defined(&$func)) {
	  Log 0, "JSN PARSE Function not defined: $SType -> $func";
	  return undef;
	}
	no strict "refs";
	%readings = &$func($iodev,$name,$NodeID, $SType,@SData);
	use strict "refs";
  }
  else {
	# Sensor-Data Bytes to Values
	# lowBit HighBit reverse ....
	@SData = reverse(@SData);
	my $raw_value = join("",@SData);
	my $value = "";
	map {$value .= sprintf "%02x",$_} @SData;
	$value = hex($value);
	Log 5, "JSN PARSE DATA $NodeID - $SType - " . join(" " , @SData) . " -> " . $value;

	my $reading_name = $data{JEECONF}{$SType}{ReadingName};
	$readings{$reading_name} = $value;
	if(defined($data{JEECONF}{$SType}{CorrFactor})) {
	  my $corr = $data{JEECONF}{$SType}{CorrFactor};
	  $readings{$reading_name} = $value * $corr;
	}
  }
  #Reading
  my $i = 0;
  foreach my $r (sort keys %readings) {
	Log 5, "JSN $name $r:" . $readings{$r};
	$defs{$name}{READINGS}{$r}{VAL} = $readings{$r};
	$defs{$name}{READINGS}{$r}{TIME} = TimeNow();
	$defs{$name}{STATE} = TimeNow() . " " . $r;
	# Changed for Notify and Logs
	$defs{$name}{CHANGED}[$i] = $r . ": " . $readings{$r};
	$i++;
  }
  return $name;
}
################################################################################
sub JSN_parse_12() {
  my ($iodev,$name,$NodeID, $SType,@SData) = @_;
  Log 5, "JSN PARSE-12 DATA $NodeID - $SType - " . join(" " , @SData);
  my %reading;
  $reading{X} = "XXX";
  $reading{Y} = "YYY";
  $reading{Z} = "ZZZ";
  return \%reading;

}
################################################################################
1;

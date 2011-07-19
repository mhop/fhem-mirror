################################################################################
# FHEM-Modul see www.fhem.de
# 18_JME.pm
# JeeMeterNode
#
# Usage: define <Name> JME  <Node-Nr>
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
# READINGs
# MeterBase = MeterBase abgelesener Zaehlerstand...default 0
# MeterNow = aktueller Zaehlerstand...wird hochgezŠhlt
# Wenn MeterBase gesetzt ist, wird von dan an hochgezaehlt
# Wenn MeterBase gesetzt wird, werden 
# AVG_Hour, AVG_Day, AVG_Month
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
sub JME_Initialize($)
{
  my ($hash) = @_;
  
  # Match/Prefix
  my $match = "JME";
  $hash->{Match}     = "^JME";
  $hash->{DefFn}     = "JME_Define";
  $hash->{UndefFn}   = "JME_Undef";
  $hash->{SetFn}     = "JME_Set";
  $hash->{ParseFn}   = "JME_Parse";
  $hash->{AttrList}  = "do_not_notify:0,1 loglevel:0,5 disable:0,1 TicksPerUnit avg_data_day avg_data_month";
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
  # Counter --------------------------------------------------------------------
  $data{JEECONF}{14}{ReadingName} = "counter";
  $data{JEECONF}{14}{DataBytes} = 2;
  $data{JEECONF}{14}{Prefix} = $match;  
}
################################################################################
sub JME_Define($){
  # define J001 JME <Node-Nr>
  # hash = New Device
  # defs = $a[0] <DEVICE-NAME> $a[1] DEVICE-TYPE $a[2]<Parameter-1-> $a[3]<Parameter-2->
  my ($hash, $def) = @_;
  my @a = split(/\s+/, $def);
  return "JME: Unknown argument count " . int(@a) . " , usage define <NAME>
			NodeID [<Path_to_User_Conf_File>]"  if(int(@a) != 3);
  my $NodeID = $a[2];
  if(defined($modules{JME}{defptr}{$NodeID})) {
    return "Node $NodeID allready define"; 
  }
  $hash->{CODE} = $NodeID;
  $hash->{STATE} = "NEW: " . TimeNow();
  $hash->{OrderID} = ord($NodeID);
  $modules{JME}{defptr}{ord($NodeID)}   = $hash;
  
  # Init
  #$hash->{READINGS}{MeterBase}{TIME} = TimeNow();
  #$hash->{READINGS}{MeterBase}{VAL} = 0;
  #$hash->{READINGS}{MeterNow}{TIME} = TimeNow();
  #$hash->{READINGS}{MeterNow}{VAL} = 0;
  #$hash->{READINGS}{consumption}{TIME} = TimeNow();
  #$hash->{READINGS}{consumption}{VAL} = 0;
  #$hash->{READINGS}{current}{TIME} = TimeNow();
  #$hash->{READINGS}{current}{VAL} = 0;
  #$hash->{cnt_old} = 0;
  return undef;
}
################################################################################
sub JME_Undef($$){
  my ($hash, $name) = @_;
  Log 4, "JME Undef: " . Dumper(@_);
  my $NodeID = $hash->{NodeID};
  if(defined($modules{JME}{defptr}{$NodeID})) {
    delete $modules{JME}{defptr}{$NodeID}
  }
  return undef;
}
################################################################################
sub JME_Set($)
{
  my ($hash, @a) = @_;
  my $fields = "MeterBase MeterNow counter avg_day avg_month";
  return "Unknown argument $a[1], choose one of $fields" if($a[1] eq "?");
  
  if($fields =~ m/$a[1]/){
    $hash->{READINGS}{$a[1]}{VAL} = sprintf("%0.3f",$a[2]);
    $hash->{READINGS}{$a[1]}{TIME} = TimeNow();
  }
  return "";
}
################################################################################
sub JME_Parse($$) {
  my ($iodev, $rawmsg) = @_;
  # $rawmsg = JeeNodeID + SensorType + SensorData
  # rawmsg = JME 03 252 03 65
  Log 4, "JME PARSE RAW-MSG: " . $rawmsg . " IODEV:" . $iodev->{NAME};
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
  Log 4, "JME PARSE N:$NodeID S:$SType B:$data_bytes CNT:" . @data . " END:" . $data_end;
  my @SData = @data[3..$data_end];
	
  my ($hash,$name);
  if(defined($modules{JME}{defptr}{ord($NodeID)})) {
	  $hash =  $modules{JME}{defptr}{ord($NodeID)};
	  $name = $hash->{NAME};
  }
  else {
		  return "UNDEFINED JME_$NodeID JME $NodeID";};
  my %readings;

	# LogLevel
	my $ll = 5;
	if(defined($attr{$name}{loglevel})) {
		$ll = $attr{$name}{loglevel};
		}
  # Sensor-Data Bytes to Values
  # lowBit HighBit reverse ....
  @SData = reverse(@SData);
  my $raw_value = join("",@SData);
  my $value = "";
  map {$value .= sprintf "%02x",$_} @SData;
  $value = hex($value);
  Log $ll, "$name/JME-PARSE: $NodeID - $SType - " . join(" " , @SData) . " -> " . $value;
 
  
  my $TicksPerUnit = 0.1;
  if(defined($attr{$name}{TicksPerUnit})){
	$TicksPerUnit = $attr{$name}{TicksPerUnit};
  }
  
  my $counter = 0;
  if(defined($defs{$name}{READINGS}{counter})){
	$counter = $defs{$name}{READINGS}{counter}{VAL};
  }

  # Counter Reset at 100 to 0
  if($counter > 100) {
	$readings{counter} = 0;
  }
  else {$readings{counter} = $value;}
  
  my ($current,$cnt_delta);
  $cnt_delta = $value - $counter;

  $current = sprintf("%0.3f", ($cnt_delta * $TicksPerUnit));
  $readings{current} = $current;
  
   
  # Update only on Changes
  my ($MeterNow,$consumption,$MeterBase);
  $MeterNow = $defs{$name}{READINGS}{MeterNow}{VAL};
  if($current > 0 ){
	$MeterBase = $defs{$name}{READINGS}{MeterBase}{VAL};
	$readings{MeterNow} = sprintf("%0.3f", ($MeterNow + $current));
	$consumption = ($MeterNow + $current) - $MeterBase;
	$readings{consumption} = sprintf("%0.3f", $consumption);
  }
  #-----------------------------------------------------------------------------
  # Caculate AVG Day and Month
  #-----------------------------------------------------------------------------
  my $tsecs= time(); 
  my $d_now = (localtime($tsecs))[3];
  my $m_now = (localtime($tsecs))[4] + 1;
  # avg_data_day = Day | Day_MeterNow
	# avg_data_month = Month | Month_MeterNow
  my ($d, $d_mn,$m,$m_mn);
  if(defined($attr{$name}{avg_data_day})){
		($d, $d_mn) = split(/\|/,$attr{$name}{avg_data_day});
		($m,$m_mn) = split(/\|/,$attr{$name}{avg_data_month});
  }
  else {
		# INIT
		$defs{$name}{READINGS}{avg_day}{VAL} = 0.000;
		$defs{$name}{READINGS}{avg_day}{TIME} = TimeNow();
		$defs{$name}{READINGS}{avg_month}{VAL} = 0.000;
		$defs{$name}{READINGS}{avg_month}{TIME} = TimeNow();
		$attr{$name}{avg_data_day} = "$d_now|$MeterNow";
		$attr{$name}{avg_data_month} = "$m_now|$MeterNow";
		($d, $d_mn) = split(/\|/,$attr{$name}{avg_data_day});
		($m,$m_mn) = split(/\|/,$attr{$name}{avg_data_month});
  }
  Log $ll, "$name/JME-PARSE: D:NOW:$d_now/OLD:$d M:NOW:$m_now/OLD:$m";
  # AVG DAY
  if($d_now ne $d) {
	$consumption = ($MeterNow - $d_mn) + $defs{$name}{READINGS}{avg_day}{VAL} ;
	$consumption = $consumption / 2;
	$readings{avg_day} = sprintf("%0.3f", $consumption);
	$attr{$name}{avg_data_day} = "$d_now|$MeterNow";
  }
  # AVG Month
  if($m_now ne $m) {
	$consumption = ($MeterNow - $d_mn) + $defs{$name}{READINGS}{avg_month}{VAL} ;
	$consumption = $consumption / 2;
	$readings{avg_month} = sprintf("%0.3f", $consumption);
	$attr{$name}{avg_data_month} = "$m_now|$MeterNow";
  }
  #-----------------------------------------------------------------------------
  # Readings
  my $i = 0;
  foreach my $r (sort keys %readings) {
	Log 4, "JME $name $r:" . $readings{$r};
	$defs{$name}{READINGS}{$r}{VAL} = $readings{$r};
	$defs{$name}{READINGS}{$r}{TIME} = TimeNow();
	# Changed for Notify and Logs
	$defs{$name}{CHANGED}[$i] = $r . ": " . $readings{$r};
	$i++;
  }
  $defs{$name}{STATE} = "M:" . $defs{$name}{READINGS}{MeterNow}{VAL} . " C:$value";
  
  return $name;
}
################################################################################
1;

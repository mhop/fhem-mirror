##############################################################################
# $Id$
# 97_PiXtendV2.pm
#
# Modul to control PiXtendV2
#
# define <name> PiXtendV2 <optional>
#
##############################################################################
#
# This file is part of the PiXtend(R) Project.
#
# For more information about PiXtendV2(R) and this program,
# see <http://www.PiXtend.de> or <http://www.PiXtend.com>
#
# Copyright (C) 2014-2017 Tobias Sperling
# Qube Solutions UG (haftungsbeschränkt), Arbachtalstr. 6
# 72800 Eningen, Germany
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday usleep);

my $modul_ver = "1.00";

my @PiXtendV2S_Set = (
	"_JumperSettingAI0:10V,5V",
	"_JumperSettingAI1:10V,5V",
	"_GPIO0Ctrl:input,output,DHT11,DHT22",
	"_GPIO1Ctrl:input,output,DHT11,DHT22",
	"_GPIO2Ctrl:input,output,DHT11,DHT22",
	"_GPIO3Ctrl:input,output,DHT11,DHT22",
	"_GPIOPullupsEnable:no,yes",
	"_WatchdogEnable:disabled,125ms,1s,8s",
	"_StateLEDDisable:no,yes",
	"Reset:noArg",
	"SafeState:noArg",
	"RetainCopy:off,on",
	"RetainEnable:off,on",
	"DigitalDebounce01:textField",
	"DigitalDebounce23:textField",
	"DigitalDebounce45:textField",
	"DigitalDebounce67:textField",
	"DigitalOut0:on,off,toggle",
	"DigitalOut1:on,off,toggle",
	"DigitalOut2:on,off,toggle",
	"DigitalOut3:on,off,toggle",
	"RelayOut0:on,off,toggle",
	"RelayOut1:on,off,toggle",
	"RelayOut2:on,off,toggle",
	"RelayOut3:on,off,toggle",
	"GPIOOut0:on,off,toggle",
	"GPIOOut1:on,off,toggle",
	"GPIOOut2:on,off,toggle",
	"GPIOOut3:on,off,toggle",
	"GPIODebounce01:textField",
	"GPIODebounce23:textField",
	"PWM0Ctrl0:textField",
	"PWM0Ctrl1:slider,0,1,65535",
	"PWM0A:slider,0,1,65535",
	"PWM0B:slider,0,1,65535",
	"PWM1Ctrl0:textField",
	"PWM1Ctrl1:slider,0,1,255",
	"PWM1A:slider,0,1,255",
	"PWM1B:slider,0,1,255",
	"AnalogOut0:slider,0.00,0.01,10.00,1",
	"AnalogOut1:slider,0.00,0.01,10.00,1",
	"RetainDataOut:textField"
);
	
my @PiXtendV2S_Get = (
	"Version:noArg",
	"SysState:noArg",
	"UCState:noArg",
	"UCWarnings:noArg",
	"DigitalIn0:noArg",
	"DigitalIn1:noArg",
	"DigitalIn2:noArg",
	"DigitalIn3:noArg",
	"DigitalIn4:noArg",
	"DigitalIn5:noArg",
	"DigitalIn6:noArg",
	"DigitalIn7:noArg",
	"AnalogIn0:noArg",
	"AnalogIn1:noArg",
	"GPIOIn0:noArg",
	"GPIOIn1:noArg",
	"GPIOIn2:noArg",
	"GPIOIn3:noArg",
	"Sensor0:temperature,humidity",
	"Sensor1:temperature,humidity",
	"Sensor2:temperature,humidity",
	"Sensor3:temperature,humidity",
	"RetainDataIn:textField"
);

sub BufferWrite_S($$) {
	my ($buffer, $hash) = @_;
	
	if($hash->{DataOut}{DigitalDebounce01})		{$buffer->[9] = ($hash->{DataOut}{DigitalDebounce01});}
	if($hash->{DataOut}{DigitalDebounce23})		{$buffer->[10] = ($hash->{DataOut}{DigitalDebounce23});}
	if($hash->{DataOut}{DigitalDebounce45})		{$buffer->[11] = ($hash->{DataOut}{DigitalDebounce45});}
	if($hash->{DataOut}{DigitalDebounce67})		{$buffer->[12] = ($hash->{DataOut}{DigitalDebounce67});}
	if($hash->{DataOut}{DigitalOut})			{$buffer->[13] = ($hash->{DataOut}{DigitalOut});}
	if($hash->{DataOut}{RelayOut})				{$buffer->[14] = ($hash->{DataOut}{RelayOut});}
	if($hash->{DataOut}{GPIOCtrl0})				{$buffer->[15] = ($hash->{DataOut}{GPIOCtrl0});}
	if($hash->{DataOut}{GPIOOut})				{$buffer->[16] = ($hash->{DataOut}{GPIOOut});}
	if($hash->{DataOut}{GPIODebounce01})		{$buffer->[17] = ($hash->{DataOut}{GPIODebounce01});}
	if($hash->{DataOut}{GPIODebounce23})		{$buffer->[18] = ($hash->{DataOut}{GPIODebounce23});}
	
	if($hash->{DataOut}{PWMCtrl00})				{$buffer->[19] = ($hash->{DataOut}{PWMCtrl00});}
	if($hash->{DataOut}{PWMCtrl01})				{$buffer->[20] = (($hash->{DataOut}{PWMCtrl01}) & 0xFF);
												 $buffer->[21] = (($hash->{DataOut}{PWMCtrl01}) >> 8);}
	if($hash->{DataOut}{PWM0a})					{$buffer->[22] = (($hash->{DataOut}{PWM0a}) & 0xFF);
												 $buffer->[23] = (($hash->{DataOut}{PWM0a}) >> 8);}
	if($hash->{DataOut}{PWM0b})					{$buffer->[24] = (($hash->{DataOut}{PWM0b}) & 0xFF);
												 $buffer->[25] = (($hash->{DataOut}{PWM0b}) >> 8);}
	
	if($hash->{DataOut}{PWMCtrl10})				{$buffer->[26] = ($hash->{DataOut}{PWMCtrl10});}
	if($hash->{DataOut}{PWMCtrl11})				{$buffer->[27] = (($hash->{DataOut}{PWMCtrl11}) & 0xFF);
												 $buffer->[28] = (($hash->{DataOut}{PWMCtrl11}) >> 8);}
	if($hash->{DataOut}{PWM1a})					{$buffer->[29] = (($hash->{DataOut}{PWM1a}) & 0xFF);
												 $buffer->[30] = (($hash->{DataOut}{PWM1a}) >> 8);}
	if($hash->{DataOut}{PWM1b})					{$buffer->[31] = (($hash->{DataOut}{PWM1b}) & 0xFF);
												 $buffer->[32] = (($hash->{DataOut}{PWM1b}) >> 8);}
	for(my $i=0; $i < ($hash->{RetainSize}); $i++){
		if($hash->{DataOut}{"RetainDataOut".$i})		{$buffer->[33+$i] = ($hash->{DataOut}{"RetainDataOut".$i});}
	}
}

sub BufferRead_S($$) {
	my ($buffer, $hash) = @_;
	my $str;
	
	readingsBeginUpdate($hash);
	
	readingsBulkUpdateIfChanged($hash, "Firmware", $buffer->[0], 0);
	readingsBulkUpdateIfChanged($hash, "Hardware", $buffer->[1], 0);
	readingsBulkUpdateIfChanged($hash, "Model", pack("C",$buffer->[2]), 0);
	readingsBulkUpdateIfChanged($hash, "UCState", $buffer->[3], 1);
	readingsBulkUpdateIfChanged($hash, "UCWarnings", $buffer->[4], 1);
	
	for(my $i=0; $i < 8; $i++){
		if($buffer->[9] & (1<<$i)) { readingsBulkUpdateIfChanged($hash, "DigitalIn$i", "on", 1);}
		else { readingsBulkUpdateIfChanged($hash, "DigitalIn$i", "off", 1);}
	}
	
	$str = sprintf("%.2f", (($buffer->[10] | ($buffer->[11] << 8))*($hash->{DataOut}{JumperAI0})/1024));
	readingsBulkUpdateIfChanged($hash, "AnalogIn0", $str, 1);
	$str = sprintf("%.2f", (($buffer->[12] | ($buffer->[13] << 8))*($hash->{DataOut}{JumperAI1})/1024));
	readingsBulkUpdateIfChanged($hash, "AnalogIn1", $str, 1);
	
	for(my $i=0; $i < 4; $i++){
		if($buffer->[14] & (1<<$i)) { readingsBulkUpdateIfChanged($hash, "GPIOIn$i", "on", 1);}
		else { readingsBulkUpdateIfChanged($hash, "GPIOIn$i", "off", 1);}
	}
	
	for(my $i=0; $i < 4; $i++){
		my $temp = ($buffer->[15+(4*$i)] | ($buffer->[16+(4*$i)] << 8));
		my $humi = ($buffer->[17+(4*$i)] | ($buffer->[18+(4*$i)] << 8));
		if($temp == 65535 && $humi == 65535)
		{
			$temp = "Sensor not connected";
			$humi = $temp;
		}
		else
		{
			if($hash->{DataOut}{"GPIO".$i."DHT"})
			{
				if(($hash->{DataOut}{"GPIO".$i."DHT"}) eq "dht11")
				{
					$temp = sprintf("%.1f", ($temp/256));
					$humi = sprintf("%.1f", ($humi/256));
					
				}
				elsif(($hash->{DataOut}{"GPIO".$i."DHT"}) eq "dht22")
				{
					if($temp & (1<<15))
					{
						$temp &= ~(1<<15);
						$temp /= (-10);
					}
					else
					{
						$temp /= 10;
					}
					$temp = sprintf("%.1f", $temp);
					$humi = sprintf("%.1f", ($humi/10));
				}
			}
			else
			{
				$temp = "Function not enabled";
				$humi = $temp;
			}
		}
		readingsBulkUpdateIfChanged($hash, "Sensor".$i."T", $temp, 1);
		readingsBulkUpdateIfChanged($hash, "Sensor".$i."H", $humi, 1);
	}
	
	$str = "";
	for(my $i=0; $i < ($hash->{RetainSize}); $i++){
		$str .= $buffer->[33+$i]." ";
	}
	readingsBulkUpdateIfChanged($hash, "RetainDataIn", $str, 1);

	readingsEndUpdate($hash, 1);
}

#####################################
sub PiXtendV2_Initialize($) {
    my ($hash) = @_;
 
    $hash->{DefFn}      = 'PiXtendV2_Define';
    $hash->{UndefFn}    = 'PiXtendV2_Undef';
    $hash->{SetFn}      = 'PiXtendV2_Set';
    $hash->{GetFn}      = 'PiXtendV2_Get';
    $hash->{AttrFn}     = 'PiXtendV2_Attr';
 
    $hash->{AttrList} = "PiXtend_GetFormat:text,value PiXtend_Parameter ".$readingFnAttributes;
}

#####################################
sub PiXtendV2_Define($$) {
    my ($hash, $def) = @_;
    my @param = split("[ \t][ \t]*", $def);
	
    if(scalar(@param) < 2 or scalar(@param) > 3)
	{
        return "Wrong syntax: use define <name> PiXtendV2 <optional>";
    }
	
	eval{ require "sys/ioctl.ph" };
	if($@){ return "ioctl.ph is not available but needed"; }
	
	if(scalar(@param) eq 2 or $param[2] eq "S")
	{
		$hash->{Set} = \@PiXtendV2S_Set;
		$hash->{Get} = \@PiXtendV2S_Get;
		$hash->{SPI}{Write} = \&BufferWrite_S;
		$hash->{SPI}{Read} = \&BufferRead_S;
		$hash->{SPI}{Length} = 67;
		$hash->{SPI}{Speed} = 1100000;
		$hash->{SPI}{Dev0} = "/dev/spidev0.0";
		$hash->{SPI}{Dev1} = "/dev/spidev0.1";
		$hash->{SPI}{Enable} = "/sys/class/gpio/";
		$hash->{SPI}{Model} = 83;
		$hash->{RetainSize} = 32;
		
		$hash->{DataOut}{JumperAI0} = 10;
		$hash->{DataOut}{JumperAI1} = 10;
			
	}
	else
	{
		return "Parameter <$param[2]> not supported";
	}
	
	my $ret = undef;
	$ret = Check_Device($hash->{SPI}{Dev0});
	if($ret){ return "$ret"; }
	$ret = Check_Device($hash->{SPI}{Enable}."export");
	if($ret){ return "$ret"; }
	
	$hash->{STATE} = "defined";
	SPI_Transfer($hash);
	
	$attr{$hash->{NAME}}{icon} = 'RPi';
	$attr{$hash->{NAME}}{devStateIcon} = 'defined:rc_YELLOW active:rc_GREEN error:rc_RED';
	
    return undef;
}

#####################################
sub PiXtendV2_Undef($$) {
    my ($hash, $arg) = @_;
	
	RemoveInternalTimer($hash, "SPI_Transfer");
	SPI_Disable($hash);
	UC_Reset($hash);
	
    return undef;
}

#####################################
sub PiXtendV2_Attr ($$$$)
{
	my ( $cmd, $name, $attrName, $attrValue  ) = @_;
	my $hash = $defs{$name};
	
	if($cmd eq "set")
	{
		if($attrName eq "PiXtend_GetFormat")
		{
			if($attrValue eq "text" or $attrValue eq "value")
			{
			}
			else
			{
				return "Unknown value $attrValue for $attrName, choose one of: text, value";
			}
		}
		
		if($attrName eq "PiXtend_Parameter")
		{
			my @coms = split(/ /, $attrValue);
			for(my $i=0; $i < @coms; $i++)
			{
				my @param = split(/:/, $coms[$i]);
				if(index($param[0], "_") != -1)
				{
					my $ret = PiXtendV2_Set($hash, $name, $param[0], $param[1]);
					if(defined($ret))
					{
						return $ret;
					}
				}
				else
				{
					return "Unknown command $param[0]. Only set commands with a leading '_' sign can be used.";
				}
			}
		}
	}
	return undef;
}

#####################################
sub PiXtendV2_Get($$@) {
	my ($hash, $name, $cmd, @param) = @_;
 
 	my @InList = @{$hash->{Get}};
	foreach my $c (@InList)
	{
		if(index($c, ":") != -1)
		{
			$c = substr($c,0,index($c,":"));
		}
		$c = lc($c);
	}
	$cmd = lc($cmd);
	if(grep($_ eq $cmd, @InList) > 0)
	{
		my $str = undef;
		my $val = undef;
		
		#Version
		if($cmd eq "version")
		{
			$val = ReadingsVal($name, "Model", "?")."-".ReadingsVal($name, "Hardware", "?")."-".ReadingsVal($name, "Firmware", "?");
			$str = "FHEM-Modul-Version [$modul_ver], PiXtend-Version [$val]";
		}
		
		#SysState
		elsif($cmd eq "sysstate")
		{
			$val = $hash->{STATE};
			$str = "System state is [$val]";
		}
		
		#UCState
		elsif($cmd eq "ucstate")
		{
			$val = ReadingsVal($name, "UCState", "?");
			$str = "Microcontroller state is [$val]";
		}
		
		#UCWarnings
		elsif($cmd eq "ucwarnings")
		{
			$val = ReadingsVal($name, "UCWarnings", "?");
			$str = "Microcontroller warnings are [$val]";
		}
		
		#DigitalIn
		elsif(index($cmd, "digitalin") != -1)
		{
			$cmd =~ s/digitalin//;
			$val = ReadingsVal($name, "DigitalIn$cmd", undef);
			if(defined($val))
			{
				$str = "DigitalIn$cmd is [$val]";
			}
		}
		
		#AnalogIn
		elsif(index($cmd, "analogin") != -1)
		{
			$cmd =~ s/analogin//;
			$val = ReadingsVal($name, "AnalogIn$cmd", undef);
			if(defined($val))
			{
				$str = "AnalogIn$cmd is [$val] V";
			}
		}
		
		#GPIOIn
		elsif(index($cmd, "gpioin") != -1)
		{
			$cmd =~ s/gpioin//;
			$val = ReadingsVal($name, "GPIOIn$cmd", undef);
			if(defined($val))
			{
				$str = "GPIOIn$cmd is [$val]";
			}
		}
		
		#DHTs
		elsif(index($cmd, "sensor") != -1)
		{
			$cmd =~ s/sensor//;
			
			if(lc($param[0]) eq "temperature")
			{
				$val = ReadingsVal($name, "Sensor".$cmd."T", undef);
				if(defined($val) && index($val, "not") == -1)
				{
					$str = "For Sensor$cmd temperature is [$val] &deg;C";
				}
				elsif(index($val, "not") != -1)
				{
					$str = "$val for Sensor$cmd";
				}
			}
			elsif(lc($param[0]) eq "humidity")
			{
				$val = ReadingsVal($name, "Sensor".$cmd."H", undef);
				if(defined($val) && index($val, "not") == -1)
				{
					$str = "For Sensor$cmd humidity is [$val] %";
				}
				elsif(index($val, "not") != -1)
				{
					$str = "$val for Sensor$cmd";
				}
			}
			else
			{
				$val = "Unknown value $param[0] for Sensorx, choose one of: temperature, humidity";
				$str = $val;
			}
		}
		
		#Retain
		elsif($cmd eq "retaindatain")
		{
			$str = ReadingsVal($name, "RetainDataIn", undef);
			if(defined($str))
			{
				if(int($param[0]) >= 0 && int($param[0]) < ($hash->{RetainSize}))
				{	
					my @vals = split(/ /, $str);
					$val = $vals[$param[0]];
					$str = "Value for RetainDataIn$param[0] is [$val]";
				}
				else
				{
					$val = "Unknown Index $param[0] for RetainDataIn, index must be between 0 and ($hash->{RetainSize}-1)";
					$str = $val;
				}
			}
		}
		
		if (defined($str) && defined($val))
		{
			if(AttrVal($name, "PiXtend_GetFormat", "?") eq "value")
			{
				return $val;
			}
			else
			{
				return $str;
			}
		}
	}
	else
	{
		return "Unknown argument $cmd, choose one of ". join(" ", @{$hash->{Get}});
	}
	return undef;
}

#####################################
sub PiXtendV2_Set($$@){
	my ($hash, $name, $cmd, @param) = @_;
	
	my @outList = @{$hash->{Set}};
	foreach my $c (@outList)
	{
		if(index($c, ":") != -1)
		{
			$c = substr($c,0,index($c,":"));
		}
		$c = lc($c);
	}
	$cmd = lc($cmd);
	
	if(grep($_ eq $cmd, @outList) > 0)
	{
		#Reset
		if(index($cmd, "reset") != -1)
		{
			UC_Reset($hash);
		}
		
		elsif(index($cmd, "_jumpersettingai") != -1)
		{
			$cmd =~ s/_jumpersettingai//;
			if(lc($param[0]) eq "10v")
			{
				($hash->{DataOut}{"JumperAI".$cmd}) = 10;
			}
			elsif(lc($param[0]) eq "5v")
			{
				($hash->{DataOut}{"JumperAI".$cmd}) = 5;
			}
			else
			{
				return "Unknown value $param[0] for JumperSetting, choose one of: 10V, 5V";
			}
		}
		
		elsif(index($cmd, "_gpio") != -1 and index($cmd, "ctrl") != -1)
		{
			$cmd =~ s/_gpio//;
			$cmd =~ s/ctrl//;
			my $no = 0;
			if($cmd < 4){$no = 0;}
			elsif($cmd < 8){$no = 1; $cmd -= 4;}
			else{ return "Unknown number for GPIOxCtrl";}
			
			if(lc($param[0]) eq "input")
			{
				($hash->{DataOut}{"GPIOCtrl".$no}) &= ~ (1<<($cmd+4));
				($hash->{DataOut}{"GPIOCtrl".$no}) &= ~(1<<$cmd);
				($hash->{DataOut}{"GPIO".($no*4+$cmd)."DHT"}) = undef;
			}
			elsif(lc($param[0]) eq "output")
			{
				($hash->{DataOut}{"GPIOCtrl".$no}) &= ~ (1<<($cmd+4));
				($hash->{DataOut}{"GPIOCtrl".$no}) |= (1<<$cmd);
				($hash->{DataOut}{"GPIO".($no*4+$cmd)."DHT"}) = undef;
			}
			elsif(lc($param[0]) eq "dht11" or lc($param[0]) eq "dht22")
			{
				($hash->{DataOut}{"GPIOCtrl".$no}) |= (1<<($cmd+4));
				($hash->{DataOut}{"GPIO".($no*4+$cmd)."DHT"}) = lc($param[0]);
			}
			else
			{
				return "Unknown value $param[0] for GPIOxCtrl, choose one of: input, output, DHT11, DHT22";
			}
		}
		
		elsif(index($cmd, "_gpiopullupsenable") != -1)
		{
			if(lc($param[0]) eq "no")
			{
				($hash->{DataOut}{UCCtrl1}) &= ~(1<<4);
			}
			elsif(lc($param[0]) eq "yes")
			{
				($hash->{DataOut}{UCCtrl1}) |= (1<<4);
			}
			else
			{
				return "Unknown value $param[0] for GPIOPullupsEnable, choose one of: no, yes";
			}
		}
		
		elsif(index($cmd, "_watchdogenable") != -1)
		{
			if(lc($param[0]) eq "disabled")
			{
				($hash->{DataOut}{UCCtrl0}) = (($hash->{DataOut}{UCCtrl0}) & 0xF0) | 0;
			}
			elsif(lc($param[0]) eq "125ms")
			{
				($hash->{DataOut}{UCCtrl0}) = (($hash->{DataOut}{UCCtrl0}) & 0xF0) | 4;
			}
			elsif(lc($param[0]) eq "1s")
			{
				($hash->{DataOut}{UCCtrl0}) = (($hash->{DataOut}{UCCtrl0}) & 0xF0) | 7;
			}
			elsif(lc($param[0]) eq "8s")
			{
				($hash->{DataOut}{UCCtrl0}) = (($hash->{DataOut}{UCCtrl0}) & 0xF0) | 10;
			}
			else
			{
				return "Unknown value $param[0] for WatchdogEnable, choose one of: disabled, 125ms, 1s, 8s";
			}
		}
		
		elsif(index($cmd, "_stateleddisable") != -1)
		{
			if(lc($param[0]) eq "no")
			{
				($hash->{DataOut}{UCCtrl1}) &= ~(1<<3);
			}
			elsif(lc($param[0]) eq "yes")
			{
				($hash->{DataOut}{UCCtrl1}) |= (1<<3);
			}
			else
			{
				return "Unknown value $param[0] for StateLEDDisable, choose one of: no, yes";
			}
		}
		
		elsif(index($cmd, "safestate") != -1)
		{
			($hash->{DataOut}{UCCtrl1}) |= (1<<0);
		}
		
		elsif(index($cmd, "retaincopy") != -1)
		{
			if(lc($param[0]) eq "off")
			{
				($hash->{DataOut}{UCCtrl1}) &= ~(1<<1);
			}
			elsif(lc($param[0]) eq "on")
			{
				($hash->{DataOut}{UCCtrl1}) |= (1<<1);
			}
			else
			{
				return "Unknown value $param[0] for RetainCopy, choose one of: off, on";
			}
		}
		
		elsif(index($cmd, "retainenable") != -1)
		{
			if(lc($param[0]) eq "off")
			{
				($hash->{DataOut}{UCCtrl1}) &= ~(1<<2);
			}
			elsif(lc($param[0]) eq "on")
			{
				($hash->{DataOut}{UCCtrl1}) |= (1<<2);
			}
			else
			{
				return "Unknown value $param[0] for RetainEnable, choose one of: off, on";
			}
		}

		###############
		#RelayOut
		elsif(index($cmd, "relayout") != -1)
		{
			$cmd =~ s/relayout//;
			if(lc($param[0]) eq "off")
			{
				($hash->{DataOut}{RelayOut}) &= ~(1<<$cmd);
			}
			elsif(lc($param[0]) eq "on")
			{
				($hash->{DataOut}{RelayOut}) |= (1<<$cmd);
			}
			elsif(lc($param[0]) eq "toggle")
			{
				($hash->{DataOut}{RelayOut}) ^= (1<<$cmd);
			}
			else
			{
				return "Unknown value $param[0] for RelayOut, choose one of: on, off, toggle";
			}
		}
		
		#DigitalOut
		elsif(index($cmd, "digitalout") != -1)
		{
			$cmd =~ s/digitalout//;
			if(lc($param[0]) eq "off")
			{
				($hash->{DataOut}{DigitalOut}) &= ~(1<<$cmd);
			}
			elsif(lc($param[0]) eq "on")
			{
				($hash->{DataOut}{DigitalOut}) |= (1<<$cmd);
			}
			elsif(lc($param[0]) eq "toggle")
			{
				($hash->{DataOut}{DigitalOut}) ^= (1<<$cmd);
			}
			else
			{
				return "Unknown value $param[0] for DigitalOutput, choose one of: on, off, toggle";
			}
		}
		
		#DigitalDebounce
		elsif(index($cmd, "digitaldebounce") != -1)
		{
			$cmd =~ s/digitaldebounce//;
			$hash->{DataOut}{"DigitalDebounce".$cmd} = Check_Range(0,255,$param[0]);
		}
		
		#GPIODebounce
		elsif(index($cmd, "gpiodebounce") != -1)
		{
			$cmd =~ s/gpiodebounce//;
			$hash->{DataOut}{"GPIODebounce".$cmd} = Check_Range(0,255,$param[0]);
		}
		
		#GPIOOut
		elsif(index($cmd, "gpioout") != -1)
		{
			$cmd =~ s/gpioout//;
			if(lc($param[0]) eq "off")
			{
				($hash->{DataOut}{GPIOOut}) &= ~(1<<$cmd);
			}
			elsif(lc($param[0]) eq "on")
			{
				($hash->{DataOut}{GPIOOut}) |= (1<<$cmd);
			}
			elsif(lc($param[0]) eq "toggle")
			{
				($hash->{DataOut}{GPIOOut}) ^= (1<<$cmd);
			}
			else
			{
				return "Unknown value $param[0] for GPIOOut, choose one of: on, off, toggle";
			}
		}
		
		#AnalogOut
		elsif(index($cmd, "analogout") != -1)
		{
			$cmd =~ s/analogout//;
			if(index($param[0], ".") != -1)
			{
				if($param[0] >= 0.00 && $param[0] <= 10.00)
				{
					DAC_Transfer($hash, ($param[0]*1023/10), $cmd);
				}
				else
				{
					return "Unknown value $param[0] for AnalogOut, choose a voltage between 0.00 and 10.00";
				}
			}
			else
			{
				if(int($param[0]) >= 0 && int($param[0]) <= 1023)
				{
					DAC_Transfer($hash, $param[0], $cmd);
				}
				else
				{
					return "Unknown value $param[0] for AnalogOut, choose a number between 0 and 1023";
				}
			}
		}
		
		#PWM
		elsif(index($cmd, "pwm") != -1)
		{
			$cmd =~ s/pwm//;
			if(index($cmd, "ctrl") != -1)
			{
				$cmd =~ s/ctrl//;
				$hash->{DataOut}{"PWMCtrl".$cmd} = Check_Range(0,65535,$param[0]);
			}
			elsif(index($cmd, "a") != -1 or index($cmd, "b") != -1)
			{
				$hash->{DataOut}{"PWM".$cmd} = Check_Range(0,65535,$param[0]);
			}
			else
			{
				return "Unknown command for PWM";
			}
		}
		
		#Retain
		elsif(index($cmd, "retaindataout") != -1)
		{
			if(@param == 2)
			{
				if(int($param[0]) < ($hash->{RetainSize}))
				{
					if(int($param[1]) >= 0 && int($param[1]) <= 255)
					{
						$hash->{DataOut}{"RetainDataOut".$param[0]} = $param[1];
					}
					else
					{
						return "Unknown value $param[1] for RetainDataOut, choose a number between 0 and 255";
					}
				}
				else
				{
					return "Unknown Index $param[0] for RetainDataOut, index must be between 0 and ($hash->{RetainSize}-1)";
				}
			}
			else
			{
				return "Too few parameters for RetainDataOut, 2 are expected";
			}
		}
	}
	else
	{
		return "Unknown argument $cmd, choose one of ". join(" ", @{$hash->{Set}});
	}
	return undef;
}


#####################################
sub Check_Range ($$$) {
	my ($min, $max, $val) = @_;
	if($val < $min){return $min;}
	if($val > $max){return $max;}
	else{return $val;}
}

#####################################
sub Check_Device ($) {
	my ($dev) = @_;
		my $ret = undef;
	if(-e $dev) {
		if(-r $dev) {
			unless(-w $dev) {
				$ret = ': Error! Device not writable: '.$dev . '. Please change access rights for fhem user (sudo adduser fhem gpio; sudo adduser fhem spi; sudo reboot).'; 
			}
		} else {
			$ret = ': Error! Device not readable: '.$dev . '. Please change access rights for fhem user (sudo adduser fhem gpio; sudo adduser fhem spi; sudo reboot).'; 
		}
	} else {
		$ret = ': Error! Device not found: '   .$dev . '. Please change access rights for fhem user (sudo adduser fhem gpio; sudo adduser fhem spi; sudo reboot) or check if kernelmodules must be loaded.'; 
	}
	return $ret;
}

#####################################
sub SPI_GetIOCMD ($) {
	my $arg = (1 << 30);
	$arg |= (($_[0]*32) << 16);
	$arg |= (107 << 8);
	return $arg;
}

#####################################
sub calc_crc16($$$){
	my ($beg, $end, $buff) = @_;	
	my $crc = 0xFFFF;
	for(my $i=$beg; $i <= $end; $i++){
		$crc ^= $$buff[$i];
		for(my $k=0; $k < 8; ++$k)
		{
			if($crc & 1)
			{
				$crc = ($crc >> 1) ^ 0xA001;
			}
			else
			{
				$crc = ($crc >> 1);
			}
		}
	}
	return $crc;
}

#####################################
sub DAC_Transfer ($) {
	my ($hash, $val, $chn) = @_;
	$val = ($val<<2);
	$val |= (1<<12);
	$val |= ($chn<<15);
	$val = pack("n", $val);
	my $freq = $hash->{SPI}{Speed};
	$freq = pack("L", $freq);
	my $device = $hash->{SPI}{Dev1};
	my $handler = undef;
	my $ret = sysopen($handler, $device, O_RDWR);
	if($ret == 1){
		ioctl($handler, 0x40046b04, $freq);
		syswrite($handler, $val);
		close($handler);
		return undef;
	}
	else
	{
		return "error";
	}
}

#####################################
sub SPI_Transfer ($) {
	my ($hash) = @_;
	my $len = $hash->{SPI}{Length};
	my $freq = $hash->{SPI}{Speed};
	my $device = $hash->{SPI}{Dev0};
	my $handler = undef;
	my $ret = sysopen($handler, $device, O_RDWR);
	if($ret == 1){
		SPI_Enable($hash);
		my @buffer = (0) x $len;
		$buffer[0] = ($hash->{SPI}{Model});
		if($hash->{DataOut}{UCCtrl0}){$buffer[2] = ($hash->{DataOut}{UCCtrl0});}
		if($hash->{DataOut}{UCCtrl1}){$buffer[3] = ($hash->{DataOut}{UCCtrl1});}
		($buffer[7], $buffer[8]) = unpack("C*", pack("S", calc_crc16(0,6, \@buffer)));

		$hash->{SPI}{Write}->(\@buffer, $hash);
		($buffer[$len-2], $buffer[$len-1]) = unpack("C*", pack("S", calc_crc16(9,($len-3), \@buffer)));
		if($hash->{DataOut}{UCCtrl1}){($hash->{DataOut}{UCCtrl1}) &= ~(1<<0);}
		
		my $struct;
		for(my $i=0; $i < $len; $i++){
			$buffer[$i] = pack("Q", $buffer[$i]);
			my $ptr = unpack("L", pack("P", $buffer[$i]));
			if($i == $len-1)
			{
				$struct .= pack("QQLLSCCL", $ptr, $ptr, 1, $freq, 10, 8, 0, 0);
			}
			else
			{
				$struct .= pack("QQLLSCCL", $ptr, $ptr, 1, $freq, 0, 8, 0, 0);
			}
		}
		
		my $iocmd = SPI_GetIOCMD($len);
		ioctl($handler, $iocmd, $struct);
		for(my $i=0; $i < $len; $i++) {$buffer[$i] = unpack("Q", $buffer[$i]);}
		
		if(unpack("S", pack("C2", $buffer[7], $buffer[8])) eq calc_crc16(0,6, \@buffer) and
			unpack("S", pack("C2", $buffer[$len-2], $buffer[$len-1])) eq calc_crc16(9,($len-3), \@buffer))
		{
			if($buffer[2] eq $hash->{SPI}{Model})
			{
				$hash->{SPI}{Read}->(\@buffer, $hash);
				$hash->{STATE} = "active";
				$hash->{ErrorMsg} = "-";
			}
			else
			{
				$hash->{STATE} = "error";
				$hash->{ErrorMsg} = "Wrong model selected";
			}
		}
		else
		{
			$hash->{STATE} = "error";
			$hash->{ErrorMsg} = "SPI-Transfer error";
		}
	}
	else
	{
		$hash->{STATE} = "error";
		$hash->{ErrorMsg} = "Couldn't open SPI device";
	}
	
	InternalTimer(gettimeofday()+0.1, "SPI_Transfer", $hash);
	return undef;
}

#####################################
sub SPI_Enable($){
	my ($hash) = @_;
	my ($handler) = undef;
	my $ret = sysopen($handler, $hash->{SPI}{Enable}."export", O_WRONLY);
	syswrite($handler, 24);
	
	$ret = sysopen($handler, $hash->{SPI}{Enable}."gpio24/direction", O_WRONLY);
	syswrite($handler, "out", 3);
	
	$ret = sysopen($handler, $hash->{SPI}{Enable}."gpio24/value", O_WRONLY);
	syswrite($handler, "1", 1);
	close($handler);
	return 1;
}

#####################################
sub SPI_Disable(){
	my ($hash) = @_;
	my ($handler) = undef;
	my $ret = sysopen($handler, $hash->{SPI}{Enable}."unexport", O_WRONLY);
	syswrite($handler, 24);
	close($handler);
	return 1;
}

#####################################
sub UC_Reset()
{
	my ($hash) = @_;
	my ($handler) = undef;
	my $ret = sysopen($handler, $hash->{SPI}{Enable}."export", O_WRONLY);
	syswrite($handler, 23);
	#close($handler);
	$ret = sysopen($handler, $hash->{SPI}{Enable}."gpio23/direction", O_WRONLY);
	syswrite($handler, "out", 3);
	#close($handler);
	$ret = sysopen($handler, $hash->{SPI}{Enable}."gpio23/value", O_WRONLY);
	syswrite($handler, "1", 1);
	#close($handler);
	usleep(1000);
	$ret = sysopen($handler, $hash->{SPI}{Enable}."gpio23/value", O_WRONLY);
	syswrite($handler, "0", 1);
	close($handler);
	return 1;
}


 
1;

=pod
=item device
=item summary Allows to access the PiXtendV2 (PLC).
=item summary_DE Erm&ouml;glicht den Zugriff auf den PiXtendV2 (SPS)
=begin html

<a name="PiXtendV2"></a>
<h3>PiXtendV2</h3>
<ul>

  PiXtend is a programmable logic controller (PLC) based on the Raspberry Pi.
  This FHEM-module allows to access the functions of the PiXtendV2-Board through the FHEM interface.
  PiXtend offers a variety of digital and analog inputs and outputs which are designed for industry standards
  and safe connections and thus is ideally suited for home automation.
  For more information about PiXtend(R) and this FHEM-module, see
  <a href="http://www.PiXtend.de" target="_blank">www.PiXtend.de</a> or
  <a href="http://www.PiXtend.com" target="_blank">www.PiXtend.com</a>.

  <br><br>


  <a name="PiXtendV2Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PiXtendV2</code>
    <br><br>
    Example:
    <ul>
      <code>define pix PiXtendV2</code><br>
    </ul>
  </ul>
  <br>


  <a name="PiXtendV2Set"></a>
  <b>Set</b>
  <ul>
	Commands to configure the basic settings of the PiXtend start with an "_".<br>
	If a command supports multiple channels the "#"-sign has to be replaced with the channel number.<br>
	All Set-commands are case insensitive to guarantee an easy use.<br>
	For more information see the manuel for PiXtendV2 in the
	<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
	of our homepage.
	<br><br>
	Example:
	<ul>
		<code>set pix relayOut0 on</code><br>
		<code>set pix Relayout0 On</code><br>
		<code>set pix rElAyoUT0 oFf</code><br>
	</ul>
	<br><br>
	
	<li>_GPIO#Ctrl [input,output,DHT11,DHT22]<br>
		With this setting the GPIO can be configured as [input], [output] or as [DHT11] or [DHT22] as well, if a DHT sensor is connected to this GPIO.
		If a DHT is selected and connected, the GPIO can't simultaniously be used as a normal GPIO but the temperatur and humidity is read automatically.
	<br><br></li>
	
	<li>_GPIOPullupsEnable [yes,no]<br>
		This setting enables [yes] or disables [no] the possibility to set the internal pullup resistors via GPIOOut setting for all GPIOs.
	<br><br></li>
	
	<li>_JumperSettingAI# [5V,10V]<br>
		This setting affects the calculation of the voltage on the analog inputs and refers to the actual setting of the physical jumper on the PiXtend-Board [5V,10V].
		The default value is [10V] if no jumper is used.
	<br><br></li>
	
	<li>_StateLEDDisable [yes,no]<br>
		This setting disables [yes] or enables [no] the state LED on the PiXtend. If the LED is disabled it won't light up in case of an error.
	<br><br></li>
	
	<li>_WatchdogEnable [disable,125ms,1s,8s]<br>
		This setting allows to configure the watchdog timer. If the watchdog is configured, the PiXtend will go to safe state if no valid data transfer has
		occured within the selected timeout and thus can't be accessed anymore without a reset.
	<br><br></li>

	<li>AnalogOut# []<br>
		Sets the analog output to the selected voltage. The value can be a voltage between 0 V and 10 V
		or a raw value between 0 and 1023. To set the value to a voltage the value has to include a
		"." even if it is an even number.
		<br><br>
		Example:
		<ul>
			<code>set pix analogout0 2.5</code>    &emsp;&emsp;=> sets analog output 0 to 2.5 V<br>
			<code>set pix analogout0 4.0</code>    &emsp;&emsp;=> sets analog output 0 to 4 V<br>
			<code>set pix analogout0 223</code>    &emsp;&emsp;=> sets analog output 0 to 10*(233/1024) = 1.09 V
		</ul>
	<br><br></li>

	<li>DigitalDebounce# [0-255]<br>
		Allows to debounce the digital inputs. A setting always affects two channels. So DigitalDebounce01 affects DigitalIn0 and DigitalIn1.
		The resulting delay is calculated by (selected value)*(100 ms). The selected value can be any number between 0 and 255.
		Debouncing can be usefull if a switch or button is connected to this input.
		<br><br>
		Example:
		<ul>
			<code>set pix digitaldebounce01 20</code>    &emsp;&emsp;=> debounces DigitalIn0 and DigitalIn1 over (20*100ms) = 2s
		</ul>
	<br><br></li>
	
	<li>DigitalOut# [on,off,toggle]<br>
		Set the digital output HIGH [on] or LOW [off] or [toggle]s it.
	<br><br></li>

	<li>GPIODebounce# [0-255]<br>
		Allows to debounce the GPIO inputs. A setting always affects two channels. So GPIODebounce01 affects GPIOIn0 and GPIOIn1.
		The resulting delay is calculated by (selected value)*(100 ms). The selected value can be any number between 0 and 255.
		Debouncing can be usefull if a switch or button is connected to this input.
		<br><br>
		Example:
		<ul>
			<code>set pix gpiodebounce23 33</code>    &emsp;&emsp;=> debounces GPIOIn2 and GPIOIn3 over (33*100ms) = 3.3s
		</ul>
	<br><br></li>
	
	<li>GPIOOut# [on,off,toggle]<br>
		Set the GPIO to HIGH [on] or LOW [off] or [toggle]s it, if it is configured as an output.
		If it is configured as an input, this command can enable [on] or disable [off] or [toggle] the internal pullup resistor for that GPIO,
		but therefore pullups have to be enabled globally via _GPIOPullupsEnable.
	<br><br></li>

	<li>PWM<br>
		The PiXtendV2 supports various PWM-Modes, which can be configured with this settings.
		For example a servo-mode to control servo-motors, a frequency-mode or a duty-cycle-mode are supported.
		For more information see the manuel for PiXtendV2 in the
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
		of our homepage.
		<br><br>
		PWM#Ctrl0 needs a value between 0 and 255<br>
		PWM#Ctrl1 needs a value between 0 and 65535 (or a value between 0 and 255)<br>
		PWM#A/B needs a value between 0 and 65535 (or a value between 0 and 255)
	<br><br></li>

	<li>RelayOut# [on,off,toggle]<br>
		Set the relay to HIGH [on] or LOW [off] or [toggle]s it.
	<br><br></li>
	
	<li>Reset<br>
		Resets the controller on the PiXtend, for example if it is in safe state and allows to access it again.
	<br><br></li>
	
	<li>RetainCopy [on,off]<br>
		If RetainCopy is enabled [on] the RetainDataOut that is written to the PiXtend will be received in RetainDataIn again.
		This can be usefull in some situations to see which data was send to the PiXtend.
		If it is disabled [off] the last stored data will be received.
	<br><br></li>
	
	<li>RetainDataOut [0-(RetainSize-1)] [0-255]<br>
		The PiXtendV2 supports the storage of retain data. If enabled, this data is stored in case of a power failure or if it is triggered by a watchdog timeout or the safe state command.
		The retain data is organized in bytes and each byte can be written individually with a value between 0 and 255.<br>
		As first parameter the command needs the byte index which is between 0 and the (RetainSize-1). The RetainSize is shown in the "Internals".
		As the second parameter a value is expected which should be stored.
		<br><br>
		Example:
		<ul>
			<code>set pix retaindataout 0 34</code>    	&emsp;&emsp;&emsp;=> stores 34 in retain-data-byte 0<br>
			<code>set pix retaindataout 30 222</code>   &emsp;&emsp;=> stores 222 in retain-data-byte 30
		</ul>
	<br><br></li>
	
	<li>RetainEnable [on,off]<br>
		The function of storing retain data on the PiXtend has to be enabled [on], otherwise no data is stored [off].
		The memory in which the data is stored supports 10.000 write-cycles.
		So the storage of retain data should only be used if it is really necessary.
	<br><br></li>
	
	<li>SafeState<br>
		This setting allows to force the PiXtend to enter the safe state . If retain storage is enabled the data will be stored. In safe state the PiXtend won't communicate with FHEM and can't be configured.
		To restart the PiXtend a reset has to be done.
	<br><br></li>

  </ul>
  <br>


  <a name="PiXtendV2Get"></a>
  <b>Get</b>
  <ul>
	If a command supports multiple channels the "#"-sign has to be replaced with the channel number.<br>
	All Get-commands are case insensitive to guarantee an easy use.<br>
	For more information see the manuel for PiXtendV2 in the
	<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
	of our homepage.
	The values can be returned as a string where the actual value is inside squared brackets or as raw values.
	To change the returned value an attribute has to be set.
	<br><br>
	
	<li>AnalogIn#<br>
		Returns the Value of the selected analog input.
		The result depends on the selected _JumperSettingAI# and the actual physical jumper position on the board.
	<br><br></li>

	<li>DigitalIn#<br>
		Returns the state 1 (HIGH) or 0 (LOW) of the digital input.
	<br><br></li>

	<li>GPIOIn#<br>
		Returns the state 1 (HIGH) or 0 (LOW) of the GPIO, independant of its configuration (input, output, ..).
	<br><br></li>
	
	<li>RetainDataIn [0-(RetainSize-1)]<br>
		Returns the value of the selected RetainDataIn-byte.
	<br><br></li>

	<li>Sensor# [temperature,humidity]<br>
		If a DHT-Sensor is connected to the corresponding GPIO and the _GPIO#Ctrl is set to DHT11 or DHT22 the
		temperature and humidity are measured and can be read.
		<br><br>
		Example:
		<ul>
			<code>set pix _GPIO0Ctrl DHT11</code><br>
			<code>get pix Sensor0 temperature</code>
		</ul>
	<br><br></li>
	
	<li>SysState<br>
		Returns the system state [defined, active, error] of the FHEM module.
	<br><br></li>
	
	<li>UCState<br>
		Returns the state of the PiXtend. If it is 1 everything is fine. If it is greater than 1 an error occured or is present and the PiXtend can't be configured.
		For more information see the manuel for PiXtendV2 in the
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
		of our homepage.
	<br><br></li>

	<li>UCWarnings<br>
		Returns a value that represents the PiXtend warnings.
		For more information see the manuel for PiXtendV2 in the
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
		of our homepage.
	<br><br></li>

	<li>Version<br>
		Returns the FHEM-module version and the microcontroller version [Model-Hardware-Firmware].
	<br><br></li>

  </ul>
  <br>


  <a name="PiXtendV2Readings"></a>
  <b>Readings</b>
  <ul>
	The FHEM-module for PiXtendV2 supports multiple readings from which most of them trigger an event when they have changed.
	The meaning of the readings is similar to the Get-commands.
	<br><br>

    <li>AnalogIn#<br>
		Shows the result of the measurment on the analog inputs in V.
	<br><br></li>

	<li>DigitalIn#<br>
		Shows the state 1 (HIGH) or 0 (LOW) of the digital inputs.
	<br><br></li>
	
	<li>Firmware<br>
		Shows the firmware version.
	<br><br></li>
	
	<li>GPIOIn#<br>
		Shows the state 1 (HIGH) or 0 (LOW) of the GPIOs, independant of their configuration (input, output, ..).
	<br><br></li>
	
	<li>Hardware<br>
		Shows the hardware version.
	<br><br></li>
	
	<li>Model<br>
		Shows the model.
	<br><br></li>
	
	<li>RetainDataIn<br>
		Shows the values of the RetainDataIn.
		The values of RetainDataIn are combined in one row, whereby the most left value represents Byte0 / RetainDataIn0.
		Each value is seperated by an " " and thus can be parsed very easy in perl:
		<br><br>
		Example:
		<ul>
			<code>my ($str) = ReadingsVal(pix, "RetainDataIn", "?")</code><br>
			<code>if($str ne "?"){</code><br>
			&emsp;<code>my @val = split(/ /, $str);</code>		&emsp;&emsp;=> $val[0] contains Byte0, $val[1] Byte1, ...<br>
			&emsp;<code>...</code><br>
			<code>}</code>
		</ul>
	<br><br></li>
	
	<li>Sensor#T/H<br>
		Shows the temperature (T) in &deg;C and the humidity (H) in % of the sensor that is connected to the corresponding GPIO.
	<br><br></li>

	<li>UCState<br>
		Shows the state of the PiXtend. If it is 1 everything is fine. If it is greater than 1 an error occured or is present and the PiXtend can't be configured.
		For more information see the manuel for PiXtendV2 in the
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
		of our homepage.
	<br><br></li>

	<li>UCWarnings<br>
		Shows a value that represents the PiXtend warnings.
		For more information see the manuel for PiXtendV2 in the
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">download section</a>
		of our homepage.
	<br><br></li>

  </ul>
  <br>
 
  <a name="PiXtendV2Attr"></a>
  <b>Attributes</b>
  <ul>
	The attribute name is case-sensitive.
	<br><br>

    <li>PiXtend_GetFormat [text,value]<br>
		Changes the style in which the values of the Get commands are returned. They can be returned as a message [text] or as a raw [value].
		Default is the presentation as a message.
	<br><br></li>

    <li>PiXtend_Parameter<br>
		With this attribute the base configuration (Set commands with a leading "_") can be saved as an attribute.
		Attributes are stored in the config file. Single commands are seperated with a space " " and each value is seperated by a ":".
		<br><br>
		Example:
		<ul>
			<code>attr pix PiXtend_Parameter _gpio0ctrl:dht11 _gpio3ctrl:dht22</code>
		</ul>
	<br><br></li>
  
  </ul>
  <br>
  
</ul>

=end html

=begin html_DE

<a name="PiXtendV2"></a>
<h3>PiXtendV2</h3>
<ul>

  PiXtend ist eine speicherprogrammierbare Steuerung auf Basis des Raspberry Pi.
  Dieses FHEM-Modul erm&ouml;glicht dabei den Zugriff auf die Funktionen des PiXtendV2-Boards in der FHEM-Oberfl&auml;che.
  Der PiXtend bietet dabei eine Vielzahl an digitalen und analogen Ein- und Ausg&auml;ngen, die nach Industrie-Standards ausgelegt sind
  und ist aufgrund der sicheren Anschl&uuml;sse auch ideal f&uuml;r die Hausautomatisierung geeignet.
  F&uuml;r mehr Informationen &uuml;ber PiXtend(R) und das FHEM-Modul besuchen Sie unsere Website 
  <a href="http://www.PiXtend.de" target="_blank">www.PiXtend.de</a> oder
  <a href="http://www.PiXtend.com" target="_blank">www.PiXtend.com</a>.

  <br><br>


  <a name="PiXtendV2Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; PiXtendV2</code>
    <br><br>
    Beispiel:
    <ul>
      <code>define pix PiXtendV2</code><br>
    </ul>
  </ul>
  <br>


  <a name="PiXtendV2Set"></a>
  <b>Set</b>
  <ul>
	Kommandos um die Basiskonfiguration f&uuml;r den PiXtend durchzuf&uuml;hren, beginnen mit einem "_".<br>
	Unterst&uuml;tzt ein Kommando mehrere Kan&auml;le, muss das "#"-Zeichen durch die Kanal-Nummer ersetzt werden.<br>
	Alle Set-Kommandos sind unabh&auml;ngig von der Gro&szlig;-/Kleinschreibung um die einfache Benutzung zu erm&ouml;glichen.<br>
	F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
	<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
	unserer Hompage nach.
	<br><br>
	Beispiel:
	<ul>
		<code>set pix relayOut0 on</code><br>
		<code>set pix Relayout0 On</code><br>
		<code>set pix rElAyoUT0 oFf</code><br>
	</ul>
	<br><br>
	
	<li>_GPIO#Ctrl [input,output,DHT11,DHT22]<br>
		Mit dieser Einstellung kann die Funktion des GPIO eingestellt werden. [input], [output] oder [DHT11] und [DHT22] wenn ein DHT-Sensor an den GPIO angeschlossen ist.
		Wenn ein DHT-Sensor angeschlossen ist und verwendet wird, kann die normale Funktion des GPIO als Eingang/Ausgang nicht gleichzeitig verwendet werden.
	<br><br></li>
	
	<li>_GPIOPullupsEnable [yes,no]<br>
		Diese Einstellung aktiviert [yes] oder deaktiviert [no] f&uuml;r alle GPIOs die M&ouml;glichkeit die internen PullUp-Widerst&auml;nde durch GPIOOut zu setzen.
	<br><br></li>
	
	<li>_JumperSettingAI# [5V,10V]<br>
		Diese Einstellung beeinflusst die Berechnung der Spannung durch die analogen Eing&auml;nge und bezieht sich dabei auf die tats&auml;chliche Position des Jumpers
		auf dem PiXtend-Board [5V,10V]. Wenn kein Jumper verwendet wird, entspricht das der Standardeinstellung von [10V].
	<br><br></li>
	
	<li>_StateLEDDisable [yes,no]<br>
		Diese Einstellung deaktiviert [yes] oder aktiviert [no] die Status-LED auf dem PiXtend. Wenn die LED deaktiviert ist, leuchtet sie im Fehlerfall nicht auf.
	<br><br></li>
	
	<li>_WatchdogEnable [disable,125ms,1s,8s]<br>
		Diese Einstellung erm&ouml;glicht die Konfiguration des Watchdog-Timers. Wenn der Watchdog konfiguriert ist, geht der PiXtend in den Sicheren Zustand
		&uuml;ber, falls innerhalb der eingestellten Zeit keine g&uuml;ltige &Uuml;bertragung zwischen PiXtend und Raspberry Pi stattgefunden hat.
		Im Sicheren Zustand kann der PiXtend erst wieder angesprochen werden, nachdem ein Reset des PiXtend durchgef&uuml;hrt wurde.
	<br><br></li>

	<li>AnalogOut# []<br>
		Stellt am analogen Ausgang eine Spannung ein. Der &uuml;bergebene Wert kann eine Spannung zwischen 0 V und 10 V
		oder ein Rohwert zwischen 0 und 1023 sein. Um den Wert als Spannung zu &uuml;bergeben, muss der Wert ein "." enthalten,
		auch wenn der Wert ganzzahlig ist.
		<br><br>
		Beispiel:
		<ul>
			<code>set pix analogout0 2.5</code>    &emsp;&emsp;=> Setzt den analogen Ausgang 0 auf 2,5 V<br>
			<code>set pix analogout0 4.0</code>    &emsp;&emsp;=> Setzt den analogen Ausgang 0 auf 4 V<br>
			<code>set pix analogout0 223</code>    &emsp;&emsp;=> Setzt den analogen Ausgang 0 auf 10*(233/1024) = 1,09 V
		</ul>
	<br><br></li>
	
	<li>DigitalDebounce# [0-255]<br>
		Erm&ouml;glicht das Entprellen der digitalen Eing&auml;nge. Die Einstellung beeinflusst dabei immer zwei Kan&auml;le.
		DigitalDebounce01 beeinflusst somit DigitalIn0 und DigitalIn1.
		Die resultierende Verz&ouml;gerung berechnet sich dabei durch (eingestellten Wert)*(100 ms).
		Der &uuml;bergebene Wert kann eine beliebige Zahl zwischen 0 und 255 sein.
		Entprellen kann sinnvoll sein, falls an den Eing&auml;ngen Schalter oder Taster angeschlossen sind.
		<br><br>
		Beispiel:
		<ul>
			<code>set pix digitaldebounce01 20</code>    &emsp;&emsp;=> entprellt DigitalIn0 und DigitalIn1 &uuml;ber (20*100ms) = 2s
		</ul>
	<br><br></li>
	
	<li>DigitalOut# [on,off,toggle]<br>
		Setzt den digitalen Ausgang auf HIGH [on] oder LOW [off] oder [toggle]t ihn.
	<br><br></li>

	<li>GPIODebounce# [0-255]<br>
		Erm&ouml;glicht das Entprellen der GPIO Eing&auml;nge. Die Einstellung beeinflusst dabei immer zwei Kan&auml;le.
		GPIODebounce01 beeinflusst somit GPIOIn0 und GPIOIn1.
		Die resultierende Verz&ouml;gerung berechnet sich dabei durch (eingestellten Wert)*(100 ms).
		Der &uuml;bergebene Wert kann eine beliebige Zahl zwischen 0 und 255 sein.
		Entprellen kann sinnvoll sein, falls an den Eing&auml;ngen Schalter oder Taster angeschlossen sind.
		<br><br>
		Beispiel:
		<ul>
			<code>set pix gpiodebounce23 33</code>    &emsp;&emsp;=> entprellt GPIOIn2 und GPIOIn3 &uuml;ber (33*100ms) = 3,3s
		</ul>
	<br><br></li>
	
	<li>GPIOOut# [on,off,toggle]<br>
		Setzt den GPIO auf HIGH [on] oder LOW [off] oder [toggle]t ihn, falls er als Ausgang konfiguriert ist.
		Wenn der GPIO als Eingang konfiguriert ist, kann mit diesem Kommando der interne PullUp-Widerstand aktiviert [on], deaktiviert [off] oder
		ge[toggle]t werden. Dazu muss die M&ouml;glichkeit allerdings global durch _GPIOPullupsEnable aktiviert werden.
	<br><br></li>

	<li>PWM<br>
		PiXtendV2 unterst&uuml;tzt mehrere PWM-Modi, die mit diesen Einstellungen konfiguriert werden k&ouml;nnen.
		Zum Beispiel wird ein Servo-Mode um Modellbau-Servomotoren anzusteuern, ein Frequency-Mode oder ein Duty-Cycle-Mode unterst&uuml;zt.
		F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
		unserer Hompage nach.
		<br><br>
		PWM#Ctrl0 ben&ouml;tigt einen Wert zwischen 0 und 255<br>
		PWM#Ctrl1 ben&ouml;tigt einen Wert zwischen 0 und 65535 (oder einen Wert zwischen 0 und 255)<br>
		PWM#A/B ben&ouml;tigt einen Wert zwischen 0 und 65535 (oder einen Wert zwischen 0 und 255)
	<br><br></li>

	<li>RelayOut# [on,off,toggle]<br>
		Setzt das Relay auf HIGH [on] oder LOW [off] oder [toggle]t es.
	<br><br></li>
	
	<li>Reset<br>
		Setzt den Controller auf dem PiXtend zur&uuml;ck, z.B. wenn er sich im Sicheren Zustand befindet, um ihn erneut konfigurieren zu k&ouml;nnen.
	<br><br></li>
	
	<li>RetainCopy [on,off]<br>
		Wenn RetainCopy aktiviert [on] ist, werden die geschriebenen Daten RetainDataOut vom PiXtend in RetainDataIn zur&uuml;ckgegeben.
		Die Aktivierung kann in Situationen sinnvoll sein, wenn &uuml;berpr&uuml;ft werden soll, welche Daten an den PiXtend geschickt wurden.
		Ist die Funktion deaktiviert [off] werden die zuletzt gespeicherten Daten in RetainDataIn zur&uuml;ckgegeben.
	<br><br></li>
	
	<li>RetainDataOut [0-(RetainSize-1)] [0-255]<br>
		Der PiXtendV2 unterst&uuml;zt die Speicherung remanenter/persistenter Daten - auch Retain genannt. Diese Daten werden im Falle
		einer Betribsspannungsunterbrechung, beim Ausl&ouml;sen des Watchdog-Timers oder beim Entritt in den Sicheren Zustand gespeichert,
		sofern diese Funktion aktiviert wurde. Die Retain-Daten sind dabei in Bytes organisiert, wobei jedes Byte
		individuell mit einem Wert zwischen 0 und 255 beschrieben werden kann.<br>
		Als ersten Parameter erwartet das Kommando den Index des Bytes, der zwischen 0 und (RetainSize-1) liegt. RetainSize ist in den "Internals" zu finden.
		Als zweiter Parameter wird der Wert erwartet, der gespeichert werden soll.
		<br><br>
		Beispiel:
		<ul>
			<code>set pix retaindataout 0 34</code>    	&emsp;&emsp;&emsp;=> speichert 34 in Retain-Data-Byte 0<br>
			<code>set pix retaindataout 30 222</code>   &emsp;&emsp;=> speichert 222 in Retain-Data-Byte 30
		</ul>
	<br><br></li>
	
	<li>RetainEnable [on,off]<br>
		Die Funktion um Retain-Daten auf dem PiXtend zu speichern muss erst aktiviert [on] werden. Andernfalls [off] werden keine Daten gespeichert.
		Es ist zu beachten, dass f&uuml;r den Retain-Speicherbereich 10.000 Schreibzyklen unterst&uuml;tzt werden. Dementsprechend
		sollte die Funktion nur aktiviert werden, wenn sie tats&auml;chlich ben&ouml;tigt wird.
	<br><br></li>
	
	<li>SafeState<br>
		Mit dieser Einstellung kann der PiXtend in den Sicheren Zustand versetzt werden. Wenn die Retain-Speicherung aktiviert ist, werden die Daten gesichert.
		Im Sicheren Zustand kommuniziert der PiXtend nicht mehr mit FHEM. Um den PiXtend neuzustarten muss ein Reset durchgef&uuml;hrt werden.
	<br><br></li>

  </ul>
  <br>


  <a name="PiXtendV2Get"></a>
  <b>Get</b>
  <ul>
	Unterst&uuml;tzt ein Kommando mehrere Kan&auml;le, muss das "#"-Zeichen durch die Kanal-Nummer ersetzt werden.<br>
	Alle Get-Kommandos sind unabh&auml;ngig von der Gro&szlig;-/Kleinschreibung um die einfache Benutzung zu erm&ouml;glichen.<br>
	F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
	<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
	unserer Hompage nach.<br>
	Die Werte k&ouml;nnen als Text, wobei die Werte in eckigen Klammern stehen oder als rohe Werte zur&uuml;ckgegeben werden.
	Die Einstellung f&uuml;r das Format ist in den Attributen zu finden.
	<br><br>
	
	<li>AnalogIn#<br>
		Gibt den Wert des ausgew&auml;hlten analogen Eingangs zur&uuml;ck.
		Der Wert h&auml;ngt dabei von der Einstellung _JumperSettingAI# und der tats&auml;chlichen Jumper-Position auf dem Board ab.
	<br><br></li>

	<li>DigitalIn#<br>
		Gibt den Status 1 (HIGH) oder 0 (LOW) des digitalen Eingangs zur&uuml;ck.
	<br><br></li>

	<li>GPIOIn#<br>
		Gibt den Status 1 (HIGH) oder 0 (LOW) des GPIOs zur&uuml;ck, unabh&auml;ngig von der Konfiguration (input, output, ..).
	<br><br></li>
	
	<li>RetainDataIn [0-(RetainSize-1)]<br>
		Gibt den Wert des ausgew&auml;hlten RetainDataIn-Bytes zur&uuml;ck.
	<br><br></li>

	<li>Sensor# [temperature,humidity]<br>
		Wenn ein DHT-Sensor an den entsprechenden GPIO angeschlossen ist und _GPIO#Ctrl auf DHT11 oder DHT22 gesetzt ist
		wird die Temperatur und Luftfeuchtigkeit gemessen und kann ausgelesen werden.
		<br><br>
		Beispiel:
		<ul>
			<code>set pix _GPIO0Ctrl DHT11</code><br>
			<code>get pix Sensor0 temperature</code>
		</ul>
	<br><br></li>
	
	<li>SysState<br>
		Gibt den Systemstatus [defined, active, error] des FHEM-Moduls zur&uuml;ck.
	<br><br></li>

	<li>UCState<br>
		Gibt den Status des PiXtend zur&uuml;ck. Ist der Status 1, ist alles in Ordnung. Ist der Status allerdings gr&ouml;&szlig;er als 1 ist ein Fehler aufgetreten
		oder steht noch an. In diesem Fall kann der PiXtend nicht konfiguriert werden.
		F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
		unserer Hompage nach.
	<br><br></li>

	<li>UCWarnings<br>
		Der zur&uuml;ckgegebene Wert repr&auml;sentiert die Warnungen des PiXtendV2.
		F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
		unserer Hompage nach.
	<br><br></li>

	<li>Version<br>
		Gibt die Version des FHEM-Moduls sowie die PiXtend-Version [Model-Hardware-Firmware] zur&uuml;ck.
	<br><br></li>

  </ul>
  <br>


  <a name="PiXtendV2Readings"></a>
  <b>Readings</b>
  <ul>
	Das FHEM-Modul des PiXtend unterst&uuml;zt mehrere Readings, von denen die meisten ein Event ausl&ouml;sen, sobald sie sich &auml;ndern.
	Die Bedeutung der Readings ist &auml;hnlich zu den Get-Kommandos.
	<br><br>

    <li>AnalogIn#<br>
		Zeigt das Ergebnis der Messungen der analogen Eing&auml;nge in Volt an.
	<br><br></li>

	<li>DigitalIn#<br>
		Zeigt den Status 1 (HIGH) oder 0 (LOW) der digitalen Eing&auml;nge an.
	<br><br></li>
	
	<li>Firmware<br>
		Zeigt die Firmware-Version an.
	<br><br></li>
	
	<li>GPIOIn#<br>
		Zeigt den Status 1 (HIGH) oder 0 (LOW) der GPIOs, unabh&auml;ngig von deren Konfiguration (input, output, ..).
	<br><br></li>
	
	<li>Hardware<br>
		Zeigt die Hardware-Version an.
	<br><br></li>
	
	<li>Model<br>
		Zeigt das Model an.
	<br><br></li>
	
	<li>RetainDataIn<br>
		Zeigt die Werte von RetainDataIn an. Die Werte von RetainDataIn sind dabei in einer Zeile
		zusammengefasst. Der am weitsten links stehende Wert entspricht Byte0 / RetainDataIn0.
		Die Werte sind durch ein Leerzeichen " " voneinander getrennt und k&ouml;nnen somit einfach in Perl ausgewertet werden:
		<br><br>
		Beispiel:
		<ul>
			<code>my ($str) = ReadingsVal(pix, "RetainDataIn", "?")</code><br>
			<code>if($str ne "?"){</code><br>
			&emsp;<code>my @val = split(/ /, $str);</code>		&emsp;&emsp;=> $val[0] enth&auml;lt nun Byte0, $val[1] Byte1, usw<br>
			&emsp;<code>...</code><br>
			<code>}</code>
		</ul>
	<br><br></li>
	
	<li>Sensor#T/H<br>
		Zeigt die Temperatur (T) in &deg;C und die Luftfeuchtigkeit (H) in % des Sensors an, der an den entsprechenden GPIO angeschlossen ist.
	<br><br></li>

	<li>UCState<br>
		Zeigt den Status des PiXtend an. Ist der Status 1, ist alles in Ordnung. Ist der Status allerdings gr&ouml;&szlig;er als 1 ist ein Fehler aufgetreten
		oder steht noch an. In diesem Fall kann der PiXtend nicht konfiguriert werden.
		F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
		unserer Hompage nach.
	<br><br></li>

	<li>UCWarnings<br>
		Der angezeigte Wert repr&auml;sentiert die Warnungen des PiXtendV2.
		F&uuml;r mehr Informationen sehen Sie bitte im Handbuch f&uuml;r den PiXtendV2 im
		<a href="http://www.PiXtend.de/PiXtend/downloads/" target="_blank">Downloadbereich</a>
		unserer Hompage nach.
	<br><br></li>

  </ul>
  <br>
  
  <a name="PiXtendV2Attr"></a>
  <b>Attributes</b>
  <ul>
	F&uuml;r den Attribut-Namen muss die Gro&szlig;-/Kleinschreibung beachtet werden.
	<br><br>

    <li>PiXtend_GetFormat [text,value]<br>
		&Auml;ndert die Darstellung, wie die Werte durch die Get-Kommandos zur&uuml;ckgegeben werden. Die Werte k&ouml;nnen entweder in einer Nachricht [text] oder als rohe Werte [value] zur&uuml;ckgegeben werden.
		Standard ist die Ausgabe als Text.
	<br><br></li>

    <li>PiXtend_Parameter<br>
		Dieses Attribut kann verwendet werden, um die Einstellungen zur Basiskonfiguration (Set-Kommandos beginnend mit "_") als Attribut zu speichern. Attribute werden im Gegensatz zu Set-Kommandos in der Config-Datei gespeichert.<br>
		Einzelne Kommandos werden durch ein Leerzeichen voneinander getrennt und erhalten ihre Werte nach einem Doppelpunkt.
		<br><br>
		Beispiel:
		<ul>
			<code>attr pix PiXtend_Parameter _gpio0ctrl:dht11 _gpio3ctrl:dht22</code>
		</ul>
	<br><br></li>
  
  </ul>
  <br>
  
</ul>

=end html_DE

=cut

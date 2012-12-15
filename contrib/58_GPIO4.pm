#############################################################################
# GPIO4.pm written by Peter J. Flathmann									#
# Version 0.2, 2012-12-14													#
#																			#
# define RPi GPIO4 BUSMASTER												#
#																			#
# All devices should be automatically created with model information:       #
# ===================================================================       #
# define mysSensor GPIO4 28-000004715a10                                    #
# attr mySensor model DS18B20			            						#
#																			#
# Optional attributes:														#
# ====================                                                      #
# attr mySensor pollingInterval 60  (default: 60s)    						#
#																			#
#############################################################################

package main;
use strict;
use warnings;
use POSIX;

use vars qw{%attr %defs};

sub GPIO4_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}		 = "GPIO4_Define";
	$hash->{UndefFn}	 = "GPIO4_Undef";
	$hash->{GetFn}		 = "GPIO4_Get";
	$hash->{AttrList}	 = "pollingInterval model loglevel:0,1,2,3,4,5,6";	
}

sub GPIO4_Define($$) {

	my ($hash, $def) = @_;
	Log 2, "GPIO4: GPIO4_Define($hash->{NAME})";
	
	my @a = split("[ \t][ \t]*", $def);
	return "syntax: define <name> GPIO4 <id>|BUSMASTER" if (int(@a) != 3);
	$hash->{NAME} = $a[0];
	$hash->{TYPE} = $a[1];
	if ($a[2] eq "BUSMASTER") {
		$hash->{STATE} = "Initialized";
		InternalTimer(gettimeofday()+10, "GPIO4_GetSlaves", $hash, 0);
	}
	else {
		my ($family, $id) = split('-',$a[2]);
		if ($family eq "28") {
			InternalTimer(gettimeofday()+10, "GPIO4_DeviceUpdateLoop", $hash, 0);
		}
		else {
			return "GPIO4: device family $family not supported";
		}
	}
	return undef;
}

sub GPIO4_GetSlaves($) {
	my ($hash) = @_;
	Log 2, "GPIO4: GPIO4_GetSlaves()";
	open SLAVES, "/sys/bus/w1/devices/w1_bus_master1/w1_master_slaves";
	my @slaves = <SLAVES>;
	chomp(@slaves);
	close(SLAVES);
	$hash->{CLIENTS}=join(',',@slaves);
	foreach my $slave (@slaves) {
		GPIO_GetSlave($slave);
	}
	return undef;
}

sub GPIO_GetSlave($) {
	my ($slave) = @_;
	Log 2, "GPIO4: GPIO4_GetSlave($slave)";
	my ($family, $id) = split("-", $slave);
	if ($family eq "28") {
		foreach my $devicename (keys %defs) {
			return undef if ($defs{$devicename}{DEF} eq $slave); 
		}
		Log 2, "GPIO4: create $slave";
		CommandDefine(undef,"gpio4_$id GPIO4 $slave");	
		$attr{"gpio4_$id"}{room} = "GPIO4"; 
		$attr{"gpio4_$id"}{model} = "DS18B20"; 
	}
	return undef;
}

sub GPIO4_DeviceUpdateLoop($) {
	my ($hash) = @_;
    my $pollingInterval = $attr{$hash->{NAME}}{pollingInterval} || 60; 
	Log 2, "GPIO4: GPIO4_DeviceUpdateLoop($hash->{NAME}), pollingInterval:$pollingInterval";
	GPIO4_Get($hash);
	InternalTimer(gettimeofday()+$pollingInterval, "GPIO4_DeviceUpdateLoop", $hash, 0);
	return undef;
}

sub GPIO4_Get($) {
	my ($hash) = @_;
	Log 2, "GPIO4: GPIO4_Get($hash->{NAME})";
	open DATA, "/sys/bus/w1/devices/$hash->{DEF}/w1_slave";
	if (<DATA> =~ /YES/) {
		<DATA> =~ /t=(\d+)/;
		readingsSingleUpdate($hash,"state",$1/1000.0,1);
	}
	close(DATA);
	return undef;
}

sub GPIO4_Undef($) {
	my ($hash) = @_;
	Log 2, "GPIO4: GPIO4_Undef($hash->{NAME})";
	RemoveInternalTimer($hash);
	return undef;
}

1;

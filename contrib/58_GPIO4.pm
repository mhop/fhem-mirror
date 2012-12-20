#############################################################################
# GPIO4.pm written by Peter J. Flathmann									#
# Version 0.3, 2012-12-16													#
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
	$hash->{AttrList}	 = "tempOffset pollingInterval model loglevel:0,1,2,3,4,5,6";	
}

sub GPIO4_Define($$) {

	my ($hash, $def) = @_;
	Log 4, "GPIO4: GPIO4_Define($hash->{NAME})";
	
	my @a = split("[ \t][ \t]*", $def);
	return "syntax: define <name> GPIO4 <id>|BUSMASTER" if (int(@a) != 3);
	$hash->{NAME} = $a[0];
	$hash->{TYPE} = $a[1];

	if ($a[2] eq "BUSMASTER") {
		$hash->{STATE} = "Initialized";
		
		# check connected devices after fhem.cfg completely loaded to avoid duplicates (5s)
		InternalTimer(gettimeofday()+5, "GPIO4_GetSlaves", $hash, 0);
	}
	else {
		my ($family, $id) = split('-',$a[2]);
		if ($family eq "28" || $family eq "10") {

			# reset failures counter
			setReadingsVal($hash,'failures',0,TimeNow()); 

			# start polling device after fhem.cfg completely loaded to ensure pollingInterval attribute is assigned (5s)
			InternalTimer(gettimeofday()+5, "GPIO4_DeviceUpdateLoop", $hash, 0);
		}
		else {
			return "GPIO4: device family $family not supported";
		}
	}
	return;
}

sub GPIO4_GetSlaves($) {
	my ($hash) = @_;
	Log 4, "GPIO4: GPIO4_GetSlaves()";
	open SLAVES, "/sys/bus/w1/devices/w1_bus_master1/w1_master_slaves";
	my @slaves = <SLAVES>;
	chomp(@slaves);
	close(SLAVES);
	$hash->{SLAVES} = join(',',@slaves);
	foreach my $slave (@slaves) {
		GPIO_GetSlave($hash,$slave);
	}
	return;
}

sub GPIO_GetSlave($$) {
	my ($hash,$slave) = @_;
	Log 4, "GPIO4: GPIO4_GetSlave($slave)";
	my ($family, $id) = split("-", $slave);
	
	# return if device exists
	foreach my $devicename (keys %defs) {
		return if (exists $defs{$devicename}{DEF} && $defs{$devicename}{DEF} eq $slave); 
	}

	# device does not exist, create it
	Log 1, "GPIO4: create $slave";
	CommandDefine(undef,"gpio4_$id GPIO4 $slave");	
	if ($family eq "28") {
		$attr{"gpio4_$id"}{model} = "DS18B20"; 
	}
	if ($family eq "10") {
		$attr{"gpio4_$id"}{model} = "DS1820"; 
	}
	$attr{"gpio4_$id"}{room} = "GPIO4"; 
	$defs{"gpio4_$id"}{MASTER} = $hash->{NAME}; 

	# create logfile temp4:Temp
	my @logfile = split('/',$attr{autocreate}{filelog});
	pop(@logfile);
	my $logdir = join('/',@logfile);
	CommandDefine(undef,"FileLog_gpio4_$id FileLog $logdir/gpio4_$id-%Y.log gpio4_$id:T:.*");	
	$attr{"FileLog_gpio4_$id"}{room} = "GPIO4"; 
	$attr{"FileLog_gpio4_$id"}{logtype} = "temp4:Temp,text"; 

	# create plot
	if ($attr{autocreate}{weblink}) {
		CommandDefine(undef,"weblink_gpio4_$id weblink fileplot FileLog_gpio4_$id:temp4:CURRENT");
		$attr{"weblink_gpio4_$id"}{label} = '"'."gpio4_$id: ".'Min $data{min1}, Max $data{max1}, Last $data{currval1}"';
		$attr{"weblink_gpio4_$id"}{room} = $attr{autocreate}{weblink_room} || "GPIO4";
	}

	# save fhem.cfg depending on autocreate autosave
	CommandSave(undef, undef) if($attr{autocreate}{autosave});
	return;
}

sub GPIO4_DeviceUpdateLoop($) {
	my ($hash) = @_;
    my $pollingInterval = $attr{$hash->{NAME}}{pollingInterval} || 60; 
	Log 6, "GPIO4: GPIO4_DeviceUpdateLoop($hash->{NAME}), pollingInterval:$pollingInterval";
	GPIO4_Get($hash);
	InternalTimer(gettimeofday()+$pollingInterval, "GPIO4_DeviceUpdateLoop", $hash, 0);
	return;
}

sub GPIO4_Get($) {
	my ($hash) = @_;
	Log 6, "GPIO4: GPIO4_Get($hash->{NAME})";
	open DATA, "/sys/bus/w1/devices/$hash->{DEF}/w1_slave";
	if (<DATA> =~ /YES/) {
		<DATA> =~ /t=(\d+)/;
		my $temp = $1/1000.0;
		if ($attr{$hash->{NAME}}{tempOffset}) {
			$temp+=$attr{$hash->{NAME}}{tempOffset};
		}
		my $tempstr = sprintf("%.1f",$temp);
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash,"state","T: $tempstr");
		readingsBulkUpdate($hash,"temperature",$tempstr);
		readingsEndUpdate($hash,1);
	}
	else {
		readingsSingleUpdate($hash,'failures',ReadingsVal($hash->{NAME},"failures",0)+1,1); 
	}
	close(DATA);
	return;
}

sub GPIO4_Undef($) {
	my ($hash) = @_;
	Log 4, "GPIO4: GPIO4_Undef($hash->{NAME})";
	RemoveInternalTimer($hash);
	return;
}

1;

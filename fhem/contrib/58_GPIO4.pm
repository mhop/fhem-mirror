#############################################################################
#
#  $Id$ 
#
#  Copyright notice
#
#  (c) 2012 Copyright: Peter J. Flathmann (peter dot flathmann at web dot de)
#  All rights reserved
#
#  This script free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
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
	$hash->{NotifyFn}	 = "GPIO4_Notify";
	$hash->{GetFn}		 = "GPIO4_Get";
	$hash->{AttrList}	 = "tempOffset pollingInterval model loglevel:0,1,2,3,4,5,6 ".$readingFnAttributes;
}

sub GPIO4_Notify($$) {
	my ($hash, $dev) = @_;
	return if($hash->{DEF} ne "BUSMASTER" || $dev->{NAME} ne "global" || !grep(m/^INITIALIZED$/, @{$dev->{CHANGED}}));
	# check bus for new devices not before fhem.cfg completely loaded to avoid duplicates
	GPIO4_GetSlaves($hash);
	delete $modules{GPIO4}{NotifyFn};
	return;
}

sub GPIO4_Define($$) {

	my ($hash, $def) = @_;
	Log 4, "GPIO4: GPIO4_Define($hash->{NAME})";
	
	my @a = split("[ \t][ \t]*", $def);
	return "syntax: define <name> GPIO4 <id>|BUSMASTER" if (int(@a) != 3);
	$hash->{NAME} = $a[0];
	$hash->{TYPE} = 'GPIO4';

	if ($a[2] eq "BUSMASTER") {
		$hash->{STATE} = "Initialized";
	}
	else {
		my ($family, $id) = split('-',$a[2]);
		if ($family eq "28" || $family eq "10") {
			# reset failures counter
			setReadingsVal($hash,'failures',0,TimeNow()); 
			$hash->{fhem}{interfaces} = "temperature";
			GPIO4_DeviceUpdateLoop($hash);
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

	# device does not exist, let autocreate create it
	my $model;
	if ($family eq "28") {
		$model = "DS18B20"; 
	}
	elsif ($family eq "10") {
		$model = "DS1820"; 
	}
	DoTrigger("global", "UNDEFINED GPIO4_${model}_${id} GPIO4 $slave");
	$attr{"GPIO4_${model}_${id}"}{model} = $model; 

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
		<DATA> =~ /t=(-?\d+)/;
		my $temp = $1/1000.0;
		if ($attr{$hash->{NAME}}{tempOffset}) {
			$temp+=$attr{$hash->{NAME}}{tempOffset};
		}
		readingsBeginUpdate($hash);
		readingsBulkUpdate($hash,"state","T: $temp");
		readingsBulkUpdate($hash,"temperature",$temp);
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

=pod
=begin html

<a name="GPIO4"></a>
<h3>GPIO4</h3>
<ul>
  1-wire temperature sensors connected to Raspberry Pi's GPIO port 4.
  <br><br>
  <a name="GPIO4define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; GPIO4 ('BUSMASTER'|&lt;id&gt;)</code>
    <br><br>
    Defines the BUSMASTER or one of the slave devices. The BUSMASTER is necessary 
    to get the slaves automatically created by autocreate.pm.
 	<br><br>
    Examples:
    <ul>
      <code>
	    define RPi GPIO4 BUSMASTER<br>
		define mysSensor GPIO4 28-000004715a10<br>
	  </code>
    </ul>
  </ul>
  <br>
  <a name="GPIO4attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#pollingInterval">pollingInterval</a></li>
    <li><a href="#tempOffest">tempOffset</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html
=begin html_DE

<a name="GPIO4"></a>
<h3>GPIO4</h3>
<ul>
  1-wire Temperatursensoren an GPIO Port 4 des Raspberry Pi.
  <br><br>
  <a name="GPIO4define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; GPIO4 ('BUSMASTER'|&lt;id&gt;)</code>
    <br><br>
    Definiert den BUSMASTER oder die Slave-Devices. Der BUSMASTER ist notwendig,
    um die Slave-Devices automatisch via autocreate.pm zu erzeugen.
    <br><br>
    Examples:
    <ul>
      <code>
        define RPi GPIO4 BUSMASTER<br>
        define mysSensor GPIO4 28-000004715a10<br>
      </code>
    </ul>
  </ul>
  <br>
  <a name="GPIO4attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#pollingInterval">pollingInterval</a></li>
    <li><a href="#tempOffest">tempOffset</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>

=end html_DE
=cut

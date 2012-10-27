# $Id: 98_DeviceMonitor.pm  $
#
# Copyright (C) 2012 Dennis Gnoyke
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# 
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself, either Perl version 5.8.7 or,
# at your option, any later version of Perl 5 you may have available.
#
package main;
use strict;
use warnings;

sub DeviceMonitor_Initialize($)
{
	my ($hash) = @_;
	$hash->{DefFn}     = "DeviceMonitor_Define";
	$hash->{NotifyFn}  = "DeviceMonitor_Notify";
	$hash->{AttrList}  = "disable:0,1";
	addToAttrList("device_timeout"); 
}

sub DeviceMonitor_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $u = "wrong syntax: define <name> DeviceMonitor ";
	return $u if(int(@a) < 2);
  	$hash->{CHANGED}[0] = "DEFINED";
	$hash->{STATE}      = "DEFINED";	
	return undef;
}

sub DeviceMonitor_Notify($$)
{
#*******************************************************************************
# Purpose: Checks for timeout - Notify reacts on triggers fired from the Device
# Author : Dennis Gnoyke
# Date   : 21.10.2012
# Changes: 27.10.2012 GN Code optimized
# Remarks: EXPERIMENTAL VERSION !!!!!!!
# 
#**************************** Begin of Code *************************************	
	my ($ownhash, $devhash) = @_;
 	my $devName = $devhash->{NAME}   ; #Name of the Device which has triggered this event
	my $ownName = $ownhash->{NAME}   ; #Name of DeviceMonitor
	my $enabled = $ownhash->{ENABLED}; #DeviceMonitor enabled ?
	my $timeoutinterval = 0;

	$timeoutinterval = AttrVal($devName, "device_timeout", "undef"); #Timeout configured ?
	return "" if ($timeoutinterval eq "undef");
	
	$devhash->{HEALTH_MONITORED_BY} = $ownName;	
		
	if(AttrVal($devName, "disable", 0) > 0){$timeoutinterval = 0}; #Device Enabled ?
	if(AttrVal($ownName, "disable", 0) > 0)  #DeviceMonitor Enabled ?
		{
			$timeoutinterval = 0;
			$ownhash->{STATE} = "DISABLED";			
		}
	else 
		{
			$ownhash->{STATE} = "ENABLED";
		}
			
	if ($timeoutinterval < 1) #device_timeout set to 0
		{
			if (ReadingsVal($devName,"health_state","unknown") ne "unknown"){DoTrigger($devName,"health_state: unknown")};
			$devhash->{HEALTH_STATE} = "unknown";
			$devhash->{HEALTH_TIME} = TimeNow();
			$ownhash->{READINGS}{$devName}{VAL} = "unknown";
			$ownhash->{READINGS}{$devName}{TIME} = TimeNow();
		}
	else 
		{
			if (ReadingsVal($devName,"health_state","unknown") ne "alive"){DoTrigger($devName,"health_state: alive")};
			RemoveInternalTimer($devhash);
			$devhash->{HEALTH_STATE} = "alive";
			$devhash->{HEALTH_TIME} = TimeNow();
			$ownhash->{READINGS}{$devName}{VAL} = "alive";
			$ownhash->{READINGS}{$devName}{TIME} = TimeNow();
			InternalTimer(gettimeofday()+($timeoutinterval*60), "DeviceMonitor_Timer", $devhash, 0);
		}	
	return undef;
#**************************** End of Code *************************************	
 }
 
sub DeviceMonitor_Timer($)
{
#*******************************************************************************
# Purpose: Checks for timeout - Will be called if timeout occured
# Author : Dennis Gnoyke
# Date   : 21.10.2012
# Changes: 22.10.2012 GN Typo Death -> Dead
# Remarks: EXPERIMENTAL VERSION !!!!!!!
# 
#**************************** Begin of Code *************************************	
	#set the HEALTH_STATE to "dead" if not already set
	my ($devhash) = @_;
	my $ownName = $devhash->{HEALTH_MONITORED_BY};
	my $devName = $devhash->{NAME};
  
    DoTrigger($devName,"health_state: dead");
	$devhash->{HEALTH_STATE} = "dead";
	$devhash->{HEALTH_TIME} = TimeNow();	
	$defs{$ownName}{READINGS}{$devName}{TIME} = TimeNow();
	$defs{$ownName}{READINGS}{$devName}{VAL} = "dead";
#**************************** End of Code *****************************************
}
1;
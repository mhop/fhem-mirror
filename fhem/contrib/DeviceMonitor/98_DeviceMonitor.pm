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
	$hash->{UndefFn}   = "DeviceMonitor_Undef";
	$hash->{NotifyFn}  = "DeviceMonitor_Notify";
	$hash->{GetFn}     = "DeviceMonitor_Get";
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

sub
DeviceMonitor_Undef($$)
{
  my ($hash, $arg) = @_;

  return DeviceMonitor_Remove($hash,"all");
  return undef;
}


sub DeviceMonitor_Get($@)
{
#*******************************************************************************
# Purpose: Get some results
# Author : Dennis Gnoyke
# Date   : 27.10.2012
# Changes: 
# Remarks: 
#**************************** Begin of Code *************************************	
	my ($hash, @a) = @_;
	return "argument is missing" if(int(@a) != 2);
	
    my ($criteria, $output) = split ("_",lc($a[1]));   
	return DeviceMonitor_GetResult($a[0],$criteria,$output);	
#**************************** End of Code *****************************************	
}

sub DeviceMonitor_Notify($$)
{
#*******************************************************************************
# Purpose: Checks for timeout - Notify reacts on triggers fired from the Device
# Author : Dennis Gnoyke
# Date   : 21.10.2012
# Changes: 27.10.2012 GN Code optimized, Events reduced
# Remarks: EXPERIMENTAL VERSION !!!!!!!
# 
#**************************** Begin of Code *************************************	
	my ($ownhash, $devhash) = @_;
 	my $devName = $devhash->{NAME}   ; #Name of the Device which has triggered this event
	my $ownName = $ownhash->{NAME}   ; #Name of DeviceMonitor
	my $enabled = $ownhash->{ENABLED}; #DeviceMonitor enabled ?
	my $timeoutinterval = 0;
	my $devState = "unknown";
	
	$timeoutinterval = AttrVal($devName, "device_timeout", 0); #Timeout configured ?
	return "" if ($timeoutinterval < 1 && !defined($defs{$devName}{HEALTH_MONITORED_BY})); #Leave NTFY if device is not configured for DeviceMonitor

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
	
	Log 4, "'$devName' is now monitored by '$ownName'" if(!defined($defs{$devName}{HEALTH_MONITORED_BY}));
	$devhash->{HEALTH_MONITORED_BY} = $ownName;	
	# Get current HealthState		
	if (!defined($devhash->{HEALTH_STATE})){$devState = "unknown"}else{$devState = $devhash->{HEALTH_STATE}}
		
	if ($timeoutinterval < 1) #device_timeout set to 0, remove it from monitor
		{
			DeviceMonitor_Remove($ownName,$devName);
			RemoveInternalTimer($devhash);
		}
	else 
		{
			if ($devState ne "alive"){DoTrigger($devName,"health_state: alive")};
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
# Remarks:
# 
#**************************** Begin of Code *************************************	
	#set the HEALTH_STATE to "dead" if not already set
	my ($devhash) = @_;
	my $ownName = $devhash->{HEALTH_MONITORED_BY};
	my $devName = $devhash->{NAME};
  
    if(AttrVal($devName, "device_timeout", 0) < 1) #device_timeout set to 0, remove it from monitor
		{
			DeviceMonitor_Remove($ownName,$devName);
		}
	else
		{
			DoTrigger($devName,"health_state: dead");
			$devhash->{HEALTH_STATE} = "dead";
			$devhash->{HEALTH_TIME} = TimeNow();	
			$defs{$ownName}{READINGS}{$devName}{TIME} = TimeNow();
			$defs{$ownName}{READINGS}{$devName}{VAL} = "dead";
		}
	RemoveInternalTimer($devhash);
#**************************** End of Code *****************************************
}

sub DeviceMonitor_GetResult($$$)
{
#*******************************************************************************
# Purpose: Get results from DeviceMonitor readings
# Author : Dennis Gnoyke
# Date   : 27.10.2012
# Changes: 
# Remarks: 	$_[0] = DeviceMonitor
#			$_[1] = Criteria dead|alive|total
#			$_[2] = Output as count|text|html
#**************************** Begin of Code *************************************	
	my $hash = $defs{$_[0]}{READINGS};
	my $cnt = 0; 		#counter
	my @result ; 		#result array
	$result[0] ="null";	#default
	my $tmp = "";		#temp var
	
	foreach my $readings_name (sort keys %{$hash}) #Loop through Readings
		{
			my $val = $hash->{$readings_name};
			if(ref($val)) 
				{
					my $readings_value = $val->{VAL};
					my $readings_time = $val->{TIME};
					if ($readings_value eq $_[1]) #value like dead or alive
						{
							$result["$cnt"] = $readings_name.','."has health_state '$readings_value' reported at $readings_time";
							$cnt = $cnt + 1
						}
					elsif($_[1] eq "total")
						{
							$result["$cnt"] = $readings_name.','."has health_state '$readings_value' reported at $readings_time";
							$cnt = $cnt + 1
						}
				}
		}
	if ($result[0] eq "null")
		{
			return 0 if($_[2] eq "count");
			return "$_[0]: There was no match for your criteria '$_[1]'" if($_[2] eq "text");
			return "$_[0]: There was no match for your criteria '$_[1]'" if($_[2] eq "html");
			return "$_[0]: Unknown argument $_[2] , syntax is <criteria>_<output> criteria=dead,alive,total output=count,text,html";
		}
	else
		{
			if($_[2] eq "count"){return $cnt}
			elsif($_[2] eq "text")
				{
					foreach (@result) 
						{
							my ($device, $value) = split (",",$_);
							$tmp .= "Device $device $value\n";
						}
					return $tmp;
				}
			elsif($_[2] eq "html")
				{
					$tmp = "<table>\n";
					foreach (@result)
						{
							my ($device, $value) = split (",",$_);
							$tmp .= "<tr><td>Device <a href='/fhem?detail=$device'>$device</a> $value</td></tr>\n";
						};
					$tmp .= "</table></div>";
					return $tmp;
				}
			else{return "$_[0]: Unknown argument $_[2] , syntax is <criteria>_<output> criteria=dead,alive,total output=count,text,html"}
		}
#**************************** End of Code *****************************************
}


sub DeviceMonitor_Remove($$)
{
#*******************************************************************************
# Purpose: Resets DeviceMonitor readings
# Author : Dennis Gnoyke
# Date   : 28.10.2012
# Changes: 
# Remarks: 	$_[0] = DeviceMonitor
#			$_[1] = Criteria devicename|all
#	
#**************************** Begin of Code *************************************	
	my $hash = $defs{$_[0]}{READINGS};
		
	if(defined($hash->{$_[1]})) #remove single device from monitor
		{
			 delete $hash->{$_[1]};
			 if(defined($defs{$_[1]}{HEALTH_MONITORED_BY})){delete $defs{$_[1]}{HEALTH_MONITORED_BY}};
			 if(defined($defs{$_[1]}{HEALTH_STATE})){delete $defs{$_[1]}{HEALTH_STATE}};
			 if(defined($defs{$_[1]}{HEALTH_TIME})){delete $defs{$_[1]}{HEALTH_TIME}};
			 RemoveInternalTimer($defs{$_[1]});
			 Log 4, "'$_[1]' is no longer monitored by '$_[0]'";
		}
	elsif(uc($_[1]) eq "ALL") #remove all devices from monitor
		{
			foreach my $readings_name (sort keys %{$hash}) #Loop through Readings
			{
				delete $hash->{$readings_name};
				if(defined($defs{$readings_name}{HEALTH_MONITORED_BY})){delete $defs{$readings_name}{HEALTH_MONITORED_BY}};
				if(defined($defs{$readings_name}{HEALTH_STATE})){delete $defs{$readings_name}{HEALTH_STATE}};
				if(defined($defs{$readings_name}{HEALTH_TIME})){delete $defs{$readings_name}{HEALTH_TIME}};
				RemoveInternalTimer($defs{$readings_name});
			}
			Log 4, "all devices removed from '$_[0]', please note that devices will appear again if their device_timeout attr is still set and '$_[0]' is defined and enabled!";
		}
	else
		{
			return "$_[0]: Can`t remove $_[1] check spelling and upper/lower cases";
		}

#**************************** End of Code *****************************************
}

1;
# $Id$
##############################################################################
#
#     73_PRESENCE.pm
#     Checks for the presence of a mobile phone or tablet by network ping or bluetooth detection.
#     It reports the presence of this device as state.
#
#     Copyright by Markus Bloch
#     e-mail: Notausstieg0309@googlemail.com
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
##############################################################################

package main;

use strict;
use warnings;
use Blocking;
use Time::HiRes qw(gettimeofday sleep);
use DevIo;





sub
PRESENCE_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "PRESENCE_Read";  
  $hash->{ReadyFn} = "PRESENCE_Ready";
  $hash->{SetFn}   = "PRESENCE_Set";
  $hash->{DefFn}   = "PRESENCE_Define";
  $hash->{UndefFn} = "PRESENCE_Undef";
  $hash->{AttrFn}  = "PRESENCE_Attr";
  $hash->{AttrList}= "do_not_notify:0,1 disable:0,1 fritzbox_repeater:0,1 loglevel:1,2,3,4,5 ".$readingFnAttributes;
  
}

#####################################
sub
PRESENCE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $dev;
  
  if($a[2] ne "lan-bluetooth" and not (@a == 4 or @a == 5 or @a == 6))
  {
    my $msg = "wrong syntax: define <name> PRESENCE <mode> <device-address> [ <check-interval> [ <present-check-interval> ] ]";
    Log 2, $msg;
    return $msg;
  }
  elsif($a[2] eq "lan-bluetooth" and not (@a == 5 or @a == 6)) {
    my $msg = "wrong syntax: define <name> PRESENCE lan-bluetooth <bluetooth-device-address> <ip-address>[:port] [ <check-interval> ]";
    Log 2, $msg;
    return $msg;
  }
  
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $destination = $a[2];
  my $address = $a[3];
  my $timeout = (defined($a[4]) ? $a[4] : 30);
 
  my $presence_timeout = (defined($a[5]) ? $a[5] : $timeout);
  
  $timeout = (defined($a[5]) ? $a[5] : 30) if($destination eq "lan-bluetooth");
  $presence_timeout =  (defined($a[6]) ? $a[6] : 30) if($destination eq "lan-bluetooth");
  
  $hash->{ADDRESS} = $address;
  $hash->{TIMEOUT_NORMAL} = $timeout;
  $hash->{TIMEOUT_PRESENT} = $presence_timeout;

    if(defined($timeout) and not $timeout =~ /^\d+$/)
    {
	my $msg = "check-interval must be a number";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }


    if(defined($timeout) and not $timeout > 0)
    {
	my $msg = "check-interval must be greater than zero";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }


    if(defined($presence_timeout) and not $presence_timeout =~ /^\d+$/)
    {
	my $msg = "presence-check-interval must be a number";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }


    if(defined($presence_timeout) and not $presence_timeout > 0)
    {
	my $msg = "presence-check-interval must be greater than zero";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }
    
    if(($destination eq "local-bluetooth" or $destination eq "lan-bluetooth") and not $address =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/)
    {
        my $msg = "given address is not a bluetooth hardware address";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }
    
    if($destination eq "fritzbox" and not -X "/usr/bin/ctlmgr_ctl")
    {
	my $msg = "this is not a fritzbox or you running FHEM with the AVM Beta Image. Please use the FHEM FritzBox Image from fhem.de";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }

    if(-X "/usr/bin/ctlmgr_ctl" and ($destination eq "fritzbox" or $destination eq "lan-ping") and not $< == 0)
    {

	my $msg = "FHEM is not running under root (currently ".(getpwuid($<))[0].") This check can only performed with root access to the FritzBox";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }
  
  if($destination eq "lan-ping" or $destination eq "local-bluetooth" or $destination eq "fritzbox")
  {
 
    $hash->{MODE} = $destination;
    
    delete $hash->{helper}{cachednr} if(defined($hash->{helper}{cachednr}));
    
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+2, "PRESENCE_StartLocalScan", $hash, 0) unless(exists($hash->{helper}{DISABLED}) and $hash->{helper}{DISABLED});
    
    return;
  
  }
  elsif($destination eq "lan-bluetooth")
  {
   $hash->{MODE} = "lan-bluetooth";
   $dev = $a[4];
   $dev .= ":5222" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);


    if(defined($timeout) and not $timeout =~ /^\d+$/)
    {
	my $msg = "timeout must be a number";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }


    if(defined($timeout) and not $timeout > 0)
    {
	my $msg = "timeout must be greater than zero";
	Log 2, "PRESENCE: ".$msg;
	return $msg;
    }

  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "PRESENCE_DoInit");

  return $ret;
  }
  else
  {
  
  return "unknown mode: $destination Please use lan-ping, lan-bluetooth or local-bluetooth";
  } 
}


#####################################
sub
PRESENCE_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};


  RemoveInternalTimer($hash);
  DevIo_CloseDev($hash); 
  return undef;
}

sub
PRESENCE_Set($@)
{
    my ($hash, @a) = @_;

    return "No Argument given" if(!defined($a[1]));
   
    my $usage = (defined($hash->{MODE}) and $hash->{MODE} ne "lan-bluetooth" ? "Unknown argument ".$a[1].", choose one of statusRequest " : undef);
   
    if($a[1] eq "statusRequest")
    {
	if($hash->{MODE} ne "lan-bluetooth")
	{
	    PRESENCE_StartLocalScan($hash, 1);
	    return "";
	}
   
    }
    else
    {
        return $usage;
    }
   




}


##########################
sub
PRESENCE_Attr(@)
{
  my @a = @_;
  my $hash = $defs{$a[1]};

  if($a[0] eq "set" && $a[2] eq "disable")
  {
    if($a[3] eq "0")
    {
	$hash->{helper}{DISABLED} = 0;
	readingsSingleUpdate($hash, "state", "defined",0);
	if(defined($hash->{DeviceName}))
	{
	    if(defined($hash->{FD}))
	    {
		PRESENCE_DoInit($hash);
	    }
	    else
	    {
		DevIo_OpenDev($hash, 0, "PRESENCE_DoInit");
	    }
	}
	else
	{
	    PRESENCE_StartLocalScan($hash);
	}
	
    }
    elsif($a[3] eq "1")
    {
	if(defined($hash->{FD}))
	{
	    DevIo_SimpleWrite($hash, "stop\n", 0);
	}
	
	
	RemoveInternalTimer($hash);
	
	$hash->{helper}{DISABLED} = 1;
	readingsSingleUpdate($hash, "state", "disabled",1);
    }
    
  }
  elsif($a[0] eq "del" && $a[2] eq "disable")
  {
    $hash->{helper}{DISABLED} = 0;
    readingsSingleUpdate($hash, "state", "defined",0);
    if(defined($hash->{DeviceName}))
    {
        if(defined($hash->{FD}))
	    {
		PRESENCE_DoInit($hash);
	    }
	    else
	    {
		DevIo_OpenDev($hash, 0, "PRESENCE_DoInit");
	    }
    }
    else
    {
        PRESENCE_StartLocalScan($hash);
    }
  }
  return undef;
}



#####################################
# Receives an event and creates several readings for event triggering
sub
PRESENCE_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  
  chomp $buf;
  
  
   readingsBeginUpdate($hash);
    
    if($buf eq "absence")
    {
	readingsBulkUpdate($hash, "state", "absent");
    }
    elsif($buf =~ /present;(.+?)$/)
    {
	readingsBulkUpdate($hash, "state", "present");
	
	if($1 =~ /^(.*);(.+)$/)
	{
	    readingsBulkUpdate($hash, "room", $2);
	    readingsBulkUpdate($hash, "device_name", $1);
	}
	else
	{
	    readingsBulkUpdate($hash, "device_name", $1);
	}
	
	
    }
    elsif($buf eq "command accepted")
    {
	readingsBulkUpdate($hash, "command_accepted", "yes");
    }
    elsif($buf eq "command rejected")
    {
	readingsBulkUpdate($hash, "command_accepted", "no");
    }
    elsif($buf =~ /socket_closed;(.+?)$/)
    {
	Log GetLogLevel($hash->{NAME}, 3), "PRESENCE: collectord lost connection to room $1 for device ".$hash->{NAME};
    }
    elsif($buf =~ /socket_reconnected;(.+?)$/)
    {
	Log GetLogLevel($hash->{NAME}, 3), "PRESENCE: collectord reconnected to room $1 for device ".$hash->{NAME};
    
    }
    elsif($buf =~ /error;(.+?)$/)
    {
	Log GetLogLevel($hash->{NAME}, 3), "PRESENCE: room $1 cannot execute hcitool to check device ".$hash->{NAME};
    }
    elsif($buf =~ /error$/)
    {
	Log GetLogLevel($hash->{NAME}, 3), "PRESENCE: presenced cannot execute hcitool to check device ".$hash->{NAME};
    }
    readingsEndUpdate($hash, 1);
  
}

sub
PRESENCE_DoInit($)
{

    my ($hash) = @_;

    unless($hash->{helper}{DISABLED})
    {
	DevIo_SimpleWrite($hash, $hash->{ADDRESS}."|".$hash->{TIMEOUT_NORMAL}."\n", 0);
    }
    else
    {
	readingsSingleUpdate($hash, "state", "disabled",1);
    }
}


sub
PRESENCE_Ready($)
{
   my ($hash) = @_;
       

   return DevIo_OpenDev($hash, 1, "PRESENCE_DoInit") if($hash->{MODE} eq "lan-bluetooth");

}

##########################################################################################################################
#
# 
#  Functions for local testing with Blocking.pm to ensure a smooth FHEM processing
#
#
sub PRESENCE_StartLocalScan($;$)
{
    my ($hash, $local) = @_;

    $local = 0 unless(defined($local));

    if($hash->{MODE} eq "local-bluetooth")
    {
	BlockingCall("PRESENCE_DoLocalBluetoothScan", $hash->{NAME}."|".$hash->{ADDRESS}."|".$local, "PRESENCE_ProcessLocalScan", 20);
    }
    elsif($hash->{MODE} eq "lan-ping")
    {
	BlockingCall("PRESENCE_DoLocalPingScan", $hash->{NAME}."|".$hash->{ADDRESS}."|".$local, "PRESENCE_ProcessLocalScan", 20);
    }
    elsif($hash->{MODE} eq "fritzbox")
    {
	BlockingCall("PRESENCE_DoLocalFritzBoxScan", $hash->{NAME}."|".$hash->{ADDRESS}."|".$local."|".AttrVal($hash->{NAME}, "fritzbox_repeater", "0"), "PRESENCE_ProcessLocalScan", 20);
    }
    
}

sub
PRESENCE_DoLocalPingScan($)
{

    my ($string) = @_;
    my ($name, $device, $local) = split("\\|", $string);

    Log GetLogLevel($defs{$name}{NAME}, 5), "PRESENCE_DoLocalPingScan: $string";
   
    my $retcode;
    my $return;
    my $temp;
    if($^O =~ m/(Win|cygwin)/)
    {
	eval "require Net::Ping;";
	my $pingtool = Net::Ping->new("syn");

	if($pingtool)
	{
	    $retcode = $pingtool->ping($device, 5);
	    
	    Log GetLogLevel($name, 5), "PRESENCE ($name) - pingtool returned $retcode";
	    
	    $return = "$name|$local|".($retcode ? "present" : "absent"); 
	}
	else
	{
	    $return = "$name|$local|error|Could not create a Net::Ping object.";
	}

    }
    else
    {
	$temp = qx(ping -c 4 $device);
	
	Log GetLogLevel($name, 5), "PRESENCE ($name) - ping command returned with output:\n$temp";
	$return = "$name|$local|".($temp =~ /\d+ [Bb]ytes (from|von)/ ? "present" : "absent");
    }

    return $return;

}

sub
PRESENCE_DoLocalFritzBoxScan($)
{
    my ($string) = @_;
    my ($name, $device, $local, $repeater) = split("\\|", $string);
    
    Log GetLogLevel($defs{$name}{NAME}, 5), "PRESENCE_DoLocalFritzBoxScan: $string";
    my $number=0;
    
    my $check_command = ($repeater ? "active" : "speed");


    my $status=0;

    if (defined($defs{$name}{helper}{cachednr})) 
    {
        $number = $defs{$name}{helper}{cachednr};
       
        Log GetLogLevel($name, 5), "PRESENCE_DoLocalFritzBoxScan: name=$name device=$device cachednr=$number";
       
        my $cached_name = qx(/usr/bin/ctlmgr_ctl r landevice settings/landevice$number/name);    
        chomp $cached_name;
       
        # only use the cached $number if it has still the correct device name
        if($cached_name eq $device)
        {
            Log GetLogLevel($name, 5), "PRESENCE ($name) - checking with cached number the $check_command state ($number)";
    	    $status = qx(/usr/bin/ctlmgr_ctl r landevice settings/landevice$number/$check_command);
    	    if(not $status =~ /^\s*\d+\s*$/)
    	    {
        	return "$name|$local|error|could not execute ctlmgr_ctl (cached)";
    	    }
    	    return ($status == 0)? "$name|$local|absent|$number" : "$name|$local|present|$number"; ###MH
	}
	else
	{
	    Log GetLogLevel($name, 5), "PRESENCE ($name) - cached device name ($cached_name) does not match expected name ($device). perform a full scan";
	}
    }

    my $max = qx(/usr/bin/ctlmgr_ctl r landevice settings/landevice/count);
    
    chomp $max;
    
    if(not $max =~ /^\s*\d+\s*$/)
    {
       return "$name|$local|error|could not execute ctlmgr_ctl";
    }
    
    

    my $net_device;

    $number = 0;
    
    while($number <= $max)
    {
	$net_device=qx(/usr/bin/ctlmgr_ctl r landevice settings/landevice$number/name);
        
        chomp $net_device;
        
        Log GetLogLevel($name, 5), "PRESENCE ($name) - checking with device number $number the $check_command state ($net_device)";
	if($net_device eq $device)
	{
  	    $status=qx(/usr/bin/ctlmgr_ctl r landevice settings/landevice$number/$check_command); 
  	    
  	    Log GetLogLevel($name, 5), "PRESENCE ($name) - $check_command for device number $net_device is $status";
  	    last;
	}
	
	$number++;
	sleep 0.2;
    }
    
    chomp $status;

    return ($status == 0 ? "$name|$local|absent" : "$name|$local|present").($number <= $max ? "|$number" : "");
}

sub
PRESENCE_DoLocalBluetoothScan($)
{
    my ($string) = @_;
    my ($name, $device, $local) = split("\\|", $string);
    my $hcitool = qx(which hcitool);
    my $devname;
    my $return;
    my $wait = 1;
    my $ps;
    
    Log GetLogLevel($name, 4), "PRESENCE ($name): 'which hcitool' returns: $hcitool";
    chomp $hcitool;
    
    
    if(-x $hcitool)
    {
        while($wait)
        {   # check if another hcitool process is running
    	   $ps = qx(ps ax | grep hcitool | grep -v grep);
    	   if(not $ps =~ /^\s*$/)
    	   {
    	     # sleep between 1 and 5 seconds and try again
    	     Log GetLogLevel($name, 5), "PRESENCE ($name) - another hcitool command is running. waiting...";
    	     sleep(rand(4)+1);
    	   }
    	   else
    	   {
    	     $wait = 0;
    	   }
    	 }
    	   
	$devname = qx(hcitool name $device);

	chomp($devname);
	Log GetLogLevel($name, 4), "PRESENCE ($name) - hcitool returned: $devname";

	if(not $devname =~ /^\s*$/)
	{
	    $return = "$name|$local|present|$devname";
	}
	else
	{
	    $return = "$name|$local|absent";
	}
    }
    else
    {
	$return = "$name|$local|error|no hcitool binary found. Please check that the bluez-package is properly installed";
    }

    return $return;
}





sub
PRESENCE_ProcessLocalScan($)
{
 my ($string) = @_;
 my @a = split("\\|",$string);
 
 my $hash = $defs{$a[0]};
 my $local = $a[1];
 
 return if($hash->{helper}{DISABLED});
 
 Log GetLogLevel($hash->{NAME}, 5), "PRESENCE_ProcessLocalScan: $string";
 
 if($hash->{MODE} eq "fritzbox" and defined($a[3]))
 {
    $hash->{helper}{cachednr} = $a[3] if(($a[2] eq "present") || ($a[2] eq "absent")); 
 }
 elsif($hash->{MODE} eq "fritzbox" and defined($hash->{helper}{cachednr}))
 {
    delete($hash->{helper}{cachednr});
 }
 
 readingsBeginUpdate($hash);
 if($a[2] eq "present")
 {
    readingsBulkUpdate($hash, "state", "present");
    readingsBulkUpdate($hash, "device_name", $a[3]) if(defined($a[3]) and $hash->{MODE} =~ /^(lan-bluetooth|local-bluetooth)$/ );
 }
 elsif($a[2] eq "absent")
 {
    readingsBulkUpdate($hash, "state", "absent");
 }
 elsif($a[2] eq "error")
 {
    Log GetLogLevel($hash->{NAME}, 2), "PRESENCE: error while processing device ".$hash->{NAME}." - ".$a[3];
 }


 readingsEndUpdate($hash, 1);

 #Schedule the next check withing $timeout if it is a regular run
 unless($local)
 {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+($a[2] eq "present" ? $hash->{TIMEOUT_PRESENT} : $hash->{TIMEOUT_NORMAL}), "PRESENCE_StartLocalScan", $hash, 0) unless($hash->{helper}{DISABLED});
 }
}
1;

=pod
=begin html

<a name="PRESENCE"></a>
<h3>PRESENCE</h3>
<ul>
  <tr><td>
  The PRESENCE module provides several possibilities to check the presence of mobile phones or similar mobile devices such as tablets.
  <br><br>
  This module provides several operational modes to serve your needs. These are:<br><br>
  <ul>
  <li><b>lan-ping</b> - A presence check of a device via network ping in your LAN/WLAN</li>
  <li><b>fritzbox</b> - A presence check by requesting the device state from the FritzBox internals (only available when running FHEM on a FritzBox!)</li>
  <li><b>local-bluetooth</b> - A presence check by searching directly for a given bluetooth device nearby</li>
  <li><b>lan-bluetooth</b> - A presence check of a bluetooth device via LAN network by connecting to a presenced or collectord instance</li>
  </ul>
  <br><br>
  <a name="PRESENCEdefine"></a>
  <b>Define</b><br><br>
  <ul><b>Mode: lan-ping</b><br><br>
    <code>define &lt;name&gt; PRESENCE lan-ping &lt;ip-address&gt; [ &lt;check-interval&gt; [ &lt;present-check-interval&gt; ] ]</code><br>
    <br>
    Checks for a network device via PING requests and reports its presence state.<br>
    <br>
    <b>Mode: fritzbox</b><br><br>
    <code>define &lt;name&gt; PRESENCE fritzbox &lt;device-name&gt; [ &lt;check-interval&gt; [ &lt;present-check-interval&gt; ] ]</code><br>
    <br>
    Checks for a network device by requesting the internal state on a FritzBox via ctlmgr_ctl. The device-name must be the same as shown in the network overview of the FritzBox<br>
    <br>
    <b>Mode: local-bluetooth</b><br><br>
    <code>define &lt;name&gt; PRESENCE local-bluetooth &lt;bluetooth-address&gt; [ &lt;check-interval&gt; [ &lt;present-check-interval&gt; ] ]</code><br>
    <br>
    Checks for a bluetooth device and reports its presence state. For this mode the shell command "hcitool" is required (provided with a <a href="http://www.bluez.org" target="_new">bluez</a> installation under Debian via APT), as well
    as a functional bluetooth device directly attached to your machine.<br><br>
    <b>Mode: lan-bluetooth</b><br><br>
    Checks for a bluetooth device with the help of presenced or collectord. They can be installed where-ever you like, just must be accessible via network.
     The given device will be checked for presence status.<br>
    <br>
    <code>define &lt;name&gt; PRESENCE &lt;ip-address&gt;[:port] &lt;bluetooth-address&gt; [ &lt;check-interval&gt; ]</code><br>
    <br>
    The default port is 5111 (presenced). Alternatly you can use port 5222 (collectord)<br>
    <br>
    <u>presenced</u><br><br>
    <ul>The presence is a perl network daemon, which provides presence checks of multiple bluetooth devices over network. 
    It listens on TCP port 5111 for incoming connections from a FHEM PRESENCE instance or a running collectord.<br>
<PRE>
Usage:
  presenced -d [-p &lt;port&gt;] [-P &lt;filename&gt;]
  presenced [-h | --help]


Options:
  -p, --port
     TCP Port which should be used (Default: 5111)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/presenced.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -v, --verbose
     Print detailed log output
  -h, --help
     Print detailed help screen
</PRE>
    
    It uses the hcitool command (provided by a <a href="http://www.bluez.org" target="_new">bluez</a> installation) 
    to make a paging request to the given bluetooth address (like 01:B4:5E:AD:F6:D3). The devices must not be visible, but
    still activated to receive bluetooth requests.<br><br>
    
    If a device is present, this is send to FHEM, as well as the device name as reading.<br><br>
    
    The presenced is available as:<br><br>
    <ul>
    <li>direct perl script file: <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/presenced" target="_new">presenced</a></li>
    <li>.deb package for Debian (noarch): <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/presenced-1.0.deb" target="_new">presenced-1.0.deb</a></li>
    <li>.deb package for Raspberry Pi (raspbian): <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/presenced-rpi-1.0.deb" target="_new">presenced-rpi-1.0.deb</a></li>
    </ul>
    </ul><br><br>
    <u>collectord</u><br><br>
    <ul>
    The collectord is a perl network daemon, which handles connections to several presenced installations to search for multiple bluetooth devices over network.<br><br>
    
    It listens on TCP port 5222 for incoming connections from a FHEM presence instance.
<PRE>
Usage:
  collectord -c &lt;configfile&gt; [-d] [-p &lt;port&gt;] [-P &lt;pidfile&gt;]
  collectord [-h | --help]


Options:
  -c, --configfile &lt;configfile&gt;
     The config file which contains the room and timeout definitions
  -p, --port
     TCP Port which should be used (Default: 5222)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/collectord.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -v, --verbose
     Print detailed log output
  -l, --logfile &lt;logfile&gt;
     log to the given logfile
  -h, --help
     Print detailed help screen
</PRE>  
    Before the collectord can be used, it needs a config file, where all different rooms, which have a presenced detector, will be listed. This config file looks like:
    <br><br>
<PRE>
       	# room definition
       	# ===============
	#
	[room-name]              # name of the room
	address=192.168.0.10     # ip-address or hostname
	port=5111                # tcp port which should be used (5111 is default)
	presence_timeout=120     # timeout in seconds for each check when devices are present
	absence_timeout=20       # timeout in seconds for each check when devices are absent

	[living room]
	address=192.168.0.11
	port=5111	
	presence_timeout=180
	absence_timeout=20    
</PRE>

    If a device is present in any of the configured rooms, this is send to FHEM, as well as the device name as reading and the room which has detected the device.<br><br>
    
    The collectord is available as:<br><br>
    
    <ul>
    <li>direct perl script file: <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/collectord" target="_new">collectord</a></li>
    <li>.deb package for Debian (noarch): <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/collectord-1.1.deb" target="_new">collectord-1.1.deb</a></li>
    </ul>
    </ul><br><br>

  </ul>
  <br>
  <a name="PRESENCEset"></a>
  <b>Set</b>
  <ul>
  <li><b>statusRequest</b> - (Only for local-bluetooth, lan-ping and fritzbox) - Schedules an immediatly check.</li>
  </ul>
  <br>

  <a name="PRESENCEget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>

  <a name="PRESENCEattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a>disable</a></li>
    If this attribute is activated, an active check will be disabled.<br><br>
    Possible values: 0 => not disabled , 1 => disabled<br>
    Default Value is 0 (not disabled)<br><br>
    <li><a>fritzbox_repeater</a></li> (Only in Mode "fritzbox" applicable)
    If your FritzBox is part of a network using repeaters, than this attribute needs to be enabled to ensure a correct recognition for devices, which are connected via repeater.
    <br><br>
    This attribute is also needed, if your network device has no speed information on the FritzBox website (Home Network).<br><br>
    <b>BE AWARE: The recognition of device going absent in a repeated network can take about 15 - 20 minutes!!</b>
    <br><br>
    Possible values: 0 => Use default recognition, 1 => Use repeater-supported recognition<br>
    Default Value is 0 (Use default recognition)

    <br><br>
    </ul>
  <br>
 
  <a name="PRESENCEevents"></a>
  <b>Generated Events:</b><br><br>
  <ul>
    <u>General Events:</u><br><br>
    <ul>
    <li><b>state</b>: $state (absent|present|disabled) - The state of the device or "disabled" when the disable attribute is enabled</li>
    </ul><br><br>
    <u>Bluetooth specific events:</u><br><br>
    <ul>
    <li><b>device_name</b>: $name - The name of the Bluetooth device in case it's present</li>
    </ul><br><br>
    <u>presenced/collectord specific events:</u><br><br>
    <ul>
    <li><b>command_accepted</b>: $command_accepted (yes|no) - Was the last command acknowleged and accepted by the presenced or collectord?</li>
    <li><b>room</b>: $room - If the module is connected with a collector daemon this event shows the room, where the device is located (as defined in the collectord config file)</li>
    </ul>
  </ul>
</ul>


=end html

=begin html_DE

<a name="PRESENCE"></a>
<h3>PRESENCE</h3>
<ul>
  <tr><td>
  Das PRESENCE Module bietet mehrere M&ouml;glichkteiten um die Anwesenheit von Handys/Smartphones oder anderen mobilen Ger&auml;ten (z.B. Tablets) zu erkennen.
  <br><br>
  Dieses Modul bietet dazu mehrere Modis an um Anwesenheit zu erkennen. Diese sind:<br><br>
  <ul>
  <li><b>lan-ping</b> - Eine Erkennung auf Basis von Ping-Tests im lokalen LAN/WLAN</li>
  <li><b>fritzbox</b> - Eine Erkennung aufgrund der internen Abfrage des Status auf der FritzBox (nur m&ouml;glich, wenn FHEM auf einer FritzBox l&auml;uft)</li>
  <li><b>local-bluetooth</b> - Eine Erkennung auf Basis von Bluetooth-Abfragen durch den FHEM Server. Das Ger&auml;t muss dabei in Empfangsreichweite sein, aber nicht sichtbar sein</li>
  <li><b>lan-bluetooth</b> - Eine Erkennung durch Bluetooth-Abfragen via Netzwerk (LAN/WLAN) in ein oder mehreren R&auml;umen</li>
  </ul>
  <br><br>
  <a name="PRESENCEdefine"></a>
  <b>Define</b><br><br>
  <ul><b>Modus: lan-ping</b><br><br>
    <code>define &lt;name&gt; PRESENCE lan-ping &lt;IP-Addresse oder Hostname&gt; [ &lt;Interval&gt; [ &lt;Anwesend-Interval&gt; ] ]</code><br>
    <br>
    Pr&uuml;ft ob ein Ger&auml;t &uuml;ber Netzwerk (&uuml;blicherweise WLAN) auf Ping-Anfragen reagiert und setzt entsprechend den Anwesenheitsstatus.<br>
    <br>
    <b>Modus: fritzbox</b><br><br>
    <code>define &lt;name&gt; PRESENCE fritzbox &lt;device-name&gt; [ &lt;Interval&gt; [ &lt;Anwesend-Interval&gt; ] ]</code><br>
    <br>
    Pr&uuml;ft ob ein Ger&auml;t welches per WLAN mit der FritzBox verbunden ist, erreichbar durch Abfrage des Status mit dem Befehl ctlmgr_ctl. 
    Der Ger&auml;tename (Parameter: &lt;device-name&gt;) muss dem Namen entsprechen, welcher im Men&uuml;punkt "Heimnetz" auf der FritzBox-Oberfl&auml;che angezeigt wird.<br>
    <br>
    <b>Modus: local-bluetooth</b><br><br>
    <code>define &lt;name&gt; PRESENCE local-bluetooth &lt;Bluetooth-Adresse&gt; [ &lt;Interval&gt; [ &lt;Anwesend-Interval&gt; ] ]</code><br>
    <br>
    Pr&uuml;ft ob ein Bluetooth-Ger&auml;t abgefragt werden kann und meldet dies als Anwesenheit. F&uuml;r diesen Modus wird der Shell-Befehl "hcitool" ben&ouml;tigt
    (wird durch das Paket <a href="http://www.bluez.org" target="_new">bluez</a> bereitgestellt), sowie ein funktionierender Bluetooth-Empf&auml;nger (intern oder als USB-Stick)<br><br>
    <b>Modus: lan-bluetooth</b><br><br>
    Pr&uuml;ft ein Bluetooth-Ger&auml;t auf Anwesenheit &uuml;ber Netzwerk mit Hilfe von presenced oder collectord. Diese k&ouml;nnen auf jeder Maschine installiert werden,
    welche eine Standard-Perl-Umgebung bereitstellt und &uuml;ber Netzwerk erreichbar ist.
    <br>
    <br>
    <code>define &lt;name&gt; PRESENCE &lt;IP-Adresse&gt;[:Port] &lt;Bluetooth-Adresse&gt; [ &lt;Interval&gt; ]</code><br>
    <br>
    Der Standardport ist 5111 (presenced). Alternativ kann man den Port 5222 (collectord) nutzen. Generell ist der Port aber frei w&auml;hlbar.<br>
    <br>
    <u>presenced</u><br><br>
    <ul>Der presenced ist ein Perl Netzwerk Dienst, welcher eine Bluetooth-Anwesenheitserkennung von ein oder mehreren Ger&auml;ten &uuml;ber Netzwerk bereitstellt. 
    Dieser lauscht standardm&auml;&szlig;ig auf TCP Port 5111 nach eingehenden Verbindungen von dem PRESENCE Modul oder einem collectord.<br>
<PRE>
Usage:
  presenced -d [-p &lt;port&gt;] [-P &lt;filename&gt;]
  presenced [-h | --help]


Options:
  -p, --port
     TCP Port which should be used (Default: 5111)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/presenced.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -v, --verbose
     Print detailed log output
  -h, --help
     Print detailed help screen
</PRE>
    
    Zur Bluetooth-Abfrage wird der Shell-Befehl "hcitool" verwendet (Paket: <a href="http://www.bluez.org" target="_new">bluez</a>) 
    um sogenannte "Paging-Request" an die gew&uuml;nschte Bluetooth Adresse (z.B. 01:B4:5E:AD:F6:D3) durchzuf&uuml;hren. Das Ger&auml;t muss dabei nicht sichtbar sein, allerdings st&auml;ndig aktiviert sein
    um Bluetooth-Anfragen zu beantworten.
    <br><br>
    
    Wenn ein Ger&auml;t anwesend ist, wird dies an FHEM &uuml;bermittelt zusammen mit dem Ger&auml;tenamen als Reading.<br><br>
    
    Der presenced ist zum Download verf&uuml;gbar als:<br><br>
    <ul>
    <li>Perl Skript: <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/presenced" target="_new">presenced</a></li>
    <li>.deb Paket f&uuml;r Debian (architekturunabh&auml;ngig): <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/presenced-1.0.deb" target="_new">presenced-1.0.deb</a></li>
    <li>.deb Paket f&uuml;r Raspberry Pi (raspbian): <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/presenced-rpi-1.0.deb" target="_new">presenced-rpi-1.0.deb</a></li>
    </ul>
    </ul><br><br>
    <u>collectord</u><br><br>
    <ul>
    Der collectord ist ein Perl Netzwerk Dienst, welcher Verbindungen zu mehreren presenced-Instanzen verwaltet um eine koordinierte Suche nach ein oder mehreren Bluetooth-Ger&auml;ten &uuml;ber Netzwerk durchzuf&uuml;hren.<br><br>
    
    Er lauscht auf TCP port 5222 nach eingehenden Verbindungen von einem PRESENCE Modul.
<PRE>
Usage:
  collectord -c &lt;configfile&gt; [-d] [-p &lt;port&gt;] [-P &lt;pidfile&gt;]
  collectord [-h | --help]


Options:
  -c, --configfile &lt;configfile&gt;
     The config file which contains the room and timeout definitions
  -p, --port
     TCP Port which should be used (Default: 5222)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/collectord.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -v, --verbose
     Print detailed log output
  -l, --logfile &lt;logfile&gt;
     log to the given logfile
  -h, --help
     Print detailed help screen
</PRE>  
    Bevor der collectord verwendet werden kann, ben&ouml;tigt er eine Konfigurationsdatei in welcher alle R&auml;ume mit einem presenced-Agenten eingetragen sind. Diese Datei sieht wie folgt aus:
    <br><br>
<PRE>
       	# Raum Definitionen
       	# =================
	#
	[Raum-Name]              # Name des Raumes
	address=192.168.0.10     # IP-Adresse oder Hostname
	port=5111                # TCP Port welcher benutzt werden soll (standardm&auml;&szlig;ig 5111)
	presence_timeout=120     # Pr&uuml;finterval in Sekunden f&uuml;r jede Abfrage eines Ger&auml;tes, welches anwesend ist
	absence_timeout=20       # Pr&uuml;finterval in Sekunden f&uuml;r jede Abfrage eines Ger&auml;tes, welches abwesend ist

	[Wohnzimmer]
	address=192.168.0.11
	port=5111	
	presence_timeout=180
	absence_timeout=20    
</PRE>
<br>
    Wenn ein Ger&auml;t in irgend einem Raum anwesend ist, wird dies an FHEM &uuml;bermittelt, zusammen mit dem Ger&auml;tenamen und dem Raum, in welchem das Ger&auml;t erkannt wurde.<br><br>
    
    Der collectord ist zum Download verf&uuml;gbar als:<br><br>
    
    <ul>
    <li>Perl Skript:  <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/collectord" target="_new">collectord</a></li>
    <li>.deb Paket f&uuml;r Debian (architekturunabh&auml;ngig):  <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/collectord-1.1.deb" target="_new">collectord-1.1.deb</a></li>
    </ul>
    </ul>

  </ul>
  <br>
  <a name="PRESENCEset"></a>
  <b>Set</b>
  <ul>
  
  <li><b>statusRequest</b> - (Nu f&uuml;r local-bluetooth, lan-ping and fritzbox) - Startet einen sofortigen Check.</li> 
  </ul>
  <br>

  <a name="PRESENCEget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>

  <a name="PRESENCEattr"></a>
  <b>Attributes</b><br><br>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a>disable</a></li>
    Wenn dieses Attribut aktiviert ist, wird die Anwesenheitserkennung nicht mehr durchgef&uuml;hrt.<br><br>
    M&ouml;gliche Werte: 0 => Erkennung durchf&uuml;hren , 1 => Keine Erkennungen durchf&uuml;hren<br>
    Standardwert ist 0 (Erkennung durchf&uuml;hren)<br><br>
    <li><a>fritzbox_repeater</a></li> (Nur im Modus "fritzbox" anwendbar)
    Wenn die FritzBox Teil eines Netzwerkes ist, welches mit Repeatern arbeitet, dann muss dieses Attribut gesetzt sein um die Erkennung von Ger&auml;ten zu gew&auml;hrleisten,
    welche &uuml;ber einen Repeater erreichbar sind.
    <br><br>
    Dies gilt ebenso f&uuml;r Devices, welche keine Geschwindigkeitsangaben auf der FritzBox Seite (Heimnetz) anzeigen k&ouml;nnen.<br><br>
    <b>ACHTUNG: Die Erkennung der Abwesenheit eines Ger&auml;tes in einem Repeater-Netzwerk kann ca. 15 - 20 Minuten dauern!!</b>
    <br><br>
    M&ouml;gliche Werte: 0 => Standarderkennung verwenden, 1 => Erkennung f&uuml;r Repeaterger&auml;te verwenden<br>
    Standardwert ist 0 (Standarderkennung verwenden)

    <br><br>
    </ul>
  <br>
 
  <a name="PRESENCEevents"></a>
  <b>Generierte Events:</b><br><br>
  <ul>
    <u>Generelle Events:</u><br><br>
    <ul>
    <li><b>state</b>: $state (absent|present|disabled) - Der Anwesenheitsstatus eine Ger&auml;tes (absent = abwesend; present = anwesend) oder "disabled" wenn das disable-Attribut aktiviert ist</li>
    </ul><br><br>
    <u>Bluetooth-spezifische Events:</u><br><br>
    <ul>
    <li><b>device_name</b>: $name - Der Name des Bluetooth-Ger&auml;tes, wenn es anwesend (Status: present) ist</li>
    </ul><br><br>
    <u>presenced-/collectord-spezifische Events:</u><br><br>
    <ul>
    <li><b>command_accepted</b>: $command_accepted (yes|no) - Wurde das letzte Kommando an den presenced/collectord akzeptiert (yes = ja, no = nein)?</li>
    <li><b>room</b>: $room - Wenn das Modul mit einem collectord verbunden ist, zeigt dieses Event den Raum an, in welchem dieses Ger&auml;t erkannt wurde (Raumname entsprechend der Konfigurationsdatei des collectord)</li>
    </ul>
  </ul>
</ul>


=end html_DE

=cut

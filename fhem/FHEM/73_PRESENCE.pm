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
use Net::Ping;
use Time::HiRes qw(gettimeofday);
use DevIo;



sub
PRESENCE_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "PRESENCE_Read";  
  $hash->{ReadyFn} = "PRESENCE_Ready";
  $hash->{GetFn}   = "PRESENCE_Get";
  $hash->{DefFn}   = "PRESENCE_Define";
  $hash->{UndefFn} = "PRESENCE_Undef";
  $hash->{AttrFn}  = "PRESENCE_Attr";
  $hash->{AttrList}= "do_not_notify:0,1 disable:0,1 loglevel:1,2,3,4,5 ".$readingFnAttributes;
  
}

#####################################
sub
PRESENCE_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);
  my $dev;
  
  if($a[2] ne "lan-bluetooth" and not (@a == 4 or @a == 5)) {
    my $msg = "wrong syntax: define <name> PRESENCE <mode> <device-address> [ <timeout> ]";
    Log 2, $msg;
    return $msg;
  }
  elsif(not (@a == 5 or @a == 6)) {
    my $msg = "wrong syntax: define <name> PRESENCE lan-bluetooth <bluetooth-device-address> <ip-address>[:port] [ <timeout> ]";
    Log 2, $msg;
    return $msg;
  }
  
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $destination = $a[2];
  my $address = $a[3];
  my $timeout = (defined($a[4]) ? $a[4] : 30);
 
  $timeout = (defined($a[5]) ? $a[5] : 30) if($destination eq "lan-bluetooth");
   
  
  $hash->{ADDRESS} = $address;
  $hash->{TIMEOUT} = $timeout;


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

    if(($destination eq "local-bluetooth" or $destination eq "lan-bluetooth") and not $address =~ /^\s*([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\s*$/)
    {
        my $msg = "given address is not a bluetooth hardware address";
	Log 2, "PRESENCE: ".$msg;
	return $msg
    }
  
  if($destination eq "lan-ping" or $destination eq "local-bluetooth")
  {
 
   $hash->{MODE} = $destination;
   PRESENCE_StartLocalScan($hash);
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
	if(defined($hash->{FD}))
	{
	    PRESENCE_DoInit($hash);	    
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
    if(defined($hash->{FD}))
    {
        PRESENCE_DoInit($hash);
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

    DevIo_SimpleWrite($hash, $hash->{ADDRESS}."|".$hash->{TIMEOUT}."\n", 0) unless($hash->{helper}{DISABLED});

}


sub
PRESENCE_Ready($)
{
   my ($hash) = @_;
       
   return DevIo_OpenDev($hash, 1, "PRESENCE_DoInit");

}

##########################################################################################################################
#
# 
#  Functions for local testing with Blocking.pm to ensure a smooth FHEM processing
#
#
sub 
PRESENCE_StartLocalScan($)
{
my ($hash) = @_;


    if($hash->{MODE} eq "local-bluetooth")
    {

	BlockingCall("PRESENCE_DoLocalBluetoothScan", $hash->{NAME}."|".$hash->{ADDRESS}, "PRESENCE_ProcessLocalScan", 20);
    }
    elsif($hash->{MODE} eq "lan-ping")
    {
	BlockingCall("PRESENCE_DoLocalPingScan", $hash->{NAME}."|".$hash->{ADDRESS}, "PRESENCE_ProcessLocalScan", 20);

    }
}

sub
PRESENCE_DoLocalPingScan($$)
{

    my ($string) = @_;
    my ($name, $device) = split("\\|", $string);

    my $pingtool = Net::Ping->new();
    my $retcode;
    my $return;


    if($pingtool)
    {

	$retcode = $pingtool->ping($device, 5);
	$return = "$name|".($retcode ? "present" : "absent"); 

    }
    else
    {
	$return = "$name|error|Could not create a Net::Ping object.";
    }

return $return;

}


sub
PRESENCE_DoLocalBluetoothScan($$)
{
    my ($string) = @_;
    my ($name, $device) = split("\\|", $string);
    my $hcitool = qx(which hcitool);
    my $devname;
    my $return;
    my $wait = 1;
    my $ps;
    
    if($hcitool)
    {
        while($wait)
        {   # check if another hcitool process is running
    	   $ps = qx(ps ax | grep hcitool | grep -v grep);
    	   if(not $ps =~ /^\s*$/)
    	   {
    	     # sleep between 1 and 5 seconds and try again
    	     sleep(rand(4)+1);
    	   }
    	   else
    	   {
    	     $wait = 0;
    	   }
    	 }
    	   
	$devname = qx(hcitool name $device);
	chomp($devname);
    
	if(not $devname =~ /^\s*$/)
	{
	    $return = "$name|present|$devname";
	}
	else
	{
	    $return = "$name|absent";
	}
    }
    else
    {
	$return = "$name|error|no hcitool binary found. Please check that the bluez-package is properly installed";
    }

    return $return;
}





sub
PRESENCE_ProcessLocalScan($)
{
 my ($string) = @_;
 my @a = split("\\|",$string);
 
 my $hash = $defs{$a[0]};
 
 return if($hash->{helper}{DISABLED});
 
 
 readingsBeginUpdate($hash);
 if($a[1] eq "present")
 {
    readingsBulkUpdate($hash, "state", "present");
    readingsBulkUpdate($hash, "device_name", $a[2]) if(defined($a[2]));
 }
 elsif($a[1] eq "absent")
 {
    readingsBulkUpdate($hash, "state", "absent");
 }
 elsif($a[1] eq "error")
 {
    Log GetLogLevel($hash->{NAME}, 2), "PRESENCE: error while processing device ".$hash->{NAME}." - ".$a[2];
 }


 readingsEndUpdate($hash, 1);

 #Schedule the next check withing $timeout
 RemoveInternalTimer($hash);
 InternalTimer(gettimeofday()+$hash->{TIMEOUT}, "PRESENCE_StartLocalScan", $hash, 1) unless($hash->{helper}{DISABLED});
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
  <li><b>local-bluetooth</b> - A presence check by searching directly for a given bluetooth device nearby</li>
  <li><b>lan-bluetooth</b> - A presence check of a bluetooth device via LAN network by connecting to a presenced or collectord instance</li>
  </ul>
  <br><br>
  <a name="PRESENCEdefine"></a>
  <b>Define</b><br><br>
  <ul><b>Mode: lan-ping</b><br><br>
    <code>define &lt;name&gt; PRESENCE lan-ping &lt;ip-address&gt; [ &lt;timeout&gt; ]</code><br>
    <br>
    Checks for a network device via PING requests and reports its presence state.<br>
    <br>
    <b>Mode: local-bluetooth</b><br><br>
    <code>define &lt;name&gt; PRESENCE local-bluetooth &lt;bluetooth-address&gt; [ &lt;timeout&gt; ]</code><br>
    <br>
    Checks for a bluetooth device and reports its presence state. For this mode the shell command "hcitool" is required (provided with a <a href="http://www.bluez.org" target="_new">bluez</a> installation under Debian via APT), as well
    as a functional bluetooth device directly attached to your machine.<br><br>
    <b>Mode: lan-bluetooth</b><br><br>
    Checks for a bluetooth device with the help of presenced or collectord. They can be installed where-ever you like, just must be accessible via network.
     The given device will be checked for presence status.<br>
    <br>
    <code>define &lt;name&gt; PRESENCE &lt;ip-address&gt;[:port] &lt;bluetooth-address&gt; [ &lt;timeout&gt; ]</code><br>
    <br>
    The default port is 5111 (presenced). Alternatly you can use port 5222 (collectord)<br>
    <br>
    <u>presenced</u><br><br>
    <ul>The presence is a perl network daemon, which provides presence checks of multiple bluetooth devices over network. 
    It listens on TCP port 5111 for incoming connections from a FHEM PRESENCE instance or a running collectord.<br>
<PRE>
Usage:
  presenced -d [-p <port>] [-P <filename>]
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
  collectord -c <configfile> [-d] [-p <port>] [-P <pidfile>]
  collectord [-h | --help]


Options:
  -c, --configfile <configfile>
     The config file which contains the room and timeout definitions
  -p, --port
     TCP Port which should be used (Default: 5222)
  -P, --pid-file
     PID file for storing the local process id (Default: /var/run/collectord.pid)
  -d, --daemon
     detach from terminal and run as background daemon
  -v, --verbose
     Print detailed log output
  -l, --logfile <logfile>
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
    <li>.deb package for Debian (noarch): <a href="http://fhem.svn.sourceforge.net/viewvc/fhem/trunk/fhem/contrib/PRESENCE/deb/collectord-1.0.deb" target="_new">collectord-1.0.deb</a></li>
    </ul>
    </ul><br><br>

  </ul>
  <br>
  <a name="PRESENCEset"></a>
  <b>Set</b>
  <ul>
  N/A 
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
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li><br>
    <li><a>disable</a></li>
    If this attribute is activated, an active check will be disabled.<br><br>
    Possible values: 0 => not disabled , 1 => disabled<br>
    Default Value is 0 (not disabled)<br><br>
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
    <li><b>name</b>: $name - The name of the Bluetooth device in case it's present</li>
    </ul><br><br>
    <u>presenced/collectord specific events:</u><br><br>
    <ul>
    <li><b>command_accepted</b>: $command_accepted (yes|no) - Was the last command acknowleged and accepted by the presenced or collectord</li>
    <li><b>room</b>: $room - If the module is connected with a collector daemon this event shows the room, where the device is located (as defined in the collectord config file)</li>
    </ul>
  </ul>
</ul>


=end html

=cut

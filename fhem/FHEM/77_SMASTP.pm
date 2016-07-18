###############################################################
# $Id$
#
#  Copyright notice
#
#  (c) 2016 Copyright: Volker Kettenbach (volker at kettenbach minus it dot de)
#
#  Credits:
#  - based on an Idea by SpenZerX and HDO
#  - Waldmensch for various improvements
#  - sbfspot (https://sbfspot.codeplex.com/)
#
#  Description:
#  This is an FHEM-Module for the SMA Sunny Tripower Inverter.
#  Tested on Sunny Tripower 6000TL-20, 10000-TL20 and 10000TL-10 with
#  Speedwire/Webconnect Piggyback
#
#  Requirements:
#  This module requires:
#  - Perl Module: IO::Socket::INET
#  - Perl Module: Datime
#
#  Origin:
#  https://github.com/kettenbach-it/FHEM-SMA-Speedwire
#
###############################################################

package main;

use strict;
use warnings;
use IO::Socket::INET;      
use DateTime;

# Global vars
my $cmd_login			= "534d4100000402a000000001003a001060650ea0ffffffffffff00017800C8E8033800010000000004800c04fdff07000000840300004c20cb5100000000encpw00000000";
my $cmd_logout			= "534d4100000402a00000000100220010606508a0ffffffffffff00037800C8E80338000300000000d7840e01fdffffffffff00000000";
my $cmd_query_total_today	= "534d4100000402a00000000100260010606509e0ffffffffffff00007800C8E80338000000000000f1b10002005400002600ffff260000000000";
my $cmd_query_spot_ac_power	= "534d4100000402a00000000100260010606509e0ffffffffffff00007800C8E8033800000000000081f00002005100002600ffff260000000000";
my $cmd_query_spot_dc_power	= "534d4100000402a00000000100260010606509e0ffffffffffff00007800C8E8033800000000000081f00002805300002500ffff260000000000";
my $averagebuf			= "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

my $code_login			= "0d04fdff";	#0xfffd040d;
my $code_total_today		= "01020054";	#0x54000201;
my $code_spot_ac_power		= "01020051";	#0x51000201;
my $code_spot_dc_power 		= "01028053";	#0x53800201;

my $default_starthour = "05:00";
my $starthour = 5;
my $startminute = 0;
my $default_endhour = "22:00";
my $endhour = 22;
my $endminute = 0;

my $force_sleep = 0;
my $sleep_forced = 0;

my $suppress_night_mode = 0;
my $suppress_inactivity_mode = 0;

my $modulstate_enabled = 0;
my ($alarm_value1,$alarm_value2,$alarm_value3);


###################################
sub SMASTP_Initialize($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $hval;
	my $mval;

	$hash->{DefFn}     = "SMASTP_Define";
	$hash->{UndefFn}   = "SMASTP_Undef";
	$hash->{AttrList}  = "suppress-night-mode:0,1 " .
						"suppress-inactivity-mode:0,1 " .
						"starttime " .
						"endtime " .
						"force-sleepmode:0,1 " .
						"enable-modulstate:0,1 " .
						"alarm1-value " .
						"alarm2-value " .
						"alarm3-value " .
						"interval " . 
						$readingFnAttributes;
	$hash->{AttrFn}   = "SMASTP_Attr";
	
	if ($attr{$name}{"starttime"})
	{
		($hval, $mval) = split(/:/,$attr{$name}{"starttime"});
	}
	else
	{
		($hval, $mval) = split(/:/,$default_starthour);
	}
	$starthour = int($hval);
	$startminute = int($mval);
	
	if ($attr{$name}{"endtime"})
	{
		($hval, $mval) = split(/:/,$attr{$name}{"endtime"});
	}
	else
	{
		($hval, $mval) = split(/:/,$default_endhour);
	}
	$endhour = int($hval);
	$endminute = int($mval);

	$suppress_night_mode = ($attr{$name}{"suppress-night-mode"}) ? $attr{$name}{"suppress-night-mode"} : 0;
	$suppress_inactivity_mode = ($attr{$name}{"suppress-inactivity-mode"}) ? $attr{$name}{"suppress-inactivity-mode"} : 0;
	$force_sleep = ($attr{$name}{"force-sleepmode"}) ? $attr{$name}{"force-sleepmode"} : 0;
	$modulstate_enabled = ($attr{$name}{"enable-modulstate"}) ? $attr{$name}{"enable-modulstate"} : 0;
	
	$alarm_value1 = ($attr{$name}{"alarm1-value"}) ? $attr{$name}{"alarm1-value"} : 0;
	$alarm_value2 = ($attr{$name}{"alarm2-value"}) ? $attr{$name}{"alarm2-value"} : 0;
	$alarm_value3 = ($attr{$name}{"alarm3-value"}) ? $attr{$name}{"alarm3-value"} : 0;
	
	Log3 $name, 0, "$name: Started with sleepmode from $endhour:$endminute - $starthour:$startminute";
}

###################################
sub is_Sleepmode()
{
	# Build 3 DateTime Objects to make the comparison more robust
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $dt_startdate = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>$starthour,minute=>$startminute,second=>0,time_zone=>'local');
	my $dt_enddate = DateTime->new(year=>$year+1900,month=>$mon+1,day=>$mday,hour=>$endhour,minute=>$endminute,second=>0,time_zone=>'local');
	my $dt_now = DateTime->now(time_zone=>'local');

	# Return of any value != 0 means "sleeping"
	if ($dt_now >= $dt_enddate || $dt_now <= $dt_startdate)
	{
		# switch forced sleepmode off because we have reached normal sleepmode now
		$sleep_forced = 0;			
		return 1;
	}
	elsif ($sleep_forced == 1)
	{
		# 2 = forced sleep
		return 2;					
	}
	else
	{
		return 0;
	}
}

###################################
sub SMASTP_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	return "Wrong syntax: use define <name> SMASTP <inv-userpwd> <inv-hostname/inv-ip > " if ((int(@a) < 4) and (int(@a) > 5));

	my $name	= $a[0];
	$hash->{NAME} 	= $name;
	$hash->{LASTUPDATE}=0;
	$hash->{INTERVAL} = 60;

	# SMASTP	= $a[1];
	my ($IP,$Host,$Caps);

	my $Pass = $a[2];		# to do: check 1-12 Chars

	# extract IP or Hostname from $a[4]
	if ( $a[3] ~~ m/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ )
	{
	if ( $1 <= 255 && $2 <= 255 && $3 <= 255 && $4 <= 255 )
		{
			$Host = int($1).".".int($2).".".int($3).".".int($4);
		}
	}
	
	if (!defined $Host)
	{
		if ( $a[3] =~ /^([A-Za-z0-9_.])/ )
		{
			$Host = $a[3];
		}
	}
	
	if (!defined $Host)
	{
		return "Argument:{$a[3]} not accepted as Host or IP. Read device specific help file.";
	}

	$hash->{Pass} = $Pass; 
	$hash->{Host} = $Host;


	# Use C8E80338, but NOT the number of the Inverter!
	# my $src_serial = 939780296;		

	my $encpw = "888888888888888888888888"; # unencoded pw
	for my $index (0..length $Pass )	# encode password
	{
		substr($encpw,($index*2),2) = substr(sprintf ("%lX", (hex(substr($encpw,($index*2),2)) + ord(substr($Pass,$index,1)))),0,2);
	}
	
	$cmd_login =~ s/encpw/$encpw/g;		#replace the placeholder with password

	InternalTimer(gettimeofday()+5, "SMASTP_GetStatus", $hash, 0);	# refresh timer start

	return undef;
}

#####################################
sub SMASTP_Undef($$)
{
	my ($hash, $name) = @_;
	RemoveInternalTimer($hash); 
	Log3 $hash, 0, "$name: Undefined!";
	return undef;
}

###################################
sub SMASTP_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;
  	# $cmd can be "del" or "set"
	# $name is device name
	# aName and aVal are Attribute name and value
	my $hash = $defs{$name};
	
	my $hval;
	my $mval;

	if (($aName eq "starttime" || $aName eq "endtime") && not ($aVal =~ /^([0-1]?[0-9]|[2][0-3]):([0-5][0-9])$/))
	{
		return "value $aVal invalid"; # no correct time format hh:mm
	}
	
	if ($aName eq "enable-modulstate")
	{
		$modulstate_enabled  = ($cmd eq "set") ?  int($aVal) : 0;
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}
	
	if ($aName eq "alarm1-value")
	{
		$alarm_value1  = ($cmd eq "set") ?  int($aVal) : 0;
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}
	
	if ($aName eq "alarm2-value")
	{
		$alarm_value2  = ($cmd eq "set") ?  int($aVal) : 0;
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}
	
	if ($aName eq "alarm3-value")
	{
		$alarm_value3  = ($cmd eq "set") ?  int($aVal) : 0;
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}
	
	if ($aName eq "starttime")
	{
		if ($cmd eq "set")
		{
			($hval, $mval) = split(/:/,$aVal);
		}
		else
		{
			($hval, $mval) = split(/:/,$default_starthour);
		}
		if (int($hval) < 12)
		{
			$starthour = int($hval);
			$startminute = int($mval);
		}
		else
		{
			return "$name: Attr starttime must be set smaller than 12:00! Not set to $starthour:$startminute";
		}
		
		Log3 $name, 3, "$name: Attr starttime is set to " . sprintf("%02d:%02d",$starthour,$startminute);
	}
	
	if ($aName eq "endtime")
	{
		if ($cmd eq "set")
		{
			($hval, $mval) = split(/:/,$aVal);
		}
		else
		{
			($hval, $mval) = split(/:/,$default_endhour);
		}
		
		if (int($hval) > 12)
		{
			$endhour = int($hval);
			$endminute = int($mval);
		}
		else
		{
			return "$name: Attr endtime must be set larger than 12:00! Not set to $endhour:$endminute";
		}
		
		Log3 $name, 3, "$name: Attr endtime is set to " . sprintf("%02d:%02d",$endhour,$endminute);
	}
	
	if ($aName eq "suppress-night-mode") 
	{
		$suppress_night_mode = ($cmd eq "set") ? $aVal : 0;
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}
	
	if ($aName eq "suppress-inactivity-mode") 
	{
		$suppress_inactivity_mode = ($cmd eq "set") ? $aVal : 0;
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}

	if ($aName eq "force-sleepmode") 
	{
		if ($cmd eq "set")
		{
			$force_sleep = $aVal;
			$sleep_forced = ($aVal == 0) ? 0 : $sleep_forced;
			Log3 $name, 3, "$name: Set $aName to $aVal";
		}
		else
		{
			$force_sleep = 0;
			$sleep_forced = 0;
		}
	}

	if ($aName eq "interval") 
	{
		if ($cmd eq "set") 
		{
			$hash->{INTERVAL} = $aVal;
			Log3 $name, 3, "$name: Set $aName to $aVal";
		}
	} else 
	{
		$hash->{INTERVAL} = "60";
		Log3 $name, 3, "$name: Set $aName to $aVal";
	}
	return undef;
}

#####################################
sub SMASTP_GetStatus($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	if (defined($attr{$name}{"interval"})) {
		$hash->{INTERVAL} = $attr{$name}{"interval"};
	} else {
		$hash->{INTERVAL} = 60;
	}

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	
	if ($suppress_night_mode == 0)
	{
		if(is_Sleepmode() > 0)
		{
			Log3 $name, 5, "$name: " . 
							sprintf("%02d:%02d",$hour,$min) . 
							" is out of working hours " . 
							sprintf("%02d:%02d",$starthour,$startminute) . 
							" - " . 
							sprintf("%02d:%02d",$endhour,$endminute) . 
							" " .
							(($sleep_forced == 1) ? " FORCED" : "");
			
			my $modulstate = ($hash->{READINGS}{modulstate}{VAL}) ? $hash->{READINGS}{modulstate}{VAL} : "unknown";
			if($modulstate ne "sleeping" && $modulstate_enabled == 1)
			{
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "modulstate", "sleeping");
				readingsEndUpdate($hash, 1);
			}
				
			InternalTimer(gettimeofday()+$hash->{INTERVAL}, "SMASTP_GetStatus", $hash, 1);
			return;
		}
	}
	
	use constant MAXBYTES => scalar 200; #1024 #80
	
	my $Host = $hash->{Host};
	my $interval = $hash->{INTERVAL};
	# my $averagebuf = $hash->{averagebuf};

	my ($AvP01,$AvP05,$AvP15,$TodayTotal,$SpotPower,$AlltimeTotal,$statusval,$PDC1,$PDC2);
	my ($socket,$data,$size,$code);
	my $error = 0;

	# flush after every write
	$| = 1; 				

	$socket = new IO::Socket::INET (PeerHost => $Host, PeerPort => 9522, Proto => 'udp',); # open Socket

	if (!$socket) { 															
		# in case of error
		Log3 $name, 1, "$name: ERROR. Can't open socket to inverter: $!";
		return undef;
	};

	# send login command
	Log3 $name, 2, "$name: Sending query to inverter $Host:9522";
	$data = pack "H*",$cmd_login;										
	$socket->send($data);
 
	do 
	{	
		eval 
		{
			local $SIG{ALRM} = sub { die "alarm time out" };
			alarm 5;
			# receive data
			$socket->recv($data, MAXBYTES) or die "recv: $!";					
			$size = length($data);

			# too little data - exit loop
			if ((defined $size) && ($size > 60))															
			{
				my $received = unpack("H*", $data);
				Log3 $name, 5, "$name: Received: ($received)";
			} else {
				if($size > 0)
				{
					my $received = unpack("H*", $data);
					Log3 $name, 5, "$name: Received Garbage: ($received)";
				}
			}
			
			alarm 0;
			1;																	
		} or Log3 $name, 1, "$name query timed out";
		
		# too little data -> exit loop
		if ((not defined $size) || ($size < 60))															
		{
			Log3 $name, 1, "$name: Too little data received (Len:".((not defined $size) ? "NaN/timeout" : $size).")";
			# send: cmd_logout
			$data = pack "H*",$cmd_logout;								
			$size = $socket->send($data);
			$socket->close();
			$error = 1;
		}
		else
		{
			# unpack command
			$code = unpack("H*", substr $data, 42, 4);								

			# answer to command login
			if  ($code_login eq $code)												
			{
				# send: Query total today
				$data = pack "H*",$cmd_query_total_today;					
				$size = $socket->send($data);
			} 

			# answer to command total today
			if  ($code_total_today eq $code)
			{
				$TodayTotal  = unpack("V*", substr $data, 78, 4);
				$AlltimeTotal  = unpack("V*", substr $data, 62, 4);
				# send: Query spot power
				$data = pack "H*",$cmd_query_spot_ac_power;					
				$size = $socket->send($data);
			}
			
			# answer to command AC Power
			if  ($code_spot_ac_power eq $code)										
			{
				$SpotPower  = unpack("V*", substr $data, 62, 4);
				# special case at night ? Inverter off?
				if ($SpotPower eq 0x80000000) {$SpotPower = 0};						
				# send: query spot DC power
				$data = pack "H*",$cmd_query_spot_dc_power;					
				$size = $socket->send($data);
			}
			
			# answer to command DC Power
			if  ($code_spot_dc_power eq $code)										
			{
				$PDC1 = unpack("V*", substr $data, 62, 4);
				if ($PDC1 eq 0x80000000) {$PDC1 = 0};
				$PDC2 = unpack("V*", substr $data, 90, 4);
				if ($PDC2 eq 0x80000000) {$PDC2 = 0};
				# send: cmd_logout
				$data = pack "H*",$cmd_logout;								
				$size = $socket->send($data);
				# close Socket
				$socket->close();													
			}
		}
		
	} while (($code_spot_dc_power ne $code) && ($error eq 0)); # answer to command spot_ac_power

	if ($error ne 1)															
	{
		if ( (int(hex(substr($averagebuf,0*8,8)))) eq 0)
		{
			for my $count (0..15)
			{
				# fill with new values
				substr($averagebuf,$count*8,1*8) = substr(sprintf ("%08X",$AlltimeTotal),0,8);	
			}
		}

		# average buffer shiften und mit neuem Wert füllen
		substr($averagebuf,1*8,15*8) = substr($averagebuf,0*8,15*8);							
		# und mit neuem Wert füllen
		substr($averagebuf,0*8,1*8) = substr(sprintf ("%08X",$AlltimeTotal),0,8);				
		$AvP01 = int( ( (hex(substr($averagebuf,0*8,8))) - (hex(substr($averagebuf,1*8,8)))  ) * ((3600 / 01) / $interval) );
		$AvP05 = int( ( (hex(substr($averagebuf,0*8,8))) - (hex(substr($averagebuf,5*8,8)))  ) * ((3600 / 05) / $interval) );
		$AvP15 = int( ( (hex(substr($averagebuf,0*8,8))) - (hex(substr($averagebuf,15*8,8))) ) * ((3600 / 15) / $interval) );

		$statusval = "SP:$SpotPower W  AvP1:$AvP01 W  TTP:$TodayTotal Wh  ATP:$AlltimeTotal Wh";

		Log3 $name, 4, "$name: from ($Host): ($statusval) ";
		
		Log3 $name, 5, "$name: AvP05 = $AvP05, SpotPower = $SpotPower, AvP15 = $AvP15";
		#Filter out error zero values and stop readingsupdate after 15 Mins on zero power
		if ( ((not ($AvP05 > 0 && $SpotPower == 0)) && $AvP15 > 0) || $suppress_inactivity_mode == 1 || $hash->{LASTUPDATE} eq 0)
		{
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "state", $statusval);			# Status Overview
			readingsBulkUpdate($hash, "SpotP", $SpotPower);			# Momentary Spot Power
			readingsBulkUpdate($hash, "SpotPDC1", $PDC1);			# Momentary Spot DC Power String1
			readingsBulkUpdate($hash, "SpotPDC2", $PDC2);			# Momentary Spot DC Power String2
			readingsBulkUpdate($hash, "TodayTotalP", $TodayTotal);		# Today Total Power
			readingsBulkUpdate($hash, "AlltimeTotalP", $AlltimeTotal);	# Alltime Total Power
			readingsBulkUpdate($hash, "AvP01", $AvP01);			# Average Power (last) 1 Minute (if delay 60)
			readingsBulkUpdate($hash, "AvP05", $AvP05);			# Average Power (last) 5 Minutes (if delay 60)
			readingsBulkUpdate($hash, "AvP15", $AvP15);			# Average Power (last) 15 Minutes (if delay 60)
			readingsBulkUpdate($hash, "modulstate", "normal");

			if($alarm_value1 > 0 && $SpotPower > $alarm_value1) { readingsBulkUpdate($hash, "Alarm1", 1); }
			elsif ($alarm_value1 > 0 && $SpotPower < $alarm_value1) { readingsBulkUpdate($hash, "Alarm1", (-1)); }
			else	{ readingsBulkUpdate($hash, "Alarm1", 0);	}
			
			if($alarm_value2 > 0 && $SpotPower > $alarm_value2) { readingsBulkUpdate($hash, "Alarm2", 1); }
			elsif ($alarm_value2 > 0 && $SpotPower < $alarm_value2) { readingsBulkUpdate($hash, "Alarm2", (-1)); }
			else { readingsBulkUpdate($hash, "Alarm2", 0); }
			
			if($alarm_value3 > 0 && $SpotPower > $alarm_value3) { readingsBulkUpdate($hash, "Alarm3", 1); }
			elsif ($alarm_value3 > 0 && $SpotPower < $alarm_value3) { readingsBulkUpdate($hash, "Alarm3", (-1)); }
			else { readingsBulkUpdate($hash, "Alarm3", 0); }
			
			readingsEndUpdate($hash, 1);	# Notify is done by Dispatch
			
			$hash->{LASTUPDATE} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;	
			Log3 $name, 5, "$name: Readings updated";
		}
		else
		{
			if ($AvP15 == 0 && $SpotPower == 0 && $force_sleep == 1 && $sleep_forced == 0 && $hour > 12)
			{
				$sleep_forced = 1;
				Log3 $name, 1, "$name: sleepmode forced after 15 minutes zero power";
			}

			my $modulstate = ($hash->{READINGS}{modulstate}{VAL}) ? $hash->{READINGS}{modulstate}{VAL} : "";
			if($modulstate ne "inactive" && $modulstate_enabled == 1)
			{
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "modulstate", "inactive");
				readingsEndUpdate($hash, 1);
			}
			
			Log3 $name, 5, "$name: Readings not updated";
		}
	}
	InternalTimer(gettimeofday()+$interval, "SMASTP_GetStatus", $hash, 1);
	#return undef;
}

1;

=pod

=begin html

<a name="SMASTP"></a>
<h3>SMASTP</h3>

Module for the integration of a Sunny Tripower Inverter build by SMA over it's Speedwire (=Ethernet) Interface.<br>
Tested on Sunny Tripower 6000TL-20, 10000-TL20 and 10000TL-10 with Speedwire/Webconnect Piggyback.

<p>

<b>Define</b>
<ul>
<code>define &lt;name&gt; SMASTP &lt;pin&gt; &lt;hostname/ip&gt; [port]</code><br>
<br>
<li>pin: User-Password of the SMA STP Inverter. Default is 0000. Can be changed by "Sunny Explorer" Windows Software</li>
<li>hostname/ip: Hostname or IP-Adress of the inverter (or it's speedwire piggyback module).</li>
<li>port: Port of the inverter. 9522 by default.</li>
</ul>

<p>

<b>Modus</b>
<ul>
The module automatically detects the inactvity of the inverter due to a lack of light (night). <br>
This inactivity is therefore called "nightmode". During nightmode, the inverter is not queried over the network.<br>
By default nightmode is between 9pm and 5am. This can be changed by "starttime" (start of inverter <br>
operation, end of nightmode) and "endtime" (end of inverter operation, start of nightmode).<br>
Further there is the inactivitymode: in inactivitymode, the inverter is queried but readings are not updated.
</ul>

<b>Parameter</b>
<ul>
	<li>interval: Queryintreval in seconds </li>
	<li>suppress-night-mode: The nightmode is deactivated </li>
	<li>suppress-inactivity-mode: The inactivitymode is deactivated </li>
	<li>starttime: Starttime of inverter operation (default 5am)  </li>
	<li>endtime: Endtime of inverter operation (default 9pm) </li>
	<li>force-sleepmode: The nightmode is activated on inactivity, even the endtime is not reached </li>
	<li>enable-modulstate: Turns the reading "modulstate" (normal / inactive / sleeping) on </li>
	<li>alarm1-value, alarm2-value, alarm3-value: Set an alarm on the reading SpotP in watt.<br> 
	The readings Alarm1..Alarm3 are set accordingly: -1 for SpotP < alarmX-value and 1 for SpotP >= alarmX-value </li>
</ul>

<b>Readings</b>
 <ul>
	<li>SpotP: spotpower - Current power in watt delivered by the inverter </li>
	<li>AvP01: average power 1 minute: average power in watt of the last minute </li>
	<li>AvP05: average power 5 minutes: average power in watt of the five minutes </li>
	<li>AvP15: average power 15 minutes: average power in watt of the fifteen minutes </li>
	<li>SpotPDC1: current d.c. voltage delivered by string 1 </li>
	<li>SpotPDC2: current d.c. voltage delivered by string 2 </li>
	<li>TotalTodayP: generated power in Wh of the current day </li>
	<li>AlltimeTotalP: all time generated power in Wh </li>
	<li>Alarm1..3: alrm trigger 1..3. Set by parameter alarmN-value </li>
 </ul>


=end html


=begin html_DE

<a name="SMASTP"></a>
<h3>SMASTP</h3>

Modul zur Einbindung eines Sunny Tripower Wechselrichters der Firma SMA über Speedwire (Ethernet).<br>
Getestet mit Sunny Tripower 6000TL-20, 10000-TL20 sowie 10000TL-10 mit  Speedwire/Webconnect Piggyback

<p>

<b>Define</b>
<ul>
<code>define &lt;name&gt; SMASTP &lt;pin&gt; &lt;hostname/ip&gt; [port]</code><br>
<br>
<li>pin: Benutzer-Passwort des SMA STP Wechselrichters. Default ist 0000. Kann über die Windows-Software "Sunny Explorer" geändert werden </li>
<li>hostname/ip: Hostname oder IP-Adresse des Wechselrichters (bzw. dessen Speedwire Moduls mit Ethernetanschluss) </li>
<li>port: Optional der Ports des Wechselrichters. Per default 9522. </li>
</ul>

<p>

<b>Modus</b>
<ul>
Das Modul erkennt automatisch eine Inaktivität des Wechselrichters, wenn dieser aufgrund Dunkelheit seinen Betrieb einstellt. <br>
Diese Betriebspause wird als "Nightmode" bezeichnet. Im Nightmode wird der Wechelrichter nicht mehr über das Netzwerk abgefragt.<br>
Per default geht das Modul davon aus, dass vor 5:00 und nach 21:00 der Nightmode aktiv ist.<br>
Diese Grenzen lassen sich mit den Parametern "starttime" (Start des Wechelrichterbetriebs, also Ende des Nightmode) <br>
und "endtime" (Ende des Wechselrichterbetriebs, also Beginn des Nightmode) umdefinieren. <br>
Darüber hinaus gibt es den "Inactivitymode": hier wird der Wechselrichter abgefragt, aber es werden keine Readings mehr aktualisiert. <br>
</ul>

<b>Parameter</b>
<ul>
	<li>interval: Abfrageinterval in Sekunden </li>
	<li>suppress-night-mode: Der Nightmode wird deaktiviert </li>
	<li>suppress-inactivity-mode: Der Inactivitymode wird deaktiviert </li>
	<li>starttime: Startzeit des Betriebsmodus (Default 5:00 Uhr) </li>
	<li>endtime: Endezeit des Betriebsmodus (Default 21:00 Uhr) </li>
	<li>force-sleepmode: Der Nightmode wird bei entdeckter Inaktivität auch dann aktiviert, wenn endtime noch nicht erreicht ist </li>
	<li>enable-modulstate: Schaltet das reading "modulstate" (normal / inactive / sleeping) ein </li>
	<li>alarm1-value, alarm2-value, alarm3-value: Setzt einen Alarm in Watt auf das Reading SpotP.  
	<br>Die Readings Alarm1..Alarm3 werden entsprechend gesetzt: -1 für SpotP < alarmX-value und 1 für Spot >= alarmX-value. </li>
</ul>

<b>Readings</b>
 <ul>
	<li>SpotP: SpotPower - Leistung in W zum Zeitpunkt der Abfrage</li> 
	<li>AvP01: Average Power 1 Minute - Durchschnittliche Leistung in W der letzten Minute</li>
	<li>AvP05: Average Power 5 Minuten - Durchschnittliche Leistung in W der letzten 5 Minuten</li>
	<li>AvP15: Average Power 15 Minuten - Durchschnittliche Leistung in W der letzten 15 Minuten</li> 
	<li>SpotPDC1: Spot Gleichspannung String 1 </li>
	<li>SpotPDC2: Spot Gleichspannung String 2 </li>
	<li>TotalTodayP: Erzeuge Leistung (in Wh) des heutigen Tages </li>
	<li>AlltimeTotalP: Erzeugte Leistung (in Wh) seit Inbetriebsnahme des Gerätes </li>
	<li>Alarm1..3: Alarm Trigger 1-3. Können über die Parameter "alarmN-value" gesetzt werden </li>
 </ul>


=end html_DE

################################################################
# $Id$
#
#  Copyright notice
#
#  (c) 2016 Copyright: Volker Kettenbach
#  e-mail: volker at kettenbach minus it dot de
#
#  Description:
#  This is an FHEM-Module for the TP Link TPLinkHS110110/110 
#  wifi controlled power outlet.
#  It support switching on and of the outlet as well as switching
#  on and of the nightmode (green led off).
#  It supports reading several readings as well as the
#  realtime power readings of the HS110.
#
#  Requirements
#  	Perl Module: IO::Socket::INET
#  	Perl Module: IO::Socket::Timeout
#  	
#  	In recent debian based distributions IO::Socket::Timeout can
#  	be installed by "apt-get install libio-socket-timeout-perl"
#  	In older distribution try "cpan IO::Socket::Timeout"
#
#  Origin:
#  https://github.com/kettenbach-it/FHEM-TPLink-HS110
#
################################################################

package main;

use strict;
use warnings;
use IO::Socket::INET;
use IO::Socket::Timeout;
use JSON;

#####################################
sub TPLinkHS110_Initialize($)
{
  my ($hash) = @_;
  
  $hash->{DefFn}      = "TPLinkHS110_Define";
  $hash->{ReadFn}     = "TPLinkHS110_Get";
  $hash->{SetFn}      = "TPLinkHS110_Set";
  $hash->{UndefFn}    = "TPLinkHS110_Undefine";
  $hash->{DeleteFn}   = "TPLinkHS110_Delete";
  $hash->{AttrFn}     = "TPLinkHS110_Attr";
  $hash->{AttrList}   = "interval ".
			"disable:0,1 " .
			"nightmode:on,off " .
  			"timeout " .
                        "$readingFnAttributes";
}

#####################################
sub TPLinkHS110_Define($$)
{
  my ($hash, $def) = @_;
  my $name= $hash->{NAME};

  my @a = split( "[ \t][ \t]*", $def );
  return "Wrong syntax: use define <name> TPLinkHS110 <hostname/ip> " if (int(@a) != 3);
 
  $hash->{INTERVAL}=300;
  $hash->{TIMEOUT}=1;
  $hash->{HOST}=$a[2];
  $attr{$name}{"disable"} = 0;
  # initial request after 2 secs, there timer is set to interval for further update
  InternalTimer(gettimeofday()+2, "TPLinkHS110_Get", $hash, 0);
    
  Log3 $hash, 3, "TPLinkHS110: $name defined.";
  
  return undef;
}


#####################################
sub TPLinkHS110_Get($$)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	return "Device disabled in config" if ($attr{$name}{"disable"} eq "1");
  	RemoveInternalTimer($hash);    
	InternalTimer(gettimeofday()+$hash->{INTERVAL}, "TPLinkHS110_Get", $hash, 1);
	$hash->{NEXTUPDATE}=localtime(gettimeofday()+$hash->{INTERVAL});

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$mon++;
	$year += 1900;

	my $remote_host = $hash->{HOST};
	my $remote_port = 9999;
	my $command = '{"system":{"get_sysinfo":{}}}';
	my $c = encrypt($command);
	my $socket = IO::Socket::INET->new(PeerAddr => $remote_host,
	        PeerPort => $remote_port,
	        Proto    => 'tcp',
	        Type     => SOCK_STREAM,
       		Timeout  => $hash->{TIMEOUT} )
	        or return "Couldn't connect to $remote_host:$remote_port: $@\n";
	$socket->send($c);
	my $data;
	my $retval = $socket->recv($data,8192);
	$socket->close();
	unless( defined $retval) { return undef; }
	$data = decrypt(substr($data,4));
	my $json;
	eval {
		$json = decode_json($data);
	} or do {
		Log3 $hash, 2, "TPLinkHS110: $name json-decoding failed. Problem decoding getting statistical data";
		return;
	};

	Log3 $hash, 3, "TPLinkHS110: $name Get called. Relay state: $json->{'system'}->{'get_sysinfo'}->{'relay_state'}, RSSI: $json->{'system'}->{'get_sysinfo'}->{'rssi'}";
	readingsBeginUpdate($hash);	
	foreach my $key (sort keys %{$json->{'system'}->{'get_sysinfo'}}) {
		readingsBulkUpdate($hash, $key, $json->{'system'}->{'get_sysinfo'}->{$key});
        }
	if ($json->{'system'}->{'get_sysinfo'}->{'relay_state'} == 0) {
		readingsBulkUpdate($hash, "state", "off");
	}
	if ($json->{'system'}->{'get_sysinfo'}->{'relay_state'} == 1) {
		readingsBulkUpdate($hash, "state", "on");
	}
	# If the device is a HS110, get realtime data:
	if ($json->{'system'}->{'get_sysinfo'}->{'model'} eq "HS110(EU)" or $json->{'system'}->{'get_sysinfo'}->{'model'} eq "HS110(UK)")) {
		my $realtimejcommand='{"emeter":{"get_realtime":{}}}';
		my $rc = encrypt($realtimejcommand);
		my $socket = IO::Socket::INET->new(PeerAddr => $remote_host,
		        PeerPort => $remote_port,
		        Proto    => 'tcp',
		        Type     => SOCK_STREAM,
	       		Timeout  => $hash->{TIMEOUT} )
		        or return "Couldn't connect to $remote_host:$remote_port: $@\n";
		$socket->send($rc);
		my $rdata;
		$retval = $socket->recv($rdata,8192);
		$socket->close();
		unless( defined $retval) { return undef; }
		$rdata = decrypt(substr($rdata,4));
		my $realtimejson;
		if (length($rdata)==0) {
			Log3 $hash, 1, "TPLinkHS110: $name: Received zero bytes of realtime data. Cannot process realtime data";
			return;
		}
		eval {
			$realtimejson = decode_json($rdata);
		} or do {
			Log3 $hash, 2, "TPLinkHS110: $name json-decoding failed. Problem decoding getting statistical data";
			return;
		};
		foreach my $key2 (sort keys %{$realtimejson->{'emeter'}->{'get_realtime'}}) {
			readingsBulkUpdate($hash, $key2, $realtimejson->{'emeter'}->{'get_realtime'}->{$key2});
		}
		Log3 $hash, 3, "TPLinkHS110: $name Device is an HS110. Got extra realtime data: $realtimejson->{'emeter'}->{'get_realtime'}->{'power'} Watt, $realtimejson->{'emeter'}->{'get_realtime'}->{'voltage'} Volt, $realtimejson->{'emeter'}->{'get_realtime'}->{'current'} Ampere";
		# Get Daily Stats
		my $command = '{"emeter":{"get_daystat":{"month":'.$mon.',"year":'.$year.'}}}';
		my $c = encrypt($command);
		$socket = IO::Socket::INET->new(PeerAddr => $remote_host,
		        PeerPort => $remote_port,
		        Proto    => 'tcp',
		        Type     => SOCK_STREAM,
	       		Timeout  => $hash->{TIMEOUT} )
		        or return "Couldn't connect to $remote_host:$remote_port: $@\n";
		$socket->send($c);
		my $data;
		$retval = $socket->recv($data,8192);
		$socket->close();
		unless( defined $retval) { return undef; }
		$data = decrypt(substr($data,4));
		eval {
			my $json = decode_json($data);
			my $total=0;
			foreach my $key (sort keys @{$json->{'emeter'}->{'get_daystat'}->{'day_list'}}) {
				foreach my $key2 ($json->{'emeter'}->{'get_daystat'}->{'day_list'}[$key]) {
					$total = $total+ $key2->{'energy'};
					if ($key2->{'day'} == $mday) {
						readingsBulkUpdate($hash, "daily_total", sprintf("%.3f", $key2->{'energy'}));
					}
				}
			}
			my $count=1;
			$count = @{$json->{'emeter'}->{'get_daystat'}->{'day_list'}};
			readingsBulkUpdate($hash, "monthly_total", $total);
			if ($count) { readingsBulkUpdate($hash, "daily_average", $total/$count)};
			1;
		} or do {
			Log3 $hash, 2, "TPLinkHS110: $name json-decoding failed. Problem decoding getting statistical data";
			return;
		};
	}
	readingsEndUpdate($hash, 1);
	Log3 $hash, 3, "TPLinkHS110: $name Get end";
}


#####################################
sub TPLinkHS110_Set($$)
{
	my ( $hash, @a ) = @_;
  	my $name= $hash->{NAME};
	return "Device disabled in config" if ($attr{$name}{"disable"} eq "1");
   	Log3 $hash, 3, "TPLinkHS110: $name Set <". $a[1] ."> called";
	return "Unknown argument $a[1], choose one of on off " if($a[1] ne "on" & $a[1] ne "off");

	my $command;
	if($a[1] eq "on") {
		$command = '{"system":{"set_relay_state":{"state":1}}}';
	}
	if($a[1] eq "off") {
		$command = '{"system":{"set_relay_state":{"state":0}}}';
	}
	my $remote_host = $hash->{HOST};
	my $remote_port = 9999;
	my $c = encrypt($command);
	my $socket = IO::Socket::INET->new(PeerAddr => $remote_host,
	        PeerPort => $remote_port,
	        Proto    => 'tcp',
	        Type     => SOCK_STREAM,
       		Timeout  => $hash->{TIMEOUT})
	        or return "Couldn't connect to $remote_host:$remote_port: $@\n";
	$socket->send($c);
	my $data;
	my $retval = $socket->recv($data,8192);
	$socket->close();
	unless( defined $retval) { return undef; }
	$data = decrypt(substr($data,4));
	my $json;
	eval {
		$json = decode_json($data);
	} or do {
		Log3 $hash, 2, "TPLinkHS110: $name json-decoding failed. Problem decoding getting statistical data";
		return;
	};

        if ($json->{'system'}->{'set_relay_state'}->{'err_code'} eq "0") {
		TPLinkHS110_Get($hash,"");
		
	} else {
                return "Command failed!";
        }	
	return undef;
}


#####################################
sub TPLinkHS110_Undefine($$)
{
	my ($hash, $arg) = @_;
	my $name= $hash->{NAME};
	RemoveInternalTimer($hash);    
	Log3 $hash, 3, "TPLinkHS110: $name undefined.";
	return;
}


#####################################
sub TPLinkHS110_Delete {
	my ($hash, $arg) = @_;
	my $name= $hash->{NAME};
	Log3 $hash, 3, "TPLinkHS110: $name deleted.";
	return undef;
}


#####################################
sub TPLinkHS110_Attr {
	my ($cmd,$name,$aName,$aVal) = @_;
	my $hash = $defs{$name};
  
	if ($aName eq "interval") {
		if ($cmd eq "set") {
			$hash->{INTERVAL} = $aVal;
		} else {
			$hash->{INTERVAL} = 300;
		}
		Log3 $hash, 3, "TPLinkHS110: $name INTERVAL set to " . $hash->{INTERVAL};
	}

	if ($aName eq "timeout") {
		if ($cmd eq "set") {
			$hash->{TIMEOUT} = $aVal;
		} else {
			$hash->{TIMEOUT} = 1;
		}
		Log3 $hash, 3, "TPLinkHS110: $name TIMEOUT set to " . $hash->{TIMEOUT};
	}

	if ($aName eq "nightmode") {
		my $command;
		if ($cmd eq "set") {
			$hash->{NIGHTMODE} = $aVal;
			Log3 $hash, 3, "TPLinkHS110: $name Nightmode $aVal.";
			$command =  '{"system":{"set_led_off":{"off":1}}}' if ($aVal eq "on");
			$command =  '{"system":{"set_led_off":{"off":0}}}' if ($aVal eq "off");
		}
		if ($cmd eq "del") {
			Log3 $hash, 3, "TPLinkHS110: $name Nightmode attribute removed. Nightmode disabled.";
			$command =  '{"system":{"set_led_off":{"off":0}}}';
			$hash->{NIGHTMODE} = "off";
		}
		my $remote_host = $hash->{HOST};
		my $remote_port = 9999;
		my $c = encrypt($command);
		my $socket = IO::Socket::INET->new(PeerAddr => $remote_host,
		        PeerPort => $remote_port,
		        Proto    => 'tcp',
		        Type     => SOCK_STREAM,
	       		Timeout  => $hash->{TIMEOUT} )
		        or return "Couldn't connect to $remote_host:$remote_port: $@\n";
		$socket->send($c);
		my $data;
		my $retval = $socket->recv($data,8192);
		$socket->close();
		unless( defined $retval) { return undef; }
		$data = decrypt(substr($data,4));
		my $json;
		eval {
			$json = decode_json($data);
		} or do {
			Log3 $hash, 2, "TPLinkHS110: $name json-decoding failed. Problem decoding getting statistical data";
			return;
		};
	}
	return undef;
}

# Encryption and Decryption of TP-Link Smart Home Protocol
# XOR Autokey Cipher with starting key = 171
# Based on https://www.softscheck.com/en/reverse-engineering-tp-link-hs110/
sub encrypt {
        my $key = 171;
        my $result = "\0\0\0\0";
        my @string=split(//, $_[0]);
        foreach (@string) {
                my $a = $key ^ ord($_);
                $key = $a;
                $result .= chr($a);
        }
        return $result;
}
sub decrypt {
        my $key = 171;
        my $result = "";
        my @string=split(//, $_[0]);
        foreach (@string) {
                my $a = $key ^ ord($_);
                $key = ord($_);
                $result .= chr($a);
        }
        return $result;
}

######################################################################################

1;



=pod
=begin html

<a name="TPLinkHS110"></a>
<h3>TPLinkHS110</h3>
<ul>
  <br>

  <a name="TPLinkHS110"></a>
  <b>Define</b>
    <code>define &lt;name&gt; TPLinkHS110 &lt;ip/hostname&gt;</code><br>
    	<br>
	Defines a TP-Link HS100 or HS110 wifi-controlled switchable power outlet.<br>
	The difference between HS100 and HS110 is, that the HS110 provides realtime measurments of<br>
	power, current and voltage.<br>
	This module automatically detects the modul defined and adapts the readings accordingly.<br>
	<br><br>
	This module does not implement all functions of the HS100/110.<br>
	Currently, all parameters relevant for running the outlet under FHEM are processed.<br>
	Writeable are only "On", "Off" and the nightmode (On/Off) (Nightmode: the LEDs of the outlet are switched off).<br>	
	Further programming of the outlet should be done by TPLinks app "Kasa", which funtionality is partly redundant<br>
	with FHEMs core functions.
  <p>
  <b>Attributs</b>
	<ul>
		<li><b>interval</b>: The interval in seconds, after which FHEM will update the current measurements. Default: 300s</li>
			An update of the measurements is done on each switch (On/Off) as well.
		<p>
		<li><b>timeout</b>:  Timeout in seconds used while communicationg with the outlet. Default: 1s</li>
			<i>Warning:</i>: the timeout of 1s is chosen fairly aggressive. It could lead to errors, if the outlet is not answerings the requests
			within this timeout.<br>
			Please consider, that raising the timeout could mean blocking the whole FHEM during the timeout!
		<p>
		<li><b>disable</b>: The execution of the module is suspended. Default: no.</li>
			<i>Warning: if your outlet is not on or not connected to the wifi network, consider disabling this module
			by the attribute "disable". Otherwise the cyclic update of the outlets measurments will lead to blockings in FHEM.</i>
	</ul>
  <p>
  <b>Requirements</b>
	<ul>
	This module uses the follwing perl-modules:<br><br>
	<li> Perl Module: IO::Socket::INET </li>
	<li> Perl Module: IO::Socket::Timeout </li>
	</ul>

</ul>

=end html

=begin html_DE

<a name="TPLinkHS110"></a>
<h3>TPLinkHS110</h3>
<ul>
  <br>

  <a name="TPLinkHS110"></a>
  <b>Define</b>
    <code>define &lt;name&gt; TPLinkHS110 &lt;ip/hostname&gt;</code><br>
    	<br>
    	Definiert eine TP-Link HS100 oder HS110 schaltbare WLAN-Steckdose. <br>
	Der Unterschied zwischen der HS100 und HS110 besteht darin, dass die HS110 eine Echtzeit-Messung von <br>
	Strom, Spannung sowie Leistung durchführt.<br>
	Dieses Modul erkennt automatisch, welchen Typ Sie verwenden und passt die Readings entsprechend an. 
	<br><br>
	Das Modul implementiert nicht alle Funktionen der HS100/110.<br>
	Derzeit werden alle für den sinnvollen Betrieb an FHEM benötigten Parameter ausgelesen.<br>
	Geschrieben werden jedoch nur die Schaltzustände  "An", "Aus" sowie der Nachtmodus An/Aus (Nachtmodus = LEDs der Steckdose ausschalten).<br>
	Für eine weitergehende Programmierung der Steckdosen wird daher die TP Link App "Kasa" empfohlen, wobei deren<br>
	Funktionen wie Timer etc. letztlich redundant zu Kernfunktionen von FHEM sind.
  <p>
  <b>Attribute</b>
	<ul>
		<li><b>interval</b>: Das Intervall in Sekunden, nach dem FHEM die Messwerte aktualisiert. Default: 300s</li>
			Eine Aktualisierung der Messwerte findet auch bei jedem Schaltvorgang statt.
		<p>
		<li><b>timeout</b>:  Der Timeout in Sekunden, der bei der Kommunikation mit der Steckdose verwendet wird. Default: 1s</li>
			<i>Achtung</i>: der Timeout von 1s ist knapp gewählt. Ggf. kann es zu Fehlermeldungen kommen, wenn die Steckdose nicht 
			schnell genug antwortet.<br>
			Bitte beachten Sie aber auch, dass längere Timeouts FHEM für den Zeitraum des Requests blockieren!
		<p>
		<li><b>disable</b>: Die Ausführung des Moduls wird gestoppt. Default: no.</li>
			<i>Achtung: wenn Ihre Steckdose nicht in Betrieb oder über das WLAN erreichbar ist, sollten Sie
			dieses FHEM-Modul per Attribut "disable" abschalten, da sonst beim zyklischen Abruf der Messdaten
			der Steckdose Timeouts auftreten, die FHEM unnötig verlangsamen.</i>
	</ul>
  <p>
  <b>Requirements</b>
	<ul>
	Das Modul benötigt die folgenden Perl-Module:<br><br>
	<li> Perl Module: IO::Socket::INET </li>
	<li> Perl Module: IO::Socket::Timeout </li>
	</ul>

</ul>
=end html_DE

=item summary Support for TPLink HS100/100 wifi controlled power outlet

=item summary_DE Support für die TPLink HS100/110 WLAN Steckdosen

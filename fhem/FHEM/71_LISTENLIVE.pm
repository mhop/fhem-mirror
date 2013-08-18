# $Id$
##############################################################################
#
#	71_LISTENLIVE.pm
#	An FHEM Perl module for controlling ListenLive-enabled Mediaplayers
#	via network connection.
#
#	Copyright: betateilchen ®
#	e-mail: fhem.development@betateilchen.de
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem. If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#
#	Changelog:
#
#	2013-07-21
#				Logging vereinheitlich
#				Meldungen komplett auf englisch umgestellt
#				pod (EN) erstellt
#
#	2013-07-25	
#				Anbindung an remotecontrol
#				Bereitstellung von Standardlayout und makenotify
#				neue commandGroup rc für Zugriff von 95_remotecontrol
#				Übersetzungstabelle für remoteCommands definiert
#
#				Beginn Redesign des Command-Parsing
#					neues Parsing für power erstellt
#					neues Parsing für reset erstellt
#					neues Parsing für cursor erstellt
#					neues Parsing für audio erstellt
#
#	2013-08-03
#				Fixed: Fehlermeldungen wegen ReplaceEventMap
#
##############################################################################

package main;

use strict;
use warnings;
use POSIX;
use CGI qw(:standard);
use IO::Socket;
use IO::Socket::INET;
use MIME::Base64;
use Time::HiRes qw(gettimeofday sleep usleep nanosleep);
use HttpUtils;
use feature qw/say switch/;


sub LISTENLIVE_Set($@);
sub LISTENLIVE_Get($@);
sub LISTENLIVE_Define($$);
sub LISTENLIVE_GetStatus($;$);
sub LISTENLIVE_Undefine($$);

sub HMT350_RCLayout();
sub HMT350_RCmakenotify($$);

my %HMT350_RCtranslate = (
home		=>	"HOME",
volplus		=>	"VOLp",
volmin		=>	"VOLm",
pageup		=>	"PAGEUP",
pagedn		=>	"PAGEDOWN",
);

# %HMT350_RCtranslate = (
# power		=>	"POWER",
# mute		=>	"MUTE",
# home		=>	"HOME",
# volplus		=>	"VOLp",
# tvout		=>	"OK",
# up			=>	"UP",
# rewind		=>	"REWIND",
# left		=>	"LEFT",
# ok			=>	"OK",
# right		=>	"RIGHT",
# down		=>	"DOWN",
# "return"	=>	"RETURN",
# volmin		=>	"VOLm",
# stop		=>	"STOP",
# pageup		=>	"PAGEUP",
# pause		=>	"PAUSE",
# itv			=> 	"ITV",
# pagedn		=>	"PAGEDOWN",
# menu		=>	"MENU",
# fav			=>	"OK",
# fmradio		=>	"FMRADIO",
# );

###################################
sub
LISTENLIVE_Initialize($)
{
	my ($hash) = @_;
	$hash->{GetFn}		=	"LISTENLIVE_Get";
	$hash->{SetFn}		=	"LISTENLIVE_Set";
	$hash->{DefFn}		=	"LISTENLIVE_Define";
	$hash->{UndefFn}	=	"LISTENLIVE_Undefine";
	$hash->{AttrList}	=	"do_not_notify:0,1 ".
							$readingFnAttributes;
	$data{RC_layout}{HMT350}		=	"HMT350_RClayout";
	$data{RC_makenotify}{LISTENLIVE}=	"HMT350_RCmakenotify";
}

###################################
sub
LISTENLIVE_Set($@)
{
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $address = $hash->{helper}{ADDRESS};
	my $loglevel = GetLogLevel($name, 3);
	my $result;
	my $response;

	return "No Argument given!\n\n".LISTENLIVE_HelpSet() if(!defined($a[1]));

	my %powerGroup	=	(on => "POWER", off => "POWER");
	my %muteGroup	=	(on => "MUTE", off => "MUTE");
	my %cursorGroup	=	(left => "LEFT", right => "RIGHT", up => "UP", down => "DOWN", home => "HOME", enter => "OK", ok => "OK", "exit" => "RETURN");
	my %audioGroup	=	(mute => "MUTE", unmute => "MUTE", volp => "VOLp", volm => "VOLm");

	my $pstat = $hash->{READINGS}{power}{VAL};
	my $mute  = $hash->{READINGS}{mute}{VAL};

#	my @b = split(/\./, $a[1]);
#	my $cmdGroup = $b[0];
#	my $cmd = $b[1];
#	if(!defined($cmd) && defined($a[2])) { $cmd = $a[2]; }

	my $cmdGroup = $a[1];
	my $cmd = $a[2];

	my $usage =	"Unknown argument, choose one of help:noArg statusRequest:noArg ".
				"power:on,off audio:volp,volm,mute,unmute cursor:up,down,left,right,enter,exit,home,ok ".
				"reset:power,mute,menupos app:weather raw user";

	given ($cmdGroup){

#
# commandGroup = rc
# verarbeitet Steuerbefehle aus 95_remotecontrol
#

		when("rc"){

			my ($c, $g); 
			$g = "raw";
			# prüfen ob Befehl in Kleinbuchstaben,
			# wenn ja => übersetzen!
			if($cmd eq lc($cmd)){
				$c = $HMT350_RCtranslate{$cmd};
				Log $loglevel, "LISTENLIVE $name rc_translate: >$cmdGroup $cmd< translated to: >$g $c<";
			} else {
				$c = $cmd;
			}
			fhem("set $name $g $c");
			break;
		}

#
# commandGroup = user <userDefFunction>
# ruft eine userdefinierte Funktion, z.B. aus 99_myUtils.pm auf
#

		when("user"){

			if(defined($cmd)){
				Log $loglevel, "LISTENLIVE $name input: $cmdGroup $cmd";
				no strict 'refs';
				$result = &{$cmd};
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd");
				readingsBulkUpdate($hash, "lastResult",$result);
				readingsEndUpdate($hash, 1);
			} else {
				return $usage;
			}
			break;
		}

#
# commandGroup = raw <command>
# sendet einfach das <command> per http an das Gerät
#

		when("raw"){
		
			if(defined($cmd)){
				Log $loglevel, "LISTENLIVE $name input: $cmdGroup $cmd";
				$result = LISTENLIVE_SendCommand($hash, $cmd);
				if($result =~  m/OK/){
					readingsBeginUpdate($hash);
					readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd");
					readingsBulkUpdate($hash, "lastResult",$result);
					readingsEndUpdate($hash, 1);
				} else {
					LISTENLIVE_rbuError($hash, $cmdGroup, $cmd);
				}
			} else {
				return $usage;
			}
			break;
		}

#
# commandGroup = reset <power>|<mute>
# setzt den Status von power und mute auf unbekannt,
# der nächste Befehl setzt den Status dann neu
#

		when("reset"){
		
			Log $loglevel, "LISTENLIVE $name input: $cmdGroup $cmd";
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd");
			readingsBulkUpdate($hash, "lastResult","OK");
			readingsBulkUpdate($hash, $cmd,"???");
			readingsEndUpdate($hash, 1);
			break;
		}

#
# commandGroup power <on>|<off>
# Es wird vor dem Senden geprüft, ob der Befehl Sinn macht
#

		when("power"){

			my $xCmd;
			Log $loglevel, "LISTENLIVE $name input: $cmdGroup $cmd";
			if($pstat ne $cmd) {
				$xCmd = $powerGroup{$cmd};
				$result = LISTENLIVE_SendCommand($hash, $xCmd);
				if($result =~  m/OK/){
					readingsBeginUpdate($hash);
					readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd");
					readingsBulkUpdate($hash, "lastResult",$result);
					readingsBulkUpdate($hash, "power",$cmd);
					if($cmd eq "on"){
					readingsBulkUpdate($hash, "mute", "off");
					}
					readingsEndUpdate($hash, 1);
				} else {
					LISTENLIVE_rbuError($hash, $cmdGroup, $cmd);
				}
			} else {
				LISTENLIVE_rbuError($hash, $cmdGroup, $cmd, " => device already $cmd!");
			}
			break;
		}

#
# commandGroup audio <mute>|<unmute>|<volp>|<volm>
#

		when("audio"){

			Log $loglevel, "LISTENLIVE $name input: $cmdGroup $cmd";
			if($mute ne $cmd) {
				my $xCmd = $audioGroup{$cmd};
				$result = LISTENLIVE_SendCommand($hash, $xCmd);
				if($result =~  m/OK/){
					readingsBeginUpdate($hash);
					readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd");
					readingsBulkUpdate($hash, "lastResult",$result);
					if($cmd eq "mute"){
					readingsBulkUpdate($hash, "mute", "on");
					} else {
					readingsBulkUpdate($hash, "mute", "off");
					}
					readingsEndUpdate($hash, 1);
				} else {
					LISTENLIVE_rbuError($hash, $cmdGroup, $cmd);
				}
			} else {
				LISTENLIVE_rbuError($hash, $cmdGroup, $cmd, " => no action required!");
			}
			break;
		}

#
# commandGroup cursor <up>|<down>|<left>|<right>|home|<enter>|<ok>|<exit>
#

		when("cursor"){
		
			Log $loglevel, "LISTENLIVE: $name input: $cmdGroup $cmd";
			my $xCmd = $cursorGroup{$cmd};
			$result = LISTENLIVE_SendCommand($hash, $xCmd);
			if($result =~  m/OK/){
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd");
				readingsBulkUpdate($hash, "lastResult",$result);
				readingsEndUpdate($hash, 1);
			} else {
				LISTENLIVE_rbuError($hash, $cmdGroup, $cmd);
			}
			break;
		}

#
# AREA app
#

		when ("app"){

			given($cmd){

				when("weather"){
					Log $loglevel, "LISTENLIVE $name input: $cmdGroup $cmd";
					$result = LISTENLIVE_SendCommand($hash, "POWER");
					select(undef, undef, undef, 1.0);
					$result = LISTENLIVE_SendCommand($hash, "HOME");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "DOWN");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "DOWN");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "RIGHT");
					select(undef, undef, undef, 0.2);
					$result = LISTENLIVE_SendCommand($hash, "OK");

					readingsBeginUpdate($hash);
					readingsBulkUpdate($hash, "lastCmd",$a[1]);
					readingsBulkUpdate($hash, "lastResult","done");
					readingsEndUpdate($hash, 1);
				} # end doit.weather

				default:
					{ return $usage; }
			}
		}

		when("statusRequest")	{ break; } # wird automatisch aufgerufen!
		when("present")			{ break; }
		when("absent")			{ break; }
		when("online")			{ break; }
		when("offline")			{ break; }
		when("help")			{ return LISTENLIVE_HelpSet(); }
		when("?")				{ return $usage; }
		default:				{ return $usage; }

	}

	LISTENLIVE_GetStatus($hash, 1);

	return $response;
}

###################################
sub
LISTENLIVE_Get($@){
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $address = $hash->{helper}{ADDRESS};
	my ($response, $usage);

	return "No Argument given" if(!defined($a[1]));

	my $cmdGroup	=	$a[1];
	my $cmd			=	$a[2];

	given($cmdGroup){
		when("?")		{ return $usage; }
		when("help")	{ $response = LISTENLIVE_HelpGet(); }
		default:		{ return $usage; }
	}
	return $response;
}

###################################
sub
LISTENLIVE_GetStatus($;$){
	my ($hash, $local) = @_;
	my $name = $hash->{NAME};
	my $presence;

	$local = 0 unless(defined($local));

	if($hash->{helper}{ADDRESS} ne "none")
	{ $presence = ReadingsVal("pres_".$name,"state","absent"); }
	else
	{ $presence = "present"; }

	if($presence eq "absent") { $presence = "offline";}
	else { $presence = "online"; }

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state", $presence);
	readingsEndUpdate($hash, 1);

	$hash->{STATE} = $presence;

	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "LISTENLIVE_GetStatus", $hash, 0) unless($local == 1);
	return 1;
}

#############################
sub
LISTENLIVE_Define($$){
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $name = $hash->{NAME};
	my ($cmd, $presence, $ret);

	if(! @a >= 4){
		my $msg = "wrong syntax: define <name> LISTENLIVE <ip-or-hostname>[:<port>] [<interval>]";
		Log 2, $msg;
		return $msg;
	}

# Adresse in IP und Port zerlegen
	my @address = split(":", $a[2]);
	$hash->{helper}{ADDRESS} = $address[0];

# falls kein Port angegeben, Standardport 8080 verwenden
	$address[1] = "8080" unless(defined($address[1]));  
	$hash->{helper}{PORT} = $address[1];

# falls kein Intervall angegeben, Standardintervall 60 verwenden
	my $interval = $a[3];
	$interval = "60" unless(defined($interval));
	$hash->{helper}{INTERVAL} = $interval;

	if($address[0] ne "none"){
		# PRESENCE aus device pres_+NAME lesen
		$presence = ReadingsVal("pres_".$name,"state","noPresence");
	
		if($presence eq "noPresence"){
			$cmd = "pres_$name PRESENCE lan-ping $address[0]";
			$ret = CommandDefine(undef, $cmd);
			if($ret){
				Log 2, "LISTENLIVE ERROR $ret";
			} else {
				Log 3, "LISTENLIVE $name PRESENCE pres_$name created.";
			}
		} else {
			Log 3, "LISTENLIVE $name PRESENCE pres_$name found.";
		}	
		$presence = "absent";
	} else {
	# Gerät ist als dummy definiert
		$presence = "present";	# dummy immer als online melden
	}
	

	if($presence eq "absent") {
		$presence = "offline";
	} else {
		$presence = "online";
	}

# Readings anlegen und füllen
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "lastCmd","");
	readingsBulkUpdate($hash, "lastResult","");
	readingsBulkUpdate($hash, "mute","???");
	readingsBulkUpdate($hash, "power","???");
	readingsBulkUpdate($hash, "state",$presence);
	readingsEndUpdate($hash, 1);

	$hash->{helper}{AVAILABLE} = 1;
	$hash->{STATE} = $presence;
	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "LISTENLIVE_GetStatus", $hash, 0);

	return;
}

#############################
sub
LISTENLIVE_SendCommand($$;$){
	my ($hash, $command, $loglevel) = @_;
	my $name = $hash->{NAME};
	my $address = $hash->{helper}{ADDRESS};
	my $port = $hash->{helper}{PORT};
	my $response = "";
	my $modus = "dummy";
	my ($socket,$client_socket);

	$loglevel = GetLogLevel($name, 3) unless(defined($loglevel));
	Log $loglevel, "LISTENLIVE $name command: $command";
	
	if (Value("$name") eq "online" && $hash->{helper}{ADDRESS} ne "none")	{ $modus = "online"; }
	if (Value("$name") eq "offline") 										{ $modus = "offline"; }

	given($modus) {
		when("online") {
			eval {
				$socket = new IO::Socket::INET (
					PeerHost => $address,
					PeerPort => $port,
						Proto => 'tcp',
				) or die "ERROR in Socket Creation : $!\n";
				$socket->send($command);
				usleep(30000);
				$socket->recv($response, 2);
				if($response !~  m/OK/)	{ Log 2,			"LISTENLIVE $name error: $response"; }
				else 					{ Log $loglevel,	"LISTENLIVE $name response: $response"; }
				$socket->close();
			}; warn $@ if $@;
			$hash->{helper}{AVAILABLE} = (defined($response) ? 1 : 0);
		}

		when("offline") {
			Log 2, "LISTENLIVE $name error: device offline!";
			$response = "device offline!";
		}

		default:
			{ $response = "OK"; }
	}
	return $response;
}

sub
LISTENLIVE_rbuError($$;$$){
	my ($hash, $cmdGroup, $cmd, $parameter) = @_;
	Log 2, "LISTENLIVE $hash->{NAME} error: $cmdGroup $cmd $parameter";

	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "lastCmd","$cmdGroup $cmd $parameter");
	readingsBulkUpdate($hash, "lastResult","Error: $cmdGroup $cmd $parameter");
	readingsEndUpdate($hash, 1);
	return undef;
}

sub
LISTENLIVE_HelpGet(){
my $helptext =
'get <device> <commandGroup> [<command>]


commandGroup "help"
get llradio help (show this help page)';

return $helptext;
}

sub
LISTENLIVE_HelpSet(){
my $helptext =
'set <device> <commandGroup> [<command>]


commandGroup "help"
set llradio help (show this help page)


commandGroup "audio"
set llradio audio mute
set llradio audio unmute
set llradio audio volm
set llradio audio volp


commandGroup "cursor"
set llradio cursor down
set llradio cursor left
set llradio cursor up
set llradio cursor right
set llradio cursor enter
set llradio cursor exit
set llradio cursor home
set llradio cursor ok


commandGroup "power"
set llradio power off
set llradio power on


commandGroup "raw"
set llradio raw <command>


commandGroup "reset"
set llradio reset mute
set llradio reset power


commandGroup "user"  (experimental!)
set llradio user <userDefFunction>


commandGroup "app"  (experimental!)
set llradio app weather


commandGroup "statusRequest"
set llradio statusRequest';

return $helptext;
}

#############################
sub
LISTENLIVE_Undefine($$){
	my($hash, $name) = @_;
	RemoveInternalTimer($hash);
	return undef;
}

#####################################
sub HMT350_RCmakenotify($$) {
#	my $loglevel = GetLogLevel($name, 3) unless(defined($loglevel));
	my ($nam, $ndev) = @_;
	my $nname="notify_$nam";
	my $cmd = "$nname notify $nam set $ndev rc \$EVENT";
	my $ret = CommandDefine(undef, $cmd);
	if($ret)	{ Log 2,	"remotecontrol ERROR $ret"; }
	else		{ Log 3,	"remotecontrol HMT350: $nname created as notify"; }
	return "Notify created: $nname";
}

#####################################
sub HMT350_RClayout() {
	my @row;
	my $rownum = 0;

	$row[$rownum]="power:POWEROFF,:blank,:blank,:blank,MUTE"; $rownum++;
	$row[$rownum]="home:HOMEsym,:blank,volplus:VOLUP,:blank,:TVout"; $rownum++;
	$row[$rownum]=":blank,:blank,UP,:blank,:blank"; $rownum++;
	$row[$rownum]="REWIND,LEFT,OK,RIGHT,forward:FF"; $rownum++;
	$row[$rownum]=":blank,:blank,DOWN,:blank,:blank"; $rownum++;
	$row[$rownum]="RETURN,:blank,volmin:VOLDOWN,:blank,STOP"; $rownum++;
	$row[$rownum]=":blank,:blank,:blank,:blank,:blank"; $rownum++;
	$row[$rownum]="PAGEUP,:blank,PAUSE,:blank,ITV"; $rownum++;
	$row[$rownum]="PAGEDOWN,:blank,MENU,:blank,IRADIO"; $rownum++;
	$row[$rownum]=":FAV,:blank,REPEAT,:blank,FMRADIO"; $rownum++;

	$row[19]="attr rc_iconpath icons/remotecontrol";
	$row[20]="attr rc_iconprefix black_btn_";

	return @row;
}

1;

### ENDE ######

=pod
=begin html

<a name="LISTENLIVE"></a>
<h3>LISTENLIVE</h3>
<ul>

  <a name="LISTENLIVEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LISTENLIVE &lt;ip-address&gt;[:&lt;port&gt;] [&lt;status_interval&gt;]</code>
    <br/><br/>

    This module can control all mediaplayers runnng ListenLive Firmware laufen via a network connection.
    It can control power state on/off, volume up/down/mute and can send all remomte-control commands.
    <br/><br/>
    The port value is optional. If not defined, standard port 8080 will be used.
    <br/><br/>
	The status_interval value is optional. If not defined, standard interval 60sec will be used.
	<br/><br/>
    Upon the definition of a new LISTENLIVE-device an internal Loop will be defined which will check and update the device readings
    all <status_interval> seconds to trigger all notify and FileLog entities.
    <br><br>

    Example:
    <br/><br/>
    <ul><code>
       define llradio LISTENLIVE 192.168.0.10<br><br>
       
       define llradio LISTENLIVE 192.168.0.10:8085 120 &nbsp;&nbsp;&nbsp; # with port (8085) und status interval (120 seconds)
    </code></ul><br><br>
  </ul>
  
  <a name="LISTENLIVEset"></a>
  <b>Set-Commands </b>
  <ul>
    <code>set &lt;name&gt; &lt;commandGroup&gt; [&lt;command&gt;] [&lt;parameter&gt;]</code>
    <br><br>
    Commands are grouped into commandGroups depending on their functional tasks.
    The following groups and commands are currently available:
    <br><br>
<ul><code>
commandGroup power<br>
power on<br>
power off<br>
<br>
commandGroup audio<br>
audio mute<br>
audio unmute<br>
audio volm<br>
audio volp<br>
<br>
commandGroup cursor<br>
cursor up<br>
cursor down<br>
cursor left<br>
cursor right<br>
cursor home<br>
cursor exit<br>
cursor enter<br>
cursor ok<br>
<br>
commandGroup reset<br>
reset power<br>
reset mute<br>
reset menupos<br>
<br>
commandGroup raw<br>
raw <command><br>
<br>
commandGroup user (experimental)<br>
user <userDefinedFunction><br>
<br>
commandGroup app (experimental)<br>
app weather<br>
<br>
commandGroup help<br>
help<br>
<br>
commandGroup statusRequest<br>
statusRequest
</code></ul>
</ul>
<br><br>
  <a name="LISTENLIVEget"></a>
  <b>Get-Commands</b>
  <ul>
    <code>get &lt;name&gt; &lt;parameter&gt;</code>
    <br><br>
    The following parameters are available:<br><br>
     <ul>
     <li><code>help</code> - show help-text</li>
     </ul>
  </ul>
  <br>
<br><br>
  <a name="LISTENLIVEattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>
  <b>Generated Readings/Events:</b><br>
  <ul>
  <li><b>lastCmd</b> - last command sent to device</li>
  <li><b>lastResult</b> - last response from device</li>
  <li><b>menuPos</b> - cursor position in main menu (experimental)</li>
  <li><b>mute</b> - current mute state ("on" =&gt; muted, "off" =&gt; unmuted)</li>
  <li><b>power</b> - current power state</li>
  <li><b>state</b> - current device state (online or offline)</li>
  </ul>
  <br><br>
  <b>Author's notes</b>
  <ul>
    You need to activate option "remote control settings" -> "network remote control [on]" in your device's settings.
    <br><br>
    Upon the device definion a corresponding PRESENCE-entity will be created to evaluate the device availability.
    <br>
  </ul>
</ul>

=end html
=begin html_DE

<a name="LISTENLIVE"></a>
<h3>LISTENLIVE</h3>
<ul>

  <a name="LISTENLIVEdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; LISTENLIVE &lt;ip-address&gt;[:&lt;port&gt;] [&lt;status_interval&gt;]</code>
    <br/><br/>

    Dieses Modul steuert Internetradios, die mit der ListenLive Firmware laufen, &uuml;ber die Netzwerkschnittstelle.
    Es bietet die M&ouml;glichkeit das Ger&auml;t an-/auszuschalten, die Lautst&auml;rke zu &auml;ndern, den Cursor zu steuern,
    den Receiver "Stumm" zu schalten, sowie alle Fernbedienungskommandos an das Ger&auml;t zu senden.
    <br/><br/>
    Die Angabe des TCP-ports ist optional. Fehlt dieser Parameter, wird der Standardwert 8080 verwendet.
    <br/><br/>
    Bei der Definition eines LISTENLIVE-Ger&auml;tes wird eine interne Routine in Gang gesetzt, welche regelm&auml;&szlig;ig 
    (einstellbar durch den optionalen Parameter <code>&lt;status_interval&gt;</code>; falls nicht gesetzt ist der Standardwert 60 Sekunden)
    den Status des Ger&auml;tes abfragt und entsprechende Notify-/FileLog-Ger&auml;te triggert..<br><br>

    Beispiel:
    <br/><br/>
    <ul><code>
       define llradio LISTENLIVE 192.168.0.10<br><br>
       
       define llradio LISTENLIVE 192.168.0.10:8085 120 &nbsp;&nbsp;&nbsp; # Mit modifiziertem Port (8085) und Status Interval (120 Sekunden)
    </code></ul><br><br>
  </ul>
  
  <a name="LISTENLIVEset"></a>
  <b>Set-Kommandos </b>
  <ul>
    <code>set &lt;Name&gt; &lt;Befehlsgruppe&gt; [&lt;Befehl&gt;] [&lt;Parameter&gt;]</code>
    <br><br>
    Die Befehle zur Steuerung sind weitgehend in Befehlsgruppen eingeordnet, die sich an logischen Funktionsbereichen orientieren.
    Aktuell stehen folgende Befehlsgruppen und Befehele zur Verf&uuml;gung:
<br><br>
<ul><code>
Befehlsgruppe power<br>
power on<br>
power off<br>
<br>
Befehlsgruppe audio<br>
audio mute<br>
audio unmute<br>
audio volm<br>
audio volp<br>
<br>
Befehlsgruppe cursor<br>
cursor up<br>
cursor down<br>
cursor left<br>
cursor right<br>
cursor home<br>
cursor exit<br>
cursor enter<br>
cursor ok<br>
<br>
Befehlsgruppe reset<br>
reset power<br>
reset mute<br>
reset menupos<br>
<br>
Befehlsgruppe raw<br>
raw <command><br>
<br>
Befehlsgruppe user (experimentell)<br>
user <userDefinedFunction><br>
<br>
Befehlsgruppe app (experimentell)<br>
app weather<br>
<br>
Befehlsgruppe help<br>
help<br>
<br>
Befehlsgruppe statusRequest<br>
statusRequest
</code></ul>
</ul>
<br><br>
  <a name="LISTENLIVEget"></a>
  <b>Get-Kommandos</b>
  <ul>
    <code>get &lt;Name&gt; &lt;Parameter&gt;</code>
    <br><br>
    Aktuell stehen folgende Parameter zur Verf&uuml;gung:<br><br>
     <ul>
     <li><code>help</code> - zeigt einen Hilfetext an</li>
     </ul>
  </ul>
  <br>
<br><br>
  <a name="LISTENLIVEattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br><br>
  <b>Generierte Readings/Events:</b><br>
  <ul>
  <li><b>lastCmd</b> - der letzte gesendete Befehl</li>
  <li><b>lastResult</b> - die letzte Antwort des Ger&auml;tes</li>
  <li><b>menuPos</b> - Cursorposition im Hauptmen&uuml; (experimentell)</li>
  <li><b>mute</b> - der aktuelle Stumm-Status("on" =&gt; Stumm, "off" =&gt; Laut)</li>
  <li><b>power</b> - der aktuelle Betriebsstatuse ("on" =&gt; an, "off" =&gt; aus)</li>
  <li><b>state</b> - der aktuelle Ger&auml;testatus (online oder offline)</li>
  </ul>
  <br><br>
  <b>Hinweise</b>
  <ul>
    Dieses Modul ist nur nutzbar, wenn die Option "remote control settings" -> "network remote control [on]" in der Firmware aktiviert ist.
    <br><br>
    W&auml;hrend der Definition wird automatisch ein passendes PRESENCE angelegt, um die Verf&uuml;gbarkeit des Ger&auml;tes zu ermitteln.
    <br>
  </ul>
</ul>

=end html_DE

=cut

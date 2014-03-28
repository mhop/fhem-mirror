# $Id: 71_LISTENLIVE.pm 5096 2014-03-02 12:04:28Z betateilchen $
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
#
# modifications for LL firmware V1.5x
#
#	2014-01-24
#				Removed:	commandGroup app
#							commandGroup reset
#							command cursor ok
#							readings lastCmd, lastResult
#							German commandref documentation
#
#				Added:		commandGroup message
#							command audio reset (reset mute state)
#							readings rawCmd, rawResult
#							get commands:	version volume power
#											menuinfo listinfo metatinfo
#							attribute llDelay (to adjust communication timimg)
#
#				Changed:	logging to new Log3 feature
#
#				Updated:	commandref documentations
#							internal help texts
#
#	2014-02-04
#				Added:		ShutdownFn
#				Changed:	Undef will delete presence, too
#
#	2014-02-28
#				Changed:	Make presence entities TEMPORARY
#
##############################################################################

package main;

use strict;
use warnings;
use POSIX;
use CGI qw(:standard);
use IO::Socket;
use IO::Socket::INET;
use HttpUtils;
use MIME::Base64;
use Time::HiRes qw(gettimeofday sleep usleep);
use feature qw(say switch);

sub HMT350_RCLayout();
sub HMT350_RCmakenotify($$);

my %HMT350_RCtranslate = (
home		=>	"HOME",
volplus		=>	"VOLp",
volmin		=>	"VOLm",
pageup		=>	"PAGEUP",
pagedn		=>	"PAGEDOWN",
);

my @appList = (
'mainmenu',
'internet tv app',
'internet radio app',
'shoutcast app',
'podcast app',
'mediaplayer app',
'linein',
'fm app',
'clock app',
'settings app',
'tv out',
'audio player',
'video player',
'about screen',
'keyboard is onscreen',
'weather app',
'news app',
'twitter app',
'blubrry app',
'media player selection',
'weather location selection',
'popup',
'stocks app',
'calendar',
'soundcloud',
'n/a',
'n/a',
'usatoday',
'revision3',
'n/a',
'n/a',
'n/a',
'vodcast',
'favorites',
'night stand',
'submenu',
'n/a',
'icecast',
'tunein',
'101.ru',
'tuner app',
'rad.io',
'live365',
'chinaradio',
'homeradio',
'steamcast',
'anyradio',
'qingting',
'lautfm');

###################################
sub LISTENLIVE_Initialize($) {
	my ($hash) = @_;
	$hash->{DefFn}		=	"LISTENLIVE_Define";
	$hash->{UndefFn}	=	"LISTENLIVE_Undefine";
	$hash->{ShutdownFn}	=	"LISTENLIVE_Shutdown";
	$hash->{AttrFn}		=	"LISTENLIVE_Attr";
	$hash->{SetFn}		=	"LISTENLIVE_Set";
	$hash->{GetFn}		=	"LISTENLIVE_Get";
	$hash->{AttrList}	=	"do_not_notify:0,1 ".
							"llDelay ".
							$readingFnAttributes;
	$data{RC_layout}{HMT350}		=	"HMT350_RClayout";
	$data{RC_makenotify}{LISTENLIVE}=	"HMT350_RCmakenotify";
}

sub LISTENLIVE_Define($$) {
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	my $name = $hash->{NAME};
	my ($cmd, $presence, $ret);

	$hash->{HELPER}{DELAY} = 1000;

	if(! @a >= 4){
		my $msg = "wrong syntax: define <name> LISTENLIVE <ip-or-hostname>[:<port>] [<interval>]";
		Log3($name, 2, $msg);
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
		my $pres_name;
		$presence = ReadingsVal("pres_".$name,"state","noPresence");
	
		if($presence eq "noPresence"){
			$pres_name = "pres_".$name;
			$cmd = "$pres_name PRESENCE lan-ping $address[0]";
			$ret = CommandDefine(undef, $cmd);
			if($ret){
				Log3($name, 2, "LISTENLIVE ERROR $ret");
			} else {
				Log3($name, 3, "LISTENLIVE $name PRESENCE $pres_name created.");
				$defs{$pres_name}{TEMPORARY} = 1;
				$attr{$pres_name}{verbose} = 2;
				$attr{$pres_name}{room} = 'hidden';
			}
		} else {
			Log3($name, 3, "LISTENLIVE $name PRESENCE pres_$name found.");
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

	readingsSingleUpdate($hash, "state",$presence, 1);
	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "LISTENLIVE_GetStatus", $hash, 0);
	$hash->{helper}{AVAILABLE} = 1;

	return;
}

sub LISTENLIVE_Undefine($$) {
	my($hash, $name) = @_;
	CommandDelete(undef, "pres_".$name);
	RemoveInternalTimer($hash);
	return undef;
}

sub LISTENLIVE_Shutdown($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 ($name,4,"LISTENLIVE $name: shutdown requested");
	return undef;
}


sub LISTENLIVE_Attr($@) {
	my @a = @_;
	my $hash = $defs{$a[1]};
	my (undef, $name, $attrName, $attrValue) = @a;

	given($attrName){
		when("llDelay"){
			if($attrValue ~~[1..50]) {
				$attr{$name}{$attrName} = $attrValue;
			} else {
				$attr{$name}{$attrName} = 1;
			}
			$hash->{HELPER}{DELAY} = 1000 * $attrValue;
			break;
		}
		default {$attr{$name}{$attrName} = $attrValue;}
	}

	$hash->{HELPER}{DELAY} = 1000 if $hash->{HELPER}{DELAY} < 1000;

	return "";

}

sub LISTENLIVE_Set($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $address = $hash->{helper}{ADDRESS};
	my $result;
	my $response;

	return "No Argument given!\n\n".LISTENLIVE_HelpSet() if(!defined($a[1]));

	my %powerGroup	=	(on => "POWER", off => "POWER");
	my %muteGroup	=	(on => "MUTE", off => "MUTE");
	my %cursorGroup	=	(left => "LEFT", right => "RIGHT", up => "UP", down => "DOWN", home => "HOME", ok => "OK", "exit" => "RETURN");
	my %audioGroup	=	(mute => "MUTE", unmute => "MUTE", volp => "VOLp", volm => "VOLm");

	my $pstat = $hash->{READINGS}{power}{VAL};
	my $mute  = $hash->{READINGS}{mute}{VAL};

	my $cmdGroup = lc($a[1]);
	my $cmd = $a[2];

	my $usage =	"Unknown argument, choose one of help:noArg statusRequest:noArg ".
				"power:on,off audio:volp,volm,mute,unmute,reset cursor:up,down,left,right,enter,exit,home ".
				"message raw user";

	given ($cmdGroup){

#
# commandGroup power <on>|<off>
# Es wird vor dem Senden geprüft, ob der Befehl Sinn macht
#

		when("power"){

			my $xCmd;
			Log3($name, 3, "LISTENLIVE $name input: $cmdGroup $cmd");
			if($pstat ne $cmd) {
				$xCmd = $powerGroup{$cmd};
				$result = LISTENLIVE_SendCommand($hash, $xCmd);
				if($result =~  m/OK/){
					readingsBeginUpdate($hash);
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
# commandGroup cursor <up>|<down>|<left>|<right>|home|<enter>|<ok>|<exit>
#

		when("cursor"){
		
			Log3($name, 3, "LISTENLIVE: $name input: $cmdGroup $cmd");
			my $xCmd = $cursorGroup{$cmd};
			$result = LISTENLIVE_SendCommand($hash, $xCmd);
			if($result =~  m/OK/){
				usleep($hash->{HELPER}{DELAY});
			} else {
				LISTENLIVE_rbuError($hash, $cmdGroup, $cmd);
			}
			break;
		}

#
# commandGroup audio <mute>|<unmute>|<volp>|<volm>|<reset>
#

		when("audio"){

			Log3($name, 3, "LISTENLIVE $name input: $cmdGroup $cmd");
			if($mute ne $cmd) {
				my $xCmd = $audioGroup{$cmd};
				$result = LISTENLIVE_SendCommand($hash, $xCmd);
				if($result =~  m/OK/){
					given($cmd) {
						when ('mute'){
							readingsSingleUpdate($hash, "mute", "on", 1);
						}
						when ('unmute'){
							readingsSingleUpdate($hash, "mute", "off", 1);
						}
						when ('reset'){
							readingsSingleUpdate($hash, "mute", "???", 1);
						}
					}
				} else {
					LISTENLIVE_rbuError($hash, $cmdGroup, $cmd);
				}
			} else {
				LISTENLIVE_rbuError($hash, $cmdGroup, $cmd, " => no action required!");
			}
			break;
		}

#
# commandGroup = message [<textMessage>]
# gibt eine Textnachricht als PopUp aus.
# wird die textMessage weggelassen, wird ein eventuell
# vorhandenes PopUp geschlossen.
# Mehrere message-Befehle nacheinander überschreiben jeweils
# den Inhalt eines noch geöffneten PopUps
#

		when("message"){
			if(defined($cmd)){
				my $as = @a;
				for (my $i=3; $i<$as;$i++){
					$cmd .= " $a[$i]";
				}
				Log3($name, 3, "LISTENLIVE $name input: $cmdGroup $cmd");
				$result = LISTENLIVE_SendCommand($hash, "MESSAGE ".$cmd);
			} else {
#				ll_menuinfo($hash);
				usleep($hash->{HELPER}{DELAY});
				my $mi_state = ReadingsVal($name, "mi_state",0);
				# Popup schließen, falls vorhanden
				fhem("set $name cursor ok") if $mi_state == 21;
			}
			break;
		}

#
# commandGroup = raw <command>
# sendet einfach das <command> per http an das Gerät
#

		when("raw"){
		
			if(defined($cmd)){
				Log3($name, 3, "LISTENLIVE $name input: $cmdGroup $cmd");
				$result = LISTENLIVE_SendCommand($hash, $cmd);
				readingsBeginUpdate($hash);
				readingsBulkUpdate($hash, "rawCmd","$cmdGroup $cmd");
				readingsBulkUpdate($hash, "rawResult",$result);
				readingsEndUpdate($hash, 1);
			} else {
				return $usage;
			}
			break;
		}

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
				Log3($name, 3, "LISTENLIVE $name rc_translate: >$cmdGroup $cmd< translated to: >$g $c<");
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
				Log3($name, 3, "LISTENLIVE $name input: $cmdGroup $cmd");
				no strict 'refs';
				$result = &{$cmd};
			} else {
				return $usage;
			}
			break;
		}

		when("statusRequest")	{ break; } # wird automatisch aufgerufen!
		when("help")			{ return LISTENLIVE_HelpSet(); }
		when("?")				{ return $usage; }
		default:				{ return $usage; }

	}

	ll_version($hash);
	ll_power($hash);
	ll_volume($hash);
	ll_menuinfo($hash);
	ll_listinfo($hash);
	ll_metainfo($hash);

	return;
}

sub LISTENLIVE_Get($@) {
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $address = $hash->{helper}{ADDRESS};
	my ($response, $result);

	return "No Argument given" if(!defined($a[1]));

	my $usage =	"Unknown argument, choose one of help:noArg ".
				"version:noArg volume:noArg menuinfo:noArg ".
				"power:noArg listinfo:noArg metainfo:noArg" ;

	my $cmdGroup	= lc($a[1]);
#	my $cmd			= $a[2];

	given($cmdGroup) {

		when("?") {
			return $usage;
		}

		when("help") {
			$response = LISTENLIVE_HelpGet();
		}

		when("version") {
			ll_version($hash);
		}

		when("volume") {
			ll_volume($hash);
		}

		when("menuinfo") {
			ll_menuinfo($hash);
		}

		when("metainfo") {
			ll_metainfo($hash);
		}

		when("listinfo") {
			ll_listinfo($hash);
		}

		when("power") {
			ll_power($hash);
		}

		default: {
			return $usage;
		}

	}
	return $response;
}

sub LISTENLIVE_GetStatus($;$) {
	my ($hash, $local) = @_;
	my $name = $hash->{NAME};
	my $presence;

	$local = 0 unless(defined($local));
	RemoveInternalTimer($hash);

	if($hash->{helper}{ADDRESS} ne "none") {
		$presence = ReadingsVal("pres_".$name,"state","absent");
	} else {
		$presence = "present";
	}

	if($presence eq "absent") { 
		$presence = "offline";
	} else {
		$presence = "online";
	}

	readingsSingleUpdate($hash,"state",$presence,1);

	ll_version($hash);
	ll_power($hash);
	ll_volume($hash);
	ll_menuinfo($hash);
	ll_listinfo($hash);
	ll_metainfo($hash);

	InternalTimer(gettimeofday()+$hash->{helper}{INTERVAL}, "LISTENLIVE_GetStatus", $hash, 0) unless($local == 1);
	return 1;
}

sub LISTENLIVE_SendCommand($$) {
	my ($hash, $command) = @_;
	my $name = $hash->{NAME};
	my $address = $hash->{helper}{ADDRESS};
	my $port = $hash->{helper}{PORT};
	my $response = "";
	my $modus = "dummy";
	my ($socket);#,$client_socket);

	Log3($name, 3, "LISTENLIVE $name command: $command");
	
	if (Value("$name") eq "online" && $hash->{helper}{ADDRESS} ne "none")	{ $modus = "online"; }
	if (Value("$name") eq "offline") 										{ $modus = "offline"; }

	given($modus) {
		when("online") {
			usleep($hash->{HELPER}{DELAY});
			eval {
				$socket = new IO::Socket::INET (
					PeerHost => $address,
					PeerPort => $port,
					Blocking => 0,
					Timeout => 10,
					Proto => 'tcp',
				) or die "ERROR in Socket Creation : $!\n";
				$socket->send($command);
				usleep($hash->{HELPER}{DELAY} * 3);
				$socket->recv($response, 1024);
				my $resplen = length($response);
#				Debug "LISTENLIVE $name C: $command R: $response L: $resplen";
				if($response ~~  m/UNK/) {
					Log3($name, 2, "LISTENLIVE $name error: $response");
				} else {
					Log3($name, 3, "LISTENLIVE $name response: $response");
				}
				$socket->close();
			}; warn $@ if $@;
			$hash->{helper}{AVAILABLE} = (defined($response) ? 1 : 0);
		}

		when("offline") {
			Log3($name, 2, "LISTENLIVE $name error: device offline!");
			$response = "device offline!";
		}

		default:
			{ $response = "OK"; }
	}
	return $response;
}

sub LISTENLIVE_rbuError($$;$$){
	my ($hash, $cmdGroup, $cmd, $parameter) = @_;
	$parameter = ' ' if(!defined($parameter));
	Log3($hash, 2, "LISTENLIVE $hash->{NAME} error: $cmdGroup $cmd $parameter");
	return undef;
}

sub LISTENLIVE_HelpGet() {
my $helptext =
'get <device> <commandGroup> [<command>]


get llradio help (show this help page)

get llradio power (read powerState)
get llradio version (read version info)
get llradio volume (read volume level)
get llradio menuinfo (read menu infos)
get llradio listinfo (read list infos)
get llradio metainfo (read meta infos from current title)';

return $helptext;
}

sub LISTENLIVE_HelpSet() {
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

commandGroup "statusRequest"
set llradio statusRequest';

return $helptext;
}

#### Funktionen zum Lesen bestimmter Gerätezustände

sub ll_version($){
	my ($hash) = @_;
	my $result = LISTENLIVE_SendCommand($hash, 'VERSION');
	(undef, $result) = split('=',$result);
	readingsSingleUpdate($hash, 'version', $result, 0);
	return;
}

sub ll_listinfo($){
	my ($hash) = @_;
	my $result = LISTENLIVE_SendCommand($hash, 'LISTINFO');
	readingsSingleUpdate($hash, 'listinfo', $result, 1);
	return;
}

sub ll_metainfo($){
	my ($hash) = @_;
	my $result = LISTENLIVE_SendCommand($hash, 'METAINFO');
	my @mi = split('=',$result);
	readingsBeginUpdate($hash);
	for my $i (1..5){ 
		$mi[$i] = substr($mi[$i],0,length($mi[$i])-2) if($i != 5 && defined($mi[$i])); 
		readingsBulkUpdate($hash,"metainfo".$i, $mi[$i]) if(defined($mi[$i]));
	}
	readingsEndUpdate($hash,1);
	return;
}

sub ll_menuinfo($){
	my ($hash) = @_;
	my $result = LISTENLIVE_SendCommand($hash, 'MINFO');
	my @mi = split('=',$result);
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'mi_info', $result);
	readingsBulkUpdate($hash, 'mi_state', substr($mi[1],0,length($mi[1])-2)) if(defined($mi[1]));
	readingsBulkUpdate($hash, 'mi_app', $appList[substr($mi[1],0,length($mi[1])-2)]) if(defined($mi[1]));
	readingsBulkUpdate($hash, 'mi_mp', substr($mi[2],0,length($mi[2])-2)) if(defined($mi[2]));
	readingsBulkUpdate($hash, 'mi_ms', $mi[3]);
	readingsEndUpdate($hash,1);
	return;
}

sub ll_volume($){
	my ($hash) = @_;
	my $result = LISTENLIVE_SendCommand($hash, 'VOLUME');
	(undef, $result) = split('=',$result);
	readingsSingleUpdate($hash, 'volume', $result, 1);
	return;
}

sub ll_power($){
	my ($hash) = @_;
	my $result = LISTENLIVE_SendCommand($hash, 'STATE');
	(undef, $result) = split('=',$result);
	readingsSingleUpdate($hash, 'power', $result, 1);
	return;
}

#### Funktionen zur Anbindung an remotecontrol

sub HMT350_RCmakenotify($$) {
	my ($nam, $ndev) = @_;
	my $nname="notify_$nam";
	my $cmd = "$nname notify $nam set $ndev rc \$EVENT";
	my $ret = CommandDefine(undef, $cmd);
	if($ret)	{ Log3(undef, 2, "remotecontrol ERROR $ret"); }
	else		{ Log3(undef, 3, "remotecontrol HMT350: $nname created as notify"); }
	return "Notify created: $nname";
}

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
not to be translated
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
<br>
commandGroup message<br>
message [&lt;textMessage&gt;]
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
  <li><b>listinfo</b> - current selection list on device and position in it</li>
  <li><b>metainfo1-5</b> - metainfo for currently playing stream</li>
  <li><b>mi_info</b> - current menu state</li>
  <li><b>mi_app, mi_mp, mi_ms, mi_state</b> - readings splitted from mi_info, mi_app is derived from numerical mi_state</li>
  <li><b>mute</b> - current mute state ("on" =&gt; muted, "off" =&gt; unmuted)</li>
  <li><b>power</b> - current power state</li>
  <li><b>state</b> - current device state (online or offline)</li>
  <li><b>volume</b> - current volume level</li>
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
Sorry, keine deutsche Dokumentation vorhanden.<br/><br/>
Die englische Doku gibt es hier: <a href='http://fhem.de/commandref.html#LISTENLIVE'>LISTENLIVE</a><br/>
</ul>
=end html_DE
=cut

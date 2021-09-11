# $Id$
#########################################################
# 	
#	RFHEM
#	Copyright by chris1284
#
# 23.8.21 : Modified by Admimarantis
#	Using Net::Ping for more stable detection of host
#	Improved display of status/errors in reading
#	added extra handling to sync "state" reading in case of plan "set xxx on" to be synced
#	completed "events" case to actually issue a command if limited to certain events
# 11.9.21 :
#	Added deprecation message since FHEM2FHEM now covers all functionality in a better way
#
#########################################################
package main;

use strict;
use warnings;
use Net::Ping;

sub RFHEM_GetUpdate($);
sub RFHEM_GetNet($$);
sub RFHEM_Set($@);
sub RFHEM_Define($$);
sub RFHEM_Undef($$);
sub RFHEM_Notify($$);

my %sets = (
  "cmd"   => "",
);
sub RFHEM_Initialize($)
{
  my ($hash) = @_;

	$hash->{DefFn}		=	"RFHEM_Define";	
	$hash->{FW_detailFn}  = "RFHEM_Detail";
	$hash->{FW_deviceOverview} = 1;
	$hash->{UndefFn}	=	"RFHEM_Undef";	
	$hash->{SetFn}		=	"RFHEM_Set";	
	$hash->{NotifyFn}	=	"RFHEM_Notify";		
	$hash->{AttrList}	=	"dummy:1,0 " .
							"RFHEMdevs " .
							"RFHEMevents " .
							$readingFnAttributes; 
}
sub RFHEM_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);
	return "wrong syntax: define <name> RFHEM host[:port] [pw]" if(@a < 2 || @a > 4 ) ;
	my $name 	= $a[0];   
	my $devstate = "created"; 
	my $inter	= 900; 
	my $dev = $a[2];
	my $port = "7072" if($dev !~ m/^.+:[0-9]+$/);
	if($dev =~ m/^.+:[0-9]+$/) 
	{ 
		my @temp = split(":", $dev);
		$port = $temp[1];
		$dev = $temp[0];
	}
	$hash->{NAME} 	= $name;
	$hash->{HOSTNAME} 	= $dev;
	$hash->{PORT} 	= $port;
	$hash->{PASSWORD} = $a[3] if(@a == 4);
	$hash->{STATE}		= $devstate;
	$hash->{Interval}	= $inter;
	InternalTimer(gettimeofday()+2, "RFHEM_GetUpdate", $hash, 0);
	Log3 $name, 1, "RFHEM is deprecated, please use FHEM2FHEM"; 
	return undef;
}
sub RFHEM_Undef($$)
{
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);    
  return undef;
}
sub RFHEM_Set($@)
{
	my ( $hash, @a ) = @_;
	return "\"set RFHEM\" needs at least an argument" if ( @a < 2 );
	return "Unknown argument $a[1], choose one of ".join(" ", sort keys %sets) if(!defined($sets{$a[1]}));
	my $name = shift @a;
	shift @a;
	my $command = join(" ",@a);
	my $HOSTNAME = $hash->{HOSTNAME};
	my $HOSTPORT = $hash->{PORT};
	my $HOSTPW = $hash->{PASSWORD} if ($hash->{PASSWORD});
	#my $socket = IO::Socket::INET->new('PeerAddr' => $HOSTNAME,'PeerPort' => $HOSTPORT,'Proto' => 'tcp') or die Log3 $name, 3, "Can't create socket ($!)\n";
	my $socket = IO::Socket::INET->new('PeerAddr' => $HOSTNAME,'PeerPort' => $HOSTPORT,'Proto' => 'tcp', Blocking => 0) ;
	if (!$socket) {
		readingsSingleUpdate($hash,"statedev","can't open FHEM port",1);
		return;
	}
    my $msg = $command."\n" ;
    #Log3 $name, 3, "$msg";
	my $ret =  RFHEM_GetNet($hash,$HOSTNAME);
	if ( $ret) {
		Log3 $name, 3, "Host present, executing command..."; 
		syswrite($socket, $HOSTPW . "\n")if($hash->{PASSWORD});
		print $socket $msg;
		Log3 $name, 3, "Command executed:$msg"; 
		$socket->close();
	}
	else { Log3 $name, 3, "Error: host not present!"; }
	#Log3 $name, 3, "Connection closed";
	return undef;
}
sub RFHEM_GetUpdate($)
{
	my ($hash) = @_;
	my $hostname = $hash->{HOSTNAME};
	my $name = $hash->{NAME};
	InternalTimer(gettimeofday()+$hash->{Interval}, "RFHEM_GetUpdate", $hash, 1);
	RFHEM_GetNet($hash,$hostname);
}

sub RFHEM_GetNet($$)
{
	my ($hash, $hostname) = @_;
	my $name  = $hash->{NAME};
	my $p = Net::Ping->new();
	my $ret;
	eval { $ret=$p->ping($hostname,0.5) };
	if ($@) {
		Log3 $name, 3 , $@;
		readingsSingleUpdate($hash,"statedev","unknown hostname",1);
		return 0;
	}
	$p->close();
	if ($ret) {
		readingsSingleUpdate($hash,"statedev","present",1);
	} else {
		readingsSingleUpdate($hash,"statedev","absent",1);
	}
	return $ret;
}

sub RFHEM_Notify($$)
{
	my ($hash, $extDevHash) = @_;
	my $name = $hash->{NAME}; # name RFHEM device
	my $extDevName = $extDevHash->{NAME}; # name externes device 
	my @devnames = split( ",", AttrVal($name,"RFHEMdevs",""));
	my @myevents = split( ",", AttrVal($name,"RFHEMevents",".*"));
	my $event;
	my $extevent;
	return "" if(IsDisabled($name)); # wenn attr disabled keine reaktion	
	foreach my $devname (@devnames){
		if ($extDevName eq $devname) { #wenn devicename extern zu unserne überwachten passt ...
			if ($myevents[0] eq ".*"){
				Log3 $name , 3,  "RFHEM $name - triggered by Device:$extDevName (all events) ...";
				foreach $extevent (@{$extDevHash->{CHANGED}}) { #für jedes event des externen device / dort geänderte readings
						my @eventparts = split (": ", $extevent);
						if (@eventparts == 1) {
							Log3 $name , 3,  "RFHEM adding state";
							unshift @eventparts, 'state';
						}
						Log3 $name , 3,  "RFHEM $name - event(@eventparts): $eventparts[0] with value $eventparts[1] ...";
						my $setcmd = "set $name cmd setreading $extDevName $eventparts[0] $eventparts[1]";
						fhem( $setcmd );
				}
			}
			else {
				foreach $extevent (@{$extDevHash->{CHANGED}}) { #für jedes event des externen device / dort geänderte readings
					my @exteventparts = split (": ", $extevent);
					foreach $event (@myevents) { # mit jedme event aus rhfme attribut
						if ($event eq $exteventparts[0]) { 
							Log3 $name , 3,  "RFHEM $name - triggered by Device:$extDevName with event $event";
							my @eventparts = split (": ", $extevent);
							if (@eventparts == 1) {
								unshift @eventparts, 'state';
							}
							Log3 $name , 3,  "RFHEM $name - event: $eventparts[0] with value $eventparts[1] ...";
						    my $setcmd = "set $name cmd setreading $extDevName $eventparts[0] $eventparts[1]";
						    fhem( $setcmd );							
						}
					}
				}
			}
		}
	}
}

sub RFHEM_Detail {
	my ($FW_wname, $name, $room, $pageHash) = @_;
	my $hash=$defs{$name};
	my $ret = "";
	return "RFHEM is deprecated and will be removed soon. All RFHEM functionality is now available in FHEM2FHEM.<br><br>If you need assistance for the migration please refer to the <a href=https://forum.fhem.de/index.php/topic,23638.msg1174044.html#new>forum</a><br>";
}

1;
=pod
=item helper
=item summary RFHEM is deprecated - please use FHEM2FHEM 
=item summary_DE RFHEM ist veraltet - bitte FHEM2FHEM verwenden
=begin html

<a name="RFHEM"></a>
<h3>RFHEM</h3>
<ul>This module is a easy helper module to connect separate FHEM installations</ul>
<ul>You can send commands to other installations or send them automatically.</ul>
<b>Define</b>
<ul><code>define &lt;Name&gt; RFHEM &lt;hostname[:port]&gt; &lt;[pw]&gt;</code></ul><br>
<ul><code>define remotePI RFHEM christian-pi test123</code></ul><br>
<a name="RFHEM set"></a>
<b>Set</b>
<ul><code>set &lt;Name&gt; cmd &lt;fhem command&gt;</code></ul><br>
<ul><code>set remotePI cmd set lampe on</code></ul>
<b>Attribute</b>
<li>RFHEMdevs<br>
        a list of devices separated by comma
		all events of this devices will be set on the remote installation automatically
		there must be device with the same nameon the other side (dummys)
</li><br>
<li>RFHEMevents<br>
        a list of events separated by comma
		all events of RFHEMdevs will be set on the remote installation automatically
</li><br>
<ul>this modul can be perfectly used with notify:</ul>
<ul><code>define LichtschlauchNotify notify wz.LichtschlauchDummy { fhem "set RemotePI cmd set Wohnzimmer.Lichtschlauch $EVENT" }</code></ul><br>
=end html

=begin html_DE

<a name="RFHEM"></a>
<h3>RFHEM</h3>
<ul>Dieses modul verbindet auf einfache Art separate FHEM isnatllationen.</ul>
<ul>Man kann damit einfache Befehle an andere Installationen sendne oder automatisch senden lassen.</ul>
<b>Define</b>
<ul><code>define &lt;Name&gt; RFHEM &lt;hostname[:port]&gt; &lt;[pw]&gt;</code></ul><br>
<ul><code>define remotePI RFHEM christian-pi test123</code></ul><br>
<a name="RFHEM set"></a>
<b>Set</b>
<ul><code>set &lt;Name&gt; cmd &lt;fhem befehl&gt;</code></ul><br>
<ul><code>set remotePI cmd set lampe on</code></ul>
<b>Attribute</b>
<li>RFHEMdevs<br>
        Eine durch Komma getrennte Liste von Geräten.
		Alle Events dieser Geräte werden autom. an die entfernte Installation gesendet. Auf der entfernten Seite muss es das Gerät mit selben Namen geben (zb ein Dummy).
</li><br>
<li>RFHEMevents<br>
        Eine durch Komma getrennte Liste von Events.
		Alle diese Events ( der Geräte aus RFHEMdevs) werden autom. an die entfernte Installation gesendet
</li><br>
<ul>Man kann dieses Modul zb auch in verbindung mit notify nutzen:</ul>
<ul><code>define LichtschlauchNotify notify wz.LichtschlauchDummy { fhem "set RemotePI cmd set Wohnzimmer.Lichtschlauch $EVENT" }</code></ul><br>
=end html_DE
=cut
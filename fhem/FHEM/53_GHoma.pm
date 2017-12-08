##############################################
# $Id$
#
# Protokoll:
# Prefix (5a a5), Anzahl Nutzbytes (2 Byte), Payload, Checksumme (FF - LowByte der Summe aller Payloadbytes), Postfix (5b b5)
# Antwort von Dose hat immer die letzen 3 Bloecke der MAC vom 11-13 Byte
#
# Payload immer in "|"
#
#Init1 (vom Server):
# 5a a5 00 07|02 05 0d 07 05 07 12|c6 5b b5
#                ** ** ** ** ** **													** scheinen zufaellig zu sein
# 5a a5 00 01|02|fd 5b b5
#Antwort auf Init1 von Dose:
# 5A A5 00 0B|03 01 0A C0 32 23 62 8A 7E 01 C2|AF 5B B5
#                               MM MM MM    **										MM: letzte 3 Stellen der MAC, ** scheinbar eine Checksumme basierend auf den 6 zufaelligen Bytes von Init1
#                         ?? ??                                                     ??: Unterschiedlich bei verschiedenen Steckermodellen
#Init2 (vom Server):
# 5a a5 00 02|05 01|f9 5b b5
#Antwort auf Init2 von Dose:
# 5A A5 00 12|07 01 0A C0 32 23 62 8A 7E 00 01 06 AC CF 23 62 8A 7E|5F 5B B5
#                               MM MM MM											MM: letzte 3 Stellen der MAC
#                                                 MM MM MM MM MM MM					MM: komplette MAC
#                         ?? ??                                                     ??: Unterschiedlich bei verschiedenen Steckermodellen
# 5A A5 00 12|07 01 0A C0 32 23 62 8A 7E 00 02 05 00 01 01 08 11|4C 5B B5    			Anzahl Bytes stimmt nicht! ist aber immer so
# 5A A5 00 15|90 01 0A E0 32 23 62 8A 7E 00 00 00 81 11 00 00 01 00 00 00 00|32 5B B5		Status der Dose (wird auch immer bei Zustandsaenderung geschickt)
#                               MM MM MM											MM: letzte 3 Stellen der MAC
#                                                 qq								qq: Schaltquelle 	81=lokal geschaltet, 11=remote geschaltet
#                                                                         oo 		oo: Schaltzustand	ff=an, 00=aus
#                         ?? ??                                                     ??: Unterschiedlich bei verschiedenen Steckermodellen
# Danach kommt alle x Sekunden ein Heartbeat von der Dose:
# 5A A5 00 09|04 01 0A C0 32 23 62 8A 7E|71 5B B5
#                               MM MM MM
#                         ?? ??                                                     ??: Unterschiedlich bei verschiedenen Steckermodellen
# Antwort vom Server (wenn die nicht kommt blinkt Dose wieder und muss neu initialisiert werden):
# 5a a5 00 01|06|f9 5b b5
#---------------------------------------------------------------------------------------------------------
# Einschalten der Dose:
# 5a a5 00 17|10 01 01 0a e0 32 23 62 8a 7e ff fe 00 00 10 11 00 00 01 00 00 00 ff|26 5b b5
#                                  MM MM MM
#                            ?? ??                                                     ??: Unterschiedlich bei verschiedenen Steckermodellen
# Ausschalten der Dose
# 5a a5 00 17|10 01 01 0a e0 32 23 62 8a 7e ff fe 00 00 10 11 00 00 01 00 00 00 00|25 5b b5
#                                  MM MM MM
#                            ?? ??                                                     ??: Unterschiedlich bei verschiedenen Steckermodellen
# beides wird quittiert (ebenso wird auch bei lokaler betaetigung quittiert) -> siehe 3. Antwort auf Init 2
package main;
use strict;
use warnings;
use SetExtensions;
use TcpServerUtils;

my $prefix =  pack('C*', (0x5a,0xa5));
my $postfix = pack('C*', (0x5b,0xb5));

my $init1a =  pack('C*', (0x02,0x05,0x0d,0x07,0x05,0x07,0x12));
my $init1b =  pack('C*', (0x02));
my $init2 =   pack('C*', (0x05,0x01));
my $hbeat =   pack('C*', (0x06));
my $switch1 = pack('C*', (0x10,0x01,0x01,0x0a,0xe0));
my $switch2 = pack('C*', (0xff,0xfe,0x00,0x00,0x10,0x11,0x00,0x00,0x01,0x00,0x00,0x00));

my $dosehb =  pack('C*', (0x00,0x09,0x04,0x01,0x0a,0xc0));
my $cinit1 =  pack('C*', (0x03,0x01,0x0a,0xc0));
my $cmac =    pack('C*', (0x07,0x01,0x0a,0xc0));
my $cswitch = pack('C*', (0x90,0x01,0x0a,0xe0));

my $timeout = 60;

#####################################
sub GHoma_Initialize($) {			#
  my ($hash) = @_;

  $hash->{SetFn}    = "GHoma_Set";		# evtl. noch in define rein!!!
  $hash->{DefFn}    = "GHoma_Define";
  $hash->{ReadFn}   = "GHoma_Read";		# wird von der globalen loop aufgerufen (ueber $hash->{FD} gefunden), wenn Daten verfuegbar sind
  $hash->{UndefFn}  = "GHoma_Undef";
  $hash->{AttrFn}   = "GHoma_Attr";
  $hash->{StateFn}  = "GHoma_State";
  $hash->{AttrList} = "restoreOnStartup:last,on,off restoreOnReinit:last,on,off blocklocal:yes,no ".
                      "allowfrom connectTimeout connectInterval";
  $hash->{noAutocreatedFilelog} = 1;		# kein Filelog bei Autocreate anlegen
  $hash->{ShutdownFn} = "GHoma_Shutdown";
}
#####################################
sub GHoma_ClientConnect($) {		# im Mom unnuetz
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  $hash->{DEF} =~ m/^(IPV6:)?(.*):(\d+)$/;
  my ($isIPv6, $server, $port) = ($1, $2, $3);

  Log3 $name, 4, "$name: Connecting to $server:$port...";
  my @opts = (
        PeerAddr => "$server:$port",
        Timeout => AttrVal($name, "connectTimeout", 60),
  );

  my $client;
  if($hash->{SSL}) {
    $client = IO::Socket::SSL->new(@opts);
  } else {
    $client = IO::Socket::INET->new(@opts);
  }
  if($client) {
    $hash->{FD}    = $client->fileno();
    $hash->{CD}    = $client;         # sysread / close won't work on fileno
    $hash->{BUF}   = "";
    $hash->{CONNECTS}++;
    $selectlist{$name} = $hash;
    $hash->{STATE} = "Connected";
    RemoveInternalTimer($hash);
    Log3 $name, 3, "$name: connected to $server:$port";
	syswrite($hash->{CD}, ( GHoma_BuildString($init1a) . GHoma_BuildString($init1b) ) );
	InternalTimer(gettimeofday()+ $timeout + 30, "GHoma_Timer", $hash,0);
  } else {
    GHoma_ClientDisconnect($hash, 1);
  }
}
#####################################
sub GHoma_ClientDisconnect($$) {	# im Mom unnuetz
  my ($hash, $connect) = @_;
  my $name   = $hash->{NAME};
  close($hash->{CD}) if($hash->{CD});
  delete($hash->{FD});
  delete($hash->{CD});
  delete($selectlist{$name});
  $hash->{STATE} = "Offline";
  InternalTimer(gettimeofday()+AttrVal($name, "connectInterval", 60),
                "GHoma_ClientConnect", $hash, 0);
  if($connect) {
    Log3 $name, 4, "$name: Connect failed.";
  } else {
    Log3 $name, 3, "$name: Offline";
  }
}
#####################################
sub GHoma_Shutdown($) {				#
  my ($hash) = @_;
  return unless defined $hash->{Id};        #nicht f?r Server
  # state auf letzten Schaltwert setzen oder auf fixen Startwert (wird bereitsbeim Shutdown ausgefuehrt)
  if      (AttrVal($hash->{NAME},"restoreOnStartup","last") eq "on") {
	readingsSingleUpdate($hash, "state", "on", 1);
  } elsif (AttrVal($hash->{NAME},"restoreOnStartup","last") eq "last" && defined $hash->{LASTSTATE} && $hash->{LASTSTATE} eq "on" ) {
	readingsSingleUpdate($hash, "state", "on", 1);
  } else {
	readingsSingleUpdate($hash, "state", "off", 1);
  }
  return undef;
}
#####################################
sub GHoma_Define($$$) {				#
  my ($hash, $def) = @_;

  #my @a = split("[ \t][ \t]*", $def);
  my ($name, $type, $pport, $global) = split("[ \t]+", $def);

  my $port = $pport;
  $port =~ s/^IPV6://;

  my $isServer = 1 if(defined($port) && $port =~ m/^\d+$/);
  my $isClient = 1 if($port && $port =~ m/^(.+):\d+$/);
  my $isSerCli = 1 if(defined($port) && $port =~ m/^([\da-f]{6})$/i);

  #return "Usage: define <name> GHoma { [IPV6:]<tcp-portnr>|<serverName:port> }" if(!($isServer || $isClient || $isSerCli));
  return "Usage: define <name> GHoma { [IPV6:]<tcp-portnr> }" if(!($isServer || $isClient || $isSerCli));

  #$hash->{DeviceName} = $pport;
  if($isSerCli) {				#ServerClient
	#my $name = $a[0];
  # my $addr = $a[2];
	#$hash->{Id} = pack('C*', ( hex(substr($pport,0,2)), hex(substr($pport,2,2)), hex(substr($pport,4,2)) ) );
	$hash->{Id} = $pport;
    return;
  }
  
  # Make sure that fhem only runs once
  if($isServer) {
    my $ret = TcpServer_Open($hash, $pport, "global");
    if($ret && !$init_done) {
      Log3 $name, 1, "$ret. Exiting.";
      exit(1);
    }
    return $ret;
  }

  if($isClient) {
    $hash->{isClient} = 1;
    GHoma_ClientConnect($hash);
  }
  return;
}
#####################################
sub GHoma_BuildString($) { 			# Botschaft zum senden erzeugen
  my ($data) = @_;
  my $count = pack('n*', length($data));
  my $checksum = pack ('C*', 0xFF - (unpack("%8c*", $data)) );
  
  #(my $smsg = ($prefix . $count . $data . $checksum . $postfix)) =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg;
  #Log3 undef, 1, "GHoma TX: $smsg";
  
  return $prefix . $count . $data . $checksum . $postfix;
}									#
#####################################
sub GHoma_moveclient($$) {			# Handles von temporaerem Client zu Statischem uebertragen und Temporaeren dann loeschen
  my ($thash, $chash) = @_;
  
    if(defined($chash->{CD})) { # alte Verbindung entfernen, falls noch offen
		close($chash->{CD});
		delete($chash->{CD}); 
		#delete($selectlist{$chash->{NAME}});
		delete($chash->{FD});  # Avoid Read->Close->Write
	}
  	$chash->{FD} = $thash->{FD};
	$chash->{CD} = $thash->{CD};
	$chash->{SNAME} = $thash->{SNAME};
	my @client = split("_",$thash->{NAME});
	$chash->{IP} = $client[1];
	$chash->{PORT} = $client[2];
	$selectlist{$chash->{NAME}} = $chash;
	readingsSingleUpdate($chash, "state", "Initialize...", 1);
	delete($selectlist{$thash->{NAME}});
	delete $thash->{FD};
	CommandDelete(undef, $thash->{NAME});
	syswrite( $chash->{CD}, GHoma_BuildString($init2) );
	InternalTimer(gettimeofday()+ $timeout, "GHoma_Timer", $chash,0);
}
#####################################
sub GHoma_Read($) {					# wird von der globalen loop aufgerufen (ueber $hash->{FD} gefunden), wenn Daten verfuegbar sind
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if($hash->{SERVERSOCKET}) {   # Accept and create a child
    my $chash = TcpServer_Accept($hash, "GHoma");
    return if(!$chash);	
    Log3 $name, 4, "$name: angelegt: $chash->{NAME}";
    syswrite($chash->{CD}, ( GHoma_BuildString($init1a) . GHoma_BuildString($init1b) ) );
	InternalTimer(gettimeofday()+ $timeout, "GHoma_Timer", $chash,0);
    $chash->{CD}->flush();
    return;
  }

  my $buf;
  my $ret = sysread($hash->{CD}, $buf, 256);
  if(!defined($ret)) {
    if($hash->{isClient}) {
      Log3 $name, 1, "$name \$buf nicht definiert";
      GHoma_ClientDisconnect($hash, 0);
    } else {
      CommandDelete(undef, $name);
    }
    return;
  }
  
  if ( substr($buf,0,8) eq ($prefix . $dosehb )) {     									# Heartbeat (Dosen Id wird nicht ueberprueft)
	#DevIo_SimpleWrite($hash, GHoma_BuildString($hbeat) , undef);
	RemoveInternalTimer($hash);
	$buf =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg;		#empfangene Zeichen in Hexwerte wandeln
	Log3 $name, 5, "$name Heartbeatanfrage empfangen: $buf";
    syswrite( $hash->{CD}, GHoma_BuildString($hbeat) );
    Log3 $hash, 5, "$hash->{NAME} Heartbeat gesendet";
    InternalTimer(gettimeofday()+ $timeout, "GHoma_Timer", $hash,0);
  } else {																					# alles ausser Heartbeat
	my @msg = split(/$prefix/,$buf);
	foreach (@msg) {
		next if ( $_ eq "" );
		if ( hex(unpack('H*', substr($_,length($_)-2,2))) != hex(unpack('H*', $postfix ))) {								# Check Postfix
			Log3 $hash, 1, "$hash->{NAME} Fehler: postfix = " . unpack('H*', substr($_,length($_)-2,2));
			next;
		}
		if ( hex(unpack('H*', substr($_,length($_)-3,1))) != ( 0xFF - unpack("%8c*", substr($_,2,length($_)-5) ) ) ) {		# Check Checksum
			Log3 $hash, 1, "$hash->{NAME} Fehler: Checksum soll = " . hex(unpack('H*', substr($_,length($_)-3,1))) . " ist = ". ( 0xFF - unpack("%8c*", substr($_,2,length($_)-5) ) );
			next;
		}
		if ( hex(unpack('H*', substr($_,0,2))) != ( length($_) - 5 ) ) {													# Check Laenge
			Log3 $hash, 4, "$hash->{NAME} laengesoll = " . hex(unpack('H*', substr($_,0,2))) . " laengeist = " . ( length($_) - 5 )
		}
		
		(my $smsg = $_) =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg;							# empfangene Zeichen in Hexwerte wandeln
		Log3 $hash, 5, "$hash->{NAME} RX: 5A A5 $smsg";										# ...und ins Log schreiben
		
		$hash->{Pattern} = unpack('H*', substr($_,6,2) ) unless defined $hash->{Pattern};
		
		if ( substr($_,2,4) eq ($cinit1)) {  												# Antwort auf erstes Init
			$hash->{Id} = unpack('H*', substr($_,8,3) );
			unless ($hash->{isClient}) {
				# fuer Server Loesung bei erster Antwort von Dose nach bestehendem Device mit gleicher Id suchen und Verbindung auf dieses Modul uebertragen
				my $clientdefined = undef;
				foreach my $dev (devspec2array("TYPE=$hash->{TYPE}")) {		# bereits bestehendes define mit dieser Id suchen
					if ($hash->{Id} eq InternalVal($dev,"Id","") && $hash->{NAME} ne $dev && InternalVal($dev,"TEMPORARY","") ne "1") {
						#Log3 $hash, 5, "$hash->{NAME}: $dev passt -> Handles uebertragen";
						GHoma_moveclient($hash, $defs{$dev});
						$clientdefined = 1;
						last
					}
				}
				unless ( defined $clientdefined) {							# ...ein Neues anlegen, falls keins existiert
					Log3 $name, 4, "GHoma Unknown device $hash->{Id}, please define it";
					DoTrigger("global", "UNDEFINED GHoma_$hash->{Id} GHoma $hash->{Id}");
					GHoma_moveclient($hash, $defs{"GHoma_$hash->{Id}"}) if ($defs{"GHoma_$hash->{Id}"});
				}
			} else {
				readingsSingleUpdate($hash, "state", "Initialize...", 1);
				syswrite( $hash->{CD}, GHoma_BuildString($init2) );
				RemoveInternalTimer($hash);
				InternalTimer(gettimeofday()+ $timeout, "GHoma_Timer", $hash,0);
			}
		} elsif ( substr($_,2,4) eq $cmac && substr($_,8,3) eq substr($_,17,3) ) {			# Nachricht mit MAC (kommt unter Anderem als Antwort auf Init2)
			my $mac;
			for my $i (0...5) {			# MAC formattieren
				$mac .= sprintf("%.2X",ord( substr($_,14+$i,1) ));
				last if $i == 5;
				$mac .= ":";
			}
			$hash->{MAC} = $mac;
		} elsif ( substr($_,2,4) eq $cswitch && (( length($_) - 5 ) == 0x15 ) ) {			# An oder Aus
			my $id = unpack('H*', substr($_,8,3) );
			my $rstate = hex(unpack('H*', substr($_,22,1))) == 0xFF ? "on" : "off";
            my $src    = hex(unpack('H*', substr($_,14,1))) == 0x81 ? "local" : "remote";
			if ( defined $hash->{LASTSTATE} && $hash->{STATE} eq "Initialize..." ) {	# wenn dies erste Statusbotschaft nach Anmeldung
				my $nstate = AttrVal($name, "restoreOnReinit", "last");
				if ( $nstate ne "last" && $nstate ne $rstate ) {
					GHoma_Set( $hash, $hash->{NAME}, $nstate );
				} elsif ($nstate eq "last" && $hash->{LASTSTATE} ne $rstate) {
					GHoma_Set( $hash, $hash->{NAME}, $hash->{LASTSTATE} );
				}				
			} elsif ($src eq "local") {								# bei schalten direkt an Steckdose soll...  
				if (AttrVal($name, "blocklocal", "no") eq "yes") {	# ...wieder zurueckgeschaltet werden, wenn Attribut blocklocal yes ist
					GHoma_Set($hash, $hash->{NAME}, $hash->{LASTSTATE});
				} else {											# ...laststate angepasst werden (um bei reinit richtigen wert zu haben)
					$hash->{LASTSTATE} = $rstate;
				}
			}

			if (defined $hash->{SNAME} && defined $defs{$hash->{SNAME}} ) {	# Readings auch im Server eintragen
				readingsBeginUpdate($defs{$hash->{SNAME}});
				readingsBulkUpdate($defs{$hash->{SNAME}}, $id .'_state', $rstate);
				readingsBulkUpdate($defs{$hash->{SNAME}}, $id .'_source', $src);
				readingsEndUpdate($defs{$hash->{SNAME}}, 1);
			}
			
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash, 'state', $rstate);
			readingsBulkUpdate($hash, 'source', $src);
			readingsEndUpdate($hash, 1);
		} 
    }
  }
  #Log3 $name, 5, "$name empfangen: $buf";
  return
}
#####################################
sub GHoma_Timer($) {					# wird ausgeloest wenn heartbeat nicht mehr kommt
  my ($hash) = @_;
  Log3 $hash, 3, "$hash->{NAME}: Timer abgelaufen";
  readingsSingleUpdate($hash, "state", "offline", 1);
  GHoma_ClientDisconnect($hash, 0) if $hash->{isClient};
  return TcpServer_Close($hash) if defined $hash->{FD};
  #DevIo_Disconnected($hash);
}
#####################################
sub GHoma_Attr(@) {					#
  my ($command, $name, $attr, $val) = @_;
  my $hash = $defs{$name};
  
	#  if($a[0] eq "set" && $a[2] eq "SSL") {
	#    TcpServer_SetSSL($hash);
	#    if($hash->{CD}) {
	#      my $ret = IO::Socket::SSL->start_SSL($hash->{CD});
	#      Log3 $a[1], 1, "$hash->{NAME} start_SSL: $ret" if($ret);
	#    }
	#  }

  return undef;
}
#####################################
sub GHoma_Set($@) {					#
  my ($hash, @a) = @_;
  my $name = $a[0];
  my $type = $a[1];
  return "Unknown argument $type, choose one of ConfigAll" unless (defined $hash->{Id} || $type eq "ConfigAll");	# set fuer den Server
  my @sets = ('on:noArg', 'off:noArg');
  
  my $status = ReadingsVal($hash->{NAME},"state","");
  
  if($type eq "ConfigAll") {
	GHoma_udpbroad($hash, defined $a[2] ? $a[2] : undef);
  } elsif($type eq "on") {
	$type = pack('C*', (0xff));
	readingsSingleUpdate($hash, "state", "set_on", 1) if ( $status =~ m/([set_]?o[n|ff])$/i );
	$hash->{LASTSTATE} = "on";
  } elsif($type eq "off") {
	$type = pack('C*', (0x00));
	readingsSingleUpdate($hash, "state", "set_off", 1) if ( $status =~ m/([set_]?o[n|ff])$/i );
	$hash->{LASTSTATE} = "off";
  } else {
  	my $slist = join(' ', @sets);
	return SetExtensions($hash, $slist, @a);
  }
  if (defined $hash->{CD}) {
  	Log3 $hash, 2, "$hash->{NAME}: Pattern noch nicht empfangen" unless defined $hash->{Pattern};
	syswrite( $hash->{CD}, GHoma_BuildString($switch1  . pack('C*', ( hex(substr($hash->{Pattern},0,2)), hex(substr($hash->{Pattern},2,2)) ) ) . pack('C*', ( hex(substr($hash->{Id},0,2)), hex(substr($hash->{Id},2,2)), hex(substr($hash->{Id},4,2)) ) ) . $switch2 . $type) );
  }
  return undef;
}
#####################################
sub GHoma_State($$$$) {				# reload readings at FHEM start
	my ($hash, $tim, $sname, $sval) = @_;
	Log3 $hash, 4, "$hash->{NAME}: $sname kann auf $sval wiederhergestellt werden $tim";
	if ( $sname eq "state" 	&& defined $hash->{Id} ) {        #wenn kein Server
		$hash->{LASTSTATE} = $sval;
		readingsSingleUpdate($hash, "state", "offline", 1)
	}
	return;
}
#####################################
sub GHoma_Undef($$) {				#
  my ($hash, $arg) = @_;
  RemoveInternalTimer($hash);
  return TcpServer_Close($hash) if defined $hash->{FD};
}
#####################################
sub GHoma_udpbroad {
  eval "use IO::Socket::INET;";
	return "please install IO::Socket::INET" if($@);
  my ($hash, $ownIP) = @_;	
  
  # flush after every write
  $| = 1;

  my ($socket,$data);
  $socket = new IO::Socket::INET (
	PeerAddr  => '255.255.255.255',
	PeerPort  =>  '48899',
	Proto     => 'udp',
	Broadcast => 1
  ) or die "ERROR in Socket Creation : $!\n";

#send operation
  unless (defined $ownIP) {
  	my $ownIPl = `hostname -I`;
  	my @ownIPs = grep { /^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$/ } split / /, $ownIPl;
  	$ownIP = $ownIPs[0];
  } else {
    return "$ownIP ist not an correct IP or hostname" unless $ownIP =~ /^((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))|(([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*)+(\.([a-zA-Z0-9]+(-[a-zA-Z0-9]+)*))*$)$/
  }
  Log3 $hash, 1, "$hash->{NAME}: setting server address for GHoma plugs to $ownIP:$hash->{PORT}";
  my @sdata = (
    "HF-A11ASSISTHREAD",
	"+ok",
	"AT+NETP=TCP,Client,$hash->{PORT},$ownIP\r",
	"AT+TCPTO=120\r"
	);
  foreach (@sdata) {
  	$socket->send($_);
	Log3 $hash, 1, "$hash->{NAME}: sende Multicast: $_";
  }
  $socket->close();

}

1;

=pod
=item device
=item summary controls an G-Homa wlan adapter plug
=item summary_DE Steuerung einer G-Homa Wlan Steckdose
=begin html

<a name="GHoma"></a>
<h3>GHoma</h3>
(en | <a href="commandref_DE.html#GHoma">de</a>)
<ul>
  <ul>
  Connects fhem to an G-Homa adapter plug<br><br>
  <b>preliminary:</b><br>
    <li>Configure WLAN settings (Firmware <= 1.06):<br>
      bring device in AP mode (press button for more than 3s, repeat this step until the LED is permanently on)<br>
      Now connect with your computer to G-Home network.<br>
      Browse to 10.10.100.254 (username:password = admin:admin)<br>
      In STA Setting insert your WLAN settings<br>
    </li>
    <li>Configure WLAN settings:<br>
      bring device in AP mode (press button for more than 3s, repeat this step until the LED is permanently on)<br>
      Configure WLAN with G-Homa App.<br>
    </li>
    <li>Configure Network Parameters setting (Firmware <= 1.06):<br>
      Other Setting -> Protocol to TCP-Client<br>
      Other Setting -> Port ID (remember value for FHEM settings)<br>
	  Other Setting -> Server Address (IP of your FHEM Server)<br>
    </li>
    <li>Configure Network Parameters settings:<br>
      Use <code>set ... ConfigAll</code> from server device to set parameters automaticly.<br>
    </li>
    
    <li>Optional:<br>
      Block all outgoing connections for G-Homa in your router.<br>
    </li>
  </ul>
  <br><br>
  
  <a name="GHomadefine"></a>
  <b>Define</b><br>
  <ul>
  <code>define &lt;name&gt; GHoma &lt;port&gt;</code> <br>
  Specifies the GHoma server device.<br>
  New adapters will be added automaticaly after first connection.<br>
  You can also manyally add an adapter:<br>
  <code>define &lt;name&gt; GHoma &lt;Id&gt;</code> <br>
  where <code>Id</code> is the last 6 numbers of the plug's MAC address<br>
  Example: MAC= AC:CF:23:A5:E2:3B -> Id= A5E23B<br>
  <br>
  </ul>
  <a name="GHomaset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is one of:<br>
    <ul><code>
        off<br>
        on<br>		
      </code>
    </ul>
    The <a href="#setExtensions"> set extensions</a> are also supported.<br>
    <br>
	For server device:
	<code>set &lt;name&gt; ConfigAll [IP|hostname|FQDN]</code><br>
	Setting all GHoma plugs via UDP broadcast to TCP client of FHEM servers address and port of GHoma server device.<br>
  </ul>

  <a name="GHomaattr"></a>
  <b>Attributes</b><br>
  <ul>
    For plug devices:
    <ul><li>restoreOnStartup<br>
      Restore switch state after reboot<br>
      Default: last, valid values: last, on, off<br><br>
    </li>
	<li>restoreOnReinit<br>
      Restore switch state after reconnect<br>
      Default: last, valid values: last, on, off<br><br>
    </li>
	<li>blocklocal<br>
      Restore switch state to reading state immideately after local switching<br>
      Default: no, valid values: no, yes<br><br>
    </li></ul>
	For server devices:
    <ul><li>allowfrom<br>
        Regexp of allowed ip-addresses or hostnames. If set,
        only connections from these addresses are allowed.<br><br>
    </li></ul>
	<li><a href="#readingFnAttributes">readingFnAttributes</a></li> 
  </ul>
<br>
</ul>

=end html

=begin html_DE

<a name="GHoma"></a>
<h3>GHoma</h3>
(<a href="commandref.html#GHoma">en</a> | de)
<ul>
  <ul>
  Verbindet fhem mit einem G-Homa Zwischenstecker<br><br>
  <b>Vorbereitung:</b><br>
    <li>WLAN konfigurieren (bis Firmware 1.06):<br>
      Ger&auml;t in den AP modus bringen (Knopf f&uuml;r mehr als 3s dr&uuml;cken, diesen Schritt wiederholen bis die LED permanent leuchtet)<br>
      Nun einen Computer mit der SSID G-Home verbinden.<br>
      Im Browser zu 10.10.100.254 (username:passwort = admin:admin)<br>
      In STA Setting WLAN Einstellungen eintragen<br>
    </li>
    <li>WLAN konfigurieren:<br>
      Ger&auml;t in den AP modus bringen (Knopf f&uuml;r mehr als 3s dr&uuml;cken, diesen Schritt wiederholen bis die LED permanent leuchtet)<br>
      Mit der G-Homa App das WLAN des Zwischensteckers einstellen<br>
    </li>
    <li>Network Parameters settings (bis Firmware 1.06):<br>
      Other Setting -> Protocol auf TCP-Server<br>
      Other Setting -> Port ID (wird sp&auml;ter f&uuml;r FHEM ben&ouml;tigt)<br>
	  Other Setting -> Server Address (IP Adresse des FHEM Servers)<br>
    </li>
    <li>Network Parameters settings:<br>
      &Uuml;ber <code>set ... ConfigAll</code> des Server Ger&auml;tes die Parameter automatisch setzen.<br>
    </li>
    <li>Optional:<br>
      Im Router alle ausgehenden Verbindungen f&uuml;r G-Homa blockieren.<br>
    </li>
  </ul>
  <br><br>
  
  <a name="GHomadefine"></a>
  <b>Define</b><br>
  <ul>
  <code>define &lt;name&gt; GHoma &lt;port&gt;</code> <br>
  Legt ein GHoma Server device an.<br>
  Neue Zwischenstecker werden beim ersten verbinden automatisch angelegt.<br>
  Diese k&ouml;nnen aber auch manuell angelegt werden:<br>
  <code>define &lt;name&gt; GHoma &lt;Id&gt;</code> <br>
  Die <code>Id</code> besteht aus den letzten 6 Stellen der MAC Adresse des Zwischensteckers.<br>
  Beispiel: MAC= AC:CF:23:A5:E2:3B -> Id= A5E23B<br>
  <br>
  </ul>
  <a name="GHomaset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    G&uuml;ltige Werte f&uuml;r <code>value</code>:<br>
    <ul><code>
        off<br>
        on<br>		
      </code>
    </ul>
    Die <a href="#setExtensions"> set extensions</a> werden auch unterst&uuml;tzt.<br>
    <br>
  	F&uuml;r Server Device:
	<code>set &lt;name&gt; ConfigAll [IP|hostname|FQDN]</code><br>
	Einstellen aller GHoma Zwischenstecker &uuml;ber UDP broadcast auf TCP client mit FHEM Server Adresse und Port des GHoma Server Devices.<br>
  </ul>

    
  
  <a name="GHomaattr"></a>
  <b>Attributes</b><br>
  <ul>
    F&uuml;r Zwischenstecker devices:
    <ul><li>restoreOnStartup<br>
      Wiederherstellen der Portzust&auml;nde nach Neustart<br>
      Standard: last, g&uuml;ltige Werte: last, on, off<br><br>
    </li>
	<li>restoreOnReinit<br>
      Wiederherstellen der Portzust&auml;nde nach Neustart<br>
      Standard: last, g&uuml;ltige Werte: last, on, off<br><br>
    </li>
	<li>blocklocal<br>
      Wert im Reading State sofort nach &Auml;nderung &uuml;ber lokale Taste wiederherstellen<br>
      Standard: no, g&uuml;ltige Werte: no, yes<br><br>
    </li></ul>
	F&uuml;r Server devices:
    <ul><li>allowfrom<br>
      Regexp der erlaubten IP-Adressen oder Hostnamen. Wenn dieses Attribut
      gesetzt wurde, werden ausschlie&szlig;lich Verbindungen von diesen
      Adressen akzeptiert.<br><br>
     </li></ul>
	<li><a href="#readingFnAttributes">readingFnAttributes</a></li> 
  </ul>
<br>
</ul>

=end html_DE

=cut
##############################################
# $Id: 00_Netzer_I2C.pm klausw
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub NetzerI2C_Attr(@);
sub NetzerI2C_HandleQueue($);
sub NetzerI2C_Read($);
#sub NetzerI2C_Ready($);
sub NetzerI2C_Write($$);

#my $clientsI2C = ":I2C_PCF8574:I2C_PCA9532:I2C_BMP180:FHT.*:";

#my %matchListI2C = (
#    "1:I2C_PCF8574"=> ".*",
#    "2:FHT"       => "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
#);

my @clients = qw(
I2C_LCD
I2C_DS1307
I2C_PC.*
I2C_MCP23017
I2C_BMP180
I2C_SHT21
);

sub NetzerI2C_Initialize($) {
  my ($hash) = @_;
  
  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
	$hash->{Clients} = join (':',@clients);
  $hash->{ReadFn}   = "NetzerI2C_Read";		#wird von der globalen loop aufgerufen (ueber $hash->{FD} gefunden), wenn Daten verfuegbar sind 
  $hash->{WriteFn}  = "NetzerI2C_Write";    #wird vom client per IOWrite($@) aufgerufen
  $hash->{ReadyFn}  = "NetzerI2C_Ready";
  $hash->{I2CWrtFn} = "NetzerI2C_Write";    #zum testen als alternative fuer IOWrite

# Normal devices
  $hash->{DefFn}   = "NetzerI2C_Define";
  $hash->{UndefFn} = "NetzerI2C_Undef";
  $hash->{GetFn}   = "NetzerI2C_Get";
  $hash->{SetFn}   = "NetzerI2C_Set";
	$hash->{NotifyFn}= "NetzerI2C_Notify";
  $hash->{AttrFn}  = "NetzerI2C_Attr";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "timeout socat:1,0";
}
#####################################
sub NetzerI2C_Define($$) {					#
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  unless(@a == 3) {
    my $msg = "wrong syntax: define <name> NetzerI2C {none | hostname:port}";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];

  #$hash->{Clients} = $clientsI2C;
  #$hash->{MatchList} = \%matchListI2C;

  if($dev eq "none") {
    Log3 $name, 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $hash->{DeviceName} = $dev;
  #my $ret = DevIo_OpenDev($hash, 0, "CUL_DoInit");
  my $ret = DevIo_OpenDev($hash, 0, "");
  return $ret;
}
#####################################
sub NetzerI2C_Notify {							#
  my ($hash,$dev) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
   	NetzerI2C_forall_clients($hash,\&NetzerI2C_Init_Client,undef);;
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}
#####################################
sub NetzerI2C_forall_clients($$$) {	#
  my ($hash,$fn,$args) = @_;
  foreach my $d ( sort keys %main::defs ) {
    if ( defined( $main::defs{$d} )
      && defined( $main::defs{$d}{IODev} )
      && $main::defs{$d}{IODev} == $hash ) {
       &$fn($main::defs{$d},$args);
    }
  }
  return undef;
}
#####################################
sub NetzerI2C_Init_Client($@) {			#
	my ($hash,$args) = @_;
	if (!defined $args and defined $hash->{DEF}) {
		my @a = split("[ \t][ \t]*", $hash->{DEF});
		$args = \@a;
	}
	my $name = $hash->{NAME};
	Log3 $name,1,"im init client fuer $name "; 
	my $ret = CallFn($name,"InitFn",$hash,$args);
	if ($ret) {
		Log3 $name,2,"error initializing '".$hash->{NAME}."': ".$ret;
	}
}
#####################################
sub NetzerI2C_Undef($$) {						#
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        Log3 $name, 3, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  DevIo_CloseDev($hash); 
  return undef;
}
#####################################
sub NetzerI2C_Set($@) {							#
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $type = shift @a;
  my $arg = join(" ", @a);
  my @sets = ('writeByte', 'writeByteReg', 'writeBlock');
	
  if($type eq "writeByte") {
    return "Usage: set $name i2csend <i2caddress> [<register address>] <data> [...<data>]"
        if(!$arg || $arg !~ /^[0-7][0-9A-F](\W[0-9A-F][0-9A-F]){0,64}$/xi);
		foreach (@a) {
			$_ = hex;
		}
		my $i2caddr = shift @a;
    my %sendpackage = ( i2caddress => $i2caddr, direction => "i2cwrite", data => join(" ", @a), direct=>1 );
		Log3 $hash, 1, "$sendpackage{data}";
		NetzerI2C_Write($hash, \%sendpackage);
  } elsif($type eq "writeByteReg") {
		return "Usage: set $name writeByteReg <i2caddress> <register address> <data> [...<data>]"
        if(!$arg || $arg !~ /^[0-7][0-9A-F](\W[0-9A-F][0-9A-F]){0,64}$/xi);
		foreach (@a) {
			$_ = hex;
		}
		my $i2caddr = shift @a;
		my $reg = shift @a;
		my %sendpackage = ( i2caddress => $i2caddr, direction => "i2cwrite", reg => $reg, data => join(" ", @a), direct=>1 );
		NetzerI2C_Write($hash, \%sendpackage);
	} elsif($type eq "writeBlock") {
		return "Usage: set $name writeBlock <i2caddress> <register address> <data> [...<data>]"
        if(!$arg || $arg !~ /^[0-7][0-9A-F](\W[0-9A-F][0-9A-F]){0,64}$/xi);
		foreach (@a) {
			$_ = hex;
		}
		my $i2caddr = shift @a;
		my $reg = shift @a;
		my %sendpackage = ( i2caddress => $i2caddr, direction => "i2cblockwrite", reg => $reg, data => join(" ", @a), direct=>1 );
		NetzerI2C_Write($hash, \%sendpackage);
	} else {
    return "Unknown argument $type, choose one of " . join(" ", @sets);
  }
  return undef;
}
#####################################
sub NetzerI2C_Get($@) {							#
  my ($hash, @a) = @_;
  my $nargs = int(@a);
  my $name = $hash->{NAME};
  my @gets = ('read');
  unless ( exists($a[1]) && $a[1] ne "?" && grep {/^$a[1]$/} @gets ) { 
		return "Unknown argument $a[1], choose one of " . join(" ", @gets);
  }
  
  my ($msg, $err);
  return "No $a[1] for dummies" if(IsDummy($name));
  
  if ($a[1] eq "read") {
    return "use: \"get $name $a[1] <i2cAddress> [<RegisterAddress> [<Number od bytes to get>]]\"" if(@a < 3);  
    return "$name I2C address must be 2-digit hexvalues"    unless ($a[2] =~ /^(0x|)(|[0-7])[0-9A-F]$/xi);  # && hex($a[2]) % 2 == 0);
		return "$name register address must be a hexvalues" if (defined($a[3]) && $a[3] !~ /^(0x|)[0-9A-F]{1,2}$/xi);
		return "$name number of bytes must be decimal value"      if (defined($a[4]) && $a[4] !~ /^[0-9]{1,2}$/ && $a[4] < 65);
	
		my $hmsg = chr( (hex( $a[2] ) << 1) + 1 );								#I2C Adresse (read) in Zeichen wandeln
    if ( $a[3] ) {  																					#Registeradresse in Hexwerte wandeln
	    $hmsg .= chr( hex("5C")  ) if ( (hex($a[3])) == "00"); 	#wenn 0x00 gesendet mit 0x5C escapen
	    $hmsg .= chr( hex($a[3]) );
    }	
		if ( $a[4] ) {  
			for(my $n=1; $n<$a[4]; $n++) {						#Fuer jedes zu lesende Byte ein Byte rausschicken
				$hmsg .= chr( hex("01") );
			}
    }
    $hmsg .= chr( hex("00") );  							#Endezeichen anhaengen
    #nur zum testen mit socat#######################
    $hmsg =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg if ( AttrVal($hash->{NAME}, 'socat', 0) == 1 );
		################################################
		DevIo_SimpleWrite($hash, $hmsg, undef);
	
		my $buf = undef;
		my $timeout = 10;
		return $hash->{NAME} . " disconnected" unless $hash->{FD};
		for(;;) {												#Werte direkt lesen (mit Timeout)
      my $rin = "";
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $timeout);
      last if($nfound <= 0);
      my $r = DevIo_DoSimpleRead($hash);
      if(!defined($r) || $r ne "") {
				$buf = $r;
				last;
			}
    }
		if ($buf) {
			if ( AttrVal($hash->{NAME}, 'socat', 0) == 0 ) {
				$buf =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg;					#empfangene Zeichen in Hexwerte wandeln (fuer Socat auskommentieren)
      } else {
				chomp($buf);		#weg nach testen mit Socat
				$buf = uc($buf);	#weg nach testen mit Socat
			}
			my @abuf = split (/ /,$buf);
      for (my $i = 1; $i < (defined($a[3])? 3 : 2 ) ; $i++) {	#pruefen, ob jedes gesendete Byte ein positives Ack bekommen hat
				return "error, no Ack received for $a[$1]; received: $buf" if $abuf[0] ne "FF";
				shift(@abuf);
			}
			my $rmsg = undef;
			my $nrec = int(@abuf);
			for (my $j = 0; $j < $nrec ; $j++) {							#escape Zeichen fuer 0x00 entfernen
				$rmsg .= " " if (defined($rmsg));
				$rmsg .= $abuf[$j] unless( $abuf[$j] eq "5C" && defined($abuf[$j + 1]) && $abuf[$j + 1] eq "00" );
			}
			$buf = $rmsg;
		} else {
			$buf = "no Message received";
		}
    return $buf;
  } 
  #$hash->{READINGS}{$a[1]}{VAL} = $msg;
  #$hash->{READINGS}{$a[1]}{TIME} = TimeNow();
  #return "$a[0] $a[1] => $msg";
  return undef;
}
#####################################
sub NetzerI2C_DoInit($) { 					#ausfuehren beim start von devio evtl. loeschen oder reinit von clienten reinbauen
  my $hash = shift;
  my $name = $hash->{NAME};
  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
  return undef;
}
#####################################
sub NetzerI2C_Write($$) { 					#wird vom Client aufgerufen
  my ($hash, $clientmsg) = @_;
  foreach my $av (keys %{$clientmsg}) { Log3 $hash, 5, "$hash->{NAME} vom Clienten: $av= " . $clientmsg->{$av}; }
  if ($clientmsg->{direction} && $clientmsg->{i2caddress}) {
    if(!$hash->{QQUEUE} || 0 == scalar(@{$hash->{QQUEUE}})) {
      $hash->{QQUEUE} = [ $clientmsg ];
      NetzerI2C_SendFromQueue($hash, $clientmsg);
    } else {
      push(@{$hash->{QQUEUE}}, $clientmsg);
    }
  }  
  return undef;
}
#####################################
sub NetzerI2C_SendFromQueue($$) {		#
  my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};
  	
  my (@msg,@adata) = ();
  
  @adata = split(/ /,$clientmsg->{data}) if defined($clientmsg->{data});
	
	if (defined($clientmsg->{reg}) && ($clientmsg->{direction} eq "i2cwrite" && int(@adata) > 1) 
	        || ($clientmsg->{nbyte} && $clientmsg->{nbyte} > 1)) {		#klaeren, ob Register sequentiell geschrieben werden
		$clientmsg->{smsg} = ( $clientmsg->{direction} eq "i2cwrite" ? int(@adata) : $clientmsg->{nbyte} ) if !$clientmsg->{smsg};
		$clientmsg->{smsgcnt}++;
		push(@msg, $clientmsg->{reg} + $clientmsg->{smsgcnt} - 1 ) if ($clientmsg->{reg});		#Registeradresse hochzaehlen wenn vorhanden
		push(@msg, $adata[$clientmsg->{smsgcnt} - 1]) if ($clientmsg->{direction} eq "i2cwrite"); 
		Log3 $hash, 5, $clientmsg->{direction} . " Nachricht zerteilen: ". ( defined($clientmsg->{data}) ? $clientmsg->{data} : "leer" ) ." Teil Nr: " .$clientmsg->{smsgcnt} ." = ". $clientmsg->{smsg};
	} else {																																												#oder alle auf einmal
		Log3 $hash, 5, $clientmsg->{direction} . " Nachricht nicht zerteilen: ". ( defined($clientmsg->{data}) ? $clientmsg->{data} : "leer" ) ." Nbytes: " . int(@adata);
		push(@msg, $clientmsg->{reg} ) if defined($clientmsg->{reg});
		push(@msg, @adata);
	}
	
  my $hmsg = chr(  ( $clientmsg->{i2caddress} << 1 ) + (($clientmsg->{direction} eq "i2cread")? 1 : 0) );
  if ( int(@msg) > 0 ) {  
		foreach (@msg) {																			#Daten in Zeichen wandeln
			$hmsg .= chr( hex("5C") ) if ( $_ == hex("00") ); 	#wenn 0x00 gesendet mit 0x5C escapen
			$hmsg .= chr( $_ );
		}
  }
  $hmsg .= chr( hex("00") );  														#Endezeichen anhaengen
	
#nur zum Testen########
  $clientmsg->{bytecount} = int(@msg) + 1;								#Anzahl Nutzdaten + Adressbyte
  (my $smsg = $hmsg) =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg;
  Log3 $hash, 5, "$name SendFromQueue: $clientmsg->{direction}, String: $smsg, Hex: $hmsg, NBytes: $clientmsg->{bytecount}";
#######################
  #DevIo_SimpleWrite($hash, $hmsg, undef);
  DevIo_SimpleWrite($hash, AttrVal($hash->{NAME}, 'socat', 0) == 1 ? $smsg : $hmsg, undef); #fuer Socat zum testen
  NetzerI2C_InternalTimer("RecvTimeout", gettimeofday() + AttrVal($hash->{NAME}, 'timeout', 10), "NetzerI2C_TransceiveTimeout", $hash, 0);
}
#####################################
sub NetzerI2C_HandleQueue($) {			#
  my $hash = shift;
  my $arr = $hash->{QQUEUE};
  if(defined($arr) && @{$arr} > 0) {
		shift(@{$arr}) unless $arr->[0]->{smsg} && $arr->[0]->{smsg} > $arr->[0]->{smsgcnt};  #nur auf naechste Botschaft wechseln wenn alle Byte gesendet wurden
		if(@{$arr} == 0) {
			delete($hash->{QQUEUE});
			return;
		}
		my $clientmsg = $arr->[0];
		if(defined($clientmsg) && $clientmsg eq "") {
			NetzerI2C_HandleQueue($hash) if defined($hash);
		} else {
			NetzerI2C_SendFromQueue($hash, $clientmsg);
		}
  }
}
#####################################
sub NetzerI2C_TransceiveTimeout($) {#
  #my $hash = shift;
  #Hash finden wenn myinternaltimer genutzt wird#
  my ($myHash) = @_;														#
  my $hash = $myHash->{HASH};										#
  ###############################################
  my $name = $hash->{NAME};
  Log3 $hash, 1, "$name: Timeout I2C response";
	my $arr = $hash->{QQUEUE};
	delete $arr->[0]->{smsg} if $arr->[0]->{smsg}; 
  NetzerI2C_HandleQueue($hash);
}
#####################################
sub NetzerI2C_Read($) {							# called from the global loop, when the select for hash->{FD} reports data
  my ($hash) = @_;
  my $buf = DevIo_SimpleRead($hash);
	return undef if(!defined($buf));					#Aendern????
	#Log3 $hash, 1, "$hash->{NAME} vom I2C empfangen 1: $buf";
	#hier noch abfangen, wenn $buf leer ist
  if ( AttrVal($hash->{NAME}, 'socat', 0) == 1 ) { 			#weg nach testen mit Socat
		chomp($buf);
		#$buf = hex($buf);
	} else {
		$buf =~ s/(.|\n)/sprintf("%.2X ",ord($1))/eg				#empfangene Zeichen in Hexwerte wandeln -> in wandlung nach Zahl aendern
	}
	Log3 $hash, 5, "$hash->{NAME} vom I2C empfangen: $buf";
  my @abuf = split (/ /,$buf);
	foreach (@abuf) {																			#weg wenn Zeichen direkt gewandelt werden
		$_ = hex;
		#Log3 $hash, 1, "$hash->{NAME} vom I2C: $_";
	}
  my $name = $hash->{NAME};
  #Log3 $hash, 1, "$hash->{NAME} vom I2C empfangen: $buf";

  my $arr = $hash->{QQUEUE};
  if(defined($arr) && @{$arr} > 0) {
    my $clientmsg = $arr->[0];
		NetzerI2C_RemoveInternalTimer("RecvTimeout", $hash);
		my $status = "Ok";
    for (my $i = 0; $i < $clientmsg->{bytecount} ; $i++) {	#pruefen, ob jedes gesendete Byte ein positives Ack (FF) bekommen hat
			$status = "error" . ($arr->[0]->{smsg} ? "@ reg: ". sprintf("%.2X ",($clientmsg->{reg} + $clientmsg->{smsgcnt} - 1)) :"") if !defined($abuf[0]) || $abuf[0] != 255;
			shift(@abuf);
		}
		my $rmsg = undef;
		my $nrec = int(@abuf);
		for (my $i = 0; $i < $nrec ; $i++) {					#escape Zeichen (0x5C) fuer 0x00 entfernen
			$rmsg .= " " if (defined($rmsg));
			#$rmsg .= $abuf[$i] unless( $abuf[$i] eq "5C" && defined($abuf[$i + 1]) && $abuf[$i + 1] eq "00" );
			$rmsg .= $abuf[$i] unless( $abuf[$i] == 92 && defined($abuf[$i + 1]) && $abuf[$i + 1] == 0 );
		}
		
		if ( $arr->[0]->{smsg} && defined($rmsg) ) {									#wenn Nachricht Teil einer Nachrichtenfolge, dann Daten anhaengen
			$clientmsg->{received} .= ( defined($arr->[0]->{smsg}) && $arr->[0]->{smsg} == 1 ? "" : " ") . $rmsg;
		} else {
			$clientmsg->{received} = $rmsg;
		}
		unless ( $arr->[0]->{smsg} && $arr->[0]->{smsg} > $arr->[0]->{smsgcnt} && $status eq "Ok" ) {	#erst senden, wenn Transfer abgeschlossen oder bei Fehler
		delete $arr->[0]->{smsg} if $arr->[0]->{smsg} && $status ne "Ok";				#aktuellen Einzeltransfer durch loeschen der Botschaftszahl abbrechen
			#$clientmsg->{received} = $rmsg if defined($rmsg);
			$clientmsg->{$name . "_" . "RAWMSG"} = $buf;
			$clientmsg->{$name . "_" . "SENDSTAT"} = $status;
			if ($clientmsg->{direct}) {																							#Vorgang wurde von diesem Modul ausgeloest
				$hash->{direct_send}    = $clientmsg->{data};
				$hash->{direct_answer}  = $clientmsg->{$name . "_" . "RAWMSG"};
				$hash->{direct_I2Caddr} = $clientmsg->{i2caddress};
				$hash->{direct_SENDSTAT} = $status; 
			}
			########################################### neue Variante zum senden an client
			foreach my $d ( sort keys %main::defs ) {				#zur Botschaft passenden Clienten ermitteln geht auf Client: I2CRecFn
				#Log3 $hash, 1, "Clients suchen d: $d". ($main::defs{$d}{IODev}? ", IODev: $main::defs{$d}{IODev}":"") . ($main::defs{$d}{I2C_Address} ? ", I2C: $main::defs{$d}{I2C_Address}":"") . ($clientmsg->{i2caddress} ? " CI2C: $clientmsg->{i2caddress}" : "");
				if ( defined( $main::defs{$d} )
						&& defined( $main::defs{$d}{IODev} )    && $main::defs{$d}{IODev} == $hash
						&& defined( $main::defs{$d}{I2C_Address} )  && defined( $clientmsg->{i2caddress} )
						&& $main::defs{$d}{I2C_Address} eq $clientmsg->{i2caddress} ) {
					my $chash = $main::defs{$d};
					Log3 $hash, 5, "Client gefunden d: $d". ($main::defs{$d}{IODev}? ", IODev: $main::defs{$d}{IODev}":"") . ($main::defs{$d}{I2C_Address} ? ", I2C: $main::defs{$d}{I2C_Address}":"") . ($clientmsg->{i2caddress} ? " CI2C: $clientmsg->{i2caddress}" : "");
					CallFn($d, "I2CRecFn", $chash, $clientmsg);
				}
			}
			######################################## alte Variante ueber Dispatch ######################
			#	  my $dir = $clientmsg->{direction};																										#
			#	  my $sid = $clientmsg->{id};																														#
			#      if($dir eq "i2cread" || $dir eq "i2cwrite") {																			#
			#		my $dev = $clientmsg->{i2caddress};																										#
			#		my %addvals = (RAWMSG => $buf, SENDSTAT => $status);																	#
			#		$rmsg = ( defined($rmsg) ? ($sid . " " . $dev . " " . $rmsg) : ($sid . " " . $dev) );	#
			#       Log 1, "wird an Client geschickt: $rmsg";																					#
			#       Dispatch($hash, $rmsg, \%addvals);																								#
			#	   }																																										#
			###########################################################################################
			undef $clientmsg; #Hash loeschen nachdem Daten verteilt wurden
		}
		NetzerI2C_HandleQueue($hash);	
  } else {
		Log3 $hash, 1, "$name: unknown data received: $buf";
  }
}
#####################################
sub NetzerI2C_Ready($) {############# kann geloescht werden?
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}
#####################################
sub NetzerI2C_Attr(@) {							#
  my ($cmd,$name,$aName,$aVal) = @_;
  my $msg = undef;
  if($aName eq "timeout") {
    if ( defined($aVal) ) {
    unless ( looks_like_number($aVal) && $aVal >= 0.1 && $aVal <= 20 ) {
	  $msg = "$name: Wrong $aName defined. Value must be a number between 0.1 and 20";
    }    
   } 
  } 
  return $msg;
}
##################################### 
sub NetzerI2C_InternalTimer($$$$$) {#(von Dietmar63)
   my ($modifier, $tim, $callback, $hash, $waitIfInitNotDone) = @_;

   my $mHash;
   if ($modifier eq "") {
      $mHash = $hash;
   } else {
      my $timerName = "$hash->{NAME}_$modifier";
      if (exists  ($hash->{TIMER}{$timerName})) {
          $mHash = $hash->{TIMER}{$timerName};
      } else {
          $mHash = { HASH=>$hash, NAME=>"$hash->{NAME}_$modifier", MODIFIER=>$modifier};
          $hash->{TIMER}{$timerName} = $mHash;
      }
   }
   InternalTimer($tim, $callback, $mHash, $waitIfInitNotDone);
}
#####################################
sub NetzerI2C_RemoveInternalTimer($$) {
   my ($modifier, $hash) = @_;

   my $timerName = "$hash->{NAME}_$modifier";
   if ($modifier eq "") {
      RemoveInternalTimer($hash);
   } else {
      my $myHash = $hash->{TIMER}{$timerName};
      if (defined($myHash)) {
         delete $hash->{TIMER}{$timerName};
         RemoveInternalTimer($myHash);
      }
   }
}

1;

=pod
=begin html

<a name="NetzerI2C"></a>
<h3>NetzerI2C</h3>
<ul>
	<a name="NetzerI2C"></a>
		Provides access to <a href="http://www.mobacon.de/wiki/doku.php/en/netzer/index">Netzer's</a> I2C interfaces for some logical modules and also directly.<br><br>
		<b>preliminary:</b><br>
		Serial Server of Netzer must be <a href="http://www.mobacon.de/wiki/doku.php/en/netzer/serialserveraktiviert"> activated and configured for I2C	</a>.<br>
	<a name="NetzerI2CDefine"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; NetzerI2C &lt;Device-Address:Port&gt;</code><br>
		where <code>&lt;Device-Address:Port&gt;</code> Device Address/ IP-Address and Serial Server TCP Port of the Netzer<br><br>
	</ul>

	<a name="NetzerI2CSet"></a>
	<b>Set</b>
	<ul>
		<li>
			Write one byte (or more bytes sequentially) directly to an I2C device (for devices that have only one register to write):<br>
			<code>set &lt;name&gt; writeByte    &lt;I2C Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Write one byte (or more bytes sequentially) to the specified register of an I2C device:<br>
			<code>set &lt;name&gt; writeByteReg &lt;I2C Address&gt; &lt;Register Address&gt;  &lt;value&gt;</code><br><br>
		</li>
		<li>
			Write n-bytes to an register range, beginning at the specified register:<br>	
			<code>set &lt;name&gt; writeBlock   &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt;</code><br><br>
		</li>
		Examples:
		<ul>
			Write 0xAA to device with I2C address 0x60<br>
			<code>set test1 writeByte 60 AA</code><br>
			Write 0xAA to register 0x01 of device with I2C address 0x6E<br>
			<code>set test1 writeByteReg 6E 01 AA</code><br>
			Write 0xAA to register 0x01 of device with I2C address 0x6E, after it write 0x55 to register 0x02<br>
			<code>set test1 writeByteReg 6E 01 AA 55</code><br>
			Write 0xA4 to register 0x03, 0x00 to register 0x04 and 0xDA to register 0x05 of device with I2C address 0x60 as block operation<br>
			<code>set test1 writeBlock 60 03 A4 00 DA</code><br>
		</ul><br>
	</ul>

	<a name="NetzerI2CGet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt; read &lt;I2C Address&gt; [&lt;Register Address&gt; [&lt;number of registers&gt;]] </code>
		<br>
		gets value of I2C device's registers<br><br>
		Examples:
		<ul>
			Reads byte from device with I2C address 0x60<br>
			<code>get test1 writeByte 60</code><br>
			Reads register 0x01 of device with I2C address 0x6E.<br>
			<code>get test1 read 6E 01 AA 55</code><br>
			Reads register 0x03 to 0x06 of device with I2C address 0x60.<br>
			<code>get test1 read 60 03 4</code><br>
		</ul><br>
	</ul><br>

	<a name="NetzerI2CAttr"></a>
	<b>Attributes</b>
	<ul>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html

=begin html_DE

<a name="NetzerI2C"></a>
<h3>NetzerI2C</h3>
<ul>
	<a name="NetzerI2C"></a>
		Erm&ouml;glicht den Zugriff auf die I2C Schnittstelle des <a href="http://www.mobacon.de/wiki/doku.php/de/netzer/index">Netzer</a>.<br> &uuml;ber logische Module. Register von I2C IC's k&ouml;nnen auch direkt gelesen und geschrieben werden.<br><br>
		<b>Vorbereitung:</b><br>
		Bevor dieses Modul verwendet werden kann muss der Serielle Server des Netzers <a href="http://www.mobacon.de/wiki/doku.php/de/netzer/serialserveraktiviert"> und auf I2C gestellt</a> werden.
	<a name="NetzerI2CDefine"></a><br><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; NetzerI2C &lt;Device-Address:Port&gt;</code><br>
		<code>&lt;Device-Address:Port&gt;</code> ist  die Adresse/IP-Adresse und Serial Server TCP-Port des Netzer<br><br>
	</ul>

	<a name="NetzerI2CSet"></a>
	<b>Set</b>
	<ul>
		<li>
			Schreibe ein Byte (oder auch mehrere nacheinander) direkt auf ein I2C device (manche I2C Module sind so einfach, das es nicht einmal mehrere Register gibt):<br>
			<code>set &lt;name&gt; writeByte    &lt;I2C Address&gt; &lt;value&gt;</code><br><br>
		</li>
		<li>
			Schreibe ein Byte (oder auch mehrere nacheinander) direkt auf ein Register des adressierten I2C device:<br>
			<code>set &lt;name&gt; writeByteReg &lt;I2C Address&gt; &lt;Register Address&gt;  &lt;value&gt;</code><br><br>
		</li>
		<li>
			Schreibe n-bytes auf einen Registerbereich, beginnend mit dem angegebenen Register:<br>	
			<code>set &lt;name&gt; writeBlock   &lt;I2C Address&gt; &lt;Register Address&gt; &lt;value&gt;</code><br><br>
		</li>
		Beispiele:
		<ul>
			Schreibe 0xAA zu Modul mit I2C Addresse 0x60<br>
			<code>set test1 writeByte 60 AA</code><br>
			Schreibe 0xAA zu Register 0x01 des Moduls mit der I2C Adresse 0x6E<br>
			<code>set test1 writeByteReg 6E 01 AA</code><br>
			Schreibe 0xAA zu Register 0x01 des Moduls mit der I2C Adresse 0x6E, schreibe danach 0x55 zu Register 0x01<br>
			<code>set test1 writeByteReg 6E 01 AA 55</code><br>
			Schreibe 0xA4 zu Register 0x03, 0x00 zu Register 0x04 und 0xDA zu Register 0x05 des Moduls mit der I2C Adresse 0x60 als Block<br>
			<code>set test1 writeBlock 60 03 A4 00 DA</code><br>

		</ul><br>
	</ul>

	<a name="NetzerI2CGet"></a>
	<b>Get</b>
	<ul>
		<code>get &lt;name&gt; read &lt;I2C Address&gt; [&lt;Register Address&gt; [&lt;number of registers&gt;]] </code>
		<br>
		Auslesen der Registerinhalte des I2C Moduls<br><br>
		Examples:
		<ul>
			Lese Byte vom Modul mit der I2C Adresse 0x60<br>
			<code>get test1 writeByte 60</code><br>
			Lese den Inhalt des Registers 0x01 vom Modul mit der I2C Adresse 0x6E.<br>
			<code>get test1 read 6E 01 AA 55</code><br>
			Lese den Inhalt des Registerbereichs 0x03 bis 0x06 vom Modul mit der I2C Adresse 0x60.<br>
			<code>get test1 read 60 03 4</code><br>
		</ul><br>
	</ul><br>

	<a name="NetzerI2CAttr"></a>
	<b>Attribute</b>
	<ul>
		<li><a href="#ignore">ignore</a></li>
		<li><a href="#do_not_notify">do_not_notify</a></li>
		<li><a href="#showtime">showtime</a></li>
	</ul>
	<br>
</ul>

=end html_DE
################################################################################################
# $Id: 77_SMAEM.pm 19460 2019-05-24 20:19:41Z DS_Starter $
#
#  Copyright notice
#
#  (c) 2016-2019 Copyright: Volker Kettenbach
#  e-mail: volker at kettenbach minus it dot de
#
#  Credits: 
#  - DS_Starter (Heiko) for persistent readings
#    and various improvements
#
#  Description:
#  This is an FHEM-Module for the SMA Energy Meter, 
#  a bidirectional energy meter/counter used in photovoltaics
#
#  Requirements:
#  This module requires:
#  - Perl Module: IO::Socket::Multicast
#  On a Debian (based) system, these requirements can be fullfilled by:
#  - apt-get install install libio-socket-multicast-perl
#
#  Origin:
#  https://gitlab.com/volkerkettenbach/FHEM-SMA-Speedwire
#
################################################################################################# 

package main;

use strict;
use warnings;
use bignum;
use IO::Socket::Multicast;
use Blocking;
eval "use FHEM::Meta;1" or my $modMetaAbsent = 1;

# Versions History by DS_Starter 
our %SMAEM_vNotesIntern = (
  "4.0.0" => "16.12.2019  change module to OBIS metric resolution, change Readings Lx_THD to Lx_Strom, FirmwareVersion to SoftwareVersion ".
                          "new attribute \"noCoprocess\", many internal code changes ",
  "3.5.0" => "14.12.2019  support of SMA Homemanager 2.0 >= 2.03.4.R, attribute \"serialNumber\", ".
                          "delete hash keys by set reset, initial OBIS items resolution ",
  "3.4.0" => "22.05.2019  support of Installer.pm/Meta.pm added, new version maintenance, commandref revised ",
  "3.3.0" => "21.05.2019  set reset to delete and reinitialize cacheFile, support of DelayedShutdownFn ",
  "3.2.0" => "26.07.2018  log entry enhanced if diff overflow ",
  "3.1.0" => "12.02.2018  extend error handling in define ",
  "3.0.1" => "26.11.2017  use abort cause of BlockingCall ",
  "3.0.0" => "29.09.2017  make SMAEM ready for multimeter usage ",
  "2.9.1" => "29.05.2017  DbLog_splitFn added, some function names adapted ",
  "2.9.0" => "25.05.2017  own SMAEM_setCacheValue, SMAEM_getCacheValue, new internal VERSION ",
  "2.8.2" => "03.12.2016  Prefix SMAEMserialnumber for Reading \"state\" removed, commandref adapted ",
  "2.8.1" => "02.12.2016  encode / decode \$data ",
  "2.8.0" => "02.12.2016  plausibility check of measured differences, attr diffAccept, timeout ".
                          "validation checks, improvement of failure prevention ",
  "2.7.0" => "01.12.2016  logging of discarded cycles ",
  "2.6.0" => "01.12.2016  some improvements, better logging possibility ",
  "2.5.0" => "30.11.2016  some improvements ",
  "2.4.0" => "30.11.2016  some improvements, attributes disable, timeout for BlockingCall added ",
  "2.3.0" => "30.11.2016  SMAEM_getsum, SMAEM_setsum changed ",
  "2.2.0" => "29.11.2016  check error while writing values to file -> set state with error ", 
  "2.1.0" => "29.11.2016  move \$hash->{GRIDin_SUM}, \$hash->{GRIDOUT_SUM} calc to smaread_ParseDone, ".
                          "some little improvements to logging process",
  "2.0.0" => "28.11.2016  switch to nonblocking "
);

# Beschreibung OBIS Kennzahlen
our %SMAEM_obisitem = (
  "1:1.4.0"   => "SUM Wirkleistung Bezug",
  "1:1.8.0"   => "SUM Wirkleistung Bezug Zaehler",
  "1:2.4.0"   => "SUM Wirkleistung Einspeisung",
  "1:2.8.0"   => "SUM Wirkleistung Einspeisung Zaehler",
  "1:3.4.0"   => "SUM Blindleistung Bezug",
  "1:3.8.0"   => "SUM Blindleistung Bezug Zaehler",
  "1:4.4.0"   => "SUM Blindleistung Einspeisung",
  "1:4.8.0"   => "SUM Blindleistung Einspeisung Zaehler",
  "1:9.4.0"   => "SUM Scheinleistung Bezug",
  "1:9.8.0"   => "SUM Scheinleistung Bezug Zaehler",
  "1:10.4.0"  => "SUM Scheinleistung Einspeisung",
  "1:10.8.0"  => "SUM Scheinleistung Einspeisung Zaehler",
  "1:13.4.0"  => "SUM Leistungsfaktor",
  "1:14.4.0"  => "Netzfrequenz",
  "1:21.4.0"  => "L1 Wirkleistung Bezug",
  "1:21.8.0"  => "L1 Wirkleistung Bezug Zaehler",
  "1:22.4.0"  => "L1 Wirkleistung Einspeisung",
  "1:22.8.0"  => "L1 Wirkleistung Einspeisung Zaehler",
  "1:23.4.0"  => "L1 Blindleistung Bezug",
  "1:23.8.0"  => "L1 Blindleistung Bezug Zaehler",
  "1:24.4.0"  => "L1 Blindleistung Einspeisung",
  "1:24.8.0"  => "L1 Blindleistung Einspeisung Zaehler",
  "1:29.4.0"  => "L1 Scheinleistung Bezug",
  "1:29.8.0"  => "L1 Scheinleistung Bezug Zaehler",
  "1:30.4.0"  => "L1 Scheinleistung Einspeisung",
  "1:30.8.0"  => "L1 Scheinleistung Einspeisung Zaehler",
  "1:31.4.0"  => "L1 Strom",
  "1:32.4.0"  => "L1 Spannung",
  "1:33.4.0"  => "L1 Leistungsfaktor",
  "1:41.4.0"  => "L2 Wirkleistung Bezug",
  "1:41.8.0"  => "L2 Wirkleistung Bezug Zaehler",
  "1:42.4.0"  => "L2 Wirkleistung Einspeisung",
  "1:42.8.0"  => "L2 Wirkleistung Einspeisung Zaehler",
  "1:43.4.0"  => "L2 Blindleistung Bezug",
  "1:43.8.0"  => "L2 Blindleistung Bezug Zaehler",
  "1:44.4.0"  => "L2 Blindleistung Einspeisung",
  "1:44.8.0"  => "L2 Blindleistung Einspeisung Zaehler",
  "1:49.4.0"  => "L2 Scheinleistung Bezug",
  "1:49.8.0"  => "L2 Scheinleistung Bezug Zaehler",
  "1:50.4.0"  => "L2 Scheinleistung Einspeisung",
  "1:50.8.0"  => "L2 Scheinleistung Einspeisung Zaehler",
  "1:51.4.0"  => "L2 Strom",
  "1:52.4.0"  => "L2 Spannung",
  "1:53.4.0"  => "L2 Leistungsfaktor",
  "1:61.4.0"  => "L3 Wirkleistung Bezug",
  "1:61.8.0"  => "L3 Wirkleistung Bezug Zaehler",
  "1:62.4.0"  => "L3 Wirkleistung Einspeisung",
  "1:62.8.0"  => "L3 Wirkleistung Einspeisung Zaehler",
  "1:63.4.0"  => "L3 Blindleistung Bezug",
  "1:63.8.0"  => "L3 Blindleistung Bezug Zaehler",
  "1:64.4.0"  => "L3 Blindleistung Einspeisung",
  "1:64.8.0"  => "L3 Blindleistung Einspeisung Zaehler",
  "1:69.4.0"  => "L3 Scheinleistung Bezug",
  "1:69.8.0"  => "L3 Scheinleistung Bezug Zaehler",
  "1:70.4.0"  => "L3 Scheinleistung Einspeisung",
  "1:70.8.0"  => "L3 Scheinleistung Einspeisung Zaehler",
  "1:71.4.0"  => "L3 Strom",
  "1:72.4.0"  => "L3 Spannung",
  "1:73.4.0"  => "L3 Leistungsfaktor",
  "144:0.0.0" => "Software Version",
);

###############################################################
#                  SMAEM Initialize
###############################################################
sub SMAEM_Initialize ($) {
  my ($hash) = @_;
  
  $hash->{ReadFn}            = "SMAEM_Read";
  $hash->{SetFn}             = "SMAEM_Set";
  $hash->{DefFn}             = "SMAEM_Define";
  $hash->{UndefFn}           = "SMAEM_Undef";
  $hash->{DeleteFn}          = "SMAEM_Delete";
  $hash->{DbLog_splitFn}     = "SMAEM_DbLogSplit";
  $hash->{DelayedShutdownFn} = "SMAEM_DelayedShutdown";
  $hash->{AttrFn}            = "SMAEM_Attr";
  $hash->{AttrList}          = "interval ".
                               "disable:1,0 ".
						       "diffAccept ".
                               "disableSernoInReading:1,0 ".
                               "feedinPrice ".
                               "noCoprocess:1,0 ".
                               "powerCost ".
                               "serialNumber ".
                               "timeout ".						
                               "$readingFnAttributes";
                               
  eval { FHEM::Meta::InitMod( __FILE__, $hash ) };           # für Meta.pm (https://forum.fhem.de/index.php/topic,97589.0.html)
  
return; 
}

###############################################################
#                  SMAEM Define
###############################################################
sub SMAEM_Define ($$) {
  my ($hash, $def) = @_;
  my $name= $hash->{NAME};
  my ($success, $gridin_sum, $gridout_sum);
  my $socket;
  
  $hash->{INTERVAL}              = 60;
  $hash->{HELPER}{FAULTEDCYCLES} = 0;
  $hash->{HELPER}{STARTTIME}     = time();
    
  Log3 $hash, 3, "SMAEM $name - Opening multicast socket...";
  eval {
  $socket = IO::Socket::Multicast->new(
           Proto     => 'udp',
           LocalPort => '9522',
           ReuseAddr => '1',
           ReusePort => defined(&ReusePort) ? 1 : 0,
  ); };
  if($@) {
      Log3 $hash, 1, "SMAEM $name - Can't bind: $@";
      return;      
  }
  
  Log3 $hash, 3, "SMAEM $name - Multicast socket opened";
  
  $socket->mcast_add('239.12.255.254');

  $hash->{TCPDev} = $socket;
  $hash->{FD}     = $socket->fileno();
  delete($readyfnlist{"$name"});
  $selectlist{"$name"} = $hash;
  
  $hash->{HELPER}{MODMETAABSENT} = 1 if($modMetaAbsent);                         # Modul Meta.pm nicht vorhanden
  
  # Versionsinformationen setzen
  SMAEM_setVersionInfo($hash);
  
  # gespeicherte Serialnummern lesen und extrahieren
  my $retcode = SMAEM_getserials($hash); 
  $hash->{HELPER}{READFILEERROR} = $retcode if($retcode);
  
  
  if($hash->{HELPER}{ALLSERIALS}) {
      my @allserials = split(/_/,$hash->{HELPER}{ALLSERIALS});
	  foreach(@allserials) {
	      my $smaserial = $_;
	      # gespeicherte Energiezählerwerte von File einlesen
          my $retcode = SMAEM_getsum($hash,$smaserial);
          $hash->{HELPER}{READFILEERROR} = $retcode if($retcode);
	  }
  }
  
return undef;
}

###############################################################
#                  SMAEM Undefine
###############################################################
sub SMAEM_Undef ($$) {
  my ($hash, $arg) = @_;
  my $name= $hash->{NAME};
  my $socket= $hash->{TCPDev};
  
  BlockingKill($hash->{HELPER}{RUNNING_PID}) if(defined($hash->{HELPER}{RUNNING_PID}));
  Log3 $hash, 3, "SMAEM $name - Closing multicast socket...";
  $socket->mcast_drop('239.12.255.254');
  
  my $ret = close($hash->{TCPDev});
  Log3 $hash, 4, "SMAEM $name - Close-ret: $ret";
  delete($hash->{TCPDev});
  delete($selectlist{"$name"});
  delete($hash->{FD});
 
return;
}

###############################################################
#                  SMAEM Delete
###############################################################
sub SMAEM_Delete ($$) {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    
    # gespeicherte Energiezählerwerte löschen
    setKeyValue($index, undef);
    
return undef;
}

#######################################################################################################
# Mit der X_DelayedShutdown Funktion kann eine Definition das Stoppen von FHEM verzögern um asynchron 
# hinter sich aufzuräumen.  
# Je nach Rückgabewert $delay_needed wird der Stopp von FHEM verzögert (0|1).
# Sobald alle nötigen Maßnahmen erledigt sind, muss der Abschluss mit CancelDelayedShutdown($name) an 
# FHEM zurückgemeldet werden. 
#######################################################################################################
sub SMAEM_DelayedShutdown ($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};
  
  if($hash->{HELPER}{RUNNING_PID}) {
      Log3($name, 2, "$name - Quit background process due to shutdown ...");
      return 1;
  }

return 0;
}

###############################################################
#                  SMAEM Set
###############################################################
sub SMAEM_Set ($@) {
  my ($hash, @a) = @_;
  return "\"set X\" needs at least an argument" if ( @a < 2 );
  my $name = $a[0];
  my $opt  = $a[1];
  
  my $setlist = "Unknown argument $opt, choose one of ".
                "reset:noArg "
                ;

  if ($opt eq "reset") {
      BlockingKill($hash->{HELPER}{RUNNING_PID}) if(defined($hash->{HELPER}{RUNNING_PID}));
      delete $hash->{HELPER}{ALLSERIALS};
	  foreach my $key (keys %{$hash}) {
		  delete $hash->{$key} if($key =~ /GRIDIN_SUM|GRIDOUT_SUM/);
      } 
      my $result = unlink $attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM"; 
      if ($result) {      
          $result = "Cachefile ".$attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM deleted. It will be initialized immediately.";  
      } else {
          $result = "Error while deleting Cachefile ".$attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM: $!";
      }
      Log3 ($name, 3, "SMAEM $name - $result");
      return $result;
  
  } else {
      return "$setlist";
  }  
  
return;
}

###############################################################
#                  SMAEM Attr
###############################################################
sub SMAEM_Attr ($$$$) {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $do;
  
  # $cmd can be "del" or "set"
  # $name is device name
  # aName and aVal are Attribute name and value
  
  if ($aName eq "interval") {
      if($cmd eq "set") {
          $hash->{INTERVAL} = $aVal;
      } else {
          $hash->{INTERVAL} = "60";
      }
  }
  
  if ($aName eq "disableSernoInReading") {
        delete $defs{$name}{READINGS};
        readingsSingleUpdate($hash, "state", "initialized", 1);
  }
  
  if ($aName eq "timeout" || $aName eq "diffAccept") {
      unless ($aVal =~ /^[0-9]+$/) { return " The Value of $aName is not valid. Use only figures 0-9 without decimal places !";}
  } 
  
  if ($aName eq "disable") {
      if($cmd eq "set") {
          $do = ($aVal) ? 1 : 0;
      }
      $do = 0 if($cmd eq "del");
      my $val   = ($do == 1 ?  "disabled" : "initialized");
  
      readingsSingleUpdate($hash, "state", $val, 1);
  }
  
return undef;
}

###############################################################
#                  SMAEM Read (Hauptschleife)
###############################################################
# called from the global loop, when the select for hash->{FD} reports data
sub SMAEM_Read ($) {
  my ($hash)  = @_;
  my $name    = $hash->{NAME};
  my $socket  = $hash->{TCPDev};
  my $timeout = AttrVal($name, "timeout", 60);
  my $refsn   = AttrVal($name, "serialNumber", "");
  my ($data,$model);
  
  return if(IsDisabled($name));
  
  $socket->recv($data, 656);
  my $dl = length($data);
  if($dl == 600) {                                                  # Each SMAEM packet is 600 bytes of packed payload
      $model = "EM / HM 2.0 < 2.03.4.R";
  } elsif($dl == 608) {                                             # Each packet of HM with FW >= 2.03.4.R is 608 bytes of packed payload
      $model = "HM 2.0 >= 2.03.4.R";
  } else {
      $model = "unknown";
      Log3 ($name, 3, "SMAEM $name - Buffer length ".$dl." is not usual. May be your meter has been updated with a new firmware.");
  }

  return if (time() <= $hash->{HELPER}{STARTTIME}+30);
  
  # decode serial number of dataset received
  # unpack big-endian to 2-digit hex (bin2hex)
  my $hex       = unpack('H*', $data);
  my $smaserial = hex(substr($hex,40,8));
  
  return if(!$smaserial);
  return if($refsn && $refsn ne $smaserial);                        # nur selektiv eine EM mit angegebener Serial lesen (default: alle)
  
  $hash->{MODEL} = $model;
  
  # alle Serialnummern in HELPER sammeln und ggf. speichern
  if(!defined($hash->{HELPER}{ALLSERIALS}) || $hash->{HELPER}{ALLSERIALS} !~ /$smaserial/) {
      my $sep = $hash->{HELPER}{ALLSERIALS}?"_":undef;
      if($sep) {
	      $hash->{HELPER}{ALLSERIALS} = $hash->{HELPER}{ALLSERIALS}.$sep.$smaserial;
	  } else {
	      $hash->{HELPER}{ALLSERIALS} = $smaserial;
	  }
      SMAEM_setserials($hash);
  }
  
  if ( !$hash->{HELPER}{'LASTUPDATE_'.$smaserial} || time() >= ($hash->{HELPER}{'LASTUPDATE_'.$smaserial}+$hash->{INTERVAL}) ) {
      Log3 ($name, 4, "SMAEM $name - ###############################################################");
      Log3 ($name, 4, "SMAEM $name - ### Begin of new SMA Energymeter $smaserial get data cycle ###");
	  Log3 ($name, 4, "SMAEM $name - ###############################################################");
	  Log3 ($name, 4, "SMAEM $name - discarded cycles since module start: $hash->{HELPER}{FAULTEDCYCLES}");
      
	  if($hash->{HELPER}{RUNNING_PID}) {
          Log3 ($name, 3, "SMAEM $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} has been killed to start a new BlockingCall");
	      BlockingKill($hash->{HELPER}{RUNNING_PID});
	      delete($hash->{HELPER}{RUNNING_PID});
      }

	  # update time
      SMAEM_setlastupdate($hash,$smaserial);
	  
	  my $dataenc = encode_base64($data,"");
      
      if(AttrVal($name, "noCoprocess", 0)) {
          SMAEM_DoParse ("$name|$dataenc|$smaserial|$dl");
      } else {
	      $hash->{HELPER}{RUNNING_PID} = BlockingCall("SMAEM_DoParse", "$name|$dataenc|$smaserial|$dl", "SMAEM_ParseDone", $timeout, "SMAEM_ParseAborted", $hash); 
          $hash->{HELPER}{RUNNING_PID}{loglevel} = 5 if($hash->{HELPER}{RUNNING_PID});          # Forum #77057
          Log3 ($name, 4, "SMAEM $name - Blocking process with PID: $hash->{HELPER}{RUNNING_PID}{pid} started");
      }
  
  } else {
	  Log3 $hash, 5, "SMAEM $name - received ".$dl." bytes but interval $hash->{INTERVAL}s isn't expired.";
  }
  
return undef;
}

###############################################################
#          non-blocking Inverter Datenabruf
###############################################################
sub SMAEM_DoParse ($) {
    my ($string) = @_;
    my ($name,$dataenc,$smaserial,$dl) = split("\\|", $string);
    my $hash       = $defs{$name};
    my $data       = decode_base64($dataenc);
    my $discycles  = $hash->{HELPER}{FAULTEDCYCLES};
    my $diffaccept = AttrVal($name, "diffAccept", 10);
    my ($error,@row_array,@array);
 
    my $gridinsum  = $hash->{'GRIDIN_SUM_'.$smaserial} ?sprintf("%.4f",$hash->{'GRIDIN_SUM_'.$smaserial}):'';    
    my $gridoutsum = $hash->{'GRIDOUT_SUM_'.$smaserial}?sprintf("%.4f",$hash->{'GRIDOUT_SUM_'.$smaserial}):'';
 
    # check if cacheSMAEM-file has been opened at module start and try again if not
    if($hash->{HELPER}{READFILEERROR}) {
        my $retcode = SMAEM_getsum($hash,$smaserial);
        if ($retcode) {
            $error = encode_base64($retcode,"");
            $discycles++;
            return "$name|''|''|''|$error|$discycles|''"; 
        } else {
            delete($hash->{HELPER}{READFILEERROR})
        }
    }
 
    # Format of the udp packets of the SMAEM:
    # http://www.sma.de/fileadmin/content/global/Partner/Documents/SMA_Labs/EMETER-Protokoll-TI-de-10.pdf
    # http://www.eb-systeme.de/?page_id=1240
    # http://www.eb-systeme.de/?page_id=3005

    # Conversion like in this python code:
    # http://www.unifox.at/sma_energy_meter/
    # https://github.com/datenschuft/SMA-EM

    # unpack big-endian to 2-digit hex (bin2hex)
    my $hex = unpack('H*', $data);
    
    # OBIS Kennzahlen Zerlegung
    my $obis = {};
    my $i    = 56;                                                           # Start nach Header (28 Bytes)
    my $length;
    my ($b,$c,$d,$e);                                                        # OBIS Klassen
    
    while (substr($hex,$i,8) ne "00000000" && $i<=($dl*2)) {
        $b = hex(substr($hex,$i,2));
        $c = hex(substr($hex,$i+2,2));
        $d = hex(substr($hex,$i+4,2));
        $e = hex(substr($hex,$i+6,2));
        $length = $d*2;
        if ($b == 144) {
            # Firmware Version
            $obis->{$b.":0.0.0"} = hex(substr($hex,$i+8,2)).".".sprintf("%02d", hex(substr($hex,$i+10,2))).".".sprintf("%02d", hex(substr($hex,$i+12,2))).".".chr(hex(substr($hex,$i+14,2)));
            $i = $i + 16;
            next;
        }
        $obis->{"1:".$c.".".$d.".".$e} = hex(substr($hex,$i+8,$length));
        $i = $i + 8 + $length;
    }
    
    Log3 ($name, 5, "SMAEM $name - OBIS metrics identified:");
    my @ui;                                                                  # Array für "unknown items"
    foreach my $k (sort keys %{$obis}) {
        my $uit  = "unknown item";
        my $item = $SMAEM_obisitem{$k}?$SMAEM_obisitem{$k}:$uit;
        push(@ui, $k) if($item eq $uit); 
        Log3 ($name, 5, "SMAEM $name - $k -> ".$item." -> ".$obis->{$k});
    }   
  
 	################ Aufbau Ergebnis-Array ####################
    # Extract datasets from hex:
    # Generic:
    my $susyid       = hex(substr($hex,36,4));
    # SerialNumber     hex(substr($hex,40,8))
    my $milliseconds = hex(substr($hex,48,8));
	
    # Prestring with SMAEM and SERIALNO or not
    my $ps     = (!AttrVal($name, "disableSernoInReading", undef)) ? "SMAEM".$smaserial."_" : "";
	
    # Counter Divisor: [Hex-Value] = Ws => Ws/1000*3600=kWh => divide by 3600000
    # Sum L1-L3
    my $bezug_wirk             = $obis->{"1:1.4.0"}/10;
    my $bezug_wirk_count       = $obis->{"1:1.8.0"}/3600000;
    my $einspeisung_wirk       = $obis->{"1:2.4.0"}/10;
    my $einspeisung_wirk_count = $obis->{"1:2.8.0"}/3600000;
  
	# calculation of GRID-hashes and persist to file
    Log3 ($name, 4, "SMAEM $name - old GRIDIN_SUM_$smaserial got from RAM: $gridinsum");
	Log3 ($name, 4, "SMAEM $name - old GRIDOUT_SUM_$smaserial got from RAM: $gridoutsum");
	
	my $plausibility_out = 0;
    if( !$gridoutsum || ($bezug_wirk_count && $bezug_wirk_count < $gridoutsum) ) {
        $gridoutsum = $bezug_wirk_count;
		Log3 ($name, 4, "SMAEM $name - gridoutsum_$smaserial new set: $gridoutsum");
    } else {
        if ($gridoutsum && $bezug_wirk_count >= $gridoutsum) {
            if(($bezug_wirk_count - $gridoutsum) <= $diffaccept) {	
                # Plausibilitätscheck ob Differenz kleiner als erlaubter Wert -> Fehlerprävention			
                my $diffb = ($bezug_wirk_count - $gridoutsum)>0 ? sprintf("%.4f",$bezug_wirk_count - $gridoutsum) : 0;   
                Log3 ($name, 4, "SMAEM $name - bezug_wirk_count: $bezug_wirk_count");
                Log3 ($name, 4, "SMAEM $name - gridoutsum_$smaserial: $gridoutsum");
                Log3 ($name, 4, "SMAEM $name - diffb: $diffb");			
                $gridoutsum = $bezug_wirk_count;
			    push(@row_array, $ps."Bezug_WirkP_Zaehler_Diff ".$diffb."\n");
			    push(@row_array, $ps."Bezug_WirkP_Kosten_Diff ".sprintf("%.4f", $diffb*AttrVal($name, "powerCost", 0))."\n");
				$plausibility_out = 1;
			} else {
			    # Zyklus verwerfen wenn Plausibilität nicht erfüllt
				my $d = $bezug_wirk_count - $gridoutsum;
			    my $errtxt = "Cycle discarded due to allowed diff \"$d\" GRIDOUT exceeding. \n".
                             "Try to set attribute \"diffAccept > $d\" temporary or execute \"reset\".";
			    $error = encode_base64($errtxt,"");
				Log3 ($name, 1, "SMAEM $name - $errtxt");
				$gridinsum  = $einspeisung_wirk_count;
				$gridoutsum = $bezug_wirk_count;
		        $discycles++;
                return "$name|''|$gridinsum|$gridoutsum|$error|$discycles|''";     
			}
        }
    }  

	my $plausibility_in = 0;
    if( !$gridinsum || ($einspeisung_wirk_count && $einspeisung_wirk_count < $gridinsum) ) {
        $gridinsum = $einspeisung_wirk_count;
		Log3 ($name, 4, "SMAEM $name - gridinsum_$smaserial new set: $gridinsum");
    } else {
        if ($gridinsum && $einspeisung_wirk_count >= $gridinsum) {
		    if(($einspeisung_wirk_count - $gridinsum) <= $diffaccept) {
			    # Plausibilitätscheck ob Differenz kleiner als erlaubter Wert -> Fehlerprävention
                my $diffe = ($einspeisung_wirk_count - $gridinsum)>0 ? sprintf("%.4f",$einspeisung_wirk_count - $gridinsum) : 0;
                Log3 ($name, 4, "SMAEM $name - einspeisung_wirk_count: $einspeisung_wirk_count");
                Log3 ($name, 4, "SMAEM $name - gridinsum_$smaserial: $gridinsum");
                Log3 ($name, 4, "SMAEM $name - diffe: $diffe");
                $gridinsum = $einspeisung_wirk_count;
			    push(@row_array, $ps."Einspeisung_WirkP_Zaehler_Diff ".$diffe."\n");
			    push(@row_array, $ps."Einspeisung_WirkP_Verguet_Diff ".sprintf("%.4f", $diffe*AttrVal($name, "feedinPrice", 0))."\n");
				$plausibility_in = 1;
			} else {
			    # Zyklus verwerfen wenn Plausibilität nicht erfüllt
				my $d = $einspeisung_wirk_count - $gridinsum;
			    my $errtxt = "Cycle discarded due to allowed diff \"$d\" GRIDIN exceeding. \n".
                             "Try to set attribute \"diffAccept > $d\" temporary or execute \"reset\".";
			    $error = encode_base64($errtxt,"");
				Log3 ($name, 1, "SMAEM $name - $errtxt");
				$gridinsum  = $einspeisung_wirk_count;
				$gridoutsum = $bezug_wirk_count;
		        $discycles++;
                return "$name|''|$gridinsum|$gridoutsum|$error|$discycles|''";  
			}
        }
    }
    
    # write GRIDIN_SUM and GRIDOUT_SUM to file if plausibility check ok
	Log3 ($name, 4, "SMAEM $name - plausibility check done: GRIDIN -> $plausibility_in, GRIDOUT -> $plausibility_out");
    my $retcode = SMAEM_setsum($hash,$smaserial,$gridinsum,$gridoutsum) if($plausibility_in && $plausibility_out);
	
	# error while writing values to file
	if ($retcode) {
      	$error = encode_base64($retcode,"");
	    $discycles++;
        if(AttrVal($name, "noCoprocess", 0)) {
            return SMAEM_ParseDone("$name|''|''|''|$error|$discycles|''");
        } else {
            return "$name|''|''|''|$error|$discycles|''"; 
        }
	}
	
	push(@row_array, "state ".sprintf("%.1f", $einspeisung_wirk-$bezug_wirk)."\n");
	push(@row_array, $ps."Saldo_Wirkleistung ".sprintf("%.1f",$einspeisung_wirk-$bezug_wirk)."\n");
	push(@row_array, $ps."Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$einspeisung_wirk_count-$bezug_wirk_count)."\n");
	push(@row_array, $ps."Bezug_Wirkleistung ".sprintf("%.1f",$bezug_wirk)."\n");
	push(@row_array, $ps."Bezug_Wirkleistung_Zaehler ".sprintf("%.4f",$bezug_wirk_count)."\n");
	push(@row_array, $ps."Einspeisung_Wirkleistung ".sprintf("%.1f",$einspeisung_wirk)."\n");
	push(@row_array, $ps."Einspeisung_Wirkleistung_Zaehler ".sprintf("%.4f",$einspeisung_wirk_count)."\n");
      
    my $bezug_blind             = $obis->{"1:3.4.0"}/10;
    my $bezug_blind_count       = $obis->{"1:3.8.0"}/3600000;
    my $einspeisung_blind       = $obis->{"1:4.4.0"}/10;
    my $einspeisung_blind_count = $obis->{"1:4.8.0"}/3600000;
	push(@row_array, $ps."Bezug_Blindleistung ".sprintf("%.1f",$bezug_blind)."\n");
	push(@row_array, $ps."Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$bezug_blind_count)."\n");
	push(@row_array, $ps."Einspeisung_Blindleistung ".sprintf("%.1f",$einspeisung_blind)."\n");
	push(@row_array, $ps."Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$einspeisung_blind_count)."\n");

    my $bezug_schein             = $obis->{"1:9.4.0"}/10;
    my $bezug_schein_count       = $obis->{"1:9.8.0"}/3600000;
    my $einspeisung_schein       = $obis->{"1:10.4.0"}/10;
    my $einspeisung_schein_count = $obis->{"1:10.8.0"}/3600000;
	push(@row_array, $ps."Bezug_Scheinleistung ".sprintf("%.1f",$bezug_schein)."\n");
	push(@row_array, $ps."Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$bezug_schein_count)."\n");
	push(@row_array, $ps."Einspeisung_Scheinleistung ".sprintf("%.1f",$einspeisung_schein)."\n");
	push(@row_array, $ps."Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$einspeisung_schein_count)."\n");

    my $cosphi = $obis->{"1:13.4.0"}/1000;
	push(@row_array, $ps."CosPhi ".sprintf("%.3f",$cosphi)."\n");
    
    my $grid_freq = $obis->{"1:14.4.0"}/1000;
    push(@row_array, $ps."GridFreq ".$grid_freq."\n") if($grid_freq);
    
    push(@row_array, $ps."SoftwareVersion ".$obis->{"144:0.0.0"}."\n");
    push(@row_array, "SerialNumber ".$smaserial."\n") if(!$ps);
    push(@row_array, $ps."SUSyID ".$susyid."\n");
    
    if(!@ui) {
        push(@ui, "none");                                           # Wenn kein unbekanntes OBIS Item identifiziert wurde
    }
    push(@row_array, "OBISnewItems ".join(",",@ui)."\n");

    # L1
    my $l1_bezug_wirk             = $obis->{"1:21.4.0"}/10;
    my $l1_bezug_wirk_count       = $obis->{"1:21.8.0"}/3600000;
    my $l1_einspeisung_wirk       = $obis->{"1:22.4.0"}/10;
    my $l1_einspeisung_wirk_count = $obis->{"1:22.8.0"}/3600000;
    push(@row_array, $ps."L1_Saldo_Wirkleistung ".sprintf("%.1f",$l1_einspeisung_wirk-$l1_bezug_wirk)."\n");
    push(@row_array, $ps."L1_Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_wirk_count-$l1_bezug_wirk_count)."\n");	
    push(@row_array, $ps."L1_Bezug_Wirkleistung ".sprintf("%.1f",$l1_bezug_wirk)."\n");
    push(@row_array, $ps."L1_Bezug_Wirkleistung_Zaehler ".sprintf("%.1f",$l1_bezug_wirk_count)."\n");
    push(@row_array, $ps."L1_Einspeisung_Wirkleistung ".sprintf("%.1f",$l1_einspeisung_wirk)."\n");
    push(@row_array, $ps."L1_Einspeisung_Wirkleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_wirk_count)."\n");	
 
    my $l1_bezug_blind             = $obis->{"1:23.4.0"}/10;
    my $l1_bezug_blind_count       = $obis->{"1:23.8.0"}/3600000;
    my $l1_einspeisung_blind       = $obis->{"1:24.4.0"}/10;
    my $l1_einspeisung_blind_count = $obis->{"1:24.8.0"}/3600000;
    push(@row_array, $ps."L1_Bezug_Blindleistung ".sprintf("%.1f",$l1_bezug_blind)."\n");
    push(@row_array, $ps."L1_Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$l1_bezug_blind_count)."\n");
    push(@row_array, $ps."L1_Einspeisung_Blindleistung ".sprintf("%.1f",$l1_einspeisung_blind)."\n");
    push(@row_array, $ps."L1_Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_blind_count)."\n");

    my $l1_bezug_schein             = $obis->{"1:29.4.0"}/10;
    my $l1_bezug_schein_count       = $obis->{"1:29.8.0"}/3600000;
    my $l1_einspeisung_schein       = $obis->{"1:30.4.0"}/10;
    my $l1_einspeisung_schein_count = $obis->{"1:30.8.0"}/3600000;
	push(@row_array, $ps."L1_Bezug_Scheinleistung ".sprintf("%.1f",$l1_bezug_schein)."\n");
	push(@row_array, $ps."L1_Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$l1_bezug_schein_count)."\n");
	push(@row_array, $ps."L1_Einspeisung_Scheinleistung ".sprintf("%.1f",$l1_einspeisung_schein)."\n");
	push(@row_array, $ps."L1_Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_schein_count)."\n");

    my $l1_i       = $obis->{"1:31.4.0"}/1000;
    my $l1_v       = $obis->{"1:32.4.0"}/1000;
    my $l1_cosphi  = $obis->{"1:33.4.0"}/1000;
	push(@row_array, $ps."L1_Strom ".sprintf("%.2f",$l1_i)."\n");
	push(@row_array, $ps."L1_Spannung ".sprintf("%.1f",$l1_v)."\n");
	push(@row_array, $ps."L1_CosPhi ".sprintf("%.3f",$l1_cosphi)."\n");

    # L2
    my $l2_bezug_wirk             = $obis->{"1:41.4.0"}/10;
    my $l2_bezug_wirk_count       = $obis->{"1:41.8.0"}/3600000;
    my $l2_einspeisung_wirk       = $obis->{"1:42.4.0"}/10;
    my $l2_einspeisung_wirk_count = $obis->{"1:42.8.0"}/3600000;
    push(@row_array, $ps."L2_Saldo_Wirkleistung ".sprintf("%.1f",$l2_einspeisung_wirk-$l2_bezug_wirk)."\n");
    push(@row_array, $ps."L2_Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_wirk_count-$l2_bezug_wirk_count)."\n");	
    push(@row_array, $ps."L2_Bezug_Wirkleistung ".sprintf("%.1f",$l2_bezug_wirk)."\n");
    push(@row_array, $ps."L2_Bezug_Wirkleistung_Zaehler ".sprintf("%.1f",$l2_bezug_wirk_count)."\n");
    push(@row_array, $ps."L2_Einspeisung_Wirkleistung ".sprintf("%.1f",$l2_einspeisung_wirk)."\n");
    push(@row_array, $ps."L2_Einspeisung_Wirkleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_wirk_count)."\n");
 
    my $l2_bezug_blind             = $obis->{"1:43.4.0"}/10;
    my $l2_bezug_blind_count       = $obis->{"1:43.8.0"}/3600000;
    my $l2_einspeisung_blind       = $obis->{"1:44.4.0"}/10;
    my $l2_einspeisung_blind_count = $obis->{"1:44.8.0"}/3600000;
    push(@row_array, $ps."L2_Bezug_Blindleistung ".sprintf("%.1f",$l2_bezug_blind)."\n");
    push(@row_array, $ps."L2_Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$l2_bezug_blind_count)."\n");	
    push(@row_array, $ps."L2_Einspeisung_Blindleistung ".sprintf("%.1f",$l2_einspeisung_blind)."\n");
    push(@row_array, $ps."L2_Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_blind_count)."\n");

    my $l2_bezug_schein             = $obis->{"1:49.4.0"}/10;
    my $l2_bezug_schein_count       = $obis->{"1:49.8.0"}/3600000;
    my $l2_einspeisung_schein       = $obis->{"1:50.4.0"}/10;
    my $l2_einspeisung_schein_count = $obis->{"1:50.8.0"}/3600000;
    push(@row_array, $ps."L2_Bezug_Scheinleistung ".sprintf("%.1f",$l2_bezug_schein)."\n");
    push(@row_array, $ps."L2_Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$l2_bezug_schein_count)."\n");	
    push(@row_array, $ps."L2_Einspeisung_Scheinleistung ".sprintf("%.1f",$l2_einspeisung_schein)."\n");
    push(@row_array, $ps."L2_Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_schein_count)."\n");

    my $l2_i      = $obis->{"1:51.4.0"}/1000;
    my $l2_v      = $obis->{"1:52.4.0"}/1000;
    my $l2_cosphi = $obis->{"1:53.4.0"}/1000;
    push(@row_array, $ps."L2_Strom ".sprintf("%.2f",$l2_i)."\n");
    push(@row_array, $ps."L2_Spannung ".sprintf("%.1f",$l2_v)."\n");	
    push(@row_array, $ps."L2_CosPhi ".sprintf("%.3f",$l2_cosphi)."\n");

    # L3
    my $l3_bezug_wirk             = $obis->{"1:61.4.0"}/10;
    my $l3_bezug_wirk_count       = $obis->{"1:61.8.0"}/3600000;
    my $l3_einspeisung_wirk       = $obis->{"1:62.4.0"}/10;
    my $l3_einspeisung_wirk_count = $obis->{"1:62.8.0"}/3600000;
    push(@row_array, $ps."L3_Saldo_Wirkleistung ".sprintf("%.1f",$l3_einspeisung_wirk-$l3_bezug_wirk)."\n");
    push(@row_array, $ps."L3_Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_wirk_count-$l3_bezug_wirk_count)."\n");	
    push(@row_array, $ps."L3_Bezug_Wirkleistung ".sprintf("%.1f",$l3_bezug_wirk)."\n");
    push(@row_array, $ps."L3_Bezug_Wirkleistung_Zaehler ".sprintf("%.1f",$l3_bezug_wirk_count)."\n");
    push(@row_array, $ps."L3_Einspeisung_Wirkleistung ".sprintf("%.1f",$l3_einspeisung_wirk)."\n");
    push(@row_array, $ps."L3_Einspeisung_Wirkleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_wirk_count)."\n");

    my $l3_bezug_blind             = $obis->{"1:63.4.0"}/10;
    my $l3_bezug_blind_count       = $obis->{"1:63.8.0"}/3600000;
    my $l3_einspeisung_blind       = $obis->{"1:64.4.0"}/10;
    my $l3_einspeisung_blind_count = $obis->{"1:64.8.0"}/3600000;
    push(@row_array, $ps."L3_Bezug_Blindleistung ".sprintf("%.1f",$l3_bezug_blind)."\n");
    push(@row_array, $ps."L3_Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$l3_bezug_blind_count)."\n");	
    push(@row_array, $ps."L3_Einspeisung_Blindleistung ".sprintf("%.1f",$l3_einspeisung_blind)."\n");
    push(@row_array, $ps."L3_Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_blind_count)."\n");

    my $l3_bezug_schein             = $obis->{"1:69.4.0"}/10;
    my $l3_bezug_schein_count       = $obis->{"1:69.8.0"}/3600000;
    my $l3_einspeisung_schein       = $obis->{"1:70.4.0"}/10;
    my $l3_einspeisung_schein_count = $obis->{"1:70.8.0"}/3600000;
    push(@row_array, $ps."L3_Bezug_Scheinleistung ".sprintf("%.1f",$l3_bezug_schein)."\n");
    push(@row_array, $ps."L3_Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$l3_bezug_schein_count)."\n");	
    push(@row_array, $ps."L3_Einspeisung_Scheinleistung ".sprintf("%.1f",$l3_einspeisung_schein)."\n");
    push(@row_array, $ps."L3_Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_schein_count)."\n");

    my $l3_i      = $obis->{"1:71.4.0"}/1000;
    my $l3_v      = $obis->{"1:72.4.0"}/1000;
    my $l3_cosphi = $obis->{"1:73.4.0"}/1000;
    push(@row_array, $ps."L3_Strom ".sprintf("%.2f",$l3_i)."\n");
    push(@row_array, $ps."L3_Spannung ".sprintf("%.1f",$l3_v)."\n");	
    push(@row_array, $ps."L3_CosPhi ".sprintf("%.3f",$l3_cosphi)."\n");
 
    # encoding result 
    my $rowlist = join('_ESC_', @row_array);
    $rowlist    = encode_base64($rowlist,"");
 
    if(AttrVal($name, "noCoprocess", 0)) {
        return SMAEM_ParseDone ("$name|$rowlist|$gridinsum|$gridoutsum|''|$discycles|$smaserial");
    } else {
        return "$name|$rowlist|$gridinsum|$gridoutsum|''|$discycles|$smaserial"; 
    }
}

###############################################################
#         Auswertung non-blocking Inverter Datenabruf
###############################################################
sub SMAEM_ParseDone ($) {
 my ($string)   = @_;
 my @a          = split("\\|",$string);
 my $name       = $a[0];
 my $hash       = $defs{$name};
 my $rowlist    = decode_base64($a[1]);
 my $gridinsum  = $a[2];
 my $gridoutsum = $a[3];
 my $error      = decode_base64($a[4]) if($a[4]);
 my $discycles  = $a[5];
 my $smaserial  = $a[6];
 
 $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
 
 # update time
 SMAEM_setlastupdate($hash,$smaserial);
 
 if ($error) {
     readingsSingleUpdate($hash, "state", $error, 1);
	 delete($hash->{HELPER}{RUNNING_PID});
	 return;
 }

 $hash->{'GRIDIN_SUM_'.$smaserial}  = $gridinsum;
 $hash->{'GRIDOUT_SUM_'.$smaserial} = $gridoutsum;
 Log3($name, 4, "SMAEM $name - wrote new energy values to INTERNALS - GRIDIN_SUM_$smaserial: $gridinsum, GRIDOUT_SUM_$smaserial: $gridoutsum"); 

 my @row_array = split("_ESC_", $rowlist);
  
 readingsBeginUpdate($hash); 
 foreach my $row (@row_array) {
     chomp $row;
	 my @a = split(" ", $row, 2);
     readingsBulkUpdate($hash, $a[0], $a[1]);
 }
 readingsEndUpdate($hash, 1);

 delete($hash->{HELPER}{RUNNING_PID});
 CancelDelayedShutdown($name);
 
return;
}

###############################################################
#           Abbruchroutine Timeout Inverter Abfrage
###############################################################
sub SMAEM_ParseAborted ($) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  my $discycles  = $hash->{HELPER}{FAULTEDCYCLES};
  $cause = $cause?$cause:"Timeout: process terminated";
   
  $discycles++;
  $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
  Log3 ($name, 1, "SMAEM $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} $cause");
  readingsSingleUpdate($hash, "state", $cause, 1);
  delete($hash->{HELPER}{RUNNING_PID});
  CancelDelayedShutdown($name);
  
return;
}

###############################################################
#                  DbLog_splitFn
###############################################################
sub SMAEM_DbLogSplit ($) {
  my ($event,$device) = @_;
  my ($reading, $value, $unit) = "";

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value   = $parts[1];
  
  if($reading =~ m/.*leistung$/) {
      $unit = 'W';
  } elsif($reading =~ m/.*Spannung/) {
      $unit = 'V';
  } elsif($reading =~ m/.*Strom/) {
      $unit = 'A';
  } elsif($reading =~ m/.*leistung_Zaehler$/) {
      $unit = 'kWh';
  } else {
      if(!defined($parts[1])) {
	      $reading = "state";
	      $value   = $event;
		  $unit    = 'W';
	  } else {
          $value = $parts[1];
          $value = $value." ".$parts[2] if(defined($parts[2]));
	  }
  }

  Log3 ($device, 5, "SMAEM $device - Split for DbLog done -> Reading: ".$reading.", Value: ".(defined($value)?$value:'').", Unit: ".(defined($unit)?$unit:''));

return ($reading, $value, $unit);
}


###############################################################
#                  Hilfsroutinen
###############################################################

###############################################################
###       alle Serial-Nummern in cacheSMAEM speichern
sub SMAEM_setserials ($) {
    my ($hash)  = @_;
    my $name    = $hash->{NAME};
	my $modpath = $attr{global}{modpath};
    my ($index,$retcode,$as);
    
    $as = $hash->{HELPER}{ALLSERIALS};
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_allserials";
    $retcode = SMAEM_setCacheValue($hash,$index,$as);
    
    if ($retcode) { 
        Log3($name, 1, "SMAEM $name - ERROR while saving all serial numbers - $retcode");
    } else {
        Log3($name, 4, "SMAEM $name - all serial numbers were saved to $modpath/FHEM/FhemUtils/cacheSMAEM");
    }
return ($retcode);
}

###############################################################
###  Summenwerte für GridIn, GridOut speichern
sub SMAEM_setsum ($$$$) {
    my ($hash,$smaserial,$gridinsum,$gridoutsum) = @_;
    my $name    = $hash->{NAME};
	my $modpath = $attr{global}{modpath};
    my ($index,$retcode,$sumstr);
    
    $sumstr = $gridinsum."_".$gridoutsum;
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_".$smaserial;
    $retcode = SMAEM_setCacheValue($hash,$index,$sumstr);
    
    if ($retcode) { 
        Log3($name, 1, "SMAEM $name - ERROR while saving summary of energy values - $retcode");
    } else {
        Log3($name, 4, "SMAEM $name - new energy values saved to $modpath/FHEM/FhemUtils/cacheSMAEM");
		Log3($name, 4, "SMAEM $name - GRIDIN_SUM_$smaserial: $gridinsum, GRIDOUT_SUM_$smaserial: $gridoutsum"); 
    }
    
return ($retcode);
}

###############################################################
###  Schreibroutine in eigenes Keyvalue-File
sub SMAEM_setCacheValue ($$$) {
  my ($hash,$key,$value) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM";
  
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my ($err, @old) = FileRead($param);
  
  SMAEM_createCacheFile($hash) if($err); 
  
  my @new;
  my $fnd;
  foreach my $l (@old) {
    if($l =~ m/^$key:/) {
      $fnd = 1;
      push @new, "$key:$value" if(defined($value));
    } else {
      push @new, $l;
    }
  }
  push @new, "$key:$value" if(!$fnd && defined($value));

return FileWrite($param, @new);
}

###############################################################
###          gespeicherte Serial-Nummern auslesen
sub SMAEM_getserials ($) {
    my ($hash)  = @_;
    my $name    = $hash->{NAME};
    my $modpath = $attr{global}{modpath};
    my ($index,$retcode,$serials);
	
    $index = $hash->{TYPE}."_".$hash->{NAME}."_allserials";
    ($retcode, $serials) = SMAEM_getCacheValue($index);
    
    if ($retcode) {
        Log3($name, 1, "SMAEM $name - $retcode") if ($retcode);
        Log3($name, 3, "SMAEM $name - Create new cacheFile $modpath/FHEM/FhemUtils/cacheSMAEM");
		$retcode = SMAEM_createCacheFile($hash); 
    } else {
	    if ($serials) {
            $hash->{HELPER}{ALLSERIALS} = $serials;
            Log3 ($name, 3, "SMAEM $name - read saved serial numbers from $modpath/FHEM/FhemUtils/cacheSMAEM");  
        }
	}
    
return ($retcode);        
}

###############################################################
###  Summenwerte für GridIn, GridOut auslesen
sub SMAEM_getsum ($$) {
    my ($hash,$smaserial) = @_;
    my $name   = $hash->{NAME};
    my $modpath = $attr{global}{modpath};
    my ($index,$retcode,$sumstr);
	
    $index = $hash->{TYPE}."_".$hash->{NAME}."_".$smaserial;
    ($retcode, $sumstr) = SMAEM_getCacheValue($index);
    
    if ($retcode) { 
        Log3($name, 1, "SMAEM $name - $retcode") if ($retcode);
    } else {
	    if ($sumstr) {
            ($hash->{'GRIDIN_SUM_'.$smaserial}, $hash->{'GRIDOUT_SUM_'.$smaserial}) = split(/_/, $sumstr);
            Log3 ($name, 3, "SMAEM $name - read saved energy values from $modpath/FHEM/FhemUtils/cacheSMAEM");
			Log3 ($name, 3, "SMAEM $name - GRIDIN_SUM_$smaserial: $hash->{'GRIDIN_SUM_'.$smaserial}, GRIDOUT_SUM_$smaserial: $hash->{'GRIDOUT_SUM_'.$smaserial}");  
        }
	}
    
return ($retcode);        
}

###############################################################
###  Leseroutine aus eigenem Keyvalue-File
sub SMAEM_getCacheValue ($) {
  my ($key) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM";
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my ($err, @l) = FileRead($param);
  return ($err, undef) if($err);
  for my $l (@l) {
    return (undef, $1) if($l =~ m/^$key:(.*)/);
  }
  
return (undef, undef);
}

###############################################################
###  Anlegen eigenes Keyvalue-File wenn nicht vorhanden
sub SMAEM_createCacheFile ($) {
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM";
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my @new;
  push(@new, "# This file is auto generated from 77_SMAEM.",
             "# Please do not modify, move or delete it.",
             "");

return FileWrite($param, @new);
}

###############################################################
###  $update time of last update
sub SMAEM_setlastupdate ($$) {
    my ($hash,$smaserial) = @_;
	my $name              = $hash->{NAME};
	
	return if(!$smaserial);  # Abbruch wenn keine Seriennummer extrahiert
	
    $hash->{HELPER}{'LASTUPDATE_'.$smaserial} = time();
    my ($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime();
    $hash->{'LASTUPDATE_'.$smaserial} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
	Log3 ($name, 4, "SMAEM $name - last update time set to: $hash->{'LASTUPDATE_'.$smaserial}");
	
return;
}

#############################################################################################
#                          Versionierungen des Moduls setzen
#                  Die Verwendung von Meta.pm und Packages wird berücksichtigt
#############################################################################################
sub SMAEM_setVersionInfo($) {
  my ($hash) = @_;
  my $name   = $hash->{NAME};

  my $v                    = (sortTopicNum("desc",keys %SMAEM_vNotesIntern))[0];
  my $type                 = $hash->{TYPE};
  $hash->{HELPER}{PACKAGE} = __PACKAGE__;
  $hash->{HELPER}{VERSION} = $v;
  
  if($modules{$type}{META}{x_prereqs_src} && !$hash->{HELPER}{MODMETAABSENT}) {
	  # META-Daten sind vorhanden
	  $modules{$type}{META}{version} = "v".$v;              # Version aus META.json überschreiben, Anzeige mit {Dumper $modules{SMAPortal}{META}}
	  if($modules{$type}{META}{x_version}) {                                                                             # {x_version} ( nur gesetzt wenn $Id: 77_SMAEM.pm 19460 2019-05-24 20:19:41Z DS_Starter $ im Kopf komplett! vorhanden )
		  $modules{$type}{META}{x_version} =~ s/1.1.1/$v/g;
	  } else {
		  $modules{$type}{META}{x_version} = $v; 
	  }
	  return $@ unless (FHEM::Meta::SetInternals($hash));                                                                # FVERSION wird gesetzt ( nur gesetzt wenn $Id: 77_SMAEM.pm 19460 2019-05-24 20:19:41Z DS_Starter $ im Kopf komplett! vorhanden )
	  if(__PACKAGE__ eq "FHEM::$type" || __PACKAGE__ eq $type) {
	      # es wird mit Packages gearbeitet -> Perl übliche Modulversion setzen
		  # mit {<Modul>->VERSION()} im FHEMWEB kann Modulversion abgefragt werden
	      use version 0.77; our $VERSION = FHEM::Meta::Get( $hash, 'version' );                                          
      }
  } else {
	  # herkömmliche Modulstruktur
	  $hash->{VERSION} = $v;
  }
  
return;
}
 
1;

=pod
=item summary    Integration of SMA Energy Meters 
=item summary_DE Integration von SMA Energy Meter

=begin html

<a name="SMAEM"></a>
<h3>SMAEM</h3>
<br>

<a name="SMAEMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SMAEM </code><br>
    <br>
    Defines a SMA Energy Meter (SMAEM), a bidirectional energy meter/counter used in photovoltaics. 
    <br><br>
    You need at least one SMAEM on your local subnet or behind a multicast enabled network of routers to receive multicast messages from the SMAEM over the
    multicast group 239.12.255.254 on udp/9522. Multicast messages are sent by SMAEM once a second (firmware 1.02.04.R, March 2016).
    <br><br>
    The update interval will be set by attribute "interval". If not set, it defaults to 60s. Since the SMAEM sends updates once a second, you can
    update the readings once a second by lowering the interval to 1 (Not recommended, since it puts FHEM under heavy load).
    <br><br>
    The parameter "disableSernoInReading" changes the way readings are named: if disableSernoInReading is false or unset, the readings will be named
    "SMAEM&lt;serialnumber_&gt;.....".
    If set to true, the prefix "SMAEM&lt;serialnumber_&gt;" is skipped.
    Set this to true if you only have one SMAEM device on your network and you want shorter reading names.
    If unsure, leave it unset.
    <br><br>
    You need the perl module IO::Socket::Multicast. Under Debian (based) systems it can be installed with <code>apt-get install libio-socket-multicast-perl</code>.
  </ul>  
<br>
<br>

<a name="SMAEMset"></a>
<b>Set </b>
<ul>
  <li><b>reset</b> <br>
  The automatically generated file "cacheSMAEM" will be deleted. Then the file will be recreated again by the module.
  This function is used to reset the device in possible case of error condition, but may be executed at all times.  
  </li>
  <br>  
</ul>
  
<a name="SMAEMattr"></a>
<b>Attribute</b>
<ul>

  <a name="diffAccept"></a>
  <li><b>diffAccept</b> <br>
  The attribute diffAccept determines the threshold,  up to that a calaculated difference between two 
  straight sequently meter readings (Readings with *_Diff) should be commenly accepted (default = 10). <br>
  Hence faulty DB entries with a disproportional high difference values will be eliminated, don't 
  tamper the result and the measure cycles will be discarded.  
  </li>
  <br>
  
  <a name="disable"></a>
  <li><b>disable</b> <br>
  Disable or enable the device.
  </li>
  <br>
  
  <a name="disableSernoInReading"></a>
  <li><b>disableSernoInReading</b> <br>
  Prevents the prefix "SMAEM&lt;serialnumber_&gt;....."  
  </li>
  <br>
  
  <a name="feedinPrice"></a>
  <li><b>feedinPrice</b> <br>
  The individual amount of refund of one kilowatt hour
  </li>
  <br>
  
  <a name="interval"></a>
  <li><b>interval</b> <br>
  Evaluation interval in seconds 
  </li>
  <br>
  
  <a name="noCoprocess"></a>
  <li><b>noCoprocess</b> <br>
  If set, the energy evaluation takes place in a separate backround process. At default a
  parallel background process is started every evaluation period. This attribute can be helpful to optimize 
  the FHEM system.
  </li>
  <br>
  
  <a name="powerCost"></a>
  <li><b>powerCost</b> <br>
  The individual amount of power cost per kWh 
  </li>
  <br>
  
  <a name="serialNumber"></a>
  <li><b>serialNumber</b> <br>
  The serial number (e.g. 1900212213) of the SMA Energy Meter which data has to be received. <br>
  (default: no restriction)
  </li>
  <br>
  
  <a name="timeout"></a>
  <li><b>timeout</b> <br>
  Adjustment timeout of backgound processing (default 60s). The value of timeout has to be higher than the value 
  of "interval". 
  </li> 
  <br>

</ul>

=end html

=begin html_DE

<a name="SMAEM"></a>
<h3>SMAEM</h3>
<br>

<a name="SMAEMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SMAEM </code><br>
    <br>
    Definiert ein SMA Energy Meter (SMAEM), einen bidirektionalen Stromzähler, der häufig in Photovolatikanlagen der Firma SMA zum Einsatz kommt. 
    <br><br>
    Sie brauchen mindest ein SMAEM in Ihrem lokalen Netzwerk oder hinter einen multicastfähigen Netz von Routern, um die Daten des SMAEM über die
    Multicastgruppe 239.12.255.254 auf udp/9522 zu empfangen. Die Multicastpakete werden vom SMAEM einmal pro Sekunde ausgesendet (firmware 1.02.04.R, März 2016).
    <br><br>
    Das update interval kann über das Attribut "interval" gesetzt werden. Wenn es nicht gesetzt wird, werden updates per default alle 60 Sekunden durchgeführt.
    Da das SMAEM seine Daten sekündlich aktualisiert, kann das update interval auf bis zu einer Sekunde reduziert werden. Das wird nicht empfohlen, da FHEM
    sonst unter große Last gesetzt wird.
    <br><br>
    Der Parameter "disableSernoInReading" ändert die Art und Weise, wie die Readings des SMAEN bezeichnet werden: ist der Parameter false 
	oder nicht gesetzt, werden die Readings mit "SMAEM&lt;serialnumber_&gt;....." bezeichnet.
    Wird der Parameter auf true gesetzt, wird das Prefix "SMAEM&lt;serialnumber_&gt;....." weg gelassen.
    Sie können diesen Parameter auf true setzen, wenn Sie nicht mehr als ein SMAEM-Gerät in Ihrem Netzwerk haben und kürzere Namen für die Readings wünschen.
    Falls Sie unsicher sind, setzen Sie diesen Parameter nicht.
    <br><br>
    Sie benötigen das Perl-Module IO::Socket::Multicast für dieses FHEM Modul. Unter Debian (basierten) System, kann dies 
	mittels <code>apt-get install libio-socket-multicast-perl</code> installiert werden. 
  </ul>  
  <br>
  
<a name="SMAEMset"></a>
<b>Set </b>
<ul>
  <li><b>reset</b> <br>
  Es wird das automatisch erstellte File "cacheSMAEM" gelöscht. Das File wird durch das Modul wieder neu initialisiert
  angelegt. Diese Funktion wird zur Rücksetzung eines eventuellen Fehlerzustandes des Devices verwendet, kann 
  aber auch jederzeit ausgeführt werden.  
  </li>
  <br>  
</ul>
  
<a name="SMAEMattr"></a>
<b>Attribute</b>
<ul>

  <a name="diffAccept"></a>
  <li><b>diffAccept</b> <br>
  diffAccept legt fest, bis zu welchem Schwellenwert eine berechnete positive Werte-Differenz 
  zwischen zwei unmittelbar aufeinander folgenden Zählerwerten (Readings mit *_Diff) akzeptiert werden 
  soll (Standard ist 10). <br>
  Damit werden eventuell fehlerhafte Differenzen mit einem unverhältnismäßig hohen Differenzwert von der Berechnung 
  ausgeschlossen und der Messzyklus verworfen.  
  </li>
  <br>

  <a name="disable"></a>
  <li><b>disable</b> <br>
  1 = das Modul ist disabled 
  </li>
  <br>
  
  <a name="disableSernoInReading"></a>
  <li><b>disableSernoInReading</b> <br>
  unterdrückt das Prefix "SMAEM&lt;serialnumber_&gt;....."  
  </li>
  <br>
  
  <a name="feedinPrice"></a>
  <li><b>feedinPrice</b> <br>
  die individuelle Höhe der Vergütung pro Kilowattstunde 
  </li>
  <br>
  
  <a name="interval"></a>
  <li><b>interval</b> <br>
  Auswertungsinterval in Sekunden 
  </li>
  <br>
  
  <a name="noCoprocess"></a>
  <li><b>noCoprocess</b> <br>
  Wenn gesetzt, wird die Energieauswertung nicht in einen Hintergrundprozess ausgelagert. Im Standard wird 
  dazu ein paralleler Prozess gestartet. Das Attribut kann zur Optimierung des FHEM-Systems hilfreich sein.
  </li>
  <br>
  
  <a name="powerCost"></a>
  <li><b>powerCost</b> <br>
  die individuelle Höhe der Stromkosten pro Kilowattstunde 
  </li>
  <br>
  
  <a name="serialNumber"></a>
  <li><b>serialNumber</b> <br>
  Die Seriennummer (z.B. 1900212213) des SMA Energy Meters der durch das SMAEM-Device empfangen werden soll. <br>
  (default: keine Einschränkung)
  </li>
  <br>
  
  <a name="timeout"></a>
  <li><b>timeout</b> <br>
  Einstellung timeout für Hintergrundverarbeitung (default 60s). Der timeout-Wert muss größer als das Wert von 
  "interval" sein. 
  </li> 
  <br>

</ul>

=end html_DE

=for :application/json;q=META.json 77_SMAEM.pm
{
  "abstract": "Integration of one or more SMA Energy Meters.",
  "x_lang": {
    "de": {
      "abstract": "Integration von einem oder mehreren SMA Energy Metern."
    }
  },
  "keywords": [
    "SMA",
    "Photovoltaik",
    "SMA Energy Meter"
  ],
  "version": "v1.1.1",
  "release_status": "stable",
  "author": [
    "Volker Kettenbach <volker@kettenbach-it.de>",
    "Heiko Maaz <heiko.maaz@t-online.de>",
    null,
    null
  ],
  "x_fhem_maintainer": [
    "Volker Kettenbach",
    "DS_Starter",
    null,
    null
  ],
  "x_fhem_maintainer_github": [
    "Volker Kettenbach",
    "nasseeder1",
    null,
    null
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.014,
        "bignum": 0,
        "IO::Socket::Multicast": 0,
        "Blocking": 0      
      },
      "recommends": {
        "FHEM::Meta": 0
      },
      "suggests": {
      }
    }
  },
  "resources": {
    "repository": {
      "x_dev": {
        "type": "git",
        "url": "https://gitlab.com/volkerkettenbach/FHEM-SMA-Speedwire",
        "web": "https://gitlab.com/volkerkettenbach/FHEM-SMA-Speedwire/blob/master/77_SMAEM.pm",
        "x_branch": "dev",
        "x_raw": "https://gitlab.com/volkerkettenbach/FHEM-SMA-Speedwire/raw/master/77_SMAEM.pm"
      }      
    }
  },
  "x_support_status": "supported"
}
=end :application/json;q=META.json

=cut


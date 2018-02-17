################################################################################################
# $Id$
#
#  Copyright notice
#
#  (c) 2016 Copyright: Volker Kettenbach
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
#  https://github.com/kettenbach-it/FHEM-SMA-Speedwire
#
#################################################################################################
# Versions History done by DS_Starter
#
# 3.1.0    12.02.2018     extend error handling in define
# 3.0.1    26.11.2017     use abort cause of BlockingCall
# 3.0.0    29.09.2017     make SMAEM ready for multimeter usage
# 2.9.1    29.05.2017     DbLog_splitFn added, some function names adapted
# 2.9.0    25.05.2017     own SMAEM_setCacheValue, SMAEM_getCacheValue, new internal VERSION
# 2.8.2    03.12.2016     Prefix SMAEMserialnumber for Reading "state" removed, commandref adapted
# 2.8.1    02.12.2016     encode / decode $data 
# 2.8      02.12.2016     plausibility check of measured differences, attr diffAccept, timeout
#                         validation checks, improvement of failure prevention
# 2.7      01.12.2016     logging of discarded cycles 
# 2.6      01.12.2016     some improvements, better logging possibility
# 2.5      30.11.2016     some improvements
# 2.4      30.11.2016     some improvements, attributes disable, timeout for BlockingCall added
# 2.3      30.11.2016     SMAEM_getsum, SMAEM_setsum changed
# 2.2      29.11.2016     check error while writing values to file -> set state with error
# 2.1      29.11.2016     move $hash->{GRIDin_SUM}, $hash->{GRIDOUT_SUM} calc to smaread_ParseDone,
#                         some little improvements to logging process
# 2.0      28.11.2016     switch to nonblocking

package main;

use strict;
use warnings;
use bignum;
use IO::Socket::Multicast;
use Blocking;

my $SMAEMVersion = "3.1.0";

###############################################################
#                  SMAEM Initialize
###############################################################
sub SMAEM_Initialize($) {
  my ($hash) = @_;
  
  $hash->{ReadFn}        = "SMAEM_Read";
  $hash->{DefFn}         = "SMAEM_Define";
  $hash->{UndefFn}       = "SMAEM_Undef";
  $hash->{DeleteFn}      = "SMAEM_Delete";
  $hash->{DbLog_splitFn} = "SMAEM_DbLog_splitFn";
  $hash->{AttrFn}        = "SMAEM_Attr";
  $hash->{AttrList}      = "interval ".
                           "disable:1,0 ".
						   "diffAccept ".
                           "disableSernoInReading:1,0 ".
                           "feedinPrice ".
                           "powerCost ".
                           "timeout ".						
                           "$readingFnAttributes";
}

###############################################################
#                  SMAEM Define
###############################################################
sub SMAEM_Define($$) {
  my ($hash, $def) = @_;
  my $name= $hash->{NAME};
  my ($success, $gridin_sum, $gridout_sum);
  my $socket;
  
  $hash->{INTERVAL}              = 60 ;
  $hash->{VERSION}               = $SMAEMVersion;
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

  $hash->{TCPDev}= $socket;
  $hash->{FD} = $socket->fileno();
  delete($readyfnlist{"$name"});
  $selectlist{"$name"} = $hash;
  
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
sub SMAEM_Undef($$) {
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
sub SMAEM_Delete {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    
    # gespeicherte Energiezählerwerte löschen
    setKeyValue($index, undef);
    
return undef;
}

###############################################################
#                  SMAEM Attr
###############################################################
sub SMAEM_Attr {
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
sub SMAEM_Read($) {
  my ($hash) = @_;
  my $name= $hash->{NAME};
  my $socket= $hash->{TCPDev};
  my $timeout = AttrVal($name, "timeout", 60);
  my $data;
  
  return if(IsDisabled($name));
  return unless $socket->recv($data, 600); # Each SMAEM packet is 600 bytes of packed payload
  
  return if (time() <= $hash->{HELPER}{STARTTIME}+30);
  
  # decode serial number of dataset received
  my $hex       = unpack('H*', $data);
  my $smaserial = hex(substr($hex,40,8));
  
  return if(!$smaserial);
  
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
      Log3 ($name, 4, "SMAEM $name - ##############################################################");
      Log3 ($name, 4, "SMAEM $name - ### Begin of new SMA Energymeter $smaserial get data cycle ###");
	  Log3 ($name, 4, "SMAEM $name - ##############################################################");
	  Log3 ($name, 4, "SMAEM $name - discarded cycles since module start: $hash->{HELPER}{FAULTEDCYCLES}");
      
	  if($hash->{HELPER}{RUNNING_PID}) {
          Log3 ($name, 3, "SMAEM $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} has been killed to start a new BlockingCall");
	      BlockingKill($hash->{HELPER}{RUNNING_PID});
	      delete($hash->{HELPER}{RUNNING_PID});
      }

	  # update time
      SMAEM_setlastupdate($hash,$smaserial);
	  
	  my $dataenc = encode_base64($data,"");
      
	  $hash->{HELPER}{RUNNING_PID} = BlockingCall("SMAEM_DoParse", "$name|$dataenc|$smaserial", "SMAEM_ParseDone", $timeout, "SMAEM_ParseAborted", $hash); 
      Log3 ($name, 4, "SMAEM $name - Blocking process with PID: $hash->{HELPER}{RUNNING_PID}{pid} started");
  
  } else {
      
	  Log3 $hash, 5, "SMAEM $name: - received " . length($data) . " bytes but interval $hash->{INTERVAL}s isn't expired.";
  }
return undef;
}

###############################################################
#          non-blocking Inverter Datenabruf
###############################################################
sub SMAEM_DoParse($) {
 my ($string) = @_;
 my ($name,$dataenc,$smaserial) = split("\\|", $string);
 my $hash          = $defs{$name};
 my $data          = decode_base64($dataenc);
 my $discycles     = $hash->{HELPER}{FAULTEDCYCLES};
 my $diffaccept    = AttrVal($name, "diffAccept", 10);
 my @row_array;
 my @array;
 
 Log3 ($name, 4, "SMAEM $name -> Start BlockingCall SMAEM_DoParse");
 
 my $gridinsum  = $hash->{'GRIDIN_SUM_'.$smaserial} ?sprintf("%.4f",$hash->{'GRIDIN_SUM_'.$smaserial}):'';    
 my $gridoutsum = $hash->{'GRIDOUT_SUM_'.$smaserial}?sprintf("%.4f",$hash->{'GRIDOUT_SUM_'.$smaserial}):'';
 
 # check if cacheSMAEM-file has been opened at module start and try again if not
 if($hash->{HELPER}{READFILEERROR}) {
     my $retcode = SMAEM_getsum($hash,$smaserial);
	 if ($retcode) {
	     my $error = encode_base64($retcode,"");
	     Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_DoParse finished");
		 $discycles++;
         return "$name|''|''|''|$error|$discycles|''"; 
	 } else {
	     delete($hash->{HELPER}{READFILEERROR})
	 }
 }
 
    # Format of the udp packets of the SMAEM:
    # http://www.sma.de/fileadmin/content/global/Partner/Documents/SMA_Labs/EMETER-Protokoll-TI-de-10.pdf
    # http://www.eb-systeme.de/?page_id=1240

    # Conversion like in this python code:
    # http://www.unifox.at/sma_energy_meter/
    # https://github.com/datenschuft/SMA-EM

    # unpack big-endian to 2-digit hex (bin2hex)
    my $hex = unpack('H*', $data);
  
 	################ Aufbau Ergebnis-Array ####################
    # Extract datasets from hex:
    # Generic:
    my $susyid       = hex(substr($hex,36,4));
    # $smaserial    = hex(substr($hex,40,8));
    my $milliseconds = hex(substr($hex,48,8));
	# Prestring with SMAEM and SERIALNO or not
    my $ps = (!AttrVal($name, "disableSernoInReading", undef)) ? "SMAEM".$smaserial."_" : "";
	
    # Counter Divisor: [Hex-Value]=Ws => Ws/1000*3600=kWh => divide by 3600000
    # Sum L1-3
    my $bezug_wirk             = hex(substr($hex,64,8))/10;
    my $bezug_wirk_count       = hex(substr($hex,80,16))/3600000;
    my $einspeisung_wirk       = hex(substr($hex,104,8))/10;
    my $einspeisung_wirk_count = hex(substr($hex,120,16))/3600000;
  
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
			    my $errtxt = "cycle discarded due to allowed diff GRIDOUT exceeding";
			    my $error = encode_base64($errtxt,"");
				Log3 ($name, 1, "SMAEM $name - $errtxt");
		        Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_DoParse finished");
				$gridinsum = $einspeisung_wirk_count;
				$gridoutsum = $bezug_wirk_count;
		        $discycles++;
                return "$name|''|$gridinsum|$gridoutsum|''|$discycles|''";     
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
			    my $errtxt = "cycle discarded due to allowed diff GRIDIN exceeding";
			    my $error = encode_base64($errtxt,"");
				Log3 ($name, 1, "SMAEM $name - $errtxt");
		        Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_DoParse finished");
				$gridinsum = $einspeisung_wirk_count;
				$gridoutsum = $bezug_wirk_count;
		        $discycles++;
                return "$name|''|$gridinsum|$gridoutsum|''|$discycles|''";  
			}
        }
    }
    
    # write GRIDIN_SUM and GRIDOUT_SUM to file if plausibility check ok
	Log3 ($name, 4, "SMAEM $name - plausibility check done: GRIDIN -> $plausibility_in, GRIDOUT -> $plausibility_out");
    my $retcode = SMAEM_setsum($hash,$smaserial,$gridinsum,$gridoutsum) if($plausibility_in && $plausibility_out);
	
	# error while writing values to file
	if ($retcode) {
	    my $error = encode_base64($retcode,"");
		Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_DoParse finished");
		$discycles++;
        return "$name|''|''|''|$error|$discycles|''"; 
	}
	
	push(@row_array, "state ".sprintf("%.1f", $einspeisung_wirk-$bezug_wirk)."\n");
	push(@row_array, $ps."Saldo_Wirkleistung ".sprintf("%.1f",$einspeisung_wirk-$bezug_wirk)."\n");
	push(@row_array, $ps."Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$einspeisung_wirk_count-$bezug_wirk_count)."\n");
	push(@row_array, $ps."Bezug_Wirkleistung ".sprintf("%.1f",$bezug_wirk)."\n");
	push(@row_array, $ps."Bezug_Wirkleistung_Zaehler ".sprintf("%.4f",$bezug_wirk_count)."\n");
	push(@row_array, $ps."Einspeisung_Wirkleistung ".sprintf("%.1f",$einspeisung_wirk)."\n");
	push(@row_array, $ps."Einspeisung_Wirkleistung_Zaehler ".sprintf("%.4f",$einspeisung_wirk_count)."\n");
      
    my $bezug_blind=hex(substr($hex,144,8))/10;
    my $bezug_blind_count=hex(substr($hex,160,16))/3600000;
    my $einspeisung_blind=hex(substr($hex,184,8))/10;
    my $einspeisung_blind_count=hex(substr($hex,200,16))/3600000;
	push(@row_array, $ps."Bezug_Blindleistung ".sprintf("%.1f",$bezug_blind)."\n");
	push(@row_array, $ps."Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$bezug_blind_count)."\n");
	push(@row_array, $ps."Einspeisung_Blindleistung ".sprintf("%.1f",$einspeisung_blind)."\n");
	push(@row_array, $ps."Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$einspeisung_blind_count)."\n");

    my $bezug_schein=hex(substr($hex,224,8))/10;
    my $bezug_schein_count=hex(substr($hex,240,16))/3600000;
    my $einspeisung_schein=hex(substr($hex,264,8))/10;
    my $einspeisung_schein_count=hex(substr($hex,280,16))/3600000;
	push(@row_array, $ps."Bezug_Scheinleistung ".sprintf("%.1f",$bezug_schein)."\n");
	push(@row_array, $ps."Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$bezug_schein_count)."\n");
	push(@row_array, $ps."Einspeisung_Scheinleistung ".sprintf("%.1f",$einspeisung_schein)."\n");
	push(@row_array, $ps."Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$einspeisung_schein_count)."\n");

    my $cosphi=hex(substr($hex,304,8))/1000;
	push(@row_array, $ps."CosPhi ".sprintf("%.3f",$cosphi)."\n");

    # L1
    my $l1_bezug_wirk=hex(substr($hex,320,8))/10;
    my $l1_bezug_wirk_count=hex(substr($hex,336,16))/3600000;
    my $l1_einspeisung_wirk=hex(substr($hex,360,8))/10;
    my $l1_einspeisung_wirk_count=hex(substr($hex,376,16))/3600000;
    push(@row_array, $ps."L1_Saldo_Wirkleistung ".sprintf("%.1f",$l1_einspeisung_wirk-$l1_bezug_wirk)."\n");
    push(@row_array, $ps."L1_Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_wirk_count-$l1_bezug_wirk_count)."\n");	
    push(@row_array, $ps."L1_Bezug_Wirkleistung ".sprintf("%.1f",$l1_bezug_wirk)."\n");
    push(@row_array, $ps."L1_Bezug_Wirkleistung_Zaehler ".sprintf("%.1f",$l1_bezug_wirk_count)."\n");
    push(@row_array, $ps."L1_Einspeisung_Wirkleistung ".sprintf("%.1f",$l1_einspeisung_wirk)."\n");
    push(@row_array, $ps."L1_Einspeisung_Wirkleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_wirk_count)."\n");	
 
    my $l1_bezug_blind=hex(substr($hex,400,8))/10;
    my $l1_bezug_blind_count=hex(substr($hex,416,16))/3600000;
    my $l1_einspeisung_blind=hex(substr($hex,440,8))/10;
    my $l1_einspeisung_blind_count=hex(substr($hex,456,16))/3600000;
    push(@row_array, $ps."L1_Bezug_Blindleistung ".sprintf("%.1f",$l1_bezug_blind)."\n");
    push(@row_array, $ps."L1_Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$l1_bezug_blind_count)."\n");
    push(@row_array, $ps."L1_Einspeisung_Blindleistung ".sprintf("%.1f",$l1_einspeisung_blind)."\n");
    push(@row_array, $ps."L1_Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_blind_count)."\n");

    my $l1_bezug_schein=hex(substr($hex,480,8))/10;
    my $l1_bezug_schein_count=hex(substr($hex,496,16))/3600000;
    my $l1_einspeisung_schein=hex(substr($hex,520,8))/10;
    my $l1_einspeisung_schein_count=hex(substr($hex,536,16))/3600000;
	push(@row_array, $ps."L1_Bezug_Scheinleistung ".sprintf("%.1f",$l1_bezug_schein)."\n");
	push(@row_array, $ps."L1_Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$l1_bezug_schein_count)."\n");
	push(@row_array, $ps."L1_Einspeisung_Scheinleistung ".sprintf("%.1f",$l1_einspeisung_schein)."\n");
	push(@row_array, $ps."L1_Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$l1_einspeisung_schein_count)."\n");

    my $l1_thd=hex(substr($hex,560,8))/1000;
    my $l1_v=hex(substr($hex,576,8))/1000;
    my $l1_cosphi=hex(substr($hex,592,8))/1000;
	push(@row_array, $ps."L1_THD ".sprintf("%.2f",$l1_thd)."\n");
	push(@row_array, $ps."L1_Spannung ".sprintf("%.1f",$l1_v)."\n");
	push(@row_array, $ps."L1_CosPhi ".sprintf("%.3f",$l1_cosphi)."\n");

    # L2
    my $l2_bezug_wirk=hex(substr($hex,608,8))/10;
    my $l2_bezug_wirk_count=hex(substr($hex,624,16))/3600000;
    my $l2_einspeisung_wirk=hex(substr($hex,648,8))/10;
    my $l2_einspeisung_wirk_count=hex(substr($hex,664,16))/3600000;
    push(@row_array, $ps."L2_Saldo_Wirkleistung ".sprintf("%.1f",$l2_einspeisung_wirk-$l2_bezug_wirk)."\n");
    push(@row_array, $ps."L2_Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_wirk_count-$l2_bezug_wirk_count)."\n");	
    push(@row_array, $ps."L2_Bezug_Wirkleistung ".sprintf("%.1f",$l2_bezug_wirk)."\n");
    push(@row_array, $ps."L2_Bezug_Wirkleistung_Zaehler ".sprintf("%.1f",$l2_bezug_wirk_count)."\n");
    push(@row_array, $ps."L2_Einspeisung_Wirkleistung ".sprintf("%.1f",$l2_einspeisung_wirk)."\n");
    push(@row_array, $ps."L2_Einspeisung_Wirkleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_wirk_count)."\n");
 
    my $l2_bezug_blind=hex(substr($hex,688,8))/10;
    my $l2_bezug_blind_count=hex(substr($hex,704,16))/3600000;
    my $l2_einspeisung_blind=hex(substr($hex,728,8))/10;
    my $l2_einspeisung_blind_count=hex(substr($hex,744,16))/3600000;
    push(@row_array, $ps."L2_Bezug_Blindleistung ".sprintf("%.1f",$l2_bezug_blind)."\n");
    push(@row_array, $ps."L2_Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$l2_bezug_blind_count)."\n");	
    push(@row_array, $ps."L2_Einspeisung_Blindleistung ".sprintf("%.1f",$l2_einspeisung_blind)."\n");
    push(@row_array, $ps."L2_Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_blind_count)."\n");

    my $l2_bezug_schein=hex(substr($hex,768,8))/10;
    my $l2_bezug_schein_count=hex(substr($hex,784,16))/3600000;
    my $l2_einspeisung_schein=hex(substr($hex,808,8))/10;
    my $l2_einspeisung_schein_count=hex(substr($hex,824,16))/3600000;
    push(@row_array, $ps."L2_Bezug_Scheinleistung ".sprintf("%.1f",$l2_bezug_schein)."\n");
    push(@row_array, $ps."L2_Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$l2_bezug_schein_count)."\n");	
    push(@row_array, $ps."L2_Einspeisung_Scheinleistung ".sprintf("%.1f",$l2_einspeisung_schein)."\n");
    push(@row_array, $ps."L2_Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$l2_einspeisung_schein_count)."\n");

    my $l2_thd=hex(substr($hex,848,8))/1000;
    my $l2_v=hex(substr($hex,864,8))/1000;
    my $l2_cosphi=hex(substr($hex,880,8))/1000;
    push(@row_array, $ps."L2_THD ".sprintf("%.2f",$l2_thd)."\n");
    push(@row_array, $ps."L2_Spannung ".sprintf("%.1f",$l2_v)."\n");	
    push(@row_array, $ps."L2_CosPhi ".sprintf("%.3f",$l2_cosphi)."\n");

    # L3
    my $l3_bezug_wirk=hex(substr($hex,896,8))/10;
    my $l3_bezug_wirk_count=hex(substr($hex,912,16))/3600000;
    my $l3_einspeisung_wirk=hex(substr($hex,936,8))/10;
    my $l3_einspeisung_wirk_count=hex(substr($hex,952,16))/3600000;
    push(@row_array, $ps."L3_Saldo_Wirkleistung ".sprintf("%.1f",$l3_einspeisung_wirk-$l3_bezug_wirk)."\n");
    push(@row_array, $ps."L3_Saldo_Wirkleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_wirk_count-$l3_bezug_wirk_count)."\n");	
    push(@row_array, $ps."L3_Bezug_Wirkleistung ".sprintf("%.1f",$l3_bezug_wirk)."\n");
    push(@row_array, $ps."L3_Bezug_Wirkleistung_Zaehler ".sprintf("%.1f",$l3_bezug_wirk_count)."\n");
    push(@row_array, $ps."L3_Einspeisung_Wirkleistung ".sprintf("%.1f",$l3_einspeisung_wirk)."\n");
    push(@row_array, $ps."L3_Einspeisung_Wirkleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_wirk_count)."\n");

    my $l3_bezug_blind=hex(substr($hex,976,8))/10;
    my $l3_bezug_blind_count=hex(substr($hex,992,16))/3600000;
    my $l3_einspeisung_blind=hex(substr($hex,1016,8))/10;
    my $l3_einspeisung_blind_count=hex(substr($hex,1032,16))/3600000;
    push(@row_array, $ps."L3_Bezug_Blindleistung ".sprintf("%.1f",$l3_bezug_blind)."\n");
    push(@row_array, $ps."L3_Bezug_Blindleistung_Zaehler ".sprintf("%.1f",$l3_bezug_blind_count)."\n");	
    push(@row_array, $ps."L3_Einspeisung_Blindleistung ".sprintf("%.1f",$l3_einspeisung_blind)."\n");
    push(@row_array, $ps."L3_Einspeisung_Blindleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_blind_count)."\n");

    my $l3_bezug_schein=hex(substr($hex,1056,8))/10;
    my $l3_bezug_schein_count=hex(substr($hex,1072,16))/3600000;
    my $l3_einspeisung_schein=hex(substr($hex,1096,8))/10;
    my $l3_einspeisung_schein_count=hex(substr($hex,1112,16))/3600000;
    push(@row_array, $ps."L3_Bezug_Scheinleistung ".sprintf("%.1f",$l3_bezug_schein)."\n");
    push(@row_array, $ps."L3_Bezug_Scheinleistung_Zaehler ".sprintf("%.1f",$l3_bezug_schein_count)."\n");	
    push(@row_array, $ps."L3_Einspeisung_Scheinleistung ".sprintf("%.1f",$l3_einspeisung_schein)."\n");
    push(@row_array, $ps."L3_Einspeisung_Scheinleistung_Zaehler ".sprintf("%.1f",$l3_einspeisung_schein_count)."\n");

    my $l3_thd=hex(substr($hex,1136,8))/1000;
    my $l3_v=hex(substr($hex,1152,8))/1000;
    my $l3_cosphi=hex(substr($hex,1168,8))/1000;
    push(@row_array, $ps."L3_THD ".sprintf("%.2f",$l3_thd)."\n");
    push(@row_array, $ps."L3_Spannung ".sprintf("%.1f",$l3_v)."\n");	
    push(@row_array, $ps."L3_CosPhi ".sprintf("%.3f",$l3_cosphi)."\n");

    Log3 ($name, 5, "$name - row_array before encoding:");
    foreach my $row (@row_array) {
	    chomp $row;
        Log3 ($name, 5, "SMAEM $name - $row");
    }
 
    # encoding result 
    my $rowlist = join('|', @row_array);
    $rowlist    = encode_base64($rowlist,"");
 
    Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_DoParse finished");
 
return "$name|$rowlist|$gridinsum|$gridoutsum|''|$discycles|$smaserial"; 
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
 
 Log3 ($name, 4, "SMAEM $name -> Start BlockingCall SMAEM_ParseDone");
 
 $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
 
 # update time
 SMAEM_setlastupdate($hash,$smaserial);
 
 if ($error) {
     readingsSingleUpdate($hash, "state", $error, 1);
	 Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_ParseDone finished");
	 delete($hash->{HELPER}{RUNNING_PID});
	 return;
 }
 
 $hash->{'GRIDIN_SUM_'.$smaserial}  = $gridinsum;
 $hash->{'GRIDOUT_SUM_'.$smaserial} = $gridoutsum;
 Log3($name, 4, "SMAEM $name - wrote new energy values to INTERNALS - GRIDIN_SUM_$smaserial: $gridinsum, GRIDOUT_SUM_$smaserial: $gridoutsum"); 

 my @row_array = split("\\|", $rowlist);
 
 Log3 ($name, 5, "SMAEM $name - row_array after decoding:");
 foreach my $row (@row_array) {
     chomp $row;
     Log3 ($name, 5, "SMAEM $name - $row");
 }
 
 readingsBeginUpdate($hash); 
 foreach my $row (@row_array) {
     chomp $row;
	 my @a = split(" ", $row, 2);
     readingsBulkUpdate($hash, $a[0], $a[1]);
 }
 readingsEndUpdate($hash, 1);
 
 delete($hash->{HELPER}{RUNNING_PID});
 Log3 ($name, 4, "SMAEM $name -> BlockingCall SMAEM_ParseDone finished");
 
return;
}

###############################################################
#           Abbruchroutine Timeout Inverter Abfrage
###############################################################
sub SMAEM_ParseAborted($) {
  my ($hash,$cause) = @_;
  my $name = $hash->{NAME};
  my $discycles  = $hash->{HELPER}{FAULTEDCYCLES};
  $cause = $cause?$cause:"Timeout: process terminated";
   
  $discycles++;
  $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
  Log3 ($name, 1, "SMAEM $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} $cause");
  readingsSingleUpdate($hash, "state", $cause, 1);
  delete($hash->{HELPER}{RUNNING_PID});
}

###############################################################
#                  DbLog_splitFn
###############################################################
sub SMAEM_DbLog_splitFn($) {
  my ($event,$device) = @_;
  my ($reading, $value, $unit) = "";

  # Log3 ($device, 5, "SMAEM $device - splitFn splits event: ".$event);

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value   = $parts[1];
  
  if($reading =~ m/.*leistung$/) {
      $unit = 'W';
  } elsif($reading =~ m/.*Spannung/) {
      $unit = 'V';
  } elsif($reading =~ m/.*leistung_Zaehler$/) {
      $unit = 'kWh';
  } elsif($reading =~ m/.*THD$/) {
      $unit = '%';
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

  Log3 ($device, 5, "SMAEM $device - splitFn returns Reading: ".$reading.", Value: ".
       defined($value)?$value:''.", Unit: ".defined($unit)?$unit:'');

return ($reading, $value, $unit);
}


###############################################################
#                  Hilfsroutinen
###############################################################

###############################################################
###       alle Serial-Nummern in cacheSMAEM speichern
sub SMAEM_setserials ($) {
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my ($index,$retcode,$as);
	my $modpath = AttrVal("global", "modpath", undef);
    
    $as = $hash->{HELPER}{ALLSERIALS};
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_allserials";
    $retcode = SMAEM_setCacheValue($index,$as);
    
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
    my $name     = $hash->{NAME};
    my ($index,$retcode,$sumstr);
	my $modpath = AttrVal("global", "modpath", undef);
    
    $sumstr = $gridinsum."_".$gridoutsum;
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_".$smaserial;
    $retcode = SMAEM_setCacheValue($index,$sumstr);
    
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
sub SMAEM_setCacheValue($$) {
  my ($key,$value) = @_;
  my $fName = $attr{global}{modpath}."/FHEM/FhemUtils/cacheSMAEM";
  
  my $param = {
               FileName   => $fName,
               ForceType  => "file",
              };
  my ($err, @old) = FileRead($param);
  
  SMAEM_createCacheFile() if($err); 
  
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
    my ($hash) = @_;
    my $name   = $hash->{NAME};
    my ($index,$retcode,$serials);
    my $modpath = AttrVal("global", "modpath", undef);
	
    $index = $hash->{TYPE}."_".$hash->{NAME}."_allserials";
    ($retcode, $serials) = SMAEM_getCacheValue($index);
    
    if ($retcode) {
        Log3($name, 1, "SMAEM $name - $retcode") if ($retcode);
        Log3($name, 3, "SMAEM $name - Create new cacheFile $modpath/FHEM/FhemUtils/cacheSMAEM");
		$retcode = SMAEM_createCacheFile(); 
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
    my ($index,$retcode,$sumstr);
    my $modpath = AttrVal("global", "modpath", undef);
	
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
sub SMAEM_getCacheValue($) {
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
sub SMAEM_createCacheFile {
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
  
<a name="SMAEMattr"></a>
<b>Attribute</b>
<ul>
  <li><b>disableSernoInReading</b>  : prevents the prefix "SMAEM&lt;serialnumber_&gt;....."  </li>
  <li><b>feedinPrice</b>            : the individual amount of refund of one kilowatt hour</li>
  <li><b>interval</b>               : evaluation interval in seconds </li>
  <li><b>disable</b>                : 1 = the module is disabled </li>
  <li><b>diffAccept</b>             : diffAccept determines the threshold,  up to that a calaculated difference between two 
                                      straight sequently meter readings (Readings with *_Diff) should be commenly accepted (default = 10). <br>
                                      Hence faulty DB entries with a disproportional high difference values will be eliminated, don't 
									  tamper the result and the measure cycles will be discarded.  </li>
  <li><b>powerCost</b>              : the individual amount of power cost per kWh </li>
  <li><b>timeout</b>                : adjustment timeout of backgound processing (default 60s). The value of timeout has to be higher than the value of "interval". </li> 
</ul>
<br>

<a name="SMAEMreadings"></a>
<b>Readings</b> <br><br>

The created readings of SMAEM mostly are self-explanatory. 
However there are readings what maybe need some explanation. <br>

<ul>
  <li><b>&lt;Phase&gt;_THD</b>  : (Total Harmonic Distortion) - Proportion or quota of total effective value 
                                  of all harmonic component to effective value of fundamental component. 
								  Total ratio of harmonic component and interference of pure sinusoidal wave 
								  in %.
								  It is a rate of interferences. d is 0, if sinusoidal voltage exists and a sinusoidal 
								  current exists as well. As larger d, as more harmonic component are existing. 
								  According EN 50160/1999 the value mustn't exceed 8 %. 
								  If a current interference is so powerful that it is causing a voltage interference of 
								  more than 5 % (THD), that points to an issue with electrical potential.  </li>
</ul>
<br>

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
  
<a name="SMAEMattr"></a>
<b>Attribute</b>
<ul>
  <li><b>disableSernoInReading</b>  : unterdrückt das Prefix "SMAEM&lt;serialnumber_&gt;....."  </li>
  <li><b>feedinPrice</b>            : die individuelle Höhe der Vergütung pro Kilowattstunde </li>
  <li><b>interval</b>               : Auswertungsinterval in Sekunden </li>
  <li><b>disable</b>                : 1 = das Modul ist disabled </li>
  <li><b>diffAccept</b>             : diffAccept legt fest, bis zu welchem Schwellenwert eine berechnete positive Werte-Differenz 
                                      zwischen zwei unmittelbar aufeinander folgenden Zählerwerten (Readings mit *_Diff) akzeptiert werden 
									  soll (Standard ist 10). <br>
								      Damit werden eventuell fehlerhafte Differenzen mit einem unverhältnismäßig hohen Differenzwert von der Berechnung 
									  ausgeschlossen und der Messzyklus verworfen.  </li>
  <li><b>powerCost</b>              : die individuelle Höhe der Stromkosten pro Kilowattstunde </li>
  <li><b>timeout</b>                : Einstellung timeout für Hintergrundverarbeitung (default 60s). Der timeout-Wert muss größer als das Wert von "interval" sein. </li> 
</ul>
<br>

<a name="SMAEMreadings"></a>
<b>Readings</b> <br><br>

Die meisten erzeugten Readings von SMAEM sind selbsterklärend. 
Es gibt allerdings Readings die einer Erläuterung bedürfen. <br>

<ul>
  <li><b>&lt;Phase&gt;_THD</b>  : (Total Harmonic Distortion) - Verzerrungs- oder Gesamtklirrfaktor - Verhältnis oder 
                                  Anteil des Gesamteffektivwert aller Oberschwingungen zum Effektivwert der 
								  Grundschwingung. Gesamtanteil an Oberschwingungen und Störung der reinen Sinuswelle 
								  in % bzw. Verhältnis vom nutzbaren Grundschwingungsstrom zu den 
								  nicht nutzbaren Oberschwingungsströmen. Es ist ein Maß für Störungen. d ist 0, wenn bei 
								  sinusförmiger Spannung ein sinusförmiger Strom fließt. Je größer d, um so mehr 
								  Oberschwingungen sind vorhanden. Nach EN 50160/1999 z.B. darf der Wert 8 % nicht 
								  überschreiten. Wenn eine Stromstörung so stark ist, dass sie eine Spannungsstörung 
								  (THD) von über 5 % verursacht, deutet dies auf ein Potentialproblem hin.  </li>

</ul>
<br>

=end html_DE


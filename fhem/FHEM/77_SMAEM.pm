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
# 2.8.2    03.12.2016     Prefix SMAEMserialnumber for Reading "state" removed, commandref adapted
# 2.8.1    02.12.2016     encode / decode $data 
# 2.8      02.12.2016     plausibility check of measured differences, attr diffAccept, timeout
#                         validation checks, improvement of failure prevention
# 2.7      01.12.2016     logging of discarded cycles 
# 2.6      01.12.2016     some improvements, better logging possibility
# 2.5      30.11.2016     some improvements
# 2.4      30.11.2016     some improvements, attributes disable, timeout for BlockingCall added
# 2.3      30.11.2016     getsum, setsum changed
# 2.2      29.11.2016     check error while writing values to file -> set state with error
# 2.1      29.11.2016     move $hash->{GRIDin_SUM}, $hash->{GRIDOUT_SUM} calc to smaread_ParseDone,
#                         some little improvements to logging process
# 2.0      28.11.2016     switch to nonblocking

package main;

use strict;
use warnings;
use bignum;
use IO::Socket::Multicast;
# use Scalar::Util qw(looks_like_number);
use Blocking;

###############################################################
#                  SMAEM Initialize
###############################################################
sub SMAEM_Initialize($) {
  my ($hash) = @_;
  
  $hash->{ReadFn}     = "SMAEM_Read";
  $hash->{DefFn}      = "SMAEM_Define";
  $hash->{UndefFn}    = "SMAEM_Undef";
  $hash->{DeleteFn}   = "SMAEM_Delete";
  #$hash->{WriteFn} = "SMAEM_Write";
  #$hash->{ReadyFn} = "SMAEM_Ready";
  #$hash->{GetFn}   = "SMAEM_Get";
  #$hash->{SetFn}   = "SMAEM_Set";
  $hash->{AttrFn}     = "SMAEM_Attr";
  $hash->{AttrList}   = "interval ".
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
  
  $hash->{INTERVAL}              = 60 ;
  $hash->{LASTUPDATE}            = 0;
  $hash->{HELPER}{LASTUPDATE}    = 0;
  $hash->{HELPER}{FAULTEDCYCLES} = 0;
  $hash->{HELPER}{STARTTIME}     = time();
    
  Log3 $hash, 3, "SMAEM $name - Opening multicast socket...";
  my $socket = IO::Socket::Multicast->new(
           Proto     => 'udp',
           LocalPort => '9522',
           ReuseAddr => '1',
           ReusePort => defined(&ReusePort) ? 1 : 0,
  ) or return "Can't bind : $@";
  
  $socket->mcast_add('239.12.255.254');

  $hash->{TCPDev}= $socket;
  $hash->{FD} = $socket->fileno();
  delete($readyfnlist{"$name"});
  $selectlist{"$name"} = $hash;
  
  # gespeicherte Energiezählerwerte von File einlesen
  my $retcode = getsum($hash);
  
  if ($retcode) {
  	 $hash->{HELPER}{READFILEERROR} = $retcode;
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
  
  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
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
  
  if (time() <= $hash->{HELPER}{STARTTIME}+30) {
      return;
  }
  
  if ( $hash->{HELPER}{LASTUPDATE} == 0 || time() >= ($hash->{HELPER}{LASTUPDATE}+$hash->{INTERVAL}) ) {
      Log3 ($name, 4, "SMAEM $name - ###############################################################");
      Log3 ($name, 4, "SMAEM $name - ######### Begin of new SMA Energymeter get data cycle #########");
	  Log3 ($name, 4, "SMAEM $name - ###############################################################");
	  Log3 ($name, 4, "SMAEM $name - discarded cycles since module start: $hash->{HELPER}{FAULTEDCYCLES}");
      
	  if($hash->{helper}{RUNNING_PID}) {
          Log3 ($name, 3, "SMAEM $name - WARNING - old process $hash->{HELPER}{RUNNING_PID}{pid} has been killed to start a new BlockingCall");
	      BlockingKill($hash->{HELPER}{RUNNING_PID});
	      delete($hash->{HELPER}{RUNNING_PID});
      }

	  # update time
      lastupdate_set($hash);
	  
	  my $dataenc = encode_base64($data,"");
      
	  $hash->{HELPER}{RUNNING_PID} = BlockingCall("smaemread_DoParse", "$name|$dataenc", "smaemread_ParseDone", $timeout, "smaemread_ParseAborted", $hash); 
      Log3 ($name, 4, "SMAEM $name - Blocking process with PID: $hash->{HELPER}{RUNNING_PID}{pid} started");
  
  } else {
      
	  Log3 $hash, 5, "SMAEM $name: - received " . length($data) . " bytes but interval $hash->{INTERVAL}s isn't expired.";
  }
return undef;
}

###############################################################
#          non-blocking Inverter Datenabruf
###############################################################
sub smaemread_DoParse($) {
 my ($string) = @_;
 my ($name, $dataenc) = split("\\|", $string);
 my $hash          = $defs{$name};
 my $data          = decode_base64($dataenc);
 my $discycles     = $hash->{HELPER}{FAULTEDCYCLES};
 my $diffaccept    = AttrVal($name, "diffAccept", 10);
 my @row_array;
 my @array;
 
 Log3 ($name, 4, "SMAEM $name -> Start BlockingCall smaemread_DoParse");
 
 my $gridinsum  = $hash->{GRIDIN_SUM} ?sprintf("%.4f",$hash->{GRIDIN_SUM}):'';    
 my $gridoutsum = $hash->{GRIDOUT_SUM}?sprintf("%.4f",$hash->{GRIDOUT_SUM}):'';
 
 # check if uniqueID-file has been opened at module start and try again if not
 if($hash->{HELPER}{READFILEERROR}) {
     my $retcode = getsum($hash);
	 if ($retcode) {
	     my $error = encode_base64($retcode,"");
	     Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_DoParse finished");
		 $discycles++;
         return "$name|''|''|''|$error|$discycles"; 
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
    my $hex=unpack('H*', $data);
  
 	################ Aufbau Ergebnis-Array ####################
    # Extract datasets from hex:
    # Generic:
    my $susyid=hex(substr($hex,36,4));
    my $smaserial=hex(substr($hex,40,8));
    my $milliseconds=hex(substr($hex,48,8));
	# Prestring with NAME and SERIALNO or not
    my $ps = (!AttrVal($name, "disableSernoInReading", undef)) ? "SMAEM".$smaserial."_" : "";
	
    # Counter Divisor: [Hex-Value]=Ws => Ws/1000*3600=kWh => divide by 3600000
    # Sum L1-3
    my $bezug_wirk=hex(substr($hex,64,8))/10;
    my $bezug_wirk_count=hex(substr($hex,80,16))/3600000;
    my $einspeisung_wirk=hex(substr($hex,104,8))/10;
    my $einspeisung_wirk_count=hex(substr($hex,120,16))/3600000;
   

	# calculation of GRID-hashes and persist to file
    Log3 ($name, 4, "SMAEM $name - old GRIDIN_SUM got from RAM: $gridinsum");
	Log3 ($name, 4, "SMAEM $name - old GRIDOUT_SUM got from RAM: $gridoutsum");
	
	my $plausibility_out = 0;
    if( !$gridoutsum || ($bezug_wirk_count && $bezug_wirk_count < $gridoutsum) ) {
        $gridoutsum = $bezug_wirk_count;
		Log3 ($name, 4, "SMAEM $name - gridoutsum new set: $gridoutsum");
    } else {
        if ($gridoutsum && $bezug_wirk_count >= $gridoutsum) {
            if(($bezug_wirk_count - $gridoutsum) <= $diffaccept) {	
                # Plausibilitätscheck ob Differenz kleiner als erlaubter Wert -> Fehlerprävention			
                my $diffb = ($bezug_wirk_count - $gridoutsum)>0 ? sprintf("%.4f",$bezug_wirk_count - $gridoutsum) : 0;   
                Log3 ($name, 4, "SMAEM $name - bezug_wirk_count: $bezug_wirk_count");
                Log3 ($name, 4, "SMAEM $name - gridoutsum: $gridoutsum");
                Log3 ($name, 4, "SMAEM $name - diffb: $diffb");			
                $gridoutsum = $bezug_wirk_count;
			    push(@row_array, $ps."Bezug_WirkP_Zaehler_Diff ".$diffb."\n");
			    push(@row_array, $ps."Bezug_WirkP_Kosten_Diff ".sprintf("%.4f", $diffb*AttrVal($name, "powerCost", 0))."\n");
				$plausibility_out = 1;
			} else {
			    # Zyklus verwerfen wenn Plusibilität nicht erfüllt
			    my $errtxt = "cycle discarded due to allowed diff GRIDOUT exceeding";
			    my $error = encode_base64($errtxt,"");
				Log3 ($name, 1, "SMAEM $name - $errtxt");
		        Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_DoParse finished");
				$gridinsum = $einspeisung_wirk_count;
				$gridoutsum = $bezug_wirk_count;
		        $discycles++;
                return "$name|''|$gridinsum|$gridoutsum|''|$discycles";     
			}
        }
    }  

	my $plausibility_in = 0;
    if( !$gridinsum || ($einspeisung_wirk_count && $einspeisung_wirk_count < $gridinsum) ) {
        $gridinsum = $einspeisung_wirk_count;
		Log3 ($name, 4, "SMAEM $name - gridinsum new set: $gridinsum");
    } else {
        if ($gridinsum && $einspeisung_wirk_count >= $gridinsum) {
		    if(($einspeisung_wirk_count - $gridinsum) <= $diffaccept) {
			    # Plausibilitätscheck ob Differenz kleiner als erlaubter Wert -> Fehlerprävention
                my $diffe = ($einspeisung_wirk_count - $gridinsum)>0 ? sprintf("%.4f",$einspeisung_wirk_count - $gridinsum) : 0;
                Log3 ($name, 4, "SMAEM $name - einspeisung_wirk_count: $einspeisung_wirk_count");
                Log3 ($name, 4, "SMAEM $name - gridinsum: $gridinsum");
                Log3 ($name, 4, "SMAEM $name - diffe: $diffe");
                $gridinsum = $einspeisung_wirk_count;
			    push(@row_array, $ps."Einspeisung_WirkP_Zaehler_Diff ".$diffe."\n");
			    push(@row_array, $ps."Einspeisung_WirkP_Verguet_Diff ".sprintf("%.4f", $diffe*AttrVal($name, "feedinPrice", 0))."\n");
				$plausibility_in = 1;
			} else {
			    # Zyklus verwerfen wenn Plusibilität nicht erfüllt
			    my $errtxt = "cycle discarded due to allowed diff GRIDIN exceeding";
			    my $error = encode_base64($errtxt,"");
				Log3 ($name, 1, "SMAEM $name - $errtxt");
		        Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_DoParse finished");
				$gridinsum = $einspeisung_wirk_count;
				$gridoutsum = $bezug_wirk_count;
		        $discycles++;
                return "$name|''|$gridinsum|$gridoutsum|''|$discycles";  
			}
        }
    }
    
    # write GRIDIN_SUM and GRIDOUT_SUM to file if plausibility check ok
	Log3 ($name, 4, "SMAEM $name - plausibility check done: GRIDIN -> $plausibility_in, GRIDOUT -> $plausibility_out");
    my $retcode = setsum($hash, $gridinsum, $gridoutsum) if($plausibility_in && $plausibility_out);
	
	# error while writing values to file
	if ($retcode) {
	    my $error = encode_base64($retcode,"");
		Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_DoParse finished");
		$discycles++;
        return "$name|''|''|''|$error|$discycles"; 
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
 
    Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_DoParse finished");
 
return "$name|$rowlist|$gridinsum|$gridoutsum|''|$discycles"; 
}

###############################################################
#         Auswertung non-blocking Inverter Datenabruf
###############################################################
sub smaemread_ParseDone ($) {
 my ($string)   = @_;
 my @a          = split("\\|",$string);
 my $name       = $a[0];
 my $hash       = $defs{$name};
 my $rowlist    = decode_base64($a[1]);
 my $gridinsum  = $a[2];
 my $gridoutsum = $a[3];
 my $error      = decode_base64($a[4]) if($a[4]);
 my $discycles  = $a[5];
 
 Log3 ($name, 4, "SMAEM $name -> Start BlockingCall smaemread_ParseDone");
 
 $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
 
 # update time
 lastupdate_set($hash);
 
 if ($error) {
     readingsSingleUpdate($hash, "state", $error, 1);
	 Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_ParseDone finished");
	 delete($hash->{HELPER}{RUNNING_PID});
	 return;
 }
 
 $hash->{GRIDIN_SUM}         = $gridinsum;
 $hash->{GRIDOUT_SUM}        = $gridoutsum;
 Log3($name, 4, "SMAEM $name - wrote new energy values to INTERNALS - GRIDIN_SUM: $gridinsum, GRIDOUT_SUM: $gridoutsum"); 

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
 Log3 ($name, 4, "SMAEM $name -> BlockingCall smaemread_ParseDone finished");
 
return;
}

###############################################################
#           Abbruchroutine Timeout Inverter Abfrage
###############################################################
sub smaemread_ParseAborted($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $discycles  = $hash->{HELPER}{FAULTEDCYCLES};
   
  $discycles++;
  $hash->{HELPER}{FAULTEDCYCLES} = $discycles;
  Log3 ($name, 1, "SMAEM $name -> BlockingCall $hash->{HELPER}{RUNNING_PID}{fn} timed out");
  readingsSingleUpdate($hash, "state", "timeout", 1);
  delete($hash->{HELPER}{RUNNING_PID});
}


###############################################################
#                  Hilfsroutinen
###############################################################

###############################################################
###  Summenwerte für GridIn, GridOut speichern

sub setsum ($$$) {
    my ($hash, $gridinsum, $gridoutsum) = @_;
    my $name     = $hash->{NAME};
    my $index;
    my $retcode = 0;
    my $sumstr;
	my $modpath = AttrVal("global", "modpath", undef);
    
    $sumstr = $gridinsum."_".$gridoutsum;
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    $retcode = setKeyValue($index, $sumstr);
    
    if ($retcode) { 
        Log3($name, 1, "SMAEM $name - ERROR while saving summary of energy values - $retcode");
    } else {
        Log3($name, 4, "SMAEM $name - new energy values saved to $modpath/FHEM/FhemUtils/uniqueID:");
		Log3($name, 4, "SMAEM $name - GRIDIN_SUM: $gridinsum, GRIDOUT_SUM: $gridoutsum"); 
    }
return ($retcode);
}

###############################################################
###  Summenwerte für GridIn, GridOut abtufen
sub getsum ($) {
    my ($hash) = @_;
    my $name     = $hash->{NAME};
    my $index;
    my $retcode = 0;
    my $sumstr;
    my $modpath = AttrVal("global", "modpath", undef);
	
    $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    ($retcode, $sumstr) = getKeyValue($index);
    
    if ($retcode) {
        Log3($name, 1, "SMAEM $name - ERROR while reading saved energy values from $modpath/FHEM/FhemUtils/uniqueID:");
        Log3($name, 1, "SMAEM $name - $retcode");
    } else {
	    if ($sumstr) {
            ($hash->{GRIDIN_SUM}, $hash->{GRIDOUT_SUM}) = split(/_/, $sumstr);
            Log3 ($name, 3, "SMAEM $name - read saved energy values from $modpath/FHEM/FhemUtils/uniqueID:");
			Log3 ($name, 3, "SMAEM $name - GRIDIN_SUM: $hash->{GRIDIN_SUM}, GRIDOUT_SUM: $hash->{GRIDOUT_SUM}");  
        }
	}
return ($retcode);        
}

###############################################################
###  $update time of last update
sub lastupdate_set ($) {
    my ($hash) = @_;
	my $name     = $hash->{NAME};
	
    $hash->{HELPER}{LASTUPDATE} = time();
    my ($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime();
    $hash->{LASTUPDATE} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
	Log3 ($name, 4, "SMAEM $name - last update time set to: $hash->{LASTUPDATE}");
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
  <li><b>powerCost</b>              : die individuelle Höhe der Stromkosten pro Kilowattstunde </li>
  <li><b>timeout</b>                : Einstellung des timeout für die Wechselrichterabfrage (default 60s) </li> 
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
    Sie brauchen mindest ein SMAEM in Ihrem lokalen Netzwerk oder hinter einemmulticast fähigen Netz von Routern, um die Daten des SMAEM über die
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
  <li><b>timeout</b>                : Einstellung des timeout für die Wechselrichterabfrage (default 60s) </li> 
</ul>
  
=end html_DE


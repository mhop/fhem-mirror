################################################################
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
################################################################

package main;

use strict;
use warnings;
use bignum;

use IO::Socket::Multicast;

#####################################
sub
SMAEM_Initialize($)
{
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
                        "disableSernoInReading:1,0 ".
                        "feedinPrice ".
                        "powerCost ".	
                        "$readingFnAttributes";
}

#####################################
sub
SMAEM_Define($$)
{
  my ($hash, $def) = @_;
  my $name= $hash->{NAME};
  my ($success, $gridin_sum, $gridout_sum);
  
  $hash->{INTERVAL} = 60 ;
                
  $hash->{LASTUPDATE}=0;
  $hash->{HELPER}{LASTUPDATE} = 0;
    
  Log3 $hash, 3, "$name - Opening multicast socket...";
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
  ($success, $gridin_sum, $gridout_sum) = getsum($hash);
  if ($success) {
      $hash->{GRIDIN_SUM} = $gridin_sum;
      $hash->{GRIDOUT_SUM} = $gridout_sum;
      Log3 $name, 3, "$name - read saved energy values from file - GRIDIN_SUM: $gridin_sum, GRIDOUT_SUM: $gridout_sum";
  }
  
return undef;
}

sub
SMAEM_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name= $hash->{NAME};
  my $socket= $hash->{TCPDev};
  
  Log3 $hash, 3, "$name: Closing multicast socket...";
  $socket->mcast_drop('239.12.255.254');
  # $socket->close;
  
  my $ret = close($hash->{TCPDev});
  Log3 $hash, 4, "$name: Close-ret: $ret";
  delete($hash->{TCPDev});
  delete($selectlist{"$name"});
  delete($hash->{FD});

  return;
}

sub SMAEM_Delete {
    my ($hash, $arg) = @_;
    my $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    
    # gespeicherte Energiezählerwerte löschen
    setKeyValue($index, undef);
    
return undef;
}

sub SMAEM_Attr {
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  
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
        readingsSingleUpdate($hash, "state", "readingsreset", 1);
  }
  
return undef;
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub SMAEM_Read($) 
{
  my ($hash) = @_;
  my $name= $hash->{NAME};
  my $socket= $hash->{TCPDev};

  my $data;
  return unless $socket->recv($data, 600); # Each SMAEM packet is 600 bytes of packed payload
  Log3 $hash, 5, "$name: Received " . length($data) . " bytes.";

  if ($hash->{HELPER}{LASTUPDATE} == 0 || time() >= $hash->{HELPER}{LASTUPDATE}+$hash->{INTERVAL}) {
    
    # Format of the udp packets of the SMAEM:
    # http://www.sma.de/fileadmin/content/global/Partner/Documents/SMA_Labs/EMETER-Protokoll-TI-de-10.pdf
    # http://www.eb-systeme.de/?page_id=1240

    # Conversion like in this python code:
    # http://www.unifox.at/sma_energy_meter/
    # https://github.com/datenschuft/SMA-EM

    # unpack big-endian to 2-digit hex (bin2hex)
    my $hex=unpack('H*', $data);
  
    # Extract datasets from hex:
    # Generic:
    my $susyid=hex(substr($hex,36,4));
    my $smaserial=hex(substr($hex,40,8));
    my $milliseconds=hex(substr($hex,48,8));
    #readingsBulkUpdate($hash, "SUSy-ID", $susyid);
    #readingsBulkUpdate($hash, "Seriennummer", $smaserial);

    # Counter Divisor: [Hex-Value]=Ws => Ws/1000*3600=kWh => divide by 3600000
    # Sum L1-3
    my $bezug_wirk=hex(substr($hex,64,8))/10;
    my $bezug_wirk_count=hex(substr($hex,80,16))/3600000;
    my $einspeisung_wirk=hex(substr($hex,104,8))/10;
    my $einspeisung_wirk_count=hex(substr($hex,120,16))/3600000;
    
    # Prestring with NAME and SERIALNO or not
    my $ps = (!AttrVal($name, "disableSernoInReading", undef)) ? "SMAEM".$smaserial."_" : "";
    
    readingsBeginUpdate($hash);   
    
    readingsBulkUpdate($hash, "state", sprintf("%.1f", $einspeisung_wirk-$bezug_wirk));
    readingsBulkUpdate($hash, $ps."Saldo_Wirkleistung", sprintf("%.1f",$einspeisung_wirk-$bezug_wirk));
    readingsBulkUpdate($hash, $ps."Saldo_Wirkleistung_Zaehler", sprintf("%.1f",$einspeisung_wirk_count-$bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."Bezug_Wirkleistung", sprintf("%.1f",$bezug_wirk));
    readingsBulkUpdate($hash, $ps."Bezug_Wirkleistung_Zaehler", sprintf("%.4f",$bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."Einspeisung_Wirkleistung", sprintf("%.1f",$einspeisung_wirk));
    readingsBulkUpdate($hash, $ps."Einspeisung_Wirkleistung_Zaehler", sprintf("%.4f",$einspeisung_wirk_count));
    
    if(!$hash->{GRIDOUT_SUM} || ReadingsVal($name,$ps."Bezug_Wirkleistung_Zaehler","") < $hash->{GRIDOUT_SUM}) {
        $hash->{GRIDOUT_SUM} = sprintf("%.4f",$bezug_wirk_count);
    } else {
        if (ReadingsVal($name,$ps."Bezug_Wirkleistung_Zaehler","") >= $hash->{GRIDOUT_SUM}) {     
            my $diffb = $bezug_wirk_count - $hash->{GRIDOUT_SUM};     
            $hash->{GRIDOUT_SUM} = sprintf("%.4f",$bezug_wirk_count);
            readingsBulkUpdate($hash, $ps."Bezug_WirkP_Zaehler_Diff", $diffb);
	    readingsBulkUpdate($hash, $ps."Bezug_WirkP_Kosten_Diff", sprintf("%.4f", $diffb*AttrVal($hash->{NAME}, "powerCost", 0)));
        }
    }

    if(!$hash->{GRIDIN_SUM} || ReadingsVal($name,$ps."Einspeisung_Wirkleistung_Zaehler","") < $hash->{GRIDIN_SUM}) {
        $hash->{GRIDIN_SUM} = sprintf("%.4f",$einspeisung_wirk_count);
    } else {
        if (ReadingsVal($name,$ps."Einspeisung_Wirkleistung_Zaehler","") >= $hash->{GRIDIN_SUM}) {
            my $diffe = $einspeisung_wirk_count - $hash->{GRIDIN_SUM};
            $hash->{GRIDIN_SUM} = sprintf("%.4f",$einspeisung_wirk_count);
            readingsBulkUpdate($hash, $ps."Einspeisung_WirkP_Zaehler_Diff", $diffe);
	    readingsBulkUpdate($hash, $ps."Einspeisung_WirkP_Verguet_Diff", sprintf("%.4f", $diffe*AttrVal($hash->{NAME}, "feedinPrice", 0)));
        }
    }
    
    # GRIDIN_SUM und GRIDOUT_SUM in File schreiben
    my $success = setsum($hash, $hash->{GRIDIN_SUM}, $hash->{GRIDOUT_SUM});
      
    my $bezug_blind=hex(substr($hex,144,8))/10;
    my $bezug_blind_count=hex(substr($hex,160,16))/3600000;
    my $einspeisung_blind=hex(substr($hex,184,8))/10;
    my $einspeisung_blind_count=hex(substr($hex,200,16))/3600000;
    readingsBulkUpdate($hash, $ps."Bezug_Blindleistung", sprintf("%.1f",$bezug_blind));
    readingsBulkUpdate($hash, $ps."Bezug_Blindleistung_Zaehler", sprintf("%.1f",$bezug_blind_count));
    readingsBulkUpdate($hash, $ps."Einspeisung_Blindleistung", sprintf("%.1f",$einspeisung_blind));
    readingsBulkUpdate($hash, $ps."Einspeisung_Blindleistung_Zaehler", sprintf("%.1f",$einspeisung_blind_count));

    my $bezug_schein=hex(substr($hex,224,8))/10;
    my $bezug_schein_count=hex(substr($hex,240,16))/3600000;
    my $einspeisung_schein=hex(substr($hex,264,8))/10;
    my $einspeisung_schein_count=hex(substr($hex,280,16))/3600000;
    readingsBulkUpdate($hash, $ps."Bezug_Scheinleistung", sprintf("%.1f",$bezug_schein));
    readingsBulkUpdate($hash, $ps."Bezug_Scheinleistung_Zaehler", sprintf("%.1f",$bezug_schein_count));
    readingsBulkUpdate($hash, $ps."Einspeisung_Scheinleistung", sprintf("%.1f",$einspeisung_schein));
    readingsBulkUpdate($hash, $ps."Einspeisung_Scheinleistung_Zaehler", sprintf("%.1f",$einspeisung_schein_count));

    my $cosphi=hex(substr($hex,304,8))/1000;
    readingsBulkUpdate($hash, $ps."CosPhi", sprintf("%.3f",$cosphi));

    # L1
    my $l1_bezug_wirk=hex(substr($hex,320,8))/10;
    my $l1_bezug_wirk_count=hex(substr($hex,336,16))/3600000;
    my $l1_einspeisung_wirk=hex(substr($hex,360,8))/10;
    my $l1_einspeisung_wirk_count=hex(substr($hex,376,16))/3600000;
    readingsBulkUpdate($hash, $ps."L1_Saldo_Wirkleistung", sprintf("%.1f",$l1_einspeisung_wirk-$l1_bezug_wirk));
    readingsBulkUpdate($hash, $ps."L1_Saldo_Wirkleistung_Zaehler", sprintf("%.1f",$l1_einspeisung_wirk_count-$l1_bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."L1_Bezug_Wirkleistung", sprintf("%.1f",$l1_bezug_wirk));
    readingsBulkUpdate($hash, $ps."L1_Bezug_Wirkleistung_Zaehler", sprintf("%.1f",$l1_bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."L1_Einspeisung_Wirkleistung", sprintf("%.1f",$l1_einspeisung_wirk));
    readingsBulkUpdate($hash, $ps."L1_Einspeisung_Wirkleistung_Zaehler", sprintf("%.1f",$l1_einspeisung_wirk_count));
 
    my $l1_bezug_blind=hex(substr($hex,400,8))/10;
    my $l1_bezug_blind_count=hex(substr($hex,416,16))/3600000;
    my $l1_einspeisung_blind=hex(substr($hex,440,8))/10;
    my $l1_einspeisung_blind_count=hex(substr($hex,456,16))/3600000;
    readingsBulkUpdate($hash, $ps."L1_Bezug_Blindleistung", sprintf("%.1f",$l1_bezug_blind));
    readingsBulkUpdate($hash, $ps."L1_Bezug_Blindleistung_Zaehler", sprintf("%.1f",$l1_bezug_blind_count));
    readingsBulkUpdate($hash, $ps."L1_Einspeisung_Blindleistung", sprintf("%.1f",$l1_einspeisung_blind));
    readingsBulkUpdate($hash, $ps."L1_Einspeisung_Blindleistung_Zaehler", sprintf("%.1f",$l1_einspeisung_blind_count));

    my $l1_bezug_schein=hex(substr($hex,480,8))/10;
    my $l1_bezug_schein_count=hex(substr($hex,496,16))/3600000;
    my $l1_einspeisung_schein=hex(substr($hex,520,8))/10;
    my $l1_einspeisung_schein_count=hex(substr($hex,536,16))/3600000;
    readingsBulkUpdate($hash, $ps."L1_Bezug_Scheinleistung", sprintf("%.1f",$l1_bezug_schein));
    readingsBulkUpdate($hash, $ps."L1_Bezug_Scheinleistung_Zaehler", sprintf("%.1f",$l1_bezug_schein_count));
    readingsBulkUpdate($hash, $ps."L1_Einspeisung_Scheinleistung", sprintf("%.1f",$l1_einspeisung_schein));
    readingsBulkUpdate($hash, $ps."L1_Einspeisung_Scheinleistung_Zaehler", sprintf("%.1f",$l1_einspeisung_schein_count));

    my $l1_thd=hex(substr($hex,560,8))/1000;
    my $l1_v=hex(substr($hex,576,8))/1000;
    my $l1_cosphi=hex(substr($hex,592,8))/1000;
    readingsBulkUpdate($hash, $ps."L1_THD", sprintf("%.2f",$l1_thd));
    readingsBulkUpdate($hash, $ps."L1_Spannung", sprintf("%.1f",$l1_v));
    readingsBulkUpdate($hash, $ps."L1_CosPhi", sprintf("%.3f",$l1_cosphi));


    # L2
    my $l2_bezug_wirk=hex(substr($hex,608,8))/10;
    my $l2_bezug_wirk_count=hex(substr($hex,624,16))/3600000;
    my $l2_einspeisung_wirk=hex(substr($hex,648,8))/10;
    my $l2_einspeisung_wirk_count=hex(substr($hex,664,16))/3600000;
    readingsBulkUpdate($hash, $ps."L2_Saldo_Wirkleistung", sprintf("%.1f",$l2_einspeisung_wirk-$l2_bezug_wirk));
    readingsBulkUpdate($hash, $ps."L2_Saldo_Wirkleistung_Zaehler", sprintf("%.1f",$l2_einspeisung_wirk_count-$l2_bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."L2_Bezug_Wirkleistung", sprintf("%.1f",$l2_bezug_wirk));
    readingsBulkUpdate($hash, $ps."L2_Bezug_Wirkleistung_Zaehler", sprintf("%.1f",$l2_bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."L2_Einspeisung_Wirkleistung", sprintf("%.1f",$l2_einspeisung_wirk));
    readingsBulkUpdate($hash, $ps."L2_Einspeisung_Wirkleistung_Zaehler", sprintf("%.1f",$l2_einspeisung_wirk_count));
 
    my $l2_bezug_blind=hex(substr($hex,688,8))/10;
    my $l2_bezug_blind_count=hex(substr($hex,704,16))/3600000;
    my $l2_einspeisung_blind=hex(substr($hex,728,8))/10;
    my $l2_einspeisung_blind_count=hex(substr($hex,744,16))/3600000;
    readingsBulkUpdate($hash, $ps."L2_Bezug_Blindleistung", sprintf("%.1f",$l2_bezug_blind));
    readingsBulkUpdate($hash, $ps."L2_Bezug_Blindleistung_Zaehler", sprintf("%.1f",$l2_bezug_blind_count));
    readingsBulkUpdate($hash, $ps."L2_Einspeisung_Blindleistung", sprintf("%.1f",$l2_einspeisung_blind));
    readingsBulkUpdate($hash, $ps."L2_Einspeisung_Blindleistung_Zaehler", sprintf("%.1f",$l2_einspeisung_blind_count));

    my $l2_bezug_schein=hex(substr($hex,768,8))/10;
    my $l2_bezug_schein_count=hex(substr($hex,784,16))/3600000;
    my $l2_einspeisung_schein=hex(substr($hex,808,8))/10;
    my $l2_einspeisung_schein_count=hex(substr($hex,824,16))/3600000;
    readingsBulkUpdate($hash, $ps."L2_Bezug_Scheinleistung", sprintf("%.1f",$l2_bezug_schein));
    readingsBulkUpdate($hash, $ps."L2_Bezug_Scheinleistung_Zaehler", sprintf("%.1f",$l2_bezug_schein_count));
    readingsBulkUpdate($hash, $ps."L2_Einspeisung_Scheinleistung", sprintf("%.1f",$l2_einspeisung_schein));
    readingsBulkUpdate($hash, $ps."L2_Einspeisung_Scheinleistung_Zaehler", sprintf("%.1f",$l2_einspeisung_schein_count));

    my $l2_thd=hex(substr($hex,848,8))/1000;
    my $l2_v=hex(substr($hex,864,8))/1000;
    my $l2_cosphi=hex(substr($hex,880,8))/1000;
    readingsBulkUpdate($hash, $ps."L2_THD", sprintf("%.2f",$l2_thd));
    readingsBulkUpdate($hash, $ps."L2_Spannung", sprintf("%.1f",$l2_v));
    readingsBulkUpdate($hash, $ps."L2_CosPhi", sprintf("%.3f",$l2_cosphi));

    # L3
    my $l3_bezug_wirk=hex(substr($hex,896,8))/10;
    my $l3_bezug_wirk_count=hex(substr($hex,912,16))/3600000;
    my $l3_einspeisung_wirk=hex(substr($hex,936,8))/10;
    my $l3_einspeisung_wirk_count=hex(substr($hex,952,16))/3600000;
    readingsBulkUpdate($hash, $ps."L3_Saldo_Wirkleistung", sprintf("%.1f",$l3_einspeisung_wirk-$l3_bezug_wirk));
    readingsBulkUpdate($hash, $ps."L3_Saldo_Wirkleistung_Zaehler", sprintf("%.1f",$l3_einspeisung_wirk_count-$l3_bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."L3_Bezug_Wirkleistung", sprintf("%.1f",$l3_bezug_wirk));
    readingsBulkUpdate($hash, $ps."L3_Bezug_Wirkleistung_Zaehler", sprintf("%.1f",$l3_bezug_wirk_count));
    readingsBulkUpdate($hash, $ps."L3_Einspeisung_Wirkleistung", sprintf("%.1f",$l3_einspeisung_wirk));
    readingsBulkUpdate($hash, $ps."L3_Einspeisung_Wirkleistung_Zaehler", sprintf("%.1f",$l3_einspeisung_wirk_count));

    my $l3_bezug_blind=hex(substr($hex,976,8))/10;
    my $l3_bezug_blind_count=hex(substr($hex,992,16))/3600000;
    my $l3_einspeisung_blind=hex(substr($hex,1016,8))/10;
    my $l3_einspeisung_blind_count=hex(substr($hex,1032,16))/3600000;
    readingsBulkUpdate($hash, $ps."L3_Bezug_Blindleistung", sprintf("%.1f",$l3_bezug_blind));
    readingsBulkUpdate($hash, $ps."L3_Bezug_Blindleistung_Zaehler", sprintf("%.1f",$l3_bezug_blind_count));
    readingsBulkUpdate($hash, $ps."L3_Einspeisung_Blindleistung", sprintf("%.1f",$l3_einspeisung_blind));
    readingsBulkUpdate($hash, $ps."L3_Einspeisung_Blindleistung_Zaehler", sprintf("%.1f",$l3_einspeisung_blind_count));

    my $l3_bezug_schein=hex(substr($hex,1056,8))/10;
    my $l3_bezug_schein_count=hex(substr($hex,1072,16))/3600000;
    my $l3_einspeisung_schein=hex(substr($hex,1096,8))/10;
    my $l3_einspeisung_schein_count=hex(substr($hex,1112,16))/3600000;
    readingsBulkUpdate($hash, $ps."L3_Bezug_Scheinleistung", sprintf("%.1f",$l3_bezug_schein));
    readingsBulkUpdate($hash, $ps."L3_Bezug_Scheinleistung_Zaehler", sprintf("%.1f",$l3_bezug_schein_count));
    readingsBulkUpdate($hash, $ps."L3_Einspeisung_Scheinleistung", sprintf("%.1f",$l3_einspeisung_schein));
    readingsBulkUpdate($hash, $ps."L3_Einspeisung_Scheinleistung_Zaehler", sprintf("%.1f",$l3_einspeisung_schein_count));

    my $l3_thd=hex(substr($hex,1136,8))/1000;
    my $l3_v=hex(substr($hex,1152,8))/1000;
    my $l3_cosphi=hex(substr($hex,1168,8))/1000;
    readingsBulkUpdate($hash, $ps."L3_THD", sprintf("%.2f",$l3_thd));
    readingsBulkUpdate($hash, $ps."L3_Spannung", sprintf("%.1f",$l3_v));
    readingsBulkUpdate($hash, $ps."L3_CosPhi", sprintf("%.3f",$l3_cosphi));

    readingsEndUpdate($hash, 1);

    $hash->{HELPER}{LASTUPDATE}=time();
    
   # $update time
   my ($sec,$min,$hour,$mday,$mon,$year,undef,undef,undef) = localtime;
   $hash->{LASTUPDATE} = sprintf "%02d.%02d.%04d / %02d:%02d:%02d" , $mday , $mon+=1 ,$year+=1900 , $hour , $min , $sec ;
  }
}

######################################################################################
###  Summenwerte für GridIn, GridOut speichern

sub setsum ($$$) {
    my ($hash, $gridin_sum, $gridout_sum) = @_;
    my $name     = $hash->{NAME};
    my $success;
    my $index;
    my $retcode;
    my $sumstr;
    
    $sumstr = $gridin_sum."_".$gridout_sum;
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    $retcode = setKeyValue($index, $sumstr);
    
    if ($retcode) { 
        Log3($name, 1, "$name - Error while saving summary of energy values - $retcode");
        $success = 0;
        }
        else
        {
        Log3($name, 4, "$name - summary of energy values saved - GRIDIN_SUM: $gridin_sum, GRIDOUT_SUM: $gridout_sum"); 
        $success = 1;
        }

return ($success);
}

######################################################################################
###  Summenwerte für GridIn, GridOut abtufen

sub getsum ($) {
    my ($hash) = @_;
    my $name     = $hash->{NAME};
    my $success;
    my $index;
    my $retcode;
    my $sumstr;
    my ($gridin_sum, $gridout_sum);
    
    $index = $hash->{TYPE}."_".$hash->{NAME}."_energysum";
    ($retcode, $sumstr) = getKeyValue($index);
    
    if ($retcode) {
        Log3($name, 1, "$name - ERROR -unable to read summary of energy values from file - $retcode");
        $success = 0;
    }  

    if ($sumstr) {
        ($gridin_sum, $gridout_sum) = split(/_/, $sumstr);
        Log3($name, 4, "$name - summary of energy values was read from file - GRIDIN_SUM: $gridin_sum, GRIDOUT_SUM: $gridout_sum"); 
        $success = 1;
    }
    
return ($success, $gridin_sum, $gridout_sum);        
}

######################################################################################

1;



=pod
=begin html

<a name="SMAEM"></a>
<h3>SMAEM</h3>
<ul>
  <br>

  <a name="SMAEM"></a>
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
    "SMAEMserialnooftheEM_.....
    If set to true, the prefix SMA_serialnooftheEM_ is skipped.
    Set this to true if you only have one SMAEM device on your network and you want shorter reading names.
    If unsure, leave it unset.
    <br><br>
    You need the perl module IO::Socket::Multicast. Under Debian (based) systems it can be installed with <code>apt-get install libio-socket-multicast-perl</code>.
  </ul>  

</ul>

=end html

=begin html_DE

<a name="SMAEM"></a>
<h3>SMAEM</h3>
<ul>
  <br>

  <a name="SMAEM"></a>
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
    Der Parameter "disableSernoInReading" ändert die Art und Weise, wie die Readings des SMAEN bezeichnet werden: ist der Parameter false oder nicht gesetzt,
    werden die Readings mit "SMAEMserialnodesEM_....." bezeichnet.
    Wird der Parameter auf true gesetzt, wird das Prefix "SMAEMserialnodesEM_....." weg gelassen.
    Sie können diesen Parameter auf true setzen, wenn Sie nicht mehr als ein SMAEM-Gerät in Ihrem Netzwerk haben und kürzere Namen für die Readings wünschen.
    Falls Sie unsicher sind, setzen Sie diesen Parameter nicht.
    <br><br>
    Sie benötigen das Perl-Module IO::Socket::Multicast für dieses FHEM Modul. Unter Debian (basierten) System, kann dies mittels <code>apt-get install libio-socket-multicast-perl</code> installiert werden. 
  </ul>  

</ul>



=end html_DE


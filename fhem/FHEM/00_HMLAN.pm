##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub HMLAN_Parse($$);
sub HMLAN_Read($);
sub HMLAN_Write($$$);
sub HMLAN_ReadAnswer($$$);
sub HMLAN_uptime($$);
sub HMLAN_secSince2000();

sub HMLAN_SimpleWrite(@);

my $debug = 1; # set 1 for better log readability
my %sets = (
  "hmPairForSec" => "HomeMatic",
  "hmPairSerial" => "HomeMatic",
);

sub HMLAN_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "HMLAN_Read";
  $hash->{WriteFn} = "HMLAN_Write";
  $hash->{ReadyFn} = "HMLAN_Ready";
  $hash->{SetFn}   = "HMLAN_Set";
  $hash->{Clients} = ":CUL_HM:";
  my %mc = (
    "1:CUL_HM" => "^A......................",
  );
  $hash->{MatchList} = \%mc;

# Normal devices
  $hash->{DefFn}   = "HMLAN_Define";
  $hash->{UndefFn} = "HMLAN_Undef";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "loglevel:0,1,2,3,4,5,6 addvaltrigger " . 
                     "hmId hmKey " .
                     "respTime " .
					 "hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger";
}
sub HMLAN_Define($$) {#########################################################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> HMLAN ip[:port]";
    Log 2, $msg;
    return $msg;
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $dev .= ":1000" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "HMLAN_DoInit");
  return $ret;
}
sub HMLAN_Undef($$) {##########################################################
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  DevIo_CloseDev($hash); 
  return undef;
}
sub HMLAN_RemoveHMPair($) {####################################################
  my($in ) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  delete($hash->{hmPair});
}
sub HMLAN_Set($@) {############################################################
  my ($hash, @a) = @_;

  return "\"set HMLAN\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);
  my $ll = GetLogLevel($name,3);
  if($type eq "hmPairForSec") { ####################################
    return "Usage: set $name hmPairForSec <seconds_active>"
        if(!$arg || $arg !~ m/^\d+$/);
    $hash->{hmPair} = 1;
    InternalTimer(gettimeofday()+$arg, "HMLAN_RemoveHMPair", "hmPairForSec:".$hash, 1);

  } 
  elsif($type eq "hmPairSerial") { ################################
    return "Usage: set $name hmPairSerial <10-character-serialnumber>"
        if(!$arg || $arg !~ m/^.{10}$/);

    my $id = AttrVal($hash->{NAME}, "hmId", "123456");
    $hash->{HM_CMDNR} = $hash->{HM_CMDNR} ? ($hash->{HM_CMDNR}+1)%256 : 1;

    HMLAN_Write($hash, undef, sprintf("As15%02X8401%s000000010A%s",
                    $hash->{HM_CMDNR}, $id, unpack('H*', $arg)));
    $hash->{hmPairSerial} = $arg;

  }
  return undef;
}
sub HMLAN_ReadAnswer($$$) {# This is a direct read for commands like get
  my ($hash, $arg, $regexp) = @_;
  my $type = $hash->{TYPE};

  return ("No FD", undef)
        if(!$hash && !defined($hash->{FD}));

  my ($mdata, $rin) = ("", '');
  my $buf;
  my $to = 3;                                         # 3 seconds timeout
  $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
  for(;;) {

    return ("Device lost when reading answer for get $arg", undef)
      if(!$hash->{FD});
    vec($rin, $hash->{FD}, 1) = 1;
    my $nfound = select($rin, undef, undef, $to);
    if($nfound < 0) {
      next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
      my $err = $!;
      DevIo_Disconnected($hash);
      return("HMLAN_ReadAnswer $arg: $err", undef);
    }
    return ("Timeout reading answer for get $arg", undef) if($nfound == 0);
    $buf = DevIo_SimpleRead($hash);# and now read
    return ("No data", undef) if(!defined($buf));

    if($buf) {
      Log 5, "HMLAN/RAW (ReadAnswer): $buf";
      $mdata .= $buf;
    }
    if($mdata =~ m/\r\n/) {
      if($regexp && $mdata !~ m/$regexp/) {
        HMLAN_Parse($hash, $mdata);
      } else {
        return (undef, $mdata);
      }
    }
  }
}

my %lhash; # remember which ID is assigned to this HMLAN

sub HMLAN_Write($$$) {#########################################################
  my ($hash,$fn,$msg) = @_;
  if (length($msg)>22){
    my ($mtype,$src,$dst) = (substr($msg, 8, 2),
                             substr($msg, 10, 6),
	  					     substr($msg, 16, 6));
    my $ll5 = GetLogLevel($hash->{NAME},5);						   
    
    if ($mtype eq "02" && $src eq $hash->{owner} && length($msg) == 24){
      # Acks are generally send by HMLAN autonomously
      # Special 
      Log $ll5, "HMLAN: Skip ACK" if (!$debug);
	  return;
    }
#   my $IDHM  = '+'.$dst.',01,00,F1EF'; #used by HMconfig - meanning??
#   my $IDadd = '+'.$dst;               # guess: add ID?                                     
#   my $IDack = '+'.$dst.',02,00,';     # guess: ID acknowledge
#   my $IDack = '+'.$dst.',FF,00,';     # guess: ID acknowledge
#   my $IDsub = '-'.$dst;               # guess: ID remove?
#   my $IDnew = '+'.$dst.',00,01,';     # newChannel- trailing 01 to be sent if talk to neu channel
    my $IDadd = '+'.$dst.',00,00,';     # guess: add ID?                                     
    
    if (!$lhash{$dst} && $dst ne "000000"){
      HMLAN_SimpleWrite($hash, $IDadd);
	  delete $hash->{helper}{$dst};
	  my $rxt = CUL_HM_Get(CUL_HM_id2Hash($dst),CUL_HM_id2Name($dst),"param","rxType");
	  if (!($rxt & ~0x04)){#config only
	    $hash->{helper}{$dst}{newChn} = '+'.$dst.",01,01,FE1F";
      }
	  else{
	    $hash->{helper}{$dst}{newChn} = '+'.$dst.',00,01,';
	  }
	  $hash->{helper}{$dst}{name} = CUL_HM_id2Name($dst);
      $lhash{$dst} = 1;
      $hash->{assignIDs}=join(',',keys %lhash);
      $hash->{assignIDsCnt}=scalar(keys %lhash);
    }
  }
  my $tm = int(gettimeofday()*1000) % 0xffffffff;
  $msg = sprintf("S%08X,00,00000000,01,%08X,%s",$tm, $tm, substr($msg, 4));
  HMLAN_SimpleWrite($hash, $msg);
}
sub HMLAN_Read($) {############################################################
# called from the global loop, when the select for hash->{FD} reports data
  my ($hash) = @_;
  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  
  my $hmdata = $hash->{PARTIAL};
  Log $ll5, "HMLAN/RAW: $hmdata/$buf" if (!$debug);
  $hmdata .= $buf;

  while($hmdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$hmdata) = split("\n", $hmdata, 2);
    $rmsg =~ s/\r//;
    HMLAN_Parse($hash, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $hmdata;
}
sub HMLAN_uptime($$) {#########################################################
  my ($hash,$msec) = @_;

  $msec = hex($msec);
  my $sec = int($msec/1000);
  
#  my ($sysec, $syusec) = gettimeofday();
#  my $symsec = int($sysec*1000+$syusec/1000);
#  if ($hash->{helper}{refTime} == 1){ #init referenceTime
#    $hash->{helper}{refTime} = 2;
#    $hash->{helper}{refTimeS} = $symsec;
#    $hash->{helper}{refTStmp} = $msec; 
#    $hash->{helper}{msgdly} = $hash->{helper}{msgdlymin} = $hash->{helper}{msgdlymax} = 0; 
#  }
#  elsif ($hash->{helper}{refTime} == 0){ #init referenceTime
#    $hash->{helper}{refTime} = 1;
#  }
#  else{
#    my $dly = ($symsec - $hash->{helper}{refTimeS} ) -
#	          ($msec   - $hash->{helper}{refTStmp});
#    $hash->{helper}{msgdly} = $dly;
#    $hash->{helper}{msgdlymin} = $dly 
#	    if (!$hash->{helper}{msgdlymin} || $hash->{helper}{msgdlymin} > $dly);
#    $hash->{helper}{msgdlymax} = $dly 
#	    if (!$hash->{helper}{msgdlymax} || $hash->{helper}{msgdlymax} < $dly);
#	readingsSingleUpdate($hash,"msgDly","last:".$hash->{helper}{msgdly}
#	                                   ." min:".$hash->{helper}{msgdlymin}
#	                                   ." max:".$hash->{helper}{msgdlymax},0);
#  }
  return sprintf("%03d %02d:%02d:%02d.%03d",
                  int($msec/86400000), int($sec/3600),
                  int(($sec%3600)/60), $sec%60, $msec % 1000);
}
sub HMLAN_Parse($$) {##########################################################
  my ($hash, $rmsg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my @mFld = split(',', $rmsg);
  my $letter = substr($mFld[0],0,1); # get leading char
  
  if ($letter =~ m/^[ER]/){#@mFld=($src, $status, $msec, $d2, $rssi, $msg)
    # max speed for devices is 100ms after receive - example:TC

    my $stat = hex($mFld[1]);
	my ($mNo,$flg,$type,$src,$dst) = ($1,$2,$3,$4,$5)# Std Header
	                  if ($mFld[5] =~ m/^(..)(..)(..)(.{6})(.{6})/);
	my $p = substr($mFld[5],18);                     # additional content
    my $rssi = hex($mFld[4])-65536;

    Log $ll5, "HMLAN_Parse: $name R:".$mFld[0]
	                               .(($mFld[0] =~ m/^E/)?'  ':'')
	                               .' stat:' .$mFld[1]
	                               .' t:'    .$mFld[2]
								   .' d:'    .$mFld[3]
								   .' r:'    .$mFld[4] 
                                   .'     m:'.$mNo
                                   .' '.$flg.$type
                                   .' '.$src
                                   .' '.$dst
                                   .' '.$p;
								  
    # handle status. 
	#    00 00= msg without relation
	#    00 01= ack that HMLAN waited for
	#    00 02= msg send, no ack was requested
	#    00 08= nack - ack was requested, msg repeated 3 times, still no ack
	#    00 21= (seen with 'R')
	#    00 30=
	#    00 41= (seen with 'R')
	#    00 50= (seen with 'R')
	#    00 81= open
	#    01 xx= (seen with 'E')
	#    02 xx= prestate to 04xx. 
	#    04 xx= nothing sent anymore. Any restart unsuccessful except power
	# 
    # HMLAN_SimpleWrite($hash, '+'.$src) if (($letter eq 'R') && $src ne AttrVal($name, "hmId", $mFld[4]));
    # 
    # if (!($flg & 0x25)){#rule out other messages 
	#  HMLAN_SimpleWrite($hash, '-'.$src);
	#  HMLAN_SimpleWrite($hash, '+'.$src);
	# }
	if($stat & 0x040A){ # do not parse this message, no valid content
	  Log $ll5, "HMLAN_Parse: $name problems detected - please restart HMLAN"if($stat & 0x0400);
	  Log $ll5, "HMLAN_Parse: $name discard"                                 if($stat & 0x000A);
	  return ;# message with no ack is send - do not dispatch
	}
	if ($mFld[1] !~ m/00(01|02|21|41|50)/ && $letter eq 'R'){
      Log $ll5, "HMLAN_Parse: $name discard, NACK state:".$mFld[1];
	  $hash->{helper}{$dst}{flg} = 0;#NACK is also a response, continue process
	  return;
	}
    Log $ll5, "HMLAN_Parse: $name special reply ".$mFld[1]        if($stat & 0x0200);

	# HMLAN sends ACK for flag 'A0' but not for 'A4'(config mode)- 
	# we ack ourself an long as logic is uncertain - also possible is 'A6' for RHS
	if (hex($flg)&0x4){#not sure: 4 oder 2 ? 
	  $hash->{helper}{nextSend}{$src} = gettimeofday() + 0.100;
	}
	if (hex($flg)&0xA4 == 0xA4 && $hash->{owner} eq $dst){
	  Log $ll5, "HMLAN_Parse: $name ACK config";
	  HMLAN_Write($hash,undef, "As15".$mNo."8002".$dst.$src."00");
	}
     #update some User information ------
	$hash->{uptime} = HMLAN_uptime($hash,$mFld[2]);
	$hash->{RSSI}   = $rssi;
    $hash->{RAWMSG} = $rmsg;
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
	
    if ($letter eq 'R' && $hash->{helper}{$src}{flg}){
	  $hash->{helper}{$src}{flg} = 0;                 #release send-holdoff
	  if ($hash->{helper}{$src}{msg}){                #send delayed msg if any
	    Log $ll5,"HMLAN_SdDly: $name $src ".$hash->{helper}{$src}{msg};
		HMLAN_SimpleWrite($hash, $hash->{helper}{$src}{msg});
	  }
	  $hash->{helper}{$src}{msg} = "";                #clear message
	}
	# prepare dispatch-----------
    # HM format A<len><msg>:<info>:<RSSI>:<IOname>  Info is not used anymore
    my $dmsg = sprintf("A%02X%s::", length($mFld[5])/2, uc($mFld[5]))
	          .$rssi                 #RSSI
			  .":".$name;            #add sender Name
    my %addvals = (RAWMSG => $rmsg, RSSI => hex($mFld[4])-65536);
    Dispatch($hash, $dmsg, \%addvals);
  }
  elsif($mFld[0] eq 'HHM-LAN-IF'){#@mFld=(undef,$vers,$serno,$d1,$owner,$msec,$d2)
    $hash->{serialNr} = $mFld[2];
    $hash->{firmware} = sprintf("%d.%d", (hex($mFld[1])>>12)&0xf, hex($mFld[1]) & 0xffff);
    $hash->{owner} = $mFld[4];
    $hash->{uptime} = HMLAN_uptime($hash,$mFld[5]);
   	$hash->{assignIDsReport}=$mFld[6];
    $hash->{helper}{keepAliveRec} = 1;
    $hash->{helper}{keepAliveRpt} = 0;
    Log $ll5, 'HMLAN_Parse: '.$name.                 ' V:'.$mFld[1]
	                               .' sNo:'.$mFld[2].' d:'.$mFld[3]
								   .' O:'  .$mFld[4].' t:'.$mFld[5].' IDcnt:'.$mFld[6];
    my $myId = AttrVal($name, "hmId", "");
	$myId = $attr{$name}{hmId} = $mFld[4] if (!$myId);
	
    if($mFld[4] ne $myId && !AttrVal($name, "dummy", 0)) {
      Log 1, 'HMLAN setting owner to '.$myId.' from '.$mFld[4];
      HMLAN_SimpleWrite($hash, "A$myId");
    }
  }
  elsif($rmsg =~ m/^I00.*/) {;
    # Ack from the HMLAN
  } 
  else {
    Log $ll5, "$name Unknown msg >$rmsg<";
  }
}
sub HMLAN_Ready($) {###########################################################
  my ($hash) = @_;
  return DevIo_OpenDev($hash, 1, "HMLAN_DoInit");
}
sub HMLAN_SimpleWrite(@) {#####################################################
  my ($hash, $msg, $nonl) = @_;

  return if(!$hash || AttrVal($hash->{NAME}, "dummy", undef));
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my $len = length($msg);
  
  # It is not possible to answer befor 100ms

  if ($len>51){
    my $dst = substr($msg,46,6);
    if ($hash->{helper}{nextSend}{$dst}){
      my $DevDelay = $hash->{helper}{nextSend}{$dst} - gettimeofday();
      select(undef, undef, undef, (($DevDelay > 0.1)?0.1:$DevDelay))
	        if ($DevDelay > 0.01);
	  delete $hash->{helper}{nextSend}{$dst};
    }
    $msg =~ m/(.{9}).(..).(.{8}).(..).(.{8}).(..)(....)(.{6})(.{6})(.*)/;
	Log $ll5, 'HMLAN_Send:  '.$name.' S:'.$1
                             .' stat:  ' .$2
                             .' t:'      .$3
                             .' d:'      .$4
                             .' r:'      .$5 
                             .' m:'      .$6
                             .' '        .$7 
                             .' '        .$8
                             .' '        .$9
                             .' '        .$10;
	if ($dst ne $attr{$name}{hmId}){  #delay send if answer is pending
	  if ( $hash->{helper}{$dst}{flg} &&                #HMLAN's ack pending
          ($hash->{helper}{$dst}{to} > gettimeofday())){#won't wait forever!
	    $hash->{helper}{$dst}{msg} = $msg;              #postpone  message
	    Log $ll5,"HMLAN_Delay: $name msg delayed $dst $msg";
	    return;
	  }
      my $flg = substr($msg,36,2);
	  $hash->{helper}{$dst}{flg} = (hex($flg)&0x20)?1:0;
      $hash->{helper}{$dst}{to} = gettimeofday() + 2;# flag timeout after 2 sec
	  $hash->{helper}{$dst}{msg} = "";
	}
    if ($len > 52){#channel information included, send sone kind of clearance
	  my $chn = substr($msg,52,2);
	  if ($hash->{helper}{$dst}{chn} && $hash->{helper}{$dst}{chn} ne $chn){
	    my $updt = $hash->{helper}{$dst}{newChn};
        Log $ll5, 'HMLAN_Send:  '.$name.' S:'.$updt; 
	    syswrite($hash->{TCPDev}, $updt."\r\n")     if($hash->{TCPDev});
	  }
	  $hash->{helper}{$dst}{chn} = $chn;
	} 
  }
  else{
    Log $ll5, 'HMLAN_Send:  '.$name.' I:'.$msg; 
  }
  
  $msg .= "\r\n" unless($nonl);
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});
}
sub HMLAN_DoInit($) {##########################################################
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $id  = AttrVal($name, "hmId", undef);
  my $key = AttrVal($name, "hmKey", "");        # 36(!) hex digits

  my $s2000 = sprintf("%02X", HMLAN_secSince2000());

  HMLAN_SimpleWrite($hash, "A$id") if($id);
  HMLAN_SimpleWrite($hash, "C");
  HMLAN_SimpleWrite($hash, "Y01,01,$key");
  HMLAN_SimpleWrite($hash, "Y02,00,");
  HMLAN_SimpleWrite($hash, "Y03,00,");
  HMLAN_SimpleWrite($hash, "Y03,00,");
  HMLAN_SimpleWrite($hash, "T$s2000,04,00,00000000");
 
  $hash->{helper}{refTime}=0;
  
  foreach (keys %lhash){delete ($lhash{$_})};# clear IDs - HMLAN might have a reset 
  $hash->{helper}{keepAliveRec} = 1; # ok for first time
  $hash->{helper}{keepAliveRpt} = 0; # ok for first time
  RemoveInternalTimer( "keepAliveCk:".$name);# avoid duplicate timer
  RemoveInternalTimer( "keepAlive:".$name);# avoid duplicate timer
  InternalTimer(gettimeofday()+25, "HMLAN_KeepAlive", "keepAlive:".$name, 0);
  return undef;
}
sub HMLAN_KeepAlive($) {#######################################################
  my($in ) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  $hash->{helper}{keepAliveRec} = 0; # reset indicator

  return if(!$hash->{FD});
  HMLAN_SimpleWrite($hash, "K");
  RemoveInternalTimer( "keepAlive:".$name);# avoid duplicate timer
  my $rt = AttrVal($name,"respTime",1);
  InternalTimer(gettimeofday()+$rt,"HMLAN_KeepAliveCheck","keepAliveCk:".$name,1);
  InternalTimer(gettimeofday()+25 ,"HMLAN_KeepAlive", "keepAlive:".$name, 1);
}
sub HMLAN_KeepAliveCheck($) {##################################################
  my($in ) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  if ($hash->{helper}{keepAliveRec} != 1){# no answer
    if ($hash->{helper}{keepAliveRpt} >2){# give up here
      DevIo_Disconnected($hash);
    }
    else{
      $hash->{helper}{keepAliveRpt}++;
	  HMLAN_KeepAlive("keepAlive:".$name);#repeat
    }
  }
  else{
    $hash->{helper}{keepAliveRpt}=0;
  }

}
sub HMLAN_secSince2000() {#####################################################
  # Calculate the local time in seconds from 2000.
  my $t = time();
  my @l = localtime($t);
  my @g = gmtime($t);
  $t += 60*(($l[2]-$g[2] + ((($l[5]<<9)|$l[7]) <=> (($g[5]<<9)|$g[7])) * 24) * 60 + $l[1]-$g[1]) 
                           # timezone and daylight saving...
        - 946684800        # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
        - 7200;            # HM Special
  return $t;
}

1;

=pod
=begin html

<a name="HMLAN"></a>
<h3>HMLAN</h3>
<ul>
  <tr><td>
  The HMLAN is the fhem module for the eQ-3 HomeMatic LAN Configurator.
  <br><br>
  The fhem module will emulate a CUL device, so the <a href="#CUL_HM">CUL_HM</a>
  module can be used to define HomeMatic devices.<br><br>

  In order to use it with fhem you <b>must</b> disable the encryption first
  with the "HomeMatic Lan Interface Configurator" (which is part of the
  supplied Windows software), by selecting the device, "Change IP Settings",
  and deselect "AES Encrypt Lan Communication".<br><br>
  This device can be used in parallel with a CCU and (readonly) with fhem. To do this:
  <ul>
    <li>start the fhem/contrib/tcptee.pl program
    <li>redirect the CCU to the local host
    <li>disable the LAN-Encryption on the CCU for the Lan configurator
    <li>set the dummy attribute for the HMLAN device in fhem
  </ul>
  <br><br>





  <a name="HMLANdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HMLAN &lt;ip-address&gt;[:port]</code><br>
    <br>
    port is 1000 by default.
    If the ip-address is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>
  </ul>
  <br>

  <a name="HMLANset"></a>
  <b>Set</b>
  <ul>
    <li><a href="#hmPairForSec">hmPairForSec</a>
    <li><a href="#hmPairSerial">hmPairSerial</a>
  </ul>
  <br>

  <a name="HMLANget"></a>
  <b>Get</b>
  <ul>
  N/A
  </ul>
  <br>
  <br>

  <a name="HMLANattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#loglevel">loglevel</a></li><br>
    <li><a href="#addvaltrigger">addvaltrigger</a></li><br>
    <li><a href="#hmId">hmId</a></li><br>
    <li><a href="#hmProtocolEvents">hmProtocolEvents</a></li><br>
    <li><a href="#respTime">respTime</a><br>
	 Define max response time of the HMLAN adapter in seconds. Default is 1 sec. 
	 Longer times may be used as workaround in slow/instable systems or LAN configurations.
	</li>
  </ul>
</ul>

=end html
=cut

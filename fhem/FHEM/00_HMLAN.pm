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
sub HMLAN_uptime($);
sub HMLAN_secSince2000();

sub HMLAN_SimpleWrite(@);

my %sets = (
  "hmPairForSec" => "HomeMatic",
  "hmPairSerial" => "HomeMatic",
);

sub
HMLAN_Initialize($)
{
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
					 "hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger";
}

#####################################
sub
HMLAN_Define($$)
{
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
  $attr{$name}{hmId} = sprintf("%06X", time() % 0xffffff); # Will be overwritten

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $hash->{DeviceName} = $dev;
  $hash->{helper}{nextSend}=gettimeofday();
  my $ret = DevIo_OpenDev($hash, 0, "HMLAN_DoInit");
  return $ret;
}


#####################################
sub
HMLAN_Undef($$)
{
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

#####################################
sub
HMLAN_RemoveHMPair($)
{
  my $hash = shift;
  delete($hash->{hmPair});
}


#####################################
sub
HMLAN_Set($@)
{
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
    InternalTimer(gettimeofday()+$arg, "HMLAN_RemoveHMPair", $hash, 1);

  } elsif($type eq "hmPairSerial") { ################################
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


#####################################
# This is a direct read for commands like get
sub
HMLAN_ReadAnswer($$$)
{
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
    return ("Timeout reading answer for get $arg", undef)
      if($nfound == 0);
    $buf = DevIo_SimpleRead($hash);
    return ("No data", undef) if(!defined($buf));

    if($buf) {
      Log 5, "HMLAN/RAW (ReadAnswer): $buf";
      $mdata .= $buf;
    }
    if($mdata =~ m/\r\n/) {
      if($regexp && $mdata !~ m/$regexp/) {
        HMLAN_Parse($hash, $mdata);
      } else {
        return (undef, $mdata)
      }
    }
  }
}

my %lhash;

#####################################
sub
HMLAN_Write($$$)
{
  my ($hash,$fn,$msg) = @_;
  my ($mtype,$src,$dst) = (substr($msg, 8, 2),
                           substr($msg, 10, 6),
						   substr($msg, 16, 6));

	if ($mtype eq "02" && $src eq $hash->{owner}){
                                  # Acks are generally send by HMLAN
                                  # So far there is no need to send own
    Log 5, "HMLAN: Skip ACK";
	return;
  }
  
#  my $IDHM  = '+'.$dst.',01,00,F1EF'; #used by HMconfig - meanning??
  my $IDadd = '+'.$dst.',00,00,';     # guess: add ID?                                     
  my $IDsub = '-'.$dst;               # guess: ID remove?
#  my $IDact = '+'.$dst;               # guess: ID recover? Different to IDadd?
#  my $IDack = '+'.$dst.',02,00,';     # guess: ID acknowledge
    
  HMLAN_SimpleWrite($hash, $IDadd) if (!$lhash{$dst});
  $lhash{$dst} = 1;
   
  if(hex(substr($msg, 6, 2))&0x01){   # wakeup sequence for TC... hmmm
    HMLAN_SimpleWrite($hash, $IDadd);
    HMLAN_SimpleWrite($hash, $IDadd);
    HMLAN_SimpleWrite($hash, $IDadd);
    HMLAN_SimpleWrite($hash, $IDsub);
    HMLAN_SimpleWrite($hash, $IDadd);
    HMLAN_SimpleWrite($hash, $IDadd);
    HMLAN_SimpleWrite($hash, $IDadd);
    HMLAN_SimpleWrite($hash, $IDadd);
    #HMLAN_SimpleWrite($hash, "+$dst,01,00,F1EF\x0d\x0a");
  }
  my $tm = int(gettimeofday()*1000) % 0xffffffff;
  $msg = sprintf("S%08X,00,00000000,01,%08X,%s",$tm, $tm, substr($msg, 4));
  HMLAN_SimpleWrite($hash, $msg);

  # Avoid problems with structure set
  # TODO: rewrite it to use a queue+internaltimer like the CUL
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
HMLAN_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};

  my $hmdata = $hash->{PARTIAL};
#  Log 5, "HMLAN/RAW: $hmdata/$buf";
  $hmdata .= $buf;

  while($hmdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$hmdata) = split("\n", $hmdata, 2);
    $rmsg =~ s/\r//;
    HMLAN_Parse($hash, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $hmdata;
}

sub
HMLAN_uptime($)
{
  my $msec = shift;

  $msec = hex($msec);
  my $sec = int($msec/1000);
  return sprintf("%03d %02d:%02d:%02d.%03d",
                  int($msec/86400000), int($sec/3600),
                  int(($sec%3600)/60), $sec%60, $msec % 1000);
}

sub
HMLAN_Parse($$)
{
  my ($hash, $rmsg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my @mFld = split(',', $rmsg);
  my $letter = substr($mFld[0],0,1); # get leading char
  
  if ($letter =~ m/^[ER]/){#@mFld=($src, $status, $msec, $d2, $rssi, $msg)
    Log $ll5, 'HMLAN_Parse: '.$name.' S:'.$mFld[0]
	                               .(($mFld[0] =~ m/^E/)?'  ':'')
	                               .' stat:'.$mFld[1]
	                               .' t:'.$mFld[2].' d:'.$mFld[3]
								   .' r:'.$mFld[4] 
 								   .'m:'.$mFld[5];
#                                   .'     m:'.substr($mFld[5],0,2)
#                                   .' '.substr($mFld[5],2,4)
#                                   .' '.substr($mFld[5],6,6)
#                                   .' '.substr($mFld[5],12,6)
#                                   .' '.substr($mFld[5],18);
								  
    my $dmsg = sprintf("A%02X%s", length($mFld[5])/2, uc($mFld[5]));
	
	my $src = substr($mFld[5],6,6);
	my $dst = substr($mFld[5],12,6);
	my $flg = hex(substr($mFld[5],2,2));
	
    # handle status. 01=ack:seems to announce the new message counter
	#                02=our send message returned it was likely not sent
	#                08=nack,
	#                21=?,
	#                81=open
    HMLAN_SimpleWrite($hash, '+'.$src) if (($letter eq 'R'));

    if (!($flg & 0x25)){#rule out other messages 
	  HMLAN_SimpleWrite($hash, '-'.$src);
	  HMLAN_SimpleWrite($hash, '+'.$src);
	}
    $dmsg .= "NACK" if($mFld[1] !~ m/00(01|02|21)/ && $letter eq 'R');	

    $hash->{uptime} = HMLAN_uptime($mFld[2]);
	$hash->{RSSI}   = hex($mFld[4])-65536;
    $hash->{RAWMSG} = $rmsg;
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();
    my %addvals = (RAWMSG => $rmsg, RSSI => hex($mFld[4])-65536);
    Dispatch($hash, $dmsg, \%addvals);
  }
  elsif($mFld[0] eq 'HHM-LAN-IF'){#@mFld=(undef,$vers,$serno,$d1,$owner,$msec,$d2)
    $hash->{serialNr} = $mFld[2];
    $hash->{firmware} = sprintf("%d.%d", (hex($mFld[1])>>12)&0xf, hex($mFld[1]) & 0xffff);
    $hash->{owner} = $mFld[4];
    $hash->{uptime} = HMLAN_uptime($mFld[5]);
    Log $ll5, 'HMLAN_Parse: '.$name.                 ' V:'.$mFld[1]
	                               .' sNo:'.$mFld[2].' d:'.$mFld[3]
								   .' O:'  .$mFld[4].' m:'.$mFld[5].' d2:'.$mFld[6];
    my $myId = AttrVal($name, "hmId", $mFld[4]);
    if(lc($mFld[4]) ne lc($myId) && !AttrVal($name, "dummy", 0)) {
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


#####################################
sub
HMLAN_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "HMLAN_DoInit");
}

########################
sub
HMLAN_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  my $name = $hash->{NAME};
  return if(!$hash || AttrVal($hash->{NAME}, "dummy", undef));

#  select(undef, undef, undef, 0.01); #  todo check necessity
#---------- confort trace--------------
# Log GetLogLevel($name,5), 'HMLAN_Send:         S:'.
#                                       substr($msg,0,9).
#
#                           ' stat:  '.substr($msg,10,2).
#                           ' t:'      .substr($msg,13,8).
#                           ' d:'      .substr($msg,22,2).
#                           ' r:'      .substr($msg,25,8).
# 							 ' m:'      .substr($msg,34)
#
#                           ' m:'      .substr($msg,34,2).
#                           ' '        .substr($msg,36,4). 
#                           ' '        .substr($msg,40,6).
#                           ' '        .substr($msg,46,6). 
#                           ' '        .substr($msg,52)     
#
#							if (length($msg )>19);
# Log GetLogLevel($name,5), 'HMLAN_Send:  '.$msg     if (length($msg) <=19); 
#----------- normal trace,better speed-----------
  Log GetLogLevel($name,5), 'HMLAN_Send:  '.$msg; #normal trace
  
  $msg .= "\r\n" unless($nonl);
  
  # Currently it does  not seem to be necessary to wait Thus this code is inhibit for now
  for (my$cnt=0;$cnt<10;$cnt++){ #  no more then 10 itterations!!! fault save
    last if ($hash->{helper}{nextSend} <gettimeofday());
	select(undef, undef, undef, 0.01);
  }
  
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});
  $hash->{helper}{nextSend} = gettimeofday() + 0.01; # experimental value. 
}

########################
sub
HMLAN_DoInit($)
{
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

  InternalTimer(gettimeofday()+25, "HMLAN_KeepAlive", $hash, 0);
  return undef;
}

#####################################
sub
HMLAN_KeepAlive($)
{
  my $hash = shift;
  return if(!$hash->{FD});
  HMLAN_SimpleWrite($hash, "K");
  InternalTimer(gettimeofday()+25, "HMLAN_KeepAlive", $hash, 1);
}

sub
HMLAN_secSince2000()
{
  # Calculate the local time in seconds from 2000.
  my $t = time();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
  $t -= 946684800; # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
  $t -= 7200;   # HM Special
  $t += fhemTzOffset($t);
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
  </ul>
</ul>

=end html
=cut

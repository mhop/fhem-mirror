##############################################
# $Id$
package main;


use strict;
use warnings;
use Time::HiRes qw(gettimeofday time);
use Digest::MD5 qw(md5);

sub HMLAN_Initialize($);
sub HMLAN_Define($$);
sub HMLAN_Undef($$);
sub HMLAN_RemoveHMPair($);
sub HMLAN_Attr(@);
sub HMLAN_Set($@);
sub HMLAN_ReadAnswer($$$);
sub HMLAN_Write($$$);
sub HMLAN_Read($);
sub HMLAN_uptime($@);
sub HMLAN_Parse($$);
sub HMLAN_Ready($);
sub HMLAN_SimpleWrite(@);
sub HMLAN_DoInit($);
sub HMLAN_KeepAlive($);
sub HMLAN_secSince2000();
sub HMLAN_relOvrLd($);
sub HMLAN_condUpdate($$);

my $debug = 1; # set 1 for better log readability
my %sets = ( "hmPairForSec" => "HomeMatic"
            ,"hmPairSerial" => "HomeMatic"
);
my %HMcond = ( 0  =>'ok'
              ,2  =>'Warning-HighLoad'
              ,4  =>'ERROR-Overload'
              ,252=>'timeout'
              ,253=>'disconnected'
              ,254=>'Overload-released'
              ,255=>'init');

#my %HM STATE= (  =>'opened'
#                 =>'disconnected'
#                 =>'overload');

my $HMOvLdRcvr = 6*60;# time HMLAN needs to recover from overload
my $HMmlSlice = 6; # number of messageload slices per hour (10 = 6min)

sub HMLAN_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "HMLAN_Read";
  $hash->{WriteFn} = "HMLAN_Write";
  $hash->{ReadyFn} = "HMLAN_Ready";
  $hash->{SetFn}   = "HMLAN_Set";
  $hash->{NotifyFn}= "HMLAN_Notify";
  $hash->{AttrFn}  = "HMLAN_Attr";
  $hash->{Clients} = ":CUL_HM:";
  my %mc = (
    "1:CUL_HM" => "^A......................",
  );
  $hash->{MatchList} = \%mc;

# Normal devices
  $hash->{DefFn}   = "HMLAN_Define";
  $hash->{UndefFn} = "HMLAN_Undef";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "addvaltrigger " .
                     "hmId hmKey hmKey2 hmKey3 " .
                     "respTime " .
                     "hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger ".
                     "hmMsgLowLimit ".
                     "hmLanQlen:1_min,2_low,3_normal,4_high,5_critical ".
                     "wdTimer:5,10,15,20,25 ".
                     "logIDs ".
                     $readingFnAttributes;
}
sub HMLAN_Define($$) {#########################################################
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> HMLAN ip[:port]";
    Log3 $hash, 2, $msg;
    return $msg;
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $dev .= ":1000" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);

  if($dev eq "none") {
    Log3 $hash, 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $attr{$name}{hmLanQlen} = "1_min"; #max message queue length in HMLan

  no warnings 'numeric';
  $hash->{helper}{q}{hmLanQlen} = int($attr{$name}{hmLanQlen})+0;
  use warnings 'numeric';
  $hash->{DeviceName} = $dev;
  $hash->{msgKeepAlive} = "";   # delay of trigger Alive messages
  $hash->{helper}{k}{DlyMax} = 0;
  $hash->{helper}{k}{BufMin} = 30;

  $hash->{helper}{q}{answerPend} = 0;#pending answers from LANIf
  my @arr = ();
  @{$hash->{helper}{q}{apIDs}} = \@arr;

  $hash->{helper}{q}{cap}{$_}   = 0 for (0..($HMmlSlice-1));
  $hash->{helper}{q}{cap}{last} = 0;
  $hash->{helper}{q}{cap}{sum}  = 0;
  HMLAN_UpdtMsgCnt("UpdtMsg:".$name);
  $defs{$name}{helper}{log}{all} = 0;# selective log support
  $defs{$name}{helper}{log}{sys} = 0;
  my @al = ();
  @{$defs{$name}{helper}{log}{ids}} = \@al;

  HMLAN_condUpdate($hash,253);#set disconnected
  $hash->{STATE} = "disconnected";

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
        Log3 $hash, 2, "deleting port for $d";
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
sub HMLAN_Notify(@) {##########################################################
  my ($hash,$dev) = @_;
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED$/,@{$dev->{CHANGED}})){
    if ($hash->{helper}{attrPend}){
      my $aVal = AttrVal($hash->{NAME},"logIDs","");
      HMLAN_Attr("set",$hash->{NAME},"logIDs",$aVal) if($aVal);
      delete $hash->{helper}{attrPend};
    }
  }
  elsif ($dev->{NAME} eq $hash->{NAME}){
    foreach (grep (m/CONNECTED$/,@{$dev->{CHANGED}})) { # connect/disconnect
      if    ($_ eq "DISCONNECTED") {HMLAN_condUpdate($hash,253);}
#      elsif ($_ eq "CONNECTED")    {covered by init;}
    }
  }
  return;
}
sub HMLAN_Attr(@) {############################################################
  my ($cmd,$name, $aName,$aVal) = @_;
  if   ($aName eq "wdTimer" && $cmd eq "set"){#allow between 5 and 25 second
    return "select wdTimer between 5 and 25 seconds" if ($aVal>30 || $aVal<5);
    $attr{$name}{wdTimer} = $aVal;
    $defs{$name}{helper}{k}{Start} = 0;
   }
  elsif($aName eq "hmLanQlen"){
    if ($cmd eq "set"){
      no warnings 'numeric';
      $defs{$name}{helper}{q}{hmLanQlen} = int($aVal)+0;
      use warnings 'numeric';
    }
    else{
      $defs{$name}{helper}{q}{hmLanQlen} = 1;
    }
  }
  elsif($aName =~ m /^hmKey/){
    my $retVal= "";
    if ($cmd eq "set"){
      my $kno = ($aName eq "hmKey")?1:substr($aName,5,1);
      my ($no,$val) = (sprintf("%02X",$kno),$aVal);
      if ($aVal =~ m/:/){#number given
        ($no,$val) = split ":",$aVal;
        return "illegal number:$no" if (hex($no) < 1 || hex($no) > 255 || length($no) != 2);
      }
      $attr{$name}{$aName} = "$no:".
                               (($val =~ m /^[0-9A-Fa-f]{32}$/ )?
                                 $val:
                                   unpack('H*', md5($val)));
      $retVal = "$aName set to $attr{$name}{$aName}";
    }
    else{
      delete $attr{$name}{$aName};
    }
    my ($k1no,$k1,$k2no,$k2,$k3no,$k3)
         =( "01",AttrVal($name,"hmKey","")
           ,"02",AttrVal($name,"hmKey2","")
           ,"03",AttrVal($name,"hmKey3","")
                       );

    if ($k1 =~ m/:/){($k1no,$k1) = split(":",$k1);}
    if ($k2 =~ m/:/){($k2no,$k2) = split(":",$k2);}
    if ($k3 =~ m/:/){($k3no,$k3) = split(":",$k3);}

    HMLAN_SimpleWrite($defs{$name}, "Y01,".($k1?"$k1no,$k1":"00,"));
    HMLAN_SimpleWrite($defs{$name}, "Y02,".($k2?"$k2no,$k2":"00,"));
    HMLAN_SimpleWrite($defs{$name}, "Y03,".($k3?"$k3no,$k3":"00,"));
    return $retVal;
  }
  elsif($aName eq "hmMsgLowLimit"){
    if ($cmd eq "set"){
      return "hmMsgLowLimit:please add integer between 10 and 120"
          if (  $aVal !~ m/^(\d+)$/
              ||$aVal<10
              ||$aVal >120 );
    }
  }
  elsif($aName eq "hmId"){
    if ($cmd eq "set"){
      return "wrong syntax: hmId must be 6-digit-hex-code (3 byte)"
        if ($aVal !~ m/^[A-F0-9]{6}$/i);
    }
  }
  elsif($aName eq "logIDs"){
    if ($cmd eq "set"){
      if ($init_done){
        my @ids = split",",$aVal;
        my @idName;
        if (grep /sys/,@ids){
          push @idName,"sys";
          $defs{$name}{helper}{log}{sys}=1;
        }
        else{
          $defs{$name}{helper}{log}{sys}=0;
        }
        if (grep /all/,@ids){
          push @idName,"all";
          $defs{$name}{helper}{log}{all}=1;
        }
        else{
          $defs{$name}{helper}{log}{all}=0;
          $_=substr(CUL_HM_name2Id($_),0,6) foreach(grep !/^$/,@ids);
          $_="" foreach(grep !/^[A-F0-9]{6}$/,@ids);
          @ids = HMLAN_noDup(@ids);
          push @idName,CUL_HM_id2Name($_) foreach(@ids);
        }
        $attr{$name}{$aName} = join(",",@idName);
        @{$defs{$name}{helper}{log}{ids}}=@ids;
      }
      else{
        $defs{$name}{helper}{attrPend} = 1;
        return;
      }
    }
    else{
      my @ids = ();
      $defs{$name}{helper}{log}{sys}=0;
      $defs{$name}{helper}{log}{all}=0;
      @{$defs{$name}{helper}{log}{ids}}=@ids;
    }
    return "logging set to $attr{$name}{$aName}"
        if ($attr{$name}{$aName} ne $aVal);
  }
  return;
}

sub HMLAN_UpdtMsgCnt($) {######################################################
  # update HMLAN capacity counter
  # HMLAN will raise high-load after ~610 msgs per hour
  #                  overload with send-stop after 670 msgs
  # this count is an approximation and best guess - nevertheless it cannot
  # read the real values of HMLAN that might persist e.g. after FHEM reboot
  my($in ) = shift;
  my(undef,$name) = split(':',$in);

  HMLAN_UpdtMsgLoad($name,0);
  InternalTimer(gettimeofday()+100, "HMLAN_UpdtMsgCnt", "UpdtMsg:".$name, 0);
  return;
}
sub HMLAN_UpdtMsgLoad($$) {####################################################
  my($name,$incr) = @_;
  my $hash = $defs{$name};
  my $hCap = $hash->{helper}{q}{cap};

  my $t = int(gettimeofday()/(3600/$HMmlSlice))%$HMmlSlice;
  if ($hCap->{last} != $t){
    $hCap->{last} = $t;
    $hCap->{$t} = 0;
       # try to release high-load condition with a dummy message
       # one a while
    if (ReadingsVal($name,"cond","") =~ m /(Warning-HighLoad|ERROR-Overload)/){
      $hash->{helper}{recoverTest} = 1;
      HMLAN_Write($hash,"","As09998112"
                         .AttrVal($name,"hmId","999999")
                         ."000001");
    }
  }
  $hCap->{$hCap->{last}}+=$incr  if ($incr);
  my @tl;
  $hCap->{sum} = 0;
  for (($t-$HMmlSlice+1)..$t){# we have 6 slices
    push @tl,int($hCap->{$_%$HMmlSlice}/16.8);
    $hCap->{sum} += $hCap->{$_%$HMmlSlice}; # need to recalc incase a slice was removed
  }

  $hash->{msgLoadEst} = "1hour:".int($hCap->{sum}/16.8)."% "
                        .(60/$HMmlSlice)."min steps: ".join("/",reverse @tl);
#testing only           ." :".$hCap->{sum}
  return;
}

sub HMLAN_Set($@) {############################################################
  my ($hash, @a) = @_;

  return "\"set HMLAN\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
      if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);
  if($type eq "hmPairForSec") { ####################################
    return "Usage: set $name hmPairForSec <seconds_active>"
        if(!$arg || $arg !~ m/^\d+$/);
    $hash->{hmPair} = 1;
    InternalTimer(gettimeofday()+$arg, "HMLAN_RemoveHMPair", "hmPairForSec:".$name, 1);
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
  return ("",1);# no not generate trigger outof command
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
      HMLAN_condUpdate($hash,253);
      return("HMLAN_ReadAnswer $arg: $err", undef);
    }
    return ("Timeout reading answer for get $arg", undef) if($nfound == 0);
    $buf = DevIo_SimpleRead($hash);# and now read
    return ("No data", undef) if(!defined($buf));

    if($buf) {
      Log3 $hash, 5, "HMLAN/RAW (ReadAnswer): $buf";
      $mdata .= $buf;
    }
    if($mdata =~ m/\r\n/) {
      if($regexp && $mdata !~ m/$regexp/) {
        HMLAN_Parse($hash, $mdata);
      }
      else {
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

    if (   $mtype eq "02" && $src eq $hash->{owner} && length($msg) == 24
        && $hash->{assignIDs} =~ m/$dst/){
      # Acks are generally send by HMLAN autonomously
      # Special
      Log3 $hash, 5, "HMLAN: Skip ACK" if (!$debug);
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
#     delete $hash->{helper}{$dst};
      my $dN = CUL_HM_id2Name($dst);
      if (!($dN eq $dst) &&  # name not found
          !(CUL_HM_Get(CUL_HM_id2Hash($dst),$dN,"param","rxType") & ~0x04)){#config only
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

  my $hmdata = $hash->{PARTIAL};
  Log3 $hash, 5, "HMLAN/RAW: $hmdata/$buf" if (!$debug);
  $hmdata .= $buf;

  while($hmdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$hmdata) = split("\n", $hmdata, 2);
    $rmsg =~ s/\r//;
    HMLAN_Parse($hash, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $hmdata;
}
sub HMLAN_uptime($@) {#########################################################
  my ($hmtC,$hash) = @_;  # hmTime Current

  $hmtC = hex($hmtC);

  if ($hash && $hash->{helper}{ref}){ #will calculate new ref-time
    my $ref = $hash->{helper}{ref};#shortcut
    my $sysC = int(time()*1000);   #current systime in ms
    my $offC = $sysC - $hmtC;      #offset calc between time and HM-stamp
    if ($ref->{hmtL} && ($hmtC > $ref->{hmtL})){
      if (($sysC - $ref->{kTs})<20){ #if delay is more then 20ms, we dont trust
        if ($ref->{sysL}){
          $ref->{drft} = ($offC - $ref->{offL})/($sysC - $ref->{sysL});
        }
        $ref->{sysL} = $sysC;
        $ref->{offL} = $offC;
      }
    }
    else{# hm had a skip in time, start over calculation
      delete $hash->{helper}{ref};
    }
    $hash->{helper}{ref}{hmtL} = $hmtC;
    $hash->{helper}{ref}{kTs} = 0;
  }

  my $sec = int($hmtC/1000);
  return sprintf("%03d %02d:%02d:%02d.%03d",
                  int($hmtC/86400000), int($sec/3600),
                  int(($sec%3600)/60), $sec%60, $hmtC % 1000);
}
sub HMLAN_Parse($$) {##########################################################
  my ($hash, $rmsg) = @_;
  my $name = $hash->{NAME};
  my @mFld = split(',', $rmsg);
  my $letter = substr($mFld[0],0,1); # get leading char

  if ($letter =~ m/^[ER]/){#@mFld=($src, $status, $msec, $d2, $rssi, $msg)
    # max speed for devices is 100ms after receive - example:TC

    my ($mNo,$flg,$type,$src,$dst,$p) = unpack('A2A2A2A6A6A*',$mFld[5]);
    my $CULinfo = "";

    my @logIds = ("150B94","172A85");
    Log3 $hash,  HMLAN_getVerbLvl ($hash,$src,$dst,"5")
                    , "HMLAN_Parse: $name R:".$mFld[0]
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
    #HMcnd stat
    #    00 00= msg without relation
    #    00 01= ack that HMLAN waited for
    #    00 02= msg send, no ack requested
    #    00 08= nack - ack was requested, msg repeated 3 times, still no ack
    #    00 21= ??(seen with 'R') - see below
    #    00 2x= should: AES was accepted, here is the response
    #    00 30= should: AES response failed
    #    00 40= ??(seen with 'E') after 0100
    #    00 41= ??(seen with 'R')
    #    00 50= ??(seen with 'R')
    #    00 81= ??
    #    01 xx= ?? 0100 AES response send (gen autoMsgSent)
    #    02 xx= prestate to 04xx. Message is still sent. This is a warning
    #    04 xx= nothing sent anymore. Any restart unsuccessful except power
    #
    #  parameter 'cond'- condition of the IO device
    #  Cond text
    #     0 ok
    #     1 comes with AES, also seen with wakeup long-sleep devices
    #     2 Warning-HighLoad
    #     4 Overload condition - no send anymore
    #
    my $stat = hex($mFld[1]);
    my $HMcnd =$stat >>8; #high = HMLAN cond
    $stat &= 0xff;        # low byte related to message format

    if ($HMcnd == 0x01){#HMLAN responded to AES request
      $CULinfo = "AESKey-".$mFld[3];
    }

    if ($stat){# message with status information
      HMLAN_condUpdate($hash,$HMcnd)if ($hash->{helper}{q}{HMcndN} != $HMcnd);

      if    ($stat & 0x03 && $dst eq $attr{$name}{hmId}){HMLAN_qResp($hash,$src,0);}
      elsif ($stat & 0x08 && $src eq $attr{$name}{hmId}){HMLAN_qResp($hash,$dst,0);}

      HMLAN_UpdtMsgLoad($name,((hex($flg)&0x10)?34   #burst=17units *2
                                               :2))  #ACK=1 unit *2
          if (($stat & 0x48) == 8);# reject - but not from repeater

      $hash->{helper}{$dst}{flg} = 0;#got response => unblock sending
      if ($stat & 0x0A){#08 and 02 dont need to go to CUL, internal ack only
        Log3 $hash, HMLAN_getVerbLvl ($hash,$src,$dst,"5")
                  , "HMLAN_Parse: $name no ACK from $dst"   if($stat & 0x08);
        return;
      }elsif (($stat & 0x70) == 0x30){Log3 $hash, HMLAN_getVerbLvl ($hash,$src,$dst,"5")
                                                , "HMLAN_Parse: $name AES code rejected for $dst $stat";
                                      $CULinfo = "AESerrReject";
                                      HMLAN_qResp($hash,$src,0);
      }elsif (($stat & 0x70) == 0x20){$CULinfo = "AESok";
      }elsif (($stat & 0x70) == 0x40){;#$CULinfo = "???";
      }
    }
    else{
      HMLAN_UpdtMsgLoad($name,1)
            if (   $letter eq "E"
                && (hex($flg)&0x60) == 0x20 # ack but not from repeater
                && $dst eq $attr{$name}{hmId});
    }

    my $rssi = hex($mFld[4])-65536;
     #update some User information ------
    $hash->{uptime} = HMLAN_uptime($mFld[2]);
    $hash->{RSSI}   = $rssi;
    $hash->{RAWMSG} = $rmsg;
    $hash->{"${name}_MSGCNT"}++;
    $hash->{"${name}_TIME"} = TimeNow();

    my $dly = 0; #--------- calc messageDelay ----------
    if ($hash->{helper}{ref} && $hash->{helper}{ref}{drft}){
      my $ref = $hash->{helper}{ref};#shortcut
      my $sysC = int(time()*1000);   #current systime in ms
      $dly = int($sysC - (hex($mFld[2]) + $ref->{offL} + $ref->{drft}*($sysC - $ref->{sysL})));

      $hash->{helper}{dly}{lst} = $dly;
      my $dlyP = $hash->{helper}{dly};
      $dlyP->{min} = $dly if (!$dlyP->{min} || $dlyP->{min}>$dly);
      $dlyP->{max} = $dly if (!$dlyP->{max} || $dlyP->{max}<$dly);
      if ($dlyP->{cnt}) {$dlyP->{cnt}++} else {$dlyP->{cnt} = 1} ;

      $hash->{msgParseDly} =   "min:" .$dlyP->{min}
                             ." max:" .$dlyP->{max}
                             ." last:".$dlyP->{lst}
                             ." cnt:" .$dlyP->{cnt};
      $dly = 0 if ($dly<0);
    }

    # HMLAN sends ACK for flag 'A0' but not for 'A4'(config mode)-
    # we ack ourself an long as logic is uncertain - also possible is 'A6' for RHS
    if (hex($flg)&0x22){#not sure: 4 oder 2 ? 0x.2 works for VD!
      my $wait = 0.100 - $dly/1000;
      $hash->{helper}{$src}{nextSend} = gettimeofday() + $wait if ($wait > 0);
    }
    if (hex($flg)&0xA4 == 0xA4 && $hash->{owner} eq $dst){
      Log3 $hash, HMLAN_getVerbLvl ($hash,$src,$dst,"5")
                , "HMLAN_Parse: $name ACK config";
      HMLAN_Write($hash,undef, "As15".$mNo."8002".$dst.$src."00");
    }

    if ($letter eq 'R' && $hash->{helper}{$src}{flg}){
      $hash->{helper}{$src}{flg} = 0;                 #release send-holdoff
      if ($hash->{helper}{$src}{msg}){                #send delayed msg if any
        Log3 $hash, HMLAN_getVerbLvl ($hash,$src,$dst,"5")
                  ,"HMLAN_SdDly: $name $src";
        HMLAN_SimpleWrite($hash, $hash->{helper}{$src}{msg});
      }
      $hash->{helper}{$src}{msg} = "";                #clear message
    }
    # prepare dispatch-----------
    # HM format A<len><msg>:<info>:<RSSI>:<IOname>  Info is not used anymore
    my $dmsg = sprintf("A%02X%s:$CULinfo:$rssi:$name",
                         length($mFld[5])/2, uc($mFld[5]));
    my %addvals = (RAWMSG => $rmsg, RSSI => hex($mFld[4])-65536);
    Dispatch($hash, $dmsg, \%addvals);
  }
  elsif($mFld[0] eq 'HHM-LAN-IF'){#HMLAN version info
    $hash->{serialNr} = $mFld[2];
    $hash->{firmware} = sprintf("%d.%d", (hex($mFld[1])>>12)&0xf, hex($mFld[1]) & 0xffff);
    $hash->{owner} = $mFld[4];
    $hash->{uptime} = HMLAN_uptime($mFld[5],$hash);
       $hash->{assignIDsReport}=hex($mFld[6]);
    $hash->{helper}{q}{keepAliveRec} = 1;
    $hash->{helper}{q}{keepAliveRpt} = 0;
    Log3 $hash, ($hash->{helper}{log}{sys}?0:5)
              , 'HMLAN_Parse: '.$name.                 ' V:'.$mFld[1]
                                   .' sNo:'.$mFld[2].' d:'.$mFld[3]
                                   .' O:'  .$mFld[4].' t:'.$mFld[5].' IDcnt:'.$mFld[6];
    my $myId = AttrVal($name, "hmId", "");
    $myId = $attr{$name}{hmId} = $mFld[4] if (!$myId);

    if($mFld[4] ne $myId && !AttrVal($name, "dummy", 0)) {
      Log3 $hash, 1, 'HMLAN setting owner to '.$myId.' from '.$mFld[4];
      HMLAN_SimpleWrite($hash, "A$myId");
    }
  }
  elsif($rmsg =~ m/^I00.*/) {;
    # Ack from the HMLAN
  }
  else {
    Log3 $hash, 5, "$name Unknown msg >$rmsg<";
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
  my $len = length($msg);

  # It is not possible to answer befor 100ms
  if ($len>51){
    if($hash->{helper}{q}{HMcndN}){
      my $HMcnd = $hash->{helper}{q}{HMcndN};
      return if (  ($HMcnd == 4 || $HMcnd == 253)
                  && !$hash->{helper}{recoverTest});# no send if overload or disconnect
      delete $hash->{helper}{recoverTest}; # test done
    }
    $msg =~ m/(.{9}).(..).(.{8}).(..).(.{8}).(..)(..)(..)(.{6})(.{6})(.*)/;
    my ($s,$stat,$t,$d,$r,$no,$flg,$typ,$src,$dst,$p) =
       ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);

    my $hmId = AttrVal($name,"hmId","");
    my $hDst = $hash->{helper}{$dst};# shortcut
    my $tn = gettimeofday();
    if ($hDst->{nextSend}){
      my $DevDelay = $hDst->{nextSend} - $tn;
      select(undef, undef, undef, (($DevDelay > 0.1)?0.1:$DevDelay))
            if ($DevDelay > 0.01);
      delete $hDst->{nextSend};
    }
    if ($dst ne $hmId){  #delay send if answer is pending
      if ( $hDst->{flg} &&                #HMLAN's ack pending
          ($hDst->{to} > $tn)){#won't wait forever! check timeout
        $hDst->{msg} = $msg;              #postpone  message
        Log3 $hash, HMLAN_getVerbLvl($hash,$src,$dst,"5"),"HMLAN_Delay: $name $dst";
        return;
      }
      if ($src eq $hmId){
        $hDst->{flg} = (hex($flg)&0x20)?1:0;# answer expected?
        $hDst->{to} = $tn + 2;# flag timeout after 2 sec
        $hDst->{msg} = "";
        HMLAN_qResp($hash,$dst,1) if ($hDst->{flg} == 1);
      }
    }

    if ($len > 52){#channel information included, send sone kind of clearance
      my $chn = substr($msg,52,2);
      if ($hDst->{chn} && $hDst->{chn} ne $chn){
        my $updt = $hDst->{newChn};
        Log3 $hash,  HMLAN_getVerbLvl($hash,$src,$dst,"5")
                  , 'HMLAN_Send:  '.$name.' S:'.$updt;
        syswrite($hash->{TCPDev}, $updt."\r\n")     if($hash->{TCPDev});
      }
      $hDst->{chn} = $chn;
    }
    Log3 $hash,  HMLAN_getVerbLvl($hash,$src,$dst,"5")
            , 'HMLAN_Send:  '.$name.' S:'.$s
                             .' stat:  ' .$stat
                             .' t:'      .$t
                             .' d:'      .$d
                             .' r:'      .$r
                             .' m:'      .$no
                             .' '        .$flg.$typ
                             .' '        .$src
                             .' '        .$dst
                             .' '        .$p;

    HMLAN_UpdtMsgLoad($name,(hex($flg)&0x10)?17:1);#burst counts
  }
  else{
    Log3 $hash, ($hash->{helper}{log}{sys}?0:5), 'HMLAN_Send:  '.$name.' I:'.$msg;
  }

  $msg .= "\r\n" unless($nonl);
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});
}
sub HMLAN_DoInit($) {##########################################################
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $id  = AttrVal($name, "hmId", "999999");
  my ($k1no,$k1,$k2no,$k2,$k3no,$k3)
         =( "01",AttrVal($name,"hmKey","")
           ,"02",AttrVal($name,"hmKey2","")
           ,"03",AttrVal($name,"hmKey3","")
                       );

  if ($k1 =~ m/:/){($k1no,$k1) = split(":",$k1);}
  if ($k2 =~ m/:/){($k2no,$k2) = split(":",$k2);}
  if ($k3 =~ m/:/){($k3no,$k3) = split(":",$k3);}

  my $s2000 = sprintf("%02X", HMLAN_secSince2000());
  delete $hash->{READINGS}{state};

  HMLAN_SimpleWrite($hash, "A$id") if($id ne "999999");
  HMLAN_SimpleWrite($hash, "C");
  HMLAN_SimpleWrite($defs{$name}, "Y01,".($k1?"$k1no,$k1":"00,"));
  HMLAN_SimpleWrite($defs{$name}, "Y02,".($k2?"$k2no,$k2":"00,"));
  HMLAN_SimpleWrite($defs{$name}, "Y03,".($k3?"$k3no,$k3":"00,"));
  HMLAN_SimpleWrite($hash, "T$s2000,04,00,00000000");
  delete $hash->{helper}{ref};

  HMLAN_condUpdate($hash,0xff);
  $hash->{helper}{q}{cap}{$_}=0 foreach (keys %{$hash->{helper}{q}{cap}});

  foreach (keys %lhash){delete ($lhash{$_})};# clear IDs - HMLAN might have a reset
  $hash->{helper}{q}{keepAliveRec} = 1; # ok for first time
  $hash->{helper}{q}{keepAliveRpt} = 0; # ok for first time

  my $tn = gettimeofday();
  my $wdTimer = AttrVal($name,"wdTimer",25);
  $hash->{helper}{k}{Start} = $tn;
  $hash->{helper}{k}{Next} = $tn + $wdTimer;

  RemoveInternalTimer( "keepAliveCk:".$name);# avoid duplicate timer
  RemoveInternalTimer( "keepAlive:".$name);# avoid duplicate timer
  InternalTimer($tn+$wdTimer, "HMLAN_KeepAlive", "keepAlive:".$name, 0);
  # send first message to retrieve HMLAN condition
  HMLAN_Write($hash,"","As09998112".$id."000001");

  return undef;
}
sub HMLAN_KeepAlive($) {#######################################################
  my($in ) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  $hash->{helper}{q}{keepAliveRec} = 0; # reset indicator

  return if(!$hash->{FD});
  HMLAN_SimpleWrite($hash, "K");
  my $tn = gettimeofday();
  my $wdTimer = AttrVal($name,"wdTimer",25);

  my $kDly =  int(($tn - $hash->{helper}{k}{Next})*1000)/1000;
  $hash->{helper}{k}{DlyMax} =  $kDly if($hash->{helper}{k}{DlyMax} < $kDly);

  if ($hash->{helper}{k}{Start}){
    my $kBuf =  int($hash->{helper}{k}{Start} + 30 - $tn);
    $hash->{helper}{k}{BufMin} =  $kBuf if($hash->{helper}{k}{BufMin} > $kBuf);
  }
  else{
    $hash->{helper}{k}{BufMin} =  30;
  }

  $hash->{msgKeepAlive} = "dlyMax:".$hash->{helper}{k}{DlyMax}
                         ." bufferMin:". $hash->{helper}{k}{BufMin};
  $hash->{helper}{k}{Start} = $tn;
  $hash->{helper}{k}{Next} = $tn + $wdTimer;
  $hash->{helper}{ref}{kTs} = int($tn*1000);

  my $rt = AttrVal($name,"respTime",1);
  InternalTimer($tn+$rt,"HMLAN_KeepAliveCheck","keepAliveCk:".$name,1);
  RemoveInternalTimer( "keepAlive:".$name);# avoid duplicate timer
  InternalTimer($tn+$wdTimer,"HMLAN_KeepAlive", "keepAlive:".$name, 1);
}
sub HMLAN_KeepAliveCheck($) {##################################################
  my($in ) = shift;
  my(undef,$name) = split(':',$in);
  my $hash = $defs{$name};
  if ($hash->{helper}{q}{keepAliveRec} != 1){# no answer
    if ($hash->{helper}{q}{keepAliveRpt} >2){# give up here
      HMLAN_condUpdate($hash,252);# trigger timeout event
      DevIo_Disconnected($hash);
    }
    else{
      $hash->{helper}{q}{keepAliveRpt}++;
      HMLAN_KeepAlive("keepAlive:".$name);#repeat
    }
  }
  else{
    $hash->{helper}{q}{keepAliveRpt}=0;
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
sub HMLAN_qResp($$$) {#response-waiting queue##################################
  my($hash,$id,$cmd) = @_;
  my $hashQ = $hash->{helper}{q};
  if ($cmd){
    $hashQ->{answerPend} ++;
    push @{$hashQ->{apIDs}},$id;
    $hash->{XmitOpen} = 0 if ($hashQ->{answerPend} >= $hashQ->{hmLanQlen});
  }
  else{
    $hashQ->{answerPend}-- if ($hashQ->{answerPend}>0);
    @{$hashQ->{apIDs}}=grep !/$id/,@{$hashQ->{apIDs}};
    $hash->{XmitOpen} = 1
            if (($hashQ->{answerPend} < $hashQ->{hmLanQlen}) &&
                !($hashQ->{HMcndN} == 4 ||
                  $hashQ->{HMcndN} == 253)
               );
  }
}

sub HMLAN_condUpdate($$) {#####################################################
  my($hash,$HMcnd) = @_;
  my $name = $hash->{NAME};
  my $hashCnd = $hash->{helper}{cnd};#short to helper
  my $hashQ   = $hash->{helper}{q};#short to helper
  $hashCnd->{$HMcnd} = 0 if (!$hashCnd->{$HMcnd});
  $hashCnd->{$HMcnd}++;
  if ($HMcnd == 4){#HMLAN needs a rest. Supress all sends exept keep alive
    $hash->{STATE} = "overload";
  }

  my $HMcndTxt = $HMcond{$HMcnd}?$HMcond{$HMcnd}:"Unknown:$HMcnd";
  Log3 $hash, 1, "HMLAN_Parse: $name new condition $HMcndTxt";
  my $txt;
  $txt .= $HMcond{$_}.":".$hashCnd->{$_}." "
                            foreach (keys%{$hashCnd});

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash,"cond",$HMcndTxt);
  readingsBulkUpdate($hash,"Xmit-Events",$txt);
  readingsBulkUpdate($hash,"prot_".$HMcndTxt,"last");

  $hashQ->{HMcndN} = $HMcnd;

  if ($HMcnd == 4 || $HMcnd == 253) {#transmission down
    $hashQ->{answerPend} = 0;
    @{$hashQ->{apIDs}} = ();       #clear Q-status
    $hash->{XmitOpen} = 0;         #deny transmit
    readingsBulkUpdate($hash,"prot_keepAlive","last")
        if (   $HMcnd == 253
            && $hash->{helper}{k}{Start}
            &&(gettimeofday() - 29) > $hash->{helper}{k}{Start});
  }
  elsif ($HMcnd == 255) {#reset counter after init
    $hashQ->{answerPend} = 0;
    @{$hashQ->{apIDs}} = ();       #clear Q-status
    $hash->{XmitOpen} = 1;         #allow transmit
  }
  else{
    $hash->{XmitOpen} = 1
        if($hashQ->{answerPend} < $hashQ->{hmLanQlen});#allow transmit
  }
  readingsEndUpdate($hash,1);
}

sub HMLAN_noDup(@) {#return list with no duplicates
  my %all;
  return "" if (scalar(@_) == 0);
  $all{$_}=0 foreach (grep !/^$/,@_);
  delete $all{""}; #remove empties if present
  return (sort keys %all);
}
sub HMLAN_getVerbLvl ($$$$){#get verboseLevel for message
  my ($hash,$src,$dst,$def) = @_;
  return ($hash->{helper}{log}{all}||
          (grep /($src|$dst)/,@{$hash->{helper}{log}{ids}}))?0:$def;
}

1;

=pod
=begin html

<a name="HMLAN"></a>
<h3>HMLAN</h3>
<ul>
    The HMLAN is the fhem module for the eQ-3 HomeMatic LAN Configurator.<br>
    A description on how to use  <a href="https://git.zerfleddert.de/cgi-bin/gitweb.cgi/hmcfgusb">hmCfgUsb</a> can be found follwing the link.<br/>
    <br/>
    The fhem module will emulate a CUL device, so the <a href="#CUL_HM">CUL_HM</a> module can be used to define HomeMatic devices.<br/>
    <br>
    In order to use it with fhem you <b>must</b> disable the encryption first with the "HomeMatic Lan Interface Configurator"<br>
    (which is part of the supplied Windows software), by selecting the device, "Change IP Settings", and deselect "AES Encrypt Lan Communication".<br/>
    <br/>
    This device can be used in parallel with a CCU and (readonly) with fhem. To do this:
    <ul>
        <li>start the fhem/contrib/tcptee.pl program</li>
        <li>redirect the CCU to the local host</li>
        <li>disable the LAN-Encryption on the CCU for the Lan configurator</li>
        <li>set the dummy attribute for the HMLAN device in fhem</li>
    </ul>
    <br/><br/>

    <a name="HMLANdefine"><b>Define</b></a>
    <ul>
        <code>define &lt;name&gt; HMLAN &lt;ip-address&gt;[:port]</code><br>
        <br>
        port is 1000 by default.<br/>
        If the ip-address is called none, then no device will be opened, so you can experiment without hardware attached.
    </ul>
    <br><br>

    <a name="HMLANset"><b>Set</b></a>
    <ul>
        <li><a href="#hmPairForSec">hmPairForSec</a></li>
        <li><a href="#hmPairSerial">hmPairSerial</a></li>
    </ul>
    <br><br>

    <a name="HMLANget"><b>Get</b></a>
    <ul>
        N/A
    </ul>
    <br><br>

    <a name="HMLANattr"><b>Attributes</b></a>
    <ul>
        <li><a href="#do_not_notify">do_not_notify</a></li><br>
        <li><a href="#attrdummy">dummy</a></li><br>
        <li><a href="#addvaltrigger">addvaltrigger</a></li><br>
        <li><a href="#HMLANlogIDs">logIDs</a><br>
           enables selective logging of HMLAN messages. A list of HMIds or names can be
           entered, comma separated, which shall be logged.<br>
           The attribute only allows device-IDs, not channel IDs.
           Channel-IDs will be modified to device-IDs automatically.
           <b>all</b> will log raw messages for all HMIds<br>
           <b>sys</b> will log system related messages like keep-alive<br>
           in order to enable all messages set "<b>all,sys</b>"<br>
        </li>
        <li><a name="HMLANhmMsgLowLimit">hmMsgLowLimit</a><br>
            max messages level of HMLAN allowed for low-level message queue
            to be executed. Above this level processing will be postponed.<br>
            HMLAN will allow a max of messages per hour, it will block sending otherwise.
            After about 90% messages the low-priority queue (currently only CUL_HM autoReadReg)
            will be delayed until the condition is cleared. <br>
            hmMsgLowLimit allowes to reduce this level further.<br>
            Note that HMLAN transmitt-level calculation is based on some estimations and
            has some tolerance. <br>
            </li><br>
        <li><a href="#hmId">hmId</a></li><br>
        <li><a name="HMLANhmKey">hmKey</a></li><br>
        <li><a name="HMLANhmKey2">hmKey2</a></li><br>
        <li><a name="HMLANhmKey3">hmKey3</a><br>
        AES keys for the HMLAN adapter. <br>
        The key is converted to a hash. If a hash is given directly it is not converted but taken directly.
        Therefore the original key cannot be converted back<br>
        </li>
        <li><a href="#hmProtocolEvents">hmProtocolEvents</a></li><br>
        <li><a name="HMLANrespTime">respTime</a><br>
        Define max response time of the HMLAN adapter in seconds. Default is 1 sec.<br/>
        Longer times may be used as workaround in slow/instable systems or LAN configurations.</li>
        <li><a name="HMLAN#wdTimer">wdTimer</a><br>
        Time in sec to trigger HMLAN. Values between 5 and 25 are allowed, 25 is default.<br>
        It is <B>not recommended</B> to change this timer. If problems are detected with <br>
        HLMLAN disconnection it is advisable to resolve the root-cause of the problem and not symptoms.</li>
        <li><a name="HMLANhmLanQlen">hmLanQlen</a><br>
        defines queuelength of HMLAN interface. This is therefore the number of
        simultanously send messages. increasing values may cause higher transmission speed.
        It may also cause retransmissions up to data loss.<br>
        Effects can be observed by watching protocol events<br>
        1 - is a conservatibe value, and is default<br>
        5 - is critical length, likely cause message loss</li>
    </ul>
    <a name="HMLANparameter"><b>parameter</b></a>
    <ul>
      <li><B>assignedIDs</B><br>
          HMIds that are assigned to HMLAN and will be handled. e.g. ACK will be generated internally</li>
      <li><B>assignedIDsCnt</B><br>
          number of IDs that are assigned to HMLAN by FHEM</li>
      <li><B>assignedIDsReport</B><br>
          number of HMIds that HMLAN reports are assigned. This should be identical
          to assignedIDsCnt</li>
      <li><B>msgKeepAlive</B><br>
          performance of keep-alive messages. <br>
          <B>dlyMax</B>: maximum delay of sheduled message-time to actual message send.<br>
          <B>bufferMin</B>: minimal buffer left to before HMLAN would likely disconnect
          due to missing keepAlive message. bufferMin will be reset to 30sec if
          attribut wdTimer is changed.<br>
          if dlyMax is high (several seconds) or bufferMin goes to "0" (normal is 4) the system
          suffers on internal delays. Reasons for the delay might be explored. As a quick solution
          wdTimer could be decreased to trigger HMLAN faster.</li>
      <li><B>msgLoadEst</B><br>
          estimation of load of HMLAN. As HMLAN has a max capacity of message transmit per hour
          FHEM tries to estimate usage - see also
          <a href="#hmMsgLowLimit">hmMsgLowLimit</a><br></li>
      <li><B>msgParseDly</B><br>
          calculates the delay of messages in ms from send in HMLAN until processing in FHEM.
          It therefore gives an indication about FHEM system performance.
          </li>
    </ul>
    <a name="HMLANreadings"><b>parameter and readings</b></a>
    <ul>
      <li><B>prot_disconnect</B>       <br>recent HMLAN disconnect</li>
      <li><B>prot_init</B>             <br>recent HMLAN init</li>
      <li><B>prot_keepAlive</B>        <br>HMLAN disconnect likely do to slow keep-alive sending</li>
      <li><B>prot_ok</B>               <br>recent HMLAN ok condition</li>
      <li><B>prot_timeout</B>          <br>recent HMLAN timeout</li>
      <li><B>prot_Warning-HighLoad</B> <br>high load condition entered - HMLAN has about 10% performance left</li>
      <li><B>prot_ERROR-Overload</B>   <br>overload condition - HMLAN will receive bu tno longer transmitt messages</li>
      <li><B>prot_Overload-released</B><br>overload condition released - normal operation possible</li>
    </ul>

</ul>

=end html
=cut

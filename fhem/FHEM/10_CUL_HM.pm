##############################################
# CUL HomeMatic handler
package main;

use strict;
use warnings;

sub CUL_HM_Define($$);
sub CUL_HM_Id($);
sub CUL_HM_Initialize($);
sub CUL_HM_Pair(@);
sub CUL_HM_Parse($$);
sub CUL_HM_SendCmd($$$$);
sub CUL_HM_Set($@);

my %culHmDevProps=(
  "10" => { st => "switch",          cl => "receiver" },
  "20" => { st => "dimmer",          cl => "receiver" },
  "30" => { st => "blindActuator",   cl => "receiver" },
  "40" => { st => "remote",          cl => "sender" },
  "41" => { st => "sensor",          cl => "sender" },
  "42" => { st => "swi",             cl => "sender" },
  "43" => { st => "pushButton",      cl => "sender" },
  "80" => { st => "threeStateSensor",cl => "sender" },
  "81" => { st => "motionDetector",  cl => "sender" },
  "C0" => { st => "keyMatic",        cl => "sender" },
  "C1" => { st => "winMatic",        cl => "receiver" },
  "CD" => { st => "smokeDetector",   cl => "sender" },
);

my %culHmModel=(
  "0001" => "HM-LC-SW1-PL-OM54",
  "0002" => "HM-LC-SW1-SM",
  "0003" => "HM-LC-SW4-SM",
  "0004" => "HM-LC-SW1-FM",
  "0005" => "HM-LC-BL1-FM",
  "0006" => "HM-LC-BL1-SM",
  "0007" => "KS550",
  "0008" => "HM-RC-4",
  "0009" => "HM-LC-SW2-FM",
  "000A" => "HM-LC-SW2-SM",
  "000B" => "HM-WDC7000",
  "000D" => "ASH550",
  "000E" => "ASH550I",
  "000F" => "S550IA",
  "0011" => "HM-LC-SW1-PL",
  "0012" => "HM-LC-DIM1L-CV",
  "0013" => "HM-LC-DIM1L-PL",
  "0014" => "HM-LC-SW1-SM-ATMEGA168",
  "0015" => "HM-LC-SW4-SM-ATMEGA168",
  "0016" => "HM-LC-DIM2L-CV",
  "0018" => "CMM",
  "0019" => "HM-SEC-KEY",
  "001A" => "HM-RC-P1",
  "001B" => "HM-RC-SEC3",
  "001C" => "HM-RC-SEC3-B",
  "001D" => "HM-RC-KEY3",
  "001E" => "HM-RC-KEY3-B",
  "0022" => "WS888",
  "0026" => "HM-SEC-KEY-S",
  "0027" => "HM-SEC-KEY-O",
  "0028" => "HM-SEC-WIN",
  "0029" => "HM-RC-12",
  "002A" => "HM-RC-12-B",
  "002D" => "HM-LC-SW4-PCB",
  "002E" => "HM-LC-DIM2L-SM",
  "002F" => "HM-SEC-SC",
  "0030" => "HM-SEC-RHS",
  "0034" => "HM-PBI-4-FM",
  "0035" => "HM-PB-4-WM",
  "0036" => "HM-PB-2-WM",
  "0037" => "HM-RC-19",
  "0038" => "HM-RC-19-B",
  "0039" => "HM-CC-TC",
  "003A" => "HM-CC-VD",
  "003B" => "HM-RC-4-B",
  "003C" => "HM-WDS20-TH-O",
  "003D" => "HM-WDS10-TH-O",
  "003E" => "HM-WDS30-T-O",
  "003F" => "HM-WDS40-TH-I",
  "0040" => "HM-WDS100-C6-O",
  "0041" => "HM-WDC7000",
  "0042" => "HM-SEC-SD",
  "0043" => "HM-SEC-TIS",
  "0044" => "HM-SEN-EP",
  "0045" => "HM-SEC-WDS",
  "0046" => "HM-SWI-3-FM",
  "0048" => "IS-WDS-TH-OD-S-R3",
  "004A" => "HM-SEC-MDIR",
  "004C" => "HM-RC-12-SW",
  "004D" => "HM-RC-19-SW",
  "004E" => "HM-LC-DDC1-PCB",
  "004F" => "HM-SEN-MDIR-SM",
  "0050" => "HM-SEC-SFA-SM",
  "0051" => "HM-LC-SW1-PB-FM",
  "0052" => "HM-LC-SW2-PB-FM",
  "0053" => "HM-LC-BL1-PB-FM",
  "0056" => "HM-CC-SCD",
  "0057" => "HM-LC-DIM1T-PL",
  "0058" => "HM-LC-DIM1T-CV",
  "0059" => "HM-LC-DIM1T-FM",
  "005A" => "HM-LC-DIM2T-SM",
  "005C" => "HM-OU-CF-PL",
  "005F" => "HM-SCI-3-FM",
  "0060" => "HM-PB-4DIS-WM",
  "0061" => "HM-LC-SW4-DR",
  "0062" => "HM-LC-SW2-DR",
);


sub
CUL_HM_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^A......................";
  $hash->{DefFn}     = "CUL_HM_Define";
  $hash->{ParseFn}   = "CUL_HM_Parse";
  $hash->{SetFn}     = "CUL_HM_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 model " .
                       "subType:switch,dimmer,blindActuator,remote,sensor,".
                             "swi,pushButton,threeStateSensor,motionDetector,".
                             "keyMatic,winMatic,smokeDetector " .
                       "hmClass:receiver,sender";
}


#############################
sub
CUL_HM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL_HM 6-digit-hex-code [Raw-Message]"
        if(!(int(@a)==3 || int(@a)==4) || $a[2] !~ m/^[A-F0-9]{6}$/i);

  $modules{CUL_HM}{defptr}{uc($a[2])} = $hash;
  $hash->{STATE} = "???";
  AssignIoPort($hash);
  if(int(@a) == 4) {
    $hash->{DEF} = $a[2];
    CUL_HM_Parse($hash, $a[3]);
  }
  return undef;
}



#############################
sub
CUL_HM_Parse($$)
{
  my ($hash, $msg) = @_;
  my $id = CUL_HM_Id($hash);

  # Msg format: Allnnccttssssssddddddpp...
  $msg =~ m/A(..)(..)(..)(..)(......)(......)(.*)/;
  my @msgarr = ($1,$2,$3,$4,$5,$6,$7);
  my ($len,$msgcnt,$channel,$msgtype,$src,$dst,$p) = @msgarr;
  Log 1, "CUL_HM L:$len N:$msgcnt C:$channel T:$msgtype SRC:$src DST:$dst $p";
  my $shash = $modules{CUL_HM}{defptr}{$src};

  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  my $dname = $dhash ? $dhash->{NAME} : "unknown";
  $dname = "broadcast" if($dst eq "000000");
  $dname = $hash->{NAME} if($dst eq $id);

  if(!$shash) {
    my $sname = "CUL_HM_$src";
    if("$channel$msgtype" eq "8400" && $len eq "1A") {
      my $model = substr($p, 2, 4);
      if($culHmModel{$model}) {
        $sname = $culHmModel{$model} . "_" . $src;
        $sname =~ s/-/_/g;
      }
    }
    Log 3, "CUL_HM Unknown device $sname, please define it";
    return "UNDEFINED $sname CUL_HM $src $msg";
  }

  my $name = $shash->{NAME};
  my @event;
  my $isack;
  if($shash->{ackWaiting}) {
    delete($shash->{ackWaiting});
    delete($shash->{ackCmdSent});
    RemoveInternalTimer($shash);
    $isack = 1;
  }

  my $st = AttrVal($name, "subType", undef);

  if("$channel$msgtype" =~ m/(8400|A000|A001)/) { # Pairing-Request
    push @event, CUL_HM_Pair($name, $shash, @msgarr);

  } elsif(!$st) {     # Will trigger unknown
    ;

  } elsif("$channel$msgtype" eq "8002" &&
           $shash->{pairingStep} &&
           $len eq "0A") { # Ack Pair
    push @event, CUL_HM_Pair($name, $shash, @msgarr);

  } elsif($st eq "switch") { ############################################

    if($p =~ m/^0.01(..)00/) {
      my $val = ($1 eq "C8" ? "on" : ($1 eq "00" ? "off" : "unknown $1"));
      push @event, "ackedCmd:$val";
      push @event, "state:$val" if(!$isack);

    } elsif($p =~ m/^0600(..)00$/) {
      my $s = ($1 eq "C8" ? "on" : ($1 eq "00" ? "off" : "unknown $1"));
      push @event, "poweron:$s";
      push @event, "state:$s";

    }

  } elsif($st eq "remote") { ############################################

    if("$channel$msgtype" =~ m/A.4./ && $p =~ m/^(..)(..)$/) {
      my $btn = int(($1+1)/2);
      my $state = $1&1 ? "off" : "on";
      my $add = ($dst eq $id) ? "" : " (to $dname)";
      push @event, "state:Btn$btn:$state$add";
      if($id eq $dst) {
        CUL_HM_SendCmd($shash, "++8002".$id.$src."0101".    # Send Ack.
                ($state eq "on"?"C8":"00")."0028", 1, 0);
      }
    }

  } elsif($st eq "smokeDetector") { #####################################

    if($p eq "0106C8") {
      push @event, "state:on";
      push @event, "smoke_detect:on";

    } elsif($p =~ m/^00..$/) {
      push @event, "test:$p";

    }

  }

  push @event, "unknown:$p" if(!@event);

  my $tn = TimeNow();
  for(my $i = 0; $i < int(@event); $i++) {
    next if($event[$i] eq "");
    my ($vn, $vv) = split(":", $event[$i], 2);
    Log GetLogLevel($name,2), "CUL_HM $name $vn:$vv" if($vn eq "unknown");

    if($vn eq "state") {
      $shash->{STATE} = $vv;
      $shash->{CHANGED}[$i] = $vv;

    } else {
      $shash->{CHANGED}[$i] = "$vn: $vv";

    }

    $shash->{READINGS}{$vn}{TIME} = $tn;
    $shash->{READINGS}{$vn}{VAL} = $vv;
  }


  return $name;
}

###################################
sub
CUL_HM_Set($@)
{
  my ($hash, @a) = @_;
  my $ret = undef;
  my $na = int(@a);

  return "no set value specified" if($na < 2 || $na > 3);

  my $name = $hash->{NAME};
  my $st = AttrVal($name, "subType", undef);
  my $cmd = $a[1];
  my $id = CUL_HM_Id($hash->{IODev});

  my $sndcmd;
  my $state;

  if($st eq "switch") {
    if($cmd eq "on" || $cmd eq "off") {
      $state = $cmd;
      $sndcmd = sprintf("++A440%s%s%02d%02d", $id, $hash->{DEF},
                 $cmd eq "on" ? 2: 1, $hash->{"${cmd}MsgNr"}++);
    }

  }

  return "$name: Unknown device subtype or command" if(!$sndcmd);
  CUL_HM_SendCmd($hash, $sndcmd, 0, 1);
  if($state) {
    $hash->{STATE} = $state;
    $hash->{READINGS}{state}{TIME} = TimeNow();
    $hash->{READINGS}{state}{VAL} = $state;
  }

  return "";
}


###################################
# A pairing between rrrrrr (remote) and ssssss (switch) looks like the
# following (nn and ff is the index of the on and off button):
# 1A 66 84 00 ssssss 000000 19 0011 46 4551303 03831363537 10 01 0100
# 1A CF 84 00 rrrrrr ssssss 12 0035 47 4551303 03333333633 40 04 nnff
# 0A D0 80 02 ssssss rrrrrr 00
# 10 D0 A0 01 ssssss rrrrrr nn05 ssssss 0104
# 0A D0 80 02 rrrrrr ssssss 00
# 0E D0 A0 01 ssssss rrrrrr nn07 020201
# 0A D0 80 02 rrrrrr ssssss 00
# 0B D0 A0 01 ssssss rrrrrr nn06
# 0A D0 80 02 rrrrrr ssssss 00
# 10 D0 A0 01 ssssss rrrrrr ff05 ssssss 0104
# 0A D0 80 02 rrrrrr ssssss 00
# 0E D0 A0 01 ssssss rrrrrr ff07 020201
# 0A D0 80 02 rrrrrr ssssss 02
# 0B D0 A0 01 ssssss rrrrrr ff06
# 0A D0 80 02 rrrrrr ssssss 00
sub
CUL_HM_Pair(@)
{
  my ($name, $def, $len,$msgcnt,$channel,$msgtype,$src,$dst,$p) = @_;
  my $id = CUL_HM_Id($def->{IODev});
  my $l4 = GetLogLevel($name,4);
  my $ps = $def->{pairingStep} ? $def->{pairingStep} : "";


  # Starting pair message with everything we need
  if($len eq "1A") {
    my $stc = substr($p, 26, 2);        # subTypeCode
    my $model = substr($p, 2, 4);
    my $dp = $culHmDevProps{$stc};

    $attr{$name}{model}   = $culHmModel{$model}? $culHmModel{$model} :"unknown";
    $attr{$name}{subType} = $dp ? $dp->{st} : "unknown";
    $attr{$name}{hmClass} = $dp ? $dp->{cl} : "unknown";

    my $stn = $attr{$name}{subType};    # subTypeName
    my $stt = $stn eq "unknown" ? "subType unknown" : "is a $stn";

    # First message
    if(!$ps) {
      Log GetLogLevel($name,2), "CUL_HM $name $stt, model $attr{$name}{model}";

      if($stn eq "unknown") {
        Log GetLogLevel($name,1), "CUL_HM unknown subType $stc, cannot pair";
        return "";
      }

      # Abort if we are not authorized
      my $ion = $def->{IODev}->{NAME};
      return "" 
        if(!($dst eq "000000" && AttrVal($ion, "hm_autopair", 1) ||
             $dst eq $id));

      # Sender pair mode, before btn is pressed
      $def->{pairButtons} = substr($p, 30, 4);
      return "" if($def->{pairButtons} eq "0000");

      my ($mystc, $mymodel, $mybtn, $myunknown);
      if(AttrVal($name,"hmClass","") eq "sender") {
        $mymodel   = "0011";  # Emulate a HM-LC-SW1-PL
        $mystc     = "10";    # switch
        $mybtn     = "010100";# No buttons (?)
        $myunknown = "46455130303831363537"

      } else {
        $mymodel   = "0060";  # Emulate a HM-PB-4DIS-WM
        $mystc     = "40";    # remote
        $mybtn     = "940201";# Buttons 02 (on) & 01 (off)
        $myunknown = "48455130303634393136";
      }

      if($dst eq "000000") {
        Log $l4, "CUL_HM Pairing Step 1";
        CUL_HM_SendCmd($def,
          $msgcnt."A000".$id.$src."19".$mymodel.$myunknown.$mystc.$mybtn, 1, 0);
      }

      $ps = $def->{pairingStep} = 1;
      return "" if(AttrVal($name,"hmClass","") eq "receiver");
    }
  }

  if(!$ps || $dst ne $id) {
    Log 4, "CUL_HM $name pairing step with other device";
    return "";
  }

  # If the partner is a receiver, then we only have to ack every message
  # after the first.
  if($ps && AttrVal($name,"hmClass","") eq "receiver") {
    CUL_HM_SendCmd($def, $msgcnt."8002".$id.$src."00", 1, 0);
    return "";
  }

  # switch emulation (sender is ack only and handled above);
  $def->{pairButtons} =~ m/(..)(..)/;
  my ($b1, $b2, $cmd) = ($1, $2, "");
  $cmd = "++A001$id$src${b1}05$src${b1}04" if($ps == 1);
  $cmd = "++A001$id$src${b1}07020201"      if($ps == 2);
  $cmd = "++A001$id$src${b1}06"            if($ps == 3);
  $cmd = "++A001$id$src${b2}05$src${b1}04" if($ps == 4);
  $cmd = "++A001$id$src${b2}07020201"      if($ps == 5);
  $cmd = "++A001$id$src${b2}06"            if($ps == 6);
  if($ps == 7) {
    delete($def->{pairingStep});
    return "";
  }
  CUL_HM_SendCmd($def, $cmd, 1, 1);
  $def->{pairingStep} = ++$ps;
  Log $l4, "CUL_HM Pairing Step $ps ($cmd)";

  return "";
}
    
###################################
sub
CUL_HM_SendCmd($$$$)
{
  my ($hash, $cmd, $sleep, $waitforack) = @_;
  my $io = $hash->{IODev};
  my $l4 = GetLogLevel($hash->{NAME},4);

  select(undef, undef, undef, 0.1*$sleep) if($sleep);

  $cmd =~ m/^(..)(.*)$/;
  my ($mn, $cmd2) = ($1, $2);

  if($mn eq "++") {
    $mn = $io->{HM_CMDNR} ? ($io->{HM_CMDNR} +1) : 1;
    $mn = 0 if($mn > 255);

  } else {
    $mn = hex($mn);

  }

  $io->{HM_CMDNR} = $mn;
  $cmd = sprintf("As%02X%02x%s", length($cmd2)/2+1, $mn, $cmd2);
  Log $l4, "CUL_HM $cmd";
  IOWrite($hash, "", $cmd);
  if($waitforack) {
    $hash->{ackWaiting} = $cmd;
    $hash->{ackCmdSent} = 1;
    InternalTimer(gettimeofday()+0.4, "CUL_HM_Resend", $hash, 0);
  }
}

###################################
sub
CUL_HM_Resend($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  if($hash->{ackCmdSent} == 3) {
    delete($hash->{ackCmdSent});
    delete($hash->{ackWaiting});
    $hash->{STATE} = "MISSING ACK";
    DoTrigger($name, "MISSING ACK");
    return;
  }
  IOWrite($hash, "", $hash->{ackWaiting});
  $hash->{ackCmdSent}++;
  DoTrigger($name, "resend nr ".$hash->{ackCmdSent});
  InternalTimer(gettimeofday()+0.4, "CUL_HM_Resend", $hash, 0);
}

###################################
sub
CUL_HM_Id($)
{
  my ($io) = @_;
  return "123456" if(!$io || !$io->{FHTID});
  return "F1" . $io->{FHTID};
}

1;

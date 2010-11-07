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
sub CUL_HM_SendCmd($$$);
sub CUL_HM_Set($@);

my %culHmSubType=(
  "10" => "switch",
  "20" => "dimmer",
  "30" => "blindActuator",
  "40" => "remote",
  "41" => "sensor",
  "42" => "swi",
  "43" => "pushButton",
  "80" => "threeStateSensor",
  "81" => "motionDetector",
  "C0" => "keyMatic",
  "C1" => "winMatic", 
  "CD" => "smokeDetector",
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
                             "keyMatic,winMatic,smokeDetector";
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
  $hash->{STATE} = "Defined";
  if(int(@a) == 4) {
    CUL_HM_Parse($hash, $a[3]);
    $hash->{DEF} = $a[2];
  }
  AssignIoPort($hash);
  return undef;
}


sub
CUL_HM_Parse($$)
{
  my ($hash, $msg) = @_;

  # Msg format: Allnnccttssssssddddddpp...
  $msg =~ m/A(..)(..)(..)(..)(......)(......)(.*)/;
  my @msgarr = ($1,$2,$3,$4,$5,$6,$7);
  my ($len,$msgcnt,$channel,$msgtype,$src,$dst,$p) = @msgarr;
  Log 1, "CUL_HM L:$len N:$msgcnt C:$channel T:$msgtype SRC:$src DST:$dst $p";
  my $def = $modules{CUL_HM}{defptr}{$src};

  if(!$def) {
    Log 3, "CUL_HM Unknown device $src, please define it";
    return "UNDEFINED CUL_HM_$src CUL_HM $src $msg";
  }

  my $name = $def->{NAME};
  my @event;

  my $st = AttrVal($name, "subType", undef);
  if("$channel$msgtype" =~ m/(8400|A000|A001|8002)/) { # Pairing-Request
    push @event, CUL_HM_Pair($name, $def, @msgarr);

  } elsif(!$st) {     # Will trigger unknown
    ;

  } elsif($st eq "switch") {

    if($p =~ m/^0601(..)00$/) {
      push @event, "state:" .
        ($1 eq "C8" ? "on" : ($1 eq "00" ? "off" : "unknown $1"));

    } elsif($p =~ m/^0600(..)00$/) {
      my $s = ($1 eq "C8" ? "on" : ($1 eq "00" ? "off" : "unknown $1"));
      push @event, "poweron:$s";
      push @event, "state:$s";

    }

  } elsif($st eq "smokeDetector") {

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
      $def->{STATE} = $vv;
      $def->{CHANGED}[$i] = $vv;

    } else {
      $def->{CHANGED}[$i] = "$vn: $vv";

    }

    $def->{READINGS}{$vn}{TIME} = $tn;
    $def->{READINGS}{$vn}{VAL} = $vv;
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

  if($st eq "switch") {
    if($cmd eq "on" || $cmd eq "off") {
      CUL_HM_SendCmd($hash, 
        sprintf("++9441%s%s0101%s", $id, $hash->{DEF}, $cmd eq "on"?"C8":"00"),
        0);

    } elsif($cmd eq "raw") {
      CUL_HM_SendCmd($hash, 
        sprintf("++9441%s%s%s", $id, $hash->{DEF}, $a[2]), 0);
    }

  } else {
    return "$name: Unknown subtype, cannot set";
  }
  return "";
}

###################################
sub
CUL_HM_Pair(@)
{
  my ($name, $def, $len,$msgcnt,$channel,$msgtype,$src,$dst,$p) = @_;
  my $id = CUL_HM_Id($def->{IODev});
  my $l4 = GetLogLevel($name,4);

  if($len eq "1A") {
    my $st = substr($p, 26, 2);
    my $model = substr($p, 2, 4);
    $attr{$name}{subType} = $culHmSubType{$st} ? $culHmSubType{$st} : "unknown";
    $attr{$name}{model} = $culHmModel{$model} ? $culHmModel{$model} : "unknown";

    $st = $attr{$name}{subType};
    $st = $st eq "unknown" ? "subType unknown" : "is a $st";
    Log GetLogLevel($name,2), "CUL_HM $name $st, model $attr{$name}{model}";

    # Lets answer if we are authorized
    my $ion = $def->{IODev}->{NAME};
    if(($dst eq "000000" && $attr{$ion} && $attr{$ion}{hm_autopair}) ||
       $dst eq $id) {
      CUL_HM_SendCmd($def,
          "${msgcnt}A000$id${src}EEEEEE48455130313236373039EE000100", 1);
      $def->{pairingStep} = 1;
      Log $l4, "Pairing Step 1 (Send reply)";
    }

  } elsif($dst ne $id) {
    return "";

  } elsif($len eq "0A") {
    my $ps = $def->{pairingStep};
    if($ps) {
      $def->{pairingStep} = ++$ps;
      Log 1, "Pairing Step $ps (GOT ACK)";
      return "" if($ps == 2);
      CUL_HM_SendCmd($def, "++A001$id${src}0105${src}0103", 1)
                                if($ps == 6);
      CUL_HM_SendCmd($def, "++A001$id${src}0108011202120312043205B40A01", 1)
                                if($ps == 7);
      CUL_HM_SendCmd($def, "++A001$id${src}01080B140C240D248A00", 1)
                                if($ps == 8);
      CUL_HM_SendCmd($def, "++A001$id${src}0106", 1)
                                if($ps == 9);
      CUL_HM_SendCmd($def, "++A001$id${src}0105${id}0104", 1)
                                if($ps == 10);
      Log $l4, "Pairing finished" if($ps == 11);
    }

  } elsif($len eq "10") {
    CUL_HM_SendCmd($def, "${msgcnt}8002$id${src}80", 1);
    my $ps = $def->{pairingStep};
    $ps = 2 if(!$ps);
    $def->{pairingStep} = ++$ps;
    Log $l4, "Pairing Step $ps (SEND ACK)";
    CUL_HM_SendCmd($def, "++A001$id${src}0101${src}0100", 10)
                                if($ps == 4);
  }

  return "";
}
    
###################################
sub
CUL_HM_SendCmd($$$)
{
  my ($hash, $cmd, $sleep) = @_;
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
  Log $l4, $cmd;
  IOWrite($hash, "", $cmd);
}

sub
CUL_HM_Id($)
{
  my ($io) = @_;
  return "000000" if(!$io || !$io->{FHTID});
  return "F1" . $io->{FHTID};
}

1;

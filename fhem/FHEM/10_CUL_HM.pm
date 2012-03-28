##############################################
# CUL HomeMatic handler
# $Id$
package main;

use strict;
use warnings;

sub CUL_HM_Define($$);
sub CUL_HM_Id($);
sub CUL_HM_Initialize($);
sub CUL_HM_Pair(@);
sub CUL_HM_Parse($$);
sub CUL_HM_PushCmdStack($$);
sub CUL_HM_ProcessCmdStack($);
sub CUL_HM_SendCmd($$$$);
sub CUL_HM_Set($@);
sub CUL_HM_DumpProtocol($$@);
sub CUL_HM_convTemp($);

my %culHmDevProps=(
  "01" => { st => "AlarmControl",    cl => "controller" }, # by peterp
  "10" => { st => "switch",          cl => "receiver" }, # Parse,Set
  "20" => { st => "dimmer",          cl => "receiver" }, # Parse,Set
  "30" => { st => "blindActuator",   cl => "receiver" }, # Parse,Set
  "40" => { st => "remote",          cl => "sender" },   # Parse
  "41" => { st => "sensor",          cl => "sender" },
  "42" => { st => "swi",             cl => "sender" },
  "43" => { st => "pushButton",      cl => "sender" },
  "60" => { st => "KFM100",          cl => "sender" },   # Parse,unfinished
  "70" => { st => "THSensor",        cl => "sender" },   # Parse,unfinished
  "80" => { st => "threeStateSensor",cl => "sender" },
  "81" => { st => "motionDetector",  cl => "sender" },
  "C0" => { st => "keyMatic",        cl => "sender" },
  "C1" => { st => "winMatic",        cl => "receiver" },
  "CD" => { st => "smokeDetector",   cl => "sender" },   # Parse
);

my %culHmModel=(
  "0001" => "HM-LC-SW1-PL-OM54",
  "0002" => "HM-LC-SW1-SM",
  "0003" => "HM-LC-SW4-SM",
  "0004" => "HM-LC-SW1-FM",  # Tested
  "0005" => "HM-LC-BL1-FM",  # Tested by ruebezahl (2011-09-22)
  "0006" => "HM-LC-BL1-SM",
  "0007" => "KS550",         # Tested
  "0008" => "HM-RC-4",       # cant pair(AES)-> broadcast only
  "0009" => "HM-LC-SW2-FM",
  "000A" => "HM-LC-SW2-SM",
  "000B" => "HM-WDC7000",    # Tested by elanter (2011-09-22)
  "000D" => "ASH550",
  "000E" => "ASH550I",
  "000F" => "S550IA",
  "0011" => "HM-LC-SW1-PL",   # Tested
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
  "0028" => "HM-SEC-WIN",     # some experiments
  "0029" => "HM-RC-12",
  "002A" => "HM-RC-12-B",
  "002D" => "HM-LC-SW4-PCB",
  "002E" => "HM-LC-DIM2L-SM",
  "002F" => "HM-SEC-SC",
  "0030" => "HM-SEC-RHS",     # Tested
  "0034" => "HM-PBI-4-FM",
  "0035" => "HM-PB-4-WM",     # Tested
  "0036" => "HM-PB-2-WM",
  "0037" => "HM-RC-19",
  "0038" => "HM-RC-19-B",
  "0039" => "HM-CC-TC",       # Selected commands
  "003A" => "HM-CC-VD",       # Actuator, battery/etc missing
  "003B" => "HM-RC-4-B",
  "003C" => "HM-WDS20-TH-O",
  "003D" => "HM-WDS10-TH-O",  # Reported to work (2011-07-26)
  "003E" => "HM-WDS30-T-O",
  "003F" => "HM-WDS40-TH-I",  # Tested by peterp
  "0040" => "HM-WDS100-C6-O", # Identical to KS550?
  "0041" => "HM-WDC7000",     # Tested by elanter (2011-09-22)
  "0042" => "HM-SEC-SD",      # Tested
  "0043" => "HM-SEC-TIS",
  "0044" => "HM-SEN-EP",
  "0045" => "HM-SEC-WDS",     # Tested by peterp
  "0046" => "HM-SWI-3-FM",
  "0047" => "KFM-Display",
  "0048" => "IS-WDS-TH-OD-S-R3",
  "0049" => "KFM-Sensor",
  "004A" => "HM-SEC-MDIR",     # Tested
  "004B" => "HM-Sec-Cen",      # by peterp
  "004C" => "HM-RC-12-SW",
  "004D" => "HM-RC-19-SW",
  "004E" => "HM-LC-DDC1-PCB",
  "004F" => "HM-SEN-MDIR-SM",
  "0050" => "HM-SEC-SFA-SM",
  "0051" => "HM-LC-SW1-PB-FM",
  "0052" => "HM-LC-SW2-PB-FM", # Tested
  "0053" => "HM-LC-BL1-PB-FM", # Tested by ruebezahl (2011-09-22)
  "0056" => "HM-CC-SCD",	   
  "0057" => "HM-LC-DIM1T-PL",
  "0058" => "HM-LC-DIM1T-CV",
  "0059" => "HM-LC-DIM1T-FM",
  "005A" => "HM-LC-DIM2T-SM",
  "005C" => "HM-OU-CF-PL",
  "005F" => "HM-SCI-3-FM",
  "0060" => "HM-PB-4DIS-WM",   # Tested
  "0061" => "HM-LC-SW4-DR",    # Tested by fhem-hm-knecht.
  "0062" => "HM-LC-SW2-DR",
  "0066" => "HM_LC_Sw4-WM",    # Tested by peterp
  "006C" => "HM-LC-SW1-PCB",   # By jan (unsure if working)
);


sub
CUL_HM_Initialize($)
{
  my ($hash) = @_;

  $hash->{Match}     = "^A....................";
  $hash->{DefFn}     = "CUL_HM_Define";
  $hash->{ParseFn}   = "CUL_HM_Parse";
  $hash->{SetFn}     = "CUL_HM_Set";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 " .
                       "showtime:1,0 loglevel:0,1,2,3,4,5,6 model " .
                       "subType:switch,dimmer,blindActuator,remote,sensor,".
                         "swi,pushButton,threeStateSensor,motionDetector,".
                         "keyMatic,winMatic,smokeDetector " .
                       "hmClass:receiver,sender serialNr firmware devInfo ".
                       "rawToReadable unit";
}


#############################
sub
CUL_HM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  return "wrong syntax: define <name> CUL_HM 6-digit-hex-code [Raw-Message]"
        if(!(int(@a)==3 || int(@a)==4) || $a[2] !~ m/^[A-F0-9]{6,8}$/i);

  $modules{CUL_HM}{defptr}{uc($a[2])} = $hash;
  AssignIoPort($hash);

  # shadow switch device, look for the real one, and copy its attributes
  if(length($a[2]) == 8) {
    my $chiefId = substr($a[2], 0, 6);
    my $chiefHash = $modules{CUL_HM}{defptr}{uc($chiefId)};
    if($chiefHash) {
      my $cname = $chiefHash->{NAME};
      if($attr{$cname}) {
        foreach my $attrName (keys %{$attr{$cname}}) {
          $attr{$name}{$attrName} = $attr{$cname}{$attrName};
        }
      }
    }
  }

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
  my ($iohash, $msg) = @_;
  my $id = CUL_HM_Id($iohash);

  # Msg format: Allnnccttssssssddddddpp...
  $msg =~ m/A(..)(..)(....)(......)(......)(.*)/;
  my @msgarr = ($1,$2,$3,$4,$5,$6,$7);
  my ($len,$msgcnt,$cmd,$src,$dst,$p) = @msgarr;
  $p = "" if(!defined($p));

  # cmdX / msgX used for duplicate detection
  my $cmdX = $cmd;
  $cmdX =~ s/^A4/A0/;
  $cmdX =~ s/^0B/0A/;
  $cmdX =~ s/^84/A0/;
  my $msgX = "$len$msgcnt$cmdX$src$dst$p";

  # $shash will be replaced for multichannel commands
  my $shash = $modules{CUL_HM}{defptr}{$src}; 
  my $lcm = "$len$cmd";
  my $dhash = $modules{CUL_HM}{defptr}{$dst};
  my $dname = $dhash ? $dhash->{NAME} :
                       ($dst eq "000000" ? "broadcast" : 
                       ($dst eq $id ? $iohash->{NAME} : $dst));
  my $target = ($dst eq $id) ? "" : " (to $dname)";


  if($p =~ m/NACK$/) {  # HMLAN special
    if($dhash) {
      delete($dhash->{ackCmdSent});
      delete($dhash->{ackWaiting});
      delete($dhash->{cmdStack});
      $dhash->{STATE} = "MISSING ACK";
      DoTrigger($dname, "MISSING ACK");
    }
    return "";
  }

  CUL_HM_DumpProtocol("RCV", $iohash, @msgarr);

  if(!$shash) {      #  Unknown source

    # Generate an UNKNOWN event for pairing requests, ignore everything else
    if($lcm =~ m/1A8.00/) {
      my $sname = "CUL_HM_$src";

      # prefer subType over model to make autocreate easier
      # model names are quite cryptic anyway
      my $model = substr($p, 2, 4);
      my $stc = substr($p, 26, 2);        # subTypeCode
      if($culHmDevProps{$stc}) {
        $sname = "CUL_HM_".$culHmDevProps{$stc}{st} . "_" . $src;

      } elsif($culHmModel{$model}) {
        $sname = "CUL_HM_".$culHmModel{$model} . "_" . $src;
        $sname =~ s/-/_/g;
      }

      Log 3, "CUL_HM Unknown device $sname, please define it";
      return "UNDEFINED $sname CUL_HM $src $msg";
    }

    return "";
  }

  my $name = $shash->{NAME};
  my @event;
  my $st = AttrVal($name, "subType", "");
  my $model = AttrVal($name, "model", "");
  my $tn = TimeNow();

  if($cmd eq "8002") {                  # Ack / Nack
    # Multi-channel device: Switch to the shadow source hash
    my $chn = $2 if($p =~ m/^(..)(..)/);
    if($chn && $chn ne "01" && $chn ne "00") {
      my $sshash = $modules{CUL_HM}{defptr}{"$src$chn"};
      $shash = $sshash if($sshash);
    }

    if($p =~ m/^8/) {
      delete($shash->{cmdStack});
      push @event, "state:NACK";

    } else {
      CUL_HM_ProcessCmdStack($shash);
      push @event, "";
    }
    $shash->{READINGS}{CommandAccepted}{TIME} = $tn;
    $shash->{READINGS}{CommandAccepted}{VAL} = ($p =~ m/^8/ ? "no" : "yes");

  }

  if($cmd ne "8002" && $shash->{cmdStack}) { 
    # i have to tell something, dont care what it said
    CUL_HM_SendCmd($shash, "++8002$id${src}00",1,0)  # Send Ack
      if($id eq $dst && $p ne "00");
    CUL_HM_ProcessCmdStack($shash);
    push @event, "";

  } elsif($lcm eq "09A112") {      ### Another fhem wants to talk (HAVE_DATA)
    ;

  } elsif($lcm eq "1A8400" ||      #### Pairing-Request
          $lcm eq "1A8000" ||
          $lcm eq "1A0400") {

    if($shash->{cmdStack}) {
      #CUL_HM_SendCmd($shash, "++A112$id$src", 1, 1); # HAVE_DATA
      CUL_HM_ProcessCmdStack($shash);

    } else {
      push @event, CUL_HM_Pair($name, $shash, @msgarr);

    }

  } elsif($cmd =~ m/^A0[01]{2}$/ && $dst eq $id) {#### Pairing-Request-Convers.
    CUL_HM_SendCmd($shash, $msgcnt."8002".$id.$src."00", 1, 0);  # Ack
    push @event, "";

  } elsif($model eq "KS550" || $model eq "HM-WDS100-C6-O") { ############

    if($cmd eq "8670" && $p =~ m/^(....)(..)(....)(....)(..)(..)(..)/) {

      my (    $t,      $h,      $r,      $w,     $wd,      $s,      $b ) =
         (hex($1), hex($2), hex($3), hex($4), hex($5), hex($6), hex($7));
      my $tsgn = ($t & 0x4000);
      $t = ($t & 0x3fff)/10;
      $t = sprintf("%0.1f", $t-1638.4) if($tsgn);
      my $ir = $r & 0x8000;
      $r = ($r & 0x7fff) * 0.295;
      my $wdr = ($w>>14)*22.5;
      $w = ($w & 0x3fff)/10;
      $wd = $wd * 5;

      push @event,
        "state:T: $t H: $h W: $w R: $r IR: $ir WD: $wd WDR: $wdr S: $s B: $b";
      push @event, "temperature:$t";
      push @event, "humidity:$h";
      push @event, "windSpeed:$w";
      push @event, "windDirection:$wd";
      push @event, "windDirRange:$wdr";
      push @event, "rain:$r";
      push @event, "isRaining:$ir";
      push @event, "sunshine:$s";
      push @event, "brightness:$b";

    } else {
      push @event, "KS550 unknown: $p";

    }

  } elsif($model eq "HM-CC-TC") {  ####################################

    if($cmd eq "8670" && $p =~ m/^(....)(..)/) {
      my (    $t,      $h) = 
         (hex($1), hex($2));
      my $tsgn = ($t & 0x4000);
      $t = ($t & 0x3fff)/10;
      $t = sprintf("%0.1f", $t-1638.4) if($tsgn);
      push @event, "state:T: $t H: $h";
      push @event, "measured-temp:$t";
      push @event, "temperature:$t";
      push @event, "humidity:$h";

    }

    if($cmd eq "A258" && $p =~ m/^(..)(..)/) {
      my (   $d1,     $vp) = 
         (hex($1), hex($2));
      $vp = int($vp/2.56+0.5);   # valve position in %
      push @event, "actuator:$vp %";

      # Set the valve state too, without an extra trigger
      if($dhash) {
        $dhash->{STATE} = "$vp %";
        $dhash->{READINGS}{STATE}{TIME} = $tn;
        $dhash->{READINGS}{STATE}{VAL} = "$vp %";
      }
    }

    # 0403 167DE9 01 05 05 16 0000 windowopen-temp channel 03, device 167DE9 on
    # slot 01.
    if($cmd eq "A410" && $p =~ m/^0403(......)(..)(..)(..)(..)(....)/) {
      my ( $tdev,   $tchan,  $plist, $o1,     $v1,  $rest) = 
       (($1), hex($2), hex($3),   ($4), hex($5), ($6));
      my $msg;
      if($plist == 5) {
      	if($o1 eq "05") {
          $msg = sprintf("windowopen-temp-%d: %.1f (sensor:%s)",
                        $tchan, $v1/2, $tdev);
        }
      }
      push @event, $msg if $msg;
    }
    # idea: remember  all possible 24 value-pairs per day and reconstruct list
    # everytime new values are set or received.
    if($cmd eq "A410" &&
       $p =~ m/^0402000000000(.)(..)(..)(..)(..)(..)(..)(..)(..)/) {
      # param list 5 or 6, 4 value pairs.
      my ($plist, $o1,    $v1,    $o2,    $v2,    $o3,    $v3,    $o4,    $v4) =
         (hex($1),hex($2),hex($3),hex($4),hex($5),hex($6),hex($7),hex($8),hex($9));

      my ($dayoff, $maxdays, $basevalue);
      my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");

      if($plist == 5 || $plist == 6) {
        if($plist == 5) {
          $dayoff = 0; $maxdays = 5; $basevalue = hex("0B");

        } else {
          $dayoff = 5; $maxdays = 2; $basevalue = hex("01");

        }
        my $idx = ($o1-$basevalue);
        my $dayidx = int($idx/48);
        if($idx % 4 == 0 && $dayidx < $maxdays) {
          $idx -= 48*$dayidx;
          $idx /= 2;
          my $ptr = $shash->{TEMPLIST}{$days[$dayidx+$dayoff]};
          $ptr->{$idx}{HOUR} = int($v1/6);
          $ptr->{$idx}{MINUTE} = ($v1 - int($v1/6)*6)*10;
          $ptr->{$idx}{TEMP} = $v2/2;
          $ptr->{$idx+1}{HOUR} = int($v3/6);
          $ptr->{$idx+1}{MINUTE} = ($v3 - int($v3/6)*6)*10;
          $ptr->{$idx+1}{TEMP} = $v4/2;
        }
      }

      foreach my $wd (@days) {
        my $twentyfour = 0;
        my $msg = sprintf("tempList%s:", $wd);
        foreach(my $idx=0; $idx<24; $idx+=1) {
          my $ptr = $shash->{TEMPLIST}{$wd}{$idx};
          if(defined ($ptr->{TEMP}) && $ptr->{TEMP} ne "") {
            if($twentyfour == 0) {
              $msg .= sprintf(" %02d:%02d %.1f",
                                $ptr->{HOUR}, $ptr->{MINUTE}, $ptr->{TEMP});
            } else {
              $ptr->{HOUR} = $ptr->{MINUTE} = $ptr->{TEMP} = "";

            }
          }
          if(defined ($ptr->{HOUR}) && 0+$ptr->{HOUR} == 24) {
            $twentyfour = 1;  # next value uninteresting, only first counts.
          }
      	}
        push @event, $msg if($msg);
      }
#                                      0402000000000501090000
    } elsif($cmd eq "A410" && $p =~ m/^0402000000000(.)(..)(..)/) {
      my ($plist, $o1,    $v1) =
         (hex($1),hex($2),hex($3));
      my $msg;
      my @days = ("Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri");
      if($plist == 5) {
        $msg = sprintf("param-change: offset=%s, value=%s", $o1, $v1);
      	if($o1 == 1) { ### bitfield containing multiple values...
          $msg = "displayMode:temperature only" if ($v1 & 1) == 0;
          $msg = "displayMode:temperature and humidity" if ($v1 & 1) == 1;
          push @event, $msg if $msg;
          $msg = "displayTemp:actual" if ($v1 & 2) == 0;
          $msg = "displayTemp:setpoint" if ($v1 & 2) == 2;
          push @event, $msg if $msg;
          $msg = "displayTempUnit:celsius" if ($v1 & 4) == 0;
          $msg = "displayTempUnit:fahrenheit" if ($v1 & 4) == 4;
          push @event, $msg if $msg;
          $msg = "controlMode:manual" if ($v1 & 0x18) == 0;
          $msg = "controlMode:auto" if ($v1 & 0x18) == 8;
          $msg = "controlMode:central" if ($v1 & 0x18) == 0x10;
          $msg = "controlMode:party" if ($v1 & 0x18) == 0x18;
          push @event, $msg if $msg;
          my $day = $days[($v1 & 0xE0) - 0xD9 + 1];
          $msg = sprintf("decalcDay:%s", $day);

          # remember state for subsequent set operations
          $shash->{helper}{state251} = $v1;
        } elsif($o1 == 2) {
          $msg = "tempValveMode:Auto" if ($v1 & 0xC0) == 0;
          $msg = "tempValveMode:Closed" if ($v1 & 0xC0) == 0x40;
          $msg = "tempValveMode:Open" if ($v1 & 0xC0) == 0x80;
        }
      }
      push @event, $msg if $msg;
    }

    if($cmd eq "A001" && $p =~ m/^01080900(..)(..)/) {
      my (   $of,     $vep) = 
         (hex($1), hex($2));
      push @event, "ValveErrorPosition $dname: $vep %";
      push @event, "ValveOffset $dname: $of %";
    }

    if(($cmd eq "A410" && $p =~ m/^0602(..)........$/) ||
       ($cmd eq "A112" && $p =~ m/^0202(..)$/)) { # Set desired temp
      push @event, "desired-temp:" .sprintf("%0.1f", hex($1)/2);
    }

    if($cmd eq "8002" && $p =~ m/^0102(..)(....)/) { # Ack for fhem-command
      push @event, "desired-temp-ack:" .sprintf("%0.1f", hex($1)/2);
      # FIXME: following is needed, else a set won't show up.
      push @event, "desired-temp:" .sprintf("%0.1f", hex($1)/2);
    }

    CUL_HM_SendCmd($shash, "++8002$id${src}00",1,0)  # Send Ack
      if($id eq $dst && $cmd ne "8002");
      

  } elsif($model eq "HM-CC-VD") { ###################
    # CMD:8202 SRC:13F251 DST:15B50D 010100002A
    # status ACK to controlling HM-CC-TC
    if($cmd eq "8202" && $p =~ m/^(..)(..)(..)(..)/) {
      my (   $vp,     $st) =
         (hex($3), hex($4));
      $vp = int($vp)/2;   # valve position in %
      push @event, "actuator:$vp %";

      # Status-Byte Auswertung
      push @event, "motor:opening" if($st&0x10);
      push @event, "motor:closing" if($st&0x20);
      push @event, "motor:blocked" if($st&0x06) == 2;
      push @event, "motor:loose" if($st&0x06) == 4;
      push @event, "motor:adjusting range too small" if($st&0x06) == 6;
      push @event, "motor:ok" if($st&0x06) == 0;
      push @event, "battery:low" if($st&0x08);
      push @event, "battery:ok" if(($st&0x08) == 0);
    }

    # CMD:A010 SRC:13F251 DST:5D24C9 0401000000000509000A070000
    # status change report to paired central unit
    if($cmd eq "A010" && $p =~ m/^04010000000005(..)(..)(..)(..)/) {
      my (    $of,     $vep) = 
        (hex($3), hex($4));
      push @event, "valve error position:$vep %";
      push @event, "ValveOffset $dname: $of %";
    }

    CUL_HM_SendCmd($shash, "++8002$id${src}00",1,0)  # Send Ack
      if($id eq $dst && $cmd ne "8002");
  

  } elsif($st eq "KFM100" && $model eq "KFM-Sensor") { ###################

    if($p =~ m/.14(.)0200(..)(..)(..)/) {
      my ($k_cnt, $k_v1, $k_v2, $k_v3) = ($1,$2,$3,$4);
      my $v = 128-hex($k_v2);                  # FIXME: calibrate
      # $v = 256+$v if($v < 0);
      $v += 256 if(!($k_v3 & 1));
      push @event, "rawValue:$v";

      my $seq = hex($k_cnt);
      push @event, "Sequence:$seq";

      my $r2r = AttrVal($name, "rawToReadable", undef);
      if($r2r) {
        my @r2r = split("[ :]", $r2r);
        foreach(my $idx = 0; $idx < @r2r-2; $idx+=2) {
          if($v >= $r2r[$idx] && $v <= $r2r[$idx+2]) {
            my $f = (($v-$r2r[$idx])/($r2r[$idx+2]-$r2r[$idx]));
            my $cv = ($r2r[$idx+3]-$r2r[$idx+1])*$f + $r2r[$idx+1];
            my $unit = AttrVal($name, "unit", "");
            $unit = " $unit" if($unit);
            push @event, "state:$cv $unit";
            push @event, "content:$cv $unit";
            last;
          }
        }
      } else {
        push @event, "state:$v";
      }

    }

    
  } elsif($st eq "switch" || ############################################
          $st eq "dimmer" ||
          $st eq "blindActuator") {

    if($p =~ m/^(0.)(..)(..).0/
       && $cmd ne "A010"
       && $cmd ne "A002") {
      my $msgType = $1;
      my $chn = $2;

      # Multi-channel device: Switch to the shadow source hash
      if($chn ne "01" && $chn ne "00") {
        my $cSrc = "$src$chn";
        if($modules{CUL_HM}{defptr}{$cSrc}) {
          $shash = $modules{CUL_HM}{defptr}{$cSrc};
          $name = $shash->{NAME}
        }
      }

      my $val = hex($3)/2;
      $val = ($val == 100 ? "on" : ($val == 0 ? "off" : "$val %"));
      my $msg = "unknown";
      $msg = "deviceMsg" if($msgType =~ m/0./);
      $msg = "powerOn"   if($msgType =~ m/06/ && $chn eq "00");
      push @event, "$msg:$val$target";
      push @event, "state:$val";
    }

  } elsif($st eq "remote" || $st eq "pushButton") { #######################

    if($cmd =~ m/^..4./ && $p =~ m/^(..)(..)$/) {
      my ($button, $bno) = (hex($1), hex($2));

      my $btn = int((($button&0x3f)+1)/2);
      my $state = ($button&1 ? "off" : "on") . ($button & 0x40 ? "Long" : "");

      push @event, "state:Btn$btn $state$target";
      if($id eq $dst && $cmd ne "8002") {  # Send Ack
        CUL_HM_SendCmd($shash, "++8002".$id.$src."0101".    # Send Ack.
                ($state =~ m/on/?"C8":"00")."00", 1, 0);
      }

    }

  } elsif($st eq "motionDetector") { #####################################

    # Code with help of Bassem
    my $state;
    if($cmd =~ m/^..10/ && $p =~ m/^0601(..)(..)/) {
      ($state, undef) = ($1, $2);
      push @event, "brightness:".hex($state);
      push @event, "state:alive";
    }
    if($cmd =~ m/^..41/ && $p =~ m/^01(......)/) {
      $state = $1;
      push @event, "state:motion";
      push @event, "motion:on$target"; #added peterp
    }
    if($cmd =~ m/^.610/) {
      push @event, "cover:closed" if($p =~ m/^0601..00$/);         # By peterp
      push @event, "cover:open"   if($p =~ m/^0601..0E$/);
    }

    CUL_HM_SendCmd($shash, "++8002".$id.$src."0101${state}00",1,0)
      if($id eq $dst && $cmd ne "8002");  # Send Ack


  } elsif($st eq "smokeDetector") { #####################################

    if($p =~ m/01..C8/) {
      push @event, "state:on";
      push @event, "smoke_detect:on$target";

    } elsif($p =~ m/^01..01$/) {
      push @event, "state:all-clear";   # Entwarnung

    } elsif($p =~ m/^06010.00$/) {
      push @event, "state:alive";

    } elsif($p =~ m/^00(..)$/) {
      push @event, "test:$1";

    }

    $p =~ m/^....(..)$/;
    my $lst = defined($1) ? $1 : "00";
    CUL_HM_SendCmd($shash, "++8002".$id.$src."0101".$lst."00",1,0)  # Send Ack
          if($id eq $dst);
    push @event, "unknownMsg:$p" if(!@event);

  } elsif($st eq "threeStateSensor") { #####################################

    $p =~ m/^....(..)$/;
    my $lst = defined($1) ? $1 : "00";

    if($p =~ m/^0601000E$/) {
      push @event, "alive:yes";

    } elsif($p =~ m/^0601..00$/) {
      push @event, "cover:closed";
      push @event, "alive:yes";

    } elsif($p =~ m/^0601..0E$/) {
      push @event, "cover:open";
      push @event, "state:sabotage";

    } else {

      # Multi-channel device: Switch to the shadow source hash
      # for the HM-SCI-3-FM
      my $chn = $2 if($p =~ m/^(..)(..)/);
      if($chn && $chn ne "01" && $chn ne "00") {
        my $sshash = $modules{CUL_HM}{defptr}{"$src$chn"};
        $shash = $sshash if($sshash);
        $name = $shash->{NAME};
      }

      my %txt;
      %txt = ("C8"=>"open", "64"=>"tilted", "00"=>"closed");
      %txt = ("C8"=>"wet",  "64"=>"damp",   "00"=>"dry")  # by peterp
                   if($model eq "HM-SEC-WDS");

      if($txt{$lst}) {
        push @event, "state:$txt{$lst}$target";

      } else {
        $lst = "00"; # for the ack

      }

    }

    CUL_HM_SendCmd($shash, "++8002".$id.$src."0101".$lst."00",1,0)  # Send Ack
      if($id eq $dst);
    push @event, "unknownMsg:$p" if(!@event);


  } elsif($model eq "HM-WDC7000") { #### $st=THSensor with additional pressure
  
    if($p =~ m/^(....)(..)(....)$/) {
      my ($t, $h, $ap) = ($1, $2, $3);
      $t = hex($t)/10;
      $t -= 3276.8 if($t > 1638.4);
      $h = hex($h);
      $ap = hex($ap);
      push @event, "state:T: $t H: $h AP: $ap";
      push @event, "temperature:$t";
      push @event, "humidity:$h";
      push @event, "airpress:$ap";

    } elsif($p =~ m/^(....)$/) {
      my $t = $1;
      $t = hex($t)/10;
      $t -= 3276.8 if($t > 1638.4);
      push @event, "temperature:$t";

    }
 
  } elsif($model eq "HM-CC-SCD") { ##########################################
  
    if($p =~ m/^....00$/) {
    	push @event, "state:normal";
    	
    } elsif($p =~ m/^....64$/) {
    	push @event, "state:added";
    	
    } elsif($p =~ m/^....C8$/) {
    	push @event, "state:added_strong";
    	
    }


  } elsif($st eq "THSensor") { ##########################################

    if($p =~ m/^(....)(..)$/) {
      my ($t, $h) = ($1, $2);
      $t = hex($t);
      $t -= 32768 if($t > 16384);
      $t = sprintf("%0.1f", $t/10);
      $h = hex($h);
      push @event, "state:T: $t H: $h";
      push @event, "temperature:$t";
      push @event, "humidity:$h";

    } elsif($p =~ m/^(....)$/) {
      my $t = $1;
      $t = hex($t)/10;
      $t -= 3276.8 if($t > 1638.4);
      push @event, "temperature:$t";

    }

  } elsif($st eq "winMatic") {  ####################################
    
    if($cmd eq "A410" && $p =~ m/^0601(..)(..)/) {
      my ($lst, $flg) = ($1, $2);
           if($lst eq "C8" && $flg eq "00") { push @event, "contact:tilted";
      } elsif($lst eq "FF" && $flg eq "00") { push @event, "contact:closed";
      } elsif($lst eq "00" && $flg eq "10") { push @event, "contact:movement_tilted";
      } elsif($lst eq "00" && $flg eq "20") { push @event, "contact:movement_closed";
      } elsif($lst eq "FF" && $flg eq "10") { push @event, "contact:lock_on";
      } elsif($lst eq "00" && $flg eq "30") { push @event, "contact:open";
      }
      CUL_HM_SendCmd($shash, "++8002".$id.$src."0101".$lst."00",1,0)  # Send Ack
        if($id eq $dst);
    }

    if($cmd eq "A010" && $p =~ m/^0287(..)89(..)8B(..)/) {
      my ($air, undef, $course) = ($1, $2, $3);
      push @event, "airing:".
      ($air eq "FF" ? "inactiv" : CUL_HM_decodeTime8($air));
      push @event, "course:".($course eq "FF" ? "tilt" : "close");

      CUL_HM_SendCmd($shash, "++8002".$id.$src."00",1,0)  # Send Ack
        if($id eq $dst);
    }

    if($cmd eq "A010" &&
       $p =~ m/^0201(..)03(..)04(..)05(..)07(..)09(..)0B(..)0D(..)/) {

      my ($flg1, $flg2, $flg3, $flg4, $flg5, $flg6, $flg7, $flg8) =
         ($1, $2, $3, $4, $5, $6, $7, $8);
      push @event, "airing:".($flg5 eq "FF" ? "inactiv" : CUL_HM_decodeTime8($flg5));
      push @event, "contact:tesed";
      CUL_HM_SendCmd($shash, "++8002".$id.$src."00",1,0)  # Send Ack
        if($id eq $dst);
   } 

  }

  #push @event, "unknownMsg:$p" if(!@event);
  push @event, "unknownMsg:($cmd) $p" if(!@event);

  my @changed;
  for(my $i = 0; $i < int(@event); $i++) {
    next if($event[$i] eq "");
    if($shash->{lastMsg} && $shash->{lastMsg} eq $msgX) {
      Log GetLogLevel($name,4), "CUL_HM $name dup mesg";
      next;
    }

    my ($vn, $vv) = split(":", $event[$i], 2);
    Log GetLogLevel($name,2), "CUL_HM $name $vn:$vv" if($vn eq "unknown");

    if($vn eq "state") {

      if($shash->{cmdSent} && $shash->{cmdSent} eq $vv) {
        delete($shash->{cmdSent}); # Skip second "on/off" after our own command

      } else {
        $shash->{STATE} = $vv;
        push @changed, $vv;
      }

    } else {
      push @changed, "$vn: $vv";

    }

    $shash->{READINGS}{$vn}{TIME} = $tn;
    $shash->{READINGS}{$vn}{VAL} = $vv;
  }
  $shash->{CHANGED} = \@changed;
  
  $shash->{lastMsg} = $msgX;

  if($shash->{ackWaiting}) {
    delete($shash->{ackWaiting});
    delete($shash->{ackCmdSent});
    RemoveInternalTimer($shash);
  }

  return $name;
}

###################################
sub
CUL_HM_TC_missing($)
{
  #
  # find out missing configuration parameters
  #
  my ($hash) = @_ ;
  my $missingSettings = "please complete settings for ";
  $missingSettings .= "displayTemp " unless($hash->{READINGS}{displayTemp}{VAL});
  $missingSettings .= "displayTempUnit " unless($hash->{READINGS}{displayTempUnit}{VAL});
  $missingSettings .= "displayMode " unless($hash->{READINGS}{displayMode}{VAL});
  $missingSettings .= "controlMode " unless($hash->{READINGS}{controlMode}{VAL});
  $missingSettings .= "decalcDay " unless($hash->{READINGS}{decalcDay}{VAL});
  return $missingSettings;
}

my %culHmGlobalSets = (
  raw      => "data ...",
  reset    => "",
  pair     => "",
  unpair   => "",
  sign     => "[on|off]",
  statusRequest  => "",
);
my %culHmSubTypeSets = (
  switch =>
        { "on-for-timer"=>"sec", on=>"", off=>"", toggle=>"" },
  dimmer =>
        { "on-for-timer"=>"sec", on=>"", off=>"", toggle=>"", pct=>"" },
  blindActuator=>
        { "on-for-timer"=>"sec", on =>"", off=>"", toggle=>"", pct=>"" },
  remote =>
        { text => "<btn> [on|off] <txt1> <txt2>",
          devicepair => "<btnNumber> device", },
  winMatic =>
        { matic  => "<btn>",
          read   => "<btn>",
          keydef => "<btn> <txt1> <txt2>",
          create => "<txt>" },
);
my %culHmModelSets = (
  "HM-CC-TC"=>
        { "day-temp"     => "temp",
          "night-temp"   => "temp",
          "party-temp"   => "temp",
          "desired-temp" => "temp", # does not work
          "tempListSat"=> "HH:MM temp ...",
          "tempListSun"=> "HH:MM temp ...",
          "tempListMon"=> "HH:MM temp ...",
          "tempListTue"=> "HH:MM temp ...",
          "tempListThu"=> "HH:MM temp ...",
          "tempListWed"=> "HH:MM temp ...",
          "tempListFri"=> "HH:MM temp ...",
          "displayMode"  => "[temp-only|temp-hum]",
          "displayTemp"  => "[actual|setpoint]",
          "displayTempUnit" => "[celsius|fahrenheit]",
          "controlMode"  => "[manual|auto|central|party]",
          "decalcDay"    => "day",
        },
);

###################################
sub
CUL_HM_Set($@)
{
  my ($hash, @a) = @_;
  my ($ret, $tval, $rval); #added rval for ramptime by unimatrix

  return "no set value specified" if(@a < 2);

  my $name = $hash->{NAME};
  my $st = AttrVal($name, "subType", "");
  my $md = AttrVal($name, "model", "");
  my $cmd = $a[1];
  my $dst = $hash->{DEF};
  my $chn = "01";

  if(length($dst) == 8) {       # shadow switch device for multi-channel switch
    $chn = substr($dst, 6, 2);
    $dst = substr($dst, 0, 6);
  }

  my $h = $culHmGlobalSets{$cmd};
  $h = $culHmSubTypeSets{$st}{$cmd} if(!defined($h) && $culHmSubTypeSets{$st});
  $h = $culHmModelSets{$md}{$cmd}   if(!defined($h) && $culHmModelSets{$md});
  my @h;
  @h = split(" ", $h) if($h);

  my $isSender = (AttrVal($name,"hmClass","") eq "sender" || $md eq "HM-CC-TC");

  # HM-CC-TC control mode bits for day encoding
  my %tc_day2bits = ( "Sat"=>"0", "Sun"=>"0x20", "Mon"=>"0x40",
        	      "Tue"=>"0x60", "Wed"=>"0x80", "Thu"=>"0xA0",
        	      "Fri"=>"0xC0");

  if(!defined($h) && defined($culHmSubTypeSets{$st}{pct}) && $cmd =~ m/^\d+/) {
    $cmd = "pct";

  } elsif(!defined($h)) {
    my $usg = "Unknown argument $cmd, choose one of " .
                 join(" ",sort keys %culHmGlobalSets);
    $usg .= " ". join(" ",sort keys %{$culHmSubTypeSets{$st}})
                  if($culHmSubTypeSets{$st});
    $usg .= " ". join(" ",sort keys %{$culHmModelSets{$md}})
                  if($culHmModelSets{$md});
    my $pct = join(" ", (0..100));
    $usg =~ s/ pct/ $pct/;
    return $usg;

  } elsif($h eq "" && @a != 2) {
    return "$cmd requires no parameters";
    
  } elsif($h !~ m/\.\.\./ && @h != @a-2) {
    return "$cmd requires parameter: $h";

  }

  my $id = CUL_HM_Id($hash->{IODev});
  my $state = join(" ", @a[1..(int(@a)-1)]);

  if($cmd eq "raw") {  ##################################################
    return "Usage: set $a[0] $cmd data [data ...]" if(@a < 3);
    for (my $i = 2; $i < @a; $i++) {
      CUL_HM_PushCmdStack($hash, $a[$i]);
    }
    $state = "";

  } elsif($cmd eq "reset") { ############################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++A011%s%s0400", $id,$dst));

  } elsif($cmd eq "pair") { #############################################
    return "pair is not enabled for this type of device, ".
                "use set <IODev> hmPairForSec"
        if($isSender);

    my $serialNr = AttrVal($name, "serialNr", undef);
    return "serialNr is not set" if(!$serialNr);
    CUL_HM_PushCmdStack($hash,
        sprintf("++A401%s000000010A%s", $id, unpack("H*",$serialNr)));
    $hash->{hmPairSerial} = $serialNr;

  } elsif($cmd eq "unpair") { ###########################################
    CUL_HM_pushConfig($hash, $id, $dst, 0, 0, "02010A000B000C00");

  } elsif($cmd eq "sign") { ############################################
    CUL_HM_pushConfig($hash, $id, $dst, $chn, $chn,
                    "08" . ($a[2] eq "on" ? "01":"02"));

  } elsif($cmd eq "statusRequest") { ####################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s%s0E", $id,$dst, $chn));

  } elsif($cmd eq "on") { ###############################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++A011%s%s02%sC80000", $id,$dst, $chn));

  } elsif($cmd eq "off") { ##############################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++A011%s%s02%s000000", $id,$dst,$chn));

  } elsif($cmd eq "on-for-timer") { #####################################
    ($tval,$ret) = CUL_HM_encodeTime16($a[2]);
    Log 1, $ret if($ret);
    CUL_HM_PushCmdStack($hash,
        sprintf("++A011%s%s02%sC80000%s", $id,$dst, $chn, $tval));

  } elsif($cmd eq "toggle") { ###########################################
    $hash->{toggleIndex} = 1 if(!$hash->{toggleIndex});
    $hash->{toggleIndex} = (($hash->{toggleIndex}+1) % 128);
    CUL_HM_PushCmdStack($hash, sprintf("++A03E%s%s%s40%s%02X", $id, $dst,
                                      $dst, $chn, $hash->{toggleIndex}));

  } elsif($cmd eq "pct") { ##############################################
    $a[1] = 100 if ($a[1] > 100);
    if(@a == 2) {$tval="";$rval="0000";}
    if(@a > 2) {
      ($tval,$ret) = CUL_HM_encodeTime16($a[2]);
      Log 1, $ret if($ret);
    }
    if(@a > 3) {
      ($rval,$ret) = CUL_HM_encodeTime16($a[3]);
      Log 1, $ret if($ret);
    }
    my $cmd = sprintf("++A011%s%s02%s%02X%s%s", $id, $dst, $chn, $a[1]*2,$rval,$tval);
    CUL_HM_PushCmdStack($hash, $cmd);

  } elsif($cmd eq "text") { #############################################
    $state = "";
    return "$a[2] is not a button number" if($a[2] !~ m/^\d$/ || $a[2] < 1);
    return "$a[3] is not on or off" if($a[3] !~ m/^(on|off)$/);
    my $bn = $a[2]*2-($a[3] eq "on" ? 0 : 1);


    my ($l1, $l2, $s);     # Create CONFIG_WRITE_INDEX string
    $l1 = $a[4] . "\x00";
    $l1 = substr($l1, 0, 13);
    $s = 54;
    $l1 =~ s/(.)/sprintf("%02X%02X",$s++,ord($1))/ge;

    $l2 = $a[5] . "\x00";
    $l2 = substr($l2, 0, 13);
    $s = 70;
    $l2 =~ s/(.)/sprintf("%02X%02X",$s++,ord($1))/ge;
    $l1 .= $l2;

    CUL_HM_pushConfig($hash, $id, $dst, $bn, 1, $l1);

  } elsif($cmd =~ m/^displayMode$/) { ###############################
    my $tcnf;
    if($hash->{helper}{state251}) {
      $tcnf = $hash->{helper}{state251};
      if($a[2] eq "temp-only") {
        $tcnf &= 0xFE;
      } else {
        $tcnf |= 0x1;
      }
    } else {
      # look if index 1 subfields are complete, construct state251,
      # if incomplete, issue errormessage, set reading and wait for
      # completion of state251
      if($hash->{READINGS}{displayTemp}{VAL} &&
         $hash->{READINGS}{displayTempUnit}{VAL} &&
         $hash->{READINGS}{controlMode}{VAL} &&
         $hash->{READINGS}{decalcDay}{VAL}) {
        
        $tcnf = 0;
        $tcnf |= 1 if($a[2] ne "temp-only");	# the parameter actually to be changed
        $tcnf |= 2 if($hash->{READINGS}{displayTemp}{VAL} eq "setpoint");
        $tcnf |= 4 if($hash->{READINGS}{displayTempUnit}{VAL} eq "fahrenheit");
        $tcnf |= 8 if($hash->{READINGS}{controlMode}{VAL} eq "auto");
        $tcnf |= 0x10 if($hash->{READINGS}{controlMode}{VAL} eq "central");
        $tcnf |= 0x18 if($hash->{READINGS}{controlMode}{VAL} eq "party");
        my $dbit = $tc_day2bits{$hash->{READINGS}{decalcDay}{VAL}};
        $tcnf |= $dbit;
      } else {
        $hash->{READINGS}{$cmd}{TIME} = TimeNow();
        $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
        return CUL_HM_TC_missing($hash);
      }
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2, 5, "01$tcnf");
    $hash->{helper}{state251} = $tcnf;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
    return;

  } elsif($cmd =~ m/^displayTemp$/) { ###############################
    my $tcnf;
    if($hash->{helper}{state251}) {
      $tcnf = $hash->{helper}{state251};
      if($a[2] eq "setpoint") {
        $tcnf &= 0xFD;
      } else {
        $tcnf |= 0x2;
      }
    } else {
      # look if index 1 subfields are complete, construct state251,
      # if incomplete, issue errormessage, set reading and wait for
      # completion of state251
      if($hash->{READINGS}{displayMode}{VAL} &&
         $hash->{READINGS}{displayTempUnit}{VAL} &&
         $hash->{READINGS}{controlMode}{VAL} &&
         $hash->{READINGS}{decalcDay}{VAL}) {
        
        $tcnf = 0;
        $tcnf |= 1 if($hash->{READINGS}{displayMode}{VAL} ne "temp-only");
        $tcnf |= 2 if($a[2] ne "setpoint");	# the parameter actually to be changed
        $tcnf |= 4 if($hash->{READINGS}{displayTempUnit}{VAL} eq "fahrenheit");
        $tcnf |= 8 if($hash->{READINGS}{controlMode}{VAL} eq "auto");
        $tcnf |= 0x10 if($hash->{READINGS}{controlMode}{VAL} eq "central");
        $tcnf |= 0x18 if($hash->{READINGS}{controlMode}{VAL} eq "party");
        my $dbit = $tc_day2bits{$hash->{READINGS}{decalcDay}{VAL}};
        $tcnf |= $dbit;
      } else {
        $hash->{READINGS}{$cmd}{TIME} = TimeNow();
        $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
        return CUL_HM_TC_missing($hash);
      }
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2, 5, "01$tcnf");
    $hash->{helper}{state251} = $tcnf;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
    return;

  } elsif($cmd =~ m/^displayTempUnit$/) { ###############################
    my $tcnf;
    if($hash->{helper}{state251}) {
      $tcnf = $hash->{helper}{state251};
      if($a[2] eq "celsius") {
        $tcnf &= 0xFD;
      } else {
        $tcnf |= 0xFB;
      }
    } else {
      # look if index 1 subfields are complete, construct state251,
      # if incomplete, issue errormessage, set reading and wait for
      # completion of state251
      if($hash->{READINGS}{displayTemp}{VAL} &&
         $hash->{READINGS}{displayMode}{VAL} &&
         $hash->{READINGS}{controlMode}{VAL} &&
         $hash->{READINGS}{decalcDay}{VAL}) {
        
        $tcnf = 0;
        $tcnf |= 1 if($hash->{READINGS}{displayMode}{VAL} ne "temp-only");
        $tcnf |= 2 if($hash->{READINGS}{displayTemp}{VAL} eq "setpoint");
        $tcnf |= 4 if($a[2] ne "fahrenheit");	# the parameter actually to be changed
        $tcnf |= 8 if($hash->{READINGS}{controlMode}{VAL} eq "auto");
        $tcnf |= 0x10 if($hash->{READINGS}{controlMode}{VAL} eq "central");
        $tcnf |= 0x18 if($hash->{READINGS}{controlMode}{VAL} eq "party");
        my $dbit = $tc_day2bits{$hash->{READINGS}{decalcDay}{VAL}};
        $tcnf |= $dbit;
      } else {
        $hash->{READINGS}{$cmd}{TIME} = TimeNow();
        $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
        return CUL_HM_TC_missing($hash);
      }
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2, 5, "01$tcnf");
    $hash->{helper}{state251} = $tcnf;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
    return;

  } elsif($cmd =~ m/^controlMode$/) { ###############################
    my $tcnf;
    if($hash->{helper}{state251}) {
      $tcnf = $hash->{helper}{state251};
      $tcnf &= 0xE7;		# blank out the control mode bits (equals mode manual)
      $tcnf |= 0x08 if($a[2] eq "auto");
      $tcnf |= 0x10 if($a[2] eq "central");
      $tcnf |= 0x18 if($a[2] eq "party");
    } else {
      # look if index 1 subfields are complete, construct state251,
      # if incomplete, issue errormessage, set reading and wait for
      # completion of state251
      if($hash->{READINGS}{displayTemp}{VAL} &&
         $hash->{READINGS}{displayMode}{VAL} &&
         $hash->{READINGS}{displayTempUnit}{VAL} &&
         $hash->{READINGS}{decalcDay}{VAL}) {
        
        $tcnf = 0;
        $tcnf |= 1 if($hash->{READINGS}{displayMode}{VAL} ne "temp-only");
        $tcnf |= 2 if($hash->{READINGS}{displayTemp}{VAL} eq "setpoint");
        $tcnf |= 4 if($hash->{READINGS}{displayTempUnit}{VAL} eq "fahrenheit");
        $tcnf |= 8 if($a[2] eq "auto");	# the parameter actually to be changed
        $tcnf |= 0x10 if($a[2] eq "central");
        $tcnf |= 0x18 if($a[2] eq "party");
        my $dbit = $tc_day2bits{$hash->{READINGS}{decalcDay}{VAL}};
        $tcnf |= $dbit;
      } else {
        $hash->{READINGS}{$cmd}{TIME} = TimeNow();
        $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
        return CUL_HM_TC_missing($hash);
      }
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2, 5, "01$tcnf");
    $hash->{helper}{state251} = $tcnf;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
    return;

  } elsif($cmd =~ m/^decalcDay$/) { ###############################
    my $tcnf;
    my $dbit = $tc_day2bits{$a[2]};

    if($hash->{helper}{state251}) {
      $tcnf = $hash->{helper}{state251};
      $tcnf &= 0x1F;		# blank out the decalc day bits (equals Sat)
      $tcnf |= $dbit;
    } else {
      # look if index 1 subfields are complete, construct state251,
      # if incomplete, issue errormessage, set reading and wait for
      # completion of state251
      if($hash->{READINGS}{displayTemp}{VAL} &&
         $hash->{READINGS}{displayMode}{VAL} &&
         $hash->{READINGS}{displayTempUnit}{VAL} &&
         $hash->{READINGS}{controlMode}{VAL}) {
        
        $tcnf = 0;
        $tcnf |= 1 if($hash->{READINGS}{displayMode}{VAL} ne "temp-only");
        $tcnf |= 2 if($hash->{READINGS}{displayTemp}{VAL} eq "setpoint");
        $tcnf |= 4 if($hash->{READINGS}{displayTempUnit}{VAL} eq "fahrenheit");
        $tcnf |= 8 if($hash->{READINGS}{controlMode}{VAL} eq "auto");
        $tcnf |= 0x10 if($hash->{READINGS}{controlMode}{VAL} eq "central");
        $tcnf |= 0x18 if($hash->{READINGS}{controlMode}{VAL} eq "party");
        $tcnf |= $dbit;	# the parameter actually to be changed
      } else {
        $hash->{READINGS}{$cmd}{TIME} = TimeNow();
        $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
        return CUL_HM_TC_missing($hash);
      }
    }
    CUL_HM_pushConfig($hash, $id, $dst, 2, 5, "01$tcnf");
    $hash->{helper}{state251} = $tcnf;
    $hash->{READINGS}{$cmd}{TIME} = TimeNow();
    $hash->{READINGS}{$cmd}{VAL} = sprintf("%s", $a[2]);
    return;

  } elsif($cmd =~ m/^desired-temp$/) { ##################
    my $temp = CUL_HM_convTemp($a[2]);
    return $temp if(length($temp) > 2);
    CUL_HM_PushCmdStack($hash, "++A112$id$dst");     # Wakeup...
    CUL_HM_PushCmdStack($hash,
                sprintf("++A011%s%s0202%s", $id,$dst,$temp));

  } elsif($cmd =~ m/^(day|night|party)-temp$/) { ##################
    my %tt = (day=>"03", night=>"04", party=>"06");
    my $tt = $tt{$1};
    my $temp = CUL_HM_convTemp($a[2]);
    return $temp if(length($temp) > 2);
    CUL_HM_PushCmdStack($hash, "++A112$id$dst");     # Wakeup...
    CUL_HM_pushConfig($hash, $id, $dst, 2, 5, "$tt$temp");      # List 5

  } elsif($cmd =~ m/^tempList(...)/) { ##################################
    my %day2off = ( "Sat"=>"5 0B", "Sun"=>"5 3B", "Mon"=>"5 6B",
                    "Tue"=>"5 9B", "Wed"=>"5 CB", "Thu"=>"6 01",
                    "Fri"=>"6 31");
    my $wd = $1;
    my ($list,$addr) = split(" ", $day2off{$wd});
    $addr = hex($addr);

    return "To few arguments"                   if(@a < 4);
    return "To many arguments, max is 24 pairs" if(@a > 50);
    return "Bad format, use HH:MM TEMP ..."     if(@a % 2);
    return "Last time spec must be 24:00"       if($a[@a-2] ne "24:00");
    my $data = "";
    my $msg = "";
    for(my $idx = 2; $idx < @a; $idx += 2) {
      return "$a[$idx] is not in HH:MM format"
                                if($a[$idx] !~ m/^([0-2]\d):([0-5]\d)/);
      my ($h, $m) = ($1, $2);
      my $temp = CUL_HM_convTemp($a[$idx+1]);
      return $temp if(length($temp) > 2);
      $data .= sprintf("%02X%02X%02X%s", $addr, $h*6+($m/10), $addr+1, $temp);
      $addr += 2;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{HOUR} = $h;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{MINUTE} = $m;
      $hash->{TEMPLIST}{$wd}{($idx-2)/2}{TEMP} = $a[$idx+1];
      $msg .= sprintf(" %02d:%02d %.1f", $h, $m, $a[$idx+1]);
    }
    CUL_HM_PushCmdStack($hash, "++A112$id$dst");     # Wakeup...
    CUL_HM_pushConfig($hash, $id, $dst, 2, $list, $data);

    my $vn = "tempList$wd";
    $hash->{READINGS}{$vn}{TIME} = TimeNow();
    $hash->{READINGS}{$vn}{VAL} = $msg;

  } elsif($cmd eq "matic") { ##################################### 
    # Trigger pre-programmed action in the winmatic. These actions must be
    # programmed via the original software.

    CUL_HM_PushCmdStack($hash,
        sprintf("++B03E%s%s%s40%02X%s", $id, $dst, $id, $a[2], $chn));

  } elsif($cmd eq "create") { ###################################
    CUL_HM_PushCmdStack($hash, 
        sprintf("++B001%s%s0101%s%02X%s", $id, $dst, $id, $a[2], $chn));
    CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s0104%s%02X%s", $id, $dst, $id, $a[2], $chn));

  } elsif($cmd eq "read") { ###################################
    CUL_HM_PushCmdStack($hash,
        sprintf("++B001%s%s0104%s%02X03", $id, $dst, $id, $a[2]));

  } elsif($cmd eq "keydef") { #####################################

    my $cmd;
    if ($a[3] eq "tilt") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2],"0B220D838B228D83");

    } elsif ($a[3] eq "close") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2], "0B550D838B558D83");

    } elsif ($a[3] eq "closed") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2], "0F008F00");

    } elsif ($a[3] eq "bolt") {
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2], "0FFF8FFF");

    } elsif ($a[3] eq "delete") {
      $cmd = sprintf("++B001%s%s0102%s%02X%s", $id, $dst, $id, $a[2], $chn);

    } elsif ($a[3] eq "speedclose") {
      $cmd = $a[4]*2;
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2],
                                sprintf("23%02XA3%02X", $cmd, $cmd));

    } elsif ($a[3] eq "speedtilt") {
      $cmd = $a[4]*2;
      $cmd = CUL_HM_maticFn($hash, $id, $dst, $a[2],
                                sprintf("22%02XA2%02X", $cmd, $cmd));
    } else {
      return "unknown argument $a[3]";

    }
    CUL_HM_PushCmdStack($hash, $cmd) if($cmd);

  } elsif($cmd eq "devicepair") { #####################################
    return "$a[2] is not a button number" if($a[2] !~ m/^\d$/ || $a[2] < 1);
    my $b1 = sprintf("%02X", $a[2]*2-1);
    my $b2 = sprintf("%02X", $a[2]*2);
    
    my $dhash = $defs{$a[3]};
    return "$a[3] is not a known fhem device" if(!$dhash);
    return "$a[3] is not a CUL_HM device" if($dhash->{TYPE} ne "CUL_HM");

    my $dst2 = $dhash->{DEF};
    my $chn2 = "01";
    if(length($dst2) == 8) {     # shadow switch device for multi-channel switch
      $chn2 = substr($dst2, 6, 2);
      $dst2 = substr($dst2, 0, 6);
      $dhash = $modules{CUL_HM}{defptr}{$dst2};
    }

    # First the remote (one loop for on, one for off)
    for(my $i = 1; $i <= 2; $i++) {
      my $b = ($i==1 ? $b1 : $b2);

      # PEER_ADD, START, WRITE_INDEX, END
      CUL_HM_PushCmdStack($hash, "++A001${id}${dst}${b}01${dst2}${chn2}00");
      CUL_HM_PushCmdStack($hash, "++A001${id}${dst}${b}05${dst2}${chn2}04");
      CUL_HM_PushCmdStack($hash, "++A001${id}${dst}${b}080100");
      CUL_HM_PushCmdStack($hash, "++A001${id}${dst}${b}06");
    }

    # Now the switch: PEER_ADD, PARAM_REQ:on, PARAM_REQ:off
    CUL_HM_PushCmdStack($dhash, "++A001${id}${dst2}${chn2}01${dst}${b2}${b1}");
    CUL_HM_PushCmdStack($dhash, "++A001${id}${dst2}${chn2}04${dst}${b1}03");
    CUL_HM_PushCmdStack($dhash, "++A001${id}${dst2}${chn2}04${dst}${b2}03");
    $hash = $dhash; # Exchange the hash, as the switch is always alive.
    $isSender=0;    # the other device is a switch. ahem.

  }

  $hash->{STATE} = $state if($state);
  Log GetLogLevel($name,2), "CUL_HM set $name " . join(" ", @a[1..$#a]);

  CUL_HM_ProcessCmdStack($hash) if(!$isSender);
  return "";
}


###################################
# A pairing between rrrrrr (remote) and ssssss (switch) looks like the
# following (nn and ff is the index of the on and off button):
# 1A CF 84 00 rrrrrr 000000 10 0060 serialnumberxxxxxxxx 40 04 nnff
# 1A 66 A0 00 ssssss rrrrrr 19 0011 serialnumberxxxxxxxx 10 01 0100
# 0A D0 80 02 rrrrrr ssssss 00
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
  my ($name, $hash, $len,$msgcnt,$cmd,$src,$dst,$p) = @_;
  my $iohash = $hash->{IODev};
  my $id = CUL_HM_Id($iohash);
  my $l4 = GetLogLevel($name,4);
  my ($idstr, $s) = ($id, 0xA);
  $idstr =~ s/(..)/sprintf("%02X%s",$s++,$1)/ge;

  my $stc = substr($p, 26, 2);        # subTypeCode
  my $model = substr($p, 2, 4);
  my $dp = $culHmDevProps{$stc};

  $model = $culHmModel{$model} ? $culHmModel{$model} :"unknown";
  my $serNo = pack('H*', substr($p, 6, 20));
  my $devInfo = substr($p,28);

  $attr{$name}{model}    = $model;
  $attr{$name}{subType}  = $dp ? $dp->{st} : "unknown";
  $attr{$name}{hmClass}  = $dp ? $dp->{cl} : "unknown";
  $attr{$name}{serialNr} = $serNo;
  $attr{$name}{firmware} = 
        sprintf("%d.%d", hex(substr($p,0,1)),hex(substr($p,1,1)));
  $attr{$name}{devInfo}  = $devInfo;
  my $stn = $attr{$name}{subType};    # subTypeName
  my $stt = $stn eq "unknown" ? "subType unknown" : "is a $stn";

  Log GetLogLevel($name,2),
        "CUL_HM pair: $name $stt, model $model serialNr $serNo";

  # Create shadow device for multi-channel
  if(($stn eq "switch" || $stn eq "threeStateSensor") &&
    $devInfo =~ m,(..)(..)(..), ) {
    my ($b1, $b2, $b3) = (hex($1)&0xf, hex($2), $3);
    for(my $i = $b2+1; $i<=$b1; $i++) {
      my $nSrc = sprintf("%s%02X", $src, $i);
      if(!defined($modules{CUL_HM}{defptr}{$nSrc})) {
        delete($defs{"global"}{INTRIGGER});    # Hack
        DoTrigger("global",  "UNDEFINED ${name}_CHN_$i CUL_HM $nSrc");
      }
    }
  }

  # Abort if we are not authorized
  if($dst eq "000000") {
    if(!$iohash->{hmPair} &&
       (!$iohash->{hmPairSerial} || $iohash->{hmPairSerial} ne $serNo)) {
      Log GetLogLevel($name,2),
        $iohash->{NAME}. " pairing (hmPairForSec) not enabled";
      return "";
    }

  } elsif($dst ne $id) {
    return "" ;

  } elsif($cmd eq "0400") {     # WDC7000
    return "" ;

  } elsif($iohash->{hmPairSerial}) {
    delete($iohash->{hmPairSerial});

  }

  my $chn = 0;
  #$chn = hex($2) if($devInfo =~ m,(..)(..), && $stn eq "remote");
  CUL_HM_pushConfig($hash, $id, $src, $chn, 0, "0201$idstr");
  CUL_HM_SendCmd($hash, shift @{$hash->{cmdStack}}, 1, 1);

  return "";
}
    
###################################
sub
CUL_HM_SendCmd($$$$)
{
  my ($hash, $cmd, $sleep, $waitforack) = @_;
  my $io = $hash->{IODev};

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
  $cmd = sprintf("As%02X%02X%s", length($cmd2)/2+1, $mn, $cmd2);
  IOWrite($hash, "", $cmd);
  if($waitforack) {
    my $iohash = $hash->{IODev};
    if($iohash && $iohash->{TYPE} ne "HMLAN") {
      $hash->{ackWaiting} = $cmd;
      $hash->{ackCmdSent} = 1;
      my $off = 0.5;
      $off += 0.15*int(@{$iohash->{QUEUE}}) if($iohash->{QUEUE});
      InternalTimer(gettimeofday()+$off, "CUL_HM_Resend", $hash, 0);
    }
  }
  $cmd =~ m/As(..)(..)(....)(......)(......)(.*)/;
  CUL_HM_DumpProtocol("SND", $io, ($1,$2,$3,$4,$5,$6));
}

###################################
sub
CUL_HM_PushCmdStack($$)
{
  my ($hash, $cmd) = @_;
  my @arr = ();

  $hash->{cmdStack} = \@arr if(!$hash->{cmdStack});
  push(@{$hash->{cmdStack}}, $cmd);
}

###################################
sub
CUL_HM_ProcessCmdStack($)
{
  my ($hash) = @_;
  my $sent;

  if($hash->{cmdStack}) {
    if(@{$hash->{cmdStack}}) {
      CUL_HM_SendCmd($hash, shift @{$hash->{cmdStack}}, 1, 1);
      $sent = 1;
    }
    if(!@{$hash->{cmdStack}}) {
      delete($hash->{cmdStack});
    }
  }
  return $sent;
}

###################################
sub
CUL_HM_Resend($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  return if(!$hash->{ackCmdSent});      # Double timer?
  if($hash->{ackCmdSent} == 3) {
    delete($hash->{ackCmdSent});
    delete($hash->{ackWaiting});
    delete($hash->{cmdStack});
    $hash->{STATE} = "MISSING ACK";
    DoTrigger($name, "MISSING ACK");
    return;
  }
  IOWrite($hash, "", $hash->{ackWaiting});
  $hash->{ackCmdSent}++;
  DoTrigger($name, "resend nr ".$hash->{ackCmdSent});
  InternalTimer(gettimeofday()+0.5, "CUL_HM_Resend", $hash, 0);
}

###################################
sub
CUL_HM_Id($)
{
  my ($io) = @_;
  my $fhtid = defined($io->{FHTID}) ? $io->{FHTID} : "0000";
  return AttrVal($io->{NAME}, "hmId", "F1$fhtid");
}

#############################
my %culHmBits = (
  "8000"          => { txt => "DEVICE_INFO",  params => {
                       FIRMWARE       => '00,2',
                       TYPE           => "02,4",
                       SERIALNO       => '06,20,$val=pack("H*",$val)',
                       CLASS          => "26,2",
                       PEER_CHANNEL_A => "28,2",
                       PEER_CHANNEL_B => "30,2",
                       UNKNOWN        => "32,2", } },
  "8002;p01=01"   => { txt => "ACK_STATUS",  params => {
                       CHANNEL        => "02,2",
                       STATUS         => "04,2",
                       RSSI           => "08,2", } },
  "8002;p01=00"   => { txt => "ACK" },
  "8002;p01=80"   => { txt => "NACK" },
  "8002;p01=84"   => { txt => "NACK_TARGET_INVALID" },
  "A001;p11=01"   => { txt => "CONFIG_PEER_ADD", params => {
                       CHANNEL        => "00,2",
                       PEER_ADDRESS   => "04,6",
                       PEER_CHANNEL_A => "10,2",
                       PEER_CHANNEL_B => "12,2", } },
  "A001;p11=03"   => { txt => "CONFIG_PEER_LIST_REQ", params => {
                       CHANNEL => "0,2", } },
  "A001;p11=04"   => { txt => "CONFIG_PARAM_REQ", params => {
                       CHANNEL        => "00,2",
                       PEER_ADDRESS   => "04,6",
                       PEER_CHANNEL   => "10,2",
                       PARAM_LIST     => "12,2", } },
  "A001;p11=05"   => { txt => "CONFIG_START", params => {
                       CHANNEL        => "00,2",
                       PEER_ADDRESS   => "04,6",
                       PEER_CHANNEL   => "10,2",
                       PARAM_LIST     => "12,2", } },
  "A001;p11=06"   => { txt => "CONFIG_END", params => {
                       CHANNEL => "0,2", } },
  "A001;p11=08"   => { txt => "CONFIG_WRITE_INDEX", params => {
                       CHANNEL => "0,2",
                       DATA => '4,,$val =~ s/(..)(..)/ $1:$2/g', } },
  "A001;p11=0E"   => { txt => "CONFIG_STATUS_REQUEST", params => {
                       CHANNEL => "0,2", } },
  "A002"          => { txt => "Request AES", params => { 
                       DATA =>  "0," } },
  "A003"          => { txt => "AES reply",   params => {
                       DATA =>  "0," } },
  "A010;p01=01"   => { txt => "INFO_PEER_LIST", params => {
                       PEER_ADDR1 => "02,6", PEER_CH1 => "08,2",
                       PEER_ADDR2 => "10,6", PEER_CH2 => "16,2",
                       PEER_ADDR3 => "18,6", PEER_CH3 => "24,2",
                       PEER_ADDR4 => "26,6", PEER_CH4 => "32,2", } },
  "A010;p01=02"   => { txt => "INFO_PARAM_RESPONSE_PAIRS", params => {
                       DATA => "2,", } },
  "A010;p01=03"   => { txt => "INFO_PARAM_RESPONSE_SEQ", params => {
                       OFFSET => "2,2", 
                       DATA => "4,", } },
  "A011;p02=0400" => { txt => "RESET" },
  "A011;p01=02"   => { txt => "SET" , params => {
                       CHANNEL  => "02,2", 
                       VALUE    => "04,2", 
                       RAMPTIME => '06,4,$val=CUL_HM_decodeTime16($val)', 
                       DURATION => '10,4,$val=CUL_HM_decodeTime16($val)', } }, 
  "A03E"          => { txt => "SWITCH", params => {
                       DST      => "00,6", 
                       UNKNOWN  => "06,2", 
                       CHANNEL  => "08,2", 
                       COUNTER  => "10,2", } },
  "A001;p02=010A" => { txt => "PAIR_SERIAL", params => {
                       SERIALNO       => '04,,$val=pack("H*",$val)', } },
  "A010;p01=04"   => { txt => "INFO_PARAMETER_CHANGE", params => {
                       CHANNEL => "2,2", 
                       UNKNOWN => "4,8", 
                       PARAM_LIST => "12,2",
                       DATA => '14,,$val =~ s/(..)(..)/ $1:$2/g', } },
  "A010;p01=06"   => { txt => "INFO_ACTUATOR_STATUS", params => {
                       CHANNEL => "2,2", 
                       STATUS  => '4,2', 
                       UNKNOWN => "6,2",
                       RSSI    => "8,2" } },
  "A040"          => { txt => "REMOTE", params => {
                       BUTTON        => '00,02,$val=(hex($val)&0x3F)',
                       LONG          => '00,02,$val=(hex($val)&0x40)?1:0',
                       LOWBAT        => '00,02,$val=(hex($val)&0x80)?1:0',
                       COUNTER       => "02,02", } },
  "A112"          => { txt => "HAVE_DATA"},
  "A610;p01=06"   => { txt => "INFO_SYSTEM_STATUS", params => {
                       CHANNEL => "2,2",
                       STATUS  => '4,2',
                       UNKNOWN => "6,2" } },

);

my @culHmCmdBits = ( "WAKEUP", "WAKEMEUP", "BCAST", "Bit3",
                     "BURST", "BIDI", "RPTED", "RPTEN");


sub
CUL_HM_DumpProtocol($$@)
{
  my ($prefix, $iohash, $len,$cnt,$cmd,$src,$dst,$p) = @_;
  my $iname = $iohash->{NAME};
  my $ev = AttrVal($iname, "hmProtocolEvents", 0);
  my $l4 = GetLogLevel($iname, 4);
  return if(!$ev && $attr{global}{verbose} < $l4);

  my $p01 = substr($p,0,2);
  my $p02 = substr($p,0,4);
  my $p11 = (length($p) > 2 ? substr($p,2,2) : "");

  my $cmdInt = hex($cmd)>>8;
  my $cmdBits="TYPE=".(hex($cmd)&0xff);
  for(my $i = 0; $i < @culHmCmdBits; $i++) {
    $cmdBits .= ",$culHmCmdBits[$i]" if($cmdInt & (1<<$i));
  }

  $cmd = "0A$1" if($cmd =~ m/0B(..)/);
  $cmd = "A4$1" if($cmd =~ m/84(..)/);
  $cmd = "8000" if(($cmd =~ m/A40./ || $cmd eq "0400") && $len eq "1A");
  $cmd = "A0$1" if($cmd =~ m/A4(..)/);

  my $ps;
  $ps = $culHmBits{"$cmd;p11=$p11"} if(!$ps);
  $ps = $culHmBits{"$cmd;p01=$p01"} if(!$ps);
  $ps = $culHmBits{"$cmd;p02=$p02"} if(!$ps);
  $ps = $culHmBits{"$cmd"}         if(!$ps);
  my $txt = "";
  if($ps) {
    $txt = $ps->{txt};
    if($ps->{params}) {
      $ps = $ps->{params};
      foreach my $k (sort {$ps->{$a} cmp $ps->{$b} } keys %{$ps}) {
        my ($o,$l,$expr) = split(",", $ps->{$k}, 3);
        last if(length($p) <= $o);
        my $val = $l ? substr($p,$o,$l) : substr($p,$o);
        eval $expr if($expr);
        $txt .= " $k:$val";
      }
    }
    $txt = " ($txt)" if($txt);
  }
  my $msg  = "$prefix L:$len N:$cnt CMD:$cmd ($cmdBits) SRC:$src DST:$dst $p$txt";
  Log $l4, $msg;
  DoTrigger($iname, $msg) if($ev);
}

#############################
my @culHmTimes8 = ( 0.1, 1, 5, 10, 60, 300, 600, 3600 );
sub
CUL_HM_encodeTime8($)
{
  my $v = shift;
  return "00" if($v < 0.1);
  for(my $i = 0; $i < @culHmTimes8; $i++) {
    if($culHmTimes8[$i] * 32 > $v) {
      for(my $j = 0; $j < 32; $j++) {
        if($j*$culHmTimes8[$i] >= $v) {
          return sprintf("%X", $i*32+$j);
        }
      }
    }
  }
  return "FF";
}

#############################
sub
CUL_HM_decodeTime8($)
{
  my $v = hex(shift);
  return "undef" if($v > 255);
  my $v1 = int($v/32);
  my $v2 = $v%32;
  return $v2 * $culHmTimes8[$v1];
}

#############################
sub
CUL_HM_encodeTime16($)
{
  my $v = shift;
  my $ret = "FFFF";
  my $mul = 20;

  return "0000" if($v < 0.05);
  for(my $i = 0; $i < 16; $i++) {
    if($v*$mul < 0xfff) {
     $ret=sprintf("%03X%X", $v*$mul, $i);
     last;
    }
    $mul /= 2;
  }
  my $v2 = CUL_HM_decodeTime16($ret);
  Log 1, "Timeout $v rounded to $v2" if($v != $v2);
  return ($ret, "");
}

sub
CUL_HM_convTemp($)
{
  my ($val) = @_;

  my @list = map { ($_.".0", $_+0.5) } (6..30);
  pop @list;
  return "Invalid temperature $val, choose one of on off " . join(" ",@list)
    if(!($val eq "on" || $val eq "off" ||
         ($val =~ m/^\d*\.?\d+$/ && $val >= 6 && $val <= 30)));
  $val = 100 if($val eq "on");
  $val =   0 if($val eq "off");
  return sprintf("%02X", $val*2);
}

#############################
sub
CUL_HM_decodeTime16($)
{
  my $v = hex(shift);
  my $m = int($v/16);
  my $e = $v % 16;
  my $mul = 0.05;
  while($e--) {
    $mul *= 2;
  }
  return $mul*$m;
}

#############################
sub
CUL_HM_pushConfig($$$$$$)
{
  my ($hash,$src,$dst,$chn,$list,$content) = @_;

  CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s%02X0500000000%02X",$src,$dst,$chn,$list));
  my $tl = length($content);
  for(my $l = 0; $l < $tl; $l+=28) {
    my $ml = $tl-$l < 28 ? $tl-$l : 28;
    CUL_HM_PushCmdStack($hash,
      sprintf("++A001%s%s%02X08%s", $src,$dst,$chn, substr($content,$l,$ml)));
  }
  CUL_HM_PushCmdStack($hash,
        sprintf("++A001%s%s%02X06",$src,$dst,$chn));
}

sub
CUL_HM_maticFn($$$$$)
{
  my ($hash, $id, $dst, $a2, $cfg) = @_;
  my $sndcmd =  sprintf("++B001%s%s0105%s%02X03", $id, $dst, $id, $a2);
  CUL_HM_SendCmd ($hash, $sndcmd, 10, 2);
  $sndcmd =  sprintf("++A001%s%s0108%s", $id, $dst, $cfg);
  CUL_HM_SendCmd ($hash, $sndcmd, 10, 2);
  $sndcmd = sprintf("++A001%s%s0106", $id, $dst);
  return $sndcmd;
}

1;

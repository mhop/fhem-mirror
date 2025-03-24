# $Id$
# This modules handles the communication with a TCM 120 or TCM 310 / TCM 400J / TCM 515 EnOcean transceiver chip.
# As the protocols are radically different, this is actually 2 drivers in one.
# See also:
#  TCM_120_User_Manual_V1.53_02.pdf
#  EnOcean Serial Protocol 3 (ESP3) (for the TCM 310, TCM 400J, TCM 515)

package main;
use strict;
use warnings;
use DevIo;
use Time::HiRes qw(gettimeofday usleep);
my $dupTimeout = 0.6;
my $modulesHash = \%modules;
my $modulesType = 'TCM';

sub TCM_Read($);
sub TCM_ReadAnswer($$);
sub TCM_Ready($);
sub TCM_Write($$$$);
sub TCM_Parse120($$$);
sub TCM_Parse310($$$);
sub TCM_CRC8($);
sub TCM_CSUM($);

# ESP3 response codes
my %esp3Rc = (
  "00" => "OK",
  "01" => "ERROR",
  "02" => "NOT_SUPPORTED",
  "03" => "WRONG_PARAM",
  "04" => "OPERATION_DENIED",
  "05" => "LOCK_SET",
  "07" => "NO_FREE_BUFFER",
  "82" => "FLASH_HW_ERROR",
  "90" => "BASEID_OUT_OF_RANGE",
  "91" => "BASEID_MAX_REACHED",
);

sub TCM_Initialize($) {
  my ($hash) = @_;
  # Provider
  my %matchList= (
    "1:EnOcean" => "^EnOcean:",
  );
  $hash->{Clients} = "EnOcean";
  $hash->{MatchList} = \%matchList;
  $hash->{ReadFn} = "TCM_Read";
  $hash->{ReadyFn} = "TCM_Ready";
  $hash->{WriteFn} = "TCM_Write";
  # Normal devices
  $hash->{AttrFn} = "TCM_Attr";
  $hash->{DefFn} = "TCM_Define";
  $hash->{FingerprintFn} = "TCM_Fingerprint";
  $hash->{NotifyFn} = "TCM_Notify";
  $hash->{NotifyOrderPrefix} = "45-";
  $hash->{GetFn} = "TCM_Get";
  $hash->{SetFn} = "TCM_Set";
  $hash->{ShutdownFn} = "TCM_Shutdown";
  $hash->{UndefFn} = "TCM_Undef";
  $hash->{AttrList} = "assignIODev:select,no,yes baseID .baseIDSaved blockSenderID:own,no .chipIDSaved comModeUTE:auto,biDir,uniDir comType:TCM,RS485 do_not_notify:1,0 " .
                      "dummy:1,0 fingerprint:off,on learningDev:all,teachMsg learningMode:always,demand,nearfield " .
                      "msgCounter:select,off,on rcvIDShift sendInterval:0,5,10,15,20,25,40,50,100,150,200,250 smartAckMailboxMax:slider,0,1,20 " .
                      "smartAckLearnMode:simple,advance,advanceSelectRep";
  return undef;
}

# Define
sub TCM_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  my $model = $a[2];
  return "TCM: wrong syntax, correct is: define <name> TCM [ESP2|ESP3] {devicename[\@baudrate]|ip:port|none}"
    if (@a != 4 || $model !~ m/^(ESP2|ESP3|120|310)$/);
  DevIo_CloseDev($hash);
  my $dev = $a[3];
  $hash->{DeviceName} = $dev;
  # old model names replaced
  $model = "ESP2" if ($model eq "120");
  $model = "ESP3" if ($model eq "310");
  $hash->{MODEL} = $model;
  $hash->{BaseID} = "00000000";
  $hash->{LastID} = "00000000";
  $hash->{NOTIFYDEV} = "global";
  $modules{$modulesType}{devHash}{$name} = $hash;
  if($dev eq "none") {
    Log3 $name, 1, "TCM $name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  InternalTimer(time() + 60, 'TCM_msgCounter', $hash, 0);
  my $ret = DevIo_OpenDev($hash, 0, undef);
  return $ret;
}

# Initialize serial communication
sub TCM_InitSerialCom($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  delete $hash->{helper}{init_done};
  if ($hash->{STATE} eq "disconnected") {
    Log3 $name, 2, "TCM $name not initialized";
    return undef;
  }
  my $attrVal;
  my $comType = AttrVal($name, "comType", "TCM");
  my $setCmdVal = "";
  my @setCmd = ("set", "reset", $setCmdVal);
  # read and discard receive buffer, modem reset
  if ($hash->{MODEL} eq "ESP2") {
    if ($comType eq "TCM") {
      TCM_ReadAnswer($hash, "set reset");
      #TCM_Read($hash);
      $hash->{PARTIAL} = '';
      TCM_Set($hash, @setCmd);
    }
  } else {
    #TCM_ReadAnswer($hash, "set reset");
    #TCM_Read($hash);
    $hash->{PARTIAL} = '';
    delete $hash->{helper}{awaitCmdResp};
    if (TCM_Set($hash, @setCmd) ne '') {
      $hash->{PARTIAL} = '';
      delete $hash->{helper}{awaitCmdResp};
      TCM_Set($hash, @setCmd);
    }
  }
  # default attributes
  my %setAttrInit;
  if ($comType eq "RS485" || $hash->{DeviceName} eq "none") {
    %setAttrInit = (sendInterval => {ESP2 => 100, ESP3 => 0},
                    learningMode => {ESP2 => "always", ESP3 => "always"}
                   );
  }else {
    %setAttrInit = ("sendInterval" => {ESP2 => 100, ESP3 => 0});
  }
  foreach(keys %setAttrInit) {
    $attrVal = AttrVal($name, $_, undef);
    if(!defined $attrVal && defined $setAttrInit{$_}{$hash->{MODEL}}) {
      $attr{$name}{$_} = $setAttrInit{$_}{$hash->{MODEL}};
      Log3 $name, 2, "TCM $name Attribute $_ $setAttrInit{$_}{$hash->{MODEL}} initialized";
    }
  }
  # 750 ms pause
  usleep(750 * 1000);
  # read transceiver IDs
  my $baseID = AttrVal($name, "baseID", undef);
  if (defined $baseID) {
    $hash->{BaseID} = $baseID;
    $hash->{LastID} = sprintf "%08X", (hex $baseID) + 127;
  } elsif ($comType ne "RS485" && $hash->{DeviceName} ne "none") {
    my @getBaseID = ("get", "baseID");
    if (TCM_Get($hash, @getBaseID) =~ /[Ff]{2}[\dA-Fa-f]{6}/) {
      $baseID = sprintf "%08X", hex $&;
      $baseID = $baseID eq 'F' x 8 ? '0' x 8 : $baseID;
      $attr{$name}{".baseIDSaved"} = $baseID;
      $hash->{BaseID} = $baseID;
      $hash->{LastID} = sprintf "%08X", (hex $baseID) + 127;
    } else {
      $baseID = AttrVal($name, ".baseIDSaved", '0' x 8);
      $hash->{BaseID} = $baseID;
      $hash->{LastID} = sprintf("%08X", (hex $baseID) + 127);
    }
  }
  if (defined $baseID) {
    push(@{$modules{"$hash->{TYPE}"}{BaseID}}, $baseID) if (!grep(/^$baseID$/, @{$modules{"$hash->{TYPE}"}{BaseID}}));
    @{$hash->{helper}{BaseID}} = @{$modules{"$hash->{TYPE}"}{BaseID}};
  }
  my $chipID;
  if ($hash->{MODEL} eq "ESP3" && $comType ne "RS485" && $hash->{DeviceName} ne "none") {
    # get chipID
    my @getChipID = ('get', 'version');
    if (TCM_Get($hash, @getChipID) =~ m/ChipID:.([\dA-Fa-f]{8})/) {
      $chipID = sprintf "%08X", hex $1;
      $attr{$name}{".chipIDSaved"} = $chipID;
    } else {
      $chipID = AttrVal($name, ".chipIDSaved", undef);
    }
  }
  if (defined $chipID) {
    $hash->{ChipID} = $chipID;
    push(@{$modules{"$hash->{TYPE}"}{ChipID}}, $hash->{ChipID}) if (!grep(/^$chipID$/, @{$modules{"$hash->{TYPE}"}{ChipID}}));
    @{$hash->{helper}{ChipID}} = @{$modules{"$hash->{TYPE}"}{ChipID}};
  }
  # default transceiver parameter
  if ($comType ne "RS485" && $hash->{DeviceName} ne "none") {
    my %setCmdRestore = (mode => "00",
                         maturity => "00",
                         repeater => "RepEnable: 00 RepLevel: 00",
                         smartAckMailboxMax => 0
                        );
    foreach(keys %setCmdRestore) {
      $setCmdVal = ReadingsVal($name, $_, AttrVal($name, $_, undef));
      if (defined $setCmdVal) {
        if ($_ eq "repeater") {
          $setCmdVal = substr($setCmdVal, 11, 2) . substr($setCmdVal, 24, 2);
          $setCmdVal = "0000" if ($setCmdVal eq "0001");
        }
        @setCmd = ("set", $_, $setCmdVal);
        TCM_Set($hash, @setCmd);
        Log3 $name, 2, "TCM $name $_ $setCmdVal restored";
      } else {
        if ($hash->{MODEL} eq "ESP2") {

        } else {
          if ($_ eq "repeater") {
            $setCmdVal = substr($setCmdRestore{$_}, 11, 2) . substr($setCmdRestore{$_}, 24, 2);
          } else {
            $setCmdVal = $setCmdRestore{$_};
          }
          @setCmd = ("set", $_, $setCmdVal);
          my $msg = TCM_Set($hash, @setCmd);
          Log3 $name, 2, "TCM $name $_ $setCmdVal initialized" if ($msg eq "");
        }
      }
    }
  }
  #CommandSave(undef, undef);
  $hash->{helper}{init_done} = 1;
  readingsSingleUpdate($hash, "state", "initialized", 1);
  Log3 $name, 2, "TCM $name initialized";
  return undef;
}

sub TCM_Fingerprint($$) {
  my ($IODev, $msg) = @_;
  return ($IODev, $msg) if (AttrVal($IODev, "fingerprint", 'off') eq 'off');
  my @msg = split(":", $msg);
  if ($msg[1] == 1) {
    # RADIO_ERP1
    #EnOcean:PacketType:RORG:MessageData:SourceID:Status:OptionalData
    substr($msg[5], 1, 1, "0");
    substr($msg[6], 0, 2, "01");
    substr($msg[6], 10, 4, "0000");

  } elsif ($msg[1] == 2) {
    # RESPONSE
    #EnOcean:PacketType:ResposeCode:MessageData:OptionalData
    # no dispatch

  } elsif ($msg[1] == 3) {
    # RADIO_SUB_TEL
    # no dispatch

  } elsif ($msg[1] == 4) {
    # EVENT
    #EnOcean:PacketType:eventCode:MessageData
    # no manipulation of the data necessary

  } elsif ($msg[1] == 5) {
    # COMMON_COMMAND
    # no dispatch

  } elsif ($msg[1] == 6) {
    # SMART_ACK_COMMAND
    #EnOcean:PacketType:smartAckCode:MessageData
    # no manipulation of the data necessary

  } elsif ($msg[1] == 7) {
    # REMOTE_MAN_COMMAND
    #EnOcean:PacketType:RORG:MessageData:SourceID:DestinationID:FunctionNumber:ManufacturerID:RSSI:Delay
    substr($msg[8], 0, 2, "00");
    substr($msg[9], 0, 2, "00");

  } elsif ($msg[1] == 9) {
    # RADIO_MESSAGE
    # no dispatch

  } elsif ($msg[1] == 10) {
    # RADIO_ERP2
    # no dispatch

  } else {

  }
  $msg = join(":", @msg);
  #Log3 $IODev, 2, "TCM $IODev <TCM_Fingerprint> PacketType: $msg[1] Data: $msg";
  return ($IODev, $msg);
}

# Write
sub TCM_Write($$$$) {
  # Input is header and data (HEX), without CRC
  my ($hash, $shash, $header, $msg) = @_;
  #return if (!exists($hash->{helper}{init_done}) && $hash != $shash);
  # return if (!defined($header));
  my $name = $hash->{NAME};
  my $bstring;
  if ($hash->{MODEL} eq "ESP2") {
    # TCM 120 (ESP2)
    if ($header) {
      # ESP3 packet
      my $packetType = hex(substr($header, 6, 2));
      if ($packetType != 1) {
        Log3 $name, 1, "TCM $name Packet Type not supported.";
        return;
      }
      my $odataLen = hex(substr($header, 4, 2));
      if ($odataLen != 0) {
        Log3 $name, 1, "TCM $name Radio Telegram with optional Data not supported.";
        return;
      }
      #my $mdataLen = hex(substr($header, 0, 4));
      my $rorg = substr ($msg, 0, 2);
      # translate the RORG to ORG
      my %rorgmap = ("F6"=>"05",
                     "D5"=>"06",
                     "A5"=>"07"
                    );
      if($rorgmap{$rorg}) {
        $rorg = $rorgmap{$rorg};
      } else {
        Log3 $name, 1, "TCM $name unknown RORG mapping for $rorg";
      }
      if ($rorg eq "05" || $rorg eq "06") {
        $bstring = "6B" . $rorg . substr ($msg, 2, 2) . "000000" . substr ($msg, 4);
      } else {
        $bstring = "6B" . $rorg . substr ($msg, 2);
      }
    } else {
      # ESP2 packet
      $bstring = $msg;
    }
    $bstring = "A55A" . $bstring . TCM_CSUM($bstring);
  } else {
    # TCM 310 (ESP3)
    $bstring = "55" . $header . TCM_CRC8($header) . $msg . TCM_CRC8($msg);
    if (exists($hash->{helper}{telegramSentTimeLast}) && $hash->{helper}{telegramSentTimeLast} < gettimeofday() - 6) {
      # clear outdated response control list
      delete $hash->{helper}{awaitCmdResp};
    }
    $hash->{helper}{telegramSentTimeLast} = gettimeofday();
    if (exists $hash->{helper}{SetAwaitCmdResp}) {
      #push(@{$hash->{helper}{awaitCmdResp}}, 1);
      push(@{$hash->{helper}{awaitCmdResp}}, $hash->{helper}{SetAwaitCmdResp});
      delete $hash->{helper}{SetAwaitCmdResp};
    } else {
      push(@{$hash->{helper}{awaitCmdResp}}, undef);
    }
    #Log3 $name, 5, "TCM $name awaitCmdResp: " . join(' ', @{$hash->{helper}{awaitCmdResp}});
  }
  Log3 $name, 5, "TCM $name sent ESP: $bstring";
  push(@{$hash->{helper}{sndCounter}}, time() + 0) if (AttrVal($hash->{NAME}, 'msgCounter', 'off') eq 'on');
  DevIo_SimpleWrite($hash, $bstring, 1);
  # next commands will be sent with a delay
  usleep(int(AttrVal($name, "sendInterval", 100)) * 1000);
  return undef;
}

# ESP2 CRC
# Used in the TCM120
sub TCM_CSUM($) {
  my $msg = shift;
  my $ml = length($msg);
  my @data;
  for(my $i = 0; $i < $ml; $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  my $sum = 0;
  map { $sum += $_; } @data;
  return sprintf("%02X", $sum & 0xFF);
}

# ESP3 CRC-Table
my @u8CRC8Table = (
  0x00, 0x07, 0x0e, 0x09, 0x1c, 0x1b, 0x12, 0x15, 0x38, 0x3f, 0x36, 0x31, 0x24,
  0x23, 0x2a, 0x2d, 0x70, 0x77, 0x7e, 0x79, 0x6c, 0x6b, 0x62, 0x65, 0x48, 0x4f,
  0x46, 0x41, 0x54, 0x53, 0x5a, 0x5d, 0xe0, 0xe7, 0xee, 0xe9, 0xfc, 0xfb, 0xf2,
  0xf5, 0xd8, 0xdf, 0xd6, 0xd1, 0xc4, 0xc3, 0xca, 0xcd, 0x90, 0x97, 0x9e, 0x99,
  0x8c, 0x8b, 0x82, 0x85, 0xa8, 0xaf, 0xa6, 0xa1, 0xb4, 0xb3, 0xba, 0xbd, 0xc7,
  0xc0, 0xc9, 0xce, 0xdb, 0xdc, 0xd5, 0xd2, 0xff, 0xf8, 0xf1, 0xf6, 0xe3, 0xe4,
  0xed, 0xea, 0xb7, 0xb0, 0xb9, 0xbe, 0xab, 0xac, 0xa5, 0xa2, 0x8f, 0x88, 0x81,
  0x86, 0x93, 0x94, 0x9d, 0x9a, 0x27, 0x20, 0x29, 0x2e, 0x3b, 0x3c, 0x35, 0x32,
  0x1f, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0d, 0x0a, 0x57, 0x50, 0x59, 0x5e, 0x4b,
  0x4c, 0x45, 0x42, 0x6f, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7d, 0x7a, 0x89, 0x8e,
  0x87, 0x80, 0x95, 0x92, 0x9b, 0x9c, 0xb1, 0xb6, 0xbf, 0xb8, 0xad, 0xaa, 0xa3,
  0xa4, 0xf9, 0xfe, 0xf7, 0xf0, 0xe5, 0xe2, 0xeb, 0xec, 0xc1, 0xc6, 0xcf, 0xc8,
  0xdd, 0xda, 0xd3, 0xd4, 0x69, 0x6e, 0x67, 0x60, 0x75, 0x72, 0x7b, 0x7c, 0x51,
  0x56, 0x5f, 0x58, 0x4d, 0x4a, 0x43, 0x44, 0x19, 0x1e, 0x17, 0x10, 0x05, 0x02,
  0x0b, 0x0c, 0x21, 0x26, 0x2f, 0x28, 0x3d, 0x3a, 0x33, 0x34, 0x4e, 0x49, 0x40,
  0x47, 0x52, 0x55, 0x5c, 0x5b, 0x76, 0x71, 0x78, 0x7f, 0x6A, 0x6d, 0x64, 0x63,
  0x3e, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2c, 0x2b, 0x06, 0x01, 0x08, 0x0f, 0x1a,
  0x1d, 0x14, 0x13, 0xae, 0xa9, 0xa0, 0xa7, 0xb2, 0xb5, 0xbc, 0xbb, 0x96, 0x91,
  0x98, 0x9f, 0x8a, 0x8D, 0x84, 0x83, 0xde, 0xd9, 0xd0, 0xd7, 0xc2, 0xc5, 0xcc,
  0xcb, 0xe6, 0xe1, 0xe8, 0xef, 0xfa, 0xfd, 0xf4, 0xf3);

# ESP3 CRC
# Used in the TCM310
sub TCM_CRC8($) {
  my $msg = shift;
  my $ml = length($msg);
  my @data;
  for(my $i = 0; $i < $ml; $i += 2) {
    push(@data, ord(pack('H*', substr($msg, $i, 2))));
  }
  my $crc = 0;
  map { $crc = $u8CRC8Table[$crc ^ $_]; } @data;
  return sprintf("%02X", $crc);
}

# Read
# called from the global loop, when the select for hash->{FD} reports data
sub TCM_Read($) {
  my ($hash) = @_;
  my $buf = DevIo_SimpleRead($hash);
  return "" if (!defined($buf));
  my $name = $hash->{NAME};
  my $blockSenderID = AttrVal($name, "blockSenderID", "own");
  my $data = $hash->{PARTIAL} . uc(unpack('H*', $buf));
  #Log3 $name, 5, "TCM $name received ESP: $data";

  if($hash->{MODEL} eq "ESP2") {
    # TCM 120

    while($data =~ m/^A55A(.B.{20})(..)/) {
      my ($net, $crc) = ($1, $2);
      my $mycrc = TCM_CSUM($net);
      my $rest = substr($data, 28);

      if($crc ne $mycrc) {
        Log3 $name, 2, "TCM $name wrong data checksum: got $crc, computed $mycrc" ;
        $data = $rest;
        next;
      }

      Log3 $name, 5, "TCM $name received ESP: $data";

      if($net =~ m/^0B(..)(........)(........)(..)/) {
        # Receive Radio Telegram (RRT)
        my ($org, $d1, $id, $status) = ($1, $2, $3, $4);
        my $packetType = 1;
        # shift rcvID range
        $id = sprintf("%08X", hex($id) + hex($attr{$name}{rcvIdShift})) if (defined $attr{$name}{rcvIdShift});
        # Re-translate the ORG to RadioORG / TCM310 equivalent
        my %orgmap = ("05" => "F6", "06" => "D5", "07" => "A5");
        if($orgmap{$org}) {
          $org = $orgmap{$org};
        } else {
          Log3 $name, 2, "TCM $name unknown ORG mapping for $org";
        }
        if ($org ne "A5") {
          # extract db_0
          $d1 = substr($d1, 0, 2);
        }
        if (!defined TCM_BlockSenderID($hash, $blockSenderID, $id)) {
          Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:01FFFFFFFF0000", undef) if (exists $hash->{helper}{init_done});
        }

      } else {
        # Receive Message Telegram (RMT)
        my $msg = TCM_Parse120($hash, $net, 1);
        if (($msg eq 'OK') && ($net =~ m/^8B(..)(........)(........)(..)/)){
          my ($org, $d1, $id, $status) = ($1, $2, $3, $4);
          my $packetType = 1;
          # shift rcvID range
          $id = sprintf("%08X", hex($id) + hex($attr{$name}{rcvIDShift})) if (defined $attr{$name}{rcvIDShift});
          # Re-translate the ORG to RadioORG / TCM310 equivalent
          my %orgmap = ("05" => "F6", "06" => "D5", "07" => "A5");
          if($orgmap{$org}) {
            $org = $orgmap{$org};
          } else {
            Log3 $name, 2, "TCM $name unknown ORG mapping for $org";
          }
          if ($org ne "A5") {
            # extract db_0
            $d1 = substr($d1, 0, 2);
          }
          if (!defined TCM_BlockSenderID($hash, $blockSenderID, $id)) {
            Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:01FFFFFFFF0000", undef)  if (exists $hash->{helper}{init_done});
          }
         }
      }
      $data = $rest;
      push(@{$hash->{helper}{rcvCounter}}, time() + 0) if (AttrVal($hash->{NAME}, 'msgCounter', 'off') eq 'on');
    }

    if (length($data) >= 4) {
      $data =~ s/.*A55A/A55A/ if($data !~ m/^A55A/);
      $data = "" if($data !~ m/^A55A/);
    }

  } else {
    # TCM310 / ESP3

    while ($data =~ m/^55(....)(..)(..)(..)/) {
      my ($ldata, $lodata, $packetType, $crc) = (hex($1), hex($2), hex($3), $4);
      my $tlen = 2 * (7 + $ldata + $lodata);
      # data telegram incomplete
      last if (length($data) < $tlen);
      my $rest = substr($data, $tlen);
      $data = substr($data, 0, $tlen);

      Log3 $name, 5, "TCM $name received ESP: $data";

      my $hdr = substr($data, 2, 8);
      my $mdata = substr($data, 12, $ldata * 2);
      my $odata = substr($data, 12 + $ldata * 2, $lodata * 2);
      my $mycrc = TCM_CRC8($hdr);
      if ($mycrc ne $crc) {
        Log3 $name, 2, "TCM $name wrong header checksum: got $crc, computed $mycrc" ;
        $data = $rest;
        next;
      }
      $mycrc = TCM_CRC8($mdata . $odata);
      $crc  = substr($data, -2);
      if ($mycrc ne $crc) {
        Log3 $name, 2, "TCM $name wrong data checksum: got $crc, computed $mycrc" ;
        $data = $rest;
        next;
      }

      if ($packetType == 1) {
        # packet type RADIO
        $mdata =~ m/^(..)(.*)(........)(..)$/;
        my ($org, $d1, $id, $status) = ($1,$2,$3,$4);
        my $repeatingCounter = hex substr($status, 1, 1);
        $odata =~ m/^(..)(........)(..)(..)$/;
        my ($RSSI, $receivingQuality) = (hex($3), "excellent");
        if ($RSSI > 87) {
          $receivingQuality = "bad";
        } elsif ($RSSI > 75) {
          $receivingQuality = "good";
        }
        my %addvals = (
          PacketType       => $packetType,
          SubTelNum        => hex($1),
          DestinationID    => $2,
          RSSI             => -$RSSI,
          ReceivingQuality => $receivingQuality,
          RepeatingCounter => $repeatingCounter,
        );
        $hash->{RSSI} = -$RSSI;

        if (!defined TCM_BlockSenderID($hash, $blockSenderID, $id)) {
          #EnOcean:PacketType:RORG:MessageData:SourceID:Status:OptionalData
          Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:$odata", \%addvals) if (exists $hash->{helper}{init_done});
        }

      } elsif ($packetType == 2) {
        # packet type RESPONSE
        $mdata =~ m/^(..)(.*)$/;
        my $rc = $1;
        my $rcTxt = exists($esp3Rc{$rc}) ? $esp3Rc{$rc} : $rc;
        if (defined $hash->{helper}{awaitCmdResp}[0] && $hash->{helper}{awaitCmdResp}[0]) {
          # received command response message
          TCM_Parse310($hash, $mdata, shift(@{$hash->{helper}{awaitCmdResp}}));
          # do not execute if transceiver command answer is expected
          #$data .= $rest;
          #last;
        } else {
          # received sent data response messages
          shift(@{$hash->{helper}{awaitCmdResp}});
          Log3 $name, $rc eq "00" ? 5 : 2, "TCM $name RESPONSE: $rcTxt";
        }
        #$packetType = sprintf "%01X", $packetType;
        #EnOcean:PacketType:ResposeCode:MessageData:OptionalData
        #Dispatch($hash, "EnOcean:$packetType:$1:$2:$odata", undef);

      } elsif ($packetType == 3) {
        # packet type RADIO_SUB_TEL
        Log3 $name, 2, "TCM $name packet type RADIO_SUB_TEL not supported: $data";

      } elsif ($packetType == 4) {
        # packet type EVENT
        $mdata =~ m/^(..)(.*)$/;
        $packetType = sprintf "%01X", $packetType;
        my $eventCode = $1;
        my $messageData = $2;
        if (hex($eventCode) <= 3) {
          #EnOcean:PacketType:eventCode:messageData
          Dispatch($hash, "EnOcean:$packetType:$eventCode:$messageData", undef);
        } elsif (hex($eventCode) == 4) {
          # CO_READY
          my @resetCause = ('voltage_supply_drop', 'reset_pin', 'watchdog', 'flywheel', 'parity_error', 'hw_parity_error', 'memory_request_error', 'wake_up_pin_0', 'wake_up_pin_1', 'unknown', 'wake_up_uart', 'sw_reset');
          my @secureMode = ('standard', 'extended');
          $hash->{RESET_CAUSE} = $resetCause[hex($messageData)] // $messageData;
          $hash->{SECURE_MODE} = $secureMode[hex($odata)];
          DoTrigger($name, "EVENT: RESET_CAUSE: $hash->{RESET_CAUSE}");
          DoTrigger($name, "EVENT: SECURE_MODE: $hash->{SECURE_MODE}");
          Log3 $name, 2, "TCM $name EVENT RESET_CAUSE: $hash->{RESET_CAUSE} SECURE_MODE: $hash->{SECURE_MODE}";
        } elsif (hex($eventCode) == 5) {
          # CO_EVENT_SECUREDEVICES
        } elsif (hex($eventCode) == 6) {
          # CO_DUTYCYCLE_LIMIT
          my @dutycycleLimit = ('released', 'reached');
          $hash->{DUTYCYCLE_LIMIT} = $dutycycleLimit[hex($messageData)];
          DoTrigger($name, "EVENT: DUTYCYCLE_LIMIT: $hash->{DUTYCYCLE_LIMIT}");
          Log3 $name, 2, "TCM $name EVENT DUTYCYCLE_LIMIT: $hash->{DUTYCYCLE_LIMIT}";
        } elsif (hex($eventCode) == 7) {
          # CO_TRANSMIT_FAILED
          my @transmitFailed = ('CSMA_failed', 'no_ack_received');
          $hash->{TRANSMIT_FAILED} = $transmitFailed[hex($messageData)];
          DoTrigger($name, "EVENT: TRANSMIT_FAILED: $hash->{TRANSMIT_FAILED}");
          Log3 $name, 2, "TCM $name EVENT TRANSMIT_FAILED: $hash->{TRANSMIT_FAILED}";
        } else {
        }

      } elsif ($packetType == 5) {
        # packet type COMMON_COMMAND
        Log3 $name, 2, "TCM $name packet type COMMON_COMMAND not supported: $data";

      } elsif ($packetType == 6) {
        # packet type SMART_ACK_COMMAND
        $mdata =~ m/^(..)(.*)$/;
        $packetType = sprintf "%01X", $packetType;
        #EnOcean:PacketType:smartAckCode:MessageData
        Dispatch($hash, "EnOcean:$packetType:$1:$2", undef) if (exists $hash->{helper}{init_done});

      } elsif ($packetType == 7) {
        # packet type REMOTE_MAN_COMMAND
        $mdata =~ m/^(....)(....)(.*)$/;
        my ($function, $manufID, $messageData) = ($1, $2, $3);
        $odata =~ m/^(........)(........)(..)(..)$/;
        my ($RSSI, $receivingQuality) = ($3, "excellent");
        if (hex($RSSI) > 87) {
          $receivingQuality = "bad";
        } elsif (hex($RSSI) > 75) {
          $receivingQuality = "good";
        }
        my %addvals = (
          PacketType       => $packetType,
          DestinationID    => $1,
          RSSI             => -hex($RSSI),
          ReceivingQuality => $receivingQuality,
        );
        $hash->{RSSI} = -hex($RSSI);
        $packetType = sprintf "%01X", $packetType;

        if (!defined TCM_BlockSenderID($hash, $blockSenderID, $2)) {
          #EnOcean:PacketType:RORG:MessageData:SourceID:DestinationID:FunctionNumber:ManufacturerID:RSSI:Delay
          Dispatch($hash, "EnOcean:$packetType:C5:$messageData:$2:$1:$function:$manufID:$RSSI:$4", \%addvals) if (exists $hash->{helper}{init_done});
        }

      } elsif ($packetType == 9) {
        # packet type RADIO_MESSAGE
        Log3 $name, 2, "TCM: $name packet type RADIO_MESSAGE not supported: $data";

      } elsif ($packetType == 10) {
        # packet type RADIO_ERP2
        Log3 $name, 2, "TCM $name packet type RADIO_ADVANCED not supported: $data";

      } else {
        Log3 $name, 2, "TCM $name unknown packet type $packetType: $data";

      }

      $data = $rest;
      push(@{$hash->{helper}{rcvCounter}}, time() + 0) if (AttrVal($hash->{NAME}, 'msgCounter', 'off') eq 'on');
    }

    if(length($data) >= 4) {
      $data =~ s/.*55/55/ if($data !~ m/^55/);
      $data = "" if($data !~ m/^55/);
    }

  }
  $hash->{PARTIAL} = $data;
}

# Parse Table TCM 120
my %parsetbl120 = (
  "8B05" => { msg=>"OK" },
  "8B06" => { msg=>"OK" },
  "8B07" => { msg=>"OK" },
  "8B08" => { msg=>"ERR_SYNTAX_H_SEQ" },
  "8B09" => { msg=>"ERR_SYNTAX_LENGTH" },
  "8B0A" => { msg=>"ERR_SYNTAX_CHKSUM" },
  "8B0B" => { msg=>"ERR_SYNTAX_ORG" },
  "8B0C" => { msg=>"ERR_MODEM_DUP_ID" },
  "8B19" => { msg=>"ERR" },
  "8B1A" => { msg=>"ERR_IDRANGE" },
  "8B22" => { msg=>"ERR_TX_IDRANGE" },
  "8B28" => { msg=>"ERR_MODEM_NOTWANTEDACK" },
  "8B29" => { msg=>"ERR_MODEM_NOTACK" },
  "8B58" => { msg=>"OK" },
  "8B8C" => { msg=>"INF_SW_VER", expr=>'"$a[2].$a[3].$a[4].$a[5]"' },
  "8B88" => { msg=>"INF_RX_SENSIVITY", expr=>'$a[2] ? "High (01)":"Low (00)"' },
  "8B89" => { msg=>"INFO", expr=>'substr($rawstr,2,9)' },
  "8B98" => { msg=>"INF_IDBASE",
              expr=>'sprintf("%02x%02x%02x%02x", $a[2], $a[3], $a[4], $a[5])' },
  "8BA8" => { msg=>"INF_MODEM_STATUS",
              expr=>'sprintf("%s, ID:%02x%02x", $a[2]?"on":"off", $a[3], $a[4])' },
);

# Parse TCM 120
sub TCM_Parse120($$$) {
  my ($hash,$rawmsg,$ret) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "TCM $name Parse $rawmsg";
  my $msg = "";
  my $cmd = $parsetbl120{substr($rawmsg, 0, 4)};
  if(!$cmd) {
    $msg ="Unknown command: $rawmsg";
  } else {
    if($cmd->{expr}) {
      $msg = $cmd->{msg}." " if(!$ret);
      my $rawstr = pack('H*', $rawmsg);
      $rawstr =~ s/[\r\n]//g;
      my @a = map { ord($_) } split("", $rawstr);
      $msg .= eval $cmd->{expr};
    } else {
      return "" if($cmd ->{msg} eq "OK" && !$ret); # SKIP Ok
      $msg = $cmd->{msg};
    }
  }
  Log3 $name, 2, "TCM $name RESPONSE: $msg" if(!$ret);
  return $msg;
}

# Parse TCM 310
sub TCM_Parse310($$$) {
  my ($hash, $rawmsg, $ptr) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "TCM $name TCM_Parse $rawmsg";
  my $rc = substr($rawmsg, 0, 2);
  my $msg = "";
  if ($rc ne "00") {
    $msg = $esp3Rc{$rc};
    $msg = "Unknown return code $rc" if (!$msg);
  } else {
    my @ans;
    foreach my $k (sort keys %{$ptr}) {
      next if($k eq "cmd" || $k eq "oCmd" || $k eq "arg" || $k eq "packetType");
      my ($off, $len, $type) = split(",", $ptr->{$k});
      my $data;
      if ($len == 0) {
        $data = substr($rawmsg, $off*2);
      } else {
        $data = substr($rawmsg, $off*2, $len*2);
      }
      if ($type) {
        if ($type eq "STR") {
          $data = pack('H*', $data);
          ####
          # remove trailing 0x00
          #$data =~ s/[^A-Za-z0-9#\.\-_]//g;
          $data =~ tr/A-Za-z0-9#.-_//cd;
        } else {
          my $dataLen = length($data);
          my $dataOut = '';
          my ($part1, $part2, $part3) = split(":", $type);
          $part1 *= 2;
          $part2 *= 2;
          if (defined $part3) {
            $part3 *= 2;
            while ($dataLen > 0) {
              $data =~ m/^(.{$part1})(.{$part2})(.{$part3})(.*)$/;
              $dataOut .= $1 . ':' . $2 . ':' . $3 . ' ';
              $data = $4;
              $dataLen -= $part1 + $part2 + $part3;
            }
          } else {
            while ($dataLen > 0) {
              $data =~ m/^(.{$part1})(.{$part2})(.*)$/;
              $dataOut .= $1 . ':' . $2 . ' ';
              $data = $3;
              $dataLen -= $part1 + $part2;
            }
          }
          chop($dataOut);
          $data = $dataOut;
        }
      }
      push @ans, "$k: $data";
    }
    $msg = join(" ", @ans);
  }
  if ($msg eq "") {
    Log3 $name, 5, "TCM $name RESPONSE: OK";
  } else {
    Log3 $name, 2, "TCM $name RESPONSE: $msg";
  }
  return $msg;
}

# Ready
sub TCM_Ready($) {
  my ($hash) = @_;
  my $ret;
  if ($hash->{STATE} eq "disconnected") {
  #if($hash->{STATE} ne "opened") {
    $ret = DevIo_OpenDev($hash, 1, undef);
    return $ret if (defined $ret);
    TCM_InitSerialCom($hash) if (DevIo_IsOpen($hash));
    return $ret;
  }

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  return undef if(!$po);
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes > 0);
}

# Get commands TCM 120
my %gets120 = (
  "sensitivity"  => "AB48",
  "baseID"       => "AB58",
  "modem_status" => "AB68",
  "version"      => "AB4B",
);

# Get commands TCM 310
my %gets310 = (
  "baseID" => {packetType => 5, cmd => "08", BaseID => "1,4", RemainingWriteCycles => "5,1"},
  "dutycycleLimit" => {packetType => 5, cmd => "23", DutyCycle => "1,1", Slots => "2,1", SlotPeriod => "3,2", ActualSlotLeft => "5,2", LoadAfterActual => "7,1"},
  "filter" => {packetType => 5, cmd => "0F", "Type:Value" => "1,0,1:4"},
  "frequencyInfo" => {packetType => 5, cmd => "25", Frequency => "1,1", Protocol => "2,1"},
  "noiseThreshold" => {packetType => 5, cmd => "33", NoiseThreshold => "1,1"},
  "numSecureDevicesIn" => {packetType => 5, cmd => "1D", oCmd => "00", Number => "1,1"},
  "numSecureDevicesOut" => {packetType => 5, cmd => "1D",oCmd => "01", Number => "1,1"},
  "remanRepeating" => {packetType => 5, cmd => "31", Repeated => "1,1"},
  "repeater" => {packetType => 5, cmd => "0A", RepEnable => "1,1", RepLevel => "2,1"},
  "stepCode" => {packetType => 5, cmd => "27", HWRevision => "1,1", Stepcode => "2,1"},
  "smartAckLearnMode" => {packetType => 6, cmd => "02", Enable => "1,1", Extended => "2,1"},
  "smartAckLearnedClients" => {packetType => 6, cmd => "06", "ClientID:CtrlID:Mailbox" => "1,0,4:4:1"},
  "version" => {packetType => 5, cmd => "03", APPVersion => "1,4", APIVersion => "5,4", ChipID => "9,4", ChipVersion => "13,4", Desc => "17,16,STR"},
);

# Get
sub TCM_Get($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  return if (AttrVal($name, "comType", "TCM") eq "RS485" || $hash->{DeviceName} eq "none");
  return "\"get $name\" needs one parameter" if(@a != 2);
  my $cmd = $a[1];
  my ($err, $msg, $packetType);

  if($hash->{MODEL} eq "ESP2") {
    # TCM 120
    my $rawcmd = $gets120{$cmd};
    return "Unknown argument $cmd, choose one of " . join(':noArg ', sort keys %gets120) . ':noArg' if(!defined($rawcmd));
    Log3 $name, 3, "TCM $name get $cmd";
    $rawcmd .= "000000000000000000";
    TCM_Write($hash, $hash, "", $rawcmd);
    ($err, $msg) = TCM_ReadAnswer($hash, "get $cmd");
    $msg = TCM_Parse120($hash, $msg, 1) if(!$err);

  } else {
    # TCM 310
    my $cmdhash = $gets310{$cmd};
    if (!defined($cmdhash) && $cmd !~ m/^getFreeID|getUsedID$/) {
      return "Unknown argument $cmd, choose one of getFreeID:noArg getUsedID:noArg " . join(':noArg ', sort keys %gets310) . ':noArg';
    }
    Log3 $name, 3, "TCM $name get $cmd";
    if ($cmd eq 'getFreeID') {
      $msg = substr(EnOcean_CheckSenderID('getFreeID', $name, 8 x '0'), 1);
    } elsif ($cmd eq 'getUsedID') {
      $msg = EnOcean_CheckSenderID('getUsedID', $name, 8 x '0');
    } else {
      my $cmdHex = $cmdhash->{cmd};
      my $oCmdHex = '';
      $oCmdHex = $cmdhash->{oCmd} if (exists $cmdhash->{oCmd});
      $hash->{helper}{SetAwaitCmdResp} = $cmdhash;
      TCM_Write($hash, $hash, sprintf("%04X%02X%02X", length($cmdHex)/2, length($oCmdHex)/2, $cmdhash->{packetType}), $cmdHex . $oCmdHex);
      ($err, $msg) = TCM_ReadAnswer($hash, "get $cmd");
      $msg = TCM_Parse310($hash, $msg, $cmdhash) if(!$err);
    }
  }
  if($err) {
    Log3 $name, 2, "TCM $name $err";
    return $err;
  }
  readingsSingleUpdate($hash, $cmd, $msg, 1);
  return $msg;
}

# Set commands TCM 120
my %sets120 = (    # Name, Data to send to the CUL, Regexp for the answer
  "teach"  => {cmd => "AB18", arg => "\\d+"},
  "baseID"  => {cmd => "AB18", arg => "FF[8-9A-F][0-9A-F]{5}"},
  "sensitivity" => {cmd => "AB08", arg => "0[01]"},
  "sleep" => {cmd => "AB09"},
  "wake" => {cmd => ""}, # Special
  "reset" => {cmd => "AB0A"},
  "modem_on" => {cmd => "AB28", arg => "[0-9A-F]{4}"},
  "modem_off" => {cmd => "AB2A"},
);

# Set commands TCM 310
my %sets310 = (
  "baseID" => {packetType => 5, cmd => "07", arg => "FF[8-9A-F][0-9A-F]{5}"},
  "baudrate" => {packetType => 5, cmd => "24", arg => "0[0-3]"},
  "bist" => {packetType => 5, cmd => "06", BIST_Result => "1,1"},
  "filterAdd" => {packetType => 5, cmd => "0B", arg => "0[0-3][0-9A-F]{8}[048C]0"},
  "filterDel" => {packetType => 5, cmd => "0C", arg => "0[0-3][0-9A-F]{8}"},
  "filterDelAll" => {packetType => 5, cmd => "0D"},
  "filterEnable" => {packetType => 5, cmd => "0E", arg => "0[01]0[0189]"},
  "init" => {},
  "maturity" => {packetType => 5, cmd => "10", arg => "0[0-2]"},
  "mode" => {packetType => 5, cmd => "1C", arg => "0[0-1]"},
  "noiseThreshold" => {packetType => 5, cmd => "32", arg => "2E|2F|3[0-8]"},
  "pskAdd" => {arg => "[0-9a-fA-F]{32}"},
  "pskDel" => {},
  "remanCode" => {packetType => 5, cmd => "2E", arg => "[0-9A-F]{8}"},
  "remanRepeating" => {packetType => 5, cmd => "30", arg => "0[0-1]"},
  "reset" => {packetType => 5, cmd => "02"},
  "resetEvents" => {},
  "repeater" => {packetType => 5, cmd => "09", arg => "0[0-1]0[0-2]"},
  "sleep" => {packetType => 5, cmd => "01", arg => "00[0-9A-F]{6}"},
  "smartAckLearn" => {packetType => 6, cmd => "01", arg => "\\d+"},
  "smartAckMailboxMax" => {packetType => 6, cmd => "08", arg => "\\d+"},
  "startupDelay" => {packetType => 5, cmd => "2F", arg => "[0-9A-F]{2}"},
  "subtel" => {packetType => 5, cmd => "11", arg => "0[0-1]"},
  "teach" => {packetType => 1, arg => "\\d+"},
);

# clear teach in flag
sub TCM_ClearTeach($) {
  my $hash = shift;
  foreach my $iName (keys %defs) {
    delete $defs{$iName}{Teach} if ($defs{$iName}{TYPE} eq 'TCM');
  }
  delete($modules{"$hash->{TYPE}"}{Teach});
  Log3 $hash->{NAME}, 3, "TCM $hash->{NAME} set teach 0";
  if($hash->{MODEL} ne 'ESP2') {
    # signal telegram learn mode status
    my $cmdhex = 'D011B' . 'F' x 17 . $hash->{ChipID} . '0' x 2;
    my ($err, $msg);
    $hash->{helper}{SetAwaitCmdResp} = $sets310{'teach'};
    TCM_Write($hash, $hash, sprintf("%04X00%02X", length($cmdhex)/2, 1), $cmdhex);
    ($err, $msg) = TCM_ReadAnswer($hash, "set teach");
     if(!$err) {
       $msg = TCM_Parse310($hash, $msg, $sets310{'teach'});
     }
  }
  return;
}

# clear Smart ACK teach in flag
sub TCM_ClearSmartAckLearn($) {
  my $hash = shift;
  delete($hash->{SmartAckLearn});
  delete($modules{"$hash->{TYPE}"}{SmartAckLearn});
  readingsSingleUpdate($hash, "smartAckLearnMode", "Enable: 00 Extended: 00", 1);
}

# Set
sub TCM_Set($@) {
  my ($hash, @a) = @_;
  my $name = $hash->{NAME};
  return if (AttrVal($name, "comType", "TCM") eq "RS485" || $hash->{DeviceName} eq "none");
  return "\"set $name\" needs at least one parameter" if(@a < 2);
  my $cmd = $a[1];
  my $arg = $a[2];
  my ($err, $msg);
  my $chash = ($hash->{MODEL} eq "ESP2" ? \%sets120 : \%sets310);
  my $cmdhash = $chash->{$cmd};
  return "Unknown argument $cmd, choose one of ".join(" ",sort keys %{$chash}) if(!defined($cmdhash));

  my $cmdHex = $cmdhash->{cmd};
  my $argre = $cmdhash->{arg};
  my $logArg = defined($arg) ? $arg : '';
  if($argre) {
    return "Argument needed for set $name $cmd ($argre)" if (!defined($arg));
    return "Argument does not match the regexp ($argre)" if ($arg !~ m/$argre/i);
    if ($cmd eq "pskAdd") {
      $modules{"$hash->{TYPE}"}{STE}{psk} = $arg;
      Log3 $name, 3, "TCM $name set $cmd $logArg";
      return;
    } elsif ($cmd eq "smartAckLearn") {
      if (($arg + 0) >= 0 && ($arg + 0) <= 4294967) {
        if ($arg == 0) {
          $arg = '0' x 12;
          readingsSingleUpdate($hash, "smartAckLearnMode", "Enable: 00 Extended: 00", 1);
        } else {
          my $smartAckLearnMode = AttrVal($name, "smartAckLearnMode", "simple");
          my %smartAckLearnMode = (simple => 0, advance => 1, advanceSelectRep => 2);
          $arg = sprintf "01%02X%08X", $smartAckLearnMode{$smartAckLearnMode}, $arg * 1000;
          readingsSingleUpdate($hash, "smartAckLearnMode", "Enable: 01 Extended: " . sprintf("%02X", $smartAckLearnMode{$smartAckLearnMode}), 1);
        }
      } else {
        return "Argument wrong, choose 0...4294967";
      }
    } elsif ($cmd eq "smartAckMailboxMax") {
      if (($arg + 0) >= 0 && ($arg + 0) <= 20) {
        $attr{$name}{smartAckMailboxMax} = $arg;
        $arg = sprintf "%02X", $arg;
      } else {
        return "Argument wrong, choose 0...20";
      }
    }

    $cmdHex .= $arg;
  }
  Log3 $name, 3, "TCM $name set $cmd $logArg";

  if($cmd eq "pskDel") {
    delete $modules{"$hash->{TYPE}"}{STE}{psk};
    return;
  } elsif($cmd eq "teach") {
    if ($arg == 0) {
      RemoveInternalTimer($hash, "TCM_ClearTeach");
      while (my ($iDev, $iHash) = each (%{$modules{"$hash->{TYPE}"}{devHash}})) {
        #Log3 $name, 3, "TCM $name clear Teach flag ioDev: $iDev ioHash: $iHash ioDevName: " . $defs{"$iHash->{NAME}"}->{NAME};
        delete $defs{"$iHash->{NAME}"}->{Teach};
      }
      delete $modules{"$hash->{TYPE}"}{Teach};
      return if ($hash->{MODEL} eq "ESP2");
      # signal telegram learn mode status
      $cmdHex = 'D011B' . 'F' x 17 . $hash->{ChipID} . '0' x 2;
    } else {
      while (my ($iDev, $iHash) = each (%{$modules{"$hash->{TYPE}"}{devHash}})) {
        #Log3 $name, 2, "TCM $name clear Teach flag ioDev: $iDev ioHash: $iHash ioDevName: " . $defs{"$iHash->{NAME}"}->{NAME};
        delete $defs{"$iHash->{NAME}"}->{Teach};
      }
      $hash->{Teach} = 1;
      $modules{"$hash->{TYPE}"}{Teach} = $hash;
      #Log3 $name, 2, "TCM $name set Teach flag ioHash: " . $modules{"$hash->{TYPE}"}{Teach};
      RemoveInternalTimer($hash, "TCM_ClearTeach");
      InternalTimer(gettimeofday() + $arg, "TCM_ClearTeach", $hash, 1);
      return if ($hash->{MODEL} eq "ESP2");
      # signal telegram learn mode status
      my $remainTime = $arg < 10 ? 1 : int($arg / 10);
      $remainTime = $remainTime < 254 ? $remainTime : 254;
      $cmdHex = 'D0114F' . sprintf("%02X", $remainTime) . 'F' x 14 . $hash->{ChipID} . '0' x 2;
    }
  }

  if($hash->{MODEL} eq "ESP2") {
    # TCM 120
    if($cmdHex eq "") {            # wake is very special
      DevIo_SimpleWrite($hash, "AA", 1);
      return "";
    }
    $cmdHex .= "0" x (22 - length($cmdHex));  # Padding with 0
    TCM_Write($hash, $hash, "", $cmdHex);
    ($err, $msg) = TCM_ReadAnswer($hash, "get $cmd");
    $msg = TCM_Parse120($hash, $msg, 1) if(!$err);

  } else {
    # TCM310
    if($cmd eq "init") {
      TCM_InitSerialCom($hash);
      return;
    }
    if($cmd eq "resetEvents") {
      delete $hash->{RESET_CAUSE};
      delete $hash->{SECURE_MODE};
      delete $hash->{DUTYCYCLE_LIMIT};
      delete $hash->{TRANSMIT_FAILED};
      return;
    }
    $hash->{helper}{SetAwaitCmdResp} = $cmdhash;
    TCM_Write($hash, $hash, sprintf("%04X00%02X", length($cmdHex)/2, $cmdhash->{packetType}), $cmdHex);
    ($err, $msg) = TCM_ReadAnswer($hash, "set $cmd");
    if(!$err) {
      $msg = TCM_Parse310($hash, $msg, $cmdhash);
      if ($cmd eq "smartAckLearn") {
        if (substr($arg, 0, 2) eq '00') {
          # end Smart ACK learnmode
          RemoveInternalTimer($hash, "TCM_ClearSmartAckLearn");
          delete $hash->{SmartAckLearn};
          delete $modules{"$hash->{TYPE}"}{SmartAckLearn};
        } else {
          RemoveInternalTimer($hash, "TCM_ClearSmartAckLearn");
          InternalTimer(gettimeofday() + hex(substr($arg, 4, 8)) * 0.001, "TCM_ClearSmartAckLearn", $hash, 1);
          $hash->{SmartAckLearn} = 1;
          $modules{"$hash->{TYPE}"}{SmartAckLearn} = $hash;
          Log3 $name, 3, "TCM $name set SmartAckLearn flag ioHash: " . $modules{"$hash->{TYPE}"}{SmartAckLearn};
        }
      }
    }
  }
  if($err) {
    Log3 $name, 2, "TCM $name $err";
    return $err;
  }

  my @setCmdReadingsUpdate = ("repeater", "maturity", "mode");
  foreach(@setCmdReadingsUpdate) {
    if ($_ eq $cmd && $msg eq "") {
      if ($_ eq "repeater") {
        $arg = "RepEnable: " . substr($arg, 0, 2) . " RepLevel: " . substr($arg, 2, 2);
      }
      readingsSingleUpdate($hash, $cmd, $arg, 1);
    }
  }
  return $msg;
}

# read command response data
sub TCM_ReadAnswer($$) {
  my ($hash, $arg) = @_;
  return ("No FD", undef) if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));
  my $name = $hash->{NAME};
  my $blockSenderID = AttrVal($name, "blockSenderID", "own");
  my ($data, $rin, $buf) = ($hash->{PARTIAL}, "", "");
  # 2 seconds timeout
  my $to = 2;
  for (;;) {
    if ($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      if (length($buf) == 0) {
        if (length($data) == 0) {
          shift(@{$hash->{helper}{awaitCmdResp}});
          return ("Timeout reading answer for $arg", undef);
        }
      } else {
        $data .= uc(unpack('H*', $buf));
      }

    } else {
      if (!$hash->{FD}) {
        shift(@{$hash->{helper}{awaitCmdResp}});
        return ("Device lost when reading answer for $arg", undef);
      }
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if ($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        DevIo_Disconnected($hash);
        shift(@{$hash->{helper}{awaitCmdResp}});
        return("Device error: $err", undef);
      } elsif ($nfound == 0) {
        if (length($data) == 0) {
          shift(@{$hash->{helper}{awaitCmdResp}});
          return ("Timeout reading response for $arg", undef);
        }
      } else {
        $buf = DevIo_SimpleRead($hash);
        if(!defined($buf)) {
          shift(@{$hash->{helper}{awaitCmdResp}});
          return ("No response data for $arg", undef);
        }
        $data .= uc(unpack('H*', $buf));
      }
    }

    if (length($data) > 4) {
      #Log3 $name, 5, "TCM $name received ESP: $data";

      if ($hash->{MODEL} eq "ESP2") {
        # TCM 120
        if (length($data) >= 28) {
          if ($data !~ m/^A55A(.B.{20})(..)/) {
            $hash->{PARTIAL} = '';
            return ("$arg: Bogus answer received: $data", undef);
          }

          Log3 $name, 5, "TCM $name received ESP: $data";

          my ($net, $crc) = ($1, $2);
          my $mycrc = TCM_CSUM($net);
          $hash->{PARTIAL} = substr($data, 28);
          if ($crc ne $mycrc) {
            return ("wrong data checksum: got $crc, computed $mycrc", undef);
          }
          return (undef, $net);
        }

      } else {
        # TCM 310
        if($data !~ m/^55/) {
          $data =~ s/.*55/55/;
          if ($data !~ m/^55/) {
            #$data = '';
            $hash->{PARTIAL} = '';
            shift(@{$hash->{helper}{awaitCmdResp}});
            return ("$arg: Bogus answer received: $data", undef);
          }
          $hash->{PARTIAL} = $data;
        }
        next if ($data !~ m/^55(....)(..)(..)(..)/);
        my ($ldata, $lodata, $packetType, $crc) = (hex($1), hex($2), hex($3), $4);
        my $tlen = 2 * (7 + $ldata + $lodata);
        # data telegram incomplete
        next if (length($data) < $tlen);
        my $rest = substr($data, $tlen);
        $data = substr($data, 0, $tlen);

        Log3 $name, 5, "TCM $name received ESP: $data";

        my $hdr = substr($data, 2, 8);
        my $mdata = substr($data, 12, $ldata * 2);
        my $odata = substr($data, 12 + $ldata * 2, $lodata * 2);
        my $mycrc = TCM_CRC8($hdr);
        if ($crc ne $mycrc) {
          $hash->{PARTIAL} = $rest;
          shift(@{$hash->{helper}{awaitCmdResp}});
          return ("wrong header checksum: got $crc, computed $mycrc", undef);
        }
        $mycrc = TCM_CRC8($mdata . $odata);
        $crc  = substr($data, -2);
        if ($crc ne $mycrc) {
          $hash->{PARTIAL} = $rest;
          shift(@{$hash->{helper}{awaitCmdResp}});
          return ("wrong data checksum: got $crc, computed $mycrc", undef);
        }

        if ($packetType == 1) {
          # packet type RADIO
          $mdata =~ m/^(..)(.*)(........)(..)$/;
          my ($org, $d1, $id, $status) = ($1, $2, $3, $4);
          my $repeatingCounter = hex substr($status, 1, 1);
          $odata =~ m/^(..)(........)(..)(..)$/;
          my ($RSSI, $receivingQuality) = (hex($3), "excellent");
          if ($RSSI > 87) {
            $receivingQuality = "bad";
          } elsif ($RSSI > 75) {
            $receivingQuality = "good";
          }
          my %addvals = (
            PacketType       => $packetType,
            SubTelNum        => hex($1),
            DestinationID    => $2,
            RSSI             => -$RSSI,
            ReceivingQuality => $receivingQuality,
            RepeatingCounter => $repeatingCounter,
          );
          $hash->{RSSI} = -$RSSI;

          if (!defined TCM_BlockSenderID($hash, $blockSenderID, $id)) {
            #EnOcean:PacketType:RORG:MessageData:SourceID:Status:OptionalData
            Dispatch($hash, "EnOcean:$packetType:$org:$d1:$id:$status:$odata", \%addvals) if (exists $hash->{helper}{init_done});
          }
          $data = $rest;
          $hash->{PARTIAL} = $rest;
          next;
        } elsif($packetType == 2) {
        # packet type RESPONSE
          $hash->{PARTIAL} = $rest;
          if (defined $hash->{helper}{awaitCmdResp}[0] && $hash->{helper}{awaitCmdResp}[0]) {
            shift(@{$hash->{helper}{awaitCmdResp}});
            return (undef, $mdata . $odata);
          } else {
            shift(@{$hash->{helper}{awaitCmdResp}});
            $mdata =~ m/^(..)(.*)$/;
            my $rc = $1;
            my $rcTxt = $esp3Rc{$rc} if ($esp3Rc{$rc});
            Log3 $name, $rc eq "00" ? 5 : 2, "TCM $name RESPONSE: $rcTxt";
            #$packetType = sprintf "%01X", $packetType;
            #EnOcean:PacketType:ResposeCode:MessageData:OptionalData
            #Dispatch($hash, "EnOcean:$packetType:$1:$2:$odata", undef);
            $data = $rest;
            next;
          }
        } elsif ($packetType == 4) {
          #####
          # packet type EVENT
          $mdata =~ m/^(..)(.*)$/;
          my $eventCode = $1;
          my $messageData = $2;
          if (hex($eventCode) <= 3) {
            my $packetTypeHex = sprintf "%01X", $packetType;
            #EnOcean:PacketType:eventCode:messageData
            Dispatch($hash, "EnOcean:$packetTypeHex:$eventCode:$messageData", undef);
          } elsif (hex($eventCode) == 4) {
            # CO_READY
            my @resetCause = ('voltage_supply_drop', 'reset_pin', 'watchdog', 'flywheel', 'parity_error', 'hw_parity_error', 'memory_request_error', 'wake_up_pin_0', 'wake_up_pin_1', 'unknown', 'wake_up_uart', 'sw_reset');
            my @secureMode = ('standard', 'extended');
            $hash->{RESET_CAUSE} = $resetCause[hex($messageData)];
            $hash->{SECURE_MODE} = $secureMode[hex($odata)];
            Log3 $name, 2, "TCM $name EVENT RESET_CAUSE: $hash->{RESET_CAUSE} SECURE_MODE: $hash->{SECURE_MODE}";
          } elsif (hex($eventCode) == 5) {
            # CO_EVENT_SECUREDEVICES
          } elsif (hex($eventCode) == 6) {
            # CO_DUTYCYCLE_LIMIT
            my @dutycycleLimit = ('released', 'reached');
            $hash->{DUTYCYCLE_LIMIT} = $dutycycleLimit[hex($messageData)];
            Log3 $name, 2, "TCM $name EVENT DUTYCYCLE_LIMIT: $hash->{DUTYCYCLE_LIMIT}";
          } elsif (hex($eventCode) == 7) {
            # CO_TRANSMIT_FAILED
            my @transmitFailed = ('CSMA_failed', 'no_ack_received');
            $hash->{TRANSMIT_FAILED} = $transmitFailed[hex($messageData)];
            Log3 $name, 2, "TCM $name EVENT TRANSMIT_FAILED: $hash->{TRANSMIT_FAILED}";
          }
          $data = $rest;
          $hash->{PARTIAL} = $rest;
          next;
        } else {
          return ("$arg ERROR: received data telegram PacketType: $packetType Data: $mdata not supported.", undef)
        }
      }
    }
  }
}

sub TCM_BlockSenderID($$$) {
  my ($hash, $blockSenderID, $senderID) = @_;
  return undef if ($blockSenderID eq 'no');
  return undef if (!exists $modules{"$hash->{TYPE}"}{BaseID});
  foreach (@{$modules{"$hash->{TYPE}"}{BaseID}}) {
    if (hex($_) == (hex($senderID) & 0xFFFFFF80)) {
      Log3 $hash->{NAME}, 4, "TCM $hash->{NAME} received own telegram from SenderID $senderID blocked.";
      return 1;
    }
  }
  return undef if (!exists $modules{"$hash->{TYPE}"}{ChipID});
  foreach (@{$modules{"$hash->{TYPE}"}{ChipID}}) {
    if (hex($_) == hex($senderID)) {
      Log3 $hash->{NAME}, 4, "TCM $hash->{NAME} received own telegram from $senderID blocked.";
      return 1;
    }
  }
  return undef;
}

#
sub TCM_msgCounter($) {
  my $hash = shift(@_);
  my $timeNow = time();
  my ($count, $countPerDay, $countPerHour, $countPerMin);
  RemoveInternalTimer($hash, 'TCM_msgCounter');
  if (AttrVal($hash->{NAME}, 'msgCounter', 'off') eq 'off') {
    delete $hash->{MsgRcvPerDay};
    delete $hash->{MsgRcvPerHour};
    delete $hash->{MsgRcvPerMin};
    delete $hash->{MsgSndPerDay};
    delete $hash->{MsgSndPerHour};
    delete $hash->{MsgSndPerMin};
    return undef;
  }
  # receive counter
  if (exists $hash->{helper}{rcvCounter}) {
    ($count, $countPerDay, $countPerHour, $countPerMin) = (0, 0, 0, 0);
    foreach my $timestamp (@{$hash->{helper}{rcvCounter}}) {
      $countPerDay = $count if ($timestamp < $timeNow - 86400);
      $countPerHour = $count if ($timestamp < $timeNow - 3600);
      $countPerMin = $count if ($timestamp < $timeNow - 60);
      $count ++;
    }
    splice(@{$hash->{helper}{rcvCounter}}, 0, $countPerDay);
    $hash->{MsgRcvPerDay} = $#{$hash->{helper}{rcvCounter}};
    $hash->{MsgRcvPerHour} = $hash->{MsgRcvPerDay} + $countPerDay - $countPerHour;
    $hash->{MsgRcvPerMin} = $hash->{MsgRcvPerDay} + $countPerDay - $countPerMin;
  }
  # send counter
  if (exists $hash->{helper}{sndCounter}) {
    ($count, $countPerDay, $countPerHour, $countPerMin) = (0, 0, 0, 0);
    foreach my $timestamp (@{$hash->{helper}{sndCounter}}) {
      $countPerDay = $count if ($timestamp < $timeNow - 86400);
      $countPerHour = $count if ($timestamp < $timeNow - 3600);
      $countPerMin = $count if ($timestamp < $timeNow - 60);
      $count ++;
    }
    splice(@{$hash->{helper}{sndCounter}}, 0, $countPerDay);
    $hash->{MsgSndPerDay} = $#{$hash->{helper}{sndCounter}};
    $hash->{MsgSndPerHour} = $hash->{MsgSndPerDay} + $countPerDay - $countPerHour;
    $hash->{MsgSndPerMin} = $hash->{MsgSndPerDay} + $countPerDay - $countPerMin;
  }
  InternalTimer(time() + 60, 'TCM_msgCounter', $hash, 0);
  return undef;
}

#
sub TCM_Attr(@) {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  my $hash = $defs{$name};
  # return if attribute list is incomplete
  return undef if (!$init_done);

  if ($attrName eq "assignIODev") {
    if (!defined $attrVal) {
      if (exists $modules{TCM}{assignIODev}) {
        delete($modules{TCM}{assignIODev}) if ($modules{TCM}{assignIODev} eq $hash);
      }
    } elsif ($attrVal eq 'no') {
      if (exists $modules{TCM}{assignIODev}) {
        delete($modules{TCM}{assignIODev}) if ($modules{TCM}{assignIODev} eq $hash);
      }
    } elsif ($attrVal eq 'yes') {
      $modules{TCM}{assignIODev} = $hash;
    } else {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
      if (exists $modules{TCM}{assignIODev}) {
        delete($modules{TCM}{assignIODev}) if ($modules{TCM}{assignIODev} eq $hash);
      }
    }

  } elsif ($attrName eq "baseID") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[Ff]{2}[\dA-Fa-f]{4}[08]0$/ || $attrVal =~ m/^[Ff]{8}$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    } else {
      $hash->{BaseID} = $attrVal;
      $hash->{LastID} = sprintf "%08X", (hex $attrVal) + 127;
    }

  } elsif ($attrName  =~ m/^\.(base|chip)IDSaved$/) {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[Ff]{2}[\dA-Fa-f]{6}$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "blockSenderID") {
    if (!defined $attrVal) {

    } elsif ($attrVal !~ m/^own|no$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "comModeUTE") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^auto|biDir|uniDir$/) {
      Log3 $name, 2, "EnOcean $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "comType") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^TCM|RS485$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "fingerprint") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^off|on$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "learningDev") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^all|teachMsg$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "learningMode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^always|demand|nearfield$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "msgCounter") {
    if (!defined $attrVal){
      RemoveInternalTimer($hash, 'TCM_msgCounter');
    } elsif ($attrVal eq 'off') {
      RemoveInternalTimer($hash, 'TCM_msgCounter');
    } elsif ($attrVal eq 'on') {
      RemoveInternalTimer($hash, 'TCM_msgCounter');
      InternalTimer(time() + 60, 'TCM_msgCounter', $hash, 0);
    } else {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "rcvIDShift") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^[\dA-Fa-f]{6}[08]0$/ || $attrVal =~ m/^[Ff]{8}$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "sendInterval") {
    if (!defined $attrVal){

    } elsif (($attrVal + 0) < 0 || ($attrVal + 0) > 250) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong or out of range";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  } elsif ($attrName eq "smartAckLearnMode") {
    if (!defined $attrVal){

    } elsif ($attrVal !~ m/^simple|advance|advanceSelectRep$/) {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong";
      CommandDeleteAttr(undef, "$name $attrName");
    }
  } elsif ($attrName eq "smartAckMailboxMax") {
    if (!defined $attrVal){

    } elsif (($attrVal + 0) >= 0 && ($attrVal + 0) <= 20) {
      TCM_Set($hash, ("set", "smartAckMailboxMax", $attrVal));
    } else {
      Log3 $name, 2, "TCM $name attribute-value [$attrName] = $attrVal wrong or out of range";
      CommandDeleteAttr(undef, "$name $attrName");
    }

  }
  return undef;
}

#
sub TCM_Notify(@) {
  my ($hash, $dev) = @_;
  if ($dev->{TYPE} eq 'Global' && grep (m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}})){
  #if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}})){
    RemoveInternalTimer($hash, 'TCM_msgCounter');
    InternalTimer(time() + 60, 'TCM_msgCounter', $hash, 0) if (AttrVal($hash->{NAME}, 'msgCounter', 'off') eq 'on');
    TCM_InitSerialCom($hash);
    my $assignIODevFlag = AttrVal($hash->{NAME}, 'assignIODev', undef);
    if (defined $assignIODevFlag) {
      if ($assignIODevFlag eq 'yes') {
        $modules{TCM}{assignIODev} = $hash;
      } else {
        if (exists $modules{TCM}{assignIODev}) {
          delete($modules{TCM}{assignIODev}) if ($modules{TCM}{assignIODev} eq $hash);
        }
      }
    }
    if (exists $modules{$modulesType}{ChipID}) {
      if (@{$modules{$modulesType}{ChipID}} <= 1) {
        # one transmitter currently registered
        #$attr{$hash->{NAME}}{fingerprint} = 'off';
        #Log3 $hash->{NAME}, 2, "TCM $hash->{NAME} Atribute fingerprint: off";
      } else {
        # more then one transmitter currently registered
        if (!exists $attr{$dev->{NAME}}{dupTimeout}) {
          $attr{$dev->{NAME}}{dupTimeout} = $dupTimeout;
          Log3 $dev->{NAME}, 2, "$dev->{TYPE} $dev->{NAME} Attribute dupTimeout: $attr{$dev->{NAME}}{dupTimeout}";
        }
        while (my ($iDev, $iHash) = each (%{$modules{$modulesType}{devHash}})) {
          if (!exists $attr{$iDev}{fingerprint}) {
            $attr{$iDev}{fingerprint} = 'on';
            Log3 $iDev, 2, "TCM $iDev Attribute fingerprint: $attr{$iDev}{fingerprint}";
          }
        }
      }
      if (exists($modules{"$hash->{TYPE}"}{BaseID}) && exists($modules{"$hash->{TYPE}"}{ChipID})) {
        Log3 $hash->{NAME}, 2, "TCM registered transceiver BaseID: " . join(':', @{$modules{"$hash->{TYPE}"}{BaseID}}) . " ChipID: " . join(':', @{$modules{"$hash->{TYPE}"}{ChipID}});
      }
    }
  }
  return undef;
}

# Undef
sub TCM_Undef($$) {
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};
  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) && defined($defs{$d}{IODev}) && $defs{$d}{IODev} == $hash) {
      my $lev = ($reread_active ? 4 : 2);
      Log3 $name, $lev, "TCM $name deleting port for $d";
      delete $defs{$d}{IODev};
    }
  }
  DevIo_CloseDev($hash);
  if (exists $modules{"$hash->{TYPE}"}{BaseID}) {
    for (my $i = 0; $i <= @{$modules{"$hash->{TYPE}"}{BaseID}}; $i++) {
      if (${$modules{"$hash->{TYPE}"}{BaseID}}[$i] eq $hash->{BaseID}) {
        Log3 $name, 4, "TCM $name remove module BaseID: " . ${$modules{"$hash->{TYPE}"}{BaseID}}[$i];
        splice(@{$modules{"$hash->{TYPE}"}{BaseID}}, $i, 1);
        last;
      }
    }
  }
  if (exists $modules{"$hash->{TYPE}"}{ChipID}) {
    for (my $i = 0; $i <= @{$modules{"$hash->{TYPE}"}{ChipID}}; $i++) {
      if (${$modules{"$hash->{TYPE}"}{ChipID}}[$i] eq $hash->{ChipID}) {
        Log3 $name, 4, "TCM $name remove module ChipID: " . ${$modules{"$hash->{TYPE}"}{ChipID}}[$i];
        splice(@{$modules{"$hash->{TYPE}"}{ChipID}}, $i, 1);
        last;
      }
    }
  }
  RemoveInternalTimer($hash, 'TCM_msgCounter');
  delete $hash->{helper}{init_done};
  return undef;
}

# Shutdown
sub TCM_Shutdown($) {
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  return undef;
}

1;

=pod
=item summary    EnOcean Serial Protocol Inferface (ESP2/ESP3)
=item summary_DE EnOcean Serial Protocol Interface (ESP2/ESP3)
=begin html

<a id="TCM"></a>
<h3>TCM</h3>
<ul>
  The TCM module serves an USB or TCP/IP connected TCM 120 or TCM 310x, TCM 410J, TCM 515
  EnOcean Transceiver module. These are mostly packaged together with a serial to USB
  chip and an antenna, e.g. the BSC BOR contains the TCM 120, the <a
  href="http://www.enocean.com/de/enocean_module/usb-300-oem/">USB 300</a> from
  EnOcean and the EUL from busware contains a TCM 310 or TCM 515. See also the datasheet
  available from <a href="http://www.enocean.com">www.enocean.com</a>.
  <br>
  As the TCM 120 and the TCM 310, TCM 410J, TCM 515 speak completely different protocols, this
  module implements 2 drivers in one. It is the "physical" part for the <a
  href="#EnOcean">EnOcean</a> module.<br><br>
  Please note that EnOcean repeaters also send Fhem data telegrams again. Use
  <code>attr &lt;name&gt; <a href="#TCM-attr-blockSenderID">blockSenderID</a> own</code>
  to block receiving telegrams with TCM SenderIDs.<br>
  The address range used by your transceiver module, can be found in the
  parameters BaseID and LastID.
  <br><br>
  The transceiver moduls do not always support all commands. The supported range
  of commands depends on the hardware and the firmware version. A firmware update
  is usually not provided.
  <br><br>

  <b>Eltako RS485 bus</b>
  <ul>
  The TCM module enables also a wired connection to Eltako actuators over the
  Eltako RS485 bus in the switchboard or distribution box via Eltako FGW14 RS232-RS485
  gateway modules. These actuators are linked to an associated wireless antenna module
  (FAM14) on the bus. The FAM14 device frequently polls the actuator status of all
  associated devices if the FAM14 operating mode rotary switch is on position 4.
  Therefore, actuator states can be retrieved more reliable, even after any fhem downtime,
  when switch events or actuator confirmations could not have been tracked during the
  downtime. As all actuators are polled approx. every 1-2 seconds, it should be avoided to
  use event-on-update-reading. Use instead either event-on-change-reading or
  event-min-interval.
  The Eltako bus uses the EnOcean Serial Protocol version 2 (ESP2). For this reason,
  a FGW14 can be configured as a ESP2. The attribute <a href="#TCM-attr-comType">comType</a>
  must be set to RS485.
  </ul>
  <br>

  <b>Multi-transceiver operation</b>
  <ul>
  It is possible to operate multiple transceivers in one Fhem instance in parallel.
  EnOcean repeaters meet the usual requirements for increasing range in homes much more
  easily than a multi-transceiver instance. It is interesting to operate several transceivers
  but with extensive building complexes. In addition, the radio channel utilization can be
  reduced compared to the use of several repeaters when self-contained spatial zones are formed.
  After all, multiple transceivers can increase the number of available SenderIDs in Fhem.<br><br>
  Within an Fhem installation with multiple transceivers, one of these transceivers sends the
  outgoing telegrams. The transceiver is assigned to IODev when an EnOcean device is set up. One of
  the enabled transceivers can be specifically selected as the transmitting device (IODev) for manual
  setup of EnOcean devices. For this purpose, the attribute<br>
  <ul><code>attr &lt;name&gt; assignIODev yes</code></ul>
  must be set.
  <br><br>
  For teach-in sensors or actuators, the desired transceiver must be set by<br>
  <ul><code>set &lt;name&gt; teach &lt;t/s&gt;</code></ul>
  into learning mode.
  <br><br>
  Incoming telegrams are received by all transceivers. Duplicates are determined and
  suppressed by the fingerprint function. This function must be used for each transceiver using the<br>
  <ul><code>attr &lt;name&gt; fingerprint on</code></ul>
  activated. Furthermore, the global attribute must be<br>
  <ul><code>attr global dupTimeout 0.6</code></ul>
  or larger. The attributes are set automatically if they have not already been manually defined.
  <br><br>
  Transceivers on remote servers have been tested with the Linux service ser2net. For example,
  ser2net can be set up on a Raspberry PI Remote server for a transceiver on the
  /dev/ttyUSB0@57600 USB port (8, 'none', 1) in the following steps:<br><br>
  Package provisioning<br>
  <ul><code>sudo apt install ser2net</code></ul>
  Configuration in the file: /etc/ser2net.conf<br>
  <ul><code>7000:raw:0:/dev/ttyUSB0:57600 8DATABITS NONE 1STOPBIT HANGUP_WHEN_DONE</code></ul>
  Program start for a test<br>
  <ul><code>sudo ser2net -n</code></ul>
  Automatically boot (insert script /etc/init.d/ser2net into startup procedure)<br>
  <ul><code>sudo update-rc.d ser2net defaults</code></ul>
  Take program from the autostart<br>
  <ul><code>sudo update-rc.d -f ser2net remove</code></ul><br>
  On the remote server, ser2net and Fhem should not be active in parallel.
  During Fhem start, the autocreate function may inadvertently integrate the transceiver
  into Fhem and then errors occur.<br><br>
  On the target system, the transceiver is then connected to the IP address of the remote server via<br>
  <ul><code>define TCM_Remote TCM ESP3 &lt;ip1&gt;.&lt;ip2&gt;.<ip3>&lt;ip3&gt;.&lt;ip4&gt;:7000</code></ul>
  set up.<br><br>
  Only ESP3 transceivers have been tested.
  </ul>
  <br>

  <a id="TCM-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TCM [ESP2|ESP3] &lt;device&gt;</code> <br>
    <br>
    First you have to specify the type of the EnOcean Transceiver Chip, i.e
    either ESP2 for the TCM 120 or ESP3 for the TCM 310x, TCM 410J, TCM 515, USB 300, USB400J, USB 500.<br><br>
    <code>device</code> can take the same parameters (@baudrate, @directio,
    TCP/IP, none), but you probably have
    to specify the baudrate: the TCM 120 should be opened with 9600 Baud, the
    TCM 310 and TCM 515 with 57600 baud. For Eltako FGW14 devices, type has to be set to 120 and
    the baudrate has to be set to 57600 baud if the FGW14 operating mode
    rotary switch is on position 6.<br><br>

    Example:
    <ul><code>
      define BscBor TCM ESP2 /dev/ttyACM0@9600<br>
      define FGW14 TCM ESP2 /dev/ttyS3@57600<br>
      define TCM310 TCM ESP3 /dev/ttyACM0@57600<br>
      define TCM310 TCM ESP3 COM1@57600 (Windows)<br>
    </code></ul>
  </ul>
  <br>

  <a id="TCM-set"></a>
  <b>Set</b><br>
  <ul><b>ESP2 (TCM 120)</b><br>
    <li>baseID [FF000000 ... FFFFFF80]<br>
      Set the BaseID.<br>
      Note: The firmware executes this command only up to then times to prevent misuse.</li>
    <li>modem_off<br>
      Deactivates TCM modem functionality</li>
    <li>modem_on [0000 ... FFFF]<br>
      Activates TCM modem functionality and sets the modem ID</li>
    <li>reset<br>
      Reset the device</li>
    <li>sensitivity [00|01]<br>
      Set the TCM radio sensitivity: low = 00, high = 01</li>
    <li>sleep<br>
      Enter the energy saving mode</li>
    <li>teach &lt;t/s&gt;<br>
      Set Fhem in learning mode, see <a href="#TCM-attr-learningMode">learningMode</a> and <a href="#TCM-attr-learningDev">learningDev</a>.<br>
      The command is always required for UTE and to teach-in bidirectional actuators
      e. g. EEP 4BS (RORG A5-20-XX),
      see <a href="#EnOcean-teach-in">Teach-In / Teach-Out</a>.</li>
    <li>wake<br>
      Wakes up from sleep mode</li>
    <br>
    For details see the TCM 120 User Manual available from <a href="http://www.enocean.com">www.enocean.com</a>.
  <br><br>
  </ul>
  <ul><b>ESP3 (TCM 310x, TCM 410J, TCM 515, USB 300, USB400J, USB 515)</b><br>
    <li><a id="TCM-set-baseID">baseID</a> [FF000000 ... FFFFFF80]<br>
      Set the BaseID.<br>
      Note: The firmware executes this command only up to then times to prevent misuse.</li>
    <li><a id="TCM-set-baudrate">baudrate</a> [00|01|02|03]<br>
      Modifies the baud rate of the EnOcean device.<br>
      baudrate = 00: 56700 baud (default)<br>
      baudrate = 01: 115200 baud<br>
      baudrate = 02: 230400 baud<br>
      baudrate = 03: 460800 baud</li>
    <li><a id="TCM-set-bist">bist</a><br>
      Perform Flash BIST operation (Built-in-self-test).</li>
    <li><a id="TCM-set->filterAdd">>filterAdd</a &lt;FilterType&gt;&lt;FilterValue&gt;&lt;FilterKind&gt;<br>
      Add filter to filter list. Description of the filter parameters and examples, see
      <a href="https://www.enocean.com/esp">EnOcean Serial Protocol 3 (ESP3)</a></li>
    <li><a id="TCM-set-filterDel">filterDel</a> &lt;FilterType&gt;&lt;FilterValue&gt;<br>
      Del filter from filter list. Description of the filter parameters, see
      <a href="https://www.enocean.com/esp">EnOcean Serial Protocol 3 (ESP3)</a></li>
    <li><a id="TCM-set-filterDelAll">filterDelAll</a><br>
      Del all filter from filter list.</li>
    <li><a id="TCM-set-filterEnable">filterEnable</a> &lt;FilterON/OFF&gt;&lt;FilterOperator&gt;<br>
      Enable/Disable all supplied filters. Description of the filter parameters, see
      <a href="https://www.enocean.com/esp">EnOcean Serial Protocol 3 (ESP3)</a></li>
    <li><a id="TCM-set-init">init</a><br>
      Initialize serial communication and transceiver configuration</li>
    <li><a id="TCM-set-maturity">maturity</a> [00|01|02]<br>
      Waiting till end of maturity time before received radio telegrams will transmit:
      radio telegrams are send immediately = 00 (default mode), after the maturity time is elapsed = 01, all received Sub-telegrams shall be forwarded immediately = 02</li>
    <li><a id="TCM-set-mode">mode</a> [00|01]<br>
      mode = 00: Compatible mode - ERP1 - gateway uses Packet Type 1 to transmit and receive radio telegrams<br>
      mode = 01: Advanced mode - ERP2 - gateway uses Packet Type 10 to transmit and receive radio telegrams
      (for FSK products with advanced protocol)</li>
    <li><a id="TCM-set-noiseThreshold">noiseThreshold</a> [2E|2F|30|31|32|33|34|35|36|37|38]<br>
      Modifies the noise threshold of the EnOcean device.<br>
      noiseThreshold = 2E: -100 dBm<br>
      noiseThreshold = 2F: -99 dBm<br>
      noiseThreshold = 30: -98 dBm<br>
      noiseThreshold = 31: -97 dBm<br>
      noiseThreshold = 32: -96 dBm (default)<br>
      noiseThreshold = 33: -95 dBm<br>
      noiseThreshold = 34: -94 dBm<br>
      noiseThreshold = 35: -93 dBm<br>
      noiseThreshold = 36: -92 dBm<br>
      noiseThreshold = 37: -91 dBm<br>
      noiseThreshold = 38: -90 dBm</li>
    <li><a id="TCM-set-pskAdd">pskAdd</a> [16 byte hex]<br>
      Set the pre-shared key (psk) for secure teach-in. The key is stored until the Fhem restart.</li>
    <li><a id="TCM-set-pskDel">pskDel</a><br>
      Delete the pre-shared key (psk) for secure teach-in.</li>
    <li><a id="TCM-set-remanCode">remanCode</a> [00000000-FFFFFFFF]<br>
      Sets secure code to unlock Remote Management functionality by radio.</li>
    <li><a id="TCM-set-remanRepeating">remanRepeating</a> [00|01]<br>
      Select if REMAN telegrams originating from this module can be repeated: off = 00, on = 01.</li>
    <li><a id="TCM-set-reset">reset</a><br>
      Reset the device</li>
    <li><a id="TCM-set-resetEvents">resetEvents</a><br>
      Reset generated events</li>
    <li><a id="TCM-set-repeater">repeater</a> [0000|0101|0102]<br>
      Set Repeater Level: off = 0000, 1 = 0101, 2 = 0102.</li>
    <li><a id="TCM-set-sleep">sleep</a> &lt;t/10 ms&gt; (Range: 00000000 ... 00FFFFFF)<br>
      Enter the energy saving mode</li>
    <li><a id="TCM-set-smartAckLearn">smartAckLearn</a> &lt;t/s&gt;<br>
      Set Fhem in Smart Ack learning mode.<br>
      The post master fuctionality must be activated using the command <code>smartAckMailboxMax</code> in advance.<br>
      The simple learnmode is supported, see <a href="#TCM-attr-smartAckLearnMode">smartAckLearnMode</a><br>
      A device, which is then also put in this state is to paired with
      Fhem. Bidirectional learn in for 4BS, UTE and Generic Profiles are supported.<br>
      <code>t/s</code> is the time for the learning period.</li>
    <li><a id="TCM-set-smartAckMailboxMax">smartAckMailboxMax</a> 0..20<br>
      Enable the post master fuctionality and set amount of mailboxes available, 0 = disable post master functionality.
      Maximum 28 mailboxes can be created. This upper limit is for each firmware restricted and may be smaller.</li>
    <li><a id="TCM-set-startupDelay">startupDelay</a> [00-FF]<br>
      Sets the startup delay [10ms]: the time before the system initializes.</li>
    <li><a id="TCM-set-subtel">subtel</a> [00|01]<br>
      Transmitting additional subtelegram info: Enable = 01, Disable = 00</li>
    <li><a id="TCM-set-teach">teach</a> &lt;t/s&gt;<br>
      Set Fhem in learning mode for RBS, 1BS, 4BS, GP, STE and UTE teach-in / teach-out, see <a href="#TCM-attr-learningMode">learningMode</a>
      and <a href="#TCM-attr-learningDev">learningDev</a>.<br>
      The command is always required for STE, GB, UTE and to teach-in bidirectional actuators
      e. g. EEP 4BS (RORG A5-20-XX), see <a href="#EnOcean-teach-in">Teach-In / Teach-Out</a>.</li>
    <br>
    For details see the EnOcean Serial Protocol 3 (ESP3) available from
    <a href="http://www.enocean.com">www.enocean.com</a>.
    <br><br>
  </ul>

  <a id="TCM-get"></a>
  <b>Get</b><br>
  <ul><b>TCM 120</b><br>
    <li>baseID<br>
      Get the BaseID. You need this command in order to control EnOcean devices,
      see the <a href="#EnOcean-define">EnOcean</a> paragraph.
      </li>
    <li>modem_status<br>
      Requests the current modem status.</li>
    <li>sensitivity<br>
      Get the TCM radio sensitivity, low = 00, high = 01</li>
    <li>version<br>
      Read the device SW version / HW version, chip-ID, etc.</li>
    <br>
    For details see the TCM 120 User Manual available from <a href="http://www.enocean.com">www.enocean.com</a>.
    <br><br>
  </ul>
  <ul><b>TCM 310</b><br>
    <li><a id="TCM-get-baseID">baseID</a><br>
      Get the BaseID. You need this command in order to control EnOcean devices,
      see the <a href="#EnOcean-define">EnOcean</a> paragraph.</li>
    <li><a id="TCM-get-dutycycleLimi">dutycycleLimi</a>t<br>
       Read actual duty cycle limit values.</li>
    <li><a id="TCM-get-filter">filter</a><br>
      Get supplied filters. Description of the filter parameters, see
      <a href="https://www.enocean.com/esp">EnOcean Serial Protocol 3 (ESP3)</a></li>
    <li><a id="TCM-get-freqencyInfo">freqencyInfo</a><br>
      Reads Frequency and protocol of the Device, see
      <a href="https://www.enocean.com/esp">EnOcean Serial Protocol 3 (ESP3)</a></li>
    <li><a id="TCM-get-getFreeID">getFreeID</a><br>
      Get free Transceiver SenderIDs.</li>
    <li><a id="TCM-get-getUsedID">getUsedID</a><br>
      Get used Transceiver SenderIDs.</li>
    <li><a id="TCM-get-numSecureDev">numSecureDev</a><br>
      Read number of teached in secure devices.</li>
    <li><a id="TCM-get-remanRepeating">remanRepeating</a><br>
      REMAN telegrams originating from this module can be repeated: off = 00, on = 01.</li>
    <li><a id="TCM-get-repeater">repeater</a><br>
      Read Repeater Level: off = 0000, 1 = 0101, 2 = 0102.</li>
    <li><a id="TCM-get-smartAckLearnMode">smartAckLearnMode</a><br>
      Get current smart ack learn mode<br>
      Enable: 00|01 = off|on<br>
      Extended: 00|01|02 = simple|advance|advanceSelectRep</li>
    <li><a id="TCM-get-smartAckLearnedClients">smartAckLearnedClients</a><br>
      Get information about the learned smart ack clients</li>
    <li><a id="TCM-get-stepCode">stepCode</a><br>
      Reads Hardware Step code and Revision of the Device, see
      <a href="https://www.enocean.com/esp">EnOcean Serial Protocol 3 (ESP3)</a></li>
    <li><a id="TCM-get-version">version</a><br>
      Read the device SW version / HW version, chip-ID, etc.</li>
    <br>
    For details see the EnOcean Serial Protocol 3 (ESP3) available from
    <a href="http://www.enocean.com">www.enocean.com</a>.
    <br><br>
  </ul>

  <a id="TCM-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a id="TCM-attr-assignIODev">assignIODev</a> &lt;no|yes&gt;,
      [assignIODev] = no is default.<br>
      Transceiver used as IO device (IODev) for manually set up EnOcean devices.
    </li>
    <li><a id="TCM-attr-blockSenderID">blockSenderID</a> &lt;own|no&gt;,
      [blockSenderID] = own is default.<br>
      Block receiving telegrams with a TCM SenderID sent by repeaters.
    </li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a id="TCM-attr-baseID">baseID</a> &lt;FF000000 ... FFFFFF80&gt;,
      [baseID] = <none> is default.<br>
      Set Transceiver baseID and override automatic allocation. Use this attribute only if the IODev does not allow automatic allocation.
      The BaseID must be set in increments of 0x80.
    </li>
    <li><a id="TCM-attr-fingerprint">fingerprint</a> &lt;off|on&gt;,
      [fingerprint] = off is default.<br>
      Activate the fingerprint function. The fingerprint function eliminates multiple identical data telegrams received via different TCM modules.<br>
      The function must be activated for each TCM module.
    </li>
    <li><a id="TCM-attr-comModeUTE">comModeUTE</a> &lt;auto|biDir|uniDir&gt;,
      [comModeUTE] = auto is default.<br>
      Presetting the communication method of actuators that be taught using the UTE teach-in. The automatic selection of the
      communication method should only be overwrite manually, if this is explicitly required in the operating instructions of
      the actuator. The parameters should then be immediately re-set to "auto".
      </li>
    <li><a id="TCM-attr-comType">comType</a> &lt;TCM|RS485&gt;,
      [comType] = TCM is default.<br>
      Type of communication device
    </li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a id="TCM-attr-learningDev">learningDev</a> &lt;all|teachMsg&gt;,
      [learningDev] = teachMsg is default.<br>
      Learning method for automatic setup of EnOcean devices:<br>
      [learningDev] = all: All incoming telegrams generate device definitions<br>
      [learningDev] = teachMsg: Only incoming learning telegrams generate device definitions. RPS telegrams always create new devices due to principle.<br>
    </li>
    <li><a id="TCM-attr-learningMode">learningMode</a> &lt;always|demand|nearfield&gt;,
      [learningMode] = demand is default.<br>
      Learning method for automatic setup of EnOcean devices:<br>
      [learningMode] = always: Teach-In/Teach-Out telegrams always accepted, with the exception of bidirectional devices<br>
      [learningMode] = demand: Teach-In/Teach-Out telegrams accepted if Fhem is in learning mode, see also <code>set &lt;IODev&gt; teach &lt;t/s&gt;</code><br>
      [learningMode] = nearfield: Teach-In/Teach-Out telegrams accepted if Fhem is in learning mode and the signal strength RSSI >= -60 dBm.<be>
    </li>
    <li><a id="TCM-attr-msgCounter">msgCounter</a> &lt;off|on&gt;,
      [msgCounter] = off is default.<br>
      Counts the received and sent messages in the last day, last hour, and minute, see internals MsgRcvPerDay, MsgSndPerDay,
      MsgRcvPerHour, MsgSndPerHour, MsgRcvPerMin MsgSndPerMin.
    </li>
    <li><a id="TCM-attr-rcvIDShift">rcvIDShift</a> &lt;00000080 ... FFFFFF80&gt;,
      [rcvIDShift] = <none> is default.<br>
      Shift the address range of the received data telegrams. The attribute is supported only for the ESP2 protocol.
      The rcvIDShift must be set in increments of 0x80.
    </li>
    <li><a id="TCM-attr-sendInterval">sendInterval</a> &lt;0 ... 250&gt;<br>
      ESP2: [sendInterval] = 100 ms is default.<br>
      ESP3: [sendInterval] = 0 ms is default.<br>
      Smallest interval between two sending telegrams
    </li>
    <li><a id="TCM-attr-smartAckLearnMode">smartAckLearnMode</a> &lt;simple|advance|advanceSelectRep&gt;<br>
      select Smart Ack learn mode; only simple supported by Fhem
    </li>
    <li><a id="TCM-attr-smartAckMailboxMax">smartAckMailboxMax</a> &lt;0 ... 28&gt;<br>
      Amount of mailboxes available, 0 = disable post master functionality.
      Maximum 28 mailboxes can be created. This upper limit is for each firmware restricted and may be smaller.
    </li>
    <li><a href="#verbose">verbose</a></li>
    <br><br>
  </ul>

  <a id="TCM-events"></a>
  <b>Generated events</b>
  <ul>
    <li>baseID &lt;transceiver response&gt;</li>
    <li>maturity 00|01</li>
    <li>modem_status &lt;transceiver response&gt;</li>
    <li>numSecureDev &lt;transceiver response&gt;</li>
    <li>repeater 0000|0101|0102</li>
    <li>sensitivity 00|01</li>
    <li>version &lt;transceiver response&gt;</li>
    <li>state: opend|initialized</li>
    <br><br>
  </ul>
</ul>

=end html
=cut

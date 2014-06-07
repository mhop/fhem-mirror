
# $Id$

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub JeeLink_Attr(@);
sub JeeLink_Clear($);
sub JeeLink_HandleWriteQueue($);
sub JeeLink_Parse($$$$);
sub JeeLink_Read($);
sub JeeLink_ReadAnswer($$$$);
sub JeeLink_Ready($);
sub JeeLink_Write($$);

sub JeeLink_SimpleWrite(@);
sub JeeLink_ResetDevice($);

my $clientsJeeLink = ":PCA301:EC3000:RoomNode:LaCrosse:ETH200comfort:CUL_IR:HX2272:FS20:AliRF";

my %matchListPCA301 = (
    "1:PCA301"          => "^\\S+\\s+24",
    "2:EC3000"          => "^\\S+\\s+22",
    "3:RoomNode"        => "^\\S+\\s+11",
    "4:LaCrosse"        => "^\\S+\\s+9 ",
    "5:AliRF"           => "^\\S+\\s+5 ",
);

my %matchListJeeLink433 = (
    "1:CUL_IR"  => "^I............\$",  #I
    "2:HX2272"  => "^O01[A-F0-9]{4}\$", #O0112A0
);
my %matchListJeeLink868 = (
    "1:LaCrosse"                        => "^F01[A-F0-9]{8}\$", #F019205396A
    "2:ETH200comfort"                   => "^F020[AC][0-9A-F]{8}\$", #F020A01004200
    "3:CUL_IR"                          => "^I............\$",  #I
    "4:FS20"                            => "^O02[A-F0-9]{8}\$", #O02D28C0000
);

my %RxListJeeLink = (
        "HX2272" => "Or",
        "FS20" => "Or",
        "LaCrosse"      => "Fr01",
);

#my %JeeLinkCmds = (
#       "868" => {
#               "FS20"                  => "Or",
#               "LaCrosse"      => "Fr01",
#       },
#       "433" => {
#               "HX2272"                => "Or",
#       },
#);

sub
JeeLink_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "JeeLink_Read";
  $hash->{WriteFn} = "JeeLink_Write";
  $hash->{ReadyFn} = "JeeLink_Ready";

# Normal devices
  $hash->{DefFn}        = "JeeLink_Define";
  $hash->{FingerprintFn}   = "JeeLink_Fingerprint";
  $hash->{UndefFn}      = "JeeLink_Undef";
  $hash->{GetFn}        = "JeeLink_Get";
  $hash->{SetFn}        = "JeeLink_Set";
  $hash->{AttrFn}       = "JeeLink_Attr";
  $hash->{AttrList} = "Clients MatchList"
                      ." hexFile"
                      ." initCommands"
                      ." flashCommand"
                      ." DebounceTime BeepLong BeepShort BeepDelay"
                      ." tune " . join(" ", map { "tune_$_" } keys %RxListJeeLink)
                      ." $readingFnAttributes";

  $hash->{ShutdownFn} = "JeeLink_Shutdown";
}
sub
JeeLink_Fingerprint($$)
{
}


#####################################
sub
JeeLink_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> JeeLink {devicename[\@baudrate] ".
                        "| devicename\@directio}";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];

  my $dev = $a[2];
  $dev .= "\@57600" if( $dev !~ m/\@/ );

  $hash->{Clients} = $clientsJeeLink;
  $hash->{MatchList} = \%matchListPCA301;

  if( !defined( $attr{$name}{flashCommand} ) ) {
    $attr{$name}{flashCommand} = "avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]"
  }

  $hash->{DeviceName} = $dev;

  my $ret = DevIo_OpenDev($hash, 0, "JeeLink_DoInit");
  return $ret;
}

#####################################
sub
JeeLink_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if(defined($defs{$d}) &&
       defined($defs{$d}{IODev}) &&
       $defs{$d}{IODev} == $hash)
      {
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  JeeLink_Shutdown($hash);
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
JeeLink_Shutdown($)
{
  my ($hash) = @_;
  ###JeeLink_SimpleWrite($hash, "X00");
  return undef;
}

sub
JeeLink_RemoveLaCrossePair($)
{
  my $hash = shift;
  delete($hash->{LaCrossePair});
}

#####################################
sub
JeeLink_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);


  my $list = "beep raw led:on,off led-on-for-timer reset LaCrossePairForSec setReceiverMode:LaCrosse,HX2272,FS20 flash";
  return $list if( $cmd eq '?' || $cmd eq '');


  if($cmd eq "raw") {
    Log3 $name, 4, "set $name $cmd $arg";
    JeeLink_SimpleWrite($hash, $arg);

  } elsif( $cmd eq "beep" ) {
    # +    = Langer Piep
    # -    = Kurzer Piep
    # anderes = Pause
    my $longbeep = AttrVal($name, "BeepLong", "250");
    my $shortbeep = AttrVal($name, "BeepShort", "100");
    my $delaybeep = AttrVal($name, "BeepDelay", "0.25");

    for(my $i=0;$i<length($arg);$i++) {
      my $x=substr($arg,$i,1);
      if($x eq "+") {
              # long beep
              JeeLink_Write($hash, "bFF" . $longbeep);
      } elsif($x eq "-") {
              # short beep
              JeeLink_Write($hash, "bFF" . $shortbeep);
      }
      select(undef, undef, undef, $delaybeep);
    }
  }
  elsif( $cmd eq "flash" ) {
    my @args = split(' ', $arg);
    my $log = "";
    my $hexFile = "";
    my @deviceName = split('@', $hash->{DeviceName});
    my $port = $deviceName[0];
    my $defaultHexFile = "./hexfiles/$hash->{TYPE}-LaCrosseITPlusReader10.hex";
    my $logFile = AttrVal("global", "logdir", "./log") . "/JeeLinkFlash.log";


    if(!$arg || $args[0] !~ m/^(\w|\/|.)+$/) {
      $hexFile = AttrVal($name, "hexFile", "");
      if ($hexFile eq "") {
        $hexFile = $defaultHexFile;
      }
    }
    else {
      $hexFile = $args[0];
    }

    return "Usage: set $name flash [filename]\n\nor use the hexFile attribute" if($hexFile !~ m/^(\w|\/|.)+$/);

    $log .= "flashing JeeLink $name\n";
    $log .= "hex file: $hexFile\n";
    $log .= "port: $port\n";
    $log .= "log file: $logFile\n";

    my $flashCommand = AttrVal($name, "flashCommand", "");

    if($flashCommand ne "") {
      if (-e $logFile) {
        unlink $logFile;
      }

      DevIo_CloseDev($hash);
      $hash->{STATE} = "disconnected";
      $log .= "$name closed\n";

      my $avrdude = $flashCommand;
      $avrdude =~ s/\Q[PORT]\E/$port/g;
      $avrdude =~ s/\Q[HEXFILE]\E/$hexFile/g;
      $avrdude =~ s/\Q[LOGFILE]\E/$logFile/g;

      $log .= "command: $avrdude\n\n";
      `$avrdude`;

      local $/=undef;
      if (-e $logFile) {
        open FILE, $logFile;
        my $logText = <FILE>;
        close FILE;
        $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n";
        $log .= $logText;
        $log .= "--- AVRDUDE ---------------------------------------------------------------------------------\n\n";
      }
      else {
        $log .= "WARNING: avrdude created no log file\n\n";
      }

    }
    else {
      $log .= "\n\nNo flashCommand found. Please define this attribute.\n\n";
    }

    DevIo_OpenDev($hash, 0, "JeeLink_DoInit");
    $log .= "$name opened\n";

    return $log;
  }

  elsif( $cmd eq "LaCrossePairForSec" ) {
    my @args = split(' ', $arg);

    return "Usage: set $name LaCrossePairForSec <seconds_active> [ignore_battery]" if(!$arg || $args[0] !~ m/^\d+$/ || ($args[1] && $args[1] ne "ignore_battery") );
    $hash->{LaCrossePair} = $args[1]?2:1;
    InternalTimer(gettimeofday()+$args[0], "JeeLink_RemoveLaCrossePair", $hash, 0);

  } elsif( $cmd eq "setReceiverMode" ) {
    return "Usage: set $name setReceiverMode (LaCrosse,HX2272,FS20)"  if($arg !~ m/^(LaCrosse|HX2272|FS20)$/);

    #Get tune values of Transceiver if needed (TX+RX)
    my $TuneStr = undef;
    my $AttrStr = AttrVal($name, "tune_" . $arg, undef);
    $AttrStr = AttrVal($name, "tune", undef) if(!(defined $AttrStr));
    $TuneStr = JeeLink_CalcTuneCmd($AttrStr) if(defined $AttrStr);

    JeeLink_Write($hash, $RxListJeeLink{$arg});     #set receiver
    JeeLink_Write($hash, "t" . $TuneStr) if(defined $TuneStr); #set modified tune

    #reset debounce time for OOK Signals
    if($RxListJeeLink{$arg} =~ m/^O/) {
        my $DebStr = AttrVal($name, "DebounceTime", undef);
        JeeLink_Write($hash, "Od" . $DebStr) if(defined $DebStr);
    }

    JeeLink_Write($hash, "f");  # update RFM configuration in FHEM (returns e.g. "FSK-868MHz")

    Log3 $name, 4, "set $name $cmd $arg";

  } elsif ($cmd =~ m/^led$/i) {
    return "Unknown argument $cmd, choose one of $list" if($arg !~ m/^(on|off)$/i);

    Log3 $name, 4, "set $name $cmd $arg";
    if($hash->{model} =~ m/LaCrosseITPlusReader./i ) {
      JeeLink_Write($hash, ($arg eq "on" ? "1" : "0") ."a" );
    }
    else {
      JeeLink_Write($hash, "l" . ($arg eq "on" ? "1" : "0") );
    }
  } elsif ($cmd =~ m/led-on-for-timer/i) {
    return "Unknown argument $cmd, choose one of $list" if($arg !~ m/^[0-9]+$/i);

    #remove timer if there is one active
    if($modules{JeeLink}{ldata}{$name}) {
    CommandDelete(undef, $name . "_timer");
    delete $modules{JeeLink}{ldata}{$name};
    }

    Log3 $name, 4, "set $name on";
    if($hash->{model} =~ m/LaCrosseITPlusReader./i ) {
      JeeLink_Write($hash, "1a");
    }
    else {
      JeeLink_Write($hash, "l" . "1");
    }

    my $to = sprintf("%02d:%02d:%02d", $arg/3600, ($arg%3600)/60, $arg%60);
    $modules{JeeLink}{ldata}{$name} = $to;
    Log3 $name, 4, "Follow: +$to setstate $name off";
    CommandDefine(undef, $name."_timer at +$to {fhem(\"set $name led" ." off\")}");

  } elsif ($cmd =~ m/reset/i) {
    return JeeLink_ResetDevice($hash);

  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

#####################################
sub
JeeLink_Get($@)
{
  my ($hash, $name, $cmd, @msg ) = @_;
  my $arg = join(" ", @msg);

  my $list = "devices:noArg initJeeLink:noArg RFMconfig:noArg updateAvailRam:noArg raw";

  if( $cmd eq "devices" ) {
    if($hash->{model} =~m/JeeNode -- HomeControl -/ ) {
      JeeLink_SimpleWrite($hash, "h");
    } else {
      JeeLink_SimpleWrite($hash, "l");
        }
  } elsif( $cmd eq "initJeeLink" ) {

        $hash->{STATE} = "Opened";

        if($hash->{model} =~m/JeeNode -- HomeControl -/ ) {
                JeeLink_SimpleWrite($hash, "o");
        } else {
            JeeLink_SimpleWrite($hash, "0c");
        JeeLink_SimpleWrite($hash, "2c");
                }

        } elsif ($cmd eq "raw" ) {
                return "raw => 01" if($arg =~ m/^Ir/);  ## Needed for CUL_IR usage (IR-Receive is always on for JeeLinks

        } elsif ($cmd eq "RFMconfig" ) {
                JeeLink_SimpleWrite($hash, "f");

        } elsif ($cmd eq "updateAvailRam" ) {
                        JeeLink_SimpleWrite($hash, "m");

  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

sub
JeeLink_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 1;
  for(;;) {
    my ($err, undef) = JeeLink_ReadAnswer($hash, "Clear", 0, undef);
    last if($err && $err =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});
}

#####################################
sub
JeeLink_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my $val;

  JeeLink_Clear($hash);

  $hash->{STATE} = "Opened";

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});

  return undef;
}

#####################################
# This is a direct read for commands like get
# Anydata is used by read file to get the filesize
sub
JeeLink_ReadAnswer($$$$)
{
  my ($hash, $arg, $anydata, $regexp) = @_;
  my $type = $hash->{TYPE};

  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($mpandata, $rin) = ("", '');
  my $buf;
  my $to = 3;                                         # 3 seconds timeout
  $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
  for(;;) {

    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("Timeout reading answer for get $arg", undef)
        if(length($buf) == 0);

    } else {
      return ("Device lost when reading answer for get $arg", undef)
        if(!$hash->{FD});

      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        DevIo_Disconnected($hash);
        return("JeeLink_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if($buf) {
      Log3 $hash->{NAME}, 5, "JeeLink/RAW (ReadAnswer): $buf";
      $mpandata .= $buf;
    }

    chop($mpandata);
    chop($mpandata);

    return (undef, $mpandata)
  }

}

#####################################
# Check if the 1% limit is reached and trigger notifies
sub
JeeLink_XmitLimitCheck($$)
{
  my ($hash,$fn) = @_;
  my $now = time();

  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # 163 comes from fs20. todo: verify if correct for JeeLink modulation

    my $name = $hash->{NAME};
    Log3 $name, 2, "JeeLink TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
sub
JeeLink_Write($$)
{
        my ($hash, $cmd, $msg) = @_;
        my $name = $hash->{NAME};
        my $arg = $cmd;
        $arg .= " " . $msg if(defined($msg));

        #Modify command for CUL_IR
        $arg =~ s/^\s+|\s+$//g;
        $arg =~ s/^Is/I/i;  #SendIR command is "I" not "Is" for JeeLink devices

  Log3 $name, 5, "$name sending $arg";

  JeeLink_AddQueue($hash, $arg);
  #JeeLink_SimpleWrite($hash, $msg);
}

sub
JeeLink_SendFromQueue($$)
{
  my ($hash, $bstring) = @_;
  my $name = $hash->{NAME};
  my $to = 0.05;

  if($bstring ne "") {
    my $sp = AttrVal($name, "sendpool", undef);
    if($sp) {   # Is one of the JeeLink-fellows sending data?
      my @fellows = split(",", $sp);
      foreach my $f (@fellows) {
        if($f ne $name &&
           $defs{$f} &&
           $defs{$f}{QUEUE} &&
           $defs{$f}{QUEUE}->[0] ne "")
          {
            unshift(@{$hash->{QUEUE}}, "");
            InternalTimer(gettimeofday()+$to, "JeeLink_HandleWriteQueue", $hash, 0);
            return;
          }
      }
    }

    JeeLink_XmitLimitCheck($hash,$bstring);
    JeeLink_SimpleWrite($hash, $bstring);
  }

  InternalTimer(gettimeofday()+$to, "JeeLink_HandleWriteQueue", $hash, 0);
}

sub
JeeLink_AddQueue($$)
{
  my ($hash, $bstring) = @_;
  if(!$hash->{QUEUE}) {
    $hash->{QUEUE} = [ $bstring ];
    JeeLink_SendFromQueue($hash, $bstring);

  } else {
    push(@{$hash->{QUEUE}}, $bstring);
  }
}

#####################################
sub
JeeLink_HandleWriteQueue($)
{
  my $hash = shift;
  my $arr = $hash->{QUEUE};
  if(defined($arr) && @{$arr} > 0) {
    shift(@{$arr});
    if(@{$arr} == 0) {
      delete($hash->{QUEUE});
      return;
    }
    my $bstring = $arr->[0];
    if($bstring eq "") {
      JeeLink_HandleWriteQueue($hash);
    } else {
      JeeLink_SendFromQueue($hash, $bstring);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
JeeLink_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  my $pandata = $hash->{PARTIAL};
  Log3 $name, 5, "JeeLink/RAW: $pandata/$buf";
  $pandata .= $buf;

  while($pandata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$pandata) = split("\n", $pandata, 2);
    $rmsg =~ s/\r//;
    JeeLink_Parse($hash, $hash, $name, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $pandata;
}

sub
JeeLink_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  my $dmsg = $rmsg;
  #my $l = length($dmsg);
  my $rssi;
  #my $rssi = hex(substr($dmsg, 1, 2));
  #$rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
  my $lqi;
  #my $lqi = hex(substr($dmsg, 3, 2));
  #$dmsg = substr($dmsg, 6, $l-6);
  #Log3, $name, 5, "$name: $dmsg $rssi $lqi";

  next if(!$dmsg || length($dmsg) < 1);            # Bogus messages
  return if($dmsg =~ m/^Available commands:/ );    # ignore startup messages
  return if($dmsg =~ m/^  / );                     # ignore startup messages
  return if($dmsg =~ m/^-> ack/ );                 # ignore send ack

  if($dmsg =~ m/^\[/ ) {
        $hash->{model} = $dmsg;

    if( $hash->{STATE} eq "Opened" ) {
      if( my $initCommandsString = AttrVal($name, "initCommands", undef) ) {
        my @initCommands = split(' ', $initCommandsString);
        foreach my $command (@initCommands) {
          JeeLink_SimpleWrite($hash, $command);
        }

      } elsif( $dmsg =~m /pcaSerial/ ) {
        $hash->{MatchList} = \%matchListPCA301;
        JeeLink_SimpleWrite($hash, "1a" ); # led on
        JeeLink_SimpleWrite($hash, "1q" ); # quiet mode
        #JeeLink_SimpleWrite($hash, "0x" ); # hex mode off
        JeeLink_SimpleWrite($hash, "0a" ); # led off
        JeeLink_SimpleWrite($hash, "l" );  # list known devices

      }
      elsif( $dmsg =~m /LaCrosseITPlusReader/ ) {
        $hash->{MatchList} = \%matchListPCA301;

      } elsif( $dmsg =~m /ec3kSerial/ ) {
        $hash->{MatchList} = \%matchListPCA301;
        #JeeLink_SimpleWrite($hash, "ec", 1);

      } elsif( $dmsg =~m /JeeNode -- HomeControl -/ ) {
        $hash->{MatchList} = \%matchListJeeLink433 if($dmsg =~ m/433MHz/);
                                $hash->{MatchList} = \%matchListJeeLink868 if($dmsg =~ m/868MHz/);
        JeeLink_SimpleWrite($hash, "q1");  # turn quiet mode on
        JeeLink_SimpleWrite($hash, "a0");  # turn activity led off
        JeeLink_SimpleWrite($hash, "f");   # get RFM frequence config
        JeeLink_SimpleWrite($hash, "m");   # show used ram on jeenode
      }

      $hash->{STATE} = "Initialized";
    }

    return;

  } elsif ( $dmsg =~ m/^(OOK|FSK)\-(433|868)MHz/ ) {
        readingsSingleUpdate($hash,"RFM-config",$dmsg,0);
        return;

  } elsif ( $dmsg =~ m/^Ram available: </ ) {
        $dmsg =~ s/^.*<(.*)>.*$/$1/;
        readingsSingleUpdate($hash,"RAM-Available",$dmsg,0);
        return;

  } elsif( $dmsg =~ m/drecvintr exit/ ) {
        # command "ec" will not work with the EC3000, use reset instead
        Log3 $hash, 0, "$name: drecvintr detected";
        JeeLink_ResetDevice($hash);

        #JeeLink_SimpleWrite($hash, "ec",1);
  } elsif( $dmsg =~ m/RFM12 hang/ ) {
        # EC3000 seems not to recover from an RFM12 hang, so do a reset
        Log3 $hash, 0, "$name: RFM12 hang detected";
        JeeLink_ResetDevice($hash);

    return;
  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;
  my %addvals = (RAWMSG => $rmsg);
  if(defined($rssi)) {
    $hash->{RSSI} = $rssi;
    $addvals{RSSI} = $rssi;
  }
  if(defined($lqi)) {
    $hash->{LQI} = $lqi;
    $addvals{LQI} = $lqi;
  }

#Adapt JeeLink command (O02D28C0000) to match FS20 command ("^81..(04|0c)..0101a001") from CUL
        my $dmsgMod = $dmsg;
        if( $dmsg =~ m/^O02[A-F0-9]{8}/ ) {  #O02D28C0100
                my $dev = substr($dmsg, 3, 4);
                my $btn = substr($dmsg, 7, 2);
                my $cde = substr($dmsg, 9, 2);
          # Msg format:
        # 81 0b 04 f7 0101 a001 HHHH 01 00 11
                $dmsgMod = "810b04f70101a001" . lc($dev) . lc($btn) . "00" . lc($cde);
                #Log 1, "Modified F20 command: " . $dmsgMod;
        }

#Adapt JeeLink command (F019204356A) to LaCrosse module standard syntax "OK 9 32 1 4 91 62" ("^\\S+\\s+9 ")
        elsif( $dmsg =~ m/^F01[A-F0-9]{8}/ ) {
                #
                # Message Format:
                #
                # .- [0] -. .- [1] -. .- [2] -. .- [3] -. .- [4] -.
                # |       | |       | |       | |       | |       |
                # SSSS.DDDD DDN_.TTTT TTTT.TTTT WHHH.HHHH CCCC.CCCC
                # |  | |     ||  |  | |  | |  | ||      | |       |
                # |  | |     ||  |  | |  | |  | ||      | `--------- CRC
                # |  | |     ||  |  | |  | |  | |`-------- Humidity
                # |  | |     ||  |  | |  | |  | |
                # |  | |     ||  |  | |  | |  | `---- weak battery
                # |  | |     ||  |  | |  | |  |
                # |  | |     ||  |  | |  | `----- Temperature T * 0.1
                # |  | |     ||  |  | |  |
                # |  | |     ||  |  | `---------- Temperature T * 1
                # |  | |     ||  |  |
                # |  | |     ||  `--------------- Temperature T * 10
                # |  | |     | `--- new battery
                # |  | `---------- ID
                # `---- START
                #
                #

                my( $addr, $type, $channel, $temperature, $humidity, $batInserted ) = 0.0;

                $addr = sprintf( "%02X", ((hex(substr($dmsg,3,2)) & 0x0F) << 2) | ((hex(substr($dmsg,5,2)) & 0xC0) >> 6) );
                $type = ((hex(substr($dmsg,5,2)) & 0xF0) >> 4); # not needed by LaCrosse Module
                #$channel = 1; ## $channel = (hex(substr($dmsg,5,2)) & 0x0F);

                $temperature = ( ( ((hex(substr($dmsg,5,2)) & 0x0F) * 100) + (((hex(substr($dmsg,7,2)) & 0xF0) >> 4) * 10) + (hex(substr($dmsg,7,2)) & 0x0F) ) / 10) - 40;
                return if($temperature >= 60 || $temperature <= -40);

                $humidity = hex(substr($dmsg,9,2));
                $batInserted = ( (hex(substr($dmsg,5,2)) & 0x20) << 2 );

                #build string for 36_LaCrosse.pm
                $dmsgMod = "OK 9 $addr ";
                        #bogus check humidity + eval 2 channel TX25IT
                if (($humidity >= 0 && $humidity <= 99) || $humidity == 106 || ($humidity >= 128 && $humidity <= 227) || $humidity == 234) {
                        $dmsgMod .= (1 | $batInserted);
                } elsif ($humidity == 125 || $humidity == 253 ) {
                        $dmsgMod .= (2 | $batInserted);
                }

                $temperature = (($temperature* 10 + 1000) & 0xFFFF);
                $dmsgMod .= " " . (($temperature >> 8) & 0xFF)  . " " . ($temperature & 0xFF) . " $humidity";
        }

#  if( $rmsg =~ m/(\S* )(\d+)(.*)/ ) {
#    my $node = $2 & 0x1F;              #mask HDR -> it is handled by the skech
#    $dmsg = $1.$node.$3;
#  }

  Dispatch($hash, $dmsgMod, \%addvals);
}


#####################################
sub
JeeLink_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "JeeLink_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

########################
sub
JeeLink_SimpleWrite(@)
{
  my ($hash, $msg, $nocr) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "SW: $msg";

  $msg .= "\n" unless($nocr);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}
sub
JeeLink_ResetDevice($)
{
  my ($hash) = @_;

  DevIo_CloseDev($hash);
  my $ret = DevIo_OpenDev($hash, 0, "JeeLink_DoInit");

  return $ret;
}


sub
JeeLink_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  if( $aName eq "Clients" ) {
    $hash->{Clients} = $aVal;
    $hash->{Clients} = $clientsJeeLink if( !$hash->{Clients}) ;
  } elsif( $aName eq "MatchList" ) {
    my $match_list;
    if( $cmd eq "set" ) {
      $match_list = eval $aVal;
      if( $@ ) {
        Log3 $name, 2, $name .": $aVal: ". $@;
      }
    }

    if( ref($match_list) eq 'HASH' ) {
      $hash->{MatchList} = $match_list;
    } else {
      $hash->{MatchList} = \%matchListPCA301;
      Log3 $name, 2, $name .": $aVal: not a HASH" if( $aVal );
    }
  } elsif($aName =~ m/^tune/i) { #tune attribute freq / rx:bWidth / rx:rAmpl / rx:sens / tx:deviation / tx:power
  # Frequenze: Fc =860+ F x0.0050MHz
        # LNA Gain [dB] = MAX -6, -14, -20
        # RX Bandwidth [kHz] = -, 400, 340, 270, 200, 134, 67
        # DRSSI [dB] = -103, -97, -91, -85, -79, -73
        # Deviation [kHz] = 15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240
        # OuputPower [dBm] = 0, -3, -6, -9, -12, -15, -18, -21

        return "Usage: attr $name $aName <Frequence> <Rx:Bandwidth> <Rx:Amplitude> <Rx:Sens> <Tx:Deviation> <Tx:Power>"
                if(!$aVal || $aVal !~ m/^(4|8)[\d]{2}.[\d]{3} (0|400|340|270|200|134|67) (0|\-6|\-14|\-20) (\-103|\-97|\-91|\-85|\-79|\-73) (15|30|45|60|75|90|105|120|135|150|165|180|195|210|225|240) (0|\-3|\-6|\-9|\-12|\-15|\-18|\-21)/ );

        my $TuneStr = JeeLink_CalcTuneCmd($aVal);

    JeeLink_Write($hash, "t" . $TuneStr);

  } elsif ($aName eq "DebounceTime") {

                return "Usage: attr $name $aName <OOK-Protocol-Number><DebounceTime>"
                        if($aVal !~ m/^[0-9]{3,5}$/);

    #Log3 $name, 4, "set $name $cmd $arg";
    JeeLink_Write($hash, "Od" . $aVal);
  }

  return undef;
}

sub JeeLink_CalcTuneCmd($) {

        my ($str) = @_;

        my ($freq, $rxbwidth, $rxampl, $rxsens, $txdev, $txpower) = split(' ', $str ,6);

        my $sfreq;
        if($freq < 800) {
                $sfreq = sprintf("%03X", ($freq-430)/0.0025);
        } else {
                $sfreq = sprintf("%03X", ($freq-860)/0.0050);
        }

        my $sbwidth = sprintf("%01X", JeeLink_getIndexOfArray($rxbwidth,(0, 400, 340, 270, 200, 134, 67)));
        my $sampl = sprintf("%01X", JeeLink_getIndexOfArray($rxampl,(0, -6, -14, -20)));
        my $ssens = sprintf("%01X", JeeLink_getIndexOfArray($rxsens,    (-103, -97, -91, -85, -79, -73)));

        my $sdev = sprintf("%01X", JeeLink_getIndexOfArray($txdev,      (15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240)));
        my $soutpupower = sprintf("%01X", JeeLink_getIndexOfArray($txpower,     (0, -3, -6, -9, -12, -15, -18, -21)));

        return $sfreq . $sbwidth . $sampl . $ssens . $sdev . $soutpupower;
}

sub JeeLink_getIndexOfArray($@) {

        my ($value, @array) = @_;
        my ($ivalue) = grep { $array[$_] == $value } 0..$#array;
        return $ivalue;
}
1;

=pod
=begin html

<a name="JeeLink"></a>
<h3>JeeLink</h3>
<ul>
  The JeeLink is a family of RF devices sold by <a href="http://jeelabs.com">jeelabs.com</a>.

  It is possible to attach more than one device in order to get better
  reception, fhem will filter out duplicate messages.<br><br>

  This module provides the IODevice for:
  <ul>
  <li><a href="#PCA301">PCA301</a> modules that implement the PCA301 protocol.</li>
  <li><a href="#LaCrosse">LaCrosse</a> modules that implement the IT+ protocol (Sensors like TX29DTH, TX35, ...).</li>
  <li>LevelSender for measuring tank levels</li>
  <li>EMT7110 energy meter</li>
  <li>Other Sensors like WT440XH (their protocol gets transformed to IT+)</li>
  </ul>

  <br>
  Note: this module may require the Device::SerialPort or Win32::SerialPort module if you attach the device via USB
  and the OS sets strange default parameters for serial devices.

  <br><br>

  <a name="JeeLink_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; JeeLink &lt;device&gt;</code> <br>
    <br>
    USB-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the JeeLink.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the JeeLink by the
      following command:<ul>modprobe usbserial vendor=0x0403
      product=0x6001</ul>In this case the device is most probably
      /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@57600<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br>

    </ul>
    <br>
  </ul>

  <a name="JeeLink_Set"></a>
  <b>Set</b>
  <ul>
    <li>raw &lt;data&gt;<br>
        send &lt;data&gt; to the JeeLink. Depending on the sketch running on the JeeLink, different commands are available. Most of the sketches support the v command to get the version info and the ? command to get the list of available commands.
    </li><br>

    <li>reset<br>
        force a device reset closing and reopening the device.
    </li><br>

    <li>LaCrossePairForSec &lt;sec&gt; [ignore_battery]<br>
       enable autocreate of new LaCrosse sensors for &lt;sec&gt; seconds. If ignore_battery is not given only sensors
       sending the 'new battery' flag will be created.
    </li><br>

    <li>flash [hexFile]<br>
    The JeeLink needs the right firmware to be able to receive and deliver the sensor data to fhem. In addition to the way using the
    arduino IDE to flash the firmware into the JeeLink this provides a way to flash it directly from FHEM.

    There are some requirements:
    <ul>
      <li>avrdude must be installed on the host<br>
      On a Raspberry PI this can be done with: sudo apt-get install avrdude</li>
      <li>the flashCommand attribute must be set.<br>
        This attribute defines the command, that gets sent to avrdude to flash the JeeLink.<br>
        The default is: avrdude -p atmega328P -c arduino -P [PORT] -D -U flash:w:[HEXFILE] 2>[LOGFILE]<br>
        It contains some place-holders that automatically get filled with the according values:<br>
        <ul>
          <li>[PORT]<br>
            is the port the JeeLink is connectd to (e.g. /dev/ttyUSB0)</li>
          <li>[HEXFILE]<br>
            is the .hex file that shall get flashed. There are three options (applied in this order):<br>
            - passed in set flash<br>
            - taken from the hexFile attribute<br>
            - the default value defined in the module<br>
          </li>
          <li>[LOGFILE]<br>
            The logfile that collects information about the flash process. It gets displayed in FHEM after finishing the flash process</li>
        </ul>
      </li>
    </ul>

    </li><br>

    <li>led &lt;on|off&gt;<br>
    Is used to disable the blue activity LED
    </li><br>

    <li>beep<br>
    ...
    </li><br>

    <li>setReceiverMode<br>
    ...
    </li><br>

  </ul>

  <a name="JeeLink_Get"></a>
  <b>Get</b>
  <ul>
  </ul>
  <br>

  <a name="JeeLink_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>Clients<br>
      The received data gets distributed to a client (e.g. LaCrosse, EMT7110, ...) that handles the data.
      This attribute tells, which are the clients, that handle the data. If you add a new module to FHEM, that shall handle
      data distributed by the JeeLink module, you must add it to the Clients attribute.</li>

    <li>MatchList<br>
      can be set to a perl expression that returns a hash that is used as the MatchList<br>
      <code>attr myJeeLink MatchList {'5:AliRF' => '^\\S+\\s+5 '}</code></li>

    <li>initCommands<br>
      Space separated list of commands to send for device initialization.<br>
      This can be used e.g. to bring the LaCrosse Sketch into the data rate toggle mode. In this case initCommands would be: 30t
    </li>

    <li>flashCommand<br>
      See "Set flash"
    </li><br>


  </ul>
  <br>
</ul>

=end html
=cut

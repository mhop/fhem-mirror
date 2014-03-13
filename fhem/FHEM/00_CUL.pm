##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub CUL_Attr(@);
sub CUL_Clear($);
sub CUL_HandleCurRequest($$);
sub CUL_HandleWriteQueue($);
sub CUL_Parse($$$$$);
sub CUL_Read($);
sub CUL_ReadAnswer($$$$);
sub CUL_Ready($);
sub CUL_Write($$$);

sub CUL_SimpleWrite(@);

my %gets = (    # Name, Data to send to the CUL, Regexp for the answer
  "ccconf"   => 1,
  "file"     => 1,
  "version"  => ["V", '^V .*'],
  "raw"      => ["", '.*'],
  "uptime"   => ["t", '^[0-9A-F]{8}[\r\n]*$' ],
  "fhtbuf"   => ["T03", '^[0-9A-F]+[\r\n]*$' ],
  "cmds"     => ["?", '.*Use one of[ 0-9A-Za-z]+[\r\n]*$' ],
  "credit10ms" => [ "X", '^.. *\d*[\r\n]*$' ],
);

my %sets = (
  "hmPairForSec" => "HomeMatic",
  "hmPairSerial" => "HomeMatic",
  "raw"       => "",
  "freq"      => "SlowRF",
  "bWidth"    => "SlowRF",
  "rAmpl"     => "SlowRF",
  "sens"      => "SlowRF",
  "led"       => "",
  "patable"   => "",
  "file"      => "",
  "time"      => ""
);

my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42); # rAmpl(dB) 

my $clientsSlowRF = ":FS20:FHT.*:KS300:USF1000:BS:HMS: " .
                    ":CUL_EM:CUL_WS:CUL_FHTTK:CUL_RFR:CUL_HOERMANN: " .
                    ":ESA2000:CUL_IR:CUL_TX:Revolt:IT:";

my $clientsHomeMatic = ":CUL_HM:HMS:CUL_IR:";  # OneWire emulated as HMS on a CUNO

my $clientsMAX = ":CUL_MAX:HMS:CUL_IR";  # CUL_MAX is not available, yet

my %matchListSlowRF = (
    "1:USF1000"   => "^81..(04|0c)..0101a001a5ceaa00....",
    "2:BS"        => "^81..(04|0c)..0101a001a5cf",
    "3:FS20"      => "^81..(04|0c)..0101a001",
    "4:FHT"       => "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
    "5:KS300"     => "^810d04..4027a001",
    "6:CUL_WS"    => "^K.....",
    "7:CUL_EM"    => "^E0.................\$",
    "8:HMS"       => "^810e04....(1|5|9).a001",
    "9:CUL_FHTTK" => "^T[A-F0-9]{8}",
    "A:CUL_RFR"   => "^[0-9A-F]{4}U.",
    "B:CUL_HOERMANN"=> "^R..........",
    "C:ESA2000"   => "^S................................\$",
    "D:CUL_IR"    => "^I............",
    "E:CUL_TX"    => "^TX[A-F0-9]{10}",
    "F:Revolt"    => "^r......................\$",
    "G:IT"        => "^i......\$",
);
my %matchListHomeMatic = (
    "1:CUL_HM" => "^A....................",
    "8:HMS"       => "^810e04....(1|5|9).a001", # CUNO OneWire HMS Emulation
    "D:CUL_IR"    => "^I............",
);

my %matchListMAX = (
    "1:CUL_MAX" => "^Z........................",
    "8:HMS"       => "^810e04....(1|5|9).a001", # CUNO OneWire HMS Emulation
    "D:CUL_IR"    => "^I............",
);

sub
CUL_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "CUL_Read";
  $hash->{WriteFn} = "CUL_Write";
  $hash->{ReadyFn} = "CUL_Ready";

# Normal devices
  $hash->{DefFn}   = "CUL_Define";
  $hash->{FingerprintFn} = "CUL_FingerprintFn";
  $hash->{UndefFn} = "CUL_Undef";
  $hash->{GetFn}   = "CUL_Get";
  $hash->{SetFn}   = "CUL_Set";
  $hash->{AttrFn}  = "CUL_Attr";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "showtime:1,0 model:CUL,CUN,CUR " . 
                     "sendpool addvaltrigger rfmode:SlowRF,HomeMatic,MAX ".
                     "hmId ".
                     "hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger ";

  $hash->{ShutdownFn} = "CUL_Shutdown";

}

sub
CUL_FingerprintFn($$)
{
  my ($name, $msg) = @_;
 
  # Store only the "relevant" part, as the CUL won't compute the checksum
  $msg = substr($msg, 8) if($msg =~ m/^81/ && length($msg) > 8);
 
  return ($name, $msg);
}

#####################################
sub
CUL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4 || @a > 5) {
    my $msg = "wrong syntax: define <name> CUL {none | devicename[\@baudrate] ".
                        "| devicename\@directio | hostname:port} <FHTID>";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  return "FHTID must be H1H2, with H1 and H2 hex and both smaller than 64"
                if(uc($a[3]) !~ m/^[0-6][0-9A-F][0-6][0-9A-F]$/);

  if(uc($a[3]) =~ m/^([0-6][0-9A-F])/ && $1 ne "00") {
    my $x = $1;
    foreach my $d (keys %defs) {
      next if($d eq $name);
      if($defs{$d}{TYPE} eq "CUL") {
        if(uc($defs{$d}{FHTID}) =~ m/^$x/) {
          my $m = "$name: Cannot define multiple CULs with identical ".
                        "first two digits ($x)";
          Log3 $name, 1, $m;
          return $m;
        }
      }
    }
  }
  $hash->{FHTID} = uc($a[3]);
  $hash->{initString} = "X21";
  $hash->{CMDS} = "";
  $hash->{Clients} = $clientsSlowRF;
  $hash->{MatchList} = \%matchListSlowRF;

  if($dev eq "none") {
    Log3 $name, 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "CUL_DoInit");
  return $ret;
}

#####################################
sub
CUL_Undef($$)
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

  CUL_SimpleWrite($hash, "X00"); # Switch reception off, it may hang up the CUL
  DevIo_CloseDev($hash); 
  return undef;
}

#####################################
sub
CUL_Shutdown($)
{
  my ($hash) = @_;
  CUL_SimpleWrite($hash, "X00") if(!CUL_isCUR($hash));
  return undef;
}

sub
CUL_isCUR($)
{
  my ($hash) = @_;
  return ($hash->{VERSION} && $hash->{VERSION} =~ m/CUR/);
}

sub
CUL_RemoveHMPair($)
{
  my $hash = shift;
  delete($hash->{hmPair});
}

#####################################
sub
CUL_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set CUL\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);

  return "This command is not valid in the current rfmode"
      if($sets{$type} && $sets{$type} ne AttrVal($name, "rfmode", "SlowRF"));

  if($type eq "hmPairForSec") { ####################################
    return "Usage: set $name hmPairForSec <seconds_active>"
        if(!$arg || $arg !~ m/^\d+$/);
    $hash->{hmPair} = 1;
    InternalTimer(gettimeofday()+$arg, "CUL_RemoveHMPair", $hash, 1);

  } elsif($type eq "hmPairSerial") { ################################
    return "Usage: set $name hmPairSerial <10-character-serialnumber>"
        if(!$arg || $arg !~ m/^.{10}$/);

    my $id = AttrVal($hash->{NAME}, "hmId", "F1".$hash->{FHTID});
    $hash->{HM_CMDNR} = $hash->{HM_CMDNR} ? ($hash->{HM_CMDNR}+1)%256 : 1;
    CUL_SimpleWrite($hash, sprintf("As15%02x8401%s000000010A%s",
                    $hash->{HM_CMDNR}, $id, unpack('H*', $arg)));
    $hash->{hmPairSerial} = $arg;

  } elsif($type eq "freq") { ######################################## MHz

    my $f = $arg/26*65536;

    my $f2 = sprintf("%02x", $f / 65536);
    my $f1 = sprintf("%02x", int($f % 65536) / 256);
    my $f0 = sprintf("%02x", $f % 256);
    $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
    Log3 $name, 3, "Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
    CUL_SimpleWrite($hash, "W0F$f2");
    CUL_SimpleWrite($hash, "W10$f1");
    CUL_SimpleWrite($hash, "W11$f0");
    CUL_SimpleWrite($hash, $hash->{initString});   # Will reprogram the CC1101

  } elsif($type eq "bWidth") { ###################################### KHz

    my ($err, $ob);
    if(!IsDummy($hash->{NAME})) {
      CUL_SimpleWrite($hash, "C10");
      ($err, $ob) = CUL_ReadAnswer($hash, $type, 0, "^C10 = .*");
      return "Can't get old MDMCFG4 value" if($err || $ob !~ m,/ (.*)\r,);
      $ob = $1 & 0x0f;
    }

    my ($bits, $bw) = (0,0);
    for (my $e = 0; $e < 4; $e++) {
      for (my $m = 0; $m < 4; $m++) {
        $bits = ($e<<6)+($m<<4);
        $bw  = int(26000/(8 * (4+$m) * (1 << $e))); # KHz
        goto GOTBW if($arg >= $bw);
      }
    }

GOTBW:
    $ob = sprintf("%02x", $ob+$bits);
    Log3 $name, 3, "Setting MDMCFG4 (10) to $ob = $bw KHz";
    CUL_SimpleWrite($hash, "W12$ob");
    CUL_SimpleWrite($hash, $hash->{initString});

  } elsif($type eq "rAmpl") { ####################################### dB

    return "a numerical value between 24 and 42 is expected"
        if($arg !~ m/^\d+$/ || $arg < 24 || $arg > 42);
    my ($v, $w);
    for($v = 0; $v < @ampllist; $v++) {
      last if($ampllist[$v] > $arg);
    }
    $v = sprintf("%02d", $v-1);
    $w = $ampllist[$v];
    Log3 $name, 3, "Setting AGCCTRL2 (1B) to $v / $w dB";
    CUL_SimpleWrite($hash, "W1D$v");
    CUL_SimpleWrite($hash, $hash->{initString});

  } elsif($type eq "sens") { ######################################## dB

    return "a numerical value between 4 and 16 is expected"
        if($arg !~ m/^\d+$/ || $arg < 4 || $arg > 16);
    my $w = int($arg/4)*4;
    my $v = sprintf("9%d",$arg/4-1);
    Log3 $name, 3, "Setting AGCCTRL0 (1D) to $v / $w dB";
    CUL_SimpleWrite($hash, "W1F$v");
    CUL_SimpleWrite($hash, $hash->{initString});

  } elsif($type eq "file") { ########################################

    return "Only supported for CUR devices (see VERSION)" if(!CUL_isCUR($hash));

    return "$name: Need 2 further arguments: source destination"
                                if(@a != 2);
    my ($buf, $msg, $err);
    return "$a[0]: $!" if(!open(FH, $a[0]));
    $buf = join("", <FH>);
    close(FH);

    my $len = length($buf);
    CUL_Clear($hash);
    CUL_SimpleWrite($hash, "X00");

    CUL_SimpleWrite($hash, sprintf("w%08X$a[1]", $len));
    ($err, $msg) = CUL_ReadAnswer($hash, $type, 1, undef);
    goto WRITEEND if($err);
    if($msg ne sprintf("%08X\r\n", $len)) {
      $err = "Bogus length received: $msg";
      goto WRITEEND;
    }

    my $off = 0;
    while($off < $len) {
      my $mlen = ($len-$off) > 32 ? 32 : ($len-$off);
      CUL_SimpleWrite($hash, substr($buf,$off,$mlen), 1);
      $off += $mlen;
    }

WRITEEND:
    CUL_SimpleWrite($hash, $hash->{initString});
    return "$name: $err" if($err);

  } elsif($type eq "time") { ########################################

    return "Only supported for CUR devices (see VERSION)" if(!CUL_isCUR($hash));
    my @a = localtime;
    my $msg = sprintf("c%02d%02d%02d", $a[2],$a[1],$a[0]);
    CUL_SimpleWrite($hash, $msg);

  } else { ###############################################  raw,led,patable

    return "Expecting a 0-padded hex number"
        if((length($arg)&1) == 1 && $type ne "raw");
    Log3 $name, 3, "set $name $type $arg";
    $arg = "l$arg" if($type eq "led");
    $arg = "x$arg" if($type eq "patable");
    CUL_SimpleWrite($hash, $arg);

  }
  return undef;
}

#####################################
sub
CUL_Get($@)
{
  my ($hash, @a) = @_;
  my $type = $hash->{TYPE};

  return "\"get $type\" needs at least one parameter" if(@a < 2);
  if(!defined($gets{$a[1]})) {
    my @cList = map { $_ =~ m/^(file|raw)$/ ? $_ : "$_:noArg" } sort keys %gets;
    return "Unknown argument $a[1], choose one of " . join(" ", @cList);
  }

  my $arg = ($a[2] ? $a[2] : "");
  my ($msg, $err);
  my $name = $a[0];

  return "No $a[1] for dummies" if(IsDummy($name));

  if($a[1] eq "ccconf") {

    my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"1B"=>1,"1D"=>1 );
    foreach my $a (sort keys %r) {
      CUL_SimpleWrite($hash, "C$a");
      ($err, $msg) = CUL_ReadAnswer($hash, "C$a", 0, "^C.* = .*");
      return $err if($err);
      my @answ = split(" ", $msg);
      $r{$a} = $answ[4];
    }
    $msg = sprintf("freq:%.3fMHz bWidth:%dKHz rAmpl:%ddB sens:%ddB",
        26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
        26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
        $ampllist[$r{"1B"}&7],
        4+4*($r{"1D"}&3)                                                #Sens
        );
    
  } elsif($a[1] eq "file") {

    return "Only supported for CUR devices (see VERSION)" if(!CUL_isCUR($hash));

    CUL_Clear($hash);
    CUL_SimpleWrite($hash, "X00");

    if(int(@a) == 2) {  # No argument: List directory

      CUL_SimpleWrite($hash, "r.");
      ($err, $msg) = CUL_ReadAnswer($hash, $a[1], 0, undef);
      goto READEND if($err);

      $msg =~ s/[\r\n]//g;
      my @a;
      foreach my $f (split(" ", $msg)) {
        my ($name, $size) = split("/", $f);
        push @a, sprintf("%-14s %5d", $name, hex($size));
      }
      $msg = join("\n", @a);

    } else {            # Read specific file

      if(@a != 4) {
        $err = "Need 2 further arguments: source [destination|-]";
        goto READEND;
      }

      CUL_SimpleWrite($hash, "r$a[2]");
      ($err, $msg) = CUL_ReadAnswer($hash, $a[1], 0, undef);
      goto READEND if($err);

      if($msg eq "X") {
        $err = "$a[2]: file not found on CUL";
        goto READEND if($err);
      }
      $msg =~ s/[\r\n]//g;
      my ($len,  $buf) = (hex($msg), "");
      $msg = "";
      while(length($msg) != $len) {
        ($err, $buf) = CUL_ReadAnswer($hash, $a[1], 1, undef);
        goto READEND if($err);
        $msg .= $buf;
      }

      if($a[3] ne "-") {
        if(!open(FH, ">$a[3]")) {
          $err = "$a[3]: $!";
          goto READEND;
        }
        print FH $msg;
        close(FH);
        $msg = "";
      }

    }

READEND:
    CUL_SimpleWrite($hash, $hash->{initString});
    return "$name: $err" if($err);
    return $msg;

  } else {

    CUL_SimpleWrite($hash, $gets{$a[1]}[0] . $arg);
    ($err, $msg) = CUL_ReadAnswer($hash, $a[1], 0, $gets{$a[1]}[1]);
    if(!defined($msg)) {
      DevIo_Disconnected($hash);
      $msg = "No answer";

    } elsif($a[1] eq "cmds") {       # nice it up
      $msg =~ s/.*Use one of//g;

    } elsif($a[1] eq "uptime") {     # decode it
      $msg =~ s/[\r\n]//g;
      $msg = hex($msg)/125;
      $msg = sprintf("%d %02d:%02d:%02d",
        $msg/86400, ($msg%86400)/3600, ($msg%3600)/60, $msg%60);
    } elsif($a[1] eq "credit10ms") {
      ($msg) = ($msg =~ /^.. *(\d*)[\r\n]*$/);
    }

    $msg =~ s/[\r\n]//g;

  }

  $hash->{READINGS}{$a[1]}{VAL} = $msg;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $msg";
}

sub
CUL_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    my ($err, undef) = CUL_ReadAnswer($hash, "Clear", 0, undef);
    last if($err && $err =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});
}

#####################################
sub
CUL_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  CUL_Clear($hash);
  my ($ver, $try) = ("", 0);
  while($try++ < 3 && $ver !~ m/^V/) {
    CUL_SimpleWrite($hash, "V");
    ($err, $ver) = CUL_ReadAnswer($hash, "Version", 0, undef);
    return "$name: $err" if($err && ($err !~ m/Timeout/ || $try == 3));
    $ver = "" if(!$ver);
  }

  if($ver !~ m/^V/) {
    $attr{$name}{dummy} = 1;
    $msg = "Not an CUL device, got for V:  $ver";
    Log3 $name, 1, $msg;
    return $msg;
  }
  $ver =~ s/[\r\n]//g;
  $hash->{VERSION} = $ver;

  if($ver =~ m/CUR/) {
    my @a = localtime;
    my $msg = sprintf("c%02d%02d%02d%02d%02d%02d",
                ($a[5]+1900)%100,$a[4]+1,$a[3],$a[2],$a[1],$a[0]);
    CUL_SimpleWrite($hash, $msg);
  }

  # Cmd-String feststellen

  my $cmds = CUL_Get($hash, $name, "cmds", 0);
  $cmds =~ s/$name cmds =>//g;
  $cmds =~ s/ //g;
  $hash->{CMDS} = $cmds;
  Log3 $name, 3, "$name: Possible commands: " . $hash->{CMDS};

  CUL_SimpleWrite($hash, $hash->{initString});

  # FHTID
  my $fhtid;
  CUL_SimpleWrite($hash, "T01");
  ($err, $fhtid) = CUL_ReadAnswer($hash, "FHTID", 0, undef);
  return "$name: $err" if($err);
  $fhtid =~ s/[\r\n]//g;
  Log3 $name, 5, "GOT CUL fhtid: $fhtid";
  if(!defined($fhtid) || $fhtid ne $hash->{FHTID}) {
    Log3 $name, 2, "Setting CUL fhtid from $fhtid to " . $hash->{FHTID};
    CUL_SimpleWrite($hash, "T01" . $hash->{FHTID});
  }

  $hash->{STATE} =
  $hash->{READINGS}{state}{VAL} = "Initialized";
  $hash->{READINGS}{state}{TIME} = TimeNow();

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
  return undef;
}

#####################################
# This is a direct read for commands like get
# Anydata is used by read file to get the filesize
sub
CUL_ReadAnswer($$$$)
{
  my ($hash, $arg, $anydata, $regexp) = @_;
  my $type = $hash->{TYPE};

  while($hash->{TYPE} eq "CUL_RFR") {   # Look for the first "real" CUL
    $hash = $hash->{IODev};
  }

  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($mculdata, $rin) = ("", '');
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
        return("CUL_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if($buf) {
      Log3 $hash->{NAME}, 5, "CUL/RAW (ReadAnswer): $buf";
      $mculdata .= $buf;
    }
    $mculdata = CUL_RFR_DelPrefix($mculdata) if($type eq "CUL_RFR");

    # \n\n is socat special
    if($mculdata =~ m/\r\n/ || $anydata || $mculdata =~ m/\n\n/ ) {
      if($regexp && $mculdata !~ m/$regexp/) {
        CUL_Parse($hash, $hash, $hash->{NAME}, $mculdata, $hash->{initString});
      } else {
        return (undef, $mculdata)
      }
    }
  }

}

#####################################
# Check if the 1% limit is reached and trigger notifies
sub
CUL_XmitLimitCheck($$$)
{
  my ($hash,$fn,$now) = @_;

  if(!$hash->{XMIT_TIME}) {
    $hash->{XMIT_TIME}[0] = $now;
    $hash->{NR_CMD_LAST_H} = 1;
    return;
  }

  my $nowM1h = $now-3600;
  my @b = grep { $_ > $nowM1h } @{$hash->{XMIT_TIME}};

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $name = $hash->{NAME};
    Log3 $name, 2, "CUL TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

sub
CUL_XmitDlyHM($$$)
{
  my ($hash,$fn,$now) = @_;
  
  my (undef,$mTy,undef,$id) = unpack 'A8A2A6A6',$fn if(length($fn)>19);

  if($id &&
     $modules{CUL_HM}{defptr}{$id} && 
     $modules{CUL_HM}{defptr}{$id}{helper}{io} && 
     $modules{CUL_HM}{defptr}{$id}{helper}{io}{nextSend}) {
    my $dDly = $modules{CUL_HM}{defptr}{$id}{helper}{io}{nextSend} - $now;
    #$dDly -= 0.04 if ($mTy eq "02");# while HM devices need a rest there are 
                                     # still some devices that need faster 
                                     # reactionfor ack. 
                                     # Mode needs to be determined
    if ($dDly > 0.01){# wait less then 10 ms will not work
      $dDly = 0.1 if($dDly > 0.1);
      Log3 $hash->{NAME}, 5, "CUL $id dly:".int($dDly*1000)."ms";
      select(undef, undef, undef, $dDly);
    }
  }
  shift(@{$hash->{helper}{$id}{QUEUE}});
  InternalTimer($now+0.1, "CUL_XmitDlyHMTo", "$hash->{NAME}:$id", 1) 
        if (scalar(@{$hash->{helper}{$id}{QUEUE}}));
  return 0;
}

sub
CUL_XmitDlyHMTo($)
{ # waited long enough - next send for this ID
  my ($name,$id) = split(":",$_[0]);
  CUL_SendFromQueue($defs{$name}, ${$defs{$name}{helper}{$id}{QUEUE}}[0]);
}

#####################################
# Translate data prepared for an FHZ to CUL syntax, so we can reuse
# the FS20 and FHZ modules.
sub
CUL_WriteTranslate($$$)
{
  my ($hash,$fn,$msg) = @_;

  my $name = $hash->{NAME};

  ###################
  # Rewrite message from FHZ -> CUL
  if(length($fn) <= 1) {                                   # CUL Native
    ;

  } elsif($fn eq "04" && substr($msg,0,6) eq "010101") {   # FS20
    $fn = "F";
    AddDuplicate($hash->{NAME},
                "0101a001" . substr($msg, 6, 6) . "00" . substr($msg, 12));
    $msg = substr($msg,6);

  } elsif($fn eq "04" && substr($msg,0,6) eq "020183") {   # FHT
    $fn = "T";
    $msg = substr($msg,6,4) . substr($msg,10);

  } else {
    Log3 $name, 2, "CUL cannot translate $fn $msg";
    return (undef, undef);
  }
  return ($fn, $msg);
}

#####################################
sub
CUL_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  ($fn, $msg) = CUL_WriteTranslate($hash, $fn, $msg);
  return if(!defined($fn));
  my $name = $hash->{NAME};
  Log3 $name, 5, "$hash->{NAME} sending $fn$msg";
  my $bstring = "$fn$msg";

  if($fn eq "F" ||                      # FS20 message
     $bstring =~ m/^u....F/ ||          # FS20 messages sent over an RFR
     ($fn eq "" && ($bstring =~ m/^A/ || $bstring =~ m/^Z/ ))) { # AskSin/BidCos/HomeMatic/MAX

    CUL_AddSendQueue($hash, $bstring);

  } else {

    CUL_SimpleWrite($hash, $bstring);

  }

}

sub
CUL_SendFromQueue($$)
{
  my ($hash, $bstring) = @_;
  my $name = $hash->{NAME};
  my $hm = ($bstring =~ m/^A/);
  my $mz = ($bstring =~ m/^Z/);
  my $to = ($hm ? 0.15 : 0.3);
  my $now = gettimeofday();
  if($bstring ne "") {
    my $sp = AttrVal($name, "sendpool", undef);
    if($sp) {   # Is one of the CUL-fellows sending data?
      my @fellows = split(",", $sp);
      foreach my $f (@fellows) {
        if($f ne $name &&
           $defs{$f} &&
           $defs{$f}{QUEUE} &&
           $defs{$f}{QUEUE}->[0] ne ""){
          unshift(@{$hash->{QUEUE}}, "");
          InternalTimer($now+$to, "CUL_HandleWriteQueue", $hash, 1);
          return;
        }
      }
    }

    if($hm) {
      CUL_SimpleWrite($hash, $bstring) if(!CUL_XmitDlyHM($hash,$bstring,$now));
      return;
    } else {
      CUL_XmitLimitCheck($hash, $bstring, $now);
      CUL_SimpleWrite($hash, $bstring);
    }
  }

  ##############
  # Write the next buffer not earlier than 0.23 seconds
  # = 3* (12*0.8+1.2+1.0*5*9+0.8+10) = 226.8ms
  # else it will be sent too early by the CUL, resulting in a collision
  InternalTimer($now+$to, "CUL_HandleWriteQueue", $hash, 1);
}

sub
CUL_AddSendQueue($$)
{
  my ($hash, $bstring) = @_;
  my $qHash = $hash;
  if ($bstring =~ m/^A/){ # HM device
    my $id = substr($bstring,16,6);#get HMID destination
    $qHash = $hash->{helper}{$id};
  }
  if(!$qHash->{QUEUE} || 0 == scalar(@{$qHash->{QUEUE}})) {
    $qHash->{QUEUE} = [ $bstring ];
    CUL_SendFromQueue($hash, $bstring);
  } else {
    push(@{$qHash->{QUEUE}}, $bstring);
  }
}

#####################################
sub
CUL_HandleWriteQueue($)
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
      CUL_HandleWriteQueue($hash);
    } else {
      CUL_SendFromQueue($hash, $bstring);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
CUL_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};

  my $culdata = $hash->{PARTIAL};
  Log3 $name, 5, "CUL/RAW: $culdata/$buf"; 
  $culdata .= $buf;

  while($culdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$culdata) = split("\n", $culdata, 2);
    $rmsg =~ s/\r//;
    CUL_Parse($hash, $hash, $name, $rmsg, $hash->{initString}) if($rmsg);
  }
  $hash->{PARTIAL} = $culdata;
}

sub
CUL_Parse($$$$$)
{
  my ($hash, $iohash, $name, $rmsg, $initstr) = @_;
  my $rssi;
  my $dmsg = $rmsg;
  my $dmsgLog = (AttrVal($name,"rfmode","") eq "HomeMatic")
                   ? join(" ",(unpack'A1A2A2A4A6A6A*',$rmsg))
                   :$dmsg;
  
  if($dmsg =~ m/^[AFTKEHRStZri]([A-F0-9][A-F0-9])+$/) { # RSSI
    my $l = length($dmsg);
    $rssi = hex(substr($dmsg, $l-2, 2));
    $dmsg = substr($dmsg, 0, $l-2);
    $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
    Log3 $name, 4, "CUL_Parse: $name $dmsgLog $rssi";
  } else {
    Log3 $name, 4, "CUL_Parse: $name $dmsgLog";
  }

  ###########################################
  #Translate Message from CUL to FHZ
  next if(!$dmsg || length($dmsg) < 1);            # Bogus messages

  if($dmsg =~ m/^[0-9A-F]{4}U./) {                 # RF_ROUTER
    Dispatch($hash, $dmsg, undef);
    return;
  }

  my $fn = substr($dmsg,0,1);
  my $len = length($dmsg);

  if($fn eq "F" && $len >= 9) {                    # Reformat for 10_FS20.pm
    CUL_AddSendQueue($iohash, "");                 # Delay immediate replies
    $dmsg = sprintf("81%02x04xx0101a001%s00%s",
                      $len/2+7, substr($dmsg,1,6), substr($dmsg,7));
    $dmsg = lc($dmsg);

  } elsif($fn eq "T") {
    if ($len >= 11) {                              # Reformat for 11_FHT.pm
      $dmsg = sprintf("81%02x04xx0909a001%s00%s",
                       $len/2+7, substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } else {
      ;                                            # => 09_CUL_FHTTK.pm

    }

  } elsif($fn eq "H" && $len >= 13) {              # Reformat for 12_HMS.pm
    my $type = hex(substr($dmsg,6,1));
    my $stat = $type > 1 ? hex(substr($dmsg,7,2)) : hex(substr($dmsg,5,2));
    my $prf  = $type > 1 ? "02" : "05";
    my $bat  = $type > 1 ? hex(substr($dmsg,5,1))+1 : 1;
    my $HA = substr($dmsg,1,4);
    my $values = $type > 1 ?  "000000" : substr($dmsg,7);
    $dmsg = sprintf("81%02x04xx%s%x%xa001%s0000%02x%s",
                      $len/2+8,            # Packet-Length
                      $prf, $bat, $type,
                      $HA,                 # House-Code
                      $stat,
                      $values);            # Values
    $dmsg = lc($dmsg);

  } elsif($fn eq "K" && $len >= 5) {
    if($len == 15) {                               # Reformat for 13_KS300.pm
      my @a = split("", $dmsg);
      $dmsg = sprintf("81%02x04xx4027a001", $len/2+6);
      for(my $i = 1; $i < 14; $i+=2) { # Swap nibbles.
        $dmsg .= $a[$i+1] . $a[$i];
      }
      $dmsg = lc($dmsg);
    }
    # Other K... Messages ar sent to CUL_WS
  } elsif($fn eq "r" && $len >= 23) {              # Revolt
    $dmsg = lc($dmsg);
  } elsif($fn eq "i" && $len >= 7) {              # IT
    $dmsg = lc($dmsg);
  } elsif($fn eq "S" && $len >= 33) {              # CUL_ESA / ESA2000 / Native
    ;
  } elsif($fn eq "E" && $len >= 11) {              # CUL_EM / Native
    ;
  } elsif($fn eq "R" && $len >= 11) {              # CUL_HOERMANN / Native
    ;
  } elsif($fn eq "I" && $len >= 12) {              # IR-CUL/CUN/CUNO
    ;
  } elsif($fn eq "A" && $len >= 20) {              # AskSin/BidCos/HomeMatic
    my $src = substr($dmsg,9,6);
    if($modules{CUL_HM}{defptr}{$src}){
      $modules{CUL_HM}{defptr}{$src}{helper}{io}{nextSend} = 
          gettimeofday() + 0.100;
    }
    $dmsg .= "::$rssi:$name" if(defined($rssi));

  } elsif($fn eq "Z" && $len >= 21) {              # Moritz/Max
    ;
  } elsif($fn eq "t" && $len >= 5)  {              # TX3
    $dmsg = "TX".substr($dmsg,1);                  # t.* is occupied by FHTTK
  } else {
    DoTrigger($name, "UNKNOWNCODE $dmsg");
    Log3 $name, 2, "$name: unknown message $dmsg";
    return;
  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} =
  $hash->{READINGS}{state}{TIME} = TimeNow();      # showtime attribute
  $hash->{RAWMSG} = $rmsg;
  my %addvals = (RAWMSG => $dmsg);
  if(defined($rssi)) {
    $hash->{RSSI} = $rssi;
    $addvals{RSSI} = $rssi;
  }
  Dispatch($hash, $dmsg, \%addvals);
}


#####################################
sub
CUL_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "CUL_DoInit")
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
CUL_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  return if(!$hash);
  if($hash->{TYPE} eq "CUL_RFR") {
    # Prefix $msg with RRBBU and return the corresponding CUL hash.
    ($hash, $msg) = CUL_RFR_AddPrefix($hash, $msg); 
  }

  my $name = $hash->{NAME};
  if (AttrVal($name,"rfmode","") eq "HomeMatic"){
    Log3 $name, 4, "CUL_send:  $name".join(" ",unpack('A2A2A2A4A6A6A*',$msg));
  }
  else{
    Log3 $name, 5, "SW: $msg";
  }

  $msg .= "\n" unless($nonl);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

sub
CUL_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  if($aName eq "rfmode") {

    my $hash = $defs{$name};

    $aVal = "SlowRF" if(!$aVal || ($aVal ne "HomeMatic" && $aVal ne "MAX"));
    my $msg = $hash->{NAME} . ": Mode $aVal not supported";

    if($aVal eq "HomeMatic") {
      return if($hash->{initString} =~ m/Ar/);
      if($hash->{CMDS} =~ m/A/ || IsDummy($hash->{NAME}) || !$hash->{FD}) {
        $hash->{Clients} = $clientsHomeMatic;
        $hash->{MatchList} = \%matchListHomeMatic;
        CUL_SimpleWrite($hash, "Zx") if ($hash->{CMDS} =~ m/Z/); # reset Moritz
        $hash->{initString} = "X21\nAr";  # X21 is needed for RSSI reporting
        CUL_SimpleWrite($hash, $hash->{initString});
      } else {
        Log3 $name, 2, $msg;
        return $msg;
      }

    } elsif($aVal eq "MAX") {
      return if($hash->{initString} =~ m/Zr/);
      if($hash->{CMDS} =~ m/Z/ || IsDummy($hash->{NAME}) || !$hash->{FD}) {
        $hash->{Clients} = $clientsMAX;
        $hash->{MatchList} = \%matchListMAX;
        CUL_SimpleWrite($hash, "Ax") if ($hash->{CMDS} =~ m/A/); # reset AskSin
        $hash->{initString} = "X21\nZr";  # X21 is needed for RSSI reporting
        CUL_SimpleWrite($hash, $hash->{initString});
      } else {
        Log3 $name, 2, $msg;
        return $msg;
      }

    } else {
      return if($hash->{initString} eq "X21");
      $hash->{Clients} = $clientsSlowRF;
      $hash->{MatchList} = \%matchListSlowRF;
      $hash->{initString} = "X21";
      CUL_SimpleWrite($hash, "Ax") if ($hash->{CMDS} =~ m/A/); # reset AskSin
      CUL_SimpleWrite($hash, "Zx") if ($hash->{CMDS} =~ m/Z/); # reset Moritz
      CUL_SimpleWrite($hash, $hash->{initString});
    }

    Log3 $name, 2, "Switched $name rfmode to $aVal";
    delete $hash->{".clientArray"};
  } elsif($aName eq "hmId"){
    if ($cmd eq "set"){
	  return "wrong syntax: hmId must be 6-digit-hex-code (3 byte)" 
	       if ($aVal !~ m/^[A-F0-9]{6}$/i);
	}    
  }
 
  return undef;
}

1;

=pod
=begin html

<a name="CUL"></a>
<h3>CUL</h3>
<ul>

  <table>
  <tr><td>
  The CUL/CUR/CUN(O) is a family of RF devices sold by <a
  href="http://www.busware.de">busware.de</a>.

  With the opensource firmware 
  <a href="http://culfw.de/culfw.html">culfw</a> they are capable
  to receive and send different 433/868 MHz protocols (FS20/FHT/S300/EM/HMS/MAX!).
  It is even possible to use these devices as range extenders/routers, see the
  <a href="#CUL_RFR">CUL_RFR</a> module for details.
  <br> <br>

  Some protocols (FS20, FHT and KS300) are converted by this module so that
  the same logical device can be used, irrespective if the radio telegram is
  received by a CUL or an FHZ device.<br>
  Other protocols (S300/EM) need their
  own modules. E.g. S300 devices are processed by the CUL_WS module if the
  signals are received by the CUL, similarly EMWZ/EMGZ/EMEM is handled by the
  CUL_EM module.<br><br>

  It is possible to attach more than one device in order to get better
  reception, FHEM will filter out duplicate messages.<br><br>

  Note: This module may require the <code>Device::SerialPort</code> or 
  <code>Win32::SerialPort</code> module if you attach the device via USB 
  and the OS sets strange default parameters for serial devices.<br><br>

  </td><td>
  <img src="ccc.jpg"/>
  </td></tr>
  </table>

  <a name="CULdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL &lt;device&gt; &lt;FHTID&gt;</code> <br>
    <br>
    USB-connected devices (CUL/CUR/CUN):<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the CUL.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the CUL by the
      following command:
      <ul><code>
        modprobe usbserial vendor=0x03eb product=0x204b
      </code></ul>
      In this case the device is most probably /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@38400<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module <code>Device::SerialPort</code> is not needed, and FHEM 
      opens the device with simple file io. This might work if the operating 
      system uses sane defaults for the serial parameters, e.g. some Linux 
      distributions and OSX.<br><br>

    </ul>
    Network-connected devices (CUN(O)):<br><ul>
    &lt;device&gt; specifies the host:port of the device, e.g.
    192.168.0.244:2323
    </ul>
    <br>
    If the device is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>

    The FHTID is a 4 digit hex number, and it is used when the CUL talks to
    FHT devices or when CUL requests data. Set it to 0000 to avoid answering
    any FHT80b request by the CUL.
  </ul>
  <br>

  <a name="CULset"></a>
  <b>Set </b>
  <ul>
    <li>raw<br>
        Issue a CUL firmware command.  See the <a
        href="http://culfw.de/commandref.html">this</a> document
        for details on CUL commands.
        </li><br>

    <li>freq / bWidth / rAmpl / sens<br>
        <a href="#rfmode">SlowRF</a> mode only.<br>
        Set the CUL frequency / bandwidth / receiver-amplitude / sensitivity<br>

        Use it with care, it may destroy your hardware and it even may be
        illegal to do so. Note: The parameters used for RFR transmission are
        not affected.<br>
        <ul>
        <li>freq sets both the reception and transmission frequency. Note:
            Although the CC1101 can be set to frequencies between 315 and 915
            MHz, the antenna interface and the antenna of the CUL is tuned for
            exactly one frequency. Default is 868.3 MHz (or 433 MHz)</li>
        <li>bWidth can be set to values between 58 kHz and 812 kHz. Large values
            are susceptible to interference, but make possible to receive
            inaccurately calibrated transmitters. It affects tranmission too.
            Default is 325 kHz.</li>
        <li>rAmpl is receiver amplification, with values between 24 and 42 dB.
            Bigger values allow reception of weak signals. Default is 42.
            </li>
        <li>sens is the decision boundary between the on and off values, and it
            is 4, 8, 12 or 16 dB.  Smaller values allow reception of less clear
            signals. Default is 4 dB.</li>
        </ul>
        </li><br>
    <a name="hmPairForSec"></a>
    <li>hmPairForSec<br>
       <a href="#rfmode">HomeMatic</a> mode only.<br>
       Set the CUL in Pairing-Mode for the given seconds. Any HM device set into
       pairing mode in this time will be paired with FHEM.
       </li><br>
    <a name="hmPairSerial"></a>
    <li>hmPairSerial<br>
       <a href="#rfmode">HomeMatic</a> mode only.<br>
       Try to pair with the given device. The argument is a 10 character
       string, usually starting with letters and ending with digits, printed on
       the backside of the device. It is not necessary to put the given device
       in learning mode if it is a receiver.
       </li><br>
    <a name="hmPairForSec"></a>
    <li>led<br>
        Set the CUL led off (00), on (01) or blinking (02).
        </li><br>
  </ul>

  <a name="CULget"></a>
  <b>Get</b>
  <ul>
    <li>version<br>
        returns the CUL firmware version
        </li><br>
    <li>uptime<br>
        returns the CUL uptime (time since CUL reset)
        </li><br>
    <li>raw<br>
        Issues a CUL firmware command, and waits for one line of data returned by
        the CUL. See the CUL firmware README document for details on CUL
        commands.
        </li><br>
    <li>fhtbuf<br>
        CUL has a message buffer for the FHT. If the buffer is full, then newly
        issued commands will be dropped, and an "EOB" message is issued to the
        FHEM log.
        <code>fhtbuf</code> returns the free memory in this buffer (in hex),
        an empty buffer in the CUL V2 is 74 bytes, in CUL V3/CUN(O) 200 Bytes.
        A message occupies 3 + 2x(number of FHT commands) bytes,
        this is the second reason why sending multiple FHT commands with one
        <a href="#set">set</a> is a good idea. The first reason is, that
        these FHT commands are sent at once to the FHT.
        </li> <br>

    <li>ccconf<br>
        Read some CUL radio-chip (cc1101) registers (frequency, bandwidth, etc.),
        and display them in human readable form.
        </li><br>

    <li>cmds<br>
        Depending on the firmware installed, CULs have a different set of
        possible commands. Please refer to the README of the firmware of your
        CUL to interpret the response of this command. See also the raw command.
        </li><br>
    <li>credit10ms<br>
        One may send for a duration of credit10ms*10 ms before the send limit
        is reached and a LOVF is generated.
        </li><br>
  </ul>

  <a name="CULattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a> (CUL,CUN,CUR)</li>
    <li><a name="sendpool">sendpool</a><br>
        If using more than one CUL for covering a large area, sending
        different events by the different CUL's might disturb each other. This
        phenomenon is also known as the Palm-Beach-Resort effect.
        Putting them in a common sendpool will serialize sending the events.
        E.g. if you have three CUN's, you have to specify following
        attributes:<br>
        <code>attr CUN1 sendpool CUN1,CUN2,CUN3<br>
        attr CUN2 sendpool CUN1,CUN2,CUN3<br>
        attr CUN3 sendpool CUN1,CUN2,CUN3</code><br>
        </li><br>
    <li><a name="addvaltrigger">addvaltrigger</a><br>
        Create triggers for additional device values. Right now these are RSSI
        and RAWMSG for the CUL family and RAWMSG for the FHZ.
        </li><br>
    <li><a name="rfmode">rfmode</a><br>
        Configure the RF Transceiver of the CUL (the CC1101). Available
        arguments are:
        <ul>
        <li>SlowRF<br>
            To communicate with FS20/FHT/HMS/EM1010/S300/Hoermann devices @1 kHz
            datarate. This is the default.</li>

        <li>HomeMatic<br>
            To communicate with HomeMatic type of devices @10 kHz datarate.</li>

        <li>MAX<br>
            To communicate with MAX! type of devices @10 kHz datarate.</li>

        </ul>
        </li><br>
    <li><a name="hmId">hmId</a><br>
        Set the HomeMatic ID of this device. If this attribute is absent, the
        ID will be F1&lt;FHTID&gt;. Note 1: After setting or changing this
        attribute you have to relearn all your HomeMatic devices. Note 2: The
        value <b>must</b> be a 6 digit hex number, and 000000 is not valid. FHEM
        won't complain if it is not correct, but the communication won't work.
        </li><br>

    <li><a name="hmProtocolEvents">hmProtocolEvents</a><br>
        Generate events for HomeMatic protocol messages. These are normally
        used for debugging, by activating "inform timer" in a telnet session,
        or looking at the Event Monitor window in the FHEMWEB frontend.<br>
        Example:
        <ul>
        <code>
        2012-05-17 09:44:22.515 CUL CULHM RCV L:0B N:81 CMD:A258 SRC:...... DST:...... 0000 (TYPE=88,WAKEMEUP,BIDI,RPTEN)
        </code>
        </ul>
        </li><br>
  </ul>
  <br>
  </ul>

=end html

=begin html_DE

<a name="CUL"></a>
<h3>CUL</h3>
<ul>

  <table>
  <tr><td>
  Der CUL/CUR/CUN(O) ist eine Familie von Funkempf&auml;ngern, die von der Firma
  <a href="http://www.busware.de">Busware</a> verkauft wird.

  Mit der OpenSource Firmware 
  <a href="http://culfw.de/culfw.html">culfw</a> k&ouml;nnen sie verschiedene
  868 MHz Funkprotokolle empfangen bzw. senden (FS20/FHT/S300/EM/HMS/MAX!).
  Man kann diese Ger&auml;te auch zur Reichweitenverl&auml;ngerung, siehe 
  <a href="#CUL_RFR">CUL_RFR</a> einsetzen.
  <br> <br>

  Einige Protokolle (FS20, FHT und KS300) werden von diesem Modul in das FHZ
  Format konvertiert, daher kann dasselbe logische Ger&auml;t verwendet werden,
  egal ob das Funktelegramm von einem CUL oder einem FHZ Ger&auml;t empfangen
  wird.<br>

  Andere Protokolle (S300/EM) ben&ouml;tigen ihre eigenen Module.  S300
  Ger&auml;te werden vom Modul CUL_WS verarbeitet, wenn das Signal von einem
  CUL empfangen wurde, &auml;hnliches gilt f&uuml;r EMWZ/EMGZ/EMEM: diese
  werden vom CUL_EM Modul verarbeitet.<br><br>

  Es ist m&ouml;glich mehr als ein Ger&auml;t zu verwenden, um einen besseren
  Empfang zu erhalten, FHEM filtert doppelte Funktelegramme aus.<br><br>

  Bemerkung: Dieses Modul ben&ouml;tigt unter Umst&auml;nden das
  <code>Device::SerialPort</code> bzw. <code>Win32::SerialPort</code> Modul,
  wenn Sie das Ger&auml;t &uuml;ber USB anschlie&szlig;en und das
  Betriebssystem un&uuml;bliche Parameter f&uuml;r serielle Schnittstellen
  setzt.<br><br>

  </td><td>
  <img src="ccc.jpg"/>
  </td></tr>
  </table>

  <a name="CULdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; CUL &lt;device&gt; &lt;FHTID&gt;</code> <br>
    <br>
    Ger&auml;te, die an USB angeschlossen sind (CUL/CUR/CUN):<br>
    <ul>
      &lt;device&gt; gibt die serielle Schnittstelle an, mit der der CUL
      kommuniziert.  Der Name der seriellen Schnittstelle h&auml;ngt von der
      gew&auml;hlten Distribution und USB-Treiber ab, unter Linux ist dies das
      Kernel Modul cdc_acm und &uuml;blicherweise wird die Schnittstelle
      /dev/ttyACM0 genannt. Wenn die Linux Distribution &uuml;ber kein Kernel
      Modul cdc_acm verf&uuml;gt, dann kann die Schnittstelle &uuml;ber
      usbserial mit dem folgenden Befehl erzeugt werden: 
        <ul><code>
          modprobe usbserial vendor=0x03eb product=0x204b
        </code></ul>
      In diesem Fall ist diese Schnittstelle dann wahrscheinlich
      /dev/ttyUSB0.<br><br>

      Wenn der Name der Schnittstelle ein @ enth&auml;lt, kann nachfolgend die
      verwendete Baudrate angegeben werden, z.B.: /dev/ttyACM0@38400.<br><br>

      Wenn die Baudrate mit "directio" angegeben wird (z.B.:
      /dev/ttyACM0@directio), wird das Perl Modul
      <code>Device::SerialPort</code> nicht ben&ouml;tigt und FHEM &ouml;ffnet
      die Schnittstelle mit einfachem Dateizugriff. Dies sollte dann
      funktionieren, wenn das Betriebssystem vern&uuml;nftige Standardwerte
      f&uuml;r die serielle Schnittstelle verwendet, wie z.B. einige Linux
      Distributionen oder OSX.<br><br>
    </ul>

    Ger&auml;te, die mit dem Netzwerk verbunden sind (CUN(O)):<br>
    <ul>
      &lt;device&gt; gibt die Hostadresse:Port des Ger&auml;tes an, z.B.
      192.168.0.244:2323
    </ul>
    <br>

    Wenn das Ger&auml;t mit none bezeichnet wird, wird keine Schnittstelle
    ge&ouml;ffnet und man kann ohne angeschlossene Hardware
    experimentieren.<br>

    Die FHTID ist eine 4-stellige hexadezimale Zahl und wird verwendet, wenn
    der CUL FHT Telegramme sendet bzw. Daten anfragt. Diese sollte als 0000
    gew&auml;hlt werden, wenn man FHT80b Anfragen durch den CUL vermeiden will.
  </ul>
  <br>

  <a name="CULset"></a>
  <b>Set </b>
  <ul>
    <li>raw<br>
        Sendet einen CUL Firmware Befehl. Siehe auch 
        <a href="http://culfw.de/commandref.html">hier</a> f&uuml;r
        n&auml;here Erl&auml;uterungen der CUL Befehle.
        </li><br>

    <li>freq / bWidth / rAmpl / sens<br>
        Nur in der Betriebsart <a href="#rfmode">SlowRF</a>.<br> Bestimmt die
        CUL Frequenz / Bandbreite / Empf&auml;nger Amplitude /
        Empfindlichkeit<br>

        Bitte mit Vorsicht verwenden, da es die verwendete Hardware
        zerst&ouml;ren kann bzw.  es zu illegalen Funkzust&auml;nden kommen
        kann. <br> Bemerkung: Die Parameter f&uuml;r die RFR &Uuml;bermittlung
        werden hierdurch nicht beeinflu&szlig;t.<br>
        <ul>
        <li>freq bestimmt sowohl die Empfangs- als auch die Sendefrequenz.<br>
            Bemerkung: Auch wenn der CC1101 zwischen den Frequenzen 315 und 915
            MHz eingestellt werden kann, ist die Antennenanbindung bzw. die Antenne
            des CUL exakt auf eine Frequenz eingestellt.
            Standard ist 868.3 MHz (bzw. 433 MHz).</li>

        <li>bWidth kann zwischen 58 kHz und 812 kHz variiert werden.
            Gro&szlig;e Werte sind empfindlicher gegen Interferencen, aber
            machen es m&ouml;glich, nicht genau kalbrierte Signale zu
            empfangen. Die Einstellung beeinflusst ebenso die &Uuml;bertragung.
            Standardwert ist 325 kHz.</li>

        <li>rAmpl ist die Verst&auml;rkung des Empf&auml;ngers mit Werten
            zwischen 24 and 42 dB.  Gr&ouml;&szlig;ere Werte erlauben den
            Empfang von schwachen Signalen.  Standardwert ist 42.</li>

        <li>sens ist die Entscheidungsgrenze zwischen "on" und "off"
            Zust&auml;nden und kann 4, 8, 12 oder 16 dB sein. Kleinere Werte
            erlauben den Empfang von undeutlicheren Signalen. Standard ist 4
            dB.</li>
        </ul>
        </li><br>
    <a name="hmPairForSec"></a>
    <li>hmPairForSec<br>
       Nur in der Betriebsart <a href="#rfmode">HomeMatic</a>.<br> Versetzt den
       CUL f&uuml;r die angegebene Zeit in Sekunden in den Anlern-Modus.  Jedes
       HM Ger&auml;t, das sich im Anlern-Modus befindet, wird an FHEM
       angelernt.  </li><br>

    <a name="hmPairSerial"></a>
    <li>hmPairSerial<br>
       Nur in der Betriebsart <a href="#rfmode">HomeMatic</a>.<br>
       Versucht, das angegebene Ger&auml;t anzulernen (zu "pairen"). Der
       Parameter ist eine 10-stellige Zeichenfolge, die normalerweise mit
       Buchstaben beginnt und mit Ziffern endet; diese sind auf der
       R&uuml;ckseite der Ger&auml;te aufgedruckt.  Wenn das Ger&auml;t ein
       Empf&auml;nger ist, ist es nicht notwendig, das angegebene Ger&auml;t in
       den Anlern-Modus zu versetzen.  </li><br>

    <a name="hmPairForSec"></a>
    <li>led<br>
        Schaltet die LED des CUL: aus (00), an (01) oder blinkend (02).
        </li><br>
  </ul>

  <a name="CULget"></a>
  <b>Get</b>
  <ul>
    <li>version<br>
        gibt die Version der CUL Firmware zur&uuml;ck
        </li><br>
    <li>uptime<br>
        gibt die Betriebszeit des CULs zur&uuml;ck (Zeit seit dem letzten Reset
        des CULs) </li><br>

    <li>raw<br>
        Sendet einen CUL Firmware Befehl und wartet auf eine R&uuml;ckgabe des
        CULs.  Siehe auch README der Firmware f&uuml;r n&auml;here
        Erl&auml;uterungen zu den CUL Befehlen.  </li><br>

    <li>fhtbuf<br>
        Der CUL hat einen Puffer f&uuml;r Nachrichten f&uuml;r FHT. Wenn der
        Puffer voll ist, werden neu empfangene Telegramme ignoriert und eine
        "EOB" Meldung wird in die FHEM Logdatei geschrieben.

        <code>fhtbuf</code> gibt den freien Speicher dieses Puffers (in hex)
        zur&uuml;ck, ein leerer Puffer im CUL V2 hat 74 Byte, im CUL V3/CUN(O)
        hat 200 Byte.  Eine Telegramm ben&ouml;tigt 3 + 2x(Anzahl der FHT
        Befehle) Byte, dies ist ein Grund, warum man mehrere FHT Befehle mit
        einem <a href="#set">set</a> senden sollte. Ein weiterer Grund ist,
        dass diese FHT Befehle in einem "Paket" zum FHT Ger&auml;t gesendet werden.
        </li> <br>

    <li>ccconf<br>
        Liest einige CUL Register des CC1101 (Sende- und Empf&auml;ngerchips)
        aus (Frequenz, Bandbreite, etc.) und stellt diese in lesbarer Form dar.
        </li><br>

    <li>cmds<br>
        In abh&auml;gigkeit der installierten Firmware hat der CUL/CUR/CUN(O)
        unterschiedliche Befehlss&auml;tze. N&auml;here Informationen &uuml;ber
        die Befehle bzw. deren Interpretation siehe README Datei der
        verwendeten CUL Firmware. Siehe auch Anmerkungen beim raw Befehl.
        </li><br>

    <li>credit10ms<br>
        Der Funkraum darf f&uuml;r eine Dauer von credit10ms*10 ms belegt
        werden, bevor die gesetzliche 1% Grenze erreicht ist und eine
        LOVF Meldung ausgegeben wird.  </li><br> </ul>

  <a name="CULattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#attrdummy">dummy</a></li>
    <li><a href="#showtime">showtime</a></li>
    <li><a href="#model">model</a> (CUL,CUN,CUR)</li>
    <li><a name="sendpool">sendpool</a><br>
        Wenn mehr als ein CUL verwendet wird, um einen gr&ouml;&szlig;eren
        Bereich abzudecken, k&ouml;nnen diese sich gegenseitig
        beeinflussen. Dieses Ph&auml;nomen wird auch Palm-Beach-Resort Effekt
        genannt.  Wenn man diese zu einen gemeinsamen Sende"pool"
        zusammenschlie&szlig;t, wird das Senden der einzelnen Telegramme
        seriell (d.h. hintereinander) durchgef&uuml;hrt.
        Wenn z.B. drei CUN's zur
        Verf&uuml;gung stehen, werden folgende Attribute gesetzt:<br>
        <code>attr CUN1 sendpool CUN1,CUN2,CUN3<br>
        attr CUN2 sendpool CUN1,CUN2,CUN3<br>
        attr CUN3 sendpool CUN1,CUN2,CUN3</code><br>
        </li><br>

    <li><a name="addvaltrigger">addvaltrigger</a><br>
        Generiert Trigger f&uuml;r zus&auml;tzliche Werte. Momentan sind dies
        RSSI und RAWMSG f&uuml;r die CUL Familie und RAWMSG f&uuml;r FHZ.
        </li><br>

    <li><a name="rfmode">rfmode</a><br>
        Konfiguriert den RF Transceiver des CULs (CC1101). Verf&uuml;gbare
        Argumente sind:
        <ul>
        <li>SlowRF<br>
            F&uuml;r die Kommunikation mit FS20/FHT/HMS/EM1010/S300/Hoermann
            Ger&auml;ten @1 kHz Datenrate (Standardeinstellung).</li>

        <li>HomeMatic<br>
            F&uuml;r die Kommunikation mit HomeMatic Ger&auml;ten @10 kHz
            Datenrate.</li>

        <li>MAX<br>
            F&uuml;r die Kommunikation mit MAX! Ger&auml;ten @10 kHz
            Datenrate.</li>

        </ul>
        </li><br>

    <li><a name="hmId">hmId</a><br>
        Setzt die HomeMatic ID des Ger&auml;tes. Wenn dieses Attribut fehlt,
        wird die ID zu F1&lt;FHTID&gt; gesetzt. Bemerkung 1: Nach dem Setzen
        bzw. Ver&auml;ndern dieses Attributes m&uuml;ssen alle HomeMatic
        Ger&auml;te neu angelernt werden.  Bemerkung 2: Der Wert <b>muss</b>
        eine 6-stellige Hexadezimalzahl sein, 000000 ist ung&uuml;ltig. FHEM
        &uuml;berpr&uuml;ft nicht, ob die ID korrekt ist, im Zweifelsfall
        funktioniert die Kommunikation nicht.  </li><br>

    <li><a name="hmProtocolEvents">hmProtocolEvents</a><br>
        Generiert Ereignisse f&uuml;r HomeMatic Telegramme. Diese werden
        normalerweise f&uuml;r die Fehlersuche verwendet, z.B. durch Aktivieren
        von <code>inform timer</code> in einer telnet Sitzung bzw. im
        <code>Event Monitor</code> Fenster im FHEMWEB Frontend.<br>
        Beispiel:
        <ul>
        <code>
        2012-05-17 09:44:22.515 CUL CULHM RCV L:0B N:81 CMD:A258 SRC:...... DST:...... 0000 (TYPE=88,WAKEMEUP,BIDI,RPTEN)
        </code>
        </ul>
        </li><br>
  </ul>
  <br>
  </ul>

=end html_DE
=cut

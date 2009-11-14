##############################################

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub CUL_Clear($);
sub CUL_Write($$$);
sub CUL_Read($);
sub CUL_ReadAnswer($$$);
sub CUL_Ready($);
sub CUL_HandleCurRequest($$);
sub CUL_HandleWriteQueue($);

sub CUL_OpenDev($$);
sub CUL_CloseDev($);
sub CUL_SimpleWrite(@);
sub CUL_SimpleRead($);

my $initstr = "X21";    # Only translated messages + RSSI
my %gets = (
  "version"  => "V",
  "raw"      => "",
  "ccconf"   => "=",
  "uptime"   => "t",
  "file"     => "",
  "time"     => "c03",
  "fhtbuf"   => "T03"
);

my %sets = (
  "raw"       => "",
  "freq"      => "",
  "bWidth"    => "",
  "rAmpl"     => "",
  "sens"      => "",
  "verbose"   => "X",
  "led"       => "l",
  "patable"   => "x",
  "file"      => "",
  "time"      => ""
);

my @ampllist = (24, 27, 30, 33, 36, 38, 40, 42);

sub
CUL_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "CUL_Read";
  $hash->{WriteFn} = "CUL_Write";
  $hash->{Clients} = ":FS20:FHT:KS300:CUL_EM:CUL_WS:USF1000:HMS:CUL_FHTTK:";
  my %mc = (
    "1:USF1000"   => "^81..(04|0c)..0101a001a5ceaa00....",
    "2:FS20"      => "^81..(04|0c)..0101a001",
    "3:FHT"       => "^81..(04|09|0d)..(0909a001|83098301|c409c401)..",
    "4:KS300"     => "^810d04..4027a001",
    "5:CUL_WS"    => "^K.....",
    "6:CUL_EM"    => "^E0.................\$",
    "7:HMS"       => "^810e04....(1|5|9).a001",
    "8:CUL_FHTTK" => "^T........",
  );
  $hash->{MatchList} = \%mc;
  $hash->{ReadyFn} = "CUL_Ready";

# Normal devices
  $hash->{DefFn}   = "CUL_Define";
  $hash->{UndefFn} = "CUL_Undef";
  $hash->{GetFn}   = "CUL_Get";
  $hash->{SetFn}   = "CUL_Set";
  $hash->{StateFn} = "CUL_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "showtime:1,0 model:CUL,CUR loglevel:0,1,2,3,4,5,6 " . 
                     "CUR_id_list fhtsoftbuffer:1,0";
  $hash->{ShutdownFn} = "CUL_Shutdown";
}

#####################################
sub
CUL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> CUL devicename <FHTID>"
    if(@a < 4 || @a > 5);

  CUL_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  return "FHTID must be H1H2, with H1 and H2 hex and both smaller than 64"
                if(uc($a[3]) !~ m/^[0-6][0-9A-F][0-6][0-9A-F]$/);
  $hash->{FHTID} = uc($a[3]);

  $attr{$name}{savefirst} = 1;

  if($dev eq "none") {
    Log 1, "CUL device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = CUL_OpenDev($hash, 0);
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
        Log GetLogLevel($name,$lev), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }

  CUL_SimpleWrite($hash, "X00"); # Switch reception off, it may hang up the CUL
  CUL_CloseDev($hash); 
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

  if($type eq "freq") {                         # MHz

    my $f = $arg/26*65536;

    my $f2 = sprintf("%02x", $f / 65536);
    my $f1 = sprintf("%02x", int($f % 65536) / 256);
    my $f0 = sprintf("%02x", $f % 256);
    $arg = sprintf("%.3f", (hex($f2)*65536+hex($f1)*256+hex($f0))/65536*26);
    my $msg = "Setting FREQ2..0 (0D,0E,0F) to $f2 $f1 $f0 = $arg MHz";
    Log GetLogLevel($name,4), $msg;
    CUL_SimpleWrite($hash, "W0F$f2");
    CUL_SimpleWrite($hash, "W10$f1");
    CUL_SimpleWrite($hash, "W11$f0");
    CUL_SimpleWrite($hash, $initstr);           # Will reprogram the CC1101
    return $msg;

  } elsif($type eq "bWidth") {               # KHz

    my ($err, $ob);
    if(!IsDummy($hash->{NAME})) {
      CUL_SimpleWrite($hash, "C10");
      ($err, $ob) = CUL_ReadAnswer($hash, $type, 0);
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
    my $msg = "Setting MDMCFG4 (10) to $ob = $bw KHz";

    Log GetLogLevel($name,4), $msg;
    CUL_SimpleWrite($hash, "W12$ob");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } elsif($type eq "rAmpl") {               # dB

    return "a numerical value between 24 and 42 is expected"
        if($arg !~ m/^\d+$/ || $arg < 24 || $arg > 42);
    my ($v, $w);
    for($v = 0; $v < @ampllist; $v++) {
      last if($ampllist[$v] > $arg);
    }
    $v = sprintf("%02d", $v-1);
    $w = $ampllist[$v];
    my $msg = "Setting AGCCTRL2 (1B) to $v / $w dB";
    CUL_SimpleWrite($hash, "W1D$v");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } elsif($type eq "sens") {               # dB

    return "a numerical value between 4 and 16 is expected"
        if($arg !~ m/^\d+$/ || $arg < 4 || $arg > 16);
    my $w = int($arg/4)*4;
    my $v = sprintf("9%d",$arg/4-1);
    my $msg = "Setting AGCCTRL0 (1D) to $v / $w dB";
    CUL_SimpleWrite($hash, "W1F$v");
    CUL_SimpleWrite($hash, $initstr);
    return $msg;

  } elsif($type eq "file") {

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
    ($err, $msg) = CUL_ReadAnswer($hash, $type, 1);
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
    CUL_SimpleWrite($hash, $initstr);
    return "$name: $err" if($err);

  } elsif($type eq "time") {

    return "Only supported for CUR devices (see VERSION)" if(!CUL_isCUR($hash));
    my @a = localtime;
    my $msg = sprintf("c%02d%02d%02d", $a[2],$a[1],$a[0]);
    CUL_SimpleWrite($hash, $msg);

  } else { 

    return "Expecting a 0-padded hex number"
        if((length($arg)&1) == 1 && $type ne "raw");
    $initstr = "X$arg" if($type eq "verbose");
    Log GetLogLevel($name,4), "set $name $type $arg";
    CUL_SimpleWrite($hash, $sets{$type} . $arg);

  }
  return undef;
}

#####################################
sub
CUL_Get($@)
{
  my ($hash, @a) = @_;

  return "\"get CUL\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));

  my $arg = ($a[2] ? $a[2] : "");
  my ($msg, $err);
  my $name = $a[0];

  return "No $a[1] for dummies" if(IsDummy($name));

  if($a[1] eq "ccconf") {

    my %r = ( "0D"=>1,"0E"=>1,"0F"=>1,"10"=>1,"1B"=>1,"1D"=>1 );
    foreach my $a (sort keys %r) {
      CUL_SimpleWrite($hash, "C$a");
      ($err, $msg) = CUL_ReadAnswer($hash, "C$a", 0);
      return $err if($err);
      my @answ = split(" ", $msg);
      $r{$a} = $answ[4];
    }
    $msg = sprintf("freq:%.3fMHz bWidth:%dKHz rAmpl:%ddB sens:%ddB",
        26*(($r{"0D"}*256+$r{"0E"})*256+$r{"0F"})/65536,                #Freq
        26000/(8 * (4+(($r{"10"}>>4)&3)) * (1 << (($r{"10"}>>6)&3))),   #Bw
        $ampllist[$r{"1B"}],
        4+4*($r{"1D"}&3)                                                #Sens
        );
    
  } elsif($a[1] eq "file") {

    return "Only supported for CUR devices (see VERSION)" if(!CUL_isCUR($hash));

    CUL_Clear($hash);
    CUL_SimpleWrite($hash, "X00");

    if(int(@a) == 2) {  # No argument: List directory

      CUL_SimpleWrite($hash, "r.");
      ($err, $msg) = CUL_ReadAnswer($hash, $a[1], 0);
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
      ($err, $msg) = CUL_ReadAnswer($hash, $a[1], 0);
      goto READEND if($err);

      if($msg eq "X") {
        $err = "$a[2]: file not found on CUL";
        goto READEND if($err);
      }
      $msg =~ s/[\r\n]//g;
      my ($len,  $buf) = (hex($msg), "");
      $msg = "";
      while(length($msg) != $len) {
        ($err, $buf) = CUL_ReadAnswer($hash, $a[1], 1);
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
    CUL_SimpleWrite($hash, $initstr);
    return "$name: $err" if($err);
    return $msg;

  } else {

    CUL_SimpleWrite($hash, $gets{$a[1]} . $arg);
    ($err, $msg) = CUL_ReadAnswer($hash, $a[1], 0);
    if(!defined($msg)) {
      CUL_Disconnected($hash);
      $msg = "No answer";
    };
    $msg =~ s/[\r\n]//g;

  }

  $hash->{READINGS}{$a[1]}{VAL} = $msg;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $msg";
}

#####################################
sub
CUL_SetState($$$$)
{
  my ($hash, $tim, $vt, $val) = @_;
  return undef;
}

sub
CUL_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    my ($err, undef) = CUL_ReadAnswer($hash, "Clear", 0);
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
    ($err, $ver) = CUL_ReadAnswer($hash, "Version", 0);
    return "$name: $err" if($err && ($err !~ m/Timeout/ || $try == 3));
  }

  if($ver !~ m/^V/) {
    $attr{$name}{dummy} = 1;
    $msg = "Not an CUL device, got for V:  $ver";
    Log 1, $msg;
    return $msg;
  }
  $hash->{VERSION} = $ver;

  if($ver =~ m/CUR/) {
    my @a = localtime;
    my $msg = sprintf("c%02d%02d%02d%02d%02d%02d",
                ($a[5]+1900)%100,$a[4]+1,$a[3],$a[2],$a[1],$a[0]);
    CUL_SimpleWrite($hash, $msg);
  }

  CUL_SimpleWrite($hash, $initstr);

  # FHTID
  my $fhtid;
  CUL_SimpleWrite($hash, "T01");
  ($err, $fhtid) = CUL_ReadAnswer($hash, "FHTID", 0);
  return "$name: $err" if($err);
  $fhtid =~ s/[\r\n]//g;
  Log 5, "GOT CUL fhtid: $fhtid";
  if(!defined($fhtid) || $fhtid ne $hash->{FHTID}) {
    Log 2, "Setting CUL fhtid from $fhtid to " . $hash->{FHTID};
    CUL_SimpleWrite($hash, "T01" . $hash->{FHTID});
  }

  $hash->{STATE} = "Initialized" if(!$hash->{STATE});

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
  return undef;
}

#####################################
# This is a direct read for commands like get
sub
CUL_ReadAnswer($$$)
{
  my ($hash, $arg, $anydata) = @_;

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
        CUL_Disconnected($hash);
        return("CUL_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = CUL_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));
    }

    if($buf) {
      Log 5, "CUL/RAW: $buf";
      $mculdata .= $buf;
    }
    return (undef, $mculdata) if($mculdata =~ m/\r\n/ || $anydata);
  }
}

#####################################
# Check if the 1% limit is reached and trigger notifies
sub
CUL_XmitLimitCheck($$)
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

  if(@b > 163) {          # Maximum nr of transmissions per hour (unconfirmed).

    my $name = $hash->{NAME};
    Log GetLogLevel($name,2), "CUL TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
sub
CUL_Write($$$)
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
    CUL_SimpleWrite($hash, $fn . $msg);
    return;

  } else {
    Log GetLogLevel($name,2), "CUL cannot translate $fn $msg";
    return;
  }

  Log 5, "CUL sending $fn$msg";
  my $bstring = "$fn$msg";

  if($fn eq "F") {

    if(!CUL_AddFS20Queue($hash, $bstring)) {
      CUL_XmitLimitCheck($hash,$bstring);
      CUL_SimpleWrite($hash, $bstring);
    }

  } else {

    CUL_SimpleWrite($hash, $bstring);

  }

}

sub
CUL_AddFS20Queue($$)
{
  my ($hash, $bstring) = @_;

  if(!$hash->{QUEUE}) {
    ##############
    # Write the next buffer not earlier than 0.23 seconds
    # = 3* (12*0.8+1.2+1.0*5*9+0.8+10) = 226.8ms
    # else it will be sent too early by the CUL, resulting in a collision
    $hash->{QUEUE} = [ $bstring ];
    InternalTimer(gettimeofday()+0.3, "CUL_HandleWriteQueue", $hash, 1);
    return 0;
  }
  push(@{$hash->{QUEUE}}, $bstring);
  return 1;
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
    if($bstring eq "-") {
      CUL_HandleWriteQueue($hash);
    } else {
      CUL_XmitLimitCheck($hash,$bstring);
      CUL_SimpleWrite($hash, $bstring);
      InternalTimer(gettimeofday()+0.3, "CUL_HandleWriteQueue", $hash, 1);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
CUL_Read($)
{
  my ($hash) = @_;

  my $buf = CUL_SimpleRead($hash);
  my $name = $hash->{NAME};

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = CUL_SimpleRead($hash);
  }

  if(!defined($buf) || length($buf) == 0) {
    CUL_Disconnected($hash);
    return "";
  }

  my $culdata = $hash->{PARTIAL};
  Log 5, "CUL/RAW: $culdata/$buf";
  $culdata .= $buf;

  while($culdata =~ m/\n/) {

    my ($rmsg, $rssi);
    ($rmsg,$culdata) = split("\n", $culdata, 2);
    $rmsg =~ s/\r//;
    goto NEXTMSG if($rmsg eq "");

    my $dmsg = $rmsg;
    if($initstr =~ m/X2/ && $dmsg =~ m/^[FTKEHR]([A-F0-9][A-F0-9])+$/) { # RSSI
      my $l = length($dmsg);
      $rssi = hex(substr($dmsg, $l-2, 2));
      $dmsg = substr($dmsg, 0, $l-2);
      $rssi = ($rssi>=128 ? (($rssi-256)/2-74) : ($rssi/2-74));
      Log GetLogLevel($name,4), "$name: $dmsg $rssi";
    } else {
      Log GetLogLevel($name,4), "$name: $dmsg";
    }

    ###########################################
    #Translate Message from CUL to FHZ
    next if(!$dmsg || length($dmsg) < 1);            # Bogus messages
    my $fn = substr($dmsg,0,1);
    my $len = length($dmsg);

    if($fn eq "F" && $len >= 9) {                    # Reformat for 10_FS20.pm

      CUL_AddFS20Queue($hash, "-");                  # Block immediate replies

      if(defined($attr{$name}) && defined($attr{$name}{CUR_id_list})) {
        my $id= substr($dmsg,1,4);
        if($attr{$name}{CUR_id_list} =~ m/$id/) {    # CUR Request
          CUL_HandleCurRequest($hash,$dmsg);
          goto NEXTMSG;
        }
      }

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

    } elsif($fn eq "E" && $len >= 11) {              # CUL_EM / Native
      ;
    } else {
      Log GetLogLevel($name,2), "CUL: unknown message $dmsg";
      goto NEXTMSG;
    }

    $hash->{RSSI} = $rssi if(defined($rssi));
    $hash->{RAWMSG} = $rmsg;
    my $foundp = Dispatch($hash, $dmsg);
    if($foundp) {
      foreach my $d (@{$foundp}) {
        next if(!$defs{$d});
        $defs{$d}{"RSSI_$name"} = $rssi if($rssi);
        $defs{$d}{RAWMSG} = $rmsg;
        $defs{$d}{"MSGCNT_$name"}++;
      }
    }

NEXTMSG:
  }
  $hash->{PARTIAL} = $culdata;
}

#####################################
sub
CUL_Ready($)
{
  my ($hash) = @_;

  return CUL_OpenDev($hash, 1)
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po=$hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub
CUL_SendCurMsg($$$)
{
  my ($hash,$id,$msg) = @_;

  $msg = substr($msg, 0, 12) if(length($msg) > 12);
  my $rmsg = "F" . $id .  unpack('H*', $msg);
  Log 1, "CUL_SendCurMsg: $id:$msg / $rmsg";
  sleep(1);                # Poor mans CSMA/CD
  CUL_SimpleWrite($hash, $rmsg);
}

sub
CUL_HandleCurRequest($$)
{
  my ($hash,$msg) = @_;


  Log 1, "CUR Request: $msg";
  my $l = length($msg);
  return if($l < 9);

  my $id = substr($msg,1,4);
  my $cm = substr($msg,5,2);
  my $a1 = substr($msg,7,2);
  my $a2 = pack('H*', substr($msg,9)) if($l > 9);

  if($cm eq "00") {     # Get status
    $msg = defined($defs{$a2}) ? $defs{$a2}{STATE} : "Undefined $a2";
    $msg =~ s/: /:/g;
    $msg =~ s/  / /g;
    $msg =~ s/.*[a-z]-//g;      # FHT desired-temp, but keep T:-1
    $msg =~ s/\(.*//g;          # FHT (Celsius) 
    $msg =~ s/.*5MIN:/5MIN:/g;  # EM
    $msg =~ s/\.$//;
    $msg =~ s/ *//;            # One letter seldom makes sense
    CUL_SendCurMsg($hash,$id, "d" . $msg);  # Display the message on the CUR
  }

  if($cm eq "01") {     # Send time
    my @a = localtime;
    $msg = sprintf("c%02d%02d%02d", $a[2],$a[1],$a[0]);
    CUL_SendCurMsg($hash,$id, $msg);
  }

  if($cm eq "02") {     # FHT desired temp
    $msg = sprintf("set %s desired-temp %.1f", $a2, $a1/2);
    fhem( $msg );
  }

}

########################
sub
CUL_SimpleWrite(@)
{
  my ($hash, $msg, $noapp) = @_;
  return if(!$hash);

  $msg .= "\n" unless($noapp);

  $hash->{USBDev}->write($msg . "\n") if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});

  #Log 1, "CUL_SimpleWrite >$msg<";
  select(undef, undef, undef, 0.001);
}

########################
sub
CUL_SimpleRead($)
{
  my ($hash) = @_;

  if($hash->{USBDev}) {
    return $hash->{USBDev}->input();
  }

  if($hash->{TCPDev}) {
    my $buf;
    if(!defined(sysread($hash->{TCPDev}, $buf, 256))) {
      CUL_Disconnected();
      return undef;
    }

    return $buf;
  }
  return undef;
}

########################
sub
CUL_CloseDev($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $dev = $hash->{DeviceName};

  return if(!$dev);
  
  if($hash->{TCPDev}) {
    $hash->{TCPDev}->close();
    delete($hash->{TCPDev});

  } elsif($hash->{USBDev}) {
    $hash->{USBDev}->close() ;
    delete($hash->{USBDev});

  }
  delete($selectlist{"$name.$dev"});
  delete($readyfnlist{"$name.$dev"});
  delete($hash->{FD});
}

########################
sub
CUL_OpenDev($$)
{
  my ($hash, $reopen) = @_;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};
  my $po;


  $hash->{PARTIAL} = "";
  Log 3, "CUL opening CUL device $dev"
        if(!$reopen);

  if($dev =~ m/^(.+):([0-9]+)$/) {       # host:port

    # This part is called every time the timeout (5sec) is expired _OR_
    # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
    if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
      return;
    }

    my $conn = IO::Socket::INET->new(PeerAddr => $dev);
    if($conn) {
      delete($hash->{NEXT_OPEN})

    } else {
      Log(3, "Can't connect to $dev: $!") if(!$reopen);
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      $hash->{NEXT_OPEN} = time()+60;
      return "";
    }

    $hash->{TCPDev} = $conn;
    $hash->{FD} = $conn->fileno();
    delete($readyfnlist{"$name.$dev"});
    $selectlist{"$name.$dev"} = $hash;

  } else {                              # USB Device
    if ($^O=~/Win/) {
     require Win32::SerialPort;
     $po = new Win32::SerialPort ($dev);
    } else  {
     require Device::SerialPort;
     $po = new Device::SerialPort ($dev);
    }

    if(!$po) {
      return undef if($reopen);
      Log(3, "Can't open $dev: $!");
      $readyfnlist{"$name.$dev"} = $hash;
      $hash->{STATE} = "disconnected";
      return "";
    }
    $hash->{USBDev} = $po;
    if( $^O =~ /Win/ ) {
      $readyfnlist{"$name.$dev"} = $hash;
    } else {
      $hash->{FD} = $po->FILENO;
      delete($readyfnlist{"$name.$dev"});
      $selectlist{"$name.$dev"} = $hash;
    }
  }

  if($reopen) {
    Log 1, "CUL $dev reappeared ($name)";
  } else {
    Log 3, "CUL opened $dev for $name";
  }

  $hash->{STATE}="";       # Allow InitDev to set the state
  my $ret  = CUL_DoInit($hash);

  if($ret) {
    CUL_CloseDev($hash);
    Log 1, "Cannot init $dev, ignoring it";
  }

  DoTrigger($name, "CONNECTED") if($reopen);
  return $ret;
}

sub
CUL_Disconnected($)
{
  my $hash = shift;
  my $dev = $hash->{DeviceName};
  my $name = $hash->{NAME};

  return if(!defined($hash->{FD}));                 # Already deleted.

  Log 1, "$dev disconnected, waiting to reappear";
  CUL_CloseDev($hash);
  $readyfnlist{"$name.$dev"} = $hash;               # Start polling
  $hash->{STATE} = "disconnected";

  # Without the following sleep the open of the device causes a SIGSEGV,
  # and following opens block infinitely. Only a reboot helps.
  sleep(5);

  DoTrigger($name, "DISCONNECTED");
}

1;

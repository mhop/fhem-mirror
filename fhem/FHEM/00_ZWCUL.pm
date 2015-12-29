##############################################
# $Id$
package main;

# TODO
#   inclusion/exclusion
#   resend in firmware
#   neighborUpdate Class: 010404010c0001 010604000c0040 010700 0105
#   static routing
#   explorer frames
#   implement security
#   multicast
# NIF:
#zwcul:        0101 d3 9c01 10 01 5e25263370273281855972867a73ef5a82 (zwcul)
#zme reporting:     1404    10 01 5e25263370273281855972867a73ef5a82
#zme nodeInfo: 0141 d3 9c01 041001 


use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

use ZWLib;
use DevIo;

sub ZWCUL_Parse($$$$$);
sub ZWCUL_Read($@);
sub ZWCUL_ReadAnswer($$$);
sub ZWCUL_Ready($);
sub ZWCUL_SimpleWrite($$);
sub ZWCUL_Write($$$);
sub ZWCUL_ProcessSendStack($);

use vars qw(%zwave_id2class);

my %sets = (
  "reopen"     => "",
  "raw"        => { cmd=> "%s" },
);

my %gets = (
  "homeId"     => { cmd=> "zi", regex => "^. [A-F0-9]{8} [A-F0-9]{2}\$" },
  "version"    => { cmd=> "V",  regex => "^V " },
  "raw"        => { cmd=> "%s", regex => ".*" }
);

sub
ZWCUL_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "ZWCUL_Read";
  $hash->{WriteFn} = "ZWCUL_Write";
  $hash->{ReadyFn} = "ZWCUL_Ready";
  $hash->{ReadAnswerFn} = "ZWCUL_ReadAnswer";

# Normal devices
  $hash->{DefFn}   = "ZWCUL_Define";
  $hash->{SetFn}   = "ZWCUL_Set";
  $hash->{GetFn}   = "ZWCUL_Get";
  $hash->{AttrFn}  = "ZWCUL_Attr";
  $hash->{UndefFn} = "ZWCUL_Undef";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 model disable:0,1 ".
                     "networkKey noDispatch dataRate:40k,100k,9600";
}

#####################################
sub
ZWCUL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> ZWCUL device homeId ctrlId" if(@a != 5);
  return "wrong syntax: homeId is 8 digit hex" if($a[3] !~ m/^[0-9A-F]{8}$/i);
  return "wrong syntax: ctrlId is 2 digit hex" if($a[4] !~ m/^[0-9A-F]{2}$/i);

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $hash->{homeId} = lc($a[3]);
  $hash->{homeIdSet} = lc($a[3]);
  $hash->{nodeIdHex} = lc($a[4]);
  $hash->{initString} = ($hash->{homeIdSet} =~ m/^0*$/ ? "zm":"zr");
  $hash->{monitor} = 1 if($hash->{homeIdSet} eq "00000000");

  $hash->{Clients} = ":ZWave:STACKABLE_CC:";
  my %matchList = ( "1:ZWave" => ".*",
                    "2:STACKABLE_CC"=>"^\\*");
  $hash->{MatchList} = \%matchList;

  if($dev eq "none") {
    Log3 $name, 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    readingsSingleUpdate($hash, "state", "dummy", 1);
    return undef;

  } elsif($dev !~ m/@/) {
    $def .= "\@9600";  # default baudrate

  }

  $hash->{DeviceName} = $dev;
  return DevIo_OpenDev($hash, 0, "ZWCUL_DoInit");
}

#####################################
sub
ZWCUL_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  $hash->{PARTIAL} = "";
  
  $hash->{RA_Timeout} = 0.5;     # Clear the pipe
  for(;;) {
    my ($err, undef) = ZWCUL_ReadAnswer($hash, "Clear", "wontmatch");
    last if($err && ($err =~ m/^Timeout/ || $err =~ m/No FD/));
  }
  delete($hash->{RA_Timeout});

  my ($err, $ver, $try) = ("", "", 0);
  while($try++ < 3 && $ver !~ m/^V/) {
    ZWCUL_SimpleWrite($hash, "V");
    ($err, $ver) = ZWCUL_ReadAnswer($hash, "Version", "^V");
    return "$name: $err" if($err && ($err !~ m/Timeout/ || $try == 3));
    $ver = "" if(!$ver);
  }
  if($ver !~ m/^V/) {
    $attr{$name}{dummy} = 1;
    my $msg = "Not an CUL device, got for V:  $ver";
    Log3 $name, 1, $msg;
    return $msg;
  }
  $ver =~ s/[\r\n]//g;
  $hash->{VERSION} = $ver;

  ZWCUL_SimpleWrite($hash, "zi".$hash->{homeIdSet}.$hash->{nodeIdHex});
  ZWCUL_SimpleWrite($hash, $hash->{initString});

  readingsSingleUpdate($hash, "state", "Initialized", 1);
  return undef;
}


#####################################
sub
ZWCUL_Undef($$) 
{
  my ($hash,$arg) = @_;
  ZWCUL_SimpleWrite($hash, "zx");
  DevIo_CloseDev($hash); 
  return undef;
}

#####################################
sub
ZWCUL_cmd($$@)
{
  my ($type, $cmdList, $hash, @a) = @_;
  my $name = shift @a;

  return "\"$type $name\" needs at least one parameter" if(@a < 1);
  my $cmdName = shift @a;

  if(!defined($cmdList->{$cmdName})) {
    return "Unknown argument $cmdName, choose one of " .
                join(" ",sort keys %{$cmdList});
  }

  Log3 $hash, 4, "ZWCUL $type $name $cmdName ".join(" ",@a);
  if($cmdName eq "reopen") {
    return if(AttrVal($name, "dummy",undef) || AttrVal($name, "disable",undef));
    delete $hash->{NEXT_OPEN};
    DevIo_CloseDev($hash);
    sleep(1);
    DevIo_OpenDev($hash, 0, "ZWCUL_DoInit");
    return;
  }

  my $cmd = $cmdList->{$cmdName}{cmd};
  my @ca = split("%", $cmd, -1);
  my $nargs = int(@ca)-1;
  return "$type $name $cmdName needs $nargs arguments" if($nargs != int(@a));
  $cmd = sprintf($cmd, @a);
  ZWCUL_SimpleWrite($hash,  $cmd);
  
  return undef if($type eq "set");

  my $re = $cmdList->{$cmdName}{regexp};
  my ($e, $d) = ZWCUL_ReadAnswer($hash, $cmdName, $cmdList->{$cmdName}{regexp});
  return $e if($e);
  return $d;
}

sub ZWCUL_Set() { return ZWCUL_cmd("set", \%sets, @_); };
sub ZWCUL_Get() { return ZWCUL_cmd("get", \%gets, @_); };

#####################################
sub
ZWCUL_SimpleWrite($$)
{
  my ($hash, $msg) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "SW: $msg";
  $msg .= "\n";

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{TCPDev}, $msg) if($hash->{TCPDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});
  select(undef, undef, undef, 0.001);
}

#####################################
sub
ZWCUL_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  Log3 $hash, 5, "ZWCUL_Write $fn $msg";
  if($msg =~ m/0013(..)(..)(.*)(....)/) {
    my ($t,$l,$p) = ($1,$2,$3);
    my $th = $modules{ZWave}{defptr}{"$fn $t"};
    if(!$th) {
      Log3 $hash, 1, "ZWCUL: no device found for $fn $t";
      return;
    }

    # Do not send wakeupNoMoreInformation in monitor mode
    return if($p eq "8408" && $hash->{monitor});

    $th->{sentIdx} = 0 if(!$th->{sentIdx} || $th->{sentIdx} == 15);
    $th->{sentIdx}++;

    my $s100 = (AttrVal($hash->{NAME}, "dataRate", "40k") eq "100k");

    $msg = sprintf("%s%s41%02x%02x%s%s", 
                    $fn, $hash->{nodeIdHex}, $th->{sentIdx},
                    length($p)/2+($s100 ? 11 : 10), $th->{nodeIdHex}, $p);
    $msg .= ($s100 ? zwlib_checkSum_16($msg) : zwlib_checkSum_8($msg));

    ZWCUL_SimpleWrite($hash, "zs".$msg);
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
ZWCUL_Read($@)
{
  my ($hash, $local, $regexp) = @_;

  my $buf = (defined($local) ? $local : DevIo_SimpleRead($hash));
  return "" if(!defined($buf));
  my $name = $hash->{NAME};

  my $culdata = $hash->{PARTIAL};
  #Log3 $name, 5, "ZWCUL/RAW: $culdata/$buf";
  $culdata .= $buf;

  while($culdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$culdata) = split("\n", $culdata, 2);
    $rmsg =~ s/\r//;
    $hash->{PARTIAL} = $culdata; # for recursive calls
    return $rmsg 
        if(defined($local) && (!defined($regexp) || ($rmsg =~ m/$regexp/)));
    ZWCUL_Parse($hash, $hash, $name, $rmsg, 0) if($rmsg);
    $culdata = $hash->{PARTIAL};
  }
  $hash->{PARTIAL} = $culdata;
  return undef;
}

sub
ZWCUL_Parse($$$$$)
{
  my ($hash, $iohash, $name, $rmsg, $nodispatch) = @_;

  if($rmsg =~ m/^\*/) {                           # STACKABLE_CC
    Dispatch($hash, $rmsg, undef);
    return;
  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  # showtime attribute
  readingsSingleUpdate($hash, "state", $hash->{READINGS}{state}{VAL}, 0);
  $hash->{RAWMSG} = $rmsg;
  my %addvals = (RAWMSG => $rmsg);

  Dispatch($hash, $rmsg, \%addvals) if($rmsg !~ m/^z/);

  $rmsg = lc($rmsg);
  my $me = $hash->{NAME};
  my $s100 = (AttrVal($me, "dataRate", "40k") eq "100k");

  if($rmsg =~ m/^za(..)$/) {
    Log3 $hash, 5, "$me sent ACK to $1";
    return;
  }

  my ($H, $S, $F, $f, $sn, $L, $T, $P, $C);
  if($s100 && $rmsg =~ '^z(........)(..)(..)(.)(.)(..)(..)(.*)(....)$') {
    ($H,$S,$F,$f,$sn,$L,$T,$P,$C) = ($1,$2,$3,$4,$5,$6,$7,$8,$9);

  } elsif(!$s100 && $rmsg =~ '^z(........)(..)(..)(.)(.)(..)(..)(.*)(..)$') {
    ($H,$S,$F,$f,$sn,$L,$T,$P,$C) = ($1,$2,$3,$4,$5,$6,$7,$8,$9);

  } else {
    Log3 $hash, 1, "ERROR: Unknown packet $rmsg";
    return;

  }

  my ($hF,$hf, $rf,$hc,$hp,$hops,$ri,$u1) = (hex($F),hex($f),"",0,0,"","","");
  # ITU G.9959, 8-4, 8-11
  if($hF&0x80) { # routing
    $hc = hex(substr($P,2,1));
    $hp = hex(substr($P,3,1));
    $ri = "R:".substr($P, 0, ($hc+2)*2)." ";
    $rf = substr($P, 0, 2);
    $hops = substr($P, 4, $hc*2);
    $hops =~ s/(..)/$1 /g;
    $P = substr($P,($hc+2)*2);
  }
  if($hF&4) { # Explorer?
    $u1 = " E:".substr($P,0,16)." ";
    $P = substr($P,16);
  }

  if(AttrVal($me, "verbose", 1) > 4) {
    Log3 $hash, 5, "$H S:$S F:$F f:$f SN:$sn L:$L T:$T ${ri}${u1}P:$P C:$C";
    Log3 $hash, 5, "   F:".
      (($hF & 3)==1 ? " singleCast" :
       ($hF & 3)==2 ? " multiCast" :
       ($hF & 3)==3 ? " ack" : " unknownHeaderType:".($hF&0x3)).
      (($hF & 4)    ? " explorer" : "").
      (($hF & 0x10)==0x10 ? " speedModified":"").
      (($hF & 0x20)==0x20 ? " lowPower":"").
      (($hF & 0x40)==0x40 ? " ackReq":"").
      (($hF & 0x80)==0x80 ? 
                        " routed, rf:$rf hopCnt:$hc hopPos:$hp hops:$hops":"").
      ((($hf>>1)&3)==0 ? " "          : 
      (($hf>>1)&3)==1 ? " shortBeam" :
      (($hf>>1)&3)==2 ? " longBeam"  :" unknownBeam");
  }

  return if($hc && !$hash->{monitor} && $hc == $hp);
  return if(AttrVal($me, "noDispatch", 0));


  $hash->{homeId} = $H; # Fake homeId for monitor mode

  if(length($P)) {
    $rmsg = sprintf("0004%s%s%02x%s", $S, $S, length($P)/2, $P);
    my $th = $modules{ZWave}{defptr}{"$H $S"};

    if(!($S eq $hash->{nodeIdHex} && $H eq $hash->{homeIdSet}) && !$th) {
      DoTrigger("global", "UNDEFINED ZWNode_${H}_$S ZWave $H ".hex($S));
      $th = $modules{ZWave}{defptr}{"$H $S"};
    }

  } else {
    $rmsg = sprintf("0013%s00", $S);

  }
  return $rmsg if($nodispatch);
  Dispatch($hash, $rmsg, \%addvals);
}

#####################################
# This is a direct read for commands like get
sub
ZWCUL_ReadAnswer($$$)
{
  my ($hash, $arg, $regexp) = @_;
  Log3 $hash, 4, "ZWCUL_ReadAnswer arg:$arg regexp:".($regexp ? $regexp:"");
  my $transform;
  if($regexp && $regexp =~ m/^\^000400(..)..(..)/) {
    $regexp = "^z........$1........$2";
    $transform = 1;
  }
  return ("No FD (dummy device?)", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));
  my $to = ($hash->{RA_Timeout} ? $hash->{RA_Timeout} : 1);

  for(;;) {

    my $buf;
    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("Timeout reading answer for get $arg", undef)
        if(length($buf) == 0);

    } else {
      if(!$hash->{FD}) {
        Log3 $hash, 1, "ZWCUL_ReadAnswer: device lost";
        return ("Device lost when reading answer for get $arg", undef);
      }

      my $rin = '';
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        my $err = $!;
        Log3 $hash, 5, "ZWCUL_ReadAnswer: nfound < 0 / err:$err";
        next if ($err == EAGAIN() || $err == EINTR() || $err == 0);
        DevIo_Disconnected($hash);
        return("ZWCUL_ReadAnswer $arg: $err", undef);
      }

      if($nfound == 0){
        Log3 $hash, 5, "ZWCUL_ReadAnswer: select timeout";
        return ("Timeout reading answer for get $arg", undef);
      }

      $buf = DevIo_SimpleRead($hash);
      if(!defined($buf)){
        Log3 $hash, 1,"ZWCUL_ReadAnswer: no data read";
        return ("No data", undef);
      }
    }

    my $ret = ZWCUL_Read($hash, $buf, $regexp);
    if(defined($ret)){
      if($transform) {
        my $name = $hash->{NAME};
        $ret = ZWCUL_Parse($hash, $hash, $name, $ret, 1);
      }
      Log3 $hash, 4, "ZWCUL_ReadAnswer for $arg: $ret";
      return (undef, $ret);
    }
  }
}

#####################################
sub
ZWCUL_Attr($$$$)
{
  my ($cmd, $name, $attr, $value) = @_;
  my $hash = $defs{$name};
  
  if($attr eq "disable") {
    if($cmd eq "set" && ($value || !defined($value))) {
      DevIo_CloseDev($hash) if(!AttrVal($name,"dummy",undef));
      readingsSingleUpdate($hash, "state", "disabled", 1);

    } else {
      if(AttrVal($name,"dummy",undef)) {
        readingsSingleUpdate($hash, "state", "dummy", 1);
        return;
      }
      DevIo_OpenDev($hash, 0, "ZWCUL_DoInit");

    }

  } elsif($attr eq "networkKey" && $cmd eq "set") {
    if(!$value || $value !~ m/^[0-9A-F]{32}$/i) {
      return "attr $name networkKey: not a hex string with a length of 32";
    }
    return;

  } elsif($attr eq "dataRate" && $cmd eq "set") {
    my $sfx = ($value eq "100k" ? "1" :
              ($value eq "9600" ? "9" : "4"));
    $hash->{initString} = ($hash->{homeIdSet} =~ m/^0*$/ ? "zm$sfx":"zr$sfx");
    ZWCUL_DoInit($hash);

  }

  return undef;  
  
}

#####################################
sub
ZWCUL_Ready($)
{
  my ($hash) = @_;

  return undef if (IsDisabled($hash->{NAME}));

  return DevIo_OpenDev($hash, 1, "ZWCUL_DoInit")
            if(ReadingsVal($hash->{NAME}, "state","") eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  if($po) {
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    return ($InBytes>0);
  }
  return 0;
}


1;

=pod
=begin html

<a name="ZWCUL"></a>
<h3>ZWCUL</h3>
<ul>
  This module serves a CUL in ZWave mode (starting from culfw version 1.66),
  which is attached via USB or TCP/IP, and enables the use of ZWave devices
  (see also the <a href="#ZWave">ZWave</a> module). 
  <br><br>
  <a name="ZWCULdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ZWCUL &lt;device&gt; &lt;homeId&gt;
          &lt;ctrlId&gt;</code>
  <br>
  <br>
  Since the DevIo module is used to open the device, you can also use devices
  connected via  TCP/IP. See <a href="#CULdefine">this</a> paragraph on device
  naming details.
  <br>
  Example:
  <ul>
    <code>define ZWCUL_1 ZWCUL /dev/cu.usbmodemfa141@9600 12345678 01</code><br>
  </ul>
  If the homeId is set to 0, then culfw will enter monitor mode, i.e. no
  checksum filtering will be done, and no acks for received messages will be
  sent.
  </ul>
  <br>

  <a name="ZWCULset"></a>
  <b>Set</b>
  <ul>

  <li>reopen<br>
    First close and then open the device. Used for debugging purposes.
    </li>

  <li>raw<br>
    send a raw string to culfw
    </li>


  </ul>
  <br>

  <a name="ZWCULget"></a>
  <b>Get</b>
  <ul>
  <li>homeId<br>
    return the homeId and the ctrlId of the controller.</li>

  <li>raw<br>
    Send raw data to the controller.</li>
  </ul>
  <br>

  <a name="ZWCULattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a name="#dataRate">dataRate</a> [40k|100k|9600]<br>
      specify the data rate.
      </li>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#networkKey">networkKey</a></li>
    <li><a name="#noDispatch">noDispatch</a><br>
      prohibit dispatching messages or creating ZWave devices.
      </li>
    <li>verbose<br>
      If the verbose attribute of this device (not global!) is set to 5 or
      higher, then detailed logging of the RF message will be done.
      </li>
    <li><a name="#noDispatch">noDispatch</a><br>
      prohibit dispatching messages or creating ZWave devices
      </li>
  </ul>
  <br>

  <a name="ZWCULevents"></a>
  <b>Generated events: TODO</b>

</ul>


=end html
=cut

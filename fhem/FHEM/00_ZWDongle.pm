##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);
use ZWLib;
use vars qw($FW_ME);

sub ZWDongle_Parse($$$);
sub ZWDongle_Read($@);
sub ZWDongle_ReadAnswer($$$);
sub ZWDongle_Ready($);
sub ZWDongle_Write($$$);
sub ZWDongle_ProcessSendStack($);
sub ZWDongle_NUCheck($$$$);


# See also:
# http://www.digiwave.dk/en/programming/an-introduction-to-the-z-wave-protocol/
# http://open-zwave.googlecode.com/svn-history/r426/trunk/cpp/src/Driver.cpp
# http://buzzdavidson.com/?p=68
# https://bitbucket.org/bradsjm/aeonzstickdriver
my %sets = (
  "addNode"          => { cmd => "4a%02x@",    # ZW_ADD_NODE_TO_NETWORK
                          param => { onNw   =>0xc1, on   =>0x81, off=>0x05,
                                     onNwSec=>0xc1, onSec=>0x81 } },
  "backupCreate"     => { cmd => "" },
  "backupRestore"    => { cmd => "" },
  "controllerChange" => { cmd => "4d%02x@",    # ZW_CONTROLLER_CHANGE
                          param => { on     =>0x02, stop =>0x05,
                                     stopFailed =>0x06 } },
  "createNewPrimary" => { cmd => "4c%02x@",    # ZW_CREATE_NEW_PRIMARY
                          param => { on     =>0x02, stop =>0x05,
                                     stopFailed =>0x06 } },
  "createNode"       => { cmd => "60%02x" },   # ZW_REQUEST_NODE_INFO
  "createNodeSec"    => { cmd => "60%02x" },   # ZW_REQUEST_NODE_INFO
  "factoryReset"     => { cmd => ""       },   # ZW_SET_DEFAULT
  "learnMode"        => { cmd => "50%02x@",    # ZW_SET_LEARN_MODE
                          param => { onNw   =>0x02, on   =>0x01,
                                     disable=>0x00 } },
  "removeFailedNode" => { cmd => "61%02x@" },  # ZW_REMOVE_FAILED_NODE_ID
  "removeNode"       => { cmd => "4b%02x@",    # ZW_REMOVE_NODE_FROM_NETWORK
                          param => {onNw=>0xc1, on=>0x81, off=>0x05 } },
  "reopen"           => { cmd => "" },
  "replaceFailedNode"=> { cmd => "63%02x@" },  # ZW_REPLACE_FAILED_NODE
  "routeFor"         => { cmd => "93%02x%02x%02x%02x%02x%02x" },
                                              # ZW_SET_PRIORITY_ROUTE
  "sendNIF"          => { cmd => "12%02x05@" },# ZW_SEND_NODE_INFORMATION
  "setNIF"           => { cmd => "03%02x%02x%02x%02x" },
                                              # SERIAL_API_APPL_NODE_INFORMATION
  "sucNodeId"        => { cmd => "54%02x%02x00%02x@"},
                                              # ZW_SET_SUC_NODE_ID
  "sucRequestUpdate" => { cmd => "53%02x@"},  # ZW_REQUEST_NETWORK_UPDATE
  "sucSendNodeId"    => { cmd => "57%02x25@"}, # ZW_SEND_SUC_ID
  "timeouts"         => { cmd => "06%02x%02x" }, # SERIAL_API_SET_TIMEOUTS
);

my %gets = (
  "caps"            => "07",      # SERIAL_API_GET_CAPABILITIES
  "ctrlCaps"        => "05",      # ZW_GET_CONTROLLER_CAPS
  "homeId"          => "20",      # MEMORY_GET_ID
  "isFailedNode"    => "62%02x",  # ZW_IS_FAILED_NODE
  "neighborList"    => "80%02x",  # GET_ROUTING_TABLE_LINE
  "nodeInfo"        => "41%02x",  # ZW_GET_NODE_PROTOCOL_INFO
  "nodeList"        => "02",      # SERIAL_API_GET_INIT_DATA
  "random"          => "1c%02x",  # ZW_GET_RANDOM
  "raw"             => "%s",      # hex
  "routeFor"        => "92%02x",  # hex
  "sucNodeId"       => "56",      # ZW_GET_SUC_NODE_ID
#  "timeouts"        => "06",     # Forum #71333
  "version"         => "15",      # ZW_GET_VERSION
);

sub
ZWDongle_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "ZWDongle_Read";
  $hash->{WriteFn} = "ZWDongle_Write";
  $hash->{ReadyFn} = "ZWDongle_Ready";
  $hash->{ReadAnswerFn} = "ZWDongle_ReadAnswer";

# Normal devices
  $hash->{DefFn}   = "ZWDongle_Define";
  $hash->{SetFn}   = "ZWDongle_Set";
  $hash->{GetFn}   = "ZWDongle_Get";
  $hash->{AttrFn}  = "ZWDongle_Attr";
  $hash->{UndefFn} = "ZWDongle_Undef";
  no warnings 'qw';
  my @attrList = qw(
    do_not_notify:1,0
    dummy:1,0
    model:ZWDongle
    disable:0,1
    helpSites:multiple,pepper,alliance
    homeId
    networkKey
    neighborListPos
    neighborListFmt
    showSetInState:1,0
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);

  $hash->{FW_detailFn} = "ZWDongle_fhemwebFn";
}

#####################################
sub
ZWDongle_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> ZWDongle {none[:homeId] | ".
                        "devicename[\@baudrate] | ".
                        "devicename\@directio | ".
                        "hostname:port}";
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];

  $hash->{Clients} = ":ZWave:";
  my %matchList = ( "1:ZWave" => ".*" );
  $hash->{MatchList} = \%matchList;

  if($dev =~ m/none:(.*)/) {
    $hash->{homeId} = $1;
    Log3 $name, 1,
        "$name device is none (homeId:$1), commands will be echoed only";
    $attr{$name}{dummy} = 1;
    readingsSingleUpdate($hash, "state", "dummy", 1);
    return undef;

  } elsif($dev !~ m/@/ && $dev !~ m/:/) {
    $def .= "\@115200";  # default baudrate

  }

  $hash->{DeviceName} = $dev;
  $hash->{CallbackNr} = 0;
  $hash->{nrNAck} = 0;
  my @empty;
  $hash->{SendStack} = \@empty;
  ZWDongle_shiftSendStack($hash, 0, 5, undef); # Init variables

  my $ret = DevIo_OpenDev($hash, 0, "ZWDongle_DoInit");
  return $ret;
}

#####################################
sub
ZWDongle_fhemwebFn($$$$)
{
  my ($FW_wname, $d, $room, $pageHash) = @_; # pageHash is set for summaryFn.

  my $js = "$FW_ME/pgm2/zwave_neighborlist.js";

  return
  "<div id='ZWDongleNr'><a id='zw_snm' href='#'>Show neighbor map</a></div>".
  "<div id='ZWDongleNrSVG'></div>".
  "<script type='text/javascript' src='$js'></script>".
  '<script type="text/javascript">'.<<"JSEND"
    \$(document).ready(function() {
      \$("div#ZWDongleNr a#zw_snm")
        .click(function(e){
          e.preventDefault();
          zw_nl('ZWDongle_nlData("$d")');
        });
    });
  </script>
JSEND
}

sub
ZWDongle_nlData($)
{
  my ($d) = @_;
  my @a = devspec2array("TYPE=ZWave,FILTER=IODev=$d");
  my (@dn, %nb, @ret);

  my $fmt = eval AttrVal($d, "neighborListFmt",
              '{ txt=>"NAME", img=>"IMAGE", title=>"Time to ack: timeToAck" }');

  for my $e (@a) {
    my $h = $defs{$e};
    next if($h->{ZWaveSubDevice} ne "no");
    $h->{IMAGE} = ZWave_getPic($d, ReadingsVal($e, "modelId", ""));

    my $nl = ReadingsVal($e, "neighborList", ""); 
    $nl = ReadingsVal($d, "neighborList_".hex($h->{nodeIdHex}), "")
      if(!$nl);

    $nl =~ s/,/ /g; $nl =~ s/\bempty\b//g;
    push @dn, $e if($nl =~ m/\b$d\b/);
    $nl = '"'.join('","',split(" ", $nl)).'"' if($nl);

    my %line = (
      pos       => '['.AttrVal($e, "neighborListPos", "").']',
      class     => '"zwBox"',
      neighbors => '['.$nl.']'
    );

    my $r = $h->{READINGS};
    my $a = $attr{$e};
    for my $key (keys %{$fmt}) {
      my $val = $fmt->{$key};
      $val =~ s/\b(\w+)\b/{ $h->{$1} ? $h->{$1} : 
                            $r->{$1} ? $r->{$1}{VAL} : 
                            $a->{$1} ? $a->{$1} : $1 }/ge;
      $line{$key} = "\"$val\"" if($val ne $fmt->{$key});  # Skip unchanged
    }
    push @ret, "\"$e\":{". join(',',map({"\"$_\":$line{$_}" } keys %line)) ."}";
    $nb{$e} = $nl;
  }

  my $pos = AttrVal($d, "neighborListPos", "");
  my $nl = (@dn ? '"'.join('","',@dn).'"' : '');
  push @ret, "\"$d\":{\"txt\":\"$d\", \"pos\":[$pos],".
                     "\"class\":\"zwDongle\",\"neighbors\":[$nl] }";
  return "{ \"saveFn\":\"attr {1} neighborListPos {2}\",".
           "\"firstObj\":\"$d\",".
           "\"el\":{".join(",",@ret)."} }";
}

#####################################
sub
ZWDongle_Undef($$)
{
  my ($hash,$arg) = @_;
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
ZWDongle_Set($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "\"set ZWDongle\" needs at least one parameter" if(@a < 1);
  my $type = shift @a;

  if(!defined($sets{$type})) {
    my @r;
    map { my $p = $sets{$_}{param};
          push @r,($p ? "$_:".join(",",sort keys %{$p}) : $_)} sort keys %sets;
    return "Unknown argument $type, choose one of " . join(" ",@r);
  }

  Log3 $hash, 4, "ZWDongle *** set $name $type ".join(" ",@a);
  if($type eq "reopen") {
    return if(AttrVal($name, "dummy",undef) || AttrVal($name, "disable",undef));
    delete $hash->{NEXT_OPEN};
    DevIo_CloseDev($hash);
    sleep(1);
    DevIo_OpenDev($hash, 0, "ZWDongle_DoInit");
    return;
  }

  if($type eq "backupCreate") {
    my $caps = ReadingsVal($name, "caps","");
    my $is4 = ($caps =~ m/MEMORY_GET_BUFFER/);
    my $is5 = ($caps =~ m/NVM_EXT_READ_LONG_BUFFER/);
    return "Creating a backup is not supported by this device"
      if(!$is4 && !$is5);
    return "Usage: set $name backupCreate [16k|32k|64k|128k|256k]"
      if(int(@a) != 1 || $a[0] !~ m/^(16|32|64|128|256)k$/);

    my $fn        = ($is5 ? "NVM_EXT_READ_LONG_BUFFER" : "MEMORY_GET_BUFFER");
    my $cmdFormat = ($is5 ? "002a%06x0040" : "0023%04x20");
    my $cmdRe     = ($is5 ? "^012a" : "^0123");
    my $inc       = ($is5 ? 64 : 32);

    my $l = $1 * 1024;
    my $fName = "$attr{global}{modpath}/$name.bin";
    open(OUT, ">$fName") || return "Cant open $fName: $!";
    binmode(OUT);
    for(my $off = 0; $off < $l;) {
      ZWDongle_Write($hash, "", sprintf($cmdFormat, $off));
      my ($err, $ret) = ZWDongle_ReadAnswer($hash, $fn, $cmdRe);
      return $err if($err);
      print OUT pack('H*', substr($ret, 4));
      $off += $inc;
      Log 3, "$name backupCreate at $off bytes" if($off % 16384 == 0);
    }

    close(OUT);
    return "Wrote $l bytes to $fName";
  }

  if($type eq "backupRestore") {
    my $caps = ReadingsVal($name, "caps","");
    my $is4 = ($caps =~ m/MEMORY_PUT_BUFFER/);
    my $is5 = ($caps =~ m/NVM_EXT_WRITE_LONG_BUFFER/);
    return "Restoring a backup is not supported by this device"
      if(!$is4 && !$is5);
    my $fn        = ($is5 ? "NVM_EXT_WRITE_LONG_BUFFER" : "MEMORY_PUT_BUFFER");
    my $cmdFormat = ($is5 ? "002b%06x0040%s" : "0024%04x40%s");
    my $cmdRe     = ($is5 ? "^012b"   : "^0124");
    my $cmdRet    = ($is5 ? "^012b01" : "^012401");
    my $inc       = ($is5 ? 64 : 32);

    return "Usage: set $name backupRestore" if(int(@a) != 0);
    my $fName = "$attr{global}{modpath}/$name.bin";
    my $l = -s $fName;
    return "$fName does not exists, or is empty" if(!$l);
    open(IN, $fName) || return "Cant open $fName: $!";
    binmode(IN);

    my $buf;
    for(my $off = 0; $off < $l;) {
      if(sysread(IN, $buf, $inc) != $inc) {
        return "Cant read $inc bytes from $fName";
      }
      ZWDongle_Write($hash, "", sprintf($cmdFormat, $off, unpack('H*',$buf)));
      my ($err, $ret) = ZWDongle_ReadAnswer($hash, $fn, $cmdRe);
      return $err if($err);
      return "Unexpected $fn return value $ret"
        if($ret !~ m/$cmdRet/);
      $off += $inc;
      Log 3, "$name backupRestore at $off bytes" if($off % 16384 == 0);
    }

    close(IN);
    return "Restored $l bytes from $fName";
  }

  if($type eq "factoryReset") {
    return "Reset to default is not supported by this device"
      if(ReadingsVal($name, "caps","") !~ m/ZW_SET_DEFAULT/);
    return "Read commandref before use! -> Usage: set $name factoryReset yes"
      if(int(@a) != 1 || $a[0] !~ m/^(yes)$/);
    ZWDongle_Write($hash,"","0042");
    return "Reseted $name to factory default and assigned new random HomeId";
  }

  if($type eq "removeFailedNode" ||
     $type eq "replaceFailedNode" ||
     $type =~ m/^createNode/ ||
     $type eq "sendNIF") {

    $a[0] =~ s/^UNKNOWN_//;

    $a[0] = hex($defs{$a[0]}{nodeIdHex})
      if($defs{$a[0]} && $defs{$a[0]}{nodeIdHex});
  }

  my $cmd = $sets{$type}{cmd};
  my $fb = substr($cmd, 0, 2);
  if($fb =~ m/^[0-8A-F]+$/i &&
     ReadingsVal($name, "caps","") !~ m/\b$zw_func_id{$fb}\b/) {
    return "$type is unsupported by this controller";
  }

  delete($hash->{addSecure});
  $hash->{addSecure} = 1 if($type eq "createNodeSec");

  if($type eq "addNode") {
    $hash->{addSecure} = 1 if($a[0] && $a[0] =~ m/sec/i);

    if($a[0]) { # Remember the client for the failed message
      if($a[0] eq "off") {
        delete($hash->{addCL});
      } elsif($hash->{CL}) {
        $hash->{addCL} = $hash->{CL};
      }
    }
  }

  if($type eq "routeFor") {
    for(@a = @a) {
      $_ =~ s/^UNKNOWN_//;
      $_ = hex($defs{$_}{nodeIdHex})
        if($defs{$_} && $defs{$_}{nodeIdHex});
      return "$_ is neither a device nor a decimal id" if($_ !~ m/\d+/);
    }
  }

  my $par = $sets{$type}{param};
  if($par && !$par->{noArg}) {
    return "Unknown argument for $type, choose one of ".join(" ",keys %{$par})
      if(!$a[0] || !defined($par->{$a[0]}));
    $a[0] = $par->{$a[0]};
  }

  if($cmd =~ m/\@/) {
    my $c = $hash->{CallbackNr}+1;
    $c = 1 if($c > 255);
    $hash->{CallbackNr} = $c;
    $c = sprintf("%02x", $c);
    $cmd =~ s/\@/$c/g;
  }


  my @ca = split("%", $cmd, -1);
  my $nargs = int(@ca)-1;
  return "set $name $type needs $nargs arguments" if($nargs != int(@a));

  ZWDongle_Write($hash, "",  "00".sprintf($cmd, @a));
  return undef;
}

#####################################
sub
ZWDongle_Get($@)
{
  my ($hash, @a) = @_;
  my $name = shift @a;

  return "\"get $name\" needs at least one parameter" if(@a < 1);
  my $cmd = shift @a;

  return "Unknown argument $cmd, choose one of " .
        join(" ", map { $gets{$_} =~ m/%/ ? $_ : "$_:noArg" } sort keys %gets)
        if(!defined($gets{$cmd}));

  my $fb = substr($gets{$cmd}, 0, 2);
  if($fb =~ m/^[0-8A-F]+$/i && $cmd ne "caps" &&
     ReadingsVal($name, "caps","") !~ m/\b$zw_func_id{$fb}\b/) {
    return "$cmd is unsupported by this controller";
  }

  if($cmd eq "raw") {
    if($a[0] =~ s/^42//) {
      Log3 $hash, 4, "ZWDongle *** get $name $cmd 42".join(" ",@a)." blocked";
      return "raw 0x42 (ZW_SET_DEFAULT) blocked. Read commandref first and ".
             "use instead: set $name factoryReset";
    }
  }

  Log3 $hash, 4, "ZWDongle *** get $name $cmd ".join(" ",@a);

  if($cmd eq "neighborList") {
    my @b;
    @b = grep(!/onlyRep/i,  @a); my $onlyRep = (@b != @a); @a = @b;
    @b = grep(!/excludeDead/i,  @a); my $exclDead = (@b != @a); @a = @b;
    $gets{neighborList} = "80%02x".($exclDead ?"00":"01").($onlyRep ?"01":"00");
    return "Usage: get $name $cmd [excludeDead] [onlyRep] nodeId"
        if(int(@a) != 1);
  }

  my @ga = split("%", $gets{$cmd}, -1);
  my $nargs = int(@ga)-1;
  return "get $name $cmd needs $nargs arguments" if($nargs != int(@a));

  return "No $cmd for dummies" if(IsDummy($name));

  my $a0 = $a[0];
  if($cmd eq "neighborList" ||
     $cmd eq "nodeInfo" ||
     $cmd eq "routeFor" ||
     $cmd eq "isFailedNode") {

    $a[0] =~ s/^UNKNOWN_//;

    $a[0] = hex($defs{$a[0]}{nodeIdHex})
     if($defs{$a[0]} && $defs{$a[0]}{nodeIdHex});
  }

  my $out = sprintf($gets{$cmd}, @a);
  ZWDongle_Write($hash, "", "00".$out);
  my $re = "^01".substr($out,0,2);  # Start with <01><len><01><CMD>
  my ($err, $ret) = ZWDongle_ReadAnswer($hash, $cmd, $re);
  return $err if($err);

  my $msg="";
  $a[0] = $a0 if(defined($a0));
  $msg = $ret if($ret);
  my @r = map { ord($_) } split("", pack('H*', $ret)) if(defined($ret));

  if($cmd eq "nodeList") {                     ############################
    $msg =~ s/^.{10}(.{58}).*/$1/;
    $msg = zwlib_parseNeighborList($hash, $msg);

  } elsif($cmd eq "caps") {                    ############################
    $msg  = sprintf("Vers:%d Rev:%d ",       $r[2], $r[3]);
    $msg .= sprintf("ManufID:%02x%02x ",     $r[4], $r[5]);
    $msg .= sprintf("ProductType:%02x%02x ", $r[6], $r[7]);
    $msg .= sprintf("ProductID:%02x%02x",    $r[8], $r[9]);
    my @list;
    for my $byte (0..31) {
      my $bits = $r[10+$byte];
      for my $bit (0..7) {
        my $id = sprintf("%02x", $byte*8+$bit+1);
        push @list, ($zw_func_id{$id} ? $zw_func_id{$id} : "UNKNOWN_$id")
                if($bits & (1<<$bit));
      }
    }
    $msg .= " ".join(" ",@list);

  } elsif($cmd eq "homeId") {                  ############################
    $msg = sprintf("HomeId:%s CtrlNodeIdHex:%s",
                substr($ret,4,8), substr($ret,12,2));
    $hash->{homeId} = substr($ret,4,8);
    $hash->{nodeIdHex} = substr($ret,12,2);
    $attr{$name}{homeId} = substr($ret,4,8);

  } elsif($cmd eq "version") {                 ############################
    $msg = join("",  map { chr($_) } @r[2..13]);
    my @type = qw( STATIC_CONTROLLER CONTROLLER ENHANCED_SLAVE
                   SLAVE INSTALLER NO_INTELLIGENT_LIFE BRIDGE_CONTROLLER);
    my $idx = $r[14]-1;
    $msg .= " $type[$idx]" if($idx >= 0 && $idx <= $#type);

  } elsif($cmd eq "ctrlCaps") {                ############################
    my @type = qw(SECONDARY OTHER MEMBER PRIMARY SUC);
    my @list;
    for my $bit (0..7) {
      push @list, $type[$bit] if(($r[2] & (1<<$bit)) && $bit < @type);
    }
    $msg = join(" ", @list);

  } elsif($cmd eq "nodeInfo") {                ############################
    if($r[6] == 0) {
      $msg = "node $a[0] is not present";
    } else {
      $msg = zwlib_parseNodeInfo(@r);
    }

  } elsif($cmd eq "random") {                  ############################
    return "$name: Cannot generate" if($ret !~ m/^011c01(..)(.*)$/);
    $msg = $2; @a = ();

  } elsif($cmd eq "isFailedNode") {            ############################
    $msg = ($r[2]==1)?"yes":"no";

  } elsif($cmd eq "neighborList") {            ############################
    $msg =~ s/^....//;
    $msg = zwlib_parseNeighborList($hash, $msg);

  } elsif($cmd eq "sucNodeId") {               ############################
    $msg = ($r[2]==0)?"no":$r[2];

  } elsif($cmd eq "routeFor") {                ############################
    my $homeId = $hash->{homeId};
    my @list;
    for(my $off=6; $off<16; $off+=2) {
        my $dec = hex(substr($msg, $off, 2));
        my $hex = sprintf("%02x", $dec);
        my $h = ($hex eq $hash->{nodeIdHex} ?
                        $hash : $modules{ZWave}{defptr}{"$homeId $hex"});
        push @list, ($h ? $h->{NAME} : "UNKNOWN_$dec") if($dec);
    }
    my $f = substr($msg, 17, 1);
    push @list, ("at ".($f==1 ? "9.6": ($f==2 ? "40":"100"))."kbps")
        if(@list && $f =~ m/[123]/);
    $msg = (@list ? join(" ", @list) : "N/A");
  }

  $cmd .= "_".join("_", @a) if(@a);
  readingsSingleUpdate($hash, $cmd, $msg, 0);
  return "$name $cmd => $msg";
}

#####################################
sub
ZWDongle_Clear($)
{
  my $hash = shift;

  # Clear the pipe
  for(;;) {
    my ($err, undef) = ZWDongle_ReadAnswer($hash, "Clear", "wontmatch");
    last if($err && ($err =~ m/^Timeout/ || $err =~ m/No FD/));
  }
  $hash->{PARTIAL} = "";
}

#####################################
sub
ZWDongle_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  DevIo_SetHwHandshake($hash) if($hash->{USBDev});
  $hash->{PARTIAL} = "";

  ZWDongle_Clear($hash);
  ZWDongle_Get($hash, $name, "caps");
  ZWDongle_Get($hash, $name, "ctrlCaps");
  ZWDongle_Get($hash, $name, "homeId");
  ZWDongle_Get($hash, $name, "sucNodeId");
  ZWDongle_Get($hash, $name, ("random", 32));         # Sec relevant
  ZWDongle_Set($hash, $name, ("timeouts", 100, 15));  # Sec relevant
  ZWDongle_ReadAnswer($hash, "timeouts", "^0106");
  # NODEINFO_LISTENING, Generic Static controller, Specific Static Controller, 0
  ZWDongle_Set($hash, $name, ("setNIF", 1, 2, 1, 0)); # Sec relevant (?)

  readingsSingleUpdate($hash, "state", "Initialized", 1);
  return undef;
}


#####################################
# neighborUpdate special: have to serialize. Forum #54574
my @nuStack;
sub
ZWDongle_NUCheck($$$$)
{
  my($hash, $fn, $msg, $isWrite) = @_;

  if($isWrite) {
    return 0 if($msg !~ m/^0048/ || $hash->{calledFromNuCheck});
    push @nuStack, "$fn/$msg";
    if(@nuStack == 1) {
      InternalTimer(gettimeofday+20, sub { # ZME timeout is 9-11s
        ZWDongle_NUCheck($hash, undef, "0048xx23", 0); # simulate fail
      }, \@nuStack, 0);
    }
    return (@nuStack > 1);

  } else {
    return if($msg !~ m/^0048..(..)$/ || $1 eq "21");      # 21: started
    shift @nuStack;
    RemoveInternalTimer(\@nuStack);
    return if(@nuStack == 0);

    my @a = split("/", $nuStack[0]);
    $hash->{calledFromNuCheck} = 1;
    ZWDongle_Write($hash, $a[0], $a[1]);
    delete($hash->{calledFromNuCheck});
    InternalTimer(gettimeofday+20, sub {
      ZWDongle_NUCheck($hash, undef, "0048xx23", 0); # simulate fail
    }, \@nuStack, 0);
  }
}

#####################################
sub
ZWDongle_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  return if(ZWDongle_NUCheck($hash, $fn, $msg, 1));

  Log3 $hash, 5, "ZWDongle_Write $msg ($fn)";
  # assemble complete message
  $msg = sprintf("%02x%s", length($msg)/2+1, $msg);

  $msg = "01$msg" . zwlib_checkSum_8($msg);
  push @{$hash->{SendStack}}, $msg;

  ZWDongle_ProcessSendStack($hash);
}

# Flags:
# - WaitForAck:  0:Written, 1:SerialACK received, 2:RF-Sent
# - SendRetries < MaxSendRetries(3, up to 7 when receiving CAN)

sub
ZWDongle_shiftSendStack($$$$;$)
{
  my ($hash, $reason, $loglevel, $txt, $cbId) = @_;
  my $ss = $hash->{SendStack};
  my $cmd = $ss->[0];

  if($cmd && $reason==0 && $cmd =~ m/^01..0013/) { # ACK for SEND_DATA
    Log3 $hash, $loglevel, "$txt, WaitForAck=>2 for $cmd"
        if($txt);
    $hash->{WaitForAck}=2;

  } else {
    return if($cbId && $cmd && $cbId ne substr($cmd,-4,2));
    shift @{$ss};
    Log3 $hash, $loglevel, "$txt, removing $cmd from dongle sendstack"
        if($txt && $cmd);
    $hash->{WaitForAck}=0;
    $hash->{SendRetries}=0;
    $hash->{MaxSendRetries}=3;
    delete($hash->{GotCAN});
  }
}

sub
ZWDongle_ProcessSendStack($)
{
  my ($hash) = @_;

  #Log3 $hash, 1, "ZWDongle_ProcessSendStack: ".@{$hash->{SendStack}}.
  #                      " items on stack, waitForAck ".$hash->{WaitForAck};

  RemoveInternalTimer($hash);

  my $ts = gettimeofday();

  if($hash->{WaitForAck}){
    if($hash->{WaitForAck} == 1 && $ts-$hash->{SendTime} >= 1) {
      Log3 $hash, 2, "ZWDongle_ProcessSendStack: no ACK, resending message ".
                      $hash->{SendStack}->[0];
      $hash->{SendRetries}++;
      $hash->{WaitForAck} = 0;

    } elsif($hash->{WaitForAck} == 2 && $ts-$hash->{SendTime} >= 2) {
      ZWDongle_shiftSendStack($hash, 1, 4, "no response from device");

    } else {
      InternalTimer($ts+1, "ZWDongle_ProcessSendStack", $hash, 0);
      return;

    }
  }

  if($hash->{SendRetries} > $hash->{MaxSendRetries}){
    ZWDongle_shiftSendStack($hash, 1, 1, "ERROR: max send retries reached");
  }

  return if(!@{$hash->{SendStack}} ||
               $hash->{WaitForAck} ||
               !DevIo_IsOpen($hash));

  my $msg = $hash->{SendStack}->[0];

  DevIo_SimpleWrite($hash, $msg, 1);
  $hash->{WaitForAck} = 1;
  $hash->{SendTime} = $ts;
  delete($hash->{GotCAN});

  InternalTimer($ts+1, "ZWDongle_ProcessSendStack", $hash, 0);
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
ZWDongle_Read($@)
{
  my ($hash, $local, $regexp) = @_;

  my $buf = (defined($local) ? $local : DevIo_SimpleRead($hash));
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  $buf = unpack('H*', $buf);
  # The dongle looses data over USB for some commands(?), and dropping the old
  # buffer after a timeout is my only idea of solving this problem.
  my $ts   = gettimeofday();
  my $data = ($hash->{ReadTime} && $ts-$hash->{ReadTime} > 1) ?
                        $buf : $hash->{PARTIAL}.$buf;
  $hash->{ReadTime} = $ts;


  #Log3 $name, 5, "ZWDongle RAW buffer: $data";

  my $msg;
  while(length($data) >= 2) {

    my $fb = substr($data, 0, 2);

    if($fb eq "06") {   # ACK
      ZWDongle_shiftSendStack($hash, 0, 5, "ACK received");
      $data = substr($data, 2);
      next;
    }

    if($fb eq "15") {   # NACK
      Log3 $name, 4, "ZWDongle_Read $name: NACK received";
      $hash->{WaitForAck} = 0;
      $hash->{SendRetries}++;
      $data = substr($data, 2);
      next;
    }

    if($fb eq "18") {   # CAN
      Log3 $name, 4, "ZWDongle_Read $name: CAN received";
      $hash->{MaxSendRetries}++ if($hash->{MaxSendRetries}<7);
      $data = substr($data, 2);
      $hash->{GotCAN} = 1;
      if(!$init_done) { # InternalTimer wont work
        $hash->{WaitForAck} = 0;
        $hash->{SendRetries}++;
        select(undef, undef, undef, 0.1);
      }
      next;
    }

    if($fb ne "01") {   # SOF
      Log3 $name, 1, "$name: SOF missing (got $fb instead of 01)";
      if(++$hash->{nrNAck} < 5){
        Log3 $name, 5, "ZWDongle_Read SOF Error -> sending NACK";
        DevIo_SimpleWrite($hash, "15", 1);         # Send NACK
      }
      $data="";
      last;
    }

    last if(length($data) < 4);

    my $len = substr($data, 2, 2);
    my $l = hex($len)*2;
    last if(length($data) < $l+4);       # Message not yet complete

    if($l < 4) {       # Bogus messages, forget the rest
      $data = "";
      last;
    }

    $msg = substr($data, 4, $l-2);
    my $rcs  = substr($data, $l+2, 2);          # Received Checksum
    $data = substr($data, $l+4);

    my $ccs = zwlib_checkSum_8("$len$msg");    # Computed Checksum
    if($rcs ne $ccs) {
      Log3 $name, 1,
           "$name: wrong checksum: received $rcs, computed $ccs for $len$msg";
      if(++$hash->{nrNAck} < 5) {
        Log3 $name, 5, "ZWDongle_Read wrong checksum -> sending NACK";
        DevIo_SimpleWrite($hash, "15", 1);
      }
      $msg = undef;
      $data="";
      next;
    }

    $hash->{nrNAck} = 0;
    next if($msg !~ m/^(..)(..)/);
    my $ztp = ($1 eq "00" ? "request" : ($1 eq "01" ? "answer" : "unknown $1"));
    my $zfi = $zw_func_id{$2} ?  $zw_func_id{$2} : "unknown $2";
    Log3 $name, 4, "ZWDongle_Read $name: rcvd $msg ($ztp $zfi), sending ACK";
    DevIo_SimpleWrite($hash, "06", 1);

    ZWDongle_shiftSendStack($hash, 1, 5, "device ack reveived", $1)
        if($msg =~ m/^0013(..)/);

    last if(defined($local) && (!defined($regexp) || ($msg =~ m/$regexp/)));
    $hash->{PARTIAL} = $data;    # Recursive call by ZWave get, Forum #37418
    ZWDongle_Parse($hash, $name, $msg) if($init_done);

    $data = $hash->{PARTIAL};
    $msg = undef;
  }

  $hash->{PARTIAL} = $data;

  # trigger sending of next message
  ZWDongle_ProcessSendStack($hash) if(length($data) == 0);

  return $msg if(defined($local));
  return undef;
}

#####################################
# This is a direct read for commands like get
sub
ZWDongle_ReadAnswer($$$)
{
  my ($hash, $arg, $regexp) = @_;
  Log3 $hash, 4, "ZWDongle_ReadAnswer arg:$arg regexp:".($regexp ? $regexp:"");
  return ("No FD (dummy device?)", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));
  my $to = ($hash->{RA_Timeout} ? $hash->{RA_Timeout} : 1);

  for(;;) {

    my $buf;
    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      if(length($buf) == 0) {
        if($hash->{GotCAN}) {
          ZWDongle_ProcessSendStack($hash);
          next;
        }
        return ("Timeout reading answer for get $arg", undef);
      }

    } else {
      if(!$hash->{FD}) {
        Log3 $hash, 1, "ZWDongle_ReadAnswer: device lost";
        return ("Device lost when reading answer for get $arg", undef);
      }

      my $rin = '';
      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        my $err = $!;
        Log3 $hash, 5, "ZWDongle_ReadAnswer: nfound < 0 / err:$err";
        next if ($err == EAGAIN() || $err == EINTR() || $err == 0);
        DevIo_Disconnected($hash);
        return("ZWDongle_ReadAnswer $arg: $err", undef);
      }

      if($nfound == 0){
        Log3 $hash, 5, "ZWDongle_ReadAnswer: select timeout";
        if($hash->{GotCAN}) {
          ZWDongle_ProcessSendStack($hash);
          next;
        }
        return ("Timeout reading answer for get $arg", undef);
      }

      $buf = DevIo_SimpleRead($hash);
      if(!defined($buf)){
        Log3 $hash, 1,"ZWDongle_ReadAnswer: no data read";
        return ("No data", undef);
      }
    }

    my $ret = ZWDongle_Read($hash, $buf, $regexp);
    if(defined($ret)){
      Log3 $hash, 4, "ZWDongle_ReadAnswer for $arg: $ret";
      return (undef, $ret);
    }
  }
}

sub
ZWDongle_Parse($$$)
{
  my ($hash, $name, $rmsg) = @_;

  if(!defined($hash->{STATE}) ||
     ReadingsVal($name, "state", "") ne "Initialized"){
    Log3 $hash, 4,"ZWDongle_Parse $rmsg: dongle not yet initialized";
    return;
  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;

  $hash->{SendTime}--       # Retry sending after a "real" msg from the dongle
        if($hash->{GotCAN} && $rmsg !~ m/^(0113|0013)/);

  my %addvals = (RAWMSG => $rmsg);

  ZWDongle_NUCheck($hash, undef, $rmsg, 0);
  Dispatch($hash, $rmsg, \%addvals);
}

#####################################
sub
ZWDongle_Attr($$$$)
{
  my ($cmd, $name, $attr, $value) = @_;
  my $hash = $defs{$name};
  $attr = "" if(!$attr);

  if($attr eq "disable") {
    if($cmd eq "set" && ($value || !defined($value))) {
      DevIo_CloseDev($hash) if(!AttrVal($name,"dummy",undef));
      readingsSingleUpdate($hash, "state", "disabled", 1);

    } else {
      if(AttrVal($name,"dummy",undef)) {
        readingsSingleUpdate($hash, "state", "dummy", 1);
        return;
      }
      DevIo_OpenDev($hash, 0, "ZWDongle_DoInit");

    }

  } elsif($attr eq "homeId" && $cmd eq "set") {
    $hash->{homeId} = $value;

  } elsif($attr eq "networkKey" && $cmd eq "set") {
    if(!$value || $value !~ m/^[0-9A-F]{32}$/i) {
      return "attr $name networkKey: not a hex string with a length of 32";
    }
    return;

  } elsif($attr eq "showSetInState") {
    $hash->{showSetInState} = ($cmd eq "set" ? (defined($value) ? $value:1) :0);

  }

  return undef;

}

#####################################
sub
ZWDongle_Ready($)
{
  my ($hash) = @_;

  return undef if (IsDisabled($hash->{NAME}));

  return DevIo_OpenDev($hash, 1, "ZWDongle_DoInit")
            if(ReadingsVal($hash->{NAME}, "state","") eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  if($po) {
    my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
    if(!defined($InBytes)) {
      DevIo_Disconnected($hash);
      return 0;
    }
    return ($InBytes>0);
  }
  return 0;
}


1;

=pod
=item summary    connection to standard ZWave controller
=item summary_DE Anbindung von standard ZWave Controller
=begin html

<a name="ZWDongle"></a>
<h3>ZWDongle</h3>
<ul>
  This module serves a ZWave dongle, which is attached via USB or TCP/IP, and
  enables the use of ZWave devices (see also the <a href="#ZWave">ZWave</a>
  module). It was tested wit a Goodway WD6001, but since the protocol is
  standardized, it should work with other devices too. A notable exception is
  the USB device from Merten.
  <br><br>
  <a name="ZWDongledefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; ZWDongle &lt;device&gt;</code>
  <br>
  <br>
  Upon initial connection the module will get the homeId of the attached
  device. Since the DevIo module is used to open the device, you can also use
  devices connected via  TCP/IP. See <a href="#CULdefine">this</a> paragraph on
  device naming details.
  <br>
  Example:
  <ul>
    <code>define zwdongle_1 ZWDongle /dev/cu.PL2303-000014FA@115200</code><br>
  </ul>
  </ul>
  <br>

  <a name="ZWDongleset"></a>
  <b>Set</b>
  <ul>

  <li>addNode on|onNw|onSec|onNwSec|off<br>
    Activate (or deactivate) inclusion mode. The controller (i.e. the dongle)
    will accept inclusion (i.e. pairing/learning) requests only while in this
    mode. After activating inclusion mode usually you have to press a switch
    three times within 1.5 seconds on the node to be included into the network
    of the controller. If autocreate is active, a fhem device will be created
    after inclusion. "on" activates standard inclusion. "onNw" activates network
    wide inclusion (only SDK 4.5-4.9, SDK 6.x and above).<br>
    If onSec/onNwSec is specified, the ZWDongle networkKey ist set, and the
    device supports the SECURITY class, then a secure inclusion is attempted.
    </li>

  <li>backupCreate 16k|32k|64k|128k|256k<br>
    read out the NVRAM of the ZWDongle, and store it in a file called
    &lt;ZWDongle_Name&gt;.bin in the modpath folder.  Since the size of the
    NVRAM is currently unknown to FHEM, you have to specify the size. The
    ZWave.me ZME_UZB1 Stick seems to have 256k of NVRAM. Note: writing the file
    takes some time, usually about 10s for each 64k (and significantly longer
    on Windows), and FHEM is blocked during this time.
    </li>

  <li>backupRestore<br>
    Restore the file created by backupCreate. Restoring the file takes about
    the same time as saving it, and FHEM is blocked during this time.
    Note / Important: this function is not yet tested for older devices using
    the MEMORY functions.
    </li>

  <li>controllerChange on|stop|stopFailed<br>
    Add a controller to the current network and transfer role as primary to it.
    Invoking controller is converted to secondary.<br>
    stop: stop controllerChange<br>
    stopFailed: stop controllerChange and report an error
    </li>

  <li>createNewPrimary on|stop|stopFailed<br>
    Add a controller to the current network as a replacement for an old
    primary. Command can be invoked only by a secondary configured as basic
    SUC<br>
    stop: stop createNewPrimary<br>
    stopFailed: stop createNewPrimary and report an error
    </li>

  <li>createNode &lt;device&gt;<br>
      createNodeSec &lt;device&gt;<br>
    Request the class information for the specified node, and create
    a FHEM device upon reception of the answer. Used to create FHEM devices for
    nodes included with another software or if the fhem.cfg got lost. For the
    node id see the get nodeList command below.  Note: the node must be "alive",
    i.e. for battery based devices you have to press the "wakeup" button 1-2
    seconds before entering this command in FHEM.<br>
    &lt;device&gt; is either device name or decimal nodeId.<br>
    createNodeSec assumes a secure inclusion, see the comments for "addNode
    onSec" for details.
    </li>

  <li>factoryReset yes<br>
    Reset controller to default state.
    Erase all node and routing infos, assign a new random homeId.
    To control a device it must be re-included and re-configured.<br>
    !Use this with care AND only if You know what You do!<br>
    Note: the corresponding FHEM devices have to be deleted manually.
    </li>

  <li>learnMode on|onNw|disable<br>
    Add or remove controller to/from an other network.
    Assign a homeId, nodeId and receive/store nodeList and routing infos.
    </li>

  <li>removeFailedNode &lt;device&gt;<br>
    Remove non-responding node -that must be on the failed node list-
    from the routing table in controller. Instead, always use removeNode if
    possible. Note: the corresponding FHEM device have to be deleted 
    manually.<br>
    &lt;device&gt; is either device name or decimal nodeId.
    </li>

  <li>removeNode onNw|on|off<br>
    Activate (or deactivate) exclusion mode. "on" activates standard exclusion.
    "onNw" activates network wide exclusion (only SDK 4.5-4.9, SDK 6.x and
    above).  Note: the corresponding FHEM device have to be deleted
    manually.
    </li>

  <li>reopen<br>
    First close and then open the device. Used for debugging purposes.
    </li>

  <li>replaceFailedNode &lt;device&gt;<br>
    Replace a non-responding node with a new one. The non-responding node
    must be on the failed node list.<br>
    &lt;device&gt; is either device name or decimal nodeId.
    </li>

  <li>routeFor &lt;device&gt; &lt;hop1&gt; &lt;hop2&gt; &lt;hop3&gt;
               &lt;hop4&gt; &lt;speed&gt;<br>
    set priority routing for &ltdevice&gt. &ltdevice&gt and &lt;hopN&gt are
    either device name or decimal nodeId or 0 for unused.<br>
    &lt;speed&gt;: 1=9,6kbps; 2=40kbps; 3=100kbps
    </li>

  <li>sendNIF &lt;device&gt;<br>
    Send NIF to the specified &lt;device&g.
    &lt;device&gt; is either device name or decimal nodeId.
    </li>

  <li>sucNodeId &lt;decimal nodeId&gt; &lt;sucState&gt;
                &lt;capabilities&gt;<br>
    Configure a controller node to be a SUC/SIS or not.<br>
    &lt;nodeId&gt;: decimal nodeId to be SUC/SIS<br>
    &lt;sucState&gt;: 0 = deactivate; 1 = activate<br>
    &lt;capabilities&gt;: 0 = basic SUC; 1 = SIS
    </li>

  <li>sucRequestUpdate &lt;decimal nodeId of SUC/SIS&gt;<br>
    Request network updates from SUC/SIS. Primary do not need it.
    </li>

  <li>sucSendNodeId &lt;decimal nodeId&gt;<br>
    Send SUC/SIS nodeId to the specified decimal controller nodeId.
    </li>

  </ul>
  <br>

  <a name="ZWDongleget"></a>
  <b>Get</b>
  <ul>
  <li>homeId<br>
    return the six hex-digit homeId of the controller.
    </li>

  <li>isFailedNode &lt;device&gt;<br>
    return if a node is stored in the failed node list. &lt;device&gt; is
    either device name or decimal nodeId.
    </li>

  <li>caps, ctrlCaps, version<br>
    return different controller specific information. Needed by developers
    only.
    </li>

  <li>neighborList [excludeDead] [onlyRep] &lt;device&gt;<br>
    return neighborList of the &lt;device&gt;.<br>
    &lt;device&gt; is either device name or decimal nodeId.<br>
    With onlyRep the result will include only nodes with repeater
    functionality.
    </li>

  <li>nodeInfo &lt;device&gt;<br>
    return node specific information. &lt;device&gt; is either device name or 
    decimal nodeId.
    </li>

  <li>nodeList<br>
    return the list of included nodenames or UNKNOWN_id (decimal id), if there
    is no corresponding device in FHEM. Can be used to recreate FHEM-nodes with
    the createNode command.
    </li>

  <li>random &lt;N&gt;<br>
    request &lt;N&gt; random bytes from the controller.
    </li>

  <li>raw &lt;hex&gt;<br>
    Send raw data &lt;hex&gt; to the controller. Developer only.
    </li>

  <li>routeFor &lt;device&gt;<br>
    request priority routing for &lt;device&gt;. &lt;device&gt; is either 
    device name or decimal nodeId.</li>

  <li>sucNodeId<br>
    return the currently registered decimal SUC nodeId.
    </li>

  </ul>
  <br>

  <a name="ZWDongleattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#dummy">dummy</a></li>
    <li><a href="#do_not_notify">do_not_notify</a></li>
    <li><a href="#model">model</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a name="helpSites">helpSites</a><br>
      Comma separated list of Help Sites to get device pictures from or to
      show a link to in the detailed window. Valid values are pepper
      and alliance.
      </li>
    <li><a name="homeId">homeId</a><br>
      Stores the homeId of the dongle. Is a workaround for some buggy dongles,
      wich sometimes report a wrong/nonexisten homeId (Forum #35126)</li>
    <li><a name="networkKey">networkKey</a><br>
      Needed for secure inclusion, hex string with length of 32
      </li>
    <li><a name="neighborListPos">neighborListPos</a><br>
      Used by the "Show neighbor map" function in the FHEMWEB ZWDongle detail
      screen to store the position of the box.
      </li>
    <li><a name="neighborListFmt">neighborListFmt</a><br>
      Used by the "Show neighbor map" function in the FHEMWEB ZWDongle detail
      screen. The value is a perl hash, specifiying the values for the keys
      txt, img and title. In the value each word is replaced by the
      corresponding Internal, Reading or Attribute of the device, if there is
      one to replace. Default is
      <ul><code>
        { txt=>"NAME", img=>"IMAGE", title=>"Time to ack: timeToAck" }
      </code></ul>
      </li>
    <li><a name="showSetInState">showSetInState</a><br>
      If the attribute is set to 1, and a user issues a set command to a ZWave
      device, then the state of the ZWave device will be changed to
      set_&lt;cmd&gt; first, and after the ACK from the device is received, to
      &lt;cmd&gt;. E.g.: Issuing the command on changes the state first to
      set_on, and after the device ack is received, to on.  This is analoguos
      to the CUL_HM module.  Default for this attribute is 0.
      </li>
      
  </ul>
  <br>

  <a name="ZWDongleevents"></a>
  <b>Generated events:</b>
  <ul>

  <br><b>General</b>
  <li>UNDEFINED ZWave_${type6}_$id ZWave $homeId $id $classes</li>

  <li>ZW_APPLICATION_UPDATE addDone $nodeId</li>

  <li>ZW_APPLICATION_UPDATE deleteDone $nodeId</li>

  <li>ZW_APPLICATION_UPDATE sudId $nodeId</li>

  <br><b>addNode</b>
  <li>ZW_ADD_NODE_TO_NETWORK [learnReady|nodeFound|slave|controller|
                              done|failed]</li>

  <br><b>controllerChange</b>
  <li>ZW_CONTROLLER_CHANGE [learnReady|nodeFound|controller|done|failed]</li>

  <br><b>createNewPrimary</b>
  <li>ZW_CREATE_NEW_PRIMARY [learnReady|nodeFound|controller|done|failed]</li>

  <br><b>factoryReset</b>
  <li>ZW_SET_DEFAULT [done]</li>

  <br><b>learnMode</b>
  <li>ZW_SET_LEARN_MODE [started|done|failed|deleted]</li>

  <br><b>neighborUpdate</b>
  <li>ZW_REQUEST_NODE_NEIGHBOR_UPDATE [started|done|failed]</li>

  <br><b>removeFailedNode</b>
  <li>ZW_REMOVE_FAILED_NODE_ID
           [failedNodeRemoveStarted|notPrimaryController|noCallbackFunction|
            failedNodeNotFound|failedNodeRemoveProcessBusy|
            failedNodeRemoveFail|nodeOk|nodeRemoved|nodeNotRemoved]</li>

  <br><b>removeNode</b>
  <li>ZW_REMOVE_NODE_FROM_NETWORK
                        [learnReady|nodeFound|slave|controller|done|failed]</li>

  <br><b>replaceFailedNode</b>
  <li>ZW_REPLACE_FAILED_NODE
           [failedNodeRemoveStarted|notPrimaryController|noCallbackFunction|
            failedNodeNotFound|failedNodeRemoveProcessBusy|
            failedNodeRemoveFail|nodeOk|failedNodeReplace|
            failedNodeReplaceDone|failedNodeRemoveFailed]</li>

  <br><b>routeFor</b>
  <li>ZW_SET_PRIORITY_ROUTE node $nodeId result $nr</li>

  <br><b>sucNetworkUpdate</b>
  <li>ZW_REQUEST_NETWORK_UPDATE [started|selfOrNoSUC|done|abort|wait|diabled|
                                 overflow]</li>

  <br><b>sucNodeId</b>
  <li>ZW_SET_SUC_NODE_ID [ok|failed|callbackSucceeded|callbackFailed]</li>

  <br><b>sucRouteAdd</b>
  <li>ZW_ASSIGN_SUC_RETURN_ROUTE [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>

  <br><b>sucRouteDel</b>
  <li>ZW_DELETE_SUC_RETURN_ROUTE [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>

  <br><b>sucSendNodeId</b>
  <li>ZW_SEND_SUC_ID [started|alreadyActive|transmitOk|
                                  transmitNoAck|transmitFail|transmitNotIdle|
                                  transmitNoRoute]</li>
  </ul>
</ul>


=end html
=cut

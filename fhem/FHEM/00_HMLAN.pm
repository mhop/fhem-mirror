##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub HMLAN_Parse($$);
sub HMLAN_Read($);
sub HMLAN_Write($$$);
sub HMLAN_ReadAnswer($$$);
sub HMLAN_uptime($);
sub HMLAN_secSince2000();

sub HMLAN_SimpleWrite(@);

my %sets = (
  "hmPairForSec" => "HomeMatic",
  "hmPairSerial" => "HomeMatic",
);

sub
HMLAN_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "HMLAN_Read";
  $hash->{WriteFn} = "HMLAN_Write";
  $hash->{ReadyFn} = "HMLAN_Ready";
  $hash->{SetFn}   = "HMLAN_Set";
  $hash->{Clients} = ":CUL_HM:";
  my %mc = (
    "1:CUL_HM" => "^A......................",
  );
  $hash->{MatchList} = \%mc;

# Normal devices
  $hash->{DefFn}   = "HMLAN_Define";
  $hash->{UndefFn} = "HMLAN_Undef";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 " .
                     "loglevel:0,1,2,3,4,5,6 addvaltrigger " . 
                     "hmId hmKey " .
					 "hmProtocolEvents:0_off,1_dump,2_dumpFull,3_dumpTrigger";
}

#####################################
sub
HMLAN_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> HMLAN ip[:port]";
    Log 2, $msg;
    return $msg;
  }
  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  $dev .= ":1000" if($dev !~ m/:/ && $dev ne "none" && $dev !~ m/\@/);
  $attr{$name}{hmId} = sprintf("%06X", time() % 0xffffff); # Will be overwritten

  if($dev eq "none") {
    Log 1, "$name device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "HMLAN_DoInit");
  return $ret;
}


#####################################
sub
HMLAN_Undef($$)
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

  DevIo_CloseDev($hash); 
  return undef;
}

#####################################
sub
HMLAN_RemoveHMPair($)
{
  my $hash = shift;
  delete($hash->{hmPair});
}


#####################################
sub
HMLAN_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set HMLAN\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $name = shift @a;
  my $type = shift @a;
  my $arg = join("", @a);
  my $ll = GetLogLevel($name,3);

  if($type eq "hmPairForSec") { ####################################
    return "Usage: set $name hmPairForSec <seconds_active>"
        if(!$arg || $arg !~ m/^\d+$/);
    $hash->{hmPair} = 1;
    InternalTimer(gettimeofday()+$arg, "HMLAN_RemoveHMPair", $hash, 1);

  } elsif($type eq "hmPairSerial") { ################################
    return "Usage: set $name hmPairSerial <10-character-serialnumber>"
        if(!$arg || $arg !~ m/^.{10}$/);

    my $id = AttrVal($hash->{NAME}, "hmId", "123456");
    $hash->{HM_CMDNR} = $hash->{HM_CMDNR} ? ($hash->{HM_CMDNR}+1)%256 : 1;

    HMLAN_Write($hash, undef, sprintf("As15%02X8401%s000000010A%s",
                    $hash->{HM_CMDNR}, $id, unpack('H*', $arg)));
    $hash->{hmPairSerial} = $arg;

  }
  return undef;
}


#####################################
# This is a direct read for commands like get
sub
HMLAN_ReadAnswer($$$)
{
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
      return("HMLAN_ReadAnswer $arg: $err", undef);
    }
    return ("Timeout reading answer for get $arg", undef)
      if($nfound == 0);
    $buf = DevIo_SimpleRead($hash);
    return ("No data", undef) if(!defined($buf));

    if($buf) {
      Log 5, "HMLAN/RAW (ReadAnswer): $buf";
      $mdata .= $buf;
    }
    if($mdata =~ m/\r\n/) {
      if($regexp && $mdata !~ m/$regexp/) {
        HMLAN_Parse($hash, $mdata);
      } else {
        return (undef, $mdata)
      }
    }
  }
}

#####################################
sub
HMLAN_Write($$$)
{
  my ($hash,$fn,$msg) = @_;

  my $dst = substr($msg, 16, 6);
  if(hex(substr($msg, 6, 2))&0x01) {   # wakeup flag set, shake actor awake
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
    HMLAN_SimpleWrite($hash, "-$dst");
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
    HMLAN_SimpleWrite($hash, "+$dst,00,00,");
  }
  my $tm = int(gettimeofday()*1000) % 0xffffffff;
  $msg = sprintf("S%08X,00,00000000,01,%08X,%s",
                $tm, $tm, substr($msg, 4));
  HMLAN_SimpleWrite($hash, $msg);

  # Avoid problems with structure set
  # TODO: rewrite it to use a queue+internaltimer like the CUL
  select(undef, undef, undef, 0.01); # needed for structure set by meesus. 
  # may not be needed at all if acks are handled properly
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
HMLAN_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));
  my $name = $hash->{NAME};

  my $hmdata = $hash->{PARTIAL};
  Log 5, "HMLAN/RAW: $hmdata/$buf";
  $hmdata .= $buf;

  while($hmdata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$hmdata) = split("\n", $hmdata, 2);
    $rmsg =~ s/\r//;
    HMLAN_Parse($hash, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $hmdata;
}

sub
HMLAN_uptime($)
{
  my $msec = shift;

  $msec = hex($msec);
  my $sec = int($msec/1000);
  return sprintf("%03d %02d:%02d:%02d.%03d",
                  int($msec/86400000), int($sec/3600),
                  int(($sec%3600)/60), $sec%60, $msec % 1000);
}

sub
HMLAN_Parse($$)
{
  my ($hash, $rmsg) = @_;
  my $name = $hash->{NAME};
  my $ll5 = GetLogLevel($name,5);
  my ($src, $status, $msec, $d2, $rssi, $msg);

  my $dmsg = $rmsg;

  Log $ll5, "HMLAN_Parse: $name $rmsg";
  if($rmsg =~ m/^E(......),(....),(........),(..),(....),(.*)/) {
    ($src, $status, $msec, $d2, $rssi, $msg) =
    ($1,   $2,      $3,    $4,  $5,    $6);
    $dmsg = sprintf("A%02X%s", length($msg)/2, uc($msg));
    $hash->{uptime} = HMLAN_uptime($msec);

  } elsif($rmsg =~ m/^R(........),(....),(........),(..),(....),(.*)/) {
    ($src, $status, $msec, $d2, $rssi, $msg) =
    ($1,   $2,      $3,    $4,  $5,    $6);

    $dmsg = sprintf("A%02X%s", length($msg)/2, uc($msg));
    $dmsg .= "NACK" if($status !~ m/00(01|02|21)/);	
	
    $hash->{uptime} = HMLAN_uptime($msec);

  } elsif($rmsg =~
       m/^HHM-LAN-IF,(....),(..........),(......),(......),(........),(....)/) {
    my ($vers,    $serno, $d1, $owner, $msec, $d2) =
       (hex($1), $2,     $3,  $4,     $5,    $6);
    $hash->{serialNr} = $serno;
    $hash->{firmware} = sprintf("%d.%d", ($vers>>12)&0xf, $vers & 0xffff);
    $hash->{owner} = $owner;
    $hash->{uptime} = HMLAN_uptime($msec);
    my $myId = AttrVal($name, "hmId", $owner);
    if(lc($owner) ne lc($myId) && !AttrVal($name, "dummy", 0)) {
      Log 1, "HMLAN setting owner to $myId from $owner";
      HMLAN_SimpleWrite($hash, "A$myId");
    }
    return;

  } elsif($rmsg =~ m/^I00.*/) {
    # Ack from the HMLAN
    return;

  } else {
    Log $ll5, "$name Unknown msg >$rmsg<";
    return;

  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;
  my %addvals = (RAWMSG => $rmsg);
  if(defined($rssi)) {
    $rssi = hex($rssi)-65536;
    $hash->{RSSI} = $rssi;
    $addvals{RSSI} = $rssi;
  }
  Dispatch($hash, $dmsg, \%addvals);
}


#####################################
sub
HMLAN_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "HMLAN_DoInit");
}

########################
sub
HMLAN_SimpleWrite(@)
{
  my ($hash, $msg, $nonl) = @_;
  my $name = $hash->{NAME};
  return if(!$hash || AttrVal($hash->{NAME}, "dummy", undef));

  select(undef, undef, undef, 0.01);
  Log GetLogLevel($name,5), "SW: $msg";
  
  $msg .= "\r\n" unless($nonl);
  syswrite($hash->{TCPDev}, $msg)     if($hash->{TCPDev});
}

########################
sub
HMLAN_DoInit($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $id  = AttrVal($name, "hmId", undef);
  my $key = AttrVal($name, "hmKey", "");        # 36(!) hex digits

  my $s2000 = sprintf("%02X", HMLAN_secSince2000());

  HMLAN_SimpleWrite($hash, "A$id") if($id);
  HMLAN_SimpleWrite($hash, "C");
  HMLAN_SimpleWrite($hash, "Y01,01,$key");
  HMLAN_SimpleWrite($hash, "Y02,00,");
  HMLAN_SimpleWrite($hash, "Y03,00,");
  HMLAN_SimpleWrite($hash, "Y03,00,");
  HMLAN_SimpleWrite($hash, "T$s2000,04,00,00000000");

  InternalTimer(gettimeofday()+25, "HMLAN_KeepAlive", $hash, 0);
  return undef;
}

#####################################
sub
HMLAN_KeepAlive($)
{
  my $hash = shift;
  return if(!$hash->{FD});
  HMLAN_SimpleWrite($hash, "K");
  InternalTimer(gettimeofday()+25, "HMLAN_KeepAlive", $hash, 1);
}

sub
HMLAN_secSince2000()
{
  # Calculate the local time in seconds from 2000.
  my $t = time();
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
  $t -= 946684800; # seconds between 01.01.2000, 00:00 and THE EPOCH (1970)
  $t -= 7200;   # HM Special
  $t += fhemTzOffset($t);
  return $t;
}

1;

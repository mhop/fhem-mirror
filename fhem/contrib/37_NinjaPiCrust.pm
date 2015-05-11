# $Id: $

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

#use JSON;

##########################
# This block is only needed when FileLog is checked outside fhem
#
sub Log3($$$);
sub Log($$);
sub RemoveInternalTimer($);
use vars qw(%attr);
use vars qw(%defs);
use vars qw(%modules);
use vars qw($readingFnAttributes);
use vars qw($reread_active);

##########################


sub NinjaPiCrust_Attr(@);
sub NinjaPiCrust_Clear($);
sub NinjaPiCrust_HandleWriteQueue($);
sub NinjaPiCrust_Parse($$$$);
sub NinjaPiCrust_Read($);
sub NinjaPiCrust_ReadAnswer($$$$);
sub NinjaPiCrust_Ready($);
sub NinjaPiCrust_Write($$);

sub NinjaPiCrust_SimpleWrite(@);

my $dl = 4; # debug level for log - and yes, it's dirty..

my $clientsNinjaPiCrust = ":NINJA:";

my %matchListNinjaPiCrust = (
    "1:NINJA"          => "^.+"
);

my %RxListNinjaPiCrust = (
        "HX2272" => "Or",
        "FS20" => "Or",
        "LaCrosse"      => "Fr01",
);

sub
NinjaPiCrust_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{ReadFn}  = "NinjaPiCrust_Read";
  $hash->{WriteFn} = "NinjaPiCrust_Write";
  $hash->{ReadyFn} = "NinjaPiCrust_Ready";

# Normal devices
  $hash->{DefFn}        = "NinjaPiCrust_Define";
  $hash->{FingerprintFn}   = "NinjaPiCrust_Fingerprint";
  $hash->{UndefFn}      = "NinjaPiCrust_Undef";
  $hash->{GetFn}        = "NinjaPiCrust_Get";
  $hash->{SetFn}        = "NinjaPiCrust_Set";
  $hash->{AttrFn}       = "NinjaPiCrust_Attr";
  $hash->{AttrList} = "Clients MatchList"
                      ." DebounceTime BeepLong BeepShort BeepDelay"
                      ." tune " . join(" ", map { "tune_$_" } keys %RxListNinjaPiCrust)
                      ." preferSketchReset:0,1 resetPulseWidth"
                      ." $readingFnAttributes";

  $hash->{ShutdownFn} = "NinjaPiCrust_Shutdown";

}
sub
NinjaPiCrust_Fingerprint($$)
{
}

#####################################
sub
NinjaPiCrust_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a != 3) {
    my $msg = "wrong syntax: define <name> NinjaPiCrust {devicename[\@baudrate] ".
                        "| devicename\@directio}";
    Log3 undef, $dl, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];

  my $dev = $a[2];
  $dev .= "\@9600" if( $dev !~ m/\@/ );

  $hash->{Clients} = $clientsNinjaPiCrust;
  $hash->{MatchList} = \%matchListNinjaPiCrust;

  $hash->{DeviceName} = $dev;

  my $ret = DevIo_OpenDev($hash, 0, "NinjaPiCrust_DoInit");
  return $ret;
}

#####################################
sub
NinjaPiCrust_Undef($$)
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

  NinjaPiCrust_Shutdown($hash);
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub
NinjaPiCrust_Shutdown($)
{
  my ($hash) = @_;
  ###NinjaPiCrust_SimpleWrite($hash, "X00");
  return undef;
}

#sub
#NinjaPiCrust_RemoveLaCrossePair($)
#{
#  my $hash = shift;
#  delete($hash->{LaCrossePair});
#}

use JSON;

sub
NinjaPiCrust_ParseJSON($)
{
  my ($str) = @_;
  #Log 0, "NinjaPiCrust_ParseJSON('$str')";
  return decode_json $str;
}

sub
NinjaPiCrust_encode($$$$)
{
  my ($g,$v,$d,$da) = @_;
  return '{"DEVICE":[{"G":"'.$g.'","V":'.$v.',"D":'.$d.',"DA":"'.$da.'"}]}';  
}

#####################################
sub
NinjaPiCrust_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd = shift @a;
  my $arg = join(" ", @a);


  #my $list = "led:on,off led-on-for-timer reset LaCrossePairForSec setReceiverMode:LaCrosse,HX2272,FS20";
  my $list = "eyes:rgb led:on,off,red,green,blue,yellow,cyan,magenta";
  return $list if( $cmd eq '?' || $cmd eq '');

  my %rgb = (
      on      => "FFFFFF",
      off     => "000000",
      red     => "FF0000",
      green   => "00FF00",
      blue    => "0000FF",
      cyan    => "00FFFF",
      magenta => "FF00FF",
      yellow  => "FFFF00"
  );

  if($cmd eq "raw") {
    Log3 $name, 4, "set $name $cmd $arg";
    NinjaPiCrust_SimpleWrite($hash, $arg);

  } elsif ($cmd =~ m/^eyes$/i) {
    return "Unknown argument $cmd, choose one of $list" 
	if($arg !~ m/^(on|off|red|green|blue|yellow|cyan|magenta|[0-9a-f]{6})$/i);

    Log3 $name, 4, "set $name $cmd $arg";
    NinjaPiCrust_Write($hash, (exists $rgb{$arg}) ? NinjaPiCrust_encode("0",0,1007,$rgb{$arg}) :
                                                    NinjaPiCrust_encode("0",0,1007,$arg) );

  } elsif ($cmd =~ m/^led$/i) {
    return "Unknown argument $cmd, choose one of $list"
        if($arg !~ m/^(on|off|red|green|blue|yellow|cyan|magenta|[0-9a-f]{6})$/i);

    Log3 $name, 4, "set $name $cmd $arg";
    NinjaPiCrust_Write($hash, (exists $rgb{$arg}) ? NinjaPiCrust_encode("0",0,999,$rgb{$arg}) :
                                                    NinjaPiCrust_encode("0",0,999,$arg));

  } elsif ($cmd =~ m/led-on-for-timer/i) {
    return "Unknown argument $cmd, choose one of $list" if($arg !~ m/^[0-9]+$/i);

    #remove timer if there is one active
    if($modules{NinjaPiCrust}{ldata}{$name}) {
      CommandDelete(undef, $name . "_timer");
      delete $modules{NinjaPiCrust}{ldata}{$name};
    }
    Log3 $name, 4, "set $name on";
    #TODO: NinjaPiCrust_Write($hash, "l" . "1");

    my $to = sprintf("%02d:%02d:%02d", $arg/3600, ($arg%3600)/60, $arg%60);
    $modules{NinjaPiCrust}{ldata}{$name} = $to;
    Log3 $name, 4, "Follow: +$to setstate $name off";
    CommandDefine(undef, $name."_timer at +$to {fhem(\"set $name led" ." off\")}");

  } elsif ($cmd =~ m/reset/i) {
   
   NinjaPiCrust_ResetDevice($hash);
    
  } else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

#####################################
sub
NinjaPiCrust_Get($@)
{
  my ($hash, $name, $cmd, @msg ) = @_;
  my $arg = join(" ", @msg);

  #my $list = "devices:noArg initNinjaPiCrust:noArg RFMconfig:noArg updateAvailRam:noArg raw";
  my $list = "version";

  if ($cmd eq "raw" ) {
    return "raw => 01" if($arg =~ m/^Ir/);  ## Needed for CUL_IR usage (IR-Receive is always on for NinjaPiCrusts

  } 
  elsif ($cmd eq "version" ) {
    NinjaPiCrust_SimpleWrite($hash, NinjaPiCrust_encode("0",0,1003,"VNO") );
  
  } 
  #elsif ($cmd eq "updateAvailRam" ) {
  #  NinjaPiCrust_SimpleWrite($hash, "m");
  #
  #}
  else {
    return "Unknown argument $cmd, choose one of ".$list;
  }

  return undef;
}

sub
NinjaPiCrust_Clear($)
{
  my $hash = shift;

  return undef; #TODO: do we need this?
  # Clear the pipe
  $hash->{RA_Timeout} = 1;
  for(;;) {
    my ($err, undef) = NinjaPiCrust_ReadAnswer($hash, "Clear", 0, undef);
    last if($err && $err =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});
}

#####################################
sub
NinjaPiCrust_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  my $val;

  NinjaPiCrust_Clear($hash);

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
NinjaPiCrust_ReadAnswer($$$$)
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
        return("NinjaPiCrust_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if($buf) {
      #Log3 $hash->{NAME}, 5, "NinjaPiCrust/RAW (ReadAnswer): $buf";
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
NinjaPiCrust_XmitLimitCheck($$)
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

  if(@b > 163) {          # 163 comes from fs20. todo: verify if correct for NinjaPiCrust modulation

    my $name = $hash->{NAME};
    Log3 $name, 2, "NinjaPiCrust TRANSMIT LIMIT EXCEEDED";
    DoTrigger($name, "TRANSMIT LIMIT EXCEEDED");

  } else {

    push(@b, $now);

  }
  $hash->{XMIT_TIME} = \@b;
  $hash->{NR_CMD_LAST_H} = int(@b);
}

#####################################
sub
NinjaPiCrust_Write($$)
{
        my ($hash, $cmd, $msg) = @_;
        my $name = $hash->{NAME};
        my $arg = $cmd;
        #TODO: $arg .= " " . $msg if(defined($msg));

        #Modify command for CUL_IR
        #$arg =~ s/^\s+|\s+$//g;
        #$arg =~ s/^Is/I/i;  #SendIR command is "I" not "Is" for NinjaPiCrust devices

  Log3 $name, 5, "$name sending $arg";

  NinjaPiCrust_AddQueue($hash, $arg);
  #TODO: NinjaPiCrust_SimpleWrite($hash, $msg);
}

sub
NinjaPiCrust_SendFromQueue($$)
{
  my ($hash, $bstring) = @_;
  my $name = $hash->{NAME};
  my $to = 0.05;

  if($bstring ne "") {
    my $sp = AttrVal($name, "sendpool", undef);
    if($sp) {   # Is one of the NinjaPiCrust-fellows sending data?
      my @fellows = split(",", $sp);
      foreach my $f (@fellows) {
        if($f ne $name &&
           $defs{$f} &&
           $defs{$f}{QUEUE} &&
           $defs{$f}{QUEUE}->[0] ne "")
          {
            unshift(@{$hash->{QUEUE}}, "");
            InternalTimer(gettimeofday()+$to, "NinjaPiCrust_HandleWriteQueue", $hash, 0);
            return;
          }
      }
    }

    NinjaPiCrust_XmitLimitCheck($hash,$bstring);
    NinjaPiCrust_SimpleWrite($hash, $bstring);
  }

  InternalTimer(gettimeofday()+$to, "NinjaPiCrust_HandleWriteQueue", $hash, 0);
}

sub
NinjaPiCrust_AddQueue($$)
{
  my ($hash, $bstring) = @_;
  if(!$hash->{QUEUE}) {
    $hash->{QUEUE} = [ $bstring ];
    NinjaPiCrust_SendFromQueue($hash, $bstring);

  } else {
    push(@{$hash->{QUEUE}}, $bstring);
  }
}

#####################################
sub
NinjaPiCrust_HandleWriteQueue($)
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
      NinjaPiCrust_HandleWriteQueue($hash);
    } else {
      NinjaPiCrust_SendFromQueue($hash, $bstring);
    }
  }
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
NinjaPiCrust_Read($)
{
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  my $name = $hash->{NAME};

  my $pandata = $hash->{PARTIAL};
  #Log3 $name, $dl+2, "NinjaPiCrust/RAW: $pandata/$buf";
  $pandata .= $buf;

  while($pandata =~ m/\n/) {
    my $rmsg;
    ($rmsg,$pandata) = split("\n", $pandata, 2);
    $rmsg =~ s/\r//;
    NinjaPiCrust_Parse($hash, $hash, $name, $rmsg) if($rmsg);
  }
  $hash->{PARTIAL} = $pandata;
}

sub
NinjaPiCrust_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;

  my $dmsg = $rmsg;
  my $rssi = 0;
  my $lqi = 0;
  Log3 $hash, $dl, "$name: NinjaPiCrust_Parse '$dmsg'";

  #next if(!$dmsg || length($dmsg) < 1);            # Bogus messages
  #return if($dmsg =~ m/^Available commands:/ );    # ignore startup messages
  #return if($dmsg =~ m/^  / );                     # ignore startup messages
  #return if($dmsg =~ m/^-> ack/ );                 # ignore send ack

  my ($isdup, $idx) = CheckDuplicate("", "$name: $dmsg", undef);
  return if ($isdup);

  if($dmsg =~ m/^\[/ ) {
    Log3 $name, 1, "NinjaPiCrust $name got special: $dmsg";
    $hash->{model} = $dmsg;

    if( $hash->{STATE} eq "Opened" ) {
      if( $dmsg =~m /pcaSerial/ ) {
	Log3 $hash, $dl, "nono";
      }
      $hash->{STATE} = "Initialized";
    }
    return;
  }
  readingsSingleUpdate($hash,"${name}_LASTMSG",$dmsg,1);

  my $jsonref = NinjaPiCrust_ParseJSON($dmsg);
  my %datagram = %$jsonref;
  #Log3 $name, $dl, "NinjaPiCrust_Parse: \%datagram is @{[%datagram]}";

  my %addvals;
  my $msgtype = (keys %datagram)[0];

  Log3 $name, $dl, "$name: got message type '$msgtype'";
  my %data = %{$datagram{$msgtype}[0]};
  $data{MSGTYPE} = $msgtype;
  %addvals = %data;
  Log3 $name, $dl, "$name: Got $msgtype $data{G} $data{V} $data{D} $data{DA} from $rmsg"
    if (defined $data{G} and defined $data{V} and defined $data{D} and defined $data{DA});
  $addvals{RAWMSG} = $rmsg;

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;
  #if(defined($rssi)) {
  #  $hash->{RSSI} = $rssi;
  #  $addvals{RSSI} = $rssi;
  #}
  #if(defined($lqi)) {
  #  $hash->{LQI} = $lqi;
  #  $addvals{LQI} = $lqi;
  #}

  if ($msgtype =~ m/ACK/i) {
    my $omsg = $rmsg; 
    $omsg =~ s/ACK/DEVICE/;
    Log3 $name, $dl, "$name: got ACK for command: $omsg";
    # for now, do nothing...
    return;
  } elsif ($msgtype =~ m/ERROR/i) {
    Log3 $name, 0, "$name: ERROR: got $rmsg from ".$hash->{RAWREQ};
    $hash->{RAWREQ} = undef;
    $hash->{RAWMSG} = undef;
    return;
  }

  if (($data{G} eq "0") and ($data{V} == 0)) {
    # message information pertains PiCrust hardware, so we handle it here:
    my $D = int($data{D});
    my $DA = $data{DA};
    Log3 $name, $dl, "$name: Got shield related data $msgtype: $D => '$DA'";

    if ($D == 1003) { # may be ACK (or even DEVICE?)
      my $version = substr $DA, 1;
      Log3 $name, $dl, "$name: Arduino version is $version";
      $hash->{VERSION} = $version;

    } elsif ($msgtype =~ m/DEVICE/) {
      if ($D == 999) {
        Log3 $name, $dl, "$name: led is '$DA'";
        readingsSingleUpdate($hash,"led",$DA,1);

      } elsif ($D == 1007) {
        Log3 $name, $dl, "$name: eyes are '$DA'";
        readingsSingleUpdate($hash,"eyes",$DA,1);

      } else {
        Log3 $name, 0, "$name: ERROR: got unsupported DID $D in '$rmsg'";
      }

    } else {
      Log3 $name, $dl, "$name: ignoring $msgtype-type message '$rmsg'";
    }
        
  } else {

    Log3 $hash, $dl, "$name: now dispatching    '$dmsg'";
    Dispatch($hash, $dmsg, \%addvals);
    Log3 $hash, $dl, "$name: end dispatching    '$dmsg'";
  }
}

#my devinfo = (
#  "0:0:999" => ( SENSE => 1 ),
#  "0:0:1003 => ( SENSE => 1 )
#)


#####################################
sub
NinjaPiCrust_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "NinjaPiCrust_DoInit")
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
NinjaPiCrust_ResetDevice($)
{
  my ($hash) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  my $pulse = AttrVal($name, "resetPulseWidth", 0.5);
  $pulse= 0.01 if ($pulse < 0.01);
  $pulse= 2 if ($pulse > 2);

  Log3 $name, 1, "NinjaPiCrust_ResetDevice with pulse with $pulse sec.";

  #$hash->{USBDev}->pulse_dtr_on($pulse * 1000.0) if($hash->{USBDev});

  return undef;
}

sub
NinjaPiCrust_SimpleWrite(@)
{
  my ($hash, $msg, $nocr) = @_;
  return if(!$hash);

  my $name = $hash->{NAME};
  Log3 $name, $dl, "$name: NinjaPiCrust_SW    '$msg'";

  $hash->{RAWREQ} = $msg;
  $msg .= "\n" unless($nocr);

  $hash->{USBDev}->write($msg)    if($hash->{USBDev});
  syswrite($hash->{DIODev}, $msg) if($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

sub
NinjaPiCrust_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};

  if( $aName eq "Clients" ) {
    $hash->{Clients} = $aVal;
    $hash->{Clients} = $clientsNinjaPiCrust if( !$hash->{Clients}) ;
  } elsif( $aName eq "MatchList" ) {
    $hash->{MatchList} = $aVal;
    $hash->{MatchList} = \%matchListNinjaPiCrust if( !$hash->{MatchList} );
  } elsif($aName =~ m/^tune/i) { #tune attribute freq / rx:bWidth / rx:rAmpl / rx:sens / tx:deviation / tx:power
  # Frequenze: Fc =860+ F x0.0050MHz
        # LNA Gain [dB] = MAX -6, -14, -20
        # RX Bandwidth [kHz] = -, 400, 340, 270, 200, 134, 67
        # DRSSI [dB] = -103, -97, -91, -85, -79, -73
        # Deviation [kHz] = 15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240
        # OuputPower [dBm] = 0, -3, -6, -9, -12, -15, -18, -21

        return "Usage: attr $name $aName <Frequence> <Rx:Bandwidth> <Rx:Amplitude> <Rx:Sens> <Tx:Deviation> <Tx:Power>"
                if(!$aVal || $aVal !~ m/^(4|8)[\d]{2}.[\d]{3} (0|400|340|270|200|134|67) (0|\-6|\-14|\-20) (\-103|\-97|\-91|\-85|\-79|\-73) (15|30|45|60|75|90|105|120|135|150|165|180|195|210|225|240) (0|\-3|\-6|\-9|\-12|\-15|\-18|\-21)/ );

        my $TuneStr = NinjaPiCrust_CalcTuneCmd($aVal);

    NinjaPiCrust_Write($hash, "t" . $TuneStr);

  } elsif ($aName eq "DebounceTime") {

                return "Usage: attr $name $aName <OOK-Protocol-Number><DebounceTime>"
                        if($aVal !~ m/^[0-9]{3,5}$/);

    #Log3 $name, 4, "set $name $cmd $arg";
    NinjaPiCrust_Write($hash, "Od" . $aVal);
  }

  return undef;
}

sub NinjaPiCrust_CalcTuneCmd($) {

        my ($str) = @_;

        my ($freq, $rxbwidth, $rxampl, $rxsens, $txdev, $txpower) = split(' ', $str ,6);

        my $sfreq;
        if($freq < 800) {
                $sfreq = sprintf("%03X", ($freq-430)/0.0025);
        } else {
                $sfreq = sprintf("%03X", ($freq-860)/0.0050);
        }

        my $sbwidth = sprintf("%01X", NinjaPiCrust_getIndexOfArray($rxbwidth,(0, 400, 340, 270, 200, 134, 67)));
        my $sampl = sprintf("%01X", NinjaPiCrust_getIndexOfArray($rxampl,(0, -6, -14, -20)));
        my $ssens = sprintf("%01X", NinjaPiCrust_getIndexOfArray($rxsens,    (-103, -97, -91, -85, -79, -73)));

        my $sdev = sprintf("%01X", NinjaPiCrust_getIndexOfArray($txdev,      (15, 30, 45, 60, 75, 90, 105, 120, 135, 150, 165, 180, 195, 210, 225, 240)));
        my $soutpupower = sprintf("%01X", NinjaPiCrust_getIndexOfArray($txpower,     (0, -3, -6, -9, -12, -15, -18, -21)));

        return $sfreq . $sbwidth . $sampl . $ssens . $sdev . $soutpupower;
}

sub NinjaPiCrust_getIndexOfArray($@) {

        my ($value, @array) = @_;
        my ($ivalue) = grep { $array[$_] == $value } 0..$#array;
        return $ivalue;
}
1;

=pod
=begin html

<a name="NinjaPiCrust"></a>
<h3>NinjaPiCrust</h3>
<ul>
  The NinjaPiCrust is a family of RF devices sold by <a href="http://jeelabs.com">jeelabs.com</a>.

  It is possible to attach more than one device in order to get better
  reception, fhem will filter out duplicate messages.<br><br>

  This module provides the IODevice for the <a href="#PCA301">PCA301</a> modules that implements the PCA301 protocoll.<br><br>
  In the future other RF devices like the Energy Controll 3000, JeeLabs room nodes, fs20 or kaku devices will be supportet.<br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.

  <br><br>

  <a name="NinjaPiCrust_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; NinjaPiCrust &lt;device&gt;</code> <br>
    <br>
    USB-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the NinjaPiCrust.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the NinjaPiCrust by the
      following command:<ul>modprobe usbserial vendor=0x0403
      product=0x6001</ul>In this case the device is most probably
      /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@57600<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>

    </ul>
    <br>
  </ul>
  <br>

  <a name="NinjaPiCrust_Set"></a>
  <b>Set</b>
  <ul>
    <li>raw &lt;datar&gt;<br>
        send &lt;data&gt; as a raw message to the NinjaPiCrust to be transmitted over the RF link.
        </li><br>
    <li>LaCrossePairForSec &lt;sec&gt; [ignore_battery]<br>
       enable autocreate of new LaCrosse sensors for &lt;sec&gt; seconds. if ignore_battery is not given only sensors
       sending the 'new battery' flag will be created.
        </li>
  </ul>

  <a name="NinjaPiCrust_Get"></a>
  <b>Get</b>
  <ul>
  </ul>

  <a name="NinjaPiCrust_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>Clients</li>
    <li>MatchList</li>
  </ul>
  <br>
</ul>

=end html
=cut

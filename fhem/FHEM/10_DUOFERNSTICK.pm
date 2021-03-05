##############################################
# $Id$

package main;

use strict;
use warnings;
use DevIo;

sub DUOFERNSTICK_Read($);
sub DUOFERNSTICK_Ready($);

my %matchList = ( "1:DUOFERN" => "^(06|0F|81).{42}") ;
                  
my %sets = ( 
  "reopen:noArg" => "",
  "statusBroadcast:noArg" => "",
  "pair:noArg" => "",
  "unpair:noArg" => "",
  "remotePair" => "",
  "raw" => "",
);

my $duoInit1            = "01000000000000000000000000000000000000000000";
my $duoInit2            = "0E000000000000000000000000000000000000000000";
my $duoSetDongle        = "0Azzzzzz000100000000000000000000000000000000";
my $duoInit3            = "14140000000000000000000000000000000000000000";
my $duoSetPairs         = "03nnyyyyyy0000000000000000000000000000000000";
my $duoInitEnd          = "10010000000000000000000000000000000000000000";
my $duoACK              = "81000000000000000000000000000000000000000000";
my $duoStatusRequest    = "0DFF0F400000000000000000000000000000FFFFFF01";
my $duoStartPair        = "04000000000000000000000000000000000000000000";
my $duoStopPair         = "05000000000000000000000000000000000000000000";
my $duoStartUnpair      = "07000000000000000000000000000000000000000000";
my $duoStopUnpair       = "08000000000000000000000000000000000000000000";
my $duoRemotePair       = "0D0106010000000000000000000000000000yyyyyy00";

sub DUOFERNSTICK_Initialize($)
{
  my ($hash) = @_;
   
  $hash->{ReadFn}  = "DUOFERNSTICK_Read";
  $hash->{ReadyFn} = "DUOFERNSTICK_Ready";
  $hash->{WriteFn} = "DUOFERNSTICK_Write";
  $hash->{DefFn}   = "DUOFERNSTICK_Define";
  $hash->{UndefFn} = "DUOFERNSTICK_Undef";
  $hash->{SetFn}   = "DUOFERNSTICK_Set";
  $hash->{NotifyFn}= "DUOFERNSTICK_Notify";
  $hash->{Clients} = ":DUOFERN:";
  $hash->{MatchList} = \%matchList; 
  $hash->{AttrList}= $readingFnAttributes;
  
}

#####################################
sub
DUOFERNSTICK_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if(@a < 4 || @a > 5) {
    my $msg = "wrong syntax: define <name> DUOFERNSTICK devicename DongleSerial";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev = $a[2];
  return "wrong DongleSerial format: specify a 6 digit hex value starting with 6F"
                if(uc($a[3]) !~ m/^6F[a-f0-9]{4}$/i);
                
  $hash->{DongleSerial} = uc($a[3]);

  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "DUOFERNSTICK_DoInit");
  return $ret;
}

#####################################
sub 
DUOFERNSTICK_setStates($$)
{
  my ($hash, $val) = @_;
  $hash->{STATE} = $val;
  $val = "disconnected" if ($val eq "closed");
  setReadingsVal($hash, "state", $val, TimeNow());
}

#####################################
sub
DUOFERNSTICK_Undef($$)
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

  DevIo_CloseDev($hash);
  return undef;
}


#####################################
sub 
DUOFERNSTICK_Set($@)
{
  my ($hash, @a) = @_;

  return "set $hash->{NAME} needs at least one parameter" if(@a < 2);

  my $me   = shift @a;
  my $cmd  = shift @a;
  my $arg  = shift @a;
  my $err;
  my $buf;
  
  return join(" ", sort keys %sets) if ($cmd eq "?");

  if ($cmd eq "reopen") { 
    return DUOFERNSTICK_Reopen($hash);
    
  } elsif ($cmd eq "statusBroadcast") {
    DUOFERNSTICK_AddSendQueue($hash, $duoStatusRequest);
    return undef;
    
  } elsif ($cmd eq "raw") {
    return "wrong raw format: specify a 44 digit hex value"
                if(!$arg || (uc($arg) !~ m/^[a-f0-9]{44}$/i));
    DUOFERNSTICK_AddSendQueue($hash, $arg);
    return undef;
    
  } elsif ($cmd eq "pair") {
    DUOFERNSTICK_AddSendQueue($hash, $duoStartPair);
    $hash->{pair} = 1;
    delete($hash->{unpair});
    InternalTimer(gettimeofday()+60, "DUOFERNSTICK_RemovePair", "$hash->{NAME}:RP", 1);
    return undef;
    
  } elsif ($cmd eq "unpair") {
    DUOFERNSTICK_AddSendQueue($hash, $duoStartUnpair);
    $hash->{unpair} = 1;
    delete($hash->{pair});
    InternalTimer(gettimeofday()+60, "DUOFERNSTICK_RemoveUnpair", "$hash->{NAME}:RU", 1);
    return undef;
  
   } elsif ($cmd eq "remotePair") {
    return "wrong serial format: specify a 6 digit hex value"
                if(!$arg || (uc($arg) !~ m/^[a-f0-9]{6}$/i)); 
    my $buf =  $duoRemotePair;
    $buf =~ s/yyyyyy/$arg/;      
    DUOFERNSTICK_AddSendQueue($hash, $buf);
    return undef;
      
  }
  
  return "Unknown argument $cmd, choose one of ". join(" ", sort keys %sets); 
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
DUOFERNSTICK_Read($)
{
  my ($hash) = @_;
  my $buf = "";
  my $rbuf = DevIo_SimpleRead($hash);
  
  return "" if(!defined($rbuf));
  
  if ($hash->{PARTIAL} ne "") {
    RemoveInternalTimer("$hash->{NAME}:FB");
  }
  
  my @array=split('',$rbuf);
  
  foreach (@array){
    $buf .= sprintf "%02x", ord($_) ;
  }
   
  my $name = $hash->{NAME};

  my $duodata = $hash->{PARTIAL};
  
  $duodata .= $buf;

  while(length($duodata) >= 44) {
    my $rmsg;
    my $me = $hash->{NAME};
    ($rmsg,$duodata) = unpack("a44 a*", $duodata);
    Log3 $name, 4, "$me: rx  -> $rmsg";
    $hash->{PARTIAL} = $duodata; # for recursive calls
    DUOFERNSTICK_Parse($hash, uc($rmsg)) if($rmsg);
    $duodata = $hash->{PARTIAL};
  }
  $hash->{PARTIAL} = $duodata;
  
  my $now = gettimeofday();
  if ($hash->{PARTIAL} ne "") {
  InternalTimer($now+0.5, "DUOFERNSTICK_Flush_Buffer", "$hash->{NAME}:FB", 0);
  }
}

#####################################
sub
DUOFERNSTICK_Write($$)
{
  my ($hash,$msg) = @_;
  my $err;
  my $buf;
  
  my $name = $hash->{NAME};
  Log3 $name, 5, "$hash->{NAME} sending $msg";

  $msg =~ s/zzzzzz/$hash->{DongleSerial}/;
  
  DUOFERNSTICK_AddSendQueue($hash,$msg);
  
}

#####################################
sub
DUOFERNSTICK_Parse($$)
{
  my ($hash, $rmsg) = @_;

  DUOFERNSTICK_SimpleWrite($hash, $duoACK) if($rmsg ne $duoACK);;
  
  if($rmsg =~ m/81.{42}/) {
    DUOFERNSTICK_HandleWriteQueue($hash);
  }
  
  return if($rmsg eq $duoACK);
  
  $hash->{RAWMSG} = $rmsg;
  
  if($rmsg =~ m/0602.{40}/) {
    my %addvals = (RAWMSG => $rmsg);
    Dispatch($hash, $rmsg, \%addvals) if ($hash->{pair});
    delete($hash->{pair});
    RemoveInternalTimer($hash);
    return undef;
    
  } elsif ($rmsg =~ m/0603.{40}/) {
    my %addvals = (RAWMSG => $rmsg);
    Dispatch($hash, $rmsg, \%addvals) if ($hash->{unpair});
    delete($hash->{unpair});
    RemoveInternalTimer($hash);
    return undef;
    
  } elsif ($rmsg =~ m/0FFF11.{38}/) {
    return undef;
  
  } elsif ($rmsg =~ m/81000000.{36}/) {
    return undef;
  
  }
    
  my %addvals = (RAWMSG => $rmsg);
  Dispatch($hash, $rmsg, \%addvals);
  
}
 
#####################################
sub
DUOFERNSTICK_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "DUOFERNSTICK_DoInit")
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes>0);
}

#####################################
sub
DUOFERNSTICK_RemovePair($)
{
    my ($name,$id) = split(":",$_[0]);
    my ($hash) = $defs{$name};
    
    DUOFERNSTICK_AddSendQueue($hash, $duoStopPair);
    
    delete($hash->{pair});
    
    return undef;
}

#####################################
sub
DUOFERNSTICK_RemoveUnpair($)
{
    my ($name,$id) = split(":",$_[0]);
    my ($hash) = $defs{$name};
    
    DUOFERNSTICK_AddSendQueue($hash, $duoStopUnpair);
    
    delete($hash->{unpair});
    
    return undef;
}

#####################################
sub
DUOFERNSTICK_Flush_Buffer($)
{
    my ($name,$id) = split(":",$_[0]);
    
    if ($defs{$name}{PARTIAL} ne "") {
      Log3 $name, 4, "$name discard $defs{$name}{PARTIAL}";
    }
   
    $defs{$name}{PARTIAL} ="";
    
    return undef;
}

#####################################
sub
DUOFERNSTICK_Reopen($)
{
  my ($hash) = @_;
  DevIo_CloseDev($hash);
  DevIo_OpenDev($hash, 1, "DUOFERNSTICK_DoInit");
}

#####################################
sub
DUOFERNSTICK_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;
  my $buf = "";

  my @pairs;
  
  foreach my $d (keys %defs)   
  { 
    my $module   = $defs{$d}{TYPE};
    next if ($module ne "DUOFERN");
    
    my $code = $defs{$d}{CODE};
    if(AttrVal($defs{$d}{NAME}, "ignore", "0") == "0") {
      push(@pairs, $code) if(length($code) == 6);
    }
  }

  $hash->{helper}{cmdEx} = 0;
  @{$hash->{cmdStack}} = ();
  
  return undef if (!$init_done);
  
  for(my $i = 0; $i < 4; $i++) {
    DUOFERNSTICK_SimpleWrite($hash, $duoInit1);
    ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "INIT1");
    next if($err);
    
    DUOFERNSTICK_SimpleWrite($hash, $duoInit2);
    ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "INIT2");
    next if($err);
    
    $buf = $duoSetDongle;
    $buf =~ s/zzzzzz/$hash->{DongleSerial}/;
    DUOFERNSTICK_SimpleWrite($hash, $buf);
    ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "SetDongle");
    next if($err);
    DUOFERNSTICK_SimpleWrite($hash, $duoACK);
    
    DUOFERNSTICK_SimpleWrite($hash, $duoInit3);
    ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "INIT3");
    next if($err);
    DUOFERNSTICK_SimpleWrite($hash, $duoACK);
    
    my $counter = 0;
    foreach (@pairs){
      $buf = $duoSetPairs;
      my $chex .= sprintf "%02x", $counter;
      $buf =~ s/nn/$chex/;
      $buf =~ s/yyyyyy/$_/;
      DUOFERNSTICK_SimpleWrite($hash, $buf);
      ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "SetPairs");
      next if($err);
      DUOFERNSTICK_SimpleWrite($hash, $duoACK);
      $counter++;
    }  
    
    DUOFERNSTICK_SimpleWrite($hash, $duoInitEnd);
    ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "INIT3");
    return "$name: $err" if($err);
    DUOFERNSTICK_SimpleWrite($hash, $duoACK);
    next if($err);
    
    DUOFERNSTICK_SimpleWrite($hash, $duoStatusRequest);
    ($err, $buf) = DUOFERNSTICK_ReadAnswer($hash, "statusRequest");
    next if($err);
    DUOFERNSTICK_SimpleWrite($hash, $duoACK);
  
    readingsSingleUpdate($hash, "state", "Initialized", 1);
    return undef;
  }
  return "$name: Init fail";
  
}

#####################################
sub 
DUOFERNSTICK_SimpleWrite(@)
{
  my ($hash, $msg) = @_;
  my $buf = "";
  return if(!$hash);
  my $name = $hash->{NAME};
   
  $msg =~ s/ //g;
  my $me = $hash->{NAME};
  Log3 $me, 4, "$me: snd -> $msg";

  my @hex    = ($msg =~ /(..)/g);
  foreach (@hex){
    $buf .= chr(hex($_)) ;
  }

  DevIo_SimpleWrite($hash,$buf,0);
    
  return undef;
}

#####################################
sub
DUOFERNSTICK_ReadAnswer($$)
{
  my ($hash, $arg) = @_;
  my $ohash = $hash;

  while($hash->{TYPE} ne "DUOFERNSTICK") {   
    $hash = $hash->{IODev};
  }
  return ("No FD", undef)
        if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($mduodata, $rin) = ("", '');
  my $buf;
  my $to = 1;                                         # 3 seconds timeout
  $mduodata = $hash->{PARTIAL} if(defined($hash->{PARTIAL}));

  $to = $ohash->{RA_Timeout} if($ohash->{RA_Timeout});  # ...or less
  for(;;) {

    if($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to*1000); # set timeout (ms)
      # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(22);
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
        return("DUOFERNSTICK_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if(!defined($buf));

    }

    if(defined($buf)) {
      
      my $rbuf  = "";
      my @array=split('',$buf);
      foreach (@array){
        $rbuf .= sprintf "%02x", ord($_) ;
    }
      Log3 $ohash->{NAME}, 5, "DUOFERNSTICK/RAW (ReadAnswer): $rbuf";
      $mduodata .= $rbuf;
    }

    # Dispatch data in the buffer before the proper answer.
    if(length($mduodata) >= 44) {  
      my $rmsg;
      ($rmsg,$mduodata) = unpack("a44 a*", $mduodata);
      $hash->{PARTIAL} = $mduodata; # for recursive calls
      return (undef, $rmsg);
    }
  }
}

#####################################
sub 
DUOFERNSTICK_Notify($$)
{
  my ($own, $dev) = @_;
  my $me = $own->{NAME}; # own name / hash
  my $devName = $dev->{NAME}; # Device that created the events

  return undef if ($devName ne "global");
  
  my $max = int(@{$dev->{CHANGED}}); # number of events / changes
  for (my $i = 0; $i < $max; $i++) {
    my $s = $dev->{CHANGED}[$i];
    
    next if(!defined($s));
    my ($what,$who) = split(' ',$s);
    
    if ($what && ($what =~ m/^INITIALIZED$/)) {
      DUOFERNSTICK_DoInit($own);
    }
  }
  return undef;
}

#####################################
sub
DUOFERNSTICK_HandleWriteQueue($)
{
  my ($hash) = @_;
  
  RemoveInternalTimer($hash);
  
  $hash->{helper}{cmdEx} -= 1 if ($hash->{helper}{cmdEx});
  
  my $entries = scalar @{$hash->{cmdStack}};
  if ($entries > 0) {
    readingsSingleUpdate($hash, "state", ($entries + $hash->{helper}{cmdEx})." CMDs_pending", 1);
    my $msg = shift @{$hash->{cmdStack}};
    $hash->{helper}{cmdEx} += 1;
    DUOFERNSTICK_SimpleWrite($hash, $msg);
    InternalTimer(gettimeofday()+5, "DUOFERNSTICK_HandleWriteQueue", $hash, 1);
  } else {
    readingsSingleUpdate($hash, "state","CMDs_done", 1);
  }   

}

#####################################
sub
DUOFERNSTICK_AddSendQueue($$)
{
  my ($hash, $msg) = @_;
  
  push(@{$hash->{cmdStack}}, $msg);
  my $entries = scalar @{$hash->{cmdStack}};
  
  if ($hash->{helper}{cmdEx} == 0 ) {
    DUOFERNSTICK_HandleWriteQueue($hash);
  } else {
    readingsSingleUpdate($hash, "state", ($entries + $hash->{helper}{cmdEx})." CMDs_pending", 1);
    InternalTimer(gettimeofday()+5, "DUOFERNSTICK_HandleWriteQueue", $hash, 1);
  };

}

1;

=pod
=item summary    IO device for Rademacher DuoFern devices
=item summary_DE IO device für Rademacher DuoFern Ger&auml;te
=begin html

<a name="DUOFERNSTICK"></a>
<h3>DUOFERNSTICK</h3>
<ul>

  The DUOFERNSTICK is the fhem module for the Rademacher DuoFern USB stick. <br>
    
  <br><br>

  <a name="DUOFERNSTICK_define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; DUOFERNSTICK &lt;device&gt; &lt;code&gt;</code><br><br>
    &lt;device&gt; specifies the serial port to communicate with the DuoFern stick.<br>
    &lt;code&gt; specifies the radio code of the DuoFern stick.<br>
    <br>
    The baud rate must be 115200 baud.<br>
    The code of the DuoFern stick must start with 6F.
    <br><br>
    Example:<br>
    <ul>
      <code>define myDuoFernStick DUOFERNSTICK COM5@115200 6FEDCB</code><br>
      <code>define myDuoFernStick DUOFERNSTICK /dev/serial/by-id/usb-Rademacher_DuoFern_USB-Stick_WR0455TN-if00-port0@115200 6FEDCB</code><br>
    </ul>
  </ul>
  <br>
  <a name="DUOFERNSTICK_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li><b>pair</b><br>
        Set the DuoFern stick in pairing mode for 60 seconds. Any DouFern device set into
        pairing mode in this time will be paired with the DuoFern stick.
        </li><br>
    <li><b>unpair</b><br>
        Set the DuoFern stick in unpairing mode for 60 seconds. Any DouFern device set into
        unpairing mode in this time will be unpaired from the DuoFern stick.
        </li><br>
    <li><b>reopen</b><br>
        Reopens the connection to the device and reinitializes it.
        </li><br>
    <li><b>statusBroadcast</b><br>
        Sends a status request message to all DuoFern devices.
        </li><br>
    <li><b>remotePair &lt;code&gt</b><br>
        Activates the pairing mode on the device specified by the code.<br>
        Some actors accept this command in unpaired mode up to two hours afte power up. 
        </li><br>
    <li><b>raw &lt;rawmsg&gt;</b><br>
        Sends a raw message.
        </li><br>
  </ul>
  <br>
  <b>Get</b> <ul>N/A</ul><br>
  <a name="DUOFERNSTICK_attr"></a>
  <b>Attributes</b>
  <ul>
    N/A
  </ul>
  <br>

</ul>

=end html

=cut


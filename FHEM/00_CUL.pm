##############################################
# Implemented:
# - Transmit limit trigger: Fire if more then 1% airtime 
#   is used in the last hour
# - reconnect
# - message flow control (send one F message every 0.25 seconds)
# - repeater/filtertimeout
# - FS20 rcv
# - FS20 xmit
# - FHT rcv

# TODO:
# - FHT xmit
# - HMS rcv
# - KS300 rcv
# - EMEM rcv
# - EMWZ rcv
# - EMGZ rcv
# - S300TH rcv


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);


sub CUL_Write($$$);
sub CUL_Read($);
sub CUL_ReadAnswer($$);
sub CUL_Ready($$);

my %msghist;		# Used when more than one CUL is attached
my $msgcount = 0;
my %gets = (
  "ccreg"       => "C",
  "readeeprom"  => "R",
  "version"     => "V",
  "time"        => "t",
);

my %sets = (
  "writeeeprom" => "W",
  "sendrawFS20" => "F",
  "sendrawFHT"  => "T",
  "verbose"     => "X",
);

sub
CUL_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "CUL_Read";
  $hash->{WriteFn} = "CUL_Write";
  $hash->{Clients} = ":FS20:FHT:KS300:CUL_EM:CUL_WS:";
  $hash->{ReadyFn} = "CUL_Ready" if ($^O eq 'MSWin32');

# Normal devices
  $hash->{DefFn}   = "CUL_Define";
  $hash->{UndefFn} = "CUL_Undef";
  $hash->{GetFn}   = "CUL_Get";
  $hash->{SetFn}   = "CUL_Set";
  $hash->{StateFn} = "CUL_SetState";
  $hash->{AttrList}= "do_not_notify:1,0 dummy:1,0 filtertimeout repeater:1,0 " .
                   "showtime:1,0 model:CUL loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
CUL_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;
  $hash->{STATE} = "Initialized";

  delete $hash->{PortObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $dev = $a[2];

  $attr{$name}{savefirst} = 1;
  $attr{$name}{repeater} = 1;

  if($dev eq "none") {
    Log 1, "CUL device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }
  
  Log 3, "CUL opening CUL device $dev";
  if ($^O=~/Win/) {
   require Win32::SerialPort;
   $po = new Win32::SerialPort ($dev);
  } else  {
   require Device::SerialPort;
   $po = new Device::SerialPort ($dev);
  }
  return "Can't open $dev: $!\n" if(!$po);
  Log 3, "CUL opened CUL device $dev";

  $hash->{PortObj} = $po;
  if( $^O !~ /Win/ ) {
    $hash->{FD} = $po->FILENO;
    $selectlist{"$name.$dev"} = $hash;
  } else {
    $readyfnlist{"$name.$dev"} = $hash;
  }
  
  $hash->{DeviceName} = $dev;
  $hash->{PARTIAL} = "";
  return CUL_DoInit($hash);
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
        Log GetLogLevel($name,2), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  $hash->{PortObj}->close() if($hash->{PortObj});
  return undef;
}

#####################################
sub
CUL_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set CUL\" needs at least one parameter" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));

  my $arg = ($a[2] ? $a[2] : "");
  CUL_Write($hash, $sets{$a[1]}, $arg) if(!IsDummy($hash->{NAME}));
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
  CUL_Write($hash, $gets{$a[1]}, $arg) if(!IsDummy($hash->{NAME}));
  my $msg = CUL_ReadAnswer($hash, $a[1]);
  $msg =~ s/[\r\n]//g;

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

#####################################
sub
CUL_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};

  # Clear the pipe
  $hash->{RA_Timeout} = 0.1;
  for(;;) {
    last if(CUL_ReadAnswer($hash, "Clear") =~ m/^Timeout/);
  }
  delete($hash->{RA_Timeout});

  $hash->{PortObj}->write("V\n");
  my $ver = CUL_ReadAnswer($hash, "Version");
  if($ver !~ m/^V/) {
    $attr{$name}{dummy} = 1;
    $hash->{PortObj}->close();
    my $msg = "Not an CUL device, receives for V:  $ver";
    Log 1, $msg;
    return $msg;
  }
  $hash->{PortObj}->write("X01\n");     # Enable message reporting

  # Reset the counter
  delete($hash->{XMIT_TIME});
  delete($hash->{NR_CMD_LAST_H});
}

#####################################
# This is a direct read for commands like get
sub
CUL_ReadAnswer($$)
{
  my ($hash,$arg) = @_;

  return undef if(!$hash || !defined($hash->{FD}));
  my ($mculdata, $rin) = ("", '');
  my $nfound;
  for(;;) {
    if($^O eq 'MSWin32') {
      $nfound=CUL_Ready($hash, undef);
    } else {
      vec($rin, $hash->{FD}, 1) = 1;
      my $to = 3;                                         # 3 seconds timeout
      $to = $hash->{RA_Timeout} if($hash->{RA_Timeout});  # ...or less
      $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        die("Select error $nfound / $!\n");
      }
    }
    return "Timeout reading answer for get $arg" if($nfound == 0);
    my $buf = $hash->{PortObj}->input();

    Log 5, "CUL/RAW: $buf";
    $mculdata .= $buf;
    return $mculdata if($mculdata =~ m/\r\n/);
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

    my $me = $hash->{NAME};
    Log GetLogLevel($me,2), "CUL TRANSMIT LIMIT EXCEEDED";
    DoTrigger($me, "TRANSMIT LIMIT EXCEEDED");

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

  if(!$hash || !defined($hash->{PortObj})) {
    Log 5, "CUL device $hash->{NAME} is not active, cannot send";
    return;
  }

  ###################
  # Rewrite message from FHZ -> CUL
  if(length($fn) == 1) {                                   # CUL Native
  } elsif($fn eq "04" && substr($msg,0,6) eq "010101") {   # FS20
    $fn = "F";
    $msg = substr($msg,6);
  } else {
    Log 1, "CUL cannot translate $fn $msg";
    return;
  }

  ###############
  # insert value into the msghist. At the moment this only makes sense for FS20
  # devices. As the transmitted value differs from the received one, we have to
  # recompute.
  if($fn eq "F" || $fn eq "T") {
    $msghist{$msgcount}{TIME} = gettimeofday();
    $msghist{$msgcount}{NAME} = $hash->{NAME};
    $msghist{$msgcount}{MSG}  = "$fn$msg";
    $msgcount++;
  }

  Log 5, "CUL sending $fn$msg";
  my $bstring = "$fn$msg\n";

  if($fn eq "F") {
    if(!$hash->{QUEUECNT}) {

      CUL_XmitLimitCheck($hash, $bstring);
      $hash->{PortObj}->write($bstring);

      ##############
      # Write the next buffer not earlier than 0.227 seconds (= 65.6ms + 10ms +
      # 65.6ms + 10ms + 65.6ms + 10ms)
      InternalTimer(gettimeofday()+0.25, "CUL_HandleWriteQueue", $hash, 1);

    } elsif($hash->{QUEUECNT} == 1) {
      $hash->{QUEUE} = [ $bstring ];
    } else {
      push(@{$hash->{QUEUE}}, $bstring);
    }
    $hash->{QUEUECNT}++;

  } else {

    $hash->{PortObj}->write($bstring);

  }

}

#####################################
sub
CUL_HandleWriteQueue($)
{
  my $hash = shift;
  my $cnt = --$hash->{QUEUECNT};
  if($cnt > 0) {
    my $bstring = shift(@{$hash->{QUEUE}});
    CUL_XmitLimitCheck($hash,$bstring);
    $hash->{PortObj}->write($bstring);
    InternalTimer(gettimeofday()+0.25, "CUL_HandleWriteQueue", $hash, 1);
  }
}

#####################################
sub
CUL_Read($)
{
  my ($hash) = @_;

  my $buf = $hash->{PortObj}->input();
  my $iohash = $modules{$hash->{TYPE}}; # Our (CUL) module pointer
  my $name = $hash->{NAME};

  ###########
  # Lets' try again: Some drivers return len(0) on the first read...
  if(defined($buf) && length($buf) == 0) {
    $buf = $hash->{PortObj}->input();
  }

  if(!defined($buf) || length($buf) == 0) {

    my $devname = $hash->{DeviceName};
    Log 1, "USB device $devname disconnected, waiting to reappear";
    $hash->{PortObj}->close();
    for(;;) {
      sleep(5);
      if ($^O eq 'MSWin32') {
        $hash->{PortObj} = new Win32::SerialPort($devname);
      }else{
        $hash->{PortObj} = new Device::SerialPort($devname);  
      }
      
      if($hash->{PortObj}) {
        Log 1, "USB device $devname reappeared";
        $hash->{FD} = $hash->{PortObj}->FILENO if !($^O eq 'MSWin32');
        CUL_DoInit($hash);
	return;
      }
    }
  }

  my $culdata = $hash->{PARTIAL};
  Log 5, "CUL/RAW: $culdata/$buf";
  $culdata .= $buf;

  while($culdata =~ m/\n/) {

    my $dmsg;
    ($dmsg,$culdata) = split("\n", $culdata);
    $dmsg =~ s/\r//;

    ###############
    # check for duplicate msg from different CUL's
    my $now = gettimeofday();
    my $skip;
    my $meetoo = ($attr{$name}{repeater} ? 1 : 0);

    my $to = 0.3;
    if(defined($attr{$name}) && defined($attr{$name}{filtertimeout})) {
      $to = $attr{$name}{filtertimeout};
    }
    foreach my $oidx (keys %msghist) {
      if($now-$msghist{$oidx}{TIME} > $to) {
        delete($msghist{$oidx});
        next;
      }
      if($msghist{$oidx}{MSG} eq $dmsg &&
         ($meetoo || $msghist{$oidx}{NAME} ne $name)) {
        Log 5, "Skipping $msghist{$oidx}{MSG}";
        $skip = 1;
      }
    }
    goto NEXTMSG if($skip);
    $msghist{$msgcount}{TIME} = $now;
    $msghist{$msgcount}{NAME} = $name;
    $msghist{$msgcount}{MSG}  = $dmsg;
    $msgcount++;

Log 1, "CUL: $dmsg";
    ###########################################
    #Translate Message from CUL to FHZ
    my $fn = substr($dmsg,0,1);
    if($fn eq "F") {                                 # FS20
      $dmsg = sprintf("81%02x04xx0101a001%s00%s",
                        length($dmsg)/2+5,
                        substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } elsif($fn eq "T") {                            # FHT

      $dmsg =~ s/([1-4]\d)79(..)$/${1}69$2/;         # should be done in the FHT

      $dmsg = sprintf("81%02x04xx0909a001%s00%s",
                        length($dmsg)/2+5,
                        substr($dmsg,1,6), substr($dmsg,7));
      $dmsg = lc($dmsg);

    } elsif($fn eq "K" && length($dmsg) == 15) {     # KS300

      # K17815254024C82 ->   810d04f94027a0011718254520C428
      my $n = "";
      my @a = split("", $dmsg);
      for(my $i = 0; $i < 14; $i+=2) {   # Swap nibbles.
        $n .= $a[$i+2] . $a[$i+1];
      }
      $dmsg = sprintf("81%02x04xx4027a001%s", length($dmsg)/2+6, $n);

    } elsif($fn eq "K" && length($dmsg) == 9) {      # CUL_WS / Native
      ;
    } elsif($fn eq "E") {                            # CUL_EM / Native
      ;
    } else {
      Log 4, "CUL: unknown message $dmsg";
      goto NEXTMSG;
    }


    my @found;
    my $last_module;
    foreach my $m (sort { $modules{$a}{ORDER} cmp $modules{$b}{ORDER} }
                    grep {defined($modules{$_}{ORDER});}keys %modules) {
      next if($iohash->{Clients} !~ m/:$m:/);

      # Module is not loaded or the message is not for this module
      next if(!$modules{$m}{Match} || $dmsg !~ m/$modules{$m}{Match}/i);

      no strict "refs";
      @found = &{$modules{$m}{ParseFn}}($hash,$dmsg);
      use strict "refs";
      $last_module = $m;
      last if(int(@found));
    }
    if(!int(@found)) {
      Log 1, "Unknown code $dmsg, help me!";
      goto NEXTMSG;
    }

    goto NEXTMSG if($found[0] eq "");	# Special return: Do not notify

    # The trigger needs a device: we create a minimal temporary one
    if($found[0] =~ m/^(UNDEFINED) ([^ ]*) (.*)$/) {
      my $d = $1;
      $defs{$d}{NAME} = $1;
      $defs{$d}{TYPE} = $last_module;
      DoTrigger($d, "$2 $3");
      CommandDelete(undef, $d);                 # Remove the device
      goto NEXTMSG;
    }

    foreach my $found (@found) {
      DoTrigger($found, undef);
    }
NEXTMSG:
  }
  $hash->{PARTIAL} = $culdata;
}

#####################################
sub
CUL_Ready($$)           # Windows - only
{
  my ($hash, $dev) = @_;
  my $po=$hash->{PortObj};
  return undef if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}

1;

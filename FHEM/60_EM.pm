##############################################
package main;

use strict;
use warnings;


sub EM_Write($$);
sub EmCrc($$);
sub EmCrcCheck($$);
sub EmEsc($);
sub EmGetData($$);
sub EmMakeMsg($);
sub EM_Set($@);

# Following one-byte commands are trange, as they cause a timeout:
# 124 127 150 153 155 156


#####################################
sub
EM_Initialize($)
{
  my ($hash) = @_;


# Provider
  $hash->{WriteFn} = "EM_Write";
  $hash->{Clients} = ":EMWZ:EMEM:EMGZ:";

# Consumer
  $hash->{DefFn}   = "EM_Define";
  $hash->{UndefFn} = "EM_Undef";
  $hash->{GetFn}   = "EM_Get";
  $hash->{SetFn}   = "EM_Set";
  $hash->{AttrList}= "model:em1010pc dummy:1,0 loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
EM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE} = "Initialized";

  delete $hash->{PortObj};
  delete $hash->{FD};

  my $name = $a[0];
  my $dev = $a[2];

  $attr{$name}{savefirst} = 1;

  if($dev eq "none") {
    Log 1, "EM device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  Log 3, "EM opening device $dev";
  if ($^O=~/Win/) {
   eval ("use Win32::SerialPort;");
   my $po = new Win32::SerialPort ($dev);
  }else{
   eval ("use Device::SerialPort;");
   my $po = new Device::SerialPort ($dev);
  }
  
  return "Can't open $dev: $!" if(!$po);
  Log 3, "EM opened device $dev";
  $po->close();

  $hash->{DeviceName} = $dev;
  return undef;
}

#####################################
sub
EM_Undef($$)
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
  return undef;
}


#####################################
sub
EM_Set($@)
{
  my ($hash, @a) = @_;
  my $u1 = "Usage: set <name> reset\n" . 
          "       set <name> time [YYYY-MM-DD HH:MM:SS]";

  return $u1 if(int(@a) < 2);
  my $name = $hash->{DeviceName};

  if($a[1] eq "time") {

    if (int(@a) == 2) {
      my @lt = localtime;
      $a[2] = sprintf ("%04d-%02d-%02d", $lt[5]+1900, $lt[4]+1, $lt[3]);
      $a[3] = sprintf ("%02d:%02d:%02d", $lt[2], $lt[1], $lt[0]);
    } elsif (int(@a) != 4) {
      return $u1;
    }
    my @d = split("-", $a[2]);
    my @t = split(":", $a[3]);
    my $msg = sprintf("73%02x%02x%02x00%02x%02x%02x",
          $d[2],$d[1],$d[0]-2000+0xd0, $t[0],$t[1],$t[2]);
    my $d = EmGetData($name, $msg);
    return "Read error" if(!defined($d));
    return b($d,0);

  } elsif($a[1] eq "reset") {

    my $d = EmGetData($name, "4545");   # Reset
    return "Read error" if(!defined($d));
    sleep(10);
    EM_Set($hash, ($a[0], "time"));     # Set the time
    sleep(1);
    $d = EmGetData($name, "67");        # "Push the button", we don't want usesr interaction
    return "Read error" if(!defined($d));

  } else {

    return "Unknown argument $a[1], choose one of reset,time"

  }
  return undef;

}

#########################
sub
b($$)
{
  my ($t,$p) = @_;
  return -1 if(!defined($t) || length($t) < $p);
  return ord(substr($t,$p,1));
}

sub
w($$)
{
  my ($t,$p) = @_;
  return b($t,$p+1)*256 + b($t,$p);
}

sub
dw($$)
{
  my ($t,$p) = @_;
  return w($t,$p+2)*65536 + w($t,$p);
}

#####################################
sub
EM_Get($@)
{
  my ($hash, @a) = @_;

  return "\"get EM\" needs only one parameter" if(@a != 2);

  my $v;
  if($a[1] eq "time") {

    my $d = EmGetData($hash->{DeviceName}, "74");
    return "Read error" if(!defined($d));

    $v = sprintf "%4d-%02d-%02d %02d:%02d:%02d",
              b($d,5)+2006, b($d,4), b($d,3),
              b($d,0), b($d,1), b($d,2);

  } elsif($a[1] eq "version") {

    my $d = EmGetData($hash->{DeviceName},"76");
    return "Read error" if(!defined($d));
    $v = sprintf "%d.%d", b($d,0), b($d,1);

  } else {
    return "Unknown argument $a[1], choose one of time,version";
  }

  $hash->{READINGS}{$a[1]}{VAL} = $v;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $v";
}

#####################################
sub
EM_Write($$)
{
  my ($hash,$msg) = @_;

  return EmGetData($hash->{DeviceName}, $msg);
}

#####################################
sub
EmCrc($$)
{
  my ($in, $val) = @_;
  my ($crc, $bits) = (0, 8);
  my $k = (($in >> 8) ^ $val) << 8;
  while($bits--) {
    if(($crc ^ $k) & 0x8000) {
      $crc = ($crc << 1) ^ 0x8005;
    } else {
      $crc <<= 1;
    }
    $k <<= 1;
  }
  return (($in << 8) ^ $crc) & 0xffff;
}

#########################
sub
EmEsc($)
{
  my ($b) = @_;

  my $out = "";
  $out .= chr(0x10) if($b==0x02 || $b==0x03 || $b==0x10);
  $out .= chr($b);
}


#####################################
sub
EmCrcCheck($$)
{
  my ($otxt, $len) = @_;
  my $crc = 0x8c27;
  for(my $l = 2; $l < $len+4; $l++) {
    my $b = ord(substr($otxt,$l,1));
    $crc = EmCrc($crc, 0x10) if($b==0x02 || $b==0x03 || $b==0x10);
    $crc = EmCrc($crc, $b);
  }
  return ($crc == w($otxt, $len+4));
}

#########################
sub
EmMakeMsg($)
{
  my ($data) = @_;
  my $len = length($data);
  $data = chr($len&0xff) . chr(int($len/256)) . $data;

  my $out = pack('H*', "0200");
  my $crc = 0x8c27;
  for(my $l = 0; $l < $len+2; $l++) {
    my $b = ord(substr($data,$l,1));
    $crc = EmCrc($crc, 0x10) if($b==0x02 || $b==0x03 || $b==0x10);
    $crc = EmCrc($crc, $b);
    $out .= EmEsc($b);
  }
  $out .= EmEsc($crc&0xff);
  $out .= EmEsc($crc/256);
  $out .= chr(0x03);
  return $out;
}

#####################################
# This is the only 
sub
EmGetData($$)
{
  my ($dev, $d) = @_;
  $d = EmMakeMsg(pack('H*', $d));

  return undef if(!$dev);
  if ($^O=~/Win/) {
      my $serport = new Win32::SerialPort ($dev);
    }else{  
     my $serport = new Device::SerialPort ($dev);
    }
    
  if(!$serport) {
    Log 1, "EM: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(38400);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');

  Log 4, "EM: Sending " . unpack('H*', $d);

  my $rm = "EM timeout reading the answer";
  for(my $rep = 0; $rep < 3; $rep++) {

    $serport->write($d);

    my $retval = "";
    my $esc = 0;
    my $started = 0;
    my $complete = 0;
    for(;;) {
      my ($rout, $rin) = ('', '');
      vec($rin, $serport->FILENO, 1) = 1;
      my $nfound = select($rout=$rin, undef, undef, 1.0);

      if($nfound < 0) {
        $rm = "EM Select error $nfound / $!";
        goto DONE;
      }
      last if($nfound == 0);

      my $buf = $serport->input();
      if(!defined($buf) || length($buf) == 0) {
        $rm = "EM EOF on $dev";
        goto DONE;
      }

      for(my $i = 0; $i < length($buf); $i++) {
        my $b = ord(substr($buf,$i,1));

        if(!$started && $b != 0x02) { next; }
        $started = 1;
        if($esc) { $retval .= chr($b); $esc = 0; next; }
        if($b == 0x10) { $esc = 1; next; }
        $retval .= chr($b);
        if($b == 0x03) { $complete = 1; last; }
      }

      if($complete) {
        my $l = length($retval);
        if($l < 8)                    { $rm = "EM Msg too short";   goto DONE; }
        if(b($retval,1) != 0)         { $rm = "EM Bad second byte"; goto DONE; }
        if(w($retval,2) != $l-7)      { $rm = "EM Length mismatch"; goto DONE; }
        if(!EmCrcCheck($retval,$l-7)) { $rm = "EM Bad CRC";         goto DONE; }
        $serport->close();
        return substr($retval, 4, $l-7);
      }
    }
  }

DONE:
  $serport->close();
  return undef;
}


#########################
# Interpretation is left for the "user";
sub
EmGetDevData($)
{
  my ($hash) = @_;

  my $dnr = $hash->{DEVNR};
  my $d = IOWrite($hash, sprintf("7a%02x", $dnr-1));

  return("ERROR: No device no. $dnr present")
        if($d eq ((pack('H*',"00") x 45) . pack('H*',"FF") x 6));

  my $nrreadings = w($d,2);
  return("ERROR: No data to read (yet?)")
        if($nrreadings == 0);

  my $step  = b($d,6);
  my $start = b($d,18)+13;
  my $end   = $start + int(($nrreadings-1)/64)*$step;

  my @ret;
  for(my $p = $start; $p <= $end; $p += $step) {        # blockwise
    $d = IOWrite($hash, sprintf("52%02x%02x00000801", $p%256, int($p/256)));
    my $max = (($p == $end) ? ($nrreadings%64)*4+4 : 260);
    my $step = b($d, 6);

    for(my $off = 8; $off <= $max; $off += 4) {         # Samples in each block
      push(@ret, sprintf("%04x%04x\n", w($d,$off), w($d,$off+2)));
    }
  }
  return @ret;
}


1;

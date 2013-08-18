##############################################
# $Id$
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
  $hash->{AttrList}= "model:em1010pc dummy:1,0 ";
}

#####################################
sub
EM_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $po;
  $hash->{STATE} = "Initialized";

  my $name = $a[0];
  my $dev = $a[2];

  if($dev eq "none") {
    Log3 $name, 1, "EM device is none, commands will be echoed only";
    $attr{$name}{dummy} = 1;
    return undef;
  }

  Log3 $name, 3, "EM opening device $dev";
  if ( $^O =~ /Win/) {
   eval ("use Win32::SerialPort;");
    $po = new Win32::SerialPort ($dev);
  }else{
   eval ("use Device::SerialPort;");
    $po = new Device::SerialPort ($dev);
  }
  
  return "Can't open $dev: $!" if(!$po);
  Log3 $name, 3, "EM opened device $dev";
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
        my $lev = ($reread_active ? 4 : 2);
        Log3 $name, $lev, "deleting port for $d";
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

    return "Unknown argument $a[1], choose one of reset time"

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
  my $serport;
  my $rm;
  return undef if(!$dev);
  #OS depends
  if ($^O=~/Win/) {
       $serport = new Win32::SerialPort ($dev);
    }else{  
      $serport = new Device::SerialPort ($dev);
    }
    
  if(!$serport) {
    Log3 undef, 1, "EM: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(38400);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  if ( $^O =~ /Win/ ) {
    unless ($serport->write_settings) {
          $rm= "EM:Can't change Device_Control_Block: $^E\n";
          goto DONE;
        }
  }
  Log3 undef, 4, "EM: Sending " . unpack('H*', $d);

  $rm = "EM: timeout reading the answer";
  for(my $rep = 0; $rep < 3; $rep++) {

    $serport->write($d);
    
    
    my $retval = "";
    my $esc = 0;
    my $started = 0;
    my $complete = 0;
    my $buf;
    my $i;
    my $b;
    for(;;) {

      if($^O =~ /Win/) {
        #select will not work on windows, replaced with status
        my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=(0,0,0,0);
        for ($i=0;$i<9; $i++) {
           sleep(1); #waiiiit
          ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$serport->status;
          last if $InBytes>0;
        }
        Log3 undef, 5,"EM: read returned $InBytes Bytes($i trys)";
        last if ($InBytes<1);
        $buf = $serport->input();
        
      } else {
        my ($rout, $rin) = ('', '');
        vec($rin, $serport->FILENO, 1) = 1;
        my $nfound = select($rout=$rin, undef, undef, 1.0);
        
        if($nfound < 0) {
          $rm = "EM Select error $nfound / $!";
          goto DONE;
        }
        last if($nfound == 0);
        $buf = $serport->input();
      }

      
      if(!defined($buf) || length($buf) == 0) {
        $rm = "EM EOF on $dev";
        goto DONE;
      }

      for($i = 0; $i < length($buf); $i++) {
        $b = ord(substr($buf,$i,1));

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
        my $data=substr($retval, 4, $l-7);
        Log3 undef, 5,"EM: returned ".unpack("H*",$data);
        return $data;
      }
    }
  }

DONE:
  Log3 undef, 5,$rm;
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
  my $max;
  my $off;
  for(my $p = $start; $p <= $end; $p += $step) {        # blockwise
    $d = IOWrite($hash, sprintf("52%02x%02x00000801", $p%256, int($p/256)));
    $max = (($p == $end) ? ($nrreadings%64)*4+4 : 260);
    $step = b($d, 6);

    for($off = 8; $off <= $max; $off += 4) {         # Samples in each block
      push(@ret, sprintf("%04x%04x\n", w($d,$off), w($d,$off+2)));
    }
  }
  return @ret;
}


1;

=pod
=begin html

<a name="EM"></a>
<h3>EM</h3>
<ul>
  <a name="EMdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EM &lt;em1010pc-device&gt;</code>
    <br><br>

    Define a EM1010PC USB device. As the EM1010PC was not designed to be used
    with a PC attached to it all the time, it won't transmit received signals
    automatically, fhem has to poll it every 5 minutes.<br>

    Currently there is no way to read the internal log of the EM1010PC with
    fhem, use the program em1010.pl in the contrib directory for this
    purpose.<br><br>

    Examples:
    <ul>
      <code>define em EM /dev/elv_em1010pc</code><br>
    </ul>
  </ul>
  <br>

  <a name="EMset"></a>
  <b>Set</b>
  <ul>
    <code>set EM &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is either time or reset.<br>
    If time has arguments of the form YYYY-MM-DD HH:MM:SS, then the specified
    time will be set, else the time from the host.<br>
    Note: after reset you should set the time.
  </ul>
  <br>

  <a name="EMget"></a>
  <b>Get</b>
  <ul>
    <code>get EM &lt;value&gt;</code>
    <br><br>
    where <code>value</code> is either version or time.
  </ul>

  <a name="EMattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#model">model</a> (em1010pc)</li>
    <li><a href="#attrdummy">dummy</a></li>
  </ul>
  <br>
</ul>

=end html
=cut

#
#
# 80_M232.pm
# written by Dr. Boris Neubert 2007-11-26
# e-mail: omega at online dot de
#
##############################################
# $Id$
package main;

use strict;
use warnings;


sub M232Write($$);
sub M232GetData($$);
sub Log($$);
use vars qw {%attr %defs};

#####################################
sub
M232_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{WriteFn} = "M232_Write";
  $hash->{Clients} = ":M232Counter:M232Voltage:";

# Consumer
  $hash->{DefFn}   = "M232_Define";
  $hash->{UndefFn} = "M232_Undef";
  $hash->{GetFn}   = "M232_Get";
  $hash->{SetFn}   = "M232_Set";
  $hash->{AttrList}= "model:m232 loglevel:0,1,2,3,4,5";
}

#####################################
sub
M232_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE} = "Initialized";

  my $dev = $a[2];
  if($dev eq "none") {
    Log 1, "M232 device is none, commands will be echoed only";
    return undef;
  }

  Log 3, "M232 opening device $dev";
  my $po;
	if ($^O eq 'MSWin32') {
		eval ("use Win32::SerialPort;");
		if ($@) {
                   $hash->{STATE} = "error using Modul Win32::SerialPort";
                   Log 1,"Error using Device::SerialPort";
                   return "Can't use Win32::SerialPort $@\n";
                }
                $po = new Win32::SerialPort ($dev, 1);
                
	} else {
		eval ("use Device::SerialPort;");
		if ($@) {
                   $hash->{STATE} = "error using Modul Device::SerialPort";
                   Log 1,"Error using Device::SerialPort";
                   return "Can't Device::SerialPort $@\n";
                }
		$po = new Device::SerialPort ($dev, 1);
	}
	if (!$po) {
                   $hash->{STATE} = "error opening device";
                   Log 1,"Error opening Serial Device $dev";
                   return "Can't open Device $dev: $^E\n";
	}
  
  Log 3, "M232 opened device $dev";
  $po->close();

  $hash->{DeviceName} = $dev;
  return undef;
}

#####################################
sub
M232_Undef($$)
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
  return undef;
}
#####################################
# M232_Ready
# implement ReadyFn
# only used for Win32
#
sub
M232_Ready($$)
{
  my ($hash, $dev) = @_;
  my $po=$dev||$hash->{po};
  return 0 if !$po;
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags)=$po->status;
  return ($InBytes>0);
}


#####################################

sub
M232_Set($@)
{
  my ($hash, @a) = @_;
  my $u1 = "Usage: set <name> auto <value>\n" .
                  "set <name> stop\n" .
		  "set <name> start\n" .
		  "set <name> octet <value>\n" .
		  "set <name> [io0..io7] 0|1\n";

  return $u1 if(int(@a) < 2);
  my $msg;
  my $reading= $a[1];
  my $value;
  my @legal;

  if($reading eq "auto") {
        return $u1 if(int(@a) !=3);
	$value= $a[2];
        @legal= (0..5,"none");
        if(!grep($value eq $_, @legal)) {
                return "Illegal value $value, possible values: @legal";
        }
        if($value eq "none") { $value= 0; } else { $value+=1; }
	$msg= "M" . $value;
  }
  
  elsif($reading eq "start") {
        return $u1 if(int(@a) !=2);
	$msg= "Z1";
  }

  elsif($reading eq "stop") {
        return $u1 if(int(@a) !=2);
	$msg= "Z0";
  }

  elsif($reading eq "octet") {
        return $u1 if(int(@a) !=3);
	$value= $a[2];
        @legal= (0..255);
        if(!grep($value eq $_, @legal)) {
                return "Illegal value $value, possible values: 0..255";
        }
	$msg= sprintf("W%02X", $value);
  }

  elsif($reading =~ /^io[0-7]$/) {
        return $u1 if(int(@a) !=3);
	$value= $a[2];
	return $u1 unless($value eq "0" || $value eq "1");
        $msg= "D" . substr($reading,2,1) . $value;
  }

  else { return $u1; }
		
  my $d = M232GetData($hash, $msg);
  return "Read error" if(!defined($d));
  return $d;
}

#####################################
sub
M232_Get($@)
{

  my ($hash, @a) = @_;
  my $u1 = "Usage: get <name> [an0..an5]\n" .
                  "get <name> [io0..io7]\n" .
                  "get <name> octet\n" .
                  "get <name> counter";

  return $u1 if(int(@a) != 2);

  my $name= $a[0];
  my $reading= $a[1];
  my $msg;
  my $retval;
  my ($count,$d,$state,$iscurrent,$voltage);


  if($reading eq "counter") {
	$msg= "z";
  	$d = M232GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$count= hex $d;
	$retval= $count;
  } 

  elsif($reading =~  /^an[0-5]$/) {
	$msg= "a" . substr($reading,2,1);
  	$d = M232GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$voltage= (hex substr($d,0,3))*5.00/1024.0;
	$iscurrent= substr($d,3,1);
	$retval= $voltage; # . " " . $iscurrent;
  } 
  
  elsif($reading =~ /^io[0-7]$/) {
	$msg= "d" . substr($reading,2,1);
  	$d = M232GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$state= hex $d;
	$retval= $state;
  } 

  elsif($reading eq "octet") {
	$msg= "w"; 
  	$d = M232GetData($hash, $msg);
 	return "Read error" if(!defined($d));
	$state= hex $d;
	$retval= $state;
  } 

  else { return $u1; }

  $hash->{READINGS}{$reading}{VAL}= $retval;
  $hash->{READINGS}{$reading}{TIME}= TimeNow();

  return "$name $reading => $retval";
		
}

#####################################
sub
M232_Write($$)
{
  my ($hash,$msg) = @_;

  return M232GetData($hash, $msg);
}


#####################################
sub
M232GetData($$)
{
  my ($hash, $data) = @_;
  my $dev=$hash->{DeviceName};
  my $MSGSTART= chr 1;
  my $MSGEND= chr 13;
  my $MSGACK= chr 6;
  my $MSGNACK= chr 21;
  my $serport;
  my $d = $MSGSTART . $data . $MSGEND;

  if ($^O eq 'MSWin32') {
    $serport=new Win32::SerialPort ($dev, 1);
  }else{
    $serport=new Device::SerialPort ($dev, 1);
  }
  if(!$serport) {
    Log 3, "M232: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(2400);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');
  $serport->write_settings;
  $hash->{po}=$serport;
  Log 4, "M232: Sending $d";

  my $rm = "M232: ?";

  $serport->lookclear;
  $serport->write($d);

  my $retval = "";
  my $status = "";
  my $nfound=0;
  my $ret=undef;
  sleep(1);
  for(;;) {
    if ($^O eq 'MSWin32') {
      $nfound=M232_Ready($hash,undef);
    }else{
      my ($rout, $rin) = ('', '');
      vec($rin, $serport->FILENO, 1) = 1;
       $nfound = select($rin, undef, undef, 1.0); # 3 seconds timeout
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        $rm="M232:Select error $nfound / $!";
	last;
      }
    }
      
      last if($nfound == 0);

      my $out = $serport->read(1);
      if(!defined($out) || length($out) == 0) {
        $rm = "M232 EOF on $dev";
        last;
      }

      if($out eq $MSGACK) {
      	$rm= "M232: acknowledged";
	Log 4, "M232: return value \'" . $retval . "\'";
	$status= "ACK";
      } elsif($out eq $MSGNACK) {
        $rm= "M232: not acknowledged";
	$status= "NACK";
	$retval= undef;
      } else {
      	$retval .= $out;
      }

      if($status) {
	$ret=$retval;
	last;
      }
	
  }

DONE:
  $serport->close();
  undef $serport;
  delete $hash->{po} if exists($hash->{po});
  Log 4, $rm;
  return $ret;
}

1;

=pod
=begin html

<a name="M232"></a>
<h3>M232</h3>
<ul>
  <br>

  <a name="M232define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; M232 &lt;m232-device&gt;</code>
    <br><br>

    Define a M232 device. You can attach as many M232 devices as you like. A
    M232 device provides 6 analog inputs (voltage 0..5V with 10 bit resolution)
    and 8 bidirectional digital ports. The eighth digital port can be used as a
    16 bit counter (maximum frequency 3kHz). The M232 device needs to be
    connected to a 25pin sub-d RS232 serial port. A USB-to-serial converter
    works fine if no serial port is available.<br><br>

    Examples:
    <ul>
      <code>define m232 M232 /dev/ttyUSB2</code><br>
    </ul>
    <br>
  </ul>

  <a name="M232set"></a>
  <b>Set </b>
  <ul>
    <code>set &lt;name&gt; stop</code>
    <br><br>
    Stops the counter.
    <br><br>
    <code>set &lt;name&gt; start</code>
    <br><br>
    Resets the counter to zero and starts it.
    <br><br>
    <code>set &lt;name&gt; octet <value></code>
    <br><br>
    Sets the state of all digital ports at once, value is 0..255.
    <br><br>
    <code>set &lt;name&gt; io0..io7 0|1</code>
    <br><br>
    Turns digital port 0..7 off or on.
    <br><br>
  </ul>


  <a name="M232get"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; [an0..an5]</code>
    <br><br>
    Gets the reading of analog input 0..5 in volts.
    <br><br>
    <code>get &lt;name&gt; [io0..io7]</code>
    <br><br>
    Gets the state of digital ports 0..7, result is 0 or 1.
    <br><br>
    <code>get &lt;name&gt; octet</code>
    <br><br>
    Gets the state of all digital ports at once, result is 0..255.
    <br><br>
    <code>get &lt;name&gt; counter</code>
    <br><br>
    Gets the number of ticks of the counter since the last reset. The counter
    wraps around from 65,535 to 0 and <i>then stops</i>.
    See <a href="#M232Counter">M232Counter</a> for how we care about this.
    <br><br>
  </ul>


  <a name="M232attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#model">model</a> (m232)</li>
  </ul>
  <br>

</ul>


=end html
=cut

#
#
# 80_M232.pm
# written by Dr. Boris Neubert 2007-11-26
# e-mail: omega at online dot de
#
##############################################
package main;

use strict;
use warnings;
use Device::SerialPort;

sub M232Write($$);
sub M232GetData($$);

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

  delete $hash->{PortObj};
  delete $hash->{FD};

  my $dev = $a[2];
  $attr{$a[0]}{savefirst} = 1;

  if($dev eq "none") {
    Log 1, "M232 device is none, commands will be echoed only";
    return undef;
  }

  Log 3, "M232 opening device $dev";
  my $po = new Device::SerialPort ($dev);
  return "Can't open $dev: $!" if(!$po);
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
        Log GetLogLevel($name,2), "deleting port for $d";
        delete $defs{$d}{IODev};
      }
  }
  return undef;
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


  if($reading eq "auto") {
        return $u1 if(int(@a) !=3);
	my $value= $a[2];
        my @legal= (0..5,"none");
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
	my $value= $a[2];
        my @legal= (0..255);
        if(!grep($value eq $_, @legal)) {
                return "Illegal value $value, possible values: 0..255";
        }
	$msg= sprintf("W%02X", $value);
  }

  elsif($reading =~ /^io[0-7]$/) {
        return $u1 if(int(@a) !=3);
	my $value= $a[2];
	return $u1 unless($value eq "0" || $value eq "1");
        $msg= "D" . substr($reading,2,1) . $value;
  }

  else { return $u1; }
		
  my $d = M232GetData($hash->{DeviceName}, $msg);
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


  if($reading eq "counter") {
	$msg= "z";
  	my $d = M232GetData($hash->{DeviceName}, $msg);
 	return "Read error" if(!defined($d));
	my $count= hex $d;
	$retval= $count;
  } 

  elsif($reading =~  /^an[0-5]$/) {
	$msg= "a" . substr($reading,2,1);
  	my $d = M232GetData($hash->{DeviceName}, $msg);
 	return "Read error" if(!defined($d));
	my $voltage= (hex substr($d,0,3))*5.00/1024.0;
	my $iscurrent= substr($d,3,1);
	$retval= $voltage; # . " " . $iscurrent;
  } 
  
  elsif($reading =~ /^io[0-7]$/) {
	$msg= "d" . substr($reading,2,1);
  	my $d = M232GetData($hash->{DeviceName}, $msg);
 	return "Read error" if(!defined($d));
	my $state= hex $d;
	$retval= $state;
  } 

  elsif($reading eq "octet") {
	$msg= "w"; 
  	my $d = M232GetData($hash->{DeviceName}, $msg);
 	return "Read error" if(!defined($d));
	my $state= hex $d;
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

  return M232GetData($hash->{DeviceName}, $msg);
}


#####################################
sub
M232GetData($$)
{
  my ($dev, $d) = @_;

  my $MSGSTART= chr 1;
  my $MSGEND= chr 13;
  my $MSGACK= chr 6;
  my $MSGNACK= chr 21;

  $d = $MSGSTART . $d . $MSGEND;

  my $serport = new Device::SerialPort ($dev);
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

  Log 4, "M232: Sending $d";

  my $rm = "M232: ?";

  $serport->lookclear;
  $serport->write($d);

  my $retval = "";
  my $status = "";

  for(;;) {
      my ($rout, $rin) = ('', '');
      vec($rin, $serport->FILENO, 1) = 1;
      my $nfound = select($rout=$rin, undef, undef, 1.0);

      if($nfound < 0) {
        $rm = "M232: Select error $nfound / $!";
        goto DONE;
      }
      last if($nfound == 0);

      my $out = $serport->read(1);
      if(!defined($out) || length($out) == 0) {
        $rm = "M232 EOF on $dev";
        goto DONE;
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
      	$serport->close();
  	Log 4, $rm;
	return $retval;
      }
	
  }

DONE:
  $serport->close();
  Log 4, $rm;
  return undef;
}

1;

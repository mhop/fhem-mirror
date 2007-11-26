##############################################
package main;

use strict;
use warnings;
use Device::SerialPort;

#####################################
sub
SCIVT_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "SCIVT_Define";
  $hash->{GetFn}   = "SCIVT_Get";
  $hash->{AttrList}= "model:SCD loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
SCIVT_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "Define the serial device as a parameter, use none for a fake device"
        if(@a != 3);
  $hash->{STATE} = "Initialized";

  my $dev = $a[2];

  Log 1, "SCIVT device is none, commands will be echoed only"
    if($dev eq "none");

  if($dev ne "none") {
    Log 2, "SCIVT opening device $dev";
    my $po = new Device::SerialPort ($dev);
    return "Can't open $dev: $!" if(!$po);
    Log 2, "SCIVT opened device $dev";
    $po->close();
  }

  $hash->{DeviceName} = $dev;

  SCIVT_GetStatus($hash);
  return undef;
}


#####################################
sub
SCIVT_Get($@)
{
  my ($hash, @a) = @_;

  return "get for an SCIVT device needs exactly one parameter" if(@a != 2);

  my $v;
  if($a[1] eq "data") {
    $v = SCIVT_GetLine($hash->{DeviceName});
    $v =~ s/[\r\n]//g;                          # Delete the NewLine
  } else {
    return "Unknown argument $a[1], must be data";
  }

  $hash->{READINGS}{$a[1]}{VAL} = $v;
  $hash->{READINGS}{$a[1]}{TIME} = TimeNow();

  return "$a[0] $a[1] => $v";
}

#####################################
sub
SCIVT_GetStatus($)
{
  my ($hash) = @_;

  # Call us in 5 minutes again.
  InternalTimer(gettimeofday()+300, "SCIVT_GetStatus", $hash, 0);

  my $dnr = $hash->{DEVNR};
  my $name = $hash->{NAME};

  my %vals;
  my $result = SCIVT_GetLine($hash->{DeviceName});

  if(!defined($result)) 
    {
    Log GetLogLevel($name,2), "SCIVT read error, retry";
    $result = SCIVT_GetLine($hash->{DeviceName});
    }

  if(!defined($result)) 
    {
    Log GetLogLevel($name,2), "SCIVT read error, abort";
    $hash->{STATE} = "timeout";
    return $hash->{STATE};
    }
  if (length($result) < 10)
    {
    Log GetLogLevel($name,2), "SCIVT incomplete line ($result)";
    $hash->{STATE} = "incomplete";
    }
  else
    {
    $result =~ s/^.*R://;
    $result =~ s/[\r\n ]//g;   
    Log GetLogLevel($name,2), "SCIVT $result (raw)";
    $result=~ s/,/./g;
    my @data = split(";", $result);
    
    my @names = ("Vs", "Is", "Temp", "minV", "maxV", "minI", "maxI");
    my $tn = TimeNow();
    for(my $i = 0; $i < int(@names); $i++) {
      $hash->{CHANGED}[$i] = "$names[$i]: $data[$i]";
      $hash->{READINGS}{$names[$i]}{TIME} = $tn;
      $hash->{READINGS}{$names[$i]}{VAL} = $data[$i];
    }
    
    DoTrigger($name, undef) if($init_done);

    $result =~ s/;/ /g;  
    $hash->{STATE} = "$result";
    }

  return $hash->{STATE};
}

#####################################
sub
SCIVT_GetLine($)
{
  my $retry = 0;
  my ($dev) = @_;

  return "R:13,66; 0,0;30;13,62;15,09;- 0,2; 2,8;\n"
        if($dev eq "none");       # Fake-mode

  my $serport = new Device::SerialPort ($dev);
  if(!$serport) {
    Log 1, "SCIVT: Can't open $dev: $!";
    return undef;
  }
  $serport->reset_error();
  $serport->baudrate(1200);
  $serport->databits(8);
  $serport->parity('none');
  $serport->stopbits(1);
  $serport->handshake('none');

  my $rm = "SCIVT timeout reading the answer";
  my $data="";

  $serport->write('F');
  sleep(1);

  for(;;) 
   {
    my ($rout, $rin) = ('', '');
    vec($rin, $serport->FILENO, 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, 3.0);

    if($nfound < 0) {
      $rm = "SCIVT Select error $nfound / $!";
      goto DONE;
    }
    last if($nfound == 0);

    my $buf = $serport->input();
    if(!defined($buf) || length($buf) == 0) {
      $rm = "SCIVT EOF on $dev";
      goto DONE;
    }


    $data .= $buf;
    if($data =~ m/[\r\n]/) {    # Newline received
      $serport->close();
      return $data;
    }
  }

DONE:
  $serport->close();
  Log 3, "SCIVT $rm";
  return undef;
}

1;

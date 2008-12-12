##############################################
package main;

use strict;
use warnings;
use Device::SerialPort;
use IO::Socket::INET;

my $fs10data = "";
my $pcwsdsocket;


#####################################
sub
FS10_Initialize($)
{
  my ($hash) = @_;

  # Consumer
  $hash->{DefFn}   = "FS10_Define";
  $hash->{AttrList}= "model:FS10 loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
FS10_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  Log 3, "FS10 Define: $a[0] $a[1] $a[2] $a[3]";

  return "Define the host and portnr as a parameter i.e. 127.0.0.1 4711"
          if(@a != 4);

  $hash->{Timer} = 600;
  $hash->{Host} = $a[2];
  $hash->{Port} = $a[3];
  $hash->{STATE} = "Initialized";

  my $dev = $a[2];
  Log 1, "FS10 device is none, commands will be echoed only"
      if($dev eq "none");

  $hash->{DeviceName} = $dev;

  FS10_GetStatus($hash);
  return undef;
}


#####################################
sub
FS10_GetStatus($)
{
  my ($hash) = @_;
  my $buf;
  #my $banner;
  my $reqcmd;
  my $fs10time;
  my $dt;
  my $x;
  my $result = "";

  Log 3, "FS10_GetStatus";

  # Call us in 5 minutes again.
  InternalTimer(gettimeofday()+300, "FS10_GetStatus", $hash, 0);

  my $dnr = $hash->{DEVNR};
  my $name = $hash->{NAME};
  my $host = $hash->{Host};
  my $port = $hash->{Port};
  my %vals;
  my $pcwsd ="$host:$port";
  my $pcwsdsocket = IO::Socket::INET->new( $pcwsd )
  or return "FS10 Can't bind to pcwsd" if(!$pcwsdsocket);

  my $banner = $pcwsdsocket->getline();
  my @x = split(" ", $banner);
  my @y;
  my $fs10name;

  for(my $i = 0; $i < 8; $i++) #Outdoor
     {
     $fs10name ="Ta$i";
     $reqcmd = "get od2temp $i\r\n";
     $pcwsdsocket->print($reqcmd);
     $buf = $pcwsdsocket->getline();
     $result = "$result $buf";

     @x = split(" ", $buf);
     $fs10time = FmtDateTime($x[1]);

     $hash->{CHANGED}[$i] = "Ta$i: $x[0]";
     $hash->{READINGS}{$fs10name}{TIME} = $fs10time;
     $hash->{READINGS}{$fs10name}{VAL} = $x[0];
     }

  $fs10name="Ti";
     $reqcmd = "get idtemp 7\r\n";
     $pcwsdsocket->print($reqcmd);
     $buf = $pcwsdsocket->getline();
     @x = split(" ", $buf);
     $fs10time = FmtDateTime($x[1]);

     $hash->{CHANGED}[8] = "Ti: $x[0]";
     $hash->{READINGS}{$fs10name}{TIME} = $fs10time;
     $hash->{READINGS}{$fs10name}{VAL} = $x[0];

  $fs10name="Rain";
     $reqcmd = "get rain 7\r\n";
     $pcwsdsocket->print($reqcmd);
     $buf = $pcwsdsocket->getline();
     @x = split(" ", $buf);
     $fs10time = FmtDateTime($x[1]);

     $hash->{CHANGED}[9] = "Rain: $x[0]";
     $hash->{READINGS}{$fs10name}{TIME} = $fs10time;
     $hash->{READINGS}{$fs10name}{VAL} = $x[0];

  $fs10name="Sun";
     $reqcmd = "get bright 7\r\n";
     $pcwsdsocket->print($reqcmd);
     $buf = $pcwsdsocket->getline();
     @x = split(" ", $buf);
     $fs10time = FmtDateTime($x[1]);

     $hash->{CHANGED}[10] = "Sun: $x[0]";
     $hash->{READINGS}{$fs10name}{TIME} = $fs10time;
     $hash->{READINGS}{$fs10name}{VAL} = $x[0];

  $fs10name="Windspeed";
     $reqcmd = "get wspd 7\r\n";
     $pcwsdsocket->print($reqcmd);
     $buf = $pcwsdsocket->getline();
     @x = split(" ", $buf);
     $fs10time = FmtDateTime($x[1]);

     $hash->{CHANGED}[11] = "Windspeed: $x[0]";
     $hash->{READINGS}{$fs10name}{TIME} = $fs10time;
     $hash->{READINGS}{$fs10name}{VAL} = $x[0];

  close($pcwsdsocket);

  $result =~ s/[\r\n]//g;   
  DoTrigger($name, undef) if($init_done);

  $hash->{STATE} = "$result";
  Log 3,"FS10 Result: $result";
  return $hash->{STATE};
}

#####################################
sub
FS10Log($$)
{
  my ($a1, $a2) = @_;

  #define n31 notify fs10 {FS10Log("@", "%")}
  #define here notify action

  Log 2,"FS10 $a1 = $a2 old: $oldvalue{$a1}{TIME}=> $oldvalue{$a1}{VAL});";
}

1;

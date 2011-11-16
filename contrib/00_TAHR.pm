###############################################
# Sample fhem module, one-level approach, controlling a single device like a
# directly attached heating regulator.
# The alternative is a two level approach, where a physical device like a CUL
# is a bridge to a large number of logical devices (like FS20 actors, S300
# sensors, etc)

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub TAHR_Read($);
sub TAHR_Ready($);
sub TAHR_setbits($$);
sub TAHR_SetReading($$$$);

my %tahr_sets = (
  "ww_soll"         => "0C07656565%02x6565",
  "ww_betriebsart"  => "0C0E%02x6565656565", 
);


sub
TAHR_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{ReadFn}  = "TAHR_Read";
  $hash->{ReadyFn} = "TAHR_Ready";
  $hash->{DefFn}   = "TAHR_Define";
  $hash->{UndefFn} = "TAHR_Undef";
  $hash->{SetFn}   = "TAHR_Set";
  $hash->{AttrList}= "do_not_notify:1,0 loglevel:0,1,2,3,4,5,6";
}

#####################################
sub
TAHR_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> TAHR [devicename|none]"
    if(@a != 3);

  DevIo_CloseDev($hash);
  my $name = $a[0];
  my $dev = $a[2];

  if($dev eq "none") {
    Log 1, "TAHR device is none, commands will be echoed only";
    return undef;
  }
  
  $hash->{DeviceName} = $dev;
  my $ret = DevIo_OpenDev($hash, 0, "TAHR_Poll");
  return $ret;
}


#####################################
sub
TAHR_Undef($$)
{
  my ($hash, $arg) = @_;
  DevIo_CloseDev($hash); 
  RemoveInternalTimer($hash);
  return undef;
}

#####################################
sub
TAHR_Set($@)
{
  my ($hash, @a) = @_;

  return "\"set TAHR\" needs at least an argument" if(@a < 2);

  my $cmd = $tahr_sets{$a[1]};
  return "Unknown argument $a[1], choose one of " . 
                join(" ", sort keys %tahr_sets) if(!defined($cmd));
  # FIXME
  DevIo_SimpleWrite($hash, $cmd);
  return undef;
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
TAHR_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my ($data, $crc);

  my $buf = DevIo_SimpleRead($hash);
  return "" if(!defined($buf));

  $buf = unpack('H*', $buf);
  Log 5, "RAW: $buf";

  ######################################
  # Analyze the data
  my $tn = TimeNow();
  my ($key, $val) = ("key", "val");

  # FIXME
  TAHR_SetReading($hash, $tn, $key, $val);
}

#####################################
sub
TAHR_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, undef)
                if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  return ($InBytes>0);
}

sub
TAHR_Poll($)
{
  my ($hash) = @_;
  return if($hash->{STATE} eq "disconnected");
  # FIXME
  DevIo_SimpleWrite($hash, "02"); # Request data
  InternalTimer(gettimeofday()+5, "TAHR_Poll", $hash, 0);
}

sub
TAHR_SetReading($$$$)
{
  my ($hash,$tn,$key,$val) = @_;
  my $name = $hash->{NAME};
  Log GetLogLevel($name,4), "$name: $key $val";
  $hash->{READINGS}{$key}{TIME} = $tn;
  $hash->{READINGS}{$key}{VAL} = $val;
  DoTrigger($name, "$key: $val");
}


1;

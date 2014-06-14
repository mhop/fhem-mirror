##########################################################################
# This file is part of the smarthomatic module for FHEM.
#
# Copyright (c) 2014 Stefan Baumann
#
# You can find smarthomatic at www.smarthomatic.org.
# You can find FHEM at www.fhem.de.
#
# This file is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This file is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with smarthomatic. If not, see <http://www.gnu.org/licenses/>.
###########################################################################
# $Id: 37_SHC.pm xxxx 2014-xx-xx xx:xx:xx rr2000 $

package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub SHC_Parse($$$$);
sub SHC_Read($);
sub SHC_ReadAnswer($$$$);
sub SHC_Ready($);

sub SHC_SimpleWrite(@);

my $clientsSHC = ":SHCdev:BASE:xxx:";

my %matchListSHC = (
  "1:SHCdev" => "^Packet Data: SenderID=[1-9]|0[1-9]|[1-9][0-9]|[0-9][0-9][0-9]|[0-3][0-9][0-9][0-9]|40[0-8][0-9]|409[0-6]",    #1-4096 with leading zeros
  "2:xxx"     => "^\\S+\\s+22",
  "3:xxx"     => "^\\S+\\s+11",
  "4:xxx"     => "^\\S+\\s+9 ",
);

sub SHC_Initialize($)
{
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  # Provider
  $hash->{ReadFn}  = "SHC_Read";
  $hash->{WriteFn} = "SHC_Write";
  $hash->{ReadyFn} = "SHC_Ready";

  # Normal devices
  $hash->{DefFn}      = "SHC_Define";
  $hash->{UndefFn}    = "SHC_Undef";
  $hash->{GetFn}      = "SHC_Get";
  $hash->{SetFn}      = "SHC_Set";
  $hash->{ShutdownFn} = "SHC_Shutdown";
}

#####################################
sub SHC_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  if (@a != 3) {
    my $msg = "wrong syntax: define <name> SHC {devicename[\@baudrate] " . "| devicename\@directio}";
    Log3 undef, 2, $msg;
    return $msg;
  }

  DevIo_CloseDev($hash);

  my $name = $a[0];
  my $dev  = $a[2];
  $dev .= "\@19200" if ($dev !~ m/\@/);

  $hash->{Clients}    = $clientsSHC;
  $hash->{MatchList}  = \%matchListSHC;
  $hash->{DeviceName} = $dev;

  my $ret = DevIo_OpenDev($hash, 0, "SHC_DoInit");
  return $ret;
}

#####################################
sub SHC_Undef($$)
{
  my ($hash, $arg) = @_;
  my $name = $hash->{NAME};

  foreach my $d (sort keys %defs) {
    if ( defined($defs{$d})
      && defined($defs{$d}{IODev})
      && $defs{$d}{IODev} == $hash)
    {
      my $lev = ($reread_active ? 4 : 2);
      Log3 $name, $lev, "$name: deleting port for $d";
      delete $defs{$d}{IODev};
    }
  }

  SHC_Shutdown($hash);
  DevIo_CloseDev($hash);
  return undef;
}

#####################################
sub SHC_Shutdown($)
{
  my ($hash) = @_;
  return undef;
}

#####################################
sub SHC_Set($@)
{
  my ($hash, @a) = @_;

  my $name = shift @a;
  my $cmd  = shift @a;
  my $arg  = join("", @a);

  my $list = "raw:noArg";
  return $list if ($cmd eq '?');

  if ($cmd eq "raw") {

    #return "\"set SHC $cmd\" needs exactly one parameter" if(@_ != 4);
    #return "Expecting a even length hex number" if((length($arg)&1) == 1 || $arg !~ m/^[\dA-F]{12,}$/ );
    Log3 $name, 4, "$name: set $name $cmd $arg";
    SHC_SimpleWrite($hash, $arg);

  } else {
    return "Unknown argument $cmd, choose one of " . $list;
  }

  return undef;
}

#####################################
sub SHC_Get($@)
{
  my ($hash, $name, $cmd) = @_;

  return undef;
}

#####################################
sub SHC_DoInit($)
{
  my $hash = shift;
  my $name = $hash->{NAME};
  my $err;
  my $msg = undef;

  $hash->{STATE} = "Initialized";

  return undef;
}

#####################################
# This is a direct read for commands like get
# Anydata is used by read file to get the filesize
sub SHC_ReadAnswer($$$$)
{
  # TODO: Not adapted to SHC, copy from 36_JeeLink.pm
  my ($hash, $arg, $anydata, $regexp) = @_;
  my $type = $hash->{TYPE};
  my $name = $hash->{NAME};

  return ("No FD", undef)
    if (!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));

  my ($mpandata, $rin) = ("", '');
  my $buf;
  my $to = 3;    # 3 seconds timeout
  $to = $hash->{RA_Timeout} if ($hash->{RA_Timeout});    # ...or less
  for (; ;) {

    if ($^O =~ m/Win/ && $hash->{USBDev}) {
      $hash->{USBDev}->read_const_time($to * 1000);      # set timeout (ms)
                                                         # Read anstatt input sonst funzt read_const_time nicht.
      $buf = $hash->{USBDev}->read(999);
      return ("Timeout reading answer for get $arg", undef)
        if (length($buf) == 0);

    } else {
      return ("Device lost when reading answer for get $arg", undef)
        if (!$hash->{FD});

      vec($rin, $hash->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if ($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        DevIo_Disconnected($hash);
        return ("SHC_ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if ($nfound == 0);
      $buf = DevIo_SimpleRead($hash);
      return ("No data", undef) if (!defined($buf));

    }

    if ($buf) {
      Log3 $hash->{NAME}, 5, "$name: SHC/RAW (ReadAnswer): $buf";
      $mpandata .= $buf;
    }

    chop($mpandata);
    chop($mpandata);

    return (
      undef, $mpandata
      );
  }

}

#####################################
sub SHC_Write($$)
{
  # TODO: Not adapted to SHC, copy from 36_JeeLink.pm
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "$name: sending $msg";

  SHC_SimpleWrite($hash, $msg);
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub SHC_Read($)
{
  # TODO: Verify if partial data handling is required for SHC
  my ($hash) = @_;

  my $buf = DevIo_SimpleRead($hash);
  return "" if (!defined($buf));

  my $name = $hash->{NAME};

  my $pandata = $hash->{PARTIAL};
  Log3 $name, 5, "$name: SHC/RAW: $pandata/$buf";
  $pandata .= $buf;

  while ($pandata =~ m/\n/) {
    my $rmsg;
    ($rmsg, $pandata) = split("\n", $pandata, 2);
    $rmsg =~ s/\r//;
    SHC_Parse($hash, $hash, $name, $rmsg) if ($rmsg);
  }
  $hash->{PARTIAL} = $pandata;
}

#####################################
sub SHC_Parse($$$$)
{
  my ($hash, $iohash, $name, $rmsg) = @_;
  my $dmsg = $rmsg;

  next if (!$dmsg || length($dmsg) < 1);    # Bogus messages

  if ($dmsg !~ m/^Packet Data: SenderID=/) {

    # Messages just to dipose
    if ( $dmsg =~ m/^\*\*\* Enter AES key nr/
      || $dmsg =~ m/^\*\*\* Received character/)
    {
      return;
    }

    # -Verbosity level 5
    if ( $dmsg =~ m/^Received \(AES key/
      || $dmsg =~ m/^Received garbage/
      || $dmsg =~ m/^Before encryption/
      || $dmsg =~ m/^After encryption/
      || $dmsg =~ m/^Repeating request./
      || $dmsg =~ m/^Request Queue empty/
      || $dmsg =~ m/^Removing request from request buffer/)
    {
      Log3 $name, 5, "$name: $dmsg";
      return;
    }

    # -Verbosity level 4
    if ( $dmsg =~ m/^Request added to queue/
      || $dmsg =~ m/^Request Buffer/
      || $dmsg =~ m/^Request (q|Q)ueue/)
    {
      Log3 $name, 4, "$name: $dmsg";
      return;
    }

    # Anything else in verbosity level 3
    Log3 $name, 3, "$name: $dmsg";
    return;
  }

  $hash->{"${name}_MSGCNT"}++;
  $hash->{"${name}_TIME"} = TimeNow();
  $hash->{RAWMSG} = $rmsg;
  my %addvals = (RAWMSG => $rmsg);

  Dispatch($hash, $dmsg, \%addvals);
}

#####################################
sub SHC_Ready($)
{
  my ($hash) = @_;

  return DevIo_OpenDev($hash, 1, "SHC_DoInit")
    if ($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
  if ($po) {
    ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
  }
  return ($InBytes && $InBytes > 0);
}

########################
sub SHC_SimpleWrite(@)
{
  my ($hash, $msg) = @_;
  return if (!$hash);

  my $name = $hash->{NAME};
  Log3 $name, 5, "$name: SW: $msg";

  $msg .= "\r";

  $hash->{USBDev}->write($msg) if ($hash->{USBDev});
  syswrite($hash->{DIODev}, $msg) if ($hash->{DIODev});

  # Some linux installations are broken with 0.001, T01 returns no answer
  select(undef, undef, undef, 0.01);
}

1;

=pod
=begin html

<a name="SHC"></a>
<h3>SHC</h3>
<ul>
  SHC is the basestation module that supports a family of RF devices available 
  at <a href="http://http://www.smarthomatic.org">www.smarthomatic.org</a>.

  This module provides the IODevice for the <a href="#SHCdev">SHCdev</a> 
  modules that implement the SHCdev protocol.<br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.<br><br>

  <a name="SHC_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SHC &lt;device&gt;</code><br>
    <br>
      &lt;device&gt; specifies the serial port to communicate with the SHC.
      The name of the serial-device depends on your distribution, under
      linux usually a /dev/ttyUSB0 device will be created.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyUSB0@57600. Please note that the default
      baudrate for the SHC base station is 19200 baud.<br><br>

      Example:<br>
      <ul>
        <code>define shc_base SHC /dev/ttyUSB0</code><br><br>
      </ul>
  </ul>

  <a name="SHC_Set"></a>
  <b>Set</b>
  <ul>
    <li>raw &lt;data&gt;<br>
        not supported yet
    </li><br>
  </ul>

  <a name="SHC_Get"></a>
  <b>Get</b>
  <ul>
    <li>
      N/A
    </li><br>
  </ul>

  <a name="SHC_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>
      N/A
    </li><br>
  </ul>
</ul>

=end html
=cut

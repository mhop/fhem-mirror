##############################################################################
#
# 70_SolarView.pm
#
# A FHEM module to read power/energy values from solarview.
#
# written 2012 by Tobe Toben <fhem@toben.net>
#
# $Id$
#
##############################################################################
#
# SolarView is a powerful datalogger for photovoltaic systems that runs on
# an AVM Fritz!Box (and also on x86 systems). For details see the SV homepage:
# http://www.amhamberg.de/solarview_fritzbox.aspx
#
# SV supports many different inverters. To read the SV power values using
# this module, a TCP-Server must be enabled for SV by adding the parameter
# "-TCP <port>" to the startscript (see the SV manual).
#
# usage:
# define <name> SolarView <host> <port> [<interval> [<timeout>]]
#
# If <interval> is positive, new values are read every <interval> seconds.
# If <interval> is 0, new values are read whenever a get request is called 
# on <name>. The default for <interval> is 300 (i.e. 5 minutes).
#
# get <name> <key>
#
# where <key> is one of currentPower, totalEnergy, totalEnergyDay, 
# totalEnergyMonth, totalEnergyYear, UDC, IDC, UDCB, IDCB, UDCC, IDCC,
# gridVoltage, gridPower and temperature.
#
##############################################################################
#
# Copyright notice
#
# (c) 2012 Tobe Toben <fhem@toben.net>
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# The GNU General Public License can be found at
# http://www.gnu.org/copyleft/gpl.html.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# This copyright notice MUST APPEAR in all copies of the script!
#
##############################################################################

package main;

use strict;
use warnings;

use IO::Socket::INET;

my @gets = ('totalEnergyDay',            # kWh
            'totalEnergyMonth',          # kWh
            'totalEnergyYear',           # kWh
            'totalEnergy',               # kWh
            'currentPower',              # W
            'UDC', 'IDC', 'UDCB',        # V, A, V
            'IDCB', 'UDCC', 'IDCC',      # A, V, A
            'gridVoltage', 'gridPower',  # V, A
            'temperature');              # °C

sub
SolarView_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "SolarView_Define";
  $hash->{UndefFn}  = "SolarView_Undef";
  $hash->{GetFn}    = "SolarView_Get";
  $hash->{AttrList} = "loglevel:0,1,2,3,4,5";
}

sub
SolarView_Define($$)
{
  my ($hash, $def) = @_;

  my @args = split("[ \t]+", $def);

  if (@args < 4)
  {
    return "SolarView_Define: too few arguments. Usage:\n" .
           "define <name> SolarView <host> <port> [<interval> [<timeout>]]";
  }

  $hash->{Host}     = $args[2];
  $hash->{Port}     = $args[3];
  $hash->{Interval} = (@args>=5) ? int($args[4]) : 300;
  $hash->{Timeout}  = (@args>=6) ? int($args[5]) : 4;

  $hash->{Invalid}  = -1;
  $hash->{NightOff} = 1;
  $hash->{Debounce} = 50;
  $hash->{Sleep}    = 0;

  $hash->{STATE} = 'Initializing';

  my $timenow = TimeNow();

  for my $get (@gets)
  {
    $hash->{READINGS}{$get}{VAL}  = $hash->{Invalid};
    $hash->{READINGS}{$get}{TIME} = $timenow;
  }

  SolarView_Update($hash);

  Log 2, "$hash->{NAME} will read from solarview at $hash->{Host}:$hash->{Port} " . 
         ($hash->{Interval} ? "every $hash->{Interval} seconds" : "for every 'get $hash->{NAME} <key>' request");

  return undef;
}

sub
SolarView_Update($)
{
  my ($hash) = @_;

  if ($hash->{Interval} > 0) {
    InternalTimer(gettimeofday() + $hash->{Interval}, "SolarView_Update", $hash, 0);
  }

  # if NightOff is set and there has been a successful 
  # reading before, then skip this update "at night"
  #
  if ($hash->{NightOff} and $hash->{READINGS}{currentPower}{VAL} != $hash->{Invalid})
  {
    my ($sec,$min,$hour) = localtime(time);
    return undef if ($hour < 6 or $hour > 22);
  }

  sleep($hash->{Sleep}) if $hash->{Sleep};

  Log 4, "$hash->{NAME} tries to connect solarview at $hash->{Host}:$hash->{Port}";

  my $success = 0;

  eval {
    local $SIG{ALRM} = sub { die 'timeout'; };
    alarm $hash->{Timeout};

    my $socket = IO::Socket::INET->new(PeerAddr => $hash->{Host}, 
                                       PeerPort => $hash->{Port}, 
                                       Timeout  => $hash->{Timeout});

    if ($socket and $socket->connected())
    {
      $socket->autoflush(1);
      print $socket "00*\r\n";
      my $res = <$socket>;
      close($socket);

      alarm 0;

      if ($res and $res =~ /^\{(00,[\d\.,]+)\},/)
      {
        my @vals = split(/,/, $1);

        my $tn = sprintf("%04d-%02d-%02d %02d:%02d:00",
                   $vals[3], $vals[2], $vals[1], $vals[4], $vals[5]);

        my $cpVal  = $hash->{READINGS}{currentPower}{VAL};
        my $cpTime = $hash->{READINGS}{currentPower}{TIME};

        for my $i (6..19)
        {
          my $getIdx = $i-6;

          if (defined($vals[$i]))
          {
            $hash->{READINGS}{$gets[$getIdx]}{VAL}  = 0 + $vals[$i];
            $hash->{READINGS}{$gets[$getIdx]}{TIME} = $tn;
          }
        }

        # if Debounce is enabled, then skip one drop of
        # currentPower from 'greater than Debounce' to 'Zero'
        #
        if ($hash->{Debounce} > 0 and
            $hash->{Debounce} < $cpVal and
            $hash->{READINGS}{currentPower}{VAL} == 0)
        {
            $hash->{READINGS}{currentPower}{VAL}  = $cpVal;
            $hash->{READINGS}{currentPower}{TIME} = $cpTime;
        }

        $success = 1;
      }
    }
  };

  alarm 0;

  if ($success)
  {
    $hash->{STATE} = 'Initialized';
    Log 4, "$hash->{NAME} got fresh values from solarview";
  } else {
    $hash->{STATE} = 'Failure';
    Log 4, "$hash->{NAME} was unable to get fresh values from solarview";
  }

  return undef;
}

sub
SolarView_Get($@)
{
  my ($hash, @args) = @_;

  return 'SolarView_Get needs two arguments' if (@args != 2);

  SolarView_Update($hash) unless $hash->{Interval};

  my $get = $args[1];
  my $val = $hash->{Invalid};

  if (defined($hash->{READINGS}{$get})) {
    $val = $hash->{READINGS}{$get}{VAL};
  } else {
    return "SolarView_Get: no such reading: $get";
  }

  Log 3, "$args[0] $get => $val";

  return $val;
}

sub
SolarView_Undef($$)
{
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash) if $hash->{Interval};

  return undef;
}

1;


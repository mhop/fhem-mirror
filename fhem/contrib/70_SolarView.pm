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
# totalEnergyMonth, totalEnergyYear and temperature.
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

  $hash->{HOST}     = $args[2];
  $hash->{PORT}     = $args[3];
  $hash->{INTERVAL} = (@args>=5) ? int($args[4]) : 300;
  $hash->{TIMEOUT}  = (@args>=6) ? int($args[5]) : 4;
  $hash->{INVALID}  = -1;

  SolarView_Update($hash);

  $hash->{STATE} = 'Initialized';

  Log 2, "$hash->{NAME} will read power values from solarview at $hash->{HOST}:$hash->{PORT} " . 
         ($hash->{INTERVAL} ? "every $hash->{INTERVAL} seconds" : "for every 'get $hash->{NAME} <key>' request");

  return undef;
}

sub
SolarView_Update($)
{
  my ($hash) = @_;

  my $timenow = TimeNow();

  my %gets = ('totalEnergy'      => $hash->{INVALID},
              'totalEnergyDay'   => $hash->{INVALID},
              'totalEnergyMonth' => $hash->{INVALID},
              'totalEnergyYear'  => $hash->{INVALID},
              'currentPower'     => $hash->{INVALID},
              'temperature'      => $hash->{INVALID},);

  if ($hash->{INTERVAL} > 0) {
    InternalTimer(gettimeofday() + $hash->{INTERVAL}, "SolarView_Update", $hash, 0);
  }

  Log 4, "$hash->{NAME} tries to connect solarview at $hash->{HOST}:$hash->{PORT}";

  eval {
    local $SIG{ALRM} = sub { die 'timeout'; };
    alarm $hash->{TIMEOUT};

    my $socket = IO::Socket::INET->new(PeerAddr => $hash->{HOST}, 
                                       PeerPort => $hash->{PORT}, 
                                       Timeout  => $hash->{TIMEOUT});

    if ($socket and $socket->connected())
    {
      $socket->autoflush(1);
      print $socket "00*\r\n";
      my $res = <$socket>;
      $timenow = TimeNow();
      close($socket);
      alarm 0;

      if ($res and $res =~ /^\{(00,.*)\},.+$/)
      {
        my @vals = split(/,/, $1);

        $gets{'totalEnergyDay'}   = 0 + $vals[6]   if defined($vals[6]);
        $gets{'totalEnergyMonth'} = 0 + $vals[7]   if defined($vals[7]);
        $gets{'totalEnergyYear'}  = 0 + $vals[8]   if defined($vals[8]);
        $gets{'totalEnergy'}      = 0 + $vals[9]   if defined($vals[9]);
        $gets{'currentPower'}     = 0 + $vals[10]  if defined($vals[10]);
        $gets{'temperature'}      = 0 + $vals[19]  if defined($vals[19]);
      }
    }
  };

  alarm 0;

  if ($gets{'currentPower'} != $hash->{INVALID}) {
    Log 4, "$hash->{NAME} got fresh values from solarview, currentPower: $gets{'currentPower'}";
  } else {
    Log 4, "$hash->{NAME} was unable to get fresh values from solarview";
  }

  while ( my ($key,$val) = each(%gets) )
  {
    $hash->{READINGS}{$key}{VAL}  = $val;
    $hash->{READINGS}{$key}{TIME} = $timenow;

    Log 5, "$hash->{NAME} $key => $gets{$key}";
  }

  return undef;
}

sub
SolarView_Get($@)
{
  my ($hash, @args) = @_;

  return 'SolarView_Get needs two arguments' if (@args != 2);

  SolarView_Update($hash) unless $hash->{INTERVAL};

  my $get = $args[1];
  my $val = $hash->{INVALID};

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

  RemoveInternalTimer($hash) if $hash->{INTERVAL};

  return undef;
}

1;


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
# SolarView is a powerful ;) datalogger for photovoltaic systems that runs on
# an AVM Fritz!Box (and also on x86 systems). For details see the SV homepage:
# http://www.solarview.info
#
# SV supports many different inverters. To read the SV power values using
# this module, a TCP-Server must be enabled for SV by adding the parameter
# "-TCP <port>" to the startscript (see the SV manual).
#
# usage:
# define <name> SolarView <host> <port> [wr<i> wr...] [<interval> [<timeout>]]
#
# example: 
# define sv SolarView fritz.box 15000 wr1 wr2 60
#
# If <interval> is positive, new values are read every <interval> seconds.
# If <interval> is 0, new values are read whenever a get request is called 
# on <name>. The default for <interval> is 300 (i.e. 5 minutes).
#
# The parameters wr<i> specify the number(s) of the inverter(s) to be read. 
# When omitted, the sum of all inverters is read. If more than one inverter 
# is specified, the names of the readings are prefixed with the inverter 
# number, e.g. 'wr2_currentPower'.
#
# get <name> [wr<i>_]<key>
#
# where <key> is one of currentPower, totalEnergy, totalEnergyDay, 
# totalEnergyMonth, totalEnergyYear, UDC, IDC, UDCB, IDCB, UDCC, IDCC,
# gridVoltage, gridCurrent and temperature.
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

my @gets = ('totalEnergyDay',               # kWh
            'totalEnergyMonth',             # kWh
            'totalEnergyYear',              # kWh
            'totalEnergy',                  # kWh
            'currentPower',                 # W
            'UDC', 'IDC', 'UDCB',           # V, A, V
            'IDCB', 'UDCC', 'IDCC',         # A, V, A
            'gridVoltage', 'gridCurrent',   # V, A
            'temperature');                 # oC

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

  if (int(@args) < 4)
  {
    return "SolarView_Define: too few arguments. Usage:\n" .
           "define <name> SolarView <host> <port> [wr<i> wr...] [<interval> [<timeout>]]";
  }

  $hash->{Host} = $args[2];
  $hash->{Port} = $args[3];

  # collect the set of inverters which are to be read
  @{$hash->{WRs2Read}} = (0);
  while ((int(@args) >= 5) && ($args[4] =~ /^[Ww][Rr](\d+)$/))
  {
    push @{$hash->{WRs2Read}}, $1 if int($1);
    splice(@args, 4, 1);
  }
  # remove WR0 if exactly one inverter has been specified
  shift @{$hash->{WRs2Read}} if (int(@{$hash->{WRs2Read}}) == 2);

  $hash->{Interval} = int(@args) >= 5 ? int($args[4]) : 300;
  $hash->{Timeout}  = int(@args) >= 6 ? int($args[5]) : 4;

  # config variables
  $hash->{Invalid}    = -1;    # default value for invalid readings
  $hash->{Sleep}      = 0;     # seconds to sleep before connect
  $hash->{Debounce}   = 50;    # minimum level for debouncing (0 to disable)
  $hash->{Rereads}    = 2;     # number of retries when reading curPwr of 0
  $hash->{NightOff}   = 'yes'; # skip connection to SV at night?
  $hash->{UseSVNight} = 'yes'; # use the on/off timings from SV (else: SUNRISE_EL)
  $hash->{UseSVTime}  = '';    # use the SV time as timestamp (else: TimeNow())

  $hash->{STATE} = 'Initializing';

  my $timenow = TimeNow();

  # initialization
  for my $wr (@{$hash->{WRs2Read}})
  {
    $hash->{SolarView_WR($hash, 'Debounced', $wr)}  = 0;

    for my $get (@gets)
    {
      $hash->{READINGS}{SolarView_WR($hash, $get, $wr)}{VAL}  = $hash->{Invalid};
      $hash->{READINGS}{SolarView_WR($hash, $get, $wr)}{TIME} = $timenow;
    }
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
  if ($hash->{NightOff} and SolarView_IsNight($hash) and
      $hash->{READINGS}{currentPower}{VAL} != $hash->{Invalid})
  {
    $hash->{STATE} = '0 W, '.$hash->{READINGS}{totalEnergyDay}{VAL}.' kWh (Night)';
    return undef;
  }

  sleep($hash->{Sleep}) if $hash->{Sleep};

  Log 4, "$hash->{NAME} tries to contact solarview at $hash->{Host}:$hash->{Port}";

  my $success = 0;
  my $timenow = TimeNow();

  for my $wr (@{$hash->{WRs2Read}})
  {
    my %readings = ();
    my $rereads  = $hash->{Rereads};

    eval {
      local $SIG{ALRM} = sub { die 'timeout'; };
      alarm $hash->{Timeout};

      READ_SV:
      my $socket = IO::Socket::INET->new(PeerAddr => $hash->{Host}, 
                                         PeerPort => $hash->{Port}, 
                                         Timeout  => $hash->{Timeout});

      if ($socket and $socket->connected())
      {
        $socket->autoflush(1);
        printf $socket "%02d*\r\n", int($wr);
        my $res = <$socket>;
        close($socket);

        if ($res and $res =~ /^\{(\d\d,[\d\.,]+)\},/)
        {
          my @vals = split(/,/, $1);

          if ($hash->{UseSVTime}) 
          {
            $timenow = sprintf("%04d-%02d-%02d %02d:%02d:00",
                         $vals[3], $vals[2], $vals[1], $vals[4], $vals[5]);
          }

          # parse the result from SV to dedicated values
          for my $i (6..19)
          {
            if (defined($vals[$i]))
            { 
              $readings{$gets[$i - 6]} = 0 + $vals[$i]; 
            }
          }

          # need to reread?
          if ($rereads and $readings{currentPower} == 0)
          { 
            sleep(1);
            $rereads = $rereads - 1;
            goto READ_SV;
          }

          # if Debounce is enabled (>0), then skip one! drop of
          # currentPower from 'greater than Debounce' to 'Zero'
          #
          if ($hash->{Debounce} > 0 and
              $hash->{Debounce} < $hash->{READINGS}{SolarView_WR($hash, 'currentPower', $wr)}{VAL} and
              $readings{currentPower} == 0 and not $hash->{SolarView_WR($hash, 'Debounced', $wr)})
          {
              # revert to the previous value
              $readings{currentPower} = $hash->{READINGS}{SolarView_WR($hash, 'currentPower', $wr)}{VAL};
              $hash->{SolarView_WR($hash, 'Debounced', $wr)} = 1;
          } else {
              $hash->{SolarView_WR($hash, 'Debounced', $wr)} = 0;
          }

          # copy the values to the READINGS
          for my $get (@gets)
          {
            # update and notify readings if they have changed
            if ($hash->{READINGS}{SolarView_WR($hash, $get, $wr)}{VAL} != $readings{$get})
            {
              $hash->{READINGS}{SolarView_WR($hash, $get, $wr)}{VAL}  = $readings{$get};
              $hash->{READINGS}{SolarView_WR($hash, $get, $wr)}{TIME} = $timenow;
              #
              push @{$hash->{CHANGED}}, sprintf("%s: %s (wr%s)", $get, $readings{$get}, $wr);
            }
          }
          
          alarm 0;
          $success = 1;

        } # res okay
      } # socket okay
    }; # eval
    alarm 0;
  } # wr loop

  $hash->{STATE} = $hash->{READINGS}{currentPower}{VAL}.' W, '.$hash->{READINGS}{totalEnergyDay}{VAL}.' kWh';

  if ($success) 
  {
    DoTrigger($hash->{NAME}, undef) if ($init_done);
    Log 4, "$hash->{NAME} got fresh values from solarview";
  } 
  else 
  {
    $hash->{STATE} .= ' (Fail)';
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

sub
SolarView_IsNight($)
{
  my ($hash) = @_;

  my $isNight = 0;

  my ($sec,$min,$hour,$mday,$mon) = localtime(time);

  # reset totalEnergyX at midnight
  if ($hour == 0) 
  {
    my $timenow = TimeNow();

    for my $wr (@{$hash->{WRs2Read}})
    {
      $hash->{READINGS}{SolarView_WR($hash, 'totalEnergyDay', $wr)}{VAL}  = 0;
      $hash->{READINGS}{SolarView_WR($hash, 'totalEnergyDay', $wr)}{TIME} = $timenow;
    }
    #
    if ($mday == 1)
    {
      for my $wr (@{$hash->{WRs2Read}})
      {
        $hash->{READINGS}{SolarView_WR($hash, 'totalEnergyMonth', $wr)}{VAL}  = 0;
        $hash->{READINGS}{SolarView_WR($hash, 'totalEnergyMonth', $wr)}{TIME} = $timenow;
      }
      #
      if ($mon == 0)
      {
        for my $wr (@{$hash->{WRs2Read}})
        {
          $hash->{READINGS}{SolarView_WR($hash, 'totalEnergyYear', $wr)}{VAL}  = 0;
          $hash->{READINGS}{SolarView_WR($hash, 'totalEnergyYear', $wr)}{TIME} = $timenow;
        }
      }
    }
  }

  if ($hash->{UseSVNight})
  {
    # These are the on/off timings from Solarview, see
    # http://www.amhamberg.de/solarview-fb_Installieren.pdf
    #
    if ($mon == 0) { # Jan
      $isNight = ($hour < 7 or $hour > 17);
    } elsif ($mon == 1) {  # Feb
      $isNight = ($hour < 7 or $hour > 18);
    } elsif ($mon == 2) {  # Mar
      $isNight = ($hour < 6 or $hour > 19);
    } elsif ($mon == 3) {  # Apr
      $isNight = ($hour < 5 or $hour > 20);
    } elsif ($mon == 4) {  # May
      $isNight = ($hour < 5 or $hour > 21);
    } elsif ($mon == 5) {  # Jun
      $isNight = ($hour < 5 or $hour > 21);
    } elsif ($mon == 6) {  # Jul
      $isNight = ($hour < 5 or $hour > 21);
    } elsif ($mon == 7) {  # Aug
      $isNight = ($hour < 5 or $hour > 21);
    } elsif ($mon == 8) {  # Sep
      $isNight = ($hour < 6 or $hour > 20);
    } elsif ($mon == 9) {  # Oct
      $isNight = ($hour < 7 or $hour > 19);
    } elsif ($mon == 10) { # Nov
      $isNight = ($hour < 7 or $hour > 17);
    } elsif ($mon == 11) { # Dec
      $isNight = ($hour < 8 or $hour > 16);
    }
  } else { # we use SUNRISE_EL 
    $isNight = not isday();
  }

  return $isNight;
}

# prefix the reading name with inverter number
sub
SolarView_WR($$$)
{
  my ($hash, $reading, $wr) = @_;

  if ((int(@{$hash->{WRs2Read}}) > 1) && (int($wr) > 0))
  {
    return sprintf("wr%s_%s", $wr, $reading);
  }
  else
  {
    return $reading;
  }
}

1;


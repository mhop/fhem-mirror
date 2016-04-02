#################################################################################
#
#  $Id$
#
#  52_I2C_MMA845X.pm
#
#  (c) 2016 Copyright Jens Beyer < jensb at forum dot fhem dot de >
#
#  This script is part of FHEM.
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#################################################################################

# encoding: UTF-8 (äöüÄÖÜß§€)

# -----------------------------------------------------------------------------

=pod

TODO

- configurable max. measurement range?
- return values with get even if using non-blocking I2C IO?
- support power saving?

=cut

# -----------------------------------------------------------------------------

package main;

use strict;
use warnings;

# -----------------------------------------------------------------------------

use constant {
  MMA845X_STATE_DEFINED             => 'defined',
  MMA845X_STATE_INITIALIZED         => 'initialized',
  MMA845X_STATE_CALIBRATING         => 'calibrating',
  MMA845X_STATE_INVALID_DEVICE      => 'invalid device',
  MMA845X_STATE_DISABLED            => 'disabled',
  MMA845X_STATE_I2C_ERROR           => 'I2C error',

  MMA845X_DEVICE_CODE_MMA8451       => 0x1A, # sensitivity 4096, FIFO, programmable orientation detection
  MMA845X_DEVICE_CODE_MMA8452       => 0x2A, # sensitivity 1024
  MMA845X_DEVICE_CODE_MMA8453       => 0x3A, # sensitivity 256

  MMA845X_ADDR_LOW                  => '0x1C',
  MMA845X_ADDR_HIGH                 => '0x1D',

  MMA845X_REGISTER_OUT_X_MSB        => 0x01, # r/o
  MMA845X_REGISTER_WHO_AM_I         => 0x0D, # r/o
  MMA845X_REGISTER_XYZ_DATA_CFG     => 0x0E,
  MMA845X_REGISTER_HP_FILTER_CUTOFF => 0x0F,
  MMA845X_REGISTER_PL_STATUS        => 0x10, # r/o
  MMA845X_REGISTER_PL_CFG           => 0x11,
  MMA845X_REGISTER_PL_COUNT         => 0x12,
  MMA845X_REGISTER_PL_BF_ZCOMP      => 0x13,
  MMA845X_REGISTER_PL_THS_REG       => 0x14,
  MMA845X_REGISTER_FF_MT_CFG        => 0x15,
  MMA845X_REGISTER_FF_MT_SRC        => 0x16, # r/o
  MMA845X_REGISTER_FF_MT_THS        => 0x17,
  MMA845X_REGISTER_FF_MT_COUNT      => 0x18,
  MMA845X_REGISTER_TRANSIENT_CFG    => 0x1D,
  MMA845X_REGISTER_TRANSIENT_SRC    => 0x1E, # r/o
  MMA845X_REGISTER_TRANSIENT_THS    => 0x1F,
  MMA845X_REGISTER_TRANSIENT_COUNT  => 0x20,
  MMA845X_REGISTER_PULSE_CFG        => 0x21,
  MMA845X_REGISTER_PULSE_SRC        => 0x22, # r/o
  MMA845X_REGISTER_PULSE_THSX       => 0x23,
  MMA845X_REGISTER_PULSE_THSY       => 0x24,
  MMA845X_REGISTER_PULSE_THSZ       => 0x25,
  MMA845X_REGISTER_PULSE_TMLT       => 0x26,
  MMA845X_REGISTER_PULSE_LTCY       => 0x27,
  MMA845X_REGISTER_PULSE_WIND       => 0x28,
  MMA845X_REGISTER_CTRL_REG1        => 0x2A,
  MMA845X_REGISTER_CTRL_REG4        => 0x2D,
  MMA845X_REGISTER_CTRL_REG5        => 0x2E,
  MMA845X_REGISTER_OFF_X            => 0x2F,
  MMA845X_REGISTER_OFF_Y            => 0x30,
  MMA845X_REGISTER_OFF_Z            => 0x31,

  MMA845X_BIT_XYZ_DATA_CFG_HPF_OUT  => 0x10,

  MMA845X_BIT_PL_CFG_PL_EN          => 0x40,

  MMA845X_BIT_HP_FILTER_PULSE_BYP   => 0x20,

  MMA845X_BIT_PL_STATUS_BAFRO       => 0x01,
  MMA845X_BIT_PL_STATUS_LO          => 0x40,
  MMA845X_BIT_PL_STATUS_NEWLP       => 0x80,

  MMA845X_BIT_FF_MT_CFG_EFE_X       => 0x08,
  MMA845X_BIT_FF_MT_CFG_EFE_Y       => 0x10,
  MMA845X_BIT_FF_MT_CFG_EFE_Z       => 0x20,
  MMA845X_BIT_FF_MT_CFG_OAE         => 0x40,
  MMA845X_BIT_FF_MT_CFG_ELE         => 0x80,

  MMA845X_BIT_FF_MT_SRC_POL_X       => 0x01,
  MMA845X_BIT_FF_MT_SRC_AX_X        => 0x02,
  MMA845X_BIT_FF_MT_SRC_POL_Y       => 0x04,
  MMA845X_BIT_FF_MT_SRC_AX_Y        => 0x08,
  MMA845X_BIT_FF_MT_SRC_POL_Z       => 0x10,
  MMA845X_BIT_FF_MT_SRC_AX_Z        => 0x20,
  MMA845X_BIT_FF_MT_SRC_EA          => 0x80,

  MMA845X_BIT_TRANSIENT_CFG_HPF_BYP => 0x01,
  MMA845X_BIT_TRANSIENT_CFG_EFE_X   => 0x02,
  MMA845X_BIT_TRANSIENT_CFG_EFE_Y   => 0x04,
  MMA845X_BIT_TRANSIENT_CFG_EFE_Z   => 0x08,
  MMA845X_BIT_TRANSIENT_CFG_ELE     => 0x10,

  MMA845X_BIT_TRANSIENT_SRC_POL_X   => 0x01,
  MMA845X_BIT_TRANSIENT_SRC_AX_X    => 0x02,
  MMA845X_BIT_TRANSIENT_SRC_POL_Y   => 0x04,
  MMA845X_BIT_TRANSIENT_SRC_AX_Y    => 0x08,
  MMA845X_BIT_TRANSIENT_SRC_POL_Z   => 0x10,
  MMA845X_BIT_TRANSIENT_SRC_AX_Z    => 0x20,
  MMA845X_BIT_TRANSIENT_SRC_EA      => 0x40,

  MMA845X_BIT_PULSE_CFG_EFE_XS      => 0x01,
  MMA845X_BIT_PULSE_CFG_EFE_XD      => 0x02,
  MMA845X_BIT_PULSE_CFG_EFE_YS      => 0x04,
  MMA845X_BIT_PULSE_CFG_EFE_YD      => 0x08,
  MMA845X_BIT_PULSE_CFG_EFE_ZS      => 0x10,
  MMA845X_BIT_PULSE_CFG_EFE_ZD      => 0x20,
  MMA845X_BIT_PULSE_CFG_ELE         => 0x40,
  MMA845X_BIT_PULSE_CFG_DPA         => 0x80,

  MMA845X_BIT_PULSE_SRC_POL_X       => 0x01,
  MMA845X_BIT_PULSE_SRC_POL_Y       => 0x02,
  MMA845X_BIT_PULSE_SRC_POL_Z       => 0x04,
  MMA845X_BIT_PULSE_SRC_DPE         => 0x08,
  MMA845X_BIT_PULSE_SRC_AX_X        => 0x10,
  MMA845X_BIT_PULSE_SRC_AX_Y        => 0x20,
  MMA845X_BIT_PULSE_SRC_AX_Z        => 0x40,
  MMA845X_BIT_PULSE_SRC_EA          => 0x80,

  MMA845X_BIT_CTRL_REG1_ACTIVE      => 0x01,
  MMA845X_BIT_CTRL_REG1_LNOISE      => 0x04,

  # CTRL_REG4
  MMA845X_BIT_INT_EN_FF_MT          => 0x04,
  MMA845X_BIT_INT_EN_PULSE          => 0x08,
  MMA845X_BIT_INT_EN_LNDPRT         => 0x10,
  MMA845X_BIT_INT_EN_TRANS          => 0x20,

  # CTRL_REG5
  MMA845X_BIT_INT_CFG_FF_MT         => 0x04,
  MMA845X_BIT_INT_CFG_PULSE         => 0x08,
  MMA845X_BIT_INT_CFG_LNDPRT        => 0x10,
  MMA845X_BIT_INT_CFG_TRANS         => 0x20,

  # PL_STATUS
  MMA845X_BITS_PL_LAPO_PU           => 0x00,
  MMA845X_BITS_PL_LAPO_PD           => 0x02,
  MMA845X_BITS_PL_LAPO_LR           => 0x04,
  MMA845X_BITS_PL_LAPO_LL           => 0x06,

  # CTRL_REG1
  MMA845X_BITS_ODR_800HZ            => 0x00, # default
  MMA845X_BITS_ODR_400HZ            => 0x08,
  MMA845X_BITS_ODR_200HZ            => 0x10,
  MMA845X_BITS_ODR_100HZ            => 0x18,
  MMA845X_BITS_ODR_50HZ             => 0x20,
  MMA845X_BITS_ODR_12_5HZ           => 0x28,
  MMA845X_BITS_ODR_6_25HZ           => 0x30,
  MMA845X_BITS_ODR_1_56HZ           => 0x38,

  # XYZ_DATA
  MMA845X_BITS_FS_2G                => 0x00, # default
  MMA845X_BITS_FS_4G                => 0x01,
  MMA845X_BITS_FS_8G                => 0x02,

  MMA845X_POLLING_INTERVAL_DEFAULT  => 10, # [s]
};

my %MMA845X_ADDRESSES = (
  "0x1c" => MMA845X_ADDR_LOW,
  "0x1d" => MMA845X_ADDR_HIGH,
);

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Initialize()

  Parameters:
    $hash:    hash reference of device instance

  Returns:    nothing

=cut

sub I2C_MMA845X_Initialize($) {
  my ($hash) = @_;

  $hash->{AttrFn}   = 'I2C_MMA845X_Attr';
  $hash->{DefFn}    = 'I2C_MMA845X_Define';
  $hash->{InitFn}   = 'I2C_MMA845X_Init';
  $hash->{I2CRecFn} = 'I2C_MMA845X_I2CRec';
  $hash->{SetFn}    = 'I2C_MMA845X_Set';
  $hash->{GetFn}    = 'I2C_MMA845X_Get';
  $hash->{UndefFn}  = 'I2C_MMA845X_Undef';

  $hash->{AttrList} = 'IODev pollInterval pollAccelerations:0,1 pollOrientation:0,1 pollEventSources:0,1 '
                    . 'outputDataRate:1.56,6.25,12.5,50,100,200,400,800 '
                    . 'highPass:multiple-strict,outputData,jolt,pulse highPassCutoffFrequency:0,1,2,3 '
                    . 'orientationDetection:0,1 orientationInterrupt:0,1,2 '
                    . 'orientationDebounce orientationZLockThreshold orientationBFTripAngleThreshold orientationPLTripAngleHysteresis orientationPLTripAngleThreshold '
                    . 'motionEvent:multiple-strict,X,Y,Z motionEventLatch:0,1 motionInterrupt:0,1,2 '
                    . 'motionMode:motion,freefall motionThreshold motionDebounce '
                    . 'joltEvent:multiple-strict,X,Y,Z joltEventLatch:0,1 joltInterrupt:0,1,2 '
                    . 'joltThreshold joltDebounce '
                    . 'pulseEvent:multiple-strict,XS,XD,YS,YD,ZS,ZD pulseEventLatch:0,1 pulseInterrupt:0,1,2 '
                    . 'pulseThresholdX pulseThresholdY pulseThresholdZ pulseWindow pulseLatency pulseWindow2 '
                    . 'disable:0,1 '
                    . $readingFnAttributes;

  # device power on defaults
  $hash->{OFF_X} = 0;
  $hash->{OFF_Y} = 0;
  $hash->{OFF_Z} = 0;
  $hash->{XYZ_DATA_CFG} = 0;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Attr()

  Parameters:
    @args:    array of parameters

  Returns:    undef on success or string with error message

=cut

sub I2C_MMA845X_Attr (@) {
  my ($cmd, $name, $attr, $val) = @_;
  my $hash = $defs{$name};
  my $result = undef;

  if ($cmd eq 'set') {
    if ($attr eq 'pollInterval') {
      my $pollInterval = (defined($val) && looks_like_number($val) && $val >= 0) ? $val : -1;
      if ($pollInterval > 0) {
        # start new measurement cycle
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($pollInterval < 0) {
        $result = 'invalid polling interval, must be an number >= 0 [seconds]';
      }
    }
    elsif ($attr eq 'highPassCutoffFrequency') {
      my $cutoffFrequency = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 3) ? $val : -1;
      if ($cutoffFrequency >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($cutoffFrequency < 0) {
        $result = 'invalid high-pass cutoff frequency selector, must be an integer number between 0 (higher frequency) and 3 (lower frequency)';
      }
    }
    elsif ($attr eq 'outputDataRate'       || $attr eq 'highPass'              ||
           $attr eq 'orientationDetection' ||                                     $attr eq 'orientationInterrupt' ||
           $attr eq 'pulseEvent'           || $attr eq 'pulseEventLatch'       || $attr eq 'pulseInterrupt'       ||
           $attr eq 'motionEvent'          || $attr eq 'motionEventLatch'      || $attr eq 'motionInterrupt'      || $attr eq 'motionMode' ||
           $attr eq 'joltEvent'            || $attr eq 'joltEventLatch'        || $attr eq 'joltInterrupt') {
      # cleanup readings
      if ($attr eq 'orientationDetection' && (!defined($val) || $val eq '0')) {
        delete $hash->{READINGS}{orientation};
      }
      elsif ($attr eq 'pulseEvent' && (!defined($val) || $val eq '1')) {
        delete $hash->{READINGS}{pulseEvent};
      }
      elsif ($attr eq 'motionEvent' && (!defined($val) || $val eq '1')) {
        delete $hash->{READINGS}{motionEvent};
      }
      elsif ($attr eq 'joltEvent' && (!defined($val) || $val eq '1')) {
        delete $hash->{READINGS}{joltEvent};
      }

      # force device reinit
      $hash->{MODEL} = undef;
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
    }
    elsif ($attr eq 'orientationDebounce') {
      my $orientationDebounce = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 255) ? $val : -1;
      if ($orientationDebounce >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($orientationDebounce < 0) {
        $result = 'invalid orientation debounce duration, must be an integer number between 0 and 255 [~ms]';
      }
    }
    elsif ($attr eq 'orientationZLockThreshold') {
      my $orientationZLockThreshold = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 7) ? $val : -1;
      if ($orientationZLockThreshold >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($orientationZLockThreshold < 0) {
        $result = 'invalid orientation Z lockout threshold, must be an integer number between 0 and 7 [14 ... 42°]';
      }
    }
    elsif ($attr eq 'orientationBFTripAngleThreshold') {
      my $orientationBFTripAngleThreshold = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 3) ? $val : -1;
      if ($orientationBFTripAngleThreshold >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($orientationBFTripAngleThreshold < 0) {
        $result = 'invalid orientation back/front trip angle threshold, must be an integer number between 0 and 3 [65 ... 80°]';
      }
    }
    elsif ($attr eq 'orientationPLTripAngleHysteresis') {
      my $orientationPLTripAngleHysteresis = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 7) ? $val : -1;
      if ($orientationPLTripAngleHysteresis >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($orientationPLTripAngleHysteresis < 0) {
        $result = 'invalid orientation portrait/landscape trip angle hysteresis, must be an integer number between 0 and 7 [±0 ... ±14°]';
      }
    }
    elsif ($attr eq 'orientationPLTripAngleThreshold') {
      my $orientationPLTripAngleThreshold = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 31) ? $val : -1;
      if ($orientationPLTripAngleThreshold >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($orientationPLTripAngleThreshold < 0) {
        $result = 'invalid orientation portrait/landscape trip angle threshold, must be an integer number between 0 and 31 [0 ... 75°]';
      }
    }
    elsif ($attr eq 'pulseThresholdX' || $attr eq 'pulseThresholdY' || $attr eq 'pulseThresholdZ') {
      my $pulseThreshold = (defined($val) && looks_like_number($val) && $val > 0 && $val <= 63) ? $val : -1;
      if ($pulseThreshold > 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($pulseThreshold < 0) {
        $result = 'invalid pulse threshold, must be an integer number between 1 and 63 [0.063g]';
      }
    }
    elsif ($attr eq 'pulseWindow' || $attr eq 'pulseWindow2') {
      my $pulseThreshold = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 255) ? $val : -1;
      if ($pulseThreshold >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($pulseThreshold < 0) {
        $result = 'invalid pulse window duration, must be an integer number between 0 and 255 [~ms]';
      }
    }
    elsif ($attr eq 'pulseLatency') {
      my $pulseThreshold = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 255) ? $val : -1;
      if ($pulseThreshold >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($pulseThreshold < 0) {
        $result = 'invalid pulse latency duration, must be an integer number between 0 and 255 [~ms]';
      }
    }
    elsif ($attr eq 'motionThreshold') {
      my $motionThreshold = (defined($val) && looks_like_number($val) && $val > 0 && $val <= 63) ? $val : -1;
      if ($motionThreshold > 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($motionThreshold < 0) {
        $result = 'invalid motion threshold, must be an integer number between 1 and 63 [0.063g]';
      }
    }
    elsif ($attr eq 'motionDebounce') {
      my $motionDebounce = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 255) ? $val : -1;
      if ($motionDebounce >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($motionDebounce < 0) {
        $result = 'invalid motion debounce duration, must be an integer number between 0 and 255 [~ms]';
      }
    }
    elsif ($attr eq 'joltThreshold') {
      my $joltThreshold = (defined($val) && looks_like_number($val) && $val > 0 && $val <= 63) ? $val : -1;
      if ($joltThreshold > 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($joltThreshold < 0) {
        $result = 'invalid jolt threshold, must be an integer number between 1 and 63 [0.063g]';
      }
    }
    elsif ($attr eq 'joltDebounce') {
      my $joltDebounce = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 255) ? $val : -1;
      if ($joltDebounce >= 0) {
        # force device reinit
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($joltDebounce < 0) {
        $result = 'invalid jolt debounce duration, must be an integer number between 0 and 255 [~ms]';
      }
    }
    elsif ($attr eq 'disable') {
      my $disable = (defined($val) && looks_like_number($val) && $val >= 0 && $val <= 1) ? $val : -1;
      if ($disable > 0) {
        # stop timer and force reinit at next start
        $hash->{MODEL} = undef;
        RemoveInternalTimer($hash);
        readingsSingleUpdate($hash, 'state', MMA845X_STATE_DISABLED, 1);
      } elsif ($disable == 0) {
        # restart timer
        RemoveInternalTimer($hash);
        InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
      } elsif ($disable < 0) {
        $result = 'invalid disable value, must be 0 or 1';
      }
    }

  } elsif ($cmd eq 'del') {
    if ($attr eq 'disable') {
      # restart timer
      RemoveInternalTimer($hash);
      InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
    }
    elsif ($attr eq 'orientationDetection') {
      delete $hash->{READINGS}{orientation};
    }
    elsif ($attr eq 'pulseEvent') {
      delete $hash->{READINGS}{pulseEvent};
    }
    elsif ($attr eq 'motionEvent') {
      delete $hash->{READINGS}{motionEvent};
    }
    elsif ($attr eq 'joltEvent') {
      delete $hash->{READINGS}{joltEvent};
    }
  }

  return $result;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Define()

  Parameters:
    $hash:    hash reference of device instance
    $def:     string device definition (device name, module name, I2C address)

  Returns:    undef on success or string with error message

=cut

sub I2C_MMA845X_Define($$) {
  my ($hash, $def) = @_;
  my $name = $hash->{NAME};
  my @a = split('[ \t][ \t]*', $def);

  my $result = undef;
  if (@a == 3) {
    my $address = lc($a[2]);
    $address = $MMA845X_ADDRESSES{$address};
    if (defined($address)) {
      $hash->{I2C_Address} = hex($address);
      readingsSingleUpdate($hash, 'state', MMA845X_STATE_DEFINED, 1);
    } else {
      $result = "I2C_MMA845X: invalid I2C address, must be one of " . join(', ', keys %MMA845X_ADDRESSES);
    }
  } elsif (@a < 3) {
    $result = "I2C_MMA845X: missing parameters, usage: define <name> I2C_MMA845X <I2C address>";
  } else {
    $result = "I2C_MMA845X: too many parameters in define";
  }

  if (!defined($result)) {
    # create default attributes
    if (AttrVal($name, 'pollInterval', '?') eq '?') {
      $attr{$name}{pollInterval} = MMA845X_POLLING_INTERVAL_DEFAULT;
    }

    # init immediately if FHEM is already up
    if ($main::init_done) {
      eval { I2C_MMA845X_Init($hash, undef); };
    }
  }

  return $result;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Init()

  Parameters:
    $hash:    hash reference of device instance
    \@args:   string array reference of initialization parameters

  Returns:    undef on success

=cut

sub I2C_MMA845X_Init($$) {
  my ($hash, $args) = @_;

  AssignIoPort($hash);

  # reset state
  $hash->{MODEL} = undef;
  $hash->{XYZ_DATA_CFG} = 0;
  $hash->{I2C_Blocking} = 0;

  # start timer
  RemoveInternalTimer($hash);
  InternalTimer(gettimeofday() + 8, 'I2C_MMA845X_Poll', $hash, 0);

  return undef;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Poll()

  Parameters:
    $hash:      hash reference of device instance
    $cmd:       optional string, may be one of "pulseSource"

  Returns:      undef on success

=cut

sub I2C_MMA845X_Poll($;$) {
  my ($hash, $cmd) =  @_;
  my $name = $hash->{NAME};

  # disable timer
  if (!defined($cmd)) {
    RemoveInternalTimer($hash);
  }

  my $pollDelay = AttrVal($hash->{NAME}, "pollInterval", MMA845X_POLLING_INTERVAL_DEFAULT) ;
  my $state = ReadingsVal($name, 'state', '?');
  if (!AttrVal($hash->{NAME}, "disable", 0)) {
    if ($state eq MMA845X_STATE_INVALID_DEVICE || $state eq MMA845X_STATE_DISABLED || $state eq MMA845X_STATE_I2C_ERROR) {
      # error state, clear model registration to force new setup
      $hash->{MODEL} = undef;
    }
    if (!defined($hash->{MODEL})) {
      # reset state
      if ($state ne MMA845X_STATE_DEFINED && $state ne MMA845X_STATE_INVALID_DEVICE) {
        readingsSingleUpdate($hash, 'state', MMA845X_STATE_DEFINED, 1);
      }
      $hash->{setup} = 0;
      $hash->{I2C_PendingRequests} = 0;

      # detect device model and IO mode
      $hash->{operationInProgress} = 1;
      I2C_MMA845X_Read($hash, MMA845X_REGISTER_WHO_AM_I, 1);
      delete $hash->{operationInProgress};
    }
    if (defined($hash->{setup})) {
      if ($hash->{I2C_Blocking}) {
        # start/continue with blocking setup
        I2C_MMA845X_Setup($hash);

        # yield to FHEM for 100 ms
        $pollDelay = 0.1;
      } else {
        # monitor non-blocking setup
        $hash->{I2C_PendingRequests}++;
        if ($hash->{I2C_PendingRequests} > 10) {
          # non-blocking setup timeout
          readingsSingleUpdate($hash, 'state', MMA845X_STATE_I2C_ERROR, 1);
        }
      }
    } else {
      # polling
      if (defined($hash->{I2C_PendingRequests})) {
        $hash->{I2C_PendingRequests}++;
      } else {
        $hash->{I2C_PendingRequests} = 1;
      }

      # get acceleration values
      if (AttrVal($name, 'pollAccelerations', 1) || $state eq MMA845X_STATE_CALIBRATING || (defined($cmd) && $cmd eq 'accelerations')) {
        I2C_MMA845X_Read($hash, MMA845X_REGISTER_OUT_X_MSB, 6);
      }

      # get orientation
      if ((AttrVal($name, 'pollOrientation', 1) && $state ne MMA845X_STATE_CALIBRATING) || (defined($cmd) && $cmd eq 'orientation')) {
        my $orientationDetection = AttrVal($name, 'orientationDetection', 0);
        if ($orientationDetection) {
          I2C_MMA845X_Read($hash, MMA845X_REGISTER_PL_STATUS, 1);
        }
      }

      # get event sources
      if ((AttrVal($name, 'pollEventSources', 1) && $state ne MMA845X_STATE_CALIBRATING) || (defined($cmd) && $cmd eq 'eventSource')) {
        # get motion source
        my $motionEvent = AttrVal($name, 'motionEvent', '');
        if (length($motionEvent) > 0 && $motionEvent ne '1') {
          I2C_MMA845X_Read($hash, MMA845X_REGISTER_FF_MT_SRC, 1);
        }
        # get jolt source
        my $joltEvent = AttrVal($name, 'joltEvent', '');
        if (length($joltEvent) > 0 && $joltEvent ne '1') {
          I2C_MMA845X_Read($hash, MMA845X_REGISTER_TRANSIENT_SRC, 1);
        }
        # get pulse source
        my $pulseEvent = AttrVal($name, 'pulseEvent', '');
        if (length($pulseEvent) > 0 && $pulseEvent ne '1') {
          I2C_MMA845X_Read($hash, MMA845X_REGISTER_PULSE_SRC, 1);
        }
      }

      # monitor non-blocking read of acceleration values
      if (!$hash->{I2C_Blocking} && $hash->{I2C_PendingRequests} >= 3) {
        # non-blocking read timeout
        readingsSingleUpdate($hash, 'state', MMA845X_STATE_I2C_ERROR, 1);
      }
    }
  }
  elsif ($state ne MMA845X_STATE_DISABLED) {
    readingsSingleUpdate($hash, 'state', MMA845X_STATE_DISABLED, 1);
  }

  # schedule next poll
  if (!defined($cmd)) {
    #Log3($name, 5, "I2C_MMA845X_Poll: $pollDelay s");
    if ($pollDelay > 0) {
      InternalTimer(gettimeofday() + $pollDelay, 'I2C_MMA845X_Poll', $hash, 0);
    }
  }

  return undef;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_I2CRec()

  Parameters:
    $hash:      hash reference of device instance
    $clientmsg: hash reference from I2C receiver

  Returns:      nothing

=cut

sub I2C_MMA845X_I2CRec($) {
  my ($hash, $clientmsg) = @_;
  my $name = $hash->{NAME};

  # copy all elements of clientmsg starting with IODev name into internal (debug data)
  my $phash = $hash->{IODev};
  my $pname = $phash->{NAME};
  while (my ($k, $v) = each %$clientmsg) {
    $hash->{$k} = $v if $k =~ /^$pname/;
  }

  # last send was OK?
  if ($clientmsg->{direction} && $clientmsg->{reg} && $pname && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok") {
    # data was received?
    if ($clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received})) {
      my $register = $clientmsg->{reg} & 0xFF;
      Log3($hash, 5, "$name RX register $register, $clientmsg->{nbyte} bytes: $clientmsg->{received}");
      my $byte = undef;
      my $word = undef;
      my @raw = split(" ", $clientmsg->{received});
      if ($clientmsg->{nbyte} == 1) {
        $byte = $raw[0];
      } elsif ($clientmsg->{nbyte} == 2) {
        $word = $raw[0] << 8 | $raw[1];
      }

      # process reply
      if ($register == MMA845X_REGISTER_WHO_AM_I) {
        I2C_MMA845X_WHO_AM_I($hash, $byte);
      } elsif ($register == MMA845X_REGISTER_OUT_X_MSB && $clientmsg->{nbyte} == 6) {
        I2C_MMA845X_OUT_XYZ($hash, \@raw);
        $hash->{I2C_PendingRequests} = 0;
      } elsif ($register == MMA845X_REGISTER_PL_STATUS) {
        I2C_MMA845X_PL_STATUS($hash, $byte);
        $hash->{I2C_PendingRequests} = 0;
      } elsif ($register == MMA845X_REGISTER_FF_MT_SRC) {
        I2C_MMA845X_FF_MT_SRC($hash, $byte);
        $hash->{I2C_PendingRequests} = 0;
      } elsif ($register == MMA845X_REGISTER_TRANSIENT_SRC) {
        I2C_MMA845X_TRANSIENT_SRC($hash, $byte);
        $hash->{I2C_PendingRequests} = 0;
      } elsif ($register == MMA845X_REGISTER_PULSE_SRC) {
        I2C_MMA845X_PULSE_SRC($hash, $byte);
        $hash->{I2C_PendingRequests} = 0;
      } else {
        Log3($hash, 2, "$name RX register $register not implemented");
      }
    }
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_WHO_AM_I()

  Parameters:
    $hash:      hash reference of device instance
    $byte:      I2C register value

  Returns:      nothing

=cut

sub I2C_MMA845X_WHO_AM_I($$) {
  my ($hash, $byte) = @_;
  my $name = $hash->{NAME};

  if ($byte == MMA845X_DEVICE_CODE_MMA8451 || $byte == MMA845X_DEVICE_CODE_MMA8452 || $byte == MMA845X_DEVICE_CODE_MMA8453) {
    # save model code
    $hash->{MODEL} = $byte;

    # save IO mode
    if (defined($hash->{operationInProgress})) {
      $hash->{I2C_Blocking} = 1;
    }

    if (defined($hash->{setup} && !$hash->{I2C_Blocking})) {
      # start/continue with non-blocking setup
      I2C_MMA845X_Setup($hash);

      # perform read to ensure non-blocking setup stage was completed
      if (defined($hash->{setup})) {
        I2C_MMA845X_Read($hash, MMA845X_REGISTER_WHO_AM_I, 1);
      }
    }
  } else {
    Log3($hash, 1, "$name I2C device at address " . $hash->{I2C_Address} . " is not MMA845X compatible");
    $hash->{MODEL} = undef; # incompatible
    if (ReadingsVal($name, 'state', '?') ne MMA845X_STATE_INVALID_DEVICE) {
      readingsSingleUpdate($hash, 'state', MMA845X_STATE_INVALID_DEVICE, 1);
    }
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Setup()

  Parameters:
    $hash:      hash reference of device instance

  Returns:      nothing

=cut

sub I2C_MMA845X_Setup($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $stage = 0;
  if (defined($hash->{setup}) && $hash->{setup} >= 0 && $hash->{setup} <= 6) {
    $stage = $hash->{setup};
  }

  #Log3($hash, 1, "$name setup stage $stage");

  if ($stage == 0)
  {
    # disable measurement
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG1, 0);

    # activate 4 g full scale range and optionally the high-pass filter
    $hash->{XYZ_DATA_CFG} = MMA845X_BITS_FS_4G;
    $hash->{XYZ_DATA_CFG} |= MMA845X_BIT_XYZ_DATA_CFG_HPF_OUT if (index(AttrVal($name, 'highPass', ''), 'outputData') >= 0);
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_XYZ_DATA_CFG, $hash->{XYZ_DATA_CFG});

    # set the high-pass filter cutoff frequency and optionally disable the high-pass filter
    $hash->{HP_FILTER_CUTOFF} = AttrVal($name, 'highPassCutoffFrequency', 0);
    $hash->{HP_FILTER_CUTOFF} |= MMA845X_BIT_HP_FILTER_PULSE_BYP if (index(AttrVal($name, 'highPass', 'pulse'), 'pulse') < 0);
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_HP_FILTER_CUTOFF, $hash->{HP_FILTER_CUTOFF});
  }

  elsif ($stage == 1)
  {
    # prepare control registers 4 and 5 (interrupt configuration)
    $hash->{CTRL_REG4} = 0;
    $hash->{CTRL_REG5} = 0;

    # enable orientation detection
    my $orientatonEvent = AttrVal($name, 'orientatonEvent', 1);
    if ($orientatonEvent) {
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_PL_CFG, MMA845X_BIT_PL_CFG_PL_EN);

      # configure interrupt
      my $orientationInterrupt = AttrVal($name, 'orientationInterrupt', 0);
      $hash->{CTRL_REG4} |= MMA845X_BIT_INT_EN_LNDPRT if ($orientationInterrupt);
      $hash->{CTRL_REG5} |= MMA845X_BIT_INT_CFG_LNDPRT if ($orientationInterrupt == 1);

      # configure parameters
      my $orientationDebounce = AttrVal($name, 'orientationDebounce', 100); # 500 ms default with MODS=Normal ODR=200Hz = 5 ms steps
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_PL_COUNT, $orientationDebounce);

      my $orientationZLockThreshold = AttrVal($name, 'orientationZLockThreshold', 4);  # Z 29° default
      my $orientationBFTripAngleThreshold = AttrVal($name, 'orientationBFTripAngleThreshold', 1) << 6;  # Z < 75° or Z > 285° default
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_PL_BF_ZCOMP, $orientationBFTripAngleThreshold + $orientationZLockThreshold);

      my $orientationPLTripAngleHysteresis = AttrVal($name, 'orientationPLTripAngleHysteresis', 4);  # ±14° default
      my $orientationPLTripAngleThreshold = AttrVal($name, 'orientationPLTripAngleThreshold', 0x10) << 3;  # 45° default
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_PL_THS_REG, $orientationPLTripAngleHysteresis + $orientationPLTripAngleThreshold);
    } else {
      # disable orientation detection
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_PL_CFG, 0);
    }
  }

  elsif ($stage == 2)
  {
    # enable freefall/motion detection
    my $motionEvent = AttrVal($name, 'motionEvent', '');
    if (length($motionEvent) > 0 && $motionEvent ne '1') {
      my $motionCfg = 0;
      if (index($motionEvent, 'X') >= 0) {
        $motionCfg |= MMA845X_BIT_FF_MT_CFG_EFE_X;
      }
      if (index($motionEvent, 'Y') >= 0) {
        $motionCfg |= MMA845X_BIT_FF_MT_CFG_EFE_Y;
      }
      if (index($motionEvent, 'Z') >= 0) {
        $motionCfg |= MMA845X_BIT_FF_MT_CFG_EFE_Z;
      }
      if ($motionCfg) {
        # configure motion detection
        if (AttrVal($name, 'motionEventLatch', 0)) { # default: interrupt will be automatically reset
          $motionCfg |= MMA845X_BIT_FF_MT_CFG_ELE;
        }
        if (AttrVal($name, 'motionMode', 'motion') eq 'motion') {
          $motionCfg |= MMA845X_BIT_FF_MT_CFG_OAE;
        }
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_FF_MT_CFG, $motionCfg);

        # configure interrupt
        my $motionInterrupt = AttrVal($name, 'motionInterrupt', 0);
        $hash->{CTRL_REG4} |= MMA845X_BIT_INT_EN_FF_MT if ($motionInterrupt);
        $hash->{CTRL_REG5} |= MMA845X_BIT_INT_CFG_FF_MT if ($motionInterrupt == 1);

        # configure parameters
        my $motionThreshold = AttrVal($name, 'motionThreshold', 0x01);  # 0.063g default
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_FF_MT_THS, $motionThreshold);

        my $motionDebounce = AttrVal($name, 'motionDebounce', 0x00);    # 0 ms default with MODS=Normal ODR=200Hz = 5 ms steps
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_FF_MT_COUNT, $motionDebounce);
      } else {
        # disable motion detection
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_FF_MT_CFG, 0);
      }
    } else {
      # disable motion detection
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_FF_MT_CFG, 0);
    }
  }

  elsif ($stage == 3)
  {
    # enable jolt detection
    my $joltEvent = AttrVal($name, 'joltEvent', '');
    if (length($joltEvent) > 0 && $joltEvent ne '1') {
      my $joltCfg = 0;
      if (index($joltEvent, 'X') >= 0) {
        $joltCfg |= MMA845X_BIT_TRANSIENT_CFG_EFE_X;
      }
      if (index($joltEvent, 'Y') >= 0) {
        $joltCfg |= MMA845X_BIT_TRANSIENT_CFG_EFE_Y;
      }
      if (index($joltEvent, 'Z') >= 0) {
        $joltCfg |= MMA845X_BIT_TRANSIENT_CFG_EFE_Z;
      }
      if ($joltCfg) {
        # configure jolt detection and optionally disable the high-pass filter
        $joltCfg |= MMA845X_BIT_TRANSIENT_CFG_HPF_BYP if (index(AttrVal($name, 'highPass', 'jolt'), 'jolt') < 0);
        if (AttrVal($name, 'joltEventLatch', 0)) { # default: interrupt will be automatically reset
          $joltCfg |= MMA845X_BIT_TRANSIENT_CFG_ELE;
        }
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_TRANSIENT_CFG, $joltCfg);

        # configure interrupt
        my $joltInterrupt = AttrVal($name, 'joltInterrupt', 0);
        $hash->{CTRL_REG4} |= MMA845X_BIT_INT_EN_TRANS if ($joltInterrupt);
        $hash->{CTRL_REG5} |= MMA845X_BIT_INT_CFG_TRANS if ($joltInterrupt == 1);

        # configure parameters
        my $joltThreshold = AttrVal($name, 'joltThreshold', 0x01);  # 0.063g default
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_TRANSIENT_THS, $joltThreshold);

        my $joltDebounce = AttrVal($name, 'joltDebounce', 0x00);    # 0 ms default with MODS=Normal ODR=200Hz = 5 ms steps
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_TRANSIENT_COUNT, $joltDebounce);
      } else {
        # disable jolt detection
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_TRANSIENT_CFG, 0);
      }
    } else {
      # disable jolt detection
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_TRANSIENT_CFG, 0);
    }
  }

  elsif ($stage == 4)
  {
    # enable pulse detection
    my $pulseEvent = AttrVal($name, 'pulseEvent', '');
    if (length($pulseEvent) > 0 && $pulseEvent ne '1') {
      my $pulseCfg = 0;
      if (index($pulseEvent, 'XS') >= 0) {
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_EFE_XS;
      }
      if (index($pulseEvent, 'XD') >= 0) {
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_EFE_XD;
      }
      if (index($pulseEvent, 'YS') >= 0) {
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_EFE_YS;
      }
      if (index($pulseEvent, 'YD') >= 0) {
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_EFE_YD;
      }
      if (index($pulseEvent, 'ZS') >= 0) {
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_EFE_ZS;
      }
      if (index($pulseEvent, 'ZD') >= 0) {
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_EFE_ZD;
      }
      if ($pulseCfg) {
        # configure pulse detection
        if (AttrVal($name, 'pulseEventLatch', 0)) { # default: interrupt will be automatically reset after latency duration
          $pulseCfg |= MMA845X_BIT_PULSE_CFG_ELE;
        }
        $pulseCfg |= MMA845X_BIT_PULSE_CFG_DPA; # enable single and double pulse detection abort on timing mismatch
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_CFG, $pulseCfg);

        # configure interrupt
        my $pulseInterrupt = AttrVal($name, 'pulseInterrupt', 0);
        $hash->{CTRL_REG4} |= MMA845X_BIT_INT_EN_PULSE if ($pulseInterrupt);
        $hash->{CTRL_REG5} |= MMA845X_BIT_INT_CFG_PULSE if ($pulseInterrupt == 1);

        # configure parameters
        my $pulseThresholdX = AttrVal($name, 'pulseThresholdX', 0x10);   # 1g default
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_THSX, $pulseThresholdX);
        my $pulseThresholdY = AttrVal($name, 'pulseThresholdY', 0x10);   # 1g default
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_THSY, $pulseThresholdY);
        my $pulseThresholdZ = AttrVal($name, 'pulseThresholdZ', 0x30);   # 3g default
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_THSZ, $pulseThresholdZ);

        my $pulseWindow = AttrVal($name, 'pulseWindow', 0x30);           # 60 ms default with MODS=Normal ODR=200Hz = 1.25 ms steps
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_TMLT, $pulseWindow);

        my $pulseLatency = AttrVal($name, 'pulseLatency', 0x50);         # 200 ms default with MODS=Normal ODR=200Hz = 2.5 ms steps
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_LTCY, $pulseLatency);

        my $pulseWindow2 = AttrVal($name, 'pulseWindow2', 0x78);         # 300 ms default with MODS=Normal ODR=200Hz = 2.5 ms steps
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_WIND, $pulseWindow2);
      } else {
        # disable pulse detection
        I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_CFG, 0);
      }
    } else {
      # disable pulse detection
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_PULSE_CFG, 0);
    }
  }

  elsif ($stage == 5)
  {
    # write control registers 4 and 5 (interrupt configuration)
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG4, $hash->{CTRL_REG4});
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG5, $hash->{CTRL_REG5});

    # rewrite last calibration
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_X, I2C_MMA845X_G_TO_OFF($hash, ReadingsVal($name, 'offX', 0)));
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_Y, I2C_MMA845X_G_TO_OFF($hash, ReadingsVal($name, 'offY', 0)));
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_Z, I2C_MMA845X_G_TO_OFF($hash, ReadingsVal($name, 'offZ', 0)));

    # activate measurement (low noise filter = max. 4g, MODS=Normal)
    $hash->{CTRL_REG1} = MMA845X_BIT_CTRL_REG1_ACTIVE | MMA845X_BIT_CTRL_REG1_LNOISE;
    my $outputDataRate = AttrVal($name, 'outputDataRate', 200);
    if ($outputDataRate == 1.56) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_1_56HZ;
    } elsif ($outputDataRate == 6.25) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_6_25HZ;
    } elsif ($outputDataRate == 12.5) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_12_5HZ;
    } elsif ($outputDataRate == 50) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_50HZ;
    } elsif ($outputDataRate == 100) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_100HZ;
    } elsif ($outputDataRate == 200) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_200HZ;
    } elsif ($outputDataRate == 400) {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_400HZ;
    } else {
      $hash->{CTRL_REG1} |= MMA845X_BITS_ODR_800HZ;
    }
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG1, $hash->{CTRL_REG1});
  }

  elsif ($stage >= 6)
  {
    # setup completed
    delete $hash->{setup};
    $hash->{I2C_PendingRequests} = 0;
    readingsSingleUpdate($hash, 'state', MMA845X_STATE_INITIALIZED, 1);
    return;
  }

  # prepare next setup stage
  $stage++;
  $hash->{setup} = $stage;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_OUT_XYZ()

  Parameters:
    $hash:      hash reference of device instance
    $bytes:     byte array reference of I2C register values

  Returns:      nothing

=cut

sub I2C_MMA845X_OUT_XYZ($$) {
  my ($hash, $bytes) = @_;
  my $name = $hash->{NAME};

  # extract sample values assuming max. resolution (CTRL_REG1:F_READ=0)
  readingsBeginUpdate($hash);
  for (my $i=0; $i<3; $i++) {
    my $sample = $$bytes[2*$i] << 8 | $$bytes[2*$i + 1];                                  # combine MSB/LSB
    $sample = ($sample >> 2) & 0x3FFF if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451); # 14-bit adjust
    $sample = ($sample >> 4) & 0x0FFF if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452); # 12-bit adjust
    $sample = ($sample >> 6) & 0x03FF if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453); # 10-bit adjust
    if ($$bytes[2*$i] & 0x80) {
      $sample -= 0x4000 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451);               # 14-bit 2's complement negative value transform
      $sample -= 0x1000 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452);               # 12-bit 2's complement negative value transform
      $sample -= 0x0400 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453);               # 10-bit 2's complement negative value transform
    }
    my $range = 2 << ($hash->{XYZ_DATA_CFG} & 0x3);                                       # [1 g = 9.80665 m/s2]
    $hash->{accelerations}[$i] = $range * $sample;
    $hash->{accelerations}[$i] /= 0x2000 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451);           # 14-bit scale to [g]
    $hash->{accelerations}[$i] /= 0x0800 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452);           # 12-bit scale to [g]
    $hash->{accelerations}[$i] /= 0x0200 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453);           # 10-bit scale to [g]
    Log3($hash, 5, $hash->{NAME} . " i $i sample $sample range $range acceleration $hash->{accelerations}[$i]");
    readingsBulkUpdate($hash, "outX", sprintf('%0.3f', $hash->{accelerations}[$i])) if ($i == 0);
    readingsBulkUpdate($hash, "outY", sprintf('%0.3f', $hash->{accelerations}[$i])) if ($i == 1);
    readingsBulkUpdate($hash, "outZ", sprintf('%0.3f', $hash->{accelerations}[$i])) if ($i == 2);
  }
  readingsEndUpdate($hash, 1);

  # calibrate offset
  if (ReadingsVal($name, 'state', '?') eq MMA845X_STATE_CALIBRATING) {
    I2C_MMA845X_Calibrate($hash);
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_PL_STATUS()

  Parameters:
    $hash:      hash reference of device instance
    $byte:      I2C register value

  Returns:      nothing

=cut

sub I2C_MMA845X_PL_STATUS($$) {
  my ($hash, $byte) = @_;
  my $name = $hash->{NAME};

  my $orientation = '';
  if ($byte & MMA845X_BIT_PL_STATUS_NEWLP) {
    my $lapo = $byte & MMA845X_BITS_PL_LAPO_LL;
    if ($lapo == MMA845X_BITS_PL_LAPO_PU) {
      $orientation .= 'PU';
    } elsif ($lapo == MMA845X_BITS_PL_LAPO_PD) {
      $orientation .= 'PD';
    } elsif ($lapo == MMA845X_BITS_PL_LAPO_LR) {
      $orientation .= 'LR';
    } else {
      $orientation .= 'LL';
    }
    if ($byte & MMA845X_BIT_PL_STATUS_BAFRO) {
      $orientation .= 'B';
    } else {
      $orientation .= 'F';
    }
    if ($byte & MMA845X_BIT_PL_STATUS_LO) {
      $orientation .= 'X';
    }

    if (ReadingsVal($name, 'orientation', '') ne $orientation) {
      readingsSingleUpdate($hash, 'orientation', $orientation, 1);
    }
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_PULSE_SRC()

  Parameters:
    $hash:      hash reference of device instance
    $byte:      I2C register value

  Returns:      nothing

=cut

sub I2C_MMA845X_PULSE_SRC($$) {
  my ($hash, $byte) = @_;
  my $name = $hash->{NAME};

  my $eventSource = '';
  if ($byte & MMA845X_BIT_PULSE_SRC_EA) {
    if ($byte & MMA845X_BIT_PULSE_SRC_AX_X) {
      if ($byte & MMA845X_BIT_PULSE_SRC_POL_X) {
        $eventSource .= '-X';
      } else {
        $eventSource .= '+X';
      }
      if ($byte & MMA845X_BIT_PULSE_SRC_DPE) {
        $eventSource .= 'D';
      } else {
        $eventSource .= 'S';
      }
    }
    if ($byte & MMA845X_BIT_PULSE_SRC_AX_Y) {
      if ($byte & MMA845X_BIT_PULSE_SRC_POL_Y) {
        $eventSource .= '-Y';
      } else {
        $eventSource .= '+Y';
      }
      if ($byte & MMA845X_BIT_PULSE_SRC_DPE) {
        $eventSource .= 'D';
      } else {
        $eventSource .= 'S';
      }
    }
    if ($byte & MMA845X_BIT_PULSE_SRC_AX_Z) {
      if ($byte & MMA845X_BIT_PULSE_SRC_POL_Z) {
        $eventSource .= '-Z';
      } else {
        $eventSource .= '+Z';
      }
      if ($byte & MMA845X_BIT_PULSE_SRC_DPE) {
        $eventSource .= 'D';
      } else {
        $eventSource .= 'S';
      }
    }
  }

  if (ReadingsVal($name, 'pulseEvent', '') ne $eventSource) {
    readingsSingleUpdate($hash, 'pulseEvent', $eventSource, 1);
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_FF_MT_SRC()

  Parameters:
    $hash:      hash reference of device instance
    $byte:      I2C register value

  Returns:      nothing

=cut

sub I2C_MMA845X_FF_MT_SRC($$) {
  my ($hash, $byte) = @_;
  my $name = $hash->{NAME};

  my $eventSource = '';
  if ($byte & MMA845X_BIT_FF_MT_SRC_EA) {
    if ($byte & MMA845X_BIT_FF_MT_SRC_AX_X) {
      if ($byte & MMA845X_BIT_FF_MT_SRC_POL_X) {
        $eventSource .= '-X';
      } else {
        $eventSource .= '+X';
      }
    }
    if ($byte & MMA845X_BIT_FF_MT_SRC_AX_Y) {
      if ($byte & MMA845X_BIT_FF_MT_SRC_POL_Y) {
        $eventSource .= '-Y';
      } else {
        $eventSource .= '+Y';
      }
    }
    if ($byte & MMA845X_BIT_FF_MT_SRC_AX_Z) {
      if ($byte & MMA845X_BIT_FF_MT_SRC_POL_Z) {
        $eventSource .= '-Z';
      } else {
        $eventSource .= '+Z';
      }
    }
  }

  if (ReadingsVal($name, 'motionEvent', '') ne $eventSource) {
    readingsSingleUpdate($hash, 'motionEvent', $eventSource, 1);
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_TRANSIENT_SRC()

  Parameters:
    $hash:      hash reference of device instance
    $byte:      I2C register value

  Returns:      nothing

=cut

sub I2C_MMA845X_TRANSIENT_SRC($$) {
  my ($hash, $byte) = @_;
  my $name = $hash->{NAME};

  my $eventSource = '';
  if ($byte & MMA845X_BIT_TRANSIENT_SRC_EA) {
    if ($byte & MMA845X_BIT_TRANSIENT_SRC_AX_X) {
      if ($byte & MMA845X_BIT_TRANSIENT_SRC_POL_X) {
        $eventSource .= '-X';
      } else {
        $eventSource .= '+X';
      }
    }
    if ($byte & MMA845X_BIT_TRANSIENT_SRC_AX_Y) {
      if ($byte & MMA845X_BIT_TRANSIENT_SRC_POL_Y) {
        $eventSource .= '-Y';
      } else {
        $eventSource .= '+Y';
      }
    }
    if ($byte & MMA845X_BIT_TRANSIENT_SRC_AX_Z) {
      if ($byte & MMA845X_BIT_TRANSIENT_SRC_POL_Z) {
        $eventSource .= '-Z';
      } else {
        $eventSource .= '+Z';
      }
    }
  }

  if (ReadingsVal($name, 'joltEvent', '') ne $eventSource) {
    readingsSingleUpdate($hash, 'joltEvent', $eventSource, 1);
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Get()

  Parameters:
    $hash:    hash reference of device instance
    @args:    array of arguments

  Returns:    undef on success or string with error message

=cut

sub I2C_MMA845X_Get($@) {
  my ($hash, $name, $cmd, @a) = @_;
  my $result = undef;

  if ($cmd eq 'accelerations') {
    I2C_MMA845X_Poll($hash, 'accelerations');
    if ($hash->{I2C_Blocking}) {
      return "$name $cmd => x:$hash->{accelerations}[0]g y:$hash->{accelerations}[1]g z:$hash->{accelerations}[2]g";
    }
  } elsif ($cmd eq 'orientation') {
    I2C_MMA845X_Poll($hash, 'orientation');
    if ($hash->{I2C_Blocking}) {
      return "$name $cmd => orientation:" . ReadingsVal($name, 'orientation', '?');
    }
  } elsif ($cmd eq 'eventSources') {
    I2C_MMA845X_Poll($hash, 'eventSources');
    if ($hash->{I2C_Blocking}) {
      return "$name $cmd => pulse:"  . ReadingsVal($name, 'pulseEvent', '')  .
                          " motion:" . ReadingsVal($name, 'motionEvent', '') .
                          " jolt:"   . ReadingsVal($name, 'joltEvent', '');
    }
  } elsif ($cmd eq 'update') {
    I2C_MMA845X_Poll($hash, 'update');
  } else {
    $result = "I2C_MMA845X: unknown get command " . $cmd . ", choose one of accelerations:noArg orientation:noArg eventSources:noArg update:noArg";
  }

  return $result;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Set()

  Parameters:
    $hash:    hash reference of device instance
    @args:    array of arguments

  Returns:    undef on success or string with error message

=cut

sub I2C_MMA845X_Set($@) {
  my ($hash, $name, $cmd, @args) = @_;
  my $result = undef;

  if ($cmd eq 'calibrate') {
    if ($hash->{XYZ_DATA_CFG} & MMA845X_BIT_XYZ_DATA_CFG_HPF_OUT) {
      $result = "I2C_MMA845X: calibration only available with high-pass filter disabled";
    } else {
      I2C_MMA845X_StartCalibration($hash);
    }
  } else {
    $result = "I2C_MMA845X: unknown set command " . $cmd . ", choose one of calibrate:noArg";
  }

  return $result;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_G_TO_OFF()

  Parameters:
    $hash:     hash reference of device instance
    $accel:    decimal number, acceleration [g]

  Returns:     raw offset value

=cut

sub I2C_MMA845X_G_TO_OFF($$) {
  my ($hash, $result) = @_;

  Log3($hash, 5, $hash->{NAME} . " to byte 1 $result");

  $result *= 0x2000 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451); # 14-bit scale from [g]
  $result *= 0x0800 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452); # 12-bit scale from [g]
  $result *= 0x0200 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453); # 10-bit scale from [g]

  my $range = 2 << ($hash->{XYZ_DATA_CFG} & 0x3);                       # [1 g = 9.80665 m/s2]
  $result /= $range;

  $range = 0.125 * (1 << ($hash->{XYZ_DATA_CFG} & 0x3)) if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451); # 14-bit offset scale
  $range = 0.5   * (1 << ($hash->{XYZ_DATA_CFG} & 0x3)) if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452); # 12-bit offset scale
  $range = 2.0   * (1 << ($hash->{XYZ_DATA_CFG} & 0x3)) if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453); # 10-bit offset scale
  $result *= $range;

  $result = -127 if ($result < -127);                                   # byte range limiter
  $result = 127 if ($result > 127);                                     # byte range limiter

  $result += 0x0100 if ($result < 0);                                   # 2's complement transform

  Log3($hash, 5, $hash->{NAME} . " to byte 4 $result");

  return $result;
 }

# -----------------------------------------------------------------------------

=item I2C_MMA845X_OFF_TO_G()

  Parameters:
    $hash:     hash reference of device instance
    $offset:   raw offset value

  Returns:     decimal number, acceleration [g]

=cut

sub I2C_MMA845X_OFF_TO_G($$) {
  my ($hash, $result) = @_;

  $result -= 0x0100 if ($result > 0x7F);                                # 2's complement transform

  my $range = 2 << ($hash->{XYZ_DATA_CFG} & 0x3);                       # [1 g = 9.80665 m/s2]
  $result *= $range;

  $range = 0.125 * (1 << ($hash->{XYZ_DATA_CFG} & 0x3)) if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451); # 14-bit offset scale
  $range = 0.5   * (1 << ($hash->{XYZ_DATA_CFG} & 0x3)) if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452); # 12-bit offset scale
  $range = 2.0   * (1 << ($hash->{XYZ_DATA_CFG} & 0x3)) if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453); # 10-bit offset scale
  $result /= $range;

  $result /= 0x2000 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8451); # 14-bit scale to [g]
  $result /= 0x0800 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8452); # 12-bit scale to [g]
  $result /= 0x0200 if ($hash->{MODEL} == MMA845X_DEVICE_CODE_MMA8453); # 10-bit scale to [g]

  Log3($hash, 5, $hash->{NAME} . " to g 5 $result");

  return $result;
 }

# -----------------------------------------------------------------------------

=item I2C_MMA845X_StartCalibration()

  Parameters:
    $hash:      hash reference of device instance

  Returns:      nothing

=cut

sub I2C_MMA845X_StartCalibration($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  if (!AttrVal($hash->{NAME}, "disable", 0)) {
    # disable measurement
    $hash->{CTRL_REG1} &= ~MMA845X_BIT_CTRL_REG1_ACTIVE;
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG1, $hash->{CTRL_REG1});

    # clear current calibration values
    for (my $i=0; $i<3; $i++) {
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_X, 0) if ($i == 0);
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_Y, 0) if ($i == 1);
      I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_Z, 0) if ($i == 2);
    }

    # reenable measurement
    $hash->{CTRL_REG1} |= MMA845X_BIT_CTRL_REG1_ACTIVE;
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG1, $hash->{CTRL_REG1});

    # trigger new measurement
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + 1, 'I2C_MMA845X_Poll', $hash, 0);
    readingsSingleUpdate($hash, 'state', MMA845X_STATE_CALIBRATING, 1);
  }
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Calibrate()

  Parameters:
    $hash:      hash reference of device instance

  Returns:      nothing

=cut

sub I2C_MMA845X_Calibrate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @cal;

  # disable measurement
  $hash->{CTRL_REG1} &= ~MMA845X_BIT_CTRL_REG1_ACTIVE;
  I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG1, $hash->{CTRL_REG1});

  # detect gravity axis and direction by highest absolute output value
  my $gravityIndex = 0;
  for (my $i=1; $i<3; $i++) {
    if (abs($hash->{accelerations}[$i]) > abs($hash->{accelerations}[$gravityIndex])) {
      $gravityIndex = $i;
    }
  }
  my $gravityDirection = $hash->{accelerations}[$gravityIndex]<=>0;

  Log3($hash, 5, $hash->{NAME} . " Calibrate gravity index $gravityIndex, gravity direction $gravityDirection");

  readingsBeginUpdate($hash);
  for (my $i=0; $i<3; $i++) {
    # calculate calibration values based on current samples assuming orthogonal orientation
    $cal[$i] = -$hash->{accelerations}[$i]                     if ($i != $gravityIndex);
    $cal[$i] = -$hash->{accelerations}[$i] + $gravityDirection if ($i == $gravityIndex);
    $cal[$i] = I2C_MMA845X_G_TO_OFF($hash, $cal[$i]);

    # write new calibration values
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_X, $cal[$i]) if ($i == 0);
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_Y, $cal[$i]) if ($i == 1);
    I2C_MMA845X_Write($hash, MMA845X_REGISTER_OFF_Z, $cal[$i]) if ($i == 2);

    # save offsets
    readingsBulkUpdate($hash, "offX", I2C_MMA845X_OFF_TO_G($hash, $cal[$i])) if ($i == 0);
    readingsBulkUpdate($hash, "offY", I2C_MMA845X_OFF_TO_G($hash, $cal[$i])) if ($i == 1);
    readingsBulkUpdate($hash, "offZ", I2C_MMA845X_OFF_TO_G($hash, $cal[$i])) if ($i == 2);

    # modify readings
    readingsBulkUpdate($hash, "outX", sprintf('%0.3f', $hash->{accelerations}[$i] + ReadingsVal($name, 'offX', 0))) if ($i == 0);
    readingsBulkUpdate($hash, "outY", sprintf('%0.3f', $hash->{accelerations}[$i] + ReadingsVal($name, 'offY', 0))) if ($i == 1);
    readingsBulkUpdate($hash, "outZ", sprintf('%0.3f', $hash->{accelerations}[$i] + ReadingsVal($name, 'offZ', 0))) if ($i == 2);
  }
  readingsEndUpdate($hash, 1);

  # reenable measurement
  $hash->{CTRL_REG1} |= MMA845X_BIT_CTRL_REG1_ACTIVE;
  I2C_MMA845X_Write($hash, MMA845X_REGISTER_CTRL_REG1, $hash->{CTRL_REG1});
  readingsSingleUpdate($hash, 'state', MMA845X_STATE_INITIALIZED, 1);
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Undef()

  Parameters:
    $hash:    hash reference of device instance
    $name:    string name of device

  Returns:    undef on success

=cut

sub I2C_MMA845X_Undef($$) {
  my ($hash, $name) = @_;

  RemoveInternalTimer($hash);

  return undef;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Read()

  Parameters:
    $hash:    hash reference of device instance
    $reg:     integer, I2C register to read
    $nbytes:  integer, number of bytes to read

  Returns:    1 on success, 0 on error

=cut

sub I2C_MMA845X_Read($$$) {
  my ($hash, $reg, $nbytes) = @_;

  local $SIG{__WARN__} = sub {
    my $message = shift;
    # turn warnings from RPII2C_HWACCESS_ioctl into exception
    if ($message =~ /Exiting subroutine via last at.*00_RPII2C.pm/) {
      die;
    } else {
      warn($message);
    }
  };

  my $success = 1;
  if (defined (my $iodev = $hash->{IODev})) {
    eval {
      CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
      direction => "i2cread",
      i2caddress => $hash->{I2C_Address},
      reg => $reg,
      nbyte => $nbytes
      });
    };
    my $sendStat = $hash->{$iodev->{NAME}.'_SENDSTAT'};
    if (defined($sendStat) && $sendStat eq 'error') {
      readingsSingleUpdate($hash, 'state', MMA845X_STATE_I2C_ERROR, 1);
      Log3($hash, 5, $hash->{NAME} . " I2C read on $iodev->{NAME} failed");
      $success = 0;
    }
  } else {
    Log3($hash, 1, $hash->{NAME} . " no IODev assigned");
    $success = 0;
  }

  return $success;
}

# -----------------------------------------------------------------------------

=item I2C_MMA845X_Write()

  Parameters:
    $hash:    hash reference of device instance
    $reg:     integer, I2C register to write
    @data:    array of byte to write

  Returns:    1 on success, 0 on error

=cut

sub I2C_MMA845X_Write($$$) {
  my ($hash, $reg, @data) = @_;

  my $success = 1;
  if (defined (my $iodev = $hash->{IODev})) {
    eval {
      CallFn($iodev->{NAME}, "I2CWrtFn", $iodev, {
        direction => "i2cwrite",
        i2caddress => $hash->{I2C_Address},
        reg => $reg,
        data => join (' ',@data),
      });
    };
    my $sendStat = $hash->{$iodev->{NAME}.'_SENDSTAT'};
    if (defined($sendStat) && $sendStat eq 'error') {
      readingsSingleUpdate($hash, 'state', MMA845X_STATE_I2C_ERROR, 1);
      Log3($hash, 5, $hash->{NAME} . " I2C write on $iodev->{NAME} failed");
      $success = 0;
    }
  } else {
    Log3($hash, 1, $hash->{NAME} . " no IODev assigned");
    $success = 0;
  }

  return $success;
}

# -----------------------------------------------------------------------------

1;

# -----------------------------------------------------------------------------

=pod

CHANGES

19.03.2016
- orientation detection added

01.03.2016
- high-pass filter attributes added

27.02.2016
- event latch support added
- freefall/motion detection added
- jolt detection added

21.02.2016
- pulse detection added

19.02.2016 created
- acceleration measurement and calibration added

=cut

# -----------------------------------------------------------------------------

=pod
=begin html

<a name="I2C_MMA845X"></a>
<h3>I2C_MMA845X</h3>
<ul>
    This modules is a driver for using the Freescale/NXP MMA8451/MMA84512/MMA84513 accelerometer with I2C bus interface (see the <a href="http://www.nxp.com/products/sensors/accelerometers/3-axis-accelerometers/2g-4g-8g-low-g-14-bit-digital-accelerometer:MMA8451Q">NXP product description</a> for full specifications).
    Note that the Freescale/NXP MMA8450 accelerometer, though similar, has a different register set and cannot be addressed by this module.
    <br><br>
    The I2C messages are sent through an interface module like <a href="#RPII2C">RPII2C</a> or <a href="#FRM">FRM</a>,
    so this device must be defined first and assigned as IODev attribute.
    <br><br>
    This module supports the following features:
    <ul>
      <li>read current acceleration (x, y, z)</li>
      <li>calibrate acceleration offsets</li>
      <li>orientation detection</li>
      <li>motion detection (at least one axis above threshold) or freefall detection (all axes below threshold)</li>
      <li>jolt detection (at least one axis change above threshold)</li>
      <li>single and/or double pulse (tap) detection</li>
      <li>detection event latching</li>
      <li>hardware interrupt signalling of detection events</li>
    </ul>
    <br>
    The accelerometer is configured for an output data rate of 200 Hz in normal oversampling mode with the low noise
    filter enabled providing a full scale range of +/-4 g as default. This output data rate can be changed if required.
    <br><br>
    The detection events (orientation, motion/freefall, jolt, pulse) can be signaled by one or two hardware outputs that can
    be used for interrupt driven operations without need for continuous polling. If the event latch is enabled, the events
    and the interrupt signals will remain set until the event source register is read, providing additional event details
    (e.g. axis, direction). With orientation detection the event latch is always enabled.
    <br><br>
    The acceleration measurement output can optionally be passed through a high-pass filter with a selectable cutoff frequency
    effectively eliminating the gravity offset of 1g to provide change detection instead of orientation detection.
    The motion/freefall detection will always bypass the high-pass filter while the jolt and pulse detections will always
    use the high-pass filter with default settings. When using motion detection you would typically not enable the gravity
    axis or set a threshold higher than 1 g.
    <br><br>
    While the orientation detection works well with the default settings the other detection modes typically require fine tuning
    of their parameters. To understand the detection modes and their parameters in detail please refer to the Freescale annotations
    AN4068 (orientation), AN4070 (freefall/motion), AN4071 (jolt) and AN4072 (pulse).
    <br><br>
    Several of the parameters represent a frequency [Hz], a threshold [g]/[°] or a duration [ms]. Their absolute values often
    depend on a combination of register settings requiring lookup tables. This module uses the raw binary values for these
    attributes making fine tuning easier because value granularity is always 1. If you need to translate between binary
    values and absolute values please refer to the device documentation.
    <br><br>

    <a name="I2C_MMA845Xdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;device name&gt I2C_MMA845X &lt;I2C address&gt</code>
        <br><br>
        <code>&lt;I2C address&gt;</code> may be 0x1C or 0x1D
        <br><br>
        Example:
        <pre>
             define MMA8452 I2C_MMA845X 0x1D
             attr MMA8452 IODev I2CModule
             attr MMA8452 pollInterval 5
        </pre>

        Notes:
        <ul>
        <br>
            <li>The I2C bus connection must be kept active between write and read with the MMA8451/MMA84512/MMA84513 devices
                (repeated start alias combined write/read). This communication mode is not the default on most platforms:
                <br><br>
                <u>Raspberry</u>:
                <ul>
                    <li>Change parameter 'combined' of BCM2708 driver from N to Y.<br>
                        Temporary: <code>sudo su - echo -n 1 > /sys/module/i2c_bcm2708/parameters/combined exit</code>.<br>
                        Permanent: add <code>echo -n 1 > /sys/module/i2c_bcm2708/parameters/combined</code> to script
                                   <code>/etc/init.d/rc.local</code>.
                    </li>
                    <li>Set attribute <code>useHWLib</code> of your RPII2C device to <code>SMBus</code>
                        (RPII2C's ioctl mode currently does not support combined write/read mode).
                    </li>
                </ul>
                <br>
                <u>Firmata</u>:
                <ul>
                    <li>Make sure to call <code>Wire.endTransmission(false)</code>. Currently requires manually changing the
                        <code>ino</code> file (Standard Firmata) or <code>I2CFirmata.h</code> (Configurable Firmata).
                    </li>
                </ul>
            </li>
        </ul>
    </ul>
    <br>

    <a name="I2C_MMA845Xset"></a>
    <b>Set</b><br>
    <ul>
        <ul>
            <li><code>set &lt;device name&gt calibrate</code><br>
                Calibrate the acceleration offset based on the next sample assuming 1g gravity on any one axis.<br>
                Prerequisites: Align one axis with gravity and keep device stationary during calibration.
            </li>
        </ul>
    </ul>
    <br>

    <a name="I2C_MMA845Xget"></a>
    <b>Get</b><br>
    <ul>
        <ul>
            <li><code>get &lt;device name&gt update</code><br>
                Request an update of the acceleration readings.
            </li>
            <br>
            <li><code>get &lt;device name&gt orientation</code><br>
                Request an update of the orientation reading.
            </li>
            <li><code>get &lt;device name&gt eventSources</code><br>
                Request an update of the event source readings.
            </li>
            <br>
            <li><code>get &lt;device name&gt update</code><br>
                Perform manual polling, e.g. when attribute <code>pollInterval</code> is set to zero.
                At least one of <code>pollAccelerations</code>, <code>pollOrientation</code> or <code>pollEventSources</code> should be enabled.
            </li>
        </ul>
    </ul>
    <br>

    <a name="I2C_MMA845Xattr"></a>
    <b>Attributes</b>
    <ul>
        <code>attr &lt;device name&gt &lt;attribute name&gt &lt;value&gt</code>
        <br><br>
        Attributes:
        <ul>
            <li><i>IODev</i> &lt;IODev device name&gt<br>
                I2C IODev device name, <i>no default</i>, required
            </li>
            <li><i>pollInterval</i> &lt;seconds&gt<br>
                period for updating acceleration and event source readings, <i>default 10 s</i><br>
                fractional seconds are supported, use 0 to disable polling
            </li>
            <li><i>pollAccelerations</i> 0|1<br>
                include reading of accelerations when polling, <i>default 1</i><br>
            </li>
            <li><i>pollOrientation</i> 0|1<br>
                include reading of orientation when polling, <i>default 1</i><br>
            </li>
            <li><i>pollEventSources</i> 0|1<br>
                include reading of event sources when polling, <i>default 1</i><br>
            </li>
            <li><i>disable</i> 0|1<br>
                disables device (I2C operations), <i>default 0</i>
            </li>
            <li><i>outputDataRate</i> &lt;frequency&gt<br>
                device internal acceleration value output rate, may be one of 1.56, 6.25, 12.5, 50, 100, 200, 400 or 800 Hz, <i>default 200 Hz</i><br>
                affects all timing parameters, is independent of pollInterval
            </li>
            <li><i>highPass</i> &lt;function&gt[,&lt;function&gt]<br>
                select which function should use the high-pass filter, may be any of outputData, jolt or pulse, <i>default jolt,pulse</i><br>
                activating the high-pass filter will remove the 1g offset in the gravity direction
            </li>
            <li><i>highPassCutoffFrequency</i> 0 ... 3<br>
                set the high-pass filter cutoff frequency, changes with on output data rate, <i>default 0</i><br>
                0 is a higher cutoff frequency (up to 16 Hz) and 3 is a lower cutoff frequency (down to 0.25 Hz), see device manual for details
            </li>
            <li><i>orientation...</i><br>
                orientation detection parameters, see device manual for details
            </li>
            <li><i>motion...</i><br>
                motion/freefall detection parameters, see device manual for details
            </li>
            <li><i>jolt...</i><br>
                jolt detection parameters, see device manual for details
            </li>
            <li><i>pulse...</i><br>
                pulse (tap) detection parameters, see device manual for details
            </li>
            <li><i>...EventLatch</i> 0|1<br>
                if enabled an event (and the hardware output) will stay latched until the event source register is read, <i>default 0</i><br>
                the corresponding event source reading will provide additional information about the event
            </li>
            <li><i>...Interrupt</i> 0|1|2<br>
                an event will also raise one of two hardware outputs, <i>default 0</i><br>
                use 0 to disable linking an event with an hardware outputs
            </li>
        </ul>
    </ul>
    <br>

    <b>Readings</b>
    <ul>
        <ul>
            <li><i>out...</i><br>
                acceleration for x, y and z axes [g]<br>
                the number of decimal places is limited to 3 to remove a significant amount of noise
            </li>
            <li><i>off...</i><br>
                acceleration offset for x, y and z axes from last calibration [g]<br>
                to adjust offsets manually at runtime, change offset readings and toggle disable attribute
            </li>
            <li><i>orientation</i><br>
                current orientation, orientation detection must be enabled, the reading is only updated on change<br>
                P=portrait + U=up/D=down or L=landscape + L=left/R=right, B=back or F=front, X=z-lockout
            </li>
            <li><i>...Event</i><br>
                source of last event, event and event latch must be enabled, the reading is only updated on change<br>
                motion/jolt/pulse: X, Y or Z for the affected axis preceded by a sign for the direction of the the event<br>
                pulse: additional pulse type indicator postfix S=single or D=double
            </li>
        </ul>
    </ul>
</ul>

=end html
=cut

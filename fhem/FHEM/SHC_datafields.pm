#!/usr/bin/perl 

##########################################################################
# This file is part of the smarthomatic module for FHEM.
#
# Copyright (c) 2014 Uwe Freese
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
##########################################################################
# $Id: 37_SHC_Dev.pm xxxx 2014-xx-xx xx:xx:xx rr2000 $

package SHC_util;

# ----------- helper functions -----------

sub max($$)
{
  my ($x, $y) = @_;
  return $x >= $y ? $x : $y;
}

sub min($$)
{
  my ($x, $y) = @_;
  return $x <= $y ? $x : $y;
}

# clear some bits within a byte
sub clear_bits($$$)
{
  my ($input, $bit, $bits_to_clear) = @_;
  my $mask = (~((((1 << $bits_to_clear) - 1)) << (8 - $bits_to_clear - $bit)));
  return ($input & $mask);
}

# get some bits from a 32 bit value, counted from the left (MSB) side! The first bit is bit nr. 0.
sub get_bits($$$)
{
  my ($input, $bit, $len) = @_;
  return ($input >> (32 - $len - $bit)) & ((1 << $len) - 1);
}

sub getUInt($$$)
{
  my ($byteArrayRef, $offset, $length_bits) = @_;

  my $byte = $offset / 8;
  my $bit  = $offset % 8;

  my $byres_read = 0;
  my $val        = 0;
  my $shiftBits;

  # read the bytes one after another, shift them to the correct position and add them
  while ($length_bits + $bit > $byres_read * 8) {
    $shiftBits = $length_bits + $bit - $byres_read * 8 - 8;
    my $zz = @$byteArrayRef[$byte + $byres_read];

    if ($shiftBits >= 0) {
      $val += $zz << $shiftBits;
    } else {
      $val += $zz >> -$shiftBits;
    }

    $byres_read++;
  }

  # filter out only the wanted bits and clear unwanted upper bits
  if ($length_bits < 32) {
    $val = $val & ((1 << $length_bits) - 1);
  }

  return $val;
}

# write some bits to byte array only within one byte
sub setUIntBits($$$$$)
{
  my ($byteArrayRef, $byte, $bit, $length_bits, $val8) = @_;

  my $b = 0;

  # if length is smaller than 8 bits, get the old value from array
  if ($length_bits < 8) {
    $b = @$byteArrayRef[$byte];
    $b = clear_bits($b, $bit, $length_bits);
  }

  # set bits from given value
  $b = $b | ($val8 << (8 - $length_bits - $bit));

  @$byteArrayRef[$byte] = $b;
}

# Write UIntValue to data array
sub setUInt($$$$)
{
  my ($byteArrayRef, $offset, $length_bits, $value) = @_;

  my $byte = $offset / 8;
  my $bit  = $offset % 8;

  # move bits to the left border
  $value = $value << (32 - $length_bits);

  # DEBUG print "Moved left: val " . $value . "\r\n";

  # 1st byte
  my $src_start = 0;
  my $dst_start = $bit;
  my $len       = min($length_bits, 8 - $bit);
  my $val8      = get_bits($value, $src_start, $len);

  # DEBUG print "   Write bits to byte " . $byte . ", dst_start " . $dst_start . ", len " . $len . ", val8 " . $val8 . "\r\n";

  setUIntBits($byteArrayRef, $byte, $dst_start, $len, $val8);

  $dst_start = 0;
  $src_start = $len;

  while ($src_start < $length_bits) {
    $len = min($length_bits - $src_start, 8);
    $val8 = get_bits($value, $src_start, $len);
    $byte++;

    # DEBUG print "      Byte nr. " . $byte . ", src_start " . $src_start . ", len " . $len . ", val8 " . $val8 . "\r\n";

    setUIntBits($byteArrayRef, $byte, $dst_start, $len, $val8);

    $src_start += $len;
  }
}

sub getInt($$$)
{
  my ($byteArrayRef, $offset, $length_bits) = @_;

  # FIX ME! DOES NOT WORK WITH NEGATIVE VALUES!

  $x = getUInt($byteArrayRef, $offset, $length_bits);

  # If MSB is 1 (value is negative interpreted as signed int),
  # set all higher bits also to 1.
  if ((($x >> ($length_bits - 1)) & 1) == 1) {
    $x = $x | ~((1 << ($length_bits - 1)) - 1);
  }

  $y = $x;

  return $y;
}

# ----------- UIntValue class -----------

package UIntValue;

sub new
{
  my $class = shift;
  my $self  = {
    _id     => shift,
    _offset => shift,
    _bits   => shift,
  };
  bless $self, $class;
  return $self;
}

sub getValue
{
  my ($self, $byteArrayRef) = @_;

  return SHC_util::getUInt($byteArrayRef, $self->{_offset}, $self->{_bits});
}

sub setValue
{
  my ($self, $byteArrayRef, $value) = @_;

  SHC_util::setUInt($byteArrayRef, $self->{_offset}, $self->{_bits}, $value);
}

# ----------- IntValue class -----------

package IntValue;

sub new
{
  my $class = shift;
  my $self  = {
    _id     => shift,
    _offset => shift,
    _bits   => shift,
  };
  bless $self, $class;
  return $self;
}

sub getValue
{
  my ($self, $byteArrayRef) = @_;

  return SHC_util::getUInt($byteArrayRef, $self->{_offset}, $self->{_bits});
}

sub setValue
{
  my ($self, $byteArrayRef, $value) = @_;

  SHC_util::setUInt($byteArrayRef, $self->{_offset}, $self->{_bits}, $value);
}

# ----------- BoolValue class -----------

package BoolValue;

sub new
{
  my $class = shift;
  my $self  = {
    _id     => shift,
    _offset => shift,
    _length => shift,
  };
  bless $self, $class;
  return $self;
}

sub getValue
{
  my ($self, $byteArrayRef, $index) = @_;

  return SHC_util::getUInt($byteArrayRef, $self->{_offset} + $index, 1) == 1 ? 1 : 0;
}

sub setValue
{
  my ($self, $byteArrayRef, $value) = @_;

  return SHC_util::setUInt($byteArrayRef, $self->{_offset}, 1, $value == 0 ? 0 : 1);
}

# ----------- EnumValue class -----------

package EnumValue;

my %name2value = ();
my %value2name = ();

sub new
{
  my $class = shift;
  my $self  = {
    _id     => shift,
    _offset => shift,
    _bits   => shift,
  };
  bless $self, $class;
  return $self;
}

sub addValue
{
  my ($self, $name, $value) = @_;

  $name2value{$name}  = $value;
  $value2name{$value} = $name;
}

sub getValue
{
  my ($self, $byteArrayRef) = @_;

  my $value = SHC_util::getUInt($byteArrayRef, $self->{_offset}, $self->{_bits});
  return $value2name{$value};
}

sub setValue
{
  my ($self, $byteArrayRef, $name) = @_;

  my $value = $name2value{$name};
  SHC_util::setUInt($byteArrayRef, $self->{_offset}, $self->{_bits}, $value);
}

1;

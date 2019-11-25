################################################################################
#
# $Id$
#
# 66_EseraDigitalInOut.pm 
#
# Copyright (C) 2018  pizmus
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
################################################################################
#
# This FHEM module controls a digital input and/or output device connected via
# an Esera "1-wire Controller 1" with LAN interface and the 66_EseraOneWire 
# module.
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

my %deviceSpecs = ("DS2408" => 8, "11220" => 8, "11228" => 8, "11229" => 8, "11216" => 8, "SYS1" => 4, "SYS2" => 5);

sub 
EseraDigitalInOut_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "DS2408";
  $hash->{DefFn}         = "EseraDigitalInOut_Define";
  $hash->{UndefFn}       = "EseraDigitalInOut_Undef";
  $hash->{ParseFn}       = "EseraDigitalInOut_Parse";
  $hash->{SetFn}         = "EseraDigitalInOut_Set";
  $hash->{GetFn}         = "EseraDigitalInOut_Get";
  $hash->{AttrFn}        = "EseraDigitalInOut_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub
EseraDigitalInOut_calculateBits($$$$)
{
  my ($hash, $deviceType, $rawBitPos, $rawBitCount) = @_;
  my $name = $hash->{NAME};
  
  my $maxBitCount = $deviceSpecs{$deviceType};
  
  if (!defined $maxBitCount)
  {
    Log3 $name, 1, "EseraDigitalInOut ($name) - error looking up maximum bit width";
    return undef;
  }
  
  my $bitPos = 0;
  
  if (!($rawBitPos eq "-"))
  {
    if (($rawBitPos >= 0) && ($rawBitPos < $maxBitCount))
    {
      $bitPos = $rawBitPos;
    }
    else
    {
      Log3 $name, 1, "EseraDigitalInOut ($name) - specified bit field position is out of range";
    }
  }
  $hash->{BITPOS} = $bitPos; 
  
  my $bitCount = $maxBitCount - $bitPos;
  if (!($rawBitCount eq "-"))
  {
    if ($rawBitCount > $bitCount)
    {
      Log3 $name, 1, "EseraDigitalInOut ($name) - specified bit field size is out of range";
    }
    else
    {
      $bitCount = $rawBitCount;
    }
  }
  $hash->{BITCOUNT} = $bitCount;
  
  return 1;
}

sub 
EseraDigitalInOut_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  return "Usage: define <name> EseraDigitalInOut <physicalDevice> <1-wire-ID> <deviceType> (<bitPos>|-) (<bitCount>|-)" if(@a < 7);

  my $devName = $a[0];
  my $type = $a[1];
  my $physicalDevice = $a[2];
  my $oneWireId = $a[3];
  my $deviceType = uc($a[4]);
  my $bitPos = $a[5];
  my $bitCount = $a[6];
  
  $hash->{STATE} = 'Initialized';
  $hash->{NAME} = $devName;
  $hash->{TYPE} = $type;
  $hash->{ONEWIREID} = $oneWireId;
  $hash->{ESERAID} = undef;  # We will get this from the first reading.
  $hash->{DEVICE_TYPE} = $deviceType;
 
  my $success = EseraDigitalInOut_calculateBits($hash, $deviceType, $bitPos, $bitCount);
  if (!$success)
  {
    Log3 $devName, 1, "EseraDigitalInOut ($devName) - definition failed";
    return undef;
  }
  
  $modules{EseraDigitalInOut}{defptr}{$oneWireId} = $hash;
  
  AssignIoPort($hash, $physicalDevice);
  
  if (defined($hash->{IODev}->{NAME})) 
  {
    Log3 $devName, 4, "EseraDigitalInOut ($devName) - I/O device is " . $hash->{IODev}->{NAME};
  } 
  else 
  {
    Log3 $devName, 1, "EseraDigitalInOut ($devName) - no I/O device";
  }
    
  # program the the device type into the controller via the physical module
  if ($deviceType =~ m/^DS([0-9A-F]+)/)
  {
    # for the DS* devices types the "DS" has to be omitted
    IOWrite($hash, "assign;$oneWireId;$1");
  }
  elsif (!($deviceType =~ m/^SYS[12]/))
  {
    IOWrite($hash, "assign;$oneWireId;$deviceType");
  }
    
  return undef;
}

sub 
EseraDigitalInOut_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraDigitalInOut}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraDigitalInOut_Get($@) 
{
  return undef;
}

sub 
EseraDigitalInOut_setDS2408digout($$$$)
{
  my ($hash, $owId, $mask, $value) = @_;
  my $name = $hash->{NAME};
  
  if ($mask < 1)
  {
    my $message = "error: at least one mask bit must be set, mask ".$mask.", value ".$value;
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }
  
  if ($mask > 255) 
  {
    my $message = "error: mask is out of range";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }
  
  if (($value < 0) || ($value > 255))
  {
    my $message = "error: value out of range";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }
  
  # look up the ESERA ID
  my $eseraId = $hash->{ESERAID};
  if (!defined $eseraId)
  {
    my $message = "error: ESERA ID not known";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }

  # set values as given by mask and value
  if ($mask == 255)
  {
    # all bits are selected, use command to set all bits
    my $command = "set,owd,outh,".$eseraId.",".$value;
    IOWrite($hash, "set;$owId;$command");
    return undef;
  }
  else
  {
    # a subset of bits is selected, iterate over selected bits
    my $i;
    for ($i=0; $i<8; $i++)
    {
      if ($mask & 0x1)
      {
        my $bitValue = $value & 0x1;
        my $command = "set,owd,out,".$eseraId.",".$i.",".$bitValue;
        IOWrite($hash, "set;$owId;$command");
      }
      $mask = $mask >> 1;
      $value = $value >> 1;
    }
    return undef;
  }
   
  return undef;
}

sub 
EseraDigitalInOut_setSysDigout($$$$)
{
  my ($hash, $owId, $mask, $value) = @_;
  my $name = $hash->{NAME};
  
  if ($mask < 1)
  {
    my $message = "error: at least one mask bit must be set, mask ".$mask.", value ".$value;
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }
  
  if ($mask > 31) 
  {
    my $message = "error: mask is out of range";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }
  
  if (($value < 0) || ($value > 31))
  {
    my $message = "error: value out of range";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }
  
  # look up the ESERA ID
  my $eseraId = $hash->{ESERAID};
  if (!defined $eseraId)
  {
    my $message = "error: ESERA ID not known";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }

  # set values as given by mask and value
  if ($mask == 31)
  {
    # all bits are selected, use command to set all bits
    my $command = "set,sys,outh,".$value;
    IOWrite($hash, "set;$owId;$command");
    return undef;
  }
  else
  {
    # a subset of bits is selected, iterate over selected bits
    my $i;
    for ($i=0; $i<8; $i++)
    {
      if ($mask & 0x1)
      {
        my $bitValue = $value & 0x1;
        my $command = "set,sys,out,".($i+1).",".$bitValue;
        IOWrite($hash, "set;$owId;$command");
      }
      $mask = $mask >> 1;
      $value = $value >> 1;
    }
    return undef;
  }
   
  return undef;
}

sub
EseraDigitalInOut_calculateBitMasksForSet($$$)
{
  my ($hash, $mask, $value) = @_;
  my $name = $hash->{NAME}; 
  
  my $maxMask = (2**($hash->{BITCOUNT})) - 1;
  
  my $adjustedMask = ($mask & $maxMask) << $hash->{BITPOS};
  my $adjustedValue = ($value & $maxMask) << $hash->{BITPOS};
  
  return ($adjustedMask, $adjustedValue);
}

sub
EseraDigitalInOut_setOutput($$$$)
{
  my ($hash, $oneWireId, $mask, $value) = @_;
  my $name = $hash->{NAME}; 
  
  Log3 $name, 5, "EseraDigitalInOut ($name) - EseraDigitalInOut_setOutput inputs: $oneWireId,$mask,$value";
  
  if (!defined  $hash->{DEVICE_TYPE})
  {
    my $message = "error: device type not known";
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;        
  } 
  
  if (($hash->{DEVICE_TYPE} eq "DS2408") || 
      ($hash->{DEVICE_TYPE} eq "11220") ||
      ($hash->{DEVICE_TYPE} eq "11228") ||
      ($hash->{DEVICE_TYPE} eq "11229"))
  {
    my ($adjustedMask, $adjustedValue) = EseraDigitalInOut_calculateBitMasksForSet($hash, $mask, $value);
    
    Log3 $name, 5, "EseraDigitalInOut ($name) - EseraDigitalInOut_setOutput DS2408 adjustedMask: $adjustedMask, adjustedValue: $adjustedValue";
    EseraDigitalInOut_setDS2408digout($hash, $oneWireId, $adjustedMask, $adjustedValue);
  }
  elsif ($hash->{DEVICE_TYPE} eq "SYS2")
  {
    my ($adjustedMask, $adjustedValue) = EseraDigitalInOut_calculateBitMasksForSet($hash, $mask, $value);
    
    Log3 $name, 5, "EseraDigitalInOut ($name) - EseraDigitalInOut_setOutput SYS2 adjustedMask: $adjustedMask, adjustedValue: $adjustedValue";
    EseraDigitalInOut_setSysDigout($hash, $oneWireId, $adjustedMask, $adjustedValue);
  }
  elsif (($hash->{DEVICE_TYPE} eq "11216") || ($hash->{DEVICE_TYPE} eq "SYS1"))
  {
    Log3 $name, 1, "EseraDigitalInOut ($name) - error: trying to set digital output but this device only has inputs";
  }
  else
  {
    my $message = "error: device type not supported: ".$hash->{DEVICE_TYPE};
    Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
    return $message;    
  }

  return undef;
}

# interpret a string entered by the user as a number
sub 
EseraDigitalInOut_convertNumber($$)
{
  my ($hash, $numberString) = @_;
  $numberString = lc($numberString);
  my $number = undef;
  if ($numberString =~ m/^(\d+)$/)
  {
    $number = $1;
  }
  elsif (($numberString =~ m/^0b([01]+)$/) || ($numberString =~ m/^0x([a-f0-9]+)$/))
  {
    $number = oct($numberString);
  }
  return $number;
}

sub 
EseraDigitalInOut_Set($$) 
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
 
  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands = ("on:noArg off:noArg out");
  
  if ($what eq "out") 
  {
    if ((scalar(@parameters) != 4))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
      return $message;      
    }
    my $mask = EseraDigitalInOut_convertNumber($hash, $parameters[2]);
    my $value = EseraDigitalInOut_convertNumber($hash, $parameters[3]);
    EseraDigitalInOut_setOutput($hash, $oneWireId, $mask, $value);
    $hash->{LAST_OUT} = undef;
  }
  elsif ($what eq "on")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
      return $message;      
    }
    EseraDigitalInOut_setOutput($hash, $oneWireId, 0xFFFFFFFF, 0xFFFFFFFF);
    $hash->{LAST_OUT} = 1;
  }
  elsif ($what eq "off")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDigitalInOut ($name) - ".$message;
      return $message;      
    }
    EseraDigitalInOut_setOutput($hash, $oneWireId, 0xFFFFFFFF, 0x00000000);
    $hash->{LAST_OUT} = 0;
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of $commands";
    return $message;
  }
  else
  {
    shift @parameters;
    shift @parameters;
    return SetExtensions($hash, $commands, $name, $what, @parameters);
  }
  return undef;
}

sub
EseraDigitalInOut_getReadingValue($$$)
{
  my ($value, $bitPos, $bitCount) = @_;
  
  # The controller sends digital output state as binary mask (without leading 0b)
  my ($decimalValue) = oct("0b".$value);
  
  return ($decimalValue >> $bitPos) & ((2**$bitCount)-1);
}

sub
EseraDigitalInOut_ParseForOneDevice($$$$$$)
{
  my ($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value) = @_;
  my $rname = $rhash->{NAME};
  Log3 $rname, 4, "EseraDigitalInOut ($rname) - ParseForOneDevice: ".$rname;

  # capture the Esera ID for later use
  $rhash->{ESERAID} = $eseraId;
    
  # consistency check of device type
  if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
  {
    Log3 $rname, 1, "EseraDigitalInOut ($rname) - unexpected device type ".$deviceType;
    
    # program the the device type into the controller via the physical module
    if ($rhash->{DEVICE_TYPE} =~ m/^DS([0-9A-F]+)/)
    {
      # for the DS* devices types the "DS" has to be omitted
      IOWrite($rhash, "assign;$oneWireId;$1");
    }
    elsif (!($deviceType =~ m/^SYS[12]/))
    {
      IOWrite($rhash, "assign;$oneWireId;".$rhash->{DEVICE_TYPE});
    }
  }
   
  if ($readingId eq "ERROR")
  {
    Log3 $rname, 1, "EseraDigitalInOut ($rname) - error message from physical device: ".$value;
  }
  elsif ($readingId eq "STATISTIC")
  {
    Log3 $rname, 1, "EseraDigitalInOut ($rname) - statistics message not supported yet: ".$value;
  }
  else
  { 
    my $nameOfReading;
    if ($deviceType eq "DS2408")
    {
      if ($readingId == 2)
      {
        $nameOfReading = "in";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      } 
      elsif ($readingId == 4)
      {
        $nameOfReading = "out";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
    }
    elsif (($deviceType eq "11220") || ($deviceType eq "11228")) # 8 channel digital output with push buttons
    {
      if ($readingId == 2)
      {
        $nameOfReading = "in";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
      if ($readingId == 4)
      {
        $nameOfReading = "out";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
    }      
    elsif ($deviceType eq "11229") # 8 channel digital output
    {
      if ($readingId == 4)
      {
        $nameOfReading = "out";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
    }      
    elsif ($deviceType eq "11216")  # 8 channel digital input
    {
      if ($readingId == 2)
      {
        $nameOfReading = "in";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
    }
    elsif ($deviceType eq "SYS2")  # Controller 2 digital output
    {
      if ($readingId == 2)
      {
        $nameOfReading = "out";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
    }      
    elsif ($deviceType eq "SYS1")  # Controller 2 digital input
    {
      if ($readingId == 2)
      {
        $nameOfReading = "in";
        my $readingValue = EseraDigitalInOut_getReadingValue($value, $rhash->{BITPOS}, $rhash->{BITCOUNT});
        readingsSingleUpdate($rhash, $nameOfReading, $readingValue, 1);
      }
    }
  }
  return $rname;
}

sub 
EseraDigitalInOut_Parse($$) 
{
  my ($ioHash, $msg) = @_;
  my $ioName = $ioHash->{NAME};
  my $buffer = $msg;

  # expected message format: $deviceType."_".$oneWireId."_".$eseraId."_".$readingId."_".$value
  my @fields = split(/_/, $buffer);
  if (scalar(@fields) != 5)
  {
    return undef;
  }
  my $deviceType = uc($fields[0]);
  my $oneWireId = $fields[1];
  my $eseraId = $fields[2];
  my $readingId = $fields[3];
  my $value = $fields[4];

  # search for logical device
  my $rhash = undef;  
  my @list;
  foreach my $d (keys %defs) 
  {
    my $h = $defs{$d};
    my $type = $h->{TYPE};
        
    if($type eq "EseraDigitalInOut") 
    {
      if (defined($h->{IODev}->{NAME})) 
      {
        my $ioDev = $h->{IODev}->{NAME};
        my $def = $h->{DEF};

        # $def has the whole definition, extract the oneWireId (which is expected as 2nd parameter)
        my @parts = split(/ /, $def);
	my $oneWireIdFromDef = $parts[1];
	
        if (($ioDev eq $ioName) && ($oneWireIdFromDef eq $oneWireId)) 
	{
          $rhash = $h;  
	  my $rname = EseraDigitalInOut_ParseForOneDevice($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value);
          push(@list, $rname);
        }
      }
    }
  }
 
  if ((scalar @list) > 0) 
  {
    return @list;
  }
  elsif (($deviceType eq "DS2408") or ($deviceType eq "11216") or
         ($deviceType eq "11220") or  
         ($deviceType eq "11228") or ($deviceType eq "11229") or
         ($deviceType eq "SYS1") or ($deviceType eq "SYS2"))
  {
    return "UNDEFINED EseraDigitalInOut_".$ioName."_".$oneWireId." EseraDigitalInOut ".$ioName." ".$oneWireId." ".$deviceType." - -";
  }
  
  return undef;
}

sub 
EseraDigitalInOut_Attr(@) 
{
}



1;

=pod
=item summary    Represents a 1-wire digital input/output.
=item summary_DE Repraesentiert einen 1-wire digitalen Eingang/Ausgang.
=begin html

<a name="EseraDigitalInOut"></a>
<h3>EseraDigitalInOut</h3>

<ul>
  This module implements a 1-wire digital input/output. It uses 66_EseraOneWire <br>
  as I/O device.<br>
  <br>
  
  <a name="EseraDigitalInOut_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraDigitalInOut &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt; &lt;bitPos&gt; &lt;bitCount&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the digital input/output chip.<br>
    Use the "get devices" query of EseraOneWire to get a list of 1-wire IDs, <br>
    or simply rely on autocreate.<br>
    Supported values for deviceType:
    <ul> 
      <li>DS2408</li>
      <li>11220/11228 (Esera "Digital Out 8-Channel with push-button interface")</li> 
      <li>11229 (Esera "Digital Out 8-Channel")</li> 
      <li>11216 (Esera "8-Channel Digital Input DC")</li>
      <li>SYS1 (Esera Controller 2, digital input, not listed by "get devices")</li>
      <li>SYS2 (Esera Controller 2, digital output, not listed by "get devices")</li>
    </ul>
    The bitPos and bitCount parameters is used to specify a subset of bits only. <br>
    For example, the DS2408 has 8 inputs, and you can define a EseraDigitalInOut <br>
    that uses bits 4..7 (in range 0..7). In this case you specify bitPos = 4 and <br>
    bitWidth = 4.<br>
    You can also give "-" for bitPos and bitWidth. In this case the module uses<br>
    the maximum possible bit range, which is bitPos = 0 and bitWidth = 8 for DS2408.<br>
    In typical use cases the n bits of a digital input device are used to control <br>
    or observe n different things, e.g. 8 motion sensors connected to 8 digital inputs.<br>
    In this case you would define 8 EseraDigitalInOut devices, one for each motion sensor.<br>
  </ul>
  <br>
  
  <a name="EseraDigitalInOut_Set"></a>
  <b>Set</b>
  <ul>
    <li>
      <b><code>set &lt;name&gt; out &lt;bitMask&gt; &lt;bitValue&gt;</code><br></b>
      Controls digital outputs. The bitMask selects bits that are programmed, <br>
      and bitValue specifies the new value.<br>
      Examples: <code>set myEseraDigitalInOut out 0xf 0x3</code><br>
      In this example the four lower outputs are selected by the mask, <br>
      and they get the new value 0x3 = 0b0011.<br>
      bitMask and bitValue can be specified as hex number (0x...), binary<br>
      number (0b....) or decimal number.<br>
      Note: If all bits are selected by mask the outputs are set by a single <br>
      access to the controller. If subset of bits is selected the bits are set <br>
      by individual accesses, one after the other, as fast as the controller allows.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; on</code><br></b>
      Switch on all outputs.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; off</code><br></b>
      Switch off all outputs.<br>
    </li>
  </ul>
  <br>

  <a name="EseraDigitalInOut_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraDigitalInOut_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>no attributes</li>  
  </ul>
  <br>
      
  <a name="EseraDigitalInOut_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>in &ndash; digital input state</li>
    <li>out &ndash; digital output state</li>
  </ul>
  <br>

</ul>

=end html
=cut

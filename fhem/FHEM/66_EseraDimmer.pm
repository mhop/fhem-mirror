################################################################################
#
# $Id$
#
# 66_EseraDimmer.pm 
#
# Copyright (C) 2020  pizmus
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

package main;

use strict;
use warnings;
use SetExtensions;

sub 
EseraDimmer_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "11221|11222";
  $hash->{DefFn}         = "EseraDimmer_Define";
  $hash->{UndefFn}       = "EseraDimmer_Undef";
  $hash->{ParseFn}       = "EseraDimmer_Parse";
  $hash->{SetFn}         = "EseraDimmer_Set";
  $hash->{AttrFn}        = "EseraDimmer_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub 
EseraDimmer_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  return "Usage: define <name> EseraDimmer <physicalDevice> <1-wire-ID> <deviceType> <channel> " if(@a < 6);

  my $devName = $a[0];
  my $type = $a[1];
  my $physicalDevice = $a[2];
  my $oneWireId = $a[3];
  my $deviceType = uc($a[4]);
  my $channel = $a[5];
  
  $hash->{STATE} = 'Initialized';
  $hash->{NAME} = $devName;
  $hash->{TYPE} = $type;
  $hash->{ONEWIREID} = $oneWireId;
  $hash->{ESERAID} = undef;  # We will get this from the first reading.
  $hash->{LAST_OUT} = undef;
  
  if (($deviceType eq "11221") or ($deviceType eq "11222"))
  {
    $hash->{DEVICE_TYPE} = $deviceType;
  }
  else
  {
    Log3 $devName, 4, "EseraDimmer ($devName) - invalid device type";
    return "Usage: define <name> EseraDimmer <physicalDevice> <1-wire-ID> <deviceType> <channel> " if(@a < 6);
  }
  
  if (($channel eq "1") or ($channel eq "2"))
  {
    $hash->{CHANNEL} = $channel;
  }
  else
  {
    Log3 $devName, 4, "EseraDimmer ($devName) - invalid channel";
    return "Usage: define <name> EseraDimmer <physicalDevice> <1-wire-ID> <deviceType> <channel> " if(@a < 6);
  }
   
  $modules{EseraDimmer}{defptr}{$oneWireId} = $hash;
  
  AssignIoPort($hash, $physicalDevice);
  
  if (defined($hash->{IODev}->{NAME})) 
  {
    Log3 $devName, 4, "EseraDimmer ($devName) - I/O device is " . $hash->{IODev}->{NAME};
  } 
  else 
  {
    Log3 $devName, 1, "EseraDimmer ($devName) - no I/O device";
  }
    
  return undef;
}

sub 
EseraDimmer_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraDimmer}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraDimmer_setOutput($$$)
{
  my ($hash, $owId, $value) = @_;
  my $name = $hash->{NAME};
  
  if (($value < 0) || ($value > 31))
  {
    my $message = "error: value out of range";
    Log3 $name, 1, "EseraDimmer ($name) - ".$message;
    return $message;    
  }
  
  # look up the ESERA ID
  my $eseraId = $hash->{ESERAID};
  if (!defined $eseraId)
  {
    my $message = "error: ESERA ID not known";
    Log3 $name, 1, "EseraDimmer ($name) - ".$message;
    return $message;    
  }

  # set value
  my $command = "set,owd,dim,".$eseraId.",".$hash->{CHANNEL}.",".$value;
  IOWrite($hash, "set;$owId;$command");
   
  return undef;
}

# interpret a string entered by the user as a number
sub 
EseraDimmer_convertNumber($$)
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
EseraDimmer_Set($$) 
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
 
  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands = ("on:noArg off:noArg out up:noArg down:noArg");
  
  if ($what eq "out") 
  {
    if ((scalar(@parameters) != 3))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDimmer ($name) - ".$message;
      return $message;      
    }
    my $value = EseraDimmer_convertNumber($hash, $parameters[2]);
    EseraDimmer_setOutput($hash, $oneWireId, $value);
    $hash->{LAST_OUT} = $value;
  }
  elsif ($what eq "on")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDimmer ($name) - ".$message;
      return $message;      
    }
    EseraDimmer_setOutput($hash, $oneWireId, 31);
    $hash->{LAST_OUT} = 31;
  }
  elsif ($what eq "off")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDimmer ($name) - ".$message;
      return $message;      
    }
    EseraDimmer_setOutput($hash, $oneWireId, 0);
    $hash->{LAST_OUT} = 0;
  }
  elsif ($what eq "up")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDimmer ($name) - ".$message;
      return $message;      
    }
    if ((defined $hash->{LAST_OUT}) and ($hash->{LAST_OUT} < 31))
    {
      $hash->{LAST_OUT} = $hash->{LAST_OUT} + 1;
      EseraDimmer_setOutput($hash, $oneWireId, $hash->{LAST_OUT});
    }
  }
  elsif ($what eq "down")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraDimmer ($name) - ".$message;
      return $message;      
    }
    if ((defined $hash->{LAST_OUT}) and ($hash->{LAST_OUT} > 0))
    {
      $hash->{LAST_OUT} = $hash->{LAST_OUT} - 1;
      EseraDimmer_setOutput($hash, $oneWireId, $hash->{LAST_OUT});
    }
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
EseraDimmer_ParseForOneDevice($$$$$$)
{
  my ($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value) = @_;
  my $rname = $rhash->{NAME};
  Log3 $rname, 4, "EseraDimmer ($rname) - ParseForOneDevice: ".$rname;

  # capture the Esera ID for later use
  $rhash->{ESERAID} = $eseraId;
    
  # consistency check of device type
  if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
  {
    Log3 $rname, 1, "EseraDimmer ($rname) - unexpected device type ".$deviceType;
  }
   
  if ($readingId eq "ERROR")
  {
    Log3 $rname, 1, "EseraDimmer ($rname) - error message from physical device: ".$value;
  }
  elsif ($readingId eq "STATISTIC")
  {
    Log3 $rname, 1, "EseraDimmer ($rname) - statistics message not supported yet: ".$value;
  }
  else
  { 
    my $nameOfReading;
    if (($deviceType eq "11221") || ($deviceType eq "11222")) 
    {
      if ($rhash->{CHANNEL} == 1)
      {
        if ($readingId == 3)
        {
          $rhash->{LAST_OUT} = $value;
          $nameOfReading = "out";
          readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
        }
        elsif ($readingId == 1)
        {
          # Tasterschnittstelle Kanal 1 = 1, Tasterschnittstelle Kanal 2 = 2, Modultaster Kanal 1 = 4, Modultaster Kanal 2 = 8
          $nameOfReading = "button";
          my $buttonPressed = 0;
          if ((($value & 0x1) != 0) or (($value & 0x4) != 0))
          {
            $buttonPressed = 1;
          }
          readingsSingleUpdate($rhash, $nameOfReading, $buttonPressed, 1);
        }        
      }
      elsif ($rhash->{CHANNEL} == 2)
      {
        if ($readingId == 4)
        {
          $rhash->{LAST_OUT} = $value;
          $nameOfReading = "out";
          readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
        }
        elsif ($readingId == 1)
        {
          # Tasterschnittstelle Kanal 1 = 1, Tasterschnittstelle Kanal 2 = 2, Modultaster Kanal 1 = 4, Modultaster Kanal 2 = 8
          $nameOfReading = "button";
          my $buttonPressed = 0;
          if ((($value & 0x2) != 0) or (($value & 0x8) != 0))
          {
            $buttonPressed = 1;
          }
          readingsSingleUpdate($rhash, $nameOfReading, $buttonPressed, 1);
        }
      }
    }      
  }
  return $rname;
}

sub 
EseraDimmer_Parse($$) 
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
        
    if($type eq "EseraDimmer") 
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
          
          # readingId 4 is for channel 2 only. Ignore it with channel 1.  
          if (not (($rhash->{CHANNEL} == 1) and ($readingId == 4)))
          {
	    my $rname = EseraDimmer_ParseForOneDevice($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value);
            push(@list, $rname);
          }
        }
      }
    }
  }
 
  if ((scalar @list) > 0) 
  {
    return @list;
  }
  elsif (($deviceType eq "11221") or ($deviceType eq "11222"))
  {
    my $channel = 1;
    
    if ($readingId == 4)
    {
      # readingId 4 is for channel 2
      $channel = 2;
    }
    
    return "UNDEFINED EseraDimmer_".$ioName."_".$oneWireId."_".$channel." EseraDimmer ".$ioName." ".$oneWireId." ".$deviceType." ".$channel;
  }
  
  return undef;
}

sub 
EseraDimmer_Attr(@) 
{
}



1;

=pod
=item summary    Represents an Esera 1-wire dimmer.
=item summary_DE Repraesentiert einen Esera 1-wire Dimmer.
=begin html

<a name="EseraDimmer"></a>
<h3>EseraDimmer</h3>

<ul>
  This module implements an Esera 1-wire dimmer. It uses 66_EseraOneWire as I/O device.<br>
  <br>
  
  <a name="EseraDimmer_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraDimmer &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt; &lt;channel&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the digital input/output chip.<br>
    Use the "get devices" query of EseraOneWire to get a list of 1-wire IDs, <br>
    or simply rely on autocreate.<br>
    Supported values for deviceType:
    <ul> 
      <li>11221</li> 
      <li>11222</li> 
    </ul>
    &lt;channel&gt; specifies the channel, 1 or 2.
  </ul>
  <br>
  
  <a name="EseraDimmer_Set"></a>
  <b>Set</b>
  <ul>
    <li>
      <b><code>set &lt;name&gt; out &lt;value&gt;</code><br></b>
    </li>
    <li>
      <b><code>set &lt;name&gt; on</code><br></b>
      Sets the dimmer to the maximum value 31.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; off</code><br></b>
      Sets the dimmer to the minimum value 0.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; up</code><br></b>
      Increase dimmer value by 1.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; down</code><br></b>
      Reduce dimmer value by 1.<br>
    </li>
  </ul>
  <br>

  <a name="EseraDimmer_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>out &ndash; output state</li>
    <li>button &ndash; state of the push button, 1=pressed, 0=not pressed</li>
  </ul>
  <br>

</ul>

=end html
=cut

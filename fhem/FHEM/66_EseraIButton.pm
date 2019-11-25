################################################################################
#
# $Id$
#
# 66_EseraIButton.pm 
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
# This FHEM module supports iButton devices connected via an Esera 1-wire Controller
# and the 66_EseraOneWire module.
# For more details please read the device specific help / commandref.
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

sub 
EseraIButton_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "DS2401";
  $hash->{DefFn}         = "EseraIButton_Define";
  $hash->{UndefFn}       = "EseraIButton_Undef";
  $hash->{ParseFn}       = "EseraIButton_Parse";
  $hash->{SetFn}         = "EseraIButton_Set";
  $hash->{GetFn}         = "EseraIButton_Get";
  $hash->{AttrFn}        = "EseraIButton_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub 
EseraIButton_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  return "Usage: define <name> EseraIButton <physicalDevice> <1-wire-ID> <deviceType>" if(@a < 5);

  my $devName = $a[0];
  my $type = $a[1];
  my $physicalDevice = $a[2];
  my $oneWireId = $a[3];
  my $deviceType = uc($a[4]);

  $hash->{STATE} = 'Initialized';
  $hash->{NAME} = $devName;
  $hash->{TYPE} = $type;
  $hash->{ONEWIREID} = $oneWireId;
  $hash->{ESERAID} = undef;  # We will get this from the first reading.
  $hash->{DEVICE_TYPE} = $deviceType;
 
  $modules{EseraIButton}{defptr}{$oneWireId} = $hash;
  
  AssignIoPort($hash, $physicalDevice);
  
  if (defined($hash->{IODev}->{NAME})) 
  {
    Log3 $devName, 4, "$devName: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else 
  {
    Log3 $devName, 1, "$devName: no I/O device";
  }
    
  return undef;
}

sub 
EseraIButton_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraIButton}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraIButton_Get($@) 
{
  return undef;
}

sub 
EseraIButton_Set($$) 
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
 
  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands = ("statusRequest");
  
  if ($what eq "statusRequest")
  {
    IOWrite($hash, "status;$oneWireId");
  }
  elsif ($what eq "?")
  {
    # TODO use the :noArg info 
    my $message = "unknown argument $what, choose one of $commands";
    return $message;
  }
  else
  {
    my $message = "unknown argument $what, choose one of $commands";
    Log3 $name, 1, "EseraIButton ($name) - ".$message;
    return $message;
  }
  return undef;
}

sub 
EseraIButton_Parse($$) 
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
  foreach my $d (keys %defs) {
    my $h = $defs{$d};
    my $type = $h->{TYPE};
        
    if($type eq "EseraIButton") 
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
          last;
        }
      }
    }
  }
 
  if($rhash) {
    my $rname = $rhash->{NAME};
    Log3 $rname, 4, "EseraIButton ($rname) - parse - device found: ".$rname;

    # capture the Esera ID for later use
    $rhash->{ESERAID} = $eseraId;
    
    # consistency check of device type
    if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
    {
      Log3 $rname, 1, "EseraIButton ($rname) - unexpected device type ".$deviceType;
    }
    
    if ($readingId eq "ERROR")
    {
      Log3 $rname, 1, "EseraIButton ($rname) - error message from physical device: ".$value;
    }
    elsif ($readingId eq "STATISTIC")
    {
      Log3 $rname, 1, "EseraIButton ($rname) - statistics message not supported yet: ".$value;
    }
    else
    {
      my $nameOfReading = "status";
      readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
    }
           
    my @list;
    push(@list, $rname);
    return @list;
  }
  elsif ($deviceType eq "DS2401") # TODO
  {
    return "UNDEFINED EseraIButton_".$ioName."_".$oneWireId." EseraIButton ".$ioName." ".$oneWireId." ".$deviceType;
  }
  
  return undef;
}

sub 
EseraIButton_Attr(@) 
{
}

1;

=pod
=item summary    Represents a 1-wire iButton device.
=item summary_DE Repraesentiert einen 1-wire iButton.
=begin html

<a name="EseraIButton"></a>
<h3>EseraIButton</h3>

<ul>
  This module supports 1-wire iButton devices. It uses 66_EseraOneWire as I/O device.<br>
  Events are generated for connecting and disconnecting an iButton.<br>
  <br>
  The Esera Controller needs to know the iButton so that it can detect it quickly when it <br>
  is connected. The iButton needs to be in the list of devices which is stored in a non-volatile <br>
  memory in the controller. Initially, you need to connect a new iButton for ~10 seconds. Use the <br>
  "get devices" query of EseraOneWire to check whether the device has been detected. When it has <br>
  been detected use "set savelist" to store the current list in the controller. Repeat the same <br>
  procedure with additional iButtons. Alternatively, you can use the "Config Tool 3" software from <br>
  Esera to store iButton devices in the controller.<br>
  <br>
  It is stronly recommended to use the additional license "iButton Fast Mode" from Esera (product <br>
  number 40202). With this license the controller detects iButton devices quickly. Without that <br>
  license the controller sometimes needs quite long to detect an iButton. <br>
  <br>
  See the "Programmierhandbuch" from Esera for details.<br>
  <br>
  
  <a name="EseraIButton_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraIButton &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt;</code> <br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the iButton.<br>
    Supported values for deviceType: DS2401<br>
  </ul>
  <br>
  
  <a name="EseraIButton_Set"></a>
  <b>Set</b>
  <ul>
    <li>no set functionality</li>
  </ul>
  <br>

  <a name="EseraIButton_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraIButton_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>no attributes</li>
  </ul>
  <br>
      
  <a name="EseraIButton_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>status &ndash; connection status 0 or 1</li>
  </ul>
  <br>

</ul>

=end html
=cut

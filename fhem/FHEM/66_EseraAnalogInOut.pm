################################################################################
#
# $Id$
#
# 66_EseraAnalogInOut.pm 
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
# This FHEM module controls analog input/output devices connected via
# an Esera 1-wire controller and the 66_EseraOneWire module.
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

my %SYS3Specs = (
  factor => 0.01,  # factor to get from raw reading to value in given unit
  unit => "V",
  lowLimit => 0.0,
  highLimit => 10.0,
  defaultValue => 0.0
);

my %DS2450Specs = (
  factor => 0.01,  # factor to get from raw reading to value in given unit
  unit => "V",
  lowLimit => 0.0,
  highLimit => 0.0,
  defaultValue => 0.0
);

my %Esera11202Specs = (
  factor => 0.01,  # factor to get from raw reading to value in given unit
  unit => "V",
  lowLimit => 0.0,
  highLimit => 0.0,
  defaultValue => 0.0
);

my %Esera11203Specs = (
  factor => 0.01,  # factor to get from raw reading to value in given unit
  unit => "V",
  lowLimit => 0.0,
  highLimit => 0.0,
  defaultValue => 0.0
);

my %Esera11208Specs = (
  factor => 0.01,  # factor to get from raw reading to value in given unit
  unit => "V",
  lowLimit => 0.0,
  highLimit => 10.0,
  defaultValue => 0.0
);

my %Esera11219Specs = (
  factor => 0.01,  # factor to get from raw reading to value in given unit
  unit => "mA",
  lowLimit => 0.0,
  highLimit => 20.0,
  defaultValue => 0.0
);

my %EseraAnalogInOutSpecs = (
  "SYS3" => \%SYS3Specs,
  "DS2450" => \%DS2450Specs,
  "11202" => \%Esera11202Specs,
  "11203" => \%Esera11203Specs,
  "11208" => \%Esera11208Specs,
  "11219" => \%Esera11219Specs
  );

sub 
EseraAnalogInOut_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "SYS3|DS2450|11202|11203|11208|11219";
  $hash->{DefFn}         = "EseraAnalogInOut_Define";
  $hash->{UndefFn}       = "EseraAnalogInOut_Undef";
  $hash->{ParseFn}       = "EseraAnalogInOut_Parse";
  $hash->{SetFn}         = "EseraAnalogInOut_Set";
  $hash->{GetFn}         = "EseraAnalogInOut_Get";
  $hash->{AttrFn}        = "EseraAnalogInOut_Attr";
  $hash->{AttrList}      = "LowValue HighValue ".$readingFnAttributes;
}

sub 
EseraAnalogInOut_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  my $usage = "Usage: define <name> EseraAnalogInOut <physicalDevice> <1-wire-ID> <deviceType> <lowLimit|-> <highLimit|->";
  
  return $usage if(@a < 7);

  my $devName = $a[0];
  my $type = $a[1];
  my $physicalDevice = $a[2];
  my $oneWireId = $a[3];
  my $deviceType = uc($a[4]);
  my $lowLimit = $a[5];
  my $highLimit = $a[6];
  
  $hash->{STATE} = 'Initialized';
  $hash->{NAME} = $devName;
  $hash->{TYPE} = $type;
  $hash->{ONEWIREID} = $oneWireId;
  $hash->{ESERAID} = undef;  # We will get this from the first reading.
  $hash->{DEVICE_TYPE} = $deviceType;
 
  $modules{EseraAnalogInOut}{defptr}{$oneWireId} = $hash;
  
  AssignIoPort($hash, $physicalDevice);
  
  if (defined($hash->{IODev}->{NAME})) 
  {
    Log3 $devName, 4, "EseraAnalogInOut ($devName) - I/O device is " . $hash->{IODev}->{NAME};
  } 
  else 
  {
    Log3 $devName, 1, "EseraAnalogInOut ($devName) - no I/O device";
    return $usage;
  }

  # check and use LowLimit and HighLimit
  if (!defined($EseraAnalogInOutSpecs{$deviceType}))
  {
    Log3 $devName, 1, "EseraAnalogInOut ($devName) - unknown device type".$deviceType;
    return $usage;
  }
  
  if (($lowLimit eq "-") || ($lowLimit < $EseraAnalogInOutSpecs{$deviceType}->{lowLimit}))
  {
    $lowLimit = $EseraAnalogInOutSpecs{$deviceType}->{lowLimit};
  }
  if (($highLimit eq "-") || ($highLimit > $EseraAnalogInOutSpecs{$deviceType}->{highLimit}))
  {
    $highLimit = $EseraAnalogInOutSpecs{$deviceType}->{highLimit};
  }
  $hash->{LOW_LIMIT} = $lowLimit;
  $hash->{HIGH_LIMIT} = $highLimit;

  # program the the device type into the controller via the physical module
  if ($deviceType =~ m/^DS([0-9A-F]+)/)
  {
    # for the DS* devices types the "DS" has to be omitted
    IOWrite($hash, "assign;$oneWireId;$1");
  }
  elsif (!($deviceType =~ m/^SYS3/))
  {
    IOWrite($hash, "assign;$oneWireId;$deviceType");
  }
    
  return undef;
}

sub 
EseraAnalogInOut_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraAnalogInOut}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraAnalogInOut_Get($@) 
{
  return undef;
}

sub 
EseraAnalogInOut_setSysDigout($$$)
{
  my ($hash, $owId, $value) = @_;
  my $name = $hash->{NAME};
  
  if (($value < $hash->{LOW_LIMIT}) || ($value > $hash->{HIGH_LIMIT}))
  {
    my $message = "error: value out of range ".$value." ".$hash->{LOW_LIMIT}." ".$hash->{HIGH_LIMIT};
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }
  
  # look up the ESERA ID
  my $eseraId = $hash->{ESERAID};
  if (!defined $eseraId)
  {
    my $message = "error: ESERA ID not known";
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }

  # set value
  my $command = "set,sys,outa,".int($value / $EseraAnalogInOutSpecs{SYS3}->{factor});
  IOWrite($hash, "set;$owId;$command");
  
  return undef;
}

sub 
EseraAnalogInOut_set11208Digout($$$)
{
  my ($hash, $owId, $value) = @_;
  my $name = $hash->{NAME};
  
  if (($value < $hash->{LOW_LIMIT}) || ($value > $hash->{HIGH_LIMIT}))
  {
    my $message = "error: value out of range ".$value." ".$hash->{LOW_LIMIT}." ".$hash->{HIGH_LIMIT};
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }
  
  # look up the ESERA ID
  my $eseraId = $hash->{ESERAID};
  if (!defined $eseraId)
  {
    my $message = "error: ESERA ID not known";
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }

  # set value
  # SET,OWD,OUTA,OWD-Nummer,Ausgangsspannung
  my $command = "set,owd,outa,".$eseraId.",".int($value / $EseraAnalogInOutSpecs{$hash->{DEVICE_TYPE}}->{factor});
  IOWrite($hash, "set;$owId;$command");
  
  return undef;
}

sub 
EseraAnalogInOut_set11219Digout($$$)
{
  my ($hash, $owId, $value) = @_;
  my $name = $hash->{NAME};
  
  if (($value < $hash->{LOW_LIMIT}) || ($value > $hash->{HIGH_LIMIT}))
  {
    my $message = "error: value out of range ".$value." ".$hash->{LOW_LIMIT}." ".$hash->{HIGH_LIMIT};
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }
  
  # look up the ESERA ID
  my $eseraId = $hash->{ESERAID};
  if (!defined $eseraId)
  {
    my $message = "error: ESERA ID not known";
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }

  # set value
  # SET,OWD,OUTAMA,OWD-Nummer,Ausgangsstrom
  my $command = "set,owd,outama,".$eseraId.",".int($value / $EseraAnalogInOutSpecs{$hash->{DEVICE_TYPE}}->{factor});
  IOWrite($hash, "set;$owId;$command");
  
  return undef;
}

sub
EseraAnalogInOut_setOutput($$$)
{
  my ($hash, $oneWireId, $value) = @_;
  my $name = $hash->{NAME}; 
  
  if (!defined  $hash->{DEVICE_TYPE})
  {
    my $message = "error: device type not known";
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;        
  } 
  
  if ($hash->{DEVICE_TYPE} eq "SYS3")
  {
    Log3 $name, 5, "EseraAnalogInOut ($name) - EseraAnalogInOut_setOutput SYS3 value: $value";
    EseraAnalogInOut_setSysDigout($hash, $oneWireId, $value);
  }
  elsif ($hash->{DEVICE_TYPE} eq "11208")
  {
    Log3 $name, 5, "EseraAnalogInOut ($name) - EseraAnalogInOut_setOutput value: $value";
    EseraAnalogInOut_set11208Digout($hash, $oneWireId, $value);
  }
  elsif ($hash->{DEVICE_TYPE} eq "11219")
  {
    Log3 $name, 5, "EseraAnalogInOut ($name) - EseraAnalogInOut_setOutput value: $value";
    EseraAnalogInOut_set11219Digout($hash, $oneWireId, $value);
  }
  else
  {
    my $message = "error: device type not supported as analog output: ".$hash->{DEVICE_TYPE};
    Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
    return $message;    
  }

  return undef;
}

sub 
EseraAnalogInOut_Set($$) 
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
 
  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands = ("on off out");
  
  if ($what eq "out") 
  {
    if ((scalar(@parameters) != 3))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
      return $message;      
    }
    my $value = $parameters[2];
    EseraAnalogInOut_setOutput($hash, $oneWireId, $value);
    $hash->{LAST_OUT} = undef;
  }
  elsif ($what eq "on")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
      return $message;      
    }
    my $value = AttrVal($name, "HighValue", $EseraAnalogInOutSpecs{$hash->{DEVICE_TYPE}}->{defaultValue});
    EseraAnalogInOut_setOutput($hash, $oneWireId, $value);
    $hash->{LAST_OUT} = 1;
  }
  elsif ($what eq "off")
  {
    if ((scalar(@parameters) != 2))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraAnalogInOut ($name) - ".$message;
      return $message;      
    }
    my $value = AttrVal($name, "LowValue", $EseraAnalogInOutSpecs{$hash->{DEVICE_TYPE}}->{defaultValue});
    EseraAnalogInOut_setOutput($hash, $oneWireId, $value);
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
EseraAnalogInOut_ParseForOneDevice($$$$$$)
{
  my ($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value) = @_;
  my $rname = $rhash->{NAME};
  Log3 $rname, 4, "EseraAnalogInOut ($rname) - ParseForOneDevice: ".$rname;

  # capture the Esera ID for later use
  $rhash->{ESERAID} = $eseraId;
    
  # consistency check of device type
  if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
  {
    Log3 $rname, 1, "EseraAnalogInOut ($rname) - unexpected device type ".$deviceType;
    
    # program the the device type into the controller via the physical module
    if ($rhash->{DEVICE_TYPE} =~ m/^DS([0-9A-F]+)/)
    {
      # for the DS* devices types the "DS" has to be omitted
      IOWrite($rhash, "assign;$oneWireId;$1");
    }
    elsif (!($rhash->{DEVICE_TYPE} =~ m/^SYS3/))
    {
      IOWrite($rhash, "assign;$oneWireId;".$rhash->{DEVICE_TYPE});
    }
  }
   
  if ($readingId eq "ERROR")
  {
    Log3 $rname, 1, "EseraAnalogInOut ($rname) - error message from physical device: ".$value;
  }
  elsif ($readingId eq "STATISTIC")
  {
    Log3 $rname, 1, "EseraAnalogInOut ($rname) - statistics message not supported yet: ".$value;
  }
  else
  { 
    my $nameOfReading = "";
    if (($deviceType eq "SYS3") || ($deviceType eq "11208") || ($deviceType eq "11219"))
    {
      if ($readingId == 0)
      {
        $nameOfReading .= "out";
        my $readingValue = $value * $EseraAnalogInOutSpecs{$deviceType}->{factor};
	my $reading = $readingValue." ".$EseraAnalogInOutSpecs{$deviceType}->{unit};
        readingsSingleUpdate($rhash, $nameOfReading, $reading, 1);
      }
    }
    elsif (($deviceType eq "DS2450") || ($deviceType eq "11202") || ($deviceType eq "11203"))
    {
      if (($readingId >=1) && ($readingId <=4))
      {
        $nameOfReading .= "in".$readingId;
        my $readingValue = $value * $EseraAnalogInOutSpecs{$deviceType}->{factor};
	my $reading = $readingValue." ".$EseraAnalogInOutSpecs{$deviceType}->{unit};
        readingsSingleUpdate($rhash, $nameOfReading, $reading, 1);
      }
    }
  }
  return $rname;
}

sub 
EseraAnalogInOut_Parse($$) 
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
        
    if($type eq "EseraAnalogInOut") 
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
	  my $rname = EseraAnalogInOut_ParseForOneDevice($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value);
          push(@list, $rname);
        }
      }
    }
  }

  if ((scalar @list) > 0) 
  {
    return @list;
  }
  elsif (exists($EseraAnalogInOutSpecs{$deviceType}))
  {
    return "UNDEFINED EseraAnalogInOut_".$ioName."_".$oneWireId." EseraAnalogInOut ".$ioName." ".$oneWireId." ".$deviceType." - -";
  }
  
  return undef;
}

sub 
EseraAnalogInOut_Attr(@) 
{
  return undef;
}

1;

=pod
=item summary    Represents a 1-wire analog input/output.
=item summary_DE Repraesentiert einen 1-wire analogen Eingang/Ausgang.
=begin html

<a name="EseraAnalogInOut"></a>
<h3>EseraAnalogInOut</h3>

<ul>
  This module implements a 1-wire analog input/output. It uses 66_EseraOneWire <br>
  as I/O device.<br>
  <br>
  
  <a name="EseraAnalogInOut_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraAnalogInOut &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt; &lt;lowLimit&gt; &lt;highLimit&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the analog input/output chip.<br>
    Use the "get devices" query of EseraOneWire to get a list of 1-wire IDs, <br>
    or simply rely on autocreate.<br>
    Supported values for deviceType:
    <ul> 
      <li>SYS3 (analog output build into the Esera Controller 2, Note: This does not show up in the "get devices" response.)</li>
      <li>DS2450 (4x analog input)</li>
      <li>11202 (4x analog input)</li>
      <li>11203 (4x analog input)</li>
      <li>11208 (analog output, voltage)</li>
      <li>11219 (analog output, current)</li>
    </ul>
    This module knows the high and low limits of the supported devices. You might<br>
    want to further reduce the output range, e.g. to protect hardware connected to the <br>
    output from user errors. You can use the parameters &lt;lowLimit&gt; and &lt;highLimit&gt; to do<br>
    so. You can also give "-" for &lt;lowLimit&gt and &lt;highLimit&gt;. In this case the module uses<br>
    the maximum possible output range.<br>
  </ul>
  <br>
  
  <a name="EseraAnalogInOut_Set"></a>
  <b>Set</b>
  <ul>
    This applies to analog outputs only.
    <li>
      <b><code>set &lt;name&gt; out &lt;value&gt;</code><br></b>
      Controls the analog output. &lt;value&gt; specifies the new value.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; on</code><br></b>
      Switch output to "high" value. The on value has to be specified as attribute HighValue.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; off</code><br></b>
      Switch output to "low" value. The on value has to be specified as attribute LowValue.<br>
    </li>
  </ul>
  <br>

  <a name="EseraAnalogInOut_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraAnalogInOut_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>LowValue (see above)</li>
    <li>HighValue (see above)</li>
  </ul>
  <br>
      
  <a name="EseraAnalogInOut_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>in &ndash; analog input value</li>
    <li>out &ndash; analog output value</li>
  </ul>
  <br>

</ul>

=end html
=cut

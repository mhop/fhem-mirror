# $Id$
####################################################################################################
#
#	12_HProtocolGateway.pm
#
#	Copyright: Stephan Eisler
#	Email: fhem.dev@hausautomatisierung.co
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
####################################################################################################

package main;

use strict;
use warnings;
use DevIo;

my @tankList = undef;

my %sets = (
	        'readValues' => 1,
);

sub HProtocolGateway_Initialize($) {
  my ($hash) = @_;

  $hash->{Clients}  = "HProtocolTank";
  $hash->{DefFn}    = "HProtocolGateway_Define";
  $hash->{InitFn}   = "HProtocolGateway_Init";
  $hash->{GetFn}    = "HProtocolGateway_Get";
  $hash->{SetFn}    = "HProtocolGateway_Set";
  $hash->{AttrFn}   = "HProtocolGateway_Attr";
  $hash->{AttrList} = "device " .
                      "baudrate:300,600,1200,2400,4800,9600 " .
                      "parityBit:N,E,O " .
                      "databitsLength:5,6,7,8 " .
                      "stopBit:0,1" .
                      "pollIntervalMins " .
                      "path";
}

sub HProtocolGateway_Define($$) {
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  return "Wrong syntax: use define <name> HProtocolGateway </dev/tty???>" if(int(@a) != 3);

  $hash->{helper}{DeviceName} = $a[2];
  $hash->{Clients}  = "HProtocolTank";
  $hash->{STATE} = "Initialized";

  $attr{$name}{room} = "HProtocol";

  HProtocolGateway_DeviceConfig($hash);
  
  HProtocolGateway_Poll($hash) if defined(AttrVal($hash->{NAME}, 'pollIntervalMins', undef));  # if pollIntervalMins defind -> start timer

  return undef;
}

sub HProtocolGateway_Get($$@) {
	my ($hash, $name, $opt, @args) = @_;
	return "\"get $name\" needs at least one argument" unless(defined($opt));
	if ($opt eq "update") {
    		HProtocolGateway_GetUpdate($hash);
    		return "Done.";
	} else {
    # IMPORTANT! This defines the list of possible commands
    my $list = "update:noArg";
		return "Unknown argument $opt, choose one of $list";
	}
  return -1;
}

sub HProtocolGateway_Set($@) {                                      
    my ($hash, @a) = @_;
    my $name = $a[0];
    my $cmd =  $a[1];
    if(!defined($sets{$cmd})) {
	    return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)  . ":noArg"
	}
	if ($cmd eq 'readValues') {
	   RemoveInternalTimer($hash);
	   InternalTimer(gettimeofday() + 1, 'HProtocolGateway_GetUpdate', $hash, 0);
	}
	return undef
}

sub HProtocolGateway_GetUpdate($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  foreach (@tankList) {
    my $tankHash = $_;
    my $mode = AttrVal($tankHash->{NAME},"mode","");
    my $command = "\$A";
    if ($mode eq "Volume") {
      $command = "\$B";
    } elsif ($mode eq "Ullage") {
      $command = "\$C";
    }
    my $hID = AttrVal($tankHash->{NAME},"hID","");
    my $msg = $command . $hID . "\r\n";
    DevIo_SimpleWrite($hash, $msg , 2);
    my ($err, $data) = HProtocolGateway_ReadAnswer($hash,$tankHash);
    Log3 $name, 5, "err:". $err;
    Log3 $name, 5, "data:". $data;
  }
  
    my $pollInterval = AttrVal($hash->{NAME}, 'pollIntervalMins', 0);  #restore pollIntervalMins Timer
    InternalTimer(gettimeofday() + ($pollInterval * 60), 'HProtocolGateway_Poll', $hash, 0) if ($pollInterval > 0);
}

sub HProtocolGateway_ReadAnswer($$) {
    my ($hash,$tankHash) = @_;
    my $name = $hash->{NAME};
    return ("No FD (dummy device?)", undef)
	    if(!$hash || ($^O !~ /Win/ && !defined($hash->{FD})));
    
    for(;;) {
        return ("Device lost when reading answer", undef)
            if(!$hash->{FD});
        my $rin = '';
	    vec($rin, $hash->{FD}, 1) = 1;
	    my $nfound = select($rin, undef, undef, 3);
	    if($nfound <= 0) {
	      next if ($! == EAGAIN() || $! == EINTR());
	      my $err = ($! ? $! : "Timeout");
	      return("ProtocolGateway_ReadAnswer $err", undef);
	    }
	    my $buf = DevIo_SimpleRead($hash);
	    return ("No data", undef) if(!defined($buf));

	    my $ret = HProtocolGateway_Read($hash, $buf,$tankHash);
	    return (undef, $ret) if(defined($ret));
	  }
    
}

sub HProtocolGateway_Read($@) {

  my ($hash, $data, $tankHash) = @_;
  my $name = $hash->{NAME};
  my $buffer = $hash->{PARTIAL};
  
  Log3 $name, 5, "HProtocolGateway ($name) - received $data (buffer contains: $buffer)";
  
  $buffer .= $data;

  my $msg;
  # as long as the buffer contains CR (complete datagramm)
  while($buffer =~ m/\r/)
  {
    ($msg, $buffer) = split("\r", $buffer, 2);
    chomp $msg;
    HProtocolGateway_ParseMessage($hash, $msg, $tankHash);
  }

  $hash->{PARTIAL} = $buffer; 

  return $msg if(defined($data));
  return undef;
}

sub HProtocolGateway_ParseMessage($$) {
    my ($hash, $data, $tankHash) = @_;
    my $name = $hash->{NAME};
    
    $data =~ s/^.//; # remove # 
    
    my ($tankdata,$water,$temperature,$probe_offset,$version,$error,$checksum)=split(/@/,$data);
    my $test = "#".$tankdata.$water.$temperature.$probe_offset.$version.$error; 

    # calculate XOR CRC
    my $check = 0;
    $check ^= $_ for unpack 'C*', $test;
    # convert to HEX
    $check = sprintf '%02X', $check;
    
    # Unitronics Vision130
    if ($water == 0 && $temperature == 0 && $probe_offset == 0 && $version == 0 && $error == 0 && $checksum == 0 ) {
      $check = 0;
    }

    return if($check ne $checksum);

    my ($filllevel,$volume,$ullage) = (0,0,0); 
    my $mode = AttrVal($tankHash->{NAME},"mode","");

    if ($mode eq "FillLevel") {
      $filllevel = $tankdata;
      $volume = HProtocolGateway_Tank($hash,$tankHash,$filllevel);
    } elsif ($mode eq "Volume") {
      $volume = $tankdata;
    } elsif ($mode eq "Ullage") {
      $ullage = $tankdata;
    }

    my $sign = substr($temperature,0,1);
    $temperature  =~ s/^.//; 
    if ($sign eq "-") { $temperature = int($temperature) * -1 };
    $temperature = $temperature / 10;
    
    $sign = substr($probe_offset,0,1);
    $probe_offset  =~ s/^.//; 
    if ($sign eq "-") { $probe_offset = int($probe_offset) * -1 };
  
    my $volume_15C = $volume * (1 + 0.00084 * ( 15 - $temperature ));
    $volume_15C = int($volume_15C); 

    # Update all received readings
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "ullage", $ullage);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "filllevel", $filllevel);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "volume", $volume);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "volume_15C", $volume_15C);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "temperature", $temperature);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "waterlevel", $water);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "probe_offset", $probe_offset);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "version", $version);
    HProtocolGateway_UpdateTankDevice($hash, $tankHash->{NAME}, "error", $error);
}

sub HProtocolGateway_UpdateTankDevice($$$$) {
  my ($hash, $tankName, $reading, $value) = @_;

  my $message = $tankName . " " . $reading . " " . $value;

  my $success = Dispatch($hash, $message, undef);

  if (!$success) {
    my $name = $hash->{NAME};
    Log3 $name, 1, "$name: failed to update tank device";
  }
}

sub HProtocolGateway_RegisterTank($) {
  my ($tankHash) = @_;

  # Remove undefined elements of empty array
  @tankList = grep defined, @tankList;

  @tankList = (@tankList, $tankHash);
}

# called when definition is undefined 
# (config reload, shutdown or delete of definition)
sub HProtocolGateway_Undef($$)
{
  my ($hash, $name) = @_;
 
  # close the connection 
  DevIo_CloseDev($hash);
  
  return undef;
}

# called repeatedly if device disappeared
sub HProtocolGateway_Ready($)
{
  my ($hash) = @_;
  
  # try to reopen the connection in case the connection is lost
  return DevIo_OpenDev($hash, 1, "HProtocolGateway_Init"); 
}

# will be executed upon successful connection establishment (see DevIo_OpenDev())
sub HProtocolGateway_Init($)
{
    my ($hash) = @_;

    # send a status request to the device
    # DevIo_SimpleWrite($hash, "get_status\r\n", 2);
    
    return undef; 
}

# Called during attribute create/change
sub HProtocolGateway_Attr (@) {
    my ($command, $name, $attr, $val) =  @_;
    my $hash = $defs{$name};
    my $msg = '';

    if ($attr eq 'poll_interval') {
        if (defined($val)) {
            if ($val =~ m/^(0*[1-9][0-9]*)$/) {
                RemoveInternalTimer($hash);
                HProtocolGateway_Poll($hash) if ($main::init_done);
	        } else {
	            $msg = 'Wrong poll intervall defined. pollIntervalMins must be a number > 0';
	        }
	    } else {
	       RemoveInternalTimer($hash);
        }
    } elsif ($attr eq 'path') {
      $attr{$name}{path} = $val; 
    } elsif ($attr eq 'baudrate') {
      $attr{$name}{baudrate} = $val;
      HProtocolGateway_DeviceConfig($hash);
    } elsif ($attr eq 'databitsLength') {
      $attr{$name}{databitsLength} = $val;
      HProtocolGateway_DeviceConfig($hash);
    } elsif ($attr eq 'parityBit') {
      $attr{$name}{parityBit} = $val;
      HProtocolGateway_DeviceConfig($hash);
    } elsif ($attr eq 'stopBit') {
      $attr{$name}{stopBit} = $val;
      HProtocolGateway_DeviceConfig($hash);
    }
    
}

sub HProtocolGateway_DeviceConfig($) {
  my ($hash) =  @_;
  my $name = $hash->{NAME};
  my $deviceName = $hash->{helper}{DeviceName};
  $hash->{DeviceName} = $deviceName."@".$attr{$name}{baudrate}.",".$attr{$name}{databitsLength}.",".$attr{$name}{parityBit}.",".$attr{$name}{stopBit};
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));
  my $ret = DevIo_OpenDev($hash, 0, "HProtocolGateway_Init");
  return $ret
}

# Request measurements regularly
sub HProtocolGateway_Poll($) {
    my ($hash) =  @_;
    my $name = $hash->{NAME};
    
    HProtocolGateway_Set($hash, ($name, 'readValues'));
    
    my $pollInterval = AttrVal($hash->{NAME}, 'pollIntervalMins', 0);
    if ($pollInterval > 0) {
        InternalTimer(gettimeofday() + ($pollInterval * 60), 'HProtocolGateway_Poll', $hash, 0);
    }
}

sub HProtocolGateway_Tank($$$) {
  my ($hash,$tankHash,$filllevel) = @_;
  my $name = $hash->{NAME};
  my $path = AttrVal($name,"path","");
  my $type = AttrVal($tankHash->{NAME},"type","");

  my %TankChartHash;
  open my $fh, '<', $path.$type or die "Cannot open: $!";
  while (my $line = <$fh>) {
    $line =~ s/\s*\z//;
    my @array = split /,/, $line;
    my $key = shift @array;
    $TankChartHash{$key} = $array[0];
  }
  close $fh;

  my $messwert = $filllevel/100;
  my $volume = 0;

  foreach my $level (sort keys %TankChartHash) {
    if ($level ne "level" && $messwert <= $level) {
	    $volume = $TankChartHash{$level};
      last;
    }
  }
  return $volume;
}

1;


=pod
=item summary    support for the HLS 6010 Probes
=begin html

<a name="HProtocolGateway"></a>
<h3>HProtocolGateway</h3>
<ul>
    The HProtocolGateway is a fhem module for the RS232 standard interface for HLS 6010 Probes connected to a Hectronic OPTILEVEL Supply.

  <br /><br /><br />

  <a name="HProtocolGateway"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; HProtocolGateway /dev/tty???<br />
    attr &lt;name&gt; pollIntervalMins 2<br />
    attr &lt;name&gt; path /opt/fhem/<br />
    attr &lt;name&gt; baudrate 1200<br />
    attr &lt;name&gt; databitsLength 8<br />
    attr &lt;name&gt; parityBit N<br />
    attr &lt;name&gt; stopBit 1</code>
    <br />
    <br />
    Defines an HProtocolGateway connected to RS232 serial standard interface.<br /><br /> 
    path is the path for tank&lt;01&gt;.csv strapping table files.<br /><br /> 

    <code>
    level,volume<br />
    10,16<br />
    520,7781<br />
    1330,29105<br />
    1830,43403<br />
    2070,49844<br />
    2220,53580<br />
    2370,57009<br />
    2400,57650<br />
    2430,58275<br />
    2370,57009<br />
    2400,57650<br />
    2430,58275<br />
    </code> 

  
    <br /><br /> 

  <a name="HProtocolGateway"></a>
  <b>Attributes</b>
  <ul>
    <li>pollIntervalMins<br />
    poll Interval in Mins</li>
    <li>path<br />
    Strapping Table csv file path</li>
    <li>baudrate<br />
    Baudrate / 300, 600, 1200, 2400, 4800, 9600</li>
    <li>databitsLength<br />
    Databits Length / 5, 6, 7, 8</li>
    <li>parityBit<br />
    Parity Bit / N, E, O</li>
    <li>stopBit<br />
    Stop Bit / 0, 1</li>
  </ul><br />

  </ul><br />

</ul><br />

=end html

=cut

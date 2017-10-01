# $Id$

package main;

use strict;
use warnings;
use SetExtensions;

#=======================================================================================
sub EleroDrive_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}         = ".*";
  $hash->{DefFn}         = "EleroDrive_Define";
  $hash->{UndefFn}       = "EleroDrive_Undef";
  $hash->{FingerprintFn} = "EleroDrive_Fingerprint";
  $hash->{ParseFn}       = "EleroDrive_Parse";
  $hash->{SetFn}         = "EleroDrive_Set";
  $hash->{GetFn}         = "EleroDrive_Get";
  $hash->{AttrFn}        = "EleroDrive_Attr";
  $hash->{AttrList}      = "IODev " .
                           "TopToBottomTime " .
                           "TiltPercent " .
                           "IntermediatePercent " .
                           "$readingFnAttributes ";
                           
  $hash->{noAutocreatedFilelog} = 1;
}


#=======================================================================================
sub EleroDrive_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  
  return "Usage: define <name> EleroDrive <Channel>" if(@a < 3);

  my $devName   = $a[0];
  my $type      = $a[1];
  my $channel   = $a[2];
  
  $hash->{STATE}    = 'Initialized';
  $hash->{NAME}     = $devName;
  $hash->{TYPE}     = $type;
  $hash->{channel}  = $channel;
  
  $modules{EleroDrive}{defptr}{$channel} = $hash;
  
  my $ioDev = undef;
  my @parts = split("_", $devName);
  if(@parts == 3) {
    $ioDev = $parts[1];
  }
  if($ioDev) {
    AssignIoPort($hash, $ioDev);
  }
  else {
    AssignIoPort($hash);
  }
  
  
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $devName, 4, "$devName: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else {
    Log3 $devName, 1, "$devName: no I/O device";
  }
    
  return undef;
}


#=======================================================================================
sub EleroDrive_Undef($$) {
  my ($hash, $arg) = @_;  
  my $channel = $hash->{channel};
  
  RemoveInternalTimer($hash); 
  delete( $modules{EleroDrive}{defptr}{$channel} );
  
  return undef;
}


#=======================================================================================
sub EleroDrive_Get($@) {
  return undef;
}

#=======================================================================================
sub EleroDrive_ToFixPosition($$) {
  my ( $hash, $position) = @_;
  
  my $channel = $hash->{channel};
  
  my $head = 'aa';
  my $msgLength = '05';
  my $msgCmd = '4c';
  my $firstBits = '';
  my $firstChannels = '';
  my $secondBits = '';
  my $secondChannels = '';
  my $checksum = '';
  my $payload = '';
  
  if($position eq 'bottom'){
    $payload = '40';
  }
  elsif($position eq 'top'){
    $payload = '20';
  }
  elsif($position eq 'stop'){
    $payload = '10';
  }
  elsif($position eq 'intermediate'){
    $payload = '44';
  }
  elsif($position eq 'tilt'){
    $payload = '24';
  }
  
  if($payload) {
    if($channel <= 8){
      $firstChannels = '00';
      $secondChannels = 2**($channel-1);
      $secondChannels = sprintf('%02x', $secondChannels);
    }
    else {
      $secondChannels = '00';
      $firstChannels = 2**($channel-1-8);
      $firstChannels = sprintf('%02x', $firstChannels);
    }
        
    my $checksumNumber = hex($head) + hex($msgLength) + hex($msgCmd) + hex($firstChannels) + hex($secondChannels) + hex($payload);
    my $byteUpperBound = 256;
    my $upperBound = $byteUpperBound;
    while($checksumNumber > $upperBound){
     $upperBound = $upperBound + $byteUpperBound;
    }
    $checksumNumber =  $upperBound - $checksumNumber;
    $checksum = sprintf('%02x', $checksumNumber);
    
    my $byteMsg = $head.$msgLength.$msgCmd.$firstChannels.$secondChannels.$payload.$checksum;
    
    IOWrite($hash, "send", $byteMsg);
  }
 
}


#=======================================================================================
sub EleroDrive_ToAnyPosition($$) {
  my ( $hash, $position) = @_;
  my $name = $hash->{NAME};
}

#=======================================================================================
sub EleroDrive_Set($@) {
  my ( $hash, $name, $cmd, @params ) = @_;
    
  my $channel = $hash->{channel};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands=("stop:noArg moveDown:noArg moveUp:noArg moveIntermediate:noArg moveTilt:noArg refresh:noArg");
  return $commands if( $cmd eq '?' || $cmd eq '');

  my $doRefresh = '0';
  
  if($cmd eq 'refresh'){
    IOWrite($hash, "refresh", $channel);
  }
  elsif($cmd eq 'moveDown'){
    EleroDrive_ToFixPosition($hash, "bottom");
    $doRefresh = '1';
  }
  elsif($cmd eq 'moveUp'){
    EleroDrive_ToFixPosition($hash, "top");
    $doRefresh = '1';
  }
  elsif($cmd eq 'stop'){
    EleroDrive_ToFixPosition($hash, "stop");
  }
  elsif($cmd eq 'moveIntermediate'){
    EleroDrive_ToFixPosition($hash, "intermediate");
    $doRefresh = '1';
  }
  elsif($cmd eq 'moveTilt'){
    EleroDrive_ToFixPosition($hash, "tilt");
    $doRefresh = '1';
  }
  elsif($cmd eq 'moveTo' && scalar @params eq 1){
    EleroDrive_ToAnyPosition($hash, $params[0]);
    
    $doRefresh = '1';
  }
  else {
    return "Unknown argument $cmd, choose one of $commands";
  }

  # Start a one time timer that refreshes the position for this drive
  my $refreshDelay = AttrVal($name, "TopToBottomTime", 0);
  if($doRefresh && $refreshDelay) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + $refreshDelay + 2, "EleroDrive_OnRefreshTimer", $hash, 0);
  }

  return undef;
}


#=======================================================================================
sub EleroDrive_Fingerprint($$) {
  my ($name, $msg) = @_;
  return ("", $msg);
}


#=======================================================================================
sub EleroDrive_Parse($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  my $buffer = $msg;
  
  # aa054d00010102 : channel 1 top
  # aa054d00010202 : channel 1 bottom
  # aa054d00020102 : channel 2 top
  # aa054d00020202 : channel 2 bottom
  # aa 05 4d 00 01 01 02
  # ----- -- -- -- -- -- 
  # |     |  |  |  |  |
  # |     |  |  |  |  Checksum
  # |     |  |  |  State (top, bottom, ...)
  # |     |  |  Lower channel bits (1 - 8)
  # |     |  Upper channel bits (9 - 15)
  # |     4d = Easy_Ack (answer on Easy_Send or Easy_Info)
  # Fix aa 05
  # State: 0x01 = top
  #        0x02 = bottom
  #        0x03 = intermediate
  #        0x04 = tilt
  
  # get the channel
  my $firstChannels  = substr($buffer,6,2);
  my $secondChannels = substr($buffer,8,2);
            
  my $bytes =  $firstChannels.$secondChannels ;
  $bytes = hex ($bytes);

  my $channel = 1;
  while ($bytes != 1 and $channel <= 15) {
    $bytes = $bytes >> 1;
    $channel++;
  }
  
  if($channel <= 15) {
    # Check if it is defined as a switch device
    my $switchChannels = AttrVal($name, "SwitchChannels", undef);
    if(defined $switchChannels) {
      my @channelList = split /,/, $switchChannels;
      if ($channel ~~ @channelList) {
        return undef;
      }
    }
  
    my $rhash = undef;
  
    foreach my $d (keys %defs) {
      my $h = $defs{$d};
      my $type = $h->{TYPE};
      if($type eq "EleroDrive") {
        if (defined($h->{IODev}->{NAME})) {
          my $ioDev = $h->{IODev}->{NAME};
          my $def = $h->{DEF};
          if ($ioDev eq $name && $def eq $channel) {
            $rhash = $h;
            last;
          }
        }
      }
    }
    
    if($rhash) {
      my $rname = $rhash->{NAME};
    
      # get status
      my $statusByte = substr($buffer,10,2);
               
      my %deviceStati = ('00' => "no_information",
                         '01' => "top_position",
                         '02' => "bottom_position",
                         '03' => "intermediate_position",
                         '04' => "tilt_position",
                         '05' => "blocking",
                         '06' => "overheated",
                         '07' => "timeout",
                         '08' => "move_up_started",
                         '09' => "move_down_started",
                         '0a' => "moving_up",
                         '0b' => "moving_down",
                         '0d' => "stopped_in_undefined_position",
                         '0e' => "top_tilt_stop",
                         '0f' => "bottom_intermediate_stop",
                         '10' => "switching_device_switched_off",
                         '11' => "switching_device_switched_on"                 
                        );
                        
      my %percentDefinitions = ('00' => 50,
                         '01' => 0,
                         '02' => 100,
                         '03' => AttrVal($rname, "IntermediatePercent", 50),
                         '04' => AttrVal($rname, "TiltPercent", 50),
                         '05' => -1,
                         '06' => -1,
                         '07' => -1,
                         '08' => -1,
                         '09' => -1,
                         '0a' => -1,
                         '0b' => -1,
                         '0d' => 50,
                         '0e' => 0,
                         '0f' => 100,
                         '10' => -1,
                         '11' => -1                 
                        );                      
                           
      my $newstate = $deviceStati{$statusByte};
      my $percentClosed = $percentDefinitions{$statusByte};
    
      readingsBeginUpdate($rhash);
      readingsBulkUpdate($rhash, "state", $newstate);
      readingsBulkUpdate($rhash, "position", $newstate);
      if($percentClosed ne -1) {
        readingsBulkUpdate($rhash, "percentClosed", $percentClosed);
      }
      readingsEndUpdate($rhash,1);
           
      my @list;
      push(@list, $rname);
      return @list;
    }
    else {
      return "UNDEFINED EleroDrive_" . $name . "_" . $channel . " EleroDrive " . $channel;
    }
  }
}


#=======================================================================================
sub EleroDrive_Attr(@) {

}

#=======================================================================================
sub EleroDrive_OnRefreshTimer($$) {
  my ($hash, @params) = @_;
  my $name  = $hash->{NAME};
  my $channel = $hash->{channel};
  
  IOWrite($hash, "refresh", $channel);
          
  return undef;
}



1;

=pod
=item summary    Represents on elero drive
=item summary_DE Repräsentiert ein elero drive
=begin html

<a name="EleroDrive"></a>
<h3>EleroDrive</h3>

<ul>
  This mudule implements an Elero drive. It uses EleroStick as IO-Device.
  <br><br>
  
  <a name="EleroDrive_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EleroDrive &lt;channel&gt;</code> <br>
    &lt;channel&gt; specifies the channel of the transmitter stick that shall be used.
    <br><br>
  </ul>
  
  <a name="EleroDrive_Set"></a>
  <b>Set</b>
  <ul>
    <li>moveDown<br>
    </li>
    <li>moveUp<br>
    </li>
    <li>stop<br>
    </li>
    <li>moveIntermediate<br>
    </li>
    <li>moveTilt<br>
    </li>
    <li>refresh<br>
    </li>
 </ul>
 <br>

  <a name="EleroDrive_Get"></a>
  <b>Get</b>
  <ul>
    <li>no gets<br>
    </li><br>   
  </ul>

  <a name="EleroDrive_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>IODev<br>
    The name of the IO-Device, normally the name of the EleroStick definition</li>
    
    <li>TopToBottomTime<br>
    The time in seconds this drive needs for a complete run from the top to the bottom or vice versa</li>
    
    <li>IntermediatePercent<br>
    Percent open when in intermediate position</li>
    
    <li>TiltPercent<br>
    Percent open when in tilt position</li>
    
  </ul><br>
  
  <a name="EleroDrive_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>position<br>
    Current position of the drive (top_position, bottom_position, ...)</li>
    
    <li>percentClosed<br>
    0 ... 100<br>
    100 is completely closed, 0 is completely open</li>
  </ul><br>

</ul>

=end html
=cut

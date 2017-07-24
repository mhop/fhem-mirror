# $Id$

package main;

use strict;
use warnings;
use SetExtensions;

#=======================================================================================
sub EleroSwitch_Initialize($) {
  my ($hash) = @_;

  $hash->{Match}         = ".*";
  $hash->{DefFn}         = "EleroSwitch_Define";
  $hash->{UndefFn}       = "EleroSwitch_Undef";
  $hash->{FingerprintFn} = "EleroSwitch_Fingerprint";
  $hash->{ParseFn}       = "EleroSwitch_Parse";
  $hash->{SetFn}         = "EleroSwitch_Set";
  $hash->{GetFn}         = "EleroSwitch_Get";
  $hash->{AttrFn}        = "EleroSwitch_Attr";
  $hash->{AttrList}      = "IODev " .
                           "$readingFnAttributes ";
                           
  $hash->{noAutocreatedFilelog} = 1; 
}


#=======================================================================================
sub EleroSwitch_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
  
  return "Usage: define <name> EleroSwitch <Channel>" if(@a < 3);

  my $devName   = $a[0];
  my $type      = $a[1];
  my $channel   = $a[2];

  $hash->{STATE}    = 'Initialized';
  $hash->{NAME}     = $devName;
  $hash->{TYPE}     = $type;
  $hash->{channel}  = $channel;
  
  $modules{EleroSwitch}{defptr}{$channel} = $hash;
  
  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $devName, 4, "$devName: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else {
    Log3 $devName, 1, "$devName: no I/O device";
  }
    
  return undef;
}


#=======================================================================================
sub EleroSwitch_Undef($$) {
  my ($hash, $arg) = @_;  
  my $channel = $hash->{channel};
  
  RemoveInternalTimer($hash); 
  delete( $modules{EleroSwitch}{defptr}{$channel} );
  
  return undef;
}


#=======================================================================================
sub EleroSwitch_Get($@) {
  return undef;
}

#=======================================================================================
sub EleroSwitch_Send($$) {
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
  
  if($position eq 'off'){
    # stop / off
    $payload = '10';
  }
  elsif($position eq 'on'){
    # top / on
    $payload = '20';
  }
  elsif($position eq 'dim1'){
    # intermediate / dim1
    $payload = '44';
  }
  elsif($position eq 'dim2'){
    # tilt / dim2
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
sub EleroSwitch_Set($@) {
  my ( $hash, $name, $cmd, @params ) = @_;
    
  my $channel = $hash->{channel};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands=("on:noArg off:noArg dim1:noArg dim2:noArg refresh:noArg");
  return $commands if( $cmd eq '?' || $cmd eq '');

  my $doRefresh = '0';
  
  if($cmd eq 'refresh'){
    IOWrite($hash, "refresh", $channel);
  }
  elsif($cmd eq 'on'){
    EleroSwitch_Send($hash, "on");
    $doRefresh = '1';
  }
  elsif($cmd eq 'off'){
    EleroSwitch_Send($hash, "off");
    $doRefresh = '1';
  }
  elsif($cmd eq 'dim1'){
    EleroSwitch_Send($hash, "dim1");
  }
  elsif($cmd eq 'dim2'){
    EleroSwitch_Send($hash, "dim2");
    $doRefresh = '1';
  }
  else {
    return "Unknown argument $cmd, choose one of $commands";
  }

  # Start a one time timer that refreshes this switch
  if($doRefresh) {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + 2, "EleroSwitch_OnRefreshTimer", $hash, 0);
  }

  return undef;
}


#=======================================================================================
sub EleroSwitch_Fingerprint($$) {
  my ($name, $msg) = @_;
  return ("", $msg);
}


#=======================================================================================
sub EleroSwitch_Parse($$) {
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  my $buffer = $msg;
  
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
      if (!$channel ~~ @channelList) {
        return undef;
      }
    }
    else {
      return undef;
    }
    
    
    # get status
    my $statusByte = substr($buffer,10,2);
             
    my %deviceStati = ('00' => "no_information",
                       '01' => "off",
                       '02' => "on",
                       '03' => "dim1",
                       '04' => "dim2",
                       '05' => "unknown",
                       '06' => "overheated",
                       '07' => "timeout",
                       '08' => "unknown",
                       '09' => "unknown",
                       '0a' => "unknown",
                       '0b' => "unknown",
                       '0d' => "unknown",
                       '0e' => "unknown",
                       '0f' => "unknown",
                       '10' => "off",
                       '11' => "on"                 
                      );
                         
    my $newstate = $deviceStati{$statusByte};
         
    my $rhash = $modules{EleroSwitch}{defptr}{$channel};
    my $rname = $rhash->{NAME};
      
    if($modules{EleroSwitch}{defptr}{$channel}) {
      readingsBeginUpdate($rhash);
      readingsBulkUpdate($rhash, "state", $newstate);
      readingsEndUpdate($rhash,1);
           
      my @list;
      push(@list, $rname);
      return @list;
    }
    else {
      return "UNDEFINED EleroSwitch_$channel EleroSwitch $channel";
    }
  }
}


#=======================================================================================
sub EleroSwitch_Attr(@) {

}

#=======================================================================================
sub EleroSwitch_OnRefreshTimer($$) {
  my ($hash, @params) = @_;
  my $name  = $hash->{NAME};
  my $channel = $hash->{channel};
  
  IOWrite($hash, "refresh", $channel);
          
  return undef;
}



1;

=pod
=item summary    Represents an Elero switch
=item summary_DE Repräsentiert einen Elero switch
=begin html

<a name="EleroSwitch"></a>
<h3>EleroSwitch</h3>

<ul>
  This mudule implements an Elero switch. It uses EleroStick as IO-Device.
  <br><br>
  
  <a name="EleroSwitch_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EleroSwitch &lt;channel&gt;</code> <br>
    &lt;channel&gt; specifies the channel of the transmitter stick that shall be used.
    <br><br>
  </ul>
  
  <a name="EleroSwitch_Set"></a>
  <b>Set</b>
  <ul>
    <li>on<br>
    </li>
    <li>off<br>
    </li>
    <li>dim1<br>
    </li>
    <li>dim2<br>
    </li>
    <li>refresh<br>
    </li>
 </ul>
 <br>

  <a name="EleroSwitch_Get"></a>
  <b>Get</b>
  <ul>
    <li>no gets<br>
    </li><br>   
  </ul>

  <a name="EleroSwitch_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>IODev<br>
    The name of the IO-Device, normally the name of the EleroStick definition</li>
  </ul><br>
  
  <a name="EleroSwitch_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>state<br>
    Current state of the switch (on, off, dim1, dim2)</li>
  </ul><br>

</ul>

=end html
=cut

# $Id$

# ToDo-List
# ---------
# [ ] Disable the timer when a Drive asks for information to avoid conflicts
#     After getting a message in EleroStick_Write we must interupt the timer 
#     for "ChannelTimeout" seconds
#
# [ ] Perhaps we need a cache for incoming commands that delays the incoming commands
#     for "ChannelTimeout" seconds to give the previous command a chance to hear its acknowledge
#     
#
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

my $clients   = ":EleroDrive";
my %matchList = ("1:EleroDrive" => ".*",);

# Answer Types
my $easy_confirm = "aa044b";
my $easy_ack     = "aa054d";

#=======================================================================================
sub EleroStick_Initialize($) {
  my ($hash) = @_;

  require "$attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{ReadFn}         = "EleroStick_Read";
  $hash->{WriteFn}        = "EleroStick_Write";
  $hash->{ReadyFn}        = "EleroStick_Ready";
  $hash->{DefFn}          = "EleroStick_Define";
  $hash->{UndefFn}        = "EleroStick_Undef";
  $hash->{GetFn}          = "EleroStick_Get";
  $hash->{SetFn}          = "EleroStick_Set";
  $hash->{AttrFn}         = "EleroStick_Attr";
  $hash->{FingerprintFn}  = "EleroStick_Fingerprint";
  $hash->{ShutdownFn}     = "EleroStick_Shutdown";
  $hash->{AttrList}       = "Clients " .
                            "MatchList " .
                            "ChannelTimeout " .
                            "Interval " .
                            "$readingFnAttributes ";
                                                     
}


#=======================================================================================
sub EleroStick_Fingerprint($$) {
}

#=======================================================================================
sub EleroStick_SimpleWrite($$) {
  my ($hash, $data) = @_;

  DevIo_SimpleWrite($hash, $data, 1);
  
  if(index($data, "aa054c", 0) == 0) {
    readingsSingleUpdate($hash, 'SendType', "easy_send", 1); 
  }
  elsif(index($data, "aa044e", 0) == 0) {
    readingsSingleUpdate($hash, 'SendType', "easy_info", 1);
  }
  elsif(index($data, "aa024a", 0) == 0) {
    readingsSingleUpdate($hash, 'SendType', "easy_check", 1);
  }
  
  readingsSingleUpdate($hash, 'SendMsg', $data, 1); 
}


#=======================================================================================
sub EleroStick_Define($$) {
  my ( $hash, $def ) = @_;
  my @a = split( "[ \t][ \t]*", $def );
   
  my $name = $a[0];
  my $type = $a[1];
  my $dev  = $a[2];
  
  $hash->{USBDev}     	= $dev;
  $hash->{DeviceName}   = $dev;
  $hash->{NAME}         = $name;
  $hash->{TYPE}         = $type;
  $hash->{Clients}      = $clients;
  $hash->{MatchList}    = \%matchList;
  
  DevIo_OpenDev($hash, 0, undef);
  
  EleroStick_SendEasyCheck($hash);  
    
  InternalTimer(gettimeofday()+2, "EleroStick_OnTimer", $hash, 0);  
    
  return undef;
}

#=======================================================================================
sub EleroStick_Undef($$) {
  my ( $hash, $arg ) = @_;       
  DevIo_CloseDev($hash);         
  RemoveInternalTimer($hash);    
  return undef;    
}

#=======================================================================================
sub EleroStick_Shutdown($) {
  my ($hash) = @_;
  $hash->{channels} = "";
  return undef;
}

#=======================================================================================
sub EleroStick_SendEasyCheck($) {
  my ($hash) = @_;
  my $name  = $hash->{NAME};

  if($hash->{STATE} ne "disconnected") {
    my $head = 'aa';
    my $msgLength = '02';
    my $msgCmd = '4a';

    my $checksumNumber = hex($head) + hex($msgLength) + hex($msgCmd);
    my $byteUpperBound = 256; 
    my $upperBound = $byteUpperBound;
    while($checksumNumber > $upperBound){
      $upperBound = $upperBound + $byteUpperBound;
    }
    $checksumNumber =  $upperBound - $checksumNumber;

    my $checksum = sprintf('%02x', $checksumNumber);

    my $byteMsg = $head.$msgLength.$msgCmd.$checksum;

    EleroStick_SimpleWrite($hash, $byteMsg);
   
  }
}

#=======================================================================================
sub EleroStick_SendEasyInfo($$) {
  my ($hash, $channel) = @_;
  my $name  = $hash->{NAME};
  
  if($hash->{STATE} ne "disconnected") {
    my $head = 'aa';
    my $msgLength = '04';
    my $msgCmd = '4e';
    my $firstBits = '';
    my $secondBits = '';
    my $firstChannels = '';
    my $secondChannels = '';

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
    
    my $checksumNumber = hex($head) + hex($msgLength) + hex($msgCmd) + hex($firstChannels) + hex($secondChannels);
    my $byteUpperBound = 256;
    my $upperBound = $byteUpperBound;
    while($checksumNumber > $upperBound){
      $upperBound = $upperBound + $byteUpperBound;
    }
    $checksumNumber =  $upperBound - $checksumNumber;   
    my $checksum = sprintf('%02x', $checksumNumber);
     
    my $byteMsg = $head.$msgLength.$msgCmd.$firstChannels.$secondChannels.$checksum;
        
    EleroStick_SimpleWrite($hash, $byteMsg);
  }
  
}


#=======================================================================================
sub EleroStick_OnTimer($$) {
  my ($hash, @params) = @_;
  my $name  = $hash->{NAME};
  
  my $timerInterval = AttrVal($name, "ChannelTimeout", 5);
  
  if($hash->{STATE} ne "disconnected") {
    if($hash->{channels}) {
      my $channels = $hash->{channels};
      
      if(index($channels, "x") eq -1) {
        # We were at the end of the learned channels or lost our position 
        my $flc = index($channels, "1");
        if($flc ne -1) {
          substr($channels, $flc, 1, "x");
        }
      }
      
      my $now = index($channels, "x");
      if($now ne -1) {
        substr($channels, $now, 1, "1");
        ###debugLog($name, "now " . ($now +1));
        EleroStick_SendEasyInfo($hash, $now +1);

        for(my $i = $now +1; $i<15; $i++) {
          if(substr($channels, $i, 1) eq "1") {
            substr($channels,$i,1,"x");
            last;
          }
        }
        $hash->{channels} = $channels;
      }
      
      # All Channels completed, wait interval seconds
      if (index($channels, "x") eq -1) {
        $timerInterval = AttrVal($name, "Interval", 60);
      }

    }

  }

  InternalTimer(gettimeofday()+$timerInterval, "EleroStick_OnTimer", $hash, 0);  
          
  return undef;
}


#=======================================================================================
sub EleroStick_Set($@) {
  return undef;
}


#=======================================================================================
sub EleroStick_Get($@) {
  return undef;
}


#=======================================================================================
sub EleroStick_Write($$) {
  my ($hash, $cmd, $msg) = @_;
  my $name = $hash->{NAME};
  
  # Send to the transmitter stick
  if($cmd eq 'send'){
    ###debugLog($name, "EleroStick cmd=send msg=$msg");
    EleroStick_SimpleWrite($hash, $msg);
  }
  
  # Request status for a channel
  elsif ($cmd eq 'refresh') {
    ###debugLog($name, "EleroStick cmd=refresh msg=$msg");
    EleroStick_SendEasyInfo($hash, $msg);
  }
  
}


#=======================================================================================
sub EleroStick_Read($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # read from serial device
  my $buf = DevIo_SimpleRead($hash);		
  return "" if ( !defined($buf) );

  # convert to hex string to make parsing with regex easier
  my $answer = unpack ('H*', $buf);
    
  if(index($answer, 'aa', 0) == 0){
    # New Byte String
    $hash->{buffer} = $answer;
  }
  else{
    # Append to Byte String
    $hash->{buffer} .= $answer;
  }
   
  #todo:  hier gibts manchmal Fehlermeldung $strLen nicht definiert 	
  my $strLen = substr($hash->{buffer},3-1,2);
  $strLen = hex($strLen);
  my $calLen = ($strLen * 2) + 4;

  if($calLen == length($hash->{buffer})){
    # Die Länge der Nachricht entspricht der Vorgabe im Header

    readingsSingleUpdate($hash,'AnswerMsg', $hash->{buffer},1);
    
    if(index($hash->{buffer}, $easy_confirm, 0) == 0) {
      $hash->{lastAnswerType} = "easy_confirm";
      
      my $cc = substr($hash->{buffer},6,4);
      my $firstChannels  = substr($cc,0,2);
      my $secondChannels = substr($cc,2,2);
      my $bytes =  $firstChannels.$secondChannels ;
      $bytes = hex ($bytes);
      my $dummy="";
      my $learndChannelFound = 0;
      for (my $i=0; $i < 15; $i++) {
        if($bytes & 1 << $i) {
          if(!$learndChannelFound) {
            $dummy = $dummy . "x"; 
            $learndChannelFound = 1; 
          }
          else {
            $dummy = $dummy . "1";
          }
        }
        else {
          $dummy = $dummy . "0";
        }
      }       
       
      $hash->{channels} = $dummy;
    }
    elsif(index($hash->{buffer}, $easy_ack, 0) == 0) {
      $hash->{lastAnswerType} = "easy_ack";
      my $buffer = $hash->{buffer};
      Dispatch($hash, $buffer, "");
    }
    
    readingsSingleUpdate($hash, 'AnswerType', $hash->{lastAnswerType}, 1);
    Log3 $name, 4, "Current buffer content: " . $hash->{buffer}." Name ". $hash->{NAME};
  }
  else {
    # Wait for the rest of the data
    Log3 $name, 5, "Current buffer is not long enough ";
  } 
}


#=======================================================================================
sub EleroStick_Ready($) {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $openResult = DevIo_OpenDev($hash, 1, undef);
  
  if($hash->{STATE} eq "disconnected") {
    $hash->{channels} = "";
  }
  else {
    EleroStick_SendEasyCheck($hash);
    ###debugLog($name, "EleroStick_Ready -> SendEasyInfo");
  }
  
  return $openResult if($hash->{STATE} eq "disconnected");

  # This is relevant for windows/USB only
  my $po = $hash->{USBDev};
  my ( $BlockingFlags, $InBytes, $OutBytes, $ErrorFlags ) = $po->status;

  return ( $InBytes > 0 );
}


#=======================================================================================
sub EleroStick_Attr(@) {
  my ($cmd, $name, $aName, $aVal) = @_;
  my $hash = $defs{$name};
  
  if($aName eq "Clients") {
    $hash->{Clients} = $aVal;
    $hash->{Clients} = $clients if( !$hash->{Clients});  
  }
  
  elsif($aName eq "MatchList") {
    my $match_list;
    if($cmd eq "set") {
      $match_list = eval $aVal;
      if( $@ ) {
        Log3 $name, 2, $name .": $aVal: ". $@;
      }
    }

    if(ref($match_list) eq 'HASH') {
      $hash->{MatchList} = $match_list;
    } 
    else {
      $hash->{MatchList} = \%matchList;
    }
  
  }
  
  return undef;
}





#=======================================================================================
1;

=pod
=begin html

<a name="EleroStick"></a>
<h3>EleroStick</h3>
<ul>
  This module provides the IODevice for EleroDrive and other future modules that implement Elero components<br>
  It handles the communication with an "Elero Transmitter Stick"

  <br><br>

  <a name="EleroStick_Define"></a>
  <b>Define</b>
  <ul>
    <li>
    <code>define &lt;name&gt; EleroStick &lt;port&gt;</code> <br>
    &lt;port&gt; specifies the serial port where the transmitter stick is attached.<br>
    The name of the serial-device depends on your OS. Example: /dev/ttyUSB1@38400<br>
    The baud rate must be 38400 baud.<br><br>
  </li>
  </ul>
  
  <a name="EleroStick_Set"></a>
  <b>Set</b>
  <ul>
    <li>no sets<br>
    </li><br>
 </ul>

  <a name="EleroStick_Get"></a>
  <b>Get</b>
  <ul>
    <li>no gets<br>
    </li><br>
 </ul>

  <a name="EleroStick_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>Clients<br>
      The received data gets distributed to a client (e.g. EleroDrive, ...) that handles the data.
      This attribute tells, which are the clients, that handle the data. If you add a new module to FHEM, that shall handle
      data distributed by the EleroStick module, you must add it to the Clients attribute.
    </li>

    <br>
    <li>MatchList<br>
      The MatchList defines, which data shall be distributed to which device.<br>
      It can be set to a perl expression that returns a hash that is used as the MatchList<br>
      Example: <code>attr myElero MatchList {'1:EleroDrive' => '.*'}</code>
    </li>

    <br>
    <li>ChannelTimeout<br>
      The delay, how long the modul waits for an answer after sending a command to a drive.<br>
      Default is 5 seconds.
    </li>

    <br>
    <li>Interval<br>
      When all channels are checkt, this number of seconds will be waited, until the channels will be checked again.<br>
      Default is 60 seconds.
    </li><br>
  </ul>
  
  <a name="EleroStick_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>state<br>
    disconnected or opened if a transmitter stick is connected</li>
    <li>SendType<br>
    Type of the last command sent to the stick</li>
    <li>SendMsg<br>
    Last command sent to the stick</li>
    <li>AnswerType<br>
    Type of the last Answer received from the stick</li>
    <li>AnswerMsg<br>
    Last Answer received from the stick</li>
  </ul><br>
</ul>

=end html
=cut

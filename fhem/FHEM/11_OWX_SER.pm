########################################################################################
#
# OWX_SER.pm
#
# FHEM module providing hardware dependent functions for the serial (USB) interface of OWX
#
# Prof. Dr. Peter A. Henning
#
# $Id$
#
########################################################################################
#
# Provides the following methods for OWX
#
# Define
# Detect
# Alarms
# Complex
# Discover
# Init
# Read
# Ready
# Reset
# Verify
# Write
# Query
# First
# Next
# Search
# SearchLow
#
########################################################################################

package OWX_SER;

use strict;
use warnings;
use DevIo;

########################################################################################
# 
# Constructor
#
########################################################################################

sub new($) {
	my ($class,$hash) = @_;
	
	return bless {
		#-- OWX device
		hash => $hash,
		#-- baud rate serial interface
		baud => 9600,
		#-- 16 byte search string
		search => [0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0],
		ROM_ID => [0,0,0,0 ,0,0,0,0],
		#-- search state for 1-Wire bus search
		LastDiscrepancy => 0,
		LastFamilyDiscrepancy => 0,
		LastDeviceFlag => 0,
	}, $class;
}

########################################################################################
#
# Define - Implements Define method
# 
# Parameter def = definition string
#
# Return undef if ok, otherwise error message
#
########################################################################################

sub Define ($) {
	my ($self,$def) = @_;
	my $hash = $self->{hash};
	
	my @a = split("[ \t][ \t]*", $def);
	my $dev = $a[2];
    
    #-- when the specified device name contains @<digits>, remove these.
    $dev =~ s/\@\d*//;
    
    #-- store with OWX device
    $hash->{DeviceName}   = $dev;
    $hash->{INTERFACE}    = "serial";
    $hash->{ASYNCHRONOUS} = 0;  
  
    #-- module version
	$hash->{version}      = "7.01";
    main::Log3 $hash->{NAME},1,"OWX_SER::Define warning: version ".$hash->{version}." not identical to OWX version ".$main::owx_version
      if( $hash->{version} ne $main::owx_version);
      
    #-- call low level init function for the device
    $self->Init();
    return undef;
}

########################################################################################
#
# Detect - Find out if we have the proper interface
#
# Return 1 if ok, otherwise 0
#
########################################################################################

sub Detect () {
  my ($self) = @_;
  my $hash = $self->{hash};
  
  my ($i,$j,$k,$l,$res,$ret,$ress);
  my $name = $hash->{NAME};
  my $ress0 = "OWX_SER::Detect 1-Wire bus $name: interface ";
  $ress     = $ress0;

  my $interface;
  
  #-- timing byte for DS2480
  $self->Query("\xC1",1);
  
  #-- Max 4 tries to detect an interface
  for($l=0;$l<4;$l++) {
    #-- write 1-Wire bus (Fig. 2 of Maxim AN192)
    $res = $self->Query("\x17\x45\x5B\x0F\x91",5);
    
    #-- process 4/5-byte string for detection
    if( !defined($res)){
      $res="";
      $ret=0;
    }elsif( ($res eq "\x16\x44\x5A\x00") || ($res eq "\x16\x44\x5A\x00\x90") || ($res eq "\x16\x44\x5A\x00\x93")){
      $ress .= "master DS2480 detected for the first time";
      $interface="DS2480";
      $ret=1;
    } elsif( ($res eq "\x17\x45\x5B\x0F\x91") || ($res eq "\x17\x45\x1B\x0F\x91")){
      $ress .= "master DS2480 re-detected";
      $interface="DS2480";
      $ret=1;
    } else {
      $ret=0;
    }
    last 
      if( $ret==1 );
    main::OWX_WDBGL($name,4,$ress."not found, answer was ",$res);
    $ress = $ress0;
  }
  if( $ret == 0 ){
    $interface=undef;
    main::OWX_WDBGL($name,4,$ress."not detected, answer was ",$res);
  } else {
    main::OWX_WDBGL($name,3,$ress,undef);
  }
  $hash->{INTERFACE} = $interface;
  return $ret; 
}

########################################################################################
#
# Alarms - Find devices on the 1-Wire bus, which have the alarm flag set
#
# Return number of alarmed devices => DOES NOT WORK PROPERLY, WHY ????
#
########################################################################################

sub Alarms () {
  my ($self) = @_;
  my $hash = $self->{hash};
  my $name  = $hash->{NAME};
  
  #-- Discover all alarmed devices on the 1-Wire bus
  my $res = $self->First("alarm");
  while( $self->{LastDeviceFlag}==0 && $res != 0){
    $res = $res & $self->SER_Next("alarm");
  }
  if( $hash->{ALARMDEVS} ) {
    main::Log3 $name, 1, " Alarms = ".join(' ',@{$hash->{ALARMDEVS}});
    return( int(@{$hash->{ALARMDEVS}}) );
  } else {
    return 0;
  }
} 

########################################################################################
# 
# Complex - Send match ROM, data block and receive bytes as response
#
# Parameter hash    = hash of bus master, 
#           owx_dev = ROM ID of device
#           data    = string to send
#           numread = number of bytes to receive
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub Complex ($$$$) {
  my ($self,$dev,$data,$numread) =@_;
  my $hash = $self->{hash};
  my $name = $hash->{NAME};
  
  my $select;
  my $res;
  
  #-- get the interface
  my $interface = $hash->{INTERFACE};
  my $hwdevice  = $hash->{HWDEVICE};
  
  #-- has match ROM part
  if( $dev ){
    #-- ID of the device
    my $owx_rnf = substr($dev,3,12);
    my $owx_f   = substr($dev,0,2);

    #-- 8 byte 1-Wire device address
    my @rom_id  =(0,0,0,0,0,0,0,0); 
    #-- from search string to byte id
    $dev=~s/\.//g;
    for(my $i=0;$i<8;$i++){
       $rom_id[$i]=hex(substr($dev,2*$i,2));
    }
    $select=sprintf("\x55%c%c%c%c%c%c%c%c",@rom_id).$data; 
  #-- has no match ROM part
  } else {
    $select=$data;
  }
  #-- has receive data part
  if( $numread >0 ){
    #$numread += length($data);
    for( my $i=0;$i<$numread;$i++){
      $select .= "\xFF";
    };
  }
  
  main::OWX_WDBGL($name,5,"OWX_SER::Complex sending ",$select);
   
  #-- send data block (Fig. 6 of Maxim AN192)
  my $data2="";
  my $retlen = length($select);
   
  #-- if necessary, prepend E1 character for data mode
  if( substr($select,0,1) ne '\xE1') {
    $data2 = "\xE1";
  }
  #-- all E3 characters have to be duplicated
  for(my $i=0;$i<length($select);$i++){
    my $newchar = substr($select,$i,1);
    $data2=$data2.$newchar;
    if( $newchar eq '\xE3'){
      $data2=$data2.$newchar;
    }
  }
  #-- write 1-Wire bus as a single string
  $res =$self->Query($data2,$retlen);
  main::OWX_WDBGL($name,5,"OWX_SER::Complex receiving ",$res);
  return $res
}

########################################################################################
#
# Discover - Find devices on the 1-Wire bus
#
# Return 1, if alarmed devices found, 0 otherwise.
#
########################################################################################

sub Discover () {
  my ($self) = @_;
  my $hash = $self->{hash};
  
  #-- zero the array
  @{$hash->{DEVS}}=();
  #-- Discover all devices on the 1-Wire bus
  my $res = $self->First("discover");
  while( $self->{LastDeviceFlag}==0 && $res!=0 ){
    $res = $res & $self->Next("discover"); 
  }
  return( @{$hash->{DEVS}} == 0);
}

########################################################################################
# 
# Init - Initialize the 1-wire device
#
# Return undef if ok
#
########################################################################################

sub Init() {
  my ($self)   = @_;
  my $hash     = $self->{hash};
  my $dev      = $hash->{DeviceName};
  my $name     = $hash->{NAME};
  
  main::Log3 $name,5,"OWX_SER::Init called on device $dev for bus $name, state is ".$hash->{STATE};
  
  #if($hash->{STATE} ne "opened"){
  #XXX
    #main::DevIo_CloseDev($hash);
    main::DevIo_OpenDev($hash,0,undef);
  #}
  my $hwdevice = $hash->{USBDev};
    
  if( !($hwdevice)){
    main::Log3 $name,1, "OWX_SER: Can't open serial device $dev: $!";
  }else{
    main::Log3 $name,3, "OWX_SER: opened serial device $dev: $!";
    $hwdevice->reset_error();
    $hwdevice->baudrate(9600);
    $hwdevice->databits(8);
    $hwdevice->parity('none');
    $hwdevice->stopbits(1);
    $hwdevice->handshake('none');
    $hwdevice->write_settings;
    #-- store with OWX device
    $hash->{HWDEVICE}   = $hwdevice;
  }
  return undef;
}

#######################################################################################
#
# Read - Implement the Read function
#
# Parameter numexp = expected number of bytes
#
#######################################################################################

sub Read(@) {
  my ($self,$numexp)   = @_;
  my $hash     = $self->{hash};
  my $name     = $hash->{NAME};
  my $buffer   = "";
  
  #-- first try to read things
  $buffer = main::DevIo_SimpleRead($hash);  
  return $buffer;
}  
  
########################################################################################
# 
# Ready - Implement the Ready function
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Ready () {
  my ($self) = @_;
  my $hash = $self->{hash};
  my $name = $hash->{NAME};
  my $success;

  $success = main::DevIo_OpenDev($hash,1,"main::OWX_Init")
    if($hash->{STATE} eq "disconnected");
              
  return $success;
}

########################################################################################
# 
# Reset - Reset the 1-Wire bus (Fig. 4 of Maxim AN192)
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Reset () {
  my ($self)=@_;
  my $hash          = $self->{hash};
  my $name          = $hash->{NAME};
  my $interface     = $hash->{TYPE};
  my $asynchronous  = $hash->{ASYNCHRONOUS};
  
  return 0
   if( $hash->{STATE} eq "disconnected" );
  
  my ($res,$r1,$r2);
  #-- Reset command  
  my $cmd  = "\xE3\xC5"; 

  #-- OWX interface
  if( $interface eq "OWX" ){
    $res = $self->Query($cmd,1);
    $res = "" if( !$res );
  #-- OWX_ASYNC
  }elsif( $interface eq "OWX_ASYNC"){
    $res = $self->Query($cmd,1);
    $res = "" if( !$res );
  }

  #-- process result
  $r1  = ord(substr($res,0,1)) & 192;
  if( $r1 != 192){
    main::OWX_WDBGL($name,4,"OWX_SER::Reset failure on bus $name ",$res);
    return 0;
  }
  $hash->{ALARMED} = "no";
  
  $r2 = ord(substr($res,0,1)) & 3;
  
  if( $r2 == 3 ){
    main::Log3($name,4, "OWX_SER::Reset $name detects no presence");
    return 1;
  }elsif( $r2 ==2 ){
    main::Log3($name,3, "OWX_SER::Reset Alarm presence detected on bus $name");
    $hash->{ALARMED} = "yes";
  }
  return 1;
}

########################################################################################
#
# Query - Synchronously write to and read from the 1-Wire bus
# 
# Parameter: cmd    = string to send to the 1-Wire bus
#            retlen = expected length of return string
# Return: string received from the 1-Wire bus
#
########################################################################################

sub Query ($$) {
	
  my ($self,$cmd,$numexp) = @_;
  my $hash     = $self->{hash};
  my $name     = $hash->{NAME};
  my $state    = $hash->{STATE};
  my $timeout  = $hash->{timeout};
  my $numget   = 0;
  my $buffer   = "";
  my $try;

  if($state ne "opened") {
    main::Log3 $name, 4, "OWX_SER::Query $name: attempted to write to $state device $name";
    return undef;
  } 
  
  #-- write operation
  main::OWX_WDBGL($name,5,"OWX_SER::Query $name: Sending out",$cmd);
  return undef unless defined(main::DevIo_SimpleWrite($hash, $cmd, 0));
  
  #-- sleeping for some time
  select(undef,undef,undef,0.04);
  
  #-- first try to read things
  $buffer = main::DevIo_SimpleRead($hash); 
  $numget  = (defined($buffer))?length($buffer):0;
  
  #-- first try ok
  if( $numget >= $numexp){
    main::Log3 $name, 4, "OWX_SER::Query $name: $numget of $numexp bytes in first attempt and state $state";
    return $buffer;
  #-- several tries to read from slow device     
  }elsif( ($numget>0) && ($numget<$numexp) ){                                
    for($try=0;$try<3;$try++) {  
      $buffer .= main::DevIo_SimpleRead($hash);                    
      $numget  = length($buffer);            
      last
        if( $numget>=$numexp );  
      select(undef,undef,undef,0.01);
    }  
    main::Log3 $name, 5, "OWX_SER::Query $name: $numget of $numexp bytes in attempt $try and state $state"
      if( $numget < $numexp );
    return $buffer
      if( $numget >= $numexp);
  }
  
  #if( $numget >= $numexp){
  #  main::Log3 $name, 4, "OWX_SER::Query $name: $numget of $numexp bytes in 2nd attempt and state $state";
  #  return $buffer;
  #-- ultimate failure
  #}else{
    main::Log3 $name, 1,"OWX_SER::Query $name:  $numget of $numexp bytes in last attempt and state $state, this is an unrecoverable error";
    main::DevIo_Disconnected($hash);
    main::InternalTimer(main::gettimeofday()+$timeout, "main::OWX_Ready", $hash,0);
    return "";  
  #}
  
  
  #--reopen device
  main::Log3 $name, 4, "OWX_SER::Query $name: trying to close and open the device";

  #-- the next two lines are required to avoid a deadlock when the remote end
  #   closes the connection upon DevIo_OpenDev, as e.g. netcat -l <port> does.
  main::DevIo_CloseDev($hash);
  main::DevIo_OpenDev($hash, 0, undef);  

  #-- second try to read things - with timeout
  #$buffer .= main::DevIo_SimpleReadWithTimeout($hash, $timeout);  
  $buffer .= main::DevIo_SimpleRead($hash);  
  $numget  = (defined($buffer))?length($buffer):0;

  #-- second try ok
  if( $numget >= $numexp){
    main::Log3 $name, 4, "OWX_SER::Query $name: $numget of $numexp bytes after reopening and state $state";
    return $buffer;
  #-- several tries to read from slow device     
  }elsif( ($numget>0) && ($numget<$numexp) ){                                
    for($try=0;$try<4;$try++) {  
      $buffer .= main::DevIo_SimpleRead($hash);                    
      $numget  = length($buffer);            
      last
        if( $numget>=$numexp );  
      select(undef,undef,undef,0.01);
    }  
    main::Log3 $name, 5, "OWX_SER::Query $name: $numget of $numexp bytes in 2nd attempt try $try and state $state"
      if( $numget < $numexp );
  }

  if( $numget >= $numexp){
    main::Log3 $name, 4, "OWX_SER::Query $name: $numget of $numexp bytes in 2nd attempt and state $state";
    return $buffer;
  #-- ultimate failure
  }else{
    main::Log3 $name, 1,"OWX_SER::Query $name:  $numget of $numexp bytes in last attempt and state $state, this is an unrecoverable error";
    main::DevIo_Disconnected($hash);
    return "";  
  }
}

########################################################################################
#
# Verify - Verify a particular device on the 1-Wire bus
#
# Parameter dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not
#
########################################################################################

sub Verify ($) {
  my ($self,$dev) = @_;
  my $hash = $self->{hash};
  my @rom_id;
  my $i;
    
  #-- from search string to byte id
  my $devs=$dev;
  $devs=~s/\.//g;
  for($i=0;$i<8;$i++){
     $rom_id[$i]=hex(substr($devs,2*$i,2));
  }
  @{$self->{ROM_ID}}=@rom_id;
  #-- reset the search state
  $self->{LastDiscrepancy} = 64;
  $self->{LastDeviceFlag} = 0;
  #-- now do the search
  my $res=$self->Search("verify");
  my $dev2=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$self->{ROM_ID}});
  #-- reset the search state
  $self->{LastDiscrepancy} = 0;
  $self->{LastDeviceFlag} = 0;
  #-- check result
  if ($dev eq $dev2){
    return 1;
  }else{
    return 0;
  }
}

#######################################################################################
#
# Write - Implement the write function
#
# Parameter cmd   = string to be sent
#           reset = 1 if initial bus reset has to be done
#
########################################################################################

sub Write(@) {
  my ($self,$cmd, $reset) = @_;
  my $hash = $self->{hash};
  my $name = $hash->{NAME};
  
  if($hash->{STATE} eq "disconnected"){
    main::Log3 $name,4,"OWX_SER::Write attempted to disconnected device $name";
    return undef;
  }
  
  #-- if necessary, perform a reset operation
  $self->Reset()
    if( $reset ); 
    
  #-- if necessary, prepend E1 character for data mode of DS2480
  my $cmd2 = ( substr($cmd,0,1) ne '\xE1')?"\xE1":"";

  #-- all E3 characters have to be duplicated in DS2480
  for(my $i=0;$i<length($cmd);$i++){
    my $newchar = substr($cmd,$i,1);
    $cmd2=$cmd2.$newchar;
    if( $newchar eq '\xE3'){
      $cmd2=$cmd2.$newchar;
    }
  }
  
  main::OWX_WDBGL($name,4,"OWX_SER::Write Sending out ",$cmd2);
    
  main::DevIo_SimpleWrite($hash, $cmd2, 0);
  return;
}

#######################################################################################
#
# First - Find the 'first' devices on the 1-Wire bus
#
# Parameter mode
#
# Return 1 : device found, ROM number pushed to list
#        0 : no device present
#
########################################################################################

sub First ($) {
  my ($self,$mode) = @_;
  #-- clear 16 byte of search data
  @{$self->{search}} = (0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
  #-- reset the search state
  $self->{LastDiscrepancy} = 0;
  $self->{LastDeviceFlag} = 0;
  $self->{LastFamilyDiscrepancy} = 0;
  #-- now do the search
  return $self->Search($mode);
}

########################################################################################
#
# Next - Find the 'next' devices on the 1-Wire bus
#
# Parameter hash = hash of bus master, mode
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub Next ($) {
  my ($self,$mode) = @_;
  
  #-- now do the search
  return $self->Search($mode);
}

#######################################################################################
#
# Search - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub Search ($) {
  my ($self,$mode)=@_;
  my $hash = $self->{hash};
  my $name = $hash->{NAME};
  my $interface = $hash->{INTERFACE};
  my $hwdevice  = $hash->{HWDEVICE};
  
  my @owx_fams=();
  
  return 0 unless (defined $hwdevice);
  
  #-- if the last call was the last one, no search 
  if ($self->{LastDeviceFlag}==1){
    return 0;
  }
  #-- 1-Wire reset
  if ($self->Reset()==0){
    #-- reset the search
    main::Log(1, "OWX_SER::Search reset failed on bus $name");
    $self->{LastDiscrepancy} = 0;
    $self->{LastDeviceFlag} = 0;
    $self->{LastFamilyDiscrepancy} = 0;
    return 0;
  }
  
  #-- Here we call the device dependent part
  $self->SearchLow($mode);
  
  #--check if we really found a device
  if( main::OWX_CRC($self->{ROM_ID})!= 0){
  #-- reset the search
    main::Log(1, "OWX_SER::Search CRC failed on bus $name");
    $self->{LastDiscrepancy} = 0;
    $self->{LastDeviceFlag} = 0;
    $self->{LastFamilyDiscrepancy} = 0;
    return 0;
  }
    
  #-- character version of device ROM_ID, first byte = family 
  my $dev=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$self->{ROM_ID}});
  
  #-- for some reason this does not work - replaced by another test, see below
  #if( $self->{LastDiscrepancy}==0 ){
  #    $self->{LastDeviceFlag}=1;
  #}
  #--
  if( $self->{LastDiscrepancy}==$self->{LastFamilyDiscrepancy} ){
      $self->{LastFamilyDiscrepancy}=0;    
  }
    
  #-- mode was to verify presence of a device
  if ($mode eq "verify") {
    main::Log(5, "OWX_SER::Search verified $dev on bus $name");
    return 1;
  #-- mode was to discover devices
  } elsif( $mode eq "discover" ){
    #-- check families
    my $famfnd=0;
    foreach (@owx_fams){
      if( substr($dev,0,2) eq $_ ){        
        #-- if present, set the fam found flag
        $famfnd=1;
        last;
      }
    }
    push(@owx_fams,substr($dev,0,2)) if( !$famfnd );
    foreach (@{$hash->{DEVS}}){
      if( $dev eq $_ ){        
        #-- if present, set the last device found flag
        $self->{LastDeviceFlag}=1;
        last;
      }
    }
    if( $self->{LastDeviceFlag}!=1 ){
      #-- push to list
      push(@{$hash->{DEVS}},$dev);
      main::Log(5, "OWX_SER::Search new device found $dev on bus $name");
    }  
    return 1;
    
  #-- mode was to discover alarm devices 
  } elsif( $hash->{ALARMDEVS} ) {
    for(my $i=0;$i<@{$hash->{ALARMDEVS}};$i++){
      if( $dev eq ${$hash->{ALARMDEVS}}[$i] ){        
        #-- if present, set the last device found flag
        $self->{LastDeviceFlag}=1;
        last;
      }
    }
    if( $self->{LastDeviceFlag}!=1 ){
    #--push to list
      push(@{$hash->{ALARMDEVS}},$dev);
      main::Log(5, "OWX_SER::Search new alarm device found $dev on bus $name");
    }  
    return 1;
  } 
}

########################################################################################
#
# SearchLow - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub SearchLow ($) {
  my ($self,$mode)=@_;
  my $hash = $self->{hash};
  
  my ($sp1,$sp2,$response,$search_direction,$id_bit_number);
    
  #-- Response search data parsing operates bytewise
  $id_bit_number = 1;
  
  #-- used to be 0.5
  select(undef,undef,undef,0.05);
  
  #-- clear 16 byte of search data
  @{$self->{search}}=(0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
  #-- Output search data construction (Fig. 9 of Maxim AN192)
  #   operates on a 16 byte search response = 64 pairs of two bits
  while ( $id_bit_number <= 64) {
    #-- address single bits in a 16 byte search string
    my $newcpos = int(($id_bit_number-1)/4);
    my $newimsk = ($id_bit_number-1)%4;
    #-- address single bits in a 8 byte id string
    my $newcpos2 = int(($id_bit_number-1)/8);
    my $newimsk2 = ($id_bit_number-1)%8;

    if( $id_bit_number <= $self->{LastDiscrepancy}){
      #-- first use the ROM ID bit to set the search direction  
      if( $id_bit_number < $self->{LastDiscrepancy} ) {
        $search_direction = (@{$self->{ROM_ID}}[$newcpos2]>>$newimsk2) & 1;
        #-- at the last discrepancy search into 1 direction anyhow
      } else {
        $search_direction = 1;
      } 
      #-- fill into search data;
      @{$self->{search}}[$newcpos]+=$search_direction<<(2*$newimsk+1);
    }
    #--increment number
    $id_bit_number++;
  }
  #-- issue data mode \xE1, the normal search command \xF0 or the alarm search command \xEC 
  #   and the command mode \xE3 / start accelerator \xB5 
  if( $mode ne "alarm" ){
    $sp1 = "\xE1\xF0\xE3\xB5";
  } else {
    $sp1 = "\xE1\xEC\xE3\xB5";
  }
  #-- issue data mode \xE1, device ID, command mode \xE3 / end accelerator \xA5
  $sp2=sprintf("\xE1%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c%c\xE3\xA5",@{$self->{search}}); 
  $response = $self->Query($sp1,1); 
  $response = $self->Query($sp2,16);   
     
  #-- interpret the return data
  if( length($response)!=16 ) {
    main::Log(3, "OWX_SER::Search 2nd return has wrong parameter with length = ".length($response)."");
    return 0;
  }
  #-- Response search data parsing (Fig. 11 of Maxim AN192)
  #   operates on a 16 byte search response = 64 pairs of two bits
  $id_bit_number = 1;
  #-- clear 8 byte of device id for current search
  @{$self->{ROM_ID}} =(0,0,0,0 ,0,0,0,0); 

  while ( $id_bit_number <= 64) {
    #-- adress single bits in a 16 byte string
    my $newcpos = int(($id_bit_number-1)/4);
    my $newimsk = ($id_bit_number-1)%4;

    #-- retrieve the new ROM_ID bit
    my $newchar = substr($response,$newcpos,1);
 
    #-- these are the new bits
    my $newibit = (( ord($newchar) >> (2*$newimsk) ) & 2) / 2;
    my $newdbit = (  ord($newchar) >> (2*$newimsk) ) & 1;

    #-- output for test purpose
    #print "id_bit_number=$id_bit_number => newcpos=$newcpos, newchar=0x".int(ord($newchar)/16).
    #      ".".int(ord($newchar)%16)." r$id_bit_number=$newibit d$id_bit_number=$newdbit\n";
    
    #-- discrepancy=1 and ROM_ID=0
    if( ($newdbit==1) and ($newibit==0) ){
        $self->{LastDiscrepancy}=$id_bit_number;
        if( $id_bit_number < 9 ){
        	$self->{LastFamilyDiscrepancy}=$id_bit_number;
        }
    } 
    #-- fill into device data; one char per 8 bits
    @{$self->{ROM_ID}}[int(($id_bit_number-1)/8)]+=$newibit<<(($id_bit_number-1)%8);
  
    #-- increment number
    $id_bit_number++;
  }
  return 1;
}

1;


=pod
=item helper
=item summary to address an OWX interface device via USB/Serial Interface
=item summary_DE zur Adressierung eines OWX Interface Device via USB/Serial Interface
=begin html

<a name="OWX_SER"></a>
<h3>OWX_SER</h3>
See <a href="/fhem/docs/commandref.html#OWX">OWX</a>
end html
=begin html_DE

<a name="OWX_SER"></a>
<h3>OWX_SER</h3>
<a href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#OWX">OWX</a> 
=end html_DE
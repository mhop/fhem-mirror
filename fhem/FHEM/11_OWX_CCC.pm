########################################################################################
#
# OWX_CCC.pm
#
# FHEM module providing hardware dependent functions for the COC/CUNO interface of OWX
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
# ReadLow
# Ready
# Reset
# Verify
# Write
#
########################################################################################

package OWX_CCC;

use strict;
use warnings;

########################################################################################
# 
# Constructor
#
########################################################################################

sub new($) {
	my ($class,$hash) = @_;

	return bless {
		hash => $hash,
	    #-- module version
		version => "7.01"
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

sub Define($) {
	my ($self,$def) = @_;
	my $hash = $self->{hash};
	
	my @a = split("[ \t][ \t]*", $def);

	#-- check syntax
	if(int(@a) < 3){
		return "OWX_CCC::Define Syntax error - must be define <name> OWX <cuno/coc-device>"
	}
	
    my $name = $a[0];
    $hash->{NAME} = $name;
    my $dev  = $a[2];
    $hash->{DeviceName} = $dev;
    
    
    #-- Second step in case of CUNO: See if we can open it
    my $msg = "OWX_CCC::Define COC/CUNO device $dev";
    #-- hash des COC/CUNO
    my $hwdevice = $main::defs{$dev};
    if(!$hwdevice){
      main::Log3 $name,1, $msg." not defined";
      return $msg." not defined";
    } 
    
    main::Log(1,$msg." defined");
    
    #-- store with OWX device
    $hash->{DeviceName}   = $dev;
    $hash->{ASYNCHRONOUS} = 0; 
    $hash->{INTERFACE}    = "COC/CUNO";
    $hash->{HWDEVICE}     = $hwdevice;
    
    #-- loop for some time until the state is "Initialized"
    for(my $i=0;$i<6;$i++){
      last if( $hwdevice->{STATE} eq "Initialized");
      main::Log(1,"OWX_CCC::Define Waiting, at t=$i ".$dev." is still ".$hwdevice->{STATE});
      select(undef,undef,undef,3); 
    }
    main::Log(1, "OWX_CCC::Define Can't open ".$dev) if( $hwdevice->{STATE} ne "Initialized");
    #-- reset the 1-Wire system in COC/CUNO
    main::CUL_SimpleWrite($hwdevice, "Oi");
      
    #-- module version
	$hash->{version}      = "7.0beta2";
    main::Log3 $name,1,"OWX_CCC::Define warning: version ".$hash->{version}." not identical to OWX version ".$main::owx_version
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
  
  my ($ret,$ress);
  my $name = $hash->{NAME};
  my $ress0 = "OWX_CCC::Detect: 1-Wire bus $name interface ";
  $ress     = $ress0;

  #-- get the interface
  my $interface;
  my $hwdevice  = $hash->{HWDEVICE};
  
  select(undef,undef,undef,2);
  #-- type of interface
  main::CUL_SimpleWrite($hwdevice, "V");
  select(undef,undef,undef,0.01);
  my ($err,$ob) = ReadLow($hwdevice);
  #my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "V"));
  #-- process result for detection
  if( !defined($ob)){
    $ob="";
    $ret=0;
  #-- COC
  }elsif( $ob =~ m/.*CSM.*/){
    $interface="COC";
    $ress .= "DS2482 / COC detected in $hwdevice->{NAME}";
    $ret=1;
  #-- CUNO
  }elsif( $ob =~ m/.*CUNO.*/){
    $interface="CUNO";
     $ress .= "DS2482 / CUNO detected in $hwdevice->{NAME}";
    $ret=1;
  #-- something else
  } else {
    $ret=0;
  }
  #-- treat the failure cases
  if( $ret == 0 ){
    $interface=undef;
    $ress .= "in $hwdevice->{NAME} could not be addressed, return was $ob";
  }
  #-- store with OWX device
  $hash->{INTERFACE} = $interface;
  main::Log(1, $ress);
  return $ret; 
}

########################################################################################
#
# Alarms - Find devices on the 1-Wire bus, which have the alarm flag set
#
# Return 0 because not implemented here.
#
########################################################################################

sub Alarms () {
  my ($self) = @_;
  
  return 0;
} 

########################################################################################
# 
# Complex - Send match ROM, data block and receive bytes as response
#
# Parameter dev = ROM ID of device
#           data    = string to send
#           numread = number of bytes to receive
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub Complex ($$$) {
  my ($self,$dev,$data,$numread) =@_;
  my $hash = $self->{hash};
  
  my $select;
  my $res = "";
  
  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  my $name      = $hash->{NAME};
  
  #-- has match ROM part
  if( $dev ){
    #-- ID of the device
    my $owx_rnf = substr($dev,3,12);
    my $owx_f   = substr($dev,0,2);

    #-- 8 byte 1-Wire device address
    my @rom_id  =(0,0,0,0 ,0,0,0,0); 
    #-- from search string to reverse string id
    $dev=~s/\.//g;
    for(my $i=0;$i<8;$i++){
       $rom_id[7-$i]=substr($dev,2*$i,2);
    }
    $select=sprintf("Om%s%s%s%s%s%s%s%s",@rom_id); 
    main::Log3 $name,5,"OWX_CCC::Complex: sending match ROM to COC/CUNO ".$select;
    #--
    main::CUL_SimpleWrite($hwdevice, $select);
    my ($err,$ob) = ReadLow($hwdevice);
    #-- padding first 9 bytes into result string, since we have this 
    #   in the serial interfaces as well
    $res .= "000000000";
  }
  #-- has data part
  if ( $data ){
    $self->Write($data,0);
    $res .= $data;
  }
  #-- has receive part
  if( $numread > 0 ){
    #$numread += length($data);
    main::Log3 $name,5,"OWX_CCC::Complex: COC/CUNO is expected to deliver $numread bytes";
    $res.=$self->Read($numread);
  }
  return $res;
}

########################################################################################
#
# Discover - Discover devices on the 1-Wire bus via internal firmware
#
# Return 0  : error
#        1  : OK
#
########################################################################################

sub Discover () {
  my ($self) = @_;
  my $hash = $self->{hash};
  
  my $res;
  
  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  my $name      = $hash->{NAME};
  
  #-- zero the array
  @{$hash->{DEVS}}=();
  #-- reset the busmaster
  $self->Init();
  #-- get the devices
  main::CUL_SimpleWrite($hwdevice, "Oc");
  select(undef,undef,undef,0.5);
  my ($err,$ob) = ReadLow($hwdevice);
  if( $ob ){
    # main::Log(3,"OWX_CCC::Discover: ".$hwdevice->{NAME}." device search returns ".$ob);
    foreach my $dx (split(/\n/,$ob)){
      next if ($dx !~ /^\d\d?\:[0-9a-fA-F]{16}/);
      $dx =~ s/\d+\://;
      my $ddx = substr($dx,14,2).".";
      #-- reverse data from culfw
      for( my $i=1;$i<7;$i++){
        $ddx .= substr($dx,14-2*$i,2);
      }
      $ddx .= ".".substr($dx,0,2);
      push (@{$hash->{DEVS}},$ddx);
    }
    return 1;
  } else {
    main::Log3 $name,1, "OWX_CCC::Discover No answer to device search";
    return 0;
  }
}

########################################################################################
# 
# Init - Low Level Init of the 1-wire device
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Init () { 
  my ($self) = @_;
  my $hash = $self->{hash};
  my $dev      = $hash->{DeviceName};
  my $name     = $hash->{NAME};
  
  #main::Log3 $name,1,"OWX_CCC::Init called on device $dev for bus $name, state is ".$hash->{STATE};
  
  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  
  my $ob = main::CallFn($hwdevice->{NAME}, "GetFn", $hwdevice, (" ", "raw", "ORm"));
      #--
  #  main::CUL_SimpleWrite($hwdevice, "ORm");
  #  select(undef,undef,undef,0.01);
  #  my ($err,$ob) = ReadLow($hwdevice);
  #main::Log3 $name,1,"OWX_CCC::Init gives ob=$ob ";
  if( !defined($ob) ){
    #main::Log 1,"empty ORm";
    return "empty ORm";
  }elsif( length($ob) < 13){
    #main::Log 1,"short ORm of length ".length($ob);
    return "short ORm of length ".length($ob);
  }elsif( substr($ob,9,4) eq "OK" ){
    #main::Log 1,"=====> OK";
    $hash->{STATE} = "opened";
    return undef;
  }else{
    #main::Log 1,"=====> ORm empty -> still OK ???";
    $hash->{STATE} = "opened";
    return undef;
  }
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
  my $state    = $hash->{STATE};
  my $buffer   = "";
  my $numget   = 0;
  my ($err,$ob);
  my $try;
  my $maxtry   = $numexp;
  
  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  
  for($try=0;$try<$maxtry;$try++){
    #main::Log(1, "Sending $hwdevice->{NAME}: OrB";
    #my $ob = CallFn($hwdevice->{NAME}, "GetFn", $hwdevice, (" ", "raw", "OrB"));
    main::CUL_SimpleWrite($hwdevice, "OrB");
    ($err,$ob) = main::CUL_ReadAnswer($hwdevice,$name,0,undef);
    #select(undef,undef,undef,0.01);
    #($err,$ob) = ReadLow($hwdevice);

    #-- process results  
    if( !(defined($ob)) ){
      return "";
    #-- four bytes received makes one byte of result
    }elsif( length($ob) == 4 ){
      $buffer .= sprintf("%c",hex(substr($ob,0,2)));
      $numget++;
    #-- 11 bytes received makes one byte of result
    }elsif( length($ob) == 11 ){
      $buffer .= sprintf("%c",hex(substr($ob,9,2)));
      $numget++;
    #-- 18 bytes received from CUNO 
    }elsif( length($ob) == 18 ){
      main::OWX_WDBGL($name,4,"OWX_CCC::Read 18 bytes from CUNO: ",$ob);
    #-- 20 bytes received = leftover from match
    }elsif( length($ob) == 20 ){
      $maxtry++;
    }else{
      main::Log3 $name,1,"OWX_CCC::Read unexpected number of ".length($ob)." bytes on bus ".$hwdevice->{NAME};
    } 
  }
  if( $numget >= $numexp){
    main::OWX_WDBGL($name,1,"OWX_CCC::Read from CUNO with error=$err: ",$buffer);
    return $buffer    
  #-- ultimate failure
  }else{
    main::Log3 $name, 1,"OWX_CCC::Read $name: $numget of $numexp bytes  with error=$err at state $state, this is an unrecoverable error";
    #main::DevIo_Disconnected($hwdevice);
    return "";  
  }
}

########################################################################################
#
# ReadLow - Replacement for CUL_ReadAnswer for better control
# 
# Parameter: hash = hash of bus master 
#
# Return: string received 
#
########################################################################################

sub ReadLow($)
{
  my ($hwdevice) = @_;
  
  my $type = $hwdevice->{TYPE};
  my $name = $hwdevice->{NAME};

  my $arg ="";
  my $anydata=0;
  my $regexp =undef;
   
  my ($mculdata, $rin) = ("", '');
  my $buf;
  my $to = 3;                                         # 3 seconds timeout
  $to = $hwdevice->{RA_Timeout} if($hwdevice->{RA_Timeout});  # ...or less
  for(;;) {
      return ("Device lost when reading answer for get $arg", undef)
        if(!$hwdevice->{FD});

      vec($rin, $hwdevice->{FD}, 1) = 1;
      my $nfound = select($rin, undef, undef, $to);
      if($nfound < 0) {
        next if ($! == EAGAIN() || $! == EINTR() || $! == 0);
        my $err = $!;
        #main::DevIo_Disconnected($hwdevice); 
        main::Log 1,"============================> DISCOINNECTING";
        return("ReadLow $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = main::DevIo_SimpleRead($hwdevice);
      return ("No data", undef) if(!defined($buf));

    if($buf) {
      main::Log3 $name,5, "OWX_CCC::ReadLow $buf";
      $mculdata .= $buf;
    }

    # \n\n is socat special
    if($mculdata =~ m/\r\n/ || $anydata || $mculdata =~ m/\n\n/ ) {
      if($regexp && $mculdata !~ m/$regexp/) {
        main::CUL_Parse($hwdevice, $hwdevice, $hwdevice->{NAME}, $mculdata, $hwdevice->{initString});
      } else {
        return (undef, $mculdata)
      }
    }
  }
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
# Reset - Reset the 1-Wire bus 
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Reset () { 
  my ($self) = @_;
  my $hash = $self->{hash};
  
  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  
  my $ob = main::CallFn($hwdevice->{NAME}, "GetFn", $hwdevice, (" ", "raw", "ORb"));
  
  if( substr($ob,9,4) eq "OK:1" ){
    return 1;
  }else{
    return 0
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
  
  my $i;
    
  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  
  #-- Ask the COC/CUNO 
  main::CUL_SimpleWrite($hwdevice, "OCf");
  #-- sleeping for some time
  select(undef,undef,undef,3);
  main::CUL_SimpleWrite($hwdevice, "Oc");
  select(undef,undef,undef,0.5);
  my ($err,$ob) = $self->($hwdevice);
  if( $ob ){
    foreach my $dx (split(/\n/,$ob)){
      next if ($dx !~ /^\d\d?\:[0-9a-fA-F]{16}/);
      $dx =~ s/\d+\://;
      my $ddx = substr($dx,14,2).".";
      #-- reverse data from culfw
      for( my $i=1;$i<7;$i++){
        $ddx .= substr($dx,14-2*$i,2);
      }
      $ddx .= ".".substr($dx,0,2);
      return 1 if( $dev eq $ddx);
    }
  }
  return 0;
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
  my $count_out;
  
  if($hash->{STATE} eq "disconnected"){
    main::Log3 $name,4,"OWX_CCC::Write attempted to disconnected device $name";
    return undef;
  }
  
  #-- if necessary, perform a reset operation
  $self->Reset()
    if( $reset );
  
  my ($i,$j,$k);
  my $res  = "";

  #-- get the interface
  my $hwdevice  = $hash->{HWDEVICE};
  
  for( $i=0;$i<length($cmd);$i++){
    $j   = int(ord(substr($cmd,$i,1))/16);
    $k   = ord(substr($cmd,$i,1))%16;
  	$res = sprintf "OwB%1x%1x ",$j,$k;
    main::CUL_SimpleWrite($hwdevice, $res);
  } 
  main::OWX_WDBGL($name,5,"OWX_CCC::Write Sending out ",$cmd);
}

1;

=pod
=item helper
=item summary to address an OWX interface device via COC/CUNO
=item summary_DE zur Adressierung eines OWX Interface Device mit COC/CUNO
=begin html

<a name="OWX_CCC"></a>
<h3>OWX_CCC</h3>
See <a href="/fhem/docs/commandref.html#OWX">OWX</a>
end html
=begin html_DE

<a name="OWX_CCC"></a>
<h3>OWX_CCC</h3>
<a href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#OWX">OWX</a> 
=end html_DE
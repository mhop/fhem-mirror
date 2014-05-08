########################################################################################
#
# OWX_CCC.pm
#
# FHEM module providing hardware dependent functions for the COC/CUNO interface of OWX
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
#
# $Id: 11_OWX_CCC.pm 2013-03 - pahenning $
#
########################################################################################
#
# Provides the following methods for OWX
#
# Alarms
# Complex
# Define
# Discover
# Init
# Reset
# Verify
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
	my ($class) = @_;

	return bless {
		interface => "COC/CUNO",		
	    #-- module version
		version => 4.0
	}, $class;
}

########################################################################################
# 
# Public methods
#
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
	my ($self,$hash,$def) = @_;
	
	my @a = split("[ \t][ \t]*", $def);

	#-- check syntax
	if(int(@a) < 3){
		return "OWX_CCC: Syntax error - must be define <name> OWX <cuno/coc-device>"
	}
	my $dev = $a[2];
		
    $hash->{DeviceName} = $dev;
    #-- Second step in case of CUNO: See if we can open it
    my $msg = "OWX_CCC: COC/CUNO device $dev";
    #-- hash des COC/CUNO
    my $hwdevice = $main::defs{$dev};
    if($hwdevice){
      main::Log(1,$msg." defined");
      #-- store with OWX device
      $self->{hwdevice}    = $hwdevice;
      #-- loop for some time until the state is "Initialized"
      for(my $i=0;$i<6;$i++){
        last if( $hwdevice->{STATE} eq "Initialized");
        main::Log(1,"OWX_CCC: Waiting, at t=$i ".$dev." is still ".$hwdevice->{STATE});
        select(undef,undef,undef,3); 
      }
      main::Log(1, "OWX_CCC: Can't open ".$dev) if( $hwdevice->{STATE} ne "Initialized");
      #-- reset the 1-Wire system in COC/CUNO
      main::CUL_SimpleWrite($hwdevice, "Oi");
      
      $dev = split('@',$dev);
      #-- let fhem.pl MAIN call OWX_Ready when setup is done.
      $main::readyfnlist{"$hash->{NAME}.$dev"} = $hash;
      
      return undef;
    }else{
      main::Log(1, $msg." not defined");
      return $msg." not defined";
    } 
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
  
  my $select;
  my $res = "";
  
  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
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
    main::Log(3,"OWX_CCC::Complex: sending match ROM to COC/CUNO ".$select)
       if( $main::owx_debug > 1);
    #--
    main::CUL_SimpleWrite($hwdevice, $select);
    my ($err,$ob) = ReadAnswer($hwdevice);
    #-- padding first 9 bytes into result string, since we have this 
    #   in the serial interfaces as well
    $res .= "000000000";
  }
  #-- has data part
  if ( $data ){
    $self->Send($data);
    $res .= $data;
  }
  #-- has receive part
  if( $numread > 0 ){
    #$numread += length($data);
    main::Log(3,"OWX_CCC::Complex: COC/CUNO is expected to deliver $numread bytes")
      if( $main::owx_debug > 1);
    $res.=$self->Receive($numread);
  }
  main::Log(3,"OWX_CCC::Complex: returned from COC/CUNO $res")
    if( $main::owx_debug > 1);
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
  
  my $res;
  
  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
  #-- zero the array
  my @devs=();
  #-- reset the busmaster
  $self->Init();
  #-- get the devices
  main::CUL_SimpleWrite($hwdevice, "Oc");
  select(undef,undef,undef,0.5);
  my ($err,$ob) = ReadAnswer($hwdevice);
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
      push (@devs,$ddx);
    }
    return \@devs;
  } else {
    main::Log(1, "OWX_CCC: No answer to ".$hwdevice->{NAME}." device search");
    return 0;
  }
}

########################################################################################
# 
# Init - Initialize the 1-wire device
#
# Return 1 or Errormessage: not OK
#        0 or undef: OK
#
########################################################################################

sub Init ($) { 
  my ($self,$hash) = @_;
  
  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
  my $get = main::CallFn($hwdevice->{NAME}, "GetFn", $hwdevice, (" ", "raw", "ORm"));
  return 1 if( !defined($get) );
  return 1 if( length($get) < 13);
  return 1 unless ( substr($get,9,4) eq "OK" );

  my ($ret,$ress);
  my $name = $hash->{NAME};
  my $ress0 = "OWX_CCC::Detect: 1-Wire bus $name interface ";
  $ress     = $ress0;

  #-- get the interface
  my $interface;
  
  select(undef,undef,undef,2);
  #-- type of interface
  main::CUL_SimpleWrite($hwdevice, "V");
  select(undef,undef,undef,0.01);
  my ($err,$ob) = ReadAnswer($hwdevice);
  #my $ob = CallFn($owx_hwdevice->{NAME}, "GetFn", $owx_hwdevice, (" ", "raw", "V"));
  #-- process result for detection
  if( !defined($ob)){
    $ob="";
    $ret=1;
  #-- COC
  }elsif( $ob =~ m/.*CSM.*/){
    $interface="COC";
    $ress .= "DS2482 / COC detected in $hwdevice->{NAME}";
    $ret=0;
  #-- CUNO
  }elsif( $ob =~ m/.*CUNO.*/){
    $interface="CUNO";
     $ress .= "DS2482 / CUNO detected in $hwdevice->{NAME}";
    $ret=0;
  #-- something else
  } else {
    $ret=1;
  }
  #-- treat the failure cases
  if( $ret == 1 ){
    $interface=undef;
    $ress .= "in $hwdevice->{NAME} could not be addressed, return was $ob";
  }
  #-- store with OWX device
  $self->{interface} = $interface;
  main::Log(1, $ress);
  return $ret; 
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
  
  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
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
  
  my $i;
    
  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
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
# Private methods 
#
########################################################################################
#
# ReadAnswer - Replacement for CUL_ReadAnswer for better control
# 
# Parameter: hash = hash of bus master 
#
# Return: string received 
#
########################################################################################

sub ReadAnswer($)
{
  my ($hwdevice) = @_;
  
  my $type = $hwdevice->{TYPE};

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
        main::DevIo_Disconnected($hwdevice); # TODO: DevIO_Disconnected sets hash on readyFnList! -> results in errors later as there's no ReadyFn in OWX
        return("ReadAnswer $arg: $err", undef);
      }
      return ("Timeout reading answer for get $arg", undef)
        if($nfound == 0);
      $buf = main::DevIo_SimpleRead($hwdevice);
      return ("No data", undef) if(!defined($buf));

 

    if($buf) {
      main::Log(5, "OWX_CCC::ReadAnswer $buf");
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
# Receive - Read data from the 1-Wire bus
# 
# Parameter: hash = hash of bus master, numread = number of bytes to read
#
# Return: string received 
#
########################################################################################

sub Receive ($) {
  my ($self,$numread) = @_;
  
  my $res="";
  my $res2="";
  
  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
  for( 
  my $i=0;$i<$numread;$i++){
  #main::Log(1, "Sending $hwdevice->{NAME}: OrB";
  #my $ob = CallFn($hwdevice->{NAME}, "GetFn", $hwdevice, (" ", "raw", "OrB"));
  main::CUL_SimpleWrite($hwdevice, "OrB");
  select(undef,undef,undef,0.01);
  my ($err,$ob) = ReadAnswer($hwdevice);
  #main::Log(1, "Answer from $hwdevice->{NAME}:$ob: ";

    #-- process results  
    if( !(defined($ob)) ){
      return "";
    #-- four bytes received makes one byte of result
    }elsif( length($ob) == 4 ){
      $res  .= sprintf("%c",hex(substr($ob,0,2)));
      $res2 .= "0x".substr($ob,0,2)." ";
    #-- 11 bytes received makes one byte of result
    }elsif( length($ob) == 11 ){
      $res  .= sprintf("%c",hex(substr($ob,9,2)));
      $res2 .= "0x".substr($ob,9,2)." ";
    #-- 18 bytes received from CUNO 
    }elsif( length($ob) == 18 ){
    
    my $res = "OWX_CCC::Receive: 18 bytes from CUNO: $ob\n";
    for(my $i=0;$i<length($ob);$i++){  
      my $j=int(ord(substr($ob,$i,1))/16);
      my $k=ord(substr($ob,$i,1))%16;
      $res.=sprintf "0x%1x%1x ",$j,$k;
    }
    main::Log(3, $res);
    
    #$numread++;
    #-- 20 bytes received = leftover from match
    }elsif( length($ob) == 20 ){
      $numread++;
    }else{
      main::Log(1,"OWX_CCC::Receive: unexpected number of ".length($ob)." bytes on bus ".$hwdevice->{NAME});
    } 
  }
  main::Log(3, "OWX_CCC::Receive: $numread bytes = $res2 on bus ".$hwdevice->{NAME})
     if( $main::owx_debug > 1);
  
  return($res);
}

#########################################################################################
# 
# Send - Send data block  
#
# Parameter hash = hash of bus master, data = string to send
#
# Return response, if OK
#        0 if not OK
#
########################################################################################

sub Send ($) {
  my ($self,$data) =@_;
  
  my ($i,$j,$k);
  my $res  = "";
  my $res2 = "";

  #-- get the interface
  my $hwdevice  = $self->{hwdevice};
  
  for( $i=0;$i<length($data);$i++){
    $j=int(ord(substr($data,$i,1))/16);
    $k=ord(substr($data,$i,1))%16;
  	$res  =sprintf "OwB%1x%1x ",$j,$k;
    $res2.=sprintf "0x%1x%1x ",$j,$k;
    main::CUL_SimpleWrite($hwdevice, $res);
  } 
  main::Log(3,"OWX_CCC::Send to COC/CUNO $res2")
     if( $main::owx_debug > 1);
}

1;
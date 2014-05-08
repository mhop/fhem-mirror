########################################################################################
#
# OWX_SER.pm
#
# FHEM module providing hardware dependent functions for the serial (USB) interface of OWX
#
# Prof. Dr. Peter A. Henning
# Norbert Truchsess
#
# $Id: OWX_SER.pm 2013-04 - ntruchsess $
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

package OWX_SER;

use strict;
use warnings;

use vars qw/@ISA/;
@ISA='OWX_Executor';

use ProtoThreads;
no warnings 'deprecated';

########################################################################################
# 
# Constructor
#
########################################################################################

sub new() {
	my $class = shift;
	
	require "$main::attr{global}{modpath}/FHEM/OWX_Executor.pm";
	
	my $self = OWX_Executor->new();
	
	$self->{interface} = "serial";
	#-- baud rate serial interface
	$self->{baud} = 9600;
	#-- 16 byte search string
	$self->{search} = [0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0];
	$self->{ROM_ID} = [0,0,0,0 ,0,0,0,0];
	#-- search state for 1-Wire bus search
	$self->{LastDiscrepancy} = 0;
	$self->{LastFamilyDiscrepancy} = 0;
	$self->{LastDeviceFlag} = 0;
	#-- module version
	$self->{version} = 4.0;
	$self->{alarmdevs} = [];
	$self->{devs} = [];
	$self->{pt_alarms} = PT_THREAD(\&pt_alarms);
	$self->{pt_discover} = PT_THREAD(\&pt_discover);
	$self->{pt_verify} = PT_THREAD(\&pt_verify);
	$self->{pt_execute} = PT_THREAD(\&pt_execute);
	
	$self->{timeout} = 1.0; #default timeout 1 sec.

	return bless $self,$class;	
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

sub Define ($$) {
	my ($self,$hash,$def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	$self->{name} = $hash->{NAME};

	#-- check syntax
	if(int(@a) < 3){
		return "OWX_SER: Syntax error - must be define <name> OWX <serial-device>"
	}
	my $dev = $a[2];
    
  #-- when the specified device name contains @<digits> already, use it as supplied
  if ( $dev !~ m/\@\d*/ ){
    $hash->{DeviceName} = $dev."\@9600";
  }
  $dev = split('@',$dev);
  #-- let fhem.pl MAIN call OWX_Ready when setup is done.
  $main::readyfnlist{"$hash->{NAME}.$dev"} = $hash;
    
  return undef;
}

########################################################################################
#
# Alarms - Find devices on the 1-Wire bus, which have the alarm flag set
#
# Return number of alarmed devices
#
########################################################################################

sub pt_alarms () {
  my ($thread,$self) = @_;
  
  PT_BEGIN($thread);
  $self->{alarmdevs} = [];
  #-- Discover all alarmed devices on the 1-Wire bus
  $self->first("alarm");
  do {
    $self->next("alarm");
    PT_WAIT_UNTIL($self->response_ready());
    PT_EXIT unless $self->next_response("alarm");
  } while( $self->{LastDeviceFlag}==0 );
  main::Log3($self->{name},1, " Alarms = ".join(' ',@{$self->{alarmdevs}}));
  PT_EXIT($self->{alarmdevs});
  PT_END;
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

sub pt_execute($$$$$$$) {
  my ($thread, $self, $hash, $context, $reset, $address, $writedata, $numread) = @_;

  PT_BEGIN($thread);
  
  #-- get the interface
  my $interface = $self->{interface};
  my $hwdevice  = $self->{hwdevice};

  PT_EXIT unless (defined $hwdevice);

  $self->reset() if ($reset);

  my $dev = $address;
  my $data = $writedata;
  
  my $select;
  my $res2 = "";
  my ($i,$j,$k);
  
  #-- has match ROM part
  if( $dev ){#		command   => EXECUTE,
#		context   => $context,
#		reset     => $reset,
#		address   => $owx_dev,
#		writedata => $data,
#		numread   => $numread,
#		delay     => $delay

    
    #-- ID of the device
    my $owx_rnf = substr($dev,3,12);
    my $owx_f   = substr($dev,0,2);

    #-- 8 byte 1-Wire device address
    my @rom_id  =(0,0,0,0 ,0,0,0,0); 
    #-- from search string to byte id
    $dev=~s/\.//g;
    for(my $i=0;$i<8;$i++){
       $rom_id[$i]=hex(substr($dev,2*$i,2));
    }
    $select=sprintf("\x55%c%c%c%c%c%c%c%c",@rom_id).$data; 
  #-- has no match ROM part, issue skip ROM command (0xCC:)
  } else {
    $select="\xCC".$data;
  }
  #-- has receive data part
  if( $numread >0 ){
    #$numread += length($data);
    for( my $i=0;$i<$numread;$i++){
      $select .= "\xFF";
    };
  }
  
  #-- for debugging
  if( $main::owx_async_debug > 1){
    main::Log3($self->{name},3,"OWX_SER::Execute: Sending out ".unpack ("H*",$select));
  }
  $self->block($select);
  
  PT_WAIT_UNTIL($self->response_ready());
  
  PT_EXIT if ($reset and !$self->reset_response());

  my $res = $self->{string_in};
  #-- for debugging
  if( $main::owx_async_debug > 1){
    main::Log3($self->{name},3,"OWX_SER::Execute: Receiving ".unpack ("H*",$res));
  }

  PT_EXIT($res);
  PT_END;
}

########################################################################################
#
# Discover - Find devices on the 1-Wire bus
#
# Parameter hash = hash of bus master
#
# Return 1, if alarmed devices found, 0 otherwise.
#
########################################################################################

sub pt_discover($) {
  my ($thread,$self) = @_;
  PT_BEGIN($thread);
  #-- Discover all alarmed devices on the 1-Wire bus
  $self->first("discover");
  do {
    $self->next("discover");
    PT_WAIT_UNTIL($self->response_ready());
    PT_EXIT unless $self->next_response("discover");
  } while( $self->{LastDeviceFlag}==0 );
  PT_EXIT($self->{devs});
  PT_END;
}

########################################################################################
# 
# Init - Initialize the 1-wire device
#
# Parameter hash = hash of bus master
#
# Return 1 or Errormessage : not OK
#        0 or undef : OK
#
########################################################################################

sub initialize($) {
  my ($self,$hash) = @_;
  my ($i,$j,$k,$l,$res,$ret,$ress);
  #-- Second step in case of serial device: open the serial device to test it
  my $msg = "OWX_SER: Serial device $hash->{DeviceName}";
  main::DevIo_OpenDev($hash,0,undef);
  my $hwdevice = $hash->{USBDev};
  if(!defined($hwdevice)){
    die $msg." not defined: $!";
  } else {
    main::Log3($hash->{NAME},1,$msg." defined");
  }

  $hwdevice->reset_error();
  $hwdevice->baudrate(9600);
  $hwdevice->databits(8);
  $hwdevice->parity('none');
  $hwdevice->stopbits(1);
  $hwdevice->handshake('none');
  $hwdevice->write_settings;
  #-- store with OWX device
  $self->{hwdevice}   = $hwdevice;

  #force master reset in DS2480
  $hwdevice->purge_all;
  $hwdevice->baudrate(4800);
  $hwdevice->write_settings;
  $hwdevice->write(sprintf("\x00"));
  select(undef,undef,undef,0.5);

  #-- Third step detect busmaster on serial interface
  
  my $name = $self->{name};
  my $ress0 = "OWX_SER::Detect 1-Wire bus $name: interface ";
  $ress     = $ress0;

  my $interface;
  
  require "$main::attr{global}{modpath}/FHEM/OWX_DS2480.pm";
  my $ds2480 = OWX_DS2480->new($self);
  
  #-- timing byte for DS2480
  $ds2480->start_query();
  $ds2480->query("\xC1",1);
  eval {   #ignore timeout
    do {
      $ds2480->read();
    } while (!$ds2480->response_ready());
  };
    
  #-- Max 4 tries to detect an interface
  for($l=0;$l<100;$l++) {
    #-- write 1-Wire bus (Fig. 2 of Maxim AN192)
    $ds2480->start_query();
    $ds2480->query("\x17\x45\x5B\x0F\x91",5);
    eval {   #ignore timeout
      do {
        $ds2480->read();
      } while (!$ds2480->response_ready());
    };
    $res = $ds2480->{string_in};
    #-- process 4/5-byte string for detection
    if( !defined($res)){
      $res="";
      $ret=1;
    }elsif( ($res eq "\x16\x44\x5A\x00\x90") || ($res eq "\x16\x44\x5A\x00\x93")){
      $ress .= "master DS2480 detected for the first time";
      $interface="DS2480";
      $ret=0;
    } elsif( $res eq "\x17\x45\x5B\x0F\x91"){
      $ress .= "master DS2480 re-detected";
      $interface="DS2480";
      $ret=0;
    } elsif( ($res eq "\x17\x0A\x5B\x0F\x02") || ($res eq "\x00\x17\x0A\x5B\x0F\x02") || ($res eq "\x30\xf8\x00") || ($res eq "\x06\x00\x09\x07\x80")){
      $ress .= "passive DS9097 detected";
      $interface="DS9097";
      $ret=0;
    } else {
      $ret=1;
    }
    last 
      if( $ret==0 );
    $ress .= "not found, answer was ";
    for($i=0;$i<length($res);$i++){
      $j=int(ord(substr($res,$i,1))/16);
      $k=ord(substr($res,$i,1))%16;
      $ress.=sprintf "0x%1x%1x ",$j,$k;
    }
    main::Log3($hash->{NAME},1, $ress);
    $ress = $ress0;
    #-- sleeping for some time
    select(undef,undef,undef,0.5);
  }
  if( $ret == 1 ){
    $interface=undef;
    $ress .= "not detected, answer was ";
    for($i=0;$i<length($res);$i++){
      $j=int(ord(substr($res,$i,1))/16);
      $k=ord(substr($res,$i,1))%16;
      $ress.=sprintf "0x%1x%1x ",$j,$k;
    }
  }
  $self->{interface} = $interface;
  main::Log3($hash->{NAME},1, $ress);
  if ($interface eq "DS2480") {
    return $ds2480;
  } elsif ($interface eq "DS9097") {
    require "$main::attr{global}{modpath}/FHEM/OWX_DS9097.pm";
    return OWX_DS9097->new($self);
  } else {
    die $ress;
  }
}

sub Disconnect($) {
	my ($self,$hash) = @_;
	main::DevIo_Disconnected($hash);
	delete $self->{hwdevice};
	$self->{interface} = "serial";
}

########################################################################################
#
# Verify - Verify a particular device on the 1-Wire bus
#
# Parameter hash = hash of bus master, dev =  8 Byte ROM ID of device to be tested
#
# Return 1 : device found
#        0 : device not
#
########################################################################################

sub pt_verify ($) {
  my ($thread,$self,$dev) = @_;
  my $i;
  PT_BEGIN($thread);  
  #-- from search string to byte id
  my $devs=$dev;
  $devs=~s/\.//g;
  for($i=0;$i<8;$i++){
    @{$self->{ROM_ID}}[$i]=hex(substr($devs,2*$i,2));
  }
  #-- reset the search state
  $self->{LastDiscrepancy} = 64;
  $self->{LastDeviceFlag} = 0;
  
  $self->reset();
  #-- now do the search
  $self->next("verify");
  PT_WAIT_UNTIL($self->response_ready());
  PT_EXIT unless $self->next_response("verify");
  
  my $dev2=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$self->{ROM_ID}});
  #-- reset the search state
  $self->{LastDiscrepancy} = 0;
  $self->{LastDeviceFlag} = 0;
  #-- check result
  if ($dev eq $dev2){
    PT_EXIT(1);
  }else{
    PT_EXIT;
  }
  PT_END;
}

#######################################################################################
#
# Private methods 
#
#######################################################################################
#
# First - Find the 'first' devices on the 1-Wire bus
#
# Parameter hash = hash of bus master, mode
#
# Return 1 : device found, ROM number pushed to list
#        0 : no device present
#
########################################################################################

sub first($) {
  my ($self) = @_;
  
  #-- clear 16 byte of search data
  @{$self->{search}} = (0,0,0,0 ,0,0,0,0, 0,0,0,0, 0,0,0,0);
  #-- reset the search state
  $self->{LastDiscrepancy} = 0;
  $self->{LastDeviceFlag} = 0;
  $self->{LastFamilyDiscrepancy} = 0;
}

#######################################################################################
#
# Search - Perform the 1-Wire Search Algorithm on the 1-Wire bus using the existing
#              search state.
#
# Parameter hash = hash of bus master, mode=alarm,discover or verify
#
# Return 1 : device found, ROM number in owx_ROM_ID and pushed to list (LastDeviceFlag=0) 
#                                     or only in owx_ROM_ID (LastDeviceFlag=1)
#        0 : device not found, or ot searched at all
#
########################################################################################

sub next($) {
  my ($self,$mode)=@_;
  
  #-- if the last call was the last one, no search 
  return undef if ( $self->{LastDeviceFlag} == 1 );
    
  #-- now do the search
  $self->search($mode);
}

sub next_response($) {
  my ($self,$mode) = @_;
  
  #TODO find out where contents of @owx_fams come from:
  my @owx_fams=();

  return undef unless $self->search_response();

  #-- character version of device ROM_ID, first byte = family 
  my $dev=sprintf("%02X.%02X%02X%02X%02X%02X%02X.%02X",@{$self->{ROM_ID}});

  #--check if we really found a device
  if( main::OWX_CRC($self->{ROM_ID})!= 0){
    #-- reset the search
    main::Log3($self->{name},1, "OWX_SER::Search CRC failed : $dev");
    $self->{LastDiscrepancy} = 0;
    $self->{LastDeviceFlag} = 0;
    $self->{LastFamilyDiscrepancy} = 0;
    die "OWX_SER::Search CRC failed : $dev";
  }
  
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
    main::Log3($self->{name},5, "OWX_SER::Search: device verified $dev");
  #-- mode was to discover devices
  } elsif( $mode eq "discover" ) {
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
    foreach (@{$self->{devs}}){
      if( $dev eq $_ ){        
        #-- if present, set the last device found flag
        $self->{LastDeviceFlag}=1;
        last;
      }
    }
    if( $self->{LastDeviceFlag}!=1 ){
      #-- push to list
      push(@{$self->{devs}},$dev);
      main::Log3($self->{name},5, "OWX_SER::Search: new device found $dev");
    }
  #-- mode was to discover alarm devices 
  } else {
    for(my $i=0;$i<@{$self->{alarmdevs}};$i++){
      if( $dev eq ${$self->{alarmdevs}}[$i] ){        
        #-- if present, set the last device found flag
        $self->{LastDeviceFlag}=1;
        last;
      }
    }
    if( $self->{LastDeviceFlag}!=1 ){
    #--push to list
      push(@{$self->{alarmdevs}},$dev);
      main::Log3($self->{name},5, "OWX_SER::Search: new alarm device found $dev");
    }
  }
  return 1;
}

1;

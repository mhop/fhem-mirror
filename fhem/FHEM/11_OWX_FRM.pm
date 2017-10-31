########################################################################################
#
# OWX_FRM.pm
#
# FHEM module providing hardware dependent functions for the FRM interface of OWX
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
# Read
# Ready
# Verify
# Write
# observer
# device_to_firmata
# firmata_to_device
#
########################################################################################

package OWX_FRM;

use strict;
use warnings;

use Data::Dumper;

use Device::Firmata::Constants qw/ :all /;

########################################################################################
# 
# Constructor
#
########################################################################################

sub new($) {
	my ($class,$hash) = @_;

	return bless {
		hash => $hash
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

  	if (!defined($main::modules{FRM})) {
  	  my $ret = "OWX_FRM::Define module FRM not yet loaded, please define an FRM device first."; 
  	  main::Log3 $hash->{NAME},1,$ret;
  	  return $ret;
  	}
  	
  	my @a = split( "[ \t][ \t]*", $def );
    my $u = "wrong syntax: define <name> OWX <firmata-device>:<firmata-pin>";
    return $u unless int(@a) > 0;
    
    my($fdev,$pin) = split(':',$a[2]);
    $self->{pin} = $pin;
    $self->{id}  = 0;
    $self->{name} = $hash->{NAME};
    $self->{hash} = $hash;
  	
  	#-- when the specified device name contains @<digits>, remove these.
    #my $dev =~ s/\@\d*//;
	#main::AssignIoPort($hash);
	  
	#-- store with OWX device
    #$hash->{DeviceName}   = $dev;
    $hash->{INTERFACE}    = "firmata";
    $hash->{HWDEVICE}     = $fdev;
    $hash->{PIN}          = $pin;
    $hash->{ASYNCHRONOUS} = 0;  
  
    #-- module version
	$hash->{version}      = "7.03";
    main::Log3 $hash->{NAME},1,"OWX_FRM::Define warning: version ".$hash->{version}." not identical to OWX version ".$main::owx_version
      if( $hash->{version} ne $main::owx_version);
   
    #-- call low level init function for the device
    main::InternalTimer(time()+55, "OWX_FRM::Init", $self,0);
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

  my $ret;
  my $name = $hash->{NAME};
  my $ress = "OWX: 1-Wire bus $name: interface ";

  my $iodev = $hash->{IODev};
  if (defined $iodev and defined $iodev->{FirmataDevice} and defined $iodev->{FD}) {  	
    $ret=1;
    $ress .= "Firmata detected in $iodev->{NAME}";
  } else {
	$ret=0;
	$ress .= defined $iodev ? "$iodev->{NAME} is not connected to Firmata" : "not associated to any FRM device";
  }
  main::Log(1, $ress);
  return $ret; 
}

########################################################################################
#
# Alarms - Find devices on the 1-Wire bus, which have the alarm flag set
#
# Return number of alarmed devices
#
########################################################################################

sub Alarms() {
	my ($self) = @_;
	my $hash = $self->{hash};

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );
	$hash->{ALARMDEVS} = undef;			
	$firmata->onewire_search_alarms($hash->{PIN});
	my $times = main::AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
	for (my $i=0;$i<$times;$i++) {
		if (main::FRM_poll($hash->{IODev})) {
			if (defined $hash->{ALARMDEVS}) {
				return 1;
			}
		} else {
			select (undef,undef,undef,0.05);
		}
	}
	$hash->{ALARMDEVS} = [];
	return 1;
}

########################################################################################
# 
# Init - Initialize the 1-wire device
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Init() {
  my ($self) = @_;
  my $hash   = $self->{hash};
  my $dev    = $hash->{DeviceName};
  my $name   = $hash->{NAME};
  my $pin    = $hash->{PIN};
  my $msg;
  
  main::Log 1,"==================> STARTING INIT of 11_OWX_FRM";
  
  my @args = ($pin);  
  $hash->{IODev} = $main::defs{$hash->{HWDEVICE}};
  my $ret = main::FRM_Init_Pin_Client($hash,\@args,PIN_ONEWIRE);
  if (defined $ret){
    $msg = "Error ".$ret;
    main::Log3 $name,1,"OWX_FRM::Init ".$msg;
    return $msg;
  }
  
  my $firmata = main::FRM_Client_FirmataDevice($hash);
		
  $hash->{FRM_OWX_CORRELATIONID} = 0;
  $firmata->observe_onewire($pin,\&observer,$hash);
		
  $hash->{FRM_OWX_REPLIES} = {};
  $hash->{DEVS} = [];
  if ( main::AttrVal($hash->{NAME},"buspower","") eq "parasitic" ) {
	$firmata->onewire_config($pin,1);
  }
	 
  $hash->{STATE}="Initialized";
  main::InternalTimer(main::gettimeofday()+10, "OWX_Discover", $hash,0);
  return undef;
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
	my ($self,$owx_dev,$data,$numread) =@_;
	
	my $hash = $self->{hash};
    my $name = $hash->{NAME};

	my $res = "";

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );

	my $ow_command = {};

	#-- has match ROM part
	if ($owx_dev) {
		$ow_command->{"select"} = device_to_firmata($owx_dev);

		#-- padding first 9 bytes into result string, since we have this
		#   in the serial interfaces as well
		$res .= "000000000";
	}

	#-- has data part
	if ($data) {
		my @data = unpack "C*", $data;
		$ow_command->{"write"} = \@data;
		$res.=$data;
	}
	
	#-- has receive part
    if ( $numread > 0 ) {
	  $ow_command->{"read"} = $numread;
	  #Firmata sends 0-address on read after skip
	  $owx_dev = '00.000000000000.00' unless defined $owx_dev;
	  my $id = $hash->{FRM_OWX_CORRELATIONID};
	  $ow_command->{"id"} = $hash->{FRM_OWX_CORRELATIONID};
	  $hash->{FRM_OWX_REQUESTS}->{$id} = {
		command => $ow_command,
		device => $owx_dev
	  };
	  delete $hash->{FRM_OWX_REPLIES}->{$owx_dev};		
		$hash->{FRM_OWX_CORRELATIONID} = ($id + 1) & 0xFFFF;
	}
	
	$firmata->onewire_command_series( $pin, $ow_command );
		
	if ($numread) {
	  my $times = main::AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
	  for (my $i=0;$i<$times;$i++) {
	    if (main::FRM_poll($hash->{IODev})) {
	  	  if (defined $hash->{FRM_OWX_REPLIES}->{$owx_dev}) {
		    $res .= $hash->{FRM_OWX_REPLIES}->{$owx_dev};
		    main::OWX_WDBGL($name,5,"OWX_FRM::Complex receiving inside loop no. $i ",$res);
		    return $res;
		  }
		} else {
		  select (undef,undef,undef,0.05);
		}
	  }
	}

	main::OWX_WDBGL($name,5,"OWX_FRM::Complex receiving outside loop ",$res);
	return $res;
}

########################################################################################
#
# Discover - Discover devices on the 1-Wire bus via internal firmware
#
# Parameter hash = hash of bus master
#
# Return 0  : error
#        1  : OK
#
########################################################################################

sub Discover ($) {

	my ($self) = @_;
	my $hash = $self->{hash};
	
	#main::Log 1,"======================> FRM Discover called";

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );
	my $old_devices = $hash->{DEVS};
	$hash->{DEVS} = undef;			
	my $res = $firmata->onewire_search($hash->{PIN});
	#main::Log 1,"=============> result from search is $res, iodev is ".$hash->{IODev};
	my $times = main::AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
    #main::Log 1,"===========> olddevices = $old_devices, tries =$times";
	for (my $i=0;$i<$times;$i++) {
		if (main::FRM_poll($hash->{IODev})) {
			if (defined $hash->{DEVS}) {
				return 1;
			}
		} else {
			select (undef,undef,undef,0.05);
		}
	}
	#main::Log 1,"===========> olddevices restored";
	$hash->{DEVS} = $old_devices;
	return 1;
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
  my $buffer   = $hash->{PREBUFFER};
  
  my $owx_dev = $hash->{FRM_OWX_CURRDEV};
   
  my $times = main::AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec

  #-- first read
  $buffer .= $hash->{FRM_OWX_REPLIES}->{$owx_dev};
  main::OWX_WDBGL($name,5,"OWX_FRM::Read receiving in first read ",$buffer);
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
  my $hash   = $self->{hash};
  my $name   = $hash->{NAME};
  my $success= 0;
  
  main::Log3 $name,1,"OWX_FRM::Ready function called for bus $name. STATE=".$hash->{STATE};

  return $success;
}

########################################################################################
# 
# Reset - Reset the 1-Wire bus 
#
# Parameter hash = hash of bus master
#
# Return 1 : OK
#        0 : not OK
#
########################################################################################

sub Reset() {
	my ($self) = @_;
	my $hash = $self->{hash};
	
	#-- get the interface
	my $frm = $hash->{IODev};
	return undef unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return undef unless ( defined $firmata and defined $pin );

	$firmata->onewire_reset($pin);
	
	return 1;
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

sub Verify($) {
	my ($self,$dev) = @_;
	my $hash = $self->{hash};
	foreach my $found ($hash->{DEVS}) {
		if ($dev eq $found) {
			return 1;
		}
	}
	return 0;
}

#######################################################################################
#
# Write - Implement the write function
#
#
# Parameter cmd   = string to be sent
#           reset = 1 if initial bus reset has to be done
#
########################################################################################

sub Write(@) {
  my ($self,$cmd, $reset) = @_;
  my $hash = $self->{hash};
  my $name = $hash->{NAME};
  
  my $res = "";

  #-- get the interface
  my $frm = $hash->{IODev};
  unless(defined $frm){
    main::Log3 $name,1,"OWX_FRM::Write attempted to undefined device $name";
    return 0 
  }
  
  my $firmata = $frm->{FirmataDevice};
  my $pin     = $hash->{PIN};
  unless ( defined $firmata and defined $pin ){ 
    main::Log3 $name,1,"OWX_FRM::Write attempted to ill-defined device $name";
    return 0 
  }
  
  #-- if necessary, perform a reset operation
  $self->Reset()
    if( $reset );
  
  main::OWX_WDBGL($name,5,"OWX_FRM::Write Sending out ",$cmd);
  
  my $cmd2    = $cmd;
  my $owx_dev ="";
  my $ow_command = {};
  
  #-- take away trailing 0xFF
  my $takeoff=0;
  my $tchar;
  for( my $i=length($cmd)-1; $i>=0; $i--){
    $tchar = substr($cmd,$i,1);
    if( ord($tchar) == 0xff ){
      $takeoff++;
    }else{
      last;
    }
  }
  
  $cmd2 = substr($cmd,0,length($cmd)-$takeoff);

  #-- has match ROM part - need to extract this
  $tchar = substr($cmd2,0,1);
  if( ord($tchar) == 0x55 ){
    #-- ID of the device. Careful, because hash is the hash of busmaster
    for(my $i=0;$i<8;$i++){
      my $j=int(ord(substr($cmd2,$i+1,1))/16);
      my $k=ord(substr($cmd,$i+1,1))%16;
      $owx_dev.=sprintf "%1x%1x",$j,$k;
      $owx_dev.="."
        if($i==0 || $i==6);
    }
    $owx_dev=uc($owx_dev);
    $cmd2 = substr($cmd2,9);
    $ow_command->{"select"} = device_to_firmata($owx_dev);

    #-- padding first 9 bytes into result string, since we have this
    #   in the serial interfaces as well
	$res .= "000000000";
  }

  #-- has data part
  if ($cmd2) {
    my @data = unpack "C*", $cmd2;
    $ow_command->{"write"} = \@data;
    $res.=$cmd2;
  }
  
  #-- pre-content of result buffer
  $hash->{PREBUFFER} = $res;
  
  #-- always receive part ??
  # if ( $numread > 0 ) {
  $ow_command->{"read"} = length($cmd);
    #Firmata sends 0-address on read after skip
      $owx_dev = '00.000000000000.00' unless defined $owx_dev;
	  my $id = $hash->{FRM_OWX_CORRELATIONID};
	  $ow_command->{"id"} = $hash->{FRM_OWX_CORRELATIONID};
	  $hash->{FRM_OWX_REQUESTS}->{$id} = {
		command => $ow_command,
		device => $owx_dev
	  };
	  delete $hash->{FRM_OWX_REPLIES}->{$owx_dev};		
		$hash->{FRM_OWX_CORRELATIONID} = ($id + 1) & 0xFFFF;
	#}
	
	$firmata->onewire_command_series( $pin, $ow_command );
	
}

#######################################################################################
#
# observer function for listening to the FRM device
#
#######################################################################################

sub observer
{
	my ( $data,$hash ) = @_;
	my $command = $data->{command};
	COMMAND_HANDLER: {
		$command eq "READ_REPLY" and do {
			my $id = $data->{id};
			my $request = (defined $id) ? $hash->{FRM_OWX_REQUESTS}->{$id} : undef;
			unless (defined $request) {
				return unless (defined $data->{device});
				my $owx_device = firmata_to_device($data->{device});
				my %requests = %{$hash->{FRM_OWX_REQUESTS}};
				foreach my $key (keys %requests) {
					if ($requests{$key}->{device} eq $owx_device) {
						$request = $requests{$key};
						$id = $key;
						last;
					};
				};
			};
			return unless (defined $request);
			my $owx_data = pack "C*",@{$data->{data}};
			my $owx_device = $request->{device};
			$hash->{FRM_OWX_REPLIES}->{$owx_device} = $owx_data;
			##
			$hash->{FRM_OWX_CURRDEV} = $owx_device;
			delete $hash->{FRM_OWX_REQUESTS}->{$id};
			
			return main::OWX_Read($hash);	
	
		};
		($command eq "SEARCH_REPLY" or $command eq "SEARCH_ALARMS_REPLY") and do {
			my @owx_devices = ();
			foreach my $device (@{$data->{devices}}) {
				push @owx_devices, firmata_to_device($device);
			}
			if ($command eq "SEARCH_REPLY") {
				$hash->{DEVS} = \@owx_devices;
				#$main::attr{$hash->{NAME}}{"ow-devices"} = join " ",@owx_devices;
			} else {
				$hash->{ALARMDEVS} = \@owx_devices;
			}
			last;
		};
	}
}

#######################################################################################
#
# translation of strings
#
#######################################################################################

sub device_to_firmata
{
  my @device;
  foreach my $hbyte ( unpack "A2xA2A2A2A2A2A2xA2", shift ) {
    push @device, hex $hbyte;
  }
  return {
    family   => shift @device,
    crc      => pop @device,
    identity => \@device,
  }
}

sub firmata_to_device
{
  my $device = shift;
  return sprintf( "%02X.%02X%02X%02X%02X%02X%02X.%02X", $device->{family}, @{ $device->{identity} }, $device->{crc} );
}

1;


=pod
=item helper
=item summary to address an OWX interface device via Arduino Firmata
=item summary_DE zur Adressierung eines OWX Interface Device mit Arduino Firmata
=begin html

<a name="OWX_FRM"></a>
<h3>OWX_FRM</h3>
See <a href="/fhem/docs/commandref.html#OWX">OWX</a>
end html
=begin html_DE

<a name="OWX_FRM"></a>
<h3>OWX_FRM</h3>
<a href="http://fhemwiki.de/wiki/Interfaces_f%C3%BCr_1-Wire">Deutsche Dokumentation im Wiki</a> vorhanden, die englische Version gibt es hier: <a href="/fhem/docs/commandref.html#OWX">OWX</a> 
=end html_DE
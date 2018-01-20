########################################################################################
#
# $Id$
#
# FHEM module to communicate with Firmata devices
#
########################################################################################
#
#  LICENSE AND COPYRIGHT
#
#  Copyright (C) 2013 ntruchess
#  Copyright (C) 2015 jensb
#
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
########################################################################################

package main;

use vars qw{%attr %defs}; 
use strict;
use warnings;
use GPUtils qw(:all);

#add FHEM/lib to @INC if it's not already included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

use Device::Firmata;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::Protocol;
use Device::Firmata::Platform;

sub FRM_Set($@);
sub FRM_Attr(@);

my %sets = (
  "reset" => "",
  "reinit" => ""
);

my %gets = (
  "firmware" => "",
  "version"   => ""
);

my @clients = qw(
  FRM_IN
  FRM_OUT
  FRM_AD
  FRM_PWM
  FRM_I2C
  FRM_SERVO
  FRM_RGB
  FRM_ROTENC
  FRM_STEPPER
  OWX
  OWX_ASYNC
  I2C_LCD
  I2C_DS1307
  I2C_PC.*
  I2C_MCP23.*
  I2C_SHT.*
  I2C_BME280
  I2C_BMP180
  I2C_BH1750
  I2C_TSL2561
  FRM_LCD
  I2C_K30
  I2C_LM.*
);

=item FRM_Initialize($)

  Returns:
    nothing
    
  Description:
    FHEM module initialization function ($hash is FRM)
    
=cut

sub FRM_Initialize($) {
	my $hash = shift @_;
	
	require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

	# Provider
	$hash->{Clients} = join (':',@clients);
	$hash->{ReadyFn} = "FRM_Ready";  
	$hash->{ReadFn}  = "FRM_Read";

	$hash->{I2CWrtFn} = "FRM_I2C_Write";

	$hash->{IOOpenFn}  = "FRM_Serial_Open";
	$hash->{IOWriteFn} = "FRM_Serial_Write";
	$hash->{IOCloseFn} = "FRM_Serial_Close";

	# Consumer
	$hash->{DefFn}    = "FRM_Define";
	$hash->{UndefFn}  = "FRM_Undef";
	$hash->{GetFn}    = "FRM_Get";
	$hash->{SetFn}    = "FRM_Set";
	$hash->{AttrFn}   = "FRM_Attr";
	$hash->{NotifyFn} = "FRM_Notify";

	$hash->{AttrList} = "model:nano dummy:1,0 sampling-interval i2c-config resetDeviceOnConnect:0,1 software-serial-config errorExclude disable:0,1 $main::readingFnAttributes";
}

=item FRM_Define($$)

  Returns:
    undef on success or error message
  
  Description:
    FHEM module DefFn ($hash is FRM)
    
=cut

sub FRM_Define($$) {
	my ( $hash, $def ) = @_;

	my ($name, $type, $dev, $global) = split("[ \t]+", $def);
	$hash->{DeviceName} = $dev;

	$hash->{NOTIFYDEV} = "global";

	if ( $dev eq "none" ) {
		Log3 $name,3,"device is none, commands will be echoed only";
		$main::attr{$name}{dummy} = 1;
	}
	if ($main::init_done && !AttrVal($name,'disable',0)) {
		return FRM_Start($hash);
	}
	readingsSingleUpdate($hash, 'state', 'defined', 1); 
	
	return undef;
}

=item FRM_Undef($)

  Returns:
    undef
    
  Description:
    FHEM module UndefFn ($hash is FRM)
    
=cut

sub FRM_Undef($) {
	my $hash = shift;
	FRM_forall_clients($hash,\&FRM_Client_Unassign,undef);
	if (defined $hash->{DeviceName}) {
		DevIo_Disconnected($hash);
	};
	TcpServer_Close($hash);
	foreach my $d ( sort keys %main::defs ) { # close and dispose open tcp-connection (if any) to free open filedescriptors
		if ( defined( my $dev = $main::defs{$d} )) {
			if ( defined( $main::defs{$d}{SNAME} )
				&& $main::defs{$d}{SNAME} eq $hash->{NAME}) {
					FRM_Tcp_Connection_Close($main::defs{$d});
				}
		}
	}

	FRM_FirmataDevice_Close($hash);

	FRM_ClearConfiguration($hash);

	return undef;
}

=item FRM_Start

  Returns:
    undef on success or error messages
    
  Description:
    FRM internal function ($hash is FRM)
    
=cut

sub FRM_Start {
	my ($hash) = @_;
	my $name  = $hash->{NAME};

	my ($dev, $global) = split("[ \t]+", $hash->{DEF});
	$hash->{DeviceName} = $dev;
	
	my $isServer = 1 if($dev && $dev =~ m/^(IPV6:)?\d+$/);
#	my $isClient = 1 if($dev && $dev =~ m/^(IPV6:)?.*:\d+$/);

#	return "Usage: define <name> FRM {<device>[@<baudrate>] | [IPV6:]<tcp-portnr> [global]}"
#		if(!($isServer || $isClient) ||
#			($isClient && $global) ||
#			($global && $global ne "global"));

	# clear old device ids to force full init
	FRM_ClearConfiguration($hash);

	# show version of perl-firmata driver
	$main::defs{$name}{DRIVER_VERSION} = $Device::Firmata::VERSION;

	# make sure that fhem only runs once
	if($isServer) {
		# set initial state  
		readingsSingleUpdate($hash, 'state', 'defined', 1);
  
		# start TCP server  
		my $ret = TcpServer_Open($hash, $dev, $global);
		if (!$ret) {
			readingsSingleUpdate($hash, 'state', 'listening', 1);
		}
		return $ret;
	}

	# close old DevIO (if any)
	DevIo_CloseDev($hash);
	readingsSingleUpdate($hash, 'state', 'defined', 1);
  
	# open DevIO  
	my $ret = DevIo_OpenDev($hash, 0, "FRM_DoInit");
	return $ret;
}

=item FRM_Notify

  Returns:
    nothing
    
  Description:
    FHEM module NotifyFn ($hash is FRM)
    
=cut

sub FRM_Notify {
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) && !AttrVal($name,'disable',0) ) {
  	FRM_Start($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

=item FRM_is_firmata_connected

  Returns:
    true if Firmata device and Firmata device IO are defined
    
  Description:
    FRM internal utility function($hash is FRM)
    
=cut

sub FRM_is_firmata_connected {
  my ($hash) = @_;
  return defined($hash->{FirmataDevice}) && defined ($hash->{FirmataDevice}->{io});
}

=item FRM_Set($@)

  Returns:
    undef or error message
    
  Description:
    FHEM module SetFn ($hash is FRM)
    
=cut

sub FRM_Set($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];

  COMMAND_HANDLER: {
    $command eq "reset" and do {
      return $hash->{NAME}." is not connected" unless (FRM_is_firmata_connected($hash) && (defined $hash->{FD} or ($^O=~/Win/ and defined $hash->{USBDev})));
      $hash->{FirmataDevice}->system_reset();
      FRM_ClearConfiguration($hash);
      if (defined $hash->{SERVERSOCKET}) {
        # dispose preexisting connections
        foreach my $e ( sort keys %main::defs ) {
          if ( defined( my $dev = $main::defs{$e} )) {
            if ( defined( $dev->{SNAME} ) && ( $dev->{SNAME} eq $hash->{NAME} )) {
              FRM_Tcp_Connection_Close($dev);
            }
          }
        }
        FRM_FirmataDevice_Close($hash);
        last;
      } else {
        DevIo_Disconnected($hash);
        FRM_FirmataDevice_Close($hash);
        return DevIo_OpenDev($hash, 0, "FRM_DoInit");
      }
    };
    $command eq "reinit" and do {
			FRM_forall_clients($hash,\&FRM_Init_Client,undef);
			last;
    };
	}
	return undef;
}

=item FRM_Get($@)

  Returns:
    requested data or error message
    
  Description:
    FHEM module GetFn ($hash is FRM)
    
=cut

sub FRM_Get($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "firmware" and do {
      if (FRM_is_firmata_connected($hash)) {
        return $hash->{FirmataDevice}->{metadata}->{firmware};
      } else {
        return "not connected to FirmataDevice";
      }
    };
    $cmd eq "version" and do {
      if (FRM_is_firmata_connected($hash)) {
        return $hash->{FirmataDevice}->{metadata}->{firmware_version};
      } else {
        return "not connected to FirmataDevice";
      }
    };
  }
}

=item FRM_Read($)

  Returns:
    nothing

  Description:
    FHEM module ReadFn, called by IODev of FRM ($hash is FRM, $chash is TCP client session)
    called from the global loop, when the select for hash->{FD} reports data

=cut

sub FRM_Read($) {
	my ( $hash ) = @_;
	if($hash->{SERVERSOCKET}) {   # Accept and create a child
		my $chash = TcpServer_Accept($hash, "FRM");
		return if(!$chash);
		$chash->{DeviceName}=$hash->{PORT}; # required for DevIo_CloseDev and FRM_Ready
		$chash->{TCPDev}=$chash->{CD};
		
		# dispose preexisting connections
		foreach my $e ( sort keys %main::defs ) {
			if ( defined( my $dev = $main::defs{$e} )) {
				if ( $dev != $chash && defined( $dev->{SNAME} ) && ( $dev->{SNAME} eq $chash->{SNAME} )) {
					FRM_Tcp_Connection_Close($dev);
				}
			}
		}
		FRM_FirmataDevice_Close($hash);
		FRM_DoInit($chash);
		return;
	}
	my $device = $hash->{FirmataDevice} or return;
	$device->poll();
	FRM_SetupDevice($hash);
}

=item FRM_Ready($)

  Returns:
    number of bytes waiting to be read or nothing on error

  Description:
    FHEM module RedyFn, called by IODev of FRM ($hash is IODev/master, $shash is FRM/slave)
    
=cut

sub FRM_Ready($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	if ($name=~/^^FRM:.+:\d+$/) { # this is a closed tcp-connection, remove it
		FRM_Tcp_Connection_Close($hash);
		FRM_FirmataDevice_Close($hash);
		return;
	}
  
	# reopen connection to DevIO if closed
	return DevIo_OpenDev($hash, 1, "FRM_DoInit") if($hash->{STATE} eq "disconnected");

	# This is relevant for windows/USB only
	my $po = $hash->{USBDev};
	my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
	if($po) {
		($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
	}
	return ($InBytes && $InBytes>0);
}

=item FRM_Tcp_Connection_Close($)

  Returns:
    undef

  Description:
    FRM internal function for IODev ($hash is IODev/master, $shash is FRM/slave)
    
=cut

sub FRM_Tcp_Connection_Close($) {
	my $hash = shift;
	TcpServer_Close($hash);
	if ($hash->{SNAME}) {
		my $shash = $main::defs{$hash->{SNAME}};
		readingsSingleUpdate($shash, 'state', 'listening', 1);
		if (defined $shash) {
			delete $shash->{SocketDevice} if (defined $shash->{SocketDevice});
		}
	}
	my $dev = $hash->{DeviceName};
	my $name = $hash->{NAME};
	if (defined $name) {
		delete $main::readyfnlist{"$name.$dev"} if (defined $dev);
		delete $main::attr{$name};
		delete $main::defs{$name};
	}
	return undef;
}

=item FRM_FirmataDevice_Close($)

  Returns:
    nothing

  Description:
    FRM internal function ($hash is FRM)
    
=cut

sub FRM_FirmataDevice_Close($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $device = $hash->{FirmataDevice};
	if (defined $device) {
		if (defined $device->{io}) {
			delete $hash->{FirmataDevice}->{io}->{handle} if defined $hash->{FirmataDevice}->{io}->{handle};
			delete $hash->{FirmataDevice}->{io};
		}
		delete $device->{protocol} if defined $device->{protocol};
		delete $hash->{FirmataDevice};
	}
}

=item FRM_Attr(@)

  Returns:
    nothing

  Description:
    FHEM module AttrFn ($hash is FRM)
    
=cut

sub FRM_Attr(@) {
	my ($command,$name,$attribute,$value) = @_;
	my $hash = $main::defs{$name};
	if ($command eq "set") {
		ARGUMENT_HANDLER: {
			($attribute eq "sampling-interval" or 
			 $attribute eq "i2c-config") and do {  
				$main::attr{$name}{$attribute}=$value;
				FRM_apply_attribute($main::defs{$name},$attribute);
				last;
			};
			$attribute eq "disable" and do {
				if ($main::init_done) {
					if ($value) {
						FRM_Undef($hash);
						readingsSingleUpdate($hash, 'state', 'disabled', 1);
					} else {
						FRM_Start($hash);
					}
				}
				last;
			};
		}
	}
}

=item FRM_apply_attribute()

  Returns:
    nothing

  Description:
    FRM internal function ($hash is FRM)
    
=cut

sub FRM_apply_attribute {
	my ($hash,$attribute) = @_;
	my $firmata = $hash->{FirmataDevice};
	my $name = $hash->{NAME};
	if (defined $firmata) {
		if ($attribute eq "sampling-interval") {
			$firmata->sampling_interval(AttrVal($name,$attribute,"1000"));
		} elsif ($attribute eq "i2c-config") {
			my $i2cattr = AttrVal($name,$attribute,undef);
			if (defined $i2cattr) {
				my @a = split(" ", $i2cattr);
				my $i2cpins = $firmata->{metadata}{i2c_pins};
				my $err; 
				if (defined $i2cpins and scalar @$i2cpins) {
					eval {
						foreach my $i2cpin (@$i2cpins) {
							$firmata->pin_mode($i2cpin,PIN_I2C);
						}
						$firmata->i2c_config(@a);
						$firmata->observe_i2c(\&FRM_i2c_observer,$hash);
					};
					$err = $@ if ($@);	
				} else {
					$err = "Error, arduino doesn't support I2C";
				}
				Log3 $name,2,$err if ($err);
			}
		}
	}
}

=item FRM_DoInit($)

  Returns:
    undef on success or 1 if Firmata platform attach fails

  Description:
    FRM internal function for IODev ($hash is IODev/master or FRM, $shash is FRM/slave)
    try to reset Firmata device and start Firmata device initialization
    
=cut

sub FRM_DoInit($) {
  my ($hash) = @_;

  my $sname = $hash->{SNAME}; #is this a serversocket-connection?
  my $shash = defined $sname ? $main::defs{$sname} : $hash;
  my $name = $shash->{NAME};

  Log3 $name, 5, "$name FRM_DoInit";
  readingsSingleUpdate($shash, 'state', "connected", 1);
  
  my $firmata_io = Firmata_IO->new($hash, $name);
  my $device = Device::Firmata::Platform->attach($firmata_io) or return 1;

  $shash->{FirmataDevice} = $device;
  if (defined $sname) {
    $shash->{SocketDevice} = $hash;
    #as FRM_Read gets the connected socket hash, but calls firmatadevice->poll():
    $hash->{FirmataDevice} = $device;
  }
  $device->observe_string(\&FRM_string_observer, $shash);
  
  if (AttrVal($name, 'resetDeviceOnConnect', 1)) {
    $device->system_reset();
    FRM_ClearConfiguration($shash);
  }    
  
  $shash->{SETUP_START} = gettimeofday();
  $shash->{SETUP_STAGE} = 1; # detect connect mode (fhem startup, device startup or device reconnect) and query versions
  $shash->{SETUP_TRIES} = 1;  
  
  return FRM_SetupDevice($shash);
}

=item FRM_ClearConfiguration()

  Returns:    
    nothing

  Description: 
    FRM internal function ($hash is FRM)
    delete all version and capability readings
  
=cut

sub FRM_ClearConfiguration($) {
	my $hash = shift;
	my $name = $hash->{NAME};

	delete $main::defs{$name}{protocol_version};
	delete $main::defs{$name}{firmware};
	delete $main::defs{$name}{firmware_version};

	delete $main::defs{$name}{input_pins};
	delete $main::defs{$name}{output_pins};
	delete $main::defs{$name}{analog_pins};
	delete $main::defs{$name}{pwm_pins};
	delete $main::defs{$name}{servo_pins};
	delete $main::defs{$name}{i2c_pins};
	delete $main::defs{$name}{onewire_pins};
	delete $main::defs{$name}{stepper_pins};
	delete $main::defs{$name}{encoder_pins};
	delete $main::defs{$name}{serial_pins};
	delete $main::defs{$name}{pullup_pins};

	delete $main::defs{$name}{analog_resolutions};
	delete $main::defs{$name}{pwm_resolutions};
	delete $main::defs{$name}{servo_resolutions};
	delete $main::defs{$name}{encoder_resolutions};
	delete $main::defs{$name}{stepper_resolutions};
	delete $main::defs{$name}{serial_ports};
}

=item FRM_SetupDevice()

  Returns:
    undef 

  Description: 
    FRM internal function ($hash is IODev/master or FRM)
    Monitor data received from Firmata device immediately after connect, perform
    protocol, firmware and capability queries and configure device according to 
    the FRM device attributes.
  
=cut

sub FRM_SetupDevice($);

sub FRM_SetupDevice($) {
  my ($hash) = @_;  
  if (defined($hash->{SNAME})) {
    $hash = $main::defs{$hash->{SNAME}};
  }
  
  return undef if (!defined($hash->{SETUP_START}));
  
  my $name = $hash->{NAME};
  
  Log3 $name, 5, "$name setup stage $hash->{SETUP_STAGE}";
  
  my $now = gettimeofday();
  my $elapsed = $now - $hash->{SETUP_START};
  my $device = $hash->{FirmataDevice};

  if ($hash->{SETUP_STAGE} == 1) { # protocol and firmware version
    RemoveInternalTimer($hash);
    InternalTimer($now + (($elapsed < 1)? 0.1 : 1), 'FRM_SetupDevice', $hash, 0);    
    # wait for protocol and firmware version
    my $fhemRestart = !defined($main::defs{$name}{protocol_version});
    my $versionsReceived = $device->{metadata}{firmware} && $device->{metadata}{firmware_version} && $device->{metadata}{protocol_version};
    if ($versionsReceived) {
      # clear old version and capability readings if not already done
      if (!$fhemRestart) {
        FRM_ClearConfiguration($hash);
      }
      # protocol and firmware versions have been received
      $main::defs{$name}{firmware} = $device->{metadata}{firmware};
      $main::defs{$name}{firmware_version} = $device->{metadata}{firmware_version};
      $main::defs{$name}{protocol_version} = $device->{protocol}->get_max_supported_protocol_version($device->{metadata}{protocol_version});
      Log3 $name, 3, $name." Firmata Firmware Version: ".$device->{metadata}{firmware}." ".$device->{metadata}{firmware_version}." (using Protocol Version: ".$main::defs{$name}{protocol_version}.")";        
      # query capabilities
      $device->analog_mapping_query();
      $device->capability_query();
      # wait for capabilities
      $hash->{SETUP_STAGE} = 2;
    } elsif ($elapsed >= 3) {
      # protocol and firmware version still missing
      if ($hash->{SETUP_TRIES} < 3) {
        # requery versions
        Log3 $name, 3, "$name querying Firmata versions";
        $device->protocol_version_query();
        $device->firmware_version_query();
        # restart setup
        $hash->{SETUP_START} = gettimeofday();
        $hash->{SETUP_STAGE} = 1;
        $hash->{SETUP_TRIES}++;
      } else {
        # retry limit exceeded, abort
        $hash->{SETUP_STAGE} = 4; 
        FRM_SetupDevice($hash);
      }
    } elsif ($elapsed >= 0.2 && defined($hash->{PORT})) {
      # if we don't receive the protocol version within 200 millis, the device has reconnected (or has an old firmware)
      my $deviceRestart = $device->{metadata}{protocol_version};
      if (!$deviceRestart && !$fhemRestart) {
        # probably a reconnect
        Log3 $name, 3, "$name Firmata device has reconnected";
        #if ($skipSetupOnReconnect) {
        #  # skip capability queries and device setup, just reinit client modules
        #  $hash->{SETUP_STAGE} = 3;
        #  FRM_SetupDevice($hash);
        #  return undef;
        #}
        # clear old version and capability readings
        FRM_ClearConfiguration($hash);
        # query versions
        Log3 $name, 3, "$name querying Firmata versions";
        $device->protocol_version_query();
        $device->firmware_version_query();
      } 
    }
    
  } elsif  ($hash->{SETUP_STAGE} == 2) { # device capabilities
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + 1, 'FRM_SetupDevice', $hash, 0);    
    my $capabilitiesReceived = $device->{metadata}{capabilities} && ($device->{metadata}{analog_mappings} || ($elapsed >= 5));
    if ($capabilitiesReceived) {
      # device capabilities have been received, convert to readings
      my $inputpins = $device->{metadata}{input_pins};
      $main::defs{$name}{input_pins} = join(",", sort{$a<=>$b}(@$inputpins)) if (defined $inputpins and scalar @$inputpins);
      my $outputpins = $device->{metadata}{output_pins};
      $main::defs{$name}{output_pins} =  join(",", sort{$a<=>$b}(@$outputpins)) if (defined $outputpins and scalar @$outputpins);
      my $analogpins = $device->{metadata}{analog_pins};
      $main::defs{$name}{analog_pins} = join(",", sort{$a<=>$b}(@$analogpins)) if (defined $analogpins and scalar @$analogpins);
      my $pwmpins = $device->{metadata}{pwm_pins};
      $main::defs{$name}{pwm_pins} = join(",", sort{$a<=>$b}(@$pwmpins)) if (defined $pwmpins and scalar @$pwmpins);
      my $servopins = $device->{metadata}{servo_pins};
      $main::defs{$name}{servo_pins} = join(",", sort{$a<=>$b}(@$servopins)) if (defined $servopins and scalar @$servopins);
      my $i2cpins = $device->{metadata}{i2c_pins};
      $main::defs{$name}{i2c_pins} = join(",", sort{$a<=>$b}(@$i2cpins)) if (defined $i2cpins and scalar @$i2cpins);
      my $onewirepins = $device->{metadata}{onewire_pins};
      $main::defs{$name}{onewire_pins} = join(",", sort{$a<=>$b}(@$onewirepins)) if (defined $onewirepins and scalar @$onewirepins);
      my $stepperpins = $device->{metadata}{stepper_pins};
      $main::defs{$name}{stepper_pins} = join(",", sort{$a<=>$b}(@$stepperpins)) if (defined $stepperpins and scalar @$stepperpins);
      my $encoderpins = $device->{metadata}{encoder_pins};
      $main::defs{$name}{encoder_pins} = join(",", sort{$a<=>$b}(@$encoderpins)) if (defined $encoderpins and scalar @$encoderpins);
      my $serialpins = $device->{metadata}{serial_pins};
      $main::defs{$name}{serial_pins} = join(",", sort{$a<=>$b}(@$serialpins)) if (defined $serialpins and scalar @$serialpins);
      my $pulluppins = $device->{metadata}{pullup_pins};
      $main::defs{$name}{pullup_pins} = join(",", sort{$a<=>$b}(@$pulluppins)) if (defined $pulluppins and scalar @$pulluppins);
      if (defined $device->{metadata}{analog_resolutions}) {
        my @analog_resolutions;
        foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{analog_resolutions}})) {
          push @analog_resolutions,$pin.":".$device->{metadata}{analog_resolutions}{$pin};
        }
        $main::defs{$name}{analog_resolutions} = join(",",@analog_resolutions) if (scalar @analog_resolutions);
      }
      if (defined $device->{metadata}{pwm_resolutions}) {
        my @pwm_resolutions;
        foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{pwm_resolutions}})) {
          push @pwm_resolutions,$pin.":".$device->{metadata}{pwm_resolutions}{$pin};
        }
        $main::defs{$name}{pwm_resolutions} = join(",",@pwm_resolutions) if (scalar @pwm_resolutions);
      }
      if (defined $device->{metadata}{servo_resolutions}) {
        my @servo_resolutions;
        foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{servo_resolutions}})) {
          push @servo_resolutions,$pin.":".$device->{metadata}{servo_resolutions}{$pin};
        }
        $main::defs{$name}{servo_resolutions} = join(",",@servo_resolutions) if (scalar @servo_resolutions);
      }
      if (defined $device->{metadata}{encoder_resolutions}) {
        my @encoder_resolutions;
        foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{encoder_resolutions}})) {
          push @encoder_resolutions,$pin.":".$device->{metadata}{encoder_resolutions}{$pin};
        }
        $main::defs{$name}{encoder_resolutions} = join(",",@encoder_resolutions) if (scalar @encoder_resolutions);
      }
      if (defined $device->{metadata}{stepper_resolutions}) {
        my @stepper_resolutions;
        foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{stepper_resolutions}})) {
          push @stepper_resolutions,$pin.":".$device->{metadata}{stepper_resolutions}{$pin};
        }
        $main::defs{$name}{stepper_resolutions} = join(",",@stepper_resolutions) if (scalar @stepper_resolutions);
      }
      if (defined $device->{metadata}{serial_resolutions}) {
        my @serial_ports;
        foreach my $pin (sort{$a<=>$b}(keys %{$device->{metadata}{serial_resolutions}})) {
          push @serial_ports,$pin.":".int($device->{metadata}{serial_resolutions}{$pin}/2);
        }
        $main::defs{$name}{serial_ports} = join(",",@serial_ports) if (scalar @serial_ports);
      }
      # setup device
      FRM_apply_attribute($hash, "sampling-interval");
      FRM_apply_attribute($hash, "i2c-config");
      FRM_serial_setup($hash);            
      # ready, init client modules 
      $hash->{SETUP_STAGE} = 3; 
      FRM_SetupDevice($hash); 
    } elsif ($elapsed >= 5) {
      # capabilities receive timeout, abort
      $hash->{SETUP_STAGE} = 4; 
      FRM_SetupDevice($hash);
    }
    
  } elsif  ($hash->{SETUP_STAGE} == 3) { # client modules
    # client module initialization
    FRM_forall_clients($hash, \&FRM_Init_Client, undef);
    readingsSingleUpdate($hash, 'state', "Initialized", 1);
    # done, terminate setup sequence
    $hash->{SETUP_STAGE} = 5; 
    FRM_SetupDevice($hash);
    
  } elsif  ($hash->{SETUP_STAGE} == 4) { # abort setup
    # device setup has failed, cleanup connection
    if (defined $hash->{SERVERSOCKET}) {
      Log3 $name, 3, "$name no response from Firmata, closing TCP connection";
      foreach my $e (sort keys %main::defs) {
        if (defined(my $dev = $main::defs{$e})) {
          if (defined($dev->{SNAME}) && ($dev->{SNAME} eq $hash->{NAME})) {
            FRM_Tcp_Connection_Close($dev);
          }
        }
      }
    } else {
      Log3 $name, 3, "$name no response from Firmata, closing DevIo";
      DevIo_Disconnected($hash);
    }
    FRM_FirmataDevice_Close($hash);
    # cleanup setup
    $hash->{SETUP_STAGE} = 5; 
    FRM_SetupDevice($hash);
    
  } elsif ($hash->{SETUP_STAGE} == 5) { # finish setup
    # terminate setup sequence
    RemoveInternalTimer($hash);
    delete $hash->{SETUP_START};
    delete $hash->{SETUP_STAGE};
    delete $hash->{SETUP_TRIES};
    
  } else { 
    # invalid state, abort
    $hash->{SETUP_STAGE} = 4; 
    FRM_SetupDevice($hash);  
  }

  return undef;
}

=item FRM_forall_clients($$$)

  Returns:
    undef

  Description: 
    FRM internal function ($hash is FRM)
    Call a function $1 with arguments $2 for all FHEM devices that use device $0 as IODev.
    
=cut

sub
FRM_forall_clients($$$) {
  my ($hash,$fn,$args) = @_;
  foreach my $d ( sort keys %main::defs ) {
    if (   defined( $main::defs{$d} )
      && defined( $main::defs{$d}{IODev} )
      && $main::defs{$d}{IODev} == $hash ) {
      	&$fn($main::defs{$d},$args);
    }
  }
  return undef;
}

=item FRM_Init_Client($@)

  Exception: 
    if calling InitFn of client $0 raises an exception
 
  Description: 
    FRM public client function ($chash is FRM client)
    trigger InitFn of FRM client, typically called after initialization of connection to Firmata device
    
=cut

sub
FRM_Init_Client($@) {
	my ($chash,$args) = @_;
	if (!defined $args and defined $chash->{DEF}) {
		my @a = split("[ \t][ \t]*", $chash->{DEF});
		$args = \@a;
	}
	my $cname = $chash->{NAME};
	my $iodev = defined($chash->{IODev})? $chash->{IODev}{NAME} : "?";
	Log3 $iodev, 5, "$iodev initializing '$cname'";
  if (!defined($main::modules{$main::defs{$cname}{TYPE}}{InitFn})) {
    Log3 $iodev, 5, "$iodev error initializing '$cname': InitFn not implemented";
  }
	my $ret = CallFn($cname,"InitFn",$chash,$args);
	if ($ret) {
		Log3 $iodev,2,"$iodev error initializing '$cname': $ret";
	}
}

=item FRM_Init_Pin_Client($$$)

  Returns:
    undef on success or error message

  Exception: 
    if calling InitFn of client $0 raises an exception
 
  Description: 
    FRM public client function ($chash is FRM client)
    register FRM client at IODev for I/O operations and set requested pin mode in Firmata device
    
=cut

sub
FRM_Init_Pin_Client($$$) {
	my ($chash,$args,$mode) = @_;
	my $u = "wrong syntax: define <name> FRM_XXX pin";
	return $u unless defined $args and int(@$args) > 0;
	my $pin = @$args[0];

	$chash->{PIN} = $pin;
	eval {
		FRM_Client_AssignIOPort($chash);
		FRM_Client_FirmataDevice($chash)->pin_mode($pin,$mode);
	};
	if ($@) {
		readingsSingleUpdate($chash, 'state', "error initializing: pin $pin", 1);
		$@ =~ /^(.*)( at.*FHEM.*)$/;
		return $1;
	}
	my $name = $chash->{NAME};
	my $iodev = defined($chash->{IODev})? $chash->{IODev}{NAME} : "?";
	Log3 $name, 5, "$name initialized pin $pin of $iodev";
	return undef;
}

=item FRM_Client_Define($$)

  Returns:
    undef on success or error message

  Exception: 
    if calling InitFn of client $0 raises an exception
 
  Description: 
    FRM public client function ($chash is FRM client)
    trigger InitFn of FRM client
    
=cut

sub
FRM_Client_Define($$) {
  my ($chash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  readingsSingleUpdate($chash, 'state', 'defined', 1);
  
  if ($main::init_done) {
    eval {
      FRM_Init_Client($chash,[@a[2..scalar(@a)-1]]);
    };
    if ($@) {
      $@ =~ /^(.*)( at.*FHEM.*)$/;
      return $1;
    }
  }
  return undef;
}

=item FRM_Client_Undef($$)

  Returns:
    undef

  Description: 
    FRM public client function ($chash is FRM client)
    try to set pin mode to analog input if supported or to digital input
    
=cut

sub
FRM_Client_Undef($$) {
  my ($chash, $name) = @_;
  my $pin = $chash->{PIN};
  eval {
    my $firmata = FRM_Client_FirmataDevice($chash);
    $firmata->pin_mode($pin,PIN_ANALOG);
  };
  if ($@) {
    eval {
      my $firmata = FRM_Client_FirmataDevice($chash);
      $firmata->pin_mode($pin,PIN_INPUT);
      # @TODO PIN_PULLUP
      $firmata->digital_write($pin,0);
    };
  }
  return undef;
}

=item FRM_Client_Unassign($)

  Description: 
    FRM internal function ($chash FRM client)
    remove IODev assignment from FRM client device
    
=cut

sub
FRM_Client_Unassign($) {
  my ($chash) = @_;
  delete $chash->{IODev} if defined $chash->{IODev};
  readingsSingleUpdate($chash, 'state', 'defined', 1);
}

=item FRM_Client_AssignIOPort($$)

  Exception: 
    if IODev of of client $0 is still undefined after returning from AssignIoPort() or
    if another client is already assigned to the same PIN as client
 
  Description: 
    FRM public client function ($chash is FRM client)
    
=cut

sub
FRM_Client_AssignIOPort($@) {
	my ($chash,$iodev) = @_;
	my $name = $chash->{NAME};

	# use proposed $iodev or assigned {IODev} (FHEM will additionally check IODev attribute if not defined)
	$iodev = defined($iodev)? $iodev : (defined($chash->{IODev})? $chash->{IODev}{NAME} : undef);
	Log3 $name, 5, "$name FRM_Client_AssignIOPort before IODev " . (defined($chash->{IODev})? $chash->{IODev}{NAME} : "-" ) . " -> " . (defined($iodev)? $iodev : "?");
	AssignIoPort($chash, $iodev);
	die "unable to assign IODev to '$name'" unless defined ($chash->{IODev});
	Log3 $name, 5, "$name FRM_Client_AssignIOPort after IODev $chash->{IODev}{NAME}";

	if (defined($chash->{IODev}->{SNAME})) {
		$chash->{IODev} = $main::defs{$chash->{IODev}->{SNAME}};
		$attr{$name}{IODev} = $chash->{IODev}{NAME};
	}

	foreach my $d ( sort keys %main::defs ) {
		if ( defined( my $dev = $main::defs{$d} )) {
			if ( $dev != $chash
				&& defined( $dev->{IODev} )
				&& defined( $dev->{PIN} )
				&& $dev->{IODev} == $chash->{IODev}
				&& defined( $chash->{PIN})
				&& grep {$_ == $chash->{PIN}} split(" ",$dev->{PIN}) ) {
				  delete $chash->{IODev};
				  delete $attr{$name}{IODev};
					die "Device '$main::defs{$d}{NAME}' already defined for pin $chash->{PIN}";
				}
		}
	}
}

=item FRM_Client_FirmataDevice($)

  Returns:
    perl-firmata handle for given FRM client

  Exception: 
    if IODev is not defined or not connected
 
  Description: 
    FRM public client function ($chash is FRM client, $iodev is FRM)
    
=cut

sub FRM_Client_FirmataDevice($) {
  my $chash = shift;
  my $iodev = $chash->{IODev};
  die $chash->{NAME}." no IODev assigned" unless defined $iodev;
  die $chash->{NAME}.", ".$iodev->{NAME}." is not connected" unless (defined $iodev->{FirmataDevice} and (defined $iodev->{FD} or ($^O=~/Win/ and defined $iodev->{USBDev})));
  return $iodev->{FirmataDevice};
}

=item FRM_Catch($)

  Returns: 
    undef or exception message if parameter $0 is a FHEM stack trace
 
  Description: 
    FRM public utility function
    
=cut

sub FRM_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

=item Firmata_IO

  Description: 
    FRM internal wrapper class to provide perl-firmata compatible read and write methods
    
=cut

package Firmata_IO;

sub new($$) {
  my ($class,$hash,$name) = @_;
  return bless {
    hash => $hash,
    name => $name,
  }, $class;
}

sub data_write {
  my ( $self, $buf ) = @_;
  my $hash = $self->{hash};
  main::Log3 $self->{name},5,"$self->{name} FRM:>".unpack "H*",$buf;
  main::DevIo_SimpleWrite($hash,$buf,undef);
}

sub data_read {
  my ( $self, $bytes ) = @_;
  my $hash = $self->{hash};
  my $string = main::DevIo_SimpleRead($hash);
  if (defined $string ) {
    main::Log3 $self->{name},5,"$self->{name} FRM:<".unpack "H*",$string;
  }
  return $string;
}

package main;

=item FRM_I2C_Write

# im master muss eine I2CWrtFn definiert werden, diese wird vom client mit
# CallFn(<mastername>, "I2CWrtFn", <masterhash>, \%sendpackage);
# aufgerufen.
# Der Master muss mit AssignIoPort() dem Client zugeordnet werden;
# %sendpackage muss folgende keys enthalten:
#
#    i2caddress => <xx>
#    direction => <i2cwrite|i2cread>
#    data => <xx [xx ...] (kann für read leer bleiben)>
#
# der Master fügt zu %sendpackage noch folgende keys hinzu:
#
#    received (durch leerzeichen getrennte 1byte hexwerte)
#    mastername_* (alle mit mastername_  beginnenden keys können als internal im client angelegt weden)
#    unter anderem: mastername_SENDSTAT (enthält "Ok" wenn Übertragung erfolgreich)
#
# danach ruft er über:
# CallFn(<clientname>, "I2CRecFn", <clienthash>, $sendpackage);
# die I2CRecFn im client auf. Dort werden die Daten verarbeitet und
# im Master wird der Hash sendpackage gelöscht.
#
#		$package->{i2caddress}; # single byte value
#		$package->{direction}; # i2cread|i2cwrite
#		$package->{data}; # space separated list of values
#		$package->{reg}; # register
#		$package->{nbyte}; # number of bytes to read
#		
#		$firmata->i2c_read($address,$register,$bytestoread);
#		$firmata->i2c_write($address,@data);

  Description:
    FHEM module I2CWrtFn ($hash is FRM)
    
=cut

sub FRM_I2C_Write
{
  my ($hash,$package)  = @_;

  if (FRM_is_firmata_connected($hash) && defined($package) && defined($package->{i2caddress})) {
    my $firmata = $hash->{FirmataDevice};
    COMMANDHANDLER: {
      $package->{direction} eq "i2cwrite" and do {
        if (defined $package->{reg}) {
          $firmata->i2c_write($package->{i2caddress},$package->{reg},split(" ",$package->{data}));
        } else {
          $firmata->i2c_write($package->{i2caddress},split(" ",$package->{data}));
        }
        last;
      };
      $package->{direction} eq "i2cread" and do {
        delete $hash->{I2C_ERROR};
        if (defined $package->{reg}) {
          $firmata->i2c_readonce($package->{i2caddress},$package->{reg},defined $package->{nbyte} ? $package->{nbyte} : 1);
        } else {
          $firmata->i2c_readonce($package->{i2caddress},defined $package->{nbyte} ? $package->{nbyte} : 1);
        }
        last;
      };
    }
  }
}

=item FRM_i2c_observer

  Returns:
    nothing

  Description:
    FRM internal Firmata device receive callback ($hash is FRM)
    
=cut 

sub FRM_i2c_observer {
	my ($data,$hash) = @_;
	Log3 $hash->{NAME},5,"onI2CMessage address: '".$data->{address}."', register: '".$data->{register}."' data: [".(join(',',@{$data->{data}}))."]";
	FRM_forall_clients($hash,\&FRM_i2c_update_device,$data);
}

=item FRM_i2c_update_device

  Returns:
    nothing

  Description:
    FRM internal receive bridge for I2C receive from Firmata device to FRM I2C client ($chash is FRM client that called FRM_I2C_Write)
    If I2C address of FRM client matches, the received data  is passed on.
    
=cut 

sub FRM_i2c_update_device {
	my ($chash,$data) = @_;
	
	if (defined $chash->{I2C_Address} and $chash->{I2C_Address} eq $data->{address}) {
		my $sendStat = "Ok";
		if (defined($chash->{IODev}->{I2C_ERROR})) {
			$sendStat = $chash->{IODev}->{I2C_ERROR};
		}
		CallFn($chash->{NAME}, "I2CRecFn", $chash, {
			i2caddress => $data->{address},
			direction  => "i2cread",
			reg        => $data->{register},
			nbyte      => scalar(@{$data->{data}}),
			received   => join (' ',@{$data->{data}}),
			$chash->{IODev}->{NAME}."_SENDSTAT" => $sendStat,
		});
	} elsif (defined $chash->{"i2c-address"} && $chash->{"i2c-address"}==$data->{address}) {
		my $replydata = $data->{data};
		my @values = split(" ",ReadingsVal($chash->{NAME},"values",""));
		splice(@values,$data->{register},@$replydata, @$replydata);
		readingsBeginUpdate($chash);
		$chash->{STATE}="active";
		readingsBulkUpdate($chash,"values",join (" ",@values),1);
		readingsEndUpdate($chash,1);
	}
}

=item FRM_string_observer

  Returns:
    nothing

  Description:
    FRM internal Firmata device receive callback ($hash is FRM)
    
=cut 

sub FRM_string_observer {
	my ($string,$hash) = @_;
	my $errorExclude = AttrVal($hash->{NAME}, "errorExclude", undef);
	if (defined($errorExclude) && length($errorExclude) > 0 && ($string =~ $errorExclude)) {
		Log3 $hash->{NAME},5,"received String_data: ".$string;
		readingsSingleUpdate($hash,"stringMessage",$string,1);
	} else {
		Log3 $hash->{NAME},3,"received String_data: ".$string;
		readingsSingleUpdate($hash,"error",$string,1);
		if ($string =~ "I2C.*") {
			$hash->{I2C_ERROR} = substr($string, 5);
		}
	}
}

=item FRM_serial_observer

  Returns:
    nothing

  Description:
    FRM internal Firmata device receive callback ($hash is FRM)
    
=cut 

sub FRM_serial_observer {
	my ($data,$hash) = @_;
	#Log3 $hash->{NAME},5,"onSerialMessage port: '".$data->{port}."' data: [".(join(',',@{$data->{data}}))."]";
	FRM_forall_clients($hash,\&FRM_serial_update_device,$data);
}

=item FRM_serial_update_device

  Returns:
    nothing

  Description:
    FRM internal receive bridge for serial receive from Firmata device to FRM serial client ($chash is FRM client)
    If IODevPort of FRM client matches, the received data  is passed on.
    
=cut 

sub FRM_serial_update_device {
	my ($chash,$data) = @_;
	
	if (defined $chash->{IODevPort} and $chash->{IODevPort} eq $data->{port}) {
		my $buf = pack("C*", @{$data->{data}});
		#Log3 $chash->{NAME},5,"FRM_serial_update_device port: " . length($buf) . " bytes on serial port " . $data->{port} . " for " . $chash->{NAME};
		$chash->{IODevRxBuffer} = "" if (!defined($chash->{IODevRxBuffer}));
		$chash->{IODevRxBuffer} = $chash->{IODevRxBuffer} . $buf;
		CallFn($chash->{NAME}, "ReadFn", $chash);
	}
}

=item FRM_serial_setup

  Returns:
    nothing

  Description:
    FRM internal function ($hash is FRM, $chash is FRM client)
    
=cut 

sub FRM_serial_setup {
	my ($hash) = @_;

	foreach my $port ( keys %{$hash->{SERIAL}} ) {
		my $chash = $defs{$hash->{SERIAL}{$port}};
		if (defined($chash)) {
			FRM_Serial_Setup($chash);
		}
	}
}

=item FRM_poll

  Returns:
    true if something was read from the Firmata device or nothing

  Description:
    FRM public function ($hash is FRM)
    
=cut 

sub FRM_poll {
	my ($hash) = @_;
	if (defined $hash->{SocketDevice} and defined $hash->{SocketDevice}->{FD}) {
		my ($rout, $rin) = ('', '');
		vec($rin, $hash->{SocketDevice}->{FD}, 1) = 1;
		my $nfound = select($rout=$rin, undef, undef, 0.1);
		my $mfound = vec($rout, $hash->{SocketDevice}->{FD}, 1); 
		if($mfound && FRM_is_firmata_connected($hash)) {
			$hash->{FirmataDevice}->poll();
		}
		return $mfound;
	} elsif (defined $hash->{FD}) {
		my ($rout, $rin) = ('', '');
		vec($rin, $hash->{FD}, 1) = 1;
		my $nfound = select($rout=$rin, undef, undef, 0.1);
		my $mfound = vec($rout, $hash->{FD}, 1); 
		if($mfound && FRM_is_firmata_connected($hash)) {
			$hash->{FirmataDevice}->poll();
		}
		return $mfound;
	} else {
		# This is relevant for windows/USB only
		my $po = $hash->{USBDev};
		my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
		if($po) {
			($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
		}
		if ($InBytes && $InBytes>0 && FRM_is_firmata_connected($hash)) {
			$hash->{FirmataDevice}->poll();
		}
	}
}

=item FRM_OWX_Init

  Returns:
    undef or error message

  Description:
    obsolete FRM client function ($chash is FRM client)
    
=cut 

sub FRM_OWX_Init($$) {
	my ($chash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($chash,$args,PIN_ONEWIRE);
	return $ret if (defined $ret);
	eval {
		my $firmata = FRM_Client_FirmataDevice($chash);
		my $pin = $chash->{PIN};
		$chash->{FRM_OWX_CORRELATIONID} = 0;
		$firmata->observe_onewire($pin,\&FRM_OWX_observer,$chash);
		$chash->{FRM_OWX_REPLIES} = {};
		$chash->{DEVS} = [];
		if ( AttrVal($chash->{NAME},"buspower","") eq "parasitic" ) {
			$firmata->onewire_config($pin,1);
		}
	};
	return GP_Catch($@) if ($@);
	ReadingsSingleUpdate($chash, 'state', 'Initialized', 1);
	InternalTimer(gettimeofday()+10, "OWX_Discover", $chash,0);
	return undef;
}

=item FRM_OWX_observer

  Returns:
    nothing

  Description:
    obsolete Firmata device receive callback ($chash is FRM client)
    
=cut 

sub FRM_OWX_observer
{
	my ( $data,$chash ) = @_;
	my $command = $data->{command};
	COMMAND_HANDLER: {
		$command eq "READ_REPLY" and do {
			my $id = $data->{id};
			my $request = (defined $id) ? $chash->{FRM_OWX_REQUESTS}->{$id} : undef;
			unless (defined $request) {
				return unless (defined $data->{device});
				my $owx_device = FRM_OWX_firmata_to_device($data->{device});
				my %requests = %{$chash->{FRM_OWX_REQUESTS}};
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
			$chash->{FRM_OWX_REPLIES}->{$owx_device} = $owx_data;
			delete $chash->{FRM_OWX_REQUESTS}->{$id};
			last;			
		};
		($command eq "SEARCH_REPLY" or $command eq "SEARCH_ALARMS_REPLY") and do {
			my @owx_devices = ();
			foreach my $device (@{$data->{devices}}) {
				push @owx_devices, FRM_OWX_firmata_to_device($device);
			}
			if ($command eq "SEARCH_REPLY") {
				$chash->{DEVS} = \@owx_devices;
				#$main::attr{$chash->{NAME}}{"ow-devices"} = join " ",@owx_devices;
			} else {
				$chash->{ALARMDEVS} = \@owx_devices;
			}
			last;
		};
	}
}

=item FRM_OWX_device_to_firmata

  Description:
    obsolete FRM internal OWX utility function
    
=cut 

sub FRM_OWX_device_to_firmata
{
	my @device;
	foreach my $hbyte (unpack "A2xA2A2A2A2A2A2xA2", shift) {
		push @device, hex $hbyte;
	}
	return {
		family => shift @device,
		crc => pop @device,
		identity => \@device,
	}
}

=item FRM_OWX_firmata_to_device

  Description:
    obsolete FRM internal OWX utility function
    
=cut 

sub FRM_OWX_firmata_to_device
{
	my $device = shift;
	return sprintf ("%02X.%02X%02X%02X%02X%02X%02X.%02X",$device->{family},@{$device->{identity}},$device->{crc});
}

=item FRM_OWX_Verify

  Description:
    obsolete FRM client function ($chash is FRM client)
    
=cut 

sub FRM_OWX_Verify {
	my ($chash,$dev) = @_;
	foreach my $found (@{$chash->{DEVS}}) {
		if ($dev eq $found) {
			return 1;
		}
	}
	return 0;
}

=item FRM_OWX_Alarms

  Description:
    obsolete FRM client function ($chash is FRM client)
    
=cut 

sub FRM_OWX_Alarms {
	my ($chash) = @_;

	my $ret = eval {
		my $firmata = FRM_Client_FirmataDevice($chash);
		my $pin     = $chash->{PIN};
		return 0 unless ( defined $firmata and defined $pin );
		$chash->{ALARMDEVS} = undef;			
		$firmata->onewire_search_alarms($chash->{PIN});
		my $times = AttrVal($chash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
		for (my $i=0;$i<$times;$i++) {
			if (FRM_poll($chash->{IODev})) {
				if (defined $chash->{ALARMDEVS}) {
					return 1;
				}
			} else {
				select (undef,undef,undef,0.05);
			}
		}
		$chash->{ALARMDEVS} = [];
		return 1;
	};
	if ($@) {
		Log3 $chash->{NAME},4,"FRM_OWX_Alarms: ".GP_Catch($@);
		return 0;
	}
	return $ret;
}

=item FRM_OWX_Reset

  Description:
    obsolete FRM client function ($chash is FRM client)
    
=cut 

sub FRM_OWX_Reset {
	my ($chash) = @_;
	my $ret = eval {
		my $firmata = FRM_Client_FirmataDevice($chash);
		my $pin     = $chash->{PIN};
		return undef unless ( defined $firmata and defined $pin );
	
		$firmata->onewire_reset($pin);
		
		return 1;
	};
	if ($@) {
		Log3 $chash->{NAME},4,"FRM_OWX_Alarms: ".GP_Catch($@);
		return 0;
	}
	return $ret;
}

=item FRM_OWX_Complex

  Description:
    obsolete FRM client function ($chash is FRM client)
    
=cut 

sub FRM_OWX_Complex ($$$$) {
	my ( $chash, $owx_dev, $data, $numread ) = @_;

	my $res = "";

	my $ret = eval {
		my $firmata = FRM_Client_FirmataDevice($chash);
		my $pin     = $chash->{PIN};
		return 0 unless ( defined $firmata and defined $pin );
	
		my $ow_command = {};
	
		#-- has match ROM part
		if ($owx_dev) {
			$ow_command->{"select"} = FRM_OWX_device_to_firmata($owx_dev);
	
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
			my $id = $chash->{FRM_OWX_CORRELATIONID};
			$ow_command->{"id"} = $chash->{FRM_OWX_CORRELATIONID};
			$chash->{FRM_OWX_REQUESTS}->{$id} = {
				command => $ow_command,
				device => $owx_dev
			};
			delete $chash->{FRM_OWX_REPLIES}->{$owx_dev};		
			$chash->{FRM_OWX_CORRELATIONID} = ($id + 1) & 0xFFFF;
		}
	
		$firmata->onewire_command_series( $pin, $ow_command );
		
		if ($numread) {
			my $times = AttrVal($chash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
			for (my $i=0;$i<$times;$i++) {
				if (FRM_poll($chash->{IODev})) {
					if (defined $chash->{FRM_OWX_REPLIES}->{$owx_dev}) {
						$res .= $chash->{FRM_OWX_REPLIES}->{$owx_dev};
						return $res;
					}
				} else {
					select (undef,undef,undef,0.05);
				}
			}
		}
		return $res;
	};
	if ($@) {
		Log3 $chash->{NAME},4,"FRM_OWX_Alarms: ".GP_Catch($@);
		return 0;
	}
	return $ret;
}

=item FRM_OWX_Discover

  Returns:
    0: error
    1: OK
    
  Description:
    obsolete FRM client function ($chash is FRM client)
    Discover devices on the 1-Wire bus via Firmata internal firmware
    
=cut 

sub FRM_OWX_Discover ($) {
	my ($chash) = @_;

	my $ret = eval {
		my $firmata = FRM_Client_FirmataDevice($chash);
		my $pin     = $chash->{PIN};
		return 0 unless ( defined $firmata and defined $pin );
		my $old_devices = $chash->{DEVS};
		$chash->{DEVS} = undef;			
		$firmata->onewire_search($chash->{PIN});
		my $times = AttrVal($chash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
		for (my $i=0;$i<$times;$i++) {
			if (FRM_poll($chash->{IODev})) {
				if (defined $chash->{DEVS}) {
					return 1;
				}
			} else {
				select (undef,undef,undef,0.05);
			}
		}
		$chash->{DEVS} = $old_devices;
		return 1;
	};
	if ($@) {
		Log3 $chash->{NAME},4,"FRM_OWX_Alarms: ".GP_Catch($@);
		return 0;
	}
	return $ret;
}

=item FRM_Serial_Open

  Returns:
    0: error
    1: OK
    
  Description:
    FHEM module IOOpenFn for FRM client that uses FRM as IODev ($chash is FRM client)
    
=cut 

sub FRM_Serial_Open {
  my ($chash) = @_;

  if (!defined $chash->{IODevPort} || !defined $chash->{IODevParameters}) {
    Log3 $chash->{NAME},3,"$chash->{IODev}{NAME} Serial_Open: serial port or baudrate not defined by $chash->{NAME}";
    return 0;
  }
  
  $chash->{IODev}{SERIAL}{$chash->{IODevPort}} = $chash->{NAME};

  Log3 $chash->{NAME},5,"$chash->{IODev}{NAME} Serial_Open: serial port $chash->{IODevPort} registered for $chash->{NAME}";

  return FRM_Serial_Setup($chash);
}

=item FRM_Serial_Setup

  Returns:
    0: error
    1: OK
    
  Description:
    FRM internal function ($chash is FRM client that uses FRM as IODev)
    
=cut 

sub FRM_Serial_Setup {
  my ($chash) = @_;
  
  if (FRM_is_firmata_connected($chash->{IODev})) {
    my $firmata = FRM_Client_FirmataDevice($chash);
    if (!defined $firmata ) {
      Log3 $chash->{NAME},3,"$chash->{IODev}{NAME} Serial_Setup: no Firmata device available";
      return 0;
    }
        
    # configure port by claiming pins, setting baud rate and start reading
    my $port = $chash->{IODevPort};
    if ($chash->{IODevParameters} =~ m/(\d+)(,([78])(,([NEO])(,([012]))?)?)?/) {
      my $baudrate = $1;
      if ($port > 7) {
        # software serial port, get serial pins from attribute
        my $err; 
        my $serialattr = AttrVal($chash->{IODev}{NAME}, "software-serial-config", undef);
        if (defined $serialattr) {
          my @a = split(":", $serialattr);
          if (scalar @a == 3 && $a[0] == $port) {
            $chash->{PIN_RX} = $a[1];
            $chash->{PIN_TX} = $a[2];
            
            # activate port
            $firmata->serial_config($port, $baudrate, $a[1], $a[2]);
          } else {
            $err = "Error, invalid software-serial-config, must be <software serial port number>:<RX pin number>:<TX pin number>";
          }
        } else {
          $err = "Error, attribute software-serial-config required for using software serial port $port";
        }
        if ($err) {        
          Log3 $chash->{NAME},2,"$chash->{IODev}{NAME}: $err";
          return 0;
        }
      } else {
        # hardware serial port, get serial pins by port number from capability metadata
        my $rxPinType = 2*$port;
        my $txPinType = $rxPinType + 1;
        my $rxPin = undef;
        my $txPin = undef;
        foreach my $pin ( keys %{$firmata->{metadata}{serial_resolutions}} ) {
          if ($firmata->{metadata}{serial_resolutions}{$pin} == $rxPinType) {
            $rxPin = $pin;
          }
          if ($firmata->{metadata}{serial_resolutions}{$pin} == $txPinType) {
            $txPin = $pin;
          }
        }
        if (!defined $rxPin || !defined $txPin) {
          Log3 $chash->{NAME},3,"$chash->{IODev}{NAME} Serial_Setup: serial pins of port $port not available on Arduino";
          return 0;
        }
        $chash->{PIN_RX} = $rxPin;
        $chash->{PIN_TX} = $txPin;

        # activate port
        $firmata->serial_config($port, $baudrate);
      }      
      $firmata->observe_serial($port, \&FRM_serial_observer, $chash->{IODev});
      $firmata->serial_read($port, 0); # continuously read and send all available bytes 
      Log3 $chash->{NAME},5,"$chash->{IODev}{NAME} Serial_Setup: serial port $chash->{IODevPort} opened with $baudrate baud for $chash->{NAME}";
    } else {
      Log3 $chash->{NAME},3,"$chash->{IODev}{NAME} Serial_Setup: invalid baudrate definition $chash->{IODevParameters} for port $port by $chash->{NAME}";
      return 0;
    }
  }

  return 1;
}

=item FRM_Serial_Write

  Returns:
    number of bytes written
    
  Description:
    FHEM module IOWriteFn for FRM client that uses FRM as IODev ($chash is FRM client)
    
=cut 

sub FRM_Serial_Write {
  my ($chash, $msg) = @_;

  my $firmata = FRM_Client_FirmataDevice($chash);
  my $port    = $chash->{IODevPort};
  return 0 unless ( defined $firmata and defined $port );

  if (FRM_is_firmata_connected($chash->{IODev}) && defined($msg)) {
    my @data = unpack("C*", $msg);
    #my $size = scalar(@data);
    #Log3 $chash->{NAME},3,"$chash->{IODev}{NAME} Serial_Write: $size bytes on serial port $chash->{IODevPort} $msg by $chash->{NAME}";
    $firmata->serial_write($port, @data);
    return length($msg);
  } else {
    return 0;
  }
}

=item FRM_Serial_Close

  Returns:
    0: error
    1: OK
    
  Description:
    FHEM module IOCloseFn for FRM client that uses FRM as IODev ($chash is FRM client)
    
=cut 

sub FRM_Serial_Close {
  my ($chash) = @_;

  my $port = $chash->{IODevPort};
  return 0 unless ( defined $port );

  if (FRM_is_firmata_connected($chash->{IODev})) {
    my $firmata = FRM_Client_FirmataDevice($chash);
    $firmata->serial_stopreading($port);
  }
  
  delete $chash->{PIN_RX};
  delete $chash->{PIN_TX};
  delete $chash->{IODev}{SERIAL}{$chash->{IODevPort}};
  
  #Log3 $chash->{NAME},5,"$chash->{IODev}{NAME} Serial_Close: serial port $chash->{IODevPort} unregistered for $chash->{NAME}";
  
  return 1;
}

1;

=pod

  CHANGES

  18.12.2015 jensb
    o added sub FRM_is_firmata_connected
      - extended connection check including {FirmataDevice}->{io} (gets
        deleted by FRM_FirmataDevice_Close on TCP disconnect while FHEM
        has still a valid reference to {FirmataDevice} when calling
        I2CWrtFn)
    o modified sub FRM_Set, FRM_Get, FRM_I2C_Write, FRM_poll:
      - use sub FRM_is_firmata_connected to check if Firmata is still
        connected before performing IO operations (to prevent FHEM crash)
    o modified sub FRM_Tcp_Connection_Close:
      - set STATE to listening and delete SocketDevice (to present same
        idle state as FRM_Start)
    o help updated
    
  22.12.2015 jensb
    o modified sub FRM_DoInit:
      - clear internal readings (device may have changed)
    o added serial pin support  
    
  05.01.2016 jensb
    o modified FRM_DoInit:
      - do not disconnect DevIo in TCP mode to stay reconnectable
    o use readingsSingleUpdate on state instead of directly changing STATE
    
  26.03.2016 jensb
    o asynchronous device setup (FRM_DoInit, FRM_SetupDevice)
    o experimental reconnect detection
    o new attribute to skip device reset on connect
    o help updated
    
  31.12.2016 jensb
    o I2C read error detection
      - modified FRM_I2C_Write: delete internal I2C_ERROR reading before performing I2C read operation to detect read errors
      - modified FRM_string_observer: assign Firmata message to internal I2C_ERROR reading when string starts with "I2C"
      - modified FRM_i2c_update_device: assign internal I2C_ERROR to XXX_SENDSTAT of IODev if defined after performing a I2C read
    
  27.12.2017 JB
    o I2C write parameter validation
      - modified FRM_I2C_Write: prevent processing if parameters are undefined
      
  01.01.2018 JB
    o OWX support
      - modified FRM_Client_AssignIOPort: use already assigned IODev
      
  03.01.2018 JB
    o show capability "pullup" as internal "pullup_pins"
    o show version of perl-firmata driver as internal "DRIVER_VERSION"
      
  04.01.2018 JB
    o fix capability query for Firmata firmware without AnalogInputFirmata
    o new attribute "disable" and new state "disabled"
    
  07.01.2018 JB
    o new attribute "errorExclude" and new reading "stringMessage"
    
  10.01.2018 JB
    o new states "defined" and "connected"
  
  13.01.2018 JB
    o commented, formatted and refactored
    
=cut

=pod
=item device
=item summary Firmata device gateway 
=item summary_DE Firmata Gateway
=begin html

<a name="FRM"></a>
<h3>FRM</h3>
<ul>
  This module enables FHEM to communicate with a device that implements the <a href="http://www.firmata.org">Firmata</a> protocol
  (e.g. an <a href="http://www.arduino.cc">Arduino</a>).<br><br>

  The connection between FHEM and the Firmata device can be established by serial port, USB, LAN or WiFi.<br><br>
  
  A single FRM device can serve multiple FRM clients from this list:<br><br>
  <a href="#FRM_IN">FRM_IN</a>,
  <a href="#FRM_OUT">FRM_OUT</a>,
  <a href="#FRM_AD">FRM_AD</a>,
  <a href="#FRM_PWM">FRM_PWM</a>,
  <a href="#FRM_I2C">FRM_I2C</a>,
  <a href="#FRM_SERVO">FRM_SERVO</a>,
  <a href="#FRM_RGB">FRM_RGB</a>,
  <a href="#FRM_ROTENC">FRM_ROTENC</a>,
  <a href="#FRM_STEPPER">FRM_STEPPER</a>,
  <a href="#FRM_LCD">FRM_LCD</a>,
  <a href="#OWX">OWX</a>,
  <a href="#I2C_LCD">I2C_LCD</a>,
  <a href="#I2C_DS1307">I2C_DS1307</a>,
  <a href="#I2C_PCA9532">I2C_PCA9532</a>,
  <a href="#I2C_PCA9685">I2C_PCA9685</a>,
  <a href="#I2C_PCF8574">I2C_PCF8574</a>,
  <a href="#I2C_MCP23008">I2C_MCP23008</a>,
  <a href="#I2C_MCP23017">I2C_MCP23017</a>,
  <a href="#I2C_MCP342x">I2C_MCP342x</a>,
  <a href="#I2C_SHT21">I2C_SHT21</a>,
  <a href="#I2C_SHT3x">I2C_SHT3x</a>,
  <a href="#I2C_BME280">I2C_BME280</a>,
  <a href="#I2C_BMP180">I2C_BMP180</a>,
  <a href="#I2C_BH1750">I2C_BH1750</a>,
  <a href="#I2C_TSL2561">I2C_TSL2561</a>,
  <a href="#I2C_K30">I2C_K30</a>,
  <a href="#I2C_LM75A">I2C_LM75A</a><br><br>  
   
  Each client stands for a pin of the Firmata device configured for a specific use 
  (digital/analog in/out) or an integrated circuit connected to Firmata device by I2C.<br><br>
  
  Note: This module is based on the Perl module <a href="https://github.com/jnsbyr/perl-firmata">Device::Firmata</a>
  (perl-firmata). A suitable version of perl-firmata is distributed with FHEM (see subdirectory FHEM/lib/Device/Firmata). 
  You can download the latest version of perl-firmata <a href="https://github.com/jnsbyr/perl-firmata/archive/master.zip">
  as a single zip</a> file from github.<br><br>
  
  Note: This module may require the Device::SerialPort or Win32::SerialPort module if you attach the device via serial port
  or USB and the operating system sets unsuitable default parameters for serial devices.<br><br>

  <a name="FRMdefine"></a>
  <b>Define</b><br><br>
  
  <code>define &lt;name&gt; FRM {&lt;device&gt; | &lt;port&gt; [global]}</code> <br><br>
      
  <ul>
  <li>serial and USB connected devices:<br><br>
      <code>&lt;device&gt;</code> specifies the serial port to communicate with the Firmata device.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the Firmata device by the
      following command:<br>
      <code>modprobe usbserial vendor=0x03eb product=0x204b</code></br>
      In this case the device is most probably /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@38400<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and FHEM opens the device
      with simple file io. This might work if the operating system uses the same
      defaults for the serial parameters as the Firmata device, e.g. some Linux 
      distributions and OSX.<br><br>

      An Arduino compatible device should either use 'StandardFirmata' or 'ConfigurableFirmata' without NetworkFirmata.
  </li><br>
  
  <li>network connected devices:<br><br>
      <code>&lt;port&gt;</code> specifies the port the FRM device listens on. If <code>global</code> is
      specified the socket is bound to all local IP addresses, otherwise to localhost
      only.<br><br>

      The connection is initiated by the Firmata device in client-mode. Therefore the IP address and port
      of the FHEM server has to be configured in the Firmata device, so it knows where to connect to.<br>
      For multiple Firmata you need separate FRM devices configured to different ports.<br><br>

      An Arduino compatible device should run one of 'StandardFirmataEthernet', 'StandardFirmataWiFi', 
      'ConfigurableFirmata' with NetworkFirmata or 'ConfigurableFirmataWiFi'.
  </li><br>
  
  <li>no device:<br><br>
      If <code>&lt;device&gt;</code> is set to <code>none</code>, no connection will be opened and you
      can experiment without hardware attached.<br>
  </li>
  </ul>
  <br>
  StandardFirmata supports digital and analog-I/O, servos and I2C. In addition to that ConfigurableFirmata supports 1-Wire and stepper motors.<br><br>
  
  You can find StandardFirmata, StandardFirmataEthernet and StandardFirmataWiFi in the Arduino IDE in the menu 'File->Examples->Firmata'<br><br>
  
  <a href="https://github.com/firmata/arduino/tree/configurable/examples/ConfigurableFirmata">ConfigurableFirmata</a>
  can be installed using the library manager of the Arduino IDE.<br><br>
  
  Further information can be found at the FRM client devices listed above and the 
  <a href="http://www.fhemwiki.de/wiki/Arduino_Firmata#Installation_ConfigurableFirmata">FHEM-Wiki</a>.<br><br>
  
  <a name="FRMset"></a>
  <b>Set</b>
  <ul>
  <li>
    <code>set &lt;name&gt; reinit</code><br>
    reinitializes the FRM client devices attached to this FRM device
  </li><br>
  
  <li>
    <code>set &lt;name&gt; reset</code><br>
    performs a software reset on the Firmata device and disconnects form the Firmata device - after the Firmata device reconnects the attached FRM client devices are reinitialized
  </li>
  </ul>
  <br><br>
  
  <a name="FRMattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>resetDeviceOnConnect {0|1}, default: 1<br>
      Reset the Firmata device immediately after connect to force default Firmata startup state: 
      All pins with analog capability are configured as input, all other (digital) pins are configured as output 
      and the input pin reporting, the I2C configuration and the serial port configuration are cancelled and will
      be reinitialized.
      </li><br>
      
      <li>i2c-config &lt;write-read-delay&gt;, no default<br>
      Configure the Arduino for ic2 communication. Definig this attribute will enable I2C on all
      i2c_pins received by the capability-query issued during initialization of FRM.<br>
      As of Firmata 2.3 you can set a delay-time (in microseconds, max. 32767, default: 0) that will be
      inserted into I2C protocol when switching from write to read. This may be necessary because Firmata
      I2C write does not block on the FHEM side so consecutive I2C write/read operations get queued and
      will be executed on the Firmata device in a different time sequence. Use the maximum operation
      time required by the connected I2C devices (e.g. 30000 for the BMP180 with triple oversampling,
      see I2C device manufacturer documentation for details).<br>
      See: <a href="http://www.firmata.org/wiki/Protocol#I2C">Firmata Protocol details about I2C</a>
      </li><br>
      
      <li>sampling-interval &lt;interval&gt;, default: 1000 ms<br>
      Configure the interval Firmata reports analog data to FRM (in milliseconds, max. 32767).<br>
      This interval applies to the operation of <a href="#FRM_I2C">FRM_I2C</a>.<br>
      See: <a href="http://www.firmata.org/wiki/Protocol#Sampling_Interval">Firmata Protocol details about Sampling Interval</a>
      </li><br>
      
      <li>software-serial-config &lt;port&gt;:&lt;rx pin&gt;:&lt;tx pin&gt;, no default<br>
      For using a software serial port (port number 8, 9, 10 or 11) two I/O pins must be specified.
      The rx pin must have interrupt capability and the tx pin must have digital output capability.<br>
      See: <a href="https://www.arduino.cc/en/Reference/SoftwareSerial">Arduino SoftwareSerial Library</a>
      </li><br>
      
      <li>errorExclude &lt;regexp&gt;, no default<br>
      If set will exclude a string message received from the Firmata device that matches the given regexp
      from being logged at verbose=3 and will assign the data to the reading <i>stringMessage</i> instead 
      of <i>error</i>. Logging will still be done at verbose=5.
      </li><br>
      
      <li>disable {0|1}, default: 0<br>
      Disables this devices if set to 1.
      </li>      
  </ul>
  <br><br>

  <a name="FRMreadings"></a>
  <b>Readings</b><br>
  <ul>
      <li>state<br>
          Possible values are: <i>defined | disabled</i> and depending on the connection type:<br>
          serial: <i>opened | connected | Initialized | disconnected</i><br>
          network: <i>listening | connected | Initialized</i>
      </li><br>
      
      <li>error<br>
          Data of last string message received from Firmata device, typically (but not necessarily) an error of the last operation.
          Data prefixed with <i>I2C</i> will additionally be assigned to the internal reading <i>I2C_ERROR</i>.
      </li><br>
      
      <li>stringMessage<br>
          Data of last string message received from Firmata device that matches attribute <i>errorExclude</i>.
      </li>      
  </ul>
  <br><br>
  
  <a name="FRMinternals"></a>
  <b>Internals</b><br>
  <ul>
      <li><code>DRIVER_VERSION</code><br>
          Version of the Perl module Device::Firmata (perl-firmata), should be 0.63 or higher.
      </li><br>
      
      <li><code>protocol_version</code><br>
          Firmata protocol version reported by the Firmata device.
      </li><br>
      
      <li><code>firmware</code><br>
          Firmata firmware name reported by the Firmata device (this is typically the Arduino project name).
      </li><br>
      
      <li><code>firmware_version</code><br>
          Firmata firmware version reported by the Firmata device.
      </li><br>
      
      <li><code>xxx_pins | xxx_resolutions | xxx_ports</code><br>
          Pin capability reported by the Firmata device, where <code>xxx</code> can be one of the following:
          <ul>
              <li><code>input | pullup:</code> digital input, see <a href="#FRM_IN">FRM_IN</a></li>
              <li><code>output:</code> digital output, see <a href="#FRM_OUT">FRM_OUT</a></li>
              <li><code>analog:</code> analog input with ADC of given resolution, see <a href="#FRM_AD">FRM_AD</a></li>
              <li><code>pwm:</code> digital output with PWM capability with DAC of given resolution, see <a href="#FRM_PWM">FRM_PWM</a></li>
              <li><code>servo:</code> analog output with servo capability of given resolution, see <a href="#FRM_SERVO">FRM_SERVO</a></li>
              <li><code>i2c:</code> I2C compatible pin, FRM can be used as IODev of another FHEM I2C device</li>
              <li><code>onewire:</code> OneWire compatible pin, FRM can be used as IODev of <a href="#OWX">OWX</a></li>
              <li><code>stepper:</code> stepper output pin of given resolution, see <a href="#FRM_STEPPER">FRM_STEPPER</a></li>
              <li><code>encoder:</code> rotary encoder input pin of given resolution, see <a href="#FRM_ROTENC">FRM_ROTENC</a></li>              
              <li><code>serial:</code> serial rx/tx pin of given port, FRM can be used as serial device of another FHEM device, 
                  see <a href="#FRMnotes">notes</a>
              </li>        
          </ul><br>
          
          <i>Note:</i> A reported capability is a minimum requirement but does not guarantee that this pin function is
          really available. Some reasons for this are (a) boards with same model name may have different hardware and 
          firmware revisions with different hardwired special functions for specific pins and (b) a pin function may 
          depend on the Arduino platform and specific library version. When something does not work on the fist pin 
          you try and you can rule out a wiring problem try some other pins or try to find manufacturer documentation.
      </li>
  </ul>
  <br><br>
  
  <a name="FRMnotes"></a>
  <b>Notes</b><br>
  <ul>
      <li><code>Digital Pins</code><br>
        WARNING: Stock Firmata has a notable default: At the end of the initialization phase of the Firmata device 
        after boot or reset and before a host connection can be established all pins with analog input capability will be configured
        as analog input and all pins with "only" digial I/O capability are configured as outputs and set to off. ConfigurableFirmata 
        is a little bit more selective in this respect and will only do this if you enable AnalogInputFirmata or DigitalOutputFirmata
        respectively. If your board has a pin without analog capability and you have wired this pin as a digital input this behaviour 
        might damage your circuit. CPUs typically set input mode for GPIO pins when resetting to prevent this.<br><br>
        
        You should look for the function "<code>void systemResetCallback()</code>" in your Firmata sketch and change 
        "<code>Firmata.setPinMode(i, OUTPUT);</code>" to "<code>Firmata.setPinMode(i, INPUT);</code>" to get a save initial state or 
        completely customize the default state of each pin according to your needs by replacing the Firmata reset code.
      </li><br>
      
      <li><code>Serial Ports</code><br>
        A serial device can be connected to a serial port of a network connected Firmata device instead of being directly connected
        to your FHEM computer. This way the Firmata device will become a serial over LAN (SOL) adapter. To use such a remote serial 
        port in other FHEM modules you need to set the serial device descriptor to:<br><br>
      
        <code>FHEM:DEVIO:&lt;FRM device name&gt;:&lt;serial port&gt;@&lt;baud rate&gt;</code><br><br>
        
        To use a serial port both the RX and TX pin of this port must be available via Firmata, even if one of the pins will not be used. 
        Depending on the Firmata version the first hardware serial port (port 0) cannot be used even with network connected 
        devices because port 0 is still reserved for the Arduino host communication.
        On some Arduinos you can use software serial ports (ports 8 to 11). FRM supports a maximum of one software serial port that can
        be activated using the software-serial-config attribute.<br><br>
        
        In current Firmata versions serial setup options (data bits, parity, stop bits) cannot be configured but may be compiled into the 
        Firmata Firmware (see function "<code>((HardwareSerial*)serialPort)->begin(baud, options)</code>" in SerialFirmata.cpp of the
        Firmata library).<br><br>
              
        Not all FHEM modules for serial devices are compatible with this mode of operation. It will not work if (1) the FHEM module requires
        hardware handshake or direct IO of serial pin like CTS or DTR or (2) the FHEM module does not support the syntax of serial device 
        descriptor (e.g. the <a href="#HEATRONIC">HEATRONIC</a> module works perfectly with a single line patch).
      </li>
  </ul>
</ul>
<br>

=end html
=cut

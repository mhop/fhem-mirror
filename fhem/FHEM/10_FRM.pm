##############################################
package main;

use vars qw{%attr %defs}; 
use strict;
use warnings;

#add FHEM/lib to @INC if it's not allready included. Should rather be in fhem.pl than here though...
BEGIN {
	if (!grep(/FHEM\/lib$/,@INC)) {
		foreach my $inc (grep(/FHEM$/,@INC)) {
			push @INC,$inc."/lib";
		};
	};
};

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
  I2C_LCD
  I2C_PC.*
  I2C_MCP23017
  I2C_BMP180
  FRM_LCD
);

#####################################
sub FRM_Initialize($) {
	my $hash = shift @_;
	
	require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

	# Provider
	$hash->{Clients} = join (':',@clients);
	$hash->{ReadyFn} = "FRM_Ready";  
	$hash->{ReadFn}  = "FRM_Read";

	$hash->{I2CWrtFn} = "FRM_I2C_Write";

	# Consumer
	$hash->{DefFn}    = "FRM_Define";
	$hash->{UndefFn}  = "FRM_Undef";
	$hash->{GetFn}    = "FRM_Get";
	$hash->{SetFn}    = "FRM_Set";
	$hash->{AttrFn}   = "FRM_Attr";
	$hash->{NotifyFn} = "FRM_Notify";

	$hash->{AttrList} = "model:nano dummy:1,0 sampling-interval i2c-config $main::readingFnAttributes";
}

#####################################
sub FRM_Define($$) {
	my ( $hash, $def ) = @_;

	my ($name, $type, $dev, $global) = split("[ \t]+", $def);
	$hash->{DeviceName} = $dev;

	$hash->{NOTIFYDEV} = "global";

	if ( $dev eq "none" ) {
		Log3 $name,3,"device is none, commands will be echoed only";
		$main::attr{$name}{dummy} = 1;
	}
	if ($main::init_done) {
		return FRM_Start($hash);
	}
	
	return undef;
}

#####################################
sub FRM_Undef($) {
	my $hash = shift;
	FRM_forall_clients($hash,\&FRM_Client_Unassign,undef);
	if (defined $hash->{DeviceName}) {
		DevIo_Disconnected($hash);
	};
	
	foreach my $d ( sort keys %main::defs ) { # close and dispose open tcp-connection (if any) to free open filedescriptors
		if ( defined( my $dev = $main::defs{$d} )) {
			if ( defined( $main::defs{$d}{SNAME} )
				&& $main::defs{$d}{SNAME} eq $hash->{NAME}) {
					FRM_Tcp_Connection_Close($main::defs{$d});
				}
		}
	}

	FRM_FirmataDevice_Close($hash);

	return undef;
}

sub FRM_Start {
	my ($hash) = @_;

	my ($dev, $global) = split("[ \t]+", $hash->{DEF});
	$hash->{DeviceName} = $dev;
	
	my $isServer = 1 if($dev && $dev =~ m/^(IPV6:)?\d+$/);
#	my $isClient = 1 if($dev && $dev =~ m/^(IPV6:)?.*:\d+$/);

#	return "Usage: define <name> FRM {<device>[@<baudrate>] | [IPV6:]<tcp-portnr> [global]}"
#		if(!($isServer || $isClient) ||
#			($isClient && $global) ||
#			($global && $global ne "global"));

	# Make sure that fhem only runs once
	if($isServer) {
		my $ret = TcpServer_Open($hash, $dev, $global);
		if (!$ret) {
			$hash->{STATE}="listening";
		}
		return $ret;
	}

	DevIo_CloseDev($hash);	

	my $ret = DevIo_OpenDev($hash, 0, "FRM_DoInit");
	return $ret;	
}

sub FRM_Notify {
  my ($hash,$dev) = @_;
  my $name  = $hash->{NAME};
  my $type  = $hash->{TYPE};

  if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
  	FRM_Start($hash);
  } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  }
}

#####################################
sub FRM_Set($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
  	if(!defined($sets{$a[1]}));
  my $command = $a[1];
  my $value = $a[2];

  COMMAND_HANDLER: {
    $command eq "reset" and do {
      return $hash->{NAME}." is not connected" unless (defined $hash->{FirmataDevice} and (defined $hash->{FD} or ($^O=~/Win/ and defined $hash->{USBDev})));
      $hash->{FirmataDevice}->system_reset();
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
        DevIo_CloseDev($hash);
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

#####################################
sub FRM_Get($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %gets)
  	if(!defined($gets{$a[1]}));
  my $name = shift @a;
  my $cmd = shift @a;
  ARGUMENT_HANDLER: {
    $cmd eq "firmware" and do {
      if (defined $hash->{FirmataDevice}) {
        return $hash->{FirmataDevice}->{metadata}->{firmware};
      } else {
        return "not connected to FirmataDevice";
      }
		};
		$cmd eq "version" and do {
  		if (defined $hash->{FirmataDevice}) {
  		  return $hash->{FirmataDevice}->{metadata}->{firmware_version};
  		} else {
  		  return "not connected to FirmataDevice";
		  }
		};
	}
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data

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
}

sub FRM_Ready($) {

	my ($hash) = @_;
	my $name = $hash->{NAME};
	if ($name=~/^^FRM:.+:\d+$/) { # this is a closed tcp-connection, remove it
		FRM_Tcp_Connection_Close($hash);
		FRM_FirmataDevice_Close($hash);
	}
	return DevIo_OpenDev($hash, 1, "FRM_DoInit") if($hash->{STATE} eq "disconnected");
	
	# This is relevant for windows/USB only
	my $po = $hash->{USBDev};
	my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags);
	if($po) {
		($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
	}
	return ($InBytes && $InBytes>0);
}

sub FRM_Tcp_Connection_Close($) {
	my $hash = shift;
	TcpServer_Close($hash);
	if ($hash->{SNAME}) {
		my $shash = $main::defs{$hash->{SNAME}};
		$hash->{SocketDevice} = undef if (defined $shash);
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

sub FRM_FirmataDevice_Close($) {
	my $hash = shift;
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

sub FRM_Attr(@) {
	my ($command,$name,$attribute,$value) = @_;
	if ($command eq "set") {
		$main::attr{$name}{$attribute}=$value;
		if ($attribute eq "sampling-interval" 
			or $attribute eq "i2c-config") {
			FRM_apply_attribute($main::defs{$name},$attribute);
		}
	}
}

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

sub FRM_DoInit($) {
	
	my ($hash) = @_;
	
	my $sname = $hash->{SNAME}; #is this a serversocket-connection?
	my $shash = defined $sname ? $main::defs{$sname} : $hash;
	
	my $name = $shash->{NAME};
	
  	my $firmata_io = Firmata_IO->new($hash);
	my $device = Device::Firmata::Platform->attach($firmata_io) or return 1;

	$shash->{FirmataDevice} = $device;
	if (defined $sname) {
		$shash->{SocketDevice} = $hash;
		#as FRM_Read gets the connected socket hash, but calls firmatadevice->poll():
		$hash->{FirmataDevice} = $device;
	}
	$device->observe_string(\&FRM_string_observer,$shash);
	
	my $found; # we cannot call $device->probe() here, as it doesn't select bevore read, so it would likely cause IODev to close the connection on the first attempt to read from empty stream
	my $endTicks = time+5;
	my $queryTicks = time+2;
	$device->system_reset();
	do {
		FRM_poll($shash);
		if ($device->{metadata}{firmware} && $device->{metadata}{firmware_version}) {
			$device->{protocol}->{protocol_version} = $device->{metadata}{firmware_version};
			$main::defs{$name}{firmware} = $device->{metadata}{firmware};
			$main::defs{$name}{firmware_version} = $device->{metadata}{firmware_version};
			Log3 $name,3,"Firmata Firmware Version: ".$device->{metadata}{firmware}." ".$device->{metadata}{firmware_version};
			$device->analog_mapping_query();
			$device->capability_query();
			do {
				FRM_poll($shash);
				if ($device->{metadata}{analog_mappings} and $device->{metadata}{capabilities}) {
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
					my $encoderpins = $device->{metadata}{encoder_pins};
					$main::defs{$name}{encoder_pins} = join(",", sort{$a<=>$b}(@$encoderpins)) if (defined $encoderpins and scalar @$encoderpins);
					my $stepperpins = $device->{metadata}{stepper_pins};
					$main::defs{$name}{stepper_pins} = join(",", sort{$a<=>$b}(@$stepperpins)) if (defined $stepperpins and scalar @$stepperpins);
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
					$found = 1;
				} else {
					select (undef,undef,undef,0.01);
				} 
			} while (time < $endTicks and !$found);
			$found = 1;
		} else {
			select (undef,undef,undef,0.01);
			if (time > $queryTicks) {
				Log3 $name,3,"querying Firmata Firmware Version";
				$device->firmware_version_query();
				$queryTicks++;
			}
		}
	} while (time < $endTicks and !$found);
	if ($found) {
		FRM_apply_attribute($shash,"sampling-interval");
		FRM_apply_attribute($shash,"i2c-config");
		FRM_forall_clients($shash,\&FRM_Init_Client,undef);
		$shash->{STATE}="Initialized";
		return undef;
	}
	Log3 $name,3,"no response from Firmata, closing DevIO";
	DevIo_Disconnected($shash);
	delete $shash->{FirmataDevice};
	delete $shash->{SocketDevice};
	return "FirmataDevice not responding";
}

sub
FRM_forall_clients($$$)
{
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

sub
FRM_Init_Client($@) {
	my ($hash,$args) = @_;
	if (!defined $args and defined $hash->{DEF}) {
  		my @a = split("[ \t][ \t]*", $hash->{DEF});
  		$args = \@a;
	}
	my $name = $hash->{NAME};
	my $ret = CallFn($name,"InitFn",$hash,$args);
	if ($ret) {
		Log3 $name,2,"error initializing '".$hash->{NAME}."': ".$ret;
	}
}

sub
FRM_Init_Pin_Client($$$) {
	my ($hash,$args,$mode) = @_;
	my $u = "wrong syntax: define <name> FRM_XXX pin";
  	return $u unless defined $args and int(@$args) > 0;
 	my $pin = @$args[0];
 	
	$hash->{PIN} = $pin;
	eval {
		FRM_Client_AssignIOPort($hash);
		FRM_Client_FirmataDevice($hash)->pin_mode($pin,$mode);
	};
	if ($@) {
		$@ =~ /^(.*)( at.*FHEM.*)$/;
		$hash->{STATE} = "error initializing: ".$1;
		return $1;
	}
	return undef;
}

sub
FRM_Client_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  $hash->{STATE}="defined";
  
  if ($main::init_done) {
    eval {
      FRM_Init_Client($hash,[@a[2..scalar(@a)-1]]);
    };
    if ($@) {
      $@ =~ /^(.*)( at.*FHEM.*)$/;
      return $1;
    }
  }
  return undef;
}

sub
FRM_Client_Undef($$)
{
  my ($hash, $name) = @_;
  my $pin = $hash->{PIN};
  eval {
    my $firmata = FRM_Client_FirmataDevice($hash);
    $firmata->pin_mode($pin,PIN_ANALOG);
  };
  if ($@) {
    eval {
      my $firmata = FRM_Client_FirmataDevice($hash);
      $firmata->pin_mode($pin,PIN_INPUT);
      $firmata->digital_write($pin,0);
    };
  }
  return undef;
}

sub
FRM_Client_Unassign($)
{
  my ($dev) = @_;
  delete $dev->{IODev} if defined $dev->{IODev};
  $dev->{STATE}="defined";  
}

sub
FRM_Client_AssignIOPort($@)
{
	my ($hash,$iodev) = @_;
	my $name = $hash->{NAME};
	AssignIoPort($hash,defined $iodev ? $iodev : AttrVal($hash->{NAME},"IODev",undef));
	die "unable to assign IODev to '$name'" unless defined ($hash->{IODev});
	
	if (defined($hash->{IODev}->{SNAME})) {
		$hash->{IODev} = $main::defs{$hash->{IODev}->{SNAME}};
		$attr{$name}{IODev} = $hash->{IODev}{NAME};
	}

	foreach my $d ( sort keys %main::defs ) {
		if ( defined( my $dev = $main::defs{$d} )) {
			if ( $dev != $hash
				&& defined( $dev->{IODev} )
				&& defined( $dev->{PIN} )
				&& $dev->{IODev} == $hash->{IODev}
				&& defined( $hash->{PIN})
				&& grep {$_ == $hash->{PIN}} split(" ",$dev->{PIN}) ) {
				  delete $hash->{IODev};
				  delete $attr{$name}{IODev};
					die "Device '$main::defs{$d}{NAME}' allready defined for pin $hash->{PIN}";
				}
		}
	}
}

sub FRM_Client_FirmataDevice($) {
  my $hash = shift;
  my $iodev = $hash->{IODev};
  die $hash->{NAME}." no IODev assigned" unless defined $iodev;
  die $hash->{NAME}.", ".$iodev->{NAME}." is not connected" unless (defined $iodev->{FirmataDevice} and (defined $iodev->{FD} or ($^O=~/Win/ and defined $iodev->{USBDev})));
  return $iodev->{FirmataDevice};
}

sub FRM_Catch($) {
  my $exception = shift;
  if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
  }
  return undef;
}

package Firmata_IO;

sub new {
	my ($class,$hash) = @_;
	return bless {
		hash => $hash,
	}, $class;
}

sub data_write {
   	my ( $self, $buf ) = @_;
   	my $hash = $self->{hash};
    main::Log3 $hash->{NAME},5,$hash->{FD}.">".join(",",map{sprintf"%02x",ord$_}split//,$buf);
   	main::DevIo_SimpleWrite($hash,$buf,undef);
}

sub data_read {
    my ( $self, $bytes ) = @_;
   	my $hash = $self->{hash};
    my $string = main::DevIo_SimpleRead($hash);
    if (defined $string ) {
   	    main::Log3 $hash->{NAME},5,$hash->{FD}."<".join(",",map{sprintf"%02x",ord$_}split//,$string);
   	}
    return $string;
}

package main;

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

sub FRM_I2C_Write
{
	my ($hash,$package)  = @_;
	
	if (defined (my $firmata = $hash->{FirmataDevice})) {
		COMMANDHANDLER: {
			$package->{direction} eq "i2cwrite" and do {
				$firmata->i2c_write($package->{i2caddress},split(" ",$package->{data}));
				last;
			};
			$package->{direction} eq "i2cread" and do {
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

sub
FRM_i2c_observer
{
	my ($data,$hash) = @_;
	Log3 $hash->{NAME},5,"onI2CMessage address: '".$data->{address}."', register: '".$data->{register}."' data: '".$data->{data}."'";
	FRM_forall_clients($hash,\&FRM_i2c_update_device,$data);
}

sub FRM_i2c_update_device
{
	my ($hash,$data) = @_;
	
	if (defined $hash->{I2C_Address} and $hash->{I2C_Address} eq $data->{address}) {
		CallFn($hash->{NAME}, "I2CRecFn", $hash, {
			i2caddress => $data->{address},
			direction  => "i2cread",
			reg        => $data->{register},
			nbyte      => scalar(@{$data->{data}}),
			data       => join (' ',@{$data->{data}})
		});
	} elsif (defined $hash->{"i2c-address"} && $hash->{"i2c-address"}==$data->{address}) {
		my $replydata = $data->{data};
		my @values = split(" ",ReadingsVal($hash->{NAME},"values",""));
		splice(@values,$data->{register},@$replydata, @$replydata);
		readingsBeginUpdate($hash);
		$hash->{STATE}="active";
		readingsBulkUpdate($hash,"values",join (" ",@values),1);
		readingsEndUpdate($hash,1);
	}
}

sub FRM_string_observer
{
	my ($string,$hash) = @_;
	Log3 $hash->{NAME},3,"received String_data: ".$string;
	readingsSingleUpdate($hash,"error",$string,1);
}

sub FRM_poll
{
	my ($hash) = @_;
	if (defined $hash->{SocketDevice} and defined $hash->{SocketDevice}->{FD}) {
		my ($rout, $rin) = ('', '');
    	vec($rin, $hash->{SocketDevice}->{FD}, 1) = 1;
    	my $nfound = select($rout=$rin, undef, undef, 0.1);
    	my $mfound = vec($rout, $hash->{SocketDevice}->{FD}, 1); 
		if($mfound && defined $hash->{FirmataDevice}) {
			$hash->{FirmataDevice}->poll();
		}
		return $mfound;
	} elsif (defined $hash->{FD}) {
		my ($rout, $rin) = ('', '');
    	vec($rin, $hash->{FD}, 1) = 1;
    	my $nfound = select($rout=$rin, undef, undef, 0.1);
    	my $mfound = vec($rout, $hash->{FD}, 1); 
		if($mfound && defined $hash->{FirmataDevice}) {
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
  		if ($InBytes && $InBytes>0 && defined $hash->{FirmataDevice}) {
			$hash->{FirmataDevice}->poll();
  		}
	}
}

######### following is code to be called from OWX: ##########

sub
FRM_OWX_Init($$)
{
	my ($hash,$args) = @_;
	my $ret = FRM_Init_Pin_Client($hash,$args,PIN_ONEWIRE);
	return $ret if (defined $ret);
	eval {
		my $firmata = FRM_Client_FirmataDevice($hash);
		my $pin = $hash->{PIN};
		$hash->{FRM_OWX_CORRELATIONID} = 0;
		$firmata->observe_onewire($pin,\&FRM_OWX_observer,$hash);
		$hash->{FRM_OWX_REPLIES} = {};
		$hash->{DEVS} = [];
		if ( AttrVal($hash->{NAME},"buspower","") eq "parasitic" ) {
			$firmata->onewire_config($pin,1);
		}
	};
	return FRM_Catch($@) if ($@);
	$hash->{STATE}="Initialized";
	InternalTimer(gettimeofday()+10, "OWX_Discover", $hash,0);
	return undef;
}

sub FRM_OWX_observer
{
	my ( $data,$hash ) = @_;
	my $command = $data->{command};
	COMMAND_HANDLER: {
		$command eq "READ_REPLY" and do {
			my $id = $data->{id};
			my $request = (defined $id) ? $hash->{FRM_OWX_REQUESTS}->{$id} : undef;
			unless (defined $request) {
				return unless (defined $data->{device});
				my $owx_device = FRM_OWX_firmata_to_device($data->{device});
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
			delete $hash->{FRM_OWX_REQUESTS}->{$id};
			last;			
		};
		($command eq "SEARCH_REPLY" or $command eq "SEARCH_ALARMS_REPLY") and do {
			my @owx_devices = ();
			foreach my $device (@{$data->{devices}}) {
				push @owx_devices, FRM_OWX_firmata_to_device($device);
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

########### functions implementing interface to OWX ##########

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

sub FRM_OWX_firmata_to_device
{
	my $device = shift;
	return sprintf ("%02X.%02X%02X%02X%02X%02X%02X.%02X",$device->{family},@{$device->{identity}},$device->{crc});
}

sub FRM_OWX_Verify {
	my ($hash,$dev) = @_;
	foreach my $found (@{$hash->{DEVS}}) {
		if ($dev eq $found) {
			return 1;
		}
	}
	return 0;
}

sub FRM_OWX_Alarms {
	my ($hash) = @_;

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );
	$hash->{ALARMDEVS} = undef;			
	$firmata->onewire_search_alarms($hash->{PIN});
	my $times = AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
	for (my $i=0;$i<$times;$i++) {
		if (FRM_poll($hash->{IODev})) {
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

sub FRM_OWX_Reset {
	my ($hash) = @_;
	#-- get the interface
	my $frm = $hash->{IODev};
	return undef unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return undef unless ( defined $firmata and defined $pin );

	$firmata->onewire_reset($pin);
	
	return 1;
}

sub FRM_OWX_Complex ($$$$) {
	my ( $hash, $owx_dev, $data, $numread ) = @_;

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
		my $times = AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
		for (my $i=0;$i<$times;$i++) {
			if (FRM_poll($hash->{IODev})) {
				if (defined $hash->{FRM_OWX_REPLIES}->{$owx_dev}) {
					$res .= $hash->{FRM_OWX_REPLIES}->{$owx_dev};
					return $res;
				}
			} else {
				select (undef,undef,undef,0.05);
			}
		}
	}
	return $res;
}

########################################################################################
#
# OWX_Discover_FRM - Discover devices on the 1-Wire bus via internal firmware
#
# Parameter hash = hash of bus master
#
# Return 0  : error
#        1  : OK
#
########################################################################################

sub FRM_OWX_Discover ($) {

	my ($hash) = @_;

	#-- get the interface
	my $frm = $hash->{IODev};
	return 0 unless defined $frm;
	my $firmata = $frm->{FirmataDevice};
	my $pin     = $hash->{PIN};
	return 0 unless ( defined $firmata and defined $pin );
	my $old_devices = $hash->{DEVS};
	$hash->{DEVS} = undef;			
	$firmata->onewire_search($hash->{PIN});
	my $times = AttrVal($hash,"ow-read-timeout",1000) / 50; #timeout in ms, defaults to 1 sec
	for (my $i=0;$i<$times;$i++) {
		if (FRM_poll($hash->{IODev})) {
			if (defined $hash->{DEVS}) {
				return 1;
			}
		} else {
			select (undef,undef,undef,0.05);
		}
	}
	$hash->{DEVS} = $old_devices;
	return 1;
}

1;

=pod
=begin html

<a name="FRM"></a>
<h3>FRM</h3>
<ul>
  connects fhem to <a href="http://www.arduino.cc">Arduino</a> using
  the <a href="http://www.firmata.org">Firmata</a> protocol. 
  <br><br>
  A single FRM device can serve multiple FRM-clients.<br><br>
  Clients of FRM are:<br><br>
  <a href="#FRM_IN">FRM_IN</a> for digital input<br>
  <a href="#FRM_OUT">FRM_OUT</a> for digital out<br>
  <a href="#FRM_AD">FRM_AD</a> for analog input<br>
  <a href="#FRM_PWM">FRM_PWM</a> for analog output (pulse_width_modulated)<br>
  <a href="#FRM_RGB">FRM_RGB</a> control multichannel/RGB-LEDs by pwm<br>
  <a href="#FRM_SERVO">FRM_SERVO</a> for pwm-controled servos as being used in modelmaking<br>
  <a href="#FRM_LCD">FRM_LCD</a> output text to LCD attached via I2C<br>
  <a href="#FRM_I2C">FRM_I2C</a> to read data from integrated circutes attached
   to Arduino supporting the <a href="http://en.wikipedia.org/wiki/I%C2%B2C">
   i2c-protocol</a>.<br>
  <a href="#OWX">OWX</a> to read/write sensors and actors on 1-Wire bus.<br><br>
   
  Each client stands for a Pin of the Arduino configured for a specific use 
  (digital/analog in/out) or an integrated circuit connected to Arduino by i2c.<br><br>
  
  Note: this module is based on <a href="https://github.com/ntruchsess/perl-firmata">Device::Firmata</a> module (perl-firmata).
  perl-firmata is included in FHEM-distributions lib-directory. You can download the latest version <a href="https://github.com/amimoto/perl-firmata/archive/master.zip">as a single zip</a> file from github.<br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.<br><br>
  
  <a name="FRMdefine"></a>
  <b>Define</b><br>
  <ul><br>
  <code>define &lt;name&gt; FRM {&lt;device&gt; | &lt;port&gt; [global]}</code> <br>
  Specifies the FRM device.<br>
  <br>
  <li>USB-connected devices:<br><br>
      <code>&lt;device&gt;</code> specifies the serial port to communicate with the Arduino.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the Arduino by the
      following command:<br>
      <code>modprobe usbserial vendor=0x03eb product=0x204b</code></br>
      In this case the device is most probably /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@38400<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>
      
      The Arduino has to run either 'StandardFirmata' or 'ConfigurableFirmata'.
      StandardFirmata supports Digital and Analog-I/O, Servo and I2C. In addition
      to that ConfigurableFirmata supports 1-Wire, Stepper-motors and allows to
      connect via ethernet in client mode. <br><br>
      
      You can find StandardFirmata in the Arduino-IDE under 'Examples->Firmata->StandardFirmata<br><br>
      ConfigurableFirmata has to be installed manualy. See <a href="https://github.com/firmata/arduino/tree/configurable/examples/ConfigurableFirmata">
      ConfigurableFirmata</a> on GitHub or <a href="http://www.fhemwiki.de/wiki/Arduino_Firmata#Installation_ConfigurableFirmata">FHEM-Wiki</a><br> 
  </li>
  <br>
  <li>Network-connected devices:<br><br>
      <code>&lt;port&gt;</code> specifies the port the FRM device listens on. If <code>global</code> is
      specified the socket is bound to all local ip-addresses, otherwise to localhost
      only.<br>
      The Arduino must ConfigurableFirmata. The connection is initiated by the arduino
      in client-mode. Therefor the ip-address and port of the fhem-server has to be 
      configured an the arduino, so it knows where to connect to.<br>
      As of now only a single Arduino per FRM-device configured is supported. Multiple
      Arduinos may connect to different FRM-devices configured for different ports.<br>
      ConfigurableFirmata has to be installed manualy. See <a href="https://github.com/firmata/arduino/tree/configurable/examples/ConfigurableFirmata">
      ConfigurableFirmata</a> on GitHub or <a href="http://www.fhemwiki.de/wiki/Arduino_Firmata#Installation_ConfigurableFirmata">FHEM-Wiki</a><br> 
  </li>
  <br>
  <li>
	  If the device is called none, then no device will be opened, so you
	  can experiment without hardware attached.<br>
  </li>
  </ul>
  
  <br>
  <a name="FRMset"></a>
  <b>Set</b>
  <ul>
  <li>
    <code>set &lt;name&gt; init</code><br>
    reinitializes the FRM-Client-devices configured for this Arduino
  </li><br>
  <li>
    <code>set &lt;name&gt; reset</code><br>
    does a complete reset of FRM by disconnecting from, reconnecting to and reinitializing the Arduino and FRM internals and all attached FRM-client-devices
  </li>
  </ul>
  <br><br>
  
  <a name="FRMattr"></a>
  <b>Attributes</b><br>
  <ul>
      <li>i2c-config<br>
      Configure the arduino for ic2 communication. This will enable i2c on the
      i2c_pins received by the capability-query issued during initialization of FRM.<br>
      As of Firmata 2.3 you can set a delay-time (in microseconds) that will be inserted into i2c
      protocol when switching from write to read.<br>
      See: <a href="http://www.firmata.org/wiki/Protocol#I2C">Firmata Protocol details about I2C</a><br>
      </li><br>
      <li>sampling-interval<br>
      Configure the interval Firmata reports data to FRM. Unit is milliseconds.<br>
      See: <a href="http://www.firmata.org/wiki/Protocol#Sampling_Interval">Firmata Protocol details about Sampling Interval</a></br>
      </li>
    </ul>
  </ul>
<br>

=end html
=cut

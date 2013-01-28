##############################################
package main;

use strict;
use warnings;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata::IO;
use Device::Firmata::Protocol;
use Device::Firmata::Platform;

sub FRM_Set($@);
sub FRM_Attr(@);
sub Log($$);

#####################################
sub FRM_Initialize($) {
	my ($hash) = @_;
	
	require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

	# Provider
	$hash->{Clients} =
	  ":FRM_IN:FRM_OUT:FRM_AD:FRM_PWM:FRM_I2C:";
	$hash->{ReadyFn} = "FRM_Ready";  
	$hash->{ReadFn}  = "FRM_Read";

	# Consumer
	$hash->{DefFn}    = "FRM_Define";
	$hash->{UndefFn}  = "FRM_Undef";
	$hash->{GetFn}    = "FRM_Get";
	$hash->{SetFn}    = "FRM_Set";
	$hash->{AttrFn}   = "FRM_Attr";
  
	$hash->{AttrList} = "model:nano dummy:1,0 loglevel:0,1,2,3,4,5 sampling-interval i2c-config $main::readingFnAttributes";
}

#####################################
sub FRM_Define($$) {
	my ( $hash, $def ) = @_;
	my @a = split( "[ \t][ \t]*", $def );
	my $po;
	
	DevIo_CloseDev($hash);	

	my $name = $a[0];
	my $dev  = $a[2];

	if ( $dev eq "none" ) {
		Log 1, "FRM device is none, commands will be echoed only";
		$main::attr{$name}{dummy} = 1;
		return undef;
	}
	$hash->{DeviceName} = $dev;
	my $ret = DevIo_OpenDev($hash, 0, "FRM_DoInit");
	main::readingsSingleUpdate($hash,"state","initialized", 1);
	return $ret;	
}

#####################################
sub FRM_Undef($) {
	my $hash = @_;
	FRM_forall_clients($hash,\&FRM_Client_Unassign,undef);
	DevIo_CloseDev($hash);
	my $device = $hash->{FirmataDevice};
	if (defined $device) {
		if (defined $device->{io}) {
			delete $hash->{FirmataDevice}->{io}->{handle} if defined $hash->{FirmataDevice}->{io}->{handle};
			delete $hash->{FirmataDevice}->{io};
		}
		delete $device->{protocol} if defined $device->{protocol};
		delete $hash->{FirmataDevice};
	}
	return undef;
}

#####################################
sub FRM_Set($@) {
	my ( $hash, @a ) = @_;
	my $u1 = "Usage: set <name> reset/reinit\n";

	return $u1 if ( int(@a) < 2 );
	my $name = $hash->{DeviceName};

	if ( $a[1] eq 'reset' ) {
		DevIo_CloseDev($hash);	
		my $ret = DevIo_OpenDev($hash, 0, "FRM_DoInit");
		return $ret;	
	} elsif ( $a[1] eq 'reinit' ) {
		FRM_forall_clients($hash,\&FRM_Init_Client,undef);
	} else {
		return "Unknown argument $a[1], supported arguments are 'reset', 'reinit'";
	}
	return undef;
}

#####################################
sub FRM_Get($@) {
	my ( $hash, @a ) = @_;
	return "\"get FRM\" needs only one parameter" if ( @a != 2 );
	shift @a;
	my $spec = shift @a;
	if ( $spec eq "firmware" ) {
		if (defined $hash->{FirmataDevice}) {
			return $hash->{FirmataDevice}->{metadata}->{firmware};
		} else {
			return "not connected to FirmataDevice";
		}	
	} elsif ( $spec eq "version" ) {
		if (defined $hash->{FirmataDevice}) {
			return $hash->{FirmataDevice}->{metadata}->{firmware_version};
		} else {
			return "not connected to FirmataDevice";
		}
	}
}

#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub FRM_Read($) {
	my ( $hash ) = @_;
	my $device = $hash->{FirmataDevice} or return;
	$device->poll();
}

sub FRM_Ready($) {

	my ($hash) = @_;
	return DevIo_OpenDev($hash, 1, "FRM_DoInit") if($hash->{READINGS}{state} eq "disconnected");
}

sub FRM_Attr(@) {
	my ($command,$name,$attribute,$value) = @_;
	if ($command eq "set") {
		$main::attr{$name}{$attribute}=$value;
		if ($attribute eq "sampling-interval" 
			or $attribute eq "i2c-config" ) {
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
			$firmata->sampling_interval(main::AttrVal($name,$attribute,"1000"));
		} elsif ($attribute eq "i2c-config") {
			my $i2cattr = main::AttrVal($name,$attribute,undef);
			if (defined $i2cattr) {
				my @a = split(" ", $i2cattr);
				my $i2cpins = $firmata->{metadata}{i2c_pins}; 
				if (defined $i2cpins and scalar @$i2cpins) {
					foreach my $i2cpin (@$i2cpins) {
						$firmata->pin_mode($i2cpin,PIN_I2C);
					}
					$firmata->i2c_config(@a);
					$firmata->observe_i2c(\&FRM_i2c_observer,$hash);	
				} else {
					Log 1,"Error, arduino doesn't support I2C";
				}
			}
		}
	}
}

sub FRM_DoInit($) {
	
	my ($hash) = @_;
	
	my $name = $hash->{NAME};
	$hash->{loglevel} = main::GetLogLevel($name);
	
  	my $firmata_io = Firmata_IO->new($hash);
	my $device = Device::Firmata::Platform->attach($firmata_io) or return 1;

	$hash->{FirmataDevice} = $device;
	$device->observe_string(\&FRM_string_observer,$hash);
	
	my $found; # we cannot call $device->probe() here, as it doesn't select bevore read, so it would likely cause IODev to close the connection on the first attempt to read from empty stream
	do {
		$device->system_reset();
		$device->firmware_version_query();
		for (my $i=0;$i<50;$i++) {
			if (FRM_poll($hash)) {
				if ($device->{metadata}{firmware} && $device->{metadata}{firmware_version}){
					$device->{protocol}->{protocol_version} = $device->{metadata}{firmware_version};
					$main::defs{$name}{firmware} = $device->{metadata}{firmware};
					$main::defs{$name}{firmware_version} = $device->{metadata}{firmware_version};
					$device->analog_mapping_query();
					$device->capability_query();
					for (my $j=0;$j<100;$j++) {
						if (FRM_poll($hash)) {
							if (($device->{metadata}{analog_mappings}) and ($device->{metadata}{capabilities})) {
								my $inputpins = $device->{metadata}{input_pins};
								$main::defs{$name}{input_pins} = join(",", sort{$a<=>$b}(@$inputpins));
								my $outputpins = $device->{metadata}{output_pins};
								$main::defs{$name}{output_pins} =  join(",", sort{$a<=>$b}(@$outputpins));
								my $analogpins = $device->{metadata}{analog_pins};
								$main::defs{$name}{analog_pins} = join(",", sort{$a<=>$b}(@$analogpins));
								my $i2cpins = $device->{metadata}{i2c_pins};
								$main::defs{$name}{i2c_pins} = join(",", sort{$a<=>$b}(@$i2cpins));
								my $onewirepins = $device->{metadata}{onewire_pins};
								$main::defs{$name}{onewire_pins} = join(",", sort{$a<=>$b}(@$onewirepins));
								$found = 1;
								last;
							}
						} else {
							select (undef,undef,undef,0.1);
						} 
					}
					$found = 1;
					last;
				}
			} else {
				select (undef,undef,undef,0.1);
			}
		}
	} while (!$found);
	
	FRM_apply_attribute($hash,"sampling-interval");
	FRM_apply_attribute($hash,"i2c-config");
	FRM_forall_clients($hash,\&FRM_Init_Client,undef);
	
	return undef;
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
FRM_Init_Client($$) {
	my ($hash,$args) = @_;
	$hash->{loglevel} = main::GetLogLevel($hash->{NAME});
	main::CallFn($hash->{NAME},"InitFn",$hash,$args);
}

sub
FRM_Init_Pin_Client($$) {
	my ($hash,$args) = @_;
  	my $u = "wrong syntax: define <name> FRM_XXX pin";
  	return $u if(int(@$args) < 3);
  	$hash->{PIN} = @$args[2];
}

sub
FRM_Client_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  main::readingsSingleUpdate($hash,"state","defined",0);
  
  main::AssignIoPort($hash);	
  FRM_Init_Client($hash,\@a);
    
  return undef;
}

sub
FRM_Client_Undef($$)
{
  my ($hash, $name) = @_;
}

sub
FRM_Client_Unassign($)
{
  my ($dev) = @_;
  delete $dev->{IODev} if defined $dev->{IODev};
  main::readingsSingleUpdate($dev,"state","defined",0);  
}

package Firmata_IO {
	
	sub new {
		my ($class,$hash) = @_;
		return bless {
			hash => $hash,
		}, $class;
	}

	sub data_write {
    	my ( $self, $buf ) = @_;
	    main::Log 5, ">".join(",",map{sprintf"%02x",ord$_}split//,$buf);
    	main::DevIo_SimpleWrite($self->{hash},$buf);
	}

	sub data_read {
	    my ( $self, $bytes ) = @_;
	    my $string = main::DevIo_SimpleRead($self->{hash});
	    if (defined $string ) {
    	    main::Log 5,"<".join(",",map{sprintf"%02x",ord$_}split//,$string);
    	}
	    return $string;
	}
}

sub
FRM_i2c_observer
{
	my ($data,$hash) = @_;
	main::Log 5,"onI2CMessage address: '".$data->{address}."', register: '".$data->{register}."' data: '".$data->{data}."'";
	FRM_forall_clients($hash,\&FRM_i2c_update_device,$data);
}

sub FRM_i2c_update_device
{
	my ($hash,$data) = @_;
	if (defined $hash->{"i2c-address"} && $hash->{"i2c-address"}==$data->{address}) {
		my $replydata = $data->{data};
		my @values = split(" ",main::ReadingsVal($hash->{NAME},"values",""));
		splice(@values,$data->{register},@$replydata, @$replydata);
		main::readingsBeginUpdate($hash);
		main::readingsBulkUpdate($hash,"state","active",0);
		main::readingsBulkUpdate($hash,"values",join (" ",@values),1);
		main::readingsEndUpdate($hash,undef);
	}
}

sub FRM_string_observer
{
	my ($string,$hash) = @_;
	main::Log 4, "received String_data: ".$string;
	main::readingsSingleUpdate($hash,"error",$string,1);
}

sub FRM_poll
{
	my ($hash) = @_;
	my ($rout, $rin) = ('', '');
    vec($rin, $hash->{FD}, 1) = 1;
    my $nfound = select($rout=$rin, undef, undef, 0.1);
    my $mfound = vec($rout, $hash->{FD}, 1); 
	if($mfound) {
		$hash->{FirmataDevice}->poll();
	}
	return $mfound;
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
  <a href="#FRM_PWM">FRM_PWM</a> for analog (pulse_width_modulated) output<br>
  <a href="#FRM_I2C">FRM_I2C</a> to read data from integrated circutes attached
   to Arduino supporting the <a href="http://en.wikipedia.org/wiki/I%C2%B2C">
   i2c-protocol</a>.<br><br>
   
  Each client stands for a Pin of the Arduino configured for a specific use 
  (digital/analog in/out) or an integrated circuit connected to Arduino by i2c.<br><br>
  
  Note: this module requires the <a href="https://github.com/amimoto/perl-firmata">Device::Firmata</a> module (perl-firmata).
  You can download it <a href="https://github.com/amimoto/perl-firmata/archive/master.zip">as a single zip</a> file from github.
  Copy 'lib/Device' (with all subdirectories) to e.g. FHEM directory (or other location within perl include path)<br><br>

  Note: this module may require the Device::SerialPort or Win32::SerialPort
  module if you attach the device via USB and the OS sets strange default
  parameters for serial devices.<br><br>
  
  <a name="FRMdefine"></a>
  <b>Define</b>
  <ul>
  <code>define &lt;name&gt; FRM &lt;device&gt;</code> <br>
  Specifies the FRM device.   </ul>
  
    <br>
    <ul>
    USB-connected devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the Arduino.
      The name of the serial-device depends on your distribution, under
      linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a
      cdc_acm module, you can force usbserial to handle the Arduino by the
      following command:<ul>modprobe usbserial vendor=0x03eb
      product=0x204b</ul>In this case the device is most probably
      /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @
      character, e.g.: /dev/ttyACM0@38400<br><br>

      If the baudrate is "directio" (e.g.: /dev/ttyACM0@directio), then the
      perl module Device::SerialPort is not needed, and fhem opens the device
      with simple file io. This might work if the operating system uses sane
      defaults for the serial parameters, e.g. some Linux distributions and
      OSX.  <br><br>
      
      The Arduino has to run 'StandardFirmata'. You can find StandardFirmata
      in the Arduino-IDE under 'Examples->Firmata->StandardFirmata<br><br>

    </ul>
    Network-connected devices:<br><ul>
    &lt;device&gt; specifies the host:port of the device. E.g.
    192.168.0.244:2323<br>
    As of now EthernetFirmata is still eperimental.
    </ul>
    <br>
    If the device is called none, then no device will be opened, so you
    can experiment without hardware attached.<br>
  </ul>
  
  <br>
  <a name="FRMset"></a>
  <b>Set</b>
  <ul>
  N/A<br>
  </ul><br>
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

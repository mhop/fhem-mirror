#$Id$
#Based on GPIO4 by Peter J. Flathmann (peter dot flathmann at web dot de)
#and various extension to the GPIO4 Module by members of the FHEM forum
#and RoBue to access 1-Wire-Clones with ID: 28 53 44 54 xx xx xx 

#Possible Extensions:
#Writing to the switches is not supported (but I also don't have the HW to test that)

package main;
use strict;
use warnings;
#use Data::Dumper;
use Time::HiRes qw ( gettimeofday tv_interval );
use Scalar::Util qw(looks_like_number);
#use vars qw{%attr %defs};
eval "use RPi::DHT;1" or my $DHT_missing = "yes";

sub RPI_1Wire_Initialize {
	my ($hash) = @_;

	$hash->{DefFn}		 = "RPI_1Wire_Define";
	$hash->{FW_detailFn}  = "RPI_1Wire_Detail";
	$hash->{FW_deviceOverview} = 1;
	$hash->{AttrFn}		 = 	"RPI_1Wire_Attr";
	$hash->{UndefFn}	 = "RPI_1Wire_Undef";
	$hash->{NotifyFn}	 = "RPI_1Wire_Notify";
	$hash->{GetFn}		 = "RPI_1Wire_Get";
	$hash->{SetFn}		 = "RPI_1Wire_Set";
	$hash->{AttrList}	 = "tempOffset tempFactor pollingInterval ".
							"mode:blocking,nonblocking,timer ".
							"faultvalues ".
							"decimals:0,1,2,3 ".
							"$readingFnAttributes";
}

my $w1_path="/sys/bus/w1/devices";
my $ms_path="/sys/devices/w1_bus_master";
my $dht_path="/sys/devices/platform/dht11@";

my %RPI_1Wire_Devices =
(
	'10' => {"name"=>"DS18S20", "type"=>"temperature", "path"=>"w1_slave"},
	'12' => {"name"=>"DS2406", "type"=>"switch", "path"=>"state"}, # Not supported by old module
	'19' => {"name"=>"DS28E17", "type"=>"i2c bridge"},
	'1c' => {"name"=>"DS28E04", "type"=>"eeprom"},
	'1d' => {"name"=>"DS2423", "type"=>"counter", "path"=>"w1_slave"},
	'26' => {"name"=>"DS2438", "type"=>"voltage", "path"=>"temperature,vdd,vad"},
	'28' => {"name"=>"DS18B20", "type"=>"temperature", "path"=>"w1_slave"},
	'29' => {"name"=>"DS2408", "type"=>"8p-switch", "path"=>"output"},
	'3a' => {"name"=>"DS2413", "type"=>"2p-switch", "path"=>"state"}, # not supported by old module
	'3b' => {"name"=>"DS1825", "type"=>"temperature", "path"=>"w1_slave"},
	'42' => {"name"=>"DS28EA00", "type"=>"temperature", "path"=>"w1_slave"},
	'DHT11' => {"name"=>"DHT11", "type"=>"dht", "path"=>"11"},
	'DHT22' => {"name"=>"DHT22", "type"=>"dht", "path"=>"22"},
	'BUSMASTER' => {"name"=>"BUSMASTER", "type"=>"BUSMASTER", "path"=>""}
);

sub RPI_1Wire_Notify {
	my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled

	my $devName = $dev_hash->{NAME}; # Device that created the events
#	Log3 $ownName, 1, $ownName." Notify from $devName";
	my $events = deviceEvents($dev_hash,1);
	if ($devName eq "global" and grep(m/^INITIALIZED|REREADCFG$/, @{$events})) {
		my $def=$own_hash->{DEF};
		$def="" if (!defined $def); 
		#GetDevices is triggering the autocreate calls, but this is not yet working (autocreate not ready?) so delay this by 10 seconds
		RPI_1Wire_Init($own_hash,$def,0);
		InternalTimer(gettimeofday()+10, "RPI_1Wire_GetDevices", $own_hash, 0) if $own_hash->{DEF} =~ /BUSMASTER/;
	}
}

sub RPI_1Wire_Define {			#
	my ($hash, $def) = @_;
	Log3 $hash->{NAME}, 2, $hash->{NAME}." Define: $def";
	$hash->{setList}	= {
		"update" => "noArg",
		"scan" => "noArg",
		"precision" => "9,10,11,12",
		"conv_time" => "textField",
		"therm_bulk_read" => "on,off",
	};
	$hash->{getList}= {
		"udev"      => "noArg",
	};
	
	$hash->{NOTIFYDEV} = "global";
		if ($init_done) {
			Log3 $hash->{NAME}, 2, "Define init_done: $def";
			$def =~ s/^\S+\s*\S+\s*//; #Remove devicename and type
			my $ret=RPI_1Wire_Init($hash,$def,1);
			return $ret if $ret;
	}
	return;
}
################################### 
sub RPI_1Wire_Init {				#
	my ( $hash, $args, $check ) = @_;
	Log3 $hash->{NAME}, 2, $hash->{NAME}.": Init: $args $check";
	if (! -e "$w1_path") {
		$hash->{STATE} ="No 1-Wire Bus found";
		Log3 $hash->{NAME}, 3, $hash->{NAME}.": Init: $hash->{STATE}";
		return $hash->{STATE};
	}

	my @a = split("[ \t]+", $args);
	if (@a!=1)	{
		return "syntax: define <name> RPI_1Wire <id>|BUSMASTER|DHT11-<gpio>|DHT22-<gpio>";
	}
	my $name = $hash->{NAME};
	my $arg=$a[0];
	$hash->{helper}{write}="";
	$hash->{helper}{duration}=0;
	my $device="";
	my $family="";
	my $id="";
	my $dev=0;
	if ($arg =~ /(BUSMASTER)(-\d)?$/) {
		$device=$1;
		$family=$1;
		$id=1;
		$id=abs($2) if defined $2; #abs to get rid of the "-"
		if (! -e $ms_path.$id) {
			readingsSingleUpdate($hash,"failreason","Device not found",0);
			return "Device $device $id does not exist";
		}
	} elsif ($arg =~ /DHT(11|22)-(\d+)/) {
		return "Module RPi::DHT missing (see https://github.com/bublath/rpi-dht)" if defined $DHT_missing;
		$id=$2;
		$family="DHT".$1;
		$device=$family;
	} else {
		return "Device $arg does not exist" if (! -e "$w1_path/$arg" and $check==1); #Only quit if coming from interactive define
		($family, $id) = split('-',$arg);
		return "Unknown device family $family" if !defined $RPI_1Wire_Devices{$family};
		$device=$RPI_1Wire_Devices{$family}{name};
	}
	$hash->{id}=$id;
	$hash->{model}=$device; #for statistics
	$hash->{family}=$family;
	my $type=$RPI_1Wire_Devices{$family}{type};
	
	#remove set commands that make no sense
	if ($device ne "BUSMASTER") {
		delete($hash->{setList}{scan});
		delete($hash->{setList}{therm_bulk_read});
		RPI_1Wire_DeviceUpdate($hash);
	} else {
		my $bulk=ReadingsVal($name,"therm_bulk_read","off");
		if (! -w $ms_path.$id."/therm_bulk_read") {
			delete($hash->{setList}{therm_bulk_read});
			delete($hash->{setList}{update});
			readingsSingleUpdate($hash, 'therm_bulk_read', "off",0);
		} elsif ($bulk eq "on") {
			$hash->{setList}{update}="noArg"; #Restore set command in case it was deleted previously
			RPI_1Wire_DeviceUpdate($hash);
		}
	}
	if ($type ne "temperature") {
		delete($hash->{setList}{precision});
		delete($hash->{setList}{conv_time});
	} else {
		if (!(-w "$w1_path/$arg/conv_time")) {
			delete($hash->{setList}{conv_time});
			$hash->{helper}{write}.="conv_time ";
		}
		if (!(-w "$w1_path/$arg/resolution")) {
			delete($hash->{setList}{precision});
			$hash->{helper}{write}.="resolution ";
		}
	}
	RPI_1Wire_Set($hash, $name, "setfromreading");
	#Restore previous settings
	my $precision=ReadingsVal($name,"temperature",undef);
	my $conv_time=ReadingsVal($name,"conv_time",undef);
	if (defined $precision) {
		RPI_1Wire_SetPrecision($hash,$precision);
	}
	if (defined $conv_time) {
		RPI_1Wire_SetConversion($hash,$conv_time);
	}
	RPI_1Wire_GetConfig($hash);
	$hash->{STATE} = "Initialized";
	Log3 $hash->{NAME}, 3, $hash->{NAME}.": Init done for $device $family $id $type";
	return;
}

sub RPI_1Wire_GetDevices {
	my ($hash) = @_;
	Log3 $hash->{NAME}, 3 , $hash->{NAME}.": GetDevices";
	my @devices;
	if (open(my $fh, "<", $ms_path.$hash->{id}."/w1_master_slaves")) {
		while (my $device = <$fh>) {
			chomp $device; #remove \n
			Log3 $hash->{NAME}, 4 , $hash->{NAME}.": Found device $device";
			push @devices,$device;
			my $found=0;
			foreach my $dev ( sort keys %main::defs ) {
				if ($defs{$dev}->{TYPE} eq "RPI_1Wire" && $defs{$dev}->{DEF} eq $device) { $found=1; }
			}
			if ($found == 0) {
				my ($family, $id) = split('-',$device);
				if (defined $RPI_1Wire_Devices{$family}) { #only autocreate for known devices
					Log3 $hash->{NAME}, 4 , $hash->{NAME}.": Autocreate $device";
					DoTrigger("global", "UNDEFINED ".$RPI_1Wire_Devices{$family}{name}."_$id RPI_1Wire $device"); #autocreate
				}
			}
		}
		close($fh);
	}
	$hash->{devices}=join(" ",@devices);
	return;
}

sub RPI_1Wire_DeviceUpdate {
	my ($hash) = @_;
	my $name=$hash->{NAME};
	my $family=$hash->{family};
	if (!defined $family) {
		#For safety, if a device was not ready during startup it sometimes is not properly initialized when being reconnected
		return RPI_1Wire_Init($hash,$hash->{DEF},0);
	}
	my $pollingInterval = AttrVal($name,"pollingInterval",60);
	return if $pollingInterval<1;
	Log3 $name, 4 , $name.": DeviceUpdate($hash->{NAME}), pollingInterval:$pollingInterval";

	my $mode=AttrVal($name,"mode","nonblocking");
	if ($family eq "BUSMASTER") {
		if (ReadingsVal($name,"therm_bulk_read","off") eq "on") {
			$mode="bulk_read";
		} else {
			return; #once set to "off" the timer won't be started again by exiting here
		}
	}
	if ($mode eq "nonblocking") {
		delete($hash->{helper}{RUNNING_PID}) if(exists($hash->{helper}{RUNNING_PID}));
		$hash->{helper}{RUNNING_PID} = BlockingCall("RPI_1Wire_Poll", $hash,"RPI_1Wire_FinishFn");
		Log3 $name, 5, $name.": BlockingCall for $name";
	} elsif ($mode eq "blocking") {
		my $ret=RPI_1Wire_Poll($hash);
		RPI_1Wire_FinishFn($ret);
	} elsif ($mode eq "timer") {
		#In case of "hack" using minimal conv_time, trigger conversion twice
		my $ret=RPI_1Wire_Poll($hash);
		#RPI_1Wire_FinishFn($ret); First result can be ignored
		RemoveInternalTimer($hash);
		#Table of reasonable conv_times?
		InternalTimer(gettimeofday()+1.5, "RPI_1Wire_FromTimer", $hash, 0);
		return;
	} elsif ($mode eq "bulk_read") {
		$hash->{helper}{RUNNING_PID} = BlockingCall("RPI_1Wire_TriggerBulk", $hash,undef);
		Log3 $hash->{NAME}, 3, $hash->{NAME}.": Triggered bulk read";
	}
	RemoveInternalTimer($hash);
	InternalTimer(gettimeofday()+$pollingInterval, "RPI_1Wire_DeviceUpdate", $hash, 0);
	return;
}

sub RPI_1Wire_TriggerBulk {
	my ($hash) = @_;
	my $path=$ms_path.$hash->{id}."/therm_bulk_read";
	if (open(my $fh, ">", $path)) {
		print $fh "trigger\n";
		close($fh);
	}
}

sub RPI_1Wire_FromTimer {
	my ($hash) = @_;
	my $name=$hash->{NAME};
	my $ret=RPI_1Wire_Poll($hash);
	#Second call is where we read the "real" value
	RPI_1Wire_FinishFn($ret);
	RemoveInternalTimer($hash);
	my $pollingInterval = AttrVal($name,"pollingInterval",60);
	InternalTimer(gettimeofday()+$pollingInterval, "RPI_1Wire_DeviceUpdate", $hash, 0);
}

sub RPI_1Wire_SetPrecision {
	my ( $hash, $precision)= @_;
	my $fh;
	if (!looks_like_number($precision) || $precision < 9 || $precision>12) {
		return "Precision needs to be a number between 9 and 12";
	}
	my $path="$w1_path/$hash->{DEF}/resolution";
	if (open($fh, ">", $path)) {
		print $fh $precision;
		close($fh);
	} else {
		return "Error writing to $w1_path/$hash->{DEF}/resolution";
	}
	return;
}

sub RPI_1Wire_SetConversion {
	my ( $hash, $conv_time)= @_;
	my $fh;
	my $path="$w1_path/$hash->{DEF}/conv_time";
	if (open($fh, ">", $path)) {
		print $fh $conv_time;
		close($fh);
	} else {
		return "Error writing to $w1_path/$hash->{DEF}/conv_time";
	}
	return;
}

sub RPI_1Wire_Set {

	my ( $hash, $name, @args ) = @_;
	return unless defined $hash->{setList};
	my %sets=%{$hash->{setList}};
	### Check Args
	my $numberOfArgs  = int(@args);
	return "RPI_1Wire_Set: No cmd specified for set" if ( $numberOfArgs < 1 );
	my $device=$hash->{DEF};

	my $cmd = shift @args;
	if (!exists($sets{$cmd}))  {
		my @cList;
		foreach my $k (keys %sets) {
			my $opts = undef;
			$opts = $sets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		}
		return "RPI_1Wire_Set: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling

	if ($cmd eq "precision" and @args==1) {
		my $ret=RPI_1Wire_SetPrecision($hash,$args[0]);
		return $ret if defined $ret;
		RPI_1Wire_GetConfig($hash);
	} elsif ($cmd eq "scan") {
		RPI_1Wire_GetDevices($hash);
		return;
	} elsif ($cmd eq "update") {
		RPI_1Wire_GetConfig($hash);
		return RPI_1Wire_DeviceUpdate($hash);
	} elsif ($cmd eq "conv_time" and @args==1) {
		my $ret=RPI_1Wire_SetConversion($hash,$args[0]);
		return $ret if defined $ret;
		RPI_1Wire_GetConfig($hash);
	} elsif ($cmd eq "therm_bulk_read" and @args==1) {
		if ($args[0] eq "on") {
			readingsSingleUpdate($hash, 'therm_bulk_read', "on",1);
			return RPI_1Wire_DeviceUpdate($hash);
		} else {
			readingsSingleUpdate($hash, 'therm_bulk_read', "off",1);
		}
	}
	return;
}

sub RPI_1Wire_Get {
	my ($hash, $name, @args) = @_;
	return unless defined $hash->{getList};
	my $family=$hash->{family};
	return unless defined $family;
	my $type=$RPI_1Wire_Devices{$family}{type};
	return unless $type eq "temperature";
	return unless $hash->{helper}{write} ne "";
	my %gets=%{$hash->{getList}};
	my $numberOfArgs  = int(@args);
	return "RPI_1Wire_Get: No cmd specified for get" if ( $numberOfArgs < 1 );

	my $cmd = shift @args;

	if (!exists($gets{$cmd}))  {
		my @cList;
		foreach my $k (keys %gets) {
			my $opts = undef;
			$opts = $gets{$k};

			if (defined($opts)) {
				push(@cList,$k . ':' . $opts);
			} else {
				push (@cList,$k);
			}
		}
		return "RPI_1Wire_Get: Unknown argument $cmd, choose one of " . join(" ", @cList);
	} # error unknown cmd handling

	if ($cmd eq "udev") {
		my $ret= "In order to be able to use some functionality , write access to certain devices is required\n";
		 $ret.= "Recommended way is to create a udev script\n\n";
		 $ret.= "Create a text file <b>99-w1.rules</b> with the content below and copy it to <b>/etc/udev/rules.d/</b>\n";
		 $ret.= "You also need to make sure your fhem user is in the gpio group\n\n";
		
		my $script= "SUBSYSTEM==\"w1*\", PROGRAM=\"/bin/sh -c \'\\\n";
		$script .= "chown -R root:gpio /sys/devices/w1*;\\\n";
		$script .= "chmod g+w /sys/devices/w1_bus_master*/therm_bulk_read;\\\n";
		$script .= "chmod g+w /sys/devices/w1_bus_master*/*/resolution;\\\n";
		$script .= "chmod g+w /sys/devices/w1_bus_master*/*/conv_time;\\ \'\"\n";
		
		return $ret.$script;
	}
	return;
}

sub RPI_1Wire_GetConfig {
	my ($hash) = @_;
	readingsBeginUpdate($hash);
	my $device=$hash->{DEF};
	my $fh;
	my $conv=0;
	my $path="$w1_path/$device/resolution";
	if (open($fh, "<", $path)) {
		my $line = <$fh>;
		chomp $line;
		readingsBulkUpdate($hash,"precision",$line);
		close($fh);
	}
	$path="$w1_path/$device/conv_time";
	if (open($fh, "<", $path)) {
		my $line = <$fh>;
		chomp $line;
		$conv=$line;
		readingsBulkUpdate($hash,"conv_time",$line);
		close($fh);
	}
	if (ReadingsVal($hash->{NAME},"mode","nonblocking") eq "timer" && $conv>10) {
	}
	readingsEndUpdate($hash,1);			
}

sub RPI_1Wire_Poll {
	my $start = [gettimeofday];
	my ($hash) = @_;
	my $device=$hash->{DEF};
	my $family=$hash->{family};
	my $type=$RPI_1Wire_Devices{$family}{type};
	my @path=split(",",$RPI_1Wire_Devices{$family}{path});
	my $id=$hash->{id};
	my $name=$hash->{NAME};
	my $temperature;
	my $humidity;
	my @counter;
	
	return if ($device eq "BUSMASTER");
	
	my $retval=$name;
	my $file="";
	my @data;
	foreach (@path) {
		$file="$w1_path/$device/$_";
		if ($family =~ /DHT(11|22)/) { 
			my $env = RPi::DHT->new($id,$1,1);
			Log3 $name, 4 , $name.": Using RPi::DHT for $id DHT-$1";
			@data=$env->read();
			last;
		}
		Log3 $name, 5 , $name.": Open $file";
		my $fh;
		my $count=0;
		my $loopcount=0;
		while ($count==0 && $loopcount<3){
			if (!open($fh, "<", $file)) {
				Log3 $name, 2 , $name.": Error opening $file";
				return "$retval error=open_device";
			}
			while (my $line = <$fh>) {
				chomp($line); #Issue with binary?
				push @data, $line;
				$count++;
				Log3 $name, 5 , $name.": Read $line";
			}
			close ($fh);
			$loopcount++;
		}
		if ($count == 0) {
			Log3 $name, 2 , $name.": No data found in $file"; 
			return "$retval error=empty_data";
		}
	}
	
	if ($type =~ /temperature/) {
		if ($data[0] =~ /crc.*YES/) {
			$data[1] =~ /t=(-?\d+)/;
			my $temp = $1/1000.0;
			$temp -= 4096 if($temp > 1000);
			$retval .= " temperature=$temp";
		} else {
			$retval .= " error=crc";
		}
	}

	#Special handling for Robue Clone - is anyone using that?
	#Running throught the standard branch DS18B20 branch should still work for Robue, right? So we just overwrite any previous temperature or error
	if ($type eq "temperature" and $data[0] =~ /crc.*YES/ and substr($device, 6, 6) eq "544853") {
		my @owarray = split(" ", $data[0]);
		$retval.=" temperature=".(hex($owarray[1]) * 256 + hex($owarray[0]))/10.0;
		$retval.=" humidity=".(hex($owarray[3]) * 256 + hex($owarray[2]))/10.0;
		$retval.=" value=".hex($owarray[5]) * 256 + hex($owarray[4]);
		$retval.=" error=".hex($owarray[7]) if $owarray[7] ne "00"; #Is 00 no error?
	} 
	
	if ($type =~ /dht/) {
		#Getting data from this sensor is very unreliable. In case it fails (undefined) use the previous value so "state" is always looking ok
		if (defined $data[0]) {
			$retval.=" temperature=".$data[0];
			$retval.=" humidity=".$data[1];
		} else {
			$retval.=" error=crc";
		}
	}
	
	if ($type =~ /voltage/) {
		$retval .= " temperature=".$data[0]/256;
		$retval .= " vdd=".$data[1]/100;
		$retval .= " vad=".$data[2]/100;
	}
	if ($type =~ /counter/) {
		if (defined $data[2] && $data[2] =~ /c=(-?\d+)/) {
			$retval .= " counter.A=".$1;
		} else {
			$retval .= " error=crc";
		}
		if (defined $data[3] && $data[3] =~ /c=(-?\d+)/) {
			$retval .= " counter.B=".$1;
		} else {
			$retval .= " error=crc";
		}
	}
	
	##################### UNTESTED ####################
	if ($type =~ /switch/) {
		my $pins=unpack("c",$data[0]); # Binary bits
		my $data_bin=sprintf("%008b", $pins);
		my @pio=split("",$data_bin);
		if ($type eq "8p-switch") {
			my $pin=7;
			foreach (@pio) {
				$retval.=" pio".$pin."=".$_;
			}
		} else {
			$retval.= " pioa=".$pio[0];
			if ($type eq "2p-switch") {
				$retval.= " piob=".$pio[2];
			} else {
				$retval.= " piob=".$pio[1];
			}
		}	
	}
	#################################################
	my $elapsed = tv_interval ($start,[gettimeofday]);
	Log3 $hash->{NAME}, 4, $hash->{NAME}.": Poll for $type took $elapsed s";
	return $retval." duration=$elapsed";
}

#get attribute "faultvalues" and return values that are contained in this space seperated list
#temperature apply factor and offset
sub RPI_1Wire_CheckFaultvalues {
	my ($hash, $val) = @_;
	my @faultvalues = split(" ",AttrVal($hash->{NAME},"faultvalues",""));
	for (my $i=0; $i < @faultvalues; $i++) {
		if($val == $faultvalues[$i]) {
			Log3 $hash->{NAME}, 2, $hash->{NAME}.": Ignoring faultvalue $val";
			return;
		}
	}
	return $val;
}

sub RPI_1Wire_FinishFn {
	my ($string) = @_;
	return unless(defined($string));
	my @ret=split(" ",$string);
	my $name = shift @ret;
	Log3 $name, 5, $name.": Finish: $string";
	my $hash = $defs{$name};
	my $decimals = AttrVal($name,"decimals",3);
	readingsBeginUpdate($hash);
	my $state="";
	if (ReadingsAge($name,"failreason",0)>300) {
		readingsBulkUpdate($hash,"failreason","ok"); # Reset fail reason after 5 minutes to avoid confusion
	}
	foreach (@ret) {
		my ($par,$val)=split("=",$_);
		
		$val=RPI_1Wire_CheckFaultvalues($hash,$val);
		next if !defined $val;
		if ($par eq "temperature") {
			$val=sprintf( '%.'.$decimals.'f',$val*AttrVal($name,"tempFactor",1.0)+AttrVal($name,"tempOffset",0));
			readingsBulkUpdate($hash,"temperature",$val);
			$state.="T: $val ";
		} elsif ($par eq "duration") {
			my $duration=ReadingsVal($name,"duration",0);
			readingsBulkUpdate($hash,$par,sprintf("%.2f",$val));
			my $mode=AttrVal($name,"mode","nonblocking");
			if ($duration>0.5 and $val>0.5 and $mode ne "nonblocking") { #Only complain with 2 values in raw >0.5s
				readingsBulkUpdate($hash,"failreason","Read>0.5s - nonblocking mode recommended");
			}	
		} elsif ($par eq "error") {
			readingsBulkUpdate($hash,"failures",ReadingsVal($name,"failures",0)+1);
			readingsBulkUpdate($hash,"failreason",$val);
		} else {
			readingsBulkUpdate($hash,$par,$val);
			$state.="$par:$val ";
		}
	}
	readingsBulkUpdate($hash,"state",$state) unless $state eq ""; #Don't update state if nothing to update
	readingsEndUpdate($hash,1);			
}

sub RPI_1Wire_Attr {					#
	my ($command, $name, $attr, $val) = @_;
	my $hash = $defs{$name};
	return if !defined $val; #nothing to do when deleting an attribute
	Log3 $hash->{NAME}, 5, $hash->{NAME}.": Attr $attr=$val"; 
	if($attr eq "pollingInterval") {
		if (!looks_like_number($val) || $val < 0) {
			return "pollingInterval has to be a positive number or zero";
		}
		#Restart Timer
		RPI_1Wire_DeviceUpdate($hash);
	} elsif ($attr eq "mode") {
		if ($val ne "blocking" && $val ne "nonblocking" && $val ne "timer") {
			return "Unknown mode $val";
		}
		RPI_1Wire_GetConfig($hash); #Make sure the test is done with updated HW values
		if ($val eq "timer" && ReadingsVal($name,"conv_time",1000)>10) {
			return "Using timer mode is only recommended with reduced conv_time\nTry to adjust conv_time to 2";
		}
		#Restart Timer
		RPI_1Wire_DeviceUpdate($hash);
	} elsif ($attr eq "tempFactor" || $attr eq "tempOffset" || $attr eq "decimals") {
		if (!looks_like_number($val)) {
			return "$attr needs to be numeric";
		}
	}
	return;
}

sub RPI_1Wire_Undef {
	my ($hash) = @_;
	Log 4, "GPIO4: RPI_1Wire_Undef($hash->{NAME})";
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
	RemoveInternalTimer($hash);
	return;
}

sub RPI_1Wire_Detail {
	my ($FW_wname, $name, $room, $pageHash) = @_;
	my $hash=$defs{$name};
	my $ret = "";
	if ($hash->{helper}{write} ne "") {
		return "Some commands are not available due to missing write permissions to files in $w1_path:<br>$hash->{helper}{write}<br>See <b>get udev</b> for help how to resolved this.<br>";
	}
	return;
}

1;

=pod
=item device
=item summary Interface for various 1-Wire devices
=item summary_DE Interface für verschiedene 1-Wire Geräte

=begin html

<h3>RPI_1Wire</h3>
<a id="RPI_1Wire"></a>
For German documentation see <a href="https://wiki.fhem.de/wiki/RPI_1Wire">Wiki</a>
<ul>
		provides an interface to devices connected through the standard Raspberry 1-Wire interface (GPIO4) and is aware of the following devices:<br><br>
		<li>Family 0x10 (DS18S20) temperature</li>
		<li>Family 0x12 (DS2406) adressable 2 port switch (read only, untested)</li>
		<li>Family 0x19 (DS28E17) i2c bridge (unsupported)</li>
		<li>Family 0x1c (DS28E04) eeprom memory (unsupported)</li>
		<li>Family 0x1d (DS2423) dual counter</li>
		<li>Family 0x26 (DS2438) a/d converter with temperature support</li>
		<li>Family 0x28 (DS18B20) temperature</li>
		<li>Family 0x29 (DS2408) 8 port switch (read only, untested)</li>
		<li>Family 0x3a (DS2413) adressable 2 port switch (read only, untested)</li>
		<li>Family 0x3b (DS1825) temperature</li>
		<li>Family 0x42 (DS28EA00) temperature</li>
		<li>DHT11/DHT22 sensors (adressable GPIO) temperature, humidity</li>
		<br>
		Data can be queried blocking (conversion time of temperature sensors can block FHEM for about 1s), nonblocking or with staged timer (conv_time hack)
		</ul>
	<a id="RPI_1Wire-define"></a><br>
	<b>Define</b>
	<ul>
		<code>define &lt;name&gt; RPI_1Wire BUSMASTER|ff-xxxxxxxxxxxx|DHT11-&lt;gpio&gt|DHT22-&lt;gpio&gt</code><br><br>
		<li>BUSMASTER device has the functionality to autocreate devices on startup or with the "scan" command<br>
		Having a BUSMASTER is not required unless you like to use autocreate or the therm_bulk_read feature.<br>
		The internal reading "devices" will list all the device IDs associated with the BUSMASTER.<br>
		In case you defined more than one w1_bus_master in your system, you can use "BUSMASTER-x", where "x" is the number of w1_bus_master<b>x</b> in the sysfs, to explicitly define it. Default is always to use "1".<br>
		</li>
		<li>ff-xxxxxxxxxxxx is the id of a 1-Wire device as shown in sysfs tree where ff is the family. To use 1-Wire sensors call "sudo raspi-config" and enable the "1-Wire Interface" under "Interface options".</li>
		<li>DHT11|12-&lt;gpio&gt defines a DHT11 or DHT22 sensor where gpio is the number of the used GPIO. This requires an additional Perl module which can be aquired <a href="https://github.com/bublath/rpi-dht">here</a>. Make sure to define the right type, since DHT11 and DHT22 sensors are similar, but require different algorithms to read. Also note that these are not 1-Wire (GPIO4) sensors and should be attached to GPIOs different to 4 and require one GPIO each.</li>
		<br>
	</ul>

	<a id="RPI_1Wire-set"></a>
	<b>Set</b>
	<ul>
		<li><b>set scan</b><br>
		<a id="RPI_1Wire-set-scan"></a>
		Only available for BUSMASTER: Scan the device tree for new 1-Wire devices (not possible for DHT) and trigger autocreate<br>
		</li>
		<li><b>set update</b><br>
		<a id="RPI_1Wire-set-update"></a>
		Force a manual update of the device data. Will also restart the polling interval.<br>
		</li>
		<li><b>set precision 9|10|11|12</b><br>
		<a id="RPI_1Wire-set-precision"></a>
		Set the precision of the temperature conversion. Only available for temperature sensors and if the "resolution" file in sysfs is writable by the fhem user. See udev how to enable. Changing the precision is resetting conv_time to its default value.<br>
		Lowering the precision can significantly reduce conversion time.<br>
		Requires Linux Kernel 5.10+ (Raspbian Buster)  and write permissions to sysfs (see "get udev")<br>
		</li>
		<li><b>set conv_time &lt;milliseconds&gt</b><br>
		<a id="RPI_1Wire-set-conv_time"></a>
		Set the conversion time of the temperature conversion. When changing the precision, this is always reset to the system default (by the w1_therm driver) and that is the recommended value for most users.<br>
		Requires Linux Kernel 5.10+ (Raspbian Buster) and write permissions to sysfs (see "get udev")<br>
		</li>
		<a id="RPI_1Wire-setignore"></a>
		<li>(applies only Linux Kernel 5.10+ (Raspbian Buster)): There is however a "hack" to avoid fork()ing a nonblocking call, by setting the conv_time to e.g. 2ms (do not use 1ms, this had an unexpected behaviour in my system, setting the conv_time to 576, while setting it to 0 is restoring the default value). By this the read operation to the device will not finish in time before the new value is ready, but exit almost immediately (not blocking fhem). If you now set the "mode" of this device to "timer" it will trigger another read 1.5s later when the result will be ready (and also return immediately). With this timer driven "double read" it is possible to read the values quickly without blocking FHEM.<br>
		This might be useful if you have a lot of devices that you are reading in short sequence and you're low on system memory. The typical "nonblocking" call is temporarily creating a fork() of the current FHEM process, which in worst case can be complete copy of the memory FHEM uses (the OS does some optimizations though and only copies active parts). This can increase the risk of running out of system memory.
		</li>
		<li><b>set therm_bulk_read on|off</b><br>
		<a id="RPI_1Wire-set-therm_bulk_read"></a>
		Only available for BUSMASTER: Trigger a bulk read (in non-blocking mode) for ALL temperature sensors at once. The next read from the temperature sensors will return immediately, so it will be safe to set them to "blocking" mode, if the pollingInterval for BUSMASTER is smaller than the lowest pollingInterval for all sensors.<br>
		Requires Linux Kernel 5.10+ (Raspbian Buster) and write permissions to sysfs (see "get udev")<br>
		<b>Note:</b> There seems to be a Kernel bug, that breaks this feature if there are other 1-Wire devices on GPIO4 than temperature sensors using w1_therm driver.<br>
		</li>
	</ul>

	<a id="RPI_1Wire-get"></a>
	<b>Get</b>
	<ul>
		<li><b>udev</b><br>
		<a id="RPI_1Wire-get-udev"></a>
		Displays help how to configure udev to make some sysfs files writable for the fhem user. These write permissions are required to use the features conv_time, precision and therm_bulk_read.<br>
		Just create a udev file with content as described and copy it to /etc/udev/rules.d/ (root required). To activate the rules without a reboot you can use "sudo udevadm control --reload-rules && udevadm trigger". To activate the missing set commands, you will still need to restart FHEM.<br>
		</li>
	</ul>

	<a id="RPI_1Wire-attr"></a>
	<b>Attributes</b>
	<ul>
		<br>
		<li><b>pollingInterval</b><br>
		<a id="RPI_1Wire-attr-pollingInterval"></a>
			Defines how often the device is updated in seconds.<br>
			Default: 60, valid values: integers<br>
		</li>
		<li><b>tempOffset</b><br>
		<a id="RPI_1Wire-attr-tempOffset"></a>
			Only applies to temperature measurements: Value to be added to the measured temperature to calibrate sensors that are off.<br>
			In combination with the tempFactor the factor will be applied first, then the offset is added.<br>
			Default: 0, valid values: float<br>
		</li>
		<li><b>tempFactor</b><br>
		<a id="RPI_1Wire-attr-tempFactor"></a>
			Only applies to temperature measurements: Value that the measured temperature gets multiplied with to calibrate sensors that are off.<br>
			In combination with the tempOffset the factor will be applied first, then the offset is added.<br>
			Default: 1.0, valid values: float<br>
		</li>
		<li><b>mode blocking|nonblocking|timer</b><br>
		<a id="RPI_1Wire-attr-mode"></a>
			Reading values from the devices is typically blocking the execution of FHEM. In my tests a typical precision 12 temperature reading blocks for about 1s, a counter read for 0.2s and reading voltages about 0.5s.<br>
			While this sounds minimal there are devices that may depend on timing (e.g. CUL_HM) and can be impacted if FHEM is blocked for so long. As a result this module is by default fork()ing a seperate process that does the read operation in parallel to normal FHEM execution, which should be ok for most users, but can be optimized if desired (see more in "set conv_time" above).<br>
			Setting to timer mode is blocked for safety reasons in case conv_time is more than 9ms.<br>
			Default: nonblocking, valid values: blocking,nonblocking,timer<br>
		</li>
		<li><b>faultvalues</b><br>
		<a id="RPI_1Wire-attr-faultvalues"></a>
			A space separated list of values that will be ignored. Use this if you sensor is sometimes returning a strange value that you don't want to be processed. The comparison is done before applying any rounding, offsets or factors.<br>
			Default: empty, valid values: list of values <br>
		</li>
		<li><b>decimals</b><br>
		<a id="RPI_1Wire-attr-decimals"></a>
			Only applies to temperatures: Number of decimals for display (T: x.xx). The reading "temperature" always shows the full precision given by the sensor.<br>
			Default: 3, valid values: integer<br>
		</li>
	</ul>
	<a id="RPI_1Wire-readings"></a>
	<b>Readings</b>
	<ul>
		<br>
		<li><b>failures</b></li>
		Counts the failed read attempts (due to unavaible devices, empty data or CRC failures)<br>
		<li><b>failreason</b></li>
		Reason for the last seen failure:
		<li>crc: data could be read, but there was a checksum failure. If that happens too often, check you cabling quality</li>
		<li>no_data: The device could be opened, but no data was received</li>
		<li>open_device: The device could not be opened. Likely it was disconnected</li>
		<li><b>duration</b></li>
		Duration of the last read out. In modes blocking and timer a warning is put into failreason if this get more than 0.5s<br>
		<li><b>conv_time</b></li>
		Only for temperature: The actual used conversion time (queried from the OS)<br>
		Requires Linux Kernel 5.10+ (Raspbian Buster)<br>
		<li><b>precision</b></li>
		Only for temperature: The actual used precision/resolution (queried from the OS)<br>
		Requires Linux Kernel 5.10+ (Raspbian Buster)<br>
		<li><b>temperature</b></li>
		Temperature reading from the device<br>
		<li><b>counter.A/counter.B</b></li>
		Counter readings from the device (DS2423)<br>
		<li><b>vad/vdd</b></li>
		Voltage readings from the device (DS2438)<br>
		<li><b>pioa/piob</b></li>
		Switch states for dual port switches<br>
		<li><b>pio1 ... pio8</b></li>
		Switch states for 8 port switches<br>
	</ul>
	<br>

=end html
=cut

#original script by  https://github.com/mjg59/python-broadlink
#some parts by 31_LightScene.pm
# $Id$
package main;
use strict;
use warnings;
use Time::Local;
use IO::Socket::INET;
use IO::Select;

#use Crypt::CBC;
#use Crypt::OpenSSL::AES;
#use MIME::Base64;
#use Data::Dump qw(dump);

my $broadlink_hasJSON = 1;
my $broadlink_hasDataDumper = 1;
my $broadlink_hasCBC = 1;
my $broadlink_hasAES = 1;
my $broadlink_hasBase64 = 1;

sub Broadlink_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'Broadlink_Define';
    $hash->{UndefFn}    = 'Broadlink_Undef';
    $hash->{SetFn}      = 'Broadlink_Set';
    
    $hash->{AttrList} = 'socket_timeout:0.5,1,1.5,2,2.5,3,4,5,10 ' . $readingFnAttributes;
	eval "use JSON";
	$broadlink_hasJSON = 0 if($@);

	eval "use Data::Dumper";
	$broadlink_hasDataDumper = 0 if($@);
	
	eval "use Crypt::CBC";
	$broadlink_hasCBC = 0 if($@);
	
	eval "use Crypt::OpenSSL::AES";
	$broadlink_hasAES = 0 if($@);
	
	eval "use MIME::Base64";
	$broadlink_hasBase64 = 0 if($@);
	
}

sub Broadlink_Define($$) {
    my ($hash, $def) = @_;
    my @param = split('[ \t]+', $def);
	
	return "install Crypt::CBC to use Broadlink" if( !$broadlink_hasCBC);
	return "install Crypt::OpenSSL::AES to use Broadlink" if( !$broadlink_hasAES);
	return "install MIME::Base64 to use Broadlink" if( !$broadlink_hasBase64);
	return "install JSON (or Data::Dumper) to use Broadlink" if( !$broadlink_hasJSON && !$broadlink_hasDataDumper );
	
    if(int(@param) <= 4) {
        return "wrong syntax: define <name> Broadlink <connection=ip> <mac=xx:xx:xx:xx:xx> <optional type=rmpro or sp3>";
    }
    
    $hash->{ip}  = $param[2];
    $hash->{mac} = $param[3];
    $hash->{devtype} = $param[4];
	$hash->{'.key'} = pack('C*', 0x09, 0x76, 0x28, 0x34, 0x3f, 0xe9, 0x9e, 0x23, 0x76, 0x5c, 0x15, 0x13, 0xac, 0xcf, 0x8b, 0x02);
	$hash->{'.iv'} = pack('C*', 0x56, 0x2e, 0x17, 0x99, 0x6d, 0x09, 0x3d, 0x28, 0xdd, 0xb3, 0xba, 0x69, 0x5a, 0x2e, 0x6f, 0x58);
	$hash->{'.id'} = pack('C*', 0, 0, 0, 0);
	$hash->{counter} = 1;
	$hash->{isAuthenticated} = 0;
	if ($hash->{devtype} eq 'sp3' or $hash->{devtype} eq 'sp3s') { #steckdose
		Broadlink_auth($hash);
		if ($hash->{isAuthenticated} != 0) {
			Broadlink_sp3_getStatus($hash, 1);
		}
	} else {
		$hash->{commandList} = ();
		Broadlink_Load($hash);
	}
	
    return undef;
}

sub Broadlink_Undef($$) {
    my ($hash, $arg) = @_; 
    # nothing to do
    return undef;
}

sub Broadlink_Get($@) {
	my ($hash, @param) = @_;
	
	return undef;
}

sub Broadlink_Set(@) {
	my ($hash, $name, $cmd, @args) = @_;
	if ($hash->{devtype} eq 'sp3' or $hash->{devtype} eq 'sp3s') { #steckdose
		if ($cmd eq 'on') {
			Broadlink_auth($hash);
			if ($hash->{isAuthenticated} != 0) {
				Broadlink_sp3_setPower($hash, 1);
			}
			return undef;
		} elsif ($cmd eq 'off') {
			Broadlink_auth($hash);
			if ($hash->{isAuthenticated} != 0) {
				Broadlink_sp3_setPower($hash, 0);
			}
			return undef;
		} elsif ($cmd eq 'toggle') {
			Broadlink_auth($hash);
			if ($hash->{isAuthenticated} != 0) {
				if ($hash->{STATE} eq 'unknown') {
					Broadlink_sp3_getStatus($hash);				
				}
				if ($hash->{STATE} eq 'on') {
					Broadlink_sp3_setPower($hash, 0);
				} else {
					Broadlink_sp3_setPower($hash, 1);
				}
			}
			return undef;
		} elsif ($cmd eq 'getStatus') {
			Broadlink_auth($hash);
			if ($hash->{isAuthenticated} != 0) {
				Broadlink_sp3_getStatus($hash);
			}
			return undef;
		} elsif ($cmd eq 'getEnergy' and $hash->{devtype} eq 'sp3s') {
			Broadlink_auth($hash);
			if ($hash->{isAuthenticated} != 0) {
				Broadlink_sp3s_getEnergy($hash);
			}
			return undef;
		} else {
			if ($hash->{devtype} eq 'sp3s') {
				return "Unknown argument $cmd, choose one of on off toggle getStatus getEnergy";
			} else {
				return "Unknown argument $cmd, choose one of on off toggle getStatus";
			}
		}    
		return "$cmd. Try to get it.";
	} else { #rmpro rmmini etc.
		if ($cmd eq 'recordNewCommand') {
			Broadlink_auth($hash);
			my $cmdname = $args[0];
			if ($cmdname eq "") {
				return "Please specify commandname to record set <dev> recordNewCommand <name of the command>";
			}
			#if ($cmdname =~ /#|'|"|\/|\\|,/) {
			#   return "it is not allowed to use #,',\",\/,\\ or comma in commandname";
			#}
			if ($cmdname =~ /^[A-Z_a-z0-9\+\-]+$/) {
				$hash->{STATE} = "learning new command";
				if ($hash->{isAuthenticated} != 0) {
					Broadlink_enterLearning($hash, $cmdname);
				}
			} else {
				return "only A-Z, a-z, 0-9, _, +, - are allowed in commandname";
			}
			return undef;
		} elsif ($cmd eq 'commandSend') {
			Broadlink_auth($hash);
			my $cmdname = $args[0];
			if(!$hash->{commandList}{$cmdname}) {
				return "Unknown command $cmdname, choose an existing one or record a new one";
			}
			$hash->{STATE} = "send command:" . $cmdname;
			if ($hash->{isAuthenticated} != 0) {
				Broadlink_send_data($hash, decode_base64($hash->{commandList}{$cmdname}), $cmdname);
			}
			return undef;
		} elsif ($cmd eq 'rename') {
			my $cmdname = $args[0];
			my $newCmdname = $args[1];
			if ($cmdname eq "" or $newCmdname eq "") {
				return "Command wrong use set <dev> rename <oldname> <newname>";
			}
			if(!$hash->{commandList}{$cmdname}) {
				return "Unknown command $cmdname, choose an existing one";
			}
			if ($newCmdname =~ /^[A-Z_a-z0-9\+\-]+$/) {
				Broadlink_Load($hash);
				$hash->{commandList}{$newCmdname} = $hash->{commandList}{$cmdname};
				delete($hash->{commandList}{$cmdname});
				Broadlink_Save($hash);
			} else {
				return "only A-Z, a-z, 0-9, _, +, - are allowed in commandname";
			}
			return undef;
		} elsif ($cmd eq 'remove') {
			my $cmdname = $args[0];
			if(!$hash->{commandList}{$cmdname}) {
				return "Unknown command $cmdname, choose an existing one";
			}
			Broadlink_Load($hash);
			delete($hash->{commandList}{$cmdname});
			Broadlink_Save($hash);
			return undef;
		} elsif ($cmd eq 'getTemperature' and $hash->{devtype} eq 'rmpro') {
			Broadlink_auth($hash);
			if ($hash->{isAuthenticated} != 0) {
				Broadlink_getTemperature($hash);
			}
			return undef;
		} else {
			#sort with ignore case
			my $commandList = join(",", sort {
					lc $a cmp lc $b
						|| $a cmp $b
				} keys %{$hash->{commandList}});			
			#return "Unknown argument $cmd, choose one of learnNewCommand sendCommand sendCommandBase64 sendCommandHex createCommandBase64 createCommandHex";
			if ($hash->{devtype} eq 'rmpro') {
				return "Unknown argument $cmd, choose one of recordNewCommand rename getTemperature remove:" . $commandList . " commandSend:". $commandList;
			} else {
				return "Unknown argument $cmd, choose one of recordNewCommand rename remove:" . $commandList . " commandSend:". $commandList;
			}
		}    
		return "$cmd. Try to get it.";
	}
}

sub Broadlink_send_data(@) {
	my ($hash, $dataToSend, $cmdname) = @_;
	my @broadlink_payload = ((0) x 4);
	$broadlink_payload[0] = 2;
	my @values = split(//,$dataToSend);
	foreach my $val (@values) {
		push @broadlink_payload, unpack("C*", $val);
	}
	my $msg = "Try to send a command: " . $cmdname;
    Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $response = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	if (length($response) > 0 && $response ne "xxx") {
		readingsSingleUpdate ( $hash, "lastCommandSend", $cmdname, 1 );
		my $msg = $cmdname ." send";
		Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	} else {
		readingsSingleUpdate ( $hash, "connectionErrorOn", "sendCommand: " . $cmdname, 1 );
		my $msg = $cmdname . " command send failed - device not connected?";
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		$hash->{STATE} = $msg;
	}
}

sub Broadlink_check_data(@) {
	my ($hash) = @_;
	my @broadlink_payload = ((0) x  16);
	$broadlink_payload[0] = 4;
	my $msg = "check for new command";
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $data = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	#length must be bigger than 0x38, if not, cant get substring with data
	if (length($data) > 0x38 && $data ne "xxx") {
		my $err = unpack("C*", substr($data, 0x22, 1)) | (unpack("C*", substr($data, 0x23, 1)) << 8);
		if ($err == 0) {
			my $msg = "new command found";
			Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
			my $enc_payload = substr($data, 0x38);
			my $cipher =  Broadlink_getCipher($hash);         
			my $decodedData = $cipher->decrypt($enc_payload);
			$hash->{STATE} = "new Command learned: " . $hash->{'.newcommandname'};
			readingsSingleUpdate ( $hash, "lastRecordedCommand", $hash->{'.newcommandname'}, 1 );
			#frist load it again, if more than one device is defined
			Broadlink_Load($hash);
			$hash->{commandList}{$hash->{'.newcommandname'}} = encode_base64(substr($decodedData, 4));
			Broadlink_Save($hash);
			return substr($decodedData, 4);
		} else {
			my $msg = "Error receiving command";
			Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
		}
	} else {
		my $msg = "no new command data found - data length: " . length($data);
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		$hash->{STATE} = $msg;
	}
	$hash->{'.broadlink_checkCommands'}++;
	if ($hash->{'.broadlink_checkCommands'} < 15) {
		my $msg = "no command recorded. retry count:" . $hash->{'.broadlink_checkCommands'};
		Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
		InternalTimer(gettimeofday()+2, "Broadlink_check_data", $hash);
	} else {
		my $msg = "no command recorded even after a lot of retries. Try to learn again";
		Log3 $hash->{NAME}, 3, $hash->{NAME} . ": " . $msg;
		$hash->{STATE} = $msg;
		readingsSingleUpdate ( $hash, "lastFailedRecordedCommand", $hash->{'.newcommandname'}, 1 );
	}	
}

sub Broadlink_getTemperature(@) {
	my ($hash) = @_;
	my @broadlink_payload = ((0) x  16);
	$broadlink_payload[0] = 1;
	
	my $msg = "sp3_energy request";
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $data = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	#length must be bigger than 0x38, if not, cant get substring with data
	if (length($data) > 0x38 && $data ne "xxx") {
		my $err = unpack("C*", substr($data, 0x22, 1)) | (unpack("C*", substr($data, 0x23, 1)) << 8);
		if ($err == 0) {
			my $msg = "sp3 receiving temperature - data length: " . length($data);
			Log3 $hash->{NAME}, 1, $hash->{NAME} . ": " . $msg;
			my $enc_payload = substr($data, 0x38);
			my $cipher =  Broadlink_getCipher($hash);         
			my $decodedData = $cipher->decrypt($enc_payload);
			my $temperature = 0.0;
			if (unpack("C*", substr($decodedData, 4, 1)) =~ /^\d+?$/) { #isint
				$temperature = (unpack("C*", substr($decodedData, 4, 1)) * 10 + unpack("C*", substr($decodedData, 5, 1))) / 10.0;
			} else {
				$temperature = (ord(unpack("C*", substr($decodedData, 4, 1))) * 10 + ord(unpack("C*", substr($decodedData, 5, 1)))) / 10.0;
			}
			readingsSingleUpdate ( $hash, "currentTemperature", $temperature, 1 );
		} else {
			my $msg = "Error receiving temperature";
			Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
			readingsSingleUpdate ( $hash, "connectionErrorOn", "geTemperatureWithData", 1 );
		}
	} else {
		my $msg = "no new temperature data found - data length: " . length($data);
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		readingsSingleUpdate ( $hash, "connectionErrorOn", "getTemperature", 1 );
	}
}

sub Broadlink_sp3_getStatus(@) {
	my ($hash) = @_;
	my @broadlink_payload = ((0) x  16);
	$broadlink_payload[0] = 1;
	my $msg = "sp3_status request";
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $data = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	#length must be bigger than 0x38, if not, cant get substring with data
	if (length($data) > 0x38 && $data ne "xxx") {
		my $err = unpack("C*", substr($data, 0x22, 1)) | (unpack("C*", substr($data, 0x23, 1)) << 8);
		if ($err == 0) {
			my $msg = "sp3 receiving status - data length: " . length($data);
			Log3 $hash->{NAME}, 1, $hash->{NAME} . ": " . $msg;
			my $enc_payload = substr($data, 0x38);
			my $cipher =  Broadlink_getCipher($hash);         
			my $decodedData = $cipher->decrypt($enc_payload);
			if (unpack("C*", substr($decodedData, 4, 1)) eq 0) {
				$hash->{STATE} = "off";
			} else {
				$hash->{STATE} = "on";
			}
		} else {
			my $msg = "Error receiving status";
			Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
			$hash->{STATE} = "unknown";
			readingsSingleUpdate ( $hash, "connectionErrorOn", "geStatusWithData", 1 );
		}
	} else {
		my $msg = "no new status data found - data length: " . length($data);
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		$hash->{STATE} = "unknown";
		readingsSingleUpdate ( $hash, "connectionErrorOn", "geStatus", 1 );
	}
}


sub Broadlink_sp3_setPower(@) {
	my ($hash, $on) = @_;
	my @broadlink_payload = ((0) x  16);
	$broadlink_payload[0] = 2;
	if ($on == 1) {
		$broadlink_payload[4] = 1;
	} else {
		$broadlink_payload[4] = 0;
	}
	my $msg = "sp3_status request";
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $data = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	if (length($data) > 0 && $data ne "xxx") {
		if ($on == 1) {
			$hash->{STATE} = "on";
		} else {
			$hash->{STATE} = "off";
		}
	} else {
		readingsSingleUpdate ( $hash, "connectionErrorOn", "powerChange", 1 );
		my $msg = "powerChange - device not connected?";
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		$hash->{STATE} = "unkown";
	}
}

sub Broadlink_sp3s_getEnergy(@) {
	my ($hash) = @_;
	my @broadlink_payload = ((0) x  16);
	$broadlink_payload[0] = 8;
	$broadlink_payload[2] = 254;
	$broadlink_payload[3] = 1;
	$broadlink_payload[4] = 5;
	$broadlink_payload[5] = 1;
	$broadlink_payload[9] = 45;
	#my @broadlink_payload = pack('C*', 8, 0, 254, 1, 5, 1, 0, 0, 0, 45, 0, 0, 0, 0, 0, 0);
	
	my $msg = "sp3_energy request";
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $data = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	#length must be bigger than 0x38, if not, cant get substring with data
	if (length($data) > 0x38 && $data ne "xxx") {
		my $err = unpack("C*", substr($data, 0x22, 1)) | (unpack("C*", substr($data, 0x23, 1)) << 8);
		if ($err == 0) {
			my $msg = "sp3 receiving energy - data length: " . length($data);
			Log3 $hash->{NAME}, 1, $hash->{NAME} . ": " . $msg;
			my $enc_payload = substr($data, 0x38);
			my $cipher =  Broadlink_getCipher($hash);         
			my $decodedData = $cipher->decrypt($enc_payload);
			readingsSingleUpdate ( $hash, "currentPowerComsuption", sprintf("%.2f", (sprintf("%X", unpack("C*", substr($decodedData, 7, 1)) * 256 + unpack("C*", substr($decodedData, 6, 1))) + sprintf("%.2f", sprintf("%X", unpack("C*", substr($decodedData, 5, 1))) / 100.0))), 1 );
		} else {
			my $msg = "Error receiving energy";
			Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
			readingsSingleUpdate ( $hash, "connectionErrorOn", "geEnergyWithData", 1 );
		}
	} else {
		my $msg = "no new ernergy data found - data length: " . length($data);
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		readingsSingleUpdate ( $hash, "connectionErrorOn", "getEnergy", 1 );
	}
}

sub Broadlink_enterLearning(@) {
	my ($hash, $cmdname) = @_;
	my @broadlink_payload = ((0) x 16);
	$broadlink_payload[0] = 3;
	my $msg = "learn new commadn for " . $cmdname;
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
	my $data = Broadlink_send_packet($hash, 0x6a, @broadlink_payload);
	if (length($data) > 0 && $data ne "xxx") {
		$hash->{'.broadlink_checkCommands'} = 0;
		$hash->{'.newcommandname'} = $cmdname;
		my $msg = "start polling for " . $cmdname;
		Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
		InternalTimer(gettimeofday()+2, "Broadlink_check_data", $hash);
	} else {
		readingsSingleUpdate ( $hash, "connectionErrorOn", "enterLearning", 1 );
		my $msg = "command learn failed - device not connected?";
		Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
		$hash->{STATE} = $msg;
	}
}

sub Broadlink_auth(@) {
	my ($hash) = @_;
	#never authenticate again, if not needed
	if ($hash->{isAuthenticated} == 0) { 
		my @broadlink_payload = ((0) x 80);
		$broadlink_payload[0x04] = 0x31;
		$broadlink_payload[0x05] = 0x31;
		$broadlink_payload[0x06] = 0x31;
		$broadlink_payload[0x07] = 0x31;
		$broadlink_payload[0x08] = 0x31;
		$broadlink_payload[0x09] = 0x31;
		$broadlink_payload[0x0a] = 0x31;
		$broadlink_payload[0x0b] = 0x31;
		$broadlink_payload[0x0c] = 0x31;
		$broadlink_payload[0x0d] = 0x31;
		$broadlink_payload[0x0e] = 0x31;
		$broadlink_payload[0x0f] = 0x31;
		$broadlink_payload[0x10] = 0x31;
		$broadlink_payload[0x11] = 0x31;
		$broadlink_payload[0x12] = 0x31;
		$broadlink_payload[0x1e] = 0x01;
		$broadlink_payload[0x2d] = 0x01;
		$broadlink_payload[0x30] = ord('T');
		$broadlink_payload[0x31] = ord('e');
		$broadlink_payload[0x32] = ord('s');
		$broadlink_payload[0x33] = ord('t');
		$broadlink_payload[0x34] = ord(' ');
		$broadlink_payload[0x35] = ord(' ');
		$broadlink_payload[0x36] = ord('1');
		
		my $msg = "try to authenticate";
		Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . $msg;
		my $response = Broadlink_send_packet($hash, 0x65, @broadlink_payload);
		if (length($response) > 0x38 && $response ne "xxx") {
			my $enc_payload = substr($response, 0x38);
			my $cipher =  Broadlink_getCipher($hash);
			my $broadlink_payload = $cipher->decrypt($enc_payload);
			#authentication worked
			$hash->{'.key'} = substr($broadlink_payload, 0x04, 16);
			$hash->{'.id'} = substr($broadlink_payload, 0, 4);
			$hash->{isAuthenticated} = 1;
		} else {
			readingsSingleUpdate ( $hash, "lastAuthenticationFailed", "", 1 );
			my $msg = "authentication failed - device not connected? - response length: " . length($response);
			Log3 $hash->{NAME}, 4, $hash->{NAME} . ": " . $msg;
			$hash->{STATE} = $msg;
		}
	}
}

sub Broadlink_getCipher(@) {
	my ($hash) = @_;
	return Crypt::CBC->new(
					-key         => $hash->{'.key'},
					-cipher      => "Crypt::OpenSSL::AES",
					-header      => "none",
					-iv          => $hash->{'.iv'},
					-literal_key => 1,
					-keysize     => 16,
					-padding	 => 'space'
			);
}

sub Broadlink_send_packet(@) {
	my ($hash,$command,@broadlink_payload) = @_;
	
	#prepare header of packet
	$hash->{counter} = ($hash->{counter} + 1) & 0xffff;
	
	my @broadlink_id = split(//,$hash->{'.id'});
	my @broadlink_mac = split ':', $hash->{mac};
	
	my @packet = (0) x 56;
	$packet[0x00] = 0x5a;
    $packet[0x01] = 0xa5;
    $packet[0x02] = 0xaa;
    $packet[0x03] = 0x55;
    $packet[0x04] = 0x5a;
    $packet[0x05] = 0xa5;
    $packet[0x06] = 0xaa;
    $packet[0x07] = 0x55;
    $packet[0x24] = 0x2a;
    $packet[0x25] = 0x27;
    $packet[0x26] = $command;
	$packet[0x28] = $hash->{counter} & 0xff;
    $packet[0x29] = $hash->{counter} >> 8;
    $packet[0x2a] = unpack('H', $broadlink_mac[0]);
    $packet[0x2b] = unpack('H', $broadlink_mac[1]);
    $packet[0x2c] = unpack('H', $broadlink_mac[2]);
    $packet[0x2d] = unpack('H', $broadlink_mac[3]);
    $packet[0x2e] = unpack('H', $broadlink_mac[4]);
    $packet[0x2f] = unpack('H', $broadlink_mac[5]);
	
	$packet[0x30] = unpack('C', $broadlink_id[0]);
    $packet[0x31] = unpack('C', $broadlink_id[1]);
    $packet[0x32] = unpack('C', $broadlink_id[2]);
    $packet[0x33] = unpack('C', $broadlink_id[3]);
	
	#calculate payload checksum of original data
	my $checksum = 0xbeaf;
	my $arrSize = @broadlink_payload;
	for(my $i = 0; $i < $arrSize; $i++) {
		$checksum += $broadlink_payload[$i];
		$checksum = $checksum & 0xffff;
	}
	#put the checksum of payload in the header info
	$packet[0x34] = $checksum & 0xff;
    $packet[0x35] = $checksum >> 8;
	
	#crypt payload
	my $cipher =  Broadlink_getCipher($hash);       
	my $payloadCrypt = $cipher->encrypt(pack('C*', @broadlink_payload));
	
	#add the crypted data to packet
	my @values = split(//,$payloadCrypt);
	  foreach my $val (@values) {
		push @packet, unpack("C*", $val);
	}

	#create checksum of whole packet
	$checksum = 0xbeaf;
	$arrSize = @packet;
	for(my $i = 0; $i < $arrSize; $i++) {
		$checksum += $packet[$i];
		$checksum = $checksum & 0xffff;
	}
	#put the checksum of whole packet in the header info
	$packet[0x20] = $checksum & 0xff;
    $packet[0x21] = $checksum >> 8;
	
	#errorvalue if no data received
	my $data = "xxx";
	my $timeout = AttrVal($hash->{NAME}, 'socket_timeout', 3.0);
	eval { 
	  local $SIG{ALRM} = sub { die 'Timed Out'; }; 
	  alarm $timeout;
	  
	  #send udp packet
	  my $socket = IO::Socket::INET->new(
        Proto       => 'udp',
        PeerAddr    => $hash->{ip},
        PeerPort    => '80',
		ReuseAddr  => 1,
		Timeout => $timeout,
        #Blocking => 0
	  )  or Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . "Problem with socket";
	  
	  my $select = IO::Select->new($socket) if $socket;
	  
	  
	  #$socket->autoflush;   
	  $socket->send(pack('C*',@packet));
	  #IO::Select->select($select, undef, undef, 3);
	  if ($select->can_read($timeout)) {
		$socket->recv($data, 1024);
	  } else {
		Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . "can't read"; 
	  }
	  $socket->close();
	  alarm 0; 
	}; 
	alarm 0; # race condition protection 
	Log3 $hash->{NAME}, 3, $hash->{NAME} . ": " . 'Error Timout' if ( $@ && $@ =~ /Timed Out/ ); 
	Log3 $hash->{NAME}, 3, $hash->{NAME} . ": " . "Error: Eval corrupted: $@" if $@; 
	Log3 $hash->{NAME}, 5, $hash->{NAME} . ": " . length($data) . " bytes received from socket"; 
	return $data;
}

#lightscene Copy
sub Broadlink_statefileName() {
  my $statefile = $attr{global}{statefile};
  $statefile = substr $statefile,0,rindex($statefile,'/')+1;
  return $statefile ."broadlink.save" if( $broadlink_hasJSON );
  return $statefile ."broadlink.dd.save" if( $broadlink_hasDataDumper );
}

sub Broadlink_Save(@) {
	my ($hash) = @_;
	my $time_now = TimeNow();
	
	return "No statefile specified" if(!$attr{global}{statefile});
	my $statefile = Broadlink_statefileName();

	my $commandList = $hash->{commandList};
	
  if(open(FH, ">$statefile")) {
    my $t = localtime;
    print FH "#$t\n";

    if( $broadlink_hasJSON ) {
      print FH encode_json($commandList) if( defined($commandList) );
    } elsif( $broadlink_hasDataDumper ) {
      my $dumper = Data::Dumper->new([]);
      $dumper->Terse(1);

      $dumper->Values([$commandList]);
      print FH $dumper->Dump;
    }

    close(FH);
  } else {

    my $msg = "Broadlink_Save: Cannot open $statefile: $!";
    Log3 $hash->{NAME}, 1, $hash->{NAME} . ": " . $msg;
  }

  return undef;
}

sub Broadlink_Load(@) {
  my ($hash) = @_;

  return "No statefile specified" if(!$attr{global}{statefile});
  my $statefile = Broadlink_statefileName();

  if(open(FH, "<$statefile")) {
    my $encoded;
    while (my $line = <FH>) {
      chomp $line;
      next if($line =~ m/^#.*$/);
      $encoded .= $line;
    }
    close(FH);

    return if( !defined($encoded) );

    my $decoded;
    if( $broadlink_hasJSON ) {
      $decoded = decode_json( $encoded );
    } elsif( $broadlink_hasDataDumper ) {
      $decoded = eval $encoded;
    }
    $hash->{commandList} = $decoded;
  } else {
    my $msg = "Broadlink_Load: Cannot open $statefile: $!";
    Log3 $hash->{NAME}, 1, $hash->{NAME} . ": " . $msg;
  }
  return undef;
}

1;

=pod
=item device
=item summary    implements a connection to Broadlink devices
=item summary_DE implementiert die Verbindung zu Broadlink Geräten
=begin html

<a name="Broadlink"></a>
<h3>Broadlink</h3>
<ul>
    <i>Broadlink</i> implements a connection to Broadlink devices - currently tested with Broadlink RM Pro, which is able to send IR and 433MHz commands. It is also able to record this commands.
	It can also control <i>rmmini</i> devices and sp3 or sp3s plugs.
	<br>
	It requires AES encryption please install on Windows:<br>
	<code>ppm install Crypt-CBC</code><br>
	<code>ppm install Crypt-OpenSSL-AES</code><br><br>
	or Linux/Raspberry: 
	<code>sudo apt-get install libcrypt-cbc-perl</code><br>
	<code>sudo apt-get install libcrypt-rijndael-perl</code><br>
	<code>sudo cpan Crypt/OpenSSL/AES.pm</code><br>
    <br><br>
    <a name="Broadlinkdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Broadlink &lt;ip/host&gt; &lt;mac&gt; &lt;type=rmpro or rmmini or sp3 or sp3s&gt;</code>
        <br><br>
        Example: <code>define broadlinkWZ Broadlink 10.23.11.85 34:EA:34:F4:77:7B rmpro</code>
        <br><br>
		The <i>mac</i> of the device have to be set in format: xx:xx:xx:xx:xx<br>
        The type is in current development state optional.
    </ul>
    <br>
    
    <a name="Broadlinkset"></a>
    <b>Set for rmpro</b><br>
    <ul>
        <li><code>set &lt;name&gt; &lt;commandSend&gt; &lt;command name&gt;</code>
        <br><br>
		Send a previous recorded command.
        </li>
		<li><code>set &lt;name&gt; recordNewCommand &lt;command name&gt;</code>
        <br><br>
		Records a new command. You have to specify a commandname
        </li>
		<li>
		<code>set &lt;name&gt; remove &lt;command name&gt;</code>
        <br><br>
		Removes a recored command.
        </li>
		<li>
		<code>set &lt;name&gt; rename &lt;old command name&gt; &lt;new command name&gt;</code>
        <br><br>
		Renames a recored command.
        </li>
		<li><code>set &lt;name&gt; getTemperature</code>
        <br><br>
		Get the device current enviroment Temperature
        </li>
    </ul>
	<b>Set for rmmini</b><br>
    <ul>
        <li><code>set &lt;name&gt; &lt;commandSend&gt; &lt;command name&gt;</code>
        <br><br>
		Send a previous recorded command.
        </li>
		<li><code>set &lt;name&gt; recordNewCommand &lt;command name&gt;</code>
        <br><br>
		Records a new command. You have to specify a commandname
        </li>
		<li>
		<code>set &lt;name&gt; remove &lt;command name&gt;</code>
        <br><br>
		Removes a recored command.
        </li>
		<li>
		<code>set &lt;name&gt; rename &lt;old command name&gt; &lt;new command name&gt;</code>
        <br><br>
		Renames a recored command.
        </li>
    </ul>
    <br>
	    <b>Set for sp3</b><br>
    <ul>
        <li><code>set &lt;name&gt; on</code>
        <br><br>
		Set the device on
        </li>
		<li><code>set &lt;name&gt; off</code>
        <br><br>
		Set the device off
        </li>
		<li><code>set &lt;name&gt; toggle</code>
        <br><br>
		Toggle the device on and off
        </li>
		<li><code>set &lt;name&gt; getStatus</code>
        <br><br>
		Get the device on/off status
        </li>
    </ul>
	    <b>Set for sp3s</b><br>
    <ul>
        <li><code>set &lt;name&gt; on</code>
        <br><br>
		Set the device on
        </li>
		<li><code>set &lt;name&gt; off</code>
        <br><br>
		Set the device off
        </li>
		<li><code>set &lt;name&gt; toggle</code>
        <br><br>
		Toggle the device on and off
        </li>
		<li><code>set &lt;name&gt; getStatus</code>
        <br><br>
		Get the device on/off status
        </li>
		<li><code>set &lt;name&gt; getEnergy</code>
        <br><br>
		Get the device current energy consumption
        </li>
    </ul>
    <br>
	<a name="Broadlinkattr"></a>
    <b>Attributes for all Broadlink Devices</b><br>
    <ul>
        <li><code>socket_timeout</code>
        <br><br>
		sets a timeout for the device communication
        </li>
    </ul>
    <br>
</ul>

=end html
=begin html_DE

<a name="Broadlink"></a>
<h3>Broadlink</h3>
<ul>
    <i>Broadlink</i> implementiert die Verbindung zu Broadlink Geräten - aktuell mit Broadlink RM Pro, welcher sowohl Infrarot als auch 433MHz aufnehmen und anschließend versenden kann.
	Zusätzlich werden RMMinis und die Wlan Steckdosen SP3 und SP3S unterstützt
	<br>
	Das Modul benötigt AES-Verschlüsslung.<br>
	In Windows installiert man die Untersützung mit:<br>
	<code>ppm install Crypt-CBC</code><br>
	<code>ppm install Crypt-OpenSSL-AES</code><br><br>
	Auf Linux/Raspberry: 
	<code>sudo apt-get install libcrypt-cbc-perl</code><br>
	<code>sudo apt-get install libcrypt-rijndael-perl</code><br>
	<code>sudo cpan Crypt/OpenSSL/AES.pm</code><br>
    <br><br>
    <a name="Broadlinkdefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Broadlink &lt;ip/host&gt; &lt;mac&gt; &lt;type=rmpro or rmmini or sp3 or sp3s&gt;</code>
        <br><br>
        Beispiel: <code>define broadlinkWZ Broadlink 10.23.11.85 34:EA:34:F4:77:7B rmpro</code>
        <br><br>
		Die <i>mac</i>-Adresse des Gerätes muss im folgenden Format eingegeben werden: xx:xx:xx:xx:xx<br>
        Der Typ <i>sp3</i> wird für schaltbare Steckdosen genutzt. <i>rmpro</i> für alle anderen Geräte.
    </ul>
    <br>
    
    <a name="Broadlinkset"></a>
    <b>Set f&uuml;r rmpro</b><br>
    <ul>
        <li><code>set &lt;name&gt; &lt;commandSend&gt; &lt;command name&gt;</code>
        <br><br>
		Sendet ein vorher aufgenommenen Befehl
        </li>
		<li><code>set &lt;name&gt; recordNewCommand &lt;command name&gt;</code>
        <br><br>
		Nimmt ein neuen Befehl auf. Man muss einen Befehlnamen angeben.
        </li>
		<li>
		<code>set &lt;name&gt; remove &lt;command name&gt;</code>
        <br><br>
		Löscht einen vorher aufgezeichneten Befehl.
        </li>
		<li>
		<code>set &lt;name&gt; rename &lt;old command name&gt; &lt;new command name&gt;</code>
        <br><br>
		Benennt einen vorher aufgezeichneten Befehl um.
        </li>
		<li><code>set &lt;name&gt; getTemperature</code>
        <br><br>
		Ermittelt die aktuelle Temperatur die am Gerät gemessen wird.
        </li>
    </ul>
	<br>
	<b>Set f&uuml;r rmmini</b><br>
    <ul>
        <li><code>set &lt;name&gt; &lt;commandSend&gt; &lt;command name&gt;</code>
        <br><br>
		Sendet ein vorher aufgenommenen Befehl
        </li>
		<li><code>set &lt;name&gt; recordNewCommand &lt;command name&gt;</code>
        <br><br>
		Nimmt ein neuen Befehl auf. Man muss einen Befehlnamen angeben.
        </li>
		<li>
		<code>set &lt;name&gt; remove &lt;command name&gt;</code>
        <br><br>
		Löscht einen vorher aufgezeichneten Befehl.
        </li>
		<li>
		<code>set &lt;name&gt; rename &lt;old command name&gt; &lt;new command name&gt;</code>
        <br><br>
		Benennt einen vorher aufgezeichneten Befehl um.
        </li>
    </ul>
    <br>
	    <b>Set f&uuml;r sp3</b><br>
    <ul>
        <li><code>set &lt;name&gt; on</code>
        <br><br>
		Schaltet das Gerät an.
        </li>
		<li><code>set &lt;name&gt; off</code>
        <br><br>
		Schaltet das Gerät aus.
        </li>
		<li><code>set &lt;name&gt; toggle</code>
        <br><br>
		Schaltet das Gerät entweder ein oder aus.
        </li>
		<li><code>set &lt;name&gt; getStatus</code>
        <br><br>
		Ermittelt den aktuellen Status des Gerätes.
        </li>
    </ul>
    <br>
	    <b>Set f&uuml;r sp3s</b><br>
    <ul>
        <li><code>set &lt;name&gt; on</code>
        <br><br>
		Schaltet das Gerät an.
        </li>
		<li><code>set &lt;name&gt; off</code>
        <br><br>
		Schaltet das Gerät aus.
        </li>
		<li><code>set &lt;name&gt; toggle</code>
        <br><br>
		Schaltet das Gerät entweder ein oder aus.
        </li>
		<li><code>set &lt;name&gt; getStatus</code>
        <br><br>
		Ermittelt den aktuellen Status des Gerätes.
        </li>
		<li><code>set &lt;name&gt; getEnergy</code>
        <br><br>
		Ermittelt den aktuellen Stromverbrauch des angeschlossenen Gerätes.
        </li>
    </ul>
    <br>
	<a name="Broadlinkattr"></a>
    <b>Attribute f&uuml;r alle Broadlink Gräte</b><br>
    <ul>
        <li><code>socket_timeout</code>
        <br><br>
		Setzt den Timeout für die Gerätekommunikation.
        </li>
    </ul>
    <br>
</ul>

=end html_DE
=cut
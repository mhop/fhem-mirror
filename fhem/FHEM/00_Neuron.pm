##############################################
# $Id$
# todo:
# websocket automatischer restart				-> fertsch über devio
# DevIo_IsOpen() anstelle con hash helper websocket
# $hash->{DeviceName} global verwenden und devio nutzen
# ein httprequest?								-> Neuron_GetVal in Neuron_SetVal integriert
# NotifyFn sets/gets aus Readings				-> fertsch
#			(polling auch mit rein?)			-> nein
# set:
#	websocket open/close 						-> fertsch
#	otype-port on/off slider 					-> fertsch
#		(wenn $hash{FD} dann über websocket?)	-> fertsch
#	type-port -> conf (frei setzbar machen)		-> fertsch (postjson)
#
# bug?:  wenn man einen value setzt, dann wird im response der alte zurückgeschickt
#
#"alias": "al_Versuch1"
#{"glob_dev_id": 1, "dev": "input", "circuit": "1_01", "value": 0, "mode": "Simple", "counter_modes": ["Enabled", "Disabled"], "modes": ["Simple", "DirectSwitch"], "debounce": 50, "counter": 0, "counter_mode": "Enabled"}, 
#{"glob_dev_id": 1, "dev": "relay", "circuit": "1_01", "value": 0, "mode": "Simple", "modes": ["Simple", "PWM"], "pending": false, "relay_type": "digital"}, 
#{"glob_dev_id": 1, "dev": "relay", "circuit": "2_05", "value": 0, "mode": "Simple", "modes": ["Simple"], "pending": false, "relay_type": "physical"}, 
#{"glob_dev_id": 1, "dev": "ai",    "circuit": "1_01", "value": 0.0104..09, "unit": "V", "mode": "Voltage", "range_modes": ["10.0"], "modes": ["Voltage", "Current"], "range": "10.0"}, 
#{"glob_dev_id": 1, "dev": "ai", 	"circuit": "2_01", "value": -0.001..28, "unit": "V", "mode": "Voltage", "range_modes": ["0.0", "2.5", "10.0"], "modes": ["Voltage", "Current", "Resistance"], "range": "10.0"}, 
#{"glob_dev_id": 1, "dev": "ao", 	"circuit": "1_01", "value": 0.0, 		"unit": "V", "mode": "Voltage", "modes": ["Voltage", "Current", "Resistance"]}, 
#{"glob_dev_id": 1, "dev": "ao", 	"circuit": "2_01", "value": 0.0, 		"unit": "V", "mode": "Voltage", "modes": ["Voltage"]}, 
#{"glob_dev_id": 1, "dev": "led", 	"circuit": "1_01", "value": 0}, 
#{"glob_dev_id": 1, "dev": "wd", 	"circuit": "1_01", "value": 0, "timeout": 5000, "was_wd_reset": 0, "nv_save": 0}, 
#{"glob_dev_id": 1, "dev": "neuron","circuit": "1",    "ver2": "1.0", "sn": 31, "model": "M503", "board_count": 2}, 
#{"glob_dev_id": 1, "dev": "uart", 	"circuit": "1_01", "conf_value": 14, "stopb_modes": ["One", "Two"], "stopb_mode": "One", "speed_modes": ["2400bps", "4800bps", "9600bps", "19200bps", "38400bps", "57600bps", "115200bps"], "parity_modes": ["None", "Odd", "Even"], "parity_mode": "None", "speed_mode": "19200bps"}]#
#
#
package main;
 
use strict;
use warnings;

require "HttpUtils.pm";

my @clients = qw(
NeuronPin
);

my %opcode = (		# Opcode interpretation of the ws "Payload data
	'continuation'	=> 0x00,
	'text' 			=> 0x01,
	'binary'	 	=> 0x02,
	'close' 		=> 0x08,
	'ping' 			=> 0x09,
	'pong' 			=> 0x0A
);

my %setsP = (
	'off' => 0,
	'on' => 1,
);
#my %rsetsP = reverse %setsP;

sub Neuron_Initialize(@) {
    my ($hash) = @_;
	eval "use JSON::XS;";
	return "please install JSON::XS" if($@);
	eval "use Digest::SHA qw(sha1_hex);";
	return "please install Digest::SHA" if($@);

    # Provider
	$hash->{Clients} 		= join (':',@clients);
	$hash->{MatchList} 		= { "NeuronPin" => ".*" };
    $hash->{ReadFn}     	= "Neuron_Read";
    $hash->{ReadyFn}     	= "Neuron_Ready";
	$hash->{WriteFn}    	= "Neuron_Test";

    $hash->{DefFn}          = 'Neuron_Define';
    $hash->{UndefFn}        = 'Neuron_Undef';
    $hash->{ShutdownFn}     = 'Neuron_Undef';
    $hash->{SetFn}          = 'Neuron_Set';
    $hash->{GetFn}          = 'Neuron_Get';
    $hash->{AttrFn}         = 'Neuron_Attr';
    $hash->{NotifyFn}       = 'Neuron_Notify';
    $hash->{AttrList}       = "connection:websockets,polling poll_interval "
							 ."wsFilter:multiple-strict,ai,ao,input,led,relay,wd "
							 ."logicalDev:multiple-strict,ai,ao,input,led,relay,wd "
							 ."$readingFnAttributes";
    return undef;
}

sub Neuron_Define($$) {
    my ($hash, $def) = @_;
    my @parts=split("[ \t][ \t]*", $def);
	return "Usage: define <name> Neuron <hostname|ip>[:<tcp-portnr>]" unless defined $parts[2];
	$hash->{NOTIFYDEV} = "global";
	my ($address, $port) = split(/:/, $parts[2]);
    $port = "80" unless defined $port;
	$hash->{HOST} = $address;
	$hash->{PORT} = $port;
	$hash->{DeviceName} = $address.":".$port;
	$hash->{STATE} = "defined";
    return undef;
}

sub Neuron_Undef(@){
	my $hash = shift;
	Neuron_Close($hash);
	RemoveInternalTimer($hash);
    return undef;
}

sub Neuron_Set(@) {
	my ($hash, $name, $cmd, @args) = @_;
	my $sets = $hash->{HELPER}{SETS};
	if (index($hash->{HELPER}{SETS}, $cmd) != -1) {			# dynamisch erzeugte outputs
		my $circuit = substr($cmd,length($cmd)-4,4);
		my $dev = (split '_', $cmd)[0];
		my $value = (looks_like_number($args[0]) ? $args[0] : $setsP{$args[0]});
#		if ($hash->{HELPER}{WESOCKETS}) {
		if ($hash->{HELPER}{wsKey} && DevIo_IsOpen($hash)) {
			my $string = Neuron_wsEncode('{"cmd":"set", "dev":"'.$dev.'", "circuit":"'.$circuit.'", "value":"'.$value.'"}');
			Neuron_Write($hash,$string);
		} else {
			Neuron_HTTP($hash,$dev,$circuit,$value);
		}
	} elsif ($cmd eq "atest") {
		Log3 $hash, 1, "Testcmd abgesetzt";
		my $testcmd = '{"cmd":"set", "dev":"relay", "circuit":"2_01", "value":"'.$args[0].'"}';
		my $string = Neuron_wsEncode($testcmd);
		Neuron_Write($hash,$string);
	} elsif ($cmd eq "postjson") {
		my ($dev, $circuit , $value, $state) = @args;
		$value = '{"'.$value.'":"'.$state.'"}' if (defined($state));
		$hash->{HELPER}{CLSET} = $hash->{CL};
		Neuron_HTTP($hash,$dev,$circuit,$value);
	} elsif ($cmd eq "websocket") {
		if ($args[0] && $args[0] eq 'open') {
			Neuron_Open($hash);
		} else {
			Neuron_Close($hash);
		}
	} elsif ($cmd eq "clearreadings") {
		fhem("deletereading $hash->{NAME} .*", 1);
		#readingsDelete($hash, ".*");
	} else {
		return "Unknown argument $cmd, choose one of clearreadings:noArg websocket:open,close atest postjson " . ($hash->{HELPER}{SETS} ? $hash->{HELPER}{SETS} : '');
	}
    return undef;
}

sub Neuron_Get(@) {
    my ($hash, $name, $cmd, @args) = @_;
	if ($cmd eq "all") {
		Neuron_GetAll($hash);
	} elsif ($cmd eq "updt_sets_gets") {
		Neuron_ReadingstoSets($hash);
	} elsif ($cmd eq "value") {
		if (index($hash->{HELPER}{GETS}, $args[0]) != -1) {
			my @line = (split("_", $args[0],2));
			$hash->{HELPER}{CLVAL} = $hash->{CL};
			Neuron_HTTP($hash,$line[0],$line[1]);
		} else {
			return "Unknown Port $args[0], choose one of ".$hash->{HELPER}{GETS};
		}
	} elsif ($cmd eq "conf") {
		if (index($hash->{HELPER}{GETS}, $args[0]) != -1) {
			my @line = (split("_", $args[0],2));
			$hash->{HELPER}{CLCONF} = $hash->{CL};
			Neuron_HTTP($hash,$line[0],$line[1]);
		} else {
			return "Unknown Port $args[0], choose one of ".$hash->{HELPER}{GETS};
		}
	} else {
		my @gets = ('updt_sets_gets:noArg','all:noArg');
		if ($hash->{HELPER}{GETS}) {
			push(@gets, 'value:' . $hash->{HELPER}{GETS});
			push(@gets, 'conf:' . $hash->{HELPER}{GETS});
		}
		return "Unknown argument $cmd, choose one of " . join(" ", @gets);
	}
    return undef;
}

sub Neuron_Attr(@) {
	my ($cmd, $name, $attr, $val) = @_;
	
	# $cmd  - Vorgangsart - kann die Werte "del" (löschen) oder "set" (setzen) annehmen
	# $name - Gerätename
	# $attr/$val sind Attribut-Name und Attribut-Wert
	
	my $hash = $defs{$name};
	if ($attr && $attr eq 'connection') {
		if ($val && $val eq 'websockets' && $cmd eq 'set') {
			Log3 $hash, 5, "Neuron_Attr oeffne WS";
			Neuron_Open($hash);
		} else {
			Log3 $hash, 5, "Neuron_Attr schließe WS";
			Neuron_Close($hash);
		}
	} elsif ($attr eq 'poll_interval') {
		if ( defined($val) ) {
			if ( looks_like_number($val) && $val > 0) {
				RemoveInternalTimer($hash);
				if (AttrVal($hash->{NAME}, 'connection', 'polling') eq 'polling') {
					InternalTimer(1, 'Neuron_Poll', $hash, 0);
				} else {
					return '$hash->{NAME}: poll intervall can\'t defined together with websocket connection';
				}
			} else {
			return "$hash->{NAME}: Wrong poll intervall defined. poll_interval must be a number > 0";
			}
		} else {
			RemoveInternalTimer($hash);
		}
	} elsif ($attr eq 'wsFilter') {
		Neuron_wsSetFilter($hash,$val);
	}
	return undef;
}

sub Neuron_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};
	if (AttrVal($hash->{NAME}, 'connection', 'polling') eq 'polling') {	
		# Read all values
		Neuron_GetAll($hash);
		my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
		InternalTimer(gettimeofday() + ($pollInterval * 60), 'Neuron_Poll', $hash, 0) if ($pollInterval > 0);
	}
}



sub Neuron_Notify(@) {
	my ($hash, $nhash) = @_;
	my $name   = $hash->{NAME};
	return '' if(IsDisabled($name));

	my $events = deviceEvents($nhash, 1);
	if($nhash->{NAME} eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
		 Neuron_ReadingstoSets($hash);
		 Neuron_forall_clients($hash,\&Neuron_Init_Client,undef);
	}
    return undef;
}

sub Neuron_forall_clients($$$) {
	my ($hash,$fn,$args) = @_;
	foreach my $d ( sort keys %main::defs ) {
		if ( defined( $main::defs{$d} )
			&& defined( $main::defs{$d}{IODev} )
			&& $main::defs{$d}{IODev} == $hash ) {
			 &$fn($main::defs{$d},$args);
		}
	}
	return undef;
}

sub Neuron_Init_Client($@) {
	my ($hash,$args) = @_;
	if (!defined $args and defined $hash->{DEF}) {
		my @a = split("[ \t][ \t]*", $hash->{DEF});
		$args = \@a;
	}
	my $name = $hash->{NAME};
	Log3 $name,5,"im init client fuer $name "; 
	my $ret = CallFn($name,"InitFn",$hash,$args);
	if ($ret) {
		Log3 $name,2,"error initializing '".$hash->{NAME}."': ".$ret;
	}
}

###########################################################################################################
sub Neuron_Test($$) {

	my ( $hash, @args) = @_;
	my ($dev, $circuit , $value, $state) = @args;
	Log3($hash, 4,"$hash->{TYPE} ($hash->{NAME}) from logical dev: @args");

#	if ($hash->{HELPER}{WESOCKETS} && looks_like_number($value)) {
	if (looks_like_number($value) && $hash->{HELPER}{wsKey} && DevIo_IsOpen($hash)) {
		#my $string = Neuron_wsEncode('{"cmd":"set", "dev":"'.$dev.'", "circuit":"'.$circuit.'", "value":"'.$value.'"}');
		my $string = '{"cmd":"set", "dev":"'.$dev.'", "circuit":"'.$circuit.'", "value":"'.$value.'"}';
		Log3($hash, 4,"$hash->{TYPE} ($hash->{NAME}) from logical dev to Websocket: $string");
		Neuron_Write($hash,Neuron_wsEncode($string));
	} else {
		if (defined($state)) {
			if ($value eq 'debounce' || $value eq 'counter' || $value eq 'pwm_duty' || $value eq 'pwm_freq') {		#debounce Werte dürfen nicht in Hochkommas sein
				$value = '{"'.$value.'":'.$state.'}';
			} elsif ($value eq 'counter_mode') {
				$value = '{"'.$value.'":'.lc($state).'}';
			}else {
				$value = '{"'.$value.'":"'.$state.'"}';
			}
		}
		Log3($hash, 4,"$hash->{TYPE} ($hash->{NAME}) from logical dev to HTTP: $dev,$circuit".($value ? ",$value" : '').($state ? ",$state" : ''));
		Neuron_HTTP($hash,$dev,$circuit,$value);
	}
	return undef;
}

#####################################
# http fuctions
#####################################
sub Neuron_HTTP(@){
    my ($hash,$dev,$circuit,$data) = @_;
	#my $url="http://$hash->{HOST}:$hash->{PORT}/json/$dev/$circuit";
	my $url="http://$hash->{HOST}:$hash->{PORT}/".(defined($data) ? "json" : "rest")."/$dev/$circuit";
	if (defined($data) && index($data, ':') == -1) {
    	$data = '{"value":"'.$data.'"}';
	}
	Log3($hash, 3,"$hash->{TYPE} ($hash->{NAME}): sending ".($data ? "POST ($data)" : "GET")." request to url $url");
    my $param= {
        url      => $url,
        hash     => $hash,
        timeout  => 30,
        method   => ($data ? "POST" : "GET"),
		data	 => ($data ? $data : ''),
        header   => "User-Agent: fhem\r\nAccept: application/json",
        parser   => \&Neuron_ParseSingle,
        callback => \&Neuron_callback
     };
     HttpUtils_NonblockingGet($param);
     return undef;
}

sub Neuron_GetAll(@){
    my ($hash) = @_;
	#my $url="http://$hash->{HOST}:$hash->{PORT}/json/all";
	my $url="http://$hash->{HOST}:$hash->{PORT}/rest/all";

    Log3($hash, 4,"$hash->{TYPE} ($hash->{NAME}): sending GET all request with url $url");
    my $param= {
        url      => $url,
        hash     => $hash,
        timeout  => 30,
        method   => "GET",
        header   => "User-Agent: fhem\r\nAccept: application/json",
        parser   => \&Neuron_ParseAll,
        callback => \&Neuron_callback
     };
     HttpUtils_NonblockingGet($param);
     return undef;
}

#####################################
# functions to handle responses
#####################################
sub Neuron_callback(@) {
    my ($param, $err, $data) = @_;
    my ($hash) = $param->{hash};
	
	if($err){
        Log3($hash, 3, "$hash->{TYPE} ($hash->{NAME}) received callback with error:\n$err");
	} elsif($data){
		Log3($hash, 5, "$hash->{TYPE} ($hash->{NAME}) received callback with:\n$data");
	     my $parser = $param->{parser};
     	&$parser($hash, $data);
		asyncOutput($hash->{HELPER}{CLCONF}, $data) if $hash->{HELPER}{CLCONF};
		delete $hash->{HELPER}{CLCONF};
 	} else {
        Log3($hash, 2, "$hash->{TYPE} ($hash->{NAME}) received callback without Data and Error String!!!");
    }
   return undef;
}
 
sub Neuron_ParseSingle(@){
    my ($hash, $data)=@_;
    my $result;
	Log3($hash, 4, "$hash->{TYPE} ($hash->{NAME}) parse data:\n$data");
	eval {
		$result = JSON->new->utf8(1)->decode($data);
		#Log3 ($hash, 1, "$hash->{TYPE} ($hash->{NAME}) single result->status=".ref($result));
	};
	if ($@) {
		Log3 ($hash, 3, "$hash->{TYPE} ($hash->{NAME}) error decoding response: $@");
		readingsSingleUpdate($hash,"state","JSON decode error",1);
	} elsif ( $result->{status} && $result->{status} eq 'fail' ) {
		readingsSingleUpdate($hash,"state",'fail',1);
		asyncOutput($hash->{HELPER}{CLSET}, "set response fail") if $hash->{HELPER}{CLSET};
		Log3 ($hash, 2, "$hash->{TYPE} ($hash->{NAME}) http response fail with: ".$result->{data});
	} else {
		readingsSingleUpdate($hash,"state",'success',1);
		my %addvals = (STATUS => $result->{status}) if exists $result->{status};
		my $data;
		if (exists $result->{data}) {
			if (exists $result->{data}{result}) {
				$result = $result->{data}{result};
			} else {
				$result = $result->{data};
			}
		} elsif (exists $result->{result}) {
			$result = $result->{result};
		} else {
			$result = $result;
		}
		readingsSingleUpdate($hash,$result->{dev}."_".$result->{circuit},$result->{value},1);
		asyncOutput($hash->{HELPER}{CLVAL}, $result->{value}) if $hash->{HELPER}{CLVAL};
		delete $hash->{HELPER}{CLVAL};
		Dispatch($hash, $result, (%addvals ? \%addvals : undef)) if index(AttrVal($hash->{NAME}, 'logicalDev', 'relay,input,led,ao') , $result->{dev}) != -1; 
	}
	delete $hash->{HELPER}{CLSET};
	return $result;
}

sub Neuron_ParseAll(@){
    my ($hash, $data)=@_;
    my $result;
	Log3($hash, 5, "$hash->{TYPE} ($hash->{NAME}) parse data:\n$data");
	eval {
		$result = JSON->new->utf8(1)->decode($data);
	};
	if ($@) {
		Log3 ($hash, 3, "$hash->{TYPE} ($hash->{NAME}) error decoding response: $@");
		readingsSingleUpdate($hash,"state","JSON decode error",1);
	} else {
###################################################################
		eval {
	
			#Log3 ($hash, 1, "$hash->{TYPE} ($hash->{NAME}) result->status=".ref($result));
			my %addvals = (STATUS => $result->{status}) if ref $result eq 'HASH';
			my ($subdevs) = (ref $result eq 'HASH' ? $result->{data} : $result);
			readingsBeginUpdate($hash);
			my $i = 1;
			foreach (@{$subdevs}){
				(my $subdev)=$_;
				if (defined $subdev->{model} && defined $subdev->{glob_dev_id}) {
					foreach my $intrnl (keys %{$subdev}) {
						next if $intrnl eq "glob_dev_id";
						$hash->{uc($intrnl)} = $subdev->{$intrnl};
					}
				} elsif (defined $subdev->{model}) {
					foreach my $intrnl (keys %{$subdev}) {
						next if $intrnl eq "glob_dev_id";
						$hash->{'ext'.$i.'_'.uc($intrnl)} = $subdev->{$intrnl};
					}
					$i++;
				}  else {
					my $value = $subdev->{value};
					#$value = $rsetsP{$value} if ($subdev->{dev} eq 'input' || $subdev->{dev} eq 'relay' || $subdev->{dev} eq 'led');	# on,off anstelle von 1,0
					readingsBulkUpdateIfChanged($hash,$subdev->{dev}."_".$subdev->{circuit},$value) if defined($value);
					Dispatch($hash, $subdev, (%addvals ? \%addvals : undef)) if index(AttrVal($hash->{NAME}, 'logicalDev', 'relay,input,led,ao'), $subdev->{dev}) != -1;
					delete $subdev->{value};				
					readingsBulkUpdateIfChanged($hash,".".$subdev->{dev}."_".$subdev->{circuit},encode_json $subdev,0);
					Log3 ($hash, 4, "$hash->{TYPE} ($hash->{NAME}) ".$subdev->{dev}."_".$subdev->{circuit} .": ".encode_json $subdev);
				}
			}
			readingsBulkUpdate($hash,"state",$result->{status}) if ref $result eq 'HASH';
			readingsEndUpdate($hash,1);
			Neuron_ReadingstoSets($hash);
#################################################################  
		};
		if ($@) {
			Log3 ($hash, 1, "$hash->{TYPE} ($hash->{NAME}) ParseAll Error: $@");
			readingsSingleUpdate($hash,"state","JSON decode error",1);
		}		
	} 		
    return $data;
}

sub Neuron_ParseWsResponse($$){
    my ($hash, $data)=@_;
	my $name = $hash->{NAME};
    my $result;
    eval {
        $result = JSON->new->utf8(1)->decode($data);
    };
    if ($@) {
        Log3 ($hash, 3, "$hash->{TYPE} ($hash->{NAME}): error decoding response $@\nData:\n$data");
    } else {
        #my ($subdevs) = $result->{data};
        readingsBeginUpdate($hash);
        foreach (@{$result}){
            (my $subdev)=$_;
			my $value = $subdev->{value};
			#$value = $rsetsP{$value} if ($subdev->{dev} eq 'input' || $subdev->{dev} eq 'relay' || $subdev->{dev} eq 'led');	# on,off anstelle von 1,0
			readingsBulkUpdate($hash,$subdev->{dev}."_".$subdev->{circuit},$value);
			Dispatch($hash, $subdev, undef) if index(AttrVal($hash->{NAME}, 'logicalDev', 'relay,input,led,ao') , $subdev->{dev}) != -1; 
################################
		}
        readingsEndUpdate($hash,1);
    }         
    return undef
}
sub Neuron_ReadingstoSets($){
	my ($hash)=@_;
	my $sets;
	my @gets;
	foreach (keys %{$hash->{READINGS}}) {
		if (substr($_,0,3) eq 'led') {
			$sets .= " " if $sets;
			$sets .= $_ .":off,on";
		} elsif ( substr($_,0,5) eq 'relay') {
			$sets .= " " if $sets;
			$sets .= $_ .":off,on";
		} elsif (substr($_,0,2) eq 'ao') {
			$sets .= " " if $sets;
			$sets .= $_ .":slider,0,0.1,10";
		}
		unless (substr($_,0,1) eq '.') {
			push (@gets,$_); 
		}
		@gets = sort @gets;
	}
	$hash->{HELPER}{SETS} = $sets;
	$hash->{HELPER}{GETS} = join (',',@gets);
}
#######################################
# Socket Fuctions
#######################################
sub Neuron_Open($) {
	my $hash    = shift;
	my $name    = $hash->{NAME};
	my $host    = $hash->{HOST};
	my $port    = $hash->{PORT};
	my $timeout = 0.1;

	Log3 $name, 4, "$hash->{TYPE} ($name) - Establishing socket connection";
######### 1	
	DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));  
	DevIo_OpenDev($hash, 0, "Neuron_wsHandshake"); 
	#DevIo_OpenDev($hash, 0, "Neuron_wsHandshake", "Neuron_Callback"); 
######### 2	
#	return if( $hash->{CD} );
#	my $socket = new IO::Socket::INET   (   PeerHost => $host,
#											PeerPort => $port,
#											Proto => 'tcp',
#											Timeout => $timeout
#										)
#		or return Log3 $name, 4, "$hash->{TYPE} ($name) Couldn't connect to $host:$port";      # open Socket
#	$hash->{FD} = $socket->fileno();
#	$hash->{CD} = $socket;         # sysread / close won't work on fileno
#	$selectlist{$name} = $hash;
#########	
#	Log3 $name, 4, "$hash->{TYPE} ($name) - Socket Connected";
#	readingsSingleUpdate($hash,'state','ws_opened',1);
#	Neuron_wsHandshake($hash);	
}

sub Neuron_Ready($) {
	my ($hash) = @_;
	return DevIo_OpenDev($hash, 1, "Neuron_wsHandshake") if ( $hash->{STATE} eq "disconnected" );
}

sub Neuron_Close($) {
    my $hash    = shift;
    my $name    = $hash->{NAME};
	delete $hash->{HELPER}{WESOCKETS};
	delete $hash->{HELPER}{wsKey};
######### 1
	DevIo_CloseDev($hash);
######### 2
#    return if( !$hash->{CD} );
#    close($hash->{CD}) if($hash->{CD});
#    delete($hash->{FD});
#    delete($hash->{CD});
#    delete($selectlist{$name});
#########
#    readingsSingleUpdate($hash,'state','ws_disconnected',1);
#    Log3 $name, 4, "$hash->{TYPE} ($name) - Socket Disconnected";
}

sub Neuron_Write($@) {
	my ($hash,$string)  = @_;
	my $name = $hash->{NAME};

	Log3 $name, 4, "$hash->{TYPE} ($name) - WriteFn called:\n$string";
######### 1	
	DevIo_SimpleWrite($hash, $string, 0);
######### 2
#	return Log3 $name, 4, "$hash->{TYPE} ($name) - socket not connected" unless($hash->{CD});
#	syswrite($hash->{CD}, $string);
#########	
	return undef;
}

sub Neuron_Read($) {
	my $hash = shift;
	my $name = $hash->{NAME};
    my $buf;

	Log3 $name, 5, "$hash->{TYPE} ($name) - ReadFn started";
########### 1
	my $buf = DevIo_SimpleRead($hash);
########### 2
#	my $len = sysread($hash->{CD},$buf,10240);
#	if( !defined($len) or !$len ) {
#		Neuron_Close($hash);
#		return;
#	}
###########
	return Log3 $name, 3, "$hash->{TYPE} ($name) - no data received" 
		unless( defined $buf);

	if ($hash->{HELPER}{WESOCKETS}) {
		# Fehlerhafte Botschaftsteile abschneiden?
		#$buf =~ /(.{2,4}\[\{.*"glob_dev_id": .+\}\])/;
		#$buf = $1;
		Neuron_wsDecode($hash,$buf);
    } elsif( $buf =~ /HTTP\/1.1 101 Switching Protocols/ ) {
        Log3 $name, 4, "$hash->{TYPE} ($name) - received HTTP data string, start response processing:\n$buf";
		Neuron_wsCheckHandshake($hash,$buf);
    } else {
        Log3 $name, 1, "$hash->{TYPE} ($name) - corrupted data found:\n$buf";
    }
}
sub Neuron_Callback($) {
    my ($hash, $error) = @_;
	my $name = $hash->{NAME};
    Log3 $name, 5, "$hash->{TYPE} ($name) - error while connecting: $error"; 
    return undef; 
}
#######################################
#	Websocket Functions
#######################################
sub Neuron_wsHandshake($) {
	my $hash    = shift;
	my $name    = $hash->{NAME};
	my $host    = $hash->{HOST};
	#my $path    = $hash->{PATH};
	my $path    = "/ws";
	my $wsKey   = encode_base64(gettimeofday());

	my $wsHandshakeCmd  = "";
	$wsHandshakeCmd     .= "GET $path HTTP/1.1\r\n";
	$wsHandshakeCmd     .= "Host: $host\r\n";
	$wsHandshakeCmd     .= "User-Agent: FHEM\r\n";
	$wsHandshakeCmd     .= "Upgrade: websocket\r\n";
	$wsHandshakeCmd     .= "Connection: Upgrade\r\n";
	$wsHandshakeCmd     .= "Sec-WebSocket-Version: 13\r\n";            
	$wsHandshakeCmd     .= "Sec-WebSocket-Key: " . $wsKey . "\r\n";

	Log3 $name, 4, "$hash->{TYPE} ($name) - Starting Websocket Handshake";
	Neuron_Write($hash,$wsHandshakeCmd);

	$hash->{HELPER}{wsKey}  = $wsKey;

#	Log3 $name, 4, "$hash->{TYPE} Websocket ($name) - start WS hearbeat timer";
#	Neuron_HbTimer($hash);

#	Log3 $name, 4, "$hash->{TYPE} Websocket ($name) - start WS initialisation routine";
#	Neuron_WsInit($hash);
	return undef;
}

sub Neuron_wsCheckHandshake($$) {
	my ($hash,$response) = @_;
	my $name = $hash->{NAME};
	# header in Hash wandeln
	my %header = ();
	foreach my $line (split("\r\n", $response)) {
	    my ($key,$value) = split( ": ", $line );
	    next if( !$value );
	    $value =~ s/^ //;
		Log3 $name, 4, "$hash->{TYPE} ($name) - headertohash |$key|$value|";
	    $header{lc($key)} = $value;
	}
	# check handshake
	if( defined($header{'sec-websocket-accept'})) {
		my $keyAccept   = $header{'sec-websocket-accept'};
		Log3 $name, 5, "$hash->{TYPE} ($name) - keyAccept: $keyAccept";
		my $wsKey = $hash->{HELPER}{wsKey};
		my $expectedResponse = trim(encode_base64(pack('H*', sha1_hex(trim($wsKey)."258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))));
		if ($keyAccept eq $expectedResponse) {
			Log3 $name, 4, "$hash->{TYPE} ($name) - Successful WS connection to $hash->{HOST}";
			readingsSingleUpdate($hash,'state','ws_connected',1);
			$hash->{HELPER}{WESOCKETS} = '1';
			InternalTimer(gettimeofday() + (5), 'Neuron_wsHertbeat', $hash, 0) if AttrVal($hash->{NAME}, 'wsFilter', '');
			#Neuron_wsSetFilter($hash) if AttrVal($hash->{NAME}, 'wsFilter', '');
		} else {
			Neuron_Close($hash);
			Log3 $name, 3, "$hash->{TYPE} ($name) - ERROR: Unsucessfull WS connection to $hash->{HOST}";
			readingsSingleUpdate($hash,'state','ws_handshake-error',1);
		}
	}
	return undef;
}

sub Neuron_wsSetFilter($;$) {
	my ($hash,$val) = @_;
#	if ($hash->{HELPER}{WESOCKETS}) {
	if ($hash->{HELPER}{wsKey} && DevIo_IsOpen($hash)) {
		my $wsFilter = $val || AttrVal($hash->{NAME}, 'wsFilter', 'all');
		my $filter = '{"cmd":"filter","devices":["'. join( '","', split(',', $wsFilter ) ) .'"]}';
		#Log3 $hash, 1, "Filter: $filter";
		my $string = Neuron_wsEncode($filter);
		#Log3 $hash, 1, "Filter encoded: $string\nMAY NOT WORK";
		Neuron_Write($hash,$string);
	}
}

sub Neuron_wsHertbeat($) {
	my ($hash) =  @_;
	if (DevIo_IsOpen($hash)) {
		Neuron_wsSetFilter($hash);
		InternalTimer(gettimeofday() + (5 * 30), 'Neuron_wsHertbeat', $hash, 0)
	}
}

#	0                   1                   2                   3
#	0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
#	+-+-+-+-+-------+-+-------------+-------------------------------+
#	|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
#	|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
#	|N|V|V|V|       |S|             |   (if payload len==126/127)   |
#	| |1|2|3|       |K|             |                               |
#	+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
#	|     Extended payload length continued, if payload len == 127  |
#	+ - - - - - - - - - - - - - - - +-------------------------------+
#	|                               |Masking-key, if MASK set to 1  |
#	+-------------------------------+-------------------------------+
##	| Masking-key (continued)       |          Payload Data         |
#	+-------------------------------- - - - - - - - - - - - - - - - +
#	:                     Payload Data continued ...                :
#	+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
#	|                     Payload Data continued ...                |
#	+---------------------------------------------------------------+
# https://tools.ietf.org/html/draft-ietf-hybi-thewebsocketprotocol-17
sub Neuron_wsEncode($;$$) {
	my ($payload, $type, $masked) = @_;
	Log3 undef, 3, "Neuron_wsEncode Payload: " . $payload;
	$type //= "text";
	$masked //= 1;		# Mask   If set to 1, a masking key is present in masking-key. 1 for all frames sent from client to server
	my $RSV = 0;
	my $FIN = 1;		# FIN    Indicates that this is the final fragment in a message. The first fragment MAY also be the final fragment.
	my $MAX_PAYLOAD_SIZE = 65536;
	my $wsString ='';
	$wsString .= pack 'C', ($opcode{$type} | $RSV | ($FIN ? 128 : 0));
	my $len = length($payload);
	return "payload to big" if ($len > $MAX_PAYLOAD_SIZE);
    if ($len <= 125) {
        $len |= 0x80 if $masked;
        $wsString .= pack 'C', $len;
    } elsif ($len <= 0xffff) {
        $wsString .= pack 'C', 126 + ($masked ? 128 : 0);
        $wsString .= pack 'n', $len;
    } else {
        $wsString .= pack 'C', 127 + ($masked ? 128 : 0);
        $wsString .= pack 'N', $len >> 32;
        $wsString .= pack 'N', ($len & 0xffffffff);
    }
    if ($masked) { 
        my $mask = pack 'N', int(rand(2**32));
		$wsString .= $mask;
		$wsString .= Neuron_wsMasking($payload, $mask);	
    } else {
        $wsString .= $payload;
    }
	Log3 undef, 3, "Neuron_wsEncode String: " . unpack('H*',$wsString);
	return $wsString;
}
sub Neuron_wsDecode($$) {
	my ($hash,$wsString) = @_;
	Log3 $hash, 5, "Neuron_wsDecode String:\n" . $wsString;
	while (length $wsString) {
		my $FIN = 	 (ord(substr($wsString,0,1)) & 0b10000000) >> 7;
		my $OPCODE = (ord(substr($wsString,0,1)) & 0b00001111);
		my $masked = (ord(substr($wsString,1,1)) & 0b10000000) >> 7;
		my $len = 	 (ord(substr($wsString,1,1)) & 0b01111111);
		my $offset = 2;
		if ($len == 126) {
			$len = unpack 'n', substr($wsString,$offset,2);
			$offset += 2;
		} elsif ($len == 127) {
			$len = unpack 'q', substr($wsString,$offset,8);
			$offset += 8;
		}
		my $mask;
		if($masked) {											# Mask auslesen falls Masked Bit gesetzt
			$mask = substr($wsString,$offset,4);
			$offset += 4;
		}
		#String kürzer als Längenangabe -> Zwischenspeichern?
		if (length($wsString) < $offset + $len) {
			Log3 $hash, 3, "Neuron_wsDecode Incomplete:\n" . $wsString;
			return;
		}
		my $payload = substr($wsString, $offset, $len);			# Daten aus String extrahieren
		if ($masked) {											# Daten demaskieren falls maskiert
		   $payload = Neuron_wsMasking($payload, $mask);
		}
		Log3 $hash, 5, "Neuron_wsDecode Payload:\n" . $payload;
		$wsString = substr($wsString,$offset+$len);				# ausgewerteten Stringteil entfernen
		if ($FIN) {
			if ($OPCODE == $opcode{"text"}) {
				Neuron_ParseWsResponse($hash,$payload);
			}
		}

	# Behandlung von Segmentierten Botschaften
	#	if ($FIN) {
	#		if (@{$self->{fragments}}) {
	#			$self->opcode(shift @{$self->{fragments}});
	#		} else {
	#			$self->opcode($opcode);
	#		}
	#		$payload = join '', @{$self->{fragments}}, $payload;
	#		$self->{fragments} = [];
	#		return $payload;
	#	} else {
	#		# Remember first fragment opcode
	#		if (!@{$self->{fragments}}) {
	#			push @{$self->{fragments}}, $opcode;
	#		}
	#		push @{$self->{fragments}}, $payload;
	#		die "Too many fragments" if @{$self->{fragments}} > $self->{max_fragments_amount};
	#	}
	}

	
}
sub Neuron_wsMasking($$) {
    my ($payload, $mask) = @_;
    $mask = $mask x (int(length($payload) / 4) + 1);
    $mask = substr($mask, 0, length($payload));
    $payload = $payload ^ $mask;
    return $payload;
}

1;

=pod
=item device
=item summary Module for EVOK driven devices like UniPi Neuron
=item summary_DE Modul f&uuml; Ger&auml;te auf denen EVOK l&auml;uft z.B. UniPi Neuron.
=begin html

<a name="Neuron"></a>
<h3>Neuron</h3>
<ul>
	<a name="Neuron"></a>
		Module for EVOK driven devices like UniPi Neuron.
		Defines will be automatically created by the Neuron module.
		<br>
	<a name="NeuronDefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> Neuron &lt;dev&gt; &lt;circuit&gt;</code><br><br>
		&lt;dev&gt; is an device type like input, ai (analog input), relay (digital output) etc.<br>
		&lt;circuit&gt; ist the number of the device.
		<br><br>
		
    Example:
    <pre>
		<code>define <name> Neuron &lt;IP&gt;[:&lt;Port&gt;]</code><br><br>
    </pre>
  </ul>

  <a name="NeuronSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt;</code>
    <br><br>
    where <code>value</code> can be e.g.:<br>
    <ul><li>for relay
      <ul><code>
        off<br>
        on<br>	
        </code>
      </ul>
      The <a href="#setExtensions"> set extensions</a> are also supported for output devices.<br>
      </li>
	  Other set values depending on the options of the device function.
	  Details can be found in the UniPi Evok documentation.
	</ul>
  </ul>

  <a name="NeuronGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt;</code>
    <br><br>
	where <code>value</code> can be<br>
	<ul>
		<li>refresh: uptates all readings</li>
		<li>config: returns the configuration JSON</li>
	</ul>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attributes</b>
  <ul>
    <li>connection<br>
      Set the connection type to the EVOK device<br>
      Default: polling, valid values: websockets, polling<br><br>
    </li>							 
    <li>poll_interval<br>
      Set the polling interval in minutes to query all readings (and distribute them to logical devices)<br>
      Default: -, valid values: decimal number<br><br>
    </li>
    <li>wsFilter<br>
      Filter to limit the list of devices which should send websocket events<br>
      Default: all, valid values: all, ai, ao, input, led, relay, wd<br><br>
    </li>
    <li>logicalDev<br>
      Filter which subdevices should create / communicate with logical device<br>
      Default: ao, input, led, relay, valid values: ai, ao, input, led, relay, wd<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>
=end html

=begin html_DE

<a name="Neuron"></a>
<h3>Neuron</h3>
<ul>
	<a name="Neuron"></a>
		Modul f&uuml; die Steuerung von Ger&auml;ten auf denen EVOK l&auml;uft z.B. UniPi Neuron.
		<br>
	<a name="NeuronDefine"></a>
	<b>Define</b>
	<ul>
		<code>define <name> Neuron &lt;IP&gt;[:&lt;Port&gt;]</code><br><br>
		<br><br>
	</ul>

  <a name="NeuronSet"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;value&gt; [&lt;args&gt;]</code>
    <br><br>
	clearreadings:noArg websocket:open,close atest postjson
    where <code>value</code> can be e.g.:<br>
    <ul><li>dev_circuit<br>
			nur f&uuml; Ausg&auml;nge<br>
			&lt;args&gt;: on, off f&uuml;r Ausg&auml;nge und Slider f&uumlr ao<br>
			<br>
		</li>
		<li>clearreadings<br>
			l&ouml;sche alle Readings
		</li>
		<li>websocket<br>
			&lt;arg&gt;: open,close<br>
			Websocket Verbindung &ouml;ffnen, schliessen
		</li>
		<li>postjson<br>
			&lt;args&gt;: <code>dev circuit type value</code><br>
			JSON Kommando an entsprechendes Subdevice schicken.<br>
			z.B.: <code>set neuron input 1_01 mode simple</code>
		</li>
	  Details dazu sind in der UniPi Evok Dokumentation zu finden.
	</ul>
  </ul>

  <a name="NeuronGet"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;value&gt; [&lt;arg&gt;]</code>
    <br><br>
	where <code>value</code> can be<br>
	<ul>
		<li>all: aktualisiert alle readings</li>
		<li>config: gibt das Konfiguration des Subdevices &lt;arg&gt; zur&uuml;ck</li>
		<li>updt_sets_gets: Aktualisierung der Set und Get Auswahllisten</li>
		<li>value: gibt das Status des Subdevices &lt;arg&gt; zur&uuml;ck</li>
	</ul>
  </ul><br>

  <a name="RPI_GPIOAttr"></a>
  <b>Attribute</b>
  <ul>
    <li>connection<br>
      Verbindungsart zum EVOK Device<br>
      Standard: polling, g&uuml;ltige Werte: websockets, polling<br><br>
    </li>							 
    <li>poll_interval<br>
      Interval in Minuten in dem alle Werte gelesen (und auch an die log. Devices weitergeleitet) werden.<br>
      Standard: -, g&uuml;ltige Werte: Dezimalzahl<br><br>
    </li>
    <li>wsFilter<br>
      Filter um die liste der Ger&auml;te zu limitieren welche websocket events generieren sollen<br>
      Standard: all, g&uuml;ltige Werte: all, ai, ao, input, led, relay, wd<br><br>
    </li>
    <li>logicalDev<br>
      Filter um Ger&auml;te zu limitieren die logische Devices anlegen und mit ihnen kommunizieren.<br>
      Standard: ao, input, led, relay, g&uuml;ltige Werte: ai, ao, input, led, relay, wd<br><br>
    </li>
    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br>
</ul>
=end html_DE

=cut

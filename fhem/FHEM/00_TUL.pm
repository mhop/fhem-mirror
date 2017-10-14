##############################################
# $Id$
# ABU 20150916 removed print: simpleWriteDate, cleaned init
# ABU 20150918 fixed deprecated warning, fixed warning related to hex-conversion in simple-write
# ABU 20151123 added error-label in getGroup. Responsible for error-handling, if knxd is not accesible
# ABU 20151213 changed message-check in decode_tpuart() to avoid ignore while receiving repeated messages
# ABU 20160308 remoced set, get. Changed loglevel to verbose. Added KNX/EIB-Split. Added EIB-backward-compatibility.
# ABU 20160309 fixed log2
# ABU 20160310 repaired dispatch events - inform EIB, only is useEIB is set
# ABU 20160515 removed compatibility flag for EIB
# ABU 20160516 added log entry for non-compatibility of tul
# ABU 20160613 changed log entry for startup
# ABU 20161108 added knxd. Added doku as well. Added summary. Treat it like eibd. See thread #58375
# ABU 20170102 fixed write-mechanism, added mod for extended adressing (thx to its2bit)
# ABU 20170110 removed mod for extended adressing
# ABU 20170427 reintegrated mechanism for extenden GAD-Support
# ABU 20170427 cleaned logs
# ABU 20171006 deactivated default-log-entry
# ABU 20171006 EIB requires different handling of extended GAD --> added


package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

sub TUL_Attr(@);
sub TUL_Clear($);
sub TUL_Parse($$$$$);
sub TUL_Read($);
sub TUL_Ready($);
sub TUL_Write($$$);

sub TUL_OpenDev($$);
sub TUL_CloseDev($);
sub TUL_SimpleWrite(@);
sub TUL_SimpleRead($);
sub TUL_Disconnected($);
sub TUL_Shutdown($);

my %gets = (    # Name, Data to send to the TUL, Regexp for the answer
  "raw"      => ["r", '.*'],
);

my %sets = (
  "raw"       => "",
);

my $clients = ":KNX:EIB:";

my %matchList = (
    "2:KNX"      => "^C.*",
    "3:EIB"      => "^B.*",
);

my $useEIB = '0';

sub
TUL_Initialize($)
{
  my ($hash) = @_;

# Provider
  $hash->{ReadFn}  = "TUL_Read";
  $hash->{WriteFn} = "TUL_Write";
  $hash->{ReadyFn} = "TUL_Ready";

# Normal devices
  $hash->{DefFn}   = "TUL_Define";
  $hash->{UndefFn} = "TUL_Undef";
  $hash->{StateFn} = "TUL_SetState";
  $hash->{AttrFn}  = "TUL_Attr";
					 
  $hash->{AttrList}= 			"do_not_notify:1,0 " .
								"dummy:1,0 " .
								"showtime:1,0 " .
								"verbose:0,1,2,3,4,5 " .
								"useEIB:1,0 ";
							   
  $hash->{ShutdownFn} = "TUL_Shutdown";
  
}

#####################################
sub
TUL_Define($$)
{
	my ($hash, $def) = @_;
	my @a = split("[ \t][ \t]*", $def);

	if(@a < 4) 
	{
		my $msg = "wrong syntax: define <name> TUL <devicename> <device addr> [<line def in hex>]";
		return $msg;
	}

	TUL_CloseDev($hash);

	my $name = $a[0];
	my $dev = $a[2];
	my $devaddr = tul_str2hex($a[3]);
	my $linedef = substr(tul_str2hex($a[4]),0,2) if(@a > 4);

	if($dev eq "none") 
	{
		Log3 ($name, 1, "device is none, commands will be echoed only");
		$attr{$name}{dummy} = 1;
		return undef;
	}
  
	#Set attributes in order to control backward-compatibility
	#$attr{$name}{useEIB} = 1;
	#Log3 ($name, 0, "Using EIB is deprecated. Please migrate to KNX soon. Module 10_EIB is not maintained any longer. If you still want to use the module EIB, 
	#please set the attribute useEIB to 1 within the tul-device. Please keep in mind, that 10_KNX has a changed syntax regarding the definition, arguments and readings. Please refer to the commandref. 
	#As well 10_EIB and 10_KNX are compatible to daemon eibd and knxd.") if (AttrVal($name, "useEIB", 0) =~ m/0/);
  
	$hash->{DeviceName} = $dev;
	$hash->{DeviceAddress} = $devaddr;
	$hash->{Clients} = $clients;
	$hash->{MatchList} = \%matchList;
	$hash->{AckLineDef}= $linedef;
  
	my $ret = TUL_OpenDev($hash, 0);
	return $ret;
}


#####################################
sub
TUL_Undef($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	foreach my $d (sort keys %defs) 
	{
		if(defined($defs{$d}) && defined($defs{$d}{IODev}) && $defs{$d}{IODev} == $hash)
		{
			my $lev = ($reread_active ? 4 : 2);
			Log(GetLogLevel($name,$lev), "deleting port for $d");
			delete $defs{$d}{IODev};
		}
	}

	TUL_CloseDev($hash); 
	return undef;
}

#####################################
sub TUL_Shutdown($)
{
	my ($hash) = @_;
	TUL_CloseDev($hash); 
	return undef;
}

#####################################
sub
TUL_SetState($$$$)
{
	my ($hash, $tim, $vt, $val) = @_;
	return undef;
}

sub
TUL_Clear($)
{
	my $hash = shift;

	#Clear the pipe
	#TUL has no pipe....
}

#####################################
sub
TUL_DoInit($)
{
	my $hash = shift;
	my $name = $hash->{NAME};
	my $err;

	TUL_Clear($hash);

	# send any initializing request if needed
	# TODO move to device init 
	return 1 unless openGroupSocket($hash);
  
	# reset buffer
	purgeReceiverBuf($hash);

	$hash->{STATE} = "Initialized" if(!$hash->{STATE});

	# Reset the counter
	delete($hash->{XMIT_TIME});
	delete($hash->{NR_CMD_LAST_H});
	return undef;
}

#####################################
sub
TUL_Write($$$)
{
	my ($hash,$fn,$msg) = @_; 
	my $name = $hash->{NAME};
	
	return if(!defined($fn));
	
	#Discard message, if not set to backward-compatibility
	if (($useEIB =~ m/0/) and ($fn =~ m/\^B/))
	{
		Log3 ($name, 0, "EIB is no longer supported. Message discarded.");
		return;
	}

	Log3 ($name, 5, "sending $fn$msg");
	my $bstring = "$fn$msg";

	TUL_SimpleWrite($hash, $bstring);
}


#####################################
# called from the global loop, when the select for hash->{FD} reports data
sub
TUL_Read($)
{
	my ($hash) = @_;

	#reset the refused flag, so we can check if a telegram was refused
	# and therefor we did not get a response
	$hash->{REFUSED} = undef;	
	my $buf = TUL_SimpleRead($hash);
	my $name = $hash->{NAME};

	# check if refused
	if(defined($hash->{REFUSED}))
	{
		Log3 ($name, 3,"TUL $name refused message: $hash->{REFUSED}");
		$hash->{REFUSED} = undef;
		return "";
	}

	###########
	# Lets' try again: Some drivers return len(0) on the first read...
	if(defined($buf) && length($buf) == 0) 
	{
		$buf = TUL_SimpleRead($hash);
	}

	if(!defined($buf) || length($buf) == 0) 
	{
		TUL_Disconnected($hash);
		return "";
	}

	#place KNX-Message
	TUL_Parse($hash, $hash, $name, "B".$buf, $hash->{initString}) if ($useEIB =~ m/1/);
	#place EIB-Message
	TUL_Parse($hash, $hash, $name, "C".$buf, $hash->{initString});
}

sub
TUL_Parse($$$$$)
{
	my ($hash, $iohash, $name, $rmsg, $initstr) = @_;

	# there is nothing specal to do at the moment.
	# just dispatch
	
	my $dmsg = $rmsg;
	Log3 ($name, 4, "$name: $dmsg");

	$hash->{"${name}_MSGCNT"}++;
	$hash->{"${name}_TIME"} = TimeNow();
	$hash->{RAWMSG} = $rmsg;
	my %addvals = (RAWMSG => $rmsg);

	Dispatch($hash, $dmsg, \%addvals);
}


#####################################
sub
TUL_Ready($)
{
	my ($hash) = @_;

	return TUL_OpenDev($hash, 1) if($hash->{STATE} eq "disconnected");

	# This is relevant for windows/USB only
	my $po = $hash->{USBDev};
	my ($BlockingFlags, $InBytes, $OutBytes, $ErrorFlags) = $po->status;
	return ($InBytes>0);
}

########################
sub
TUL_SimpleWrite(@)
{
	my ($hash, $msg) = @_;
	return if(!$hash);

	# Msg must have the format B(w,r,p)g1g2g3v....
	# w-> write, r-> read, p-> reply
	# g1,g2,g3 are the hex parts of the group name
	# v is a simple (1 Byte) or complex value (n bytes)	

	# For eibd we need a more elaborate structure
	# Old
	#if($msg =~ /^[BC](.)(.{4})(.*)$/)
	# New: its2bit
	#if($msg =~ /^[BC](.)(.{5})(.*)$/)
	#extended adressing
	if ((($useEIB =~ m/1/) and ($msg =~ /^[BC](.)(.{4})(.*)$/)) or (($useEIB =~ m/0/) and ($msg =~ /^[BC](.)(.{5})(.*)$/)))
	{
		my $eibmsg;
		if($1 eq "w")
		{
			$eibmsg->{'type'} = 'write';
		}
		elsif ($1 eq "r") 
		{
			$eibmsg->{'type'} = 'read';
		}
		elsif ($1 eq "p") 
		{
			$eibmsg->{'type'} = 'reply';
		}

		$eibmsg->{'dst'} = $2;
		my $hexvalues = $3;
    
		#The array has to have a given length. During Hex-conversion Trailing
		#0 are recognizes for warnings.
		#Therefore we backup the length, trim, and reappend the 0
		#
		#save length and trim right side
		my $strLen = length ($hexvalues) / 2;
		$hexvalues =~ s/\s+$//;
		#convert hex-string to array with dezimal values
		my @data =  map hex($_), $hexvalues =~ /(..)/g;
		#re-append 0x00
		for (my $i=0; $strLen - scalar @data; $i++)
		{
			push (@data, 0);
		}
	
		# check: first byte is only allowed to contain data in the lower 6bits
		#        to make sure all is fine, we mask the first byte
		$data[0] = $data[0] & 0x3f if(defined($data[0]));
    
		$eibmsg->{'data'} = \@data;
    
		sendGroup($hash, $eibmsg);
	}
	else
	{
		Log3 ($hash->{NAME}, 1,"Could not parse message $msg");
		return undef;
	}

	select(undef, undef, undef, 0.001);
}

########################
sub
TUL_SimpleRead($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $msg = getGroup($hash);
	if(!defined($msg)) 
	{
		Log3 ($name, 4,"No data received.") ;
		return undef;
	}
  
	my $type = $msg->{'type'};
	my $dst = $msg->{'dst'};
	my $src = $msg->{'src'};
	my @bindata = @{$msg->{'data'}};
	my $data = "";
  
	# convert bin data to hex
	foreach my $c (@bindata) 
	{
		$data .= sprintf ("%02x", $c);
	}
 
	Log3 ($name, 5, "SimpleRead msg.type: $type, msg.src: $msg->{'src'}, msg.dst: $msg->{'dst'}");
	Log3 ($name, 5, "SimpleRead data: $data");
  
	# we will build a string like:
	# Bs1s2s3(w|r|p)g1g2g3v
	# s -> src 
	my $buf;
	#$buf = "C$src";
	$buf = $src;

	if($type eq "write") 
	{
		$buf .= "w";
	}
	elsif ($type eq "read") 
	{
		$buf .= "r";
	}
	else 
	{
		$buf .= "p";
	}
  
	$buf .= $dst;
	$buf .= $data;
  
	Log(4,"SimpleRead: $buf\n");
  
	return $buf;
}

########################
sub
TUL_CloseDev($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $dev = $hash->{DeviceName};

	return if(!$dev);
  
	if($hash->{TCPDev}) 
	{
		$hash->{TCPDev}->close();
		delete($hash->{TCPDev});
	} 
	elsif($hash->{USBDev}) 
	{
		$hash->{USBDev}->close() ;
		delete($hash->{USBDev});
	}
	
	delete($selectlist{"$name.$dev"});
	delete($readyfnlist{"$name.$dev"});
	delete($hash->{FD});
}

########################
sub
TUL_OpenDev($$)
{
	my ($hash, $reopen) = @_;
	my $dev = $hash->{DeviceName};
	my $name = $hash->{NAME};
	my $po;

	$hash->{PARTIAL} = "";
	Log 3, "TUL opening $name device $dev" if(!$reopen);

	# eibd:host[:port]
	#if($dev =~ m/^(eibd):(.+)$/)
	if($dev =~ m/^(eibd|knxd):(.+)$/)
	{
		my $host = $2;
		my $port = 6720;
		
		#host:port
		if($host =~ m/^(.+):([0-9]+)$/)
		{ 
			$host = $1;
			$port = $2;
		}

		# This part is called every time the timeout (5sec) is expired _OR_
		# somebody is communicating over another TCP connection. As the connect
		# for non-existent devices has a delay of 3 sec, we are sitting all the
		# time in this connect. NEXT_OPEN tries to avoid this problem.
		return if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN});

		my $conn = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port,Proto => 'tcp');
		if($conn) 
		{
			delete($hash->{NEXT_OPEN})
		} 
		else 
		{
			Log3 ($name, 3, "Can't connect to $dev: $!") if(!$reopen);
			$readyfnlist{"$name.$dev"} = $hash;
			$hash->{STATE} = "disconnected";
			$hash->{NEXT_OPEN} = time()+60;
			return "";
		}

		$hash->{DevType} = 'EIBD';
		$hash->{TCPDev} = $conn;
		$hash->{FD} = $conn->fileno();
		delete($readyfnlist{"$name.$dev"});
		$selectlist{"$name.$dev"} = $hash;
	}
	# tpuart:ttydev[@baudrate] / USB/Serial device
	elsif ($dev =~ m/^(tul|tpuart):(.+)$/) 
	{
		my $dev = $2;
		my $baudrate;
		($dev, $baudrate) = split("@", $dev);
		$baudrate = 19200 if(!$baudrate); # fix for TUL board
  	
		if ($^O=~/Win/) 
		{
			require Win32::SerialPort;
			$po = new Win32::SerialPort ($dev);
		} else  
		{
			require Device::SerialPort;
			$po = new Device::SerialPort ($dev);
		}

		if(!$po) 
		{
			return undef if($reopen);
			Log3 ($name, 3, "Can't open $dev: $!");
			$readyfnlist{"$name.$dev"} = $hash;
			$hash->{STATE} = "disconnected";
			return "";
		}
		
		$hash->{DevType} = 'TPUART';
		$hash->{USBDev} = $po;
		if( $^O =~ /Win/ ) 
		{
			$readyfnlist{"$name.$dev"} = $hash;
		} 
		else 
		{
			$hash->{FD} = $po->FILENO;
			delete($readyfnlist{"$name.$dev"});
			$selectlist{"$name.$dev"} = $hash;
		}
		
		# assumed always available
		if($baudrate) 
		{
			$po->reset_error();
			Log3 ($name, 3, "TUL setting $name baudrate to $baudrate");
			$po->baudrate($baudrate);
			$po->databits(8);
			$po->parity('even');
			$po->stopbits(1);
			$po->handshake('none');

			# This part is for some Linux kernel versions which has strange default
			# settings.  Device::SerialPort is nice: if the flag is not defined for your
			# OS then it will be ignored.
			$po->stty_icanon(0);
			#$po->stty_parmrk(0); # The debian standard install does not have it
			$po->stty_icrnl(0);
			$po->stty_echoe(0);
			$po->stty_echok(0);
			$po->stty_echoctl(0);

			# Needed for some strange distros
			$po->stty_echo(0);
			$po->stty_icanon(0);
			$po->stty_isig(0);
			$po->stty_opost(0);
			$po->stty_icrnl(0);
		}

		$po->write_settings;
	}
	# No more devices supported now
	else 
	{                              
		Log3 ($name, 1, "$dev protocol is not supported");
	}

	if($reopen) 
	{
		Log3 ($name, 1, "TUL $dev reappeared ($name)");
	} 
	else 
	{
		Log3 ($name, 3, "TUL device opened");
	}

	$hash->{STATE}="";       # Allow InitDev to set the state
	my $ret  = TUL_DoInit($hash);

	if($ret) 
	{
		TUL_CloseDev($hash);
		Log (1, "Cannot init $dev, ignoring it");
	}

	DoTrigger($name, "CONNECTED") if($reopen);
	return $ret;
}

########################
sub
TUL_Disconnected($)
{
	my $hash = shift;
	my $dev = $hash->{DeviceName};
	my $name = $hash->{NAME};

	return if(!defined($hash->{FD}));                 # Already deleted or RFR

	Log3 ($name, 1, "$dev disconnected, waiting to reappear");
	TUL_CloseDev($hash);
	$readyfnlist{"$name.$dev"} = $hash;               # Start polling
	$hash->{STATE} = "disconnected";

	# Without the following sleep the open of the device causes a SIGSEGV,
	# and following opens block infinitely. Only a reboot helps.
	sleep(5);

	DoTrigger($name, "DISCONNECTED");
}

########################
sub
TUL_Attr(@)
{
	my ($cmd,$name,$aName,$aVal) = @_;

	Log3 ($name, 5, "changing value, ATTR: $aName, VALUE: $aVal");
	
	if ($aName =~ m/useEIB/)
	{
		if ($aVal =~ m/1/)
		{
			$useEIB = '1';
		}
		else
		{
			$useEIB = '0';
		}
	}
	
	return undef;
}


####################################################################################
####################################################################################

#    
#
# The following section has been inspired by the EIB module from MrHouse project
# written by Peter Sj?din peter@sjodin.net and Mike Pieper eibdmh@pieper-family.de
# Code has been mainly changed to fit to the FHEM framework by Maz Rashid
# (to be honest the code had to be reworked very intensively due  the lack of code quality)
#

# Utility functions
sub tul_hex2addr 
{
	my $str = lc($_[0]);
    # Old
	#if ($str =~ /([0-9a-f])([0-9a-f])([0-9a-f]{2})/) 
	# New its2bit
	#if ($str =~ /([0-9a-f]{2})([0-9a-f])([0-9a-f]{2})/) 
	#extended adressing
	if ((($useEIB =~ m/1/) and ($str =~ /([0-9a-f])([0-9a-f])([0-9a-f]{2})/)) or (($useEIB =~ m/0/) and ($str =~ /([0-9a-f]{2})([0-9a-f])([0-9a-f]{2})/)))
	{
        return (hex($1) << 11) | (hex($2) << 8) | hex($3);
    }
    else
    {
		Log(3,"Bad EIB address string: \'$str\'\n");
		return;
    }
}

sub tul_addr2hex 
{
	my $a = $_[0];
	my $b = $_[1];  # 1 if local (group) address, else physical address
    my $str ;
	
    if ($b == 1) 
	{		
		#logical address used
		#old, short-syntax
        #$str = sprintf "%01x%01x%02x", ($a >> 11) & 0xf, ($a >> 8) & 0x7, $a & 0xff;
		#extended adress-range
		#$str = sprintf "%02x%01x%02x", ($a >> 11) & 0x1f, ($a >> 8) & 0x7, $a & 0xff;
		
		#extended adressing
		if ($useEIB =~ m/1/)
		{
			$str = sprintf "%01x%01x%02x", ($a >> 11) & 0xf, ($a >> 8) & 0x7, $a & 0xff;
		}
		else
		{
			$str = sprintf "%02x%01x%02x", ($a >> 11) & 0x1f, ($a >> 8) & 0x7, $a & 0xff;
		}
    }
    else 
	{ 
		#physical address used
		# Old
		# $str = sprintf "%01x%01x%02x", $a >> 12, ($a >> 8) & 0xf, $a & 0xff;
		# New
        #$str = sprintf "%02x%01x%02x", $a >> 12, ($a >> 8) & 0xf, $a & 0xff;
		
		#extended adressing
		if ($useEIB =~ m/1/)
		{
			$str = sprintf "%01x%01x%02x", $a >> 12, ($a >> 8) & 0xf, $a & 0xff;
		}
		else
		{
			$str = sprintf "%02x%01x%02x", $a >> 12, ($a >> 8) & 0xf, $a & 0xff;
		}
    }
	
    return $str;
}

sub tul_str2hex 
{
	my $str = $_[0];
	my $hex;
	
    if (($str =~ /(\d+)\/(\d+)\/(\d+)/) or ($str =~ /(\d+)\.(\d+)\.(\d+)/))
	{ 
		# logical address
		# old
		# my $hex = sprintf("%01x%01x%02x",$1,$2,$3);
		# New
		#my $hex = sprintf("%02x%01x%02x",$1,$2,$3);
		
		#extended adressing
		if ($useEIB =~ m/1/)
		{
			$hex = sprintf("%01x%01x%02x",$1,$2,$3);
		}
		else
		{
			$hex = sprintf("%02x%01x%02x",$1,$2,$3);
		}

		return $hex; 
    } 
}

# For mapping between APCI symbols and values
my @apcicodes = ('read', 'reply', 'write');
my %apcivalues = ('read' => 0, 'reply' => 1, 'write' => 2,);

# decode: unmarshall a string with an EIB message into a hash
# The hash has the follwing fields:
#	- type: APCI (symbolic value)
#	- src: source address
#	- dst: destiniation address
#	- data: array of integers; one for each byte of data
sub decode_eibd($)
{
    my ($buf) = @_;
    my $drl = 0xe1; # dummy value
    my %msg;
    my @data;
    my ($src, $dst,$bytes) = unpack("nnxa*", $buf);
    my $apci;

    $apci = vec($bytes, 3, 2);
	# mask out apci bits, so we can use the whole byte as data:
    vec($bytes, 3, 2) = 0;
    if ($apci >= 0 && $apci <= $#apcicodes) 
	{
		$msg{'type'} = $apcicodes[$apci];
    }
    else 
	{
		$msg{'type'} = 'apci ' . $apci;
    }
    $msg{'src'} = tul_addr2hex($src,0);
    $msg{'dst'} = tul_addr2hex($dst,1);

    @data = unpack ("C" . length($bytes), $bytes);
    my $datalen = @data;
    Log (5, "decode_eibd byte len: " . length($bytes) . " array size: $datalen");
    
    # in case of data len > 1, the first byte (the one with apci) seems not to be used
    # and only the following byte are of interest.
    if($datalen>1) 
	{
    	shift @data;
    }
    
    $msg{'data'} = \@data;
    return \%msg;
}

# encode: marshall a hash into a EIB message string
sub encode_eibd($) 
{
    my ($mref) = @_;
    my @msg;
    my $APCI;
    my @data;

    $APCI = $apcivalues{$mref->{'type'}};
    if (!(defined $APCI)) 
	{
		Log(3,"Bad EIB message type $mref->{'type'}\n");
		return;
    }
    @data = @{$mref->{'data'}};
	
    @data = (0x0) if(!@data || !defined($data[0])); #make sure data has at least one element
	#@data = (0x0) if(!(defined @data) || !(defined $data[0])); #make sure data has at least one element
    my $datalen = @data;
    Log (5,"encode_eibd dst: $mref->{'dst'} apci: $APCI datalen: $datalen data: @data");
    @msg = (
	    tul_hex2addr( $mref->{'dst'}), 	# Destination address
	    0x0 | ($APCI >> 2), 	# TPDU type, Sequence no, APCI (msb)
	    (($APCI & 0x3) << 6) | $data[0],
	    );
    if ($datalen > 1) 
	{
    	shift(@data);
		push @msg, @data;
    }
    return @msg;
}


# decode: unmarshall a string with an EIB telegram into a hash
#  A typical telegram looks like: bc110a0002e100813a
#   checks:
#       - 1st byte must have at least the bits $90 set. (otherwise it is false or a repeat)
#       - 2nd/3rd byte are the source (1.1.10)
#       - 4th/5th byte are the dst group (0/0/2)
#       - 6th byte (msb if 1 dst is group, else a phys. address ) 
#       -     low nibble is length of data (counting from 0) (->2)
#       - 7th byte is ignored
#       - 8th byte is the command / short data byte
#       -    if 8th byte >>6  is 0 -> read
#       -                     is 2 -> write
#       -                     is 1 -> reply
#       -    if length is 2 -> 8th byte & 0x3F is data
#       otherwise data start after 8th byte  
#       - last byte is the crc (ignored)
# The hash has the follwing fields:
#	- type: APCI (symbolic value)
#	- src: source address
#	- dst: destiniation address
#	- data: array of integers; one for each byte of data
sub decode_tpuart($)
{
    my ($buf) = @_;
    my ($ctrl,$src, $dst, $routingcnt,$cmd, $bytes) = unpack("CnnCxCa*", $buf);
    my $drl = $routingcnt >>7;
    my $len = ($routingcnt & 0x0F) +1;
	#if(($ctrl & 0xB0)!=0xB0)
    if(($ctrl & 0x90)!=0x90)
    {
		Log (3,"Control Byte " . sprintf("0x%02x",$ctrl) . " does not match expected mask 2x1001nnnn");
    	return undef;
    }

   Log (5,"msg cmd: " . sprintf("0x%02x",$cmd) ." datalen: $len");
   
   my $apci = ($cmd >> 6) & 0x0F;
   if($len == 2) 
   { # 1 byte data
   	$bytes = pack("C",$cmd & 0x3F);
   }

   Log (5,"msg cmd: " . sprintf("0x%02x",$cmd) ." datalen: $len apci: $apci");
   
    my %msg;
    my @data;
    if ($apci >= 0 && $apci <= $#apcicodes) 
	{
		$msg{'type'} = $apcicodes[$apci];
    }
    else 
	{
		$msg{'type'} = 'apci ' . $apci;
    }

    $msg{'src'} = tul_addr2hex($src,0);
    $msg{'dst'} = tul_addr2hex($dst,$drl);

    @data = unpack ("C" . length($bytes), $bytes);
    my $datalen = @data;
    Log (5, "decode_tpuart byte len: " . length($bytes) . " array size: $datalen");
    
    $msg{'data'} = \@data;
    return \%msg;
}

# encode: marshall a hash into a EIB message string
sub encode_tpuart($) 
{
    my ($mref) = @_;
    my @msg;
    my $APCI;
    my @data;

    $APCI = $apcivalues{$mref->{'type'}};
    if (!(defined $APCI)) 
	{
		Log (3,"Bad EIB message type $mref->{'type'}\n");
		return;
    }
    @data = @{$mref->{'data'}};
    my $datalen = @data;
    if($datalen > 14)
    {
  		Log (3,"Bad EIB message length $datalen\n");
		return;
   	
    }
    Log (5,"encode_tpuart dst: $mref->{'dst'} apci: $APCI datalen: $datalen data: @data");
    @msg = (
    	0xBC, # EIB ctrl byte
		tul_hex2addr($mref->{'src'}), # src address    	
	    tul_hex2addr( $mref->{'dst'}), 	# Destination address
	    0xE0 | $datalen, # Routing counter + data len
	    0x00,
	    (($APCI & 0x3) << 6) | $data[0],
	    );
    if ($datalen > 1) 
	{
    	shift(@data);
		push @msg, @data;
    }
    
    # convert to byte array
    my $arraystr = pack("CnnC*",@msg);
    @msg = unpack("C*",$arraystr);
    
    my @tpuartmsg;
    
    # calculate crc
    my $crc = 0xFF;
    my $i;
    for($i=0; $i<@msg;$i++)
    {
    	$crc ^= $msg[$i];
    	push @tpuartmsg,(0x80 | $i);
    	push @tpuartmsg, $msg[$i];
    }
    
    push @tpuartmsg,(0x40 | $i);
    push @tpuartmsg,$crc;
    
    return @tpuartmsg;
}

#
# eibd communication part
#

# Functions four group socket communication
# Open a group socket for group communication
# openGroupSocket SOCK
sub openGroupSocket($) 
{
    my $hash = shift;

	## only needed if EIBD
	if($hash->{DevType} eq 'EIBD')
	{
	    my @msg = (0x0026,0x0000,0x00);			# EIB_OPEN_GROUPCON
	    sendRequest ($hash, pack "nnC" ,@msg);
	    goto error unless my $answer = getRequest($hash);
	    my $head = unpack ("n", $answer);
	    goto error unless $head == 0x0026;
	}
	    
	return 1;

  error:
    print "openGroupSocket failed\n";
    return undef;
}

# Send group data
# sendGroup Hash DEST DATA
sub sendGroup($$)
{
    my ($hash,$msgref) = @_;
    my $dst = $msgref->{'dst'};
    my $src = $hash->{DeviceAddress};
    $msgref->{'src'} = $src;
    
    if($hash->{DevType} eq 'EIBD')
	{
	    my @encmsg = encode_eibd($msgref);
	
	    Log (5,"SendGroup: dst: $dst, msg: @encmsg \n");
	
	    my @msg = (0x0027);			# EIB_GROUP_PACKET
	    push @msg, @encmsg;
	    sendRequest($hash, pack("nnCC*", @msg));
	}
	elsif($hash->{DevType} eq 'TPUART')
	{
	    my @encmsg = encode_tpuart($msgref);
	
	    Log (5,"SendGroup: dst: $dst, msg: @encmsg \n");
		sendRequest($hash, pack("C*", @encmsg));
		my $response = getRequestFixLength($hash,($#encmsg + 1)/2+1);
	}
    return 1;
}

# will read as much byte as exists at the 
# serial buffer.
sub purgeReceiverBuf($)
{
	my ($hash) = @_;
	if($hash->{DevType} eq 'TPUART')
	{
	  Log (5,"purging receiver buffer ");
	  my $data = undef;
	  do
	  {
	    my(undef,$data) =  $hash->{USBDev}->read(100);
	    Log (5,"purging packet: ". unpack("H*",$data) . "\n") if(defined($data) and length($data)>0);
	  } while(defined($data) and length($data)>0)
	}
}

sub getRequestFixLength($$)
{
	my ($hash, $len) = @_;
	
	if($hash->{DevType} eq 'TPUART')
	{
		Log (5,"waiting to receive $len bytes ...");
		my $buf = "";
		while(length($buf)<$len)
		{
			#select(undef,undef,undef,0.5);
			my (undef,$data) =  $hash->{USBDev}->read($len-length($buf));
	    	Log (5,"Received fixlen packet: ". unpack("H*",$data) . "\n") if(defined($data) and length($data)>0);
				
			$buf .= $data if(defined($data));
			#Log (5,"buf len: " . length($buf) . " expected: $len");
			# TODO: if we are longer than 5 seconds here, we should reset
		}
		
#		# we got more than needed
		if(length($buf)>$len)
		{
			#check if this is ok
			my $remainpart = substr($buf,$len);
			$hash->{PARTIAL} .= $remainpart;
			$buf = substr($buf,0,$len);
			
			Log (5,"we got too much.. buf(" .unpack("H*",$buf).") remainingpart(" .unpack("H*",$remainpart).")");
		}
		
		Log (5,"getRequest len: $len packet: ". unpack("H*",$buf) . "\n");
		return $buf;
	}
	
	return undef;
}


# Receive group data
# getGroup hash
sub getGroup($) 
{
    my $hash = shift;

    if($hash->{DevType} eq 'EIBD')
	{
	    goto error unless my $buf = getRequest($hash);
	    my ($head, $data) = unpack ("na*", $buf);
	    goto error unless $head == 0x0027;
	
	    return decode_eibd($data);
	}
	elsif($hash->{DevType} eq 'TPUART')
	{
		my $ackdst = $hash->{AckLineDef};
		my $buf = $hash->{PARTIAL};
		my $reqlen = 8;
		my $telegram;
		
		do
		{
	    	my $data = getRequestFixLength($hash,$reqlen-length($buf)) if($reqlen>length($buf));
	    	if(length($buf)==0 && (!defined($data)||length($data)==0))
	    	{
	    		Log (5,"read fix length delivered no data.");
	    		return undef;
	    	}
	    	$buf .= $data if(defined($data));
	    	
	    	# check that control byte is correct
	    	my $ctrl = unpack("C",$buf) if(length($buf)>0);
	    	if(defined($ctrl) && ($ctrl&0x40) )
	    	{
	    		$buf = substr($buf,1);
	    		$hash->{PARTIAL} = $buf;
	    		Log (5,"TPUART RSP " . sprintf("0x%02x",$ctrl) ." ignored.");
	    		return undef;
	    	}
	    	
	    	if(length($buf)>5)
	    	{
	    		my $routingcnt = unpack("xxxxxC", $buf);
	    		$reqlen = ($routingcnt & 0x0F)+8;
	    		Log (5,"receiving telegram with len: $reqlen");
	    	}
			
			
			if($reqlen <= length($buf))
			{
				$telegram = substr($buf,0,$reqlen-1);
				$buf = substr($buf,$reqlen);	
			}
		}
		while(!defined($telegram));
	    
	    Log (5, "Telegram: (".length($telegram)."): " . unpack("H*",$telegram));
	    Log (5, "Buf: (".length($buf)."): " . unpack("H*",$buf));
	    
	    $hash->{PARTIAL} = $buf;	
	    my $msg = decode_tpuart($telegram);
	    
	    #check if we refused a telegram (i.e. repeats)
	    $hash->{REFUSED} = unpack("H*",$telegram) if(!defined($msg));
	    
# We are always too late for Ack	    
#	    if(defined($msg) && (substr($msg->{'dst'},0,2) eq $ackdst))
#	    {
#	    	# ACK
#	    	sendRequest($hash,pack('C',0x11));
#	    	Log (5,"Ack!");
#	    } 
	    
	    return $msg;
	}
	
	Log (2,"DevType $hash->{DevType} not supported for getGroup\n");
	return undef;
	
	error:
    print "seems like eibd not connected\n";
    return undef;  	    
}

# Gets a request from eibd
# DATA = getRequest SOCK
sub getRequest($) 
{
    my $hash = shift;
    my ($data);
    
    if($hash->{TCPDev} && $hash->{DevType} eq 'EIBD')
	{
	    goto error unless sysread($hash->{TCPDev}, $data, 2);
	    my $size = unpack ("n", $data);
	    goto error unless sysread($hash->{TCPDev}, $data, $size);
	    Log (5,"Received packet: ". unpack("H*",$data) . "\n");
	    return $data;
	}
	elsif($hash->{USBDev}) {
    	my $data = $hash->{USBDev}->input();
	    Log (5,"Received packet: ". unpack("H*",$data) . "\n") if(defined($data) and length($data)>0);
    	return $data;
	}
	
	Log (1,"TUL $hash->{NAME}: can not select a source for reading data.");
	return undef;
	
  error:
    printf "eibd communication failed\n";
    return undef;
	
}

# Sends a request to eibd
# sendRequest Hash,DATA
sub sendRequest($$) 
{
    my ($hash,$str) = @_;
    Log (5,"sendRequest: ". unpack("H*",$str). "\n");

	if($hash->{TCPDev})
	{
	    my $size = length($str);
	    my @head = (($size >> 8) & 0xff, $size & 0xff);

    	return undef unless syswrite($hash->{TCPDev},pack("CC", @head));
    	return undef unless syswrite($hash->{TCPDev}, $str);
	}
	elsif($hash->{USBDev})
	{
   		$hash->{USBDev}->write($str);
	}
	else
	{
		Log (2,"TUL $hash->{NAME}: No known physical protocoll defined.");
		return undef;
	}
	return 1;
}




1;

=pod
=begin html

<a name="TUL"></a>
<h3>TUL</h3>
<ul>

  <table>
  <tr><td>
  The TUL module is the representation of a EIB / KNX connector in FHEM.
  <a href="#KNX">KNX</a> instances represent the EIB / KNX devices and will need a TUL as IODev to communicate with the EIB / KNX network.<br>
  The TUL module is designed to connect to EIB network either using eibd, knxd or the <a href="http://busware.de/tiki-index.php?page=TUL" target="_blank">TUL usb stick</a> created by busware.de

  Note: this module may require the Device::SerialPort or Win32::SerialPort module if you attach the device via USB and the OS sets strange default parameters for serial devices.

  </td><td>
  <img src="IMG_0483.jpg" width="100%" height="100%"/>
  </td></tr>
  </table>

  <a name="TULdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TUL &lt;device&gt; &lt;physical address&gt;</code> <br>
    <br>
    TUL usb stick / TPUART serial devices:<br><ul>
      &lt;device&gt; specifies the serial port to communicate with the TUL. The name of the serial-device depends on your distribution, under linux the cdc_acm kernel module is responsible, and usually a
      /dev/ttyACM0 device will be created. If your distribution does not have a cdc_acm module, you can force usbserial to handle the TUL by the following command:<ul>modprobe usbserial vendor=0x03eb
      product=0x204b</ul>In this case the device is most probably /dev/ttyUSB0.<br><br>

      You can also specify a baudrate if the device name contains the @ character, e.g.: /dev/ttyACM0@19200<br><br>
	  Note: For TUL usb stick the baudrate 19200 is needed and this is the default when no baudrate is given.
	  <br><br>

	  Example:<br>
	  <code>define tul TUL tul:/dev/ttyACM0 1.1.249</code>
    </ul>
	
    EIBD:<br><ul>
    &lt;device&gt; specifies the host:port of the eibd device. E.g. eibd:192.168.0.244:2323. When using the standard port, the port can be omitted.
    <br><br>

	  Example:<br>
	  <code>define tul TUL eibd:localhost 1.1.249</code>
	  <code>define tul TUL knxd:192.168.178.1 1.1.248</code>
    </ul>
    <br>
    If the device is called none, then no device will be opened, so you can experiment without hardware attached.<br>

    The physical address is used as the source address of telegrams sent to EIB network.
  </ul>
  <br>

  <a name="TULattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#verbose">verbose</a></li><br>
	<li><a href="#useEIB">useEIB</a></li><br>
	<ul> 
		The device operates the module 10_EIB, if this flag is set to 1. This is used for backward compatibility only. Otherwise, only the client 10_KNX is used.
	</ul>	
  </ul>
  <br>
</ul>

=end html
=device
=item summary Connects FHEM to KNX-Bus (Base-device)
=item summary_DE Verbindet FHEM mit dem KNX-Bus (Basisger&umlat)
=begin html_DE

<a name="TUL"></a>
<h3>TUL</h3>
<ul>

  <table>
  <tr><td>
  Das Modul TUL stellt die Verbindung von FHEM zum EIB / KNX dar.
  <a href="#KNX">KNX</a> Instanzen stellen die Vrbindung zu den KNX-Gruppen dar und ben&Ouml;tigen ein TUL-Device als IO-Schnittstelle.<br>
  Das Modul TUL kommuniziert mit dem KNX entweder &Uuml;ber den eibd, den knxd oder den TUL <a href="http://busware.de/tiki-index.php?page=TUL" target="_blank">TUL usb stick</a> hergestellt von busware.de

  Anmerkung: das Modul ben&Ouml;tigt die Device::SerialPort oder Win32::SerialPort wenn der Stick &Uuml;ber USB angeschlossen wird, und das OS unrealistische Parameter f&Uuml;r das Device einstellt.

  </td><td>
  <img src="IMG_0483.jpg" width="100%" height="100%"/>
  </td></tr>
  </table>

  <a name="TULdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; TUL &lt;device&gt; &lt;physical address&gt;</code> <br>
    <br>
    TUL usb stick / TPUART serial devices:<br><ul>
      &lt;device&gt; enth&auml;lt die serielle Schnittstelle der TUL. Der name der Schnittstelle h&auml;ngt von Eurer Distribution ab. Unter linux wird f&Uuml;r gew&Ouml;hnlich /dev/ttyACM0 verwandt. 
	  Wenn Eure Distribution das modul cdc_acm nicht enth&auml;lt, k&Ouml;nnt Ihr das Laden des handles der TUL mit dem folgenden Befehl erzwingen:<ul>modprobe usbserial vendor=0x03eb
      product=0x204b</ul>Dann ist die Schnittstelle meist /dev/ttyUSB0.<br><br>

	  Ihr k&Ouml;nnt dem Ger&auml;t eine Baudrate vorgeben. Dazu dem Ger&auml;tenamen das Zeichen @ hinzuf&Uuml;gen, z.B.: /dev/ttyACM0@19200<br><br>
	  Anmerkung: F&Uuml;r den TUL-USB-Stick wird die Baudrate 19200 ben&Ouml;tigt. Dies entspricht der Defaulteinstellung.
	  <br><br>

	  Beispiel:<br>
	  <code>define tul TUL tul:/dev/ttyACM0 1.1.249</code>
    </ul>
	
    EIBD:<br><ul>
    &lt;device&gt; entspricht dem host:port des eibd-servers. z.B. eibd:192.168.0.244:2323. Wenn der Standardport genutzt wird, muss dieser nicht angegeben werden.
    <br><br>

	  Beispiel:<br>
	  <code>define tul TUL eibd:localhost 1.1.249</code>
	  <code>define tul TUL knxd:192.168.178.2 1.1.248</code>
    </ul>
    <br>
	Wenn das Ger&auml;t none konfiguriert wird, wird kein device ge&Ouml;ffnet. So k&Ouml;nnt Ihr ohne angeschlossene Hardware experimentieren. <br>

	Die physikalische Adresse wird als Absender f&Uuml;r KNX-Telegramme genutzt.
  </ul>
  <br>

  <a name="TULattr"></a>
  <b>Attribute</b>
  <ul>
    <li><a href="#do_not_notify">do_not_notify</a></li><br>
    <li><a href="#attrdummy">dummy</a></li><br>
    <li><a href="#showtime">showtime</a></li><br>
    <li><a href="#verbose">verbose</a></li><br>
	<li><a href="#useEIB">useEIB</a></li><br>
	<ul> 
		Das Ger&auml;t kann das Modul 10_EIB bedienen, wenn das Flag auf 1 gesetzt ist. Dies ist nur f&Uuml;r R&Uuml;ckw&auml;rtskompatibili&auml;t genutzt. Andernfalls wird nur das Modul 10_KNX bedient.
	</ul>	
  </ul>
  <br>
</ul>

=end html_DE

=cut

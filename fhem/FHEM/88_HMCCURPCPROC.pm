##############################################################################
#
#  88_HMCCURPCPROC.pm
#
#  $Id$
#
#  Version 1.1
#
#  Subprocess based RPC Server module for HMCCU.
#
#  (c) 2018 by zap (zap01 <at> t-online <dot> de)
#
##############################################################################
#
#  Required perl modules:
#
#    RPC::XML::Client
#    RPC::XML::Server
#
##############################################################################


package main;

use strict;
use warnings;

use RPC::XML::Client;
use RPC::XML::Server;
use SetExtensions;


######################################################################
# Constants
######################################################################

# HMCCURPC version
my $HMCCURPCPROC_VERSION = '1.0.007';

# Maximum number of events processed per call of Read()
my $HMCCURPCPROC_MAX_EVENTS = 100;

# Maximum number of errors during socket write before log message is written
my $HMCCURPCPROC_MAX_IOERRORS  = 100;

# Maximum number of elements in queue
my $HMCCURPCPROC_MAX_QUEUESIZE = 500;

# Maximum number of events to be send to FHEM within one function call
my $HMCCURPCPROC_MAX_QUEUESEND = 70;

# Time to wait after data processing loop in microseconds
my $HMCCURPCPROC_TIME_WAIT = 100000;

# Timeout for established CCU connection
my $HMCCURPCPROC_TIMEOUT_CONNECTION = 1;

# Timeout for TriggerIO()
my $HMCCURPCPROC_TIMEOUT_WRITE = 0.001;

# Timeout for accepting incoming connections (0 = default)
my $HMCCURPCPROC_TIMEOUT_ACCEPT = 1;

# Timeout for incoming CCU events
my $HMCCURPCPROC_TIMEOUT_EVENT = 600;

# Send statistic information after specified amount of events
my $HMCCURPCPROC_STATISTICS = 500;

# Default RPC Port = BidCos-RF
my $HMCCURPCPROC_RPC_PORT_DEFAULT = 2001;

# Default RPC server base port
my $HMCCURPCPROC_SERVER_PORT = 5400;

# Delay for RPC server start after FHEM is initialized
my $HMCCURPCPROC_INIT_INTERVAL0 = 12;

# Delay for RPC server cleanup after stop
my $HMCCURPCPROC_INIT_INTERVAL2 = 30;

# Delay for RPC server functionality check after start
my $HMCCURPCPROC_INIT_INTERVAL3 = 25;

# BinRPC data types
my $BINRPC_INTEGER = 1;
my $BINRPC_BOOL    = 2;
my $BINRPC_STRING  = 3;
my $BINRPC_DOUBLE  = 4;
my $BINRPC_BASE64  = 17;
my $BINRPC_ARRAY   = 256;
my $BINRPC_STRUCT  = 257;

# BinRPC message types
my $BINRPC_REQUEST        = 0x42696E00;
my $BINRPC_RESPONSE       = 0x42696E01;
my $BINRPC_REQUEST_HEADER = 0x42696E40;
my $BINRPC_ERROR          = 0x42696EFF;


######################################################################
# Functions
######################################################################

# Standard functions
sub HMCCURPCPROC_Initialize ($);
sub HMCCURPCPROC_Define ($$);
sub HMCCURPCPROC_InitDevice ($$);
sub HMCCURPCPROC_Undef ($$);
sub HMCCURPCPROC_Shutdown ($);
sub HMCCURPCPROC_Attr ($@);
sub HMCCURPCPROC_Set ($@);
sub HMCCURPCPROC_Get ($@);
sub HMCCURPCPROC_Read ($);
sub HMCCURPCPROC_SetError ($$$);
sub HMCCURPCPROC_SetState ($$);
sub HMCCURPCPROC_ProcessEvent ($$);

# RPC server control functions
sub HMCCURPCPROC_GetRPCServerID ($$);
sub HMCCURPCPROC_RegisterCallback ($$);
sub HMCCURPCPROC_DeRegisterCallback ($$);
sub HMCCURPCPROC_InitRPCServer ($$$$);
sub HMCCURPCPROC_StartRPCServer ($);
sub HMCCURPCPROC_RPCServerStarted ($);
sub HMCCURPCPROC_RPCServerStopped ($);
sub HMCCURPCPROC_CleanupProcess ($);
sub HMCCURPCPROC_CleanupIO ($);
sub HMCCURPCPROC_TerminateProcess ($);
sub HMCCURPCPROC_CheckProcessState ($$);
sub HMCCURPCPROC_IsRPCServerRunning ($);
sub HMCCURPCPROC_Housekeeping ($);
sub HMCCURPCPROC_StopRPCServer ($);
sub HMCCURPCPROC_SendRequest ($@);
sub HMCCURPCPROC_SetRPCState ($$$$);
sub HMCCURPCPROC_ResetRPCState ($);
sub HMCCURPCPROC_IsRPCStateBlocking ($);

# Helper functions
sub HMCCURPCPROC_GetAttribute ($$$$);
sub HMCCURPCPROC_HexDump ($$);

# RPC server functions
sub HMCCURPCPROC_ProcessRequest ($$);
sub HMCCURPCPROC_HandleConnection ($$$$);
sub HMCCURPCPROC_SendQueue ($$$$);
sub HMCCURPCPROC_SendData ($$);
sub HMCCURPCPROC_Write ($$$$);
sub HMCCURPCPROC_WriteStats ($$);
sub HMCCURPCPROC_NewDevicesCB ($$$);
sub HMCCURPCPROC_DeleteDevicesCB ($$$);
sub HMCCURPCPROC_UpdateDeviceCB ($$$$);
sub HMCCURPCPROC_ReplaceDeviceCB ($$$$);
sub HMCCURPCPROC_ReaddDevicesCB ($$$);
sub HMCCURPCPROC_EventCB ($$$$$);
sub HMCCURPCPROC_ListDevicesCB ($$);

# Binary RPC encoding functions
sub HMCCURPCPROC_EncInteger ($);
sub HMCCURPCPROC_EncBool ($);
sub HMCCURPCPROC_EncString ($);
sub HMCCURPCPROC_EncName ($);
sub HMCCURPCPROC_EncDouble ($);
sub HMCCURPCPROC_EncBase64 ($);
sub HMCCURPCPROC_EncArray ($);
sub HMCCURPCPROC_EncStruct ($);
sub HMCCURPCPROC_EncType ($$);
sub HMCCURPCPROC_EncodeRequest ($$);
sub HMCCURPCPROC_EncodeResponse ($$);

# Binary RPC decoding functions
sub HMCCURPCPROC_DecInteger ($$$);
sub HMCCURPCPROC_DecBool ($$);
sub HMCCURPCPROC_DecString ($$);
sub HMCCURPCPROC_DecDouble ($$);
sub HMCCURPCPROC_DecBase64 ($$);
sub HMCCURPCPROC_DecArray ($$);
sub HMCCURPCPROC_DecStruct ($$);
sub HMCCURPCPROC_DecType ($$);
sub HMCCURPCPROC_DecodeRequest ($);
sub HMCCURPCPROC_DecodeResponse ($);


######################################################################
# Initialize module
######################################################################

sub HMCCURPCPROC_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn}      = "HMCCURPCPROC_Define";
	$hash->{UndefFn}    = "HMCCURPCPROC_Undef";
	$hash->{SetFn}      = "HMCCURPCPROC_Set";
	$hash->{GetFn}      = "HMCCURPCPROC_Get";
	$hash->{ReadFn}     = "HMCCURPCPROC_Read";
	$hash->{AttrFn}     = "HMCCURPCPROC_Attr";
	$hash->{ShutdownFn} = "HMCCURPCPROC_Shutdown";
	
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "ccuflags:multiple-strict,expert,reconnect,logEvents,ccuInit,queueEvents".
		" rpcMaxEvents rpcQueueSend rpcQueueSize rpcMaxIOErrors". 
		" rpcServerAddr rpcServerPort rpcWriteTimeout rpcAcceptTimeout".
		" rpcConnTimeout rpcStatistics rpcEventTimeout ".
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCURPCPROC_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash;
	my $ioname = '';
	my $rpcip = '';
	my $iface;
	my $usage = "Usage: define $name HMCCURPCPROC { CCUHost | iodev={device} } { RPCPort | RPCInterface }";
	
	$hash->{version} = $HMCCURPCPROC_VERSION;

	if (exists ($h->{iodev})) {
		$ioname = $h->{iodev};
		return $usage if (scalar (@$a) < 3);
		return "HMCCU I/O device $ioname not found" if (!exists ($defs{$ioname}));
		return "Device $ioname is not a HMCCU device" if ($defs{$ioname}->{TYPE} ne 'HMCCU');
		$hmccu_hash = $defs{$ioname};
		if (scalar (@$a) < 4) {
			$hash->{host} = $hmccu_hash->{host};
			$iface = $$a[2];
		}
		else {
			$hash->{host} = $$a[2];
			$iface = $$a[3];
		}
		$rpcip = HMCCU_ResolveName ($hash->{host}, 'N/A');
	}
	else {
		return $usage if (scalar (@$a) < 4);
		$hash->{host} = $$a[2];
		$iface = $$a[3];	
		$rpcip = HMCCU_ResolveName ($hash->{host}, 'N/A');

		# Find IO device
		for my $d (keys %defs) {
			my $dh = $defs{$d};
			next if (!exists ($dh->{TYPE}) || !exists ($dh->{NAME}));
			next if ($dh->{TYPE} ne 'HMCCU');
	
			# The following call will fail during FHEM start if CCU is not ready
			my $ifhost = HMCCU_GetRPCServerInfo ($dh, $iface, 'host');
			next if (!defined ($ifhost));
			if ($dh->{host} eq $hash->{host} || $ifhost eq $hash->{host} || $ifhost eq $rpcip) {
				$hmccu_hash = $dh;
				last;
			}
		}
	}

	# Store some definitions for delayed initialization
	$hash->{hmccu}{devspec} = $iface;
	$hash->{rpcip} = $rpcip;
			
	if ($init_done) {
		# Interactive define command while CCU not ready or no IO device defined
		if (!defined ($hmccu_hash)) {
			my ($ccuactive, $ccuinactive) = HMCCU_IODeviceStates ();
			if ($ccuinactive > 0) {
				return "CCU and/or IO device not ready. Please try again later";
			}
			else {
				return "Cannot detect IO device";
			}
		}
	}
	else {
		# CCU not ready during FHEM start
		if (!defined ($hmccu_hash) || $hmccu_hash->{ccustate} ne 'active') {
			Log3 $name, 2, "HMCCURPCPROC: [$name] Cannot detect IO device, maybe CCU not ready. Trying later ...";
			readingsSingleUpdate ($hash, "state", "Pending", 1);
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}

	# Initialize FHEM device, set IO device
	my $rc = HMCCURPCPROC_InitDevice ($hmccu_hash, $hash);
	return "Invalid port or interface $iface" if ($rc == 1);
	return "Can't assign I/O device $ioname" if ($rc == 2);
	return "Invalid local IP address ".$hash->{hmccu}{localaddr} if ($rc == 3);

	return undef;
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = Invalid port or interface
# 2 = Cannot assign IO device
# 3 = Invalid local IP address
######################################################################

sub HMCCURPCPROC_InitDevice ($$) {
	my ($hmccu_hash, $dev_hash) = @_;
	my $name = $dev_hash->{NAME};
	my $iface = $dev_hash->{hmccu}{devspec};
	
	# Check if interface is valid
	my $ifname = HMCCU_GetRPCServerInfo ($hmccu_hash, $iface, 'name'); 
	my $ifport = HMCCU_GetRPCServerInfo ($hmccu_hash, $iface, 'port'); 
	return 1 if (!defined ($ifname) || !defined ($ifport));

	# Check if RPC device with same interface already exists
	for my $d (keys %defs) {
		my $dh = $defs{$d};
		next if (!exists ($dh->{TYPE}) || !exists ($dh->{NAME}));
		if ($dh->{TYPE} eq 'HMCCURPCPROC' && $dh->{NAME} ne $name && IsDisabled ($dh->{NAME}) != 1) {
			return "RPC device for CCU/port already exists"
				if ($dev_hash->{host} eq $dh->{host} && exists ($dh->{rpcport}) && $dh->{rpcport} == $ifport);
		}
	}
	
	# Detect local IP address and check if CCU is reachable
	my $localaddr = HMCCU_TCPConnect ($dev_hash->{host}, $ifport);
	return "Can't connect to CCU ".$dev_hash->{host}." port $ifport" if ($localaddr eq '');
	$dev_hash->{hmccu}{localaddr} = $localaddr;
	$dev_hash->{hmccu}{defaultaddr} = $dev_hash->{hmccu}{localaddr};

	# Get unique ID for RPC server: last 2 segments of local IP address
	# Do not append random digits because of https://forum.fhem.de/index.php/topic,83544.msg797146.html#msg797146
	my @ipseg = split (/\./, $dev_hash->{hmccu}{localaddr});
	return 3 if (scalar (@ipseg) != 4);
	$dev_hash->{rpcid} = sprintf ("%03d%03d", $ipseg[2], $ipseg[3]);

	# Set I/O device and store reference for RPC device in I/O device
	my $ioname = $hmccu_hash->{NAME};
	return 2 if (!HMCCU_AssignIODevice ($dev_hash, $ioname, $ifname));

	# Store internals
	$dev_hash->{rpcport}      = $ifport;
	$dev_hash->{rpcinterface} = $ifname;
	$dev_hash->{ccuip}        = $hmccu_hash->{ccuip};
	$dev_hash->{ccutype}      = $hmccu_hash->{ccutype};
	$dev_hash->{CCUNum}       = $hmccu_hash->{CCUNum};
	$dev_hash->{ccustate}     = $hmccu_hash->{ccustate};
	
	Log3 $name, 1, "HMCCURPCPROC: [$name] Initialized version $HMCCURPCPROC_VERSION for interface $ifname with I/O device $ioname";

	# Set some attributes
	if ($init_done) {
		$attr{$name}{stateFormat} = "rpcstate/state";
		$attr{$name}{verbose} = 2;
	}

	HMCCURPCPROC_ResetRPCState ($dev_hash);
	HMCCURPCPROC_SetState ($dev_hash, 'Initialized');
	
	return 0;
}

######################################################################
# Delete device
######################################################################

sub HMCCURPCPROC_Undef ($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	my $ifname = $hash->{rpcinterface};

	# Shutdown RPC server
	HMCCURPCPROC_Shutdown ($hash);

	# Delete RPC device name in I/O device
	if (exists ($hmccu_hash->{hmccu}{interfaces}{$ifname}{device}) &&
		$hmccu_hash->{hmccu}{interfaces}{$ifname}{device} eq $name) {
		delete $hmccu_hash->{hmccu}{interfaces}{$ifname}{device};
	}
	
	return undef;
}

######################################################################
# Shutdown FHEM
######################################################################

sub HMCCURPCPROC_Shutdown ($)
{
	my ($hash) = @_;

	# Shutdown RPC server
	HMCCURPCPROC_StopRPCServer ($hash);
	RemoveInternalTimer ($hash);

	return undef;
}

######################################################################
# Set attribute
######################################################################

sub HMCCURPCPROC_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};
	
	if ($cmd eq 'set') {
		if (($attrname eq 'rpcAcceptTimeout' || $attrname eq 'rpcMaxEvents') && $attrval == 0) {
			return "HMCCURPCPROC: [$name] Value for attribute $attrname must be greater than 0";
		}
		elsif ($attrname eq 'rpcServerAddr') {
			$hash->{hmccu}{localaddr} = $attrval;
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'rpcServerAddr') {
			$hash->{hmccu}{localaddr} = $hash->{hmccu}{defaultaddr};
		}
	}
	
	return undef;
}

######################################################################
# Set commands
######################################################################

sub HMCCURPCPROC_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $hmccu_hash = $hash->{IODev};
	my $name = shift @$a;
	my $opt = shift @$a;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $options = $ccuflags =~ /expert/ ? "cleanup:noArg deregister:noArg register:noArg rpcrequest rpcserver:on,off" : "";
	my $busyoptions = $ccuflags =~ /expert/ ? "rpcserver:off" : "";

	return "HMCCURPCPROC: CCU busy, choose one of $busyoptions"
		if ($opt ne 'rpcserver' && HMCCURPCPROC_IsRPCStateBlocking ($hash));

	if ($opt eq 'cleanup') {
		HMCCURPCPROC_Housekeeping ($hash);
		return undef;
	}
	elsif ($opt eq 'register') {
		if ($hash->{RPCState} eq 'running') {
			my ($rc, $rcmsg) = HMCCURPCPROC_RegisterCallback ($hash, 2);
			if ($rc) {
				$hash->{ccustate} = 'active';
				return HMCCURPCPROC_SetState ($hash, "OK");
			}
			else {
				return HMCCURPCPROC_SetError ($hash, $rcmsg, 2);
			}
		}
		else {
			return HMCCURPCPROC_SetError ($hash, "RPC server not running", 2);
		}
	}
	elsif ($opt eq 'deregister') {
		my ($rc, $err) = HMCCURPCPROC_DeRegisterCallback ($hash, 1);
		return HMCCURPCPROC_SetError ($hash, $err, 2) if (!$rc);
		return HMCCURPCPROC_SetState ($hash, "OK");
	}
	elsif ($opt eq 'rpcrequest') {
		my $request = shift @$a;
		return HMCCURPCPROC_SetError ($hash, "Usage: set $name rpcrequest {request} [{parameter} ...]", 2)
			if (!defined ($request));

		my $response = HMCCURPCPROC_SendRequest ($hash, $request, @$a);
		return HMCCURPCPROC_SetError ($hash, "RPC request failed", 2) if (!defined ($response));
		return HMCCU_RefToString ($response);
	}
	elsif ($opt eq 'rpcserver') {
		my $action = shift @$a;

		return HMCCURPCPROC_SetError ($hash, "Usage: set $name rpcserver {on|off}", 2)
		   if (!defined ($action) || $action !~ /^(on|off)$/);

		if ($action eq 'on') {
			return HMCCURPCPROC_SetError ($hash, "RPC server already running", 2)
				if ($hash->{RPCState} ne 'inactive' && $hash->{RPCState} ne 'error');
			$hmccu_hash->{hmccu}{interfaces}{$hash->{rpcinterface}}{manager} = 'HMCCURPCPROC';
			my ($rc, $info) = HMCCURPCPROC_StartRPCServer ($hash);
			if (!$rc) {
				HMCCURPCPROC_SetRPCState ($hash, 'error', undef, undef);
				return HMCCURPCPROC_SetError ($hash, $info, 1);
			}
		}
		elsif ($action eq 'off') {
			$hmccu_hash->{hmccu}{interfaces}{$hash->{rpcinterface}}{manager} = 'HMCCURPCPROC';
			HMCCURPCPROC_StopRPCServer ($hash);
		}
		
		return undef;
	}
	else {
		return "HMCCURPCPROC: Unknown argument $opt, choose one of ".$options;
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCURPCPROC_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $options = "rpcevents:noArg rpcstate:noArg";

	return "HMCCURPCPROC: CCU busy, choose one of rpcstate:noArg"
		if ($opt ne 'rpcstate' && HMCCURPCPROC_IsRPCStateBlocking ($hash));

	my $result = 'Command not implemented';
	my $rc;

	if ($opt eq 'rpcevents') {
		my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");
		my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};

		$result = "Event statistics for server $clkey\n";
		$result .= "Average event delay = ".$hash->{hmccu}{rpc}{avgdelay}."\n"
			if (defined ($hash->{hmccu}{rpc}{avgdelay}));
		$result .= "========================================\n";
		$result .= "ET Sent by RPC server   Received by FHEM\n";
		$result .= "----------------------------------------\n";
		foreach my $et (@eventtypes) {
			my $snd = exists ($hash->{hmccu}{rpc}{snd}{$et}) ?
				sprintf ("%7d", $hash->{hmccu}{rpc}{snd}{$et}) : "    n/a"; 
			my $rec = exists ($hash->{hmccu}{rpc}{rec}{$et}) ?
				sprintf ("%7d", $hash->{hmccu}{rpc}{rec}{$et}) : "    n/a"; 
			$result .= "$et            $snd            $rec\n\n";
		}
		return $result eq '' ? "No event statistics found" : $result;
	}
	elsif ($opt eq 'rpcstate') {
		my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};
		$result = "PID   RPC-Process  State   \n";
		$result .= "--------------------------\n";
		my $sid = defined ($hash->{hmccu}{rpc}{pid}) ? sprintf ("%5d", $hash->{hmccu}{rpc}{pid}) : "N/A  ";
		my $sname = sprintf ("%-10s", $clkey);
		$result .= $sid." ".$sname."      ".$hash->{hmccu}{rpc}{state}."\n";
		return $result;
	}
	else {
		return "HMCCURPCPROC: Unknown argument $opt, choose one of ".$options;
	}
}

######################################################################
# Read data from processes
######################################################################

sub HMCCURPCPROC_Read ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	
	my $eventcount = 0;	# Total number of events
	my $devcount = 0;		# Number of DD, ND or RD events
	my $evcount = 0;		# Number of EV events
	my %events = ();
	my %devices = ();
	
	Log3 $name, 4, "HMCCURPCPROC: [$name] Read called";

	# Check if child socket exists
	if (!defined ($hash->{hmccu}{sockchild})) {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Child socket does not exist";
		return;
	}
	
	# Get attributes
	my $rpcmaxevents = AttrVal ($name, 'rpcMaxEvents', $HMCCURPCPROC_MAX_EVENTS);
	my $ccuflags     = AttrVal ($name, 'ccuflags', 'null');
	my $socktimeout  = AttrVal ($name, 'rpcWriteTimeout',  $HMCCURPCPROC_TIMEOUT_WRITE);
	
	# Read events from queue
	while (1) {
		my ($item, $err) = HMCCURPCPROC_ReceiveData ($hash->{hmccu}{sockchild}, $socktimeout);
		if (!defined ($item)) {
			Log3 $name, 4, "HMCCURPCPROC: [$name] Read stopped after $eventcount events $err";
			last;
		}
		
		Log3 $name, 4, "HMCCURPCPROC: [$name] read $item from queue" if ($ccuflags =~ /logEvents/);
		my ($et, $clkey, @par) = HMCCURPCPROC_ProcessEvent ($hash, $item);
		next if (!defined ($et));
		
		if ($et eq 'EV') {
			$events{$par[0]}{$par[1]}{$par[2]} = $par[3];
			$evcount++;
			$hash->{ccustate} = 'active' if ($hash->{ccustate} ne 'active');
		}
		elsif ($et eq 'EX') {
			# I/O already cleaned up. Leave Read()
			last;
		}
		elsif ($et eq 'ND') {
			$devices{$par[0]}{flag} = 'N';
			$devices{$par[0]}{version} = $par[3];
			if ($par[1] eq 'D') {
				$devices{$par[0]}{addtype}  = 'dev';
				$devices{$par[0]}{type}     = $par[2];
				$devices{$par[0]}{firmware} = $par[4];
				$devices{$par[0]}{rxmode}   = $par[5];
			}
			else {
				$devices{$par[0]}{addtype}  = 'chn';
				$devices{$par[0]}{usetype}  = $par[2];
			}
			$devcount++;
		}
		elsif ($et eq 'DD') {
			$devices{$par[0]}{flag} = 'D';
			$devcount++;
		}
		elsif ($et eq 'RD') {
			$devices{$par[0]}{flag} = 'R';
			$devices{$par[0]}{newaddr} = $par[1];			
			$devcount++;
		}
		
		$eventcount++;
		if ($eventcount > $rpcmaxevents) {
			Log3 $name, 4, "HMCCURPCPROC: [$name] Read stopped after $rpcmaxevents events";
			last;
		}
	}

	# Update device table and client device readings
	HMCCU_UpdateDeviceTable ($hmccu_hash, \%devices) if ($devcount > 0);
	HMCCU_UpdateMultipleDevices ($hmccu_hash, \%events) if ($evcount > 0);
	
	Log3 $name, 4, "HMCCURPCPROC: [$name] Read finished";
}

######################################################################
# Set error state and write log file message
# Parameter level is optional. Default value for level is 1.
######################################################################

sub HMCCURPCPROC_SetError ($$$)
{
	my ($hash, $text, $level) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $msg;

	$msg = defined ($text) ? $text : "unknown error";
	$msg = $type.": [".$name."] ". $msg;

	HMCCURPCPROC_SetState ($hash, "error");
	Log3 $name, (defined($level) ? $level : 1), $msg;
	
	return $msg;
}

######################################################################
# Set state of device
######################################################################

sub HMCCURPCPROC_SetState ($$)
{
	my ($hash, $state) = @_;
	my $name = $hash->{NAME};
	
	if (defined ($state)) {
		readingsSingleUpdate ($hash, "state", $state, 1);
		Log3 $name, 4, "HMCCURPCPROC: [$name] Set state to $state";
	}

	return undef;
}

######################################################################
# Set state of RPC server
# Parameters msg and level are optional. Default for level is 1.
######################################################################

sub HMCCURPCPROC_SetRPCState ($$$$)
{
	my ($hash, $state, $msg, $level) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	
	return undef if (exists ($hash->{RPCState}) && $hash->{RPCState} eq $state);

	$hash->{hmccu}{rpc}{state} = $state;
	$hash->{RPCState} = $state;
	
	readingsSingleUpdate ($hash, "rpcstate", $state, 1);
	
	HMCCURPCPROC_SetState ($hash, 'busy') if ($state ne 'running' && $state ne 'inactive' &&
		$state ne 'error' && ReadingsVal ($name, 'state', '') ne 'busy');
		 
	Log3 $name, (defined($level) ? $level : 1), "HMCCURPCPROC: [$name] $msg" if (defined ($msg));
	Log3 $name, 4, "HMCCURPCPROC: [$name] Set rpcstate to $state";
	
	# Set state of interface in I/O device
	HMCCU_SetRPCState ($hmccu_hash, $state, $hash->{rpcinterface});
	
	return undef;
}

######################################################################
# Reset RPC State
######################################################################

sub HMCCURPCPROC_ResetRPCState ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 4, "HMCCURPCPROC: [$name] Reset RPC state";
	
	$hash->{RPCPID} = "0";
	$hash->{hmccu}{rpc}{pid} = undef;
	$hash->{hmccu}{rpc}{clkey} = undef;
	$hash->{hmccu}{evtime} = 0;
	$hash->{hmccu}{rpcstarttime} = 0;

	return HMCCURPCPROC_SetRPCState ($hash, 'inactive', undef, undef);
}

######################################################################
# Check if CCU is busy due to RPC start or stop
######################################################################

sub HMCCURPCPROC_IsRPCStateBlocking ($)
{
	my ($hash) = @_;

	return ($hash->{RPCState} eq "running" || $hash->{RPCState} eq "inactive") ? 0 : 1;
}

######################################################################
# Process RPC server event
######################################################################

sub HMCCURPCPROC_ProcessEvent ($$)
{
	my ($hash, $event) = @_;
	my $name = $hash->{NAME};
	my $rpcname = 'CB'.$hash->{rpcport}.$hash->{rpcid};
	my $rh = \%{$hash->{hmccu}{rpc}};	# Just for code simplification
	my $hmccu_hash = $hash->{IODev};

	# Number of arguments in RPC events (without event type and clkey)
	my %rpceventargs = (
		"EV", 4,
		"ND", 6,
		"DD", 1,
		"RD", 2,
		"RA", 1,
		"UD", 2,
		"IN", 2,
		"EX", 2,
		"SL", 1,
		"TO", 1,
		"ST", 11
	);

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $evttimeout = HMCCURPCPROC_GetAttribute ($hash, 'rpcEventTimeout', 'rpcevtimeout',
		$HMCCURPCPROC_TIMEOUT_EVENT);

	# Parse event
	return undef if (!defined ($event) || $event eq '');
	my @t = split (/\|/, $event);
	my $et = shift @t;
	my $clkey = shift @t;
	my $tc = scalar (@t);

	# Log event
	Log3 $name, 2, "HMCCURPCPROC: [$name] CCUEvent = $event" if ($ccuflags =~ /logEvents/);

	# Check event data
	if (!defined ($clkey)) {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Syntax error in RPC event data";
		return undef;
	}
	
	# Check for valid server
	if ($clkey ne $rpcname) {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Received $et event for unknown RPC server $clkey";
		return undef;
	}

	# Check event type
	if (!exists ($rpceventargs{$et})) {
		$et =~ s/([\x00-\xFF])/sprintf("0x%X ",ord($1))/eg;
		Log3 $name, 2, "HMCCURPCPROC: [$name] Received unknown event from CCU: ".$et;
		return undef;
	}
	
	# Check event parameters
	if ($tc != $rpceventargs{$et}) {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Wrong number of parameters in event $event. Expected ". 
			$rpceventargs{$et};
		return undef;
	}

	# Update statistic counters
	$rh->{rec}{$et}++;
	$rh->{evtime} = time ();
	
	if ($et eq 'EV') {
		#
		# Update of datapoint
		# Input:  EV|clkey|Time|Address|Datapoint|Value
		# Output: EV, clkey, DevAdd, ChnNo, Datapoint, Value
		#
		my $delay = $rh->{evtime}-$t[0];
		$rh->{sumdelay} += $delay;
		$rh->{avgdelay} = $rh->{sumdelay}/$rh->{rec}{$et};
		$hash->{ccustate} = 'active' if ($hash->{ccustate} ne 'active');
		Log3 $name, 3, "HMCCURPCPROC: [$name] Received CENTRAL event. ".$t[2]."=".$t[3] if ($t[1] eq 'CENTRAL');
		my ($add, $chn) = split (/:/, $t[1]);
		return defined ($chn) ? ($et, $clkey, $add, $chn, $t[2], $t[3]) : undef;
	}
	elsif ($et eq 'SL') {
		#
		# RPC server enters server loop
		# Input:  SL|clkey|Pid
		# Output: SL, clkey, countWorking
		#
		if ($t[0] == $rh->{pid}) {
			HMCCURPCPROC_SetRPCState ($hash, 'working', "RPC server $clkey enters server loop", 2);
			my ($rc, $rcmsg) = HMCCURPCPROC_RegisterCallback ($hash, 0);
			if (!$rc) {
				HMCCURPCPROC_SetRPCState ($hash, 'error', $rcmsg, 1);
				return ($et, $clkey, 1, 0, 0, 0);
			}
			else {
				HMCCURPCPROC_SetRPCState ($hash, $rcmsg, "RPC server $clkey $rcmsg", 1);
			}
			my $srun = HMCCURPCPROC_RPCServerStarted ($hash);
			return ($et, $clkey, ($srun == 0 ? 1 : 0), $srun);
		}
		else {
			Log3 $name, 0, "HMCCURPCPROC: [$name] Received SL event. Wrong PID=".$t[0]." for RPC server $clkey";
			return undef;
		}
	}
	elsif ($et eq 'IN') {
		#
		# RPC server initialized
		# Input:  IN|clkey|INIT|State
		# Output: IN, clkey, Running, ClientsUpdated, UpdateErrors
		#
		return ($et, $clkey, 0, 0, 0) if ($rh->{state} eq 'running');
		
		HMCCURPCPROC_SetRPCState ($hash, 'running', "RPC server $clkey running.", 1);
		my $run = HMCCURPCPROC_RPCServerStarted ($hash);
		return ($et, $clkey, $run);
	}
	elsif ($et eq 'EX') {
		#
		# Process stopped
		# Input:  EX|clkey|SHUTDOWN|Pid
		# Output: EX, clkey, Pid, Stopped, All
		#
		HMCCURPCPROC_SetRPCState ($hash, 'inactive', "RPC server process $clkey terminated.", 1);
		HMCCURPCPROC_RPCServerStopped ($hash);
		return ($et, $clkey, $t[1], 1, 1);
	}
	elsif ($et eq 'ND') {
		#
		# CCU device added
		# Input:  ND|clkey|C/D|Address|Type|Version|Firmware|RxMode
		# Output: ND, clkey, DevAdd, C/D, Type, Version, Firmware, RxMode
		#
		return ($et, $clkey, $t[1], $t[0], $t[2], $t[3], $t[4], $t[5]);
	}
	elsif ($et eq 'DD' || $et eq 'RA') {
		#
		# CCU device deleted or readded
		# Input:  {DD,RA}|clkey|Address
		# Output: {DD,RA}, clkey, DevAdd
		#
		return ($et, $clkey, $t[0]);
	}
	elsif ($et eq 'UD') {
		#
		# CCU device updated
		# Input:  UD|clkey|Address|Hint
		# Output: UD, clkey, DevAdd, Hint
		#
		return ($et, $clkey, $t[0], $t[1]);
	}
	elsif ($et eq 'RD') {
		#
		# CCU device replaced
		# Input:  RD|clkey|Address1|Address2
		# Output: RD, clkey, Address1, Address2
		#
		return ($et, $clkey, $t[0], $t[1]);
	}
	elsif ($et eq 'ST') {
		#
		# Statistic data. Store snapshots of sent events.
		# Input:  ST|clkey|nTotal|nEV|nND|nDD|nRD|nRA|nUD|nIN|nEX|nSL
		# Output: ST, clkey, ...
		#
		my @res = ($et, $clkey);
		push (@res, @t);
		my $total = shift @t;
		my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");
		for (my $i=0; $i<scalar(@eventtypes); $i++) {
			$hash->{hmccu}{rpc}{snd}{$eventtypes[$i]} += $t[$i];
		}
		return @res;
	}
	elsif ($et eq 'TO') {
		#
		# Event timeout
		# Input:  TO|clkey|Time
		# Output: TO, clkey, Port, Time
		#
		if ($evttimeout > 0 && $evttimeout >= $t[0]) {
			Log3 $name, 2, "HMCCURPCPROC: [$name] Received no events from interface $clkey for ".$t[0]." seconds";
			$hash->{ccustate} = 'timeout';
			if ($hash->{RPCState} eq 'running' && $ccuflags =~ /reconnect/) {
				Log3 $name, 2, "HMCCURPCPROC: [$name] Reconnecting to CCU interface ".$hash->{rpcinterface};
				my ($rc, $rcmsg) = HMCCURPCPROC_RegisterCallback ($hash, 2);
				if ($rc) {
					$hash->{ccustate} = 'active';
				}
				else {
					Log3 $name, 1, "HMCCURPCPROC: [$name] $rcmsg";
				}
			}
			DoTrigger ($name, "No events from interface $clkey for ".$t[0]." seconds");
		}
		return ($et, $clkey, $hash->{rpcport}, $t[0]);
	}

	return undef;
}

######################################################################
# Get attribute with fallback to I/O device attribute
######################################################################

sub HMCCURPCPROC_GetAttribute ($$$$)
{
	my ($hash, $attr, $ioattr, $default) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	my $value = 'null';
	
	if (defined ($attr)) {
		$value = AttrVal ($name, $attr, 'null');
		return $value if ($value ne 'null');
	}
	
	if (defined ($ioattr)) {
		$value = AttrVal ($hmccu_hash->{NAME}, $ioattr, 'null');
		return $value if ($value ne 'null');
	}
	
	return $default;
}

######################################################################
# Register callback for specified CCU interface port.
# Parameter force:
# 1: callback will be registered even if state is "running". State
#    will not be modified.
# 2: CCU connectivity is checked before registering RPC server.
# Return (1, new state) on success. New state is 'running' if flag
# ccuInit is not set. Otherwise 'registered'.
# Return (0, errormessage) on error.
######################################################################

sub HMCCURPCPROC_RegisterCallback ($$)
{
	my ($hash, $force) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	my $port = $hash->{rpcport};
	my $serveraddr = $hash->{host};
	my $localaddr = $hash->{hmccu}{localaddr};
	my $clkey = 'CB'.$port.$hash->{rpcid};
	
	return (0, "RPC server $clkey not in state working")
		if ($hash->{hmccu}{rpc}{state} ne 'working' && $force == 0);

	if ($force == 2) {
		return (0, "CCU port $port not reachable") if (!HMCCU_TCPConnect ($hash->{host}, $port));
	}

	my $cburl = HMCCU_GetRPCCallbackURL ($hmccu_hash, $localaddr, $hash->{hmccu}{rpc}{cbport}, $clkey, $port);
	my $clurl = HMCCU_GetRPCServerInfo ($hmccu_hash, $port, 'url');
	my $rpctype = HMCCU_GetRPCServerInfo ($hmccu_hash, $port, 'type');
	return (0, "Can't get RPC parameters for ID $clkey") if (!defined ($cburl) || !defined ($clurl) || !defined ($rpctype));
	
	$hash->{hmccu}{rpc}{port} = $port;
	$hash->{hmccu}{rpc}{clurl} = $clurl;
	$hash->{hmccu}{rpc}{cburl} = $cburl;

	Log3 $name, 2, "HMCCURPCPROC: [$name] Registering callback $cburl of type $rpctype with ID $clkey at $clurl";
	my $rc;
	if ($rpctype eq 'A') {
		$rc = HMCCURPCPROC_SendRequest ($hash, "init", $cburl, $clkey);
	}
	else {
		$rc = HMCCURPCPROC_SendRequest ($hash, "init", $BINRPC_STRING, $cburl, $BINRPC_STRING, $clkey);
	}

	if (defined ($rc)) {
		return (1, $ccuflags !~ /ccuInit/ ? 'running' : 'registered');
	}
	else {
		return (0, "Failed to register callback for ID $clkey");
	}
}

######################################################################
# Deregister RPC callbacks at CCU
######################################################################

sub HMCCURPCPROC_DeRegisterCallback ($$)
{
	my ($hash, $force) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	
	my $port = $hash->{rpcport};
	my $clkey = 'CB'.$port.$hash->{rpcid};
	my $localaddr = $hash->{hmccu}{localaddr};
	my $cburl = '';
	my $clurl = '';
	my $rpchash = \%{$hash->{hmccu}{rpc}};

	return (0, "RPC server $clkey not in state registered or running")
		if ($rpchash->{state} ne 'registered' && $rpchash->{state} ne 'running' && $force == 0);

	$cburl = $rpchash->{cburl} if (exists ($rpchash->{cburl}));
	$clurl = $rpchash->{clurl} if (exists ($rpchash->{clurl}));
	$cburl = HMCCU_GetRPCCallbackURL ($hmccu_hash, $localaddr, $rpchash->{cbport}, $clkey, $port) if ($cburl eq '');
	$clurl = HMCCU_GetRPCServerInfo ($hmccu_hash, $port, 'url') if ($clurl eq '');
	return (0, "Can't get RPC parameters for ID $clkey") if ($cburl eq '' || $clurl eq '');

	Log3 $name, 1, "HMCCURPCPROC: [$name] Deregistering RPC server $cburl with ID $clkey at $clurl";
	
	# Deregister up to 2 times
	for (my $i=0; $i<2; $i++) {
		my $rc;
		if (HMCCU_IsRPCType ($hmccu_hash, $port, 'A')) {
			$rc = HMCCURPCPROC_SendRequest ($hash, "init", $cburl);
		}
		else {
			$rc = HMCCURPCPROC_SendRequest ($hash, "init", $BINRPC_STRING, $cburl);
		}

		if (defined ($rc)) {
			HMCCURPCPROC_SetRPCState ($hash, $force == 0 ? 'deregistered' : $rpchash->{state},
				"Callback for RPC server $clkey deregistered", 1);

			$rpchash->{cburl} = '';
			$rpchash->{clurl} = '';
			$rpchash->{cbport} = 0;
		
			return (1, 'working');
		}
	}
	
	return (0, "Failed to deregister RPC server $clkey");
}

######################################################################
# Initialize RPC server for specified CCU port
# Return server object or undef on error
######################################################################

sub HMCCURPCPROC_InitRPCServer ($$$$)
{
	my ($name, $clkey, $callbackport, $prot) = @_;
	my $server;

	# Create binary RPC server
	if ($prot eq 'B') {
		$server->{__daemon} = IO::Socket::INET->new (LocalPort => $callbackport,
			Type => SOCK_STREAM, Reuse => 1, Listen => SOMAXCONN);
		if (!($server->{__daemon})) {
			Log3 $name, 1, "HMCCURPCPROC: [$name] Can't create RPC callback server $clkey on port $callbackport. Port in use?";
			return undef;
		}
		return $server;
	}
	
	# Create XML RPC server
	$server = RPC::XML::Server->new (port => $callbackport);
	if (!ref($server)) {
		Log3 $name, 1, "HMCCURPCPROC: [$name] Can't create RPC callback server $clkey on port $callbackport. Port in use?";
		return undef;
	}
	Log3 $name, 2, "HMCCURPCPROC: [$name] Callback server $clkey created. Listening on port $callbackport";

	# Callback for events
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for events for server $clkey";
	$server->add_method (
	   { name=>"event",
	     signature=> ["string string string string string","string string string string int",
		 "string string string string double","string string string string boolean",
		 "string string string string i4"],
	     code=>\&HMCCURPCPROC_EventCB
	   }
	);

	# Callback for new devices
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for new devices for server $clkey";
	$server->add_method (
	   { name=>"newDevices",
	     signature=>["string string array"],
         code=>\&HMCCURPCPROC_NewDevicesCB
	   }
	);

	# Callback for deleted devices
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for deleted devices for server $clkey";
	$server->add_method (
	   { name=>"deleteDevices",
	     signature=>["string string array"],
         code=>\&HMCCURPCPROC_DeleteDevicesCB
	   }
	);

	# Callback for modified devices
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for modified devices for server $clkey";
	$server->add_method (
	   { name=>"updateDevice",
	     signature=>["string string string int", "string string string i4"],
	     code=>\&HMCCURPCPROC_UpdateDeviceCB
	   }
	);

	# Callback for replaced devices
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for replaced devices for server $clkey";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string string string"],
	     code=>\&HMCCURPCPROC_ReplaceDeviceCB
	   }
	);

	# Callback for readded devices
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for readded devices for server $clkey";
	$server->add_method (
	   { name=>"readdedDevice",
	     signature=>["string string array"],
	     code=>\&HMCCURPCPROC_ReaddDeviceCB
	   }
	);
	
	# Dummy implementation, always return an empty array
	Log3 $name, 4, "HMCCURPCPROC: [$name] Adding callback for list devices for server $clkey";
	$server->add_method (
	   { name=>"listDevices",
	     signature=>["array string"],
	     code=>\&HMCCURPCPROC_ListDevicesCB
	   }
	);

	return $server;
}

######################################################################
# Start RPC server process
# Return (State, Msg)
######################################################################

sub HMCCURPCPROC_StartRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};

	# Local IP address and callback ID should be set during device definition
	return (0, "Local address and/or callback ID not defined")
		if (!exists ($hash->{hmccu}{localaddr}) || !exists ($hash->{rpcid}));
		
	# Check if RPC server is already running
	return (0, "RPC server already running") if (HMCCURPCPROC_CheckProcessState ($hash, 'running'));
	
	# Get parameters and attributes
	my %procpar;
	my $localaddr     = HMCCURPCPROC_GetAttribute ($hash, undef, 'rpcserveraddr', $hash->{hmccu}{localaddr});
	my $rpcserverport = HMCCURPCPROC_GetAttribute ($hash, 'rpcServerPort', 'rpcserverport', $HMCCURPCPROC_SERVER_PORT);
	my $evttimeout    = HMCCURPCPROC_GetAttribute ($hash, 'rpcEventTimeout', 'rpcevtimeout', $HMCCURPCPROC_TIMEOUT_EVENT);
	my $ccunum        = $hash->{CCUNum};
	my $rpcport       = $hash->{rpcport};
	my $serveraddr    = HMCCU_GetRPCServerInfo ($hmccu_hash, $rpcport, 'host');
	my $interface     = HMCCU_GetRPCServerInfo ($hmccu_hash, $rpcport, 'name');
	my $clkey         = 'CB'.$rpcport.$hash->{rpcid};
	$hash->{hmccu}{localaddr} = $localaddr;

	# Store parameters for child process
	$procpar{socktimeout} = AttrVal ($name, 'rpcWriteTimeout',  $HMCCURPCPROC_TIMEOUT_WRITE);
	$procpar{conntimeout} = AttrVal ($name, 'rpcConnTimeout',   $HMCCURPCPROC_TIMEOUT_CONNECTION);
	$procpar{acctimeout}  = AttrVal ($name, 'rpcAcceptTimeout', $HMCCURPCPROC_TIMEOUT_ACCEPT);
	$procpar{evttimeout}  = AttrVal ($name, 'rpcEventTimeout',  $HMCCURPCPROC_TIMEOUT_EVENT);
	$procpar{queuesize}   = AttrVal ($name, 'rpcQueueSize',     $HMCCURPCPROC_MAX_QUEUESIZE);
	$procpar{queuesend}   = AttrVal ($name, 'rpcQueueSend',     $HMCCURPCPROC_MAX_QUEUESEND);
	$procpar{statistics}  = AttrVal ($name, 'rpcStatistics',    $HMCCURPCPROC_STATISTICS);
	$procpar{maxioerrors} = AttrVal ($name, 'rpcMaxIOErrors',   $HMCCURPCPROC_MAX_IOERRORS);
	$procpar{evttimeout}  = AttrVal ($name, 'rpcEventTimeout',  $HMCCURPCPROC_TIMEOUT_EVENT);
	$procpar{ccuflags}    = AttrVal ($name, 'ccuflags',         'null');
	$procpar{interface}   = $interface;
	$procpar{flags}       = HMCCU_GetRPCServerInfo ($hmccu_hash, $rpcport, 'flags');
	$procpar{type}        = HMCCU_GetRPCServerInfo ($hmccu_hash, $rpcport, 'type');
	$procpar{name}        = $name;
	$procpar{clkey}       = $clkey;
	
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");

	# Reset state of server processes
	$hash->{hmccu}{rpc}{state} = 'inactive';

	# Create socket pair for communication between RPC server process and FHEM process
	my ($sockchild, $sockparent);
	return (0, "Can't create I/O socket pair")
		if (!socketpair ($sockchild, $sockparent, AF_UNIX, SOCK_STREAM, PF_UNSPEC));
	$sockchild->autoflush (1);
	$sockparent->autoflush (1);
	$hash->{hmccu}{sockparent} = $sockparent;
	$hash->{hmccu}{sockchild} = $sockchild;

	# Enable FHEM I/O
	my $pid = $$;
	$hash->{FD} = fileno $sockchild;
	$selectlist{"RPC.$name.$pid"} = $hash; 
	
	# Initialize RPC server
	my $err = '';
	my %srvprocpar;
	my $callbackport = $rpcserverport+$rpcport+($ccunum*10);

	# Start RPC server process
	my $rpcpid = fhemFork ();
	if (!defined ($rpcpid)) {
		close ($sockparent);
		close ($sockchild);
		return (0, "Can't create RPC server process for interface $interface");
	}
		
	if (!$rpcpid) {
		# Child process, only needs parent socket
		HMCCURPCPROC_HandleConnection ($rpcport, $callbackport, $sockparent, \%procpar);
		# Exit child process
		close ($sockparent);
		close ($sockchild);
		exit (0);
	}

	# Parent process
	Log3 $name, 2, "HMCCURPCPROC: [$name] RPC server process started for interface $interface with PID=$rpcpid";

	# Store process parameters
	$hash->{hmccu}{rpc}{clkey}  = $clkey;
	$hash->{hmccu}{rpc}{cbport} = $callbackport;
	$hash->{hmccu}{rpc}{pid}    = $rpcpid;
	$hash->{hmccu}{rpc}{state}  = 'initialized';
		
	# Reset statistic counter
	foreach my $et (@eventtypes) {
		$hash->{hmccu}{rpc}{rec}{$et} = 0;
		$hash->{hmccu}{rpc}{snd}{$et} = 0;
	}
	$hash->{hmccu}{rpc}{sumdelay} = 0;

	$hash->{RPCPID} = $rpcpid;

	# Trigger Timer function for checking successful RPC start
	# Timer will be removed before execution if event 'IN' is reveived
	InternalTimer (gettimeofday()+$HMCCURPCPROC_INIT_INTERVAL3, "HMCCURPCPROC_IsRPCServerRunning",
		$hash, 0);
	
	HMCCURPCPROC_SetRPCState ($hash, "starting", "RPC server starting", 1);	
	DoTrigger ($name, "RPC server starting");
	
	return (1, undef);
}

######################################################################
# Set overall status if all RPC servers are running and update all
# FHEM devices.
# Return (State, updated devices, failed updates)
######################################################################

sub HMCCURPCPROC_RPCServerStarted ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};
	my $ifname = $hash->{rpcinterface};
	
	# Check if RPC servers are running. Set overall status
	if (HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
		$hash->{hmccu}{rpcstarttime} = time ();
		HMCCURPCPROC_SetState ($hash, "OK");

		if ($hmccu_hash->{hmccu}{interfaces}{$ifname}{manager} eq 'HMCCURPCPROC') {
			my ($c_ok, $c_err) = HMCCU_UpdateClients ($hmccu_hash, '.*', 'Attr', 0, $ifname);
			Log3 $name, 2, "HMCCURPCPROC: [$name] Updated devices. Success=$c_ok Failed=$c_err";
		}
		
		RemoveInternalTimer ($hash);
		DoTrigger ($name, "RPC server $clkey running");
		return 1;
	}
	
	return 0;
}

######################################################################
# Cleanup if RPC server stopped
######################################################################

sub HMCCURPCPROC_RPCServerStopped ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};

	HMCCURPCPROC_CleanupProcess ($hash);
	HMCCURPCPROC_CleanupIO ($hash);
	
	HMCCURPCPROC_ResetRPCState ($hash);
	HMCCURPCPROC_SetState ($hash, "OK");
	
	RemoveInternalTimer ($hash);
	DoTrigger ($name, "RPC server $clkey stopped");
}

######################################################################
# Stop I/O Handling
######################################################################

sub HMCCURPCPROC_CleanupIO ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $pid = $$;
	if (exists ($selectlist{"RPC.$name.$pid"})) {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Stop I/O handling";
		delete $selectlist{"RPC.$name.$pid"};
		delete $hash->{FD} if (defined ($hash->{FD}));
	}
	if (defined ($hash->{hmccu}{sockchild})) {
		Log3 $name, 3, "HMCCURPCPROC: [$name] Close child socket";
		$hash->{hmccu}{sockchild}->close ();
		delete $hash->{hmccu}{sockchild};
	}
	if (defined ($hash->{hmccu}{sockparent})) {
		Log3 $name, 3, "HMCCURPCPROC: [$name] Close parent socket";
		$hash->{hmccu}{sockparent}->close ();
		delete $hash->{hmccu}{sockparent};
	}
}

######################################################################
# Terminate RPC server process by sending an INT signal.
# Return 0 if RPC server not running.
######################################################################

sub HMCCURPCPROC_TerminateProcess ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};
	
#	return 0 if ($hash->{hmccu}{rpc}{state} eq 'inactive');
	
	my $pid = $hash->{hmccu}{rpc}{pid};
	if (defined ($pid) && kill (0, $pid)) {
		HMCCURPCPROC_SetRPCState ($hash, 'stopping', "Sending signal INT to RPC server process $clkey with PID=$pid", 2);
		kill ('INT', $pid);
		return 1;
	}
	else {
		HMCCURPCPROC_SetRPCState ($hash, 'inactive', "RPC server process $clkey not runnning", 1);
		return 0;
	}
}

######################################################################
# Cleanup inactive RPC server process.
# Return 0 if process is running.
######################################################################

sub HMCCURPCPROC_CleanupProcess ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};
	
#	return 1 if ($hash->{hmccu}{rpc}{state} eq 'inactive');
	
	my $pid = $hash->{hmccu}{rpc}{pid};
	if (defined ($pid) && kill (0, $pid)) {
		Log3 $name, 1, "HMCCURPCPROC: [$name] Process $clkey with PID=$pid".
			" still running. Killing it.";
		kill ('KILL', $pid);
		sleep (1);
		if (kill (0, $pid)) {
			Log3 $name, 1, "HMCCURPCPROC: [$name] Can't kill process $clkey with PID=$pid";
			return 0;
		}
	}
	
	HMCCURPCPROC_SetRPCState ($hash, 'inactive', "RPC server process $clkey deleted", 2);
	$hash->{hmccu}{rpc}{pid} = undef;
	
	return 1;
}

######################################################################
# Check if RPC server process is in specified state.
# Parameter state is a regular expression. Valid states are:
#   inactive
#   starting
#   working
#   registered
#   running
#   stopping
# If state is 'running' the process is checked by calling kill() with
# signal 0.
######################################################################

sub HMCCURPCPROC_CheckProcessState ($$)
{
	my ($hash, $state) = @_;
	my $prcname = 'CB'.$hash->{rpcport}.$hash->{rpcid};

	my $pstate = $hash->{hmccu}{rpc}{state};
	if ($state eq 'running' || $state eq '.*') {
		my $pid = $hash->{hmccu}{rpc}{pid};
		return (defined ($pid) && $pid != 0 && kill (0, $pid) && $pstate =~ /$state/) ? $pid : 0
	}
	else {
		return ($pstate =~ /$state/) ? 1 : 0;
	}
}

######################################################################
# Timer function to check if RPC server process is running.
# Call Housekeeping() if process is not running.
######################################################################

sub HMCCURPCPROC_IsRPCServerRunning ($)
{
	my ($hash, $cleanup) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 2, "HMCCURPCPROC: [$name] Checking if RPC server process is running";
	if (!HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
		Log3 $name, 1, "HMCCURPCPROC: [$name] RPC server process not running. Cleaning up";
		HMCCURPCPROC_Housekeeping ($hash);
		return 0;
	}

	Log3 $name, 2, "HMCCURPCPROC: [$name] RPC server process running";
	return 1;
}

######################################################################
# Cleanup RPC server environment.
######################################################################

sub HMCCURPCPROC_Housekeeping ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 1, "HMCCURPCPROC: [$name] Housekeeping called. Cleaning up RPC environment";

	# Deregister callback URLs in CCU
	HMCCURPCPROC_DeRegisterCallback ($hash, 0);

	# Terminate process by sending signal INT
	sleep (2) if (HMCCURPCPROC_TerminateProcess ($hash));
	
	# Next call will cleanup IO, processes and reset RPC state
	HMCCURPCPROC_RPCServerStopped ($hash);
}

######################################################################
# Stop RPC server processes.
######################################################################

sub HMCCURPCPROC_StopRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $clkey = 'CB'.$hash->{rpcport}.$hash->{rpcid};

	if (HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
		Log3 $name, 1, "HMCCURPCPROC: [$name] Stopping RPC server $clkey";
		HMCCURPCPROC_SetState ($hash, "busy");

		# Deregister callback URLs in CCU
		my ($rc, $err) = HMCCURPCPROC_DeRegisterCallback ($hash, 0);
		Log3 $name, 1, "HMCCURPCPROC: [$name] $err" if (!$rc);

		# Stop RPC server process 
 		HMCCURPCPROC_TerminateProcess ($hash);

		# Trigger timer function for checking successful RPC stop
		# Timer will be removed wenn receiving EX event from RPC server process
		InternalTimer (gettimeofday()+$HMCCURPCPROC_INIT_INTERVAL2, "HMCCURPCPROC_Housekeeping",
			$hash, 0);
		
		# Give process the chance to terminate
		sleep (1);
		return 1;
	}
	else {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Found no running processes. Cleaning up ...";
		HMCCURPCPROC_Housekeeping ($hash);
		return 0;
	}
}

######################################################################
# Send RPC request to CCU.
# Supports XML and BINRPC requests.
# Return response or undef on error.
######################################################################

sub HMCCURPCPROC_SendRequest ($@)
{
	my ($hash, $request, @param) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash = $hash->{IODev};
	my $port = $hash->{rpcport};
	
	my $rc;
	
	if (HMCCU_IsRPCType ($hmccu_hash, $port, 'A')) {
		my $clurl = HMCCU_GetRPCServerInfo ($hmccu_hash, $port, 'url');
		return HMCCU_Log ($hash, 2, "Can't get client URL for port $port", undef)
			if (!defined ($clurl));
		
		Log3 $name, 4, "HMCCURPCPROC: [$name] Send ASCII RPC request $request to $clurl";
		my $rpcclient = RPC::XML::Client->new ($clurl);
		$rc = $rpcclient->simple_request ($request, @param);
		Log3 $name, 2, "HMCCURPCPROC: [$name] RPC request error ".$RPC::XML::ERROR if (!defined ($rc));
	}
	elsif (HMCCU_IsRPCType ($hmccu_hash, $port, 'B')) {
		my $serveraddr = HMCCU_GetRPCServerInfo ($hmccu_hash, $port, 'host');
		return HMCCU_Log ($hash, 2, "Can't get server address for port $port", undef)
			if (!defined ($serveraddr));
	
		my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
		my $verbose = GetVerbose ($name);
	
		Log3 $name, 4, "HMCCURPCPROC: [$name] Send binary RPC request $request to $serveraddr:$port";
		my $encreq = HMCCURPCPROC_EncodeRequest ($request, \@param);
		return HMCCU_Log ($hash, 2, "Error encoding binary request", undef) if ($encreq eq '');

		# auto-flush on socket
		$| = 1;

		# create a connecting socket
		my $socket = new IO::Socket::INET (PeerHost => $serveraddr, PeerPort => $port,
			Proto => 'tcp');
		return HMCCU_Log ($hash, 2, "Can't create socket for $serveraddr:$port", undef) if (!$socket);
	
		my $size = $socket->send ($encreq);
		if (defined ($size)) {
			my $encresp = <$socket>;
			$socket->close ();
		
			if (defined ($encresp)) {
				if ($ccuflags =~ /logEvents/ && $verbose >= 4) {
					Log3 $name, 4, "HMCCURPCPROC: [$name] Response";
					HMCCURPCPROC_HexDump ($name, $encresp);
				}
				my ($response, $err) = HMCCURPCPROC_DecodeResponse ($encresp);
				return $response;
			}
			else {
				return '';
			}
		}
	
		$socket->close ();
	}
	else {
		Log3 $name, 2, "HMCCURPCPROC: [$name] Unknown RPC server type";
	}
	
	return $rc;
}

######################################################################
# Process binary RPC request
######################################################################

sub HMCCURPCPROC_ProcessRequest ($$)
{
	my ($server, $connection) = @_;
	my $name = $server->{hmccu}{name};
	my $clkey = $server->{hmccu}{clkey};
	my @methodlist = ('listDevices', 'listMethods', 'system.multicall');
	my $verbose = GetVerbose ($name);
	
	# Read request
	my $request = '';
	while  (my $packet = <$connection>) {
		$request .= $packet;
	}
	return if (!defined ($request) || $request eq '');
	
	if ($server->{hmccu}{ccuflags} =~ /logEvents/ && $verbose >= 4) {
		Log3 $name, 4, "CCURPC: [$name] $clkey raw request:";
		HMCCURPCPROC_HexDump ($name, $request);
	}
	
	# Decode request
	my ($method, $params) = HMCCURPCPROC_DecodeRequest ($request);
	return if (!defined ($method));
	Log3 $name, 4, "CCURPC: [$name] request method = $method";
	
	if ($method eq 'listmethods') {
		$connection->send (HMCCURPCPROC_EncodeResponse ($BINRPC_ARRAY, \@methodlist));
	}
	elsif ($method eq 'listdevices') {
		HMCCURPCPROC_ListDevicesCB ($server, $clkey);
		$connection->send (HMCCURPCPROC_EncodeResponse ($BINRPC_ARRAY, undef));
	}
	elsif ($method eq 'system.multicall') {
		return if (ref ($params) ne 'ARRAY');
		my $a = $$params[0];
		foreach my $s (@$a) {
			next if (!exists ($s->{methodName}) || !exists ($s->{params}));
			next if ($s->{methodName} ne 'event');
			next if (scalar (@{$s->{params}}) < 4);
 			HMCCURPCPROC_EventCB ($server, $clkey,
 				${$s->{params}}[1], ${$s->{params}}[2], ${$s->{params}}[3]);
 			Log3 $name, 4, "CCURPC: [$name] Event ".${$s->{params}}[1]." ".${$s->{params}}[2]." "
 				.${$s->{params}}[3];
		}
	}
}

######################################################################
# Subprocess function for handling incoming RPC requests
######################################################################

sub HMCCURPCPROC_HandleConnection ($$$$)
{
	my ($port, $callbackport, $sockparent, $procpar) = @_;
	my $name = $procpar->{name};
	
	my $iface       = $procpar->{interface};
	my $prot        = $procpar->{type};
	my $evttimeout  = $procpar->{evttimeout};
	my $conntimeout = $procpar->{conntimeout};
	my $acctimeout  = $procpar->{acctimeout};
	my $socktimeout = $procpar->{socktimeout};
	my $maxsnd      = $procpar->{queuesend};
	my $maxioerrors = $procpar->{maxioerrors};
	my $clkey       = $procpar->{clkey};
	
	my $ioerrors = 0;
	my $sioerrors = 0;
	my $run = 1;
	my $pid = $$;
	
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");

	# Initialize RPC server
	Log3 $name, 2, "CCURPC: [$name] Initializing RPC server $clkey for interface $iface";
	my $rpcsrv = HMCCURPCPROC_InitRPCServer ($name, $clkey, $callbackport, $prot);
	if (!defined ($rpcsrv)) {
		Log3 $name, 1, "CCURPC: [$name] Can't initialize RPC server $clkey for interface $iface";
		return;
	}
	if (!($rpcsrv->{__daemon})) {
		Log3 $name, 1, "CCURPC: [$name] Server socket not found for port $port";
		return;
	}
	
	# Event queue
	my @queue = ();
	
	# Store RPC server parameters
	$rpcsrv->{hmccu}{name}       = $name;
	$rpcsrv->{hmccu}{clkey}      = $clkey;
	$rpcsrv->{hmccu}{eventqueue} = \@queue;
	$rpcsrv->{hmccu}{queuesize}  = $procpar->{queuesize};
	$rpcsrv->{hmccu}{sockparent} = $sockparent;
	$rpcsrv->{hmccu}{statistics} = $procpar->{statistics};
	$rpcsrv->{hmccu}{ccuflags}   = $procpar->{ccuflags};
	$rpcsrv->{hmccu}{flags}      = $procpar->{flags};	
	$rpcsrv->{hmccu}{evttime}    = time ();
	
	# Initialize statistic counters
	foreach my $et (@eventtypes) {
		$rpcsrv->{hmccu}{rec}{$et} = 0;
		$rpcsrv->{hmccu}{snd}{$et} = 0;
	}
	$rpcsrv->{hmccu}{rec}{total} = 0;
	$rpcsrv->{hmccu}{snd}{total} = 0;

	# Signal handler
	$SIG{INT} = sub { $run = 0; Log3 $name, 2, "CCURPC: [$name] $clkey received signal INT"; };	

	HMCCURPCPROC_Write ($rpcsrv, "SL", $clkey, $pid);
	Log3 $name, 2, "CCURPC: [$name] $clkey accepting connections. PID=$pid";
	
	$rpcsrv->{__daemon}->timeout ($acctimeout) if ($acctimeout > 0.0);

	while ($run) {
		if ($evttimeout > 0) {
			my $difftime = time()-$rpcsrv->{hmccu}{evttime};
			HMCCURPCPROC_Write ($rpcsrv, "TO", $clkey, $difftime) if ($difftime >= $evttimeout);
		}
		
		# Send queue entries to parent process
		if (scalar (@queue) > 0) {
			Log3 $name, 4, "CCURPC: [$name] RPC server $clkey sending data to FHEM";
			my ($c, $m) = HMCCURPCPROC_SendQueue ($sockparent, $socktimeout, \@queue, $maxsnd);
			if ($c < 0) {
				$ioerrors++;
				$sioerrors++;
				if ($ioerrors >= $maxioerrors || $maxioerrors == 0) {
					Log3 $name, 2, "CCURPC: [$name] Sending data to FHEM failed $ioerrors times. $m";
					$ioerrors = 0;
				}
			}
		}
				
		# Next statement blocks for rpcAcceptTimeout seconds
		Log3 $name, 5, "CCURPC: [$name] RPC server $clkey accepting connections";
		my $connection = $rpcsrv->{__daemon}->accept ();
		next if (! $connection);
		last if (! $run);
		$connection->timeout ($conntimeout) if ($conntimeout > 0.0);
		
		Log3 $name, 4, "CCURPC: [$name] RPC server $clkey processing request";
		if ($prot eq 'A') {
			$rpcsrv->process_request ($connection);
		}
		else {
			HMCCURPCPROC_ProcessRequest ($rpcsrv, $connection);
		}
		
		shutdown ($connection, 2);
		close ($connection);
		undef $connection;
	}

	Log3 $name, 1, "CCURPC: [$name] RPC server $clkey stopped handling connections. PID=$pid";

	close ($rpcsrv->{__daemon}) if ($prot eq 'B');
	
	# Send statistic info
	HMCCURPCPROC_WriteStats ($rpcsrv, $clkey);

	# Send exit information	
	HMCCURPCPROC_Write ($rpcsrv, "EX", $clkey, "SHUTDOWN|$pid");

	# Send queue entries to parent process. Resend on error to ensure that EX event is sent
	my ($c, $m) = HMCCURPCPROC_SendQueue ($sockparent, $socktimeout, \@queue, 0);
	if ($c < 0) {
		Log3 $name, 4, "CCURPC: [$name] Sending data to FHEM failed. $m";
		# Wait 1 second and try again
		sleep (1);
		HMCCURPCPROC_SendQueue ($sockparent, $socktimeout, \@queue, 0);
	}
	
	# Log statistic counters
	foreach my $et (@eventtypes) {
		Log3 $name, 4, "CCURPC: [$name] $clkey event type = $et: ".$rpcsrv->{hmccu}{rec}{$et};
	}
	Log3 $name, 2, "CCURPC: [$name] Number of I/O errors = $sioerrors";
	
	return;
}

######################################################################
# Send queue data to parent process.
# Return number of queue elements sent to parent process or
# (-1, errormessage) on error.
######################################################################

sub HMCCURPCPROC_SendQueue ($$$$)
{
	my ($sockparent, $socktimeout, $queue, $maxsnd) = @_;

	my $fd = fileno ($sockparent);
	my $msg = '';
	my $win = '';
	vec ($win, $fd, 1) = 1;
	my $nf = select (undef, $win, undef, $socktimeout);
	if ($nf <= 0) {
		$msg = $nf == 0 ? "select found no reader" : $!;
		return (-1, $msg);
	}
	
	my $sndcnt = 0;
	while (my $snddata = shift @{$queue}) {
		my ($bytes, $err) = HMCCURPCPROC_SendData ($sockparent, $snddata);
		if ($bytes == 0) {
			# Put item back in queue
			unshift @{$queue}, $snddata;
			$msg = $err;
			$sndcnt = -1;
			last;
		}
		$sndcnt++;
		last if ($sndcnt == $maxsnd && $maxsnd > 0);
	}
	
	return ($sndcnt, $msg);
}

######################################################################
# Check if file descriptor is writeable and write data.
# Return number of bytes written and error message.
######################################################################

sub HMCCURPCPROC_SendData ($$)
{
	my ($sockparent, $data) = @_;
	
	my $bytes = 0;
	my $err = '';

	my $size = pack ("N", length ($data));
	my $msg = $size . $data;
	$bytes = syswrite ($sockparent, $msg);
	if (!defined ($bytes)) {
		$err = $!;
		$bytes = 0;
	}
	elsif ($bytes != length ($msg)) {
		$err = "Sent incomplete data";
	}
	
	return ($bytes, $err);
}

######################################################################
# Check if file descriptor is readable and read data.
# Return data and error message.
######################################################################

sub HMCCURPCPROC_ReceiveData ($$)
{
	my ($fh, $socktimeout) = @_;
	
	my $header;
	my $data;
	my $err = '';

	# Check if data is available
	my $fd = fileno ($fh);
	my $rin = '';
	vec ($rin, $fd, 1) = 1;
	my $nfound = select ($rin, undef, undef, $socktimeout);
	if ($nfound < 0) {
		return (undef, $!);
	}
	elsif ($nfound == 0) {
		return (undef, "read: no data");
	}
  
	# Read datagram size	
	my $sbytes = sysread ($fh, $header, 4);
	if (!defined ($sbytes)) {
		return (undef, $!);
	}
	elsif ($sbytes != 4) {
		return (undef, "read: short header");
	}

	# Read datagram
	my $size = unpack ('N', $header);	
	my $bytes = sysread ($fh, $data, $size);
	if (!defined ($bytes)) {
		return (undef, $!);
	}
	elsif ($bytes != $size) {
		return (undef, "read: incomplete data");
	}

	return ($data, $err);
}

######################################################################
# Write event into queue.
######################################################################

sub HMCCURPCPROC_Write ($$$$)
{
	my ($server, $et, $cb, $msg) = @_;
	my $name = $server->{hmccu}{name};

	if (defined ($server->{hmccu}{eventqueue})) {
		my $queue = $server->{hmccu}{eventqueue};
		my $ev = $et."|".$cb."|".$msg;

		$server->{hmccu}{evttime} = time ();
		
		if (defined ($server->{hmccu}{queuesize}) &&
			scalar (@{$queue}) >= $server->{hmccu}{queuesize}) {
			Log3 $name, 1, "CCURPC: [$name] $cb maximum queue size reached. Dropping event.";
			return;
		}

		Log3 $name, 2, "CCURPC: [$name] event = $ev" if ($server->{hmccu}{ccuflags} =~ /logEvents/);

		# Try to send events immediately. Put them in queue if send fails
		my $rc = 0;
		my $err = '';
		if ($et ne 'ND' && $server->{hmccu}{ccuflags} !~ /queueEvents/) {
			($rc, $err) = HMCCURPCPROC_SendData ($server->{hmccu}{sockparent}, $ev);
			Log3 $name, 3, "CCURPC: [$name] SendData $ev $err" if ($rc == 0);
		}
		push (@{$queue}, $ev) if ($rc == 0);
		
		# Event statistics
		$server->{hmccu}{rec}{$et}++;
		$server->{hmccu}{rec}{total}++;
		$server->{hmccu}{snd}{$et}++;
		$server->{hmccu}{snd}{total}++;
		HMCCURPCPROC_WriteStats ($server, $cb)
			if ($server->{hmccu}{snd}{total} % $server->{hmccu}{statistics} == 0);
	}
}

######################################################################
# Write statistics
######################################################################

sub HMCCURPCPROC_WriteStats ($$)
{
	my ($server, $clkey) = @_;
	my $name = $server->{hmccu}{name};
	
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");

	if (defined ($server->{hmccu}{eventqueue})) {
		my $queue = $server->{hmccu}{eventqueue};

		# Send statistic info
		my $st = $server->{hmccu}{snd}{total};
		foreach my $et (@eventtypes) {
			$st .= '|'.$server->{hmccu}{snd}{$et};
			$server->{hmccu}{snd}{$et} = 0;
		}
	
		Log3 $name, 4, "CCURPC: [$name] Event statistics = $st";
		push (@{$queue}, "ST|$clkey|$st");
	}
}

######################################################################
# Helper functions
######################################################################

######################################################################
# Dump variable content as hex/ascii combination
######################################################################

sub HMCCURPCPROC_HexDump ($$)
{
	my ($name, $data) = @_;
	
	my $offset = 0;

	foreach my $chunk (unpack "(a16)*", $data) {
		my $hex = unpack "H*", $chunk; # hexadecimal magic
		$chunk =~ tr/ -~/./c;          # replace unprintables
		$hex   =~ s/(.{1,8})/$1 /gs;   # insert spaces
		Log3 $name, 4, sprintf "0x%08x (%05u)  %-*s %s", $offset, $offset, 36, $hex, $chunk;
		$offset += 16;
	}
}

######################################################################
# Callback functions
######################################################################

######################################################################
# Callback for new devices
######################################################################

sub HMCCURPCPROC_NewDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: [$name] $cb NewDevice received $devcount device and channel specifications";	
	foreach my $dev (@$a) {
		my $msg = '';
		if ($dev->{ADDRESS} =~ /:[0-9]{1,2}$/) {
			$msg = "C|".$dev->{ADDRESS}."|".$dev->{TYPE}."|".$dev->{VERSION}."|null|null";
		}
		else {
			# Wired devices do not have a RX_MODE attribute
			my $rx = exists ($dev->{RX_MODE}) ? $dev->{RX_MODE} : 'null';
			$msg = "D|".$dev->{ADDRESS}."|".$dev->{TYPE}."|".$dev->{VERSION}."|".
				$dev->{FIRMWARE}."|".$rx;
		}
		HMCCURPCPROC_Write ($server, "ND", $cb, $msg);
	}

	return;
}

##################################################
# Callback for deleted devices
##################################################

sub HMCCURPCPROC_DeleteDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: [$name] $cb DeleteDevice received $devcount device addresses";
	foreach my $dev (@$a) {
		HMCCURPCPROC_Write ($server, "DD", $cb, $dev);
	}

	return;
}

##################################################
# Callback for modified devices
##################################################

sub HMCCURPCPROC_UpdateDeviceCB ($$$$)
{
	my ($server, $cb, $devid, $hint) = @_;
	my $name = $server->{hmccu}{name};

	Log3 $name, 2, "CCURPC: [$name] $cb updated device $devid with hint $hint";	
	HMCCURPCPROC_Write ($server, "UD", $cb, $devid."|".$hint);

	return;
}

##################################################
# Callback for replaced devices
##################################################

sub HMCCURPCPROC_ReplaceDeviceCB ($$$$)
{
	my ($server, $cb, $devid1, $devid2) = @_;
	my $name = $server->{hmccu}{name};
	
	Log3 $name, 2, "CCURPC: [$name] $cb device $devid1 replaced by $devid2";
	HMCCURPCPROC_Write ($server, "RD", $cb, $devid1."|".$devid2);

	return;
}

##################################################
# Callback for readded devices
##################################################

sub HMCCURPCPROC_ReaddDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: [$name] $cb ReaddDevice received $devcount device addresses";
	foreach my $dev (@$a) {
		HMCCURPCPROC_Write ($server, "RA", $cb, $dev);
	}

	return;
}

##################################################
# Callback for handling CCU events
##################################################

sub HMCCURPCPROC_EventCB ($$$$$)
{
	my ($server, $cb, $devid, $attr, $val) = @_;
	my $name = $server->{hmccu}{name};
	my $etime = time ();
	
	HMCCURPCPROC_Write ($server, "EV", $cb, $etime."|".$devid."|".$attr."|".$val);

	# Never remove this statement!
	return;
}

##################################################
# Callback for list devices
##################################################

sub HMCCURPCPROC_ListDevicesCB ($$)
{
	my ($server, $cb) = @_;
	my $name = $server->{hmccu}{name};
	
	if ($server->{hmccu}{ccuflags} =~ /ccuInit/) {
		$cb = "unknown" if (!defined ($cb));
		Log3 $name, 1, "CCURPC: [$name] $cb ListDevices. Sending init to HMCCU";
		HMCCURPCPROC_Write ($server, "IN", $cb, "INIT|1");
	}
	
	return RPC::XML::array->new ();
}


######################################################################
# Binary RPC encoding functions
######################################################################

######################################################################
# Encode integer (type = 1)
######################################################################

sub HMCCURPCPROC_EncInteger ($)
{
	my ($v) = @_;
	
	return pack ('Nl', $BINRPC_INTEGER, $v);
}

######################################################################
# Encode bool (type = 2)
######################################################################

sub HMCCURPCPROC_EncBool ($)
{
	my ($v) = @_;
	
	return pack ('NC', $BINRPC_BOOL, $v);
}

######################################################################
# Encode string (type = 3)
# Input is string. Empty string = void
######################################################################

sub HMCCURPCPROC_EncString ($)
{
	my ($v) = @_;
	
	return pack ('NN', $BINRPC_STRING, length ($v)).$v;
}

######################################################################
# Encode name
######################################################################

sub HMCCURPCPROC_EncName ($)
{
	my ($v) = @_;

	return pack ('N', length ($v)).$v;
}

######################################################################
# Encode double (type = 4)
######################################################################

sub HMCCURPCPROC_EncDouble ($)
{
	my ($v) = @_;
 
#	my $s = $v < 0 ? -1.0 : 1.0;
# 	my $l = $v != 0.0 ? log (abs($v))/log (2) : 0.0;
# 	my $f = $l;
#        
# 	if ($l-int ($l) > 0) {
# 		$f = ($l < 0) ? -int (abs ($l)+1.0) : int ($l);
# 	}
# 	my $e = $f+1;
# 	my $m = int ($v*2**-$e*0x40000000);

	my $m = 0;
	my $e = 0;
	
	if ($v != 0.0) {
		$e = int(log(abs($v))/log(2.0))+1;
		$m = int($v/(2**$e)*0x40000000);
	}
	        
	return pack ('NNN', $BINRPC_DOUBLE, $m, $e);
}

######################################################################
# Encode base64 (type = 17)
# Input is base64 encoded string
######################################################################

sub HMCCURPCPROC_EncBase64 ($)
{
	my ($v) = @_;
	
	return pack ('NN', $BINRPC_DOUBLE, length ($v)).$v;
}

######################################################################
# Encode array (type = 256)
# Input is array reference. Array must contain (type, value) pairs
######################################################################

sub HMCCURPCPROC_EncArray ($)
{
	my ($a) = @_;
	
	my $r = '';
	my $s = 0;

	if (defined ($a)) {
		while (my $t = shift @$a) {
			my $e = shift @$a;
			if ($e) {
				$r .= HMCCURPCPROC_EncType ($t, $e);
				$s++;
			}
		}
	}
		
	return pack ('NN', $BINRPC_ARRAY, $s).$r;
}

######################################################################
# Encode struct (type = 257)
# Input is hash reference. Hash elements:
#   hash->{$element}{T} = Type
#   hash->{$element}{V} = Value
######################################################################

sub HMCCURPCPROC_EncStruct ($)
{
	my ($h) = @_;
	
	my $r = '';
	my $s = 0;
	
	foreach my $k (keys %{$h}) {
		$r .= HMCCURPCPROC_EncName ($k);
		$r .= HMCCURPCPROC_EncType ($h->{$k}{T}, $h->{$k}{V});
		$s++;
	}

	return pack ('NN', $BINRPC_STRUCT, $s).$r;
}

######################################################################
# Encode any type
# Input is type and value
# Return encoded data or empty string on error
######################################################################

sub HMCCURPCPROC_EncType ($$)
{
	my ($t, $v) = @_;
	
	if ($t == $BINRPC_INTEGER) {
		return HMCCURPCPROC_EncInteger ($v);
	}
	elsif ($t == $BINRPC_BOOL) {
		return HMCCURPCPROC_EncBool ($v);
	}
	elsif ($t == $BINRPC_STRING) {
		return HMCCURPCPROC_EncString ($v);
	}
	elsif ($t == $BINRPC_DOUBLE) {
		return HMCCURPCPROC_EncDouble ($v);
	}
	elsif ($t == $BINRPC_BASE64) {
		return HMCCURPCPROC_EncBase64 ($v);
	}
	elsif ($t == $BINRPC_ARRAY) {
		return HMCCURPCPROC_EncArray ($v);
	}
	elsif ($t == $BINRPC_STRUCT) {
		return HMCCURPCPROC_EncStruct ($v);
	}
	else {
		return '';
	}
}

######################################################################
# Encode RPC request with method and optional parameters.
# Headers are not supported.
# Input is method name and reference to parameter array.
# Array must contain (type, value) pairs
# Return encoded data or empty string on error
######################################################################

sub HMCCURPCPROC_EncodeRequest ($$)
{
	my ($method, $args) = @_;

	# Encode method
	my $m = HMCCURPCPROC_EncName ($method);
	
	# Encode parameters
	my $r = '';
	my $s = 0;

	if (defined ($args)) {
		while (my $t = shift @$args) {
			my $e = shift @$args;
			last if (!defined ($e));
			$r .= HMCCURPCPROC_EncType ($t, $e);
			$s++;
		}
	}
	
	# Method, ParameterCount, Parameters
	$r = $m.pack ('N', $s).$r;

	# Identifier, ContentLength, Content
	# Ggf. +8
	$r = pack ('NN', $BINRPC_REQUEST, length ($r)+8).$r;
	
	return $r;
}

######################################################################
# Encode RPC response
# Input is type and value
######################################################################

sub HMCCURPCPROC_EncodeResponse ($$)
{
	my ($t, $v) = @_;

	if (defined ($t) && defined ($v)) {
		my $r = HMCCURPCPROC_EncType ($t, $v);
		# Ggf. +8
		return pack ('NN', $BINRPC_RESPONSE, length ($r)+8).$r;
	}
	else {
		return pack ('NN', $BINRPC_RESPONSE);
	}
}

######################################################################
# Binary RPC decoding functions
######################################################################

######################################################################
# Decode integer (type = 1)
# Return (value, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecInteger ($$$)
{
	my ($d, $i, $u) = @_;

	return ($i+4 <= length ($d)) ? (unpack ($u, substr ($d, $i, 4)), 4) : (undef, undef);
}

######################################################################
# Decode bool (type = 2)
# Return (value, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecBool ($$)
{
	my ($d, $i) = @_;

	return ($i+1 <= length ($d)) ? (unpack ('C', substr ($d, $i, 1)), 1) : (undef, undef);
}

######################################################################
# Decode string or void (type = 3)
# Return (string, packet size) or (undef, undef)
# Return ('', 4) for special type 'void'
######################################################################

sub HMCCURPCPROC_DecString ($$)
{
	my ($d, $i) = @_;

	my ($s, $o) = HMCCURPCPROC_DecInteger ($d, $i, 'N');
	if (defined ($s) && $i+$s+4 <= length ($d)) {
		return $s > 0 ? (substr ($d, $i+4, $s), $s+4) : ('', 4);
	}
	
	return (undef, undef);
}

######################################################################
# Decode double (type = 4)
# Return (value, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecDouble ($$)
{
	my ($d, $i) = @_;

	return (undef, undef) if ($i+8 > length ($d));
	
	my $m = unpack ('l', reverse (substr ($d, $i, 4)));
	my $e = unpack ('l', reverse (substr ($d, $i+4, 4)));	
	$m = $m/(1<<30);
	my $v = $m*(2**$e);

	return (sprintf ("%.6f",$v), 8);
}

######################################################################
# Decode base64 encoded string (type = 17)
# Return (string, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecBase64 ($$)
{
	my ($d, $i) = @_;
	
	return HMCCURPCPROC_DecString ($d, $i);
}

######################################################################
# Decode array (type = 256)
# Return (arrayref, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecArray ($$)
{
	my ($d, $i) = @_;
	my @r = ();

	my ($s, $x) = HMCCURPCPROC_DecInteger ($d, $i, 'N');
	if (defined ($s)) {
		my $j = $x;
		for (my $n=0; $n<$s; $n++) {
			my ($v, $o) = HMCCURPCPROC_DecType ($d, $i+$j);
			return (undef, undef) if (!defined ($o));
			push (@r, $v);
			$j += $o;
		}
		return (\@r, $j);
	}
	
	return (undef, undef);
}

######################################################################
# Decode struct (type = 257)
# Return (hashref, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecStruct ($$)
{
	my ($d, $i) = @_;
	my %r;
	
	my ($s, $x) = HMCCURPCPROC_DecInteger ($d, $i, 'N');
	if (defined ($s)) {
		my $j = $x;
		for (my $n=0; $n<$s; $n++) {
			my ($k, $o1) = HMCCURPCPROC_DecString ($d, $i+$j);
			return (undef, undef) if (!defined ($o1));
			my ($v, $o2) = HMCCURPCPROC_DecType ($d, $i+$j+$o1);
			return (undef, undef) if (!defined ($o2));
			$r{$k} = $v;
			$j += $o1+$o2;
		}
		return (\%r, $j);
	}
	
	return (undef, undef);
}

######################################################################
# Decode any type
# Return (element, packetsize) or (undef, undef)
######################################################################

sub HMCCURPCPROC_DecType ($$)
{
	my ($d, $i) = @_;
	
	return (undef, undef) if ($i+4 > length ($d));

	my @r = ();
	
	my $t = unpack ('N', substr ($d, $i, 4));
	$i += 4;
	
	if ($t == $BINRPC_INTEGER) {
		# Integer
		@r = HMCCURPCPROC_DecInteger ($d, $i, 'N');
	}
	elsif ($t == $BINRPC_BOOL) {
		# Bool
		@r = HMCCURPCPROC_DecBool ($d, $i);
	}
	elsif ($t == $BINRPC_STRING || $t == $BINRPC_BASE64) {
		# String / Base64
		@r = HMCCURPCPROC_DecString ($d, $i);
	}
	elsif ($t == $BINRPC_DOUBLE) {
		# Double
		@r = HMCCURPCPROC_DecDouble ($d, $i);
	}
	elsif ($t == $BINRPC_ARRAY) {
		# Array
		@r = HMCCURPCPROC_DecArray ($d, $i);
	}
	elsif ($t == $BINRPC_STRUCT) {
		# Struct
		@r = HMCCURPCPROC_DecStruct ($d, $i);
	}
	
	$r[1] += 4;

	return @r;
}

######################################################################
# Decode request.
# Return method, arguments. Arguments are returned as array.
######################################################################

sub HMCCURPCPROC_DecodeRequest ($)
{
	my ($data) = @_;

	my @r = ();
	my $i = 8;
	
	return (undef, undef) if (length ($data) < 8);
	
	# Decode method
	my ($method, $o) = HMCCURPCPROC_DecString ($data, $i);
	return (undef, undef) if (!defined ($method));

	$i += $o;
	
	my $c = unpack ('N', substr ($data, $i, 4));
	$i += 4;

	for (my $n=0; $n<$c; $n++) {
		my ($d, $s) = HMCCURPCPROC_DecType ($data, $i);
		return (undef, undef) if (!defined ($d) || !defined ($s));
		push (@r, $d);
		$i += $s;
	}
		
	return (lc ($method), \@r);
}

######################################################################
# Decode response.
# Return (ref, type) or (undef, undef)
# type: 1=ok, 0=error
######################################################################

sub HMCCURPCPROC_DecodeResponse ($)
{
	my ($data) = @_;
	
	return (undef, undef) if (length ($data) < 8);
	
	my $id = unpack ('N', substr ($data, 0, 4));
	if ($id == $BINRPC_RESPONSE) {
		# Data
		my ($result, $offset) = HMCCURPCPROC_DecType ($data, 8);
		return ($result, 1);
	}
	elsif ($id == $BINRPC_ERROR) {
		# Error
		my ($result, $offset) = HMCCURPCPROC_DecType ($data, 8);
		return ($result, 0);
	}
#	Response with header not supported
#	elsif ($id == 0x42696E41) {
#	}
	
	return (undef, undef);
}


1;

=pod
=item device
=item summary provides RPC server for connection between FHEM and Homematic CCU2
=begin html

<a name="HMCCURPCPROC"></a>
<h3>HMCCURPCPROC</h3>
<ul>
	The module provides a subprocess based RPC server for receiving events from HomeMatic CCU2.
	A HMCCURPCPROC device acts as a client device for a HMCCU I/O device. Normally RPC servers of
	type HMCCURPCPROC are started or stopped from HMCCU I/O device via command 'set rpcserver on,off'.
	HMCCURPCPROC devices will be created automatically by I/O device when RPC server is started.
	There should be no need for creating HMCCURPCPROC devices manually.
   </br></br>
   <a name="HMCCURPCPROCdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCURPCPROC {&lt;HostOrIP&gt;|iodev=&lt;DeviceName&gt;} 
      {&lt;port&gt;|&lt;interface&gt;}</code>
      <br/><br/>
      Examples:<br/>
      <code>define myccurpc HMCCURPCPROC 192.168.1.10 2001</code><br/>
      <code>define myccurpc HMCCURPCPROC iodev=myccudev BidCos-RF</code><br/>
      <br/><br/>
      The parameter <i>HostOrIP</i> is the hostname or IP address of a Homematic CCU2.
      The I/O device can also be specified with parameter iodev. If more than one CCU exist
      it's highly recommended to specify IO device with option iodev. Supported interfaces or
      ports are:
      <table>
      <tr><td><b>Port</b></td><td><b>Interface</b></td></tr>
      <tr><td>2000</td><td>BidCos-Wired</td></tr>
      <tr><td>2001</td><td>BidCos-RF</td></tr>
      <tr><td>2010</td><td>HmIP-RF</td></tr>
      <tr><td>7000</td><td>HVL</td></tr>
      <tr><td>8701</td><td>CUxD</td></tr>
      <tr><td>9292</td><td>Virtual</td></tr>
      </table>
   </ul>
   <br/>
   
   <a name="HMCCURPCPROCset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; deregister</b><br/>
         Deregister RPC server at CCU.
      </li><br/>
      <li><b>set &lt;name&gt; register</b><br/>
         Register RPC server at CCU. RPC server must be running. Helpful when CCU lost
         connection to FHEM and events timed out.
      </li><br/>
		<li><b>set &lt;name&gt; rpcrequest &lt;method&gt; [&lt;parameters&gt;]</b><br/>
			Send RPC request to CCU. The result is displayed in FHEM browser window. See EQ-3
			RPC XML documentation for mor information about valid methods and requests.
		</li><br/>
		<li><b>set &lt;name&gt; rpcserver { on | off }</b><br/>
			Start or stop RPC server. This command is only available if expert mode is activated.
		</li><br/>
	</ul>
	
	<a name="HMCCURPCPROCget"></a>
	<b>Get</b><br/><br/>
	<ul>
		<li><b>get &lt;name&gt; rpcevent</b><br/>
			Show RPC server events statistics.
		</li><br/>
		<li><b>get &lt;name&gt; rpcstate</b><br/>
			Show RPC process state.
		</li><br/>
	</ul>
	
	<a name="HMCCURPCPROCattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><b>ccuflags { flag-list }</b><br/>
			Set flags for controlling device behaviour. Meaning of flags is:<br/>
			ccuInit - RPC server initialization depends on ListDevice RPC call issued by CCU.
			This flag is not supported by interfaces CUxD and HVL.<br/>
			expert - Activate expert mode<br/>
			logEvents - Events are written into FHEM logfile if verbose is 4<br/>
			queueEvents - Always write events into queue and send them asynchronously to FHEM.
			Frequency of event transmission to FHEM depends on attribute rpcConnTimeout.<br/>
			reconnect - Try to re-register at CCU if no events received for rpcEventTimeout seconds<br/>
		</li><br/>
		<li><b>rpcAcceptTimeout &lt;seconds&gt;</b><br/>
			Specify timeout for accepting incoming connections. Default is 1 second. Increase this 
			value by 1 or 2 seconds on slow systems.
		</li><br/>
	   <li><b>rpcConnTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout of incoming CCU connections. Default is 1 second. Value must be greater than 0.
	   </li><br/>
	   <li><b>rpcEventTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout for CCU events. Default is 600 seconds. If timeout occurs an event
	   	is triggered. If set to 0 the timeout is ignored. If ccuflag reconnect is set the
	   	RPC device tries to establish a new connection to the CCU.
	   </li><br/>
	   <li><b>rpcMaxEvents &lt;count&gt;</b><br/>
	   	Specify maximum number of events read by FHEM during one I/O loop. If FHEM performance
	   	slows down decrease this value and increase attribute rpcQueueSize. Default value is 100.
	   	Value must be greater than 0.
	   </li><br/>
	   <li><b>rpcMaxIOErrors &lt;count&gt;</b><br/>
	   	Specifiy maximum number of I/O errors allowed when sending events to FHEM before a 
	   	message is written into FHEM log file. Default value is 100. Set this attribute to 0
	   	to disable error counting.
	   </li><br/>
	   <li><b>rpcQueueSend &lt;events&gt;</b><br/>
	      Maximum number of events sent to FHEM per accept loop. Default is 70. If set to 0
	      all events in queue are sent to FHEM. Transmission is stopped when an I/O error occurrs
	      or specified number of events has been sent.
	   </li><br/>
	   <li><b>rpcQueueSize &lt;count&gt;</b><br/>
	   	Specify maximum size of event queue. When this limit is reached no more CCU events
	   	are forwarded to FHEM. In this case increase this value or increase attribute
	   	<b>rpcMaxEvents</b>. Default value is 500.
	   </li><br/>
	   <li><b>rpcServerAddr &lt;ip-address&gt;</b><br/>
	   	Set local IP address of RPC servers on FHEM system. If attribute is missing the
	   	corresponding attribute of I/O device (HMCCU device) is used or IP address is
	   	detected automatically. This attribute should be set if FHEM is running on a system
	   	with multiple network interfaces.
	   </li><br/>
	   <li><b>rpcServerPort &lt;port&gt;</b><br/>
	   	Specify TCP port number used for calculation of real RPC server ports. 
	   	If attribute is missing the corresponding attribute of I/O device (HMCCU device)
	   	is used. Default value is 5400.
	   </li><br/>
	   <li><b>rpcStatistics &lt;count&gt;</b><br/>
	   	Specify amount of events after which statistic data is sent to FHEM. Default value
	   	is 500.
	   </li><br/>
		<li><b>rpcWriteTimeout &lt;seconds&gt;</b><br/>
			Wait the specified time for socket to become readable or writeable. Default value
			is 0.001 seconds.
		</li>
	</ul>
</ul>

=end html
=cut



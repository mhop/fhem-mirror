##############################################################################
#
#  88_HMCCURPCPROC.pm
#
#  $Id$
#
#  Version 5.0
#
#  Subprocess based RPC Server module for HMCCU.
#
#  (c) 2024 by zap (zap01 <at> t-online <dot> de)
#
##############################################################################
#
#  Required perl modules:
#
#    RPC::XML::Client
#    RPC::XML::Server
#
# ND deactivated in Read and Write!!
##############################################################################


package main;

use strict;
use warnings;

# use Data::Dumper;
use RPC::XML::Client;
use RPC::XML::Server;
use SetExtensions;

######################################################################
# Constants
######################################################################

# HMCCURPC version
my $HMCCURPCPROC_VERSION = '2024-12';

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

# RPC ping interval for default interface, should be smaller than HMCCURPCPROC_TIMEOUT_EVENT
my $HMCCURPCPROC_TIME_PING = 300;

# Timeout for established CCU connection in seconds
my $HMCCURPCPROC_TIMEOUT_CONNECTION = 1;

# Timeout for TriggerIO() in seconds
my $HMCCURPCPROC_TIMEOUT_WRITE = 0.001;

# Timeout for reading from Socket
my $HMCCURPCPROC_TIMEOUT_READ = 0.01;

# Timeout for accepting incoming connections in seconds (0 = default)
my $HMCCURPCPROC_TIMEOUT_ACCEPT = 1;

# Timeout for incoming CCU events in seconds (0 = ignore timeout)
my $HMCCURPCPROC_TIMEOUT_EVENT = 0;

# Send statistic information after specified amount of events
my $HMCCURPCPROC_STATISTICS = 500;

# Default RPC server base port
my $HMCCURPCPROC_SERVER_PORT = 5400;

# Delay for RPC server start after FHEM is initialized in seconds
my $HMCCURPCPROC_INIT_INTERVAL0 = 12;

# Delay for RPC server cleanup after stop in seconds
my $HMCCURPCPROC_INIT_INTERVAL2 = 30;

# Delay for RPC server functionality check after start in seconds
my $HMCCURPCPROC_INIT_INTERVAL3 = 25;

# Interval for checking status of parent (FHEM) process in seconds
my $HMCCURPCPROC_PARENT_CHECK_INTERVAL = 5;

my %HMCCURPCPROC_RPC_FLAGS = (
   'BidCos-Wired' => '_', 'BidCos-RF' => 'multicalls', 'HmIP-RF' => '_',
   'VirtualDevices' => '_', 'Homegear' => '_', 'CUxD' => '_',
   'HVL' => '_'
);

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

# BinRPC datatype mapping
my %BINRPC_TYPE_MAPPING = (
	'BOOL'    => $BINRPC_BOOL,
	'INTEGER' => $BINRPC_INTEGER,
	'ENUM'    => $BINRPC_INTEGER,
	'STRING'  => $BINRPC_STRING,
	'FLOAT'   => $BINRPC_DOUBLE,
	'DOUBLE'  => $BINRPC_DOUBLE,
	'BASE64'  => $BINRPC_BASE64,
	'ARRAY'   => $BINRPC_ARRAY,
	'STRUCT'  => $BINRPC_STRUCT
);

# Usage of some RPC requests (STRUCT => HASH)
my %RPC_METHODS = (
	'system.multicall'       => [ 'ARRAY' ],
	'putParamset'            => [ 'STRING', 'STRING', 'HASH' ],
	'getParamset'            => [ 'STRING', 'STRING' ],
	'getParamsetDescription' => [ 'STRING', 'STRING' ],
	'setValue'               => [ 'STRING', 'STRING', 'STRING' ],
	'getValue'               => [ 'STRING', 'STRING' ]
);

# RPC event types:
#
# EV = Event
# ND = New device
# DD = Delete device
# RD = Replace device
# RA = Readded device
# UD = Update device
# IN = Init RPC connection
# EX = Exit RPC process
# SL = Server loop (server is accepting connections)
# ST = Statistics (not in list of event types)
# TO = Timeout
my @RPC_EVENT_TYPES = ('EV', 'ND', 'DD', 'RD', 'RA', 'UD', 'IN', 'EX', 'SL', 'TO');


######################################################################
# Functions
######################################################################

# Standard functions
sub HMCCURPCPROC_Initialize ($);
sub HMCCURPCPROC_Define ($$);
sub HMCCURPCPROC_InitDevice ($$);
sub HMCCURPCPROC_Undef ($$);
sub HMCCURPCPROC_Rename ($$);
sub HMCCURPCPROC_DelayedShutdown ($);
sub HMCCURPCPROC_Shutdown ($);
sub HMCCURPCPROC_Attr ($@);
sub HMCCURPCPROC_Set ($@);
sub HMCCURPCPROC_Get ($@);
sub HMCCURPCPROC_Read ($);
sub HMCCURPCPROC_SetError ($$$);
sub HMCCURPCPROC_SetState ($$);
sub HMCCURPCPROC_ProcessEvent ($$);

# RPC information
sub HMCCURPCPROC_GetDeviceDesc ($@);
sub HMCCURPCPROC_GetParamsetDesc ($;$);
sub HMCCURPCPROC_BuildParamsetRequest ($$$$);
sub HMCCURPCPROC_GetPeers ($;$);

# RPC server control functions
sub HMCCURPCPROC_CheckProcessState ($$);
sub HMCCURPCPROC_CleanupIO ($);
sub HMCCURPCPROC_CleanupProcess ($);
sub HMCCURPCPROC_DeRegisterCallback ($$);
sub HMCCURPCPROC_GetRPCServerID ($$);
sub HMCCURPCPROC_Housekeeping ($);
sub HMCCURPCPROC_InitRPCServer ($$$$);
sub HMCCURPCPROC_IsRPCServerRunning ($);
sub HMCCURPCPROC_IsRPCStateBlocking ($);
sub HMCCURPCPROC_RegisterCallback ($$);
sub HMCCURPCPROC_ResetRPCState ($);
sub HMCCURPCPROC_RPCPing ($);
sub HMCCURPCPROC_RPCServerStarted ($);
sub HMCCURPCPROC_RPCServerStopped ($);
sub HMCCURPCPROC_Connect ($;$);
sub HMCCURPCPROC_Disconnect ($;$);
sub HMCCURPCPROC_IsConnected ($);
sub HMCCURPCPROC_SendRequest ($@);
sub HMCCURPCPROC_SendXMLRequest ($@);
sub HMCCURPCPROC_SendBINRequest ($@);
sub HMCCURPCPROC_SetRPCState ($$$$);
sub HMCCURPCPROC_StartRPCServer ($);
sub HMCCURPCPROC_StopRPCServer ($$);
sub HMCCURPCPROC_TerminateProcess ($);

# Helper functions
sub HMCCURPCPROC_GetAttribute ($$$$);
sub HMCCURPCPROC_GetKey ($);
sub HMCCURPCPROC_HexDump ($$);

# RPC server functions
sub HMCCURPCPROC_ProcessRequest ($$);
sub HMCCURPCPROC_HandleConnection ($$$$);
sub HMCCURPCPROC_SendQueue ($$$$);
sub HMCCURPCPROC_SendData ($$);
sub HMCCURPCPROC_ReceiveData ($$);
sub HMCCURPCPROC_ReadFromSocket ($$);
sub HMCCURPCPROC_DataAvailableOnSocket ($$);
sub HMCCURPCPROC_WriteToSocket ($$$);
sub HMCCURPCPROC_Write ($$$$);
sub HMCCURPCPROC_WriteStats ($$);
sub HMCCURPCPROC_NewDevicesCB ($$$);
sub HMCCURPCPROC_DeleteDevicesCB ($$$);
sub HMCCURPCPROC_UpdateDeviceCB ($$$$);
sub HMCCURPCPROC_ReplaceDeviceCB ($$$$);
sub HMCCURPCPROC_ReaddDevicesCB ($$$);
sub HMCCURPCPROC_EventCB ($$$$$);
sub HMCCURPCPROC_ListDevicesCB ($$);

# RPC encoding functions
sub HMCCURPCPROC_XMLEncValue ($;$);
sub HMCCURPCPROC_EncInteger ($);
sub HMCCURPCPROC_EncBool ($);
sub HMCCURPCPROC_EncString ($);
sub HMCCURPCPROC_EncName ($);
sub HMCCURPCPROC_EncDouble ($);
sub HMCCURPCPROC_EncBase64 ($);
sub HMCCURPCPROC_EncArray ($);
sub HMCCURPCPROC_EncStruct ($);
sub HMCCURPCPROC_EncType ($;$);
sub HMCCURPCPROC_EncodeRequest ($$);
sub HMCCURPCPROC_EncodeResponse ($;$);

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

	$hash->{version} = $HMCCURPCPROC_VERSION;
	
	$hash->{DefFn}             = 'HMCCURPCPROC_Define';
	$hash->{UndefFn}           = 'HMCCURPCPROC_Undef';
	$hash->{RenameFn}          = 'HMCCURPCPROC_Rename';
	$hash->{SetFn}             = 'HMCCURPCPROC_Set';
	$hash->{GetFn}             = 'HMCCURPCPROC_Get';
	$hash->{ReadFn}            = 'HMCCURPCPROC_Read';
	$hash->{AttrFn}            = 'HMCCURPCPROC_Attr';
	$hash->{ShutdownFn}        = 'HMCCURPCPROC_Shutdown';
	$hash->{DelayedShutdownFn} = 'HMCCURPCPROC_DelayedShutdown';
	
	$hash->{parseParams} = 1;

	$hash->{AttrList} = 'ccuflags:multiple-strict,expert,logEvents,ccuInit,queueEvents,noEvents,noInitialUpdate,noMulticalls,statistics'.
		' rpcMaxEvents rpcQueueSend rpcQueueSize rpcMaxIOErrors'. 
		' rpcServerAddr rpcServerPort rpcReadTimeout rpcWriteTimeout rpcAcceptTimeout'.
		' rpcRetryRequest:0,1,2 rpcConnTimeout rpcStatistics rpcEventTimeout rpcPingCCU '.
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCURPCPROC_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $ioHash;
	my $ioname = '';
	my $rpcip = '';
	my $iface;
	my $usage = 'Usage: define $name HMCCURPCPROC { CCUHost | iodev={device} } { RPCPort | RPCInterface }';
	my $errSource = "HMCCURPCPROC [$name]";
	
	$hash->{version} = $HMCCURPCPROC_VERSION;

	if (exists($h->{iodev})) {
		$ioname = $h->{iodev};
		return $usage if (scalar(@$a) < 3);
		return "$errSource HMCCU I/O device $ioname not found" if (!exists($defs{$ioname}));
		return "$errSource Device $ioname is not a HMCCU device" if ($defs{$ioname}->{TYPE} ne 'HMCCU');
		$ioHash = $defs{$ioname};
		if (scalar(@$a) < 4) {
			$hash->{host} = $ioHash->{host};
			$hash->{prot} = $ioHash->{prot};
			$iface = $$a[2];
		}
		else {
			if ($$a[2] =~ /^(https?):\/\/(.+)/) {
				$hash->{prot} = $1;
				$hash->{host} = $2;
			}
			else {
				$hash->{prot} = 'http';
				$hash->{host} = $$a[2];
			}
			$iface = $$a[3];
		}
		$rpcip = HMCCU_ResolveName ($hash->{host}, 'N/A');
	}
	else {
		return $usage if (scalar(@$a) < 4);
		if ($$a[2] =~ /^(https?):\/\/(.+)/) {
			$hash->{prot} = $1;
			$hash->{host} = $2;
		}
		else {
			$hash->{prot} = 'http';
			$hash->{host} = $$a[2];
		}
		$iface = $$a[3];	
		$rpcip = HMCCU_ResolveName ($hash->{host}, 'N/A');

		# Find IO device
		foreach my $d (keys %defs) {
			my $dh = $defs{$d};
			next if (!exists ($dh->{TYPE}) || !exists ($dh->{NAME}) || $dh->{TYPE} ne 'HMCCU');
			if ($dh->{ccuip} eq $rpcip) { $ioHash = $dh; last; }
		}
		
		return $errSource."HMCCU I/O device not found" if (!defined($ioHash));
	}

	# Store some definitions for delayed initialization
	$hash->{hmccu}{devspec} = $iface;
	$hash->{rpcip} = $rpcip;
			
	if ($init_done) {
		# Interactive define command while CCU not ready or no IO device defined
		if (!defined($ioHash)) {
			my ($ccuactive, $ccuinactive) = HMCCU_IODeviceStates ();
			return $errSource.($ccuinactive > 0 ?
				' CCU and/or IO device not ready. Please try again later' :
				' Cannot detect IO device');
		}
	}
	else {
		# CCU not ready during FHEM start
		if ($ioHash->{ccustate} ne 'active') {
			HMCCU_Log ($hash, 2, 'CCU not ready. Trying later ...');
			readingsSingleUpdate ($hash, 'state', 'Pending', 1);
			$hash->{ccudevstate} = 'pending';
			return undef;
		}
	}

	# Initialize FHEM device, set IO device
	my $rc = HMCCURPCPROC_InitDevice ($ioHash, $hash);
	return "$errSource Invalid port or interface $iface" if ($rc == 1);
	return "$errSource Can't assign I/O device $ioname" if ($rc == 2);
	return "$errSource Invalid local IP address ".$hash->{hmccu}{localaddr} if ($rc == 3);
	return "$errSource RPC device for CCU/port already exists" if ($rc == 4);
	return "$errSource Cannot connect to CCU ".$hash->{host}." interface $iface" if ($rc == 5);
	return "$errSource Can't fetch RPC methods supported by CCU ".$hash->{host} if ($rc == 6);

	return undef;
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU during delayed initialization
# after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = Invalid port or interface
# 2 = Cannot assign IO device
# 3 = Invalid local IP address
# 4 = RPC device for CCU/port already exists
# 5 = Cannot connect to CCU
######################################################################

sub HMCCURPCPROC_InitDevice ($$)
{
	my ($ioHash, $devHash) = @_;
	my $name = $devHash->{NAME};
	my $iface = $devHash->{hmccu}{devspec};
	
	# Check if interface is valid
	my ($ifname, $ifport) = HMCCU_GetRPCServerInfo ($ioHash, $iface, 'name,port'); 
	return 1 if (!defined($ifname) || !defined($ifport));

	# Check if RPC device with same interface already exists
	foreach my $d (keys %defs) {
		my $dh = $defs{$d};
		next if (!exists($dh->{TYPE}) || !exists($dh->{NAME}));
		if ($dh->{TYPE} eq 'HMCCURPCPROC' && $dh->{NAME} ne $name && IsDisabled ($dh->{NAME}) != 1) {
			return 4 if ($devHash->{host} eq $dh->{host} && exists ($dh->{rpcport}) &&
				$dh->{rpcport} == $ifport);
		}
	}
	
	# Detect local IP address and check if CCU is reachable
	my $localaddr = HMCCU_TCPConnect ($devHash->{host}, $ifport);
	return 5 if ($localaddr eq '');
	$devHash->{hmccu}{localaddr} = $localaddr;
	$devHash->{hmccu}{defaultaddr} = $devHash->{hmccu}{localaddr};

	# Get unique ID for RPC server: last 2 segments of local IP address
	# Do not append random digits because of https://forum.fhem.de/index.php/topic,83544.msg797146.html#msg797146
	my $id1 = HMCCU_GetIdFromIP ($devHash->{hmccu}{localaddr}, '');
	my $id2 = HMCCU_GetIdFromIP ($ioHash->{ccuip}, '');
	return 3 if ($id1 eq '' || $id2 eq '');
	$devHash->{rpcid} = $id1.$id2;
	
	# Set I/O device and store reference for RPC device in I/O device
	my $ioname = $ioHash->{NAME};
	return 2 if (!HMCCU_AssignIODevice ($devHash, $ioname, $ifname));

	# Store internals
	$devHash->{rpcport}      = $ifport;
	$devHash->{rpcinterface} = $ifname;
	$devHash->{ccuip}        = $ioHash->{ccuip};
	$devHash->{ccutype}      = $ioHash->{ccutype};
	$devHash->{CCUNum}       = $ioHash->{CCUNum};
	$devHash->{ccustate}     = $ioHash->{ccustate};
	
	# Fetch supported RPC methods
	my ($resp, $err) = HMCCURPCPROC_SendRequest ($devHash, 'system.listMethods');
	if (!defined($resp)) {
		return HMCCU_Log ($devHash, 1, "Can't fetch RPC methods supported by CCU", 6);
	}
	elsif (ref($resp) eq 'ARRAY') {
		$devHash->{hmccu}{rpc}{methods} = join(',',@$resp);
		if (exists($HMCCURPCPROC_RPC_FLAGS{$ifname}) && $HMCCURPCPROC_RPC_FLAGS{$ifname} =~ /multicalls/ &&
			$devHash->{hmccu}{rpc}{methods} =~ /(system\.multicall)/i)
		{
			$devHash->{hmccu}{rpc}{multicall} = $1;
			HMCCU_Log ($devHash, 5, "CCU interface $ifname supports RPC multicalls");
		}
		else {
			HMCCU_Log ($devHash, 2, "CCU interface $ifname doesn't support RPC multicalls");
		}
	}
	else {
		return HMCCU_Log ($devHash, 2, 'Unexpected response from system.listMethods', 6);
	}

	HMCCU_Log ($devHash, 1, "Initialized version $HMCCURPCPROC_VERSION for interface $ifname with I/O device $ioname");

	# Set some attributes
	if ($init_done) {
		$attr{$name}{stateFormat} = 'rpcstate/state';
		$attr{$name}{room}        = 'Homematic';
		$attr{$name}{verbose} = 2;
	}
	
	# RPC device ready
	HMCCURPCPROC_ResetRPCState ($devHash);
	HMCCURPCPROC_SetState ($devHash, 'Initialized');
	
	return 0;
}

######################################################################
# Delete device
######################################################################

sub HMCCURPCPROC_Undef ($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};
	my $ioHash = $hash->{IODev};
	my $ifname = $hash->{rpcinterface};

	# Shutdown RPC server
	HMCCURPCPROC_StopRPCServer ($hash, $HMCCURPCPROC_INIT_INTERVAL2);

	# Delete RPC device name in I/O device
	if (exists($ioHash->{hmccu}{interfaces}{$ifname}) &&
		exists($ioHash->{hmccu}{interfaces}{$ifname}{device}) &&
		$ioHash->{hmccu}{interfaces}{$ifname}{device} eq $name) {
		delete $ioHash->{hmccu}{interfaces}{$ifname}{device};
	}
	
	return undef;
}

######################################################################
# Rename device
######################################################################

sub HMCCURPCPROC_Rename ($$)
{
	my ($newName, $oldName) = @_;
	my $hash = $defs{$newName};

	my $ioHash = $hash->{IODev};
	my $ifName = $hash->{rpcinterface};

	$ioHash->{hmccu}{interfaces}{$ifName}{device} = $newName;
}

######################################################################
# Delayed shutdown FHEM
######################################################################

sub HMCCURPCPROC_DelayedShutdown ($)
{
	my ($hash) = @_;
	my $ioHash = $hash->{IODev};
	my $ifname = $hash->{rpcinterface};
	
	my $delay = HMCCU_Max (AttrVal ('global', 'maxShutdownDelay', 10)-2, 0);

	# Shutdown RPC server
	if (defined($ioHash) && exists($ioHash->{hmccu}{interfaces}{$ifname}{manager}) &&
		$ioHash->{hmccu}{interfaces}{$ifname}{manager} eq 'HMCCURPCPROC') {
		if (!exists($hash->{hmccu}{delayedShutdown})) {
			$hash->{hmccu}{delayedShutdown} = $delay;
			HMCCU_Log ($hash, 1, "Graceful shutdown within $delay seconds");
			HMCCURPCPROC_StopRPCServer ($hash, $delay);
		}
		else {
			HMCCU_Log ($hash, 1, 'Graceful shutdown already in progress');
		}
	}
		
	return 1;
}

######################################################################
# Shutdown FHEM
######################################################################

sub HMCCURPCPROC_Shutdown ($)
{
	my ($hash) = @_;
	my $ioHash = $hash->{IODev};
	my $ifname = $hash->{rpcinterface};

	# Shutdown RPC server
	if (defined($ioHash) && exists($ioHash->{hmccu}{interfaces}{$ifname}{manager}) &&
		$ioHash->{hmccu}{interfaces}{$ifname}{manager} eq 'HMCCURPCPROC') {
		if (!exists ($hash->{hmccu}{delayedShutdown})) {
			HMCCU_Log ($hash, 1, 'Immediate shutdown');
			HMCCURPCPROC_StopRPCServer ($hash, 0);
		}
		else {
			HMCCU_Log ($hash, 1, 'Graceful shutdown');
		}
	}
	
	# Remove all internal timers
	RemoveInternalTimer ($hash);

	return undef;
}

######################################################################
# Set/delete attribute
######################################################################

sub HMCCURPCPROC_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};
	my $ioHash = $hash->{IODev};
	my $restartRPC = 0;
	
	if ($cmd eq 'set') {
		if ($attrname =~ /^(rpcAcceptTimeout|rpcReadTimeout|rpcWriteTimeout)$/ && $attrval == 0) {
			$restartRPC = 1;
			return "HMCCURPCPROC: [$name] Value for attribute $attrname must be greater than 0";
		}
		elsif ($attrname eq 'rpcServerAddr') {
			$restartRPC = 1;
			$hash->{hmccu}{localaddr} = $attrval;
		}
		elsif ($attrname eq 'rpcPingCCU') {
			HMCCU_Log ($hash, 1, "Attribute rpcPingCCU ignored. Please set it in I/O device");
		}
		elsif ($attrname eq 'ccuflags' && $attrval =~ /(reconnect|logPong)/) {
			HMCCU_Log ($hash, 1, "Flag $1 ignored. Please set it in I/O device");
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'rpcServerAddr') {
			$restartRPC = 1;
			$hash->{hmccu}{localaddr} = $hash->{hmccu}{defaultaddr};
		}
	}

	HMCCU_LogDisplay ($hash, 2, 'Please restart RPC server to apply attribute changes')
		if ($restartRPC && $init_done && (!defined($ioHash) || $ioHash->{hmccu}{postInit} == 0) &&
			HMCCURPCPROC_CheckProcessState ($hash, 'running'));

	return undef;
}

######################################################################
# Set commands
######################################################################

sub HMCCURPCPROC_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $ioHash = $hash->{IODev};
	my $name = shift @$a;
	my $opt = shift @$a // return 'No set command specified';

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $options = $ccuflags =~ /expert/ ?
		'cleanup:noArg deregister:noArg register:noArg rpcrequest rpcserver:on,off' : '';
	my $busyoptions = $ccuflags =~ /expert/ ? 'rpcserver:off' : '';

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
				return HMCCURPCPROC_SetState ($hash, 'OK');
			}
			else {
				return HMCCURPCPROC_SetError ($hash, $rcmsg, 2);
			}
		}
		else {
			return HMCCURPCPROC_SetError ($hash, 'RPC server not running', 2);
		}
	}
	elsif ($opt eq 'deregister') {
		my ($rc, $err) = HMCCURPCPROC_DeRegisterCallback ($hash, 1);
		return HMCCURPCPROC_SetError ($hash, $err, 2) if (!$rc);
		return HMCCURPCPROC_SetState ($hash, "OK");
	}
	elsif ($opt eq 'rpcrequest') {
		my $request = shift @$a // return HMCCURPCPROC_SetError (
			$hash, "Usage: set $name rpcrequest {request} [{ value[:type] | parameter=value[:type] | !STRUCT } ...]", 2);
		return "RPC method $request not supported"
			if (defined($hash->{hmccu}{rpc}{methods}) && $hash->{hmccu}{rpc}{methods} !~ /$request/);
		my $structSize = scalar(keys %$h);
		my $s = 0;
		my @param = ();
		foreach my $p (@$a) {
			if ($p eq '!STRUCT' && $structSize > 0) {
				push @param, $h;
				$s = 1;
			}
			else {
				push @param, $p;
			}
		}
		push @param, $h if ($structSize > 0 && !$s);
		my ($resp, $err) = HMCCURPCPROC_SendRequest ($hash, $request, @param);
		return HMCCURPCPROC_SetError ($hash, "RPC request failed: $err", 2) if (!defined($resp));
		return HMCCU_RefToString ($resp);
	}
	elsif ($opt eq 'rpcserver') {
		my $action = shift @$a;
		return HMCCURPCPROC_SetError ($hash, "Usage: set $name rpcserver {on|off}", 2)
		   if (!defined($action) || $action !~ /^(on|off)$/);

		if ($action eq 'on') {
			return HMCCURPCPROC_SetError ($hash, 'RPC server already running', 2)
				if ($hash->{RPCState} ne 'inactive' && $hash->{RPCState} ne 'error');
			$ioHash->{hmccu}{interfaces}{$hash->{rpcinterface}}{manager} = 'HMCCURPCPROC';
			my ($rc, $info) = HMCCURPCPROC_StartRPCServer ($hash);
			if (!$rc) {
				HMCCURPCPROC_SetRPCState ($hash, 'error', undef, undef);
				return HMCCURPCPROC_SetError ($hash, $info, 1);
			}
		}
		elsif ($action eq 'off') {
			$ioHash->{hmccu}{interfaces}{$hash->{rpcinterface}}{manager} = 'HMCCURPCPROC';
			HMCCURPCPROC_StopRPCServer ($hash, $HMCCURPCPROC_INIT_INTERVAL2);
		}
		
		return undef;
	}

	return "HMCCURPCPROC: Unknown argument $opt, choose one of $options";
}

######################################################################
# Get commands
######################################################################

sub HMCCURPCPROC_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $ioHash = $hash->{IODev};
	my $name = shift @$a;
	my $opt = shift @$a // return 'No get command specified';

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $options = 'deviceDesc rpcevents:noArg rpcstate:noArg peers:noArg';

	return 'HMCCURPCPROC: CCU busy, choose one of rpcstate:noArg'
		if ($opt ne 'rpcstate' && HMCCURPCPROC_IsRPCStateBlocking ($hash));

	my $result = 'Command not implemented';
	my $rc;

	if ($opt eq 'deviceDesc') {
		my $address;
		my $object = shift @$a;
		if (defined($object)) {
			if (exists($defs{$object})) {
				my $clHash = $defs{$object};
				my $clType = $clHash->{TYPE};
				return HMCCURPCPROC_SetError ($hash, "Illegal device type $clType", 2)
					if ($clType ne 'HMCCUCHN' && $clType ne 'HMCCUDEV');
				$address = $clHash->{ccuaddr};
			}
			else {
				$address = $object;
			}
			($address, undef) = HMCCU_SplitChnAddr ($address);
		}
		HMCCU_ResetDeviceTables ($ioHash, $hash->{rpcinterface}, $address);
		my $cd = HMCCURPCPROC_GetDeviceDesc ($hash, $address);
		my $cm = HMCCURPCPROC_GetParamsetDesc ($hash, $address);
		return "Read $cd channel and device descriptions and $cm device models from CCU";
	}
	elsif ($opt eq 'peers') {
		my $cp = HMCCURPCPROC_GetPeers ($hash);
		return "Read $cp links from CCU";
	}
	elsif ($opt eq 'rpcevents') {
		my $clkey = HMCCURPCPROC_GetKey ($hash);

		$result = "Event statistics for server $clkey\n";
		$result .= "Average event delay = ".$hash->{hmccu}{rpc}{avgdelay}."\n"
			if (defined ($hash->{hmccu}{rpc}{avgdelay}));
		$result .= ('=' x 40)."\nET Sent by RPC server   Received by FHEM\n".('-' x 40)."\n";
		foreach my $et (@RPC_EVENT_TYPES) {
			my $snd = exists ($hash->{hmccu}{rpc}{snd}{$et}) ?
				sprintf ("%7d", $hash->{hmccu}{rpc}{snd}{$et}) : "    n/a"; 
			my $rec = exists ($hash->{hmccu}{rpc}{rec}{$et}) ?
				sprintf ("%7d", $hash->{hmccu}{rpc}{rec}{$et}) : "    n/a"; 
			$result .= "$et            $snd            $rec\n\n";
		}
		if ($ccuflags =~ /statistics/ && exists ($hash->{hmccu}{stats}{rcv})) {
			my $eh = HMCCU_MaxHashEntries ($hash->{hmccu}{stats}{rcv}, 3);
			$result .= ('=' x 40)."\nTop Sender\n".('=' x 40)."\n";
			for (my $i=0; $i<3; $i++) {
				last if (!exists ($eh->{$i}));
				my $dn = HMCCU_GetDeviceName ($ioHash, $eh->{$i}{k}, '?');
				$result .= "$eh->{$i}{k} / $dn : $eh->{$i}{v}\n";
			}
		}
		return $result eq '' ? 'No event statistics found' : $result;
	}
	elsif ($opt eq 'rpcstate') {
		my $clkey = HMCCURPCPROC_GetKey ($hash);
		$result = "PID   RPC-Process        State   \n".('-' x 32)."\n";
		my $sid = defined ($hash->{hmccu}{rpc}{pid}) ? sprintf ("%5d", $hash->{hmccu}{rpc}{pid}) : "N/A  ";
		my $sname = sprintf ("%-10s", $clkey);
		my $cbport = defined ($hash->{hmccu}{rpc}{cbport}) ? $hash->{hmccu}{rpc}{cbport} : "N/A";
		my $addr = defined ($hash->{hmccu}{localaddr}) ? $hash->{hmccu}{localaddr} : "N/A";
		$result .= $sid." ".$sname."      ".$hash->{hmccu}{rpc}{state}."\n\n".
			"Local address = $addr\n".
			"Callback port = $cbport\n";
		return $result;
	}
	
	return "HMCCURPCPROC: Unknown argument $opt, choose one of $options";
}

######################################################################
# Read data from processes
######################################################################

sub HMCCURPCPROC_Read ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $ioHash = $hash->{IODev};
	
	my $eventcount = 0;	# Total number of events
	my $devcount = 0;		# Number of DD, ND or RD events
	my $evcount = 0;		# Number of EV events
	my %events = ();
	my %devices = ();
	
	# Check if child socket exists
	if (!defined ($hash->{hmccu}{sockchild})) {
		HMCCU_Log ($hash, 2, 'Child socket does not exist');
		return;
	}
	
	# Get attributes
	my $rpcmaxevents = AttrVal ($name, 'rpcMaxEvents', $HMCCURPCPROC_MAX_EVENTS);
	my $ccuflags     = AttrVal ($name, 'ccuflags', 'null');
	my $hmccuflags   = AttrVal ($ioHash->{NAME}, 'ccuflags', 'null');
	my $socktimeout  = AttrVal ($name, 'rpcWriteTimeout',  $HMCCURPCPROC_TIMEOUT_WRITE);
	
	# Read events from queue
	while (1) {
		my ($item, $err) = HMCCURPCPROC_ReceiveData ($hash->{hmccu}{sockchild}, $socktimeout);
		if (!defined($item)) {
			HMCCU_Log ($hash, 4, "Read stopped after $eventcount events $err");
			last;
		}
		
		HMCCU_Log ($hash, 4, "read $item from queue") if ($ccuflags =~ /logEvents/);
		my ($et, $clkey, @par) = HMCCURPCPROC_ProcessEvent ($hash, $item);
		next if (!defined($et));
		
		if ($et eq 'EV') {
			$events{$par[0]}{$par[1]}{VALUES}{$par[2]} = $par[3];
			$evcount++;
			$hash->{ccustate} = 'active' if ($hash->{ccustate} ne 'active');
			
			# Count events per device for statistics
			$hash->{hmccu}{stats}{rcv}{$par[0]}++ if ($ccuflags =~ /statistics/);
		}
		elsif ($et eq 'EX') {
			# I/O already cleaned up. Leave Read()
			last;
		}
		elsif ($et eq 'ND') {
#			HMCCU_Log ($hash, 2, "ND: ".join(';', @par));
# 			$devices{$par[0]}{flag}      = 'N';
# 			$devices{$par[0]}{version}   = $par[3];
# 			$devices{$par[0]}{paramsets} = $par[6];
# 			if ($par[1] eq 'D') {
# 				$devices{$par[0]}{addtype}  = 'dev';
# 				$devices{$par[0]}{type}     = $par[2];
# 				$devices{$par[0]}{firmware} = $par[4];
# 				$devices{$par[0]}{rxmode}   = $par[5];
# 				$devices{$par[0]}{children} = $par[10];
# 			}
# 			else {
# 				$devices{$par[0]}{addtype}     = 'chn';
# 				$devices{$par[0]}{usetype}     = $par[2];
# 				$devices{$par[0]}{sourceroles} = $par[7];
# 				$devices{$par[0]}{targetroles} = $par[8];
# 				$devices{$par[0]}{direction}   = $par[9];
# 				$devices{$par[0]}{parent}      = $par[11];
# 				$devices{$par[0]}{aes}         = $par[12];
# 			}
# 			$devcount++;
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
			HMCCU_Log ($hash, 4, "Read stopped after $rpcmaxevents events");
			last;
		}
	}

	# Update device table and client device readings
	HMCCU_UpdateDeviceTable ($ioHash, \%devices) if ($devcount > 0);
	HMCCU_UpdateMultipleDevices ($ioHash, \%events)
		if ($evcount > 0 && $ccuflags !~ /noEvents/ && $hmccuflags !~ /noEvents/);
}

######################################################################
# Set error state and write log file message
# Parameter level is optional. Default value for level is 1.
######################################################################

sub HMCCURPCPROC_SetError ($$$)
{
	my ($hash, $text, $level) = @_;
	my $msg = defined ($text) ? $text : 'unknown error';

	HMCCURPCPROC_SetState ($hash, 'error');
	HMCCU_Log ($hash, (defined($level) ? $level : 1), $msg);
	
	return $msg;
}

######################################################################
# Set state of device
######################################################################

sub HMCCURPCPROC_SetState ($$)
{
	my ($hash, $state) = @_;
	
	if (defined($state)) {
		readingsSingleUpdate ($hash, 'state', $state, 1);
		HMCCU_Log ($hash, 4, "Set state to $state");
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
	my $ioHash = $hash->{IODev};
	
	return undef if (exists($hash->{RPCState}) && $hash->{RPCState} eq $state);

	$hash->{hmccu}{rpc}{state} = $state;
	$hash->{RPCState} = $state;
	
	readingsSingleUpdate ($hash, 'rpcstate', $state, 1);
	
	HMCCURPCPROC_SetState ($hash, 'busy') if ($state ne 'running' && $state ne 'inactive' &&
		$state ne 'error' && ReadingsVal ($name, 'state', '') ne 'busy');
		 
	HMCCU_Log ($hash, (defined($level) ? $level : 1), $msg) if (defined($msg));
	HMCCU_Log ($hash, 4, "Set rpcstate to $state");
	
	# Set state of interface in I/O device
	HMCCU_SetRPCState ($ioHash, $state, $hash->{rpcinterface});
	
	return undef;
}

######################################################################
# Reset RPC State
######################################################################

sub HMCCURPCPROC_ResetRPCState ($)
{
	my ($hash) = @_;

	$hash->{RPCPID} = '0';
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

	return (exists($hash->{RPCState}) &&
		($hash->{RPCState} eq 'running' || $hash->{RPCState} eq 'inactive')) ? 0 : 1;
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
	my $ioHash = $hash->{IODev};
	my ($defInterface, $defPort) = HMCCU_GetDefaultInterface ($ioHash);

	# Number of arguments in RPC events (without event type and clkey)
	my %rpceventargs = (
		'EV', 4, 'ND', 13, 'DD', 1, 'RD', 2, 'RA', 1, 'UD', 2, 'IN', 2, 'EX', 2, 'SL', 1,
		'TO', 1, 'ST', 11
	);

	return undef if (!defined ($event) || $event eq '');

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $ping = AttrVal ($ioHash->{NAME}, 'rpcPingCCU', $HMCCURPCPROC_TIME_PING);
	my $evttimeout = ($ping > 0 && $hash->{rpcinterface} eq $defInterface) ? $ping*2 :
	   HMCCURPCPROC_GetAttribute ($hash, 'rpcEventTimeout', 'rpcevtimeout', $HMCCURPCPROC_TIMEOUT_EVENT);                  

	# Log event
	HMCCU_Log ($hash, 2, "CCUEvent = $event") if ($ccuflags =~ /logEvents/);

	# Detect event type and clkey
	my ($et, $clkey, $evdata) = split (/\|/, $event, 3);

	if (!defined($evdata)) {
		HMCCU_Log ($hash, 2, "Syntax error in RPC event data $event");
		return undef;
	}	

	# Check for valid server
	if ($clkey ne $rpcname) {
		HMCCU_Log ($hash, 2, "Received $et event for unknown RPC server $clkey");
		return undef;
	}

	# Check event type
	if (!exists ($rpceventargs{$et})) {
		$et =~ s/([\x00-\xFF])/sprintf("0x%X ",ord($1))/eg;
		HMCCU_Log ($hash, 2, "Received unknown event from CCU: $et");
		return undef;
	}

	# Parse event
	my @t = split (/\|/, $evdata, $rpceventargs{$et});
	my $tc = scalar(@t);
	
	# Check event parameters
	if ($tc != $rpceventargs{$et}) {
		HMCCU_Log ($hash, 2, "Wrong number of $tc parameters in event $event. Expected ".$rpceventargs{$et});
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
		HMCCU_Log ($hash, 3, "Received CENTRAL event from $clkey. ".$t[2]."=".$t[3])
			if ($t[1] eq 'CENTRAL' && $t[3] eq $rpcname && HMCCU_IsFlag ($ioHash->{NAME}, 'logPong'));
		my ($add, $chn) = split (/:/, $t[1]);
		return defined($chn) ? ($et, $clkey, $add, $chn, @t[2,3]) : undef;
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
			HMCCU_Log ($hash, 0, "Received SL event. Wrong PID=".$t[0]." for RPC server $clkey");
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
		# Input:  ND|clkey|C/D|Address|Type|Version|Firmware|RxMode|Paramsets|
		#         LinkSourceRoles|LinkTargetRoles|Direction|Children|Parent|AESActive
		# Output: ND, clkey, DevAdd, C/D, Type, Version, Firmware, RxMode, Paramsets,
		#         LinkSourceRoles, LinkTargetRoles, Direction, Children, Parent, AESActive
		#
		return ($et, $clkey, @t[1,0,2..12]);
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
		return ($et, $clkey, @t[0,1]);
	}
	elsif ($et eq 'RD') {
		#
		# CCU device replaced
		# Input:  RD|clkey|Address1|Address2
		# Output: RD, clkey, Address1, Address2
		#
		return ($et, $clkey, @t[0,1]);
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
		for (my $i=0; $i<scalar(@RPC_EVENT_TYPES); $i++) {
			$hash->{hmccu}{rpc}{snd}{$RPC_EVENT_TYPES[$i]} += $t[$i];
		}
		return @res;
	}
	elsif ($et eq 'TO') {
		#
		# Event timeout
		# Input:  TO|clkey|DiffTime
		# Output: TO, clkey, Port, DiffTime
		#
		if ($evttimeout > 0) {
			HMCCU_Log ($hash, 2, "Received no events from interface $clkey for ".$t[0]." seconds");
			$hash->{ccustate} = 'timeout';
			if ($hash->{RPCState} eq 'running' && $hash->{rpcport} == $defPort) {
				# If interface is default interface inform IO device about timeout
				HMCCU_EventsTimedOut ($ioHash)
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
	my $ioHash = $hash->{IODev};
	my $value = 'null';
	
	if (defined($attr)) {
		$value = AttrVal ($name, $attr, 'null');
		return $value if ($value ne 'null');
	}
	
	if (defined($ioattr)) {
		$value = AttrVal ($ioHash->{NAME}, $ioattr, 'null');
		return $value if ($value ne 'null');
	}
	
	return $default;
}

######################################################################
# Get links (sender and receiver) from CCU.
######################################################################

sub HMCCURPCPROC_GetPeers ($;$)
{
	my ($hash, $address) = @_;
	my $ioHash = $hash->{IODev};
	my $c = 0;
		
	my ($resp, $err) = defined($address) ?
		HMCCURPCPROC_SendRequest ($hash, 'getLinks', $address) :
		HMCCURPCPROC_SendRequest ($hash, 'getLinks');

	if (!defined($resp)) {
		my $msg = defined($address) ? "Can't get peers of device $address" :
			"Can't get full list of peers";
		return HMCCU_Log ($hash, 2, "$msg: $err", 0);
	}

	if (ref($resp) eq 'ARRAY') {
		$c = HMCCU_AddPeers ($ioHash, $resp, $hash->{rpcinterface});
	}
	else {
		return HMCCU_Log ($hash, 2, "Unexpected response from getLinks: $err", 0);
	}

	return $c;
}

######################################################################
# Get RPC device descriptions from CCU recursively. Add devices to
# IO device.
# If address is not specified, fetch description of all devices.
# Return number of devices and channels read from CCU.
######################################################################

sub HMCCURPCPROC_GetDeviceDesc ($@)
{
	my ($hash, @addressList) = @_;
	my $ioHash = $hash->{IODev};
	my $c = 0;
	
	my $resp;
	my $err;
	
	if (@addressList) {
		if (scalar(@addressList) == 1) {
			# Read a single device or channel description
			($resp, $err) = HMCCURPCPROC_SendRequest ($hash, 'getDeviceDescription', $addressList[0]);
		}
		else {
			# Read multiple device or channel descriptions
			my @multiCall = map { { methodName => 'getDeviceDescription', params => [ $_ ] } } @addressList;
			($resp, $err) = HMCCURPCPROC_SendRequest ($hash, \@multiCall);
		}
	}
	else {
		# Read all device descriptions, including channels
		($resp, $err) = HMCCURPCPROC_SendRequest ($hash, 'listDevices');
	}
	
	return HMCCU_Log ($hash, 2, "Can't read device description(s)", 0) if (!defined($resp));

	if (ref($resp) eq 'HASH') {
		if (HMCCU_AddDeviceDesc ($ioHash, $resp, 'ADDRESS', $hash->{rpcinterface})) {
			$c = 1;
			if (defined($resp->{CHILDREN}) && ref($resp->{CHILDREN}) eq 'ARRAY') {
				foreach my $child (@{$resp->{CHILDREN}}) {
					$c += HMCCURPCPROC_GetDeviceDesc ($hash, $child);
				}
			}
		}
	}
	elsif (ref($resp) eq 'ARRAY') {
		foreach my $dev (@$resp) {
			$c++ if (HMCCU_AddDeviceDesc ($ioHash, $dev, 'ADDRESS', $hash->{rpcinterface}));
		}
	}
	else {
		return HMCCU_Log ($hash, 2, 'Illegal device description format', 0);
	}

	return $c;
}

######################################################################
# Get RPC device paramset descriptions from CCU
# Function is called recursively
# Parameters:
#   $address - Device or channel address. If not specified, all
#     addresses known by IO device are used. 
# Return number of devices read from CCU.
######################################################################

sub HMCCURPCPROC_GetParamsetDesc ($;$)
{
	my ($hash, $address) = @_;
	my $ioHash = $hash->{IODev};

	if (defined($address)) {

		# Build multicall request for requesting all parameter set definitions of address
		my @multiCall = ();
		my @cbParam = ();
		my $cnt = HMCCURPCPROC_BuildParamsetRequest ($hash, $address, \@multiCall, \@cbParam);
		return 0 if ($cnt == 0);

		# Multicall request
		my ($c, $err) = HMCCURPCPROC_SendMulticallRequest ($hash, \@multiCall, \&HMCCU_AddDeviceModel, \@cbParam);
		$c //= 0;
		if ($c == 0) {
			HMCCU_Log ($hash, 2, "Error(s) while fetching parameter set descriptions $address. $err");
		}
		return $c;
	}
	else {
		my $c = 0;
		foreach my $a (HMCCU_GetDeviceAddresses ($ioHash, $hash->{rpcinterface}, '_addtype=dev')) {
			$c += HMCCURPCPROC_GetParamsetDesc ($hash, $a);
		}
		return $c;
	}
}

######################################################################
# Build RPC multicall request for device or channel
# Return number of single requests
######################################################################

sub HMCCURPCPROC_BuildParamsetRequest ($$$$)
{
	my ($hash, $address, $multiCall, $cbParam) = @_;
	my $ioHash = $hash->{IODev};

	my $c = 0;

	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $address, $hash->{rpcinterface});
	return HMCCU_Log ($hash, 2, "Can't get device description for address $address", 0)
		if (!defined($devDesc) || !defined($devDesc->{PARAMSETS}) || $devDesc->{PARAMSETS} eq '' || !exists($devDesc->{_fw_ver}));

	my $chnNo = ($devDesc->{_addtype} eq 'chn') ? $devDesc->{INDEX} : 'd';

	# Check if model already exists
	if (!HMCCU_ExistsDeviceModel ($ioHash, $devDesc->{_model}, $devDesc->{_fw_ver}, $chnNo)) {
		# Build multicall request for requesting all parameter set definitions of address
		foreach my $ps (split (',', $devDesc->{PARAMSETS})) {
			push @$multiCall, { methodName => 'getParamsetDescription', params => [ $address, $ps ] };
			push @$cbParam, [ $devDesc->{_model}, $devDesc->{_fw_ver}, $ps, $chnNo ];
			$c++;
		}
	}

	# Read paramset definitions of childs (= channels)
	if (defined($devDesc->{CHILDREN}) && $devDesc->{CHILDREN} ne '') {
		foreach my $child (split (',', $devDesc->{CHILDREN})) {
			$c += HMCCURPCPROC_BuildParamsetRequest ($hash, $child, $multiCall, $cbParam);
		}
	}

	return $c;
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
	my $ioHash = $hash->{IODev};
	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	my $port = $hash->{rpcport};
	my $serveraddr = $hash->{host};
	my $localaddr = $hash->{hmccu}{localaddr};
	my $clkey = HMCCURPCPROC_GetKey ($hash);
	
	return (0, "RPC server $clkey not in state working")
		if ($hash->{hmccu}{rpc}{state} ne 'working' && $force == 0);
	return (0, "CCU port $port not reachable")
		if ($force == 2 && !HMCCU_TCPConnect ($hash->{host}, $port));

	my $cburl = HMCCU_GetRPCCallbackURL ($ioHash, $localaddr, $hash->{hmccu}{rpc}{cbport}, $clkey, $port);
	my ($clurl, $auth) = HMCCU_BuildURL ($ioHash, $port);
	my ($rpctype) = HMCCU_GetRPCServerInfo ($ioHash, $port, 'type');
	return (0, "Can't get RPC parameters for ID $clkey")
		if (!defined($cburl) || !defined($clurl) || !defined($rpctype));
	
	$hash->{hmccu}{rpc}{port}  = $port;
	$hash->{hmccu}{rpc}{clurl} = $clurl;
	$hash->{hmccu}{rpc}{auth}  = $auth;
	$hash->{hmccu}{rpc}{cburl} = $cburl;

	HMCCU_Log ($hash, 2, "Registering callback $cburl of type $rpctype with ID $clkey at $clurl");
	my ($resp, $err) = HMCCURPCPROC_SendRequest ($hash, "init", "$cburl:STRING", "$clkey:STRING");

	if (defined($resp)) {
		return (1, $ccuflags !~ /ccuInit/ ? 'running' : 'registered');
	}
	else {
		return (0, "Failed to register callback for ID $clkey: $err");
	}
}

######################################################################
# Deregister RPC callbacks at CCU
# force:
#   >0 - Ignore state of RPC server. Deregister in any case.
#   >1 - Do not update RPC server state.
######################################################################

sub HMCCURPCPROC_DeRegisterCallback ($$)
{
	my ($hash, $force) = @_;
	my $name = $hash->{NAME};
	my $ioHash = $hash->{IODev};
	
	my $port = $hash->{rpcport};
	my $clkey = HMCCURPCPROC_GetKey ($hash);
	my $localaddr = $hash->{hmccu}{localaddr};
	my $rpchash = \%{$hash->{hmccu}{rpc}};

	return (0, "RPC server $clkey not in state registered or running")
		if ($rpchash->{state} ne 'registered' && $rpchash->{state} ne 'running' && $force == 0);

	my $cburl = $rpchash->{cburl} // HMCCU_GetRPCCallbackURL ($ioHash, $localaddr, $rpchash->{cbport}, $clkey, $port);
	my $clurl = $rpchash->{clurl} // '';
	my $auth  = $rpchash->{auth}  // '';
	($clurl, $auth) = HMCCU_BuildURL ($ioHash, $port) if ($clurl eq '');
	return (0, "Can't get RPC parameters for ID $clkey") if ($cburl eq '' || $clurl eq '');

	HMCCU_Log ($hash, 1, "Deregistering RPC server $cburl with ID $clkey at $clurl");
	
	# Deregister up to 2 times
	my $resp;
	my $err;
	for (my $i=0; $i<2; $i++) {
		($resp, $err) = HMCCURPCPROC_SendRequest ($hash, "init", "$cburl:STRING", '');
		if (defined ($resp) && $force < 2) {
			HMCCURPCPROC_SetRPCState ($hash, $force == 0 ? 'deregistered' : $rpchash->{state},
				"Callback for RPC server $clkey deregistered", 1);

			$rpchash->{cburl}  = '';
			$rpchash->{clurl}  = '';
			$rpchash->{auth}   = '';
			$rpchash->{cbport} = 0;
		
			return (1, 'working');
		}
	}
	
	return (0, "Failed to deregister RPC server $clkey: $err");
}

######################################################################
# Initialize RPC server for specified CCU port
# Return server object or undef on error
######################################################################

sub HMCCURPCPROC_InitRPCServer ($$$$)
{
	my ($name, $clkey, $cbPort, $prot) = @_;
	my $server;

	# Create binary RPC server
	if ($prot eq 'B') {
		$server->{__daemon} = IO::Socket::INET->new (LocalPort => $cbPort,
			Type => SOCK_STREAM, Reuse => 1, Listen => SOMAXCONN);
		if (!($server->{__daemon})) {
			HMCCU_Log ($name, 1, "Can't create RPC callback server $clkey. Port $cbPort in use?");
			return undef;
		}
		return $server;
	}
	
	# Create XML RPC server
	$server = RPC::XML::Server->new (port => $cbPort);
	if (!ref($server)) {
		HMCCU_Log ($name, 1, "Can't create RPC callback server $clkey. Port $cbPort in use?");
		return undef;
	}
	HMCCU_Log ($name, 2, "Callback server $clkey created. Listening on port $cbPort");

	# Callback for events
	HMCCU_Log ($name, 4, "Adding callback for events for server $clkey");
	$server->add_method ({
		name => "event",
		signature => ["string string string string string","string string string string int",
			"string string string string double","string string string string boolean",
			"string string string string i4"],
	   code => \&HMCCURPCPROC_EventCB
	});

	# Callback for new devices
	HMCCU_Log ($name, 4, "Adding callback for new devices for server $clkey");
	$server->add_method ({
		name => "newDevices",
	   signature => ["string string array"],
      code => \&HMCCURPCPROC_NewDevicesCB
	});

	# Callback for deleted devices
	HMCCU_Log ($name, 4, "Adding callback for deleted devices for server $clkey");
	$server->add_method ({
		name => "deleteDevices",
	   signature => ["string string array"],
      code => \&HMCCURPCPROC_DeleteDevicesCB
	});

	# Callback for modified devices
	HMCCU_Log ($name, 4, "Adding callback for modified devices for server $clkey");
	$server->add_method ({
		name => "updateDevice",
	   signature => ["string string string int", "string string string i4"],
	   code => \&HMCCURPCPROC_UpdateDeviceCB
	});

	# Callback for replaced devices
	HMCCU_Log ($name, 4, "Adding callback for replaced devices for server $clkey");
	$server->add_method ({
		name => "replaceDevice",
	   signature => ["string string string string"],
	   code => \&HMCCURPCPROC_ReplaceDeviceCB
	});

	# Callback for readded devices
	HMCCU_Log ($name, 4, "Adding callback for readded devices for server $clkey");
	$server->add_method ({
		name => "readdedDevice",
	   signature => ["string string array"],
	   code => \&HMCCURPCPROC_ReaddDeviceCB
	});
	
	# Dummy implementation, always return an empty array
	HMCCU_Log ($name, 4, "Adding callback for list devices for server $clkey");
	$server->add_method ({
		name => "listDevices",
	   signature => ["array string"],
	   code => \&HMCCURPCPROC_ListDevicesCB
	});

	return $server;
}

######################################################################
# Start RPC server process
# Return (State, Msg)
# State: 0=Error, 1=Started, 2=Already running
######################################################################

sub HMCCURPCPROC_StartRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $ioHash = $hash->{IODev};
	my ($defInterface, $defPort) = HMCCU_GetDefaultInterface ($ioHash);

	# Local IP address and callback ID should be set during device definition
	return (0, 'Local address and/or callback ID not defined')
		if (!exists($hash->{hmccu}{localaddr}) || !exists($hash->{rpcid}));
		
	# Check if RPC server is already running
	return (2, 'RPC server already running') if (HMCCURPCPROC_CheckProcessState ($hash, 'running'));
	
	# Get parameters and attributes
	my $ping          = AttrVal ($ioHash->{NAME}, 'rpcPingCCU', $HMCCURPCPROC_TIME_PING);
	my $localaddr     = HMCCURPCPROC_GetAttribute ($hash, undef, 'rpcserveraddr', $hash->{hmccu}{localaddr});
	my $rpcserverport = HMCCURPCPROC_GetAttribute ($hash, 'rpcServerPort', 'rpcserverport', $HMCCURPCPROC_SERVER_PORT);
	my $evttimeout    = ($ping > 0 && $hash->{rpcinterface} eq $defInterface) ?
	                    $ping*2 :
	                    HMCCURPCPROC_GetAttribute ($hash, 'rpcEventTimeout', 'rpcevtimeout', $HMCCURPCPROC_TIMEOUT_EVENT);
	my $ccunum        = $hash->{CCUNum};
	my $rpcport       = $hash->{rpcport};
	my ($serveraddr, $interface) = HMCCU_GetRPCServerInfo ($ioHash, $rpcport, 'host,name');
	my $clkey         = 'CB'.$rpcport.$hash->{rpcid};
	my $callbackport  = $rpcserverport+$rpcport+($ccunum*10);
	$hash->{hmccu}{localaddr} = $localaddr;

	my ($clurl, $auth) = HMCCU_BuildURL ($ioHash, $hash->{rpcport});
	my ($flags, $type) = HMCCU_GetRPCServerInfo ($ioHash, $rpcport, 'flags,type');

	# Store parameters for child process
	my %procpar = (
		socktimeout => AttrVal ($name, 'rpcWriteTimeout',  $HMCCURPCPROC_TIMEOUT_WRITE),
		conntimeout => AttrVal ($name, 'rpcConnTimeout',   $HMCCURPCPROC_TIMEOUT_CONNECTION),
		acctimeout  => AttrVal ($name, 'rpcAcceptTimeout', $HMCCURPCPROC_TIMEOUT_ACCEPT),
		queuesize   => AttrVal ($name, 'rpcQueueSize',     $HMCCURPCPROC_MAX_QUEUESIZE),
		queuesend   => AttrVal ($name, 'rpcQueueSend',     $HMCCURPCPROC_MAX_QUEUESEND),
		statistics  => AttrVal ($name, 'rpcStatistics',    $HMCCURPCPROC_STATISTICS),
		maxioerrors => AttrVal ($name, 'rpcMaxIOErrors',   $HMCCURPCPROC_MAX_IOERRORS),
		ccuflags    => AttrVal ($name, 'ccuflags',         'null'),
		name        => $name,
		evttimeout  => $evttimeout,
		serveraddr  => $serveraddr,
		interface   => $interface,
		clkey       => $clkey,
		flags       => $flags,
		type        => $type,
		parentPID   => $$
	);
	
	# Reset state of server processes
	$hash->{hmccu}{rpc}{state} = 'inactive';

	# Create socket pair for communication between RPC server process and FHEM process
	my ($sockchild, $sockparent);
	return (0, "Can't create I/O socket pair")
		if (!socketpair ($sockchild, $sockparent, AF_UNIX, SOCK_STREAM, PF_UNSPEC));
	$sockchild->autoflush (1);
	$sockparent->autoflush (1);
	$hash->{hmccu}{sockparent}  = $sockparent;
	$hash->{hmccu}{sockchild}   = $sockchild;

	# Enable FHEM I/O, calculate RPC server port
	my $pid = $$;
	$hash->{FD} = fileno $sockchild;
	$selectlist{"RPC.$name.$pid"} = $hash; 

	$hash->{hmccu}{rpc}{clkey}  = $clkey;
	$hash->{hmccu}{rpc}{cbport} = $callbackport;
	$hash->{callback} = "$localaddr:$callbackport";

	# Start RPC server process
	my $rpcpid = fhemFork ();
	if (!defined($rpcpid)) {
		close ($sockparent);
		close ($sockchild);
		return (0, "Can't create RPC server process for interface $interface");
	}

	if (!$rpcpid) {
		# Child process, only needs parent socket
		HMCCURPCPROC_HandleConnection ($rpcport, $callbackport, $sockparent, \%procpar);
		
		# Connection loop ended. Close sockets and exit child process
		close ($sockparent);
		close ($sockchild);
		exit(0);
	}

	# Parent process
	HMCCU_Log ($hash, 2, "RPC server process started for interface $interface with PID=$rpcpid");

	# Store process parameters
	$hash->{hmccu}{rpc}{pid}    = $rpcpid;
	$hash->{hmccu}{rpc}{state}  = 'initialized';
		
	# Reset statistic counter
	foreach my $et (@RPC_EVENT_TYPES) {
		$hash->{hmccu}{rpc}{rec}{$et} = 0;
		$hash->{hmccu}{rpc}{snd}{$et} = 0;
	}
	
	$hash->{hmccu}{rpc}{sumdelay} = 0;
	$hash->{RPCPID} = $rpcpid;

	# Trigger Timer function for checking successful RPC start
	# Timer will be removed before first execution if event 'IN' is reveived
	InternalTimer (gettimeofday()+$HMCCURPCPROC_INIT_INTERVAL3, "HMCCURPCPROC_IsRPCServerRunning",
		$hash, 0);
	
	HMCCURPCPROC_SetRPCState ($hash, 'starting', 'RPC server starting', 1);	
	DoTrigger ($name, 'RPC server starting');
	
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
	my $ioHash = $hash->{IODev};
	my $clkey = HMCCURPCPROC_GetKey ($hash);
	my $ifname = $hash->{rpcinterface};
	my $ping = AttrVal ($ioHash->{NAME}, 'rpcPingCCU', $HMCCURPCPROC_TIME_PING);
	my ($defInterface, $defPort) = HMCCU_GetDefaultInterface ($ioHash);
	
	# Check if RPC servers are running. Set overall status
	if (HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
		$hash->{hmccu}{rpcstarttime} = time ();
		HMCCURPCPROC_SetState ($hash, 'OK');

		# Update client devices if interface is managed by HMCCURPCPROC device.
		# Normally interfaces are managed by HMCCU device.
		if ($ioHash->{hmccu}{interfaces}{$ifname}{manager} eq 'HMCCURPCPROC') {
			HMCCU_UpdateClients ($ioHash, '.*', 'Attr', $ifname, 1);
		}

		RemoveInternalTimer ($hash, "HMCCURPCPROC_IsRPCServerRunning");
		
		# Activate heartbeat if interface is default interface and rpcPingCCU > 0
		if ($ping > 0 && $ifname eq $defInterface) {
			HMCCU_Log ($hash, 1, "Scheduled CCU ping every $ping seconds");
			InternalTimer (gettimeofday()+$ping, "HMCCURPCPROC_RPCPing", $hash, 0);
		}
		
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
	my $clkey = HMCCURPCPROC_GetKey ($hash);

	HMCCURPCPROC_CleanupProcess ($hash);
	HMCCURPCPROC_CleanupIO ($hash);
	
	HMCCURPCPROC_ResetRPCState ($hash);
	HMCCURPCPROC_SetState ($hash, 'OK');
	
	RemoveInternalTimer ($hash);
	DoTrigger ($name, "RPC server $clkey stopped");

	# Inform FHEM that instance can be shut down
	HMCCU_Log ($hash, 2, 'RPC server stopped. Cancel delayed shutdown.');
	CancelDelayedShutdown ($name) if (exists($hash->{hmccu}{delayedShutdown}));
}

######################################################################
# Stop I/O Handling
######################################################################

sub HMCCURPCPROC_CleanupIO ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $pid = $$;
	if (exists($selectlist{"RPC.$name.$pid"})) {
		HMCCU_Log ($hash, 2, 'Stop I/O handling');
		delete $selectlist{"RPC.$name.$pid"};
		delete $hash->{FD} if (defined ($hash->{FD}));
	}
	if (defined($hash->{hmccu}{sockchild})) {
		HMCCU_Log ($hash, 3, 'Close child socket');
		$hash->{hmccu}{sockchild}->close ();
		delete $hash->{hmccu}{sockchild};
	}
	if (defined($hash->{hmccu}{sockparent})) {
		HMCCU_Log ($hash, 3, 'Close parent socket');
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
	my $clkey = HMCCURPCPROC_GetKey ($hash);
	
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
	my $clkey = HMCCURPCPROC_GetKey ($hash);
	
	my $pid = $hash->{hmccu}{rpc}{pid};
	if (defined($pid) && kill (0, $pid)) {
		HMCCU_Log ($hash, 1, "Process $clkey with PID=$pid still running. Killing it.");
		kill ('KILL', $pid);
		sleep (1);
		return HMCCU_Log ($hash, 1, "Can't kill process $clkey with PID=$pid", 0)
			if (kill (0, $pid));
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
	
	my $pstate = $hash->{hmccu}{rpc}{state};
	if ($state eq 'running' || $state eq '.*') {
		my $pid = $hash->{hmccu}{rpc}{pid};
		return (defined($pid) && $pid != 0 && kill (0, $pid) && $pstate =~ /$state/) ? $pid : 0
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
	my ($hash) = @_;
	
	HMCCU_Log ($hash, 2, 'Checking if RPC server process is running');
	if (!HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
		HMCCU_Log ($hash, 1, 'RPC server process not running. Cleaning up');
		HMCCURPCPROC_Housekeeping ($hash);
		return 0;
	}

	return HMCCU_Log ($hash, 2, 'RPC server process running', 1);
}

######################################################################
# Cleanup RPC server environment.
######################################################################

sub HMCCURPCPROC_Housekeeping ($)
{
	my ($hash) = @_;

	HMCCU_Log ($hash, 1, 'Housekeeping called. Cleaning up RPC environment');

	# Deregister callback URLs in CCU
	HMCCURPCPROC_DeRegisterCallback ($hash, 0);

	# Terminate process by sending signal INT
	sleep (2) if (HMCCURPCPROC_TerminateProcess ($hash));
	
	# Next call will cleanup IO, processes and reset RPC state
	HMCCURPCPROC_RPCServerStopped ($hash);
}

######################################################################
# Stop RPC server processes.
# If function is called by Shutdown. If parameter wait can be 0 or
# undef.
######################################################################

sub HMCCURPCPROC_StopRPCServer ($$)
{
	my ($hash, $wait) = @_;
	$wait //= $HMCCURPCPROC_INIT_INTERVAL2;
	my $clkey = HMCCURPCPROC_GetKey ($hash);
	
	if (HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
		HMCCU_Log ($hash, 1, "Stopping RPC server $clkey");
		HMCCURPCPROC_SetState ($hash, "busy");

		# Deregister callback URLs in CCU
		my ($rc, $err) = HMCCURPCPROC_DeRegisterCallback ($hash, 0);
		HMCCU_Log ($hash, 1, $err) if (!$rc);

		# Stop RPC server process 
 		HMCCURPCPROC_TerminateProcess ($hash);

		# Trigger timer function for checking successful RPC stop
		# Timer will be removed wenn receiving EX event from RPC server process
		if ($wait > 0) {
			HMCCU_Log ($hash, 2, "Scheduling cleanup in $wait seconds");
			InternalTimer (gettimeofday()+$wait, "HMCCURPCPROC_Housekeeping", $hash, 0);
		}
		else {
			HMCCU_Log ($hash, 2, 'Cleaning up immediately');
			HMCCURPCPROC_Housekeeping ($hash);
		}
		
		# Give process the chance to terminate
		sleep (1);
		return 1;
	}
	else {
		HMCCU_Log ($hash, 2, 'Found no running processes. Cleaning up ...');
		HMCCURPCPROC_Housekeeping ($hash);
		return 0;
	}
}

######################################################################
# Establish RPC connection
# Return value depends on RPC interface:
#   XML: Return RPC::XML::Client
#   BIN: Return binary TCP socket
# Return 0 = error, 1 = success.
######################################################################

sub HMCCURPCPROC_Connect ($;$)
{
	my ($hash, $ioHash) = @_;
	$ioHash //= $hash->{IODev};

	# Connection already established
	return $hash->{hmccu}{rpc}{connection} if (defined($hash->{hmccu}{rpc}{connection}));

	if (HMCCU_IsRPCType ($ioHash, $hash->{rpcport}, 'A')) {
		# Build the request URL
		my ($clurl, $auth) = HMCCU_BuildURL ($ioHash, $hash->{rpcport});
		HMCCU_Log ($hash, 5, "Connecting to " . $clurl);
		return HMCCU_Log ($hash, 1, "Can't get RPC client URL for port $hash->{rpcport}", 0) if (!defined($clurl));

		my $header = HTTP::Headers->new ('Connection' => 'Keep-Alive');
		$header->header('Authorization' => "Basic $auth") if ($auth) ne '';
		$hash->{hmccu}{rpc}{connection} = RPC::XML::Client->new ($clurl,
			useragent => [
				ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 }
			]
		);
		$hash->{hmccu}{rpc}{connection}->useragent->default_headers($header);
		$hash->{hmccu}{rpc}{clurl} = $clurl;
		$hash->{hmccu}{rpc}{auth} = $auth;
	}
	elsif (HMCCU_IsRPCType ($ioHash, $hash->{rpcport}, 'B')) {
		my ($serveraddr) = HMCCU_GetRPCServerInfo ($ioHash, $hash->{rpcport}, 'host');
		return HMCCU_Log ($ioHash, 1, "Can't get server address for port $hash->{rpcport}", 0) if (!defined($serveraddr));

		$hash->{hmccu}{rpc}{connection} = IO::Socket::INET->new (
			PeerHost => $serveraddr, PeerPort => $hash->{rpcport}, Proto => 'tcp', Timeout => 3
		);
		if ($hash->{hmccu}{rpc}{connection}) {
			$hash->{hmccu}{rpc}{connection}->autoflush (1);
			$hash->{hmccu}{rpc}{connection}->timeout (1);
		}
	}

	return HMCCU_Log ($hash, 1, "Can't connect to RPC interface", 0) if (!defined($hash->{hmccu}{rpc}{connection}));

	return 1;
}

######################################################################
# Close RPC connection
######################################################################

sub HMCCURPCPROC_Disconnect ($;$)
{
	my ($hash, $ioHash) = @_;
	$ioHash //= $hash->{IODev};

	return if (!defined($hash->{hmccu}{rpc}{connection}));

	if (HMCCU_IsRPCType ($ioHash, $hash->{rpcport}, 'B')) {
		# Close socket
		$hash->{hmccu}{rpc}{connection}->close();
	}

	delete $hash->{hmccu}{rpc}{connection};
	$hash->{hmccu}{rpc}{clurl} = '';
	$hash->{hmccu}{rpc}{auth} = '';
}

######################################################################
# Check if connection to CCU is established
######################################################################

sub HMCCURPCPROC_IsConnected ($)
{
	my ($hash) = @_;

	return defined($hash->{hmccu}{rpc}{connection}) ? 1 : 0;
}

######################################################################
# Send multicall RPC request to CCU
# Function $cbFunc is executed for each successful element of result
# $cbParam is a reference to an array of parameter array references
# array. Syntax of callback function is:
#   Func ($ioHash, $respRef, @$cbPar[n])
# Return (undef, errMsg) on error
# Return (reqCount, undef) on success
######################################################################

sub HMCCURPCPROC_SendMulticallRequest ($$$$)
{
	my ($hash, $multiCall, $cbFunc, $cbPar) = @_;

	my ($resp, $err) = HMCCURPCPROC_SendRequest ($hash, 'system.multicall', $multiCall);
	if (defined($resp)) {
		return HMCCURPCPROC_ProcessMulticallResponse ($hash, $multiCall, $resp, $cbFunc, $cbPar);
	}
	else {
		return (undef, "Error while executing RPC multicall request: $err");
	}
}

######################################################################
# Process RPC multicall respone recursively. If HASH reference is
# found, call $cbFunc and pass ioHash, reference and @$cbPar[n]
# Return (undef, errMsg) on error
# Return (reqCount, undef) on success
######################################################################

sub HMCCURPCPROC_ProcessMulticallResponse ($$$$$)
{
	my ($hash, $multiCall, $resp, $cbFunc, $cbPar) = @_;

	if (ref($resp) eq 'ARRAY') {
		my $c = 0;
		my $i = 0;

		# Single request response loop
		foreach my $r (@$resp) {
			if (ref($r) eq 'HASH') {
				if (exists($r->{faultString})) {
					# Single request failed
					my $req = @$multiCall[$i];
					my $m = $req->{methodName};
					my $p = join(',',@{$req->{params}});
					HMCCU_Log ($hash, 2, "Error in RPC multicall request $m $p: $r->{faultString}");
				}
				else {
					# Single request was successful. Execute callback function
					&$cbFunc ($hash->{IODev}, $r, @{$cbPar->[$i]});
					$c++;   # Count successful single request
				}
			}
			elsif (ref($r) eq 'ARRAY') {
				# Sub array of structs (normally one)
				# Request response element loop
				foreach my $e (@$r) {
					if (ref($e) eq 'HASH') {
						# Single request was successful. Execute callback function
						&$cbFunc ($hash->{IODev}, $e, @{$cbPar->[$i]});
						$c++;   # Count successful single request
					}
				}
			}
			else {
				HMCCU_Log ($hash, 2, 'Invalid single request response type in multicall response');
			}
			$i++;   # Count single requests
		}

		return $c == 0 ? (undef, 'All RPC multicall single requests failed') : ($c, undef);
	}
	elsif (ref($resp) eq 'HASH' && exists($resp->{faultString})) {
		# Multicall request failed
		return (undef, $resp->{faultString});
	}

	return (undef, 'Invalid multicall request response type');
}

######################################################################
# Send RPC request to CCU.
# Supports XML and BINRPC requests.
# Parameters:
#   hash - FHEM hash reference or parameter hash reference
# Parameter hash used by sub processes:
#   NAME    - HMCCURPCPROC device name
#   rpcport - CCU RPC port
#   methods - list of RPC methods
# Return value:
#   (response, undef) - Request successful
#   (undef, error) - Request failed with error
######################################################################

sub HMCCURPCPROC_SendRequest ($@)
{
	my ($hash, $request, @param) = @_;
	
	my $ph = exists($hash->{TYPE}) ? 0 : 1;

	my $ioHash = $hash->{IODev};
	if (!$ph && !defined($ioHash)) {
		HMCCU_Log ($hash, 2, 'I/O device not found');
		return (undef, 'I/O device not found');
	}

	my $port = $hash->{rpcport};
	my $multicalls = 0;
	if (!$ph) {
		$multicalls = 1 if (
			!HMCCU_IsFlag ($hash, 'noMulticalls') && defined($hash->{hmccu}{rpc}{multicall}) &&
			HMCCU_IsRPCType ($ioHash, $port, 'A')
		);
	}

	my $retry = AttrVal ($hash->{NAME}, 'rpcRetryRequest', 1);
	$retry = 2 if ($retry > 2);

	# Multicall request
	if ($request eq 'system.multicall' && !$multicalls) {
		# If multicalls are not supported or disabled, execute multiple requests
		my @respList = ();
		my $reqList = shift @param;   # Reference to request array
		foreach my $r (@$reqList) {
			my ($resp, $err) = HMCCURPCPROC_SendRequest ($hash, $r->{methodName}, @{$r->{params}});
			return ($resp, $err) if (!defined($resp));
			push @respList, $resp;
		}
		return (\@respList, undef);
	}

	# Check request syntax
	return (undef, "Request method $request not supported by CCU interface")
		if (defined($hash->{hmccu}{rpc}{methods}) && $hash->{hmccu}{rpc}{methods} !~ /$request/);
	if (exists($RPC_METHODS{$request})) {
		my @rpcParam = @param;
		my @syntax = @{$RPC_METHODS{$request}};
		while (my $t = shift @syntax) {
			my $p = shift @rpcParam // return (undef, "Missing parameter in RPC request $request");
			return (undef, "Wrong parameter type in RPC request $request. Expected type is $t")
				if ($t ne 'STRING' && ref($p) ne $t);
		}
	}

	# Reuse existing connection
	my $alreadyConnected = HMCCURPCPROC_IsConnected ($hash);
	if (!$alreadyConnected) {
		if (!HMCCURPCPROC_Connect ($hash, $ioHash)) {
			return (undef, "Can't connect to CCU");
		}
	}

	my $resp;
	my $err;

	for (my $reqNo=0; $reqNo<=$retry; $reqNo++) {
		if (HMCCU_IsRPCType ($ioHash, $port, 'A')) {
			# XML RPC request
			($resp, $err) = HMCCURPCPROC_SendXMLRequest ($hash, $ioHash, $request, @param);
			last if (defined($resp));
		}
		elsif (HMCCU_IsRPCType ($ioHash, $port, 'B')) {
			# Binary RPC request
			($resp, $err) = HMCCURPCPROC_SendBINRequest ($hash, $ioHash, $request, @param);
			last if (defined($resp));
		}
		else {
			HMCCU_Log ($hash, 2, 'Unknown RPC server type', undef);
			return (undef, 'Unknown RPC server type');
		}
		HMCCU_Log ($hash, 2, "Retrying request $request");
	}

	if (!$alreadyConnected) {
		HMCCURPCPROC_Disconnect ($hash, $ioHash);
	}

	return ($resp, $err);
}

######################################################################
# Send XML RPC request to CCU
# Return value:
#   (response, undef) - Request successful
#   (undef, error) - Request failed with error
######################################################################

sub HMCCURPCPROC_SendXMLRequest ($@)
{
	my ($hash, $ioHash, $request, @param) = @_;
	my $name = $hash->{NAME};
	my $port = $hash->{rpcport};
	
	my $re = ':('.join('|', keys(%BINRPC_TYPE_MAPPING)).')';

	# Build the request URL
	# my $clurl = HMCCU_BuildURL ($ioHash, $port);
	# if (!defined($clurl)) {
	# 	HMCCU_Log ($hash, 2, "Can't get RPC client URL for port $port");
	# 	return (undef, "Can't get RPC client URL for port $port");
	# }	
#	HMCCU_Log ($hash, 1, stacktraceAsString(undef));
#	HMCCU_Log ($hash, 1, "Send ASCII XML RPC request $request to " . $hash->{hmccu}{rpc}{clurl});

#	my $rpcclient = RPC::XML::Client->new ($clurl, useragent => [
#		ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 }
#	]);

	my @rpcParam = map { HMCCURPCPROC_XMLEncValue ($_) } @param;

	# Submit RPC request
#	HMCCU_Log($hash, 2, Dumper($hash->{hmccu}{rpc}{connection}));
	my $resp = $hash->{hmccu}{rpc}{connection}->simple_request ($request, @rpcParam);
	if (!defined($resp)) {
		HMCCU_Log ($hash, 2, "RPC request $request failed: ".$RPC::XML::ERROR);
		return (undef, "RPC request $request failed: ".$RPC::XML::ERROR);
	}
	if (ref($resp) eq 'HASH' && exists($resp->{faultString})) {
		HMCCU_Log ($hash, 2, "RPC request $request failed: ".$resp->{faultString});
		return (undef, "RPC request $request failed: ".$resp->{faultString});
	}

	return ($resp, undef);
}

######################################################################
# Send binary RPC request to CCU
# Return value:
#   (response, undef) - Request successful
#   (undef, error) - Request failed with error
######################################################################

sub HMCCURPCPROC_SendBINRequest ($@)
{
	my ($hash, $ioHash, $request, @param) = @_;
	my $name = $hash->{NAME};
#	my $port = $hash->{rpcport};
	
#	my ($serveraddr) = HMCCU_GetRPCServerInfo ($ioHash, $port, 'host');
#	if (!defined($serveraddr)) {
#		HMCCU_Log ($ioHash, 2, "Can't get server address for port $port");
#		return (undef, "Can't get server address for port $port");
#	}

#	HMCCU_Log ($hash, 1, "Send BIN XML RPC request $request");

	my $timeoutRead  = AttrVal ($name, 'rpcReadTimeout',  $HMCCURPCPROC_TIMEOUT_READ);
	my $timeoutWrite = AttrVal ($name, 'rpcWriteTimeout',  $HMCCURPCPROC_TIMEOUT_WRITE);	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $verbose = GetVerbose ($name);

	my $encreq = HMCCURPCPROC_EncodeRequest ($request, \@param);
	return (undef, 'Error while encoding binary request') if ($encreq eq '');
	
	if ($ccuflags =~ /logEvents/) {
		HMCCU_Log ($hash, 4, 'Binary RPC request');
		HMCCURPCPROC_HexDump ($name, $encreq);
	}

	# Create a socket connection
#	my $socket = IO::Socket::INET->new (PeerHost => $serveraddr, PeerPort => $port, Proto => 'tcp', Timeout => 3);
#	if (!$socket) {
#		HMCCU_Log ($hash, 2, "Can't create socket for $serveraddr:$port");
#		return (undef, "Can't create socket for $serveraddr:$port");
#	}

#	$socket->autoflush (1);
#	$socket->timeout (1);
	
	my ($bytesWritten, $errmsg) = HMCCURPCPROC_WriteToSocket ($hash->{hmccu}{rpc}{connection}, $encreq, $timeoutWrite);
	if ($bytesWritten > 0) {
		my ($bytesRead, $encresp) = HMCCURPCPROC_ReadFromSocket ($hash->{hmccu}{rpc}{connection}, $timeoutRead);
#		$socket->close ();
	
		if ($bytesRead > 0) {
			if ($ccuflags =~ /logEvents/) {
				HMCCU_Log ($hash, 4, 'Binary RPC response');
				HMCCURPCPROC_HexDump ($name, $encresp);
			}
			my ($response, $err) = HMCCURPCPROC_DecodeResponse ($encresp);
			return (undef, 'Error while decoding binary response') if (!defined($err) || $err == 0);
			return $response;
		}
		else {
			# Reconnect
			HMCCURPCPROC_Disconnect ($hash, $ioHash);
			HMCCURPCPROC_Connect ($hash, $ioHash);
			return (undef, "Error while reading response for command $request: $encresp");
		}
	}
	else {
#		$socket->close ();
		return (undef, "No data sent for request $request: $errmsg");
	}
}

######################################################################
# Timer function for RPC Ping
######################################################################

sub HMCCURPCPROC_RPCPing ($)
{
	my ($hash) = @_;
	my $ioHash = $hash->{IODev};
	my $ping = AttrVal ($ioHash->{NAME}, 'rpcPingCCU', $HMCCURPCPROC_TIME_PING);
	return HMCCU_Log ($hash, 1, 'CCU ping disabled') if ($ping == 0);
	
	my ($defInterface, $defPort) = HMCCU_GetDefaultInterface ($ioHash);
	if ($hash->{rpcinterface} eq $defInterface) {
		if ($init_done && HMCCURPCPROC_CheckProcessState ($hash, 'running')) {
			my $clkey = HMCCURPCPROC_GetKey ($hash);
			my ($resp, $err) = HMCCURPCPROC_SendRequest ($hash, 'ping', "$clkey:STRING");
			HMCCU_Log ($hash, 3, "Failed to send RPC ping: $err") if (!defined($resp));
		}
		InternalTimer (gettimeofday()+$ping, "HMCCURPCPROC_RPCPing", $hash, 0);
	}
}

######################################################################
# Process binary RPC request
######################################################################

sub HMCCURPCPROC_ProcessRequest ($$)
{
	my ($server, $connection) = @_;
	my $name = $server->{hmccu}{name};
	my $clkey = $server->{hmccu}{clkey};
	my @methodlist = ('listDevices', 'listMethods', 'system.listMethods', 'system.multicall');
	my $verbose = GetVerbose ($name);
	
	# Read request
	my $request = '';
	while  (my $packet = <$connection>) {
		$request .= $packet;
	}
	return if ($request eq '');
	
	if ($server->{hmccu}{ccuflags} =~ /logEvents/ && $verbose >= 4) {
		HMCCU_Log ($name, 4, "$clkey raw request:");
		HMCCURPCPROC_HexDump ($name, $request);
	}
	
	# Decode request
	my ($method, $params) = HMCCURPCPROC_DecodeRequest ($request);
	return if (!defined($method));
	$method = lc($method);
	HMCCU_Log ($name, 4, "Request method = $method");
	
	if ($method eq 'listmethods' || $method eq 'system.listmethods') {
		$connection->send (HMCCURPCPROC_EncodeResponse (\@methodlist));
	}
	elsif ($method eq 'listdevices') {
		HMCCURPCPROC_ListDevicesCB ($server, $clkey);
		$connection->send (HMCCURPCPROC_EncodeResponse (undef));
	}
	elsif ($method eq 'system.multicall') {
		return if (ref($params) ne 'ARRAY');
		my $a = $$params[0];
		foreach my $s (@$a) {
			next if (!exists($s->{methodName}) || !exists($s->{params}) ||
				$s->{methodName} ne 'event' || scalar(@{$s->{params}}) < 4);
 			HMCCURPCPROC_EventCB ($server, $clkey,
 				${$s->{params}}[1], ${$s->{params}}[2], ${$s->{params}}[3]);
 			HMCCU_Log ($name, 4, 'Event '.${$s->{params}}[1].' '.${$s->{params}}[2].' '
 				.${$s->{params}}[3]);
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
	my $parentPID   = $procpar->{parentPID};
	
	my $ioerrors = 0;
	my $sioerrors = 0;
	my $run = 1;
	my $pid = $$;
	
	# Initialize RPC server
	HMCCU_Log ($name, 2, "Initializing RPC server $clkey for interface $iface");
	my $rpcsrv = HMCCURPCPROC_InitRPCServer ($name, $clkey, $callbackport, $prot);
	return HMCCU_Log ($name, 1, "Can't initialize RPC server $clkey for interface $iface")
		if (!defined($rpcsrv));
	return HMCCU_Log ($name, 1, "Server socket not found for port $port")
		if (!($rpcsrv->{__daemon}));
	
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
	foreach my $et (@RPC_EVENT_TYPES, 'total') {
		$rpcsrv->{hmccu}{rec}{$et} = 0;
		$rpcsrv->{hmccu}{snd}{$et} = 0;
	}

	# Recover device hash
	my $rpcDeviceHash = $defs{$name};

	# Signal handler
	$SIG{INT} = sub { $run = 0; HMCCU_Log ($name, 2, "$clkey received signal INT"); };	

	my $checkTime = time();	# At this point in time we checked the state of the parent process

	HMCCURPCPROC_Write ($rpcsrv, 'SL', $clkey, $pid);
	HMCCU_Log ($name, 2, "$clkey accepting connections. PID=$pid");
	
	$rpcsrv->{__daemon}->timeout ($acctimeout) if ($acctimeout > 0.0);

	while ($run > 0) {
		my $currentTime = time();

		# Check for event timeout
		if ($evttimeout > 0) {
			my $difftime = $currentTime-$rpcsrv->{hmccu}{evttime};
			HMCCURPCPROC_Write ($rpcsrv, 'TO', $clkey, $difftime) if ($difftime >= $evttimeout);
		}

		# Check if parent process is still running
		if ($currentTime-$checkTime > $HMCCURPCPROC_PARENT_CHECK_INTERVAL) {
			$run = kill(0, $parentPID) ? 1 : -1;
			$checkTime = $currentTime;
		}

		# Send queue entries to parent process
		if (scalar (@queue) > 0) {
			HMCCU_Log ($name, 4, "RPC server $clkey sending data to FHEM");
			my ($c, $m) = HMCCURPCPROC_SendQueue ($sockparent, $socktimeout, \@queue, $maxsnd);
			if ($c < 0) {
				$ioerrors++;
				$sioerrors++;
				if ($ioerrors >= $maxioerrors || $maxioerrors == 0) {
					HMCCU_Log ($name, 2, "Sending data to FHEM failed $ioerrors times. $m");
					$ioerrors = 0;
				}
			}
		}
				
		# Next statement blocks for rpcAcceptTimeout seconds
		HMCCU_Log ($name, 4, "RPC server $clkey accepting connections");
		my $connection = $rpcsrv->{__daemon}->accept ();
		next if (! $connection);
		last if ($run < 1);
		$connection->timeout ($conntimeout) if ($conntimeout > 0.0);
		
		HMCCU_Log ($name, 4, "RPC server $clkey processing request");
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

	HMCCU_Log ($name, 1, "RPC server $clkey stopped handling connections. PID=$pid run=$run");

	close ($rpcsrv->{__daemon}) if ($prot eq 'B');

	if ($run < 0) {
		# Parent process not running: try to deregister callback URL and terminate RPC server process
		HMCCU_Log ($name, 1, "Parent process (FHEM,PID=$parentPID) not running. Shutting down RPC server process $clkey.");
		HMCCURPCPROC_DeRegisterCallback ($rpcDeviceHash, 1);
		HMCCU_Log ($name, 1, "FHEM will be restarted automatically if restart is enabled in system.d configuration.");
		return;
	}

	# Send statistic info
	HMCCURPCPROC_WriteStats ($rpcsrv, $clkey);

	# Send exit information	
	HMCCURPCPROC_Write ($rpcsrv, 'EX', $clkey, "SHUTDOWN|$pid");

	# Send queue entries to parent process. Resend on error to ensure that EX event is sent
	my ($c, $m) = HMCCURPCPROC_SendQueue ($sockparent, $socktimeout, \@queue, 0);
	if ($c < 0) {
		HMCCU_Log ($name, 4, "Sending data to FHEM failed. $m");
		# Wait 1 second and try again
		sleep (1);
		HMCCURPCPROC_SendQueue ($sockparent, $socktimeout, \@queue, 0);
	}
	
	# Log statistic counters
	foreach my $et (@RPC_EVENT_TYPES) {
		HMCCU_Log ($name, 4, "$clkey event type = $et: ".$rpcsrv->{hmccu}{rec}{$et});
	}
	HMCCU_Log ($name, 2, "Number of I/O errors = $sioerrors");
	
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
		$msg = $nf == 0 ? 'select found no reader' : $!;
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

	my $size = pack ("N", length($data));
	my $msg = $size . $data;
	$bytes = syswrite ($sockparent, $msg);
	if (!defined($bytes)) {
		$err = $!;
		$bytes = 0;
	}
	elsif ($bytes != length($msg)) {
		$err = 'send: incomplete data';
	}
	
	return ($bytes, $err);
}

######################################################################
# Check if file descriptor is readable and read data.
# Return (data, '') on success
# Return (undef, errmsg) on error
######################################################################

sub HMCCURPCPROC_ReceiveData ($$)
{
	my ($fh, $timeout) = @_;
	
	my $header;
	my $data;
	my $err = '';

	my ($st, $msg) = HMCCURPCPROC_DataAvailableOnSocket ($fh, $timeout);
	return (undef, $msg) if ($st <= 0);
  
	# Read datagram size	
	my $sbytes = sysread ($fh, $header, 4);
	if (!defined($sbytes)) {
		return (undef, $!);
	}
	elsif ($sbytes != 4) {
		return (undef, 'receive: short header');
	}

	# Read datagram
	my $size = unpack ('N', $header);	
	my $bytes = sysread ($fh, $data, $size);
	if (!defined ($bytes)) {
		return (undef, $!);
	}
	elsif ($bytes != $size) {
		return (undef, 'receive: incomplete data');
	}

	return ($data, $err);
}

######################################################################
# Read data from socket
# Return (-1, ErrorStr) on error.
# Return (0, 'read: no data') if no data available.
# Return (BytesRead, Data) on success.
######################################################################

sub HMCCURPCPROC_ReadFromSocket ($$)
{
	my ($socket, $timeout) = @_;
	
	my $data = '';
	my $totalBytes = 0;
	
	my ($st, $msg) = HMCCURPCPROC_DataAvailableOnSocket ($socket, $timeout);
	while ($st > 0) {
		my $buffer;	
		my $bytes = sysread ($socket, $buffer, 10000);
		return (-1, $!) if (!defined($bytes));
		last if ($bytes == 0);
		$data .= $buffer;
		$totalBytes += $bytes;
		($st, $msg) = HMCCURPCPROC_DataAvailableOnSocket ($socket, $timeout);
	}

	return $st < 0 ? ($st, $msg) : ($totalBytes, $data);
}

######################################################################
# Check if data is available for reading from socket
######################################################################

sub HMCCURPCPROC_DataAvailableOnSocket ($$)
{
	my ($socket, $timeout) = @_;
	
	my $fd = fileno ($socket);
	my $rin = '';
	vec ($rin, $fd, 1) = 1;
	
	my $nfound = select ($rin, undef, undef, $timeout);
	if ($nfound < 0) {
		return (-1, $!);
	}
	elsif ($nfound == 0) {
		return (0, 'read: no data');
	}
	
	return (1, '');
}

######################################################################
# Write data to socket
# Return (-1, ErrorStr) on error.
# Return (0, 'write: no reader') if no reading process on remote host.
# Return (BytesWritten, 'OK') on success.
######################################################################

sub HMCCURPCPROC_WriteToSocket ($$$)
{
	my ($socket, $data, $timeout) = @_;
	
	my $fd = fileno ($socket);
	my $win = '';
	vec ($win, $fd, 1) = 1;
	my $nfound = select (undef, $win, undef, $timeout);
	if ($nfound < 0) {
		return (-1, $!);
	}
	elsif ($nfound == 0) {
		return (0, 'write: no reader');
	}
	
	my $size = syswrite ($socket, $data);
	
	return defined($size) ? ($size, 'OK') : (-1, $!);
}

######################################################################
# Write event into queue.
######################################################################

sub HMCCURPCPROC_Write ($$$$)
{
	my ($server, $et, $cb, $msg) = @_;
	my $name = $server->{hmccu}{name};

	if (defined($server->{hmccu}{eventqueue})) {
		my $queue = $server->{hmccu}{eventqueue};
		my $ev = "$et|$cb|$msg";
		$server->{hmccu}{evttime} = time ();
		
		if (defined($server->{hmccu}{queuesize}) &&
			scalar(@{$queue}) >= $server->{hmccu}{queuesize}) {
			return HMCCU_Log ($name, 1, "$cb maximum queue size reached. Dropping event.");
		}

		HMCCU_Log ($name, 2, "Event = $ev") if ($server->{hmccu}{ccuflags} =~ /logEvents/);

		# Try to send events immediately. Put them in queue if send fails
		my $rc = 0;
		my $err = '';
		if ($server->{hmccu}{ccuflags} !~ /queueEvents/) {
			($rc, $err) = HMCCURPCPROC_SendData ($server->{hmccu}{sockparent}, $ev);
			HMCCU_Log ($name, 3, "SendData $ev $err") if ($rc == 0);
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
	
	if (defined ($server->{hmccu}{eventqueue})) {
		my $queue = $server->{hmccu}{eventqueue};

		# Send statistic info
		my $st = $server->{hmccu}{snd}{total};
		foreach my $et (@RPC_EVENT_TYPES) {
			$st .= '|'.$server->{hmccu}{snd}{$et};
			$server->{hmccu}{snd}{$et} = 0;
		}
	
		HMCCU_Log ($name, 4, "Event statistics = $st");
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
	
	if (!defined($data)) {
		HMCCU_Log ($name, 4, 'HexDump called without data');
		return;
	}

	my $offset = 0;

	foreach my $chunk (unpack "(a16)*", $data) {
		my $hex = unpack "H*", $chunk; # hexadecimal
		$chunk =~ tr/ -~/./c;          # replace unprintables
		$hex   =~ s/(.{1,8})/$1 /gs;   # insert spaces
		HMCCU_Log ($name, 4, sprintf "0x%08x (%05u)  %-*s %s", $offset, $offset, 36, $hex, $chunk);
		$offset += 16;
	}
}

######################################################################
# Build RPC server key
######################################################################

sub HMCCURPCPROC_GetKey ($)
{
	my ($hash) = @_;
	
	return 'CB'.$hash->{rpcport}.$hash->{rpcid};
}

######################################################################
# Callback functions
######################################################################

######################################################################
# Callback for new devices
# Message format:
#   C|ADDRESS|TYPE|VERSION|null|null|PARAMSETS|
#      LINK_SOURCE_ROLES|LINK_TARGET_ROLES|DIRECTION|
#      null|PARENT|AES_ACTIVE
#   D|ADDRESS|TYPE|VERSION|FIRMWARE|RX_MODE|PARAMSETS|
#      null|null|null|
#      CHILDREN|null|null
######################################################################

sub HMCCURPCPROC_NewDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	HMCCU_Log ($name, 2, "$cb NewDevice received $devcount device and channel specifications");

	# Format:
	# C/D|Address|Type|Version|Firmware|RxMode|Paramsets|
	# LinkSourceRoles|LinkTargetRoles|Direction|Children|Parent|AESActive

	foreach my $dev (@$a) {
		my $msg = '';
		my $ps = ref($dev->{PARAMSETS}) eq 'ARRAY' ?
			join(',', @{$dev->{PARAMSETS}}) : $dev->{PARAMSETS};
		if (defined($dev->{PARENT}) && $dev->{PARENT} ne '') {
			my $lsr = ref($dev->{LINK_SOURCE_ROLES}) eq 'ARRAY' ?
				join(',', @{$dev->{LINK_SOURCE_ROLES}}) : $dev->{LINK_SOURCE_ROLES};
			my $ltr = ref($dev->{LINK_TARGET_ROLES}) eq 'ARRAY' ?
				join(',', @{$dev->{LINK_TARGET_ROLES}}) : $dev->{LINK_TARGET_ROLES};
			$msg = 'C|'.$dev->{ADDRESS}.'|'.$dev->{TYPE}.'|'.$dev->{VERSION}.
				'|null|null|'.$ps.'|'.$lsr.'|'.$ltr.'|'.$dev->{DIRECTION}.
				'|null|'.$dev->{PARENT}."|".$dev->{AES_ACTIVE};
		}
		else {
			# Wired devices do not have a RX_MODE attribute
			my $rx = exists ($dev->{RX_MODE}) ? $dev->{RX_MODE} : 'null';
			$msg = 'D|'.$dev->{ADDRESS}.'|'.$dev->{TYPE}.'|'.$dev->{VERSION}."|".
				$dev->{FIRMWARE}.'|'.$rx.'|'.$ps.'|null|null|null|'.
				join(',',@{$dev->{CHILDREN}}).'|null|null';
		}
		HMCCURPCPROC_Write ($server, 'ND', $cb, $msg);
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
	my $devCount = scalar (@$a);
	
	HMCCU_Log ($name, 2, "$cb DeleteDevice received $devCount device addresses");
	foreach my $dev (@$a) {
		HMCCURPCPROC_Write ($server, 'DD', $cb, $dev);
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

	HMCCU_Log ($name, 2, "$cb updated device $devid with hint $hint");	
	HMCCURPCPROC_Write ($server, 'UD', $cb, $devid.'|'.$hint);

	return;
}

##################################################
# Callback for replaced devices
##################################################

sub HMCCURPCPROC_ReplaceDeviceCB ($$$$)
{
	my ($server, $cb, $devid1, $devid2) = @_;
	my $name = $server->{hmccu}{name};
	
	HMCCU_Log ($name, 2, "$cb device $devid1 replaced by $devid2");
	HMCCURPCPROC_Write ($server, 'RD', $cb, $devid1.'|'.$devid2);

	return;
}

##################################################
# Callback for readded devices
##################################################

sub HMCCURPCPROC_ReaddDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar(@$a);
	
	HMCCU_Log ($name, 2, "$cb ReaddDevice received $devcount device addresses");
	foreach my $dev (@$a) { HMCCURPCPROC_Write ($server, 'RA', $cb, $dev); }

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
	
	HMCCURPCPROC_Write ($server, 'EV', $cb, $etime.'|'.$devid.'|'.$attr.'|'.$val);

	# Never remove this statement!
	return;
}

##################################################
# Callback for list devices
##################################################

sub HMCCURPCPROC_ListDevicesCB ($$)
{
	my ($server, $cb) = @_;
	$cb //= 'unknown';
	my $name = $server->{hmccu}{name};
	
	if ($server->{hmccu}{ccuflags} =~ /ccuInit/) {
		HMCCU_Log ($name, 1, "$cb ListDevices. Sending init to HMCCU");
		HMCCURPCPROC_Write ($server, 'IN', $cb, 'INIT|1');
	}
	
	return RPC::XML::array->new ();
}

######################################################################
# RPC encoding functions
######################################################################

######################################################################
# Convert value to RPC data type
# Supported types are bool, boolean, int, integer, float, double,
# base64, string, array or hash reference.
# Type of parameter $value can be appended to value, separated by
# a colon, i.e. 100:INTEGER
# If type is undefined, type is detected. If type cannot be detected
# value is returned as it is.
######################################################################

sub HMCCURPCPROC_XMLEncValue ($;$)
{
	my ($value, $type) = @_;

	# Regular expression containing all supported scalar data types
	my $re = ':('.join('|', keys(%BINRPC_TYPE_MAPPING)).')$';
	if ($value =~ /${re}/i) {
		$type = $1;
		$value =~ s/${re}//i;
	}

	# Try to detect type if type not specified
	if (!defined($type)) {
		if (ref($value) eq 'HASH')                                    { $type = 'struct'; }
		elsif (ref($value) eq 'ARRAY')                                { $type = 'array'; }
		elsif (lc($value) =~ /^(true|false)$/)                        { $type = 'boolean'; }
		elsif ($value =~ /^[-+]?\d+$/)                                { $type = 'integer'; }
		elsif ($value =~ /^[-+]?[0-9]*\.[0-9]+$/)                     { $type = 'float'; }
		elsif ($value eq '' || $value =~ /^([a-zA-Z_ ]+|'.+'|".+")$/) { $type = 'string'; }
	}
	
	return $value if (!defined($type));

	my $lcType = lc($type);
	$type = 'struct' if ($type eq 'hash');
	if ($type eq 'struct') {
		my %struct = ();
		foreach my $k (keys %$value) {
			$struct{$k} = HMCCURPCPROC_XMLEncValue ($value->{$k});
		}
		return RPC::XML::struct->new (\%struct);
	}
	elsif ($type eq 'array') {
		return RPC::XML::array->new (map { HMCCURPCPROC_XMLEncValue ($_); } @$value);
	}
	elsif ($lcType =~ /^bool/ && uc($value) =~ /^(TRUE|FALSE|0|1)$/) {
		return RPC::XML::boolean->new ($value);
	}
	elsif ($lcType =~ /^int/ && $value =~ /^[-+]?\d+$/) {
		return RPC::XML::int->new ($value);
	}
	elsif ($lcType =~ /^(float|double)$/ && $value =~ /^[-+]?[0-9]*\.[0-9]+$/) {
		return RPC::XML::double->new ($value);
	}
	elsif ($lcType =~ /^base/) {
		return RPC::XML::base64->new ($value);
	}
	elsif ($lcType =~ /^str/) {
		return RPC::XML::string->new ($value);
	}
	else {
		return $value;
	}
}

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

	$v = 1 if ($v eq 'true');
	$v = 0 if ($v eq 'false');

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
# Encoded data will only contain the length and the name, no type.
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
# Input is array reference
######################################################################

sub HMCCURPCPROC_EncArray ($)
{
	my ($a) = @_;
	
	my $r = '';
	my $s = 0;   # Number of elements in array

	if (defined($a)) {
		return '' if (ref($a) ne 'ARRAY');
		while (my $v = shift @$a) {
			$r .= HMCCURPCPROC_EncType ($v);
			$s++;
		}
	}
		
	return pack ('NN', $BINRPC_ARRAY, $s).$r;
}

######################################################################
# Encode struct (type = 257)
# Input is hash reference. 
######################################################################

sub HMCCURPCPROC_EncStruct ($)
{
	my ($h) = @_;
	
	my $r = '';
	my $s = 0;   # Number of elements in structure

	if (defined($h)) {	
		return '' if (ref($h) ne 'HASH');
		foreach my $k (keys %{$h}) {
			my $n = HMCCURPCPROC_EncName ($k);
			if ($n ne '') {
				$r .= $n.HMCCURPCPROC_EncType ($h->{$k});
				$s++;
			}
		}
	}

	return pack ('NN', $BINRPC_STRUCT, $s).$r;
}

######################################################################
# Encode any type
# Input is value and optionally type.
# Value can be in format Value:Type
# Types are: STRING, INTEGER, BOOL, FLOAT, DOUBLE, BASE64
# Return encoded data or empty string on error
######################################################################

sub HMCCURPCPROC_EncType ($;$)
{
	my ($v, $t) = @_;

	return '' if (!defined($v));

	my $re = ':('.join('|', keys(%BINRPC_TYPE_MAPPING)).')';
	my $pt = '';
				
	if (ref($v) eq 'ARRAY')   { $pt = 'ARRAY'; }
	elsif (ref($v) eq 'HASH') { $pt = 'STRUCT'; }
	elsif ($v =~ /${re}/)     { $pt = $1; $v =~ s/${re}//; }

	$t = $BINRPC_TYPE_MAPPING{uc($pt)} if ($pt ne '' && exists($BINRPC_TYPE_MAPPING{uc($pt)}));

	$t //= HMCCURPCPROC_DetType ($v);
	
	if ($t == $BINRPC_INTEGER)   { return HMCCURPCPROC_EncInteger ($v); }
	elsif ($t == $BINRPC_BOOL)   { return HMCCURPCPROC_EncBool ($v); }
	elsif ($t == $BINRPC_STRING) { return HMCCURPCPROC_EncString ($v); }
	elsif ($t == $BINRPC_DOUBLE) { return HMCCURPCPROC_EncDouble ($v); }
	elsif ($t == $BINRPC_BASE64) { return HMCCURPCPROC_EncBase64 ($v); }
	elsif ($t == $BINRPC_ARRAY)  { return HMCCURPCPROC_EncArray ($v); }
	elsif ($t == $BINRPC_STRUCT) { return HMCCURPCPROC_EncStruct ($v); }

	return '';
}

######################################################################
# Detect type
# Default type is STRING
######################################################################

sub HMCCURPCPROC_DetType ($)
{
	my ($v) = @_;

	if (ref($v) eq 'ARRAY') { return $BINRPC_ARRAY; }
	if (ref($v) eq 'HASH') { return $BINRPC_STRUCT; }
	if (HMCCU_IsIntNum($v)) { return $BINRPC_INTEGER; }
	if (HMCCU_IsFltNum($v)) { return $BINRPC_DOUBLE; }
	if ($v eq 'true' || $v eq 'false') { return $BINRPC_BOOL; }
	return $BINRPC_STRING;
}

######################################################################
# Encode RPC request with method and optional parameters.
# Headers are not supported.
# Input is method name and reference to parameter array.
# Array must contain parameters in format value[:type]. Default for
# type is STRING. 
# Return encoded data or empty string on error
######################################################################
# Binary RPC request format:
#
# Offset Size Description
#   0      3  'Bin'
#   3      1  Type: 0=Request, 1=Response
#   4      4  Total length of data: n+4(ml)+4(pc)+p
#   8      4  Length of request method name (ml)
#  12      n  Request method name
#  12+n    4  Number of parameters (pc)
#  16+n    p  Encoded parameters
######################################################################

sub HMCCURPCPROC_EncodeRequest ($$)
{
	my ($method, $args) = @_;
	
	return '' if (!defined($method) || $method eq '');

	# Encode method
	my $methodEnc = HMCCURPCPROC_EncName ($method);
	
	# Encode parameters
	my $re = ':('.join('|', keys(%BINRPC_TYPE_MAPPING)).')';
	my $content = '';
	my $s = 0;

	while (my $p = shift @$args) {
		my $encType = HMCCURPCPROC_EncType ($p);
		return '' if ($encType eq '');
		$content .= $encType;
		$s++;
	}
	
	my $header = pack ('NN', $BINRPC_REQUEST, 8+length($method)+length($content)).
		$methodEnc.pack('N', $s);
	
	return $header.$content;
}

######################################################################
# Encode RPC response
# Input is type and value
######################################################################

sub HMCCURPCPROC_EncodeResponse ($;$)
{
	my ($v, $t) = @_;

	if (defined ($v)) {
		my $r = HMCCURPCPROC_EncType ($v, $t);
		# BINRPC is not a standard. Some implementations require an offset of 8 to be added
		return pack ('NN', $BINRPC_RESPONSE, length($r)+8).$r;
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
	if (defined($s) && $i+$s+4 <= length ($d)) {
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

	return (undef, undef) if ($i+8 > length($d));
	
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
	if (defined($s)) {
		my $j = $x;
		for (my $n=0; $n<$s; $n++) {
			my ($v, $o) = HMCCURPCPROC_DecType ($d, $i+$j);
			return (undef, undef) if (!defined($o));
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
	if (defined($s)) {
		my $j = $x;
		for (my $n=0; $n<$s; $n++) {
			my ($k, $o1) = HMCCURPCPROC_DecString ($d, $i+$j);
			return (undef, undef) if (!defined($o1));
			my ($v, $o2) = HMCCURPCPROC_DecType ($d, $i+$j+$o1);
			return (undef, undef) if (!defined($o2));
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
# element could be a scalar, array ref or hash ref.
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
		return (undef, undef) if (!defined($d)|| !defined($s));
		push (@r, $d);
		$i += $s;
	}
		
	return (lc($method), \@r);
}

######################################################################
# Decode response.
# Return (ref, type) or (undef, undef)
# type: 1=ok, 0=error
######################################################################

sub HMCCURPCPROC_DecodeResponse ($)
{
	my ($data) = @_;
	
	return (undef, 0) if (length($data) < 8);
	
	my $id = unpack ('N', substr ($data, 0, 4));
	if ($id == $BINRPC_RESPONSE) {
		# Data
		my ($result, $offset) = HMCCURPCPROC_DecType ($data, 8);
		return ($result, defined($result) ? 1 : 0);
	}
	elsif ($id == $BINRPC_ERROR) {
		# Error
		my ($result, $offset) = HMCCURPCPROC_DecType ($data, 8);
		return ($result, 0);
	}
#	Response with header not supported
#	elsif ($id == 0x42696E41) {
#	}
	
	return (undef, 0);
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
	  <li><b>set &lt;name&gt; rpcrequest &lt;method&gt; [{&lt;value[:type]&gt;|&lt;parameter&gt;=&lt;value[:type]&gt;|'!STRUCT'} ...]</b><br/>
		Send RPC request to CCU. The result is displayed in FHEM browser window. See EQ-3
		RPC XML documentation for mor information about valid methods and requests.<br/>
		If <i>type</i> is not speicifed, it's detected automatically. Valid types are:<br/>
		INTEGER, BOOL, FLOAT, DOUBLE, BASE64, STRING (defaul)<br/>
		The command also supports passing a parameter structure. All parameters in format
		Name=Value[:Type] are treated as members of a structure. This structure will be
		appended to the list of the other parameters. If you like to insert the structure
		at a speicifc position in the parameter list, use '!STRUCT' as a placeholder.<br/>
		Example:<br/>
		set myRPCDev rpcrequest putParamset 123456 VALUES SET_POINT_TEMPERATURE=20:FLOAT SET_POINT_MODE=1<br/>
		Parameters SET_POINT_TEMPERATURE and SET_POINT_MODE will be converted to a structure.
		This structure is passed as the last parameter to the request.
	  </li><br/>
	  <li><b>set &lt;name&gt; rpcserver { on | off }</b><br/>
		Start or stop RPC server. This command is only available if expert mode is activated.
	  </li><br/>
	</ul>
	
	<a name="HMCCURPCPROCget"></a>
	<b>Get</b><br/><br/>
	<ul>
		<li><b>get &lt;name&gt; devicedesc [&lt;fhem-device&gt;|&lt;address&gt;]</b><br/>
			Read device and paramset descriptions for current RPC interface from CCU and
			store the information in I/O device. The device description is always read from 
			CCU. The paramset description is only read if it doesn't exist in IO device.
			If a HMCCUCHN device or a channel address is specified, the description of the
			corresponding device address with all channels is read.
		</li><br/>
		<li><b>get &lt;name&gt; rpcevent</b><br/>
			Show RPC server events statistics. If attribute ccuflags contains flag 'statistics'
			the 3 devices which sent most events are listed.
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
			noEvents - Ignore events from CCU, do not update client device readings.<br/>
			noInitalUpdate - Do not update devices after RPC server started.<br/>
			noMulticalls - Do not execute RPC requests as multicalls (only BidCos-RF)<br/>
			queueEvents - Always write events into queue and send them asynchronously to FHEM.
			Frequency of event transmission to FHEM depends on attribute rpcConnTimeout.<br/>
			statistics - Count events per device sent by CCU<br/>
		</li><br/>
		<li><b>rpcAcceptTimeout &lt;seconds&gt;</b><br/>
			Specify timeout for accepting incoming connections. Default is 1 second. Increase this 
			value by 1 or 2 seconds on slow systems.
		</li><br/>
	   <li><b>rpcConnTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout of incoming CCU connections. Default is 1 second. Value must be greater than 0.
	   </li><br/>
	   <li><b>rpcEventTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout for CCU events. Default is 0, timeout is ignored. If timeout occurs an event
	   	is triggered. If ccuflag reconnect is set in I/O device the RPC device tries to establish a new
	   	connection to the CCU.
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
	   <li><b>rpcPingCCU &lt;interval&gt;</b><br/>
	   	Ignored. Should be set in I/O device.
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
	   <li><b>rpcReadTimeout &lt;seconds&gt;</b><br/>
		Wait the specified time for socket to become readable. Default value is 0.005 seconds.
		When using a CCU2 and parameter set definitions cannot be read (timeout), increase this
		value, i.e. to 0.01. Drawback: This could slow down the FHEM start time.
	   </li><br/>
	   <li><b>rpcRetryRequest &lt;retries&gt;</b><br/>
	    Number of times, failed RPC requests are repeated. Default is 1. Parameter <i>retries</i>
		must be in range 0-2.
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
			Wait the specified time for socket to become writeable. Default value is 0.001 seconds.
		</li>
	</ul>
</ul>

=end html
=cut



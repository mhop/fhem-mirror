##############################################################################
#
#  88_HMCCURPC.pm
#
#  $Id$
#
#  Version 0.98 beta
#
#  Thread based RPC Server module for HMCCU.
#
#  (c) 2017 by zap (zap01 <at> t-online <dot> de)
#
##############################################################################
#  Requires modules:
#
#    threads
#    Thread::Queue
#    Time::HiRes
#    RPC::XML::Client
#    RPC::XML::Server
##############################################################################


package main;

use strict;
use warnings;

use threads;
use Thread::Queue;
# use Data::Dumper;
use Time::HiRes qw(usleep);
use RPC::XML::Client;
use RPC::XML::Server;
use SetExtensions;


######################################################################
# Constants
######################################################################

# HMCCURPC version
my $HMCCURPC_VERSION = '0.98 beta';

# Maximum number of events processed per call of Read()
my $HMCCURPC_MAX_EVENTS = 50;

# Maximum number of errors during TriggerIO() before log message is written
my $HMCCURPC_MAX_IOERRORS  = 100;

# Maximum number of elements in queue
my $HMCCURPC_MAX_QUEUESIZE = 500;

# Time to wait after data processing loop
my $HMCCURPC_TIME_WAIT = 100000;

# Time to wait before calling TriggerIO() again after I/O error
my $HMCCURPC_TIME_TRIGGER = 10;

# Timeout for established CCU connection
my $HMCCURPC_TIMEOUT_CONNECTION = 10;

# Timeout for TriggerIO()
my $HMCCURPC_TIMEOUT_WRITE = 0.001;

# Timeout for accepting incoming connections
my $HMCCURPC_TIMEOUT_ACCEPT = 1;

# Timeout for incoming CCU events
my $HMCCURPC_TIMEOUT_EVENT = 600;

# Send statistic information after specified amount of events
my $HMCCURPC_STATISTICS = 500;

# Default RPC Port = BidCos-RF
my $HMCCURPC_RPC_PORT_DEFAULT = 2001;

# RPC protocol name by port number
my %HMCCURPC_RPC_NUMPORT = (
	2000 => 'BidCos-Wired', 2001 => 'BidCos-RF', 2010 => 'HmIP-RF', 9292 => 'VirtualDevices',
	2003 => 'Homegear', 8701 => 'CUxD'
);

# RPC ports by protocol name
my %HMCCURPC_RPC_PORT = (
   'BidCos-Wired', 2000, 'BidCos-RF', 2001, 'HmIP-RF', 2010, 'VirtualDevices', 9292,
   'Homegear', 2003, 'CUxD', 8701
);

# URL extensions
my %HMCCURPC_RPC_URL = (
	9292, 'groups'
);

# Type of RPC interface. A=ASCII B=BINARY
my %HMCCURPC_RPC_PROT = (
   2000 => 'A', 2001 => 'A', 2010 => 'A', 9292 => 'A', 2003 => 'A', 8701 => 'B'
);

# Initial intervals for registration of RPC callbacks and reading RPC queue
#
# X                         = Start RPC server
# X+HMCCURPC_INIT_INTERVAL1 = Register RPC callback
# X+HMCCURPC_INIT_INTERVAL2 = Read RPC Queue
#
my $HMCCURPC_INIT_INTERVAL0 = 12;
my $HMCCURPC_INIT_INTERVAL1 = 7;
my $HMCCURPC_INIT_INTERVAL2 = 5;
my $HMCCURPC_INIT_INTERVAL3 = 25;

# Thread type flags
my $HMCCURPC_THREAD_DATA   = 1;
my $HMCCURPC_THREAD_ASCII  = 2;
my $HMCCURPC_THREAD_BINARY = 4;
my $HMCCURPC_THREAD_SERVER = 6;
my $HMCCURPC_THREAD_ALL    = 7;

# Data types
my $BINRPC_INTEGER = 1;
my $BINRPC_BOOL    = 2;
my $BINRPC_STRING  = 3;
my $BINRPC_DOUBLE  = 4;
my $BINRPC_BASE64  = 17;
my $BINRPC_ARRAY   = 256;
my $BINRPC_STRUCT  = 257;

# Message types
my $BINRPC_REQUEST        = 0x42696E00;
my $BINRPC_RESPONSE       = 0x42696E01;
my $BINRPC_REQUEST_HEADER = 0x42696E40;
my $BINRPC_ERROR          = 0x42696EFF;


######################################################################
# Functions
######################################################################

# Standard functions
sub HMCCURPC_Initialize ($);
sub HMCCURPC_Define ($$);
sub HMCCURPC_Undef ($$);
sub HMCCURPC_Shutdown ($);
sub HMCCURPC_Attr ($@);
sub HMCCURPC_Set ($@);
sub HMCCURPC_Get ($@);
sub HMCCURPC_Notify ($$);
sub HMCCURPC_Read ($);
sub HMCCURPC_SetError ($$);
sub HMCCURPC_SetState ($$);
sub HMCCURPC_SetRPCState ($$$);
sub HMCCURPC_ResetRPCState ($$);
sub HMCCURPC_IsRPCStateBlocking ($);
sub HMCCURPC_FindHMCCUDevice ($);
sub HMCCURPC_ProcessEvent ($$);

# RPC server management functions
sub HMCCURPC_GetAttribute ($$$$);
sub HMCCURPC_GetRPCPortList ($);
sub HMCCURPC_ListDevices ($);
sub HMCCURPC_RegisterCallback ($);
sub HMCCURPC_RegisterSingleCallback ($$$);
sub HMCCURPC_DeRegisterCallback ($);
sub HMCCURPC_InitRPCServer ($$$);
sub HMCCURPC_StartRPCServer ($);
sub HMCCURPC_CleanupThreads ($$$);
sub HMCCURPC_CleanupThreadIO ($);
sub HMCCURPC_TerminateThreads ($$);
sub HMCCURPC_CheckThreadState ($$$$);
sub HMCCURPC_IsRPCServerRunning ($);
sub HMCCURPC_Housekeeping ($);
sub HMCCURPC_StopRPCServer ($);
sub HMCCURPC_IsAscRPCPort ($);
sub HMCCURPC_IsBinRPCPort ($);
sub HMCCURPC_SendRequest ($@);
sub HMCCURPC_SendBinRequest ($@);

# Helper functions
sub HMCCURPC_HexDump ($$);

# RPC server functions
sub HMCCURPC_ProcessRequest ($$);
sub HMCCURPC_HandleConnection ($$$$);
sub HMCCURPC_TriggerIO ($$$);
sub HMCCURPC_ProcessData ($$$$);
sub HMCCURPC_Write ($$$$);
sub HMCCURPC_WriteStats ($$);
sub HMCCURPC_NewDevicesCB ($$$);
sub HMCCURPC_DeleteDevicesCB ($$$);
sub HMCCURPC_UpdateDeviceCB ($$$$);
sub HMCCURPC_ReplaceDeviceCB ($$$$);
sub HMCCURPC_ReaddDevicesCB ($$$);
sub HMCCURPC_EventCB ($$$$$);
sub HMCCURPC_ListDevicesCB ($$);

# Binary RPC encoding functions
sub HMCCURPC_EncInteger ($);
sub HMCCURPC_EncBool ($);
sub HMCCURPC_EncString ($);
sub HMCCURPC_EncName ($);
sub HMCCURPC_EncDouble ($);
sub HMCCURPC_EncBase64 ($);
sub HMCCURPC_EncArray ($);
sub HMCCURPC_EncStruct ($);
sub HMCCURPC_EncType ($$);
sub HMCCURPC_EncodeRequest ($$);
sub HMCCURPC_EncodeResponse ($$);

# Binary RPC decoding functions
sub HMCCURPC_DecInteger ($$$);
sub HMCCURPC_DecBool ($$);
sub HMCCURPC_DecString ($$);
sub HMCCURPC_DecDouble ($$);
sub HMCCURPC_DecBase64 ($$);
sub HMCCURPC_DecArray ($$);
sub HMCCURPC_DecStruct ($$);
sub HMCCURPC_DecType ($$);
sub HMCCURPC_DecodeRequest ($);
sub HMCCURPC_DecodeResponse ($);


######################################################################
# Initialize module
######################################################################

sub HMCCURPC_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCURPC_Define";
	$hash->{UndefFn} = "HMCCURPC_Undef";
	$hash->{SetFn} = "HMCCURPC_Set";
	$hash->{GetFn} = "HMCCURPC_Get";
	$hash->{ReadFn} = "HMCCURPC_Read";
	$hash->{AttrFn} = "HMCCURPC_Attr";
	$hash->{NotifyFn} = "HMCCURPC_Notify";
	$hash->{ShutdownFn} = "HMCCURPC_Shutdown";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "rpcInterfaces:multiple-strict,".join(',',sort keys %HMCCURPC_RPC_PORT).
		" ccuflags:multiple-strict,expert,keepThreads,logEvents,reconnect".
		" rpcMaxEvents rpcQueueSize rpcTriggerTime". 
		" rpcServer:on,off rpcServerAddr rpcServerPort rpcWriteTimeout rpcAcceptTimeout".
		" rpcConnTimeout rpcWaitTime rpcStatistics rpcEventTimeout ".
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCURPC_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $hmccu_hash;
	my $usage = "Usage: define $name HMCCURPC { CCUHost [noiodev] | iodev=Device_Name }";
	
	$hash->{version} = $HMCCURPC_VERSION;
	$hash->{noiodev} = 0;
	
	if (exists ($h->{iodev})) {
		my $ioname = $h->{iodev};
		return "HMCCU I/O device $ioname not found" if (!exists ($defs{$ioname}));
		return "Device $ioname is no HMCCU device" if ($defs{$ioname}->{TYPE} ne 'HMCCU');
		$hmccu_hash = $defs{$ioname};
		$hash->{host} = $hmccu_hash->{host};
	}
	else {
		return $usage if (scalar (@$a) < 3);
		$hash->{host} = $$a[2];
		if (scalar (@$a) > 3) {
			return $usage if ($$a[3] ne 'noiodev');
			$hash->{noiodev} = 1;
		}
	}

	# Try to find I/O device if not defined by parameter iodev
	if (!defined ($hmccu_hash) && $hash->{noiodev} == 0) {
		$hmccu_hash = HMCCURPC_FindHMCCUDevice ($hash);
		return "Can't find HMCCU I/O device" if (!defined ($hmccu_hash));
	}

	if (defined ($hmccu_hash)) {
		# Set I/O device and store reference for RPC device in I/O device
		AssignIoPort ($hash, $hmccu_hash->{NAME});
		$hmccu_hash->{RPCDEV} = $name;
		$hash->{ccutype}  = $hmccu_hash->{ccutype};
		$hash->{CCUNum}   = $hmccu_hash->{CCUNum};
		$hash->{ccustate} = $hmccu_hash->{ccustate};
	}
	else {
		# Count CCU devices
		my $ccucount = 0;
		foreach my $d (keys %defs) {
			my $ch = $defs{$d};
			next if (!exists ($ch->{TYPE}));
			$ccucount++ if ($ch->{TYPE} eq 'HMCCU');
			$ccucount++ if ($ch->{TYPE} eq 'HMCCURPC' && $ch != $hash && $ch->{noiodev} == 1);
		}
		$hash->{CCUNum} = $ccucount+1;
		$hash->{ccutype} = "CCU2";
		$hash->{ccustate} = 'initialized';
	}

	Log3 $name, 1, "HMCCURPC: Device $name. Initialized version $HMCCURPC_VERSION";

	# Set some attributes
	$attr{$name}{stateFormat} = "rpcstate/state";
	$attr{$name}{verbose} = 2;

	HMCCURPC_ResetRPCState ($hash, "initialized");
	
	return undef;
}

######################################################################
# Delete device
######################################################################

sub HMCCURPC_Undef ($$)
{
	my ($hash, $arg) = @_;

	# Delete RPC device name in I/O device
	my $hmccu_hash;
	$hmccu_hash = $hash->{IODev} if (exists ($hash->{IODev}));
	delete $hmccu_hash->{RPCDEV} if (defined ($hmccu_hash) && exists ($hmccu_hash->{RPCDEV}));
	
	# Shutdown RPC server
	HMCCURPC_Shutdown ($hash);

	return undef;
}

######################################################################
# Shutdown FHEM
######################################################################

sub HMCCURPC_Shutdown ($)
{
	my ($hash) = @_;

	# Shutdown RPC server
	HMCCURPC_StopRPCServer ($hash);
	RemoveInternalTimer ($hash);

	return undef;
}

######################################################################
# Set attribute
######################################################################

sub HMCCURPC_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};
	my $rc = 0;

	if ($attrname eq 'rpcInterfaces') {
		my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running', undef);
		return 'Stop RPC server before modifying rpcInterfaces' if ($run > 0);
	}
	
	if ($cmd eq 'set') {
		if ($attrname eq 'rpcInterfaces') {
			my @ports = split (',', $attrval);
			my @plist = ();
			foreach my $p (@ports) {
				return "Illegal RPC interface $p" if (!exists ($HMCCURPC_RPC_PORT{$p}));
				push (@plist, $HMCCURPC_RPC_PORT{$p});
			}
			return "No RPC interface specified" if (scalar (@plist) == 0);
			$hash->{hmccu}{rpcports} = join (',', @plist);
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'rpcInterfaces' && exists ($hash->{hmccu}{rpcports})) {
			delete $hash->{hmccu}{rpcports};
		}
	}
	
	return undef;
}

######################################################################
# Set commands
######################################################################

sub HMCCURPC_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $options = $ccuflags =~ /expert/ ? "rpcrequest rpcserver:on,off" : "";
	my $busyoptions = $ccuflags =~ /expert/ ? "rpcserver:off" : "";

	if ($opt ne 'rpcserver' && HMCCURPC_IsRPCStateBlocking ($hash)) {
		HMCCURPC_SetState ($hash, "busy");
		return "HMCCURPC: CCU busy, choose one of $busyoptions";
	}

	if ($opt eq 'rpcrequest') {
		my $port = shift @$a;
		my $request = shift @$a;
		return "Usage: set $name rpcrequest {port} {request} [{parameter} ...]"
			if (!defined ($request));

		my $response;
		if (HMCCURPC_IsAscRPCPort ($port)) {
			$response = HMCCURPC_SendRequest ($hash, $port, $request, @$a);
		}
		elsif (HMCCURPC_IsBinRPCPort ($port)) {
			$response = HMCCURPC_SendBinRequest ($hash, $port, $request, @$a);
		}
		else {
			return HMCCURPC_SetError ($hash, "Invalid RPC port $port");
		}
					
		return HMCCURPC_SetError ($hash, "RPC request failed") if (!defined ($response));

		my $result = HMCCU_RefToString ($response);
# 		if (ref ($response) eq 'ARRAY') {
# 			$result = join "\n", @$response;
# 		}
# 		elsif (ref ($response) eq 'HASH') {
# 			foreach my $k (keys %$response) {
# 				$result .= "$k = ".$response->{$k}."\n";
# 			}
# 		}
# 		elsif (ref ($response) eq 'SCALAR') {
# 			$result = $$response;
# 		}
# 		else {
# 			if (ref ($response)) {
# 				$result = "Unknown response from CCU of type ".ref ($response);
# 			}
# 			else {
# 				$result = ($response eq '') ? 'Request returned void' : $response;
# 			}
# 		}
				
		return $result;
	}
	elsif ($opt eq 'rpcserver') {
		my $action = shift @$a;

		return HMCCURPC_SetError ($hash, "Usage: set $name rpcserver {on|off}")
		   if (!defined ($action) || $action !~ /^(on|off)$/);

		if ($action eq 'on') {
			return HMCCURPC_SetError ($hash, "RPC server already running")
				if ($hash->{RPCState} ne 'stopped');
			my ($rc, $info) = HMCCURPC_StartRPCServer ($hash);
			return HMCCURPC_SetError ($hash, $info) if (!$rc);
		}
		elsif ($action eq 'off') {
			HMCCURPC_StopRPCServer ($hash);
		}
		
		return HMCCURPC_SetState ($hash, "OK");
	}
	else {
		return "HMCCURPC: Unknown argument $opt, choose one of ".$options;
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCURPC_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $options = "rpcevents:noArg rpcstate:noArg";

	if ($opt ne 'rpcstate' && HMCCURPC_IsRPCStateBlocking ($hash)) {
		HMCCURPC_SetState ($hash, "busy");
		return "HMCCURPC: CCU busy, choose one of rpcstate:noArg";
	}

	my $result = 'Command not implemented';
	my $rc;

	if ($opt eq 'rpcevents') {
		my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");
		$result = '';
		foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
			next if ($clkey eq 'DATA');
			$result .= "Event statistics for server $clkey\n";
			$result .= "Average event delay = ".$hash->{hmccu}{rpc}{$clkey}{avgdelay}."\n"
				if (defined ($hash->{hmccu}{rpc}{$clkey}{avgdelay}));
			$result .= "========================================\n";
			$result .= "ET Sent by RPC server   Received by FHEM\n";
			$result .= "----------------------------------------\n";
			foreach my $et (@eventtypes) {
				my $snd = exists ($hash->{hmccu}{rpc}{$clkey}{snd}{$et}) ?
					sprintf ("%7d", $hash->{hmccu}{rpc}{$clkey}{snd}{$et}) : "    n/a"; 
				my $rec = exists ($hash->{hmccu}{rpc}{$clkey}{rec}{$et}) ?
					sprintf ("%7d", $hash->{hmccu}{rpc}{$clkey}{rec}{$et}) : "    n/a"; 
				$result .= "$et            $snd            $rec\n\n";
			}
		}
		return $result eq '' ? "No event statistics found" : $result;
	}
	elsif ($opt eq 'rpcstate') {
		$result = '';
		foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
			if ($result eq '') {
				$result .= "ID RPC-Thread  State   \n";
				$result .= "-----------------------\n";
			}
			my $sid = sprintf ("%2d", $hash->{hmccu}{rpc}{$clkey}{tid});
		   my $sname = sprintf ("%-6s", $clkey);
			$result .= $sid." ".$sname."      ".$hash->{hmccu}{rpc}{$clkey}{state}."\n";
		}
		$result = "No RPC server running" if ($result eq '');
		return $result;
	}
	else {
		return "HMCCURPC: Unknown argument $opt, choose one of ".$options;
	}
}

######################################################################
# Handle FHEM events
######################################################################

sub HMCCURPC_Notify ($$)
{
	my ($hash, $devhash) = @_;
	my $name = $hash->{NAME};
	my $devname = $devhash->{NAME};
	my $devtype = $devhash->{TYPE};

	my $disable = AttrVal ($name, 'disable', 0);
	my $rpcserver = AttrVal ($name, 'rpcServer', 'off');
	return if ($disable);
		
	my $events = deviceEvents ($devhash, 1);
	return if (! $events);

	# Process events
	foreach my $event (@{$events}) {	
		if ($devname eq 'global') {
			if ($event eq 'INITIALIZED') {
				if (!exists ($hash->{IODev})) {
					my $hmccu_hash = HMCCURPC_FindHMCCUDevice ($hash);
					if (defined ($hmccu_hash)) {
						$hash->{IODev} = $hmccu_hash;
						$hash->{CCUNum} = $hmccu_hash->{CCUNum};
						AssignIoPort ($hash, $hmccu_hash->{NAME});
					}
					else {
						Log3 $name, 0, "HMCCURPC: FHEM initialized but HMCCU IO device not found"
							if ($hash->{noiodev} == 0);
					}
				}
# 				return if ($rpcserver eq 'off');
# 				my $delay = $HMCCURPC_INIT_INTERVAL0;
# 				Log3 $name, 0, "HMCCURPC: Start of RPC server after FHEM initialization in $delay seconds";
# 				if ($ccuflags =~ /threads/) {
# 					InternalTimer (gettimeofday()+$delay, "HMCCURPC_StartRPCServer", $hash, 0);
# 				}
				last;
			}
		}
	}

	return;
}

######################################################################
# Read data from thread
######################################################################

sub HMCCURPC_Read ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my @termtids;
	my $eventcount = 0;	# Total number of events
	my $devcount = 0;		# Number of DD, ND or RD events
	my $evcount = 0;		# Number of EV events
	my %events = ();
	my %devices = ();
	
	Log3 $name, 4, "HMCCURPC: Read called";

	# Check if child socket, event queue and IO device exists
	return if (!defined ($hash->{hmccu}{sockchild}));
	my $child = $hash->{hmccu}{sockchild};
	return if (!defined ($hash->{hmccu}{eventqueue}));
	my $queue = $hash->{hmccu}{eventqueue};
	my $hmccu_hash = (exists ($hash->{IODev}) && $hash->{noiodev} == 0) ? $hash->{IODev} : $hash;
	
	# Get attributes
	my $rpcmaxevents = AttrVal ($name, 'rpcMaxEvents', $HMCCURPC_MAX_EVENTS);
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	
	# Data read from child socket is only a trigger for reading data from event queue
	my $buffer = '';
	my $res = sysread ($child, $buffer, 4096);
	if (!defined ($res) || length ($buffer) == 0) {
		Log3 $name, 4, "HMCCURPC: read failed";
		return;
	}
	else {
		Log3 $name, 4, "HMCCURPC: read $buffer from child socket";
	}

	# Read events from queue
	$hash->{hmccu}{readqueue}->enqueue (1);
	while (my $item = $queue->dequeue_nb ()) {
		Log3 $name, 4, "HMCCURPC: read $item from queue";
		my ($et, $clkey, @par) = HMCCURPC_ProcessEvent ($hash, $item);
		next if (!defined ($et));
		
		if ($et eq 'EV') {
			$events{$par[0]}{$par[1]}{$par[2]} = $par[3];
			$evcount++;
			$hmccu_hash->{ccustate} = 'active' if ($hmccu_hash->{ccustate} ne 'active');
		}
		elsif ($et eq 'ND') {
			$devices{$par[0]}{flag} = 'N';
			$devices{$par[0]}{version} = $par[3];
			if ($par[1] eq 'D') {
				$devices{$par[0]}{type} = $par[2];
				$devices{$par[0]}{firmware} = $par[4];
				$devices{$par[0]}{rxmode} = $par[5];
			}
			else {
				$devices{$par[0]}{usetype} = $par[2];
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
		elsif ($et eq 'TO') {
			$hmccu_hash->{ccustate} = 'timeout';
			if ($hash->{RPCState} eq 'running' && $ccuflags =~ /reconnect/) {
				if (HMCCU_TCPConnect ($hash->{host}, $par[0])) {
					$hmccu_hash->{ccustate} = 'active';
					Log3 $name, 2, "HMCCURPC: Reconnecting to CCU interface ".
						$HMCCURPC_RPC_NUMPORT{$par[0]};
					HMCCURPC_RegisterSingleCallback ($hash, $par[0], 1);
				}
				else {
					$hmccu_hash->{ccustate} = 'unreachable';
					Log3 $name, 1, "HMCCURPC: CCU not reachable on port ".$par[0];
				}
			}
		}
		
		$eventcount++;
		if ($eventcount > $rpcmaxevents) {
			Log3 $name, 4, "HMCCURPC: Read stopped after $rpcmaxevents events";
			last;
		}
	}

	# Update device table and client device readings
	if (defined ($hmccu_hash)) {
		HMCCU_UpdateDeviceTable ($hmccu_hash, \%devices) if ($devcount > 0);
		HMCCU_UpdateMultipleDevices ($hmccu_hash, \%events) if ($evcount > 0);
	}
	
	$hash->{hmccu}{readqueue}->dequeue_nb ();
	Log3 $name, 4, "HMCCURPC: Read finished";
}

######################################################################
# Set error state and write log file message
######################################################################

sub HMCCURPC_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $msg;

	$msg = defined ($text) ? $text : "unknown error";
	$msg = $type.": ".$name." ". $msg;

	HMCCURPC_SetState ($hash, "Error");
	Log3 $name, 1, $msg;
	return $msg;
}

######################################################################
# Set state of device
######################################################################

sub HMCCURPC_SetState ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};

	if (defined ($hash) && defined ($text)) {
		readingsSingleUpdate ($hash, "state", $text, 1);
	}

	return ($text eq "busy") ? "HMCCURPC: CCU busy" : undef;
}

######################################################################
# Set state of RPC server
######################################################################

sub HMCCURPC_SetRPCState ($$$)
{
	my ($hash, $state, $msg) = @_;
	
	# Search HMCCU device and check for running RPC servers
	my $hmccu_hash;
	$hmccu_hash = $hash->{IODev} if (exists ($hash->{IODev}));
	
	$hash->{RPCState} = $state;
	readingsSingleUpdate ($hash, "rpcstate", $state, 1);
	Log3 $hash->{NAME}, 1, "HMCCURPC: $msg" if (defined ($msg));
	
	# Update internals of I/O device
	if (defined ($hmccu_hash)) {
		$hmccu_hash->{RPCState} = $state;
		readingsSingleUpdate ($hmccu_hash, "rpcstate", $state, 1);
	}
}

######################################################################
# Reset RPC State
######################################################################

sub HMCCURPC_ResetRPCState ($$)
{
	my ($hash, $state) = @_;

	# Search HMCCU device and check for running RPC servers
	my $hmccu_hash;
	$hmccu_hash = $hash->{IODev} if (exists ($hash->{IODev}) && $hash->{noiodev} == 0);
	
	$hash->{RPCState} = "stopped";		# RPC server state
	$hash->{RPCTID} = "0";					# List of RPC server thread IDs
	
	$hash->{hmccu}{evtime} = 0;			# Timestamp of last event from CCU
	$hash->{hmccu}{rpcstarttime} = 0;	# Timestamp of RPC server start

	readingsBeginUpdate ($hash);
	readingsBulkUpdate ($hash, "state", $state);
	readingsBulkUpdate ($hash, "rpcstate", "stopped");
	readingsEndUpdate ($hash, 1);
	
	if (defined ($hmccu_hash) && $state ne "initialized") {
		$hmccu_hash->{RPCState} = "stopped";
		readingsBeginUpdate ($hmccu_hash);
		readingsBulkUpdate ($hmccu_hash, "state", $state);
		readingsBulkUpdate ($hmccu_hash, "rpcstate", "stopped");
		readingsEndUpdate ($hmccu_hash, 1);
	}
}

######################################################################
# Check if CCU is busy due to RPC start or stop
######################################################################

sub HMCCURPC_IsRPCStateBlocking ($)
{
	my ($hash) = @_;

	return ($hash->{RPCState} eq "running" || $hash->{RPCState} eq "stopped") ? 0 : 1;
}

######################################################################
# Return hash of corresponding HMCCU device.
# CCU name in HMCCU device must match CCU name in HMCCURPC device.
######################################################################

sub HMCCURPC_FindHMCCUDevice ($)
{
	my ($hash) = @_;
	
	return undef if ($hash->{noiodev} == 1);
	return $hash->{IODev} if (defined ($hash->{IODev}));
	
	for my $d (keys %defs) {
		my $h = $defs{$d};
		next if (!exists ($h->{TYPE}) || !exists ($h->{NAME}));
		next if ($h->{TYPE} ne 'HMCCU');
		return $h if ($h->{host} eq $hash->{host});
	}
	
	return undef;
}

######################################################################
# Process RPC server event
######################################################################

sub HMCCURPC_ProcessEvent ($$)
{
	my ($hash, $event) = @_;
	my $name = $hash->{NAME};
	my $rh = \%{$hash->{hmccu}{rpc}};	# Just for code simplification
	my $hmccu_hash;
	$hmccu_hash = $hash->{IODev} if (exists ($hash->{IODev}) && $hash->{noiodev} == 0);

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
	
	# Parse event
	return undef if (!defined ($event) || $event eq '');
	my @t = split (/\|/, $event);
	my $et = shift @t;
	my $clkey = shift @t;
	my $tc = scalar (@t);

	# Check event data
	if (!defined ($clkey)) {
		Log3 $name, 2, "HMCCURPC: Syntax error in RPC event data";
		return undef;
	}
	
	# Check for valid server
	if (!exists ($rh->{$clkey})) {
		Log3 $name, 0, "HMCCURPC: Received SL event for unknown RPC server $clkey";
		return undef;
	}

	# Check event type
	if (!exists ($rpceventargs{$et})) {
		$et =~ s/([\x00-\xFF])/sprintf("0x%X ",ord($1))/eg;
		Log3 $name, 2, "HMCCURPC: Received unknown event from CCU: ".$et;
		return undef;
	}
	
	# Check event parameters
	if ($tc != $rpceventargs{$et}) {
		Log3 $name, 2, "HMCCURPC: Wrong number of parameters in event $event. Expected ". 
			$rpceventargs{$et};
		return undef;
	}
	
	# Log event
	Log3 $name, 2, "HMCCURPC: CCUEvent = $event" if ($ccuflags =~ /logEvents/);

	# Update statistic counters
	$rh->{$clkey}{rec}{$et}++;
	$rh->{$clkey}{evtime} = time ();
	
	if ($et eq 'EV') {
		#
		# Update of datapoint
		# Input:  EV|clkey|Time|Address|Datapoint|Value
		# Output: EV, clkey, DevAdd, ChnNo, Datapoint, Value
		#
		my $delay = $rh->{$clkey}{evtime}-$t[0];
		$rh->{$clkey}{sumdelay} += $delay;
		$rh->{$clkey}{avgdelay} = $rh->{$clkey}{sumdelay}/$rh->{$clkey}{rec}{$et};
		if (defined ($hmccu_hash) && $hmccu_hash->{ccustate} ne 'active') {
			$hmccu_hash->{ccustate} = 'active';
		}
		Log3 $name, 2, "HMCCURPC: Received CENTRAL event. ".$t[2]."=".$t[3] if ($t[1] eq 'CENTRAL');
		my ($add, $chn) = split (/:/, $t[1]);
		return defined ($chn) ? ($et, $clkey, $add, $chn, $t[2], $t[3]) : undef;
	}
	elsif ($et eq 'SL') {
		#
		# RPC server enters server loop
		# Input:  SL|clkey|Tid
		# Output: SL, clkey, countWorking
		#
		if ($t[0] == $rh->{$clkey}{tid}) {
			Log3 $name, 1, "HMCCURPC: Received SL event. RPC server $clkey enters server loop";
			$rh->{$clkey}{state} = $clkey eq 'DATA' ? 'running' : 'working';
			my ($run, $alld) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_DATA, 'running', undef);
			my ($work, $alls) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_SERVER, 'working', undef);
			if ($work == $alls && $run == $alld) {
				Log3 $name, 1, "HMCCURPC: All threads working";
				HMCCURPC_RegisterCallback ($hash);
			}		
			return ($et, $clkey, $work);
		}
		else {
			Log3 $name, 0, "HMCCURPC: Received SL event. Wrong TID=".$t[0]." for RPC server $clkey";
			return undef;
		}
	}
	elsif ($et eq 'IN') {
		#
		# RPC server initialized
		# Input:  IN|clkey|INIT|State
		# Output: IN, clkey, Running, ClientsUpdated, UpdateErrors
		#
		my $c_ok = 0;
		my $c_err = 0;

		Log3 $name, 1, "HMCCURPC: Received IN event. RPC server $clkey running.";
		return ($et, $clkey, 0, 0, 0) if ($rh->{$clkey}{state} eq 'running');
		$rh->{$clkey}{state} = "running";
		
		# Set binary RPC interfaces to 'running' if all ascii interfaces are in state 'running'
		my ($runa, $alla) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ASCII, 'running', undef);
		if ($runa == $alla) {
			foreach my $sn (keys %{$rh}) {
				$rh->{$sn}{state} = "running"
					if ($rh->{$sn}{type} == $HMCCURPC_THREAD_BINARY && $rh->{$sn}{state} eq 'registered');
			}
		}
				
		# Check if all RPC servers were initialized. Set overall status
		my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running', undef);
		if ($run == $all) {
			$hash->{hmccu}{rpcstarttime} = 0;
			HMCCURPC_SetRPCState ($hash, "running", "All RPC servers running");
			HMCCURPC_SetState ($hash, "OK");
			if (defined ($hmccu_hash)) {
				HMCCU_SetState ($hmccu_hash, "OK");
				($c_ok, $c_err) = HMCCU_UpdateClients ($hmccu_hash, '.*', 'Attr', 0);
				Log3 $name, 2, "HMCCURPC: Updated devices. Success=$c_ok Failed=$c_err";
			}
			RemoveInternalTimer ($hash);
			DoTrigger ($name, "RPC server running");
		}
		return ($et, $clkey, $run, $c_ok, $c_err);
	}
	elsif ($et eq 'EX') {
		#
		# Thread stopped
		# Input:  EX|clkey|SHUTDOWN|Tid
		# Output: EX, clkey, Tid, Stopped, All
		#
		Log3 $name, 1, "HMCCURPC: Received EX event. Thread $clkey terminated.";

		my $stopped = 0;
		my $all = 0;
		
		$rh->{$clkey}{state} = 'stopped';
		
		# Check if all threads were terminated. Set overall status
		if ($clkey ne 'DATA') {
			($stopped, $all) = HMCCURPC_CleanupThreads ($hash, $HMCCURPC_THREAD_SERVER, 'stopped');
			if ($stopped == $all) {
				# Terminate data processing thread if all server threads stopped
				Log3 $name, 2, "HMCCURPC: All RPC servers stopped. Terminating data processing thread";
				HMCCURPC_TerminateThreads ($hash, $HMCCURPC_THREAD_DATA);
				sleep (1);
			}
		}
		else {
			($stopped, $all) = HMCCURPC_CleanupThreads ($hash, $HMCCURPC_THREAD_DATA, '.*');
			if ($stopped == $all) {
				HMCCURPC_CleanupThreadIO ($hash);
				HMCCURPC_ResetRPCState ($hash, "OK");
				RemoveInternalTimer ($hash);
				Log3 $name, 1, "HMCCURPC: All threads stopped";
				DoTrigger ($name, "RPC server stopped");
			}
			else {
				Log3 $name, 1, "HMCCURPC: Data processing thread still running";
			}
		}
		return ($et, $clkey, $t[1], $stopped, $all);
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
			$hash->{hmccu}{rpc}{$clkey}{snd}{$eventtypes[$i]} += $t[$i];
		}
		return @res;
	}
	elsif ($et eq 'TO') {
		#
		# Event timeout
		# Input:  TO|clkey|Time
		# Output: TO, clkey, Port, Time
		#
		Log3 $name, 2, "HMCCURPC: Received no events from interface $clkey for ".$t[0]." seconds";
		DoTrigger ($name, "No events from interface $clkey for ".$t[0]." seconds");
		return ($et, $clkey, $hash->{hmccu}{rpc}{$clkey}{port}, $t[0]);
	}

	return undef;
}

######################################################################
# Get list of RPC ports.
# If no ports defined in HMCCURPC device get port list from I/O
# device.
######################################################################

sub HMCCURPC_GetRPCPortList ($)
{
	my ($hash) = @_;
	my @ports = ($HMCCURPC_RPC_PORT_DEFAULT);
	
	if (defined ($hash->{hmccu}{rpcports})) {
		@ports = split (',', $hash->{hmccu}{rpcports});
	}
	else {
		my $hmccu_hash = HMCCURPC_FindHMCCUDevice ($hash);
		if (defined ($hmccu_hash)) {
			@ports = HMCCU_GetRPCPortList ($hmccu_hash);
		}
	}
	
	return @ports;
}

######################################################################
# Get attribute with fallback to I/O device attribute
######################################################################

sub HMCCURPC_GetAttribute ($$$$)
{
	my ($hash, $attr, $ioattr, $default) = @_;
	my $name = $hash->{NAME};
	
	my $value = AttrVal ($hash->{NAME}, $attr, 'null');
	return $value if ($value ne 'null');
	
	my $hmccu_hash = HMCCURPC_FindHMCCUDevice ($hash);
	if (defined ($hmccu_hash)) {
		$value = AttrVal ($hmccu_hash->{NAME}, $ioattr, 'null');
		return $value if ($value ne 'null');
	}
	
	return $default;
}

######################################################################
# Request device list from CCU
######################################################################

sub HMCCURPC_ListDevices ($)
{
	my ($hash, $port) = @_;
	my $name = $hash->{NAME};

	my $serveraddr = $hash->{host};
	my $clurl = "http://$serveraddr:$port/";
		$clurl .= $HMCCURPC_RPC_URL{$port} if (exists ($HMCCURPC_RPC_URL{$port}));

	my $rpcclient = RPC::XML::Client->new ($clurl);
	my $res = $rpcclient->send_request ("listDevices");
}

######################################################################
# Register RPC callbacks at CCU if RPC-Server is in state
# 'working'.
# Return number of registered callbacks.
######################################################################

sub HMCCURPC_RegisterCallback ($)
{
	my ($hash) = @_;

	my @rpcports = HMCCURPC_GetRPCPortList ($hash);
	my $regcount = 0;
	
	foreach my $port (@rpcports) {
		$regcount++ if (HMCCURPC_RegisterSingleCallback ($hash, $port, 0));
	}
	
	return $regcount;
}

######################################################################
# Register callback for specified CCU interface port.
# If parameter 'force' is 1 callback will be registered even if state
# is "running". State will not be modified.
# Return 0 on error.
######################################################################

sub HMCCURPC_RegisterSingleCallback ($$$)
{
	my ($hash, $port, $force) = @_;
	my $name = $hash->{NAME};

	my $serveraddr = $hash->{host};
	my $localaddr = $hash->{hmccu}{localaddr};
	my $rpcserveraddr = AttrVal ($name, 'rpcServerAddr', $localaddr);
	my $clkey = 'CB'.$port;
	
	return 0 if (!exists ($hash->{hmccu}{rpc}{$clkey}));
	return 0 if ($hash->{hmccu}{rpc}{$clkey}{state} ne 'working' && $force == 0);

	my $cburl = '';
	if (HMCCURPC_IsAscRPCPort ($port)) {
		$cburl = "http://$rpcserveraddr:".$hash->{hmccu}{rpc}{$clkey}{cbport}."/fh".$port;
	}
	else {
		$cburl = "xmlrpc_bin://$rpcserveraddr:".$hash->{hmccu}{rpc}{$clkey}{cbport};
	}

	my $clurl = "http://$serveraddr:$port/";
	$clurl .= $HMCCURPC_RPC_URL{$port} if (exists ($HMCCURPC_RPC_URL{$port}));
	
	$hash->{hmccu}{rpc}{$clkey}{port} = $port;
	$hash->{hmccu}{rpc}{$clkey}{clurl} = $clurl;
	$hash->{hmccu}{rpc}{$clkey}{cburl} = $cburl;
	$hash->{hmccu}{rpc}{$clkey}{state} = 'registered' if ($force == 0);

	Log3 $name, 2, "HMCCURPC: Registering callback $cburl with ID $clkey at $clurl";
	my $rc;
	if (HMCCURPC_IsAscRPCPort ($port)) {
		$rc = HMCCURPC_SendRequest ($hash, $port, "init", $cburl, $clkey);
	}
	else {
		$rc = HMCCURPC_SendBinRequest ($hash, $port, "init",
			$BINRPC_STRING, $cburl, $BINRPC_STRING, $clkey);
	}
	
	if (defined ($rc)) {
		Log3 $name, 1, "HMCCURPC: RPC callback with URL $cburl registered";
		return 1;
	}
	else {
		Log3 $name, 1, "HMCCURPC: Failed to register callback for ID $clkey";
		return 0;
	}
}

######################################################################
# Deregister RPC callbacks at CCU
# Return number of deregistered callbacks
######################################################################

sub HMCCURPC_DeRegisterCallback ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $deregcount = 0;
	
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		my $rpchash = \%{$hash->{hmccu}{rpc}{$clkey}};
		next if ($rpchash->{state} ne 'registered' && $rpchash->{state} ne 'running');
		if (exists ($rpchash->{cburl}) && $rpchash->{cburl} ne '') {
			Log3 $name, 1, "HMCCURPC: Deregistering RPC server ".$rpchash->{cburl}.
			   " with ID $clkey at ".$rpchash->{clurl};
			if (HMCCURPC_IsAscRPCPort ($rpchash->{port})) {
				HMCCURPC_SendRequest ($hash, $rpchash->{port}, "init", $rpchash->{cburl});
			}
			else {
				HMCCURPC_SendBinRequest ($hash, $rpchash->{port}, "init", $BINRPC_STRING, $rpchash->{cburl});
			}
			$rpchash->{port} = 0;
			$rpchash->{cburl} = '';
			$rpchash->{clurl} = '';
			$rpchash->{cbport} = 0;
			$rpchash->{state} = 'deregistered';
			
			Log3 $name, 1, "HMCCURPC: RPC callback for server $clkey deregistered";
			$deregcount++;
		}
	}
	
	return $deregcount;
}

######################################################################
# Initialize RPC server for specified CCU port
# Return server object or undef on error
######################################################################

sub HMCCURPC_InitRPCServer ($$$)
{
	my ($name, $serverport, $callbackport) = @_;
	my $clkey = 'CB'.$serverport;
	my $server;

	if (HMCCURPC_IsBinRPCPort ($serverport)) {
		$server->{__daemon} = IO::Socket::INET->new (LocalPort => $callbackport,
			Type => SOCK_STREAM, Reuse => 1, Listen => SOMAXCONN);
		if (!($server->{__daemon})) {
			Log3 $name, 1, "HMCCURPC: Can't create RPC callback server $clkey on port $callbackport. Port in use?";
			return undef;
		}
		return $server;
	}
	
	# Create RPC server
	$server = RPC::XML::Server->new (port => $callbackport);
	if (!ref($server)) {
		Log3 $name, 1, "HMCCURPC: Can't create RPC callback server $clkey on port $callbackport. Port in use?";
		return undef;
	}
	Log3 $name, 2, "HMCCURPC: Callback server $clkey created. Listening on port $callbackport";

	# Callback for events
	Log3 $name, 4, "HMCCURPC: Adding callback for events for server $clkey";
	$server->add_method (
	   { name=>"event",
	     signature=> ["string string string string int","string string string string double","string string string string boolean","string string string string i4"],
	     code=>\&HMCCURPC_EventCB
	   }
	);

	# Callback for new devices
	Log3 $name, 4, "HMCCURPC: Adding callback for new devices for server $clkey";
	$server->add_method (
	   { name=>"newDevices",
	     signature=>["string string array"],
             code=>\&HMCCURPC_NewDevicesCB
	   }
	);

	# Callback for deleted devices
	Log3 $name, 4, "HMCCURPC: Adding callback for deleted devices for server $clkey";
	$server->add_method (
	   { name=>"deleteDevices",
	     signature=>["string string array"],
             code=>\&HMCCURPC_DeleteDevicesCB
	   }
	);

	# Callback for modified devices
	Log3 $name, 4, "HMCCURPC: Adding callback for modified devices for server $clkey";
	$server->add_method (
	   { name=>"updateDevice",
	     signature=>["string string string int"],
	     code=>\&HMCCURPC_UpdateDeviceCB
	   }
	);

	# Callback for replaced devices
	Log3 $name, 4, "HMCCURPC: Adding callback for replaced devices for server $clkey";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string string string"],
	     code=>\&HMCCURPC_ReplaceDeviceCB
	   }
	);

	# Callback for readded devices
	Log3 $name, 4, "HMCCURPC: Adding callback for readded devices for server $clkey";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string array"],
	     code=>\&HMCCURPC_ReaddDeviceCB
	   }
	);
	
	# Dummy implementation, always return an empty array
	Log3 $name, 4, "HMCCURPC: Adding callback for list devices for server $clkey";
	$server->add_method (
	   { name=>"listDevices",
	     signature=>["array string"],
	     code=>\&HMCCURPC_ListDevicesCB
	   }
	);

	return $server;
}

######################################################################
# Start RPC server threads
# 1 thread for processing event data in event queue
# 1 thread per CCU RPC interface for receiving data
# Return number of started RPC server threads or 0 on error.
######################################################################

sub HMCCURPC_StartRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# Search HMCCU device and check for running RPC servers
	my $hmccu_hash = $hash->{IODev} if (exists ($hash->{IODev}) && $hash->{noiodev} == 0);	
	if (defined ($hmccu_hash)) {
		my @hm_pids = ();
		my @ex_pids = ();
		return (0, "RPC server already running for device ".$hmccu_hash->{NAME})
			if (HMCCU_IsRPCServerRunning ($hmccu_hash, \@hm_pids, \@ex_pids));
	}
	
	# Get parameters and attributes
	my %thrpar;
	my @rpcports         = HMCCURPC_GetRPCPortList ($hash);
	my $localaddr        = HMCCURPC_GetAttribute ($hash, 'rpcServerAddr', 'rpcserveraddr', '');
	my $rpcserverport    = HMCCURPC_GetAttribute ($hash, 'rpcServerPort', 'rpcserverport', 5400);
	my $ccuflags         = AttrVal ($name, 'ccuflags', 'null');
	$thrpar{socktimeout} = AttrVal ($name, 'rpcWriteTimeout',  $HMCCURPC_TIMEOUT_WRITE);
	$thrpar{conntimeout} = AttrVal ($name, 'rpcConnTimeout',   $HMCCURPC_TIMEOUT_CONNECTION);
	$thrpar{acctimeout}  = AttrVal ($name, 'rpcAcceptTimeout', $HMCCURPC_TIMEOUT_ACCEPT);
	$thrpar{evttimeout}  = AttrVal ($name, 'rpcEventTimeout',  $HMCCURPC_TIMEOUT_EVENT);
	$thrpar{waittime}    = AttrVal ($name, 'rpcWaitTime',      $HMCCURPC_TIME_WAIT);
	$thrpar{queuesize}   = AttrVal ($name, 'rpcQueueSize',     $HMCCURPC_MAX_QUEUESIZE);
	$thrpar{triggertime} = AttrVal ($name, 'rpcTriggerTime',   $HMCCURPC_TIME_TRIGGER);
	$thrpar{statistics}  = AttrVal ($name, 'rpcStatistics',    $HMCCURPC_STATISTICS);
	$thrpar{name}        = $name;
	
	my $ccunum = $hash->{CCUNum};
	my $serveraddr = $hash->{host};
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");

	# Get or detect local IP address
	if ($localaddr eq '') {
		my $socket = IO::Socket::INET->new (PeerAddr => $serveraddr, PeerPort => $rpcports[0]);
		return (0, "Can't connect to CCU port ".$rpcports[0]) if (!$socket);
		$localaddr = $socket->sockhost ();
		close ($socket);
	}
	$hash->{hmccu}{localaddr} = $localaddr;

	# Create socket pair for communication between data processing thread and FHEM
	my ($sockchild, $sockparent);
	return (0, "Can't create I/O socket pair") if (!socketpair ($sockchild, $sockparent,
		AF_UNIX, SOCK_STREAM || SOCK_NONBLOCK, PF_UNSPEC));
	$sockchild->autoflush (1);
	$sockparent->autoflush (1);
	$hash->{hmccu}{sockchild} = $sockchild;
	$hash->{hmccu}{sockparent} = $sockparent;
	my $fd_child = fileno $sockchild;
	my $fd_parent = fileno $sockparent;

	# Enable FHEM I/O
	my $pid = $$;
	$hash->{FD} = $fd_child;
	$selectlist{"RPC.$name.$pid"} = $hash; 

	# Create event data queue
	my $equeue = Thread::Queue->new ();
	$hash->{hmccu}{eventqueue} = $equeue;

	# Create queue for controlling data processing
	my $rqueue = Thread::Queue->new ();
	$hash->{hmccu}{readqueue} = $rqueue;

	# Start thread for data processing
	Log3 $name, 2, "HMCCURPC: Starting thread for data processing";
	my $pthread = threads->create ('HMCCURPC_ProcessData', $equeue, $rqueue, $sockparent, \%thrpar);
	return (0, "Can't start data processing thread") if (!defined ($pthread));
	Log3 $name, 2, "HMCCURPC: Started thread for data processing. TID=" . $pthread->tid ();
	$pthread->detach ();

	$hash->{hmccu}{rpc}{DATA}{type}   = $HMCCURPC_THREAD_DATA;
	$hash->{hmccu}{rpc}{DATA}{child}  = $pthread;
	$hash->{hmccu}{rpc}{DATA}{cbport} = 0;
	$hash->{hmccu}{rpc}{DATA}{tid}    = $pthread->tid ();
	$hash->{hmccu}{rpc}{DATA}{state}  = 'initialized';

	# Reset state of all RPC server threads
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		$hash->{hmccu}{rpc}{$clkey}{state} = 'inactive';
	}
		
	# Initialize RPC servers
	my @hm_tids;
	my $err = '';
	foreach my $port (@rpcports) {
		my $clkey = 'CB'.$port;
		my $callbackport = $rpcserverport+$port+($ccunum*10);
		my $interface = $HMCCURPC_RPC_NUMPORT{$port};

		# Start RPC server thread
		my $thr = threads->create ('HMCCURPC_HandleConnection',
			$port, $callbackport, $equeue, \%thrpar);
		if (!defined ($thr)) {
			$err = "Can't create RPC server thread for interface $interface";
			last;
		}
		$thr->detach ();
		Log3 $name, 2, "HMCCURPC: RPC server thread started for interface $interface with TID=".
			$thr->tid ();

		# Store thread parameters
		$hash->{hmccu}{rpc}{$clkey}{type}   = HMCCURPC_IsBinRPCPort ($port) ?
			$HMCCURPC_THREAD_BINARY : $HMCCURPC_THREAD_ASCII;
		$hash->{hmccu}{rpc}{$clkey}{child}  = $thr;
		$hash->{hmccu}{rpc}{$clkey}{cbport} = $callbackport;
		$hash->{hmccu}{rpc}{$clkey}{tid}    = $thr->tid ();
		$hash->{hmccu}{rpc}{$clkey}{state}  = 'initialized';
		push (@hm_tids, $thr->tid ());
		
		# Reset statistic counter
		foreach my $et (@eventtypes) {
			$hash->{hmccu}{rpc}{$clkey}{rec}{$et} = 0;
			$hash->{hmccu}{rpc}{$clkey}{snd}{$et} = 0;
		}
		$hash->{hmccu}{rpc}{$clkey}{sumdelay} = 0;
	}

	sleep (1);
	
	# Cleanup if one or more threads are not initialized (ignore thread state)
	my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, '.*', undef);
	if ($run != $all) {
		Log3 $name, 0, "HMCCURPC: Only $run from $all threads are running. Cleaning up";
		HMCCURPC_Housekeeping ($hash);
		return (0, $err);
	}

	$hash->{RPCTID} = join (',', @hm_tids);
	$hash->{hmccu}{rpcstarttime} = time ();

	# Trigger Timer function for checking successful RPC start
	# Timer will be removed if event 'IN' is reveived
	InternalTimer (gettimeofday()+$HMCCURPC_INIT_INTERVAL3*$run, "HMCCURPC_IsRPCServerRunning",
		$hash, 0);
	
	HMCCURPC_SetRPCState ($hash, "starting", "RPC server(s) starting");
	DoTrigger ($name, "RPC server starting");
	
	return ($run, undef);
}

######################################################################
# Stop I/O Handling
######################################################################

sub HMCCURPC_CleanupThreadIO ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $pid = $$;
	if (exists ($selectlist{"RPC.$name.$pid"})) {
		Log3 $name, 2, "HMCCURPC: Stop I/O handling";
		delete $selectlist{"RPC.$name.$pid"};
		delete $hash->{FD} if (defined ($hash->{FD}));
	}
	if (defined ($hash->{hmccu}{sockchild})) {
		Log3 $name, 2, "HMCCURPC: Close child socket";
		$hash->{hmccu}{sockchild}->close ();
		delete $hash->{hmccu}{sockchild};
	}
	if (defined ($hash->{hmccu}{sockparent})) {
		Log3 $name, 2, "HMCCURPC: Close parent socket";
		$hash->{hmccu}{sockparent}->close ();
		delete $hash->{hmccu}{sockparent};
	}
}

######################################################################
# Terminate RPC server threads and data processing thread by sending
# an INT signal.
# Parameter mode specifies which threads should be terminated:
#   1 - Terminate data processing thread
#   2 - Terminate server threads
#   3 - Terminate all threads
# Number of threads with INT sent
######################################################################

sub HMCCURPC_TerminateThreads ($$)
{
	my ($hash, $mode) = @_;
	my $name = $hash->{NAME};
	
	my $count = 0;
	
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		next if ($hash->{hmccu}{rpc}{$clkey}{state} eq 'inactive');
		next if (!($hash->{hmccu}{rpc}{$clkey}{type} & $mode));
		next if (!exists ($hash->{hmccu}{rpc}{$clkey}{child}));
		my $thr = $hash->{hmccu}{rpc}{$clkey}{child};
		if (defined ($thr) && $thr->is_running ()) {
			$hash->{hmccu}{rpc}{$clkey}{state} = "stopping";
			Log3 $name, 2, "HMCCURPC: Sending signal INT to thread $clkey TID=".$thr->tid ();
			$thr->kill ('INT');
			$count++;
		}
	}
	
	return $count;
}

######################################################################
# Cleanup threads in specified state.
# Parameter state is a regular expression.
# Return number of deleted threads
######################################################################

sub HMCCURPC_CleanupThreads ($$$)
{
	my ($hash, $mode, $state) = @_;
	my $name = $hash->{NAME};
	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	
	my $count = 0;
	my $all = 0;
	
	# Check if threads has been stopped
	my @thrlist = keys %{$hash->{hmccu}{rpc}};
	foreach my $clkey (@thrlist) {
		next if ($hash->{hmccu}{rpc}{$clkey}{state} eq 'inactive');
		next if (!($hash->{hmccu}{rpc}{$clkey}{type} & $mode));
		$all++;
		if (exists ($hash->{hmccu}{rpc}{$clkey}{child})) {
			my $thr = $hash->{hmccu}{rpc}{$clkey}{child};
			if (defined ($thr)) {
				if ($thr->is_running () || $hash->{hmccu}{rpc}{$clkey}{state} !~ /$state/) {
					Log3 $name, 1, "HMCCURPC: Thread $clkey with TID=".$thr->tid().
						" still running. Can't delete it";
					next;
				}
				if ($hash->{hmccu}{rpc}{$clkey}{state} eq 'stopped' && $ccuflags !~ /keepThreads/) {
					Log3 $name, 2, "HMCCURPC: Thread $clkey with TID=".$thr->tid ().
						" has been stopped. Deleting it";
					undef $hash->{hmccu}{rpc}{$clkey}{child};
				}
				else {
					Log3 $name, 2, "HMCCURPC: Thread $clkey with TID=".$thr->tid ().
						" is in state ".$hash->{hmccu}{rpc}{$clkey}{state}.". Can't delete it";
				}
#				delete $hash->{hmccu}{rpc}{$clkey};
			}
		}
		$count++;
	}
	
	return ($count, $all);
}

######################################################################
# Count threads in specified state.
# Parameter state is a regular expression.
# Parameter mode specifies which threads should be counted:
# If state is empty thread state is ignored and only running threads
# are counted by calling thread function is_running().
# Return number of threads in specified state and total number of
# threads. Also return IDs of running threads if parameter tids is
# defined and parameter state is 'running' or '.*'.
######################################################################

sub HMCCURPC_CheckThreadState ($$$$)
{
	my ($hash, $mode, $state, $tids) = @_;
	my $count = 0;
	my $all = 0;

	$mode = $HMCCURPC_THREAD_ALL if (!defined ($mode));
	$state = '' if (!defined ($state));
	
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		next if ($hash->{hmccu}{rpc}{$clkey}{state} eq 'inactive');
		next if (!($hash->{hmccu}{rpc}{$clkey}{type} & $mode));
		$all++;
		if ($state eq 'running' || $state eq '.*') {
			next if (!exists ($hash->{hmccu}{rpc}{$clkey}{child}));
			my $thr = $hash->{hmccu}{rpc}{$clkey}{child};
			if (defined ($thr) && $thr->is_running () &&
				($state eq '' || $hash->{hmccu}{rpc}{$clkey}{state} =~ /$state/)) {
				$count++;
				push (@$tids, $thr->tid()) if (defined ($tids));
			}
		}
		else {
			$count++ if ($hash->{hmccu}{rpc}{$clkey}{state} =~ /$state/);
		}
	}

	return ($count, $all);
}

######################################################################
# Timer function to check if all threads are running
######################################################################

sub HMCCURPC_IsRPCServerRunning ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	Log3 $name, 2, "HMCCURPC: Checking if all threads are running";
	my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running', undef);
	if ($run != $all) {
		Log3 $name, 1, "HMCCURPC: Only $run of $all threads are running. Cleaning up";
		HMCCURPC_Housekeeping ($hash);
		return 0;
	}

	Log3 $name, 2, "HMCCURPC: $run of $all threads are running";
	
	return 1;
}

######################################################################
# Cleanup all threads
######################################################################

sub HMCCURPC_Housekeeping ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	Log3 $name, 1, "HMCCURPC: Housekeeping called. Cleaning up RPC environment";

	# Deregister callback URLs in CCU
	HMCCURPC_DeRegisterCallback ($hash);

	# Stop I/O handling
	HMCCURPC_CleanupThreadIO ($hash);
	
 	my $count = HMCCURPC_TerminateThreads ($hash, $HMCCURPC_THREAD_ALL);
	sleep (2) if ($count > 0);
	
	my ($del, $total) = HMCCURPC_CleanupThreads ($hash, $HMCCURPC_THREAD_ALL, '.*');
	$count = $total-$del;
	if ($count == 0) {
		HMCCURPC_ResetRPCState ($hash, "OK");
	}
	else {
		HMCCURPC_SetRPCState ($hash, "error", "Clean up failed for $count threads");
	}
}

######################################################################
# Stop RPC server threads
# Data processing thread is stopped when receiving 'EX' event.
######################################################################

sub HMCCURPC_StopRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running', undef);
	if ($run > 0) {
		HMCCURPC_SetRPCState ($hash, "stopping", "Found $run threads. Stopping ...");

		# Deregister callback URLs in CCU
		HMCCURPC_DeRegisterCallback ($hash);

		# Stop RPC server threads 
 		HMCCURPC_TerminateThreads ($hash, $HMCCURPC_THREAD_SERVER);

		# Trigger timer function for checking successful RPC stop
		# Timer will be removed wenn receiving EX event from data processing thread
		InternalTimer (gettimeofday()+$HMCCURPC_INIT_INTERVAL3*$all, "HMCCURPC_Housekeeping",
			$hash, 0);
		
		# Give threads the chance to terminate
		sleep (1);
	}
	elsif ($run == 0 && $hash->{RPCState} ne 'stopped') {
		Log3 $name, 2, "HMCCURPC: Found no running threads. Cleaning up ...";
		HMCCURPC_CleanupThreadIO ($hash);
		HMCCURPC_CleanupThreads ($hash, $HMCCURPC_THREAD_ALL, '.*');
		HMCCURPC_ResetRPCState ($hash, "OK");
	}
		
	return 1;
}

######################################################################
# Check if port is valid and an ascii RPC port
######################################################################

sub HMCCURPC_IsAscRPCPort ($)
{
	my ($port) = @_;
	
	return exists ($HMCCURPC_RPC_PROT{$port}) && $HMCCURPC_RPC_PROT{$port} eq 'A' ? 1 : 0;
}

######################################################################
# Check if port is valid and a binary RPC port
######################################################################

sub HMCCURPC_IsBinRPCPort ($)
{
	my ($port) = @_;
	
	return exists ($HMCCURPC_RPC_PROT{$port}) && $HMCCURPC_RPC_PROT{$port} eq 'B' ? 1 : 0;
}

######################################################################
# Send ascii RPC request to CCU
# Return response or undef on error.
######################################################################

sub HMCCURPC_SendRequest ($@)
{
	my ($hash, $port, $request, @param) = @_;
	my $name = $hash->{NAME};
	my $serveraddr = $hash->{host};
	
	return undef if (!HMCCURPC_IsAscRPCPort ($port));	
	
	Log3 $name, 4, "HMCCURPC: Send ASCII RPC request $request to $serveraddr:$port";

	my $clurl = "http://$serveraddr:$port/";
	$clurl .= $HMCCURPC_RPC_URL{$port} if (exists ($HMCCURPC_RPC_URL{$port}));
	my $rpcclient = RPC::XML::Client->new ($clurl);
	return $rpcclient->simple_request ($request, @param);
}

######################################################################
# Send binary RPC request to CCU
# Return response or undef on error. Return empty string on missing
# server response.
######################################################################
	
sub HMCCURPC_SendBinRequest ($@)
{
	my ($hash, $port, $request, @param) = @_;
	my $name = $hash->{NAME};
	my $serveraddr = $hash->{host};

	return undef if (!HMCCURPC_IsBinRPCPort ($port));	
	
	my $verbose = GetVerbose ($name);
	
	Log3 $name, 4, "HMCCURPC: Send binary RPC request $request to $serveraddr:$port";
	my $encreq = HMCCURPC_EncodeRequest ($request, \@param);
	return undef if ($encreq eq '');

	# auto-flush on socket
	$| = 1;

	# create a connecting socket
	my $socket = new IO::Socket::INET (PeerHost => $serveraddr, PeerPort => $port,
		Proto => 'tcp');
	return undef if (!$socket);
	
	my $size = $socket->send ($encreq);
	if (defined ($size)) {
		my $encresp = <$socket>;
		$socket->close ();
		
		if (defined ($encresp)) {
			Log3 $name, 4, "HMCCURPC: Response";
			HMCCURPC_HexDump ($name, $encresp) if ($verbose >= 4);
			my ($response, $rc) = HMCCURPC_DecodeResponse ($encresp);
			return $response;
		}
		else {
			return '';
		}
	}
	
	$socket->close ();
	return undef;
}

######################################################################
# Process binary RPC request
######################################################################

sub HMCCURPC_ProcessRequest ($$)
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
	
	Log3 $name, 4, "CCURPC: $clkey raw request:";
	HMCCURPC_HexDump ($name, $request) if ($verbose >= 4);
	
	# Decode request
	my ($method, $params) = HMCCURPC_DecodeRequest ($request);
	return if (!defined ($method));
	Log3 $name, 4, "CCURPC: request method = $method";
	
	if ($method eq 'listmethods') {
		$connection->send (HMCCURPC_EncodeResponse ($BINRPC_ARRAY, \@methodlist));
	}
	elsif ($method eq 'listdevices') {
		HMCCURPC_ListDevicesCB ($server, $clkey);
		$connection->send (HMCCURPC_EncodeResponse ($BINRPC_ARRAY, undef));
	}
	elsif ($method eq 'system.multicall') {
		# Send INIT to FHEM when we receive the first event from CCU/CUxD because some binary
		# RPC clients won't send a ListDevices request
		if ($server->{hmccu}{running} == 0) {
			$server->{hmccu}{running} = 1;
			Log3 $name, 1, "CCURPC: Binary RPC $clkey. Sending init to HMCCU";
			HMCCURPC_Write ($server, "IN", $clkey, "INIT|1");
		}
		return if (ref ($params) ne 'ARRAY');
		my $a = $$params[0];
		foreach my $s (@$a) {
			next if (!exists ($s->{methodName}) || !exists ($s->{params}));
			next if ($s->{methodName} ne 'event');
			next if (scalar (@{$s->{params}}) < 4);
 			HMCCURPC_EventCB ($server, $clkey,
 				${$s->{params}}[1], ${$s->{params}}[2], ${$s->{params}}[3]);
 			Log3 $name, 4, "CCURPC: Event ".${$s->{params}}[1]." ".${$s->{params}}[2]." "
 				.${$s->{params}}[3];
		}
	}
}

######################################################################
# Thread function for handling incoming RPC requests
#   thrpar - Hash reference with thread parameters:
#     waittime    - Time to wait after each loop in microseconds
#     name        - FHEM module name for log function
#     socktimeout - Time to wait for socket to become ready
#     queuesize   - Maximum number of queue entries
#     triggertime - Time to wait before retriggering I/O
######################################################################

sub HMCCURPC_HandleConnection ($$$$)
{
	my ($port, $callbackport, $queue, $thrpar) = @_;
	my $name = $thrpar->{name};
	
	my $evttimeout = $thrpar->{evttimeout};
	my $conntimeout = $thrpar->{conntimeout};
	
	my $run = 1;
	my $tid = threads->tid ();
	my $clkey = 'CB'.$port;
	
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");

	# Initialize RPC server
	my $iface = $HMCCURPC_RPC_NUMPORT{$port};
	my $prot = $HMCCURPC_RPC_PROT{$port};
	Log3 $name, 2, "CCURPC: Initializing RPC server $clkey for interface $iface";
	my $rpcsrv = HMCCURPC_InitRPCServer ($name, $port, $callbackport);
	if (!defined ($rpcsrv)) {
		Log3 $name, 1, "CCURPC: Can't initialize RPC server $clkey for interface $iface";
		return;
	}
	if (!($rpcsrv->{__daemon})) {
		Log3 $name, 1, "CCURPC: Server socket not found for port $port";
		return;
	}
	
	# Store RPC server parameters
	$rpcsrv->{hmccu}{name}       = $name;
	$rpcsrv->{hmccu}{clkey}      = $clkey;
	$rpcsrv->{hmccu}{eventqueue} = $queue;
	$rpcsrv->{hmccu}{queuesize}  = $thrpar->{queuesize};
	$rpcsrv->{hmccu}{statistics} = $thrpar->{statistics};
	$rpcsrv->{hmccu}{running}    = 0;
	$rpcsrv->{hmccu}{evttime}    = time ();
	
	# Initialize statistic counters
	foreach my $et (@eventtypes) {
		$rpcsrv->{hmccu}{rec}{$et} = 0;
		$rpcsrv->{hmccu}{snd}{$et} = 0;
	}
	$rpcsrv->{hmccu}{rec}{total} = 0;
	$rpcsrv->{hmccu}{snd}{total} = 0;

	$SIG{INT} = sub { $run = 0; };	

	HMCCURPC_Write ($rpcsrv, "SL", $clkey, $tid);
	Log3 $name, 2, "CCURPC: $clkey accepting connections. TID=$tid";
	
	$rpcsrv->{__daemon}->timeout ($thrpar->{acctimeout});

	while ($run) {
		if ($evttimeout > 0) {
			my $difftime = time()-$rpcsrv->{hmccu}{evttime};
			HMCCURPC_Write ($rpcsrv, "TO", $clkey, $difftime) if ($difftime >= $evttimeout);
		}
		
		# Next statement blocks for timeout seconds
		my $connection = $rpcsrv->{__daemon}->accept ();
		next if (! $connection);
		last if (! $run);
		$connection->timeout ($conntimeout);
		if ($prot eq 'A') {
			Log3 $name, 4, "CCURPC: $clkey processing CCU request";
			$rpcsrv->process_request ($connection);
		}
		else {
			HMCCURPC_ProcessRequest ($rpcsrv, $connection);
		}
		shutdown ($connection, 2);
		close ($connection);
		undef $connection;
	}

	close ($rpcsrv->{__daemon}) if ($prot eq 'B');
	
	# Send statistic info
	HMCCURPC_WriteStats ($rpcsrv, $clkey);

	# Send exit information	
	HMCCURPC_Write ($rpcsrv, "EX", $clkey, "SHUTDOWN|$tid");
	Log3 $name, 2, "CCURPC: RPC server $clkey stopped handling connections. TID=$tid";

	# Log statistic counters
	push (@eventtypes, 'EV');
	foreach my $et (@eventtypes) {
		Log3 $name, 4, "CCURPC: $clkey event type = $et: ".$rpcsrv->{hmccu}{rec}{$et};
	}
	
	return;
}

######################################################################
# Check if file descriptor is writeable and write data.
# Only to inform FHEM I/O loop about data available in thread queue.
# Return 0 on error or trigger time.
######################################################################

sub HMCCURPC_TriggerIO ($$$)
{
	my ($fh, $num_items, $socktimeout) = @_;
	
	my $fd = fileno ($fh);
	my $err = '';
	my $win = '';
	vec ($win, $fd, 1) = 1;
	my $nf = select (undef, $win, undef, $socktimeout);
	if ($nf < 0) {
		$err = $!;
	}
	elsif ($nf == 0) {
		$err = "Select found no reader";
	}
	else {
		my $bytes= syswrite ($fh, "IT|$num_items;");
		if (!defined ($bytes)) {
			$err = $!;
		}
		elsif ($bytes != length ("IT|$num_items;")) {
			$err = "Wrote incomplete data";
		}
	}
	
	return (($err eq '') ? time () : 0, $err);
}

######################################################################
# Thread function for processing RPC events
#   equeue - Event queue
#   rqueue - Read control queue
#   socket - Parent socket
#   thrpar - Hash reference with thread parameters:
#     waittime    - Time to wait after each loop in microseconds
#     name        - FHEM module name for log function
#     socktimeout - Time to wait for socket to become ready
#     queuesize   - Maximum number of queue entries
#     triggertime - Time to wait before retriggering I/O
######################################################################

sub HMCCURPC_ProcessData ($$$$)
{
	my ($equeue, $rqueue, $socket, $thrpar) = @_;

	my $name = $thrpar->{name};
	my $queuesize = $thrpar->{queuesize};
	my $waittime = $thrpar->{waittime};
	my $triggertime = $thrpar->{triggertime};
	my $socktimeout = $thrpar->{socktimeout};
	
	my $threadname = "DATA";
	my $run = 1;
	my $warn = 0;
	my $ec = 0;
	my $tid = threads->tid ();
	
	$SIG{INT} = sub { $run = 0; };

	# Inform FHEM that data processing is ready
	$equeue->enqueue ("SL|$threadname|".$tid);
	Log3 $name, 2, "CCURPC: Thread $threadname processing RPC events. TID=$tid";

	while ($run) {
		# Do nothing as long as HMCCURPC_Read() is reading events from queue
		my $num_read = $rqueue->pending ();
		if ($num_read == 0) {
			# Do nothing if no more items in event queue
			my $num_items = $equeue->pending ();
			if ($num_items > 0) {
				# Check max queue size
				if ($num_items >= $queuesize && $warn == 0) {
					Log3 $name, 2, "CCURPC: Size of event queue exceeds $queuesize";
					$warn = 1;
				}
				else {
					$warn = 0 if ($warn == 1);
				}
				
				# Inform reader about new items in queue
				Log3 $name, 4, "CCURPC: Trigger I/O for $num_items items";
				my ($ttime, $err) = HMCCURPC_TriggerIO ($socket, $num_items, $socktimeout);
				if ($triggertime > 0) {
					if ($ttime == 0) {
						$ec++;
						Log3 $name, 2, "CCURPC: I/O error during data processing ($err)" if ($ec == 1);
						$ec = 0 if ($ec == $HMCCURPC_MAX_IOERRORS);
						sleep ($triggertime);
					}
					else {
						$ec = 0;
					}
				}
			}
		}
		
		threads->yield ();
		usleep ($waittime);
	}

	$equeue->enqueue ("EX|$threadname|SHUTDOWN|".$tid);
	Log3 $name, 2, "CCURPC: $threadname stopped event processing. TID=$tid";
	
	# Inform FHEM about the EX event in queue
	for (my $i=0; $i<10; $i++) {
		my ($ttime, $err) = HMCCURPC_TriggerIO ($socket, 1, $socktimeout);
		last if ($ttime > 0);
		usleep ($waittime);
	}
	
	return;
}

######################################################################
# Write event into queue
######################################################################

sub HMCCURPC_Write ($$$$)
{
	my ($server, $et, $cb, $msg) = @_;
	my $name = $server->{hmccu}{name};

	if (defined ($server->{hmccu}{eventqueue})) {
		my $queue = $server->{hmccu}{eventqueue};

		$server->{hmccu}{evttime} = time ();
		
		if (defined ($server->{hmccu}{queuesize}) &&
			$queue->pending () >= $server->{hmccu}{queuesize}) {
			Log3 $name, 1, "CCURPC: $cb maximum queue size reached";
			return;
		}

		Log3 $name, 4, "CCURPC: $cb enqueue event $et. parameter = $msg";
		$queue->enqueue ($et."|".$cb."|".$msg);
		$server->{hmccu}{rec}{$et}++;
		$server->{hmccu}{rec}{total}++;
		$server->{hmccu}{snd}{$et}++;
		$server->{hmccu}{snd}{total}++;
		HMCCURPC_WriteStats ($server, $cb)
			if ($server->{hmccu}{snd}{total} % $server->{hmccu}{statistics} == 0);
	}
}

######################################################################
# Write statistics
######################################################################

sub HMCCURPC_WriteStats ($$)
{
	my ($server, $clkey) = @_;
	my $name = $server->{hmccu}{name};
	
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL", "TO");

	# Send statistic info
	my $st = $server->{hmccu}{snd}{total};
	foreach my $et (@eventtypes) {
		$st .= '|'.$server->{hmccu}{snd}{$et};
		$server->{hmccu}{snd}{$et} = 0;
	}
	
	Log3 $name, 4, "CCURPC: Event statistics = $st";
	my $queue = $server->{hmccu}{eventqueue};
	$queue->enqueue ("ST|$clkey|$st");
}

######################################################################
# Helper functions
######################################################################

######################################################################
# Dump variable content as hex/ascii combination
######################################################################

sub HMCCURPC_HexDump ($$)
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

sub HMCCURPC_NewDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: $cb NewDevice received $devcount device and channel specifications";	
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
		HMCCURPC_Write ($server, "ND", $cb, $msg);
	}

	return;
}

##################################################
# Callback for deleted devices
##################################################

sub HMCCURPC_DeleteDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: $cb DeleteDevice received $devcount device addresses";
	foreach my $dev (@$a) {
		HMCCURPC_Write ($server, "DD", $cb, $dev);
	}

	return;
}

##################################################
# Callback for modified devices
##################################################

sub HMCCURPC_UpdateDeviceCB ($$$$)
{
	my ($server, $cb, $devid, $hint) = @_;
	my $name = $server->{hmccu}{name};

	Log3 $name, 2, "CCURPC: $cb updated device $devid with hint $hint";	
	HMCCURPC_Write ($server, "UD", $cb, $devid."|".$hint);

	return;
}

##################################################
# Callback for replaced devices
##################################################

sub HMCCURPC_ReplaceDeviceCB ($$$$)
{
	my ($server, $cb, $devid1, $devid2) = @_;
	my $name = $server->{hmccu}{name};
	
	Log3 $name, 2, "CCURPC: $cb device $devid1 replaced by $devid2";
	HMCCURPC_Write ($server, "RD", $cb, $devid1."|".$devid2);

	return;
}

##################################################
# Callback for readded devices
##################################################

sub HMCCURPC_ReaddDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: $cb ReaddDevice received $devcount device addresses";
	foreach my $dev (@$a) {
		HMCCURPC_Write ($server, "RA", $cb, $dev);
	}

	return;
}

##################################################
# Callback for handling CCU events
##################################################

sub HMCCURPC_EventCB ($$$$$)
{
	my ($server, $cb, $devid, $attr, $val) = @_;
	my $name = $server->{hmccu}{name};
	my $etime = time ();
	
	HMCCURPC_Write ($server, "EV", $cb, $etime."|".$devid."|".$attr."|".$val);

	# Never remove this statement!
	return;
}

##################################################
# Callback for list devices
##################################################

sub HMCCURPC_ListDevicesCB ($$)
{
	my ($server, $cb) = @_;
	my $name = $server->{hmccu}{name};
	
	$server->{hmccu}{running} = 1;
	$cb = "unknown" if (!defined ($cb));
	Log3 $name, 1, "CCURPC: $cb ListDevices. Sending init to HMCCU";
	HMCCURPC_Write ($server, "IN", $cb, "INIT|1");

	return RPC::XML::array->new ();
}


######################################################################
# Binary RPC encoding functions
######################################################################

######################################################################
# Encode integer (type = 1)
######################################################################

sub HMCCURPC_EncInteger ($)
{
	my ($v) = @_;
	
	return pack ('Nl', $BINRPC_INTEGER, $v);
}

######################################################################
# Encode bool (type = 2)
######################################################################

sub HMCCURPC_EncBool ($)
{
	my ($v) = @_;
	
	return pack ('NC', $BINRPC_BOOL, $v);
}

######################################################################
# Encode string (type = 3)
# Input is string. Empty string = void
######################################################################

sub HMCCURPC_EncString ($)
{
	my ($v) = @_;
	
	return pack ('NN', $BINRPC_STRING, length ($v)).$v;
}

######################################################################
# Encode name
######################################################################

sub HMCCURPC_EncName ($)
{
	my ($v) = @_;

	return pack ('N', length ($v)).$v;
}

######################################################################
# Encode double (type = 4)
######################################################################

sub HMCCURPC_EncDouble ($)
{
	my ($v) = @_;
 
	my $s = $v < 0 ? -1.0 : 1.0;
	my $l = log (abs($v))/log (2);
	my $f = $l;
       
	if ($l-int ($l) > 0) {
		$f = ($l < 0) ? -int (abs ($l)+1.0) : int ($l);
	}
	my $e = $f+1;
	my $m = int ($s*$v*2**-$e*0x40000000);
       
	return pack ('NNN', $BINRPC_DOUBLE, $m, $e);
}

######################################################################
# Encode base64 (type = 17)
# Input is base64 encoded string
######################################################################

sub HMCCURPC_EncBase64 ($)
{
	my ($v) = @_;
	
	return pack ('NN', $BINRPC_DOUBLE, length ($v)).$v;
}

######################################################################
# Encode array (type = 256)
# Input is array reference. Array must contain (type, value) pairs
######################################################################

sub HMCCURPC_EncArray ($)
{
	my ($a) = @_;
	
	my $r = '';
	my $s = 0;

	if (defined ($a)) {
		while (my $t = shift @$a) {
			my $e = shift @$a;
			if ($e) {
				$r .= HMCCURPC_EncType ($t, $e);
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

sub HMCCURPC_EncStruct ($)
{
	my ($h) = @_;
	
	my $r = '';
	my $s = 0;
	
	foreach my $k (keys %{$h}) {
		$r .= HMCCURPC_EncName ($k);
		$r .= HMCCURPC_EncType ($h->{$k}{T}, $h->{$k}{V});
		$s++;
	}

	return pack ('NN', $BINRPC_STRUCT, $s).$r;
}

######################################################################
# Encode any type
# Input is type and value
# Return encoded data or empty string on error
######################################################################

sub HMCCURPC_EncType ($$)
{
	my ($t, $v) = @_;
	
	if ($t == $BINRPC_INTEGER) {
		return HMCCURPC_EncInteger ($v);
	}
	elsif ($t == $BINRPC_BOOL) {
		return HMCCURPC_EncBool ($v);
	}
	elsif ($t == $BINRPC_STRING) {
		return HMCCURPC_EncString ($v);
	}
	elsif ($t == $BINRPC_DOUBLE) {
		return HMCCURPC_EncDouble ($v);
	}
	elsif ($t == $BINRPC_BASE64) {
		return HMCCURPC_EncBase64 ($v);
	}
	elsif ($t == $BINRPC_ARRAY) {
		return HMCCURPC_EncArray ($v);
	}
	elsif ($t == $BINRPC_STRUCT) {
		return HMCCURPC_EncStruct ($v);
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

sub HMCCURPC_EncodeRequest ($$)
{
	my ($method, $args) = @_;

	# Encode method
	my $m = HMCCURPC_EncName ($method);
	
	# Encode parameters
	my $r = '';
	my $s = 0;

	if (defined ($args)) {
		while (my $t = shift @$args) {
			my $e = shift @$args;
			last if (!defined ($e));
			$r .= HMCCURPC_EncType ($t, $e);
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

sub HMCCURPC_EncodeResponse ($$)
{
	my ($t, $v) = @_;

	if (defined ($t) && defined ($v)) {
		my $r = HMCCURPC_EncType ($t, $v);
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

sub HMCCURPC_DecInteger ($$$)
{
	my ($d, $i, $u) = @_;

	return ($i+4 <= length ($d)) ? (unpack ($u, substr ($d, $i, 4)), 4) : (undef, undef);
}

######################################################################
# Decode bool (type = 2)
# Return (value, packetsize) or (undef, undef)
######################################################################

sub HMCCURPC_DecBool ($$)
{
	my ($d, $i) = @_;

	return ($i+1 <= length ($d)) ? (unpack ('C', substr ($d, $i, 1)), 1) : (undef, undef);
}

######################################################################
# Decode string or void (type = 3)
# Return (string, packet size) or (undef, undef)
# Return ('', 4) for special type 'void'
######################################################################

sub HMCCURPC_DecString ($$)
{
	my ($d, $i) = @_;

	my ($s, $o) = HMCCURPC_DecInteger ($d, $i, 'N');
	if (defined ($s) && $i+$s+4 <= length ($d)) {
		return $s > 0 ? (substr ($d, $i+4, $s), $s+4) : ('', 4);
	}
	
	return (undef, undef);
}

######################################################################
# Decode double (type = 4)
# Return (value, packetsize) or (undef, undef)
######################################################################

sub HMCCURPC_DecDouble ($$)
{
	my ($d, $i) = @_;

	return (undef, undef) if ($i+8 > length ($d));
	
	my $m = unpack ('N', substr ($d, $i, 4));
	my $e = unpack ('N', substr ($d, $i+4, 4));
	
	return (sprintf ("%.6f",$m/0x40000000*(2**$e)), 8);
}

######################################################################
# Decode base64 encoded string (type = 17)
# Return (string, packetsize) or (undef, undef)
######################################################################

sub HMCCURPC_DecBase64 ($$)
{
	my ($d, $i) = @_;
	
	return HMCCURPC_DecString ($d, $i);
}

######################################################################
# Decode array (type = 256)
# Return (arrayref, packetsize) or (undef, undef)
######################################################################

sub HMCCURPC_DecArray ($$)
{
	my ($d, $i) = @_;
	my @r = ();

	my ($s, $x) = HMCCURPC_DecInteger ($d, $i, 'N');
	if (defined ($s)) {
		my $j = $x;
		for (my $n=0; $n<$s; $n++) {
			my ($v, $o) = HMCCURPC_DecType ($d, $i+$j);
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

sub HMCCURPC_DecStruct ($$)
{
	my ($d, $i) = @_;
	my %r;
	
	my ($s, $x) = HMCCURPC_DecInteger ($d, $i, 'N');
	if (defined ($s)) {
		my $j = $x;
		for (my $n=0; $n<$s; $n++) {
			my ($k, $o1) = HMCCURPC_DecString ($d, $i+$j);
			return (undef, undef) if (!defined ($o1));
			my ($v, $o2) = HMCCURPC_DecType ($d, $i+$j+$o1);
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

sub HMCCURPC_DecType ($$)
{
	my ($d, $i) = @_;
	
	return (undef, undef) if ($i+4 > length ($d));

	my @r = ();
	
	my $t = unpack ('N', substr ($d, $i, 4));
	$i += 4;
	
	if ($t == $BINRPC_INTEGER) {
		# Integer
		@r = HMCCURPC_DecInteger ($d, $i, 'N');
	}
	elsif ($t == $BINRPC_BOOL) {
		# Bool
		@r = HMCCURPC_DecBool ($d, $i);
	}
	elsif ($t == $BINRPC_STRING || $t == $BINRPC_BASE64) {
		# String / Base64
		@r = HMCCURPC_DecString ($d, $i);
	}
	elsif ($t == $BINRPC_DOUBLE) {
		# Double
		@r = HMCCURPC_DecDouble ($d, $i);
	}
	elsif ($t == $BINRPC_ARRAY) {
		# Array
		@r = HMCCURPC_DecArray ($d, $i);
	}
	elsif ($t == $BINRPC_STRUCT) {
		# Struct
		@r = HMCCURPC_DecStruct ($d, $i);
	}
	
	$r[1] += 4;

	return @r;
}

######################################################################
# Decode request.
# Return method, arguments. Arguments are returned as array.
######################################################################

sub HMCCURPC_DecodeRequest ($)
{
	my ($data) = @_;

	my @r = ();
	my $i = 8;
	
	return (undef, undef) if (length ($data) < 8);
	
	# Decode method
	my ($method, $o) = HMCCURPC_DecString ($data, $i);
	return (undef, undef) if (!defined ($method));

	$i += $o;
	
	my $c = unpack ('N', substr ($data, $i, 4));
	$i += 4;

	for (my $n=0; $n<$c; $n++) {
		my ($d, $s) = HMCCURPC_DecType ($data, $i);
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

sub HMCCURPC_DecodeResponse ($)
{
	my ($data) = @_;
	
	return (undef, undef) if (length ($data) < 8);
	
	my $id = unpack ('N', substr ($data, 0, 4));
	if ($id == $BINRPC_RESPONSE) {
		# Data
		my ($result, $offset) = HMCCURPC_DecType ($data, 8);
		return ($result, 1);
	}
	elsif ($id == $BINRPC_ERROR) {
		# Error
		my ($result, $offset) = HMCCURPC_DecType ($data, 8);
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

<a name="HMCCURPC"></a>
<h3>HMCCURPC</h3>
<ul>
	The module provides thread based RPC servers for receiving events from HomeMatic CCU2.
	A HMCCURPC device acts as a client device for a HMCCU I/O device. Normally RPC servers of
	HMCCURPC are started from HMCCU I/O device.
   </br></br>
   <a name="HMCCURPCdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCURPC {&lt;HostOrIP&gt;|iodev=&lt;DeviceName&gt;|standalone=&lt;
      HostOrIP&gt;}</code>
      <br/><br/>
      Examples:<br/>
      <code>define myccurpc HMCCURPC 192.168.1.10</code><br/>
      <code>define myccurpc HMCCURPC iodev=myccudev</code><br/>
      <code>define myccurpc HMCCURPC standalone=192.168.1.10</code>
      <br/><br/>
      The parameter <i>HostOrIP</i> is the hostname or IP address of a Homematic CCU2.
      The I/O device can also be specified with parameter iodev. If option <b>standalone</b> is
      specified RPC servers will operate without I/O device (for development purposes).
   </ul>
   <br/>
   
   <a name="HMCCURPCset"></a>
   <b>Set</b><br/><br/>
   <ul>
		<li><b> set &lt;name&gt; rpcrequest &lt;port&gt; &lt;method&gt; [&lt;parameters&gt;]</b><br/>
			Send RPC request to CCU. The result is displayed in FHEM browser window. Parameter 
			&lt;port&gt; is a valid RPC port (i.e. 2001 for BidCos).
		</li><br/>
		<li><b>set &lt;name&gt; rpcserver { on | off }</b><br/>
			Start or stop RPC server(s). This command is only available if expert mode is activated.
		</li><br/>
	</ul>
	
	<a name="HMCCURPCget"></a>
	<b>Get</b><br/><br/>
	<ul>
		<li><b>get &lt;name&gt; rpcevent</b><br/>
			Show RPC server events statistics.
		</li><br/>
		<li><b>get &lt;name&gt; rpcstate</b><br/>
			Show RPC thread states.
		</li><br/>
	</ul>
	
	<a name="HMCCURPCattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><b>ccuflags { expert }</b><br/>
			Set flags for controlling device behaviour. Meaning of flags is:<br/>
				expert - Activate expert mode<br/>
				keepThreads - Do not delete thread objects after RPC server has been stopped<br/>
				reconnect - Try to re-register at CCU if no events received for rpcEventTimeout seconds<br/>
		</li><br/>
		<li><b>rpcAcceptTimeout &lt;seconds&gt;</b><br/>
			Specify timeout for accepting incoming connections. Default is 1 second. Increase this 
			value by 1 or 2 seconds on slow systems.
		</li><br/>
	   <li><b>rpcConnTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout of CCU connection handling. Default is 10 second.
	   </li><br/>
	   <li><b>rpcEventTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout for CCU events. Default is 600 seconds. If timeout occurs an event
	   	is triggered. If set to 0 the timeout is ignored.
	   </li><br/>
	   <li><b>rpcInterfaces { BidCos-Wired, BidCos-RF, HmIP-RF, VirtualDevices, CUxD, Homegear }</b><br/>
	   	Select RPC interfaces. If attribute is missing the corresponding attribute of I/O device
	   	(HMCCU device) is used. Default is BidCos-RF.
	   </li><br/> 
	   <li><b>rpcMaxEvents &lt;count&gt;</b><br/>
	   	Specify maximum number of events read by FHEM during one I/O loop. If FHEM performance
	   	slows down decrease this value. On a fast system this value can be increased to 100.
	   	Default value is 50.
	   </li><br/>
	   <li><b>rpcQueueSize &lt;count&gt;</b><br/>
	   	Specify maximum size of event queue. When this limit is reached no more CCU events
	   	are forwarded to FHEM. In this case increase this attribute or increase attribute
	   	<b>rpcMaxEvents</b>. Default value is 500.
	   </li><br/>
	   <li><b>rpcServer { on | off }</b><br/>
	   	If set to 'on' start RPC server(s) after FHEM start. Default is 'off'.
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
	   <li><b>rpcTriggerTime &lt;seconds&gt;</b><br/>
	   	Set time to wait before triggering I/O again after an I/O error "no reader" occurred.
	   	Default value is 10 seconds, 0 will deactivate error handling for this kind of error.
	   	On fast systems this value can be set to 5 seconds. Higher values Reduce number of
	   	log messages written if FHEM is busy and not able to read data from CCU.
	   </li><br/>
		<li><b>rpcWaitTime &lt;microseconds&gt;</b><br/>
			Specify time to wait for data processing thread after each loop. Default value is
			100000 microseconds.
		</li><br/>
		<li><b>rpcWriteTimeout &lt;seconds&gt;</b><br/>
			The data processing thread will wait the specified time for FHEM input socket to
			become writeable. Default value is 0.001 seconds.
		</li>
	</ul>
</ul>

=end html
=cut



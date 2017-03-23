##############################################################################
#
#  88_HMCCURPC.pm
#
#  $Id$
#
#  Version 0.8 beta
#
#  Thread based RPC Server module for HMCCU.
#
#  (c) 2017 zap (zap01 <at> t-online <dot> de)
#
##############################################################################
#  Requires modules:
#
#    88_HMCCU.pm
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


# HMCCU version
my $HMCCURPC_VERSION = '0.8 beta';

# Maximum number of errors during TriggerIO()
my $HMCCURPC_MAX_IOERRORS  = 100;
my $HMCCURPC_MAX_QUEUESIZE = 500;

# RPC Ports and URL extensions
my %HMCCURPC_RPC_NUMPORT = (
	2000 => 'BidCos-Wired', 2001 => 'BidCos-RF', 2010 => 'HmIP-RF', 9292 => 'VirtualDevices',
	2003 => 'Homegear'
);
my %HMCCURPC_RPC_PORT = (
   'BidCos-Wired', 2000, 'BidCos-RF', 2001, 'HmIP-RF', 2010, 'VirtualDevices', 9292,
   'Homegear', 2003
);
my %HMCCURPC_RPC_URL = (
	9292, 'groups'
);

# Initial intervals for registration of RPC callbacks and reading RPC queue
#
# X                      = Start RPC server
# X+HMCCURPC_INIT_INTERVAL1 = Register RPC callback
# X+HMCCURPC_INIT_INTERVAL2 = Read RPC Queue
#
my $HMCCURPC_INIT_INTERVAL0 = 12;
my $HMCCURPC_INIT_INTERVAL1 = 7;
my $HMCCURPC_INIT_INTERVAL2 = 5;
my $HMCCURPC_INIT_INTERVAL3 = 25;

my $HMCCURPC_THREAD_DATA = 1;
my $HMCCURPC_THREAD_SERVER = 2;
my $HMCCURPC_THREAD_ALL = 3;

my $HMCCURPC_MAX_EVENTS = 50;

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
sub HMCCURPC_RegisterSingleCallback ($$);
sub HMCCURPC_DeRegisterCallback ($);
sub HMCCURPC_InitRPCServer ($$$);
sub HMCCURPC_StartRPCServer ($);
sub HMCCURPC_CleanupThreads ($$$);
sub HMCCURPC_CleanupThreadIO ($);
sub HMCCURPC_TerminateThreads ($$);
sub HMCCURPC_CheckThreadState ($$$);
sub HMCCURPC_IsRPCServerRunning ($);
sub HMCCURPC_Housekeeping ($);
sub HMCCURPC_StopRPCServer ($);

# RPC server functions
sub HMCCURPC_HandleConnection ($$$$);
sub HMCCURPC_TriggerIO ($$$);
sub HMCCURPC_ProcessData ($$$$);
sub HMCCURPC_Write ($$$$);
sub HMCCURPC_NewDevicesCB ($$$);
sub HMCCURPC_DeleteDevicesCB ($$$);
sub HMCCURPC_UpdateDeviceCB ($$$$);
sub HMCCURPC_ReplaceDeviceCB ($$$$);
sub HMCCURPC_ReaddDevicesCB ($$$);
sub HMCCURPC_EventCB ($$$$$);
sub HMCCURPC_ListDevicesCB ($$);

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
		" ccuflags:multiple-strict,expert rpcMaxEvents rpcQueueSize rpcTriggerTime". 
		" rpcServer:on,off rpcServerAddr rpcServerPort rpcWriteTimeout rpcAcceptTimeout".
		" rpcConnTimeout rpcWaitTime ".
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
	
	if (exists ($h->{iodev})) {
		my $ioname = $h->{iodev};
		return "HMCCU I/O device $ioname not found" if (!exists ($defs{$ioname}));
		return "Device $ioname is no HMCCU device" if ($defs{$ioname}->{TYPE} ne 'HMCCU');
		$hmccu_hash = $defs{$ioname};
		$hash->{host} = $hmccu_hash->{host};
	}
	else {
		return "Usage: define $name HMCCURPC { Host_or_IP | iodev=Device_Name }" if (@$a < 3);
		$hash->{host} = $$a[2];
	}

	# Try to find I/O device if not defined by parameter iodev
	$hmccu_hash = HMCCURPC_FindHMCCUDevice ($hash) if (!defined ($hmccu_hash));
	return "Can't find HMCCU I/O device" if (!defined ($hmccu_hash));

	# Set I/O device
	AssignIoPort ($hash, $hmccu_hash->{NAME});
	
	# Store name of RPC device in I/O device
	$hmccu_hash->{RPCDEV} = $name;

	$hash->{version} = $HMCCURPC_VERSION;
	$hash->{ccutype} = $hmccu_hash->{ccutype};
	$hash->{CCUNum}  = $hmccu_hash->{CCUNum};

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
		my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running');
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
	my $options = $ccuflags =~ /expert/ ? "rpcserver:on,off" : "";
	my $busyoptions = $ccuflags =~ /expert/ ? "rpcserver:off" : "";

	if ($opt ne 'rpcserver' && HMCCURPC_IsRPCStateBlocking ($hash)) {
		HMCCURPC_SetState ($hash, "busy");
		return "HMCCURPC: CCU busy, choose one of $busyoptions";
	}

	if ($opt eq 'rpcserver') {
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
	my $options = "rpcevents:noArg rpcstate:noArg";

	if ($opt ne 'rpcstate' && HMCCURPC_IsRPCStateBlocking ($hash)) {
		HMCCURPC_SetState ($hash, "busy");
		return "HMCCURPC: CCU busy, choose one of rpcstate:noArg";
	}

	my $result = 'Command not implemented';
	my $rc;

	if ($opt eq 'rpcevents') {
		my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL");
		$result = '';
		foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
			next if ($clkey eq 'DATA');
			$result .= "Event statistics for server $clkey\n";
			$result .= "========================================\n";
			$result .= "ET Sent by RPC server   Received by FHEM\n";
			$result .= "----------------------------------------\n";
			foreach my $et (@eventtypes) {
				my $snd = exists ($hash->{hmccu}{rpc}{$clkey}{snd}{$et}) ?
					sprintf ("%5d", $hash->{hmccu}{rpc}{$clkey}{snd}{$et}) : "  n/a"; 
				my $rec = exists ($hash->{hmccu}{rpc}{$clkey}{rec}{$et}) ?
					sprintf ("%5d", $hash->{hmccu}{rpc}{$clkey}{rec}{$et}) : "  n/a"; 
				$result .= "$et             $snd              $rec\n\n";
			}
		}
		return $result eq '' ? "No event statistics found" : $result;
	}
	elsif ($opt eq 'rpcstate') {
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
	my $rpcserver = AttrVal ($name, 'rpcserver', 'off');
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
						Log3 $name, 0, "HMCCURPC: FHEM initialized but HMCCU IO device not found";
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
	return if (!exists ($hash->{IODev}));
	my $hmccu_hash = $hash->{IODev};
	
	# Get attributes
	my $rpcmaxevents = AttrVal ($name, 'rpcMaxEvents', $HMCCURPC_MAX_EVENTS);
	
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
		
		$eventcount++;
		if ($eventcount > $rpcmaxevents) {
			Log3 $name, 4, "Read stopped after $rpcmaxevents events";
			last;
		}
	}

	# Update device table
 	HMCCU_UpdateDeviceTable ($hmccu_hash, \%devices) if ($devcount > 0);
 	
 	# Update client device readings
 	HMCCU_UpdateMultipleDevices ($hmccu_hash, \%events) if ($evcount > 0);

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
	$hmccu_hash = $hash->{IODev} if (exists ($hash->{IODev}));
	
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
	my $hmccu_hash = $hash->{IODev};

	# Number of arguments in RPC events
	my %rpceventargs = (
		"EV", 3,
		"ND", 6,
		"DD", 1,
		"RD", 2,
		"RA", 1,
		"UD", 2,
		"IN", 2,
		"EX", 2,
		"SL", 1,
		"ST", 9
	);
	
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

	# Update statistic counters
	$rh->{$clkey}{rec}{$et}++;
	$rh->{$clkey}{evtime} = time ();
	
	if ($et eq 'EV') {
		#
		# Update of datapoint
		# Input:  EV|clkey|Address|Datapoint|Value
		# Output: EV, clkey, DevAdd, ChnNo, Datapoint, Value
		#
		my ($add, $chn) = split (/:/, $t[0]);
		return ($et, $clkey, $add, $chn, $t[1], $t[2]);
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
			my ($run, $alld) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_DATA, "running");
			my ($work, $alls) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_SERVER, 'working');
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
		$rh->{$clkey}{state} = "running";
		
		# Check if all RPC servers were initialized. Set overall status
		my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running');
		if ($run == $all) {
			$hash->{hmccu}{rpcstarttime} = 0;
			HMCCURPC_SetRPCState ($hash, "running", "All RPC servers running");
			HMCCURPC_SetState ($hash, "OK");
			($c_ok, $c_err) = HMCCU_UpdateClients ($hmccu_hash, '.*', 'Attr', 0);
			Log3 $name, 2, "HMCCURPC: Updated devices. Success=$c_ok Failed=$c_err";
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
				# Terminate data processing thread
				Log3 $name, 2, "HMCCURPC: All RPC servers stopped. Terminating data processing thread";
				HMCCURPC_TerminateThreads ($hash, $HMCCURPC_THREAD_DATA);
				sleep (1);
			}
		}
		else {
			# Vielleicht besser außerhalb von Read() löschen
			HMCCURPC_CleanupThreadIO ($hash);
			($stopped, $all) = HMCCURPC_CleanupThreads ($hash, $HMCCURPC_THREAD_DATA, '.*');
			if ($stopped == $all) {
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
		# Statistic data. Store snapshots of sent and received events.
		# Input:  ST|clkey|nTotal|nEV|nND|nDD|nRD|nRA|nUD|nIN|nSL|nEX
		# Output: ST, clkey, ...
		#
		my @res = ($et, $clkey);
		push (@res, @t);
		my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL");
		for (my $i=0; $i<$rpceventargs{$et}; $i++) {
			$hash->{hmccu}{rpc}{$clkey}{snd}{$eventtypes[$i]} += $t[$i];
		}
		return @res;
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
	my @ports = (2001);
	
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
		$regcount++ if (HMCCURPC_RegisterSingleCallback ($hash, $port));
	}
	
	return $regcount;
}

######################################################################
# Register single callback
######################################################################

sub HMCCURPC_RegisterSingleCallback ($$)
{
	my ($hash, $port) = @_;
	my $name = $hash->{NAME};

	my $serveraddr = $hash->{host};
	my $localaddr = $hash->{hmccu}{localaddr};
	my $rpcserveraddr = AttrVal ($name, 'rpcServerAddr', $localaddr);
	my $clkey = 'CB'.$port;
	
	return 0 if (!exists ($hash->{hmccu}{rpc}{$clkey}) ||
		$hash->{hmccu}{rpc}{$clkey}{state} ne 'working');
	
	my $cburl = "http://$rpcserveraddr:".$hash->{hmccu}{rpc}{$clkey}{cbport}."/fh".$port;
	my $clurl = "http://$serveraddr:$port/";
		$clurl .= $HMCCURPC_RPC_URL{$port} if (exists ($HMCCURPC_RPC_URL{$port}));
	
	$hash->{hmccu}{rpc}{$clkey}{clurl} = $clurl;
	$hash->{hmccu}{rpc}{$clkey}{cburl} = $cburl;
	$hash->{hmccu}{rpc}{$clkey}{state} = 'registered';

	Log3 $name, 1, "HMCCURPC: Registering callback $cburl with ID $clkey at $clurl";
	my $rpcclient = RPC::XML::Client->new ($clurl);
	$rpcclient->send_request ("init", $cburl, $clkey);
	Log3 $name, 1, "HMCCURPC: RPC callback with URL $cburl registered";
	
	return 1;
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
			my $rpcclient = RPC::XML::Client->new ($rpchash->{clurl});
			$rpcclient->send_request ("init", $rpchash->{cburl});
			
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
	
	# Create RPC server
	my $server = RPC::XML::Server->new (port => $callbackport);
	if (!ref($server)) {
		Log3 $name, 1, "HMCCURPC: Can't create RPC callback server $clkey on port $callbackport. Port in use?";
		return undef;
	}
	Log3 $name, 2, "HMCCURPC: Callback server $clkey created. Listening on port $callbackport";

	# Callback for events
	Log3 $name, 2, "HMCCURPC: Adding callback for events for server $clkey";
	$server->add_method (
	   { name=>"event",
	     signature=> ["string string string string int","string string string string double","string string string string boolean","string string string string i4"],
	     code=>\&HMCCURPC_EventCB
	   }
	);

	# Callback for new devices
	Log3 $name, 2, "HMCCURPC: Adding callback for new devices for server $clkey";
	$server->add_method (
	   { name=>"newDevices",
	     signature=>["string string array"],
             code=>\&HMCCURPC_NewDevicesCB
	   }
	);

	# Callback for deleted devices
	Log3 $name, 2, "HMCCURPC: Adding callback for deleted devices for server $clkey";
	$server->add_method (
	   { name=>"deleteDevices",
	     signature=>["string string array"],
             code=>\&HMCCURPC_DeleteDevicesCB
	   }
	);

	# Callback for modified devices
	Log3 $name, 2, "HMCCURPC: Adding callback for modified devices for server $clkey";
	$server->add_method (
	   { name=>"updateDevice",
	     signature=>["string string string int"],
	     code=>\&HMCCURPC_UpdateDeviceCB
	   }
	);

	# Callback for replaced devices
	Log3 $name, 2, "HMCCURPC: Adding callback for replaced devices for server $clkey";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string string string"],
	     code=>\&HMCCURPC_ReplaceDeviceCB
	   }
	);

	# Callback for readded devices
	Log3 $name, 2, "HMCCURPC: Adding callback for readded devices for server $clkey";
	$server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string array"],
	     code=>\&HMCCURPC_ReaddDeviceCB
	   }
	);
	
	# Dummy implementation, always return an empty array
	Log3 $name, 2, "HMCCURPC: Adding callback for list devices for server $clkey";
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
	return (0, "No HMCCU IO device found") if (!exists ($hash->{IODev}));
	my $hmccu_hash = $hash->{IODev};	
	my @hm_pids = ();
	my @ex_pids = ();
	return (0, "RPC server already running for device ".$hmccu_hash->{NAME})
		if (HMCCU_IsRPCServerRunning ($hmccu_hash, \@hm_pids, \@ex_pids));
	
	# Get parameters and attributes
	my %thrpar;
	my @rpcports         = HMCCURPC_GetRPCPortList ($hash);
	my $localaddr        = HMCCURPC_GetAttribute ($hash, 'rpcServerAddr', 'rpcserveraddr', '');
	my $rpcserverport    = HMCCURPC_GetAttribute ($hash, 'rpcServerPort', 'rpcserverport', 5400);
	my $ccuflags         = AttrVal ($name, 'ccuflags', 'null');
	$thrpar{socktimeout} = AttrVal ($name, 'rpcWriteTimeout', 0.001);
	$thrpar{conntimeout} = AttrVal ($name, 'rpcConnTimeout', 10);
	$thrpar{acctimeout}  = AttrVal ($name, 'rpcAcceptTimeout', 1);
	$thrpar{waittime}    = AttrVal ($name, 'rpcWaitTime', 100000);
	$thrpar{queuesize}   = AttrVal ($name, 'rpcQueueSize', $HMCCURPC_MAX_QUEUESIZE);
	$thrpar{triggertime} = AttrVal ($name, 'rpcTriggerTime', 10);
	$thrpar{name}        = $name;
	
	my $ccunum = $hash->{CCUNum};
	my $serveraddr = $hash->{host};
	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL");

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
		$hash->{hmccu}{rpc}{$clkey}{type}   = $HMCCURPC_THREAD_SERVER;
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
	}

	sleep (1);
	
	# Cleanup if one or more threads are not initialized (ignore thread state)
	my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, '.*');
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
		delete $hash->{FD};
		delete $selectlist{"RPC.$name.$pid"};
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
				Log3 $name, 2, "HMCCURPC: Thread $clkey with TID=".$thr->tid ().
					" has been stopped. Deleting it";
#				undef $hash->{hmccu}{rpc}{$clkey}{child};
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
#   1 - Count data processing thread
#   2 - Count server threads
#   3 - Count all threads
# If state is empty thread state is ignored and only running threads
# are counted by calling thread function is_running().
# Return number of threads in specified state and total number of
# threads.
######################################################################

sub HMCCURPC_CheckThreadState ($$$)
{
	my ($hash, $mode, $state) = @_;
	my $count = 0;
	my $all = 0;
	
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		next if ($hash->{hmccu}{rpc}{$clkey}{state} eq 'inactive');
		next if (!($hash->{hmccu}{rpc}{$clkey}{type} & $mode));
		$all++;
		if ($state eq 'running' || $state eq '.*') {
			next if (!exists ($hash->{hmccu}{rpc}{$clkey}{child}));
			my $thr = $hash->{hmccu}{rpc}{$clkey}{child};
			$count++ if (defined ($thr) && $thr->is_running () &&
				$hash->{hmccu}{rpc}{$clkey}{state} =~ /$state/);
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
	my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running');
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
	
	# I/O Handling beenden
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

	my ($run, $all) = HMCCURPC_CheckThreadState ($hash, $HMCCURPC_THREAD_ALL, 'running');
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
	
	my $run = 1;
	my $tid = threads->tid ();
	my $clkey = 'CB'.$port;

	my @eventtypes = ("EV", "ND", "DD", "RD", "RA", "UD", "IN", "EX", "SL");

	# Initialize RPC server
	my $iface = $HMCCURPC_RPC_NUMPORT{$port};
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
	$rpcsrv->{hmccu}{name} = $name;
	$rpcsrv->{hmccu}{clkey} = $clkey;
	$rpcsrv->{hmccu}{eventqueue} = $queue;
	$rpcsrv->{hmccu}{queuesize} = $thrpar->{queuesize};
	
	# Initialize statistic counters
	foreach my $et (@eventtypes) {
		$rpcsrv->{hmccu}{snd}{$et} = 0;
	}

	$SIG{INT} = sub { $run = 0; };	

	HMCCURPC_Write ($rpcsrv, "SL", $clkey, $tid);
	Log3 $name, 2, "CCURPC: $clkey accepting connections. TID=$tid";

	$rpcsrv->{__daemon}->timeout ($thrpar->{acctimeout});

	while ($run) {
		# Next statement blocks for timeout seconds
		my $connection = $rpcsrv->{__daemon}->accept ();
		next if (! $connection);
		last if (! $run);
		$connection->timeout ($thrpar->{conntimeout});
		Log3 $name, 4, "CCURPC: $clkey processing CCU request";
		$rpcsrv->process_request ($connection);
		shutdown ($connection, 2);
		undef $connection;
	}

	# Send statistic info
	my $et = shift @eventtypes;
	my $st = $rpcsrv->{hmccu}{snd}{$et};
	foreach $et (@eventtypes) {
		$st .= '|'.$rpcsrv->{hmccu}{snd}{$et};
	}
	HMCCURPC_Write ($rpcsrv, "ST", $clkey, $st);
	
	HMCCURPC_Write ($rpcsrv, "EX", $clkey, "SHUTDOWN|$tid");
	Log3 $name, 2, "CCURPC: RPC server $clkey stopped handling connections. TID=$tid";

	# Log statistic counters
	push (@eventtypes, 'EV');
	foreach my $et (@eventtypes) {
		Log3 $name, 4, "CCURPC: $clkey event type = $et: ".$rpcsrv->{hmccu}{snd}{$et};
	}
}

######################################################################
# Check if file descriptor is writeable and write data.
# Only to inform FHEM I/O loop about data available in thread queue.
# Return 0 on error or trigger time.
######################################################################

sub HMCCURPC_TriggerIO ($$$)
{
	my ($fh, $num_items, $thrpar) = @_;
	
	my $fd = fileno ($fh);
	my $err = '';
	my $win = '';
	vec ($win, $fd, 1) = 1;
	my $nf = select (undef, $win, undef, $thrpar->{socktimeout});
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
		# Do nothing as long as reading is active
		my $num_read = $rqueue->pending ();
		if ($num_read == 0) {
			# Do nothing if no more items in event queue
			my $num_items = $equeue->pending ();
			if ($num_items > 0) {
				# Check max queue size
				if ($num_items >= $thrpar->{queuesize} && $warn == 0) {
					Log3 $name, 2, "CCURPC: Size of event queue exceeds ".$thrpar->{queuesize};
					$warn = 1;
				}
				else {
					$warn = 0 if ($warn == 1);
				}
				
				# Inform reader about new items in queue
				Log3 $name, 4, "CCURPC: Trigger I/O for $num_items items";
				my ($ttime, $err) = HMCCURPC_TriggerIO ($socket, $num_items, $thrpar);
				if ($ttime == 0) {
					$ec++;
					Log3 $name, 2, "CCURPC: I/O error during data processing ($err)" if ($ec == 1);
					$ec = 0 if ($ec == $HMCCURPC_MAX_IOERRORS);
				}
				else {
					$ec = 0;
				}
			}
		}
		
		threads->yield ();
		usleep ($thrpar->{waittime});
	}

	$equeue->enqueue ("EX|$threadname|SHUTDOWN|".$tid);
	Log3 $name, 2, "CCURPC: $threadname stopped event processing. TID=$tid";
	
	# Inform FHEM about the EX event in queue
	for (my $i=0; $i<10; $i++) {
		my ($ttime, $err) = HMCCURPC_TriggerIO ($socket, 1, $thrpar);
		last if ($ttime > 0);
		usleep ($thrpar->{waittime});
	}
	
	return;
}

##################################################
# Write event into queue
##################################################

sub HMCCURPC_Write ($$$$)
{
	my ($server, $et, $cb, $msg) = @_;
	my $name = $server->{hmccu}{name};

	if (defined ($server->{hmccu}{eventqueue})) {
		my $queue = $server->{hmccu}{eventqueue};

		if (defined ($server->{hmccu}{queuesize}) &&
			$queue->pending () >= $server->{hmccu}{queuesize}) {
			Log3 $name, 1, "CCURPC: $cb maximum queue size reached";
			return;
		}

		Log3 $name, 4, "CCURPC: $cb enqueue event $et. parameter = $msg";
		$queue->enqueue ($et."|".$cb."|".$msg);
		$server->{hmccu}{snd}{$et}++;
	}
}

######################################################################
# Callback functions
######################################################################

##################################################
# Callback for new devices
##################################################

sub HMCCURPC_NewDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $server->{hmccu}{name};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: $cb NewDevice received $devcount device specifications";	
	foreach my $dev (@$a) {
		my $msg = '';
		if ($dev->{ADDRESS} =~ /:[0-9]{1,2}$/) {
			$msg = "C|".$dev->{ADDRESS}."|".$dev->{TYPE}."|".$dev->{VERSION}."|null|null";
		}
		else {
			$msg = "D|".$dev->{ADDRESS}."|".$dev->{TYPE}."|".$dev->{VERSION}."|".
				$dev->{FIRMWARE}."|".$dev->{RX_MODE};
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
	
	HMCCURPC_Write ($server, "EV", $cb, $devid."|".$attr."|".$val);

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
	
	$cb = "unknown" if (!defined ($cb));
	Log3 $name, 1, "CCURPC: $cb ListDevices. Sending init to HMCCU";
	HMCCURPC_Write ($server, "IN", $cb, "INIT|1");

	return RPC::XML::array->new ();
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
      <code>define &lt;name&gt; HMCCURPC {&lt;HostOrIP&gt;|iodev=&lt;DeviceName&gt;}</code>
      <br/><br/>
      Examples:<br/>
      <code>define myccurpc HMCCURPC 192.168.1.10</code><br/>
      <code>define myccurpc HMCCURPC iodev=myccudev</code>
      <br/><br/>
      The parameter <i>HostOrIP</i> is the hostname or IP address of a Homematic CCU2.
      The I/O device can also be specified with parameter iodev.
   </ul>
   <br/>
   
   <a name="HMCCURPCset"></a>
   <b>Set</b><br/><br/>
   <ul>
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
	</ul>
	
	<a name="HMCCURPCattr"></a>
	<b>Attributes</b><br/><br/>
	<ul>
		<li><b>ccuflags { expert }</b><br/>
			Set flags for controlling device behaviour. Meaning of flags is:<br/>
				expert - Activate expert mode<br/>
		</li><br/>
		<li><b>rpcAcceptTimeout &lt;seconds&gt;</b><br/>
			Specify timeout for accepting incoming connections. Default is 1 second. Increase this 
			value by 1 or 2 seconds on slow systems.
		</li><br/>
	   <li><b>rpcConnTimeout &lt;seconds&gt;</b><br/>
	   	Specify timeout of CCU connection handling. Default is 10 second.
	   </li><br/>
	   <li><b>rpcInterfaces { BidCos-Wired, BidCos-RF, HmIP-RF, VirtualDevices, Homegear }</b><br/>
	   	Select RPC interfaces. If attribute is missing the corresponding attribute of I/O device
	   	(HMCCU device) is used. Default is BidCos-RF.
	   </li><br/> 
	   <li><b>rpcMaxEvents &lt;count&gt;</b><br/>
	   	Specify maximum number of events read by FHEM during one I/O loop. If FHEM performance
	   	slows down decrease this value. On a fast system this value can be increased to 100.
	   	Default value is 50.
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
	   <li><b>rpcQueueSize &lt;count&gt;</b><br/>
	   	Specify maximum size of event queue. When this limit is reached no more CCU events
	   	are forwarded to FHEM. In this case increase this attribute or increase attribute
	   	<b>rpcMaxEvents</b>. Default value is 500.
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



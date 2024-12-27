##############################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 5.0
#
#  Module for communication between FHEM and Homematic CCU2/3.
#
#  Supports BidCos-RF, BidCos-Wired, HmIP-RF, virtual CCU channels,
#  CCU group devices, HomeGear, CUxD, Osram Lightify, Homematic Virtual Layer
#  and Philips Hue (not tested)
#
#  (c) 2024 by zap (zap01 <at> t-online <dot> de)
#
##############################################################################
#
#  Verbose levels:
#
#  0 = Log start/stop and initialization messages
#  1 = Log errors
#  2 = Log counters and warnings
#  3 = Log events and runtime information
#
##############################################################################

package main;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use strict;
use warnings;
# use Data::Dumper;
use Encode qw(decode encode);
use RPC::XML::Client;
use RPC::XML::Server;
use JSON;
use HttpUtils;
use SetExtensions;
use HMCCUConf;

# Import configuration data
my $HMCCU_CONFIG_VERSION = $HMCCUConf::HMCCU_CONFIG_VERSION;
my $HMCCU_DEF_ROLE       = \%HMCCUConf::HMCCU_DEF_ROLE;
my $HMCCU_STATECONTROL   = \%HMCCUConf::HMCCU_STATECONTROL;
my $HMCCU_READINGS       = \%HMCCUConf::HMCCU_READINGS;
my $HMCCU_ROLECMDS       = \%HMCCUConf::HMCCU_ROLECMDS;
my $HMCCU_GETROLECMDS    = \%HMCCUConf::HMCCU_GETROLECMDS;
my $HMCCU_ATTR           = \%HMCCUConf::HMCCU_ATTR;
my $HMCCU_CONVERSIONS    = \%HMCCUConf::HMCCU_CONVERSIONS;
my $HMCCU_CHN_DEFAULTS   = \%HMCCUConf::HMCCU_CHN_DEFAULTS;
my $HMCCU_DEV_DEFAULTS   = \%HMCCUConf::HMCCU_DEV_DEFAULTS;
my $HMCCU_SCRIPTS        = \%HMCCUConf::HMCCU_SCRIPTS;

# Custom configuration data
my %HMCCU_CUST_CHN_DEFAULTS;
my %HMCCU_CUST_DEV_DEFAULTS;

# HMCCU version
my $HMCCU_VERSION = '2024-12';

# Timeout for CCU requests (seconds)
my $HMCCU_TIMEOUT_REQUEST = 4;

# ReGa Ports
my %HMCCU_REGA_PORT = (
	'http' => 8181, 'https' => '48181'
);

# RPC interface priority
my @HMCCU_RPC_PRIORITY = ('BidCos-RF', 'HmIP-RF', 'BidCos-Wired');

# RPC port name by port number
my %HMCCU_RPC_NUMPORT = (
	2000 => 'BidCos-Wired', 2001 => 'BidCos-RF', 2010 => 'HmIP-RF', 9292 => 'VirtualDevices',
	2003 => 'Homegear', 8701 => 'CUxD', 7000 => 'HVL'
);

# RPC port number by port name
my %HMCCU_RPC_PORT = (
   'BidCos-Wired', 2000, 'BidCos-RF', 2001, 'HmIP-RF', 2010, 'VirtualDevices', 9292,
   'Homegear', 2003, 'CUxD', 8701, 'HVL', 7000
);

# RPC flags
my %HMCCU_RPC_FLAG = (
	2000 => 'forceASCII', 2001 => 'forceASCII', 2003 => '_', 2010 => 'forceASCII',
	7000 => 'forceInit', 8701 => 'forceInit', 9292 => '_'
);

my %HMCCU_RPC_SSL = (
	2000 => 1, 2001 => 1, 2010 => 1, 9292 => 1,
	'BidCos-Wired' => 1, 'BidCos-RF' => 1, 'HmIP-RF' => 1, 'VirtualDevices' => 1
);

# Default values for delayed initialization during FHEM startup
my $HMCCU_INIT_INTERVAL0   = 12;
my $HMCCU_CCU_PING_TIMEOUT = 1;
my $HMCCU_CCU_PING_SLEEP   = 1;
my $HMCCU_CCU_BOOT_DELAY   = 180;
my $HMCCU_CCU_DELAYED_INIT = 59;
my $HMCCU_CCU_RPC_OFFSET   = 20;

# Datapoint operations
my $HMCCU_OPER_READ  = 1;
my $HMCCU_OPER_WRITE = 2;
my $HMCCU_OPER_EVENT = 4;

# Datapoint types
my $HMCCU_TYPE_BINARY  = 2;
my $HMCCU_TYPE_FLOAT   = 4;
my $HMCCU_TYPE_INTEGER = 16;
my $HMCCU_TYPE_STRING  = 20;

# Flags for address/name checks
my $HMCCU_FL_STADDRESS = 1;
my $HMCCU_FL_NAME      = 2;
my $HMCCU_FL_EXADDRESS = 4;
my $HMCCU_FL_ADDRESS   = 5;
my $HMCCU_FL_ALL       = 7;

# Default values
my $HMCCU_DEF_HMSTATE = '^0\.UNREACH!(1|true):unreachable;^[0-9]\.LOW_?BAT!(1|true):warn_battery';

# Placeholder for external addresses (i.e. HVL)
my $HMCCU_EXT_ADDR = 'ZZZ0000000';

# Error codes
my %HMCCU_ERR_LIST = (
	-1 => 'Invalid device/channel name or address',
	-2 => 'Execution of CCU script or command failed',
	-3 => 'Cannot detect IO device',
	-4 => 'Device deleted in CCU',
	-5 => 'No response from CCU',
	-6 => 'Update of readings disabled. Remove ccuflag noReadings',
	-7 => 'Invalid channel number',
	-8 => 'Invalid datapoint',
	-9 => 'Interface does not support RPC calls',
	-10 => 'No readable datapoints found',
	-11 => 'No state channel defined',
	-12 => 'No control channel defined',
	-13 => 'No state datapoint defined',
	-14 => 'No control datapoint defined',
	-15 => 'No state values defined',
	-16 => 'Cannot open file',
	-17 => 'Cannot detect or create external RPC device',
	-18 => 'Type of system variable not supported',
	-19 => 'Device not initialized',
	-20 => 'Invalid or unknown device interface',
	-21 => 'Device disabled',
	-22 => 'Invalid RPC method',
	-23 => 'Invalid parameter in RPC request'
);


# Declare functions

# FHEM standard functions
sub HMCCU_Initialize ($);
sub HMCCU_Define ($$$);
sub HMCCU_InitDevice ($);
sub HMCCU_Undef ($$);
sub HMCCU_Renane ($$);
sub HMCCU_DelayedShutdown ($);
sub HMCCU_Shutdown ($);
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_Notify ($$);
sub HMCCU_Detail ($$$$);
sub HMCCU_PostInit ($);

# Aggregation
sub HMCCU_AggregateReadingsRule ($$);
sub HMCCU_AggregationRules ($$);

# Handling of default attributes
sub HMCCU_ExportDefaults ($$);
sub HMCCU_ImportDefaults ($);
sub HMCCU_FindDefaults ($);
sub HMCCU_GetDefaults ($;$);
sub HMCCU_SetDefaults ($);

# Status and logging functions
sub HMCCU_Trace ($$$);
sub HMCCU_Log ($$$;$);
sub HMCCU_LogDisplay ($$$;$);
sub HMCCU_LogError ($$$);
sub HMCCU_SetError ($@);
sub HMCCU_SetState ($@);
sub HMCCU_SetRPCState ($@);

# Filter and modify readings
sub HMCCU_FilterReading ($$$;$);
sub HMCCU_FormatReadingValue ($$$);
sub HMCCU_GetReadingName ($$$$$;$$$);
sub HMCCU_ScaleValue ($$$$$;$);
sub HMCCU_StripNumber ($$;$);
sub HMCCU_Substitute ($$$$$;$$);
sub HMCCU_SubstRule ($$$);
sub HMCCU_SubstVariables ($$$);

# Update client device readings
sub HMCCU_BulkUpdate ($$$;$$);
sub HMCCU_RefreshReadings ($;$);
sub HMCCU_UpdateCB ($$$);
sub HMCCU_UpdateClients ($$$;$$);
sub HMCCU_UpdateInternalValues ($$$$$);
sub HMCCU_UpdateMultipleDevices ($$;$);
sub HMCCU_UpdateParamsetReadings ($$$;$);
sub HMCCU_UpdateSingleDatapoint ($$$$);

# RPC functions
sub HMCCU_CreateRPCDevice ($$$$);
sub HMCCU_EventsTimedOut ($);
sub HMCCU_GetRPCCallbackURL ($$$$$);
sub HMCCU_GetRPCDevice ($$$);
sub HMCCU_GetRPCInterfaceList ($;$);
sub HMCCU_GetRPCServerInfo ($$$);
sub HMCCU_IsRPCServerRunning ($;$);
sub HMCCU_IsRPCType ($$$);
sub HMCCU_IsRPCStateBlocking ($);
sub HMCCU_RPCParamsetRequest ($$$;$$);
sub HMCCU_StartExtRPCServer ($);
sub HMCCU_StopExtRPCServer ($;$);

# Parse and validate names and addresses
sub HMCCU_IsDevAddr ($$);
sub HMCCU_IsChnAddr ($$);
sub HMCCU_SplitChnAddr ($;$);
sub HMCCU_SplitDatapoint ($;$);

# FHEM device handling functions
sub HMCCU_AssignIODevice ($$;$);
sub HMCCU_ExistsClientDevice ($$);
sub HMCCU_FindClientDevices ($$;$$);
sub HMCCU_FindIODevice ($);
sub HMCCU_GetHash ($@);
sub HMCCU_GetAttribute ($$$$);
sub HMCCU_GetFlags ($);
sub HMCCU_GetAttrReadingFormat ($$);
sub HMCCU_GetAttrStripNumber ($);
sub HMCCU_GetAttrSubstitute ($;$);
sub HMCCU_IODeviceStates ();
sub HMCCU_IsFlag ($$);

# Handle interfaces, devices and channels
sub HMCCU_AddDevice ($$$;$);
sub HMCCU_AddDeviceDesc ($$$$);
sub HMCCU_AddDeviceModel ($$$$$$);
sub HMCCU_AddPeers ($$$);
sub HMCCU_CheckParameter ($$;$$$);
sub HMCCU_DetectDevice ($$$);
sub HMCCU_CreateFHEMDevices ($@);
sub HMCCU_CreateDevice ($@);
sub HMCCU_IdentifyDeviceRoles ($$$$$$);
sub HMCCU_IdentifyChannelRole ($$$$$);
sub HMCCU_DetectRolePattern ($;$$$$);
sub HMCCU_DeviceDescToStr ($$);
sub HMCCU_ExecuteRoleCommand ($@);
sub HMCCU_ExecuteGetDeviceInfoCommand ($@);
sub HMCCU_ExecuteGetParameterCommand ($@);
sub HMCCU_ExecuteSetClearCommand ($@);
sub HMCCU_ExecuteSetControlCommand ($@);
sub HMCCU_ExecuteSetDatapointCommand ($@);
sub HMCCU_ExecuteSetParameterCommand ($@);
sub HMCCU_ExecuteGetExtValuesCommand ($@);
sub HMCCU_DisplayGetParameterResult ($$$);
sub HMCCU_DisplayWeekProgram ($$$;$$);
sub HMCCU_ExistsDeviceModel ($$$;$);
sub HMCCU_FindParamDef ($$$);
sub HMCCU_FormatDeviceInfo ($);
sub HMCCU_FormatHashTable ($);
sub HMCCU_GetAddress ($$;$$);
sub HMCCU_GetAffectedAddresses ($);
sub HMCCU_GetCCUDeviceParam ($$);
sub HMCCU_GetChannelName ($$;$);
sub HMCCU_GetChannelRole ($;$);
sub HMCCU_GetDeviceRoles ($$$;$);
sub HMCCU_GetClientDeviceModel ($;$);
sub HMCCU_GetDefaultInterface ($);
sub HMCCU_GetDeviceAddresses ($;$$);
sub HMCCU_GetDeviceConfig ($);
sub HMCCU_GetDeviceDesc ($$;$);
sub HMCCU_GetDeviceIdentifier ($$;$$);
sub HMCCU_GetDeviceInfo ($$;$);
sub HMCCU_GetDeviceInterface ($$;$);
sub HMCCU_GetInterfaceList ($);
sub HMCCU_GetDeviceList ($);
sub HMCCU_GetDeviceModel ($$$;$);
sub HMCCU_GetDeviceName ($$;$);
sub HMCCU_GetDeviceType ($$$);
sub HMCCU_GetParamDef ($$$;$);
sub HMCCU_GetReceivers ($$$);
sub HMCCU_IsValidChannel ($$$);
sub HMCCU_IsValidDevice ($$$);
sub HMCCU_IsValidDeviceOrChannel ($$$);
sub HMCCU_IsValidParameter ($$$$;$);
sub HMCCU_IsValidReceiver ($$$$);
sub HMCCU_ParamsetDescToStr ($$);
sub HMCCU_RemoveDevice ($$$;$);
sub HMCCU_RenameDevice ($$$);
sub HMCCU_ResetDeviceTables ($;$$);
sub HMCCU_SetSCAttributes ($$;$);
sub HMCCU_UpdateDevice ($$);
sub HMCCU_UpdateDeviceRoles ($$;$$);
sub HMCCU_UpdateDeviceTable ($$);
sub HMCCU_UpdateRoleCommands ($$);

# Handle datapoints
sub HMCCU_GetSCDatapoints ($);
sub HMCCU_SetSCDatapoints ($$;$$$);
sub HMCCU_GetStateValues ($;$$);
sub HMCCU_SetInitialAttributes ($$;$);
sub HMCCU_SetDefaultAttributes ($;$);
sub HMCCU_SetMultipleDatapoints ($$);
sub HMCCU_SetMultipleParameters ($$$;$);

# Homematic script and variable functions
sub HMCCU_GetVariables ($$);
sub HMCCU_HMCommand ($$$);
sub HMCCU_HMCommandNB ($$$);
sub HMCCU_HMScriptExt ($$;$$$);
sub HMCCU_SetVariable ($$$$$);
sub HMCCU_UpdateVariables ($);

# Helper functions
sub HMCCU_BitsToStr ($$);
sub HMCCU_BuildURL ($$);
sub HMCCU_CalculateReading ($$);
sub HMCCU_CorrectName ($);
sub HMCCU_Encrypt ($);
sub HMCCU_Decrypt ($);
sub HMCCU_DefStr ($;$$);
sub HMCCU_DeleteReadings ($;$);
sub HMCCU_EncodeEPDisplay ($);
sub HMCCU_ExprMatch ($$$);
sub HMCCU_ExprNotMatch ($$$);
sub HMCCU_FlagsToStr ($$$;$$);
sub HMCCU_GetDeviceStates ($);
sub HMCCU_GetDutyCycle ($);
sub HMCCU_GetHMState ($$;$);
sub HMCCU_GetIdFromIP ($$);
sub HMCCU_GetTimeSpec ($);
sub HMCCU_IsFltNum ($;$);
sub HMCCU_IsIntNum ($);
sub HMCCU_ISO2UTF ($);
sub HMCCU_Max ($$);
sub HMCCU_MaxHashEntries ($$);
sub HMCCU_Min ($$);
sub HMCCU_MinMax ($$$);
sub HMCCU_RefToString ($;$);
sub HMCCU_ResolveName ($$);
sub HMCCU_TCPConnect ($$;$);
sub HMCCU_TCPPing ($$$);
sub HMCCU_UpdateReadings ($$;$);

##################################################
# Initialize module
##################################################

sub HMCCU_Initialize ($)
{
	my ($hash) = @_;

	$hash->{version} = $HMCCU_VERSION;

	$hash->{DefFn}             = 'HMCCU_Define';
	$hash->{UndefFn}           = 'HMCCU_Undef';
	$hash->{RenameFn}          = 'HMCCU_Rename';
	$hash->{SetFn}             = 'HMCCU_Set';
	$hash->{GetFn}             = 'HMCCU_Get';
	$hash->{ReadFn}            = 'HMCCU_Read';
	$hash->{AttrFn}            = 'HMCCU_Attr';
	$hash->{NotifyFn}          = 'HMCCU_Notify';
	$hash->{ShutdownFn}        = 'HMCCU_Shutdown';
	$hash->{DelayedShutdownFn} = 'HMCCU_DelayedShutdown';
	$hash->{FW_detailFn}       = 'HMCCU_Detail';
	$hash->{parseParams} = 1;

	$hash->{AttrList} = 'stripchar stripnumber ccuaggregate:textField-long'.
		' ccudefaults createDeviceGroup'.
		' ccudef-hmstatevals:textField-long ccudef-substitute:textField-long'.
		' ccudef-readingformat:name,namelc,address,addresslc,datapoint,datapointlc'.
		' ccudef-stripnumber ccudef-attributes ccuReadingPrefix'.
		' ccuflags:multiple-strict,procrpc,dptnocheck,logCommand,noagg,nohmstate,'.
		'logEvents,noEvents,noInitialUpdate,noReadings,nonBlocking,reconnect,logPong,trace,logEnhanced,'.
		'noAutoDetect,noAutoSubstitute'.
		' ccuReqTimeout ccuGetVars rpcPingCCU rpcinterfaces ccuAdminURLs'.
		' rpcserver:on,off rpcserveraddr rpcserverport rpctimeout rpcevtimeout substitute'.
		' ccuget:Value,State devCommand '.
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCU_Define ($$$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $usage = "Usage: define $name HMCCU {NameOrIP} [{ccunum}] [nosync] [ccudelay={time}] [waitforccu={time}] [delayedinit={time}]";

	return $usage if (scalar(@$a) < 3);

	# Setup http or ssl connection	
	if ($$a[2] =~ /^(https?):\/\/(.+)/) {
		$hash->{prot} = $1;
		$hash->{host} = $2;
	}
	else {
		$hash->{prot} = 'http';
		$hash->{host} = $$a[2];
	}

	$hash->{Clients} = ':HMCCUDEV:HMCCUCHN:HMCCURPCPROC:';
	$hash->{hmccu}{ccu}{delay}   = $h->{ccudelay}   // $HMCCU_CCU_BOOT_DELAY;
	$hash->{hmccu}{ccu}{timeout} = $h->{waitforccu} // $HMCCU_CCU_PING_TIMEOUT;
	$hash->{hmccu}{ccu}{delayed} = 0;
	$hash->{hmccu}{ccu}{sync}    = 1;
	
	if (exists($h->{delayedinit}) && $h->{delayedinit} > 0) {
		if (!$init_done) {
			# Forced delayed initialization
			return "Value for delayed initialization must be greater than $HMCCU_CCU_DELAYED_INIT"
				if ($h->{delayedinit} <= $HMCCU_CCU_DELAYED_INIT);
			$hash->{hmccu}{ccu}{delay} = $h->{delayedinit};
			$hash->{ccustate} = 'unreachable';
			HMCCU_Log ($hash, 1, 'Forced delayed initialization');
		}
		else {
			HMCCU_LogDisplay ($hash, 2, 'Forced delayed initialization is done during FHEM start');
		}
	}
	else {
		# Check if TCL-Rega process is running on CCU (CCU is reachable)
		if (HMCCU_TCPPing ($hash->{host}, $HMCCU_REGA_PORT{$hash->{prot}}, $hash->{hmccu}{ccu}{timeout})) {
			$hash->{ccustate} = 'active';
			HMCCU_Log ($hash, 1, 'CCU port '.$HMCCU_REGA_PORT{$hash->{prot}}.' is reachable');
		}
		else {
			$hash->{ccustate} = 'unreachable';
			HMCCU_LogDisplay ($hash, 1, 'CCU port '.$HMCCU_REGA_PORT{$hash->{prot}}.' is not reachable');
		}
	}

	# Get CCU IP address
	$hash->{ccuip} = HMCCU_ResolveName ($hash->{host}, 'N/A');

	# Parse optional command line parameters
	for (my $i=3; $i<scalar(@$a); $i++) {
		if (HMCCU_IsIntNum ($$a[$i])) {
			return 'CCU number must be in range 1-9' if ($$a[$i] < 1 || $$a[$i] > 9);
			$hash->{CCUNum} = $$a[$i];
		}
		elsif (lc($$a[$i]) eq 'nosync') {
			$hash->{hmccu}{ccu}{sync} = 0;
		}
		else {
			return $usage;
		}
	}
	
	# Get CCU number (if there is more than one)
	if (!exists($hash->{CCUNum})) {
		# Count CCU devices
		$hash->{CCUNum} = 1;
		foreach my $d (keys %defs) {
			my $ch = $defs{$d};
			$hash->{CCUNum}++ if (exists($ch->{TYPE}) && $ch->{TYPE} eq 'HMCCU' && $ch != $hash);
		}
	}

	$hash->{version}         = $HMCCU_VERSION;
	$hash->{config}          = $HMCCU_CONFIG_VERSION;
	$hash->{ccutype}         = 'CCU2/3';
	$hash->{RPCState}        = 'inactive';
	$hash->{NOTIFYDEV}       = 'global';
	$hash->{hmccu}{rpcports} = undef;
	$hash->{hmccu}{postInit} = 0;

	# Check if authentication is active
	my ($username, $password) = HMCCU_GetCredentials ($hash);
	$hash->{authentication} = $username ne '' && $password ne '' ? 'on' : 'off';

	$hash->{json} = HMCCU_JSONLogin ($hash) ? 'on' : 'off';

	HMCCU_Log ($hash, 1, "Initialized version $HMCCU_VERSION");
	
	my $rc = 0;
	if ($hash->{ccustate} eq 'active') {
		# If CCU is alive read devices, channels, interfaces and groups
		HMCCU_Log ($hash, 1, 'Initializing device');
		$rc = HMCCU_InitDevice ($hash);
	}
	
	if (($hash->{ccustate} ne 'active' || $rc > 0) && !$init_done) {
		# Schedule later update of CCU assets if CCU is not active during FHEM startup
		$hash->{hmccu}{ccu}{delayed} = 1;
	}
	
	$hash->{hmccu}{$_} = 0 for ('evtime', 'evtimeout', 'updatetime', 'rpccount', 'defaults');

	HMCCU_UpdateReadings ($hash, { 'state' => 'Initialized', 'rpcstate' => 'inactive' });

	if ($init_done) {
		# Set default attributes
		$attr{$name}{stateFormat} = 'rpcstate/state';
		$attr{$name}{room}        = 'Homematic';
	}
	
	return undef;
}

######################################################################
# Initialization of FHEM device.
# Called during Define() or by HMCCU after CCU ready.
# Return 0 on successful initialization or >0 on error:
# 1 = CCU port 8181 or 48181 is not reachable.
# 2 = Error while reading device list from CCU.
######################################################################

sub HMCCU_InitDevice ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $host = $hash->{host};

	if (HMCCU_IsDelayedInit ($hash)) {
		HMCCU_Log ($hash, 1, 'Delayed I/O device initialization');
		if (!HMCCU_TCPPing ($host, $HMCCU_REGA_PORT{$hash->{prot}}, $hash->{hmccu}{ccu}{timeout})) {
			$hash->{ccustate} = 'unreachable';
			return HMCCU_Log ($hash, 1, "CCU port ".$HMCCU_REGA_PORT{$hash->{prot}}." is not reachable", 1);
		}
		else {
			$hash->{ccustate} = 'active';
		}
	}

	my ($devcnt, $chncnt, $ifcount, $prgcount, $gcount) = HMCCU_GetDeviceList ($hash);
	if ($ifcount > 0) {
		my $rpcinterfaces = 'rpcinterfaces:multiple-strict,'.$hash->{ccuinterfaces};
		my $attributes = $modules{HMCCU}{AttrList};
		$attributes =~ s/rpcinterfaces/$rpcinterfaces/;
		setDevAttrList ($name, $attributes);

		HMCCU_Log ($hash, 1, "Read $devcnt devices with $chncnt channels, $prgcount programs, $gcount virtual groups from CCU $host");
		
		# Interactive device definition or delayed initialization
		if ($init_done && !HMCCU_IsDelayedInit ($hash)) {
			# Force sync with CCU during interactive device definition
			if ($hash->{hmccu}{ccu}{sync} == 1) {
 				HMCCU_LogDisplay ($hash, 1, 'Reading device config from CCU. This may take a couple of seconds ...');
				my ($cDev, $cPar, $cLnk) = HMCCU_GetDeviceConfig ($hash);
				HMCCU_Log ($hash, 2, "Read RPC device configuration: devices/channels=$cDev parametersets=$cPar links=$cLnk");
			}
		}

		return 0;
	}
	else {
		return HMCCU_Log ($hash, 1, "No RPC interfaces found on CCU $host", 2);
	}
}

######################################################################
# Tasks to be executed after all devices have been defined. Executed 
# as timer function after FHEM has been initialized and startup is
# complete.
#   Read device configuration from CCU
#   Start RPC servers
######################################################################

sub HMCCU_PostInit ($)
{
	my ($hash) = @_;
	
	my $host = $hash->{host};
	$hash->{hmccu}{postInit} = 1;

	if (HMCCU_IsDelayedInit ($hash)) {
		if (HMCCU_InitDevice ($hash) > 0) {
			$hash->{hmccu}{postInit} = 0;
			return;
		}
	}

	if ($hash->{ccustate} eq 'active') {
		my $rpcServer = AttrVal ($hash->{NAME}, 'rpcserver', 'off');

		HMCCU_Log ($hash, 1, 'Reading device config from CCU. This may take a couple of seconds ...');
		my $ts = time();
		my ($cDev, $cPar, $cLnk) = HMCCU_GetDeviceConfig ($hash);
		$ts = time()-$ts;
		HMCCU_Log ($hash, 2, "Read device configuration in $ts seconds: devices/channels=$cDev parametersets=$cPar links=$cLnk");
		
		HMCCU_StartExtRPCServer ($hash) if ($rpcServer eq 'on');
	}
	else {
		HMCCU_Log ($hash, 1, 'CCU not active. Post FHEM start initialization failed');
	}

	$hash->{hmccu}{postInit} = 0;
}

######################################################################
# Check for delayed initialization
######################################################################

sub HMCCU_IsDelayedInit ($)
{
	my ($ioHash) = @_;

	return exists($ioHash->{hmccu}{ccu}{delayed}) && exists($ioHash->{hmccu}{ccu}{delay}) &&
		$ioHash->{hmccu}{ccu}{delayed} == 1 && $ioHash->{hmccu}{ccu}{delay} > 0 ? 1 : 0;
}

######################################################################
# Set or delete attribute
######################################################################

sub HMCCU_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};
	my $rc = 0;

	if ($cmd eq 'set') {
		if ($attrname eq 'ccudefaults') {
			$rc = HMCCU_ImportDefaults ($attrval);
			return HMCCU_SetError ($hash, -16) if ($rc == 0);
			return HMCCU_SetError ($hash, 'Syntax error in default attribute file $attrval line '.(-$rc))
				if ($rc < 0);
		}
		elsif ($attrname eq 'ccuaggregate') {
			$rc = HMCCU_AggregationRules ($hash, $attrval);
			return HMCCU_SetError ($hash, 'Syntax error in attribute ccuaggregate') if ($rc == 0);
		}
		elsif ($attrname eq 'ccuackstate') {
			return "HMCCU: [$name] Attribute ccuackstate is depricated. Use ccuflags with 'ackState' instead";
		}
		elsif ($attrname eq 'ccureadings') {
			return "HMCCU: [$name] Attribute ccureadings is depricated. Use ccuflags with 'noReadings' instead";
		}
		elsif ($attrname eq 'ccuflags') {
			my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
			if ($attrval =~ /(intrpc|extrpc)/) {
				HMCCU_Log ($hash, 1, "RPC server mode $1 no longer supported. Using procrpc instead");
				$attrval =~ s/(extrpc|intrpc)/procrpc/;
				$_[3] = $attrval;
			}
		}
		elsif ($attrname eq 'ccuGetVars') {
			my ($interval, $pattern) = split /:/, $attrval;
			$interval = 60 if (!defined($interval) || $interval eq '');
			$pattern = '.*' if (!defined($pattern) || $pattern eq '');
			return "HMCCU: [$name] Interval is not numeric for attribute ccuGetVars" if (!HMCCU_IsIntNum($interval));
			$hash->{hmccu}{ccuvarspat} = $pattern;
			$hash->{hmccu}{ccuvarsint} = $interval;
			RemoveInternalTimer ($hash, 'HMCCU_UpdateVariables');
			if ($interval > 0) {
				HMCCU_Log ($hash, 2, "Updating CCU system variables matching $pattern every $interval seconds");
				InternalTimer (gettimeofday()+$interval, 'HMCCU_UpdateVariables', $hash);
			}
		}
		elsif ($attrname eq 'eventMap') {
			my @av = map { $_ =~ /^rpcserver (on|off):(on|off)$/ || $_ eq '' ? () : $_ } split (/\//, $attrval);
			if (scalar(@av) > 0) {
				$_[3] = '/'.join('/',@av).'/';
				HMCCU_Log ($hash, 2, "Removed rpcserver entries from attribute eventMap");
			}
			else {
				# Workaround because FHEM is ignoring error values for attribute eventMap
				delete $attr{$name}{eventMap} if (exists($attr{$name}{eventMap}));
				return "HMCCU: [$name] Ignored attribute eventMap because it contains only obsolet rpcserver entries";
			}
		}
		elsif ($attrname eq 'rpcdevice') {
			return "HMCCU: [$name] Attribute rpcdevice is depricated. Please remove it";
		}
		elsif ($attrname eq 'rpcport') {
			return "HMCCU: [$name] Attribute rpcport is no longer supported. Use rpcinterfaces instead";
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'ccuaggregate') {
			HMCCU_AggregationRules ($hash, '');
		}
		elsif ($attrname eq 'ccuGetVars') {
			RemoveInternalTimer ($hash, "HMCCU_UpdateVariables");
		}
	}
	
	return undef;
}

######################################################################
# Parse aggregation rules for readings.
# Syntax of aggregation rule is:
# FilterSpec[;...]
# FilterSpec := {Name|Filt|Read|Cond|Else|Pref|Coll|Html}[,...]
# Name := name:Name
# Filt := filter:{name|type|group|room|alias}=Regexp[!Regexp]
# Read := read:Regexp
# Cond := if:{any|all|min|max|sum|avg|gt|lt|ge|le}=Value
# Else := else:Value
# Pref := prefix:{RULE|Prefix}
# Coll := coll:{NAME|Attribute}
# Html := html:Template
######################################################################

sub HMCCU_AggregationRules ($$)
{
	my ($hash, $rulestr) = @_;
	my $name = $hash->{NAME};

	# Delete existing aggregation rules
	if (exists($hash->{hmccu}{agg})) { delete $hash->{hmccu}{agg}; }
	return if ($rulestr eq '');
	
	my @pars = ('name', 'filter', 'if', 'else');

	# Extract aggregation rules
	my $cnt = 0;
	foreach my $r (split(/[;\n]+/, $rulestr)) {
		$cnt++;
		
		# Set default rule parameters. Can be modified later
		my %opt = ('read' => 'state', 'prefix' => 'RULE', 'coll' => 'NAME');

		# Parse aggregation rule
		foreach my $spec (split(',', $r)) {
			if ($spec =~ /^(name|filter|read|if|else|prefix|coll|html):(.+)$/) { $opt{$1} = $2; }
		}
		
		# Check if mandatory parameters are specified
		foreach my $p (@pars) {
			return HMCCU_Log ($hash, 1, "Parameter $p is missing in aggregation rule $cnt.", 0)
				if (!exists($opt{$p}));
		}
		
		my $fname = $opt{name};
		my ($fincl, $fexcl) = split ('!', $opt{filter});
		my ($ftype, $fexpr) = split ('=', $fincl);
		my ($fcond, $fval)  = split ('=', $opt{if});
		my ($fcoll, $fdflt) = split ('!', $opt{coll});
		return 0 if (!defined($fexpr) || !defined($fval));
		$fdflt //= 'no match';
		my $fhtml = exists($opt{'html'}) ? $opt{'html'} : '';
		
		# Read HTML template (optional)
		if ($fhtml ne '') {
			my %tdef;
			my @html;
			
			# Read template file
			if (open (TEMPLATE, "<$fhtml")) {
				@html = <TEMPLATE>;
				close (TEMPLATE);
			}
			else {
				return HMCCU_Log ($hash, 1, "Can't open file $fhtml.", 0);
			}

			# Parse template
			foreach my $line (@html) {
				chomp $line;
				my ($key, $h) = split /:/, $line, 2;
				$tdef{$key} = $h if (defined($h) && $key !~ /^#/);
			}

			# Some syntax checks
			return HMCCU_Log ($hash, 1, 'Missing definition row-odd in template file.', 0)
				if (!exists($tdef{'row-odd'}));

			# Set default values
			$tdef{'begin-html'}  = '' if (!exists($tdef{'begin-html'}));
			$tdef{'end-html'}    = '' if (!exists($tdef{'end-html'}));
			$tdef{'begin-table'} = "<table>" if (!exists($tdef{'begin-table'}));
			$tdef{'end-table'}   = "</table>" if (!exists($tdef{'end-table'}));
			$tdef{'default'}     = 'no data' if (!exists($tdef{'default'}));;
			$tdef{'row-even'}    = $tdef{'row-odd'} if (!exists($tdef{'row-even'}));
			
			foreach my $t (keys %tdef) {
				$hash->{hmccu}{agg}{$fname}{fhtml}{$t} = $tdef{$t};
			}
		}

		$hash->{hmccu}{agg}{$fname}{ftype} = $ftype;
		$hash->{hmccu}{agg}{$fname}{fexpr} = $fexpr;
		$hash->{hmccu}{agg}{$fname}{fexcl} = (defined($fexcl) ? $fexcl : '');
		$hash->{hmccu}{agg}{$fname}{fread} = $opt{'read'};
		$hash->{hmccu}{agg}{$fname}{fcond} = $fcond;
		$hash->{hmccu}{agg}{$fname}{ftrue} = $fval;
		$hash->{hmccu}{agg}{$fname}{felse} = $opt{'else'};
		$hash->{hmccu}{agg}{$fname}{fpref} = $opt{prefix} eq 'RULE' ? $fname : $opt{prefix};
		$hash->{hmccu}{agg}{$fname}{fcoll} = $fcoll;
		$hash->{hmccu}{agg}{$fname}{fdflt} = $fdflt;
	}

	return 1;
}

######################################################################
# Export default attributes.
######################################################################

sub HMCCU_ExportDefaults ($$)
{
	my ($filename, $all) = @_;

	return 0 if (!open (DEFFILE, ">$filename"));

	print DEFFILE "# HMCCU default attributes for channels\n";
	foreach my $t (keys %{$HMCCU_CHN_DEFAULTS}) {
		print DEFFILE "\nchannel:$t\n";
		foreach my $a (sort keys %{$HMCCU_CHN_DEFAULTS->{$t}}) {
			print DEFFILE "$a=".$HMCCU_CHN_DEFAULTS->{$t}{$a}."\n";
		}
	}

	print DEFFILE "\n# HMCCU default attributes for devices\n";
	foreach my $t (keys %{$HMCCU_DEV_DEFAULTS}) {
		print DEFFILE "\ndevice:$t\n";
		foreach my $a (sort keys %{$HMCCU_DEV_DEFAULTS->{$t}}) {
			print DEFFILE "$a=".$HMCCU_DEV_DEFAULTS->{$t}{$a}."\n";
		}
	}
	
	if ($all) {
		print DEFFILE "# HMCCU custom default attributes for channels\n";
		foreach my $t (keys %HMCCU_CUST_CHN_DEFAULTS) {
			print DEFFILE "\nchannel:$t\n";
			foreach my $a (sort keys %{$HMCCU_CUST_CHN_DEFAULTS{$t}}) {
				print DEFFILE "$a=".$HMCCU_CUST_CHN_DEFAULTS{$t}{$a}."\n";
			}
		}

		print DEFFILE "\n# HMCCU custom default attributes for devices\n";
		foreach my $t (keys %HMCCU_CUST_DEV_DEFAULTS) {
			print DEFFILE "\ndevice:$t\n";
			foreach my $a (sort keys %{$HMCCU_CUST_DEV_DEFAULTS{$t}}) {
				print DEFFILE "$a=".$HMCCU_CUST_DEV_DEFAULTS{$t}{$a}."\n";
			}
		}
	}

	close (DEFFILE);

	return 1;
}

######################################################################
# Import customer default attributes
# Returns 1 on success. Returns negative line number on syntax errors.
# Returns 0 on file open error.
######################################################################
 
sub HMCCU_ImportDefaults ($)
{
	my ($filename) = @_;
	my $modtype = '';
	my $ccutype = '';
	my $line = 0;

	return 0 if (!open (DEFFILE, "<$filename"));
	my @defaults = <DEFFILE>;
	close (DEFFILE);
	chomp (@defaults);

	%HMCCU_CUST_CHN_DEFAULTS = ();
	%HMCCU_CUST_DEV_DEFAULTS = ();
	
	foreach my $d (@defaults) {
		$line++;
		next if ($d eq '' || $d =~ /^#/);

		if ($d =~ /^(channel|device):/) {
			my @t = split (':', $d, 2);
			if (scalar (@t) != 2) {
				close (DEFFILE);
				return -$line;
			}
			$modtype = $t[0];
			$ccutype = $t[1];
			next;
		}

		if ($ccutype eq '' || $modtype eq '') {
			close (DEFFILE);
			return -$line;
		}

		my @av = split ('=', $d, 2);
		if (scalar (@av) != 2) {
			close (DEFFILE);
			return -$line;
		}

		if ($modtype eq 'channel') {
			$HMCCU_CUST_CHN_DEFAULTS{$ccutype}{$av[0]} = $av[1];
		}
		else {
			$HMCCU_CUST_DEV_DEFAULTS{$ccutype}{$av[0]} = $av[1];
		}
	}

	return 1;
}

######################################################################
# Find default attributes
# Return template reference or undef if no defaults were found.
######################################################################

sub HMCCU_FindDefaults ($)
{
	my ($hash) = @_;
	my $type = $hash->{TYPE};
	my $ccutype = $hash->{ccutype};

	if ($type eq 'HMCCUCHN') {
		my ($adr, $chn) = split (':', $hash->{ccuaddr});

		foreach my $deftype (keys %HMCCU_CUST_CHN_DEFAULTS) {
			my @chnlst = split (',', $HMCCU_CUST_CHN_DEFAULTS{$deftype}{_channels});
			return \%{$HMCCU_CUST_CHN_DEFAULTS{$deftype}}
				if ($ccutype =~ /^($deftype)$/i && grep { $_ eq $chn} @chnlst);
		}
		
		foreach my $deftype (keys %{$HMCCU_CHN_DEFAULTS}) {
			my @chnlst = split (',', $HMCCU_CHN_DEFAULTS->{$deftype}{_channels});
			return \%{$HMCCU_CHN_DEFAULTS->{$deftype}}
				if ($ccutype =~ /^($deftype)$/i && grep { $_ eq $chn} @chnlst);
		}
	}
	elsif ($type eq 'HMCCUDEV' || $type eq 'HMCCU') {
		foreach my $deftype (keys %HMCCU_CUST_DEV_DEFAULTS) {
			return \%{$HMCCU_CUST_DEV_DEFAULTS{$deftype}} if ($ccutype =~ /^($deftype)$/i);
		}

		foreach my $deftype (keys %{$HMCCU_DEV_DEFAULTS}) {
			return \%{$HMCCU_DEV_DEFAULTS->{$deftype}} if ($ccutype =~ /^($deftype)$/i);
		}
	}

	return undef;	
}

######################################################################
# Set default attributes from template
######################################################################

sub HMCCU_SetDefaultsTemplate ($$)
{
	my ($hash, $template) = @_;
	my $name = $hash->{NAME};
	
	foreach my $a (keys %{$template}) {
		next if ($a =~ /^_/);
		my $v = $template->{$a};
		CommandAttr (undef, "$name $a $v");
	}
}

######################################################################
# Set default attributes
######################################################################

sub HMCCU_SetDefaults ($)
{
	my ($hash) = @_;

	# Set type specific attributes	
	my $template = HMCCU_FindDefaults ($hash) // return 0;
	
	HMCCU_SetDefaultsTemplate ($hash, $template);
	return 1;
}

######################################################################
# List default attributes for device type (mode = 0) or all
# device types (mode = 1) with default attributes available.
######################################################################

sub HMCCU_GetDefaults ($;$)
{
	my ($hash, $mode) = @_;
	$mode //= 0;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $ccutype = $hash->{ccutype};
	my $result = '';
	my $deffile = '';
	
	if ($mode == 0) {
		if (exists($hash->{ccurolectrl}) && exists($HMCCU_STATECONTROL->{$hash->{ccurolectrl}})) {
			$result .= "Support for role $hash->{ccurolectrl} of device type $ccutype is built in.";
		}
		elsif (exists($hash->{ccurolestate}) && exists($HMCCU_STATECONTROL->{$hash->{ccurolestate}})) {
			$result .= "Support for role $hash->{ccurolestate} of device type $ccutype is built in.";
		}
		elsif (exists($hash->{hmccu}{role})) {
			my @roleList = ();
			foreach my $role (split(',', $hash->{hmccu}{role})) {
				my ($rChn, $rNam) = split(':', $role);
				push @roleList, $rNam if (exists($HMCCU_STATECONTROL->{$rNam}));
			}
			$result .= 'Support for role(s) '.join(',', @roleList)." of device type $ccutype is built in."
				if (scalar(@roleList) > 0);
		}
		else {
			my $template = HMCCU_FindDefaults ($hash);
			return ($result eq '' ? 'No default attributes defined' : $result) if (!defined($template));
	
			foreach my $a (keys %{$template}) {
				next if ($a =~ /^_/);
				my $v = $template->{$a};
				$result .= $a." = ".$v."\n";
			}
		}
	}
	else {
		$result = "HMCCU Channels:\n".('-' x 30)."\n";
		foreach my $deftype (sort keys %{$HMCCU_CHN_DEFAULTS}) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_CHN_DEFAULTS->{$deftype}{_description}." ($tlist), channels ".
				$HMCCU_CHN_DEFAULTS->{$deftype}{_channels}."\n";
		}
		$result .= "\nHMCCU Devices:\n".('-' x 30)."\n";
		foreach my $deftype (sort keys %{$HMCCU_DEV_DEFAULTS}) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_DEV_DEFAULTS->{$deftype}{_description}." ($tlist)\n";
		}
		$result .= "\nCustom Channels:\n".('-' x 30)."\n";
		foreach my $deftype (sort keys %HMCCU_CUST_CHN_DEFAULTS) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_CUST_CHN_DEFAULTS{$deftype}{_description}." ($tlist), channels ".
				$HMCCU_CUST_CHN_DEFAULTS{$deftype}{_channels}."\n";
		}
		$result .= "\nCustom Devices:\n".('-' x 30)."\n";
		foreach my $deftype (sort keys %HMCCU_CUST_DEV_DEFAULTS) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_CUST_DEV_DEFAULTS{$deftype}{_description}." ($tlist)\n";
		}
	}
	
	return $result;	
}

######################################################################
# Handle FHEM events
######################################################################

sub HMCCU_Notify ($$)
{
	my ($hash, $devhash) = @_;
	my $name = $hash->{NAME};
	my $devname = $devhash->{NAME};
	my $devtype = $devhash->{TYPE};

#	return if (!HMCCU_IsDeviceActive ($hash));

	my $events = deviceEvents ($devhash, 1);
	return if (!$events);
	
	# Process events
	foreach my $event (@{$events}) {	
		if ($devname eq 'global') {
			# Global event
			if ($event eq 'INITIALIZED') {
				# FHEM initialized. Schedule post initialization tasks
				my $delay = $hash->{ccustate} eq 'active' && !HMCCU_IsDelayedInit ($hash) ?
					$HMCCU_INIT_INTERVAL0 : $hash->{hmccu}{ccu}{delay}+$HMCCU_CCU_RPC_OFFSET;
				HMCCU_Log ($hash, 0, "Scheduling post FHEM initialization tasks in $delay seconds");
				InternalTimer (gettimeofday()+$delay, "HMCCU_PostInit", $hash, 0);
			}
			elsif ($event =~ /^(ATTR|DELETEATTR)/ && $init_done) {
				my ($aCmd, $aDev, $aAtt, $aVal) = split (/\s+/, $event);
#				$aAtt = $aVal if ($aCmd eq 'DELETEATTR');
				if (defined($aAtt)) {
					my $clHash = $defs{$aDev};
					# Consider attr event only for HMCCUCHN or HMCCUDEV devices assigned to current IO device
					my $setDefaults = $clHash->{hmccu}{setDefaults} // 0;
					HMCCU_RefreshReadings ($clHash, $aAtt)
						if (defined($clHash->{TYPE}) && ($clHash->{TYPE} eq 'HMCCUCHN' || $clHash->{TYPE} eq 'HMCCUDEV') &&
							defined($clHash->{IODev}) && $clHash->{IODev} == $hash && $setDefaults == 0);
				}
			}
		}
	}

	return;
}

######################################################################
# Enhance device details in FHEM web view
# URls can be modified by attribute ccuAdminURLs. Example:
# ccu=URL cuxd=URL
######################################################################

sub HMCCU_Detail ($$$$)
{
	my ($FW_Name, $Device, $Room, $pageHash) = @_;
	my $hash = $defs{$Device};

	my $links = '';
	my %url;

	if (defined($hash->{host})) {
		$url{ccu} = "$hash->{prot}://$hash->{host}";
		$url{cuxd} = "$hash->{prot}://$hash->{host}" if (exists($hash->{hmccu}{interfaces}{CUxD}));
	}

	my $ccuAdminURLs = AttrVal ($Device, 'ccuAdminURLs', '');
	if ($ccuAdminURLs ne '') {
		foreach my $u (split(' ',$ccuAdminURLs)) {
			my ($k, $v) = split('=',$u);
			$url{$k} = $v if ($k eq 'cuxd' || $k eq 'ccu');
		}
	}

	my $c = scalar(keys %url);

	if ($c > 0) {
		$links .= qq(
<span class='mkTitle'>CCU Administration</span>
<table class="block wide">
		);
	}

	if  (exists($url{ccu})) {
		$links .= qq(
<tr class="odd">
<td><div class="col1">
&gt; <a target="_blank" href="$url{ccu}">CCU WebUI</a>
</div></td>
</tr>
		);
	}

	if (exists($url{cuxd})) {
		$links .= qq(
<tr class="odd">
<td><div class="col1">
&gt; <a target="_blank" href="$url{cuxd}/addons/cuxd/index.ccc">CUxD Config</a>
</div></td>
</tr>
		);
	}

	if ($c > 0) {
		$links .= '</table>';
	}

	return $links;
}

sub HMCCU_IsAggregation ($)
{
	my ($ioHash) = @_;

	return (HMCCU_IsFlag ($ioHash->{NAME}, 'noagg') || AttrVal ($ioHash->{NAME}, 'ccuaggregate', '') eq '') ? 0 : 1;
}

######################################################################
# Calculate reading aggregations
######################################################################

sub HMCCU_AggregateReadings ($)
{
	my ($clHash) = @_;

	my $ioHash = HMCCU_GetHash ($clHash);
	return if (!defined($ioHash) || !exists($clHash->{hmccu}{updateReadings}) || !HMCCU_IsAggregation ($ioHash));

	my $name = $clHash->{NAME};

	foreach my $r (keys %{$clHash->{hmccu}{updateReadings}}) {
		foreach my $rule (keys %{$ioHash->{hmccu}{agg}}) {
			my $ftype = $ioHash->{hmccu}{agg}{$rule}{ftype};
			my $fexpr = $ioHash->{hmccu}{agg}{$rule}{fexpr};
			my $fread = $ioHash->{hmccu}{agg}{$rule}{fread};
			next if ($r !~ $fread ||
				($ftype eq 'name' && $name !~ /$fexpr/) ||
				($ftype eq 'type' && $clHash->{ccutype} !~ /$fexpr/) ||
				($ftype eq 'group' && AttrVal ($name, 'group', 'null') !~ /$fexpr/) ||
				($ftype eq 'room' && AttrVal ($name, 'room', 'null') !~ /$fexpr/) ||
				($ftype eq 'alias' && AttrVal ($name, 'alias', 'null') !~ /$fexpr/));
		
			HMCCU_AggregateReadingsRule ($ioHash, $rule);
		}
	}

	delete $clHash->{hmccu}{updateReadings};
}

######################################################################
# Calculate reading aggregations by rule.
######################################################################

sub HMCCU_AggregateReadingsRule ($$)
{
	my ($hash, $rule) = @_;
	
	my $dc = 0;
	my $mc = 0;
	my $result = '';
	my $rl = '';
	my $table = '';

	# Get rule parameters
	my $r = $hash->{hmccu}{agg}{$rule};
	my $cnd = $r->{fcond};
	my $tr = $r->{ftrue};

	my $resval;
	$resval = $r->{ftrue} if ($r->{fcond} =~ /^(max|min|sum|avg)$/);
	
	my @devlist = HMCCU_FindClientDevices ($hash, "(HMCCUDEV|HMCCUCHN)");
	foreach my $d (@devlist) {
		my $ch = $defs{$d};
		my $cn = $ch->{NAME};
		my $ct = $ch->{TYPE};
		
		my $fmatch = '';
		if ($r->{ftype} eq 'name')     { $fmatch = $cn // ''; }
		elsif ($r->{ftype} eq 'type')  { $fmatch = $ch->{ccutype} // ''; }
		elsif ($r->{ftype} eq 'group') { $fmatch = AttrVal ($cn, 'group', ''); }
		elsif ($r->{ftype} eq 'room')  { $fmatch = AttrVal ($cn, 'room', ''); }
		elsif ($r->{ftype} eq 'alias') { $fmatch = AttrVal ($cn, 'alias', ''); }
		
		next if ($fmatch eq '' || $fmatch !~ /$r->{fexpr}/ || ($r->{fexcl} ne '' && $fmatch =~ /$r->{fexcl}/));
		
		my $fcoll = $r->{fcoll} eq 'NAME' ? $cn : AttrVal ($cn, $r->{fcoll}, $cn);
		
		# Compare readings
		foreach my $rd (keys %{$ch->{READINGS}}) {
			next if ($rd =~ /^\./ || $rd !~ /$r->{fread}/);
			my $rv = $ch->{READINGS}{$rd}{VAL};
			my $f = 0;
			
			if (($cnd eq 'any' || $cnd eq 'all') && $rv =~ /$tr/) { $mc++; $f = 1; }
			if ($cnd eq 'max' && $rv > $resval)                   { $resval = $rv; $mc = 1; $f = 1; }
			if ($cnd eq 'min' && $rv < $resval)                   { $resval = $rv; $mc = 1; $f = 1; }
			if ($cnd eq 'sum' || $cnd eq 'avg')                   { $resval += $rv; $mc++; $f = 1; }
			if ($cnd =~ /^(gt|lt|ge|le)$/ && (!HMCCU_IsFltNum ($rv) || !HMCCU_IsFltNum($tr))) {
				HMCCU_Log ($hash, 4, "Aggregation value $rv of reading $cn.$r or $tr is not numeric");
				next;
			}
			if (($cnd eq 'gt' && $rv > $tr) || ($cnd eq 'lt' && $rv < $tr) || ($cnd eq 'ge' && $rv >= $tr) || ($cnd eq 'le' && $rv <= $tr)) {
				$mc++; $f = 1;
			}
			if ($f) {
				$rl .= ($mc > 1 ? ",$fcoll" : $fcoll);
				last;
			}
		}
		$dc++;
	}
	
	$rl =  $r->{fdflt} if ($rl eq '');

	# HTML code generation
	if ($r->{fhtml}) {
		if ($rl ne '') {
			$table = $r->{fhtml}{'begin-html'}.$r->{fhtml}{'begin-table'};
			$table .= $r->{fhtml}{'header'} if (exists($r->{fhtml}{'header'}));

			my $row = 1;
			foreach my $v (split (",", $rl)) {
				my $t_row = ($row % 2) ? $r->{fhtml}{'row-odd'} : $r->{fhtml}{'row-even'};
				$t_row =~ s/\<reading\/\>/$v/;
				$table .= $t_row;
				$row++;
			}

			$table .= $r->{fhtml}{'end-table'}.$r->{fhtml}{'end-html'};
		}
		else {
			$table = $r->{fhtml}{'begin-html'}.$r->{fhtml}{'default'}.$r->{fhtml}{'end-html'};
		}
	}

	if ($cnd eq 'any')                { $result = $mc > 0    ? $tr : $r->{felse}; }
	elsif ($cnd eq 'all')             { $result = $mc == $dc ? $tr : $r->{felse}; }
	elsif ($cnd =~ /^(min|max|sum)$/) { $result = $mc > 0    ? $resval     : $r->{felse}; }
	elsif ($cnd eq 'avg')             { $result = $mc > 0    ? $resval/$mc : $r->{felse}; }
	elsif ($cnd =~ /^(gt|lt|ge|le)$/) { $result = $mc; }
	
	HMCCU_UpdateReadings ($hash, { $r->{fpref}.'state' => $result, $r->{fpref}.'match' => $mc,
		$r->{fpref}.'count' => $dc, $r->{fpref}.'list' => $rl });
	readingsSingleUpdate ($hash, $r->{fpref}.'table', $table, 1) if ($r->{fhtml});
	
	return $result;
}

######################################################################
# Delete device
######################################################################

sub HMCCU_Undef ($$)
{
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	# Shutdown RPC server
	HMCCU_Shutdown ($hash);

	my @keylist = keys %defs;
	foreach my $d (@keylist) {
		my $ch = $defs{$d} // next;
		next if (!exists($ch->{TYPE}) || !exists($ch->{IODev}) || $ch->{IODev} != $hash);
		if ($ch->{TYPE} eq 'HMCCUDEV' || $ch->{TYPE} eq 'HMCCUCHN') {
			# Delete reference to IO module in client devices
        	delete $defs{$d}{IODev};
		}
		elsif ($ch->{TYPE} eq 'HMCCURPCPROC') {
			# Delete RPC server devices associated with deleted I/O device
			HMCCU_Log ($hash, 1, "Deleting RPC server device $ch->{NAME}");
			CommandDelete (undef, $ch->{NAME});
		}
	}

	# Delete CCU credentials
	HMCCU_SetCredentials ($hash);
	HMCCU_SetCredentials ($hash, '_json_');

	return undef;
}

######################################################################
# Rename device
######################################################################

sub HMCCU_Rename ($$)
{
	my ($oldName, $newName);

	my ($username, $password) = HMCCU_GetCredentials ($oldName);
	if ($username ne '' && $password ne '') {
		HMCCU_SetCredentials ($oldName);
		HMCCU_SetCredentials ($newName, '_', $username, $password);
	}
	($username, $password) = HMCCU_GetCredentials ($oldName, '_json_');
	if ($username ne '' && $password ne '') {
		HMCCU_SetCredentials ($oldName, '_json_');
		HMCCU_SetCredentials ($newName, '_json_', $username, $password);
	}
}

######################################################################
# Delayed shutdown FHEM
######################################################################

sub HMCCU_DelayedShutdown ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $delay = HMCCU_Max (AttrVal ('global', 'maxShutdownDelay', 10)-2, 0);

	# Shutdown RPC server
	if (!exists($hash->{hmccu}{delayedShutdown})) {
		$hash->{hmccu}{delayedShutdown} = $delay;
		HMCCU_Log ($hash, 1, "Graceful shutdown in $delay seconds");
		HMCCU_StopExtRPCServer ($hash, 0);
	}
	else {
		HMCCU_Log ($hash, 1, 'Graceful shutdown already in progress');
	}
	
	return 1;
}

######################################################################
# Shutdown FHEM
######################################################################

sub HMCCU_Shutdown ($)
{
	my ($hash) = @_;

	# Shutdown RPC server
	if (!exists($hash->{hmccu}{delayedShutdown})) {
		HMCCU_Log ($hash, 1, 'Immediate shutdown');
		HMCCU_StopExtRPCServer ($hash, 0);
	}
	else {
		HMCCU_Log ($hash, 1, 'Graceful shutdown');
	}
		
	# Remove existing timer functions
	RemoveInternalTimer ($hash);

	return undef;
}

######################################################################
# Set commands
######################################################################

sub HMCCU_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a // return 'No set command specified';
	my $options = "var clear delete execute hmscript cleardefaults:noArg datapoint ".
		"importdefaults rpcregister:all ackmessages:noArg authentication ".
		"prgActivate prgDeactivate on:noArg off:noArg";
	$opt = lc($opt);
	
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
	my @ifList = keys %$interfaces;
	if (scalar(@ifList) > 0) {
		my $ifStr = join(',', @ifList);
		$options =~ s/rpcregister:all/rpcregister:all,$ifStr/;
	}
	my $host = $hash->{host};

	$options = 'initialize:noArg' if (HMCCU_IsDelayedInit ($hash) && $hash->{ccustate} eq 'unreachable');
	return 'HMCCU: CCU busy, choose one of rpcserver:off'
		if ($opt ne 'rpcserver' && HMCCU_IsRPCStateBlocking ($hash));

	my $usage = "HMCCU: Unknown argument $opt, choose one of $options";

	my $ccuflags      = HMCCU_GetFlags ($name);
	my $stripchar     = AttrVal ($name, "stripchar", '');
	my $ccureadings   = AttrVal ($name, "ccureadings", $ccuflags =~ /noReadings/ ? 0 : 1);
	my $ccureqtimeout = AttrVal ($name, "ccuReqTimeout", $HMCCU_TIMEOUT_REQUEST);
	my $readingformat = HMCCU_GetAttrReadingFormat ($hash, $hash);
	my $substitute    = HMCCU_GetAttrSubstitute ($hash);
	my $result;

	# Add program names to command execute
	if (exists($hash->{hmccu}{prg})) {
		my @progs = ();
		my @aprogs = ();
		my @iprogs = ();
		foreach my $p (keys %{$hash->{hmccu}{prg}}) {
			if (!exists($hash->{hmccu}{prg}{$p}{internal}) || !exists($hash->{hmccu}{prg}{$p}{active})) {
				HMCCU_Log ($hash, 2, "Information for CCU program $p incomplete");
				next;
			}
			if ($hash->{hmccu}{prg}{$p}{internal} eq 'false' && $p !~ /^\$/) {
				my $pn = $p;
				$pn =~ s/ /#/g;
				push (@progs, $pn);
				push (@aprogs, $pn) if ($hash->{hmccu}{prg}{$p}{active} eq 'true');
				push (@iprogs, $pn) if ($hash->{hmccu}{prg}{$p}{active} eq 'false');
			}
		}
		if (scalar (@progs) > 0) {
			my $prgopt = "execute:".join(',', @progs);
			my $prgact = "prgActivate:".join(',', @iprogs);
			my $prgdac = "prgDeactivate:".join(',', @aprogs);
			$options =~ s/execute/$prgopt/;
			$options =~ s/prgActivate/$prgact/;
			$options =~ s/prgDeactivate/$prgdac/;
			$usage =~ s/execute/$prgopt/;
			$usage =~ s/prgActivate/$prgact/;
			$usage =~ s/prgDeactivate/$prgdac/;
		}
	}
	
	if ($opt eq 'var') {
		$usage = "set $name $opt [{'bool'|'list'|'number'|'text'}] variable value [param=value [...]]";
		my $vartype;
		$vartype = shift @$a if (scalar(@$a) == 3);
		my $objname = shift @$a;
		my $objvalue = shift @$a // return HMCCU_SetError ($hash, $usage);

		$objname =~ s/$stripchar$// if ($stripchar ne '');
		$h->{name} = $objname if (!defined($h) && defined($vartype));
		
		$result = HMCCU_SetVariable ($hash, $objname, $objvalue, $vartype, $h);

		return HMCCU_SetError ($hash, $result) if ($result < 0);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'initialize') {
		return HMCCU_SetError ($hash, 'State of CCU must be unreachable')
			if ($hash->{ccustate} ne 'unreachable');
		my $err = HMCCU_InitDevice ($hash);
		return HMCCU_SetError ($hash, 'CCU not reachable') if ($err == 1);
		return HMCCU_SetError ($hash, "Can't read device list from CCU") if ($err == 2);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'authentication') {
		my $json = 0;
		my $credKey = '_';
		my $credInt = 'authentication';
		my $username = shift @$a;
		if (defined($username) && $username eq 'json') {
			$json = 1;
			$credKey = '_json_';
			$credInt = 'json';
			$username = shift @$a;
		}
		my $password = shift @$a;
		$usage = "set $name $opt ['json'] username password";

		if (!defined($username)) {
			my $err = HMCCU_SetCredentials ($hash, $credKey);
			if (!defined($err)) {
				$hash->{$credInt} = 'off';
				return 'Credentials for CCU authentication deleted';
			}
			else {
				return HMCCU_SetError ($hash, "Can't delete credentials. $err");
			}
		}		
		return HMCCU_SetError ($hash, $usage) if (!defined($password));

		my $err = HMCCU_SetCredentials ($hash, $credKey, $username, $password);
		return HMCCU_SetError ($hash, "Can't store credentials. $err") if (defined($err));

		if ($credInt eq 'json') {
			if (!HMCCU_JSONLogin ($hash)) {
				$hash->{json} = 'off';
				return HMCCU_SetError ($hash, "JSON API login failed");
			}
		}

		$hash->{$credInt} = 'on';
		return 'Credentials for CCU authentication stored';		
	}
	elsif ($opt eq 'clear') {
		my $rnexp = shift @$a;
		HMCCU_DeleteReadings ($hash, $rnexp);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'datapoint') {
		$usage = "set $name $opt [DevSpec] [Device[,...]].[Channel].Datapoint=Value [...]\n";
		my $devSpec = shift @$a;
		
		return HMCCU_SetError ($hash, $usage) if (scalar(keys %$h) < 1);

		my $cmd = 1;
		my %dpValues;
		my @devSpecList = ();
		
		if (defined($devSpec)) {
			@devSpecList = devspec2array ($devSpec);
			return HMCCU_SetError ($hash, "No FHEM device matching $devSpec in command set datapoint")
				if (scalar(@devSpecList) == 0);
		}
		
		foreach my $dptSpec (keys %$h) {
			my $adr;
			my $chn;
			my $dpt;
			my $value = $h->{$dptSpec};
			my @t = split (/\./, $dptSpec);
			
			my @devList = ();
			
			if (scalar(@t) == 3 || (scalar(@t) == 2 && $dptSpec !~ /^[0-9]{1,2}\.(.+)$/)) {
				$devSpec = shift @t;
				@devList = split (',', $devSpec);
			}
			else {
				@devList = @devSpecList;
			}
			my ($t1, $t2) = @t;
			
			foreach my $devName (@devList) {
				my $dh = $defs{$devName};
				my $ccuif = $dh->{ccuif};
				my ($sc, $sd, $cc, $cd, $sdCnt, $cdCnt) = HMCCU_GetSCDatapoints ($dh);
				my $stateVals = HMCCU_GetStateValues ($dh, $cd, $cc);

				if ($dh->{TYPE} eq 'HMCCUCHN') {
					if (defined ($t2)) {
						HMCCU_Log ($hash, 3, "Ignored channel in set datapoint for device $devName");
						$dpt = $t2;
					}
					else {
						$dpt = $t1;
					}
					($adr, $chn) = HMCCU_SplitChnAddr ($dh->{ccuaddr});
				}
				elsif ($dh->{TYPE} eq 'HMCCUDEV') {
					return HMCCU_SetError ($hash, "Missing channel number for device $devName")
						if (!defined ($t2));
					return HMCCU_SetError ($hash, "Invalid channel number specified for device $devName")
						if ($t1 !~ /^[0-9]+$/ || $t1 > $dh->{hmccu}{channels});
					$adr = $dh->{ccuaddr};
					$chn = $t1;
					$dpt = $t2;
				}
				else {
					return HMCCU_SetError ($hash, "FHEM device $devName has illegal type");
				}

				return HMCCU_SetError ($hash, "Invalid datapoint $dpt specified for device $devName")
					if (!HMCCU_IsValidParameter ($dh, HMCCU_GetChannelAddr ($dh, $chn), 'VALUES', $dpt, 2));
				
				$value = HMCCU_Substitute ($value, $stateVals, 1, undef, '')
					if ($stateVals ne '' && "$chn" eq "$cc" && $dpt eq $cd);
				my $no = sprintf ("%03d", $cmd);
				$dpValues{"$no.$ccuif.$devName:$chn.$dpt"} = $value;
				$cmd++;
			}
		}
		
		my $rc = HMCCU_SetMultipleDatapoints ($hash, \%dpValues);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);
		return HMCCU_SetState ($hash, 'OK');		
	}
	elsif ($opt eq 'delete') {
		my $objname = shift @$a;
		my $objtype = shift @$a // 'OT_VARDP';
		$usage = "Usage: set $name $opt ccuobject ['OT_VARDP'|'OT_DEVICE']";

		return HMCCU_SetError ($hash, $usage)
			if (!defined($objname) || $objtype !~ /^(OT_VARDP|OT_DEVICE)$/);
		
		$result = HMCCU_HMScriptExt ($hash, "!DeleteObject", { name => $objname, type => $objtype });

		return HMCCU_SetError ($hash, -2) if ($result =~ /^ERROR:.*/);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'execute') {
		my $program = shift @$a;
		$program .= ' '.join(' ', @$a) if (scalar(@$a) > 0);
		my $response;
		$usage = "Usage: set $name $opt program-name";

		return HMCCU_SetError ($hash, $usage) if (!defined($program));

		my $cmd = qq(dom.GetObject("$program").ProgramExecute());
		my $value = HMCCU_HMCommand ($hash, $cmd, 1);
		
		return HMCCU_SetState ($hash, 'OK') if (defined($value));
		return HMCCU_SetError ($hash, 'Program execution error');
	}
	elsif ($opt eq 'prgActivate' || $opt eq 'prgDeactivate') {
		$usage = "Usage: set $name $opt program-name";
		my $program = shift @$a // return HMCCU_SetError ($hash, $usage);
		my $mode = $opt eq 'prgActivate' ? 'true' : 'false';
		
		$result = HMCCU_HMScriptExt ($hash, '!ActivateProgram', { name => $program, mode => $mode });

		return HMCCU_SetError ($hash, -2) if ($result =~ /^ERROR:.*/);
		return HMCCU_SetState ($hash, 'OK');	
	}
	elsif ($opt eq 'hmscript') {
		my $script = shift @$a;
		my $dump = shift @$a;
		my $response = '';
		my %ccuReading = ();
		$usage = "Usage: set $name $opt {file|!function|'['code']'} ['dump'] [parname=value [...]]";
		
		# If no parameter is specified list available script functions
		if (!defined($script)) {
			$response = "Available HomeMatic script functions:\n".('-' x 37)."\n";
			foreach my $scr (keys %{$HMCCU_SCRIPTS}) {
				$response .= "$scr ".$HMCCU_SCRIPTS->{$scr}{syntax}."\n".
					$HMCCU_SCRIPTS->{$scr}{description}."\n\n";
			}		
			return $response.$usage;
		}
		
		return HMCCU_SetError ($hash, $usage) if (defined($dump) && $dump ne 'dump');

		# Execute script
		$response = HMCCU_HMScriptExt ($hash, $script, $h);
		return HMCCU_SetError ($hash, -2, $response) if ($response =~ /^ERROR:/);

		HMCCU_SetState ($hash, 'OK');
		return $response if (! $ccureadings || defined($dump));

		foreach my $line (split /[\n\r]+/, $response) {
			my ($obj, $val) = split /=/, $line;
			next if (!defined($val));
			if ($obj =~ /^[a-zA-Z0-9_-]+$/) {
				# If output is not related to a channel store reading in I/O device
				$val = HMCCU_Substitute ($val, $substitute, 0, undef, $obj);
				my $rn = HMCCU_CorrectName ($obj);
				$ccuReading{$rn} = $val;
			}
		}

		HMCCU_UpdateReadings ($hash, \%ccuReading);

		return defined ($dump) ? $response : undef;
	}
	elsif ($opt eq 'rpcregister') {
		my $ifName = shift @$a // 'all';
		$result = '';
		@ifList = ($ifName) if ($ifName ne 'all');
		
		foreach my $i (@ifList) {
			my ($rpcdev, $save) = HMCCU_GetRPCDevice ($hash, 0, $i);
			if ($rpcdev eq '') {
				HMCCU_Log ($hash, 2, "Can't find HMCCURPCPROC device for interface $i");
				next;
			}
			my $res = AnalyzeCommandChain (undef, "set $rpcdev register");
			$result .= $res if (defined($res));
		}
		return HMCCU_SetState ($hash, 'OK', $result);
	}
	elsif ($opt =~ /^(rpcserver|on|off)$/) {
		my $action = $opt eq 'rpcserver' ? shift @$a : $opt;
		$usage = "Usage: set $name $opt {'on'|'off'}";

		return HMCCU_SetError ($hash, "Usage: set $name [rpcserver] {'on'|'off'}")
			if (!defined($action) || $action !~ /^(on|off)$/);
		   
		if ($action eq 'on') {
			return HMCCU_SetError ($hash, 'Start of RPC server failed')
				if (!HMCCU_StartExtRPCServer ($hash));
		}
		else {
			return HMCCU_SetError ($hash, 'Stop of RPC server failed')
				if (!HMCCU_StopExtRPCServer ($hash));
		}
		
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'ackmessages') {
		my $response = HMCCU_HMScriptExt ($hash, "!ClearUnreachable");
		return HMCCU_SetError ($hash, -2, $response) if ($response =~ /^ERROR:/);
		return HMCCU_SetState ($hash, "OK", "Unreach errors in CCU cleared");
	}
	elsif ($opt eq 'cleardefaults') {
		%HMCCU_CUST_CHN_DEFAULTS = ();
		%HMCCU_CUST_DEV_DEFAULTS = ();	
		return HMCCU_SetState ($hash, 'OK', 'Default attributes deleted');
	}
	elsif ($opt eq 'importdefaults') {
		my $filename = shift @$a;
		$usage = "Usage: set $name $opt filename";

		return HMCCU_SetError ($hash, $usage) if (!defined ($filename));
			
		my $rc = HMCCU_ImportDefaults ($filename);
		return HMCCU_SetError ($hash, -16) if ($rc == 0);
		if ($rc < 0) {
			$rc = -$rc;
			return HMCCU_SetError ($hash, "Syntax error in default attribute file $filename line $rc");
		}
		
		return HMCCU_SetState ($hash, "OK", "Default attributes read from file $filename");
	}
	else {
		return $usage;
	}
}

######################################################################
# Get commands
######################################################################

sub HMCCU_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a // return 'No get command specified';
	$opt = lc($opt);

	my $options = "create createDev detectDev defaults:noArg exportDefaults dutycycle:noArg vars update".
		" paramsetDesc rpcEvents:noArg rpcState:noArg deviceInfo".
		" ccuMsg:alarm,service ccuConfig:noArg ccuDevices:noArg".
		" internal:groups,interfaces,versions";
	if (defined($hash->{hmccu}{ccuSuppDevList}) && $hash->{hmccu}{ccuSuppDevList} ne '') {
		$options =~ s/createDev/createDev:$hash->{hmccu}{ccuSuppDevList}/;
	}
	if (defined($hash->{hmccu}{ccuDevList}) && $hash->{hmccu}{ccuDevList} ne '') {
		$options =~ s/detectDev/detectDev:$hash->{hmccu}{ccuDevList}/;
		$options =~ s/deviceInfo/deviceInfo:$hash->{hmccu}{ccuDevList}/;
		$options =~ s/paramsetDesc/paramsetDesc:$hash->{hmccu}{ccuDevList}/;
	}
	my $usage = "HMCCU: Unknown argument $opt, choose one of $options";

	return undef if (HMCCU_IsDelayedInit ($hash) || $hash->{ccustate} ne 'active');
	return 'HMCCU: CCU busy, choose one of rpcstate:noArg'
		if ($opt ne 'rpcstate' && HMCCU_IsRPCStateBlocking ($hash));

	my $ccuflags = HMCCU_GetFlags ($name);
	my $ccureadings = AttrVal ($name, "ccureadings", $ccuflags =~ /noReadings/ ? 0 : 1);

	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
	my @ifList = keys %$interfaces;

	my $readname;
	my $readaddr;
	my $result = '';
	my $rc;
	
	if ($opt eq 'vars') {
		my $varname = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name vars {regexp}");
		($rc, $result) = HMCCU_GetVariables ($hash, $varname);
		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return HMCCU_SetState ($hash, 'OK', $result);
	}
	elsif ($opt eq 'update') {
		my $devexp = shift @$a // '.*';
		my $ccuget = shift @$a // 'Attr';
		return HMCCU_SetError ($hash, "Usage: get $name $opt [device-expr [{'State'|'Value'}]]")
			if ($ccuget !~ /^(Attr|State|Value)$/);
		HMCCU_UpdateClients ($hash, $devexp, $ccuget);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'ccudevices') {
		my $devTable = '<html><table border="1">'.
			'<tr><th>Name</th><th>Model</th><th>Interface</th><th>Address</th><th>Channels</th><th>Supported roles</th></tr>';
		foreach my $di (sort keys %{$hash->{hmccu}{device}}) {
			foreach my $da (sort keys %{$hash->{hmccu}{device}{$di}}) {
				next if ($hash->{hmccu}{device}{$di}{$da}{_addtype} ne 'dev');
				my $chn = exists($hash->{hmccu}{dev}{$da}) ? $hash->{hmccu}{dev}{$da}{channels} : '?';
				my @roles = HMCCU_GetDeviceRoles ($hash, $di, $da, 1);
				my %suppRoles;
				$suppRoles{$_}++ for @roles;
				$devTable .= "<tr>".
					"<td>$hash->{hmccu}{device}{$di}{$da}{_name}</td>".
					"<td>$hash->{hmccu}{device}{$di}{$da}{_model}</td>".
					"<td>$di</td><td>$da</td><td>$chn</td>".
					"<td>".join('<br/>', map { "$_ [$suppRoles{$_}x]" } sort keys %suppRoles)."</td>".
					"</tr>\n";
			}
		}
		$devTable .= '</table></html>';
		return $devTable;
	}
	elsif ($opt eq 'deviceinfo') {
		my $device = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name $opt {device} [extended]");
		my $extended = shift @$a;
		my ($add, $chn) = HMCCU_GetAddress ($hash, $device);
		return HMCCU_SetError ($hash, -1, $device) if ($add eq '');
		return HMCCU_ExecuteGetDeviceInfoCommand ($hash, $hash, $add, defined($extended) ? 1 : 0);
	}
	elsif ($opt eq 'rpcevents') {
		$result = '';
		foreach my $ifname (@ifList) {
			my ($rpcdev, $save) = HMCCU_GetRPCDevice ($hash, 0, $ifname);
			if ($rpcdev eq '') {
				HMCCU_Log ($hash, 2, "Can't find HMCCURPCPROC device for interface $ifname");
				next;
			}
			my $res = AnalyzeCommandChain (undef, "get $rpcdev rpcevents");
			$result .= $res if (defined($res));
		}
		return HMCCU_SetState ($hash, 'OK', $result) if ($result ne '');
		return HMCCU_SetError ($hash, 'No event statistics available');
	}
	elsif ($opt eq 'rpcstate') {
		my @hm_pids = ();
		if (HMCCU_IsRPCServerRunning ($hash, \@hm_pids)) {
			$result = 'RPC process(es) running with pid(s) '.
				join (',', @hm_pids) if (scalar(@hm_pids) > 0);
		}
		else {
			$result = 'No RPC processes or threads are running';
		}	
		return HMCCU_SetState ($hash, 'OK', $result);
	}
	elsif ($opt eq 'ccuconfig') {
		my ($devcount, $chncount, $ifcount, $prgcount, $gcount) = HMCCU_GetDeviceList ($hash);
		return HMCCU_SetError ($hash, -2) if ($devcount < 0);
		return HMCCU_SetError ($hash, 'No devices received from CCU') if ($devcount == 0);
		HMCCU_ResetDeviceTables ($hash);
		my ($cDev, $cPar, $cLnk) = HMCCU_GetDeviceConfig ($hash);
		return "Devices: $devcount, Channels: $chncount\nDevice descriptions: $cDev\n".
			"Paramset descriptions: $cPar\nLinks/Peerings: $cLnk\n".
			"Interfaces: $ifcount\nPrograms: $prgcount\nVirtual groups: $gcount";
	}
	elsif ($opt eq 'detectdev') {
		$usage = "Usage: get $name detectDev device-name";
		my $devSpec = shift @$a // return HMCCU_SetError ($hash, $usage);

		foreach my $iface (keys %{$hash->{hmccu}{device}}) {
			foreach my $address (keys %{$hash->{hmccu}{device}{$iface}}) {
				if ($hash->{hmccu}{device}{$iface}{$address}{_name} eq $devSpec) {
					my $detect = HMCCU_DetectDevice ($hash, $address, $iface);
					if (defined($detect)) {
						return HMCCU_RefToString ($detect);
					}
					else {
						return "Automatic detection of $devSpec not possible";
					}
				}
			}
		}
		
		return "Device $devSpec not found";
	}
	elsif ($opt eq 'create' || $opt eq 'createdev') {
		$usage = $opt eq 'createdev' ?
			"Usage: get $name createDev device-name" :
			"Usage: get $name create device-expr [s=suffix] [p=prefix] [f=format] ".
				"['noDefaults'] ['save'] ['forceDev'] [attr=val [...]]";

		# Process command line parameters				
		my $devSpec = shift @$a // return HMCCU_SetError ($hash, $usage); 
		my $devPrefix = $h->{'p'} // '';	    # Prefix of FHEM device name
		my $devSuffix = $h->{'s'} // '';	    # Suffix of FHEM device name
		my $devFormat = $h->{'f'} // '%n';	 # Format string for FHEM device name
		my @options = ();
		my $saveDef = 0;
		foreach my $defOpt (@$a) {
			if (lc($defOpt) eq 'nodefaults')  { push @options, 'noDefaults'; }
			elsif (lc($defOpt) eq 'save')     { $saveDef = 1; }
			elsif (lc($defOpt) eq 'forcedev') { push @options, 'forceDev'; }
			else                              { return HMCCU_SetError ($hash, $usage); }
		}
		$devSpec = '^'.$devSpec.'$' if ($opt eq 'createdev');
		my $defOpts = join(' ', @options);

		# Setup attributes for new devices
		my %ah = ();
		HMCCU_SetInitialAttributes ($hash, undef, \%ah);
		foreach my $da (keys %$h) { $ah{$da} = $h->{$da} if ($da !~ /^[psf]$/); }

		my $cs = HMCCU_CreateFHEMDevices ($hash, $devSpec, $devPrefix, $devSuffix, $devFormat, $defOpts, \%ah);
		
		# Statistics
		#
		# {statsValue}{devName} = addr.ccuName
		#
		# {notDetected}{$ccuDevName}: CCU device with $devName not detected
		# {notSupported}{$ccuDevName}: CCU device type is not supported by create commands
		# {fhemExists}{$fhemDevName}: FHEM device with $devName already exists
		# {devDefined}{$fhemDevName}: FHEM device for $devAdd already exists
		# {defFailed}{$fhemDevName}: Device definition failed
		# {defSuccess}{$fhemDevName}: Device defined
		# {attrFailed}{$fhemDevName.$attr}: Attribute setting failed

		# Save FHEM config
		CommandSave (undef, undef) if (scalar(keys %{$cs->{defSuccess}}) > 0 && $saveDef);				

		# Prepare summary
		my %csText = (
			notDetected => 'Not detected CCU devices: ',
			notSupported => 'Not supported by create command: ',
			fhemExists => 'FHEM device already exists: ',
			devDefined => 'HMCCUCHN devices already defined for: ',
			defFailed => 'Failed to define devices: ',
			defSuccess => 'New devices successfuly defined: ',
			attrFailed => 'Failed to assign attributes: '
		);
		$result = "Results of create command:";
		foreach my $sk (keys %csText) {
			$result .= "\n$csText{$sk}\n".join('', map { "  $_ = $cs->{$sk}{$_}\n" } keys %{$cs->{$sk}}) if (scalar(keys %{$cs->{$sk}}) > 0);
		}
		
		return HMCCU_SetState ($hash, 'OK', $result);
	}
	elsif ($opt eq 'dutycycle') {
		HMCCU_GetDutyCycle ($hash);
		return HMCCU_SetState ($hash, 'OK');
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash, 1);
		return HMCCU_SetState ($hash, 'OK', $result);
	}
	elsif ($opt eq 'exportdefaults') {
		$usage = "Usage: get $name $opt filename ['all']";	
		my $filename = shift @$a // return HMCCU_SetError ($hash, $usage);
		my $all = 0;
		my $defopt = shift @$a;
		$all = 1 if (defined($defopt) && $defopt eq 'all');
		
		my $rc = HMCCU_ExportDefaults ($filename, $all);
		return HMCCU_SetError ($hash, -16) if ($rc == 0);
		return HMCCU_SetState ($hash, 'OK', "Default attributes written to $filename");
	}
	elsif ($opt eq 'aggregation') {
		$usage = "Usage: get $name $opt {'all'|rule}";	
		my $rule = shift @$a // return HMCCU_SetError ($hash, $usage);
			
		if ($rule eq 'all') {
			foreach my $r (keys %{$hash->{hmccu}{agg}}) {
				my $rc = HMCCU_AggregateReadingsRule ($hash, $r);
				$result .= "$r = $rc\n";
			}
		}
		else {
			return HMCCU_SetError ($hash, "HMCCU: Aggregation rule $rule does not exist")
				if (!exists($hash->{hmccu}{agg}{$rule}));
			$result = HMCCU_AggregateReadingsRule ($hash, $rule);
			$result = "$rule = $result";			
		}

		return HMCCU_SetState ($hash, 'OK', $ccureadings ? undef : $result);
	}
	elsif ($opt eq 'paramsetdesc') {
		my $device = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name $opt {device}");
		my ($add, $chn) = HMCCU_GetAddress ($hash, $device);
		return HMCCU_SetError ($hash, -1, $device) if ($add eq '');
		return HMCCU_ParamsetDescToStr ($hash, $add) // HMCCU_SetError ($hash, "Can't get device description");
	}
	elsif ($opt eq 'ccumsg') {
		my $msgtype = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name $opt {service|alarm}");
		my $script = ($msgtype eq 'service') ? "!GetServiceMessages" : "!GetAlarms";

		my $res = HMCCU_HMScriptExt ($hash, $script);		
		return HMCCU_SetError ($hash, "Error") if ($res eq '' || $res =~ /^ERROR:.*/);
		
		# Generate event for each message
		foreach my $msg (split /[\n\r]+/, $res) {
			DoTrigger ($name, $msg) if ($msg !~ /^[0-9]+$/);
		}
		
		return HMCCU_SetState ($hash, 'OK', $res);
	}
	elsif ($opt eq 'internal') {
		my $parameter = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name $opt {internalParameter}");
		if ($parameter eq 'groups') {
			return exists($hash->{hmccu}{grp}) && scalar(keys %{$hash->{hmccu}{grp}}) > 0 ?
				'<html>'.HMCCU_FormatHashTable ($hash->{hmccu}{grp}).'</html>' :
				'No virtual groups found';
		}
		elsif ($parameter eq 'interfaces') {
			return exists($hash->{hmccu}{interfaces}) && scalar(keys %{$hash->{hmccu}{interfaces}}) > 0 ?
				'<html>'.HMCCU_FormatHashTable ($hash->{hmccu}{interfaces}).'</html>' :
				'No interfaces found';
		}
		elsif ($parameter eq 'versions') {
			my $v = '';
			foreach my $m ('HMCCU', 'HMCCURPCPROC', 'HMCCUDEV', 'HMCCUCHN') {
				$v .= "$m: ".($modules{$m}{version} // '???').'<br/>' if (exists($modules{$m})); 
			}
			return $v ne '' ? "<html>$v</html>" : 'No module versions found';
		}
		else {
			return HMCCU_SetError ($hash, "Invalid internal parameter $parameter");
		}
	}
	else {
		if (exists ($hash->{hmccu}{agg})) {
			my @rules = keys %{$hash->{hmccu}{agg}};
			$usage .= " aggregation:all,".join (',', @rules) if (scalar(@rules) > 0);
		}
		return $usage;
	}
}

######################################################################
# Filter reading by datapoint and optionally by channel name or
# channel address.
# Parameter channel can be a channel name or a channel address without
# interface specification.
# Filter rule syntax is either:
#   [N:]{Channel-No[,Channel-No]|Channel-Name-Expr}!Datapoint-Expr
# or
#   [N:][Channel-No[,Channel-No].]Datapoint-Expr
# Multiple filter rules must be separated by ;
# Return: 0=Do not update reading, 1=Update reading
######################################################################
 
sub HMCCU_FilterReading ($$$;$)
{
	my ($hash, $chn, $dpt, $ps) = @_;
	my $name = $hash->{NAME};
	my $ioHash = HMCCU_GetHash ($hash) // return 1;
	
	if (defined($ps)) {
		$ps = 'LINK' if ($ps =~ /^LINK\..+$/);
	}
	else {
		$ps = 'VALUES';
	}

	my $flags = HMCCU_GetFlags ($name);
	my @flagList = $flags =~ /show(Master|Link|Device|Service)Readings/g;
	push (@flagList, 'VALUES');
	my $dispFlags = uc(join(',', @flagList));
	my ($sc, $sd) = HMCCU_StateDatapoint ($hash);
	my ($cc, $cd) = HMCCU_ControlDatapoint ($hash);
	my $rfAtt = AttrVal ($name, 'ccureadingfilter', '');
	my $rf = $rfAtt eq '' ? '.*' : $rfAtt;

	my $chnnam = '';
	my ($devadd, $chnnum) = HMCCU_SplitChnAddr ($chn);
	if ($chnnum ne 'd') {
		# Get channel name and channel number
		$chnnam = HMCCU_GetChannelName ($ioHash, $chn);
		if ($chnnam eq '') {
			($devadd, $chnnum) = HMCCU_GetAddress ($hash, $chn);
			$chnnam = $chn;
		}
	}

 	HMCCU_Trace ($hash, 2, "chn=$chn, cName=$chnnam cNum=$chnnum dpt=$dpt, rules=$rf dispFlags=$dispFlags ps=$ps");	
 	return 0 if (($dispFlags !~ /DEVICE/ && ($chnnum eq 'd' || $chnnum eq '0')) || $dispFlags !~ /$ps/);

	# Process filter rules
	foreach my $r (split (';', $rf)) {
		my $rm = 1;
		my $cn = '';
		my $cnl = '';
		
		# Negative filter
		if ($r =~ /^N:/) {
			$rm = 0;
			$r =~ s/^N://;
		}
		
		# Get filter criteria
		my ($c, $f) = split ("!", $r);
		if (defined($f)) {
			next if ($c eq '' || $chnnam eq '' || $chnnum eq '');
			$cn = $c if ($c =~ /^([0-9]{1,2})$/);
			$cnl = $c if ($c =~ /^[0-9]{1,2}(,[0-9]{1,2})+$/);
		}
		else {
			$c = '';
			if ($r =~ /^([0-9]{1,2})\.(.+)$/) {
				$cn = $1;
				$f = $2;
			}
			elsif ($r =~ /^[0-9]{1,2}(,[0-9]{1,2})+\.(.+)$/) {
				($cnl, $f) = split /\./, $r, 2;
			}
			else {
				$cn = '';
				$f = $r;
			}
		}

		$cnl = ",$cnl," if ($cnl ne '');
	
		HMCCU_Trace ($hash, 2, "    check rm=$rm f=$f cn=$cn cnl=$cnl c=$c");
		# Positive filter
		return 1 if (
			$rm && (
				(
					($cn ne '' && "$chnnum" eq "$cn") ||
					($cnl ne '' && $cnl =~ /,$chnnum,/) ||
					($c ne '' && $chnnam =~ /$c/) ||
					($cn eq '' && $c eq '' && $cnl eq '') ||
					($chnnum eq 'd')
				) && $dpt =~ /$f/
			)
		);
		# Negative filter
		return 1 if (
			!$rm && (
				($cn ne '' && "$chnnum" ne "$cn") ||
				($c ne '' && $chnnam !~ /$c/) ||
				$dpt !~ /$f/
			)
		);
		HMCCU_Trace ($hash, 2, "    check result false");
	}

	return 0;
}

######################################################################
# Build reading name
#
# Parameters:
#
#   $i - Interface
#   $a - Address
#   $c - Channel number
#   $d - Datapoint name
#   $h - 0=Show reading, 1=Hide reading
#   $rf - Reading name format
#   $ps - Parameter set
#   Format := { name[lc] | datapoint[lc] | address[lc] | formatStr }
#   formatStr := Any text containing at least one format pattern
#   pattern := { %a, %c, %n, %d, %A, %C, %N, %D }
#
# Valid combinations of input parameters:
#
#   ChannelName,Datapoint
#   Address,Datapoint
#   Address,ChannelNo,Datapoint
#
# Reading names can be modified or new readings can be added by
# setting attribut ccureadingname.
# Returns list of readings names. Return empty list on error.
######################################################################

sub HMCCU_GetReadingName ($$$$$;$$$)
{
	my ($hash, $i, $a, $c, $d, $h, $rf, $ps) = @_;
	$c //= '';
	$i //= '';
	$h //= 0;
	$ps //= 'VALUES';
	my $n = '';
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	
	# Reading name prefix depends on parameter set name. Readings of parameter set
	# VALUES have no prefix
	my %prefix = (
		'MASTER' => 'R-', 'LINK' => 'L-', 'VALUES' => '',
		'PEER' => 'P-', 'DEVICE' => 'R-'
	);

	# Datapoints to be converted to new readings
	my %newReadings = (
		'AES_KEY'           => 'sign',
		'RSSI_DEVICE'       => 'rssidevice',
		'RSSI_PEER'         => 'rssipeer',
		'LOW_BAT'           => 'battery',
		'LOWBAT'            => 'battery',
		'OPERATING_VOLTAGE' => 'voltage',
		'UNREACH'           => 'activity',
		'SABOTAGE'          => 'sabotage',
		'ERROR_SABOTAGE'    => 'sabotage'
	);

	my $ioHash = HMCCU_GetHash ($hash);
	return () if (!defined($ioHash) || !defined($d) || $d eq '');

	my $hideStandard    = HMCCU_IsFlag ($name, 'hideStdReadings');
	my $replaceStandard = HMCCU_IsFlag ($name, 'replaceStdReadings');

	# Links
	my @rcv = ();
	if ($ps =~ /^LINK\.(.+)$/) {
		@rcv = HMCCU_GetDeviceIdentifier ($ioHash, $1);
		$ps = 'LINK';
	}

	my $rn = '';
	my @rnlist = ();

	# Get reading prefix definitions
	$ps = 'DEVICE' if (($c eq '0' && $ps eq 'MASTER') || $c eq 'd');
	my $readingPrefix = HMCCU_GetAttribute ($ioHash, $hash, 'ccuReadingPrefix', '');
	foreach my $pd (split (',', $readingPrefix)) {
		my ($rSet, $rPre) = split (':', $pd);
		if (exists($prefix{$rSet})) {
			$prefix{$rSet} = defined($rPre) && $rPre ne '' ? $rPre : '';
		}
	}
	my $rpf = exists($prefix{$ps}) ? $prefix{$ps} : '';

	# Add device state reading
	if (exists($newReadings{$d}) && ($c eq '' || $c eq '0')) {
		push @rnlist, $newReadings{$d};
	}

	# Build list of reading name rules
	my @srl = ();
	my $crn = AttrVal ($name, 'ccureadingname', '');
	push @srl, split(';', $crn) if ($crn ne '');
#	if (!$hideStandard &&
#		(exists($hash->{hmccu}{control}{chn}) && "$c" eq $hash->{hmccu}{control}{chn}) ||
#		(exists($hash->{hmccu}{state}{chn}) && "$c" eq $hash->{hmccu}{state}{chn})
#	) {
	if (!$hideStandard) {
		my $role = $c ne '' && $c ne 'd' ? HMCCU_GetChannelRole ($hash, $c) : '';
		$crn = $role ne '' && exists($HMCCU_READINGS->{$role}) ? $HMCCU_READINGS->{$role} : $HMCCU_READINGS->{DEFAULT};
		$crn =~ s/C#\\/$c\\/g;
		$crn =~ s/P#/$rpf/g;
		push @srl, map { $replaceStandard ? $_ =~ s/\+//g : $_ } split(';',$crn);
	}
	
	# Try to complete missing values
	if ($a ne '') {
		$n = ($c ne '') ? HMCCU_GetChannelName ($ioHash, $a.':'.$c) : HMCCU_GetDeviceName ($ioHash, $a);
	}
	if ($n ne '' && $a eq '') {
		($a, $c) = HMCCU_GetAddress ($ioHash, $n);
	}
	if ($i eq '' && $a ne '') {
		$i = HMCCU_GetDeviceInterface ($ioHash, $a);
	}

	# Format reading name
	if (!$h) {
		$rf //= HMCCU_GetAttrReadingFormat ($hash, $ioHash);
		$rn = HMCCU_FormatReadingName ($hash, $rf, $i, $a, $c, $d, $n);
		push @rnlist, $rpf.$rn;
	}

	if (scalar(@rcv) > 0) {
		# Add link readings
		push @rnlist, map { $rpf.$_.'-'.$rn } @rcv;
	}

	# Process reading name rules. Modify and/or add reading names
	return HMCCU_Unique (map { HMCCU_ModifyReadingName ($_, \@srl) } @rnlist);
}

sub HMCCU_ModifyReadingName ($$)
{
	my ($rn, $srl) = @_;

	my @rnlist = ();
	my $f = 0;

	foreach my $rr (@$srl) {
		my ($rold, $rnw) = split (':', $rr);
		next if (!defined($rold) || $rold eq '');
		if ($rn =~ /$rold/) {
			if (!defined ($rnw) || $rnw eq '') {
				# Suppress reading
				$f = 1;
				next;
			}
			foreach my $rnew (split (',', $rnw)) {
				my $radd = $rn;
				if ($rnew =~ /^\+(.+)$/) {
					# Add new reading
					$rnew = $1;
					$radd =~ s/$rold/$rnew/;
					push @rnlist, $rn, $radd;
					$f = 1;
				}
				else {
					# Substitute reading
					$radd =~ s/$rold/$rnew/;
					push @rnlist, $radd;
					$f = 1;
					last;
				}
			}
		}
	}

	# Add original reading name to list if no rule matched
	push @rnlist, $rn if ($f == 0);

	return map { HMCCU_CorrectName ($_) } @rnlist;
}

sub HMCCU_FormatReadingName ($$$$$$$)
{
	my ($clHash, $rf, $i, $a, $c, $d, $n) = @_;

	$rf = 'datapoint' if (!defined($rf) || $rf eq '');
	my $rn = '';

	if ($rf =~ /^datapoint(lc|uc)?$/) {
		$rn = $c ne '' && $c ne 'd' && $clHash->{TYPE} ne 'HMCCUCHN' ? $c.'.'.$d : $d;
	}
	elsif ($rf =~ /^name(lc|uc)?$/) {
		return () if ($n eq '');
		$rn = $n.'.'.$d;
	}
	elsif ($rf =~ /^address(lc|uc)?$/) {
		return () if ($a eq '');
		my $t = $a;
		$t = $i.'.'.$t if ($i ne '');
		$t = $t.'.'.$c if ($c ne '');
		$rn = $t.'.'.$d;
	}
	elsif ($rf =~ /\%/) {
		$rn = $rf;
		if ($a ne '') { $rn =~ s/\%a/lc($a)/ge; $rn =~ s/\%A/uc($a)/ge; }
		if ($n ne '') { $rn =~ s/\%n/lc($n)/ge; $rn =~ s/\%N/uc($n)/ge; }
		if ($c ne '') { $rn =~ s/\%c/lc($c)/ge; $rn =~ s/\%C/uc($c)/ge; }
		$rn =~ s/\%d/lc($d)/ge;
		$rn =~ s/\%D/uc($d)/ge;
	}
	
	# Convert to lower or upper case
	$rn = lc($rn) if ($rf =~ /^(datapoint|name|address)lc$/);
	$rn = uc($rn) if ($rf =~ /^(datapoint|name|address)uc$/);

	return $rn;
}

######################################################################
# Format reading value depending on attribute stripnumber.
# Syntax of attribute stripnumber:
#   [datapoint-expr!]format[;...]
# Valid formats:
#   0 = Remove all digits
#   1 = Preserve 1 digit
#   2 = Remove trailing zeroes
#   -n = Round value to specified number of digits (-0 is allowed)
#   %f = Format for numbers. String suffix is allowed.
######################################################################

sub HMCCU_FormatReadingValue ($$$)
{
	my ($hash, $value, $dpt) = @_;
	my $name = $hash->{NAME};

	if (!defined($value)) {
		HMCCU_Trace ($hash, 2, "Value undefined for datapoint $dpt");
		return $value;
	}
	
	my $stripnumber = HMCCU_GetAttrStripNumber ($hash);
	
	if ($stripnumber ne 'null' && HMCCU_IsFltNum ($value)) {
		my $isint = HMCCU_IsIntNum ($value) ? 2 : 0;
	
		foreach my $sr (split (';', $stripnumber)) {
			my ($d, $s) = split ('!', $sr);
			if (defined ($s)) {
				next if ($d eq '' || $dpt !~ /$d/);
			}
			else {
				$s = $sr;
			}
			
			return HMCCU_StripNumber ($value, $s, $isint | 1);
		}
	
		HMCCU_Trace ($hash, 2, "sn = $stripnumber, dpt=$dpt, isint=$isint, value $value not changed");	
	}
	else {
		my $h = uc(unpack "H*", $value);
		HMCCU_Trace ($hash, 2, "sn = $stripnumber, Value $value 0x$h not changed");
	}

	return $value;
}

######################################################################
# Format number
# Parameter:
#   $value - Any value (non numeric values will be ignored)
#   $strip -
#   $number - 0=detect, 1=number, 2=integer
######################################################################

sub HMCCU_StripNumber ($$;$)
{
	my ($value, $strip, $number) = @_;	
	$number //= 0;
	
	if ($number & 1 || $value =~ /^[+-]?\d*\.?\d+(?:(?:e|E)\d+)?$/) {
		my $isint = ($number & 2 || $value =~ /^[+-]?[0-9]+$/) ? 1 : 0;
		
		if ($strip eq '0' && !$isint)             { return sprintf ("%d", $value); }
		elsif ($strip eq '1' && !$isint)          { return sprintf ("%.1f", $value); }
		elsif ($strip eq '2' && !$isint)          { return sprintf ("%g", $value); }
		elsif ($strip =~ /^-([0-9])$/ && !$isint) { my $f = '%.'.$1.'f'; return sprintf ($f, $value); }
		elsif ($strip =~ /^%.+$/)                 { return sprintf ($strip, $value); }	
	}
	
	return $value;
}

######################################################################
# Convert float to int, if float == int
######################################################################

sub HMCCU_StripZero ($)
{
	my ($value) = @_;

	return HMCCU_IsFltNum ($value) && int($value) == $value ? int($value) : $value;
}

######################################################################
# Log message if trace flag is set.
# Will output multiple log file entries if parameter msg is separated
# by <br>
######################################################################

sub HMCCU_Trace ($$$)
{
	my ($hash, $level, $msg) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	
	return if (!HMCCU_IsFlag ($name, 'trace'));	
		
	my $pid = $$;
	my $fnc = (caller(1))[3] // 'unknown';	
	
	my $traceFilter = AttrVal ($name, 'traceFilter', '.*'); 
	return if ($fnc !~ /$traceFilter/);
	
	foreach my $m (split ("<br>", $msg)) {
		Log3 $name, $level, "$type: [$name : $pid] [$fnc] $m";
	}
}

######################################################################
# Log message. Optionally show message on the screen, if async output
# is possible.
######################################################################

sub HMCCU_LogDisplay ($$$;$)
{
	my ($hash, $level, $msg, $rc) = @_;
	
	if ($init_done && exists($hash->{CL})) {
		my $devType = $hash->{TYPE} // '';
		my $devName = defined($hash->{NAME}) ? " [$hash->{NAME}]" : '';
		my $cl = $hash->{CL};
		InternalTimer (gettimeofday()+1, sub { asyncOutput ($cl, "$devType $devName $msg") }, undef, 1);
	}
	
	return HMCCU_Log ($hash, $level, $msg, $rc);
}

######################################################################
# Log message with module type, device name and process id.
# Return parameter rc or 0.
# Parameter source can be a device hash reference, a string reference
# or a string.
# Parameter msg can be an array reference or a string.
######################################################################

sub HMCCU_Log ($$$;$)
{
	my ($source, $level, $msg, $rc) = @_;
	$rc //= 0;
	
	my ($cf, $cp, $cl) = caller;
	my $r = defined($source) ? ref($source) : 'N/A';
	my $pid = $$;
	my $name = 'N/A';
	
	if ($r eq 'HASH')      { $name = $source->{NAME} // 'N/A'; }
	elsif ($r eq 'SCALAR') { $name = $$source; }
	else                   { $name = $source // 'N/A'; }

	my $hash = $defs{$name};
	my $type = defined($hash) ? $hash->{TYPE} : 'N/A';
	if (defined($hash) && HMCCU_IsFlag ($hash->{NAME}, 'logEnhanced')) {
		$type .= ":$cl";
		$name .= " : $pid";
	}
	my $logname = exists($defs{$name}) ? $name : undef;

	if (ref($msg) eq 'ARRAY') {
		foreach my $m (@$msg) {
			# Remove credentials from URLs
			$m =~ s/(https?:\/\/)[^\@]+\@/$1/g;
			Log3 $logname, $level, "$type [$name] $m";
		}
	}
	else {
		# Remove credentials from URLs
		$msg =~ s/(https?:\/\/)[^\@]+\@/$1/g;
		Log3 $logname, $level, "$type [$name] $msg";
	}

	return $rc;
}

######################################################################
# Log message and return message preceded by string "ERROR: ".
######################################################################

sub HMCCU_LogError ($$$)
{
	my ($hash, $level, $msg) = @_;
	
	return HMCCU_Log ($hash, $level, $msg, "ERROR: $msg");
}

######################################################################
# Set error state and write log file message
# Parameter text can be an error code (integer <= 0) or an error text.
# If text is 0 or 'OK' call HMCCU_SetState which returns undef.
# Otherwise error message is returned.
# Parameter addinfo is optional.
######################################################################

sub HMCCU_SetError ($@)
{
	my ($hash, $text, $addinfo) = @_;
	$addinfo //= '';
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $msg;

	if ($text ne 'OK' && $text ne '0') {
		$msg = $HMCCU_ERR_LIST{$text} // $text;
		$msg = "$type: $name $msg";
		$msg .= ". $addinfo" if ($addinfo ne '');
		HMCCU_Log ($hash, 1, $msg);
		return HMCCU_SetState ($hash, 'Error', $msg);
	}

	return HMCCU_SetState ($hash, 'OK');
}

######################################################################
# Set state of device if attribute ccuflags = ackState
# Return undef or $retval
######################################################################

sub HMCCU_SetState ($@)
{
	my ($hash, $text, $retval) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = HMCCU_GetFlags ($name);
	$ccuflags .= ',ackState' if ($hash->{TYPE} eq 'HMCCU' && $ccuflags !~ /ackState/);
	
	if (defined($hash) && defined($text) && $ccuflags =~ /ackState/) {
		readingsSingleUpdate ($hash, 'state', $text, 1)
			if (ReadingsVal ($name, 'state', '') ne $text);
	}

	return $retval;
}

######################################################################
# Set state of RPC server. Update all client devices if overall state
# is 'running'.
# Parameters iface and msg are optional. If iface is set function
# was called by HMCCURPCPROC device.
######################################################################

sub HMCCU_SetRPCState ($@)
{
	my ($hash, $state, $iface, $msg) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = HMCCU_GetFlags ($name);
	my $filter;
	my $rpcstate = $state;
	
	if (defined($iface)) {
		# Set interface state
		my ($ifname) = HMCCU_GetRPCServerInfo ($hash, $iface, 'name');
		$hash->{hmccu}{interfaces}{$ifname}{state} = $state if (defined ($ifname));
		
		# Count number of processes in state running, error or inactive
		# Prepare filter for updating client devices
		my %stc = ('running' => 0, 'error' => 0, 'inactive' => 0);
		my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
		my @iflist = keys %$interfaces;
		my $ifCount = scalar(@iflist);
		foreach my $i (@iflist) {
			my $st = $hash->{hmccu}{interfaces}{$i}{state};
			$stc{$st}++ if (exists ($stc{$st}));
			if ($hash->{hmccu}{interfaces}{$i}{manager} eq 'HMCCU' && $ccuflags !~ /noInitialUpdate/) {
				my $rpcFlags = AttrVal ($hash->{hmccu}{interfaces}{$i}{device}, 'ccuflags', 'null');
				if ($rpcFlags !~ /noInitialUpdate/) {
					$filter = defined ($filter) ? "$filter|$i" : $i;
				}
			}
		}
		
		# Determine overall process state
		$rpcstate = 'null';
		foreach my $rpcst (keys %stc) {
			if ($stc{$rpcst} == $ifCount) {
				$rpcstate = $rpcst;
				last;
			}
		}

		if ($rpcstate ne 'null' && $rpcstate ne $hash->{RPCState}) {
			$hash->{RPCState} = $rpcstate;
			readingsSingleUpdate ($hash, "rpcstate", $rpcstate, 1);
			HMCCU_Log ($hash, 4, "Set rpcstate to $rpcstate");
			HMCCU_Log ($hash, 1, $msg) if (defined($msg));
			HMCCU_Log ($hash, 1, "All RPC servers $rpcstate");
			DoTrigger ($name, "RPC server $rpcstate");
			HMCCU_UpdateClients ($hash, '.*', 'Value', $filter, 1)
				if ($rpcstate eq 'running' && defined($filter));
		}
	}

	# Set I/O device state
	if ($rpcstate eq 'running' || $rpcstate eq 'inactive') {
		HMCCU_SetState ($hash, 'OK');
	}
	elsif ($rpcstate eq 'error') {
		HMCCU_SetState ($hash, 'error');
	}
	else {
		HMCCU_SetState ($hash, 'busy');
	}
	
	return undef;
}

######################################################################
# Substitute first occurrence of regular expression or fixed string.
# Floating point values are ignored without datapoint specification.
# Integer values are compared with complete value.
#   $hashOrRule - 
#   $mode - 0=Substitute regular expression, 1=Substitute text
#   $chn  - A channel number. Ignored if $dpt contains a Channel
#           number.
#   $dpt  - Datapoint name. If it contains a channel number, it
#           overrides parameter $chn
#   $type - Role of a channel, i.e. SHUTTER_CONTACT (optional).
#   $devDesc - Device description reference (optional).
######################################################################

sub HMCCU_Substitute ($$$$$;$$)
{
	my ($value, $hashOrRule, $mode, $chn, $dpt, $type, $devDesc) = @_;

	my $substrule = '';
	my $ioHash;
	my $rc = 0;
	my $newvalue;
	my $noAutoSubstitute = 0;

	if ($mode == -1) {
		$mode = 0;
		$noAutoSubstitute = 1;
	}
	
	if (defined($hashOrRule)) {
		if (ref($hashOrRule) eq 'HASH') {
			$ioHash = HMCCU_GetHash ($hashOrRule);
			$substrule = HMCCU_GetAttrSubstitute ($hashOrRule, $ioHash);
		}
		else {
			$substrule = $hashOrRule;
		}
	}

	# Separate channel number from datapoint if specified
	if ($dpt =~ /^([0-9]{1,2})\.(.+)$/) {
		($chn, $dpt) = ($1, $2);
	}
	
	my @rulelist = split (';', $substrule);
	foreach my $rule (@rulelist) {
		my @ruletoks = split ('!', $rule);
		if (scalar(@ruletoks) == 2 && $dpt ne '' && $mode == 0) {
			# Substitute if current role and/or datapoint is matching rule

			# Left part of subst rule. r=role, f=channel/datapoint filter
			my ($r, $f) = split (':', $ruletoks[0], 2);
			if (!defined($f)) {
				# No role specified
				$f = $r;
				$r = undef;
			}
			if (!defined($r) || (defined($type) && defined($r) && $r eq $type)) {
				# List of datapoints where rule should be applied on
				my @dptlist = split (',', $f);
				foreach my $d (@dptlist) {
					my $c = -1;	# Channel number (optional)
					if ($d =~ /^([0-9]{1,2})\.(.+)$/) {
						($c, $d) = ($1, $2);
					}
					if ($d eq $dpt && ($c == -1 || !defined($chn) || $c == $chn)) {
						($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[1], $mode);
						return $newvalue if ($rc == 1);
					}
				}
			}
		}
		elsif (scalar(@ruletoks) == 1) {
			# Substitute independent from role/datapoint

			# Do not substitute floating point values ???
			return $value if ($value !~ /^[+-]?\d+$/ && $value =~ /^[+-]?\d*\.?\d+(?:(?:e|E)\d+)?$/);

			($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[0], $mode);
			return $newvalue if ($rc == 1);
		}
	}

	# Original value not modified by rules. Use default conversion depending on type/role
	# Default conversion can be overriden by attribute ccudef-substitute in I/O device
	return $value if ($noAutoSubstitute);

	# Substitute by rules defined in CONVERSIONS table		
	if (!defined($type) || $type eq '') {
		$type = defined($devDesc) && defined($devDesc->{INDEX}) ? $devDesc->{TYPE} : 'DEFAULT';
	}
	if (exists($HMCCU_CONVERSIONS->{$type}{$dpt}{$value})) {
		return $HMCCU_CONVERSIONS->{$type}{$dpt}{$value};
	}
	elsif (exists($HMCCU_CONVERSIONS->{DEFAULT}{$dpt}{$value})) {
		return $HMCCU_CONVERSIONS->{DEFAULT}{$dpt}{$value};
	}

	# Substitute enumerations and default parameter type conversions
	if (defined($devDesc) && defined($ioHash)) {
		my $paramDef = HMCCU_GetParamDef ($ioHash, $devDesc, 'VALUES', $dpt) //
			HMCCU_GetParamDef ($ioHash, $devDesc, 'MASTER', $dpt);
		if (defined($paramDef) && defined($paramDef->{TYPE})) {
			my %ct = (
				'BOOL' => { '0' => 'false', '1' => 'true' }
			);
			my $parType = $paramDef->{TYPE};
			if ($parType eq 'ENUM' && defined($paramDef->{VALUE_LIST}) && HMCCU_IsIntNum($value)) {
				return HMCCU_GetEnumValues ($ioHash, $paramDef, undef, undef, $value);
			}
			elsif (exists($ct{$parType}) && exists($ct{$parType}{$value})) {
				return $ct{$parType}{$value};
			}
		}
	}
	
	return $value;
}

######################################################################
# Execute substitution list.
# Syntax for single substitution: {#n-n|regexp|text}:newtext
#   mode=0: Substitute regular expression
#   mode=1: Substitute text (for setting statevals)
# newtext can contain ':'. Parameter ${value} in newtext is
# substituted by original value.
# Return (status, value)
#   status=1: value = substituted value
#   status=0: value = original value
######################################################################

sub HMCCU_SubstRule ($$$)
{
	my ($value, $substitutes, $mode) = @_;
	my $rc = 0;

	$substitutes =~ s/\$\{value\}/$value/g;
	
	my @sub_list = split /,/,$substitutes;
	foreach my $s (@sub_list) {
		my ($regexp, $text) = split /:/,$s,2;
		next if (!defined($regexp) || !defined($text));
		if ($regexp =~ /^#([+-]?\d*\.?\d+?)\-([+-]?\d*\.?\d+?)$/) {
			my ($mi, $ma) = ($1, $2);
			if ($value =~ /^\d*\.?\d+?$/ && $value >= $mi && $value <= $ma) {
				$value = $text;
				$rc = 1;
			}
		}
		elsif ($mode == 0 && $value =~ /$regexp/ && $value !~ /^[+-]?\d+$/) {
			my $x = eval { $value =~ s/$regexp/$text/ };
			$rc = 1 if (defined($x));
			last;
		}
		elsif (($mode == 1 || $value =~ /^[+-]?\d+$/) && $value =~ /^$regexp$/) {
			my $x = eval { $value =~ s/^$regexp$/$text/ };
			$rc = 1 if (defined($x));
			last;
		}
	}

	return ($rc, $value);
}

######################################################################
# Substitute datapoint variables in string by datapoint value. The
# value depends on the character preceding the variable name. Syntax
# of variable names is:
#   {$|$$|%|%%}{[cn.]Name}
#   {$|$$|%|%%}[cn.]Name
# %  = Original / raw value
# %% = Previous original / raw value
# $  = Converted / formatted value
# $$ = Previous converted / formatted value
# Parameter dplist is a comma separated list of value keys in format
# [address:]Channel.Datapoint.
######################################################################

sub HMCCU_SubstVariables ($$$)
{
	my ($clhash, $text, $dplist) = @_;
	
	my @varlist = defined($dplist) ? split (',', $dplist) : keys %{$clhash->{hmccu}{dp}};

	HMCCU_Trace ($clhash, 2, "text=$text");
	
	# Substitute datapoint variables by value
	foreach my $dp (@varlist) {
		my ($chn, $dpt) = split (/\./, $dp);
		
		HMCCU_Trace ($clhash, 2, "var=$dp");

		if (defined ($clhash->{hmccu}{dp}{$dp}{VALUES}{OSVAL})) {
			$text =~ s/\$\$\{?$dp\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{OSVAL}/g;
			$text =~ s/\$\$\{?$dpt\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{OSVAL}/g;
		}
		if (defined ($clhash->{hmccu}{dp}{$dp}{VALUES}{SVAL})) {
			$text =~ s/\$\{?$dp\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{SVAL}/g;
			$text =~ s/\$\{?$dpt\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{SVAL}/g;
		}
		if (defined ($clhash->{hmccu}{dp}{$dp}{VALUES}{OVAL})) {
			$text =~ s/\%\%\{?$dp\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{OVAL}/g;
			$text =~ s/\%\%\{?$dpt\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{OVAL}/g;
		}
		if (defined ($clhash->{hmccu}{dp}{$dp}{VALUES}{VAL})) {
			$text =~ s/\%\{?$dp\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{VAL}/g;
			$text =~ s/\%\{?$dpt\}?/$clhash->{hmccu}{dp}{$dp}{VALUES}{VAL}/g;
#			$text =~ s/$dp/$clhash->{hmccu}{dp}{$dp}{VALUES}{VAL}/g;
		}
	}

	HMCCU_Trace ($clhash, 2, "text=$text");
	
	return $text;
}

######################################################################
# Update all datapoint/readings of all client devices matching
# specified regular expression. Update will fail if device is deleted
# or disabled or if ccuflag noReadings is set.
# Parameter devexp is compared to FHEM device name. If ifname is specified
# only devices belonging to interface ifname are updated.
######################################################################

sub HMCCU_UpdateClients ($$$;$$)
{
	my ($hash, $devexp, $ccuget, $ifname, $nonBlock) = @_;
	my $fhname = $hash->{NAME};
	$nonBlock //= HMCCU_IsFlag ($fhname, 'nonBlocking');
	my $dc = 0;
	my $filter = 'ccudevstate=active';
	$filter .= ",ccuif=$ifname" if (defined($ifname));
	$ccuget = AttrVal ($fhname, 'ccuget', 'Value') if ($ccuget eq 'Attr');
	my %ccuDevList = ();
	my @fhemDevList = ();

	my @devlist = HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN)', $devexp, $filter);
	$dc = scalar(@devlist);
	foreach my $d (@devlist) {
		my $ch = $defs{$d};
		my $cn = $ch->{NAME};
		if (!defined($ch->{IODev})) {
			HMCCU_Log ($hash, 2, "Device $cn not updated. I/O device not specified");
			next;
		}
		if (!defined($ch->{ccuaddr})) {
			HMCCU_Log ($hash, 2, "Device $cn not updated. CCU address not specified");
			next;
		}
		if (!HMCCU_IsValidDeviceOrChannel ($hash, $ch->{ccuaddr}, $HMCCU_FL_ADDRESS)) {
			HMCCU_Log ($hash, 2, "Device $cn not updated. Address $ch->{ccuaddr} is not valid");
			next;
		}
		my $name = HMCCU_GetDeviceName ($hash, $ch->{ccuaddr});
		if ($name eq '') {
			HMCCU_Log ($hash, 2, "Device $cn not updated. Can't get CCU device name for address $ch->{ccuaddr}");
			next;
		}
		$ccuDevList{$name} = 1;
		push @fhemDevList, $d;
	}

	my $c = scalar(keys %ccuDevList);
	return HMCCU_Log ($hash, 2, 'Found no devices to update') if ($c == 0);
	HMCCU_Log ($hash, 2, "Updating $c of $dc devices matching devexp=$devexp filter=$filter ".($nonBlock ? 'nonBlocking' : 'blocking'));
	my $ccuDevNameList = join(',', keys %ccuDevList);
	my $fhemDevNameList = join(',', @fhemDevList);
	HMCCU_Log ($hash, 2, "CCU device list 2b updated: $ccuDevNameList");
	HMCCU_Log ($hash, 2, "FHEM device list 2b updated: $fhemDevNameList");
	
	if ($nonBlock) {
		HMCCU_HMScriptExt ($hash, '!GetDatapointsByDevice', { list => $ccuDevNameList, ccuget => $ccuget },
			\&HMCCU_UpdateCB, {
				logCount => 1, devCount => $c,
				fhemDevNameList => $fhemDevNameList, ccuDevNameList => $ccuDevNameList
			});
		return 1;
	}
	else {
		my $response = HMCCU_HMScriptExt ($hash, '!GetDatapointsByDevice',
			{ list => $ccuDevNameList, ccuget => $ccuget });
		return -2 if ($response eq '' || $response =~ /^ERROR:.*/);

		HMCCU_UpdateCB ({
			ioHash => $hash, logCount => 1, devCount => $c,
			fhemDevNameList => $fhemDevNameList, ccuDevNameList => $ccuDevNameList
		}, undef, $response);
		return 1;
	}
}

##########################################################################
# Update parameters in internal device tables and client devices.
# Parameter devices is a hash reference with following keys:
#  {address}
#  {address}{flag}        := [N, D, R] (N=New, D=Deleted, R=Renamed)
#  {address}{addtype}     := [chn, dev] for channel or device
#  {address}{channels}    := Number of channels
#  {address}{name}        := Device or channel name
#  {address}{type}        := Homematic device type
#  {address}{usetype}     := Usage type
#  {address}{interface}   := Device interface ID
#  {address}{firmware}    := Firmware version of device
#  {address}{version}     := Version of RPC device description
#  {address}{rxmode}      := Transmit mode
#  {address}{direction}   := Channel direction: 0=none, 1=sensor, 2=actor
#  {address}{paramsets}   := Comma separated list of supported paramsets
#  {address}{sourceroles} := Link sender roles
#  {address}{targetroles} := Link receiver roles
#  {address}{children}    := Comma separated list of channels
#  {address}{parent}      := Parent device
#  {address}{aes}         := AES flag
# If flag is 'D' the hash must contain an entry for the device address
# and for each channel address.
##########################################################################

sub HMCCU_UpdateDeviceTable ($$)
{
	my ($hash, $devices) = @_;
	my $name = $hash->{NAME};
	my $devcount = 0;
	my $chncount = 0;

	HMCCU_Log ($hash, 3, "Updating device table");
	
	# Update internal device table
	foreach my $da (keys %{$devices}) {
		my $nm = $hash->{hmccu}{dev}{$da}{name} if (defined ($hash->{hmccu}{dev}{$da}{name}));
		$nm = $devices->{$da}{name} if (defined ($devices->{$da}{name}));

		if ($devices->{$da}{flag} eq 'N' && defined($nm)) {
			my $at = '';
			if (defined($devices->{$da}{addtype})) {
				$at = $devices->{$da}{addtype};
			}
			else {
				$at = 'chn' if (HMCCU_IsChnAddr ($da, 0));
				$at = 'dev' if (HMCCU_IsDevAddr ($da, 0));
			}
			if ($at eq '') {
				HMCCU_Log ($hash, 2, "Cannot detect type of address $da. Ignored.");
				next;
			}
			HMCCU_Log ($hash, 2, "Duplicate name for device/channel $nm address=$da in CCU.")			
				if (exists($hash->{hmccu}{adr}{$nm}) && $at ne $hash->{hmccu}{adr}{$nm}{addtype});

			# Updated or new device/channel
			$hash->{hmccu}{dev}{$da}{addtype} = $at;
			$hash->{hmccu}{dev}{$da}{valid}   = 1;

			foreach my $k ('channels', 'type', 'usetype', 'interface', 'version',
				'firmware', 'rxmode', 'direction', 'paramsets', 'sourceroles', 'targetroles',
				'children', 'parent', 'aes') {
				$hash->{hmccu}{dev}{$da}{$k} = $devices->{$da}{$k}
					if (defined($devices->{$da}{$k}));
			}
			
			if (defined($nm)) {
				$hash->{hmccu}{dev}{$da}{name}    = $nm;
				$hash->{hmccu}{adr}{$nm}{address} = $da;
				$hash->{hmccu}{adr}{$nm}{addtype} = $hash->{hmccu}{dev}{$da}{addtype};
				$hash->{hmccu}{adr}{$nm}{valid}   = 1;
			}
		}
		elsif ($devices->{$da}{flag} eq 'D' && exists($hash->{hmccu}{dev}{$da})) {
			# Device deleted, mark as invalid
			$hash->{hmccu}{dev}{$da}{valid} = 0;
			$hash->{hmccu}{adr}{$nm}{valid} = 0 if (defined ($nm));
			my $iface = $hash->{hmccu}{dev}{$da}{interface};
			$hash->{hmccu}{device}{$iface}{$da}{_valid} = 0
				if (exists($hash->{hmccu}{device}{$iface}{$da}));
		}
		elsif ($devices->{$da}{flag} eq 'R' && exists($hash->{hmccu}{dev}{$da})) {
			# Device replaced, change address
			my $na = $devices->{hmccu}{newaddr};
			# Copy device entries and delete old device entries
			foreach my $k (keys %{$hash->{hmccu}{dev}{$da}}) {
				$hash->{hmccu}{dev}{$na}{$k} = $hash->{hmccu}{dev}{$da}{$k};
			}
			$hash->{hmccu}{adr}{$nm}{address} = $na;
			delete $hash->{hmccu}{dev}{$da};
		}
	}

	# Delayed initialization if CCU was not ready during FHEM start
	if (HMCCU_IsDelayedInit ($hash)) {			
		# Initialize pending client devices
		my @cdev = HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN|HMCCURPCPROC)', undef, 'ccudevstate=pending');
		if (scalar(@cdev) > 0) {
			HMCCU_Log ($hash, 2, "Initializing ".scalar(@cdev)." client devices in state 'pending'");
			foreach my $cd (@cdev) {
				my $ch = $defs{$cd};
				my $ct = $ch->{TYPE};
				my $rc = 0;
				if ($ct eq 'HMCCUDEV')        { $rc = HMCCUDEV_InitDevice ($hash, $ch); }
				elsif ($ct eq 'HMCCUCHN')     { $rc = HMCCUCHN_InitDevice ($hash, $ch); }
				elsif ($ct eq 'HMCCURPCPROC') { $rc = HMCCURPCPROC_InitDevice ($hash, $ch); }
				HMCCU_Log ($hash, 3, "Can't initialize client device ".$ch->{NAME}) if ($rc > 0);
			}
		}
		
		$hash->{hmccu}{ccu}{delayed} = 0;
	}

	# Update client devices
	my @devlist = HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN)');
	foreach my $d (@devlist) {
		my $ch = $defs{$d};
		my $ct = $ch->{TYPE};
		next if (!exists($ch->{ccuaddr}));
		my $ca = $ch->{ccuaddr};
		next if (!exists($devices->{$ca}));
		if ($devices->{$ca}{flag} eq 'N') {
			# New device or new device information
			$ch->{ccudevstate} = 'active';
			if ($ct eq 'HMCCUDEV') {
				$ch->{firmware}   = $devices->{$ca}{firmware} // '?';
				$ch->{ccutype}    = $devices->{$ca}{type}     // '?';
			}
			else {
				my ($add, $chn) = HMCCU_SplitChnAddr ($ca);
				$ch->{chntype}  = $devices->{$ca}{usetype}   // '?';
				$ch->{ccutype}  = $devices->{$add}{type}     // '?';
				$ch->{firmware} = $devices->{$add}{firmware} // '?';
			}
			$ch->{ccuname} = $hash->{hmccu}{dev}{$ca}{name}     if (defined($hash->{hmccu}{dev}{$ca}{name}));
			$ch->{ccuif} = $hash->{hmccu}{dev}{$ca}{interface}  if (defined($devices->{$ca}{interface}));
			$ch->{hmccu}{channels} = $hash->{hmccu}{dev}{$ca}{channels}
				if (defined($hash->{hmccu}{dev}{$ca}{channels}));
		}
		elsif ($devices->{$ca}{flag} eq 'D') {
			# Deleted device
			$ch->{ccudevstate} = 'deleted';
		}
		elsif ($devices->{$ca}{flag} eq 'R') {
			# Replaced device
			$ch->{ccuaddr} = $devices->{$ca}{newaddr};
		}
	}
	
	# Update internals of I/O device
	foreach my $adr (keys %{$hash->{hmccu}{dev}}) {
		if (exists ($hash->{hmccu}{dev}{$adr}{addtype})) {
			$devcount++ if ($hash->{hmccu}{dev}{$adr}{addtype} eq 'dev');
			$chncount++ if ($hash->{hmccu}{dev}{$adr}{addtype} eq 'chn');
		}
	}
	$hash->{ccudevices} = $devcount;
	$hash->{ccuchannels} = $chncount;
	
	return ($devcount, $chncount);
}

######################################################################
# Delete device table entries
# New version
######################################################################

sub HMCCU_ResetDeviceTables ($;$$)
{
	my ($hash, $iface, $address) = @_;
	
	if (defined($iface)) {
		if (defined($address)) {
			$hash->{hmccu}{device}{$iface}{$address} = ();
		}
		else {
			$hash->{hmccu}{device}{$iface} = ();
		}
	}
	else {
		$hash->{hmccu}{device} = ();
		$hash->{hmccu}{model} = ();
		$hash->{hmccu}{snd} = ();
		$hash->{hmccu}{rcv} = ();
	}
}

######################################################################
# Create FHEM device(s) for CCU device(s)
######################################################################

sub HMCCU_CreateFHEMDevices ($@)
{
	my ($hash, $devSpec, $devPrefix, $devSuffix, $devFormat, $defOpts, $ah) = @_;
	
	# Statistics
	#
	# {statsValue}{devName} = addr.ccuName
	#
	# {notDetected}{$ccuDevName}: CCU device with $devName not detected
	# {notSupported}{$ccuDevName}: CCU device type is not supported by create commands
	# {fhemExists}{$fhemDevName}: FHEM device with $devName already exists
	# {devDefined}{$fhemDevName}: FHEM device for $devAdd already exists
	# {defFailed}{$fhemDevName}: Device definition failed
	# {defSuccess}{$fhemDevName}: Device defined
	# {attrFailed}{$fhemDevName.$attr}: Attribute setting failed
	my %cs = ();

	foreach my $iface (keys %{$hash->{hmccu}{device}}) {
		foreach my $address (keys %{$hash->{hmccu}{device}{$iface}}) {
			my $ccuName = $hash->{hmccu}{device}{$iface}{$address}{_name};
			next if ($hash->{hmccu}{device}{$iface}{$address}{_addtype} ne 'dev' ||
				HMCCU_ExprNotMatch ($ccuName, $devSpec, 1));

			my $ccuType = $hash->{hmccu}{device}{$iface}{$address}{_model};
			if ($ccuType =~ /^(HM-RCV-50|HmIP-RCV-50)$/) {
				$cs{notSupported}{$ccuName} = "$address [$ccuName]";
				next;
			}
			
			# Detect FHEM device type
			my $detect = HMCCU_DetectDevice ($hash, $address, $iface);
			if (!defined($detect)) {		
				$cs{notDetected}{$ccuName} = "$address [$ccuName]";
				next;
			}

			my $defMod = $detect->{defMod};
			my $defAdd = $detect->{defAdd};

			# Build FHEM device name
			my $devName = HMCCU_MakeDeviceName ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuName);

			if ($detect->{level} == 0) {
				# Unknown HMCCUDEV device
				HMCCU_CreateDevice ($hash, $ccuName, $devName, $defMod, $defAdd, $defOpts, $ah, \%cs);
			}
			elsif ($detect->{level} == 1) {
				# Simple HMCCUCHN device
				HMCCU_CreateDevice ($hash, $ccuName, $devName, $defMod, $defAdd, $defOpts, $ah, \%cs);
			}
			elsif ($detect->{level} == 2) {
				# Multiple identical channels
				if ($defOpts =~ /forcedev/i) {
					# Force creation of HMCCUDEV
					$ah->{statedatapoint} = $detect->{defSDP} if ($detect->{defSCh} != -1 && $detect->{stateRoleCount} > 1);
					$ah->{controldatapoint} = $detect->{defCDP} if ($detect->{defCCh} != -1 && $detect->{controlRoleCount} > 1);
					HMCCU_CreateDevice ($hash, $ccuName, $devName, 'HMCCUDEV', $defAdd, $defOpts, $ah, \%cs);
				}
				else {
					HMCCU_BuildGroupAttr ($hash, $address, $ccuType, $ah) if ($detect->{controlRoleCount}+$detect->{stateRoleCount} > 1);

					# Create a HMCCUCHN for each channel
					if ($detect->{controlRoleCount} > 0) {
						# First create a HMCCUCHN for each control channel
						foreach my $cc (keys %{$detect->{controlRole}}) {
							my $ccuChnName = $hash->{hmccu}{device}{$iface}{"$address:$cc"}{_name};
							my $devChnName = HMCCU_MakeDeviceName ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuChnName);
							HMCCU_CreateDevice ($hash, $ccuChnName, $devChnName, $defMod, "$defAdd:$cc", $defOpts, $ah, \%cs);
						}
					}
					# Create a HMCCUCHN for each channel without control datapoint
					foreach my $sc (keys %{$detect->{stateRole}}) {
						if (!exists($detect->{controlRole}{$sc})) {
							my $ccuChnName = $hash->{hmccu}{device}{$iface}{"$address:$sc"}{_name};
							my $devChnName = HMCCU_MakeDeviceName ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuChnName);
							HMCCU_CreateDevice ($hash, $ccuChnName, $devChnName, $defMod, "$defAdd:$sc", $defOpts, $ah, \%cs);
						}
					}
				}
			}
			elsif ($detect->{level} == 3 || $detect->{level} == 4) {
				# Multiple roles
				$ah->{statedatapoint} = $detect->{defSDP} if ($detect->{defSCh} != -1 && $detect->{stateRoleCount} > 1);
				$ah->{controldatapoint} = $detect->{defCDP} if ($detect->{defCCh} != -1 && $detect->{controlRoleCount} > 1);
				HMCCU_CreateDevice ($hash, $ccuName, $devName, $defMod, $defAdd, $defOpts, $ah, \%cs);
			}
			elsif ($detect->{level} == 5) {
				# 4-channel role patterns, create a HMCCUDEV for each occurrence
				my $rpCount = scalar(keys %{$detect->{rolePattern}});
				HMCCU_BuildGroupAttr ($hash, $address, $ccuType, $ah, '%n') if ($detect->{rolePatternCount} > 1);
				HMCCU_Log ($hash, 3, "4-channel role patterns found $rpCount");
				my @rpChannels = map { ($_, $_+1, $_+2, $_+3) } keys %{$detect->{rolePattern}};
				foreach my $firstChannel (keys %{$detect->{rolePattern}}) {
					my $ccuChnName = $hash->{hmccu}{device}{$iface}{"$address:$firstChannel"}{_name};
					my $devChnName = HMCCU_MakeDeviceName ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuChnName);
					my $defPar = '';
					$defPar .= ' sd='.$detect->{rolePattern}{$firstChannel}{stateChannel}.'.'.$detect->{rolePattern}{$firstChannel}{stateDatapoint}
						if (exists($detect->{rolePattern}{$firstChannel}{stateChannel}));
					$defPar .= ' cd='.$detect->{rolePattern}{$firstChannel}{controlChannel}.'.'.$detect->{rolePattern}{$firstChannel}{controlDatapoint}
						if (exists($detect->{rolePattern}{$firstChannel}{controlChannel}));

					# Reset attributes (currently statedatapoint and controldatapoint are not needed)
					delete $ah->{statedatapoint} if (exists($ah->{statedatapoint}));
					delete $ah->{controldatapoint} if (exists($ah->{controldatapoint}));
					delete $ah->{ccureadingfilter} if (exists($ah->{ccureadingfilter}));

					# Build list of channel numbers for reading filter
					my @rfChannels = map { HMCCU_IsArrayElement ($_, @rpChannels) ? () : $_ } keys %{$detect->{stateRole}};
					push @rfChannels, $detect->{rolePattern}{$firstChannel}{stateChannel} // ();
					push @rfChannels, $detect->{rolePattern}{$firstChannel}{controlChannel} // ();
					$ah->{ccureadingfilter} = join(',',sort @rfChannels).'..*';

					HMCCU_CreateDevice ($hash, $ccuChnName, $devChnName, $defMod, $defAdd, $defOpts.$defPar, $ah, \%cs);
				}
			}
		}
	}
	
	return \%cs;
}

######################################################################
# Create a new FHEM HMCCUCHN or HMCCUDEV device
# Parameters:
#   ccuName - Name of device in CCU
#   devName - Name of new FHEM device
#   defMod  - Module for device definition
#   defAdd  - Address for device definition
#   defOpts - String with additional command options
#   ah      - Hash reference of device attributes
#   cs      - Hash reference with device create results
# Return values:
#   0 - Error(s)
#   1 - Success (even if attributes cannot be set)
# Results are stored in hash $cs. Value is $defAdd.$ccuName:
#   {fhemExists}{$devName}: FHEM device with $devName already exists
#   {devDefined}{$devName}: FHEM device for $devAdd already exists
#   {defFailed}{$devName}: Device definition failed
#   {defSuccess}{$devName}: Device defined
#   {attrFailed}{$devName.$attr}: Attribute setting failed
######################################################################

sub HMCCU_CreateDevice ($@)
{
	my ($hash, $ccuName, $devName, $defMod, $defAdd, $defOpts, $ah, $cs) = @_;

	# Check for existing FHEM devices with same name
	if (exists($defs{$devName})) {
		$cs->{fhemExists}{$devName} = "$defAdd [$ccuName]";
		return 0;
	}

	# Check for existing FHEM devices for CCU address (HMCCUCHN only)
	if ($defMod eq 'HMCCUCHN' && HMCCU_ExistsClientDevice ($defAdd, $defMod)) {
		$cs->{devDefined}{$devName} = "$defAdd [$ccuName]";
		return 0; 
	}

	# Define new client device
	$defOpts //= '';
	my $cmd = "$devName $defMod $defAdd";
	$cmd .= " $defOpts" if ($defOpts ne '');
	$cmd .= " iodev=$hash->{NAME}" if ($defAdd =~ /^INT[0-9]+$/);
	my $ret = CommandDefine (undef, $cmd);
	if ($ret) {
		HMCCU_Log ($hash, 2, "Define command failed $cmd. $ret");
		$cs->{defFailed}{$devName} = "$defAdd [$ccuName]";
		return 0;
	}
	else {
		$cs->{defSuccess}{$devName} = "$defAdd [$ccuName]";

		# Set device attributes
#		HMCCU_SetInitialAttributes ($hash, $devName);
		foreach my $da (keys %$ah) {
			$ret = CommandAttr (undef, "$devName $da ".$ah->{$da});
			if ($ret) {
				HMCCU_Log ($hash, 2, "Attr command failed $devName $da ".$ah->{$da}.". $ret");
				$cs->{attrFailed}{$devName.$da} = "$defAdd [$ccuName]";
			}
		}
	}

	return 1;
}

######################################################################
# Build group attribute
######################################################################

sub HMCCU_BuildGroupAttr ($$$$;$)
{
	my ($ioHash, $address, $ccuType, $ah, $groupName) = @_;

	$groupName //= AttrVal ($ioHash->{NAME}, 'createDeviceGroup', '');
	if ($groupName ne '') {
		my $devName = HMCCU_GetDeviceName ($ioHash, $address);
		$groupName =~ s/%n/$devName/g;
		$groupName =~ s/%a/$address/g;
		$groupName =~ s/%t/$ccuType/g;
		$ah->{group} = $groupName;
		return 1;
	}

	return 0;
}

######################################################################
# Create device name
######################################################################

sub HMCCU_MakeDeviceName ($$$$$)
{
	my ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuName) = @_;

	my %umlaute = ("ä" => "ae", "Ä" => "Ae", "ü" => "ue", "Ü" => "Ue", "ö" => "oe", "Ö" => "Oe", "ß" => "ss" );
	my $umlautkeys = join ("|", keys(%umlaute));

	my $devName = $devPrefix.$devFormat.$devSuffix;
	$devName =~ s/%n/$ccuName/g;
	$devName =~ s/%a/$defAdd/g;
	$devName =~ s/($umlautkeys)/$umlaute{$1}/g;
	$devName =~ s/[^A-Za-z\d_\.]+/_/g;

	return $devName;
}

######################################################################
# Add new CCU or FHEM device or channel
# If $devName is undef, a new device or channel will be added to IO
# device if it doesn't exist.
# This function is called during device definition in HMCCUDEV and
# HMCCUCHN.
######################################################################

sub HMCCU_AddDevice ($$$;$)
{
	my ($ioHash, $iface, $address, $devName) = @_;
	
	if (defined($devName)) {
		# Device description must exist
		return if (!exists($ioHash->{hmccu}{device}{$iface}{$address}));
		my @devList = ();
		if (defined($ioHash->{hmccu}{device}{$iface}{$address}{_fhem})) {
			@devList = split (',', $ioHash->{hmccu}{device}{$iface}{$address}{_fhem});
			# Prevent duplicate device names
			foreach my $d (@devList) { return if ($d eq $devName); }
		}
	
		push @devList, $devName;
		$ioHash->{hmccu}{device}{$iface}{$address}{_fhem} = join(',', @devList);
	}
	elsif (!exists($ioHash->{hmccu}{device}{$iface}{$address})) {
		my ($rpcDevice, undef) = HMCCU_GetRPCDevice ($ioHash, 0, $iface);
		if ($rpcDevice ne '') {
			my $rpcHash = $defs{$rpcDevice};
			HMCCURPCPROC_GetDeviceDesc ($rpcHash, $address);
			HMCCURPCPROC_GetParamsetDesc ($rpcHash, $address);
		}
	}
}

######################################################################
# Delete CCU or FHEM device or Channel
# If $devName is undef, a device or a channel will be removed from
# IO device.
######################################################################

sub HMCCU_RemoveDevice ($$$;$)
{
	my ($ioHash, $iface, $address, $devName) = @_;
	
	return if (!exists($ioHash->{hmccu}{device}{$iface}{$address}));

	if (defined($devName)) {
		if (defined($ioHash->{hmccu}{device}{$iface}{$address}{_fhem})) {
			my @devList = grep { $_ ne $devName } split(',', $ioHash->{hmccu}{device}{$iface}{$address}{_fhem});
			$ioHash->{hmccu}{device}{$iface}{$address}{_fhem} = scalar(@devList) > 0 ?
				join(',', @devList) : undef;
		}
	}
	elsif (exists($ioHash->{hmccu}{device}{$iface}{$address})) {
		delete $ioHash->{hmccu}{device}{$iface}{$address};
	}
}

######################################################################
# Update client device or channel
# Store receiver, sender
######################################################################

sub HMCCU_UpdateDevice ($$)
{
	my ($ioHash, $clHash) = @_;
	
	return if (!exists($clHash->{ccuif}) || !exists($clHash->{ccuaddr}));
	
	my $clType  = $clHash->{TYPE};
	my $address = $clHash->{ccuaddr};
	my $iface   = $clHash->{ccuif};
	my ($da, $dc) = HMCCU_SplitChnAddr ($address);
	
	# Update device information
	if (exists($ioHash->{hmccu}{device}{$iface}{$da})) {
		$clHash->{firmware} = $ioHash->{hmccu}{device}{$iface}{$da}{FIRMWARE} // '?';
	}

	# Update link receivers
	if (exists($ioHash->{hmccu}{snd}{$iface}{$da})) {
		delete $clHash->{receiver} if (exists($clHash->{receiver}));
		my @rcvList = ();

		foreach my $c (sort keys %{$ioHash->{hmccu}{snd}{$iface}{$da}}) {
#			next if ($clType eq 'HMCCUCHN' && "$c" ne "$dc");
			foreach my $r (keys %{$ioHash->{hmccu}{snd}{$iface}{$da}{$c}}) {
				my ($la, $lc) = HMCCU_SplitChnAddr ($r);
				next if ($la eq $da);	# Ignore link if receiver = current device
				my @rcvNames = HMCCU_GetDeviceIdentifier ($ioHash, $r, $iface);
				my $rcvFlags = HMCCU_FlagsToStr ('peer', 'FLAGS',
					$ioHash->{hmccu}{snd}{$iface}{$da}{$c}{$r}{FLAGS}, ',');
				push @rcvList, map { $_.($rcvFlags ne 'OK' ? " [".$rcvFlags."]" : '') } @rcvNames;	
			}
		}

		$clHash->{receiver} = join (',', HMCCU_Unique (@rcvList)) if (scalar(@rcvList) > 0);
	}

	# Update link senders
	if (exists($ioHash->{hmccu}{rcv}{$iface}{$da})) {
		delete $clHash->{sender} if (exists($clHash->{sender}));
		my @sndList = ();

		foreach my $c (sort keys %{$ioHash->{hmccu}{rcv}{$iface}{$da}}) {
#			next if ($clType eq 'HMCCUCHN' && "$c" ne "$dc");
			foreach my $s (keys %{$ioHash->{hmccu}{rcv}{$iface}{$da}{$c}}) {
				my ($la, $lc) = HMCCU_SplitChnAddr ($s);
				next if ($la eq $da);	# Ignore link if sender = current device
				my @sndNames = HMCCU_GetDeviceIdentifier ($ioHash, $s, $iface);
				my $sndFlags = HMCCU_FlagsToStr ('peer', 'FLAGS',
					$ioHash->{hmccu}{snd}{$iface}{$da}{$c}{$s}{FLAGS}, ',');
				push @sndList, map { $_.($sndFlags ne 'OK' ? " [".$sndFlags."]" : '') } @sndNames; 
			}
		}

	 	$clHash->{sender} = join (',', HMCCU_Unique (@sndList)) if (scalar(@sndList) > 0);
	}
}

######################################################################
# Update device roles
######################################################################

sub HMCCU_UpdateDeviceRoles ($$;$$)
{
	my ($ioHash, $clHash, $iface, $address) = @_;

	my $clType = $clHash->{TYPE};	

	$iface //= $clHash->{ccuif};
	$address //= $clHash->{ccuaddr};
	return if (!defined($address));

	my $dd = HMCCU_GetDeviceDesc ($ioHash, $address, $iface);
	if (!defined($dd)) {
		HMCCU_Log ($clHash, 2, "Can't get device description for $address ".stacktraceAsString(undef));
		return;
	}

	if ($clType eq 'HMCCUCHN' && defined($dd->{TYPE})) {
		$clHash->{hmccu}{role} = $dd->{INDEX}.':'.$dd->{TYPE};
		$clHash->{hmccu}{roleChannels}{$dd->{TYPE}} = $dd->{INDEX};
		my $pdd = HMCCU_GetDeviceDesc ($ioHash, $dd->{PARENT}, $iface);
		if (defined($pdd)) {
			$clHash->{ccutype}    = defined($pdd->{TYPE}) && $pdd->{TYPE} ne '' ? $pdd->{TYPE} : '?';
			$clHash->{ccusubtype} = defined($pdd->{SUBTYPE}) && $pdd->{SUBTYPE} ne '' ? $pdd->{SUBTYPE} : $clHash->{ccutype};
		}
	}
	elsif ($clType eq 'HMCCUDEV' && defined($dd->{CHILDREN})) {
		my @roles = ();
		foreach my $c (split(',', $dd->{CHILDREN})) {
			my $cdd = HMCCU_GetDeviceDesc ($ioHash, $c, $iface);
			if (defined($cdd) && defined($cdd->{TYPE}) && $cdd->{TYPE} ne '') {
				push @roles, $cdd->{INDEX}.':'.$cdd->{TYPE};
				if (defined($clHash->{hmccu}{roleChannels}{$cdd->{TYPE}})) {
					$clHash->{hmccu}{roleChannels}{$cdd->{TYPE}} .= ",$cdd->{INDEX}";
				}
				else {
					$clHash->{hmccu}{roleChannels}{$cdd->{TYPE}} = $cdd->{INDEX};
				}
			}
		}
		$clHash->{hmccu}{role} = join(',', @roles) if (scalar(@roles) > 0);
		$clHash->{ccutype}     = defined($dd->{TYPE}) && $dd->{TYPE} ne '' ? $dd->{TYPE} : '?';
		$clHash->{ccusubtype}  = defined($dd->{SUBTYPE}) && $dd->{SUBTYPE} ne '' ? $dd->{SUBTYPE} : $clHash->{ccutype};
	}
}

######################################################################
# Rename a client device
######################################################################

sub HMCCU_RenameDevice ($$$)
{
	my ($ioHash, $clHash, $oldName) = @_;
	
	return 0 if (!defined($ioHash) || !defined($clHash) || !exists($clHash->{ccuif}) ||
		!exists($clHash->{ccuaddr}));
	
	my $name = $clHash->{NAME};
	my $iface = $clHash->{ccuif};
	my $address = $clHash->{ccuaddr};
	
	return 0 if (!exists($ioHash->{hmccu}{device}{$iface}{$address}));
	
	if (exists($ioHash->{hmccu}{device}{$iface}{$address}{_fhem})) {
		my @devList = map { $_ eq $oldName ? $name : $_ } split(',', $ioHash->{hmccu}{device}{$iface}{$address}{_fhem});
		$ioHash->{hmccu}{device}{$iface}{$address}{_fhem} = join(',', @devList);
	}
	else {
		$ioHash->{hmccu}{device}{$iface}{$address}{_fhem} = $name;
	}
	
	# Update links, but not the roles
	HMCCU_UpdateDevice ($ioHash, $clHash);
	
	return 1;
}

######################################################################
# Initialize user attributes statedatapoint and controldatapoint
######################################################################

sub HMCCU_SetSCAttributes ($$;$)
{
	my ($ioHash, $clHash, $detect) = @_;

	my $name = $clHash->{NAME} // return;
	my $type = $clHash->{TYPE} // return;
	my $ccuType = $clHash->{ccutype} // return;
	my $ccuAddr = $clHash->{ccuaddr} // return;
	my $ccuIf = $clHash->{ccuif} // return;

	# Get readable and writeable datapoints
	my @dpWrite = ();
	my @dpRead = ();
	my ($da, $dc) = HMCCU_SplitChnAddr ($ccuAddr);
	my $dpWriteCnt = HMCCU_GetValidParameters ($clHash, $dc, 'VALUES', 2, \@dpWrite, 1);
	my $dpReadCnt  = HMCCU_GetValidParameters ($clHash, $dc, 'VALUES', 5, \@dpRead, 1);

	# Detect device and initialize attribute lists for statedatapoint and controldatapoint
	my @userattr = grep (!/statedatapoint|controldatapoint/, split(' ', $modules{$clHash->{TYPE}}{AttrList}));
	push @userattr, 'statedatapoint:select,'.join(',', sort @dpRead) if ($dpReadCnt > 0);
	push @userattr, 'controldatapoint:select,'.join(',', sort @dpWrite) if ($dpWriteCnt > 0);
	$clHash->{hmccu}{detect} = defined($detect) ? $detect->{level} : 0;
	
	# Make sure that generic attributes are available, if no role attributes found
	push @userattr, 'statedatapoint' if (!grep(/statedatapoint/, @userattr));
	push @userattr, 'controldatapoint' if (!grep(/controldatapoint/, @userattr));

	setDevAttrList ($name, join(' ', @userattr)) if (scalar(@userattr) > 0);
}

######################################################################
# Return role of a channel as stored in device hash
# Parameter chnNo is ignored for HMCCUCHN devices. If chnNo is not
# specified for a HMCCUDEV device, the control channel is used.
# Returns role name or empty string if role cannot be detected.
######################################################################

sub HMCCU_GetChannelRole ($;$)
{
	my ($clHash, $chnNo) = @_;
	
	return '' if (!defined($clHash->{hmccu}{role}) || $clHash->{hmccu}{role} eq '');

	if (!defined($chnNo) || $chnNo eq '' || $chnNo == -1) {
		if ($clHash->{TYPE} eq 'HMCCUCHN') {
			my ($ad, $cc) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
			$chnNo = $cc;
		}
	}
	if (defined($chnNo) && $chnNo ne '' && $chnNo != -1) {
		foreach my $role (split(',', $clHash->{hmccu}{role})) {
			my ($c, $r) = split(':', $role);
			return $r if (defined($r) && "$c" eq "$chnNo");
		}
	}
	
	return '';
}

######################################################################
# Return role(s) of a device or a channel identified by address
# Parameters:
#   $mode: 0 = All roles, 1 = Only supported roles
######################################################################

sub HMCCU_GetDeviceRoles ($$$;$)
{
	my ($ioHash, $iface, $address, $mode) = @_;
	$mode //= 0;	# By default get all roles
	my @roles = ();
	
	if (exists($ioHash->{hmccu}{device}{$iface}{$address})) {
		if ($ioHash->{hmccu}{device}{$iface}{$address}{_addtype} eq 'dev') {
			foreach my $chAddress (split(',', $ioHash->{hmccu}{device}{$iface}{$address}{CHILDREN})) {
				my $r = $ioHash->{hmccu}{device}{$iface}{$chAddress}{TYPE};
				push @roles, $r if (exists($ioHash->{hmccu}{device}{$iface}{$chAddress}) &&
					$ioHash->{hmccu}{device}{$iface}{$chAddress}{_addtype} eq 'chn' &&
					($mode == 0 || ($mode == 1 && exists($HMCCU_STATECONTROL->{$r}))));
			}
		}
		elsif ($ioHash->{hmccu}{device}{$iface}{$address}{_addtype} eq 'chn') {
			my $r = $ioHash->{hmccu}{device}{$iface}{$address}{TYPE};
			push @roles, $r if ($mode == 0 || ($mode == 1 && exists($HMCCU_STATECONTROL->{$r})));
		}
	}
	
	return @roles;
}

######################################################################
# Get device configuration for all interfaces from CCU
######################################################################

sub HMCCU_GetDeviceConfig ($)
{
	my ($ioHash, $ifaceExpr) = @_;
	
	my ($cDev, $cPar, $cLnk) = (0, 0, 0);
	my $c = 0;
	
	my $interfaces = HMCCU_GetRPCInterfaceList ($ioHash, 0);
	my @ifList = keys %$interfaces;
	HMCCU_Log ($ioHash, 2, "Reading device configuration for interfaces ".join(',', @ifList));
	foreach my $iface (@ifList) {
		my ($rpcdev, $save) = HMCCU_GetRPCDevice ($ioHash, 1, $iface);
		if ($rpcdev ne '') {
			my $rpcHash = $defs{$rpcdev};
			HMCCURPCPROC_Connect ($rpcHash, $ioHash);
			HMCCU_Log ($ioHash, 5, "Reading Device Descriptions for interface $iface");
			$c = HMCCURPCPROC_GetDeviceDesc ($rpcHash);
			HMCCU_Log ($ioHash, 5, "Read $c Device Descriptions for interface $iface");
			$cDev += $c;
			HMCCU_Log ($ioHash, 5, "Reading Paramset Descriptions for interface $iface");
			$c = HMCCURPCPROC_GetParamsetDesc ($rpcHash);
			HMCCU_Log ($ioHash, 5, "Read $c Paramset Descriptions for interface $iface");
			$cPar += $c;
			HMCCU_Log ($ioHash, 5, "Reading Peer Descriptions for interface $iface");
			$c = HMCCURPCPROC_GetPeers ($rpcHash);
			HMCCU_Log ($ioHash, 5, "Read $c Peer Descriptions for interface $iface");
			$cLnk += $c;
			HMCCURPCPROC_Disconnect ($rpcHash, $ioHash);
		}
		else {
			HMCCU_Log ($ioHash, 2, "No RPC device found for interface $iface. Can't read device config.");
		}
	}
	HMCCU_Log ($ioHash, 2, "Read descriptions of $cDev devices, $cPar paramsets, $cLnk links");

	my @ccuDevList = ();
	my @ccuSuppDevList = ();
	my %ccuSuppTypes = ();
	my %ccuNotSuppTypes = ();
	@ifList = sort keys %{$ioHash->{hmccu}{device}};
	HMCCU_Log ($ioHash, 2, "Detecting devices of interfaces ".join(',', @ifList));
	foreach my $di (@ifList) {
		foreach my $da (sort keys %{$ioHash->{hmccu}{device}{$di}}) {
			next if ($ioHash->{hmccu}{device}{$di}{$da}{_addtype} ne 'dev');
			my $devName = $ioHash->{hmccu}{device}{$di}{$da}{_name};
			my $devModel = $ioHash->{hmccu}{device}{$di}{$da}{_model};
			if ($devName =~ / /) {
				$devName = qq("$devName");
				$devName =~ s/ /#/g;
			}
			push @ccuDevList, $devName;
			my $detect = HMCCU_DetectDevice ($ioHash, $da, $di);
			if (defined($detect)) {
				if ($da ne 'HmIP-RCV-1' && $da ne 'BidCoS-RF') {
					push @ccuSuppDevList, $devName;
					$ccuSuppTypes{$devModel} = 1;
					HMCCU_Log ($ioHash, 5, "Device $da $devName detected");
				}
				else {
					HMCCU_Log ($ioHash, 5, "Device $da $devName ignored");
				}
			}
			else {
				$ccuNotSuppTypes{$devModel} = 1;
				HMCCU_Log ($ioHash, 5, "Device $da $devName not detected");
			}
		}
	}
	$ioHash->{hmccu}{ccuDevList} = join(',', sort @ccuDevList);
	$ioHash->{hmccu}{ccuSuppDevList} = join(',', sort @ccuSuppDevList);
	$ioHash->{hmccu}{ccuTypes}{supported} = join(',', sort keys %ccuSuppTypes);
	$ioHash->{hmccu}{ccuTypes}{unsupported} = join(',', sort keys %ccuNotSuppTypes);
	
	# Set CCU firmware version
	if (exists($ioHash->{hmccu}{device}{'BidCos-RF'}) && exists($ioHash->{hmccu}{device}{'BidCos-RF'}{'BidCoS-RF'})) {
		$ioHash->{firmware} = $ioHash->{hmccu}{device}{'BidCos-RF'}{'BidCoS-RF'}{FIRMWARE} // '?';
	}

	# Get defined FHEM devices	
	my @devList = HMCCU_FindClientDevices ($ioHash, '(HMCCUDEV|HMCCUCHN)');

	# Add devices
	foreach my $d (@devList) {
		my $clHash = $defs{$d};
		if (exists($clHash->{ccuaddr}) && exists($clHash->{ccuif})) {
			HMCCU_AddDevice ($ioHash, $clHash->{ccuif}, $clHash->{ccuaddr}, $d);
		}
	}

	# Update FHEM devices
	foreach my $d (@devList) {
		my $clHash = $defs{$d};
		my $name = $clHash->{NAME};
		
		if (!exists($clHash->{ccuaddr})) {
			HMCCU_Log ($ioHash, 2, "Disabling client device $name because CCU address is missing. Does the device exist on CCU?");
			CommandAttr (undef, "$name disable 1");
			$clHash->{ccudevstate} = 'inactive';
			next;
		}

		HMCCU_SetSCAttributes ($ioHash, $clHash);
		HMCCU_UpdateDevice ($ioHash, $clHash);
		HMCCU_UpdateDeviceRoles ($ioHash, $clHash);
		HMCCU_SetDefaultSCDatapoints ($ioHash, $clHash);
		HMCCU_UpdateRoleCommands ($ioHash, $clHash);
	}
	
	return ($cDev, $cPar, $cLnk);
}

######################################################################
# Add new device.
# Arrays are converted to a comma separated string. Device description
# is stored in $hash->{hmccu}{device}.
# Address type and name of interface will be added to standard device
# description in hash elements "_addtype" and "_interface".
# Parameters:
#   $desc  - Hash reference with RPC device description.
#   $key   - Key of device description hash (i.e. "ADDRESS").
#   $iface - RPC interface name (i.e. "BidCos-RF").
######################################################################

sub HMCCU_AddDeviceDesc ($$$$)
{
	my ($hash, $desc, $key, $iface) = @_;

	return 0 if (!exists($desc->{$key}));

	my $k = $desc->{$key};

	foreach my $p (keys %$desc) {
		if (ref($desc->{$p}) eq 'ARRAY') {
			$hash->{hmccu}{device}{$iface}{$k}{$p} = join(',', @{$desc->{$p}});
		}
		else {
			my $d = $desc->{$p};
			$d =~ s/ /,/g;
			$hash->{hmccu}{device}{$iface}{$k}{$p} = $d;
		}
	}
	
	$hash->{hmccu}{device}{$iface}{$k}{_interface} = $iface;
	if (defined($desc->{PARENT}) && $desc->{PARENT} ne '') {
		$hash->{hmccu}{device}{$iface}{$k}{_addtype} = 'chn';
		$hash->{hmccu}{device}{$iface}{$k}{_fw_ver} = $hash->{hmccu}{device}{$iface}{$desc->{PARENT}}{_fw_ver};
		$hash->{hmccu}{device}{$iface}{$k}{_model} = $hash->{hmccu}{device}{$iface}{$desc->{PARENT}}{_model};
		$hash->{hmccu}{device}{$iface}{$k}{_name} = HMCCU_GetChannelName ($hash, $k);
	}
	else {
		$hash->{hmccu}{device}{$iface}{$k}{_addtype} = 'dev';
		my $fw_ver = $desc->{FIRMWARE};
		$fw_ver =~ s/[-\.]/_/g;
		$hash->{hmccu}{device}{$iface}{$k}{_fw_ver} = $fw_ver."-".$desc->{VERSION};
		$hash->{hmccu}{device}{$iface}{$k}{_model} = $desc->{TYPE};
		$hash->{hmccu}{device}{$iface}{$k}{_name} = HMCCU_GetDeviceName ($hash, $k);
		$hash->{hmccu}{device}{$iface}{$k}{_valid} = 1;
	}

	return 1;
}

######################################################################
# Get device description.
# Parameters:
#   $hash - Hash reference of IO device.
#   $address - Address of device or channel. Accepts a channel address
#      with channel number 'd' as an alias for device address.
#   $iface - Interface name (optional).
# Return hash reference for device description or undef on error.
######################################################################

sub HMCCU_GetDeviceDesc ($$;$)
{
	my ($hash, $address, $iface) = @_;
	
	return undef if (!exists($hash->{hmccu}{device}));

	if (!defined($address)) {
		HMCCU_Log ($hash, 2, "Address not defined for device\n".stacktraceAsString(undef));
		return undef;
	}
	
	my @ifaceList = ();
	if (defined($iface)) {
		push (@ifaceList, $iface);
	}
	else {
		push (@ifaceList, keys %{$hash->{hmccu}{device}});	
	}
	
	$address =~ s/:d//;
	foreach my $i (@ifaceList) {
		return $hash->{hmccu}{device}{$i}{$address}
			if (exists($hash->{hmccu}{device}{$i}{$address}));
	}
	
	return undef;
}

######################################################################
# Get list of device identifiers
# CCU device names are preceeded by "ccu:".
# If no names were found, the address is returned.
######################################################################

sub HMCCU_GetDeviceIdentifier ($$;$$)
{
	my ($ioHash, $address, $iface, $chnNo) = @_;
	
	my @idList = ();
	my ($da, $dc) = HMCCU_SplitChnAddr ($address);
# 	my $c = defined($chnNo) ? ' #'.$chnNo : '';
	my $c = '';
	
	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $address, $iface);
	if (defined($devDesc)) {
		if (defined($devDesc->{_fhem})) {
			push @idList, map { $_.$c } split(',', $devDesc->{_fhem});
		}
		elsif (defined($devDesc->{PARENT}) && $devDesc->{PARENT} ne '') {
			push @idList, HMCCU_GetDeviceIdentifier ($ioHash, $devDesc->{PARENT}, $iface, $dc);
		}
		elsif (defined($devDesc->{_name})) {
			push @idList, "ccu:".$devDesc->{_name};
		}
	}
	
	return scalar(@idList) > 0 ? @idList : ($address);
}

######################################################################
# Convert device description to string
# Parameter $object can be a device or channel address or a client
# device hash reference.
######################################################################

sub HMCCU_DeviceDescToStr ($$)
{
	my ($ioHash, $object) = @_;
	
	my $result = '';
	my $address;
	my $iface;
		
	if (ref($object) eq 'HASH') {
		$address = $object->{ccuaddr};
		$iface = $object->{ccuif};
	}
	else {
		$address = $object;
	}
	
	my ($devAddr, $chnNo) = HMCCU_SplitChnAddr ($address);
	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $devAddr, $iface);
		return undef if (!defined($devDesc));
	my @addList = ($devAddr);
	push (@addList, split (',', $devDesc->{CHILDREN}))
		if (defined($devDesc->{CHILDREN}) && $devDesc->{CHILDREN} ne '');
	
	foreach my $a (@addList) {
		my ($d, $c) = HMCCU_SplitChnAddr ($a);
		next if ($chnNo ne '' && "$c" ne '0' && "$c" ne "$chnNo" && $c ne '');		

		$devDesc = HMCCU_GetDeviceDesc ($ioHash, $a, $iface);
		return undef if (!defined($devDesc));

		my $channelType = $devDesc->{TYPE};
		my $status = exists($HMCCU_STATECONTROL->{$channelType}) ? ' known' : '';
		$result .= $a eq $devAddr ? "Device $a" : "Channel $a";
		$result .= " $devDesc->{_name} [$channelType]$status<br/>";
		foreach my $n (sort keys %{$devDesc}) {
			next if ($n =~ /^_/ || $n =~ /^(ADDRESS|TYPE|INDEX|VERSION)$/ ||
				!defined($devDesc->{$n}) || $devDesc->{$n} eq '');
			$result .= "&nbsp;&nbsp;$n: ".HMCCU_FlagsToStr ('device', $n, $devDesc->{$n}, ',', '')."<br/>";
		}
	}
	
	return $result;
}

######################################################################
# Convert parameter set description to string
# Parameter $object can be an address or a reference to a client hash.
######################################################################

sub HMCCU_ParamsetDescToStr ($$)
{
	my ($ioHash, $object) = @_;
	
	my $result = '<html>';
	my $address;
	my $iface;

	if (ref($object) eq 'HASH') {
		$address = $object->{ccuaddr};
		$iface = $object->{ccuif};
	}
	else {
		$address = $object;
	}
	
	my ($devAddr, $chnNo) = HMCCU_SplitChnAddr ($address);

# BUG?
#	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $address, $iface);
	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $devAddr, $iface);
	return undef if (!defined($devDesc));
	my $model = HMCCU_GetDeviceModel ($ioHash, $devDesc->{_model}, $devDesc->{_fw_ver});
	return undef if (!defined($model));
	
	my @chnList = ();
	if ($chnNo eq '') {
		push @chnList, sort keys %{$model};
		unshift (@chnList, pop(@chnList)) if (exists($model->{'d'}));
	}
	else {
		push @chnList, 'd', 0, $chnNo;
	}
	
	$result .= qq(<a name="top">);
	foreach my $c (@chnList) {
		$result .= qq(<a href="#$devAddr:$c">Channel $c</a><br/>) if ($c ne 'd');
	}
	$result .= '<br/>';
	foreach my $c (@chnList) {
		$result .= $c eq 'd' ? "<b>Device $devAddr</b><br/>" : qq(<a name="$devAddr:$c"><b>Channel $devAddr $c</b><br/>);
		foreach my $ps (sort keys %{$model->{$c}}) {
			$result .= "&nbsp;&nbsp;Paramset $ps<br/>";
			$result .= join ("<br/>", map {
				"&nbsp;&nbsp;&nbsp;&nbsp;".$_.": ".
				$model->{$c}{$ps}{$_}{TYPE}.
				" [".HMCCU_FlagsToStr ('model', 'OPERATIONS', $model->{$c}{$ps}{$_}{OPERATIONS}, ',', '')."]".
				" [".HMCCU_FlagsToStr ('model', 'FLAGS', $model->{$c}{$ps}{$_}{FLAGS}, ',', '')."]".
				" RANGE=".HMCCU_StripNumber ($model->{$c}{$ps}{$_}{MIN}, 2).
				"...".HMCCU_StripNumber ($model->{$c}{$ps}{$_}{MAX}, 2).
				" DFLT=".HMCCU_StripNumber ($model->{$c}{$ps}{$_}{DEFAULT}, 2).
				HMCCU_ISO2UTF (HMCCU_DefStr ($model->{$c}{$ps}{$_}{UNIT}, " UNIT=")).
				HMCCU_DefStr ($model->{$c}{$ps}{$_}{VALUE_LIST}, " VALUES=")
			} sort keys %{$model->{$c}{$ps}})."<br/>";
		}
		$result .= qq(<br/><a href="#top">Top</a><br/><br/>);
	}
	
	$result .= '</html>';
	
	return $result;
}

######################################################################
# Get device addresses.
# Parameters:
#   $iface - Interface name. If set to undef, all devices are
#      returned.
#   $filter - Filter expression in format Attribute=RegExp[,...].
#      Attribute is a valid device description parameter name or
#      "_addtype" or "_interface".
# Return array with addresses.
######################################################################

sub HMCCU_GetDeviceAddresses ($;$$)
{
	my ($hash, $iface, $filter) = @_;
	
	my @addList = ();
	my @ifaceList = ();
	
	return @addList if (!exists($hash->{hmccu}{device}));
	
	if (defined($iface)) {
		push (@ifaceList, $iface);
	}
	else {
		push (@ifaceList, keys %{$hash->{hmccu}{device}});
	}
	
	if (defined($filter)) {
		my %f = ();
		foreach my $fd (split (',', $filter)) {
			my ($fa, $fv) = split ('=', $fd);
			$f{$fa} = $fv if (defined($fv));
		}
		return undef if (scalar(keys(%f)) == 0);

		foreach my $i (@ifaceList) {		
			foreach my $a (keys %{$hash->{hmccu}{device}{$i}}) {
				my $n = 0;
				foreach my $fr (keys(%f)) {
					if (HMCCU_ExprNotMatch ($hash->{hmccu}{device}{$i}{$a}{$fr}, $f{$fr}, 1)) {
						$n = 1;
						last;
					}
				}
				push (@addList, $a) if ($n == 0);
			}
		}
	}
	else {
		foreach my $i (@ifaceList) {
			push (@addList, keys %{$hash->{hmccu}{device}{$i}});
		}
	}
	
	return @addList;
}

######################################################################
# Check if device model is already known by HMCCU
#   $type - The device model
#   $fw_ver - combined key of firmware and description version
#   $chnNo - Channel number or 'd' for device
######################################################################

sub HMCCU_ExistsDeviceModel ($$$;$)
{
	my ($hash, $type, $fw_ver, $chnNo) = @_;
	
	return 0 if (!exists($hash->{hmccu}{model}));
	
	if (defined($chnNo)) {
		return (exists($hash->{hmccu}{model}{$type}) && exists($hash->{hmccu}{model}{$type}{$fw_ver}) &&
			exists($hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}) ? 1 : 0);
	}
	else {
		return (exists($hash->{hmccu}{model}{$type}) && exists($hash->{hmccu}{model}{$type}{$fw_ver}) ? 1 : 0);
	}
}

######################################################################
# Add new device model
# Parameters:
#   $desc - Hash reference with paramset description
#   $type - The device model
#   $fw_ver - combined key of firmware and description version
#   $paramset - Name of parameter set
#   $chnNo - Channel number or 'd' for device
######################################################################

sub HMCCU_AddDeviceModel ($$$$$$)
{
	my ($hash, $desc, $type, $fw_ver, $paramset, $chnNo) = @_;
	
	# Process list of parameter names
	foreach my $p (keys %$desc) {	
		# Process parameter attributes
		foreach my $a (keys %{$desc->{$p}}) {
			if (ref($desc->{$p}{$a}) eq 'HASH') {
				# Process sub attributes
				foreach my $s (keys %{$desc->{$p}{$a}}) {
					if (ref($desc->{$p}{$a}{$s}) eq 'ARRAY') {
						# Store array elements as list
						$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}{$paramset}{$p}{$a}{$s} = join(',', @{$desc->{$p}{$a}{$s}});
					}
					elsif (ref($desc->{$p}{$a}{$s}) eq 'HASH') {
						HMCCU_Log ($hash, 2, "HASH ref $type $chnNo $p $a $s");
						$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}{$paramset}{$p}{$a}{$s} = $desc->{$p}{$a}{$s};
					}
					else {
						# Value
						$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}{$paramset}{$p}{$a}{$s} = $desc->{$p}{$a}{$s};
					}
				}
			}
			elsif (ref($desc->{$p}{$a}) eq 'ARRAY') {
				$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}{$paramset}{$p}{$a} = join(',', @{$desc->{$p}{$a}});
			}
			else {
				$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}{$paramset}{$p}{$a} = $desc->{$p}{$a};
			}
		}
	}
}

######################################################################
# Get device model
# Parameters:
#   $chnNo - Channel number. Use 'd' for device entry. If not defined
#     a reference to the master entry is returned.
######################################################################

sub HMCCU_GetDeviceModel ($$$;$)
{
	my ($hash, $type, $fw_ver, $chnNo) = @_;
	
	return undef if (!exists($hash->{hmccu}{model}));
	
	if (defined($chnNo) && $chnNo ne '') {
		return (exists($hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}) ?
			$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo} : undef);
	}
	else {
		return (exists($hash->{hmccu}{model}{$type}{$fw_ver}) ?
			$hash->{hmccu}{model}{$type}{$fw_ver} : undef);
	}
}

######################################################################
# Get device model for client device
# Parameters:
#   $hash - Hash reference for device of type HMCCUCHN or HMCCUDEV.
#   $chnNo - Channel number. Use 'd' for device entry. If not defined
#     a reference to the master entry is returned.
######################################################################

sub HMCCU_GetClientDeviceModel ($;$)
{
	my ($clHash, $chnNo) = @_;
	
	return undef if (
		($clHash->{TYPE} ne 'HMCCUCHN' && $clHash->{TYPE} ne 'HMCCUDEV') ||
		(!defined($clHash->{ccuaddr})));
	
	my $ioHash = HMCCU_GetHash ($clHash);
	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $clHash->{ccuaddr}, $clHash->{ccuif});
	
	return defined($devDesc) ? 
		HMCCU_GetDeviceModel ($ioHash, $devDesc->{_model}, $devDesc->{_fw_ver}, $chnNo) : undef;
}

######################################################################
# Get parameter defintion of device model
# Parameters:
#   $hash - Hash reference of IO device.
#   $object - Device or channel address or device description
#      reference.
#   $paramset - Valid paramset for device or channel.
#   $parameter - Parameter name.
# Returns undef on error. On success return a reference to the
# parameter or parameter set definition, if $parameter is not
# specified. 
######################################################################

sub HMCCU_GetParamDef ($$$;$)
{
	my ($hash, $object, $paramset, $parameter) = @_;

	return undef if (!defined($object));
	
	my $devDesc = ref($object) eq 'HASH' ? $object : HMCCU_GetDeviceDesc ($hash, $object);

	if (defined($devDesc)) {
		# Build device address and channel number
		my $a = $devDesc->{ADDRESS};
		my ($devAddr, $chnNo) = ($a =~ /:[0-9]{1,2}$/) ? HMCCU_SplitChnAddr ($a) : ($a, 'd');

		if (!defined($paramset)) {
			HMCCU_Log ($hash, 2, "$a Paramset not defined ".stacktraceAsString(undef));
			return undef;
		}

		my $model = HMCCU_GetDeviceModel ($hash, $devDesc->{_model}, $devDesc->{_fw_ver}, $chnNo);
		if (defined($model) && exists($model->{$paramset})) {
			if (defined($parameter)) {
				return exists($model->{$paramset}{$parameter}) ? $model->{$paramset}{$parameter} : undef;
			}
			else {
				return $model->{$paramset}
			}
		}
	}
	
	return undef;
}

######################################################################
# Find parameter defintion of device model
# Parameters:
#   $hash - Hash reference of IO device.
#   $object - Device or channel address or device description
#      reference.
#   $parameter - Parameter name.
# Returns (undef,undef) on error. Otherwise parameter set name and
# reference to the parameter definition.
######################################################################

sub HMCCU_FindParamDef ($$$)
{
	my ($hash, $object, $parameter) = @_;
	
	my $devDesc = ref($object) eq 'HASH' ? $object : HMCCU_GetDeviceDesc ($hash, $object);
		
	if (defined($devDesc)) {
		# Build device address and channel number
		my $a = $devDesc->{ADDRESS};
		my ($devAddr, $chnNo) = ($a =~ /:[0-9]{1,2}$/) ? HMCCU_SplitChnAddr ($a) : ($a, 'd');

		my $model = HMCCU_GetDeviceModel ($hash, $devDesc->{_model}, $devDesc->{_fw_ver}, $chnNo);
		if (defined($model)) {
			foreach my $ps (keys %$model) {
				return ($ps, $model->{$ps}{$parameter}) if (exists($model->{$ps}{$parameter}));
			}
		}
	}
	
	return (undef, undef);
}

######################################################################
# Get values of ENUM datapoint or HMCCU_STATECONTROL or HMCCU_CONVERSIONS
# entry.
#
# Parameters:
#   object - Hash with parameter defintion or channel address
#   dpt - Datapoint name. Can be undef if object is a paramDef hash.
#   value - Either '#', a numeric value or an enumeration constant
#   argList - Comma seperated list of constants
# If value is not specified, a string with a comma separated list of
# enumeration constants is returned.
# Return value, constant or list of constants depending on parameter
# $value:
#   '#' : Return list of constant:value pairs
#   undef: Return paramdef VALUE_LIST (if paramdef available and type = ENUM)
######################################################################

sub HMCCU_GetEnumValues ($$$$;$$)
{
	my ($ioHash, $object, $dpt, $role, $value, $argList) = @_;

	my %valList = ();	# Mapping constant => value
	my %valIndex = ();	# Mapping value => constant

	my $paramDef = ref($object) eq 'HASH' ? $object : HMCCU_GetParamDef ($ioHash, $object, 'VALUES', $dpt);
	return $value // '' if (!defined($paramDef) && !defined($dpt));

	if (defined($paramDef) && defined($paramDef->{TYPE}) && $paramDef->{TYPE} eq 'ENUM' && defined($paramDef->{VALUE_LIST})) {
		my $i = defined($paramDef->{MIN}) && HMCCU_IsIntNum($paramDef->{MIN}) ? $paramDef->{MIN} : 0;
		foreach my $vn (split(',',$paramDef->{VALUE_LIST})) {
			if ($vn ne '') {
				$valList{$vn} = $i;
				$valIndex{$i} = $vn;
			}
			$i++;
		}
	}
	elsif (defined($dpt) && defined($role) && $dpt eq $HMCCU_STATECONTROL->{$role}{C} && $HMCCU_STATECONTROL->{$role}{V} ne '#') {
		# If parameter is control datapoint, use values/conversions from HMCCU_STATECONTROL
		foreach my $cv (split(',', $HMCCU_STATECONTROL->{$role}{V})) {
			my ($vn, $vv) = split(':', $cv);
			if (defined($vv)) {
				$vv = $vv eq 'true' ? 1 : ($vv eq 'false' ? 0 : $vv);
				$valList{$vn} = $vv;
				$valIndex{$vv} = $vn;
			}
		}
	}
	elsif (defined($argList)) {
		if (defined($dpt) && defined($role) && exists($HMCCU_CONVERSIONS->{$role}{$dpt})) {
			# If a list of conversions exists, use values/conversions from HMCCU_CONVERSIONS
			foreach my $cv (split(',', $argList)) {
				if (exists($HMCCU_CONVERSIONS->{$role}{$dpt}{$cv})) {
					$valList{$cv} = $HMCCU_CONVERSIONS->{$role}{$dpt}{$cv};
					$valIndex{$HMCCU_CONVERSIONS->{$role}{$dpt}{$cv}} = $cv;
				}
				else {
					$valList{$cv} = $cv;
				}
			}
		}
		else {
			# As fallback use values as specified in command definition
			if (defined($paramDef) && defined($paramDef->{MIN}) && HMCCU_IsIntNum($paramDef->{MIN})) {
				my $i = $paramDef->{MIN};
				foreach my $cv (split(',', $argList)) {
					$valList{$cv} = $i;
					$valIndex{$i} = $cv;
					$i++;
				}
			}
			else {
				my $i = 0;
				foreach my $cv (split(',', $argList)) {
					my $j = HMCCU_IsIntNum($cv) ? $cv : $i;
					$valList{$cv} = $j;
					$valIndex{$j} = $cv;
					$i++;
				}
			}
		}
	}
	elsif (defined($paramDef) &&
		defined($paramDef->{MIN}) && HMCCU_IsIntNum($paramDef->{MIN}) &&
		defined($paramDef->{MAX}) && HMCCU_IsIntNum($paramDef->{MAX}) &&
		$paramDef->{MAX}-$paramDef->{MIN} < 10
	) {
		for (my $i=$paramDef->{MIN}; $i<=$paramDef->{MAX}; $i++) {
			$valList{$i} = $i;
			$valIndex{$i} = $i;
		}
	}

	if (defined($value)) {
		if ($value eq '#') {
			# Return list of Constant:Value pairs
			return '' if (scalar(keys %valList) == 0);
			return join(',', map { $_.':'.$valList{$_} } keys %valList);
		}
		elsif (HMCCU_IsFltNum($value)) {
			# Return Constant for value. Constant might be ''
			return $valIndex{$value} // '';
		}
		else {
			# Return Value for Constant
			return $valList{$value} // '';
		}
	}
	else {
		if (defined($paramDef) && exists($paramDef->{VALUE_LIST})) {
			return $paramDef->{VALUE_LIST};
		}
		elsif (defined($argList)) {
			return $argList;
		}
		else {
			return '';
		}
	}
}

######################################################################
# Check if parameter exists
# Parameters:
#   $clHash - Hash reference of client device.
#   $object - Device or channel address or device description
#      reference.
#   $ps - Parameter set name.
#   $parameter - Parameter name.
#   $oper - Access mode (default = 7):
#     1 = parameter readable
#     2 = parameter writeable
#     4 = parameter events
# Returns 0 or 1
######################################################################

sub HMCCU_IsValidParameter ($$$$;$)
{
	my ($clHash, $object, $ps, $parameter, $oper) = @_;

	$oper //= 7;
	my $ioHash = HMCCU_GetHash ($clHash) // return 0;

	return 0 if (!defined($parameter) || $parameter eq '');
	
	my $devDesc = ref($object) eq 'HASH' ? $object : HMCCU_GetDeviceDesc ($ioHash, $object);
		
	if (defined($devDesc)) {
		# Build device address and channel number
		my $a = $devDesc->{ADDRESS};
		my ($devAddr, $chnNo) = ($a =~ /:[0-9]{1,2}$/) ? HMCCU_SplitChnAddr ($a) : ($a, 'd');

		my $model = HMCCU_GetDeviceModel ($ioHash, $devDesc->{_model}, $devDesc->{_fw_ver}, $chnNo);
		if (defined($model)) {
			my @parList = ref($parameter) eq 'HASH' ? keys %$parameter : ($parameter);
			foreach my $p (@parList) {
				return 0 if (!exists($model->{$ps}) || !exists($model->{$ps}{$p}) ||
					!($model->{$ps}{$p}{OPERATIONS} & $oper));
			}
			return 1;
		}
	}
	
	return 0;
}

######################################################################
# Update client devices with peering information
# In addition peering information is stored in hash of IO device.
######################################################################

sub HMCCU_AddPeers ($$$)
{
	my ($ioHash, $peerList, $iface) = @_;
		
	foreach my $p (@$peerList) {
		my ($sd, $sc) = HMCCU_SplitChnAddr ($p->{SENDER});
		my ($rd, $rc) = HMCCU_SplitChnAddr ($p->{RECEIVER});
		$ioHash->{hmccu}{snd}{$iface}{$sd}{$sc}{$p->{RECEIVER}}{NAME} = $p->{NAME};
		$ioHash->{hmccu}{snd}{$iface}{$sd}{$sc}{$p->{RECEIVER}}{DESCRIPTION} = $p->{DESCRIPTION};
		$ioHash->{hmccu}{snd}{$iface}{$sd}{$sc}{$p->{RECEIVER}}{FLAGS} = $p->{FLAGS};
		$ioHash->{hmccu}{rcv}{$iface}{$rd}{$rc}{$p->{SENDER}}{NAME} = $p->{NAME};
		$ioHash->{hmccu}{rcv}{$iface}{$rd}{$rc}{$p->{SENDER}}{DESCRIPTION} = $p->{DESCRIPTION};
		$ioHash->{hmccu}{rcv}{$iface}{$rd}{$rc}{$p->{SENDER}}{FLAGS} = $p->{FLAGS};
	}

	return scalar(@$peerList);
}

######################################################################
# Get list of receivers for a source address
######################################################################

sub HMCCU_GetReceivers ($$$)
{
	my ($ioHash, $address, $iface) = @_;
	
	my ($sd, $sc) = HMCCU_SplitChnAddr ($address);
	if (exists($ioHash->{hmccu}{snd}{$iface}{$sd}{$sc})) {
		return keys %{$ioHash->{hmccu}{snd}{$iface}{$sd}{$sc}};
	}
	
	return ();
}

######################################################################
# Check if receiver exists for a source address
######################################################################

sub HMCCU_IsValidReceiver ($$$$)
{
	my ($ioHash, $address, $iface, $receiver) = @_;
	
	my ($sd, $sc) = HMCCU_SplitChnAddr ($address);
	return exists($ioHash->{hmccu}{snd}{$iface}{$sd}{$sc}{$receiver}) ? 1 : 0;
}

#######################################################################
# Convert bitmask to text
# Parameters:
#   $set - 'device', 'model' or 'peer'.
#   $flag - Name of parameter.
#   $value - Value of parameter.
#   $sep - String separator. Default = ''.
#   $default - Default value is returned if no bit is set.
# Return empty string on error. Return $default if no bit set.
# Return $value if $flag is not a bitmask.
######################################################################

sub HMCCU_FlagsToStr ($$$;$$)
{
	my ($set, $flag, $value, $sep, $default) = @_;
	
	$value //= 0;
	$default //= '';
	$sep //= '';
	
	my %bitmasks = (
		'device' => {
			'DIRECTION' => { 1 => 'SENDER', 2 => 'RECEIVER' },
			'FLAGS' =>     { 1 => 'Visible', 2 => 'Internal', 8 => 'DontDelete' },
			'RX_MODE' =>   { 1 => 'ALWAYS', 2 => 'BURST', 4 => 'CONFIG', 8 => 'WAKEUP', 16 => 'LAZY_CONFIG' }
		},
		'model' => {
			'FLAGS' =>      { 1 => 'Visible', 2 => 'Internal', 4 => 'Transform', 8 => 'Service', 16 => 'Sticky' },
			'OPERATIONS' => { 1 => 'R', 2 => 'W', 4 => 'E' }
		},
		'peer' => {
			'FLAGS' =>      { 1 => 'SENDER_BROKEN', 2 => 'RECEIVER_BROKEN' }
		}
	);
	
	my %mappings = (
		'device' => {
			'DIRECTION' => { 0 => 'NONE' }
		},
		'peer' => {
			'FLAGS' =>     { 0 => 'OK' }
		}
	);
	
	return $value if (!exists($bitmasks{$set}{$flag}) && !exists($mappings{$set}{$flag}));

	return $mappings{$set}{$flag}{$value}
		if (exists($mappings{$set}{$flag}) && exists($mappings{$set}{$flag}{$value}));
	
	if (exists($bitmasks{$set}{$flag})) {
		my @list = ();
		foreach my $b (sort keys %{$bitmasks{$set}{$flag}}) {
			push (@list, $bitmasks{$set}{$flag}{$b}) if ($value & $b);
		}
	
		return scalar(@list) == 0 ? $default : join($sep, @list);
	}
	
	return $value;
}

######################################################################
# Update a single client device datapoint considering scaling, reading
# format and value substitution.
# Return stored value.
######################################################################

sub HMCCU_UpdateSingleDatapoint ($$$$)
{
	my ($clHash, $chn, $dpt, $value) = @_;

	my $ioHash = HMCCU_GetHash ($clHash) // $value;
	my %objects;
	
	my $ccuaddr = $clHash->{ccuaddr};
	my ($devaddr, $chnnum) = HMCCU_SplitChnAddr ($ccuaddr);
	$objects{$devaddr}{$chn}{VALUES}{$dpt} = $value;
	
	my $rc = HMCCU_UpdateParamsetReadings ($ioHash, $clHash, \%objects);
	return (ref($rc)) ? $rc->{$devaddr}{$chn}{VALUES}{$dpt} : $value;
}

######################################################################
# Update readings of client device.
# Parameter objects is a hash reference which contains updated data
# for devices:
#   {devaddr}{channelno}{paramset}{parameter} = value
# For links format of paramset is "LINK.receiver".
# channelno = 'd' for device parameters.
# Return hash reference for results or undef on error.
######################################################################

sub HMCCU_UpdateParamsetReadings ($$$;$)
{
	my ($ioHash, $clHash, $objects, $devNames) = @_;
	
	return undef if (!defined($clHash) && !defined($devNames));

	my @devList = ();
	if (defined($devNames)) {
		@devList = @$devNames;
	}
	elsif (defined($clHash)) {
		push @devList, $clHash->{NAME};
	}
	else {
		return undef;
	}

	# Resulting readings
	my %results;
	
	# Updated internal values
	my @chKeys = ();
		
	# Loop over all addresses
	foreach my $d (@devList) {
		$clHash = $defs{$d} // next;

		# Valid device ?
		next if (!defined($clHash->{IODev}) || !defined($clHash->{ccuaddr}) || $clHash->{IODev} != $ioHash);

		# Check if there are any updates for the device
		my ($a, $chnNo) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
		next if (!exists($objects->{$a}));

		my $ioName = $ioHash->{NAME};
		my $clName = $clHash->{NAME};
		my $clType = $clHash->{TYPE};

		# Check if update of device allowed
		my $ccuflags = HMCCU_GetFlags ($ioName);
		my $disable = AttrVal ($clName, 'disable', 0);
		my $update = AttrVal ($clName, 'ccureadings', HMCCU_IsFlag ($clName, 'noReadings') ? 0 : 1);
		next if ($update == 0 || $disable == 1 || $clHash->{ccudevstate} ne 'active');

		# Get client device attributes
		my $substMode = HMCCU_IsFlag($ioName,'noAutoSubstitute') || HMCCU_IsFlag($clName,'noAutoSubstitute') ? -1 : 0;
		my $clRF = HMCCU_GetAttrReadingFormat ($clHash, $ioHash);
		my $clInt = $clHash->{ccuif};
		my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);

		HMCCU_BeginBulkUpdate ($clHash);

		# Loop over all channels of device, including channel 'd'
		foreach my $c (keys %{$objects->{$a}}) {
			# For HMCCUCHN update device channel and channel 0 only
			next if (($clType eq 'HMCCUCHN' && "$c" ne "$chnNo" && "$c" ne "0" && "$c" ne "d"));
			
			if (ref($objects->{$a}{$c}) ne 'HASH') {
				HMCCU_Log ($ioHash, 2, "object $a $c is not a hash reference\n".stacktraceAsString(undef));
				next;
			}

			my $chnAddr = "$a:$c";
			my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $chnAddr, $clHash->{ccuif});
			my $chnType = defined($devDesc) ? $devDesc->{TYPE} : HMCCU_GetChannelRole ($clHash, $c);

			# Loop over all parameter sets
			foreach my $ps (keys %{$objects->{$a}{$c}}) {
				if (ref($objects->{$a}{$c}{$ps}) ne 'HASH') {
					HMCCU_Log ($ioHash, 2, "object $a $c $ps is not a hash reference\n".stacktraceAsString(undef));
					next;
				}
				
				# Loop over all parameters
				foreach my $p (keys %{$objects->{$a}{$c}{$ps}}) {
					my $v = $objects->{$a}{$c}{$ps}{$p};
					next if (!defined($v));
					$v = $v eq 'true' ? 1 : ($v eq 'false' ? 0 : $v);
					my $fv = $v;
					my $cv = $v;
					my $sv;
					
					HMCCU_Trace ($clHash, 2, "ParamsetReading $a.$c.$ps.$p=$v");
					
					# Key for storing values in client device hash. Indirect updates of virtual
					# devices are stored with device address in key.
					# my $chKey = $devAddr ne $a ? "$chnAddr.$p" : "$c.$p";
					my $chKey = "$c.$p";

					# Store raw value in client device hash
					HMCCU_UpdateInternalValues ($clHash, $chKey, $ps, 'VAL', $v);

					# Modify reading value: scale, format, substitute
					$sv = HMCCU_ScaleValue ($clHash, $c, $p, $v, 0, $ps);
					HMCCU_UpdateInternalValues ($clHash, $chKey, $ps, 'NVAL', $sv);
					$fv = HMCCU_FormatReadingValue ($clHash, $sv, $p);
					$cv = HMCCU_Substitute ($fv, $clHash, $substMode, $c, $p, $chnType, $devDesc);
					HMCCU_UpdateInternalValues ($clHash, $chKey, $ps, 'SVAL', $cv);
					push @chKeys, $chKey;

					# Update 'state' and 'control'
					HMCCU_BulkUpdate ($clHash, 'control', $fv, $cv) if ($cd ne '' && $p eq $cd && $c eq $cc);
					HMCCU_BulkUpdate ($clHash, 'state', $fv, $cv) if ($p eq $sd && ($sc eq '' || $sc eq $c));
				
					# Store result
					$results{$a}{$c}{$ps}{$p} = $cv;
					
					# Modify and filter reading names
					my $hide = HMCCU_FilterReading ($clHash, $chnAddr, $p, $ps) ? 0 : 1;
					my @rnList = HMCCU_GetReadingName ($clHash, $clInt, $a, $c, $p, $hide, $clRF, $ps);

					# Update readings
					foreach my $rn (@rnList) {
						HMCCU_Trace ($clHash, 2, "p=$p rn=$rn, fv=$fv, cv=$cv");
						HMCCU_BulkUpdate ($clHash, $rn, $fv, $cv);
					}
				}
			}
		}

		# Calculate additional readings	
		if (scalar (@chKeys) > 0) {
			my %calc = HMCCU_CalculateReading ($clHash, \@chKeys);
			foreach my $cr (keys %calc) {
				HMCCU_BulkUpdate ($clHash, $cr, $calc{$cr}, $calc{$cr});
			}
		}
		
		# Update device states
		my $devstate = HMCCU_GetDeviceStates ($clHash);
		HMCCU_BulkUpdate ($clHash, 'devstate', $devstate);

		# Calculate and update HomeMatic state
		if ($ccuflags !~ /nohmstate/) {
			my ($hms_read, $hms_chn, $hms_dpt, $hms_val) = HMCCU_GetHMState ($clName, $ioName);
			HMCCU_BulkUpdate ($clHash, $hms_read, $hms_val, $hms_val) if (defined($hms_val));
		}

		HMCCU_EndBulkUpdate ($clHash);
	}

	return \%results;
}

######################################################################
# Refresh readings of a client device
######################################################################

sub HMCCU_RefreshReadings ($;$)
{
	my ($clHash, $attribute) = @_;
	
	my $ioHash = HMCCU_GetHash ($clHash) // return;
	my $refreshAttrList = 'ccucalculate|ccuflags|ccureadingfilter|ccureadingformat|'.
		'ccureadingname|ccuReadingPrefix|ccuscaleval|controldatapoint|hmstatevals|'.
		'statedatapoint|statevals|substitute|substexcl|stripnumber';

	return if (defined($attribute) && $attribute !~ /^($refreshAttrList)$/i);

	HMCCU_DeleteReadings ($clHash);
	
	my %objects;
	my ($devAddr, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	
	for my $dp (keys %{$clHash->{hmccu}{dp}}) {
		foreach my $ps (keys %{$clHash->{hmccu}{dp}{$dp}}) {
			my ($chnNo, $par) = split (/\./, $dp);
			if (defined($par) && defined($clHash->{hmccu}{dp}{$dp}{$ps}{VAL})) {
				$objects{$devAddr}{$chnNo}{$ps}{$par} = $clHash->{hmccu}{dp}{$dp}{$ps}{VAL};
			}
		}
	}
	
	if (scalar(keys %objects) > 0) {
		HMCCU_UpdateParamsetReadings ($ioHash, $clHash, \%objects);
	}
}

######################################################################
# Store datapoint values in device hash.
# Parameter type is VAL, NVAL or SVAL:
#  VAL - Original value (CCU), i.e. 1
#  NVAL - Scaled value, i.e. 100
#  SVAL - Substituted value, i.e. "on"
# Structure:
#  {hmccu}{dp}{channel.datapoint}{paramset}{VAL|OVAL|SVAL|OSVAL}
#  {hmccu}{tt}{program}{section}{daynum}{entrynum}
######################################################################

sub HMCCU_UpdateInternalValues ($$$$$)
{
	my ($ch, $chkey, $paramset, $type, $value) = @_;	
	my $otype = "O".$type;
	
	my %weekDay = ('SUNDAY', 0, 'MONDAY', 1, 'TUESDAY', 2, 'WEDNESDAY', 3,
		'THURSDAY', 4, 'FRIDAY', 5, 'SATURDAY', 6);
	my $weekDayExp = join('|', keys %weekDay);
	
	# Store time/value tables
	if ($type eq 'SVAL') {
		if ($chkey =~ /^[0-9d]+\.P([0-9])_([A-Z]+)_($weekDayExp)_([0-9]+)$/) {
			my ($prog, $valName, $day, $time) = ($1, $2, $3, $4);
			$prog--;
			if (exists($weekDay{$day})) {
				$ch->{hmccu}{tt}{$prog}{$valName}{$weekDay{$day}}{$time} = $value;
			}
		}
		elsif ($chkey =~ /^[0-9d]+\.([A-Z]+)_($weekDayExp)_([0-9]+)$/) {
			my ($valName, $day, $time) = ($1, $2, $3);
			if (exists($weekDay{$day})) {
				$ch->{hmccu}{tt}{0}{$valName}{$weekDay{$day}}{$time} = $value;
			}
		}
	}
	
	# Save old value
	my $cvalue = $ch->{hmccu}{dp}{$chkey}{$paramset}{$type};
	if (defined($cvalue) && "$value" ne "$cvalue") {
		$ch->{hmccu}{dp}{$chkey}{$paramset}{$otype} = $cvalue;
	}
	
	# Store new value
	$ch->{hmccu}{dp}{$chkey}{$paramset}{$type} = $value;
}

######################################################################
# Update readings of multiple client devices.
# Parameter objects is a hash reference:
#   {devaddr}
#   {devaddr}{channelno}
#   {devaddr}{channelno}{datapoint} = value
# Return number of updated devices.
######################################################################

sub HMCCU_UpdateMultipleDevices ($$;$)
{
	my ($hash, $objects, $devNameList) = @_;
	
	# Check syntax
	return 0 if (!defined ($hash) || !defined ($objects));

	# Update reading in matching client devices
	my @devList = defined($devNameList) ? split(',',$devNameList) :
		HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN)', undef, 'ccudevstate=active');

	my $rc = HMCCU_UpdateParamsetReadings ($hash, undef, $objects, \@devList);
	return ref($rc) eq 'HASH' ? scalar(@devList) : 0;
}

######################################################################
# Get list of device addresses
######################################################################

sub HMCCU_GetAffectedAddresses ($)
{
	my ($clHash) = @_;
	my @addlist = ();
	
	if ($clHash->{TYPE} eq 'HMCCUDEV' || $clHash->{TYPE} eq 'HMCCUCHN') {
		if (HMCCU_IsDeviceActive ($clHash)) {
			my ($devaddr, $cnum) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
			push @addlist, $devaddr;
		}
	}
	
	return @addlist;
}

######################################################################
# Get hash with valid RPC interfaces and ports
# If $mode = 1, return only interfaces which have devices assigned.
######################################################################

sub HMCCU_GetRPCInterfaceList ($;$)
{
	my ($hash, $mode) = @_;
	$mode //= 0;
	my $name = $hash->{NAME};
	my %interfaces = ();	

	my $rpcInterfaces = AttrVal ($name, 'rpcinterfaces', '');
	if ($rpcInterfaces ne '') {
		foreach my $in (split (',', $rpcInterfaces)) {
			my ($pn, $dc) = HMCCU_GetRPCServerInfo ($hash, $in, 'port,devcount');
			if (defined($pn) && ($mode == 0 || ($mode == 1 && defined($dc) && $dc > 0))) {
				$interfaces{$in} = $pn;
			}
		}
	}
	elsif (defined($hash->{hmccu}{rpcports})) {
		foreach my $pn (split (',', $hash->{hmccu}{rpcports})) {
			my ($in, $it, $dc) = HMCCU_GetRPCServerInfo ($hash, $pn, 'name,type,devcount');
			if (defined($in) && defined($it) && ($mode == 0 || ($mode == 1 && defined($dc) && $dc > 0))) {
				$interfaces{$in} = $pn;
			}
		}
	}
	
	return \%interfaces;
}

######################################################################
# Called by HMCCURPCPROC device of default interface 
# when no events from CCU were received for a specified time span.
# Return 1 if all RPC servers have been registered successfully.
# Return 0 if at least one RPC server failed to register or the
# corresponding HMCCURPCPROC device was not found.
######################################################################

sub HMCCU_EventsTimedOut ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	return 1 if (!HMCCU_IsFlag ($name, 'reconnect'));
	
	HMCCU_Log ($hash, 2, 'Reconnecting to CCU');
	
	# Register callback for each interface
	my $rc = 1;
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
	foreach my $ifname (keys %$interfaces) {
		my ($rpcdev, $save) = HMCCU_GetRPCDevice ($hash, 0, $ifname);
		if ($rpcdev eq '') {
			HMCCU_Log ($hash, 0, "Can't find RPC device for interface $ifname");
			$rc = 0;
			next;
		}
		my $clHash = $defs{$rpcdev};
		# Check if CCU interface is reachable before registering callback
		my ($nrc, $msg) = HMCCURPCPROC_RegisterCallback ($clHash, 2);
		$rc &= $nrc;
		if ($nrc) {
			$clHash->{ccustate} = 'active';
		}
		else {
			HMCCU_Log ($clHash, 1, $msg);
		}
	}
	
	return $rc;
}

######################################################################
# Build RPC callback URL
# Parameter hash might be a HMCCU or a HMCCURPCPROC hash.
######################################################################

sub HMCCU_GetRPCCallbackURL ($$$$$)
{
	my ($hash, $localaddr, $cbport, $clkey, $iface) = @_;

	return undef if (!defined($hash));
	
	my $ioHash = $hash->{TYPE} eq 'HMCCURPCPROC' ? $hash->{IODev} : $hash;
	
	return undef if (!exists($ioHash->{hmccu}{interfaces}{$iface}) &&
		!exists ($ioHash->{hmccu}{ifports}{$iface}));
	
	my $ifname = $iface =~ /^[0-9]+$/ ? $ioHash->{hmccu}{ifports}{$iface} : $iface;
	return undef if (!exists($ioHash->{hmccu}{interfaces}{$ifname}));

	my $url = $ioHash->{hmccu}{interfaces}{$ifname}{prot}."://$localaddr:$cbport/fh".
		$ioHash->{hmccu}{interfaces}{$ifname}{port};
	$url =~ s/^https/http/;
	
	return $url;
}

######################################################################
# Get RPC server information.
# Parameter iface can be a port number or an interface name.
# Parameter info is a comma separated list of info tokens.
# Valid values for info are:
# url, port, prot, host, type, name, flags, device, devcount.
# Return undef for invalid interface or info token.
######################################################################

sub HMCCU_GetRPCServerInfo ($$$)
{
	my ($hash, $iface, $info) = @_;
	my @result = ();
	
	return @result if (!defined($hash) ||
		(!exists($hash->{hmccu}{interfaces}{$iface}) && !exists($hash->{hmccu}{ifports}{$iface})));
	
	my $ifname = $iface =~ /^[0-9]+$/ ? $hash->{hmccu}{ifports}{$iface} : $iface;
	return @result if (!exists($hash->{hmccu}{interfaces}{$ifname}));
	
	foreach my $i (split (',', $info)) {
		if ($i eq 'name') {
			push (@result, $ifname);
		}
		else {
			my $v = exists ($hash->{hmccu}{interfaces}{$ifname}{$i}) ?
				$hash->{hmccu}{interfaces}{$ifname}{$i} : undef;
			push @result, $v;
		}
	}
	
	return @result;
}

######################################################################
# Check if RPC interface is of specified type.
# Parameter $type is A for XML or B for binary.
######################################################################

sub HMCCU_IsRPCType ($$$)
{
	my ($hash, $iface, $type) = @_;
	
	my ($rpctype) = HMCCU_GetRPCServerInfo ($hash, $iface, 'type');
	return 0 if (!defined($rpctype));
	
	return $rpctype eq $type ? 1 : 0;
}

######################################################################
# Start external RPC server via RPC device.
# Return number of started/running RPC servers or 0 on error.
######################################################################

sub HMCCU_StartExtRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $attrset = 0;
	
	my $c = 0;	# Started RPC servers
	my $r = 0;	# Running RPC servers
	my $f = 0;	# Failed RPC servers
	my $d = 0;
	my $s = 0;
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
	my @iflist = keys %$interfaces;
	foreach my $ifname1 (@iflist) {
		my ($rpcdev, $save) = HMCCU_GetRPCDevice ($hash, 1, $ifname1);
		HMCCU_Log ($hash, 2, "RPC device for interface $ifname1: ".($rpcdev eq '' ? 'not found' : $rpcdev));
		next if ($rpcdev eq '' || !defined ($hash->{hmccu}{interfaces}{$ifname1}{device}));
		$d++;
		$s++ if ($save);
	}

	# Save FHEM config if new RPC devices were defined or attribute has changed
	if ($s > 0 || $attrset) {
		HMCCU_Log ($hash, 1, 'Saving FHEM config');
		CommandSave (undef, undef);
	}

	if ($d == scalar(@iflist)) {
		foreach my $ifname2 (@iflist) {
			my $dh = $defs{$hash->{hmccu}{interfaces}{$ifname2}{device}};
			$hash->{hmccu}{interfaces}{$ifname2}{manager} = 'HMCCU';
			my ($rc, $msg) = HMCCURPCPROC_StartRPCServer ($dh);
			if ($rc == 0) {
				$f++;
				HMCCU_SetRPCState ($hash, 'error', $ifname2, $msg);
			}
			elsif ($rc == 1) {
				$c++;
			}
			elsif ($rc == 2) {
				$r++;
			}
		}
		HMCCU_SetRPCState ($hash, 'starting') if ($c > 0);
		HMCCU_Log ($hash, 2, "RPC server start: $c started, $r already running, $f failed to start");
		return $c+$r;
	}
	else {
		HMCCU_Log ($hash, 0, 'Definition of some RPC devices failed');
	}
	
	return 0;
}

######################################################################
# Stop external RPC server via RPC device.
######################################################################

sub HMCCU_StopExtRPCServer ($;$)
{
	my ($hash, $wait) = @_;
	my $name = $hash->{NAME};

	return HMCCU_Log ($hash, 0, 'Module HMCCURPCPROC not loaded', 0)
		if (!exists($modules{'HMCCURPCPROC'}));
		
	HMCCU_SetRPCState ($hash, 'stopping');

	my $rc = 1;
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
	foreach my $ifname (keys %$interfaces) {
		my ($rpcdev, $save) = HMCCU_GetRPCDevice ($hash, 0, $ifname);
		if ($rpcdev eq '') {
			HMCCU_Log ($hash, 0, "HMCCU: Can't find RPC device");
			next;
		}
		$hash->{hmccu}{interfaces}{$ifname}{manager} = 'HMCCU';
		$rc &= HMCCURPCPROC_StopRPCServer ($defs{$rpcdev}, $wait);
	}
	
	return $rc;
}

######################################################################
# Check status of RPC server depending on internal RPCState.
# Return 1 if RPC server is stopping, starting or restarting. During
# this phases CCU reacts very slowly so any get or set command from
# HMCCU devices are disabled.
######################################################################

sub HMCCU_IsRPCStateBlocking ($)
{
	my ($hash) = @_;

	return (exists($hash->{RPCState}) && (
		$hash->{RPCState} eq 'starting' ||
		$hash->{RPCState} eq 'restarting' ||
		$hash->{RPCState} eq 'stopping'
	)) ? 1 : 0;
}

######################################################################
# Check if RPC servers are running. 
# Return number of running RPC servers. If paramters pids or tids are
# defined also return process or thread IDs.
######################################################################

sub HMCCU_IsRPCServerRunning ($;$)
{
	my ($hash, $pids) = @_;
	my $name = $hash->{NAME};
	my $c = 0;
	
	my $ccuflags = HMCCU_GetFlags ($name);

	@$pids = () if (defined($pids));
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 0);
	foreach my $ifname (keys %$interfaces) {
		my ($rpcdev, $save) = HMCCU_GetRPCDevice ($hash, 0, $ifname);
		next if ($rpcdev eq '');
		my $rc = HMCCURPCPROC_CheckProcessState ($defs{$rpcdev}, 'running');
		if ($rc < 0 || $rc > 1) {
			push (@$pids, $rc) if (defined($pids));
			$c++;
		}
	}
	
	return $c;
}

######################################################################
# Get channels and datapoints of CCU device
######################################################################

sub HMCCU_GetDeviceInfo ($$;$)
{
	my ($hash, $address, $ccuget) = @_;
	$ccuget //= 'Value';
	my $name = $hash->{NAME};
	my $response = '';

	my $ioHash = HMCCU_GetHash ($hash) // return '';
	$ccuget = HMCCU_GetAttribute ($ioHash, $hash, 'ccuget', 'Value') if ($ccuget eq 'Attr');
	my $devname = HMCCU_GetDeviceName ($ioHash, $address);


	$response .= HMCCU_HMScriptExt ($ioHash, "!GetDeviceInfo", { devname => $devname, ccuget => $ccuget });
	HMCCU_Trace ($hash, 2,
		"Device=$devname Devname=$devname<br>".
		"Script response = \n".$response."<br>".
		"Script = GetDeviceInfo");

	return $response;
}

######################################################################
# Make device info readable
# n=number, b=bool, f=float, i=integer, s=string, a=alarm, p=presence
# e=enumeration
######################################################################

sub HMCCU_FormatDeviceInfo ($)
{
	my ($devinfo) = @_;
	
	my %vtypes = (0, 'n', 2, 'b', 4, 'f', 6, 'a', 8, 'n', 11, 's', 16, 'i', 20, 's', 23, 'p', 29, 'e');
	my $result = '';
	my $c_oaddr = '';

	return 'Device info is empty' if (!defined($devinfo) || $devinfo eq '');
	
	foreach my $dpspec (split ("\n", $devinfo)) {
		if ($dpspec =~ /^D/) {
			my ($t, $d_iface, $d_addr, $d_name, $d_type) = split (';', $dpspec);
 			$result .= "DEV $d_name $d_addr interface=$d_iface type=$d_type<br/>";
		}
		else {
			my ($t, $c_addr, $c_name, $d_name, $d_type, $d_value, $d_flags) = split (';', $dpspec);
			if (defined($d_flags)) {
				$d_name =~ s/^[^:]+:(.+)$/$1/;
				if ($c_addr ne $c_oaddr) {
					$result .= "CHN $c_addr $c_name<br/>";
					$c_oaddr = $c_addr;
				}
				my $dt = exists($vtypes{$d_type}) ? $vtypes{$d_type} : $d_type;
				$result .= "&nbsp;&nbsp;&nbsp;$d_name = $d_value {$dt} [$d_flags]<br/>";
			}
			else {
				return "Datapoint specification incomplete: $dpspec";
			}
		}
	}
	
	return $result;
}

######################################################################
# Format a hash as HTML table
# {row1}{col1} = Value12
# {row1}{col2} = Value12
# {row2}{col1} = Value21
# ...
######################################################################

sub HMCCU_FormatHashTable ($)
{
	my ($hash) = @_;

	my $t = 0;
	my $result = '';
	foreach my $row (sort keys %$hash) {
		if ($t == 0) {
			# Begin of table with header
			$result .= '<table border="1"><tr>';
			$result .= '<th>Key</th>';
			foreach my $col (sort keys %{$hash->{$row}}) {
				$result .= "<th>$col</th>";
			}
			$result .= "</tr>\n";
			$t = 1;
		}
		$result .= "<tr><td>$row</td>";
		foreach my $col (sort keys %{$hash->{$row}}) {
			$result .= "<td>$hash->{$row}{$col}</td>";
		}
		$result .= "</tr>\n";
	}
	$result .= '</table>';

	return $result;
}

######################################################################
# Read CCU device identified by device or channel name via Homematic
# Script.
# Return (device count, channel count) or (-1, -1) on error.
######################################################################

sub HMCCU_GetDevice ($$)
{
	my ($hash, $name) = @_;
	
	my $devcount = 0;
	my $chncount = 0;
	my $devname;
	my $devtype;
	my %objects = ();
	
	my $response = HMCCU_HMScriptExt ($hash, '!GetDevice', { name => $name });
	return (-1, -1) if ($response eq '' || $response =~ /^ERROR:.*/);
	
	my @scrlines = split /[\n\r]+/,$response;
	foreach my $hmdef (@scrlines) {
		my @hmdata = split /;/,$hmdef;
		next if (scalar(@hmdata) == 0);

		if ($hmdata[0] eq 'D') {
			next if (scalar (@hmdata) != 6);
			# 1=Interface 2=Device-Address 3=Device-Name 4=Device-Type 5=Channel-Count
			# my $typeprefix = $hmdata[2] =~ /^CUX/ ? 'CUX-' :
			# 	$hmdata[1] eq 'HVL' ? 'HVL-' : '';
			$objects{$hmdata[2]}{addtype}   = 'dev';
			$objects{$hmdata[2]}{channels}  = $hmdata[5];
			$objects{$hmdata[2]}{flag}      = 'N';
			$objects{$hmdata[2]}{interface} = $hmdata[1];
			$objects{$hmdata[2]}{name}      = $hmdata[3];
			# $objects{$hmdata[2]}{type}      = $typeprefix . $hmdata[4];
			$objects{$hmdata[2]}{type}      = $hmdata[4];
			$objects{$hmdata[2]}{direction} = 0;
			$devname = $hmdata[3];
			# $devtype = $typeprefix . $hmdata[4];
			$devtype = $hmdata[4];
		}
		elsif ($hmdata[0] eq 'C') {
			next if (scalar (@hmdata) != 4);
			# 1=Channel-Address 2=Channel-Name 3=Direction
			$objects{$hmdata[1]}{addtype}   = 'chn';
			$objects{$hmdata[1]}{channels}  = 1;
			$objects{$hmdata[1]}{flag}      = 'N';
			$objects{$hmdata[1]}{name}      = $hmdata[2];
			$objects{$hmdata[1]}{valid}     = 1;
			$objects{$hmdata[1]}{direction} = $hmdata[3];
		}
	}

	if (scalar(keys %objects) > 0) {
		# Update HMCCU device tables
		($devcount, $chncount) = HMCCU_UpdateDeviceTable ($hash, \%objects);
	}

	return ($devcount, $chncount);
}

######################################################################
# Read list of CCU interfaces via Homematic Script.
# Return number of interfaces.
# Note: Doesn't update $hash->{hmccu}{interfaces}
######################################################################

sub HMCCU_GetInterfaceList ($)
{
	my ($hash) = @_;
	
	my $ifCount = 0;
	my @ifNames = ();
	my @ifPorts = ();
	
	my $response = HMCCU_HMScriptExt ($hash, "!GetInterfaceList");
	return '' if ($response eq '' || $response =~ /^ERROR:.*/);
	
	foreach my $hmdef (split /[\n\r]+/,$response) {
		my @hmdata = split /;/,$hmdef;
		if (scalar(@hmdata) == 3 && $hmdata[2] =~ /^([^:]+):\/\/([^:]+):([0-9]+)/) {
			my ($prot, $ipaddr, $port) = ($1, $2, $3);
			next if (!defined ($port) || $port eq '');
			$port -= 30000 if ($port >= 10000);
			push @ifNames, $hmdata[0];
			push @ifPorts, $port;
			$ifCount++;
		}				
	}
	
	if ($ifCount > 0) {
		$hash->{hmccu}{rpcports} = join(',', @ifPorts);
		$hash->{ccuinterfaces} = join(',', @ifNames);
	}
		
	return $ifCount;
}

######################################################################
# Read list of CCU devices, channels, interfaces, programs and groups
# via Homematic Script.
# Update data of client devices if not current.
# Return counters (devices, channels, interfaces, programs, groups)
# or (-1, -1, -1, -1, -1) on error.
######################################################################

sub HMCCU_GetDeviceList ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	my $devcount = 0;
	my $chncount = 0;
	my $ifcount = 0;
	my $prgcount = 0;
	my $gcount = 0;
	my %objects = ();
	
	# Read devices, channels, interfaces and groups from CCU
	my $response = HMCCU_HMScriptExt ($hash, '!GetDeviceList');
	return (-1, -1, -1, -1, -1) if ($response eq '' || $response =~ /^ERROR:.*/);
	my $groups = HMCCU_HMScriptExt ($hash, '!GetGroupDevices');
	
	# CCU is reachable
	$hash->{ccustate} = 'active';
	
	# Delete old entries
	HMCCU_Log ($hash, 5, "Deleting old CCU configuration data");
	%{$hash->{hmccu}{dev}} = ();
	%{$hash->{hmccu}{adr}} = ();
	%{$hash->{hmccu}{interfaces}} = ();
	%{$hash->{hmccu}{grp}} = ();
	%{$hash->{hmccu}{prg}} = ();
	$hash->{hmccu}{updatetime} = time ();

#  Device hash elements for HMCCU_UpdateDeviceTable():
#
#  {address}{flag}      := [N, D, R]
#  {address}{addtype}   := [chn, dev]
#  {address}{channels}  := Number of channels
#  {address}{name}      := Device or channel name
#  {address}{type}      := Homematic device type
#  {address}{usetype}   := Usage type
#  {address}{interface} := Device interface ID
#  {address}{firmware}  := Firmware version of device
#  {address}{version}   := Version of RPC device description
#  {address}{rxmode}    := Transmit mode
#  {address}{direction} := Channel direction: 1=sensor 2=actor 0=none

	my @scrlines = split /[\n\r]+/,$response;
	foreach my $hmdef (@scrlines) {
		my @hmdata = split /;/,$hmdef;
		next if (scalar (@hmdata) == 0);
		my $typeprefix = '';

		if ($hmdata[0] eq 'D') {
			# Device
			next if (scalar (@hmdata) != 6);
			# @hmdata: 1=Interface 2=Device-Address 3=Device-Name 4=Device-Type 5=Channel-Count
			$objects{$hmdata[2]}{addtype}   = 'dev';
			$objects{$hmdata[2]}{channels}  = $hmdata[5];
			$objects{$hmdata[2]}{flag}      = 'N';
			$objects{$hmdata[2]}{interface} = $hmdata[1];
			$objects{$hmdata[2]}{name}      = $hmdata[3];
			# $typeprefix = "CUX-" if ($hmdata[2] =~ /^CUX/);
			# $typeprefix = "HVL-" if ($hmdata[1] eq 'HVL');
			# $objects{$hmdata[2]}{type}      = $typeprefix . $hmdata[4];
			$objects{$hmdata[2]}{type}      = $hmdata[4];
			$objects{$hmdata[2]}{direction} = 0;
			# CCU information (address = BidCoS-RF)
			if ($hmdata[2] eq 'BidCoS-RF') {
				$hash->{ccuname} = $hmdata[3];
				$hash->{ccuaddr} = $hmdata[2];
				$hash->{ccuif}   = $hmdata[1];
			}
			# Count devices per interface
			if (exists ($hash->{hmccu}{interfaces}{$hmdata[1]}) &&
				exists ($hash->{hmccu}{interfaces}{$hmdata[1]}{devcount})) {
				$hash->{hmccu}{interfaces}{$hmdata[1]}{devcount}++;
			}
			else {
				$hash->{hmccu}{interfaces}{$hmdata[1]}{devcount} = 1;
			}
		}
		elsif ($hmdata[0] eq 'C') {
			# Channel
			next if (scalar (@hmdata) != 4);
			# @hmdata: 1=Channel-Address 2=Channel-Name 3=Direction
			$objects{$hmdata[1]}{addtype}   = 'chn';
			$objects{$hmdata[1]}{channels}  = 1;
			$objects{$hmdata[1]}{flag}      = 'N';
			$objects{$hmdata[1]}{name}      = $hmdata[2];
			$objects{$hmdata[1]}{valid}     = 1;
			$objects{$hmdata[1]}{direction} = $hmdata[3];
		}
		elsif ($hmdata[0] eq 'I') {
			# Interface
			next if (scalar (@hmdata) != 4);
			# 1=Interface-Name 2=Interface Info 3=URL
			my $ifurl = $hmdata[3];
			if ($ifurl =~ /^([^:]+):\/\/([^:]+):([0-9]+)/) {
				my ($prot, $ipaddr, $port) = ($1, $2, $3);
				next if (!defined ($port) || $port eq '');
				if ($port >= 10000) {
					$port -= 30000;
					$ifurl =~ s/:3$port/:$port/;
				}
				if ($hash->{ccuip} ne 'N/A') {
					$ifurl =~ s/127\.0\.0\.1/$hash->{ccuip}/;
					$ipaddr =~ s/127\.0\.0\.1/$hash->{ccuip}/;					
				}
				else {
					$ifurl =~ s/127\.0\.0\.1/$hash->{host}/;
					$ipaddr =~ s/127\.0\.0\.1/$hash->{host}/;					
				}
				if ($HMCCU_RPC_FLAG{$port} =~ /forceASCII/) {
					$ifurl =~ s/xmlrpc_bin/xmlrpc/;
					$prot = "xmlrpc";
				}
				# Perl module RPC::XML::Client.pm does not support URLs starting with xmlrpc://
				$ifurl =~ s/xmlrpc:/http:/;
				$prot =~ s/^xmlrpc$/http/;
				
				$hash->{hmccu}{interfaces}{$hmdata[1]}{url}     = $ifurl;
				$hash->{hmccu}{interfaces}{$hmdata[1]}{prot}    = $prot;
				$hash->{hmccu}{interfaces}{$hmdata[1]}{type}    = $prot eq 'http' ? 'A' : 'B';
				$hash->{hmccu}{interfaces}{$hmdata[1]}{port}    = $port;
				$hash->{hmccu}{interfaces}{$hmdata[1]}{host}    = $ipaddr;
				$hash->{hmccu}{interfaces}{$hmdata[1]}{state}   = 'inactive';
				$hash->{hmccu}{interfaces}{$hmdata[1]}{manager} = 'null';
				$hash->{hmccu}{interfaces}{$hmdata[1]}{flags}   = $HMCCU_RPC_FLAG{$port};
				if (!exists ($hash->{hmccu}{interfaces}{$hmdata[1]}{devcount})) {
					$hash->{hmccu}{interfaces}{$hmdata[1]}{devcount} = 0;
				}
				$hash->{hmccu}{ifports}{$port} = $hmdata[1];
				$ifcount++;
			}
		}
		elsif ($hmdata[0] eq 'P') {
			# Program
			next if (scalar (@hmdata) != 4);
			# 1=Program-Name 2=Active-Flag 3=Internal-Flag
			$hash->{hmccu}{prg}{$hmdata[1]}{active} = $hmdata[2]; 
			$hash->{hmccu}{prg}{$hmdata[1]}{internal} = $hmdata[3];
			$prgcount++;
		}
	}

	if ($ifcount > 0) {
		$hash->{ccuinterfaces} = join (',', keys %{$hash->{hmccu}{interfaces}});
		$hash->{hmccu}{rpcports} = join (',', keys %{$hash->{hmccu}{ifports}});
	}
	else {
		HMCCU_Log ($hash, 1, "Found no interfaces on CCU");
		return (-1, -1, -1, -1, -1);
	}
	
	if (scalar (keys %objects) > 0) {
		# Update HMCCU device tables
		($devcount, $chncount) = HMCCU_UpdateDeviceTable ($hash, \%objects);
	}
	
	# Store group configurations
	if ($groups !~ /^ERROR:.*/ && $groups ne '') {
		my @gnames = ($groups =~ m/"NAME":"([^"]+)"/g);
		my @gmembers = ($groups =~ m/"groupMembers":\[[^\]]+\]/g);
		my @gtypes = ($groups =~ m/"groupType":\{"id":"([^"]+)"/g);

		foreach my $gm (@gmembers) {
			my $gn = shift @gnames;
			my $gt = shift @gtypes;
			my @ml = ($gm =~ m/,"id":"([^"]+)"/g);
			$hash->{hmccu}{grp}{$gn}{type} = $gt;
			$hash->{hmccu}{grp}{$gn}{devs} = join (',', @ml);
			$gcount++;
		}
	}
	else {
		HMCCU_Log ($hash, 1, "Can't read virtual groups from CCU. Response: $groups");
	}

	# Store asset counters
	$hash->{hmccu}{ccu}{devcount} = $devcount;
	$hash->{hmccu}{ccu}{chncount} = $chncount;
	$hash->{hmccu}{ccu}{ifcount}  = $ifcount;
	$hash->{hmccu}{ccu}{prgcount} = $prgcount;
	$hash->{hmccu}{ccu}{gcount}   = $gcount;

	my %ccuReading = (
		"count_devices" => $devcount, "count_channels" => $chncount,
		"count_interfaces" => $ifcount, "count_programs" => $prgcount,
		"count_groups" => $gcount
	);

	# Read CCU information
	my $info = HMCCU_HMScriptExt ($hash, '!GetVersion');
	if ($info ne '' && $info !~ /^ERROR:.*/) {
		foreach my $line (split /[\n\r]+/, $info) {
			my ($obj, $val) = split /=/, $line;
			next if ($obj !~ /^(VERSION|PRODUCT|PLATFORM)$/ || !defined($val));
			$ccuReading{$obj} = $val;
		}
	}
	
	HMCCU_UpdateReadings ($hash, \%ccuReading);
	
	return ($devcount, $chncount, $ifcount, $prgcount, $gcount);
}

sub HMCCU_GetDeviceList2 ($)
{
	my ($hash) = @_;
	
	my $response = HMCCU_JSONRequest ($hash, qq(
{
	"method": "Device.listAllDetail",
	"params": {
		"_session_id_": "$hash->{hmccu}{jsonAPI}{sessionId}"
	}
}
	));
}

######################################################################
# Check if device has an address, is not disabled and state is
# not inactive
######################################################################

sub HMCCU_IsDeviceActive ($)
{
	my ($clHash) = @_;

	if (defined($clHash)) {
		my $disabled = AttrVal ($clHash->{NAME}, 'disable', 0);
		my $devstate = $clHash->{ccudevstate} // 'pending';
		return 1 if ($disabled == 0 && exists($clHash->{ccuaddr}) && exists($clHash->{ccuif}) && $devstate ne 'inactive');
	}

	return 0;
}

######################################################################
# Check if device/channel name or address is valid and refers to an
# existing device or channel.
# mode: Bit combination: 1=Address 2=Name 4=Special address
######################################################################

sub HMCCU_IsValidDeviceOrChannel ($$$)
{
	my ($hash, $param, $mode) = @_;

	return HMCCU_IsValidDevice ($hash, $param, $mode) || HMCCU_IsValidChannel ($hash, $param, $mode) ? 1 : 0;
}

######################################################################
# Check if device name or address is valid and refers to an existing
# device.
# mode: Bit combination: 1=Address 2=Name 4=Special address
######################################################################

sub HMCCU_IsValidDevice ($$$)
{
	my ($hash, $param, $mode) = @_;

	# Address
	if ($mode & $HMCCU_FL_STADDRESS) {
		my $i;
		my $a = 'null';
		
		# Address with interface
		if (HMCCU_IsDevAddr ($param, 1)) {
			($i, $a) = split (/\./, $param);
		}
		elsif (HMCCU_IsDevAddr ($param, 0)) {
			$a = $param;
		}

		if (exists ($hash->{hmccu}{dev}{$a})) {
			return $hash->{hmccu}{dev}{$a}{valid};		
		}
		
		# Special address for Non-Homematic devices
		if (($mode & $HMCCU_FL_EXADDRESS) && exists ($hash->{hmccu}{dev}{$param})) {
			return $hash->{hmccu}{dev}{$param}{valid} && $hash->{hmccu}{dev}{$param}{addtype} eq 'dev' ? 1 : 0;
		}
	}
	
	# Name
	if (($mode & $HMCCU_FL_NAME)) {
		if (exists ($hash->{hmccu}{adr}{$param})) {
			return $hash->{hmccu}{adr}{$param}{valid} && $hash->{hmccu}{adr}{$param}{addtype} eq 'dev' ? 1 : 0;
		}
	}

	return 0;
}

######################################################################
# Check if channel name or address is valid and refers to an existing
# channel.
# mode: Bit combination: 1=Address 2=Name 4=Special address
######################################################################

sub HMCCU_IsValidChannel ($$$)
{
	my ($hash, $param, $mode) = @_;

	# Standard address for Homematic devices
	if ($mode & $HMCCU_FL_STADDRESS) {
		# Address with interface
		if (($mode & $HMCCU_FL_STADDRESS) && HMCCU_IsChnAddr ($param, 1)) {
			my ($i, $a) = split (/\./, $param);
			return 0 if (! exists ($hash->{hmccu}{dev}{$a}));
			return $hash->{hmccu}{dev}{$a}{valid};		
		}
	
		# Address without interface
		if (HMCCU_IsChnAddr ($param, 0)) {
			return 0 if (! exists ($hash->{hmccu}{dev}{$param}));
			return $hash->{hmccu}{dev}{$param}{valid};
		}
	}

	# Special address for Non-Homematic devices
	if (($mode & $HMCCU_FL_EXADDRESS) && exists ($hash->{hmccu}{dev}{$param})) {
		return $hash->{hmccu}{dev}{$param}{valid} && $hash->{hmccu}{dev}{$param}{addtype} eq 'chn' ? 1 : 0;
	}

	# Name
	if (($mode & $HMCCU_FL_NAME) && exists ($hash->{hmccu}{adr}{$param})) {
		return $hash->{hmccu}{adr}{$param}{valid} && $hash->{hmccu}{adr}{$param}{addtype} eq 'chn' ? 1 : 0;
	}

	return 0;
}

######################################################################
# Get CCU parameters of device or channel.
# Returns list containing interface, deviceaddress, name, type and
# channels.
######################################################################

sub HMCCU_GetCCUDeviceParam ($$)
{
	my ($hash, $param) = @_;
	my $name = $hash->{NAME};
	my $devadd;
	my $add = undef;
	my $chn = undef;

	if (HMCCU_IsDevAddr ($param, 1) || HMCCU_IsChnAddr ($param, 1)) {
		my $i;
		($i, $add) = split (/\./, $param);
	}
	else {
		if (HMCCU_IsDevAddr ($param, 0) || HMCCU_IsChnAddr ($param, 0)) {
			$add = $param;
		}
		else {
			if (exists ($hash->{hmccu}{adr}{$param})) {
				# param is a device name
				$add = $hash->{hmccu}{adr}{$param}{address};
			}
			elsif (exists ($hash->{hmccu}{dev}{$param})) {
				# param is a non standard device or channel address
				$add = $param;
			}
		}
	}
	
	return (undef, undef, undef, undef) if (!defined($add));
	($devadd, $chn) = split (':', $add);
	return (undef, undef, undef, undef) if (!defined($devadd) ||
		!exists ($hash->{hmccu}{dev}{$devadd}) || $hash->{hmccu}{dev}{$devadd}{valid} == 0);
	
	return ($hash->{hmccu}{dev}{$devadd}{interface}, $add, $hash->{hmccu}{dev}{$add}{name},
		$hash->{hmccu}{dev}{$devadd}{type}, $hash->{hmccu}{dev}{$add}{channels});
}

######################################################################
# Get list of valid parameters for device type
# Parameters:
#   clHash = hash of client device
#   chn = Channel number, special values:
#           undef = datapoints of all channels
#           d = device
#   ps = Parameterset name: VALUES, MASTER
#   oper = Valid operation, combination of 1=Read, 2=Write, 4=Event
#   dplistref = Reference for array with datapoints (optional)
# Return number of datapoints.
######################################################################

sub HMCCU_GetValidParameters ($$$$;$$)
{
	my ($clHash, $chn, $ps, $oper, $dplistref, $inclChnNo) = @_;
	$inclChnNo //= 0;

	my $model = HMCCU_GetClientDeviceModel ($clHash, $chn);
	return 0 if (!defined($model));

	if (!defined($chn) || $chn eq '') {
		my $count = 0;
		foreach my $c (keys %{$model}) {
			my @dpList = ();
			$count += HMCCU_GetValidChannelParameters ($model->{$c}, $ps, $oper, \@dpList);
			if ($inclChnNo) {
				push @$dplistref, map { "$c.$_" } @dpList;
			}
			else {
				push @$dplistref, @dpList;
			}
		}
		return $count;
	}
	else {
		return HMCCU_GetValidChannelParameters ($model, $ps, $oper, $dplistref);
	}
}

sub HMCCU_GetValidChannelParameters ($$$;$)
{
	my ($channelModel, $ps, $oper, $dplistref) = @_;

	my $count = 0;

	if (defined($channelModel) && exists($channelModel->{$ps})) {
		foreach my $dpt (keys %{$channelModel->{$ps}}) {
			if ($channelModel->{$ps}{$dpt}{OPERATIONS} & $oper) {
				push @$dplistref, $dpt if (defined($dplistref));
				$count++;
			}
		}
	}

	return $count;
}

######################################################################
# Get name of a CCU device by address.
# Channel number will be removed if specified.
######################################################################

sub HMCCU_GetDeviceName ($$;$)
{
	my ($hash, $addr, $default) = @_;
	$default //= '';
	
	if (HMCCU_IsValidDeviceOrChannel ($hash, $addr, $HMCCU_FL_ADDRESS)) {
		$addr =~ s/:[0-9]+$//;
		return $hash->{hmccu}{dev}{$addr}{name};
	}

	return $default;
}

######################################################################
# Get name of a CCU device channel by address.
######################################################################

sub HMCCU_GetChannelName ($$;$)
{
	my ($hash, $addr, $default) = @_;
	$default //= '';
	
	if (HMCCU_IsValidChannel ($hash, $addr, $HMCCU_FL_ADDRESS)) {
		return $hash->{hmccu}{dev}{$addr}{name};
	}

	return $default;
}

######################################################################
# Get type of a CCU device by address.
# Channel number will be removed if specified.
######################################################################

sub HMCCU_GetDeviceType ($$$)
{
	my ($hash, $addr, $default) = @_;

	if (HMCCU_IsValidDeviceOrChannel ($hash, $addr, $HMCCU_FL_ADDRESS)) {
		$addr =~ s/:[0-9]+$//;
		return $hash->{hmccu}{dev}{$addr}{type} // $default;
	}

	return $default;
}

######################################################################
# Get default RPC interface and port
######################################################################

sub HMCCU_GetDefaultInterface ($)
{
	my ($hash) = @_;
	
	my $ifname = $HMCCU_RPC_PRIORITY[0];
	my $ifport = $HMCCU_RPC_PORT{$ifname};
	
	foreach my $i (@HMCCU_RPC_PRIORITY) {
		if (exists ($hash->{hmccu}{interfaces}{$i}) && $hash->{hmccu}{interfaces}{$i}{devcount} > 0) {
			$ifname = $i;
			$ifport = $HMCCU_RPC_PORT{$i};
			last;
		}
	}
				
	return ($ifname, $ifport);
}

######################################################################
# Get interface of a CCU device by address.
# Channel number will be removed if specified.
######################################################################

sub HMCCU_GetDeviceInterface ($$;$)
{
	my ($hash, $addr, $default) = @_;
	$default //= '';

	if (HMCCU_IsValidDeviceOrChannel ($hash, $addr, $HMCCU_FL_ADDRESS)) {
		$addr =~ s/:[0-9]+$//;
		return $hash->{hmccu}{dev}{$addr}{interface};
	}

	return $default;
}

######################################################################
# Get address of a CCU device or channel by CCU name or FHEM device
# name defined via HMCCUCHN or HMCCUDEV. FHEM device names must be
# preceded by "hmccu:". CCU names can be preceded by "ccu:".
# Return array with device address, channel number and type
# If name is not found or refers to a device the default values will
# be returned.
######################################################################

sub HMCCU_GetAddress ($$;$$)
{
	my ($hash, $name, $defadd, $defchn) = @_;
	$defadd //= '';
	$defchn //= '';
	my $ioHash = HMCCU_GetHash ($hash);
	my $addr;
	my $iface;

	if ($name =~ /^hmccu:.+$/) {
		# Name is a FHEM device name
		my $chnno = $defchn;
		$name =~ s/^hmccu://;
		if ($name =~ /^([^:]+):([0-9]{1,2})$/) {
			$name = $1;
			$chnno = $2;
		}
		return ($defadd, $defchn, '') if (!exists($defs{$name}));
		my $dh = $defs{$name};
		return ($defadd, $defchn, '') if ($dh->{TYPE} ne 'HMCCUCHN' && $dh->{TYPE} ne 'HMCCUDEV');
		return (HMCCU_SplitChnAddr ($dh->{ccuaddr}, $chnno), $hash->{ccuif});
	}
	elsif ($name =~ /^ccu:.+$/) {
		# Name is a CCU device or channel name
		$name =~ s/^ccu://;
	}

	if (exists ($ioHash->{hmccu}{adr}{$name})) {
		# $name is a name and known by HMCCU
		$addr = $ioHash->{hmccu}{adr}{$name}{address};
		HMCCU_Trace ($hash, 2, "GetAddress by name $name");
	}
	elsif (exists ($ioHash->{hmccu}{dev}{$name})) {
		# $name is an address and known by HMCCU
		$addr = $name;
		HMCCU_Trace ($hash, 2, "GetAddress by address $name");
	}
	else {
		# Assume that $name is a device or channel name. Query CCU
		my ($dc, $cc) = HMCCU_GetDevice ($ioHash, $name);
		if ($dc > 0 && $cc > 0 && exists ($ioHash->{hmccu}{adr}{$name})) {
			$addr = $ioHash->{hmccu}{adr}{$name}{address};
		}
		HMCCU_Trace ($hash, 2, "GetAddress from CCU by name $name");
	}
	
	$addr //= '';

	HMCCU_Trace ($hash, 2, "Adress is $addr");

	if ($addr ne '') {
		my ($adr, $chn) = HMCCU_SplitChnAddr ($addr, $defchn);
		if (exists($ioHash->{hmccu}{dev}{$adr})) {
			$iface = $ioHash->{hmccu}{dev}{$adr}{interface};
		}
		$iface //= '';
		HMCCU_Trace ($hash, 2, "adr=$adr, chn=$chn, iface=$iface");
		return ($adr, $chn, $iface);
	}

	return ($defadd, $defchn, '');
}

######################################################################
# Check if parameter is a channel address (syntax)
# f=1: Interface required.
######################################################################

sub HMCCU_IsChnAddr ($$)
{
	my ($id, $f) = @_;

	if ($f) {
		return ($id =~ /^.+\.[\*]*[A-Z]{3}[0-9]{7}:[0-9]{1,2}$/ ||
		   $id =~ /^.+\.[0-9A-F]{12,14}:[0-9]{1,2}$/ ||
		   $id =~ /^.+\.OL-.+:[0-9]{1,2}$/ ||
		   $id =~ /^.+\.BidCoS-RF:[0-9]{1,2}$/) ? 1 : 0;
	}
	else {
		return ($id =~ /^[\*]*[A-Z]{3}[0-9]{7}:[0-9]{1,2}$/ ||
		   $id =~ /^[0-9A-F]{12,14}:[0-9]{1,2}$/ ||
		   $id =~ /^OL-.+:[0-9]{1,2}$/ ||
		   $id =~ /^BidCoS-RF:[0-9]{1,2}$/) ? 1 : 0;
	}
}

######################################################################
# Check if parameter is a device address (syntax)
# f=1: Interface required.
######################################################################

sub HMCCU_IsDevAddr ($$)
{
	my ($id, $f) = @_;

	if ($f) {
		return ($id =~ /^.+\.[\*]*[A-Z]{3}[0-9]{7}$/ ||
		   $id =~ /^.+\.[0-9A-F]{12,14}$/ ||
		   $id =~ /^.+\.OL-.+$/ ||
		   $id =~ /^.+\.BidCoS-RF$/) ? 1 : 0;
	}
	else {
		return ($id =~ /^[\*]*[A-Z]{3}[0-9]{7}$/ ||
		   $id =~ /^[0-9A-F]{12,14}$/ ||
		   $id =~ /^OL-.+$/ ||
		   $id eq 'BidCoS-RF') ? 1 : 0;
	}
}

######################################################################
# Split channel address into device address and channel number.
# Returns device address only if parameter is already a device address.
######################################################################

sub HMCCU_SplitChnAddr ($;$)
{
	my ($addr, $default) = @_;
	$default //= '';

	return ('', '') if (!defined($addr) || $addr eq '');
	
	my ($dev, $chn) = split (':', $addr);
	$chn = $default if (!defined ($chn));

	return ($dev, $chn);
}

######################################################################
# Split datapoint specification into channel number and datapoint name
######################################################################

sub HMCCU_SplitDatapoint ($;$)
{
	my ($dpt, $defchn) = @_;
	$defchn //= '';

	return ('', '') if (!defined($dpt));

	my @t = split (/\./, $dpt);
	
	return (scalar(@t) > 1) ? @t : ($defchn, $t[0]);
}

######################################################################
# Get channel address of FHEM device
######################################################################

sub HMCCU_GetChannelAddr ($;$)
{
	my ($clHash, $chn) = @_;

	if (exists($clHash->{ccuaddr})) {
		my ($d, $c) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
		$c = '0' if ($clHash->{TYPE} eq 'HMCCUDEV');
		$chn = $c if (!defined($chn) || $chn eq '');
		return "$d:$chn";
	}

	return '';
}

######################################################################
# Get list of client devices matching the specified criteria.
# If no criteria is specified all device names will be returned.
# Parameters modexp and namexp are regular expressions for module
# name and device name. Parameter internal contains a comma separated
# list of expressions like internal=valueexp.
# All parameters can be undefined. In this case all devices will be
# returned.
######################################################################
 
sub HMCCU_FindClientDevices ($$;$$)
{
	my ($hash, $modexp, $namexp, $internal) = @_;
	my @devlist = ();

	foreach my $d (keys %defs) {
		my $ch = $defs{$d};
		my $m = 1;
		next if (
			(!defined($ch->{TYPE}) || !defined($ch->{NAME})) ||
			(defined ($modexp) && $ch->{TYPE} !~ /$modexp/) ||
			(defined ($namexp) && $ch->{NAME} !~ /$namexp/) ||
			(defined ($hash) && exists ($ch->{IODev}) && $ch->{IODev} != $hash));
		if (defined($internal)) {
			foreach my $intspec (split (',', $internal)) {
				my ($i, $v) = split ('=', $intspec);
				if (!exists($ch->{$i}) || (defined ($v) && exists ($ch->{$i}) && $ch->{$i} !~ /$v/)) {
					$m = 0;
					last;
				}
			}
		}
		push @devlist, $ch->{NAME} if ($m == 1);
	}

	return @devlist;
}

######################################################################
# Check if client device already exists
# Parameter $devSpec is the name or address of a CCU device or channel
# Return name of existing FHEM device or empty string.
######################################################################

sub HMCCU_ExistsClientDevice ($$)
{
	my ($devSpec, $type) = @_;
	
	foreach my $d (keys %defs) {
		my $clHash = $defs{$d};
		return $clHash->{NAME} if (defined($clHash->{TYPE}) && $clHash->{TYPE} eq $type &&
			(defined($clHash->{ccuaddr}) && $clHash->{ccuaddr} eq $devSpec ||
			 defined($clHash->{ccuname}) && $clHash->{ccuname} eq $devSpec)
		);
	}
	
	return '';
}

######################################################################
# Get name of assigned client device of type HMCCURPCPROC.
# Create a RPC device of type HMCCURPCPROC if none is found and
# parameter create is set to 1.
# Return (devname, create).
# Return empty string for devname if RPC device cannot be identified
# or created. Return (devname,1) if device has been created and
# configuration should be saved.
######################################################################

sub HMCCU_GetRPCDevice ($$$)
{
	my ($hash, $create, $ifname) = @_;
	my $name = $hash->{NAME};
	my $rpcdevname;
	my $rpchost = $hash->{host};
	my $rpcprot = $hash->{prot};
	
	my $ccuflags = HMCCU_GetFlags ($name);

	return (HMCCU_Log ($hash, 1, 'Interface not defined for RPC server of type HMCCURPCPROC', ''))
		if (!defined($ifname));
	($rpcdevname, $rpchost) = HMCCU_GetRPCServerInfo ($hash, $ifname, 'device,host');
	return ($rpcdevname, 0) if (defined($rpcdevname));
	return ('', 0) if (!defined($rpchost));
	
	# Search for RPC devices associated with I/O device
	my @devlist;
	foreach my $dev (keys %defs) {
		my $devhash = $defs{$dev};
		next if ($devhash->{TYPE} ne 'HMCCURPCPROC');
		my $ip = !exists($devhash->{rpcip}) ? HMCCU_Resolve ($devhash->{host}, 'null') : $devhash->{rpcip};
		next if (($devhash->{host} ne $rpchost && $ip ne $rpchost) || $devhash->{rpcinterface} ne $ifname);
		push @devlist, $devhash->{NAME};
	}
	my $devcnt = scalar(@devlist);
	if ($devcnt == 1) {
		$hash->{hmccu}{interfaces}{$ifname}{device} = $devlist[0];
		return ($devlist[0], 0);
	}
	elsif ($devcnt > 1) {
		return (HMCCU_Log ($hash, 2, "Found more than one RPC device for interface $ifname", ''), 0);
	}
	
	HMCCU_Log ($hash, 1, "No RPC device defined for interface $ifname");
	
	# Create RPC device
	return $create ? HMCCU_CreateRPCDevice ($hash, $ifname, $rpcprot, $rpchost) : ('', 0);
}

######################################################################
# Create a new device of type HMCCURPCPROC for a RPC interface
# Return (deviceName, 1) on success.
# Return (errorMessage, 0) on error.
######################################################################

sub HMCCU_CreateRPCDevice ($$$$)
{
	my ($hash, $ifname, $rpcprot, $rpchost) = @_;
	
	my $ccuNum = $hash->{CCUNum} // '1';
	my $rpcdevname = 'd_rpc';

	# Ensure unique device name by appending last 2 digits of CCU IP address
	my $uID = HMCCU_GetIdFromIP ($hash->{ccuip}, '');
	$rpcdevname .= $uID;
	my $alias = "CCU ".($uID eq '' ? $ccuNum : $uID)." RPC $ifname";

	# Build device name and define command
	$rpcdevname = makeDeviceName ($rpcdevname.$ifname);
	my $rpccreate = "$rpcdevname HMCCURPCPROC $rpcprot://$rpchost $ifname";
	return (HMCCU_Log ($hash, 2, "Device $rpcdevname already exists. Please delete or rename it.", ''), 0)
		if (exists($defs{"$rpcdevname"}));

	# Create RPC device
	HMCCU_Log ($hash, 1, "Creating new RPC device $rpcdevname for interface $ifname");
	my $ret = CommandDefine (undef, $rpccreate);
	if (!defined($ret)) {
		# RPC device created. Set/copy some attributes from I/O device
		my %rpcdevattr = ('room' => 'copy', 'group' => 'copy', 'icon' => 'copy',
			'stateFormat' => 'rpcstate/state', 'eventMap' => '/rpcserver on:on/rpcserver off:off/',
			'verbose' => 2, 'alias' => $alias );
		foreach my $a (keys %rpcdevattr) {
			my $v = $rpcdevattr{$a} eq 'copy' ? AttrVal ($hash->{NAME}, $a, '') : $rpcdevattr{$a};
			CommandAttr (undef, "$rpcdevname $a $v") if ($v ne '');
		}
		return ($rpcdevname, 1);
	}
	else {
		HMCCU_Log ($hash, 1, "Definition of RPC device for interface $ifname failed. $ret");
		return ($ret, 0);
	}
}

######################################################################
# Assign IO device to client device.
# Wrapper function for AssignIOPort()
# Parameter $hash refers to a client device of type HMCCURPCPROC,
# HMCCUDEV or HMCCUCHN.
# Parameters ioname and ifname are optional.
# Return 1 on success or 0 on error.
######################################################################

sub HMCCU_AssignIODevice ($$;$)
{
	my ($hash, $ioName, $ifName) = @_;
	my $type = $hash->{TYPE};
	my $name = $hash->{NAME};
	my $ioHash;
	
	AssignIoPort ($hash, $ioName);
	
	$ioHash = $hash->{IODev} if (exists($hash->{IODev}));
	return HMCCU_Log ($hash, 1, "Can't assign I/O device", 0)
		if (!defined($ioHash) || !exists($ioHash->{TYPE}) || $ioHash->{TYPE} ne 'HMCCU');
	
	if ($type eq 'HMCCURPCPROC' && defined($ifName) && exists($ioHash->{hmccu}{interfaces}{$ifName})) {
		# Register RPC device
		$ioHash->{hmccu}{interfaces}{$ifName}{device} = $name;
	}
	
	return 1;
}

######################################################################
# Get hash of HMCCU IO device which is responsible for device or
# channel specified by parameter. If param is undef the first device
# of type HMCCU will be returned.
######################################################################

sub HMCCU_FindIODevice ($)
{
	my ($param) = @_;
	
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		my $disabled = AttrVal ($ch->{NAME}, 'disable', 0);
		next if (!exists($ch->{TYPE}) || $ch->{TYPE} ne 'HMCCU' || $disabled);
		
		return $ch if (!defined($param));
		return $ch if (HMCCU_IsValidDeviceOrChannel ($ch, $param, $HMCCU_FL_ALL));
	}
	
	return undef;
}

######################################################################
# Get states of IO devices
######################################################################

sub HMCCU_IODeviceStates ()
{
	my $active = 0;
	my $inactive = 0;
	
	# Search for first HMCCU device
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		next if (!exists($ch->{TYPE}) || $ch->{TYPE} ne 'HMCCU');
		if (exists($ch->{ccustate}) && $ch->{ccustate} eq 'active') {
			$active++;
		}
		else {
			$inactive++;
		}
	}	
	
	return ($active, $inactive);
}

######################################################################
# Get hash of HMCCU IO device. Useful for client devices. Accepts hash
# of HMCCU, HMCCUDEV or HMCCUCHN device as parameter.
# If hash is 0 or undefined the hash of the first device of type HMCCU
# will be returned.
######################################################################

sub HMCCU_GetHash ($@)
{
	my ($hash) = @_;

	if (defined($hash) && $hash != 0) {
		if ($hash->{TYPE} eq 'HMCCUDEV' || $hash->{TYPE} eq 'HMCCUCHN') {
			return $hash->{IODev} if (exists($hash->{IODev}));
			return HMCCU_FindIODevice ($hash->{ccuaddr}) if (exists($hash->{ccuaddr}));
		}
		elsif ($hash->{TYPE} eq 'HMCCU') {
			return $hash;
		}
	}

	# Search for first HMCCU device
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		next if (!exists($ch->{TYPE}));
		return $ch if ($ch->{TYPE} eq 'HMCCU');
	}

	return undef;
}

######################################################################
# Get attribute of client device. Fallback to attribute of IO device.
######################################################################

sub HMCCU_GetAttribute ($$$$)
{
	my ($ioHash, $clHash, $attrName, $attrDefault) = @_;

	my $value = AttrVal ($clHash->{NAME}, $attrName, '');
	$value = AttrVal ($ioHash->{NAME}, $attrName, $attrDefault) if ($value eq '');

	return $value;
}

######################################################################
# Set initial attributes after device definition as defined in IO
# device attribute ccudef-attributes
######################################################################

sub HMCCU_SetInitialAttributes ($$;$)
{
	my ($ioHash, $clName, $ah) = @_;

	my $ccudefAttributes = AttrVal ($ioHash->{NAME}, 'ccudef-attributes', '');
	foreach my $a (split(';', $ccudefAttributes)) {
		my ($an, $av) = split('=', $a);
		if (defined($ah)) {
			$ah->{$an} = $av;
		}
		else {
			CommandAttr (undef, "$clName $an $av") if (defined($av));
		}
	}
}

######################################################################
# Set default attributes for client device.
# Optionally delete obsolete attributes.
# Return (rc, messages).
# rc: 0=error, 1=success
# messages can be an empty string.
######################################################################

sub HMCCU_SetDefaultAttributes ($;$)
{
	my ($clHash, $parRef) = @_;
	my $ioHash = HMCCU_GetHash ($clHash);
	my $clType = $clHash->{TYPE};
	my $clName = $clHash->{NAME};
	
	$parRef //= { mode => 'update', role => undef, roleChn => undef };
	my $role;
	my @toast = ();
	my $rc = 1;

	if ($parRef->{mode} eq 'reset' || $parRef->{mode} eq 'forceReset') {
		my $detect = HMCCU_DetectDevice ($ioHash, $clHash->{ccuaddr}, $clHash->{ccuif});
		if (defined($detect) && $detect->{level} > 0) {
			# List of attributes which can be removed for devices known by HMCCU
			my @attrList = (
				'ccureadingname', 'ccuscaleval', 'cmdIcon', 'eventMap',
				'substitute', 'webCmd', 'widgetOverride'
			);
			# List of attributes to be removed
			my @removeAttr = ();
			# List of attributes to keep
			my @keepAttr = ();

			# Wrong module used for client device
			push @toast, "Device is of type HMCCUDEV, but HMCCUCHN is recommended. Please consider recreating the device with 'get createDev'."
				if (exists($detect->{defMod}) && $detect->{defMod} eq 'HMCCUCHN' && $clType eq 'HMCCUDEV');
			
			$role = HMCCU_GetChannelRole ($clHash, $detect->{defCCh});

			# Set attributes defined in IO device attribute ccudef-attributes
			HMCCU_SetInitialAttributes ($ioHash, $clName);

			# Remove additional attributes if device type is supported by HMCCU and attributes are not modified by user
			if (($detect->{level} == 5 && $detect->{rolePatternCount} > 1 && $clType eq 'HMCCUDEV' &&
				AttrVal ($clName, 'statedatapoint', '') eq '' && AttrVal ($clName, 'controldatapoint', '') eq '') ||
				($detect->{defSCh} == -1 && $detect->{defCCh} == -1))
			{
				push @toast, 'Please select a state and/or control datapoint by using attributes statedatapoint and controldatapoint.';
			}
			else {
				push @removeAttr, 'statechannel', 'statedatapoint' if ($detect->{defSCh} != -1);
				push @removeAttr, 'controlchannel', 'controldatapoint', 'statevals' if ($detect->{defCCh} != -1);
			}

			# Keep attribute if it differs from old defaults
			my $template = HMCCU_FindDefaults ($clHash);
			if (defined($template)) {
				foreach my $a (@attrList) {
					my $av = AttrVal ($clName, $a, '');
					if ($parRef->{mode} eq 'forceReset' || (exists($template->{$a}) && $av eq $template->{$a})) {
						push @removeAttr, $a;
						next;
					}

					push @keepAttr, $a if ($av ne '');
				}
			}

			push @toast, 'Attributes '.join(',',@keepAttr).' are no longer needed in 5.0 but differ from old 4.3 defaults. Please remove all HMCCU values from them or delete the attributes manually'
				if (scalar(@keepAttr) > 0);
			push @toast, 'Removed attributes '.join(',', @removeAttr) if (scalar(@removeAttr) > 0);

			# Remove attributes. Set flag 'setDefaults' to prevent calling HMCCU_SetDefaultSCDatapoints in Attr function
			# of client devices
			HMCCU_DeleteAttributes ($clHash, \@removeAttr, 1);

			my ($sc, $sd, $cc, $cd, $rsd, $rcd) = HMCCU_SetDefaultSCDatapoints ($ioHash, $clHash, $detect, 1);
			push @toast, 'Cannot set default state and control datapoint.'
				if ($rsd == 0 && $rcd == 0);
		}
		else {
			push @toast, "Device type $clHash->{ccutype} not known by HMCCU";
			$rc = 0;
		}
	}
	else {
		my $scc = HMCCU_StateOrControlChannel ($clHash);
		$role = $parRef->{role} // HMCCU_GetChannelRole ($clHash, $parRef->{roleChn} // $scc);
	}

	if (defined($role) && $role ne '') {
		# Set additional attributes
		if (exists($HMCCU_ATTR->{$role})) {
			foreach my $a (keys %{$HMCCU_ATTR->{$role}}) {
				CommandAttr (undef, "$clName $a ".$HMCCU_ATTR->{$role}{$a});
			}
		}
	}
	else {
		push @toast, "Cannot detect role of $clName";
	}

	return ($rc, join("\n", @toast));
}

######################################################################
# Delete list of attributes
######################################################################

sub HMCCU_DeleteAttributes ($$;$)
{
	my ($clHash, $attrList, $sem) = @_;
	$sem //= 0;
	my $clName = $clHash->{NAME};

	foreach my $a (@$attrList) {
		CommandDeleteAttr (undef, "$clName $a") if (exists($attr{$clName}{$a}));
	}
}

######################################################################
# Get state values of client device
# Return '' if no state values available
######################################################################

sub HMCCU_GetStateValues ($;$$)
{
	my ($clHash, $dpt, $ctrlChn) = @_;
	$dpt //= '';
	$ctrlChn //= '';

	my $ioHash = HMCCU_GetHash ($clHash);

	my $sv = AttrVal ($clHash->{NAME}, 'statevals', '');
	if ($sv eq '' && $dpt ne '' && $ctrlChn ne '') {
		my $role = HMCCU_GetChannelRole ($clHash, $ctrlChn);
		HMCCU_Trace ($clHash, 2, "dpt=$dpt, ctrlChn=$ctrlChn, role=$role");
		if ($role ne '' && exists($HMCCU_STATECONTROL->{$role}) &&
			HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$role}{C}, $clHash->{ccuif}) eq $dpt)
		{
			return $HMCCU_STATECONTROL->{$role}{V} eq '#' ?
				HMCCU_GetEnumValues ($ioHash, HMCCU_GetChannelAddr ($clHash, $ctrlChn), $HMCCU_STATECONTROL->{$role}{C}, $role, '#') :
				$HMCCU_STATECONTROL->{$role}{V};
		}
	}
	
	return $sv;
}

######################################################################
# Return additional commands depending on the channel role.
#
# Command-Defintion:
#   'Datapoint-Definition [...]'
# Datapoint-Definition:
#   Paramset:Datapoints:[+|-]Value
#   Paramset:Datapoints:?Parameter
#   Paramset:Datapoints:?Parameter=Default-Value
#   Paramset:Datapoints:#Parameter[=Value1[,...]]
# Paramset:
#   V=VALUES, M=MASTER (channel), D=MASTER (device)
# Datapoints:
#   List of parameter names separated by ,
# If Parameter is preceded by ? any value is accepted.
# If Parameter is preceded by #, Datapoint must have type ENUM or
# a list of values must be specified. 
# If Default-Value is preceeded by + or -, value is added to or 
# subtracted from current datapoint value.
#
# Output format:
# {cmdType}                       - Command type 'set' or 'get'
#   {'cmd'}{syntax}                 - Command syntax (input definition)
#   {'cmd'}{channel}                - Channel number
#   {'cmd'}{role}                   - Channel role
#   {'cmd'}{usage}                  - Usage string
#   {'cmd'}{subcount}               - Number of sub commands
#   {'cmd'}{subcmd}{'nnn'}{ps}      - Parameter set name
#   {'cmd'}{subcmd}{'nnn'}{dpt}     - Datapoint name
#   {'cmd'}{subcmd}{'nnn'}{type}    - Datapoint type
#   {'cmd'}{subcmd}{'nnn'}{parname} - Parameter name (default=datapoint)
#   {'cmd'}{subcmd}{'nnn'}{partype} - Parameter type (s. below)
#   {'cmd'}{subcmd}{'nnn'}{args}    - Comma separated list of valid values
#                                     or default value or fix value or ''
#   {'cmd'}{subcmd}{'nnn'}{min}     - Minimum value
#   {'cmd'}{subcmd}{'nnn'}{max}     - Maximum value
#   {'cmd'}{subcmd}{'nnn'}{unit}    - Unit of parameter value
#   {'cmd'}{subcmd}{'nnn'}{fnc}     - Function name (called with parameter value)
# {cmdlist}{set}                  - Set command definition
# {cmdlist}{get}                  - Get command definition
#
# Datapoint types: BOOL, INTEGER, ENUM, ACTION, STRING
#
# Parameter types:
#   0 = no parameter
#   1 = argument required, list of valid parameters defined
#   2 = argument required, default value may be available
#   3 = fix value, no argument required
#   4 = fix internal value, no argument required, default possible
######################################################################

sub HMCCU_UpdateRoleCommands ($$)
{
	my ($ioHash, $clHash) = @_;

	my %pset = ('V' => 'VALUES', 'M' => 'MASTER', 'D' => 'MASTER', 'I' => 'INTERNAL', 'S' => 'STRING');
	my @cmdSetList = ();
	my @cmdGetList = ();
	return if (HMCCU_IsFlag ($ioHash, 'noAutoDetect') || !defined($clHash->{hmccu}{role}) || $clHash->{hmccu}{role} eq '');

	my $chnNo //= '';
	my ($cc, $cd) = HMCCU_ControlDatapoint ($clHash);

	my $devName = $clHash->{NAME};
	my $devType = $clHash->{TYPE}; 

	# Delete existing role commands
	delete $clHash->{hmccu}{roleCmds} if (exists($clHash->{hmccu}{roleCmds}));

	my ($addr, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});

	URCROL: foreach my $chnRole (split(',', $clHash->{hmccu}{role})) {
		my ($channel, $role) = split(':', $chnRole);
		next URCROL if (!defined($role) || !exists($HMCCU_ROLECMDS->{$role}));
		
		URCCMD: foreach my $cmdKey (keys %{$HMCCU_ROLECMDS->{$role}}) {
			next URCCMD if ($chnNo ne '' && $chnNo != $channel && $chnNo ne 'd');
			next URCCMD if ($cmdKey eq 'COMBINED_PARAMETER' || $cmdKey eq 'SUBMIT');

			my ($cmd, $cmdIf) = split (':', $cmdKey);
			next URCCMD if (defined($cmdIf) && $clHash->{ccuif} !~ /$cmdIf/);

			my $cmdChn = $channel;
			my $cmdType = 'set';
			my $forceRPC = 0;
			if ($cmd =~ /^(set|get|rpcset|rpcget) (.+)$/) {
				$cmdType = $1;
				$cmd = $2;
				if ($cmdType =~ /^rpc/) {
					$forceRPC = 1;
					$cmdType =~ s/rpc//;
				}
			}
			next URCCMD if (exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}) && defined($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel}) &&
				$cc ne '' && "$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel}" eq "$cc");
			my $parAccess = $cmdType eq 'set' ? 2 : 5;

			my $cmdSyntax = $HMCCU_ROLECMDS->{$role}{$cmdKey};
			my $combDpt = '';
			if ($cmdSyntax =~ /^(COMBINED_PARAMETER|SUBMIT) /) {
				$combDpt = $1;
				$cmdSyntax =~ s/^(COMBINED_PARAMETER|SUBMIT) //;
				if (!HMCCU_IsValidParameter ($clHash, "$addr:$cmdChn", 'VALUES', $combDpt, $parAccess)) {
					HMCCU_Log ($clHash, 4, "HMCCUConf: Invalid parameter $addr:$cmdChn VALUES $combDpt $parAccess. Ignoring command $cmd in role $role for $devType device $devName");
					next URCCMD;
				}
			}
			
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{syntax} = $cmdSyntax;
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{role}   = $role;
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{rpc}    = $forceRPC;

			my $cnt = 0;
			my $cmdDef = $cmd;
			my $usage = $cmdDef;
			my $cmdArgList = '';
			my @parTypes = (0, 0, 0, 0, 0);
			my @combArgs = ();                        # Combined parameter components
			
			URCSUB: foreach my $subCmd (split(/\s+/, $cmdSyntax)) {
				my $pt = 0;                           # Default = no parameter (only valid for get commands)
				my $scn = sprintf ("%03d", $cnt);     # Subcommand number in command definition
				my $subCmdNo = $cnt;                  # Subcommand number in command execution
				my @subCmdList = split(/:/, $subCmd); # Split subcommand into tokens separated by ':'
				if ($subCmdList[0] =~ /^([0-9]+)$/) {
					$subCmdNo = $1;                   # Subcommand number specified
					shift @subCmdList;
				}
				my ($ps, $dptList, $par, $fnc) = @subCmdList;
				my $psName = $ps eq 'I' ? 'VALUES' : $pset{$ps};
				if (!defined($psName)) {
					HMCCU_Log ($clHash, 4, "HMCCUConf: Invalid or undefined parameter set. Ignoring command $cmd in role $role for $devType device $devName");
					next URCSUB;
				}
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{ps} //= $psName;
				if ($forceRPC && $psName ne $clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{ps}) {
					HMCCU_Log ($clHash, 2, "HMCCUConf: RPC mode doesn't allow mixed paramsets in one command");
					next URCSUB;
				}

				$cmdChn = 'd' if ($ps eq 'D');

				my $dptValid = 0;
				my $dpt = '';
				my $paramDef = { };

				if ($dptList ne '*') {
					# Allow different datapoint/config parameter names for same command, if name depends on firmware revision of device type
					# Find supported datapoint/config parameter
					foreach my $d (split /,/, $dptList) {
						next if (!defined($d) || $d eq '');
						if ($combDpt ne '') {
							next if (!exists($HMCCU_ROLECMDS->{$role}{$combDpt}{$d}));
							$dpt = $HMCCU_ROLECMDS->{$role}{$combDpt}{$d};
							push @combArgs, $d;
						}
						else {
							$dpt = $d;
						}
						if (HMCCU_IsValidParameter ($clHash, "$addr:$cmdChn", $psName, $dpt, $parAccess)) {
							$dptValid = 1;
							last;
						}
					}
					if (!$dptValid) {
						HMCCU_Log ($clHash, 4, "HMCCUConf: Unsupported parameter $addr:$cmdChn $psName $dpt $parAccess. Ignoring sub command $subCmd in role $role for $devType device $devName");
						next URCSUB;
					}
					
					$paramDef = HMCCU_GetParamDef ($ioHash, "$addr:$cmdChn", $psName, $dpt);
					if (!defined($paramDef)) {
						HMCCU_Log ($ioHash, 4, "HMCCUConf: Can't get definition of datapoint $addr:$cmdChn.$dpt. Ignoring command $cmd in role $role for $devType device $devName");
						next URCCMD;
					}
				}
				else {
					$dpt = '_any_';
				}

				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{scn}  = sprintf("%03d", $subCmdNo);
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{type} = $paramDef->{TYPE} // '';
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{min}  = $paramDef->{MIN};
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{max}  = $paramDef->{MAX};
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{unit} = $paramDef->{UNIT} // '';
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{ps}   = $psName;
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{dpt}  = $dpt;
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{fnc}  = $fnc // '';
			
				if (defined($par) && $par ne '') {
					if ($par =~ /^#(.+)$/) {
						# Parameter with list of values (either ENUM or fixed list)
						my ($pn, $pv) = split('=', $1);

						# Build lookup table
						my $argList = '';
						my $el = '';

						if (defined($pv) && $pv =~ /^[A-Z0-9_]+$/) {
							$paramDef = HMCCU_GetParamDef ($ioHash, "$addr:$cmdChn", 'VALUES', $pv);
							if (defined($paramDef)) {
								$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{min}  = $paramDef->{MIN};
								$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{max}  = $paramDef->{MAX};
								$el = HMCCU_GetEnumValues ($ioHash, $paramDef, $pv, $role, '#');
							}
						}
						else {
							$el = HMCCU_GetEnumValues ($ioHash, $paramDef, $dpt, $role, '#', $pv);
						}
						if ($el ne '') {
							my $min;
							my $max;
							my @cNames = ();
							foreach my $e (split(',',$el)) {
								my ($cNam, $cVal) = split (':', $e);
								if (defined($cVal)) {
									push @cNames, $cNam;
									if (!HMCCU_IsFltNum($cVal)) {
										HMCCU_Log ($clHash, 2, "cVal $cVal is not numeric. Enum = $el, type = $clHash->{ccutype}, dpt=$dpt, role=$role");
									}
									$min = $cVal if (!defined($min) || $cVal<$min);
									$max = $cVal if (!defined($max) || $cVal>$max);
									$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$cNam} = $cVal;
								}
							}
							$argList = join(',', @cNames);
								
							# Parameter definition contains names for min and max value
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{min} = $min;
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{max} = $max;
						}
						else {
							HMCCU_Log ($clHash, 2, "$cmdType $cmd: Cannot find enum values for parameter $pn, pv = $pv");
						}

						# Parameter list
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $pn;
						$pt = 1;   # Enum / List of fixed values

						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = $argList;
						$cmdArgList = $argList;
						$usage .= " {$argList}";
					}
					elsif ($par =~ /^\?(.+)$/) {
						# User must specify a parameter (default value possible)
						my ($pn, $pv) = split('=', $1);
						$pt = 2;
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $pn;
						if (defined($pv)) {
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = "$pv";
							$usage .= " [$pn]";
						}
						else {
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = '';
							$usage .= " $pn";
						}
					}
					elsif ($par =~ /^\*(.+)$/) {
						# Internal parameter taken from device hash (default value possible)
						my ($pn, $pv) = split('=', $1);
						$pt = 4;
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $pn;
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = $pv // '';
					}
					else {
						# Fix value. Parameter must not be specified
						my ($pn, $pv) = split('=', $par);
						$pt = 3;
						$pn = $dpt if(!defined($pv));
						$pv //= $par;
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $pn;
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = $pv;
					}
				}

				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{partype} = $pt;
				$parTypes[$pt]++;
				$cnt++;
			}

			if ($cnt == 0) {
				if (!exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcount})) {
					HMCCU_Log ($clHash, 4, "No datapoints found. Deleting command $cmd");
					delete $clHash->{hmccu}{roleCmds}{$cmdType}{$cmd};
				}
				next URCCMD;
			}
			
			if ($parTypes[1] == 1 && $parTypes[2] == 0 && $cmdArgList ne '') {
				# Only one variable argument. Argument belongs to a predefined value list
				# If values contain blanks, substitute blanks by # and enclose strings in quotes
				$cmdDef .= ':'.join(',', sort map { $_ =~ / / ? '"'.(s/ /#/gr).'"' : $_ } split(',', $cmdArgList));
			}
			elsif ($parTypes[1] == 0 && $parTypes[2] == 0) {
				$cmdDef .= ':noArg';
			}

			if ((!exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel})) || $cc eq $cmdChn) {
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel} = $cmdChn;
			}

			# if (exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel})) {
				# Same command in multiple channels.
				# Channel number will be set to control channel during command execution
			# 	$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel} = '?';
			# }
			# else {
			# 	$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel} = $cmdChn;
			# }
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{usage}    = $usage;
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcount} = $cnt;
			if (scalar(@combArgs) > 0) {
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{combined}{dpt} = $combDpt;
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{combined}{str} = join(',', map { $_.'=%s' } @combArgs);
			}

			if ($cmdType eq 'set') {
				push @cmdSetList, $cmdDef;
			}
			else {
				push @cmdGetList, $cmdDef;
			}
		}
	}
	
	$clHash->{hmccu}{cmdlist}{set} = join(' ', @cmdSetList);
	$clHash->{hmccu}{cmdlist}{get} = join(' ', @cmdGetList);
	
 	return;
}

######################################################################
# Execute command related to role
# Parameters:
#   $mode - 'set' or 'get'
#   $command - The command
#   $a - Reference for argument array
#   $h - Reference for argument hash
# Parameter types:
#   0 = no parameter
#   1 = argument required, list of valid parameters defined
#   2 = argument required, default value may be available
#   3 = fix value, no argument required
#   4 = fix internal value, no argument required, default possible
######################################################################

sub HMCCU_ExecuteRoleCommand ($@)
{
	my ($ioHash, $clHash, $mode, $command, $a, $h) = @_;

	my $name = $clHash->{NAME};
	my $rc;
	my %dpval;	# Datapoint values
	my %cfval;	# Config values
	my %inval;	# Internal values
	my %cmdFnc;
	my ($devAddr, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	my $usage = $clHash->{hmccu}{roleCmds}{$mode}{$command}{usage};
	my $forceRPC = $clHash->{hmccu}{roleCmds}{$mode}{$command}{rpc};
	my $psName = $clHash->{hmccu}{roleCmds}{$mode}{$command}{ps} // 'MASTER';

	my $channel = $clHash->{hmccu}{roleCmds}{$mode}{$command}{channel} // '?';
	if ("$channel" eq '?') {
		my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
		return HMCCU_SetError ($clHash, -12) if ($cc eq '');
		$channel = $cc;
	}
	my $chnAddr = "$devAddr:$channel";

	my ($combDpt, $combStr) = exists($clHash->{hmccu}{roleCmds}{$mode}{$command}{combined}) ?
		($clHash->{hmccu}{roleCmds}{$mode}{$command}{combined}{dpt}, $clHash->{hmccu}{roleCmds}{$mode}{$command}{combined}{str}) :
		('', '');
	my @combArgs = ();

	foreach my $cmdNo (sort keys %{$clHash->{hmccu}{roleCmds}{$mode}{$command}{subcmd}}) {
		my $cmd = $clHash->{hmccu}{roleCmds}{$mode}{$command}{subcmd}{$cmdNo};
		my $value;
		my @par = ();
		my $autoscale = 0;
		
		if ($cmd->{ps} ne 'INTERNAL' && $cmd->{dpt} ne '_any_' && !HMCCU_IsValidParameter ($clHash, $chnAddr, $cmd->{ps}, $cmd->{dpt})) {
			HMCCU_Trace ($clHash, 2, "Invalid parameter $cmd->{ps}.$cmd->{dpt} for command $command");
			return HMCCU_SetError ($clHash, -8, "$cmd->{ps}.$cmd->{dpt}");
		}
		
		if ($cmd->{partype} == 4) {
			# Internal value
			$value = $clHash->{hmccu}{intvalues}{$cmd->{parname}} // $cmd->{args};		
		}
		elsif ($cmd->{partype} == 3) {
			# Fixed value
			if ($cmd->{args} =~ /^[+-](.+)$/) {
				# Delta value
				return HMCCU_SetError ($clHash, "Current value of $channel.$cmd->{dpt} not available")
					if (!defined($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}));
				$value = HMCCU_MinMax ($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}+$cmd->{args},
					$cmd->{min}, $cmd->{max});
			}
			else {
				my @states = split (',', $cmd->{args});
				my $stc = scalar(@states);
				if ($stc > 1) {
					# Toggle
					my $curState = defined($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{VALUES}{NVAL}) ?
						$clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{VALUES}{NVAL} : $states[0];
					$value = '';
					my $st = 0;
					while ($st < $stc) {
						HMCCU_Trace ($clHash, 2, "curState=$curState states $st = ".$states[$st]);
						if (HMCCU_EQ($states[$st], $curState)) {
							$value = ($st == $stc-1) ? $states[0] : $states[$st+1];
							last;
						}
						$st++;
					}

					return HMCCU_SetError ($clHash, "Current device state doesn't match any state value")
						if ($value eq '');
				}
				else {
					$value = $cmd->{args};
				}
			}
		}
		elsif ($cmd->{partype} == 2) {
			# Normal value
			$value = shift @$a // $cmd->{args};
			return HMCCU_SetError ($clHash, "Missing parameter $cmd->{parname}.\nUsage: $mode $name $usage")
				if ($value eq '');
			return HMCCU_SetError ($clHash, "Usage: $mode $name $usage")
				if ($value eq '?');
			$autoscale = 1;
			if ($cmd->{args} =~ /^([+-])(.+)$/) {
				# Delta value. Sign depends on sign of default value. Sign of specified value is ignored
				return HMCCU_SetError ($clHash, "Current value of $channel.$cmd->{dpt} not available")
					if (!defined($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}));
				HMCCU_Trace($clHash, 2, "Current value of $channel.$cmd->{dpt} is ".$clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL});
#				$value = HMCCU_MinMax ($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}+$cmd->{args},
#					$cmd->{min}, $cmd->{max});
				$value = $clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}+$cmd->{args};
				HMCCU_Trace($clHash, 2, "New value is $value. Added ".$cmd->{args});
			}
			if ($cmd->{unit} eq 's') {
				$value = HMCCU_GetTimeSpec ($value);
				return HMCCU_SetError ($clHash, 'Wrong time format. Use seconds or HH:MM[:SS]')
					if ($value < 0);
			}
		}
		elsif ($cmd->{partype} == 1) {
			# Set of valid values
			my $vl = shift @$a // return HMCCU_SetError (
				$clHash, "Missing parameter $cmd->{parname}. Usage: $mode $name $usage");
			$value = $cmd->{look}{$vl} // return HMCCU_SetError (
				$clHash, "Illegal value $vl. Use one of ". join(',', keys %{$cmd->{look}}));
			push @par, $vl;
		}
		else {
			return HMCCU_SetError ($clHash, "Command type ".$cmd->{partype}." not supported");
		}

		return HMCCU_SetError ($clHash, "Command value not defined")
			if (!defined($value));

		# Align new value with min/max boundaries
		# if (exists($cmd->{min}) && exists($cmd->{max}) && HMCCU_IsFltNum($cmd->{min}) && HMCCU_IsFltNum($cmd->{max})) {
		# 	# Use mode = 2 in HMCCU_ScaleValue to get the min and max value allowed
		# 	HMCCU_Trace ($clHash, 2, "MinMax: value=$value, min=$cmd->{min}, max=$cmd->{max}");
		# 	my $scMin = HMCCU_ScaleValue ($clHash, $channel, $cmd->{dpt}, $cmd->{min}, 2);
		# 	my $scMax = HMCCU_ScaleValue ($clHash, $channel, $cmd->{dpt}, $cmd->{max}, 2);
		# 	$value = HMCCU_MinMax ($value, $scMin, $scMax);
		# 	HMCCU_Trace ($clHash, 2, "scMin=$scMin, scMax=$scMax, scVal=$value");
		# }
		
		if ($combDpt eq '') {
			if ($cmd->{ps} eq 'VALUES' && !$forceRPC) {	
				if ($cmd->{type} eq 'BOOL' && HMCCU_IsIntNum($value)) {
					$value = $value > 0 ? 'true' : 'false';
				}
				$dpval{"$cmd->{scn}.$clHash->{ccuif}.$chnAddr.$cmd->{dpt}"} = $value;
			}
			elsif ($cmd->{ps} eq 'INTERNAL') {
				$inval{$cmd->{parname}} = $value;
			}
			else {
				$cfval{$cmd->{dpt}} = $value;
			}
		}
		else {
			push @combArgs, $value;
		}

		push @par, $value if (defined($value));
		$cmdFnc{$cmdNo}{cmd} = $cmd;
		$cmdFnc{$cmdNo}{fnc} = $cmd->{fnc};
		$cmdFnc{$cmdNo}{par} = \@par;
	}

	if (scalar(@combArgs) > 0) {
		if ($forceRPC) {
			$cfval{$combDpt} = sprintf($combStr, @combArgs);
		}
		else {
			$dpval{"000.$clHash->{ccuif}.$chnAddr.$combDpt"} = sprintf($combStr, @combArgs);
		}
	}

	my $ndpval = scalar(keys %dpval);
	my $ncfval = scalar(keys %cfval);
	my $ninval = scalar(keys %inval);
	
	if ($mode eq 'set') {
		# Set commands
		if ($ninval > 0) {
			# Internal commands
			foreach my $iv (keys %inval) {
				HMCCU_Trace ($clHash, 2, "Internal $iv=$inval{$iv}");
				$clHash->{hmccu}{intvalues}{$iv} = $inval{$iv};
			}
			return HMCCU_SetError ($clHash, 0);
		}
		if ($ndpval > 0) {
			# Datapoint commands
			foreach my $dpv (keys %dpval) { HMCCU_Trace ($clHash, 2, "Datapoint $dpv=$dpval{$dpv}"); }
			$rc = HMCCU_SetMultipleDatapoints ($clHash, \%dpval);
			return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc));
		}
		if ($ncfval > 0) {
			# Config commands
			foreach my $pv (keys %cfval) { HMCCU_Trace ($clHash, 2, "Parameter $pv=$cfval{$pv}"); }
			($rc, undef) = HMCCU_SetMultipleParameters ($clHash, $chnAddr, \%cfval, $psName);
			return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc));
		}
	}
	else {
		# Get commands
		my $opt = '';
		if ($ndpval > 0 && $ncfval == 0) { $opt = 'values'; }
		elsif ($ndpval == 0 && $ncfval > 0) { $opt = 'config'; }
		elsif ($ndpval > 0 && $ncfval > 0) { $opt = 'update'; }

		if ($opt ne '') {
			$chnAddr =~ s/:d$//;
 			my $resp = HMCCU_ExecuteGetParameterCommand ($ioHash, $clHash, $opt, [ $chnAddr ]);
 			return HMCCU_SetError ($clHash, "Cannot get values for command") if (!defined($resp));
 			my $disp = '';
			foreach my $cmdNo (sort keys %cmdFnc) {
				if ($cmdFnc{$cmdNo}{fnc} ne '') {
					# :(
					no strict "refs";
					$disp .= &{$cmdFnc{$cmdNo}{fnc}}($ioHash, $clHash, $resp, $cmdFnc{$cmdNo}{cmd}, @{$cmdFnc{$cmdNo}{par}});
					use strict "refs";
				}
			}
			return $disp;
		}
	}
	
	return HMCCU_SetError ($clHash, "Command $command not executed");
}

######################################################################
# Execute set clear command
######################################################################

sub HMCCU_ExecuteSetClearCommand ($@)
{
	my ($clHash, $a) = @_;
	
	my $delPar = shift @$a // '.*';
	my $rnexp = '';
	if ($delPar eq 'reset') {
		$rnexp = '.*';
		delete $clHash->{hmccu}{dp};
	}
	else {
		$rnexp = $delPar;
	}
	HMCCU_DeleteReadings ($clHash, $rnexp);
	return HMCCU_SetState ($clHash, "OK");
}

######################################################################
# Execute set control command
######################################################################

sub HMCCU_ExecuteSetControlCommand ($@)
{
	my ($clHash, $a, $h) = @_;
	
	my $value = shift @$a // return HMCCU_SetError ($clHash, "Usage: set $clHash->{NAME} control {value}");
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
	my $stateVals = HMCCU_GetStateValues ($clHash, $cd, $cc);
	my $rc = HMCCU_SetMultipleDatapoints ($clHash,
		{ "001.$clHash->{ccuif}.$clHash->{ccuaddr}:$cc.$cd" => HMCCU_Substitute ($value, $stateVals, 1, undef, '') }
	);
	return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc));
}

######################################################################
# Execute set datapoint command
######################################################################

sub HMCCU_ExecuteSetDatapointCommand ($@)
{
	my ($clHash, $a, $h) = @_;
	
	my $ioHash = HMCCU_GetHash ($clHash);
	my $usage = "Usage: set $clHash->{NAME} datapoint [{no}:][{channel-number}.]{datapoint} {value|'oldval'} [...]";
	my %dpval;
	my $cmdNo = 0;
	my ($devAddr, $chnNo) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
	my $stVals = HMCCU_GetStateValues ($clHash, $cd, $cc);

	push (@$a, %${h}) if (defined($h));
	while (my $cdpt = shift @$a) {
		my $value = shift @$a // return HMCCU_SetError ($clHash, $usage);
		$cmdNo++;

		my $chnAddr = '';
		my $dpt = '';
		my $dptChn = $chnNo;

		# Check for command order number
		if ($cdpt =~ /^([0-9]+):/) {
			$cmdNo = $1;
			$cdpt =~ s/^[0-9]+://;
		}

		if ($clHash->{TYPE} eq 'HMCCUDEV') {
			if ($cdpt =~ /^([0-9]+)\.(.+)$/) {
				$chnAddr = "$devAddr:$1";
				$dptChn = $1;
				$dpt = $2;
				return HMCCU_SetError ($clHash, -7) if ($dptChn >= $clHash->{hmccu}{channels});
			}
			else {
				return HMCCU_SetError ($clHash, -12) if ($cc eq '');
				$dpt = $cdpt;
				$cdpt = "$cc.$cdpt";
				$chnAddr = "$devAddr:$cc";
			}
		}
		else {
			if ($cdpt =~ /^([0-9]+)\.(.+)$/) {
				$chnAddr = "$devAddr:$1";
				$dptChn = $1;
				$dpt = $2;
				return HMCCU_SetError ($clHash, -7) if ($dptChn != $chnNo);
			}
			else {
				$dpt = $cdpt;
				$cdpt = "$chnNo.$cdpt";
				$chnAddr = "$devAddr:$chnNo";
			}
		}

		my $paramDef = HMCCU_GetParamDef ($ioHash, $chnAddr, 'VALUES', $dpt);
		my $paramType = defined($paramDef) ? $paramDef->{TYPE} : '';

		# Show values allowed for datapoint
		if ($value eq '?' && defined($paramDef)) {
			if ($paramDef->{OPERATIONS} & 2) {
				if ($paramType ne 'ENUM') {
					my $min = $paramDef->{MIN} // '?';
					my $max = $paramDef->{MAX} // '?';
					my $unit = $paramDef->{UNIT} // '?';
					return "Usage: set $clHash->{NAME} datapoint $cdpt {$paramType} # min=$min max=$max unit=$unit";
				}
				else {
					return "Usage: set $clHash->{NAME} datapoint $cdpt {$paramDef->{VALUE_LIST}}";
				}
			}
			else {
				return "Datapoint $cdpt is not writeable";
			}
		}

		if (lc($value) eq 'oldval') {
			return "Old value of datapoint $dpt not available"
				if (!defined($clHash->{hmccu}{dp}{"$dptChn.$dpt"}{VALUES}{ONVAL}));
			$value = $clHash->{hmccu}{dp}{"$dptChn.$dpt"}{VALUES}{ONVAL};
		}

		$value = HMCCU_Substitute ($value, $stVals, 1, undef, '') if ($stVals ne '' && $dpt eq $cd);

		my $no = sprintf ("%03d", $cmdNo);
		$dpval{"$no.$clHash->{ccuif}.$chnAddr.$dpt"} = $value;
	}

	return HMCCU_SetError ($clHash, $usage) if (scalar(keys %dpval) < 1);
	
	my $rc = HMCCU_SetMultipleDatapoints ($clHash, \%dpval);
	return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc));
}

sub HMCCU_ExecuteGetDatapointCommand ($@)
{
	my ($clHash, $a) = @_;

	my $ioHash = HMCCU_GetHash ($clHash);
	my $usage = "Usage: get $clHash->{NAME} datapoint [{channel-number}.]{datapoint}";

	my $dpt = shift @$a // return HMCCU_SetError ($clHash, $usage);

	my $ccuget = HMCCU_GetAttribute ($ioHash, $clHash, 'ccuget', 'Value');

	my $chnadd = $clHash->{ccuaddr};

	if ($clHash->{TYPE} eq 'HMCCUDEV') {
		return $usage if ($dpt !~ /^([0-9]+)\.[A-Z0-9_]+$/);
		$chnadd = "$chnadd:$1";
	}
	else {
		return $usage if ($dpt !~ /^[A-Z0-9_]+$/);
	}

	my ($devadd, $chn) = HMCCU_SplitChnAddr ($chnadd);

	return "Invalid datapoint $dpt" if (!HMCCU_IsValidParameter ($clHash, "$chnadd", 'VALUES', $dpt, 1));

	my $cmd = 'Write((datapoints.Get("'.$clHash->{ccuif}.'.'.$chnadd.'.'.$dpt.'")).'.$ccuget.'())';
	my $value = HMCCU_HMCommand ($clHash, $cmd, 1);

	if (defined($value) && $value ne '' && $value ne 'null') {
		$value = HMCCU_UpdateSingleDatapoint ($clHash, $chn, $dpt, $value);
		HMCCU_Trace ($clHash, 2, "Value of $chn.$dpt = $value"); 
		return $value;
	}
	else {
		HMCCU_Log ($clHash, 1, "Error CMD = $cmd");
		return "Error executing command $cmd";
	}
}

######################################################################
# Execute set config / values / link command
# Usage of command in FHEM for HMCCUCHN devices:
#   MASTER: set config ['device'] parameter=value [...]
#   LINKS:  set config peer-address parameter=value [...]
#   VALUES: set values parameter=value [...]
# Usage of command in FHEM for HMCCUDEV devices:
#   MASTER: set config [channel] parameter=value [...]
#   LINKS:  set config channel peer-address parameter=value [...]
#   VALUES: set values channel parameter=value [...]
######################################################################

sub HMCCU_ExecuteSetParameterCommand ($@)
{
	my ($ioHash, $clHash, $command, $a, $h) = @_;

	my $paramset = $command eq 'config' ? 'MASTER' : 'VALUES';
	my $rc;
	my $result = '';
	my $receiver = '';
	my $ccuobj = $clHash->{ccuaddr};
	
	return HMCCU_SetError ($clHash, 'No parameter specified') if ((scalar keys %{$h}) < 1);	

	my $p = shift @$a;
	if (defined($p)) {
		if ($clHash->{TYPE} eq 'HMCCUDEV') {
			if ($p =~ /^([0-9]{1,2})$/) {
				return HMCCU_SetError ($clHash, -7) if ($p >= $clHash->{hmccu}{channels});
				$ccuobj .= ':'.$p;
				$p = shift @$a;
				if (defined($p)) {
					$receiver = $p;
					$paramset = 'LINK';
				}
			}
		}
		else {
			if (lc($p) eq 'device') {
				($ccuobj, undef) = HMCCU_SplitChnAddr ($ccuobj);
			}
			else {
				$receiver = $p;
				$paramset = 'LINK';
			}
		}
	}
	
	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $ccuobj, $clHash->{ccuif}) //
		return HMCCU_SetError ($clHash, "Can't get device description");
	return HMCCU_SetError ($clHash, "Paramset $paramset not supported by device or channel")
		if ($devDesc->{PARAMSETS} !~ /$paramset/);
	if (!HMCCU_IsValidParameter ($ioHash, $devDesc, $paramset, $h)) {
		my $paramDef = HMCCU_GetParamDef ($ioHash, $devDesc, $paramset);
		if (defined($paramDef)) {
			my @parList = map { $paramDef->{$_}{OPERATIONS} == 2 ? $_ : () } keys %$paramDef;
			return HMCCU_SetError ($clHash, 'Invalid parameter specified. Valid parameters: '.
				join(',', @parList)) if (scalar(@parList) > 0);
		}
		return HMCCU_SetError ($clHash, 'Invalid parameter specified');
	}
			
	if ($paramset eq 'VALUES' || $paramset eq 'MASTER') {
		($rc, $result) = HMCCU_SetMultipleParameters ($clHash, $ccuobj, $h, $paramset);
	}
	else {
		if (exists($defs{$receiver}) && defined($defs{$receiver}->{TYPE})) {
			my $clRecHash = $defs{$receiver};
			if ($clRecHash->{TYPE} eq 'HMCCUDEV') {
				my $chnNo = shift @$a;
				return HMCCU_SetError ($clHash, 'Channel number required for link receiver')
					if (!defined($chnNo) || $chnNo !~ /^[0-9]{1,2}$/);
				$receiver = $clRecHash->{ccuaddr}.":$chnNo";
			}
			elsif ($clRecHash->{TYPE} eq 'HMCCUCHN') {
				$receiver = $clRecHash->{ccuaddr};
			}
			else {
				return HMCCU_SetError ($clHash, "Receiver $receiver is not a HMCCUCHN or HMCCUDEV device");
			}
		}
		elsif (!HMCCU_IsChnAddr ($receiver, 0)) {
			my ($rcvAdd, $rcvChn) = HMCCU_GetAddress ($ioHash, $receiver);
			return HMCCU_SetError ($clHash, "$receiver is not a valid CCU channel name")
				if ($rcvAdd eq '' || $rcvChn eq '');
			$receiver = "$rcvAdd:$rcvChn";
		}

		return HMCCU_SetError ($clHash, "$receiver is not a link receiver of $clHash->{NAME}")
			if (!HMCCU_IsValidReceiver ($ioHash, $ccuobj, $clHash->{ccuif}, $receiver));
		($rc, $result) = HMCCU_RPCParamsetRequest ($clHash, 'putParamset', $ccuobj, $receiver, $h);
	}

	return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc), $result);
}

######################################################################
# Execute command to show device information
######################################################################

sub HMCCU_ExecuteGetDeviceInfoCommand ($@)
{
	my ($ioHash, $clHash, $address, $extended) = @_;
	$extended //= 0;

	my $iface = HMCCU_GetDeviceInterface ($ioHash, $address);
	my $result = HMCCU_GetDeviceInfo ($clHash, $address);
	return HMCCU_SetError ($clHash, -2) if ($result eq '');

	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
	my $devInfo = '<html><b>Device channels and datapoints</b><br/><br/>';
	$devInfo .= '<pre>';
	$devInfo .= HMCCU_FormatDeviceInfo ($result);
	$devInfo .= '</pre>';
	my $detect = HMCCU_DetectDevice ($ioHash, $address, $iface);
	if (defined($detect)) {
		$devInfo .= "<br/>Device detection:<br/>";
		if ($detect->{stateRoleCount} > 0) {
			foreach my $c (sort keys %{$detect->{stateRole}}) {
				my $stateChn = $detect->{stateRole}{$c};
				$devInfo .= "StateDatapoint = $c.$stateChn->{datapoint} [$stateChn->{role}]<br/>";
			}
		}
		else {
			$devInfo .= 'No state datapoint detected<br/>';
		}
		if ($detect->{controlRoleCount} > 0) {
			foreach my $c (sort keys %{$detect->{controlRole}}) {
				my $ctrlChn = $detect->{controlRole}{$c};
				$devInfo .= "ControlDatapoint = $c.$ctrlChn->{datapoint} [$ctrlChn->{role}]<br/>";
			}
		}
		else {
			$devInfo .= 'No control datapoint detected<br/>';
		}
		$devInfo .=  $detect->{defMod} ne '' ?
			"<br/>Recommended module for device definition: $detect->{defMod}<br/>" :
			"<br/>Failed to detect device settings. Device must be configured manually.<br/>";
		if ($extended) {
			$devInfo .=  "<br/>Detection level: $detect->{level}<br/>".
				"<br/>Detected default state datapoint: $detect->{defSDP}<br/>".	
				"<br/>Detected default control datapoint: $detect->{defCDP}<br/>".
				"<br/>Unique state roles: $detect->{uniqueStateRoleCount}<br/>".
				"<br/>Unique control roles: $detect->{uniqueControlRoleCount}<br/>";		
		}
	}
	$devInfo .= "<br/>Current state datapoint = $sc.$sd<br/>" if ($sc ne '' && $sd ne '');
	$devInfo .= "<br/>Current control datapoint = $cc.$cd<br/>" if ($cc ne '' && $cd ne '');
	$devInfo .= '<br/><b>Device description</b><br/><br/><pre>';
	$result = HMCCU_DeviceDescToStr ($ioHash, $clHash->{TYPE} eq 'HMCCU' ? $address : $clHash);
	$devInfo .= '</pre>';
	$devInfo .= defined($result) ? $result : "Can't get device description<br/>";
	if ($clHash->{TYPE} ne 'HMCCU') {
		$devInfo .= '<br/>Defaults<br/><br/>';
		$devInfo .= HMCCU_GetDefaults ($clHash);
	}

	return $devInfo;
}

######################################################################
# Execute commands to fetch device parameters
######################################################################

sub HMCCU_ExecuteGetParameterCommand ($@)
{
	my ($ioHash, $clHash, $command, $addList, $filter) = @_;
	$filter //= '.*';

	my %parSets = ('config' => 'MASTER,LINK', 'values' => 'VALUES', 'update' => 'VALUES,MASTER,LINK');
	my $defParamset = $parSets{$command};
	
	my %objects;
	foreach my $a (@$addList) {
		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $a, $clHash->{ccuif});
		if (!defined($devDesc)) {
			HMCCU_Log ($clHash, 2, "Can't get device description");
			return undef;
		}
		
		my $paramset = $defParamset eq '' ? $devDesc->{PARAMSETS} : $defParamset;
		my ($da, $dc) = HMCCU_SplitChnAddr ($a, 'd');

		foreach my $ps (split (',', $paramset)) {
			next if ($ps eq 'SERVICE' || $devDesc->{PARAMSETS} !~ /$ps/);

			if ($ps eq 'LINK') {
				foreach my $rcv (HMCCU_GetReceivers ($ioHash, $a, $clHash->{ccuif})) {
					my ($rc, $result) = HMCCU_RPCParamsetRequest ($clHash, 'getParamset', $a, $rcv);
					next if ($rc < 0);
					foreach my $p (keys %$result) {
						$objects{$da}{$dc}{"LINK.$rcv"}{$p} = $result->{$p} if ($p =~ /$filter/);
					}					
				}
			}
			else {
				my ($rc, $result) = HMCCU_RPCParamsetRequest ($clHash, 'getParamset', $a, $ps);
				if ($rc < 0) {
					my $m = $result ne '' ? $result : $HMCCU_ERR_LIST{$rc} // '';
					HMCCU_Log ($clHash, 2, "Can't get parameterset $ps for address $a: $m");
					next;
				}
				foreach my $p (keys %$result) {
					$objects{$da}{$dc}{$ps}{$p} = $result->{$p} if ($p =~ /$filter/);
				}
			}
		}
	}
	
	return \%objects;
}

sub HMCCU_ExecuteGetExtValuesCommand ($@)
{
	my ($clHash, $addr, $filter, $ccuget) = @_;
	$filter //= '.*';
	$ccuget //= 'Value';

	my $name = $clHash->{NAME};
	my $type = $clHash->{TYPE};
	my $ifname = $clHash->{ccuif};
	my $devexp = '^'.$name.'$';

	return 1 if (!HMCCU_IsDeviceActive ($clHash));
	my $ioHash = HMCCU_GetHash ($clHash) // return -3;
	return -4 if ($type ne 'HMCCU' && $clHash->{ccudevstate} eq 'deleted');

	$ccuget = HMCCU_GetAttribute ($ioHash, $clHash, 'ccuget', 'Value') if ($ccuget eq 'Attr');
	my $nonBlock = HMCCU_IsFlag ($ioHash->{NAME}, 'nonBlocking') ? 1 : 0;

	return HMCCU_UpdateClients ($ioHash, $devexp, $ccuget, $ifname, $nonBlock);
}

######################################################################
# Read meta data of device or channel
######################################################################

sub HMCCU_ExecuteGetMetaDataCommand ($@)
{
	my ($ioHash, $clHash, $filter) = @_;
	$filter //= '.*';

	my $response = HMCCU_HMScriptExt ($ioHash, '!GetMetaData', { name => $clHash->{ccuname} });
	return (-2, $response) if ($response eq '' || $response =~ /^ERROR:.*/);
  
	my %readings;
	my $count = 0;
	my $result = '';

	foreach my $meta (split /[\n\r]+/, $response) {
		# Array values: 0=dataId, 1=value
		my ($address, $dataId, $value) = split /=/, $meta;
		if (!defined($dataId)) {
			# Return error message from script
			return (-2, $address) if (defined($address));
			next;
		}
		next if ($dataId !~ /$filter/);
		$value //= '';
		my ($devAddr, $chnNo) = HMCCU_SplitChnAddr ($address);
		my $rn = HMCCU_CorrectName ($dataId);
		$rn = "$chnNo.$rn" if ($chnNo ne '' && $clHash->{TYPE} eq 'HMCCUDEV');
		my $rv = HMCCU_ISO2UTF ($value);
		$readings{$rn} = HMCCU_FormatReadingValue ($clHash, $rv, $dataId);
		$result .= "$rn=$rv\n";
		$count++;
	}
	
	HMCCU_UpdateReadings ($clHash, \%readings) if ($count > 0);

	return ($count, $count > 0 ? $result: 'OK');
}

######################################################################
# Convert results into a readable format
######################################################################

sub HMCCU_DisplayGetParameterResult ($$$)
{
	my ($ioHash, $clHash, $objects) = @_;
	
	my $res = '';
	my $flags = HMCCU_GetFlags ($clHash->{NAME});
	$res = "Info: Readings for config parameters are not updated until you set showXXX flags in attribute ccuflags\n\n"
		if ($flags !~ /show(Master|Device)/);
	if (scalar(keys %$objects) > 0) {
		my $convRes = HMCCU_UpdateParamsetReadings ($ioHash, $clHash, $objects);
		if (defined($convRes)) {
			foreach my $da (sort keys %$convRes) {
				$res .= "Device $da\n";
				foreach my $dc (sort keys %{$convRes->{$da}}) {
					foreach my $ps (sort keys %{$convRes->{$da}{$dc}}) { 
						$res .= "  Channel $dc [$ps]\n".
							join ("\n", map { 
								"    ".$_.' = '.$convRes->{$da}{$dc}{$ps}{$_}
							} sort keys %{$convRes->{$da}{$dc}{$ps}})."\n";
					}
				}
			}
		}
	}
	
	return $res;
}

######################################################################
# Get week program(s) as html table
######################################################################

sub HMCCU_DisplayWeekProgram ($$$;$$)
{
	my ($ioHash, $clHash, $resp, $cmd, $programName, $program) = @_;
	$programName //= 'all';
	$program //= 'all';
	
	my @weekDay = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday');
	
	my $convRes = HMCCU_UpdateParamsetReadings ($ioHash, $clHash, $resp);

	return "No data available for week program(s) $program"
		if (!exists($clHash->{hmccu}{tt}) || ($program ne 'all' && !exists($clHash->{hmccu}{tt}{$program})));

	if (defined($cmd->{min}) && HMCCU_IsIntNum($cmd->{min}) && $cmd->{min} > 0) {
		$program -= $cmd->{min};
	}

	my $s = '<html>';
	foreach my $w (sort keys %{$clHash->{hmccu}{tt}}) {
		next if ("$w" ne "$program" && "$program" ne 'all');
#		$w-- if ("$program" eq "$programName" && HMCCU_IsIntNum($program) && $w > 0);
		my $p = $clHash->{hmccu}{tt}{$w};
		my $pn = $programName ne 'all' ? $programName : $w+1;
		$s .= '<p><b>Week Program '.$pn.'</b></p><br/><table border="1">';
		foreach my $d (sort keys %{$p->{ENDTIME}}) {
			my $beginTime = '00:00';
			$s .= '<tr><td style="padding: 2px"><b>'.$weekDay[$d].'</b></td>';
			foreach my $h (sort { $a <=> $b } keys %{$p->{ENDTIME}{$d}}) {
				$s .= '<td style="padding: 2px">'.$beginTime.' - '.$p->{ENDTIME}{$d}{$h}.': '.$p->{TEMPERATURE}{$d}{$h}.'&deg;</td>';
				last if ($p->{ENDTIME}{$d}{$h} eq '24:00');
				$beginTime = $p->{ENDTIME}{$d}{$h};
			}
			$s .= '</tr>';
		}
		$s .= '</table><br/>';
	}
	$s .= '</html>';

	return $s;
}

######################################################################
# Check if value matches parameter definition
# Parameter t can be a datapoint type or a hash reference to a role
# command parameter definition.
# Parameter list can be a comma separated list of valid values.
######################################################################

sub HMCCU_CheckParameter ($$;$$$)
{
	my ($v, $t, $min, $max, $list) = @_;
	
	return 0 if (!defined($v) || !defined($t));

	my $type;
	
	if (ref($t) eq 'HASH') {
		$type = $t->{type};
		if ($type eq 'ENUM') {
			return exists($t->{look}) && exists($t->{look}{$v}) ||
				(HMCCU_IsIntNum ($v) && (!defined($min) || $v >= $min) && (!defined($max) || $v <= $max)) ? 1 : 0;
		}
		$min = $t->{min};
		$max = $t->{max};
	}
	else {
		$type = $t;
	}
	
	if ($type eq 'BOOL') {
		return $v =~ /^(true|false|1|0)$/ ? 1 : 0;
	}
	elsif ($type eq 'INTEGER') {
		return HMCCU_IsIntNum ($v) && (!defined($min) || $v >= $min) && (!defined($max) || $v <= $max);
	}
	elsif ($type eq 'FLOAT' || $type eq 'DOUBLE') {
		return HMCCU_IsFltNum ($v) && (!defined($min) || $v >= $min) && (!defined($max) || $v <= $max);
	}
	elsif ($type eq 'ENUM') {
		if (HMCCU_IsIntNum ($v)) {
			return (!defined($min) || $v >= $min) && (!defined($max) || $v <= $max) ? 1 : 0;
		}
		elsif (defined($list)) {
			foreach my $le (split(',', $list)) { return 1 if ($v eq $le); }
		}
	}
	elsif ($type eq 'ACTION') {
		return $v =~ /^[01]$/ ? 1 : 0;
	}
	elsif ($type eq 'STRING') {
		return 1;
	}
	
	return 0;
}

######################################################################
# Set or delete state and control datapoints
# Parameter d specifies the value to be set:
#   state, control, statechannel, statedatapoint, controlchannel,
#   controldatapoint
# Parameter v is the statedatapoint or controldatapoint including
# the channel number.
# If parameter v is missing, the attribute is deleted
# Parameter r contains the role.
# If $cmd == 1 update role commands.
# Return:
#   0=Error, 1=Success
######################################################################

sub HMCCU_SetSCDatapoints ($$;$$$)
{
	my ($clHash, $d, $v, $r, $cmd) = @_;

	my $ioHash = HMCCU_GetHash ($clHash);
	my $addr = $clHash->{ccuaddr};
	$r //= '';
	$cmd //= 0;

	# Flags: 1=statechannel, 2=statedatapoint, 4=controlchannel, 8=controldatapoint
	my %flags = (
		'state' => 3, 'control' => 12,
		'statechannel' => 1, 'statedatapoint' => 2,
		'controlchannel' => 4, 'controldatapoint' => 8
	);

	my $chn;
	my $dpt;
	my $f = $flags{$d} // return 0;

	# $d becomes the hash key: state or control
	$d =~ s/^(state|control)(channel|datapoint)$/$1/;
	return 0 if ($d ne 'state' && $d ne 'control');

	if (defined($v)) {
		# Set value
		return 0 if (!HMCCU_IsDeviceActive ($clHash) || $v eq '' || $v eq '.' || $v =~ /^[0-9]+\.$/ || $v =~ /^\..+$/);

#		HMCCU_Log ($clHash, 2, "SetSCDatapoint $v");

		if ($f & 10) {
			# statedatapoint / controldatapoint
			if ($v =~ /^([0-9]{1,2})\.(.+)$/) {
				($chn, $dpt) = ($1, $2);
			}
			else {
				($chn, $dpt) = ($clHash->{hmccu}{$d}{chn}, $v);
				if ((!defined($chn) || $chn eq '') && $clHash->{TYPE} eq 'HMCCUCHN') {
					my ($da, $cn) = HMCCU_SplitChnAddr ($addr);
					$chn = $cn;
				}
			}
		}
		elsif ($f & 5) {
			# statechannel / controlchannel
			return 0 if ($v !~ /^[0-9]{1,2}$/);
			($chn, $dpt) = ($v, $clHash->{hmccu}{$d}{dpt});
		}
		HMCCU_Log ($clHash, 2, "f=$f chn not defined in $d $v".stacktraceAsString(undef)) if (!defined($chn));
		HMCCU_Log ($clHash, 2, "f=$f dpt not defined in $d $v".stacktraceAsString(undef)) if (!defined($dpt) && !($f & 5));

		if ($init_done && defined($chn) && $chn ne '' && defined($dpt) && $dpt ne '' &&
			!HMCCU_IsValidParameter ($clHash, HMCCU_GetChannelAddr ($clHash, $chn), 'VALUES', $dpt, $f & 3 ? 5 : 2))
		{
			HMCCU_Log ($clHash, 2, "Invalid datapoint $chn.$dpt for parameter $d");
			return 0;	
		}

		$clHash->{ccurolestate} = $r if ($r ne '' && $f & 3);
		$clHash->{ccurolectrl} = $r if ($r ne '' && $f & 12);
	}
	else {
		# Delete value
		$chn = '' if ($f & 5);
		$dpt = '' if ($f & 10);
		delete $clHash->{ccurolestate} if ($f & 3);
		delete $clHash->{ccurolectrl} if ($f & 12);
	}

	$clHash->{hmccu}{$d}{chn} = $chn if (defined($chn));
	$clHash->{hmccu}{$d}{dpt} = $dpt if (defined($dpt));

	# Try to set missing state/control datapoint to the same datapoint
	if (defined($chn) && defined($dpt) && defined($clHash->{ccuaddr})) {
		my ($da, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
		if ($d eq 'control' && !HMCCU_IsValidStateDatapoint ($clHash, 1) &&
			HMCCU_IsValidParameter ($clHash, "$da:$chn", 'VALUES', $dpt, 5)
		) {
			$clHash->{hmccu}{state}{chn} = $chn;
			$clHash->{hmccu}{state}{dpt} = $dpt;
		}
		elsif ($d eq 'state' && !HMCCU_IsValidControlDatapoint ($clHash, 1) &&
			HMCCU_IsValidParameter ($clHash, "$da:$chn", 'VALUES', $dpt, 2)
		) {
			$clHash->{hmccu}{control}{chn} = $chn;
			$clHash->{hmccu}{control}{dpt} = $dpt;
		}
	}

	# Optionally update internal command tables
	if ($cmd) {
		my ($cc, $cd) = HMCCU_ControlDatapoint ($clHash);
		if ($cc ne '' && $cd ne '') {		
			HMCCU_UpdateRoleCommands ($ioHash, $clHash);
		}
	}

	return 1;
}

######################################################################
# Set default state and control datapoint
# If $cmd == 1 update role commands
######################################################################

sub HMCCU_SetDefaultSCDatapoints ($$;$$)
{
	my ($ioHash, $clHash, $detect, $cmd) = @_;

 	$detect //= HMCCU_DetectDevice ($ioHash, $clHash->{ccuaddr}, $clHash->{ccuif});
	$cmd //= 0;

	my ($sc, $sd, $cc, $cd) = ('', '', '', '');
	my $clName = $clHash->{NAME};
	my $clType = $clHash->{TYPE};

	# Prio 4: Use information from device detection
	if (defined($detect)) {
		$sc = $detect->{defSCh} if ($detect->{defSCh} != -1);
		$cc = $detect->{defCCh} if ($detect->{defCCh} != -1);
		$sd = $detect->{stateRole}{$sc}{datapoint} if ($sc ne '' && exists($detect->{stateRole}{$sc}));
		$cd = $detect->{controlRole}{$cc}{datapoint} if ($cc ne '' && exists($detect->{controlRole}{$cc}));
#		HMCCU_Log ($clHash, 2, "Prio 4: s=$sc.$sd c=$cc.$cd");
	}

	# Prio 3: Use information stored in device hash (HMCCUDEV only)
	if ($clType eq 'HMCCUDEV') {
		# Support for level 5 devices
		($sc, $sd) = HMCCU_SplitDatapoint ($clHash->{hmccu}{defSDP}) if (defined($clHash->{hmccu}{defSDP}));
		($cc, $cd) = HMCCU_SplitDatapoint ($clHash->{hmccu}{defCDP}) if (defined($clHash->{hmccu}{defCDP}));
#		HMCCU_Log ($clHash, 2, "Prio 3: s=$sc.$sd c=$cc.$cd");
	}

	# Prio 2: Use attribute statechannel and controlchannel for HMCCUDEV and channel address for HMCCUCHN
	my ($asc, $acc) = ('', '');
	if ($clType eq 'HMCCUCHN') {
		# State and control channel of HMCCUCHN devices is defined by channel address
		my $da;
		($da, $asc) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
		$acc = $asc;
	}
	else {
		# Consider attributes statechannel and controlchannel for HMCCUDEV devices
		$asc = AttrVal ($clName, 'statechannel', $sc);
		$acc = AttrVal ($clName, 'controlchannel', $cc);
	}
	# Correct datapoints
	if (defined($detect)) {
		if ($asc ne '' && exists($detect->{stateRole}) && exists($detect->{stateRole}{$asc})) {
			$sc = $asc;
			$sd = $detect->{stateRole}{$asc}{datapoint};
		}
		if ($acc ne '' && exists($detect->{controlRole}) && exists($detect->{controlRole}{$acc})) {
			$cc = $acc;
			$cd = $detect->{controlRole}{$acc}{datapoint};
		}
	}
#	HMCCU_Log ($clHash, 2, "Prio 2: s=$sc.$sd c=$cc.$cd");

	# Prio 1: Use attributes statedatapoint and controldatapoint
	# Attributes are overriding attributes statechannel and controlchannel for HMCCUDEV
	my $asd = AttrVal ($clName, 'statedatapoint', '');
	my $acd = AttrVal ($clName, 'controldatapoint', '');
	if ($asd ne '') {
		my @sa = split (/\./, $asd);
		if (scalar(@sa) > 1) {
			$sc = $sa[0] if ($clType eq 'HMCCUDEV');
			shift @sa;
		}
		$sd = $sa[0];
	}
	if ($acd ne '') {
		my @ca = split (/\./, $acd);
		if (scalar(@ca) > 1) {
			$cc = $ca[0] if ($clType eq 'HMCCUDEV');
			shift @ca;
		}
		$cd = $ca[0];
	}
#	HMCCU_Log ($clHash, 2, "Prio 1: s=$sc.$sd c=$cc.$cd");

	my $sr = $sc ne '' && defined($detect) && exists($detect->{stateRole}{$sc}) ? $detect->{stateRole}{$sc}{role} : '';
	my $cr = $cc ne '' && defined($detect) && exists($detect->{controlRole}{$cc}) ? $detect->{controlRole}{$cc}{role} : '';
	($sc, $sd) = ('', '') if (!HMCCU_SetSCDatapoints ($clHash, 'statedatapoint', "$sc.$sd", $sr));
	($cc, $cd) = ('', '') if (!HMCCU_SetSCDatapoints ($clHash, 'controldatapoint', "$cc.$cd", $cr));
#	HMCCU_Log ($clHash, 2, "SetDC: s=$sc.$sd c=$cc.$cd sr=$sr cr=$cr");

	if ($cmd) {
		my $chn = $cc ne '' ? $cc : $sc;
		my $dpt = $cd ne '' ? $cd : $sd;

		HMCCU_UpdateRoleCommands ($ioHash, $clHash);
	}

	my $rsd = $sc ne '' && $sd ne '' ? 1 : 0;
	my $rcd = $cc ne '' && $cd ne '' ? 1 : 0;

	return ($sc, $sd, $cc, $cd, $rsd, $rcd);
}

######################################################################
# Get state and control channel and datapoint of a device.
# If neither statedatapoint nor controldatapoint is defined, try
# setting default values.
######################################################################

sub HMCCU_GetSCDatapoints ($)
{
	my ($clHash) = @_;

	my $type = $clHash->{TYPE};
	return ('', '', '', '', 0, 0) if ($type ne 'HMCCUDEV' && $type ne 'HMCCUCHN');

	my ($sc, $sd) = HMCCU_StateDatapoint ($clHash);
	my ($cc, $cd) = HMCCU_ControlDatapoint ($clHash);

	my $rsdCnt = $sc ne '' && $sd ne '' ? 1 : 0;
	my $rcdCnt = $cc ne '' && $cd ne '' ? 1 : 0;

	return ($sc, $sd, $cc, $cd, $rsdCnt, $rcdCnt) if ($rsdCnt > 0 || $rcdCnt > 0);

	my $ioHash = HMCCU_GetHash ($clHash);
	return HMCCU_SetDefaultSCDatapoints ($ioHash, $clHash);
}

sub HMCCU_StateOrControlChannel ($)
{
	my ($clHash) = @_;

	my ($sc, $sd) = HMCCU_StateDatapoint ($clHash);
	my ($cc, $cd) = HMCCU_ControlDatapoint ($clHash);

	($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);

	return $cc eq '' ? $sc : $cc;
}

sub HMCCU_ControlDatapoint ($)
{
	my ($clHash) = @_;

	return ($clHash->{hmccu}{control}{chn} // '', $clHash->{hmccu}{control}{dpt} // '');
}

sub HMCCU_IsValidControlDatapoint ($;$)
{
	my ($clHash, $checkHashOnly) = @_;

	return 0 if (!defined($clHash->{ccuaddr}));

	$checkHashOnly //= 0;
	my ($cc, $cd) = HMCCU_ControlDatapoint ($clHash);
	my ($da, $chnNo) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});

	return $cc ne '' && $cd ne '' && ($checkHashOnly || HMCCU_IsValidParameter ($clHash, "$da:$cc", 'VALUES', $cd, 2)) ? 1 : 0;
}

sub HMCCU_StateDatapoint ($)
{
	my ($clHash) = @_;

	return ($clHash->{hmccu}{state}{chn} // '', $clHash->{hmccu}{state}{dpt} // '');
}

sub HMCCU_IsValidStateDatapoint ($;$)
{
	my ($clHash, $checkHashOnly) = @_;

	return 0 if (!defined($clHash->{ccuaddr}));
	
	$checkHashOnly //= 0;
	my ($sc, $sd) = HMCCU_StateDatapoint ($clHash);
	my ($da, $chnNo) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});

	return $sc ne '' && $sd ne '' && ($checkHashOnly || HMCCU_IsValidParameter ($clHash, "$da:$sc", 'VALUES', $sd, 5)) ? 1 : 0;
}

######################################################################
# Detect roles, channel and datapoint to be used for controlling and
# displaying the state of a device or channel identified by its
# address.
#
# The function returns a hash reference with the following structure:
#
#   int stateRoleCount:   Number of stateRole entries
#   int controlRoleCount: Number of controlRole entries
#   int rolePatternCount: Number of 4-channel role patterns
#   hash stateRole:   Hash with state roles, key is channel number
#   hash controlRole: Hash with control roles, key is channel number
#   hash rolePattern: Hash with 4-channel role patterns
#   string defMod: Default module 'HMCCUDEV', 'HMCCUCHN' or ''
#   string defAdd: Device address (append channel number fpr HMCCUCHN)
#   int defSCh: Default state channel or -1
#   int defCCh: Default control channel or -1
#   int defSDP: Default state datapoint with channel
#   int defCDP: Default control datapoint with channel
#   int level: Detection level
#     0 = device type not detected or error during detection
#     1 = device type detected with single known role => HMCCUCHN
#     2 = device detected with multiple identical channels (i.e. switch
#         or remote with more than 1 button) => Multiple HMCCUCHNs
#     3 = device detected with multiple channels with different known
#         roles (i.e. roles KEY and THERMALCONTROL) => HMCCUDEV
#     4 = device type detected with different state and control role
#         (>=2 different channels) => HMCCUDEV
#     5 = device type detected with one or more 4-channel-groups (1xState,3xControl)
#     6 = device type not detected, but readable and/or writeable roles found
#
# Structure of stateRole / controlRole hashes:
#   int <channel>: Channel number (key)
#   string {<channel>}{role}: Channel role
#   string {<channel>}{datapoint}: State or control datapoint
#   int {<channel>}{priority}: Priority of role/datapoint
#
# Structure of rolePattern hash (detection level = 5)
#   int <channel>: Number of first channel of a group
#   string {<channel>}{stateRole}: Role of state channel
#   string {<channel>}{controlRole}: Role of control channel
#   string {<channel>}{stateDatapoint}: The state datapoint
#   string {<channel>}{controlDatapoint}: The control datapoint
######################################################################

sub HMCCU_DetectDevice ($$$)
{
	my ($ioHash, $address, $iface) = @_;

	my @definitions = ();			# Detected device definitions
	my @allRoles = ();				# Channel roles, index = channel number
	my @stateRoles = ();
	my @controlRoles = ();
	my ($prioState, $prioControl) = (-1, -1);

	if (!defined($address)) {
		HMCCU_Log ($ioHash, 2, "Parameter address not defined ".stacktraceAsString(undef));
		return undef;
	}

	my ($devAdd, $devChn) = HMCCU_SplitChnAddr ($address);

	my $roleCnt = HMCCU_IdentifyDeviceRoles ($ioHash, $address, $iface, \@allRoles, \@stateRoles, \@controlRoles);
	if ($roleCnt == 0) {
		$roleCnt = HMCCU_UnknownDeviceRoles ($ioHash, $address, $iface, \@stateRoles, \@controlRoles);
	}
	if ($roleCnt == 0) {
		HMCCU_Log ($ioHash, 5, "No roles detected for device $address");
		return undef;
	}

	# Count roles and unique roles
	my $stateRoleCnt = scalar(@stateRoles);
	my $ctrlRoleCnt  = scalar(@controlRoles);
	my %uniqStateRoles;
	my %uniqCtrlRoles;
	$uniqStateRoles{$_->{role}}++ for @stateRoles;
	$uniqCtrlRoles{$_->{role}}++ for @controlRoles;
	my $cntUniqStateRoles = scalar(keys %uniqStateRoles);
	my $cntUniqCtrlRoles  = scalar(keys %uniqCtrlRoles);

	# Build device information to be returned
	my %di = (
		stateRoleCount => $stateRoleCnt, controlRoleCount => $ctrlRoleCnt,
		uniqueStateRoleCount => $cntUniqStateRoles, uniqueControlRoleCount => $cntUniqCtrlRoles,
		rolePatternCount => 0,
		defMod => 'HMCCUDEV', defAdd => $devAdd, defSCh => -1, defCCh => -1, defSDP => '', defCDP => '',
		level => 0
	);
	my $p = -1;
	foreach my $sr (@stateRoles) {
		$di{stateRole}{$sr->{channel}}{role}      = $sr->{role};
		$di{stateRole}{$sr->{channel}}{datapoint} = $sr->{datapoint};
		$di{stateRole}{$sr->{channel}}{priority}  = $sr->{priority};
		if (defined($sr->{priority}) && $sr->{priority} > $p) {
			$di{defSCh} = $sr->{channel};
			$p = $sr->{priority};
		}
	}
	$p = -1;
	foreach my $cr (@controlRoles) {
		$di{controlRole}{$cr->{channel}}{role}      = $cr->{role};
		$di{controlRole}{$cr->{channel}}{datapoint} = $cr->{datapoint};
		$di{controlRole}{$cr->{channel}}{priority}  = $cr->{priority};
		if (defined($cr->{priority}) && $cr->{priority} > $p) {
			$di{defCCh} = $cr->{channel};
			$p = $cr->{priority};
		}
	}

	# Determine parameters for device definition
	if ($stateRoleCnt == 1 && $ctrlRoleCnt == 0) {
		# Type 1: One channel with statedatapoint, but no controldatapoint (read only) => HMCCUCHN
		$di{defSCh} = $stateRoles[0]->{channel};
		$di{defMod} = 'HMCCUCHN';
		$di{defAdd} = "$devAdd:$di{defSCh}";
		$di{level} = 1;
	}
	elsif ($stateRoleCnt == 0 && $ctrlRoleCnt == 1) {
		# Type 1: One channel with controldatapoint, but no statedatapoint (write only) => HMCCUCHN
		$di{defCCh} = $controlRoles[0]->{channel};
		$di{defMod} = 'HMCCUCHN';
		$di{defAdd} = "$devAdd:$di{defCCh}";
		$di{level} = 1;
	}
	elsif ($stateRoleCnt == 1 && $ctrlRoleCnt == 1) {
		$di{defSCh} = $stateRoles[0]->{channel};
		$di{defCCh} = $controlRoles[0]->{channel};
		if ($stateRoles[0]->{channel} == $controlRoles[0]->{channel}) {
			# Type 1: One channel with controldatapoint and statedatapoint (read + write)=> HMCCUCHN
			$di{defMod} = 'HMCCUCHN';
			$di{defAdd} = "$devAdd:$di{defCCh}";
			$di{level} = 1;
		}
		else {
			# Type 4: Two different channels for controldatapoint and statedatapoint (read + write) => HMCCUDEV
			$di{defMod} = 'HMCCUDEV';
			$di{defAdd} = $devAdd;
			$di{level} = 4;
		}
	}
	elsif ($stateRoleCnt > 1 || $ctrlRoleCnt > 1) {
		# Multiple channels found
		if ($cntUniqStateRoles == 1 && $cntUniqCtrlRoles == 0 ||
			 $cntUniqStateRoles == 0 && $cntUniqCtrlRoles == 1 || 
#			 $cntUniqCtrlRoles > 1 ||
			(
				 $cntUniqStateRoles == 1 && $cntUniqCtrlRoles == 1 && $stateRoles[0]->{role} eq $controlRoles[0]->{role}
			 )
		) {
			# Type 2: Device with multiple identical channels 
			$di{defSCh} = $cntUniqStateRoles == 1 ? $stateRoles[0]->{channel} : -1;
			$di{defCCh} = $cntUniqCtrlRoles == 1 ? $controlRoles[0]->{channel} : -1;
			$di{defMod} = 'HMCCUCHN';
			$di{defAdd} = $devAdd;
			$di{level} = 2;
		}
		else {
			# Type 3: Device with multiple different channel roles
			$di{defMod} = 'HMCCUDEV';
			$di{defAdd} = $devAdd;
			$di{level} = 3;
			$di{rolePatternCount} = 0;
			
			# Try to find channel role pattern with 4 channels.
			# If no pattern can be found, default channels depend on role priorities
			my $rolePatterns = HMCCU_DetectRolePattern (\@allRoles,
				'^(?!([A-Z]+_VIRTUAL))([A-Z]+)[A-Z_]+(,\g2_VIRTUAL_[A-Z_]+){3}$', 4, 4);
			if (defined($rolePatterns)) {
				ROLEPATTERN: foreach my $rp (keys %$rolePatterns) {

					# A role pattern is a comma separated list of channel roles
					my @patternRoles = split(',', $rp);

					# Check if all roles of a pattern role are supported (TODO: move this check to HMCCU_DetectRolePattern)
					PATTERNROLE: foreach my $pr (@patternRoles) {
						next ROLEPATTERN if (!exists($HMCCU_STATECONTROL->{$pr}));
					}

					foreach my $firstChannel (split(',', $rolePatterns->{$rp}{i})) {
						# state/control channel is the first channel with a state/control datapoint
						my $i = 0;
						foreach my $pr (@patternRoles) {
							my $chnNo = $firstChannel+$i;
							my $chnAdd = "$devAdd:$chnNo";
							if ($HMCCU_STATECONTROL->{$pr}{S} ne '' &&
								HMCCU_IsValidParameter ($ioHash, $chnAdd, 'VALUES', $HMCCU_STATECONTROL->{$pr}{S}, 5)
							) {
								$di{rolePattern}{$firstChannel}{stateRole} = $pr;
								$di{rolePattern}{$firstChannel}{stateChannel} = $firstChannel+$i; 
								$di{rolePattern}{$firstChannel}{stateDatapoint} = $HMCCU_STATECONTROL->{$pr}{S}; 
								$di{defSCh} = $firstChannel+$i;
								last;
							}
							$i++;
						}
						$i = 0;
						foreach my $pr (@patternRoles) {
							my $chnNo = $firstChannel+$i;
							my $chnAdd = "$devAdd:$chnNo";
							if ($HMCCU_STATECONTROL->{$pr}{C} ne '' &&
								HMCCU_IsValidParameter ($ioHash, $chnAdd, 'VALUES', $HMCCU_STATECONTROL->{$pr}{C}, 2)
							) {
								$di{rolePattern}{$firstChannel}{controlRole} = $pr;
								$di{rolePattern}{$firstChannel}{controlChannel} = $firstChannel+$i;
								$di{rolePattern}{$firstChannel}{controlDatapoint} = $HMCCU_STATECONTROL->{$pr}{C}; 
								$di{defCCh} = $firstChannel+$i;
								last;
							}
							$i++;
						}
					}

					$di{rolePatternCount} += $rolePatterns->{$rp}{c};
				}

				$di{level} = 5 if (exists($di{rolePattern}) && scalar(keys %{$di{rolePattern}}) > 0);
			}
		}
	}

	if ($di{defSCh} != -1 && exists($di{stateRole}{$di{defSCh}})) {
		my $dpn = $di{stateRole}{$di{defSCh}}{datapoint} // '';
		my $dpr = $di{stateRole}{$di{defSCh}}{role} // '';
		$di{defSDP} = $di{defSCh}.'.'.$dpn if ($dpn ne '');
	}
	if ($di{defCCh} != -1 && exists($di{controlRole}{$di{defCCh}})) {
		my $dpn = $di{controlRole}{$di{defCCh}}{datapoint} // '';
		my $dpr = $di{controlRole}{$di{defCCh}}{role} // '';
		$di{defCDP} = $di{defCCh}.'.'.$dpn if ($dpn ne '');
	}
 
	return \%di;
}

######################################################################
# Identify device roles
# Return 0 on error or number of roles
######################################################################

sub HMCCU_IdentifyDeviceRoles ($$$$$$)
{
	my ($ioHash, $address, $iface, $allRoles, $stateRoles, $controlRoles) = @_;

	return 0 if (HMCCU_IsFlag ($ioHash, 'noAutoDetect'));

	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $address, $iface);
	if (!defined($devDesc)) {
		HMCCU_Log ($ioHash, 2, "Can't get device description for $address ".stacktraceAsString(undef));
		return 0;
	}

	# Identify roles
	if ($devDesc->{_addtype} eq 'dev') {
		foreach my $child (split(',', $devDesc->{CHILDREN})) {
			my $chnDesc = HMCCU_GetDeviceDesc ($ioHash, $child, $devDesc->{_interface});
			if (defined($chnDesc)) {
				push @$allRoles, $chnDesc->{TYPE};
				HMCCU_IdentifyChannelRole ($ioHash, $chnDesc, $iface, $stateRoles, $controlRoles);
			}
			else {
				push @$allRoles, 'UNKNOWN';
			}
		}
	}
	elsif ($devDesc->{_addtype} eq 'chn') {
		push @$allRoles, $devDesc->{TYPE};
		HMCCU_IdentifyChannelRole ($ioHash, $devDesc, $iface, $stateRoles, $controlRoles);
	}

	return scalar(@$stateRoles)+scalar(@$controlRoles);
}

######################################################################
# Identify a channel role
######################################################################

sub HMCCU_IdentifyChannelRole ($$$$$)
{
	my ($ioHash, $chnDesc, $iface, $stateRoles, $controlRoles) = @_;
	
	my $t = $chnDesc->{TYPE};		# Channel role

	return if (!exists($HMCCU_STATECONTROL->{$t}));

	# Role supported by HMCCU
	my ($a, $c) = HMCCU_SplitChnAddr ($chnDesc->{ADDRESS});
	my $p = $HMCCU_STATECONTROL->{$t}{P};

	# State datapoint must be of type readable and/or event
	my $sDP = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$t}{S}, $iface);
	push @$stateRoles, { 'channel' => $c, 'role' => $t, 'datapoint' => $sDP, 'priority' => $p }
		if (HMCCU_IsValidParameter ($ioHash, $chnDesc, 'VALUES', $sDP, 5));

	# Control datapoint must be writeable
	my $cDP = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$t}{C}, $iface);
	push @$controlRoles, { 'channel' => $c, 'role' => $t, 'datapoint' => $cDP, 'priority' => $p }
		if (HMCCU_IsValidParameter ($ioHash, $chnDesc, 'VALUES', $cDP, 2));
}

sub HMCCU_UnknownDeviceRoles ($$$$$)
{
	my ($ioHash, $address, $iface, $stateRoles, $controlRoles) = @_;

	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $address, $iface);
	if (!defined($devDesc)) {
		HMCCU_Log ($ioHash, 2, "Can't get device description for $address ".stacktraceAsString(undef));
		return 0;
	}

	# Identify roles
	if ($devDesc->{_addtype} eq 'dev') {
		foreach my $child (split(',', $devDesc->{CHILDREN})) {
			my $chnDesc = HMCCU_GetDeviceDesc ($ioHash, $child, $devDesc->{_interface});
			if (defined($chnDesc)) {
				HMCCU_UnknownChannelRole ($ioHash, $chnDesc, $stateRoles, $controlRoles);
			}
		}
	}
	elsif ($devDesc->{_addtype} eq 'chn') {
		HMCCU_UnknownChannelRole ($ioHash, $devDesc, $stateRoles, $controlRoles);
	}

	return scalar(@$stateRoles)+scalar(@$controlRoles);
}

sub HMCCU_UnknownChannelRole ($$$$)
{
	my ($ioHash, $chnDesc, $stateRoles, $controlRoles) = @_;
	
	my $t = $chnDesc->{TYPE};	# Channel role

	return if ($t eq 'MAINTENANCE');

	# Role not supported by HMCCU, check for usable datapoints
	my $model = HMCCU_GetDeviceModel ($ioHash, $chnDesc->{_model}, $chnDesc->{_fw_ver}, $chnDesc->{INDEX});
	if (defined($model) && exists($model->{VALUES})) {
		my $sdp = '';
		my $cdp = '';
		my @sdpList = ();
		my @cdpList = ();
		foreach my $p (keys %{$model->{VALUES}}) {
			if (exists($model->{VALUES}{$p}{OPERATIONS})) {
				if ($model->{VALUES}{$p}{OPERATIONS} & 5) {
					push @sdpList, $p;
					$sdp = $p if ($sdp eq '' || ($sdp ne 'STATE' && $sdp ne 'LEVEL'));
				}
				if ($model->{VALUES}{$p}{OPERATIONS} & 2) {
					push @cdpList, $p;
					$cdp = $p if ($cdp eq '' || ($cdp ne 'STATE' && $cdp ne 'LEVEL'));
				}
			}
		}
		push @$stateRoles, {
			'channel' => $chnDesc->{INDEX}, 'role' => $chnDesc->{TYPE}, 'datapoint' => $sdp,
			'dptList' => join(',', @sdpList), 'priority' => 0
		} if ($sdp ne '');
		push @$controlRoles, {
			'channel' => $chnDesc->{INDEX}, 'role' => $chnDesc->{TYPE}, 'datapoint' => $cdp,
			'dptList' => join(',',@cdpList), 'priority' => 0
		} if ($cdp ne '');
		# HMCCU_Log ($ioHash, 5, "Unknown role $t. sdp=$sdp, cdp=$cdp");
	}
}

######################################################################
# Detect role patterns
#
# Parameters:
#   $roles - Array reference containing a list of channel roles
#   $regMatch - Regular expression describing the pattern
#   $minPatternLen - Minimum number of roles in the pattern
#   $maxPatternLen - Maximum number of roles in the pattern
#   $minOcc - Minimum number of occurrences of the pattern
#
# Example expression for matching groups of 1 TRANSMITTER and 3
# virtual RECEIVER channels (default):
#
#   '^(?!([A-Z]+_VIRTUAL))([A-Z]+)[A-Z_]+(,\g2_VIRTUAL_[A-Z_]+){3}$'  
#
# Return hash reference with role patterns or undef on error.
# Role pattern hash (key = pattern):
#   c - Occurrences of the pattern
#   i - Comma separated list of the starting positions of the pattern
######################################################################

sub HMCCU_DetectRolePattern ($;$$$$)
{
	my ($roles, $regMatch, $minPatternLen, $maxPatternLen, $minOcc) = @_;
	$regMatch //= '^(?!([A-Z]+_VIRTUAL))([A-Z]+)[A-Z_]+(,\g2_VIRTUAL_[A-Z_]+){3}$';
	$minPatternLen //= 2;
	$minOcc //= 1;
	$minOcc = HMCCU_Max ($minOcc, 1);

	my $n = scalar(@$roles);
	my $skip = 1;

	return undef if ($n-$skip < $minPatternLen);
	$maxPatternLen //= int(($n-$skip)/$minOcc);
	return undef if ($maxPatternLen < $minPatternLen);

	my %patternList;

	for (my $patternLen=$minPatternLen; $patternLen<=$maxPatternLen; $patternLen++) {
		# Create list of patterns
		my @p = ();
		for (my $j=$skip; $j<=$n-$patternLen; $j++) {
			my $k=$j+$patternLen-1;
			my $patStr = join(',',@$roles[$j..$k]);
			push @p, { i => $j, p => $patStr } if ($patStr =~ /$regMatch/);
		}
		# Count patterns
		foreach my $first (@p) {
			next if (exists($patternList{$first->{p}}));
			my $cnt = 0;
			my @c = ();
			foreach my $t (@p) {
				if ($t->{p} eq $first->{p}) {
					push @c, $t->{i};
					$cnt++;
				}
			}
			if ($cnt >= $minOcc) {
				$patternList{$first->{p}}{c} = $cnt;
				$patternList{$first->{p}}{i} = join(',',@c);
			}
		}
	}
	
	return \%patternList;
}

######################################################################
# Select state or control datapoint from HMCCU_STATECONTROL definition
# considering interface specified in definition.
# Return datapoint or empty string.
######################################################################

sub HMCCU_DetectSCDatapoint ($$)
{
	my ($dpSpec, $iface) = @_;

	if (defined($dpSpec) && $dpSpec ne '') {
		foreach my $dp (split(',', $dpSpec)) {
			my ($i, $d) = split(':', $dp);
			return $dp if (!defined($d));
			return $d if ($i eq $iface);
		}
	}

	return '';
}

######################################################################
# Get attribute ccuflags.
# Default value is 'null'. With version 4.4 flags intrpc and extrpc
# are substituted by procrpc.
######################################################################

sub HMCCU_GetFlags ($)
{
	my ($name) = @_;
	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	$ccuflags =~ s/(extrpc|intrpc)/procrpc/g;
	return $ccuflags;
}

######################################################################
# Check if specific CCU flag is set.
# Parameter $flag is a regular expression.
######################################################################

sub HMCCU_IsFlag ($$)
{
	my ($nameOrHash, $flag) = @_;

	my $name = ref($nameOrHash) eq 'HASH' ? $nameOrHash->{NAME} : $nameOrHash;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	return $ccuflags =~ /$flag/ ? 1 : 0;
}

######################################################################
# Get reading format considering default attribute
# ccudef-readingformat defined in I/O device.
# Default reading format for virtual groups is always 'name'.
######################################################################

sub HMCCU_GetAttrReadingFormat ($$)
{
	my ($clHash, $ioHash) = @_;
	
	my $rfdef = AttrVal ($ioHash->{NAME}, 'ccudef-readingformat', 'datapoint');

	return AttrVal ($clHash->{NAME}, 'ccureadingformat', $rfdef);
}

######################################################################
# Get number format considering default attribute ccudef-stripnumber,
# Default is null
######################################################################

sub HMCCU_GetAttrStripNumber ($)
{
	my ($hash) = @_;
	my $type = $hash->{TYPE};
	
	my %strip = (
		'BLIND' => '0', 'DIMMER' => '0'
	);
		
	my $ioHash = HMCCU_GetHash ($hash);
	my $snDef = defined($ioHash) ? AttrVal ($ioHash->{NAME}, 'ccudef-stripnumber', '1') : '1';
	
	if (defined($hash->{hmccu}{role}) && $hash->{hmccu}{role} ne '') {
		foreach my $cr (split(',', $hash->{hmccu}{role})) {
			my ($c, $r) = split(':', $cr);
			if (exists($strip{$r})) {
				$snDef = $strip{$r};
				last;
			}
		}
	}
	
	return AttrVal ($hash->{NAME}, 'stripnumber', $snDef);
}

######################################################################
# Get attribute substitute considering default attribute
# ccudef-substitute defined in I/O device.
# Substitute ${xxx} by datapoint value.
######################################################################

sub HMCCU_GetAttrSubstitute ($;$)
{
	my ($clhash, $iohash) = @_;

	my $substdef = defined($iohash) ? AttrVal ($iohash->{NAME}, 'ccudef-substitute', '') : '';
	my $subst = AttrVal ($clhash->{NAME}, 'substitute', $substdef);
	$subst .= ";$substdef" if ($subst ne $substdef && $substdef ne '');
	
	return $subst !~ /\$\{.+\}/ ? $subst : HMCCU_SubstVariables ($clhash, $subst, undef);
}

######################################################################
# Execute Homematic command on CCU (blocking).
# If parameter mode is 1 an empty string is a valid result.
# Return undef on error.
######################################################################

sub HMCCU_HMCommand ($$$)
{
	my ($cl_hash, $cmd, $mode) = @_;
	my $cl_name = $cl_hash->{NAME};
	
	my $io_hash = HMCCU_GetHash ($cl_hash);
	my $ccureqtimeout = AttrVal ($io_hash->{NAME}, 'ccuReqTimeout', $HMCCU_TIMEOUT_REQUEST);
	my ($url, $auth) = HMCCU_BuildURL ($io_hash, 'rega');
	my $value;

	HMCCU_Trace ($cl_hash, 2, "URL=$url, cmd=$cmd");

	my $param = { url => $url, timeout => $ccureqtimeout, data => $cmd, method => "POST" };
	$param->{sslargs} = { SSL_verify_mode => 0 };
	my %header = ('Content-Type' => 'text/plain; charset=utf-8');
	$header{'Authorization'} = "Basic $auth" if ($auth ne '');
	$param->{header} = \%header;

	my ($err, $response) = HttpUtils_BlockingGet ($param);
	
	if ($err eq '') {
		$value = HMCCU_FormatScriptResponse ($response);
		HMCCU_Trace ($cl_hash, 2, "Response=$response, Value=".(defined($value) ? $value : "undef"));
	}
	else {
		HMCCU_Log ($io_hash, 2, "Error during HTTP request: $err");
		HMCCU_Trace ($cl_hash, 2, "Response=".(defined($response) ? $response : 'undef'));
		return undef;
	}

	if ($mode == 1) {
		return (defined($value) && $value ne 'null') ? $value : undef;
	}
	else {
		return (defined($value) && $value ne '' && $value ne 'null') ? $value : undef;		
	}
}

######################################################################
# Execute Homematic command on CCU (non blocking).
######################################################################

sub HMCCU_HMCommandNB ($$$)
{
	my ($clHash, $cmd, $cbFunc) = @_;
	my $clName = $clHash->{NAME};

	my $ioHash = HMCCU_GetHash ($clHash);
	my $ccureqtimeout = AttrVal ($ioHash->{NAME}, 'ccuReqTimeout', $HMCCU_TIMEOUT_REQUEST);
	my ($url, $auth) = HMCCU_BuildURL ($ioHash, 'rega');

	HMCCU_Trace ($ioHash, 2, "Executing command $cmd non blocking");
	HMCCU_Trace ($clHash, 2, "URL=$url");

	my $param = { url => $url, timeout => $ccureqtimeout, data => $cmd, method => "POST",
		callback => \&HMCCU_HMScriptCB, cbFunc => $cbFunc, devhash => $clHash, ioHash => $ioHash };
	$param->{sslargs} = { SSL_verify_mode => 0 };
	my %header = ('Content-Type' => 'text/plain; charset=utf-8');
	$header{'Authorization'} = "Basic $auth" if ($auth ne '');
	$param->{header} = \%header;
	
	HttpUtils_NonblockingGet ($param);
}

######################################################################
# Execute Homematic script on CCU.
# Parameters: device-hash, script-code or script-name, parameter-hash
# If content of hmscript starts with a ! the following text is treated
# as name of an internal HomeMatic script function defined in
# HMCCUConf.pm.
# If content of hmscript is enclosed in [] the content is treated as
# HomeMatic script code. Characters [] will be removed.
# Otherwise hmscript is the name of a file containing Homematic script
# code.
# Return script output or error message starting with "ERROR:".
# If script is executed non-blocking, '' is returned.
######################################################################
 
sub HMCCU_HMScriptExt ($$;$$$)
{
	my ($hash, $hmscript, $params, $cbFunc, $cbParam) = @_;
	my $name = $hash->{NAME};
	my $ioHash = HMCCU_GetHash ($hash);
	my $code = $hmscript;
	my $scrname = '';
	
	if ($hash->{TYPE} ne 'HMCCU') {
		HMCCU_Log ($hash, 2, stacktraceAsString(undef));
		return HMCCU_LogError ($hash, 2, "HMScriptExt called for device type $hash->{TYPE}");
	}
	
	return HMCCU_LogError ($hash, 2, 'CCU host name not defined') if (!exists($hash->{host}));
	my $host = $hash->{host};

	my $ccureqtimeout = AttrVal ($hash->{NAME}, 'ccuReqTimeout', $HMCCU_TIMEOUT_REQUEST);

	if ($hmscript =~ /^!(.*)$/) {
		# Internal script
		$scrname = $1;
		return "ERROR: Can't find internal script $scrname" if (!exists($HMCCU_SCRIPTS->{$scrname}));
		$code = $HMCCU_SCRIPTS->{$scrname}{code};
	}
	elsif ($hmscript =~ /^\[(.*)\]$/) {
		# Script code
		$code = $1;
	}
	else {
		# Script file
		if (open (SCRFILE, "<$hmscript")) {
			my @lines = <SCRFILE>;
			$code = join ("\n", @lines);
			close (SCRFILE);
		}
		else {
			return "ERROR: Can't open script file";
		}
	}
 
	# Check and replace variables
	if (defined($params)) {
		my @parnames = keys %{$params};
		if ($scrname ne '') {
			if (scalar (@parnames) != $HMCCU_SCRIPTS->{$scrname}{parameters}) {
				return "ERROR: Wrong number of parameters. Usage: $scrname ".
					$HMCCU_SCRIPTS->{$scrname}{syntax};
			}
			foreach my $p (split (/[, ]+/, $HMCCU_SCRIPTS->{$scrname}{syntax})) {
				return "ERROR: Missing definition of parameter $p" if (!exists ($params->{$p}));
			}
		}
		foreach my $svar (keys %{$params}) {
			next if ($code !~ /\$$svar/);
			$code =~ s/\$$svar/$params->{$svar}/g;
		}
	}
	else {
		if ($scrname ne '' && $HMCCU_SCRIPTS->{$scrname}{parameters} > 0) {
			return "ERROR: Wrong number of parameters. Usage: $scrname ".
				$HMCCU_SCRIPTS->{$scrname}{syntax};
		}
	}
	
	HMCCU_Trace ($hash, 2, "Code=$code");
	
	# Execute script on CCU
	my ($url, $auth) = HMCCU_BuildURL ($hash, 'rega');
	my %header = ('Content-Type' => 'text/plain; charset=utf-8');
	$header{'Authorization'} = "Basic $auth" if ($auth ne '');
	if (defined($cbFunc)) {
		# Non blocking
		HMCCU_Trace ($hash, 2, "Executing $hmscript non blocking");
		my $param = { url => $url, timeout => $ccureqtimeout, data => $code, method => "POST",
			callback => \&HMCCU_HMScriptCB, cbFunc => $cbFunc, devhash => $hash, ioHash => $ioHash };
		if (defined($cbParam)) {
			foreach my $p (keys %{$cbParam}) { $param->{$p} = $cbParam->{$p}; }
		}
		$param->{sslargs} = { SSL_verify_mode => 0 };
		$param->{header} = \%header;
		HttpUtils_NonblockingGet ($param);
		return '';
	}

	# Blocking request
	my $param = { url => $url, timeout => $ccureqtimeout, data => $code, method => "POST" };
	$param->{sslargs} = { SSL_verify_mode => 0 };
	$param->{header} = \%header;
	my ($err, $response) = HttpUtils_BlockingGet ($param);
	HMCCU_Trace ($hash, 2, "err=$err\nresponse=".($response // ''));

	if ($err eq '') {
		return HMCCU_FormatScriptResponse ($response);
	}
	else {
		return HMCCU_LogError ($hash, 2, "HMScript failed. $err");
	}
}

######################################################################
# Default callback function for non blocking Homematic scripts
# If a custom callback function is defined in $param->{cbFunc},
# obsolete data is removed from respone and resulting data is handed
# over to custom callback function.
######################################################################

sub HMCCU_HMScriptCB ($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{devhash};
	$data //= '';

	HMCCU_Log ($hash, 2, "Error during CCU request. $err") if ($err ne '');
	HMCCU_Trace ($hash, 2, "url=$param->{url}\nerr=$err\nresponse=$data");

	if (defined($param->{cbFunc})) {
		$param->{cbFunc}->($param, $err, $err eq '' ? HMCCU_FormatScriptResponse ($data) : $data);
	}
	else {
		HMCCU_Log ($hash, 5, 'No callback function defined');
	}
}

######################################################################
# Format result of Homematic script execution
# Response is converted from ISO-8859-1 to UTF-8
######################################################################

sub HMCCU_FormatScriptResponse ($)
{
	my ($response) = @_;

	$response =~ s/\r//mg;		# Remove CR
	$response =~ s/<xml>.*//s;	# Remove XML formatted part of the response
	$response =~ s/^\n//mg;		# Remove empty lines
	return HMCCU_ISO2UTF($response);
}

######################################################################
# Login to JSON API
######################################################################

sub HMCCU_JSONLogin ($)
{
	my ($hash) = @_;

	my ($username, $password) = HMCCU_GetCredentials ($hash, '_json_');
	return 0 if ($username eq '' || $password eq '');

	my $response = HMCCU_JSONRequest ($hash, qq(
{
	"method": "Session.login",
	"params": {
		"username": "$username",
		"password": "$password"
	}
}
	));

	return 0 if (!defined($response));

	if ($response->{error} eq '') {
		$hash->{hmccu}{jsonAPI}{sessionId} = $response->{result};
		return 1;
	}

	return 0;
}

######################################################################
# Execute JSON API request
######################################################################

sub HMCCU_JSONRequest ($$)
{
	my ($hash, $data) = @_;

	my $ccureqtimeout = AttrVal ($hash->{NAME}, 'ccuReqTimeout', $HMCCU_TIMEOUT_REQUEST);

	my ($url, $auth) = HMCCU_BuildURL ($hash, 'json');
	return undef if ($url eq '');

	# Blocking request
	my ($err, $response) = HttpUtils_BlockingGet ({
		url => $url,
		method => 'POST',
		timeout => $ccureqtimeout,
		sslargs => {
			SSL_verify_mode => 0
		},
		header => {
			'Content-Type' => 'application/json; charset=utf-8'
		},
		data => $data
	});

	if ($err eq '') {
		my $jsonResp;
		my $rc = eval { $jsonResp = decode_json ($response); 1; };
		if ($rc && defined($jsonResp)) {
			$jsonResp->{error} //= '';
			return $jsonResp;
		}
		else {
			HMCCU_LogError ($hash, 2, "Decoding JSON response failed");
		}
	}
	else {
		HMCCU_LogError ($hash, 2, "JSON API request failed. $err");
	}

	return undef;
}

######################################################################
# Bulk update of reading considering attribute substexcl.
######################################################################

sub HMCCU_BeginBulkUpdate ($)
{
	my ($hash) = @_;

	readingsBeginUpdate ($hash);
}

######################################################################
# Update reading
# Parameters:
#   $orgval - Original value
#   $subval - Original value modified by value substitution
#   $hide - Hide reading: 0=Show 1=Hide (store as .reading)
# If reading name is matching regular expression specified in
# attribute substexcl, original value is stored in reading.
######################################################################

sub HMCCU_BulkUpdate ($$$;$$)
{
	my ($hash, $reading, $orgval, $subval, $hide) = @_;
	$subval //= $orgval;
	$hide //= 0;
	my $ioHash = HMCCU_GetHash ($hash);
	
	my $excl = AttrVal ($hash->{NAME}, 'substexcl', '');
	my $rv = $excl ne '' && $reading =~ /$excl/ ? $orgval : $subval;
	$hash->{hmccu}{updateReadings}{$reading} = $rv if (HMCCU_IsAggregation ($ioHash));

	my $disp = $hide ? '.' : '';
	readingsBulkUpdate ($hash, $disp.$reading, $rv);
}

sub HMCCU_EndBulkUpdate ($)
{
	my ($hash) = @_;

	HMCCU_AggregateReadings ($hash);

	readingsEndUpdate ($hash, 1);
}

######################################################################
# Set multiple values of parameter set.
# Parameter params is a hash reference. Keys are parameter names.
# Parameter address must be a device or a channel address.
# If no paramSet is specified, VALUES is used by default.
# Optional paramater flags:
#   1 = Do not scale values before setting
######################################################################

sub HMCCU_SetMultipleParameters ($$$;$)
{
	my ($clHash, $address, $params, $paramSet) = @_;
	$paramSet //= 'VALUES';
	$address =~ s/:d$//;
	my $clName = $clHash->{NAME};

	my ($add, $chn) = HMCCU_SplitChnAddr ($address, 'd');
	return (-1, undef) if ($paramSet eq 'VALUES' && $chn eq 'd');
	
	foreach my $p (sort keys %$params) {
		return (-8, undef) if (
			($paramSet eq 'VALUES' && !HMCCU_IsValidParameter ($clHash, $address, 'VALUES', $p, 2)) ||
			($paramSet eq 'MASTER' && !HMCCU_IsValidParameter ($clHash, $address, 'MASTER', $p))
		);
		if ($params->{$p} !~ /:(STRING|BOOL|INTEGER|FLOAT|DOUBLE)$/) {
			$params->{$p} = HMCCU_ScaleValue ($clHash, $chn, $p, $params->{$p}, 1, $paramSet);
		}
		HMCCU_Trace ($clHash, 2, "set parameter=$address.$paramSet.$p chn=$chn value=$params->{$p}");
	}

	return 0 if (HMCCU_IsFlag ($clName, 'simulate'));

	return HMCCU_RPCParamsetRequest ($clHash, 'putParamset', $address, $paramSet, $params);
}

######################################################################
# Set multiple datapoints on CCU in a single request.
# Parameter params is a hash reference. Keys are full qualified CCU
# datapoint specifications in format:
#   no.interface.{address|fhemdev}:channelno.datapoint
# Parameter no defines the command order.
# Optional parameter pval:
#   1 = Do not scale values before setting
# Return value < 0 on error.
######################################################################

sub HMCCU_SetMultipleDatapoints ($$)
{
	my ($clHash, $params) = @_;
	my $mdFlag = $clHash->{TYPE} eq 'HMCCU' ? 1 : 0;
	my $ioHash;

	if ($mdFlag) {
		$ioHash = $clHash;
	}
	else {
		$ioHash = HMCCU_GetHash ($clHash) // return -3;
	}
	
	my $ioName = $ioHash->{NAME};
	my $clName = $clHash->{NAME};
	my $ccuFlags = HMCCU_GetFlags ($ioName);
	
	# Build Homematic script
	my $cmd = '';
	foreach my $p (sort keys %$params) {
		my $v = $params->{$p};

		# Check address. dev is either a device address or a FHEM device name
		my ($no, $int, $addchn, $dpt) = split (/\./, $p);
		return -1 if (!defined($dpt));
		my ($dev, $chn) = split (':', $addchn);
		return -1 if (!defined($chn));
		my $add = $dev;
		
		# Get hash of FHEM device
		if ($mdFlag) {
			$clHash = $defs{$dev} // return -1;
			($add, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
		}

		# Device has been deleted or is disabled
		return -4 if (exists($clHash->{ccudevstate}) && $clHash->{ccudevstate} eq 'deleted');
		return -21 if (IsDisabled ($clHash->{NAME}));
	
		# Check client device type and datapoint
		my $clType = $clHash->{TYPE};
		my $ccuType = $clHash->{ccutype};
		return -1 if ($clType ne 'HMCCUCHN' && $clType ne 'HMCCUDEV');
		if (!HMCCU_IsValidParameter ($clHash, HMCCU_GetChannelAddr ($clHash, $chn), 'VALUES', $dpt, 2)) {
			HMCCU_Trace ($clHash, 2, "Invalid datapoint $chn $dpt");
			return -8;
		}
		
		my $ccuVerify = AttrVal ($clName, 'ccuverify', 0);
		my $ccuChange = AttrVal ($clName, 'ccuSetOnChange', 'null');

		if ($ccuType =~ /^HM-Dis-EP-WM55/ && $dpt eq 'SUBMIT') {
			$v = HMCCU_EncodeEPDisplay ($v);
		}
		else {
			if ($v =~ /^[\$\%]{1,2}([0-9]{1,2}\.[A-Z0-9_]+)$/ && exists($clHash->{hmccu}{dp}{"$1"})) {
				$v = HMCCU_SubstVariables ($clHash, $v, undef);
			}
			else {
				$v = HMCCU_ScaleValue ($clHash, $chn, $dpt, $v, 1);
			}
		}

		my $paramDef = HMCCU_GetParamDef ($ioHash, "$add:$chn", 'VALUES', $dpt);
		if (defined($paramDef)) {
			if ($paramDef->{TYPE} eq 'STRING') {
				$v = "'".$v."'";
			}
			elsif ($paramDef->{TYPE} eq 'ENUM' && !HMCCU_IsIntNum($v)) {
				$v = HMCCU_GetEnumValues ($ioHash, $paramDef, $dpt, undef, $v);
			}
		}

		HMCCU_Trace ($clHash, 2, "set dpt=$p, value=$v");

		my $c = '(datapoints.Get("'.$int.'.'.$add.':'.$chn.'.'.$dpt.'")).State('.$v.");\n";

		if ($dpt =~ /$ccuChange/) {
			$cmd .= 'if((datapoints.Get("'.$int.'.'.$add.':'.$chn.'.'.$dpt.'")).Value() != '.$v.") {\n$c}\n";
		}
		else {
			$cmd .= $c;
		}
	}
	
	HMCCU_Trace ($clHash, 2, "cmd=$cmd");
	return 0 if (HMCCU_IsFlag ($clName, 'simulate'));

	if ($ccuFlags =~ /nonBlocking/) {
		# Execute command (non blocking)
		HMCCU_HMCommandNB ($clHash, $cmd, undef);
		return 0;
	}
	
	# Execute command (blocking)
	my $response = HMCCU_HMCommand ($clHash, $cmd, 1);
	return defined($response) ? 0 : -2;
	# Datapoint verification ???
}

######################################################################
# Scale, spread and/or shift datapoint value.
# Mode:
#   0 = Get/Multiply/Scale up
#   1 = Set/Divide/Scale down
#   2 = Scale min/max value
# Supports reversing of value if value range is specified. Syntax for
# Rule is:
#   [ChannelNo.]Datapoint:Factor
#   [!][ChannelNo.]Datapoint:Min:Max:Range1:Range2
# If Datapoint name starts with a ! the value is reversed. In case of
# an error original value is returned.
######################################################################

sub HMCCU_ScaleValue ($$$$$;$)
{
	my ($hash, $chnno, $dpt, $value, $mode, $paramSet) = @_;
	$chnno //= '';
	$paramSet //= 'VALUES';
	my $name = $hash->{NAME};
	my $ioHash = HMCCU_GetHash ($hash);
	my $ov = $value;

	return $value if (!defined($value) || !HMCCU_IsFltNum($value));

	# Get parameter definition and min/max values
	my $min;
	my $max;
	my $unit;
	my $ccuaddr = $hash->{ccuaddr};
	if ($hash->{TYPE} eq 'HMCCUDEV' && $chnno ne '' && $chnno ne 'd') {
		$ccuaddr .= ':'.$chnno;
	}
	elsif ($hash->{TYPE} eq 'HMCCUCHN' && ($chnno eq 'd' || $chnno eq '0')) {
		($ccuaddr, undef) = HMCCU_SplitChnAddr ($ccuaddr);
		$ccuaddr .= ':0' if ($chnno eq '0');
	}

	my $paramDef = HMCCU_GetParamDef ($ioHash, $ccuaddr, $paramSet, $dpt);
	if (defined($paramDef)) {
		# Do not modify enum or bool values
		return $value if (defined($paramDef->{TYPE}) && ($paramDef->{TYPE} eq 'ENUM' || $paramDef->{TYPE} eq 'BOOL'));
		$min = $paramDef->{MIN} if (defined($paramDef->{MIN}) && $paramDef->{MIN} ne '' && HMCCU_IsFltNum($paramDef->{MIN}));
		$max = $paramDef->{MAX} if (defined($paramDef->{MAX}) && $paramDef->{MAX} ne '' && HMCCU_IsFltNum($paramDef->{MAX}));
		$unit = $paramDef->{UNIT};
		if (!defined($unit)) {
			if ($dpt eq 'LEVEL' || $dpt eq 'LEVEL_2' || $dpt eq 'LEVEL_SLATS') {
				$unit = '100%';
			}
			elsif ($dpt =~ /^P[0-9]_ENDTIME_/ && defined($max) && $max == 1440) {
				$unit = 'minutes';
			}
		}
	}
	else {
		HMCCU_Trace ($hash, 2, "Can't get parameter definion for addr=$ccuaddr chn=$chnno dpt=$dpt");
	}

	# Default values can be overriden by attribute
	my $ccuscaleval = AttrVal ($name, 'ccuscaleval', '');	

	HMCCU_Trace ($hash, 2, "Scaling chnno=$chnno, dpt=$dpt, value=$value, mode=$mode");
	
	# Scale by attribute ccuscaleval
	if ($ccuscaleval ne '' && $mode != 2) {
		HMCCU_Trace ($hash, 2, "ccuscaleval = $ccuscaleval");
		my @sl = split (',', $ccuscaleval);
		foreach my $sr (@sl) {
			my $f = 1.0;
			my @a = split (':', $sr);
			my $n = scalar (@a);
			next if ($n != 2 && $n != 5);

			my $rev = 0;
			my $dn = $a[0];
			my $cn = $chnno;
			if ($dn =~ /^\!(.+)$/) {
				# Invert
				$dn = $1;
				$rev = 1;
			}
			if ($dn =~ /^([0-9]{1,2})\.(.+)$/) {
				# Compare channel number
				$cn = $1;
				$dn = $2;
			}
			next if ($dpt ne $dn || ($chnno ne '' && $cn ne $chnno));
			
			if ($n == 2) {
				$f = ($a[1] == 0.0) ? 1.0 : $a[1];
				$value = ($mode == 0) ? $value/$f : $value*$f;
			}
			elsif ($a[1] <= $a[2] && $a[3] <= $a[4] && (
				($mode == 0 && $value >= $a[1] && $value <= $a[2]) ||
				($mode == 1 && $value >= $a[3] && $value <= $a[4])
			)) {	
				# Reverse value 
				if ($rev) {
					my $dr = ($mode == 0) ? $a[1]+$a[2] : $a[3]+$a[4];
					$value = $dr-$value;
				}
				
				my $d1 = $a[2]-$a[1];
				my $d2 = $a[4]-$a[3];
				if ($d1 != 0.0 && $d2 != 0.0) {
					$f = $d1/$d2;
					$value = ($mode == 0) ? $value/$f+$a[3] : ($value-$a[3])*$f;
				}
			}
		}

		# Align value with min/max boundaries for set mode
		if ($mode == 1 && defined($min) && defined($max)) {
			$value = HMCCU_MinMax ($value, $min, $max);
		}
		
		HMCCU_Trace ($hash, 2, "Scaled value of $dpt from $ov to $value by attribute");

		return $mode == 0 && int($value) == $value ? int($value) : $value;
	}

	# Auto scale
	if ($dpt =~ /^RSSI_/ && $mode == 0) {
		# Subtract 256 from Rega value (Rega bug)
		$value = abs($value) == 65535 || $value == 0 ? 'N/A' : ($value > 0 ? $value-256 : $value);
	}
	elsif (defined($unit) && ($unit eq 'minutes' || $unit eq 's')) {
		$value = HMCCU_ConvertTime ($value, $unit, $mode);
	}
	elsif (defined($unit) && $unit =~ /^([0-9]+)%$/) {
		my $f = $1;
		$min //= 0;
		$max //= 1.0;
		HMCCU_Trace ($hash, 2, "unit=$unit, min=$min, max=$max f=$f");
		if (($mode == 0 || $mode == 2) && $value <= 1.0) {
			$value = HMCCU_MinMax ($value, $min, $max)*$f;
		}
		elsif ($mode == 1 && "$value" ne '1.0' && ($value == 1 || $value >= 2)) {
			# Do not change special values like -0.5, 1.005 or 1.01
			$value = HMCCU_MinMax($value, $min*$f, $max*$f)/$f;
		}
	}
	
	HMCCU_Trace ($hash, 2, "Auto scaled value of $dpt from $ov to $value");
	
	return $value;
}

######################################################################
# Get CCU system variables and update readings.
# System variable readings are stored in I/O device. Unsupported
# characters in variable names are substituted.
######################################################################

sub HMCCU_GetVariables ($$)
{
	my ($hash, $pattern) = @_;

	my $response = HMCCU_HMScriptExt ($hash, '!GetVariables');
	return (-2, $response) if ($response eq '' || $response =~ /^ERROR:.*/);
  
	my %readings;
	my $count = 0;
	my $result = '';

	foreach my $vardef (split /[\n\r]+/, $response) {
		# Array values: 0=varName, 1=varType, 2=varValue
		my @vardata = split /=/, $vardef;
		next if (@vardata != 3 || $vardata[0] !~ /$pattern/);
		my $rn = HMCCU_CorrectName ($vardata[0]);
		my $rv = HMCCU_ISO2UTF ($vardata[2]);
		$readings{$rn} = HMCCU_FormatReadingValue ($hash, $rv, $vardata[0]);
		$result .= $vardata[0].'='.$vardata[2]."\n";
		$count++;
	}
	
	HMCCU_UpdateReadings ($hash, \%readings);

	return ($count, $result);
}

######################################################################
# Timer function for periodic update of CCU system variables.
######################################################################

sub HMCCU_UpdateVariables ($)
{
	my ($hash) = @_;
	
	if (exists($hash->{hmccu}{ccuvarspat})) {
		HMCCU_GetVariables ($hash, $hash->{hmccu}{ccuvarspat});
		InternalTimer (gettimeofday ()+$hash->{hmccu}{ccuvarsint}, 'HMCCU_UpdateVariables', $hash);
	}
}

######################################################################
# Set CCU system variable. If parameter vartype is undefined system
# variable must exist in CCU. Following variable types are supported:
# bool, list, number, text. Parameter params is a hash reference of
# script parameters.
# Return 0 on success, error code on error.
######################################################################

sub HMCCU_SetVariable ($$$$$)
{
	my ($hash, $varname, $value, $vartype, $params) = @_;
	my $name = $hash->{NAME};
	
	my $ccureqtimeout = AttrVal ($name, 'ccuReqTimeout', $HMCCU_TIMEOUT_REQUEST);
	
	my %varfnc = (
		'bool'   => '!CreateBoolVariable',    'list' => '!CreateListVariable',
		'number' => '!CreateNumericVariable', 'text' => '!CreateStringVariable'
	);

	if (!defined($vartype)) {
		my $cmd = qq(dom.GetObject("$varname").State("$value"));
		my $response = HMCCU_HMCommand ($hash, $cmd, 1) //
			return HMCCU_Log ($hash, 1, "CMD=$cmd", -2);
	}
	else {
		return -18 if (!exists($varfnc{$vartype}));

		# Set default values for variable attributes
		$params->{name}     = $varname if (!exists ($params->{name}));
		$params->{init}     = $value if (!exists ($params->{init}));
		$params->{unit}     = '' if (!exists ($params->{unit}));
		$params->{desc}     = '' if (!exists ($params->{desc}));
		$params->{min}      = '0' if ($vartype eq 'number' && !exists ($params->{min}));
		$params->{max}      = '65000' if ($vartype eq 'number' && !exists ($params->{max}));
		$params->{list}     = $value if ($vartype eq 'list' && !exists ($params->{list}));
		$params->{valtrue}  = 'ist wahr' if ($vartype eq 'bool' && !exists ($params->{valtrue}));
		$params->{valfalse} = 'ist falsch' if ($vartype eq 'bool' && !exists ($params->{valfalse}));
		
		my $rc = HMCCU_HMScriptExt ($hash, $varfnc{$vartype}, $params);
		return HMCCU_Log ($hash, 1, $rc, -2) if ($rc =~ /^ERROR:.*/);
	}

	return 0;
}

######################################################################
# Generic reading update callback function for non blocking HTTP
# requests.
# Format of $data: Newline separated list of datapoint values.
#    ChannelName=Interface.ChannelAddress.Datapoint=Value
# Optionally last line can contain the number of datapoint lines.
######################################################################

sub HMCCU_UpdateCB ($$$)
{
	my ($param, $err, $data) = @_;
	
	if (!exists($param->{ioHash})) {
		Log3 1, undef, 'HMCCU: Missing parameter ioHash in update callback';
		return;
	}

	my $hash = $param->{ioHash};
	my $filter = $param->{filter} // '.*';
	my $logcount = exists($param->{logCount}) && $param->{logCount} == 1 ? 1 : 0;
	my %devUpdStatus = ();
	foreach my $devName (split(',',$param->{ccuDevNameList} // '')) {
		my $devAdd = $hash->{hmccu}{adr}{$devName}{address};
		$devUpdStatus{$devAdd}{name} = $devName;
		$devUpdStatus{$devAdd}{upd} = 0;
	}

	my $count = 0;
	my @dpdef = split /[\n\r]+/, $data;
	my $lines = scalar (@dpdef);
	$count = ($lines > 0 && $dpdef[$lines-1] =~ /^[0-9]+$/) ? pop (@dpdef) : $lines;
	return if ($count == 0);

	my %events = ();
	foreach my $dp (@dpdef) {
		my ($chnname, $dpspec, $value) = split /=/, $dp;
		next if (!defined($value));
		my ($iface, $chnadd, $dpt) = split /\./, $dpspec;
		next if (!defined($dpt) || $dpt !~ /$filter/);
		my ($add, $chn) = ('', '');
		if ($iface eq 'sysvar' && $chnadd eq 'link') {
			($add, $chn) = HMCCU_GetAddress ($hash, $chnname);
		}
		else {
			($add, $chn) = HMCCU_SplitChnAddr ($chnadd);
		}
		next if ($chn eq '');
		$events{$add}{$chn}{VALUES}{$dpt} = $value;

		$devUpdStatus{$add}{upd} = 1;
	}

	my $d_ok = join(',', map { $devUpdStatus{$_}{upd} ? $devUpdStatus{$_}{name} : () } keys %devUpdStatus);
	my $d_err = join(',', map { !($devUpdStatus{$_}{upd}) ? $devUpdStatus{$_}{name} : () } keys %devUpdStatus);
	my $c_ok = HMCCU_UpdateMultipleDevices ($hash, \%events, $param->{fhemDevNameList});
	my $c_err = exists($param->{devCount}) ? HMCCU_Max($param->{devCount}-$c_ok, 0) : 0;
	if ($logcount) {
		HMCCU_Log ($hash, 2, "Update success=$c_ok failed=$c_err");
		HMCCU_Log ($hash, 2, "Updated devices: $d_ok");
		HMCCU_Log ($hash, 2, "Update failed for: $d_err");
	}
}

######################################################################
# Execute RPC request
# Parameters:
#  $method - RPC request method. Use listParamset or listRawParamset
#     as an alias for getParamset if readings should not be updated.
#  $address  - Device or channel address.
#  $paramset - paramset name (VALUE, MASTER) or LINK receiver address.
#  $parref   - Hash reference with parameter/value pairs (optional).
# Return (retCode, result).
#  retCode = 0 - Success
#  retCode < 0 - Error, result contains error message
######################################################################

sub HMCCU_RPCParamsetRequest ($$$;$$)
{
	my ($clHash, $method, $address, $paramset, $parref) = @_;
	$paramset //= 'VALUES';
	my $name = $clHash->{NAME};
	my $type = $clHash->{TYPE};
	my $addr = '';
	
	my $ioHash = HMCCU_GetHash ($clHash) // return (-3, '');
	return (-4, '') if ($type ne 'HMCCU' && $clHash->{ccudevstate} eq 'deleted');
	return (-22, '') if ($method ne 'putParamset' && $method ne 'getParamset');

	# Get flags and attributes
	my $ioFlags = HMCCU_GetFlags ($ioHash->{NAME});
	my $clFlags = HMCCU_GetFlags ($name);
	my $ccureadings = AttrVal ($name, 'ccureadings', $clFlags =~ /noReadings/ ? 0 : 1);
	my $readingformat = HMCCU_GetAttrReadingFormat ($clHash, $ioHash);
	my $substitute = HMCCU_GetAttrSubstitute ($clHash, $ioHash);
	
	# Parse address, complete address information
	my ($add, $chn, $int) = HMCCU_GetAddress ($clHash, $address);
	return (-1, '') if ($add eq '' || $int eq '');
	$addr = $chn ne '' ? "$add:$chn" : $add;

	# Search RPC device, do not create one
	my ($rpcDevice, $save) = HMCCU_GetRPCDevice ($ioHash, 0, $int);
	return (-17, '') if ($rpcDevice eq '');
	my $rpcHash = $defs{$rpcDevice};
	
	# Build parameter array: (Address, Paramset [, Parameter ...])
	# Paramset := VALUE | MASTER | LINK receiver address
	# Parameter := Name=Value[:Type]
	my @parArray = ($addr, $paramset);
	if (defined($parref)) {
		if (ref($parref) eq 'HASH') {
			my %struct = ();
			foreach my $k (keys %{$parref}) {
				my ($pv, $pt) = split (':', $parref->{$k});
				if (!defined($pt)) {
					my $paramDef = HMCCU_GetParamDef ($ioHash, $addr, $paramset, $k);
					$pt = defined($paramDef) && defined($paramDef->{TYPE}) && $paramDef->{TYPE} ne '' ?
						$paramDef->{TYPE} : 'STRING';
				}
				$struct{$k} = "$pv:$pt";
			}
			push @parArray,\%struct;
		}
		else {
			return (-23, 'Hash reference required');
		}
	}
	
	# Submit RPC request
	my ($resp, $err) = HMCCURPCPROC_SendRequest ($rpcHash, $method, @parArray);
		return (-2, "RPC request $method failed: $err") if (!defined($resp));
	
	HMCCU_Trace ($clHash, 2, 
		"Dump of RPC request $method $paramset $addr. Result type=".ref($resp)."<br>".
		HMCCU_RefToString ($resp));	
	
	return (0, $resp);
}

######################################################################
#                     *** HELPER FUNCTIONS ***
######################################################################

sub HMCCU_SetIfDef { $_[0] = $_[1] if (defined($_[1])) }
sub HMCCU_SetIfEx { $_[0] = $_[1] if (exists($_[1])) }
sub HMCCU_SetVal { $_[0] = defined $_[1] && $_[1] ne '' ? $_[1] : $_[2] }

######################################################################
# Return Prefix.Value if value is defined. Otherwise default.
######################################################################

sub HMCCU_DefStr ($;$$)
{
	my ($v, $p, $d) = @_;
	$p //= '';
	$d //= '';
	
	return defined($v) && $v ne '' ? $p.$v : $d;
}

######################################################################
# Get unique array elements
######################################################################

sub HMCCU_Unique
{
	my %e;
	return grep { !$e{$_}++ } @_;
}

sub HMCCU_IsArrayElement
{
	my $e = shift;
	return grep { $_ eq $e } @_;
}

######################################################################
# Convert string from ISO-8859-1 to UTF-8
######################################################################

sub HMCCU_ISO2UTF ($)
{
	my ($t) = @_;
	$t //= '';
	
	return encode("UTF-8", decode("iso-8859-1", $t));
}

######################################################################
# Check for floating point number
######################################################################

sub HMCCU_IsFltNum ($;$)
{
	my ($value, $flag) = @_;
	$flag //= 0;	

	return $flag ?
		(defined($value) && $value =~ /^[+-]?\d*\.?\d+?$/ ? 1 : 0) :
		(defined($value) && $value =~ /^[+-]?\d*\.?\d+(?:(?:e|E)\d+)?$/ ? 1 : 0);
}

######################################################################
# Check for integer number
######################################################################

sub HMCCU_IsIntNum ($)
{
	my ($value) = @_;
	
	return defined($value) && $value =~ /^[+-]?[0-9]+$/ ? 1 : 0;
}

sub HMCCU_EQ ($$)
{
	my ($v1, $v2) = @_;

	if (HMCCU_IsFltNum($v1) && HMCCU_IsFltNum($v2)) {
		return $v1 == $v2;
	}
	else {
		return $v1 eq $v2;
	}
}

######################################################################
# Get device state from maintenance channel 0
# Return 'ok' or list of state flags.
######################################################################

sub HMCCU_GetDeviceStates ($)
{
	my ($clHash) = @_;
	
	# Datapoints related to reading 'devstate'
	my %stName = (
		'0.CONFIG_PENDING'       => { value => '^(1|true)$', flag => 'cfgPending' },
		'0.DEVICE_IN_BOOTLOADER' => { value => '^(1|true)$', flag => 'boot' },
		'0.UNREACH'              => { value => '^(1|true)$', flag => 'unreach' },
		'0.STICKY_UNREACH'       => { value => '^(1|true)$', flag => 'stickyUnreach' },
		'0.UPDATE_PENDING'       => { value => '^(1|true)$', flag => 'updPending' },
		'0.SABOTAGE'             => { value => '^(1|true)$', flag => 'sabotage' },
		'0.ERROR_SABOTAGE'       => { value => '^(1|true)$', flag => 'sabotage' }
	);
	
	if (exists($clHash->{hmccu}{dp})) {
		# Calculate the device state Reading
		my $devState = AttrVal ($clHash->{NAME}, 'devStateFlags', '');
		foreach my $ds (split(' ',$devState)) {
			my ($dsd, $dsv, $dsf) = split(':',$ds);
			next if (!defined($dsv) || $dsv eq '' || !defined($dsf) || $dsf eq '');
			$stName{$dsd}{value} = $dsv;
			$stName{$dsd}{flag}  = $dsf;
		}
		my @states = ();
		foreach my $dp (keys %stName) {
			my $v = $stName{$dp}{value};
			push @states, $stName{$dp}{flag} if (
				exists($clHash->{hmccu}{dp}{$dp}) &&
				exists($clHash->{hmccu}{dp}{$dp}{VALUES}) &&
				defined($clHash->{hmccu}{dp}{$dp}{VALUES}{VAL}) &&
				$clHash->{hmccu}{dp}{$dp}{VALUES}{VAL} =~ /$v/
			);
		}

		return scalar(@states) > 0 ? join(',', @states) : 'ok';
	}

	return '';
}

######################################################################
# Determine HomeMatic state considering datapoint values specified
# in attributes ccudef-hmstatevals and hmstatevals.
# Return (reading, channel, datapoint, value)
######################################################################

sub HMCCU_GetHMState ($$;$)
{
	my ($name, $ioname, $defval) = @_;
	my @hmstate = ('hmstate', undef, undef, $defval);

	my $clhash = $defs{$name};
	my $cltype = $clhash->{TYPE};
	return @hmstate if ($cltype ne 'HMCCUDEV' && $cltype ne 'HMCCUCHN');
	
	my $ghmstatevals = AttrVal ($ioname, 'ccudef-hmstatevals', $HMCCU_DEF_HMSTATE);
	my $hmstatevals = AttrVal ($name, 'hmstatevals', $ghmstatevals);
	$hmstatevals .= ";".$ghmstatevals if ($hmstatevals ne $ghmstatevals);
	
	# Get reading name
	if ($hmstatevals =~ /^=([^;]*);/) {
		$hmstate[0] = $1;
		$hmstatevals =~ s/^=[^;]*;//;
	}
	
	# Default hmstate is equal to state
	$hmstate[3] = ReadingsVal ($name, 'state', undef) if (!defined ($defval));

	# Substitute variables	
	$hmstatevals = HMCCU_SubstVariables ($clhash, $hmstatevals, undef);

	foreach my $rule (split (';', $hmstatevals)) {
		my ($dptexpr, $subst) = split ('!', $rule, 2);
		my $dp = '';
		next if (!defined ($dptexpr) || !defined ($subst));
		foreach my $d (keys %{$clhash->{hmccu}{dp}}) {
			if ($d =~ /$dptexpr/) {
				$dp = $d;
				last;
			}
		}
		next if ($dp eq '');
		my ($chn, $dpt) = split (/\./, $dp);
		if (exists($clhash->{hmccu}{dp}{$dp}) && exists($clhash->{hmccu}{dp}{$dp}{VALUES}{VAL})) {
			my $value = HMCCU_FormatReadingValue ($clhash, $clhash->{hmccu}{dp}{$dp}{VALUES}{VAL}, $hmstate[0]);
			my ($rc, $newvalue) = HMCCU_SubstRule ($value, $subst, 0);
			return ($hmstate[0], $chn, $dpt, $newvalue) if ($rc);
		}
	}

	return @hmstate;
}

######################################################################
# Calculate time difference in seconds between current time and
# specified timestamp
######################################################################

sub HMCCU_GetTimeSpec ($)
{
	my ($ts) = @_;
	
	return $ts if (HMCCU_IsFltNum ($ts, 1));
	return -1 if ($ts !~ /^[0-9]{2}:[0-9]{2}$/ && $ts !~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}$/);
	
	my (undef, $h, $m, $s) = GetTimeSpec ($ts);
	return -1 if (!defined($h));
	
	$s += $h*3600+$m*60;
	my @lt = localtime;
	my $cs = $lt[2]*3600+$lt[1]*60+$lt[0];
	$s += 86400 if ($cs > $s);
	
	return ($s-$cs);
}

######################################################################
# Convert time values
#   $value - Time value, format:
#      $mode = 0: n
#      $mode = 1, unit = s: [[hh:]mm:]ss
#      $mode = 1, unit = minutes: [hh:]mm
#   $unit - s or minutes
#   $mode - 0 = Get, 1 = Set 
# A value of 0 is not converted into time format (if $mode = 0).
######################################################################

sub HMCCU_ConvertTime ($$$)
{
	my ($value, $unit, $mode) = @_;

	return $value if (
		($unit ne 'minutes' && $unit ne 's') ||
		($mode == 0 && !HMCCU_IsIntNum($value))
	);

	if ($mode == 0) {
		my $f = $unit eq 'minutes' ? 60 : 3600;
		my @t = ();
		while ($f >= 60) {
			push @t, sprintf('%02d',int($value/$f));
			$value = $value%$f;
			$f = $f/60;
		}
		push @t, sprintf('%02d',$value);
		return join(':',@t);
	}
	else {
		my @t = split(':',$value);
		my $f = scalar(@t) == 1 ? 1 : ($unit eq 'minutes' ? 60 : (scalar(@t) == 3 ? 3600 : 60));
		my $r = 0;
		foreach my $v (@t) {
			$r = $r+$v*$f;
			$f = $f/60;
		}
		return $r;
	}
}

######################################################################
# Get minimum or maximum of 2 values
# Align value with boundaries
######################################################################

sub HMCCU_Min ($$)
{
	my ($a, $b) = @_;
	
	if (!defined($a) || !defined($b)) {
		HMCCU_Log (undef, 5, "Argument not defined in HMCCU_Min ".stacktraceAsString(undef));
		return 0;
	}
	if (!HMCCU_IsFltNum($a) || !HMCCU_IsFltNum($b)) {
		HMCCU_Log (undef, 5, "Argument $a or $b isn't numeric in HMCCU_Min ".stacktraceAsString(undef));
		return 0;
	}
	
	return $a < $b ? $a : $b;
}

sub HMCCU_Max ($$)
{
	my ($a, $b) = @_;
	
	if (!defined($a) || !defined($b)) {
		HMCCU_Log (undef, 5, "Argument not defined in HMCCU_Min ".stacktraceAsString(undef));
		return 0;
	}
	if (!HMCCU_IsFltNum($a) || !HMCCU_IsFltNum($b)) {
		HMCCU_Log (undef, 5, "Argument $a or $b isn't numeric in HMCCU_Max ".stacktraceAsString(undef));
		return 0;
	}

	return $a > $b ? $a : $b;
}

sub HMCCU_MinMax ($$$)
{
	my ($v, $min, $max) = @_;
	$min = $v if (!defined($min) || $min eq '' || !HMCCU_IsFltNum($min));
	$max = $min if (!defined($max) || $max eq '' || !HMCCU_IsFltNum($max));

	return HMCCU_Max (HMCCU_Min ($v, $max), $min);
}

######################################################################
# Build ReGa or RPC client URL
# Parameter backend specifies type of URL, 'rega' or name or port of
# RPC interface.
# Return array in format (url, authorization)
# Return empty strings on error.
######################################################################

sub HMCCU_BuildURL ($$)
{
	my ($hash, $backend) = @_;
	my $name = $hash->{NAME};

	my $url = '';

	my ($username, $password) = HMCCU_GetCredentials ($hash);
	my $authorization = $username ne '' && $password ne '' ? encode_base64 ("$username:$password", '') : '';

	if ($backend eq 'rega') {
		$url = $hash->{prot}."://".$hash->{host}.':'.$HMCCU_REGA_PORT{$hash->{prot}}.'/tclrega.exe';
	}
	elsif ($backend eq 'json') {
		$url = $hash->{prot}."://".$hash->{host}.'/api/homematic.cgi';
	}
	else {
		($url) = HMCCU_GetRPCServerInfo ($hash, $backend, 'url');
		if (defined($url)) {
			if (exists($HMCCU_RPC_SSL{$backend})) {
				my $p = $hash->{prot} eq 'https' ? '4' : '';
 				$url =~ s/^http:\/\//$hash->{prot}:\/\//;
				$url =~ s/:([0-9]+)/:$p$1/;
			}
		}
		else {
			$url = '';
		}
	}
	
	HMCCU_Trace ($hash, 2, "Build URL = " . $url);
	HMCCU_Trace ($hash, 2, "Authorization = " . $authorization);

	return ($url, $authorization);
}

######################################################################
# Calculate special readings. Requires hash of client device, channel
# number and datapoint. Supported functions:
#  dewpoint, absolute humidity, increasing/decreasing counters,
#  minimum/maximum, average, sum, set.
# Return readings array with reading/value pairs.
######################################################################

sub HMCCU_CalculateReading ($$)
{
	my ($cl_hash, $chkeys) = @_;
	my $name = $cl_hash->{NAME};
	
	my %parCount = ('dewpoint' => 2, 'abshumidity' => 2, 'equ' => 1,
		'max' => 1, 'min' => 1, 'inc' => 1, 'dec' => 1, 'avg' => 1,
		'sum' => 1, 'or' => 1, 'and' => 1, 'set' => 1);
	my @result = ();
	
	my $ccucalculate = AttrVal ($name, 'ccucalculate', '');
	return @result if ($ccucalculate eq '');
	
	foreach my $calculation (split (/[;\n]+/, $ccucalculate)) {
		my ($vt, $rn, $dpts) = split (':', $calculation, 3);
		if (!defined($dpts) || !exists($parCount{$vt})) {
			HMCCU_Log ($cl_hash, 2, "Error in reading calculation expression $calculation. Ignored.");
			next;
		}
		my $tmpdpts = ",$dpts,";
		$tmpdpts =~ s/[\$\%\{\}]+//g;
		HMCCU_Trace ($cl_hash, 2, "vt=$vt, rn=$rn, dpts=$dpts, tmpdpts=$tmpdpts");
		my $f = 0;
		foreach my $chkey (@$chkeys) {
			if ($tmpdpts =~ /,$chkey,/) { $f = 1; last; }
		}
		next if ($f == 0);
		my @dplist = split (',', $dpts);

		# Get parameters values stored in device hash
		my $newdpts = HMCCU_SubstVariables ($cl_hash, $dpts, undef);
		my @pars = split (',', $newdpts);
		my $pc = scalar (@pars);
		if ($pc != scalar(@dplist) || $pc < $parCount{$vt}) {
			HMCCU_Log ($cl_hash, 2, "Wrong number of parameters in reading calculation expression $calculation");
			next;
		}
		$f = 0;
		for (my $i=0; $i<$pc; $i++) {
			$pars[$i] =~ s/^#//;
			if ($pars[$i] eq $dplist[$i]) { $f = 1; last; }
		}
		next if ($f);
		
		if ($vt eq 'dewpoint' || $vt eq 'abshumidity') {
			# Dewpoint and absolute humidity
			my ($tmp, $hum) = @pars;
			my ($a, $b) = $tmp >= 0.0 ? (7.5, 237.3) : (7.6, 240.7);
			my $sdd = 6.1078*(10.0**(($a*$tmp)/($b+$tmp)));
			my $dd = $hum/100.0*$sdd;
			if ($dd != 0.0) {
				if ($vt eq 'dewpoint') {
					my $v = log($dd/6.1078)/log(10.0);
					my $td = $b*$v/($a-$v);
					push (@result, $rn, (sprintf "%.1f", $td));
				}
				else {
					my $af = 100000.0*18.016/8314.3*$dd/($tmp+273.15);
					push (@result, $rn, (sprintf "%.1f", $af));
				}
			}
		}
		elsif ($vt eq 'equ') {
			# Set reading to value if all variables have the same value
			my $curval = shift @pars;
			my $f = 1;
			foreach my $newval (@pars) {
				$f = 0 if ("$newval" ne "$curval");
			}
			push (@result, $rn, $f ? $curval : "n/a");
		}
		elsif ($vt eq 'min' || $vt eq 'max') {
			# Minimum or maximum values
			my $curval = $pc > 1 ? shift @pars : ReadingsVal ($name, $rn, 0);
			foreach my $newval (@pars) {
				$curval = $newval if ($vt eq 'min' && $newval < $curval);
				$curval = $newval if ($vt eq 'max' && $newval > $curval);
			}
			push (@result, $rn, $curval);
		}
		elsif ($vt eq 'inc' || $vt eq 'dec') {
			# Increasing or decreasing values without reset
			my $newval = shift @pars;
			my $oldval = ReadingsVal ($name, $rn."_old", 0);
			my $curval = ReadingsVal ($name, $rn, 0);
			if (($vt eq 'inc' && $newval < $curval) || ($vt eq 'dec' && $newval > $curval)) {
				$oldval = $curval;
				push (@result, $rn."_old", $oldval);
			}
			$curval = $newval+$oldval;
			push (@result, $rn, $curval);
 		}
		elsif ($vt eq 'avg') {
			# Average value
			if ($pc == 1) {
				my $newval = shift @pars;
				my $cnt = ReadingsVal ($name, $rn."_cnt", 0);
				my $sum = ReadingsVal ($name, $rn."_sum", 0);
				$cnt++;
				$sum += $newval;
				my $curval = $sum/$cnt;
				push (@result, $rn."_cnt", $cnt, $rn."_sum", $sum, $rn, $curval);
			}
			else {
				my $sum = 0;
				foreach my $p (@pars) { $sum += $p; }
				push (@result, $rn, $sum/scalar(@pars));
			}
		}
		elsif ($vt eq 'sum') {
			# Sum of values
			my $curval = $pc > 1 ? 0 : ReadingsVal ($name, $rn, 0);
			foreach my $newval (@pars) { $curval += $newval; }
			push (@result, $rn, $curval);
		}
		elsif ($vt eq 'or') {
			# Logical OR
			my $curval = $pc > 1 ? 0 : ReadingsVal ($name, $rn, 0);
			foreach my $newval (@pars) { $curval |= $newval; }
			push (@result, $rn, $curval);
		}
		elsif ($vt eq 'and') {
			# Logical AND
			my $curval = $pc > 1 ? 1 : ReadingsVal ($name, $rn, 1);
			foreach my $newval (@pars) { $curval &= $newval; }
			push (@result, $rn, $curval);
		}
		elsif ($vt eq 'set') {
			# Set reading to value
			push (@result, $rn, join('', @pars));
		}
	}
	
	return @result;
}

######################################################################
# Encrypt string with FHEM unique ID
######################################################################

sub HMCCU_Encrypt ($)
{
	my ($istr) = @_;
	
	my $id = getUniqueId() // return '';
	
	my $key = $id;
	my $ostr = '';
	foreach my $c (split //, $istr) {
		my $k = chop($key);
		if ($k eq '') {
			$key = $id;
			$k = chop($key);
		}
		$ostr .= sprintf ("%.2x",ord($c)^ord($k));
	}

	return $ostr;	
}

######################################################################
# Decrypt string with FHEM unique ID
######################################################################

sub HMCCU_Decrypt ($)
{
	my ($istr) = @_;

	my $id = getUniqueId() // return '';

	my $key = $id;
	my $ostr = '';
	foreach my $c (map { pack('C', hex($_)) } ($istr =~ /(..)/g)) {
		my $k = chop($key);
		if ($k eq '') {
			$key = $id;
			$k = chop($key);
		}
		$ostr .= chr(ord($c)^ord($k));
	}

	return $ostr;
}

######################################################################
# Delete readings matching regular expression.
# Default for rnexp is .*
# Readings 'state' and 'control' are ignored.
######################################################################

sub HMCCU_DeleteReadings ($;$)
{
	my ($hash, $rnexp) = @_;
	$rnexp //= '.*';
	
	my @readlist = keys %{$hash->{READINGS}};
	foreach my $rd (@readlist) {
		readingsDelete ($hash, $rd) if ($rd ne 'state' && $rd ne 'control' && $rd =~ /$rnexp/);
	}
}

######################################################################
# Update readings from hash
# If flag & 1, consider reading update attributes
# If flag & 2, skip Begin/End Update
######################################################################

sub HMCCU_UpdateReadings ($$;$)
{
	my ($hash, $readings, $flag) = @_;
	$flag //= 1;
	my $name = $hash->{NAME};

	my $ccureadings = $flag & 1 ?
		AttrVal ($name, 'ccureadings', HMCCU_IsFlag ($name, 'noReadings') ? 0 : 1) : 1;
	
	if ($ccureadings) {
		readingsBeginUpdate ($hash) if (!($flag & 2));
		foreach my $rn (keys %{$readings}) {
			readingsBulkUpdate ($hash, $rn, $readings->{$rn});
		}
		readingsEndUpdate ($hash, 1) if (!($flag & 2));
	}
}

######################################################################
# Encode command string for e-paper display
#
# Parameters:
#
#  msg := parameter:value[,...]
#
#  text1-3=Text
#  icon1-3=IconName
#  sound=SoundName
#  signal=SignalName
#  pause=1-160
#  repeat=0-15
#
# Returns undef on error or encoded string on success
######################################################################

sub HMCCU_EncodeEPDisplay ($)
{
	my ($msg) = @_;	
	$msg //= '';
	
	my %disp_icons = (
		ico_off    => '0x80', ico_on => '0x81', ico_open => '0x82', ico_closed => '0x83',
		ico_error  => '0x84', ico_ok => '0x85', ico_info => '0x86', ico_newmsg => '0x87',
		ico_svcmsg => '0x88'
	);

	my %disp_sounds = (
		snd_off        => '0xC0', snd_longlong => '0xC1', snd_longshort  => '0xC2',
		snd_long2short => '0xC3', snd_short    => '0xC4', snd_shortshort => '0xC5',
		snd_long       => '0xC6'
	);

	my %disp_signals = (
		sig_off => '0xF0', sig_red => '0xF1', sig_green => '0xF2', sig_orange => '0xF3'
	);

	my %conf = (
		sound => 'snd_off', signal => 'sig_off', repeat => 1, pause => 10
	);

	# Parse command string
	my @text = ('', '', '');
	my @icon = ('', '', '');
	foreach my $tok (split (',', $msg)) {
		my ($par, $val) = split (':', $tok, 2);
		next if (!defined($val));
		if    ($par =~ /^text([1-3])$/)                 { $text[$1-1] = substr($val, 0, 12); }
		elsif ($par =~ /^icon([1-3])$/)                 { $icon[$1-1] = $val; }
		elsif ($par =~ /^(sound|pause|repeat|signal)$/) { $conf{$1} = $val; }
	}
	
	my $cmd = '0x02,0x0A';

	for (my $c=0; $c<3; $c++) {
		if ($text[$c] ne '' || $icon[$c] ne '') {
			$cmd .= ',0x12';
			
			# Hex code
			if ($text[$c] =~ /^0x[0-9A-F]{2}$/i) {
				$cmd .= ','.$text[$c];
			}
			# Predefined text code #0-9
			elsif ($text[$c] =~ /^#([0-9])$/) {
				$cmd .= sprintf (",0x8%1X", $1);
			}
			# Convert string to hex codes
			else {
				$text[$c] =~ s/\\_/ /g;
				foreach my $ch (split ('', $text[$c])) { $cmd .= sprintf (",0x%02X", ord($ch)); }
			}
			
			# Icon
			if ($icon[$c] ne '' && exists($disp_icons{$icon[$c]})) {
				$cmd .= ',0x13,'.$disp_icons{$icon[$c]};
			}
		}
		
		$cmd .= ',0x0A';
	}
	
	# Sound
	my $snd = $disp_sounds{snd_off};
	$snd = $disp_sounds{$conf{sound}} if (exists($disp_sounds{$conf{sound}}));
	$cmd .= ',0x14,'.$snd.',0x1C';

	# Repeat
	my $rep = HMCCU_AdjustValue ($conf{repeat}, 0, 15);
	$cmd .= $rep == 0 ? ',0xDF' : sprintf (",0x%02X", 0xD0+$rep-1);
	$cmd .= ',0x1D';
	
	# Pause
	$cmd .= sprintf (",0xE%1X,0x16", int((HMCCU_AdjustValue ($conf{pause}, 1, 160)-1)/10));
	
	# Signal
	my $sig = $disp_signals{sig_off};
	$sig = $disp_signals{$conf{signal}} if(exists($disp_signals{$conf{signal}}));
	$cmd .= ','.$sig.',0x03';
	
	return $cmd;
}

######################################################################
# Convert reference to string recursively
# Supports reference to ARRAY, HASH and SCALAR and scalar values.
######################################################################

sub HMCCU_RefToString ($;$)
{
	my ($r, $l) = @_;
	$r //= 'Undefined value';
	$l //= 0;
	my $s1 = ' ' x ($l*2);
	my $s2 = ' ' x (($l+1)*2);

	if (ref($r) eq 'ARRAY') {
		my $result = "[\n";
		$result .= join (",\n", map { $s2.HMCCU_RefToString($_, $l+1) } @$r);
		return "$result\n$s1]";
	}
	elsif (ref($r) eq 'HASH') {
		my $result .= "{\n";
		$result .= join (",\n", map { $s2."$_=".HMCCU_RefToString($r->{$_}, $l+1) } sort keys %$r);
		return "$result\n$s1}";
	}
	elsif (ref($r) eq 'SCALAR') {
		return $$r;
	}
	else {
		return $r;
	}
}

######################################################################
# Convert bitmask to string
######################################################################

sub HMCCU_BitsToStr ($$)
{
	my ($chrMap, $bMask) = @_;
	
	my $r = '';
	foreach my $bVal (sort keys %$chrMap) { $r .= $chrMap->{$bVal} if ($bMask & $bVal); }
	return $r;
}

######################################################################
# Ensure that value is within range low-high
######################################################################

sub HMCCU_AdjustValue ($$$)
{
	my ($value, $low, $high) = @_;;
	
	return $low if ($value < $low);
	return $high if ($value > $high);
	return $value;
}

######################################################################
# Match string with regular expression considering illegal regular
# expressions.
# Return parameter e if regular expression is incorrect.
######################################################################

sub HMCCU_ExprMatch ($$$)
{
	my ($t, $r, $e) = @_;

	my $x = eval { $t =~ /$r/ } // $e;
	return "$x" eq '' ? 0 : 1;
}

sub HMCCU_ExprNotMatch ($$$)
{
	my ($t, $r, $e) = @_;

	my $x = eval { $t !~ /$r/ } // $e;
	return "$x" eq '' ? 0 : 1;
}

######################################################################
# Read duty cycles of interfaces 2001 and 2010 and update readings.
######################################################################

sub HMCCU_GetDutyCycle ($)
{
	my ($hash) = @_;
	
	my $dc = 0;
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash);
	my %readings = ();
	
	foreach my $port (values %$interfaces) {
		next if ($port != 2001 && $port != 2010);
		my ($url, $auth) = HMCCU_BuildURL ($hash, $port);
		if ($url eq '') {
			HMCCU_Log ($hash, 2, "Cannot get RPC URL for port $port");
			next;
		}

		my $header = HTTP::Headers->new ('Connection' => 'Keep-Alive');
		$header->header('Authorization' => "Basic $auth") if ($auth) ne '';
		my $rpcclient = RPC::XML::Client->new ($url,
			useragent => [
				ssl_opts => { verify_hostname => 0, SSL_verify_mode => 0 }
			]
		);
		$rpcclient->useragent->default_headers($header);

		my $response = $rpcclient->simple_request ('listBidcosInterfaces');
		next if (!defined($response) || ref($response) ne 'ARRAY');
		foreach my $iface (@$response) {
			next if (ref($iface) ne 'HASH' || !exists($iface->{DUTY_CYCLE}));
			$dc++;
			my ($type) = exists($iface->{TYPE}) ?
				($iface->{TYPE}) : HMCCU_GetRPCServerInfo ($hash, $port, 'name');
			my $ext = substr($iface->{ADDRESS}, -4);
			$readings{"iface_addr_$ext"} = $iface->{ADDRESS};
			$readings{"iface_conn_$ext"} = $iface->{CONNECTED};
			$readings{"iface_type_$ext"} = $type;
			$readings{"iface_ducy_$ext"} = $iface->{DUTY_CYCLE};
		}
	}
	
	HMCCU_UpdateReadings ($hash, \%readings);

	return $dc;
}

######################################################################
# Check if TCP port is reachable.
# Parameter timeout should be a multiple of 20 plus 5.
######################################################################

sub HMCCU_TCPPing ($$$)
{
	my ($addr, $port, $timeout) = @_;
	
	if ($timeout > 0) {
		my $t = time ();
	
		while (time() < $t+$timeout) {
			return 1 if (HMCCU_TCPConnect ($addr, $port, 1) ne '');
			sleep ($HMCCU_CCU_PING_SLEEP);
		}
		
		return 0;
	}
	else {
		return HMCCU_TCPConnect ($addr, $port) eq '' ? 0 : 1;
	}
}

######################################################################
# Check if TCP connection to specified host and port is possible.
# Return empty string on error or local IP address on success.
######################################################################

sub HMCCU_TCPConnect ($$;$)
{
	my ($addr, $port, $timeout) = @_;
	
	my $socket = IO::Socket::INET->new (PeerAddr => $addr, PeerPort => $port, Timeout => $timeout);
	if ($socket) {
		my $ipaddr = $socket->sockhost ();
		close ($socket);
		return $ipaddr if (defined($ipaddr));
	}

	return '';
}

######################################################################
# Generate a 6 digit Id from last 2 segments of IP address
######################################################################

sub HMCCU_GetIdFromIP ($$)
{
	my ($ip, $default) = @_;
	return $default if (!defined($ip));

	if ($ip =~ /:[0-9]{1,4}$/) {
		# Looks like an IPv6 address
		$ip =~ s/://g;
		my $ip1 = int(hex('0x'.substr($ip,-4))/256) // 0;
		my $ip2 = hex('0x'.substr($ip,-4))%256 // 0;
		return $ip1 > 0 || $ip2 > 0 ? sprintf("%03d%03d", $ip1, $ip2) : $default;
	}
	else {
		my @ipseg = split (/\./, $ip);
		return scalar(@ipseg) == 4 ? sprintf ("%03d%03d", $ipseg[2], $ipseg[3]) : $default;
	}
}
	
######################################################################
# Resolve hostname.
# Return value defIP if hostname can't be resolved.
######################################################################

sub HMCCU_ResolveName ($$)
{
	my ($host, $defIP) = @_;
	
	my $addrNum = inet_aton ($host);	
	return defined($addrNum) ? inet_ntoa ($addrNum) : $defIP;
}

######################################################################
# Substitute invalid characters in reading name.
# Substitution rules: ':' => '.', any other illegal character => '_'
######################################################################

sub HMCCU_CorrectName ($)
{
	my ($rn) = @_;
	
	$rn =~ s/\:/\./g;
	$rn =~ s/[^A-Za-z\d_\.-]+/_/g;
	return $rn;
}

######################################################################
# Get N biggest hash entries
# Format of returned hash is
#   {0..entries-1}{k} = Key of hash entry
#   {0..entries-1}{v} = Value of hash entry
######################################################################

sub HMCCU_MaxHashEntries ($$)
{
	my ($hash, $entries) = @_;
	my %result;

	while (my ($key, $value) = each %$hash) {
		for (my $i=0; $i<$entries; $i++) {
			if (!exists ($result{$i}) || $value > $result{$i}{v}) {
				for (my $j=$entries-1; $j>$i; $j--) {
					if (exists ($result{$j-1})) {
						$result{$j}{k} = $result{$j-1}{k};
						$result{$j}{v} = $result{$j-1}{v};
					}
				}
				$result{$i}{v} = $value;
				$result{$i}{k} = $key;
				last;
			}
		}
	}

	return \%result;
}

######################################################################
# Set or delete credentials
#######################################################################

sub HMCCU_SetCredentials ($@)
{
	my ($ioHashOrName, $key, $username, $password) = @_;
	$key //= '_';

	my $name = ref($ioHashOrName) eq 'HASH' ? $ioHashOrName->{NAME} : $ioHashOrName;
	my $userkey = $name.$key.'username';
	my $passkey = $name.$key.'password';
	my $rc;

	# Delete CCU credentials
	if (!defined($username)) {
		my ($erruser, $encuser) = getKeyValue ($userkey);
		my ($errpass, $encpass) = getKeyValue ($passkey);
		$rc = setKeyValue ($userkey, undef) if (!defined($erruser) && defined($encuser));
		return $rc if (defined($rc));
		$rc = setKeyValue ($passkey, undef) if (!defined($errpass) && defined($encpass));
		return $rc if (defined($rc));
	}
	elsif (defined($password)) {
		my $encuser = HMCCU_Encrypt ($username);
		return 'Cannot encrypt username' if ($encuser eq '');
		my $encpass = HMCCU_Encrypt ($password);
		return 'Cannot encrypt password' if ($encpass eq '');
		$rc = setKeyValue ($userkey, $encuser);
		return $rc if (defined($rc));
		$rc = setKeyValue ($passkey, $encpass);
		return $rc if (defined($rc));
	}
	else {
		return 'Missing password';
	}

	return undef;
}

######################################################################
# Read credentials
#######################################################################

sub HMCCU_GetCredentials ($@)
{
	my ($ioHashOrName, $key) = @_;
	$key //= '_';

	my $name = ref($ioHashOrName) eq 'HASH' ? $ioHashOrName->{NAME} : $ioHashOrName;
	my $userkey = $name.$key.'username';
	my $passkey = $name.$key.'password';

	my ($erruser, $encuser) = getKeyValue ($userkey);
	my ($errpass, $encpass) = getKeyValue ($passkey);

	my $username = defined($encuser) ? HMCCU_Decrypt ($encuser) : '';
	my $password = defined($encpass) ? HMCCU_Decrypt ($encpass) : '';

	return ($username, $password);
}

1;


=pod
=item device
=item summary provides interface between FHEM and Homematic CCU2
=begin html

<a name="HMCCU"></a>
<h3>HMCCU</h3>
<ul>
   The module provides an interface between FHEM and a Homematic CCU. HMCCU is the 
   I/O device for the client devices HMCCUDEV and HMCCUCHN. The module requires the
   additional Perl modules IO::File, RPC::XML::Client, RPC::XML::Server.
   </br></br>
   <a name="HMCCUdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCU [&lt;Protocol&gt;://]&lt;HostOrIP&gt; [&lt;ccu-number&gt;] [nosync]
      [waitforccu=&lt;timeout&gt;] [ccudelay=&lt;delay&gt;] [delayedinit=&lt;delay&gt;]</code>
      <br/><br/>
      Example:<br/>
      <code>define myccu HMCCU https://192.168.1.10 nosync ccudelay=180</code>
      <br/><br/>
      The parameter <i>HostOrIP</i> is the hostname or IP address of a Homematic CCU. Optionally
      the <i>protocol</i> 'http' or 'https' can be specified. Default protocol is 'http'.<br/>
      If you have more than one CCU you can specifiy a unique CCU number with parameter <i>ccu-number</i>.
		If there's only one CCU, the default <i>ccu-number</i> is 1. Note: The ports used for the RPC
		servers depend on the <i>ccu-number</i>. See attribute rpcserverport for more information.<br/>
      The option<i>nosync</i> prevents reading CCU config during interactive device definition. This
      option is ignored during FHEM start.<br/>
      With option <i>waitforccu</i> HMCCU will wait for the specified time if CCU is not reachable.
      Parameter <i>timeout</i> should be a multiple of 20 in seconds. Warning: This option will 
      block the start of FHEM for a maximum of <i>timeout</i> seconds. The default value is 1.<br/>
      The option <i>ccudelay</i> specifies the time for delayed initialization of CCU environment if
      the CCU is not reachable during FHEM startup (i.e. in case of a power failure). The default value
      for <i>delay</i> is 180 seconds. Increase this value if your CCU needs more time to start up
      after a power failure. This option will not block the start of FHEM.<br/>
      With option <i>delayedinit</i> the CCU ennvironment will be initialized after the specified time,
      no matter if CCU is reachable or not. As long as CCU environment is not initialized all client
      devices of type HMCCUCHN or HMCCUDEV are in state 'pending' and all commands are disabled.<br/><br/>
      For automatic update of Homematic device datapoints and FHEM readings one have to:
      <br/><br/>
      <ul>
      <li>Define used RPC interfaces with attribute 'rpcinterfaces'</li>
      <li>Start RPC servers with command 'set on'</li>
      <li>Optionally enable automatic start of RPC servers by setting attribute 'rpcserver' to 'on'.</li>
      </ul><br/>
	  When RPC servers are started for the first time, HMCCU will create a HMCCURPCPROC device for 
	  each interface defined in attribut 'rpcinterfaces'. These devices are assigned xto the same room
	  as I/O device.<br/>
      After I/O device has been defined, start with the definition of client devices using modules HMCCUDEV (CCU devices)
      and HMCCUCHN (CCU channels) or with commands 'get createDev' or 'get create'.<br/>
   </ul>
   <br/>
   
   <a name="HMCCUset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; ackmessages</b><br/>
      	Acknowledge "device was unreachable" messages in CCU.
      </li><br/>
      <li><b>set &lt;name&gt; authentication ['json'] [&lt;username&gt; &lt;password&gt;]</b><br/>
      	Set credentials for CCU authentication. With option 'json' the CCU JSON interface is used for syncing the CCU configuration.<br/>
      	When executing this command without username and password, the credentials are deleted.
      </li><br/>
      <li><b>set &lt;name&gt; clear [&lt;reading-exp&gt;]</b><br/>
         Delete readings matching specified reading name expression. Default expression is '.*'.
         Readings 'state' and 'control' are not deleted.
      </li><br/>
		<li><b>set &lt;name&gt; cleardefaults</b><br/>
			Clear default attributes imported from file.
		</li><br/>
		<li><b>set &lt;name&gt; datapoint &lt;FHEM-DevSpec&gt; [&lt;channel-number&gt;].&lt;datapoint&gt;=&ltvalue&gt;</b><br/>
			Set datapoint values on multiple devices. If <i>FHEM-Device</i> is of type HMCCUDEV
			a <i>channel-number</i> must be specified. The channel number is ignored for devices of
			type HMCCUCHN.
		</li><br/>
		<li><b>set &lt;name&gt; delete &lt;ccuobject&gt; [&lt;objecttype&gt;]</b><br/>
			Delete object in CCU. Default object type is OT_VARDP. Valid object types are<br/>
			OT_DEVICE=device, OT_VARDP=variable.
		</li><br/>
      <li><b>set &lt;name&gt; execute &lt;program&gt;</b><br/>
         Execute a CCU program.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu execute PR-TEST</code>
      </li><br/>
      <li><b>set &lt;name&gt; hmscript {&lt;script-file&gt;|'!'&lt;function&gt;|'['&lt;code&gt;']'} [dump] 
         [&lt;parname&gt;=&lt;value&gt; [...]]</b><br/>
         Execute Homematic script on CCU. If script code contains parameters in format $parname
         they are substituted by corresponding command line parameters <i>parname</i>.<br/>
         If output of script contains lines in format Object=Value readings in existing
         corresponding FHEM devices will be set. <i>Object</i> can be the name of a CCU system
         variable or a valid channel and datapoint specification. Readings for system variables
         are set in the I/O device. Datapoint related readings are set in client devices. If option
         'dump' is specified the result of script execution is displayed in FHEM web interface.
         Execute command without parameters will list available script functions.
      </li><br/>
      <li><b>set &lt;name&gt; importdefaults &lt;filename&gt;</b><br/>
      	Import default attributes from file.
      </li><br/>
      <li><b>set &lt;name&gt; initialize</b><br/>
      	Initialize I/O device if state of CCU is unreachable.
      </li><br/>
      <li><b>set &lt;name&gt; off</b><br/>
	  	 Stop RPC server(s). See also 'set on' command.
      </li><br/>
      <li><b>set &lt;name&gt; on</b><br/>
	     Start RPC server(s). This command will fork a RPC server process for each RPC interface defined in attribute 'rpcinterfaces'.
         Until operation is completed only a few set/get commands are available and you may get the error message 'CCU busy'.
      </li><br/>
	  <li><b>set &lt;name&gt; prgActivate &lt;program&gt;</b><br/>
         Activate a CCU program.
      </li><br/>
      <li><b>set &lt;name&gt; prgDeactivate &lt;program&gt;</b><br/>
         Deactivate a CCU program.
      </li><br/>
      <li><b>set &lt;name&gt; rpcregister [{all | &lt;interface&gt;}]</b><br/>
      	Register RPC servers at CCU.
      </li><br/>
      <li><b>set &lt;name&gt; var &lt;variable&gt; &lt;Value&gt;</b><br/>
        Set CCU system variable value. Special characters \_ in <i>value</i> are
        substituted by blanks.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; aggregation {&lt;rule&gt;|all}</b><br/>
      	Process aggregation rule defined with attribute ccuaggregate.
      </li><br/>
      <li><b>get &lt;name&gt; ccuConfig</b><br/>
         Read configuration of CCU (devices, channels, programs). This command is executed automatically
         after the definition of an I/O device. It must be executed manually after
         module HMCCU is reloaded or after devices have changed in CCU (added, removed or
         renamed).<br/>
         If a RPC server is running HMCCU will raise events "<i>count</i> devices added in CCU" or
         "<i>count</i> devices deleted in CCU". It's recommended to set up a notification
         which reacts with execution of command 'get ccuConfig' on these events.
      </li><br/>
      <li><b>get &lt;name&gt; ccuDevices</b><br/>
      	Show table of CCU devices including channel roles supported by HMCCU auto detection.
      </li><br/>
      <li><b>get &lt;name&gt; ccumsg {service|alarm}</b><br/>
      	Query active service or alarm messages from CCU. Generate FHEM event for each message.
      </li><br/>
      <li><b>get &lt;name&gt; create &lt;devexp&gt; [p=&lt;prefix&gt;] [s=&lt;suffix&gt;] [f=&lt;format&gt;]
      	[noDefaults] [save] [&lt;attr&gt;=&lt;value&gt; [...]]</b><br/>
         Create client devices for all CCU devices and channels matching specified regular
         expression. Parameter <i>devexp</i> is a regular expression for CCU device or channel
         names. HMCCU automatically creates the appropriate client device (HMCCUCHN or HMCCUDEV)<br/>
         With options 'p' and 's' a <i>prefix</i> and/or a <i>suffix</i> for the FHEM device
         name can be specified. The option 'f' with parameter <i>format</i>
         defines a template for the FHEM device names. Prefix, suffix and format can contain
         format identifiers which are substituted by corresponding values of the CCU device or
         channel:<br/>
         %n = CCU object name (channel or device)<br/>
         %a = CCU address<br/>
         In addition a list of default attributes for the created client devices can be specified.
         If option 'noDefaults' is specified, HMCCU does not set default attributes for a device.
         Option 'save' will save FHEM config after device definition.
      </li><br/>
      <li><b>get &lt;name&gt; createDev &lt;devname&gt;</b><br/>
        Simplified version of 'get create'. Doesn't accept a regular expression for device name.
      </li><br/>
	  <li><b>get &lt;name&gt; detectDev &lt;devname&gt;</b><br/>
	    Diagnostics command. Try to auto-detect device and display the result. Add this information
		to your post in FHEM forum, if a device is not created as expected.
	  </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	List device types and channels with default attributes available.
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo &lt;device-name-or-address&gt; [extended]</b><br/>
         List device channels, datapoints and the device description. 
      </li><br/>
      <li><b>get &lt;name&gt; dutycycle</b><br/>
         Read CCU interface and gateway information. For each interface/gateway the following
         information is stored in readings:<br/>
         iface_addr_n = interface address<br/>
         iface_type_n = interface type<br/>
         iface_conn_n = interface connection state (1=connected, 0=disconnected)<br/>
         iface_ducy_n = duty cycle of interface (0-100)
      </li><br/>
      <li><b>get &lt;name&gt; exportdefaults &lt;filename&gt; [all]</b><br/>
      	Export default attributes into file. If option <i>all</i> is specified, also defaults imported
      	by customer will be exported.
      </li><br/>
	  <li><b>get &lt;name&gt; internal &lt;parameter&gt;</b><br/>
	  	Show internal values. Valid <i>parameters</i> are:<br/>
		<ul>
		<li>interfaces - RPC interfaces</li>
		<li>groups - Virtual CCU device groups</li>
		<li>versions - Versions of HMCCU modules</li>
		</ul>
	  </li><br/>
      <li><b>get &lt;name&gt; paramsetDesc {&lt;device&gt;|&lt;channel&gt;}</b><br/>
         Get parameter set description of CCU device or channel.
      </li><br/>
      <li><b>get &lt;name&gt; rpcstate</b><br/>
         Check if RPC server process is running.
      </li><br/>
      <li><b>get &lt;name&gt; update [&lt;devexp&gt; [{State | <u>Value</u>}]]</b><br/>
         Update all datapoints / readings of client devices with <u>FHEM device name</u>(!) matching
         <i>devexp</i>. With option 'State' all CCU devices are queried directly. This can be
         time consuming.
      </li><br/>
      <li><b>get &lt;name&gt; vars &lt;regexp&gt;</b><br/>
         Get CCU system variables matching <i>regexp</i> and store them as readings. Use attribute
		 ccuGetVars to fetch variables periodically.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
	  <li><b>ccuAdminURLs {ccu|cuxd}=&lt;url&gt; [...]</b><br/>
	  	Define admin URLs for CCU and CUxD web interface. URls must be in format: Protocol://Host[:Port]. Page or
		html files will be added automatically. Example:<br/>
		attr myIODev ccuAdminURLs ccu=https://192.168.1.2 cuxd=https://192.168.1.2:3000
	  </li> 
      <li><b>ccuaggregate &lt;rule&gt;[;...]</b><br/>
      	Define aggregation rules for client device readings. With an aggregation rule
      	it's easy to detect if some or all client device readings are set to a specific
      	value, i.e. detect all devices with low battery or detect all open windows.<br/>
      	Aggregation rules are automatically executed as a reaction on reading events of
      	HMCCU client devices. An aggregation rule consists of several parameters separated
      	by comma:<br/><br/>
      	<ul>
      	<li><b>name:&lt;rule-name&gt;</b><br/>
      	Name of aggregation rule</li>
      	<li><b>filter:{name|alias|group|room|type}=&lt;incl-expr&gt;[!&lt;excl-expr&gt;]</b><br/>
      	Filter criteria, i.e. "type=^HM-Sec-SC.*"</li>
      	<li><b>read:&lt;read-expr&gt;</b><br/>
      	Expression for reading names, i.e. "STATE"</li>
      	<li><b>if:{any|all|min|max|sum|avg|lt|gt|le|ge}=&lt;value&gt;</b><br/>
      	Condition, i.e. "any=open" or initial value, i.e. max=0</li>
      	<li><b>else:&lt;value&gt;</b><br/>
      	Complementary value, i.e. "closed"</li>
      	<li><b>prefix:{&lt;text&gt;|RULE}</b><br/>
      	Prefix for reading names with aggregation results</li>
      	<li><b>coll:{&lt;attribute&gt;|NAME}[!&lt;default-text&gt;]</b><br/>
      	Attribute of matching devices stored in aggregation results. Default text in case
      	of no matching devices found is optional.</li>
      	<li><b>html:&lt;template-file&gt;</b><br/>
      	Create HTML code with matching devices.</li>
      	</ul><br/>
      	Aggregation results will be stored in readings <i>prefix</i>count, <i>prefix</i>list,
      	<i>prefix</i>match, <i>prefix</i>state and <i>prefix</i>table.<br/><br/>
      	Format of a line in <i>template-file</i> is &lt;keyword&gt;:&lt;html-code&gt;. See
      	FHEM Wiki for an example. Valid keywords are:<br/><br/>
      	<ul>
      	<li><b>begin-html</b>: Start of html code.</li>
      	<li><b>begin-table</b>: Start of table (i.e. the table header)</li>
      	<li><b>row-odd</b>: HTML code for odd lines. A tag &lt;reading/&gt is replaced by a matching device.</li>
      	<li><b>row-even</b>: HTML code for event lines.</li>
      	<li><b>end-table</b>: End of table.</li>
      	<li><b>default</b>: HTML code for no matches.</li>
      	<li><b>end-html</b>: End of html code.</li>
      	</ul><br/>
      	Example: Find open windows<br/>
      	name=lock,filter:type=^HM-Sec-SC.*,read:STATE,if:any=open,else:closed,prefix:lock_,coll:NAME!All windows closed<br/><br/>
      	Example: Find devices with low batteries. Generate reading in HTML format.<br/>
      	name=battery,filter:name=.*,read:(LOWBAT|LOW_BAT),if:any=yes,else:no,prefix:batt_,coll:NAME!All batteries OK,html:/home/battery.cfg<br/>
      </li><br/>
		<li><b>ccudef-attributes &lt;attrName&gt;=&lt;attrValue&gt;[;...]</b><br/>
			Define attributes which are assigned to newly defined HMCCUDEV or HMCCUCHN devices. By default no
			attributes will be assigned. To assign every new device to room Homematic, set this attribute
			to 'room=Homematic'.
		</li><br/>
      <li><b>ccudef-hmstatevals &lt;subst-rule[;...]&gt;</b><br/>
      	Set global rules for calculation of reading hmstate.
      </li><br/>
      <li><b>ccudef-readingformat {name | address | <u>datapoint</u> | namelc | addresslc |
		   datapointlc}</b><br/>
		   Set global reading format. This format is the default for all readings except readings
		   of virtual device groups.
		</li><br/>
      <li><b>ccudef-stripnumber [&lt;datapoint-expr&gt;!]{0|1|2|-n|%fmt}[;...]</b><br/>
         Set global formatting rules for numeric datapoint or config parameter values.
         Default value is 2 (strip trailing zeroes).<br/>
         For details see description of attribute stripnumber in <a href="#HMCCUCHNattr">HMCCUCHN</a>.
      </li>
      <li><b>ccudef-substitute &lt;subst-rule&gt;[;...]</b><br/>
         Set global substitution rules for datapoint value. These rules are added to the rules
         specified by client device attribute 'substitute'.
      </li><br/>
      <li><b>ccudefaults &lt;filename&gt;</b><br/>
      	Load default attributes for HMCCUCHN and HMCCUDEV devices from specified file. Best
      	practice for creating a custom default attribute file is by exporting predefined default
      	attributes from HMCCU with command 'get exportdefaults'.
      </li><br/>
      <li><b>ccuflags {&lt;flags&gt;}</b><br/>
      	Control behaviour of several HMCCU functions. Parameter <i>flags</i> is a comma
      	seperated list of the following strings:<br/>
      	ackState - Acknowledge command execution by setting STATE to error or success.<br/>
      	dptnocheck - Do not check within set or get commands if datapoint is valid<br/>
      	intrpc - No longer supported.<br/>
      	extrpc - No longer supported.<br/>
      	logCommand - Write all set and get commands of all devices to log file with verbose level 3.<br/>
      	logEnhanced - Messages in FHEM logfile will contain line number and process ID.<br/>
      	logEvents - Write events from CCU into FHEM logfile<br/>
			logPong - Write log message when receiving pong event if verbose level is at least 3.<br/>
			noAutoSubstitute - Do not substitute reading values by names. This global flag affects all devices. Set this flag in client devices to turn off substitutions in single devices<br/>
      	noEvents - Ignore events / device updates sent by CCU. No readings will be updated!<br/>
      	noInitialUpdate - Do not update datapoints of devices after RPC server start. Overrides 
      	settings in RPC devices.<br/>
			noAutoDetect - Do not detect any device (only for development and testing)<br/>
      	nonBlocking - Use non blocking (asynchronous) CCU requests<br/>
      	noReadings - Do not create or update readings<br/>
      	procrpc - Use external RPC server provided by module HMCCPRPCPROC. During first RPC
      	server start HMCCU will create a HMCCURPCPROC device for each interface confiugured
      	in attribute 'rpcinterface'<br/>
      	reconnect - Automatically reconnect to CCU when events timeout occurred.
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than
         'Value' because each request is sent to the device. With method 'Value' only CCU
         is queried. Default is 'Value'. Method for write access to datapoints is always
         'State'.
      </li><br/>
      <li><b>ccuGetVars &lt;interval&gt;:[&lt;pattern&gt;]</b><br/>
      	Read CCU system variables periodically and update readings. If pattern is specified
      	only variables matching this expression are stored as readings. Delete attribute or set
		<i>interval</i> to 0 to deactivate the polling of system variables.
      </li><br/>
      <li><b>ccuReqTimeout &lt;Seconds&gt;</b><br/>
      	Set timeout for CCU request. Default is 4 seconds. This timeout affects several
      	set and get commands, i.e. "set datapoint" or "set var". If a command runs into
      	a timeout FHEM will block for <i>Seconds</i>. To prevent blocking set flag 'nonBlocking'
      	in attribute <i>ccuflags</i>.
      </li><br/>
      <li><b>ccureadings {0 | <u>1</u>}</b><br/>
         Deprecated. Readings are written by default. To deactivate readings set flag noReadings
         in attribute ccuflags.
      </li><br/>
	  <li><b>createDeviceGroup &lt;pattern&gt;</b><br/>
	  	The commands "get create" and "get createDev" will automatically set the group
		attribute for newly created devices to the specified <i>pattern</i> if multiple FHEM
		devices were created for a single CCU device. This will happen i.e. for remote controls
		with mutliple keys or HmIP-Wired multi-switches.<br/>
		The parameter <i>pattern</i> supports the following placeholders:<br/>
		%n - replaced by CCU device name<br/>
		%a - replaced by CCU device address<br/>
		%t - replaced by CCU device type<br/>
		Example: A remote with 4 channels named 'Light_Control' should be created in FHEM. Using
		command "get createDev" will define one HMCCUCHN device per channel. Our naming scheme
		for automatically assigned groups should be "ccuDeviceType ccuDeviceName".<br>
		<pre>
		attr myIODev createDeviceGroup "%t %n" 
		get myIODev createDev Light_Control
		</pre>
	  </li><br/>
      <li><b>rpcinterfaces &lt;interface&gt;[,...]</b><br/>
   		Specify list of CCU RPC interfaces. HMCCU will register a RPC server for each interface.
   		Either interface BidCos-RF or HmIP-RF (HmIP only) is default. Valid interfaces are:<br/><br/>
   		<ul>
   		<li>BidCos-Wired (Port 2000)</li>
   		<li>BidCos-RF (Port 2001)</li>
   		<li>Homegear (Port 2003)</li>
   		<li>HmIP-RF (Port 2010)</li>
   		<li>HVL (Port 7000)</li>
   		<li>CUxD (Port 8701)</li>
   		<li>VirtualDevice (Port 9292)</li>
   		</ul>
      </li><br/>
	   <li><b>rpcPingCCU &lt;interval&gt;</b><br/>
	   	Send RPC ping request to CCU every <i>interval</i> seconds. If <i>interval</i> is 0
	   	ping requests are disabled. Default value is 300 seconds. If attribut ccuflags is set
	   	to logPong a log message with level 3 is created when receiving a pong event.
	   </li><br/>
      <li><b>rpcserver {on | <u>off</u>}</b><br/>
         Specify if RPC server is automatically started on FHEM startup.
      </li><br/>
      <li><b>rpcserveraddr &lt;ip-or-name&gt;</b><br/>
      	Specify network interface by IP address or DNS name where RPC server should listen
      	on. By default HMCCU automatically detects the IP address. This attribute should be used
      	if the FHEM server has more than one network interface.
      </li><br/>
      <li><b>rpcserverport &lt;base-port&gt;</b><br/>
      	Specify base port for RPC server. The real listening port of an RPC server is
      	calculated by the formula: base-port + rpc-port + (10 * ccu-number). Default
      	value for <i>base-port</i> is 5400.<br/>
      	The value ccu-number is only relevant if more than one CCU is connected to FHEM.
      	Example: If <i>base-port</i> is 5000, protocol is BidCos (rpc-port 2001) and only
      	one CCU is connected the resulting RPC server port is 5000+2001+(10*1) = 7010.
      </li><br/>
      <li><b>substitute &lt;subst-rule&gt;:&lt;substext&gt;[,...]</b><br/>
         Define substitions for datapoint values. Syntax of <i>subst-rule</i> is<br/><br/>
         [[&lt;channelno.&gt;]&lt;datapoint&gt;[,...]!]&lt;{#n1-m1|regexp1}&gt;:&lt;text1&gt;[,...]
      </li><br/>
      <li><b>stripchar &lt;character&gt;</b><br/>
         Strip the specified character from variable or device name in set commands. This
         is useful if a variable should be set in CCU using the reading with trailing colon.
      </li>
   </ul>
</ul>

=end html
=cut


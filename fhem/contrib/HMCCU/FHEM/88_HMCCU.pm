##############################################################################
#
#  88_HMCCU.pm
#
#  $Id: 88_HMCCU.pm 18745 2019-02-26 17:33:23Z zap $
#
#  Version 4.4.069
#
#  Module for communication between FHEM and Homematic CCU2/3.
#
#  Supports BidCos-RF, BidCos-Wired, HmIP-RF, virtual CCU channels,
#  CCU group devices, HomeGear, CUxD, Osram Lightify, Homematic Virtual Layer
#  and Philips Hue (not tested)
#
#  (c) 2021 by zap (zap01 <at> t-online <dot> de)
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
use IO::File;
use Encode qw(decode encode);
use RPC::XML::Client;
use RPC::XML::Server;
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
my $HMCCU_VERSION = '4.4.069';

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

# Flags for CCU object specification
my $HMCCU_FLAG_NAME      = 1;
my $HMCCU_FLAG_CHANNEL   = 2;
my $HMCCU_FLAG_DATAPOINT = 4;
my $HMCCU_FLAG_ADDRESS   = 8;
my $HMCCU_FLAG_INTERFACE = 16;
my $HMCCU_FLAG_FULLADDR  = 32;

# Valid flag combinations
my $HMCCU_FLAGS_IACD = $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_ADDRESS |
	$HMCCU_FLAG_CHANNEL | $HMCCU_FLAG_DATAPOINT;
my $HMCCU_FLAGS_IAC = $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_ADDRESS | $HMCCU_FLAG_CHANNEL;
my $HMCCU_FLAGS_ACD = $HMCCU_FLAG_ADDRESS | $HMCCU_FLAG_CHANNEL | $HMCCU_FLAG_DATAPOINT;
my $HMCCU_FLAGS_AC  = $HMCCU_FLAG_ADDRESS | $HMCCU_FLAG_CHANNEL;
my $HMCCU_FLAGS_ND  = $HMCCU_FLAG_NAME | $HMCCU_FLAG_DATAPOINT;
my $HMCCU_FLAGS_NC  = $HMCCU_FLAG_NAME | $HMCCU_FLAG_CHANNEL;
my $HMCCU_FLAGS_NCD = $HMCCU_FLAG_NAME | $HMCCU_FLAG_CHANNEL | $HMCCU_FLAG_DATAPOINT;

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


# Declare functions

# FHEM standard functions
sub HMCCU_Initialize ($);
sub HMCCU_Define ($$$);
sub HMCCU_InitDevice ($);
sub HMCCU_Undef ($$);
sub HMCCU_DelayedShutdown ($);
sub HMCCU_Shutdown ($);
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_Notify ($$);
sub HMCCU_Detail ($$$$);
sub HMCCU_PostInit ($);

# Aggregation
sub HMCCU_AggregateReadings ($$);
sub HMCCU_AggregationRules ($$);

# Handling of default attributes
sub HMCCU_ExportDefaults ($$);
sub HMCCU_ImportDefaults ($);
sub HMCCU_FindDefaults ($$);
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
sub HMCCU_GetReadingName ($$$$$$$;$);
sub HMCCU_ScaleValue ($$$$$;$);
sub HMCCU_StripNumber ($$;$);
sub HMCCU_Substitute ($$$$$;$$);
sub HMCCU_SubstRule ($$$);
sub HMCCU_SubstVariables ($$$);

# Update client device readings
sub HMCCU_BulkUpdate ($$$;$);
sub HMCCU_GetUpdate ($$$);
sub HMCCU_RefreshReadings ($);
sub HMCCU_UpdateCB ($$$);
sub HMCCU_UpdateClients ($$$$;$$);
sub HMCCU_UpdateInternalValues ($$$$$);
sub HMCCU_UpdateMultipleDevices ($$);
sub HMCCU_UpdatePeers ($$$$);
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
sub HMCCU_RPCRequest ($$$$;$$);
sub HMCCU_StartExtRPCServer ($);
sub HMCCU_StopExtRPCServer ($;$);

# Parse and validate names and addresses
sub HMCCU_ParseObject ($$$);
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
sub HMCCU_IdentifyRole ($$$$$);
sub HMCCU_DetectRolePattern ($;$$$$);
sub HMCCU_GetSCInfo ($$;$);
sub HMCCU_DeviceDescToStr ($$);
sub HMCCU_ExecuteRoleCommand ($@);
sub HMCCU_ExecuteGetDeviceInfoCommand ($@);
sub HMCCU_ExecuteGetParameterCommand ($@);
sub HMCCU_ExecuteSetClearCommand ($@);
sub HMCCU_ExecuteSetControlCommand ($@);
sub HMCCU_ExecuteSetDatapointCommand ($@);
sub HMCCU_ExecuteSetParameterCommand ($@);
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
sub HMCCU_GetFirmwareVersions ($$);
sub HMCCU_GetGroupMembers ($$);
sub HMCCU_GetMatchingDevices ($$$$);
sub HMCCU_GetParamDef ($$$;$);
sub HMCCU_GetParamValueConversion ($$$$$);
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
sub HMCCU_UpdateRoleCommands ($$;$);
sub HMCCU_UpdateAdditionalCommands ($$;$$);

# Handle datapoints
sub HMCCU_FindDatapoint ($$$$$);
sub HMCCU_GetDatapoint ($@);
sub HMCCU_GetDatapointAttr ($$$$$);
sub HMCCU_GetDatapointList ($;$$);
sub HMCCU_GetSCDatapoints ($);
sub HMCCU_SetSCDatapoints ($$;$$);
sub HMCCU_GetStateValues ($;$$);
sub HMCCU_GetValidDatapoints ($$$$;$);
sub HMCCU_IsValidDatapoint ($$$$$);
sub HMCCU_SetInitialAttributes ($$);
sub HMCCU_SetDefaultAttributes ($;$);
sub HMCCU_SetMultipleDatapoints ($$);
sub HMCCU_SetMultipleParameters ($$$;$);

# Homematic script and variable functions
sub HMCCU_GetVariables ($$);
sub HMCCU_HMCommand ($$$);
sub HMCCU_HMCommandCB ($$$);
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
sub HMCCU_DeleteReadings ($$);
sub HMCCU_EncodeEPDisplay ($);
sub HMCCU_ExprMatch ($$$);
sub HMCCU_ExprNotMatch ($$$);
sub HMCCU_FlagsToStr ($$$;$$);
sub HMCCU_UpdateDeviceStates ($);
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
sub HMCCU_RefToString ($);
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

	$hash->{DefFn}             = 'HMCCU_Define';
	$hash->{UndefFn}           = 'HMCCU_Undef';
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
		' ccudefaults'.
		' ccudef-hmstatevals:textField-long ccudef-substitute:textField-long'.
		' ccudef-readingformat:name,namelc,address,addresslc,datapoint,datapointlc'.
		' ccudef-stripnumber ccudef-attributes ccuReadingPrefix'.
		' ccuflags:multiple-strict,procrpc,dptnocheck,logCommand,noagg,nohmstate,updGroupMembers,'.
		'logEvents,noEvents,noInitialUpdate,noReadings,nonBlocking,reconnect,logPong,trace,logEnhanced'.
		' ccuReqTimeout ccuGetVars rpcPingCCU'.
		' rpcserver:on,off rpcserveraddr rpcserverport rpctimeout rpcevtimeout substitute'.
		' ccuget:Value,State '.
		$readingFnAttributes;
}

######################################################################
# Define device
######################################################################

sub HMCCU_Define ($$$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};
	my $usage = "Usage: define $name HMCCU {NameOrIP} [{ccunum}] [nosync] ccudelay={time} waitforccu={time} delayedinit={time}";

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
	$hash->{NOTIFYDEV}       = 'global,TYPE=(HMCCU|HMCCUDEV|HMCCUCHN)';
	$hash->{hmccu}{rpcports} = undef;

	HMCCU_Log ($hash, 1, "Initialized version $HMCCU_VERSION");
	
	my $rc = 0;
	if ($hash->{ccustate} eq 'active') {
		# If CCU is alive read devices, channels, interfaces and groups
		HMCCU_Log ($hash, 1, 'Initializing device');
		$rc = HMCCU_InitDevice ($hash);
	}
	
	if (($hash->{ccustate} ne 'active' || $rc > 0) && !$init_done) {
		# Schedule update of CCU assets if CCU is not active during FHEM startup
		$hash->{hmccu}{ccu}{delayed} = 1;
		HMCCU_Log ($hash, 1, 'Scheduling delayed initialization in '.$hash->{hmccu}{ccu}{delay}.' seconds');
		InternalTimer (gettimeofday()+$hash->{hmccu}{ccu}{delay}, "HMCCU_InitDevice", $hash);
	}
	
	$hash->{hmccu}{$_} = 0 for ('evtime', 'evtimeout', 'updatetime', 'rpccount', 'defaults');

	HMCCU_UpdateReadings ($hash, { 'state' => 'Initialized', 'rpcstate' => 'inactive' });

	if ($init_done) {
		$attr{$name}{stateFormat} = 'rpcstate/state';
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

	if ($hash->{hmccu}{ccu}{delayed} == 1) {
		HMCCU_Log ($hash, 1, 'Initializing devices');
		if (!HMCCU_TCPPing ($host, $HMCCU_REGA_PORT{$hash->{prot}}, $hash->{hmccu}{ccu}{timeout})) {
			$hash->{ccustate} = 'unreachable';
			return HMCCU_Log ($hash, 1, "CCU port ".$HMCCU_REGA_PORT{$hash->{prot}}." is not reachable", 1);
		}
	}

	my ($devcnt, $chncnt, $ifcount, $prgcount, $gcount) = HMCCU_GetDeviceList ($hash);
	if ($ifcount > 0) {
		setDevAttrList ($name, $modules{HMCCU}{AttrList}.' rpcinterfaces:multiple-strict,'.$hash->{ccuinterfaces});

		HMCCU_Log ($hash, 1, [
			"Read $devcnt devices with $chncnt channels from CCU $host",
			"Read $prgcount programs from CCU $host",
			"Read $gcount virtual groups from CCU $host"
		]);
		
		# Interactive device definition
		if ($init_done && $hash->{hmccu}{ccu}{delayed} == 0) {
			# Force sync with CCU during interactive device definition
			if ($hash->{hmccu}{ccu}{sync} == 1) {
 				HMCCU_Log ($hash, 1, 'Reading device config from CCU. This may take a couple of seconds ...');
				my ($cDev, $cPar, $cLnk) = HMCCU_GetDeviceConfig ($hash);
				HMCCU_Log ($hash, 2, "Read RPC device configuration: devices/channels=$cDev parametersets=$cPar links=$cLnk");
			}
		}
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

	if ($hash->{ccustate} eq 'active') {
		my $rpcServer = AttrVal ($hash->{NAME}, 'rpcserver', 'off');

		HMCCU_Log ($hash, 1, 'Reading device config from CCU. This may take a couple of seconds ...');
		my ($cDev, $cPar, $cLnk) = HMCCU_GetDeviceConfig ($hash);
		HMCCU_Log ($hash, 2, "Read device configuration: devices/channels=$cDev parametersets=$cPar links=$cLnk");
		
		HMCCU_StartExtRPCServer ($hash) if ($rpcServer eq 'on');
	}
	else {
		HMCCU_Log ($hash, 1, 'CCU not active. Post FHEM start initialization failed');
	}
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
			return "HMCCU: Attribute ccuackstate is depricated. Use ccuflags with 'ackState' instead";
		}
		elsif ($attrname eq 'ccureadings') {
			return "HMCCU: Attribute ccureadings is depricated. Use ccuflags with 'noReadings' instead";
		}
		elsif ($attrname eq 'ccuflags') {
			my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
			my @flags = ($attrval =~ /(intrpc|extrpc|procrpc)/g);
			return "Flags extrpc, procrpc and intrpc cannot be combined" if (scalar (@flags) > 1);
			if ($attrval =~ /(intrpc|extrpc)/) {
				HMCCU_Log ($hash, 1, "RPC server mode $1 no longer supported. Using procrpc instead");
				$attrval =~ s/(extrpc|intrpc)/procrpc/;
				$_[3] = $attrval;
			}
		}
		elsif ($attrname eq 'ccuGetVars') {
			my ($interval, $pattern) = split /:/, $attrval;
			$pattern = '.*' if (!defined ($pattern));
			$hash->{hmccu}{ccuvarspat} = $pattern;
			$hash->{hmccu}{ccuvarsint} = $interval;
			RemoveInternalTimer ($hash, "HMCCU_UpdateVariables");
			if ($interval > 0) {
				HMCCU_Log ($hash, 2, "Updating CCU system variables every $interval seconds");
				InternalTimer (gettimeofday()+$interval, "HMCCU_UpdateVariables", $hash);
			}
		}
		elsif ($attrname eq 'rpcdevice') {
			return "HMCCU: Attribute rpcdevice is depricated. Please remove it";
		}
		elsif ($attrname eq 'rpcport') {
			return 'HMCCU: Attribute rpcport is no longer supported. Use rpcinterfaces instead';
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

	return 0 if ($rulestr eq '');

	# Delete existing aggregation rules
	if (exists($hash->{hmccu}{agg})) { delete $hash->{hmccu}{agg}; }
	
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
# Return template reference.
######################################################################

sub HMCCU_FindDefaults ($$)
{
	my ($hash, $common) = @_;
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
	
	$hash->{hmccu}{semDefaults} = 1;
	foreach my $a (keys %{$template}) {
		next if ($a =~ /^_/);
		my $v = $template->{$a};
		CommandAttr (undef, "$name $a $v");
	}
	$hash->{hmccu}{semDefaults} = 0;
}

######################################################################
# Set default attributes
######################################################################

sub HMCCU_SetDefaults ($)
{
	my ($hash) = @_;

	# Set type specific attributes	
	my $template = HMCCU_FindDefaults ($hash, 0) // return 0;
	
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
			my $template = HMCCU_FindDefaults ($hash, 0);
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

	return if (AttrVal ($name, 'disable', 0) == 1);
		
	my $events = deviceEvents ($devhash, 1);
	return if (!$events);
	
	# Process events
	foreach my $event (@{$events}) {	
		if ($devname eq 'global') {
			# Global event
			if ($event eq 'INITIALIZED') {
				# FHEM initialized. Schedule post initialization tasks
				my $delay = $hash->{ccustate} eq 'active' && $hash->{hmccu}{ccu}{delayed} == 0 ?
					$HMCCU_INIT_INTERVAL0 : $hash->{hmccu}{ccu}{delay}+$HMCCU_CCU_RPC_OFFSET;
				HMCCU_Log ($hash, 0, "Scheduling post FHEM initialization tasks in $delay seconds");
				InternalTimer (gettimeofday()+$delay, "HMCCU_PostInit", $hash, 0);
			}
			elsif ($event =~ /^(ATTR|DELETEATTR)/ && $init_done) {
				# Attribute of client device set or deleted
				my $refreshAttrList = 'ccucalculate|ccuflags|ccureadingfilter|ccureadingformat|'.
					'ccureadingname|ccuReadingPrefix|ccuscaleval|controldatapoint|hmstatevals|'.
					'statedatapoint|statevals|substitute:textField-long|substexcl|stripnumber';
				my $cmdAttrList = 'statechannel|statedatapoint|controlchannel|controldatapoint';

				my ($aCmd, $aDev, $aAtt, $aVal) = split (/\s+/, $event);
				$aAtt = $aVal if ($aCmd eq 'DELETEATTR');
				if (defined($aAtt)) {
					my $clHash = $defs{$aDev};
					if (defined($clHash->{TYPE}) && ($clHash->{TYPE} eq 'HMCCUCHN' || $clHash->{TYPE} eq 'HMCCUDEV')) {
						if ($aAtt =~ /^($cmdAttrList)$/) {
							my ($sc, $sd, $cc, $cd, $sdCnt, $cdCnt) = HMCCU_GetSCDatapoints ($hash);
							if ($cdCnt < 2) {
								HMCCU_UpdateRoleCommands ($hash, $clHash, $cc);
								HMCCU_UpdateAdditionalCommands ($hash, $clHash, $cc, $cd);
							}
						}
						if ($aAtt =~ /^($refreshAttrList)$/i) {
							HMCCU_RefreshReadings ($clHash);
						}
					}
				}
			}
		}
		else {
			# Reading updated
			return if ($devtype ne 'HMCCUDEV' && $devtype ne 'HMCCUCHN');
			my ($r, $v) = split (": ", $event);
			return if (!defined($v) || HMCCU_IsFlag ($name, 'noagg'));

			foreach my $rule (keys %{$hash->{hmccu}{agg}}) {
				my $ftype = $hash->{hmccu}{agg}{$rule}{ftype};
				my $fexpr = $hash->{hmccu}{agg}{$rule}{fexpr};
				my $fread = $hash->{hmccu}{agg}{$rule}{fread};
				next if ($r !~ $fread ||
					($ftype eq 'name' && $devname !~ /$fexpr/) ||
					($ftype eq 'type' && $devhash->{ccutype} !~ /$fexpr/) ||
					($ftype eq 'group' && AttrVal ($devname, 'group', 'null') !~ /$fexpr/) ||
					($ftype eq 'room' && AttrVal ($devname, 'room', 'null') !~ /$fexpr/) ||
					($ftype eq 'alias' && AttrVal ($devname, 'alias', 'null') !~ /$fexpr/));
			
				HMCCU_AggregateReadings ($hash, $rule);
			}
		}
	}

	return;
}

######################################################################
# Enhance device details in FHEM web view
######################################################################

sub HMCCU_Detail ($$$$)
{
	my ($FW_Name, $Device, $Room, $pageHash) = @_;
	my $hash = $defs{$Device};

	return defined($hash->{host}) ? qq(
<span class='mkTitle'>CCU Administration</span>
<table class="block wide">
<tr class="odd">
<td><div class="col1">
&gt; <a target="_blank" href="$hash->{prot}://$hash->{host}">CCU WebUI</a>
</div></td>
</tr>
<tr class="odd">
<td><div class="col1">
&gt; <a target="_blank" href="$hash->{prot}://$hash->{host}/addons/cuxd/index.ccc">CUxD Config</a>
</div></td>
</tr>
</table>
	) : '';
}

######################################################################
# Calculate reading aggregations.
# Called by Notify or via command get aggregation.
######################################################################

sub HMCCU_AggregateReadings ($$)
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

	# Shutdown RPC server
	HMCCU_Shutdown ($hash);

	# Delete reference to IO module in client devices
	my @keylist = keys %defs;
	foreach my $d (@keylist) {
		my $ch = $defs{$d} // next;
		if (exists ($ch->{TYPE}) && $ch->{TYPE} =~ /^(HMCCUDEV|HMCCUCHN|HMCCURPCPROC)$/ &&
			exists($ch->{IODev}) && $ch->{IODev} == $hash) {
        	delete $defs{$d}{IODev};
		}
	}

	return undef;
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
		"importdefaults rpcregister:all rpcserver:on,off ackmessages:noArg authentication ".
		"prgActivate prgDeactivate on:noArg off:noArg";
	$opt = lc($opt);
	
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
	my @ifList = keys %$interfaces;
	if (scalar(@ifList) > 0) {
		my $ifStr = join(',', @ifList);
		$options =~ s/rpcregister:all/rpcregister:all,$ifStr/;
	}
	my $host = $hash->{host};

	$options = 'initialize:noArg' if (exists($hash->{hmccu}{ccu}{delayed}) &&
		$hash->{hmccu}{ccu}{delayed} == 1 && $hash->{ccustate} eq 'unreachable');
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
		my $username = shift @$a;
		my $password = shift @$a;
		$usage = "set $name $opt username password";

		if (!defined($username)) {
			setKeyValue ($name."_username", undef);
			setKeyValue ($name."_password", undef);
			return 'Credentials for CCU authentication deleted';
		}		
		return HMCCU_SetError ($hash, $usage) if (!defined($password));

		my $encuser = HMCCU_Encrypt ($username);
		my $encpass = HMCCU_Encrypt ($password);
		return HMCCU_SetError ($hash, 'Encryption of credentials failed') if ($encuser eq '' || $encpass eq '');
		
		my $err = setKeyValue ($name."_username", $encuser);
		return HMCCU_SetError ($hash, "Can't store credentials. $err") if (defined ($err));
		$err = setKeyValue ($name."_password", $encpass);
		return HMCCU_SetError ($hash, "Can't store credentials. $err") if (defined ($err));
		
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
						if ($t1 !~ /^[0-9]+$/ || $t1 > $dh->{channels});
					$adr = $dh->{ccuaddr};
					$chn = $t1;
					$dpt = $t2;
				}
				else {
					return HMCCU_SetError ($hash, "FHEM device $devName has illegal type");
				}

				return HMCCU_SetError ($hash, "Invalid datapoint $dpt specified for device $devName")
					if (!HMCCU_IsValidDatapoint ($dh, $dh->{ccutype}, $chn, $dpt, 2));
				
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
		my %objects = ();
		my $objcount = 0;
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
			my @tokens = split /=/, $line;
			next if (@tokens != 2);
			my $reading;
			my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hash, $tokens[0],
				$HMCCU_FLAG_INTERFACE);
			($add, $chn) = HMCCU_GetAddress ($hash, $nam) if ($flags == $HMCCU_FLAGS_NCD);
			
			if ($flags == $HMCCU_FLAGS_IACD || $flags == $HMCCU_FLAGS_NCD) {
				$objects{$add}{$chn}{VALUES}{$dpt} = $tokens[1];
				$objcount++;
			}
			else {
				# If output is not related to a channel store reading in I/O device
				my $Value = HMCCU_Substitute ($tokens[1], $substitute, 0, undef, $tokens[0]);
				my $rn = HMCCU_CorrectName ($tokens[0]);
				readingsSingleUpdate ($hash, $rn, $Value, 1);
			}
		}
		
		HMCCU_UpdateMultipleDevices ($hash, \%objects) if ($objcount > 0);

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

	my $options = "create createDev defaults:noArg exportDefaults dutycycle:noArg vars update".
		" updateCCU paramsetDesc firmware rpcEvents:noArg rpcState:noArg deviceInfo".
		" ccuMsg:alarm,service ccuConfig:noArg ccuDevices:noArg".
		" internal:groups,interfaces";
	if (defined($hash->{hmccu}{ccuSuppDevList}) && $hash->{hmccu}{ccuSuppDevList} ne '') {
		$options =~ s/createDev/createDev:$hash->{hmccu}{ccuSuppDevList}/;
	}
	if (defined($hash->{hmccu}{ccuDevList}) && $hash->{hmccu}{ccuDevList} ne '') {
		$options =~ s/deviceInfo/deviceInfo:$hash->{hmccu}{ccuDevList}/;
		$options =~ s/paramsetDesc/paramsetDesc:$hash->{hmccu}{ccuDevList}/;
	}
	my $usage = "HMCCU: Unknown argument $opt, choose one of $options";

	return undef if ($hash->{hmccu}{ccu}{delayed} || $hash->{ccustate} ne 'active');
	return 'HMCCU: CCU busy, choose one of rpcstate:noArg'
		if ($opt ne 'rpcstate' && HMCCU_IsRPCStateBlocking ($hash));

	my $ccuflags = HMCCU_GetFlags ($name);
	my $ccureadings = AttrVal ($name, "ccureadings", $ccuflags =~ /noReadings/ ? 0 : 1);

	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
	my @ifList = keys %$interfaces;

	my $readname;
	my $readaddr;
	my $result = '';
	my $rc;
	
	if ($opt eq 'vars') {
		my $varname = shift @$a // return HMCCU_SetError ($hash, "Usage: get $name vars {regexp}[,...]");
		($rc, $result) = HMCCU_GetVariables ($hash, $varname);
		return HMCCU_SetError ($hash, $rc, $result) if ($rc < 0);
		return HMCCU_SetState ($hash, 'OK', $result);
	}
	elsif ($opt eq 'update' || $opt eq 'updateccu') {
		my $devexp = shift @$a // '.*';
		my $ccuget = shift @$a // 'Attr';
		return HMCCU_SetError ($hash, "Usage: get $name $opt [device-expr [{'State'|'Value'}]]")
			if ($ccuget !~ /^(Attr|State|Value)$/);
		HMCCU_UpdateClients ($hash, $devexp, $ccuget, ($opt eq 'updateccu') ? 1 : 0);
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
		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hash, $device,
			$HMCCU_FLAG_FULLADDR);
		return HMCCU_SetError ($hash, -1, $device) if (!($flags & $HMCCU_FLAG_ADDRESS));
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
	elsif ($opt eq 'firmware') {
		my $devtype = shift @$a // '.*';
		my $dtexp = $devtype eq 'full' ? '.*' : $devtype;
		my $dc = HMCCU_GetFirmwareVersions ($hash, $dtexp);
		return 'Found no firmware downloads' if ($dc == 0);
		$result = "Found $dc firmware downloads. Click on the new version number for download\n\n";
		if ($devtype eq 'full') {
			$result .= "Type                 Available Date\n".('-' x 41)."\n";
			foreach my $ct (keys %{$hash->{hmccu}{type}}) {
				$result .= sprintf "%-20s <a href=\"http://www.eq-3.de/%s\">%-9s</a> %-10s\n",
					$ct, $hash->{hmccu}{type}{$ct}{download},
					$hash->{hmccu}{type}{$ct}{firmware}, $hash->{hmccu}{type}{$ct}{date};
			}
		}
		else {
			my @devlist = HMCCU_FindClientDevices ($hash, "(HMCCUDEV|HMCCUCHN)");
			return $result if (scalar (@devlist) == 0);
			$result .= 
				"Device                    Type                 Current Available Date\n".('-' x 76)."\n";
			foreach my $dev (@devlist) {
				my $ch = $defs{$dev};
				my $ct = uc($ch->{ccutype});
				my $fw = $ch->{firmware} // 'N/A';
				next if (!exists ($hash->{hmccu}{type}{$ct}) || $ct !~ /$dtexp/);
				$result .= sprintf "%-25s %-20s %-7s <a href=\"http://www.eq-3.de/%s\">%-9s</a> %-10s\n",
					$ch->{NAME}, $ct, $fw, $hash->{hmccu}{type}{$ct}{download},
					$hash->{hmccu}{type}{$ct}{firmware}, $hash->{hmccu}{type}{$ct}{date};
			}
		}
				
		return HMCCU_SetState ($hash, 'OK', $result);
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
				my $rc = HMCCU_AggregateReadings ($hash, $r);
				$result .= "$r = $rc\n";
			}
		}
		else {
			return HMCCU_SetError ($hash, "HMCCU: Aggregation rule $rule does not exist")
				if (!exists($hash->{hmccu}{agg}{$rule}));
			$result = HMCCU_AggregateReadings ($hash, $rule);
			$result = "$rule = $result";			
		}

		return HMCCU_SetState ($hash, 'OK', $ccureadings ? undef : $result);
	}
	elsif ($opt eq 'paramsetdesc') {
		$usage = "Usage: get $name $opt {device|channel}";
		my $ccuobj = shift @$a // return HMCCU_SetError ($hash, $usage);
		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hash, $ccuobj,
			$HMCCU_FLAG_FULLADDR);
		return HMCCU_SetError ($hash, 'Invalid device or address')
			if (!($flags & $HMCCU_FLAG_ADDRESS));
		$result = HMCCU_ParamsetDescToStr ($hash, $add);
		return defined($result) ? $result : HMCCU_SetError ($hash, "Can't get device description");
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
# Parse CCU object specification.
#
# Supported address types:
#   Classic Homematic and Homematic-IP addresses.
#   Team addresses with leading * for BidCos-RF.
#   CCU virtual remote addresses (BidCoS:ChnNo)
#   OSRAM lightify addresses (OL-...)
#   Homematic virtual layer addresses (if known by HMCCU)
#
# Possible syntax for datapoints:
#   Interface.Address:Channel.Datapoint
#   Address:Channel.Datapoint
#   Channelname.Datapoint
#
# Possible syntax for channels:
#   Interface.Address:Channel
#   Address:Channel
#   Channelname
#
# If object name doesn't match the rules above it's treated as name.
# With parameter flags one can specify if result is filled up with
# default values for interface or datapoint.
#
# Return list of detected attributes (empty string if attribute is
# not detected):
#   (Interface, Address, Channel, Datapoint, Name, Flags)
#   Flags is a bitmask of detected attributes.
######################################################################

sub HMCCU_ParseObject ($$$)
{
	my ($hash, $object, $flags) = @_;
	my ($i, $a, $c, $d, $n, $f) = ('', '', '', '', '', '', 0);
	my $extaddr;
	
	# "ccu:" is default. Remove it.
	$object =~ s/^ccu://g;
	
	# Check for FHEM device
	if ($object =~ /^hmccu:/) {
		my ($hmccu, $fhdev, $fhcdp) = split(':', $object);
		return ($i, $a, $c, $d, $n, $f) if (!defined ($fhdev));
		my $cl_hash = $defs{$fhdev};
		return ($i, $a, $c, $d, $n, $f) if (!defined ($cl_hash) ||
			($cl_hash->{TYPE} ne 'HMCCUDEV' && $cl_hash->{TYPE} ne 'HMCCUCHN'));
		$object = $cl_hash->{ccuaddr};
		$object .= ":$fhcdp" if (defined ($fhcdp));
	}
	
	# Check if address is already known by HMCCU. Substitute device address by ZZZ0000000
	# to allow external addresses like HVL
	if ($object =~ /^.+\.(.+):[0-9]{1,2}\..+$/ ||
		$object =~ /^.+\.(.+):[0-9]{1,2}$/ ||
		$object =~ /^(.+):[0-9]{1,2}\..+$/ ||
		$object =~ /^(.+):[0-9]{1,2}$/ ||
		$object =~ /^(.+)$/) {
		$extaddr = $1;
		if (!HMCCU_IsDevAddr ($extaddr, 0) &&
			exists ($hash->{hmccu}{dev}{$extaddr}) && $hash->{hmccu}{dev}{$extaddr}{valid}) {
			$object =~ s/$extaddr/$HMCCU_EXT_ADDR/;
		}
	}

	if ($object =~ /^(.+?)\.([\*]*[A-Z]{3}[0-9]{7}):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^(.+?)\.([0-9A-F]{12,14}):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^(.+?)\.(OL-.+):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^(.+?)\.(BidCoS-RF):([0-9]{1,2})\.(.+)$/) {
		#
		# Interface.Address:Channel.Datapoint [30=11110]
		#
		$f = $HMCCU_FLAGS_IACD;
		($i, $a, $c, $d) = ($1, $2, $3, $4);
	}
	elsif ($object =~ /^(.+)\.([\*]*[A-Z]{3}[0-9]{7}):([0-9]{1,2})$/ ||
		$object =~ /^(.+)\.([0-9A-F]{12,14}):([0-9]{1,2})$/ ||
		$object =~ /^(.+)\.(OL-.+):([0-9]{1,2})$/ ||
		$object =~ /^(.+)\.(BidCoS-RF):([0-9]{1,2})$/) {
		#
		# Interface.Address:Channel [26=11010]
		#
		$f = $HMCCU_FLAGS_IAC | ($flags & $HMCCU_FLAG_DATAPOINT);
		($i, $a, $c, $d) = ($1, $2, $3, $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
	}
	elsif ($object =~ /^([\*]*[A-Z]{3}[0-9]{7}):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^([0-9A-F]{12,14}):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^(OL-.+):([0-9]{1,2})\.(.+)$/ ||
		$object =~ /^(BidCoS-RF):([0-9]{1,2})\.(.+)$/) {
		#
		# Address:Channel.Datapoint [14=01110]
		#
		$f = $HMCCU_FLAGS_ACD;
		($a, $c, $d) = ($1, $2, $3);
	}
	elsif ($object =~ /^([\*]*[A-Z]{3}[0-9]{7}):([0-9]{1,2})$/ ||
		$object =~ /^([0-9A-Z]{12,14}):([0-9]{1,2})$/ ||
		$object =~ /^(OL-.+):([0-9]{1,2})$/ ||
		$object =~ /^(BidCoS-RF):([0-9]{1,2})$/) {
		#
		# Address:Channel [10=01010]
		#
		$f = $HMCCU_FLAGS_AC | ($flags & $HMCCU_FLAG_DATAPOINT);
		($a, $c, $d) = ($1, $2, $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
	}
	elsif ($object =~ /^([\*]*[A-Z]{3}[0-9]{7})$/ ||
		$object =~ /^([0-9A-Z]{12,14})$/ ||
		$object =~ /^(OL-.+)$/ ||
		$object eq 'BidCoS') {
		#
		# Address
		#
		$f = $HMCCU_FLAG_ADDRESS;
		$a = $1;
	}
	elsif ($object =~ /^(.+?)\.([A-Z_]+)$/) {
		#
		# Name.Datapoint
		#
		$f = $HMCCU_FLAGS_ND;
		($n, $d) = ($1, $2);
	}
	elsif ($object =~ /^.+$/) {
		#
		# Name [1=00001]
		#
		$f = $HMCCU_FLAG_NAME | ($flags & $HMCCU_FLAG_DATAPOINT);
		($n, $d) = ($object, $flags & $HMCCU_FLAG_DATAPOINT ? '.*' : '');
	}
	else {
		$f = 0;
	}
	
	# Restore external address (i.e. HVL device address)
	$a = $extaddr if ($a eq $HMCCU_EXT_ADDR);

	# Check if name is a valid channel name
	if ($f & $HMCCU_FLAG_NAME) {
		my ($add, $chn) = HMCCU_GetAddress ($hash, $n);
		if ($chn ne '') {
			$f = $f | $HMCCU_FLAG_CHANNEL;
		}
		if ($flags & $HMCCU_FLAG_FULLADDR) {
			($i, $a, $c) = (HMCCU_GetDeviceInterface ($hash, $add), $add, $chn);
			$f |= $HMCCU_FLAG_INTERFACE if ($i ne '');
			$f |= $HMCCU_FLAG_ADDRESS if ($add ne '');
			$f |= $HMCCU_FLAG_CHANNEL if ($chn ne '');
		}
	}
	elsif ($f & $HMCCU_FLAG_ADDRESS && $i eq '' &&
	   ($flags & $HMCCU_FLAG_FULLADDR || $flags & $HMCCU_FLAG_INTERFACE)) {
		$i = HMCCU_GetDeviceInterface ($hash, $a);
		$f |= $HMCCU_FLAG_INTERFACE if ($i ne '');
	}

	return ($i, $a, $c, $d, $n, $f);
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
	my $rf = AttrVal ($name, 'ccureadingfilter', '.*');

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
					($cn eq '' && $c eq '') ||
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
#   Interface,Address,ChannelNo,Datapoint,ChannelNam,Format,Paramset
#   Format := { name[lc] | datapoint[lc] | address[lc] | formatStr }
#   formatStr := Any text containing at least one format pattern
#   pattern := { %a, %c, %n, %d, %A, %C, %N, %D }
#
# Valid combinations:
#
#   ChannelName,Datapoint
#   Address,Datapoint
#   Address,ChannelNo,Datapoint
#
# Reading names can be modified or new readings can be added by
# setting attribut ccureadingname.
# Returns list of readings names. Return empty list on error.
######################################################################

sub HMCCU_GetReadingName ($$$$$$$;$)
{
	my ($hash, $i, $a, $c, $d, $n, $rf, $ps) = @_;
	$c //= '';
	$i //= '';
	$ps //= 'VALUES';
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	
	my %prefix = ( 'MASTER' => 'R-', 'LINK' => 'L-', 'VALUES' => '', 'SERVICE' => 'S-',
		'PEER' => 'P-', 'DEVICE' => 'R-' );

	my $ioHash = HMCCU_GetHash ($hash);
	return () if (!defined($ioHash) || !defined($d) || $d eq '');

	my @rcv = ();
	if ($ps =~ /^LINK\.(.+)$/) {
		@rcv = HMCCU_GetDeviceIdentifier ($ioHash, $1);
		$ps = 'LINK';
	}

	my $rn = '';
	my @rnlist;

	$rf //= HMCCU_GetAttrReadingFormat ($hash, $ioHash);

	my @srl = ();
	my $crn = AttrVal ($name, 'ccureadingname', '');
	push @srl, $crn if ($crn ne '');
	if ((exists($hash->{hmccu}{control}{chn}) && "$c" eq $hash->{hmccu}{control}{chn}) ||
		(exists($hash->{hmccu}{state}{chn}) && "$c" eq $hash->{hmccu}{state}{chn})) {
		my $role = HMCCU_GetChannelRole ($hash, $c);
		if ($role ne '' && exists($HMCCU_READINGS->{$role})) {
			$crn = $HMCCU_READINGS->{$role};
			$crn =~ s/C#\./$c\./g;
			push @srl, $crn;
		}
	}
	my $sr = join (';', @srl);
	
	HMCCU_Trace ($hash, 2, "sr=$sr");
	
	# Complete missing values
	if ($n eq '' && $a ne '') {
		$n = ($c ne '') ?
			HMCCU_GetChannelName ($ioHash, $a.':'.$c) :
			HMCCU_GetDeviceName ($ioHash, $a);
	}
	elsif ($n ne '' && $a eq '') {
		($a, $c) = HMCCU_GetAddress ($ioHash, $n);
	}
	if ($i eq '' && $a ne '') {
		$i = HMCCU_GetDeviceInterface ($ioHash, $a);
	}

	# Get reading prefix definitions
	$ps = 'DEVICE' if (($c eq '0' && $ps eq 'MASTER') || $c eq 'd');
	my $readingPrefix = HMCCU_GetAttribute ($ioHash, $hash, 'ccuReadingPrefix', '');
	foreach my $pd (split (',', $readingPrefix)) {
		my ($rSet, $rPre) = split (':', $pd);
		$prefix{$rSet} = $rPre if (defined($rPre) && exists($prefix{$rSet}));
	}
	my $rpf = exists($prefix{$ps}) ? $prefix{$ps} : '';
			
	if ($rf =~ /^datapoint(lc|uc)?$/) {
		$rn = $c ne '' && $c ne 'd' && $type ne 'HMCCUCHN' ? $c.'.'.$d : $d;
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
	
	if (scalar (@rcv) > 0) {
		push (@rnlist, map { $rpf.$_.'-'.$rn } @rcv);
	}
	else {
		push (@rnlist, $rpf.$rn);
	}
	
	# Rename and/or add reading names
	my @rules = split (';', $sr);
	foreach my $rr (@rules) {
		my ($rold, $rnew) = split (':', $rr);
		next if (!defined ($rnew));
		my @rnewList = split (',', $rnew);
		next if (scalar (@rnewList) < 1);
		if ($rnlist[0] =~ /$rold/) {
			foreach my $rnew (@rnewList) {
				if ($rnew =~ /^\+(.+)$/) {
					my $radd = $1;
					$radd =~ s/$rold/$radd/;
					push (@rnlist, $radd);
				}
				else {
					$rnlist[0] =~ s/$rold/$rnew/;
					last;
				}
			}
		}
	}
	
	# Convert to lower or upper case
	$rnlist[0] = lc($rnlist[0]) if ($rf =~ /^(datapoint|name|address)lc$/);
	$rnlist[0] = uc($rnlist[0]) if ($rf =~ /^(datapoint|name|address)uc$/);

	# Return array of corrected reading names
	return HMCCU_Unique (map { HMCCU_CorrectName ($_) } @rnlist);
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
	
	if (exists($hash->{CL}) && $init_done) {
		my $devType = $hash->{TYPE} // '';
		my $devName = defined($hash->{NAME}) ? " [$hash->{NAME}]" : '';
		asyncOutput ($hash->{CL}, "$devType $devName $msg");
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
	if (defined($hash) && HMCCU_IsFlag ($hash, 'logEnhanced')) {
		$type .= ":$cl";
		$name .= " : $pid";
	}
	my $logname = exists($defs{$name}) ? $name : undef;

	if (ref($msg) eq 'ARRAY') {
		foreach my $m (@$msg) {
			Log3 $logname, $level, "$type [$name] $m";
		}
	}
	else {
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
	my %errlist = (
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
	   -21 => 'Device disabled'
	);

	if ($text ne 'OK' && $text ne '0') {
		$msg = exists($errlist{$text}) ? $errlist{$text} : $text;
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
		my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
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
			HMCCU_UpdateClients ($hash, '.*', 'Value', 0, $filter, 1)
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
			my ($r, $f) = split (':', $ruletoks[0], 2);
			if (!defined($f)) {
				$f = $r;
				$r = undef;
			}
			if (!defined($r) || (defined($type) && $r eq $type)) {
				my @dptlist = split (',', $f);
				foreach my $d (@dptlist) {
					my $c = -1;
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
			return $value if ($value !~ /^[+-]?\d+$/ && $value =~ /^[+-]?\d*\.?\d+(?:(?:e|E)\d+)?$/);
			($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[0], $mode);
			return $newvalue if ($rc == 1);
		}
	}

	# Original value not modified by rules. Use default conversion depending on type/role
	# Default conversion can be overriden by attribute ccudef-substitute in I/O device

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
	
	# Substitute enumerations
	if (defined($devDesc) && defined($ioHash)) {
		my $paramDef = HMCCU_GetParamDef ($ioHash, $devDesc, 'VALUES', $dpt);
		if (!defined($paramDef) && defined($paramDef->{TYPE}) &&
			$paramDef->{TYPE} eq 'ENUM' && defined($paramDef->{VALUE_LIST})) {
			my $i = defined($paramDef->{MIN}) ? $paramDef->{MIN} : 0;
			if ($mode) {
				my %enumVals = map { $_ => $i++ } split(',', $paramDef->{VALUE_LIST});
				return $enumVals{$value} if (exists($enumVals{$value}));
			}
			else {
				my @enumList = split(',', $paramDef->{VALUE_LIST});
				my $idx = $value-$i;
				return $enumList[$idx] if ($idx >= 0 && $idx < scalar(@enumList));
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
	
	my @sub_list = split /[, ]/,$substitutes;
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
			$text =~ s/$dp/$clhash->{hmccu}{dp}{$dp}{VALUES}{VAL}/g;
		}
	}

	HMCCU_Trace ($clhash, 2, "text=$text");
	
	return $text;
}

######################################################################
# Update all datapoint/readings of all client devices matching
# specified regular expression. Update will fail if device is deleted
# or disabled or if ccuflag noReadings is set.
# If fromccu is 1 regular expression is compared to CCU device name.
# Otherwise it's compared to FHEM device name. If ifname is specified
# only devices belonging to interface ifname are updated.
######################################################################

sub HMCCU_UpdateClients ($$$$;$$)
{
	my ($hash, $devexp, $ccuget, $fromccu, $ifname, $nonBlock) = @_;
	my $fhname = $hash->{NAME};
	$nonBlock //= HMCCU_IsFlag ($fhname, 'nonBlocking');
	my $c = 0;
	my $dc = 0;
	my $filter = 'ccudevstate=active';
	$filter .= ",ccuif=$ifname" if (defined($ifname));
	$ccuget = AttrVal ($fhname, 'ccuget', 'Value') if ($ccuget eq 'Attr');
	my $list = '';

	if ($fromccu) {
		foreach my $name (sort keys %{$hash->{hmccu}{adr}}) {
			next if ($name !~ /$devexp/ || !($hash->{hmccu}{adr}{$name}{valid}));

			my @devlist = HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN)', undef, $filter);	
			$dc += scalar(@devlist);
			foreach my $d (@devlist) {
				my $ch = $defs{$d};
				next if (!defined($ch->{IODev}) || !defined($ch->{ccuaddr}) ||
					$ch->{ccuaddr} ne $hash->{hmccu}{adr}{$name}{address} ||
					!HMCCU_IsValidDeviceOrChannel ($hash, $ch->{ccuaddr}, $HMCCU_FL_ADDRESS));
				$list .= ($list eq '') ? $name : ",$name";
				$c++;
			}
		}
	}
	else {
		my @devlist = HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN)', $devexp, $filter);
		$dc = scalar(@devlist);
		foreach my $d (@devlist) {
			my $ch = $defs{$d};
			next if (!defined($ch->{IODev}) || !defined($ch->{ccuaddr}) ||			
				!HMCCU_IsValidDeviceOrChannel ($hash, $ch->{ccuaddr}, $HMCCU_FL_ADDRESS));
			my $name = HMCCU_GetDeviceName ($hash, $ch->{ccuaddr});
			next if ($name eq '');
			$list .= ($list eq '') ? $name : ",$name";
			$c++;
		}
	}

	return HMCCU_Log ($hash, 2, 'Found no devices to update') if ($c == 0);
	HMCCU_Log ($hash, 2, "Updating $c of $dc client devices matching devexp=$devexp filter=$filter");
	
	if ($nonBlock) {
		HMCCU_HMScriptExt ($hash, '!GetDatapointsByDevice', { list => $list, ccuget => $ccuget },
			\&HMCCU_UpdateCB, { logCount => 1, devCount => $c });
		return 1;
	}
	else {
		my $response = HMCCU_HMScriptExt ($hash, '!GetDatapointsByDevice',
			{ list => $list, ccuget => $ccuget });
		return -2 if ($response eq '' || $response =~ /^ERROR:.*/);

		HMCCU_UpdateCB ({ ioHash => $hash, logCount => 1, devCount => $c }, undef, $response);
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

	HMCCU_Log ($hash, 2, "Updating device table");
	
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
	if ($hash->{hmccu}{ccu}{delayed} == 1) {			
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

			if ($hash->{hmccu}{device}{$iface}{$address}{_model} =~ /^(HM-RCV-50|HmIP-RCV-50)$/) {
				$cs{notSupported}{$ccuName} = "$address [$ccuName]";
				next;
			}
			
			# Detect FHEM device type
			my $detect = HMCCU_DetectDevice ($hash, $address, $iface);
			if (!defined($detect) || $detect->{level} == 0) {		
				$cs{notDetected}{$ccuName} = "$address [$ccuName]";
				next;
			}

			my $defMod = $detect->{defMod};
			my $defAdd = $detect->{defAdd};

			# Build FHEM device name
			my $devName = HMCCU_MakeDeviceName ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuName);

			if ($detect->{level} == 1) {
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
	my $cmd = "$devName $defMod $defAdd";
	$cmd .= " $defOpts" if (defined($defOpts) && $defOpts ne '');
	my $ret = CommandDefine (undef, $cmd);
	if ($ret) {
		HMCCU_Log ($hash, 2, "Define command failed $cmd. $ret");
		$cs->{defFailed}{$devName} = "$defAdd [$ccuName]";
		return 0;
	}
	else {
		$cs->{defSuccess}{$devName} = "$defAdd [$ccuName]";

		# Set device attributes
		HMCCU_SetInitialAttributes ($hash, $devName);
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
# Create device name
######################################################################

sub HMCCU_MakeDeviceName ($$$$$)
{
	my ($defAdd, $devPrefix, $devFormat, $devSuffix, $ccuName) = @_;

	my $devName = $devPrefix.$devFormat.$devSuffix;
	$devName =~ s/%n/$ccuName/g;
	$devName =~ s/%a/$defAdd/g;
	$devName =~ s/[^A-Za-z\d_\. ]+/_/g;

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

	# if (exists($ioHash->{hmccu}{snd}{$iface}{$da})) {
	# 	delete $clHash->{sender} if (exists($clHash->{sender}));
	# 	delete $clHash->{receiver} if (exists($clHash->{receiver}));
	# 	my @rcvList = ();
	# 	my @sndList = ();
		
	# 	foreach my $c (sort keys %{$ioHash->{hmccu}{snd}{$iface}{$da}}) {
	# 		next if ($clType eq 'HMCCUCHN' && "$c" ne "$dc");
	# 		foreach my $r (keys %{$ioHash->{hmccu}{snd}{$iface}{$da}{$c}}) {
	# 			my ($la, $lc) = HMCCU_SplitChnAddr ($r);
	# 			next if ($la eq $da);	# Ignore link if receiver = current device
	# 			my @rcvNames = HMCCU_GetDeviceIdentifier ($ioHash, $r, $iface);
	# 			my $rcvFlags = HMCCU_FlagsToStr ('peer', 'FLAGS',
	# 				$ioHash->{hmccu}{snd}{$iface}{$da}{$c}{$r}{FLAGS}, ',');
	# 			push @rcvList, map { $_.($rcvFlags ne 'OK' ? " [".$rcvFlags."]" : '') } @rcvNames;	
	# 		}
	# 	}

	# 	foreach my $c (sort keys %{$ioHash->{hmccu}{rcv}{$iface}{$da}}) {
	# 		next if ($clType eq 'HMCCUCHN' && "$c" ne "$dc");
	# 		foreach my $s (keys %{$ioHash->{hmccu}{rcv}{$iface}{$da}{$c}}) {
	# 			my ($la, $lc) = HMCCU_SplitChnAddr ($s);
	# 			next if ($la eq $da);	# Ignore link if sender = current device
	# 			my @sndNames = HMCCU_GetDeviceIdentifier ($ioHash, $s, $iface);
	# 			my $sndFlags = HMCCU_FlagsToStr ('peer', 'FLAGS',
	# 				$ioHash->{hmccu}{snd}{$iface}{$da}{$c}{$s}{FLAGS}, ',');
	# 			push @sndList, map { $_.($sndFlags ne 'OK' ? " [".$sndFlags."]" : '') } @sndNames; 
	# 		}
	# 	}

	# 	$clHash->{sender} = join (',', @sndList) if (scalar(@sndList) > 0);
	# 	$clHash->{receiver} = join (',', @rcvList) if (scalar(@rcvList) > 0);
	# }
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
#		$clHash->{ccurole} = $dd->{TYPE};
		$clHash->{hmccu}{role} = $dd->{INDEX}.':'.$dd->{TYPE};
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
		my @devList = grep { $_ ne $oldName } split(',', $ioHash->{hmccu}{device}{$iface}{$address}{_fhem});
		push @devList, $name;
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
	$detect //= HMCCU_DetectDevice ($ioHash, $ccuAddr, $ccuIf);

	# Get readable and writeable datapoints
	my @dpWrite = ();
	my @dpRead = ();
	my ($da, $dc) = HMCCU_SplitChnAddr ($ccuAddr, -2);
	my $dpWriteCnt = HMCCU_GetValidDatapoints ($clHash, $ccuType, $dc, 2, \@dpWrite);
	my $dpReadCnt  = HMCCU_GetValidDatapoints ($clHash, $ccuType, $dc, 5, \@dpRead);

	# Detect device and initialize attribute lists for statedatapoint and controldatapoint
	my @userattr = grep (!/statedatapoint|controldatapoint/, split(' ', $modules{$clHash->{TYPE}}{AttrList}));
	if (defined($detect) && $detect->{level} > 0) {
		if ($type eq 'HMCCUDEV') {
			push @userattr, 'statedatapoint:select,'.
				join(',', sort map { $_.'.'.$detect->{stateRole}{$_}{datapoint} } keys %{$detect->{stateRole}})
					if ($detect->{stateRoleCount} > 0);
			push @userattr, 'controldatapoint:select,'.
				join(',', sort map { $_.'.'.$detect->{controlRole}{$_}{datapoint} } keys %{$detect->{controlRole}})
					if ($detect->{controlRoleCount} > 0);
		}
		elsif ($type eq 'HMCCUCHN') {
			push @userattr, 'statedatapoint:select,'.
				join(',', sort map { $detect->{stateRole}{$_}{datapoint} } keys %{$detect->{stateRole}})
					if ($detect->{stateRoleCount} > 0);
			push @userattr, 'controldatapoint:select,'.
				join(',', sort map { $detect->{controlRole}{$_}{datapoint} } keys %{$detect->{controlRole}})
					if ($detect->{controlRoleCount} > 0);
		}
	}
	else {
		push @userattr, 'statedatapoint:select,'.join(',', sort @dpRead) if ($dpReadCnt > 0);
		push @userattr, 'controldatapoint:select,'.join(',', sort @dpWrite) if ($dpWriteCnt > 0);
	}
	
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
	
	my $interfaces = HMCCU_GetRPCInterfaceList ($ioHash, 1);
	foreach my $iface (keys %$interfaces) {
		my ($rpcdev, $save) = HMCCU_GetRPCDevice ($ioHash, 1, $iface);
		if ($rpcdev ne '') {
			my $rpcHash = $defs{$rpcdev};
			HMCCU_Log ($ioHash, 2, "Reading Device Descriptions for interface $iface");
			$c = HMCCURPCPROC_GetDeviceDesc ($rpcHash);
			HMCCU_Log ($ioHash, 2, "Read $c Device Descriptions for interface $iface");
			$cDev += $c;
			HMCCU_Log ($ioHash, 2, "Reading Paramset Descriptions for interface $iface");
			$c = HMCCURPCPROC_GetParamsetDesc ($rpcHash);
			HMCCU_Log ($ioHash, 2, "Read $c Paramset Descriptions for interface $iface");
			$cPar += $c;
			HMCCU_Log ($ioHash, 2, "Reading Peer Descriptions for interface $iface");
			$c = HMCCURPCPROC_GetPeers ($rpcHash);
			HMCCU_Log ($ioHash, 2, "Read $c Peer Descriptions for interface $iface");
			$cLnk += $c;
		}
		else {
			HMCCU_Log ($ioHash, 2, "No RPC device found for interface $iface. Can't read device config.");
		}
	}

	my @ccuDevList = ();
	my @ccuSuppDevList = ();
	my @ccuSuppTypes = ();
	my @ccuNotSuppTypes = ();
	foreach my $di (sort keys %{$ioHash->{hmccu}{device}}) {
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
			if (defined($detect) && $da ne 'HmIP-RCV-1' && $da ne 'BidCoS-RF') {
				push @ccuSuppDevList, $devName;
				push @ccuSuppTypes, $devModel;
			}
			else {
				push @ccuNotSuppTypes, $devModel;
			}
		}
	}
	$ioHash->{hmccu}{ccuDevList} = join(',', sort @ccuDevList);
	$ioHash->{hmccu}{ccuSuppDevList} = join(',', sort @ccuSuppDevList);
	$ioHash->{hmccu}{ccuTypes}{supported} = join(',', sort @ccuSuppTypes);
	$ioHash->{hmccu}{ccuTypes}{unsupported} = join(',', sort @ccuNotSuppTypes);
	
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
		
		HMCCU_SetSCAttributes ($ioHash, $clHash);
		HMCCU_UpdateDevice ($ioHash, $clHash);
		HMCCU_UpdateDeviceRoles ($ioHash, $clHash);

		my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);

		HMCCU_UpdateRoleCommands ($ioHash, $clHash, $cc);
		HMCCU_UpdateAdditionalCommands ($ioHash, $clHash, $cc, $cd);
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
	
	foreach my $c (@chnList) {
		$result .= $c eq 'd' ? "Device<br/>" : "Channel $c<br/>";
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

sub HMCCU_CloneDeviceModel ($$$$$)
{
# 	if (HMCCU_ExistsDeviceModel ($hash, $type, $fw_ver)) {
# 	}
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
						$hash->{hmccu}{model}{$type}{$fw_ver}{$chnNo}{$paramset}{$p}{$a}{$s} = join(',', @{$desc->{$p}{$a}{$s}});
					}
					else {
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
	
	if (defined($chnNo)) {
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
# Check if parameter exists
# Parameters:
#   $clHash - Hash reference of client device.
#   $object - Device or channel address or device description
#      reference.
#   $ps - Parameter set name.
#   $parameter - Parameter name.
# Returns 0 or 1
######################################################################

sub HMCCU_IsValidParameter ($$$$;$)
{
	my ($clHash, $object, $ps, $parameter, $oper) = @_;

	$oper //= 7;
	my $ioHash = HMCCU_GetHash ($clHash) // return 0;
	
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
# Convert parameter value
# Parameters:
#  $hash - Hash reference of IO device.
#  $object - Device/channel address or device description reference.
#  $paramset - Parameter set.
#  $parameter - Parameter name.
#  $value - Parameter value.
# Return converted or original value.
######################################################################

sub HMCCU_GetParamValueConversion ($$$$$)
{
	my ($hash, $object, $paramset, $parameter, $value) = @_;
	
	# Conversion table
	my %ct = (
		'BOOL' => { 0 => 'false', 1 => 'true' }
	);
	
	return $value if (!defined($object));
	
	$paramset = 'LINK' if ($paramset =~ /^LINK\..+$/);
	my $paramDef = HMCCU_GetParamDef ($hash, $object, $paramset, $parameter) // return $value;
	my $type = $paramDef->{TYPE} // return $value;

	return $ct{$type}{$value} if (exists($ct{$type}) && exists($ct{$type}{$value}));

	if ($type eq 'ENUM' && exists($paramDef->{VALUE_LIST})) {
		my @vl = split(',', $paramDef->{VALUE_LIST});
		return $vl[$value] if ($value =~ /^[0-9]+$/ && $value < scalar(@vl));
	}
	
	return $value;
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
	my ($ioHash, $clHash, $objects, $addListRef) = @_;
	
	my $ioName = $ioHash->{NAME};
	my $clName = $clHash->{NAME};
	my $clType = $clHash->{TYPE};
	
	return undef if (!defined($clHash->{IODev}) || !defined($clHash->{ccuaddr}) ||
		$clHash->{IODev} != $ioHash);

	# Resulting readings
	my %results;
	
	# Updated internal values
	my @chKeys = ();
	
	# Check if update of device allowed
	my $ccuflags = HMCCU_GetFlags ($ioName);
	my $disable = AttrVal ($clName, 'disable', 0);
	my $update = AttrVal ($clName, 'ccureadings', HMCCU_IsFlag ($clName, 'noReadings') ? 0 : 1);
	return undef if ($update == 0 || $disable == 1 || $clHash->{ccudevstate} ne 'active');
	
	# Build list of affected addresses
 	my ($devAddr, $chnNo) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	my @addList = defined ($addListRef) ? @$addListRef : ($devAddr);

	# Determine virtual device flag
	my $vg = ($clHash->{ccuif} eq 'VirtualDevices' && exists($clHash->{ccugroup}) && $clHash->{ccugroup} ne '') ? 1 : 0;

	# Get client device attributes
 	my $clFlags = HMCCU_GetFlags ($clName);
	my $clRF = HMCCU_GetAttrReadingFormat ($clHash, $ioHash);
	my $peer = AttrVal ($clName, 'peer', 'null');
 	my $clInt = $clHash->{ccuif};
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);

#	HMCCU_Trace ($clHash, 2, 'AddList='.join(',', @addList));
#	HMCCU_Trace ($clHash, 2, 'Objects='.Dumper($objects));

	readingsBeginUpdate ($clHash);
	
	# Loop over all addresses
	foreach my $a (@addList) {
		next if (!exists($objects->{$a}));
		
		# Loop over all channels of device, including channel 'd'
		foreach my $c (keys %{$objects->{$a}}) {
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
					my $fv = $v;
					my $cv = $v;
					my $sv;
					
					HMCCU_Trace ($clHash, 2, "ParamsetReading $a.$c.$ps.$p=$v");
					
					# Key for storing values in client device hash. Indirect updates of virtual
					# devices are stored with device address in key.
					my $chKey = $devAddr ne $a ? "$chnAddr.$p" : "$c.$p";

					# Store raw value in client device hash
					HMCCU_UpdateInternalValues ($clHash, $chKey, $ps, 'VAL', $v);

					# Modify value: scale, format, substitute
					$sv = HMCCU_ScaleValue ($clHash, $c, $p, $v, 0);
					HMCCU_UpdateInternalValues ($clHash, $chKey, $ps, 'NVAL', $sv);
					HMCCU_Trace ($clHash, 2, "$p: sv = $sv");
					$fv = HMCCU_FormatReadingValue ($clHash, $sv, $p);
					$cv = HMCCU_Substitute ($fv, $clHash, 0, $c, $p, $chnType, $devDesc);
					$cv = HMCCU_GetParamValueConversion ($ioHash, $devDesc, $ps, $p, $fv)
						if (defined($devDesc) && "$fv" eq "$cv");

					HMCCU_UpdateInternalValues ($clHash, $chKey, $ps, 'SVAL', $cv);
					push @chKeys, $chKey;

					# Update 'state' and 'control'
					HMCCU_BulkUpdate ($clHash, 'control', $fv, $cv)
						if ($cd ne '' && $p eq $cd && $c eq $cc);
					HMCCU_BulkUpdate ($clHash, 'state', $fv, $cv)
						if ($p eq $sd && ($sc eq '' || $sc eq $c));
				
					# Update peers
					HMCCU_UpdatePeers ($clHash, "$c.$p", $cv, $peer) if (!$vg && $peer ne 'null');

					# Store result, but not for indirect updates of virtual devices
					$results{$devAddr}{$c}{$ps}{$p} = $cv if ($devAddr eq $a);
					
					my @rnList = HMCCU_GetReadingName ($clHash, $clInt, $a, $c, $p, '', $clRF, $ps);
					my $dispFlag = HMCCU_FilterReading ($clHash, $chnAddr, $p, $ps) ? '' : '.';
					foreach my $rn (@rnList) {
						HMCCU_Trace ($clHash, 2, "rn=$rn, dispFlag=$dispFlag, fv=$fv, cv=$cv");
						HMCCU_BulkUpdate ($clHash, $dispFlag.$rn, $fv, $cv);
					}
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
	HMCCU_UpdateDeviceStates ($clHash);
# 	HMCCU_BulkUpdate ($clHash, 'battery', $battery) if ($battery ne 'unknown');
# 	HMCCU_BulkUpdate ($clHash, 'activity', $activity);
# 	HMCCU_BulkUpdate ($clHash, 'devstate', $devState);	

	# Calculate and update HomeMatic state
	if ($ccuflags !~ /nohmstate/) {
		my ($hms_read, $hms_chn, $hms_dpt, $hms_val) = HMCCU_GetHMState ($clName, $ioName);
		HMCCU_BulkUpdate ($clHash, $hms_read, $hms_val, $hms_val) if (defined($hms_val));
	}

	readingsEndUpdate ($clHash, 1);
	
	return \%results;
}

######################################################################
# Refresh readings of a client device
######################################################################

sub HMCCU_RefreshReadings ($)
{
	my ($clHash) = @_;
	
	return if ($clHash->{hmccu}{semDefaults} == 1);
	
	my $ioHash = HMCCU_GetHash ($clHash) // return;
	
	HMCCU_DeleteReadings ($clHash, '.*');
	
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
# Parameter type is VAL or SVAL.
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
	if (exists ($ch->{hmccu}{dp}{$chkey}{$paramset}{$type})) {
		$ch->{hmccu}{dp}{$chkey}{$paramset}{$otype} = $ch->{hmccu}{dp}{$chkey}{$paramset}{$type};
	}
	else {
		$ch->{hmccu}{dp}{$chkey}{$paramset}{$otype} = $value;
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

sub HMCCU_UpdateMultipleDevices ($$)
{
	my ($hash, $objects) = @_;
	my $name = $hash->{NAME};
	my $c = 0;
	
	# Check syntax
	return 0 if (!defined ($hash) || !defined ($objects));

	# Update reading in matching client devices
	my @devlist = HMCCU_FindClientDevices ($hash, '(HMCCUDEV|HMCCUCHN)', undef,
		'ccudevstate=active');
	foreach my $d (@devlist) {
		my $clHash = $defs{$d};
		if (!defined($clHash)) {
			HMCCU_Log ($name, 2, "Can't find hash for device $d");
			next;
		}
	 	my @addrlist = HMCCU_GetAffectedAddresses ($clHash);
		next if (scalar (@addrlist) == 0);
		foreach my $addr (@addrlist) {
			if (exists ($objects->{$addr})) {
 				my $rc = HMCCU_UpdateParamsetReadings ($hash, $clHash, $objects, \@addrlist);
				$c++ if (ref($rc));
				last;
			}
		}
	}

	return $c;
}

######################################################################
# Get list of device addresses including group device members.
# For virtual devices group members are only returned if ccuflag
# updGroupMembers is set.
######################################################################

sub HMCCU_GetAffectedAddresses ($)
{
	my ($clHash) = @_;
	my @addlist = ();
	
	if ($clHash->{TYPE} eq 'HMCCUDEV' || $clHash->{TYPE} eq 'HMCCUCHN') {
		my $ioHash = HMCCU_GetHash ($clHash);
		my $ccuFlags = defined($ioHash) ? HMCCU_GetFlags ($ioHash) : 'null';
		if (exists($clHash->{ccuaddr})) {
			my ($devaddr, $cnum) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
			push @addlist, $devaddr;
		}
		if ($clHash->{ccuif} eq 'VirtualDevices' && $ccuFlags =~ /updGroupMembers/ && exists($clHash->{ccugroup}) && $clHash->{ccugroup} ne '') {
			push @addlist, split (',', $clHash->{ccugroup});
		}
	}
	
	return @addlist;
}

######################################################################
# Update peer devices.
# Syntax of peer definitions is:
# channel.datapoint[,...]:condition:type:action
# condition := valid perl expression. Any channel.datapoint
#    combination is substituted by the corresponding value. If channel
#    is preceded by a % it's substituted by the raw value. If it's
#    preceded by a $ it's substituted by the formated/converted value.
#    If % or $ is doubled the old values are used.
# type := type of action. Valid types are ccu, hmccu and fhem.
# action := Action to be performed if result of condition is true.
#    Depending on type action type this could be an assignment or a
#    FHEM command. If action contains $value this parameter is 
#    substituted by the original value of the datapoint which has
#    triggered the action.
# assignment := channel.datapoint=expression
######################################################################

sub HMCCU_UpdatePeers ($$$$)
{
	my ($clt_hash, $chndpt, $val, $peerattr) = @_;

	my $io_hash = HMCCU_GetHash ($clt_hash);

	HMCCU_Trace ($clt_hash, 2, "chndpt=$chndpt val=$val peer=$peerattr");
	
	foreach my $r (split (/[;\n]+/, $peerattr)) {
		HMCCU_Trace ($clt_hash, 2, "rule=$r");
		my ($vars, $cond, $type, $act) = split (/:/, $r, 4);
		next if (!defined ($act));
		HMCCU_Trace ($clt_hash, 2, "vars=$vars, cond=$cond, type=$type, act=$act");
		next if ($cond !~ /$chndpt/);
		
		# Check if rule is affected by datapoint update
		my $ex = 0;
		foreach my $dpt (split (",", $vars)) {
			HMCCU_Trace ($clt_hash, 2, "dpt=$dpt");
			$ex = 1 if ($ex == 0 && $dpt eq $chndpt);
			if (!exists ($clt_hash->{hmccu}{dp}{$dpt})) {
				HMCCU_Trace ($clt_hash, 2, "Datapoint $dpt does not exist on hash");
			}
			last if ($ex == 1);
		}
		next if (! $ex);

		# Substitute variables and evaluate condition		
		$cond = HMCCU_SubstVariables ($clt_hash, $cond, $vars);
		my $e = eval "$cond";
		HMCCU_Trace ($clt_hash, 2, "eval $cond = $e") if (defined($e));
		HMCCU_Trace ($clt_hash, 2, "Error in eval $cond") if (!defined($e));
		HMCCU_Trace ($clt_hash, 2, "NoMatch in eval $cond") if (defined($e) && $e eq '');
		next if (!defined($e) || $e eq '');

		# Substitute variables and execute action	
		if ($type eq 'ccu' || $type eq 'hmccu') {
			my ($aobj, $aexp) = split (/=/, $act);
			$aexp =~ s/\$value/$val/g;
			$aexp = HMCCU_SubstVariables ($clt_hash, $aexp, $vars);
			HMCCU_Trace ($clt_hash, 2, "set $aobj to $aexp");
			my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($io_hash, "$type:$aobj",
				$HMCCU_FLAG_INTERFACE);
			next if ($flags != $HMCCU_FLAGS_IACD && $flags != $HMCCU_FLAGS_NCD);
			HMCCU_SetMultipleDatapoints ($clt_hash, { "001.$int.$add:$chn.$dpt" => $aexp });
		}
	}
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
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
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
# Parameter type is A for XML or B for binary.
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
# Return number of RPC servers or 0 on error.
######################################################################

sub HMCCU_StartExtRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $attrset = 0;

	# Change RPC type to procrpc
	if ($ccuflags =~ /(extrpc|intrpc)/) {
		$ccuflags =~ s/(extrpc|intrpc)/procrpc/g;
		CommandAttr (undef, "$name ccuflags $ccuflags");
		$attrset = 1;
		
		# Disable existing devices of type HMCCURPC
		foreach my $d (keys %defs) {
			my $ch = $defs{$d};
			next if (!exists ($ch->{TYPE}) || !exists ($ch->{NAME}) || $ch->{TYPE} ne 'HMCCURPC');
			CommandAttr (undef, $ch->{NAME}." disable 1") if (IsDisabled ($ch->{NAME}) != 1);
		}
	}
	
	my $c = 0;
	my $d = 0;
	my $s = 0;
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
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
			if (!$rc) {
				HMCCU_SetRPCState ($hash, 'error', $ifname2, $msg);
			}
			else {
				$c++;
			}
		}
		HMCCU_SetRPCState ($hash, 'starting') if ($c > 0);
		return $c;
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
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
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
	my $interfaces = HMCCU_GetRPCInterfaceList ($hash, 1);
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
	my ($hash, $device, $ccuget) = @_;
	$ccuget //= 'Value';
	my $name = $hash->{NAME};
	my $devname = '';
	my $response = '';

	my $ioHash = HMCCU_GetHash ($hash) // return '';
	
	$ccuget = HMCCU_GetAttribute ($ioHash, $hash, 'ccuget', 'Value') if ($ccuget eq 'Attr');

	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($ioHash, $device, 0);
	if ($flags == $HMCCU_FLAG_ADDRESS) {
		$devname = HMCCU_GetDeviceName ($ioHash, $add);
		return '' if ($devname eq '');
	}
	else {
		$devname = $nam;
	}

	$response .= HMCCU_HMScriptExt ($ioHash, "!GetDeviceInfo", 
		{ devname => $devname, ccuget => $ccuget });
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
	
	foreach my $dpspec (split ("\n", $devinfo)) {
		if ($dpspec =~ /^D/) {
			my ($t, $d_iface, $d_addr, $d_name, $d_type) = split (';', $dpspec);
 			$result .= "DEV $d_name $d_addr interface=$d_iface type=$d_type<br/>";
		}
		else {
			my ($t, $c_addr, $c_name, $d_name, $d_type, $d_value, $d_flags) = split (';', $dpspec);
			$d_name =~ s/^[^:]+:(.+)$/$1/;
			if ($c_addr ne $c_oaddr) {
				$result .= "CHN $c_addr $c_name<br/>";
				$c_oaddr = $c_addr;
			}
			my $dt = exists($vtypes{$d_type}) ? $vtypes{$d_type} : $d_type;
			$result .= "&nbsp;&nbsp;&nbsp;$d_name = $d_value {$dt} [$d_flags]<br/>";
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
			$result .= '<table border="1">\n<tr>';
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
# Get available firmware versions from EQ-3 server.
# Firmware version, date and download link are stored in hash
# {hmccu}{type}{$type} in elements {firmware}, {date} and {download}.
# Parameter type can be a regular expression matching valid Homematic
# device types in upper case letters. Default is '.*'. 
# Return number of available firmware downloads.
######################################################################

sub HMCCU_GetFirmwareVersions ($$)
{
	my ($hash, $type) = @_;
	my $name = $hash->{NAME};
	my $ccureqtimeout = AttrVal ($name, 'ccuReqTimeout', $HMCCU_TIMEOUT_REQUEST);
	
	my $url = 'http://www.eq-3.de/service/downloads.html';
	my $response = GetFileFromURL ($url, $ccureqtimeout, "suchtext=&suche_in=&downloadart=11");
	my @download = $response =~ m/<a.href="(Downloads\/Software\/Firmware\/[^"]+)/g;
	my $dc = 0;
	my @ts = localtime (time);
	$ts[4] += 1;
	$ts[5] += 1900;
	
	foreach my $dl (@download) {
		my $dd = $ts[3];
		my $mm = $ts[4];
		my $yy = $ts[5];
		my $fw;
		my $date = "$dd.$mm.$yy";

		my @path = split (/\//, $dl);
		my $file = pop @path;
		next if ($file !~ /(\.tgz|\.tar\.gz)/);
		
		$file =~ s/_update_V?/\|/;
		my ($dt, $rest) = split (/\|/, $file);
		next if (!defined($rest));
		$dt =~ s/_/-/g;
		$dt = uc($dt);
		
		next if ($dt !~ /$type/);
		
		if ($rest =~ /^([\d_]+)([0-9]{2})([0-9]{2})([0-9]{2})\./) {
			# Filename with version and date
			($fw, $yy, $mm, $dd) = ($1, $2, $3, $4);
			$yy += 2000 if ($yy < 100);
			$date = "$dd.$mm.$yy";
			$fw =~ s/_$//;
		}
		elsif ($rest =~ /^([\d_]+)\./) {
			# Filename with version
			$fw = $1;
		}
		else {
			$fw = $rest;
		}
		$fw =~ s/_/\./g;

		# Compare firmware dates
		if (exists ($hash->{hmccu}{type}{$dt}{date})) {
			my ($dd1, $mm1, $yy1) = split (/\./, $hash->{hmccu}{type}{$dt}{date});
			my $v1 = $yy1*10000+$mm1*100+$dd1;
			my $v2 = $yy*10000+$mm*100+$dd;
			next if ($v1 > $v2);
		}

		$dc++;		
		$hash->{hmccu}{type}{$dt}{firmware} = $fw;
		$hash->{hmccu}{type}{$dt}{date} = $date;
		$hash->{hmccu}{type}{$dt}{download} = $dl;
	}
	
	return $dc;
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
			my $typeprefix = $hmdata[2] =~ /^CUX/ ? 'CUX-' :
				$hmdata[1] eq 'HVL' ? 'HVL-' : '';
			$objects{$hmdata[2]}{addtype}   = 'dev';
			$objects{$hmdata[2]}{channels}  = $hmdata[5];
			$objects{$hmdata[2]}{flag}      = 'N';
			$objects{$hmdata[2]}{interface} = $hmdata[1];
			$objects{$hmdata[2]}{name}      = $hmdata[3];
			$objects{$hmdata[2]}{type}      = $typeprefix . $hmdata[4];
			$objects{$hmdata[2]}{direction} = 0;
			$devname = $hmdata[3];
			$devtype = $typeprefix . $hmdata[4];
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

		# Read available datapoints for device type
		HMCCU_GetDatapointList ($hash, $devname, $devtype) if (defined ($devname) && defined ($devtype));
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
	my $response = HMCCU_HMScriptExt ($hash, "!GetDeviceList");
	return (-1, -1, -1, -1, -1) if ($response eq '' || $response =~ /^ERROR:.*/);
	my $groups = HMCCU_HMScriptExt ($hash, "!GetGroupDevices");
	
	# CCU is reachable
	$hash->{ccustate} = 'active';
	
	# Delete old entries
	HMCCU_Log ($hash, 2, "Deleting old groups");
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
			$typeprefix = "CUX-" if ($hmdata[2] =~ /^CUX/);
			$typeprefix = "HVL-" if ($hmdata[1] eq 'HVL');
			$objects{$hmdata[2]}{type}      = $typeprefix . $hmdata[4];
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

		# Read available datapoints for each device type
		# This will lead to problems if some devices have different firmware versions
		# or links to system variables !
		HMCCU_GetDatapointList ($hash);
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
	
	HMCCU_UpdateReadings ($hash, { "count_devices" => $devcount, "count_channels" => $chncount,
		"count_interfaces" => $ifcount, "count_programs" => $prgcount, "count_groups" => $gcount
	});
	
	return ($devcount, $chncount, $ifcount, $prgcount, $gcount);
}

######################################################################
# Read list of datapoints for all or one CCU device type(s).
# Function must not be called before GetDeviceList.
# Return number of datapoints read.
######################################################################

sub HMCCU_GetDatapointList ($;$$)
{
	my ($hash, $devname, $devtype) = @_;
	my $name = $hash->{NAME};

	my @devunique;

	if (defined($devname) && defined($devtype)) {
		return 0 if (exists($hash->{hmccu}{dp}{$devtype}));
		push @devunique, $devname;
	}
	else {
		if (exists($hash->{hmccu}{dp})) {
			delete $hash->{hmccu}{dp};
		}

		# Select one device for each device type
		my %alltypes;
		foreach my $add (sort keys %{$hash->{hmccu}{dev}}) {
			next if ($hash->{hmccu}{dev}{$add}{addtype} ne 'dev');
			my $dt = $hash->{hmccu}{dev}{$add}{type};
			if (defined($dt)) {
				if ($dt ne '' && !exists ($alltypes{$dt})) {
					$alltypes{$dt} = 1;
					push @devunique, $hash->{hmccu}{dev}{$add}{name};
				}
			}
			else {
				HMCCU_Log ($hash, 2, "Corrupt or invalid entry in device table for device $add");
			}
		}
	}

	return HMCCU_Log ($hash, 2, "No device types found in device table. Cannot read datapoints.", 0)
		if (scalar(@devunique) == 0);
	
	my $devlist = join (',', @devunique);
	my $response = HMCCU_HMScriptExt ($hash, '!GetDatapointList', { list => $devlist });
	return HMCCU_Log ($hash, 2, "Cannot get datapoint list", 0)
		if ($response eq '' || $response =~ /^ERROR:.*/);

	my $c = 0;	
	foreach my $dpspec (split /[\n\r]+/,$response) {
		my ($iface, $chna, $devt, $devc, $dptn, $dptt, $dpto) = split (";", $dpspec);
		my $dcdp = "$devc.$dptn";
		$devt = "CUX-".$devt if ($iface eq 'CUxD');
		$devt = "HVL-".$devt if ($iface eq 'HVL');
# 		$hash->{hmccu}{dp}{$devt}{spc}{ontime}   = $dcdp if ($dptn eq 'ON_TIME');
# 		$hash->{hmccu}{dp}{$devt}{spc}{ramptime} = $dcdp if ($dptn eq 'RAMP_TIME');
# 		$hash->{hmccu}{dp}{$devt}{spc}{submit}   = $dcdp if ($dptn eq 'SUBMIT');
# 		$hash->{hmccu}{dp}{$devt}{spc}{level}    = $dcdp if ($dptn eq 'LEVEL');		
		$hash->{hmccu}{dp}{$devt}{ch}{$devc}{$dptn}{type} = $dptt;
		$hash->{hmccu}{dp}{$devt}{ch}{$devc}{$dptn}{oper} = $dpto;
		if (exists($hash->{hmccu}{dp}{$devt}{cnt}{$dptn})) {
			$hash->{hmccu}{dp}{$devt}{cnt}{$dptn}++;
		}
		else {
			$hash->{hmccu}{dp}{$devt}{cnt}{$dptn} = 1;
		}
		$c++;
	}
	
	return $c;
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
# Get list of valid datapoints for device type.
# hash = hash of client or IO device
# devtype = Homematic device type
# chn = Channel number, -1=all channels
# oper = Valid operation, combination of 1=Read, 2=Write, 4=Event
# dplistref = Reference for array with datapoints (optional)
# Return number of datapoints.
######################################################################

sub HMCCU_GetValidDatapoints ($$$$;$)
{
	my ($hash, $devtype, $chn, $oper, $dplistref) = @_;
	$chn //= -1;

	my $count = 0;
	my $ioHash = HMCCU_GetHash ($hash);
	
#	return 0 if (HMCCU_IsFlag ($ioHash->{NAME}, 'dptnocheck') || !exists($ioHash->{hmccu}{dp}));
	return 0 if (!exists($ioHash->{hmccu}{dp}));
	
	if ($chn >= 0) {
		if (exists($ioHash->{hmccu}{dp}{$devtype}{ch}{$chn})) {
			foreach my $dp (sort keys %{$ioHash->{hmccu}{dp}{$devtype}{ch}{$chn}}) {
				if ($ioHash->{hmccu}{dp}{$devtype}{ch}{$chn}{$dp}{oper} & $oper) {
					push @$dplistref, $dp if (defined($dplistref));
					$count++;
				}
			}
		}
	}
	else {
		if (exists ($ioHash->{hmccu}{dp}{$devtype})) {
			foreach my $ch (sort keys %{$ioHash->{hmccu}{dp}{$devtype}{ch}}) {
				next if ($ch == 0 && $chn == -2);
				foreach my $dp (sort keys %{$ioHash->{hmccu}{dp}{$devtype}{ch}{$ch}}) {
					if ($ioHash->{hmccu}{dp}{$devtype}{ch}{$ch}{$dp}{oper} & $oper) {
						push @$dplistref, $ch.".".$dp if (defined($dplistref));
						$count++;
					}
				}
			}
		}
	}
	
	return $count;
}

######################################################################
# Get datapoint attribute.
# Valid attributes are 'oper' or 'type'.
# Return undef on error
######################################################################

sub HMCCU_GetDatapointAttr ($$$$$)
{
	my ($hash, $devtype, $chnno, $dpt, $attr) = @_;
	
	return (
		($attr ne 'oper' && $attr ne 'type') ||
		(!exists($hash->{hmccu}{dp}{$devtype})) ||
		(!exists($hash->{hmccu}{dp}{$devtype}{ch}{$chnno})) ||
		(!exists($hash->{hmccu}{dp}{$devtype}{ch}{$chnno}{$dpt}))
	) ? undef : $hash->{hmccu}{dp}{$devtype}{ch}{$chnno}{$dpt}{$attr};
}

######################################################################
# Find a datapoint for device type.
# hash = hash of client or IO device
# devtype = Homematic device type
# chn = Channel number, -1=all channels
# oper = Valid operation: 1=Read, 2=Write, 4=Event
# Return channel of first match or -1.
######################################################################

sub HMCCU_FindDatapoint ($$$$$)
{
	my ($hash, $devtype, $chn, $dpt, $oper) = @_;
	
	my $ioHash = HMCCU_GetHash ($hash);
	return -1 if (!exists($ioHash->{hmccu}{dp}));
	
	if ($chn >= 0) {
		if (exists($ioHash->{hmccu}{dp}{$devtype}{ch}{$chn})) {
			foreach my $dp (sort keys %{$ioHash->{hmccu}{dp}{$devtype}{ch}{$chn}}) {
				return $chn if ($dp eq $dpt &&
					$ioHash->{hmccu}{dp}{$devtype}{ch}{$chn}{$dp}{oper} & $oper);
			}
		}
	}
	else {
		if (exists($ioHash->{hmccu}{dp}{$devtype})) {
			foreach my $ch (sort keys %{$ioHash->{hmccu}{dp}{$devtype}{ch}}) {
				foreach my $dp (sort keys %{$ioHash->{hmccu}{dp}{$devtype}{ch}{$ch}}) {
					return $ch if ($dp eq $dpt &&
						$ioHash->{hmccu}{dp}{$devtype}{ch}{$ch}{$dp}{oper} & $oper);
				}
			}
		}
	}
	
	return -1;
}

######################################################################
# Check if datapoint is valid.
# Parameter chn can be a channel address or a channel number. If dpt
# contains a channel number parameter chn should be set to undef.
# Parameter dpt can contain a channel number.
# Parameter oper specifies access flag:
#   1 = datapoint readable
#   2 = datapoint writeable
#   4 = datapoint events
# Return 1 if ccuflags is set to dptnocheck or datapoint is valid.
# Otherwise 0.
######################################################################

sub HMCCU_IsValidDatapoint ($$$$$)
{
	my ($hash, $devtype, $chn, $dpt, $oper) = @_;
	
	my $ioHash = HMCCU_GetHash ($hash);
	return 0 if (!defined($ioHash));
	
	if ($hash->{TYPE} eq 'HMCCU' && !defined($devtype)) {
		$devtype = HMCCU_GetDeviceType ($ioHash, $chn, 'null');
	}
	
	return 1 if (HMCCU_IsFlag ($ioHash->{NAME}, "dptnocheck") || !exists($ioHash->{hmccu}{dp}));

	my $chnno;
	
	if (defined($chn) && $chn ne '') {
		if ($chn =~ /^[0-9]{1,2}$/) {
			$chnno = $chn;
		}
		elsif (HMCCU_IsValidChannel ($ioHash, $chn, $HMCCU_FL_ADDRESS)) {
			my ($a, $c) = split(":",$chn);
			$chnno = $c;
		}
		else {
			HMCCU_Trace ($hash, 2, "$chn is not a valid channel address or number");
			HMCCU_Trace ($hash, 2, stacktraceAsString(undef));
			return 0;
		}
	}
	
	if ($dpt =~ /^([0-9]{1,2})\.(.+)$/) {
		$chnno = $1;
		$dpt = $2;
	}
	
	if (!defined($chnno) || $chnno eq '') {
		HMCCU_Trace ($hash, 2, "channel number missing for datapoint $dpt");
		return 0;
	}
	
	my $v = (exists($ioHash->{hmccu}{dp}{$devtype}{ch}{$chnno}{$dpt}) &&
	   ($ioHash->{hmccu}{dp}{$devtype}{ch}{$chnno}{$dpt}{oper} & $oper)) ? 1 : 0;
	HMCCU_Trace ($hash, 2, "devtype=$devtype, chnno=$chnno, dpt=$dpt, valid=$v");
	
	return $v;
}

######################################################################
# Get list of device or channel addresses for which device or channel
# name matches regular expression.
# Parameter mode can be 'dev' or 'chn'.
# Return number of matching entries.
######################################################################

sub HMCCU_GetMatchingDevices ($$$$)
{
	my ($hash, $regexp, $mode, $listref) = @_;
	my $c = 0;

	foreach my $name (sort keys %{$hash->{hmccu}{adr}}) {
		next if (
			$name !~/$regexp/ ||
			$hash->{hmccu}{adr}{$name}{addtype} ne $mode ||
		   $hash->{hmccu}{adr}{$name}{valid} == 0);
		push (@$listref, $hash->{hmccu}{adr}{$name}{address});
		$c++;
	}

	return $c;
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
# Return array with device address and channel no. If name is not
# found or refers to a device the specified default values will be
# returned. 
######################################################################

sub HMCCU_GetAddress ($$;$$)
{
	my ($hash, $name, $defadd, $defchn) = @_;
	$defadd //= '';
	$defchn //= '';
	my $add = $defadd;
	my $chn = $defchn;
	my $chnno = $defchn;
	my $addr = '';
	my $type = '';

	if ($name =~ /^hmccu:.+$/) {
		# Name is a FHEM device name
		$name =~ s/^hmccu://;
		if ($name =~ /^([^:]+):([0-9]{1,2})$/) {
			$name = $1;
			$chnno = $2;
		}
		return ($defadd, $defchn) if (!exists($defs{$name}));
		my $dh = $defs{$name};
		return ($defadd, $defchn) if ($dh->{TYPE} ne 'HMCCUCHN' && $dh->{TYPE} ne 'HMCCUDEV');
		($add, $chn) = HMCCU_SplitChnAddr ($dh->{ccuaddr});
		$chn = $chnno if ($chn eq '');
		return ($add, $chn);
	}
	elsif ($name =~ /^ccu:.+$/) {
		# Name is a CCU device or channel name
		$name =~ s/^ccu://;
	}

	if (exists ($hash->{hmccu}{adr}{$name})) {
		# Name known by HMCCU
		$addr = $hash->{hmccu}{adr}{$name}{address};
		$type = $hash->{hmccu}{adr}{$name}{addtype};
	}
	elsif (exists ($hash->{hmccu}{dev}{$name})) {
		# Address known by HMCCU
		$addr = $name;
		$type = $hash->{hmccu}{dev}{$name}{addtype};
	}
	else {
		# Address not known. Query CCU
		my ($dc, $cc) = HMCCU_GetDevice ($hash, $name);
		if ($dc > 0 && $cc > 0 && exists ($hash->{hmccu}{adr}{$name})) {
			$addr = $hash->{hmccu}{adr}{$name}{address};
			$type = $hash->{hmccu}{adr}{$name}{addtype};
		}
	}
	
	if ($addr ne '') {
		if ($type eq 'chn') {
			($add, $chn) = split (":", $addr);
		}
		else {
			$add = $addr;
		}
	}

	return ($add, $chn);
}

######################################################################
# Get addresses of group member devices.
# Group 'virtual' is ignored.
# Return list of device addresses or empty list on error.
######################################################################

sub HMCCU_GetGroupMembers ($$)
{
	my ($hash, $group) = @_;
	
	return $group ne 'virtual' && exists ($hash->{hmccu}{grp}{$group}) ?
		split (',', $hash->{hmccu}{grp}{$group}{devs}) : ();
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

	if (!defined($addr)) {
		HMCCU_Log ('HMCCU', 2, stacktraceAsString(undef));
		return ('', '');
	}
	
	my ($dev, $chn) = split (':', $addr);
	$chn = $default if (!defined ($chn));

	return ($dev, $chn);
}

sub HMCCU_SplitDatapoint ($;$)
{
	my ($dpt, $defchn) = @_;
	
	my @t = split ('.', $dpt);
	
	return (scalar(@t) > 1) ? @t : ($defchn, $t[0]);
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
	
	my $alias = "CCU RPC $ifname";
	my $rpcdevname = 'd_rpc';

	# Ensure unique device name by appending last 2 digits of CCU IP address
	$rpcdevname .= HMCCU_GetIdFromIP ($hash->{ccuip}, '') if (exists($hash->{ccuip}));

	# Build device name and define command
	$rpcdevname = makeDeviceName ($rpcdevname.$ifname);
	my $rpccreate = "$rpcdevname HMCCURPCPROC $rpcprot://$rpchost $ifname";
	return (HMCCU_Log ($hash, 2, "Device $rpcdevname already exists. Please delete or rename it.", ''), 0)
		if (exists($defs{"$rpcdevname"}));

	# Create RPC device
	HMCCU_Log ($hash, 1, "Creating new RPC device $rpcdevname for interface $ifname");
	my $ret = CommandDefine (undef, $rpccreate);
	if (!defined($ret)) {
		# RPC device created. Set/copy some attributes from HMCCU device
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
# Set initial attributes after device definition
######################################################################

sub HMCCU_SetInitialAttributes ($$)
{
	my ($ioHash, $clName) = @_;

	my $ccudefAttributes = AttrVal ($ioHash->{NAME}, 'ccudef-attributes', 'room=Homematic');
	foreach my $a (split(';', $ccudefAttributes)) {
		my ($an, $av) = split('=', $a);
		CommandAttr (undef, "$clName $an $av") if (defined($av));
	}
}

######################################################################
# Set default attributes for client device.
# Optionally delete obsolete attributes.
######################################################################

sub HMCCU_SetDefaultAttributes ($;$)
{
	my ($clHash, $parRef) = @_;
	my $ioHash = HMCCU_GetHash ($clHash);
	my $clName = $clHash->{NAME};
	
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
	$parRef //= { mode => 'update', role => undef, roleChn => undef };
	my $role = $parRef->{role} // HMCCU_GetChannelRole ($clHash, $parRef->{roleChn} // $cc);

	if ($role ne '') {
		$clHash->{hmccu}{semDefaults} = 1;
		
		# Delete obsolete attributes
		if ($parRef->{mode} eq 'reset') {
			my @removeAttr = ('ccureadingname', 'ccuscaleval', 'eventMap', 'cmdIcon',
				'substitute', 'webCmd', 'widgetOverride'
			);
			my $detect = HMCCU_DetectDevice ($ioHash, $clHash->{ccuaddr}, $clHash->{ccuif});
			if (defined($detect) && ($detect->{level} == 1 || ($detect->{level} == 2 && $clHash->{TYPE} eq 'HMCCUCHN'))) {
				push @removeAttr, 'statechannel', 'statedatapoint', 'controlchannel', 'controldatapoint', 'statevals'
			}
			foreach my $a (@removeAttr) {
				CommandDeleteAttr (undef, "$clName $a") if (exists($attr{$clName}{$a}));
			}
		}
		
		# Set additional attributes
		if (exists($HMCCU_ATTR->{$role}) && !exists($HMCCU_ATTR->{$role}{_none_})) {
			foreach my $a (keys %{$HMCCU_ATTR->{$role}}) {
				CommandAttr (undef, "$clName $a ".$HMCCU_ATTR->{$role}{$a});
			}
		}
		
		$clHash->{hmccu}{semDefaults} = 0;
		return 1;
	}
	else {
		HMCCU_Log ($clHash, 2, "Cannot detect role of $clName");
		return 0;
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

	HMCCU_Trace ($clHash, 2, "dpt=$dpt, ctrlChn=$ctrlChn");
	my $sv = AttrVal ($clHash->{NAME}, 'statevals', '');
	if ($sv eq '' && $dpt ne '' && $ctrlChn ne '') {
		my $role = HMCCU_GetChannelRole ($clHash, $ctrlChn);
		HMCCU_Trace ($clHash, 2, "dpt=$dpt, ctrlChn=$ctrlChn, role=$role");
		if ($role ne '' && exists($HMCCU_STATECONTROL->{$role}) &&
			HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$role}{C}, $clHash->{ccuif}) eq $dpt)
		{
			return $HMCCU_STATECONTROL->{$role}{V};
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
#   Paramset:Datapoint:[+|-]Value
#   Paramset:Datapoint:?Parameter
#   Paramset:Datapoint:?Parameter=Default-Value
#   Paramset:Datapoint:#Parameter=[Value1[,...]]
# Paramset:
#   V=VALUES, M=MASTER (channel), D=MASTER (device)
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

sub HMCCU_UpdateRoleCommands ($$;$)
{
	my ($ioHash, $clHash, $chnNo) = @_;
	$chnNo //= '';

	my %pset = ('V' => 'VALUES', 'M' => 'MASTER', 'D' => 'MASTER', 'I' => 'INTERNAL');
	my @cmdSetList = ();
	my @cmdGetList = ();
	return if (!defined($clHash->{hmccu}{role}) || $clHash->{hmccu}{role} eq '');
	
	# Delete existing role commands
	delete $clHash->{hmccu}{roleCmds} if (exists($clHash->{hmccu}{roleCmds}));
	
	URCROL: foreach my $chnRole (split(',', $clHash->{hmccu}{role})) {
		my ($channel, $role) = split(':', $chnRole);
		next URCROL if (!defined($role) || !exists($HMCCU_ROLECMDS->{$role}));
		
		URCCMD: foreach my $cmdKey (keys %{$HMCCU_ROLECMDS->{$role}}) {
			next URCCMD if ($chnNo ne '' && $chnNo != $channel && $chnNo ne 'd');
			my ($cmd, $cmdIf) = split (':', $cmdKey);
			next URCCMD if (defined($cmdIf) && $clHash->{ccuif} !~ /$cmdIf/);
			my $cmdSyntax = $HMCCU_ROLECMDS->{$role}{$cmdKey};
			my $cmdChn = $channel;
			my $cmdType = 'set';
			if ($cmd =~ /^(set|get) (.+)$/) {
				$cmdType = $1;
				$cmd = $2;
			}
			
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{syntax} = $cmdSyntax;
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{role}   = $role;

			my $cnt = 0;
			my $cmdDef = $cmd;
			my $usage = $cmdDef;
			my $cmdArgList = '';
			my @parTypes = (0, 0, 0, 0, 0);
			
			URCSUB: foreach my $subCmd (split(/\s+/, $cmdSyntax)) {
				my $pt = 0;   # Default = no parameter
				my $scn = sprintf ("%03d", $cnt);
				my ($ps, $dpt, $par, $fnc) = split(/:/, $subCmd);
				my ($addr, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
				$cmdChn = 'd' if ($ps eq 'D');
				
				my $paramDef = HMCCU_GetParamDef ($ioHash, "$addr:$cmdChn", $ps eq 'I' ? 'VALUES' : $pset{$ps}, $dpt);
				if (!defined($paramDef)) {
					HMCCU_Log ($ioHash, 2, "Can't get definition of $addr:$cmdChn.$dpt. Ignoring command $cmd for device $clHash->{NAME}");
					next URCCMD;
				}
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{min}  = $paramDef->{MIN};
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{max}  = $paramDef->{MAX};
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{unit} = $paramDef->{UNIT} // '';
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{ps}   = $pset{$ps};
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{dpt}  = $dpt;
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{fnc}  = $fnc // '';
				if ($paramDef->{TYPE} eq 'ENUM' && defined($paramDef->{VALUE_LIST})) {
					# Build lookup table
					my @el = split(',', $paramDef->{VALUE_LIST});
					while (my ($i, $e) = each @el) {
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$e} = $i;
					}
					 
					# Parameter definition contains names for min and max value
					$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{min} =
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$paramDef->{MIN}}
							if (exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$paramDef->{MIN}}));					
					$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{max} =
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$paramDef->{MAX}}
							if (exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$paramDef->{MAX}}));					
				}
			
				if (defined($par) && $par ne '') {
					if ($par =~ /^#([^=]+)/) {
						# Parameter list
						my $argList = '';
						$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $1;
						$pt = 1;   # Enum / List of fixed values

						if ($paramDef->{TYPE} eq 'ENUM' && defined($paramDef->{VALUE_LIST})) {
							$argList = $paramDef->{VALUE_LIST};
						}
						else {
							my ($pn, $pv) = split('=', $par);
							$argList = $pv // '';
							my %valList;
							foreach my $cv (split(',', $HMCCU_STATECONTROL->{$role}{V})) {
								my ($vn, $vv) = split(':', $cv);
								$valList{$vn} = $vv // $vn;
							}
							my @el = split(',', $argList);
							while (my ($i, $e) = each @el) {
								$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{look}{$e} = $valList{$e} // $i;
							}
						}

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
						# Fix value. Command has no argument
						my ($pn, $pv) = split('=', $par);
						$pt = 3;
						if (defined($pv)) {
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $pn;
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = $pv;
						}
						else {
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{parname} = $dpt;
							$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{args} = $par;
						}
					}
				}

				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcmd}{$scn}{partype} = $pt;
				$parTypes[$pt]++;
				$cnt++;
			}
			
			if ($parTypes[1] == 1 && $parTypes[2] == 0 && $cmdArgList ne '') {
				# Only one variable argument. Argument belongs to a predefined value list
				# If values contain blanks, substitute blanks by # and enclose strings in quotes
				$cmdDef .= ':'.join(',', map { $_ =~ / / ? '"'.(s/ /#/gr).'"' : $_ } split(',', $cmdArgList));
			}
			elsif ($parTypes[1] == 0 && $parTypes[2] == 0) {
				$cmdDef .= ':noArg';
			}

			if (exists($clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel})) {
				# Same command in multiple channels.
				# Channel number will be set to control channel during command execution
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel} = '?';
			}
			else {
				$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{channel} = $cmdChn;
			}
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{usage}    = $usage;
			$clHash->{hmccu}{roleCmds}{$cmdType}{$cmd}{subcount} = $cnt;

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
# Update additional commands which depend on device state
######################################################################

sub HMCCU_UpdateAdditionalCommands ($$;$$)
{
	my ($ioHash, $clHash, $cc, $cd) = @_;
	$cc //= '';
	$cd //= '';

	# Toggle command
	my $stateVals = HMCCU_GetStateValues ($clHash, $cd, $cc);
	HMCCU_Trace ($clHash, 2, "stateVals=$stateVals, cd=$cd, cc=$cc");
	my %stateCmds = split (/[:,]/, $stateVals);
	my @states = keys %stateCmds;
	$clHash->{hmccu}{cmdlist}{set} .= ' toggle:noArg' if (scalar(@states) > 1);
}

######################################################################
# Execute command related to role
# Parameters:
#   $mode: 'set' or 'get'
#   $command: The command
######################################################################

sub HMCCU_ExecuteRoleCommand ($@)
{
	my ($ioHash, $clHash, $mode, $command, $a, $h) = @_;

	my $name = $clHash->{NAME};
	my $rc;
	my %dpval;
	my %cfval;
	my %inval;
	my %cmdFnc;
	my ($devAddr, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	my $usage = $clHash->{hmccu}{roleCmds}{$mode}{$command}{usage};
	my $c = 0;

	my $channel = $clHash->{hmccu}{roleCmds}{$mode}{$command}{channel};
	if ("$channel" eq '?') {
		my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
		return HMCCU_SetError ($clHash, -12) if ($cc eq '');
		$channel = $cc;
	}
	my $chnAddr = "$devAddr:$channel";
	
	foreach my $cmdNo (sort keys %{$clHash->{hmccu}{roleCmds}{$mode}{$command}{subcmd}}) {
		my $cmd = $clHash->{hmccu}{roleCmds}{$mode}{$command}{subcmd}{$cmdNo};
		my $value;
		my @par = ();
		
		if ($cmd->{ps} ne 'INTERNAL' && !HMCCU_IsValidParameter ($clHash, $chnAddr, $cmd->{ps}, $cmd->{dpt})) {
			HMCCU_Trace ($clHash, 2, "Invalid parameter $cmd->{ps}.$cmd->{dpt} for command $command");
			return HMCCU_SetError ($clHash, -8, "$cmd->{ps}.$cmd->{dpt}");
		}
		
		if ($cmd->{partype} == 4) {
			# Internal value
			$value = $clHash->{hmccu}{intvalues}{$cmd->{parname}} // $cmd->{args};		
		}
		elsif ($cmd->{partype} == 3) {
			# Fix value
			if ($cmd->{args} =~ /^[+-](.+)$/) {
				# Delta value
				return HMCCU_SetError ($clHash, "Current value of $channel.$cmd->{dpt} not available")
					if (!defined($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{SVAL}));
				$value = $clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{SVAL}+int($cmd->{args});
			}
			else {
				$value = $cmd->{args};
			}
		}
		elsif ($cmd->{partype} == 2) {
			# Normal value
			$value = shift @$a // $cmd->{args};
			return HMCCU_SetError ($clHash, "Missing parameter $cmd->{parname}. Usage: $mode $name $usage")
				if ($value eq '');
			if ($cmd->{args} =~ /^([+-])(.+)$/) {
				# Delta value. Sign depends on sign of default value. Sign of specified value is ignored
				my $sign = $1 eq '+' ? 1 : -1;
				return HMCCU_SetError ($clHash, "Current value of $channel.$cmd->{dpt} not available")
					if (!defined($clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}));
				$value = $clHash->{hmccu}{dp}{"$channel.$cmd->{dpt}"}{$cmd->{ps}}{NVAL}+abs(int($value))*$sign;
			}
			if ($cmd->{unit} eq 's') {
				$value = HMCCU_GetTimeSpec ($value);
				return HMCCU_SetError ($clHash, 'Wrong time format. Use seconds or HH:MM[:SS]')
					if ($value < 0);
			}
		}
		else {
			# Set of valid values
			my $vl = shift @$a // return HMCCU_SetError (
				$clHash, "Missing parameter $cmd->{parname}. Usage: $mode $name $usage");
			$value = $cmd->{look}{$vl} // return HMCCU_SetError (
				$clHash, "Illegal value $vl. Use one of ". join(',', keys %{$cmd->{look}}));
			push @par, $vl;
		}

		# Align new value with min/max boundaries
		if (exists($cmd->{min}) && exists($cmd->{max})) {
			$value = HMCCU_MinMax ($value,
				HMCCU_ScaleValue ($clHash, $channel, $cmd->{dpt}, $cmd->{min}, 0),
				HMCCU_ScaleValue ($clHash, $channel, $cmd->{dpt}, $cmd->{max}, 0)
			);
		}
		
		if ($cmd->{ps} eq 'VALUES') {		
			my $dno = sprintf ("%03d", $c);
			$dpval{"$dno.$clHash->{ccuif}.$chnAddr.$cmd->{dpt}"} = $value;
			$c++;
		}
		elsif ($cmd->{ps} eq 'INTERNAL') {
			$inval{$cmd->{parname}} = $value;
		}
		else {
			$cfval{$cmd->{dpt}} = $value;
		}

		push @par, $value if (defined($value));
		$cmdFnc{$cmdNo}{fnc} = $cmd->{fnc};
		$cmdFnc{$cmdNo}{par} = \@par;
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
			($rc, undef) = HMCCU_SetMultipleParameters ($clHash, $chnAddr, \%cfval, 'MASTER');
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
					$disp .= &{$cmdFnc{$cmdNo}{fnc}}($ioHash, $clHash, $resp, @{$cmdFnc{$cmdNo}{par}});
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
	
	my $usage = "Usage: set $clHash->{NAME} datapoint [{channel-number}.]{datapoint} {value} [...]";
	my %dpval;
	my $i = 0;
	my ($devAddr, $chnNo) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
	my $stVals = HMCCU_GetStateValues ($clHash, $cd, $cc);

	push (@$a, %${h}) if (defined($h));
	while (my $dpt = shift @$a) {
		my $value = shift @$a // return HMCCU_SetError ($clHash, $usage);
		$i++;

		if ($clHash->{TYPE} eq 'HMCCUDEV') {
			if ($dpt =~ /^([0-9]+)\..+$/) {
				return HMCCU_SetError ($clHash, -7) if ($1 >= $clHash->{hmccu}{channels});
			}
			else {
				return HMCCU_SetError ($clHash, -12) if ($cc eq '');
				$dpt = "$cc.$dpt";
			}
		}
		else {
			if ($dpt =~ /^([0-9]+)\..+$/) {
				return HMCCU_SetError ($clHash, -7) if ($1 != $chnNo);
			}
			else {
				$dpt = "$chnNo.$dpt";
			}
		}

		$value = HMCCU_Substitute ($value, $stVals, 1, undef, '') if ($stVals ne '' && $dpt eq $cd);

		my $no = sprintf ("%03d", $i);
		$dpval{"$no.$clHash->{ccuif}.$devAddr:$dpt"} = $value;
	}

	return HMCCU_SetError ($clHash, $usage) if (scalar(keys %dpval) < 1);
	
	my $rc = HMCCU_SetMultipleDatapoints ($clHash, \%dpval);
	return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc));
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
		my @parList = HMCCU_GetParamDef ($ioHash, $devDesc, $paramset);
		return HMCCU_SetError ($clHash, 'Invalid parameter specified. Valid parameters are '.
			join(',', @parList));
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
		($rc, $result) = HMCCU_RPCRequest ($clHash, 'putParamset', $ccuobj, $receiver, $h);
	}

	return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc), $result);
}

######################################################################
# Execute toggle command
######################################################################

sub HMCCU_ExecuteToggleCommand ($@)
{
	my ($clHash) = @_;
	
	# Get state values related to control channel and datapoint
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSCDatapoints ($clHash);
	my $stateVals = HMCCU_GetStateValues ($clHash, $cd, $cc);
	my %stateCmds = split (/[:,]/, $stateVals);
	my @states = keys %stateCmds;
	
	my $ccuif = $clHash->{ccuif};
	my ($devAddr, undef) = HMCCU_SplitChnAddr ($clHash->{ccuaddr}); 
	my $stc = scalar(@states);
	return HMCCU_SetError ($clHash, -15) if ($stc == 0);

	my $curState = defined($clHash->{hmccu}{dp}{"$cc.$cd"}{VALUES}{SVAL}) ?
		$clHash->{hmccu}{dp}{"$cc.$cd"}{VALUES}{SVAL} : $states[0];

	my $newState = '';
	my $st = 0;
	while ($st < $stc) {
		if ($states[$st] eq $curState	) {
			$newState = ($st == $stc-1) ? $states[0] : $states[$st+1];
			last;
		}
		$st++;
	}

	return HMCCU_SetError ($clHash, "Current device state doesn't match any state value")
		if ($newState eq '');

	my $rc = HMCCU_SetMultipleDatapoints ($clHash,
		{ "001.$ccuif.$devAddr:$cc.$cd" => $stateCmds{$newState} }
	);
	return HMCCU_SetError ($clHash, HMCCU_Min(0, $rc))
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
				"<br/>Detected default state datapoint: $detect->{defSCh}.$detect->{defSDP}<br/>".	
				"<br/>Detected default control datapoint: $detect->{defCCh}.$detect->{defCDP}<br/>".
				"<br/>Unique state roles: $detect->{uniqueStateRoleCount}<br/>".
				"<br/>Unique state roles: $detect->{uniqueControlRoleCount}<br/>";		
		}
	}
	$devInfo .= "<br/>Current state datapoint = $sc.$sd<br/>";
	$devInfo .= "<br/>Current control datapoint = $cc.$cd<br/>";
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
	my ($ioHash, $clHash, $command, $addList) = @_;

	my %parSets = ('config' => 'MASTER,LINK,SERVICE', 'values' => 'VALUES', 'update' => 'VALUES,MASTER,LINK,SERVICE');
	my $defParamset = $parSets{$command};
	
	my %objects;
	foreach my $a (@$addList) {
		my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $a, $clHash->{ccuif});
		return HMCCU_SetError ($clHash, "Can't get device description") if (!defined($devDesc));
		
		my $paramset = $defParamset eq '' ? $devDesc->{PARAMSETS} : $defParamset;
		my ($da, $dc) = HMCCU_SplitChnAddr ($a);
		$dc = 'd' if ($dc eq '');

		foreach my $ps (split (',', $paramset)) {
			next if ($devDesc->{PARAMSETS} !~ /$ps/);

			if ($ps eq 'LINK') {
				foreach my $rcv (HMCCU_GetReceivers ($ioHash, $a, $clHash->{ccuif})) {
					my ($rc, $result) = HMCCU_RPCRequest ($clHash, 'getRawParamset', $a, $rcv);
					next if ($rc < 0);
					foreach my $p (keys %$result) { $objects{$da}{$dc}{"LINK.$rcv"}{$p} = $result->{$p}; }					
				}
			}
			else {
				my ($rc, $result) = HMCCU_RPCRequest ($clHash, 'getRawParamset', $a, $ps);
				if ($rc < 0) {
					HMCCU_Log ($clHash, 2, "Can't get parameterset $ps for address $a");
					next;
				}
				foreach my $p (keys %$result) { $objects{$da}{$dc}{$ps}{$p} = $result->{$p}; }
			}
		}
	}
	
	return \%objects;
}

######################################################################
# Convert results into a readable format
######################################################################

sub HMCCU_DisplayGetParameterResult ($$$)
{
	my ($ioHash, $clHash, $objects) = @_;
	
	my $res = '';
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
	my ($ioHash, $clHash, $resp, $programName, $program) = @_;
	$programName //= 'all';
	$program //= 'all';
	
	my @weekDay = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday');
	
	my $convRes = HMCCU_UpdateParamsetReadings ($ioHash, $clHash, $resp);
	
	return "No data available for week program(s) $program"
		if (!exists($clHash->{hmccu}{tt}) || ($program ne 'all' && !exists($clHash->{hmccu}{tt}{$program})));

	my $s = '<html>';
	foreach my $w (sort keys %{$clHash->{hmccu}{tt}}) {
		next if ("$w" ne "$program" && "$program" ne 'all');
		my $p = $clHash->{hmccu}{tt}{$w};
		my $pn = $programName ne 'all' ? $programName : $w+1;
		$s .= '<p><b>Week Program '.$pn.'</b></p><br/><table border="1">';
		foreach my $d (sort keys %{$p->{ENDTIME}}) {
			$s .= '<tr><td><b>'.$weekDay[$d].'</b></td>';
			foreach my $h (sort { $a <=> $b } keys %{$p->{ENDTIME}{$d}}) {
				$s .= '<td>'.$p->{ENDTIME}{$d}{$h}.' / '.$p->{TEMPERATURE}{$d}{$h}.'</td>';
				last if ($p->{ENDTIME}{$d}{$h} eq '24:00');
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
######################################################################

sub HMCCU_SetSCDatapoints ($$;$$)
{
	my ($clHash, $d, $v, $r) = @_;

	my $ioHash = HMCCU_GetHash ($clHash);
	$r //= '';

	# Flags: 1=statechannel, 2=statedatapoint, 4=controlchannel, 8=controldatapoint
	my %flags = (
		'state' => 3, 'control' => 12,
		'statechannel' => 1, 'statedatapoint' => 2,
		'controlchannel' => 4, 'controldatapoint' => 8
	);

	my $chn;
	my $dpt;
	my $f = $flags{$d} // return 0;
	$d =~ s/^(state|control)(channel|datapoint)$/$1/;

	if (defined($v)) {
		# Set value
		return 0 if ($v eq '');

		if ($f & 10) {
			($chn, $dpt) = $v =~ /^([0-9]{1,2})\.(.+)/ ? ($1, $2) : ($clHash->{hmccu}{$d}{chn}, $v);
		}
		elsif ($f & 5) {
			return 0 if ($v !~ /^[0-9]{1,2}$/);
			($chn, $dpt) = ($v, $clHash->{hmccu}{$d}{dpt});
		}

		return 0 if ($init_done && defined($chn) && $chn ne '' && defined($dpt) && $dpt ne '' &&
			!HMCCU_IsValidDatapoint ($clHash, $clHash->{ccutype}, $chn, $dpt, $f & 3 ? 5 : 2));

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

	return 1;
}

sub HMCCU_SetDefaultSCDatapoints ($$;$)
{
	my ($ioHash, $clHash, $detect) = @_;

	$detect //= HMCCU_DetectDevice ($ioHash, $clHash->{ccuaddr}, $clHash->{ccuif});
	return 0 if (!defined($detect));

	my $si = HMCCU_GetSCInfo ($detect, 0);	# State info
	my $ci = HMCCU_GetSCInfo ($detect, 1);	# Control info
	return 0 if (!defined($si) && !defined($ci));
		
	HMCCU_SetSCDatapoints ($clHash, 'statedatapoint', $detect->{defSDP}, $si->{role});
	HMCCU_SetSCDatapoints ($clHash, 'controldatapoint', $detect->{defCDP}, $ci->{role});

	my $chn = $detect->{defCCh} != -1 ? $detect->{defCCh} : $detect->{defSCh};
	my $dpt = defined($ci) ? $ci->{datapoint} : $si->{datapoint};

	HMCCU_UpdateRoleCommands ($ioHash, $clHash, $chn);
	HMCCU_UpdateAdditionalCommands ($ioHash, $clHash, $chn, $dpt);

	return 1;
}

######################################################################
# Get state and control channel and datapoint of a device.
# Priority depends on FHEM device type:
#
# HMCCUCHN:
# 1. Datapoints from attributes statedatapoint, controldatapoint
# 2. Datapoints by role
#
# HMCCUDEV:
# 1. Attributes statechannel, controlchannel
# 2. Channel from attributes statedatapoint, controldatapoint
# 3. Datapoints from attributes statedatapoint, controldatapoint
# 4. Channel datapoint by role
#
# If controldatapoint is not specified it will synchronized with
# statedatapoint.
#
# Return (sc, sd, cc, cd, sdCnt, cdCnt)
# If sdCnt > 1 or cdCnt > 1 more than 1 matching rules were found
######################################################################

sub HMCCU_GetSCDatapoints ($)
{
	my ($clHash) = @_;

	my $ioHash = HMCCU_GetHash ($clHash);
	my $type = $clHash->{TYPE};

	my $sc = exists($clHash->{hmccu}{state}{chn}) ? $clHash->{hmccu}{state}{chn} : '';
	my $sd = exists($clHash->{hmccu}{state}{dpt}) ? $clHash->{hmccu}{state}{dpt} : '';
	my $cc = exists($clHash->{hmccu}{control}{chn}) ? $clHash->{hmccu}{control}{chn} : '';
	my $cd = exists($clHash->{hmccu}{control}{dpt}) ? $clHash->{hmccu}{control}{dpt} : '';
	my $rsdCnt;
	my $rcdCnt;

	# Detect by attributes
	($sc, $sd, $cc, $cd, $rsdCnt, $rcdCnt) = HMCCU_DetectSCAttr ($clHash, $sc, $sd, $cc, $cd);
	return ($sc, $sd, $cc, $cd, 1, 1) if ($rsdCnt == 1 && $rcdCnt == 1);

	HMCCU_SetDefaultSCDatapoints ($ioHash, $clHash);

	return (
		exists($clHash->{hmccu}{state}{chn}) ? $clHash->{hmccu}{state}{chn} : '',
		exists($clHash->{hmccu}{state}{dpt}) ? $clHash->{hmccu}{state}{dpt} : '',
		exists($clHash->{hmccu}{control}{chn}) ? $clHash->{hmccu}{control}{chn} : '',
		exists($clHash->{hmccu}{control}{dpt}) ? $clHash->{hmccu}{control}{dpt} : '',
		1, 1
	)

	# Detect by role, but do not override values defined as attributes
#	if (defined($clHash->{hmccu}{role}) && $clHash->{hmccu}{role} ne '') {
#		HMCCU_Trace ($clHash, 2, "hmccurole=$clHash->{hmccu}{role}");
	# 	if ($type eq 'HMCCUCHN') {
	# 		($sd, $cd, $rsdCnt, $rcdCnt) = HMCCU_DetectSCChn ($clHash, $sd, $cd);
	# 	}
	# 	elsif ($type eq 'HMCCUDEV') {
	# 		($sc, $sd, $cc, $cd, $rsdCnt, $rcdCnt) = HMCCU_DetectSCDev ($clHash, $sc, $sd, $cc, $cd);
	# 	}
	# }
	
	# if ($rsdCnt == 0 && $rcdCnt == 1 && HMCCU_IsValidDatapoint ($clHash, $clHash->{ccutype}, $cc, $cd, 5)) {
		# Use control datapoint as state datapoint if control datapoint is readable or updated by events
	# 	($sc, $sd) = ($cc, $cd);
	# }
	# elsif ($rsdCnt == 1 && $rcdCnt == 0 && HMCCU_IsValidDatapoint ($clHash, $clHash->{ccutype}, $sc, $sd, 2)) {
	# 	# Use state datapoint as control datapoint if state datapoint is writeable
	# 	($cc, $cd) = ($sc, $sd);
	# }
	
	# Store channels and datapoints in device hash
	# $clHash->{hmccu}{state}{dpt} = $sd;
	# $clHash->{hmccu}{state}{chn} = $sc;
	# $clHash->{hmccu}{control}{dpt} = $cd;
	# $clHash->{hmccu}{control}{chn} = $cc;
	
	# return ($sc, $sd, $cc, $cd, $rsdCnt, $rcdCnt);
}

sub HMCCU_DetectSCAttr ($$$$$)
{
	my ($clHash, $sc, $sd, $cc, $cd) = @_;
	my $name = $clHash->{NAME};
	my $type = $clHash->{TYPE};
	
	my $da;
	my $dc;
	if (exists($clHash->{ccuaddr})) {
		($da, $dc) = HMCCU_SplitChnAddr ($clHash->{ccuaddr});
	}

	$sc = $dc if ($sc eq '');
	$cc = $dc if ($cc eq '');

	my $statedatapoint = AttrVal ($name, 'statedatapoint', '');
	my $controldatapoint = AttrVal ($name, 'controldatapoint', '');
	
	# Attributes controlchannel and statechannel are only valid for HMCCUDEV devices
	if ($type eq 'HMCCUDEV') {
		$sc = AttrVal ($name, 'statechannel', $sc);
		$cc = AttrVal ($name, 'controlchannel', $cc);
	}
	
	# If attribute statedatapoint is specified, use it.
	if ($statedatapoint ne '') {
		if ($statedatapoint =~ /^([0-9]+)\.(.+)$/) {
			# Attribute statechannel overrides channel specification.
			($sc, $sd) = $sc eq '' ? ($1, $2) : ($sc, $2);
		}
		else {
			$sd = $statedatapoint;
			if ($sc eq '') {
				# Try to find state channel (datapoint must be readable or provide events)
				my $c = HMCCU_FindDatapoint ($clHash, $type, -1, $sd, 5);
				$sc = $c if ($c >= 0);
			}
		}
	}

	# If attribute controldatapoint is specified, use it. 
	if ($controldatapoint ne '') {
		if ($controldatapoint =~ /^([0-9]+)\.(.+)$/) {
			# Attribute controlchannel overrides channel specification in controldatapoint
			($cc, $cd) = $cc eq '' ? ($1, $2) : ($cc, $2);
		}
		else {
			$cd = $controldatapoint;
			if ($cc eq '') {
				# Try to find control channel (datapoint must be writeable)
				my $c = HMCCU_FindDatapoint  ($clHash, $type, -1, $cd, 4);
				$cc = $c if ($c >= 0);
			}
		}
	}

	my $rsdCnt = $sc ne '' && $sd ne '' ? 1 : 0;
	my $rcdCnt = $cc ne '' && $cd ne '' ? 1 : 0;
	
	return ($sc, $sd, $cc, $cd, $rsdCnt, $rcdCnt);
}

sub HMCCU_DetectSCChn ($;$$)
{
	my ($clHash, $sd, $cd) = @_;
	$sd //= '';
	$cd //= '';

	my $role = HMCCU_GetChannelRole ($clHash);
	HMCCU_Trace ($clHash, 2, "role=$role");
	
	if ($role ne '' && exists($HMCCU_STATECONTROL->{$role}) && $HMCCU_STATECONTROL->{$role}{F} & 1) {
		my $nsd = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$role}{S}, $clHash->{ccuif});
		my $ncd = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$role}{C}, $clHash->{ccuif});
		HMCCU_Log ($clHash, 2, "statedatapoint of role and attribute do not match")
			if ($nsd ne '' && $sd ne '' && $nsd ne $sd);
		HMCCU_Log ($clHash, 2, "controldatapoint of role and attribute do not match")
			if ($ncd ne '' && $cd ne '' && $ncd ne $cd);
			
		$sd = $nsd if ($nsd ne '' && $sd eq '');
		$cd = $ncd if ($ncd ne '' && $cd eq '');
		$clHash->{ccurolestate} = $role if ($nsd ne '');
		$clHash->{ccurolectrl}  = $role if ($ncd ne '');
	}
	
	return ($sd, $cd, $sd ne '' ? 1 : 0, $cd ne '' ? 1 : 0);
}

sub HMCCU_DetectSCDev ($;$$$$)
{
	my ($clHash, $sc, $sd, $cc, $cd) = @_;
	$sc //= '';
	$sd //= '';
	$cc //= '';
	$cd //= '';

	# Count matching roles to prevent ambiguous definitions 
	my ($rsc, $rsd, $rcc, $rcd) = ('', '', '', '');
	# Priorities
	my ($ccp, $scp) = (0, 0);
	# Number of matching roles
	my $rsdCnt = $sc ne '' && $sd ne '' ? 1 : 0;
	my $rcdCnt = $cc ne '' && $cd ne '' ? 1 : 0;
	
	my $defRole = $HMCCU_DEF_ROLE->{$clHash->{ccusubtype}};
	my $resRole;
	
	foreach my $roleDef (split(',', $clHash->{hmccu}{role})) {
		my ($rc, $role) = split(':', $roleDef);	
		
		next if (!defined($role) || (defined($defRole) && $role ne $defRole));		

		if (defined($role) && exists($HMCCU_STATECONTROL->{$role}) && $HMCCU_STATECONTROL->{$role}{F} & 2) {
			my $nsd = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$role}{S}, $clHash->{ccuif});
			if ($sd eq '' && $nsd ne '') {
				# If state datapoint is defined for this role
				if ($sc ne '' && $rc eq $sc) {
					# If channel of current role matches state channel, use datapoint specified
					# in $HMCCU_STATECONTROL as state datapoint 
					$rsc = $sc;
					$rsd = $nsd;
					$clHash->{ccurolestate} = $role;
					$rsdCnt = 1;
				}
				else {
					# If state channel is not defined or role channel doesn't match state channel,
					# assign state channel and datapoint considering role priority
					if ($HMCCU_STATECONTROL->{$role}{P} > $scp) {
						# Priority of this role is higher than the previous priority
						$scp = $HMCCU_STATECONTROL->{$role}{P};
						$rsc = $rc;
						$rsd = $nsd;
						$rsdCnt = 1;
						$clHash->{ccurolestate} = $role;
					}
					elsif ($HMCCU_STATECONTROL->{$role}{P} == $scp) {
						# Priority of this role is equal to previous priority. We found more
						# than 1 matching roles. We use the first matching role/channel, but count
						# the number of matching roles.
						if ($rsc eq '') {
							$rsc = $rc;
							$rsd = $nsd;
							$clHash->{ccurolestate} = $role;
						}
						$rsdCnt++;
					}
				}
			}
			if ($cd eq '' && $HMCCU_STATECONTROL->{$role}{C} ne '') {
				my $ncd = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$role}{C}, $clHash->{ccuif});
				if ($cc ne '' && $rc eq $cc) {
					$rcc = $cc;
					$rcd = $ncd;
					$clHash->{ccurolectrl} = $role;
					$rcdCnt = 1;
				}
				else {
					# If control channel is not defined or role channel doesn't match control channel,
					# assign control channel and datapoint considering role priority
					if ($HMCCU_STATECONTROL->{$role}{P} > $scp) {
						# Priority of this role is higher than the previous priority
						$scp = $HMCCU_STATECONTROL->{$role}{P};
						$rcc = $rc;
						$rcd = $ncd;
						$rcdCnt = 1;
						$clHash->{ccurolectrl} = $role;
					}
					elsif ($HMCCU_STATECONTROL->{$role}{P} == $scp) {
						# Priority of this role is equal to previous priority. We found more
						# than 1 matching roles. We use the first matching role/channel, but count
						# the number of matching roles.
						if ($rcc eq '') {
							$rcc = $rc;
							$rcd = $ncd;
							$clHash->{ccurolectrl} = $role;
						}
						$rcdCnt++;
					}
				}
			}
		}
	}

	($sc, $sd) = ($rsc, $rsd) if ($rsdCnt > 0 && $sd eq '');
	($cc, $cd) = ($rcc, $rcd) if ($rcdCnt > 0 && $cd eq '');
	
	return ($sc, $sd, $cc, $cd, $rsdCnt, $rcdCnt);
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
#   hash stateRole:   Hash with state roles, key is channel number
#   hash controlRole: Hash with control roles, key is channel number
#   string defMod: Default module 'HMCCUDEV', 'HMCCUCHN' or ''
#   string defAdd: Device address (append channel number fpr HMCCUCHN)
#   int defSCh: Default state channel or -1
#   int defCCh: Default control channel or -1
#   int defSDP: Default state datapoint with channel
#   int defCDP: Default control datapoint with channel
#   int level: Detection level
#     0 = device type not detected
#     1 = device type detected with single known role => HMCCUCHN
#     2 = device detected with multiple identical channels (i.e. switch
#         or remote with more than 1 button) => Multiple HMCCUCHNs
#     3 = device detected with multiple channels with different known
#         roles (i.e. roles KEY and THERMALCONTROL) => HMCCUDEV
#     4 = device type detected with different state and control role
#         (>=2 different channels) => HMCCUDEV
#
# Structure of stateRole / controlRole hashes:
#   int <channel>: Channel number
#   string {<channel>}{role}: Channel role
#   string {<channel>}{datapoint}: State or control datapoint
#   int {<channel>}{priority}: Priority of role/datapoint
######################################################################

sub HMCCU_DetectDevice ($$$)
{
	my ($ioHash, $address, $iface) = @_;

	my @allRoles = ();
	my @stateRoles = ();
	my @controlRoles = ();
	my ($prioState, $prioControl) = (-1, -1);
	my ($devAdd, $devChn) = HMCCU_SplitChnAddr ($address);

	my $devDesc = HMCCU_GetDeviceDesc ($ioHash, $address, $iface);
	if (!defined($devDesc)) {
		HMCCU_Log ($ioHash, 2, "Can't get device description for $address ".stacktraceAsString(undef));
		return undef;
	}

	# Identify known roles
	if ($devDesc->{_addtype} eq 'dev') {
		foreach my $child (split(',', $devDesc->{CHILDREN})) {
			$devDesc = HMCCU_GetDeviceDesc ($ioHash, $child, $devDesc->{_interface}) // next;
			push @allRoles, $devDesc->{TYPE};
			HMCCU_IdentifyRole ($ioHash, $devDesc, $iface, \@stateRoles, \@controlRoles);
		}
	}
	elsif ($devDesc->{_addtype} eq 'chn') {
		HMCCU_IdentifyRole ($ioHash, $devDesc, $iface, \@stateRoles, \@controlRoles);
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
		defSCh => -1, defCCh => -1, defSDP => '', defCDP => '',
		level => 0
	);
	my $p = -1;
	foreach my $sr (@stateRoles) {
		$di{stateRole}{$sr->{channel}}{role}      = $sr->{role};
		$di{stateRole}{$sr->{channel}}{datapoint} = $sr->{datapoint};
		$di{stateRole}{$sr->{channel}}{priority}  = $sr->{priority};
		if ($sr->{priority} > $p) {
			$di{defSCh} = $sr->{channel};
			$p = $sr->{priority};
		}
	}
	$p = -1;
	foreach my $cr (@controlRoles) {
		$di{controlRole}{$cr->{channel}}{role}      = $cr->{role};
		$di{controlRole}{$cr->{channel}}{datapoint} = $cr->{datapoint};
		$di{controlRole}{$cr->{channel}}{priority}  = $cr->{priority};
		if ($cr->{priority} > $p) {
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
			 $cntUniqCtrlRoles > 1 || (
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
			# Type 3: Device with multiple different channels
			$di{defMod} = 'HMCCUDEV';
			$di{defAdd} = $devAdd;
			$di{level} = 3;
			
			# Try to find channel role pattern with 4 channels.
			# If no pattern can be found, default channels depend on role priorities
			my $rolePatterns = HMCCU_DetectRolePattern (\@allRoles,
				'^(?!([A-Z]+_VIRTUAL))([A-Z]+)[A-Z_]+(,\g2_VIRTUAL_[A-Z_]+){3}$', 4, 4);
			if (defined($rolePatterns)) {
				ROLEPATTERN: foreach my $rp (keys %$rolePatterns) {
					my @patternRoles = split(',', $rp);
					my $firstChannel = (split(',', $rolePatterns->{$rp}{i}))[0];
					PATTERNROLE: foreach my $pr (@patternRoles) {
						next ROLEPATTERN if (!exists($HMCCU_STATECONTROL->{$pr}));
					}
					# state/control channel is the first channel with a state/control datapoint
					while (my ($i, $pr) = each @patternRoles) {
						if ($HMCCU_STATECONTROL->{$pr}{S} ne '') {
							$di{defSCh} = $firstChannel+$i;
							last;
						}
					}
					while (my ($i, $pr) = each @patternRoles) {
						if ($HMCCU_STATECONTROL->{$pr}{C} ne '') {
							$di{defCCh} = $firstChannel+$i;
							last;
						}
					}
				}
			}
		}
	}

 	$di{defSDP} = $di{defSCh}.'.'.$di{stateRole}{$di{defSCh}}{datapoint} if ($di{defSCh} != -1);
  	$di{defCDP} = $di{defCCh}.'.'.$di{controlRole}{$di{defCCh}}{datapoint} if ($di{defCCh} != -1);

	return \%di;
}

######################################################################
# Identify a channel role
######################################################################

sub HMCCU_IdentifyRole ($$$$$)
{
	my ($ioHash, $devDesc, $iface, $stateRoles, $controlRoles) = @_;
	
	my $t = $devDesc->{TYPE};		# Channel role

	if (exists($HMCCU_STATECONTROL->{$t})) {
		my ($a, $c) = HMCCU_SplitChnAddr ($devDesc->{ADDRESS});
		my $p = $HMCCU_STATECONTROL->{$t}{P};

		# State datapoint must be readable and/or event
		my $sDP = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$t}{S}, $iface);
		push @$stateRoles, { 'channel' => $c, 'role' => $t, 'datapoint' => $sDP, 'priority' => $p }
			if ($sDP ne '' && HMCCU_IsValidParameter ($ioHash, $devDesc, 'VALUES', $sDP, 5));

		# Control datapoint must be writeable
		my $cDP = HMCCU_DetectSCDatapoint ($HMCCU_STATECONTROL->{$t}{C}, $iface);
		push @$controlRoles, { 'channel' => $c, 'role' => $t, 'datapoint' => $cDP, 'priority' => $p }
			if ($cDP ne ''&& HMCCU_IsValidParameter ($ioHash, $devDesc, 'VALUES', $cDP, 2));
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
	
	for (my $i=$skip; $i<$n; $i++) {
		for (my $patternLen=$minPatternLen; $patternLen<=$maxPatternLen; $patternLen++) {
			my @p = ();
			for (my $j=$i; $j<=$n-$patternLen; $j++) {
				my $k=$j+$patternLen-1;
				my $patStr = join(',',@$roles[$j..$k]);
				push @p, { i => $j, p => $patStr } if ($patStr =~ /$regMatch/);
			}
			my $first = shift @p // next;
			my $cnt = 1;
			foreach my $t (@p) {
				last if ($t->{p} ne $first->{p});
				$cnt++;
			}
			if ($cnt >= $minOcc && !exists($patternList{$first->{p}})) {
				unshift @p, $first;
				$patternList{$first->{p}}{c} = $cnt;
				$patternList{$first->{p}}{i} = join(',',map { $_->{i}; } @p);
			}
		}
	}
	
	return \%patternList;
}

######################################################################
# Return state or control datapoint information
# $mode: 0=State 1=Control
######################################################################

sub HMCCU_GetSCInfo ($$;$)
{
	my ($detect, $mode, $chn) = @_;
	
	$chn //= $mode == 0 ? $detect->{defSCh} : $detect->{defCCh};
	
	if ($chn >= 0) {
		return $detect->{stateRole}{$chn} if (exists($detect->{stateRole}{$chn}) && $mode == 0);
		return $detect->{controlRole}{$chn} if (exists($detect->{controlRole}{$chn}) && $mode == 1);
	}

	return undef;
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
######################################################################

sub HMCCU_IsFlag ($$)
{
	my ($name, $flag) = @_;

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
	
	my $rfdef;
		
	if (HMCCU_IsFlag ($ioHash, 'updGroupMembers') && exists($clHash->{ccutype}) && $clHash->{ccutype} =~ /^HM-CC-VG/) {
		$rfdef = 'name';
	}
	else {
		$rfdef = AttrVal ($ioHash->{NAME}, 'ccudef-readingformat', 'datapoint');
	}

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
	my $url = HMCCU_BuildURL ($io_hash, 'rega');
	my $value;

	HMCCU_Trace ($cl_hash, 2, "URL=$url, cmd=$cmd");

	my $param = { url => $url, timeout => $ccureqtimeout, data => $cmd, method => "POST" };
	$param->{sslargs} = { SSL_verify_mode => 0 };
	my ($err, $response) = HttpUtils_BlockingGet ($param);
	
	if ($err eq '') {
		$value = $response;
		if (defined($value)) {
			$value =~ s/<xml>(.*)<\/xml>//;
			$value =~ s/\r//g;
		}
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
	my $url = HMCCU_BuildURL ($ioHash, 'rega');

	HMCCU_Trace ($clHash, 2, "URL=$url");

	if (defined($cbFunc)) {
		my $param = { url => $url, timeout => $ccureqtimeout, data => $cmd, method => "POST",
			callback => $cbFunc, devhash => $clHash };
		$param->{sslargs} = { SSL_verify_mode => 0 };
		HttpUtils_NonblockingGet ($param);
	}
	else {
		my $param = { url => $url, timeout => $ccureqtimeout, data => $cmd, method => "POST",
			callback => \&HMCCU_HMCommandCB, devhash => $clHash };
		$param->{sslargs} = { SSL_verify_mode => 0 };
		HttpUtils_NonblockingGet ($param);
	}
}

######################################################################
# Default callback function for non blocking CCU request.
######################################################################

sub HMCCU_HMCommandCB ($$$)
{
	my ($param, $err, $data) = @_;
	my $hash = $param->{devhash};

	HMCCU_Log ($hash, 2, "Error during CCU request. $err") if ($err ne '');
	HMCCU_Trace ($hash, 2, "URL=".$param->{url}."<br>Response=$data");
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
######################################################################
 
sub HMCCU_HMScriptExt ($$;$$$)
{
	my ($hash, $hmscript, $params, $cbFunc, $cbParam) = @_;
	my $name = $hash->{NAME};
	my $code = $hmscript;
	my $scrname = '';
	
	if ($hash->{TYPE} ne 'HMCCU') {
		HMCCU_Log ($hash, 2, stacktraceAsString(undef));
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
	
	HMCCU_Trace ($hash, 2, $code);
	
	# Execute script on CCU
	my $url = HMCCU_BuildURL ($hash, 'rega');
	if (defined($cbFunc)) {
		# Non blocking
		my $param = { url => $url, timeout => $ccureqtimeout, data => $code, method => "POST",
			callback => $cbFunc, ioHash => $hash };
		if (defined($cbParam)) {
			foreach my $p (keys %{$cbParam}) { $param->{$p} = $cbParam->{$p}; }
		}
		$param->{sslargs} = { SSL_verify_mode => 0 };
		HttpUtils_NonblockingGet ($param);
		return ''
	}

	# Blocking
	my $param = { url => $url, timeout => $ccureqtimeout, data => $code, method => "POST" };
	$param->{sslargs} = { SSL_verify_mode => 0 };
	my ($err, $response) = HttpUtils_BlockingGet ($param);
	if ($err eq '') {
		$response =~ s/<xml>.*<\/xml>//;
		$response =~ s/\r//g;
		return $response;
	}
	else {
		return HMCCU_LogError ($hash, 2, "HMScript failed. $err");
	}
}

######################################################################
# Bulk update of reading considering attribute substexcl.
######################################################################

sub HMCCU_BulkUpdate ($$$;$)
{
	my ($hash, $reading, $orgval, $subval) = @_;
	$subval //= $orgval;
	
	my $excl = AttrVal ($hash->{NAME}, 'substexcl', '');

	readingsBulkUpdate ($hash, $reading, ($excl ne '' && $reading =~ /$excl/ ? $orgval : $subval));
}

######################################################################
# Get datapoint value from CCU and optionally update reading.
# If parameter noupd is defined and > 0 no readings will be updated.
######################################################################

sub HMCCU_GetDatapoint ($@)
{
	my ($cl_hash, $param, $noupd) = @_;
	my $cl_name = $cl_hash->{NAME};
	my $value = '';

	my $io_hash = HMCCU_GetHash ($cl_hash) // return (-3, $value);
	return (-4, $value) if ($cl_hash->{TYPE} ne 'HMCCU' && $cl_hash->{ccudevstate} eq 'deleted');

	my $readingformat = HMCCU_GetAttrReadingFormat ($cl_hash, $io_hash);
	my $substitute = HMCCU_GetAttrSubstitute ($cl_hash, $io_hash);
	my $ccuget = HMCCU_GetAttribute ($io_hash, $cl_hash, 'ccuget', 'Value');
	my $ccureqtimeout = AttrVal ($io_hash->{NAME}, "ccuReqTimeout", $HMCCU_TIMEOUT_REQUEST);

	my $cmd = '';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($io_hash, $param,
		$HMCCU_FLAG_INTERFACE);
	return (-1, $value) if ($flags != $HMCCU_FLAGS_IACD && $flags != $HMCCU_FLAGS_NCD);

	if ($flags == $HMCCU_FLAGS_IACD) {
		$cmd = 'Write((datapoints.Get("'.$int.'.'.$add.':'.$chn.'.'.$dpt.'")).'.$ccuget.'())';
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$cmd = 'Write((dom.GetObject(ID_CHANNELS)).Get("'.$nam.'").DPByHssDP("'.$dpt.'").'.$ccuget.'())';
		($add, $chn) = HMCCU_GetAddress ($io_hash, $nam);
	}

	HMCCU_Trace ($cl_hash, 2, "CMD=$cmd, param=$param, ccuget=$ccuget");

	$value = HMCCU_HMCommand ($cl_hash, $cmd, 1);

	if (defined($value) && $value ne '' && $value ne 'null') {
		if (!defined($noupd) || $noupd == 0) {
			$value = HMCCU_UpdateSingleDatapoint ($cl_hash, $chn, $dpt, $value);
		}
		else {
			my $svalue = HMCCU_ScaleValue ($cl_hash, $chn, $dpt, $value, 0);	
			$value = HMCCU_Substitute ($svalue, $substitute, 0, $chn, $dpt);
		}
		HMCCU_Trace ($cl_hash, 2, "Value of $chn.$dpt = $value"); 
		return (1, $value);
	}
	else {
		HMCCU_Log ($cl_hash, 1, "Error CMD = $cmd");
		return (-2, '');
	}
}

######################################################################
# Set multiple values of parameter set.
# Parameter params is a hash reference. Keys are parameter names.
# Parameter address must be a device or a channel address.
# If no paramSet is specified, VALUES is used by default.
######################################################################

sub HMCCU_SetMultipleParameters ($$$;$)
{
	my ($clHash, $address, $params, $paramSet) = @_;
	$paramSet //= 'VALUES';
	$address =~ s/:d$//;

	my ($add, $chn) = HMCCU_SplitChnAddr ($address);
	return (-1, undef) if ($paramSet eq 'VALUES' && !defined($chn));
	
	foreach my $p (sort keys %$params) {
		HMCCU_Trace ($clHash, 2, "Parameter=$address.$paramSet.$p Value=$params->{$p}");
		return (-8, undef) if (
			($paramSet eq 'VALUES' && !HMCCU_IsValidDatapoint ($clHash, $clHash->{ccutype}, $chn, $p, 2)) ||
			($paramSet eq 'MASTER' && !HMCCU_IsValidParameter ($clHash, $address, $paramSet, $p))
		);
		$params->{$p} = HMCCU_ScaleValue ($clHash, $chn, $p, $params->{$p}, 1);
	}

	return HMCCU_RPCRequest ($clHash, 'putParamset', $address, $paramSet, $params);
}

######################################################################
# Set multiple datapoints on CCU in a single request.
# Parameter params is a hash reference. Keys are full qualified CCU
# datapoint specifications in format:
#   no.interface.{address|fhemdev}:channelno.datapoint
# Parameter no defines the command order.
# Return value < 0 on error.
######################################################################

sub HMCCU_SetMultipleDatapoints ($$) {
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
	
		HMCCU_Trace ($clHash, 2, "dpt=$p, value=$v");

		# Check client device type and datapoint
		my $clType = $clHash->{TYPE};
		my $ccuType = $clHash->{ccutype};
		return -1 if ($clType ne 'HMCCUCHN' && $clType ne 'HMCCUDEV');
		if (!HMCCU_IsValidDatapoint ($clHash, $ccuType, $chn, $dpt, 2)) {
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

		my $dptType = HMCCU_GetDatapointAttr ($ioHash, $ccuType, $chn, $dpt, 'type');
		$v = "'".$v."'" if (defined($dptType) && $dptType == $HMCCU_TYPE_STRING);
		my $c = '(datapoints.Get("'.$int.'.'.$add.':'.$chn.'.'.$dpt.'")).State('.$v.");\n";

		if ($dpt =~ /$ccuChange/) {
			$cmd .= 'if((datapoints.Get("'.$int.'.'.$add.':'.$chn.'.'.$dpt.'")).Value() != '.$v.") {\n$c}\n";
		}
		else {
			$cmd .= $c;
		}
	}
	
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
# Mode: 0 = Get/Multiply, 1 = Set/Divide
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
	
	# Get parameter definition and min/max values
	my $min;
	my $max;
	my $unit;
	my $ccuaddr = $hash->{ccuaddr};
	$ccuaddr .= ':'.$chnno if ($hash->{TYPE} eq 'HMCCUDEV' && $chnno ne ''); 
	my $paramDef = HMCCU_GetParamDef ($ioHash, $ccuaddr, 'VALUES', $dpt);
	if (defined($paramDef)) {
		$min = $paramDef->{MIN} if (defined($paramDef->{MIN}) && $paramDef->{MIN} ne '');
		$max = $paramDef->{MAX} if (defined($paramDef->{MAX}) && $paramDef->{MAX} ne '');
		$unit = $paramDef->{UNIT};
	}
	else {
		HMCCU_Trace ($hash, 2, "Can't get parameter definion for addr=$hash->{ccuaddr} chn=$chnno");
	}

	# Default values can be overriden by attribute
	my $ccuscaleval = AttrVal ($name, 'ccuscaleval', '');	

	HMCCU_Trace ($hash, 2, "chnno=$chnno, dpt=$dpt, value=$value, mode=$mode");
	
	if ($ccuscaleval ne '') {
		HMCCU_Trace ($hash, 2, "ccuscaleval");
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
		
		HMCCU_Trace ($hash, 2, "Attribute scaled value of $dpt = $value");

		return $value;
	}
	
#	if ($dpt eq 'LEVEL') {
#		my $rv = ($mode == 0) ? HMCCU_Min($value,1.0)*100.0 : HMCCU_Min($value,100.0)/100.0;
#		HMCCU_Trace ($hash, 2, "LEVEL: $rv");
#		return $rv;
## 		return ($mode == 0) ? HMCCU_Min($value,1.0)*100.0 : HMCCU_Min($value,100.0)/100.0;
#	}
	if ($dpt =~ /^RSSI_/) {
		# Subtract 256 from Rega value (Rega bug)
		$value = abs ($value) == 65535 || $value == 0 ? 'N/A' : ($value > 0 ? $value-256 : $value);
	}
	elsif ($dpt =~ /^(P[0-9]_)?ENDTIME/) {
		if ($mode == 0) {
			my $hh = sprintf ("%02d", int($value/60));
			my $mm = sprintf ("%02d", $value%60);
			$value = "$hh:$mm";
		}
		else {
			my ($hh, $mm) = split (':', $value);
			$mm //= 0;
			$value = $hh*60+$mm;
		} 
	}
	elsif (defined($unit) && $unit =~ /^([0-9]+)%$/) {
		my $f = $1;
		$min //= 0;
		$max //= 1.0;
		$value = ($mode == 0) ? HMCCU_MinMax ($value, $min, $max)*$f :
			HMCCU_MinMax($value, $min*$f, $max*$f)/$f;
	}
	
	HMCCU_Trace ($hash, 2, "Auto scaled value of $dpt = $value");
	
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
		$readings{$rn} = HMCCU_FormatReadingValue ($hash, $vardata[2], $vardata[0]);
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
# Update all datapoints / readings of device or channel considering
# attribute ccureadingfilter.
# Parameter $ccuget can be 'State', 'Value' or 'Attr'.
# Return 1 on success, <= 0 on error
######################################################################

sub HMCCU_GetUpdate ($$$)
{
	my ($clHash, $addr, $ccuget) = @_;
	my $name = $clHash->{NAME};
	my $type = $clHash->{TYPE};

	return 1 if (AttrVal ($name, 'disable', 0) == 1);
	my $ioHash = HMCCU_GetHash ($clHash) // return -3;
	return -4 if ($type ne 'HMCCU' && $clHash->{ccudevstate} eq 'deleted');

	my $nam = '';
	my $list = '';
	my $script = '';
	$ccuget = HMCCU_GetAttribute ($ioHash, $clHash, 'ccuget', 'Value') if ($ccuget eq 'Attr');

	if (HMCCU_IsValidChannel ($ioHash, $addr, $HMCCU_FL_ADDRESS)) {
		$nam = HMCCU_GetChannelName ($ioHash, $addr);
		return -1 if ($nam eq '');
		my ($stadd, $stchn) = split (':', $addr);
		my $stnam = HMCCU_GetChannelName ($ioHash, "$stadd:0");
		$list = $stnam eq '' ? $nam : $stnam . "," . $nam;
		$script = '!GetDatapointsByChannel';
	}
	elsif (HMCCU_IsValidDevice ($ioHash, $addr, $HMCCU_FL_ADDRESS)) {
		$nam = HMCCU_GetDeviceName ($ioHash, $addr);
		return -1 if ($nam eq '');
		$script = '!GetDatapointsByDevice';

		# Consider members of group device
		if ($type eq 'HMCCUDEV' && $clHash->{ccuif} eq 'VirtualDevices' && HMCCU_IsFlag ($ioHash, 'updGroupMembers') &&
			exists($clHash->{ccugroup}) && $clHash->{ccugroup} ne '') {
			foreach my $gd (split (',', $clHash->{ccugroup})) {
				$nam = HMCCU_GetDeviceName ($ioHash, $gd);
				$list .= ','.$nam if ($nam ne '');
			}
		}
	}
	else {
		return -1;
	}

	if (HMCCU_IsFlag ($ioHash->{NAME}, 'nonBlocking')) {
		# Non blocking request
		HMCCU_HMScriptExt ($ioHash, $script, { list => $list, ccuget => $ccuget },
			\&HMCCU_UpdateCB);
		return 1;
	}
	
	# Blocking request
	my $response = HMCCU_HMScriptExt ($ioHash, $script,
		{ list => $list, ccuget => $ccuget });
	HMCCU_Trace ($clHash, 2, "Addr=$addr Name=$nam Script=$script<br>".
		"Script response = \n".$response);
	return -2 if ($response eq '' || $response =~ /^ERROR:.*/);

	HMCCU_UpdateCB ({ ioHash => $ioHash }, undef, $response);
	return 1;
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
	my $logcount = exists($param->{logCount}) && $param->{logCount} == 1 ? 1 : 0;
	
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
		next if (!defined($dpt));
		my ($add, $chn) = ('', '');
		if ($iface eq 'sysvar' && $chnadd eq 'link') {
			($add, $chn) = HMCCU_GetAddress ($hash, $chnname);
		}
		else {
			($add, $chn) = HMCCU_SplitChnAddr ($chnadd);
		}
		next if ($chn eq '');
		$events{$add}{$chn}{VALUES}{$dpt} = $value;
	}
	
	my $c_ok = HMCCU_UpdateMultipleDevices ($hash, \%events);
	my $c_err = exists($param->{devCount}) ? HMCCU_Max($param->{devCount}-$c_ok, 0) : 0;
	HMCCU_Log ($hash, 2, "Update success=$c_ok failed=$c_err") if ($logcount);
}

######################################################################
# Execute RPC request
# Parameters:
#  $method - RPC request method. Use listParamset or listRawParamset
#     as an alias for getParamset if readings should not be updated.
#  $address  - Device address.
#  $paramset - paramset name: VALUE, MASTER, LINK, ... If not defined
#              request does not affect a parameter set
#  $parref   - Hash reference with parameter/value pairs or array
#              reference with parameter values (optional).
#  $filter   - Regular expression for filtering response (default = .*).
# Return (retCode, result).
#  retCode = 0 - Success
#  retCode < 0 - Error, result contains error message
######################################################################

sub HMCCU_RPCRequest ($$$$;$$)
{
	my ($clHash, $method, $address, $paramset, $parref, $filter) = @_;
	$filter //= '.*';
	my $name = $clHash->{NAME};
	my $type = $clHash->{TYPE};

	my $reqMethod = $method eq 'listParamset' || $method eq 'listRawParamset' ||
		$method eq 'getRawParamset' ? 'getParamset' : $method;
	my $addr = '';
	my $result = '';
	
	my $ioHash = HMCCU_GetHash ($clHash) // return (-3, $result);
	return (-4, $result) if ($type ne 'HMCCU' && $clHash->{ccudevstate} eq 'deleted');

	# Get flags and attributes
	my $ioFlags = HMCCU_GetFlags ($ioHash->{NAME});
	my $clFlags = HMCCU_GetFlags ($name);
	my $ccureadings = AttrVal ($name, 'ccureadings', $clFlags =~ /noReadings/ ? 0 : 1);
	my $readingformat = HMCCU_GetAttrReadingFormat ($clHash, $ioHash);
	my $substitute = HMCCU_GetAttrSubstitute ($clHash, $ioHash);
	
	# Parse address, complete address information
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($ioHash, $address,
		$HMCCU_FLAG_FULLADDR);
	return (-1, $result) if (!($flags & $HMCCU_FLAG_ADDRESS));
	$addr = $flags & $HMCCU_FLAG_CHANNEL ? "$add:$chn" : $add;

	# Get RPC type and port for interface of device address
	my ($rpcType, $rpcPort) = HMCCU_GetRPCServerInfo ($ioHash, $int, 'type,port');
	return (-9, '') if (!defined($rpcType) || !defined($rpcPort));

	# Search RPC device, do not create one
	my ($rpcDevice, $save) = HMCCU_GetRPCDevice ($ioHash, 0, $int);
	return (-17, $result) if ($rpcDevice eq '');
	my $rpcHash = $defs{$rpcDevice};
	
	# Build parameter array: (Address, Paramset [, Parameter ...])
	# Paramset := VALUE | MASTER | LINK or any paramset supported by device
	# Parameter := Name=Value[:Type]
	my @parArray = ($addr);
	push (@parArray, $paramset) if (defined($paramset));
	if (defined($parref)) {
		if (ref($parref) eq 'HASH') {
			foreach my $k (keys %{$parref}) {
				my ($pv, $pt) = split (':', $parref->{$k});
				if (!defined($pt)) {
					my $paramDef = HMCCU_GetParamDef ($ioHash, $addr, $paramset, $k);
					$pt = defined($paramDef) && defined($paramDef->{TYPE}) && $paramDef->{TYPE} ne '' ?
						$paramDef->{TYPE} : 'STRING';
				}
				$pv .= ":$pt";
				push @parArray, "$k=$pv";
			}
		}
		elsif (ref($parref) eq 'ARRAY') {
			push @parArray, @$parref;
		}
	}
	
	# Submit RPC request
	my $reqResult = HMCCURPCPROC_SendRequest ($rpcHash, $reqMethod, @parArray) //
		return (-5, 'RPC function not available');
	
	HMCCU_Trace ($clHash, 2, 
		"Dump of RPC request $method $paramset $addr. Result type=".ref($reqResult)."<br>".
		HMCCU_RefToString ($reqResult));	

	my $parCount = 0;
	if (ref($reqResult) eq 'HASH') {
		if (exists($reqResult->{faultString})) {
			HMCCU_Log ($rpcHash, 1, "Error in request $reqMethod ".join(' ', @parArray).': '.
				$reqResult->{faultString});
			return (-2, $reqResult->{faultString});
		}
		else {
			$parCount = keys %{$reqResult};
		}
	}
#	else {
#		return (-2, defined ($RPC::XML::ERROR) ? $RPC::XML::ERROR : 'RPC request failed');
#	}	

	if ($method eq 'listParamset') {
		$result = join ("\n", map { $_ =~ /$filter/ ? $_.'='.$reqResult->{$_} : () } keys %$reqResult);
	}
	elsif ($method eq 'listRawParamset' || $method eq 'getRawParamset') {
		$result = $reqResult;
	}
	elsif ($method eq 'getDeviceDescription') {
		$result = '';
		foreach my $k (sort keys %$reqResult) {
			if (ref($reqResult->{$k}) eq 'ARRAY') {
				$result .= "$k=".join(',', @{$reqResult->{$k}})."\n";
			}
			else {
				$result .= "$k=".$reqResult->{$k}."\n";
			}
		}
	}
	elsif ($method eq 'getParamsetDescription') {
		my %operFlags = ( 1 => 'R', 2 => 'W', 4 => 'E' );
		$result = join ("\n", 
			map {
				$_.': '.
				$reqResult->{$_}->{TYPE}.
				" [".HMCCU_BitsToStr(\%operFlags,$reqResult->{$_}->{OPERATIONS})."]".
				" FLAGS=".sprintf("%#b", $reqResult->{$_}->{FLAGS}).
				" RANGE=".$reqResult->{$_}->{MIN}."-".$reqResult->{$_}->{MAX}.
				" DFLT=".$reqResult->{$_}->{DEFAULT}.
				" UNIT=".$reqResult->{$_}->{UNIT}
			} sort keys %$reqResult);		
	}
	else {
		$result = $reqResult;
	}
	
	return (0, $result);
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

######################################################################
# Convert string from ISO-8859-1 to UTF-8
######################################################################

sub HMCCU_ISO2UTF ($)
{
	my ($t) = @_;
	
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

######################################################################
# Get device state from maintenance channel 0
# Update corresponding readings.
# Default is unknown for each reading
######################################################################

sub HMCCU_UpdateDeviceStates ($)
{
	my ($clHash) = @_;
	
	# Datapoints related to reading 'devstate'
	my %stName = (
		'0.CONFIG_PENDING'       => 'cfgPending',
		'0.DEVICE_IN_BOOTLOADER' => 'boot',
		'0.STICKY_UNREACH'       => 'stickyUnreach',
		'0.UPDATE_PENDING'       => 'updPending',
	);
	
	# Datapoints to be converted to readings
	my %newReadings = (
		'0.AES_KEY'     => 'sign',
		'0.RSSI_DEVICE' => 'rssidevice',
		'0.RSSI_PEER'   => 'rssipeer',
		'0.LOW_BAT'     => 'battery',
		'0.LOWBAT'      => 'battery',
		'0.UNREACH'     => 'activity'
	);
	
	# The new readings
	my %readings = ();
	
	if (exists($clHash->{hmccu}{dp})) {
		# Create the new readings
		foreach my $dp (keys %newReadings) {
			if (exists($clHash->{hmccu}{dp}{$dp}) && exists($clHash->{hmccu}{dp}{$dp}{VALUES})) {
				if (exists($clHash->{hmccu}{dp}{$dp}{VALUES}{SVAL})) {
					$readings{$newReadings{$dp}} = $clHash->{hmccu}{dp}{$dp}{VALUES}{SVAL};
				}
				elsif (exists($clHash->{hmccu}{dp}{$dp}{VALUES}{VAL})) {
					$readings{$newReadings{$dp}} = $clHash->{hmccu}{dp}{$dp}{VALUES}{VAL};
				}
			}
		}
		
		# Calculate the device state Reading
		my @states = ();
		foreach my $dp (keys %stName) {
			push @states, $stName{$dp} if (exists($clHash->{hmccu}{dp}{$dp}) &&
				exists($clHash->{hmccu}{dp}{$dp}{VALUES}) &&
				defined($clHash->{hmccu}{dp}{$dp}{VALUES}{VAL}) &&
				$clHash->{hmccu}{dp}{$dp}{VALUES}{VAL} =~ /^(1|true)$/);
		}
		$readings{devstate} = scalar(@states) > 0 ? join(',', @states) : 'ok';
		
		HMCCU_UpdateReadings ($clHash, \%readings, 2);
	}
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
# Get minimum or maximum of 2 values
# Align value with boundaries
######################################################################

sub HMCCU_Min ($$)
{
	my ($a, $b) = @_;
	
	return $a < $b ? $a : $b;
}

sub HMCCU_Max ($$)
{
	my ($a, $b) = @_;
	
	return $a > $b ? $a : $b;
}

sub HMCCU_MinMax ($$$)
{
	my ($v, $min, $max) = @_;
	$min = $v if (!defined($min) || $min eq '');
	$max = $min if (!defined($max) || $max eq '');

	return HMCCU_Max (HMCCU_Min ($v, $max), $min);
}

######################################################################
# Build ReGa or RPC client URL
# Parameter backend specifies type of URL, 'rega' or name or port of
# RPC interface.
# Return empty string on error.
######################################################################

sub HMCCU_BuildURL ($$)
{
	my ($hash, $backend) = @_;
	my $name = $hash->{NAME};
	
	my $url = '';
	my $username = '';
	my $password = '';
	my ($erruser, $encuser) = getKeyValue ($name.'_username');
	my ($errpass, $encpass) = getKeyValue ($name.'_password');	
	if (!defined($erruser) && !defined($errpass) && defined($encuser) && defined($encpass)) {
		$username = HMCCU_Decrypt ($encuser);
		$password = HMCCU_Decrypt ($encpass);
	}
	my $auth = ($username ne '' && $password ne '') ? "$username:$password".'@' : '';
		
	if ($backend eq 'rega') {
		$url = $hash->{prot}."://$auth".$hash->{host}.':'.
			$HMCCU_REGA_PORT{$hash->{prot}}.'/tclrega.exe';
	}
	else {
		($url) = HMCCU_GetRPCServerInfo ($hash, $backend, 'url');
		if (defined($url)) {
			if (exists($HMCCU_RPC_SSL{$backend})) {
				my $p = $hash->{prot} eq 'https' ? '4' : '';
 				$url =~ s/^http:\/\//$hash->{prot}:\/\/$auth/;
				$url =~ s/:([0-9]+)/:$p$1/;
			}
		}
		else {
			$url = '';
		}
	}
	
	HMCCU_Log ($hash, 4, "Build URL = $url");
	return $url;
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

sub HMCCU_DeleteReadings ($$)
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
		my ($par, $val) = split (':', $tok);
		next if (!defined($val));
		if    ($par =~ /^text([1-3])$/)                 { $text[$1-1] = substr ($val, 0, 12); }
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

sub HMCCU_RefToString ($)
{
	my ($r) = @_;
	
	if (ref($r) eq 'ARRAY') {
		my $result = "[\n";
		foreach my $e (@$r) {
			$result .= ',' if ($result ne '[');
			$result .= HMCCU_RefToString ($e);
		}
		return "$result\n]";
	}
	elsif (ref($r) eq 'HASH') {
		my $result .= "{\n";
		foreach my $k (sort keys %$r) {
			$result .= ',' if ($result ne '{');
			$result .= "$k=".HMCCU_RefToString ($r->{$k});
		}
		return "$result\n}";
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
	my ($value, $low, $high);
	
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
	my %readings;
	
	foreach my $port (values %$interfaces) {
		next if ($port != 2001 && $port != 2010);
		my $url = HMCCU_BuildURL ($hash, $port) // next;
		my $rpcclient = RPC::XML::Client->new ($url);
		my $response = $rpcclient->simple_request ('listBidcosInterfaces');
		next if (!defined($response) || ref($response) ne 'ARRAY');
		foreach my $iface (@$response) {
			next if (ref($iface) ne 'HASH' || !exists($iface->{DUTY_CYCLE}));
			$dc++;
			my ($type) = exists($iface->{TYPE}) ?
				($iface->{TYPE}) : HMCCU_GetRPCServerInfo ($hash, $port, 'name');
			$readings{"iface_addr_$dc"} = $iface->{ADDRESS};
			$readings{"iface_conn_$dc"} = $iface->{CONNECTED};
			$readings{"iface_type_$dc"} = $type;
			$readings{"iface_ducy_$dc"} = $iface->{DUTY_CYCLE};
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

	my @ipseg = split (/\./, $ip);
	return scalar(@ipseg) == 4 ? sprintf ("%03d%03d", $ipseg[2], $ipseg[3]) : $default;
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

1;


=pod
=item device
=item summary provides interface between FHEM and Homematic CCU2
=begin html

<a name="HMCCU"></a>
<h3>HMCCU</h3>
<ul>
   The module provides an interface between FHEM and a Homematic CCU2. HMCCU is the 
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
      <li>Start RPC servers with command 'set rpcserver on'</li>
      <li>Optionally enable automatic start of RPC servers with attribute 'rpcserver'</li>
      </ul><br/>
      Then start with the definition of client devices using modules HMCCUDEV (CCU devices)
      and HMCCUCHN (CCU channels) or with command 'get create'.<br/>
   </ul>
   <br/>
   
   <a name="HMCCUset"></a>
   <b>Set</b><br/><br/>
   <ul>
      <li><b>set &lt;name&gt; ackmessages</b><br/>
      	Acknowledge "device was unreachable" messages in CCU.
      </li><br/>
      <li><b>set &lt;name&gt; authentication [&lt;username&gt; &lt;password&gt;]</b><br/>
      	Set credentials for CCU authentication. Authentication must be activated by setting flag
      	'authenticate' in attribute 'ccuflags'.<br/>
      	When executing this command without arguments, the credentials are deleted.
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
      <li><b>set &lt;name&gt; prgActivate &lt;program&gt;</b><br/>
         Activate a CCU program.
      </li><br/>
      <li><b>set &lt;name&gt; prgDeactivate &lt;program&gt;</b><br/>
         Deactivate a CCU program.
      </li><br/>
      <li><b>set &lt;name&gt; rpcregister [{all | &lt;interface&gt;}]</b><br/>
      	Register RPC servers at CCU.
      </li><br/>
      <li><b>set &lt;name&gt; rpcserver {on | off | restart}</b><br/>
         Start, stop or restart RPC server(s). This command executed with option 'on'
         will fork a RPC server process for each RPC interface defined in attribute 'rpcinterfaces'.
         Until operation is completed only a few set/get commands are available and you
         may get the error message 'CCU busy'.
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
      <li><b>get &lt;name&gt; firmware [{&lt;type-expr&gt; | full}]</b><br/>
      	Get available firmware downloads from eq-3.de. List FHEM devices with current and available
      	firmware version. By default only firmware version of defined HMCCUDEV or HMCCUCHN
      	devices are listet. With option 'full' all available firmware versions are listed.
      	With parameter <i>type-expr</i> one can filter displayed firmware versions by 
      	Homematic device type.
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
      <li><b>get &lt;name&gt; updateccu [&lt;devexp&gt; [{State | <u>Value</u>}]]</b><br/>
         Update all datapoints / readings of client devices with <u>CCU device name</u>(!) matching
         <i>devexp</i>. With option 'State' all CCU devices are queried directly. This can be
         time consuming.
      </li><br/>
      <li><b>get &lt;name&gt; vars &lt;regexp&gt;</b><br/>
         Get CCU system variables matching <i>regexp</i> and store them as readings.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUattr"></a>
   <b>Attributes</b><br/>
   <br/>
   <ul>
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
		<li><b>ccudef-attributes {&lt;attrName&gt;=&lt;attrValue&gt;[;...] | none}</b><br/>
			Define attributes which are assigned to newly defined HMCCUDEV or HMCCUCHN devices. By default the following
			attributes will be assigned:<br/>
			room=Homematic<br/>
			If attribute is set to 'none', no attributes will be assigned to new devices.
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
      	noEvents - Ignore events / device updates sent by CCU. No readings will be updated!<br/>
      	noInitialUpdate - Do not update datapoints of devices after RPC server start. Overrides 
      	settings in RPC devices.
      	nonBlocking - Use non blocking (asynchronous) CCU requests<br/>
      	noReadings - Do not create or update readings<br/>
      	procrpc - Use external RPC server provided by module HMCCPRPCPROC. During first RPC
      	server start HMCCU will create a HMCCURPCPROC device for each interface confiugured
      	in attribute 'rpcinterface'<br/>
      	reconnect - Automatically reconnect to CCU when events timeout occurred.<br/>
      	updGroupMembers - Update readings of group members in virtual devices.
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than
         'Value' because each request is sent to the device. With method 'Value' only CCU
         is queried. Default is 'Value'. Method for write access to datapoints is always
         'State'.
      </li><br/>
      <li><b>ccuGetVars &lt;interval&gt;[&lt;pattern&gt;]</b><br/>
      	Read CCU system variables periodically and update readings. If pattern is specified
      	only variables matching this expression are stored as readings.
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


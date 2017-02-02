##############################################################################
#
#  88_HMCCU.pm
#
#  $Id$
#
#  Version 3.9.002
#
#  Module for communication between FHEM and Homematic CCU2.
#  Supports BidCos-RF, BidCos-Wired, HmIP-RF, virtual CCU channels,
#  CCU group devices.
#
#  (c) 2016 zap (zap01 <at> t-online <dot> de)
#
##############################################################################
#
#  define <name> HMCCU <hostname_or_ip_of_ccu>
#
#  set <name> cleardefaults
#  set <name> defaults
#  set <name> execute <ccu_program>
#  set <name> importdefaults <filename>
#  set <name> hmscript <hm_script_file>
#  set <name> rpcserver {on|off|restart}
#  set <name> var <value> [...]
#
#  get <name> aggregation {<rule>|all}
#  get <name> configdesc {<device>|<channel>}
#  get <name> defaults
#  get <name> deviceinfo <device>
#  get <name> devicelist [dump]
#  get <name> devicelist create <devexp> [t={chn|dev|all}] [s=<suffix>]
#                                        [p=<prefix>] [f=<format>]
#                                        [defattr] [<attr>=<val> [...]]}]
#  get <name> dump {devtypes|datapoints} [<filter>]
#  get <name> exportdefaults {filename}
#  get <name> parfile [<parfile>]
#  get <name> rpcevents
#  get <name> rpcstate
#  get <name> update [<fhemdevexp> [{ State | Value }]]
#  get <name> updateccu [<devexp> [{ State | Value }]]
#  get <name> vars <regexp>
#
#  attr <name> ccuackstate { 0 | 1 }
#  attr <name> ccuaggregate <rules>
#  attr <name> ccudef-hmstatevals <subst_rules>
#  attr <name> ccudef-readingfilter <filter_rule>
#  attr <name> ccudef-readingname <rules>
#  attr <name> ccudef-substitute <subst_rule>
#  attr <name> ccudefaults <filename>
#  attr <name> ccuflags { intrpc,extrpc,dptnocheck,noagg }
#  attr <name> ccuget { State | Value }
#  attr <name> ccureadingfilter <filter_rule>
#  attr <name> ccureadingformat { name[lc] | address[lc] | datapoint[lc] }
#  attr <name> ccureadings { 0 | 1 }
#  attr <name> ccutrace {<ccudevname_exp>|<ccudevaddr_exp>}
#  attr <name> parfile <parfile>
#  attr <name> rpcevtimeout <seconds>
#  attr <name> rpcinterfaces { BidCos-Wired, BidCos-RF, HmIP-RF, VirtualDevices, Homegear }
#  attr <name> rpcinterval <seconds>
#  attr <name> rpcport <ccu_rpc_port>
#  attr <name> rpcqueue <file>
#  attr <name> rpcserver { on | off }
#  attr <name> rpcserveraddr <ip-or-name>
#  attr <name> rpcserverport <base_port>
#  attr <name> rpctimeout <read>[,<write>]
#  attr <name> stripchar <character>
#  attr <name> stripnumber { 0 | 1 | 2 }
#  attr <name> substitute <subst_rule>
#
#  filter_rule := [channel-regexp!]datapoint-regexp[,...]
#  subst_rule := [[channel.]datapoint[,...]!]<regexp>:<subtext>[,...][;...]
##############################################################################
#  Verbose levels:
#
#  0 = Log start/stop and initialization messages
#  1 = Log errors
#  2 = Log counters and warnings
#  3 = Log events and runtime information
##############################################################################

package main;

no if $] >= 5.017011, warnings => 'experimental::smartmatch';

use strict;
use warnings;
# use Data::Dumper;
# use Time::HiRes qw(usleep);
use IO::File;
use Fcntl 'SEEK_END', 'SEEK_SET', 'O_CREAT', 'O_RDWR';
use RPC::XML::Client;
use RPC::XML::Server;
use SetExtensions;
use SubProcess;
use HMCCUConf;

# Import configuration data
my $HMCCU_CHN_DEFAULTS = \%HMCCUConf::HMCCU_CHN_DEFAULTS;
my $HMCCU_DEV_DEFAULTS = \%HMCCUConf::HMCCU_DEV_DEFAULTS;

# Custom configuration data
my %HMCCU_CUST_CHN_DEFAULTS;
my %HMCCU_CUST_DEV_DEFAULTS;

# HMCCU version
my $HMCCU_VERSION = '3.9.002';

# RPC Ports and URL extensions
my %HMCCU_RPC_NUMPORT = (
	2000 => 'BidCos-Wired', 2001 => 'BidCos-RF', 2010 => 'HmIP-RF', 9292 => 'VirtualDevices',
	2003 => 'Homegear'
);
my %HMCCU_RPC_PORT = (
   'BidCos-Wired', 2000, 'BidCos-RF', 2001, 'HmIP-RF', 2010, 'VirtualDevices', 9292,
   'Homegear', 2003
);
my %HMCCU_RPC_URL = (
	9292, 'groups'
);

# Initial intervals for registration of RPC callbacks and reading RPC queue
#
# X                      = Start RPC server
# X+HMCCU_INIT_INTERVAL1 = Register RPC callback
# X+HMCCU_INIT_INTERVAL2 = Read RPC Queue
#
my $HMCCU_INIT_INTERVAL0 = 12;
my $HMCCU_INIT_INTERVAL1 = 7;
my $HMCCU_INIT_INTERVAL2 = 5;

# Number of arguments in RPC events
my %rpceventargs = (
	"EV", 3,
	"ND", 2,
	"DD", 1,
	"RD", 2,
	"RA", 1,
	"UD", 2,
	"IN", 3,
	"EX", 3,
	"SL", 2,
	"ST", 10
);

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
my $HMCCU_FLAGS_IAC = $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_ADDRESS |
	$HMCCU_FLAG_CHANNEL;
my $HMCCU_FLAGS_ACD = $HMCCU_FLAG_ADDRESS | $HMCCU_FLAG_CHANNEL |
	$HMCCU_FLAG_DATAPOINT;
my $HMCCU_FLAGS_AC = $HMCCU_FLAG_ADDRESS | $HMCCU_FLAG_CHANNEL;
my $HMCCU_FLAGS_ND = $HMCCU_FLAG_NAME | $HMCCU_FLAG_DATAPOINT;
my $HMCCU_FLAGS_NC = $HMCCU_FLAG_NAME | $HMCCU_FLAG_CHANNEL;
my $HMCCU_FLAGS_NCD = $HMCCU_FLAG_NAME | $HMCCU_FLAG_CHANNEL |
	$HMCCU_FLAG_DATAPOINT;

# Declare functions
sub HMCCU_Initialize ($);
sub HMCCU_Define ($$);
sub HMCCU_Undef ($$);
sub HMCCU_Shutdown ($);
sub HMCCU_Set ($@);
sub HMCCU_Get ($@);
sub HMCCU_Attr ($@);
sub HMCCU_AggregationRules ($$);
sub HMCCU_ExportDefaults ($);
sub HMCCU_ImportDefaults ($);
sub HMCCU_FindDefaults ($$);
sub HMCCU_SetDefaults ($);
sub HMCCU_GetDefaults ($$);
sub HMCCU_Notify ($$);
sub HMCCU_AggregateReadings ($$);
sub HMCCU_ParseObject ($$$);
sub HMCCU_FilterReading ($$$);
sub HMCCU_GetReadingName ($$$$$$$);
sub HMCCU_FormatReadingValue ($$);
sub HMCCU_SetError ($$);
sub HMCCU_SetState ($$);
sub HMCCU_Substitute ($$$$$);
sub HMCCU_SubstRule ($$$);
sub HMCCU_SubstVariables ($$);
sub HMCCU_UpdateClients ($$$$);
sub HMCCU_UpdateClientReading ($@);
sub HMCCU_AddDevices ($$);
sub HMCCU_DeleteDevices ($$);
sub HMCCU_RPCRegisterCallback ($);
sub HMCCU_RPCDeRegisterCallback ($);
sub HMCCU_ResetCounters ($);
sub HMCCU_StartExtRPCServer ($);
sub HMCCU_StartIntRPCServer ($);
sub HMCCU_StopRPCServer ($);
sub HMCCU_IsRPCStateBlocking ($);
sub HMCCU_IsRPCServerRunning ($$$);
sub HMCCU_CheckProcess ($$);
sub HMCCU_GetDeviceInfo ($$$);
sub HMCCU_FormatDeviceInfo ($);
sub HMCCU_GetDeviceList ($);
sub HMCCU_GetDatapointList ($);
sub HMCCU_FindDatapoint ($$$$$);
sub HMCCU_GetAddress ($$$$);
sub HMCCU_IsDevAddr ($$);
sub HMCCU_IsChnAddr ($$);
sub HMCCU_SplitChnAddr ($);
sub HMCCU_GetCCUObjectAttribute ($$$);
sub HMCCU_FindIODevice ($);
sub HMCCU_GetHash ($@);
sub HMCCU_GetAttribute ($$$$);
sub HMCCU_GetDatapointCount ($$$);
sub HMCCU_GetSpecialDatapoints ($$$$$);
sub HMCCU_GetAttrReadingFormat ($$);
sub HMCCU_GetAttrSubstitute ($$);
sub HMCCU_IsValidDeviceOrChannel ($$);
sub HMCCU_IsValidDevice ($$);
sub HMCCU_IsValidChannel ($$);
sub HMCCU_GetCCUDeviceParam ($$);
sub HMCCU_GetValidDatapoints ($$$$$);
sub HMCCU_GetSwitchDatapoint ($$$);
sub HMCCU_IsValidDatapoint ($$$$$);
sub HMCCU_GetMatchingDevices ($$$$);
sub HMCCU_GetDeviceName ($$$);
sub HMCCU_GetChannelName ($$$);
sub HMCCU_GetDeviceType ($$$);
sub HMCCU_GetDeviceChannels ($$$);
sub HMCCU_GetDeviceInterface ($$$);
sub HMCCU_ResetRPCQueue ($$);
sub HMCCU_ReadRPCQueue ($);
sub HMCCU_ProcessEvent ($$);
sub HMCCU_HMScript ($$);
sub HMCCU_UpdateSingleReading ($$$$$);
sub HMCCU_BulkUpdate ($$$$);
sub HMCCU_GetDatapoint ($@);
sub HMCCU_SetDatapoint ($$$);
sub HMCCU_ScaleValue ($$$$);
sub HMCCU_GetVariables ($$);
sub HMCCU_SetVariable ($$$);
sub HMCCU_GetUpdate ($$$);
sub HMCCU_UpdateDeviceReadings ($$);
sub HMCCU_GetChannel ($$);
sub HMCCU_RPCGetConfig ($$$$);
sub HMCCU_RPCSetConfig ($$$);

# File queue functions
sub HMCCU_QueueOpen ($$);
sub HMCCU_QueueClose ($);
sub HMCCU_QueueReset ($);
sub HMCCU_QueueEnq ($$);
sub HMCCU_QueueDeq ($);

# Helper functions
sub HMCCU_GetHMState ($$$);
sub HMCCU_AggReadings ($$$$$);
sub HMCCU_GetTimeSpec ($);
sub HMCCU_Dewpoint ($$$$);
sub HMCCU_CalculateReading ($$$);
sub HMCCU_EncodeEPDisplay ($);

# Subprocess functions
sub HMCCU_CCURPC_Write ($$);
sub HMCCU_CCURPC_OnRun ($);
sub HMCCU_CCURPC_OnExit ();
sub HMCCU_CCURPC_NewDevicesCB ($$$);
sub HMCCU_CCURPC_DeleteDevicesCB ($$$);
sub HMCCU_CCURPC_UpdateDeviceCB ($$$$);
sub HMCCU_CCURPC_ReplaceDeviceCB ($$$$);
sub HMCCU_CCURPC_ReaddDevicesCB ($$$);
sub HMCCU_CCURPC_EventCB ($$$$$);
sub HMCCU_CCURPC_ListDevicesCB ($$);
sub HMCCU_CCURPC_GetEventsCB ($$);


##################################################
# Initialize module
##################################################

sub HMCCU_Initialize ($)
{
	my ($hash) = @_;

	$hash->{DefFn} = "HMCCU_Define";
	$hash->{UndefFn} = "HMCCU_Undef";
	$hash->{SetFn} = "HMCCU_Set";
	$hash->{GetFn} = "HMCCU_Get";
	$hash->{ReadFn} = "HMCCU_Read";
	$hash->{AttrFn} = "HMCCU_Attr";
	$hash->{NotifyFn} = "HMCCU_Notify";
	$hash->{ShutdownFn} = "HMCCU_Shutdown";
	$hash->{parseParams} = 1;

	$hash->{AttrList} = "stripchar stripnumber ccuackstate:0,1 ccuaggregate:textField-long ccudefaults rpcinterfaces:multiple-strict,".join(',',sort keys %HMCCU_RPC_PORT)." ccudef-hmstatevals:textField-long ccudef-substitute:textField-long ccudef-readingname:textField-long ccudef-readingfilter:textField-long ccudef-readingformat:name,namelc,address,addresslc,datapoint,datapointlc  ccuflags:multiple-strict,intrpc,dptnocheck,noagg,nohmstate ccureadings:0,1 ccureadingfilter ccureadingformat:name,namelc,address,addresslc,datapoint,datapointlc rpcinterval:2,3,5,7,10 rpcqueue rpcport:multiple-strict,".join(',',sort keys %HMCCU_RPC_NUMPORT)." rpcserver:on,off rpcserveraddr rpcserverport rpctimeout rpcevtimeout parfile substitute ccutrace ccuget:Value,State ". $readingFnAttributes;
}

##################################################
# Define device
##################################################

sub HMCCU_Define ($$)
{
	my ($hash, $a, $h) = @_;
	my $name = $hash->{NAME};

	return "Specify CCU hostname or IP address as a parameter" if(@$a < 3);
	
	$hash->{host} = $$a[2];
	$hash->{Clients} = ':HMCCUDEV:HMCCUCHN:';

	# Find existing CCU devices
	my $ccucount = 0;
	foreach my $d (keys %defs) {
		my $ch = $defs{$d};
		next if (!exists ($ch->{TYPE}));
		$ccucount++ if ($ch->{TYPE} eq 'HMCCU' && $ch != $hash);
	}
	
	$hash->{CCUNum} = $ccucount+1;
	$hash->{version} = $HMCCU_VERSION;
	$hash->{ccutype} = 'CCU2';
	$hash->{DevCount} = HMCCU_GetDeviceList ($hash);
	$hash->{NewDevices} = 0;
   $hash->{DelDevices} = 0;
	$hash->{RPCState} = "stopped";
	
	$hash->{hmccu}{evtime} = 0;
	$hash->{hmccu}{evtimeout} = 0;
	$hash->{hmccu}{updatetime} = 0;
	$hash->{hmccu}{rpccount} = 0;
	$hash->{hmccu}{rpcports} = '2001';

	readingsBeginUpdate ($hash);
	readingsBulkUpdate ($hash, "state", "Initialized");
	readingsBulkUpdate ($hash, "rpcstate", "stopped");
	readingsEndUpdate ($hash, 1);

	$attr{$name}{stateFormat} = "rpcstate/state";
	
	return undef;
}

#####################################
# Set attribute
#####################################

sub HMCCU_Attr ($@)
{
	my ($cmd, $name, $attrname, $attrval) = @_;
	my $hash = $defs{$name};
	my $rc = 0;

	if ($cmd eq 'set') {
		if ($attrname eq 'ccudefaults') {
			$rc = HMCCU_ImportDefaults ($attrval);
			return HMCCU_SetError ($hash, -16) if ($rc == 0);
			if ($rc < 0) {
				$rc = -$rc;
				return HMCCU_SetError ($hash,
					"Syntax error in default attribute file $attrval line $rc");
			}
		}
		elsif ($attrname eq 'ccuaggregate') {
			$rc = HMCCU_AggregationRules ($hash, $attrval);
			return HMCCU_SetError ($hash, "Syntax error in attribute ccuaggregate") if ($rc == 0);
		}
		elsif ($attrname eq 'rpcinterfaces') {
			my @ports = split (',', $attrval);
			my @plist = ();
			foreach my $p (@ports) {
				return "Illegal RPC interface $p" if (!exists ($HMCCU_RPC_PORT{$p}));
				push (@plist, $HMCCU_RPC_PORT{$p});
			}
			return "No RPC interface specified" if (scalar (@plist) == 0);
			$hash->{hmccu}{rpcports} = join (',', @plist);
			$attr{$name}{"rpcport"} = $hash->{hmccu}{rpcports};
		}
		elsif ($attrname eq 'rpcport') {
			my @ports = split (',', $attrval);
			my @ilist = ();
			foreach my $p (@ports) {
				return "Illegal RPC port $p" if (!exists ($HMCCU_RPC_NUMPORT{$p}));
				push (@ilist, $HMCCU_RPC_NUMPORT{$p});
			}
			return "No RPC port specified" if (scalar (@ilist) == 0);
			$hash->{hmccu}{rpcports} = $attrval;
			$attr{$name}{"rpcinterfaces"} = join (',', @ilist);
		}
	}
	elsif ($cmd eq 'del') {
		if ($attrname eq 'ccuaggregate') {
			HMCCU_AggregationRules ($hash, '');			
		}
		elsif ($attrname eq 'rpcport' || $attrname eq 'rpcinterfaces') {
			$hash->{hmccu}{rpcports} = '2001';
		}
	}
	
	return undef;
}

######################################################################
# Parse aggregation rules for readings.
# Syntax of aggregation rule is:
# FilterSpec[;...]
# FilterSpec := {Name|Filt|Read|Cond|Else|Pref|Coll}[,...]
# Name := name:Name
# Filt := filter:{name|type|group|room|alias}=Regexp[!Regexp]
# Read := read:Regexp
# Cond := if:{any|all|min|max|sum|avg|gt|lt|ge|le}=Value
# Else := else:Value
# Pref := prefix:{RULE|Prefix}
# Coll := coll:{NAME|Attribute}
######################################################################

sub HMCCU_AggregationRules ($$)
{
	my ($hash, $rulestr) = @_;
	my $name = $hash->{NAME};

	# Delete existing aggregation rules
	if (exists ($hash->{hmccu}{agg})) {
		delete $hash->{hmccu}{agg};
	}
	return if ($rulestr eq '');
	
	my @opts = ('name', 'filter', 'if', 'else');

	# Extract aggregation rules
	my $cnt = 0;
	my @rules = split (/[;\n]+/, $rulestr);
	foreach my $r (@rules) {
		$cnt++;
		
		# Set default rule parameters
		my %opt = (
			'read' => 'state',
			prefix => 'RULE',
			coll   => 'NAME'
		);

		# Parse aggregation rule
		my @specs = split (',', $r);		
		foreach my $spec (@specs) {
			if ($spec =~ /^(name|filter|read|if|else|prefix|coll):(.+)$/) {
				$opt{$1} = $2;
			}
		}
		
		# Check if rule syntax is correct
		foreach my $o (@opts) {
			if (!exists ($opt{$o})) {
				Log3 $name, 1, "HMCCU: Parameter $o is missing in aggregation rule $cnt.";
				return 0;
			}
		}
		
		my $fname = $opt{name};
		my ($fincl, $fexcl) = split ('!', $opt{filter});
		my ($ftype, $fexpr) = split ('=', $fincl);
		return 0 if (!defined ($fexpr));
		my ($fcond, $fval) = split ('=', $opt{if});
		return 0 if (!defined ($fval));
		my ($fcoll, $fdflt) = split ('!', $opt{coll});
		$fdflt = 'no match' if (!defined ($fdflt));

		$hash->{hmccu}{agg}{$fname}{ftype} = $ftype;
		$hash->{hmccu}{agg}{$fname}{fexpr} = $fexpr;
		$hash->{hmccu}{agg}{$fname}{fexcl} = (defined ($fexcl) ? $fexcl : '');
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

#####################################
# Export default attributes.
#####################################

sub HMCCU_ExportDefaults ($)
{
	my ($filename) = @_;

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

	close (DEFFILE);

	return 1;
}

#####################################
# Import customer default attributes
# Returns 1 on success. Returns
# negative line number on syntax
# errors. Returns 0 on file open
# error.
#####################################
 
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

#####################################
# Find default attributes
# Return template reference.
#####################################

sub HMCCU_FindDefaults ($$)
{
	my ($hash, $common) = @_;
	my $type = $hash->{TYPE};
	my $ccutype = $hash->{ccutype};

	if ($type eq 'HMCCUCHN') {
		my ($adr, $chn) = split (':', $hash->{ccuaddr});

		if ($common) {
			return \%{$HMCCU_CUST_CHN_DEFAULTS{COMMON}} if (exists ($HMCCU_CUST_CHN_DEFAULTS{COMMON}));
			return \%{$HMCCU_CHN_DEFAULTS->{COMMON}} if (exists ($HMCCU_CHN_DEFAULTS->{COMMON}));
		}
		
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
		if ($common) {
			return \%{$HMCCU_CUST_DEV_DEFAULTS{COMMON}} if (exists ($HMCCU_CUST_DEV_DEFAULTS{COMMON}));
			return \%{$HMCCU_DEV_DEFAULTS->{COMMON}} if (exists ($HMCCU_DEV_DEFAULTS->{COMMON}));
		}

		foreach my $deftype (keys %HMCCU_CUST_DEV_DEFAULTS) {
			return \%{$HMCCU_CUST_DEV_DEFAULTS{$deftype}} if ($ccutype =~ /^($deftype)$/i);
		}

		foreach my $deftype (keys %{$HMCCU_DEV_DEFAULTS}) {
			return \%{$HMCCU_DEV_DEFAULTS->{$deftype}} if ($ccutype =~ /^($deftype)$/i);
		}
	}

	return undef;	
}

############################################################
# Set default attributes from template
############################################################

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

############################################################
# Set default attributes
############################################################

sub HMCCU_SetDefaults ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# Set common attributes
	my $template = HMCCU_FindDefaults ($hash, 1);
	HMCCU_SetDefaultsTemplate ($hash, $template) if (defined ($template));

	# Set type specific attributes	
	$template = HMCCU_FindDefaults ($hash, 0);
	return 0 if (!defined ($template));
	
	HMCCU_SetDefaultsTemplate ($hash, $template);
	return 1;
}

############################################################
# List default attributes for device type (mode = 0) or all
# device types (mode = 1) with default attributes available.
############################################################

sub HMCCU_GetDefaults ($$)
{
	my ($hash, $mode) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $ccutype = $hash->{ccutype};
	my $result = '';
	my $deffile = '';
	
# 	my $template = HMCCU_FindDefaults ($hash, 1);
# 	if (defined ($template)) {
# 		foreach my $a (keys %{$template}) {
# 			next if ($a =~ /^_/);
# 			my $v = $template->{$a};
# 			$result .= $a." = ".$v."\n";
# 		}
# 	}
	
	if ($mode == 0) {
		my $template = HMCCU_FindDefaults ($hash, 0);
		return ($result eq '' ? "No default attributes defined" : $result) if (!defined ($template));
	
		foreach my $a (keys %{$template}) {
			next if ($a =~ /^_/);
			my $v = $template->{$a};
			$result .= $a." = ".$v."\n";
		}
	}
	else {
		$result = "HMCCU Channels:\n------------------------------\n";
		foreach my $deftype (sort keys %{$HMCCU_CHN_DEFAULTS}) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_CHN_DEFAULTS->{$deftype}{_description}." ($tlist), channels ".
				$HMCCU_CHN_DEFAULTS->{$deftype}{_channels}."\n";
		}
		$result .= "\nHMCCU Devices:\n------------------------------\n";
		foreach my $deftype (sort keys %{$HMCCU_DEV_DEFAULTS}) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_DEV_DEFAULTS->{$deftype}{_description}." ($tlist)\n";
		}
		$result .= "\nCustom Channels:\n-----------------------------\n";
		foreach my $deftype (sort keys %HMCCU_CUST_CHN_DEFAULTS) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_CUST_CHN_DEFAULTS{$deftype}{_description}." ($tlist), channels ".
				$HMCCU_CUST_CHN_DEFAULTS{$deftype}{_channels}."\n";
		}
		$result .= "\nCustom Devices:\n-----------------------------\n";
		foreach my $deftype (sort keys %HMCCU_CUST_DEV_DEFAULTS) {
			my $tlist = $deftype;
			$tlist =~ s/\|/,/g;
			$result .= $HMCCU_CUST_DEV_DEFAULTS{$deftype}{_description}." ($tlist)\n";
		}
	}
	
	return $result;	
}

############################################################
# Handle FHEM events
############################################################

sub HMCCU_Notify ($$)
{
	my ($hash, $devhash) = @_;
	my $name = $hash->{NAME};
	my $devname = $devhash->{NAME};
	my $devtype = $devhash->{TYPE};

	my $disable = AttrVal ($name, 'disable', 0);
	my $rpcserver = AttrVal ($name, 'rpcserver', 'off');
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	return if ($disable);
		
	my $events = deviceEvents ($devhash, 1);
	return if (! $events);

	# Process events
	foreach my $event (@{$events}) {	
		if ($devname eq 'global') {
			if ($event eq 'INITIALIZED') {
				return if ($rpcserver eq 'off');
				my $delay = $HMCCU_INIT_INTERVAL0;
				Log3 $name, 0, "HMCCU: Start of RPC server after FHEM initialization in $delay seconds";
				if ($ccuflags =~ /extrpc/) {
					InternalTimer (gettimeofday()+$delay, "HMCCU_StartExtRPCServer", $hash, 0);
				}
				else {
					InternalTimer (gettimeofday()+$delay, "HMCCU_StartIntRPCServer", $hash, 0);
				}
			}
		}
		else {
			return if ($devtype ne 'HMCCUDEV' && $devtype ne 'HMCCUCHN');
			my ($r, $v) = split (": ", $event);
			return if (!defined ($v));
			my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
			return if ($ccuflags =~ /noagg/);

			foreach my $rule (keys %{$hash->{hmccu}{agg}}) {
				my $ftype = $hash->{hmccu}{agg}{$rule}{ftype};
				my $fexpr = $hash->{hmccu}{agg}{$rule}{fexpr};
				my $fread = $hash->{hmccu}{agg}{$rule}{fread};
				next if ($r !~ $fread);
				next if ($ftype eq 'name' && $devname !~ /$fexpr/);
				next if ($ftype eq 'type' && $devhash->{ccutype} !~ /$fexpr/);
				next if ($ftype eq 'group' && AttrVal ($devname, 'group', 'null') !~ /$fexpr/);
				next if ($ftype eq 'room' && AttrVal ($devname, 'room', 'null') !~ /$fexpr/);
				next if ($ftype eq 'alias' && AttrVal ($devname, 'alias', 'null') !~ /$fexpr/);
			
				HMCCU_AggregateReadings ($hash, $rule);
			}
		}
	}

	return;
}

#####################################
# Calculate reading aggregation
#####################################

sub HMCCU_AggregateReadings ($$)
{
	my ($hash, $rule) = @_;
	
	my $dc = 0;
	my $mc = 0;
	my $result = '';
	my $rl = '';

	# Get rule parameters
	my $ftype = $hash->{hmccu}{agg}{$rule}{ftype};
	my $fexpr = $hash->{hmccu}{agg}{$rule}{fexpr};
	my $fexcl = $hash->{hmccu}{agg}{$rule}{fexcl};
	my $fread = $hash->{hmccu}{agg}{$rule}{fread};
#	my $fcoll = $hash->{hmccu}{agg}{$rule}{fcoll};
	my $fcond = $hash->{hmccu}{agg}{$rule}{fcond};
	my $ftrue = $hash->{hmccu}{agg}{$rule}{ftrue};
	my $felse = $hash->{hmccu}{agg}{$rule}{felse};
	my $fpref = $hash->{hmccu}{agg}{$rule}{fpref};

	my $resval;
	$resval = $ftrue if ($fcond =~ /^(max|min|sum|avg)$/);
	
	foreach my $d (keys %defs) {
		# Get device parameters and check device type
		my $ch = $defs{$d};
		next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
		my $cn = $ch->{NAME};
		my $ct = $ch->{TYPE};
		next if ($ct ne 'HMCCUCHN' && $ct ne 'HMCCUDEV');
		
		my $fmatch = '';
		$fmatch = $cn if ($ftype eq 'name');
		$fmatch = $ch->{ccutype} if ($ftype eq 'type');
		$fmatch = AttrVal ($cn, 'group', '') if ($ftype eq 'group');
		$fmatch = AttrVal ($cn, 'room', '') if ($ftype eq 'room');
		$fmatch = AttrVal ($cn, 'alias', '') if ($ftype eq 'alias');		
		next if ($fmatch eq '' || $fmatch !~ /$fexpr/ || ($fexcl ne '' && $fmatch =~ /$fexcl/));
		
		my $fcoll = $hash->{hmccu}{agg}{$rule}{fcoll} eq 'NAME' ?
			$cn : AttrVal ($cn, $hash->{hmccu}{agg}{$rule}{fcoll}, $cn);
		
		# Compare readings
		my $f = 0;
		foreach my $r (keys %{$ch->{READINGS}}) {
			next if ($r !~ /$fread/);
			my $rv = $ch->{READINGS}{$r}{VAL};
			if (($fcond eq 'any' || $fcond eq 'all') && $rv =~ /$ftrue/) {
				$mc++;
				$rl .= ($mc > 1 ? ",$fcoll" : $fcoll);
				last;
			}
			if ($fcond eq 'max' && $rv > $resval) {
				$resval = $rv;
				$mc = 1;
				$rl = $fcoll;
				last;
			}
			if ($fcond eq 'min' && $rv < $resval) {
				$resval = $rv;
				$mc = 1;
				$rl = $fcoll;
				last;
			}
			if ($fcond eq 'sum' || $fcond eq 'avg') {
				$resval += $rv;
				$mc++;
				$f = 1;
				last;
			}
			if (($fcond eq 'gt' && $rv > $ftrue) ||
			    ($fcond eq 'lt' && $rv < $ftrue) ||
			    ($fcond eq 'ge' && $rv >= $ftrue) ||
			    ($fcond eq 'le' && $rv <= $ftrue)) {
				$mc++;
				$rl .= ($mc > 1 ? ",$fcoll" : $fcoll);
				last;
			}
		}
		$dc++;
	}
	
	$rl =  $hash->{hmccu}{agg}{$rule}{fdflt} if ($rl eq '');
	if ($fcond eq 'any') {
		$result = $mc > 0 ? $ftrue : $felse;
	}
	elsif ($fcond eq 'all') {
		$result = $mc == $dc ? $ftrue : $felse;
	}
	elsif ($fcond eq 'min' || $fcond eq 'max' || $fcond eq 'sum') {
		$result = $mc > 0 ? $resval : $felse;
	}
	elsif ($fcond eq 'avg') {
		$result = $mc > 0 ? $resval/$mc : $felse;
	}
	elsif ($fcond =~ /^(gt|lt|ge|le)$/) {
		$result = $mc;
	}
	
	# Set readings
	readingsBeginUpdate ($hash);
	readingsBulkUpdate ($hash, $fpref.'state', $result);
	readingsBulkUpdate ($hash, $fpref.'match', $mc);
	readingsBulkUpdate ($hash, $fpref.'count', $dc);
	readingsBulkUpdate ($hash, $fpref.'list', $rl);
	readingsEndUpdate ($hash, 1);
	
	return $result;
}

#####################################
# Delete device
#####################################

sub HMCCU_Undef ($$)
{
	my ($hash, $arg) = @_;

	# Shutdown RPC server
	HMCCU_Shutdown ($hash);

	# Delete reference to IO module in client devices
	my @keylist = sort keys %defs;
	foreach my $d (@keylist) {
		if (exists ($defs{$d}) && exists($defs{$d}{IODev}) &&
		    $defs{$d}{IODev} == $hash) {
        		delete $defs{$d}{IODev};
		}
	}

	return undef;
}

#####################################
# Shutdown FHEM
#####################################

sub HMCCU_Shutdown ($)
{
	my ($hash) = @_;

	# Shutdown RPC server
	HMCCU_StopRPCServer ($hash);
	RemoveInternalTimer ($hash);

	return undef;
}

#####################################
# Set commands
#####################################

sub HMCCU_Set ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;
	my $options = "var execute hmscript cleardefaults:noArg defaults:noArg importdefaults rpcserver:on,off,restart";
	my $host = $hash->{host};

	if ($opt ne 'rpcserver' && HMCCU_IsRPCStateBlocking ($hash)) {
		HMCCU_SetState ($hash, "busy");
		return "HMCCU: CCU busy, choose one of rpcserver:off";
	}

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $stripchar = AttrVal ($name, "stripchar", '');
#	my ($sc, $statedatapoint, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');
#	my $statevals = AttrVal ($name, "statevals", '');
	my $ccureadings = AttrVal ($name, "ccureadings", 1);
	my $readingformat = HMCCU_GetAttrReadingFormat ($hash, $hash);
	my $substitute = HMCCU_GetAttrSubstitute ($hash, $hash);

	if ($opt eq 'var') {
		my $objname = shift @$a;
		my $objvalue = shift @$a;
		my $result;

		return HMCCU_SetError ($hash, "Usage: set $name $opt {ccuobject} {value}")
			if (!defined ($objname) || !defined ($objvalue));

		$objname =~ s/$stripchar$// if ($stripchar ne '');
		$objvalue =~ s/\\_/%20/g;

		$result = HMCCU_SetVariable ($hash, $objname, $objvalue);

		return HMCCU_SetError ($hash, $result) if ($result < 0);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq "execute") {
		my $program = shift @$a;
		my $response;

		return HMCCU_SetError ($hash, "Usage: set $name execute {program-name}")
			if (!defined ($program));

		my $url = qq(http://$host:8181/do.exe?r1=dom.GetObject("$program").ProgramExecute());
		$response = GetFileFromURL ($url);
		$response =~ m/<r1>(.*)<\/r1>/;
		my $value = $1;
		if (defined ($value) && $value ne '' && $value ne 'null') {
			return HMCCU_SetState ($hash, "OK");
		}
		else {
			return HMCCU_SetError ($hash, "Program execution error");
		}
	}
	elsif ($opt eq 'hmscript') {
		my $scrfile = shift @$a;
		my $dump = shift @$a;
		my $script;
		my $response;

		return HMCCU_SetError ($hash, "Usage: set $name hmscript {scriptfile} [dump] [parname=value [...]]")
			if (!defined ($scrfile) || (defined ($dump) && $dump ne 'dump'));
			
		if (open (SCRFILE, "<$scrfile")) {
			my @lines = <SCRFILE>;
			$script = join ("\n", @lines);
			close (SCRFILE);
		}
		else {
			return HMCCU_SetError ($hash, -16);
		}

		# Replace variables
		foreach my $svar (keys %{$h}) {
			next if ($script !~ /\$$svar/);
			$script =~ s/\$$svar/$h->{$svar}/g;
		}
		
		$response = HMCCU_HMScript ($hash, $script);
		return HMCCU_SetError ($hash, -2) if ($response eq '');

		HMCCU_SetState ($hash, "OK");
		return $response if (! $ccureadings);

		foreach my $line (split /\n/, $response) {
			my @tokens = split /=/, $line;
			next if (@tokens != 2);
			my $reading;
			my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hash, $tokens[0],
				$HMCCU_FLAG_INTERFACE);
			($add, $chn) = HMCCU_GetAddress ($hash, $nam, '', '') if ($flags == $HMCCU_FLAGS_NCD);
			if ($flags == $HMCCU_FLAGS_IACD || $flags == $HMCCU_FLAGS_NCD) {
#				$reading = HMCCU_GetReadingName ($hash, $int, $add, $chn, $dpt, $nam, $readingformat);
				HMCCU_UpdateClientReading ($hash, $add, $chn, $dpt, $tokens[1]);
			}
			else {
				my $Value = HMCCU_Substitute ($tokens[1], $substitute, 0, undef, $tokens[0]);
				readingsSingleUpdate ($hash, $tokens[0], $Value, 1);
			}
		}

		return defined ($dump) ? $response : undef;
	}
	elsif ($opt eq 'rpcserver') {
		my $action = shift @$a;

		return HMCCU_SetError ($hash, "Usage: set $name rpcserver {on|off|restart}")
		   if (!defined ($action) || $action !~ /^(on|off|restart)$/);
		   
		if ($action eq 'on') {
			if ($ccuflags =~ /extrpc/) {
				return HMCCU_SetError ($hash, "Start of RPC server failed")
				   if (!HMCCU_StartExtRPCServer ($hash));
			}
			else {
				return HMCCU_SetError ($hash, "Start of RPC server failed")
				   if (!HMCCU_StartIntRPCServer ($hash));
			}
		}
		elsif ($action eq 'off') {
			return HMCCU_SetError ($hash, "Stop of RPC server failed")
			   if (!HMCCU_StopRPCServer ($hash));
		}
		elsif ($action eq 'restart') {
			my @hm_pids;
			my @ex_pids;
			return "HMCCU: RPC server not running"
			   if (!HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids));
			return "HMCCU: Can't stop RPC server" if (!HMCCU_StopRPCServer ($hash));

			$hash->{RPCState} = "restarting";
			readingsSingleUpdate ($hash, "rpcstate", "restarting", 1);
			DoTrigger ($name, "RPC server restarting");
		}
		
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'defaults') {
		my $rc = HMCCU_SetDefaults ($hash);
		return HMCCU_SetError ($hash, "HMCCU: No default attributes found") if ($rc == 0);
		return HMCCU_SetState ($hash, "OK");
	}
	elsif ($opt eq 'cleardefaults') {
		%HMCCU_CUST_CHN_DEFAULTS = ();
		%HMCCU_CUST_DEV_DEFAULTS = ();
		
		return "Default attributes deleted";
	}
	elsif ($opt eq 'importdefaults') {
		my $filename = shift @$a;

		return HMCCU_SetError ($hash, "Usage: set $name importdefaults {filename}")
			if (!defined ($filename));
			
		my $rc = HMCCU_ImportDefaults ($filename);
		return HMCCU_SetError ($hash, -16) if ($rc == 0);
		if ($rc < 0) {
			$rc = -$rc;
			return HMCCU_SetError ($hash, "Syntax error in default attribute file $filename line $rc");
		}
		
		HMCCU_SetState ($hash, "OK");
		return "Default attributes read from file $filename";
	}
	else {
		return "HMCCU: Unknown argument $opt, choose one of ".$options;
	}
}

#####################################
# Get commands
#####################################

sub HMCCU_Get ($@)
{
	my ($hash, $a, $h) = @_;
	my $name = shift @$a;
	my $opt = shift @$a;
	my $options = "defaults:noArg exportdefaults devicelist dump vars update updateccu parfile configdesc rpcevents:noArg rpcstate:noArg deviceinfo";
	my $host = $hash->{host};

	if ($opt ne 'rpcstate' && HMCCU_IsRPCStateBlocking ($hash)) {
		HMCCU_SetState ($hash, "busy");
		return "HMCCU: CCU busy, choose one of rpcstate:noArg";
	}

	my $ccureadingformat = HMCCU_GetAttrReadingFormat ($hash, $hash);
	my $ccureadings = AttrVal ($name, "ccureadings", 1);
	my $parfile = AttrVal ($name, "parfile", '');
#	my ($sc, $statedatapoint, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');
#	my $substitute = AttrVal ($name, 'substitute', '');
#	my $rpcport = AttrVal ($name, 'rpcport', 2001);
	my $rpcport = $hash->{hmccu}{rpcports};

	my $readname;
	my $readaddr;
	my $result = '';
	my $rc;

	if ($opt eq 'dump') {
		my $content = shift @$a;
		my $filter = shift @$a;
		$filter = '.*' if (!defined ($filter));
		
		my %foper = (1, "R", 2, "W", 4, "E", 3, "RW", 5, "RE", 6, "WE", 7, "RWE");
		my %ftype = (2, "B", 4, "F", 16, "I", 20, "S");
		
		return HMCCU_SetError ($hash, "Usage: get $name dump {datapoints|devtypes} [filter]")
		   if (!defined ($content));
		
		if ($content eq 'devtypes') {
			foreach my $devtype (sort keys %{$hash->{hmccu}{dp}}) {
				$result .= $devtype."\n" if ($devtype =~ /$filter/);
			}
		}
		elsif ($content eq 'datapoints') {
			foreach my $devtype (sort keys %{$hash->{hmccu}{dp}}) {
				next if ($devtype !~ /$filter/);
				foreach my $chn (sort keys %{$hash->{hmccu}{dp}{$devtype}{ch}}) {
					foreach my $dpt (sort keys %{$hash->{hmccu}{dp}{$devtype}{ch}{$chn}}) {
						my $t = $hash->{hmccu}{dp}{$devtype}{ch}{$chn}{$dpt}{type};
						my $o = $hash->{hmccu}{dp}{$devtype}{ch}{$chn}{$dpt}{oper};
						$result .= $devtype.".".$chn.".".$dpt." [".
						   (exists($ftype{$t}) ? $ftype{$t} : $t)."] [".
						   (exists($foper{$o}) ? $foper{$o} : $o)."]\n";
					}
				}
			}
		}
		else {
			return HMCCU_SetError ($hash, "Usage: get $name dump {datapoints|devtypes} [{filter}]");
		}
		
		return "No data found" if ($result eq '');
		return $result;
	}
	elsif ($opt eq 'vars') {
		my $varname = shift @$a;

		return HMCCU_SetError ($hash, "Usage: get $name vars {regexp}[,...]")
		   if (!defined ($varname));

		($rc, $result) = HMCCU_GetVariables ($hash, $varname);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'update' || $opt eq 'updateccu') {
		my $devexp = shift @$a;
		$devexp = '.*' if (!defined ($devexp));
		my $ccuget = shift @$a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		return HMCCU_SetError ($hash, "Usage: get $name $opt [device-expr [{'State'|'Value'}]]")
			if ($ccuget !~ /^(Attr|State|Value)$/);

		my ($c_ok, $c_err) = HMCCU_UpdateClients ($hash, $devexp, $ccuget,
			($opt eq 'updateccu') ? 1 : 0);

		HMCCU_SetState ($hash, "OK");
		return "$c_ok client devices successfully updated. Update for $c_err client devices failed";
	}
	elsif ($opt eq 'parfile') {
		my $par_parfile = shift @$a;
		my @parameters;
		my $parcount;

		if (defined ($par_parfile)) {
			$parfile = $par_parfile;
		}
		else {
			return HMCCU_SetError ($hash, "No parameter file specified") if ($parfile eq '');
		}

		# Read parameter file
		if (open (PARFILE, "<$parfile")) {
			@parameters = <PARFILE>;
			$parcount = scalar @parameters;
			close (PARFILE);
		}
		else {
			return HMCCU_SetError ($hash, -16);
		}

		return HMCCU_SetError ($hash, "Empty parameter file") if ($parcount < 1);

		($rc, $result) = HMCCU_GetChannel ($hash, \@parameters);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'deviceinfo') {
		my $device = shift @$a;

		return HMCCU_SetError ($hash, "Usage: get $name deviceinfo {device} [{'State'|'Value'}]")
		   if (!defined ($device));

		my $ccuget = shift @$a;
		$ccuget = 'Attr' if (!defined ($ccuget));
		return HMCCU_SetError ($hash, "Usage: get $name deviceinfo {device} [{'State'|'Value'}]")
		   if ($ccuget !~ /^(Attr|State|Value)$/);

		return HMCCU_SetError ($hash, -1) if (!HMCCU_IsValidDeviceOrChannel ($hash, $device));
		$result = HMCCU_GetDeviceInfo ($hash, $device, $ccuget);
		return HMCCU_SetError ($hash, -2) if ($result eq '');
		return HMCCU_FormatDeviceInfo ($result);
	}
	elsif ($opt eq 'rpcevents') {
		return HMCCU_SetError ($hash, "No event statistics available")
		   if (!exists ($hash->{hmccu}{evs}) || !exists ($hash->{hmccu}{evr}));
		foreach my $stkey (sort keys %{$hash->{hmccu}{evr}}) {
			$result .= "S: ".$stkey." = ".$hash->{hmccu}{evs}{$stkey}."\n";
			$result .= "R: ".$stkey." = ".$hash->{hmccu}{evr}{$stkey}."\n";
		}
		return $result;
	}
	elsif ($opt eq 'rpcstate') {
		my @pidlist;
		foreach my $port (split (',', $rpcport)) {
			my $pid = HMCCU_CheckProcess ($hash, $port);
			push (@pidlist, $pid) if ($pid > 0);
		}
		return "RPC process(es) running with pid(s) ".join (',', @pidlist) if (@pidlist > 0);
		return "RPC process not running";
	}
	elsif ($opt eq 'devicelist') {
		$hash->{DevCount} = HMCCU_GetDeviceList ($hash);
		return HMCCU_SetError ($hash, -2) if ($hash->{DevCount} < 0);
		return HMCCU_SetError ($hash, "No devices received from CCU") if ($hash->{DevCount} == 0);
		$result = "Read ".$hash->{DevCount}." devices/channels from CCU";

		my $optcmd = shift @$a;
		if (defined ($optcmd)) {
			if ($optcmd eq 'dump') {
				$result .= "\n-----------------------------------------\n";
				my $n = 0;
				foreach my $add (sort keys %{$hash->{hmccu}{dev}}) {
					if ($hash->{hmccu}{dev}{$add}{addtype} eq 'dev') {
						$result .= "Device ".'"'.$hash->{hmccu}{dev}{$add}{name}.'"'." [".$add."] ".
							"Type=".$hash->{hmccu}{dev}{$add}{type}."\n";
						$n = 0;
					}
					else {
						$result .= "  Channel $n ".'"'.$hash->{hmccu}{dev}{$add}{name}.'"'." [".$add."]\n";
						$n++;
					}
				}
				return $result;
			}
			elsif ($optcmd eq 'create') {
				my $devprefix = exists ($h->{p}) ? $h->{p} : '';
				my $devsuffix = exists ($h->{'s'}) ? $h->{'s'} : '';
				my $devtype = exists ($h->{t}) ? $h->{t} : 'dev';
				my $devformat = exists ($h->{f}) ? $h->{f} : '%n';
				my $devdefaults = 0;
				my $newcount = 0;
				my @devattr;
				
				my $devspec = shift @$a;
				return "Please specify expression for CCU device or channel names"
					if (!defined ($devspec));

				foreach my $defopt (@$a) {
					if ($defopt eq 'defattr') {
						$devdefaults = 1;
					}
					else {
						push (@devattr, $defopt);
					}
				}
				
				foreach my $add (sort keys %{$hash->{hmccu}{dev}}) {
					my $defmod = $hash->{hmccu}{dev}{$add}{addtype} eq 'dev' ? 'HMCCUDEV' : 'HMCCUCHN';
					my $ccuname = $hash->{hmccu}{dev}{$add}{name};	
					my $ccudevname = HMCCU_GetDeviceName ($hash, $add, $ccuname);
					next if ($devtype ne 'all' && $devtype ne $hash->{hmccu}{dev}{$add}{addtype});
					next if ($ccuname !~ /$devspec/);
					my $devname = $devformat;
					$devname = $devprefix.$devname.$devsuffix;
					$devname =~ s/%n/$ccuname/g;
					$devname =~ s/%d/$ccudevname/g;
					$devname =~ s/%a/$add/g;
					$devname =~ s/[^A-Za-z\d_\.]+/_/g;
					my $ret = CommandDefine (undef, $devname." $defmod ".$add);
					if ($ret) {
						Log3 $name, 2, "HMCCU: Define command failed $devname $defmod $ccuname";
						Log3 $name, 2, "$defmod: $ret";
						next;
					}
					HMCCU_SetDefaults ($defs{$devname}) if ($devdefaults);
					foreach my $da (@devattr) {
						my ($at, $vl) = split ('=', $da);
						CommandAttr (undef, "$devname $at $vl") if (defined ($vl));
					}
					Log3 $name, 2, "$defmod: Created device $devname";
					$newcount++;
				}
				
				$result .= ", created $newcount client devices";
			}
		}

		HMCCU_SetState ($hash, "OK");
		return $result;
	}
	elsif ($opt eq 'defaults') {
		$result = HMCCU_GetDefaults ($hash, 1);
		return $result;
	}
	elsif ($opt eq 'exportdefaults') {
		my $filename = shift @$a;
		
		return HMCCU_SetError ($hash, "Usage: get $name exportdefaults {filename}")
			if (!defined ($filename));
		
		my $rc = HMCCU_ExportDefaults ($filename);
		return HMCCU_SetError ($hash, -16) if ($rc == 0);
		
		HMCCU_SetState ($hash, "OK");
		return "Default attributes written to $filename";
	}
	elsif ($opt eq 'aggregation') {
		my $rule = shift @$a;
		
		return HMCCU_SetError ($hash, "Usage: get $name aggregagtion {all|rule}")
			if (!defined ($rule));
			
		if ($rule eq 'all') {
			foreach my $r (keys %{$hash->{hmccu}{agg}}) {
				my $rc = HMCCU_AggregateReadings ($hash, $r);
				$result .= "$r = $rc\n";
			}
		}
		else {
			return HMCCU_SetError ($hash, "HMCCU: Aggregation rule does not exist")
				if (!exists ($hash->{hmccu}{agg}{$rule}));
			$result = HMCCU_AggregateReadings ($hash, $rule);
			$result = "$rule = $result";			
		}

		HMCCU_SetState ($hash, "OK");
		return $ccureadings ? undef : $result;
	}
	elsif ($opt eq 'configdesc') {
		my $ccuobj = shift @$a;

		return HMCCU_SetError ($hash, "Usage: get $name configdesc {device|channel}")
		   if (!defined ($ccuobj));

		my ($rc, $res) = HMCCU_RPCGetConfig ($hash, $ccuobj, "getParamsetDescription", undef);
		return HMCCU_SetError ($hash, $rc) if ($rc < 0);

		HMCCU_SetState ($hash, "OK");
		return $res;
	}
	else {
		if (exists ($hash->{hmccu}{agg})) {
			my @rules = keys %{$hash->{hmccu}{agg}};
			$options .= " aggregation:all,".join (',', @rules) if (scalar (@rules) > 0);
		}
		return "HMCCU: Unknown argument $opt, choose one of ".$options;
	}
}

##################################################################
# Parse CCU object specification.
# Supports classic Homematic and Homematic-IP addresses.
# Supports team addresses with leading * for BidCos-RF.
# Supports CCU virtual remote addresses (BidCoS:ChnNo)
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
# If object name doesn't match the rules above object is treated
# as name.
# With parameter flags one can specify if result is filled up
# with default values for interface or datapoint.
#
# Return list of detected attributes:
#   (Interface, Address, Channel, Datapoint, Name, Flags)
#   Flags is a bitmask of detected attributes.
##################################################################

sub HMCCU_ParseObject ($$$)
{
	my ($hash, $object, $flags) = @_;
	my ($i, $a, $c, $d, $n, $f) = ('', '', '', '', '', '', 0);

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
	elsif ($object =~ /^([\*]*[A-Z]{3}[0-9]{7}):([0-9]){1,2}\.(.+)$/ ||
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

	# Check if name is a valid channel name
	if ($f & $HMCCU_FLAG_NAME) {
		my ($add, $chn) = HMCCU_GetAddress ($hash, $n, '', '');
		if ($chn ne '') {
			$f = $f | $HMCCU_FLAG_CHANNEL;
		}
		if ($flags & $HMCCU_FLAG_FULLADDR) {
			($i, $a, $c) = (HMCCU_GetDeviceInterface ($hash, $add, 'BidCos-RF'), $add, $chn);
			$f |= $HMCCU_FLAG_INTERFACE;
			$f |= $HMCCU_FLAG_ADDRESS if ($add ne '');
			$f |= $HMCCU_FLAG_CHANNEL if ($chn ne '');
		}
	}
	elsif ($f & $HMCCU_FLAG_ADDRESS && $i eq '' &&
	   ($flags & $HMCCU_FLAG_FULLADDR || $flags & $HMCCU_FLAG_INTERFACE)) {
		$i = HMCCU_GetDeviceInterface ($hash, $a, 'BidCos-RF');
		$f |= $HMCCU_FLAG_INTERFACE;
	}

	return ($i, $a, $c, $d, $n, $f);
}

##################################################################
# Filter reading by datapoint and optionally by channel name or
# channel address.
# Parameters: hash, channel, datapoint
##################################################################

sub HMCCU_FilterReading ($$$)
{
	my ($hash, $chn, $dpt) = @_;
	my $name = $hash->{NAME};

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return 1 if (!defined ($hmccu_hash));
	
	my $cf = AttrVal ($name, 'ccuflags', 'null');
	my $grf = AttrVal ($hmccu_hash->{NAME}, 'ccudef-readingfilter', '');
	$grf = '.*' if ($grf eq '');
	my $rf = AttrVal ($name, 'ccureadingfilter', $grf);
	$rf .= ";".$grf if ($rf ne $grf && $grf ne '.*' && $grf ne '');

	my $chnnam = HMCCU_IsChnAddr ($chn, 0) ? HMCCU_GetChannelName ($hmccu_hash, $chn, '') : $chn;
	Log3 $name, 2, "HMCCU: FilterReading: dpt=$dpt chnname=$chnnam rf=$rf" if ($cf =~ /trace/);

	my @rules = split (';', $rf);
	foreach my $r (@rules) {
		my ($c, $f) = split ("!", $r);
		if (defined ($f) && $chnnam ne '') {
			if ($chnnam =~ /$c/) {
				if ($dpt !~ /$f/) {
					Log3 $name, 2, "HMCCU: FilterReading: Datapoint $dpt doesn't match filter $rf"
						if ($cf =~ /trace/);
					return 0;
				}
				else {
					return 1;
				}
			}
		}
		else {
			return 1 if ($dpt =~ /$r/);
		}
	}

	Log3 $name, 2, "HMCCU: FilterReading: Datapoint $dpt doesn't match filter $rf"
		if ($cf =~ /trace/);
		
	return 0;
}

######################################################################
# Build reading name
#
# Parameters:
#
#   Interface,Address,ChannelNo,Datapoint,ChannelNam,ReadingFormat
#
#   ReadingFormat := { name[lc] | datapoint[lc] | address[lc] }
#
# Valid combinations:
#
#   ChannelNam,Datapoint
#   Address,Datapoint
#   Address,ChannelNo,Datapoint
#
# Reading names can be modified by setting attribut ccureadingname.
# Returns list of readings names.
######################################################################

sub HMCCU_GetReadingName ($$$$$$$)
{
	my ($hash, $i, $a, $c, $d, $n, $rf) = @_;
	my $name = $hash->{NAME};

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return '' if (!defined ($hmccu_hash));
	
	my $rn = '';
	my @rnlist;

	Log3 $name, 1, "HMCCU: ChannelNo undefined: Addr=".$a if (!defined ($c));

	$rf = HMCCU_GetAttrReadingFormat ($hash, $hmccu_hash) if (!defined ($rf));
	my $gsr = AttrVal ($hmccu_hash->{NAME}, 'ccudef-readingname', '');
	my $sr = AttrVal ($name, 'ccureadingname', $gsr);
	$sr .= ";".$gsr if ($sr ne $gsr && $gsr ne '');
	
	# Datapoint is mandatory
	return '' if ($d eq '');

	if ($rf eq 'datapoint' || $rf eq 'datapointlc') {
		$rn = (defined ($c) && $c ne '') ? $c.'.'.$d : $d;
	}
	elsif ($rf eq 'name' || $rf eq 'namelc') {
		if ($n eq '') {
			if ($a ne '' && $c ne '') {
				$n = HMCCU_GetChannelName ($hmccu_hash, $a.':'.$c, '');
			}
			elsif ($a ne '' && $c eq '') {
				$n = HMCCU_GetDeviceName ($hmccu_hash, $a, '');
			}
			else {
				return '';
			}
		}

		$n =~ s/\:/\./g;
		$n =~ s/[^A-Za-z\d_\.-]+/_/g;

		return '' if ($n eq '');
		$rn = $n.'.'.$d;
	}
	elsif ($rf eq 'address' || $rf eq 'addresslc') {
		if ($a eq '' && $n ne '') {
			($a, $c) = HMCCU_GetAddress ($hmccu_hash, $n, '', '');
		}

		if ($a ne '') {
			my $t = $a;
			$i = HMCCU_GetDeviceInterface ($hmccu_hash, $a, '') if ($i  eq '');
			$t = $i.'.'.$t if ($i ne '');
			$t = $t.'.'.$c if ($c ne '');

			$rn = $t.'.'.$d;
		}
	}
	
	push (@rnlist, $rn);
	
	# Rename and/or add reading names
	if ($sr ne '') {
		my @rules = split (';', $sr);
		foreach my $rr (@rules) {
			my ($rold, $rnew) = split (':', $rr);
			next if (!defined ($rnew));
			if ($rnlist[0] =~ /$rold/) {
				if ($rnew =~ /^\+(.+)$/) {
					my $radd = $1;
					$radd =~ s/$rold/$radd/;
					push (@rnlist, $radd);
				}
				else {
					$rnlist[0] =~ s/$rold/$rnew/;
				}
			}
		}
	}
	
	# Convert to lowercase
	$rnlist[0] = lc($rnlist[0]) if ($rf =~ /lc$/);

	return @rnlist;
}

######################################################################
# Format reading value depending on attribute stripnumber. Integer
# values are ignored.
# 0 = Preserve all digits
# 1 = Preserve 1 digit
# 2 = Remove trailing zeroes
# -n = Round value to specified number of digits (-0 is valid)
######################################################################

sub HMCCU_FormatReadingValue ($$)
{
	my ($hash, $value) = @_;

	my $stripnumber = AttrVal ($hash->{NAME}, 'stripnumber', '0');
	return $value if ($stripnumber eq '0' || $value !~ /\.[0-9]+$/);

	if ($stripnumber eq '1') {
		return sprintf ("%.1f", $value);
	}
	elsif ($stripnumber eq '2') {
		return sprintf ("%g", $value);
	}
	elsif ($stripnumber =~ /^-([0-9])$/) {
		my $fmt = '%.'.$1.'f';
		return sprintf ($fmt, $value);
	}

	return $value;
}

######################################################################
# Set error state and write log file message
######################################################################

sub HMCCU_SetError ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $msg;
	my %errlist = (
	   -1 => 'Invalid name or address',
	   -2 => 'Execution of CCU script or command failed',
	   -3 => 'Cannot detect IO device',
	   -4 => 'Device deleted in CCU',
	   -5 => 'No response from CCU',
	   -6 => 'Update of readings disabled. Set attribute ccureadings first',
	   -7 => 'Invalid channel number',
	   -8 => 'Invalid datapoint',
	   -9 => 'Interface does not support RPC calls',
	   -10 => 'No readable datapoints found',
	   -11 => 'No state channel defined',
	   -12 => 'No control channel defined',
	   -13 => 'No state datapoint defined',
	   -14 => 'No control datapoint defined',
	   -15 => 'No state values defined',
	   -16 => 'Cannot open file'
	);

	$msg = exists ($errlist{$text}) ? $errlist{$text} : $text;
	$msg = $type.": ".$name." ". $msg;

	HMCCU_SetState ($hash, "Error");
	Log3 $name, 1, $msg;
	return $msg;
}

##################################################################
# Set state of device if attribute ccuackstate = 1
##################################################################

sub HMCCU_SetState ($$)
{
	my ($hash, $text) = @_;
	my $name = $hash->{NAME};

	my $defackstate = $hash->{TYPE} eq 'HMCCU' ? 1 : 0;
	my $ackstate = AttrVal ($name, 'ccuackstate', $defackstate);
	return undef if ($ackstate == 0);
	
	if (defined ($hash) && defined ($text)) {
		readingsSingleUpdate ($hash, "state", $text, 1);
	}

	return ($text eq "busy") ? "HMCCU: CCU busy" : undef;
}

##################################################################
# Substitute first occurrence of regular expressions or fixed
# string. Floating point values are ignored without datapoint
# specification. Integer values are compared with complete value.
# mode: 0=Substitute regular expression, 1=Substitute text
##################################################################

sub HMCCU_Substitute ($$$$$)
{
	my ($value, $substrule, $mode, $chn, $dpt, $std) = @_;
	my $rc = 0;
	my $newvalue;

	return $value if (!defined ($substrule) || $substrule eq '');

	# Remove channel number from datapoint if specified
	if ($dpt =~ /^([0-9]{1,2})\.(.+)$/) {
		($chn, $dpt) = ($1, $2);
	}

	my @rulelist = split (';', $substrule);
	foreach my $rule (@rulelist) {
		my @ruletoks = split ('!', $rule);
		if (@ruletoks == 2 && $dpt ne '' && $mode == 0) {
			my @dptlist = split (',', $ruletoks[0]);
			foreach my $d (@dptlist) {
				my $c = -1;
				if ($d =~ /^([0-9]{1,2})\.(.+)$/) {
					($c, $d) = ($1, $2);
				}
				if ($d eq $dpt && ($c == -1 || !defined($chn) || $c == $chn)) {
					($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[1], $mode);
					return $newvalue;
				}
			}
		}
		elsif (@ruletoks == 1) {
			return $value if ($value !~ /^[+-]?\d+$/ && $value =~ /^[+-]?\d*\.?\d+(?:(?:e|E)\d+)?$/);
			($rc, $newvalue) = HMCCU_SubstRule ($value, $ruletoks[0], $mode);
			return $newvalue if ($rc == 1);
		}
	}

	return $value;
}

##################################################################
# Execute substitution list.
# Syntax for single substitution: {#n-n|regexp|text}:newtext
#   mode=0: Substitute regular expression
#   mode=1: Substitute text (for setting statevals)
# newtext can contain ':'. Parameter ${value} in newtext is
# substituted by original value.
# Return (status, value)
#   status=1: value = substituted value
#   status=0: value = original value
##################################################################

sub HMCCU_SubstRule ($$$)
{
	my ($value, $substitutes, $mode ) = @_;
	my $rc = 0;

	$substitutes =~ s/\$\{value\}/$value/g;
	
	my @sub_list = split /,/,$substitutes;
	foreach my $s (@sub_list) {
		my ($regexp, $text) = split /:/,$s,2;
		next if (!defined ($regexp) || !defined($text));
		if ($regexp =~ /^#([+-]?\d*\.?\d+?)\-([+-]?\d*\.?\d+?)$/) {
			my ($mi, $ma) = ($1, $2);
			if ($value =~ /^\d*\.?\d+?$/ && $value >= $mi && $value <= $ma) {
				$value = $text;
				$rc = 1;
#				my $x = eval { $value =~ s/^\d*\.?\d+?/$text/ };
#				$rc = 1 if (defined ($x));				last;
			}
		}
		if ($mode == 0 && $value =~ /$regexp/ && $value !~ /^[+-]?\d+$/) {
			my $x = eval { $value =~ s/$regexp/$text/ };
			$rc = 1 if (defined ($x));
			last;
		}
		elsif (($mode == 1 || $value =~/^[+-]?\d+$/) && $value =~ /^$regexp$/) {
			my $x = eval { $value =~ s/^$regexp$/$text/ };
			$rc = 1 if (defined ($x));
			last;
		}
	}

	return ($rc, $value);
}

##################################################################
# Substitute datapoint variables in string by datapoint value.
##################################################################

sub HMCCU_SubstVariables ($$)
{
	my ($clhash, $text) = @_;
	
	# Substitute datapoint variables by value
	foreach my $dp (keys %{$clhash->{hmccu}{dp}}) {
		my ($chn,$dpt) = split (/\./, $dp);
		if (defined ($clhash->{hmccu}{dp}{$dp}{VAL})) {
			my $value = HMCCU_FormatReadingValue ($clhash, $clhash->{hmccu}{dp}{$dp}{VAL});
			$text =~ s/\$\{$dp\}/$value/g;
			$text =~ s/\$\{$dpt\}/$value/g;
		}
	}
	
	return $text;
}

##################################################################
# Update all datapoint/readings of all client devices matching
# specified regular expression. Update will fail if device is 
# deteted or disabled or if attribute ccureadings of a device is
# set to 0.
# If fromccu is 1 regular expression is compared to CCU device
# name. Otherwise it's compared to FHEM device name.
##################################################################

sub HMCCU_UpdateClients ($$$$)
{
	my ($hash, $devexp, $ccuget, $fromccu) = @_;
	my $fhname = $hash->{NAME};
	my $c_ok = 0;
	my $c_err = 0;

	if ($fromccu) {
		foreach my $name (sort keys %{$hash->{hmccu}{adr}}) {
			next if ($name !~ /$devexp/ || !($hash->{hmccu}{adr}{$name}{valid}));

			foreach my $d (keys %defs) {
				my $ch = $defs{$d};
				next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
				next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
				next if ($ch->{ccudevstate} ne 'Active');
				next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));
				next if ($ch->{ccuaddr} ne $hash->{hmccu}{adr}{$name}{address});

				my $rc = HMCCU_GetUpdate ($ch, $hash->{hmccu}{adr}{$name}{address}, $ccuget);
				if ($rc <= 0) {
					if ($rc == -10) {
						Log3 $fhname, 1, "HMCCU: Device $name has no readable datapoints";
					}
					else {
						Log3 $fhname, 1, "HMCCU: Update of device $name failed" if ($rc != -10);
					}
					$c_err++;
				}
				else {
					$c_ok++;
				}
			}
		}
	}
	else {
		foreach my $d (keys %defs) {
			# Get hash of client device
			my $ch = $defs{$d};
			next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
			next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
			next if ($ch->{ccudevstate} ne 'Active');
			next if ($ch->{NAME} !~ /$devexp/);
			next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));

			my $rc = HMCCU_GetUpdate ($ch, $ch->{ccuaddr}, $ccuget);
			if ($rc <= 0) {
				if ($rc == -10) {
					Log3 $fhname, 3, "HMCCU: Device ".$ch->{ccuaddr}." has no readable datapoints";
				}
				else {
					Log3 $fhname, 2, "HMCCU: Update of device ".$ch->{ccuaddr}." failed"
						if ($ch->{ccuif} ne 'VirtualDevices');
				}
				$c_err++;
			}
			else {
				$c_ok++;
			}
		}
	}

	return ($c_ok, $c_err);
}

##################################################################
# Update reading in all client devices matching specified address.
#
# Parameters:
#   hash, address, channelno, datapoint, value, [mode]
#
# Parameter hash refers to HMCCU IO device.
# Parameter address can be a device or a channel address. If
# devadd is a channel address parameter channelno is ignored.
#
# Valid modes are:
#   rpcevent: Function is triggered by RPC server.
#   client:   Function is triggered by client device.
#
# Reading values are substituted, scaled and formatted according
# to attributes in client device.
# Return 1 on success and 0 on error.
##################################################################

sub HMCCU_UpdateClientReading ($@)
{
	my ($hash, $address, $chn, $dpt, $value, $mode) = @_;
	my $name = $hash->{NAME};
	my $fnc = "UpdateClientReading";
	my $chnadd = '';
	my $devadd = '';

	# Check syntax
	return 0 if (!defined ($hash) || !defined ($devadd) || !defined ($chn) || !defined ($dpt) ||
	   !defined ($value));

	if (HMCCU_IsChnAddr ($address, 0)) {
		$chnadd = $address;
		($devadd, $chn) = HMCCU_SplitChnAddr ($address);
	}
	elsif (HMCCU_IsDevAddr ($address, 0)) {
		$devadd = $address;
		$chnadd = $address.':'.$chn if ($chn ne '');
	}
	else {
		Log3 $name, 2, "HMCCU: $fnc Address $address not valid";
		return 0;
	}
	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	# Update reading in matching client devices
	foreach my $d (keys %defs) {
		# Get hash and name of client device
		my $ch = $defs{$d};
		next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
		my $ct = $ch->{TYPE};
		my $cn = $ch->{NAME};

		next if ($ct ne 'HMCCUDEV' && $ct ne 'HMCCUCHN');
		next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));
		next if ($ch->{IODev} != $hash);
		my $ca = $ch->{ccuaddr};
		my ($cdev, undef) = HMCCU_SplitChnAddr ($ca);
		my $csa = $cdev.':0';
		my $cf = AttrVal ($cn, 'ccuflags', 'null');
		
 		if ($ch->{ccuif} eq "VirtualDevices" && exists ($ch->{ccugroup})) {
 			# Store values of group devices in group readings
 			my @gdevs = split (",", $ch->{ccugroup});
 			next if (!(grep { $_ eq $devadd } @gdevs) && !(grep { $_ eq $chnadd } @gdevs) &&
			  $ch->{ccuaddr} ne $devadd && $ch->{ccuaddr} ne $chnadd);
 		}
 		else {
 			next if ($ct eq 'HMCCUDEV' && $ch->{ccuaddr} ne $devadd);
 			next if ($ct eq 'HMCCUCHN' && $ch->{ccuaddr} ne $chnadd && $csa ne $chnadd);
 			next if ($csa eq $chnadd && $cf =~ /nochn0/);
 		}
		
		# Get attributes of client device
		my $dis = AttrVal ($cn, 'disable', 0);
		my $upd = AttrVal ($cn, 'ccureadings', 1);
		my $crf = HMCCU_GetAttrReadingFormat ($ch, $hash);
		my $substitute = HMCCU_GetAttrSubstitute ($ch, $hash);
		my ($sc, $st, $cc, $cd) = HMCCU_GetSpecialDatapoints ($ch, '', 'STATE', '', '');
		last if ($upd == 0 || $dis == 1);

		Log3 $name, 2, "HMCCU: $fnc device=$cn, devadd=$devadd, chnadd=$chnadd, dpt=$dpt, value=$value"
			if ($cf =~ /trace/);

		$ch->{hmccu}{dp}{"$chn.$dpt"}{VAL} = $value;
		
		# Update datapoint reading and control/state readings
 		readingsBeginUpdate ($ch);
 		
		if (HMCCU_FilterReading ($ch, $chnadd, $dpt)) {
			my @readings = HMCCU_GetReadingName ($ch, '', $devadd, $chn, $dpt, '', $crf);
			my $svalue = HMCCU_ScaleValue ($ch, $dpt, $value, 0);	
			my $fvalue = HMCCU_FormatReadingValue ($ch, $svalue);
			my $cvalue = HMCCU_Substitute ($fvalue, $substitute, 0, $chn, $dpt);
			my %calcs = HMCCU_CalculateReading ($ch, $chn, $dpt);
			
			Log3 $name, 2, "HMCCU: $fnc device=$cn, readings=".join(',', @readings).
				", orgvalue=$value value=$cvalue" if ($cf =~ /trace/);

			foreach my $rn (@readings) {
				HMCCU_BulkUpdate ($ch, $rn, $value, $cvalue) if ($rn ne '');
			}
			foreach my $clcr (keys %calcs) {
				HMCCU_BulkUpdate ($ch, $clcr, $calcs{$clcr}, $calcs{$clcr});
			}
			HMCCU_BulkUpdate ($ch, 'control', $fvalue, $cvalue)
				if ($cd ne '' && $dpt eq $cd && $chn eq $cc);
			HMCCU_BulkUpdate ($ch, 'state', $fvalue, $cvalue)
				if ($dpt eq $st && ($sc eq '' || $sc eq $chn));
		}
		
		if ($ccuflags !~ /nohmstate/) {
			my ($hms_read, $hms_chn, $hms_dpt, $hms_val) = HMCCU_GetHMState ($cn, $name, undef);
			HMCCU_BulkUpdate ($ch, $hms_read, $hms_val, $hms_val) if (defined ($hms_val));
		}
		
		readingsEndUpdate ($ch, 1);
	}

	return 1;
}

####################################################
# Update existing devices
####################################################

sub HMCCU_AddDevices ($$)
{
	my ($hash, $devlist) = @_;
	
	foreach my $a (@$devlist) {
		foreach my $d (keys %defs) {
			my $ch = $defs{$d};
			next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
			next if ($ch->{TYPE} ne 'HMCCUCHN');
			$ch->{chntype} = defined ($hash->{hmccu}{dev}{$a}{chntype}) ?
				$hash->{hmccu}{dev}{$a}{chntype} : "unknown";
		}
	}
}

####################################################
# Mark client devices deleted in CCU as invalid
####################################################

sub HMCCU_DeleteDevices ($$)
{
	my ($hash, $devlist) = @_;

	foreach my $a (@$devlist) {
		my $cc = $hash->{hmccu}{dev}{$a}{channels};
		$hash->{hmccu}{dev}{$a}{valid} = 0;
		$hash->{hmccu}{adr}{$hash->{hmccu}{dev}{$a}{name}}{valid} = 0;
		for (my $i=0; $i<$cc; $i++) {
			$hash->{hmccu}{dev}{$a.':'.$i}{valid} = 0;
			$hash->{hmccu}{adr}{$hash->{hmccu}{dev}{$a.':'.$i}{name}}{valid} = 0;
		}
		foreach my $d (keys %defs) {
			my $ch = $defs{$d};
			next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
			if ($ch->{TYPE} eq 'HMCCUDEV' && $ch->{ccuaddr} eq $a) {
				$ch->{ccudevstate} = 'Deleted';
				readingsSingleUpdate ($ch, 'state', 'Deleted', 1);
			}
			elsif ($ch->{TYPE} eq 'HMCCUCHN' && $ch->{ccuaddr} =~ /^$a:[0-9]+/) {
				$ch->{ccudevstate} = 'Deleted';
				readingsSingleUpdate ($ch, 'state', 'Deleted', 1);
			}
		}
	}
}

####################################################
# Register RPC callbacks at CCU if RPC-Server
# already in server loop
####################################################

sub HMCCU_RPCRegisterCallback ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $serveraddr = $hash->{host};
	my $localaddr = $hash->{hmccu}{localaddr};

#	my $rpcport = AttrVal ($name, 'rpcport', 2001);
	my $rpcport = $hash->{hmccu}{rpcports};
	my $rpcinterval = AttrVal ($name, 'rpcinterval', $HMCCU_INIT_INTERVAL2);
	my $rpcserveraddr = AttrVal ($name, 'rpcserveraddr', $localaddr);
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	
	foreach my $port (split (',', $rpcport)) {
		my $clkey = 'CB'.$port;
		my $cburl = "http://".$localaddr.":".$hash->{hmccu}{rpc}{$clkey}{cbport}."/fh".$port;
		my $url = "http://$serveraddr:$port/";
		$url .= $HMCCU_RPC_URL{$port} if (exists ($HMCCU_RPC_URL{$port}));
		if ($hash->{hmccu}{rpc}{$clkey}{loop} == 1 || $hash->{hmccu}{rpc}{$clkey}{state} eq "register") {		
			$hash->{hmccu}{rpc}{$clkey}{port} = $port;
			$hash->{hmccu}{rpc}{$clkey}{clurl} = $url;
			$hash->{hmccu}{rpc}{$clkey}{cburl} = $cburl;
			$hash->{hmccu}{rpc}{$clkey}{loop} = 2;
			$hash->{hmccu}{rpc}{$clkey}{state} = "registered";

			Log3 $name, 1, "HMCCU: Registering callback $cburl with ID $clkey at $url";
			my $rpcclient = RPC::XML::Client->new ($url);
			$rpcclient->send_request ("init", $cburl, $clkey);
			Log3 $name, 1, "HMCCU: RPC callback with URL $cburl initialized";
		}
	}
	
	# Schedule reading of RPC queue
	InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
}

####################################################
# Deregister RPC callbacks at CCU
####################################################

sub HMCCU_RPCDeRegisterCallback ($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		my $rpchash = \%{$hash->{hmccu}{rpc}{$clkey}};
		if (exists ($rpchash->{cburl}) && $rpchash->{cburl} ne '') {
			my $port = $rpchash->{port};
			my $rpcclient = RPC::XML::Client->new ($rpchash->{clurl});
			Log3 $name, 1, "HMCCU: Deregistering RPC server ".$rpchash->{cburl}.
			   " at ".$rpchash->{clurl};
			$rpcclient->send_request("init", $rpchash->{cburl});
			$rpchash->{cburl} = '';
			$rpchash->{clurl} = '';
			$rpchash->{cbport} = 0;
		}
	}
}

####################################################
# Initialize statistic counters
####################################################

sub HMCCU_ResetCounters ($)
{
	my ($hash) = @_;
	my @counters = ('total', 'EV', 'ND', 'IN', 'DD', 'RA', 'RD', 'UD', 'EX', 'SL', 'ST');
	
	foreach my $cnt (@counters) {
		$hash->{hmccu}{ev}{$cnt} = 0;
	}
	delete $hash->{hmccu}{evs};
	delete $hash->{hmccu}{evr};

	$hash->{hmccu}{evtimeout} = 0;
	$hash->{hmccu}{evtime} = 0;
}

####################################################
# Start external RPC server
####################################################

sub HMCCU_StartExtRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $modpath = AttrVal ('global', 'modpath', '/opt/fhem');
	my $logfile = $modpath."/log/ccurpcd";
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
#	my $rpcport = AttrVal ($name, 'rpcport', 2001);
	my $rpcport = $hash->{hmccu}{rpcports};
	my $rpcserverport = AttrVal ($name, 'rpcserverport', 5400);
	my $rpcinterval = AttrVal ($name, 'rpcinterval', $HMCCU_INIT_INTERVAL1);
	my $verbose = AttrVal ($name, 'verbose', -1);
	$verbose = AttrVal ('global', 'verbose', 0) if ($verbose == -1);
	
	my $serveraddr = $hash->{host};
	my $localaddr = '';

	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	if (@hm_pids > 0) {
		Log3 $name, 0, "HMCCU: RPC server(s) already running with PIDs ".join (',', @hm_pids);
		return scalar (@hm_pids);
	}
	elsif (@ex_pids > 0) {
		Log3 $name, 1, "HMCCU: Externally launched RPC server(s) detected. Kill process(es) manually with command kill -SIGINT pid for pid=".join (',', @ex_pids);
		return 0;
	}

 	my $rpcserver = $modpath."/FHEM/ccurpcd.pl";
	# Check if RPC server exists
 	if (! -e $rpcserver) {
 		Log3 $name, 1, "HMCCU: RPC server file ccurpcd.pl not found in ".$modpath."/FHEM";
 		return 0;
 	}

	my $fork_cnt = 0;
	my $callbackport = 0;
	my $ccunum = $hash->{CCUNum};
	
	# Fork child process(es)
	foreach my $port (split (',', $rpcport)) {
 		my $clkey = 'CB'.$port;
		my $rpcqueueport = $rpcqueue."_".$port."_".$ccunum;
		my $logfileport = $logfile."_".$port."_".$ccunum.".log";

		$callbackport = $rpcserverport+$port+($ccunum*10)
			if ($callbackport == 0);
	
		# Detect local IP
		if ($localaddr eq '') {
			my $socket = IO::Socket::INET->new (PeerAddr => $serveraddr, PeerPort => $port);
			if (!$socket) {
				Log3 $name, 1, "Can't connect to CCU port $port";
				next;
			}
			$localaddr = $socket->sockhost ();
			close ($socket);
		}

		if ($fork_cnt == 0 || $ccuflags !~ /singlerpc/) {
			# Cleat event queue
			HMCCU_ResetRPCQueue ($hash, $port);
			
			my $pid = fork ();
			if (!defined ($pid)) {
				Log3 $name, 1, "HMCCU: Can't fork child process for CCU port $port";
				next;
			}

			if (!$pid) {
				# Child process. Replaced by RPC server
				exec ($rpcserver." ".$serveraddr." ".$port." ".$rpcqueueport." ".$logfileport." ".$verbose);

				# When we reach this line start of RPC server failed and child process can exit
				die;
			}
			
			# Parent process
			
			# Store PID
			push (@hm_pids, $pid);
			$hash->{hmccu}{rpc}{$clkey}{pid} = $pid;
			$hash->{hmccu}{rpc}{$clkey}{queue} = $rpcqueueport;
			$hash->{hmccu}{rpc}{$clkey}{state} = "starting";
			Log3 $name, 0, "HMCCU: RPC server $clkey started with pid ".$pid;
		
			$fork_cnt++;
		}
		else {
			$hash->{hmccu}{rpc}{$clkey}{pid} = 0;
			$hash->{hmccu}{rpc}{$clkey}{state} = "register";
			$hash->{hmccu}{rpc}{$clkey}{queue} = '';
		}

		$hash->{hmccu}{rpc}{$clkey}{cbport} = $callbackport;
		$hash->{hmccu}{rpc}{$clkey}{loop} = 0;
	}

	$hash->{hmccu}{rpccount} = $fork_cnt;
	$hash->{hmccu}{localaddr} = $localaddr;
	
	if ($fork_cnt > 0) {
		$hash->{hmccu}{evtimeout} = 0;
		$hash->{hmccu}{eventtime} = 0;
		$hash->{RPCPID} = join (',', @hm_pids);
		$hash->{RPCPRC} = $rpcserver;
		$hash->{RPCState} = "starting";
		
		# Initialize statistic counters
		HMCCU_ResetCounters ($hash);
	
		readingsSingleUpdate ($hash, "rpcstate", "starting", 1);	
		DoTrigger ($name, "RPC server starting");

		InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
	}
	else {
		Log3 $name, 1, "HMCCU: No RPC process started";
	}

	return scalar (@hm_pids);
}

####################################################
# Start internal RPC server
####################################################

sub HMCCU_StartIntRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	# Timeouts
	my $timeout = AttrVal ($name, 'rpctimeout', '0.01,0.25');
	my ($to_read, $to_write) = split (",", $timeout);
	$to_write = $to_read if (!defined ($to_write));
	
	# Address and ports
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
#	my $rpcport = AttrVal ($name, 'rpcport', 2001);
	my $rpcport = $hash->{hmccu}{rpcports};
	my $rpcserverport = AttrVal ($name, 'rpcserverport', 5400);
	my $rpcinterval = AttrVal ($name, 'rpcinterval', $HMCCU_INIT_INTERVAL1);
	my @rpcportlist = split (",", $rpcport);
	my $serveraddr = $hash->{host};
	my $fork_cnt = 0;

	# Check for running RPC server processes	
	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	if (@hm_pids > 0) {
		Log3 $name, 0, "HMCCU: RPC server(s) already running with PIDs ".join (',', @hm_pids);
		return scalar (@hm_pids);
	}
	elsif (@ex_pids > 0) {
		Log3 $name, 1, "HMCCU: Externally launched RPC server(s) detected. Kill process(es) manually with command kill -SIGINT pid for pid=".join (',', @ex_pids);
		return 0;
	}

	# Detect local IP address
	my $socket = IO::Socket::INET->new (PeerAddr => $serveraddr, PeerPort => $rpcportlist[0]);
	if (!$socket) {
		Log3 $name, 1, "HMCCU: Can't connect to CCU port".$rpcportlist[0];
		return 0;
	}
	my $localaddr = $socket->sockhost ();
	close ($socket);

	my $ccunum = $hash->{CCUNum};
	
	# Fork child processes
	foreach my $port (@rpcportlist) {
		my $clkey = 'CB'.$port;
		my $rpcqueueport = $rpcqueue."_".$port."_".$ccunum;
		my $callbackport = $rpcserverport+$port+($ccunum*10);

		# Clear event queue
		HMCCU_ResetRPCQueue ($hash, $port);
		
		# Create child process
		Log3 $name, 2, "HMCCU: Create child process with timeouts $to_read and $to_write";
		my $child = SubProcess->new ({ onRun => \&HMCCU_CCURPC_OnRun,
			onExit => \&HMCCU_CCURPC_OnExit, timeoutread => $to_read, timeoutwrite => $to_write });
		$child->{serveraddr}   = $serveraddr;
		$child->{serverport}   = $port;
		$child->{callbackport} = $callbackport;
		$child->{devname}      = $name;
		$child->{queue}        = $rpcqueueport;
		
# 		Log3 $name, 2, "HMCCU: Child socket snd buffer = ".$child->getsndbuffer ($child->child());
# 		Log3 $name, 2, "HMCCU: Child socket rcv buffer = ".$child->getrcvbuffer ($child->child());
# 		Log3 $name, 2, "HMCCU: Parent socket snd buffer = ".$child->getrcvbuffer ($child->parent());
# 		Log3 $name, 2, "HMCCU: Parent socket rcv buffer = ".$child->getrcvbuffer ($child->parent());
# 		Log3 $name, 2, "HMCCU: Parent socket snd lowat = ".$child->getsndlowat ($child->parent());
# 		Log3 $name, 2, "HMCCU: Parent socket rcv lowat = ".$child->getrcvlowat ($child->parent());

		# Start child process
		my $pid = $child->run ();
		if (!defined ($pid)) {
			Log3 $name, 1, "HMCCU: No RPC process for server $clkey started";
			next;
		}
		
		Log3 $name, 0, "HMCCU: Child process for server $clkey started with PID $pid";
		$fork_cnt++;

		# Store child process parameters
		$hash->{hmccu}{rpc}{$clkey}{child}  = $child;
		$hash->{hmccu}{rpc}{$clkey}{cbport} = $callbackport;
		$hash->{hmccu}{rpc}{$clkey}{loop}   = 0;
		$hash->{hmccu}{rpc}{$clkey}{pid}    = $pid;
		$hash->{hmccu}{rpc}{$clkey}{queue}  = $rpcqueueport;
		$hash->{hmccu}{rpc}{$clkey}{state}  = "starting";
		push (@hm_pids, $pid);
	}

	$hash->{hmccu}{rpccount}  = $fork_cnt;
	$hash->{hmccu}{localaddr} = $localaddr;

	if ($fork_cnt > 0) {	
		# Set internals
		$hash->{RPCPID} = join (',', @hm_pids);
		$hash->{RPCPRC} = "internal";
		$hash->{RPCState} = "starting";

		# Initialize statistic counters
		HMCCU_ResetCounters ($hash);
	
		readingsSingleUpdate ($hash, "rpcstate", "starting", 1);	
		Log3 $name, 0, "RPC server(s) starting";
		DoTrigger ($name, "RPC server starting");

		InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
	}
		
	return $fork_cnt;
}

####################################################
# Stop RPC server(s)
# Send SIGINT to process(es)
####################################################

sub HMCCU_StopRPCServer ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $pid = 0;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
#	my $rpcport = AttrVal ($name, 'rpcport', 2001);
	my $rpcport = $hash->{hmccu}{rpcports};
	my $serveraddr = $hash->{host};

	# Deregister callback URLs in CCU
	HMCCU_RPCDeRegisterCallback ($hash);
		
	# Send signal SIGINT to RPC server processes
	foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
		my $rpchash = \%{$hash->{hmccu}{rpc}{$clkey}};
		if (exists ($rpchash->{pid}) && $rpchash->{pid} > 0) {
			Log3 $name, 0, "HMCCU: Stopping RPC server $clkey with PID ".$rpchash->{pid};
			kill ('INT', $rpchash->{pid});
			$rpchash->{state} = "stopping";
		}
		else {
			$rpchash->{state} = "stopped";
		}
	}
	
	# Update status
	if ($hash->{hmccu}{rpccount} > 0) {
		readingsSingleUpdate ($hash, "rpcstate", "stopping", 1);
		$hash->{RPCState} = "stopping";
	}
	
	# Wait
	sleep (1);
	
	# Check if processes were terminated
	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	if (@hm_pids > 0) {
		foreach my $pid (@hm_pids) {
			Log3 $name, 0, "HMCCU: Stopping RPC server with PID $pid";
			kill ('INT', $pid);
		}
	}
	if (@ex_pids > 0) {
		Log3 $name, 0, "HMCCU: Externally launched RPC server detected.";
		foreach my $pid (@ex_pids) {
			kill ('INT', $pid);
		}
	}
	
	# Wait
	sleep (1);
	
	# Kill the rest
	@hm_pids = ();
	@ex_pids = ();
	if (HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids)) {
		push (@hm_pids, @ex_pids);
		foreach my $pid (@hm_pids) {
			kill ('KILL', $pid);
		}
	}

	@hm_pids = ();
	@ex_pids = ();
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	push (@hm_pids, @ex_pids);
	$hash->{hmccu}{rpccount} = scalar(@hm_pids);

	return $hash->{hmccu}{rpccount} > 0 ? 0 : 1;
}

####################################################
# Check status of RPC server depending on internal
# RPCState. Return 1 if RPC server is stopping,
# starting or restarting. During this phases CCU
# react very slowly so any get or set command from
# HMCCU devices are disabled.
####################################################

sub HMCCU_IsRPCStateBlocking ($)
{
	my ($hash) = @_;

	if ($hash->{RPCState} eq "starting" ||
	    $hash->{RPCState} eq "restarting" ||
	    $hash->{RPCState} eq "stopping") {
		return 1;
	}
	else {
		return 0;
	}
}

####################################################
# Check if RPC server is running. Return list of
# PIDs in referenced arrays.
# 1 = One or more RPC servers running.
# 0 = No RPC server running.
####################################################

sub HMCCU_IsRPCServerRunning ($$$)
{
	my ($hash, $hm_pids, $ex_pids) = @_;
	my $name = $hash->{NAME};
	
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	my @rpcpids;
	if (defined ($hash->{RPCPID}) && $hash->{RPCPID} ne '0') {
		@rpcpids = split (',', $hash->{RPCPID});
	}

	if ($ccuflags =~ /extrpc/) {
		my $rpcport = AttrVal ($hash->{NAME}, 'rpcport', 2001);
		foreach my $port (split (',', $rpcport)) {
			my $pid = HMCCU_CheckProcess ($hash, $port);
			next if ($pid == 0);
			if (grep { $_ eq $pid } @rpcpids) {
				if (kill (0, $pid)) {
					push (@$hm_pids, $pid);
				}
				else {
					push (@$ex_pids, $pid);
				}
			}
			else {
				push (@$ex_pids, $pid);
			}
		}
	}
	else {
		foreach my $clkey (keys %{$hash->{hmccu}{rpc}}) {
			if (exists ($hash->{hmccu}{rpc}{$clkey}{pid}) &&
			   defined ($hash->{hmccu}{rpc}{$clkey}{pid}) &&
			   $hash->{hmccu}{rpc}{$clkey}{pid} > 0) {
			   my $pid = $hash->{hmccu}{rpc}{$clkey}{pid};
				push (@$hm_pids, $pid) if (kill (0, $pid));
			}
		}
	}
	
	return (@$hm_pids > 0 || @$ex_pids > 0) ? 1 : 0;
}

####################################################
# Get PID of RPC server process (0=not running)
####################################################

sub HMCCU_CheckProcess ($$)
{
	my ($hash, $port) = @_;
	my $name = $hash->{NAME};

	my $modpath = AttrVal ('global', 'modpath', '/opt/fhem');
	my $rpcserver = $modpath."/FHEM/ccurpcd.pl";

	# Using BDS syntax. Supported by Debian, MacOS and FreeBSD
	my $pdump = `ps ax | grep $rpcserver | grep -v grep`;
	my @plist = split "\n", $pdump;

	foreach my $proc (@plist) {
		# Remove leading blanks, fix for MacOS. Thanks to mcdeck
		$proc =~ s/^\s+//;
		my @procattr = split /\s+/, $proc;
		return $procattr[0] if ($procattr[0] != $$ && $procattr[4] =~ /perl$/ &&
		   $procattr[5] eq $rpcserver && $procattr[7] eq "$port");
	}

	return 0;
}

####################################################
# Get channels and datapoints of CCU device
####################################################

sub HMCCU_GetDeviceInfo ($$$)
{
	my ($hash, $device, $ccuget) = @_;
	my $name = $hash->{NAME};
	my $devname = '';

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return '' if (!defined ($hmccu_hash));

	$ccuget = HMCCU_GetAttribute ($hmccu_hash, $hash, 'ccuget', 'Value') if ($ccuget eq 'Attr');
	my $ccutrace = AttrVal ($hmccu_hash->{NAME}, 'ccutrace', '');
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hmccu_hash, $device, 0);
	if ($flags == $HMCCU_FLAG_ADDRESS) {
		$devname = HMCCU_GetDeviceName ($hmccu_hash, $add, '');
		return '' if ($devname eq '');
	}
	else {
		$devname = $nam;
	}

	my $script = qq(
string chnid;
string sDPId;
object odev = dom.GetObject ("$devname");
if (odev) {
  foreach (chnid, odev.Channels()) {
    object ochn = dom.GetObject(chnid);
    if (ochn) {
      foreach(sDPId, ochn.DPs()) {
        object oDP = dom.GetObject(sDPId);
        if (oDP) {
          integer op = oDP.Operations();
          string flags = "";
          if (OPERATION_READ & op) { flags = flags # "R"; }
          if (OPERATION_WRITE & op) { flags = flags # "W"; }
          if (OPERATION_EVENT & op) { flags = flags # "E"; }
          WriteLine ("C;" # ochn.Address() # ";" # ochn.Name() # ";" # oDP.Name() # ";" # oDP.ValueType() # ";" # oDP.$ccuget() # ";" # flags);
        }
      }
    }
  }
}
	);

	my $response = HMCCU_HMScript ($hmccu_hash, $script);
	if (($ccutrace ne '' && ($device =~ /$ccutrace/ || $devname =~ /$ccutrace/)) || $ccuflags =~ /trace/) {
		Log3 $name, 2, "HMCCU: Device=$device Devname=$devname";
		Log3 $name, 2, "HMCCU: Script response = \n".$response;
		Log3 $name, 2, "HMCCU: Script = ".$script;
	}
	return $response;
}

####################################################
# Make device info readable
####################################################

sub HMCCU_FormatDeviceInfo ($)
{
	my ($devinfo) = @_;
	
	my %vtypes = (2, "b", 4, "f", 8, "n", 11, "s", 16, "i", 20, "s", 29, "e");
	my $result = '';
	my $c_oaddr = '';
	
	foreach my $dpspec (split ("\n", $devinfo)) {
		my ($c, $c_addr, $c_name, $d_name, $d_type, $d_value, $d_flags) = split (";", $dpspec);
		if ($c_addr ne $c_oaddr) {
			$result .= "CHN $c_addr $c_name\n";
			$c_oaddr = $c_addr;
		}
		my $t = exists ($vtypes{$d_type}) ? $vtypes{$d_type} : $d_type;
		$result .= "  DPT {$t} $d_name = $d_value [$d_flags]\n";
	}
	
	return $result;
}

####################################################
# Read list of CCU devices via Homematic Script.
# Update data of client devices if not current.
####################################################

sub HMCCU_GetDeviceList ($)
{
	my ($hash) = @_;
	my $count = 0;
        
	my $script = qq(
string devid;
string chnid;
foreach(devid, root.Devices().EnumUsedIDs()) {
   object odev=dom.GetObject(devid);
   string intid=odev.Interface();
   string intna=dom.GetObject(intid).Name();
   integer cc=0;
   foreach (chnid, odev.Channels()) {
      object ochn=dom.GetObject(chnid);
      WriteLine("C;" # ochn.Address() # ";" # ochn.Name());
      cc=cc+1;
   }
   WriteLine("D;" # intna # ";" # odev.Address() # ";" # odev.Name() # ";" # odev.HssType() # ";" # cc);
}
	);

	my $response = HMCCU_HMScript ($hash, $script);
	return -1 if ($response eq '');

	%{$hash->{hmccu}{dev}} = ();
	%{$hash->{hmccu}{adr}} = ();
	$hash->{hmccu}{updatetime} = time ();

	foreach my $hmdef (split /\n/,$response) {
		my @hmdata = split /;/,$hmdef;
		if ($hmdata[0] eq 'D') {
			# 1=Interface 2=Device-Address 3=Device-Name 4=Device-Type 5=Channel-Count
			$hash->{hmccu}{dev}{$hmdata[2]}{name} = $hmdata[3];
			$hash->{hmccu}{dev}{$hmdata[2]}{type} = ($hmdata[2] =~ /^CUX/) ? "CUX-".$hmdata[4] : $hmdata[4];
			$hash->{hmccu}{dev}{$hmdata[2]}{interface} = $hmdata[1];
			$hash->{hmccu}{dev}{$hmdata[2]}{channels} = $hmdata[5];
			$hash->{hmccu}{dev}{$hmdata[2]}{addtype} = 'dev';
			$hash->{hmccu}{dev}{$hmdata[2]}{valid} = 1;
			$hash->{hmccu}{adr}{$hmdata[3]}{address} = $hmdata[2];
			$hash->{hmccu}{adr}{$hmdata[3]}{addtype} = 'dev';
			$hash->{hmccu}{adr}{$hmdata[3]}{valid} = 1;
			$count++;
		}
		elsif ($hmdata[0] eq 'C') {
			# 1=Channel-Address 2=Channel-Name
			$hash->{hmccu}{dev}{$hmdata[1]}{name} = $hmdata[2];
			$hash->{hmccu}{dev}{$hmdata[1]}{channels} = 1;
			$hash->{hmccu}{dev}{$hmdata[1]}{addtype} = 'chn';
			$hash->{hmccu}{dev}{$hmdata[1]}{valid} = 1;
			$hash->{hmccu}{adr}{$hmdata[2]}{address} = $hmdata[1];
			$hash->{hmccu}{adr}{$hmdata[2]}{addtype} = 'chn';
			$hash->{hmccu}{adr}{$hmdata[2]}{valid} = 1;
			$count++;
		}
	}

	HMCCU_GetDatapointList ($hash);
	
	# Update client devices
	foreach my $d (keys %defs) {
		# Get hash of client device
		my $ch = $defs{$d};
		next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
		next if ($ch->{TYPE} ne 'HMCCUDEV' && $ch->{TYPE} ne 'HMCCUCHN');
		next if (!defined ($ch->{IODev}) || !defined ($ch->{ccuaddr}));
		next if ($ch->{TYPE} eq 'HMCCUDEV' && $ch->{ccuif} eq "VirtualDevices" &&
		   $ch->{ccuname} eq 'none');
		my $add = $ch->{ccuaddr};
		my $dadd = $add;
		$dadd =~ s/:[0-9]+$//;

		# Update device or channel attributes if it has changed in CCU
		$ch->{ccuname} = $hash->{hmccu}{dev}{$add}{name}
		   if (!defined ($ch->{ccuname}) || $ch->{ccuname} ne $hash->{hmccu}{dev}{$add}{name});
		$ch->{ccuif} = $hash->{hmccu}{dev}{$dadd}{interface}
		   if (!defined ($ch->{ccuif}) || $ch->{ccuif} ne $hash->{hmccu}{dev}{$dadd}{interface});
		$ch->{ccutype} = $hash->{hmccu}{dev}{$dadd}{type}
		   if (!defined ($ch->{ccutype}) || $ch->{ccutype} ne $hash->{hmccu}{dev}{$dadd}{type});
		$ch->{channels} = $hash->{hmccu}{dev}{$add}{channels}
		   if (!defined ($ch->{channels}) || $ch->{channels} != $hash->{hmccu}{dev}{$add}{channels});
	}

	$hash->{NewDevices} = 0;
	$hash->{DelDevices} = 0;

	return $count;
}

####################################################
# Read list of datapoints for CCU device types.
# Function must not be called before GetDeviceList.
# Return number of datapoints.
####################################################

sub HMCCU_GetDatapointList ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};

	if (exists ($hash->{hmccu}{dp})) {
		delete $hash->{hmccu}{dp};
	}
	
	# Get unique device types
	my %alltypes;
	my @devunique;
	foreach my $add (sort keys %{$hash->{hmccu}{dev}}) {
		next if ($hash->{hmccu}{dev}{$add}{addtype} ne 'dev');
#		next if ($hash->{hmccu}{dev}{$add}{addtype} ne 'dev' ||
#		   $hash->{hmccu}{dev}{$add}{interface} eq 'CUxD');
		my $dt = $hash->{hmccu}{dev}{$add}{type};
		if ($dt ne '' && !exists ($alltypes{$dt})) {
			$alltypes{$dt} = 1;
			push @devunique, $hash->{hmccu}{dev}{$add}{name};
		}
	}
	my $devlist = join (',', @devunique);

	my $script = qq(
string chnid;
string sDPId;
string sDevice;
string sDevList = "$devlist";
foreach (sDevice, sDevList.Split(",")) {
  object odev = dom.GetObject (sDevice);
  if (odev) {
    string sType = odev.HssType();
    foreach (chnid, odev.Channels()) {
      object ochn = dom.GetObject(chnid);
      if (ochn) {
        string sAddr = ochn.Address();
        string sChnNo = sAddr.StrValueByIndex(":",1);
        foreach(sDPId, ochn.DPs()) {
          object oDP = dom.GetObject(sDPId);
          if (oDP) {
            string sDPName = oDP.Name().StrValueByIndex(".",2);
            WriteLine (sAddr # ";" # sType # ";" # sChnNo # ";" # sDPName # ";" # oDP.ValueType() # ";" # oDP.Operations());
          }
        }
      }
    }
  }
}
	);

	my $response = HMCCU_HMScript ($hash, $script);
	return 0 if ($response eq '');

	my $c = 0;	
	foreach my $dpspec (split /\n/,$response) {
		my ($chna, $devt, $devc, $dptn, $dptt, $dpto) = split (";", $dpspec);
		$devt = "CUX-".$devt if ($chna =~ /^CUX/);
		$hash->{hmccu}{dp}{$devt}{spc}{ontime} = $devc.".".$dptn if ($dptn eq "ON_TIME");
		$hash->{hmccu}{dp}{$devt}{spc}{ramptime} = $devc.".".$dptn if ($dptn eq "RAMP_TIME");
		$hash->{hmccu}{dp}{$devt}{spc}{submit} = $devc.".".$dptn if ($dptn eq "SUBMIT");
		$hash->{hmccu}{dp}{$devt}{spc}{level} = $devc.".".$dptn if ($dptn eq "LEVEL");		
		$hash->{hmccu}{dp}{$devt}{ch}{$devc}{$dptn}{type} = $dptt;
		$hash->{hmccu}{dp}{$devt}{ch}{$devc}{$dptn}{oper} = $dpto;
		if (exists ($hash->{hmccu}{dp}{$devt}{cnt}{$dptn})) {
			$hash->{hmccu}{dp}{$devt}{cnt}{$dptn}++;
		}
		else {
			$hash->{hmccu}{dp}{$devt}{cnt}{$dptn} = 1;
		}
		$c++;
	}
	
	return $c;
}

####################################################
# Check if device/channel name or address is valid
# and refers to an existing device or channel.
####################################################

sub HMCCU_IsValidDeviceOrChannel ($$)
{
	my ($hash, $param) = @_;

	if (HMCCU_IsDevAddr ($param, 1) || HMCCU_IsChnAddr ($param, 1)) {
		my ($i, $a) = split (/\./, $param);
		return 0 if (! exists ($hash->{hmccu}{dev}{$a}));
		return $hash->{hmccu}{dev}{$a}{valid};		
	}
	
	if (HMCCU_IsDevAddr ($param, 0) || HMCCU_IsChnAddr ($param, 0)) {
		return 0 if (! exists ($hash->{hmccu}{dev}{$param}));
		return $hash->{hmccu}{dev}{$param}{valid};
	}
	else {
		return 0 if (! exists ($hash->{hmccu}{adr}{$param}));
		return $hash->{hmccu}{adr}{$param}{valid};
	}
}

####################################################
# Check if device name or address is valid
# and refers to an existing device.
####################################################

sub HMCCU_IsValidDevice ($$)
{
	my ($hash, $param) = @_;

	if (HMCCU_IsDevAddr ($param, 1)) {
		my ($i, $a) = split (/\./, $param);
		return 0 if (! exists ($hash->{hmccu}{dev}{$a}));
		return $hash->{hmccu}{dev}{$a}{valid};		
	}
	
	if (HMCCU_IsDevAddr ($param, 0)) {
		return 0 if (! exists ($hash->{hmccu}{dev}{$param}));
		return $hash->{hmccu}{dev}{$param}{valid};
	}
	else {
		return 0 if (! exists ($hash->{hmccu}{adr}{$param}));
		return $hash->{hmccu}{adr}{$param}{valid} && $hash->{hmccu}{adr}{$param}{addtype} eq 'dev';
	}
}

####################################################
# Check if channel name or address is valid
# and refers to an existing channel.
####################################################

sub HMCCU_IsValidChannel ($$)
{
	my ($hash, $param) = @_;

	if (HMCCU_IsChnAddr ($param, 1)) {
		my ($i, $a) = split (/\./, $param);
		return 0 if (! exists ($hash->{hmccu}{dev}{$a}));
		return $hash->{hmccu}{dev}{$a}{valid};		
	}
	
	if (HMCCU_IsChnAddr ($param, 0)) {
		return 0 if (! exists ($hash->{hmccu}{dev}{$param}));
		return $hash->{hmccu}{dev}{$param}{valid};
	}
	else {
		return 0 if (! exists ($hash->{hmccu}{adr}{$param}));
		return $hash->{hmccu}{adr}{$param}{valid} && $hash->{hmccu}{adr}{$param}{addtype} eq 'chn';
	}
}

####################################################
# Get CCU parameters of device or channel. Returns
# list containing interface, deviceaddress, name
# type, channels.
####################################################

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
				$add = $hash->{hmccu}{adr}{$param}{address};
			}
# 			else {
# 				Log3 $name, 2, "HMCCU: Address for $param not found";
# 			}
		}
	}
	
# 	Log3 $name, 2, "HMCCU: Address not defined" if (!defined ($add));
# 	Log3 $name, 2, "HMCCU: Device not found for $add" if (!exists ($hash->{hmccu}{dev}{$add}));
# 	Log3 $name, 2, "HMCCU: Device invalid for $add" if ($hash->{hmccu}{dev}{$add}{valid} == 0);

	return (undef, undef, undef, undef) if (!defined ($add));
	($devadd, $chn) = HMCCU_SplitChnAddr ($add);
	return (undef, undef, undef, undef) if (!defined ($devadd) ||
		!exists ($hash->{hmccu}{dev}{$devadd}) || $hash->{hmccu}{dev}{$devadd}{valid} == 0);
	
	return ($hash->{hmccu}{dev}{$devadd}{interface}, $add, $hash->{hmccu}{dev}{$add}{name},
		$hash->{hmccu}{dev}{$devadd}{type}, $hash->{hmccu}{dev}{$add}{channels});
}

####################################################
# Get list of valid datapoints for device type.
# hash = hash of client or IO device
# devtype = Homematic device type
# chn = Channel number, -1=all channels
# oper = Valid operation: 1=Read, 2=Write, 4=Event
# dplistref = Reference for array with datapoints.
# Return number of datapoints.
####################################################

sub HMCCU_GetValidDatapoints ($$$$$)
{
	my ($hash, $devtype, $chn, $oper, $dplistref) = @_;
	
	my $hmccu_hash = HMCCU_GetHash ($hash);
	
	my $ccuflags = AttrVal ($hmccu_hash->{NAME}, 'ccuflags', 'null');
	return 0 if ($ccuflags =~ /dptnocheck/);

	return 0 if (!exists ($hmccu_hash->{hmccu}{dp}));
	
	if (!defined ($chn)) {
		Log3 $hash->{NAME}, 2, $hash->{NAME}.": chn undefined";
		return 0;
	}
	
	if ($chn >= 0) {
		if (exists ($hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chn})) {
			foreach my $dp (sort keys %{$hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chn}}) {
				if ($hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chn}{$dp}{oper} & $oper) {
					push @$dplistref, $dp;
				}
			}
		}
	}
	else {
		if (exists ($hmccu_hash->{hmccu}{dp}{$devtype})) {
			foreach my $ch (sort keys %{$hmccu_hash->{hmccu}{dp}{$devtype}{ch}}) {
				foreach my $dp (sort keys %{$hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$ch}}) {
					if ($hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$ch}{$dp}{oper} & $oper) {
						push @$dplistref, $ch.".".$dp;
					}
				}
			}
		}
	}
	
	return scalar (@$dplistref);
}

####################################################
# Find a datapoint for device type.
# hash = hash of client or IO device
# devtype = Homematic device type
# chn = Channel number, -1=all channels
# oper = Valid operation: 1=Read, 2=Write, 4=Event
# Return channel of first match or -1.
####################################################

sub HMCCU_FindDatapoint ($$$$$)
{
	my ($hash, $devtype, $chn, $dpt, $oper) = @_;
	
	my $hmccu_hash = HMCCU_GetHash ($hash);

	return -1 if (!exists ($hmccu_hash->{hmccu}{dp}));
	
	if ($chn >= 0) {
		if (exists ($hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chn})) {
			foreach my $dp (sort keys %{$hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chn}}) {
				if ($dp eq $dpt && $hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chn}{$dp}{oper} & $oper) {
					return $chn;
				}
			}
		}
	}
	else {
		if (exists ($hmccu_hash->{hmccu}{dp}{$devtype})) {
			foreach my $ch (sort keys %{$hmccu_hash->{hmccu}{dp}{$devtype}{ch}}) {
				foreach my $dp (sort keys %{$hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$ch}}) {
					if ($dp eq $dpt && $hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$ch}{$dp}{oper} & $oper) {
						return $ch;
					}
				}
			}
		}
	}
	
	return -1;
}

####################################################
# Get channel number and datapoint name for special
# datapoint. Valid modes are ontime, ramptime,
# submit, level
####################################################

sub HMCCU_GetSwitchDatapoint ($$$)
{
	my ($hash, $devtype, $mode) = @_;

	my $hmccu_hash = HMCCU_GetHash ($hash);
		
	if (exists ($hmccu_hash->{hmccu}{dp}{$devtype}{spc}{$mode})) {
		return $hmccu_hash->{hmccu}{dp}{$devtype}{spc}{$mode};
	}
	else {
		return '';
	}
}

###########################################################
# Check if datapoint is valid.
# Parameter chn can be a channel address or a channel
# number. Parameter dpt can contain a channel number.
# Parameter oper specifies access flag:
#   1 = datapoint readable
#   2 = datapoint writeable
# Return 1 if ccuflags is set to dptnocheck or datapoint
# is valid. Otherwise 0.
###########################################################

sub HMCCU_IsValidDatapoint ($$$$$)
{
	my ($hash, $devtype, $chn, $dpt, $oper) = @_;
	
	my $hmccu_hash = HMCCU_GetHash ($hash);
	return 0 if (!defined ($hmccu_hash));
	
	if ($hash->{TYPE} eq 'HMCCU' && !defined ($devtype)) {
		$devtype = HMCCU_GetDeviceType ($hmccu_hash, $chn, 'null');
	}
	
	my $ccuflags = AttrVal ($hmccu_hash->{NAME}, 'ccuflags', 'null');
	return 1 if ($ccuflags =~ /dptnocheck/);

	return 1 if (!exists ($hmccu_hash->{hmccu}{dp}));

	my $chnno = $chn;
	if (HMCCU_IsChnAddr ($chn, 0)) {
		my ($a, $c) = split(":",$chn);
		$chnno = $c;
	}
	
	# If datapoint name has format channel-number.datapoint ignore parameter chn
	if ($dpt =~ /^([0-9]{1,2})\.(.+)$/) {
		$chnno = $1;
		$dpt = $2;
	}
	
	return (exists ($hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chnno}{$dpt}) &&
	   ($hmccu_hash->{hmccu}{dp}{$devtype}{ch}{$chnno}{$dpt}{oper} & $oper)) ? 1 : 0;
}

####################################################
# Get list of device or channel addresses for which
# device or channel name matches regular expression.
# Parameter mode can be 'dev' or 'chn'.
# Return number of matching entries.
####################################################

sub HMCCU_GetMatchingDevices ($$$$)
{
	my ($hash, $regexp, $mode, $listref) = @_;
	my $c = 0;

	foreach my $name (sort keys %{$hash->{hmccu}{adr}}) {
		next if ($name !~/$regexp/ || $hash->{hmccu}{adr}{$name}{addtype} ne $mode ||
		   $hash->{hmccu}{adr}{$name}{valid} == 0);
		push (@$listref, $hash->{hmccu}{adr}{$name}{address});
		$c++;
	}

	return $c;
}

####################################################
# Get name of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceName ($$$)
{
	my ($hash, $addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($hash->{hmccu}{dev}{$addr})) {
			return $hash->{hmccu}{dev}{$addr}{name};
		}
	}

	return $default;
}

####################################################
# Get name of a CCU device channel by address.
####################################################

sub HMCCU_GetChannelName ($$$)
{
	my ($hash, $addr, $default) = @_;

	if (HMCCU_IsChnAddr ($addr, 0)) {
		if (exists ($hash->{hmccu}{dev}{$addr})) {
			return $hash->{hmccu}{dev}{$addr}{name};
		}
	}

	return $default;
}

####################################################
# Get type of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceType ($$$)
{
	my ($hash, $addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($hash->{hmccu}{dev}{$addr})) {
			return $hash->{hmccu}{dev}{$addr}{type};
		}
	}

	return $default;
}


####################################################
# Get number of channels of a CCU device.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceChannels ($$$)
{
	my ($hash, $addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($hash->{hmccu}{dev}{$addr})) {
			return $hash->{hmccu}{dev}{$addr}{channels};
		}
	}

	return 0;
}

####################################################
# Get interface of a CCU device by address.
# Channel number will be removed if specified.
####################################################

sub HMCCU_GetDeviceInterface ($$$)
{
	my ($hash, $addr, $default) = @_;

	if (HMCCU_IsDevAddr ($addr, 0) || HMCCU_IsChnAddr ($addr, 0)) {
		$addr =~ s/:[0-9]+$//;
		if (exists ($hash->{hmccu}{dev}{$addr})) {
			return $hash->{hmccu}{dev}{$addr}{interface};
		}
	}

	return $default;
}

####################################################
# Get address of a CCU device or channel by name.
# Return array with device address and channel no.
####################################################

sub HMCCU_GetAddress ($$$$)
{
	my ($hash, $name, $defadd, $defchn) = @_;
	my $add = $defadd;
	my $chn = $defchn;

	if (exists ($hash->{hmccu}{adr}{$name})) {
		# Address known by HMCCU
		my $addr = $hash->{hmccu}{adr}{$name}{address};
		if (HMCCU_IsChnAddr ($addr, 0)) {
			($add, $chn) = split (":", $addr);
		}
		elsif (HMCCU_IsDevAddr ($addr, 0)) {
			$add = $addr;
		}
	}
	else {
		# Address not known. Query CCU
		my $response = HMCCU_GetCCUObjectAttribute ($hash, $name, "Address()");
		if (defined ($response)) {
			if (HMCCU_IsChnAddr ($response, 0)) {
				($add, $chn) = split (":", $response);
				$hash->{hmccu}{adr}{$name}{address} = $response;
				$hash->{hmccu}{adr}{$name}{addtype} = 'chn';
			}
			elsif (HMCCU_IsDevAddr ($response, 0)) {
				$add = $response;
				$hash->{hmccu}{adr}{$name}{address} = $response;
				$hash->{hmccu}{adr}{$name}{addtype} = 'dev';
			}
		}
	}

	return ($add, $chn);
}

####################################################
# Check if parameter is a channel address (syntax)
# f=1: Interface required.
####################################################

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

####################################################
# Check if parameter is a device address (syntax)
# f=1: Interface required.
####################################################

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

####################################################
# Split channel address into device address and
# channel number. Returns device address only if
# parameter is already a device address.
####################################################

sub HMCCU_SplitChnAddr ($)
{
	my ($addr) = @_;

	if (HMCCU_IsChnAddr ($addr, 0)) {
		return split (":", $addr);
	}
	elsif (HMCCU_IsDevAddr ($addr, 0)) {
		return ($addr, '');
	}

	return ('', '');
}

####################################################
# Query object attribute from CCU. Attribute must
# be a valid method for specified object, 
# i.e. Address()
####################################################

sub HMCCU_GetCCUObjectAttribute ($$$)
{
	my ($hash, $object, $attr) = @_;

	my $url = 'http://'.$hash->{host}.':8181/do.exe?r1=dom.GetObject("'.$object.'").'.$attr;
	my $response = GetFileFromURL ($url);
	if (defined ($response) && $response !~ /<r1>null</) {
		if ($response =~ /<r1>(.+)<\/r1>/) {
			return $1;
		}
	}

	return undef;
}

####################################################
# Get hash of HMCCU IO device which is responsible
# for device or channel specified by parameter
####################################################

sub HMCCU_FindIODevice ($)
{
	my ($param) = @_;
	
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		next if (!exists ($ch->{TYPE}));
		next if ($ch->{TYPE} ne 'HMCCU');
		
		return $ch if (HMCCU_IsValidDeviceOrChannel ($ch, $param));
	}
	
	return undef;
}

####################################################
# Get hash of HMCCU IO device. Useful for client
# devices. Accepts hash of HMCCU, HMCCUDEV or 
# HMCCUCHN device as parameter.
####################################################

sub HMCCU_GetHash ($@)
{
	my ($hash) = @_;

	if (defined ($hash) && $hash != 0) {
		if ($hash->{TYPE} eq 'HMCCUDEV' || $hash->{TYPE} eq 'HMCCUCHN') {
			return $hash->{IODev} if (exists ($hash->{IODev}));
			return HMCCU_FindIODevice ($hash->{ccuaddr}) if (exists ($hash->{ccuaddr}));
		}
		elsif ($hash->{TYPE} eq 'HMCCU') {
			return $hash;
		}
	}

	# Search for first HMCCU device
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		next if (!exists ($ch->{TYPE}));
		return $ch if ($ch->{TYPE} eq 'HMCCU');
	}

	return undef;
}

####################################################
# Get attribute of client device with fallback to
# attribute of IO device.
####################################################

sub HMCCU_GetAttribute ($$$$)
{
	my ($hmccu_hash, $cl_hash, $attr_name, $attr_def) = @_;

	my $value = AttrVal ($cl_hash->{NAME}, $attr_name, '');
	$value = AttrVal ($hmccu_hash->{NAME}, $attr_name, $attr_def) if ($value eq '');

	return $value;
}

####################################################
# Get number of occurrences of datapoint.
# Return 0 if datapoint does not exist.
####################################################

sub HMCCU_GetDatapointCount ($$$)
{
	my ($hash, $devtype, $dpt) = @_;
	
	if (exists ($hash->{hmccu}{dp}{$devtype}{cnt}{$dpt})) {
		return $hash->{hmccu}{dp}{$devtype}{cnt}{$dpt};
	}
	else {
		return 0;
	}
}

####################################################
# Get channels and datapoints from attributes
# statechannel, statedatapoint and controldatapoint.
# Return attribute values. Attribute controldatapoint
# is splittet into controlchannel and datapoint name.
# If attribute statedatapoint contains channel number
# it is splitted into statechannel and datapoint
# name.
####################################################

sub HMCCU_GetSpecialDatapoints ($$$$$)
{
#	my ($hash, $defsc, $defsd, $defcc, $defcd) = @_;
	my ($hash, $sc, $sd, $cc, $cd) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};

	my $statedatapoint = AttrVal ($name, 'statedatapoint', '');
	my $statechannel = AttrVal ($name, 'statechannel', '');
	my $controldatapoint = AttrVal ($name, 'controldatapoint', '');
	
	if ($statedatapoint ne '') {
		if ($statedatapoint =~ /^([0-9]+)\.(.+)$/) {
			($sc, $sd) = ($1, $2);
		}
		else {
			$sd = $statedatapoint;
		}
	}
	$sc = $statechannel if ($statechannel ne '' && $sc eq '');

	if ($controldatapoint ne '') {
		if ($controldatapoint =~ /^([0-9]+)\.(.+)$/) {
			($cc, $cd) = ($1, $2);
		}
		else {
			$cd = $controldatapoint;
		}
	}
	
	# For devices of type HMCCUCHN extract channel numbers from CCU device address
	if ($type eq 'HMCCUCHN') {
		$sc = $hash->{ccuaddr};
		$sc =~ s/^[\*]*[0-9A-Z]+://;
		$cc = $sc;
	}
	
	# Try to find state channel and state datapoint
	my $c = -1;
	if ($sc eq '' && $sd ne '') {
		$c = HMCCU_FindDatapoint ($hash, $hash->{ccutype}, -1, $sd, 3);
		$sc = $c if ($c >= 0);
	}
	
	# Try to find control channel
	if ($cc eq '' && $cd ne '') {
		$c = HMCCU_FindDatapoint  ($hash, $hash->{ccutype}, -1, $cd, 3);
		$cc = $c if ($c >= 0);
	}

	return ($sc, $sd, $cc, $cd);
}

######################################################################
# Get reading format considering default attribute
# ccudef-readingformat defined in I/O device.
# Default reading format for virtual groups is always 'name'.
######################################################################

sub HMCCU_GetAttrReadingFormat ($$)
{
	my ($clhash, $iohash) = @_;
	
	my $clname = $clhash->{NAME};
	my $ioname = $iohash->{NAME};
	my $rfdef = '';
	
	if (exists ($clhash->{ccutype}) && $clhash->{ccutype} =~ /^HM-CC-VG/) {
		$rfdef = 'name';
	}
	else {
		$rfdef = AttrVal ($ioname, 'ccudef-readingformat', 'datapoint');
	}
	
	return  AttrVal ($clname, 'ccureadingformat', $rfdef);
}

######################################################################
# Get attributes substitute and substexcl considering default
# attribute ccudef-substitute defined in I/O device.
# Substitute ${xxx} by datapoint value.
######################################################################

sub HMCCU_GetAttrSubstitute ($$)
{
	my ($clhash, $iohash) = @_;
	
	my $clname = $clhash->{NAME};
	my $ioname = $iohash->{NAME};

	my $ccuflags = AttrVal ($clname, 'ccuflags', 'null');
	my $substdef = AttrVal ($ioname, 'ccudef-substitute', '');
	my $subst = AttrVal ($clname, 'substitute', $substdef);
	$subst .= ";$substdef" if ($subst ne $substdef && $substdef ne '');
	Log3 $clname, 2, "HMCCU: GetAttrSubstitute: subst = $subst" if ($ccuflags =~ /trace/);
	
	return $subst if ($subst !~ /\$\{.+\}/);

	$subst = HMCCU_SubstVariables ($clhash, $subst);

	Log3 $clname, 2, "HMCCU: GetAttrSubstitute: subst = $subst" if ($ccuflags =~ /trace/);
	
	return $subst;
}

####################################################
# Clear RPC queue
####################################################

sub HMCCU_ResetRPCQueue ($$)
{
	my ($hash, $port) = @_;
	my $name = $hash->{NAME};

	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
	my $clkey = 'CB'.$port;

	if (HMCCU_QueueOpen ($hash, $rpcqueue."_".$port."_".$hash->{CCUNum})) {
		HMCCU_QueueReset ($hash);
		while (defined (HMCCU_QueueDeq ($hash))) { }
		HMCCU_QueueClose ($hash);
	}
	$hash->{hmccu}{rpc}{$clkey}{queue} = '' if (exists ($hash->{hmccu}{rpc}{$clkey}{queue}));
}

####################################################
# Process RPC server event
####################################################

sub HMCCU_ProcessEvent ($$)
{
	my ($hash, $event) = @_;
	my $name = $hash->{NAME};
	my $rh = \%{$hash->{hmccu}{rpc}};
	
	return undef if (!defined ($event) || $event eq '');

	my @t = split (/\|/, $event);
	my $tc = scalar (@t);

	# Update statistic counters
	if (exists ($hash->{hmccu}{ev}{$t[0]})) {
		$hash->{hmccu}{evtime} = time ();
		$hash->{hmccu}{ev}{total}++;
		$hash->{hmccu}{ev}{$t[0]}++;
		$hash->{hmccu}{evtimeout} = 0 if ($hash->{hmccu}{evtimeout} == 1);
	}
	else {
		my $errtok = $t[0];
		$errtok =~ s/([\x00-\xFF])/sprintf("0x%X ",ord($1))/eg;
		Log3 $name, 2, "HMCCU: Received unknown event from CCU: ".$errtok;
		return undef;
	}
	
	# Check event syntax
	if (exists ($rpceventargs{$t[0]}) && ($tc-1) != $rpceventargs{$t[0]}) {
		Log3 $name, 2, "HMCCU: Wrong number of parameters in event $event";
		return undef;
	}
		
	if ($t[0] eq 'EV') {
		#
		# Update of datapoint
		# Input:  EV|Adress|Datapoint|Value
		# Output: EV, DevAdd, ChnNo, Reading='', Value
		#
		return undef if ($tc != 4 || !HMCCU_IsChnAddr ($t[1], 0));
		my ($add, $chn) = split (/:/, $t[1]);
		HMCCU_UpdateClientReading ($hash, $add, $chn, $t[2], $t[3], 'rpcevent');
		return ($t[0], $add, $chn, '', $t[3]);
	}
	elsif ($t[0] eq 'SL') {
		#
		# RPC server enters server loop
		# Input:  SL|Pid|Servername
		# Output: SL, Servername, Pid
		#
		my $clkey = $t[2];
		if (!exists ($rh->{$clkey})) {
			Log3 $name, 0, "HMCCU: Received SL event for unknown RPC server $clkey";
			return undef;
		}
		Log3 $name, 0, "HMCCU: Received SL event. RPC server $clkey enters server loop";
		$rh->{$clkey}{loop} = 1 if ($rh->{$clkey}{pid} == $t[1]);
		return ($t[0], $clkey, $t[1]);
	}
	elsif ($t[0] eq 'IN') {
		#
		# RPC server initialized
		# Input:  IN|INIT|State|Servername
		# Output: IN, Servername, Running, NotRunning, ClientsUpdated, UpdateErrors
		#
		my $clkey = $t[3];
		my $norun = 0;
		my $run = 0;
		my $c_ok = 0;
		my $c_err = 0;
		if (!exists ($rh->{$clkey})) {
			Log3 $name, 0, "HMCCU: Received IN event for unknown RPC server $clkey";
			return undef;
		}
		Log3 $name, 0, "HMCCU: Received IN event. RPC server $clkey initialized.";
		$rh->{$clkey}{state} = $rh->{$clkey}{pid} > 0 ? "running" : "initialized";
		
		# Check if all RPC servers were initialized. Set overall status
		foreach my $ser (keys %{$rh}) {
			$norun++ if ($rh->{$ser}{state} ne "running" && $rh->{$ser}{pid} > 0);
			$norun++ if ($rh->{$ser}{state} ne "initialized" && $rh->{$ser}{pid} == 0);
			$run++ if ($rh->{$ser}{state} eq "running");
		}
		if ($norun == 0) {
			$hash->{RPCState} = "running";
			readingsSingleUpdate ($hash, "rpcstate", "running", 1);
			HMCCU_SetState ($hash, "OK");
			($c_ok, $c_err) = HMCCU_UpdateClients ($hash, '.*', 'Attr', 0);
			Log3 $name, 2, "HMCCU: Updated devices. Success=$c_ok Failed=$c_err";
			Log3 $name, 1, "HMCCU: All RPC servers running";
			DoTrigger ($name, "RPC server running");
		}
		$hash->{hmccu}{rpcinit} = $run;
		return ($t[0], $clkey, $run, $norun, $c_ok, $c_err);
	}
	elsif ($t[0] eq 'EX') {
		#
		# RPC server shutdown
		# Input:  EX|SHUTDOWN|Pid|Servername
		# Output: EX, Servername, Pid, Flag, Run
		#
		my $clkey = $t[3];
		my $run = 0;
		if (!exists ($rh->{$clkey})) {
			Log3 $name, 0, "HMCCU: Received EX event for unknown RPC server $clkey";
			return undef;
		}
		
		Log3 $name, 0, "HMCCU: Received EX event. RPC server $clkey terminated.";
		my $f = $hash->{RPCState} eq "restarting" ? 2 : 1;
		delete $rh->{$clkey};
	
		# Check if all RPC servers were terminated. Set overall status
		foreach my $ser (keys %{$rh}) {
			$run++ if ($rh->{$ser}{state} ne "stopped");
		}
		if ($run == 0) {
			if ($f == 1) {
				$hash->{RPCState} = "stopped";
				readingsSingleUpdate ($hash, "rpcstate", "stopped", 1);
			}
			$hash->{RPCPID} = '0';
		}
		$hash->{hmccu}{rpccount} = $run;
		$hash->{hmccu}{rpcinit} = $run;
		return ($t[0], $clkey, $t[2], $f, $run);
	}
	elsif ($t[0] eq 'ND' || $t[0] eq 'DD' || $t[0] eq 'RA') {
		#
		# CCU device added, deleted or readded
		# Input:  {ND,DD,RA}|Address
		# Output: {ND,DD,RA}, DevAdd, [ChnType]
		#
		return ($t[0], $t[1], $t[2]);
	}
	elsif ($t[0] eq 'UD') {
		#
		# CCU device updated
		# Input:  UD|Address|Hint
		# Output: UD, DevAdd, Hint
		#
		return ($t[0], $t[1], $t[2]);
	}
	elsif ($t[0] eq 'RD') {
		#
		# CCU device replaced
		# Input:  RD|Address1|Address2
		# Output: RD, Address1, Address2
		#
		return ($t[0], $t[1], $t[2]);
	}
	elsif ($t[0] eq 'ST') {
		#
		# Statistic data. Store snapshots of sent and received events.
		# Input:  ST|nTotal|nEV|nND|nDD|nRD|nRA|nUD|nIN|nSL|nEX
		# Output: ST, ...
		#
		my @stkeys = ('total', 'EV', 'ND', 'DD', 'RD', 'RA', 'UD', 'IN', 'SL', 'EX');
		for (my $i=0; $i<10; $i++) {
			$hash->{hmccu}{evs}{$stkeys[$i]} = $t[$i+1];
			$hash->{hmccu}{evr}{$stkeys[$i]} = $hash->{hmccu}{ev}{$stkeys[$i]};
		}
		return @t;
	}
	else {
		my $errtok = $t[0];
		$errtok =~ s/([\x00-\xFF])/sprintf("0x%X ",ord($1))/eg;
		Log3 $name, 2, "HMCCU: Received unknown event from CCU: ".$errtok;
	}
	
	return undef;
}

####################################################
# Timer function for reading RPC queue
####################################################

sub HMCCU_ReadRPCQueue ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $eventno = 0;
	my $f = 0;
	my @newdevices;
	my @deldevices;
	my @termpids;
	my $newcount = 0;
	my $delcount = 0;

	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $rpcinterval = AttrVal ($name, 'rpcinterval', 5);
	my $rpcqueue = AttrVal ($name, 'rpcqueue', '/tmp/ccuqueue');
#	my $rpcport = AttrVal ($name, 'rpcport', 2001);
	my $rpcport = $hash->{hmccu}{rpcports};
	my $rpctimeout = AttrVal ($name, 'rpcevtimeout', 300);
	my $maxevents = $rpcinterval*10;
	$maxevents = 50 if ($maxevents > 50);
	$maxevents = 10 if ($maxevents < 10);

	my @portlist = split (',', $rpcport);
	foreach my $port (@portlist) {
		my $clkey = 'CB'.$port;
		next if (!exists ($hash->{hmccu}{rpc}{$clkey}{queue}));
		my $queuename = $hash->{hmccu}{rpc}{$clkey}{queue};
		next if ($queuename eq '');
		if (!HMCCU_QueueOpen ($hash, $queuename)) {
			Log3 $name, 1, "HMCCU: Can't open file queue $queuename";
			next;
		}

		my $element = HMCCU_QueueDeq ($hash);
		while (defined ($element)) {
			my ($et, @par) = HMCCU_ProcessEvent ($hash, $element);
			if (defined ($et)) {
				if ($et eq 'EV') {
					$eventno++;
					last if ($eventno == $maxevents);
				}
				elsif ($et eq 'ND') {
					push (@newdevices, $par[0]);
					$newcount++ if (!exists ($hash->{hmccu}{dev}{$par[0]}));
					$hash->{hmccu}{dev}{$par[0]}{chntype} = $par[1];
				}
				elsif ($et eq 'DD') {
					push (@deldevices, $par[0]);
					$delcount++;
				}
				elsif ($et eq 'SL') {
					InternalTimer (gettimeofday()+$HMCCU_INIT_INTERVAL1,
					   'HMCCU_RPCRegisterCallback', $hash, 0);
					return;
				}
				elsif ($et eq 'EX') {
					push (@termpids, $par[1]);
					$f = $par[2];
					last;
				}
			}

			# Read next element from queue
			$element = HMCCU_QueueDeq ($hash);
		}

		HMCCU_QueueClose ($hash);
	}

	# Check if events from CCU timed out
	if ($hash->{hmccu}{evtime} > 0 && time()-$hash->{hmccu}{evtime} > $rpctimeout &&
	   $hash->{hmccu}{evtimeout} == 0) {
	   $hash->{hmccu}{evtimeout} = 1;
		Log3 $name, 2, "HMCCU: Received no events from CCU since $rpctimeout seconds";
		DoTrigger ($name, "No events from CCU since $rpctimeout seconds");
	}

	# CCU devices deleted
	$delcount = scalar @deldevices;
	if ($delcount > 0) {
		HMCCU_DeleteDevices ($hash, \@deldevices);
		$hash->{DelDevices} = $delcount;
		DoTrigger ($name, "$delcount devices deleted in CCU");
	}

	# CCU devices added
	HMCCU_AddDevices ($hash, \@newdevices) if (scalar @newdevices > 0);
	if ($newcount > 0) {
		$hash->{NewDevices} += $newcount;
		DoTrigger ($name, "$newcount devices added in CCU");
	}

	my @hm_pids;
	my @ex_pids;
	HMCCU_IsRPCServerRunning ($hash, \@hm_pids, \@ex_pids);
	my $nhm_pids = scalar (@hm_pids);
	my $nex_pids = scalar (@ex_pids);

	if ($nex_pids > 0) {
		Log3 $name, 1, "HMCCU: Externally launched RPC server(s) detected. Kill process(es) manually with command kill -SIGINT pid for pids ".join (',', @ex_pids)." f=$f";
	}

	if ($f > 0) {
		# At least one RPC server has been stopped. Update PID list
		$hash->{RPCPID} = $nhm_pids > 0 ? join(',',@hm_pids) : '0';
		Log3 $name, 0, "HMCCU: RPC server(s) with PID(s) ".join(',',@termpids)." shut down. f=$f";
			
		# Output statistic counters
		foreach my $cnt (sort keys %{$hash->{hmccu}{ev}}) {
			Log3 $name, 2, "HMCCU: Eventcount $cnt = ".$hash->{hmccu}{ev}{$cnt};
		}
	}

	if ($f == 2 && $nhm_pids == 0) {
		# All RPC servers terminated and restart flag set
		if ($ccuflags =~ /extrpc/) {
			return if (HMCCU_StartExtRPCServer ($hash));
		}
		else {
			return if (HMCCU_StartIntRPCServer ($hash));
		}
		Log3 $name, 0, "HMCCU: Restart of RPC server failed";
	}

	if ($nhm_pids > 0) {
		# Reschedule reading of RPC queues if at least one RPC server is running
		InternalTimer (gettimeofday()+$rpcinterval, 'HMCCU_ReadRPCQueue', $hash, 0);
	}
	else {
		# No more RPC servers active
		Log3 $name, 0, "HMCCU: Periodical check found no RPC Servers";
		# Deregister existing callbacks
		HMCCU_RPCDeRegisterCallback ($hash);
		
		# Cleanup hash variables
		my @clkeylist = keys %{$hash->{hmccu}{rpc}};
		foreach my $clkey (@clkeylist) {
			delete $hash->{hmccu}{rpc}{$clkey};
		}
		$hash->{hmccu}{rpccount} = 0;
		$hash->{hmccu}{rpcinit} = 0;

		$hash->{RPCPID} = '0';
		$hash->{RPCPRC} = 'none';
		$hash->{RPCState} = "stopped";

		Log3 $name, 0, "HMCCU: All RPC servers stopped";
		readingsSingleUpdate ($hash, "rpcstate", "stopped", 1);
		DoTrigger ($name, "All RPC servers stopped");
	}
}

####################################################
# Execute Homematic script on CCU.
# Parameters: hostname, script-code
####################################################

sub HMCCU_HMScript ($$)
{
	my ($hash, $hmscript) = @_;
	my $name = $hash->{NAME};
	my $host = $hash->{host};

	my $url = "http://".$host.":8181/tclrega.exe";
	my $ua = new LWP::UserAgent ();
	my $response = $ua->post($url, Content => $hmscript);

	if (! $response->is_success ()) {
		Log3 $name, 1, "HMCCU: ".$response->status_line();
		return '';
	}
	else {
		my $output = $response->content;
		$output =~ s/<xml>.*<\/xml>//;
		$output =~ s/\r//g;
		return $output;
	}
}

####################################################
# Update a single client device reading considering
# scaling, reading format and value substitution
####################################################

sub HMCCU_UpdateSingleReading ($$$$$)
{
	my ($hash, $chn, $dpt, $readings, $value) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return $value if (!defined ($hmccu_hash));
	my $ioname = $hmccu_hash->{NAME};
	
	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $disable = AttrVal ($name, 'disable', 0);
	return $value if ($ccureadings == 0 || $disable == 1);

	my $hmccuflags = AttrVal ($ioname, 'ccuflags', 'null');
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $readingformat = HMCCU_GetAttrReadingFormat ($hash, $hmccu_hash);
	my $substitute = HMCCU_GetAttrSubstitute ($hash, $hmccu_hash);
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');
	
	$hash->{hmccu}{dp}{"$chn.$dpt"}{VAL} = $value;
	
	my $svalue = HMCCU_ScaleValue ($hash, $dpt, $value, 0);	
	my $fvalue = HMCCU_FormatReadingValue ($hash, $svalue);
	my $cvalue = HMCCU_Substitute ($fvalue, $substitute, 0, $chn, $dpt);
	my %calcs = HMCCU_CalculateReading ($hash, $chn, $dpt);

	readingsBeginUpdate ($hash);
	
	foreach my $rn (@$readings) {
		HMCCU_BulkUpdate ($hash, $rn, $value, $cvalue) if ($rn ne '');
	}
	foreach my $clcr (keys %calcs) {
		HMCCU_BulkUpdate ($hash, $clcr, $calcs{$clcr}, $calcs{$clcr});
	}
	HMCCU_BulkUpdate ($hash, 'control', $fvalue, $cvalue)
		if ($cd ne '' && $dpt eq $cd && $chn eq $cc);
	HMCCU_BulkUpdate ($hash, 'state', $fvalue, $cvalue)
		if ($dpt eq $sd && ($sc eq '' || $sc eq $chn));
		
	if ($hmccuflags !~ /nohmstate/) {
		my ($hms_read, $hms_chn, $hms_dpt, $hms_val) = HMCCU_GetHMState ($name, $ioname, undef);
		HMCCU_BulkUpdate ($hash, $hms_read, $hms_val, $hms_val) if (defined ($hms_val));
	}
	
	readingsEndUpdate ($hash, 1);
	
	return $cvalue;
}

####################################################
# Bulk update of reading considering attribute
# substexcl.
####################################################

sub HMCCU_BulkUpdate ($$$$)
{
	my ($hash, $reading, $orgval, $subval) = @_;

	my $excl = AttrVal ($hash->{NAME}, 'substexcl', '');
	
	readingsBulkUpdate ($hash, $reading, ($excl ne '' && $reading =~ /$excl/ ? $orgval : $subval));
}

####################################################
# Get datapoint and update reading.
####################################################

sub HMCCU_GetDatapoint ($@)
{
	my ($hash, $param) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $hmccu_hash;
	my $value = '';

	$hmccu_hash = HMCCU_GetHash ($hash);
	return (-3, $value) if (!defined ($hmccu_hash));
	return (-4, $value) if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');

	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $readingformat = HMCCU_GetAttrReadingFormat ($hash, $hmccu_hash);
	my ($statechn, $statedpt, $controlchn, $controldpt) = HMCCU_GetSpecialDatapoints (
	   $hash, '', 'STATE', '', '');
	my $ccuget = HMCCU_GetAttribute ($hmccu_hash, $hash, 'ccuget', 'Value');
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $tf = ($ccuflags =~ /trace/) ? 1 : 0;

	my $url = 'http://'.$hmccu_hash->{host}.':8181/do.exe?r1=dom.GetObject("';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hmccu_hash, $param,
		$HMCCU_FLAG_INTERFACE);
	if ($flags == $HMCCU_FLAGS_IACD) {
		$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").'.$ccuget.'()';
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$url .= $nam.'").DPByHssDP("'.$dpt.'").'.$ccuget.'()';
		($add, $chn) = HMCCU_GetAddress ($hmccu_hash, $nam, '', '');
	}
	else {
		return (-1, $value);
	}

	if ($tf) {
		Log3 $name, 2, "$type: GetDatapoint()";
		Log3 $name, 2, "$type:   URL=$url";
		Log3 $name, 2, "$type:   param=$param";
		Log3 $name, 2, "$type:   ccuget=$ccuget";
	}

	my $rawresponse = GetFileFromURL ($url);
	my $response = $rawresponse;
	$response =~ m/<r1>(.*)<\/r1>/;
	$value = $1;

	Log3 ($name, 2, "$type: Response = ".$rawresponse) if ($tf);

	if (defined ($value) && $value ne '' && $value ne 'null') {
		my @readings = HMCCU_GetReadingName ($hash, $int, $add, $chn, $dpt, $nam, $readingformat);
		$value = HMCCU_UpdateSingleReading ($hash, $chn, $dpt, \@readings, $value);

		return (1, $value);
	}
	else {
		Log3 $name, 1, "$type: Error URL = ".$url;
		return (-2, '');
	}
}

####################################################
# Set datapoint
####################################################

sub HMCCU_SetDatapoint ($$$)
{
	my ($hash, $param, $value) = @_;
	my $type = $hash->{TYPE};

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return -3 if (!defined ($hmccu_hash));
	return -4 if ($hash->{ccudevstate} eq 'Deleted');
	my $name = $hmccu_hash->{NAME};
	my $cdname = $hash->{NAME};
	
	my $readingformat = HMCCU_GetAttrReadingFormat ($hash, $hmccu_hash);
	my $ccuflags = AttrVal ($cdname, 'ccuflags', 'null');
	my $ccuverify = AttrVal ($cdname, 'ccuverify', 0); 

	my $url = 'http://'.$hmccu_hash->{host}.':8181/do.exe?r1=dom.GetObject("';
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hmccu_hash, $param,
		$HMCCU_FLAG_INTERFACE);
	return -1 if ($flags != $HMCCU_FLAGS_IACD && $flags != $HMCCU_FLAGS_NCD);
	
	if ($hash->{ccutype} eq 'HM-Dis-EP-WM55' && $dpt eq 'SUBMIT') {
		$value = HMCCU_EncodeEPDisplay ($value);
	}
	else {
		$value = HMCCU_ScaleValue ($hash, $dpt, $value, 1);
	}
	
	if ($flags == $HMCCU_FLAGS_IACD) {
		$url .= $int.'.'.$add.':'.$chn.'.'.$dpt.'").State('.$value.')';
		$nam = HMCCU_GetChannelName ($hmccu_hash, $add.":".$chn, '');
	}
	elsif ($flags == $HMCCU_FLAGS_NCD) {
		$url .= $nam.'").DPByHssDP("'.$dpt.'").State('.$value.')';
		($add, $chn) = HMCCU_GetAddress ($hmccu_hash, $nam, '', '');
	}

	my $addr = $add.":".$chn;
	
	my $response = GetFileFromURL ($url);
	if ($ccuflags =~ /trace/) {
		Log3 $name, 2, "$type: Addr=$addr Name=$nam";
		Log3 $name, 2, "$type: Script response = \n".(defined ($response) ? $response: 'undef');
		Log3 $name, 2, "$type: Script = \n".$url;
	}
	
	return -2 if (!defined ($response) || $response =~ /<r1>null</);

	# Verify setting of datapoint value or update reading with new datapoint value
	if (HMCCU_IsValidDatapoint ($hash, $hash->{ccutype}, $addr, $dpt, 1)) {
		if ($ccuverify == 1) {
#			usleep (100000);
			my ($rc, $result) = HMCCU_GetDatapoint ($hash, $param);
			return $rc;
		}
		elsif ($ccuverify == 2) {
			my @readings = HMCCU_GetReadingName ($hash, $int, $add, $chn, $dpt, $nam, $readingformat);
			HMCCU_UpdateSingleReading ($hash, $chn, $dpt, \@readings, $value);
		}
	}
	
	return 0;
}

####################################################
# Scale, spread and/or shift datapoint value.
# Mode: 0 = Get/Divide, 1 = Set/Multiply
# Supports reversing of value if value range is
# specified. Syntax for Rule is:
#   Datapoint:Factor
#   [!]Datapoint:Min:Max:Range1:Range2
# If Datapoint name starts with a ! the value is
# reversed. In case of an error original value is
# returned.
####################################################

sub HMCCU_ScaleValue ($$$$)
{
	my ($hash, $dpt, $value, $mode) = @_;
	my $name = $hash->{NAME};
	
	my $ccuscaleval = AttrVal ($name, 'ccuscaleval', '');	
	return $value if ($ccuscaleval eq '');

	my @sl = split (',', $ccuscaleval);
	foreach my $sr (@sl) {
		my $f = 1.0;
		my @a = split (':', $sr);
		my $n = scalar (@a);
		next if ($n != 2 && $n != 5);

		my $rev = 0;
		my $dn = $a[0];
		if ($dn =~ /^\!(.+)$/) {
			$dn = $1;
			$rev = 1;
		}		
		next if ($dpt ne $dn);
			
		if ($n == 2) {
			$f = ($a[1] == 0.0) ? 1.0 : $a[1];
			return ($mode == 0) ? $value/$f : $value*$f;
		}
		else {
			# Do not scale if value out of range or interval wrong
			return $value if ($a[1] > $a[2] || $a[3] > $a[4]);
			return $value if ($mode == 0 && ($value < $a[1] || $value > $a[2]));
			return $value if ($mode == 1 && ($value >= $a[1] && $value <= $a[2]));
				
			# Reverse value 
			if ($rev) {
				my $dr = ($mode == 0) ? $a[1]+$a[2] : $a[3]+$a[4];
				$value = $dr-$value;
			}
				
			my $d1 = $a[2]-$a[1];
			my $d2 = $a[4]-$a[3];
			return $value if ($d1 == 0.0 || $d2 == 0.0);
			$f = $d1/$d2;
			return ($mode == 0) ? $value/$f+$a[3] : ($value-$a[3])*$f;
		}
	}
	
	return $value;
}

####################################################
# Get CCU system variables and update readings
####################################################

sub HMCCU_GetVariables ($$)
{
	my ($hash, $pattern) = @_;
	my $count = 0;
	my $result = '';

	my $ccureadings = AttrVal ($hash->{NAME}, 'ccureadings', 1);

	my $script = qq(
object osysvar;
string ssysvarid;
foreach (ssysvarid, dom.GetObject(ID_SYSTEM_VARIABLES).EnumUsedIDs())
{
   osysvar = dom.GetObject(ssysvarid);
   WriteLine (osysvar.Name() # "=" # osysvar.Variable() # "=" # osysvar.Value());
}
	);

	my $response = HMCCU_HMScript ($hash, $script);
	return (-2, $result) if ($response eq '');
  
	readingsBeginUpdate ($hash) if ($ccureadings);

	foreach my $vardef (split /\n/, $response) {
		my @vardata = split /=/, $vardef;
		next if (@vardata != 3);
		next if ($vardata[0] !~ /$pattern/);
		my $value = HMCCU_FormatReadingValue ($hash, $vardata[2]);
		readingsBulkUpdate ($hash, $vardata[0], $value) if ($ccureadings); 
		$result .= $vardata[0].'='.$vardata[2]."\n";
		$count++;
	}

	readingsEndUpdate ($hash, 1) if ($hash->{TYPE} ne 'HMCCU' && $ccureadings);

	return ($count, $result);
}

####################################################
# Set CCU system variable
####################################################

sub HMCCU_SetVariable ($$$)
{
	my ($hash, $param, $value) = @_;
	my $name = $hash->{NAME};
	my $url = 'http://'.$hash->{host}.':8181/do.exe?r1=dom.GetObject("'.$param.'").State("'.$value.'")';

	my $response = GetFileFromURL ($url);
	if (!defined ($response) || $response =~ /<r1>null</) {
		Log3 $name, 1, "HMCCU: URL=$url";
		return -2;
	}

	return 0;
}

########################################################
# Update all datapoints / readings of device or channel
# considering attribute ccureadingfilter.
# Parameter $ccuget can be 'State', 'Value' or 'Attr'.
########################################################

sub HMCCU_GetUpdate ($$$)
{
	my ($cl_hash, $addr, $ccuget) = @_;
	my $name = $cl_hash->{NAME};
	my $type = $cl_hash->{TYPE};

	my $disable = AttrVal ($name, 'disable', 0);
	return 1 if ($disable == 1);

	my $hmccu_hash = HMCCU_GetHash ($cl_hash);
	return -3 if (!defined ($hmccu_hash));
	return -4 if ($type ne 'HMCCU' && $cl_hash->{ccudevstate} eq 'Deleted');

	my $nam = '';
	my $script;

	$ccuget = HMCCU_GetAttribute ($hmccu_hash, $cl_hash, 'ccuget', 'Value') if ($ccuget eq 'Attr');
	my $ccutrace = AttrVal ($hmccu_hash->{NAME}, 'ccutrace', '');
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');

	if (HMCCU_IsChnAddr ($addr, 0)) {
		$nam = HMCCU_GetChannelName ($hmccu_hash, $addr, '');
		return -1 if ($nam eq '');
		my ($stadd, $stchn) = HMCCU_SplitChnAddr ($addr);
		my $stnam = HMCCU_GetChannelName ($hmccu_hash, "$stadd:0", '');
		my $chnlist = $stnam eq '' ? $nam : $stnam . "," . $nam;

		$script = qq(
string sDPId;
string sChnName;
string sChnList = "$chnlist";
integer c = 0;
foreach (sChnName, sChnList.Split(",")) {
  object oChannel = dom.GetObject (sChnName);
  if (oChannel) {
    foreach(sDPId, oChannel.DPs()) {
      object oDP = dom.GetObject(sDPId);
      if (oDP) {
        if (OPERATION_READ & oDP.Operations()) {
          WriteLine (sChnName # "=" # oDP.Name() # "=" # oDP.$ccuget());
          c = c+1;
        }
      }
    }
  }
}
WriteLine (c);
		);
	}
	elsif (HMCCU_IsDevAddr ($addr, 0)) {
		$nam = HMCCU_GetDeviceName ($hmccu_hash, $addr, '');
		return -1 if ($nam eq '');

		$script = qq(
string chnid;
string sDPId;
integer c = 0;
object odev = dom.GetObject ("$nam");
if (odev) {
  foreach (chnid, odev.Channels()) {
    object ochn = dom.GetObject(chnid);
    if (ochn) {
      foreach(sDPId, ochn.DPs()) {
        object oDP = dom.GetObject(sDPId);
        if (oDP) {
          if (OPERATION_READ & oDP.Operations()) {
            WriteLine (ochn.Name() # "=" # oDP.Name() # "=" # oDP.$ccuget());
            c = c+1;
          }
        }
      }
    }
  }
  WriteLine (c);
}
		);
	}
	else {
		return -1;
	}

	my $response = HMCCU_HMScript ($hmccu_hash, $script);
	if (($ccutrace ne '' && ($addr =~ /$ccutrace/ || $nam =~ /$ccutrace/)) || $ccuflags =~ /trace/) {
		Log3 $name, 2, "HMCCU: Addr=$addr Name=$nam";
		Log3 $name, 2, "HMCCU: Script response = \n".$response;
		Log3 $name, 2, "HMCCU: Script = \n".$script;
	}
	return -2 if ($response eq '');

	my @dpdef = split /\n/, $response;
	my $count = pop (@dpdef);
	return -10 if (!defined ($count) || $count == 0);

	# Update client device
	my $rc = HMCCU_UpdateDeviceReadings ($cl_hash, \@dpdef);
	return $rc if ($rc < 0);

	# Update virtual devices
	my ($da, $cno) = HMCCU_SplitChnAddr ($cl_hash->{ccuaddr});
	foreach my $dn (sort keys %defs) {
		my $ch = $defs{$dn};
		next if (!exists ($ch->{NAME}) || !exists ($ch->{TYPE}));
		next if ($ch->{TYPE} ne 'HMCCUDEV');
		next if ($ch->{ccuif} ne "VirtualDevices" || !exists ($ch->{ccugroup}));
		my @vdevs = split (",", $ch->{ccugroup});
		if ((grep { $_ eq $da } @vdevs) ||
		   ($cno ne '' && (grep { $_ eq $cl_hash->{ccuaddr} } @vdevs))) {
			HMCCU_UpdateDeviceReadings ($ch, \@dpdef);
		}
	}

	return 1;
}

####################################################
# Update readings of client device. Parameter dp
# is a reference to an array of datapoint=value
# pairs. Returns number of updated readings.
####################################################

sub HMCCU_UpdateDeviceReadings ($$)
{
	my ($cl_hash, $dp) = @_;
	my $cn = $cl_hash->{NAME};

	my $uc = 0;

	my $hmccu_hash = HMCCU_GetHash ($cl_hash);
	return 0 if (!defined ($hmccu_hash));
	my $ioname = $hmccu_hash->{NAME};

	my $disable = AttrVal ($cn, 'disable', 0);
	return 0 if ($disable == 1);
	my $ccureadings = AttrVal ($cn, 'ccureadings', 1);
	return -6 if ($ccureadings == 0);
	
	my $hmccuflags = AttrVal ($ioname, 'ccuflags', 'null');
	my $ccuflags = AttrVal ($cn, 'ccuflags', 'null');
	my $readingformat = HMCCU_GetAttrReadingFormat ($cl_hash, $hmccu_hash);
	my $substitute = HMCCU_GetAttrSubstitute ($cl_hash, $hmccu_hash);
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($cl_hash, '', 'STATE', '', '');

	readingsBeginUpdate ($cl_hash);

	# Process all datapoints
	# Format is: ChannelName=Interface.ChannelAddress.Datapoint=Value
	foreach my $dpdef (@$dp) {
		my @dpdata = split /=/, $dpdef;
		next if (@dpdata < 2);
		my @adrtoks = split /\./, $dpdata[1];
		next if (@adrtoks != 3);
                 
		my ($add, $chn) = split /:/, $adrtoks[1];
		my $dpt = $adrtoks[2];
		my $value = (defined ($dpdata[2]) && $dpdata[2] ne '') ? $dpdata[2] : 'N/A';
                 
		$cl_hash->{hmccu}{dp}{"$chn.$dpt"}{VAL} = $value;

		if (HMCCU_FilterReading ($cl_hash, $adrtoks[1], $dpt)) {		
			my @readings = HMCCU_GetReadingName ($cl_hash, $adrtoks[0], $add, $chn, $dpt,
				$dpdata[0], $readingformat);
			my $svalue = HMCCU_ScaleValue ($cl_hash, $dpt, $value, 0);	
			my $fvalue = HMCCU_FormatReadingValue ($cl_hash, $svalue);
			my $cvalue = HMCCU_Substitute ($fvalue, $substitute, 0, $chn, $dpt);
			my %calcs = HMCCU_CalculateReading ($cl_hash, $chn, $dpt);

			foreach my $rn (@readings) {
				HMCCU_BulkUpdate ($cl_hash, $rn, $value, $cvalue) if ($rn ne '');
			}
			foreach my $clcr (keys %calcs) {
				HMCCU_BulkUpdate ($cl_hash, $clcr, $calcs{$clcr}, $calcs{$clcr});
			}
			HMCCU_BulkUpdate ($cl_hash, 'control', $fvalue, $cvalue)
				if ($cd ne '' && $adrtoks[2] eq $cd && $chn eq $cc);
			HMCCU_BulkUpdate ($cl_hash, "state", $fvalue, $cvalue)
				if (($adrtoks[2] eq $sd) && ($sc eq '' || $sc eq $chn));
			$uc++;
		}
	}

	# Get HomeMatic state
	if ($hmccuflags !~ /nohmstate/) {
		my ($hms_read, $hms_chn, $hms_dpt, $hms_val) = HMCCU_GetHMState ($cn, $ioname, undef);
		HMCCU_BulkUpdate ($cl_hash, $hms_read, $hms_val, $hms_val) if (defined ($hms_val));
	}
	
	readingsEndUpdate ($cl_hash, 1);

	return $uc;
}

####################################################
# Get multiple datapoints of channels and update
# readings.
# If hash points to client device only readings
# of client device will be updated.
# Returncodes: -1 = Invalid channel/datapoint
#              -2 = CCU script execution failed
#              -3 = Cannot detect IO device
# On success number of updated readings is returned.
####################################################

sub HMCCU_GetChannel ($$)
{
	my ($hash, $chnref) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $count = 0;
	my %chnpars;
	my $chnlist = '';
	my $result = '';

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return (-3, $result) if (!defined ($hmccu_hash));;
	return (-4, $result) if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');
	my $type_hash = $type eq 'HMCCU' ? $hmccu_hash : $hash;
	my $ioname = $hmccu_hash->{NAME};

	my $hmccuflags = AttrVal ($ioname, 'ccuflags', 'null');
	my $ccuget = HMCCU_GetAttribute ($hmccu_hash, $hash, 'ccuget', 'Value');
	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $ccuflags = AttrVal ($name, 'ccuflags', 'null');
	my $readingformat = AttrVal ($name, 'ccureadingformat', 'name');
	my $defsubstitute = AttrVal ($name, 'substitute', '');
	my ($sc, $sd, $cc, $cd) = HMCCU_GetSpecialDatapoints ($hash, '', 'STATE', '', '');

	# Build channel list
	foreach my $chndef (@$chnref) {
		my ($channel, $substitute) = split /\s+/, $chndef;
		next if (!defined ($channel) || $channel =~ /^#/ || $channel eq '');
		$substitute = $defsubstitute if (!defined ($substitute));
		my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hmccu_hash, $channel,
		   $HMCCU_FLAG_INTERFACE | $HMCCU_FLAG_DATAPOINT);
		if ($flags == $HMCCU_FLAGS_IACD || $flags == $HMCCU_FLAGS_NCD) {
			if ($flags == $HMCCU_FLAGS_IACD) {
				$nam = HMCCU_GetChannelName ($hmccu_hash, $add.':'.$chn, '');
			}

			$chnlist = $chnlist eq '' ? $nam : $chnlist.','.$nam;
			$chnpars{$nam}{sub} = $substitute;
			$chnpars{$nam}{dpt} = $dpt;
		}
		else {
			return (-1, $result);
		}
	}

	return (0, $result) if ($chnlist eq '');

	# CCU script to query datapoints
	my $script = qq(
string sDPId;
string sChannel;
string sChnList = "$chnlist";
foreach (sChannel, sChnList.Split(",")) {
  object oChannel = dom.GetObject (sChannel);
  if (oChannel) {
    foreach(sDPId, oChannel.DPs()) {
      object oDP = dom.GetObject(sDPId);
      if (oDP) {
        WriteLine (sChannel # "=" # oDP.Name() # "=" # oDP.$ccuget());
      }
    }
  }
}
	);

	my $response = HMCCU_HMScript ($hmccu_hash, $script);
	return (-2, $result) if ($response eq '');
  
	readingsBeginUpdate ($hash) if ($type ne 'HMCCU' && $ccureadings);

	foreach my $dpdef (split /\n/, $response) {
		my @dpdata = split /=/, $dpdef;
		next if (@dpdata != 3);
		my @adrtoks = split /\./, $dpdata[1];
		next if (@adrtoks != 3);
		next if ($adrtoks[2] !~ /$chnpars{$dpdata[0]}{dpt}/);
                 
		my ($add, $chn) = split /:/, $adrtoks[1];
		my $dpt = $adrtoks[2];		
		my $value;
                 
		if ($hash->{TYPE} eq 'HMCCU') {
			$value = HMCCU_Substitute ($dpdata[2], $chnpars{$dpdata[0]}{sub}, 0, $chn, $dpt);
			HMCCU_UpdateClientReading ($hmccu_hash, $add, $chn, $dpt, $value);
		}
		else {
			$hash->{hmccu}{dp}{"$chn.$dpt"}{VAL} = $value;

			$value = HMCCU_ScaleValue ($hash, $dpt, $dpdata[2], 0);	
			my $fvalue = HMCCU_FormatReadingValue ($hash, $value);
			my $cvalue = HMCCU_Substitute ($fvalue, $chnpars{$dpdata[0]}{sub}, 0, $chn, $dpt);
			my %calcs = HMCCU_CalculateReading ($hash, $chn, $dpt);
			
			my @readings = HMCCU_GetReadingName ($type_hash, $adrtoks[0], $add, $chn, $dpt,
		   	$dpdata[0], $readingformat);
			
			if ($ccureadings) {
				foreach my $rn (@readings) {
					next if ($rn eq '');
					HMCCU_BulkUpdate ($hash, $rn, $value, $cvalue);
					$result .= $rn.'='.$cvalue."\n";
				}
				foreach my $clcr (keys %calcs) {
					HMCCU_BulkUpdate ($hash, $clcr, $calcs{$clcr}, $calcs{$clcr});
					$result .= $clcr.'='.$calcs{$clcr}."\n";
				}
				HMCCU_BulkUpdate ($hash, 'control', $fvalue, $cvalue)
					if ($cd ne '' && $adrtoks[2] eq $cd && $chn eq $cc);
				HMCCU_BulkUpdate ($hash, 'state', $fvalue, $cvalue)
					if (($adrtoks[2] eq $sd) && ($sc eq '' || $sc eq $chn));
			}
			$value = $cvalue;
		}

		$count++;
	}

	if ($hmccuflags !~ /nohmstate/) {
		my ($hms_read, $hms_chn, $hms_dpt, $hms_val) = HMCCU_GetHMState ($name, $ioname, undef);
		HMCCU_BulkUpdate ($hash, $hms_read, $hms_val, $hms_val) if (defined ($hms_val));
	}
	
	readingsEndUpdate ($hash, 1) if ($type ne 'HMCCU' && $ccureadings);

	return ($count, $result);
}

####################################################
# Get RPC paramSet or paramSetDescription
####################################################

sub HMCCU_RPCGetConfig ($$$$)
{
	my ($hash, $param, $mode, $filter) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};
	my $method = $mode eq 'listParamset' ? 'getParamset' : $mode;
	
	my $addr;
	my $result = '';

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return (-3, $result) if (!defined ($hmccu_hash));
	return (-4, $result) if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');

	my $ccureadings = AttrVal ($name, 'ccureadings', 1);
	my $readingformat = HMCCU_GetAttrReadingFormat ($hash, $hmccu_hash);
	my $substitute = HMCCU_GetAttrSubstitute ($hash, $hmccu_hash);
	
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hmccu_hash, $param,
		$HMCCU_FLAG_FULLADDR);
	return (-1, '') if (!($flags & $HMCCU_FLAG_ADDRESS));
	$addr = $add;
	$addr .= ':'.$chn if ($flags & $HMCCU_FLAG_CHANNEL);

	return (-9, '') if (!exists ($HMCCU_RPC_PORT{$int}));
	my $port = $HMCCU_RPC_PORT{$int};
	my $url = "http://".$hmccu_hash->{host}.":".$port."/";
	$url .= $HMCCU_RPC_URL{$port} if (exists ($HMCCU_RPC_URL{$port}));
	my $client = RPC::XML::Client->new ($url);

	my $res = $client->simple_request ($method, $addr, "MASTER");
	if (! defined ($res)) {
		return (-5, "Function not available");
	}
	elsif (ref ($res)) {
		my $parcount = scalar (keys %$res);
		if (exists ($res->{faultString})) {
			Log3 $name, 1, "HMCCU: ".$res->{faultString};
			return (-2, $res->{faultString});
		}
		elsif ($parcount == 0) {
			return (-5, "CCU returned no data");
		}
	}
	else {
		return (-2, defined ($RPC::XML::ERROR) ? $RPC::XML::ERROR : '');
	}

	if ($mode eq 'getParamsetDescription') {
		foreach my $key (sort keys %$res) {
			my $oper = '';
			$oper .= 'R' if ($res->{$key}->{OPERATIONS} & 1);
			$oper .= 'W' if ($res->{$key}->{OPERATIONS} & 2);
			$oper .= 'E' if ($res->{$key}->{OPERATIONS} & 4);
			$result .= $key.": ".$res->{$key}->{TYPE}." [".$oper."]\n";
		}
	}
	elsif ($mode eq 'listParamset') {
		foreach my $key (sort keys %$res) {
			next if ($key !~ /$filter/);
			my $value = $res->{$key};
			$result .= "$key=$value\n";
		}
	}
	else {
		readingsBeginUpdate ($hash) if ($ccureadings);

		foreach my $key (sort keys %$res) {
			next if ($key !~ /$filter/);
			my $value = $res->{$key};
			$result .= "$key=$value\n";
			next if (!$ccureadings);
			
			$value = HMCCU_FormatReadingValue ($hash, $value);
			$value = HMCCU_Substitute ($value, $substitute, 0, $chn, $key);
			my @readings = HMCCU_GetReadingName ($hash, $int, $add, $chn, $key, $nam, $readingformat);
			foreach my $rn (@readings) {
				next if ($rn eq '');
				$rn = "R-".$rn;
				readingsBulkUpdate ($hash, $rn, $value);
			}
		}

		readingsEndUpdate ($hash, 1) if ($ccureadings);
	}

	return (0, $result);
}

####################################################
# Set RPC paramSet
####################################################

sub HMCCU_RPCSetConfig ($$$)
{
	my ($hash, $param, $parref) = @_;
	my $name = $hash->{NAME};
	my $type = $hash->{TYPE};

	my $addr;
	my %paramset;

	my $hmccu_hash = HMCCU_GetHash ($hash);
	return -3 if (!defined ($hmccu_hash));
	return -4 if ($type ne 'HMCCU' && $hash->{ccudevstate} eq 'Deleted');
	
	my ($int, $add, $chn, $dpt, $nam, $flags) = HMCCU_ParseObject ($hmccu_hash, $param,
		$HMCCU_FLAG_FULLADDR);
	return -1 if (!($flags & $HMCCU_FLAG_ADDRESS));
	$addr = $add;
	$addr .= ':'.$chn if ($flags & $HMCCU_FLAG_CHANNEL);

	return -9 if (!exists ($HMCCU_RPC_PORT{$int}));
	my $port = $HMCCU_RPC_PORT{$int};
	my $url = "http://".$hmccu_hash->{host}.":".$port."/";
	$url .= $HMCCU_RPC_URL{$port} if (exists ($HMCCU_RPC_URL{$port}));
	
	# Build param set
# 	foreach my $pardef (@$parref) {
# 		my ($par,$val) = split ("=", $pardef);
# 		next if (!defined ($par) || !defined ($val));
# 		$paramset{$par} = $val;
# 	}
	
	my $client = RPC::XML::Client->new ($url);
#	my $res = $client->simple_request ("putParamset", $addr, "MASTER", \%paramset);
	my $res = $client->simple_request ("putParamset", $addr, "MASTER", $parref);
	if (! defined ($res)) {
		return -5;
	}
	elsif (ref ($res)) {
		if (exists ($res->{faultString})) {
			Log3 $name, 1, "HMCCU: ".$res->{faultString};
			return -2;
		}
	}
	
	return 0;
}

sub HMCCU_QueueOpen ($$)
{
	my ($hash, $queue_file) = @_;
	
	my $idx_file = $queue_file . '.idx';
	$queue_file .= '.dat';
	my $mode = '0666';

	umask (0);
	
	$hash->{hmccu}{queue}{block_size} = 64;
	$hash->{hmccu}{queue}{seperator} = "\n";
	$hash->{hmccu}{queue}{sep_length} = length $hash->{hmccu}{queue}{seperator};

	$hash->{hmccu}{queue}{queue_file} = $queue_file;
	$hash->{hmccu}{queue}{idx_file} = $idx_file;

	$hash->{hmccu}{queue}{queue} = new IO::File $queue_file, O_CREAT | O_RDWR, oct($mode) or return 0;
	$hash->{hmccu}{queue}{idx} = new IO::File $idx_file, O_CREAT | O_RDWR, oct($mode) or return 0;

	### Default ptr to 0, replace it with value in idx file if one exists
	$hash->{hmccu}{queue}{idx}->sysseek(0, SEEK_SET); 
	$hash->{hmccu}{queue}{idx}->sysread($hash->{hmccu}{queue}{ptr}, 1024);
	$hash->{hmccu}{queue}{ptr} = '0' unless $hash->{hmccu}{queue}{ptr};
  
	if($hash->{hmccu}{queue}{ptr} > -s $queue_file)
	{
		$hash->{hmccu}{queue}{idx}->truncate(0) or return 0;
		$hash->{hmccu}{queue}{idx}->sysseek(0, SEEK_SET); 
		$hash->{hmccu}{queue}{idx}->syswrite('0') or return 0;
	}
	
	return 1;
}

sub HMCCU_QueueClose ($)
{
	my ($hash) = @_;
	
	if (exists ($hash->{hmccu}{queue})) {
		$hash->{hmccu}{queue}{idx}->close();
		$hash->{hmccu}{queue}{queue}->close();
		delete $hash->{hmccu}{queue};
	}
}

sub HMCCU_QueueReset ($)
{
	my ($hash) = @_;

	$hash->{hmccu}{queue}{idx}->truncate(0) or return 0;
	$hash->{hmccu}{queue}{idx}->sysseek(0, SEEK_SET); 
	$hash->{hmccu}{queue}{idx}->syswrite('0') or return 0;

	$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr} = 0, SEEK_SET); 
  
	return 1;
}

sub HMCCU_QueueEnq ($$)
{
	my ($hash, $element) = @_;

	return 0 if (!exists ($hash->{hmccu}{queue}));
	
	$hash->{hmccu}{queue}{queue}->sysseek(0, SEEK_END); 
	$element =~ s/$hash->{hmccu}{queue}{seperator}//g;
	$hash->{hmccu}{queue}{queue}->syswrite($element.$hash->{hmccu}{queue}{seperator}) or return 0;
  
	return 1;  
}

sub HMCCU_QueueDeq ($)
{
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $sep_length = $hash->{hmccu}{queue}{sep_length};
	my $element = '';

	return undef if (!exists ($hash->{hmccu}{queue}));

	$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr}, SEEK_SET);

	my $i;
	while($hash->{hmccu}{queue}{queue}->sysread($_, $hash->{hmccu}{queue}{block_size})) {
		$i = index($_, $hash->{hmccu}{queue}{seperator});
		if($i != -1) {
			$element .= substr($_, 0, $i);
			$hash->{hmccu}{queue}{ptr} += $i + $sep_length;
			$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr}, SEEK_SET);
			last;
		}
		else {
			# Seperator not found, go back 'sep_length' spaces to ensure we don't miss it between reads
			Log3 $name, 2, "HMCCU: HMCCU_QueueDeq seperator not found";
			$element .= substr($_, 0, -$sep_length, '');
			$hash->{hmccu}{queue}{ptr} += $hash->{hmccu}{queue}{block_size} - $sep_length;
			$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr}, SEEK_SET);
		}
	}

	## If queue seek pointer is at the EOF, truncate the queue file
	if($hash->{hmccu}{queue}{queue}->sysread($_, 1) == 0)
	{
		$hash->{hmccu}{queue}{queue}->truncate(0) or return undef;
		$hash->{hmccu}{queue}{queue}->sysseek($hash->{hmccu}{queue}{ptr} = 0, SEEK_SET);
	}

	## Set idx file contents to point to the current seek position in queue file
	$hash->{hmccu}{queue}{idx}->truncate(0) or return undef;
	$hash->{hmccu}{queue}{idx}->sysseek(0, SEEK_SET);
	$hash->{hmccu}{queue}{idx}->syswrite($hash->{hmccu}{queue}{ptr}) or return undef;

	return ($element ne '') ? $element : undef;
}

######################################################################
# HELPER FUNCTIONS
######################################################################

######################################################################
# Determine HomeMatic state considering datapoint values specified
# in attributes ccudef-hmstatevals and hmstatevals.
# Return (reading, channel, datapoint, value)
######################################################################

sub HMCCU_GetHMState ($$$)
{
	my ($name, $ioname, $defval) = @_;
	my @hmstate = ('hmstate', undef, undef, $defval);

	my $clhash = $defs{$name};
	my $cltype = $clhash->{TYPE};
	return @hmstate if ($cltype ne 'HMCCUDEV' && $cltype ne 'HMCCUCHN');
	
	my $ghmstatevals = AttrVal ($ioname, 'ccudef-hmstatevals',
		'^UNREACH!(1|true):unreachable;^LOW_?BAT!(1|true):warn_battery');
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
	$hmstatevals = HMCCU_SubstVariables ($clhash, $hmstatevals);

	my @rulelist = split (";", $hmstatevals);
	foreach my $rule (@rulelist) {
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
		my $value = HMCCU_FormatReadingValue ($clhash, $clhash->{hmccu}{dp}{$dp}{VAL});
		my ($rc, $newvalue) = HMCCU_SubstRule ($value, $subst, 0);
		return ($hmstate[0], $chn, $dpt, $newvalue) if ($rc);
	}

# 	foreach my $dp (keys %{$clhash->{hmccu}{dp}}) {
# 		next if (!defined ($clhash->{hmccu}{dp}{$dp}{VAL}));
# 		my ($chn, $dpt) = split (/\./, $dp);
# 		my $value = $clhash->{hmccu}{dp}{$dp}{VAL};
# 		
# 		foreach my $rule (@rulelist) {
# 			my ($dptexpr, $subst) = split ('!', $rule, 2);
# 			next if (!defined ($dptexpr) || !defined ($subst));
# 			next if ($dpt !~ /$dptexpr/);
# 			$subst =~ s/\$\{value\}/$value/g;
# 			my ($rc, $newvalue) = HMCCU_SubstRule ($value, $subst, 0);
# 			return ($hmstate[0], $chn, $dpt, $newvalue) if ($rc);
# 		}
# 	}
	
	return @hmstate;
}
	

####################################################
# Aggregate readings. Valid operations are 'and',
# 'or' or 'cnt'.
# and: return v1 if all readings matching v1,
#      otherwise return v2.
# or:  return v1 if at least 1 reading matches v1,
#      otherwise return v2.
# cnt: return number of readings matching v1.
# Ex 1: number of open windows: state, "cnt", "open", ""
# Ex 2: Status of windows: state, "and", "close", "open"
####################################################

sub HMCCU_AggReadings ($$$$$)
{
	my ($name, $readexp, $oper, $v1, $v2) = @_;

	return undef if (!exists ($defs{$name}));

	my $mc = 0;
	my $c = 0;

	foreach my $r (keys %{$defs{$name}{READINGS}}) {
		next if ($r !~ /$readexp/);
		$c++;
		$mc++ if ($defs{$name}{READINGS}{$r}{VAL} eq $v1);
	}

	if ($oper eq 'and') {
		return ($mc < $c) ? $v2 : $v1;
	}
	elsif ($oper eq 'or') {
		return ($mc > 0) ? $v1 : $v2;
	}
	else {
		return $mc;
	}
}

####################################################
# Calculate time difference in seconds between
# current time and specified timestamp
####################################################

sub HMCCU_GetTimeSpec ($)
{
	my ($ts) = @_;
	
	return -1 if ($ts !~ /^[0-9]{2}:[0-9]{2}$/ && $ts !~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}$/);
	
	my (undef, $h, $m, $s)  = GetTimeSpec ($ts);
	return -1 if (!defined ($h));
	
	$s += $h*3600+$m*60;
	my @lt = localtime;
	my $cs = $lt[2]*3600+$lt[1]*60+$lt[0];
	$s += 86400 if ($cs > $s);
	
	return ($s-$cs);
}

####################################################
# Calculate dewpoint. Requires reading names of
# temperature and humidity as parameters.
####################################################

sub HMCCU_Dewpoint ($$$$)
{
	my ($name, $rtmp, $rhum, $defdp) = @_;
	my $a;
	my $b;

	my $tmp = ReadingsVal ($name, $rtmp, 100.0);
	my $hum = ReadingsVal ($name, $rhum, 0.0);
	return $defdp if ($tmp == 100.0 || $hum == 0.0);

	if ($tmp >= 0.0) {
		$a = 7.5;
		$b = 237.3;
	}
	else {
		$a = 7.6;
		$b = 240.7;
	}

	my $sdd = 6.1078*(10.0**(($a*$tmp)/($b+$tmp)));
	my $dd = $hum/100.0*$sdd;
	my $v = log($dd/6.1078)/log(10.0);
	my $td = $b*$v/($a-$v);

	return sprintf "%.1f", $td;
}

####################################################
# Calculate special readings. Requires hash of
# client device and channel number and datapoint.
# Return readings.
####################################################

sub HMCCU_CalculateReading ($$$)
{
	my ($cl_hash, $chnno, $dpt) = @_;
	my $name = $cl_hash->{NAME};
	
	my @result = ();
	
	my $ccucalculate = AttrVal ($name, 'ccucalculate', '');
	return @result if ($ccucalculate eq '');
	
	my @calclist = split (';', $ccucalculate);
	foreach my $calculation (@calclist) {
		my ($valuetype, $reading, $datapoints) = split (':', $calculation);
		next if (!defined ($reading));

		my @dplist = defined ($datapoints) ? split (',', $datapoints) : ();
		next if (@dplist > 0 && !(grep { $_ eq "$chnno.$dpt"} @dplist));
		my @pars = ();
		foreach my $dp (@dplist) {
			if (exists ($cl_hash->{hmccu}{dp}{$dp}{VAL})) {
				push @pars, $cl_hash->{hmccu}{dp}{$dp}{VAL};
			}
		}
		
		if ($valuetype eq 'dewpoint') {
			next if (@pars < 2);
			my ($tmp, $hum) = @pars;
			if ($tmp >= 0.0) {
				$a = 7.5;
				$b = 237.3;
			}
			else {
				$a = 7.6;
				$b = 240.7;
			}

			my $sdd = 6.1078*(10.0**(($a*$tmp)/($b+$tmp)));
			my $dd = $hum/100.0*$sdd;
			my $v = log($dd/6.1078)/log(10.0);
			my $td = $b*$v/($a-$v);
			
			push (@result, $reading, (sprintf "%.1f", $td));
		}
	}
	
	return @result;
}

####################################################
# Encode command string for e-paper display
#
# Parameters:
#
#  msg := parameter=value[,...]
#
#  text1-3=Text
#  icon1-3=Icon
#  sound=
#  signal=
#  pause=1-160
#  repeat=0-15
#
# Returns undef on error or encoded string on success
####################################################

sub HMCCU_EncodeEPDisplay ($)
{
	my ($msg) = @_;
	
	# set defaults
	$msg = '' if (!defined ($msg));
	
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

	# Parse command string
	my @text = ('', '', '');
	my @icon = ('', '', '');
	my %conf = (sound => 'snd_off', signal => 'sig_off', repeat => 1, pause => 10);
	foreach my $tok (split (',', $msg)) {
		my ($par, $val) = split ('=', $tok);
		next if (!defined ($val));
		if ($par =~ /^text([1-3])$/) {
			$text[$1-1] = substr ($val, 0, 12);
		}
		elsif ($par =~ /^icon([1-3])$/) {
			$icon[$1-1] = $val;
		}
		elsif ($par =~ /^(sound|pause|repeat|signal)$/) {
			$conf{$1} = $val;
		}
	}
	
	my $cmd = '0x02,0x0A';

	for (my $c=0; $c<3; $c++) {
		if ($text[$c] ne '' || $icon[$c] ne '') {
			$cmd .= ',0x12';
			
			# Hex code
			if ($text[$c] =~ /^0x[0-9A-F]{2}$/) {
				$cmd .= ','.$text[$c];
			}
			# Predefined text code #0-9
			elsif ($text[$c] =~ /^#([0-9])$/) {
				$cmd .= sprintf (",0x8%1X", $1);
			}
			# Convert string to hex codes
			else {
				$text[$c] =~ s/\\_/ /g;
				foreach my $ch (split ('', $text[$c])) {
					$cmd .= sprintf (",0x%02X", ord ($ch));
				}
			}
			
			# Icon
			if ($icon[$c] ne '' && exists ($disp_icons{$icon[$c]})) {
				$cmd .= ',0x13,'.$disp_icons{$icon[$c]};
			}
		}
		
		$cmd .= ',0x0A';
	}
	
	# Sound
	my $snd = $disp_sounds{snd_off};
	$snd = $disp_sounds{$conf{sound}} if (exists ($disp_sounds{$conf{sound}}));
	$cmd .= ',0x14,'.$snd.',0x1C';

	# Repeat
	my $rep = $conf{repeat} if ($conf{repeat} >= 0 && $conf{repeat} <= 15);
	$rep = 1 if ($rep < 0);
	$rep = 15 if ($rep > 15);
	if ($rep == 0) {
		$cmd .= ',0xDF';
	}
	else {
		$cmd .= sprintf (",0x%02X", 0xD0+$rep-1);
	}
	$cmd .= ',0x1D';
	
	# Pause
	my $pause = $conf{pause};
	$pause = 1 if ($pause < 1);
	$pause = 160 if ($pause > 160);
	$cmd .= sprintf (",0xE%1X,0x16", int(($pause-1)/10));
	
	# Signal
	my $sig = $disp_signals{sig_off};
	$sig = $disp_signals{$conf{signal}} if (exists ($disp_signals{$conf{signal}}));
	$cmd .= ','.$sig.',0x03';
	
	return '"'.$cmd.'"';
}



##################################################
#             *** Subprocess part ***
##################################################

# Child process. Must be global to allow access by RPC callbacks
my $hmccu_child;

# Queue file
my %child_queue;
my $cpqueue = \%child_queue;

# Statistic data of child process
my %child_hash = (
	"total", 0,
	"writeerror", 0,
	"EV", 0,
	"ND", 0,
	"DD", 0,
	"RD", 0,
	"RA", 0,
	"UD", 0,
	"IN", 0,
	"EX", 0,
	"SL", 0
);
my $cphash = \%child_hash;


##################################################
# Subprocess
# Write event to parent process
##################################################

sub HMCCU_CCURPC_Write ($$)
{
	my ($et, $msg) = @_;
	my $name = $hmccu_child->{devname};

	$cphash->{total}++;
	$cphash->{$et}++;

	HMCCU_QueueEnq ($cpqueue, $et."|".$msg);
}

##################################################
# Subprocess
# Start RPC server. Return 1 on success.
##################################################

sub HMCCU_CCURPC_OnRun ($)
{
	$hmccu_child = shift;
	my $name = $hmccu_child->{devname};
	my $serveraddr = $hmccu_child->{serveraddr};
	my $serverport = $hmccu_child->{serverport};
	my $callbackport = $hmccu_child->{callbackport};
	my $queuefile = $hmccu_child->{queue};
	my $clkey = "CB".$serverport;
	my $ccurpc_server;

# SUBPROCESS
	# Create, open and reset queue file
 	Log3 $name, 0, "CCURPC: $clkey Creating file queue $queuefile";
 	if (!HMCCU_QueueOpen ($cpqueue, $queuefile)) {
 		Log3 $name, 0, "CCURPC: $clkey Can't create queue";
 		return 0;
 	}

# SUBPROCESS	
	# Reset event queue
 	HMCCU_QueueReset ($cpqueue);
 	while (defined (HMCCU_QueueDeq ($cpqueue))) { }

	# Create RPC server
	Log3 $name, 0, "CCURPC: Initializing RPC server $clkey";
	$ccurpc_server = RPC::XML::Server->new (port=>$callbackport);
	if (!ref($ccurpc_server))
	{
		Log3 $name, 0, "CCURPC: Can't create RPC callback server on port $callbackport. Port in use?";
		return 0;
	}
	else {
		Log3 $name, 0, "CCURPC: Callback server created listening on port $callbackport";
	}
	
	# Callback for events
	Log3 $name, 1, "CCURPC: $clkey Adding callback for events";
	$ccurpc_server->add_method (
	   { name=>"event",
	     signature=> ["string string string string int","string string string string double","string string string string boolean","string string string string i4"],
	     code=>\&HMCCU_CCURPC_EventCB
	   }
	);

	# Callback for new devices
	Log3 $name, 1, "CCURPC: $clkey Adding callback for new devices";
	$ccurpc_server->add_method (
	   { name=>"newDevices",
	     signature=>["string string array"],
             code=>\&HMCCU_CCURPC_NewDevicesCB
	   }
	);

	# Callback for deleted devices
	Log3 $name, 1, "CCURPC: $clkey Adding callback for deleted devices";
	$ccurpc_server->add_method (
	   { name=>"deleteDevices",
	     signature=>["string string array"],
             code=>\&HMCCU_CCURPC_DeleteDevicesCB
	   }
	);

	# Callback for modified devices
	Log3 $name, 1, "CCURPC: $clkey Adding callback for modified devices";
	$ccurpc_server->add_method (
	   { name=>"updateDevice",
	     signature=>["string string string int"],
	     code=>\&HMCCU_CCURPC_UpdateDeviceCB
	   }
	);

	# Callback for replaced devices
	Log3 $name, 1, "CCURPC: $clkey Adding callback for replaced devices";
	$ccurpc_server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string string string"],
	     code=>\&HMCCU_CCURPC_ReplaceDeviceCB
	   }
	);

	# Callback for readded devices
	Log3 $name, 1, "CCURPC: $clkey Adding callback for readded devices";
	$ccurpc_server->add_method (
	   { name=>"replaceDevice",
	     signature=>["string string array"],
	     code=>\&HMCCU_CCURPC_ReaddDeviceCB
	   }
	);
	
	# Dummy implementation, always return an empty array
	Log3 $name, 1, "CCURPC: $clkey Adding callback for list devices";
	$ccurpc_server->add_method (
	   { name=>"listDevices",
	     signature=>["array string"],
	     code=>\&HMCCU_CCURPC_ListDevicesCB
	   }
	);

	# Callback for event queue query
	Log3 $name, 1, "CCURPC: $clkey Adding callback for event query";
	$ccurpc_server->add_method (
	   { name=>"getEvents",
	     signature=>["array string"],
	     code=>\&HMCCU_CCURPC_GetEventsCB
	   }
	);

	# Enter server loop
	HMCCU_CCURPC_Write ("SL", "$$|$clkey");

	Log3 $name, 0, "CCURPC: $clkey Entering server loop";
	$ccurpc_server->server_loop;
	Log3 $name, 0, "CCURPC: $clkey Server loop terminated";
	
	# Server loop exited by SIGINT
	HMCCU_CCURPC_Write ("EX", "SHUTDOWN|$$|$clkey");

	return 1;
}

##################################################
# Subprocess
# RPC server loop terminated
##################################################

sub HMCCU_CCURPC_OnExit ()
{
	# Output statistics
	foreach my $et (sort keys %child_hash) {
		Log3 $hmccu_child->{devname}, 2, "CCURPC: Eventcount $et = ".$cphash->{$et};
	}
}

##################################################
# Subprocess
# Callback for new devices
##################################################

sub HMCCU_CCURPC_NewDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $devcount = scalar (@$a);
	my $name = $hmccu_child->{devname};
	my $c = 0;
	my $msg = '';
	
	Log3 $name, 2, "CCURPC: $cb NewDevice received $devcount device specifications";	
	for my $dev (@$a) {
		HMCCU_CCURPC_Write ("ND", $dev->{ADDRESS}."|".$dev->{TYPE});
	}

	return;
}

##################################################
# Subprocess
# Callback for deleted devices
##################################################

sub HMCCU_CCURPC_DeleteDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $hmccu_child->{devname};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: $cb DeleteDevice received $devcount device addresses";
	for my $dev (@$a) {
		HMCCU_CCURPC_Write ("DD", $dev);
	}

	return;
}

##################################################
# Subprocess
# Callback for modified devices
##################################################

sub HMCCU_CCURPC_UpdateDeviceCB ($$$$)
{
	my ($server, $cb, $devid, $hint) = @_;
	
	HMCCU_CCURPC_Write ("UD", $devid."|".$hint);

	return;
}

##################################################
# Subprocess
# Callback for replaced devices
##################################################

sub HMCCU_CCURPC_ReplaceDeviceCB ($$$$)
{
	my ($server, $cb, $devid1, $devid2) = @_;
	
	HMCCU_CCURPC_Write ("RD", $devid1."|".$devid2);

	return;
}

##################################################
# Subprocess
# Callback for readded devices
##################################################

sub HMCCU_CCURPC_ReaddDevicesCB ($$$)
{
	my ($server, $cb, $a) = @_;
	my $name = $hmccu_child->{devname};
	my $devcount = scalar (@$a);
	
	Log3 $name, 2, "CCURPC: $cb ReaddDevice received $devcount device addresses";
	for my $dev (@$a) {
		HMCCU_CCURPC_Write ("RA", $dev);
	}

	return;
}

##################################################
# Subprocess
# Callback for handling CCU events
##################################################

sub HMCCU_CCURPC_EventCB ($$$$$)
{
	my ($server, $cb, $devid, $attr, $val) = @_;
	my $name = $hmccu_child->{devname};
	
	HMCCU_CCURPC_Write ("EV", $devid."|".$attr."|".$val);
	if (($cphash->{EV} % 500) == 0) {
		Log3 $name, 3, "CCURPC: $cb Received 500 events from CCU since last check";
		my @stkeys = ('total', 'EV', 'ND', 'DD', 'RD', 'RA', 'UD', 'IN', 'SL', 'EX');
		my $msg = '';
		foreach my $stkey (@stkeys) {
			$msg .= '|' if ($msg ne '');
			$msg .= $cphash->{$stkey};
		}
		HMCCU_CCURPC_Write ("ST", $msg);
	}

	# Never remove this statement!
	return;
}

##################################################
# Subprocess
# Callback for list devices
##################################################

sub HMCCU_CCURPC_ListDevicesCB ($$)
{
	my ($server, $cb) = @_;
	my $name = $hmccu_child->{devname};
	
	$cb = "unknown" if (!defined ($cb));
	Log3 $name, 1, "CCURPC: $cb ListDevices. Sending init to HMCCU";
	HMCCU_CCURPC_Write ("IN", "INIT|1|$cb");

	return RPC::XML::array->new();
}

##################################################
# Subprocess
# Callback for event query
##################################################

sub HMCCU_CCURPC_GetEventsCB ($$)
{
	my ($server, $cb) = @_;
	my @result;
	my $name = $hmccu_child->{devname};
	
	$cb = "unknown" if (!defined ($cb));
	Log3 $name, 1, "CCURPC: $cb GetEvents";

	return undef;
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
   additional Perl modules IO::File, RPC::XML::Client, RPC::XML::Server and SubProcess
   (part of FHEM).
   </br></br>
   <a name="HMCCUdefine"></a>
   <b>Define</b><br/><br/>
   <ul>
      <code>define &lt;name&gt; HMCCU &lt;HostOrIP&gt;</code>
      <br/><br/>
      Example:<br/>
      <code>define myccu HMCCU 192.168.1.10</code>
      <br/><br/>
      The parameter <i>HostOrIP</i> is the hostname or IP address of a Homematic CCU2.
      <br/>
      For automatic update of Homematic device datapoints and FHEM readings one have to:
      <br/><br/>
      <ul>
      <li>Define used RPC interfaces with attribute 'rpcinterfaces'</li>
      <li>Start RPC servers with command 'set rpcserver on'</li>
      <li>Optionally enable automatic start of RPC servers with attribute 'rpcserver'</li>
      </ul><br/>
      Than start with the definition of client devices using modules HMCCUDEV (CCU devices)
      and HMCCUCHN (CCU channels).<br/>
      Maybe it's helpful to set the following FHEM standard attributes for the HMCCU I/O
      device:<br/><br/>
      <ul>
      <li>Shortcut for RPC server control: eventMap /rpcserver on:on/rpcserver off:off/</li>
      <li>Show RPC server and I/O device state: stateFormat rpcstate/state</li> 
      </ul>
   </ul>
   <br/>
   
   <a name="HMCCUset"></a>
   <b>Set</b><br/><br/>
   <ul>
		<li><b>set &lt;name&gt; cleardefaults</b><br/>
			Clear default attributes imported from file.
		</li><br/>
		<li><b>set &lt;name&gt; defaults</b><br/>
		   Set default attributes for I/O device.
		</li><br/>
      <li><b>set &lt;name&gt; execute &lt;program&gt;</b><br/>
         Execute a CCU program.
         <br/><br/>
         Example:<br/>
         <code>set d_ccu execute PR-TEST</code>
      </li><br/>
      <li><b>set &lt;name&gt; hmscript &lt;script-file&gt; [dump] [&lt;parname&gt;=&lt;value&gt; 
         [...]]</b><br/>
         Execute Homematic script on CCU. If script code contains parameter in format $parname
         they are substituted by corresponding command line parameters <i>parname</i>.<br/>
         If output of script contains lines in format Object=Value readings in existing
         corresponding FHEM devices will be set. <i>Object</i> can be the name of a CCU system
         variable or a valid channel and datapoint specification. Readings for system variables
         are set in the I/O device. Datapoint related readings are set in client devices. If option
         'dump' is specified the result of script execution is displayed in FHEM web interface.
      </li><br/>
      <li><b>set &lt;name&gt; importdefaults &lt;filename&gt;</b><br/>
      	Import default attributes from file.
      </li><br/>
      <li><b>set &lt;name&gt; rpcserver {on | off | restart}</b><br/>
         Start, stop or restart RPC server(s). This command executed with option 'on'
         will fork a RPC server process for each RPC interface defined in attribute 'rpcinterfaces'.
         Until operation is completed only a few set/get commands are available and you
         may get the error message 'CCU busy'.
      </li><br/>
      <li><b>set &lt;name&gt; var &lt;variable&gt; &lt;Value&gt; [...]</b><br/>
        Set CCU system variable value. Special characters \_ in <i>value</i> are
        substituted by blanks.
      </li>
   </ul>
   <br/>
   
   <a name="HMCCUget"></a>
   <b>Get</b><br/><br/>
   <ul>
      <li><b>get &lt;name&gt; aggregation {&lt;rule&gt;|all}</b><br/>
      	Process aggregation rule defined with attribute ccuaggregation.
      </li><br/>
      <li><b>get &lt;name&gt; configdesc {&lt;device&gt;|&lt;channel&gt;}</b><br/>
         Get configuration parameter description of CCU device or channel (similar
         to device settings in CCU). Not every CCU device or channel provides a configuration
         parameter description. So result may be empty.
      </li><br/>
      <li><b>get &lt;name&gt; defaults</b><br/>
      	List device types and channels with default attributes available.
      </li><br/>
      <li><b>get &lt;name&gt; deviceinfo &lt;device-name&gt; [{State | <u>Value</u>}]</b><br/>
         List device channels and datapoints. If option 'State' is specified the device is
         queried directly. Otherwise device information from CCU is listed.
      </li><br/>
      <li><b>get &lt;name&gt; devicelist [dump]</b><br/>
         Read list of devices and channels from CCU. This command is executed automatically
         after the definition of an I/O device. It must be executed manually after
         module HMCCU is reloaded or after devices have changed in CCU (added, removed or
         renamed). With option 'dump' devices are displayed in browser window. If a RPC
         server is running HMCCU will raise events "<i>count</i> devices added in CCU" or
         "<i>count</i> devices deleted in CCU". It's recommended to set up a notification
         which reacts with execution of command 'get devicelist' on these events.
      </li><br/>
      <li><b>get &lt;name&gt; devicelist create &lt;devexp&gt; [t={chn|<u>dev</u>|all}]
      	[p=&lt;prefix&gt;] [s=&lt;suffix&gt;] [f=&lt;format&gt;] [defattr] 
      	[&lt;attr&gt;=&lt;value&gt; [...]]</b><br/>
         With option 'create' HMCCU will automatically create client devices for all CCU devices
         and channels matching specified regular expression. With option t=chn or t=dev (default) 
         the creation of devices is limited to CCU channels or devices.<br/>
         Optionally a <i>prefix</i> and/or a
         <i>suffix</i> for the FHEM device name can be specified. The parameter <i>format</i>
         defines a template for the FHEM device names. Prefix, suffix and format can contain
         format identifiers which are substituted by corresponding values of the CCU device or
         channel: %n = CCU object name (channel or device), %d = CCU device name, %a = CCU address.
         In addition a list of default attributes for the created client devices can be specified.
         If option 'defattr' is specified HMCCU tries to set default attributes for device.
      </li><br/>
      <li><b>get &lt;name&gt; dump {datapoints|devtypes} [&lt;filter&gt;]</b><br/>
      	Dump all Homematic devicetypes or all devices including datapoints currently
      	defined in FHEM.
      </li><br/>
      <li><b>get &lt;name&gt; exportdefaults &lt;filename&gt;</b><br/>
      	Export default attributes into file.
      </li><br/>
      <li><b>get &lt;name&gt; parfile [&lt;parfile&gt;]</b><br/>
         Get values of all channels / datapoints specified in <i>parfile</i>. The parameter
         <i>parfile</i> can also be defined as an attribute. The file must contain one channel /
         datapoint definition per line. Datapoints are optional. The channel definition
         can be followed by a list of string substitution rules for datapoint values.
         <br/><br/>
         The syntax of Parfile entries is:
         <br/><br/>
         {[&lt;interface&gt;.]&lt;channel-address&gt;[.&lt;datapoint-expr&gt;] |
         &lt;channel-name&gt;[.&lt;datapoint-expr&gt;]} &lt;regexp&gt;:&lt;subsstr&gt;[,...]
         <br/><br/>
         Empty lines or lines starting with a # are ignored.
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
      <li><b>ccuackstate {0 | <u>1</u>}</b><br/>
         If set to 1 state will be set to result of command (i.e. 'OK').
      </li><br/>
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
      	</ul><br/>
      	Aggregation results will be stored in readings <i>prefix</i>count, <i>prefix</i>
      	list, <i>prefix</i>match and <i>prefix</i>state<br/><br/>
      	Example: Find open windows<br/>
      	name=lock,filter:type=^HM-Sec-SC.*,read:STATE,if:any=open,else:closed,prefix:lock_,coll:NAME!All windows closed<br/><br/>
      	Example: Find devices with low batteries<br/>
      	name=battery,filter:name=.*,read:(LOWBAT|LOW_BAT),if:any=yes,else:no,prefix:batt_,coll:NAME<br/>
      </li><br/>
      <li><b>ccudef-hmstatevals &lt;subst-rule[;...]&gt;</b><br/>
      	Set global rules for calculation of reading hmstate.
      </li><br/>
      <li><b>ccudef-readingfilter &lt;filter-rule[;...]&gt;</b><br/>
         Set global reading/datapoint filter. This filter is added to the filter specified by
         client device attribute 'ccureadingfilter'.
      </li><br/>
      <li><b>ccudef-readingformat {name | address | <u>datapoint</u> | namelc | addresslc |
		   datapointlc}</b><br/>
		   Set global reading format. This format is the default for all readings except readings
		   of virtual device groups.
		</li><br/>
      <li><b>ccudef-readingname &lt;old-readingname-expr&gt;:[+]&lt;new-readingname&gt;
         [;...]</b><br/>
         Set global rules for reading name substitution. These rules are added to the rules
         specified by client device attribute 'ccureadingname'.
      </li><br/>
      <li><b>ccudef-substitute &lt;subst-rule&gt;[;...]</b><br/>
         Set global substitution rules for datapoint value. These rules are added to the rules
         specified by client device attribute 'substitute'.
      </li><br/>
      <li><b>ccudefaults &lt;filename&gt;</b><br/>
      	Load default attributes for HMCCUCHN and HMCCUDEV devices from specified file. Best
      	practice for creating a custom default attribute file is by exporting predefined default
      	attributes from HMCCU with command 'get exportdefaults'.
      </li><br/>
      <li><b>ccuflags {extrpc, <u>intrpc</u>}</b><br/>
      	Control RPC server process and datapoint validation:<br/>
      	intrpc - Use internal RPC server instead of ccurpcd.pl. This is the default.<br/>
      	extrpc - Use ccurpcd.pl instead of internal RPC server (depricated)<br/>
      	dptnocheck - Do not check within set or get commands if datapoint is valid<br/>
      </li><br/>
      <li><b>ccuget {State | <u>Value</u>}</b><br/>
         Set read access method for CCU channel datapoints. Method 'State' is slower than
         'Value' because each request is sent to the device. With method 'Value' only CCU
         is queried. Default is 'Value'.
      </li><br/>
      <li><b>ccureadingformat {<u>name</u> | address | datapoint | namelc | addresslc |
       datapointlc}</b><br/>
        Format of reading names (channel name, channel address or channel number combined with
        datapoint). With suffix 'lc' reading names are lowercase. Default is 'name'.
      </li><br/>
      <li><b>ccureadings {0 | <u>1</u>}</b><br/>
         If set to 1 values read from CCU will be stored as readings. Otherwise output
         is displayed in browser window.
      </li><br/>
      <li><b>ccutrace {&lt;ccu-devname-exp&gt; | &lt;ccu-address-exp&gt;}</b><br/>
         Turn on trace mode for devices matching specified expression. Will write extended
         information into FHEM log (level 1). Deprecated. Use attribute 'ccuflags' in 
         client devices instead.
      </li><br/>
      <li><b>parfile &lt;filename&gt;</b><br/>
         Define parameter file for command 'get parfile'.
      </li><br/>
      <li><b>rpcinterfaces &lt;interface&gt;[,...]</b><br/>
   		Specify list of CCU RPC interfaces. HMCCU will register a RPC server for each interface.
   		Valid interfaces are:<br/><br/>
   		<ul>
   		<li>BidCos-Wired (Port 2000)</li>
   		<li>BidCos-RF (Port 2001)</li>
   		<li>Homegear (Port 2003)</li>
   		<li>HmIP (Port 2010)</li>
   		<li>VirtualDevice (Port 9292)</li>
   		</ul>
      </li><br/>
      <li><b>rpcinterval &lt;Seconds&gt;</b><br/>
         Specifiy how often RPC queue is read. Default is 5 seconds.
      </li><br/>
      <li><b>rpcport &lt;value[,...]&gt;</b><br/>
         Deprecated, use 'rpcinterfaces' instead. Specify list of RPC ports on CCU. Default is
         2001. Valid RPC ports are:<br/><br/>
         <ul>
         <li>2000 = Wired components</li>
         <li>2001 = BidCos-RF (wireless 868 MHz components with BidCos protocol)</li>
         <li>2003 = Homegear (experimental)</li>
         <li>2010 = HM-IP (wireless 868 MHz components with IPv6 protocol)</li>
         <li>9292 = CCU group devices (especially heating groups)</li>
         </ul>
      </li><br/>
      <li><b>rpcqueue &lt;queue-file&gt;</b><br/>
         Specify name of RPC queue file. This parameter is only a prefix (including the
         pathname) for the queue files with extension .idx and .dat. Default is
         /tmp/ccuqueue. If FHEM is running on a SD card it's recommended that the queue
         files are placed on a RAM disk.
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
      	one CCU is connected the resulting RPC server port is 5000+2001+(10*0) = 7001.
      </li><br/>
      <li><b>substitute &lt;subst-rule&gt;:&lt;substext&gt;[,...]</b><br/>
         Define substitions for datapoint values. Syntax of <i>subst-rule</i> is<br/><br/>
         [[&lt;channelno.&gt;]&lt;datapoint&gt;[,...]!]&lt;{#n1-m1|regexp1}&gt;:&lt;text1&gt;[,...]
         <br/>
         Substitutions for parfile values must be specified in parfiles.
      </li><br/>
      <li><b>stripchar &lt;character&gt;</b><br/>
         Strip the specified character from variable or device name in set commands. This
         is useful if a variable should be set in CCU using the reading with trailing colon.
      </li>
   </ul>
</ul>

=end html
=cut

